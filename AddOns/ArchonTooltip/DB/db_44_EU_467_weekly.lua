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
 local lookup = {'Unknown-Unknown','Priest-Holy','Priest-Discipline','Paladin-Holy','Priest-Shadow',}; local provider = {region='EU',realm='Terrordar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aalfänger:BAAALAADCggICAAAAA==.',Ai='Aior:BAAALAADCgcIEwAAAA==.',Ak='Akeno:BAAALAAECgYICAAAAA==.',Al='Aldun:BAAALAADCggICAAAAA==.Algaan:BAAALAADCgcIBwAAAA==.Allinone:BAAALAAECgYIBgAAAA==.Allucanheal:BAAALAADCggICAAAAA==.Alphenia:BAAALAAECgIIAgAAAA==.',Ar='Arinya:BAAALAAECgMIBwAAAA==.Arkana:BAAALAAECgMIBAAAAA==.',As='Asanyeo:BAAALAADCggIDgAAAA==.Asmodiná:BAAALAAECgUIBQAAAA==.Asmodäus:BAAALAADCggIFgAAAA==.',Be='Bellafonte:BAAALAADCggIDgAAAA==.Benhîndert:BAAALAAECgMIBgAAAA==.',Bo='Bootcamp:BAAALAAECgEIAQAAAA==.',Ca='Calikessy:BAAALAADCggICAAAAA==.',Ce='Celtics:BAAALAAECgMIBQAAAA==.',Co='Coogan:BAAALAADCggIEAAAAA==.',Cr='Croiffin:BAAALAADCggIEgAAAA==.',Cy='Cyria:BAAALAADCggIDgAAAA==.',Ea='Earthchan:BAAALAADCggIDAAAAA==.',Em='Emlaiel:BAAALAADCgcIEAAAAA==.',Ex='Exundari:BAAALAADCggICAABLAAECgMIBwABAAAAAA==.',Fe='Felizitâs:BAAALAADCgcIBwAAAA==.Fenril:BAAALAAECgEIAQAAAA==.',Go='Golddiggee:BAAALAAECgIIAwAAAA==.Golgatha:BAAALAAECgMIBgAAAA==.',Gr='Grello:BAAALAAECgMIBgAAAA==.',Ha='Hackepater:BAAALAADCgEIAQAAAA==.Haru:BAAALAADCgEIAQAAAA==.',Hy='Hyacia:BAAALAAECgIIAwAAAA==.',['Hì']='Hìnata:BAAALAAECgYIBwAAAA==.',Im='Immortalem:BAABLAAECoEUAAMCAAgIBB7JBgDOAgACAAgIBB7JBgDOAgADAAYIbRQmBgCdAQAAAA==.',In='Inanisumbra:BAAALAAECgMIBwAAAA==.',Je='Jessy:BAAALAAECgcIDgAAAA==.',Ji='Jimbar:BAAALAAECgIIAgAAAA==.',Ka='Kainazzo:BAAALAAECgMIBwAAAA==.Kalthas:BAAALAADCgYIBgABLAAECggIEQABAAAAAA==.Karaswa:BAAALAAECgMIBwAAAA==.Karleeh:BAAALAAECgYIDgAAAA==.Kashmirinche:BAAALAAECgcIDwAAAA==.',Ke='Kellerkolle:BAAALAADCgcIBwAAAA==.',Kh='Khabaal:BAAALAADCggICAAAAA==.',La='Laluna:BAAALAADCgYIBgAAAA==.',Lu='Lucy:BAAALAADCgMIAwAAAA==.Lupercia:BAAALAADCggICAAAAA==.',Ma='Mahrus:BAAALAAECgMIBwAAAA==.Maikel:BAAALAADCgcIBwAAAA==.Mangis:BAAALAADCgUIBQAAAA==.Mantorock:BAAALAAECgIIBAAAAA==.',Me='Medinagreen:BAAALAAECggICAAAAA==.Melthaz:BAAALAAECgcIDwAAAA==.',Mi='Milany:BAAALAADCggICAAAAA==.',Mo='Mogy:BAAALAAECgcICAAAAA==.Monkyponky:BAAALAADCggICAABLAAECgMIBwABAAAAAA==.',Na='Nakarox:BAAALAADCgcICgAAAA==.Natdal:BAAALAADCgcIBwAAAA==.Nawdal:BAAALAADCggICwAAAA==.',Ne='Nerzul:BAAALAAECggIEQAAAA==.',Ni='Nibbl:BAAALAAECgMIAwAAAA==.',Pe='Perridur:BAAALAAECgMIBwAAAA==.',Pl='Plexia:BAAALAAECggICwAAAA==.',Py='Pythagorazz:BAAALAAECgQIBwAAAA==.',['Pê']='Pêrsês:BAAALAAECggIBgAAAA==.',['Pü']='Püppi:BAAALAAECgcIEAAAAA==.',Qu='Quelte:BAAALAAECgMIAwAAAA==.',Ra='Rainaa:BAAALAAECgMIBwAAAA==.Rapdepp:BAAALAAECgYIDQAAAA==.',Re='Renfield:BAAALAAFFAIIAgAAAA==.Rewak:BAAALAADCggICAAAAA==.',Ro='Robn:BAAALAAECgMIBwAAAA==.',Sa='Sadisticon:BAAALAADCgcIDQAAAA==.',Se='Serale:BAABLAAECoEUAAIEAAgI6w8EDQAKAgAEAAgI6w8EDQAKAgAAAA==.Sews:BAAALAAECggICAAAAA==.',Sh='Shaderon:BAAALAADCggIDwAAAA==.Shira:BAAALAAECgIIAgABLAAECggIFAAEAOsPAA==.',Sn='Snylck:BAAALAADCggICAAAAA==.',St='Strul:BAAALAADCggICAAAAA==.',Su='Suedi:BAAALAAECgEIAQAAAA==.',['Sí']='Sínthóras:BAAALAAECgMIBwAAAA==.',Ta='Tarlas:BAAALAAECgYIDgAAAA==.Tayun:BAAALAADCgcIBwAAAA==.',Th='Thalienne:BAAALAADCgYICAAAAA==.Thaloria:BAAALAAECgMIAwAAAA==.Thelea:BAAALAAECgEIAQAAAA==.Theleâs:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.',Tr='Trolladin:BAAALAADCgcIBwAAAA==.',Tu='Tungsten:BAAALAADCgYIBwAAAA==.',['Té']='Téodory:BAAALAAECggIBwAAAA==.',Va='Valanthe:BAAALAADCggICwAAAA==.',Vi='Viljar:BAABLAAECoEXAAIFAAgISiVBAQBtAwAFAAgISiVBAQBtAwABLAADCggICAABAAAAAA==.Vipa:BAAALAAECgcIBwAAAA==.Vivi:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',['Vî']='Vîollett:BAAALAADCggICAAAAA==.',Xa='Xanthà:BAAALAAECgcIDQAAAA==.',Xe='Xelos:BAAALAAECgMIBwAAAA==.',Zi='Zifrel:BAAALAADCggICgAAAA==.',Zr='Zroolek:BAAALAADCgEIAQAAAA==.',['Áa']='Áatrox:BAAALAADCgEIAQAAAA==.',['Èl']='Èlede:BAAALAADCgcIBwABLAAECgMIBwABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end