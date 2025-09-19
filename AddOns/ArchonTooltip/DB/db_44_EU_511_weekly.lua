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
 local lookup = {'Unknown-Unknown','DeathKnight-Blood',}; local provider = {region='EU',realm='Tyrande',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abso:BAAALAAECgYICwAAAA==.',Ac='Acascarlo:BAAALAADCgcIBwAAAA==.',Ad='Adelram:BAAALAADCgEIAQAAAA==.',Ae='Aerlín:BAAALAAECgUIBwAAAA==.',Af='Africana:BAAALAADCgcIDAAAAA==.',Ah='Ahdala:BAAALAAECgMIAwAAAA==.',Ai='Aidil:BAAALAADCgcIBwAAAA==.',Aj='Ajnp:BAAALAAECgIIBAAAAA==.',Ak='Akhubadain:BAAALAAECgIIAgAAAA==.Akodiña:BAAALAAECgMIBAAAAA==.',Al='Alesra:BAAALAADCgcIBwAAAA==.Alesta:BAAALAADCggIDgAAAA==.Algar:BAAALAADCgYIBgAAAA==.Almôsteasy:BAAALAAECgYICgAAAA==.Altamiro:BAAALAADCgEIAQAAAA==.Altema:BAAALAADCgcICAAAAA==.Alëxandêr:BAAALAADCgcICQAAAA==.',Am='Amaräntha:BAAALAAECgMIBQAAAA==.',An='Anapinmes:BAAALAAECgMIBgAAAA==.Ankhansunamu:BAAALAAECgYICQAAAA==.Ansset:BAAALAAECgUIBQAAAA==.Anuel:BAAALAADCggIDwAAAA==.',Ar='Arachy:BAAALAAECgYICAAAAA==.Aradoiel:BAAALAADCggICAAAAA==.Aristhos:BAAALAADCgcIDwAAAA==.Ariâlyn:BAAALAADCgQIBAAAAA==.Arkey:BAAALAAECggIDQAAAA==.Armadura:BAAALAADCggICAAAAA==.Artak:BAAALAAECgEIAQAAAA==.Arterotitan:BAAALAAECgMIBQAAAA==.Artiel:BAAALAAECgMIBQAAAA==.',As='Asptronomo:BAAALAADCggICQAAAA==.Assborr:BAAALAAECgEIAQAAAA==.Assokâ:BAAALAADCggICQAAAA==.Astrodruid:BAAALAAECgMIAwAAAA==.Astárte:BAAALAADCgMIAwAAAA==.',At='Athom:BAAALAADCgQIBgAAAA==.Athätriel:BAAALAAECgYICQAAAA==.Atriumvestæ:BAAALAADCgQIBQAAAA==.',Au='Aureoh:BAAALAADCgYIBgAAAA==.Ausentë:BAAALAADCgQIBAAAAA==.',Ax='Axelkrog:BAAALAADCgMIAwAAAA==.',Ay='Ayashi:BAAALAAECgIIAgAAAA==.Ayperos:BAAALAAECgIIBAAAAA==.',Az='Azug:BAAALAADCgcIDAAAAA==.',['Aè']='Aèto:BAAALAAECgYICwAAAA==.',Ba='Bakayaro:BAAALAAECgcIEQAAAA==.Baligos:BAAALAADCgYIBgAAAA==.Baltorus:BAAALAAECgMIBgAAAA==.Basön:BAAALAADCgIIAgAAAA==.',Be='Beastcall:BAAALAADCggIDwAAAA==.Beaxela:BAAALAAECgYICQAAAA==.Beduja:BAAALAAECgYICgAAAA==.Belialuin:BAAALAADCgUIBQAAAA==.Bemezor:BAAALAAECgEIAQAAAA==.Berrny:BAAALAAECgQIBgAAAA==.Berïel:BAAALAADCgcIDgAAAA==.Besfala:BAAALAAECgMIBgAAAA==.',Bl='Blackpapet:BAAALAADCgcIFAAAAA==.Blancosinmas:BAAALAAECgIIAgAAAA==.Blied:BAAALAADCgcIDQAAAA==.Blindkeeper:BAAALAAECgQIBAAAAA==.',Bo='Boar:BAAALAAECgEIAQAAAA==.Bombonbum:BAAALAAECgYIBgAAAA==.Borjacosta:BAAALAAECgYICwAAAA==.',Br='Brighteye:BAAALAADCgYIBgAAAA==.Briseïda:BAAALAADCgYICAAAAA==.',Bu='Bubblechick:BAAALAAECgMIBgAAAA==.',By='Byakkur:BAAALAAECggICQAAAA==.',['Bâ']='Bâmbelvi:BAAALAAECgIIAgAAAA==.',['Bø']='Børder:BAAALAADCggICAAAAA==.',Ca='Caerroil:BAAALAAECgYICgAAAA==.Calîoppe:BAAALAADCgMIAwAAAA==.Canach:BAAALAAECgYIDAAAAA==.Cassioplea:BAAALAADCgUIBQAAAA==.Caylena:BAAALAADCgcICwAAAA==.Cazatotos:BAAALAADCggICAAAAA==.',Ch='Chaminita:BAAALAADCgYIBgAAAA==.Chartrass:BAAALAAECgMIBgAAAA==.Cherrim:BAAALAAECgcIDAAAAA==.Chets:BAAALAADCgcIBwAAAA==.',Ci='Cires:BAAALAAECgYICQAAAA==.',Cl='Clarck:BAAALAADCgcIDAAAAA==.',Co='Colthan:BAAALAAECgEIAQAAAA==.Colágenö:BAAALAADCgIIAwAAAA==.Comeniños:BAAALAADCgYIBgAAAA==.',Cr='Crookedarrow:BAAALAADCggIEAAAAA==.',Da='Dablas:BAAALAAECgMIBAAAAA==.Daenay:BAAALAAECgEIAQAAAA==.Dajjal:BAAALAAECgIIAwAAAA==.Damaso:BAAALAADCgQIAgAAAA==.Darkand:BAAALAAECgEIAQAAAA==.Darkarius:BAAALAADCggIFgAAAA==.Darkatlantia:BAAALAAECgEIAQAAAA==.Darksouw:BAAALAADCgUIBQAAAA==.Dawa:BAAALAAECgEIAQAAAA==.Dayl:BAAALAADCgMIAwAAAA==.Daígotsu:BAAALAAECgEIAQAAAA==.',De='Demonjake:BAAALAADCgMIAwAAAA==.Dertipincha:BAAALAAECgYICgAAAA==.Despair:BAAALAAECggIAgAAAA==.',Di='Diegospicy:BAAALAAECgQIBwAAAA==.Diosamadre:BAAALAADCgUIBQAAAA==.',Dr='Draeliâ:BAAALAADCgIIAgAAAA==.Dranza:BAAALAAECgYIBQAAAA==.Drinchita:BAAALAAECgEIAQAAAA==.',Du='Durexcontrol:BAAALAADCgIIAgAAAA==.',Dy='Dyrinia:BAAALAAECgYICAAAAA==.',['Dá']='Dávíd:BAAALAADCggIDwAAAA==.',['Dä']='Därckness:BAAALAADCgQIBAAAAA==.',Ea='Eaglesrojod:BAAALAAECgYICgAAAA==.',Ec='Ecotone:BAAALAAECgYICgAAAA==.',Ei='Eiliv:BAAALAAECgMIAwAAAA==.',El='Elfric:BAAALAAECgYIDAAAAA==.Elrond:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.Eltiopepe:BAAALAAECgMIBwAAAA==.Elumami:BAAALAAECgYIBQAAAA==.Elunelle:BAAALAADCgcIDAAAAA==.',Em='Empireon:BAAALAADCggIFgAAAA==.',Er='Eriba:BAAALAADCgMIAwAAAA==.Ermadeon:BAAALAADCgcIDgAAAA==.Erodillen:BAAALAAECgYICgAAAA==.',Es='Escorbutopia:BAAALAADCgcIDQAAAA==.Esfolada:BAAALAADCgcIBwAAAA==.Estoimuiover:BAAALAAECgMIAwAAAA==.',['Eí']='Eír:BAAALAAECgYIDAAAAA==.',Fa='Farald:BAAALAADCgcIAwABLAAECgYIDAABAAAAAA==.',Fe='Feel:BAAALAADCgcIDAAAAA==.Feltos:BAAALAADCgYICAAAAA==.',Fi='Fiifii:BAAALAADCgIIAgAAAA==.',Fo='Formas:BAAALAAECgYICgAAAA==.',Fr='Fror:BAAALAAECgEIAQAAAA==.',Fu='Fumme:BAAALAAECgMIBQAAAA==.Fuzu:BAAALAAECgIIAgAAAA==.',Ga='Gabrantthh:BAAALAAECgIIAgAAAA==.Gabrieljdv:BAAALAADCggICAAAAA==.Gaijins:BAAALAAECgcIDgAAAA==.Galâtëa:BAAALAADCggIEwAAAA==.Gargath:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.Gaviscon:BAAALAADCgcIBwAAAA==.',Ge='Gelote:BAAALAAECgIIAgAAAA==.Gerald:BAAALAADCgUICQAAAA==.',Gh='Ghordocabron:BAAALAADCgYICAAAAA==.',Gu='Gudmund:BAAALAADCgYIBgAAAA==.Guqnir:BAAALAAECgYICwAAAA==.',['Gú']='Gúldàn:BAAALAAECgMIAwAAAA==.',Ha='Hansis:BAAALAADCgUIAQAAAA==.Haydeé:BAAALAAECgMIAwAAAA==.Hazzani:BAAALAAECgIIAgAAAA==.',He='Hectordo:BAAALAAECggIDwAAAA==.Hekatormenta:BAAALAAECgMIAwAAAA==.Helzvog:BAAALAADCggIEAAAAA==.Hermion:BAAALAADCgYIBgAAAA==.',Hi='Hideyoshi:BAAALAAECgUIBwAAAA==.Hilgarri:BAAALAADCgYIBgAAAA==.',Hl='Hleyf:BAAALAAECgMIBgAAAA==.',Ho='Hollow:BAAALAAECgMIBQAAAA==.',Hy='Hyperbor:BAAALAADCggIDQABLAAECgMIBgABAAAAAA==.Hyperspain:BAAALAAECgMIBgAAAA==.Hyrmatia:BAAALAADCggIDwAAAA==.',['Hé']='Héroder:BAAALAADCgYIBgAAAA==.',['Hô']='Hôrusin:BAAALAAECgMIBgAAAA==.',Ib='Ibisol:BAAALAAECgYICQAAAA==.',Ig='Igneelya:BAAALAADCggICwAAAA==.',Il='Illiscar:BAAALAAECgMIBQAAAA==.Ilmatar:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',In='Instanity:BAAALAADCggICQABLAAECgYICgABAAAAAA==.Inyäuke:BAAALAADCgEIAQAAAA==.',Ir='Iroas:BAAALAAECgEIAQAAAA==.',Ja='Jamvius:BAAALAADCggIDwABLAAECgUIBQABAAAAAA==.Jazari:BAAALAADCgQIBQAAAA==.',Jm='Jmlee:BAAALAADCgMIAwAAAA==.',Jo='Joaquin:BAAALAADCggIEQAAAA==.Johnatan:BAAALAADCggIEgAAAA==.Joness:BAAALAAECgMIBgAAAA==.Joseartero:BAAALAAECgYIBgAAAA==.',['Jä']='Jäké:BAAALAAECgIIAwAAAA==.',Ka='Kagetsunu:BAAALAADCgQICAAAAA==.Kalesy:BAAALAAECgEIAQAAAA==.Kallypsso:BAAALAADCgEIAQAAAA==.Kalus:BAAALAAECgYICgAAAA==.Karlfury:BAAALAAECgMIAQAAAA==.',Ke='Kernos:BAAALAAECgIIAgAAAA==.Keroseno:BAAALAAECgMIAwAAAA==.Keyrou:BAAALAAECgYICAAAAA==.',Kh='Khalegon:BAAALAAECgEIAQAAAA==.Khinn:BAAALAAECgYICwAAAA==.',Ki='Kiva:BAAALAAECgYICAAAAA==.',Ko='Koeus:BAAALAAECgMIAwAAAA==.Kogmoyed:BAAALAADCggICwAAAA==.Kohäck:BAAALAADCggIDwAAAA==.Komodona:BAAALAAECgYIDAAAAA==.Kouranuruhay:BAAALAADCggIFwAAAA==.',Kp='Kpazatio:BAAALAADCgQIBwAAAA==.',Ku='Kuhlturista:BAAALAADCgcIBwAAAA==.Kurudruida:BAAALAAECgIIAwAAAA==.Kusin:BAAALAADCgQIBAAAAA==.',Ky='Kysle:BAAALAAECgYICwAAAA==.Kytäna:BAAALAADCgYIBgAAAA==.',['Kí']='Kínnara:BAAALAAECgQIBQAAAA==.',La='Lab:BAAALAAECgMIBQAAAA==.Lademonio:BAAALAADCggIEwAAAA==.Lakamal:BAAALAAECgEIAQAAAA==.Lalaby:BAAALAADCggIDQAAAA==.Lantecurios:BAAALAADCggIEwAAAA==.Larrydc:BAAALAAECgYICAAAAA==.Laën:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',Ld='Ldark:BAAALAAECgMIAwAAAA==.',Le='Leiä:BAAALAADCggIEwAAAA==.Lestrange:BAAALAADCgEIAQAAAA==.Leynda:BAAALAADCgcIBwAAAA==.',Li='Lightwar:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.Ligthstar:BAAALAADCgMIAwAAAA==.Lish:BAAALAADCgMIAwAAAA==.',Lo='Lobog:BAAALAAECgUICQAAAA==.Loha:BAAALAAECgUIBQAAAA==.Lokemo:BAAALAADCgYIBQAAAA==.Lomonegro:BAAALAADCgMIAwAAAA==.Loring:BAAALAADCgEIAQAAAA==.Lorxen:BAAALAADCgIIAgAAAA==.Lostbeast:BAAALAADCgUIBwAAAA==.',Lu='Lukÿ:BAAALAAECgQIBAAAAA==.Lupodeath:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Lurmyr:BAAALAADCggIEwAAAA==.',Ly='Lylaeth:BAAALAADCgUIBQAAAA==.',['Lé']='Léfat:BAAALAADCgcICAAAAA==.',Ma='Macizza:BAAALAAECgMIBgAAAA==.Magufo:BAAALAAECgMIAwABLAAECgcIEQABAAAAAA==.Malakøi:BAAALAADCgcIBwAAAA==.Maniotas:BAAALAADCgcIBwAAAA==.Maokun:BAAALAAECgYIDwAAAA==.Margón:BAAALAADCggICAAAAA==.Markez:BAAALAAECgEIAQAAAA==.Mas:BAAALAAECgIIAQAAAA==.Matapatos:BAAALAADCggIDwAAAA==.',Mc='Mcabro:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.',Me='Mecmec:BAAALAADCgUICAAAAA==.Meleys:BAAALAAECgEIAQAAAA==.Melindá:BAAALAADCgYICAAAAA==.Melith:BAAALAADCgMIAwAAAA==.Menfís:BAAALAAECgEIAQAAAA==.Methor:BAAALAAECgYIDAAAAA==.',Mi='Miladymarisa:BAAALAADCgMIAwAAAA==.Minze:BAAALAAECgIIAQAAAA==.Mitsumi:BAAALAAECgMIBQAAAA==.',Mo='Moildraf:BAAALAADCgMIAwAAAA==.Momolly:BAAALAAECgcIEQAAAA==.Morcega:BAAALAADCgcIBwAAAA==.Morguis:BAAALAADCgcIDgAAAA==.Morthîs:BAAALAADCgMIAwAAAA==.Morti:BAAALAAECgMIAwAAAA==.Mottiix:BAAALAADCggICAAAAA==.',Mu='Muelita:BAAALAADCgcIAQAAAA==.Muffinz:BAAALAAECgYICQABLAAECgcIEQABAAAAAA==.Murph:BAAALAADCgQIBAAAAA==.Mustakrakïsh:BAAALAAECgcIDgAAAA==.',My='Mythbusters:BAAALAAECgMIBQAAAA==.',['Má']='Máxdark:BAAALAADCggICwAAAA==.Máxica:BAAALAADCggICQAAAA==.',['Mä']='Mälakøi:BAAALAAECgEIAQAAAA==.Mänbrü:BAAALAAECgMIAwAAAA==.',['Mé']='Médici:BAAALAAECgYIDAAAAA==.',['Mï']='Mïcha:BAAALAAECgMIBQAAAA==.',Na='Nahuala:BAAALAADCgcICAAAAA==.Naomhy:BAAALAADCgMIAwAAAA==.Narfi:BAAALAADCggIFQAAAA==.Natsull:BAAALAAECgYIDAAAAA==.',Ne='Neferpitou:BAAALAAECgEIAQAAAA==.Neolidas:BAAALAAECgMIAgAAAA==.Nephtyes:BAAALAAECgIIAwAAAA==.',Ni='Nikini:BAAALAAECgIIBAABLAAECgMIAwABAAAAAA==.Ninjawarior:BAAALAADCgQIBAAAAA==.',No='Nokron:BAAALAAECgYIBgABLAAECgYICwABAAAAAA==.Noor:BAAALAAECgYICgAAAA==.Noreline:BAAALAADCggICgAAAA==.Norlum:BAAALAADCgMIBQAAAA==.Notdïe:BAAALAAECgEIAQAAAA==.',Nr='Nr:BAAALAADCgIIAgAAAA==.',['Nÿ']='Nÿxa:BAAALAAECgEIAgAAAA==.',Ob='Obsydian:BAAALAAECgMIBgAAAA==.',Oi='Oieminegro:BAAALAADCgYIBgAAAA==.',Ok='Okotto:BAAALAADCgcIBwAAAA==.',Or='Oralva:BAAALAADCgQIBAAAAA==.Orkde:BAAALAAECgQICAAAAA==.Orshabaal:BAAALAAECgIIAwAAAA==.Orïòn:BAAALAADCgYIDAAAAA==.',Ot='Ottís:BAAALAADCgcIBwAAAA==.',Ov='Ovalar:BAAALAADCgMIAwAAAA==.',Pa='Palakín:BAAALAADCgcICgAAAA==.Panzapanza:BAAALAADCgEIAQAAAA==.Parckys:BAAALAAECgYIDAAAAA==.Pathra:BAAALAADCgcICAAAAA==.',Pe='Pelotiketo:BAAALAAECgcIEgAAAA==.Pelouzana:BAAALAAECggIDgAAAA==.Percyman:BAAALAADCgEIAQAAAA==.Peri:BAAALAADCgcIBwAAAA==.Pewzu:BAAALAADCggICQAAAA==.',Pi='Pilarita:BAAALAADCgIIAgAAAA==.Pipøevoker:BAAALAAECgcIEAAAAA==.',Po='Podroto:BAAALAAECgcIDQAAAA==.Poggers:BAAALAAECgQIBwAAAA==.Pozí:BAAALAADCgcIBwAAAA==.',Pr='Princésa:BAAALAADCggICwAAAA==.',['Põ']='Põ:BAAALAADCgcICAAAAA==.',Qu='Queiroga:BAAALAAECgIIAwAAAA==.Quinos:BAAALAADCggICwAAAA==.',Ra='Raigdesol:BAAALAADCgQIBAAAAA==.Raistlìn:BAAALAADCgcIDAAAAA==.Rakuul:BAAALAAECgYICQAAAA==.Randorf:BAAALAADCggIDgAAAA==.Raphtel:BAAALAADCgUIBQAAAA==.',Re='Redjunter:BAAALAAECgQIBgAAAA==.Reima:BAAALAADCgUIBwAAAA==.Reydruida:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.',Rh='Rhauru:BAAALAAECgMIBQAAAA==.Rhaymast:BAAALAADCgQIBAAAAA==.Rheda:BAAALAADCggICQAAAA==.',Ri='Rindo:BAAALAAECgMIBAAAAA==.Rinky:BAAALAAECgQIBQAAAA==.Rivama:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.',Ro='Roma:BAAALAADCgQIAwAAAA==.Romperocas:BAAALAADCgYIBgAAAA==.',Ru='Ruamy:BAAALAAECgMIAwAAAA==.',Ry='Ryhal:BAAALAAECgYIDQAAAA==.Ryomonio:BAAALAAECgYICQAAAA==.Ryosaeba:BAAALAAECgMIAwAAAA==.',Sa='Sacerfo:BAAALAAECgcIDgAAAA==.Salfu:BAAALAAECgcICQAAAA==.Samanthä:BAAALAADCgIIAgAAAA==.Sanare:BAAALAADCgUIBQAAAA==.Santaklaus:BAABLAAECoEVAAICAAgIBiX4AwCdAgACAAgIBiX4AwCdAgAAAA==.Santuaria:BAAALAADCgMIAwAAAA==.Satürn:BAAALAADCgEIAQAAAA==.',Se='Secondus:BAAALAADCgIIAgAAAA==.Sencilla:BAAALAADCgQIBAAAAA==.Septllas:BAAALAAECgMIBgAAAA==.Sethtak:BAAALAAECgEIAQAAAA==.Sevy:BAAALAAECgEIAQAAAA==.',Sg='Sgàeyl:BAAALAADCgcIDgAAAA==.',Sh='Shadist:BAAALAAECggIAgAAAA==.Shaelara:BAAALAADCgMIAwAAAA==.Shalashin:BAAALAAECgcICgAAAA==.Shamansito:BAAALAAECgYIBwAAAA==.Shenjingbing:BAAALAAECgYIDQAAAA==.Shibba:BAAALAADCggICAAAAA==.Shiibba:BAAALAAECgUIBQAAAA==.Shinshampoo:BAAALAAECgEIAQAAAA==.Shintaro:BAAALAADCggIEAAAAA==.Shugos:BAAALAADCgIIAgAAAA==.Shurdh:BAAALAAECgIIAwAAAA==.Shâde:BAAALAADCgcIBwAAAA==.Shën:BAAALAADCggICwAAAA==.',Si='Sichadah:BAAALAADCgcIBwAAAA==.Silexion:BAAALAADCgIIAgAAAA==.Silmar:BAAALAADCggIDgAAAA==.Sindra:BAAALAAECgcIDAAAAA==.Sindrenei:BAAALAAECgEIAQAAAA==.',Sk='Skizof:BAAALAADCgMIAwAAAA==.Skultar:BAAALAADCgEIAQAAAA==.Skyred:BAAALAAECgYICgAAAA==.Skäadi:BAAALAADCgYIBgAAAA==.',Sl='Slilandro:BAAALAADCgYIBwAAAA==.',Sn='Snaerith:BAAALAADCgIIAgAAAA==.',So='Solgélida:BAAALAADCgYIBgAAAA==.Sonnyc:BAAALAADCgcIDAAAAA==.Sottanas:BAAALAAECgMIBgAAAA==.',Sp='Spectër:BAAALAADCgcIBwAAAA==.',Sr='Srlisters:BAAALAADCgcIBwAAAA==.Srstark:BAAALAADCgEIAQAAAA==.',St='Stickmaster:BAAALAADCgEIAQAAAA==.Storyboris:BAAALAAECgMIBQAAAA==.Storyborix:BAAALAADCgYIBgAAAA==.',Su='Suhné:BAAALAAECgIIAgAAAA==.Suken:BAAALAADCgcIDgABLAAECgcIDgABAAAAAA==.Sukki:BAAALAADCgIIAwAAAA==.Supratacos:BAAALAAECgYICgAAAA==.',Sy='Syl:BAAALAADCgQIBAAAAA==.Sylvän:BAAALAAECgYICwAAAA==.',['Sá']='Sámay:BAAALAAECgEIAQAAAA==.',['Sâ']='Sâlfuman:BAAALAADCgUIBQAAAA==.',Ta='Tagliatella:BAAALAAECgIIAgAAAA==.Talanjy:BAAALAADCgcIBwAAAA==.Taldoran:BAAALAADCgYIBwAAAA==.Taltaro:BAAALAADCgUIBQAAAA==.Tapucho:BAAALAADCgYICgAAAA==.',Te='Teneumbra:BAAALAADCgEIAQAAAA==.Tenxu:BAAALAADCggICwAAAA==.Termës:BAAALAAECgMIBQAAAA==.',Th='Themagician:BAAALAADCggIDgAAAA==.Therkan:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Thordin:BAAALAAECgIIAgAAAA==.Thumder:BAAALAAECgQIBwAAAA==.',Ti='Tichöndrius:BAAALAADCggICQAAAA==.Titania:BAAALAADCggICAABLAADCggICwABAAAAAA==.',To='Toixoneta:BAAALAADCgcICgAAAA==.Toukä:BAAALAAECgcIDwAAAA==.',Tr='Trankishan:BAAALAAECgYIDQAAAA==.Traumatico:BAAALAAECgYIBgAAAA==.Troia:BAAALAAECgYIBQAAAA==.',Tu='Tula:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.',Ul='Uluk:BAAALAADCggIDQAAAA==.',Um='Umbrak:BAAALAADCgcIDgAAAA==.',Ur='Urthysis:BAAALAADCggIEAAAAA==.',Uy='Uykmiedo:BAAALAADCgYIBgAAAA==.',Va='Vaaldor:BAAALAADCgcIDQAAAA==.Vajra:BAAALAAECgcIDgAAAA==.Valerius:BAAALAAECggIBAAAAA==.Valix:BAAALAAECgYICAAAAA==.Vallen:BAAALAADCgIIAgAAAA==.',Ve='Venradis:BAAALAADCgIIAgAAAA==.',Vh='Vhalsee:BAAALAAECgcIEQAAAA==.',Vo='Voldemört:BAAALAAECgYIBgAAAA==.Volthumn:BAAALAAECgEIAQAAAA==.Volverix:BAAALAADCggICAAAAA==.Vonderleyen:BAAALAADCgYIBAAAAA==.Vortexiña:BAAALAADCgQIBAAAAA==.',We='Wex:BAAALAAECgYICgAAAA==.',Wh='Whitelock:BAAALAAECgcICgAAAA==.Whitewar:BAAALAAECgYICwAAAA==.',Wu='Wut:BAAALAADCggICgAAAA==.',Xa='Xarolastriz:BAAALAADCgEIAQAAAA==.',Xd='Xd:BAAALAAECgcIEQAAAA==.',Xe='Xemnathas:BAAALAAECgEIAQAAAA==.',Xi='Xillian:BAAALAADCgcIDgAAAA==.',Xq='Xq:BAAALAADCgcIBwAAAA==.',Ya='Yamette:BAAALAADCgQIBAAAAA==.Yassineitor:BAAALAADCgYIBgAAAA==.Yavienna:BAAALAADCgQIBAAAAA==.',Ye='Yelldemoniac:BAAALAAECggIDAAAAA==.Yensa:BAAALAAECgEIAQAAAA==.',Za='Zanesfar:BAAALAADCggICAABLAAECgcIDgABAAAAAA==.Zazerzote:BAAALAAECgMIBgAAAA==.',Ze='Zeroo:BAAALAADCggICgAAAA==.',Zh='Zhuanyun:BAAALAAECgIIAgAAAA==.',Zo='Zoaroner:BAAALAADCgMIAwAAAA==.Zondp:BAAALAAECgQICQAAAA==.Zoth:BAAALAADCgEIAQAAAA==.Zothen:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.',Zz='Zzull:BAAALAADCgIIAgAAAA==.',['Âk']='Âkh:BAAALAADCggIDQAAAA==.',['Äk']='Äködö:BAAALAAECgEIAgABLAAECgMIBAABAAAAAA==.',['Ðe']='Ðemoliria:BAAALAAECgIIAgAAAA==.',['Ðu']='Ðucal:BAAALAAECgQIBAAAAA==.',['Üm']='Ümbra:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end