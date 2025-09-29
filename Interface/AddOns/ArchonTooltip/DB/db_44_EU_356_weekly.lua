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
 local lookup = {'Hunter-BeastMastery','Mage-Frost','Warrior-Arms','Shaman-Restoration','Unknown-Unknown','Druid-Restoration','Druid-Guardian','Druid-Balance','Rogue-Assassination','Priest-Discipline','Priest-Shadow','Paladin-Protection','DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Warlock-Destruction','Evoker-Devastation','Warrior-Fury','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Frost','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Evoker-Augmentation','Monk-Brewmaster','Paladin-Holy','Mage-Arcane','Rogue-Outlaw',}; local provider = {region='EU',realm='Arakarahm',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abussos:BAACLAAFFIEGAAIBAAIIVg+HLgCIAAABAAIIVg+HLgCIAAAsAAQKgSQAAgEACAjDGDRNAPIBAAEACAjDGDRNAPIBAAAA.',Ae='Aejidk:BAAALAAFFAIIAgAAAA==.',Ai='Aight:BAAALAAECgcIEgAAAA==.Airmure:BAAALAAECgMIAwAAAA==.',Al='Alou:BAAALAADCggICAAAAA==.Altéa:BAAALAAECgcIDQAAAA==.',Am='Amo:BAAALAADCgIIAgAAAA==.',An='Ancalag:BAAALAADCgcIBwAAAA==.Androrym:BAAALAAECgYICgAAAA==.Anilgarian:BAAALAADCgcIBwAAAA==.Ankalian:BAAALAADCgYIBgAAAA==.',Ar='Araonne:BAABLAAECoEVAAICAAcIYBxzFABWAgACAAcIYBxzFABWAgAAAA==.Arganis:BAAALAADCgQIBAAAAA==.Arnito:BAAALAADCggIDwAAAA==.Arwen:BAAALAAECgEIAgAAAA==.',As='Asmodée:BAAALAAECgQIBQAAAA==.',At='Atøg:BAAALAADCgcIBgAAAA==.',Az='Azahel:BAAALAAECgYIDAAAAA==.',Ba='Baelin:BAABLAAECoEZAAIDAAgIQxcmCABNAgADAAgIQxcmCABNAgAAAA==.Baidorn:BAAALAAECgcIEAAAAA==.Balek:BAAALAADCgYIBgAAAA==.',Bi='Biijû:BAAALAADCggICAAAAA==.',Bl='Bloodgore:BAAALAAECgYIDQAAAA==.Blork:BAAALAAECgYICAAAAA==.Blörk:BAABLAAECoEdAAIEAAgI2RZbNAAbAgAEAAgI2RZbNAAbAgAAAA==.',Bo='Bouffemoileq:BAAALAAFFAIIAgAAAA==.',Br='Braxor:BAAALAAECgUIBwAAAA==.Brocolis:BAAALAADCgIIAgABLAAECgEIAQAFAAAAAA==.Broleo:BAACLAAFFIEKAAIGAAQIGxJPBwAtAQAGAAQIGxJPBwAtAQAsAAQKgSgAAgYACAiLIGUKAOwCAAYACAiLIGUKAOwCAAAA.',Ca='Ca:BAAALAAECgcIDgAAAA==.',Ch='Chakah:BAAALAAECgIIBAAAAA==.Chasstout:BAAALAADCggIDwAAAA==.Chirokee:BAABLAAECoEgAAIEAAgI6h2xFQCqAgAEAAgI6h2xFQCqAgAAAA==.',Ci='Citrêve:BAACLAAFFIEQAAIHAAUI8RhpAADBAQAHAAUI8RhpAADBAQAsAAQKgSkAAgcACAg0I9oBADADAAcACAg0I9oBADADAAAA.',Cl='Clamidya:BAAALAADCgcICAAAAA==.Clodowood:BAABLAAECoEoAAMGAAgI3h02JAApAgAGAAgI3h02JAApAgAIAAUIFggsZQDVAAAAAA==.',Co='Coldu:BAAALAADCgcIBwAAAA==.Corvo:BAABLAAECoEVAAIJAAcIiRaYIAD7AQAJAAcIiRaYIAD7AQAAAA==.Coryphée:BAABLAAECoEYAAIBAAcIGRxbQwAPAgABAAcIGRxbQwAPAgAAAA==.',Cr='Crakiî:BAAALAAECgMIAwABLAAECgcIBwAFAAAAAA==.Craquemine:BAAALAADCgYIBgAAAA==.',['Cø']='Cøryphée:BAAALAADCggIIwAAAA==.',De='Deomund:BAAALAAECgYIBgAAAA==.Destructo:BAAALAADCgIIAgAAAA==.',Di='Dinde:BAABLAAECoEkAAMKAAYIKiZqAwCXAgAKAAYIKiZqAwCXAgALAAYIPRfbPAClAQABLAAFFAMICgAMANAYAA==.Disciel:BAAALAAECgYICwAAAA==.Diäna:BAAALAADCgcIHgAAAA==.',Do='Docypal:BAAALAADCgYIBgAAAA==.Doktos:BAAALAADCggIEAAAAA==.',Dr='Drakaïna:BAABLAAECoEUAAMNAAcIhAkQNADnAAAOAAcILQWRvgARAQANAAYIIQoQNADnAAAAAA==.Droodballe:BAAALAAECgcIEQAAAA==.Dräed:BAAALAAECgEIAQAAAA==.',Du='Durin:BAAALAAECgEIAwAAAA==.Duumjuu:BAABLAAECoEXAAIGAAYIBA4qZAAjAQAGAAYIBA4qZAAjAQAAAA==.',Dw='Dwy:BAABLAAECoEVAAMPAAcIuh/fFwAbAgAPAAYILh/fFwAbAgAQAAIIAx/JIgC0AAAAAA==.',['Dü']='Düm:BAABLAAECoEjAAIRAAgIVCGKEwASAwARAAgIVCGKEwASAwAAAA==.',Ea='Eagon:BAAALAADCgcIBwAAAA==.',Ek='Ekyo:BAAALAAECgcIDQAAAA==.',El='Ellendyl:BAAALAAECgMIAwAAAA==.Elorea:BAAALAAECgIIAgAAAA==.',Ep='Epona:BAAALAAECggIIAAAAQ==.Epopopo:BAAALAADCgYIBgABLAAECggIIAAFAAAAAQ==.',Et='Eturnos:BAAALAAECgYIBwAAAA==.',Ex='Expansion:BAAALAADCgcIBwAAAA==.',Ey='Eyleen:BAAALAAECgQIBwAAAA==.Eytu:BAAALAADCggICwABLAAECgYIEwAFAAAAAA==.',Ez='Eziiliana:BAABLAAECoEUAAISAAcIyArUbAB0AQASAAcIyArUbAB0AQAAAA==.',['Eä']='Eäril:BAAALAAECgYICQABLAAECggIJgABAP8kAA==.',Fa='Faris:BAAALAAECgYIEwAAAA==.',Fe='Feï:BAAALAAECgcIEAAAAA==.',Fo='Foxouille:BAABLAAECoEUAAITAAcIZB/8EgB8AgATAAcIZB/8EgB8AgAAAA==.',Fr='Frosh:BAAALAAECgMIAwAAAA==.',['Fé']='Félinvif:BAAALAAECgYIBgAAAA==.',Gl='Glaurung:BAAALAAECgcICQAAAA==.Glavidos:BAAALAADCgcIBwAAAA==.',Go='Gordon:BAAALAAECgYIBgAAAA==.Gornit:BAABLAAECoEbAAMUAAgIFxXdXgCVAQAUAAgIZRTdXgCVAQADAAIIBBsUKAB8AAAAAA==.',Gr='Greylogger:BAAALAADCgcIBwAAAA==.Græbuge:BAABLAAECoEcAAMVAAgIXCFgBADPAgAVAAgIIiBgBADPAgAWAAgIfBsWMAAfAgAAAA==.Græbuuge:BAAALAAECgQIBAABLAAECggIHAAVAFwhAA==.',Ha='Halzhadk:BAABLAAECoEWAAIXAAcIkBdQZgDyAQAXAAcIkBdQZgDyAQAAAA==.',He='Helraiser:BAAALAADCggIHQAAAA==.Herraclès:BAAALAADCggICAAAAA==.Hexia:BAAALAAECggIEAAAAA==.',Ho='Horassio:BAABLAAECoEnAAIXAAcIhBXiegDIAQAXAAcIhBXiegDIAQAAAA==.',Hu='Hurakan:BAAALAAECgYICgAAAA==.',Hy='Hypertruite:BAAALAADCgcIBgAAAA==.',In='Injen:BAAALAAECgYIEAAAAA==.Instinkt:BAAALAAECgUIBQAAAA==.Intani:BAAALAAECgYICAAAAA==.',Ja='Jarvix:BAAALAAECgYICQABLAAECgYIEwAFAAAAAA==.',Je='Jeanbabus:BAAALAAECgcIEQAAAA==.Jenthrin:BAAALAAECggIEwAAAA==.Jessicæ:BAAALAAECggICAAAAA==.',Ji='Jinjer:BAAALAADCggICAAAAA==.',Jo='Joice:BAABLAAECoEVAAIRAAcI6xm8UAAeAgARAAcI6xm8UAAeAgAAAA==.Jokerizi:BAAALAADCgYIBgAAAA==.',Ju='Justoar:BAABLAAECoEUAAIGAAcIkRI4SgB7AQAGAAcIkRI4SgB7AQAAAA==.',Jy='Jyanna:BAAALAAECggICAAAAA==.',Ka='Kaakon:BAAALAAFFAIIAwAAAA==.Kagàho:BAAALAADCgEIAQAAAA==.',Ke='Keithfula:BAAALAAECggICAAAAA==.Keithfulap:BAAALAAECgYIBgABLAAECggICAAFAAAAAA==.Keithfulla:BAAALAADCgcIDAABLAAECggICAAFAAAAAA==.Keithfullaap:BAAALAAECggICAABLAAECggICAAFAAAAAA==.Kembei:BAAALAADCgcIBwAAAA==.Kenreal:BAAALAADCgcIBwABLAAECggIFgAYAIQbAA==.',Kh='Khaös:BAABLAAECoEVAAIZAAcIdh/kCwB9AgAZAAcIdh/kCwB9AgAAAA==.Khòdor:BAAALAAECgMIBAAAAA==.',Kk='Kkffaappee:BAAALAAECgYICQABLAAECggICAAFAAAAAA==.',Ko='Koragal:BAAALAADCgUIBQABLAAECgYIEAAFAAAAAA==.',Kr='Krazmots:BAACLAAFFIEIAAILAAMIghdNDAD6AAALAAMIghdNDAD6AAAsAAQKgRkAAgsACAihI2gNAPcCAAsACAihI2gNAPcCAAAA.Kre:BAACLAAFFIEQAAIOAAUI0BrtBQDqAQAOAAUI0BrtBQDqAQAsAAQKgSkAAg4ACAjUJQwFAGYDAA4ACAjUJQwFAGYDAAAA.',Ku='Kurgirauth:BAAALAADCgEIAQAAAA==.Kuviera:BAAALAAECgYICAAAAA==.',La='Laeryl:BAAALAAECgYIBgABLAAECgYIEwAFAAAAAA==.Lamortte:BAAALAADCgQIBAAAAA==.Lamriwen:BAAALAAECgEIAQAAAA==.Larss:BAAALAAECgYIBgAAAA==.Lauktar:BAACLAAFFIEHAAIIAAQItw9FBwA5AQAIAAQItw9FBwA5AQAsAAQKgSsAAggACAhbITwNAOcCAAgACAhbITwNAOcCAAAA.Laurelia:BAAALAAECgcIEQAAAA==.Laëvateïn:BAABLAAECoEUAAIBAAcIKhOecQCWAQABAAcIKhOecQCWAQAAAA==.',Le='Lelei:BAAALAADCggIEQABLAAECgYIEwAFAAAAAA==.',Li='Lili:BAAALAADCggICAAAAA==.Lilweez:BAAALAADCgcICAAAAA==.Liskarm:BAAALAAECggIEwAAAA==.',Lo='Lorix:BAAALAAECgUIBQABLAAFFAQICgAaAH8UAA==.Lozephir:BAAALAAECgYICQAAAA==.',Lu='Lumenos:BAAALAADCgcIBwAAAA==.Lurog:BAAALAAECggICAAAAA==.',Ly='Lyona:BAAALAAECggIEAAAAA==.',Ma='Maeglino:BAACLAAFFIEKAAIGAAMIqyPkBgA4AQAGAAMIqyPkBgA4AQAsAAQKgSgAAgYACAidJLkCAE4DAAYACAidJLkCAE4DAAAA.Malyzelle:BAAALAADCggIDwAAAA==.Mashirø:BAAALAAECgMIAQAAAA==.Mathisx:BAAALAADCgcIBwAAAA==.Maïhla:BAAALAADCggICAAAAA==.',Me='Medik:BAAALAAECgYIDQAAAA==.',Mo='Moonlïght:BAAALAADCgcIDAAAAA==.Morigan:BAAALAADCgcICgAAAA==.',Mu='Mujika:BAAALAADCgcIBwAAAA==.Muu:BAAALAADCgcIBwAAAA==.',My='Mytralalaa:BAAALAAECgYIDQAAAA==.',['Mø']='Møltes:BAAALAADCgcIDQAAAA==.Mørt:BAABLAAECoEnAAMPAAgIzRd7EwBAAgAPAAgIzRd7EwBAAgAQAAMIdg5zIwCuAAAAAA==.',Ne='Nefine:BAAALAADCgcICQAAAA==.Nekros:BAABLAAECoEUAAIXAAcIkhOybgDhAQAXAAcIkhOybgDhAQAAAA==.Nerays:BAAALAADCgQIBAAAAA==.Nervosa:BAAALAAECgcIEQAAAA==.',Ni='Nillia:BAABLAAECoEdAAITAAgISBqrEwB1AgATAAgISBqrEwB1AgAAAA==.Nitael:BAAALAADCggIDgAAAA==.Nitaël:BAABLAAECoEWAAMMAAYIigYbQADYAAAMAAYIigYbQADYAAARAAEIrgVYRAEnAAAAAA==.',No='Noadkoko:BAAALAAECgcIDwAAAA==.Nobodhia:BAAALAAECgcIBwABLAAFFAIIBQAbADkQAA==.Nobomonkia:BAACLAAFFIEFAAIbAAIIORAGDQCWAAAbAAIIORAGDQCWAAAsAAQKgTAAAxsACAjVHPsMAGwCABsACAjVHPsMAGwCABgABwgpG6UWACoCAAAA.Nocap:BAAALAADCgQIBAAAAA==.Nokomis:BAAALAADCgcIBwABLAAECggIDwAFAAAAAA==.Nomara:BAAALAAECgYIBgAAAA==.Noxtradamiis:BAAALAAECggIAwAAAA==.',Ny='Nyanta:BAAALAADCgYIBgAAAA==.Nymphadoras:BAAALAADCggICAAAAA==.Nyzia:BAABLAAECoElAAIcAAgImiJRCQAPAwAcAAgImiJRCQAPAwAAAA==.',Oc='Ochio:BAAALAAECgIIAgABLAAFFAUIDwAYAAoiAA==.',Ok='Oksana:BAAALAADCgIIAgAAAA==.Okstrasza:BAABLAAECoEXAAMdAAcIyA+9DAA7AQATAAcIrghfNQBbAQAdAAUI1xG9DAA7AQAAAA==.',Om='Omio:BAABLAAECoEZAAMSAAYIDhtlUQDGAQASAAYIUxllUQDGAQAPAAQISxaZSAAnAQAAAA==.',Or='Orcouette:BAAALAAECgUIBwABLAAECgcIDQAFAAAAAA==.',Ou='Oukir:BAAALAADCgcIBwAAAA==.',['Oð']='Oðinn:BAAALAAECgYICQAAAA==.',Pa='Palaeji:BAAALAADCgYIBgAAAA==.Paldou:BAAALAAECggIEwAAAA==.Paléo:BAAALAAECgcIEwAAAA==.Papaye:BAAALAADCggICAAAAA==.Pastèque:BAAALAAECgEIAQAAAA==.Pastøre:BAAALAAECgIIAgAAAA==.Pattopesto:BAABLAAECoEaAAIUAAcI2Q2tXACcAQAUAAcI2Q2tXACcAQAAAA==.',Pe='Persondead:BAAALAAECgcICwAAAA==.Pewpewdou:BAAALAAECgYICgAAAA==.',Pi='Pikouzz:BAAALAADCgYIBgAAAA==.Pil:BAAALAAECggIEQAAAA==.Pinke:BAAALAAECgcIEgAAAA==.',Po='Poupoulidor:BAAALAADCgQIBAAAAA==.',Pr='Prøxyyø:BAAALAADCgYIBgAAAA==.',Pu='Putoiparfumé:BAAALAADCggICgAAAA==.',Ra='Ragdahk:BAAALAADCggICQAAAA==.',Ri='Rilo:BAAALAAECgMIAQAAAA==.',Ro='Rodwolf:BAAALAAECgMIAwAAAA==.Rolfwow:BAAALAAECgUIDAAAAA==.',Sa='Sanda:BAAALAADCgcIBwAAAA==.Satsujinlock:BAAALAAFFAIIAgAAAA==.',Se='Sea:BAACLAAFFIEPAAIYAAUICiJKAQALAgAYAAUICiJKAQALAgAsAAQKgS8AAxgACAhxJtoAAIADABgACAhxJtoAAIADAB4AAQi8G9E7AFAAAAAA.Seiradji:BAAALAAECggIDwAAAA==.Sekhmett:BAAALAADCgIIAgAAAA==.Senek:BAAALAAECgcIDgAAAA==.',Sf='Sfyle:BAAALAADCgcIBwABLAAECggIHQAcAFMaAA==.',Sh='Shadoweak:BAABLAAECoEUAAIcAAYIGhHKVQBZAQAcAAYIGhHKVQBZAQAAAA==.Shinmoku:BAAALAAECgQIBgABLAAECgcIDgAFAAAAAA==.',Si='Silline:BAAALAAECgUIBQABLAAECggIJQAcAJoiAA==.Sinisia:BAAALAAECgMIAwAAAA==.',So='Sombrosh:BAABLAAECoEUAAIVAAcIiBvICQA0AgAVAAcIiBvICQA0AgAAAA==.Sotéria:BAAALAADCggIDQAAAA==.',Sp='Spectrum:BAABLAAECoEUAAIUAAcIaQwkYwCJAQAUAAcIaQwkYwCJAQAAAA==.',St='String:BAAALAADCgYIDgAAAA==.',Su='Sulimous:BAAALAAECgUIBwAAAA==.Sunnyy:BAAALAAFFAIIAwAAAA==.Sunshield:BAABLAAECoEcAAMMAAcIIB8iDwBfAgAMAAcIix4iDwBfAgARAAQIsxbM6wDgAAAAAA==.',Sw='Swixie:BAAALAAECggIBQAAAA==.',Ta='Tankouo:BAAALAADCgEIAQAAAA==.Tapedur:BAAALAADCgUIBQAAAA==.Tatasuzanne:BAAALAAECgUIDAAAAA==.',Th='Thais:BAAALAADCgMIAwAAAA==.Tharakas:BAAALAAECgMIBQAAAA==.Theta:BAAALAAECgYIDgAAAA==.Thundercow:BAAALAADCgQIBAAAAA==.',To='Toguheal:BAABLAAECoEdAAIcAAgIUxqcKgAbAgAcAAgIUxqcKgAbAgAAAA==.Togurogue:BAAALAADCggICAAAAA==.Torydon:BAAALAAECgYIDQAAAA==.',Tr='Traycy:BAAALAAECgMIAQAAAA==.Treazchan:BAAALAAECggIEwAAAA==.Triskèle:BAAALAAECgUIAgAAAA==.Tristétoile:BAAALAAECgQIBQAAAA==.Trëvil:BAAALAAECgYIBgAAAA==.',Ty='Tylezia:BAAALAADCggIEAABLAAECgYIEwAFAAAAAA==.',['Tö']='Töxba:BAAALAAECgYIDAAAAA==.',Va='Valislas:BAACLAAFFIEFAAIfAAII9xAWEwCZAAAfAAII9xAWEwCZAAAsAAQKgSMAAx8ACAiSID8GAOoCAB8ACAiSID8GAOoCABEAAQjQICEmAVYAAAAA.Valk:BAABLAAECoEVAAMCAAcI3RJTKQC3AQACAAcIzhJTKQC3AQAgAAIIUAVb0gBNAAAAAA==.Valnala:BAAALAAECgUICQAAAA==.Valoche:BAABLAAECoEgAAIgAAgI0BcZOgA/AgAgAAgI0BcZOgA/AgAAAA==.',Vi='Vickys:BAAALAAECgMIAQAAAA==.',['Vä']='Välek:BAAALAADCgYIBgAAAA==.',Wa='Wallas:BAAALAADCgcIBwAAAA==.',Wy='Wynthor:BAAALAADCgEIAQAAAA==.',Xe='Xenar:BAAALAADCgMIAwAAAA==.Xeven:BAAALAAECgYIDAAAAA==.',Xn='Xnaja:BAABLAAECoEaAAIOAAgIvRSlUQD/AQAOAAgIvRSlUQD/AQAAAA==.Xnar:BAABLAAECoEZAAMWAAcI/BkjRADDAQAWAAYIfRkjRADDAQAEAAcIvxOjYgCNAQABLAADCgMIAwAFAAAAAA==.',Xo='Xool:BAACLAAFFIEKAAIaAAQIfxQ2BAA9AQAaAAQIfxQ2BAA9AQAsAAQKgRgAAhoACAhRISAIALcCABoACAhRISAIALcCAAAA.',['Xà']='Xànnà:BAAALAAECgYIEAAAAA==.',Yo='Yorgal:BAACLAAFFIEPAAIDAAUIfBk5AADiAQADAAUIfBk5AADiAQAsAAQKgSsAAgMACAjjJUkAAIUDAAMACAjjJUkAAIUDAAAA.',['Yü']='Yüjin:BAAALAADCgYIBgAAAA==.',Zo='Zorin:BAAALAAECgMIBQABLAAFFAUICgAgAGoVAA==.',Zu='Zulkezar:BAACLAAFFIEGAAICAAMIAA3gBADWAAACAAMIAA3gBADWAAAsAAQKgSsAAgIACAh9JOUDAEYDAAIACAh9JOUDAEYDAAAA.Zumbacaféw:BAABLAAECoEbAAIhAAYItyK1BABoAgAhAAYItyK1BABoAgABLAAFFAUIDwAYAAoiAA==.',['Zø']='Zørline:BAAALAAECgcIEQAAAA==.',['Ðo']='Ðoom:BAAALAAECgYIDwAAAA==.',['Ôr']='Ôrccrô:BAAALAAECgcIDQAAAA==.',['Öt']='Öták:BAAALAAECgYIBgABLAAFFAMICAALAIIXAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end