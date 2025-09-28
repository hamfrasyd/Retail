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
 local lookup = {'Paladin-Holy','Unknown-Unknown','Warlock-Destruction','Druid-Restoration','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Mage-Fire','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Druid-Feral','DemonHunter-Vengeance','DeathKnight-Frost','Warrior-Fury','Priest-Holy','Warrior-Protection','Druid-Guardian','Paladin-Protection','Rogue-Outlaw','Paladin-Retribution','Priest-Shadow','Warrior-Arms',}; local provider = {region='EU',realm='Blackhand',name='EU',type='subscribers',zone=44,date='2025-09-25',data={Am='Ameliâ:BAEBLAAECoEgAAIBAAcIjx3TFABFAgc5DAAABgBZADsMAAAFAFMAOgwAAAUAQAA8DAAABQBGADIMAAAEAEIAPQwAAAUAVQA+DAAAAgBFAAEABwiPHdMUAEUCBzkMAAAGAFkAOwwAAAUAUwA6DAAABQBAADwMAAAFAEYAMgwAAAQAQgA9DAAABQBVAD4MAAACAEUAASwABAoICAMAAgAAAAA=.',Ar='Arcodo:BAEALAADCgUIBQABLAAFFAIIBQADACIJAA==.Arrg:BAEBLAAFFIEHAAIEAAMIBxKMCwDtAAM5DAAAAwBLADoMAAADAD4APwwAAAEAAAAEAAMIBxKMCwDtAAM5DAAAAwBLADoMAAADAD4APwwAAAEAAAABLAAFFAcIEAAFAHMPAA==.Arrgdh:BAEBLAAECoEVAAMGAAgI2QeGoAAJAQg5DAAAAwAHADsMAAAEABQAOgwAAAMACQA8DAAAAwALADIMAAADAB4APQwAAAMAEwA+DAAAAQAcAD8MAAABACEABgAICNkHhqAACQEIOQwAAAIABwA7DAAAAwAUADoMAAACAAkAPAwAAAIACwAyDAAAAgAeAD0MAAACABMAPgwAAAEAHAA/DAAAAQAhAAcABginATaZAIIABjkMAAABAAMAOwwAAAEABAA6DAAAAQAEADwMAAABAAMAMgwAAAEABAA9DAAAAQAEAAEsAAUUBwgQAAUAcw8A.Arrgdwarf:BAEALAAFFAIIBAABLAAFFAcIEAAFAHMPAA==.Arrgmändschn:BAECLAAFFIEQAAIFAAcIcw9LAQA9Agc5DAAABABiADsMAAACAAoAOgwAAAQAYgA8DAAAAgAvADIMAAABAAsAPQwAAAIACQA+DAAAAQAAAAUABwhzD0sBAD0CBzkMAAAEAGIAOwwAAAIACgA6DAAABABiADwMAAACAC8AMgwAAAEACwA9DAAAAgAJAD4MAAABAAAALAAECoEmAAIFAAgIAB6JBgC3AgAFAAgIAB6JBgC3AgAAAA==.Arrgwl:BAEALAAFFAIIBAABLAAFFAcIEAAFAHMPAA==.',Ba='Baradh:BAEALAAFFAIIAgABLAAFFAYIEQAIAAYZAA==.Baramage:BAECLAAFFIERAAMIAAYIBhnvCgDOAQY5DAAABABcADsMAAAEADwAOgwAAAQAUAA8DAAAAgAyADIMAAABABQAPQwAAAIAUAAIAAUIZhzvCgDOAQU5DAAAAwBcADsMAAAEADwAOgwAAAQAUAA8DAAAAQAyAD0MAAACAFAACQADCFkOHgIA6wADOQwAAAEAMwA8DAAAAQAlADIMAAABABQALAAECoEvAAQJAAgIziIKAwCRAgAIAAcISyLEIgCxAgAJAAgIASEKAwCRAgAKAAYIOCLoHAATAgAAAA==.Baramonk:BAEBLAAECoEkAAQLAAgIWB3/CQCoAgg5DAAABgBQADsMAAAGAFkAOgwAAAYARwA8DAAABQBCADIMAAAFAFcAPQwAAAQAXAA+DAAAAgBHAD8MAAACACoACwAICFgd/wkAqAIIOQwAAAIAUAA7DAAAAwBZADoMAAADAEcAPAwAAAMAQgAyDAAAAwBXAD0MAAACAFwAPgwAAAEARwA/DAAAAgAqAAwABwi/IfQPAIcCBzkMAAAEAFsAOwwAAAMAXAA6DAAAAgBPADwMAAACAFsAMgwAAAIAVgA9DAAAAgBNAD4MAAABAFYADQABCL0jUD8ARQABOgwAAAEAWwABLAAFFAYIEQAIAAYZAA==.Barapriest:BAEALAAECgYIBgABLAAFFAYIEQAIAAYZAA==.Baravoker:BAEBLAAECoEVAAMOAAgIkiEWBwD4AQg5DAAAAwBdADsMAAADAFUAOgwAAAMATAA8DAAAAwBaADIMAAADAFoAPQwAAAMAUAA+DAAAAgBZAD8MAAABAFAADwAHCCoZCB4AFAIHOQwAAAMAXQA7DAAAAwBVADoMAAADAEwAPAwAAAIAPQAyDAAAAgA6AD0MAAACACUAPgwAAAEAJgAOAAUIxiEWBwD4AQU8DAAAAQBaADIMAAABAFoAPQwAAAEAUAA+DAAAAQBZAD8MAAABAFAAASwABRQGCBEACAAGGQA=.Barawarlock:BAEBLAAECoEoAAQDAAgIGiTLCABFAwg5DAAABgBhADsMAAAGAF0AOgwAAAYAXAA8DAAABgBfADIMAAAFAF0APQwAAAUAUgA+DAAAAwBeAD8MAAADAFkAAwAICBokywgARQMIOQwAAAUAYQA7DAAABQBdADoMAAAFAFwAPAwAAAYAXwAyDAAABABdAD0MAAAEAFIAPgwAAAMAXgA/DAAAAwBZABAABAjPG0tMABwBBDkMAAABAFoAOwwAAAEATQA6DAAAAQA7AD0MAAABADkAEQABCFQeMjQATAABMgwAAAEATQABLAAFFAYIEQAIAAYZAA==.Barawarry:BAEALAADCggIEAABLAAFFAYIEQAIAAYZAA==.',Be='Benqti:BAECLAAFFIEQAAMSAAYIrBK0BQDPAQY5DAAABABTADsMAAADACIAOgwAAAQANwA8DAAAAgBCADIMAAABAB0APQwAAAIADwASAAYIrBK0BQDPAQY5DAAABABTADsMAAACACIAOgwAAAQANwA8DAAAAgBCADIMAAABAB0APQwAAAIADwATAAEINwLNMQAvAAE7DAAAAQAFACwABAqBMQADEgAICMQjCxcA3QIAEgAICMQjCxcA3QIAEwACCK0TJpUAcQAAASwABAoICBgAAwD/DwA=.Benqtidruid:BAEBLAAECoEsAAMUAAgIth5xGwBfAgg5DAAABwBZADsMAAAGAFYAOgwAAAYAXgA8DAAABgBTADIMAAAGAEwAPQwAAAYAVAA+DAAABAA4AD8MAAADADoAFAAICKcdcRsAXwIIOQwAAAMAWQA7DAAAAgBCADoMAAADAF4APAwAAAMAUQAyDAAAAwBMAD0MAAADAFQAPgwAAAIAOAA/DAAAAgA6ABUACAhnGA4QAC8CCDkMAAAEAEgAOwwAAAQAVgA6DAAAAwBSADwMAAADAFMAMgwAAAMAPQA9DAAAAwBFAD4MAAACACcAPwwAAAEABQABLAAECggIGAADAP8PAA==.Benqtilock:BAEBLAAECoEYAAMDAAgI/w9MTQDgAQg5DAAABAAyADsMAAAEADIAOgwAAAMAJwA8DAAAAwAxADIMAAADACsAPQwAAAMAHgA+DAAAAgApAD8MAAACABUAAwAICP8PTE0A4AEIOQwAAAQAMgA7DAAABAAyADoMAAADACcAPAwAAAMAMQAyDAAAAwArAD0MAAABAB4APgwAAAIAKQA/DAAAAgAVABEAAQjyA0I+ADMAAT0MAAACAAoAAAA=.Benqtimage:BAEALAAECggIEQABLAAECggIGAADAP8PAA==.Benqtirogue:BAEALAADCggICAABLAAECggIGAADAP8PAA==.Benqtischami:BAEBLAAECoEaAAIHAAgIWRJKOQD+AQg5DAAABAAwADsMAAAEACoAOgwAAAUANQA8DAAABAAyADIMAAAEADMAPQwAAAMAKgA+DAAAAQAsAD8MAAABACoABwAICFkSSjkA/gEIOQwAAAQAMAA7DAAABAAqADoMAAAFADUAPAwAAAQAMgAyDAAABAAzAD0MAAADACoAPgwAAAEALAA/DAAAAQAqAAEsAAQKCAgYAAMA/w8A.',Bl='Bleedting:BAEALAAECgMIBAAAAA==.',Ca='Callmewall:BAEALAAECgYIBgAAAA==.',Ch='Chaoskirito:BAEALAAECggICAAAAA==.Chîting:BAEALAAECgIIAgABLAAECgMIBAACAAAAAA==.',Cr='Crâton:BAECLAAFFIEFAAIDAAIIIgmdNgCJAAI5DAAAAgASADoMAAADABwAAwACCCIJnTYAiQACOQwAAAIAEgA6DAAAAwAcACwABAqBLgACAwAICDgc/CAAqQIAAwAICDgc/CAAqQIAAAA=.',Da='Dajanirâ:BAEALAAECgYIBgABLAAECgUIBgACAAAAAA==.',De='Deeling:BAEALAAECgYIEgABLAAECgcIFQAWAO4fAA==.',Dk='Dkbert:BAEBLAAECoEuAAIXAAgIBCY2BABrAwg5DAAABwBiADsMAAAHAGMAOgwAAAYAYwA8DAAABwBgADIMAAAGAGMAPQwAAAUAXAA+DAAABABgAD8MAAAEAF8AFwAICAQmNgQAawMIOQwAAAcAYgA7DAAABwBjADoMAAAGAGMAPAwAAAcAYAAyDAAABgBjAD0MAAAFAFwAPgwAAAQAYAA/DAAABABfAAEsAAUUBggZABgAgyAA.',Dr='Drehbert:BAEBLAAECoEUAAILAAgI4RSxFQD2AQg5DAAAAgAvADsMAAACAEUAOgwAAAMAOAA8DAAAAwASADIMAAADADsAPQwAAAMAQgA+DAAAAgA0AD8MAAACADkACwAICOEUsRUA9gEIOQwAAAIALwA7DAAAAgBFADoMAAADADgAPAwAAAMAEgAyDAAAAwA7AD0MAAADAEIAPgwAAAIANAA/DAAAAgA5AAEsAAUUBggZABgAgyAA.',Ev='Evildruid:BAEBLAAECoEaAAIEAAgIViNWBgAdAwg5DAAABABjADsMAAAFAGAAOgwAAAQAXgA8DAAABABgADIMAAAEAF8APQwAAAMAUAA+DAAAAQBEAD8MAAABAF0ABAAICFYjVgYAHQMIOQwAAAQAYwA7DAAABQBgADoMAAAEAF4APAwAAAQAYAAyDAAABABfAD0MAAADAFAAPgwAAAEARAA/DAAAAQBdAAEsAAQKCAgaABkAPR8A.Evilevoker:BAECLAAFFIEUAAIFAAYI1RiMAgDrAQY5DAAABABHADsMAAAEAF4AOgwAAAUALQA8DAAAAwA7ADIMAAACAEgAPQwAAAIAJgAFAAYI1RiMAgDrAQY5DAAABABHADsMAAAEAF4AOgwAAAUALQA8DAAAAwA7ADIMAAACAEgAPQwAAAIAJgAsAAQKgSgAAgUACAi0FjoOACICAAUACAi0FjoOACICAAEsAAQKCAgaABkAPR8A.',Fa='Fassmichan:BAECLAAFFIEKAAISAAII+xgzLACQAAI5DAAABQA1ADoMAAAFAEoAEgACCPsYMywAkAACOQwAAAUANQA6DAAABQBKACwABAqBRAACEgAICBwjgw8ADQMAEgAICBwjgw8ADQMAAAA=.',Ge='Getsù:BAEBLAAECoEWAAIPAAgIoh1NGABMAgg5DAAAAgBfADsMAAACAFwAOgwAAAIAUAA8DAAABABaADIMAAAEAFoAPQwAAAQAXgA+DAAAAgAUAD8MAAACACkADwAICKIdTRgATAIIOQwAAAIAXwA7DAAAAgBcADoMAAACAFAAPAwAAAQAWgAyDAAABABaAD0MAAAEAF4APgwAAAIAFAA/DAAAAgApAAAA.',Go='Goatekin:BAEALAADCggICQABLAAECggIHwASANscAA==.',['Gë']='Gëtsu:BAEALAAECgcIEwABLAAECggIFgAPAKIdAA==.',['Gö']='Görny:BAEBLAAECoEfAAISAAgI2xygMABgAgg5DAAABgBhADsMAAAGAGMAOgwAAAUAXAA8DAAAAwBiADIMAAAFAF4APQwAAAQAYAA+DAAAAQABAD8MAAABAAoAEgAICNscoDAAYAIIOQwAAAYAYQA7DAAABgBjADoMAAAFAFwAPAwAAAMAYgAyDAAABQBeAD0MAAAEAGAAPgwAAAEAAQA/DAAAAQAKAAAA.',Ha='Haumiwarry:BAEALAAECggIDgABLAAECggIMwAaANkiAA==.',He='Heilprisi:BAEALAAECgYIDAABLAAECggIAwACAAAAAA==.',Ho='Holydur:BAEALAAFFAIIAgABLAAFFAcIEAAGACcJAA==.',Ib='Iborekin:BAEALAAECgIIAgAAAA==.',In='Inmórtal:BAECLAAFFIEGAAIGAAII9xBkOwBzAAI5DAAAAwAyADoMAAADACQABgACCPcQZDsAcwACOQwAAAMAMgA6DAAAAwAkACwABAqBHgACBgAHCDoeESsARwIABgAHCDoeESsARwIAAAA=.Inmórtál:BAEALAAECgYIBgABLAAFFAIIBgAGAPcQAA==.',['Jå']='Jåle:BAEALAAECgIIAgAAAA==.',Kl='Klotzy:BAEALAAECggIEwABLAAECggIHwASANscAA==.',Ky='Kyranth:BAEALAADCgMIAwABLAAFFAIIBgAbAPwdAA==.',['Ká']='Káralas:BAEBLAAECoEeAAIcAAcIICDjEABVAgc5DAAABQBSADsMAAAFAFUAOgwAAAUAWwA8DAAABABEADIMAAAEAE0APQwAAAQAVQA+DAAAAwBTABwABwggIOMQAFUCBzkMAAAFAFIAOwwAAAUAVQA6DAAABQBbADwMAAAEAEQAMgwAAAQATQA9DAAABABVAD4MAAADAFMAAAA=.',['Kê']='Kêss:BAEALAADCgQIBQABLAAECgIIAgACAAAAAA==.',['Kî']='Kîzàru:BAEALAAECggIEAABLAAECggIGAAdAHwPAA==.',Li='Lightymax:BAECLAAFFIENAAIBAAMIMBtKCQD9AAM5DAAABQBFADsMAAADAD8AOgwAAAUASwABAAMIMBtKCQD9AAM5DAAABQBFADsMAAADAD8AOgwAAAUASwAsAAQKgScAAgEACAiBJCcBAFUDAAEACAiBJCcBAFUDAAEsAAQKBwgTAAIAAAAA.Lightypriest:BAEALAAECgcIEwAAAA==.Liwî:BAEALAAECggIAwAAAA==.Lizzydk:BAECLAAFFIEUAAIXAAUIjRiQCQC9AQU5DAAABgBKADsMAAAEAEEAOgwAAAYAPAA8DAAAAgAkAD0MAAACAE0AFwAFCI0YkAkAvQEFOQwAAAYASgA7DAAABABBADoMAAAGADwAPAwAAAIAJAA9DAAAAgBNACwABAqBLwACFwAICHIi1hsA6AIAFwAICHIi1hsA6AIAAAA=.',Ma='Madarkani:BAEALAAECggICgABLAAECgYIDQACAAAAAA==.Madpala:BAEBLAAECoEiAAMeAAgIFyNqDAA/Awg5DAAABQBhADsMAAAFAGEAOgwAAAYAYwA8DAAABgBYADIMAAAFAGEAPQwAAAUAYgA+DAAAAQBRAD8MAAABADsAHgAICBcjagwAPwMIOQwAAAUAYQA7DAAABQBhADoMAAAFAGMAPAwAAAUAWAAyDAAABQBhAD0MAAAFAGIAPgwAAAEAUQA/DAAAAQA7AAEAAgjZDSldAHYAAjoMAAABABgAPAwAAAEALgABLAAECgYIDQACAAAAAA==.Madvanishjin:BAEALAAECgYIDQAAAA==.',Ne='Nerto:BAECLAAFFIEYAAIVAAYIhhb0AAAFAgY5DAAABgBeADsMAAAFADMAOgwAAAYAUwA8DAAAAwBOADIMAAABABYAPQwAAAMADwAVAAYIhhb0AAAFAgY5DAAABgBeADsMAAAFADMAOgwAAAYAUwA8DAAAAwBOADIMAAABABYAPQwAAAMADwAsAAQKgSwAAhUACAgQIWgGAOICABUACAgQIWgGAOICAAAA.Nevertøxic:BAEBLAAFFIEKAAIXAAIIYiPuJgC4AAI5DAAABQBaADoMAAAFAFoAFwACCGIj7iYAuAACOQwAAAUAWgA6DAAABQBaAAAA.',Ni='Niborwer:BAEALAADCggIDgABLAAFFAIIBgAbAPwdAA==.',['Ná']='Námaa:BAEALAAECgcIBwABLAAECgcIHgAcACAgAA==.',Ok='Okotô:BAEALAADCgcIFQAAAA==.',Pa='Padii:BAEALAAECgcIDQAAAA==.Pallybert:BAEALAAECgcIDQABLAAFFAYIGQAYAIMgAA==.',Qi='Qinqmonk:BAECLAAFFIEMAAIMAAUIEBu8AgDFAQU5DAAABABdADsMAAABADIAOgwAAAMAWQA8DAAAAwBTAD0MAAABAB4ADAAFCBAbvAIAxQEFOQwAAAQAXQA7DAAAAQAyADoMAAADAFkAPAwAAAMAUwA9DAAAAQAeACwABAqBNQACDAAICA8mDgEAegMADAAICA8mDgEAegMAAAA=.',Re='Reîzwäsche:BAEALAAECgMIAwAAAA==.',Ri='Rimurû:BAEALAAECgYIBgABLAAECggIAwACAAAAAA==.',Ry='Ryumã:BAEBLAAECoEYAAIdAAgIfA/2CwCVAQg5DAAAAwBXADsMAAADACYAOgwAAAMAUQA8DAAAAwAZADIMAAADAEYAPQwAAAMAAQA+DAAAAwABAD8MAAADAAoAHQAICHwP9gsAlQEIOQwAAAMAVwA7DAAAAwAmADoMAAADAFEAPAwAAAMAGQAyDAAAAwBGAD0MAAADAAEAPgwAAAMAAQA/DAAAAwAKAAAA.',Sa='Saphiry:BAEALAAECgcIDgAAAQ==.',Sc='Scheibi:BAEALAAECggIEAAAAA==.Schlexdk:BAEALAAECggIEgABLAAECggIHwASANscAA==.',Se='Serapherion:BAEALAAECgMIAwABLAAFFAIIBgAbAPwdAA==.',Sh='Shoxxypump:BAECLAAFFIEYAAIFAAYIfx9oAQA1AgY5DAAABQBQADsMAAAEAFIAOgwAAAQATgA8DAAABABKADIMAAAEAE8APQwAAAMAWAAFAAYIfx9oAQA1AgY5DAAABQBQADsMAAAEAFIAOgwAAAQATgA8DAAABABKADIMAAAEAE8APQwAAAMAWAAsAAQKgSgAAgUACAgUJkkBAE0DAAUACAgUJkkBAE0DAAAA.Shoxxyqt:BAEALAAECgUIBwABLAAFFAYIGAAFAH8fAA==.',So='Sogekiñg:BAEALAAECggICAABLAAECggIGAAdAHwPAA==.',St='Styffenlock:BAEALAAECggIEwAAAA==.Styffenmage:BAEALAAECggIDgABLAAECggIEwACAAAAAA==.Styffenwl:BAECLAAFFIEdAAMDAAgIdCNYAAAZAwg5DAAABABjADsMAAADAGEAOgwAAAQAYwA8DAAABABZADIMAAAFAFwAPQwAAAUAYgA+DAAAAwBXAD8MAAABADwAAwAICHQjWAAAGQMIOQwAAAMAYwA7DAAAAwBhADoMAAACAGMAPAwAAAQAWQAyDAAABQBcAD0MAAAFAGIAPgwAAAMAVwA/DAAAAQA8ABAAAgj/FrEPAJ8AAjkMAAABAE8AOgwAAAIAJQAsAAQKgSQABAMACAjpJmwAAJsDAAMACAjoJmwAAJsDABEABQiYIWsOALABABAAAgiMJEBmAKsAAAEsAAQKCAgTAAIAAAAA.',['Sø']='Sønnie:BAEALAAECgUIBgAAAA==.',To='Tokhath:BAEALAAECgMIBQABLAAECggIEAACAAAAAA==.Totemting:BAEALAAECggIBwABLAAECgMIBAACAAAAAA==.',Tr='Treadknight:BAEALAAECgQICQABLAAECggIEAACAAAAAA==.',Ve='Vealin:BAEALAAECgMIAwABLAAFFAYIGgAfAB4jAA==.',Wa='Waidur:BAEALAAFFAEIAQABLAAFFAcIEAAGACcJAA==.Warribert:BAECLAAFFIEZAAIYAAYIgyDIAQBrAgY5DAAABgBiADsMAAAEAEgAOgwAAAYAYwA8DAAABABUADIMAAABAEcAPQwAAAQASQAYAAYIgyDIAQBrAgY5DAAABgBiADsMAAAEAEgAOgwAAAYAYwA8DAAABABUADIMAAABAEcAPQwAAAQASQAsAAQKgTgAAxgACAjOJjwAAKIDABgACAjOJjwAAKIDACAAAQjrJdoqAG8AAAAA.',Wi='Wingstrument:BAECLAAFFIESAAIPAAUIeB73BAC6AQU5DAAABQBWADsMAAAFAF4AOgwAAAUARAA8DAAAAgA2AD0MAAABAFUADwAFCHge9wQAugEFOQwAAAUAVgA7DAAABQBeADoMAAAFAEQAPAwAAAIANgA9DAAAAQBVACwABAqBIgACDwAICNoj3gUAKQMADwAICNoj3gUAKQMAAAA=.',Wu='Wuschélchen:BAEALAAECgEIAQABLAAECgYIDQACAAAAAA==.',Xa='Xalating:BAEALAAECggIBQABLAAECgMIBAACAAAAAA==.',Za='Zaorex:BAEALAADCgMIAwABLAAFFAIIBQADACIJAA==.Zarend:BAECLAAFFIEGAAIbAAII/B3GAgCsAAI5DAAAAwBQADoMAAADAEgAGwACCPwdxgIArAACOQwAAAMAUAA6DAAAAwBIACwABAqBJwACGwAHCFwjUAQAwwIAGwAHCFwjUAQAwwIAAAA=.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end