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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Shaman-Restoration',}; local provider = {region='EU',realm="Sen'jin",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abate:BAAALAAECgEIAQAAAA==.',Ag='Age:BAAALAAECgMIAwAAAA==.',Ak='Akrasiabow:BAAALAADCgcICAAAAA==.Akrasiapally:BAAALAADCgMIAwABLAADCgcICAABAAAAAA==.',Al='Altfvier:BAAALAAECgEIAQAAAA==.',Am='Amberle:BAAALAADCggIGwAAAA==.',An='Anolahshuri:BAAALAAECgMIAwAAAA==.Anuksa:BAAALAADCggIDgAAAA==.',Ap='Apollonier:BAAALAADCgQIBAAAAA==.',Ar='Artendor:BAAALAAECgMICAAAAA==.Artiø:BAAALAADCgMIAwAAAA==.Artío:BAAALAADCgMIAwAAAA==.Arwenus:BAAALAADCgEIAQAAAA==.Ary:BAAALAAECgUIBgAAAA==.',As='Aselage:BAAALAAECgYICAAAAA==.Asmodinâ:BAAALAADCgcIBwAAAA==.',Au='Auabär:BAAALAADCgcIBwAAAA==.',Av='Avéne:BAAALAADCggIEAAAAA==.',Ay='Aynn:BAAALAADCggIDgABLAAECgYIBgABAAAAAA==.',Az='Azra:BAAALAAECgIIBAAAAA==.',Ba='Baahlarina:BAAALAADCggICAAAAA==.Barbo:BAAALAADCgcICQAAAA==.Baschtl:BAAALAAECggICAAAAA==.',Be='Beasst:BAAALAADCgEIAQAAAA==.Belisama:BAAALAAECgYICQAAAA==.',Bl='Blackbubble:BAAALAADCggIDwABLAAECgYICwABAAAAAA==.Bloodheart:BAAALAAECggICwAAAA==.',Bo='Boouhjit:BAAALAAECgMIBQAAAA==.Boxbeutel:BAAALAADCgcIBwAAAA==.',Br='Breadhead:BAAALAAECgYICgAAAA==.Broxara:BAAALAADCgcIBwABLAADCgcICwABAAAAAA==.Broxxa:BAAALAADCgcICwAAAA==.',Bu='Burt:BAAALAADCgcIDgAAAA==.',['Bà']='Bàlîn:BAAALAAECgMIBgAAAA==.',['Bù']='Bùdspencer:BAAALAAECgUIBwAAAA==.',Ca='Caetheas:BAAALAADCgYIBgAAAA==.Caprina:BAAALAAECgIIAgAAAA==.Cattleyá:BAAALAADCgcIDAAAAA==.',Ce='Cediiy:BAAALAADCggICAAAAA==.Cein:BAAALAAECgMIBQAAAA==.Cernius:BAAALAADCggIEAAAAA==.',Ch='Charas:BAAALAAECgQIBgAAAA==.Chenna:BAAALAAECgYICAAAAA==.Chronormo:BAAALAADCgcICgAAAA==.',Cl='Claidissa:BAAALAAECgMIBAAAAA==.',Cr='Croffle:BAAALAADCggICAAAAA==.',Da='Dalegus:BAAALAADCgUIBQAAAA==.Daniel:BAAALAAECgYIBwAAAA==.Dantè:BAAALAADCggIDQAAAA==.Darkîne:BAAALAADCgYICAAAAA==.',De='Deathdome:BAAALAADCgcIDgAAAA==.Deathmakke:BAAALAAECgMIBgAAAA==.Deldoron:BAAALAAECgIIAgAAAA==.',Do='Doki:BAAALAAECggIEgAAAA==.',Dr='Dracwingduck:BAAALAADCgYIBwAAAA==.Dragonmaik:BAAALAADCgcIDQAAAA==.Drendor:BAAALAADCggICwABLAAECggIFgACANchAA==.Drowranger:BAAALAADCgYICgABLAAECgYICQABAAAAAA==.',Du='Dumesa:BAAALAAECgYICwAAAA==.Dunreb:BAAALAADCgcIDgAAAA==.',Dw='Dwarjon:BAAALAADCgUIBQAAAA==.',Dy='Dylara:BAAALAADCggIDwAAAA==.',['Dâ']='Dânte:BAAALAADCggICAABLAAECgYICwABAAAAAA==.Dânyel:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.',['Dí']='Díego:BAAALAAECgEIAQAAAA==.',Ed='Edrélua:BAAALAADCgcIDQAAAA==.',El='Eldria:BAAALAADCggIEQAAAA==.Elemdor:BAAALAAECgYIBwAAAA==.Elfenliied:BAAALAADCggIDwAAAA==.Elizara:BAAALAAECgYIBgAAAA==.Ellisha:BAAALAAECgYICQAAAA==.',Em='Emaríel:BAAALAAECgEIAQAAAA==.',En='Enterprise:BAAALAADCgEIAQAAAA==.',Er='Erendis:BAAALAADCgcICQAAAA==.',Es='Estaruu:BAAALAADCgcIDQAAAA==.',Et='Ethelyn:BAAALAADCggICAAAAA==.',Eu='Eurytion:BAAALAAECgYICQAAAA==.',Ex='Exíl:BAAALAADCggICAAAAA==.',Ey='Eynn:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.Eyr:BAAALAADCgMIBQABLAADCgcIDQABAAAAAA==.',['Eö']='Eöl:BAAALAAECgMIBgAAAA==.',Fi='Finsterbart:BAAALAAECgcIDgAAAA==.Firoh:BAAALAAECgcIDwABLAAECgYIDwABAAAAAA==.Firstdark:BAAALAAECggICAAAAA==.',Fl='Flattervieh:BAAALAADCggICAAAAA==.Fliki:BAAALAADCgIIAgAAAA==.',Fr='Frayta:BAAALAADCggIDwAAAA==.Freeya:BAAALAADCgcIDQAAAA==.Fridlin:BAAALAAECgIIAgAAAA==.Frostweber:BAAALAAECgIIAgAAAA==.Fréyà:BAAALAADCggICAAAAA==.',Ga='Galður:BAAALAAECgIIAgAAAA==.Gargora:BAAALAAECgMIBQAAAA==.',Gi='Gizzmondo:BAAALAAECgYIDwAAAA==.',Go='Golare:BAAALAADCgcIFQAAAA==.Gorgumenta:BAAALAADCgYIBgAAAA==.',Gr='Greed:BAAALAAECgIIBAAAAA==.Greendevile:BAAALAAECgMIAwAAAA==.Greensnow:BAAALAAECgIIAgAAAA==.Grimjoura:BAAALAADCgcIBwAAAA==.Grindol:BAAALAADCgcIBwAAAA==.Grischa:BAAALAADCgcICQAAAA==.Grünhornet:BAAALAAECgEIAQAAAA==.',['Gê']='Gêriêr:BAAALAADCgcIFQAAAA==.',Ha='Hawkmoon:BAAALAADCgQIBAAAAA==.',He='Headnor:BAAALAADCggIBQAAAA==.Hellhunter:BAAALAADCggIEwAAAA==.Hexenlády:BAAALAADCggIEAAAAA==.',['Hí']='Hínatá:BAAALAAECgMIAwAAAA==.',Ic='Ich:BAAALAADCggIDAABLAAECgIIBAABAAAAAA==.',Im='Imbaer:BAAALAAECgEIAwAAAA==.',In='Innabis:BAAALAADCgcIFQAAAA==.',Is='Isabellá:BAAALAADCggIGAAAAA==.',Ja='Jassi:BAAALAADCgcIBwAAAA==.',Ji='Jinsuan:BAAALAAECggICAAAAA==.',Jy='Jyinara:BAAALAADCgcIDgAAAA==.',Ka='Kaida:BAAALAAECgYIDwABLAAECggIFgACANchAA==.Kais:BAAALAAECgEIAQAAAA==.Kaiyora:BAAALAAECgYICQAAAA==.Karatee:BAAALAADCgcICQAAAA==.Karazek:BAAALAAECgcIEAAAAA==.',Ki='Kiinea:BAAALAAECgcIDwAAAA==.Kiwî:BAAALAAECgYICQAAAA==.',Ko='Komrod:BAABLAAECoEWAAIDAAgIRBV1FQAZAgADAAgIRBV1FQAZAgAAAA==.',Kr='Kratos:BAAALAAECgcIDwAAAA==.Kristallica:BAAALAADCggICAAAAA==.',Ky='Kytanix:BAAALAADCgYIBgAAAA==.',['Kâ']='Kâri:BAAALAAECgEIAQAAAA==.',La='Lauch:BAAALAAECgMIBgAAAA==.Layonlonso:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',Le='Leblack:BAAALAAECgYICwAAAA==.Legendb:BAAALAADCgcIBwAAAA==.Leshrak:BAAALAADCgMIAgAAAA==.Leukothea:BAAALAAECgUICgAAAA==.',Li='Lisanna:BAAALAAECgYICAAAAA==.',Lo='Lonsman:BAAALAAECgMIBQAAAA==.',Lu='Lupusius:BAAALAADCggICAAAAA==.',Ly='Lypsil:BAAALAADCggIDAAAAA==.Lyvaria:BAAALAAECgMIAwAAAA==.',['Lé']='Léa:BAAALAAECgcIEAAAAA==.',Ma='Magentis:BAAALAADCggIFQAAAA==.Magior:BAAALAAECgcIDQAAAA==.Maikj:BAAALAADCggIEgAAAA==.Maleachi:BAAALAAECgIIBAAAAA==.Mannilein:BAAALAAECgMIBgAAAA==.Maru:BAAALAAECgYICQAAAA==.',Me='Medícus:BAAALAAECgMIAwAAAA==.Melasculá:BAAALAAECgIIAwAAAA==.Melisándre:BAAALAAECgMIBAABLAAECgYIBgABAAAAAA==.',Mi='Mirell:BAAALAADCgcIDgAAAA==.Mireyla:BAAALAADCggIDwAAAA==.',Mo='Molgren:BAAALAADCggIBQAAAA==.Monari:BAAALAADCgYICgAAAA==.Moorlord:BAAALAAECggICAAAAA==.Morida:BAAALAAECgMIBgAAAA==.Morteques:BAAALAADCgMIAwAAAA==.',Mu='Mugand:BAAALAADCggIBwAAAA==.Muspek:BAAALAADCgEIAQAAAA==.',My='Myrdania:BAAALAAECgMIAwAAAA==.Mystiqué:BAAALAADCgUIBQAAAA==.Mystìque:BAAALAAECgcIDwAAAA==.',['Mî']='Mîndgâmes:BAAALAADCggIDwAAAA==.',Na='Nali:BAAALAADCgcIDAAAAA==.Natnat:BAAALAAECgYICQAAAA==.Naømi:BAAALAAECgIIAgAAAA==.Naýa:BAAALAADCgYIBgAAAA==.',Ne='Nekrovir:BAAALAAECgYICQAAAA==.Nelezwei:BAAALAAECgMIAwAAAA==.Neptun:BAAALAAECggICQAAAA==.Nexarion:BAAALAADCggIEAABLAAECgcIEwABAAAAAA==.Nexartus:BAAALAADCggIDwABLAAECgcIEwABAAAAAA==.',Ni='Nightsûn:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.Nikimia:BAAALAADCggIBgAAAA==.Nità:BAAALAADCgEIAQAAAA==.',Nu='Nutzlose:BAAALAAECgYIBgAAAA==.',Ny='Nyx:BAAALAAECgMIAwAAAA==.Nyxarona:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Nyxona:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Nyz:BAAALAADCgMIAwAAAA==.',['Né']='Nél:BAAALAADCgQIBAABLAAECgcIEAABAAAAAA==.',['Nê']='Nêphilim:BAAALAAECgMIAwAAAA==.',Od='Odon:BAAALAAECgYICQAAAA==.',Ol='Oldí:BAAALAAECgQIBgAAAA==.Olorim:BAAALAADCgIIAgAAAA==.',Or='Orkfrieda:BAAALAADCgcIBwAAAA==.',Pa='Palatarn:BAAALAAECggIDgAAAA==.Palpal:BAAALAAECgMIAwAAAA==.Pappagallo:BAAALAADCgMIBwAAAA==.Pappknight:BAAALAADCggICAAAAA==.Paschah:BAAALAAECgYICwAAAA==.Pasha:BAAALAAECgMIAwAAAA==.',Pi='Piffpaffpúff:BAAALAADCgcIDQAAAA==.Pilua:BAAALAADCggICAABLAAECggIDgABAAAAAA==.Pinea:BAAALAADCgUIBQAAAA==.',Po='Polocross:BAAALAADCgUIAwAAAA==.Porir:BAAALAADCgcIDAAAAA==.',Ra='Raagna:BAAALAADCgcIFQAAAA==.Raggna:BAAALAAECgMIAwAAAA==.Rahem:BAAALAAECgEIAQAAAA==.Raimei:BAAALAADCggICQAAAA==.Rainshowers:BAAALAAECgMIAwAAAA==.Razalmur:BAAALAADCgcIBwAAAA==.Raýa:BAAALAADCggIFgAAAA==.',Re='Reapia:BAAALAADCgcIEwAAAA==.Renenet:BAAALAADCgcIBwAAAA==.Rexin:BAAALAADCgcIEwAAAA==.Reyka:BAAALAADCggICgAAAA==.',['Rá']='Ráyna:BAAALAADCgEIAQAAAA==.',['Rì']='Rìn:BAAALAAECgMIBgAAAA==.',Sa='Saphir:BAAALAAECgIIBAAAAA==.Saphiron:BAAALAAECgIIAwAAAA==.Sarshiva:BAAALAADCgYIAgAAAA==.Sarwenia:BAAALAADCggICAAAAA==.',Sc='Schamadie:BAAALAAECgMIBgAAAA==.Schamakko:BAAALAADCgIIAwAAAA==.Schandra:BAAALAADCggIEgAAAA==.Schokominzaa:BAAALAAECgMIAwAAAA==.',Se='Sebbi:BAAALAADCgcICQAAAA==.',Sh='Shandrâ:BAAALAAECgYICQAAAA==.Shaonling:BAAALAAECgIIAgAAAA==.Sharky:BAAALAAECgcIEAAAAA==.Sharkyna:BAAALAADCgUIBQABLAAECgcIEAABAAAAAA==.Sheeva:BAAALAADCgcIDgAAAA==.Shimatsu:BAAALAADCgcIBwAAAA==.Shyva:BAAALAADCgUIBQAAAA==.Shôcky:BAAALAADCgYIBgAAAA==.',Si='Sindiu:BAAALAADCggIEwAAAA==.',Sk='Skender:BAAALAAECgUIBgAAAA==.',Sn='Snôw:BAAALAAECgYICQAAAA==.',So='Solkai:BAAALAAECgYICQAAAA==.',Sp='Spin:BAAALAAECggIDwAAAA==.Spogy:BAAALAAECgQIBAAAAA==.',St='Starspieler:BAAALAADCgMIAwAAAA==.Stevie:BAAALAAECgcIDwAAAA==.Stichy:BAAALAAECgYIDQAAAA==.',Su='Sule:BAAALAAECgYICQAAAA==.Suppentrulli:BAAALAADCgMIAwAAAA==.',['Sé']='Sérénítý:BAAALAAECgMIAwAAAA==.',['Sô']='Sôngo:BAAALAAECgYICAAAAA==.',['Sü']='Süßbär:BAAALAADCgcIBwAAAA==.',['Sý']='Sýlphiette:BAAALAADCgcIBwAAAA==.',Ta='Tarvik:BAAALAAECgIIAwAAAA==.Taurifax:BAAALAADCgYICwAAAA==.',Te='Temperancè:BAAALAADCggIHwAAAA==.Testman:BAAALAADCggICAAAAA==.Teublitzer:BAAALAAECggIDQAAAA==.',Th='Thalesea:BAAALAAECgcICgAAAA==.Tharalla:BAAALAAECgYICgAAAA==.Theoverlord:BAAALAAECgIIAgAAAA==.Thríller:BAAALAAECgMIBgAAAA==.Thôr:BAAALAAECgUIDAAAAA==.',Ti='Tistaria:BAAALAADCgIIAgAAAA==.',Tj='Tjuvar:BAAALAAECgUICwAAAA==.',To='Totalschaden:BAAALAAECgMIAwAAAA==.',Tr='Trendina:BAABLAAECoEWAAICAAgI1yEQBAAFAwACAAgI1yEQBAAFAwAAAA==.Trinitara:BAAALAADCgUIBQAAAA==.Trinitat:BAAALAAECgQICQAAAA==.Trnty:BAAALAAECgYIDgAAAA==.Trntyxmw:BAAALAADCgMIAwABLAAECgYIDgABAAAAAA==.',Ty='Tyraiel:BAAALAADCggICQAAAA==.',['Tê']='Têjsha:BAAALAAECgEIAQAAAA==.',Ud='Udai:BAAALAADCgEIAQAAAA==.',Va='Vaelaris:BAAALAADCgcIBwAAAA==.Vallyra:BAAALAAECgYICgAAAA==.Vanu:BAAALAADCgcIDgAAAA==.Varaany:BAAALAAECgYIBgAAAA==.',Ve='Velathra:BAAALAADCggIEAAAAA==.Velá:BAAALAADCggIEAAAAA==.Veláya:BAAALAAECgEIAQAAAA==.Verlax:BAAALAAECgcICAAAAA==.',Vi='Victania:BAAALAAECgcIEwAAAA==.Viraia:BAAALAADCgIIAgAAAA==.Virodk:BAAALAAECgYIDwAAAA==.',Vl='Vlyana:BAAALAADCggICAAAAA==.',Vo='Vollgeill:BAAALAADCgUIBgAAAA==.',Wa='Waldhüterin:BAAALAAECgMIAwAAAA==.Wassermaxi:BAAALAAECggIDQAAAA==.',Wi='Wildboy:BAAALAAECgEIAQAAAA==.',Wu='Wummel:BAAALAADCgcIBwAAAA==.',Wy='Wynn:BAAALAAECgYIBgAAAA==.',['Wé']='Wéifêng:BAAALAADCggICAAAAA==.',Xn='Xnúj:BAAALAAECgMICAAAAA==.',Xo='Xollor:BAAALAAECgIIAQAAAA==.',['Xî']='Xîîânny:BAAALAAECgYICwAAAA==.',Yr='Yrel:BAAALAADCgcIFAAAAA==.',Ys='Yserâ:BAAALAAECgYICQAAAA==.',Za='Zandalpakala:BAAALAAECgMIBgAAAA==.Zarin:BAAALAADCgcIBwAAAA==.Zauberfeê:BAAALAAECgYICQAAAA==.Zawadî:BAAALAADCggICwAAAA==.Zayaleth:BAAALAAECgEIAQAAAA==.Zaylistra:BAAALAADCggIFgAAAA==.Zayumi:BAAALAADCgIIAgAAAA==.',Ze='Zenythía:BAAALAAECgYICQAAAA==.Zephyristraz:BAAALAADCggICgAAAA==.',Zo='Zoroha:BAAALAAECgEIAQAAAA==.Zosly:BAAALAADCgcIBwAAAA==.',Zy='Zymos:BAAALAADCgEIAQAAAA==.Zynaris:BAAALAAECgMIAwAAAA==.',['Áz']='Ázrá:BAAALAAECgIIAgAAAA==.',['Âr']='Âry:BAAALAADCgcIBwAAAA==.',['Ît']='Îtsddt:BAAALAAECgUIBQAAAA==.',['ßl']='ßloodhound:BAAALAAECgcIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end