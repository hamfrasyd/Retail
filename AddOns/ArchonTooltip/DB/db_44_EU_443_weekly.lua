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
 local lookup = {'Unknown-Unknown','Mage-Frost','DeathKnight-Unholy','Hunter-BeastMastery','DeathKnight-Frost','Druid-Feral','Monk-Windwalker','Shaman-Elemental','Shaman-Restoration','Druid-Restoration','Druid-Balance','Monk-Brewmaster','Priest-Shadow','Warrior-Fury','Priest-Holy','Paladin-Retribution','Paladin-Holy','Hunter-Marksmanship','Warrior-Arms',}; local provider = {region='EU',realm='Lothar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abstergo:BAAALAADCggICAAAAA==.',Ad='Adamas:BAAALAAECgMIBQAAAA==.',Al='Alari:BAAALAAFFAIIAwAAAQ==.Alaribrew:BAAALAADCggICAABLAAFFAIIAwABAAAAAQ==.Alarî:BAAALAADCgQIBAAAAA==.Alterfelîx:BAAALAADCgcIDQAAAA==.Alzreateria:BAAALAADCgYIDQAAAA==.',Am='Ameckitos:BAAALAAECgYIDwAAAA==.Ameria:BAAALAAECgYIDwAAAA==.Amilly:BAAALAADCgcIBwAAAA==.Ammaranth:BAAALAAECgUICgAAAA==.Amous:BAAALAADCggICAAAAA==.Amunét:BAAALAAECgEIAQAAAA==.',An='Anitta:BAAALAADCggICAAAAA==.',Aq='Aquena:BAAALAAECgMIBQABLAAECggIFQACAEciAA==.',Ar='Araelien:BAAALAAECgUICwAAAA==.Arakas:BAAALAADCgUIBQAAAA==.Arath:BAAALAADCgcIBwAAAA==.Arono:BAAALAADCggIFwAAAA==.Arýa:BAAALAAECgEIAQAAAA==.',As='Ashdaleah:BAAALAAECgUIBQAAAA==.Ashînî:BAAALAADCggIFgAAAA==.Asja:BAAALAADCgcICgAAAA==.Askari:BAAALAAECgYICgAAAA==.Astora:BAAALAADCgcIBwAAAA==.',Av='Avrelle:BAAALAAECgUICAAAAA==.',Ay='Ayrah:BAAALAADCgcIDAAAAA==.',Az='Azathoth:BAAALAAECgMIBQAAAA==.',Ba='Ballrogg:BAAALAAECgEIAQAAAA==.Bankdude:BAAALAADCggICAAAAA==.Barthalos:BAAALAAECgYIDwAAAA==.',Bi='Binski:BAAALAADCgUIBQAAAA==.',Bo='Boleron:BAABLAAECoEVAAIDAAgI4x4MAwDUAgADAAgI4x4MAwDUAgAAAA==.Bossdudu:BAAALAADCgcIBwAAAA==.',Br='Brightlight:BAAALAADCgMIAgAAAA==.',['Bä']='Bärenliebe:BAAALAAECgYIBgABLAAECgYICQABAAAAAA==.',['Bê']='Bêâ:BAAALAAECgMIBQAAAA==.',['Bö']='Bömsch:BAAALAADCggICAAAAA==.',['Bù']='Bùnný:BAABLAAECoEVAAIEAAgIch0aCwC/AgAEAAgIch0aCwC/AgAAAA==.',Ca='Caldán:BAAALAAECgcICwAAAA==.Caliya:BAAALAADCgYIBgAAAA==.Callmeshock:BAAALAAECgEIAgAAAA==.Calyx:BAAALAADCggICAAAAA==.Carela:BAAALAAECgUICwAAAA==.',Ce='Ceallach:BAAALAAECgUICwAAAA==.',Ch='Chalis:BAAALAADCgIIAgAAAA==.Cherti:BAAALAAECgUIBQAAAA==.Chlorocresol:BAAALAAECgQIBAAAAA==.',Co='Conell:BAABLAAECoEhAAIFAAcIsiBVEQCUAgAFAAcIsiBVEQCUAgAAAA==.Coonie:BAAALAADCgcIDAAAAA==.',Cr='Crasher:BAAALAADCggIDwAAAA==.',Cu='Curia:BAAALAAECgMIBAAAAA==.',Da='Dahren:BAAALAAECggICQAAAA==.Danidragon:BAAALAAECgIIAgAAAA==.Darkdeamon:BAAALAADCgIIAgAAAA==.Dashennes:BAABLAAECoEVAAIGAAgIvR2FAgDkAgAGAAgIvR2FAgDkAgAAAA==.Dasjäger:BAAALAAECgYIBgABLAAECggIFwAHAHceAA==.',De='Deathfraig:BAAALAAECgMIAwAAAA==.Deathknight:BAAALAAECgUICwAAAA==.Deathpointer:BAAALAADCgEIAQAAAA==.Deep:BAAALAAECggICAAAAA==.Denetrus:BAAALAADCggICgAAAA==.',Dh='Dhannanis:BAAALAADCgcIDAAAAA==.',Di='Dirury:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Discbraten:BAAALAAECgIIAwAAAA==.',Dj='Djago:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Dm='Dmgdieter:BAAALAAECgMIBgAAAA==.',Do='Dokeni:BAAALAAECgQICgAAAA==.Dondavito:BAAALAADCgEIAQAAAA==.Donlak:BAAALAADCggIBAAAAA==.Donnella:BAAALAADCgcIDQAAAA==.Dorone:BAAALAAECgQIBwAAAA==.',Dr='Dragongîrl:BAAALAAECgUICgAAAA==.Drakthar:BAAALAAECgMIAwAAAA==.Dravco:BAAALAAECgEIAQAAAA==.Druïd:BAAALAAECggICAAAAA==.',Du='Duuri:BAAALAAECgEIAQAAAA==.',Ea='Earthlight:BAAALAAFFAIIAgAAAA==.',Ei='Eiszwerg:BAAALAAECgUIBQAAAA==.',El='Elburrìto:BAAALAAECgYIDAAAAA==.Ellburrito:BAAALAADCgQIBAAAAA==.Elvaters:BAAALAADCggIFgAAAA==.Elèmént:BAAALAAECgUICwAAAA==.',Em='Embrace:BAAALAAECgYIDQAAAA==.Emorius:BAAALAAECgUICwAAAA==.Empress:BAAALAADCgQIBAAAAA==.',En='Engelfli:BAAALAAECgEIAQAAAA==.Engelfly:BAAALAADCgYIBgAAAA==.Enõy:BAAALAADCgcIEQAAAA==.',Es='Esrâ:BAAALAADCggICAAAAA==.Esçanor:BAAALAAECgYIDAAAAA==.',Ev='Evilsonic:BAAALAAECgEIAQAAAA==.',Fa='Factor:BAAALAAECgYIDwAAAA==.Fatz:BAAALAAECgUICgAAAA==.Faulius:BAAALAADCggICAAAAA==.Faulus:BAAALAAECgEIAQAAAA==.Faura:BAAALAADCggIEgAAAA==.',Fe='Feather:BAABLAAECoEVAAMIAAgIyxwUDwBwAgAIAAcIyx4UDwBwAgAJAAEIBAlKhgAvAAAAAA==.Felidâe:BAAALAAECggICgAAAA==.Feloria:BAAALAADCggICAAAAA==.',Fl='Flavion:BAAALAADCgcIDAAAAA==.Florenda:BAABLAAECoEVAAIKAAgIdRXnEgD+AQAKAAgIdRXnEgD+AQAAAA==.Flunkor:BAAALAAECgMIBgAAAA==.',Fo='Fong:BAAALAAECgUICgAAAA==.Foox:BAAALAAECgEIAQAAAA==.',Fr='Freakbyme:BAAALAAECggICAAAAA==.',Ga='Gamblex:BAAALAAECgMIBgAAAA==.Gania:BAAALAADCgcICQAAAA==.Garthyrail:BAAALAADCgcICwAAAA==.',Ge='Genjar:BAAALAAECgQIBgAAAA==.Genshi:BAAALAAECgIIAwAAAA==.Gestrenge:BAAALAADCggIFAAAAA==.',Gh='Ghuly:BAAALAAECgUICQAAAA==.',Gl='Glimmrock:BAAALAADCgcIBwAAAA==.',Go='Gojira:BAAALAAECggICAAAAA==.Goodnìght:BAAALAAECgQIBgABLAAECggIFQACAEciAA==.',Gr='Grimbart:BAAALAAECgIIAgAAAA==.',Gu='Guldanramsey:BAAALAADCgQIBAAAAA==.',Gw='Gweny:BAAALAADCggIFAAAAA==.',['Gâ']='Gârwain:BAAALAADCgcIBgAAAA==.',Ha='Hackepeter:BAAALAADCgMIAwAAAA==.Hakula:BAAALAAECgMIBAAAAA==.Hanabi:BAAALAAECgMIBAAAAA==.Hanka:BAAALAADCggICAAAAA==.Hawke:BAAALAADCggIFwAAAA==.',He='Healdeeguard:BAAALAADCgcIDAAAAA==.Heidí:BAAALAADCgcIDQAAAA==.Heiligsmadl:BAAALAAECgcIDwAAAA==.Heróicorá:BAAALAADCggICAAAAA==.Heuljamit:BAAALAADCggIBQAAAA==.Hexfila:BAAALAAECgYIDgAAAA==.',Ho='Hogar:BAAALAADCggIDwAAAA==.Honnee:BAAALAAECgYICgAAAA==.Hordo:BAAALAAECgEIAQAAAA==.',['Hî']='Hîty:BAAALAADCgQIBQAAAA==.',Ic='Icéangel:BAAALAAECgEIAQAAAA==.',In='Inextremi:BAAALAAECgUICwAAAA==.Inki:BAAALAAECgMIBgABLAABCgcIBwABAAAAAA==.Insomniac:BAAALAAECgEIAQAAAA==.Inu:BAAALAAECgcICwAAAA==.',Is='Isnaa:BAAALAADCgcIDQAAAA==.',It='Ithlínne:BAAALAADCgcIBgAAAA==.',Ja='Janedoo:BAAALAADCgEIAQAAAA==.',Je='Jeverman:BAAALAAECgYICgAAAA==.',Ji='Jicky:BAAALAAECgQIBAAAAA==.',Jo='Joergimausi:BAAALAAECgIIAgAAAA==.',Ju='Jujube:BAAALAAECgUICgAAAA==.',['Jê']='Jêga:BAAALAADCggIFAAAAA==.',Ka='Kaffeebohne:BAAALAADCggICAAAAA==.Kalathor:BAAALAAECgMIBQAAAA==.Kalîna:BAAALAAECgYICQAAAA==.Kandâtsu:BAAALAADCgcIBwAAAA==.Karilux:BAAALAAECgYIDwAAAA==.Kavax:BAAALAAECgYICQAAAA==.',Ke='Kedi:BAAALAADCgMIAwAAAA==.',Kh='Khrimm:BAAALAAECgEIAQAAAA==.Khuno:BAAALAADCggIDwAAAA==.',Ki='Killertomate:BAAALAAECgYICgAAAA==.Kiniti:BAAALAAECgEIAQAAAA==.Kiyona:BAAALAADCggICAAAAA==.',Kl='Klorelia:BAAALAADCgcIBwAAAA==.',Kn='Knochenknut:BAAALAAECgMIBgAAAA==.',Ko='Koinheal:BAAALAADCgcIDAAAAA==.Komatös:BAAALAADCggICwAAAA==.Koraki:BAAALAAECgEIAgAAAA==.Koyeto:BAAALAAECgEIAQAAAA==.',Ku='Kuiil:BAAALAADCggIGAAAAA==.',Ky='Kyvanú:BAABLAAECoEVAAILAAgIXxBiGADVAQALAAgIXxBiGADVAQAAAA==.Kyvanúscham:BAAALAAECgMIAwAAAA==.',['Ké']='Kéhleyr:BAAALAAECgQIBAAAAA==.',La='Lacigale:BAAALAADCgYIBgAAAA==.Larentía:BAAALAADCggICAAAAA==.Laylia:BAAALAAFFAEIAQAAAA==.',Le='Leighla:BAAALAADCgIIAgAAAA==.',Li='Lillet:BAAALAAECgMIBgAAAA==.Lizzard:BAAALAADCgUIBQAAAA==.',Lo='Logarésh:BAAALAAECgYICwAAAA==.Lolika:BAAALAAFFAEIAQAAAA==.Lonik:BAAALAADCgMIAwABLAAECgUICgABAAAAAA==.Lorena:BAAALAAECgUIBQAAAA==.Lorgar:BAAALAADCggICAAAAA==.Lorim:BAAALAAECgUICgAAAA==.Lorina:BAAALAAECgYIDwAAAA==.Lorissa:BAAALAAECgEIAgAAAA==.',Lu='Ludo:BAAALAAECgYIDwAAAA==.Lumihoothoot:BAABLAAECoEWAAILAAgIkyCDCwCAAgALAAgIkyCDCwCAAgAAAA==.Lumîxy:BAAALAADCgEIAQABLAAECggIFgALAJMgAA==.',Ly='Lycàner:BAAALAADCggIDwAAAA==.Lynvala:BAAALAAECgcIDgAAAA==.Lyxe:BAAALAAECgIIAQAAAA==.',['Lí']='Lílanara:BAAALAADCggIFgAAAA==.Líllîth:BAAALAAECgYIBgAAAA==.',Ma='Macgoon:BAAALAAECgEIAQAAAA==.Machunt:BAAALAAECgMIBgAAAA==.Madàme:BAAALAAECgEIAQAAAA==.Malih:BAAALAAECgUICwAAAA==.Mandarîne:BAAALAAECgMIAwAAAA==.Mariel:BAAALAAECgUICwAAAA==.Marlen:BAAALAAECgUIBwAAAA==.Martego:BAAALAADCgcIBwAAAA==.Mashiro:BAAALAAECgMIBAAAAA==.Matayus:BAAALAADCgEIAQAAAA==.Maxim:BAAALAAECgEIAQAAAA==.',Me='Melaisa:BAAALAAECgUICAAAAA==.Meranda:BAAALAAECgIIAgAAAA==.Meshock:BAAALAAECgEIAQAAAA==.',Mi='Midera:BAAALAAECgYICgAAAA==.Milthred:BAAALAAECgEIAQAAAA==.Minona:BAAALAAECggIDwAAAA==.Mizukí:BAAALAAECgUICwAAAA==.',Mo='Mondbâr:BAAALAAECggICgAAAA==.Montie:BAAALAADCggICAAAAA==.Moonday:BAAALAAECgMIBQAAAA==.Moonozond:BAAALAAECgUICQABLAAECgUICwABAAAAAA==.Mor:BAAALAADCgcIBwAAAA==.',Mu='Muhladín:BAAALAADCgcIBwAAAA==.Muldar:BAAALAAECgMIBgAAAA==.',My='Mythica:BAAALAADCggICAAAAA==.',['Má']='Mávis:BAAALAAECgYICQAAAA==.',['Mä']='Mäggie:BAAALAADCgcIDQAAAA==.',['Mê']='Mêgo:BAABLAAECoEVAAIMAAgIMx8MAwDaAgAMAAgIMx8MAwDaAgAAAA==.',Na='Nackensteak:BAAALAADCgIIAgABLAAECgIIAQABAAAAAA==.Nadea:BAABLAAECoEVAAICAAgIRyIgAgAnAwACAAgIRyIgAgAnAwAAAA==.Nahiko:BAABLAAECoEVAAINAAgIPRg+DwBkAgANAAgIPRg+DwBkAgAAAA==.Nalie:BAAALAAECgMIBQAAAA==.Namaste:BAAALAAECgcIDQAAAA==.Namiel:BAAALAADCgcIBwAAAA==.Naves:BAAALAAECgEIAQAAAA==.Naxxi:BAAALAADCggICwAAAA==.',Ne='Nementhiel:BAAALAAECgMIBQAAAA==.Nerakson:BAAALAADCgcIBwAAAA==.Nevgond:BAAALAAECgMIBQAAAA==.Nexyrîa:BAAALAADCggIEgABLAAECgUICwABAAAAAA==.Neî:BAAALAAECgEIAgAAAA==.Neô:BAAALAAECgYIBgAAAA==.',Ni='Nibelien:BAAALAAECgUIBQAAAA==.Nique:BAAALAAECgEIAgAAAA==.Niuo:BAAALAAECgIIAQAAAA==.',No='Nobi:BAAALAADCggIDwAAAA==.',Ny='Nyphera:BAAALAADCggICAAAAA==.',['Né']='Néragodx:BAAALAADCgcIDwABLAAECgYIEAAOABYbAA==.Nérasan:BAABLAAECoEQAAIOAAYIFhsOHQDpAQAOAAYIFhsOHQDpAQAAAA==.',Od='Odryn:BAAALAAECgEIAgABLAAECgYICQABAAAAAA==.',Og='Ogórek:BAAALAAECgcIDgAAAA==.',Op='Optìmus:BAAALAAECgMIAwAAAA==.',Or='Orccro:BAAALAADCgYIBgAAAA==.Orcmon:BAAALAAECgYIDwAAAA==.Orthar:BAABLAAECoEVAAMDAAgI5xbfBQBuAgADAAgI5xbfBQBuAgAFAAEI/QfZmwAzAAAAAA==.',Os='Ossipuma:BAAALAAECgMIBQAAAA==.',Ou='Ouragan:BAAALAADCgcICgAAAA==.',Pa='Pakei:BAAALAADCgcIBwAAAA==.Palamon:BAAALAAECgYICwABLAAECgYIDwABAAAAAA==.Pandomax:BAABLAAECoEVAAIPAAgIPyBZBAD8AgAPAAgIPyBZBAD8AgAAAA==.',Pf='Pfafnir:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.',Ph='Phillepalle:BAAALAADCgEIAQAAAA==.',Pl='Plexx:BAAALAADCgEIAQAAAA==.',Qu='Quixos:BAAALAADCggICAAAAA==.',Ra='Racyareth:BAAALAADCgcIDQAAAA==.Rai:BAAALAADCggIDAABLAAECgUICwABAAAAAA==.Ralin:BAAALAAECgEIAgAAAA==.Ravius:BAAALAAECgcIEQAAAA==.',Re='Reachfight:BAAALAAECgcIDAAAAA==.Reinholz:BAAALAAECgUICwAAAA==.Returned:BAAALAADCggICAAAAA==.Rewonina:BAAALAAECgEIAQAAAA==.',Ri='Riac:BAAALAAECggIFQAAAQ==.',Ro='Rotor:BAAALAADCgcIBwAAAA==.',Ru='Rubley:BAAALAAECgUICAAAAA==.',['Rú']='Rúbydacherry:BAAALAADCgEIAQAAAA==.',Sa='Saafira:BAAALAADCggIEAAAAA==.Saiga:BAAALAADCggICAAAAA==.Salarya:BAAALAAECgMIAwAAAA==.Samilius:BAAALAADCggICAAAAA==.Sanara:BAAALAADCgcIDQAAAA==.Sanoxy:BAAALAADCgcIBwAAAA==.Santolina:BAAALAADCgIIAgAAAA==.Saphye:BAAALAADCgYIBgAAAA==.Sathria:BAAALAAECgcIDQAAAA==.',Sc='Schamasch:BAAALAADCgcIBwAAAA==.Schischong:BAAALAAECgMIBgAAAA==.',Se='Semidea:BAAALAAECgIIAgAAAA==.Semperito:BAAALAADCggICgAAAA==.Senshoux:BAABLAAECoEVAAMQAAgIrhyeEQCPAgAQAAcI0x+eEQCPAgARAAgIjxbQCgAqAgAAAA==.Sephi:BAAALAAECgEIAQAAAA==.Sethra:BAABLAAECoEVAAIEAAgI7Ro3EAB9AgAEAAgI7Ro3EAB9AgAAAA==.Sevîka:BAAALAADCggICAAAAA==.',Sh='Shael:BAAALAADCgIIAgAAAA==.Shalluna:BAAALAAECgQIBQAAAA==.Shallunâ:BAAALAAECgEIAQABLAAECgQIBQABAAAAAA==.Shikka:BAAALAAECgMIBAAAAA==.Shinoriah:BAAALAAECgUICwAAAA==.Shiresse:BAAALAAECgYIDAAAAA==.Shivaluna:BAAALAAECgUICgAAAA==.Shodashi:BAAALAAECgMIBQAAAA==.Shokzn:BAAALAAECgYIBgAAAA==.Shousui:BAAALAAECgEIAQAAAA==.Shysan:BAABLAAECoEVAAISAAgILiAkBgDXAgASAAgILiAkBgDXAgAAAA==.',Si='Sideways:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.Sindira:BAAALAADCgcIDQAAAA==.',So='Sorraja:BAAALAADCgcIBwAAAA==.',Sp='Spleen:BAAALAAECgMIBgAAAA==.Spookynooky:BAAALAADCgYIBgAAAA==.',Su='Suladria:BAAALAADCggIEAAAAA==.',Sy='Sylivrien:BAAALAAECgQICgAAAQ==.',Ta='Tamro:BAAALAADCggICAAAAA==.Tandoki:BAAALAAFFAMIAwAAAA==.Tarmo:BAAALAADCgQIBAAAAA==.Taurjan:BAAALAADCgUIBQAAAA==.Taylorswíft:BAAALAADCggICAAAAA==.',Te='Teldrag:BAAALAAECgEIAQAAAA==.Tellassa:BAAALAADCgQICQAAAA==.Tevv:BAAALAADCggICAAAAA==.Texa:BAAALAAECgEIAQAAAA==.',Th='Thalar:BAAALAAECgQIBQAAAA==.Theros:BAAALAAECgUICwAAAA==.',Ti='Timberly:BAAALAADCgcIDAAAAA==.Timii:BAAALAADCgcICwAAAA==.Tiseis:BAAALAAECgEIAgAAAA==.',To='Toastii:BAAALAAECgIIBAAAAA==.Togerass:BAAALAADCgEIAQAAAA==.Tohsaka:BAABLAAECoEVAAITAAgIGxssAgCAAgATAAgIGxssAgCAAgAAAA==.Topher:BAAALAAECgMIBgAAAA==.Torkal:BAAALAAECgUICwAAAA==.',Tr='Trueleader:BAAALAAECgUICwAAAA==.',Ts='Tsa:BAAALAAECgMIAwAAAA==.',Tt='Tton:BAAALAADCggICAAAAA==.',Ud='Udim:BAAALAAECgEIAwAAAA==.',Uk='Ukuwa:BAAALAAECgYICwAAAA==.',Ul='Ulther:BAAALAAECgEIAQAAAA==.',Un='Unkown:BAAALAAECgEIAgAAAA==.',Us='Usaca:BAAALAAECgMIBQAAAA==.',Ux='Uxmal:BAAALAADCgcIBwAAAA==.',Va='Valerina:BAAALAAECgMIAwAAAA==.Valnessa:BAAALAADCggICgAAAA==.Valraven:BAAALAAECgUIDQAAAA==.',Ve='Velencia:BAAALAAECgEIAQAAAA==.Velmoras:BAAALAADCgEIAQAAAA==.Versacé:BAAALAADCggICAAAAA==.',Vi='Violith:BAAALAADCggIDAAAAA==.Viridatrux:BAAALAAECgYIBwAAAA==.Vivy:BAAALAAECgYICQAAAA==.',Vo='Voldan:BAAALAADCgcIDQAAAA==.',Vu='Vulshok:BAAALAAECgEIAQAAAA==.',Wa='Warixus:BAAALAADCgcIEAAAAA==.',Wh='Whâtson:BAAALAADCggICAAAAA==.',Wi='Wilburga:BAAALAADCgcIBwAAAA==.',Wo='Wolfsfang:BAAALAAECgcIBwAAAA==.',Xa='Xande:BAAALAADCgcICwAAAA==.Xaroth:BAAALAADCgUIBQAAAA==.',Xc='Xcallica:BAAALAAECgMIBAAAAA==.',Xe='Xerina:BAAALAAECgEIAQAAAA==.',Xy='Xyth:BAAALAAECgYIBgAAAA==.',Ya='Yaleira:BAAALAAECgMIBgAAAA==.',Ye='Yedia:BAAALAAECgUICgAAAA==.',Yo='Yonsho:BAAALAADCggICwAAAA==.',Yu='Yuelin:BAAALAAECgMIBQAAAA==.',Za='Zalah:BAAALAADCggICAAAAA==.Zamber:BAABLAAECoEVAAIOAAgI4iR5AQBqAwAOAAgI4iR5AQBqAwAAAA==.Zarubi:BAAALAAECgEIAQAAAA==.Zat:BAAALAAECgQICgAAAQ==.',Ze='Zeedan:BAAALAADCgYIBgAAAA==.Zehn:BAAALAAECgEIAQAAAA==.',Zw='Zwörgnase:BAAALAADCgIIAgAAAA==.',Zy='Zyrinia:BAAALAAECgEIAQAAAA==.',['Àn']='Ànruna:BAAALAAECgQIBQAAAA==.',['Às']='Àshe:BAAALAADCgYIBgAAAA==.',['Ìk']='Ìká:BAAALAAECgUIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end