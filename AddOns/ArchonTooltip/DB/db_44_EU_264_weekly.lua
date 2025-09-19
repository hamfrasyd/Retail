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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Paladin-Protection','DeathKnight-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Arcane','Priest-Shadow','Mage-Frost','Shaman-Elemental','Priest-Holy','Warlock-Demonology',}; local provider = {region='EU',realm='Bloodhoof',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aapipiron:BAAALAADCggIDgAAAA==.',Ad='Addriana:BAAALAADCggIFQABLAAECgIIAgABAAAAAA==.',Ae='Aeagris:BAAALAADCggICAAAAA==.Aevelaine:BAAALAAECgUICAAAAA==.',Ag='Agnés:BAAALAADCgIIAgAAAA==.',Ah='Ahad:BAABLAAECoEYAAMCAAgI1x9AEADiAgACAAgI1x9AEADiAgADAAEIjxs7NwBEAAAAAA==.Ahadbear:BAAALAADCgIIAgABLAAECggIGAACANcfAA==.Ahadfotm:BAAALAAECgcICwABLAAECggIGAACANcfAA==.Ahadsham:BAAALAAECgIIBgABLAAECggIGAACANcfAA==.Ahadwar:BAAALAAECgcIEgABLAAECggIGAACANcfAA==.',Ai='Aineas:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Al='Alrexx:BAAALAADCgYICgAAAA==.Alunara:BAAALAAECgMIBQAAAA==.Alvura:BAAALAADCgcIDgAAAA==.',Am='Ampyy:BAAALAADCggICAAAAA==.',An='Annushka:BAAALAADCggIEAAAAA==.Anqet:BAAALAAECgEIAQAAAA==.Anzhu:BAAALAAECgYIBgAAAA==.',Ap='Appelboom:BAAALAADCgMIAwAAAA==.',Ar='Aratir:BAAALAADCggIDwABLAADCggICAABAAAAAA==.Argorn:BAAALAADCgUICQAAAA==.Arwin:BAAALAAECggICAAAAA==.Arwinn:BAAALAAECggIEAAAAA==.Arwinx:BAAALAAECggICAAAAA==.',At='Atom:BAABLAAECoEUAAIEAAcIjSB7BwCLAgAEAAcIjSB7BwCLAgAAAA==.Attikus:BAAALAAECgMIBQAAAA==.',Au='Audigy:BAAALAAECgIIAgAAAA==.',Ba='Backjauer:BAAALAAECgQICAAAAA==.Bari:BAAALAADCggIEAABLAADCggIGAABAAAAAA==.',Be='Beerbaron:BAAALAAECggIBwAAAA==.Belaris:BAAALAAECgEIAQAAAA==.Benjamano:BAAALAADCgcIBwAAAA==.',Bi='Bigbossy:BAAALAAECgYIEgAAAA==.Biggingerrob:BAAALAAECgYIBgAAAA==.Binouze:BAAALAAECgQIBAAAAA==.Bisomnio:BAAALAAECgYICgAAAA==.',Bl='Blurinho:BAAALAAECgYICgAAAA==.',Bo='Bobandy:BAAALAAECgcIEgAAAA==.Bonez:BAAALAAECgYICQAAAA==.Borcan:BAAALAAECgUIBwAAAA==.Borr:BAAALAADCggICAABLAADCggIGAABAAAAAA==.Boruvka:BAAALAAECgIIAgAAAA==.Bosshogg:BAAALAAECgYICgAAAA==.Bouchard:BAAALAAECgUICAAAAA==.',Br='Braney:BAAALAADCggICAAAAA==.Broceliande:BAAALAAECgQIBAAAAA==.Brom:BAAALAAECgEIAQAAAA==.',Bu='Burin:BAAALAADCggIGAAAAA==.',By='Bynky:BAAALAAECgYIDgAAAA==.',Ca='Calyx:BAAALAADCgcIDwAAAA==.Calándra:BAAALAAECggIEgAAAA==.Capaletti:BAAALAAECgIIBAAAAA==.',Ce='Celedar:BAAALAADCgcIBwAAAA==.Cesr:BAAALAADCggIEAAAAA==.',Ch='Chilliam:BAAALAADCgEIAQAAAA==.Chiminglee:BAAALAADCggIDgAAAA==.Choppara:BAAALAADCggIDgAAAA==.Chrchlik:BAAALAADCggIEwAAAA==.',Ci='Cij:BAAALAADCgcIDAAAAA==.Cil:BAAALAADCgcIDAAAAA==.',Co='Coldkilla:BAAALAADCgcIFAAAAA==.',Cr='Crank:BAAALAADCggICAAAAA==.Cróuch:BAAALAADCgcIAwAAAA==.',Cy='Cyberpriest:BAAALAADCgYIBgAAAA==.',['Cí']='Cítywok:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Da='Dalieta:BAAALAADCggICAAAAA==.Dalton:BAAALAAECgcIDwAAAA==.Danaval:BAAALAAECgUICgAAAA==.Darcevoker:BAAALAAECgQIBgABLAAECggIGAAFAMIaAA==.Darkelftank:BAAALAAECgQIBgAAAA==.Darksoulz:BAAALAADCgYIBgAAAA==.Darryxx:BAAALAAECgIIAwAAAA==.',De='Dekra:BAAALAADCggIDwAAAA==.Delanos:BAAALAADCgEIAQABLAAECgEIAgABAAAAAA==.Demonetize:BAAALAAECgYICwAAAA==.Denim:BAAALAAECgQICAAAAA==.Denovox:BAAALAAECggIDgAAAA==.Dezie:BAAALAADCgQIBAAAAA==.',Di='Digestibull:BAAALAADCggICAAAAA==.Direnews:BAAALAAECgIIAgAAAA==.',Dj='Djerunish:BAAALAAECgEIAgAAAA==.',Dm='Dmaar:BAAALAAECgMIAwAAAA==.',Do='Dogthe:BAAALAADCgYICQABLAAECgcIHQAGAMAGAA==.Domagoj:BAAALAAECgYIEgAAAA==.Donalddrumpf:BAAALAADCggICAABLAAECggIDAABAAAAAA==.Dontroll:BAAALAAECgEIAQAAAA==.',Dr='Drbuzzard:BAAALAAECgMIBQAAAA==.Droddy:BAAALAADCggICAAAAA==.Drushift:BAAALAADCgQIAwAAAA==.',['Dá']='Dárc:BAABLAAECoEYAAQFAAgIwhqeJgBBAgAFAAcIkhyeJgBBAgAEAAMIqwxHOACTAAAHAAEIEA7HOAAzAAAAAA==.Dárcdruid:BAAALAAECgcICQABLAAECggIGAAFAMIaAA==.',['Dé']='Déstróyer:BAAALAAECgMIBAAAAA==.',Ed='Edneiy:BAAALAAECgQIBAAAAA==.',El='Elfidor:BAAALAADCgQIBAAAAA==.Ellanic:BAAALAADCgcIBwAAAA==.Elwe:BAAALAADCgcICgAAAA==.',Em='Emì:BAAALAAECgMIBgABLAAECgYIEgABAAAAAA==.',En='Enchant:BAAALAADCgUIBQAAAA==.Enrage:BAAALAAECgMIAwAAAA==.',Ep='Epivitorina:BAAALAAECgYICwAAAA==.',Et='Etcid:BAAALAAECgYICwAAAA==.Ethaslayer:BAAALAAECgUICAAAAA==.',Ev='Evasor:BAAALAAECgMIBAAAAA==.',Fa='Falicia:BAAALAADCgIIAgAAAA==.',Fe='Fensi:BAAALAAECgIIAgAAAA==.',Fi='Fingerz:BAAALAADCgcIFQABLAAECgEIAQABAAAAAA==.',Fl='Flaga:BAAALAADCgcIBwAAAA==.Florensa:BAAALAADCgYIBgAAAA==.',Fr='Frank:BAAALAAECgYICgAAAA==.Freefellatio:BAABLAAECoEVAAIIAAgIfQuUSwCtAQAIAAgIfQuUSwCtAQAAAA==.Frisbeez:BAAALAAECgYIDwAAAA==.Friskstraza:BAAALAAECgYICAAAAA==.Frostgump:BAAALAAECgIIAgAAAA==.Frozenedge:BAAALAADCgcICAAAAA==.',Fu='Funder:BAAALAADCgcIBwAAAA==.',Ga='Gabriell:BAAALAAECgcICgAAAA==.',Ge='Ge:BAAALAAECgUIDAAAAA==.',Gi='Ging:BAAALAAECgcIBwAAAA==.',Gl='Gloriez:BAAALAADCgQIBAAAAA==.',Gn='Gnomo:BAAALAADCgYIDAAAAA==.',Go='Goarsh:BAAALAAECgYICQAAAA==.Goldiefuzz:BAAALAAECgYIDgAAAA==.Gorgots:BAAALAAECgcIEAAAAA==.',Gr='Greetmyfeet:BAAALAAECgIIAgAAAA==.Grimshank:BAAALAADCgIIAgAAAA==.Grimwall:BAAALAAECgQIBAAAAA==.Groawn:BAAALAAECgYICQAAAA==.',Gu='Gullibull:BAAALAAECgYICAABLAAECggIDAABAAAAAA==.Gurkeren:BAAALAAECgMIBwAAAA==.',He='Heda:BAAALAAECgYICgAAAA==.Heihach:BAAALAAECgYICAAAAA==.Hellscyte:BAAALAAECgUICgAAAA==.Hellthrass:BAAALAADCgYIBgAAAA==.Herbaliser:BAAALAAECgIIAwAAAA==.',Hi='Hiccupotomas:BAAALAAECgIIAgABLAAECggIDAABAAAAAA==.Hiccupotomoo:BAAALAADCggICAABLAAECggIDAABAAAAAA==.Hiccupotomos:BAAALAAECggIAgABLAAECggIDAABAAAAAA==.Hiccupotomus:BAAALAAECggIDAAAAA==.',Ho='Holyfans:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Holyhaste:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Horible:BAAALAAECgYIEgAAAA==.',Hy='Hyorel:BAAALAAECgMIAwAAAA==.',['Hó']='Hóoxy:BAAALAAECgIIAgAAAA==.',Il='Ilcka:BAAALAADCggIDwAAAA==.Ilkdrakkar:BAAALAADCgIIAgAAAA==.',In='Infestados:BAAALAAECgYICgAAAA==.',It='Itismik:BAABLAAECoEVAAMJAAcIByBfEQByAgAJAAcIByBfEQByAgAKAAQIGRL0ZwDdAAAAAA==.',Ja='Jahbinks:BAAALAAECggIEwAAAA==.Jawj:BAAALAAECgYICgAAAA==.Jaxxz:BAAALAAECgYICwAAAA==.',Je='Jellik:BAAALAAECgQIBgAAAA==.',Jo='Johnno:BAAALAAECgUICQAAAA==.Josin:BAAALAAECgcIDAAAAA==.',Jr='Jró:BAAALAAECgMIBQAAAA==.',Ju='Junbo:BAABLAAECoEbAAILAAgIiCA4DQD4AgALAAgIiCA4DQD4AgAAAA==.',Ka='Kaeabaen:BAAALAADCggICAAAAA==.Karo:BAAALAAECgUIBwAAAA==.Karon:BAAALAAECgYIEgAAAA==.Katykat:BAAALAAECgMIAwAAAA==.',Ke='Keata:BAAALAAECgEIAgAAAA==.Keddien:BAAALAADCgcIBwAAAA==.Kera:BAAALAADCgcIBwAAAA==.',Kh='Khadalia:BAAALAAECggIEwAAAA==.Khazadom:BAAALAAECgYIEQAAAA==.',Ki='Kitune:BAAALAADCgYICAAAAA==.',Kk='Kkenneth:BAAALAADCgMIAwAAAA==.',Kl='Kleopatra:BAAALAADCgcIEwABLAAECgIIAgABAAAAAA==.',Kn='Knetter:BAAALAADCgEIAQAAAA==.',Ko='Korïna:BAAALAAECggICQAAAA==.',Ku='Kuzadrion:BAAALAAECgYIEgAAAA==.',Ky='Kyanu:BAAALAADCggICAAAAA==.Kylossus:BAAALAADCgcIBwAAAA==.',La='Laesis:BAAALAADCgUIBQAAAA==.Lanks:BAAALAADCggIEAAAAA==.Lavoe:BAAALAAECgYICgAAAA==.Layria:BAAALAAECgQIBAAAAA==.',Le='Lebrann:BAAALAADCgYIBgABLAAECggIGAACANcfAA==.Lecramm:BAAALAAECgYICQAAAA==.Legendhero:BAAALAADCgcIFQAAAA==.Legendheroic:BAAALAADCgcIBwAAAA==.Legendslash:BAAALAADCgIIAQAAAA==.Leviath:BAAALAADCgcIBwAAAA==.',Li='Liaserock:BAAALAADCggIEwAAAA==.Lightswrath:BAAALAADCgUIBQAAAA==.Lilianna:BAAALAAECgYIDgAAAA==.Lillemor:BAAALAAECgEIAgAAAA==.Livranca:BAAALAADCgMIAwAAAA==.',Lu='Luk:BAAALAADCgcIAwAAAA==.Luxerry:BAAALAAECgYIDgAAAA==.',Ma='Maladi:BAABLAAECoEaAAIMAAcINhlfGwAeAgAMAAcINhlfGwAeAgAAAA==.Malkus:BAAALAAECgYICwAAAA==.Malmi:BAAALAAECgIIAgAAAA==.Mamboo:BAABLAAECoEZAAIJAAgIQByqEgBjAgAJAAgIQByqEgBjAgAAAA==.Mattex:BAAALAAECgUIBQAAAA==.Mazradon:BAAALAADCggIDQAAAA==.',Me='Megnito:BAAALAAECgMIAwAAAA==.Melbo:BAAALAAECgIIAwAAAA==.Melindya:BAABLAAECoEcAAINAAgISxYqDgBCAgANAAgISxYqDgBCAgAAAA==.Metamarv:BAAALAADCggIDgAAAA==.',Mi='Mikkiim:BAAALAAECgEIAQABLAAECgcIFQAJAAcgAA==.Misbah:BAAALAAECgcIDwAAAA==.Mizzlillý:BAAALAADCgMIAwAAAA==.',Mo='Monkd:BAAALAAECgIIAgAAAA==.Moonscream:BAAALAADCgIIAgAAAA==.Morrigu:BAAALAAECgEIAgAAAA==.',My='Mygon:BAAALAADCggICwAAAA==.',['Mï']='Mïke:BAAALAADCgcICgAAAA==.',Na='Naamverloren:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.Narasimha:BAAALAAECgQIBAAAAA==.',Ne='Neflin:BAAALAADCgcIBwAAAA==.Neth:BAAALAAECgYICgAAAA==.',Ni='Nialla:BAAALAADCgQIBAAAAA==.',Nu='Nutann:BAAALAADCgcIBwAAAA==.',['Nâ']='Nâko:BAAALAAECgQIBAAAAA==.',Om='Omun:BAAALAAECgEIAgAAAA==.',Op='Ophiuchus:BAAALAADCgEIAQAAAA==.Opicman:BAAALAAECgIIAgAAAA==.',Or='Oromé:BAAALAADCggICAAAAA==.Orpheas:BAAALAAECgIIAgAAAA==.Orphide:BAAALAAECgQIBAAAAA==.',Os='Osiriss:BAAALAADCgcIBwAAAA==.',Pa='Paaldanser:BAAALAAECgYIBgAAAA==.Pallypoise:BAAALAAECgYIBgAAAA==.Palmi:BAAALAAECgEIAgAAAA==.Papauwtje:BAAALAADCggIGwAAAA==.Paradôx:BAAALAAECgMIBAAAAA==.Paígey:BAAALAAECgMIBAAAAA==.',Pe='Peakyy:BAAALAADCggICAAAAA==.Peetehegseth:BAAALAADCggICAAAAA==.Pepeke:BAAALAADCgcICwAAAA==.Perkamentus:BAAALAAECggIEwAAAA==.',Po='Potlach:BAAALAAECggIAgAAAA==.Powerwordpeg:BAAALAADCggICAAAAA==.',Pu='Purpledrag:BAAALAAECgMIAQAAAA==.Puumala:BAAALAAECgIIAgAAAA==.',['Pâ']='Pâpauw:BAAALAAECgEIAQAAAA==.',Ra='Rackiechan:BAAALAAECgYICQAAAA==.',Rh='Rhyliana:BAAALAADCgYIBgAAAA==.',Ri='Rimanda:BAAALAAECggICAAAAA==.Rizumu:BAAALAADCgEIAQAAAA==.',Ro='Roawn:BAAALAAECgYIBgABLAAECgYICQABAAAAAA==.Robopants:BAAALAADCggIEAAAAA==.Rohirrim:BAAALAADCgUIBQAAAA==.Rolander:BAAALAAECgMIBgAAAA==.',Ry='Ryder:BAAALAADCgUIBQAAAA==.',Sa='Saafia:BAAALAADCgYIBgAAAA==.Sanctalupa:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Sarûman:BAAALAAECgEIAQAAAA==.',Sc='Scoobbs:BAAALAAECgYIEgAAAA==.Scrobo:BAAALAAECgcIDQAAAA==.Scrótotem:BAAALAADCggIEAAAAA==.',Se='Selfmade:BAAALAADCgYIBgAAAA==.Servall:BAAALAADCgQIBAAAAA==.',Sh='Shamdru:BAAALAAECgEIAgAAAA==.Shamlis:BAAALAADCggIDQAAAA==.Shandrys:BAAALAADCgIIAgAAAA==.Shelloqnatar:BAAALAADCggICAABLAAECgYIEgABAAAAAA==.Shelloqnator:BAAALAAECgYIEgAAAA==.Shinimegami:BAAALAADCgIIAgAAAA==.Shockingblue:BAAALAAECgMIAwAAAA==.Shorbi:BAABLAAECoEVAAIOAAcILATzSAAlAQAOAAcILATzSAAlAQAAAA==.Shurivie:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.',Sk='Skjold:BAAALAAECgYIDAABLAAECggIAgABAAAAAA==.Skárin:BAABLAAECoEWAAIMAAgIuRETHQAPAgAMAAgIuRETHQAPAgAAAA==.',Sn='Snifflebron:BAACLAAFFIEQAAIOAAYIPiBDAAB7AgAOAAYIPiBDAAB7AgAsAAQKgSAAAg4ACAhLJKADAFMDAA4ACAhLJKADAFMDAAAA.Snuppa:BAAALAADCgYIBgAAAA==.Snów:BAAALAADCgYIBgAAAA==.',So='Sockpuppet:BAAALAAECgUIBgAAAA==.Solyne:BAAALAADCgIIAgAAAA==.',Sp='Spawny:BAAALAAECgQICAAAAA==.Spírìt:BAAALAAECgMIAwAAAA==.',St='Staatsvijand:BAAALAADCggIFgAAAA==.Starbugone:BAAALAADCgQIBQAAAA==.Stormen:BAEALAAECgYICAAAAA==.Stormkin:BAAALAAECgYICQAAAA==.',Su='Sunforged:BAAALAADCgcIBwAAAA==.',['Sá']='Sámán:BAAALAADCggIDwAAAA==.',['Sé']='Séntox:BAAALAAECgcIEAAAAA==.',Ta='Taagey:BAAALAADCgMIAwAAAA==.Tailung:BAAALAAECgYIBgABLAAECgYICAABAAAAAA==.Taschu:BAAALAADCgcICQAAAA==.Tawaress:BAAALAAECgQIBAAAAA==.',Te='Tehaanu:BAAALAAECgYICgAAAA==.Teslata:BAAALAADCgYICwAAAA==.',Th='Thaeran:BAAALAADCggICAAAAA==.Thedarkening:BAAALAADCgcIBwAAAA==.Theras:BAAALAAECgYIEgAAAA==.Thomas:BAAALAAECgYIEgAAAA==.Thunderfox:BAAALAADCgcIBwAAAA==.Thunderholy:BAAALAADCgUIBwAAAA==.Thyrania:BAAALAAECgYICgAAAA==.',Ti='Tijnio:BAAALAADCgUIBQAAAA==.Tikla:BAAALAAECgYICQAAAA==.Tiksia:BAAALAAECgYIDgAAAA==.Tiza:BAABLAAECoEUAAIPAAgIGxSVHgAKAgAPAAgIGxSVHgAKAgAAAA==.',Tm='Tmy:BAAALAAECgMIAwAAAA==.',To='Tolkys:BAAALAAECgYICgAAAA==.Tonedeaf:BAAALAAECgYIEQAAAA==.Toomer:BAAALAAECgUICgAAAA==.Tormageddon:BAAALAAECgYICgAAAA==.Tormented:BAAALAAECgIIAgABLAAECggIAgABAAAAAA==.',Tr='Trolbo:BAAALAAECgYIBgAAAA==.',Tw='Twinkel:BAAALAAECgIIAQAAAA==.',Ty='Tyriia:BAAALAADCgQIBQAAAA==.',['Tï']='Tïch:BAAALAADCgcIBwAAAA==.',Ui='Uinen:BAAALAAECgYIDgAAAA==.',Un='Undarath:BAAALAAECgYICgAAAA==.',Va='Valgil:BAAALAAECgQIBAAAAA==.Valkyrio:BAAALAAECgEIAQAAAA==.Vanfelswing:BAAALAAECgIIAgAAAA==.Varda:BAAALAAECgEIAQAAAA==.',Ve='Veritasi:BAAALAAECgYIDAAAAA==.',Vi='Villblomst:BAAALAADCgcIBwAAAA==.',Wa='Wall:BAAALAADCggIDgABLAAECggIAgABAAAAAA==.Wallié:BAAALAADCgEIAQAAAA==.',We='Wendie:BAAALAADCgUICAAAAA==.',Wh='Whatlock:BAABLAAECoEdAAMGAAcIwAYuTQA9AQAGAAcIwAYuTQA9AQAQAAEIlwVLbAAjAAAAAA==.',Wi='Wiiroy:BAAALAAECgYICgAAAA==.Winchesteruk:BAAALAAECgUIDAAAAA==.Windspearr:BAAALAADCgIIAgAAAA==.',Wo='Woc:BAAALAAECgEIAQAAAA==.Woudloper:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Wt='Wtbhaste:BAAALAAECgYIDgAAAA==.',Xi='Xiz:BAAALAADCggICAAAAA==.',Xt='Xtál:BAAALAADCggICQAAAA==.',Ye='Yemy:BAAALAAECgQIBAAAAA==.',Yu='Yuto:BAAALAAECgMIBwAAAA==.',['Yö']='Yönritari:BAAALAAECgcIDAAAAA==.',Za='Zakizaurus:BAAALAAECgYIDgAAAA==.Zanekun:BAAALAADCggICAAAAA==.Zanithia:BAAALAADCgYIBgAAAA==.',Ze='Zerveres:BAAALAADCggIEAAAAA==.',Zh='Zhania:BAAALAADCgcIDAAAAA==.',Zu='Zucks:BAAALAADCgcIBwAAAA==.',Zy='Zytor:BAAALAAECgYICQAAAA==.',['Zá']='Zánkou:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end