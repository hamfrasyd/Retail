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
 local lookup = {'Unknown-Unknown','Monk-Brewmaster','Mage-Fire','Mage-Arcane','Mage-Frost','Druid-Guardian','Warrior-Protection','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Unholy','Monk-Mistweaver','Rogue-Subtlety','Shaman-Elemental','Druid-Restoration','DemonHunter-Havoc','Paladin-Protection','Druid-Balance','Hunter-Marksmanship','Shaman-Restoration','Rogue-Assassination','Priest-Shadow',}; local provider = {region='EU',realm='Silvermoon',name='EU',type='subscribers',zone=44,date='2025-09-06',data={Ac='Acedc:BAEALAAECgYIDAABLAAECgUIBgABAAAAAA==.Acemnk:BAECLAAFFIEPAAICAAUI5yK0AAANAgU5DAAABABfADsMAAADAF0AOgwAAAQAWgA8DAAAAgBRAD0MAAACAFUAAgAFCOcitAAADQIFOQwAAAQAXwA7DAAAAwBdADoMAAAEAFoAPAwAAAIAUQA9DAAAAgBVACwABAqBHgACAgAICAYmhQAAfgMAAgAICAYmhQAAfgMAASwABAoFCAYAAQAAAAA=.Acepally:BAEALAAECgUIBgAAAA==.',Am='Amarèya:BAEALAADCgcIBwABLAAECgYIDQABAAAAAA==.',Ar='Aryella:BAECLAAFFIENAAQDAAYIDiALAABtAgY5DAAAAwBiADsMAAACAGQAOgwAAAMAVgA8DAAAAgASADIMAAABAFgAPQwAAAIAZAADAAYIAyALAABtAgY5DAAAAgBhADsMAAABAGQAOgwAAAMAVgA8DAAAAQASADIMAAABAFgAPQwAAAIAZAAEAAIIyhWUFwCiAAI5DAAAAQBiADwMAAABAA0ABQABCCki9QgAWAABOwwAAAEAVwAsAAQKgR8ABAMACAjeJhMAAI4DAAMACAjUJhMAAI4DAAQABwiVJp8SAMsCAAUABgjaH50bALYBAAAA.Aryellei:BAEALAAECgcIDQABLAAFFAYIDQADAA4gAA==.Arythreella:BAEBLAAECoEWAAQEAAgIeyXCBABEAwg5DAAAAwBhADsMAAADAGMAOgwAAAMAYgA8DAAAAwBeADIMAAADAGMAPQwAAAMAXwA+DAAAAgBbAD8MAAACAFoABAAICHslwgQARAMIOQwAAAIAYQA7DAAAAgBjADoMAAACAGIAPAwAAAIAXgAyDAAAAgBjAD0MAAACAF8APgwAAAIAWwA/DAAAAQBaAAUABgigHt0gAIwBBjkMAAABAFMAOwwAAAEATgA6DAAAAQBZADwMAAABADQAMgwAAAEATQA9DAAAAQBZAAMAAQixIukOAFwAAT8MAAABAFgAASwABRQGCA0AAwAOIAA=.Arytwoella:BAEBLAAECoEeAAMEAAgI2iMaBwAtAwg5DAAABABgADsMAAAEAF0AOgwAAAQAWwA8DAAABABfADIMAAAEAGAAPQwAAAQAXAA+DAAAAwBSAD8MAAADAFMABAAICG4jGgcALQMIOQwAAAIAYAA7DAAAAgBVADoMAAACAFsAPAwAAAIAXwAyDAAAAgBgAD0MAAACAFwAPgwAAAIAUgA/DAAAAgBTAAUACAiXHgcJAJUCCDkMAAACAF0AOwwAAAIAXQA6DAAAAgBXADwMAAACAEwAMgwAAAIAWgA9DAAAAgA+AD4MAAABAEAAPwwAAAEAOQABLAAFFAYIDQADAA4gAA==.',Ca='Cairnsy:BAECLAAFFIEKAAIGAAUI9RUbAADBAQU5DAAAAwBOADsMAAACAB4AOgwAAAMAUwA8DAAAAQA8AD0MAAABABwABgAFCPUVGwAAwQEFOQwAAAMATgA7DAAAAgAeADoMAAADAFMAPAwAAAEAPAA9DAAAAQAcACwABAqBHAACBgAICEQknQAATwMABgAICEQknQAATwMAAAA=.Cairnsywar:BAEALAAFFAIIAgABLAAFFAUICgAGAPUVAA==.',Ch='Churo:BAEBLAAECoEUAAIEAAgIZBs2IQBfAgg5DAAAAgBDADsMAAACAEcAOgwAAAIAVgA8DAAAAwBKADIMAAAEAD4APQwAAAQAPwA+DAAAAgBZAD8MAAABAC0ABAAICGQbNiEAXwIIOQwAAAIAQwA7DAAAAgBHADoMAAACAFYAPAwAAAMASgAyDAAABAA+AD0MAAAEAD8APgwAAAIAWQA/DAAAAQAtAAAA.',Ci='Cifboomy:BAEALAAECgEIAQABLAAFFAYIDgABAAAAAQ==.',Cr='Crawenn:BAEALAAECgYIEQAAAA==.Crw:BAEALAAECgEIAQABLAAECgYIEQABAAAAAA==.',Di='Dimaethorwen:BAEALAAECgEIAgABLAAECggIGQAHABwbAA==.',Do='Domarelius:BAEALAADCgcIBwABLAAECgEIAQABAAAAAA==.Domariel:BAEALAADCggIGAABLAAECgEIAQABAAAAAA==.Domatheus:BAEALAAECgEIAQAAAA==.Domvahkiin:BAEALAADCggIDwABLAAECgEIAQABAAAAAA==.Domvein:BAEALAADCggIFwABLAAECgEIAQABAAAAAA==.',Er='Eraticartist:BAEALAAECggIDwAAAA==.',Ex='Exaltarion:BAEALAAECgYIBgAAAA==.',Fe='Fearzok:BAEBLAAECoEfAAIIAAgI1B22DQDNAgg5DAAABABhADsMAAAEAFwAOgwAAAQARQA8DAAABQBUADIMAAAEAFoAPQwAAAQAXAA+DAAABAA3AD8MAAACABwACAAICNQdtg0AzQIIOQwAAAQAYQA7DAAABABcADoMAAAEAEUAPAwAAAUAVAAyDAAABABaAD0MAAAEAFwAPgwAAAQANwA/DAAAAgAcAAAA.',Fi='Fikru:BAEALAADCggIDwABLAAFFAMICAAJAOkVAA==.Fikrus:BAEALAAFFAIIAgABLAAFFAMICAAJAOkVAA==.Fikrux:BAECLAAFFIEIAAMJAAMI6RWJAAARAQM5DAAAAwA2ADsMAAACABsAOgwAAAMAVgAJAAMI6RWJAAARAQM5DAAAAgA2ADsMAAABABsAOgwAAAIAVgAKAAMI9g2kCQD1AAM5DAAAAQAdADsMAAABAA4AOgwAAAEAPgAsAAQKgSIABAkACAidJIABADIDAAkACAhWJIABADIDAAoABwi6HioXAHcCAAsAAQj1EhIvAEYAAAAA.',Ge='Genshinwaifu:BAEALAADCgcIBwABLAAFFAEIAQABAAAAAA==.',Gh='Ghuzzi:BAEALAADCgEIAQABLAAECgYICwABAAAAAA==.Ghuzzuk:BAEALAADCgcIEAABLAAECgYICwABAAAAAA==.',Hu='Huntingnips:BAEALAAECgQIBwAAAA==.',Id='Idéfíx:BAEALAAFFAIIAgAAAA==.',Ik='Ikubrew:BAEALAAECgMIAwABLAAFFAMIBQAMANEVAA==.Ikupres:BAECLAAFFIEFAAIMAAMI0RUfAwD6AAM5DAAAAgAuADsMAAABACwAOgwAAAIATAAMAAMI0RUfAwD6AAM5DAAAAgAuADsMAAABACwAOgwAAAIATAAsAAQKgRYAAgwACAgGIuMAADwDAAwACAgGIuMAADwDAAAA.',Jf='Jfritzl:BAEBLAAECoEXAAMNAAgISyFhDAD6Agg5DAAABABfADsMAAAEAFMAOgwAAAQAYQA8DAAABABfADIMAAACAF8APQwAAAMAVQA+DAAAAQA5AD8MAAABAEcADQAICEshYQwA+gIIOQwAAAQAXwA7DAAABABTADoMAAAEAGEAPAwAAAQAXwAyDAAAAgBfAD0MAAACAFUAPgwAAAEAOQA/DAAAAQBHAA4AAQjHEQ89AEYAAT0MAAABAC0AAAA=.',Jo='Johnbarnes:BAEALAAECgYICwAAAA==.',Ka='Kantema:BAEALAAECgcICAABLAAECggIHgAPABslAA==.Kasvius:BAEALAAECgYIDQAAAA==.Kayes:BAEBLAAECoEdAAMEAAgIwSEQDQD5Agg5DAAABABgADsMAAAEAFMAOgwAAAQAWgA8DAAAAwBbADIMAAAEAEYAPQwAAAQAVwA+DAAAAwBXAD8MAAADAFMABAAICJghEA0A+QIIOQwAAAQAYAA7DAAABABTADoMAAAEAFoAPAwAAAMAWwAyDAAAAgBDAD0MAAAEAFcAPgwAAAMAVwA/DAAAAwBTAAMAAQh4G5ARAEYAATIMAAACAEYAAAA=.',Le='Leopshaman:BAEALAAECgEIAQABLAAECgYIBgABAAAAAA==.Lesserafim:BAEALAAFFAEIAQAAAA==.',Lu='Luminasta:BAEALAADCggICAAAAA==.',Ma='Maximuszeng:BAEALAADCggIDgABLAAFFAIIBAABAAAAAA==.',Mi='Misfosster:BAECLAAFFIEFAAIQAAMImiFoAQAlAQM5DAAAAgBSADsMAAACAFoAOgwAAAEAVQAQAAMImiFoAQAlAQM5DAAAAgBSADsMAAACAFoAOgwAAAEAVQAsAAQKgR8AAhAACAiZJjoAAIIDABAACAiZJjoAAIIDAAAA.Mistoutfire:BAEALAADCgYICQABLAAECgYICwABAAAAAA==.',Mu='Murçi:BAEALAAECgYIBwAAAA==.',Ne='Neonswift:BAEBLAAECoEZAAIHAAgIHBsQCwBmAgg5DAAABABPADsMAAAEAEsAOgwAAAQAPgA8DAAAAwBMADIMAAADAEYAPQwAAAQANQA+DAAAAgBGAD8MAAABAEMABwAICBwbEAsAZgIIOQwAAAQATwA7DAAABABLADoMAAAEAD4APAwAAAMATAAyDAAAAwBGAD0MAAAEADUAPgwAAAIARgA/DAAAAQBDAAAA.',No='Nomorehappie:BAEALAAECggICAABLAAECggICgABAAAAAA==.',Nx='Nxdruid:BAEALAAFFAIIBAABLAAFFAYIDgARAAUgAA==.',Ny='Nyrimage:BAEALAADCgQIBAABLAAECgYIBgABAAAAAA==.',['Nè']='Nèonmonk:BAEALAADCggICAABLAAECggIGQAHABwbAA==.',Oa='Oatlywarrior:BAEALAADCggICAAAAA==.',Pa='Paidnfull:BAEALAADCgIIAgABLAAFFAQICQASAN4bAA==.Pandalily:BAEALAAECgYIBgABLAAFFAMIBwARAJAdAA==.Pandyhunti:BAEALAAECgYIBgAAAA==.Pawjobs:BAEBLAAECoEWAAITAAgIlhx7FwCjAgg5DAAABABNADsMAAADAFYAOgwAAAMAUAA8DAAAAwBQADIMAAADAGAAPQwAAAMAUgA+DAAAAQAeAD8MAAACADIAEwAICJYcexcAowIIOQwAAAQATQA7DAAAAwBWADoMAAADAFAAPAwAAAMAUAAyDAAAAwBgAD0MAAADAFIAPgwAAAEAHgA/DAAAAgAyAAAA.',Pe='Pedroobvious:BAEBLAAECoEUAAIUAAYIjxzNEADLAQY5DAAABABQADsMAAAEAFAAOgwAAAMATAA8DAAAAwBEADIMAAADAEQAPQwAAAMAQQAUAAYIjxzNEADLAQY5DAAABABQADsMAAAEAFAAOgwAAAMATAA8DAAAAwBEADIMAAADAEQAPQwAAAMAQQAAAA==.',Ph='Phodrood:BAECLAAFFIEJAAISAAQI3ht4AgAoAQQ5DAAAAwBeADsMAAACAFsAOgwAAAMARwA8DAAAAQAbABIABAjeG3gCACgBBDkMAAADAF4AOwwAAAIAWwA6DAAAAwBHADwMAAABABsALAAECoEeAAISAAgIYyLFAwAEAwASAAgIYyLFAwAEAwAAAA==.Phomage:BAECLAAFFIEIAAIEAAMIXB4WBgAqAQM5DAAAAwBWADsMAAACADsAOgwAAAMAVwAEAAMIXB4WBgAqAQM5DAAAAwBWADsMAAACADsAOgwAAAMAVwAsAAQKgRsAAgQACAhAI2cKAA8DAAQACAhAI2cKAA8DAAEsAAUUBAgJABIA3hsA.Phomonk:BAEALAAECgYIBwABLAAFFAQICQASAN4bAA==.',Pl='Plingplang:BAEBLAAECoEeAAIGAAgITh7IAQDLAgg5DAAABABZADsMAAAEAEsAOgwAAAQAUgA8DAAABABKADIMAAAEAFQAPQwAAAQAUAA+DAAAAwBNAD8MAAADADkABgAICE4eyAEAywIIOQwAAAQAWQA7DAAABABLADoMAAAEAFIAPAwAAAQASgAyDAAABABUAD0MAAAEAFAAPgwAAAMATQA/DAAAAwA5AAAA.',Pr='Protecka:BAEALAAECgIIAgABLAAECggIHQAVAL4kAA==.',Re='Returnunit:BAEBLAAECoEYAAIEAAgIXhWjKwAgAgg5DAAABAA6ADsMAAAEAEkAOgwAAAQANgA8DAAAAwA2ADIMAAADAEcAPQwAAAMASAA+DAAAAgAKAD8MAAABACoABAAICF4VoysAIAIIOQwAAAQAOgA7DAAABABJADoMAAAEADYAPAwAAAMANgAyDAAAAwBHAD0MAAADAEgAPgwAAAIACgA/DAAAAQAqAAAA.',Ry='Ryaa:BAEALAAFFAQIBAABLAAFFAYIDgAHAA8LAA==.Ryii:BAECLAAFFIEOAAIHAAYIDwsFAQDGAQY5DAAABABLADsMAAACABkAOgwAAAMAHwA8DAAAAgAQADIMAAACAA0APQwAAAEACQAHAAYIDwsFAQDGAQY5DAAABABLADsMAAACABkAOgwAAAMAHwA8DAAAAgAQADIMAAACAA0APQwAAAEACQAsAAQKgRoAAgcACAhzIgQDACgDAAcACAhzIgQDACgDAAAA.',Sa='Sar:BAECLAAFFIEHAAIIAAQIERO1AQBKAQQ5DAAAAgBNADsMAAACAD0AOgwAAAIALAA8DAAAAQALAAgABAgRE7UBAEoBBDkMAAACAE0AOwwAAAIAPQA6DAAAAgAsADwMAAABAAsALAAECoEdAAMIAAgI8iQkBgAoAwAIAAgI8iQkBgAoAwAWAAUIlhinMQBnAQAAAA==.',Sh='Shamenkink:BAEALAADCggICAABLAAECggIGAAEAF4VAA==.',St='Steelsdk:BAEALAAECggIBwABLAAECgYIBAABAAAAAA==.Steelshunter:BAEALAAECggICAABLAAECgYIBAABAAAAAA==.Steelspally:BAEALAAECgYIBAAAAA==.',Su='Sulxan:BAEALAAECgIIAgAAAA==.Sunkala:BAEALAADCggIDQABLAAECgYICwABAAAAAA==.',Ta='Tankydh:BAEALAADCgUIBQABLAAECggIGAAEAF4VAA==.',Th='Thrapalina:BAEALAAECggICgAAAA==.',Ti='Tinyboxes:BAEBLAAECoEbAAIRAAgIDho8EgCSAgg5DAAABABQADsMAAAEAFAAOgwAAAQATAA8DAAABABRADIMAAAEAD8APQwAAAMAOQA+DAAAAwA/AD8MAAABAB4AEQAICA4aPBIAkgIIOQwAAAQAUAA7DAAABABQADoMAAAEAEwAPAwAAAQAUQAyDAAABAA/AD0MAAADADkAPgwAAAMAPwA/DAAAAQAeAAAA.Tinymoonboot:BAEALAADCgQIBAABLAAECggIGwARAA4aAA==.',To='Toxhunter:BAEALAAECgEIAQAAAA==.',Tr='Troopcsd:BAEBLAAECoEgAAMEAAgIPSLYCQAUAwg5DAAABABcADsMAAAEAF4AOgwAAAQAYwA8DAAABABeADIMAAAEAFUAPQwAAAQAUgA+DAAABABSAD8MAAAEAEQABAAICD0i2AkAFAMIOQwAAAMAXAA7DAAAAwBeADoMAAADAGMAPAwAAAMAXgAyDAAAAwBVAD0MAAACAFIAPgwAAAMAUgA/DAAABABEAAUABwiiEVIgAJABBzkMAAABAEwAOwwAAAEAFAA6DAAAAQAlADwMAAABAEAAMgwAAAEAIwA9DAAAAgBDAD4MAAABAA4AAAA=.',Ui='Uithest:BAEALAAECgYIDAAAAA==.',Ur='Urunïi:BAEALAAECgYIDQAAAA==.',Ve='Vedesl:BAEALAADCgQIBAABLAAECggIFwANAEshAA==.Vedesm:BAEALAAECgcIDQABLAAECggIFwANAEshAA==.Vedessan:BAEALAAECgcICgABLAAECggIFwANAEshAA==.',['Vî']='Vîfon:BAEALAAECgMIAwABLAAECgYIEQABAAAAAA==.',Wa='Waidur:BAEBLAAECoEVAAMXAAgIuBSKJgDvAQg5DAAAAwArADsMAAADADUAOgwAAAMAMgA8DAAAAwA6ADIMAAADAFsAPQwAAAMALwA+DAAAAgAWAD8MAAABADoAFwAICLgUiiYA7wEIOQwAAAIAKwA7DAAAAgA1ADoMAAACADIAPAwAAAIAOgAyDAAAAgBbAD0MAAACAC8APgwAAAEAFgA/DAAAAQA6ABEABwgAFkEoANkBBzkMAAABAEAAOwwAAAEASQA6DAAAAQA3ADwMAAABAEIAMgwAAAEASAA9DAAAAQAmAD4MAAABABYAASwABRQGCAsAFwBYBQA=.',Wh='Whopwhhoo:BAEALAADCggIDwABLAAECgcIBwABAAAAAA==.Whupwhup:BAEALAAECgcIBwAAAA==.',Wi='Windslasher:BAEBLAAECoEXAAIYAAcILhwHEABeAgc5DAAABABaADsMAAAEAFgAOgwAAAQAJAA8DAAAAwBBADIMAAADAFkAPQwAAAMAPwA+DAAAAgBFABgABwguHAcQAF4CBzkMAAAEAFoAOwwAAAQAWAA6DAAABAAkADwMAAADAEEAMgwAAAMAWQA9DAAAAwA/AD4MAAACAEUAAAA=.',Zn='Zng:BAEALAAFFAIIBAAAAA==.',Zt='Ztil:BAEBLAAECoEgAAIIAAgIZiWbAQBtAwg5DAAABQBjADsMAAAEAGMAOgwAAAQAYgA8DAAABABhADIMAAAFAGIAPQwAAAUAYwA+DAAAAwBgAD8MAAACAEsACAAICGYlmwEAbQMIOQwAAAUAYwA7DAAABABjADoMAAAEAGIAPAwAAAQAYQAyDAAABQBiAD0MAAAFAGMAPgwAAAMAYAA/DAAAAgBLAAAA.',Zy='Zydruid:BAEALAAFFAIIAgABLAAFFAQICwABAAAAAA==.Zyevoker:BAEALAADCgEIAQABLAAFFAQICwABAAAAAA==.Zyknight:BAEALAAFFAIIAgABLAAFFAQICwABAAAAAA==.Zymage:BAEALAAECgMIAwABLAAFFAQICwABAAAAAA==.Zythene:BAECLAAFFIEHAAIRAAMIkB1nBAAeAQM5DAAAAwBbADsMAAABADoAOgwAAAMATAARAAMIkB1nBAAeAQM5DAAAAwBbADsMAAABADoAOgwAAAMATAAsAAQKgR4AAhEACAhcJTkCAGwDABEACAhcJTkCAGwDAAAA.Zywarrior:BAEALAAFFAIIAgABLAAFFAQICwABAAAAAA==.',['År']='Årk:BAEBLAAECoEZAAIZAAcIliDrEQCDAgc5DAAABABXADsMAAAEAFAAOgwAAAQAXwA8DAAABABKADIMAAAEAEUAPQwAAAMAVQA+DAAAAgBbABkABwiWIOsRAIMCBzkMAAAEAFcAOwwAAAQAUAA6DAAABABfADwMAAAEAEoAMgwAAAQARQA9DAAAAwBVAD4MAAACAFsAAAA=.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end