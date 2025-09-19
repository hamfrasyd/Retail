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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Warrior-Fury','Paladin-Retribution',}; local provider = {region='EU',realm='Tirion',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Actionork:BAAALAADCgUIBQAAAA==.',Al='Alestis:BAAALAADCgcICgAAAA==.Alinê:BAAALAADCgcIDgAAAA==.',Am='Amônet:BAAALAADCgcIBwAAAA==.',An='Andralas:BAAALAAECgUIBwAAAA==.Anitadiq:BAAALAAECgYICgAAAA==.Ankare:BAAALAAECgIIBAAAAA==.Annastesia:BAAALAADCgIIAQAAAA==.Anubis:BAAALAAECggICwAAAA==.',Aq='Aqui:BAAALAADCgMIAwAAAA==.',Ar='Arluthien:BAAALAADCgcIDgAAAA==.Artischocke:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.',As='Aseria:BAAALAADCgcIBwAAAA==.Asira:BAAALAADCggIFQABLAAECgYICQABAAAAAA==.Asmanica:BAAALAADCggIEAAAAA==.',At='Atas:BAAALAAECggICAAAAA==.Atomstrom:BAAALAAECgIIAgAAAA==.',Au='Auron:BAAALAADCgcICAAAAA==.',Ax='Axeclick:BAAALAADCggICAAAAA==.',Ay='Ayva:BAAALAAECgEIAQAAAA==.',Az='Azaroth:BAAALAADCggIBQAAAA==.Azeem:BAAALAAECgYIDwAAAA==.',Ba='Baiky:BAAALAADCgUIBQAAAA==.Baraqyl:BAAALAADCggICAAAAA==.',Be='Beo:BAAALAADCgUIBQAAAA==.Beothor:BAAALAADCgYIBwAAAA==.',Bi='Biltan:BAAALAADCgYIDAAAAA==.',Bl='Blake:BAAALAAECgcICgAAAA==.',['Bá']='Bálin:BAAALAADCgYICQABLAAECgYICwABAAAAAA==.',Ca='Calmest:BAAALAAECgEIAQAAAA==.Capoplaza:BAAALAAECgMIAwAAAA==.Casarea:BAAALAADCggIDwAAAA==.Cayenn:BAAALAAECgYICAAAAA==.',Cr='Crazylykhan:BAAALAADCggIEAAAAA==.Crotan:BAAALAAECgEIAQAAAA==.Cryogen:BAAALAAECgcIDAAAAA==.',Cy='Cyphe:BAAALAADCgMIAwAAAA==.',Da='Dalari:BAAALAADCgYICQAAAA==.Dandiegro:BAAALAADCgcIDgAAAA==.Darkdestiiny:BAAALAADCgcICgAAAA==.Darkgore:BAAALAAECgEIAQABLAAECgYICQABAAAAAQ==.Darksilver:BAAALAAECgYICQAAAA==.',De='Dego:BAAALAAECgcIDQAAAA==.Dellefin:BAAALAAECgYICQAAAA==.Dentenist:BAAALAAECgEIAQABLAAECgcIFQACAMUYAA==.',Di='Diemonia:BAAALAADCgcIFQAAAA==.Discolight:BAAALAAECggICAAAAA==.Dissonance:BAAALAADCgMIAwAAAA==.Divoka:BAAALAADCgEIAQAAAA==.',Dm='Dmagicd:BAAALAAECggICAAAAA==.',Do='Dopsi:BAAALAADCgQIBAAAAA==.',Dr='Dracarya:BAAALAAECgYICgAAAA==.Draídax:BAAALAAECgIIBAAAAA==.',Du='Dusty:BAAALAAECggICAAAAA==.',['Dæ']='Dænerys:BAAALAADCggICAAAAA==.',['Dê']='Dêâthknight:BAAALAADCggIDwAAAA==.',['Dí']='Dína:BAAALAADCgUIBQAAAA==.Dívestry:BAAALAADCggICAABLAAECggIFQADAIYgAA==.',['Dî']='Dîvestry:BAABLAAECoEVAAIDAAgIhiB2BgAOAwADAAgIhiB2BgAOAwAAAA==.',['Dô']='Dôriâ:BAAALAADCggIDwAAAA==.',Ea='Ea:BAAALAAECgYIBwAAAA==.',Eb='Ebrietas:BAAALAAECgYICwAAAA==.',En='Endurrion:BAAALAAECgYIBwAAAA==.',Er='Erdcracker:BAAALAAECgMIAwAAAA==.Eredrak:BAAALAADCggIDwAAAA==.Eriador:BAAALAADCgcIFAAAAA==.Eriôn:BAAALAADCgcIBwAAAA==.',Ex='Exôdûs:BAAALAAECgIIAgAAAA==.',Fi='Fiesta:BAAALAADCggICAAAAA==.',Fr='Friedchicken:BAAALAAECgIIAgAAAA==.Frída:BAAALAADCgcIDgAAAA==.Frôst:BAAALAAECgUIBQAAAA==.',Ga='Ganadorus:BAAALAADCggIBwAAAA==.',Gi='Gilceleb:BAAALAADCggIFwAAAA==.',Go='Goodaim:BAAALAAECgEIAQAAAA==.',Gu='Guildt:BAAALAAECgYICwAAAA==.',Ha='Hampelmaan:BAAALAAECgYIBgAAAA==.Haraldos:BAAALAADCgcIBwAAAA==.Haress:BAAALAAECgQIBgAAAA==.',He='Heilmo:BAAALAADCgMIAwAAAA==.Heiphestos:BAAALAADCggIDQAAAA==.Helius:BAAALAADCgUIBQAAAA==.',Hi='Hizzer:BAAALAADCggICAAAAA==.',Ho='Holymeelo:BAAALAADCggIDwAAAA==.',Hy='Hydnose:BAAALAAECgcIDQAAAA==.',['Hú']='Húbert:BAAALAADCgMIAwAAAA==.',Id='Idomos:BAAALAADCgMIAwAAAA==.Idorai:BAAALAAECgEIAQAAAA==.',Il='Illidana:BAAALAADCgUIBQAAAA==.',In='Inalun:BAAALAADCggIFQAAAA==.Inasta:BAAALAADCgcIFAAAAA==.Intheembrace:BAAALAAECgcIDQAAAA==.',Ja='Jaress:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.',Ji='Jimeno:BAAALAAECgEIAQAAAA==.',Jo='Joanofarc:BAAALAAECgEIAQAAAA==.',Ju='Julaki:BAAALAADCggICQAAAA==.Junho:BAAALAAECgMIAwAAAA==.',['Jô']='Jôlinar:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.',Ka='Kair:BAAALAAECgIIBAAAAA==.Kalda:BAAALAAECgYIAgAAAA==.Karion:BAAALAADCggIDwAAAA==.',Ke='Keísha:BAAALAAECgEIAQAAAA==.',Ki='Kiaros:BAAALAAECgEIAQAAAA==.Kida:BAAALAAECgYIDQAAAA==.Killnoob:BAAALAADCggIDwAAAA==.Kimbalin:BAAALAADCgcIFAAAAA==.Kiss:BAAALAADCggIDQAAAA==.Kiyoki:BAAALAADCgYIBgAAAA==.',Kl='Kletz:BAAALAAECgYICAAAAA==.',Kn='Knörrli:BAAALAADCgcIBwAAAA==.',Ko='Kommarübär:BAAALAADCggIEAAAAA==.Koronà:BAAALAAECgYICQAAAA==.Korsarius:BAAALAAECgYIBwAAAA==.',Kr='Kration:BAAALAADCggIEwAAAA==.',['Ké']='Kéréòn:BAAALAAECgUIBQAAAA==.',['Kü']='Kürwalda:BAAALAAECgMIAwAAAA==.',La='Lagastí:BAAALAAECgcIDAAAAA==.Lahrin:BAAALAAECgUICQAAAA==.Lanaley:BAAALAAECgcIDgAAAA==.Lassknacken:BAAALAADCggICQAAAA==.Latoýya:BAAALAADCggICAAAAA==.',Le='Leandrôs:BAAALAAECgIIAgAAAA==.Leijona:BAAALAADCgMIAwAAAA==.Leyti:BAAALAADCggIBQAAAA==.',Li='Lillara:BAAALAAECgYIDAAAAA==.Lillithu:BAAALAADCggICAAAAA==.',Lo='Lokin:BAAALAADCgcIBwAAAA==.',Lu='Lukida:BAAALAADCgYICwAAAA==.Lum:BAEALAAECgIIBAABLAAECgcIEAABAAAAAA==.Lusamine:BAAALAAECgcIEAAAAA==.',Ma='Maluna:BAAALAAECgIIAgAAAA==.Manco:BAAALAAECgYIDwAAAA==.Maracuja:BAAALAAECggIDwAAAA==.Maxdk:BAAALAADCgcIDQAAAA==.',Me='Mexi:BAAALAADCgMIAQAAAA==.',Mi='Michi:BAAALAAECgEIAQAAAA==.Ministry:BAAALAAECgcICAAAAQ==.Mirkan:BAAALAAECgUIBwAAAA==.Mizagi:BAAALAAECgMIBQAAAA==.',Mu='Mugen:BAAALAADCgcIDQAAAA==.',Mv='Mvnko:BAAALAADCgYICAABLAAECgYIDwABAAAAAA==.',My='Myrion:BAAALAAECgEIAQAAAA==.Mysteryá:BAAALAADCgcIDQAAAA==.Mythio:BAAALAAECgIIAgABLAAECgMIBQABAAAAAA==.',['Mí']='Míráculíx:BAAALAAECggIDQAAAA==.',Na='Narkotica:BAAALAAECgYIDwAAAA==.',Ne='Neku:BAAALAAECgYIBgAAAA==.',Ni='Nightofmeelo:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.Nirritriel:BAAALAADCggICwABLAAECgYICwABAAAAAA==.',Ny='Nylwan:BAAALAAECgYICgAAAA==.',['Nê']='Nêram:BAAALAADCgcIBwAAAA==.',Oc='Ocyde:BAAALAAECgUIBwAAAA==.',Ol='Oleron:BAAALAAECggICAAAAA==.',Pa='Paerna:BAAALAADCgYIBgAAAA==.Painstriker:BAAALAADCggICAAAAA==.Paly:BAAALAAECgEIAQAAAA==.Paran:BAAALAADCggICAAAAA==.Parkos:BAAALAAECgMIAwAAAA==.',Pe='Pelori:BAAALAADCgIIAwAAAA==.Pey:BAAALAAECgYIEAAAAA==.Peyoteh:BAAALAADCggIEQAAAA==.',Ps='Psychomantis:BAAALAADCggIDwAAAA==.',Qu='Quirl:BAAALAAECgMIBAAAAA==.',Ra='Raddeneintop:BAAALAAECgIIAwAAAA==.Radgást:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.Ralfpeterson:BAAALAAECgUIBQAAAA==.Rarfunzel:BAAALAADCgYIBgAAAA==.Raze:BAAALAADCgcIBwAAAA==.',Re='Realm:BAAALAADCggICAAAAA==.Replika:BAAALAADCggIEQAAAA==.Retardor:BAAALAAECgYICwAAAA==.Revênger:BAAALAAECgYIDAAAAA==.',Rh='Rheja:BAAALAAECgYIBwAAAA==.',Ro='Robert:BAAALAADCggICAAAAA==.Rovína:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.',Ry='Ryluras:BAAALAAECgQIBAAAAA==.',Sa='San:BAEALAAECgcIEAAAAA==.Sansibar:BAAALAADCggIFwAAAA==.',Se='Selkie:BAAALAAECgQIBQAAAA==.Serenya:BAAALAAECgUIBQAAAA==.',Sh='Shakitilar:BAAALAAECgEIAQAAAA==.Shambulance:BAAALAADCgYIBgAAAA==.Shandoshea:BAAALAADCgYIBgAAAA==.Sheeva:BAAALAADCgcIBwAAAA==.',Si='Siluria:BAAALAAECggICAAAAA==.',Sk='Skrymir:BAAALAADCggICAAAAA==.',Sl='Sleepy:BAAALAAECgYICQAAAA==.',So='Sopranos:BAAALAAECgQIBAAAAA==.Sorasa:BAAALAADCggIEwAAAA==.',St='Sturmtraum:BAAALAAECgIIBQAAAA==.Stôrmfighter:BAAALAADCgYICAAAAA==.',Sw='Sweet:BAAALAADCgQIBAAAAA==.',Sy='Sylforia:BAAALAAECgMIBQAAAA==.',['Sê']='Sêlené:BAAALAADCgYIBgAAAA==.',Ta='Talvy:BAAALAADCgcIBwAAAA==.',Te='Temeria:BAAALAAECgYIBwAAAA==.Tendroin:BAAALAAECggIDQAAAA==.Teran:BAAALAADCgcIBwAAAA==.',Th='Themistro:BAAALAAECgYIBwAAAA==.Thurîn:BAAALAAECggICAAAAA==.Thynotlikeus:BAAALAADCggIDAAAAA==.',Ti='Titoo:BAAALAADCgcIBwAAAA==.',To='Tobert:BAAALAAECgYICQAAAA==.Todeszwerg:BAAALAADCggIFgAAAA==.',Tr='Trostrinossa:BAAALAADCgYIBgAAAA==.',Tu='Turbooma:BAAALAADCggICAAAAA==.Turrikan:BAAALAAECgEIAQAAAA==.',Tw='Twìlíght:BAAALAADCgYIBgAAAA==.',['Tâ']='Tâekwondo:BAABLAAECoEVAAICAAcIxRgpDQDzAQACAAcIxRgpDQDzAQAAAA==.',['Tå']='Tåyxzz:BAAALAADCgYIBgAAAA==.',Va='Valeri:BAAALAADCggICQAAAA==.Vanos:BAAALAADCgcIEAAAAA==.Vaska:BAAALAADCggICwAAAA==.',Ve='Verndarís:BAAALAADCgcIFAAAAA==.',Vi='Vit:BAAALAAECgIIBAAAAA==.',Wa='Wala:BAAALAAECgEIAQAAAA==.',We='Weskér:BAAALAADCgcIBwAAAA==.',Wh='Whiteiverson:BAAALAADCgEIAQAAAA==.',Wi='Wichtlzwick:BAAALAAECgMIAwAAAA==.Wildeyes:BAAALAAECgYICgAAAA==.Wildman:BAAALAADCgUIBQAAAA==.',Wo='Worn:BAAALAAECgMIAwAAAA==.',Xa='Xavulpa:BAAALAADCggICgAAAA==.',Xe='Xenophilos:BAAALAADCgYIBgAAAA==.',Xi='Xipetwo:BAAALAAECgEIAQAAAA==.',Xy='Xylaara:BAAALAADCggICgAAAA==.',Ya='Yalor:BAAALAAECgIIBAAAAA==.',Yh='Yharnam:BAAALAADCgcICwAAAA==.',Yu='Yuma:BAAALAADCgMIAwAAAA==.',['Yú']='Yúríhású:BAAALAAECgMIBQAAAA==.',['Yû']='Yûlivee:BAAALAAECgYIEgAAAA==.',Za='Zapfdos:BAAALAAECggICAAAAA==.Zayomi:BAAALAADCgYIBgAAAA==.',Ze='Zenos:BAABLAAECoEUAAIEAAgI9gDnjwBJAAAEAAgI9gDnjwBJAAAAAA==.Zera:BAAALAAECgMIAwAAAA==.',Zo='Zoè:BAAALAADCgQIBAAAAA==.',Zu='Zudar:BAAALAAECgYIBQABLAAECgYIDQABAAAAAA==.',Zw='Zwai:BAAALAADCggICAAAAA==.',['Âl']='Âllrounder:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end