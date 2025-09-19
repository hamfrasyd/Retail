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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Hunter-BeastMastery','Paladin-Holy','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Monk-Windwalker',}; local provider = {region='EU',realm='Madmortem',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abbot:BAAALAAECggICAAAAA==.Abra:BAAALAADCgcICQAAAA==.Abydos:BAAALAADCgcIBwABLAAECggICwABAAAAAA==.',Ac='Achaion:BAAALAADCgcIBwAAAA==.Acki:BAAALAADCgcIDgAAAA==.',Ad='Adyria:BAAALAAECgIIAgAAAA==.',Aj='Ajeni:BAAALAADCgYIDgAAAA==.',Al='Altimor:BAAALAAECgMIBwAAAA==.Alvára:BAAALAAECgcIEAAAAA==.',Am='Amberlee:BAAALAAECgYIDQAAAA==.Ammâzonin:BAAALAAECgEIAQAAAA==.Amuun:BAAALAADCgIIAgAAAA==.',An='Anatomie:BAAALAAECggICwAAAA==.Angelface:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Anníky:BAAALAADCggICAAAAA==.',Ar='Aramat:BAAALAADCgcIBwAAAA==.Aranthil:BAAALAAECgMIBAAAAA==.Arenthil:BAAALAAECgQIBgAAAA==.Ariljar:BAAALAAECgYIDQAAAA==.Arkaik:BAAALAADCgcIDQAAAA==.',As='Ashara:BAAALAADCgMIAwAAAA==.Asheràh:BAAALAAECgMIBQAAAA==.Asterwix:BAAALAAECgEIAQAAAA==.',At='Athil:BAAALAAECgMIBAAAAA==.Aturana:BAAALAAECgYICwAAAA==.',Au='Auralis:BAAALAAECgMIBAAAAA==.Aurara:BAAALAAECgMIAwAAAA==.Aurel:BAAALAAECgEIAQAAAA==.Aurelien:BAAALAADCgcIFAAAAA==.Aurius:BAAALAAECgYICwAAAA==.',Av='Avène:BAAALAAECgMIBQAAAA==.',Ay='Aylyssae:BAAALAAECggICAAAAA==.',Az='Azizah:BAAALAAECgEIAQAAAA==.Azòg:BAAALAAECgYIDAAAAA==.',Ba='Bambur:BAAALAAECgQICAAAAA==.Bapsi:BAAALAADCggICAAAAA==.',Be='Bearlee:BAAALAAECgUIBQAAAA==.Beckhasel:BAAALAADCggIDwAAAA==.Bellatrix:BAAALAADCgYICAAAAA==.Benjayboi:BAAALAADCgUIBQAAAA==.Beppò:BAAALAAECgMIAwAAAA==.Berstes:BAAALAADCgUIBQAAAA==.Bevola:BAAALAADCgcICgAAAA==.',Bi='Biangka:BAAALAAECggIDgAAAA==.',Bl='Blitzbirne:BAAALAADCgcIDQAAAA==.Blutdrache:BAAALAAECgEIAgAAAA==.',Bo='Boomfluffy:BAAALAAECgMIBQAAAA==.',Br='Breitstreich:BAAALAADCgcIDQAAAA==.Brumbos:BAAALAADCggICwAAAA==.',Bu='Bummelz:BAAALAAECgcIEwAAAA==.Burroughs:BAAALAADCgcIBwAAAA==.',Ca='Candystôrm:BAAALAADCgQIBAAAAA==.Caraxas:BAAALAADCggIFwABLAAECgMIBwABAAAAAA==.Carerie:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Catalaná:BAAALAAECgMICAAAAA==.',Ce='Ceeyzo:BAAALAADCgYIBgAAAA==.Cerialkiller:BAAALAADCggIDwAAAA==.',Ch='Chaoling:BAAALAAECgcIBwAAAA==.Chippzzií:BAAALAAECgYICgAAAA==.Chocalock:BAAALAAECgMIBgAAAA==.Chorknai:BAAALAAECgUICgAAAA==.Chrisa:BAAALAAECgUICgAAAA==.',Cl='Clisan:BAAALAAECgYICQAAAA==.',Co='Colinferal:BAAALAAECgYIDgAAAA==.Corazón:BAAALAADCggICAAAAA==.',Cr='Cryîngwolf:BAAALAAECgIIAgAAAA==.',Da='Daeana:BAAALAADCggIBgAAAA==.Dako:BAAALAADCgMIAwAAAA==.Dalora:BAAALAAECgYIBgAAAA==.Dameon:BAAALAADCggIEgAAAA==.Dara:BAAALAAECgcIEAAAAA==.Darkcaster:BAAALAADCgMIAgAAAA==.Darkdaka:BAABLAAECoEVAAICAAgINxEBFwDVAQACAAgINxEBFwDVAQAAAA==.Darkdk:BAAALAADCgcIBwABLAAECggIFQACADcRAA==.Darkface:BAAALAADCgcIDQAAAA==.Darkpriest:BAAALAADCgIIAgAAAA==.Darkvoker:BAAALAAECgEIAQAAAA==.Darthsoul:BAAALAAECgYICgAAAA==.Dasilva:BAAALAADCgYIFAAAAA==.',De='Deadeyê:BAAALAAECgEIAgAAAA==.Deltonia:BAAALAADCgQIBAAAAA==.',Di='Dignug:BAAALAADCggIEQAAAA==.Dilonia:BAAALAAECgYIDAAAAA==.Dimiter:BAAALAAECgMIAwAAAA==.Dirbase:BAAALAAECgYIBgAAAA==.Dirce:BAAALAADCgEIAQAAAA==.Dirtyd:BAAALAAECgEIAQAAAA==.',Dr='Draccas:BAAALAADCggIFAAAAA==.Draketa:BAAALAAECgQICQAAAA==.Drip:BAAALAADCggIEAAAAA==.Drâgoon:BAAALAAECgMIBQAAAA==.',Du='Duellant:BAAALAAECgMIBQAAAA==.Durran:BAAALAAECgMIBgAAAA==.Duschberater:BAAALAADCggIDgAAAA==.Dusk:BAAALAADCgcIBwAAAA==.Duuns:BAAALAADCgcICQAAAA==.',['Dâ']='Dârka:BAAALAAECgEIAQAAAA==.Dâywâlker:BAAALAADCgMIAwAAAA==.',['Dê']='Dêspotar:BAAALAAECgQIBAAAAA==.',Ea='Earb:BAAALAAECgMIBgAAAA==.',Eb='Ebbakush:BAAALAADCgYICwAAAA==.',Ek='Ekzykes:BAAALAAECgMIAwAAAA==.Ekáro:BAAALAAECgMIAwAAAA==.',El='Elchak:BAAALAAECgMIBQAAAA==.Elenè:BAAALAAECgMIBAAAAA==.Elené:BAAALAADCgcIBwAAAA==.Ellariana:BAAALAADCggICAAAAA==.',Er='Erandas:BAAALAADCgYIBgAAAA==.Erdenfeuer:BAAALAADCgEIAQAAAA==.Ericsa:BAAALAAECggICwAAAA==.Ersatzspiel:BAAALAAECgMICAAAAA==.',Es='Essence:BAAALAAECgYIDQAAAA==.',Ev='Evithra:BAAALAAECgQIBAAAAA==.',Ex='Existenz:BAAALAAECgUICgAAAA==.Exitor:BAAALAADCgEIAQAAAA==.',Fa='Fandelyria:BAAALAAECgIIBAAAAA==.Farasyn:BAAALAAECgEIAQAAAA==.',Fe='Felgibson:BAAALAAECgYIDQAAAA==.Felinova:BAAALAAECgQICgAAAA==.Fero:BAAALAAECgMIAwAAAA==.',Fl='Flared:BAAALAAECgEIAQAAAA==.Fluorid:BAAALAAECgMIBQAAAA==.',Fr='Freesia:BAAALAAECgUIBgAAAA==.From:BAAALAAECgMIBQAAAA==.',Fy='Fynni:BAAALAAECgYIBwAAAA==.',Ga='Garaa:BAAALAAECgUICAAAAA==.',Gh='Ghandí:BAAALAAECgYICQAAAA==.',Gi='Ginnpala:BAAALAAECgYIDwAAAA==.',Gn='Gnomferatu:BAAALAAECgMIAwAAAA==.',Go='Gomper:BAAALAADCgUIAwAAAA==.Goswin:BAAALAADCggICAAAAA==.',Gr='Greeny:BAAALAAECgYICQAAAA==.Grisu:BAAALAADCgcIEgAAAA==.Grisù:BAAALAADCgYIBgAAAA==.Grizzli:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.Gromar:BAAALAAECggICAAAAA==.',Gu='Guldanos:BAAALAAECgMIBgAAAA==.Gurkengustel:BAAALAAECgMIBAAAAA==.',Gw='Gwendoleen:BAAALAAECgIIAwAAAA==.',['Gò']='Gòlle:BAAALAAFFAEIAQAAAA==.',['Gö']='Gövb:BAAALAADCgQIBwAAAA==.',['Gú']='Gúnnârsòn:BAAALAAECgMIBgAAAA==.',Ha='Halvor:BAAALAAECgMIAwAAAA==.Hanibal:BAAALAAECgMIAwAAAA==.Hastir:BAAALAADCgcIBwAAAA==.',He='Hellráiser:BAAALAAECgIIAgAAAA==.Heribert:BAAALAAECgEIAQAAAA==.Herzbann:BAAALAAECgYIDQAAAA==.Hestaby:BAAALAAECgYIDQAAAA==.Hexerchen:BAAALAAECgMIBAABLAAECggIDgABAAAAAA==.Hexorp:BAAALAADCgIIAgAAAA==.',Hi='Hiiaka:BAAALAAECgMIBAAAAA==.Hirona:BAAALAADCggIDwAAAA==.',Ho='Holypumpgun:BAAALAAECgIIAgAAAA==.Homusubi:BAAALAADCgEIAQAAAA==.Hornîdemon:BAAALAAECgMIAwAAAA==.Hoshiguma:BAAALAAECgMIAwAAAA==.',Hr='Hrøthgarr:BAAALAADCggICAAAAA==.',['Hé']='Héllslayer:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',['Hí']='Híkarí:BAAALAAECgMIBAAAAA==.',Ig='Igcorn:BAAALAADCgcIEgAAAA==.',Il='Illidarm:BAAALAAECgYIDwAAAA==.',Im='Imhotêp:BAAALAAECgMIBAAAAA==.',In='Ino:BAAALAAECgYIDgAAAA==.Inso:BAAALAADCgcIBwAAAA==.Inspíra:BAAALAADCggIFgAAAA==.',Is='Isnipeyou:BAABLAAECoEWAAIDAAgIVgyZIQDpAQADAAgIVgyZIQDpAQAAAA==.',It='Itakespeed:BAAALAAECgYIDQAAAA==.',Iw='Iwazaro:BAAALAAECgYIDQAAAA==.',Ja='Jalendrya:BAAALAAECgYICwAAAA==.',Je='Jeneca:BAAALAAECgYICQAAAA==.Jerrica:BAAALAAECgcIEAAAAA==.Jeryssa:BAAALAADCggICQAAAA==.',Ji='Jingu:BAAALAADCggIEAAAAA==.',Ju='Juker:BAAALAAECgYIBgAAAA==.Jularis:BAAALAAECgMIAwAAAA==.',['Jî']='Jînx:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',Ka='Kagûra:BAAALAAECgUIBQAAAA==.Kaissy:BAAALAAECgMIBAAAAA==.Kaiulani:BAAALAADCgcIBwAAAA==.Kakashie:BAAALAAECgUIBwAAAA==.Kalany:BAAALAAECgMIBwAAAA==.Kaliphera:BAAALAAECgEIAQAAAA==.Karya:BAAALAAECgMIBQAAAA==.Kathreena:BAAALAAECgYICAAAAA==.Kazzia:BAAALAAECgIIAgAAAA==.',Ke='Keleriâ:BAAALAAECgcICwAAAA==.Kergrimm:BAAALAADCgcIEQAAAA==.Kerola:BAAALAADCgcIEgAAAQ==.Keshara:BAAALAAECgUICQAAAA==.',Ki='Kimiko:BAAALAADCgQIBAAAAA==.Kiralowa:BAAALAADCggIDAAAAA==.',Kl='Klotzkopf:BAAALAADCgIIAgAAAA==.',Ko='Koothrappali:BAAALAAECgQIBAAAAA==.',Kr='Kraska:BAAALAADCgIIAgAAAA==.Krellis:BAAALAADCgcIDgAAAA==.Krenon:BAAALAAECgEIAQAAAA==.',['Kä']='Käsi:BAAALAAECgYICQAAAA==.',['Kí']='Kíllbill:BAAALAAECggICAAAAA==.Kíllerspeed:BAAALAADCgYIBgAAAA==.',La='Larisha:BAAALAAECgcIEAAAAA==.Latexia:BAAALAADCggIFAAAAA==.Lautasmir:BAAALAADCgcIEAAAAA==.Lavonas:BAAALAAECgIIBAAAAA==.Laylana:BAAALAAECgMIBAAAAA==.',Le='Lenija:BAAALAAECgMIBgAAAA==.Leodor:BAAALAAECgcIDQAAAA==.Lessien:BAAALAAECgYIDQAAAA==.Lexus:BAAALAADCgcIBwAAAA==.Leyona:BAAALAADCggIDwAAAA==.',Lh='Lhoreta:BAAALAADCgYIBgAAAA==.',Li='Libertas:BAAALAAECgUICAAAAA==.Lightyear:BAAALAADCgcIBwAAAA==.Livefour:BAAALAAECgYICgAAAA==.Liwana:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.',Lo='Londran:BAAALAAECgMIBwAAAA==.Loorii:BAAALAADCgcIDgAAAA==.',Lu='Lucifér:BAAALAADCgcICgABLAAECgEIAQABAAAAAA==.Luthia:BAAALAADCggICAAAAA==.',Ly='Lynesca:BAAALAAECgIIAgAAAA==.Lyo:BAAALAAECgMIBQAAAA==.Lysalis:BAAALAADCggIEAAAAA==.Lysandar:BAAALAAECgYIDQAAAA==.',['Lü']='Lübä:BAABLAAECoEXAAIEAAgI/R+iAgDbAgAEAAgI/R+iAgDbAgAAAA==.',Ma='Maditartor:BAAALAAECgIIAgAAAA==.Mainator:BAAALAADCggIEAAAAA==.Malissa:BAAALAAECgMIBgAAAA==.Maowy:BAAALAAECgIIAwAAAA==.Marab:BAAALAAECgYICwAAAA==.Margonja:BAAALAAECgEIAQAAAA==.Maschorox:BAAALAAECgIIAwAAAA==.',Me='Medon:BAAALAADCgcIBwAAAA==.Meilíx:BAAALAADCggICAAAAA==.Meistercycle:BAAALAADCggIFAAAAA==.Melfara:BAAALAADCggIEQAAAA==.Meliaa:BAAALAADCggIEAABLAAECgMIBgABAAAAAA==.Melvin:BAAALAAECgMIBgAAAA==.Memna:BAAALAADCgMIAwABLAAECgUIBQABAAAAAA==.Merãluñã:BAAALAADCgEIAQAAAA==.',Mi='Milim:BAAALAAECgMIBAAAAA==.Mimikyu:BAAALAAECgYICQAAAA==.Minna:BAAALAADCgQIBwAAAA==.Miyade:BAAALAADCggIFwABLAAECgMIBgABAAAAAA==.',Mo='Mondschwinge:BAAALAAECgQICgAAAA==.Monomania:BAAALAAECgMIBQAAAA==.Monschischi:BAAALAAECgEIAQAAAA==.Moofiepoh:BAAALAAECgcIDQAAAA==.Mooncrush:BAAALAAECgYICgAAAA==.Morowyn:BAAALAAECgcIBwAAAA==.',Mu='Muhnagosa:BAAALAAECgMIAwAAAA==.Munel:BAAALAAECgYIDQAAAA==.',['Mè']='Mèlix:BAAALAAECgYIDQAAAA==.',Na='Naliana:BAAALAADCgcICAABLAAECgYICwABAAAAAA==.Napfkuchen:BAAALAAECgYICQAAAA==.Napo:BAAALAAECgIIAgAAAA==.Nathalel:BAAALAADCgcIBwAAAA==.',Ne='Necha:BAAALAAECgEIAQAAAA==.Nedari:BAAALAAECgMIBQAAAA==.Neiren:BAAALAAECgYIDQAAAA==.Neosha:BAAALAADCggICAABLAAECggICAABAAAAAA==.Nerdanel:BAAALAAECgYIDQAAAA==.Nerylla:BAAALAAECgMIAwAAAA==.',Ni='Nicon:BAAALAAECgYIDQAAAA==.Nightskull:BAAALAAECgUIBwAAAA==.Niluna:BAAALAADCgcIEgAAAA==.',['Nì']='Nìghtwolf:BAAALAADCgYIBgAAAA==.',Ol='Olfrad:BAAALAAECgQIBAAAAA==.',On='Oniginn:BAAALAADCgIIAgABLAAECgYIDwABAAAAAA==.Onklhorscht:BAAALAAECgMIBQAAAA==.',Or='Ordoban:BAAALAADCggIFwAAAA==.Orikano:BAAALAADCggIDwAAAA==.Orpex:BAAALAAECgEIAgAAAA==.',Os='Osbourne:BAAALAAECggICAAAAA==.',Ot='Otzum:BAAALAAECgIIAgAAAA==.',Pe='Petrani:BAAALAADCggIEgAAAA==.',Ph='Phyintias:BAAALAADCgcICwAAAA==.',Pi='Piiepmatz:BAAALAAECgIIAgAAAA==.Pillosis:BAAALAADCggICAAAAA==.',Po='Poepina:BAAALAADCggIEgAAAA==.Porthub:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.',Pr='Pretorianner:BAAALAAECgEIAQAAAA==.Priesterle:BAAALAAECgYICgABLAAECggIDgABAAAAAA==.Pränkii:BAAALAAECgcICgAAAA==.',Pu='Puda:BAAALAAECgEIAQAAAA==.Punaniwarri:BAAALAAECgYIDwAAAA==.Puredarkness:BAAALAAECgYIBgAAAA==.',Qu='Quool:BAAALAADCgQIBAAAAA==.',Re='Redbullseye:BAAALAADCgcIBwAAAA==.Rehiri:BAAALAAECgcIDQAAAA==.Rekan:BAAALAAECgQIAQAAAA==.',Ro='Robina:BAAALAAECgEIAQAAAA==.Roblock:BAABLAAECoEWAAQFAAgIbBEwCgCsAQAGAAcIwRKpHgDYAQAFAAcIxQcwCgCsAQAHAAUIbQc4LwABAQAAAA==.Robson:BAAALAAECgcIDQAAAA==.Robsón:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.Rogan:BAAALAADCggIEgAAAA==.Rokkboxx:BAAALAADCggIFwAAAA==.Roxsas:BAAALAADCgQIBAAAAA==.',['Rá']='Rásputin:BAAALAAECggIEAAAAA==.',Sa='Sairaspöllö:BAAALAAECggICAAAAA==.Saizou:BAAALAAECgMIAwAAAA==.Salz:BAAALAADCgcIBwAAAA==.Santäter:BAAALAADCgcIBwAAAA==.Sayu:BAAALAAECgcICAAAAA==.',Sc='Schitan:BAAALAAECgMIBQAAAA==.Scãrlinã:BAAALAADCgQIBAAAAA==.',Se='Secira:BAAALAAECgMIBgAAAA==.Seduka:BAAALAADCggICAAAAA==.Seelenfriede:BAAALAAECgcIEAAAAA==.Segerazz:BAAALAAECgMIBQAAAA==.Serila:BAABLAAECoEVAAIIAAgInh/qCQD1AgAIAAgInh/qCQD1AgAAAA==.Sethmorag:BAAALAADCgMIAwAAAA==.Sevaum:BAAALAAECgMIAwAAAA==.Seyco:BAAALAAECggICAAAAA==.',Sh='Shacks:BAAALAAECggICAABLAAECggIDAABAAAAAQ==.Shadowuwu:BAAALAAECgQIBgAAAA==.Shalímar:BAAALAAECgcIEQAAAA==.Shekfang:BAAALAADCgUIBQABLAAECgUICAABAAAAAA==.Shirka:BAAALAAECgIIBAAAAA==.Shix:BAAALAAECggIDAAAAQ==.Shiyzuka:BAAALAAECgMIBAAAAA==.',Si='Siegertyp:BAAALAADCgUIBQAAAA==.Sihirbaz:BAAALAAECgMIBgAAAA==.Sinon:BAAALAAECgMIBgAAAA==.Sireena:BAAALAAECgMIBQAAAA==.Sirtom:BAAALAAECgYIDQAAAA==.',Sl='Slacé:BAAALAADCggIDwAAAA==.Slany:BAAALAADCgcIDQAAAA==.',Sn='Snes:BAAALAAECgYIDgAAAA==.',So='Sodal:BAAALAAECgMIBAAAAA==.',Su='Sukie:BAAALAADCgcIBwAAAA==.Surbradl:BAAALAAECgMICgAAAA==.Susiohnebot:BAAALAAECgMIAwAAAA==.',Sw='Sworduschi:BAAALAADCggIAwAAAA==.',Sy='Syndragos:BAAALAAECgEIAQAAAA==.Sypho:BAAALAAECggIAQAAAA==.',['Sâ']='Sâlâmânderîa:BAAALAAECgIIAgAAAA==.',['Sä']='Säbellicht:BAAALAADCgIIAgAAAA==.',['Sé']='Séeéd:BAAALAADCgcICwAAAA==.',['Sê']='Sêrina:BAAALAAECgMIBQAAAA==.',Ta='Tadrin:BAAALAADCggIDwAAAA==.Talrashar:BAAALAADCgMIAwAAAA==.Taqvia:BAAALAADCggIFwAAAA==.Taryel:BAAALAADCggIEAAAAA==.',Te='Teláris:BAAALAADCgIIAgAAAA==.Teraf:BAAALAADCgcIBwAAAA==.',Th='Thalina:BAAALAAECggICAAAAA==.Tharisa:BAAALAAECgMIBQAAAA==.Thariux:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Thaílanah:BAAALAAECgEIAQAAAA==.Theundil:BAAALAAECggIEgAAAA==.Thondir:BAAALAAECgYIDQAAAA==.Thorja:BAAALAAECgMIBgAAAA==.Thundara:BAAALAAECgMIBQAAAA==.',Ti='Tigoro:BAAALAADCggIEQABLAAECgYIBgABAAAAAA==.Tinman:BAAALAADCgcIBwAAAA==.Tirifa:BAAALAADCggIDwABLAAECgYICgABAAAAAA==.Tirsulfid:BAAALAAECgEIAQAAAA==.',To='Tobrâx:BAAALAAECggIAwAAAA==.Torda:BAAALAADCgcIDAAAAA==.Totemtobi:BAAALAAECgMIBQAAAA==.Totilein:BAAALAADCgEIAgAAAA==.',Tr='Trakath:BAAALAAECgYICQAAAA==.Trevian:BAAALAAECgUIBgAAAA==.Trinkverbot:BAAALAAECgYIDAABLAAECgYIDgABAAAAAA==.',Tu='Turtledemo:BAAALAADCgEIAQAAAA==.',Tw='Twondil:BAAALAADCggICAAAAA==.',Ty='Tyrannus:BAAALAAECgQIBAAAAA==.',Un='Unaya:BAAALAAECgQIBgAAAA==.',Ur='Urathan:BAAALAAECgcICgABLAAECggIDgABAAAAAA==.',Ve='Veltar:BAAALAAECgYIBgAAAA==.Verania:BAAALAAECgEIAgAAAA==.',Vi='Violetnike:BAAALAADCggICAAAAA==.Virga:BAAALAAECgEIAQAAAA==.Vivî:BAAALAADCggICgABLAAECgMIBgABAAAAAA==.',Vo='Vokar:BAAALAAECgEIAgAAAA==.',Wa='Wayendran:BAAALAAECgMIAwAAAA==.',We='Weltnee:BAAALAAECgUIBQABLAAECgMIBgABAAAAAA==.Weltnoo:BAAALAAECgMIBgAAAA==.',Wh='Whitenike:BAAALAADCgYIBgAAAA==.',Wi='Wiaschtlsira:BAAALAADCggIEgAAAQ==.Wildstyles:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Wo='Woodford:BAAALAADCgcICQAAAA==.',Wu='Wuying:BAAALAADCggICAAAAA==.',Wy='Wyscor:BAAALAADCgcIBwAAAA==.',Xa='Xaloris:BAAALAAECgYIDQAAAA==.Xalìtas:BAAALAADCgQIBAAAAA==.Xantharî:BAAALAAECgMIBQAAAA==.Xanthya:BAAALAAECgYIDQAAAA==.',Xe='Xeller:BAAALAADCggICAAAAA==.',Xh='Xheela:BAAALAAECgMIAwAAAA==.',['Xâ']='Xânt:BAAALAADCggIFAAAAA==.',Ya='Yalani:BAAALAAECgEIAQAAAA==.Yappo:BAAALAAECgcIEgAAAA==.',Yi='Yingau:BAAALAAECgMIBQAAAA==.',Yu='Yukk:BAAALAADCgMIAwAAAA==.Yuliveê:BAAALAAECgMIBgAAAA==.',Za='Zarali:BAAALAAECgYICwAAAA==.Zaralija:BAAALAADCgMIAwAAAA==.Zatôx:BAAALAADCggIGAAAAA==.',Zi='Zin:BAAALAADCggIDwAAAA==.',Zu='Zucker:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Zulumi:BAAALAAECgMIBAAAAA==.Zuraal:BAAALAADCggIFAAAAA==.',Zy='Zymbal:BAAALAAECgIIAwAAAA==.',['Áe']='Áegwynn:BAAALAAECgcIEwABLAAECggIFAAJAG0fAA==.Áelora:BAAALAAECgYICQAAAA==.',['Äp']='Äpril:BAAALAAECgQICgAAAA==.',['Är']='Ärathan:BAAALAAECggIDgAAAA==.',['Çh']='Çhandra:BAAALAAECgYIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end