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
 local lookup = {'Hunter-BeastMastery','Paladin-Holy','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Shaman-Restoration','Shaman-Enhancement','Paladin-Protection','Paladin-Retribution','Warrior-Protection','Unknown-Unknown','Monk-Brewmaster','Monk-Windwalker','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Druid-Restoration','Druid-Balance','Shaman-Elemental',}; local provider = {region='EU',realm='Hyjal',name='EU',type='subscribers',zone=44,date='2025-09-25',data={Am='Amenadiel:BAEALAAECggIEQABLAAECggIKwABABgeAA==.',As='Astoz:BAEALAADCggIDgABLAAECggIKwACALAeAA==.',At='Atraxaa:BAEALAAECggICAABLAAFFAMICQADAM8fAA==.',Bn='Bnjee:BAECLAAFFIEPAAIEAAMIqSSJCgA5AQM5DAAABgBaADsMAAAEAFsAOgwAAAUAYwAEAAMIqSSJCgA5AQM5DAAABgBaADsMAAAEAFsAOgwAAAUAYwAsAAQKgS4AAwQACAj+JJ4DAFIDAAQACAj+JJ4DAFIDAAUABwjqDidGAIMBAAAA.Bnjhe:BAEALAAECgUIBQABLAAFFAMIDwAEAKkkAA==.',Br='Breya:BAECLAAFFIEJAAIDAAMIzx+tAgAbAQM5DAAABABfADsMAAACAD8AOgwAAAMAVQADAAMIzx+tAgAbAQM5DAAABABfADsMAAACAD8AOgwAAAMAVQAsAAQKgScAAwMACAj+JLsDACoDAAMACAj+JLsDACoDAAYABwihFgNjAN0BAAAA.',Ch='Châsseroc:BAEBLAAECoErAAIBAAgIGB6jMgBYAgg5DAAACABaADsMAAAGAFwAOgwAAAcASAA8DAAABwBXADIMAAAHAF4APQwAAAYAXgA+DAAAAQBAAD8MAAABABMAAQAICBgeozIAWAIIOQwAAAgAWgA7DAAABgBcADoMAAAHAEgAPAwAAAcAVwAyDAAABwBeAD0MAAAGAF4APgwAAAEAQAA/DAAAAQATAAAA.',Cr='Cramel:BAECLAAFFIEJAAIHAAQIkRmwDQAFAQQ5DAAAAwBVADsMAAACAEYAOgwAAAMATAA8DAAAAQAdAAcABAiRGbANAAUBBDkMAAADAFUAOwwAAAIARgA6DAAAAwBMADwMAAABAB0ALAAECoEaAAIHAAgIlxMRVQC8AQAHAAgIlxMRVQC8AQAAAA==.',Da='Daxtedge:BAECLAAFFIEIAAIIAAMI3xUfBACtAAM5DAAABABHADsMAAABAAwAOgwAAAMAVAAIAAMI3xUfBACtAAM5DAAABABHADsMAAABAAwAOgwAAAMAVAAsAAQKgSoAAggACAhwI9EBADQDAAgACAhwI9EBADQDAAAA.',Dr='Dreirak:BAEBLAAECoEhAAMJAAcITh+eDACMAgc5DAAABgBfADsMAAAGAFAAOgwAAAUAYQA8DAAABQBVADIMAAAFAEoAPQwAAAUAUwA+DAAAAQArAAkABwhOH54MAIwCBzkMAAAFAF8AOwwAAAUAUAA6DAAABABhADwMAAAFAFUAMgwAAAUASgA9DAAABQBTAD4MAAABACsACgADCKYIzxsBgQADOQwAAAEAGwA7DAAAAQALADoMAAABABsAAAA=.',Ez='Ezräna:BAEALAAECgcICgABLAAECggIFwALAPIkAA==.',Fe='Femurfebrile:BAEALAADCggIIAABLAAECgYIBgAMAAAAAA==.',Fi='Fishette:BAECLAAFFIEGAAINAAMIgQ4tCgDAAAM5DAAAAgApADsMAAACABkAOgwAAAIALAANAAMIgQ4tCgDAAAM5DAAAAgApADsMAAACABkAOgwAAAIALAAsAAQKgRwAAw0ACAiMF1QSABACAA0ACAiMF1QSABACAA4ACAjoAZFNAIAAAAEsAAUUAwgJAAMAzx8A.',Fu='Fullban:BAEALAADCgcIEAABLAAECgYICAAMAAAAAA==.Fullfurax:BAEALAADCggIAgABLAAECgYICAAMAAAAAA==.',Ga='Gaaqa:BAEBLAAECoErAAMCAAgIsB5RCADSAgg5DAAACABYADsMAAAGAEgAOgwAAAYATwA8DAAABgBGADIMAAAFAGAAPQwAAAUAYQA+DAAABABNAD8MAAADACwAAgAICLAeUQgA0gIIOQwAAAcAWAA7DAAABABIADoMAAAEAE8APAwAAAUARgAyDAAABABgAD0MAAAFAGEAPgwAAAQATQA/DAAAAwAsAAoABQgVCPr1AN0ABTkMAAABACUAOwwAAAIAJAA6DAAAAgANADwMAAABAAkAMgwAAAEABQAAAA==.',Ic='Icyrend:BAEALAADCgcIDQABLAAFFAIIAgAMAAAAAA==.',Ka='Kassl:BAEALAAECgQIBAABLAAFFAMICgAKALYaAA==.Kassp:BAECLAAFFIEKAAIKAAMIthosDQATAQM5DAAABQBeADsMAAABACMAOgwAAAQASgAKAAMIthosDQATAQM5DAAABQBeADsMAAABACMAOgwAAAQASgAsAAQKgTQAAgoACAg0Je8IAFQDAAoACAg0Je8IAFQDAAAA.Kayð:BAEALAAECggIDgAAAA==.',Ki='Killbow:BAEALAAECgYICAAAAA==.',Le='Lemonice:BAEBLAAECoEYAAQPAAgI5RmtDABLAgg5DAAAAwA/ADsMAAAFAFEAOgwAAAQATQA8DAAAAwAqADIMAAADAFcAPQwAAAQAQgA+DAAAAQAxAD8MAAABAD4ADwAICCMYrQwASwIIOQwAAAIAMQA7DAAAAgBCADoMAAAEAE0APAwAAAMAKgAyDAAAAgBRAD0MAAADAEIAPgwAAAEAMQA/DAAAAQA+ABAAAwjmHT8RABQBAzsMAAABAFEAMgwAAAEAVwA9DAAAAQA8ABEAAggvFxtYAIgAAjkMAAABAD8AOwwAAAIANwABLAAFFAMIDQAFALkkAA==.',Li='Limiriadon:BAEBLAAECoEkAAMSAAcIlxrZKAAaAgc5DAAABgBRADsMAAAGAEMAOgwAAAYATwA8DAAABQA1ADIMAAAFAD4APQwAAAUAOwA+DAAAAwBJABIABwiXGtkoABoCBzkMAAAFAFEAOwwAAAUAQwA6DAAABQBPADwMAAAEADUAMgwAAAQAPgA9DAAABAA7AD4MAAADAEkAEwAGCBIKR1sAFgEGOQwAAAEAEQA7DAAAAQArADoMAAABABsAPAwAAAEAFwAyDAAAAQAWAD0MAAABABQAAAA=.Litzii:BAEALAADCgcIBwAAAA==.',Mi='Mimimagick:BAEALAADCgcIDQABLAAECgYIBgAMAAAAAA==.',Mm='Mmrblinker:BAEALAAECgYIBgAAAA==.',My='Mynoghra:BAEALAAECgcICgABLAAECggIKwACALAeAA==.',Na='Namelya:BAEALAAECggICAABLAAFFAIIAgAMAAAAAA==.Namgor:BAEALAADCgcIBwABLAAFFAIIAgAMAAAAAA==.Namhunt:BAEALAAFFAIIAgAAAA==.Namwyn:BAEBLAAECoE3AAMHAAgI0x6VGACfAgg5DAAACQBhADsMAAAJAEAAOgwAAAkAYgA8DAAACABQADIMAAAJAF0APQwAAAcAWwA+DAAAAwA7AD8MAAABAC0ABwAICNMelRgAnwIIOQwAAAgAYQA7DAAACABAADoMAAAIAGIAPAwAAAcAUAAyDAAABwBdAD0MAAAGAFsAPgwAAAMAOwA/DAAAAQAtABQABghTGMpMAK8BBjkMAAABAFMAOwwAAAEARwA6DAAAAQADADwMAAABAEsAMgwAAAIAOQA9DAAAAQBQAAEsAAUUAggCAAwAAAAA.',Pi='Pinkywonka:BAECLAAFFIEbAAIEAAYI/R9nAQBFAgY5DAAABQBiADsMAAAGAFYAOgwAAAYAWwA8DAAABABZADIMAAACAC0APQwAAAQAUAAEAAYI/R9nAQBFAgY5DAAABQBiADsMAAAGAFYAOgwAAAYAWwA8DAAABABZADIMAAACAC0APQwAAAQAUAAsAAQKgSQAAgQACAjzJbMCAF8DAAQACAjzJbMCAF8DAAAA.',Pr='Premort:BAEALAAECgYIDgABLAAECggIFwALAPIkAA==.',['Pï']='Pïnkywonkâ:BAEBLAAECoErAAISAAgIEiTbBAAyAwg5DAAABQBfADsMAAAHAF8AOgwAAAYAXAA8DAAABgBZADIMAAAGAF8APQwAAAYAYQA+DAAABABfAD8MAAADAE0AEgAICBIk2wQAMgMIOQwAAAUAXwA7DAAABwBfADoMAAAGAFwAPAwAAAYAWQAyDAAABgBfAD0MAAAGAGEAPgwAAAQAXwA/DAAAAwBNAAEsAAUUBggbAAQA/R8A.',Ra='Raspberryice:BAECLAAFFIENAAIFAAMIuSSkCQBKAQM5DAAABQBdADsMAAADAF4AOgwAAAUAXgAFAAMIuSSkCQBKAQM5DAAABQBdADsMAAADAF4AOgwAAAUAXgAsAAQKgS8AAgUACAhuJWkEAFcDAAUACAhuJWkEAFcDAAAA.',Re='Renälda:BAEALAAECgUIBQABLAAFFAMICQADAM8fAA==.',Si='Sigmaskibidi:BAEALAADCggIDgABLAAFFAMIDQAFALkkAA==.',St='Stefaniouf:BAECLAAFFIEGAAIUAAMIKwabFQDBAAM5DAAAAgAEADoMAAADACcAPAwAAAEAAwAUAAMIKwabFQDBAAM5DAAAAgAEADoMAAADACcAPAwAAAEAAwAsAAQKgTAAAxQACAjXHpAZALQCABQACAjXHpAZALQCAAcAAggvC68AAVEAAAAA.',Sw='Swyzz:BAEALAAECgIIAgAAAA==.',['Tä']='Tätienova:BAEALAADCggICwABLAAECgYIBgAMAAAAAA==.',Va='Varala:BAEALAAECgEIAQABLAAECggIFwALAPIkAA==.Vartrogal:BAEBLAAECoEXAAILAAgI8iSGBAA7Awg5DAAAAwBiADsMAAAEAGEAOgwAAAMAYQA8DAAAAwBdADIMAAADAF8APQwAAAMAXAA+DAAAAwBYAD8MAAABAF0ACwAICPIkhgQAOwMIOQwAAAMAYgA7DAAABABhADoMAAADAGEAPAwAAAMAXQAyDAAAAwBfAD0MAAADAFwAPgwAAAMAWAA/DAAAAQBdAAAA.',Ve='Vergìl:BAECLAAFFIEGAAIKAAIIDhTsLwCeAAI5DAAAAwBDADoMAAADACMACgACCA4U7C8AngACOQwAAAMAQwA6DAAAAwAjACwABAqBHgACCgAHCLIjUiYAugIACgAHCLIjUiYAugIAAAA=.',Yo='Yoshimigi:BAEBLAAECoE6AAIHAAgIzyYhAACRAwg5DAAABwBjADsMAAAHAGMAOgwAAAcAYwA8DAAABwBjADIMAAAIAGMAPQwAAAoAYwA+DAAABgBgAD8MAAAGAGMABwAICM8mIQAAkQMIOQwAAAcAYwA7DAAABwBjADoMAAAHAGMAPAwAAAcAYwAyDAAACABjAD0MAAAKAGMAPgwAAAYAYAA/DAAABgBjAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end