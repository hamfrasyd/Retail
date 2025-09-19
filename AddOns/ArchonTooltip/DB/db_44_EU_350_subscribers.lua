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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Protection','Monk-Mistweaver','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Monk-Windwalker','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','Evoker-Preservation','Priest-Discipline','DeathKnight-Frost','Mage-Frost','Druid-Guardian','Priest-Holy','DemonHunter-Vengeance','Mage-Arcane','Mage-Fire','DeathKnight-Blood','Evoker-Devastation',}; local provider = {region='EU',realm='TwistingNether',name='EU',type='subscribers',zone=44,date='2025-09-06',data={An='Anusrelos:BAEALAADCggICAABLAAECgYICgABAAAAAA==.',Ar='Arhontas:BAEBLAAECoEZAAMCAAgIPhklCwBRAgg5DAAABABOADsMAAAEAFIAOgwAAAQAQwA8DAAABABJADIMAAADAD4APQwAAAMAIwA+DAAAAgA5AD8MAAABADkAAgAICD4ZJQsAUQIIOQwAAAMATgA7DAAAAwBSADoMAAADAEMAPAwAAAMASQAyDAAAAgA+AD0MAAACACMAPgwAAAEAOQA/DAAAAQA5AAMABwgnF6pbAHwBBzkMAAABAEoAOwwAAAEADwA6DAAAAQA1ADwMAAABADgAMgwAAAEAUwA9DAAAAQA8AD4MAAABAEcAAAA=.',Ay='Aythia:BAEALAAFFAIIBAABLAAFFAMIBwAEADobAA==.',Ba='Bababouey:BAEALAADCgMIAwABLAAECgEIAgABAAAAAA==.',Be='Beatrixa:BAEALAADCggICAAAAA==.',Bm='Bmbaclart:BAEBLAAECoEYAAMFAAcIWCGNEAB8Agc5DAAABABTADsMAAAEAFgAOgwAAAQAYAA8DAAAAwBLADIMAAADAFEAPQwAAAMAVgA+DAAAAwBVAAUABwhYIY0QAHwCBzkMAAADAFMAOwwAAAQAWAA6DAAABABgADwMAAADAEsAMgwAAAMAUQA9DAAAAwBWAD4MAAADAFUABgABCM4FRJwAIAABOQwAAAEADgAAAA==.',Ch='Chastityman:BAEALAADCggIFgABLAAECggIGAACAIASAA==.',De='Deoos:BAEALAAECggICQAAAA==.Dexxas:BAEALAADCgIIAgABLAAECggIHQAHAL4kAA==.',Dp='Dpsdiff:BAEALAADCggICAABLAAECgYICgABAAAAAA==.',Dr='Drakoncho:BAEALAAECgcIDgABLAAECggIHQAHAL4kAA==.',Du='Duskers:BAEALAAECggICwABLAAECggIFgAIACkfAA==.',Em='Empathý:BAECLAAFFIEKAAIDAAUI9h3VAADaAQU5DAAAAgBbADsMAAABAD8AOgwAAAIARgA8DAAAAwBMAD0MAAACAFEAAwAFCPYd1QAA2gEFOQwAAAIAWwA7DAAAAQA/ADoMAAACAEYAPAwAAAMATAA9DAAAAgBRACwABAqBIAACAwAICFomDQIAdwMAAwAICFomDQIAdwMAAAA=.',Ev='Everia:BAEALAAECgYIDAABLAAFFAUICgADAPYdAA==.',Fa='Faelksud:BAEALAADCggICAABLAAECggIFgAIACkfAA==.',Fe='Fendros:BAEALAAECggIDwABLAAFFAUIDAAJAAQZAA==.Fentality:BAEALAAECggIDQABLAAFFAUIDgAKAI8eAA==.Fenyo:BAECLAAFFIEOAAIKAAUIjx7ZAADnAQU5DAAABABcADsMAAADAEwAOgwAAAMAUQA8DAAAAgA/AD0MAAACAEwACgAFCI8e2QAA5wEFOQwAAAQAXAA7DAAAAwBMADoMAAADAFEAPAwAAAIAPwA9DAAAAgBMACwABAqBHAACCgAICOolOwEAaQMACgAICOolOwEAaQMAAAA=.',Fl='Flinsy:BAEBLAAECoEYAAMCAAgIgBJbEgD5AQg5DAAABABNADsMAAAEAD0AOgwAAAQAJAA8DAAAAwAPADIMAAADAEYAPQwAAAMANQA+DAAAAgAvAD8MAAABABEAAgAICIASWxIA+QEIOQwAAAIATQA7DAAAAgA9ADoMAAACACQAPAwAAAIADwAyDAAAAgBGAD0MAAACADUAPgwAAAIALwA/DAAAAQARAAMABghYDfp1AC0BBjkMAAACADgAOwwAAAIAIAA6DAAAAgAnADwMAAABABQAMgwAAAEAGAA9DAAAAQAgAAAA.Flöjtist:BAEALAAECgEIAgAAAA==.',Ga='Gaelbas:BAEBLAAECoEWAAILAAgIKhPtDQACAgg5DAAAAwA+ADsMAAADAFAAOgwAAAMAQgA8DAAAAwBEADIMAAADADgAPQwAAAMAFAA+DAAAAgATAD8MAAACABIACwAICCoT7Q0AAgIIOQwAAAMAPgA7DAAAAwBQADoMAAADAEIAPAwAAAMARAAyDAAAAwA4AD0MAAADABQAPgwAAAIAEwA/DAAAAgASAAEsAAUUBggSAAwAEB4A.',Go='Gordog:BAECLAAFFIEOAAIDAAUIHCJhAAAPAgU5DAAABABjADsMAAADAFIAOgwAAAQAYQA8DAAAAgBWAD0MAAABAEYAAwAFCBwiYQAADwIFOQwAAAQAYwA7DAAAAwBSADoMAAAEAGEAPAwAAAIAVgA9DAAAAQBGACwABAqBIgACAwAICOImHgAApQMAAwAICOImHgAApQMAAAA=.',If='Ifeelfreenow:BAEALAADCggIDwABLAAECgEIAgABAAAAAA==.',In='Inekshamân:BAECLAAFFIEJAAINAAQIkhynAQBpAQQ5DAAAAwBKADsMAAACAFIAOgwAAAMATAA8DAAAAQA7AA0ABAiSHKcBAGkBBDkMAAADAEoAOwwAAAIAUgA6DAAAAwBMADwMAAABADsALAAECoEaAAMNAAgINBtdEwBiAgANAAgINBtdEwBiAgAOAAYInA5yPQBpAQAAAA==.',Ja='Japanexport:BAEALAAFFAIIAgABLAAECggICAABAAAAAA==.Japanimport:BAECLAAFFIEMAAIPAAQIxRjcAwB+AQQ5DAAABABaADsMAAADAEcAOgwAAAMAOwA8DAAAAgAfAA8ABAjFGNwDAH4BBDkMAAAEAFoAOwwAAAMARwA6DAAAAwA7ADwMAAACAB8ALAAECoEYAAIPAAgIoSWAAgBgAwAPAAgIoSWAAgBgAwABLAAECggICAABAAAAAA==.',Jo='Jorar:BAEBLAAECoEdAAIEAAgINCa6AACDAwg5DAAABABhADsMAAAEAGMAOgwAAAQAXwA8DAAABABfADIMAAAEAGIAPQwAAAMAYQA+DAAAAwBjAD8MAAADAGIABAAICDQmugAAgwMIOQwAAAQAYQA7DAAABABjADoMAAAEAF8APAwAAAQAXwAyDAAABABiAD0MAAADAGEAPgwAAAMAYwA/DAAAAwBiAAEsAAQKCAgbAAsAGyQA.Jowaww:BAEBLAAECoEbAAMLAAgIGySYAQA2Awg5DAAAAwBWADsMAAADAGEAOgwAAAMAUwA8DAAAAwBeADIMAAADAGEAPQwAAAQAYwA+DAAAAwBSAD8MAAAFAGMACwAICBskmAEANgMIOQwAAAIAVgA7DAAAAgBhADoMAAACAFMAPAwAAAMAXgAyDAAAAwBhAD0MAAADAGMAPgwAAAMAUgA/DAAABQBjABAABAidHXgiAD8BBDkMAAABAFAAOwwAAAEARQA6DAAAAQBLAD0MAAABAE0AAAA=.',Ju='Junipear:BAEBLAAECoEWAAIIAAgIKR+WBADUAgg5DAAAAwBWADsMAAADAFwAOgwAAAMAWwA8DAAAAwBWADIMAAADAFsAPQwAAAMAVwA+DAAAAwA1AD8MAAABADEACAAICCkflgQA1AIIOQwAAAMAVgA7DAAAAwBcADoMAAADAFsAPAwAAAMAVgAyDAAAAwBbAD0MAAADAFcAPgwAAAMANQA/DAAAAQAxAAAA.',Ka='Kaldeak:BAEALAAFFAIIAgABLAAFFAYIEAAPAA0aAA==.Kaldeakw:BAECLAAFFIEQAAMPAAYIDRoPAQBNAgY5DAAAAwBcADsMAAADAE0AOgwAAAQAVgA8DAAAAgAxADIMAAACADIAPQwAAAIAKwAPAAYIDRoPAQBNAgY5DAAAAgBcADsMAAADAE0AOgwAAAMAVgA8DAAAAgAxADIMAAACADIAPQwAAAIAKwARAAIIShCmCACmAAI5DAAAAQAxADoMAAABACIALAAECoEgAAQPAAgI0iXLAQBtAwAPAAgI0iXLAQBtAwARAAYIbh1wGgC/AQASAAEIAiUTKABjAAAAAA==.Kaldh:BAEALAADCgUIBAABLAAFFAYIEAAPAA0aAA==.Kapowdh:BAEBLAAECoEYAAITAAgI3hswFwClAgg5DAAABABTADsMAAAFAE4AOgwAAAMAXgA8DAAAAwBIADIMAAAEAEwAPQwAAAIASQA+DAAAAQAiAD8MAAACADgAEwAICN4bMBcApQIIOQwAAAQAUwA7DAAABQBOADoMAAADAF4APAwAAAMASAAyDAAABABMAD0MAAACAEkAPgwAAAEAIgA/DAAAAgA4AAAA.Kardioklefti:BAEALAAECgYIBgABLAAECggIGQACAD4ZAA==.',Ke='Kerfluffle:BAEALAADCgMIAwABLAAFFAYIEQAMAEMbAA==.',Ki='Kiljacken:BAECLAAFFIESAAIMAAYIEB4rAABRAgY5DAAABABdADsMAAAEAFAAOgwAAAQAYAA8DAAAAwBUADIMAAABADsAPQwAAAIALgAMAAYIEB4rAABRAgY5DAAABABdADsMAAAEAFAAOgwAAAQAYAA8DAAAAwBUADIMAAABADsAPQwAAAIALgAsAAQKgRQAAgwACAjFH7gPAF0CAAwACAjFH7gPAF0CAAAA.Kittengirlx:BAECLAAFFIEQAAIKAAYIVhpkAABCAgY5DAAABABjADsMAAADAFAAOgwAAAQAXQA8DAAAAgBAADIMAAABAB4APQwAAAIAJAAKAAYIVhpkAABCAgY5DAAABABjADsMAAADAFAAOgwAAAQAXQA8DAAAAgBAADIMAAABAB4APQwAAAIAJAAsAAQKgRwAAgoACAiGJlsAAIwDAAoACAiGJlsAAIwDAAAA.',Kw='Kwigga:BAEALAAECgUIBgABLAAFFAMICQAMAFElAA==.',['Kä']='Kätfish:BAEALAAECgYICgAAAA==.',Li='Lilgaychi:BAEALAAFFAMIAwAAAA==.',Ma='Makiavella:BAEALAADCgcIBwABLAAECggIGQACAD4ZAA==.Mande:BAECLAAFFIEKAAIUAAUIMhrGAAD1AQU5DAAAAQBcADsMAAADAFkAOgwAAAMAYwAyDAAAAQAYAD0MAAACAB0AFAAFCDIaxgAA9QEFOQwAAAEAXAA7DAAAAwBZADoMAAADAGMAMgwAAAEAGAA9DAAAAgAdACwABAqBFgACFAAICGgaEwUAhgIAFAAICGgaEwUAhgIAAAA=.Masan:BAEALAAECgUIBgABLAAFFAMIBQAGAMsjAA==.',Mi='Mikhepls:BAECLAAFFIEHAAIEAAQIFx8sAgCEAQQ5DAAAAgBMADsMAAABAEQAOgwAAAMAWgA8DAAAAQBSAAQABAgXHywCAIQBBDkMAAACAEwAOwwAAAEARAA6DAAAAwBaADwMAAABAFIALAAECoEgAAIEAAgIpiaSAACHAwAEAAgIpiaSAACHAwAAAA==.',Mo='Monkki:BAEALAADCgcIBwABLAAECgYICgABAAAAAA==.',['Mâ']='Mâsân:BAECLAAFFIEFAAIGAAMIyyPZAQBCAQM5DAAAAgBhADsMAAABAFgAOgwAAAIAWAAGAAMIyyPZAQBCAQM5DAAAAgBhADsMAAABAFgAOgwAAAIAWAAsAAQKgR8AAgYACAhgJm8AAIkDAAYACAhgJm8AAIkDAAAA.',Na='Nadriethiël:BAECLAAFFIEMAAIJAAUIBBkcAAD+AQU5DAAAAwBhADsMAAABAAUAOgwAAAMAXAA8DAAAAwA7AD0MAAACAEEACQAFCAQZHAAA/gEFOQwAAAMAYQA7DAAAAQAFADoMAAADAFwAPAwAAAMAOwA9DAAAAgBBACwABAqBHgACCQAICM4mJQAAkwMACQAICM4mJQAAkwMAAAA=.Navira:BAECLAAFFIEHAAIEAAMIOhtABAAVAQM5DAAAAwBcADsMAAABADIAOgwAAAMAQQAEAAMIOhtABAAVAQM5DAAAAwBcADsMAAABADIAOgwAAAMAQQAsAAQKgRkAAwQACAiuIsgFACUDAAQACAiuIsgFACUDABUABwiWERUHAMMBAAAA.',Ni='Nippix:BAEALAADCgIIAgABLAAECgYIBgABAAAAAA==.',Nn='Nnoggie:BAEBLAAFFIEGAAIWAAIIGiJKCgDMAAI5DAAAAwBQADoMAAADAF4AFgACCBoiSgoAzAACOQwAAAMAUAA6DAAAAwBeAAAA.Nnoggiedh:BAEALAAECgIIAgABLAAFFAIIBgAWABoiAA==.',Pi='Pipidal:BAEBLAAECoEYAAIXAAcIuRihEQAZAgc5DAAABABLADsMAAAEAFQAOgwAAAMARwA8DAAABAA/ADIMAAAEAEgAPQwAAAMAJQA+DAAAAgAmABcABwi5GKERABkCBzkMAAAEAEsAOwwAAAQAVAA6DAAAAwBHADwMAAAEAD8AMgwAAAQASAA9DAAAAwAlAD4MAAACACYAAAA=.Pipiyel:BAEALAADCgEIAQABLAAECggIGAAXALkYAA==.',Pu='Puberty:BAEBLAAECoEVAAIYAAYIGyZkAgCYAgY5DAAABABjADsMAAAEAGMAOgwAAAQAYQA8DAAAAwBgADIMAAADAGAAPQwAAAMAXwAYAAYIGyZkAgCYAgY5DAAABABjADsMAAAEAGMAOgwAAAQAYQA8DAAAAwBgADIMAAADAGAAPQwAAAMAXwABLAAFFAYIEAAKAFYaAA==.',Py='Pyhyys:BAEALAAECgYIBgABLAAECgYICgABAAAAAA==.',Ra='Rainmakêr:BAEALAAECggIEAABLAAFFAQICQANAJIcAA==.',Sa='Sankariteme:BAEALAADCggIEAABLAAECgYICgABAAAAAA==.',Sc='Scribbles:BAECLAAFFIEKAAIZAAMI0SVCAgBZAQM5DAAABABjADsMAAACAF0AOgwAAAQAYQAZAAMI0SVCAgBZAQM5DAAABABjADsMAAACAF0AOgwAAAQAYQAsAAQKgRQAAhkACAipJI8DACwDABkACAipJI8DACwDAAEsAAUUBggRAAwAQxsA.',Sh='Shammande:BAEALAADCggICAABLAAFFAUICgAUADIaAA==.Shankyernan:BAEALAAECgYIBgAAAA==.',Sl='Slapdudu:BAEALAAECgMIBAABLAAFFAIIBgAaALEhAA==.Slapglaive:BAECLAAFFIEGAAIaAAIIsSHPAQDHAAI5DAAAAwBSADoMAAADAFoAGgACCLEhzwEAxwACOQwAAAMAUgA6DAAAAwBaACwABAqBFAACGgAHCBolQAMA7gIAGgAHCBolQAMA7gIAAAA=.Slapret:BAEALAAFFAIIAgABLAAFFAIIBgAaALEhAA==.',So='Sooth:BAECLAAFFIEQAAMbAAYIjiSkAAAwAgY5DAAAAgBjADsMAAADAFwAOgwAAAMAYwA8DAAAAwBhADIMAAACAGAAPQwAAAMATAAbAAUIVCSkAAAwAgU5DAAAAgBjADsMAAADAFwAOgwAAAMAYwA8DAAAAwBhAD0MAAADAEwAHAABCLAlqwIAcgABMgwAAAIAYAAsAAQKgR4AAxsACAiFJmIAAI0DABsACAiFJmIAAI0DABwAAQhBJn4NAG8AAAAA.Soothjr:BAEBLAAECoEdAAMbAAgIJiZmAQByAwg5DAAAAwBjADsMAAAEAGMAOgwAAAMAWwA8DAAABABjADIMAAAEAGEAPQwAAAQAYgA+DAAABABiAD8MAAADAF8AGwAICCYmZgEAcgMIOQwAAAMAYwA7DAAAAwBjADoMAAADAFsAPAwAAAMAYwAyDAAAAwBhAD0MAAADAGIAPgwAAAMAYgA/DAAAAgBfABcABgghAAAAAAAABjsMAAABAAAAPAwAAAEAAAAyDAAAAQAAAD0MAAABAAEAPgwAAAEAAAA/DAAAAQABAAEsAAUUBggQABsAjiQA.Sotateme:BAEALAADCggICAABLAAECgYICgABAAAAAA==.',Sp='Spacecowben:BAEALAAECggICgAAAA==.',Sq='Sqish:BAEBLAAECoEyAAINAAgIVCUhAQBQAwg5DAAACABhADsMAAAHAGIAOgwAAAgAYwA8DAAABgBiADIMAAAGAGEAPQwAAAUAYwA+DAAABwBYAD8MAAADAFUADQAICFQlIQEAUAMIOQwAAAgAYQA7DAAABwBiADoMAAAIAGMAPAwAAAYAYgAyDAAABgBhAD0MAAAFAGMAPgwAAAcAWAA/DAAAAwBVAAAA.',St='Stabbydk:BAEBLAAECoEUAAQJAAcIGhlMEQDhAQc5DAAABABQADsMAAAEAFEAOgwAAAQARgA8DAAAAgAzADIMAAACADoAPQwAAAIAOwA+DAAAAgAwAAkABwgCFkwRAOEBBzkMAAACAFAAOwwAAAIAUQA6DAAAAwBGADwMAAABAB0AMgwAAAEAOgA9DAAAAQAbAD4MAAABADAAHQAHCJQPHBEAewEHOQwAAAEAJwA7DAAAAgAlADoMAAABABsAPAwAAAEAMwAyDAAAAQAaAD0MAAABADsAPgwAAAEAJAAWAAEIyQfIzQArAAE5DAAAAQATAAAA.Stabbylock:BAEALAAECgIIBAABLAAECgcIFAAJABoZAA==.Stabbywar:BAEALAADCgIIAgABLAAECgcIFAAJABoZAA==.Straìly:BAEALAAECgcIBwABLAAECggIHQAHAL4kAA==.Straíly:BAEBLAAECoEdAAMHAAgIviQyAwBNAwg5DAAABABiADsMAAAEAGAAOgwAAAQAXwA8DAAABABfADIMAAAEAGEAPQwAAAQAWgA+DAAAAwBUAD8MAAACAF0ABwAICL4kMgMATQMIOQwAAAIAYgA7DAAAAgBgADoMAAACAF8APAwAAAIAXwAyDAAAAgBhAD0MAAACAFoAPgwAAAIAVAA/DAAAAQBdAAwACAj8HQwIALoCCDkMAAACAFAAOwwAAAIAXwA6DAAAAgBIADwMAAACAEEAMgwAAAIAWAA9DAAAAgBCAD4MAAABADsAPwwAAAEAVgAAAA==.Streìly:BAEALAAFFAIIBAABLAAECggIHQAHAL4kAA==.',Sw='Swiga:BAEBLAAFFIEJAAIMAAMIUSXdAQBIAQM5DAAAAwBfADsMAAADAGAAOgwAAAMAXgAMAAMIUSXdAQBIAQM5DAAAAwBfADsMAAADAGAAOgwAAAMAXgAAAA==.',Ts='Tsubàki:BAECLAAFFIEOAAIOAAUIGht0AQDrAQU5DAAABABgADsMAAADAFoAOgwAAAMASgA8DAAAAgA5AD0MAAACABwADgAFCBobdAEA6wEFOQwAAAQAYAA7DAAAAwBaADoMAAADAEoAPAwAAAIAOQA9DAAAAgAcACwABAqBHAACDgAICOQj8gYAJQMADgAICOQj8gYAJQMAAAA=.',Tw='Twiga:BAEBLAAECoEUAAICAAgIcRRUEAAQAgg5DAAAAwBIADsMAAAEAFIAOgwAAAMAJAA8DAAAAwBiADIMAAADAEoAPQwAAAIAFgA+DAAAAQAaAD8MAAABAAUAAgAICHEUVBAAEAIIOQwAAAMASAA7DAAABABSADoMAAADACQAPAwAAAMAYgAyDAAAAwBKAD0MAAACABYAPgwAAAEAGgA/DAAAAQAFAAEsAAUUAwgJAAwAUSUA.Twirps:BAEALAAFFAIIAgABLAAFFAYIEQAMAEMbAA==.',Ua='Ualizardhary:BAEALAAECgYIBgABLAAECggIMgANAFQlAA==.',Va='Vauhtiteme:BAEALAAECgEIAQABLAAECgYICgABAAAAAA==.',We='Weece:BAEBLAAECoEbAAQZAAgIhhtYDQChAgg5DAAABABbADsMAAAEAGAAOgwAAAQAXwA8DAAABABGADIMAAAEAGAAPQwAAAUAGwA+DAAAAQAzAD8MAAABACIAGQAICIYbWA0AoQIIOQwAAAMAWwA7DAAAAwBgADoMAAADAF8APAwAAAMARgAyDAAAAwBgAD0MAAACABsAPgwAAAEAMwA/DAAAAQAiAAQABQg/Gtw0AGABBTsMAAABAFgAOgwAAAEAKQA8DAAAAQBNADIMAAABAEEAPQwAAAMAPgAVAAEI3yKxGwBlAAE5DAAAAQBZAAEsAAUUBQgKABQAMhoA.',Xa='Xarxaloulis:BAEALAADCggICAABLAAECggIGQACAD4ZAA==.',Xi='Xippì:BAEALAAECgYIBgAAAA==.',['Xî']='Xîppi:BAEALAAECgcIBwABLAAECgYIBgABAAAAAA==.',Ye='Yechstree:BAECLAAFFIEIAAIHAAMIixUjBAD5AAM5DAAAAwBGADsMAAACABMAOgwAAAMASgAHAAMIixUjBAD5AAM5DAAAAwBGADsMAAACABMAOgwAAAMASgAsAAQKgRQAAgcABwiEJWQJAOACAAcABwiEJWQJAOACAAAA.',Yz='Yzaxz:BAECLAAFFIENAAIeAAYIXB17AABVAgY5DAAAAwBiADsMAAADAFkAOgwAAAMAUAA8DAAAAgAsADIMAAABADkAPQwAAAEAUAAeAAYIXB17AABVAgY5DAAAAwBiADsMAAADAFkAOgwAAAMAUAA8DAAAAgAsADIMAAABADkAPQwAAAEAUAAsAAQKgRgAAh4ACAhZI0YFAA4DAB4ACAhZI0YFAA4DAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end