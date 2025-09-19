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
 local lookup = {'Shaman-Restoration','Shaman-Elemental','Unknown-Unknown','Hunter-BeastMastery','Mage-Frost','Warrior-Fury','Druid-Balance','Druid-Restoration','Evoker-Devastation','Evoker-Augmentation','Druid-Feral','Paladin-Retribution','Hunter-Survival','Hunter-Marksmanship','Priest-Holy',}; local provider = {region='EU',realm='Eitrigg',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adalarià:BAAALAAECgYICAAAAA==.',Ae='Aegis:BAAALAAECgEIAgAAAA==.',Ag='Agreûs:BAAALAADCgcIDwAAAA==.',Al='Alectinib:BAAALAAECgEIAgAAAA==.Aleocrast:BAAALAAECgEIAQAAAA==.Alexm:BAAALAAECgMIBAAAAA==.Alitia:BAAALAADCgMIAwAAAA==.Almäh:BAABLAAECoEaAAMBAAgIRiKHBADcAgABAAgIRiKHBADcAgACAAcIPxulEwAzAgAAAA==.Alzoran:BAAALAAECgMIAwAAAA==.Aléria:BAAALAAECgEIAQAAAA==.',An='Angalis:BAAALAAECgEIAgAAAA==.',Ar='Arima:BAAALAADCggICAAAAA==.Arimas:BAAALAAECgEIAQAAAA==.Armablood:BAAALAADCggIEAAAAA==.Arrok:BAAALAADCggICAAAAA==.Arthias:BAAALAAECgUICQAAAA==.',As='Asuhna:BAAALAADCgcIBwAAAA==.',At='Atalea:BAAALAAECgMIBgAAAA==.Atrelya:BAAALAAECgUICAAAAA==.',Av='Avra:BAAALAADCgcIBwAAAA==.Avryl:BAAALAAECgQIBQAAAA==.',Az='Azral:BAAALAADCgEIAQAAAA==.Azôg:BAAALAAECgEIAQAAAA==.',['Aé']='Aégis:BAAALAADCggICAABLAAECgEIAgADAAAAAA==.',['Aë']='Aëpyx:BAAALAAECgQIBwAAAA==.',['Añ']='Añi:BAAALAAECgIIAgAAAA==.',['Aü']='Aürane:BAAALAADCgcICQAAAA==.',Ba='Badoy:BAAALAADCggICAAAAA==.Baeliggs:BAAALAADCggICQAAAA==.Bahamumuth:BAAALAADCgMIAwABLAAECgMIAwADAAAAAA==.Bahamuth:BAAALAAECgMIAwAAAA==.Baiyta:BAAALAAECgYIBgAAAA==.Bakadash:BAAALAAECggIEwAAAA==.Balou:BAAALAADCgcIBwAAAA==.Baltazarette:BAAALAADCggIDgAAAA==.Bananette:BAAALAADCgEIAQAAAA==.Basolipala:BAAALAADCggICAAAAA==.',Be='Beaumarteau:BAAALAADCgcIEQAAAA==.Beäuregard:BAAALAADCgQIBAAAAA==.',Bi='Bigheart:BAAALAADCgYICAAAAA==.Birnäm:BAAALAADCgcIBwAAAA==.Biscköotte:BAAALAAECgMIBgAAAA==.Biînd:BAAALAAECggIBAAAAA==.',Bl='Bllou:BAAALAAECgMIBQAAAA==.',Bo='Boigi:BAAALAAECgMIBAAAAA==.Boniandclyde:BAAALAADCgcIFAAAAA==.Borîs:BAAALAAECgUIBAAAAA==.',Br='Brackcham:BAAALAAECgcIEwAAAA==.Brackevok:BAAALAADCggICAABLAAECgcIEwADAAAAAA==.Brackhunt:BAAALAAECgMIAwABLAAECgcIEwADAAAAAA==.Brackprêtre:BAAALAAECgYIBgABLAAECgcIEwADAAAAAA==.Brôxigar:BAAALAADCgcIEAAAAA==.',Ca='Cajôu:BAAALAAECgYIDQAAAA==.Calcalou:BAAALAAECgYICQAAAA==.Calinea:BAAALAADCgUIAQAAAA==.Carleenne:BAAALAAECgEIAQAAAA==.Carmelita:BAAALAADCggICAAAAA==.',Ce='Celsor:BAAALAADCgcIBwAAAA==.Centrifuge:BAAALAADCgUIBQAAAA==.',Ch='Chamalolaï:BAAALAAECgEIAQAAAA==.Chamanamanah:BAAALAAECgMIBAAAAA==.Chamomille:BAAALAADCggIDwAAAA==.Choukrette:BAAALAADCggIFAABLAAECgUIAwADAAAAAA==.',Ci='Cinedelle:BAAALAADCggIFgAAAA==.',Cl='Cliff:BAAALAAECgMIAwAAAA==.',Co='Coeos:BAABLAAFFIEFAAIEAAMIqiHlAAA8AQAEAAMIqiHlAAA8AQAAAA==.Corder:BAAALAADCgcIBwAAAA==.',Cr='Crapulitos:BAAALAAECgMIBQAAAA==.Crhome:BAAALAADCgYIBAAAAA==.Crossby:BAAALAADCgQIBAAAAA==.Crowstorm:BAAALAADCggICAAAAA==.Crùsi:BAAALAADCgYICwAAAA==.',Cy='Cybèlia:BAAALAAECgYICgAAAA==.',['Cé']='Céhunskandal:BAAALAAECgMIBQAAAA==.',['Cö']='Cörazon:BAAALAAECgEIAQAAAA==.',Da='Daante:BAAALAADCggIDQAAAA==.Daemonstorm:BAAALAAECgYICAAAAA==.Dardarph:BAAALAADCggIEgAAAA==.Darkats:BAAALAAECgMIBQAAAA==.Darkblod:BAAALAADCgYIBgAAAA==.Darkmør:BAAALAAECgUICAAAAA==.Darkwraith:BAAALAADCgcIDQAAAA==.Dastru:BAAALAADCggICAAAAA==.',De='Deaktàrion:BAAALAAECgYICgABLAAFFAIIBAADAAAAAA==.Deepbloom:BAAALAAECgMIBQAAAA==.Deflora:BAAALAAECgcIDgAAAA==.Dexforitas:BAAALAAECgQIBwAAAA==.',Di='Didormu:BAAALAAECgYICAAAAA==.',Do='Donald:BAAALAAECgYICQAAAA==.Dortar:BAACLAAFFIEFAAIFAAMI/xOgAAACAQAFAAMI/xOgAAACAQAsAAQKgRcAAgUACAhHIsACAAwDAAUACAhHIsACAAwDAAAA.Doum:BAAALAADCgcIBwAAAA==.',Dr='Dractynay:BAAALAAECgMIAwAAAA==.Drakatrey:BAAALAADCggIDwAAAA==.Drakinchu:BAAALAADCgcIBwABLAAECgUICAADAAAAAA==.Drakkär:BAAALAAECgUICAAAAA==.Dravën:BAAALAAECggIBgAAAA==.Drift:BAAALAAECgIIAgAAAA==.',['Dé']='Démonelle:BAAALAADCggIDgABLAAECgMIBAADAAAAAA==.',Ed='Edorph:BAAALAADCgEIAQAAAA==.',El='Elfury:BAAALAADCggICAAAAA==.Elphi:BAAALAADCggIFAAAAA==.Elyndraë:BAAALAAECgMIBgAAAA==.',Eo='Eoin:BAAALAADCggIFQAAAA==.Eomen:BAAALAAECgcIDAAAAA==.',Er='Eranoth:BAAALAAECgYICQABLAAECggIFAAGAK8iAA==.',Es='Esrea:BAAALAADCggIBgAAAA==.Estawn:BAAALAAECgEIAgAAAA==.',['Eï']='Eïlkas:BAAALAAECgMIBAAAAA==.',Fa='Farella:BAAALAADCggICAAAAA==.Fatalys:BAAALAADCggIFQAAAA==.Fatrog:BAAALAAFFAIIAgAAAA==.',Fe='Felingel:BAAALAADCggICAAAAA==.Fellem:BAAALAADCgcIDgAAAA==.Feur:BAAALAAECgQIBwAAAA==.',Fi='Firien:BAAALAAECgMIAwAAAA==.',Fo='Forgelumière:BAAALAADCgIIAgAAAA==.Foubre:BAAALAADCgYIBgAAAA==.',Fr='Fredo:BAABLAAECoEVAAMHAAgIECJ7BAAUAwAHAAgIECJ7BAAUAwAIAAMIfBdlQgC1AAAAAA==.',Ga='Galaonar:BAAALAADCgYICAAAAA==.Galinette:BAAALAAECgIIAwAAAA==.Ganondorfe:BAAALAADCggICAAAAA==.Gaviscon:BAAALAAFFAEIAQAAAQ==.',Ge='Gegett:BAABLAAECoEXAAIBAAYIDRu5JgCoAQABAAYIDRu5JgCoAQAAAA==.',Gr='Graelt:BAAALAADCgIIAgAAAA==.Gregnêss:BAAALAAECgcIDAAAAA==.',Gu='Guldok:BAAALAADCggICAAAAA==.',Gy='Gymkhana:BAAALAAECgYICQAAAA==.',['Gä']='Gäbriëll:BAAALAADCggICQAAAA==.',Ha='Hanâe:BAAALAAECgMIAwAAAA==.Harloc:BAAALAAECgEIAQAAAA==.Harmonie:BAAALAAECgEIAQAAAA==.Haya:BAAALAADCgMIAwAAAA==.',He='Heihashi:BAAALAAECgQIBQAAAA==.Helyoss:BAAALAAECgEIAgAAAA==.Hentaïs:BAAALAAECgEIAQAAAA==.',Hi='Highvory:BAEALAAECgYIDgAAAA==.Hinami:BAAALAADCgYICAAAAA==.Hiroshige:BAAALAADCgYIBwABLAAECgIIAgADAAAAAA==.',Ho='Holight:BAAALAAECgcIBwAAAA==.Howbeesare:BAAALAADCgYIBgAAAA==.',Hy='Hygiea:BAAALAAECgMIBgAAAA==.',['Hû']='Hûrïel:BAAALAADCgEIAQAAAA==.',If='Ifreann:BAAALAAECgQIBQAAAA==.',In='Injust:BAAALAAECgMIBAAAAA==.',It='Itikastrophe:BAAALAAECgcICgAAAA==.',Iz='Izhandre:BAAALAADCgcIEAAAAA==.',Ja='Jamoneur:BAACLAAFFIEIAAMJAAQI8B09AQBrAQAJAAQIEBk9AQBrAQAKAAEIthqdAQBTAAAsAAQKgRgAAwkACAhpJbcAAHEDAAkACAhpJbcAAHEDAAoABAinIRMEAFoBAAAA.',Je='Jepp:BAABLAAECoEUAAIGAAgIryI3BAA1AwAGAAgIryI3BAA1AwAAAA==.Jessicat:BAABLAAECoEXAAILAAgIfR8hAgD3AgALAAgIfR8hAgD3AgAAAA==.',Ji='Jinnette:BAAALAADCgcIEgAAAA==.',Ju='Justicelight:BAAALAADCgcIBwAAAA==.Justmétéor:BAAALAAECgMIAwAAAA==.',Ka='Kamadark:BAAALAADCggICAAAAA==.Karz:BAACLAAFFIEFAAIMAAMIdyS+AABIAQAMAAMIdyS+AABIAQAsAAQKgRcAAgwACAhGJTMCAGgDAAwACAhGJTMCAGgDAAAA.Katsù:BAAALAADCgcIBwAAAA==.',Ke='Kek:BAABLAAECoEWAAMNAAgIwiKVAAAeAwANAAgIwiKVAAAeAwAOAAEI4iHPUABGAAAAAA==.Keliz:BAAALAADCggICAAAAA==.Kenpachi:BAAALAADCgcICAAAAA==.Kensero:BAAALAAECgYIDAAAAA==.',Ki='Kily:BAAALAADCggIDwAAAA==.Kinchuka:BAAALAAECgUICAAAAA==.Kisscools:BAAALAAECgYICQAAAA==.',Ko='Koddy:BAAALAAECgMIBQAAAA==.Kolossus:BAAALAADCgQIBAAAAA==.',Kr='Kristhal:BAAALAAECgEIAQAAAA==.Kromka:BAAALAADCgYIBgAAAA==.Krøkrø:BAAALAAECgMIAwAAAA==.',Ku='Kumaavion:BAAALAAECgIIAQAAAA==.Kumasake:BAAALAAECgEIAQABLAAECgUICQADAAAAAA==.',Ky='Kyansâ:BAAALAAECgMIBQAAAA==.Kyôko:BAAALAAECgMIBQAAAA==.',['Kä']='Kära:BAAALAAECgQIBwAAAA==.',['Kï']='Kïpïk:BAAALAADCgUIBQAAAA==.',La='Lapinator:BAAALAAECgEIAgAAAA==.Lapisugar:BAAALAADCggICQABLAAECgEIAgADAAAAAA==.Laynïe:BAAALAADCgYIBgAAAA==.',Le='Legencia:BAAALAADCgQIBAAAAA==.Legencÿ:BAAALAADCgcIBwAAAA==.Leviator:BAAALAAECgYIBgAAAA==.',Lo='Lorassor:BAAALAADCggIEgAAAA==.Louidefunnel:BAAALAADCgcICQAAAA==.',Lu='Luender:BAAALAADCgYICwAAAA==.Lutila:BAAALAAECgUICAAAAA==.',Ly='Lyaran:BAAALAAECgIIAgAAAA==.',['Lâ']='Lânaa:BAAALAAECgQIBwAAAA==.',['Lï']='Lïfÿa:BAAALAADCgYICwAAAA==.',['Lû']='Lûbite:BAAALAADCggICAAAAA==.',['Lü']='Lübu:BAAALAAECgMIBQAAAA==.Lücette:BAABLAAECoEXAAMEAAgI+CDoCADgAgAEAAgI+CDoCADgAgAOAAQIiRSaMgDzAAAAAA==.',Ma='Magestral:BAAALAAECgMIBQAAAA==.Magixdh:BAAALAADCgcIBwAAAA==.Magixo:BAAALAADCgcIBwAAAA==.Malivaï:BAAALAADCggIFQAAAA==.Mangemonheal:BAAALAAECgQIBAAAAA==.Massanthrax:BAAALAAECgMIBQAAAA==.Maédhros:BAAALAAECgUICAAAAA==.',Me='Meka:BAAALAADCggIFwAAAA==.Mekasha:BAAALAADCggICQAAAA==.Meo:BAAALAAECgYICgAAAA==.',Mi='Minnain:BAAALAADCgcICAAAAA==.Mirage:BAAALAADCgMIAwAAAA==.Mistrall:BAAALAADCgcIBwAAAA==.Mitsurii:BAAALAADCgMIAwAAAA==.',Mo='Morgarat:BAAALAADCggIDwABLAAECgQIBwADAAAAAA==.Morlaf:BAAALAAECgUIAwAAAA==.Mortibus:BAAALAAECgMIBQAAAA==.',Mu='Mualph:BAAALAAECgYICgAAAA==.',['Mè']='Mèli:BAAALAADCgcIBwAAAA==.',['Mé']='Mélomoine:BAAALAADCgcIAwABLAAECgMIBAADAAAAAA==.Méphala:BAAALAAECgQIBAAAAA==.',Na='Narma:BAAALAAECgMIBAAAAA==.Naugrim:BAAALAADCgYIEAAAAA==.Naxxars:BAAALAADCggIEAAAAQ==.',Ne='Nephertiti:BAAALAADCggIDgAAAA==.Nerissa:BAAALAADCgEIAQAAAA==.Netzach:BAAALAADCgcIBwAAAA==.Neyldari:BAAALAAECgQIBwAAAA==.',Ni='Ninjini:BAAALAADCggIFQAAAA==.Ninjutsu:BAAALAADCgcIBwAAAA==.',No='Noahdh:BAAALAAECgMIAwAAAA==.',Nx='Nxia:BAAALAADCgMIAwAAAA==.',Oi='Oignion:BAAALAAECgEIAQAAAA==.',Ok='Oklaf:BAAALAADCgQIBAABLAAECgUICAADAAAAAA==.',On='Onidark:BAAALAADCggIEAAAAA==.',Os='Oskur:BAAALAAECgEIAgAAAA==.',Ou='Ouftih:BAAALAAECgYICAAAAA==.',Ox='Oxye:BAAALAAECgcIEwAAAA==.Oxymore:BAAALAAECgYIDQAAAA==.',Pa='Paladinas:BAAALAAECgMIBwAAAA==.Palady:BAAALAAECgUIBgAAAA==.Palaga:BAAALAAECgMIAwAAAA==.Palapilou:BAAALAAECgMIBQAAAA==.Pandaerion:BAAALAADCgcIBQABLAAFFAIIBAADAAAAAA==.',Pe='Pelford:BAAALAADCggIBwAAAA==.Pelzine:BAAALAAECggIEAAAAA==.Petitbou:BAAALAADCggICwAAAA==.',Pl='Ploukine:BAAALAADCgcIBwAAAA==.',Po='Polterprïest:BAAALAAECgEIAQABLAAECgYICgADAAAAAA==.',Pr='Prat:BAAALAADCgcIBwABLAAECgYIEgADAAAAAA==.Prouty:BAAALAAECgYIEgAAAA==.Prïma:BAACLAAFFIEFAAIPAAMIAhFvAwADAQAPAAMIAhFvAwADAQAsAAQKgRcAAg8ACAjgHGUKAJUCAA8ACAjgHGUKAJUCAAAA.',Ps='Psiichokille:BAAALAAECgIIAgAAAA==.',['Pø']='Pøupette:BAAALAAECggIDgAAAA==.',['Pù']='Pùnîsher:BAAALAAECgEIAQAAAA==.',Ra='Radhruin:BAAALAADCgcIBwAAAA==.Raelya:BAAALAADCggICAAAAA==.Rafalmistral:BAAALAAECgIIBQAAAA==.Ragdoll:BAAALAAECgYICAAAAA==.Ragnarøs:BAAALAADCggIBQAAAA==.Ramablock:BAAALAADCgcIBwAAAA==.Raphatytan:BAAALAADCgUIBQAAAA==.Rayton:BAAALAADCgYIBgAAAA==.',Re='Rebelöotte:BAAALAADCgMIAwABLAAECgMIBgADAAAAAA==.Rehn:BAAALAAECgcIDAAAAA==.',Rh='Rhast:BAAALAAECgYIDAAAAA==.',Ro='Rockhette:BAAALAADCggICAAAAA==.Rommy:BAAALAADCggIEwAAAA==.Rotideboeuf:BAAALAAECgQIBQAAAA==.',Sa='San:BAAALAADCggIFgAAAA==.Sanvoix:BAAALAADCggIEwAAAA==.Saucedio:BAAALAAECgcIDQABLAAECggIFAAGAK8iAA==.Saïne:BAAALAAECgEIAgAAAA==.',Se='Seeker:BAAALAADCgcIDQAAAA==.Senturus:BAAALAADCggIEwAAAA==.',Sh='Shamaëll:BAAALAADCgYIBgAAAA==.Sheila:BAAALAAECgQIBgAAAA==.Shimura:BAAALAADCggIGAAAAA==.',Si='Siobhan:BAAALAADCggIFQAAAA==.',Sk='Skank:BAAALAAECgYICQAAAA==.',So='Soap:BAAALAAECgIIAgAAAA==.Sorme:BAAALAADCggIDwAAAA==.',Sp='Speedmäster:BAAALAADCggICAAAAA==.',St='Stronghold:BAAALAADCgcICAAAAA==.Stéarine:BAAALAAECgIIAgAAAA==.Størmrage:BAAALAADCgUIBQAAAA==.',Su='Sunjia:BAAALAADCgYIBgAAAA==.',Ta='Tagyrra:BAAALAADCgYIBgAAAA==.Talthara:BAAALAADCgcIDQAAAA==.Tarro:BAACLAAFFIEFAAICAAMIzCD1AQAnAQACAAMIzCD1AQAnAQAsAAQKgRYAAgIACAhSJDgDAEUDAAIACAhSJDgDAEUDAAAA.',Te='Teyi:BAAALAADCggICAAAAA==.',Th='Thaelynna:BAAALAADCgcIDQAAAA==.Tharÿa:BAAALAADCgYIBgAAAA==.Theonora:BAAALAAECgQIBwAAAA==.Thomas:BAAALAAECgcICgAAAA==.Thompson:BAAALAAECgMIBAAAAA==.Thorgir:BAAALAADCggIDAAAAA==.Thydearth:BAAALAAECgMIBAAAAA==.Thîef:BAAALAADCgcIDgAAAA==.',Ti='Tibgnd:BAAALAAECgEIAQAAAA==.',To='Tontonbil:BAAALAADCggIFQAAAA==.Tonyup:BAAALAADCgEIAQAAAA==.',Tr='Traïnos:BAAALAAECgEIAQAAAA==.',Ts='Tsûnadé:BAAALAAECgEIAQAAAA==.',['Tô']='Tôsu:BAAALAAECgIIAgAAAA==.',['Tÿ']='Tÿrïon:BAAALAADCgcICwAAAA==.',Ul='Ulhysse:BAAALAADCgcICQAAAA==.',Va='Valanka:BAAALAAECgcIDQAAAA==.Valorka:BAAALAADCgUIBwAAAA==.',Ve='Vexhalia:BAAALAAECgQICQAAAA==.',Vi='Victàrion:BAAALAAFFAIIBAAAAA==.Videoeuf:BAAALAADCgYIBgAAAA==.Vilfendrer:BAAALAAECgYICwAAAA==.Vinyato:BAAALAAECgEIAgAAAA==.Violinne:BAAALAAECgEIAgAAAA==.Virilia:BAAALAADCggICAAAAA==.',Vo='Vogador:BAAALAADCggICQAAAA==.Volkam:BAAALAAFFAIIBAAAAA==.',Wa='Walanardine:BAAALAAECgEIAgABLAAFFAIIAgADAAAAAA==.Warox:BAAALAADCgcIBwAAAA==.Warzzazate:BAAALAADCggICAAAAA==.Wazyi:BAAALAADCgcIBwAAAA==.',Wi='Wildstorm:BAAALAAECgIIBAAAAA==.',Wy='Wynnie:BAAALAAECgMIAwAAAA==.',Ya='Yaeshann:BAAALAAECgEIAQAAAA==.Yashak:BAAALAAECgYIBwAAAA==.',Yn='Ynkasable:BAAALAAECgYICQAAAA==.',Yq='Yquefue:BAAALAAECgQIBwAAAA==.',Yy='Yyohan:BAAALAAECgcIDwAAAA==.',Za='Zarein:BAAALAADCgEIAQAAAA==.',Ze='Zerstörer:BAAALAADCgcIBwAAAA==.',Zo='Zoukini:BAAALAADCgcIBwAAAA==.Zozio:BAAALAAECgIIAQAAAA==.',Zy='Zyradmonk:BAAALAAECgYICAAAAA==.',['Zé']='Zétheus:BAAALAAECgIIBAAAAA==.',['Ép']='Épectøz:BAAALAADCggIDAAAAA==.',['Îl']='Îlmarë:BAAALAAECgYIDAAAAA==.',['Ïl']='Ïllyanä:BAAALAAFFAEIAQAAAA==.',['Ðe']='Ðemønø:BAAALAADCggIFQAAAA==.',['ßë']='ßëlla:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end