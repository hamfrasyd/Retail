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
 local lookup = {'Shaman-Enhancement','DemonHunter-Havoc','Paladin-Protection','Unknown-Unknown','Monk-Brewmaster','Mage-Frost','Hunter-BeastMastery','Rogue-Assassination','Mage-Arcane','Hunter-Survival','Warlock-Destruction','Warrior-Fury','Druid-Restoration','Priest-Shadow','Priest-Holy','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Frost','Warlock-Demonology','Warrior-Protection','Druid-Feral','DeathKnight-Blood','Mage-Fire','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Paladin-Holy','Priest-Discipline','Druid-Balance','Rogue-Subtlety','Rogue-Outlaw','Monk-Windwalker',}; local provider = {region='EU',realm="Vek'nilash",name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abysmöl:BAAALAAFFAIIBAAAAA==.Abyssos:BAAALAADCgcICgAAAA==.',Ac='Acidar:BAAALAAECgEIAQABLAAECggIIAABAP8bAA==.',Ae='Aelune:BAAALAADCggICAAAAA==.Aertheas:BAABLAAECoEaAAICAAgIxh/kHADRAgACAAgIxh/kHADRAgAAAA==.Aerîs:BAAALAAECgYICwAAAA==.',Ag='Agitar:BAAALAADCggICAAAAA==.',Ah='Aholymoly:BAABLAAECoEdAAIDAAgI3yHpBgDtAgADAAgI3yHpBgDtAgABLAAFFAIIBAAEAAAAAA==.',Ai='Aiman:BAABLAAECoEoAAIFAAgIzxwGCgCWAgAFAAgIzxwGCgCWAgAAAA==.Aionir:BAABLAAECoEmAAIGAAgIOCXvAgBXAwAGAAgIOCXvAgBXAwAAAA==.',Al='Alsyana:BAABLAAECoEXAAIHAAgIchiHPAAmAgAHAAgIchiHPAAmAgAAAA==.',An='Anathemaa:BAAALAAECgYIBgAAAA==.',Ar='Arabélla:BAAALAAECgEIAQAAAA==.Aradenox:BAAALAAFFAIIAgAAAA==.Arckie:BAAALAAECgYICAABLAAECggIFwAIAF0eAA==.Arismo:BAAALAADCgcIBwAAAA==.Arrowplume:BAAALAAECgEIAQAAAA==.',As='Ashie:BAACLAAFFIEIAAIJAAMIlRKNGwDnAAAJAAMIlRKNGwDnAAAsAAQKgSUAAgkACAhZI90OABgDAAkACAhZI90OABgDAAAA.Astrida:BAAALAAECgYIDAAAAA==.',Au='Audran:BAABLAAECoEgAAMKAAgI1x6/BAB4AgAKAAgIVx2/BAB4AgAHAAgIBRrMOgAsAgAAAA==.',Av='Avlí:BAAALAAECgcIBwAAAA==.',Az='Azrael:BAAALAAECgYIBgAAAA==.',Ba='Bamvandam:BAAALAADCggIDAAAAA==.',Be='Beamzz:BAAALAADCggICAABLAAECggIFwAIAF0eAA==.Bedste:BAAALAADCggICAAAAA==.Belindo:BAAALAADCgUIBQAAAA==.Bennyboo:BAABLAAECoEeAAIKAAYIbyAUBgBGAgAKAAYIbyAUBgBGAgAAAA==.',Bi='Bigboned:BAAALAADCggICwABLAAECggIFwAIAF0eAA==.',Bl='Blashai:BAAALAADCgYIBgAAAA==.Blippi:BAACLAAFFIEKAAILAAMI2A5IGgDoAAALAAMI2A5IGgDoAAAsAAQKgSEAAgsACAjSGLQpAG4CAAsACAjSGLQpAG4CAAAA.',Bo='Boriz:BAAALAAECggICAAAAA==.',Br='Brakkar:BAAALAAECgYIDgAAAA==.Brewplum:BAAALAAECggIDQAAAA==.',Bu='Buns:BAAALAADCgIIAgAAAA==.Bushi:BAAALAAECgIIAwAAAA==.',Ca='Cairneblood:BAABLAAECoEcAAIMAAgIzSAUFgDiAgAMAAgIzSAUFgDiAgAAAA==.Catesi:BAABLAAECoEgAAINAAgImRpWGQBsAgANAAgImRpWGQBsAgAAAA==.',Ce='Cesiana:BAABLAAECoEUAAMOAAcIlAzPQgCIAQAOAAcIlAzPQgCIAQAPAAcI/gsgVgBYAQAAAA==.',Ch='Chandria:BAAALAADCggIEAAAAA==.Charlamagne:BAAALAAECgIIBgAAAA==.Chíe:BAAALAAECgcIEQAAAA==.',Ci='Ciezar:BAABLAAECoEgAAIMAAgI8g7ISgDVAQAMAAgI8g7ISgDVAQAAAA==.Ciirith:BAACLAAFFIEKAAMQAAUInw80BgCEAQAQAAUInw80BgCEAQARAAIIVQXjEACBAAAsAAQKgSgABBAACAg9IOAIAPwCABAACAg9IOAIAPwCABEABwjGEk4UALkBABIAAQg0HuoTAFsAAAAA.Cindia:BAACLAAFFIEKAAIPAAMIUw1hEQDeAAAPAAMIUw1hEQDeAAAsAAQKgSgAAg8ACAhqGx0WAJ0CAA8ACAhqGx0WAJ0CAAAA.Cirithi:BAACLAAFFIEFAAIPAAMIlgoFEwDTAAAPAAMIlgoFEwDTAAAsAAQKgSMAAg8ACAixGaMjAEICAA8ACAixGaMjAEICAAEsAAUUBQgKABAAnw8A.',Cl='Clausiker:BAAALAAECgYIBgABLAAFFAIIAgAEAAAAAA==.',Cr='Criuss:BAAALAAECggIDgAAAA==.Crushpack:BAAALAADCggIFgAAAA==.',Cs='Cspr:BAAALAADCggIGQAAAA==.',Da='Dakadek:BAAALAADCggIBgAAAA==.Dakamar:BAAALAAECgcIEQAAAA==.Daneli:BAAALAAECgIIAQAAAA==.Danogoza:BAABLAAECoEYAAIRAAcIjROsFACzAQARAAcIjROsFACzAQAAAA==.Darkor:BAAALAADCggICQAAAA==.Dartha:BAAALAAECgMIAwABLAAECggIJwAMAAkaAA==.',De='Deadbaldman:BAACLAAFFIEIAAITAAMIDxjSFAAAAQATAAMIDxjSFAAAAQAsAAQKgSMAAhMACAjSILEWAP0CABMACAjSILEWAP0CAAEsAAQKCAgjAAwAIyIA.Deadbullz:BAAALAADCgYIBwAAAA==.Deadtroll:BAABLAAECoETAAITAAcIWhmWYAD/AQATAAcIWhmWYAD/AQAAAA==.Decrepit:BAAALAADCggICwAAAA==.Dekart:BAAALAADCgcIBwAAAA==.Denma:BAABLAAECoEoAAIUAAgI8x1wBwDUAgAUAAgI8x1wBwDUAgAAAA==.',Di='Diesiraee:BAABLAAECoEhAAMVAAgIQBgCGQAzAgAVAAgIQBgCGQAzAgAMAAYIlA0HegBHAQAAAA==.',Dr='Dragovich:BAAALAAECgYIBgAAAA==.Drakereaper:BAAALAADCgIIAgAAAA==.Drakor:BAABLAAECoEcAAIQAAgIuhfXFQBeAgAQAAgIuhfXFQBeAgAAAA==.Drangkor:BAAALAAECgMIAwAAAA==.Drevo:BAAALAADCgUIBQAAAA==.Druamina:BAABLAAECoEeAAIWAAcI0hwGDgBFAgAWAAcI0hwGDgBFAgABLAAECggIIAAKANceAA==.Drukhan:BAACLAAFFIETAAMUAAUIkh6BAwDcAAALAAUIKhnqCgC+AQAUAAIInyWBAwDcAAAsAAQKgTMAAwsACAjSJTgFAF8DAAsACAhTJTgFAF8DABQABwgDJIAKAKMCAAAA.Drustme:BAAALAAECgMIBQAAAA==.',Du='Durzoblínt:BAAALAAECgQIBgAAAA==.',Ea='Earthandfire:BAAALAAECgEIAQAAAA==.',El='Elanderaw:BAAALAAECgUIBQABLAAFFAUIEgAQAD8cAA==.Elanderawrxd:BAAALAAECgYICAABLAAFFAUIEgAQAD8cAA==.Elementary:BAAALAAECgcICwAAAA==.Elen:BAAALAAECgYIBgAAAA==.Ellorei:BAAALAADCgcIBwAAAA==.Elviada:BAAALAAECggIDwAAAA==.',Er='Ert:BAAALAADCggIBAAAAA==.',Es='Eshonai:BAABLAAECoEaAAIXAAgILyDzCACkAgAXAAgILyDzCACkAgAAAA==.Esselie:BAAALAAECgYIEwAAAA==.',Et='Etzhrael:BAAALAADCgUIAwABLAAECgYIBgAEAAAAAA==.',Ev='Evilsoczek:BAAALAAFFAIIAgAAAA==.Evoky:BAAALAAFFAEIAQAAAA==.',Ex='Exade:BAABLAAFFIEFAAIJAAMIpw3gHgDPAAAJAAMIpw3gHgDPAAABLAAFFAcIHQALAKUYAA==.',Ey='Eyljire:BAABLAAECoEgAAICAAcI0BdWVAD3AQACAAcI0BdWVAD3AQAAAA==.',Fa='Faekitty:BAAALAAECgUIBgAAAA==.Faelarin:BAACLAAFFIEIAAIJAAIISxT2MACaAAAJAAIISxT2MACaAAAsAAQKgSgAAwkACAjnIG8UAPcCAAkACAjnIG8UAPcCABgAAgjEDTEcAD0AAAAA.Farmd:BAABLAAECoEjAAIQAAgIQCQdAwBTAwAQAAgIQCQdAwBTAwAAAA==.Fave:BAAALAAECgQIBAABLAAECgcIFAAOAJQMAA==.',Fe='Feldemon:BAAALAADCgIIAgAAAA==.',Fi='Fistrurum:BAAALAAECgYICQAAAA==.',Fl='Flurry:BAAALAAECggIEAABLAAFFAIIBgAHAKoUAA==.',Fr='Frostfiend:BAAALAADCgcIGwAAAA==.',Fu='Furthermore:BAAALAAECgYIBgAAAA==.Fusr:BAAALAADCgcIBwAAAA==.',Ga='Galdokter:BAAALAADCgQIBwAAAA==.',Gi='Gingerclaw:BAACLAAFFIEJAAINAAMIBhNmDADdAAANAAMIBhNmDADdAAAsAAQKgRoAAw0ACAg/GygkACkCAA0ACAg/GygkACkCABYAAQjsIBs7AE0AAAAA.',Go='Gonkar:BAAALAADCgcIAwAAAA==.Goracysoczek:BAACLAAFFIEIAAIJAAIIgB3OJACxAAAJAAIIgB3OJACxAAAsAAQKgRMAAgkABghMIcE/ACkCAAkABghMIcE/ACkCAAAA.',Gr='Graardor:BAABLAAECoEjAAIMAAgIIyIGFADwAgAMAAgIIyIGFADwAgAAAA==.Grarzer:BAABLAAECoEnAAIMAAgICRpQKgBeAgAMAAgICRpQKgBeAgAAAA==.Greksio:BAAALAAECgYIBgAAAA==.Grendel:BAAALAAECgIIAgAAAA==.Groktar:BAAALAAECgIIBQAAAA==.Grommdhne:BAAALAAECgYIBwAAAA==.Gruodis:BAAALAADCgYICAABLAAECgYIEwAEAAAAAA==.',Ha='Haldír:BAABLAAECoEgAAIZAAgIVhpfGwBxAgAZAAgIVhpfGwBxAgAAAA==.',He='Heal:BAAALAADCggIBwABLAAECggICAAEAAAAAA==.Healla:BAAALAADCgIIAgAAAA==.Hellsminion:BAAALAADCgYIBgAAAA==.',Hu='Huitaisin:BAAALAAECggICAABLAAFFAMIBwASAAgLAA==.',['Hé']='Héliòs:BAAALAADCgcICAAAAA==.',Il='Ilvyra:BAAALAAECgUIBQABLAAFFAIICAAJAEsUAA==.',Im='Imightdie:BAAALAAECgYIBgAAAA==.',In='Initia:BAABLAAECoEpAAIGAAgIvhmBEAB/AgAGAAgIvhmBEAB/AgAAAA==.',Io='Ioth:BAABLAAECoEbAAMaAAgInRcWQwDoAQAaAAcIyhcWQwDoAQAbAAQINArQhQDBAAAAAA==.',Ip='Ipalock:BAAALAAECgUIDAAAAA==.',Ir='Irate:BAAALAADCgcIBwAAAA==.',Iv='Ivym:BAABLAAECoErAAMJAAgImxngLwBrAgAJAAgImxngLwBrAgAGAAEIOg6wfgAzAAAAAA==.',Ja='Jakasi:BAAALAAECgUIBQABLAAECggIHAAMAM0gAA==.Jalira:BAAALAADCgYIBgAAAA==.',Ji='Jig:BAAALAADCgIIAgAAAA==.',Jo='Joelbit:BAAALAAECgUIBQABLAAFFAUIEgAQAD8cAA==.',Ju='Jubjub:BAAALAAECggIEAAAAA==.Juice:BAACLAAFFIEIAAIJAAIIgBx+KQCkAAAJAAIIgBx+KQCkAAAsAAQKgRcAAgkACAi/IVAPABYDAAkACAi/IVAPABYDAAAA.',Ka='Kaleca:BAABLAAECoEYAAMRAAYIPh33DwD8AQARAAYIPh33DwD8AQAQAAYI9RCRNgBTAQAAAA==.Kalii:BAAALAAECggIBQABLAAECggIDgAEAAAAAA==.Kamahl:BAAALAADCggICAAAAA==.',Ke='Kerppa:BAAALAADCgcIEwAAAA==.Keznu:BAAALAAECgIIAgAAAA==.',Kh='Khirgan:BAAALAADCggICAAAAA==.',Ki='Kieszonka:BAAALAADCgQIBAAAAA==.Killinghunt:BAAALAAECgYIEQAAAA==.Kivivi:BAAALAAECgIIAgABLAAECggIKQAPAI4PAA==.Kiwiwi:BAABLAAECoEpAAMPAAgIjg+DPQC7AQAPAAgIjg+DPQC7AQAOAAcI6Q8NQgCMAQAAAA==.',Ko='Kosimazaki:BAABLAAECoEXAAMcAAgIkw8MegDBAQAcAAgIww4MegDBAQADAAYIeAgSQADYAAAAAA==.',Kr='Krriss:BAAALAAECgcIDQABLAAECggIHQAdAK0jAA==.Kràpuul:BAAALAADCgUICgAAAA==.',Kw='Kwaa:BAAALAAECgYIBgAAAA==.',Ky='Kyberflame:BAAALAADCggIFwAAAA==.Kyoko:BAAALAAECgcIDAAAAA==.',La='Lawli:BAAALAAECgYICwAAAA==.',Le='Leggy:BAAALAAECgYIBwABLAAECggIFwAIAF0eAA==.Lenima:BAAALAADCggIDgAAAA==.',Li='Liarerine:BAAALAAECgYIBgAAAA==.Lid:BAAALAAECgQICAAAAA==.Litalman:BAAALAAECgcIBwAAAA==.',Lo='Lodowysoczek:BAACLAAFFIENAAIJAAUIdRLrCwCxAQAJAAUIdRLrCwCxAQAsAAQKgS0AAgkACAhFJdMGAE4DAAkACAhFJdMGAE4DAAAA.',Lu='Luckybanjer:BAAALAAECggIAQAAAA==.',['Lí']='Lín:BAAALAADCggIBgAAAA==.',Ma='Maevra:BAAALAAECgcIBwAAAA==.Mageyoulook:BAAALAADCgcIBwAAAA==.Magnac:BAAALAADCgcIEQAAAA==.',Me='Meambemexd:BAAALAAECggICgABLAAFFAUIEgAQAD8cAA==.Mebladey:BAAALAAECgEIAQABLAAECgIIAgAEAAAAAA==.Medjig:BAABLAAECoErAAMPAAgItRZaKQAiAgAPAAgItRZaKQAiAgAeAAEI5g6/MgAvAAAAAA==.Melthao:BAAALAADCgcIBwABLAAECggIIwAfAO4jAA==.Mercc:BAABLAAECoEbAAIcAAgIniBFFwD+AgAcAAgIniBFFwD+AgAAAA==.',Mi='Milkers:BAAALAAECgMIAwABLAAECggIIwAMACMiAA==.',Mo='Monachós:BAAALAAECgIIAgAAAA==.Moomiin:BAABLAAECoEeAAIcAAgIeSCWKwCaAgAcAAgIeSCWKwCaAgAAAA==.Moredots:BAAALAADCggICAAAAA==.',Na='Nada:BAAALAADCggIEQAAAA==.Narko:BAAALAAECgcIBwAAAA==.',Ne='Nekas:BAAALAADCgIIAgAAAA==.Nerdié:BAAALAAECgEIAQAAAA==.',Ni='Nikkola:BAABLAAECoEuAAIMAAgIwSF5EwD0AgAMAAgIwSF5EwD0AgAAAA==.Nish:BAAALAAECgUIBQAAAA==.',No='Nobletrasza:BAAALAAECgMIAwAAAA==.Noveria:BAAALAAECgcIDQAAAA==.',Nu='Nutella:BAAALAADCgYICgABLAAFFAQICwABADQKAA==.',Ol='Olgin:BAAALAAECgIIAgAAAA==.',On='Ono:BAAALAAECgYICwAAAA==.',Or='Orukk:BAABLAAECoEaAAIHAAcIaB5dPwAcAgAHAAcIaB5dPwAcAgAAAA==.',Ou='Outlul:BAABLAAECoEXAAQIAAgIXR7VFwBGAgAIAAcIER/VFwBGAgAgAAIIihKJNwCEAAAhAAEIkiKCFwBlAAAAAA==.',Ow='Owocek:BAABLAAECoEdAAIdAAgIrSMOAgA3AwAdAAgIrSMOAgA3AwAAAA==.',Pa='Pangtong:BAAALAAECgEIAQAAAA==.',Pe='Peakie:BAAALAADCgYIBgABLAAECggIDgAEAAAAAA==.Petalas:BAAALAAECgMIAgAAAA==.Petrichor:BAAALAADCggIFwAAAA==.',Pi='Pished:BAAALAADCggICAABLAAECgYICgAEAAAAAA==.',Pl='Plia:BAAALAAECgYICQAAAA==.',Po='Polonikoo:BAAALAAECgYIDwAAAA==.Polstre:BAAALAADCgYICAAAAA==.',Ps='Psychoboo:BAABLAAECoEcAAIHAAgIDAyXdwCJAQAHAAgIDAyXdwCJAQAAAA==.',Pu='Pulsár:BAABLAAECoEYAAMPAAcIBxlKVgBYAQAPAAUIXxZKVgBYAQAOAAYIZAqIVQA0AQAAAA==.Punish:BAABLAAECoEYAAICAAcIFgwNkwBtAQACAAcIFgwNkwBtAQAAAA==.',Qu='Quillenar:BAAALAADCgMIAwABLAAECggIEQAEAAAAAA==.',Ra='Ransu:BAAALAAECgEIAQAAAA==.',Re='Reguus:BAAALAADCggIBgAAAA==.Reuven:BAAALAAECgYIDAABLAAFFAUIEwAHAG4YAA==.',Rh='Rhododendron:BAABLAAECoEWAAMQAAcIVwbyQAAOAQAQAAcIVwbyQAAOAQASAAMIBQRyEwBnAAAAAA==.',Ri='Riker:BAAALAADCgcICAAAAA==.',Ru='Russart:BAAALAADCggIBAAAAA==.Rustbucket:BAABLAAECoEbAAMHAAgIggyddwCJAQAHAAgIAgyddwCJAQAZAAUIWAg/fQC5AAAAAA==.',Ry='Rysiu:BAAALAADCggICAAAAA==.',Rz='Rza:BAAALAAECgYICgAAAA==.',Sa='Sanys:BAAALAAECgYIBgAAAA==.',Se='Serryn:BAAALAAECgUIBQABLAAECgcIGAARAI0TAA==.',Sh='Shadowbleak:BAAALAADCgcIEAAAAA==.Shanoita:BAAALAADCggICAAAAA==.Sharlaai:BAAALAADCggICAABLAAECggIIwAfAO4jAA==.Shasseem:BAAALAAECggIEQAAAA==.',Si='Siphaman:BAABLAAECoEnAAIaAAgIMyUvBQAuAwAaAAgIMyUvBQAuAwAAAA==.Sipharrior:BAABLAAECoEUAAIMAAcIahyVMQA5AgAMAAcIahyVMQA5AgABLAAECggIJwAaADMlAA==.Siwangmu:BAAALAAECgMIBQAAAA==.',Sn='Snuffit:BAAALAADCgIIAgAAAA==.',Sp='Splashdaddy:BAAALAAECgIIAgAAAA==.',St='Starcaller:BAAALAADCgUIBQAAAA==.',Su='Suffelí:BAAALAAECgUIBQAAAA==.Superhick:BAAALAAECgEIAQAAAA==.Suz:BAAALAADCgcIBwAAAA==.',Sw='Swarmag:BAAALAADCgQIBAAAAA==.Swiftknigth:BAAALAADCggIDgAAAA==.Swiftyholy:BAAALAADCgYICQAAAA==.Swiftypala:BAAALAADCgIIAgAAAA==.Swiftyshaman:BAAALAADCgcIBwAAAA==.Swyfegosa:BAAALAADCggICAAAAA==.',Sy='Sythini:BAAALAADCggIFQAAAA==.',Ta='Talar:BAAALAAECgEIAQAAAA==.Tamerleyn:BAAALAADCgYIBgAAAA==.Tanzar:BAABLAAECoEgAAQBAAgI/xsUCgAvAgABAAcIlxwUCgAvAgAbAAgIKhRpMQAYAgAaAAMIwRnOrgDgAAAAAA==.Tazdingu:BAAALAADCggICwAAAA==.',Te='Terrix:BAAALAADCggIBgABLAAECgYIBgAEAAAAAA==.',Th='Theazzman:BAAALAADCgYIBgAAAA==.Thorlim:BAAALAAECgYIBgABLAAECggIIwAMACMiAA==.',Ti='Tiarath:BAAALAAECgYIDwABLAAECgcIGAARAI0TAA==.Titanhold:BAABLAAECoEaAAIMAAcIshQYRwDiAQAMAAcIshQYRwDiAQAAAA==.',To='Toko:BAAALAADCggICAAAAA==.Torik:BAACLAAFFIEJAAIJAAMI8BHIGgDsAAAJAAMI8BHIGgDsAAAsAAQKgS4AAgkACAiPH9sbAM8CAAkACAiPH9sbAM8CAAAA.',Ty='Typo:BAAALAADCgcIBwAAAA==.',Ug='Uglygnomerix:BAAALAAECgYIBgAAAA==.',Ur='Ursul:BAAALAAECgQIBAAAAA==.',Va='Varkarra:BAAALAADCgYIBgAAAA==.Vatkap:BAABLAAECoElAAMcAAgI5SG0FQAHAwAcAAgI5SG0FQAHAwADAAcIhAu+LwBDAQAAAA==.',Ve='Vexáhlia:BAAALAADCgMIAwAAAA==.',Vo='Voidhammer:BAAALAADCggIEQAAAA==.Voidhunt:BAAALAAECggIEwAAAA==.',Vp='Vpizdu:BAAALAAECgQIBgAAAA==.',Wa='Waak:BAAALAAECgYIBgAAAA==.Waksu:BAAALAADCggICQAAAA==.Warlockz:BAAALAAECggIEQAAAA==.',We='Wedi:BAAALAAECgYIBgAAAA==.Weirdié:BAAALAADCgcIEAABLAADCgcIEwAEAAAAAA==.',Wi='Wioth:BAAALAADCgQICAAAAA==.',Wo='Wokandroll:BAAALAAECgMIBAAAAA==.',Ys='Ysekkira:BAAALAAECgYICwABLAAECgcIGAARAI0TAA==.',Yv='Yvendria:BAAALAAECgUIBQAAAA==.',Za='Zajeczyca:BAAALAAECgUICwAAAA==.Zapper:BAAALAADCgQIBAAAAA==.Zarmin:BAABLAAECoEVAAIcAAgIihQoWQAJAgAcAAgIihQoWQAJAgAAAA==.',Ze='Zenadin:BAAALAAECgYIBwAAAA==.Zenaku:BAAALAAECgcIEwAAAA==.Zeno:BAABLAAECoEeAAIiAAgILBRWGgACAgAiAAgILBRWGgACAgAAAA==.',Zi='Zizzro:BAAALAADCggIFgAAAA==.',Zu='Zulteraa:BAAALAADCggICAABLAAECgYIGAARAD4dAA==.',Zy='Zylarx:BAAALAAECgMIBAAAAA==.',['Öl']='Ölkagge:BAAALAAECgYIBgABLAAFFAUIEgAQAD8cAA==.',['ßo']='ßoid:BAAALAAECgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end