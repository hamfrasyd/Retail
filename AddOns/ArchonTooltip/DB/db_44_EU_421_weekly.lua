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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Priest-Holy','Shaman-Elemental','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Priest-Shadow',}; local provider = {region='EU',realm='DieSilberneHand',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abendelf:BAAALAADCgcIDAABLAAECgQIBAABAAAAAA==.Abidana:BAAALAAECgMICgAAAA==.Abuduhn:BAAALAADCgcIBwAAAA==.',Af='Afra:BAAALAADCggICQAAAA==.',Ag='Agrotera:BAAALAAECgIIAgAAAA==.',Ah='Ahrline:BAAALAAECgEIAQAAAA==.',Ai='Ainzsama:BAAALAAECgYIDAAAAA==.Aiwa:BAAALAADCgYIBgAAAA==.',Aj='Ajden:BAAALAAECgEIAQAAAA==.',Al='Aldoron:BAAALAAECgcIEAAAAA==.Alysria:BAAALAAECgUIBwAAAA==.',An='Andamyon:BAAALAAECgMIBwAAAA==.Andella:BAAALAAECgYICwAAAA==.Anicaya:BAAALAAECggIDQAAAA==.Ann:BAAALAAECgEIAQAAAA==.',Ar='Argôrôk:BAAALAADCgcIBwAAAA==.Artos:BAAALAAECgYIBgAAAA==.',As='Ashesnay:BAAALAAECgYIBgAAAA==.Ashkatan:BAAALAAECgMIAwAAAA==.Asraêl:BAAALAADCgUIBQABLAADCggIEAABAAAAAA==.',At='Atomick:BAAALAAECgEIAQAAAA==.Atomreaktor:BAAALAAECgcIEAAAAA==.',Au='Aurorah:BAAALAADCggIDgAAAA==.',Av='Avaani:BAAALAAECgEIAQAAAA==.Avaborg:BAABLAAECoEUAAICAAgI/QsrGACHAQACAAgI/QsrGACHAQAAAA==.Avany:BAAALAAECgYIBgAAAA==.Avastor:BAAALAAECgMIBgAAAA==.Avathrea:BAAALAAECgQIBAAAAA==.',Az='Azante:BAAALAADCgEIAQAAAA==.Azôra:BAAALAAECgYIDAAAAA==.',Ba='Baldak:BAAALAAECgQIBgAAAA==.Balder:BAAALAAECgEIAQAAAA==.Banxor:BAAALAADCgYIBgAAAA==.',Be='Beasle:BAAALAADCggIDwAAAA==.Beliseth:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.Bengalosius:BAAALAAECgEIAgAAAA==.',Bi='Biatesh:BAAALAADCgIIAgABLAAFFAIIAgABAAAAAA==.Bisca:BAAALAAECgEIAQAAAA==.',Bl='Blaizé:BAAALAAECgcIDwAAAA==.Bluedragon:BAAALAADCgcIBwAAAA==.',Bo='Boghanik:BAAALAAECgYICgAAAA==.Bokarl:BAAALAAECgYIEgAAAA==.Boudika:BAAALAADCgMIAwAAAA==.',Br='Brokkoli:BAAALAADCgIIAQAAAA==.Brotbart:BAAALAAECgcIDAAAAA==.Bruebaeck:BAAALAAECgEIAQAAAA==.',['Bø']='Bøømér:BAAALAADCggICAAAAA==.',Ca='Caliosta:BAAALAAECgYICwAAAA==.Caltis:BAAALAADCggIFgAAAA==.Calypsó:BAAALAADCgYIDQAAAA==.Caorlas:BAAALAAECgEIAQAAAA==.',Ce='Cerio:BAAALAAECgcIDQAAAA==.',Ch='Chiella:BAAALAADCgcICQAAAA==.',Cl='Cloudy:BAAALAAECgYICwAAAA==.',Co='Coonie:BAAALAADCgcIDgAAAA==.Coraleen:BAAALAAECgcIEAAAAA==.',Cp='Cptmuhrica:BAAALAAECgQIBwAAAA==.',Cr='Crud:BAAALAADCggICQAAAA==.',Cy='Cylith:BAAALAADCggICAAAAA==.',['Câ']='Câstle:BAAALAADCgcICwAAAA==.',Da='Daedric:BAEALAAECgcIDQAAAA==.Daongel:BAAALAAECgIIAgAAAA==.Darklee:BAAALAAECgQIBAAAAA==.',De='Delia:BAAALAADCggIDwAAAA==.Delidiit:BAAALAAECgIIAgAAAA==.Desastro:BAAALAADCgcIBwAAAA==.Desi:BAAALAAECgMIAwAAAA==.Devola:BAAALAADCgMIAwAAAA==.Devoma:BAAALAAECgMIAwAAAA==.',Dh='Dholâs:BAAALAADCgEIAQAAAA==.',Di='Dice:BAEALAADCggICAABLAAECgcIDQABAAAAAA==.',Do='Dobbs:BAAALAAECggICQAAAA==.Doose:BAAALAAECgYIBgABLAAECgcIEAABAAAAAA==.Dorienne:BAAALAAECgQIBwAAAA==.Dormelosch:BAAALAADCggIEgAAAA==.',Dr='Draenice:BAAALAADCggIDgAAAA==.Dragonkai:BAAALAADCggICAAAAA==.Drapthor:BAAALAADCggICQAAAA==.Drathul:BAAALAAECgcIDgAAAA==.Dream:BAAALAAECgYICgAAAA==.Dryade:BAAALAAECgYICgAAAA==.',Du='Durula:BAAALAADCgUIBwAAAA==.',Dv='Dvolin:BAAALAAECgYIBgABLAAECgYICgABAAAAAA==.',['Dá']='Dáiya:BAAALAADCgEIAQABLAAECggIFwADAOAVAA==.',['Dä']='Dämonensepp:BAAALAADCgYIBgAAAA==.',['Dê']='Dêilm:BAAALAADCgUIBQAAAA==.',Ei='Eisenerwolf:BAAALAAECgMIAwAAAA==.',Ek='Ekko:BAAALAADCgYIBgAAAA==.',El='Elpis:BAAALAADCggIEAAAAA==.Elysya:BAAALAADCgcICgAAAA==.',En='Enjia:BAABLAAECoEVAAIEAAgIFBtEDACeAgAEAAgIFBtEDACeAgAAAA==.',Eo='Eosan:BAAALAAECgEIAQAAAA==.',Er='Erilar:BAAALAADCgcIBwAAAA==.',Es='Escadâ:BAAALAAECgQICAAAAA==.',Ex='Exorr:BAAALAAECgcIEAAAAA==.',Fa='Fahliell:BAAALAAECgEIAQAAAA==.Fanjuur:BAAALAAECgcIDgAAAA==.',Fe='Fear:BAABLAAECoEUAAIFAAgIQSQJBQA6AwAFAAgIQSQJBQA6AwAAAA==.Feelizitaz:BAAALAAECgYICwAAAA==.Fennecy:BAAALAADCggIFwAAAA==.Ferengar:BAAALAAECgYIDQAAAA==.',Fi='Fidala:BAAALAADCggIFgAAAA==.Fintia:BAAALAADCggIFQAAAA==.Fizzeline:BAAALAADCggIFwAAAA==.',Fl='Flodur:BAAALAADCgEIAQAAAA==.',Fr='Frathak:BAAALAADCggIEQABLAAECgMIBgABAAAAAA==.Frostfeuer:BAEALAAECgEIAQABLAAECgcIDQABAAAAAA==.',Fu='Furyos:BAAALAAECgcIEAAAAA==.',['Fá']='Fálah:BAAALAADCggIDQAAAA==.',Ga='Galathiêl:BAAALAAECgMIAwAAAA==.',Ge='Gemmy:BAAALAADCgYIDAAAAA==.',Gh='Ghostangel:BAAALAADCggIDwAAAA==.',Gi='Gimris:BAAALAADCgcIBwAAAA==.Ginkou:BAAALAADCgcIBwAAAA==.',Gl='Glaïmbar:BAAALAAECgIIAgAAAA==.',Gr='Gravejinx:BAAALAAECgQIBgAAAA==.Grimbearon:BAAALAAECgIIBAAAAA==.Grimthul:BAAALAADCggICAAAAA==.Grisù:BAAALAAECgQIBAAAAA==.Gromnur:BAAALAADCggIFgAAAA==.Growler:BAAALAAECgIIAgAAAA==.Gruldan:BAAALAADCggIGAAAAA==.',Gu='Guldumeek:BAAALAAECgMIAwAAAA==.',Gy='Gyngyn:BAAALAAECgMIAwAAAA==.Gywania:BAAALAADCggIFAAAAA==.',['Gá']='Gálbartorix:BAAALAAECgMIBwAAAA==.',['Gî']='Gîselle:BAAALAAECgEIAQAAAA==.',['Gü']='Gül:BAAALAADCggIEAAAAA==.',Ha='Habeera:BAAALAADCgcIDQAAAA==.Hammerfaust:BAAALAAECgEIAQAAAA==.Hanali:BAAALAAECgcIEAAAAA==.Hargrim:BAAALAAECgEIAQAAAA==.Hastati:BAAALAAECgMIAwAAAA==.',He='Held:BAAALAAECgMIBgAAAA==.Helvira:BAAALAADCgcIDAAAAA==.Hermadiaelys:BAAALAADCggIFgAAAA==.',Ho='Hornschi:BAAALAAECgIIAQAAAA==.',Hu='Hukdok:BAAALAAECgcIEAAAAA==.',['Hê']='Hêcate:BAAALAADCggIFgAAAA==.',['Hø']='Høpè:BAAALAAECgYIEgAAAA==.',Ic='Icyvenom:BAAALAAECgQIBgAAAA==.',Id='Ideala:BAAALAADCggIDgAAAA==.',Ik='Iktome:BAAALAADCggICAAAAA==.',Il='Illidoo:BAAALAAECgcIEAAAAA==.',Im='Immôrtality:BAAALAADCggICAAAAA==.',In='Ingrimmosch:BAAALAAECgYICwAAAA==.',Ir='Iras:BAAALAAECgcICgAAAA==.Irujam:BAAALAAECgQIBgAAAA==.',Is='Iseig:BAAALAAECgQIBwAAAA==.',Ja='Jajoma:BAAALAADCggIDwAAAA==.',Jh='Jhakazar:BAAALAADCgcIBwAAAA==.',Jo='Johnmandrake:BAAALAADCgcIEgAAAA==.Jonkob:BAACLAAFFIEJAAMGAAUIBx5dAAA7AQAGAAMIhRpdAAA7AQAHAAIISSNbBADdAAAsAAQKgRcAAwcACAjQJlYAAIwDAAcACAjGJlYAAIwDAAYAAgjoJtAgAOwAAAAA.',Ju='Juljia:BAAALAAECgEIAQABLAAECggIFQAEABQbAA==.',['Jè']='Jèssí:BAAALAAECgcIEAAAAA==.',['Jó']='Jódi:BAAALAAECgEIAQAAAA==.',Ka='Kadlin:BAAALAAECgcIEAAAAA==.Kaduc:BAAALAAECgEIAQAAAA==.Kalidia:BAAALAAECgEIAQAAAA==.Kaluur:BAAALAAECggIAQAAAA==.Kantholz:BAAALAAECggICwAAAA==.Kardowén:BAAALAADCggIFgAAAA==.Karuuzo:BAAALAADCggICgABLAAFFAIIAgABAAAAAA==.Kaz:BAAALAADCggIEAAAAA==.',Ke='Keebala:BAAALAADCggIDwAAAA==.Kehléthor:BAAALAAECgcIEAAAAA==.Keio:BAAALAAECgQIBgAAAA==.Kelos:BAAALAAECggIAQAAAA==.Keltran:BAAALAADCgcIDQAAAA==.Kesiray:BAAALAAECgEIAQAAAA==.Keynani:BAAALAAECgYIDQAAAA==.',Kh='Khazragore:BAAALAAECgYICwAAAA==.',Ki='Kitanidas:BAAALAAECgQIBgAAAA==.Kitty:BAAALAADCggIDwAAAA==.',Ko='Konso:BAAALAAECgMIBgAAAA==.Koralie:BAAALAAECgcIEAAAAA==.Korudash:BAAALAADCgQIBAAAAA==.',Kr='Krafter:BAAALAAECgEIAQAAAA==.Kriegsritter:BAAALAADCgYIBgAAAA==.Krolok:BAAALAAECgYICwAAAA==.',['Kâ']='Kâshira:BAAALAADCggIFwABLAAECgEIAQABAAAAAA==.Kâzaam:BAAALAAECgQIBQAAAA==.',La='Laex:BAAALAADCgIIAgAAAA==.Lagolas:BAAALAADCggIFQAAAA==.',Le='Leanâ:BAAALAAECgEIAQAAAA==.Lesarya:BAAALAADCggICAAAAA==.',Li='Lilas:BAAALAADCgcICQAAAA==.Limaro:BAAALAAECgYICgAAAA==.Linari:BAAALAAECgEIAQAAAA==.Lindragon:BAAALAAECgYICwAAAA==.Lingshu:BAAALAAECgMIAwAAAA==.Liubee:BAAALAADCggICAAAAA==.',Lo='Lorufinden:BAAALAAECgYIDwAAAA==.',Lu='Luli:BAAALAADCggIDQAAAA==.Luminos:BAAALAAECgYICgAAAA==.Luáná:BAAALAAECgQIBwAAAA==.',Ly='Lyrilith:BAAALAAECgcIDwAAAA==.',['Lò']='Lònély:BAAALAADCggICAAAAA==.',Ma='Magicguk:BAAALAADCgcIDQAAAA==.Magmatron:BAAALAAECgcIDAAAAA==.Malgor:BAAALAADCgUIBQAAAA==.Malgorian:BAAALAAECgEIAQAAAA==.Malissp:BAAALAAECgYICQAAAA==.Malura:BAAALAAECgQIBgAAAA==.Manta:BAAALAAECggICAAAAA==.Marolaz:BAAALAADCgcIBwAAAA==.Matrâs:BAAALAAECgIIAgAAAA==.Maureen:BAAALAAECgEIAQAAAA==.Mazorgrim:BAAALAADCgYIBgAAAA==.',Me='Mechratle:BAAALAADCggIDAAAAA==.Megares:BAAALAAECgQIBwAAAA==.Merona:BAAALAAECgQIBwAAAA==.Mevi:BAAALAAECgUIBQAAAA==.',Mi='Miela:BAAALAAECgEIAQAAAA==.Millinocket:BAAALAADCggIFgAAAA==.Minuky:BAAALAAECgMIBwAAAA==.Minusa:BAAALAADCgYIBgAAAA==.Mirajane:BAAALAADCgcIBwAAAA==.Misschief:BAAALAADCgcICQAAAA==.Miyasu:BAAALAAECgMIAwAAAA==.',Mo='Mohora:BAAALAADCggIFgAAAA==.Monochrome:BAEALAADCggICAABLAAECgcIDQABAAAAAA==.',Mu='Muxx:BAAALAADCgcIBgAAAA==.',My='Myracel:BAABLAAECoEXAAIDAAgI0B3mBwC9AgADAAgI0B3mBwC9AgAAAA==.',['Mâ']='Mâlory:BAAALAADCggIDwAAAA==.',['Mè']='Mèoéw:BAAALAADCggIEAABLAAECgYIBgABAAAAAA==.',['Mì']='Mìri:BAAALAAECgEIAQAAAA==.',Na='Naúrdin:BAAALAADCggIEgAAAA==.',Ne='Neischi:BAAALAADCgcIBwAAAA==.Nerimee:BAAALAAECgIIAgAAAA==.Nestario:BAAALAAECgMIAwAAAA==.',Ni='Niachha:BAAALAADCggIFgAAAA==.Nidhoegg:BAAALAADCggIFgAAAA==.Nighti:BAAALAADCggICAAAAA==.Nightstalke:BAAALAAECgcIEgAAAA==.Nilathan:BAAALAAFFAIIAgAAAA==.Nioo:BAAALAAECgIIAgABLAAFFAIIAgABAAAAAA==.Nipani:BAAALAAECgcIEAAAAA==.Nissel:BAAALAAECgcIDQAAAA==.Niva:BAAALAAECgMIBwAAAA==.',Nj='Njela:BAAALAAECgYICwAAAA==.',No='Noellene:BAAALAAECgMIBwAAAA==.Norcanor:BAAALAADCgUIBQAAAA==.Noric:BAAALAAECgMIAwAAAA==.Norrîn:BAAALAAECgEIAQAAAA==.Noxî:BAAALAAECgYICwAAAA==.',['Nê']='Nêyláh:BAAALAAECgEIAQAAAA==.',['Nî']='Nîmue:BAAALAAECgEIAQAAAA==.',['Nö']='Nörmellina:BAAALAAECgEIAQAAAA==.',Ol='Olbai:BAAALAAFFAIIAgAAAA==.',Or='Oraradas:BAAALAAECgMIBwAAAA==.',Ov='Ovelia:BAAALAADCgcIBwABLAAFFAUICQAGAAceAA==.',Pa='Paladelgon:BAAALAAECgMIAwAAAA==.',Ph='Phayara:BAAALAAECgYIBgAAAA==.',Po='Pol:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.Polat:BAAALAADCggICAABLAADCggIEAABAAAAAA==.',Pr='Priestdelgon:BAAALAAECgYIBgAAAA==.',['Pâ']='Pâtrice:BAAALAADCgcIFQABLAAECgYIDAABAAAAAA==.',Qu='Quentchen:BAAALAAECggICwAAAA==.',Ra='Radojka:BAAALAADCggICgABLAAECgUICAABAAAAAA==.Raellian:BAAALAAECgYICwAAAA==.Rahdojka:BAAALAADCgQIBAABLAAECgUICAABAAAAAA==.Rashira:BAAALAAECgEIAQAAAA==.Raskji:BAAALAAECgYICwAAAA==.',Ri='Riodaan:BAABLAAECoEXAAIIAAgIwyX+AABtAwAIAAgIwyX+AABtAwAAAA==.',Ro='Roderia:BAAALAAECgEIAQAAAA==.Ronara:BAAALAAECgMIBwAAAA==.Rouul:BAAALAAECgYIEAAAAA==.',Ru='Rucari:BAAALAAECgcIBwAAAA==.Rudig:BAAALAADCgcIBwAAAA==.Rudix:BAAALAADCgMIBAAAAA==.',['Rø']='Rølvoddoskar:BAAALAAECgMIBAAAAA==.',Sa='Sabian:BAAALAAFFAIIAgABLAAFFAIIAgABAAAAAA==.Sakuriel:BAAALAADCggIFgAAAA==.Salvira:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.Samáèl:BAAALAADCgEIAQAAAA==.Sanii:BAAALAAECgEIAQAAAA==.Savinia:BAAALAAECgMIBAAAAA==.Sayu:BAAALAADCggIFwAAAA==.',Sc='Schneestaub:BAAALAADCgUICQAAAA==.Scyllua:BAAALAAECgQIBwABLAAECggICQABAAAAAA==.',Se='Seb:BAAALAADCggIDwAAAA==.Seeknd:BAAALAADCggICAAAAA==.Selarion:BAAALAAECgIIAgABLAAECgYICwABAAAAAA==.Sengaja:BAAALAAECgMIBwAAAA==.Serelia:BAAALAAECgMIBgAAAA==.',Sh='Shadowbladé:BAAALAADCgMIAwAAAA==.Shaebear:BAAALAADCggICAAAAA==.Shanaya:BAAALAADCggICAAAAA==.Sharandala:BAAALAAECgcIDwAAAA==.Shisai:BAABLAAECoEXAAMDAAgI4BX7FAAdAgADAAgI4BX7FAAdAgAJAAcIVQiGKgBdAQAAAA==.Shneezn:BAAALAAECgcIBwAAAA==.Shylvana:BAAALAAECgcIEgAAAA==.Shálly:BAAALAADCggICQAAAA==.Shérly:BAAALAAECgMIBQAAAA==.Shíney:BAAALAADCgcIDgABLAAECgMIBQABAAAAAA==.Shôdân:BAAALAADCggICAAAAA==.',Si='Sii:BAAALAADCggICAAAAA==.Sinesterá:BAAALAAECgEIAQAAAA==.',Sn='Snuppil:BAAALAADCgYIBgAAAA==.',So='Solius:BAAALAAECgUICAAAAA==.Sonkor:BAAALAAECgcIDwAAAA==.Sonèa:BAAALAADCgcIEgAAAA==.Sophar:BAAALAAECgcIEAAAAA==.',Sp='Spätelf:BAAALAAECgQIBAAAAA==.',Sr='Sry:BAAALAAECgYIBwAAAA==.',St='Staggerop:BAAALAAECgYIBgAAAA==.',Su='Sucari:BAAALAAECgYICQAAAA==.Sugosch:BAAALAADCgQIBAABLAAECgMIAwABAAAAAA==.Summergalé:BAAALAAFFAIIBAAAAA==.Sunless:BAAALAAECgEIAQAAAA==.',Sy='Sylva:BAAALAADCgYIDAAAAA==.',['Sà']='Sàphira:BAAALAADCgcIDQAAAA==.',['Sá']='Sáhirá:BAAALAAECgIIBAAAAA==.',['Sî']='Sîana:BAAALAAECgYICgAAAA==.',Ta='Tabuu:BAAALAADCgYICAAAAA==.Tabøø:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Talanjó:BAAALAAECgIIBAAAAA==.Talitha:BAAALAADCgYIBgAAAA==.Tanshiro:BAAALAAECgcIEAAAAA==.Tapsino:BAAALAADCgYIBgAAAA==.Tarexigos:BAAALAAECgEIAQAAAA==.Tatus:BAAALAADCgYIAwAAAA==.',Te='Tellron:BAAALAAECggICQAAAA==.Tessiâ:BAAALAAECgEIAQAAAA==.',Th='Thaddeus:BAAALAAECgcIDAAAAA==.Thalyana:BAAALAAECgQIBgAAAA==.Thanae:BAAALAAECgYICwAAAA==.Thasor:BAAALAADCggIDQAAAA==.Thorgran:BAAALAADCggIEwAAAA==.Thormorath:BAAALAADCgEIAQABLAADCgYIBgABAAAAAA==.',Ti='Tieker:BAAALAAECgYIBgABLAAECggIDQABAAAAAA==.Tilasha:BAAALAAECgMIAwAAAA==.',To='Todesente:BAAALAAECgQIBgAAAA==.Todormu:BAAALAADCgYIBgAAAA==.Toron:BAAALAADCgcICwAAAA==.Torque:BAAALAADCgIIAgAAAA==.',Tr='Trias:BAAALAAECgEIAQAAAA==.',Tu='Turmbauer:BAAALAAECgQIBgAAAA==.',['Tî']='Tîara:BAAALAAECgQIBgAAAA==.',['Tó']='Tór:BAAALAADCggIFgAAAA==.',Uk='Ukkosa:BAAALAAECgYICwAAAA==.',Um='Umath:BAAALAADCggIFAAAAA==.',Ur='Urolke:BAAALAAECgMIAwABLAAECgYICwABAAAAAA==.',Va='Valagard:BAAALAADCggIFwAAAA==.Valâr:BAAALAADCgcICQABLAAECgYIDAABAAAAAA==.Vantarias:BAAALAAECgEIAQAAAA==.',Ve='Vearis:BAAALAADCgQIBAAAAA==.Velgorn:BAAALAAECgMIAwAAAA==.Venture:BAAALAAECgQIBAABLAAFFAUICQAGAAceAA==.Vette:BAAALAAECgIIAgAAAA==.',Vi='Viridan:BAAALAADCggIFAAAAA==.',['Vê']='Vênture:BAABLAAECoEWAAIJAAgIFSIvBgD/AgAJAAgIFSIvBgD/AgABLAAFFAUICQAGAAceAA==.',Wa='Walkingbeef:BAAALAAECgEIAQAAAA==.Wanaka:BAAALAAECgQICQAAAA==.',Wi='Wildoger:BAAALAADCggIDwAAAA==.',Wo='Wolke:BAAALAAECgcIEAAAAA==.',Xa='Xacxa:BAAALAADCgUIAwAAAA==.Xastra:BAAALAAECgcIEAAAAA==.Xaxi:BAAALAADCgEIAQAAAA==.',Xe='Xelestine:BAAALAADCgcIBwAAAA==.Xeliera:BAAALAAECgYICwAAAA==.',Xi='Xindria:BAAALAADCggIDQAAAA==.',Ya='Yacusa:BAAALAAECgYICwAAAA==.Yamato:BAAALAAECgMIBgAAAA==.Yangzingthao:BAAALAAECgQIBgAAAA==.',Yo='Yo:BAAALAADCggICAAAAA==.Yodok:BAAALAAECgUICAAAAA==.Youmu:BAAALAAECgEIAQAAAA==.',Yu='Yuu:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Yuukì:BAAALAAECgcIEAABLAAECgcIEAABAAAAAA==.',Za='Zaara:BAAALAADCggIEAAAAA==.Zamga:BAAALAADCgcICwAAAA==.Zati:BAAALAAECgYIBgAAAA==.Zaubernixx:BAAALAAECgEIAQAAAA==.',Ze='Zerfall:BAAALAADCggIFAAAAA==.Zeriza:BAAALAAECgMIAwAAAA==.Zeronikor:BAAALAAECgMIBwAAAA==.Zerrox:BAAALAADCgUIBgAAAA==.',Zi='Zimti:BAAALAADCgYIBgAAAA==.',Zo='Zobrombie:BAAALAAECgcIDAAAAA==.Zojin:BAAALAAECgEIAQABLAAECgcIBwABAAAAAA==.Zolgon:BAAALAAECgYIDwAAAA==.Zoé:BAAALAAECgEIAQAAAA==.',Zu='Zulan:BAAALAADCgYIBgAAAA==.',Zy='Zyliâne:BAAALAADCggIFwAAAA==.',['Án']='Ánkharesh:BAAALAAECgIIAgAAAA==.',['Âr']='Ârmun:BAAALAADCgcIDAAAAA==.',['Är']='Ärator:BAAALAADCgcIEwAAAA==.',['Él']='Éllíe:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end