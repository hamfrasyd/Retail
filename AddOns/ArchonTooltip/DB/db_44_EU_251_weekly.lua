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
 local lookup = {'Unknown-Unknown','Warrior-Protection','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Druid-Balance','Mage-Arcane','Mage-Fire','Shaman-Enhancement','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Holy','Monk-Brewmaster','Paladin-Holy','Shaman-Elemental','Warrior-Arms','DemonHunter-Vengeance','Druid-Restoration','DemonHunter-Havoc','Mage-Frost','Paladin-Retribution','Paladin-Protection','Shaman-Restoration','Monk-Windwalker',}; local provider = {region='EU',realm="Al'Akir",name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abba:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.Aboli:BAAALAAECgYIBgABLAAECggIDwABAAAAAA==.',Ae='Aerioth:BAAALAAECgYIEwAAAA==.Aeter:BAAALAAECgIIAgAAAA==.',Ag='Agro:BAABLAAECoEUAAMCAAYIXRq8FgC7AQACAAYIXRq8FgC7AQADAAMIjArGWgChAAAAAA==.Agtar:BAAALAAECgMIAwAAAA==.',Ai='Aimarn:BAAALAAECgMIAwAAAA==.Aithusa:BAAALAAECgcIDAAAAA==.',Al='Alaeddine:BAAALAAECgMIAwAAAA==.Alaira:BAAALAADCgQIBQAAAA==.Alakiros:BAAALAAECgMIAwAAAA==.Alexandru:BAAALAAECgYIDQAAAA==.Alienation:BAAALAAFFAEIAQAAAA==.Allure:BAAALAADCggICAAAAA==.Also:BAAALAADCgQIBAAAAA==.Altchland:BAABLAAECoEWAAQEAAgIHCVNAQDPAgAEAAcIMyVNAQDPAgAFAAIIrBsROwB+AAAGAAEIARSNIgBEAAAAAA==.',Am='Amatimees:BAAALAADCgUIBQAAAA==.Amoral:BAAALAADCggICAAAAA==.',An='Anri:BAAALAADCgcIAwAAAA==.Antipriest:BAABLAAECoEXAAIHAAcIERjiHwD3AQAHAAcIERjiHwD3AQAAAA==.',Ap='Aproxx:BAAALAAECggICgAAAA==.',Ar='Arataya:BAAALAAECgUICQAAAA==.Arcane:BAAALAAECgMIBAABLAAECgcIFQAIAK4XAA==.Arienton:BAAALAADCgEIAQAAAA==.Artémis:BAAALAADCgcIDQAAAA==.',As='Asheka:BAAALAAFFAIIAgAAAA==.Ashena:BAAALAAECggICAAAAA==.Asholog:BAAALAAECgQIBQAAAA==.Asoko:BAABLAAECoEUAAMJAAcIZyBIHwBsAgAJAAcIrB9IHwBsAgAKAAEIxBu4DwBTAAAAAA==.Astrae:BAAALAADCgcIBwAAAA==.Astrality:BAAALAADCgYIBgAAAA==.Astri:BAAALAAECgMIAwAAAA==.Astrois:BAAALAAECgcIEwAAAA==.',At='Atadina:BAAALAAECgIIAgAAAA==.Atix:BAAALAADCgIIAgAAAA==.Attenbruh:BAABLAAECoEUAAIIAAgIUyAWCAD2AgAIAAgIUyAWCAD2AgAAAA==.',Au='Aurash:BAAALAAECgYICwAAAA==.Aurielle:BAAALAAECgYIEwAAAA==.Auryx:BAAALAAECgMIAwAAAA==.',Az='Azerite:BAAALAADCggIDwAAAA==.',Ba='Baelpow:BAAALAADCgYIBgAAAA==.Bagz:BAAALAAECgMIBgAAAA==.Baldruid:BAAALAAECgEIAgAAAA==.Balerion:BAAALAADCggIEAAAAA==.Bananino:BAAALAADCgYIBwAAAA==.Baraddûr:BAAALAAECgYIBwAAAA==.Barasha:BAAALAAECgcIEgAAAA==.',Be='Beastmanaids:BAAALAADCgcICwAAAA==.Beibe:BAAALAAECgMIAwAAAA==.',Bi='Bibon:BAABLAAECoEVAAILAAcI0hwABgBLAgALAAcI0hwABgBLAgAAAA==.Bigmilk:BAAALAAECgcICgAAAA==.Billyboi:BAABLAAECoEUAAQMAAcI8RS2GwC3AQAMAAcI1hC2GwC3AQANAAUItQ8QTwA1AQAOAAEIsQS3MQA/AAAAAA==.Bish:BAAALAADCgYICgAAAA==.',Bj='Björntjäder:BAAALAAECgQIBQAAAA==.',Bl='Blackmaira:BAAALAAECgYIEwAAAA==.Bloodbringer:BAABLAAECoEXAAIPAAcIzhkANwD5AQAPAAcIzhkANwD5AQAAAA==.Bloodclot:BAAALAADCgcICAAAAA==.',Bo='Bow:BAAALAADCggIDwABLAAECgcIFQAIAK4XAA==.',Br='Brekke:BAAALAADCgYIBgAAAA==.Brucey:BAAALAADCgIIAQAAAA==.Bruckshot:BAAALAAECgcIDQAAAA==.Brutosaur:BAAALAAECgIIAgAAAA==.',Bu='Bubblez:BAAALAADCggIEQAAAA==.Bubumoo:BAAALAAECgcIEQAAAA==.Buburiza:BAAALAADCggICAAAAA==.Bukanyrtomy:BAAALAADCggICAAAAA==.Bumboo:BAAALAAECgIIAgAAAA==.Burstshot:BAABLAAECoEUAAMQAAcI5CFGGAAmAgAQAAYIPiNGGAAmAgARAAEIxhnJjABJAAAAAA==.',['Bå']='Båsedgôd:BAAALAAECgYIDAAAAA==.',['Bö']='Böe:BAAALAADCgcIBwAAAA==.Bösartigkeit:BAAALAAECgUIBQAAAA==.',Ca='Calioo:BAAALAADCgcIBwAAAA==.Callithyia:BAABLAAECoEYAAMSAAcIXBoNHgAOAgASAAcIXBoNHgAOAgAHAAEIfRWpYABFAAAAAA==.Cardigan:BAAALAAECgcIEwAAAA==.Carnagewar:BAAALAAECgEIAQAAAA==.',Ce='Cellstorm:BAAALAADCgYIAwAAAA==.',Ch='Choyleefut:BAABLAAECoEdAAITAAgIGhtuBwB2AgATAAgIGhtuBwB2AgAAAA==.',Ci='Ciaran:BAAALAAECgMIBgAAAA==.',Cl='Clapped:BAAALAADCgIIAgAAAA==.Clavar:BAAALAADCgcIEAAAAA==.Clerichealzz:BAAALAADCgQIBQABLAAECgYIDgABAAAAAA==.',Co='Coldplayed:BAAALAAECgIIBAAAAA==.Commandor:BAAALAADCgYIBQAAAA==.Coolkdruid:BAAALAADCgcIBwAAAA==.Coolkpaladin:BAABLAAECoEXAAIUAAcIIxTtFgDHAQAUAAcIIxTtFgDHAQAAAA==.Costhares:BAAALAAECgcIEgAAAA==.',Cr='Crackpot:BAAALAAECgcIEQAAAA==.Crankypants:BAAALAADCgUIBQAAAA==.Creapp:BAAALAAECgYIDwAAAA==.Critcobain:BAAALAAECgYIEAAAAA==.Crogis:BAAALAADCgQIBAAAAA==.Crystalwhite:BAAALAADCgYIBgAAAA==.',Cu='Cue:BAACLAAFFIEUAAIVAAYIdxfoAAAqAgAVAAYIdxfoAAAqAgAsAAQKgSQAAhUACAhpJUcFAD0DABUACAhpJUcFAD0DAAAA.',Da='Dageda:BAAALAAECgYIDgAAAA==.Daruni:BAAALAAECgYIEgAAAA==.Davidasayag:BAAALAADCggIEwAAAA==.Daydreaming:BAACLAAFFIEFAAIDAAIIkBzVCQC6AAADAAIIkBzVCQC6AAAsAAQKgR4AAwMACAgSInoKAPoCAAMACAgBInoKAPoCABYAAQj+JfkbAHEAAAAA.Daydréam:BAAALAAECgYICQABLAAFFAIIBQADAJAcAA==.',De='Deathsword:BAAALAAECgIIBAAAAA==.Decedatu:BAAALAAECgIIBwAAAA==.Dedgame:BAAALAAECgUIBQAAAA==.Degenerate:BAAALAAECgMIAwABLAAECgcIFAAXAM8hAA==.Deith:BAAALAAECgMIAwAAAA==.Deler:BAAALAADCgYICwAAAA==.Demonhaze:BAAALAAECgMIBAAAAA==.Denoysius:BAAALAADCgQIBAAAAA==.Dentibus:BAAALAADCgYIBgABLAAECgYIFgAMAMEcAA==.Dentimonk:BAAALAAECgYICAABLAAECgYIFgAMAMEcAA==.',Dh='Dharkan:BAAALAAECgcIBwABLAAECggIFQACAPokAA==.Dhsurfer:BAAALAAECgYIDQAAAA==.',Di='Dianabol:BAAALAADCgIIAgAAAA==.Diletta:BAAALAAECgUICwAAAA==.Dimageter:BAAALAADCggICAABLAAECgYIFAACAF0aAA==.',Do='Doggak:BAAALAADCggICAAAAA==.',Dr='Draakonn:BAAALAADCgEIAQAAAA==.Dragedisse:BAABLAAECoEWAAIEAAgI6wtMBADOAQAEAAgI6wtMBADOAQAAAA==.Dramalama:BAAALAAECgMIAwABLAAECggIEAABAAAAAA==.Droodya:BAAALAAECgIIAgAAAA==.Drunkenmastr:BAAALAADCggIDgAAAA==.',Du='Duduu:BAAALAAECgQIBgAAAA==.Duduz:BAAALAADCggIDAAAAA==.Dundul:BAAALAADCgQIBAAAAA==.',Dw='Dwarfpaladin:BAAALAAECgYIBwAAAA==.',['Dä']='Dähl:BAACLAAFFIEHAAIYAAMIXyFKAgAyAQAYAAMIXyFKAgAyAQAsAAQKgRsAAhgACAiNHjsKAJsCABgACAiNHjsKAJsCAAAA.',Ea='Eatdemonz:BAAALAAECgQICAAAAA==.',Ec='Echo:BAAALAADCgQIBAAAAA==.',Eg='Egiwninho:BAAALAAECgQICgAAAA==.',El='Elohim:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.Elvspriestly:BAAALAAECgMIAwAAAA==.',En='Engl:BAAALAADCggIDAAAAA==.Entrei:BAAALAAECgMIAwABLAAECggIHQANAPEaAA==.',Er='Erotrix:BAAALAADCgEIAQAAAA==.',Ev='Everec:BAABLAAECoEVAAMXAAcI/iQZBADMAgAXAAcIySQZBADMAgAZAAYIlRwAAAAAAAAAAA==.',Ex='Exyl:BAAALAAECgYIEAAAAA==.',Ey='Eyebeamkek:BAACLAAFFIEIAAIXAAMI1hzcAAAIAQAXAAMI1hzcAAAIAQAsAAQKgRkAAhcACAgAIMUEALMCABcACAgAIMUEALMCAAAA.',Fa='Farstrider:BAAALAADCgYIBgAAAA==.Fasu:BAAALAADCggIEAAAAA==.Fatherdollan:BAAALAADCgcICgAAAA==.Fatnerd:BAABLAAECoEUAAMXAAcIzyGZCQAvAgAZAAcIQR5YHQB0AgAXAAYIsSGZCQAvAgAAAA==.Fatrider:BAAALAAECgYIBgAAAA==.Fazer:BAAALAAECgcIEQAAAA==.',Fe='Femtrei:BAABLAAECoEdAAINAAgI8RqJGQBjAgANAAgI8RqJGQBjAgAAAA==.Fenrahel:BAAALAADCgUIBQABLAAECgYIBgABAAAAAA==.Fereydun:BAAALAAECggIDwAAAA==.',Fi='Firefliestwo:BAAALAADCgYIBgAAAA==.',Fl='Flaye:BAABLAAECoEdAAIHAAgIaRygDQC1AgAHAAgIaRygDQC1AgAAAA==.Fleecoshammy:BAAALAADCgQIBAABLAADCgcIDgABAAAAAA==.Floonz:BAABLAAECoEVAAMJAAgIiBhSJwA4AgAJAAgIiBhSJwA4AgAaAAMIXQvxRQCNAAAAAA==.Flowdark:BAABLAAECoEYAAMNAAgIuBz/DgDGAgANAAgIuBz/DgDGAgAMAAYIuxTgJAB+AQAAAA==.',Fo='Fongar:BAABLAAECoEZAAIPAAgIUBEOPQDhAQAPAAgIUBEOPQDhAQAAAA==.',Fr='Friede:BAAALAAECgQIAwAAAA==.Frommage:BAAALAAECgEIAQAAAA==.',Fu='Fuldtopper:BAAALAADCgcIBwAAAA==.',Ga='Galae:BAAALAADCggICAAAAA==.Gathos:BAABLAAECoEdAAIRAAgIARsNEwCXAgARAAgIARsNEwCXAgAAAA==.Gaurondal:BAABLAAECoEaAAIIAAgIHhXKFwAfAgAIAAgIHhXKFwAfAgAAAA==.',Gh='Ghaka:BAAALAADCgQIBAAAAA==.Ghosti:BAAALAAECgYICAAAAA==.',Gi='Gitalot:BAAALAAECgMIBAAAAA==.',Gj='Gj:BAAALAADCgEIAQAAAA==.',Gl='Glaiverush:BAAALAAECgYICgAAAA==.',Go='Gobblar:BAAALAADCggIDgAAAA==.Goblinus:BAAALAADCggICAAAAA==.Goetia:BAABLAAECoEXAAIPAAcI7xc5OgDtAQAPAAcI7xc5OgDtAQAAAA==.Goldyman:BAAALAAECggICAAAAA==.Gordul:BAABLAAECoEcAAIJAAgI2xVMKQAtAgAJAAgI2xVMKQAtAgAAAA==.Gorebringer:BAAALAADCgIIAgAAAA==.',Gr='Grau:BAABLAAECoEUAAMbAAcILhhKMAASAgAbAAcILhhKMAASAgAUAAYI8xu6GAC1AQAAAA==.Grav:BAAALAAECgMIBQAAAA==.Greenfred:BAAALAAECgcIDAAAAA==.Greenganji:BAAALAADCggIFwAAAA==.Greenrabit:BAAALAADCgcIBwAAAA==.Grislik:BAAALAAFFAEIAQAAAA==.Grokshall:BAAALAADCggIEQAAAA==.',Gu='Gugu:BAAALAAECgYIDAAAAA==.Gurthquake:BAAALAAECgcIDwAAAA==.',['Gö']='Göy:BAAALAAECgUICQAAAA==.',Ha='Hamanda:BAAALAADCgYICgAAAA==.Hammadin:BAAALAAECgEIAgAAAA==.Hammonology:BAAALAADCgYICAABLAAECgEIAgABAAAAAA==.Hanken:BAAALAADCgMIAwAAAA==.Harmónia:BAAALAADCgUIBgAAAA==.Haxx:BAAALAAECgYICgAAAA==.',He='Healatron:BAAALAAECgMIBAAAAA==.Hexluthor:BAAALAAECgQIBAAAAA==.',Hi='Hitnrun:BAAALAADCggIFAAAAA==.Hitraw:BAAALAAECgYIBgAAAA==.',Ho='Holyshook:BAAALAADCgQIBAAAAA==.Hotshot:BAAALAADCggIEAAAAA==.',Hu='Hubnester:BAEALAADCggICAABLAAECgMIAwABAAAAAA==.Hulle:BAAALAAECgUIBwABLAAECggIFQALAIIZAA==.Hullé:BAABLAAECoEVAAILAAgIghkuBQBpAgALAAgIghkuBQBpAgAAAA==.Huntarion:BAAALAAECgYIBgAAAA==.',Hy='Hyberion:BAAALAAECgUICQAAAA==.',Ib='Ibighealu:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Il='Ilens:BAAALAAECgcIEAAAAA==.Ilsinho:BAAALAAECgYIBgAAAA==.',In='Incendia:BAAALAADCgYIBgABLAAECgYIEwABAAAAAA==.Inir:BAAALAAECgYIDgAAAA==.',Ir='Irith:BAAALAADCggIBwAAAA==.',It='Itzadamn:BAAALAADCgIIAgAAAA==.',Iv='Ivoire:BAABLAAECoEdAAISAAgIKh8iDACuAgASAAgIKh8iDACuAgAAAA==.Ivyman:BAAALAAECggIEAAAAA==.',Iz='Izah:BAEALAAECgMIAwAAAA==.',Ja='Jaderra:BAAALAADCggIDAAAAA==.Jahika:BAAALAAECgMIAwAAAA==.Jahimees:BAAALAADCgcICwABLAAECgMIAwABAAAAAA==.Jailbaít:BAAALAAECgYIBgAAAA==.Jarazim:BAAALAADCggIEAAAAA==.Jarizard:BAAALAAECgMIAwAAAA==.Jarnis:BAABLAAECoEdAAIVAAgIhBePFgBjAgAVAAgIhBePFgBjAgAAAA==.Jarnlock:BAAALAADCggICAAAAA==.',Je='Jebako:BAAALAADCgYICgAAAA==.Jepicast:BAAALAAECgYICQAAAA==.',Ji='Jindal:BAAALAADCggICAAAAA==.',Jo='Joejoe:BAACLAAFFIEHAAIPAAMI0BapBQAWAQAPAAMI0BapBQAWAQAsAAQKgR4AAg8ACAjSIr8HACcDAA8ACAjSIr8HACcDAAAA.',Ju='Judochop:BAAALAADCgcIDAAAAA==.',Ka='Kaabulian:BAAALAAECgYIBgAAAA==.Kagul:BAAALAADCgYIBgABLAAECggIFAAIAFMgAA==.Kaiserr:BAAALAAECgIIAgAAAA==.Kale:BAAALAAECgYICAAAAA==.Kanerva:BAAALAADCggICAAAAA==.Karshee:BAAALAADCgEIAQAAAA==.Katrena:BAAALAAECgYIBgAAAA==.Kazidh:BAABLAAECoEXAAMZAAcIBh0zOwDXAQAZAAcIYRQzOwDXAQAXAAQI7iEfFQBuAQAAAA==.',Ke='Kepumies:BAAALAAECgYIDwAAAA==.',Kh='Kheldurin:BAAALAAECgYICQAAAA==.Kho:BAABLAAECoEbAAIVAAgIBRztEQCWAgAVAAgIBRztEQCWAgAAAA==.Khomeyni:BAAALAADCgYIBAAAAA==.',Ki='Killerd:BAAALAAECgEIAQAAAA==.Kiserore:BAAALAADCgQIBQABLAADCgcIBwABAAAAAA==.Kisiel:BAAALAADCggICAAAAA==.Kiyanne:BAAALAAECgYIEAAAAA==.',Ko='Kobean:BAAALAADCgcIBwAAAA==.Kolinia:BAAALAADCgcIBwAAAA==.',Kr='Kraya:BAAALAAECgMIBgAAAA==.Krazzy:BAAALAADCggIEAAAAA==.Kritos:BAAALAADCgUIBQABLAAECggIFQALAIIZAA==.Kritós:BAAALAAECgYICgABLAAECggIFQALAIIZAA==.Kruxi:BAAALAADCgcIDQAAAA==.',Ks='Ks:BAAALAAECggIEgAAAA==.',La='Laillea:BAAALAADCggIEQAAAA==.Landoo:BAAALAAECggIBgAAAA==.Laskur:BAAALAAECgYICAABLAAECgYIDAABAAAAAA==.Laurentius:BAAALAAECgcIDgAAAA==.',Li='Libertiy:BAAALAADCgYIBgAAAA==.Lichuu:BAAALAAECggICAAAAA==.Lickmethin:BAAALAADCgYIDAAAAA==.Lihapulla:BAAALAADCggICAAAAA==.Lillo:BAAALAADCgYIAwABLAAFFAIIBgASAAocAA==.',Lo='Locing:BAAALAAECgMIAwAAAA==.Lockeddown:BAAALAADCgcIBwABLAAECggILAAJACAkAA==.Lokumka:BAAALAAECgUIBQABLAAFFAIIBgAJAPUfAA==.Longshot:BAAALAADCgcICwAAAA==.Losikuhari:BAAALAADCggIFgAAAA==.Loskedemon:BAAALAADCggIDQAAAA==.Loskedragon:BAAALAADCggIGwAAAA==.Loskemonk:BAAALAADCggIDgAAAA==.Loskepaladin:BAAALAAECgUIBQAAAA==.Loskepriest:BAAALAADCggIGAAAAA==.Loskewarrior:BAAALAADCgIIAgAAAA==.',Lu='Lucillius:BAAALAADCgYICAAAAA==.Lumen:BAABLAAECoEUAAIcAAcI/SDOCwAcAgAcAAcI/SDOCwAcAgAAAA==.Lumevo:BAAALAADCgYIBwABLAAECgYIDQABAAAAAA==.Lumsha:BAAALAAECgYIDQAAAA==.',['Lö']='Lökö:BAABLAAECoEdAAIdAAgI8hJwMQC5AQAdAAgI8hJwMQC5AQAAAA==.',Ma='Magesty:BAAALAADCgUIBQAAAA==.Mageymcmage:BAAALAAECgcIEQAAAA==.Majuri:BAAALAAECgMIAwAAAA==.Makemani:BAAALAAECgYIEAAAAA==.Makqti:BAAALAADCggIFgAAAA==.Mantouge:BAAALAAECgcIDwAAAA==.Mart:BAAALAADCgcICgAAAA==.',Me='Megamagus:BAAALAAECgIIAgABLAAECgcIDQABAAAAAA==.Mementomori:BAAALAADCggIDgAAAA==.Merijntje:BAAALAAECgMIBAAAAA==.',Mi='Mi:BAAALAAECgcIDQABLAAFFAIIBgASAAocAA==.Mindrenderi:BAAALAAECggICAAAAA==.Minute:BAAALAAECggIDwABLAAECgYICAABAAAAAA==.',Mo='Monsun:BAAALAADCgUIBQAAAA==.Mooney:BAAALAAECgYIEAAAAA==.Moosmöse:BAAALAAECggIEAAAAA==.Moremats:BAAALAAECgMIBgAAAA==.',Mu='Mupsik:BAAALAAECgMIAwAAAA==.Murus:BAAALAAECgEIAQAAAA==.',My='Mymo:BAAALAADCggICAAAAA==.Mythicdungo:BAAALAAECgEIAQAAAA==.',['Má']='Máttyb:BAAALAAECgYIDgAAAA==.',['Mú']='Múhamme:BAAALAAECgQIBAAAAA==.',Na='Nala:BAAALAADCggIDQAAAA==.Nappitsu:BAAALAADCggICAAAAA==.',Ne='Neerah:BAAALAADCggICAAAAA==.Neulovim:BAAALAAECggIBQAAAA==.Newcowwhodis:BAAALAAECgIIAgAAAA==.',Nh='Nhixni:BAAALAADCggICAAAAA==.',Ni='Niktos:BAABLAAECoEVAAINAAcIsSKSEgCiAgANAAcIsSKSEgCiAgAAAA==.Nirith:BAAALAAECgUIBwAAAA==.Nisse:BAABLAAECoEYAAIeAAcIsxR4FgC7AQAeAAcIsxR4FgC7AQAAAA==.',No='Nohealrolfer:BAAALAADCgUIBQAAAA==.Notcowwhodis:BAAALAADCgUIBQAAAA==.Notholtz:BAAALAAECgYIBAAAAA==.Notsmuel:BAAALAAECgYIDAAAAA==.',Nu='Nuggetman:BAAALAAECgYIBwAAAA==.Nuppuz:BAAALAAECgMIAwAAAA==.Nurofen:BAAALAAECgQICgAAAA==.',Od='Odimm:BAAALAAECgcIDAAAAA==.Odium:BAAALAAECgUIBQAAAA==.',Ol='Oldar:BAAALAAECgYICgABLAAECgcIDAABAAAAAA==.Olidh:BAAALAAECgYIBwAAAA==.',Om='Omegadon:BAAALAADCggIFwAAAA==.Omegashenron:BAAALAAECgMIBAAAAA==.Omnath:BAAALAAECgMIBgAAAA==.',On='Onaturlig:BAAALAAECggIAwAAAA==.Onepoundfish:BAAALAAECgMIAgAAAA==.',Or='Ortri:BAAALAAECgQICQAAAA==.',Os='Ossium:BAAALAAECgYIDQAAAA==.',Ot='Ottanah:BAAALAADCggIEAAAAA==.',Ou='Ouchmybones:BAAALAAECgQIBAAAAA==.',Ow='Owuo:BAAALAAECggIBQAAAA==.',Pa='Pahatonnalli:BAAALAADCggIDQAAAA==.Palatard:BAAALAAECggICwAAAA==.Panne:BAAALAADCgYIBgAAAA==.Parvatí:BAAALAAFFAIIBAAAAA==.Pasiive:BAAALAAECggIEwAAAA==.Pavok:BAAALAAECgEIAQAAAA==.Paxen:BAAALAADCggICAAAAA==.',Ph='Pheonyx:BAABLAAECoEVAAMJAAcI3RzNKwAfAgAJAAcI3RzNKwAfAgAaAAMICw1+RQCQAAAAAA==.Phruity:BAAALAAECgYIEwAAAA==.Phyrexa:BAAALAADCggIEQAAAA==.',Pi='Pistachio:BAAALAADCgYIBQAAAA==.',Pl='Ploxi:BAAALAAECgYIBgAAAA==.',Po='Polikala:BAAALAAECgIIAgAAAA==.Ponga:BAAALAADCggICQAAAA==.Porkloin:BAAALAADCggICQAAAA==.Postponed:BAAALAAECggICAAAAA==.',Pr='Proo:BAAALAAECgYIBgAAAA==.Prínce:BAAALAADCgEIAQAAAA==.',Pu='Putamandown:BAAALAADCgMIAwAAAA==.',Py='Pyroblaast:BAAALAADCgcIDAAAAA==.',Qu='Qudshu:BAABLAAECoEdAAIZAAgIMiPhCQAdAwAZAAgIMiPhCQAdAwAAAA==.Queltals:BAAALAAECggIAgAAAA==.Quzzi:BAAALAAECgIIBAAAAA==.',Ra='Raijdow:BAAALAADCggICAAAAA==.Raketta:BAAALAADCggICAAAAA==.Rakuraido:BAAALAAECgIIBAAAAA==.Rastagangsta:BAAALAADCggICAAAAA==.Rawmeat:BAAALAADCgcICgAAAA==.',Re='Rees:BAAALAADCgEIAQABLAAFFAIIBgASAAocAA==.Regicide:BAAALAAECggIBAAAAA==.Retribúsön:BAAALAAECgUICQAAAA==.',Rg='Rgnarok:BAAALAADCgMIAwAAAA==.',Rh='Rhapidfire:BAAALAAECgYIEwAAAA==.',Ri='Ririth:BAABLAAECoEcAAMNAAgI2RaLHABKAgANAAgINhaLHABKAgAOAAYInBITDACmAQAAAA==.Rissler:BAACLAAFFIEGAAIQAAMI+BesBQDkAAAQAAMI+BesBQDkAAAsAAQKgRoAAhAACAiVJHQDADQDABAACAiVJHQDADQDAAAA.Ristoreipääs:BAAALAADCgQIBAABLAADCggIDQABAAAAAA==.',Ro='Rockwood:BAAALAADCgYIBgAAAA==.Rootnrun:BAAALAADCgcIDgABLAAECgQIBwABAAAAAA==.Rosalindaé:BAAALAAECgIIAgAAAA==.Rosalíndae:BAAALAADCgYIBgAAAA==.Rotjoch:BAAALAAECgIIAgAAAA==.Roubignol:BAAALAADCgEIAgAAAA==.',Sa='Sacredhebrew:BAAALAADCggIEAAAAA==.Saintperky:BAAALAAECgUICQAAAA==.Saketzu:BAAALAAECgYIEQAAAA==.Saladlord:BAAALAAECgYIBgABLAAECgcIFAAXAM8hAA==.Salmonsnake:BAAALAADCggICAAAAA==.Samáar:BAAALAAECgYIEgAAAA==.Sapaca:BAAALAADCgYIBgAAAA==.Sargonakos:BAAALAADCgMIAwAAAA==.Sarkhan:BAAALAADCggICAABLAAECggIFQACAPokAA==.Sarkhani:BAAALAADCggICAABLAAECggIFQACAPokAA==.Sarthas:BAAALAAECgEIAQABLAAECggIFQACAPokAA==.Sattuma:BAAALAADCggICAAAAA==.',Sc='Scarab:BAAALAAECgYIBgAAAA==.',Se='Sec:BAAALAADCgcIBwAAAA==.Sen:BAAALAADCggICQAAAA==.Serv:BAAALAADCggICAAAAA==.Seräph:BAAALAAECggIBgABLAAECggIEgABAAAAAA==.',Sh='Shadowwizard:BAAALAAECgUIBAAAAA==.Shatman:BAAALAAECgcIDQAAAA==.Shatmando:BAAALAAECgMIAwABLAAECgcIDQABAAAAAA==.Shbrorr:BAAALAAECgQICQAAAA==.Shbrror:BAAALAAECgcICgAAAA==.Sheedah:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.Sheepster:BAAALAADCggICwAAAA==.Shelana:BAAALAAECgMIBwAAAA==.Shephiroth:BAAALAADCggIEgAAAA==.Shimira:BAAALAAECgMIAwAAAA==.Sho:BAAALAADCggICwABLAAFFAIIBgASAAocAA==.Shozan:BAAALAAECgQIBAABLAAECgcIFAAcAP0gAA==.',Si='Siinister:BAAALAAECgUICAAAAA==.Sikkz:BAAALAADCgcIBwAAAA==.Sineøchka:BAACLAAFFIEGAAIJAAII9R8SDwDBAAAJAAII9R8SDwDBAAAsAAQKgRIAAgkABghiJCwiAFgCAAkABghiJCwiAFgCAAAA.Sistaboss:BAABLAAECoEVAAIIAAcIrhekGQANAgAIAAcIrhekGQANAgAAAA==.',Sl='Slugg:BAABLAAECoEXAAIHAAcI/xvpFgBJAgAHAAcI/xvpFgBJAgAAAA==.Sluxinator:BAAALAAECgIIAgAAAA==.',Sm='Smexarn:BAAALAADCggICgAAAA==.Smexi:BAAALAADCggICgAAAA==.Smuel:BAAALAADCgIIAgABLAAECgYIDAABAAAAAA==.Smueleo:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Smärsken:BAAALAAECgYIEQAAAA==.',Sn='Snakestick:BAAALAAECgIIAgAAAA==.Sneakywe:BAAALAAECgUICQABLAAECggIAgABAAAAAA==.',So='Somlog:BAAALAADCgYIBgAAAA==.Sonder:BAACLAAFFIEGAAISAAIIChxBDAC4AAASAAIIChxBDAC4AAAsAAQKgRgAAhIACAiNILcHAOkCABIACAiNILcHAOkCAAAA.Soraká:BAABLAAECoEcAAIdAAgIlRqLEgBnAgAdAAgIlRqLEgBnAgAAAA==.',Sp='Sponk:BAAALAAECgMIAwAAAA==.',Sq='Squidgame:BAAALAAECgYIBgAAAA==.',St='Stankelkang:BAAALAAECgUIBQAAAA==.Starbloom:BAAALAAECgYICAAAAA==.',Su='Summer:BAAALAAECgQIBAABLAAFFAIIBgASAAocAA==.Supertom:BAABLAAECoEVAAIdAAYIexxiLwDDAQAdAAYIexxiLwDDAQAAAA==.Surv:BAAALAAECgUIBQAAAA==.',Sy='Synjin:BAAALAAECgYIEQAAAA==.',Sz='Szaman:BAAALAADCggICAAAAA==.Szefandus:BAAALAADCgcIBwAAAA==.',['Sá']='Sárkhan:BAAALAAECgMIAwABLAAECggIFQACAPokAA==.',['Sù']='Sùnzì:BAAALAAECgMIBQAAAA==.',Ta='Taikajimi:BAAALAADCggICAAAAA==.Talaram:BAAALAADCgcIDgAAAA==.Tamran:BAAALAADCgEIAQAAAA==.Tanker:BAAALAADCgEIAQAAAA==.Tauro:BAABLAAECoEXAAMCAAcI/yG5BwCqAgACAAcI/yG5BwCqAgAWAAIILw8QGgCHAAAAAA==.Taytaytay:BAAALAAECggIDAAAAA==.',Te='Tekis:BAAALAADCgYIBgAAAA==.Teyna:BAAALAADCgUIBQAAAA==.',Th='Tharan:BAAALAAECgYIDAAAAA==.Thelaria:BAAALAADCggIEgAAAA==.Thunderbul:BAAALAAECgYICgAAAA==.Thunderdemon:BAAALAAFFAIIAgAAAA==.Thûrim:BAAALAADCgYIBQAAAA==.',Ti='Timoni:BAABLAAECoEdAAIUAAgIDB16BwCLAgAUAAgIDB16BwCLAgAAAA==.Tinaly:BAAALAAECgIIAwAAAA==.',Tl='Tlorem:BAAALAAECgcIDgAAAA==.',To='Tonkadin:BAAALAAECgcIEwAAAA==.Toutos:BAAALAAECgMIBgAAAA==.',Tr='Trôûî:BAAALAADCgMIAwAAAA==.',Tu='Tuatua:BAAALAADCgUIBQAAAA==.Tuck:BAAALAAECgYIEwAAAA==.Tullinkutina:BAAALAADCggICAAAAA==.Turbob:BAAALAADCgYICgABLAAECgYIDQABAAAAAA==.Turskidan:BAAALAADCggIDwAAAA==.Tusinenkurri:BAAALAADCggIBgABLAADCggIDQABAAAAAA==.',Tw='Twochainz:BAAALAAECgUIBQABLAAECgYIDAABAAAAAA==.',Ty='Tyrra:BAAALAADCgcIBwAAAA==.',['Tö']='Töff:BAAALAADCggIDQAAAA==.',Ug='Ug:BAAALAAECgMIAwAAAA==.',Um='Umommon:BAAALAADCgcIDQAAAA==.',Un='Unchiufester:BAAALAAECgcIBwAAAA==.Undeadnoname:BAAALAAECggIAgAAAA==.Unknowndrago:BAAALAADCgIIAgAAAA==.',Uw='Uwuwubby:BAAALAAECgMIBAAAAA==.',Va='Valthor:BAABLAAECoEUAAMDAAYI2yClHAA0AgADAAYI2yClHAA0AgACAAMInxSSMwC3AAAAAA==.Valtura:BAAALAAECgUIDAAAAA==.Vannos:BAAALAAECgUIBwAAAA==.Varthdader:BAAALAADCggICAAAAA==.Vasitanku:BAAALAADCgIIAgAAAA==.',Vc='Vcrina:BAAALAAECggICAAAAA==.',Ve='Velanne:BAAALAADCggIDwAAAA==.Velarasilent:BAAALAAECgMIBQAAAA==.Verihirvitys:BAAALAADCggICwAAAA==.Vestra:BAAALAADCggICAAAAA==.',Vi='Vilkey:BAACLAAFFIEFAAIQAAMI6h22BgDUAAAQAAMI6h22BgDUAAAsAAQKgRkAAhAACAiyJY8DADIDABAACAiyJY8DADIDAAAA.Vindicta:BAAALAADCgcICQAAAA==.Vindictus:BAAALAADCgcIBwAAAA==.Viruke:BAAALAAECgcIEwAAAA==.Vivaldi:BAAALAAECgYIBgABLAAECggIFAAIAFMgAA==.',Vo='Voljinx:BAABLAAECoEgAAMJAAgILx1wFwClAgAJAAgILx1wFwClAgAaAAYInQ1hMQAeAQAAAA==.Volscale:BAAALAAECggIBgABLAAECggIIAAJAC8dAA==.Volzen:BAAALAAECggICAABLAAECggIIAAJAC8dAA==.',Vr='Vr:BAAALAADCggIFQABLAAECgcIDAABAAAAAA==.',Vy='Vyffel:BAAALAAECgMIAwAAAA==.',['Vå']='Vårtmuttan:BAAALAAECggIEQAAAA==.',Wa='Wabshaman:BAAALAAECgYIEwAAAA==.',Wh='Whacko:BAAALAAECgcIDAAAAA==.Whitepaw:BAAALAADCgcICQABLAAECggIGgAQAJcLAA==.',Wi='Windforce:BAAALAADCgMIAwAAAA==.',Wj='Wjurt:BAAALAAECgMIBAAAAA==.',Wl='Wlok:BAAALAADCgcIDQABLAAECgYIBgABAAAAAA==.',Wu='Wupwup:BAAALAAECggIBwAAAA==.',Xi='Xirod:BAAALAAECgUIDQAAAA==.',Xm='Xmagnificent:BAAALAAECgQICAAAAA==.',Ye='Yeezzus:BAAALAADCgcIBwAAAA==.Yespappi:BAAALAAECgMIAwAAAA==.',Yu='Yunalessca:BAAALAAECgYICQAAAA==.',Za='Zapi:BAAALAAECgYIEQAAAA==.Zardrok:BAAALAADCgcIBwAAAA==.Zarkhan:BAABLAAECoEVAAICAAgI+iSKAQBeAwACAAgI+iSKAQBeAwAAAA==.Zarod:BAABLAAECoEUAAILAAcIPSOTAwC1AgALAAcIPSOTAwC1AgAAAA==.Zath:BAAALAAECgEIAQAAAA==.Zayusha:BAAALAADCggICAAAAA==.',Ze='Zedar:BAAALAADCggICwABLAAECgYIDAABAAAAAA==.Zedarz:BAAALAADCgUIBQABLAAECgYIDAABAAAAAA==.Zedmoon:BAAALAAECgYIDAAAAA==.Zedshammy:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.',Zi='Zikao:BAAALAAECgQIDwAAAA==.',Zo='Zozomatcha:BAAALAADCgcICAAAAA==.',['Zé']='Zéd:BAAALAAECgMIAwAAAA==.',['Èa']='Èarthen:BAABLAAECoEaAAIQAAgIlwvRNwBEAQAQAAgIlwvRNwBEAQAAAA==.',['Éo']='Éowyn:BAAALAAECgYIEQAAAA==.',['Ín']='Ínternet:BAAALAADCggIDAAAAA==.',['Óp']='Ópe:BAAALAAECgcICgAAAA==.',['Ög']='Ögö:BAAALAADCgcIDQAAAA==.',['Ök']='Ökö:BAAALAAECgMIAwAAAA==.',['Öl']='Ölö:BAAALAAECgQICAAAAA==.',['ßa']='ßallz:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end