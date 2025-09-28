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
 local lookup = {'Evoker-Preservation','Hunter-Marksmanship','Druid-Restoration','Hunter-BeastMastery','DeathKnight-Frost','Shaman-Restoration','Warrior-Fury','DeathKnight-Blood','Rogue-Assassination','Mage-Frost','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Druid-Balance','Evoker-Devastation','Rogue-Subtlety','Shaman-Elemental','DeathKnight-Unholy',}; local provider = {region='EU',realm="Mug'thol",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ai='Aidene:BAAALAADCgcIBwABLAAECgcIHgABAJ8QAA==.',Am='Amires:BAAALAADCgYIBgAAAA==.',An='Angelblade:BAAALAAECggICwAAAA==.Angmár:BAAALAAECgYICQAAAA==.',Au='Aunty:BAAALAADCgUIBQAAAA==.',Az='Azhag:BAAALAADCgQIBAAAAA==.',Bo='Bobbybird:BAACLAAFFIELAAICAAMIyRokDQDeAAACAAMIyRokDQDeAAAsAAQKgTMAAgIACAiVIDcNAO4CAAIACAiVIDcNAO4CAAAA.',Bu='Bubblegem:BAAALAAECgQIBAABLAAECggIHAADAGgfAA==.Bumps:BAAALAAECgEIAQAAAA==.Bunnie:BAABLAAECoEcAAIDAAgIaB+6DADYAgADAAgIaB+6DADYAgAAAA==.',Ch='Cheese:BAAALAADCggIDAAAAA==.Chmera:BAABLAAECoEcAAIEAAgITBVCUQDtAQAEAAgITBVCUQDtAQAAAA==.Chratos:BAAALAADCggIFQABLAAECgYIGQAFAMQjAA==.',Cr='Crowly:BAAALAADCggICAAAAA==.',Cs='Csér:BAAALAAECgYICwAAAA==.',['Cä']='Cäss:BAAALAADCggICAABLAAFFAYIFQAGAOsVAA==.',De='Deysi:BAAALAADCggICAAAAA==.',Dr='Dracana:BAABLAAECoEXAAIHAAcIbhNaUwC/AQAHAAcIbhNaUwC/AQAAAA==.Drakon:BAABLAAECoEcAAIFAAcIoCDjNQB3AgAFAAcIoCDjNQB3AgAAAA==.Dráke:BAAALAADCggIFgAAAA==.',Du='Durel:BAABLAAECoEcAAMIAAYIUBEAIwAnAQAIAAYINBEAIwAnAQAFAAII4wjjMAFsAAAAAA==.Durelix:BAAALAADCggICwAAAA==.',El='Eltastic:BAAALAAECgUIBQAAAA==.',En='Enab:BAAALAADCggIDwAAAA==.',Er='Eradon:BAAALAADCggIDwAAAA==.',Ex='Exituse:BAABLAAECoEfAAIIAAcIqiDbCgB+AgAIAAcIqiDbCgB+AgAAAA==.',Fe='Feyrin:BAAALAAECgQIAwAAAA==.',Fi='Fix:BAABLAAECoEaAAIJAAcIKyF6DwCfAgAJAAcIKyF6DwCfAgAAAA==.',Fo='Foxi:BAAALAAECgcIEAAAAA==.',Go='Goldhaze:BAABLAAECoEVAAIKAAgI0wdJPgBSAQAKAAgI0wdJPgBSAQAAAA==.Gorgeouii:BAAALAADCgMICgAAAA==.',Gr='Greschym:BAABLAAECoEaAAIKAAgIyhf+FABVAgAKAAgIyhf+FABVAgAAAA==.',Ha='Haruspexx:BAABLAAECoEnAAICAAgIzh1FFgCeAgACAAgIzh1FFgCeAgAAAA==.Hayli:BAAALAAECggICAAAAA==.Haylia:BAAALAAECggICgAAAA==.',Hi='Hiru:BAAALAADCgEIAQAAAA==.',Ho='Honkatonka:BAAALAAECgMIAwAAAA==.',Ja='Jalkan:BAAALAADCgEIAQAAAA==.',Ka='Kaputtnik:BAAALAAECggICQAAAA==.Kardes:BAAALAADCgMIAwAAAA==.Kassadín:BAAALAADCgUIBQAAAA==.',Kh='Khane:BAABLAAECoEZAAIFAAYIxCOqQgBPAgAFAAYIxCOqQgBPAgAAAA==.',Ko='Kopernicus:BAAALAAECgQIBwABLAAECgIIBAALAAAAAA==.Kosmokrator:BAAALAAECgEIAQAAAA==.Koyuki:BAAALAADCggICAAAAA==.',Kr='Krentas:BAAALAAECgcIEgAAAA==.',La='Lariell:BAABLAAECoEXAAIEAAcIyAaHugAKAQAEAAcIyAaHugAKAQAAAA==.',Li='Lilvanna:BAAALAADCgcICgAAAA==.',Lp='Lp:BAAALAAECgEIAQAAAA==.',Ma='Malygosa:BAAALAADCgIIAgAAAA==.',Mc='Mcvoiderson:BAAALAAECgcIEwAAAA==.',Mi='Minji:BAAALAAECgcIEgAAAA==.',Mo='Monkimonk:BAAALAADCggICAABLAAECgcIHwAIAKogAA==.',Mu='Muhkuhpala:BAAALAAECggICwAAAA==.Muhkuhsham:BAAALAAECgYIDAABLAAECggICwALAAAAAA==.',My='Myriel:BAAALAADCggICQAAAA==.',Na='Nafíra:BAAALAAECgYIDAAAAA==.',Ne='Nemtheanga:BAAALAADCggICAAAAA==.',Ni='Nimba:BAAALAAECgUIEgAAAA==.',['Nâ']='Nâmaah:BAAALAAECgcIDQAAAA==.',Or='Orcgun:BAABLAAECoEVAAICAAYIOgYgdgDZAAACAAYIOgYgdgDZAAAAAA==.',Os='Ostrakion:BAABLAAECoEqAAIMAAgIuSBuFQD0AgAMAAgIuSBuFQD0AgAAAA==.',Pa='Passionpal:BAAALAADCggICAAAAA==.',Pe='Peaj:BAAALAAECgMIBQAAAA==.',Pl='Plaguê:BAAALAAECgEIAQAAAA==.',Pr='Primlock:BAAALAAECgQIBQABLAAECgYIBgALAAAAAA==.Primwarrior:BAAALAAECgYIBgAAAA==.',Ra='Radigas:BAABLAAECoEiAAINAAgIHhXpTQAqAgANAAgIHhXpTQAqAgAAAA==.Ragytaggy:BAAALAADCggIDAAAAA==.Rapentely:BAABLAAECoEYAAIOAAcI7hUgMADSAQAOAAcI7hUgMADSAQAAAA==.',Re='Relíana:BAAALAADCgUIBQAAAA==.Reventon:BAAALAAECgYIDwAAAA==.',Rh='Rhoa:BAAALAADCgYIBgAAAA==.',Ri='Risinglight:BAAALAADCgEIAQAAAA==.',Ru='Rusk:BAAALAAECgYIBgAAAA==.',Sa='Santur:BAAALAAECgYIDgAAAA==.Sasoren:BAAALAAECgUIBQAAAA==.',Sc='Scathaca:BAABLAAECoEeAAMBAAcInxAIGQB+AQABAAcInxAIGQB+AQAPAAYIwQkAAAAAAAAAAA==.',Se='Serethna:BAAALAADCggICAAAAA==.Serés:BAAALAAECgQIBQAAAA==.',Sh='Shanane:BAACLAAFFIEVAAIGAAYI6xXJAgDyAQAGAAYI6xXJAgDyAQAsAAQKgSQAAgYACAieHLYkAF0CAAYACAieHLYkAF0CAAAA.Shannaaevo:BAAALAADCgEIAQABLAAFFAYIFQAGAOsVAA==.Shariyaci:BAABLAAECoEaAAIFAAcIohQchQC4AQAFAAcIohQchQC4AQAAAA==.Shariyamî:BAAALAAECgYIBgABLAAECgcIGgAFAKIUAA==.Shariyani:BAAALAADCggIDgABLAAECgcIGgAFAKIUAA==.Shariyavi:BAAALAADCgcIFAABLAAECgcIGgAFAKIUAA==.Shyrini:BAAALAAECggIDQAAAA==.',Si='Simsalabim:BAAALAAECgIIAgAAAA==.Sinuviel:BAAALAAECggICAAAAA==.',Sk='Skûlló:BAAALAADCggICAAAAA==.',St='Stinkylady:BAABLAAECoEnAAINAAgIQhdXSAA5AgANAAgIQhdXSAA5AgAAAA==.',Sy='Syvedas:BAABLAAECoEeAAIQAAcIux3/DQAvAgAQAAcIux3/DQAvAgAAAA==.',Ta='Tabiea:BAAALAADCgYIBgAAAA==.',Te='Tenock:BAABLAAECoEeAAMGAAgIERj0KgBDAgAGAAgIERj0KgBDAgARAAYIUAqfbwAyAQAAAA==.Tewien:BAAALAAECgUIBgAAAA==.',Th='Thurga:BAAALAAECgcICwAAAA==.',To='Todeskritter:BAAALAAECgYIBgAAAA==.Totzok:BAAALAADCggICAABLAADCggICQALAAAAAA==.',Un='Unschuld:BAAALAADCgYIBgAAAA==.',Wa='Warlôkk:BAAALAAECgIIBAAAAA==.',We='Wemma:BAABLAAECoEaAAMSAAcI8RkeEQA0AgASAAcIzBkeEQA0AgAFAAEIGgsAAAAAAAAAAA==.',Xa='Xantany:BAAALAAECgcIBwAAAA==.',Xe='Xedall:BAAALAAECgIIAgAAAA==.',Ya='Yael:BAAALAAECgYIBgAAAA==.Yappo:BAAALAADCgEIAQAAAA==.',Ze='Zelor:BAAALAAECgYICQAAAA==.',Zi='Zipfelbaby:BAAALAADCgcIDgAAAA==.Zirondel:BAAALAADCgcIBwAAAA==.',['Ða']='Ðally:BAAALAAECggIEgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end