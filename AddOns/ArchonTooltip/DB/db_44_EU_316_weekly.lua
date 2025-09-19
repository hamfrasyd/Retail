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
 local lookup = {'Rogue-Assassination','Unknown-Unknown','Hunter-Marksmanship','Paladin-Protection','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','Priest-Shadow','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Mistweaver','Druid-Balance',}; local provider = {region='EU',realm='Neptulon',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abella:BAABLAAECoEWAAIBAAcIZRjbFQAYAgABAAcIZRjbFQAYAgAAAA==.',Ac='Accadius:BAAALAAECgEIAQAAAA==.',Ae='Aevelaine:BAAALAAECgEIAQAAAA==.',Ai='Aibo:BAAALAADCgIIAgABLAADCgcIBwACAAAAAA==.',Ak='Akuma:BAAALAADCggICAAAAA==.',Al='Alarya:BAAALAAECggIAQAAAA==.',Am='Amateria:BAAALAADCggIEgAAAA==.',An='Anthodas:BAAALAAECgYIDgAAAA==.',Ar='Ariannae:BAAALAADCgcIBwABLAAECgYIDAACAAAAAA==.',As='Asminare:BAAALAADCgcICQAAAA==.Asome:BAAALAAECgYICgAAAA==.',Ba='Balta:BAAALAAECgYIDgAAAA==.Barbatheo:BAAALAADCgcIFAAAAA==.',Be='Betongarn:BAAALAAECgYIBgAAAA==.',Bi='Biberka:BAAALAAECgEIAQAAAA==.Bibizdk:BAAALAAECgYIDAAAAA==.Biliana:BAAALAAECgEIAwAAAA==.',Bl='Bladey:BAAALAAECgIIBAAAAA==.Blueais:BAAALAADCggICwAAAA==.',Bo='Boingo:BAAALAAECgIIAgAAAA==.Bokluk:BAAALAAECgUICQAAAA==.Bop:BAAALAADCggICAAAAA==.',Br='Brionac:BAAALAAECgQIBAAAAA==.',Bu='Bubkin:BAAALAADCgIIAgAAAA==.',Ca='Camellya:BAAALAADCgUIBQAAAA==.',Ch='Chicksmagnet:BAAALAADCggIEgAAAA==.Choriest:BAAALAAECgYICAAAAA==.Chorrior:BAAALAADCgMIBAAAAA==.',Cl='Clash:BAAALAADCggIEAAAAA==.',Cr='Cryxus:BAAALAADCggIDwAAAA==.',['Cì']='Cìara:BAAALAADCggIDgAAAA==.',Da='Danail:BAAALAAECgYICwAAAA==.',De='Delé:BAAALAAECgYIDQAAAA==.',Di='Dianiza:BAAALAAECggIEwAAAA==.Distinctive:BAAALAAECgUIBQAAAA==.Ditkaa:BAAALAADCggICAAAAA==.',Do='Doris:BAAALAAECgcIDAAAAA==.',Dp='Dpsheal:BAAALAADCggIFwAAAA==.',Du='Dunderhonung:BAAALAAECgYIDgAAAA==.Durek:BAAALAADCggIDgABLAAECggIAQACAAAAAA==.Duskshade:BAAALAAECgcIBwAAAA==.',Ee='Eechoo:BAAALAADCgcIEAAAAA==.',El='Elamide:BAABLAAECoEUAAIDAAcItAxJNABXAQADAAcItAxJNABXAQAAAA==.Elatemioshte:BAAALAADCggICAAAAA==.',En='Enandia:BAAALAAECggIAQAAAA==.Enjävlademon:BAAALAAECgIIAgAAAA==.',Er='Erinée:BAAALAAECgYIDgAAAA==.',Ey='Eyleen:BAAALAAECgUIBgAAAA==.',Fa='Fairly:BAAALAAECgIIAgAAAA==.Falippas:BAAALAAECgQIBAAAAA==.Fangubangu:BAAALAADCggICAAAAA==.',Fe='Feles:BAAALAAECgYIDgAAAA==.Felisin:BAAALAADCggIHAABLAAECgYIDAACAAAAAA==.',Fj='Fjolnir:BAAALAAECggIEwAAAA==.',Fo='Foreingar:BAAALAADCgcICAAAAA==.',Fr='Freebanz:BAAALAAECgYICwAAAA==.',Fu='Fumika:BAAALAADCggIEAAAAA==.Furaffinity:BAAALAAECgYIDgAAAA==.',Gj='Gjeddi:BAAALAADCggICAAAAA==.',Gl='Gladiatorat:BAAALAAECgcICQAAAA==.',Gr='Grudgebearer:BAAALAADCgYICgAAAA==.Grux:BAAALAAECgcIEAAAAA==.Gróm:BAAALAADCgYICwAAAA==.',Ha='Hamali:BAAALAADCggICAAAAA==.Harshlock:BAAALAADCggICAAAAA==.Haylah:BAAALAADCgcIBwAAAA==.',He='Hearse:BAAALAAECgcICQAAAA==.',Hi='Hillel:BAAALAAECgYICwAAAA==.',Hy='Hydonna:BAAALAAECgcIEgAAAA==.',In='Inorog:BAAALAAECgYIBwABLAAECggIDgACAAAAAA==.Involka:BAAALAADCgcIBwAAAA==.',It='Ithira:BAAALAAECgEIAQAAAA==.',Ja='Jackdragon:BAAALAAECgYIDgAAAA==.Jafree:BAAALAADCgUIBQAAAA==.Janienight:BAAALAAECgcIEgAAAA==.',Je='Jeonsa:BAAALAAECgcIEgAAAA==.',['Jö']='Jörd:BAAALAAECgQIBgAAAA==.',Ka='Kalrush:BAAALAAECgUICgAAAA==.Kangaro:BAAALAAECgYIBgAAAA==.Karlsons:BAAALAAECgYIDAAAAA==.Karnivall:BAAALAAECgQIBwAAAA==.',Ke='Kementári:BAAALAAECgQIBgAAAA==.',Kl='Klodrik:BAAALAAECgIIAwAAAA==.',Ko='Kolossen:BAAALAAECgUIBwAAAA==.',Kr='Krisona:BAAALAAECgMIAwAAAA==.',Ku='Kufa:BAAALAAECgIIAgAAAA==.',['Kö']='Körösi:BAAALAADCggIEQAAAA==.',La='Lasaros:BAAALAADCggICAAAAA==.',Le='Lebiath:BAAALAADCgYIDAAAAA==.Leh:BAAALAAECgYIEQAAAA==.Lennaa:BAAALAADCggICAAAAA==.',Li='Littlehunter:BAAALAADCgUIBQAAAA==.',Ma='Magint:BAAALAADCggICAAAAA==.Maikâti:BAAALAAECgYICwAAAA==.Majrum:BAAALAADCggICAABLAAECggIDgACAAAAAA==.Makashi:BAAALAAECgIIAwAAAA==.Malavett:BAAALAAECgQICAAAAA==.Malevolent:BAAALAAECgcICAAAAA==.Maniackillez:BAAALAADCggICwAAAA==.Manusbanus:BAAALAADCgQIBAAAAA==.',Mo='Mobsong:BAAALAADCggICAAAAA==.Moonpig:BAAALAAECggIDgAAAA==.Mortimmer:BAAALAADCggICAAAAA==.',['Mó']='Mórrigan:BAAALAAECggIEAAAAA==.',Ne='Nerthol:BAAALAADCgcIBwAAAA==.',Ni='Nicki:BAAALAADCggICQAAAA==.Nicky:BAAALAAECgYIBgAAAA==.',Nn='Nn:BAAALAADCggICAAAAA==.',No='Norkenis:BAAALAAECgUIBgAAAA==.',Nt='Ntavos:BAAALAADCggIHAAAAA==.Ntavoss:BAAALAADCgcIEwAAAA==.',['Nê']='Nêrf:BAAALAAECgYIBwAAAA==.',Om='Ompom:BAAALAAECggIDgAAAA==.',Op='Opolainen:BAAALAAECgYIDQAAAA==.',Or='Ora:BAAALAAECgYIDAAAAA==.',Pa='Palalry:BAABLAAECoEUAAIEAAUItSACEADXAQAEAAUItSACEADXAQABLAAFFAUICgAFABQaAA==.Panakos:BAAALAAECgYIBwAAAA==.Patologa:BAAALAAECgYIEgAAAA==.',Pe='Pelenope:BAAALAAECgYICQAAAA==.',Pi='Pichpunta:BAAALAAECgUICgAAAA==.',Pr='Praetorian:BAAALAADCggIEAAAAA==.',Ps='Psofoskilo:BAAALAADCggIEwAAAA==.',Ra='Ragnos:BAAALAAECgMIAwAAAA==.Ragny:BAAALAADCggIGgAAAA==.Ramlethal:BAAALAAECgYIDAAAAA==.Ravaz:BAAALAADCggICAABLAAECgYIDgACAAAAAA==.Ravingdr:BAABLAAECoEUAAMGAAcIOgiXEwA4AQAGAAcIOgiXEwA4AQAHAAEIXwfOQwA0AAAAAA==.',Ro='Rodia:BAAALAAECgYICgAAAA==.Rontina:BAAALAADCggICAAAAA==.Roupas:BAAALAAECgQIBAAAAA==.',Ry='Ryuutatsu:BAAALAADCggIFgABLAAECgYIDAACAAAAAA==.',Sa='Sabercrown:BAAALAADCgcIBwAAAA==.',Sc='Scaryowl:BAAALAADCgcIBwAAAA==.',Se='Seenoend:BAAALAAECgYIEQAAAA==.Seraphin:BAAALAAECgYICQAAAA==.',Sh='Shaboom:BAAALAADCggIDQAAAA==.Shikishi:BAAALAADCgcICQABLAAECgYIDAACAAAAAA==.Shizo:BAACLAAFFIELAAIIAAQIFxiYAgBeAQAIAAQIFxiYAgBeAQAsAAQKgR0AAggACAgfIPQJAOYCAAgACAgfIPQJAOYCAAAA.',Si='Siggae:BAAALAAECgIIBgAAAA==.',So='Soricelul:BAABLAAECoEWAAIJAAcIFBVKPQDfAQAJAAcIFBVKPQDfAQAAAA==.Sosmo:BAABLAAECoEXAAMKAAgIUSEhBgCjAgAKAAcIuiEhBgCjAgALAAUIGhsxPwB5AQAAAA==.Souzi:BAAALAADCgcICQAAAA==.',Sp='Spankingnew:BAAALAAECgYIDAAAAA==.Spellzy:BAAALAADCgYIBgAAAA==.',St='Stenåkedh:BAABLAAECoEXAAIMAAcILSN0BAC/AgAMAAcILSN0BAC/AgAAAA==.Stenåkedruid:BAAALAADCggICAAAAA==.Stenåkewar:BAAALAADCggIGAAAAA==.Stormleaf:BAAALAAECgYIDAAAAA==.Stormshaman:BAAALAADCggIEwAAAA==.',Su='Sunra:BAAALAAECgYICQAAAA==.',Ta='Taodh:BAABLAAFFIEKAAINAAMIbBkEBQAcAQANAAMIbBkEBQAcAQAAAA==.Taopal:BAAALAAFFAIIAgABLAAFFAMICgANAGwZAA==.',Te='Tephereth:BAAALAAECggIBAAAAA==.Tezzeret:BAAALAAECgIIAgAAAA==.',Th='Thepromise:BAACLAAFFIEGAAIOAAMIwCWMAQBVAQAOAAMIwCWMAQBVAQAsAAQKgRgAAg4ACAiPJjwAAIQDAA4ACAiPJjwAAIQDAAAA.Theri:BAAALAADCggIHwABLAAECgYIDAACAAAAAA==.Therianna:BAAALAAECgYIDAAAAA==.Thorgriph:BAAALAAECgYIDQAAAA==.Thunderlara:BAAALAAECgYICAAAAA==.',To='Tonni:BAAALAADCggIEAAAAA==.Torparn:BAAALAAECgYIBgAAAA==.',Ug='Uglyone:BAAALAAECgYIDAAAAA==.',Va='Valimar:BAAALAAECggICwAAAA==.',Ve='Veesie:BAAALAAECgcICAAAAA==.Ventura:BAAALAAECgMIAwAAAA==.',Vo='Vodoo:BAAALAAECgYIDAAAAA==.Volerac:BAAALAADCggICAAAAA==.',Wh='Whitephantom:BAAALAADCgcIDgAAAA==.',Wi='Wizzles:BAAALAADCgcIBwABLAAECgIIAgACAAAAAA==.',Wo='Wonda:BAAALAAECgcICwAAAA==.Woozles:BAAALAAECgIIAgAAAA==.',Xa='Xa:BAAALAAECgUIAwAAAA==.',Xy='Xysamolias:BAAALAAECgQIBAAAAA==.',Yu='Yuly:BAAALAADCgEIAQAAAA==.',Yw='Yw:BAAALAAECgYIEgAAAA==.',Za='Zagrem:BAAALAAECgUIBQAAAA==.Zannah:BAAALAAECgIIAgAAAA==.',Zo='Zoë:BAACLAAFFIEFAAIPAAIItxWqCACjAAAPAAIItxWqCACjAAAsAAQKgR8AAg8ACAhKIrwGAAsDAA8ACAhKIrwGAAsDAAAA.',Zu='Zugu:BAAALAADCgcIBgAAAA==.Zuriel:BAAALAAECgYIDAAAAA==.',['Ûf']='Ûfø:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end