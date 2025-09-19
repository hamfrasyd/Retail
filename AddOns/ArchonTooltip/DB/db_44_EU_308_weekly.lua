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
 local lookup = {'Druid-Restoration','Warrior-Protection','DeathKnight-Blood','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Warrior-Fury','Priest-Holy','DemonHunter-Havoc','Monk-Windwalker','Hunter-BeastMastery','Paladin-Protection',}; local provider = {region='EU',realm='KulTiras',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Achilleas:BAAALAAECgIIAwAAAA==.',Af='Afrodita:BAAALAAECgcIDgAAAA==.',Ag='Agrelle:BAABLAAECoEUAAIBAAgILRAYKACfAQABAAgILRAYKACfAQAAAA==.',Ai='Aizu:BAAALAAECgIIBAAAAA==.',Ak='Akile:BAABLAAFFIEPAAICAAYIbiFDAABqAgACAAYIbiFDAABqAgABLAAECggIFwADAJ0lAA==.Akivasha:BAAALAAECgIIBAAAAA==.',Al='Alabara:BAAALAAECgMIAwAAAA==.Alexandrina:BAAALAAECgYIBgAAAA==.',Am='Amaraa:BAAALAAECgYIDwAAAA==.Amedeu:BAAALAADCgcIBwAAAA==.Amidofen:BAAALAAECgYICgABLAAECgcIDgAEAAAAAA==.Amzil:BAAALAADCggICQAAAA==.',An='Annsin:BAAALAAECgYICgAAAA==.',Ap='Apokaliio:BAAALAADCgcIBwAAAA==.Apureborn:BAAALAADCggICAAAAA==.',Aq='Aquilinus:BAAALAADCgcIDQAAAA==.',Ar='Arenith:BAACLAAFFIEIAAIFAAMIHSa3AgBVAQAFAAMIHSa3AgBVAQAsAAQKgR0ABAUACAiVJcACAEQDAAUACAiVJcACAEQDAAYAAwi1G4gIAMwAAAcAAgi+ITAaAMQAAAAA.Artaios:BAAALAADCgYIBgAAAA==.',Au='Auris:BAAALAAECgUICwAAAA==.',Ay='Aydris:BAAALAAECgMIBgAAAA==.',Az='Azina:BAABLAAECoEUAAMIAAcIfiNYCwCpAgAIAAcIfiNYCwCpAgAJAAIIbSHaVQDGAAAAAA==.',Ba='Bankerdeg:BAAALAADCggICAAAAA==.',Be='Benzigaz:BAAALAADCggICAAAAA==.Berserkr:BAAALAAECgIIAgAAAA==.',Bi='Biscuittea:BAAALAADCgMIBAAAAA==.',Bk='Bkcd:BAAALAAECgIIBAAAAA==.',Bo='Boinkki:BAAALAAECgIIAgAAAA==.Borvo:BAAALAAECgIIBAAAAA==.',Br='Brenrik:BAAALAADCgQIBAAAAA==.Bronzemane:BAAALAADCgYIBgAAAA==.Bruhbble:BAAALAADCggICAAAAA==.',Ca='Cacodemon:BAAALAAECggIDgAAAA==.Castan:BAACLAAFFIEHAAMKAAMIlyGcAwA2AQAKAAMIlyGcAwA2AQACAAIIIBPfBwCPAAAsAAQKgRcAAwoACAhIJYUEAEQDAAoACAhIJYUEAEQDAAIAAgg0HyQ2AKEAAAAA.Castiana:BAECLAAFFIEIAAILAAMIZhDQBgD9AAALAAMIZhDQBgD9AAAsAAQKgRcAAgsACAh9G9URAHMCAAsACAh9G9URAHMCAAAA.Cay:BAAALAAECgYICwAAAA==.',Ch='Charmelina:BAAALAADCggICAAAAA==.Chrysalis:BAABLAAECoEYAAIMAAYITSAtLwAMAgAMAAYITSAtLwAMAgAAAA==.',Ci='Cindradeath:BAAALAAECgQIBgAAAA==.Cindralock:BAAALAAECgYIEAAAAA==.',Cl='Clageddin:BAAALAAECgcIDgAAAA==.Claim:BAAALAAECgEIAQAAAA==.Cleed:BAAALAADCgUIBgAAAA==.',Da='Danji:BAAALAADCgcIDQAAAA==.Darkhaus:BAAALAADCgYIBgAAAA==.Darksoul:BAAALAAECgEIAQAAAA==.Dazage:BAAALAAECgQICQAAAA==.',De='Deackard:BAAALAADCggICAAAAA==.Deathpelt:BAAALAAECgIIAgABLAAECggICAAEAAAAAQ==.Deathwisherr:BAAALAAECggICAAAAA==.Demohan:BAAALAADCgYIDAAAAA==.Denovox:BAAALAAFFAIIAwAAAA==.',Do='Dontcarebear:BAAALAADCggIDQABLAAFFAMIBwANAOgMAA==.Down:BAAALAAECgYICAAAAA==.',Dr='Dragonloc:BAAALAAECgMIBgAAAA==.Druda:BAAALAAECgYIDQAAAA==.',Du='Dudududududu:BAAALAAECgYICgAAAA==.Dumplings:BAAALAADCggIHwABLAAECggICAAEAAAAAQ==.Duskstrider:BAAALAAECgYIDQAAAA==.',Dv='Dv:BAAALAADCggICAABLAAECgMIAwAEAAAAAQ==.',['Dà']='Dàrren:BAAALAAECgEIAgAAAA==.',['Dò']='Dòx:BAAALAADCggIHAABLAAECgUICQAEAAAAAA==.',El='Elvenelder:BAAALAADCggIGAAAAA==.',En='Encheladus:BAAALAAECgYICQAAAA==.',Eo='Eoline:BAAALAAECgQIBAAAAA==.',Er='Eryndor:BAAALAAECggIEAAAAA==.',Ex='Expiator:BAAALAAECgIIBAAAAA==.',Fi='Fiorano:BAAALAAECgMIBwAAAA==.Fishslap:BAACLAAFFIEHAAINAAMI6AxDAwDsAAANAAMI6AxDAwDsAAAsAAQKgRwAAg0ACAjZHFkIAKMCAA0ACAjZHFkIAKMCAAAA.',Fl='Flaskekork:BAABLAAECoEWAAIOAAgIsRJMJAASAgAOAAgIsRJMJAASAgAAAA==.',Fo='Folkenor:BAAALAAECgYICgAAAA==.Fordealyn:BAAALAAFFAMIBAAAAA==.Foxford:BAAALAAECgcIBwABLAAECggICAAEAAAAAA==.Foxrogerbeer:BAAALAAECgYIDgAAAA==.',Ft='Ftw:BAAALAAECgQIBAAAAA==.',Fu='Funtimes:BAAALAAECgcIDAAAAA==.Fuzzybrows:BAAALAADCgQIBAAAAA==.',Ga='Gars:BAAALAADCggICAAAAA==.',Gi='Gilarás:BAAALAADCgcIBwAAAA==.',Go='Goldenlay:BAAALAADCgYICgABLAAECggICAAEAAAAAQ==.',Ha='Haelix:BAAALAAECgYICgAAAA==.Happy:BAAALAADCggIDwAAAA==.',He='Helvar:BAAALAAECgYICgAAAA==.',Ho='Holmqvist:BAAALAAECgYIBgAAAA==.Holyjosh:BAAALAADCgYIBwAAAA==.',Hu='Hunttn:BAAALAADCggICAAAAA==.',Id='Idle:BAAALAAECgIIAwAAAA==.',In='Incarnum:BAAALAAECgYICgAAAA==.Ink:BAAALAADCgUIBQAAAA==.',Ir='Ira:BAAALAAECgIIAwAAAA==.',Ja='Jadee:BAAALAADCgIIAgAAAA==.Jagura:BAAALAAECgYICAAAAA==.January:BAAALAAECgQIBwAAAA==.',Je='Jever:BAAALAAECgUICQAAAA==.',Ji='Jihto:BAAALAADCggICAAAAA==.',Ju='Julienne:BAAALAADCgQIBAAAAA==.',['Já']='Jámíe:BAAALAAECgYIDAAAAA==.',Ka='Kamino:BAAALAADCggICAAAAA==.Kazibo:BAAALAAECgcIEAAAAA==.',Ke='Kelsara:BAAALAAECgYICgAAAA==.',Kl='Kleivyn:BAAALAAECgYICgAAAA==.Kloabo:BAAALAADCgcIBwAAAA==.',Kn='Knabby:BAAALAAECgMIBgAAAA==.',Ko='Koiot:BAAALAADCggICgABLAAECgcIDgAEAAAAAA==.',La='Lath:BAACLAAFFIELAAIBAAQIkxSFAQBlAQABAAQIkxSFAQBlAQAsAAQKgSEAAgEACAidH/IIAKwCAAEACAidH/IIAKwCAAAA.',Le='Leannan:BAAALAADCggICAAAAA==.',Li='Liamneeson:BAAALAAECgcIDQAAAA==.Linkez:BAAALAAECgIIBAAAAA==.',Lo='Lorienne:BAAALAADCgcIDAAAAA==.',Lu='Lulläby:BAAALAADCgMIAwAAAA==.',Ly='Lyoria:BAAALAADCggIDwAAAA==.',Ma='Macy:BAAALAADCgMIBAAAAA==.Maeliven:BAAALAAECgEIAQAAAA==.Malucifer:BAAALAAECgYICgAAAA==.Mamsebumsen:BAAALAADCgcIBwAAAA==.',Mi='Micara:BAAALAADCgUIBQAAAA==.Milk:BAAALAAECgYIBgAAAA==.Minuva:BAAALAAFFAIIBAABLAAFFAMIBAAEAAAAAA==.Miramizz:BAAALAADCgMIAwAAAA==.',Mo='Morrisons:BAAALAAECgYICAAAAA==.',Ms='Msd:BAAALAAECgcICAAAAA==.',['Mî']='Mîhr:BAAALAADCggICAAAAA==.',Na='Nadgob:BAAALAADCgYICwAAAA==.Nanski:BAAALAAECgcIDQAAAA==.Narim:BAAALAAECgIIAgAAAA==.',Ne='Nemi:BAAALAADCgcIBwAAAA==.Nerflord:BAAALAAECgYICwAAAA==.Nexeath:BAAALAADCggIEAAAAA==.',No='Nomelk:BAAALAADCgIIAgAAAA==.Nozdormi:BAAALAADCggIIAABLAAECggICAAEAAAAAA==.',Nz='Nzk:BAABLAAECoEWAAIKAAcI2hwEGABdAgAKAAcI2hwEGABdAgAAAA==.',Ok='Okatsuki:BAAALAADCggICAAAAA==.',Op='Opaque:BAAALAADCgQIBAABLAAECgYIGAAMAE0gAA==.',Or='Orobas:BAAALAADCggIDgAAAA==.',Os='Osias:BAAALAADCggICAAAAA==.',Pa='Paci:BAAALAADCggICAAAAA==.Paladinpain:BAAALAAECgQIBwAAAA==.',Pe='Pesha:BAAALAAECgYIBgAAAA==.',Ph='Ph:BAAALAAECgMIAwAAAQ==.',Po='Polimeriq:BAAALAAECgYICgAAAA==.Ponydin:BAAALAAECgEIAQABLAAECggIAgAEAAAAAQ==.Ponysmash:BAAALAAECgUIBQABLAAECggIAgAEAAAAAA==.Portalkeeper:BAAALAADCgYIBgAAAA==.',Pr='Prottector:BAAALAADCggICAAAAA==.',Pu='Puss:BAAALAAECgMIAwAAAA==.',Qu='Quarrel:BAAALAAECggICAAAAA==.',Ra='Raiten:BAAALAAECgIIBAAAAA==.Raveleijn:BAAALAAECgYIDAAAAA==.Rawrbaby:BAAALAAECgUICAAAAA==.',Re='Redsonja:BAAALAADCggICAAAAA==.',Ri='Riftwalker:BAAALAAECgIIBAAAAA==.',Ro='Roger:BAAALAAECgYIEwAAAA==.Rosenkrauz:BAAALAAECgEIAQAAAA==.',Ru='Rudedude:BAAALAAECgEIAQAAAA==.',Sa='Saintpeter:BAAALAAECgYIBgAAAA==.Sandalf:BAAALAAECggICAAAAA==.',Se='Seppe:BAAALAAECgMIBgAAAA==.Serlina:BAAALAAECgYICQAAAA==.',Sh='Shadowfury:BAAALAADCggICAAAAA==.Shavora:BAAALAAECgYIBAAAAA==.Shinyman:BAAALAAECgYIDgAAAA==.',Sp='Spggl:BAAALAADCgcICwAAAA==.',St='Stanx:BAAALAADCgYIBgAAAA==.Stéfan:BAAALAADCggIFwAAAA==.',Su='Suey:BAAALAAECgcICQAAAA==.Suny:BAAALAAECgIIBAAAAA==.',Sy='Sylv:BAAALAAECgEIAgAAAA==.',Ta='Takeshi:BAAALAAECgMIAwAAAA==.Tarkuss:BAAALAADCgMIAwAAAA==.',Te='Tempest:BAAALAAECggICAAAAQ==.',Th='Thorolf:BAAALAADCgYIBgAAAA==.',Ti='Tienus:BAABLAAECoEXAAIPAAgIdh7iBwBwAgAPAAgIdh7iBwBwAgAAAA==.',Tr='Triest:BAAALAADCgMIAwAAAA==.',Tu='Turboligma:BAAALAADCggIDAAAAA==.',Tw='Tworkm:BAAALAAECgMIBQAAAA==.',Ty='Tyshia:BAAALAADCgMIAwAAAA==.',Va='Vali:BAAALAAECgYIDgAAAA==.Vanthir:BAAALAAECgYICQAAAA==.',Ve='Venrak:BAAALAADCgIIAgAAAA==.Vermax:BAAALAADCgQIBAAAAA==.',Vu='Vulaang:BAAALAAECgIIAgABLAAECggICAAEAAAAAQ==.Vulgoku:BAAALAAECgIIAgABLAAECggICAAEAAAAAA==.Vulpie:BAAALAAECgIIAgABLAAECggICAAEAAAAAA==.',Wa='Wampy:BAAALAAECgEIAwAAAA==.',Wh='Whelp:BAAALAAECgYIBgAAAA==.',Ya='Yasha:BAAALAADCgEIAQAAAA==.',Ye='Yeshbre:BAAALAAECgMIAwAAAA==.',Yo='Yondaimekun:BAAALAADCgcIBwAAAA==.',Za='Zanisia:BAAALAAECgIIAwAAAA==.Zanixis:BAAALAADCgcIDAAAAA==.',Ze='Zeng:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end