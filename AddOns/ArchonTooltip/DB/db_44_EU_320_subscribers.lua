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
 local lookup = {'Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Warlock-Destruction','Monk-Windwalker','Warlock-Demonology','Shaman-Elemental','Shaman-Enhancement','Druid-Feral','Hunter-Marksmanship','Monk-Brewmaster','Evoker-Preservation','Paladin-Holy','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','Priest-Holy','Priest-Shadow','Druid-Balance','Druid-Restoration','Warrior-Fury','Warlock-Affliction','Warrior-Protection','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Frost','Monk-Mistweaver','Mage-Arcane',}; local provider = {region='EU',realm='Ragnaros',name='EU',type='subscribers',zone=44,date='2025-09-25',data={An='Ancalágon:BAEALAAECgYICwABLAAFFAMICgABAJsVAA==.Ande:BAEALAAFFAIIAgAAAA==.',Ap='Apachi:BAEBLAAECoEaAAMCAAgIXBs9FQBjAgg5DAAAAwBKADsMAAADAFIAOgwAAAQATQA8DAAABQBbADIMAAADAFMAPQwAAAQANAA+DAAAAwBbAD8MAAABAAUAAgAICFwbPRUAYwIIOQwAAAMASgA7DAAAAwBSADoMAAAEAE0APAwAAAMAWwAyDAAAAgBTAD0MAAAEADQAPgwAAAMAWwA/DAAAAQAFAAMAAggxFWI7AHQAAjwMAAACAC4AMgwAAAEAPgABLAAFFAYIEwACAEcgAA==.Apparatchik:BAECLAAFFIETAAQCAAYIRyALBAB5AQY5DAAAAwBeADsMAAADAE0AOgwAAAMATgA8DAAABABMADIMAAACAEUAPQwAAAQAYgACAAQI1BwLBAB5AQQ5DAAAAwBeADsMAAADAE0AOgwAAAEAFwA9DAAABABiAAMAAgg3Hv4KAKcAAjoMAAACAE4APAwAAAQATAAEAAEIORs4BQBbAAEyDAAAAgBFACwABAqBJQAEAgAICIokggMAPQMAAgAICN8jggMAPQMAAwAECPohZxwAigEABAABCIkhZBgAYwAAAAA=.',Bl='Blxreroll:BAEALAAFFAIIAgABLAAFFAYIGwAFAKchAA==.',Bo='Bolldingo:BAEALAAECgcIDQABLAAFFAcIHwAGAB4jAA==.Bonytta:BAEALAADCgEIAQABLAAECggIGgAHACggAA==.',Ca='Capsalot:BAECLAAFFIEWAAMIAAUIVCEoBQDzAQU5DAAABgBfADsMAAAFAFAAOgwAAAYAXQA8DAAAAwBSAD0MAAACAEsACAAFCFQhKAUA8wEFOQwAAAQAXwA7DAAABABQADoMAAAEAF0APAwAAAMAUgA9DAAAAgBLAAkAAwhhFtICAPQAAzkMAAACAF4AOwwAAAEAJgA6DAAAAgAmACwABAqBMAADCAAICI8lewQAZgMACAAICAIlewQAZgMACQAICIwkSgQA2QIAAAA=.Carpetnar:BAEALAAECgcIDwABLAAFFAYIGQAKAEQdAA==.',Ch='Chimedh:BAEALAADCggICAABLAAECggIIQAJABofAA==.Chimeshaman:BAEBLAAECoEhAAMJAAgIGh8jBQC8Agg5DAAABwBWADsMAAAGAF8AOgwAAAQAYgA8DAAABABWADIMAAAFAFgAPQwAAAQAXwA+DAAAAgAyAD8MAAABACMACQAICBofIwUAvAIIOQwAAAcAVgA7DAAABgBfADoMAAAEAGIAPAwAAAQAVgAyDAAABQBYAD0MAAAEAF8APgwAAAEAMgA/DAAAAQAjAAgAAQgsDxmrAD8AAT4MAAABACYAAAA=.',Cr='Crwnn:BAEALAADCggIDwABLAAECgcIHQALAPMiAA==.Crâwenn:BAEALAADCggIEAABLAAECgcIHQALAPMiAA==.',Da='Danishdog:BAEALAAECgYIBgABLAAFFAUIDwAEAC0fAA==.',De='Denegatia:BAECLAAFFIEfAAMGAAcIHiOKAABrAgc5DAAABgBhADsMAAAGAGEAOgwAAAcAXgA8DAAABQBjADIMAAABAEYAPQwAAAUAYQA+DAAAAQBJAAYABwgeI4oAAGsCBzkMAAAFAGEAOwwAAAYAYQA6DAAABwBeADwMAAAFAGMAMgwAAAEARgA9DAAABQBhAD4MAAABAEkADAABCOcVdRYAQQABOQwAAAEAOAAsAAQKgSwAAgYACAjaJnoAAIwDAAYACAjaJnoAAIwDAAAA.',Dr='Dragicorn:BAECLAAFFIEPAAINAAYI4Qu0AwCuAQY5DAAABABaADsMAAACAAEAOgwAAAQAVQA8DAAAAgAAADIMAAABAAAAPQwAAAIAAwANAAYI4Qu0AwCuAQY5DAAABABaADsMAAACAAEAOgwAAAQAVQA8DAAAAgAAADIMAAABAAAAPQwAAAIAAwAsAAQKgSEAAg0ACAhHG84HAJsCAA0ACAhHG84HAJsCAAEsAAUUBwgMAA4APgoA.',['Dà']='Dàrk:BAECLAAFFIEYAAIPAAUI/h11AgDYAQU5DAAABgBVADsMAAAFAFoAOgwAAAYASAA8DAAABABCAD0MAAADAEQADwAFCP4ddQIA2AEFOQwAAAYAVQA7DAAABQBaADoMAAAGAEgAPAwAAAQAQgA9DAAAAwBEACwABAqBJwACDwAICIUjigUAAAMADwAICIUjigUAAAMAAAA=.',['Dá']='Dárkflame:BAEALAAFFAIIAgABLAAFFAUIDgALAH0jAA==.',['Dä']='Därkbeast:BAECLAAFFIEOAAMLAAUIfSOUBgB4AQU5DAAABQBcADsMAAADAF8AOgwAAAQAWwA8DAAAAQBcAD0MAAABAFIACwAECLUclAYAeAEEOQwAAAQAWgA7DAAAAQBfADoMAAADABAAPAwAAAEAXAABAAQIlh60CwBRAQQ5DAAAAQBcADsMAAACAC4AOgwAAAEAWwA9DAAAAQBSACwABAqBKgADCwAICNAi2hAAzwIACwAICDoi2hAAzwIAAQAGCMQhVEoACAIAAAA=.',El='Elejulqt:BAEALAAFFAIIAgABLAAFFAMIDAAQAMQjAA==.',En='Engrah:BAEBLAAECoEaAAMHAAgIKCD7FAA5Agg5DAAABQBcADsMAAAFAGAAOgwAAAQAWAA8DAAABABDADIMAAADAEYAPQwAAAMAXQA+DAAAAQBKAD8MAAABAEsABwAGCOUh+xQAOQIGOQwAAAUAXAA7DAAABQBgADoMAAAEAFgAPQwAAAMAXQA+DAAAAQBKAD8MAAABAEsABQACCPMaIroAmwACPAwAAAQAQwAyDAAAAwBGAAAA.Enormesvindk:BAEALAAECgYIBgABLAAFFAUIDwAEAC0fAA==.Enormesvinro:BAECLAAFFIEPAAIEAAUILR9mAAAGAgU5DAAABABhADsMAAAEAFQAOgwAAAQAYwA8DAAAAQAUAD0MAAACAGAABAAFCC0fZgAABgIFOQwAAAQAYQA7DAAABABUADoMAAAEAGMAPAwAAAEAFAA9DAAAAgBgACwABAqBIQACBAAICGsmLQAAjAMABAAICGsmLQAAjAMAAAA=.',Gr='Grækenland:BAEALAAECgMIBAABLAAFFAIIBAARAAAAAA==.',Ho='Holyunicorn:BAEBLAAFFIEMAAIOAAcIPgohAgASAgc5DAAAAgBOADsMAAABAAgAOgwAAAIARAA8DAAAAgAGADIMAAACAAEAPQwAAAIACQA+DAAAAQAJAA4ABwg+CiECABICBzkMAAACAE4AOwwAAAEACAA6DAAAAgBEADwMAAACAAYAMgwAAAIAAQA9DAAAAgAJAD4MAAABAAkAAAA=.Holyzmile:BAEBLAAFFIERAAMSAAYINxSVBgChAQY5DAAABABCADsMAAAEADIAOgwAAAQAQQA8DAAAAQAEADIMAAABAC0APQwAAAMATQASAAUI6ReVBgChAQU5DAAABABCADsMAAAEADIAOgwAAAQAQQAyDAAAAQAtAD0MAAADAE0AEwABCO0B5iQAQAABPAwAAAEABAAAAA==.',Ic='Icyhater:BAEBLAAECoEYAAIUAAgI8w+4NAC/AQg5DAAAAgBAADsMAAADAD4AOgwAAAMAIAA8DAAABAAmADIMAAAEABkAPQwAAAQALgA+DAAAAwAhAD8MAAABABYAFAAICPMPuDQAvwEIOQwAAAIAQAA7DAAAAwA+ADoMAAADACAAPAwAAAQAJgAyDAAABAAZAD0MAAAEAC4APgwAAAMAIQA/DAAAAQAWAAAA.',Il='Ildifusserne:BAEALAAFFAIIAgABLAAFFAIIBAARAAAAAA==.Ilyindia:BAEBLAAECoEhAAIQAAgIDR/mIQDAAgg5DAAABgBfADsMAAAGAFoAOgwAAAUARAA8DAAABQBSADIMAAAEAE8APQwAAAQAVAA+DAAAAgBbAD8MAAABACwAEAAICA0f5iEAwAIIOQwAAAYAXwA7DAAABgBaADoMAAAFAEQAPAwAAAUAUgAyDAAABABPAD0MAAAEAFQAPgwAAAIAWwA/DAAAAQAsAAAA.',Jo='Joshyidh:BAEALAAECggIDwABLAAFFAMICAAIAF0WAA==.Joshyidk:BAEALAAECggICQABLAAFFAMICAAIAF0WAA==.Joshyijr:BAEALAADCgUIBQABLAAFFAMICAAIAF0WAA==.Joshyis:BAEBLAAFFIEIAAIIAAMIXRaqEADwAAM5DAAAAwA0ADsMAAACADAAOgwAAAMARgAIAAMIXRaqEADwAAM5DAAAAwA0ADsMAAACADAAOgwAAAMARgAAAA==.',Kn='Knäifu:BAEALAAFFAIIAgAAAA==.',Kw='Kwigga:BAEALAAECggIEAABLAAFFAYIHAAVACAmAA==.',Le='Lenerie:BAEALAAECgcIEgABLAAECgcIGQAWAOIXAA==.',Li='Litendave:BAECLAAFFIEKAAIWAAII+xMZJACeAAI5DAAABQAzADoMAAAFADMAFgACCPsTGSQAngACOQwAAAUAMwA6DAAABQAzACwABAqBFAACFgAGCFUW1GMAlQEAFgAGCFUW1GMAlQEAAAA=.Livelørð:BAECLAAFFIEbAAMFAAYIpyGBAwBZAgY5DAAABgBjADsMAAAGAGAAOgwAAAYAYwA8DAAABQBdADIMAAABACMAPQwAAAMAXAAFAAYIpyGBAwBZAgY5DAAABgBjADsMAAAGAGAAOgwAAAEAYwA8DAAABQBdADIMAAABACMAPQwAAAMAXAAHAAEITSKOGwBeAAE6DAAABQBXACwABAqBJAAEBQAICBUkNAwALAMABQAICMAjNAwALAMAFwAFCF4iXg0AwQEABwAFCCYjbSgAtgEAAAA=.',Lv='Lvlrd:BAEALAAECgEIAQABLAAFFAYIGwAFAKchAA==.',Ma='Margokel:BAEALAADCggIAQABLAAECggIIQAQAA0fAA==.',Me='Meownar:BAECLAAFFIEZAAIKAAYIRB1fAQDlAQY5DAAABgBgADsMAAAEAE8AOgwAAAQAXAA8DAAABQBSAD0MAAAFAFwAPgwAAAEABwAKAAYIRB1fAQDlAQY5DAAABgBgADsMAAAEAE8AOgwAAAQAXAA8DAAABQBSAD0MAAAFAFwAPgwAAAEABwAsAAQKgSQAAgoACAgdJtIAAHIDAAoACAgdJtIAAHIDAAAA.',Mo='Moó:BAECLAAFFIEKAAMBAAMImxU/FQDcAAM5DAAABAA3ADsMAAACADEAOgwAAAQAPQABAAMImxU/FQDcAAM5DAAAAwA3ADsMAAACADEAOgwAAAIAPQALAAIIPwyNJQB0AAI5DAAAAQAJADoMAAACADUALAAECoEmAAMLAAgIKB9tHQBnAgALAAgI9hxtHQBnAgABAAgIjxvSNABQAgAAAA==.',Mu='Murçisztár:BAEBLAAECoEZAAMWAAcI4hc7QwD9AQc5DAAABQBHADsMAAAFAFIAOgwAAAUAQAA8DAAAAwAoADIMAAADAEQAPQwAAAMAPQA+DAAAAQAnABYABwjiFztDAP0BBzkMAAAEAEcAOwwAAAQAUgA6DAAABABAADwMAAACACgAMgwAAAIARAA9DAAAAgA9AD4MAAABACcAGAAGCKkO0kQALAEGOQwAAAEAHAA7DAAAAQAlADoMAAABADcAPAwAAAEAEAAyDAAAAQAvAD0MAAABACgAAAA=.Muskotten:BAEBLAAECoEjAAISAAgIVR0XFwCcAgg5DAAABQBSADsMAAAFAFQAOgwAAAUAXAA8DAAABQA5ADIMAAAGAFAAPQwAAAUAWwA+DAAAAwBGAD8MAAABACkAEgAICFUdFxcAnAIIOQwAAAUAUgA7DAAABQBUADoMAAAFAFwAPAwAAAUAOQAyDAAABgBQAD0MAAAFAFsAPgwAAAMARgA/DAAAAQApAAAA.',Ne='Netherax:BAEBLAAFFIEQAAIIAAgIwR3IAACwAgg5DAAAAwBjADsMAAACAGAAOgwAAAQAZAA8DAAAAgBKADIMAAABABcAPQwAAAIAYQA+DAAAAQBFAD8MAAABAC8ACAAICMEdyAAAsAIIOQwAAAMAYwA7DAAAAgBgADoMAAAEAGQAPAwAAAIASgAyDAAAAQAXAD0MAAACAGEAPgwAAAEARQA/DAAAAQAvAAAA.',No='Nomuwu:BAEALAADCggICwABLAAECggIIQAQAA0fAA==.',Pe='Petérdh:BAEALAAECgIIAwAAAA==.',Pr='Prigga:BAEALAAECgYIBwABLAAFFAYIHAAVACAmAA==.Primeazoid:BAECLAAFFIEaAAISAAcI1SYDAAA7Awc5DAAABABkADsMAAAFAGQAOgwAAAUAZAA8DAAABABkADIMAAADAGQAPQwAAAQAYAA+DAAAAQBjABIABwjVJgMAADsDBzkMAAAEAGQAOwwAAAUAZAA6DAAABQBkADwMAAAEAGQAMgwAAAMAZAA9DAAABABgAD4MAAABAGMALAAECoEXAAISAAgIxSV+BABGAwASAAgIxSV+BABGAwAAAA==.',Ra='Rahka:BAEALAADCggIBwABLAAECggIIQAQAA0fAA==.',Re='Rexwarr:BAECLAAFFIEWAAIYAAUIAxyYAwCyAQU5DAAABgBfADsMAAAFADsAOgwAAAYAWAA8DAAAAwBFAD0MAAACACwAGAAFCAMcmAMAsgEFOQwAAAYAXwA7DAAABQA7ADoMAAAGAFgAPAwAAAMARQA9DAAAAgAsACwABAqBHwACGAAICDshCAwAzAIAGAAICDshCAwAzAIAAAA=.',Sa='Sandkassen:BAEALAAFFAIIBAAAAA==.',Se='Setilvenstre:BAEALAAFFAIIBAABLAAFFAIIBAARAAAAAA==.',Sk='Skrai:BAECLAAFFIEOAAIZAAUI4huvBADEAQU5DAAABABXADsMAAACAFMAOgwAAAMATgA8DAAAAwAxADIMAAACADoAGQAFCOIbrwQAxAEFOQwAAAQAVwA7DAAAAgBTADoMAAADAE4APAwAAAMAMQAyDAAAAgA6ACwABAqBJAADGQAICPkjVQUAMQMAGQAICPkjVQUAMQMAGgABCKMWFxYARwAAAAA=.Skraitwo:BAEBLAAECoEcAAMZAAgIgiHNDADNAgg5DAAABABfADsMAAAEAFwAOgwAAAQAXQA8DAAABABbADIMAAADAEQAPQwAAAQAWAA+DAAAAwBVAD8MAAACAEYAGQAICIIhzQwAzQIIOQwAAAQAXwA7DAAABABcADoMAAAEAF0APAwAAAQAWwAyDAAAAwBEAD0MAAAEAFgAPgwAAAIAVQA/DAAAAgBGABoAAQgCHYsVAFIAAT4MAAABAEoAASwABRQFCA4AGQDiGwA=.',Sm='Smòsh:BAEALAADCggIFQABLAAFFAMICgABAJsVAA==.',Sw='Swiga:BAEALAAECggICAABLAAFFAYIHAAVACAmAA==.',Ta='Taskaine:BAECLAAFFIEZAAMNAAcIDQ8hAwDNAQc5DAAABQAvADsMAAAEAC4AOgwAAAUALQA8DAAABAAXADIMAAAEAC4APQwAAAIADAA+DAAAAQAvAA0ABgh1DiEDAM0BBjkMAAAEAC8AOwwAAAQALgA6DAAABQAtADwMAAAEABcAMgwAAAQALgA9DAAAAgAMABkAAgjbCjgTAJgAAjkMAAABACoAPgwAAAEADAAsAAQKgSUAAw0ACAhcHEkKAGoCAA0ACAhcHEkKAGoCABkABAgjG9Y7ADsBAAAA.Taskainedup:BAEALAAECgYIBgABLAAFFAcIGQANAA0PAA==.Taskainp:BAEBLAAECoEwAAISAAgIqxvjGgCCAgg5DAAABgBMADsMAAAGAFcAOgwAAAYAUAA8DAAABgAhADIMAAAGAFoAPQwAAAYAOgA+DAAABgBGAD8MAAAGAEQAEgAICKsb4xoAggIIOQwAAAYATAA7DAAABgBXADoMAAAGAFAAPAwAAAYAIQAyDAAABgBaAD0MAAAGADoAPgwAAAYARgA/DAAABgBEAAEsAAUUBwgZAA0ADQ8A.Taskainpala:BAEBLAAECoEUAAIOAAgIfRvqDQCLAgg5DAAAAwBWADsMAAADAFcAOgwAAAMAVgA8DAAAAwAmADIMAAACAF0APQwAAAIAUwA+DAAAAgAqAD8MAAACACwADgAICH0b6g0AiwIIOQwAAAMAVgA7DAAAAwBXADoMAAADAFYAPAwAAAMAJgAyDAAAAgBdAD0MAAACAFMAPgwAAAIAKgA/DAAAAgAsAAEsAAUUBwgZAA0ADQ8A.',Ti='Tibikasza:BAECLAAFFIEFAAIbAAIIiyGkIQDJAAI5DAAAAwBLADoMAAACAGAAGwACCIshpCEAyQACOQwAAAMASwA6DAAAAgBgACwABAqBGAACGwAICO8iKhsA6wIAGwAICO8iKhsA6wIAASwABAoICCEACQAaHwA=.Titanbelly:BAECLAAFFIEbAAIcAAcIyyUHAAAbAwc5DAAABgBkADsMAAAFAGMAOgwAAAQAZAA8DAAABABeADIMAAADAGQAPQwAAAQAYAA+DAAAAQBWABwABwjLJQcAABsDBzkMAAAGAGQAOwwAAAUAYwA6DAAABABkADwMAAAEAF4AMgwAAAMAZAA9DAAABABgAD4MAAABAFYALAAECoEeAAIcAAgIzCbfAABpAwAcAAgIzCbfAABpAwAAAA==.Titanhawk:BAEBLAAFFIEGAAIdAAIIziNuIgDHAAI5DAAAAwBZADoMAAADAF0AHQACCM4jbiIAxwACOQwAAAMAWQA6DAAAAwBdAAEsAAUUBwgbABwAyyUA.',Vo='Vollmer:BAEBLAAFFIEfAAMZAAcI6yR3AACnAgc5DAAABgBjADsMAAAGAGMAOgwAAAYAYwA8DAAABQBgADIMAAADAGMAPQwAAAQAYQA+DAAAAQBGABkABgiDJncAAKcCBjkMAAAGAGMAOwwAAAYAYwA6DAAABgBjADwMAAAFAGAAMgwAAAMAYwA9DAAABABhABoAAQhaGy4HAGkAAT4MAAABAEYAAAA=.Vollmerfire:BAEALAAECgEIAQABLAAFFAcIHwAZAOskAA==.',Wi='Wierv:BAEALAAECgcIBwABLAAFFAUIFgAIAFQhAA==.',Xa='Xaretas:BAEALAAECgUICgABLAAFFAMIDAAdAN8eAA==.',Ye='Yepterw:BAEALAAECgEIAgABLAAECgIIAwARAAAAAA==.',Zm='Zmile:BAEALAAECgYIBgABLAAFFAYIEQASADcUAA==.Zmiledrake:BAEBLAAECoEeAAINAAgI2x6QBQDQAgg5DAAABABeADsMAAAEAE0AOgwAAAQAWAA8DAAABAA6ADIMAAAEAFsAPQwAAAQAUQA+DAAAAwBaAD8MAAADADEADQAICNsekAUA0AIIOQwAAAQAXgA7DAAABABNADoMAAAEAFgAPAwAAAQAOgAyDAAABABbAD0MAAAEAFEAPgwAAAMAWgA/DAAAAwAxAAEsAAUUBggRABIANxQA.',Zz='Zzeeikw:BAEALAADCggICAABLAAFFAUIGAAPAP4dAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end