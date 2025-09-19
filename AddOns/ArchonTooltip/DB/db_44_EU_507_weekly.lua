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
 local lookup = {'Unknown-Unknown','Monk-Windwalker',}; local provider = {region='EU',realm='LosErrantes',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Acay:BAAALAADCgYIBgAAAA==.',Ae='Aellenris:BAAALAADCgYIBwAAAA==.',Ai='Aidenkrant:BAAALAADCggIDQAAAA==.',Ak='Akrome:BAAALAAECgIIAwAAAA==.',Al='Alanarya:BAAALAADCggIDgAAAA==.Albaa:BAAALAADCggICAAAAA==.Alileath:BAAALAADCgYIBgAAAA==.Alizza:BAAALAADCgEIAQAAAA==.Aloestra:BAAALAADCgcICQAAAA==.Althuro:BAAALAADCggIDAAAAA==.',Am='Amapolíto:BAAALAADCgcIEAAAAA==.',An='Anderkaz:BAAALAADCgEIAQAAAA==.Androx:BAAALAADCggIEQAAAA==.Anthirell:BAAALAAECgEIAQAAAA==.Anubiswar:BAAALAADCgcIBwAAAA==.',Aq='Aquerontes:BAAALAADCggIEQAAAA==.',Ar='Arcanimal:BAAALAAECgYIDQAAAA==.Aristoi:BAAALAADCggICAAAAA==.',As='Asiulfer:BAAALAADCgQIBAAAAA==.Astaaldë:BAAALAAECgEIAQAAAA==.Astar:BAAALAADCggIDgAAAA==.Astarz:BAAALAADCgQIBAAAAA==.Astredius:BAAALAADCggIEAAAAA==.',At='Athaeri:BAAALAAECgYIDQAAAA==.Athïca:BAAALAADCgYIBgAAAA==.',Ay='Ayakadina:BAAALAADCgYIBgAAAA==.',['Aé']='Aérys:BAAALAADCgEIAQAAAA==.',Be='Beldruck:BAAALAADCgQIBAAAAA==.',Bl='Blackorion:BAAALAADCgEIAQAAAA==.',Bo='Bombillita:BAAALAAECgYICwAAAA==.',Br='Breinnon:BAAALAAECggICAAAAA==.',Bu='Bursting:BAAALAAECggICAAAAA==.',Ca='Caricias:BAAALAADCggIDQAAAA==.Caspper:BAAALAAECgcICAAAAA==.Castóreo:BAAALAADCgYIBgAAAA==.Cazapoder:BAAALAAECgIIAwAAAA==.',Ch='Chony:BAAALAAECgMIBQAAAA==.Chrox:BAAALAADCgcICAAAAA==.Chunlio:BAAALAADCggICgAAAA==.',Ci='Cinabrio:BAAALAADCgYIBgAAAA==.',Cr='Crantox:BAAALAAECgcIEQAAAA==.',Da='Daggam:BAAALAAECgYICgAAAA==.Danielbcn:BAAALAADCggIDQAAAA==.Darkpiark:BAAALAAECgcICwAAAA==.Darkusys:BAAALAADCgcIFwAAAA==.Darphal:BAAALAAECgMIBgAAAA==.Dayha:BAAALAADCgMIAwAAAA==.Daêron:BAAALAADCgIIAgAAAA==.',De='Deadpul:BAAALAAECgEIAQAAAA==.Deblester:BAAALAAECgIIAwAAAA==.Demontes:BAAALAADCggICAAAAA==.Descartep:BAAALAADCgIIAgAAAA==.Desrya:BAAALAAECgUIBgAAAA==.Destrals:BAAALAAECgIIAgAAAA==.',Dh='Dhh:BAAALAAECgEIAgAAAA==.',Di='Diriel:BAAALAADCggIAwABLAAECgMIAwABAAAAAA==.',Do='Domi:BAAALAAECgUICQAAAA==.',Dr='Drÿox:BAAALAADCggICQAAAA==.',Du='Duendexl:BAABLAAECoEbAAICAAcIIw1YEwCSAQACAAcIIw1YEwCSAQAAAA==.',['Dæ']='Dærius:BAAALAADCgIIAgAAAA==.',Ed='Edelgard:BAAALAADCgcIDAAAAA==.',El='Elfyto:BAAALAAECgMIBAAAAA==.Elmetal:BAAALAAECgYICwAAAA==.Elynara:BAAALAAECgYIDAAAAA==.Elëazar:BAAALAADCggIDwAAAA==.',Er='Eruanne:BAAALAADCgcIBwAAAA==.',['Eä']='Eälara:BAAALAAECgUICQAAAA==.',Fa='Fatalision:BAAALAADCggICAAAAA==.',Fe='Fereya:BAAALAAECgEIAQAAAA==.Ferritina:BAAALAADCggIDQAAAA==.',Fh='Fhraín:BAAALAADCgIIAgAAAA==.',Fo='Forellas:BAAALAAECgMIBgAAAA==.Fortipiri:BAAALAADCgYIBwAAAA==.Fourrouses:BAAALAADCgYIBgAAAA==.',Ga='Garar:BAAALAAECggICQAAAA==.Garraatroz:BAAALAADCgYIBgAAAA==.Gatitopiloto:BAAALAAECgQIBgAAAA==.Gaunt:BAAALAADCgcIDQAAAA==.',Gi='Giste:BAAALAAECgMIBAAAAA==.',Gn='Gnotorioum:BAAALAAECgMIAwAAAA==.',Gr='Greed:BAAALAADCggIDwAAAA==.Grow:BAAALAADCgcIBwAAAA==.',Gu='Gulthix:BAAALAADCgcIDgAAAA==.Gunark:BAAALAAECgYIDAAAAA==.',He='Heafry:BAAALAADCggICAAAAA==.',Il='Illidiam:BAAALAADCgQIBAAAAA==.',Ju='Juanoton:BAAALAADCgMIBgAAAA==.Junio:BAAALAAECgMIAwAAAA==.',Ka='Kadran:BAAALAAECgYICgAAAA==.Kairel:BAAALAAECgEIAQAAAA==.Kaiton:BAAALAADCggICQAAAA==.Karslah:BAAALAAECgMIAwAAAA==.Kathiane:BAAALAADCgcICAAAAA==.Kauki:BAAALAADCggICwAAAA==.Kayl:BAAALAADCgYICAAAAA==.',Kh='Khelara:BAAALAAECgYICQAAAA==.Khrona:BAAALAADCgcIBwAAAA==.',Ki='Kiiraa:BAAALAADCggICAAAAA==.',Kl='Kleir:BAAALAADCgIIAgAAAA==.Kloso:BAAALAADCgIIAQAAAA==.',Ko='Komorebi:BAAALAAECggICQAAAA==.',Kr='Kraigon:BAAALAADCgYIBgAAAA==.Krisko:BAAALAADCggICAAAAA==.Krympal:BAAALAADCggIDAAAAA==.Krâven:BAAALAADCggICwAAAA==.',['Ké']='Kélya:BAAALAADCggICAAAAA==.',La='Larryworrier:BAAALAADCgcICgAAAA==.Larrÿ:BAAALAAECggIEwAAAA==.Layon:BAAALAADCgcIDAAAAA==.',Le='Ledolian:BAAALAAECgUICAAAAA==.',Lo='Lokdevil:BAAALAADCgcIEwAAAA==.Lolailo:BAAALAADCggICwAAAA==.',Lu='Lunyta:BAAALAADCgcIDQAAAA==.Luraan:BAAALAAECgEIAgAAAA==.Luzbuena:BAAALAAECgIIAwAAAA==.',Ly='Lybra:BAAALAAECgYIDAAAAA==.',Ma='Madôwk:BAAALAADCgYICAAAAA==.Makami:BAAALAAECgYIDgAAAA==.Maldite:BAAALAADCggIDwAAAA==.Maldixo:BAAALAAECgEIAQAAAA==.Maléfïca:BAAALAADCggIDQAAAA==.Martína:BAAALAADCggICAAAAA==.Matildabrujo:BAAALAADCgIIAgABLAAECgIIAwABAAAAAA==.Matisa:BAAALAADCgIIAgAAAA==.Mayacz:BAAALAAECgEIAQAAAA==.Mayaibuky:BAAALAAECgYICQAAAA==.Maÿä:BAAALAAECgMIBQAAAA==.',Me='Meleblanca:BAAALAAECgIIAwAAAA==.Merilas:BAAALAADCggIDAABLAAECgMIAwABAAAAAA==.',Mi='Milene:BAAALAADCgUIBgAAAA==.Miletwo:BAAALAADCgUIBgAAAA==.Mirandagr:BAAALAADCgUIBQAAAA==.',Mo='Moniná:BAAALAADCggIDwAAAA==.Mordres:BAAALAADCggIDgAAAA==.Moribundilla:BAAALAADCgQIBAAAAA==.',Mu='Muerteignea:BAAALAAECgMIAwAAAA==.Multimuerte:BAAALAAECgMIBQAAAA==.Mumscatha:BAAALAADCgcIDQAAAA==.Muriel:BAAALAADCggIDQAAAA==.',My='Mythranar:BAAALAAECgEIAgAAAA==.',['Mö']='Mömotalo:BAAALAADCggICAAAAA==.',Na='Nahiris:BAAALAAECgYIBQAAAA==.Naruat:BAAALAADCgMIAwAAAA==.Naturas:BAAALAADCggIEwAAAA==.Naylz:BAAALAAECgYIEAAAAA==.Nazryl:BAAALAADCgcICAAAAA==.',Ni='Nind:BAAALAADCgcIEgAAAA==.Nindal:BAAALAADCgQIBAAAAA==.Niznik:BAAALAADCgcIDgAAAA==.Niøh:BAAALAADCggICAAAAA==.',No='Notoriouh:BAAALAAECgEIAQAAAA==.Noxun:BAAALAADCggICAAAAA==.',Nu='Nuyou:BAAALAADCgYIBQAAAA==.',Ny='Nyx:BAAALAAECgYIBwAAAA==.',['Nò']='Nòctis:BAAALAADCgYIBgAAAA==.',Oc='Oceiiros:BAAALAADCggIBwAAAA==.',Ol='Oldxlogan:BAAALAAECgYIDAAAAA==.',On='Onîll:BAAALAADCgMIAwAAAA==.',Os='Osdir:BAAALAADCggIDAAAAA==.',Pa='Paladoña:BAAALAAECgMIBAAAAA==.Parteviudas:BAAALAADCgYIBgAAAA==.Payumpayum:BAAALAAECgcIDQAAAA==.',Pe='Peloso:BAAALAAECgQIAgAAAA==.Pepesonrisas:BAAALAAECgQICQAAAA==.Petitcherile:BAAALAADCgYIBgAAAA==.',Ph='Phalhun:BAAALAADCgUIBQAAAA==.',Pi='Pirula:BAAALAADCgcIBwAAAA==.Pixxie:BAAALAADCggIFQAAAA==.',Ra='Radagaxt:BAAALAADCggIDgAAAA==.Raidenazo:BAAALAAECgYIDgAAAA==.Rasgamuerta:BAAALAAECgMIAwAAAA==.Ratsa:BAAALAADCgYIEgAAAA==.Razputin:BAAALAADCggICAAAAA==.Raÿk:BAAALAAECgQIBAAAAA==.',Re='Retrasovil:BAAALAADCgYIBgAAAA==.',Ry='Ryun:BAAALAADCgcIDQAAAA==.',['Ré']='Révan:BAAALAADCgYIBAAAAA==.',Sa='Saioablack:BAAALAAECgUICgAAAA==.Sakher:BAAALAADCgcIBwAAAA==.Samigauren:BAAALAADCggICwAAAA==.Sanasanita:BAAALAAECgMIBgAAAA==.Sanméi:BAAALAAECgYICQAAAA==.Saturnio:BAAALAADCgcIDQAAAA==.',Sf='Sfuss:BAAALAADCgcIBwAAAA==.',Sh='Shampu:BAAALAADCgUIBQAAAA==.Shando:BAAALAADCggICgAAAA==.Shyrali:BAAALAADCggICAAAAA==.Shâÿ:BAAALAADCggIDgAAAA==.',Si='Sieria:BAAALAADCgUIBQAAAA==.Sigfry:BAAALAADCgQIBAAAAA==.Sinlorei:BAAALAADCgQIBAAAAA==.',Sk='Skeleton:BAAALAADCggIDwAAAA==.Skytorus:BAAALAADCgYIBgAAAA==.',So='Soolahi:BAAALAAECgEIAQAAAA==.',St='Starnight:BAAALAAECgYICAAAAA==.Starshadow:BAAALAADCggICAAAAA==.Stormentor:BAAALAAECgMIBQAAAA==.',Su='Sunetra:BAAALAAECgYICgAAAA==.Supther:BAAALAADCgUIBQAAAA==.',Sy='Sylwën:BAAALAADCgUIBAAAAA==.',['Sæ']='Særiel:BAAALAAECgYICAAAAA==.',Ta='Tanix:BAAALAADCggIDwAAAA==.Tansiss:BAAALAAECgEIAQAAAA==.Taunico:BAAALAADCggIEAAAAA==.',Te='Tekahn:BAAALAADCggICQAAAA==.Terodactilo:BAAALAADCgcIBwAAAA==.',Th='Thebeast:BAAALAADCggIDAAAAA==.Thepøpe:BAAALAAECgMIBAAAAA==.Thornblade:BAAALAAECgYIBgAAAA==.Throrin:BAAALAADCggICQAAAA==.',To='Torkus:BAAALAADCggIDAAAAA==.Totemigneo:BAAALAAECgQIBAAAAA==.',Tr='Trampascaza:BAAALAADCgQIBAAAAA==.Trilko:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.Truerayo:BAAALAAECgIIAgAAAA==.',Ts='Tsukuyômi:BAAALAADCggIFAAAAA==.',Ul='Ulfgürd:BAAALAAECgcIEAAAAA==.',Va='Vardena:BAAALAADCgUIBQAAAA==.',Ve='Verdepicaro:BAAALAAECgEIAQAAAA==.Veresh:BAAALAADCggIDQAAAA==.Verial:BAAALAAECgMIAwAAAA==.',Vi='Vighoc:BAAALAADCggIEAAAAA==.',Wa='Warribum:BAAALAADCggICAAAAA==.',Wi='Wilframe:BAAALAAECgcIEAAAAA==.',['Wô']='Wôlfÿx:BAAALAAECgMIAwAAAA==.',Xa='Xanya:BAAALAADCgYIBgAAAA==.',Xe='Xelia:BAAALAADCgYIBgAAAA==.',Xx='Xxlegol:BAAALAADCgUIBQAAAA==.',Xy='Xyfusino:BAAALAADCgIIAwAAAA==.Xyzxamm:BAAALAADCggIDQAAAA==.',Ya='Yazmine:BAAALAADCgcIBwAAAA==.',Yi='Yis:BAAALAAECgcIEAAAAA==.',Yr='Yrai:BAAALAAECgYIEQAAAA==.Yrelis:BAAALAADCggIDQAAAA==.Yrêll:BAAALAADCgcIBwAAAA==.',Ys='Yserá:BAAALAAECgMIAwAAAA==.',Za='Zamelnar:BAAALAAECgEIAQAAAA==.Zarfi:BAAALAAECgYICgAAAA==.',Ze='Zeykuu:BAAALAADCgcIBwAAAA==.',Zy='Zylenn:BAAALAAECgEIAQAAAA==.',['Äl']='Älfil:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end