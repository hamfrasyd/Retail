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
 local lookup = {'Unknown-Unknown','Druid-Balance','Hunter-BeastMastery','Warrior-Fury','Hunter-Marksmanship','Priest-Shadow','Mage-Arcane','Evoker-Devastation','Paladin-Retribution','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Priest-Holy','Shaman-Elemental','Warrior-Protection','Warrior-Arms','Druid-Restoration','Evoker-Augmentation','Mage-Fire','Rogue-Outlaw','Rogue-Subtlety','Hunter-Survival','DeathKnight-Blood','Mage-Frost','Shaman-Restoration',}; local provider = {region='EU',realm='Dunemaul',name='EU',type='weekly',zone=44,date='2025-09-22',data={An='Anasta:BAAALAADCgcIBwAAAA==.Andeddu:BAAALAADCgcICAAAAA==.Andromache:BAAALAADCgYICwAAAA==.Angusbiff:BAAALAADCgcICwAAAA==.',Ar='Arathraz:BAAALAAECgIIAgAAAA==.Archron:BAAALAADCggIFAAAAA==.Aribeth:BAAALAADCgYIBgAAAA==.Arjantis:BAAALAAECgEIAQAAAA==.',As='Asher:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.',At='Atoralar:BAAALAAECgUICAAAAA==.Atrabene:BAABLAAECoEbAAICAAgIqBMZKAD4AQACAAgIqBMZKAD4AQAAAA==.',Au='Auro:BAAALAAECgYIBgAAAA==.',Be='Beefcakee:BAAALAAECgQIBAABLAAECgYIDAABAAAAAA==.',Bi='Biittisika:BAABLAAECoEtAAIDAAgIdB2tNAA/AgADAAgIdB2tNAA/AgAAAA==.Billidan:BAAALAAECgIIAgAAAA==.',Bl='Blacklisto:BAAALAAECgYIDAAAAA==.',Bo='Bo:BAABLAAECoEYAAIEAAcIDRlIOQAUAgAEAAcIDRlIOQAUAgAAAA==.Bobota:BAABLAAECoEUAAIFAAYIcA1tWwAtAQAFAAYIcA1tWwAtAQAAAA==.Bombastic:BAAALAAECgcIBwAAAA==.Booly:BAABLAAECoEYAAIGAAcIqCEaFACzAgAGAAcIqCEaFACzAgAAAA==.',Br='Braxor:BAAALAADCgcIBgAAAA==.Brewsky:BAAALAAECgUIBQAAAA==.',Bu='Bullcosby:BAABLAAECoEdAAIHAAYIUxoFWADUAQAHAAYIUxoFWADUAQAAAA==.',Ca='Carlos:BAAALAAECgYIDwAAAA==.Cassie:BAACLAAFFIEQAAIIAAUIUR4BBADGAQAIAAUIUR4BBADGAQAsAAQKgSQAAggACAhgJFEGAB4DAAgACAhgJFEGAB4DAAAA.Cassãndra:BAAALAAECgEIAQABLAAFFAUIEAAIAFEeAA==.',Ce='Celetuz:BAAALAAECgEIAQAAAA==.',Ch='Chewinwicked:BAABLAAECoEZAAIJAAYIyRnwegC8AQAJAAYIyRnwegC8AQAAAA==.Chibace:BAAALAAECgYIDAAAAA==.',Cr='Craphealing:BAAALAAECgcIEgAAAA==.',Da='Darkbane:BAABLAAECoEgAAMKAAgI6xW8QgApAgAKAAgI6xW8QgApAgALAAcIRAbANADfAAAAAA==.Darkomania:BAAALAADCgYICQAAAA==.Darksoul:BAAALAADCggIEAABLAAECgYIDAABAAAAAA==.Datte:BAAALAAECggIDwAAAA==.',De='Deathflight:BAAALAADCgcIBwAAAA==.Demeron:BAACLAAFFIELAAIMAAUIjBufAQC8AQAMAAUIjBufAQC8AQAsAAQKgR4AAgwACAiFJIICAFUDAAwACAiFJIICAFUDAAAA.Demongreen:BAABLAAECoEgAAIKAAgIugusfACWAQAKAAgIugusfACWAQAAAA==.Demononme:BAAALAADCggICAAAAA==.',Di='Discochoco:BAAALAADCgQIBAAAAA==.Disney:BAAALAAECggIDwAAAA==.',Dk='Dkfilen:BAAALAADCgYIBgAAAA==.',El='Elken:BAAALAADCggICAAAAA==.',En='Endlessdark:BAAALAADCgIIAwAAAA==.',Fa='Falc:BAABLAAFFIEJAAIEAAMIPA6EEQDoAAAEAAMIPA6EEQDoAAAAAA==.Fasina:BAAALAAECgMIAgAAAA==.',Fe='Ferlicea:BAAALAADCgUIBAAAAA==.',Fi='Filen:BAAALAAECgEIAQAAAA==.',Fl='Flynxi:BAAALAADCgEIAQAAAA==.',Fr='Freakylash:BAAALAAECggIDAABLAAECggIDQABAAAAAA==.Fredsblomman:BAAALAADCgQIAgAAAA==.',Ga='Gamlesvin:BAAALAAECgYIDAAAAA==.',Gi='Gifu:BAABLAAECoEZAAMNAAYISyBYBwA2AgANAAYI2h9YBwA2AgAOAAYIdRUxXQCdAQAAAA==.Ginfaxi:BAAALAADCgMIAwAAAA==.',Gr='Grumpycat:BAAALAAECgEIAQAAAA==.',Gw='Gwendalin:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',['Gå']='Gålactus:BAAALAADCggIFQAAAA==.',Ha='Haize:BAAALAADCgMIAwAAAA==.Hashasin:BAABLAAECoEeAAIPAAgIRBvoEQB/AgAPAAgIRBvoEQB/AgAAAA==.Hastaruhlar:BAAALAAECgYIDgAAAA==.Hastaruhun:BAAALAAECgQIBQAAAA==.',Ho='Horadrim:BAAALAAECgIIAgAAAA==.',Hu='Hunterglory:BAAALAAECgYIEgAAAA==.Huntley:BAAALAAECggICwAAAA==.',Id='Idron:BAAALAADCggIGAAAAA==.',Il='Iliana:BAABLAAECoEeAAIQAAgI9B4iGACMAgAQAAgI9B4iGACMAgAAAA==.',Im='Imeena:BAABLAAECoEiAAIQAAgIDSFkCgACAwAQAAgIDSFkCgACAwAAAA==.',Jo='Joe:BAAALAAECgYIDgABLAAECgcIGAAGAOsZAA==.',Ka='Kaldeas:BAAALAAECgQIBAABLAAECggIFQARANQXAA==.Kavii:BAABLAAECoEZAAIDAAcI2h7yKgBnAgADAAcI2h7yKgBnAgAAAA==.',Ke='Kellindel:BAAALAAECgYICAAAAA==.',Ki='Kipp:BAABLAAECoEVAAMSAAcIHg7UNQBmAQASAAcI9w3UNQBmAQATAAQIyQzfIADFAAAAAA==.',['Kä']='Kärmessuu:BAABLAAECoEXAAIIAAcIfgnbNgBQAQAIAAcIfgnbNgBQAQABLAAECggILQADAHQdAA==.Käsh:BAABLAAECoEgAAIUAAgIGBQqLgDyAQAUAAgIGBQqLgDyAQAAAA==.',La='Larrybatong:BAAALAADCggICAAAAA==.Lashalmighty:BAAALAAECggIDQAAAA==.',Le='Lee:BAAALAAECgQIBAABLAAECggIGwACAKgTAA==.Leonides:BAAALAAECgUIBQAAAA==.Lesiina:BAAALAAECgEIAQAAAA==.Lewk:BAAALAAECgIIAgAAAA==.Lexkiller:BAAALAAECgYIEAAAAA==.Lezterdh:BAACLAAFFIEMAAIKAAQIgiAzCQCJAQAKAAQIgiAzCQCJAQAsAAQKgSwAAgoACAhLJrgCAHoDAAoACAhLJrgCAHoDAAAA.',Li='Lilium:BAAALAAECgMIAQAAAA==.Lilzaps:BAABLAAECoEXAAIVAAcIcwtZCgB7AQAVAAcIcwtZCgB7AQAAAA==.',Lo='Lockmuch:BAAALAADCgcIBwAAAA==.',Lu='Lurq:BAAALAADCgEIAQAAAA==.',Ma='Magroz:BAAALAAECgYIDgAAAA==.Malravion:BAABLAAECoEWAAIFAAcIGwrGWgAvAQAFAAcIGwrGWgAvAQAAAA==.Maus:BAAALAAECgYICAAAAA==.Maximus:BAAALAADCggIDgAAAA==.',Me='Medusa:BAAALAAECgYIBgAAAA==.Melisun:BAABLAAECoEVAAIUAAcI2yB5FACMAgAUAAcI2yB5FACMAgAAAA==.',Mi='Milirien:BAAALAAECgYICAAAAA==.',Ml='Mlooko:BAAALAADCgcIBwAAAA==.',Mo='Monké:BAAALAAECgcIDQAAAA==.',Mu='Mulabeef:BAAALAAECgYIBgAAAA==.',My='Myrkr:BAAALAAECgMIAgAAAA==.',Na='Narac:BAAALAAECgIIAgAAAA==.Naudemon:BAAALAADCgUICgAAAA==.Naudru:BAAALAADCgYICAAAAA==.Naulock:BAAALAADCgcIDQAAAA==.Naumage:BAAALAADCgQIAQAAAA==.Naumonk:BAAALAADCgUIBwAAAA==.Nausha:BAAALAADCgcIEAAAAA==.Nauwarri:BAAALAADCgcIDQAAAA==.',Ne='Nephalim:BAAALAADCgYIBgAAAA==.New:BAAALAAECgIIAgAAAA==.',Ni='Nightstar:BAABLAAECoEgAAIDAAgIGhNJUwDbAQADAAgIGhNJUwDbAQAAAA==.Nihilus:BAAALAAECgUIBwAAAA==.',No='Notamoo:BAAALAADCggICAAAAA==.Nothunt:BAABLAAECoEoAAIDAAgIzx2JMABPAgADAAgIzx2JMABPAgAAAA==.',Oh='Ohalan:BAABLAAECoEcAAMEAAYI+AeThAAhAQAEAAYI+AeThAAhAQATAAEIvwMnNgAjAAAAAA==.',Oz='Ozzyosbourne:BAABLAAECoEaAAMWAAcIDBL/BwCtAQAWAAcI8A//BwCtAQAHAAcIcQypcACNAQAAAA==.',Pa='Palamanthul:BAAALAADCgcIDgABLAAECgYICAABAAAAAA==.Palapatiine:BAABLAAECoEZAAIJAAgIqRBIiwCdAQAJAAgIqRBIiwCdAQAAAA==.Pappapewen:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Pappaurukhai:BAAALAAECgYICAAAAA==.',Pi='Pikachí:BAAALAADCgcIBwAAAA==.Pikipoko:BAAALAADCgYIDAAAAA==.',Pl='Pluta:BAAALAADCgUIBQAAAA==.',Pr='Pryna:BAAALAAECgYICAAAAA==.',Ql='Qlubi:BAAALAADCggICwAAAA==.',Ra='Racduck:BAAALAAECgUIBgAAAA==.Ragequit:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Raimu:BAAALAAECgYICwAAAA==.',Ru='Rumpuhol:BAAALAAECgEIAQAAAA==.',Sa='Sagrit:BAABLAAECoEVAAIXAAcI9w/iCQC8AQAXAAcI9w/iCQC8AQAAAA==.Savix:BAAALAAECgYIBQAAAA==.',Sc='Scrolldge:BAAALAAECgcIDQAAAA==.Scâremonger:BAAALAAECgYICgAAAA==.',Se='Setcycle:BAABLAAECoEVAAMYAAYImBniEwDYAQAYAAYImBniEwDYAQAPAAMIwAlBVACVAAAAAA==.',Sh='Shiina:BAACLAAFFIEKAAIZAAMI5yGbAAA8AQAZAAMI5yGbAAA8AQAsAAQKgScAAhkACAhLIzsBADMDABkACAhLIzsBADMDAAAA.Shizuko:BAAALAAECgMIAwAAAA==.Shortstack:BAAALAADCggICQAAAA==.',Si='Silverdod:BAAALAAECgYIEgAAAA==.Sinistorm:BAABLAAECoEgAAIEAAgICx1sIACXAgAEAAgICx1sIACXAgAAAA==.',Sn='Snoppbrytare:BAAALAAECgYIEQAAAA==.',So='Solisse:BAAALAADCggICAABLAAECggIHwAJAMMYAA==.',St='Starleaf:BAAALAADCggIEAAAAA==.Stuud:BAABLAAECoEfAAIaAAgIdA+KGACUAQAaAAgIdA+KGACUAQAAAA==.',Sw='Swagmooman:BAAALAADCgcIBwABLAAECggIFQARANQXAA==.',Sy='Syrnalol:BAABLAAECoEcAAIbAAgInBkuFABWAgAbAAgInBkuFABWAgAAAA==.',Ta='Taikurilehmä:BAAALAADCgIIAwAAAA==.',Te='Tetout:BAAALAADCgcIBwAAAA==.',Th='Tharondil:BAAALAADCgIIAQAAAA==.Thisone:BAAALAAECgcIEwAAAA==.Thraximar:BAAALAADCggICAAAAA==.Thundeim:BAAALAADCgcIBwAAAA==.Thunderhoof:BAACLAAFFIEJAAIcAAMI0hVqEADZAAAcAAMI0hVqEADZAAAsAAQKgRQAAhwACAiHFw1AAO8BABwACAiHFw1AAO8BAAAA.',Ti='Timmý:BAAALAAECgUIDAABLAAECgYIDQABAAAAAA==.',To='Tor:BAAALAAECgMIAgAAAA==.',Tr='Treemendous:BAAALAAECgYIBgAAAA==.',Ty='Tyranus:BAAALAADCgYIBwAAAA==.',Un='Uncleunc:BAABLAAECoEVAAIJAAgIJQ3vdgDEAQAJAAgIJQ3vdgDEAQAAAA==.Unter:BAAALAADCggICAAAAA==.',Va='Valééra:BAAALAAECgYICAAAAA==.',Vi='Vilen:BAAALAAECgYIBwAAAA==.Visshh:BAAALAADCgYICQAAAA==.',Vl='Vlachos:BAAALAAECgIIAgAAAA==.',Vo='Vodafone:BAABLAAECoEZAAMUAAcI4RaKMgDdAQAUAAcI4RaKMgDdAQACAAIICQ+kewBlAAAAAA==.',We='Web:BAAALAADCggICQAAAA==.',Wo='Wooboo:BAAALAAECgEIAQAAAA==.',Wr='Wrolkien:BAAALAAECggIDgAAAA==.',Xi='Xiled:BAAALAADCgUICAAAAA==.',Za='Zahg:BAABLAAECoEcAAMcAAgIhh7KFwCaAgAcAAgIhh7KFwCaAgARAAYIjApzaQA7AQAAAA==.',Ze='Zeous:BAAALAAECgYIBgAAAA==.Zezar:BAAALAADCgUIBQAAAA==.',Zo='Zoup:BAAALAAECgcIDwAAAA==.',['Ál']='Áldari:BAABLAAECoEgAAIKAAgIKRpgNwBRAgAKAAgIKRpgNwBRAgAAAA==.',['Ök']='Öküzgözlüm:BAAALAADCgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end