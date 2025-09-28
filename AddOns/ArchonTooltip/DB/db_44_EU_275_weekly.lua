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
 local lookup = {'Mage-Arcane','Hunter-BeastMastery','Druid-Restoration','Druid-Guardian','Druid-Balance','Warrior-Fury','Rogue-Subtlety','DeathKnight-Frost','Shaman-Enhancement','Shaman-Restoration','Mage-Frost','DemonHunter-Havoc','Unknown-Unknown','Evoker-Augmentation','Hunter-Marksmanship','DeathKnight-Blood','Priest-Shadow','Paladin-Retribution','Rogue-Assassination','Druid-Feral','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Monk-Windwalker','Warlock-Demonology','Warrior-Protection',}; local provider = {region='EU',realm='Daggerspine',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaroz:BAAALAAECggICAAAAA==.',Al='Alfonso:BAAALAAECggIDgAAAA==.',An='Angelfury:BAAALAAECgEIAgAAAA==.',Ar='Arcaneteven:BAABLAAECoEcAAIBAAcIfhxEUADtAQABAAcIfhxEUADtAQAAAA==.Artemia:BAAALAAFFAIIAgAAAA==.',Ax='Axejess:BAABLAAECoEkAAICAAgIwhyEKgBpAgACAAgIwhyEKgBpAgAAAA==.',Ba='Babypeaches:BAAALAADCggICwAAAA==.Bamso:BAABLAAECoEYAAQDAAcIJR1wMgDdAQADAAcIJR1wMgDdAQAEAAYIlxMkEgBpAQAFAAUIMRIBVAAjAQAAAA==.Bamzo:BAAALAAECgEIAQAAAA==.Banysmash:BAABLAAECoEVAAIGAAcIYxhhPAAGAgAGAAcIYxhhPAAGAgAAAA==.',Bi='Bionix:BAABLAAECoEUAAIHAAYI0xIUHQB5AQAHAAYI0xIUHQB5AQAAAA==.',Bl='Bluemidget:BAAALAADCggICAAAAA==.Blítzkrieg:BAAALAADCggICAABLAAECggIHQAIAJAhAA==.',Bo='Bogha:BAAALAAECgcIEgAAAA==.Bogwalker:BAAALAAECgYIEAAAAA==.',Br='Brulmats:BAABLAAECoEdAAMJAAcI+gZmFQBgAQAJAAcI+gZmFQBgAQAKAAcI4QiCnAAAAQAAAA==.',Ca='Calí:BAABLAAECoEgAAILAAgIgxcaGAAxAgALAAgIgxcaGAAxAgAAAA==.Catzbite:BAABLAAECoEfAAIMAAgIqBKbWADpAQAMAAgIqBKbWADpAQAAAA==.',Ch='Chains:BAAALAADCggICAABLAAECggIIQABAMkXAA==.Chicknuggets:BAAALAADCggICAABLAAECggIDgANAAAAAA==.Chiserymains:BAABLAAECoEhAAIBAAgIyRf1PAAyAgABAAgIyRf1PAAyAgAAAA==.',Cr='Creatrix:BAAALAADCgQIBAABLAAECgcIGwAOACgPAA==.Crúmpet:BAAALAAECggIDwAAAA==.',Cu='Cuthalion:BAABLAAECoEbAAIPAAgIAQ/IPgCdAQAPAAgIAQ/IPgCdAQAAAA==.',Da='Dagless:BAABLAAECoEZAAIQAAcIWxUaGwB0AQAQAAcIWxUaGwB0AQAAAA==.Darkgrim:BAABLAAECoEWAAIKAAYI5BthSADUAQAKAAYI5BthSADUAQAAAA==.Darklaw:BAAALAADCgQIBAAAAA==.Darksigns:BAAALAADCgcIBwABLAADCggICAANAAAAAA==.Darus:BAAALAAECgYIBgAAAA==.',Do='Dodgypala:BAAALAAFFAEIAQAAAA==.',Dr='Draccari:BAABLAAECoEfAAIGAAgIPxVBPAAHAgAGAAgIPxVBPAAHAgAAAA==.Drakhan:BAAALAAECgUICwABLAAECgYIDQANAAAAAA==.Draper:BAAALAADCggICAAAAA==.Draugen:BAAALAADCggIFQAAAA==.Drookhan:BAAALAAECgYIDQAAAA==.',['Dè']='Dèàth:BAAALAAECgcIDQAAAA==.',['Dí']='Dízzíe:BAABLAAECoEVAAIMAAcIyQtmjQB0AQAMAAcIyQtmjQB0AQAAAA==.',Ea='Eatmycrit:BAAALAAECgIIAgABLAAECgYIFgAKAOQbAA==.',Ex='Extorior:BAAALAAECgYICQAAAA==.',Fe='Ferda:BAAALAAECggICAAAAA==.',Fi='Fiststarter:BAAALAAECggICAAAAA==.',Gr='Grìmli:BAAALAADCgcIBwAAAA==.Grímnir:BAABLAAECoEdAAMIAAgIkCHTGwDhAgAIAAgIkCHTGwDhAgAQAAIIRyEYMQCKAAAAAA==.',He='Hentiepriest:BAABLAAECoElAAIRAAgILiBvDwDgAgARAAgILiBvDwDgAgAAAA==.Herdok:BAAALAADCggICgAAAA==.',Ho='Holycrit:BAAALAADCgQIBAABLAAECgYIFgAKAOQbAA==.Holymon:BAAALAAECggICAAAAA==.Hovnotoc:BAAALAADCgQIBAABLAAECggIDgANAAAAAA==.',Ic='Icaria:BAACLAAFFIEIAAISAAMIHRrfCwAMAQASAAMIHRrfCwAMAQAsAAQKgSYAAhIACAifIXEXAPsCABIACAifIXEXAPsCAAAA.',Ja='Jaeyla:BAAALAAECgIIAgABLAAECggIIAALAIMXAA==.Jaimiel:BAAALAADCggIFwAAAA==.Jamjam:BAAALAAECgcIDQAAAA==.',Ji='Jillofal:BAAALAAECgQICQAAAA==.Jisa:BAAALAADCgcIAgAAAA==.',Ka='Kazeh:BAAALAADCgcIBwAAAA==.',Kg='Kg:BAAALAAECgYIBgAAAA==.',Kr='Kraegaxe:BAAALAADCggICAAAAA==.Krump:BAACLAAFFIEGAAIKAAMIpwnLGgCvAAAKAAMIpwnLGgCvAAAsAAQKgTIAAgoACAhPF104AAkCAAoACAhPF104AAkCAAAA.',Lo='Lorelaei:BAAALAAECgYICgAAAA==.',Lu='Lunaris:BAAALAAECgYIEQAAAA==.',Ma='Maisie:BAABLAAECoEfAAICAAcIzQl7kgBLAQACAAcIzQl7kgBLAQAAAA==.',Me='Megu:BAABLAAECoEjAAITAAgI2BP8GgAoAgATAAgI2BP8GgAoAgAAAA==.Melwin:BAAALAAECggIEgAAAA==.',Mi='Milakur:BAAALAADCggICAAAAA==.Miserychains:BAAALAAECgIIAgABLAAECggIIQABAMkXAA==.',Mo='Monkstern:BAAALAAECgYIAQAAAA==.Mosivu:BAABLAAECoEcAAIUAAcIRxX4FADeAQAUAAcIRxX4FADeAQAAAA==.Mosivurogue:BAAALAADCgYIBgABLAAECgcIHAAUAEcVAA==.Mostima:BAAALAADCgUIBQAAAA==.',Ne='Neekeci:BAAALAAECgYIBgAAAA==.Neheb:BAACLAAFFIEDAAIIAAMI2CNeDQA9AQAIAAMI2CNeDQA9AQAsAAQKgSYAAwgACAjlJRUFAGMDAAgACAjlJRUFAGMDABAABgjVJAAAAAAAAAAA.Nekomi:BAACLAAFFIEFAAMFAAMIgx0ZCAAQAQAFAAMIgx0ZCAAQAQAUAAEITSFFDQBiAAAsAAQKgRYAAwUACAi5JSQCAHMDAAUACAi5JSQCAHMDAAMABggnGUE+AKcBAAEsAAUUAggEAA0AAAAA.Neltharia:BAABLAAECoEZAAMVAAgIZBbQJgDAAQAVAAcIhxXQJgDAAQAWAAMIYBMnKgC2AAAAAA==.',Ni='Nihilon:BAAALAADCggIDgAAAA==.Nipi:BAABLAAECoEXAAMBAAgIbBAddACEAQABAAcIFg8ddACEAQALAAUIvxNrSQAZAQAAAA==.',No='Northy:BAABLAAECoEWAAIRAAcIqAvHTwBLAQARAAcIqAvHTwBLAQAAAA==.',Oc='Oceshamanca:BAAALAADCggIEQABLAAECggICQANAAAAAA==.',Ol='Oldgregg:BAAALAAECggIDwAAAA==.',Ot='Otrodie:BAAALAAECggICAAAAA==.',Pe='Periwinkle:BAAALAAECgYIDgAAAA==.',Ph='Phentem:BAAALAAECgIIAgABLAAECggIGwACAGQdAA==.Phoba:BAAALAAECgYIBgAAAA==.Phäntom:BAABLAAECoEbAAICAAgIZB3KJQB/AgACAAgIZB3KJQB/AgAAAA==.',Pk='Pk:BAAALAADCggICAAAAA==.',Pr='Praetorian:BAAALAADCggICgAAAA==.',['Pí']='Pído:BAAALAADCgYICgABLAAECggIDgANAAAAAA==.',Qo='Qoraani:BAAALAADCgMIBQAAAA==.',Ra='Raikarpal:BAAALAADCgcIDAAAAA==.Ramolus:BAAALAAECggIEwAAAA==.',Re='Reimox:BAACLAAFFIEJAAIFAAMIXBlgCQD2AAAFAAMIXBlgCQD2AAAsAAQKgS0AAwUACAg3JPoDAFgDAAUACAg3JPoDAFgDAAMACAgcBb1qAAsBAAAA.Restaur:BAABLAAECoEkAAMKAAgIBSUfBgAhAwAKAAgIBSUfBgAhAwAXAAQIIA6JggDIAAAAAA==.Restowinkle:BAAALAAECgYIBwABLAAECgYIDgANAAAAAA==.',Ro='Roundwon:BAAALAADCggIDwAAAA==.',Ru='Rustyangel:BAAALAADCgQIBAAAAA==.',Sa='Salikissa:BAABLAAECoEUAAMSAAcILhPPewC7AQASAAcI7BLPewC7AQAYAAQItQ53RwCdAAAAAA==.Sayumi:BAAALAAECgYIBgABLAAFFAIIBAANAAAAAA==.',Sh='Shamix:BAAALAAECgcIEgAAAA==.Shinzo:BAAALAAECgYIBgAAAA==.Shulin:BAAALAADCggIEAAAAA==.',Si='Siath:BAABLAAECoEeAAMZAAgInRlvLABdAgAZAAgInRlvLABdAgAaAAEIthUYOgA7AAAAAA==.Siyumi:BAAALAAFFAIIBAAAAA==.',So='Soofz:BAABLAAECoEZAAMCAAcIohd4YQC2AQACAAcIchd4YQC2AQAPAAUI8BMQYwATAQAAAA==.Sosa:BAAALAADCgEIAQAAAA==.',Sp='Spazze:BAAALAADCgYICAABLAAECgQIBAANAAAAAA==.',Su='Sunday:BAACLAAFFIEFAAMXAAMIHA+TEADmAAAXAAMIHA+TEADmAAAKAAEInAdLTAAzAAAsAAQKgS4AAxcACAg+JEQFAFsDABcACAg+JEQFAFsDAAoAAQimAbUVARYAAAAA.Sundays:BAAALAADCggIDwABLAAFFAMIBQAXABwPAA==.',Sy='Sylvanos:BAAALAADCgUIBQAAAA==.Syryon:BAAALAAECgUIBQAAAA==.',Sz='Szegarda:BAACLAAFFIEFAAIYAAMIzQbhCACnAAAYAAMIzQbhCACnAAAsAAQKgSQAAhgACAhrEfUgAKwBABgACAhrEfUgAKwBAAAA.',Te='Tea:BAACLAAFFIEHAAIXAAMIAR/sCwAYAQAXAAMIAR/sCwAYAQAsAAQKgSYAAhcACAgCJP4FAFQDABcACAgCJP4FAFQDAAAA.',Th='Theredal:BAAALAADCgcIBwAAAA==.',Ti='Tighttoosh:BAACLAAFFIEIAAIbAAMI5hRVDgDtAAAbAAMI5hRVDgDtAAAsAAQKgR4AAhsACAgUHBEcAHECABsACAgUHBEcAHECAAAA.',To='Tortilla:BAAALAAECgYICAABLAAECggIDgANAAAAAA==.',Tr='Trousers:BAAALAAECgQIBAABLAAFFAMIBQAcABkLAA==.',Tu='Tund:BAABLAAECoEeAAQaAAgISSCSCAAYAgAZAAgIrBwsKgBpAgAaAAYIFyCSCAAYAgAdAAMIshfeXADFAAAAAA==.',Ty='Typhus:BAAALAAECgEIAQAAAA==.',Uh='Uhre:BAABLAAECoEhAAMeAAgI7R/qDAC0AgAGAAgIwB0bHAC0AgAeAAgIPx3qDAC0AgAAAA==.',Va='Vadius:BAAALAADCggIDQAAAA==.Varetha:BAAALAAECgcIEQAAAA==.',Vo='Voidling:BAAALAADCgQIBAAAAA==.',Wa='Wasntme:BAAALAAECgcICwAAAA==.',Wh='Whizzunt:BAAALAADCggICAAAAA==.',Wo='Woppersmonk:BAACLAAFFIEFAAIcAAMIGQsVBwDdAAAcAAMIGQsVBwDdAAAsAAQKgSoAAhwACAgPIwEGABsDABwACAgPIwEGABsDAAAA.Worstgamer:BAAALAADCggIEAAAAA==.',Wu='Wubblyjubbly:BAABLAAECoEfAAIBAAgIECCkFAD1AgABAAgIECCkFAD1AgAAAA==.Wubdango:BAABLAAECoEZAAMKAAgI9yJwCQABAwAKAAgI9yJwCQABAwAXAAYIDBD+XQBjAQAAAA==.',Wz='Wz:BAAALAAECggICAAAAA==.',Xe='Xede:BAAALAAECgEIAQAAAA==.',Xi='Xijangjun:BAAALAADCgcICQABLAAECggIGQAVAGQWAA==.',['Æs']='Æstus:BAABLAAECoEXAAIXAAYIsRn+PwDQAQAXAAYIsRn+PwDQAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end