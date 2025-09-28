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
 local lookup = {'Hunter-Marksmanship','Druid-Feral','Paladin-Holy','Paladin-Protection','Paladin-Retribution','Mage-Arcane','Monk-Windwalker','Hunter-BeastMastery','Evoker-Devastation','DeathKnight-Frost','Monk-Mistweaver','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Priest-Holy','Priest-Shadow','Druid-Restoration','Warlock-Destruction','Warrior-Arms','DeathKnight-Unholy','Hunter-Survival','Warrior-Fury','Warrior-Protection','Shaman-Elemental','Druid-Balance','Warlock-Demonology',}; local provider = {region='EU',realm='Ravencrest',name='EU',type='subscribers',zone=44,date='2025-09-25',data={Aj='Ajual:BAEALAADCgIIAgABLAAFFAQIDAABAKUgAA==.Ajuna:BAECLAAFFIEMAAIBAAQIpSCpBgB1AQQ5DAAABABEADsMAAADAF4AOgwAAAMAXwA8DAAAAgBMAAEABAilIKkGAHUBBDkMAAAEAEQAOwwAAAMAXgA6DAAAAwBfADwMAAACAEwALAAECoEmAAIBAAgIsSJtCwD+AgABAAgIsSJtCwD+AgAAAA==.Ajunaa:BAEALAADCgEIAQABLAAFFAQIDAABAKUgAA==.Ajured:BAEALAAECgIIAwABLAAFFAQIDAABAKUgAA==.',An='Antrakt:BAEALAAECgcIDgABLAAFFAIIDgACAK0dAA==.',Bi='Bikerbent:BAECLAAFFIEYAAIDAAUI9x4iAwDnAQU5DAAABgBhADsMAAAFAFQAOgwAAAYAWAA8DAAABAA7AD0MAAADAEEAAwAFCPceIgMA5wEFOQwAAAYAYQA7DAAABQBUADoMAAAGAFgAPAwAAAQAOwA9DAAAAwBBACwABAqBOAAEAwAICKAjFgUAAwMAAwAICKAjFgUAAwMABAAGCOoftRMANwIABQABCF8N7kUBNQAAAAA=.',Bl='Blastwain:BAEBLAAECoElAAIGAAgIRSB3HwDBAgg5DAAABQBWADsMAAAFAGAAOgwAAAUAVQA8DAAABwBZADIMAAAFAFUAPQwAAAYAWAA+DAAAAgBQAD8MAAACADAABgAICEUgdx8AwQIIOQwAAAUAVgA7DAAABQBgADoMAAAFAFUAPAwAAAcAWQAyDAAABQBVAD0MAAAGAFgAPgwAAAIAUAA/DAAAAgAwAAAA.',Bo='Bobbindk:BAEALAAECgYIBQABLAAFFAYIGAAHABAbAA==.',Br='Brinkadin:BAECLAAFFIEGAAIFAAIIbhbVKwCiAAI5DAAAAwBKADoMAAADACgABQACCG4W1SsAogACOQwAAAMASgA6DAAAAwAoACwABAqBGwACBQAICI0kuQcAXAMABQAICI0kuQcAXAMAASwABRQHCBcACAANHgA=.Brinkdruid:BAEALAAECgYIBgABLAAFFAcIFwAIAA0eAA==.Brinkevo:BAEBLAAFFIEFAAIJAAUIVA2SBwBmAQU5DAAAAQA0ADsMAAABADYAOgwAAAEAKAA8DAAAAQADAD0MAAABABQACQAFCFQNkgcAZgEFOQwAAAEANAA7DAAAAQA2ADoMAAABACgAPAwAAAEAAwA9DAAAAQAUAAEsAAUUBwgXAAgADR4A.Brinkhunt:BAECLAAFFIEXAAMIAAcIDR7HAAB8Agc5DAAABABjADsMAAAEADwAOgwAAAQAWgA8DAAAAwBQADIMAAAEAE0APQwAAAMAWgA+DAAAAQAnAAgABwgYHccAAHwCBzkMAAADAGMAOwwAAAMAPAA6DAAAAwBaADwMAAACAD8AMgwAAAIATQA9DAAAAgBaAD4MAAABACcAAQAGCE0PQQUApQEGOQwAAAEAIwA7DAAAAQAaADoMAAABAEMAPAwAAAEAUAAyDAAAAgAJAD0MAAABAA4ALAAECoElAAMIAAgIciZ9AgB0AwAIAAgIciZ9AgB0AwABAAYIzSGwKwAHAgAAAA==.',Ch='Choiyena:BAECLAAFFIEYAAIKAAYItx4aCADXAQY5DAAABgBTADsMAAADAE0AOgwAAAYAWwA8DAAABQBaAD0MAAADACwAPgwAAAEAUwAKAAYItx4aCADXAQY5DAAABgBTADsMAAADAE0AOgwAAAYAWwA8DAAABQBaAD0MAAADACwAPgwAAAEAUwAsAAQKgSAAAgoACAheJYgTABEDAAoACAheJYgTABEDAAAA.',Ci='Ciika:BAEBLAAECoE0AAIDAAgIuh+cCgCzAgg5DAAABwA8ADsMAAAHAE8AOgwAAAcAXQA8DAAABwBcADIMAAAHAFsAPQwAAAYATAA+DAAABgA/AD8MAAAFAFwAAwAICLofnAoAswIIOQwAAAcAPAA7DAAABwBPADoMAAAHAF0APAwAAAcAXAAyDAAABwBbAD0MAAAGAEwAPgwAAAYAPwA/DAAABQBcAAAA.',Cl='Clodsire:BAECLAAFFIEaAAILAAYIFCVmAACGAgY5DAAABQBjADsMAAAFAF0AOgwAAAYAYAA8DAAABABcADIMAAACAFwAPQwAAAQAXgALAAYIFCVmAACGAgY5DAAABQBjADsMAAAFAF0AOgwAAAYAYAA8DAAABABcADIMAAACAFwAPQwAAAQAXgAsAAQKgSgAAgsACAgBGxQQAEUCAAsACAgBGxQQAEUCAAAA.',Cp='Cptsimda:BAEALAAECggIDgAAAA==.',Da='Dangercookie:BAEALAAECggIBwAAAA==.',De='Demsi:BAEALAADCgcIDgAAAA==.',Dr='Drogakak:BAEALAADCgIIAgABLAAFFAMIDAALAGgeAA==.',Du='Dummernick:BAEALAAECgIIAgABLAAFFAUIGAADAPceAA==.',['Dé']='Déadmeme:BAECLAAFFIEPAAIMAAUISxaPCQCuAQU5DAAABABEADsMAAADAEAAOgwAAAQASQA8DAAAAgAsAD0MAAACACEADAAFCEsWjwkArgEFOQwAAAQARAA7DAAAAwBAADoMAAAEAEkAPAwAAAIALAA9DAAAAgAhACwABAqBPgACDAAICGQlQgsAPgMADAAICGQlQgsAPgMAAAA=.',Em='Eminos:BAECLAAFFIESAAMIAAUIFB0tBQDZAQU5DAAABQBfADsMAAAEAFYAOgwAAAUAXgA8DAAAAgATAD0MAAACAEwACAAFCBQdLQUA2QEFOQwAAAIAXwA7DAAAAgBWADoMAAACAF4APAwAAAIAEwA9DAAAAgBMAAEAAwgjGiMNAOMAAzkMAAADAFYAOwwAAAIAOgA6DAAAAwA3ACwABAqBNgADCAAICPUlkQcARQMACAAICN8kkQcARQMAAQAICCAjkw0A6wIAAAA=.',Er='Eranelle:BAEALAADCggICAAAAA==.',Ex='Exoar:BAECLAAFFIEOAAICAAMIiSPEAwAXAQM5DAAABQBfADsMAAAEAFMAOgwAAAUAXgACAAMIiSPEAwAXAQM5DAAABQBfADsMAAAEAFMAOgwAAAUAXgAsAAQKgSoAAgIACAihIgEDADgDAAIACAihIgEDADgDAAAA.Exøar:BAEBLAAECoEaAAINAAgIWRtuCACfAgg5DAAABQBaADsMAAAEAFQAOgwAAAQAVwA8DAAABABVADIMAAAEAE4APQwAAAMASQA+DAAAAQAiAD8MAAABABgADQAICFkbbggAnwIIOQwAAAUAWgA7DAAABABUADoMAAAEAFcAPAwAAAQAVQAyDAAABABOAD0MAAADAEkAPgwAAAEAIgA/DAAAAQAYAAEsAAUUAwgOAAIAiSMA.',Fa='Falconeye:BAECLAAFFIERAAIBAAUIYxJ+BgB7AQU5DAAABQBTADsMAAAEADgAOgwAAAUANgA8DAAAAQATAD0MAAACABUAAQAFCGMSfgYAewEFOQwAAAUAUwA7DAAABAA4ADoMAAAFADYAPAwAAAEAEwA9DAAAAgAVACwABAqBJgACAQAICB0e8BUAogIAAQAICB0e8BUAogIAAAA=.',Fr='Frontflipz:BAEALAADCgUICQABLAAFFAUIGAADAPceAA==.',Ga='Garlicc:BAECLAAFFIEOAAICAAIIrR1iBwCtAAI5DAAABwBTADoMAAAHAEQAAgACCK0dYgcArQACOQwAAAcAUwA6DAAABwBEACwABAqBLQACAgAICCYjUQQAFwMAAgAICCYjUQQAFwMAAAA=.',He='Hellwain:BAEBLAAECoElAAIOAAgIHBoEEwB7Agg5DAAABABSADsMAAAHAFMAOgwAAAYAWgA8DAAABgA/ADIMAAAGADwAPQwAAAUATwA+DAAAAgA4AD8MAAABABIADgAICBwaBBMAewIIOQwAAAQAUgA7DAAABwBTADoMAAAGAFoAPAwAAAYAPwAyDAAABgA8AD0MAAAFAE8APgwAAAIAOAA/DAAAAQASAAEsAAQKCAglAAYARSAA.Hellwainz:BAEALAADCgcIBwABLAAECggIJQAGAEUgAA==.Hensomecat:BAEALAADCgYICwAAAA==.',Ig='Igniz:BAEALAADCggIDgABLAAFFAIICAAKAIIlAA==.',Il='Illivondario:BAEALAAECgYICQABLAAFFAMIDQANANsgAA==.',Ja='Jaimeesoom:BAECLAAFFIESAAIPAAUI4xF4BACFAQU5DAAABABBADsMAAAEACgAOgwAAAUAUQA8DAAAAwAVAD0MAAACABQADwAFCOMReAQAhQEFOQwAAAQAQQA7DAAABAAoADoMAAAFAFEAPAwAAAMAFQA9DAAAAgAUACwABAqBHQACDwAICNIduQYAsgIADwAICNIduQYAsgIAAAA=.Jaimée:BAECLAAFFIEIAAMQAAMIswarFQDKAAM5DAAAAwANADsMAAACAA8AOgwAAAMAFwAQAAMIswarFQDKAAM5DAAAAgANADsMAAACAA8AOgwAAAIAFwARAAIISBPKGACQAAI5DAAAAQAyADoMAAABADAALAAECoEiAAMRAAgI8yJBCwAQAwARAAgI8yJBCwAQAwAQAAEInAm9pQA0AAABLAAFFAUIEgAPAOMRAA==.',Ka='Kaneian:BAECLAAFFIEIAAIDAAMILRh4DwCwAAM5DAAABABXADsMAAABACwAOgwAAAMANQADAAMILRh4DwCwAAM5DAAABABXADsMAAABACwAOgwAAAMANQAsAAQKgSYAAgMACAj2GzcTAFQCAAMACAj2GzcTAFQCAAAA.',Kh='Kharnak:BAEALAADCggICAABLAAECggINAAQAO8kAA==.',Ki='Kiirie:BAEALAAECgYIBgABLAAECggINAADALofAA==.',Li='Lillyrawr:BAEBLAAECoEYAAISAAgIIhaxKQAWAgg5DAAAAwBMADsMAAADAEMAOgwAAAMAPQA8DAAAAgAQADIMAAACAEUAPQwAAAIADAA+DAAABQBNAD8MAAAEAEcAEgAICCIWsSkAFgIIOQwAAAMATAA7DAAAAwBDADoMAAADAD0APAwAAAIAEAAyDAAAAgBFAD0MAAACAAwAPgwAAAUATQA/DAAABABHAAAA.',Mi='Mirkolock:BAECLAAFFIEFAAITAAMIThp/FgALAQM5DAAAAgBUADsMAAABABoAOgwAAAIAWgATAAMIThp/FgALAQM5DAAAAgBUADsMAAABABoAOgwAAAIAWgAsAAQKgSAAAhMACAhgJBIGAFoDABMACAhgJBIGAFoDAAEsAAUUAggGAAEALyMA.Mirkoo:BAEBLAAECoEaAAIUAAgIwiVSAACEAwg5DAAABABjADsMAAADAGEAOgwAAAQAYQA8DAAAAwBhADIMAAAEAGMAPQwAAAQAYwA+DAAAAgBYAD8MAAACAF4AFAAICMIlUgAAhAMIOQwAAAQAYwA7DAAAAwBhADoMAAAEAGEAPAwAAAMAYQAyDAAABABjAD0MAAAEAGMAPgwAAAIAWAA/DAAAAgBeAAEsAAUUAggGAAEALyMA.Mirkowo:BAECLAAFFIEGAAIHAAIIQh3xCQCtAAI5DAAAAwBHADoMAAADAE4ABwACCEId8QkArQACOQwAAAMARwA6DAAAAwBOACwABAqBGAACBwAHCCMixxUAPQIABwAHCCMixxUAPQIAASwABRQCCAYAAQAvIwA=.Mirkö:BAECLAAFFIEGAAMBAAIILyOsEQC8AAI5DAAAAwBgADoMAAADAFMAAQACCK8hrBEAvAACOQwAAAEAWAA6DAAAAQBTAAgAAgjlHvwbALsAAjkMAAACAGAAOgwAAAIAPQAsAAQKgTEAAwgACAj5JXkEAF4DAAgACAiwJXkEAF4DAAEACAjzIy0GADIDAAAA.',Mo='Morsashor:BAECLAAFFIEIAAIKAAIIgiW8HgDVAAI5DAAABABfADoMAAAEAGAACgACCIIlvB4A1QACOQwAAAQAXwA6DAAABABgACwABAqBFgADCgAHCIQjNjMAhQIACgAHCIQjNjMAhQIAFQABCOwM8FYAMQAAAAA=.Morsevoker:BAEALAAECgYIBgABLAAFFAIICAAKAIIlAA==.Morshunter:BAEBLAAECoEUAAIWAAgIwRq+AwCoAgg5DAAAAwBPADsMAAADAFoAOgwAAAMASgA8DAAAAwBHADIMAAADAFwAPQwAAAMATgA+DAAAAQAOAD8MAAABAC0AFgAICMEavgMAqAIIOQwAAAMATwA7DAAAAwBaADoMAAADAEoAPAwAAAMARwAyDAAAAwBcAD0MAAADAE4APgwAAAEADgA/DAAAAQAtAAEsAAUUAggIAAoAgiUA.Morswar:BAEBLAAECoEbAAQXAAgI5x52GwDGAgg5DAAABABaADsMAAAEAFMAOgwAAAQAXgA8DAAABABMADIMAAAEAEsAPQwAAAQAVQA+DAAAAQA6AD8MAAACAEMAFwAICOcedhsAxgIIOQwAAAMAWgA7DAAAAwBTADoMAAADAF4APAwAAAMATAAyDAAAAgBLAD0MAAADAFUAPgwAAAEAOgA/DAAAAgBDABQABgikFAoTAIgBBjkMAAABAE0AOwwAAAEAQwA6DAAAAQA6ADwMAAABABsAMgwAAAEAFgA9DAAAAQA/ABgAAQjUGqd0AEwAATIMAAABAEQAASwABRQCCAgACgCCJQA=.',My='Myunghee:BAEBLAAECoEkAAIHAAYIPiMfGQAYAgY5DAAABwBaADsMAAAHAFoAOgwAAAYAXgA8DAAABwBdADIMAAAGAFsAPQwAAAMAUQAHAAYIPiMfGQAYAgY5DAAABwBaADsMAAAHAFoAOgwAAAYAXgA8DAAABwBdADIMAAAGAFsAPQwAAAMAUQAAAA==.',Ne='Nethersong:BAEALAAFFAIIAgABLAAFFAcIHAAZAB0hAA==.',Ni='Nickelodeon:BAEALAADCgYIBgABLAAFFAUIGAADAPceAA==.',Pa='Pallindrome:BAEALAAECgcIEQABLAAFFAIICAAKAIIlAA==.',Pi='Pinkdome:BAECLAAFFIENAAIEAAMIBR9rBAARAQM5DAAABQBQADsMAAADAEkAOgwAAAUAVAAEAAMIBR9rBAARAQM5DAAABQBQADsMAAADAEkAOgwAAAUAVAAsAAQKgSMAAgQACAhFI3cFABMDAAQACAhFI3cFABMDAAAA.Pinkelvara:BAEALAAFFAMIAwABLAAFFAMIDQAEAAUfAA==.Pinkfaceroll:BAEALAAECgYICgABLAAFFAMIDQAEAAUfAA==.Pissenta:BAECLAAFFIEMAAILAAMIaB7tBQAjAQM5DAAABQBaADsMAAADADQAOgwAAAQAWgALAAMIaB7tBQAjAQM5DAAABQBaADsMAAADADQAOgwAAAQAWgAsAAQKgSkAAgsACAiCIYcFAPkCAAsACAiCIYcFAPkCAAAA.',Re='Restolover:BAEALAAFFAMIAwABLAAFFAUIGAADAPceAA==.',Ro='Ronkykles:BAECLAAFFIEVAAMKAAgIESSOAQB7Agg5DAAABABjADsMAAADAGEAOgwAAAMAYwA8DAAABABeADIMAAACAF0APQwAAAMAWAA+DAAAAQBhAD8MAAABAEMACgAHCEgkjgEAewIHOQwAAAQAYwA7DAAAAwBhADoMAAADAGMAPAwAAAQAXgAyDAAAAgBdAD4MAAABAGEAPwwAAAEAQwAVAAEIkyJoEwBlAAE9DAAAAwBYACwABAqBJAACCgAICL0mlAAAkwMACgAICL0mlAAAkwMAAAA=.',Sh='Shaimee:BAEALAAECggIDgABLAAFFAUIEgAPAOMRAA==.Shuff:BAEBLAAECoEcAAIaAAgIth2eHgBGAgg5DAAAAwBbADsMAAAEAD8AOgwAAAMAVwA8DAAABABNADIMAAAEAFEAPQwAAAQAWQA+DAAABABQAD8MAAACACUAGgAICLYdnh4ARgIIOQwAAAMAWwA7DAAABAA/ADoMAAADAFcAPAwAAAQATQAyDAAABABRAD0MAAAEAFkAPgwAAAQAUAA/DAAAAgAlAAEsAAQKCAgUABsAlhwA.Shuffybozo:BAEALAAECgYICQABLAAECggIFAAbAJYcAA==.Shuffydemon:BAEBLAAECoEUAAMbAAgIlhzyJQDEAQg5DAAAAgBUADsMAAAEAFsAOgwAAAIAHgA8DAAABABHADIMAAACAEgAPQwAAAQAXgA+DAAAAQBFAD8MAAABAEYAGwAHCPwe8iUAxAEHOQwAAAIAVAA7DAAABABbADwMAAABAEcAMgwAAAEASAA9DAAAAgBeAD4MAAABAEUAPwwAAAEARgATAAQIKwxEswCyAAQ6DAAAAgAeADwMAAADACwAMgwAAAEAAgA9DAAAAgAwAAAA.',Sk='Skovbyen:BAEALAAECggICAABLAAFFAMIDQANANsgAA==.Skovrogue:BAECLAAFFIENAAMNAAMI2yB8BgAFAQM5DAAABQBhADsMAAADAEkAOgwAAAUAUQANAAMIgB58BgAFAQM5DAAAAgBPADsMAAABAEkAOgwAAAUAUQAOAAIIux/mFQCXAAI5DAAAAwBhADsMAAACAEAALAAECoFCAAMNAAgIzSV/BAD7AgANAAgIoSF/BAD7AgAOAAcIWiSHCwDOAgAAAA==.',St='Streily:BAEALAAECgcIBwABLAAFFAUIBgAaANkKAA==.Strongpink:BAEALAAECgIIAgABLAAFFAMIDQAEAAUfAA==.',Sy='Syncopium:BAECLAAFFIEZAAMLAAYIphS5AgDRAQY5DAAABgA/ADsMAAAFAFAAOgwAAAYATQA8DAAABAAZADIMAAABAAEAPQwAAAMARAALAAYIphS5AgDRAQY5DAAABgA/ADsMAAAFAFAAOgwAAAUATQA8DAAABAAZADIMAAABAAEAPQwAAAMARAAHAAEIVAh7FABDAAE6DAAAAQAVACwABAqBMAADCwAICJ0jXQQAEAMACwAICJ0jXQQAEAMABwAHCCIR5igAjgEAAAA=.Synsis:BAEALAAECgEIAQABLAAFFAYIGQALAKYUAA==.',Tr='Traaxex:BAECLAAFFIELAAIBAAQIgSXDBACzAQQ5DAAABABgADsMAAACAGEAOgwAAAQAYwA8DAAAAQBaAAEABAiBJcMEALMBBDkMAAAEAGAAOwwAAAIAYQA6DAAABABjADwMAAABAFoALAAECoEjAAIBAAgI+CQ4BwAnAwABAAgI+CQ4BwAnAwAAAA==.Traxsex:BAEALAAECggIEAABLAAFFAUICwABAIElAA==.Traxxexx:BAEALAAECggIEQABLAAFFAUICwABAIElAA==.',Va='Vastrani:BAEALAADCggICAABLAAECggINAAQAO8kAA==.',Ya='Yanná:BAEBLAAECoE0AAIQAAgI7ySXAwBSAwg5DAAABwBdADsMAAAHAGAAOgwAAAcAYAA8DAAABwBeADIMAAAHAGEAPQwAAAYAWgA+DAAABgBeAD8MAAAFAFwAEAAICO8klwMAUgMIOQwAAAcAXQA7DAAABwBgADoMAAAHAGAAPAwAAAcAXgAyDAAABwBhAD0MAAAGAFoAPgwAAAYAXgA/DAAABQBcAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end