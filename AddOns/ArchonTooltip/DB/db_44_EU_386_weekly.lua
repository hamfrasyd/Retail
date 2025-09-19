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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Druid-Feral','Druid-Restoration','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Warrior-Fury',}; local provider = {region='EU',realm='Suramar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aara:BAAALAAECgYICgAAAA==.',Ae='Aekoo:BAAALAADCggIDgAAAA==.Aeros:BAAALAADCgcIFAAAAA==.',Ak='Akhisha:BAAALAADCgcIDQAAAA==.',Al='Alestia:BAAALAAECgcIEAAAAA==.Almaghar:BAAALAADCgcICQAAAA==.Alurdel:BAAALAADCgYIDAAAAA==.',Am='Amadass:BAAALAADCggICgAAAA==.Amergin:BAAALAADCgcIBwAAAA==.',An='Anarazel:BAAALAAECgQIBAABLAAECgYIBQABAAAAAA==.Anenix:BAAALAAECgQIBwAAAA==.',Ao='Aoshin:BAAALAAECgcICAAAAA==.',Ap='Appletree:BAAALAAECgQIBAAAAA==.',Ar='Arael:BAAALAADCgYIBgAAAA==.Aranwel:BAAALAAECgEIAQAAAA==.Arratar:BAAALAAECgYIDAAAAA==.',As='Asiriel:BAAALAAECgYIDwAAAA==.Astra:BAAALAAECgUIBQAAAA==.',Ay='Ayzan:BAAALAADCgIIAwAAAA==.',['Aé']='Aégidius:BAAALAADCggIFgAAAA==.',['Aø']='Aødhan:BAAALAAECggIEQAAAA==.',Ba='Badday:BAAALAADCgUIBQAAAA==.Bahamut:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.Bakthor:BAAALAADCggIBQAAAA==.Bamboudiné:BAAALAAECgEIAQAAAA==.',Bl='Blackpriest:BAAALAAECgMIAwABLAAECgYIBgABAAAAAA==.Blancbarbu:BAAALAAECgcIEAAAAA==.Blobecarlate:BAAALAADCgYIBwABLAAECgYIDQABAAAAAA==.Blobindigo:BAAALAAECgQICQAAAA==.Blobjeanma:BAAALAAECgUIBQAAAA==.Blobéon:BAAALAAFFAIIAgAAAA==.Blueskyy:BAAALAAECgYIDQAAAA==.',Bo='Bouhdepier:BAAALAADCggICAAAAA==.',Br='Brel:BAAALAAECgYIDwAAAA==.',By='Byakktina:BAAALAAECgcIDgAAAA==.',['Bà']='Bàohù:BAAALAAECgcIEAAAAA==.',Ca='Caepra:BAAALAADCggICAAAAA==.Camoes:BAAALAAECgcIDgAAAA==.Cartarme:BAAALAAECgYIDQAAAA==.',Ce='Celyanar:BAAALAADCgcIBwAAAA==.',Ch='Chamanni:BAAALAAECgMIBgAAAA==.Chaminati:BAAALAADCgYIBgAAAA==.Chevaliøur:BAAALAAECgIIAgAAAA==.Chicots:BAAALAADCgcIEQAAAA==.Chérie:BAAALAAECgEIAQAAAA==.',Ci='Cirdec:BAAALAADCgUIBQAAAA==.',Cs='Csisala:BAAALAADCgcICQAAAA==.',Cu='Curcuma:BAAALAAECgQICAAAAA==.',['Cô']='Côôlmâ:BAAALAADCggIEwAAAA==.',['Cø']='Cøcøtte:BAAALAADCggIDgAAAA==.',Da='Daffydock:BAAALAAECgYIDAAAAA==.Darkane:BAAALAADCggICQAAAA==.Darkfûry:BAAALAADCgYIBgAAAA==.Darkgirl:BAAALAADCgYIBgAAAA==.Darktauren:BAAALAADCgcICQAAAA==.Daëmonika:BAAALAADCgUIBQAAAA==.',De='Deathjadou:BAAALAADCgcIBwAAAA==.Derea:BAAALAADCgEIAQAAAA==.Derideath:BAAALAADCgMIAwAAAA==.',Dh='Dhik:BAAALAADCgMIAwAAAA==.',Dk='Dkmal:BAAALAAECgcIEAAAAA==.',Do='Donmakaveli:BAAALAADCgUIBQAAAA==.',Dr='Dragonico:BAAALAAECgYIDQAAAA==.Drakenshyk:BAAALAAECgEIAQAAAA==.Druidamix:BAAALAAECgIIAgABLAAECgYICwABAAAAAA==.',['Dé']='Décapfour:BAAALAADCggIEAAAAA==.Décimal:BAAALAAECgMIAwAAAA==.Déri:BAAALAAECgIIAgAAAA==.',Ea='Eaubenite:BAAALAADCgMIAwAAAA==.Eaudreyve:BAAALAAECgIIAgAAAA==.',El='Elara:BAAALAAECgMIAwABLAAECgcIBwABAAAAAA==.Elfie:BAAALAADCgcIBwABLAADCggIFAABAAAAAA==.Elémentar:BAAALAAECgYICwAAAA==.',Er='Erhétrya:BAABLAAECoEVAAICAAgIdhwfCwB2AgACAAgIdhwfCwB2AgAAAA==.',Ev='Evilwulf:BAAALAAECgYIBQAAAA==.',Ex='Exalutor:BAAALAAECgMIBQAAAA==.',Ey='Eyesonme:BAAALAADCgEIAQAAAA==.',Fa='Falkor:BAAALAAECgUIBQABLAAECgYIBQABAAAAAA==.Farléane:BAAALAAECgIIAgAAAA==.',Fe='Fefist:BAAALAAFFAEIAQAAAA==.Fellean:BAAALAAECgIIAgAAAA==.',Fo='Fougêrre:BAAALAADCggIDQAAAA==.',['Fà']='Fàfnir:BAAALAADCgcIBwAAAA==.',['Fé']='Félinne:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.',Ga='Gallaw:BAAALAADCgUIBQAAAA==.',Gi='Gilrohel:BAAALAAECgcIEAAAAA==.',Gl='Glossy:BAAALAAECgEIAQAAAA==.',Gr='Groscaillou:BAAALAAECgcIBwAAAA==.',Gu='Guïmauve:BAAALAADCgMIAwAAAA==.',['Gø']='Gørøsh:BAAALAADCgcICAAAAA==.',Ha='Hakushu:BAAALAADCgcIBwAAAA==.Hanoumân:BAAALAADCggICAAAAA==.Hathanael:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.',He='Heraa:BAAALAAECgEIAQAAAA==.',Ho='Hogma:BAAALAAECgYIBgAAAA==.',Hu='Hunä:BAAALAAECgcIEAAAAA==.',['Hé']='Héresia:BAAALAAECgMICQAAAA==.',Ic='Iceforge:BAAALAADCgIIAgAAAA==.',Ig='Iggins:BAAALAAECgEIAgAAAA==.',Ik='Ikshar:BAAALAADCgMIAwAAAA==.',Il='Ilgadh:BAAALAADCgcIBgABLAAECgcIEAABAAAAAA==.Ilgapal:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Ilgarna:BAAALAAECgcIEAAAAA==.Ilidune:BAAALAAECgYIBgAAAA==.Ill:BAAALAAECggIEAAAAA==.Ilyasse:BAAALAAECgYIDgABLAAFFAMIAgABAAAAAA==.',Is='Istarei:BAAALAAECgYIDgAAAA==.',Iz='Izikia:BAAALAADCggICAAAAA==.',Ja='Jadounet:BAAALAAECgYICAAAAA==.Jafad:BAAALAAECgIIAgAAAA==.',Ji='Jilsoul:BAAALAADCgUIBQAAAA==.',Jo='Jollyna:BAAALAADCgcIDgAAAA==.',Ka='Kaeldan:BAAALAADCgEIAQAAAA==.Kaervek:BAAALAADCgcIBwAAAA==.Kame:BAAALAAECgQIBwAAAA==.',Ke='Keitho:BAAALAAECgEIAQAAAA==.Keramal:BAAALAADCgcIBwAAAA==.',Kh='Khendan:BAAALAAECgEIAQAAAA==.',Ki='Kirito:BAAALAAECgIIAwAAAA==.',Kl='Kleà:BAAALAAECgMIBgAAAA==.',Ko='Koane:BAAALAAECgUIBgAAAA==.Kobalt:BAAALAADCgcICgAAAA==.Kornich:BAAALAADCgMIAwAAAA==.',Ku='Kuronawaah:BAAALAAECgMIAwABLAAECgQIBwABAAAAAA==.Kurowaah:BAAALAAECgQIBwAAAA==.',Ky='Kyjo:BAAALAADCgQIBAAAAA==.Kyssa:BAAALAAECgcIEAAAAA==.',Le='Lemagicien:BAAALAAECgcIEAAAAA==.Leroyn:BAAALAADCggICwAAAA==.Levdrood:BAABLAAECoEWAAMDAAgIHBhxBQBjAgADAAgIHBhxBQBjAgAEAAcIeRDeJQBfAQAAAA==.',Li='Lidalice:BAAALAAECgcIDQAAAA==.Lisneuh:BAAALAAECgcIDgAAAA==.',Lo='Lodie:BAAALAADCgQIBAAAAA==.Loludu:BAAALAADCggICAAAAA==.Loroyse:BAAALAAECgcIDwAAAA==.Lostris:BAAALAAECgMIAwAAAA==.Loturos:BAAALAAECggIDgAAAA==.',Lu='Lumineau:BAAALAADCgcIBwAAAA==.',Ly='Lykaon:BAAALAADCgcIDAAAAA==.',['Lé']='Léovis:BAAALAAECgUIBwAAAA==.',Ma='Magikbanani:BAAALAADCgUIBQAAAA==.Magikkbanani:BAABLAAECoEXAAQFAAgIPhgBCwAeAgAFAAgI1hcBCwAeAgAGAAMISA9lGgCzAAAHAAIIWxmbUACZAAAAAA==.Magistrall:BAAALAAECgYICwAAAA==.Maldonn:BAAALAADCgcICQAAAA==.Manla:BAAALAAECgMIBgAAAA==.',Mi='Midonä:BAAALAAECgMIBwAAAA==.Mikaw:BAAALAADCgYICQAAAA==.Milenia:BAAALAAECgMIAwAAAA==.Milëa:BAAALAADCggIEAAAAA==.Miniprêtress:BAAALAAECgcIEAAAAA==.Miranà:BAAALAADCgQIBAAAAA==.Missisipia:BAABLAAECoEVAAIIAAgIJhVdFQBHAgAIAAgIJhVdFQBHAgAAAA==.',Mo='Moinephuc:BAAALAAECgYIBwAAAA==.Monysera:BAAALAADCggIDwAAAA==.Morgomir:BAAALAAECggICQAAAA==.',Mu='Muldrak:BAAALAADCgcIBwAAAA==.',My='Mystas:BAAALAAECgYIBgAAAA==.Mystikh:BAAALAADCgUIBQABLAADCggIFAABAAAAAA==.',['Mä']='Mägnûm:BAAALAAECgYIDwAAAA==.',Na='Nahry:BAAALAADCggIEAAAAA==.Nanashi:BAAALAAECgMIBgAAAA==.',Ne='Nefertami:BAAALAADCgEIAQAAAA==.Nerioo:BAAALAAECgQICAAAAA==.Nerthüs:BAAALAADCggIDAAAAA==.',Ni='Niabey:BAAALAAECgMIAwAAAA==.Nirinäh:BAAALAAECgIIAgAAAA==.',No='Noukkie:BAAALAADCgcICQAAAA==.',['Né']='Néferia:BAAALAAECgMIBgAAAA==.',Or='Orksovage:BAAALAADCggIFgAAAA==.Orphélie:BAAALAAECgcIDQAAAA==.',Os='Osteolis:BAAALAADCgYICgAAAA==.',Pa='Pandaran:BAAALAADCggICwABLAAECgYIBQABAAAAAA==.Panomanixme:BAAALAADCggIFgABLAAECggIFQACAHYcAA==.Papybellu:BAAALAAECgEIAQAAAA==.Paxarius:BAAALAADCgcIBwAAAA==.',Po='Pompei:BAAALAADCgIIAgAAAA==.Popkornne:BAAALAAECgMIAwAAAA==.',Pr='Priestzle:BAAALAADCgcIDQAAAA==.Protonidze:BAAALAADCgcIDQAAAA==.',['Pï']='Pïstachë:BAAALAAECgMIBgAAAA==.',Ra='Ragnaro:BAAALAADCgcIDQAAAA==.Raknarok:BAAALAAECgYIDwAAAA==.',Re='Reythanabis:BAAALAADCggIEwAAAA==.',Ro='Rodrac:BAAALAAECgYICgAAAA==.',Sa='Saakhar:BAAALAADCgUICQAAAA==.Saekoh:BAAALAAECgcIEgAAAA==.Sakredbonk:BAAALAAECgYIBwAAAA==.Sakürà:BAAALAADCggIDQAAAA==.Sarïka:BAAALAADCggICAAAAA==.Satsujinken:BAAALAADCgcIBwAAAA==.',Sh='Shaÿa:BAAALAADCgcIDgAAAA==.Sheiyne:BAAALAAECgEIAQAAAA==.',Si='Siondrus:BAAALAADCgYIDQAAAA==.',Sm='Smò:BAAALAADCgMIAwAAAA==.Smõ:BAAALAADCggICgAAAA==.',So='Solido:BAAALAADCgMIAwAAAA==.Soltrae:BAAALAADCgcICAAAAA==.Soonyangel:BAAALAADCggICAAAAA==.Sorön:BAAALAADCgcIBwAAAA==.',Sp='Sprinkle:BAAALAADCggIFAAAAA==.',Sq='Squishina:BAAALAAECgMIBgAAAA==.',['Sî']='Sîrmerlin:BAAALAAECgcICgAAAA==.',['Sø']='Søoný:BAAALAAECgcIEAAAAA==.',Ta='Tactacdh:BAAALAAECgQIBAAAAA==.Taellia:BAAALAADCggIEAAAAA==.Taoor:BAAALAAECgcIBwAAAA==.Tarâ:BAAALAADCgcICwAAAA==.Tatoobabe:BAAALAADCgcIBwAAAA==.',Th='Tharawaah:BAAALAAECgYIDAAAAA==.Theroshan:BAAALAAECgYICwAAAA==.Thienthien:BAAALAAECggIDAAAAA==.Thàllion:BAACLAAFFIEJAAIJAAQI2hAyAQBzAQAJAAQI2hAyAQBzAQAsAAQKgRgAAgkACAi3JJ8QAHACAAkACAi3JJ8QAHACAAAA.Théoochoux:BAAALAADCgUIBQAAAA==.',To='Tontonjeanma:BAAALAADCgYIBgAAAA==.',Tu='Turim:BAAALAAECgIIAwAAAA==.',['Tø']='Tømyun:BAAALAAECgYIDwAAAA==.',Uc='Ucatsone:BAAALAADCgcICQAAAA==.',Un='Univeria:BAAALAAECgMIAQAAAA==.',Va='Valøø:BAAALAAECggIAQAAAA==.Vanhouten:BAAALAADCgcICAAAAA==.Vanthyr:BAAALAAFFAMIAgAAAA==.',Ve='Veleera:BAAALAADCggICAABLAAECggIAQABAAAAAA==.',Vi='Visariuss:BAAALAAECgIIAgAAAA==.',Wa='Walkinglunge:BAAALAAECgcICgAAAA==.',Wi='Winnie:BAAALAADCggIFQAAAA==.',Ya='Yabadabadoo:BAAALAAECgIIAgABLAAECgcIDQABAAAAAA==.',Yu='Yugure:BAAALAAECgYICAABLAAECgcIDwABAAAAAA==.Yummu:BAAALAAECgYICQAAAA==.Yumu:BAAALAAECgQIBgAAAA==.',Za='Zavryk:BAAALAADCggICAAAAA==.',Zi='Ziapaladin:BAAALAADCgcIDAAAAA==.Ziapin:BAAALAADCgUIBQAAAA==.Zionhigh:BAAALAADCgYIDAAAAA==.',Zo='Zoumio:BAAALAADCgcIBwAAAA==.',['Äb']='Äbaddon:BAAALAADCggIDgAAAA==.',['Æw']='Æwêÿn:BAAALAAECggIBgABLAAECggIEQABAAAAAA==.',['Øm']='Ømegâ:BAAALAAECgQICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end