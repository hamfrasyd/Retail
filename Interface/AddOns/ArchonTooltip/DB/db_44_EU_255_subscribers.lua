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
 local lookup = {'Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Evoker-Augmentation','DemonHunter-Havoc','Unknown-Unknown','Monk-Mistweaver','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Monk-Windwalker','Mage-Frost','Druid-Guardian','Priest-Shadow','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','DeathKnight-Frost','Evoker-Devastation','Hunter-Marksmanship','Rogue-Outlaw','Rogue-Assassination',}; local provider = {region='EU',realm='ArgentDawn',name='EU',type='subscribers',zone=44,date='2025-09-25',data={Ag='Aggarmage:BAEALAAECgYIBgABLAAFFAYIFAABABAXAA==.Aggarnar:BAECLAAFFIEUAAMBAAYIEBdOCAD2AQY5DAAAAgBKADsMAAAGAFMAOgwAAAUAQgA8DAAABAA/ADIMAAABAC0APQwAAAIAFQABAAYIEBdOCAD2AQY5DAAAAgBKADsMAAAGAFMAOgwAAAQAQgA8DAAABAA/ADIMAAABAC0APQwAAAIAFQACAAEIGRgeHwBUAAE6DAAAAQA9ACwABAqBKAAEAQAICN0jDQ0AJgMAAQAICKcjDQ0AJgMAAwAGCG0RdBEAfwEAAgAECAYV/E0AFAEAAAA=.',Al='Alaharnya:BAEALAADCgUIBQABLAAECgcIJAAEAM8YAA==.Alyenora:BAEALAAFFAMIBQABLAAFFAYIDQAFAKwPAQ==.',Am='Amineh:BAEALAAECgYIDAABLAAFFAYIDQAFAKwPAA==.',Ar='Arahnacar:BAEBLAAECoEkAAMEAAcIzxhuFwDgAQc5DAAABgBGADsMAAAGAEAAOgwAAAYAPgA8DAAABQBKADIMAAAFACkAPQwAAAQAPQA+DAAABABGAAQABwjPGG4XAOABBzkMAAAEAEYAOwwAAAQAQAA6DAAABAA+ADwMAAAEAEoAMgwAAAQAKQA9DAAAAwA9AD4MAAADAEYABgAHCHcHj7cAMgEHOQwAAAIAFgA7DAAAAgAoADoMAAACAAsAPAwAAAEABAAyDAAAAQAJAD0MAAABAB0APgwAAAEADwAAAA==.',Be='Benedictina:BAEALAAECgIIAgABLAAECgEIAQAHAAAAAA==.',Bm='Bmart:BAEALAAECgcICgABLAAECgEIAQAHAAAAAA==.',De='Deidsi:BAEALAADCgcIBwABLAAECggIGQAIAP4LAA==.Delyrien:BAEALAAECggIEQABLAAECggIEgAHAAAAAA==.',Dr='Dreandur:BAEALAADCggICAAAAA==.Driptinus:BAECLAAFFIEWAAIJAAYIDCSmAQAvAgY5DAAABQBiADsMAAADAFgAOgwAAAUAYgA8DAAAAwBEADIMAAADAGIAPQwAAAMAZAAJAAYIDCSmAQAvAgY5DAAABQBiADsMAAADAFgAOgwAAAUAYgA8DAAAAwBEADIMAAADAGIAPQwAAAMAZAAsAAQKgRYAAgkACAiHIuoJAAUDAAkACAiHIuoJAAUDAAAA.',El='Elehjul:BAEALAADCggICAABLAAFFAMIDAAGAMQjAA==.Elejulngr:BAEBLAAECoEjAAIKAAgI+CYQAACrAwg5DAAABABjADsMAAAEAGMAOgwAAAQAYwA8DAAABABjADIMAAAEAGMAPQwAAAUAYwA+DAAABQBjAD8MAAAFAGMACgAICPgmEAAAqwMIOQwAAAQAYwA7DAAABABjADoMAAAEAGMAPAwAAAQAYwAyDAAABABjAD0MAAAFAGMAPgwAAAUAYwA/DAAABQBjAAEsAAUUAwgMAAYAxCMA.Elejulw:BAEALAADCggICAABLAAFFAMIDAAGAMQjAA==.Elejulxo:BAECLAAFFIEMAAMGAAMIxCPADgAmAQM5DAAABQBfADsMAAACAFEAOgwAAAUAYQAGAAMIqiLADgAmAQM5DAAABABeADsMAAACAFEAOgwAAAQAWQAEAAIIqCViBADRAAI5DAAAAQBfADoMAAABAGEALAAECoEqAAMGAAgI9ib6AACSAwAGAAgI2Cb6AACSAwAEAAYI9ialCAC0AgAAAA==.Elerogue:BAEALAAFFAIIBAABLAAFFAMIDAAGAMQjAA==.Eleyul:BAECLAAFFIEJAAMLAAMInCT+BQBCAQM5DAAABABbADsMAAABAFwAOgwAAAQAYQALAAMInCT+BQBCAQM5DAAAAwBbADsMAAABAFwAOgwAAAMAYQAMAAIIVhkuCwCjAAI5DAAAAQBAADoMAAABAEEALAAECoEjAAMLAAgIQCbEAAB+AwALAAgICibEAAB+AwAMAAgIkSIcBwAMAwABLAAFFAMIDAAGAMQjAA==.Elunerae:BAEALAAECgYIBgABLAAFFAYIFAABABAXAA==.',Es='Eserìa:BAEBLAAECoErAAILAAgIzyEnBQAOAwg5DAAABgBTADsMAAAHAFIAOgwAAAYAWAA8DAAABQBbADIMAAAGAFcAPQwAAAYAXwA+DAAABABPAD8MAAADAFMACwAICM8hJwUADgMIOQwAAAYAUwA7DAAABwBSADoMAAAGAFgAPAwAAAUAWwAyDAAABgBXAD0MAAAGAF8APgwAAAQATwA/DAAAAwBTAAAA.',Fr='Frysedisk:BAEBLAAECoErAAINAAgInAwLLACwAQg5DAAABwAwADsMAAAHACQAOgwAAAYAEwA8DAAABgAlADIMAAAFACEAPQwAAAUAJwA+DAAABAATAD8MAAADABYADQAICJwMCywAsAEIOQwAAAcAMAA7DAAABwAkADoMAAAGABMAPAwAAAYAJQAyDAAABQAhAD0MAAAFACcAPgwAAAQAEwA/DAAAAwAWAAAA.',Go='Goosebrew:BAEALAAFFAIIBAABLAAFFAcIHgAOANMcAA==.Goosedru:BAECLAAFFIEeAAIOAAcI0xwGAADNAgc5DAAABgBjADsMAAAFAF8AOgwAAAYAXgA8DAAABABLADIMAAAEADoAPQwAAAQARQA+DAAAAQAXAA4ABwjTHAYAAM0CBzkMAAAGAGMAOwwAAAUAXwA6DAAABgBeADwMAAAEAEsAMgwAAAQAOgA9DAAABABFAD4MAAABABcALAAECoEZAAIOAAgIyiU5AQBXAwAOAAgIyiU5AQBXAwAAAA==.Goosewarr:BAEALAAECgYIDAABLAAFFAcIHgAOANMcAA==.Gorâ:BAECLAAFFIERAAIPAAUIARgFBwCmAQU5DAAABQBYADsMAAAEACwAOgwAAAUALAA8DAAAAgBUAD0MAAABAC0ADwAFCAEYBQcApgEFOQwAAAUAWAA7DAAABAAsADoMAAAFACwAPAwAAAIAVAA9DAAAAQAtACwABAqBKwACDwAICLkiJwoAGwMADwAICLkiJwoAGwMAAAA=.',Hy='Hyunseo:BAECLAAFFIEKAAIQAAQI2xIuDQA3AQQ5DAAAAwBbADsMAAADAB0AOgwAAAMAOgA8DAAAAQAOABAABAjbEi4NADcBBDkMAAADAFsAOwwAAAMAHQA6DAAAAwA6ADwMAAABAA4ALAAECoEfAAIQAAgIECOSDAAgAwAQAAgIECOSDAAgAwAAAA==.',Ic='Ictinus:BAEALAAECggIEgABLAAFFAYIFgAJAAwkAA==.',Is='Iszy:BAEALAAECggIEgAAAA==.',Je='Jegerprøven:BAEALAADCggICAABLAAECggIKwANAJwMAA==.',Ki='Kirc:BAECLAAFFIEKAAIRAAUI5SLHAwD1AQU5DAAAAwBhADsMAAACAGEAOgwAAAMAYgA8DAAAAQBHAD0MAAABAFIAEQAFCOUixwMA9QEFOQwAAAMAYQA7DAAAAgBhADoMAAADAGIAPAwAAAEARwA9DAAAAQBSACwABAqBMQACEQAICOUmTwAAogMAEQAICOUmTwAAogMAAAA=.',Lu='Lumeo:BAEALAAECgEIAQAAAA==.',Ly='Lyareth:BAEALAADCgcIBwABLAAFFAYIDQAFAKwPAA==.',Me='Menki:BAEBLAAECoEZAAMIAAgI/gs6JABVAQg5DAAABAAjADsMAAAEACEAOgwAAAQAJAA8DAAABAASADIMAAADACcAPQwAAAMAIQA+DAAAAgAYAD8MAAABABcACAAICP4LOiQAVQEIOQwAAAMAIwA7DAAAAwAhADoMAAADACQAPAwAAAIAEgAyDAAAAgAnAD0MAAACACEAPgwAAAEAGAA/DAAAAQAXAAwABwiiCfU2AC8BBzkMAAABACUAOwwAAAEAAQA6DAAAAQAOADwMAAACAB4AMgwAAAEAKQA9DAAAAQAWAD4MAAABABgAAAA=.',Na='Narystra:BAEBLAAECoEXAAIRAAcIER6aNAB+Agc5DAAABABMADsMAAAEAE8AOgwAAAQATwA8DAAABABdADIMAAADAFoAPQwAAAMARgA+DAAAAQAxABEABwgRHpo0AH4CBzkMAAAEAEwAOwwAAAQATwA6DAAABABPADwMAAAEAF0AMgwAAAMAWgA9DAAAAwBGAD4MAAABADEAASwABRQGCA0ABQCsDwA=.',No='Nonã:BAEALAAECgYICgABLAAECgcIHwASADomAA==.',['Né']='Névin:BAEALAAECgQICwAAAA==.',['Nò']='Nòna:BAEBLAAECoEfAAISAAcIOiboDADyAgc5DAAABQBjADsMAAAFAGIAOgwAAAUAYwA8DAAABQBhADIMAAAEAF8APQwAAAQAXwA+DAAAAwBjABIABwg6JugMAPICBzkMAAAFAGMAOwwAAAUAYgA6DAAABQBjADwMAAAFAGEAMgwAAAQAXwA9DAAABABfAD4MAAADAGMAAAA=.Nònà:BAEALAAECgIIAgABLAAECgcIHwASADomAA==.',['Nó']='Nóná:BAEBLAAECoEbAAITAAgIhSMJCwA9Awg5DAAAAwBeADsMAAADAFoAOgwAAAQAYwA8DAAABABcADIMAAAEAFsAPQwAAAQAWwA+DAAAAgBQAD8MAAADAFYAEwAICIUjCQsAPQMIOQwAAAMAXgA7DAAAAwBaADoMAAAEAGMAPAwAAAQAXAAyDAAABABbAD0MAAAEAFsAPgwAAAIAUAA/DAAAAwBWAAEsAAQKBwgfABIAOiYA.',Sa='Saerira:BAEALAAECggIDQABLAAECggIEgAHAAAAAA==.',Se='Seaine:BAEALAAECgYIDAABLAAECgEIAQAHAAAAAA==.',So='Soreldra:BAECLAAFFIENAAIFAAYIrA+rAQC8AQY5DAAABABHADsMAAACADIAOgwAAAQATgA8DAAAAQAAADIMAAABAAkAPQwAAAEAHQAFAAYIrA+rAQC8AQY5DAAABABHADsMAAACADIAOgwAAAQATgA8DAAAAQAAADIMAAABAAkAPQwAAAEAHQAsAAQKgTEAAwUACAjTIAoCAOECAAUACAipIAoCAOECABQABAgbG3M+ACsBAAAA.',Ta='Tazdiingo:BAEBLAAECoEcAAMQAAcIQh/+MgBXAgc5DAAABABDADsMAAAEAEAAOgwAAAQAXgA8DAAABABdADIMAAAFAGMAPQwAAAQAPgA+DAAAAwBNABAABwhCH/4yAFcCBzkMAAAEAEMAOwwAAAQAQAA6DAAABABeADwMAAAEAF0AMgwAAAQAYwA9DAAAAwA+AD4MAAADAE0AFQACCDUMP50AWwACMgwAAAEAEAA9DAAAAQAuAAAA.',Ye='Yeseo:BAECLAAFFIEFAAMWAAMIkANXAgC8AAM5DAAAAgANADsMAAABAAMAOgwAAAIACQAWAAMI2wJXAgC8AAM5DAAAAQAIADsMAAABAAMAOgwAAAIACQAXAAEIQQWjHgBFAAE5DAAAAQANACwABAqBIAADFgAICNIVrAcABQIAFgAICKgSrAcABQIAFwAGCCsQEDoAZAEAASwABRQECAoAEADbEgA=.',Za='Zanaeth:BAEBLAAECoE+AAMQAAgITiUrBgBPAwg5DAAACABiADsMAAAMAF8AOgwAAAsAYgA8DAAACwBhADIMAAAJAF4APQwAAAgAXgA+DAAAAgBjAD8MAAABAFYAEAAICE4lKwYATwMIOQwAAAcAYgA7DAAADABfADoMAAALAGIAPAwAAAsAYQAyDAAACQBeAD0MAAAIAF4APgwAAAIAYwA/DAAAAQBWABUAAQjQBYq9ACEAATkMAAABAA4AASwABRQGCA0ABQCsDwA=.',Zo='Zooks:BAEALAAECgMIAwABLAAECggIGQAIAP4LAA==.',['Zò']='Zòë:BAECLAAFFIEWAAIQAAYIBCKUAQBDAgY5DAAABgBdADsMAAADAFMAOgwAAAYAYwA8DAAAAwBWADIMAAABAFIAPQwAAAMATQAQAAYIBCKUAQBDAgY5DAAABgBdADsMAAADAFMAOgwAAAYAYwA8DAAAAwBWADIMAAABAFIAPQwAAAMATQAsAAQKgSQAAhAACAhgJRALACoDABAACAhgJRALACoDAAAA.',['Zó']='Zóë:BAEALAAECggIEgABLAAFFAYIFgAQAAQiAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end