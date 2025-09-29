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
 local lookup = {'Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','Evoker-Augmentation','Warlock-Destruction','Druid-Feral','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','Priest-Shadow','Priest-Holy','Paladin-Retribution','Shaman-Restoration','Warrior-Fury','Warrior-Protection','Evoker-Devastation','DeathKnight-Blood','Unknown-Unknown','Shaman-Elemental','Mage-Arcane','DemonHunter-Havoc','Priest-Discipline','Paladin-Holy','Mage-Fire','DemonHunter-Vengeance','Druid-Balance','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','Warlock-Demonology','Hunter-Survival','Rogue-Subtlety',}; local provider = {region='EU',realm='Karazhan',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aavux:BAABLAAECoEhAAIBAAgIDRooHwBRAgABAAgIDRooHwBRAgAAAA==.',Ae='Aedàn:BAAALAADCgcIBwAAAA==.Aethio:BAAALAAECgIIAgABLAAFFAQIDAACABQZAA==.Aethonox:BAAALAAECggIBgAAAA==.',Ag='Aglack:BAAALAAECgIIAgAAAA==.',Ai='Airman:BAAALAAECgIIAgAAAA==.',Ak='Akronnys:BAABLAAECoEWAAIDAAcICwgUPgBMAQADAAcICwgUPgBMAQAAAA==.',Al='Algethi:BAAALAADCggICAABLAAECggIHAAEAK8LAA==.Alina:BAAALAADCgcIDQAAAA==.Alphapo:BAAALAAECggICAAAAA==.Altergeist:BAAALAAECgQIBQAAAA==.',Am='Amarabub:BAAALAADCggICAAAAA==.',An='Andaluria:BAAALAADCggICAAAAA==.Andragon:BAAALAAECgMIAwAAAA==.Andrahad:BAAALAAECgYIDQAAAA==.',Ap='Aphotic:BAAALAADCggICAABLAAFFAIIBQAFANEMAA==.',Ar='Arinitti:BAAALAAECgIIAQAAAA==.Arnathil:BAAALAAECggIEgAAAA==.Arthuss:BAAALAAECgIIAgAAAA==.Articono:BAAALAAECggICAAAAA==.',Au='Auer:BAAALAADCggICAABLAAFFAIIBgAGAE4lAA==.',Az='Azeous:BAAALAAECggICAAAAA==.',Ba='Battôsai:BAABLAAECoEgAAIHAAgIfR7KBwDGAgAHAAgIfR7KBwDGAgAAAA==.',Bc='Bcklige:BAABLAAECoEPAAIIAAgIvgmcsQBjAQAIAAgIvgmcsQBjAQABLAAFFAIIBgAJAPcdAA==.',Be='Beliriosus:BAAALAAECggIEgAAAA==.Bemortal:BAABLAAFFIEHAAIIAAMIMBfTKQCoAAAIAAMIMBfTKQCoAAAAAA==.Bemortals:BAAALAAECgUIBQABLAAFFAMIBwAIADAXAA==.',Bi='Bicklige:BAACLAAFFIEGAAIJAAII9x1NDQC5AAAJAAII9x1NDQC5AAAsAAQKgTQAAgkACAigJm4AAIsDAAkACAigJm4AAIsDAAAA.Bimortals:BAAALAADCggICgABLAAFFAMIBwAIADAXAA==.',Bl='Blades:BAAALAADCgcIHAAAAA==.Bloodone:BAAALAAECgEIAQAAAA==.',Bm='Bmortal:BAAALAAECgYIBgABLAAFFAMIBwAIADAXAA==.',Br='Brandón:BAAALAAECgMIAwAAAA==.Brickedpope:BAABLAAECoEXAAMKAAcI0hgOLAD+AQAKAAcI0hgOLAD+AQALAAEIQQlFnwA1AAAAAA==.Brokk:BAAALAADCggICAABLAAFFAUIDgAMAKwZAA==.',Bu='Buildmeister:BAAALAAECgcIEgAAAA==.Bumbuliits:BAABLAAECoESAAICAAcIbh9iNABAAgACAAcIbh9iNABAAgAAAA==.Burnthedemon:BAAALAADCgUICgAAAA==.',Ca='Caleidas:BAAALAADCgcIDAAAAA==.Calida:BAAALAAECgYIBgAAAA==.Caltaq:BAAALAAECgUIBQAAAA==.Caprice:BAAALAAECgQICgAAAA==.Carlitôz:BAAALAADCggICAABLAAECggIIAANAMYmAA==.',Ce='Celice:BAAALAAECgQICAAAAA==.',Ch='Chamdrin:BAAALAADCgcIBwAAAA==.Charliexcx:BAAALAADCgQIBAAAAA==.Charlock:BAAALAAECggIDgAAAA==.Chochana:BAAALAADCgYIBgAAAA==.',Ci='Cibbry:BAAALAADCgQIBwAAAA==.',Co='Comastca:BAAALAAECggIEQAAAA==.',Cr='Crackattack:BAABLAAECoEUAAIBAAYIdx/CLAD5AQABAAYIdx/CLAD5AQAAAA==.Crackshot:BAAALAAECgUICAAAAA==.Cripleknight:BAAALAAECgQIBgAAAA==.Cryopriest:BAACLAAFFIEJAAIKAAMI2hUlDQDrAAAKAAMI2hUlDQDrAAAsAAQKgSEAAgoACAiGI9EIACMDAAoACAiGI9EIACMDAAAA.Cryowar:BAABLAAECoEgAAMOAAgIHR6MFwDVAgAOAAgIsB2MFwDVAgAPAAcITxBPMwB0AQAAAA==.',Cu='Cuggul:BAAALAAECgcIEQAAAA==.',Cy='Cynder:BAABLAAECoEgAAIQAAgImg4zIwDcAQAQAAgImg4zIwDcAQAAAA==.',Da='Dalix:BAAALAAFFAIIAwAAAA==.Damianoo:BAAALAAECgEIAQAAAA==.Darkmatter:BAAALAAECggIEAAAAA==.',De='Deathanddk:BAAALAADCgUIBQAAAA==.Deatherlo:BAABLAAECoEXAAIIAAYI9B5tVAAZAgAIAAYI9B5tVAAZAgAAAA==.Deathwalker:BAAALAAECgYICgAAAA==.Debieltje:BAACLAAFFIEKAAQHAAMIYSN/AwAiAQAHAAMI5x9/AwAiAQARAAIINQ2HCwB+AAAIAAEIqCQUWwBvAAAsAAQKgScABAcACAjvJUsBAF0DAAcACAjvJUsBAF0DABEACAjDG28JAJUCAAgAAwhGH571AN0AAAAA.Demonil:BAAALAADCgEIAQAAAA==.Desi:BAABLAAECoEVAAICAAcIDg1mhABoAQACAAcIDg1mhABoAQAAAA==.',Dh='Dhanvantari:BAAALAADCggIJQAAAA==.',Di='Dianase:BAAALAAECgcIDwAAAA==.Disc:BAAALAAECggICAAAAA==.Disceplin:BAAALAADCggICwABLAAECgMIAwASAAAAAA==.Disk:BAAALAAECggICAAAAA==.Diya:BAACLAAFFIEJAAINAAMIgSOPCAA5AQANAAMIgSOPCAA5AQAsAAQKgS4AAw0ACAgZJkICAFQDAA0ACAgZJkICAFQDABMAAQh9DZKoADIAAAAA.',Dj='Djonz:BAAALAAECgQICAAAAA==.Djtwo:BAABLAAECoEXAAIUAAcI9w8IZwCpAQAUAAcI9w8IZwCpAQABLAAFFAYIHAAEAEIWAA==.',Dr='Drakkan:BAACLAAFFIEJAAIMAAMIYA57EADkAAAMAAMIYA57EADkAAAsAAQKgS4AAgwACAiPIUwZAPECAAwACAiPIUwZAPECAAAA.Drzed:BAABLAAECoEUAAIVAAgIJhtDKwCFAgAVAAgIJhtDKwCFAgAAAA==.',Du='Duppi:BAAALAAECggIJgAAAQ==.',Dw='Dwarfmorph:BAAALAAECgcICgABLAAFFAIIBAASAAAAAA==.Dwel:BAACLAAFFIEHAAMLAAMIwhvACgAbAQALAAMIwhvACgAbAQAWAAIIgREcAgCNAAAsAAQKgSgAAxYACAiqITYCANECAAsACAgoIO0LAPMCABYACAiwHjYCANECAAAA.',['Dí']='Díana:BAAALAADCgUIBQAAAA==.',Ea='Earwin:BAABLAAECoEbAAIXAAgIZA8rIwDHAQAXAAgIZA8rIwDHAQAAAA==.',Ef='Efern:BAABLAAECoEUAAIFAAcIdAy3ZACHAQAFAAcIdAy3ZACHAQAAAA==.',En='Entropeth:BAAALAAECgIIAgAAAA==.Enyo:BAAALAADCgcIBwABLAAECggIHAAEAK8LAA==.',Er='Erduhoar:BAAALAADCgMIBAAAAA==.',Fa='Falk:BAAALAADCggICAABLAAFFAMICwAYAAUYAA==.',Fe='Felipoz:BAACLAAFFIEHAAMZAAMIVBcqAwDmAAAZAAMIVBcqAwDmAAAVAAIIUBlhJQCcAAAsAAQKgSsAAxkACAibIhUGAOYCABkACAhRIRUGAOYCABUACAiVHiAkAKgCAAAA.Felixjaeger:BAAALAADCggIGwAAAA==.Feraloration:BAABLAAECoEbAAIaAAgIUA93OQCaAQAaAAgIUA93OQCaAQAAAA==.Feythion:BAACLAAFFIEFAAIbAAII9AdXDwCFAAAbAAII9AdXDwCFAAAsAAQKgRYABBwACAhWGjYYABYCABwACAhWGjYYABYCABsAAQjdC5VFADEAAB0AAQi0GAAAAAAAAAAA.',Fi='Firefiddy:BAAALAADCgIIAgAAAA==.Firekung:BAAALAAECggICAAAAA==.',Fl='Flaxxmix:BAAALAAECgcIBwAAAA==.',Fr='Frumpwarden:BAAALAADCgYIBwAAAA==.',Fu='Furrball:BAAALAAECgcIBwAAAA==.Fuzzybeast:BAAALAAECgYICwAAAA==.',Ga='Gabzz:BAACLAAFFIELAAMYAAMIBRjVAQDtAAAYAAMIDA3VAQDtAAADAAIIzxwFCQCgAAAsAAQKgS4ABAMACAiOI48FACUDAAMACAiKI48FACUDABgACAhbG6oCAJwCABQACAgQEWxXANYBAAAA.Galadin:BAAALAAECggICAAAAA==.Galaxes:BAAALAAECgIIBAAAAA==.Garez:BAAALAADCgIIAgAAAA==.',Gd='Gdpriest:BAAALAAECgYIEAAAAA==.',Go='Goatyboi:BAAALAAFFAIIAgAAAA==.Goliäth:BAABLAAECoEiAAIHAAgI7Q8bFgD0AQAHAAgI7Q8bFgD0AQAAAA==.',Gr='Granty:BAAALAADCgUIBQAAAA==.Grindelwald:BAABLAAECoEeAAQeAAgIGxubBwAwAgAeAAcIThmbBwAwAgAfAAgIChFbHwDlAQAFAAIIQAtsxABdAAABLAAECggIIAAHAH0eAA==.',['Gö']='Götet:BAAALAADCggICAAAAA==.',Ha='Harmöny:BAAALAAECgYICQAAAA==.Havocado:BAAALAAECgMIBAAAAA==.',Hi='Highchief:BAABLAAECoEhAAIPAAgIyB1yDgChAgAPAAgIyB1yDgChAgAAAA==.',Ho='Holycow:BAAALAADCggIEAAAAA==.Holynuka:BAABLAAECoEUAAIMAAcIhw4ClACMAQAMAAcIhw4ClACMAQAAAA==.Holysmasher:BAAALAAECgQIBAAAAA==.Hova:BAAALAADCgUIBgAAAA==.',Hu='Hungsolo:BAAALAAECgYIEgAAAA==.',Ic='Icaríum:BAABLAAECoEjAAIZAAgIpxtyDABkAgAZAAgIpxtyDABkAgAAAA==.',Id='Idioot:BAAALAAECgUIDgAAAA==.',Ig='Igotbubble:BAAALAAECggIGgAAAQ==.',Io='Iol:BAAALAADCggICAABLAAECggIIAANAMYmAA==.',Ja='Jacinto:BAAALAAECgYIDQAAAA==.Jamaico:BAABLAAECoEaAAMBAAYIfx8VYwATAQABAAMI6yAVYwATAQACAAMIEx5LvwDnAAAAAA==.',Jo='Joltcola:BAABLAAECoEgAAINAAgIxiZJAACCAwANAAgIxiZJAACCAwAAAA==.',Jp='Jpbrr:BAAALAADCggICAAAAA==.Jpdracc:BAAALAADCggICAAAAA==.Jpoopmypants:BAAALAAFFAMIAwAAAA==.',Ju='Juicen:BAAALAAECggIEwAAAA==.Justlock:BAAALAAECgcIDwABLAAECggIGAAMAGAZAA==.',Ka='Kalyssa:BAAALAAECgYIDQAAAA==.Karakize:BAAALAADCgcIBwAAAA==.Kaskassim:BAAALAAECgYIDwAAAA==.Kasteczuz:BAAALAADCggICAAAAA==.Katukas:BAACLAAFFIEHAAIgAAMImhvcAAAVAQAgAAMImhvcAAAVAQAsAAQKgSgAAiAACAirIlwBACoDACAACAirIlwBACoDAAAA.',Ki='Kikle:BAABLAAECoEbAAIMAAgIbR3CLACSAgAMAAgIbR3CLACSAgAAAA==.',Ko='Koggan:BAAALAAECgMIAQAAAA==.',Ku='Kulamagdula:BAAALAADCgcIBwAAAA==.Kusneydruid:BAAALAAECgEIAQABLAAFFAIIBQAcAMYhAA==.Kusneymonk:BAACLAAFFIEFAAIcAAIIxiHSBwDIAAAcAAIIxiHSBwDIAAAsAAQKgR0AAx0ACAhlJscAAHwDAB0ACAhlJscAAHwDABwAAQgyICtPAF4AAAAA.Kusneyrogue:BAABLAAECoEZAAMhAAgI1yKiBQDZAgAhAAgIOiGiBQDZAgAJAAYIgh+dJgDPAQABLAAFFAIIBQAcAMYhAA==.Kusneywar:BAAALAAECgcIEQABLAAFFAIIBQAcAMYhAA==.',['Ká']='Káal:BAABLAAECoEmAAIOAAgIwRrtJgBvAgAOAAgIwRrtJgBvAgAAAA==.',La='Lackra:BAAALAAECgMIAwAAAA==.Lackro:BAABLAAECoEmAAIIAAgIqiNmDgApAwAIAAgIqiNmDgApAwAAAA==.Lackroo:BAAALAAECgIIAgAAAA==.Laik:BAAALAADCgIIAgAAAA==.Lazari:BAAALAADCggICAAAAA==.',Le='Legalad:BAAALAADCggIEAAAAA==.',Li='Linvala:BAAALAADCggICAAAAA==.',Lk='Lkoued:BAAALAADCgUIBgAAAA==.',Lo='Lockiè:BAAALAAECgYIBgAAAA==.Lokthar:BAAALAAECgYIEAAAAA==.Loladino:BAAALAAECgIIAgAAAA==.Lost:BAAALAADCggICAAAAA==.Lovenote:BAAALAADCgEIAQAAAA==.',Lu='Lunya:BAABLAAECoEdAAIMAAgIVSFYGgDsAgAMAAgIVSFYGgDsAgAAAA==.',Lv='Lv:BAABLAAECoEXAAIMAAcI/x5KMACDAgAMAAcI/x5KMACDAgAAAA==.',Ly='Lynex:BAAALAAECgIIBAAAAA==.',['Lé']='Léhál:BAAALAAECggIEAAAAA==.',Ma='Madoushi:BAAALAAECgEIAQAAAA==.Madstorm:BAAALAAECgcIDgAAAA==.Magnusz:BAAALAAECgYICgAAAA==.Magx:BAAALAAECgYIBgABLAAFFAIIBQAbAPQHAA==.Makhel:BAAALAADCgcIBwABLAAECggIIAAHAH0eAA==.Marfa:BAAALAAECgYICAAAAA==.Marone:BAAALAADCgYICgAAAA==.Marsplant:BAAALAAECggICAAAAA==.Maverick:BAAALAADCgMIAwABLAAECgYIBgASAAAAAA==.',Mc='Mcmanz:BAAALAAECggIAwAAAA==.',Me='Mechamonk:BAAALAAECgYIDwABLAAFFAMIBwAbAJUiAA==.Meowlock:BAAALAADCgMIAwAAAA==.Merfs:BAAALAAECgYIDQAAAA==.Metrox:BAAALAAECggICAAAAA==.',Mi='Mischiefra:BAAALAADCggIGwAAAA==.',Mo='Mooe:BAAALAAECggICAAAAA==.Moofassa:BAAALAADCggIFAAAAA==.',Mu='Muleria:BAAALAADCgIIAgAAAA==.',My='Myfaith:BAAALAADCgYIBgAAAA==.Myzzo:BAAALAAECgYIDAAAAA==.',['Má']='Málly:BAAALAAECgcIEwAAAA==.',['Mö']='Mörkerz:BAAALAAECgYIDwAAAA==.',Na='Naidala:BAABLAAECoFBAAIUAAgIIBiELQB0AgAUAAgIIBiELQB0AgAAAA==.Najimä:BAAALAADCggICQAAAA==.Naverene:BAAALAAECgcIDgAAAA==.Nayomi:BAAALAADCgYIBgABLAAECgMIAwASAAAAAA==.',Ne='Nedol:BAAALAAECgEIAQAAAQ==.Neiloth:BAAALAAECgUIBwAAAA==.Nell:BAAALAAFFAIIAwAAAQ==.',Ni='Nibel:BAABLAAECoEiAAIPAAgIRBeYGgAiAgAPAAgIRBeYGgAiAgAAAA==.Nightroar:BAAALAAECgIIAwAAAA==.',No='Noodle:BAAALAAECggIDgABLAAFFAQIEAAhAMETAA==.Nowaytorun:BAAALAAECgMIBAAAAA==.',Nu='Nuka:BAAALAAECgYICwAAAA==.',Ny='Nyxsil:BAAALAADCggIDQAAAA==.',['Né']='Nééko:BAAALAAECggIBgAAAA==.',Oc='October:BAAALAAECgYICwAAAA==.',Od='Oda:BAACLAAFFIEHAAIbAAMIlSKRBwDjAAAbAAMIlSKRBwDjAAAsAAQKgSkAAhsACAh3JpAAAHQDABsACAh3JpAAAHQDAAAA.Odingrippy:BAAALAAECgUIBQAAAA==.Odinwarrior:BAABLAAECoErAAIPAAgINiP1BQAfAwAPAAgINiP1BQAfAwAAAA==.',Ok='Okoo:BAAALAAECgUICQAAAA==.',Or='Oriens:BAABLAAECoEUAAIBAAYIjCHeOgCvAQABAAYIjCHeOgCvAQAAAA==.',Pa='Palamok:BAAALAADCgcIBwAAAA==.Palando:BAAALAADCgUIBQAAAA==.Palastick:BAAALAADCgUIBQAAAA==.Palayumix:BAAALAAECgMIAwAAAA==.Paraceta:BAAALAADCggICAAAAA==.',Pe='Peldronn:BAAALAADCggIDwAAAA==.Pepe:BAAALAADCgcIBwAAAA==.',Pi='Pigwa:BAAALAAECgYIDwAAAA==.Pitchou:BAACLAAFFIEGAAIGAAIIcQ1YCgCWAAAGAAIIcQ1YCgCWAAAsAAQKgR4AAgYABwiNHfAMAFUCAAYABwiNHfAMAFUCAAAA.',Pl='Plork:BAABLAAECoEUAAIOAAgI1hFxQAD3AQAOAAgI1hFxQAD3AQAAAA==.',Po='Poka:BAEALAAFFAIIAgABLAAFFAcIHAAMAPIiAA==.Polgaria:BAAALAAECgcIDgAAAA==.',Pr='Preb:BAAALAAECgUIBQAAAA==.Pressure:BAAALAAECgYIEQAAAA==.Profound:BAAALAADCgMIAwAAAA==.Prottyprott:BAAALAAECgQICAAAAA==.Prézz:BAAALAAECgEIAQAAAA==.',Pu='Puth:BAAALAADCggICAAAAA==.',Ra='Randhunter:BAAALAADCggIGAABLAAECgYIBgASAAAAAA==.Randproest:BAAALAAECgYIBgAAAA==.Randragon:BAAALAADCgYIBgABLAAECgYIBgASAAAAAA==.Rawrzen:BAAALAADCgcICQAAAA==.',Re='Redarrow:BAAALAADCgYIBgAAAA==.Reia:BAACLAAFFIEOAAIMAAUIrBlEBADQAQAMAAUIrBlEBADQAQAsAAQKgSAAAgwACAjsJUoDAHoDAAwACAjsJUoDAHoDAAAA.Reiadhd:BAAALAAECgcIDAABLAAFFAUIDgAMAKwZAA==.Renado:BAAALAAECgYICwAAAA==.Retainer:BAAALAADCggICAAAAA==.',Ro='Rockandstone:BAABLAAECoEYAAITAAgIchaAKgA7AgATAAgIchaAKgA7AgAAAA==.Rongwan:BAAALAAECgUIBQAAAA==.',['Ró']='Róan:BAAALAADCggIDgAAAA==.',Sc='Scully:BAAALAAECggIDwAAAA==.',Se='Seldarina:BAABLAAECoEYAAIHAAgIixAYEwAXAgAHAAgIixAYEwAXAgAAAA==.',Sh='Shadowpaws:BAAALAAECgMIAwAAAA==.Shamastic:BAAALAAECgUIBgAAAA==.Shammymcdady:BAAALAADCggIEQABLAAFFAMICgABAKYlAA==.Shawan:BAABLAAECoEXAAINAAgIcBTHQQDpAQANAAgIcBTHQQDpAQAAAA==.',Si='Sigmaboy:BAAALAAECggICAAAAA==.Sittam:BAAALAAFFAIIAgABLAAFFAMIBwAbAJUiAA==.',So='Sorrowfull:BAABLAAECoEeAAIMAAgIGggQvwA9AQAMAAgIGggQvwA9AQAAAA==.Soulbreaker:BAAALAAECgYIBgAAAA==.Soulcooker:BAABLAAECoEYAAIFAAgIjxngJwB0AgAFAAgIjxngJwB0AgAAAA==.Souldrain:BAAALAAECggICgAAAA==.',Sp='Spiritnature:BAAALAAECgEIAQABLAAECgYIBgASAAAAAA==.',St='Starcallêr:BAAALAAECgEIAQAAAA==.Storcritsyo:BAAALAAECgUIBQAAAA==.Stormbringer:BAAALAAECgYIBwAAAA==.Stramifisken:BAAALAADCgQIBAAAAA==.Stronkmonk:BAAALAAFFAIIAgAAAA==.',Su='Sup:BAABLAAECoEaAAICAAcIlQgDmwA6AQACAAcIlQgDmwA6AQAAAA==.',Sw='Swollen:BAAALAADCggIIgABLAAECggIGAANAGciAA==.',Ta='Tambar:BAAALAADCggICAAAAA==.',Th='Thelavar:BAAALAAECgcIDAAAAA==.Thorinaun:BAAALAADCggICAAAAA==.Thoringaarn:BAAALAAECgYICwABLAAFFAQICQANALQKAA==.Thorinmuin:BAACLAAFFIEJAAINAAQItAolDQDxAAANAAQItAolDQDxAAAsAAQKgSEAAg0ACAiQHZ4YAJUCAA0ACAiQHZ4YAJUCAAAA.Thundersmash:BAAALAADCggICAABLAAECgEIAQASAAAAAQ==.',Tr='Trefloest:BAAALAADCggICQAAAA==.Trumpsbeach:BAAALAAECgUIBgAAAA==.',Tu='Turambar:BAABLAAECoEWAAIIAAcIbxcTbwDdAQAIAAcIbxcTbwDdAQAAAA==.',['Tø']='Tøysekopp:BAAALAADCggIDAAAAA==.',Va='Vampire:BAAALAAECgYICAAAAA==.Varlon:BAAALAADCggICAAAAA==.',Ve='Veinlash:BAABLAAECoEgAAIRAAgIzRiPDQA+AgARAAgIzRiPDQA+AgAAAA==.',Vi='Viletaint:BAAALAADCggICAAAAA==.Vincetti:BAAALAAECgEIAQAAAA==.',Vo='Voided:BAAALAAECgQICgAAAA==.',Wa='Wacky:BAAALAAECgEIAQAAAA==.Wakanda:BAAALAAECgYIDAAAAA==.Wanjín:BAAALAADCggIEAABLAAFFAMICwAYAAUYAA==.Warner:BAAALAAECgYIEgAAAA==.',Wi='Wilder:BAAALAAECgMIAwAAAA==.Willy:BAAALAADCggIBgAAAA==.Winkles:BAABLAAECoEiAAQUAAgIFhq8KgCBAgAUAAgIFhq8KgCBAgADAAQIEhVGVgDUAAAYAAEIYwrKHgAxAAAAAA==.Wizzle:BAAALAAECgIIAgABLAAFFAIIBQAMABkTAA==.',Xd='Xdalipala:BAAALAAECgYIDgAAAA==.',Ya='Yara:BAABLAAECoEeAAMZAAcIChq6EgAJAgAZAAcIChq6EgAJAgAVAAcIBA/8gQCLAQAAAA==.Yarn:BAABLAAECoEYAAIMAAgIYBn+OwBYAgAMAAgIYBn+OwBYAgAAAA==.',Yo='Yogsoggoth:BAAALAAECgEIAgAAAA==.You:BAAALAAECgYIBgABLAAFFAMICQABAE4SAA==.Yoy:BAAALAAECggICgAAAA==.',Za='Zanamaseluta:BAABLAAECoEXAAIaAAYI6hMtQwBtAQAaAAYI6hMtQwBtAQAAAA==.Zañithy:BAABLAAECoEXAAIVAAgIpBnkOABLAgAVAAgIpBnkOABLAgAAAA==.',Ze='Zexu:BAAALAAECgcIBwAAAA==.',Zo='Zoltar:BAAALAADCgMIAwAAAA==.Zoz:BAAALAAECggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end