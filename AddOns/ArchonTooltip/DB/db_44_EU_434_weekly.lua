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
 local lookup = {'Shaman-Restoration','Warrior-Fury','Unknown-Unknown','Warrior-Arms','Shaman-Elemental','Paladin-Retribution','Hunter-BeastMastery','Druid-Balance','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Mage-Arcane',}; local provider = {region='EU',realm='Gorgonnash',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Actròn:BAAALAADCggICgAAAA==.',Ae='Aeliria:BAAALAAECgYICgAAAA==.',Aj='Ajesh:BAAALAAECgYICQAAAA==.',Al='Alenja:BAAALAADCgcIDQAAAA==.',Ar='Araes:BAAALAAECgYIBgAAAA==.Arconia:BAAALAAECgYICwAAAA==.Artêmîs:BAAALAADCgYIBgAAAA==.Arïadne:BAAALAAECgYICQAAAA==.',Au='Aufzieheule:BAAALAAECgMIAwAAAA==.',Az='Azulâ:BAAALAADCgcICwAAAA==.Azzar:BAAALAAECgUIBQAAAA==.',Ba='Baldor:BAAALAADCgcIBwAAAA==.',Be='Beckie:BAAALAADCgIIAgAAAA==.Benedikt:BAAALAADCggICAAAAA==.',Bi='Bibabutzi:BAAALAAECgMIBAAAAA==.',Bj='Bjun:BAAALAAECgMIBQAAAA==.',Bl='Bloody:BAAALAAFFAIIAgAAAA==.Blowboi:BAAALAADCgYIBgAAAA==.',Bo='Boblox:BAAALAADCggIDwAAAA==.',Br='Brahless:BAAALAAECggICQAAAA==.Breeze:BAAALAADCgYIBwAAAA==.',Bu='Bufar:BAAALAADCggIEAAAAA==.Burzum:BAAALAAECgMIBQAAAA==.Butch:BAAALAADCggIEAAAAA==.',Ca='Caco:BAAALAADCgMIAwAAAA==.Camayne:BAAALAADCgEIAQAAAA==.Carsath:BAAALAAECgIIBAAAAA==.Caty:BAAALAAECgUICQAAAA==.Cazador:BAAALAAECgIIAgAAAA==.',Ce='Celestha:BAAALAADCgcIBwAAAA==.Celso:BAAALAAECggICAAAAA==.',Ch='Charlierunkl:BAAALAAECgEIAQAAAA==.Cheripala:BAAALAAECgYICgAAAA==.',Co='Coffeeshock:BAABLAAECoEUAAIBAAcI0xBjMAB1AQABAAcI0xBjMAB1AQAAAA==.',Da='Daregas:BAAALAADCggIDwAAAA==.Dashael:BAAALAAECgUICQAAAA==.',De='Deathstroyer:BAAALAADCggIDwAAAA==.Deathvoker:BAAALAAECgYIDgAAAA==.Derarzt:BAAALAADCgMIAwAAAA==.',Dh='Dhuun:BAAALAADCggIDwAAAA==.',Di='Dinermoe:BAACLAAFFIEFAAICAAMI9x/jAQAtAQACAAMI9x/jAQAtAQAsAAQKgRoAAgIACAghJeUCAEwDAAIACAghJeUCAEwDAAAA.',Do='Dontknow:BAAALAAECgcIEQAAAA==.Dovarâ:BAAALAAFFAEIAQAAAQ==.',Dr='Drfaust:BAAALAADCggIDwAAAA==.Drui:BAAALAADCgcIBwAAAA==.Drurain:BAAALAADCggICAABLAAECggICAADAAAAAA==.',Du='Ducacell:BAAALAADCggICAAAAA==.',Ea='Eardin:BAAALAADCggICQAAAA==.',Ed='Edgewalker:BAAALAAECgYICQAAAA==.',El='Elairys:BAAALAADCggICAAAAA==.Elfilein:BAAALAAECgYICQAAAA==.',En='Enju:BAAALAADCggIGAAAAA==.',Eo='Eowewia:BAAALAADCgUIBQAAAA==.',Er='Eri:BAAALAAECgEIAQAAAA==.',Ev='Evodra:BAAALAAECgIIAgAAAA==.',Ew='Ewolet:BAAALAAECgMIBQAAAA==.',Fa='Fahne:BAAALAAECgQICQAAAA==.',Fi='Filia:BAAALAAECgYICAAAAA==.',Fl='Flamjorosaja:BAAALAADCggIEAAAAA==.',Fo='Forukos:BAAALAAECggIBwAAAA==.Fotem:BAAALAAECggIDQAAAA==.',Fr='Friedali:BAAALAADCggICAAAAA==.',Ge='Gefrierkombi:BAAALAADCggICAABLAAFFAMIBQACAPcfAA==.Germag:BAAALAADCgcIBwABLAADCggIDwADAAAAAA==.',Gn='Gnarku:BAACLAAFFIEJAAICAAUIWxp3AAD5AQACAAUIWxp3AAD5AQAsAAQKgRsAAwIACAj5JW8BAGsDAAIACAjTJW8BAGsDAAQABAgjJscFAMoBAAAA.',Go='Gosa:BAAALAADCggIEAAAAA==.',Gr='Grodak:BAAALAADCgUIBQAAAA==.Groldak:BAAALAAECgIIAgAAAA==.Gromrak:BAAALAAECgEIAQAAAA==.',Gu='Gumse:BAAALAAECgIIAgAAAA==.',Ha='Hachtel:BAAALAAECggICAAAAA==.Halexorn:BAAALAADCgcIBwAAAA==.Hawai:BAAALAADCgcIBwAAAA==.',He='Headshock:BAABLAAECoEWAAIFAAgIdyQLBAA0AwAFAAgIdyQLBAA0AwAAAA==.Herbe:BAAALAADCggICAAAAA==.Heschdinitäg:BAAALAAECgEIAQAAAA==.Hexerion:BAAALAAECgYICAAAAA==.',['Hö']='Hörä:BAAALAAECgYIDAAAAA==.',Ic='Icykaty:BAAALAADCgcIBwAAAA==.',Id='Idy:BAAALAAECgYICgAAAA==.',Il='Illil:BAAALAAECgYIDgAAAA==.',In='Infernîa:BAAALAAECgMIAwAAAA==.Ingrain:BAAALAAECggICAAAAA==.',Ja='Jacktronghop:BAAALAADCgYIBgAAAA==.Jadarc:BAAALAADCgcICAAAAA==.',Je='Jelia:BAAALAADCggIFwAAAA==.Jeroquee:BAAALAADCggIFQAAAA==.',Ka='Kalmar:BAAALAAECgEIAQAAAA==.Kanaruto:BAAALAAECgQIBAAAAA==.',Kn='Knoppers:BAAALAADCgcICAAAAA==.',Ko='Kokoro:BAAALAAECgMIAwAAAA==.Kommandognom:BAAALAADCgEIAQAAAA==.',Kr='Krisu:BAAALAAECgMIAwAAAA==.Kroot:BAAALAADCgMIAwABLAAECgcIEQADAAAAAA==.',Ku='Kurage:BAAALAADCgYIBQAAAA==.',['Kü']='Kürbiskante:BAAALAAECgIIAgABLAAECgYIBgADAAAAAA==.',La='Layla:BAAALAAECgEIAQAAAA==.',Le='Lehonk:BAAALAADCgcIBwABLAAECgYIBgADAAAAAA==.Leonie:BAAALAADCgEIAQABLAAECgYIDgADAAAAAA==.',Lo='Lovealotbear:BAAALAAECggIEQAAAA==.',Lu='Lummelinchen:BAAALAAECgYICAAAAA==.Lustlurch:BAAALAADCggICAAAAA==.',Ma='Maetzlor:BAAALAADCggICQABLAAECggIFQAGAJIhAA==.Magecore:BAAALAADCggICAABLAAECggIGAAGAE0lAA==.Mahoni:BAAALAAECgMIAwAAAA==.Makuta:BAAALAADCgMIAwAAAA==.Mandus:BAAALAADCgcICAABLAAECggIFQAGAJIhAA==.Matunos:BAAALAAECgMIBAAAAA==.',Me='Mentos:BAAALAADCggICAAAAA==.',Mi='Milandiz:BAAALAADCggIBgAAAA==.Milanny:BAAALAAECgYICQAAAA==.Miltankk:BAAALAAFFAIIAgAAAA==.Mindsoul:BAAALAAECgIIAgAAAA==.Minervá:BAAALAAECgYICwAAAA==.',Mo='Molari:BAAALAAECgIIBAAAAA==.Moozy:BAAALAADCggICAAAAA==.Morvenna:BAAALAAECgYICQAAAA==.Motion:BAAALAAECgEIAQAAAA==.',Mu='Muho:BAAALAAECgMIBAAAAA==.',My='Myrafae:BAAALAAECggIEwAAAA==.',Na='Nalind:BAAALAADCggIDAAAAA==.',Ne='Nelyn:BAAALAAECgUICQABLAAECgcIEQADAAAAAA==.Nerzan:BAAALAAECgQIBgAAAA==.',Ni='Niemand:BAAALAADCgcIBQAAAA==.Nightbowler:BAAALAADCggICwAAAA==.Nightshoot:BAAALAADCgYIBgABLAAECgQIBAADAAAAAA==.Niralta:BAAALAADCgEIAQAAAA==.',No='Nordo:BAAALAAECgYICgAAAA==.Noxit:BAAALAADCggICAAAAA==.Noxll:BAAALAAECgYICQAAAA==.',Ny='Nymora:BAAALAAECgMIAwAAAA==.',Oh='Ohnezahn:BAAALAAECgYIDwAAAA==.',Or='Orbus:BAAALAADCggIDAAAAA==.Orthos:BAAALAAECgMIAwAAAA==.',Pa='Pallyboi:BAAALAADCggICAAAAA==.',Ph='Philirose:BAAALAAECgMIBAAAAA==.',Pp='Ppati:BAAALAAECgYICQABLAAECgYIDwADAAAAAA==.',Ps='Psychosalami:BAAALAADCggICAAAAA==.',Pu='Pullover:BAAALAADCgMIAwAAAA==.Punkdaft:BAAALAADCgQIBQAAAA==.Puppal:BAAALAADCgIIAgAAAA==.',['Pà']='Pàti:BAAALAAECgYIDwAAAA==.',Qi='Qisma:BAAALAAECgUIBwAAAA==.',Qu='Qumi:BAAALAADCggIEwAAAA==.',Ra='Ra:BAAALAAECgYIDAAAAA==.Rachun:BAAALAAECgYICwABLAAECggIGAAGAE0lAA==.Rahmalla:BAAALAAECggICAAAAA==.',Ri='Rillu:BAAALAAECgMIAwAAAA==.Riyria:BAAALAAECgIIAwAAAA==.',Ro='Rodríguez:BAAALAAECggIDQAAAA==.Rogni:BAAALAAECgEIAQAAAA==.Rompo:BAAALAAECgcICgABLAAECgcIFAACAIUcAA==.',Ry='Ryson:BAAALAAECgYICQAAAA==.',['Rô']='Rôwdypiper:BAAALAAECgIIBAAAAA==.',Sa='Saphira:BAAALAADCggIDgAAAA==.',Sc='Schmirgol:BAAALAAECgYIDAAAAA==.Scylla:BAAALAADCgcIBwAAAA==.',Se='Searx:BAAALAADCgcIFAABLAAECgYIDwADAAAAAA==.Securisdei:BAAALAAECgQIBgAAAA==.Sella:BAAALAADCgcIDAAAAA==.Semilock:BAAALAADCggIDwAAAA==.Serdeath:BAAALAAECgUIBQAAAA==.Seàrx:BAAALAADCgcIBwAAAA==.Seára:BAAALAAECgYIDwAAAA==.',Sh='Shacó:BAAALAADCgcIDQAAAA==.Shakuna:BAAALAAECgMIAwAAAA==.Shockwave:BAAALAAECgMIBQAAAA==.Shoxxy:BAAALAAECgQICQAAAA==.Shuná:BAAALAADCggIEAAAAA==.Shynore:BAAALAAECgYICwAAAA==.Shùna:BAAALAADCgcIBwAAAA==.',Si='Silan:BAAALAADCgcIBwABLAAECgIIBAADAAAAAA==.',Sn='Snâkee:BAAALAAECggIDgAAAA==.',So='Solarus:BAAALAAECgMIAwAAAA==.Solumon:BAAALAAECgYIBgAAAA==.',Sw='Swítsch:BAAALAAECgEIAQAAAA==.',Sy='Syriale:BAAALAAECgMIBgAAAA==.',Ta='Taloná:BAAALAAECgQIBAAAAA==.Tameme:BAAALAADCggIFQAAAA==.Tankwärtin:BAAALAADCgcIBQABLAADCggIEAADAAAAAA==.Taolinn:BAAALAAECgUICQAAAA==.Tarinûs:BAAALAAECgIIAgAAAA==.Tark:BAABLAAECoEVAAIGAAgIkiEkDwCtAgAGAAgIkiEkDwCtAgAAAA==.',Th='Thalindriel:BAAALAADCggIEAAAAA==.',Ti='Timaja:BAAALAADCgMIAwAAAA==.Tinks:BAAALAADCgYIBgAAAA==.',To='Todian:BAAALAADCgYIBgAAAA==.Toneh:BAAALAAECgYICwAAAA==.Torgaddonn:BAAALAAECgUIBgAAAA==.Torro:BAAALAAECgMIAwAAAA==.Totemboi:BAABLAAECoEVAAIBAAgIFx7jDQBZAgABAAgIFx7jDQBZAgAAAA==.Toâdy:BAAALAADCggICAAAAA==.',Tr='Tragast:BAAALAADCggIDAAAAA==.Trixs:BAAALAAECgYIBgAAAA==.Trommler:BAABLAAECoEVAAIHAAgImRw3DQCiAgAHAAgImRw3DQCiAgAAAA==.',Ts='Tsatoggua:BAAALAADCgcIDAAAAA==.',Tw='Twîztêr:BAAALAADCggIDwAAAA==.',Ty='Tyhra:BAAALAAECgIIBAAAAA==.Tyune:BAAALAAECgcIDAAAAA==.',['Tò']='Tòasty:BAAALAAECgMIAwAAAA==.',['Tó']='Tóady:BAABLAAECoEVAAIIAAgIviFACADCAgAIAAgIviFACADCAgAAAA==.',Un='Unlight:BAABLAAECoEWAAQJAAgIKBrpFgAdAgAJAAcIvhnpFgAdAgAKAAYIyAmzDAB+AQALAAEIEx1VTgBXAAAAAA==.Unrest:BAABLAAECoEUAAICAAcIhRw2EQBoAgACAAcIhRw2EQBoAgAAAA==.',Ve='Vexahlia:BAAALAADCgMIAwAAAA==.',Vi='Vi:BAAALAADCgQIBAAAAA==.',['Vù']='Vùlgrim:BAAALAADCggIDQAAAA==.',Wa='Walburgah:BAAALAADCggIEAAAAA==.Wawoker:BAAALAAECgQIBAABLAAECgcIFAAMAM0jAA==.',Wh='Whiskeyjoe:BAAALAAECgYICwAAAA==.',Wi='Wilmastreit:BAAALAAECgYICQAAAA==.',Wo='Wodkalilly:BAABLAAECoEYAAIGAAgITSUJAgBrAwAGAAgITSUJAgBrAwAAAA==.Wookieknight:BAAALAAECgMIAwAAAA==.',Wu='Wumbillidan:BAABLAAECoEUAAIMAAcIzSO3CgDrAgAMAAcIzSO3CgDrAgAAAA==.',Xa='Xaphian:BAAALAAECggIDwAAAA==.Xardras:BAAALAAECgMIBQAAAA==.',Ya='Yavanna:BAAALAAECgYICAAAAA==.',Yu='Yurach:BAAALAADCggIDQAAAA==.',Ze='Zehnkv:BAAALAAECgYICAAAAA==.Zerberon:BAAALAAECgcIDAABLAAECgcIFAANANAfAA==.Zerbini:BAABLAAECoEUAAINAAcI0B9iFACCAgANAAcI0B9iFACCAgAAAA==.Zerkí:BAAALAAECgMIAwAAAA==.',Zo='Zodiacus:BAAALAAECgEIAQAAAA==.Zol:BAAALAADCggIGAAAAA==.',['Ák']='Ákara:BAAALAADCgYIBgABLAAECggIGAAGAE0lAA==.',['Ðe']='Ðemira:BAAALAADCgcICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end