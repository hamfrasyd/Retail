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
 local lookup = {'Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Unknown-Unknown','Monk-Windwalker','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','Evoker-Devastation','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Priest-Shadow','Shaman-Restoration','Evoker-Preservation','Warrior-Fury','Mage-Fire','Rogue-Assassination','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Druid-Balance','Druid-Restoration','Shaman-Enhancement','Warrior-Protection','Rogue-Subtlety','Rogue-Outlaw','Hunter-Marksmanship','Evoker-Augmentation','Paladin-Holy','Hunter-Survival','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Arms','DeathKnight-Blood','Druid-Feral',}; local provider = {region='EU',realm="Twilight'sHammer",name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abracädabruh:BAAALAAECgYICQABLAAECggIJAABAMwfAA==.Abzinthe:BAABLAAECoEYAAMBAAgIzQg9dgCAAQABAAgIxAc9dgCAAQACAAUICQjnVADgAAAAAA==.',Ae='Aerisz:BAAALAAECgYIEgAAAA==.Aernath:BAAALAADCgMIAwABLAAECgcIHwADAPsWAA==.Aeshma:BAACLAAFFIEHAAIDAAMIfA/DEwDqAAADAAMIfA/DEwDqAAAsAAQKgSsAAgMACAj6H3ccANQCAAMACAj6H3ccANQCAAAA.',Ak='Akio:BAAALAAECgUIBQABLAAECgUICQAEAAAAAA==.Akla:BAAALAAECggIDAAAAA==.',Al='Alanbates:BAAALAADCgYICAAAAA==.Alepouditsos:BAABLAAECoEZAAIFAAcIZQ94JwCQAQAFAAcIZQ94JwCQAQAAAA==.Alira:BAACLAAFFIEFAAIDAAIIxRIQKgCYAAADAAIIxRIQKgCYAAAsAAQKgScAAgMACAjyIE8eAMoCAAMACAjyIE8eAMoCAAAA.Allukkard:BAABLAAECoEeAAIBAAgIYBLOUADuAQABAAgIYBLOUADuAQAAAA==.',An='Anaalikukka:BAAALAADCgEIAQABLAAECgcIIAAGAKMaAA==.Animalin:BAAALAAECgUIBwAAAA==.Antimidgets:BAABLAAECoEUAAMHAAcIVhdabgDZAQAHAAcIVhdabgDZAQAIAAYIJAu0PQDoAAAAAA==.Anywai:BAAALAAECgMIAwAAAA==.',Ao='Aoibhean:BAAALAAECgYIDQAAAA==.',Ar='Arcticblood:BAAALAAECggIEwAAAA==.Argentrenard:BAACLAAFFIEHAAIJAAMI8hGZCwDoAAAJAAMI8hGZCwDoAAAsAAQKgSEAAgkACAgPHdUOALACAAkACAgPHdUOALACAAAA.Argodk:BAAALAADCgUIBQABLAAECgQIBAAEAAAAAA==.Argø:BAAALAAECgQIBAAAAA==.Arjuna:BAABLAAECoEVAAIKAAcI9ROEQwDGAQAKAAcI9ROEQwDGAQAAAA==.',As='Ashghul:BAABLAAECoEmAAMLAAgIxhEFGgAKAgALAAgIxhEFGgAKAgAMAAMISwTjyABXAAAAAA==.Astraxius:BAAALAADCggIGAAAAA==.',At='Atréia:BAAALAADCgcIBwAAAA==.Atta:BAACLAAFFIEHAAINAAMI1Q8cBQC+AAANAAMI1Q8cBQC+AAAsAAQKgSUAAg0ACAiJH7QHAMECAA0ACAiJH7QHAMECAAAA.',Aw='Away:BAAALAAECgMIBAABLAAECgYIHQAOAB0eAA==.',Az='Azassin:BAAALAADCggICgAAAA==.Aznag:BAAALAAECggIDgAAAA==.Azwyr:BAAALAAECgcIEwABLAAECggIJAAPAEcdAA==.',Ba='Babayagka:BAAALAAECgUICgAAAA==.Baker:BAAALAAECgYIBgAAAA==.',Be='Benefit:BAAALAADCgYIGwAAAA==.',Bi='Biertap:BAAALAADCgcICQABLAAECgMIAwAEAAAAAA==.Bigmongo:BAAALAAECgcIEwAAAA==.Bikit:BAABLAAECoEYAAIKAAcI7ReDNgAAAgAKAAcI7ReDNgAAAgAAAA==.Billtong:BAAALAADCgcIDgAAAA==.',Bl='Blightfang:BAAALAAECgMIBAAAAA==.Blite:BAAALAADCggIGAABLAAECgcIGAAQAPEVAA==.Bläeze:BAABLAAECoEYAAMQAAcI8RXBEgDPAQAQAAcI8RXBEgDPAQAJAAMIBRAlSgC2AAAAAA==.',Bo='Boomeria:BAAALAAECgIIAgAAAA==.Boomslangx:BAABLAAECoEYAAIRAAgI/BIkQgD0AQARAAgI/BIkQgD0AQAAAA==.',Br='Bravefartsus:BAAALAADCgcIBwAAAA==.',Bu='Bullmurray:BAAALAAECgMIAwAAAA==.Bunný:BAAALAAECgQIBAAAAA==.Buster:BAAALAADCgUICQAAAA==.Buxesas:BAAALAADCggIGwAAAA==.',['Bä']='Bäbydoll:BAAALAADCgUIBQAAAA==.',['Bé']='Bérptank:BAAALAAECgYIDAAAAA==.',Ca='Carotcake:BAAALAAECgYIBgAAAA==.Casséé:BAAALAAECggICQAAAA==.',Ch='Chamelea:BAAALAAECgcIEAAAAA==.Chaocrusher:BAAALAAECgcIDwAAAA==.Chappié:BAABLAAECoEUAAILAAcIYRXEGwD+AQALAAcIYRXEGwD+AQAAAA==.Char:BAAALAADCggICAAAAA==.Chibby:BAAALAAECgYICgAAAA==.Chiiraa:BAAALAAECgMIAwAAAA==.',Co='Cobrajack:BAAALAADCggICAAAAA==.Cobrajaçk:BAAALAADCggICAAAAA==.Cobrajàck:BAACLAAFFIEHAAMBAAMInwS6IADDAAABAAMInwS6IADDAAACAAEIigHgGQAkAAAsAAQKgSQAAwIACAjeFlMvAJYBAAEABwhVFF9YANUBAAIABghmFlMvAJYBAAAA.Cobrájack:BAAALAADCggICAAAAA==.Commandoxx:BAABLAAECoEbAAMBAAgIkxmuLAB6AgABAAgIkxmuLAB6AgASAAEIJwMlIgATAAAAAA==.',Cr='Crumbs:BAAALAAECgYIBgAAAA==.Crystel:BAAALAAECgIIAgAAAA==.',['Cë']='Cëridweñ:BAABLAAECoEkAAIBAAgIzB+XJACiAgABAAgIzB+XJACiAgAAAA==.',['Có']='Cóbrajáck:BAAALAAECggIDgAAAA==.',Da='Daghunt:BAAALAADCgYICwAAAA==.Dagpala:BAAALAAECgYICwAAAA==.Dagshaman:BAAALAAECgYIDQAAAA==.Darkomen:BAAALAADCggIDAAAAA==.Darthmana:BAAALAAECgYICwABLAAFFAIIAwAEAAAAAA==.Datsnowsky:BAAALAADCggIIwAAAA==.Dazed:BAAALAAECgQIBwAAAA==.',De='Deadbyapril:BAABLAAECoEiAAITAAgI6BbuGAA7AgATAAgI6BbuGAA7AgAAAA==.Demoncrafter:BAAALAADCgcIBwAAAA==.Derzar:BAAALAAECgMIBAAAAA==.Destinelxx:BAACLAAFFIEFAAIHAAIIkBHCKACiAAAHAAIIkBHCKACiAAAsAAQKgRoAAgcACAiwIp4NADQDAAcACAiwIp4NADQDAAEsAAUUAwgJABQArhwA.Destinelz:BAACLAAFFIEJAAIUAAMIrhz+DQAQAQAUAAMIrhz+DQAQAQAsAAQKgTAAAhQACAhLJP8IADYDABQACAhLJP8IADYDAAAA.Dezminion:BAAALAADCgUIBQABLAAECggIHQAGAPUYAA==.',Di='Diamentor:BAAALAADCgcIDQAAAA==.Dimoneski:BAAALAAECgcIEAAAAA==.',Dk='Dkdon:BAAALAAECgcIEwAAAA==.',Do='Domiknee:BAABLAAECoEYAAMVAAcI7ByVBQBBAgAVAAYIOiGVBQBBAgAWAAcI5QqTWwBFAQAAAA==.Donhuntz:BAAALAAECgYIEgABLAAECgcIEwAEAAAAAA==.',Dr='Drakaras:BAABLAAECoEXAAIDAAgI2g+aXwDaAQADAAgI2g+aXwDaAQAAAA==.Drbackup:BAABLAAECoEpAAMXAAgI+iJ2CAAfAwAXAAgI+iJ2CAAfAwAYAAEIJA5SuwAoAAAAAA==.Druidxdruid:BAABLAAECoEnAAIXAAgI+BJIKgDuAQAXAAgI+BJIKgDuAQAAAA==.',Dt='Dtouch:BAABLAAECoEmAAMLAAgIgx9WBgDnAgALAAgIgx9WBgDnAgAMAAIIex0DrgCtAAABLAAFFAUIBQAKAPMiAA==.',Du='Dumitore:BAAALAAECgYIEgAAAA==.Duskbane:BAAALAAECgYIBgAAAA==.',['Dá']='Dárkcurè:BAAALAADCggIDwAAAA==.',Ea='Eatmybeasts:BAABLAAECoEUAAIUAAYI6wo7qwAhAQAUAAYI6wo7qwAhAQAAAA==.',Ed='Eddierip:BAAALAAECgEIAQAAAA==.',Ee='Eensaam:BAAALAADCggIHwAAAA==.',Ei='Eith:BAAALAAECggIDQABLAAECggIHgAHAM4VAA==.',El='Eldenil:BAABLAAECoEfAAIHAAgIUhYATQApAgAHAAgIUhYATQApAgAAAA==.Eldánar:BAAALAAECggIDwAAAA==.Ely:BAAALAADCggIIQAAAA==.',En='Endowed:BAAALAAECgYICwAAAA==.',Ep='Ephey:BAAALAADCggICQAAAA==.Epictv:BAAALAADCgcIBwAAAA==.',Er='Eriadorn:BAAALAADCgYICgAAAA==.Erineth:BAAALAAECgQIBAAAAA==.Erosdeath:BAAALAAECgUIBQAAAA==.',Es='Estarin:BAAALAAECgcICAAAAA==.',Ex='Extremus:BAAALAAECgYIBgAAAA==.',Ey='Eyvor:BAAALAAECgIIAgAAAA==.',Fa='Fabarizo:BAAALAAECgYIBgAAAA==.Fangborn:BAAALAADCgYIBgAAAA==.Fanghorn:BAABLAAECoEXAAIYAAcIfhmUKAASAgAYAAcIfhmUKAASAgAAAA==.Fanghörn:BAAALAADCgQIBAAAAA==.Fangshield:BAAALAAECgMIAwAAAA==.Fareastbeast:BAAALAAECgcIEwAAAA==.',Fe='Fearnaut:BAAALAAECgcIEwAAAA==.',Fi='Firelighter:BAAALAADCgcIFQAAAA==.',Fl='Flarro:BAABLAAECoEdAAIZAAgIfxByDAD9AQAZAAgIfxByDAD9AQAAAA==.Flurie:BAAALAAECgYIBgAAAA==.Flúffen:BAAALAAECgUICAAAAA==.',Fo='Foomanchoo:BAAALAADCggIEwAAAA==.Forastai:BAAALAAECgEIAQAAAA==.Forgotenmage:BAAALAADCgcIBwABLAAECgcIEAAEAAAAAA==.Forgottenpal:BAAALAAECgQIBQABLAAECgcIEAAEAAAAAA==.Foukousima:BAAALAADCgUIBQAAAA==.',Fr='Frippze:BAAALAADCgcIBwAAAA==.Frontright:BAAALAAECgIIAgABLAAECgYIHwARAPUYAA==.Frostmaagi:BAAALAADCgcIBwAAAA==.Frozex:BAABLAAECoEVAAIaAAYIVCI7GAA6AgAaAAYIVCI7GAA6AgAAAA==.Frukha:BAAALAAECgQIBAAAAA==.',['Fí']='Fíddler:BAAALAAECggICQABLAAFFAMIBQALAMUWAA==.',Ga='Garrinchá:BAAALAAECggICAAAAA==.',Ge='Gemmergertji:BAAALAADCgEIAQABLAAFFAMIBwAHAPQNAA==.Getclapped:BAAALAAECggICAAAAA==.',Gh='Ghostnyx:BAAALAAECgUICAAAAA==.',Gi='Girthquake:BAAALAAECgEIAQAAAA==.',Gk='Gkanopoulos:BAAALAAFFAIIAgAAAA==.Gkara:BAAALAADCggIDgABLAAECgUICgAEAAAAAA==.Gkatoua:BAAALAAECgYICwAAAA==.',Go='Gourmand:BAABLAAECoEVAAIPAAcIZyKOFwCfAgAPAAcIZyKOFwCfAgAAAA==.',Gr='Greengerasim:BAAALAAECgYIDgAAAA==.Grigory:BAAALAAECggIEgAAAA==.Grimmore:BAAALAADCgEIAQAAAA==.Grimmorp:BAAALAADCggIFQABLAAECgcIEAAEAAAAAA==.Grimwarry:BAAALAAECgcIEAAAAA==.Grippyhands:BAAALAAFFAEIAQAAAA==.Grokath:BAAALAAECgcICAAAAA==.Grolm:BAAALAAECgcIEgAAAA==.Grùll:BAABLAAECoEaAAIXAAcIWA+GQAB8AQAXAAcIWA+GQAB8AQAAAA==.',Gu='Gunsiej:BAAALAAECggICgAAAA==.Gurr:BAACLAAFFIEHAAIaAAMIBQP7DwCVAAAaAAMIBQP7DwCVAAAsAAQKgSEAAhoACAiKDnUxAIMBABoACAiKDnUxAIMBAAAA.Gutserk:BAAALAADCggIDwAAAA==.',Ha='Hadrian:BAAALAADCggIDgAAAA==.Hamada:BAAALAAECggIEAAAAA==.Hardnekkig:BAAALAAECgcIEAAAAA==.',He='Heartburn:BAAALAADCgcIFQAAAA==.Hecht:BAAALAADCgcIBgAAAA==.Helscrux:BAAALAAECgIIAgAAAA==.Herja:BAAALAAECgUICAABLAAECggIFwAIAHIVAA==.Hexology:BAAALAADCggICQABLAADCggICgAEAAAAAA==.',Ho='Hopper:BAAALAADCggIDgAAAA==.',Hz='Hzl:BAAALAAECgIIAQABLAAECgUICAAEAAAAAA==.',['Há']='Hármón:BAABLAAECoEdAAIGAAgI9RiRDQBRAgAGAAgI9RiRDQBRAgAAAA==.',Ia='Iambigfudge:BAAALAADCggICAAAAA==.',Il='Ilso:BAAALAAECgMIAwAAAA==.',In='Incredi:BAAALAAECgcIEwAAAA==.Incredible:BAAALAAECgYICQAAAA==.Induna:BAAALAAECgYIBgABLAAECgcIDgAEAAAAAA==.Inkimoon:BAAALAAECgcIDAAAAA==.Inkipinkie:BAAALAADCggIGAAAAA==.Inqidru:BAAALAADCgcIBwAAAA==.Intouch:BAAALAAECgYIDAAAAA==.',Io='Iounothing:BAAALAADCgcIEAAAAA==.',Ja='Jagare:BAAALAADCgMIBQAAAA==.Jahtimestari:BAABLAAECoEgAAIUAAcIvhDrewB/AQAUAAcIvhDrewB/AQAAAA==.Jaluka:BAAALAADCggIFQAAAA==.Jamiryo:BAAALAAECgYIBgAAAA==.Jayche:BAABLAAECoEbAAMbAAcIhhv3DQAtAgAbAAcIhhv3DQAtAgAcAAEIwhSkGgA3AAAAAA==.',Je='Jedisauce:BAAALAAECgYIDAABLAAECggIJAABAMwfAA==.',Jk='Jkat:BAAALAADCgYIBgAAAA==.',Jo='Joeysinns:BAAALAAECgYIAwAAAA==.Joeyslam:BAAALAADCgEIAQAAAA==.',Ju='Juhlaörkki:BAABLAAECoEZAAIUAAYI0wq2rAAdAQAUAAYI0wq2rAAdAQAAAA==.',['Jù']='Jùbei:BAAALAAECgYIDQAAAA==.',Ka='Kabooze:BAABLAAECoEWAAIBAAYIDRVqbgCWAQABAAYIDRVqbgCWAQAAAA==.Karvaperse:BAABLAAECoEgAAIGAAcIoxrsEgD+AQAGAAcIoxrsEgD+AQAAAA==.Kat:BAAALAADCgcIDQAAAA==.Katumus:BAABLAAECoEgAAIWAAcIWxuVJgAwAgAWAAcIWxuVJgAwAgAAAA==.',Ke='Kealthar:BAABLAAECoEbAAICAAgILRZ/GAAwAgACAAgILRZ/GAAwAgAAAA==.Kealtharr:BAAALAAECgIIAgAAAA==.Keiria:BAABLAAECoEcAAIcAAcIYxUfCADvAQAcAAcIYxUfCADvAQAAAA==.Kelrisa:BAAALAADCggIGAABLAAECggIHQAIACgfAA==.Kelsair:BAABLAAECoEdAAIIAAgIKB+hBwDfAgAIAAgIKB+hBwDfAgAAAA==.Kerauno:BAAALAADCggIEwAAAA==.Kesselrun:BAACLAAFFIEHAAMWAAMIdhyZCwAWAQAWAAMIdhyZCwAWAQAOAAII7Rk0FACdAAAsAAQKgSUAAw4ACAgVIFYPAOMCAA4ACAgVIFYPAOMCABYABQg2Ir8/ALEBAAAA.',Kh='Khakrovin:BAABLAAECoEoAAIdAAgIoRlBIABMAgAdAAgIoRlBIABMAgAAAA==.Khazhul:BAAALAADCgYIBwAAAA==.',Ko='Koalapoo:BAABLAAECoEXAAIIAAgIchUcHADaAQAIAAgIchUcHADaAQAAAA==.Kolwyntjie:BAAALAAECgIIAgAAAA==.',Kr='Kreiven:BAAALAAECgYIBwAAAA==.',Ku='Kunjani:BAAALAADCggIEAAAAA==.',Ky='Kyrmanolis:BAAALAAECgYIBgAAAA==.',['Kâ']='Kâthina:BAABLAAECoEfAAQWAAgIlByTGwB3AgAWAAcIxR2TGwB3AgAOAAcIkgqYTABcAQAVAAMIPiPoFAAmAQAAAA==.',['Kä']='Käido:BAAALAAECgYICAAAAA==.',La='Lashina:BAAALAADCgYIBgAAAA==.',Le='Leccy:BAAALAADCggICAAAAA==.Leimahdus:BAABLAAECoEUAAMKAAcIIRDlRgC5AQAKAAcIIRDlRgC5AQAPAAMIdg3s4wB5AAAAAA==.Letzou:BAAALAAECgYIDAAAAA==.',Li='Lichstorm:BAAALAAECgIIAgAAAA==.Lifereborn:BAAALAADCgEIAQAAAA==.Lilbeach:BAAALAAECgQIBAAAAA==.Lippey:BAAALAADCgcIBwABLAAECgMIAwAEAAAAAA==.',Ll='Llust:BAAALAAECgcIEAAAAA==.Llyrdwr:BAAALAADCggICAAAAA==.',Lo='Loaf:BAAALAAECgcIEQAAAA==.Lockin:BAAALAAECggICQAAAA==.Lorky:BAABLAAECoEUAAMJAAcIDhUkJwC+AQAJAAcIMRQkJwC+AQAeAAIIyRNGEgCGAAAAAA==.',Lu='Lucy:BAABLAAECoEYAAIPAAgI4hAWXwCXAQAPAAgI4hAWXwCXAQAAAA==.Ludoki:BAAALAADCgcIDQAAAA==.Luicifer:BAAALAAECgcIDAAAAA==.',['Lä']='Läka:BAABLAAECoEWAAIPAAYIdwervgDCAAAPAAYIdwervgDCAAAAAA==.Lämy:BAAALAADCggICAAAAA==.',['Lî']='Lîght:BAAALAAECgEIAQAAAA==.',['Lø']='Løwmana:BAAALAAFFAIIAwAAAA==.',Ma='Magerage:BAAALAAECgIIAgAAAA==.Maghilla:BAAALAADCgEIAQAAAA==.Magzey:BAAALAADCggICQABLAAECggIEAAEAAAAAA==.Magë:BAAALAADCgMIAwAAAA==.Mainrak:BAABLAAECoEZAAIOAAgIlBD+LgDwAQAOAAgIlBD+LgDwAQAAAA==.Malania:BAAALAADCggICAABLAAECgcIIAACACMeAA==.Malik:BAAALAADCggICAAAAA==.Malistra:BAAALAADCggIAQAAAA==.Mandalot:BAAALAAECgIIAgAAAA==.Marbleman:BAAALAADCgMIAwAAAA==.Margorie:BAAALAAECggIDQAAAA==.Margoth:BAAALAADCggIHAAAAA==.Matatzis:BAAALAADCggIFQAAAA==.Matsabplokos:BAAALAADCgcIBwAAAA==.',Mc='Mcblack:BAAALAADCggICAAAAA==.Mcdora:BAAALAADCgUIBQAAAA==.Mckahuna:BAAALAAECgUIBgAAAA==.Mcloki:BAAALAAECgYICwAAAA==.Mcmz:BAAALAADCgYIBgAAAA==.Mcnxa:BAAALAADCggIEAAAAA==.Mcpaw:BAAALAAECgcICQAAAA==.Mcvlad:BAAALAADCggICAAAAA==.Mcwild:BAAALAAECgMIBAAAAA==.Mcáres:BAAALAADCggICgAAAA==.',Me='Meatman:BAAALAAECgEIAQAAAA==.Memoria:BAAALAAECgYIDAABLAAECgYIEgAEAAAAAA==.Menoengrish:BAAALAAECgYICgAAAA==.Metaphorxi:BAAALAADCggICAABLAAECgcIHwAPAHgZAA==.',Mi='Minarasmán:BAABLAAECoEUAAIUAAcIGQ41pAAvAQAUAAcIGQ41pAAvAQAAAA==.Missmel:BAAALAAECgIIAgABLAAECggIFQAYANYaAA==.Mitzys:BAAALAADCgYICwAAAA==.',Mo='Mondano:BAAALAADCgQIBAAAAA==.Montano:BAAALAADCggIFgAAAA==.Morfini:BAAALAAECggIEAABLAAECggIIQAKALQcAA==.Morídín:BAACLAAFFIEFAAMLAAMIxRaJCQCuAAALAAII2B2JCQCuAAAMAAEIoAi1PQBRAAAsAAQKgSQAAwsACAhAJGcCAEcDAAsACAhAJGcCAEcDAAwAAgiCFeC6AIAAAAAA.',Mp='Mpampisoflou:BAAALAADCgYIBgAAAA==.',Mu='Mui:BAAALAADCggIFQAAAA==.Muray:BAAALAADCggICAAAAA==.',['Mä']='Mälliämpäri:BAAALAADCggICAAAAA==.',Na='Naomi:BAAALAADCgEIAQAAAA==.',Ne='Necrolena:BAAALAAECgIIAgAAAA==.Necronova:BAAALAAECgEIAQAAAA==.Necrotroll:BAABLAAECoEWAAIRAAcIkBqwNwAeAgARAAcIkBqwNwAeAgAAAA==.Necrowyrm:BAAALAADCggICAAAAA==.Nevadâ:BAAALAADCgcIBwAAAA==.',Ni='Nidalap:BAABLAAECoEYAAIIAAgIvBKKIAC1AQAIAAgIvBKKIAC1AQAAAA==.',No='Novingen:BAABLAAECoEYAAIXAAcIUQYrWwAIAQAXAAcIUQYrWwAIAQAAAA==.Nozomi:BAAALAAECgYICAAAAA==.',Nu='Nuolipersees:BAABLAAECoEWAAIdAAYI9hWzSwBqAQAdAAYI9hWzSwBqAQABLAAECgcIIAAGAKMaAA==.',Ny='Nyctia:BAAALAADCggICAAAAA==.Nyctophilia:BAABLAAECoEkAAIDAAgIrxYoRwAdAgADAAgIrxYoRwAdAgAAAA==.Nyxtharia:BAAALAADCggICAAAAA==.',['Nå']='Nåmi:BAAALAAECgMIBAAAAA==.Nåmii:BAAALAAECgcIDQAAAA==.',['Nø']='Nøtoriøusßig:BAAALAAECgQIBAABLAAFFAMIBwAQALwVAA==.Nøtøriøusßig:BAABLAAECoEWAAIfAAcI5Bs1FABDAgAfAAcI5Bs1FABDAgABLAAFFAMIBwAQALwVAA==.',Od='Odinsblade:BAABLAAECoEgAAMRAAgInxg9KgBeAgARAAgInxg9KgBeAgAaAAYIDglJUQDiAAAAAA==.Odinswrath:BAAALAADCggICAAAAA==.',Ok='Okehh:BAAALAAECgYIDAABLAAECggIJAABAMwfAA==.',Ol='Oldschool:BAAALAAECgYIDAAAAA==.',Or='Orctheguy:BAAALAAECgEIAQAAAA==.Orhura:BAABLAAECoEdAAMCAAgIJR+iDQCjAgACAAcI1SCiDQCjAgABAAIINgz5yABsAAAAAA==.Orphis:BAABLAAECoEhAAIUAAgIvBowMgBNAgAUAAgIvBowMgBNAgAAAA==.',Ou='Ouiski:BAACLAAFFIEGAAMMAAMI/wIHIAC1AAAMAAMI/wIHIAC1AAALAAIIcQIQFwB4AAAsAAQKgR4AAwsACAgVF4YmAL0BAAwABwiYEtlSAMEBAAsABgg9GoYmAL0BAAAA.',Pa='Padazun:BAABLAAECoEnAAIaAAgIQR1oEACKAgAaAAgIQR1oEACKAgAAAA==.Paladari:BAABLAAECoEdAAIHAAgIpgvofAC8AQAHAAgIpgvofAC8AQAAAA==.Paladinix:BAAALAAECgMIBQAAAA==.Palydoon:BAAALAAECgUIBgABLAAECgcIEwAEAAAAAA==.Papatza:BAAALAAECgYIAQAAAA==.Papper:BAAALAADCgcIBwAAAA==.Parawietje:BAABLAAECoEdAAITAAcIlCPwCgDTAgATAAcIlCPwCgDTAgAAAA==.Payn:BAAALAAECgQIBAAAAA==.',Pe='Peepeepower:BAAALAADCgEIAQAAAA==.Pellaagarion:BAAALAAECgQIBgAAAA==.Pepitobenito:BAAALAADCgQIBAABLAAECgUIBQAEAAAAAA==.Perdepis:BAAALAAECgMIAwAAAA==.Petula:BAECLAAFFIERAAIWAAUIqh3tAwDYAQAWAAUIqh3tAwDYAQAsAAQKgSoAAhYACAjgJJkFADcDABYACAjgJJkFADcDAAAA.',Ph='Phase:BAABLAAECoEgAAIHAAcI0RTwZwDnAQAHAAcI0RTwZwDnAQAAAA==.Phiinom:BAAALAAECggICAAAAA==.',Pi='Pitoor:BAAALAAECgYIBgAAAA==.Pixiel:BAAALAADCgYIDAAAAA==.Pizzaman:BAAALAADCgUIBQAAAA==.',Pl='Plushin:BAAALAAECgcIDwAAAA==.',Po='Pokeransikte:BAABLAAECoEZAAISAAgIdxaoAwBlAgASAAgIdxaoAwBlAgAAAA==.Porkchop:BAAALAADCggIFgAAAA==.',Pr='Probeard:BAAALAADCgcICQABLAAECgcIEAAEAAAAAA==.Prodrake:BAAALAADCgQIBAABLAAECgcIEAAEAAAAAA==.Profound:BAAALAAECgcIEAAAAA==.Proktosauros:BAABLAAECoEYAAMWAAcIpw7uTQB3AQAWAAcIpw7uTQB3AQAVAAEIswdQNgAnAAAAAA==.Prowakidx:BAABLAAECoEeAAIHAAgISB4sIQDKAgAHAAgISB4sIQDKAgAAAA==.Prîestah:BAAALAAECgQIBgABLAAECggIJAABAMwfAA==.',Ps='Psykovsky:BAABLAAECoEXAAIdAAYICBFdVQBGAQAdAAYICBFdVQBGAQAAAA==.',Pu='Puffdaßigmac:BAACLAAFFIEHAAIQAAMIvBXhBgADAQAQAAMIvBXhBgADAQAsAAQKgRsAAhAACAhaGNsLAEQCABAACAhaGNsLAEQCAAAA.Pungendin:BAAALAADCgIIAgAAAA==.',Pw='Pwndps:BAAALAAECgEIAQAAAA==.Pwnpwnhaxx:BAACLAAFFIEFAAIaAAII4BwBDQCsAAAaAAII4BwBDQCsAAAsAAQKgSkAAhoACAhRIuIGABEDABoACAhRIuIGABEDAAAA.',Py='Pyörre:BAABLAAECoEgAAIPAAcI9BgEQgDrAQAPAAcI9BgEQgDrAQAAAA==.',Qo='Qoy:BAAALAAECgYICgABLAAECgcIDgAEAAAAAA==.',Qu='Queltrin:BAAALAAECgMIAwABLAAFFAIIBQAFACoYAA==.',Qx='Qxen:BAAALAADCggICgABLAAECggIHQAGAPUYAA==.',Ra='Rael:BAAALAAECgYIDAABLAAFFAIIBgAgAKYeAA==.Rahgar:BAAALAAECggIBgAAAA==.Raphaell:BAABLAAECoEeAAIYAAgIpxvJFgB9AgAYAAgIpxvJFgB9AgAAAA==.',Re='Recinder:BAAALAAECgUIAgAAAA==.Redgajol:BAACLAAFFIEFAAIHAAII4xr0HwCsAAAHAAII4xr0HwCsAAAsAAQKgSgAAgcACAijIlUSABgDAAcACAijIlUSABgDAAAA.Relthorn:BAAALAADCggIHAAAAA==.Requiem:BAABLAAECoEVAAMHAAgIsRFNmwCDAQAHAAcIfQtNmwCDAQAIAAUIjxV5NwARAQAAAA==.Ret:BAAALAAECggICAAAAA==.',Ro='Rochirielon:BAAALAADCggIDwAAAA==.Rofbul:BAAALAAECgYICwAAAA==.Rolynne:BAAALAAECgUIBQAAAA==.Rowena:BAAALAADCggICwAAAA==.',Ru='Rubíks:BAAALAADCgUIBQAAAA==.',Sa='Saiaman:BAABLAAECoEgAAMIAAcImB+8CwCPAgAIAAcImB+8CwCPAgAfAAYIZBPbNwBLAQAAAA==.Saintdamien:BAABLAAECoEUAAICAAYIBg59PQBRAQACAAYIBg59PQBRAQAAAA==.Saioubardos:BAAALAAECgYIEAAAAA==.Sallucion:BAAALAAECgEIAQABLAAECgMIAwAEAAAAAA==.Salmena:BAABLAAECoEdAAIdAAgIFhbRKgAHAgAdAAgIFhbRKgAHAgAAAA==.Sammo:BAABLAAECoEaAAIMAAcIghqeOAAmAgAMAAcIghqeOAAmAgAAAA==.Samwise:BAAALAAECggIBgAAAA==.',Sc='Scaly:BAAALAAECgMIBgAAAA==.Schoeps:BAACLAAFFIEHAAIWAAMIWB2bCwAWAQAWAAMIWB2bCwAWAQAsAAQKgSUAAhYACAhVIoQHACEDABYACAhVIoQHACEDAAAA.',Se='Selledh:BAAALAADCgcIBwAAAA==.Sellentys:BAAALAAECgQIBgAAAA==.Selma:BAAALAADCggIEAABLAAECgcIIAACACMeAA==.Seppe:BAAALAADCgYIBgABLAAECgMIBgAEAAAAAA==.',Sg='Sgourakoss:BAAALAAECgYIDQAAAA==.',Sh='Shaded:BAAALAAECgYIDQAAAA==.Shai:BAAALAAECgYIBwAAAA==.Shaidh:BAABLAAECoEVAAIDAAgIZBkxPQA/AgADAAgIZBkxPQA/AgAAAA==.Shaidk:BAAALAADCggICAAAAA==.Shao:BAAALAADCggICAAAAA==.Sheandran:BAACLAAFFIENAAIdAAUIRBZFBQCTAQAdAAUIRBZFBQCTAQAsAAQKgSIAAh0ACAjzIsMLAPkCAB0ACAjzIsMLAPkCAAAA.Sheathledger:BAABLAAECoEfAAIRAAYI9RjzUADAAQARAAYI9RjzUADAAQAAAA==.Shielder:BAAALAAECgUIDQAAAA==.Shion:BAAALAAECgUICQAAAA==.Shockolate:BAAALAADCggIEwAAAA==.Shoepsadaisy:BAAALAAECgYIBgABLAAFFAMIBwAWAFgdAA==.Shöman:BAABLAAECoEdAAMKAAgI0AzbVgB/AQAKAAcIgwrbVgB/AQAPAAEI8wYGEwEgAAAAAA==.',Si='Siiggee:BAAALAAECgcIDgAAAA==.Sindarela:BAAALAADCgcIGQAAAA==.Sinnaigo:BAAALAAECgYIBQAAAA==.Sintti:BAABLAAECoEgAAMhAAcIKBp3ZwDvAQAhAAcI3RZ3ZwDvAQAiAAQIIBhjLQA7AQAAAA==.',Sk='Skapie:BAAALAADCgYIBwAAAA==.',Sl='Sleepymop:BAAALAAECgcICgAAAA==.Slingy:BAAALAADCggIDAAAAA==.',Sm='Smartazz:BAAALAAECgcIEAAAAA==.',So='Sootglow:BAAALAADCggIIwAAAA==.Sotomayor:BAAALAADCgMIAwAAAA==.',Sp='Spartanwar:BAAALAAECgYIDwAAAA==.Spicyshots:BAAALAAECgYIBgABLAAECggIJAABAMwfAA==.Spinmeister:BAAALAAECgYIDQABLAAFFAEIAQAEAAAAAA==.Spirakoss:BAAALAAECgYIDwAAAA==.',St='Stavrogin:BAAALAAECgcIEAAAAA==.Stavrou:BAAALAAECgIIAgAAAA==.Stenbumling:BAAALAADCgYIBgAAAA==.Stikgarzuk:BAAALAAECgYIBgABLAAFFAUIDQAHAIUUAA==.Stormangels:BAAALAADCggICAABLAAECggIBgAEAAAAAA==.Stárscream:BAAALAADCgYICQAAAA==.',Su='Suga:BAAALAADCggIFQAAAA==.Sukcmydisc:BAABLAAECoEdAAIOAAYIHR7NKQAOAgAOAAYIHR7NKQAOAgAAAA==.Sulrette:BAAALAADCgYIEQAAAA==.Sunblade:BAAALAADCggICAABLAAECggIHgAHAM4VAA==.Sunfather:BAAALAADCgcICQAAAA==.Sunnyside:BAAALAADCgcICQAAAA==.Sushì:BAAALAADCggICAAAAA==.',Sy='Syerea:BAAALAADCgYIBgAAAA==.Sylider:BAAALAAECggIEAAAAA==.',Ta='Taerondris:BAAALAADCggIFQAAAA==.Taikamatto:BAABLAAECoEgAAICAAcIjRfMHQADAgACAAcIjRfMHQADAgAAAA==.',Te='Telari:BAAALAADCggICwAAAA==.Terrish:BAAALAADCggICAAAAA==.',Th='Thedirtman:BAAALAAECgQIAgAAAA==.Thetanknaut:BAAALAAECgcIDAAAAA==.Thiresios:BAAALAADCgMIAwAAAA==.Thosi:BAAALAADCggICAAAAA==.Thristen:BAACLAAFFIEGAAIiAAMIWBMoBQAEAQAiAAMIWBMoBQAEAQAsAAQKgR0AAiIACAgKG14KAJcCACIACAgKG14KAJcCAAAA.Thwra:BAAALAADCggIEAAAAA==.Thynox:BAAALAAECgIIAgAAAA==.',To='Toehater:BAAALAAECggIDwAAAA==.Toké:BAABLAAECoEaAAMjAAcInB5FCABJAgAjAAcI4hxFCABJAgARAAcIKhtkLgBJAgAAAA==.Tonight:BAAALAADCgEIAQABLAAECggIIQAKALQcAA==.Topnepneko:BAAALAADCgYIBgAAAA==.',Tr='Trath:BAACLAAFFIEGAAIYAAMICwliEQDAAAAYAAMICwliEQDAAAAsAAQKgRsAAhgACAjUEQA5AMIBABgACAjUEQA5AMIBAAAA.Trikadin:BAACLAAFFIEHAAIHAAMIHhTGDgD4AAAHAAMIHhTGDgD4AAAsAAQKgSUAAgcACAgLI4UPACgDAAcACAgLI4UPACgDAAAA.Trikaevo:BAAALAADCggIDgABLAAFFAMIBwAHAB4UAA==.Trishes:BAAALAADCggICAAAAA==.Triska:BAAALAADCgQIBAAAAA==.',Ts='Tsigaros:BAAALAADCgcIBwAAAA==.',Tz='Tzunic:BAAALAAECgYIBgAAAA==.',Uf='Ufer:BAAALAAECgYIEgAAAA==.',Un='Undeadtronic:BAAALAAECgMIAwAAAA==.Unforgoten:BAAALAAECgYICAAAAA==.',Ur='Urcaguarcy:BAAALAAECggIEAAAAA==.',Va='Valorie:BAAALAAECgYICgAAAA==.Vaude:BAAALAAECgIIAgAAAA==.',Ve='Veilord:BAAALAAECgYICwAAAA==.Vesipuhveli:BAABLAAECoEaAAIDAAcI9BxzNwBUAgADAAcI9BxzNwBUAgAAAA==.Vexis:BAAALAADCgEIAQAAAA==.',Vi='Vivian:BAAALAAECgMIAwAAAA==.',Vo='Vordian:BAAALAADCgUIBQAAAA==.Vosjaw:BAAALAADCggICAAAAA==.',Vr='Vrigka:BAAALAADCggICAAAAA==.',Vu='Vulpie:BAAALAADCgQICAAAAA==.',Vy='Vykon:BAAALAADCgcIBwAAAA==.Vykonia:BAAALAADCggIEAAAAA==.',['Vï']='Vï:BAABLAAECoEYAAINAAcICg4CJwBAAQANAAcICg4CJwBAAQAAAA==.',Wa='Warkingil:BAAALAADCgcIBwAAAA==.Warkingmo:BAAALAADCggICAAAAA==.Warriortje:BAAALAAECggIDAAAAA==.',Wi='Willgates:BAAALAAECgYICQABLAAECggIJAABAMwfAA==.',Xa='Xaks:BAAALAAECgYIBgAAAA==.Xaphan:BAAALAADCggICQAAAA==.',Xb='Xbig:BAAALAAECgIIAgAAAA==.',Xe='Xelzur:BAAALAAECgEIAQAAAA==.Xenize:BAAALAAECgYIBgAAAA==.Xervaz:BAABLAAECoEeAAIhAAgIBSOVFQACAwAhAAgIBSOVFQACAwAAAA==.',Xg='Xgemeaux:BAABLAAECoEfAAMCAAYIwQwlQwA5AQABAAYITgtHiQBMAQACAAYIRwwlQwA5AQAAAA==.',Ya='Yappalena:BAAALAADCggIDQAAAA==.Yarphead:BAAALAADCgcICQAAAA==.Yaseravoke:BAEBLAAECoEcAAIQAAgIWBkgCgBkAgAQAAgIWBkgCgBkAgABLAAFFAUIEQAWAKodAA==.Yawanna:BAABLAAECoEeAAIHAAgIzhVRTQAoAgAHAAgIzhVRTQAoAgAAAA==.',Yo='Yomasepoes:BAAALAAECgcIEAAAAA==.Yorkii:BAAALAADCgUICAAAAA==.',Za='Zaazu:BAABLAAECoEiAAIKAAYIfySxJgBUAgAKAAYIfySxJgBUAgAAAA==.Zabimaru:BAAALAAECgYIDQAAAA==.Zackeriah:BAACLAAFFIEHAAIHAAMI9A0rEQDkAAAHAAMI9A0rEQDkAAAsAAQKgSIAAgcACAgZHgcuAJACAAcACAgZHgcuAJACAAAA.Zaltadin:BAAALAAECgYIBgAAAA==.Zapp:BAABLAAECoEXAAIkAAcICR/FCwBnAgAkAAcICR/FCwBnAgAAAA==.',Zo='Zorar:BAABLAAECoEXAAIaAAcIBxTbLgCSAQAaAAcIBxTbLgCSAQAAAA==.',Zz='Zz:BAAALAAECggIDAAAAA==.',['Ùb']='Ùberskyllou:BAAALAADCgcIBwAAAA==.',['Ýl']='Ýloar:BAABLAAECoEZAAIlAAcIzR38CwBpAgAlAAcIzR38CwBpAgAAAA==.',['ßi']='ßigmâc:BAAALAADCgcIBwABLAAFFAMIBwAQALwVAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end