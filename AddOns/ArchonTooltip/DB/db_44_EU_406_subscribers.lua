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
 local lookup = {'Evoker-Preservation','Mage-Arcane','Mage-Fire','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Druid-Balance','Druid-Feral','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Warrior-Fury','Druid-Restoration','Priest-Holy','Paladin-Retribution','Paladin-Holy','Warrior-Protection','Evoker-Devastation','Monk-Windwalker',}; local provider = {region='EU',realm='Blackhand',name='EU',type='subscribers',zone=44,date='2025-09-06',data={Am='Ameliâ:BAEALAAECgYIEgAAAA==.',Ar='Arrg:BAEALAAECggIEAABLAAECggIFQABAMsaAA==.Arrgdwarf:BAEALAAECgEIAQABLAAECggIFQABAMsaAA==.Arrgmändschn:BAEBLAAECoEVAAIBAAgIyxqSBACYAgg5DAAAAwBWADsMAAADAFAAOgwAAAIAVwA8DAAAAwBMADIMAAADAFAAPQwAAAMAQgA+DAAAAgAkAD8MAAACACEAAQAICMsakgQAmAIIOQwAAAMAVgA7DAAAAwBQADoMAAACAFcAPAwAAAMATAAyDAAAAwBQAD0MAAADAEIAPgwAAAIAJAA/DAAAAgAhAAAA.Arrgwl:BAEALAAECgcICAABLAAECggIFQABAMsaAA==.',Ba='Baramage:BAECLAAFFIEHAAMCAAQIuxfiBgAdAQQ5DAAAAgAzADsMAAACADwAOgwAAAIAUAA8DAAAAQAyAAIABAiyEuIGAB0BBDkMAAABAAAAOwwAAAIAPAA6DAAAAgBQADwMAAABADIAAwABCE8U/QQATQABOQwAAAEAMwAsAAQKgRgABAMACAg4InABALQCAAMACAgAIXABALQCAAQABggWIiMQACoCAAIAAggZGNR+AJwAAAAA.Baramonk:BAEALAAECgYIDgABLAAFFAQIBwACALsXAA==.Barapriest:BAEALAAECgQIBAABLAAFFAQIBwACALsXAA==.Baravoker:BAEALAAECgcIDQABLAAFFAQIBwACALsXAA==.Barawarlock:BAEBLAAECoEUAAQFAAgIsyF9CAAOAwg5DAAAAwBaADsMAAADAFUAOgwAAAMAXAA8DAAAAwBdADIMAAADAE0APQwAAAMAUgA+DAAAAQBeAD8MAAABAEkABQAICEohfQgADgMIOQwAAAIAWAA7DAAAAgBVADoMAAACAFwAPAwAAAMAXQAyDAAAAgBGAD0MAAACAFIAPgwAAAEAXgA/DAAAAQBJAAYABAjPGwMyADMBBDkMAAABAFoAOwwAAAEATQA6DAAAAQA7AD0MAAABADkABwABCFQeTCoAVQABMgwAAAEATQABLAAFFAQIBwACALsXAA==.Barawarry:BAEALAADCggIEAABLAAFFAQIBwACALsXAA==.',Be='Benqti:BAEBLAAECoEdAAMIAAgIsiJfCAAKAwg5DAAABgBfADsMAAAEAGEAOgwAAAMAWAA8DAAAAwBQADIMAAADAFcAPQwAAAQAXAA+DAAAAwBTAD8MAAADAFYACAAICLIiXwgACgMIOQwAAAQAXwA7DAAABABhADoMAAADAFgAPAwAAAMAUAAyDAAAAwBXAD0MAAAEAFwAPgwAAAMAUwA/DAAAAwBWAAkAAQhJDk5zAC8AATkMAAACACQAASwABAoGCAgACgAAAAA=.Benqtidruid:BAEBLAAECoEeAAMLAAgIth50DwCBAgg5DAAABQBZADsMAAAEAFYAOgwAAAQAXgA8DAAABABTADIMAAAEAEwAPQwAAAQAVAA+DAAAAwA4AD8MAAACADoACwAICPUbdA8AgQIIOQwAAAIAWQA7DAAAAQAgADoMAAADAF4APAwAAAMAUQAyDAAAAwBMAD0MAAADAFQAPgwAAAIAOAA/DAAAAQA6AAwACAiOFWcLAA0CCDkMAAADAEgAOwwAAAMAVgA6DAAAAQBSADwMAAABAFMAMgwAAAEAOwA9DAAAAQAuAD4MAAABAAUAPwwAAAEABQABLAAECgYICAAKAAAAAA==.Benqtilock:BAEALAAECgYICAAAAA==.Benqtimage:BAEALAAECgIIAgABLAAECgYICAAKAAAAAA==.Benqtirogue:BAEALAADCggICAABLAAECgYICAAKAAAAAA==.Benqtischami:BAEALAAECgYIDAABLAAECgYICAAKAAAAAA==.',Bl='Bleedting:BAEALAAECgMIBAABLAAECgcIBAAKAAAAAA==.',Ch='Chîting:BAEALAAECgIIAgABLAAECgcIBAAKAAAAAA==.',Cr='Crâton:BAEALAAFFAIIAgAAAA==.Crèapzr:BAECLAAFFIENAAINAAUIFB6kAADyAQU5DAAAAwBjADsMAAACAFkAOgwAAAQAYQA8DAAAAgBCAD0MAAACAB8ADQAFCBQepAAA8gEFOQwAAAMAYwA7DAAAAgBZADoMAAAEAGEAPAwAAAIAQgA9DAAAAgAfACwABAqBIAADDQAICFMecAsAqAIADQAICFMecAsAqAIADgAICBYUxxoAPAIAAAA=.',De='Deeling:BAEALAAECgMIBQABLAAECgIIAwAKAAAAAA==.',Dk='Dkbert:BAEBLAAECoEZAAIPAAgIVyR4BABJAwg5DAAABABgADsMAAAEAGEAOgwAAAMAYAA8DAAABABgADIMAAADAGMAPQwAAAMAXAA+DAAAAgBRAD8MAAACAFMADwAICFckeAQASQMIOQwAAAQAYAA7DAAABABhADoMAAADAGAAPAwAAAQAYAAyDAAAAwBjAD0MAAADAFwAPgwAAAIAUQA/DAAAAgBTAAEsAAUUBAgJABAA9h8A.',Dr='Drehbert:BAEALAADCggIEAABLAAFFAQICQAQAPYfAA==.',Ev='Evildruid:BAEBLAAECoEVAAIRAAgIRiP2AQA2Awg5DAAAAwBjADsMAAAEAGAAOgwAAAMAXgA8DAAAAwBgADIMAAADAF4APQwAAAMAUAA+DAAAAQBEAD8MAAABAF0AEQAICEYj9gEANgMIOQwAAAMAYwA7DAAABABgADoMAAADAF4APAwAAAMAYAAyDAAAAwBeAD0MAAADAFAAPgwAAAEARAA/DAAAAQBdAAEsAAQKCAgUABIAwh0A.Evilevoker:BAECLAAFFIEKAAIBAAUITxA4AQCcAQU5DAAAAgBHADsMAAACABEAOgwAAAMAFQA8DAAAAgA7AD0MAAABACYAAQAFCE8QOAEAnAEFOQwAAAIARwA7DAAAAgARADoMAAADABUAPAwAAAIAOwA9DAAAAQAmACwABAqBIAACAQAICAoWxAcAMwIAAQAICAoWxAcAMwIAASwABAoICBQAEgDCHQA=.',Fa='Faldon:BAEBLAAECoEVAAMTAAgInhsgKwAqAgg5DAAAAwBDADsMAAADAEoAOgwAAAMAVgA8DAAAAwBMADIMAAADAEcAPQwAAAMAPQA+DAAAAgBPAD8MAAABAC8AEwAHCO4cICsAKgIHOQwAAAMAQwA7DAAAAgBKADoMAAABAFYAPAwAAAEATAAyDAAAAQBHAD0MAAABAD0APgwAAAEATwAUAAcIIA04HwB7AQc7DAAAAQA9ADoMAAACABgAPAwAAAIAMwAyDAAAAgAfAD0MAAACABIAPgwAAAEAFwA/DAAAAQAXAAAA.Faldu:BAEALAAECgcIDgABLAAECggIFQATAJ4bAA==.Faldusneak:BAEALAAECggIEAABLAAECggIFQATAJ4bAA==.Fassmichan:BAEBLAAECoEkAAIIAAgInh/8CgDtAgg5DAAABgBbADsMAAAGAF0AOgwAAAYAVgA8DAAABQBKADIMAAAFAFsAPQwAAAQAXgA+DAAAAwBUAD8MAAABACAACAAICJ4f/AoA7QIIOQwAAAYAWwA7DAAABgBdADoMAAAGAFYAPAwAAAUASgAyDAAABQBbAD0MAAAEAF4APgwAAAMAVAA/DAAAAQAgAAAA.',Go='Goatekin:BAEALAADCgcIAgABLAAECggIDAAKAAAAAA==.',['Gö']='Görny:BAEALAAECgYIDgABLAAECggIDAAKAAAAAA==.',Ha='Haumiwarry:BAEALAAECggIBgABLAAECggIGwAVAO8hAA==.',He='Heilprisi:BAEALAAECgYIDAABLAAECgYIEgAKAAAAAA==.',In='Inmórtal:BAEALAAECgcIEQAAAA==.',Kl='Klotzy:BAEALAADCggIEAABLAAECggIDAAKAAAAAA==.',Ky='Kyranth:BAEALAADCgMIAwABLAAFFAIIAgAKAAAAAA==.',['Ká']='Káralas:BAEALAAFFAEIAQAAAA==.',['Kê']='Kêss:BAEALAADCgQIBAAAAA==.',['Kî']='Kîzàru:BAEALAAECggICAABLAAECggIEAAKAAAAAA==.',Li='Lightymax:BAEALAAFFAIIBAABLAAECgcIEwAKAAAAAA==.Lightypriest:BAEALAAECgcIEwAAAA==.Lizzydk:BAECLAAFFIEGAAIPAAII+hflEwCoAAI5DAAAAwA+ADoMAAADADwADwACCPoX5RMAqAACOQwAAAMAPgA6DAAAAwA8ACwABAqBHwACDwAICNkf6Q4A5AIADwAICNkf6Q4A5AIAAAA=.',Ne='Nerto:BAECLAAFFIEIAAIMAAMIkhpGAQAeAQM5DAAAAwBeADsMAAACADMAOgwAAAMAOgAMAAMIkhpGAQAeAQM5DAAAAwBeADsMAAACADMAOgwAAAMAOgAsAAQKgR4AAgwACAgEH/YDAN4CAAwACAgEH/YDAN4CAAAA.Nevertøxic:BAEALAAFFAIIBAAAAA==.',['Ná']='Námaa:BAEALAAECgEIAQABLAAFFAEIAQAKAAAAAA==.',Pa='Padii:BAEALAAECgcIDQAAAA==.Pallybert:BAEALAAECgYIBgABLAAFFAQICQAQAPYfAA==.',Re='Reren:BAEALAADCggIFwABLAAECggIGQAQAB0bAA==.Reîzwäsche:BAEALAAECgMIAwAAAA==.',Ri='Rimurû:BAEALAAECgYIBgABLAAECgYIEgAKAAAAAA==.',Ro='Roxxondh:BAEALAAECgYIEgABLAAECggICAAKAAAAAA==.Roxxondk:BAEALAAECgYICAABLAAECggICAAKAAAAAA==.Roxxonpali:BAEALAAECgYIEgABLAAECggICAAKAAAAAA==.Roxxonpriest:BAEALAAECggICAAAAA==.Roxxonspyro:BAEALAADCgYIBgABLAAECggICAAKAAAAAA==.Roxxonwar:BAEALAADCggIEAABLAAECggICAAKAAAAAA==.',Ry='Ryumã:BAEALAAECggIEAAAAA==.',Sa='Saphiry:BAEALAAECgEIAgAAAQ==.',Sc='Schlexdk:BAEALAAECggIDAAAAA==.',Se='Serapherion:BAEALAADCggIEAABLAAFFAIIAgAKAAAAAA==.Seregas:BAEBLAAECoEZAAIQAAgIHRudFACBAgg5DAAABABPADsMAAAFAFQAOgwAAAUAWwA8DAAAAwBBADIMAAADAEYAPQwAAAMARQA+DAAAAQAtAD8MAAABADEAEAAICB0bnRQAgQIIOQwAAAQATwA7DAAABQBUADoMAAAFAFsAPAwAAAMAQQAyDAAAAwBGAD0MAAADAEUAPgwAAAEALQA/DAAAAQAxAAAA.',Sh='Shoxxypump:BAECLAAFFIELAAIBAAUIwRMoAQCmAQU5DAAAAwBQADsMAAACACsAOgwAAAIANgA8DAAAAgAJADIMAAACAEAAAQAFCMETKAEApgEFOQwAAAMAUAA7DAAAAgArADoMAAACADYAPAwAAAIACQAyDAAAAgBAACwABAqBHQACAQAICBQmdgAAXAMAAQAICBQmdgAAXAMAAAA=.Shoxxyqt:BAEALAAECgUIBwABLAAFFAUICwABAMETAA==.',St='Styffenlock:BAEALAAECggIEwAAAA==.Styffenmage:BAEALAAECggIDgABLAAECggIEwAKAAAAAA==.Styffenwl:BAEBLAAFFIETAAMFAAcIYhg2AACoAgc5DAAAAwBQADsMAAADAGEAOgwAAAMAXQA8DAAAAwA3ADIMAAADAAsAPQwAAAMATwA+DAAAAQATAAUABwhiGDYAAKgCBzkMAAACAFAAOwwAAAMAYQA6DAAAAQBdADwMAAADADcAMgwAAAMACwA9DAAAAwBPAD4MAAABABMABgACCP8WLQcArAACOQwAAAEATwA6DAAAAgAlAAEsAAQKCAgTAAoAAAAA.',['Sø']='Sønnie:BAEALAAECgUIBgAAAA==.',To='Tokhath:BAEALAAECgMIBQABLAAECgQIBwAKAAAAAA==.Totemting:BAEALAAECgcIBAAAAA==.',Tr='Treadknight:BAEALAAECgQIBwAAAA==.',Ve='Vealin:BAEALAAECgMIAwAAAA==.',Wa='Waidur:BAEALAAFFAEIAQABLAAFFAYICwANAFgFAA==.Warribert:BAECLAAFFIEJAAIQAAQI9h8eAgCaAQQ5DAAAAwBaADsMAAACADYAOgwAAAMAYQA8DAAAAQBUABAABAj2Hx4CAJoBBDkMAAADAFoAOwwAAAIANgA6DAAAAwBhADwMAAABAFQALAAECoEYAAIQAAgIUyXkCAANAwAQAAgIUyXkCAANAwAAAA==.',Wi='Wingstrument:BAECLAAFFIEHAAIWAAMIoBnpBAAEAQM5DAAAAgBGADsMAAACAFMAOgwAAAMAKgAWAAMIoBnpBAAEAQM5DAAAAgBGADsMAAACAFMAOgwAAAMAKgAsAAQKgRUAAhYACAihIDgJAMcCABYACAihIDgJAMcCAAAA.',Xe='Xelebrate:BAECLAAFFIEIAAIXAAUIExxyAAD0AQU5DAAAAgBUADsMAAACAFkAOgwAAAIAXwA8DAAAAQA/AD0MAAABABsAFwAFCBMccgAA9AEFOQwAAAIAVAA7DAAAAgBZADoMAAACAF8APAwAAAEAPwA9DAAAAQAbACwABAqBHgACFwAICGsmdgAAgQMAFwAICGsmdgAAgQMAAAA=.',Za='Zaorex:BAEALAADCgMIAwABLAAFFAIIAgAKAAAAAA==.Zarend:BAEALAAFFAIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end