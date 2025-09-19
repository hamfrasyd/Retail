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
 local lookup = {'Monk-Windwalker','Druid-Guardian','Unknown-Unknown','Mage-Arcane','Shaman-Elemental','Warrior-Fury','Paladin-Retribution','DeathKnight-Frost','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Paladin-Protection','DeathKnight-Unholy','Evoker-Preservation','Hunter-BeastMastery','Priest-Holy',}; local provider = {region='EU',realm='Thunderhorn',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abdulsalam:BAABLAAECoEWAAIBAAgIcyTjAABeAwABAAgIcyTjAABeAwAAAA==.Abufahunt:BAAALAAECgYIEgAAAA==.',Ag='Agoniac:BAAALAAECgYIBgAAAA==.',Ah='Ahaiyuto:BAAALAAECgMIBgAAAA==.',Ak='Akcope:BAAALAADCgYIBgAAAA==.Akilin:BAAALAAECgMIAwAAAA==.',Al='Alarite:BAAALAAECgEIAQAAAA==.Alassien:BAAALAAECgMIBgAAAA==.Alhu:BAAALAADCgEIAQAAAA==.Altáriel:BAAALAAECgYIDAAAAA==.Alympia:BAAALAADCggIFwAAAA==.',Am='Ambrusik:BAABLAAECoEUAAICAAgI1x7lAADRAgACAAgI1x7lAADRAgAAAA==.Ammag:BAAALAAECgYIDAAAAA==.Amun:BAAALAADCgUIAgAAAA==.',An='Andromede:BAAALAAECgMIBgAAAA==.Angoran:BAAALAAECgQICAAAAA==.Angrygoose:BAAALAADCgcIBwAAAA==.',Ap='Apoly:BAAALAAECgEIAgAAAA==.Aporita:BAAALAADCggIFwAAAA==.',Ar='Aravel:BAAALAAECgMIAwAAAA==.Arcanight:BAAALAAECgEIAQAAAA==.Arcipopicis:BAAALAADCggIGAAAAA==.Ardegos:BAAALAADCgcIBwAAAA==.Arganelement:BAAALAADCggIDwAAAA==.Ariviel:BAAALAAECgYIDwAAAA==.Arkamedes:BAAALAADCgcIDgAAAA==.',As='Asta:BAAALAAECgcIDQAAAA==.Astalda:BAAALAADCggIFwAAAA==.',At='Athian:BAAALAAECgcIEwAAAA==.Athéh:BAAALAADCgcIFQAAAA==.',Aw='Aw:BAAALAADCggICAABLAAECgQIBAADAAAAAA==.',Ba='Bakterius:BAAALAAECgMIAwAAAA==.Bakulka:BAAALAAECgEIAQAAAA==.Balos:BAAALAAECgcIEwAAAA==.Balzakhaar:BAAALAADCgcIDAAAAA==.Barroth:BAAALAADCgcIBwAAAA==.',Be='Beastrr:BAAALAADCgEIAQABLAADCggIEQADAAAAAA==.Beefgrinder:BAAALAAECgcIDgAAAA==.Belanor:BAAALAADCggICAAAAA==.Beleren:BAABLAAECoEWAAIEAAgIviT+AwA7AwAEAAgIviT+AwA7AwAAAA==.Benihime:BAAALAAECgMIBAABLAAECgYIBgADAAAAAA==.Benju:BAAALAADCggICQAAAA==.',Bl='Blacklit:BAAALAAECggICwAAAA==.Bloodragnar:BAAALAAECgEIAQAAAA==.Bloodwork:BAAALAADCgIIAgAAAA==.Blubbergutz:BAAALAADCgcIEAAAAA==.Blády:BAAALAAECgYIDwAAAA==.',Bo='Bobhilde:BAAALAAECgMIBQAAAA==.Bobkotvurce:BAAALAAECgEIAQAAAA==.Bondye:BAABLAAECoEUAAIFAAgIKQ3ZGgDeAQAFAAgIKQ3ZGgDeAQAAAA==.Boogthyr:BAAALAADCggIBgAAAA==.Boomheadshot:BAAALAAECgIIAgAAAA==.Bosacik:BAAALAAECgEIAQAAAA==.',Br='Brisdk:BAAALAADCgcIDQAAAA==.',Bu='Buckler:BAAALAADCgcICQAAAA==.Budabudaa:BAAALAAECgMIBAAAAA==.Buldozer:BAAALAADCgcICAAAAA==.Bunnie:BAAALAADCgYIBgAAAA==.',['Bé']='Bééfcakés:BAAALAAECgYICgAAAA==.',['Bú']='Búh:BAAALAADCggIEAAAAA==.',Ca='Caleya:BAAALAAECgEIAQAAAA==.Castro:BAAALAADCgcIDQAAAA==.Cazian:BAAALAAECgQICAAAAA==.',Ce='Cenerae:BAAALAAECgMIBAAAAA==.Cerridwen:BAAALAAECgcICQAAAA==.Cerrsham:BAAALAAECgMIBwAAAA==.',Ch='Cheater:BAAALAADCggICAAAAA==.Chibsbawz:BAAALAAECgEIAQAAAA==.Chrisblast:BAAALAADCgUIBgAAAA==.Chriszugzug:BAAALAAECgEIAQAAAA==.Chrysta:BAAALAAECgIIAgABLAAECgcIEwADAAAAAA==.Chrystamist:BAAALAAECgcIEwAAAA==.',Ci='Cid:BAAALAAECgMIBgAAAA==.Cinek:BAAALAAECgYICgAAAA==.Cinerous:BAAALAADCggICAABLAAECgcIEwADAAAAAA==.Cirillá:BAAALAAECgYIDgAAAA==.',Cl='Clarendon:BAAALAADCggIEQAAAA==.',Co='Cognak:BAAALAADCggICwAAAA==.',Cr='Crungle:BAAALAAECgcIEAAAAA==.Crustysock:BAAALAAECgYIDgAAAA==.',Da='Daxtrila:BAAALAAECgIIBAAAAA==.',De='Deadfrost:BAAALAAECgcIEQAAAA==.Deagan:BAAALAADCgMIAwAAAA==.Deathbaron:BAAALAADCggIDQAAAA==.Deathdesmo:BAAALAADCgMIAwAAAA==.Deathnienna:BAAALAADCgcIDgABLAADCggIGAADAAAAAA==.Deathofchi:BAAALAADCggIDgAAAA==.Deepfell:BAAALAAECgMIBQAAAA==.Denebalgedi:BAAALAAECgYIDwAAAA==.',Di='Diabolist:BAAALAAECgYIDAAAAA==.Diabolisto:BAAALAAECgYICwAAAA==.Digimonic:BAAALAAECgcIDQAAAA==.Dinozo:BAAALAAECgYIDQAAAA==.Divinestorm:BAAALAADCgcIBwAAAA==.',Do='Doloxene:BAAALAAECgMIBQAAAA==.Dot:BAAALAAECgUIBQAAAA==.',Dr='Dracalu:BAAALAAECgYIDwAAAA==.Drexxyl:BAAALAADCgIIAgAAAA==.Driztdourden:BAAALAADCggICAAAAA==.Droderog:BAAALAADCggIDgABLAAECgYIDwADAAAAAA==.Druffy:BAAALAAECgYIDwAAAA==.',Du='Dualshock:BAAALAADCggICAAAAA==.Durinko:BAAALAAECgYIDAAAAA==.',Ef='Efearus:BAAALAAECgMIAwAAAA==.',Ei='Eiffah:BAAALAADCggIFwAAAA==.',El='Eldracono:BAAALAAECgMIBwAAAA==.Electricss:BAAALAAECgUICAAAAA==.Elpatron:BAABLAAECoEVAAIGAAgItBgkFQArAgAGAAgItBgkFQArAgAAAA==.',Em='Emberwing:BAAALAAECgMIAwAAAA==.Emphasized:BAAALAADCgcIBwAAAA==.',En='Enduras:BAAALAAECgQICAAAAA==.',Er='Eryteis:BAAALAAECgcIDAAAAA==.',Et='Etex:BAAALAAECgQICAAAAA==.',Ev='Evhuuker:BAAALAAECgMIBQAAAA==.',Fa='Fadewyn:BAAALAAECgQIBAABLAAFFAIIBAADAAAAAA==.Falcorr:BAAALAAECgIIAgAAAA==.Farqon:BAAALAAECgIIBAAAAA==.',Fe='Fennixx:BAEALAAECgYIDAAAAA==.',Fl='Flákotka:BAAALAADCggIFwAAAA==.',Fo='Fornixa:BAAALAAECgcIDAAAAA==.Foxilego:BAAALAAECgUICgAAAA==.',Fr='Frankíee:BAAALAAECgMIBQAAAA==.Frimtha:BAAALAAECgMIBwAAAA==.',Fu='Fuldaftrix:BAAALAAECgYICgAAAA==.',['Fä']='Fäith:BAAALAAECgIIAgAAAA==.',Ga='Gaalkaa:BAAALAADCggIDgAAAA==.',Gg='Gg:BAAALAADCggICwAAAA==.',Gh='Ghostid:BAAALAAECgYIDgAAAA==.Ghostmourne:BAAALAADCggIEwABLAAECgYIDgADAAAAAA==.',Gi='Gildedbeard:BAAALAAECgMIAwAAAA==.Gimdalf:BAABLAAECoEWAAIHAAgIvSUBAQCBAwAHAAgIvSUBAQCBAwAAAA==.Gine:BAAALAADCgUICgABLAAECgQIBAADAAAAAA==.',Go='Gotts:BAAALAAECgUIBwAAAA==.',Gr='Grimmo:BAAALAAECgYICAAAAA==.Grimous:BAAALAADCgcIBwAAAA==.Grisling:BAAALAADCggICAAAAA==.Groosome:BAAALAAECgEIAQAAAA==.Gryf:BAAALAADCgcIBwAAAA==.Gryph:BAAALAAECgMIBgAAAA==.',Gu='Gufr:BAAALAADCgcICQAAAA==.Guttenworgen:BAAALAAECgYICwAAAA==.',Ha='Haert:BAAALAADCggICAAAAA==.Hajø:BAAALAAECgcIEwAAAA==.Havi:BAAALAAECgcIEwAAAA==.',Hd='Hdh:BAAALAAECgYICQAAAA==.',He='Headshot:BAAALAAECggIDgAAAA==.Healga:BAAALAADCggIDgAAAA==.Helldrool:BAAALAAECgQICAAAAA==.Helltear:BAAALAADCgcIBwAAAA==.Henke:BAAALAAECgQIBwAAAA==.',Hi='Hiduken:BAAALAAECgYIDgAAAA==.Hildari:BAAALAAECgYIBwAAAA==.',Ho='Holy:BAAALAADCgYIBgAAAA==.Holycambria:BAAALAAECgYIDgAAAA==.Holymoli:BAAALAAECgIIAgAAAA==.Holywolf:BAAALAAECgcICQAAAA==.Hondra:BAAALAAECgYIBgAAAA==.Honilsom:BAAALAAECgYICAAAAA==.',Ig='Ignitis:BAAALAAECgUICAAAAA==.',Im='Imogine:BAEALAAECgcIEwAAAA==.',Io='Iona:BAAALAAECgYIDgAAAA==.Ioness:BAAALAAECgUIBQAAAA==.',Ir='Iridak:BAAALAAECgYIBgABLAAECggIFgAIAGchAA==.Ironside:BAAALAAECgYIDgAAAA==.',It='Italbuffino:BAAALAAECgMIAwAAAA==.',Iy='Iyzebel:BAAALAAECgMIAwAAAA==.',Ja='Jaksel:BAAALAAECgUIBQABLAAECggIGAAJAGAaAA==.',Je='Jeezu:BAAALAAECgQICAAAAA==.Jeremiah:BAAALAADCggICAAAAA==.',Jo='Joli:BAAALAAECgYIDAAAAA==.',Ju='Juistyna:BAAALAAECgEIAgAAAA==.',['Jé']='Jésý:BAAALAADCggIFwAAAA==.',Ka='Kahlen:BAAALAADCgIIAgAAAA==.Kaito:BAAALAADCggIEAAAAA==.Kaméllie:BAAALAAECgYIDgAAAA==.Karoliinka:BAAALAADCggIEwAAAA==.Karolinkalw:BAAALAAECgYICQAAAA==.',Ke='Kenlee:BAAALAAECgMIBQAAAA==.Kentán:BAAALAAECgYIDQAAAA==.',Kh='Khazos:BAAALAADCgcIDQAAAA==.',Ki='Kidlil:BAAALAADCggIEwAAAA==.Kiilshot:BAAALAAECggICAAAAA==.Kiree:BAAALAAECgMIBAAAAA==.',Kl='Klerdinia:BAAALAAECgYICQAAAA==.',Kn='Knatchlocker:BAAALAAECgEIAQAAAA==.',Ko='Kodariah:BAAALAAECgYIDwAAAA==.Kodarisah:BAAALAADCgYIBgABLAAECgYIDwADAAAAAA==.Konsu:BAAALAAECgMIBAAAAA==.',Kr='Kragira:BAAALAAECgYICQAAAA==.Krisoc:BAAALAAECggICAAAAA==.Krystalle:BAAALAADCgcIBwAAAA==.',Ky='Kyhulla:BAAALAAECgQIBAAAAA==.',['Kí']='Kíla:BAAALAAECggICAAAAA==.',['Kû']='Kûky:BAAALAAECgYICQABLAAECgYIDQADAAAAAA==.',La='Laday:BAAALAADCgIIAgAAAA==.Laivin:BAAALAAECgYICAAAAA==.Landoria:BAAALAADCggICgAAAA==.Landoría:BAAALAAECgQIBwAAAA==.',Le='Leaa:BAABLAAECoEVAAMKAAgIAxMwCABAAgAKAAgIgxIwCABAAgALAAEIwwxcZAA3AAAAAA==.Lesie:BAAALAAECggIDQAAAA==.Lesk:BAAALAADCgYIBgAAAA==.Lesong:BAAALAAECgEIAgAAAA==.Leyona:BAAALAADCggICAAAAA==.',Li='Lichdevil:BAAALAAECgMIBwAAAA==.Lillydan:BAAALAAFFAIIBAAAAA==.Linocka:BAAALAAECgcIEgAAAA==.Liora:BAAALAAECgEIAQAAAA==.Littlbits:BAAALAADCggIEAAAAA==.Lizix:BAAALAAECgYIDAAAAA==.',Lo='Lobster:BAAALAAECgMIAwAAAA==.Lorhaen:BAAALAADCgcICAAAAA==.Lowbros:BAAALAAECgEIAQAAAA==.Lowrider:BAAALAAECgQIBAAAAA==.Lowshot:BAAALAADCgcIDAAAAA==.',Lu='Lumikìssa:BAAALAAECgcIDwAAAA==.Lunarflare:BAAALAADCggICAABLAAECgQICAADAAAAAA==.Lunatoriana:BAAALAAECgIIAgAAAA==.Lusi:BAAALAAECgcIEwAAAA==.',Ly='Lycona:BAAALAADCgcIBwAAAA==.Lydor:BAAALAADCgIIAgAAAA==.',['Lò']='Lòthical:BAAALAAECgIIAgAAAA==.',Ma='Maahes:BAAALAADCggICAAAAA==.Mageby:BAAALAAECgYIDgAAAA==.Malchior:BAAALAADCggICAAAAA==.Mandrell:BAAALAADCgEIAQAAAA==.Mank:BAAALAADCggICAAAAA==.Manke:BAAALAAECgMIBAAAAA==.Markita:BAAALAAECgMIBQAAAA==.Masakry:BAAALAAECgcIDwAAAA==.Mathrin:BAAALAADCgcIDgAAAA==.Maydalena:BAAALAADCggIFgAAAA==.',Me='Meeleys:BAAALAAECgcIDwAAAA==.Mekkazap:BAAALAAECgYIBwAAAA==.Meruem:BAAALAAECgYIBgAAAA==.',Mi='Mikerino:BAAALAADCgIIAgAAAA==.Mikki:BAAALAAECgMIBQAAAA==.Milkacsoki:BAAALAADCgIIAgAAAA==.Milkmage:BAAALAADCgIIAgAAAA==.Minysek:BAAALAAECgEIAQAAAA==.',Mo='Mootz:BAAALAAECgUIBwAAAA==.Mortalbeam:BAAALAADCggICAAAAA==.Mosler:BAAALAAECgQICAAAAA==.',Mu='Musk:BAAALAADCgcICwAAAA==.',My='Myczlalka:BAAALAADCggIFwAAAA==.Myrscilka:BAAALAAECgYIDwAAAA==.',['Má']='Mákárá:BAABLAAECoEUAAIMAAcIhBl0FAAYAgAMAAcIhBl0FAAYAgAAAA==.',['Mé']='Mélfina:BAAALAAECgcICwAAAA==.',['Mü']='Müchomurka:BAAALAAECgYICwAAAA==.',Na='Naleno:BAAALAAECgcIEQAAAA==.Narak:BAAALAAECgcIEgAAAA==.Natanek:BAAALAAECgcIEwAAAA==.Naturelolxdb:BAAALAADCgYIBgAAAA==.Natylienacz:BAAALAAECgcIEQAAAA==.',Ne='Neferkhepri:BAAALAADCgcIDgAAAA==.Neirdae:BAAALAAECgYICwAAAA==.Nes:BAABLAAECoEWAAMNAAgILSOgAQAwAwANAAgIAiOgAQAwAwAHAAEI3SAlgwBaAAAAAA==.',Ni='Niobê:BAAALAAECgMIBQAAAA==.Niveann:BAAALAAECgMIBAAAAA==.',No='Noitatohtori:BAAALAAECgcIEQAAAA==.',Nu='Nuggies:BAAALAADCgIIAgAAAA==.',Nw='Nwal:BAAALAADCgcIBwAAAA==.',Ny='Nysahj:BAAALAAECgYIDwAAAA==.',['Ní']='Níghtfáll:BAAALAADCgYIBgAAAA==.',['Nö']='Nöxim:BAABLAAECoEUAAIBAAgIXxzaBgB8AgABAAgIXxzaBgB8AgAAAA==.',Ov='Ovee:BAAALAADCggIDgAAAA==.',Pa='Padlo:BAAALAADCggICAAAAA==.Panfiluta:BAAALAAECgMIBAAAAA==.Papajoe:BAAALAADCgQIBAABLAAECgQIBAADAAAAAA==.',Pe='Peepo:BAAALAAECggIEAAAAA==.',Pi='Pig:BAAALAAECgYICQAAAA==.Pikydk:BAAALAAECgYICQAAAA==.Pinkypong:BAAALAAECgMIBwAAAA==.Pivik:BAAALAAECgYIDAAAAA==.',Pl='Plechovej:BAAALAAECgYIEgAAAA==.',Po='Pomohaci:BAAALAAECgMIAwAAAA==.Poranek:BAAALAAECgMIBAAAAA==.Poro:BAAALAADCgcICAAAAA==.',Pr='Prciina:BAAALAAECgcIEQAAAA==.Prednizon:BAAALAAECgMIBQAAAA==.Proenitus:BAAALAAECgcIEwAAAA==.Proklety:BAAALAAECgEIAgAAAA==.Prompal:BAAALAAECgYIDwAAAA==.Proteboss:BAAALAAECgQIBwAAAA==.',['Pà']='Pàz:BAAALAAECgMIAwAAAA==.',Qa='Qaelrin:BAAALAAECgIIAgAAAA==.',Qu='Quantummyth:BAAALAADCgIIAgAAAA==.Quash:BAAALAAECgQIBAAAAA==.Quazigeorge:BAAALAADCgcICgAAAA==.',Qw='Qw:BAAALAAECgQIBAAAAA==.',Ra='Raarmas:BAAALAAECgUIBAAAAA==.Rafe:BAAALAAECgMIBQAAAA==.Rainbows:BAAALAADCgMIBAAAAA==.',Re='Redexice:BAAALAAECgMIAwAAAA==.Remaqe:BAAALAADCgcIBwAAAA==.Remuku:BAAALAADCgEIAQAAAA==.Rezz:BAAALAAECgEIAQAAAA==.',Rh='Rhaalph:BAAALAAECgMIAwAAAA==.',Ri='Rihox:BAAALAAECgQIBwAAAA==.Riwex:BAAALAADCgIIAgAAAA==.Rize:BAAALAADCgYICQAAAA==.',Ro='Robik:BAAALAAECgcIEgAAAA==.',Ry='Ryaz:BAAALAAECgIIAgAAAA==.',Sa='Saimage:BAAALAAECgQIBwAAAA==.Saleh:BAAALAAECggIBgAAAA==.Saley:BAAALAADCgcIEAAAAA==.Sandshrew:BAAALAADCggIFQAAAA==.Sazzlay:BAAALAADCgIIAgAAAA==.',Sc='Scoobacca:BAAALAADCgcIDAAAAA==.Scrappydoo:BAAALAADCgcIBwAAAA==.Scullptor:BAAALAAECgMIBwAAAA==.',Se='Sectator:BAAALAAECgYIDgAAAA==.Selentia:BAAALAADCggICAAAAA==.Senron:BAAALAAECgIIAgAAAA==.Sergen:BAAALAAECgQIBgAAAA==.Serina:BAAALAADCgcIBwAAAA==.Serratus:BAAALAAECgQIBAAAAA==.Serza:BAAALAAECgcIDQABLAAECgQIBgADAAAAAA==.Setartucus:BAAALAADCgIIAgAAAA==.Sevilla:BAAALAADCgIIAgAAAA==.Sevispook:BAAALAAECgUIBQAAAA==.',Sh='Shadepunk:BAAALAADCggIFQAAAA==.Shadprincess:BAAALAAECgQICAAAAA==.Shagorsemst:BAAALAADCgEIAQAAAA==.Shammy:BAAALAAECgMIAwAAAA==.Shammyami:BAAALAADCgcICgAAAA==.Shankyernan:BAAALAADCgcIBwAAAA==.Shexye:BAAALAAECgIIAgAAAA==.Shigi:BAAALAAECgUIBwAAAA==.Shootfire:BAAALAAECgYIBgAAAA==.Shortpala:BAAALAADCgEIAQAAAA==.',Si='Siko:BAAALAADCgMIAwAAAA==.Silentshot:BAAALAAECgYIEgAAAA==.Simonthedk:BAAALAAECgYICgAAAA==.Simurgh:BAAALAAECgUIBQAAAA==.Sisar:BAAALAADCggIFwAAAA==.',Sk='Skelendi:BAAALAADCgQIBwAAAA==.Skorina:BAAALAAECgIIAgAAAA==.',Sl='Sleepyjoe:BAAALAADCgcIBwAAAA==.Sloe:BAAALAAECgYIDAAAAA==.Sluchátka:BAAALAAECgUIAwAAAA==.',Sm='Smolneen:BAAALAAECgYIBwAAAA==.Smrtacek:BAAALAADCggIFQAAAA==.',Sn='Snowey:BAABLAAECoEVAAMIAAgIbx+NCAD0AgAIAAgIbx+NCAD0AgAOAAII8B7wJQClAAAAAA==.Snuam:BAABLAAECoEUAAIPAAgIrx4PAgDLAgAPAAgIrx4PAgDLAgAAAA==.',Sp='Spagetak:BAAALAADCgcIBwAAAA==.Sprite:BAAALAAECgMIBwAAAA==.Spudclot:BAAALAAECgQIBwAAAA==.Spudmonk:BAAALAAECgMIBQABLAAECgQIBwADAAAAAA==.',Sq='Squànchy:BAAALAAECgYIDgAAAA==.',St='Stebbs:BAAALAADCgcIDgAAAA==.Stormpooper:BAABLAAECoEWAAIQAAgIRiHSBwDrAgAQAAgIRiHSBwDrAgAAAA==.Stulin:BAAALAADCggICAAAAA==.Stítch:BAAALAADCggICwAAAA==.',Su='Suei:BAAALAADCgcIBwAAAA==.Sundaysangel:BAAALAADCggIEgAAAA==.',Sv='Svelto:BAAALAAECgEIAQAAAA==.',Sw='Swell:BAAALAAECgUIBQAAAA==.',['Sí']='Símurg:BAAALAAECgMIBgAAAA==.',Ta='Tacolimey:BAAALAAECgcICQAAAA==.Tambari:BAAALAADCggIEAAAAA==.Taraskova:BAAALAAECgYIDgAAAA==.Tauros:BAAALAADCggICAAAAA==.Tayem:BAAALAAECgcIDQAAAA==.',Te='Tenebris:BAAALAADCgMIAwAAAA==.Teolines:BAAALAAECgIIAgAAAA==.Terhenwizzle:BAAALAAECgYIBgAAAA==.Tesara:BAAALAAECgIIAgAAAA==.',Th='Thenightelf:BAAALAADCgQIBAAAAA==.Thenoob:BAAALAAECgEIAQAAAA==.Thergurn:BAAALAADCgUIBwAAAA==.Thisbee:BAAALAAECgEIAgAAAA==.Thoorstein:BAAALAAECgMIBQAAAA==.Thrond:BAAALAADCggICgAAAA==.Thunderbolt:BAABLAAECoEUAAIQAAcIgRhKFwAtAgAQAAcIgRhKFwAtAgAAAA==.Thundering:BAAALAAECgcIDQABLAAECgcIFAAQAIEYAA==.',Ti='Tiazi:BAAALAADCggICAAAAA==.Timeismoney:BAAALAADCggIDAAAAA==.',To='Toftewolfe:BAAALAADCgQIBAAAAA==.Tokelau:BAAALAADCgIIAgAAAA==.Tooawesome:BAAALAADCgMIBAAAAA==.Torangon:BAAALAAECgcIEQAAAA==.',Tr='Trabantdh:BAAALAAECgIIAgAAAA==.Trynite:BAAALAAECgUIBwAAAA==.',Ty='Tylan:BAAALAAECgcIEgAAAA==.Tyrodar:BAAALAAECgMIBAAAAA==.',Ul='Ulgy:BAAALAAECgcIEAAAAA==.',Un='Uneducated:BAAALAADCgcIBwAAAA==.',Up='Uppity:BAAALAAECgYICgAAAA==.',Va='Valchyna:BAAALAAECgMIAgAAAA==.Valkýra:BAAALAAECgUIBQAAAA==.Valontuoja:BAAALAADCgQIBAABLAAECgcIDwADAAAAAA==.Valuna:BAAALAAECgQICAAAAA==.',Ve='Velaru:BAAALAADCgMIAwAAAA==.Velepytel:BAAALAAECgMIAwAAAA==.Velinia:BAAALAAECgYICwAAAA==.Veliria:BAAALAAECgYICQAAAA==.Velkyprcek:BAAALAADCggIEAABLAAECgcIEQADAAAAAA==.Velure:BAAALAAECgYIDAAAAA==.Veranka:BAAALAAECggIEQAAAA==.Vezire:BAAALAADCgcIBwAAAA==.',Vi='Vitally:BAAALAADCggIDwAAAA==.',Vl='Vlczak:BAABLAAECoEUAAIBAAgIvSGTAgAXAwABAAgIvSGTAgAXAwAAAA==.',Vo='Voidria:BAAALAAECgMIBgAAAA==.Vojthino:BAAALAAECgcIEQAAAA==.',Vr='Vrana:BAAALAADCgcIDwAAAA==.',Wa='Warbarbie:BAAALAADCggIDAAAAA==.',Wc='Wcranee:BAAALAAECgMIAwAAAA==.',We='Weatherwitch:BAAALAADCggIEgAAAA==.Welrion:BAAALAAECgMIBAAAAA==.Wenron:BAAALAADCggIEgAAAA==.',Wi='Wilczur:BAAALAAECgMIBAAAAA==.Wilke:BAAALAAECgYIDAAAAA==.Wixxyz:BAAALAAECgcIEAAAAA==.',Wo='Woottoot:BAAALAADCggIFgAAAA==.Wordlesspie:BAAALAAECgYIDwAAAA==.',Xe='Xempo:BAAALAAECgYIDAAAAA==.',Xr='Xrathis:BAAALAADCggICAAAAA==.',Ya='Yasmíne:BAAALAADCggICAAAAA==.',Yb='Ybolga:BAAALAAECgYICQAAAA==.',Ye='Yersimr:BAAALAAECgMIAwAAAA==.',Za='Zatrý:BAAALAAECgcICgAAAA==.Zatrýý:BAAALAADCgcIBwAAAA==.',Ze='Zenwalker:BAAALAADCgcIBwAAAA==.Zerges:BAAALAADCggIEgAAAA==.Zeryk:BAAALAAECgMIAwAAAA==.Zevron:BAAALAAECgUIBQAAAA==.',Zi='Zifro:BAAALAAECgEIAQAAAA==.Zindanrish:BAAALAAECgYIEgAAAA==.Zirka:BAABLAAECoEUAAIRAAgIGwzlHwCxAQARAAgIGwzlHwCxAQAAAA==.',Zu='Zuellusek:BAAALAADCggIFQAAAA==.Zulul:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end