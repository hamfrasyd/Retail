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
 local lookup = {'Unknown-Unknown','Rogue-Assassination','Paladin-Retribution','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','DeathKnight-Blood','Warlock-Affliction','Warlock-Destruction','Druid-Guardian','Shaman-Enhancement','Hunter-Marksmanship','Warrior-Protection','Druid-Restoration','Mage-Arcane','Hunter-BeastMastery','Evoker-Devastation','Priest-Holy','DeathKnight-Unholy','Paladin-Protection','Priest-Shadow','DemonHunter-Havoc','Shaman-Elemental','Paladin-Holy','Warrior-Fury','Mage-Frost','Shaman-Restoration','Hunter-Survival','Evoker-Preservation','Druid-Balance','Warlock-Demonology',}; local provider = {region='EU',realm='Neptulon',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abbadon:BAAALAAECgEIAQABLAAECggIDAABAAAAAA==.Abella:BAABLAAECoEnAAICAAgIFBoiEgB9AgACAAgIFBoiEgB9AgAAAA==.',Ac='Accadius:BAAALAAECgEIAQAAAA==.',Ae='Aevelaine:BAAALAAECgEIAQAAAA==.',Ai='Aibo:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.',Ak='Akuma:BAAALAAECggICwAAAA==.',Al='Alarya:BAAALAAECggIBwAAAA==.Alleluja:BAAALAADCgUIBQABLAAECggIDAABAAAAAA==.',Am='Amateria:BAAALAADCggIEgAAAA==.Amoniel:BAAALAADCgUIBQAAAA==.',An='Andoon:BAAALAAECggIBgABLAAECggIBwABAAAAAA==.Anthodas:BAABLAAECoEXAAIDAAgI1h0bLACVAgADAAgI1h0bLACVAgAAAA==.',Ar='Arcanius:BAAALAAECgcIDQAAAA==.Ariannae:BAAALAADCgcIBwABLAAECgcIGgAEAE4jAA==.Armina:BAAALAAECggICAAAAA==.',As='Asminare:BAAALAAECgYIDAAAAA==.Asome:BAABLAAECoEZAAIFAAgIwRJKFwDVAQAFAAgIwRJKFwDVAQAAAA==.',Ba='Balta:BAABLAAECoEfAAIGAAgIcgkOKgB6AQAGAAgIcgkOKgB6AQAAAA==.Balthur:BAAALAADCggICAABLAAECggIDAABAAAAAA==.Barbatheo:BAAALAAECgYIDAAAAA==.Batkata:BAAALAADCgYICQAAAA==.',Be='Betongarn:BAAALAAECgcIBwAAAA==.',Bg='Bggazar:BAAALAADCggICwAAAA==.Bgterror:BAAALAADCgIIAgAAAA==.',Bi='Biberka:BAAALAAECgYICgAAAA==.Bibizdk:BAABLAAECoEfAAIHAAcIcSB6MQCCAgAHAAcIcSB6MQCCAgAAAA==.Biliana:BAAALAAECgYIEwAAAA==.',Bl='Bladey:BAAALAAECgIIBAAAAA==.Blueais:BAAALAADCggICwAAAA==.Bluut:BAAALAADCggICAAAAA==.',Bo='Boingo:BAAALAAECgUICwAAAA==.Bokluk:BAAALAAECgYIEgAAAA==.Bop:BAAALAADCggICAAAAA==.',Br='Brionac:BAAALAAECgYIDAABLAABCgQIBAABAAAAAA==.',Bu='Bubkin:BAAALAADCgIIAgAAAA==.',Ca='Camellya:BAAALAAECgYIBgAAAA==.',Ch='Chicksmagnet:BAAALAAECgIIAgAAAA==.Choriest:BAABLAAECoEYAAIIAAgI+RlYBABqAgAIAAgI+RlYBABqAgAAAA==.Chorrior:BAAALAADCgMIBAAAAA==.',Cl='Clash:BAAALAAECgIIBAAAAA==.',Co='Combatform:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Cr='Critcobain:BAAALAADCgQIAgAAAA==.Cryxus:BAAALAAECgYICQAAAA==.',['Cì']='Cìara:BAAALAADCggIDgABLAAECgYICQABAAAAAA==.',Da='Danail:BAAALAAECgYIDwAAAA==.',De='Deardevill:BAAALAAECgYIBgAAAA==.Delé:BAABLAAECoEXAAMHAAgI7xR0XAAFAgAHAAgIBBR0XAAFAgAJAAEIVhkOOQBLAAAAAA==.',Di='Dianiza:BAABLAAECoEjAAMKAAgIYSMzAQBAAwAKAAgIYSMzAQBAAwALAAgI7RYcQAACAgAAAA==.Distinctive:BAAALAAECgcIEQAAAA==.Ditkaa:BAAALAADCggICAAAAA==.',Do='Dobatt:BAAALAAECgMIAwAAAA==.Doris:BAABLAAECoEUAAIMAAgIXRWjDADOAQAMAAgIXRWjDADOAQAAAA==.',Dp='Dpsheal:BAAALAAECgYIDgAAAA==.',Du='Dunderhonung:BAABLAAECoEbAAINAAgI4BwOBwB9AgANAAgI4BwOBwB9AgAAAA==.Durek:BAAALAAECgUIBQABLAAECggIBwABAAAAAA==.Duskshade:BAAALAAECggIBwAAAA==.',Ee='Eechoo:BAAALAAECgYICwAAAA==.',El='Elamide:BAABLAAECoElAAIOAAgIaha+JQAkAgAOAAgIaha+JQAkAgAAAA==.Elatemioshte:BAAALAADCggICAAAAA==.Ellevill:BAAALAADCggIFAAAAA==.Elu:BAAALAAECgcIAgABLAAECggIHAADADIVAA==.',Em='Emika:BAAALAAECgQIBAABLAAECggIHwAPAEUdAA==.Emopanda:BAAALAADCgIIAgAAAA==.',En='Enandia:BAAALAAECggIDAAAAA==.Enjävlademon:BAAALAAECgIIAgAAAA==.',Er='Erinée:BAABLAAECoEVAAIQAAgIrRvnGgBdAgAQAAgIrRvnGgBdAgAAAA==.',Ey='Eyleen:BAABLAAECoEWAAIRAAcIhBx8OwA4AgARAAcIhBx8OwA4AgAAAA==.',Fa='Fairly:BAAALAAECgYIDgAAAA==.Falippas:BAAALAAECgYICgAAAA==.Fangubangu:BAAALAADCggICAAAAA==.',Fe='Feles:BAABLAAECoEeAAISAAgIig5PZgCqAQASAAgIig5PZgCqAQAAAA==.Felisin:BAAALAAECgYICgABLAAECgcIGgAEAE4jAA==.',Fj='Fjolnir:BAAALAAECggIEwAAAA==.',Fo='Foreingar:BAAALAADCggIDQAAAA==.',Fr='Freebanz:BAAALAAECgYIEQAAAA==.',Fu='Fugicavin:BAAALAADCggICAABLAAECgcIGgAEAE4jAA==.Fumika:BAAALAADCggIEAAAAA==.Furaffinity:BAABLAAECoEXAAITAAgIRg4gJQDMAQATAAgIRg4gJQDMAQAAAA==.',Ga='Gadnqrat:BAAALAADCgUIBQAAAA==.',Gj='Gjeddi:BAAALAADCggIDgAAAA==.',Gl='Gladiatorat:BAAALAAECgcIEQAAAA==.',Go='Goblinhood:BAAALAAECgIIAgAAAA==.',Gr='Grimgorn:BAAALAAECggIDAAAAA==.Grimgørn:BAAALAAECgIIAgABLAAECggIDAABAAAAAA==.Grudgebearer:BAAALAADCgYICgAAAA==.Grux:BAABLAAECoEWAAIUAAcIwhhUNADkAQAUAAcIwhhUNADkAQAAAA==.Gróm:BAAALAAECgIIAwAAAA==.',Ha='Hagoromo:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.Hamali:BAAALAADCggICAAAAA==.Harshlock:BAAALAADCggICAAAAA==.Hasonlol:BAAALAADCgIIAgAAAA==.Haylah:BAAALAADCgcIBwABLAAECggIFgAVALkgAA==.',He='Hearse:BAABLAAECoEVAAIWAAYIbiD7FAAaAgAWAAYIbiD7FAAaAgAAAA==.',Hi='Hillel:BAABLAAECoEXAAIXAAYIOBRPPwCXAQAXAAYIOBRPPwCXAQAAAA==.',Ho='Hopparen:BAAALAADCgQIBQAAAA==.',Hy='Hydonna:BAABLAAECoEjAAIYAAgIzRkRMwBiAgAYAAgIzRkRMwBiAgAAAA==.',['Hø']='Høly:BAAALAAECgYIBAABLAAECgcIFQAXAG4ZAA==.',Ic='Icegirl:BAAALAADCggICAAAAA==.',Im='Imhunt:BAAALAAECgQIBAABLAAFFAIIAgABAAAAAA==.Immortall:BAAALAADCgYIBgAAAA==.',In='Inorog:BAAALAAECgcIEQABLAAECggIEAABAAAAAA==.Involka:BAAALAADCgcIBwAAAA==.',It='Ithira:BAAALAAECgcIDAAAAA==.',Ja='Jackdragon:BAABLAAECoEfAAIPAAgIRR38DQCnAgAPAAgIRR38DQCnAgAAAA==.Jafree:BAAALAADCgUIBQAAAA==.Janienight:BAABLAAECoEfAAIOAAgIQgsqTABlAQAOAAgIQgsqTABlAQAAAA==.',Je='Jeonsa:BAABLAAECoEjAAMFAAgIFRkVDgBZAgAFAAgIFRkVDgBZAgAGAAcIzQe8MgA8AQAAAA==.',Ju='Juuman:BAAALAADCggICAAAAA==.',['Jö']='Jörd:BAAALAAECgQICQAAAA==.',Ka='Kalrush:BAAALAAECgUICgAAAA==.Kangaro:BAAALAAECgYIEgAAAA==.Karlsons:BAABLAAECoEZAAINAAcI3BSFDQDkAQANAAcI3BSFDQDkAQAAAA==.Karnivall:BAAALAAECgYICQABLAAECgcIBwABAAAAAA==.Kateiroc:BAAALAADCggICAAAAA==.',Ke='Kementári:BAAALAAECgQIBgAAAA==.',Kl='Klodrik:BAAALAAECgYICQAAAA==.',Kn='Knifeyminaj:BAAALAADCggICAAAAA==.',Ko='Kolossen:BAAALAAECgUIBwAAAA==.',Kr='Krisona:BAABLAAECoEWAAIDAAcIthGXfAC5AQADAAcIthGXfAC5AQAAAA==.',Ku='Kufa:BAAALAAECgUIBwAAAA==.',['Kö']='Körösi:BAAALAAECgUIBQAAAA==.',La='Lasaros:BAAALAAECgMIAwAAAA==.',Le='Lebiath:BAAALAAECgYIEAAAAA==.Leh:BAABLAAECoEaAAIDAAgI1iKaFwD6AgADAAgI1iKaFwD6AgAAAA==.Lemar:BAAALAAECgcIBwAAAA==.Lennaa:BAAALAADCggIFAAAAA==.',Li='Lithos:BAAALAADCgEIAQAAAA==.Littlehunter:BAAALAAECgcIEgAAAA==.',Ma='Magint:BAAALAADCggICAABLAAECgcIFwAMAMEcAA==.Maikâti:BAAALAAECgYICwAAAA==.Majrum:BAAALAAECggIEAAAAA==.Makashi:BAAALAAECgIIAwAAAA==.Malavett:BAAALAAECgYIEAAAAA==.Malevolent:BAABLAAECoEXAAIZAAcIrANwdwABAQAZAAcIrANwdwABAQAAAA==.Maniackillez:BAAALAADCggICwAAAA==.Manusbanus:BAAALAADCgQIBAAAAA==.',Mc='Mcnabb:BAAALAAECgQIBAABLAAECggIDwABAAAAAA==.',Mi='Michail:BAAALAAECgYIBgAAAA==.',Mo='Mobsong:BAAALAADCggICAAAAA==.Mole:BAAALAAECgUICQAAAA==.Moonpig:BAAALAAECggIEQAAAA==.Mortimmer:BAAALAADCggICAAAAA==.',['Mó']='Mórrigan:BAAALAAECggIEAAAAA==.',Na='Nakazatelqt:BAAALAAECgEIAQAAAA==.',Ne='Nekrologa:BAAALAADCgUIBQAAAA==.Nerthol:BAAALAADCgcIBwAAAA==.',Nn='Nn:BAAALAADCggICAAAAA==.',No='Node:BAAALAAECgQICAAAAA==.Norkenis:BAAALAAECgYIDgAAAA==.',Nt='Ntavos:BAAALAAECgYIDwAAAA==.Ntavoss:BAAALAAECgIIAwAAAA==.',['Nê']='Nêrf:BAAALAAECgcIDgAAAA==.',['Nò']='Nòctus:BAAALAADCggICAABLAAECggIDAABAAAAAA==.',Ol='Olimar:BAAALAAECgEIAQAAAA==.',Om='Ompom:BAAALAAECggIDgABLAAECggIEAABAAAAAA==.',Oo='Oomy:BAAALAADCgcICQAAAA==.',Op='Opolainen:BAABLAAECoEeAAMDAAgIJRSyTwAeAgADAAgIJRSyTwAeAgAaAAUI+wPdTQDEAAAAAA==.Opò:BAAALAAECgQIBAAAAA==.',Or='Ora:BAABLAAECoEZAAMUAAcIOBO+QQClAQAUAAcIOBO+QQClAQAXAAYICgS6ZADdAAAAAA==.Orcko:BAAALAAECgIIBAAAAA==.',Pa='Padelakis:BAAALAADCgYIBgAAAA==.Palalry:BAABLAAECoEWAAIWAAcI+B0GEgA6AgAWAAcI+B0GEgA6AgABLAAFFAUIDQAbABQaAA==.Pallu:BAAALAADCgMIAwAAAA==.Panakos:BAAALAAECgYICQAAAA==.Patologa:BAABLAAECoEfAAIcAAcInB5OEgBoAgAcAAcInB5OEgBoAgAAAA==.Payper:BAAALAADCgcICQAAAA==.',Pe='Pelenope:BAABLAAECoEVAAMdAAgIBiFHDQDiAgAdAAgIBiFHDQDiAgAZAAEI3gc4qgAvAAAAAA==.Percival:BAAALAAECgYIDAAAAA==.',Ph='Phantom:BAAALAADCggICwAAAA==.',Pi='Pichpunta:BAABLAAECoEWAAIeAAcIhRSSCQDpAQAeAAcIhRSSCQDpAQAAAA==.',Pl='Plaurax:BAAALAADCgIIAgAAAA==.',Po='Porrstjärna:BAAALAAECgYIBgAAAA==.',Pr='Praetorian:BAAALAADCggIFQAAAA==.',Ps='Psofoskilo:BAAALAAECgYIDAAAAA==.',Ra='Ragnos:BAAALAAECgUICwAAAA==.Ragny:BAAALAAECgYIDQAAAA==.Ragoll:BAAALAAECgQICAABLAAECggIFQAQAK0bAA==.Ramlethal:BAAALAAECgYIEAAAAA==.Ravaz:BAAALAAECgYIBgABLAAECggIFQAQAK0bAA==.Ravien:BAAALAAECgIIAwAAAA==.Ravingdr:BAABLAAECoElAAMfAAgIOwnqGgBgAQAfAAgIOwnqGgBgAQATAAEIXwcHWwAvAAAAAA==.',Ro='Rodia:BAABLAAECoEXAAIgAAcIggyiRABmAQAgAAcIggyiRABmAQAAAA==.Rontina:BAAALAADCggICAAAAA==.Roupas:BAAALAAECggIDAAAAA==.',Ru='Ruiti:BAAALAADCgMIAwAAAA==.',Ry='Ryuutatsu:BAAALAADCggIFgABLAAECgcIGgAEAE4jAA==.',Sa='Sabercrown:BAAALAADCgcIBwAAAA==.',Sc='Scaryowl:BAAALAADCgcIBwAAAA==.',Se='Seenoend:BAAALAAECgYIEQAAAA==.Seraphin:BAABLAAECoEWAAIXAAcI4BxFIABNAgAXAAcI4BxFIABNAgAAAA==.',Sh='Shaboom:BAAALAADCggIDQAAAA==.Shadowlight:BAAALAADCgUIBQABLAAECggIDAABAAAAAA==.Sheeld:BAAALAAECgcIBwAAAA==.Shikishi:BAAALAADCgcICQABLAAECgcIGgAEAE4jAA==.Shizo:BAACLAAFFIETAAIXAAYIbBYoAwAJAgAXAAYIbBYoAwAJAgAsAAQKgSMAAhcACAhtILwOAOcCABcACAhtILwOAOcCAAAA.Shortshock:BAAALAAECgYICgAAAA==.',Si='Siggae:BAAALAAECgYIDgAAAA==.',So='Soricelul:BAABLAAECoEXAAIDAAgI7xOJYAD0AQADAAgI7xOJYAD0AQAAAA==.Sorkkarauta:BAAALAADCggICAAAAA==.Sosmo:BAABLAAECoEnAAMhAAgItCXTAQBXAwAhAAgIASXTAQBXAwALAAYIpR2fRwDlAQAAAA==.Souzi:BAAALAADCgcIEQAAAA==.',Sp='Spankingnew:BAABLAAECoEZAAMSAAcIGBrCTgDoAQASAAcI4hnCTgDoAQAOAAUIRBL2WwArAQAAAA==.Spellzy:BAAALAADCgYIBgAAAA==.',St='Stenåkedh:BAABLAAECoEYAAIEAAgITCK0BQDvAgAEAAgITCK0BQDvAgAAAA==.Stenåkedruid:BAAALAAECggICAAAAA==.Stenåkewar:BAAALAAECggICAAAAA==.Stormleaf:BAABLAAECoEZAAIQAAcInA0bVgBLAQAQAAcInA0bVgBLAQAAAA==.Stormshaman:BAAALAADCggIEwAAAA==.',Su='Sunra:BAABLAAECoEWAAIaAAcILQfZPQAlAQAaAAcILQfZPQAlAQAAAA==.',Ta='Taodh:BAABLAAFFIERAAIYAAUIqiBZBAAPAgAYAAUIqiBZBAAPAgABLAAFFAYICgAbAI4XAA==.Taopal:BAABLAAFFIEFAAIDAAIIPSN4EgDTAAADAAIIPSN4EgDTAAABLAAFFAYICgAbAI4XAA==.Taproot:BAAALAAECgEIAQAAAA==.',Te='Tephereth:BAAALAAECggICQAAAA==.Tezzeret:BAAALAAECgIIAgAAAA==.',Th='Thepromise:BAACLAAFFIEJAAIFAAQIIyXjAgC3AQAFAAQIIyXjAgC3AQAsAAQKgR0AAgUACAiTJo0AAHUDAAUACAiTJo0AAHUDAAAA.Theri:BAAALAAECgYIDAABLAAECgcIGgAEAE4jAA==.Therianna:BAABLAAECoEaAAMEAAcITiOxBwC8AgAEAAcITiOxBwC8AgAYAAEI1hZzBwFIAAAAAA==.Thorgriph:BAAALAAECgYIDQAAAA==.Thralia:BAAALAAECgIIAgAAAA==.Thunderlara:BAABLAAECoEVAAMLAAcIYQvqagB2AQALAAcIYQvqagB2AQAhAAIIYAEpjAAjAAAAAA==.',To='Tonni:BAAALAADCggIEAAAAA==.Torparn:BAAALAAECggIDwAAAA==.',Tr='Triv:BAAALAAECgcIBwAAAA==.',Va='Valimar:BAAALAAECggICwAAAA==.',Ve='Veesie:BAABLAAECoEeAAITAAcItgyJLgCIAQATAAcItgyJLgCIAQAAAA==.Ventura:BAAALAAECgYICQAAAA==.',Vo='Vodoo:BAABLAAECoEbAAMLAAgI0RnxKABvAgALAAgI0RnxKABvAgAKAAEIvgJxQQAYAAAAAA==.Volerac:BAAALAADCggICAAAAA==.',Wh='Whitephantom:BAAALAADCgcIDgAAAA==.',Wi='Will:BAAALAAECggIDwAAAA==.Wizzles:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Wo='Wonda:BAAALAAECgcICwAAAA==.Woozles:BAAALAAECgIIAgAAAA==.',Xa='Xa:BAAALAAECgYICwAAAA==.',Xg='Xgeforce:BAAALAAECgMIAwAAAA==.',Xy='Xysamolias:BAAALAAECgQIBAAAAA==.',Yi='Yiluun:BAAALAADCgUIBgABLAAFFAIIBgAWAOgaAA==.',Yr='Yrelia:BAAALAADCgcIDQAAAA==.',Yu='Yuly:BAAALAADCgEIAQAAAA==.',Yw='Yw:BAABLAAECoEjAAISAAgIviNsEgDwAgASAAgIviNsEgDwAgAAAA==.',Za='Zagrem:BAAALAAECgYIEAAAAA==.Zannah:BAAALAAECgIIAgAAAA==.',Ze='Zevel:BAAALAADCgcIBwAAAA==.',Zh='Zhtem:BAAALAAFFAIIBAAAAA==.',Zo='Zoosh:BAAALAADCggICAAAAA==.Zoë:BAACLAAFFIEMAAIgAAQIhxSuBgA/AQAgAAQIhxSuBgA/AQAsAAQKgS8AAiAACAjKJAsFAEoDACAACAjKJAsFAEoDAAAA.',Zu='Zugu:BAAALAADCgcIBgAAAA==.Zuriel:BAABLAAECoEXAAIaAAgIbRwMDACZAgAaAAgIbRwMDACZAgAAAA==.',['Ûf']='Ûfø:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end