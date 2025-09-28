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
 local lookup = {'Druid-Balance','Priest-Holy','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','Paladin-Retribution','Paladin-Holy','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Druid-Guardian','Unknown-Unknown','Mage-Frost','Monk-Brewmaster','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Warlock-Demonology','Priest-Shadow','DeathKnight-Unholy','Monk-Windwalker','Warlock-Destruction','Hunter-BeastMastery','Warrior-Protection','Druid-Feral','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Evoker-Augmentation','Priest-Discipline','DeathKnight-Blood','Warlock-Affliction',}; local provider = {region='EU',realm='Sinstralis',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aalec:BAABLAAECoEjAAIBAAcIDBNmPgCLAQABAAcIDBNmPgCLAQAAAA==.',Ab='Abzoom:BAABLAAECoEqAAICAAgIexcaKAAqAgACAAgIexcaKAAqAgAAAA==.',Ad='Adyboo:BAABLAAECoEhAAIDAAgIGCJ4DAAaAwADAAgIGCJ4DAAaAwAAAA==.',Ag='Agurak:BAAALAAECggIAQAAAA==.',Ah='Aheris:BAAALAADCgEIAQAAAA==.',Ai='Aifidol:BAAALAADCggICAAAAA==.',Ak='Akamarü:BAABLAAECoEcAAIEAAgIyxI9NADdAQAEAAgIyxI9NADdAQAAAA==.Akouma:BAAALAADCggIFQAAAA==.',Al='Alvilda:BAAALAAECgYIBgAAAA==.',Am='Amagaye:BAAALAAECgEIAQABLAAFFAIIBQAFAK8RAA==.Ammazone:BAAALAADCgcIBwAAAA==.',An='Annehidalgo:BAACLAAFFIEFAAIGAAII8g+0LgCeAAAGAAII8g+0LgCeAAAsAAQKgSgAAwYACAh4GLBDAEYCAAYACAh4GLBDAEYCAAcAAQhqBeVoACsAAAEsAAQKCAgmAAgAiBUA.Anèga:BAAALAADCgcIBwAAAA==.',Ap='Aphrodan:BAABLAAECoEXAAMIAAYIaw/hMwDtAAAJAAYICAslsQA3AQAIAAYIsg7hMwDtAAABLAAECggIGwAKAFwSAA==.',Ar='Arcoledemo:BAAALAAECgEIAQABLAAECgcIHAAHAG4cAA==.Arcâdïa:BAAALAAECgYIEgAAAA==.Arkide:BAABLAAECoEXAAILAAcIOx8tDwBPAgALAAcIOx8tDwBPAgAAAA==.Arklock:BAAALAADCgUIBQAAAA==.',As='Asuman:BAAALAADCggIDQAAAA==.',Az='Azarelis:BAAALAAECgEIAQAAAA==.Azrael:BAABLAAECoEXAAIBAAcIIxJZQQB+AQABAAcIIxJZQQB+AQAAAA==.',Ba='Bahaztek:BAACLAAFFIEGAAIKAAIIvyHzFQDHAAAKAAIIvyHzFQDHAAAsAAQKgSIAAgoACAikIaMUALMCAAoACAikIaMUALMCAAAA.Baladine:BAAALAAECgQIBQAAAA==.Balöo:BAAALAADCgEIAQAAAA==.Bartocck:BAAALAADCgcIDgAAAA==.Bastykk:BAACLAAFFIEJAAMMAAMICgtMEwDgAAAMAAMI3ApMEwDgAAANAAMIUAO0AgCnAAAsAAQKgTEAAw0ACAh8Iu4CAAEDAA0ACAjlIe4CAAEDAAwACAjpHowcALoCAAAA.',Be='Beback:BAABLAAECoEbAAIJAAcIdhCJegCjAQAJAAcIdhCJegCjAQAAAA==.Behe:BAABLAAECoEdAAIOAAcIuhzOIgA8AgAOAAcIuhzOIgA8AgAAAA==.Benlure:BAAALAAECggICgAAAA==.',Bh='Bhrenayn:BAACLAAFFIEGAAIPAAIIchzGAgCoAAAPAAIIchzGAgCoAAAsAAQKgTAAAg8ACAjIIa8CAAYDAA8ACAjIIa8CAAYDAAAA.',Bl='Blackbobo:BAAALAADCgYIBgABLAAFFAIIBQAFAK8RAA==.',Bo='Bonbon:BAAALAAECgcIEwAAAA==.',Bu='Buka:BAAALAAECgEIAQAAAA==.',['Bö']='Bömbers:BAAALAAECgcIBwAAAA==.',Ca='Caracas:BAAALAADCgIIAgAAAA==.',Ch='Chamanerie:BAAALAAECgUICQAAAA==.Chamoulox:BAAALAAECgYIDwAAAA==.Chamroks:BAAALAADCgcIBwAAAA==.Chamrök:BAAALAAECgcIEQAAAA==.Chamrøk:BAAALAAECgcIDgAAAA==.Chamïrokai:BAAALAADCgcIBwAAAA==.Chanteciel:BAABLAAECoEbAAICAAcIQh7fHwBdAgACAAcIQh7fHwBdAgAAAA==.Charlouff:BAAALAAECgYICwAAAA==.Chinchilla:BAAALAAECgQIBAABLAADCggIDgAQAAAAAA==.',Ci='Cimeriss:BAABLAAECoEbAAIGAAYImBtbcADZAQAGAAYImBtbcADZAQAAAA==.Ciran:BAAALAADCgMIAwAAAA==.Cirelle:BAABLAAECoEeAAIRAAgIcB0wDgCgAgARAAgIcB0wDgCgAgAAAA==.',Co='Colere:BAAALAADCggICAAAAA==.',Cr='Crakoukass:BAAALAAECgYICQABLAAECgYIEgAQAAAAAA==.Crakounette:BAAALAADCgMIAwABLAAECgYIEgAQAAAAAA==.Crankss:BAAALAAECggICAABLAAECggILgASAOASAA==.Crenks:BAAALAAECgIIAgABLAAECggILgASAOASAA==.Crenkss:BAABLAAECoEuAAISAAgI4BJjGgCgAQASAAgI4BJjGgCgAQAAAA==.',Ct='Ctoileheal:BAAALAADCgMIAwAAAA==.',Cy='Cyrann:BAAALAADCggIDgAAAA==.',['Cä']='Cämus:BAAALAAECgUICQAAAA==.',['Cï']='Cïdoü:BAAALAADCgEIAQAAAA==.',Da='Dakina:BAAALAAECgUIBgAAAA==.Darkilik:BAAALAAECgYIDQAAAA==.Darkshadöw:BAAALAAECgYIEgABLAAECgYIEgAQAAAAAA==.Darkzoom:BAAALAAECgYIDAAAAA==.',Di='Diki:BAAALAAECgcICwAAAA==.Dingodaz:BAAALAAECgEIAQAAAA==.Distress:BAABLAAECoEfAAMTAAgIiRt2DwAaAgATAAcIjBp2DwAaAgAUAAUIZxrSOABnAQAAAA==.Diviciacoss:BAABLAAECoEVAAIPAAcIZBMmDwCqAQAPAAcIZBMmDwCqAQAAAA==.',Dj='Djryllz:BAABLAAECoEuAAIRAAgIsxbXGwAWAgARAAgIsxbXGwAWAgAAAA==.Djynn:BAAALAAECgIIAgAAAA==.',Dr='Draconegro:BAAALAAECgcIBwABLAAECggIJgAIAIgVAA==.Drakaufeu:BAAALAAECgIIBgAAAA==.Drimzz:BAAALAAECgQIBAABLAAECggIGwAKAFwSAA==.',Du='Dumè:BAAALAADCggICwABLAAFFAMICAAVAJQZAA==.Durain:BAAALAADCgUIBQAAAA==.',El='Eladina:BAAALAAECgEIAQAAAA==.Elfeah:BAAALAADCgYIBgAAAA==.Elione:BAAALAADCggICgAAAA==.Eliyù:BAACLAAFFIENAAIRAAMIKB/CAwD4AAARAAMIKB/CAwD4AAAsAAQKgTEAAhEACAgeJXUCAGIDABEACAgeJXUCAGIDAAAA.Elwabi:BAABLAAECoEoAAIJAAgIARf1PwA6AgAJAAgIARf1PwA6AgAAAA==.Elyria:BAAALAADCgIIAgABLAAFFAMIAwAQAAAAAA==.',Fe='Feef:BAAALAAECgIIAgAAAA==.Felipecha:BAABLAAECoEeAAIWAAcIxBceGgAKAgAWAAcIxBceGgAKAgAAAA==.',Fo='Foxkill:BAAALAADCggICAAAAA==.',Fr='Fracafiak:BAAALAADCgMIAwAAAA==.Freetipoyo:BAAALAADCggICAABLAAECgYIEAAQAAAAAA==.Frostyze:BAABLAAECoEkAAIVAAcIyxCiZAC2AQAVAAcIyxCiZAC2AQAAAA==.',Ga='Gaarasand:BAAALAAECgMIAwAAAA==.Gargalalm:BAAALAAECgcIEQAAAA==.Garrathor:BAAALAAECgYIDAAAAA==.',Ge='Genval:BAAALAADCgUIBQAAAA==.',Gi='Gipsa:BAAALAAECgUICAABLAAFFAQIDgAFAEwiAA==.',Gl='Glubux:BAAALAAECgcICQAAAA==.',Go='Gosseyn:BAABLAAECoEUAAIMAAcIcgosbgBxAQAMAAcIcgosbgBxAQAAAA==.Goyamonk:BAAALAAECgYIDwAAAA==.Goyarogue:BAAALAAECgYIEQAAAA==.Goyasham:BAAALAADCgIIAgAAAA==.',Gr='Graha:BAAALAADCggIGAAAAA==.Grievz:BAAALAAECgcIDwAAAA==.Grâham:BAAALAAECgYIEQAAAA==.',Ha='Hakubo:BAAALAAECgIIAgAAAA==.Hanabi:BAAALAAECgYICgAAAA==.Harcolepal:BAABLAAECoEcAAIHAAcIbhxXFABFAgAHAAcIbhxXFABFAgAAAA==.',He='Healkekw:BAACLAAFFIEVAAILAAYIExT+AQD4AQALAAYIExT+AQD4AQAsAAQKgScAAgsACAhjH+0IALoCAAsACAhjH+0IALoCAAAA.Hemøragie:BAAALAADCgYIBgAAAA==.Hesteal:BAAALAADCgUIBQAAAA==.',Hu='Huulk:BAACLAAFFIEQAAMEAAYIXxiuBwAuAQAEAAQI7BOuBwAuAQABAAMIrBCnCgDvAAAsAAQKgS4AAwEACAhIJtsCAGoDAAEACAhIJtsCAGoDAAQABQjKD557AOYAAAAA.Huzako:BAAALAAFFAIIAwAAAA==.',['Hà']='Hàkntoo:BAAALAAECgEIAgAAAA==.',['Hä']='Hädam:BAABLAAECoEhAAIXAAYIKR52LQD9AQAXAAYIKR52LQD9AQAAAA==.',['Hå']='Håø:BAAALAAECggICgAAAA==.',['Hû']='Hûz:BAAALAAECgYIBgAAAA==.',Id='Idrana:BAABLAAECoEVAAIYAAgIaxYGDwBPAgAYAAgIaxYGDwBPAgAAAA==.',Il='Ilharend:BAABLAAECoEhAAIVAAcIkB20OQBFAgAVAAcIkB20OQBFAgAAAA==.Ilivïc:BAAALAAECgYICQAAAA==.',Im='Impa:BAAALAADCggICAAAAA==.',Ir='Irøh:BAABLAAECoEbAAMKAAYIPiLMMAArAgAKAAYIPiLMMAArAgADAAMI2BZrigC3AAAAAA==.',Is='Isyar:BAAALAAECggIBgAAAA==.',Iw='Iwantpickles:BAAALAADCggIDQAAAA==.',Ja='Jaggerjacka:BAAALAADCgYIBgAAAA==.',Je='Jeanray:BAACLAAFFIEIAAIVAAMIlBkPGQD7AAAVAAMIlBkPGQD7AAAsAAQKgRkAAxUACAhYILAkAKUCABUACAhYILAkAKUCABEAAQjyC819ADkAAAAA.',Jo='Jorkän:BAAALAADCgEIAQAAAA==.',Ju='Jupiterre:BAAALAADCgUIBQAAAA==.',Ka='Kagenou:BAAALAADCgcIDAAAAA==.Kahu:BAABLAAECoEeAAIKAAgI8wWMqgDuAAAKAAgI8wWMqgDuAAAAAA==.Kahulyne:BAAALAAECgMIBQAAAA==.Kame:BAAALAAECgIIAgAAAA==.Kasspard:BAABLAAECoEUAAIFAAYIQwqM2QAqAQAFAAYIQwqM2QAqAQAAAA==.',Ke='Keltia:BAAALAAECgIIAwAAAA==.',Kh='Khargun:BAAALAAECgYIEgAAAA==.Khutulun:BAAALAADCgcIDQAAAA==.',Kl='Kleø:BAAALAADCgcIBwAAAA==.',Kr='Krask:BAABLAAECoEbAAIKAAgIXBJrUgC+AQAKAAgIXBJrUgC+AQAAAA==.',['Kæ']='Kælys:BAAALAADCggIDgAAAA==.',La='Ladÿsharr:BAAALAADCggIBQAAAA==.Laurelei:BAAALAAECgYICgAAAA==.Lautrec:BAAALAAECgIIAgABLAAECgcIHQAVAGgcAA==.Lawen:BAACLAAFFIENAAILAAMItA/GCADWAAALAAMItA/GCADWAAAsAAQKgS4AAwsACAh/HDsOAFwCAAsACAh/HDsOAFwCABkABwj1GG4aAAQCAAAA.',Le='Legoret:BAACLAAFFIELAAIaAAMIyhmzFgACAQAaAAMIyhmzFgACAQAsAAQKgSkAAhoACAjbHmsaAMwCABoACAjbHmsaAMwCAAAA.Leroys:BAACLAAFFIELAAIFAAQIMhWYDgBHAQAFAAQIMhWYDgBHAQAsAAQKgSkAAgUACAg7JO4NACwDAAUACAg7JO4NACwDAAAA.',Li='Lindrya:BAAALAADCgcIBwABLAADCggIGQAQAAAAAA==.Lindä:BAAALAAECgYIEQAAAA==.Lirhia:BAAALAAECgcIEQAAAA==.Lirhïa:BAAALAADCgYIBgABLAAECgcIEQAQAAAAAA==.',Lo='Lostfire:BAABLAAECoEjAAIGAAcIQR6FPwBSAgAGAAcIQR6FPwBSAgAAAA==.Louky:BAACLAAFFIEIAAMbAAMIJBbiEwDeAAAbAAMIgRXiEwDeAAAOAAEIaw/RMAAvAAAsAAQKgS8AAxsACAg9IW8ZAM0CABsACAg9IW8ZAM0CAA4ABgjVEoZWAEQBAAAA.',['Lä']='Läwên:BAAALAADCggICAABLAAFFAMIDQALALQPAA==.',['Lé']='Léa:BAAALAAECgQIBwAAAA==.',['Lê']='Lêøne:BAAALAAECgYIDQAAAA==.',['Lî']='Lîma:BAABLAAECoEmAAIBAAgI1B5JFACgAgABAAgI1B5JFACgAgAAAA==.Lîsou:BAAALAAECgEIAQAAAA==.',['Lï']='Lïrhia:BAAALAADCgYIBgABLAAECgcIEQAQAAAAAA==.Lïrhïa:BAAALAAECgIIAgABLAAECgcIEQAQAAAAAA==.',Ma='Makiard:BAAALAADCggICAABLAAECgIIAgAQAAAAAA==.Makithar:BAAALAAECgIIAgAAAA==.Malan:BAABLAAECoEkAAMIAAgIpx9LBwDPAgAIAAgIYR9LBwDPAgAJAAcI+xdLZQDRAQAAAA==.Malendras:BAAALAADCgQIBAABLAAECggIJAAIAKcfAA==.Marionsilver:BAAALAAECggIEQAAAA==.Martys:BAAALAADCgcIBwAAAA==.',Me='Meuuhrtrier:BAAALAAECgUIBQAAAA==.',Mh='Mhad:BAAALAAECgYIDwAAAA==.',Mi='Miiti:BAABLAAECoEVAAIFAAgI0xiePwBYAgAFAAgI0xiePwBYAgAAAA==.Minxicat:BAAALAADCgcIBwAAAA==.Miralith:BAAALAAECgYIBwAAAA==.Mirâjäne:BAAALAADCgYIBgABLAAFFAMICAACANsTAA==.Misenbière:BAAALAADCggICAAAAA==.Miskina:BAAALAAECgYIEgAAAA==.',Mo='Moonn:BAAALAADCgIIAgAAAA==.Mortys:BAAALAADCgEIAQAAAA==.Morvvie:BAAALAAECgYIBAAAAA==.',Mu='Mukasan:BAAALAAECgYICAAAAA==.Murmandus:BAABLAAECoEiAAIcAAcIaRhyJQDVAQAcAAcIaRhyJQDVAQAAAA==.',My='Mylenfarmer:BAAALAADCgYIBgAAAA==.Myoren:BAAALAADCgUIBQAAAA==.Mythrandir:BAAALAADCgUIBQAAAA==.',Na='Nagalaw:BAAALAADCggICAABLAAECgcIFAAGAPQUAA==.Nalik:BAAALAADCgcICAAAAA==.Narzuol:BAAALAADCgEIAQAAAA==.Nashu:BAAALAADCggIDgAAAA==.Nathanos:BAAALAAECgcIDQAAAA==.',Ne='Nedraah:BAAALAADCgEIAQAAAA==.Nedraood:BAABLAAECoEiAAIPAAcIfSF0BQCPAgAPAAcIfSF0BQCPAgAAAA==.Neks:BAACLAAFFIEJAAIdAAMIfyBiAwAmAQAdAAMIfyBiAwAmAQAsAAQKgSwAAh0ACAhpJigCAEsDAB0ACAhpJigCAEsDAAAA.Nepthune:BAAALAADCgcICQAAAA==.Nexoxcho:BAAALAADCgcIDQAAAA==.',Ni='Nialeem:BAAALAAECgIIBAAAAA==.',No='Nokiswakss:BAAALAAECgYIBgAAAA==.Norajeuh:BAAALAAECgYIBgAAAA==.Novëa:BAAALAAECgUIBwAAAA==.',['Nã']='Nãthãdãn:BAAALAAECgEIAQAAAA==.',Om='Ombrecoeür:BAAALAADCggICQAAAA==.',Ox='Oxygene:BAACLAAFFIEIAAIJAAMIPxkbEQACAQAJAAMIPxkbEQACAQAsAAQKgTUAAgkACAjIJfwIAEsDAAkACAjIJfwIAEsDAAAA.Oxymoon:BAAALAAECgIIAgAAAA==.',Oz='Ozygrossburn:BAAALAAECgYIEAAAAA==.',Pa='Papylord:BAACLAAFFIELAAIGAAMIySUwCQBJAQAGAAMIySUwCQBJAQAsAAQKgR8AAgYACAiiJf8QACIDAAYACAiiJf8QACIDAAAA.Pastille:BAABLAAECoEdAAIKAAcImRIfbgB0AQAKAAcImRIfbgB0AQAAAA==.',Ph='Phèos:BAABLAAECoElAAIGAAgICiC3HADkAgAGAAgICiC3HADkAgAAAA==.Phéosc:BAAALAADCgcIBwAAAA==.',Py='Pyrokaid:BAACLAAFFIEOAAIUAAUInBfKAQDSAQAUAAUInBfKAQDSAQAsAAQKgTUAAhQACAgsJLQDADoDABQACAgsJLQDADoDAAAA.',['Pà']='Pàïro:BAAALAAECgIIAgAAAA==.',Qu='Quantykk:BAAALAADCgYIBgABLAAFFAMICQAMAAoLAA==.Quinzalin:BAAALAAECgUIBQAAAA==.',Ra='Radamänthis:BAAALAADCgMIAwAAAA==.Raetheldarin:BAAALAAECgUIBQAAAA==.Raimbette:BAAALAAECgQIBAABLAAFFAMIDQADALgSAA==.Raimbettelb:BAAALAAECgYIDwABLAAFFAMIDQADALgSAA==.Raimbo:BAACLAAFFIENAAIDAAMIuBLwEQDlAAADAAMIuBLwEQDlAAAsAAQKgSQAAwMACAh3ILkPAP8CAAMACAh3ILkPAP8CAAoAAQgdGcMCAUQAAAAA.Raimboitboit:BAAALAADCggICAABLAAFFAMIDQADALgSAA==.Randh:BAAALAAECgIIAwAAAA==.Rayleroux:BAAALAAECgQICgAAAA==.',Re='Ressdruide:BAAALAADCgcIBwABLAAECgcIHgAVAPQgAA==.Ressmage:BAABLAAECoEeAAIVAAcI9CB2LACAAgAVAAcI9CB2LACAAgAAAA==.Rezlock:BAAALAAECgcICQAAAA==.',Ri='Riadryn:BAAALAAECgYIEAABLAAECgUIBQAQAAAAAA==.',Ro='Roltux:BAAALAAECgUIBwAAAA==.Rosase:BAACLAAFFIERAAMUAAUIKxooBgAyAQAUAAMIXh0oBgAyAQATAAIIXxWTCwCgAAAsAAQKgTAAAxQACAitIgQIAPgCABQACAilIQQIAPgCABMABwgJHRcNAD0CAAAA.',Ry='Ryuû:BAAALAAECgUIBQAAAA==.',['Rø']='Røxxmane:BAABLAAECoEUAAMeAAcIeRQzPwAiAQAeAAUIhQ0zPwAiAQAfAAUIbAdnKQDNAAABLAAECggICAAQAAAAAA==.',Sa='Sadia:BAAALAAECgIIAgAAAA==.Sankhael:BAAALAADCggICAABLAAFFAcIHAAOAAYlAA==.Sarii:BAAALAADCgcIBwAAAA==.Sarkis:BAAALAAECgYIBwABLAAFFAIIAgAQAAAAAA==.Sarkän:BAABLAAECoEaAAIgAAcIFxs5FQAhAgAgAAcIFxs5FQAhAgAAAA==.Sasukedusud:BAABLAAECoEXAAIVAAgI8wcDdQCJAQAVAAgI8wcDdQCJAQAAAA==.Sathanas:BAAALAADCgcIEgAAAA==.Saucemagique:BAAALAADCgcIDAAAAA==.',Sd='Sdk:BAAALAAECgYICQAAAA==.',Sh='Shaapplight:BAAALAAECgYIBgAAAA==.Shapeless:BAAALAADCggIDgAAAA==.Shilliew:BAAALAAECggIEQAAAA==.Shinzô:BAAALAADCggICAAAAA==.Shöwgun:BAAALAAECgEIAQAAAA==.',Si='Sigourneypog:BAAALAAECgQIBAAAAA==.Sipapi:BAABLAAECoEWAAIRAAcIjQ/ULwCXAQARAAcIjQ/ULwCXAQAAAA==.Sisiclone:BAABLAAECoErAAQBAAgIWRmiHABRAgABAAgIWRmiHABRAgAPAAYIAwzIGgD8AAAEAAcIjxV9qgBZAAAAAA==.',Sk='Sken:BAAALAAECgYIDQAAAA==.Skipnøt:BAABLAAECoEgAAMeAAgIvB30EACZAgAeAAgIvB30EACZAgAhAAEIDhedFgA2AAABLAADCggIDgAQAAAAAA==.',Sl='Slaiyer:BAAALAAECgIIAgAAAA==.',So='Socär:BAAALAADCgIIAwAAAA==.Soobin:BAACLAAFFIEFAAIFAAIIrxHfRQCRAAAFAAIIrxHfRQCRAAAsAAQKgR4AAgUABgjCHTtpAO8BAAUABgjCHTtpAO8BAAAA.Soobinmonk:BAAALAADCgcIBwABLAAFFAIIBQAFAK8RAA==.Soyun:BAABLAAECoEfAAQZAAgIWCDYCQDdAgAZAAgIWCDYCQDdAgALAAgIeBNsFgDoAQASAAEI0xkmPQBNAAABLAAFFAMIAwAQAAAAAA==.',Sp='Spinningman:BAABLAAECoEcAAIZAAgIjyIBCAD8AgAZAAgIjyIBCAD8AgAAAA==.',St='Stendh:BAAALAADCggICAAAAA==.Stendha:BAAALAAECgQIAwAAAA==.Sthaune:BAAALAAECgEIAQAAAA==.',Su='Sucecubes:BAAALAADCgcIDAAAAA==.Sucre:BAABLAAECoEYAAILAAYIIA5ULAAJAQALAAYIIA5ULAAJAQAAAA==.Sucré:BAAALAAECggICgAAAA==.',['Sà']='Sàrkan:BAAALAAECgMIAwAAAA==.',['Sï']='Sïxxïs:BAAALAAECgIIAgAAAA==.',['Sö']='Söcar:BAAALAADCggIGQAAAA==.Söcär:BAAALAADCgcICwAAAA==.',['Sø']='Søfly:BAAALAAECggICAAAAA==.',Ta='Tanamort:BAAALAADCgUIBQAAAA==.Tanataus:BAAALAAECgIIAgAAAA==.Tanka:BAAALAAECgMIAwAAAA==.Taürüs:BAAALAADCgEIAQAAAA==.',Te='Teikashî:BAABLAAECoEUAAIEAAgIiAsDWABOAQAEAAgIiAsDWABOAQAAAA==.Temasham:BAAALAAECgYIBgABLAAECggICAAQAAAAAA==.',Th='Thorny:BAACLAAFFIEFAAIUAAIIcwvVFgCOAAAUAAIIcwvVFgCOAAAsAAQKgSoAAhQACAiQG7MSAHsCABQACAiQG7MSAHsCAAAA.Thôrgull:BAAALAAECgYIBgABLAAECgcIEgAQAAAAAA==.Thörgull:BAAALAAECgcIEgAAAA==.',Ti='Tiliate:BAABLAAECoEmAAMaAAcI1hcqQgACAgAaAAcI1hcqQgACAgAWAAUIpBJFRgAyAQAAAA==.',Tr='Trollveld:BAAALAAECgMIAwAAAA==.',Tu='Turbogroove:BAAALAADCgQIBAAAAA==.Tuuss:BAAALAADCgYIBgABLAAECgYICwAQAAAAAA==.',Tw='Twifafnyr:BAAALAAECggICAAAAA==.Twihades:BAAALAAECggIDQAAAA==.Twipluton:BAAALAAECggICAAAAA==.',['Tî']='Tîkidh:BAAALAAECgUIBQABLAAFFAMIBwAbADYdAA==.Tîtîbökä:BAAALAAECgQIBAAAAA==.',['Tö']='Tök:BAACLAAFFIEKAAICAAMIBBJDEADoAAACAAMIBBJDEADoAAAsAAQKgS0ABAIACAgBGPApACECAAIACAgBGPApACECABcABwiUClZJAG8BACIABAjkBFohAKIAAAAA.',Ul='Ulithi:BAAALAAECgcICAAAAA==.',Un='Unrahcsinep:BAAALAAECgYICwABLAAECgYIEAAQAAAAAA==.',Ut='Utøpiate:BAAALAADCgEIAQAAAA==.',Va='Vaelden:BAAALAAFFAMIAwAAAA==.Valaryn:BAAALAAECgYICgAAAA==.Valkiør:BAAALAAECgYIEwAAAA==.',Ve='Veldou:BAACLAAFFIEKAAIgAAMITBuoBAD7AAAgAAMITBuoBAD7AAAsAAQKgTIAAiAACAg1I2cEACkDACAACAg1I2cEACkDAAAA.Veldzor:BAAALAAECgMIAwAAAA==.Verhana:BAAALAADCgYIBwAAAA==.Vermithor:BAABLAAECoEeAAMhAAgIjg+7BwDZAQAhAAgIjg+7BwDZAQAeAAEIpwH/YAAWAAAAAA==.',Vi='Vishaan:BAAALAADCggIDAAAAA==.',Vo='Vortäxe:BAAALAAECgEIAQABLAAFFAMICAAVAJQZAA==.',Wa='Warveld:BAAALAAECgEIAQAAAA==.',Xe='Xendraka:BAAALAADCgYIBgAAAA==.',['Xé']='Xéryssa:BAAALAAECgIIAgAAAA==.',Yd='Ydrisse:BAABLAAECoEdAAIJAAYIghRojwB6AQAJAAYIghRojwB6AQAAAA==.',Yi='Yinmái:BAAALAAECggICAAAAA==.',Yo='Yoggsarocrow:BAACLAAFFIEPAAIXAAQIZQp0EADHAAAXAAQIZQp0EADHAAAsAAQKgRUAAhcACAjDHC4gAFMCABcACAjDHC4gAFMCAAAA.',Ys='Ysiia:BAAALAAECgYICwAAAA==.Ysyh:BAAALAAECggIEgAAAA==.',Yu='Yurraah:BAAALAADCgYIBgAAAA==.',Za='Zadarthas:BAAALAAECgIIAgAAAA==.Zadormu:BAAALAAECgQIBAAAAA==.Zarcaniste:BAAALAADCgQIBAAAAA==.Zarocrow:BAACLAAFFIEMAAIJAAMIYBnSEQD7AAAJAAMIYBnSEQD7AAAsAAQKgSwAAgkACAgQJXkMADUDAAkACAgQJXkMADUDAAAA.',Ze='Zeki:BAAALAAECggIEgAAAA==.Zerademo:BAAALAADCggICAAAAA==.Zerazera:BAABLAAECoEXAAIbAAcI/wT/xADyAAAbAAcI/wT/xADyAAAAAA==.',Zh='Zhëf:BAAALAADCgMIAwAAAA==.',Zi='Zinphéa:BAACLAAFFIEOAAMFAAMITCI9EgAeAQAFAAMITCI9EgAeAQAjAAIIFBcdCwCIAAAsAAQKgRkAAwUACAjNI5ksAJkCAAUACAg4IJksAJkCACMABgg0IOoYAJkBAAAA.Zizanie:BAAALAAECgUIBQAAAA==.',Zo='Zolda:BAAALAAECgYIDAABLAAFFAUIEQAUACsaAA==.Zoomback:BAABLAAECoEeAAIRAAgIDxi7FQBOAgARAAgIDxi7FQBOAgAAAA==.Zoomdemon:BAAALAAECgYIDAAAAA==.Zoomevo:BAABLAAECoElAAIfAAgIxRgZCgBpAgAfAAgIxRgZCgBpAgAAAA==.Zoomojo:BAABLAAECoEbAAIKAAgIsBLDUQDAAQAKAAgIsBLDUQDAAQAAAA==.Zoomonk:BAAALAAECgYIDAAAAA==.Zoomwar:BAAALAAECgYICwAAAA==.Zorica:BAABLAAECoEUAAIBAAcIpQb2VgAhAQABAAcIpQb2VgAhAQAAAA==.Zoumzoum:BAAALAAECgYICwAAAA==.Zoøm:BAAALAAECgYIDgAAAA==.Zoømette:BAABLAAECoEYAAIkAAgIixPMBwAtAgAkAAgIixPMBwAtAgAAAA==.',['Zë']='Zëf:BAAALAAECgEIAQAAAA==.',['Ân']='Ânéâ:BAACLAAFFIEIAAICAAMI2xNXDwDuAAACAAMI2xNXDwDuAAAsAAQKgSgAAwIACAhpIBQOAOQCAAIACAhpIBQOAOQCABcAAQi1DgiGAEAAAAAA.',['Äd']='Ädam:BAABLAAECoEZAAIkAAgIsBz7BgBBAgAkAAgIsBz7BgBBAgAAAA==.',['Îr']='Îragnir:BAAALAAECgYIEgAAAA==.Îragnîr:BAAALAADCggICAABLAAECgYIEgAQAAAAAA==.Îragnïr:BAAALAAECgYIDAAAAA==.Îrãgnïr:BAAALAADCggICAABLAAECgYIEgAQAAAAAA==.',['Ða']='Ðalararoth:BAAALAAECggICQAAAA==.',['Õl']='Õlæya:BAAALAADCgcICgAAAA==.',['Øg']='Øgami:BAAALAAECgYIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end