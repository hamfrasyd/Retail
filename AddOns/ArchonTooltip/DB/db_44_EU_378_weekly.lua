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
 local lookup = {'Paladin-Retribution','Unknown-Unknown','DeathKnight-Blood','Warrior-Fury','Paladin-Holy','DemonHunter-Havoc','Warrior-Protection','Shaman-Elemental','Rogue-Assassination','Priest-Holy','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Evoker-Preservation','Evoker-Devastation','Warlock-Affliction','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Windwalker',}; local provider = {region='EU',realm='LesSentinelles',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abizarde:BAAALAADCggIDwAAAA==.',Ae='Aenkhil:BAAALAAECgEIAQAAAA==.',Ai='Aiwendil:BAAALAADCggIDwAAAA==.',Ak='Akibà:BAAALAAECgUICAAAAA==.',Al='Alarön:BAAALAAECgUICAAAAA==.Alatranos:BAAALAADCgcICgAAAA==.Aldarion:BAABLAAECoEXAAIBAAgIeyOdBwARAwABAAgIeyOdBwARAwAAAA==.Aldri:BAAALAADCggIEAAAAA==.Alfgaard:BAAALAADCggIDAAAAA==.Allayä:BAAALAAECgUIBQABLAAECgYICgACAAAAAA==.Alleya:BAAALAADCgcIBAAAAA==.Alyndel:BAAALAAECgIIAgAAAA==.',Am='Amaranthia:BAAALAADCggIFQAAAA==.Ambrê:BAAALAADCgIIAgAAAA==.Amerästlin:BAAALAAECgEIAQAAAA==.',An='Andromiä:BAAALAADCgcICAAAAA==.Angelzide:BAAALAADCggIFQAAAA==.Annarchïe:BAAALAADCggIEQAAAA==.Annha:BAAALAAECgIIAgAAAA==.Antiquetama:BAAALAADCgcIBwAAAA==.Anyway:BAAALAAECgIIAgAAAA==.',Aq='Aque:BAABLAAECoEWAAIDAAgI1hTfBwD+AQADAAgI1hTfBwD+AQAAAA==.',Ar='Aralma:BAAALAAECgYICgAAAA==.Arc:BAAALAAECgMIBAAAAA==.Arcaniakya:BAAALAAECgMIBAAAAA==.Arckaytos:BAAALAAECgEIAQAAAA==.Arckwell:BAABLAAECoEXAAIEAAgIbyOCBgANAwAEAAgIbyOCBgANAwAAAA==.Argenté:BAAALAAECgMIBQAAAA==.Arisu:BAAALAAECgYIBgAAAA==.Arkaolass:BAAALAADCggIFwAAAA==.Arkhalys:BAAALAADCggICAABLAAECgUICAACAAAAAA==.Artarax:BAAALAADCggICAAAAA==.',As='Ashänä:BAAALAAECgYICgAAAA==.Asrakan:BAAALAADCgcIDAAAAA==.Astringent:BAAALAAECgMIBgAAAA==.Asùnàa:BAAALAADCggICAAAAA==.',At='Atasse:BAAALAAECggICgAAAA==.Atlasforge:BAAALAADCgQIBAABLAADCggICAACAAAAAA==.Atriam:BAAALAADCgYIBgAAAA==.',Au='Auldren:BAAALAADCgcIBwAAAA==.Auriuss:BAABLAAECoEUAAIFAAgIPgskGACIAQAFAAgIPgskGACIAQAAAA==.',Av='Avalyna:BAAALAADCgMIAwAAAA==.Aveløna:BAAALAADCgUIBQAAAA==.',Ay='Ayayamédoi:BAAALAADCgcIBwAAAA==.',Az='Azer:BAAALAADCgcIEgAAAA==.Azgaröth:BAAALAAECgMIAwAAAA==.Azsara:BAAALAAECgcIDAAAAA==.',['Aë']='Aërynn:BAAALAADCgQIBAAAAA==.',Ba='Babaoer:BAAALAADCgUIBwAAAA==.Baelhrim:BAAALAADCggIGAABLAAFFAQICQAGAM4bAA==.Balmüng:BAAALAADCgYIDAAAAA==.Banjo:BAAALAAECgUICAAAAA==.Barbeu:BAAALAAECgMIBgAAAA==.Basajaun:BAAALAAECgMIAwAAAA==.Batpims:BAAALAAECgYICgAAAA==.',Be='Beautté:BAAALAADCgcIBwAAAA==.Beledrel:BAAALAADCggIEAAAAA==.Beliora:BAAALAAECgEIAQAAAA==.',Bi='Bigbong:BAAALAAECgQICAAAAA==.',Bl='Blackbétty:BAAALAAECgQICQAAAA==.Bluecat:BAAALAADCgcIDAAAAA==.',Bo='Bong:BAAALAADCgQIBAAAAA==.Boodzin:BAAALAAECgYICQAAAA==.Borsdeganis:BAAALAAECgMIAwAAAA==.Botados:BAAALAADCgMIAwAAAA==.',Br='Bratata:BAAALAAECgMIBgAAAA==.Brodering:BAAALAAECgEIAQAAAA==.Brousselee:BAAALAADCgYIBgAAAA==.',['Bä']='Bälä:BAAALAAECgQIBAAAAA==.',['Bë']='Bën:BAAALAADCggICAAAAA==.',['Bö']='Böodzin:BAAALAAECggIEwAAAA==.',Ca='Caine:BAAALAADCggIDwAAAA==.Calpin:BAAALAAECgQICgAAAA==.Calyonia:BAAALAAECgUICAAAAA==.Calypsïa:BAAALAAECgMIBQAAAA==.Cathari:BAAALAAECgIIAgAAAA==.',Ch='Chamboultout:BAAALAAECgIIAgAAAA==.Chamity:BAAALAAECgYICwAAAA==.Charaminus:BAAALAAECgYICQAAAA==.Chassøugrøk:BAAALAADCgEIAQAAAA==.Chiassou:BAAALAAECgMIAwAAAA==.Chrisdlbe:BAAALAAECgIIAgAAAA==.Châma:BAAALAAECgUICAAAAA==.Châmïnøûx:BAAALAAECgcICQAAAA==.',Ci='Cil:BAAALAADCgYIBgAAAA==.Ciloka:BAAALAAECgIIBQAAAA==.Cirilla:BAAALAAECgYIEAAAAA==.',Co='Comentaë:BAAALAADCggICAAAAA==.Concordia:BAAALAAECgUIBwAAAA==.Connelly:BAAALAADCggIEAAAAA==.Corbhen:BAAALAAECgIIBQAAAA==.Cornederock:BAAALAADCggIDQAAAA==.Corsobrain:BAAALAADCggICAAAAA==.',Cr='Crazyhorse:BAAALAAECgYICgAAAA==.',Cu='Culmihunt:BAAALAAECgcIEwAAAA==.',Cy='Cykø:BAAALAADCgcIDQAAAA==.',Da='Daemess:BAAALAAECgUIBgAAAA==.Daemonum:BAAALAADCgIIAgABLAAECgIIAgACAAAAAA==.Dagroth:BAAALAAECgYIDgAAAA==.Dargho:BAAALAADCgcICwAAAA==.Dariun:BAAALAAECgQICgAAAA==.Darkelves:BAAALAADCgcIBwAAAA==.Dayria:BAAALAAECgEIAQAAAA==.',De='Deamoon:BAAALAAECgEIAQAAAA==.Delekhan:BAAALAADCgcIBwAAAA==.Demonus:BAAALAADCgcIBwAAAA==.Desmo:BAAALAADCgUIBQAAAA==.Devï:BAAALAADCgcIFwAAAA==.',Dh='Dhstos:BAAALAADCggICAABLAAFFAUICwAHAN4YAA==.',Di='Diaboliques:BAAALAADCgcIBwAAAA==.Diabölo:BAAALAADCggIEAAAAA==.Dionysos:BAAALAADCgcIBgAAAA==.',Dk='Dkalipso:BAAALAAECgYIBgABLAAECgYICQACAAAAAA==.Dkartash:BAAALAAECgEIAQAAAA==.Dkcontact:BAAALAAECgMIAwAAAA==.Dkstos:BAAALAAECggIBgABLAAFFAUICwAHAN4YAA==.',Do='Dodokx:BAAALAAFFAMIAwAAAA==.',Dr='Draagons:BAAALAADCgYIBgAAAA==.Dracoshin:BAAALAADCggIDAAAAA==.Dracouille:BAAALAADCggIAgAAAA==.Dranreb:BAAALAAECggIDAAAAA==.Dreksha:BAAALAADCggIEAAAAA==.Dreïchame:BAAALAAECgYICgAAAA==.Drhall:BAAALAAECgYIBAAAAA==.Drokeine:BAAALAADCgIIAgAAAA==.Droni:BAAALAADCggIEAAAAA==.Drøødistø:BAAALAADCggICAAAAA==.',Du='Durin:BAAALAADCgUIBQAAAA==.',['Dà']='Dàvin:BAAALAADCgIIAgAAAA==.',['Dä']='Därgach:BAAALAAECgMIAwAAAA==.Därktemplär:BAAALAAECgIIBQAAAA==.',['Dæ']='Dædæ:BAAALAAECgEIAQAAAA==.',['Dé']='Déjanhÿre:BAAALAAECgcIDwAAAA==.Délios:BAAALAADCgYIDwAAAA==.Démodarce:BAAALAAECgMIAwAAAA==.',['Dø']='Døxie:BAAALAAECgIIBAAAAA==.',Ec='Echnida:BAAALAAECgMIAQAAAA==.Ecsy:BAAALAAFFAEIAQAAAA==.',Ee='Eearg:BAAALAADCgMIAwAAAA==.',El='Elaedre:BAAALAAECggIEgAAAA==.Elenay:BAABLAAFFIENAAIIAAUIcCF8AAAHAgAIAAUIcCF8AAAHAgABLAAFFAEIAQACAAAAAA==.Elentàri:BAAALAADCgEIAQAAAA==.Eleona:BAAALAAECgcIEAAAAA==.Elerinne:BAAALAADCgcIBwAAAA==.Elfitt:BAAALAADCggIEAAAAA==.Eliannore:BAAALAADCggICAAAAA==.Eliàr:BAAALAADCggICAAAAA==.Elkwe:BAAALAAECgMIAwAAAA==.Ellanya:BAAALAAECgEIAQAAAA==.Elythas:BAAALAAECggIDwAAAA==.Elytisa:BAAALAADCggIEwAAAA==.',En='Enderion:BAAALAAECgIIAgAAAA==.Eneldral:BAAALAAECgYICwAAAA==.Enøxïs:BAAALAAECgIIAgAAAA==.',Er='Erakas:BAAALAAECgMIBQAAAA==.Ereldia:BAAALAAECgIIAgAAAA==.Ergheïz:BAAALAAECgMIBwAAAA==.Erikson:BAAALAADCggICQAAAA==.',Es='Estime:BAAALAADCggICAAAAA==.',Et='Ethelin:BAAALAAECgMIBQAAAA==.',Ev='Evangélique:BAAALAAECgcIDwAAAA==.',Ew='Ewilliam:BAAALAAECggIEgAAAA==.',Ey='Eyna:BAAALAADCgYIBgAAAA==.Eywä:BAAALAADCgUIBQAAAA==.',Fa='Fable:BAAALAADCgcIBwAAAA==.Faelar:BAAALAAECgIIBQAAAA==.Fahfnyre:BAAALAAFFAIIAgAAAA==.Fantominus:BAAALAAECgYICQAAAA==.Fatalfifou:BAAALAADCgcICgAAAA==.',Fi='Fiftifent:BAAALAADCgUIBQAAAA==.',Fo='Fofolla:BAAALAAECgEIAQAAAA==.Fos:BAAALAADCgEIAQAAAA==.',Fu='Fur:BAAALAAECgIIAgAAAA==.Futioo:BAAALAAECgQIBAAAAA==.',Fy='Fyron:BAAALAAECgYIBgAAAA==.',['Fâ']='Fâûst:BAAALAADCgEIAQAAAA==.',Ga='Galaxïe:BAAALAADCgcICwAAAA==.Galladrïelle:BAAALAAECgYICgAAAA==.Garmel:BAAALAAECgIIAgAAAA==.',Ge='Gekkido:BAAALAADCggIDQAAAA==.',Gi='Gigashad:BAAALAAECgIIBAAAAA==.',Gl='Glywailla:BAAALAADCgcIBwAAAA==.Glëm:BAAALAAECgYIBgAAAA==.Glïn:BAAALAAECgUIBgAAAA==.',Go='Gohez:BAAALAADCgYIBgAAAA==.Gohtt:BAAALAAECgEIAQAAAA==.Gonzaï:BAAALAADCgYIBgAAAA==.Gorba:BAAALAAECgIIAwAAAA==.Gorkanor:BAAALAADCgMIAwAAAA==.',Gr='Granitte:BAAALAAECgEIAQAAAA==.Grasdoubles:BAAALAAECgMIBQAAAA==.Gremzz:BAAALAADCggIDAAAAA==.Grimmbibine:BAAALAAECgIIAgAAAA==.Gronack:BAAALAAECgMIAwAAAA==.Gronit:BAAALAAECggIEgAAAA==.Grumpherious:BAAALAAECgEIAQAAAA==.',Gu='Guilvor:BAAALAAECgUICAAAAA==.',Ha='Haawa:BAAALAAECgMIBAAAAA==.Harleycouine:BAAALAAECgMIAwAAAA==.',He='Hellelyn:BAAALAAECgEIAQAAAA==.Hereliane:BAAALAADCgMIAwAAAA==.',Hi='Hizatis:BAAALAADCgEIAQAAAA==.',['Hé']='Héïmdal:BAAALAADCgcIBwAAAA==.',['Hï']='Hïsako:BAAALAADCgYIBgAAAA==.',Il='Il:BAAALAAECgMIBQAAAA==.Ilythiel:BAABLAAECoEXAAIFAAgIERI7DgD6AQAFAAgIERI7DgD6AQAAAA==.',Im='Imelda:BAAALAADCggICAAAAA==.',In='Inorï:BAAALAAECgQIBQAAAA==.',Ir='Irigiana:BAAALAADCggICAAAAA==.',It='Itash:BAAALAADCgYIBwAAAA==.Itsqpbro:BAAALAAECgMIBAAAAA==.',Ja='Jackdaw:BAABLAAECoEWAAIJAAcILSN8BgDZAgAJAAcILSN8BgDZAgAAAA==.Janaa:BAAALAAECgQIBgAAAA==.',Je='Jergoulin:BAAALAAFFAIIAgAAAA==.',Ji='Jiren:BAAALAADCggIEAAAAA==.',Jk='Jkø:BAAALAADCgIIAgAAAA==.',Jo='Jorkou:BAAALAAECgQIBQAAAA==.',Jp='Jpsartre:BAAALAADCgYIDAAAAA==.',Ju='Jundrood:BAAALAADCgMIAwAAAA==.',['Jö']='Jök:BAAALAAECgMIAQAAAA==.Jörmüngandr:BAAALAADCgcIBwAAAA==.',['Jù']='Jùlïûs:BAAALAAECggICAAAAA==.',Ka='Kaelis:BAAALAADCggIEAAAAA==.Kaina:BAAALAAECgYICgAAAA==.Karmalyne:BAAALAADCgcICgABLAADCgcIFAACAAAAAA==.Karmha:BAAALAADCgcIFAAAAA==.Kartash:BAAALAADCgUIBQAAAA==.Kathlëen:BAAALAAECggICQAAAA==.Kawhileonard:BAAALAAECgEIAQAAAA==.Kayhg:BAAALAAECgMIBgABLAAECgQIBAACAAAAAA==.Kaylïn:BAAALAADCggIEAAAAA==.',Ke='Kenpashï:BAAALAAECgEIAQAAAA==.Kerela:BAABLAAECoEWAAIKAAgIZh9dBwDFAgAKAAgIZh9dBwDFAgAAAA==.Keyg:BAAALAADCggICAABLAAECgQIBAACAAAAAA==.Keygg:BAAALAAECgQIBAAAAA==.',Kh='Khyrrëon:BAAALAAECgMIBgAAAA==.Khâstor:BAAALAADCgQIBAAAAA==.',Ki='Kimoa:BAAALAAECgYICgAAAA==.',Ko='Korzgohk:BAAALAADCggIEAAAAA==.',Ku='Kuraoni:BAAALAAECgEIAQAAAA==.Kuzgrim:BAAALAADCgEIAQAAAA==.',Kw='Kwaftt:BAAALAADCggIDgAAAA==.',Ky='Kylians:BAAALAAECgIIAgAAAA==.',['Kâ']='Kâyna:BAAALAADCgcIBwAAAA==.',['Kä']='Käarbonizey:BAAALAAECgYIBgAAAA==.',['Kå']='Kålípsø:BAAALAAECgYICQAAAA==.',['Kï']='Kïdd:BAAALAADCggICAAAAA==.',['Kÿ']='Kÿry:BAAALAAECgYICwABLAAECggIFwALAP4bAA==.',La='Lanfeär:BAAALAADCggIDwAAAA==.Langenøir:BAAALAAECgYICwAAAA==.Lapattefolle:BAAALAAECggIDAAAAA==.Larome:BAAALAADCggIFgAAAA==.Laru:BAAALAAECgIIAgAAAA==.Lastache:BAAALAADCgEIAQABLAAECgUIBQACAAAAAA==.Launna:BAAALAAECgQIBQAAAA==.Laurah:BAAALAADCgcIDgAAAA==.Layenne:BAAALAAECgIIBQAAAA==.Laïrae:BAAALAADCggIDwAAAA==.',Le='Leezza:BAAALAADCgYIDgAAAA==.Lella:BAAALAAECgIIAgAAAA==.Lemagequietf:BAAALAAECgEIAQAAAA==.Leyaria:BAAALAADCggIEAAAAA==.Leîna:BAAALAADCgIIAgABLAADCggIEAACAAAAAA==.',Li='Lichendh:BAAALAAECgMIBgAAAA==.Lightners:BAAALAAECgIIBAAAAA==.Linowa:BAAALAAECgMIAwAAAA==.Lisambre:BAAALAADCggIEAAAAA==.Liyell:BAAALAADCgYICwAAAA==.',Lo='Lockstock:BAAALAAECgYIBgAAAA==.Lothram:BAAALAADCggICAAAAA==.',Lu='Ludmi:BAAALAADCggIDQAAAA==.Lumièra:BAAALAADCgYIBgAAAA==.',Ly='Lyndia:BAAALAAECgEIAQABLAAECggIFwAHAPklAA==.Lyndiâ:BAAALAADCgYIBwABLAAECggIFwAHAPklAA==.',['Lï']='Lïllïth:BAAALAAECgYICQAAAA==.',['Lô']='Lôthramette:BAAALAADCggICAAAAA==.',['Lø']='Lødy:BAABLAAECoEWAAMMAAgI/RvlAwCmAgAMAAgI/RvlAwCmAgANAAIIAAx1WgBvAAAAAA==.',Ma='Macarony:BAAALAADCgYIBgAAAA==.Maglite:BAAALAADCggIDgAAAA==.Magnukharos:BAAALAAECgYIBgABLAAFFAQICQAGAM4bAA==.Magwwa:BAAALAADCggIFAAAAA==.Makkoü:BAAALAAECgYIBgAAAA==.Malyne:BAAALAADCgQIBAAAAA==.Malyéna:BAAALAAECgIIBQAAAA==.Manuella:BAAALAAECgMIBgAAAA==.Marack:BAAALAADCgIIAgAAAA==.Marazdron:BAAALAAECgQIBQABLAAFFAQICQAGAM4bAA==.Marciana:BAAALAADCggIEAAAAA==.Mariä:BAAALAADCgcIBwAAAA==.Matouftétouf:BAAALAAECgIIAgAAAA==.Matsuyaz:BAAALAADCgcIBwAAAA==.Maxxwar:BAAALAAECgMIBQAAAA==.Maøker:BAAALAAECgcIEQAAAA==.',Me='Meawen:BAAALAADCggICAABLAAECgUICAACAAAAAA==.Megodruid:BAAALAADCgIIAgAAAA==.Mekouyenski:BAAALAAECggICwAAAA==.Melindræ:BAAALAADCgEIAQAAAA==.Melköre:BAAALAAECgcIEgAAAA==.Mendril:BAABLAAECoEYAAIOAAgIzhl0BQA8AgAOAAgIzhl0BQA8AgAAAA==.Meryw:BAAALAADCgQIBAABLAADCggICAACAAAAAA==.Meytsmage:BAAALAAECgYICwAAAA==.Meøwdragon:BAABLAAECoEWAAIPAAgI3BQvDgA1AgAPAAgI3BQvDgA1AgAAAA==.',Mh='Mhyrdin:BAAALAADCggIEwAAAA==.',Mi='Mieleria:BAAALAADCgMIAwAAAA==.Milaa:BAAALAAECgMIAwAAAA==.Milesteg:BAAALAAECgIIBQAAAA==.Misk:BAAALAAECgEIAQAAAA==.Mizaky:BAAALAADCgcICgAAAA==.',Mo='Mobylette:BAAALAAECgYIBQAAAA==.Morokei:BAAALAADCggIFwAAAA==.Mortdemasse:BAAALAAECgcIBQABLAAECggIBwACAAAAAA==.Mortelus:BAAALAAECgEIAQAAAA==.Moruy:BAAALAAECgMIBQAAAA==.Morvo:BAAALAADCgcICQAAAA==.Moustikedh:BAAALAADCgcICAABLAAFFAMIBAANAPgcAA==.Moustikelock:BAACLAAFFIEEAAINAAMI+BxBAwAdAQANAAMI+BxBAwAdAQAsAAQKgRUAAw0ACAi1JTcBAGwDAA0ACAi1JTcBAGwDABAAAQgOG5wlAFwAAAAA.',Mu='Muffet:BAAALAAECgEIAQAAAA==.Munzhao:BAAALAAECgMIAwAAAA==.',['Mä']='Mägla:BAAALAAECgIIAgAAAA==.',['Mé']='Mégødcløpê:BAAALAADCgcIBwAAAA==.',['Mø']='Møjitø:BAAALAADCgcICAAAAA==.Mønkhü:BAAALAADCggICwABLAAECgcIEQACAAAAAA==.Møzîlîännä:BAAALAAECggICAAAAA==.',Na='Nahela:BAAALAADCgUIBQABLAAECgUICAACAAAAAA==.Naveis:BAAALAADCggIDQAAAA==.Nayru:BAAALAADCgUIBQAAAA==.Naïlo:BAABLAAECoEYAAIRAAgI3CHMAAALAwARAAgI3CHMAAALAwAAAA==.Naïsse:BAAALAAECgMIBAAAAA==.',Ne='Nejihyûga:BAAALAADCgcIBwAAAA==.Nenettee:BAAALAAECggICAAAAA==.Nenyïm:BAAALAAECgIIAgAAAA==.Nevermore:BAAALAAECgYIDAAAAA==.',Ni='Niilo:BAAALAADCgcIEwAAAA==.',No='Norskan:BAAALAAECgIIAgAAAA==.Notsaffy:BAAALAAECgYIDgAAAA==.',Nu='Numausus:BAAALAAECgEIAQAAAA==.',Ny='Nyléa:BAAALAADCgYICgABLAAECgIIAgACAAAAAA==.',['Nà']='Nàri:BAABLAAECoEUAAMEAAgIPh/oCADnAgAEAAgIPh/oCADnAgAHAAEIjwaUNwArAAAAAA==.',['Né']='Néménèms:BAAALAADCggIDgAAAA==.Nérik:BAAALAADCggIFwAAAA==.',['Nï']='Nïizzyy:BAAALAAECgYICQAAAA==.',Oe='Oeilclair:BAAALAADCggIFwAAAA==.',Ok='Okroaan:BAAALAADCgUIBQAAAA==.',Or='Orinäel:BAAALAAECgYIDwAAAA==.',Ot='Otopsi:BAAALAAECgYIDAABLAAECggIEwACAAAAAQ==.',Pe='Periwinkle:BAAALAAECgQICAAAAA==.Perséfonia:BAAALAAECgYICAAAAA==.Peuticul:BAAALAADCggIEQAAAA==.',Ph='Phalangette:BAAALAAECgEIAgAAAA==.Phantomiste:BAAALAADCgcIDQAAAA==.Philcollins:BAAALAADCgUIBQAAAA==.Phom:BAAALAAECgMIBQAAAA==.',Pi='Piedlégé:BAAALAAECgYICQAAAA==.Pijiu:BAAALAAECgYICgAAAA==.Pilliniãté:BAAALAAECgIIAgAAAA==.',Pl='Plasma:BAAALAADCgMIAwAAAA==.Platane:BAAALAAECgIIAwAAAA==.',Po='Polgarà:BAAALAAECgIIAgAAAA==.Poxys:BAAALAAECgMICQAAAA==.',Pr='Proot:BAAALAADCgUIBQAAAA==.Prêtrombre:BAAALAADCgYIBgABLAADCggICAACAAAAAA==.',Pt='Ptibiscuit:BAAALAADCggIDwAAAA==.',['Pø']='Pøupøule:BAAALAAECgUIBQAAAA==.',Qu='Quieth:BAAALAAECgEIAQAAAA==.Quiqua:BAAALAADCggIFwAAAA==.',Ra='Raariel:BAAALAADCgYIBgAAAA==.Raiijin:BAAALAADCgYIBgAAAA==.Ramen:BAAALAADCgQIBAAAAA==.Rathema:BAAALAADCgUIBQAAAA==.Ratiral:BAAALAAECgMIAwAAAA==.Ravannoth:BAACLAAFFIEJAAIGAAQIzhsjAQCTAQAGAAQIzhsjAQCTAQAsAAQKgRgAAgYACAjoJU0UAHgCAAYACAjoJU0UAHgCAAAA.',Re='Redleendh:BAACLAAFFIEGAAISAAMI7SIxAABDAQASAAMI7SIxAABDAQAsAAQKgRgAAhIACAhVJlAAAH0DABIACAhVJlAAAH0DAAAA.',Ro='Rogger:BAAALAADCggICAAAAA==.Ronie:BAAALAADCgcIDgAAAA==.Rony:BAAALAADCgUIBQAAAA==.Rosbif:BAAALAAECgcIDQAAAA==.',Ru='Rumahoy:BAAALAADCggIEAABLAAFFAQICQAGAM4bAA==.',['Rä']='Rägetrap:BAAALAAECgMIBQAAAA==.Räôr:BAAALAAECgIIAgAAAA==.',['Rø']='Rønan:BAAALAAECgUICAAAAA==.',Se='Segolene:BAAALAAECgcIBwAAAA==.Sentoriu:BAAALAAECgUICAAAAA==.Sernine:BAAALAADCggIEAAAAA==.Seÿfer:BAAALAADCgUICAAAAA==.',Sh='Shadowbear:BAAALAAECgYICQAAAA==.Shubnigurat:BAAALAADCggIDwAAAA==.Shàdøw:BAAALAAECgMIAwABLAAECgcIEQACAAAAAA==.',Si='Silicone:BAAALAADCgIIAgAAAA==.Silvos:BAAALAADCgMIAwAAAA==.',Sk='Skudgya:BAAALAAECgQICQAAAA==.',Sl='Slardar:BAAALAADCggIDwAAAA==.',Sm='Smartyz:BAAALAAECgUIBwAAAA==.Smashh:BAAALAAECgMIBAAAAA==.',So='Solarïa:BAABLAAECoEWAAIBAAgIbSOGBgAiAwABAAgIbSOGBgAiAwAAAA==.Sonna:BAAALAAECgcIEAAAAA==.Sonys:BAAALAAECgIIAgAAAA==.Sorwen:BAAALAADCgcIDgAAAA==.',Sp='Sprec:BAAALAADCggICAAAAA==.',St='Stoutdrood:BAAALAAECggICAAAAA==.Stáche:BAAALAAECgUIBQAAAA==.',Su='Sulis:BAAALAADCggICAABLAAECggIFgABAG0jAA==.Superdruide:BAAALAAECgEIAQAAAA==.',Sy='Sygne:BAAALAAECgEIAQAAAA==.Sylvi:BAAALAADCggICAAAAA==.',Ta='Taenoch:BAAALAAECgIIAgABLAAFFAQICQAGAM4bAA==.Taldatur:BAAALAADCgcIFAAAAA==.Taluna:BAAALAADCgYIBgAAAA==.Tarrkahan:BAAALAAECgIIAgAAAA==.Tawanka:BAAALAAECgEIAgAAAA==.',Th='Thalren:BAAALAADCgcIBwAAAA==.Thaunak:BAAALAAECgQICAAAAA==.Thechaös:BAAALAADCggIDwAAAA==.Thildadore:BAAALAADCgQIBAAAAA==.Thorgadon:BAAALAAECgMIBwAAAA==.Thorym:BAAALAAECgEIAQAAAA==.Thuradrim:BAAALAAECgMIAwAAAA==.Thälïa:BAAALAADCggICAAAAA==.Thèss:BAAALAAECgMIAwAAAA==.Thérez:BAACLAAFFIEFAAITAAMIiA7GAQDyAAATAAMIiA7GAQDyAAAsAAQKgRgAAhMACAibHW0FALMCABMACAibHW0FALMCAAAA.',To='Tournicoton:BAAALAADCgIIAgAAAA==.',Tr='Trancheveine:BAAALAAECgYICwAAAA==.',Tu='Turlupine:BAAALAAECgEIAQAAAA==.Tutîn:BAAALAADCggIEAAAAA==.',Tw='Tweely:BAAALAAECgQIBAAAAA==.',Ty='Tyc:BAAALAADCggIDwAAAA==.Tyker:BAAALAAECgIIAgAAAA==.Typhïs:BAAALAADCggIFwAAAA==.Tyra:BAAALAADCggICAAAAA==.Tyrk:BAAALAAECgQIBAAAAA==.',['Tè']='Tèndra:BAAALAADCgcICwAAAA==.',['Té']='Télapal:BAAALAADCgYIBgAAAA==.',['Tö']='Törnade:BAAALAADCgcIDgAAAA==.',Ut='Utral:BAAALAADCggIEAAAAA==.',Va='Vaelindra:BAAALAADCgYIDQAAAA==.Vafara:BAAALAAECgYIEwAAAA==.Valaan:BAAALAADCgcIBwAAAA==.Valaert:BAAALAADCgcIFQAAAA==.Vanishfraise:BAAALAADCggICAAAAA==.Vardà:BAAALAAECggIBwAAAA==.Varidan:BAAALAADCgYICwAAAA==.Varyn:BAAALAADCggIDAAAAA==.Vaxildan:BAAALAAECgcIBwAAAA==.',Ve='Vendelice:BAAALAADCgcICAAAAA==.Verks:BAAALAADCggICAAAAA==.',Vo='Volgaz:BAAALAADCgUICgAAAA==.Volyo:BAAALAADCgQIBAAAAA==.Voodmage:BAAALAADCgQIBAABLAADCgcIBwACAAAAAA==.Voodsham:BAAALAADCgcIBwAAAA==.Vorkresh:BAAALAADCgUIBQAAAA==.',Vr='Vrimel:BAABLAAECoEUAAITAAgISxJLDAAEAgATAAgISxJLDAAEAgAAAA==.',['Vá']='Váryn:BAAALAADCgEIAQAAAA==.',Wa='Wandr:BAAALAAECgQICAAAAA==.Warstos:BAACLAAFFIELAAIHAAUI3hh2AAC/AQAHAAUI3hh2AAC/AQAsAAQKgRgAAgcACAh4IhACACcDAAcACAh4IhACACcDAAAA.Warzuzbib:BAAALAAECgIIAgAAAA==.',Wi='Wiloskill:BAAALAAECgYIDQAAAA==.',Wu='Wu:BAAALAADCggICAAAAA==.',Xa='Xastan:BAAALAADCgcICgAAAA==.',Xr='Xros:BAAALAAECgIIAgAAAA==.',Ye='Yecabel:BAAALAAECgEIAQAAAA==.',Yo='Yonabricot:BAABLAAECoEYAAILAAgIOCUDAQB1AwALAAgIOCUDAQB1AwAAAA==.',Yu='Yunallion:BAAALAAECgEIAQAAAA==.Yune:BAAALAAFFAIIAQAAAA==.',['Yü']='Yünâ:BAAALAAECgMIAwAAAA==.',Za='Zabouelle:BAAALAADCggIFwAAAA==.',Ze='Zelenna:BAAALAADCggIFgAAAA==.Zenatra:BAAALAAECgYICQAAAA==.',Zo='Zomul:BAAALAADCgMIAwAAAA==.',Zu='Zuzzie:BAAALAADCgcIBwAAAA==.',['Zä']='Zäelyä:BAAALAADCgcIBwABLAAECgYICgACAAAAAA==.',['Zé']='Zéna:BAAALAAECgMIBgAAAA==.',['Zô']='Zôrn:BAABLAAECoEXAAILAAgI/husDwCCAgALAAgI/husDwCCAgAAAA==.',['Är']='Ärhen:BAABLAAECoEXAAMHAAgI+SVdAACDAwAHAAgI+SVdAACDAwAEAAEIjB3iUgBQAAAAAA==.',['Él']='Élogän:BAAALAADCgcIDQAAAA==.Élora:BAAALAADCgQIBQAAAA==.',['Ín']='Ínuk:BAAALAAECgcIEAAAAA==.',['Ðr']='Ðraiss:BAAALAAECgMIBwAAAA==.',['Ðæ']='Ðæðæ:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.',['Ñi']='Ñirä:BAAALAADCgUICAAAAA==.',['Ôn']='Ônyx:BAAALAADCggIFwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end