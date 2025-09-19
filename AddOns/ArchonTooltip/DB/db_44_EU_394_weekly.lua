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
 local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Shaman-Elemental','Priest-Holy','DeathKnight-Unholy','Priest-Shadow','Druid-Balance','Rogue-Outlaw','Rogue-Assassination','Warrior-Fury','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost',}; local provider = {region='EU',realm='Alexstrasza',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ag='Agelicia:BAAALAAECgMIAwAAAA==.Aglaea:BAAALAADCggICAAAAA==.Agona:BAAALAAECgYICAAAAA==.',Al='Alayne:BAAALAAECgYIDAAAAA==.Aldorasx:BAAALAAECgYIBgAAAA==.Alduin:BAABLAAECoEVAAIBAAgI6xp7EQAVAgABAAgI6xp7EQAVAgAAAA==.Aleastes:BAAALAADCggIDQAAAA==.Alnitak:BAAALAAECgcIDgAAAA==.Alrachi:BAAALAADCgQIBAAAAA==.',Am='Amalya:BAAALAADCggIGAAAAA==.Amaterasu:BAAALAAECgYIDwAAAA==.Amber:BAAALAAECgYICQAAAA==.',An='Ancksuamun:BAAALAADCgcIDgAAAA==.Anckzunamun:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Ansbald:BAAALAADCggIDwAAAA==.',Ap='Apoll:BAAALAADCgYICAAAAA==.',Aq='Aqisoq:BAAALAADCgMIAwAAAA==.',Ar='Araggor:BAAALAADCgMIBQAAAA==.Armalyte:BAAALAAECgIIAQAAAA==.',As='Asaron:BAAALAADCgcIDAAAAA==.Askalante:BAAALAADCgQIBAAAAA==.',At='Atbest:BAAALAAECgEIAQAAAA==.Atheenos:BAAALAAECgMIBgAAAA==.',Au='Aurinkaa:BAAALAAECgUICgAAAA==.',Ba='Bacardî:BAAALAAECgYIBgAAAA==.Balendor:BAAALAAECgYIBgAAAA==.Balin:BAAALAADCgUIBQAAAA==.Baumhirte:BAAALAADCgcIBwAAAA==.',Be='Belnas:BAAALAAECgcIDgAAAA==.Belzzebub:BAAALAAECgMIAwAAAA==.Beówólf:BAAALAAECgEIAQAAAA==.',Bh='Bheldur:BAAALAAECgMIBQAAAA==.',Bi='Bingchillíng:BAAALAAECgYIDgAAAA==.',Bl='Blackhack:BAAALAADCgcIBwABLAAECgIIAQACAAAAAA==.Blackvamp:BAAALAADCggICAAAAA==.Blaire:BAAALAAECgYICwAAAA==.Blûemoon:BAAALAAECgEIAQAAAA==.',Bo='Boderrush:BAAALAADCgUIBwAAAA==.Bohnenblüte:BAAALAAECgQIBAAAAA==.Borgosch:BAAALAAECgMIBgAAAA==.',Br='Brangäne:BAAALAAECgMIAwAAAA==.Bratyydk:BAAALAAECgYICgAAAA==.Breezer:BAAALAADCgIIAgAAAA==.Breitwieder:BAAALAAECgIIAgAAAA==.Brotinator:BAAALAADCgYIBgABLAAECgYIDAACAAAAAA==.Brummbart:BAABLAAECoEYAAIDAAgIGhvGDACUAgADAAgIGhvGDACUAgAAAA==.Brutan:BAAALAADCggIEAAAAA==.',Bu='Bulldor:BAAALAAECgIIAgAAAA==.Bulwa:BAAALAADCgEIAQAAAA==.Bumblotaurus:BAAALAAECgIIAgAAAA==.',['Bö']='Böse:BAAALAAFFAIIAwAAAA==.',Ca='Camaeel:BAAALAAECgYICwAAAA==.Captainkomo:BAAALAADCggIEAAAAA==.Capybará:BAAALAAECgYICgAAAA==.Castel:BAAALAADCgMIAwAAAA==.',Ce='Celly:BAAALAADCgcIDQABLAADCggIEAACAAAAAA==.Certania:BAAALAAECgEIAQAAAA==.',Ch='Chawis:BAAALAADCggICAAAAA==.Cheax:BAAALAADCgYIBgAAAA==.Chezaron:BAAALAAECgIIAgAAAA==.Chihirte:BAAALAADCgcIDQAAAA==.',Cl='Clairgrubê:BAAALAADCgcIBwAAAA==.',Co='Corason:BAAALAADCggIEAAAAA==.Cornholiø:BAAALAAECgYICQAAAA==.Corpsecaller:BAAALAADCgcIBwAAAA==.Cowgummi:BAAALAADCggICQAAAA==.',Cr='Crashshooter:BAAALAAECgIIAgAAAA==.Creon:BAAALAAECgMIAwAAAA==.Critbummbang:BAAALAADCgYIBgAAAA==.',Cu='Curley:BAAALAAECgYIBwAAAA==.',['Cà']='Càrryu:BAABLAAECoEUAAIEAAgIQiXkAABhAwAEAAgIQiXkAABhAwAAAA==.',['Có']='Cónf:BAAALAAECgIIAgAAAA==.Cóòkie:BAAALAAECgMIBAAAAA==.',Da='Dajin:BAAALAAECgMIBAAAAA==.Danity:BAAALAADCgUIBQAAAA==.Darkangle:BAAALAADCgQIBgAAAA==.Daroo:BAAALAAECgYIDAAAAA==.Daríus:BAAALAAECgEIAQAAAA==.',Dd='Ddarkevel:BAAALAAECggIEwAAAA==.',De='Dementor:BAAALAAECgQIBAAAAA==.Demo:BAAALAAECgcIDQAAAA==.Demonperson:BAAALAADCggICAAAAA==.Deplete:BAAALAAECgEIAQAAAA==.Derokan:BAAALAAECgcIDQAAAA==.Desperadôs:BAAALAADCgUIBwAAAA==.',Di='Divesion:BAAALAADCgYIDAAAAA==.Diânâ:BAAALAADCgcICwAAAA==.',Do='Dojoo:BAAALAAECgQIAgAAAA==.Donkkiller:BAAALAADCggIGAAAAA==.',Dr='Dragoneel:BAAALAAECgMIAwABLAAECgYICAACAAAAAQ==.Dragonine:BAAALAAECgcIEAAAAA==.Dragtor:BAAALAAECgUICgAAAA==.Draki:BAAALAAECgEIAQAAAA==.Droish:BAAALAAECgEIAQAAAA==.Drops:BAAALAAECgcIDQAAAA==.Drudlinde:BAAALAADCgEIAQAAAA==.Druídera:BAAALAADCgQIBAAAAA==.Drächerlich:BAAALAADCggIFgAAAA==.',Du='Dustinhunt:BAAALAADCggICAAAAA==.',['Dá']='Dárkness:BAAALAAECgYICwAAAA==.',Ed='Edineu:BAAALAADCggIEAAAAA==.Eduardpipi:BAAALAAECgYICAAAAA==.',El='Eladrake:BAAALAADCgcICwAAAA==.Eld:BAAALAADCgUIBwAAAA==.Eldahir:BAAALAAECgYIDQAAAA==.Elfrida:BAAALAADCgcIBwAAAA==.Elling:BAAALAAECgUICgAAAA==.Elna:BAAALAADCgMIBAAAAA==.Elrôs:BAAALAAECgUICgAAAA==.',Em='Emilein:BAAALAAECgIIAgAAAA==.Emptymage:BAAALAADCgQIBAAAAA==.',Er='Erdala:BAAALAAECgUICAAAAA==.Erdbert:BAAALAAECgYIBgAAAA==.Erdling:BAAALAAECgMIAwAAAA==.Erdnuckel:BAAALAAECgMIAwAAAA==.Erik:BAAALAAECgcIBwAAAA==.',Eu='Eurybia:BAAALAAECgUICgAAAA==.',Ew='Ewoker:BAAALAAECgcIBwAAAA==.',Ex='Executie:BAAALAAECgIIAwAAAA==.',Fa='Fahy:BAAALAAECgMIBQAAAA==.Falamira:BAAALAAECgMIBAAAAA==.Faneromeni:BAAALAAECgMIBQAAAA==.Fantanix:BAAALAADCgUIBQAAAA==.',Fe='Fenriswolff:BAAALAAECgcIEAAAAA==.',Fi='Filron:BAAALAADCgcIDgAAAA==.Fipya:BAAALAAECgMIBAAAAA==.',Fl='Flidhais:BAAALAADCgMIAwAAAA==.',Fr='Frijda:BAAALAAECgYICQABLAAECgcIDwACAAAAAA==.Frów:BAAALAADCgcIBwAAAA==.',Fu='Fujiisk:BAAALAAECgcIDwAAAA==.',['Fä']='Färón:BAAALAAECgIIAgAAAA==.',['Fø']='Førbes:BAAALAAECgUIBwAAAA==.',Ga='Gallico:BAAALAAECgMIBgAAAA==.Gasuna:BAAALAAECgUICgAAAA==.',Gi='Giftrose:BAAALAAECggIEwAAAA==.',Gl='Glondo:BAAALAAECgUICQAAAA==.',Gn='Gnomlie:BAAALAAECgQIBgAAAA==.',Go='Goldelf:BAAALAADCggICAAAAA==.Gorkaorka:BAAALAAECgYICQAAAA==.Gossanor:BAAALAADCggIEAAAAA==.Gozu:BAAALAAECgMIAwAAAA==.',Gr='Greefãx:BAAALAAECgYIDAAAAA==.Groka:BAAALAAECgYICQAAAA==.Grood:BAAALAAECgYICQAAAA==.',Gu='Guccigesicht:BAAALAADCgcIBwAAAA==.Guenji:BAAALAADCgcIEgABLAADCggIEAACAAAAAA==.Gutwúrz:BAAALAAECgMIBgAAAA==.',Ha='Hanime:BAAALAADCggICAAAAA==.Happyaua:BAAALAADCgcICgAAAA==.Hardwing:BAAALAAECgEIAQAAAA==.Hargorina:BAAALAADCgUIBQAAAA==.Harmy:BAAALAAECgUICQAAAA==.Haskeér:BAAALAAECgEIAQAAAA==.Haìley:BAAALAAECgcIDAAAAA==.',He='Healwoo:BAAALAADCggICAABLAAECgEIAQACAAAAAA==.',Hi='Hinotamâ:BAAALAAECgcIDgAAAA==.',Hj='Hjaldrig:BAAALAAECgIIAgAAAA==.',Ho='Hofiaimedyou:BAAALAADCgYIBgAAAA==.Hofiisblind:BAAALAADCgYIBgAAAA==.Hoyo:BAAALAADCggIEgAAAA==.',['Hé']='Hérá:BAAALAAECgcIEQAAAA==.',Id='Idç:BAAALAADCgIIAgAAAA==.',Il='Iluvbobz:BAAALAAECggIDAAAAA==.',Im='Imhôtep:BAAALAADCggIEAABLAAECggIFgAFAOAhAA==.',In='Inaevar:BAABLAAECoEYAAIGAAgIhCGOBAAfAwAGAAgIhCGOBAAfAwAAAA==.Induriel:BAAALAAECgEIAQAAAA==.',Ir='Irdenerwoo:BAAALAAECgUIBQAAAA==.Irrefix:BAAALAAECgUICgAAAA==.',Is='Islanzadi:BAABLAAECoEXAAIHAAgIfhaoDwA8AgAHAAgIfhaoDwA8AgAAAA==.Islanzhadi:BAAALAAECgYIDQAAAA==.',Iv='Ivenhow:BAAALAAECgcIDQAAAA==.',Ja='Jackrum:BAAALAAECgMIBQAAAA==.Jarnunvösk:BAAALAADCggIDQABLAAECggIFwAHAH4WAA==.',Je='Jenjen:BAAALAADCggIEAAAAA==.Jennika:BAABLAAECoEXAAMIAAgIahdjAgBfAgAIAAgIahdjAgBfAgAJAAEIhgfyRABBAAAAAA==.Jenora:BAAALAAECgYICQAAAA==.Jetrascha:BAAALAAECgMIAwAAAA==.',Ji='Jigger:BAAALAADCggIDQAAAA==.',Jo='Johhn:BAAALAAECgMIBAAAAA==.Jolorika:BAAALAAECgMIAwAAAA==.Joschie:BAAALAADCgMIAwAAAA==.',Jr='Jrz:BAAALAAECgMIBgAAAA==.',Ju='Jupîter:BAAALAAECgIIAgAAAA==.',Ka='Kafina:BAAALAAECgYIBgAAAA==.Kaiht:BAAALAAECgQIBAAAAA==.Kaldori:BAAALAAECgMIBgAAAA==.Kaletia:BAAALAADCgcIBwAAAA==.Kaneda:BAAALAAECgQICAAAAA==.Kaos:BAAALAAECgQIBAAAAA==.Karendavid:BAAALAAECgEIAQAAAA==.',Ke='Kennstermnid:BAAALAADCgUIBQAAAA==.',Kh='Khami:BAAALAAECgMIBQAAAA==.',Ki='Kibori:BAAALAAECgYICAAAAA==.',Kn='Knarr:BAAALAAECgIIAgAAAA==.Knarrenonkel:BAAALAADCgUIBwAAAA==.Knigge:BAAALAAECgYIDAAAAA==.Kniggecode:BAAALAADCggIEAABLAAECgYIDAACAAAAAA==.Kniggonaut:BAAALAAECgUIAQABLAAECgYIDAACAAAAAA==.Knightsabre:BAAALAADCggIEAAAAA==.',Ko='Kobi:BAAALAADCgcIBwAAAA==.Kobì:BAAALAADCggICgAAAA==.',Kp='Kpipo:BAAALAAECgIIAgAAAA==.',Kr='Kritoss:BAAALAAECgYICwAAAA==.Krolas:BAAALAAECgMIAwAAAA==.Krolya:BAAALAADCgcIBwAAAA==.',Ku='Kuniglunde:BAAALAAECgYIBgAAAA==.Kurj:BAAALAAECgMIAwAAAA==.',Ky='Kyleigh:BAAALAADCggIEwABLAAECgYIEQACAAAAAA==.Kyora:BAAALAADCggICAAAAA==.',La='Lacri:BAAALAAECgMIAwAAAA==.Lahrom:BAAALAADCggIDwAAAA==.Laiel:BAAALAAECgMIBQAAAA==.Larania:BAAALAAECgMIBQAAAA==.',Le='Leandra:BAAALAAECgMIBQAAAA==.Leviathan:BAAALAAECgQIBAAAAA==.',Li='Lichthirte:BAAALAAECgMIBgAAAA==.Liezzy:BAAALAAECgcIDgAAAA==.Lilith:BAAALAADCgcIBwABLAAECgYIDQACAAAAAA==.',Lo='Lonlyheart:BAAALAAECgEIAQAAAA==.Louboutin:BAAALAADCgcIDAAAAA==.Louisa:BAAALAAECgYICQAAAA==.',Lu='Luluchen:BAAALAAECgMIAwAAAA==.Lululicious:BAAALAAECgYIDwAAAA==.',Ly='Lydara:BAAALAAECgIIAgAAAA==.Lydith:BAAALAAECgMIAwAAAA==.Lynquay:BAAALAADCgMIAwAAAA==.',['Lé']='Léándrâ:BAAALAADCgIIAgAAAA==.',Ma='Madrikor:BAAALAADCggIEAAAAA==.Maeenae:BAAALAADCggICAAAAA==.Maerlon:BAAALAADCgcIBwABLAAECgYIDQACAAAAAA==.Malgorzata:BAAALAADCgUIBQAAAA==.Malvi:BAAALAAECgcIDwAAAA==.Maraseed:BAAALAAECgUICgAAAA==.Marfa:BAAALAADCgEIAQAAAA==.Markuss:BAAALAAECgMIBAAAAA==.Mattilde:BAAALAAECgMIBgAAAA==.Mayopumpapum:BAABLAAECoEUAAIHAAgIvB+wBwDQAgAHAAgIvB+wBwDQAgAAAA==.',Me='Meera:BAAALAADCgIIAgAAAA==.Meg:BAAALAADCgUIBwAAAA==.Melahunter:BAAALAADCggICAAAAA==.Melampous:BAAALAAECgIIAgAAAA==.Melapriest:BAAALAADCggICAAAAA==.Melirella:BAAALAAECgYIBgAAAA==.Mellchior:BAAALAADCgUIBQAAAA==.Melíandra:BAAALAAECgMIAwAAAA==.Menaxita:BAAALAADCgcIBwAAAA==.Menoxito:BAAALAAECggIDgAAAA==.Menáxi:BAAALAADCgcIBwAAAA==.Meracus:BAAALAAECgYICQAAAA==.Meyina:BAAALAADCgcIBwAAAA==.Meîmei:BAAALAADCgMIAQAAAA==.',Mh='Mhs:BAAALAADCgYIBgAAAA==.',Mi='Mihodh:BAAALAAECgMIBAAAAA==.Mirabeladin:BAAALAADCgMIAwAAAA==.Misseia:BAAALAAECgYICwAAAA==.Misstjara:BAAALAAECgIIAQAAAA==.Missyuki:BAAALAADCgIIAgAAAA==.',Mo='Monsieurfoox:BAAALAAECgMIBAAAAA==.Morkan:BAAALAADCggICwAAAA==.Mosh:BAAALAAECgIIAgAAAA==.',Mu='Mukuro:BAAALAADCggIEAAAAA==.',['Mâ']='Mâldânîus:BAAALAAECgYIDAAAAA==.Mâlefic:BAAALAAECgMIBQAAAA==.Mângo:BAAALAAECgcIDgAAAA==.',Na='Nacotic:BAAALAAECgQIAgAAAA==.Nacoya:BAAALAADCggICAAAAA==.Nagulander:BAAALAAECgEIAQAAAA==.Nallum:BAAALAADCggIFAAAAA==.Nandoriel:BAAALAAECgMIBQAAAA==.Nanyala:BAAALAAECgEIAQAAAA==.Nastya:BAAALAADCgMIAwAAAA==.',Ne='Necessaryevl:BAAALAAECgYICQAAAA==.Nerevar:BAAALAAECgcIDwAAAA==.',Ni='Nijusan:BAAALAAECgMIBgAAAA==.',No='Notarzt:BAAALAADCgIIAwABLAAECgMIBgACAAAAAA==.Noxera:BAAALAAECgYIBgAAAA==.',['Nâ']='Nâmîne:BAAALAAECgYIDwAAAA==.',Ob='Obsidia:BAAALAADCggIFgAAAA==.',Oc='Octaniaa:BAAALAAECgYIDAAAAA==.',Oh='Ohhermann:BAAALAAECgcIDwAAAA==.Ohmén:BAAALAAECgEIAQAAAA==.',Ol='Olalo:BAAALAADCggIEAAAAA==.',On='Onkeltotem:BAAALAAECgcIDQAAAA==.',Pa='Paladinwoo:BAAALAAECgEIAQAAAA==.Palladon:BAAALAADCggIEAAAAA==.Papungo:BAAALAAECgQIBgAAAA==.',Ph='Phíola:BAAALAAECgYICgAAAA==.',Pl='Plisanator:BAAALAADCgEIAQAAAA==.',Pr='Primse:BAAALAADCgMIAwAAAA==.Prowin:BAAALAADCgcICgAAAA==.',['Pá']='Pán:BAAALAAECgcICQAAAA==.',['Pî']='Pîkû:BAAALAADCgIIAgAAAA==.Pînot:BAAALAAECgcIDAAAAA==.',['Pö']='Pöserpube:BAAALAAECgMIAwAAAA==.',Ra='Ragosh:BAAALAAECgMIBQAAAA==.Raisu:BAAALAADCgIIAgAAAA==.Rangandi:BAAALAAECgIIAgABLAAECgcIDwACAAAAAA==.',Re='Rekz:BAAALAAECgMIAwAAAA==.Reorx:BAAALAAECggICAAAAA==.',Ri='Riö:BAAALAADCggICAAAAA==.',Ro='Rombosch:BAAALAADCgUIBwAAAA==.Rorey:BAAALAADCgcIBwAAAA==.Roy:BAAALAAECgMIBQAAAA==.',Ru='Rufuss:BAAALAADCggIEAAAAA==.',['Rà']='Ràven:BAAALAAECgMIAwAAAA==.',Sa='Saintnephis:BAAALAADCgIIAgAAAA==.Samaryl:BAAALAAECgYICQAAAA==.Samyrá:BAAALAAECgIIAgAAAA==.Sanndur:BAAALAAECgMIBQAAAA==.Sauerstøff:BAAALAAECgYICgAAAA==.',Sc='Schauni:BAAALAADCgUIBwAAAA==.Schein:BAAALAAECgIIAgAAAA==.Schmôggi:BAAALAADCgEIAQAAAA==.Schüppi:BAABLAAECoEVAAIKAAgIMx8sDACyAgAKAAgIMx8sDACyAgAAAA==.Schüppidk:BAAALAADCgYIBgABLAAECggIFQAKADMfAA==.',Se='Sealgaire:BAAALAADCggICgAAAA==.Sean:BAAALAAECggIDAAAAA==.Sedryn:BAAALAAECgMIAwAAAA==.Seishu:BAAALAAECgcICgAAAA==.Serrás:BAAALAAECgUICAAAAA==.Seshas:BAAALAAECgMIAwAAAA==.',Sh='Shadowbeast:BAAALAAECgMIAwAAAA==.Shadowlight:BAAALAADCgcIDgAAAA==.Shadowpilz:BAAALAAECgMIAwAAAA==.Shalara:BAABLAAECoEUAAIGAAcI4h4nGgDlAQAGAAcI4h4nGgDlAQAAAA==.Sharendra:BAAALAADCggIDAAAAA==.Sheenpala:BAAALAAECgcIDQAAAA==.Sheriva:BAAALAADCgcIFQAAAA==.Shiris:BAAALAADCgUIBwAAAA==.Shizam:BAAALAADCggICAAAAA==.Shmebulock:BAAALAADCggICAAAAA==.Shádow:BAAALAAECgYIBgAAAA==.',Si='Sidonía:BAAALAADCggICAAAAA==.Silverclaw:BAAALAADCggICAAAAA==.Silvereyes:BAAALAAECgIIAgAAAA==.Sixshido:BAAALAADCggIDgAAAA==.',Sk='Skarb:BAAALAADCggICAAAAA==.Skofnar:BAAALAADCgcIBwABLAAECgcIFAAGAOIeAA==.Skon:BAAALAADCgEIAQAAAA==.Skylarr:BAAALAADCggIEAAAAA==.Skár:BAAALAAECggIDQAAAA==.',Sm='Smogii:BAAALAAECgYIDAAAAA==.',Sn='Sniezka:BAAALAADCggIFwAAAA==.Snowie:BAAALAADCggIBQAAAA==.Snâg:BAAALAADCgcIBwABLAAECgcIDgACAAAAAA==.',So='Sonnenritter:BAAALAAECgYIBgAAAA==.',Sp='Spinatstrudl:BAAALAADCggIEAAAAA==.',Ss='Ssick:BAAALAAECgEIAQAAAA==.',St='Stahlbárt:BAAALAAECggIBgAAAA==.Stamos:BAAALAADCggIEAAAAA==.Steelwarrior:BAAALAAECgYICAAAAQ==.Stormdragon:BAAALAAECgIIAgAAAA==.Stormranger:BAAALAAECgMIBQAAAA==.',Su='Sundiego:BAAALAADCgIIAgAAAA==.',Sy='Sydba:BAAALAADCggIDwAAAA==.Sydrina:BAAALAADCgYIBgABLAAECgUICQACAAAAAA==.',['Sì']='Sìxtynine:BAAALAADCgcIBwAAAA==.',['Só']='Sóngoku:BAAALAADCggIDwABLAAECggIFAAEAEIlAA==.',Ta='Tavlin:BAAALAAECgMIBAAAAA==.',Te='Teeshâ:BAAALAAECgMIAwAAAA==.Tenten:BAAALAAECgcIDQAAAA==.Terenna:BAAALAADCgEIAQABLAAECgMIBgACAAAAAA==.Teth:BAAALAAECgMIBQAAAA==.',Th='Thallim:BAAALAAECgIIAgAAAA==.Thebigmage:BAAALAAECgYICwAAAA==.Thorodos:BAAALAAECgEIAQAAAA==.Thrunk:BAAALAADCgMIAwAAAA==.Thunderpi:BAAALAAECgcIBwAAAA==.Théséus:BAAALAADCggICAABLAAECgYICAACAAAAAQ==.Thúnder:BAAALAAFFAEIAQAAAA==.',Ti='Tiwalun:BAAALAAECgYICQAAAA==.',To='Toph:BAAALAAECgYIEQAAAA==.Torihl:BAAALAAECgYIBgAAAA==.Totemhirte:BAAALAADCggIDwAAAA==.Totemx:BAAALAADCgcICwAAAA==.',Tr='Traumjägér:BAAALAAECgMIBAAAAA==.',Tu='Tuladra:BAAALAAECgMIBgAAAA==.Turá:BAAALAADCggICAAAAA==.',Ty='Tyrosa:BAAALAAECgQICgAAAA==.',Va='Valareen:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.Valkstaff:BAAALAADCggIDwAAAA==.Valtiel:BAAALAAECgMIAwAAAA==.Vanhexing:BAAALAADCgYIBgAAAA==.Vanyas:BAAALAAECgIIAgAAAA==.Vardâ:BAAALAAECgQIAgAAAA==.Varionz:BAAALAAECgYICgAAAA==.',Ve='Veanwe:BAAALAAECgEIAQAAAA==.Vertrienne:BAAALAAECgUICgAAAA==.',Vi='Vinario:BAAALAAECgEIAQAAAA==.',Vo='Voidaria:BAAALAAFFAIIAwAAAA==.',Vr='Vrezael:BAAALAAECgYICQAAAA==.',We='Weiji:BAAALAADCgcIBwAAAA==.Weltenbrand:BAAALAADCgcICAAAAA==.Westcóast:BAAALAADCggIDwABLAAECggIFAAEAEIlAA==.',Wi='Wise:BAAALAADCggIDAABLAAFFAIIAwACAAAAAA==.',Xa='Xafira:BAAALAAECgMIBQAAAA==.',Xh='Xhavien:BAABLAAECoEXAAQLAAgIlx/DCgCzAgALAAgIkRvDCgCzAgAMAAYI9A+qCQC3AQANAAEIwg4dWAA6AAAAAA==.',['Xâ']='Xândo:BAABLAAECoEWAAMFAAgI4CF2AQAoAwAFAAgI4CF2AQAoAwAOAAQIpxavZgDjAAAAAA==.',Ye='Yeji:BAAALAADCggICAAAAA==.Yesco:BAAALAAECggICAAAAA==.',Ym='Ymo:BAAALAADCgUIBQAAAA==.',Yo='Yodâ:BAAALAAECgMIBAAAAA==.Youarefacked:BAAALAADCggICAAAAA==.Youkaii:BAAALAAECggICwAAAA==.',Yu='Yuji:BAAALAADCggIEAAAAA==.Yunarí:BAAALAAECgQIBwAAAA==.Yuvii:BAAALAAECgMIBgAAAA==.',Za='Zaps:BAAALAAECgMIBAAAAA==.',Ze='Zenon:BAAALAAECgcIDQAAAQ==.Zexíon:BAAALAADCgQIBAAAAA==.',Zi='Zirani:BAAALAAECgMIAwAAAA==.',Zo='Zookie:BAAALAAECgYICQAAAA==.Zorgul:BAAALAAECggICwAAAA==.',Zu='Zurî:BAAALAADCgMIAwAAAA==.',Zw='Zwergicus:BAAALAAECgIIAgAAAA==.',['Zî']='Zînîmînî:BAAALAAECgYIBwAAAA==.',['Ân']='Ândorâ:BAAALAADCgUIBQAAAA==.',['Âs']='Âsaron:BAAALAAECgMIAwAAAA==.',['Ät']='Ätrux:BAAALAADCgcIBwABLAAECgUICQACAAAAAA==.',['Ìs']='Ìsha:BAAALAADCgcIBwAAAA==.',['Ín']='Íní:BAAALAADCgMIAwAAAA==.',['Ða']='Ðarcja:BAAALAAECgcIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end