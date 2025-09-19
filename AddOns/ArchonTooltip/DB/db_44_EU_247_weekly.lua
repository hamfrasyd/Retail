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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Warrior-Fury','Druid-Balance','DemonHunter-Havoc','Hunter-BeastMastery','Shaman-Restoration','Paladin-Retribution','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Elemental','DeathKnight-Frost','Warlock-Demonology','Mage-Arcane','Mage-Frost','Warlock-Destruction','Hunter-Survival','Druid-Guardian','Evoker-Devastation','Rogue-Outlaw','Paladin-Protection','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Druid-Feral','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker',}; local provider = {region='EU',realm='AeriePeak',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abikita:BAAALAADCgcIAwAAAA==.Abit:BAAALAAECggIEgAAAA==.',Ad='Adelae:BAAALAADCgMIAwAAAA==.Adnior:BAAALAAECgYIEQAAAA==.Advo:BAAALAADCggICAAAAA==.Advocatas:BAAALAAECgMIAwAAAA==.Advocatus:BAAALAADCgYIBgAAAA==.Adysor:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.',Ae='Aeden:BAAALAAECgYIBwAAAA==.Aewin:BAAALAAECgYIEQAAAA==.',Ai='Aimeh:BAAALAAECgYIEAAAAA==.',Ak='Akpallus:BAAALAAECgQIBQAAAA==.',Al='Alinush:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.Alià:BAAALAAECgYIEQAAAA==.Alshai:BAAALAADCgcIBwAAAA==.Altruic:BAAALAAECgYIEQAAAA==.Alyssaria:BAAALAADCgQIBAAAAA==.Alythae:BAAALAADCggICAAAAA==.',Am='Amelya:BAAALAADCggIEwAAAA==.',An='Andie:BAAALAADCgYIBgAAAA==.Andkattdwarf:BAAALAADCggIEgAAAA==.Andrei:BAAALAADCggIEAAAAA==.Anduriel:BAAALAAECgcIEAAAAA==.Angeluna:BAAALAAECggIDQAAAA==.Angie:BAAALAAECgYIDQAAAA==.Angryeler:BAAALAAECgcIEQAAAA==.Annara:BAAALAAECgUICwAAAA==.',Ar='Aramathaya:BAAALAAECgQIBAAAAA==.Arcadias:BAABLAAECoEWAAICAAcInQi5NABhAQACAAcInQi5NABhAQAAAA==.Arcangle:BAAALAADCggIDAAAAA==.Arcanimagus:BAAALAAECgMIAwAAAA==.Armadi:BAAALAADCgYIBgAAAA==.Arminor:BAAALAADCgcIBwAAAA==.Arthok:BAAALAAECgMIAwAAAA==.Arxontas:BAAALAADCggICAAAAA==.',As='Ashhgaming:BAAALAADCggICwAAAA==.',At='Atnub:BAAALAAECgYIAgAAAA==.Atorias:BAAALAADCggICAAAAA==.Atriohm:BAAALAADCgcIBwAAAA==.',Az='Azrift:BAAALAADCgcIBwAAAA==.Azunath:BAAALAAECgMIAwAAAA==.',Ba='Bababooie:BAABLAAECoEXAAIDAAcIrBj7HQApAgADAAcIrBj7HQApAgAAAA==.Badpala:BAAALAAECgMIAwAAAA==.Badpriester:BAAALAAECgEIAQAAAA==.Baldrax:BAAALAADCggICAAAAA==.Balmdur:BAAALAAECgEIAQAAAA==.Baltic:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.',Be='Bearace:BAACLAAFFIEFAAIEAAMIFgaWBQDPAAAEAAMIFgaWBQDPAAAsAAQKgR4AAgQACAiaIIIIAO8CAAQACAiaIIIIAO8CAAAA.Beardiweirdi:BAAALAADCgUIAgAAAA==.Befreiung:BAAALAADCgcIBwAAAA==.Bereket:BAAALAAECgYIEQAAAA==.Beyfu:BAAALAADCgMIBAAAAA==.Beyrol:BAAALAAECgIIAgAAAA==.',Bi='Billidan:BAAALAADCgcIBwAAAA==.Bipsié:BAABLAAECoEcAAIFAAgIqxsLHwBoAgAFAAgIqxsLHwBoAgAAAA==.',Bl='Blackadder:BAAALAAECgYIBgAAAA==.Blasterm:BAAALAAECgMIAwAAAA==.Bloodmagik:BAAALAADCgEIAQAAAA==.',Bo='Bodziu:BAAALAAECgYIDwAAAA==.Bottimus:BAAALAADCggICAAAAA==.Bouhunter:BAABLAAECoEYAAIGAAgICBaBIAApAgAGAAgICBaBIAApAgAAAA==.',Br='Brickchewer:BAAALAAECgYIEQAAAA==.Broony:BAAALAADCggIEAAAAA==.',Bu='Buckybckbtch:BAAALAADCggIDwAAAA==.Buddala:BAAALAAECggIEgAAAA==.Bullstomper:BAAALAADCgcICwAAAA==.',Ca='Cailin:BAAALAAECgIIAgAAAA==.Calaelen:BAAALAAECgUIBQAAAA==.Callistra:BAAALAADCgcIBwAAAA==.Caplus:BAAALAADCgcIAwAAAA==.Carcossa:BAAALAADCgcIBwABLAAECggIFwAHAOMaAA==.',Ce='Cellesta:BAAALAADCggIGgAAAA==.',Ch='Chaosknight:BAAALAADCgUIBwAAAA==.Chaostotem:BAAALAADCggIEQABLAAECgMIBQABAAAAAA==.Chazar:BAAALAAECgYIDgAAAA==.Chilis:BAAALAADCgEIAQAAAA==.Chillbill:BAAALAAECgMIAwAAAA==.',Ci='Cirilla:BAAALAADCggIBgAAAA==.',Cj='Cjonas:BAAALAAECgUICAAAAA==.',Cl='Clam:BAABLAAECoEVAAIEAAgIiAeTLQB5AQAEAAgIiAeTLQB5AQAAAA==.',Co='Cordisater:BAABLAAECoEVAAIIAAcICx+jHgBxAgAIAAcICx+jHgBxAgAAAA==.Corn:BAAALAADCggICQAAAA==.Costae:BAAALAAECgEIAQAAAA==.',Cr='Crayoneater:BAABLAAECoEVAAIDAAcIKB63GABWAgADAAcIKB63GABWAgAAAA==.Creedence:BAAALAADCgYIBgAAAA==.Cronoth:BAAALAAECgMIBAAAAA==.Crowidan:BAAALAAECgcIEgAAAA==.',['Cé']='Cénice:BAAALAADCgUIBQAAAA==.',['Có']='Cómpactdísc:BAAALAAECggIDAAAAA==.',Da='Daath:BAABLAAECoEVAAIJAAcIIiHFBQCQAgAJAAcIIiHFBQCQAgAAAA==.Dagoat:BAABLAAECoEgAAIFAAgIph/vDwDkAgAFAAgIph/vDwDkAgAAAA==.Darkine:BAAALAADCgIIAgAAAA==.Darkróse:BAAALAAECgMIBgAAAA==.Darkscarlet:BAAALAAECgEIAQAAAA==.',De='Deamo:BAAALAADCgUIBQAAAA==.Deamonthinut:BAAALAAECggIDQAAAA==.Deathchef:BAAALAAECgYIEQAAAA==.Deathdissent:BAAALAADCgcICAAAAA==.Delfin:BAAALAAECgEIAQAAAA==.Desolate:BAAALAAECgMIBwAAAA==.',Di='Dionfortune:BAAALAADCgcIAwAAAA==.Dismyr:BAAALAADCgcICwAAAA==.Dixierect:BAAALAADCggIEAABLAAECggIGgAKAGkjAA==.',Dr='Draegos:BAAALAAECgIIAgAAAA==.Draendei:BAAALAADCgYIBAAAAA==.Dreaddemon:BAAALAADCggICAABLAADCggICQABAAAAAA==.Drimturm:BAAALAAECgYIDAAAAA==.Drmanháttan:BAAALAADCgYIBgAAAA==.Drogrin:BAAALAADCgcIBwAAAA==.Droseros:BAAALAADCgcIBwAAAA==.Drurmargur:BAAALAAECgYIEQAAAA==.',Dy='Dysphoria:BAAALAAECgEIAQAAAA==.',Ed='Edannu:BAAALAADCggICAAAAA==.Edgarz:BAAALAADCggIIAAAAA==.',Eg='Eggshen:BAAALAADCggICAAAAA==.',El='Elea:BAAALAADCgcICAAAAA==.Elektrorose:BAAALAADCgYIBgAAAA==.Eleonora:BAAALAADCgUIBQAAAA==.Elerment:BAABLAAECoEYAAILAAgIixZhHAAtAgALAAgIixZhHAAtAgAAAA==.Elria:BAAALAAECgMIAwAAAA==.Elrygos:BAAALAADCggIFAAAAA==.',Em='Emeraldgosa:BAAALAADCgUIBAAAAA==.Emry:BAAALAAECggIEwAAAA==.',Eu='Euphiee:BAAALAAECgEIAQAAAA==.',Fa='Faralda:BAAALAADCgMIAwAAAA==.',Fe='Felon:BAAALAAECgMIBQAAAA==.Felshan:BAAALAADCgIIAgABLAAECggIGQAMAMIiAA==.Feyrê:BAAALAADCggIFQABLAAECgYIEgABAAAAAA==.',Fi='Fiction:BAAALAAECgIIAgAAAA==.Fireminth:BAABLAAECoEUAAINAAcIwRswDgAoAgANAAcIwRswDgAoAgAAAA==.Firescream:BAABLAAECoEVAAMOAAYIuBy7NgDoAQAOAAYIuBy7NgDoAQAPAAMIvQ3NSAB9AAAAAA==.',Fl='Floridaman:BAAALAADCggICAAAAA==.Florinel:BAAALAAECgQIBgAAAA==.',Fo='Forzakenone:BAAALAAECgcIDgAAAA==.',Fr='Frizlok:BAAALAAECgEIAQAAAA==.Frostitutee:BAAALAAECgYIBgAAAA==.',Fu='Fudgex:BAAALAADCgMIAwAAAA==.',['Fê']='Fêyre:BAAALAAECgYIEgAAAA==.',Ga='Gabran:BAAALAAECgYICQAAAA==.Galbatros:BAABLAAECoEWAAIHAAcIvxeqKADkAQAHAAcIvxeqKADkAQAAAA==.Garbagedrood:BAAALAAECgIIAgAAAA==.Garre:BAAALAAECgQIBwAAAA==.Gascoigne:BAAALAADCggIEQAAAA==.Gazdalf:BAAALAADCgYIBQABLAADCggIEAABAAAAAA==.',Ge='Genghiszan:BAAALAAECgMIAwAAAA==.',Gh='Ghostspectre:BAAALAAECgEIAQAAAA==.',Gl='Glowner:BAAALAADCgcIBwAAAA==.',Go='Gondolock:BAABLAAECoEUAAINAAcIAxLCFgDbAQANAAcIAxLCFgDbAQAAAA==.Gorefriend:BAABLAAECoETAAIMAAcIxSRPEwDCAgAMAAcIxSRPEwDCAgAAAA==.Gorlem:BAAALAADCggIEAAAAA==.Gothgirlcliq:BAAALAAECgEIAQAAAA==.',Gr='Grimmage:BAAALAADCgcICQABLAAECgEIAQABAAAAAA==.Grimmly:BAAALAAECgcICwAAAA==.Grundi:BAAALAADCgYIBgAAAA==.Gruthar:BAAALAADCgcIBwAAAA==.',['Gâ']='Gârgamel:BAAALAAECgMIAwAAAA==.',['Gä']='Gäri:BAAALAADCgcIBgAAAA==.',Ha='Hardwon:BAAALAADCggIFgAAAA==.Harikrishna:BAAALAAECgYICAAAAA==.Hasadiga:BAAALAADCggICAAAAA==.',He='Healstrasza:BAAALAAECgIIAgAAAA==.Hellshan:BAABLAAECoEZAAIMAAgIwiKBBwAqAwAMAAgIwiKBBwAqAwAAAA==.Herculies:BAAALAAECgEIAQAAAA==.Hextoothless:BAAALAADCggIDAAAAA==.',Hi='Hillee:BAAALAAECgUICgAAAA==.',Ho='Hornstars:BAAALAAECgIIAgAAAA==.',Hu='Hunterm:BAAALAADCgYICgAAAA==.Huntina:BAAALAAECgYIDwAAAA==.Huntressrose:BAAALAAECgQIBAAAAA==.Huntvine:BAAALAADCggICAAAAA==.Huxsmash:BAAALAADCggICAAAAA==.',['Hü']='Hüri:BAAALAAECggIEAAAAA==.',Ia='Iamcurved:BAAALAADCggIHQAAAA==.Iamninja:BAAALAADCgMIAwAAAA==.',If='Ifiklis:BAAALAAECgYIDQAAAA==.',Il='Ilikecurves:BAAALAAECgYIEgAAAA==.Illyiah:BAAALAAECgMIAwAAAA==.',Im='Immortallife:BAAALAAECgIIAgAAAA==.Imprasarrial:BAAALAAECgYIDgAAAA==.Impravoker:BAAALAAECgYIBgAAAA==.',In='Infekted:BAABLAAECoEVAAMNAAcI9hNJIQCSAQANAAYIoRNJIQCSAQAQAAUIlBHzSwBCAQAAAA==.',Ja='Jackechan:BAAALAADCggICAAAAA==.Jackson:BAAALAAECgMIBQAAAA==.Jadá:BAABLAAECoEaAAMRAAgIMCV/AABRAwARAAgIZiR/AABRAwAKAAMIMx0rSwDcAAAAAA==.Jakksy:BAAALAADCgYICQAAAA==.Jayygeh:BAAALAADCgMIAwAAAA==.',Je='Jeremykylé:BAAALAAECgcIEQAAAA==.',Ji='Jinjuu:BAABLAAECoEZAAIPAAgIzBQwEAAqAgAPAAgIzBQwEAAqAgAAAA==.',Jo='Jobje:BAAALAAECgYICAAAAA==.Joony:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.',Ju='Juddge:BAABLAAECoEbAAISAAgIqgPpDwDlAAASAAgIqgPpDwDlAAAAAA==.Juffzh:BAAALAADCgUIBwAAAA==.Juipe:BAAALAAECgIIAgAAAA==.',Ka='Kaboose:BAAALAAECgMIAwAAAA==.Kaidasen:BAAALAAECgIIAgABLAAFFAIIBgAHAIsDAA==.Kaidazen:BAACLAAFFIEGAAIHAAIIiwNbGwBsAAAHAAIIiwNbGwBsAAAsAAQKgSEAAgcACAhEFZItAMsBAAcACAhEFZItAMsBAAAA.Kapsokolis:BAAALAADCggICQAAAA==.',Ke='Kealsith:BAAALAADCgQIBAAAAA==.Keldris:BAAALAADCggICAAAAA==.Keun:BAAALAAECgMIBAAAAA==.',Kh='Kharox:BAABLAAECoEVAAIDAAcIoxFfKgDQAQADAAcIoxFfKgDQAQAAAA==.Kházrak:BAAALAAECgYICQAAAA==.',Ki='Killshot:BAAALAAECgMIBQAAAA==.Kindread:BAAALAADCggICQAAAA==.Kiðlingur:BAAALAAECgYIDAAAAA==.',Ko='Kompakt:BAAALAAECgcIEgAAAA==.',Kr='Kraven:BAAALAAECgMIBQAAAA==.',Ku='Kuniku:BAAALAAECgYIBgAAAA==.',['Kâ']='Kâunokainen:BAAALAADCggICAAAAA==.',['Kü']='Kücümen:BAAALAAECggIDwAAAA==.',Le='Levìathan:BAAALAADCgYIBgAAAA==.',Li='Liekkiö:BAABLAAECoEcAAITAAgIBBo7DwBlAgATAAgIBBo7DwBlAgAAAA==.Lightsaxe:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Lika:BAAALAADCgMIAwAAAA==.',Ll='Llensi:BAAALAAECgEIAQAAAA==.Llowwkey:BAAALAAECgYICgAAAA==.',Lo='Loganmccrae:BAAALAAECgYIEAAAAA==.Looper:BAACLAAFFIEFAAIGAAMIORk4AwAUAQAGAAMIORk4AwAUAQAsAAQKgSQAAgYACAgYJIUFADEDAAYACAgYJIUFADEDAAAA.Loreleyannet:BAAALAAECgYICQAAAA==.',Lu='Luppin:BAAALAAECgEIAQABLAAFFAMIBQAGADkZAA==.Luthiean:BAAALAAECgYIBgAAAA==.',['Lí']='Lílith:BAAALAADCgcIBwAAAA==.',Ma='Magealot:BAAALAAECgMIBQAAAA==.Mageu:BAAALAAECgYIDAAAAA==.Mairo:BAAALAADCgcIBwAAAA==.Majro:BAAALAADCggIEgAAAA==.Mamercus:BAAALAADCgcIEAAAAA==.Manscattan:BAAALAADCggICAABLAAECggIFwAOAPQiAA==.Mardell:BAAALAAECgMIAwAAAA==.Marowit:BAAALAAECgYIDQAAAA==.Masic:BAAALAAECgYIEQAAAA==.Maximusver:BAAALAAECgIIAgAAAA==.Mazikeenn:BAAALAADCggICAAAAA==.',Mc='Mcstabberz:BAAALAADCgcIBwAAAA==.',Md='Mdx:BAAALAAECgYIBgAAAA==.',Me='Mencius:BAAALAADCgcIDQAAAA==.Mephine:BAAALAAECgEIAQAAAA==.Mezumiiru:BAAALAAECgMIBwAAAA==.',Mi='Micks:BAAALAADCgQIBQAAAA==.Mictian:BAAALAADCggICAAAAA==.Minnakra:BAAALAAECgYIEQAAAA==.Mirthy:BAAALAAECgIIAgAAAA==.Mistrzu:BAAALAADCggICQAAAA==.',Mj='Mjedër:BAABLAAECoEVAAIGAAcINh2HGABlAgAGAAcINh2HGABlAgAAAA==.',Mo='Moeko:BAAALAADCggICAAAAA==.Moostang:BAAALAADCgcIBwAAAA==.Morbis:BAABLAAECoEVAAIMAAcIuQ9LUQCaAQAMAAcIuQ9LUQCaAQAAAA==.Morphero:BAAALAAECgYIBgAAAA==.Mortarian:BAAALAAECgMIBAAAAA==.',Mu='Mudlock:BAAALAADCgcIBwAAAA==.',['Mó']='Mónthé:BAABLAAECoEXAAISAAcIWR4PAwBtAgASAAcIWR4PAwBtAgAAAA==.',Na='Naiva:BAAALAADCgYIDAABLAAECgMIBgABAAAAAA==.Narooma:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Narun:BAAALAAECgYIBgAAAA==.Nasián:BAAALAAECgYIEQAAAA==.Naveanna:BAAALAADCgMIAwABLAAECgMIBAABAAAAAA==.',Ne='Nemeziziz:BAAALAADCgYIBwAAAA==.Nepherias:BAAALAADCgMIAwAAAA==.',Ni='Nightshades:BAAALAADCgQIBAAAAA==.Nitre:BAEBLAAECoEZAAIUAAgIyxjXAgB+AgAUAAgIyxjXAgB+AgAAAA==.',Nu='Nuncio:BAAALAAECgcIEwAAAA==.Nuradin:BAAALAADCgQICAAAAA==.',Oa='Oakleaf:BAABLAAECoEUAAIGAAcImBJWMwDCAQAGAAcImBJWMwDCAQAAAA==.',Og='Ogpog:BAAALAADCgcIFAAAAA==.',On='Onepunsh:BAABLAAECoEUAAIHAAcIyB+7FABZAgAHAAcIyB+7FABZAgAAAA==.Oneshot:BAAALAADCgMIAwAAAA==.',Oo='Oomtrix:BAACLAAFFIEGAAIOAAMIexGbCgD4AAAOAAMIexGbCgD4AAAsAAQKgR4AAg4ACAihH1oPAOYCAA4ACAihH1oPAOYCAAEsAAQKAwgFAAEAAAAA.',Op='Opala:BAAALAADCggICAAAAA==.',Or='Orihan:BAAALAADCgcICAAAAA==.Oruhe:BAAALAADCgcIDQAAAA==.',Pa='Palasia:BAAALAADCgMIAwAAAA==.Papibear:BAAALAAECgUIBQAAAA==.Paulthealien:BAAALAAECgYIDgAAAA==.Paxili:BAAALAADCgMIAwAAAA==.',Pb='Pbs:BAABLAAECoEVAAIVAAcI7SCMBgCTAgAVAAcI7SCMBgCTAgAAAA==.',Pe='Petru:BAAALAADCgcICQABLAAECgQIBgABAAAAAA==.',Ph='Phoronée:BAABLAAECoEYAAIFAAgI2iJBCAAtAwAFAAgI2iJBCAAtAwAAAA==.Phéoníx:BAAALAAECgYIDgAAAA==.',Pi='Picollovac:BAAALAADCgcIBwAAAA==.Pinguïn:BAAALAAECgYICAAAAA==.Pintea:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.Pipsqueak:BAAALAAECgMIAwABLAAECgMIBAABAAAAAA==.Piroel:BAABLAAECoEWAAMIAAcINCK0FgCtAgAIAAcINCK0FgCtAgAVAAUISxqdHwAMAQAAAA==.',Pl='Plan:BAAALAAECgUIBQAAAA==.',Po='Polymorph:BAAALAAFFAEIAQAAAA==.Ponyfiddler:BAAALAAECgcIDgAAAA==.Popesith:BAAALAAECgMIBQAAAA==.Powerbttm:BAAALAAECgcIEgAAAA==.',Pp='Ppanda:BAAALAAECgEIAQAAAA==.',Pr='Prada:BAAALAAECggICAAAAA==.Preatorion:BAAALAADCgcIBwAAAA==.',['Pá']='Pádfoot:BAAALAAECgMIAwAAAA==.',Ra='Rabbidpikey:BAAALAAECgYIBgABLAAECggIDAABAAAAAA==.Raemal:BAAALAAECgUIAgAAAA==.Rageelf:BAABLAAECoEeAAQCAAgIpxLuKgCjAQACAAcIWRHuKgCjAQAWAAgI3QcDNACEAQAXAAMIPgz5FQCkAAAAAA==.Ravena:BAABLAAECoEVAAIHAAcIfQr7VAAvAQAHAAcIfQr7VAAvAQAAAA==.',Re='Redblade:BAAALAADCggICAAAAA==.Revorius:BAAALAADCggIEAABLAAECgQIBwABAAAAAA==.',Ri='Ritsen:BAAALAAECgYIEQAAAA==.',Ro='Rokiva:BAAALAADCgMIAwAAAA==.Ronalf:BAAALAAECgEIAQAAAA==.Roseblade:BAAALAAECgYIEQAAAA==.Rotandroll:BAAALAAECgIIBAAAAA==.Rotath:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.',Ru='Rubmytotèm:BAAALAAECgYICAAAAA==.Rudolph:BAAALAADCgUIBQAAAA==.',Sa='Sabe:BAAALAADCggIDgAAAA==.Saifu:BAACLAAFFIEFAAIYAAMI4AeeBADdAAAYAAMI4AeeBADdAAAsAAQKgRgAAhgACAiGDtQSAK4BABgACAiGDtQSAK4BAAAA.Sammie:BAAALAAECgYICQAAAA==.Samson:BAAALAADCggICwAAAA==.Sanjin:BAAALAADCggIEQAAAA==.Saron:BAABLAAECoEXAAMHAAgI4xocEwBkAgAHAAgI4xocEwBkAgALAAQIXR2nQgBOAQAAAA==.',Sc='Scattach:BAABLAAECoEXAAIOAAgI9CKFCwAGAwAOAAgI9CKFCwAGAwAAAA==.Schukon:BAAALAAECggICAAAAA==.Scroob:BAAALAADCggICAAAAA==.',Se='Seamanstains:BAAALAADCggIEQAAAA==.Seffron:BAAALAAECgIIAgAAAA==.Seffrone:BAAALAADCgEIAQAAAA==.Selora:BAAALAAECggIEwAAAA==.Seramoon:BAAALAADCgQIBAAAAA==.Seyko:BAAALAAECggIEQAAAA==.',Sf='Sfantu:BAAALAADCgYICQABLAAECgQIBgABAAAAAA==.',Sh='Shadedlady:BAAALAADCgcICwAAAA==.Shadowmelder:BAABLAAECoEWAAIGAAcI2BrvIQAgAgAGAAcI2BrvIQAgAgAAAA==.Shahiri:BAAALAADCggIEAABLAAECggIFwAOAPQiAA==.Shamanuellsn:BAAALAADCggICwAAAA==.Shamanzoef:BAAALAAECgcIEAABLAAECgcIFgAGAKUcAA==.Sharashim:BAAALAAECggIDQAAAA==.Shazaulk:BAAALAADCgcIBwAAAA==.Shellaa:BAAALAADCgcIBwAAAA==.Shiftimblind:BAAALAADCgcIBwABLAAECggIGgAZAGAiAA==.Shimme:BAAALAAECgIIAwAAAA==.Shinomiya:BAAALAADCggIEAAAAA==.',Si='Siirí:BAAALAAECgIIAgAAAA==.Simpsonheale:BAAALAAECgcIDAAAAA==.',Sj='Sjenka:BAAALAAECgYIEQAAAA==.',Sk='Skargoth:BAAALAADCggIDgABLAAECgEIAQABAAAAAA==.Skeleton:BAABLAAECoEUAAIJAAYI+xNWEwBTAQAJAAYI+xNWEwBTAQAAAA==.',Sl='Slasherm:BAAALAADCgcIDQAAAA==.Slaughterkil:BAAALAADCggIDQAAAA==.Slaughterwel:BAAALAAECgMIBgAAAA==.Sleep:BAAALAADCgYIBgAAAA==.',Sn='Snapdruidx:BAAALAADCggICAAAAA==.',So='Sometingwong:BAAALAADCgcIBwAAAA==.Soulpandaa:BAAALAAECgMIBQAAAA==.',Sp='Spellwright:BAAALAADCgYIBgAAAA==.Spideycat:BAAALAADCgMIAwAAAA==.Spiritius:BAAALAAECgYICAABLAAECggIHAATAAQaAA==.Spirtuel:BAAALAADCgYIAQAAAA==.',St='Steelfayth:BAAALAADCggICAAAAA==.Steelzyy:BAAALAAECgEIAQAAAA==.Stormlord:BAAALAAECgMIAwAAAA==.Stormwytch:BAAALAAECgIIBAAAAA==.Stormypetrel:BAAALAADCgcIAwAAAA==.',Su='Sunnie:BAAALAAECgMIBAAAAA==.Sunrinlin:BAAALAAECgEIAQAAAA==.Supimage:BAAALAAECgIIAgAAAA==.Suvitza:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.',Sw='Swiftie:BAAALAADCgYIBgAAAA==.',Sy='Sylren:BAABLAAECoEZAAIIAAgISAwHVACTAQAIAAgISAwHVACTAQAAAA==.Symeris:BAAALAADCggICAAAAA==.Syndrexia:BAAALAADCgMIAwAAAA==.',Ta='Tanade:BAAALAADCgEIAQAAAA==.Tankistaa:BAAALAAECgYIBgAAAA==.',Tc='Tccb:BAAALAAECgYIEQAAAA==.',Te='Tehbinka:BAAALAADCggICAAAAA==.Tenen:BAABLAAECoEVAAIGAAYIlRaPOgChAQAGAAYIlRaPOgChAQAAAA==.Tephraxis:BAAALAAECgcIEgAAAA==.Terrax:BAAALAAECgEIAQAAAA==.Terö:BAAALAAECgEIAQAAAA==.',Th='Thaddeus:BAAALAAECgYIEQAAAA==.Theshifter:BAABLAAECoEaAAQZAAgIYCJ/AwAKAwAZAAgIYCJ/AwAKAwAaAAUIHQ6DFwBEAQAEAAMI4BqlQwDeAAAAAA==.Thramlocks:BAAALAAECgcIDQAAAA==.Thunderleaf:BAACLAAFFIEHAAIbAAMI/w0mBADNAAAbAAMI/w0mBADNAAAsAAQKgSAAAhsACAiWHagGAJACABsACAiWHagGAJACAAAA.',Ti='Ticklemytess:BAABLAAECoEaAAIKAAgIaSOQBAAiAwAKAAgIaSOQBAAiAwAAAA==.Tileana:BAAALAAECgEIAQAAAA==.Tinylynne:BAAALAADCgcIAwAAAA==.',Tj='Tjaman:BAAALAADCggICAAAAA==.',To='Torche:BAAALAAECgYIDAAAAA==.',Tr='Truestorm:BAAALAADCgcIDgABLAAECgEIAQABAAAAAA==.',Tu='Tudum:BAAALAAECgIIAgAAAA==.Turnatrick:BAAALAADCgIIAgAAAA==.Tutator:BAAALAAECggIEAAAAA==.Tutlek:BAAALAADCggIDgAAAA==.',Tw='Twinklés:BAAALAAFFAIIAgAAAA==.',Ue='Ueksan:BAAALAADCgQIBAAAAA==.',Ul='Ulfgangur:BAAALAADCgcIDgAAAA==.Ulithorn:BAAALAADCgcIBwAAAA==.',Un='Uniken:BAAALAADCgcIBwAAAA==.',Va='Vadér:BAAALAADCgUICAAAAA==.Valgodorras:BAAALAAECgIIAwAAAA==.Valkahn:BAABLAAECoEYAAIEAAgI9gkuJgCpAQAEAAgI9gkuJgCpAQAAAA==.Vantrex:BAAALAAECgMIBQAAAA==.Varealf:BAAALAAECgcIEQAAAA==.Vareesha:BAAALAAECgEIAQAAAA==.Vasur:BAAALAADCgQIBAAAAA==.',Ve='Venkel:BAAALAAECgYIDAAAAA==.Venthues:BAAALAAECgMIAwAAAA==.Verifonix:BAABLAAECoEWAAIHAAgIoQyIRwBeAQAHAAgIoQyIRwBeAQAAAA==.',Vi='Vilebaard:BAAALAAECgYIEQAAAA==.Virane:BAAALAAECgYIDAAAAA==.Virmortalis:BAAALAAECgEIAQAAAA==.',Vo='Voiddeath:BAAALAADCgQIBAAAAA==.',Vu='Vukodlak:BAABLAAECoEWAAIcAAcIvBlxHADYAQAcAAcIvBlxHADYAQAAAA==.',['Vá']='Vánhelsing:BAAALAADCgUIBQAAAA==.',Wa='Warcox:BAAALAAECggIDgAAAA==.',We='Wetshya:BAAALAADCggIDAAAAA==.',Wh='Whitelighter:BAAALAAECgMIBgAAAA==.',Wi='Windtorn:BAAALAAECgYIDgAAAA==.',Wo='Wonderbread:BAAALAAECgcIBwAAAA==.',Xi='Xiaomimi:BAAALAAECgMIBQAAAA==.',Xu='Xulu:BAAALAADCggICAABLAAECggIGAAWAGEgAA==.',Ya='Yalldor:BAAALAADCgYIDAABLAAECgEIAQABAAAAAA==.',Ye='Yemanya:BAAALAADCgEIAQAAAA==.Yevaud:BAAALAAECgEIAQAAAA==.',Yo='Yodà:BAAALAAECgcIEQAAAA==.Yoshirogue:BAAALAADCggICQAAAA==.',Yu='Yungai:BAAALAAECgUIDQAAAA==.',Za='Zandwitch:BAAALAADCgUIBQAAAA==.',Ze='Zecturne:BAAALAAECgYIBgAAAA==.Zedhi:BAAALAADCgMIAwAAAA==.Zeelord:BAABLAAECoEeAAIWAAgIDiTGAgA8AwAWAAgIDiTGAgA8AwAAAA==.Zenindreas:BAAALAADCggICAABLAAECggIHAATAAQaAA==.Zenintra:BAAALAAECgYIEAABLAAECggIHAATAAQaAA==.Zeroy:BAABLAAECoEZAAIdAAgIDSXFAQBUAwAdAAgIDSXFAQBUAwAAAA==.Zetheros:BAAALAAECggIBAAAAA==.',Zi='Zireaél:BAAALAADCgcIBwAAAA==.',Zm='Zmij:BAAALAADCgMIAwABLAAECggIFwAHAOMaAA==.Zmíj:BAAALAAECgQIBAABLAAECggIFwAHAOMaAA==.Zmííj:BAAALAAECgYIEAABLAAECggIFwAHAOMaAA==.',Zo='Zoef:BAABLAAECoEWAAIGAAcIpRyOGgBWAgAGAAcIpRyOGgBWAgAAAA==.',Zr='Zroy:BAAALAADCggICAAAAA==.',Zu='Zuluhead:BAAALAADCgcIAwAAAA==.',Zw='Zwerewolfz:BAAALAAECgIIAgAAAA==.',Zy='Zyrrith:BAAALAADCgMIAwAAAA==.',['Àr']='Àres:BAAALAADCggIFgAAAA==.',['Èm']='Èmrys:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end