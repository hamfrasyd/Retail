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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Druid-Feral','Shaman-Elemental',}; local provider = {region='EU',realm='Dethecus',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abêndstern:BAAALAAECgYICAAAAA==.',Ad='Adremos:BAAALAAECgYIDAAAAA==.',Ah='Ahmshere:BAAALAAECgMIAwAAAA==.',Ai='Aiakan:BAAALAADCgcICQAAAA==.Aishá:BAAALAADCgUICgAAAA==.',Al='Alezar:BAAALAADCgcICAAAAA==.',An='Analijah:BAAALAAECgIIAgAAAA==.',Ar='Arathon:BAAALAADCgYIBgAAAA==.Arthoríos:BAAALAADCggICAAAAA==.',As='Assamausi:BAAALAADCgEIAQAAAA==.Asterin:BAAALAADCggICAAAAA==.',Av='Avathar:BAAALAAECgMIAwAAAA==.',Ba='Baass:BAAALAAECgYIDQAAAA==.Bananabee:BAAALAAECggIEAAAAA==.',Bl='Blind:BAAALAAECgEIAQAAAA==.Bloodsportt:BAAALAAECgEIAQAAAA==.Bloodveil:BAAALAADCggIDwAAAA==.Bláckhórn:BAAALAADCgcIBwAAAA==.',Bo='Bonzu:BAAALAAECgMIBQAAAA==.Borsti:BAAALAADCggICAAAAA==.Bowsa:BAAALAADCgcIBwAAAA==.',Br='Brontos:BAAALAAECgcIDQAAAA==.',Bt='Btx:BAAALAADCgIIAgAAAA==.',Bu='Bulsay:BAAALAAECgYIBwABLAAFFAEIAQABAAAAAA==.',Ca='Camyra:BAAALAADCgcIBwAAAA==.Caramôn:BAAALAADCggICgAAAA==.Cathya:BAAALAAECgYICwAAAA==.',Co='Conek:BAAALAADCgIIAgAAAA==.Contess:BAAALAADCgEIAQAAAA==.',Cr='Crafclown:BAAALAAECgEIAQAAAA==.Crayson:BAAALAADCgMIAwAAAA==.',De='Demontank:BAAALAAECgQICAAAAA==.',Di='Diesermonk:BAAALAAECgMIBgABLAAECgYICQABAAAAAA==.',Dr='Drainheal:BAACLAAFFIEFAAICAAMISB4zAQAuAQACAAMISB4zAQAuAQAsAAQKgRcAAwIACAgfILUDAN8CAAIACAgfILUDAN8CAAMAAQjyBeQfADcAAAAA.Drzwikl:BAAALAADCgcIBwAAAA==.Dráz:BAAALAAECgIIAgAAAA==.Drúidika:BAAALAADCggIAQAAAA==.',Dt='Dtm:BAAALAAECgIIAgAAAA==.',Du='Durungar:BAAALAAECgYIBgABLAAFFAEIAQABAAAAAA==.',['Dä']='Däimonia:BAAALAAECgYIDQAAAA==.',Fe='Femme:BAAALAADCgcIBwAAAA==.Fern:BAAALAAECgcIDwAAAA==.',Fk='Fk:BAAALAADCggICAAAAA==.',Fr='Frozenwrath:BAAALAAECgcIEgABLAAFFAIIAgABAAAAAA==.',Ga='Gaffel:BAAALAADCggICAAAAA==.Galfor:BAAALAAECgcIBwABLAAFFAEIAQABAAAAAA==.Gambino:BAAALAAECgEIAQAAAA==.',Go='Goemon:BAAALAAECgMICQAAAA==.Gorschar:BAAALAAFFAEIAQAAAA==.',Gr='Grünklein:BAAALAAECgYICQAAAA==.',Gu='Guldano:BAAALAAECgUIBQABLAAFFAEIAQABAAAAAA==.',Gw='Gwizdo:BAAALAAECgMIAwAAAA==.',Ha='Haaldarin:BAAALAADCgcIBwAAAA==.',He='Helldorado:BAAALAAECgcIDQAAAA==.',Il='Illuena:BAAALAADCgYIBgAAAA==.Illyasviell:BAAALAADCggICAAAAA==.',Ip='Ipheion:BAAALAADCgcIBwAAAA==.',Iq='Iqpl:BAAALAAECgYIDAAAAA==.',Is='Isakara:BAAALAAECgMIBQAAAA==.Ishah:BAABLAAECoEXAAIEAAgIjiKQDgB5AgAEAAgIjiKQDgB5AgAAAA==.',Ja='Jabjapriest:BAAALAAECgcIDgAAAA==.Jagakan:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.',Ka='Kaeldrin:BAAALAAECgUIAgAAAA==.Kariria:BAAALAADCgcIBwAAAA==.Kavarill:BAAALAADCgYIBgAAAA==.Kazzhul:BAAALAAECgEIAQAAAA==.',Ke='Kelthazad:BAAALAADCgEIAQAAAA==.Kernighan:BAAALAAECgYIEAAAAA==.',Kh='Khazerak:BAAALAAECggIEQAAAA==.Khazrak:BAAALAAECgUIBQABLAAECggIEQABAAAAAA==.',Ki='Kindermilch:BAAALAAECgYICwAAAA==.Kirchenrolf:BAAALAAECgMIAwAAAA==.',Kr='Krem:BAAALAADCggIEgAAAA==.Krâksham:BAAALAAECgUIBQAAAA==.',Li='Lilliana:BAAALAAECgYIBgAAAA==.',Lo='Lorani:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Ly='Lyínn:BAAALAADCgcIBwAAAA==.',['Lâ']='Lâphira:BAAALAADCgEIAQAAAA==.',['Lí']='Línch:BAAALAAECgYIDAAAAA==.',Ma='Magnador:BAAALAAECgYICQAAAA==.',Me='Megumin:BAAALAAECgYICQAAAA==.Mekaar:BAAALAADCggICAAAAA==.Mesfer:BAAALAADCgcIBwAAAA==.',Mi='Miishuna:BAAALAAECgYICwAAAA==.Misantropie:BAAALAADCgUIBQAAAA==.',Mu='Mupf:BAAALAAECgMIAwAAAA==.',['Mê']='Mêngiz:BAAALAAECggIEwAAAA==.',Na='Naera:BAAALAADCggIDgAAAA==.Nanî:BAAALAADCggIDgAAAA==.Navori:BAAALAAECgUIBwAAAA==.',Ne='Nedya:BAAALAADCgcIBwAAAA==.Nephilos:BAAALAADCgQIBAAAAA==.Nerodon:BAAALAAECgUIAQAAAA==.Nerolan:BAAALAADCggIEAABLAAFFAIIAgABAAAAAA==.Nevasjin:BAAALAADCggICAAAAA==.',['Nï']='Nïx:BAAALAADCgIIAgAAAA==.',Ok='Okinan:BAAALAAECgUIBQABLAAFFAEIAQABAAAAAA==.',Pi='Pirulita:BAAALAAECgEIAQAAAA==.',Pu='Punjí:BAAALAAECgcIDAAAAA==.',['Pü']='Püpyy:BAAALAAECgMIBQAAAA==.',Ri='Rivena:BAAALAADCgcIBwAAAA==.',Ru='Rujin:BAAALAAECgMIBQAAAA==.',Sa='Sandrik:BAAALAAECgMIBAAAAA==.',Sh='Shaikun:BAAALAADCggICgAAAA==.Shalia:BAAALAADCgYICwAAAA==.Shayhulud:BAAALAADCggICAAAAA==.Shurugawarry:BAAALAADCgUIBQAAAA==.Shánk:BAAALAAECgcIEAAAAA==.',Sk='Skillumina:BAAALAAECgYICAAAAA==.',Sl='Slingshot:BAAALAAFFAIIAgAAAA==.',Sm='Smauganon:BAAALAADCgcIBwABLAAFFAEIAQABAAAAAA==.',So='Soulslayer:BAAALAAFFAIIAgAAAA==.',St='Sternchên:BAAALAADCgQIBAAAAA==.',Su='Supstral:BAAALAADCggICwAAAA==.',Sv='Svobo:BAAALAADCgcIDQAAAA==.',['Sæ']='Sæmmy:BAAALAAECgYICAAAAA==.',Ta='Tavilá:BAAALAAECgcIEAAAAA==.',Te='Teylor:BAAALAAFFAIIAgAAAA==.',Ti='Tildá:BAAALAAECgMIBAAAAA==.',To='Todesmarf:BAAALAAECgcIDQAAAA==.Tomimba:BAAALAADCgcIBwAAAA==.Toto:BAAALAAECgMIAwAAAA==.',Tr='Triligon:BAAALAADCgMIAwABLAADCggIAQABAAAAAA==.',Tu='Turnschuhman:BAAALAAECgUICAAAAA==.',Tw='Tweyen:BAAALAADCggIDwAAAA==.',Ve='Venem:BAAALAADCggIEwAAAA==.Venturian:BAAALAADCgcIBwAAAA==.Verania:BAAALAAECgEIAQAAAA==.Veros:BAAALAAECgIIAwAAAA==.',Vi='Visji:BAAALAADCgYIBgAAAA==.',Vr='Vrakor:BAAALAADCgMIAwAAAA==.',Wa='Warshock:BAAALAAECgUICwAAAA==.',Xa='Xatas:BAAALAAECgYIBgAAAA==.',Xe='Xenoros:BAAALAAECgcIDQAAAA==.',Ya='Yakuzor:BAAALAAFFAIIAgAAAA==.',Yo='Yoru:BAAALAADCgcIBwAAAA==.',Za='Zagmoth:BAAALAAECgYIBgABLAAFFAEIAQABAAAAAA==.Zarroc:BAAALAAECgQICwAAAA==.',Zi='Zilfallon:BAAALAAECgYICAAAAA==.',['Zê']='Zêrekthul:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.',['És']='Ésmé:BAAALAADCggICAAAAA==.',['Ûl']='Ûltima:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end