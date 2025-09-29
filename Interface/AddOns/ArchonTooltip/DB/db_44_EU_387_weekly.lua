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
 local lookup = {'Warrior-Fury','DeathKnight-Frost','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Unknown-Unknown','Mage-Frost','Warrior-Protection','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Priest-Shadow','Shaman-Restoration',}; local provider = {region='EU',realm='Templenoir',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Actabator:BAAALAADCggIEAAAAA==.',Al='Altekos:BAAALAADCgYICQAAAA==.Altèkos:BAAALAADCgYICQAAAA==.',Ar='Armohs:BAAALAADCggIDwAAAA==.',Au='Aubry:BAACLAAFFIEJAAIBAAMIRBPZEAD7AAABAAMIRBPZEAD7AAAsAAQKgSwAAgEACAioILkUAO4CAAEACAioILkUAO4CAAAA.',['Aé']='Aérysia:BAAALAADCgcIBwAAAA==.',Bi='Bistouflex:BAAALAAECgUICgAAAA==.',Br='Brost:BAAALAAECgYIBgABLAAECggILgACAEQkAA==.Bryzburn:BAACLAAFFIEHAAIDAAIIeRdNJQCnAAADAAIIeRdNJQCnAAAsAAQKgR0AAgMACAg5IFslALgCAAMACAg5IFslALgCAAAA.',Ch='Chipenette:BAABLAAECoEiAAIEAAcIAhuiEgAHAgAEAAcIAhuiEgAHAgAAAA==.Choutala:BAABLAAECoEgAAMFAAgI1SCnHgCvAgAFAAgIayCnHgCvAgAGAAcIkxmsMADoAQAAAA==.',Co='Cordana:BAAALAAECgYIBgAAAA==.',['Câ']='Câptaincrypt:BAABLAAECoEUAAIDAAYIyRw7ZgDuAQADAAYIyRw7ZgDuAQABLAAFFAQIDwAHAPkiAA==.',Da='Dazzle:BAAALAADCgEIAQABLAAECgYIDwAIAAAAAA==.',Di='Dinendal:BAAALAAECgMIAwAAAA==.Ditscham:BAAALAADCgYIBwAAAA==.Ditsdh:BAAALAADCgcICQAAAA==.Ditspriestt:BAAALAADCgYIBgAAAA==.',Dr='Drilnish:BAAALAAECgYIEgABLAAECggILgACAEQkAA==.',['Dâ']='Dâzzle:BAAALAAECgYIDwAAAA==.',Ev='Evildeadz:BAAALAAECgYIEQAAAA==.',Ey='Eyl:BAAALAADCgcICQAAAA==.',Fi='Fiakacadabra:BAABLAAECoEWAAIJAAYI7xnAKgCzAQAJAAYI7xnAKgCzAQAAAA==.Firminx:BAAALAAECgcIEQABLAAECggILgACAEQkAA==.',Fo='Fodess:BAAALAADCgMIAwAAAA==.',Fr='Frerefiak:BAAALAAECgYICgAAAA==.',Gb='Gbdïtsav:BAAALAAECgUIBQAAAA==.Gbtakap:BAAALAADCgcIDwAAAA==.Gbtakapt:BAAALAAECgIIAgAAAA==.',Ge='Geronidasses:BAAALAAECgcIEwAAAA==.',Go='Golfetine:BAAALAADCgIIAgAAAA==.',Gr='Grosfat:BAABLAAECoEYAAMKAAcIrgswQAA6AQAKAAcIXwswQAA6AQABAAMIigaPtACHAAAAAA==.',Gu='Guenavre:BAAALAADCgcIBwAAAA==.',If='Iffritl:BAAALAADCgcIBwAAAA==.',Im='Imadness:BAACLAAFFIEFAAIHAAIIXggTPACFAAAHAAIIXggTPACFAAAsAAQKgRwAAgcACAgiFbVTAP4BAAcACAgiFbVTAP4BAAAA.',Ja='Jazar:BAACLAAFFIEFAAILAAIILxQ5AgCOAAALAAIILxQ5AgCOAAAsAAQKgTgAAgsACAgiJLwAAEQDAAsACAgiJLwAAEQDAAAA.',Je='Jetlag:BAAALAAECgYICwAAAA==.',Ju='Juiicy:BAAALAAECgcIEAAAAA==.',Ka='Kaasdaal:BAAALAADCggIEwAAAA==.Kaitø:BAABLAAECoEaAAIDAAcI2hxWQgBKAgADAAcI2hxWQgBKAgAAAA==.Kame:BAAALAADCggIGwAAAA==.Karpenter:BAAALAAECgQIBAAAAA==.Kayman:BAAALAADCgIIAQAAAA==.',Ko='Korinth:BAAALAADCgYIBgAAAA==.',Kr='Kronös:BAAALAADCgQIBAAAAA==.',Ku='Kurumî:BAAALAADCgcICAAAAA==.',Ky='Kyrado:BAAALAADCgcIBwAAAA==.',La='Laïntime:BAAALAAECgEIAQAAAA==.',Le='Leonastha:BAAALAAECgcIBgAAAA==.',Li='Light:BAABLAAECoEnAAIMAAgI9SQFAQBYAwAMAAgI9SQFAQBYAwAAAA==.',Lu='Ludwina:BAAALAADCgEIAQAAAA==.',['Lî']='Lînaya:BAACLAAFFIEIAAIDAAII9g/mMACbAAADAAII9g/mMACbAAAsAAQKgTcAAgMACAgiIfUfANICAAMACAgiIfUfANICAAAA.',['Lø']='Løkii:BAAALAAECggIDwAAAA==.',Ma='Maillos:BAABLAAECoEbAAINAAcIWxshEABAAgANAAcIWxshEABAAgAAAA==.Massaî:BAABLAAECoEaAAIFAAgI+hKVaACxAQAFAAgI+hKVaACxAQAAAA==.Mateek:BAAALAADCgYICwAAAA==.',Mu='Mutzhag:BAABLAAECoEaAAIKAAYIdxvXJgDMAQAKAAYIdxvXJgDMAQAAAA==.',['Mé']='Mélä:BAAALAAECgcICAAAAA==.',Ne='Nehaya:BAAALAADCggICAAAAA==.Nem:BAAALAAECgMIAgAAAA==.',Ni='Niisha:BAAALAADCggIKwAAAA==.',No='Nordens:BAAALAAECgUIBQAAAA==.',['Nï']='Nïmrïf:BAABLAAECoEuAAMCAAgIRCT5DQAsAwACAAgIRCT5DQAsAwAOAAYIvB6gFQDDAQAAAA==.',Oc='Octogone:BAAALAADCgIIAgAAAA==.',Or='Orchidia:BAABLAAECoEnAAIPAAgIORTQFgDjAQAPAAgIORTQFgDjAQAAAA==.Orchogan:BAAALAADCgYIBAAAAA==.',Pa='Palome:BAAALAAECgYIDwAAAA==.Palpatinx:BAAALAADCgYICAAAAA==.Palyndrôme:BAAALAADCggIDwAAAA==.Paløøpine:BAAALAADCgcIBwAAAA==.Patteenfer:BAAALAADCgMICwAAAA==.',Pe='Peacebloom:BAAALAAFFAMIBwABLAAFFAYIGgAQAEwiAQ==.',Pi='Piflya:BAAALAADCgYIBwABLAADCggIEAAIAAAAAA==.',Pn='Pneumonie:BAAALAAECgMIAwAAAA==.',Pr='Prozzax:BAAALAAECgQICgAAAA==.',Ra='Rambø:BAAALAADCggIFwAAAA==.Razmoø:BAAALAAECgIIAgAAAA==.',Re='Rekyem:BAAALAAECgYIEwAAAA==.Renoir:BAAALAAFFAEIAQAAAA==.',Sa='Samaels:BAABLAAECoEgAAICAAgIECGdGgDpAgACAAgIECGdGgDpAgAAAA==.',Sc='Sciel:BAAALAAECgYIBgAAAA==.',Se='Sekmet:BAAALAADCggIGQAAAA==.Seïdrin:BAAALAADCgcIDAABLAAECgcIEwAIAAAAAA==.',Sh='Shadøwcat:BAAALAAECgUICwAAAA==.Shakalouxx:BAAALAADCgcIBwAAAA==.Shimi:BAAALAAECgYIDAAAAA==.Shimiya:BAAALAAECgYICwAAAA==.Shivan:BAAALAAECgYICgAAAA==.',Si='Sidenn:BAAALAAECgYICwAAAA==.Sidënn:BAAALAADCgYIBgAAAA==.',Sk='Skipnøt:BAAALAADCggIDgAAAA==.',Sl='Släy:BAAALAAECgIIAgAAAA==.',Su='Sunrain:BAAALAAECgIIAgAAAA==.',Sw='Swagzer:BAAALAADCgYIBwAAAA==.',Sy='Sylvianus:BAAALAADCggICQAAAA==.Symphony:BAAALAADCggIEAAAAA==.',['Sç']='Sçky:BAAALAADCgUIBQAAAA==.',Ta='Targamor:BAAALAADCgcIFAAAAA==.Taroa:BAAALAAECgMIAwAAAA==.',Th='Thanafrogs:BAAALAAECgYICQABLAAFFAIICgARAG0NAA==.Thanapal:BAAALAAECgQICQABLAAFFAIICgARAG0NAA==.Thanapriest:BAACLAAFFIEKAAMRAAIIbQ3mGQCMAAARAAIIbQ3mGQCMAAAQAAIIygWiLACAAAAsAAQKgVYAAxEACAhuHJkYAJECABEACAhuHJkYAJECABAABwjnGbwuAAgCAAAA.Thanarogue:BAAALAAECgYICgABLAAFFAIICgARAG0NAA==.Thanwar:BAAALAADCgcIBwABLAAFFAIICgARAG0NAA==.Thereclis:BAAALAADCgcIBwAAAA==.Thortran:BAABLAAECoEaAAIDAAgI9gZArQBnAQADAAgI9gZArQBnAQAAAA==.',Ti='Tiki:BAAALAADCgEIAQAAAA==.',Ty='Tyranie:BAAALAAECgIIAwAAAA==.',['Tî']='Tîamat:BAAALAADCgYICgAAAA==.',Ur='Ursulla:BAAALAADCggICAAAAA==.',Vi='Viandaxx:BAAALAAECgYIDAAAAA==.Violet:BAAALAADCggIDwAAAA==.',Vo='Voluptea:BAAALAADCgcIBwABLAAECggIJwAPADkUAA==.',Wa='Wanhedâ:BAAALAAECgcIEwAAAA==.Wasabee:BAAALAAECgYIEwAAAA==.',Wu='Wutköder:BAACLAAFFIENAAISAAYITRaUAgD6AQASAAYITRaUAgD6AQAsAAQKgSQAAhIACAgpJh0BAGsDABIACAgpJh0BAGsDAAAA.',Xe='Xeltaë:BAAALAAECgYIBgABLAAECgYIDwAIAAAAAA==.',['Yø']='Yøgø:BAAALAAECgMIAwAAAA==.',Ze='Zerockx:BAAALAAECgQIBAAAAA==.',['Îr']='Îrina:BAAALAAECgYIBgAAAA==.',['Ðo']='Ðora:BAAALAADCgcIFAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end