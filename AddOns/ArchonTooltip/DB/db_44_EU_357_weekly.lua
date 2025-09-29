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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Druid-Balance','Druid-Restoration','Shaman-Restoration','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Warrior-Arms','Shaman-Elemental','Mage-Arcane','Mage-Frost','Warlock-Destruction','Paladin-Protection','Paladin-Holy','Rogue-Subtlety','Warlock-Demonology','DeathKnight-Frost','Hunter-Survival','Monk-Mistweaver','Monk-Windwalker','Warlock-Affliction',}; local provider = {region='EU',realm='Arathi',name='EU',type='weekly',zone=44,date='2025-09-23',data={Aa='Aarokc:BAAALAAECgIIAwABLAAECgcIDgABAAAAAA==.',Ad='Adräeth:BAAALAAECgYIBgAAAA==.',Aj='Ajunta:BAAALAAECgYIDAAAAA==.',Am='Ameliseta:BAACLAAFFIEIAAICAAMI8hoaDQAYAQACAAMI8hoaDQAYAQAsAAQKgSoAAgIACAiMJEwMACoDAAIACAiMJEwMACoDAAAA.Amelyseta:BAAALAAECggIEgABLAAFFAMICAACAPIaAA==.Ameseta:BAAALAADCgIIAgABLAAFFAMICAACAPIaAA==.',An='Antarios:BAAALAAECgIIAgAAAA==.',Ar='Araleen:BAAALAAECgYIBgAAAA==.',As='Astu:BAAALAADCgcICAAAAA==.',At='Athorie:BAABLAAECoEcAAIDAAgIcxEQNgDfAQADAAgIcxEQNgDfAQAAAA==.',Ay='Ayyurus:BAAALAAECggIDwAAAA==.',['Aù']='Aùrôrä:BAAALAADCgUIBgAAAA==.',Be='Belladonna:BAAALAAECgYIDAAAAA==.Beorn:BAAALAAECgMICQAAAA==.',Cl='Clafoutie:BAAALAADCgEIAQAAAA==.',Da='Dankø:BAAALAADCggIFwAAAA==.Darthkaz:BAAALAADCggIDwAAAA==.',De='Deadlemon:BAAALAADCggIFAAAAA==.Deathdoras:BAAALAAECgYIDgAAAA==.Deathyiff:BAAALAAECgYICwAAAA==.Deixis:BAAALAAECgYICgABLAAECggIFwAEAPIcAA==.',Dr='Droodicaël:BAABLAAECoEfAAMFAAgIFCBkEQC6AgAFAAcIiCJkEQC6AgAGAAgIXxjsIQA1AgAAAA==.',['Dø']='Døbby:BAAALAAECgIIAgAAAA==.',Ek='Ekaitz:BAABLAAECoEnAAIEAAgIuh5UBADQAgAEAAgIuh5UBADQAgAAAA==.',El='Elemtophe:BAABLAAECoEYAAIHAAcIbx0wKwA+AgAHAAcIbx0wKwA+AgAAAA==.',Ep='Eponey:BAAALAAECgMIAQAAAA==.',Et='Ether:BAAALAAECgYICAAAAA==.',Fa='Fayte:BAAALAADCggICAAAAA==.',Fl='Flak:BAAALAAECgYIDQABLAAFFAUICgAIADEYAA==.',Fo='Fotlog:BAAALAAECggIDwAAAA==.',Ga='Gabarrow:BAABLAAECoEUAAMJAAYI6REwiQBkAQAJAAYIwRAwiQBkAQAKAAUIuQxUcwDfAAAAAA==.Gaya:BAAALAAECgYIDAAAAA==.',Go='Gobledémo:BAAALAAECgEIAQAAAA==.Gobmichelle:BAAALAADCggIDwAAAA==.Gougouve:BAACLAAFFIEFAAILAAIISwsTGAB1AAALAAIISwsTGAB1AAAsAAQKgTMAAwsACAgZGZEVAFQCAAsACAgZGZEVAFQCAAwABgjFCkQaACEBAAAA.Gouvette:BAAALAAECgUIBwABLAAFFAIIBQALAEsLAA==.',Gr='Grymli:BAAALAAECgUICAAAAA==.',Ha='Haggamenom:BAAALAAECgQICQAAAA==.',Hi='Hisoka:BAAALAAECgUIBwAAAA==.',['Hï']='Hïllphyk:BAAALAAECgUICAAAAA==.',Im='Impéria:BAAALAAECggIDwAAAA==.',Ka='Kalheal:BAABLAAECoEdAAIDAAgIUxtSHQBrAgADAAgIUxtSHQBrAgAAAA==.Kauss:BAABLAAECoEWAAINAAgIqRDIOgDrAQANAAgIqRDIOgDrAQAAAA==.',Ke='Kestudi:BAAALAAECgYIEAAAAA==.',Kr='Kristianburn:BAAALAADCgIIAgAAAA==.',Ku='Kurama:BAAALAAECgMIBgAAAA==.',Ky='Kyoto:BAACLAAFFIEGAAIOAAIIPSIfIgC8AAAOAAIIPSIfIgC8AAAsAAQKgSoAAw4ACAi5JS8HAEwDAA4ACAiQJS8HAEwDAA8AAgjlJNFgAKIAAAAA.Kyotø:BAAALAAECgYIBgABLAAFFAIIBgAOAD0iAA==.',La='Lammor:BAAALAAECgYIDwAAAA==.Layte:BAABLAAECoEdAAIPAAgIBxyDDwCLAgAPAAgIBxyDDwCLAgAAAA==.',Le='Lemagus:BAABLAAECoEcAAIPAAgI/h+OCgDTAgAPAAgI/h+OCgDTAgABLAAFFAIIBgAQAFYgAA==.Lextwa:BAAALAAECgMIBgAAAA==.',Ma='Mackis:BAAALAAECgYIBgAAAA==.Magalia:BAABLAAECoEcAAIHAAcIIQ8ieABVAQAHAAcIIQ8ieABVAQAAAA==.Maléfix:BAAALAADCgYIBgAAAA==.Mardelia:BAABLAAECoEfAAQRAAgIkBkBEQBJAgARAAgIkBkBEQBJAgASAAQITQ4HTQDSAAAIAAIIswSQMgFAAAAAAA==.',Me='Mefoux:BAAALAAECgEIAQAAAA==.Meliseta:BAABLAAECoEcAAICAAgIdhk7JgB3AgACAAgIdhk7JgB3AgABLAAFFAMICAACAPIaAA==.Mendley:BAAALAAECggICAAAAA==.Merrell:BAAALAADCggIIAABLAAECggIGAATAGAdAA==.Metzya:BAABLAAECoEWAAMJAAgIvRPYZAC0AQAJAAYIOhnYZAC0AQAKAAgIjQMkfQC6AAABLAAECggIKQAUAPMgAA==.',Mi='Micheldewow:BAAALAAECgYIBgAAAA==.Migmar:BAAALAAECgMIAwAAAA==.Minideix:BAABLAAECoEXAAIEAAgI8hy4BwBrAgAEAAgI8hy4BwBrAgAAAA==.',My='Myamor:BAAALAAECgYIDQAAAA==.',['Mé']='Méliâra:BAAALAAECgUIBwAAAA==.',['Mø']='Møulaga:BAAALAAECgQIBAABLAAECgYIDwABAAAAAA==.',Na='Nadriélas:BAAALAAECgYIDQAAAA==.',Ni='Nixqt:BAAALAAECggIDQAAAA==.',Ny='Nyarlathotep:BAAALAADCgcIBwAAAA==.',Og='Oglathach:BAAALAAECgcICAAAAA==.Ogzokk:BAABLAAECoEaAAIVAAYIayBdSwAzAgAVAAYIayBdSwAzAgABLAAECggIGAATAGAdAA==.',Ow='Owa:BAAALAAECgYICwAAAA==.',Pa='Pamluxe:BAAALAADCggIGgAAAA==.Pattedefêr:BAAALAAECggIDQAAAA==.Payte:BAAALAAECgMIAwAAAA==.',Pe='Pepsette:BAAALAAECgYIDgAAAA==.',Pl='Platjahs:BAAALAADCgYIBgAAAA==.',Po='Poponey:BAABLAAECoEVAAIWAAgIwxbcBwATAgAWAAgIwxbcBwATAgAAAA==.',Pr='Prétoriàn:BAAALAAECggIDQAAAA==.',Ps='Psyroth:BAABLAAECoEeAAICAAgIXiEpEAANAwACAAgIXiEpEAANAwAAAA==.',Qu='Quill:BAAALAADCgQIBAAAAA==.',Ra='Ragnøk:BAAALAAECgYIDwAAAA==.Raukild:BAAALAAECgMIAwAAAA==.',Re='Rembikokirko:BAAALAAECgYIBwAAAA==.',['Râ']='Râoh:BAAALAAECgYIEwAAAA==.',Sa='Samtrouvtous:BAAALAAECgYIEgAAAA==.Saphirbleu:BAAALAADCgYIBgAAAA==.Saresh:BAABLAAECoEaAAIMAAgIoyERAwD3AgAMAAgIoyERAwD3AgAAAA==.Savalya:BAAALAADCggICAAAAA==.Sazamizy:BAAALAADCggIDgABLAAECgYIDwABAAAAAA==.',Sh='Shanaria:BAAALAADCgYIBgABLAAECggIGAATAGAdAA==.Shooterdark:BAABLAAECoEVAAIIAAgIpRWxbgDYAQAIAAgIpRWxbgDYAQAAAA==.',Si='Simbalavoine:BAAALAADCgcIBwAAAA==.Sisspeoh:BAAALAAECgYIDgAAAA==.Siyä:BAABLAAECoEdAAIXAAgIiyC5BgDhAgAXAAgIiyC5BgDhAgAAAA==.',Sw='Sweets:BAAALAADCgcIDAAAAA==.',Te='Terminno:BAAALAAECgcIDgAAAA==.',Th='Thalhya:BAABLAAECoEjAAIYAAgIHgwJJgCaAQAYAAgIHgwJJgCaAQAAAA==.',To='Tophe:BAAALAADCggIFAAAAA==.',Vi='Vika:BAAALAADCgQIBAAAAA==.Virsedgymek:BAAALAAECgUIBwABLAAECgYICwABAAAAAA==.',Vy='Vycka:BAAALAAECgYIDgAAAA==.',Ya='Yapal:BAAALAAECgcIEwAAAA==.',Yu='Yuji:BAAALAADCgMIBQAAAA==.',Za='Zakana:BAAALAAECgYIBQAAAA==.Zakera:BAAALAAECgYIDgAAAA==.Zatsu:BAAALAADCgcICAAAAA==.',Ze='Zertyop:BAAALAADCgYIDAAAAA==.Zeïkø:BAAALAADCggIFwAAAA==.',Zu='Zudrakk:BAAALAADCgQIBAAAAA==.',['Ãb']='Ãbaddøn:BAABLAAECoEdAAQUAAcIiwy6KwCiAQAUAAcIiwy6KwCiAQAQAAIIRwXAywBOAAAZAAEIWAJVQAAoAAAAAA==.',['Ør']='Ørløndø:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end