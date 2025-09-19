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
 local lookup = {'Priest-Holy','DeathKnight-Frost','Shaman-Elemental','Unknown-Unknown','Shaman-Restoration','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker',}; local provider = {region='EU',realm="Nera'thor",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abbrechen:BAAALAADCgcIBwAAAA==.',Ae='Aelyn:BAAALAAECgcIDgAAAA==.',Al='Alere:BAAALAADCgcIBwAAAA==.Alraik:BAAALAADCggIFQAAAA==.Alukat:BAAALAAECgMIAwAAAA==.',Am='Amarea:BAAALAADCggIDgAAAA==.',An='Antenne:BAAALAAECgEIAQAAAA==.Anyla:BAABLAAECoEUAAIBAAcIXBi+FQAVAgABAAcIXBi+FQAVAgAAAA==.',Ap='Apøkalypse:BAAALAAECgYIBgAAAA==.',Ar='Aríena:BAAALAAECgEIAQAAAA==.',As='Astá:BAAALAADCgYIBwAAAA==.',Ba='Babaiga:BAAALAADCggIEAAAAA==.Bantu:BAAALAAECgYIDQAAAA==.',Be='Behindokles:BAAALAAECgMIAwAAAA==.Beláh:BAAALAAECgQIBgAAAA==.Benjie:BAAALAAECgIIAgAAAA==.',Bl='Blackovero:BAAALAAECgQIBgAAAA==.',Br='Brewmi:BAAALAAECgYICwAAAA==.',Ca='Caliim:BAAALAADCggIDgAAAA==.Catwalk:BAAALAADCgUIBQAAAA==.',Ce='Cecilia:BAAALAAECgMIBAAAAA==.',Ch='Chox:BAAALAADCgcIBwAAAA==.',Co='Coljin:BAAALAAECgEIAQAAAA==.',Cr='Crypticsham:BAAALAAECgYIBwAAAA==.',Cu='Cuja:BAAALAAECgIIAgAAAA==.',Da='Dampfwalze:BAABLAAECoETAAICAAgIeBUuKQDsAQACAAgIeBUuKQDsAQAAAA==.Darethas:BAAALAAECgEIAQAAAA==.',De='Destt:BAAALAAECgEIAQAAAA==.',Di='Direnia:BAAALAAECgQIBgAAAA==.',Dj='Djoker:BAAALAADCgEIAQAAAA==.',Dr='Dracomorph:BAAALAADCggIBwAAAA==.Drixxi:BAAALAADCgEIAQAAAA==.',Du='Durchbrechen:BAAALAADCggICAAAAA==.',['Dê']='Dêâthwêâpôn:BAAALAAECgEIAQAAAA==.',['Dó']='Dórin:BAAALAAECgEIAQAAAA==.',El='Elaidien:BAAALAADCgUIBQAAAA==.Eldor:BAAALAADCggICAAAAA==.',Er='Erikohu:BAAALAAECgYICQAAAA==.',Gh='Ghart:BAAALAAECgEIAQAAAA==.',Gr='Greenarrow:BAAALAAECgYIBgAAAA==.Gronkash:BAAALAAECgMIBQAAAA==.',Gu='Gundrabur:BAAALAAECgYIBgABLAAECggIFwADAJQgAA==.',Gw='Gwenselah:BAAALAAECgIIAgAAAA==.',Ha='Hasu:BAAALAAECgYIDAAAAA==.',He='Heavyweigth:BAAALAAECgUIBwAAAA==.Heiliheili:BAAALAADCggICAAAAA==.Helfgar:BAAALAADCgcIBwAAAA==.Hellfirex:BAAALAADCggICAAAAA==.Hellokritty:BAAALAADCgEIAQAAAA==.Hexenmensch:BAAALAAECgYICAAAAA==.',Hj='Hjörthrimul:BAAALAAECgEIAQAAAA==.',Ho='Hoopi:BAAALAADCgcIBwAAAA==.Houdiny:BAAALAADCgMIAwAAAA==.',Ig='Igna:BAAALAAECgMIBAAAAA==.',Il='Ilari:BAAALAADCgcIBwABLAAECgEIAQAEAAAAAA==.',Ja='Javano:BAAALAADCgEIAQAAAA==.',Ju='Junkzresz:BAAALAAECgMIAwAAAA==.',['Jé']='Jénara:BAAALAADCgMIBAAAAA==.',Ka='Kahrandor:BAAALAAECgQIBgAAAA==.Kaldêa:BAAALAADCgcICAAAAA==.Karakil:BAAALAADCggICQAAAA==.Katrol:BAAALAAECgEIAQAAAA==.',Ke='Kerodoro:BAAALAAECgQIBwAAAA==.Kessina:BAAALAADCgMIAwAAAA==.Keughor:BAAALAAECgIIAgAAAA==.',Ki='Kilerion:BAAALAADCggIDwAAAA==.Kimmuriell:BAAALAADCgcIBwAAAA==.',Kr='Krazuul:BAAALAADCgQIBAAAAA==.Krâghor:BAAALAADCggIAgAAAA==.',Ku='Kuliser:BAAALAADCgcIBwAAAA==.',La='Lanayaa:BAAALAAECgYIBgABLAAECgcIDgAEAAAAAA==.',Le='Legit:BAABLAAECoEUAAIFAAgIlSH1AQAdAwAFAAgIlSH1AQAdAwAAAA==.Legnilk:BAAALAAECgYIDAAAAA==.Lemurica:BAAALAAECgMIAwAAAA==.',Li='Lizeth:BAAALAADCggIEAAAAA==.',Lo='Lorakus:BAAALAADCgMIAwAAAA==.Lothenón:BAAALAADCgcIBwAAAA==.',Ly='Lyndi:BAAALAADCgUICAAAAA==.',Ma='Maddor:BAAALAAECgYICQAAAA==.Marcellã:BAAALAADCggICQAAAA==.Maxheal:BAAALAADCgEIAQABLAADCggICAAEAAAAAA==.',Me='Merut:BAAALAADCggIDAAAAA==.',Mi='Micanopy:BAAALAADCggICQAAAA==.Mixcoatl:BAAALAAECgEIAQAAAA==.',Mo='Moonpox:BAAALAADCgYIBgAAAA==.Moonpoxdk:BAAALAAECgMIBQAAAA==.Moroge:BAABLAAECoEYAAIGAAgI3iJrBAD/AgAGAAgI3iJrBAD/AgAAAA==.Moê:BAAALAAECgEIAQAAAA==.',['Má']='Máddox:BAAALAADCggICAAAAA==.',Na='Nahara:BAAALAAECgYIDQAAAA==.Naicon:BAAALAADCggICAABLAAECgYICgAEAAAAAA==.Nanaki:BAAALAADCggICAAAAA==.',Ne='Nebuchar:BAAALAAECgEIAQAAAA==.',Ni='Nightysra:BAAALAADCgUIBQAAAA==.Nineoneone:BAAALAADCggIDgAAAA==.',No='Nockchan:BAAALAAECgQICgAAAA==.Nokivaris:BAAALAADCgcICAAAAA==.',Od='Odetta:BAAALAADCgEIAQAAAA==.',Os='Ossî:BAAALAAECgEIAQAAAA==.',Pi='Pizdation:BAAALAADCgcIBwAAAA==.',Pr='Priwardina:BAAALAAECgUIDAAAAA==.',Pv='Pvphealsham:BAAALAAECgYIEgABLAAECggIFwADAJQgAA==.',Qd='Qdww:BAAALAAECgYIBgAAAA==.',Qu='Quixxi:BAAALAAECgIIAgAAAA==.',Ra='Raisana:BAAALAADCgIIAgAAAA==.Raltar:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.Ralunara:BAAALAADCgEIAQAAAA==.',Re='Ready:BAAALAAECgMIAwAAAA==.Reifn:BAAALAAECgMIBQAAAA==.Respektive:BAAALAADCgUIBQAAAA==.',Ri='Rikolo:BAAALAAECgMIAwABLAAECgYICwAEAAAAAA==.',Ru='Rumî:BAAALAAECgUIBwAAAA==.',['Râ']='Râfiki:BAAALAAECgYIBwABLAAECggIFwADAJQgAA==.',Sc='Sceltury:BAAALAADCgcICQAAAA==.Schlemil:BAAALAADCgcIBwAAAA==.Schnauze:BAAALAADCggIEAAAAA==.',Se='Serphiron:BAAALAADCgcIBwAAAA==.Seröga:BAAALAAECgQIBgAAAA==.',Sh='Shali:BAAALAADCggIDwAAAA==.Sharokin:BAAALAAECgQIBgAAAA==.Shaukai:BAAALAAECgIIAgAAAA==.Shenya:BAAALAADCggIFgAAAA==.Sherrena:BAAALAAECgEIAQAAAA==.Sháy:BAAALAAECgEIAQAAAA==.',Si='Simboon:BAAALAAECgIIAgAAAA==.',Sn='Snowx:BAAALAADCggIHwAAAA==.',So='Sombara:BAAALAADCggIDwAAAA==.Soulkiss:BAAALAAECgEIAQAAAA==.',Sp='Spritti:BAAALAAECgMIBAAAAA==.',Sy='Syrùss:BAAALAADCgcIBwAAAA==.',['Sá']='Sálith:BAAALAADCgcIBgAAAA==.',['Sâ']='Sâsûke:BAAALAAECgYICwAAAA==.',Ta='Taric:BAAALAADCgQIBAAAAA==.',Te='Teflon:BAAALAAECgYIBgAAAA==.Tentacuru:BAAALAADCgEIAQAAAA==.Teranodon:BAAALAADCgcIBwAAAA==.Tessã:BAAALAADCgcIDQAAAA==.',Th='Thrain:BAAALAADCgMIAwAAAA==.',To='Tohuwabohu:BAAALAAECgYICQAAAA==.',Tr='Triage:BAAALAAECgYIDwAAAA==.',Ty='Tyronny:BAAALAAECgYIBwAAAA==.',Ul='Ultraradikal:BAAALAAECgEIAQAAAA==.',Ur='Uriel:BAAALAADCgUIBQAAAA==.',Uw='Uwe:BAAALAAECgYICQAAAA==.',Va='Vahyna:BAAALAAECgEIAQAAAA==.',Ve='Veni:BAAALAADCggIDwAAAA==.',Wa='Waitandbleed:BAAALAADCgcIBwAAAA==.Waxer:BAAALAAECggIDAAAAA==.',Wi='Wickedy:BAAALAAECgQIBgAAAA==.',Wu='Wukkuschukku:BAABLAAECoEXAAMDAAgIlCB0BwDxAgADAAgIlCB0BwDxAgAFAAEIVATmigAnAAAAAA==.',['Wî']='Wîkkîschîkkî:BAAALAAECgYIDwAAAA==.',['Wú']='Wúkkú:BAAALAAFFAIIAgAAAA==.Wúkkúschúkkú:BAAALAAECgYIEQAAAA==.',['Wû']='Wûkkû:BAAALAADCgEIAQABLAAECggIFwADAJQgAA==.Wûkkûschûkkû:BAAALAAECgcIEwABLAAECggIFwADAJQgAA==.',Yu='Yubel:BAAALAADCggICgAAAA==.',Zi='Ziplos:BAABLAAECoEWAAMHAAgIoCTPAABfAwAHAAgIoCTPAABfAwAIAAYIPQtNHQAKAQAAAA==.',['Àu']='Àurøra:BAAALAADCgcICQAAAA==.',['Êl']='Êlune:BAAALAADCgIIAgAAAA==.',['Êm']='Êmmely:BAAALAADCgcIDQAAAA==.',['Ën']='Ënurfala:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end