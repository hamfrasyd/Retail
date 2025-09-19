local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
 local lookup = {'Shaman-Elemental','Priest-Discipline','DemonHunter-Havoc','Unknown-Unknown','Priest-Holy','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Balance','Monk-Windwalker','Mage-Arcane','Shaman-Enhancement','Priest-Shadow','Paladin-Protection','Shaman-Restoration','Hunter-BeastMastery','Warrior-Fury','Warrior-Arms','Evoker-Preservation','Warrior-Protection','Druid-Restoration','Evoker-Devastation','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Hunter-Marksmanship','Paladin-Retribution','Monk-Brewmaster','Paladin-Holy','Monk-Mistweaver','Mage-Fire','DeathKnight-Unholy',}; local provider = {region='EU',realm='ShatteredHand',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adowyn:BAAALAADCgYIBgAAAA==.',Ag='Agathha:BAAALAADCgYICAAAAA==.',Ai='Aigent:BAAALAAECgcIDgAAAA==.',Ak='Akka:BAAALAAECgYIBgABLAAECggIEgABACcfAA==.',Al='Alastaire:BAAALAAECgcIDgABLAAFFAMIBQACAB8XAA==.Albina:BAAALAADCggICAAAAA==.Alisanos:BAAALAAECgMIAgAAAA==.Allqu:BAACLAAFFIEGAAIDAAIIpyTkCQDRAAADAAIIpyTkCQDRAAAsAAQKgRoAAgMACAjqJUMCAHIDAAMACAjqJUMCAHIDAAAA.',Am='Amfetamintj:BAAALAAECgMIAwAAAA==.Aminala:BAAALAADCggIEQAAAA==.',An='Analýs:BAAALAADCgYICgABLAAECgEIAQAEAAAAAQ==.Animugrill:BAAALAAECggIEgAAAA==.Antiles:BAAALAAECggICAAAAA==.Anyls:BAAALAAECgEIAQAAAQ==.',Ap='Apol:BAACLAAFFIEFAAMCAAMIHxeCAAC8AAACAAIIwB2CAAC8AAAFAAIIhAl1EgCgAAAsAAQKgR8AAwIACAgSJT0AAGcDAAIACAgMJT0AAGcDAAUAAghlIcJaALQAAAAA.Apoltwo:BAAALAAECgcIBwABLAAFFAMIBQACAB8XAA==.',Ar='Ariana:BAAALAAECgEIAQABLAAECgcIDAAEAAAAAA==.Arvalyn:BAAALAAECgIIAwAAAA==.',As='Asperientje:BAAALAAECgIIAwAAAA==.Astronoë:BAAALAAECgIIAQAAAA==.',Aw='Aweì:BAAALAAECggIBgAAAA==.',Ba='Badps:BAAALAAECgYIDAAAAA==.Bambus:BAABLAAECoEUAAIFAAgIhBKiIgDtAQAFAAgIhBKiIgDtAQAAAA==.Bandybosse:BAAALAADCggICAAAAA==.Baphomét:BAAALAADCgQIBAAAAA==.',Be='Belonika:BAABLAAECoEUAAIDAAgIAR/UFwCgAgADAAgIAR/UFwCgAgAAAA==.Berkley:BAAALAAECgIIAgAAAA==.Bertove:BAAALAAECgIIBAAAAA==.',Bi='Bieggagalis:BAAALAAECgMIAwAAAA==.Biggerknight:BAAALAADCggICAAAAA==.Bissenw:BAAALAAECgYICAAAAA==.',Bj='Björnet:BAAALAADCggICAAAAA==.',Bl='Bladè:BAACLAAFFIEHAAMGAAMIWB6JAgAtAQAGAAMIWB6JAgAtAQAHAAEIZBAvCgBJAAAsAAQKgRgABAYACAhyJW8EABMDAAYACAhyJW8EABMDAAcABgiuIjcGAFUCAAgAAQi9JKYQAGIAAAAA.Blaster:BAAALAAECgYICwAAAA==.Blindelle:BAAALAAECgYIDQAAAA==.Bläkas:BAAALAADCgYIBgAAAA==.Blåcola:BAAALAADCgYIBgABLAAECgUICAAEAAAAAA==.Blíndamonken:BAAALAAECgEIAQAAAA==.',Bo='Bokux:BAAALAAECgUICgAAAA==.Boldsamurai:BAAALAADCgIIAgAAAA==.Bonelocker:BAAALAADCggICAAAAA==.Boomieboomer:BAAALAADCggICAABLAAFFAMIBQACAB8XAA==.Bopcorn:BAAALAADCggIDAAAAA==.Bourumausu:BAAALAAECgEIAQAAAA==.Bowdown:BAAALAAFFAIIAwAAAA==.',Br='Brewy:BAAALAADCgUIBQAAAA==.Brimili:BAAALAADCggIGgAAAA==.Broederd:BAACLAAFFIEGAAIJAAIIfyEGBgDEAAAJAAIIfyEGBgDEAAAsAAQKgR8AAgkACAgiJdQCAFQDAAkACAgiJdQCAFQDAAAA.Broederh:BAAALAAECgYIBgAAAA==.Broederp:BAAALAAECgYICQAAAA==.Brotherchen:BAAALAAECggIBAAAAA==.Brundin:BAAALAAECgYIDAAAAA==.',Bu='Buka:BAAALAADCggIDwABLAAECggIHgABAJAkAA==.Bukibaek:BAAALAADCgMIAwABLAAECgUICAAEAAAAAA==.Buljongbörje:BAAALAAECgMIAwAAAA==.Burstski:BAAALAADCgcIAgAAAA==.Busen:BAAALAADCgUIDQABLAAECgQIBgAEAAAAAA==.Bushihouji:BAAALAAECgUIBQAAAA==.',By='Bysbly:BAAALAADCgIIAgABLAADCggICAAEAAAAAA==.',['Bó']='Bógéy:BAAALAAECgYICQAAAA==.',Ca='Caim:BAABLAAECoEaAAIKAAgIVSG1BgDJAgAKAAgIVSG1BgDJAgAAAA==.Catmeowuwu:BAAALAAECgYICAABLAAECggIEgAEAAAAAA==.Cattaleya:BAAALAAECggIBQAAAA==.',Ce='Celine:BAAALAADCgcIBwABLAAECgcIDAAEAAAAAA==.Ceradia:BAAALAADCgYIBgAAAA==.',Ch='Chrisduchamp:BAAALAADCgcIEQAAAA==.Chromatics:BAAALAAECgIIAgAAAA==.',Ci='Cinrae:BAAALAAECggIBgAAAA==.Citrondrake:BAAALAADCgUIBwAAAA==.',Cl='Claptrap:BAABLAAECoEVAAIKAAcISBm4DgAmAgAKAAcISBm4DgAmAgAAAA==.Clime:BAAALAAECgYIDgAAAA==.',Co='Coffe:BAAALAAECgYICwAAAA==.Coffepang:BAAALAAECgIIAgAAAA==.',Cr='Cresnt:BAAALAAECgUIBQAAAA==.Cromgall:BAAALAAECgYIEgAAAA==.Crúsherz:BAAALAAECgYIBwAAAA==.',Cz='Czarny:BAAALAADCggIDwAAAA==.',['Cá']='Cássándrá:BAAALAADCggICwAAAA==.',Da='Dabbedemon:BAAALAADCgcIBwAAAA==.Dabonkadonk:BAAALAAECggICAAAAA==.Dadneck:BAAALAAECgQIBQAAAA==.Dagege:BAAALAAECgQICAAAAA==.Darry:BAABLAAECoEWAAILAAcIuh05IwBRAgALAAcIuh05IwBRAgAAAA==.Dawnblood:BAAALAAECggIDwAAAA==.Dawnguard:BAAALAAECgYIDAAAAA==.Daymaan:BAAALAAECgYICAAAAA==.Dazz:BAAALAAECggICAAAAA==.',De='Deathblade:BAAALAAECgUIBQAAAA==.Degeneration:BAAALAAECgYIEAAAAA==.Demolordbill:BAAALAAECgIIAwAAAA==.Demonijuti:BAAALAADCggICAABLAAECgYIDAAEAAAAAA==.Demonrico:BAAALAADCgIIAgAAAA==.Demonsimon:BAAALAADCgcIBwAAAA==.Detílium:BAAALAAECgcIEQAAAA==.Dezzy:BAAALAADCgEIAgAAAA==.',Di='Diablofour:BAAALAADCggICwABLAAECgMIBQAEAAAAAA==.Dieseltåget:BAAALAADCggICAAAAA==.Diirectuur:BAABLAAECoEXAAIMAAgIABQ+BwAgAgAMAAgIABQ+BwAgAgAAAA==.Diplodokus:BAAALAAECgYICgABLAAECggIGgANAO0gAA==.Dirreprälle:BAAALAADCgcIBwAAAA==.',Dj='Dj:BAAALAAECgMIAwAAAA==.Djupfryst:BAAALAAECgYICgAAAA==.',Dk='Dkslund:BAAALAAECggIBwAAAA==.',Do='Dog:BAAALAAECgYIBgAAAA==.Dogcat:BAAALAADCggIDAAAAA==.Domanax:BAABLAAECoEfAAIOAAgIliR+AQBTAwAOAAgIliR+AQBTAwAAAA==.Donandzone:BAAALAAECgYICQAAAA==.Donder:BAAALAADCgcIBwAAAA==.Donical:BAAALAADCgcICAAAAA==.Doodoo:BAAALAAECgIIAgAAAA==.Doodvlees:BAAALAAECgYIDAAAAA==.Dostalie:BAAALAAECggICAABLAAECggIDAAEAAAAAA==.Dothia:BAAALAAECggIDAAAAA==.',Dr='Dragodilia:BAAALAADCgMIAgAAAA==.Drakirfan:BAAALAADCggIEAAAAA==.Drakpojken:BAAALAADCggIEAAAAA==.Dratos:BAACLAAFFIELAAMBAAUI9AxUAgCjAQABAAUI9AxUAgCjAQAPAAEIcgUhHwA/AAAsAAQKgSAAAwEACAgDIuIHABgDAAEACAgDIuIHABgDAA8AAQhHBl2rACkAAAAA.Drbomb:BAAALAADCggIDQAAAA==.Drekomelfoy:BAAALAAECgYICQAAAA==.Dreodin:BAAALAADCggIFwAAAA==.Dreoo:BAAALAADCggIEgAAAA==.Druidijuti:BAAALAAECgYIDAAAAA==.Drunkenpan:BAAALAADCgYIBgABLAAFFAMIBQACAB8XAA==.',Du='Dunkabäver:BAAALAAECgcIBwAAAA==.',Dz='Dzk:BAACLAAFFIENAAIDAAUIGRrJAQDXAQADAAUIGRrJAQDXAQAsAAQKgSAAAgMACAj6JfkBAHYDAAMACAj6JfkBAHYDAAAA.',['Dâ']='Dântë:BAAALAAECgQICAAAAA==.',['Dö']='Dödbochlin:BAAALAAECgYIEgAAAA==.',Ee='Eesmee:BAAALAAECgIIAwAAAA==.',El='Elchoco:BAAALAAECgIIAQAAAA==.Eleévampiro:BAAALAAECgYIBgAAAA==.Eluciaa:BAAALAAECgUICgAAAA==.',En='Enbajermere:BAAALAADCgYIBgABLAAECgUICAAEAAAAAA==.Engage:BAAALAAECgQIBAABLAAECgYICwAEAAAAAA==.',Er='Eriathe:BAAALAADCgcICwAAAA==.Erurururu:BAAALAADCgMIAwABLAAFFAMIBQACAB8XAA==.Erzaxd:BAACLAAFFIENAAIQAAUIuCQzAAAYAgAQAAUIuCQzAAAYAgAsAAQKgR0AAhAACAggJuIAAH0DABAACAggJuIAAH0DAAAA.',Es='Esha:BAAALAADCgUIBQABLAAECgcIDAAEAAAAAA==.Esimola:BAAALAAECgYIDwAAAA==.',Et='Etríi:BAACLAAFFIEMAAILAAUI2R6QAQD4AQALAAUI2R6QAQD4AQAsAAQKgSAAAgsACAirJXsBAHEDAAsACAirJXsBAHEDAAAA.Ettanlöös:BAAALAADCgYIBwABLAADCgcIBwAEAAAAAA==.',Ev='Evanorah:BAAALAADCggIGQAAAA==.Evildana:BAAALAADCgIIAgAAAA==.',Ew='Ewpala:BAAALAADCggICAAAAA==.',Ey='Eyeless:BAABLAAECoEWAAIRAAYIFx5jJgDrAQARAAYIFx5jJgDrAQAAAA==.Eyybro:BAAALAADCgcIBwAAAA==.',Fa='Faabb:BAAALAADCgIIBAABLAAECgYIBwAEAAAAAA==.Faabdk:BAAALAADCggIDwABLAAECgYIBwAEAAAAAA==.Faabhl:BAAALAADCgIIAwABLAAECgYIBwAEAAAAAA==.Faabulousa:BAAALAAECgYIBwAAAA==.',Fe='Fengbaolieji:BAAALAADCggIEAAAAA==.',Fl='Flavus:BAAALAAECgQIBgAAAA==.Flingsabolt:BAAALAAECgYIBQAAAA==.Flyingdan:BAAALAADCgYIBgABLAAFFAMIBQACAB8XAA==.',Fo='Forcedtobrew:BAAALAADCgcIDAAAAA==.Forcedtolock:BAAALAAECggICAAAAA==.Fourfivesix:BAAALAAECgUIBQAAAA==.',Fr='Fragsteals:BAAALAADCgcIBwAAAA==.Freakmode:BAAALAADCggICAAAAA==.Friskydingo:BAAALAAECgIIAgABLAAECgYICAAEAAAAAA==.Frozensoul:BAAALAAECgcIBQAAAA==.Fruåkesson:BAAALAADCgMIAwAAAA==.Frèdsmäklarn:BAAALAADCgcIDgAAAA==.',Fu='Fulastnamn:BAAALAADCgMIAwABLAAECgEIAQAEAAAAAQ==.Fullutill:BAAALAAECgYICAAAAA==.',Ga='Gaauude:BAAALAAECgMICQAAAA==.Gallager:BAAALAAECgYIBgAAAA==.Gamashdra:BAAALAADCgUIBAAAAA==.',Ge='Gengbang:BAAALAAECggIBwABLAAFFAMIBwAGAFgeAA==.Geregerina:BAAALAADCggIEAAAAA==.',Gf='Gfx:BAAALAAECgYIEAAAAA==.',Gh='Ghandelf:BAABLAAECoEZAAIRAAgINSAfCgD/AgARAAgINSAfCgD/AgAAAA==.Ghanoush:BAABLAAECoEgAAILAAgI5xz6FAC3AgALAAgI5xz6FAC3AgAAAA==.',Gl='Glau:BAAALAADCggIFAAAAA==.Gleenn:BAAALAAECgYIDAAAAA==.',Go='Gordonlool:BAACLAAFFIEFAAMSAAMIEBYfAQCxAAARAAMIMwt9BwDwAAASAAII+BUfAQCxAAAsAAQKgR4AAxIACAhYJNYBAOwCABIABwjhI9YBAOwCABEACAhLIR8OAMwCAAAA.Gorganega:BAAALAAECgEIAQAAAA==.Gormarz:BAAALAADCgYIBgAAAA==.Gosser:BAAALAAECgcIDwAAAA==.',Gr='Grandmagolga:BAAALAAECgUIBwAAAA==.Grimaniel:BAABLAAFFIEKAAITAAUICyVtAAAtAgATAAUICyVtAAAtAgAAAA==.Grubbysaurus:BAAALAADCgYIBgABLAADCggICAAEAAAAAA==.Grymheten:BAABLAAECoEcAAMUAAgIqiLFBAD1AgAUAAgIqiLFBAD1AgARAAEIPgoabgA9AAAAAA==.Grymlee:BAAALAADCgEIAQAAAA==.Grønbajer:BAAALAAECgUICAAAAA==.',Gu='Guilia:BAAALAAECgQIBAAAAA==.Guldash:BAAALAADCgcIDQAAAA==.Guldglavies:BAAALAAECgIIAgAAAA==.',Gw='Gwweezzy:BAAALAADCgcIBwAAAA==.',['Gá']='Gámazh:BAAALAADCgYIBgAAAA==.',Ha='Habanero:BAAALAAECggICAAAAA==.Halersa:BAAALAAECgcIBwAAAA==.Hamsarny:BAAALAADCggIDgAAAA==.Hargu:BAAALAADCgUIBQABLAAECggIFwAVAMAXAA==.Harrier:BAAALAAECgYIEgAAAA==.Hatelast:BAAALAADCggIEAAAAA==.Hathat:BAAALAADCggICAAAAA==.Hauntonio:BAAALAADCgEIAQAAAA==.',He='Heinekenpils:BAAALAAECgYICgAAAA==.Hellyse:BAAALAADCggICAAAAA==.Helstyve:BAAALAADCgcIBwAAAA==.Herrorch:BAAALAADCgcIBwAAAA==.Hexel:BAABLAAECoEUAAIQAAcIIw+1OwCbAQAQAAcIIw+1OwCbAQAAAA==.',Hi='Hingrim:BAABLAAECoEYAAIPAAgIqiC0CADIAgAPAAgIqiC0CADIAgAAAA==.',Ho='Holyrehab:BAAALAADCggIEgAAAA==.Honglian:BAAALAAECgUIBQAAAA==.Horn:BAAALAAECgYICwAAAA==.Horpasta:BAAALAAECggIEAAAAA==.Horukar:BAAALAAECgUICQAAAA==.',Hu='Huberto:BAAALAADCgcICAAAAA==.Hullukroko:BAAALAADCggIDQABLAAFFAMIBQAWAFsjAA==.Hunterbetsy:BAAALAADCggICAAAAA==.Huvudjägaren:BAAALAAECgcIEAAAAA==.',Hy='Hypon:BAAALAAECggIEAAAAA==.',Ia='Iamhated:BAAALAAECgUIBgAAAA==.',Il='Ilostmybible:BAAALAAECgEIAQAAAA==.Ilovecake:BAAALAAECgQIBQAAAA==.Ilovecider:BAAALAAECgQIBwAAAA==.Ilovecream:BAAALAADCgEIAQAAAA==.',In='Incineroar:BAAALAAECgUIBQAAAA==.Insains:BAAALAAECgIIAwAAAA==.Insulinpimp:BAAALAAECgYICwAAAA==.Integraal:BAAALAAECggIAQAAAA==.Integralevo:BAAALAAECgMIAwAAAA==.',Io='Io:BAAALAADCggIDgAAAA==.',Ir='Ironicdream:BAAALAADCgEIAQAAAA==.',Is='Isbel:BAAALAADCgYIBgAAAA==.',Iz='Izuwar:BAAALAADCggICAAAAA==.Izy:BAAALAAECggIBwAAAA==.',Ja='Jagerhorn:BAAALAADCgIIAgAAAA==.Jalapeño:BAAALAADCgYIBgAAAA==.',Je='Jejjen:BAABLAAECoEcAAMPAAgI3R8bCgC4AgAPAAgI3R8bCgC4AgABAAYIcQ4mOgB6AQAAAA==.Jelak:BAABLAAECoEMAAIRAAYI0Qn0RwAgAQARAAYI0Qn0RwAgAQAAAA==.',Ji='Jinthaiiya:BAAALAAECggICAABLAAFFAUIDQAQALgkAA==.',Ju='Junsu:BAACLAAFFIELAAMXAAUIPw+YBABaAQAXAAQIKwyYBABaAQAYAAIIYw+dCgCcAAAsAAQKgSAABBcACAizISQLAO8CABcACAh1ICQLAO8CABkABwjEFNwHAP0BABgAAwhqGsZBANYAAAAA.',Ka='Kafka:BAACLAAFFIEIAAIQAAMISBdGBAAAAQAQAAMISBdGBAAAAQAsAAQKgRUAAxAACAgCJdEEADoDABAACAgCJdEEADoDABoABAicFmdPAMQAAAAA.Kafká:BAAALAAECgYIDAABLAAFFAMICAAQAEgXAA==.Kanel:BAAALAADCgQIBAAAAA==.Kaptenkoks:BAAALAAECgYIBgABLAAECggIEAAEAAAAAA==.Kasdbau:BAAALAAECgYIBgAAAA==.Katsoja:BAAALAADCgcIBwAAAA==.Kayn:BAAALAADCgYIBgAAAA==.',Ke='Kenney:BAAALAADCgUIBQAAAA==.',Ki='Killforjoyx:BAAALAADCgEIAQAAAA==.Kishimojin:BAAALAADCgcIBwAAAA==.Kittania:BAAALAADCgcIEQAAAA==.Kivahdru:BAAALAADCggIFgAAAA==.',Kl='Klajjen:BAAALAAECgYICAAAAA==.Klappträet:BAAALAADCggICAAAAA==.Klippsigne:BAAALAADCggICAAAAA==.Kluddkrig:BAAALAAECgYIEgAAAA==.',Kr='Kravojedna:BAAALAAECgMIAwAAAA==.Kronk:BAABLAAECoEgAAIRAAgIFCJPBgAtAwARAAgIFCJPBgAtAwAAAA==.Krothar:BAAALAAECgYICAAAAA==.Krox:BAAALAAECgYIDwAAAA==.',Ku='Kunidrood:BAAALAADCgUIBQABLAAECgIIAwAEAAAAAA==.Kunigunde:BAAALAADCggIEQABLAAECgIIAwAEAAAAAA==.Kurojaki:BAAALAADCggICAAAAA==.',['Kä']='Käc:BAAALAADCgcICwAAAA==.',La='Lanadrah:BAAALAADCgYIBgAAAA==.Laserpeder:BAAALAADCgcIBwAAAA==.Latte:BAAALAADCggICAAAAA==.',Ld='Ldcola:BAAALAAECgEIAQAAAA==.',Le='Legoatjames:BAAALAADCggICQAAAA==.Lerkish:BAAALAADCggIEAAAAA==.',Li='Lichborne:BAAALAAECgEIAQAAAA==.Licifur:BAAALAADCgIIAgABLAADCggICAAEAAAAAA==.Lightweightb:BAAALAAECgcIDQAAAA==.Lildisco:BAABLAAECoEXAAIUAAcInBfkFADSAQAUAAcInBfkFADSAQAAAA==.Lillsprätten:BAAALAADCgIIAgAAAA==.Litlehealz:BAAALAAECgQIBAAAAA==.Liukuvoide:BAAALAAECgYICAABLAAECggIHQATAMIYAA==.',Lo='Lockenstein:BAAALAADCggICAAAAA==.Lockmo:BAABLAAECoEgAAMYAAgIGxTNGwC2AQAXAAgI5g8EKQDwAQAYAAYI/RXNGwC2AQAAAA==.Logo:BAAALAADCgEIAQAAAA==.Lokje:BAAALAADCggIEAAAAA==.Loktaí:BAAALAAFFAIIAgAAAA==.Lorith:BAAALAADCgcICwAAAA==.Love:BAAALAAECgMIBQAAAA==.',Lu='Luderlinus:BAAALAAFFAIIAgAAAA==.Ludovik:BAABLAAECoEhAAIbAAgI9iWfAgBvAwAbAAgI9iWfAgBvAwAAAA==.',Ly='Lyxrunka:BAAALAADCgIIAgAAAA==.',['Læ']='Læknishöggr:BAAALAAECgIIAwAAAA==.',Ma='Maangon:BAAALAAECgYIBwABLAAECggICAAEAAAAAA==.Magecob:BAAALAAECgIIAwAAAA==.Magepiben:BAAALAADCgYIBgAAAA==.Magfury:BAAALAAECgYICQAAAA==.Magimannjen:BAAALAAECgQIBAAAAA==.Maglati:BAAALAAECgYICwABLAAFFAMIBQAWAFsjAA==.Magr:BAAALAAECgYIBgAAAA==.Magraun:BAAALAAECgUIBQAAAA==.Magruz:BAACLAAFFIELAAIBAAUImyIXAQARAgABAAUImyIXAQARAgAsAAQKgRQAAgEACAjxJe0FADMDAAEACAjxJe0FADMDAAAA.Maiwaifu:BAAALAAECgYICAAAAA==.Malandy:BAABLAAECoEgAAMYAAgIuSGPDgAkAgAYAAYIXxuPDgAkAgAXAAUI/R54LwDIAQAAAA==.Malaxiangguo:BAAALAAECgUIBQABLAAECgMIAwAEAAAAAA==.Mallak:BAAALAAECgcIDgABLAAFFAQIBgAcAJgYAA==.Mallako:BAACLAAFFIEGAAIcAAQImBisAQBQAQAcAAQImBisAQBQAQAsAAQKgRUAAhwACAjvIb4EANACABwACAjvIb4EANACAAAA.Maltog:BAAALAAECggICAAAAA==.Malzkar:BAAALAADCgcIDgAAAA==.Maradar:BAAALAADCgcIBwAAAA==.Marslonsen:BAAALAAECgYICwAAAA==.Mathasys:BAAALAAECgUIBQABLAAFFAIIAgAEAAAAAA==.Mav:BAAALAADCgMIAwAAAA==.',Me='Meek:BAAALAAECggICAAAAA==.Mekd:BAAALAADCgYIBgAAAA==.Mekmonk:BAAALAADCgYIDAAAAA==.Mekro:BAAALAADCgYIDAAAAA==.Meksha:BAAALAAECgIIAgAAAA==.Mementomori:BAAALAADCggIEAAAAA==.Mesodragon:BAAALAADCggICAAAAA==.Meyer:BAABLAAECoEXAAIdAAcIAyKzBgCYAgAdAAcIAyKzBgCYAgAAAA==.',Mi='Miakis:BAAALAAECgYIEgAAAA==.Milenka:BAAALAAECgUIBQAAAA==.Mimta:BAAALAADCgYIBgAAAA==.Miniboss:BAAALAAECgYIDgAAAA==.Minimoo:BAAALAADCgYIBgAAAA==.Minipax:BAAALAADCggIEAAAAA==.Minipäx:BAAALAAECgMIBgAAAA==.Minmax:BAAALAAECgYIEgAAAA==.Mitch:BAAALAADCgQIBAAAAA==.Mitcho:BAAALAADCgYIBgAAAA==.',Mo='Mootilate:BAAALAAECggIEAAAAA==.Morrigane:BAAALAAECgUIBQAAAA==.Mortiferious:BAAALAAECgcIDAAAAA==.Moîsty:BAABLAAECoEVAAIDAAgItheeIQBXAgADAAgItheeIQBXAgAAAA==.',Mu='Muggipeepo:BAAALAADCgUIBQAAAA==.Muglati:BAAALAAECgYICgABLAAFFAMIBQAWAFsjAA==.Muklati:BAACLAAFFIEFAAIWAAMIWyMrAwA5AQAWAAMIWyMrAwA5AQAsAAQKgRsAAxYACAhqJPsCAD8DABYACAhqJPsCAD8DABMAAwhgFUAaAMQAAAAA.Munglati:BAAALAAECgcIEAABLAAFFAMIBQAWAFsjAA==.Munnad:BAAALAAECggICAAAAA==.',Mv='Mvoker:BAAALAAECgEIAQABLAAECgIIAgAEAAAAAA==.Mvuid:BAAALAAECgIIAgAAAA==.',My='Myspojken:BAAALAADCgIIAgAAAA==.',['Mà']='Màssive:BAAALAAECggIEAAAAA==.',['Má']='Mágemaster:BAABLAAECoEYAAILAAgIzxcxIQBfAgALAAgIzxcxIQBfAgAAAA==.',['Mä']='Mätäsäkki:BAAALAADCgUIBQABLAAECggIHQATAMIYAA==.',['Må']='Månsken:BAAALAADCgYIBAAAAA==.',['Mè']='Mèky:BAAALAADCgYIBgAAAA==.',['Mé']='Méeki:BAAALAADCgYIBgAAAA==.',Na='Narmaya:BAAALAADCgcIBwAAAA==.Narxia:BAABLAAECoEXAAMXAAcIjhcgIwAWAgAXAAcIjhcgIwAWAgAZAAYISxBIDQCRAQAAAA==.',Ne='Nerzhog:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.Netasi:BAAALAAECgIIAgAAAA==.Netrüassin:BAAALAAECggIDQAAAA==.Nevoh:BAABLAAECoEeAAMBAAgIkCQMBABOAwABAAgIkCQMBABOAwAPAAYIeQSpeADDAAAAAA==.',Ni='Nisty:BAAALAAECgMIAwAAAA==.',No='Nochlol:BAAALAAECgYICgAAAA==.Nochm:BAAALAADCggIEAAAAA==.Nocitum:BAAALAAECgYICgAAAA==.Notsoez:BAAALAAECgIIAwAAAA==.',Ob='Obscurion:BAAALAAECgIIAgAAAA==.',Og='Ogrox:BAAALAADCgYIBgAAAA==.',Ol='Ollonet:BAAALAAECgYICgAAAA==.',On='Onepushman:BAAALAADCgEIAQAAAA==.',Oo='Oomkin:BAAALAAECgYICQAAAA==.',Or='Orchellscrem:BAAALAADCgQIBAAAAA==.Orientkungen:BAAALAAECgIIAgAAAA==.',Ov='Ovoid:BAAALAAECgMIAwAAAA==.',Ow='Owlthar:BAABLAAECoEZAAIJAAgIiR+2EwBLAgAJAAgIiR+2EwBLAgAAAA==.',Oz='Ozzeline:BAAALAAECgQICAAAAA==.Ozzypie:BAAALAADCggIEAAAAA==.',Pa='Pajotter:BAAALAAECgYIEgAAAA==.Pallymaddy:BAAALAAECgYIDAAAAA==.Pampen:BAAALAAECgYICgAAAA==.Panzárr:BAAALAADCggIDwAAAA==.Paranato:BAAALAADCgYIBgAAAA==.Patomouno:BAAALAAECgMIAwAAAA==.Payens:BAAALAADCggICAAAAA==.',Pe='Peakmonk:BAABLAAECoEgAAIeAAgIjSIqAgAgAwAeAAgIjSIqAgAgAwAAAA==.Peakshamx:BAAALAAECgIIAgABLAAECggIIAAeAI0iAA==.Pencshaman:BAAALAADCgEIAQAAAA==.Pentaxz:BAAALAADCggIFgAAAA==.Permo:BAAALAADCggIEQAAAA==.Petrollo:BAAALAADCggICAAAAA==.',Ph='Phil:BAAALAAECgcIEgAAAA==.',Pi='Piben:BAAALAAECgIIAgAAAA==.Pirågen:BAAALAAFFAIIBAAAAA==.',Pl='Pluppsy:BAAALAADCgYIBgAAAA==.',Pr='Proppendone:BAAALAAECgUIBQAAAA==.Protar:BAAALAADCgYICgAAAA==.Protezy:BAAALAAECgIIAgAAAA==.Provectus:BAAALAADCgcIDgAAAA==.Prästsnus:BAAALAAECgYIDwAAAA==.',Pu='Pumping:BAAALAADCggICAAAAA==.',['Pä']='Päran:BAAALAADCgYIBwABLAAECgEIAQAEAAAAAQ==.Pääran:BAAALAADCgEIAQABLAAECgEIAQAEAAAAAQ==.',['Pë']='Pëntägona:BAAALAAECgUIBQAAAA==.',Ql='Qlerq:BAAALAADCgMIAwAAAA==.',Qu='Quartier:BAAALAAECgMIAwAAAA==.Queei:BAAALAADCgEIAQAAAA==.Qutale:BAAALAADCgcICgAAAA==.',Ra='Rainbow:BAAALAADCgYIBgABLAADCggIEQAEAAAAAA==.Rallysebbe:BAAALAADCgcIBwAAAA==.Rax:BAAALAAECggICAAAAA==.Razamonk:BAAALAADCgcIDAAAAA==.Razawar:BAACLAAFFIENAAMRAAUI6CDFAAATAgARAAUI6CDFAAATAgASAAEItA8OBABNAAAsAAQKgSAAAxEACAiEIw0HACQDABEACAgsIg0HACQDABIAAgjGH9oWALYAAAAA.Razdh:BAAALAAECgIIAgAAAA==.Razot:BAAALAAECgYICwAAAA==.',Rd='Rdx:BAAALAAECgYIBwAAAA==.',Re='Reaverz:BAAALAADCgEIAQAAAA==.Redbaxter:BAAALAADCggIEAAAAA==.Reeyuru:BAABLAAECoEZAAIDAAgI3iB6DwDoAgADAAgI3iB6DwDoAgAAAA==.Renew:BAAALAADCgQIBAAAAA==.Restoshaman:BAAALAAECgYIDQAAAA==.Reynad:BAAALAADCggIDwAAAA==.',Rh='Rhaenah:BAAALAAECgYIDAAAAA==.Rháegar:BAAALAAECgYICgAAAA==.',Ri='Richiee:BAAALAAECgEIAQAAAA==.Riias:BAAALAAECgcIEAAAAA==.Riiza:BAAALAAECggIEAAAAA==.Rillastin:BAAALAAECgUIBgAAAA==.Ritselblad:BAAALAADCgEIAQABLAAECgYIBwAEAAAAAA==.Rivyn:BAAALAADCgcICAAAAA==.',Ro='Robusta:BAAALAAECgYICAAAAA==.Rofrof:BAAALAADCgYICwAAAA==.Roguden:BAAALAADCgUIBQABLAAECgYICgAEAAAAAA==.Rokza:BAAALAAECgEIAQABLAAECgYICgAEAAAAAA==.Roswal:BAAALAADCggICAAAAA==.',Rs='Rsdendra:BAABLAAFFIEGAAIVAAIITiTTBwC9AAAVAAIITiTTBwC9AAAAAA==.',Ru='Runmakkerun:BAAALAAECgUIDgAAAA==.',Ry='Ryudo:BAABLAAECoEWAAMLAAgIhgxVPwDAAQALAAgIhgxVPwDAAQAfAAMIEgVvDgBiAAAAAA==.Ryzz:BAAALAAECgMIAwAAAA==.',['Rä']='Räger:BAAALAAECgYICAAAAA==.Rääpan:BAAALAADCgEIAQAAAA==.',Sa='Saikotic:BAAALAAECgcIDQAAAA==.Saimonk:BAAALAAECgYIEgAAAA==.Saleon:BAABLAAECoEYAAMGAAYI4B/tEwAtAgAGAAYI4B/tEwAtAgAHAAII5Rb8IACDAAAAAA==.Sam:BAAALAAECgIIAgABLAAECgQIBgAEAAAAAA==.Samabow:BAAALAAECgYIDwAAAA==.Samabu:BAAALAADCggIFAAAAA==.Samastab:BAAALAADCgMIAwAAAA==.Samd:BAAALAAECgMIAwABLAAECgQIBgAEAAAAAA==.Samoatrakia:BAAALAAECggICAAAAA==.Samw:BAAALAAECgQIBgAAAA==.',Sc='Scaly:BAAALAAECgMIAwAAAA==.Scarïty:BAAALAAECgIIAgAAAA==.Schaap:BAAALAADCgYIBgAAAA==.Schütze:BAAALAADCgQIBAAAAA==.Scrotul:BAAALAADCggICgAAAA==.Scrotus:BAAALAAECgMIBgAAAA==.',Se='Sedrae:BAAALAAECgUIBQAAAA==.Selvitia:BAAALAAECgUICAAAAA==.Sent:BAAALAADCgYIBgABLAAECgcIDQAEAAAAAA==.',Sh='Shandril:BAAALAAECgQIBQAAAA==.Shango:BAAALAAECgYIDAAAAA==.Shantal:BAAALAADCggICAAAAA==.Shanyhe:BAAALAAECgYIBQAAAA==.Sharkbait:BAAALAAECgUIBgAAAA==.Shrid:BAAALAAECgQIDAAAAA==.',Si='Sicozz:BAAALAADCggIEAAAAA==.Siitoin:BAABLAAECoESAAIBAAgIJx8cEACsAgABAAgIJx8cEACsAgAAAA==.Sildorai:BAAALAADCgMIBQAAAA==.Siniava:BAAALAAECgYIEgAAAA==.',Sk='Skarhex:BAAALAADCgMIBAAAAA==.Skilava:BAAALAADCgIIAgAAAA==.Skrall:BAAALAAECgYIBgAAAA==.',Sl='Slamjamsham:BAAALAADCgMIAwABLAAECgMIBQAEAAAAAA==.Slavjonas:BAAALAADCggIDgAAAA==.Sleddish:BAAALAAECggICAAAAA==.Slund:BAAALAAECgIIAgAAAA==.',Sm='Smaashy:BAAALAADCgIIAgAAAA==.Smäigel:BAAALAADCggICAAAAA==.',Sn='Sneaks:BAAALAADCgIIAgAAAA==.Sneakyreafer:BAACLAAFFIEFAAMGAAMI/A7KBAAFAQAGAAMI/A7KBAAFAQAHAAEI1gGVCgBHAAAsAAQKgR8AAwYACAioIS0GAPICAAYACAjiIC0GAPICAAcAAQjBG6glAE8AAAAA.',So='Sodomisten:BAAALAADCgQIBAAAAA==.Soetblomman:BAABLAAECoEcAAIbAAgI2yZoAACYAwAbAAgI2yZoAACYAwAAAA==.Soliana:BAAALAAECgcIDAAAAA==.Somatotropin:BAAALAADCgEIAQAAAA==.',Sp='Sparwen:BAAALAAECgYIBgABLAAECggIEAAEAAAAAA==.Spicey:BAAALAAECgEIAQAAAA==.Spirogyra:BAABLAAECoEgAAIbAAgINSJtCQAmAwAbAAgINSJtCQAmAwAAAA==.Splortasus:BAAALAAECgYICgAAAA==.Spòónéd:BAABLAAFFIEFAAIVAAIIoBT1CwCdAAAVAAIIoBT1CwCdAAAAAA==.',St='Staabster:BAAALAADCgcIBwAAAA==.Stagafists:BAAALAAECgYIDAAAAA==.Stargazër:BAAALAADCgcIBAAAAA==.Stonewaller:BAAALAADCggIDwAAAA==.Stormbläst:BAAALAAECgMIAwAAAA==.Stresskeeper:BAAALAADCggIFAAAAA==.Styxsjr:BAAALAADCggIFwAAAA==.',Su='Sumtinwon:BAABLAAECoEWAAIeAAgIZAbJHwAKAQAeAAgIZAbJHwAKAQAAAA==.Surarexd:BAAALAAFFAIIBAAAAA==.',Sv='Svartzonker:BAAALAAECgcIDgAAAA==.Svennebanan:BAAALAADCgIIAgAAAA==.',Sw='Swinee:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.Swipe:BAAALAAECgYIDQAAAA==.',Sy='Synvilla:BAAALAAECgYIDwAAAA==.',['Sä']='Säkkimätä:BAABLAAECoEdAAITAAgIwhjEBQBwAgATAAgIwhjEBQBwAgAAAA==.',['Så']='Såsmargit:BAAALAAECgMIAwAAAA==.',['Sè']='Sèxýdh:BAAALAAECgYIDQAAAA==.',Ta='Taxidriver:BAAALAADCggIEgABLAAECgMIAwAEAAAAAA==.',Te='Tendri:BAABLAAECoEXAAIVAAgIwBf6GQACAgAVAAgIwBf6GQACAgAAAA==.Teqhealah:BAABLAAECoEgAAIBAAgIxiJ8BQA5AwABAAgIxiJ8BQA5AwAAAA==.',Th='Thiccmomma:BAABLAAECoEgAAIDAAgIyyEsFAC/AgADAAgIyyEsFAC/AgAAAA==.Thirshar:BAAALAAECggICgAAAA==.Thornflex:BAABLAAECoEgAAMRAAgIeCOuBABCAwARAAgIeCOuBABCAwAUAAEIehplQwBHAAAAAA==.Thornh:BAAALAAECgMIAwAAAA==.Threedeercow:BAAALAADCgcIDgABLAAECgMIAwAEAAAAAA==.',Ti='Tickleme:BAAALAADCggIDQAAAA==.Tigerji:BAAALAADCggIDAAAAA==.Tinybluemage:BAAALAAECgYIBgAAAA==.Tirna:BAAALAAECgUIBQAAAA==.',Tj='Tjurskall:BAABLAAECoEVAAIbAAgI8B13JABMAgAbAAgI8B13JABMAgAAAA==.',To='Toproller:BAAALAAECgIIAgAAAA==.Toushangyou:BAAALAAECgQIBQAAAA==.',Tr='Trasseljanne:BAAALAADCggICAAAAA==.Trinix:BAAALAAECgYIEQAAAA==.Triton:BAAALAAECgMIAwAAAA==.Trolltyget:BAAALAAECggIEAAAAA==.Tròlltyg:BAAALAAECggICAAAAA==.',Ts='Tsfel:BAAALAAFFAIIAgABLAAFFAUIDQADABkaAA==.',Tu='Tuhosepi:BAAALAAECgYIBgABLAAFFAMIBQAWAFsjAA==.Turandot:BAAALAADCgQIBQAAAA==.',Ty='Tyhmeliini:BAAALAAECgQICAAAAA==.',['Tå']='Tårtewa:BAAALAAECgYICAABLAADCgcIBwAEAAAAAA==.',['Tö']='Tönö:BAAALAAECgYIDwAAAQ==.Tötte:BAAALAADCgUIBQAAAA==.Töttepräst:BAAALAAECgQIBgAAAA==.',Um='Umbranox:BAABLAAECoEgAAIgAAgIXCQcAQBTAwAgAAgIXCQcAQBTAwAAAA==.',Un='Ununquadium:BAAALAADCgYIBgAAAA==.',Up='Uppies:BAAALAADCgYIBgABLAAFFAMIBQAWAFsjAA==.Upptaget:BAAALAAECgIIAgABLAAECggIFQAbAPAdAA==.',Us='Usel:BAAALAADCggICAAAAA==.',Uz='Uzimullvad:BAABLAAECoEVAAISAAgIZBrLAwB9AgASAAgIZBrLAwB9AgAAAA==.',Va='Vairozdh:BAAALAADCgYIBQAAAA==.Vajaaälyinen:BAABLAAECoEUAAIQAAcIGRUQLQDgAQAQAAcIGRUQLQDgAQAAAA==.Vanil:BAAALAAECgYIBgAAAA==.Vargael:BAAALAAECgUIBwAAAA==.Varghavoc:BAAALAAECgMIBQAAAA==.Vargheal:BAAALAADCgIIAgABLAAECgMIBQAEAAAAAA==.Varghio:BAAALAAECgIIAgABLAAECgMIBQAEAAAAAA==.Varghxd:BAAALAADCgcIDgABLAAECgMIBQAEAAAAAA==.',Ve='Vellaru:BAAALAADCgYIBgABLAAFFAQIBgAcAJgYAA==.Venasi:BAAALAAECggIDwAAAA==.Vendishock:BAAALAAECgQIBAAAAA==.Venduwu:BAAALAADCgYIBwABLAAECgQIBAAEAAAAAA==.Verveine:BAAALAADCggIGwAAAA==.Vetarn:BAAALAADCgYIBgAAAA==.Vezzx:BAAALAAECgYIBgAAAA==.',Vi='Viniwari:BAAALAADCgYIBgAAAA==.Vipkrabba:BAAALAAECgYIBgAAAA==.Viserion:BAAALAADCgYICgAAAA==.Vivess:BAAALAADCgYIDAAAAA==.',Vl='Vloerinspect:BAAALAAECgYICAAAAA==.',Vo='Volzy:BAAALAAFFAIIBAAAAA==.Vontarth:BAAALAAECgIIAwAAAA==.Voodoomkin:BAAALAAECgIIAgAAAA==.',Vu='Vurax:BAAALAADCggIGAAAAA==.',['Vï']='Vïdeo:BAAALAAECgYIEQAAAA==.',Wh='Whatseeds:BAAALAADCgEIAQAAAA==.Whitemadness:BAABLAAECoEWAAIVAAcIsByxEwA4AgAVAAcIsByxEwA4AgAAAA==.Whortencia:BAAALAADCgMIAwAAAA==.',Wi='Wildneck:BAAALAADCgYIBgAAAA==.Willydunka:BAAALAADCggIDAAAAA==.Winatrix:BAAALAAECgYICgAAAA==.Wir:BAAALAAECgYIEgAAAA==.Wirtz:BAAALAAECggIDQAAAA==.',Wo='Wongfoo:BAAALAAECgYIDAAAAA==.Wonghoe:BAAALAADCggICAAAAA==.Worecc:BAAALAADCgcICwAAAA==.Worgor:BAAALAADCgQIBAAAAA==.Worstpala:BAAALAAECgYICgAAAA==.Wowser:BAACLAAFFIEIAAINAAQIMhwtAgCEAQANAAQIMhwtAgCEAQAsAAQKgRkAAg0ACAirIswHAAcDAA0ACAirIswHAAcDAAAA.',Xe='Xeducedmage:BAAALAADCgIIAgAAAA==.Xeducedsp:BAAALAADCgUIBQAAAA==.',Xi='Xiaolierenn:BAAALAAECggIDgAAAA==.',Xo='Xozar:BAAALAADCgcICgAAAA==.',Ye='Yeahhboii:BAABLAAECoEUAAMOAAYInReyFwBoAQAOAAYIUxWyFwBoAQAbAAYIWw89ZwBZAQAAAA==.Yeé:BAAALAAECgYIBgAAAA==.',Yi='Yigezhanshi:BAAALAAECgUIBQABLAAECggIDgAEAAAAAA==.',Yx='Yxjäveln:BAAALAADCgEIAQAAAA==.',Ze='Zebee:BAAALAAECgMIAwAAAA==.Zentaa:BAAALAAECgIIAgAAAA==.Zephryn:BAAALAADCgcICQAAAA==.',Zi='Ziriana:BAAALAAECgYICgAAAA==.Zito:BAAALAAECgYIDAAAAA==.',Zn='Znexx:BAAALAAECgEIAgAAAA==.',Zo='Zorlak:BAAALAADCgIIAgAAAA==.Zorluck:BAAALAAECgYICgAAAA==.',Zu='Zuckerfrei:BAAALAAECgYIEQAAAA==.Zululthar:BAAALAADCgUIBQAAAA==.',Zy='Zynenjoyer:BAAALAADCgcICQAAAA==.',['Zé']='Zérkan:BAAALAAECggICwAAAA==.',['Zì']='Zìnrà:BAAALAAECgYICgAAAA==.',['Äc']='Äckelhästen:BAABLAAECoEaAAINAAgI7SAOBwASAwANAAgI7SAOBwASAwAAAA==.',['Äl']='Älget:BAAALAADCggICAABLAADCggICAAEAAAAAA==.',['Åb']='Åbjörn:BAAALAADCgYIBgABLAAECgYIDwAEAAAAAA==.',['Ét']='Étio:BAAALAADCgcIBwAAAA==.',['ßi']='ßic:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end