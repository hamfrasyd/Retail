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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Monk-Windwalker','DeathKnight-Frost','Shaman-Elemental','Evoker-Devastation','DemonHunter-Vengeance','Hunter-Survival','Monk-Mistweaver','Druid-Balance',}; local provider = {region='EU',realm='Forscherliga',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aarmon:BAAALAADCgYICwAAAA==.',Ad='Adzzon:BAAALAAECggICAAAAA==.',Ae='Aesthetic:BAAALAAECgEIAQAAAA==.',Ai='Ailie:BAAALAAECgIIAgAAAA==.',Ak='Akarí:BAAALAAECgYICQAAAA==.Akdorban:BAAALAAECgMIBgAAAA==.Akrakadabra:BAAALAAECgIIAgAAAA==.Akurayamino:BAAALAAECgYIDwAAAA==.',Al='Alaron:BAAALAAECgYIBwABLAAECgYICwABAAAAAA==.Aletharia:BAAALAADCgcIBwAAAA==.Aliis:BAAALAAECgMIBAAAAA==.Alunah:BAAALAADCgYICwAAAA==.',Am='Amelina:BAAALAAECgYICQAAAA==.Amellià:BAAALAAECgIIAgAAAA==.',An='Andromaky:BAAALAAECgMIBgAAAA==.Anjilu:BAAALAAECgMIBQAAAA==.Anyrienna:BAAALAADCgcIDgAAAA==.Anyska:BAAALAAECgIIAgAAAA==.',Ar='Ardorion:BAAALAADCgcIBwAAAA==.Arrateri:BAAALAAECgMIBgAAAA==.Arthana:BAAALAADCggIDwAAAA==.',As='Ashram:BAAALAAECgEIAgAAAA==.',At='Attol:BAAALAAECgEIAgAAAA==.',Au='Aud:BAAALAAECgcIDAAAAA==.',Av='Avania:BAAALAADCgcIBwAAAA==.Aventorian:BAAALAAECgIIAgAAAA==.',Az='Azshatar:BAAALAAECgYIDgAAAA==.Azzazi:BAAALAAECgIIAgAAAA==.',Ba='Baceldackel:BAAALAADCgUIBQAAAA==.Balu:BAAALAADCgcIBwAAAA==.Barokx:BAAALAAECgMIBQAAAA==.',Be='Beviso:BAAALAAECgIIAgAAAA==.',Bl='Blackdragon:BAAALAAECgIIAQAAAA==.',Bo='Borrs:BAAALAADCgcIBwAAAA==.',Br='Bravados:BAAALAADCggIFQAAAA==.Bròók:BAAALAAECgIIAgAAAA==.',['Bä']='Bähdskull:BAAALAAECgcIDwAAAA==.',Ca='Caitlin:BAAALAADCgUICAAAAA==.Calgatiar:BAAALAADCgcIBwAAAA==.Caliostro:BAAALAADCgcICgAAAA==.Canondah:BAAALAADCggIEQAAAA==.Cay:BAAALAADCgcICgAAAA==.',Ch='Chitose:BAAALAAECgEIAgAAAA==.Chodeweiner:BAAALAADCgQIBAAAAA==.Chárly:BAAALAADCgcICgABLAADCggIDAABAAAAAA==.',Cl='Clayd:BAAALAAECgYIDAAAAA==.',Co='Connie:BAAALAAECgMIBQAAAA==.',Da='Dahka:BAAALAADCgIIAgAAAA==.Darkbird:BAAALAAECgMIBAAAAA==.Darkshello:BAAALAADCgUIBQAAAA==.Daríon:BAAALAAECgYIDgAAAA==.Davedatlay:BAAALAAECggIDAAAAA==.Dazan:BAABLAAECoEUAAICAAgI1RzHCAB6AgACAAgI1RzHCAB6AgAAAA==.',De='Deathlight:BAAALAAECggIBgAAAA==.Default:BAAALAADCggIFwAAAA==.Deheilemacha:BAAALAAECgYICgAAAA==.Dejan:BAAALAAECgMIBgAAAA==.Delanny:BAAALAADCggIGAAAAA==.Deloyro:BAAALAADCgYIBQAAAA==.Dematos:BAAALAADCgMIAwAAAA==.Demonlink:BAAALAAECgYICQAAAA==.Deranadis:BAAALAADCgcICwAAAA==.Deviona:BAAALAADCgcICgAAAA==.',Di='Diwa:BAAALAAECgMIAwAAAA==.',Dr='Dragondeez:BAAALAADCggICwABLAAECgYICwABAAAAAA==.Dralun:BAAALAAECgUIBQAAAA==.Drapax:BAAALAAECgIIAgAAAA==.Dregona:BAAALAAECgYIDQAAAA==.Drexx:BAAALAAECgIIAwAAAA==.Droc:BAAALAAECgcIEAAAAA==.Druidkasia:BAAALAADCgcIDgAAAA==.Dróc:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.',Ds='Dschamp:BAAALAADCggIEAAAAA==.',Du='Duge:BAAALAAECgMIBAAAAA==.',Dw='Dworg:BAAALAAECgMIAwAAAA==.',['Dæ']='Dæmon:BAAALAADCgYIBgAAAA==.',['Dø']='Døntqqme:BAAALAADCgEIAQAAAA==.',['Dú']='Dúngar:BAAALAAECggIBgAAAA==.',Ed='Edgemaster:BAAALAADCgMIAwAAAA==.',Ei='Eisenhøwer:BAAALAADCggIFwAAAA==.',El='Elcidena:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.Eldirith:BAAALAADCggIDwAAAA==.Eliyantha:BAAALAAECgIIAgAAAA==.Elorèén:BAAALAADCggIDgAAAA==.Elunde:BAAALAADCgMIAwAAAA==.',Em='Emiroc:BAAALAAECgYIDAAAAA==.Emlyn:BAAALAAECgUIDAAAAA==.',En='Endorawen:BAAALAAECgIIAgAAAA==.Engallado:BAAALAAECgEIAQAAAA==.',Er='Eriag:BAAALAAECgIIAgAAAA==.',Ev='Evitana:BAAALAADCgcIDAAAAA==.',Fa='Faowyn:BAAALAAECgYIDAAAAA==.Fario:BAAALAAECgEIAQAAAA==.Fazil:BAAALAAECgEIAgAAAA==.',Fe='Fenrus:BAAALAAECgMIBgAAAA==.Fenso:BAAALAAECgYICwAAAA==.Ferrero:BAAALAAECgIIAgAAAA==.',Fu='Funker:BAAALAAECgEIAgAAAA==.',Fy='Fyera:BAAALAAECgcIEwAAAA==.',['Fá']='Fáelin:BAAALAAECggIDgAAAA==.',['Fâ']='Fâromir:BAAALAADCggICAAAAA==.',['Fø']='Føgme:BAABLAAECoEXAAIDAAgINSJgAwD8AgADAAgINSJgAwD8AgAAAA==.',Ga='Galateriar:BAAALAAECgEIAQAAAA==.Galdinos:BAAALAAECgIIAwAAAA==.Gannimed:BAAALAADCggIBgAAAA==.Gardaf:BAAALAAECgEIAQAAAA==.Garrz:BAAALAAECgMIAwAAAA==.Gathor:BAAALAADCgcIDAAAAA==.',Ge='Gehennas:BAAALAADCggICgAAAA==.Gelek:BAAALAADCgUIBQAAAA==.Gelino:BAAALAAECgMIBAAAAA==.',Gh='Ghostbloody:BAAALAAECggIAgAAAA==.',Gi='Giwolas:BAAALAAECgMIBgAAAA==.',Go='Gofri:BAABLAAECoEUAAIEAAcIvxkINgCuAQAEAAcIvxkINgCuAQAAAA==.Gonduro:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Gr='Gravitas:BAAALAADCgcIBwAAAA==.Grishna:BAAALAAECgcIDAAAAA==.',Gu='Gudebärbel:BAAALAAECgMIBAAAAA==.Gundyr:BAAALAADCgYICQAAAA==.Gunnhild:BAAALAADCggIDgABLAAECgEIAgABAAAAAA==.',Ha='Happyness:BAAALAADCgMIAwAAAA==.Haralt:BAAALAADCgUIBQAAAA==.',He='Hearis:BAAALAAECgYICwAAAA==.Heartstopper:BAAALAAECgMIBAAAAA==.Heilemacher:BAAALAAECgEIAQAAAA==.Heleth:BAAALAAECgYICwAAAA==.Helior:BAAALAADCgIIAgAAAA==.Heredia:BAAALAADCgUIBwAAAA==.',Ho='Hober:BAAALAAECgMIBAAAAA==.',['Há']='Háe:BAAALAADCggIEAABLAAECggIDgABAAAAAA==.',Ik='Ikmuss:BAAALAAECgYIDgAAAA==.',Il='Ilaia:BAAALAADCgUIBQAAAA==.Ilaydra:BAAALAADCggIFAAAAA==.',Im='Imâla:BAAALAADCggIDwAAAA==.',In='Inaly:BAAALAADCggIFwAAAA==.Inucari:BAAALAAECgMIBgAAAA==.',Ir='Irillyth:BAAALAAECgYICAAAAA==.',Is='Isop:BAAALAAECgIIAgAAAA==.',Ix='Ixee:BAAALAAECggICAABLAAECggICAABAAAAAA==.',['Iô']='Iôn:BAAALAAECggICAAAAA==.',Ja='Jajîra:BAAALAADCgcICgAAAA==.Jakru:BAAALAADCggICAAAAA==.',Je='Jebit:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Jeblo:BAAALAADCggICAABLAAECgEIAgABAAAAAA==.Jebrak:BAAALAAECgEIAgAAAA==.',Jo='Joejitzu:BAAALAAECgEIAQAAAA==.Jolia:BAAALAAECgIIAgAAAA==.Jonáh:BAAALAADCggIDgAAAA==.Jorbine:BAAALAADCggICAAAAA==.',Ju='Ju:BAAALAADCgQIBwAAAA==.',Ka='Kalera:BAAALAADCgcIBwAAAA==.Katran:BAABLAAECoEYAAIFAAgIgSBDCADiAgAFAAgIgSBDCADiAgAAAA==.Kazzuzzu:BAAALAADCgcIBQAAAA==.',Ke='Kennshïn:BAAALAADCggICAABLAAECgcICwABAAAAAA==.',Kh='Khale:BAAALAAECgEIAQAAAA==.Khrysalion:BAABLAAECoEXAAIGAAgIzSA/BQDwAgAGAAgIzSA/BQDwAgAAAA==.Khálysta:BAAALAAECgYIEAAAAA==.Khâlé:BAAALAADCggIFQAAAA==.',Ki='Kino:BAAALAADCgcIDQAAAA==.Kirai:BAABLAAECoEWAAIHAAgI0SHvAQD2AgAHAAgI0SHvAQD2AgAAAA==.Kizûna:BAAALAAECgIIAgAAAA==.',Kl='Kloppbot:BAAALAADCgYIBgAAAA==.Klárisá:BAAALAADCggICAAAAA==.',Ko='Korhambor:BAAALAADCgcIBQAAAA==.',Ku='Kuma:BAAALAAECgIIAgAAAA==.Kuroneko:BAAALAADCgcIDAAAAA==.Kuscheltier:BAAALAADCgYIBgAAAA==.',La='Lanari:BAAALAADCgUIBQAAAA==.Lancelott:BAAALAADCgcICgAAAA==.Lanigerunum:BAAALAADCgcIDAAAAA==.Lapinkûlta:BAAALAADCgcICgAAAA==.Larentía:BAAALAADCggIEgAAAA==.Laurabell:BAAALAADCgUIBQAAAA==.Lazirus:BAAALAAECgYICwAAAA==.',Le='Leha:BAAALAADCgYIBgAAAA==.Lenneki:BAAALAADCgcICgAAAA==.',Li='Lindara:BAAALAADCgYICwAAAA==.Liniu:BAAALAAECgcIEAAAAA==.Linorie:BAAALAAECgEIAQAAAA==.',Lo='Lokion:BAAALAADCgYIDAAAAA==.Loradine:BAAALAAECgIIAgAAAA==.Lormax:BAAALAAECgIIAgAAAA==.',Lu='Lucine:BAAALAAECggIBQAAAA==.Lucía:BAAALAAECgIIAgAAAA==.Lunastrasza:BAAALAAECgQIBAAAAA==.Lutzifer:BAAALAADCgEIAQAAAA==.',Ly='Lyanda:BAAALAADCggICAAAAA==.Lythandra:BAAALAAECgEIAgAAAA==.',['Lí']='Lía:BAAALAAECgMIBQAAAA==.Líoba:BAAALAADCgcIDgAAAA==.Líranda:BAAALAAECgYIDwAAAA==.',['Lî']='Lîrania:BAAALAAECgcIEgAAAA==.',['Lï']='Lïllïth:BAAALAAECgIIAgAAAA==.',Ma='Maevia:BAAALAAECgIIAgAAAA==.Magnaclysm:BAAALAAECgYICgAAAA==.Magneria:BAAALAAECgIIAgAAAA==.Mallesein:BAAALAADCgYIBgAAAA==.Mamoulian:BAAALAAECgQIBwAAAA==.Marjorie:BAAALAAECgcIBwAAAA==.Maugrin:BAAALAADCgcICgAAAA==.',Mc='Mcmuffin:BAAALAADCgcIDQAAAA==.',Me='Megamhax:BAAALAADCggIFwAAAA==.Meiread:BAAALAAECgIIAwAAAA==.Menori:BAAALAAECgYICwAAAA==.Mephestos:BAAALAADCgQIBAAAAA==.Merador:BAAALAAECgMIBgAAAA==.Merian:BAAALAAECggIDwAAAA==.',Mi='Miyani:BAAALAADCgYIBgABLAADCggIFwABAAAAAA==.',Mj='Mjernia:BAAALAAECgIIAgAAAA==.',Mo='Monklich:BAAALAADCggICgAAAA==.Moríturus:BAAALAAECgYIBgAAAA==.Moshu:BAAALAADCgEIAQAAAA==.',Mu='Muecke:BAAALAADCggIEAAAAA==.Muhevia:BAAALAADCgcIBwAAAA==.Muranox:BAAALAADCgYICwAAAA==.Murmon:BAAALAADCggIFgAAAA==.',My='Mycenas:BAAALAADCggIDwAAAA==.Myhenea:BAAALAAECgIIAgAAAA==.Mythar:BAAALAADCggIFgAAAA==.',['Mà']='Màrzael:BAAALAADCgcIBwAAAA==.',['Mê']='Mêdusa:BAAALAAECgUIBQAAAA==.',['Mí']='Míu:BAAALAAECgUIBgABLAAECgYICQABAAAAAA==.',['Mü']='Mützchen:BAAALAAECgcIDAAAAA==.',Na='Naaruda:BAAALAAECgMIBAAAAA==.Nahr:BAAALAAECgMIAwAAAA==.Najm:BAAALAADCggICAAAAA==.Nathasìl:BAAALAADCgcICgAAAA==.Navani:BAAALAAECggIAwAAAA==.',Ne='Nehmoc:BAAALAADCggIFAAAAA==.Nenodor:BAAALAAECgIIAgAAAA==.Nerio:BAAALAAECgMIAwAAAA==.Neyja:BAAALAADCgYIBgAAAA==.',Ni='Niewinter:BAAALAAECgYICwAAAA==.Nimêa:BAAALAADCgcIBwABLAAECgUIBQABAAAAAA==.',No='Nocturne:BAAALAADCggICAAAAA==.Noktua:BAAALAAECgIIAgAAAA==.Nordschrott:BAAALAAECgYIDQAAAA==.',Nu='Numerobis:BAAALAADCgYIBgAAAA==.',Ob='Oberguffel:BAAALAAECgYICwAAAA==.',Od='Odoniel:BAAALAAECgMIBgAAAA==.',Ok='Okeanos:BAAALAADCgMIAwAAAA==.',Or='Ormoga:BAAALAADCgMIAwAAAA==.',Pa='Pachini:BAAALAAECgUIBQAAAA==.Paldoro:BAAALAADCggIDAAAAA==.Parva:BAAALAAECgIIAgAAAA==.Pastoria:BAAALAADCggIDwAAAA==.',Pi='Pistacia:BAAALAADCggICAAAAA==.',Pl='Plux:BAAALAAECgYIBgAAAA==.Pluxp:BAAALAADCggICAAAAA==.',Pr='Preto:BAAALAADCgcICAAAAA==.Proteus:BAAALAADCgcICwAAAA==.',Qa='Qahonji:BAAALAADCggIDwAAAA==.',Qi='Qishi:BAAALAAECggICAAAAA==.',Qu='Quenzah:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.Quíntás:BAAALAADCggICAAAAA==.',Ra='Ragar:BAAALAADCggIEAAAAA==.Ravienna:BAAALAADCgYIEgAAAA==.',Rh='Rhapsodi:BAAALAAECgYICQAAAA==.Rhænira:BAAALAADCggIFwAAAA==.',Ri='Rilion:BAAALAADCggIEAAAAA==.',Ro='Rokket:BAAALAADCgcICgAAAA==.Rornagh:BAAALAAECgMIAwAAAA==.Rosâlia:BAAALAAECgcIDAAAAQ==.Rozao:BAAALAADCggICAAAAA==.',['Rí']='Rísha:BAAALAAECgMIAwAAAA==.',Sa='Sa:BAAALAAECgUIBwAAAA==.Sagarem:BAAALAAECgEIAQAAAA==.Saiyanjin:BAAALAAECgIIAgAAAA==.Sanilor:BAAALAAECgUICAAAAA==.Sanjib:BAAALAADCggICAAAAA==.Santee:BAAALAAECgIIBAAAAA==.Sarania:BAAALAADCgcIBwAAAA==.Sasakurina:BAAALAAFFAQIBAAAAA==.',Sc='Scaath:BAAALAADCgcICgAAAA==.Scabbs:BAAALAADCgcICwAAAA==.Scariel:BAAALAAECgUIBQAAAA==.Schattentânz:BAAALAAECgQIBwAAAA==.Schnurlo:BAAALAADCgYIBgAAAA==.Schoki:BAAALAADCggICAAAAA==.Schûrlo:BAAALAADCgcIBwAAAA==.',Se='Seleria:BAAALAADCggIFAAAAA==.',Sh='Shadrox:BAAALAAECggICAAAAA==.Shellox:BAAALAADCgQIBAAAAA==.Shorma:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.',Si='Silberhauch:BAAALAADCggICAAAAA==.Simsala:BAAALAADCggICwAAAA==.',Sl='Sloptok:BAAALAAECgIIAgAAAA==.',So='Sorinera:BAAALAADCgcICgAAAA==.',Sp='Sphärensturm:BAAALAAECgMIBAAAAA==.',Su='Sugrem:BAAALAAECgIIAgAAAA==.Sushigenesis:BAAALAAECgYICQAAAA==.',Sy='Sylvaran:BAAALAADCgYICwAAAA==.Syphondaddy:BAAALAADCggICAABLAAECggIFAACANUcAA==.Syrenya:BAAALAADCggIDwAAAA==.',['Sê']='Sêtsuko:BAAALAAECgYICQAAAA==.',['Só']='Sóul:BAAALAAECgMIBgAAAA==.',Ta='Talesin:BAAALAAECgMIAwAAAA==.Tanariel:BAAALAADCgYIBgAAAA==.Taurantulas:BAAALAAECgQIBwAAAA==.Taurea:BAAALAADCggIFwAAAA==.Tavyun:BAAALAAECgMIBQAAAA==.Tavzul:BAAALAADCgcIBwAAAA==.',Te='Tegtha:BAAALAAECgcICwAAAA==.Teruno:BAAALAAECggIEgAAAA==.Tesalonar:BAAALAAECgUIBwAAAA==.Tesaríus:BAAALAAECgIIAgABLAAECgYIDwABAAAAAA==.',Th='Thabia:BAAALAADCgcICgAAAA==.Thaeyoung:BAAALAAECgMIBAAAAA==.Tharukko:BAABLAAECoEUAAIIAAgI0RhpAQCgAgAIAAgI0RhpAQCgAgAAAA==.Theldar:BAAALAADCggIFgAAAA==.Thoknar:BAAALAAECggIAwAAAA==.Throbon:BAAALAADCggICQAAAA==.Thurianx:BAAALAAECgEIAQAAAA==.',Ti='Timber:BAAALAADCgUIBQAAAA==.Tirimira:BAAALAAECgQIBAAAAA==.',To='Tolpana:BAAALAADCgcICgAAAA==.Toshan:BAAALAAECgIIAgAAAA==.',Tr='Tramaios:BAAALAADCggIFAAAAA==.Trineas:BAAALAAECgcIEQAAAA==.Truppenküche:BAAALAAECgMIBgAAAA==.',Ts='Tsuruka:BAAALAADCgYIBgAAAA==.',Tu='Tullios:BAAALAADCgcIBwAAAA==.Turgarn:BAAALAAECggICAAAAA==.',Ty='Ty:BAAALAADCgYICwAAAA==.',['Tí']='Tíamat:BAAALAADCgYICgAAAA==.',['Tô']='Tôrvûs:BAAALAAECgMIBAAAAA==.',Ur='Urique:BAAALAADCgUIBQAAAA==.',Uz='Uzur:BAAALAADCggIEAAAAA==.Uzziel:BAAALAADCgUIBQAAAA==.',Va='Vagnard:BAAALAAECgcIBgAAAA==.',Ve='Velrax:BAABLAAECoEYAAIJAAgIoyP1AABAAwAJAAgIoyP1AABAAwAAAA==.Venati:BAAALAADCggIFQAAAA==.',Vh='Vhegar:BAAALAAECgMIBAAAAA==.',Vo='Voilia:BAAALAADCgcIDgAAAA==.',Vr='Vrugnir:BAAALAADCgYIBgAAAA==.',Vu='Vul:BAAALAADCgcIDQAAAA==.',Wa='Wacholder:BAAALAADCggIGAAAAA==.Walfaras:BAAALAAECgYIBgAAAA==.',Wi='Wintersturm:BAAALAADCggICAAAAA==.Wirbelwind:BAAALAAECgYICQAAAA==.Wiwaria:BAAALAAECgYIBgAAAA==.',Wo='Wolfgáng:BAAALAADCggIDAAAAA==.',['Wí']='Wíwa:BAAALAADCgcIBwAAAA==.Wíwarux:BAAALAADCggICwAAAA==.',Xc='Xcyy:BAAALAAECggICAABLAAECggIFgAEAEMkAA==.',Xe='Xeranova:BAAALAADCgYIBgAAAA==.',Xi='Xiaody:BAAALAAECgIIAgAAAA==.Xippy:BAAALAADCgYICgAAAA==.Xixie:BAAALAADCggICAAAAA==.',Xr='Xris:BAAALAADCgcICgAAAA==.',Ya='Yasuko:BAAALAAECgIIAgAAAA==.Yasumi:BAAALAADCgcIDAAAAA==.',Ye='Yelnyfy:BAAALAAECgMIBAAAAA==.Yeni:BAAALAADCgcIBwAAAA==.',Ys='Yskiera:BAAALAADCgcIFAAAAA==.',Yt='Ytonia:BAAALAADCggIDgAAAA==.',Yu='Yulson:BAAALAAECgIIAgAAAA==.Yuuji:BAAALAAECgMIBQAAAA==.',Yv='Yvessaint:BAAALAADCgcIDAAAAA==.',Yy='Yyd:BAABLAAECoEWAAIEAAYIQySzFgBiAgAEAAYIQySzFgBiAgAAAA==.',Za='Zakwen:BAAALAAECgMIBgAAAA==.Zangan:BAAALAADCgcICgAAAA==.Zavarelia:BAAALAAECgMIAwAAAA==.',Ze='Zelós:BAAALAADCggIDwAAAA==.Zeraide:BAABLAAECoEXAAMCAAgIBxeGDABHAgACAAgIBxeGDABHAgAKAAYIRgXtMwDgAAAAAA==.',Zh='Zhorynoir:BAAALAADCgUIBQAAAA==.',Zi='Zidane:BAAALAAECgUIBwAAAA==.',Zu='Zuajh:BAAALAADCgUIBQAAAA==.',['Àu']='Àurorá:BAAALAAECgYICQAAAA==.',['Ár']='Árwên:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end