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
 local lookup = {'Unknown-Unknown','Warrior-Protection',}; local provider = {region='EU',realm='Theradras',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ai='Aither:BAAALAADCgYIBgAAAA==.',Al='Allaniá:BAAALAAECggIEwAAAA==.',An='Anvihunt:BAAALAADCgYIBgAAAA==.Anvisio:BAAALAAECgYICwAAAA==.',Au='Auray:BAAALAADCgIIAgAAAA==.',Az='Azorka:BAAALAAECgYICAAAAA==.Azâr:BAAALAADCggIDAAAAA==.',Ba='Baltazzar:BAAALAAECggICAAAAA==.',Be='Beshlar:BAAALAADCggIEAABLAADCggIFgABAAAAAA==.',Bi='Bierbär:BAAALAAECgYICQAAAA==.',Ca='Caramali:BAAALAAECggICAAAAA==.',Ch='Chaac:BAAALAADCggIFgAAAA==.',Co='Coryax:BAAALAADCggICAAAAA==.',Da='Dalento:BAAALAADCgEIAgAAAA==.Daleria:BAAALAAECgcICgAAAA==.Danilea:BAAALAADCgYIBgAAAA==.Darkgroll:BAAALAADCgcIAgAAAA==.',De='Delo:BAAALAADCggICAAAAA==.',Dr='Dragonskin:BAAALAADCgYIBgAAAA==.',Ea='Easypeazy:BAAALAAECgIIAgAAAA==.',Ec='Echidna:BAAALAAECgYIBwABLAAECggICAABAAAAAA==.',El='Elonie:BAAALAADCggIFAAAAA==.',Es='Esdeath:BAAALAAECgMIAwAAAA==.',Ga='Garnet:BAAALAAECgEIAQABLAAECggICAABAAAAAA==.',Gr='Grollbull:BAAALAADCggIDgAAAA==.Grollhuf:BAAALAADCggIEQAAAA==.',['Gê']='Gêxx:BAABLAAECoEXAAICAAcI4x3JCgAQAgACAAcI4x3JCgAQAgAAAA==.',['Gó']='Górdás:BAAALAADCgIIAgAAAA==.',Ha='Haalthemar:BAAALAAECgYIBwAAAA==.',He='Healnogo:BAAALAADCgcICwAAAA==.Heavylight:BAAALAAECgEIAQAAAA==.Hexí:BAAALAAECgYIDAAAAA==.',Ih='Ihuntyou:BAAALAAECgEIAQABLAAECggICAABAAAAAA==.',Ik='Ikarr:BAAALAADCggIDwAAAA==.',In='Invidia:BAAALAADCgcIFAAAAA==.',Ir='Iron:BAAALAADCgcICgAAAA==.',Iv='Ivrea:BAAALAAECgMIBQAAAA==.',['Jó']='Jósi:BAAALAAECgQICwAAAA==.',Ke='Kelgori:BAAALAAECgIIAgAAAA==.Keniy:BAAALAADCggIEwAAAA==.',Ki='Kirikaze:BAAALAAECgQIBgAAAA==.',Ko='Koksí:BAAALAAECgIIAgABLAAECggIEwABAAAAAA==.Kommakla:BAAALAADCggICAAAAA==.',Kr='Kratok:BAAALAADCgcIBwAAAA==.',Ku='Kuljin:BAAALAADCggIAQAAAA==.',Ky='Kya:BAAALAAECgcIDgAAAA==.',Le='Lenfira:BAAALAAECgMIAwAAAA==.',Li='Likandra:BAAALAADCgcIBwAAAA==.',Ly='Lyphilia:BAAALAADCgYIBgAAAA==.Lyzriel:BAAALAADCgUIBQAAAA==.',Ma='Mae:BAAALAADCgQIBAAAAA==.Mariellche:BAAALAAECgMIBQAAAA==.',Me='Meene:BAAALAADCgcICAAAAA==.Melfoy:BAAALAADCggICAAAAA==.',Mi='Milu:BAAALAAECgYIBgAAAA==.Mino:BAAALAAECgEIAQAAAA==.Mirio:BAAALAADCgcIAQAAAA==.Mizi:BAAALAADCggIFgAAAA==.',Mo='Monya:BAAALAADCgUIBQAAAA==.Mosho:BAAALAADCggIFgAAAA==.',Mu='Muhmähn:BAAALAAECgMIBAAAAA==.',Na='Nazuna:BAAALAAECgMIBgAAAA==.',Ne='Necrohunt:BAAALAADCggIDgAAAA==.Necroticz:BAAALAADCgYICQAAAA==.Necrowar:BAAALAADCgUIBQAAAA==.',Ny='Nyarlko:BAAALAAECggICAAAAA==.',['Nî']='Nîorith:BAAALAAECgYICAAAAA==.',Pl='Plux:BAAALAAECgYICAAAAA==.',Po='Pondo:BAAALAADCgcIDQAAAA==.',Qx='Qxs:BAAALAAECgMIBgAAAA==.',Ra='Ragekitty:BAAALAADCggICQAAAA==.',Re='Reissdorf:BAAALAAECgMIBQAAAA==.Retribull:BAAALAAECgQICQAAAA==.',Ro='Rokramas:BAAALAADCggICAAAAA==.',Ry='Ryuc:BAAALAADCgUIBQAAAA==.',Sa='Satarius:BAAALAADCgIIAgAAAA==.',Se='Seeboo:BAAALAAECgEIAgAAAA==.',Sh='Shamanistic:BAAALAAECgEIAQAAAA==.',Sl='Slashspit:BAAALAADCgQIBQAAAA==.',St='Sträter:BAAALAADCggIFQAAAA==.',Su='Susel:BAAALAADCggICAAAAA==.',['Sé']='Séphirôth:BAAALAADCggICAAAAA==.',Ta='Taron:BAAALAADCgYIBgAAAA==.',Th='Thaliatrix:BAAALAADCgIIAQAAAA==.Thurmal:BAAALAADCggIDwAAAA==.',Ti='Tindarella:BAAALAADCggICAAAAA==.',Tr='Trîlux:BAAALAAECgYICAAAAA==.',Ug='Ugruzz:BAAALAAECgMIBQAAAA==.',Uw='Uwabaki:BAAALAADCgcIBwAAAA==.',Va='Vanshu:BAAALAADCgYIBgAAAA==.',Vy='Vyranos:BAAALAAECgMIBgAAAA==.',Wo='Wong:BAAALAADCggIFgAAAA==.',Xa='Xavanar:BAAALAADCggICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end