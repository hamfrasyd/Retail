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
 local lookup = {'Monk-Mistweaver','Evoker-Preservation','Evoker-Devastation','Unknown-Unknown','Mage-Frost','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Druid-Guardian','Druid-Feral','Warrior-Fury',}; local provider = {region='EU',realm='Emeriss',name='EU',type='weekly',zone=44,date='2025-09-06',data={Af='Afleyushka:BAABLAAECoEaAAIBAAgIhSMaAwD/AgABAAgIhSMaAwD/AgAAAA==.',Ai='Airuna:BAAALAADCgYIBgAAAA==.',Al='Aleksi:BAAALAADCggIEAAAAA==.Alfeya:BAACLAAFFIESAAICAAYI6CUOAACsAgACAAYI6CUOAACsAgAsAAQKgRkAAwIACAhLJhkAAIUDAAIACAhLJhkAAIUDAAMAAwj+Ebw2AKsAAAAA.Allayan:BAAALAADCggIDAAAAA==.Alvico:BAAALAADCgEIAQAAAA==.',An='Angelight:BAAALAAECgYIDwAAAA==.Anu:BAAALAAECggICwABLAAECgYIBwAEAAAAAA==.',As='Ashwing:BAAALAAECgYIBgAAAA==.',Bi='Bixtonim:BAAALAADCgcIBwAAAA==.',Bl='Bloodkael:BAAALAADCggICAAAAA==.Bläze:BAAALAADCgcIBwAAAA==.',Bo='Booghy:BAAALAAECgYICAAAAA==.Bourge:BAAALAAECgYIBgAAAA==.Bouvet:BAAALAAECgMIAwABLAAECgcIFgAFAAISAA==.',Br='Brotemaikata:BAAALAAECgYICAAAAA==.Brummie:BAAALAAECgMIAwAAAA==.',Bu='Bunkhy:BAAALAADCgUIBQAAAA==.',Ca='Cantbstopped:BAAALAADCgYIBgAAAA==.',Ch='Chazyb:BAAALAAECgMIBAAAAA==.',Ci='Cilera:BAAALAAECgcIEQAAAA==.',Co='Cottillion:BAAALAAECgMIBQAAAA==.',Cr='Crivian:BAAALAAECggICAAAAA==.Crow:BAAALAAECgUIBQAAAA==.',Da='Dairblade:BAAALAAECgUIBgAAAA==.Daircane:BAAALAAECgcIEQAAAA==.Darthos:BAAALAAECgQIBAAAAA==.Dawnseeker:BAAALAADCgcICAAAAA==.',De='Derpsi:BAAALAAECgYIDwAAAA==.',Di='Diaolos:BAAALAAECgcIDwAAAA==.Dirtyegg:BAAALAADCgMIAwAAAA==.Disrupt:BAABLAAECoEXAAIGAAcI3RSEEACwAQAGAAcI3RSEEACwAQAAAA==.',Dn='Dny:BAAALAADCgUIBQAAAA==.',Dr='Dragosia:BAAALAADCggICwAAAA==.Drgndeeznutz:BAAALAAECggIEAAAAA==.Druidro:BAAALAAECggIEgAAAA==.',El='Elathaï:BAABLAAECoEXAAMHAAcIzSE7CgCwAgAHAAcIzSE7CgCwAgAIAAMIjxLlHAC4AAAAAA==.Elenera:BAAALAADCgcIEAAAAA==.Elizer:BAAALAAECgMIAwAAAA==.',Em='Emby:BAAALAADCgcIBwAAAA==.Empoly:BAAALAAECgYIBgAAAA==.',Et='Etlar:BAAALAAECgEIAQAAAA==.',Fi='Fibrex:BAAALAADCgcICwAAAA==.',Fj='Fjollegoej:BAAALAADCgcIDAAAAA==.',Fo='Form:BAABLAAECoEYAAIJAAcIDBkTGwD5AQAJAAcIDBkTGwD5AQAAAA==.Fortitude:BAAALAAECgIIAgAAAA==.',Ge='Genjistyle:BAAALAADCgcICQAAAA==.Getdunked:BAAALAAECgcIDQAAAA==.',Gi='Gimin:BAAALAAECgQIBAAAAA==.',Gl='Gladiss:BAAALAAECggIDwAAAA==.Glorificus:BAAALAADCggICAAAAA==.Gloww:BAAALAAECgYIDAAAAA==.',Gr='Gragas:BAAALAADCgcIBwAAAA==.Gravìtý:BAAALAADCgMIAwAAAA==.Greta:BAAALAADCgcIBwAAAA==.Grimoire:BAAALAAECgQIBAAAAA==.',Gu='Gullmnr:BAAALAADCgYIBgAAAA==.',Ha='Harishhjjaja:BAAALAAECgYIDQAAAA==.',He='Helland:BAABLAAECoEWAAIFAAcIAhJ/HgCfAQAFAAcIAhJ/HgCfAQAAAA==.',Hu='Hurfan:BAAALAAECgYICwAAAA==.',Ib='Ibwa:BAABLAAECoEUAAMKAAcIpR1oDQAyAgAKAAYIQh9oDQAyAgALAAII2BZkcwCGAAAAAA==.',Ig='Igrith:BAAALAAECggIBgAAAA==.',Ja='Jana:BAAALAAECgIIAgAAAA==.Jarle:BAAALAADCgcIFwAAAA==.',Ka='Kali:BAAALAADCgcIBwAAAA==.Kawnywl:BAAALAAECgMIAgAAAA==.',Ki='Kilkov:BAAALAADCgMIAwAAAA==.',Ku='Kurnela:BAAALAADCggICQAAAA==.',Le='Leewanglong:BAAALAADCgcICAAAAA==.',Li='Liami:BAAALAAECgYIDAAAAA==.Lizard:BAAALAAECgMIBQAAAA==.',Lo='Longtooth:BAABLAAECoEXAAIMAAcIRBntIAAnAgAMAAcIRBntIAAnAgAAAA==.',Lu='Ludogore:BAAALAAECgYIDAAAAA==.Lunarkitty:BAAALAAECgIIAgAAAA==.',Ly='Lylian:BAAALAAECgYIBgABLAAECgcIFwAHAM0hAA==.',Ma='Mageya:BAAALAAECggIDQAAAA==.Magneza:BAAALAAECgIIAgAAAA==.Manja:BAAALAADCggIFgAAAA==.Marthen:BAAALAADCgcIBwAAAA==.',Me='Mea:BAAALAAECgUIBgAAAA==.Megashark:BAAALAAECgYIEQAAAA==.',Mi='Midias:BAAALAAECgIIAgAAAA==.Mini:BAAALAAECgcIDgAAAA==.',Mo='Moirai:BAAALAAECgIIAwAAAA==.',Na='Nazlo:BAAALAADCgQIBAAAAA==.',Ne='Negara:BAAALAAECgYICQAAAA==.',Ni='Nickboi:BAAALAAECgUIBQAAAA==.Nightlovel:BAAALAAECgYIBgAAAA==.Niuel:BAAALAADCggIFgAAAA==.',Nn='Nnexar:BAAALAAECgYIDAAAAA==.',Ns='Nsiya:BAAALAAECgMIBQAAAA==.',Ny='Nycore:BAAALAAECgIIAgAAAA==.',['Nà']='Nàmi:BAAALAADCggICAAAAA==.',['Ná']='Náttfarinn:BAAALAAECgYIDgAAAA==.',Od='Odilolly:BAAALAAECgMIAwAAAA==.',Pa='Pavkata:BAAALAAECgUIBwAAAA==.',Pe='Penguindrumr:BAAALAADCgcICgAAAA==.Percocets:BAAALAADCggICAAAAA==.Perun:BAAALAAECgYIDwAAAA==.',Pf='Pff:BAAALAAECgYIDAAAAA==.',Po='Pop:BAAALAADCgYICQAAAA==.',Pr='Primall:BAAALAADCggICAAAAA==.',Pu='Pusheka:BAAALAADCggIFgAAAA==.',Ra='Ratzy:BAAALAAECgYICwAAAA==.',Re='Rebuke:BAAALAAECggICQAAAA==.Regelee:BAAALAAECgYIBgAAAA==.Restindemon:BAAALAAECgEIAQAAAA==.Rev:BAAALAAECgYICAAAAA==.Revzy:BAAALAAECgMIAwAAAA==.',Sc='Scarab:BAAALAADCgYIBgAAAA==.',Se='Sengar:BAAALAAECgMIAwAAAA==.Sephirae:BAAALAAECgcIDgAAAA==.',Sh='Shackle:BAAALAAECgYICAAAAA==.Shadowpray:BAAALAAECgYICgAAAA==.Sharn:BAAALAAECgMIAwAAAA==.Sherman:BAAALAADCgYIBgAAAA==.Shermon:BAAALAAECgYICAAAAA==.',Si='Silvdruid:BAABLAAECoEVAAMNAAYIMSQfAwBrAgANAAYIMSQfAwBrAgAOAAYIOgw7FwBJAQAAAA==.',Sl='Slavery:BAAALAADCggIDgAAAA==.',St='Sta:BAAALAADCggICAAAAA==.Stoney:BAAALAADCggICAAAAA==.',Sw='Swany:BAAALAADCgEIAQAAAA==.',Sy='Sylena:BAAALAAECgMIBQAAAA==.Syragix:BAAALAADCggICAAAAA==.',Th='Theshadowman:BAAALAADCggICAAAAA==.Thrunite:BAAALAAECgEIAQAAAA==.',Tr='Trapt:BAAALAADCggIDgABLAAECgMIAwAEAAAAAA==.Trolilufi:BAAALAAECgYICAAAAA==.Trollwizard:BAAALAADCgIIAgAAAA==.',Ty='Typhoeus:BAAALAAECgYICQAAAA==.',Ug='Ugrahk:BAABLAAECoEOAAIPAAgIHhd/GQBQAgAPAAgIHhd/GQBQAgAAAA==.',Uw='Uwufleya:BAAALAAECgYIBgAAAA==.',Va='Valkhor:BAAALAAECgYICwAAAA==.',Vi='Violancebg:BAAALAADCgcIBwAAAA==.',Wa='Wafleya:BAAALAAECgcICwAAAA==.',Wh='Whelp:BAAALAAECgcIBQAAAA==.Whitefoot:BAAALAAECgIIAwAAAA==.',Wo='Wolfclaw:BAAALAAECggIEAAAAA==.Wolfix:BAAALAAECgIIAgABLAAECggIEAAEAAAAAA==.',Yo='Yo:BAAALAADCggICAAAAA==.',Za='Zagor:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end