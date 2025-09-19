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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Mage-Frost','Mage-Arcane',}; local provider = {region='EU',realm='Exodar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abalham:BAAALAAECgMIAwAAAA==.',Ae='Aedonia:BAAALAADCgQIBAAAAA==.Aelarion:BAAALAAECgYICwAAAA==.Aerthrei:BAAALAAECgYIBgAAAA==.',Af='Afy:BAAALAADCgcIDAAAAA==.',Ag='Aguda:BAAALAAECgQICAAAAA==.',Al='Alarìelle:BAAALAADCggICAAAAA==.Aldara:BAAALAADCgcIBwAAAA==.Aldreon:BAAALAAECgIIAwAAAA==.Alexpik:BAAALAADCgYIBgAAAA==.Alianaa:BAAALAADCggICQAAAA==.Alimaño:BAAALAAECgUIBwAAAA==.Alteina:BAAALAAECgIIAgAAAA==.Althurius:BAAALAADCggIDwAAAA==.Alëu:BAAALAADCggICAAAAA==.',Am='Amandaruibis:BAAALAAECgUIBQAAAA==.',An='Anbun:BAAALAADCgQIBAAAAA==.Ankou:BAAALAADCgIIAgAAAA==.Anxort:BAAALAAECgcIDwAAAA==.',Ar='Aralechan:BAAALAADCgcIBwAAAA==.Archagathus:BAAALAADCgYICAAAAA==.Armsant:BAAALAAECgIIAgAAAA==.Artorias:BAAALAADCggIDAAAAA==.Arzillidan:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.Arâtor:BAAALAADCggIHAAAAA==.',As='Aseere:BAAALAAECgEIAQAAAA==.',At='Atlantic:BAAALAAECggICAAAAA==.',Ax='Axoreth:BAAALAAECgUIBQAAAA==.',Ay='Ayev:BAAALAAECgEIAQAAAA==.',Az='Azuladó:BAAALAADCgEIAQAAAA==.Azulilla:BAAALAAECgUIDAAAAA==.',['Aí']='Aíka:BAAALAAECgYIDgAAAA==.',Ba='Bacon:BAAALAADCgYIDAAAAA==.Bada:BAAALAADCggIEQAAAA==.Balana:BAAALAADCgMIAwAAAA==.Bansheec:BAAALAADCgYICgAAAA==.Batys:BAAALAADCgMIAwAAAA==.',Be='Belangy:BAAALAAECgMIBQAAAA==.Bernje:BAAALAAECgYIBwAAAA==.',Bh='Bhuka:BAAALAAECgYIDAAAAA==.',Bl='Blackwiidoww:BAAALAADCgUIBQAAAA==.Bloodihammer:BAAALAADCggIFwAAAA==.Blutbad:BAAALAADCgYIBgAAAA==.',Bo='Bocatajamón:BAAALAADCggIDwAAAA==.Bortista:BAAALAAFFAIIAgAAAA==.',Br='Breccan:BAAALAADCgUIBQAAAA==.Brochetilla:BAAALAAECgYIDgAAAA==.Brombur:BAAALAADCggIFQAAAA==.Bromdk:BAAALAADCggIDgAAAA==.',Ca='Cacuna:BAAALAAECgMIBAAAAA==.Caelfa:BAAALAADCggIEAAAAA==.Calihunter:BAAALAADCgIIAgAAAA==.',Ce='Cerian:BAAALAAECgcICgAAAA==.Cerridwenn:BAAALAADCgYIBgAAAA==.',Ch='Chanell:BAAALAADCggICQAAAA==.Chuzas:BAAALAAECgIIBAAAAA==.',Ci='Cieloso:BAAALAAECgEIAQAAAA==.',Cl='Clarïty:BAAALAADCggICgAAAA==.',Cr='Croquetta:BAAALAADCgEIAQAAAA==.',Cu='Cuxiku:BAAALAAECgEIAQAAAA==.',Cy='Cyrek:BAAALAADCggIEAAAAA==.',['Cí']='Cídron:BAAALAADCgMIAwAAAA==.',Da='Daisuka:BAAALAADCgcICgAAAA==.Damawhite:BAAALAADCggICQAAAA==.Danred:BAAALAAECgEIAQAAAA==.Darkwing:BAAALAADCgIIAgAAAA==.',De='Deathrall:BAAALAADCggIIAAAAA==.Delaron:BAAALAAECgYIBgAAAA==.Desgadelha:BAAALAAECgUICAAAAA==.Destroid:BAAALAADCgEIAQAAAA==.',Di='Diabolica:BAAALAADCgYIBgAAAA==.Dianys:BAAALAADCggICAAAAA==.Diffâ:BAAALAADCgcICAAAAA==.Dixania:BAAALAADCggIEQAAAA==.',Do='Doe:BAAALAAECgQIBAAAAA==.Domosh:BAAALAADCggIDgABLAAECgMIBQABAAAAAA==.',Dr='Draeniman:BAAALAADCgYIBgAAAA==.Dragonitern:BAAALAADCgEIAQAAAA==.Dragonlaysa:BAAALAADCgUIBQAAAA==.Drakoroth:BAAALAADCgYICgAAAA==.Dranotan:BAAALAAECgIIAwAAAA==.Draë:BAAALAADCgYIDAAAAA==.Druidit:BAAALAADCgcIBwAAAA==.Druidote:BAAALAADCgUIBQAAAA==.Drukhari:BAAALAADCgcIBwAAAA==.Drusk:BAAALAADCgcIBwABLAAECggIDgABAAAAAA==.Dränna:BAAALAADCgIIAwAAAA==.',Dw='Dwayna:BAAALAAECgYIDQAAAA==.',Dy='Dystopía:BAAALAADCgMIAwAAAA==.',['Dô']='Dômos:BAAALAAECgMIBQAAAA==.',Ed='Edusite:BAAALAADCggIDQAAAA==.',El='Elinath:BAAALAAECgYICQAAAA==.Elir:BAAALAAECgIIAwAAAA==.Elirath:BAAALAAECgMIBAABLAAECgYICQABAAAAAA==.',En='Encenall:BAAALAADCgcIBwAAAA==.Endx:BAAALAADCgYICgAAAA==.Enrique:BAAALAAECgYICAAAAA==.',Er='Erickasm:BAAALAADCgcIDQAAAA==.Erloba:BAAALAADCgYIDAAAAA==.',Es='Eskalybusito:BAAALAADCgYIDAABLAADCggIDgABAAAAAA==.Essedia:BAAALAADCgcICAAAAA==.',Et='Etimos:BAAALAAECgIIAwAAAA==.',Ex='Exae:BAAALAADCgcICAAAAA==.',['Eú']='Eúnice:BAAALAADCgcIDQAAAA==.',Fa='Faëdra:BAAALAAECgEIAQAAAA==.',Fe='Feralhound:BAAALAAECgQIBAAAAA==.',Fl='Flappyy:BAAALAADCgEIAQAAAA==.',Fo='Fokkus:BAACLAAFFIEHAAMCAAMIWyGQAgAxAQACAAMIWyGQAgAxAQADAAEIlQNkDgBFAAAsAAQKgRgABAIACAj5JEACAFMDAAIACAjrJEACAFMDAAMABQh2FmsgAGYBAAQAAggRDtwdAJcAAAAA.',Fr='Fraystiek:BAAALAADCgcICwAAAA==.Frostfault:BAAALAAECgMIBgAAAA==.Frónt:BAAALAAECgYICwAAAA==.',Fu='Furîâ:BAAALAAECgYICgAAAA==.',['Fö']='Fördragón:BAAALAADCggICQAAAA==.',Ga='Gallon:BAAALAAECgEIAQAAAA==.Garaa:BAAALAADCgcIEgAAAA==.Garatoth:BAAALAAECgQIBAAAAA==.Gargarth:BAAALAADCgUIBgAAAA==.Gazzeellee:BAAALAAECgEIAQAAAA==.',Gh='Ghostrex:BAAALAADCgEIAQAAAA==.',Gr='Gragonus:BAAALAADCgYIBgABLAADCgcICgABAAAAAA==.Gragow:BAAALAADCgcICgAAAA==.Greenslayer:BAAALAAECgcICgAAAA==.Greine:BAAALAAECgMIAgAAAA==.',Gu='Guarrøsh:BAAALAAECgUICAAAAA==.Guayoota:BAAALAAECgUICQAAAA==.Guindy:BAAALAADCgIIAgAAAA==.',['Gô']='Gôldôrâk:BAAALAADCgcICAAAAA==.',Ha='Hahli:BAAALAAECgEIAQAAAA==.Hastaroth:BAAALAADCgQIBAAAAA==.',He='Hechilinda:BAAALAADCgYIDAAAAA==.Heiryc:BAAALAAECgMIAwAAAA==.',Hk='Hkorkst:BAAALAAECgQICAAAAA==.',Ho='Hooligan:BAAALAADCgMIBAAAAA==.',['Hö']='Höwler:BAAALAADCgEIAQAAAA==.',['Hø']='Hølä:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.Høøpa:BAAALAAECgIIAgAAAA==.',['Hü']='Hüor:BAAALAAECgYICgAAAA==.',Ic='Icefrost:BAAALAAECgYICAABLAAECgcICgABAAAAAA==.Icymaster:BAAALAAECgEIAQAAAA==.',Id='Idridan:BAAALAAECgEIAQAAAA==.',Ik='Ikk:BAAALAAECgIIAgAAAA==.',Il='Ilisene:BAAALAAECgMIBAAAAA==.Illthelion:BAAALAAECgIIAgAAAA==.',Im='Imnotyisus:BAAALAAECgEIAQAAAA==.',In='Infernos:BAAALAADCgIIAgAAAA==.Insanë:BAABLAAECoEVAAIFAAgIBiKYBgAMAwAFAAgIBiKYBgAMAwAAAA==.Insolencia:BAAALAAECgEIAQAAAA==.',Is='Iscc:BAAALAAECgYICAAAAA==.',Iv='Ivanra:BAAALAADCgQIBAAAAA==.Ivuzfarm:BAAALAADCgMIAwAAAA==.',Iz='Izanagii:BAAALAADCgcICQAAAA==.Izaras:BAAALAADCggIFQAAAA==.Izza:BAAALAAECgIIAgAAAA==.',Ja='Javirux:BAAALAADCggIEwAAAA==.Jazzminne:BAAALAADCggIEAAAAA==.',Je='Jesudas:BAAALAADCgYIBgAAAA==.',Ji='Jiafei:BAAALAADCgEIAQAAAA==.',Ju='Jugenio:BAAALAADCggIDwAAAA==.Jugenioo:BAAALAADCgMIAwAAAA==.Jumisans:BAAALAADCgUIBQAAAA==.Junsonwon:BAAALAADCgUIBQAAAA==.',Ka='Kadghar:BAAALAADCgEIAQAAAA==.Kaldraht:BAAALAAECgcICgAAAA==.Kandda:BAAALAAECgUIDAAAAA==.Kayxo:BAAALAADCggIDAAAAA==.',Ke='Kenjan:BAABLAAECoELAAIGAAYI7AoiIABFAQAGAAYI7AoiIABFAQAAAA==.Kessëlring:BAAALAAECgYIDwAAAA==.Kettchup:BAAALAADCgcIBwAAAA==.',Kh='Khyslai:BAAALAAECgYIDwAAAA==.',Ki='Killmong:BAAALAADCgIIAgAAAA==.Kinomoto:BAAALAAECgIIAgAAAA==.Kirxzz:BAAALAADCggIDwAAAA==.',Kl='Kleia:BAAALAAECggIDgAAAA==.Klexia:BAAALAAECgIIAgABLAAECggIDgABAAAAAA==.',Ko='Kohkaul:BAAALAADCgEIAQAAAA==.Kolono:BAAALAAECgEIAQAAAA==.Kolorao:BAAALAADCgEIAQAAAA==.Konrad:BAAALAADCgMIAwAAAA==.Koshii:BAAALAAECgQIBAAAAA==.Kostolom:BAAALAADCggICQAAAA==.',Kr='Kracht:BAAALAAECgEIAgAAAA==.Kralidus:BAAALAAECggIGwAAAQ==.Krazêr:BAAALAADCggICAAAAA==.Krishnâ:BAAALAAECgIIAwAAAA==.',Ku='Kurorogue:BAAALAAECgIIAgAAAA==.',Ky='Kyhon:BAAALAADCgEIAQAAAA==.Kyowe:BAAALAAECgIIAgAAAA==.Kyríe:BAAALAAECgMIAwAAAA==.',La='La:BAAALAAECgMIBAAAAA==.Laccress:BAAALAADCggICAAAAA==.Laerdat:BAAALAAECgYIBgAAAA==.Laevantine:BAAALAADCgcICQAAAA==.Lamoni:BAAALAADCgYIDAAAAA==.Lanegang:BAAALAADCgcICAAAAA==.',Le='Lechuzon:BAAALAADCgUIBwAAAA==.Leonar:BAAALAADCgcIAwAAAA==.Lethion:BAAALAADCggIDwAAAA==.Letumortis:BAAALAADCgMIAwAAAA==.',Li='Linalee:BAAALAAECgUIBQAAAA==.Lingxiaøyu:BAAALAADCggIDQAAAA==.',Ll='Llorim:BAAALAADCgMIAwAAAA==.',Lo='Lobiza:BAAALAADCggIEAAAAA==.',Lu='Lutel:BAAALAADCgYICgAAAA==.',Lx='Lx:BAAALAAECgYIDAAAAA==.',Ly='Lycanon:BAAALAAECgYICQAAAA==.',['Lî']='Lîz:BAAALAADCgYIBwAAAA==.',['Lø']='Løcknox:BAAALAADCgcIBwAAAA==.',['Lü']='Lüxôr:BAAALAAECgUICQAAAA==.',['Lÿ']='Lÿla:BAAALAAECgYIBgAAAA==.',Ma='Magicos:BAAALAAECgUIBgAAAA==.Magoboss:BAAALAAECgMIBAAAAA==.Malpatin:BAAALAAECgEIAQAAAA==.Mamertox:BAAALAADCgYICgAAAA==.Mawii:BAAALAADCgcIBwAAAA==.',Me='Mechanidhogg:BAAALAADCgYIBgAAAA==.Melpomener:BAAALAAECgUICQAAAA==.Menedir:BAAALAADCggIFAAAAA==.Mennon:BAAALAAECgMIAgAAAA==.',Mi='Miaussita:BAAALAAECgcIBwAAAA==.Micheela:BAAALAADCgYIBgAAAA==.Midarrow:BAAALAADCgEIAQAAAA==.Miihhxrchena:BAAALAAECgcIEAAAAA==.Minhoxsacer:BAAALAAECgYICQAAAA==.Minihealer:BAAALAADCgMIAgAAAA==.Miraunt:BAAALAADCgUIBwAAAA==.Misah:BAAALAAECgYICQAAAA==.',Mo='Morrón:BAAALAADCgMIAwAAAA==.Moshenpo:BAAALAADCggICgAAAA==.',Mu='Muffy:BAAALAAECgEIAQAAAA==.',['Mô']='Môrphüs:BAAALAAECgYICAAAAA==.',['Mö']='Möyra:BAAALAAECgMIBAAAAA==.',['Mø']='Mørrø:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.',Na='Nalak:BAAALAADCggIEgAAAA==.Narydie:BAAALAADCgcIBwAAAA==.Naturebringe:BAAALAADCggIBgAAAA==.Natáre:BAAALAAECgQIBQAAAA==.',Ne='Neferuh:BAAALAADCgcICQAAAA==.Nemur:BAAALAADCgEIAQAAAA==.Nenamia:BAAALAADCgEIAQAAAA==.',Ni='Ningendo:BAAALAADCggIFgAAAA==.Ninphadora:BAAALAAECgMIAwAAAA==.Niohöggr:BAAALAAECgYICwAAAA==.',No='Nocurolows:BAAALAAECgUICQAAAA==.Nocurona:BAAALAADCgMIAwAAAA==.Nocílla:BAAALAADCgMIBQAAAA==.Norawithh:BAAALAADCgIIAgAAAA==.',['Nö']='Nött:BAAALAADCgUIBQABLAAECgcIBwABAAAAAA==.',On='Oneshotter:BAAALAADCgYIBgAAAA==.',Or='Orco:BAAALAAECgcIBgAAAA==.Oronegro:BAAALAAECgMIAwAAAA==.',Os='Oseapanda:BAAALAAECgYIDgAAAA==.',Pa='Palanquetâ:BAAALAADCggICAAAAA==.Pastorin:BAAALAADCgUIBQAAAA==.Pathro:BAAALAADCggIEgAAAA==.',Pe='Pegamé:BAAALAAECgMIBgAAAA==.Perpon:BAAALAADCgQIBAAAAA==.',Pi='Pikoalex:BAAALAADCgcIBwAAAA==.Piru:BAAALAADCgMIBQAAAA==.Pitidh:BAAALAADCgYIBgAAAA==.',Po='Pokky:BAAALAADCgYIBgAAAA==.Pollidalf:BAABLAAECoEUAAMGAAgIwRm4BwBsAgAGAAgIwRm4BwBsAgAHAAYIagXOVAD5AAAAAA==.',Pr='Prmatrago:BAAALAAECgEIAQAAAA==.',Pt='Pthh:BAAALAAECggIDwAAAA==.',Pu='Puthress:BAAALAADCggIEAAAAA==.',Qu='Quetsalcoatl:BAAALAAECgIIAgABLAAECggIFAAGAMEZAA==.',Ra='Rayzenn:BAAALAAECgIIAgAAAA==.',Re='Reddemon:BAAALAAECggIDwAAAA==.Rekird:BAAALAADCgcIBwAAAA==.',Ri='Ribk:BAAALAADCgcICAAAAA==.Rickwolf:BAAALAADCggICAAAAA==.Riika:BAAALAADCgcIBwAAAA==.Riverwyndd:BAAALAADCgYIBwABLAADCgcIBwABAAAAAA==.',Ro='Robabocatas:BAAALAADCgcIBwAAAA==.',Ru='Rubenalcaraz:BAAALAAECgEIAQAAAA==.',Ry='Ryuzengatsu:BAAALAAECgYIEQAAAA==.',Sa='Sacervida:BAAALAADCgQIBgAAAA==.Sagiel:BAAALAADCgYIDAAAAA==.Saidra:BAAALAAECgYIBgAAAA==.Sanchuck:BAAALAAECgYIBgAAAA==.Sanki:BAAALAADCggIDQAAAA==.',Se='Senka:BAAALAADCggIDAAAAA==.Seys:BAAALAAECgMIBgAAAA==.',Sh='Shadownaxan:BAAALAADCggICgAAAA==.Shamalarion:BAAALAADCggICAAAAA==.Shaoflight:BAAALAADCgEIAQAAAA==.Sharmei:BAAALAAECgYICwAAAA==.Shelyss:BAAALAADCgYICgAAAA==.Shibalva:BAAALAADCgcICQAAAA==.Shosimura:BAAALAADCgYIBgAAAA==.',So='Sombri:BAAALAAECgUIBQAAAA==.Souruita:BAAALAAECgUIBQAAAA==.',Sp='Spyrobuya:BAAALAADCgQIBAAAAA==.',Ss='Ssauron:BAAALAAECgQIBQAAAA==.',St='Stormwing:BAAALAADCgYIBgAAAA==.',Su='Surgoncin:BAAALAAECgIIAgAAAA==.Suyou:BAAALAADCgUICQAAAA==.',['Sö']='Sölar:BAAALAAECgQIBQAAAA==.',['Sÿ']='Sÿrö:BAAALAAECgMIBAAAAA==.',Ta='Taese:BAAALAADCgcICgAAAA==.Talions:BAAALAADCggICAAAAA==.Tancos:BAAALAADCgQIBQAAAA==.Targaryel:BAAALAADCggIDwAAAA==.Tarkan:BAAALAADCgcIDQAAAA==.',Te='Tecuroduro:BAAALAADCggIEAAAAA==.Tecz:BAAALAADCgUIBgAAAA==.Tedmaki:BAAALAADCgQIBgAAAA==.Temaar:BAAALAADCggIEAAAAA==.Temu:BAAALAAECgUIBwAAAA==.Temyble:BAAALAADCgYIDAAAAA==.Tepegoduro:BAAALAAECgUIBgAAAA==.Tevildk:BAAALAADCgcIBwAAAA==.',Th='Thannatito:BAAALAAECgIIAgAAAA==.Thau:BAAALAAFFAIIAgAAAA==.Theowar:BAABLAAECoEXAAIDAAcIySV2AQANAwADAAcIySV2AQANAwAAAA==.Thorduil:BAAALAADCggICQAAAA==.Thranos:BAAALAADCgYIBgAAAA==.',Ti='Titö:BAAALAAECgEIAQAAAA==.',Tm='Tmiroitecuro:BAAALAADCgQIBAAAAA==.',To='Tolizs:BAAALAADCgcIBwAAAA==.Tololoco:BAABLAAECoEUAAIFAAgI+hdTEAB1AgAFAAgI+hdTEAB1AgAAAA==.Tonyton:BAAALAAECgMIAwAAAA==.Totewydd:BAAALAADCgUIBQAAAA==.',Tr='Troyalx:BAAALAADCgMIAwAAAA==.Tröyalx:BAAALAADCgcICAAAAA==.',Ts='Tsukiakari:BAAALAAECgMICAAAAA==.',Ty='Tyelka:BAAALAADCgYIBQAAAA==.',Uc='Uchiharuben:BAAALAADCggIEwAAAA==.',Un='Unneot:BAAALAADCggIDwAAAA==.',Va='Vaelia:BAAALAADCggICAAAAA==.Valdi:BAAALAADCgYIBwAAAA==.Valeför:BAAALAADCgIIAgABLAAECggIFQAFAAYiAA==.Valenzuela:BAAALAADCggIDgAAAA==.Vascoshot:BAAALAADCggICwAAAA==.',Ve='Veestâ:BAAALAAECgIIAwAAAA==.Vermithorr:BAAALAADCgcICAAAAA==.',Wa='Waterandice:BAAALAAECgQIBQAAAA==.',We='Welmaster:BAAALAADCggICAAAAA==.',Wh='Whitë:BAAALAADCggIDwAAAA==.',Wi='Willywallace:BAAALAADCgMIBgAAAA==.',Wo='Woolffy:BAAALAAECgQICAAAAA==.',Xe='Xephon:BAAALAAECgEIAQAAAA==.',Xh='Xhormander:BAAALAADCgcIBwAAAA==.',Xu='Xulian:BAAALAAECgEIAQAAAA==.',['Xû']='Xûrû:BAAALAADCgUIBQAAAA==.',Ya='Yaiser:BAAALAADCggICAAAAA==.Yamikaede:BAAALAADCgEIAQAAAA==.Yaraa:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Yarthasy:BAAALAAECgIIAwAAAA==.Yasariel:BAAALAAECgYIDAAAAA==.Yayita:BAAALAADCggICQAAAA==.',Yn='Ynarion:BAAALAAECgYICwAAAA==.',Ys='Yseraa:BAAALAAECgcIDQAAAA==.',Yu='Yuray:BAAALAAECgIIAgAAAA==.',Za='Zarpitajapan:BAAALAADCgcIBwAAAA==.',Zo='Zoros:BAAALAAECgYIDAAAAA==.',Zu='Zularlx:BAAALAADCggIDAAAAA==.Zularv:BAAALAAECgMIBAAAAA==.Zurimin:BAAALAAECgUIBgAAAA==.',['Âm']='Âmador:BAAALAAECgYIBgAAAA==.',['Âz']='Âzuli:BAAALAAECgEIAQAAAA==.',['Är']='Äräfin:BAAALAAECgIIBAAAAA==.',['Ås']='Åstaroth:BAAALAAECgMIBAAAAA==.',['Ël']='Ëlünë:BAAALAAECgYICAAAAA==.',['Ïr']='Ïrma:BAAALAADCgIIAgAAAA==.',['Ñâ']='Ñâmia:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end