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
 local lookup = {'Priest-Holy','Unknown-Unknown','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Mistweaver','Mage-Frost','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Evoker-Devastation','Paladin-Holy','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Augmentation','Warrior-Fury',}; local provider = {region='EU',realm='Cho’gall',name='EU',type='weekly',zone=44,date='2025-08-30',data={Aa='Aalíyah:BAAALAAECgcIEQAAAA==.',Ad='Adeuxline:BAAALAADCgEIAQAAAA==.Adrishaman:BAAALAAFFAIIAgAAAA==.',Ai='Aiyanna:BAAALAAECgMIBQAAAA==.',Ak='Akame:BAAALAAECgcIDAAAAA==.Akonit:BAAALAADCgcIBwAAAA==.',Al='Alliyah:BAAALAAECgcICwAAAA==.Aløa:BAAALAAECggICwAAAA==.Alû:BAAALAADCggICAAAAA==.',Am='Amalgham:BAAALAAECgYICwAAAA==.',An='Andaeriel:BAABLAAECoEVAAIBAAgIog+lGwDUAQABAAgIog+lGwDUAQAAAA==.Andrõmède:BAAALAADCgUIBQAAAA==.Angahrän:BAAALAADCgQIBAAAAA==.Angëleyes:BAAALAAECgIIAgAAAA==.Anlya:BAAALAAECgYIEAAAAA==.Ansteal:BAAALAAECgEIAQAAAA==.Antòn:BAAALAAECgYICwABLAAECgcICAACAAAAAA==.',Ap='Apia:BAAALAADCggIBgAAAA==.Apollòn:BAAALAADCggICgAAAA==.',Ar='Arhès:BAAALAAECgYICQAAAA==.',As='Ascendance:BAAALAAECgcIEwAAAA==.Astrønef:BAAALAAECgIIAgAAAA==.',At='Atalânte:BAAALAADCgcIBwAAAA==.Atøme:BAAALAAECgYICgAAAA==.',Au='Augustik:BAAALAADCggIDwAAAA==.',Az='Azakeal:BAAALAADCggICQAAAA==.Azaraks:BAAALAADCgIIAgAAAA==.Azhall:BAAALAAECgMIAwAAAA==.Azkis:BAAALAADCggICAAAAA==.',Ba='Babaganoush:BAAALAADCgIIAgAAAA==.Babouliao:BAAALAAECgEIAQAAAA==.Bakhaw:BAAALAADCgQIBgAAAA==.Balisto:BAAALAAECgIIAgAAAA==.Barabell:BAAALAAECgYIEAAAAA==.Baratiddy:BAAALAAECgMIBgAAAA==.',Be='Beerloveme:BAAALAADCggIDwAAAA==.Belenos:BAAALAADCgcIBwAAAA==.Berta:BAAALAADCgEIAQAAAA==.Beurkk:BAAALAAECgMIAwAAAA==.',Bi='Bibilol:BAAALAADCggIEQAAAA==.Bigornôt:BAAALAADCggICAAAAA==.',Bl='Blyoux:BAAALAADCgEIAQAAAA==.',Bo='Bochek:BAAALAADCggIFQABLAAECgYIDgACAAAAAA==.',Br='Brawlslayer:BAAALAADCgIIAgAAAA==.',Ca='Cadvingtetun:BAAALAAECgQIBwAAAA==.Calebv:BAAALAAECgYICwAAAA==.Calfouette:BAAALAADCgcIDAAAAA==.Cambreezex:BAAALAADCgcIBwAAAA==.Catniss:BAAALAADCgcIBwAAAA==.Cazomir:BAAALAADCgYIBgAAAA==.',Ce='Cecibrr:BAAALAAECgYIBgAAAA==.Cecirae:BAAALAAECgYIDAAAAA==.Cerwyn:BAAALAAECgYICQAAAA==.Cetirizine:BAAALAADCgUIBQAAAA==.',Ch='Chamynoob:BAAALAAECgYICgAAAA==.Chaseros:BAAALAADCgcIBwAAAA==.Chonch:BAAALAADCgcIBwAAAA==.Chrisseuh:BAAALAADCggIFgAAAA==.',Ci='Cilia:BAAALAADCgUIBQAAAA==.Cindêr:BAAALAAECgYIEQAAAA==.Circë:BAAALAADCggICgAAAA==.Citrohhnelle:BAAALAAECgMIBQAAAA==.',Cl='Classcheater:BAAALAADCgUIBQAAAA==.',Cm='Cmbrzx:BAAALAAECgMIAwAAAA==.Cmbrzzx:BAAALAAECgMIAwAAAA==.',Co='Corliss:BAAALAAECgYICgAAAA==.',['Cé']='Célïa:BAAALAADCgcIBwABLAAECgcIEQACAAAAAA==.',['Cø']='Cøøkïe:BAAALAAECgYIBgAAAA==.',Da='Daddyrexgodx:BAAALAAECggICAAAAA==.Daphaladriel:BAAALAAECgMIAwAAAA==.Daphnisse:BAAALAADCgEIAQAAAA==.Darksmarties:BAAALAADCggIDgAAAA==.Darkvika:BAAALAADCgUIBQAAAA==.Darween:BAAALAADCgQIBAAAAA==.',De='Deceiver:BAAALAAECgcIEgAAAA==.Demaciaa:BAAALAAECgMIBgAAAA==.Demotria:BAAALAADCgUIBQAAAA==.Demøniä:BAAALAADCgYIBgAAAA==.Denethan:BAAALAADCggIDwAAAA==.Derrierevous:BAAALAADCgQIBAAAAA==.',Di='Dingqt:BAABLAAFFIEGAAIDAAMI/xauAgALAQADAAMI/xauAgALAQAAAA==.Diplodocus:BAAALAADCgcIBwAAAA==.',Dj='Djowcow:BAAALAAECgYIDQAAAA==.Djð:BAAALAADCgYIBgAAAA==.Djðthyr:BAAALAAECgMIAwAAAA==.',Dk='Dkleria:BAAALAADCgQIBAAAAA==.Dkrag:BAAALAAECgIIAgAAAA==.',Dm='Dmo:BAAALAADCgcIBwAAAA==.',Do='Doduh:BAAALAADCgMIAwAAAA==.Doshaburiten:BAAALAAECgEIAQAAAA==.',Dr='Draconnare:BAAALAAECgMIAwAAAA==.Dradine:BAAALAAECgYICgAAAA==.Drakhtar:BAAALAADCgUIBwAAAA==.Drizztt:BAAALAADCggICQAAAA==.Drooks:BAAALAADCggICAAAAA==.Druidesse:BAAALAADCgcIDAAAAA==.Drääkk:BAAALAADCgcIBwAAAA==.',Dw='Dwartz:BAAALAAECgMIBQAAAA==.',['Dé']='Désespoir:BAAALAAECgUIBQAAAA==.',['Dï']='Dïxdeux:BAAALAAECgMIAwAAAA==.',['Dü']='Dürotan:BAAALAADCgQIBAAAAA==.',Eb='Ebrial:BAAALAADCgUIBAAAAA==.',Ec='Echtelyon:BAAALAADCggIDgABLAAECgUIBQACAAAAAA==.Eclairage:BAAALAAECgcIEQAAAA==.',Ed='Edôtensei:BAAALAAECgcICAAAAA==.',Ef='Efeiremm:BAAALAAECgYIDgAAAA==.',El='Elethael:BAAALAAECgEIAQAAAA==.Elfagstorm:BAAALAADCgYICAAAAA==.Elfiine:BAAALAADCgUIBAAAAA==.Elicanna:BAAALAADCgcIBwAAAA==.Ellyshã:BAAALAADCgcIBwAAAA==.Elrandrir:BAAALAAECgcIDgAAAA==.Elunara:BAAALAAECgQIBwAAAA==.',En='Enaliia:BAAALAADCgIIAgAAAA==.Enallya:BAAALAADCggICAAAAA==.Ennalya:BAAALAAECgYICQAAAA==.',Eq='Equiroxx:BAAALAADCggIDgAAAA==.',Er='Erato:BAAALAADCgUIBQAAAA==.',Es='Eskk:BAAALAADCgYICgAAAA==.Eskä:BAAALAADCgYICAAAAA==.',Eu='Eurimar:BAAALAADCggICgAAAA==.Eurïpïde:BAAALAADCggIDwAAAA==.',Ey='Eyeshield:BAAALAAECgMIBAAAAA==.',['Eä']='Eärendil:BAAALAAECgcICwAAAA==.',Fa='Faitapriére:BAAALAADCggIDwAAAA==.Fak:BAAALAADCgYIBgAAAA==.Falleris:BAAALAADCgIIAgAAAA==.Fayadrake:BAAALAADCgcIBwAAAA==.',Fe='Fedréa:BAAALAAECgMIAwAAAA==.',Fl='Flannelle:BAAALAAECgUIBQAAAA==.Fluffy:BAAALAAECgQIBAAAAA==.Flêau:BAAALAAECgYIDAAAAA==.',Fn='Fnrx:BAAALAADCggIDwAAAA==.',Fo='Force:BAAALAADCgYIBQAAAA==.Forzeur:BAAALAAECgYICQAAAA==.',Fr='Freija:BAAALAADCgMIAwAAAA==.Frolix:BAAALAADCgcIBwAAAA==.Froufroune:BAAALAADCggICAAAAA==.',['Fé']='Féedesbosses:BAAALAADCgcIDgAAAA==.',Ga='Gaabriel:BAAALAADCgYIBgAAAA==.Galbathorix:BAAALAAECggICQAAAA==.Gamesh:BAAALAAECgMIBQAAAA==.',Gi='Gildàrak:BAAALAAECgMIAwAAAA==.Gilgalãd:BAAALAAECgYICwAAAA==.Girlzy:BAAALAAECgcIEAAAAA==.Gizak:BAAALAAECgYIDwABLAAECgYIDAACAAAAAA==.',Gl='Glitchwiz:BAAALAAECgIIAgAAAA==.Gluo:BAAALAAECgIIAgAAAA==.',Gn='Gnomax:BAAALAADCggICQAAAA==.',Go='Gokuwastaken:BAAALAAECgYICQABLAAFFAMIBQAEAL4fAA==.Gordoz:BAAALAADCgYIBgAAAA==.',Gr='Gravâtrix:BAAALAAECgYICgAAAA==.Grosgnon:BAAALAADCgEIAQAAAA==.Grümpy:BAAALAADCggIDAAAAA==.',['Gâ']='Gârgâ:BAAALAADCgYIBwAAAA==.',['Gê']='Gênessys:BAAALAAECgMIBgAAAA==.',Ha='Habaday:BAAALAAECgYIBgAAAA==.Hagator:BAAALAADCggICAAAAA==.Hamesh:BAAALAAECgMIAwAAAA==.Haramis:BAAALAADCgcIBwAAAA==.Haunty:BAAALAAECgYIDAAAAA==.Hawi:BAAALAAECgEIAQAAAA==.',He='Healocu:BAAALAAECgYIDgAAAA==.Henei:BAAALAAECgcICwAAAA==.Heîmdall:BAAALAAECgUICAAAAA==.',Ho='Hokayd:BAAALAAECgQIBwAAAA==.Holydabe:BAAALAADCgcIBwAAAA==.Holylumos:BAAALAAECgMIAwAAAA==.Horfela:BAAALAADCgEIAQAAAA==.Horrorshow:BAAALAAFFAIIAgAAAA==.Hoxah:BAABLAAECoEVAAMFAAgI8yO2AQD6AgAFAAgIoCC2AQD6AgAEAAcIDiXCDQC7AgAAAA==.Hoyakö:BAAALAADCgYIBgABLAAECgcIBwACAAAAAA==.',['Hé']='Héré:BAAALAAECgYIDQAAAA==.',['Hë']='Hëttaggèr:BAAALAADCggIEAAAAA==.',['Hî']='Hîri:BAAALAADCgcIBwAAAA==.',['Hø']='Høpes:BAAALAADCgcIBwAAAA==.',Ib='Ibò:BAAALAAECgIIAgAAAA==.',Ic='Icavex:BAAALAADCgcIBwAAAA==.',Id='Idrjiä:BAAALAADCggICAAAAA==.',Il='Ilynn:BAAALAADCggIFwAAAA==.',Im='Imnotfiredup:BAAALAADCgcIBwABLAAECggIFQAEAE0XAA==.',Je='Jeanmichaman:BAAALAADCggICwAAAA==.Jeanmikifear:BAAALAADCgcIDAABLAADCggICwACAAAAAA==.Jemjem:BAAALAAECgQIBwAAAA==.',Jh='Jhezabelle:BAAALAAECgIIAgAAAA==.Jhih:BAAALAADCggICAAAAA==.',Jo='Jordän:BAAALAADCggIGAAAAA==.',Ju='Juhyô:BAAALAADCgMIAwAAAA==.Juicybolt:BAAALAAECgIIAgAAAA==.',['Jâ']='Jâsmïne:BAAALAADCgMIAwAAAA==.',['Jö']='Jölyne:BAAALAAECggIAQAAAA==.',Ka='Kaane:BAAALAADCggIDwAAAA==.Kadéra:BAAALAAECgUIBQAAAA==.Kaelhyne:BAAALAAECgYIDgAAAA==.Kagou:BAAALAADCgcIBwABLAAECggIFgAGAEAlAA==.Kahba:BAAALAADCgUIBwAAAA==.Kahki:BAAALAADCgcICQAAAA==.Kaihn:BAAALAADCggIDQAAAA==.Karàba:BAAALAAECgMIBgAAAA==.Kasugo:BAAALAADCgYIBgAAAA==.Katkar:BAABLAAECoEVAAIHAAgI1x50AwDnAgAHAAgI1x50AwDnAgAAAA==.',Ke='Keepwar:BAAALAAECgUIBQAAAA==.Keize:BAAALAAECgYIDgAAAA==.Kenseidrifto:BAAALAAECgMIAwAAAA==.Kepplar:BAAALAADCgYIBgAAAA==.Kesla:BAACLAAFFIEGAAIIAAMIFxMBAgD5AAAIAAMIFxMBAgD5AAAsAAQKgRYAAwgACAgPJKQCAAADAAgACAgPJKQCAAADAAkABwgLFNsZAOcBAAAA.',Ki='Kijo:BAAALAADCgUIBQABLAAECgYIDgACAAAAAA==.Kilkeny:BAAALAADCggICAAAAA==.Killyu:BAABLAAECoEUAAIKAAYINx8XIAAPAgAKAAYINx8XIAAPAgAAAA==.Kinbew:BAAALAAECgYIBgABLAAECgcIEAACAAAAAA==.Kinboa:BAAALAAECgcIEAAAAA==.Kirlepanda:BAAALAADCggIDgAAAA==.Kiro:BAAALAAECgYIDgAAAA==.Kironash:BAAALAADCgcIBwAAAA==.',Kl='Klarté:BAAALAAECgcIDAAAAA==.Klimz:BAAALAADCgEIAQAAAA==.Klyshadow:BAAALAAECgMIBAAAAA==.',Ko='Kornyc:BAAALAADCgEIAQAAAA==.',Kr='Kralizek:BAAALAADCggIDgAAAA==.Krazilec:BAAALAADCggICAAAAA==.Krokmoû:BAAALAADCgcIDgAAAA==.Kruxx:BAABLAAECoEXAAILAAgIJiJ5AwAaAwALAAgIJiJ5AwAaAwAAAA==.',Ks='Kstør:BAAALAADCggICAAAAA==.',Kv='Kvl:BAAALAAECgEIAQAAAA==.',Ky='Kyera:BAAALAADCgYIBgAAAA==.Kyerra:BAAALAAECgMIAwAAAA==.Kyerrae:BAAALAADCggICAAAAA==.',['Kâ']='Kâlthèra:BAAALAADCgUICQAAAA==.',['Ké']='Kéria:BAAALAADCggIEAAAAA==.',['Kê']='Kêêpstrong:BAAALAADCgUIBQAAAA==.',['Kø']='Kørax:BAAALAAECgMIBQAAAA==.Køsmø:BAAALAADCggICQAAAA==.',La='Laflechette:BAAALAAECgIIAgAAAA==.Lanerdow:BAAALAAECgYIDwAAAA==.Lanerknife:BAAALAAECgIIAgAAAA==.Latorpille:BAAALAADCgEIAQAAAA==.',Le='Leilleiwel:BAAALAAECgMIBQAAAA==.',Li='Lightniñg:BAAALAADCgEIAQAAAA==.Lilylou:BAAALAADCgUIBQAAAA==.',Lu='Lucee:BAAALAADCgEIAQAAAA==.Lulw:BAAALAAECgcIBwAAAA==.',Lw='Lwi:BAAALAADCggIDgAAAA==.',Ly='Lycal:BAAALAAECgIIAgAAAA==.',['Lï']='Lïght:BAABLAAFFIEFAAIMAAMIkxEwAgAHAQAMAAMIkxEwAgAHAQAAAA==.',['Lû']='Lûlû:BAAALAAECgcIEQAAAA==.',Ma='Madarat:BAAALAAECgYIEAAAAA==.Mafouam:BAAALAAECgEIAQAAAA==.Makaz:BAAALAAECgMIBQAAAA==.Malyka:BAAALAADCgcIEgAAAA==.Malìfiko:BAAALAAECgIIAgAAAA==.Manoû:BAAALAADCgMIAwAAAA==.Matsükö:BAABLAAECoEYAAINAAgIyx2pCQCGAgANAAgIyx2pCQCGAgAAAA==.Maximus:BAAALAAECgIIAwABLAAECgUIBgACAAAAAA==.Maximusse:BAAALAAECgUIBgAAAA==.Mayuyuyu:BAAALAADCgcIDgAAAA==.Mazikheen:BAAALAAECgMIAwAAAA==.Maïline:BAAALAAECggIEAAAAA==.',Me='Mehealplz:BAAALAAECgEIAQAAAA==.Memnøk:BAAALAAECgQICAAAAA==.Meytah:BAAALAAECgYICQAAAA==.',Mi='Michkael:BAAALAADCggIDQAAAA==.Midthunder:BAAALAAECgYICAAAAA==.Mightyure:BAAALAAECgUICQAAAA==.Miirit:BAAALAADCgcIDwAAAA==.Mimisikuu:BAAALAAFFAIIBAAAAA==.',Mo='Moghiro:BAAALAAECgcIBwAAAA==.Moitrà:BAAALAAECgcIEAAAAA==.Mongrobou:BAAALAADCgcIBwAAAA==.Mopotojo:BAAALAADCgcIDAAAAA==.Mopwasbetter:BAACLAAFFIEFAAIEAAMIvh9aAgAlAQAEAAMIvh9aAgAlAQAsAAQKgRgAAgQACAgpJgIBAIEDAAQACAgpJgIBAIEDAAAA.',Mu='Munzeria:BAAALAAECgMIAwAAAA==.Mursaat:BAAALAAECggIEAAAAA==.',My='Myoangelo:BAAALAADCggIFAAAAA==.',['Mé']='Mélancolie:BAAALAADCgYICAAAAA==.',['Mò']='Mòrphé:BAAALAADCggIDgAAAA==.',['Mó']='Mónory:BAAALAAECgYIDAAAAA==.',['Mø']='Mølly:BAABLAAECoEVAAIEAAgIWRqDEwB2AgAEAAgIWRqDEwB2AgAAAA==.',Na='Naimpureté:BAAALAAECgMIAwAAAA==.Namy:BAAALAAECgEIAQAAAA==.Narmina:BAAALAAECgcIBwAAAA==.Narween:BAAALAAECgYIDgAAAA==.Nastoumë:BAAALAAECgYIBgAAAA==.',Nc='Ncr:BAAALAADCgcIBwAAAA==.',Ne='Neawo:BAAALAADCggICQAAAA==.Nessa:BAAALAAECgMIBgAAAA==.Newhoo:BAAALAADCgIIAgAAAA==.',Ni='Nijika:BAAALAAECgUIBwAAAA==.Nixara:BAAALAADCggIDgAAAA==.',No='Nonope:BAAALAAECgcIBwAAAA==.Noodlle:BAAALAAECgEIAQAAAA==.Noonoope:BAAALAADCggICQAAAA==.Notowa:BAAALAAECgcIDAAAAA==.',Nu='Nuagée:BAAALAAECgUIBQAAAA==.Nueve:BAAALAAECgQIBAAAAA==.Null:BAAALAAECgYICgAAAA==.',Ny='Nymue:BAAALAAECgIIAgAAAA==.Nyxara:BAAALAADCgcIEQAAAA==.Nyxarïa:BAAALAADCgcIDwAAAA==.',['Nà']='Nàvÿ:BAAALAADCgMIAwAAAA==.',['Nä']='Nämîe:BAAALAADCggIDwABLAAECgMIAwACAAAAAA==.',['Né']='Nélizé:BAAALAAECgMIBgAAAA==.',Od='Odín:BAAALAADCggICAAAAA==.',Oe='Oestrogene:BAAALAADCgEIAQAAAA==.',Om='Ombrastraza:BAAALAADCgcICgAAAA==.',Or='Orionfrost:BAAALAAECgQIBwAAAA==.',Oz='Ozérixya:BAAALAAECgMIBQAAAA==.',['Oé']='Oén:BAAALAAECgYIBgAAAA==.',Pa='Painmoisi:BAAALAAECgMIBgAAAA==.Palounete:BAAALAAECgMIAwAAAA==.Palâdin:BAAALAADCgcIBwAAAA==.Pattefolle:BAAALAADCgYIBgAAAA==.',Pe='Petboul:BAAALAADCggICwAAAA==.',Ph='Pharamond:BAAALAADCggICAAAAA==.',Pi='Pidakor:BAAALAADCgQIBAAAAA==.Pignouff:BAAALAAECgMIBAAAAA==.',Pl='Placebð:BAAALAADCggIEAAAAA==.',Pn='Pnzrknst:BAAALAAECgMIBQAAAA==.',Po='Pokniovitch:BAAALAADCggIHAAAAA==.',Pr='Prøtek:BAAALAAECgYIBgAAAA==.',Pu='Punishêr:BAAALAAECgIIAgAAAA==.Puritania:BAAALAADCggICgAAAA==.',['Pä']='Pästaga:BAAALAAECgMIBAAAAA==.',['Pé']='Pépé:BAAALAADCgUIBQAAAA==.Pépégém:BAAALAAECgMIAwAAAA==.',Qr='Qroh:BAAALAAECgYIDgAAAA==.',Qu='Quentîn:BAAALAADCggICQAAAA==.Quetrax:BAAALAAECgMIAwAAAA==.Quitue:BAAALAADCgYIBgAAAA==.',Ra='Raikana:BAAALAADCggIDgAAAA==.Railana:BAAALAADCggICAABLAADCggIDgACAAAAAA==.Rapotipomort:BAABLAAECoEVAAMOAAgIVhfbHAAnAgAOAAgIVhfbHAAnAgAPAAEIURZgMABJAAABLAAFFAIIBAACAAAAAA==.Rapotipécail:BAAALAAFFAIIBAAAAA==.Rasmussen:BAAALAADCgIIAgAAAA==.Razoir:BAAALAAECgYIBgAAAA==.Razoïr:BAAALAAECgUICgABLAAECgYIBgACAAAAAA==.',Re='Recountsama:BAAALAAECgYIBgAAAA==.Remorse:BAAALAAECgcIDgAAAA==.',Rh='Rhaedrim:BAAALAAECgUIBQAAAA==.',Ri='Rispedk:BAAALAAECgYICwAAAA==.Rispetotem:BAAALAADCgcIBwAAAA==.Rispewar:BAAALAADCggICAAAAA==.',Rn='Rney:BAAALAAECgYIDgAAAA==.',Ru='Rumxus:BAAALAAECgcIEAAAAA==.Ruskov:BAAALAAECgcIEAAAAA==.',Sa='Salacity:BAAALAAECgIIAgAAAA==.Salyä:BAAALAAECgQICAAAAA==.Sawsix:BAAALAAECggIEAAAAA==.',Se='Seraphita:BAAALAADCggIFgAAAA==.',Sh='Shadowvoid:BAAALAADCgcIBwAAAA==.Shadøwhimø:BAAALAAECgIIAgAAAA==.Sharinga:BAAALAAECgQICQAAAA==.Shenhe:BAAALAADCggIDgAAAA==.Shindiara:BAAALAAECgYIBgAAAA==.Shoux:BAAALAAECgYICgAAAA==.Shoxx:BAAALAAECgMIBAAAAA==.Shux:BAAALAAECgMIAwABLAAECgYICgACAAAAAA==.',Si='Sigyn:BAAALAADCggICAAAAA==.',Sm='Smartiez:BAAALAAECgYIBgAAAA==.',So='Sonepi:BAAALAADCgUIBQAAAA==.Soultaker:BAAALAAECgQIBwAAAA==.Sourïcette:BAAALAADCggIFwABLAAECggIFQAEAFkaAA==.Soze:BAAALAAECgYIEQAAAA==.',Sp='Spikø:BAAALAAECgYICAAAAA==.Spizzis:BAAALAAECgcICwAAAA==.Spookies:BAAALAAECgQIBgAAAA==.Spyni:BAABLAAECoEVAAMQAAgIcCKmAAD5AgAQAAgIcCKmAAD5AgALAAIIkxXILwB4AAAAAA==.',Sq='Squallm:BAAALAADCgcICQAAAA==.',St='Stelløu:BAAALAAECgIIAgAAAA==.Stormy:BAABLAAECoEVAAIEAAgITRchGQBAAgAEAAgITRchGQBAAgAAAA==.Stormêttê:BAAALAAECgEIAQABLAAECggIFQAEAE0XAA==.Stürling:BAAALAADCgcIEQAAAA==.',Su='Sucetteu:BAAALAADCgQIBAAAAA==.Sucram:BAAALAADCggICAAAAA==.',Sw='Swwarleyy:BAAALAADCgUIBQAAAA==.',Sy='Syyn:BAAALAAECgQIBgAAAA==.',['Sø']='Sønsøn:BAAALAADCgcIBwAAAA==.',['Sû']='Sûcram:BAAALAAECgYIEAAAAA==.',Ta='Takashy:BAABLAAECoEWAAIGAAgIQCWLAABXAwAGAAgIQCWLAABXAwAAAA==.Tarma:BAAALAADCgEIAQAAAA==.',Te='Telliok:BAAALAADCgEIAQAAAA==.Telracs:BAAALAADCgcIBwAAAA==.Telsyn:BAAALAAECgMIAwAAAA==.Tempfirel:BAAALAADCgcIDAAAAA==.Tenedrions:BAAALAAECgIIAwAAAA==.Teuilteuil:BAAALAADCggICAAAAA==.',Th='Thridek:BAAALAAECgcIDAAAAA==.Thuldus:BAAALAADCggICQAAAA==.Thunda:BAAALAAFFAIIBAAAAA==.Thyr:BAAALAADCggICAAAAA==.',Ti='Tikita:BAAALAADCgcICQAAAA==.',To='Tooropmakta:BAAALAADCgQIAgAAAA==.Tooropmaktou:BAAALAAECgUICAAAAA==.Torniaule:BAAALAADCgcIBwAAAA==.Tovac:BAAALAADCgYIBwAAAA==.Toxyk:BAAALAADCgYIAQAAAA==.',Tr='Triple:BAAALAADCggIFAAAAA==.Trouzun:BAAALAADCggICgAAAA==.',Tu='Tuckor:BAAALAAECgQIBAAAAA==.Tulistéuncon:BAAALAADCgYIBgAAAA==.',['Té']='Ténébrius:BAAALAADCggIEAAAAA==.Téylaa:BAAALAAECgEIAwAAAA==.',['Tï']='Tïara:BAAALAADCgQIBAAAAA==.',['Tö']='Töketsu:BAAALAAECgIIAgAAAA==.',['Tø']='Tøorx:BAAALAADCgcICwAAAA==.',Ul='Uldreiyn:BAAALAAECggICAAAAA==.',Un='Unbroken:BAAALAAECgEIAQAAAA==.Unsainted:BAAALAADCgEIAQAAAA==.',Ut='Utaw:BAAALAADCgQIBAAAAA==.',Va='Valkiel:BAAALAADCggIDwAAAA==.Valtharo:BAAALAAECgYIDwAAAA==.Vandal:BAAALAADCgYIBgAAAA==.Vanpcow:BAAALAADCgcIDgABLAAECgUIDAACAAAAAA==.Vanpirus:BAAALAAECgUIDAAAAA==.Varoth:BAAALAAECgMIAwAAAA==.',Vo='Voltunholy:BAAALAAECgUIBQAAAA==.Vorhaks:BAAALAAECgMIAwAAAA==.',Vr='Vrokis:BAAALAADCgUIBAAAAA==.',Vu='Vulpix:BAACLAAFFIEGAAIRAAMI9xX0AgARAQARAAMI9xX0AgARAQAsAAQKgRcAAhEACAg9IbEHAPQCABEACAg9IbEHAPQCAAAA.',Vy='Vyrta:BAAALAAECgQIBAAAAA==.',['Vâ']='Vâyranna:BAAALAAECgIIAgAAAA==.',['Vë']='Vëlty:BAAALAADCgcIBwAAAA==.',['Vï']='Vïcinois:BAAALAAECgUIBQAAAA==.',Wa='Waifu:BAAALAAFFAIIAgAAAA==.Wasteal:BAAALAADCggIDQAAAA==.',We='Westindïes:BAAALAAECgYIDwAAAA==.',Wo='Wofînia:BAAALAADCgcIBwAAAA==.',['Wà']='Wàtù:BAAALAAECgYIDgAAAA==.',Xa='Xaariel:BAAALAADCggIFQAAAA==.',Xe='Xehanort:BAAALAAECgYIBgAAAA==.',Ye='Yelevoker:BAAALAADCggIDgAAAA==.Yenelo:BAAALAAECgcICAAAAA==.',Yo='Yotzlol:BAAALAAECgYICQAAAA==.',Ys='Ysthale:BAAALAAECgEIAQAAAA==.Ysé:BAAALAAECgMIAwAAAA==.',Yu='Yugitø:BAAALAADCgcIDAAAAA==.Yumeda:BAAALAAECgYICQAAAA==.',Yz='Yzanami:BAAALAADCgYIBAAAAA==.',['Yé']='Yéliia:BAAALAAECgMIAwAAAA==.',Za='Zakmi:BAAALAADCgYIBgAAAA==.Zalene:BAAALAADCgIIAgAAAA==.Zartrons:BAAALAAECgcIBAAAAA==.Zayone:BAAALAAFFAIIAgAAAA==.',Zb='Zbiboo:BAAALAADCggIDQAAAA==.',Ze='Zenesprit:BAAALAAECgMIAwAAAA==.',Zh='Zhoka:BAAALAAECgcIEAAAAA==.Zhokah:BAAALAAECgYICgABLAAECgcIEAACAAAAAA==.',Zi='Zids:BAAALAADCggICAAAAA==.Zink:BAAALAADCgMIAQAAAA==.',Zo='Zobois:BAACLAAFFIEFAAIKAAMI1heZAQASAQAKAAMI1heZAQASAQAsAAQKgRcAAgoACAj4IZgGAB0DAAoACAj4IZgGAB0DAAAA.Zohka:BAAALAAECgYIBgABLAAECgcIEAACAAAAAA==.Zolpanique:BAAALAADCgMIAwAAAA==.Zoubilou:BAAALAADCgYICwAAAA==.',Zu='Zumo:BAAALAADCggIFgAAAA==.Zupapa:BAAALAAECggICAAAAA==.',['Ôn']='Ônurb:BAAALAADCggIBQAAAA==.',['Øm']='Ømëga:BAAALAADCggICQAAAA==.',['ße']='ßenihime:BAAALAAECgQIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end