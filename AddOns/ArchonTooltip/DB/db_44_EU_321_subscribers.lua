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
 local lookup = {'Hunter-Marksmanship','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Hunter-BeastMastery','DeathKnight-Frost','Paladin-Holy','Monk-Mistweaver','Evoker-Preservation','Priest-Shadow','Priest-Holy','Unknown-Unknown','Monk-Windwalker','Paladin-Protection','DeathKnight-Unholy','Druid-Balance',}; local provider = {region='EU',realm='Ravencrest',name='EU',type='subscribers',zone=44,date='2025-09-06',data={Aj='Ajuna:BAEBLAAECoEWAAIBAAgIESLSCQDWAgg5DAAAAwBaADsMAAADAFsAOgwAAAMAXQA8DAAAAwBXADIMAAADAF8APQwAAAMAXwA+DAAAAwBLAD8MAAABAEQAAQAICBEi0gkA1gIIOQwAAAMAWgA7DAAAAwBbADoMAAADAF0APAwAAAMAVwAyDAAAAwBfAD0MAAADAF8APgwAAAMASwA/DAAAAQBEAAAA.Ajunaa:BAEALAADCgEIAQABLAAECggIFgABABEiAA==.Ajured:BAEALAAECgIIAgABLAAECggIFgABABEiAA==.',An='Antrakt:BAEALAAECgIIAgABLAAFFAIIBgACALkZAA==.',Bi='Biggus:BAECLAAFFIEFAAMDAAIIDhv8CQC2AAI5DAAAAwA0ADoMAAACAFYAAwACCA4b/AkAtgACOQwAAAIANAA6DAAAAQBWAAQAAgh6AWccAGIAAjkMAAABAAMAOgwAAAEAAwAsAAQKgSAAAwMACAhRINQIAAsDAAMACAhRINQIAAsDAAQACAhhC/tCAHABAAAA.',Br='Brinkadin:BAEALAAFFAIIBAABLAAFFAYICgABAAUVAA==.Brinkdruid:BAEALAAECgYIBgABLAAFFAYICgABAAUVAA==.Brinkevo:BAEBLAAFFIEFAAIFAAUIVA0RAgCVAQU5DAAAAQA0ADsMAAABADYAOgwAAAEAKAA8DAAAAQADAD0MAAABABQABQAFCFQNEQIAlQEFOQwAAAEANAA7DAAAAQA2ADoMAAABACgAPAwAAAEAAwA9DAAAAQAUAAEsAAUUBggKAAEABRUA.Brinkhunt:BAECLAAFFIEKAAMBAAYIBRUPAQDYAQY5DAAAAgBaADsMAAACADwAOgwAAAIAQwA8DAAAAQBQADIMAAACAAkAPQwAAAEADgABAAYITQ8PAQDYAQY5DAAAAQAjADsMAAABABoAOgwAAAEAQwA8DAAAAQBQADIMAAACAAkAPQwAAAEADgAGAAMIlxuOBAD8AAM5DAAAAQBaADsMAAABADwAOgwAAAEAPQAsAAQKgRYAAwYACAjSIlwMANwCAAYACAjCIlwMANwCAAEABgjNIQIYACkCAAAA.',Ch='Choiyena:BAECLAAFFIELAAIHAAQIhR9lAgB9AQQ5DAAAAwBHADsMAAADAE0AOgwAAAMAUgA8DAAAAgBaAAcABAiFH2UCAH0BBDkMAAADAEcAOwwAAAMATQA6DAAAAwBSADwMAAACAFoALAAECoEXAAIHAAgINCQ/CgAPAwAHAAgINCQ/CgAPAwAAAA==.',Ci='Ciika:BAEBLAAECoEcAAIIAAgIZR6SBQCuAgg5DAAABAA8ADsMAAAEAE8AOgwAAAQAXQA8DAAABABcADIMAAAEAFsAPQwAAAMATAA+DAAAAwA/AD8MAAACAEEACAAICGUekgUArgIIOQwAAAQAPAA7DAAABABPADoMAAAEAF0APAwAAAQAXAAyDAAABABbAD0MAAADAEwAPgwAAAMAPwA/DAAAAgBBAAAA.',Cl='Clodsire:BAECLAAFFIENAAIJAAUI9SRUAAArAgU5DAAAAwBjADsMAAADAFsAOgwAAAQAYAA8DAAAAgBaAD0MAAABAF4ACQAFCPUkVAAAKwIFOQwAAAMAYwA7DAAAAwBbADoMAAAEAGAAPAwAAAIAWgA9DAAAAQBeACwABAqBIAACCQAICDgaKwoASgIACQAICDgaKwoASgIAAAA=.',Cp='Cptsimda:BAEALAAECgcIBwAAAA==.',Da='Dangercookie:BAEALAAECggIBAAAAA==.',De='Demsi:BAEALAADCgcIDQAAAA==.',Em='Eminos:BAECLAAFFIEIAAIBAAMIKRqPCAC4AAM5DAAAAwBWADsMAAACADoAOgwAAAMANwABAAMIKRqPCAC4AAM5DAAAAwBWADsMAAACADoAOgwAAAMANwAsAAQKgRcAAgEACAgbIyMGAAoDAAEACAgbIyMGAAoDAAAA.',Er='Eranelle:BAEALAADCggICAAAAA==.',Ex='Exoar:BAEBLAAECoEaAAICAAgIZyCzAgANAwg5DAAACABiADsMAAAFAGEAOgwAAAQAYwA8DAAAAgBKADIMAAADAFYAPQwAAAEAUQA+DAAAAgBhAD8MAAABABwAAgAICGcgswIADQMIOQwAAAgAYgA7DAAABQBhADoMAAAEAGMAPAwAAAIASgAyDAAAAwBWAD0MAAABAFEAPgwAAAIAYQA/DAAAAQAcAAAA.Exøar:BAEALAAECggICAABLAAECggIGgACAGcgAA==.',Fa='Falconeye:BAECLAAFFIEFAAIBAAMIcwk0CAC+AAM5DAAAAgAaADsMAAABAAkAOgwAAAIAJAABAAMIcwk0CAC+AAM5DAAAAgAaADsMAAABAAkAOgwAAAIAJAAsAAQKgRYAAgEACAivGHEYACUCAAEACAivGHEYACUCAAAA.',Ga='Garlicc:BAECLAAFFIEGAAICAAIIuRleAwCvAAI5DAAAAwBRADoMAAADADIAAgACCLkZXgMArwACOQwAAAMAUQA6DAAAAwAyACwABAqBIAACAgAICJkiAAIAJwMAAgAICJkiAAIAJwMAAAA=.',He='Hensomecat:BAEALAADCgYICwAAAA==.',Ja='Jaimeesoom:BAECLAAFFIEHAAIKAAMIwhUzAwD4AAM5DAAAAwBBADsMAAACACgAOgwAAAIAPQAKAAMIwhUzAwD4AAM5DAAAAwBBADsMAAACACgAOgwAAAIAPQAsAAQKgRUAAgoACAjUF3QIACECAAoACAjUF3QIACECAAAA.Jaimée:BAEBLAAECoEcAAILAAgIGiKcBQAoAwg5DAAABABWADsMAAAEAFwAOgwAAAQAWgA8DAAABABbADIMAAAEAF0APQwAAAMAVwA+DAAAAwBUAD8MAAACAEgACwAICBoinAUAKAMIOQwAAAQAVgA7DAAABABcADoMAAAEAFoAPAwAAAQAWwAyDAAABABdAD0MAAADAFcAPgwAAAMAVAA/DAAAAgBIAAEsAAUUAwgHAAoAwhUA.',Ka='Kaneian:BAEBLAAECoEbAAIIAAgIxBsJCgBhAgg5DAAABABNADsMAAAEAD8AOgwAAAQAUgA8DAAABABgADIMAAADAEkAPQwAAAMARwA+DAAAAwAfAD8MAAACAEcACAAICMQbCQoAYQIIOQwAAAQATQA7DAAABAA/ADoMAAAEAFIAPAwAAAQAYAAyDAAAAwBJAD0MAAADAEcAPgwAAAMAHwA/DAAAAgBHAAAA.',Kh='Kharnak:BAEALAADCggICAABLAAECggIHAAMAEIkAA==.',Ki='Kiirie:BAEALAADCggICAABLAAECggIHAAIAGUeAA==.',Li='Lillyrawr:BAEALAAECgcICwAAAA==.',Mo='Morsashor:BAEALAAFFAIIAgAAAA==.Morswar:BAEALAAECgcIDQABLAAFFAIIAgANAAAAAA==.',My='Myunghee:BAEBLAAECoEWAAIOAAYIPiMyDgAuAgY5DAAABABaADsMAAAEAFoAOgwAAAMAXgA8DAAABABdADIMAAAEAFsAPQwAAAMAUQAOAAYIPiMyDgAuAgY5DAAABABaADsMAAAEAFoAOgwAAAMAXgA8DAAABABdADIMAAAEAFsAPQwAAAMAUQAAAA==.',Pa='Pallindrome:BAEALAAECgYIBgABLAAFFAIIAgANAAAAAA==.',Pi='Pinkdome:BAECLAAFFIEGAAIPAAIIUxTtBQCLAAI5DAAAAwAwADoMAAADADcADwACCFMU7QUAiwACOQwAAAMAMAA6DAAAAwA3ACwABAqBGQACDwAICGYhQgUAwAIADwAICGYhQgUAwAIAAAA=.Pinkelvara:BAEALAAECgUIBQABLAAFFAIIBgAPAFMUAA==.Pinkfaceroll:BAEALAAECgQIBAABLAAFFAIIBgAPAFMUAA==.',Ro='Ronkykles:BAECLAAFFIEOAAMHAAYIhiSgAAAtAgY5DAAAAwBjADsMAAACAGEAOgwAAAIAYQA8DAAAAwBdADIMAAABAFQAPQwAAAMAWAAHAAUI6iSgAAAtAgU5DAAAAwBjADsMAAACAGEAOgwAAAIAYQA8DAAAAwBdADIMAAABAFQAEAABCJMiWwkAbAABPQwAAAMAWAAsAAQKgRYAAgcACAhcJk0BAHQDAAcACAhcJk0BAHQDAAAA.',Sh='Shaimee:BAEALAAECgYIBgABLAAFFAMIBwAKAMIVAA==.Shuff:BAEBLAAECoEcAAIRAAgIth0eDACyAgg5DAAAAwBbADsMAAAEAD8AOgwAAAMAVwA8DAAABABNADIMAAAEAFEAPQwAAAQAWQA+DAAABABQAD8MAAACACUAEQAICLYdHgwAsgIIOQwAAAMAWwA7DAAABAA/ADoMAAADAFcAPAwAAAQATQAyDAAABABRAD0MAAAEAFkAPgwAAAQAUAA/DAAAAgAlAAAA.Shuffydemon:BAEALAAECgYICgABLAAECggIHAARALYdAA==.',St='Streily:BAEALAADCgEIAQABLAAECggIHQARAL4kAA==.',Sy='Syncopium:BAECLAAFFIEIAAIJAAMIJBn6AgAJAQM5DAAAAwA/ADsMAAACADMAOgwAAAMATQAJAAMIJBn6AgAJAQM5DAAAAwA/ADsMAAACADMAOgwAAAMATQAsAAQKgSAAAgkACAidI+EBACsDAAkACAidI+EBACsDAAAA.Synsis:BAEALAAECgEIAQABLAAFFAMICAAJACQZAA==.',Tr='Traaxex:BAEBLAAECoEbAAIBAAgI7iNNBgAHAwg5DAAABABjADsMAAAEAF8AOgwAAAQAYgA8DAAABABaADIMAAAEAGIAPQwAAAMAWwA+DAAAAgBXAD8MAAACAEoAAQAICO4jTQYABwMIOQwAAAQAYwA7DAAABABfADoMAAAEAGIAPAwAAAQAWgAyDAAABABiAD0MAAADAFsAPgwAAAIAVwA/DAAAAgBKAAAA.Traxsex:BAEALAAECggIDgABLAAECggIGwABAO4jAA==.Traxxexx:BAEALAAECggIDQABLAAECggIGwABAO4jAA==.',Ya='Yanná:BAEBLAAECoEcAAIMAAgIQiTmAgA5Awg5DAAABABdADsMAAAEAF4AOgwAAAQAYAA8DAAABABeADIMAAAEAGEAPQwAAAMAVwA+DAAAAwBbAD8MAAACAFcADAAICEIk5gIAOQMIOQwAAAQAXQA7DAAABABeADoMAAAEAGAAPAwAAAQAXgAyDAAABABhAD0MAAADAFcAPgwAAAMAWwA/DAAAAgBXAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end