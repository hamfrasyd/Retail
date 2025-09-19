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
 local lookup = {'Unknown-Unknown','Warrior-Arms',}; local provider = {region='EU',realm='Nethersturm',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Achéron:BAAALAAECgMIAwAAAA==.Acielle:BAAALAAECggICQAAAA==.',Ad='Adanaran:BAAALAADCggIDwABLAAECgUIAwABAAAAAA==.',Ai='Aigil:BAAALAAECgYIBwAAAA==.',Al='Alery:BAAALAAECgMIAwAAAA==.Alizeá:BAAALAAECgMIAwAAAA==.',Am='Amary:BAAALAAECgYIDAAAAA==.Amatukani:BAAALAADCggICQAAAA==.',An='Anidera:BAAALAAECgYICwAAAA==.Annuxia:BAAALAAECgQIBAAAAA==.',Ar='Aramór:BAAALAAECgEIAQAAAA==.Ardeny:BAAALAAECgMIAwAAAA==.Arinja:BAAALAAECgEIAQAAAA==.Arrexxin:BAAALAADCgcIBwAAAA==.Arthag:BAAALAAECgQIBAAAAA==.',As='Asca:BAAALAADCggIDwAAAA==.Ascari:BAAALAAECgMIBQAAAA==.Asgorath:BAAALAADCggIDQABLAAECgEIAQABAAAAAA==.Astralina:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.',At='Ataxa:BAAALAADCgQIAwAAAA==.Ataxie:BAAALAAECgIIAgAAAA==.Atlandegoloz:BAAALAAECgQIBgAAAA==.',Ay='Ayasa:BAAALAADCgcIBwAAAA==.',Az='Aziron:BAAALAAECgcIEwAAAA==.',['Aý']='Aýahuasca:BAAALAAECgcIEQAAAA==.',Ba='Bastos:BAAALAAECgMIAwAAAA==.Baumfloh:BAAALAAECgMIBAAAAA==.',Be='Beater:BAAALAADCgYIBgABLAAFFAIIAgABAAAAAA==.Belicitas:BAAALAADCggIDwAAAA==.',Bi='Bigpaws:BAAALAADCggIDgAAAA==.',Bj='Björnogan:BAAALAAECgcIEAAAAA==.',Bl='Bloodshield:BAAALAAECgYIDQAAAA==.',Bo='Bode:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Bombi:BAAALAAECgEIAgAAAA==.Borouk:BAAALAADCgEIAQAAAA==.',Br='Branken:BAAALAAECgMIBQAAAA==.Brehm:BAAALAAECgMIBAAAAA==.Brewio:BAAALAADCgUIBQAAAA==.Brownielol:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.',Bu='Bumî:BAAALAAECgYIDwAAAA==.Bumîali:BAAALAADCgUIBQABLAAECgYIDwABAAAAAA==.Buuhhaua:BAAALAADCgcIBwAAAA==.',['Bê']='Bêrrók:BAAALAAECgYIAQAAAA==.',Ca='Caindral:BAAALAAECgMIAwAAAA==.Calistros:BAAALAAECgMIBgAAAA==.Cannibale:BAAALAADCggIEwAAAA==.Caprícorn:BAAALAADCgMIAwAAAA==.Carishia:BAAALAADCggIAgABLAAECgYICgABAAAAAA==.Carstelia:BAAALAADCgMIAwABLAAECgMIBgABAAAAAA==.',Ce='Cerdox:BAAALAAECgYICgAAAA==.',Ch='Changlol:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Chicrex:BAAALAAECgMIBgAAAA==.',Cl='Clericus:BAAALAAECgYIBgAAAA==.',Co='Colada:BAAALAAECgEIAQAAAA==.',Cr='Crobate:BAAALAAECgMIAwAAAA==.',Cu='Currysbabe:BAAALAAECgMIBQAAAA==.',Da='Daemonbane:BAAALAAECgQIBQAAAA==.Dafrá:BAAALAAECgMIAwAAAA==.Dangerest:BAAALAAECgUICgAAAA==.Dargon:BAAALAAECgMIBQAAAA==.',De='Death:BAAALAAECgYIEwABLAAECggIFwACALwjAA==.Debbu:BAAALAAECgMIBAAAAA==.Denden:BAAALAAECgEIAQAAAA==.Dennyyo:BAAALAAECgIIAwAAAA==.Destlight:BAAALAADCggIDwAAAA==.Destrower:BAAALAAFFAIIAgAAAA==.Destsilk:BAAALAAECgYIBgAAAA==.',Di='Diene:BAAALAADCgcICgAAAA==.',Dj='Djaydi:BAAALAADCgUIBQAAAA==.',Do='Dommie:BAAALAAECgIIAwAAAA==.Doorixdru:BAAALAADCgUIAgAAAA==.',Dr='Dracthyrus:BAAALAADCggIDwAAAA==.Draiden:BAAALAAECgcIEwAAAA==.Druidora:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Du='Dudolino:BAAALAAECgUICQAAAA==.',Dy='Dylies:BAAALAAECgMIBQAAAA==.Dywana:BAAALAAECgMIBQAAAA==.',['Dé']='Déyna:BAAALAADCggICAAAAA==.',['Dô']='Dôze:BAAALAAECgUICgAAAA==.',Eh='Ehlo:BAAALAAECgIIAgAAAA==.',El='Elartus:BAAALAAECgYICgAAAA==.Eliondra:BAAALAAECgMIBgAAAA==.Elsu:BAAALAADCgMIAwAAAA==.',Em='Emmó:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.Empar:BAAALAAECgYIDAAAAA==.',En='Ensiâ:BAAALAADCgQIBAABLAAECgYICgABAAAAAA==.Entanôtwo:BAAALAADCggICAAAAA==.Entendh:BAAALAADCgYIDAAAAA==.Entetot:BAAALAADCgUIBQAAAA==.Entevanquack:BAAALAAECgYIDAAAAA==.',Eu='Eula:BAAALAADCgcIBwAAAA==.',Ex='Exbruno:BAAALAAECgMIBQAAAA==.Exorcizamús:BAAALAADCgcIDQAAAA==.',Fa='Fausi:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.',Fe='Ferleinix:BAAALAADCgcIDQAAAA==.Feuersturm:BAAALAADCgUIBAAAAA==.',Fo='Forti:BAAALAADCggIFwAAAA==.',Fr='Frostkîller:BAAALAADCgQIBAAAAA==.',Fu='Fuchsteufel:BAAALAAECgEIAQAAAA==.Fuchur:BAAALAAECgUIAgAAAA==.',['Fû']='Fûchur:BAAALAAECggIAQAAAA==.',Ge='Geojin:BAAALAAECgYIBAAAAA==.Geran:BAAALAADCggIFgAAAA==.',Gi='Gichtknochen:BAAALAAECgYICgAAAA==.Ginette:BAAALAAECgIIAgAAAA==.',Gr='Gram:BAAALAAECgYIDwAAAA==.Grarrg:BAAALAAECgUIAgAAAA==.Gripexx:BAAALAAECgYICAAAAA==.Griswold:BAAALAAECgMIBQAAAA==.Grumbledour:BAAALAAECggIEgAAAA==.Gróm:BAAALAADCgYIBgAAAA==.',Gu='Gutesdmg:BAAALAADCggICAAAAA==.',Gw='Gwennefer:BAAALAADCggIEwAAAA==.',['Gã']='Gãntu:BAAALAADCgcIDwAAAA==.',['Gö']='Göks:BAAALAAECgEIAQAAAA==.',['Gü']='Gümli:BAAALAAECgEIAQAAAA==.',Ha='Habilol:BAAALAAECgYIDQAAAA==.Handara:BAAALAADCggIFAABLAADCggIFgABAAAAAA==.Haribo:BAAALAAECgcIEwAAAA==.',He='Hendt:BAAALAADCggIDwABLAAECgYIDwABAAAAAA==.',Hi='Himiko:BAAALAAECgQIBwAAAA==.',Ho='Holycrex:BAAALAADCgIIAgABLAAECgMIBgABAAAAAA==.',Hu='Hullá:BAAALAADCgMIAwAAAA==.',Ig='Igris:BAAALAAECgIIAgAAAA==.',Il='Ilian:BAAALAAECgQICQAAAA==.',Im='Image:BAAALAADCgcIBwAAAA==.Imposterkeck:BAAALAAECgYIEAABLAAFFAIIAgABAAAAAA==.',In='Inastrasza:BAAALAADCggIDgAAAA==.Inazuma:BAAALAAECgEIAQAAAA==.Insata:BAAALAADCgcIBwAAAA==.',Io='Ioné:BAAALAAECgIIAgAAAA==.',Is='Isiltur:BAAALAADCgcIBwAAAA==.',Ja='Jadedrache:BAAALAADCgMIAwAAAA==.',Jh='Jhuugrym:BAAALAADCgcIBwABLAADCggIFwABAAAAAA==.',Ji='Jimmyoyang:BAAALAAECgMIAwAAAA==.',Jo='Jokerdrache:BAAALAADCggIDgAAAA==.',Ka='Kadiana:BAAALAAECggIDAAAAA==.Karnic:BAAALAADCgcIBwAAAA==.',Ke='Kendár:BAAALAAECgYICQAAAA==.',Kh='Khazir:BAAALAAECgYIEAAAAA==.',Ko='Koriander:BAAALAAECgMIBgAAAA==.',Kr='Krids:BAAALAADCggIEQAAAA==.Krigsblut:BAAALAADCgcIBwAAAA==.',La='Laez:BAAALAADCgYIBgAAAA==.Large:BAAALAADCggIFwABLAAECgcIEAABAAAAAA==.Layzem:BAAALAADCgQIBAAAAA==.',Le='Leanora:BAAALAAECgEIAQAAAA==.Lehuskyh:BAAALAADCgUIBQAAAA==.Leuchtetatze:BAAALAADCgcIEAAAAA==.Lexea:BAAALAADCgcIDAAAAA==.',Li='Lik:BAAALAAECgIIAgAAAA==.Lillebror:BAAALAADCggIDwAAAA==.Littletomtom:BAAALAAECgYIBgAAAA==.Lizcore:BAAALAAECgMIBQAAAA==.Lizentia:BAAALAAECgMIBAAAAA==.',Lo='Lockmore:BAAALAADCggICgAAAA==.Lonewolf:BAAALAADCggIFgAAAA==.',Lu='Lutimarus:BAAALAADCgcIDAAAAA==.',['Lí']='Límos:BAAALAADCgcIEAAAAA==.',['Lî']='Lîllît:BAAALAAECgIIAgAAAA==.',['Lû']='Lûmiel:BAAALAADCgIIAgAAAA==.',Ma='Maarvxdh:BAAALAADCgUIAgAAAA==.Magnolie:BAAALAAECgMIBQAAAA==.Malena:BAAALAADCgYIBgAAAA==.Manadriel:BAAALAADCggIDwAAAA==.Marsellus:BAAALAADCgcIBwAAAA==.Martho:BAAALAADCgcICAAAAA==.Maybach:BAAALAAECgIIAgAAAA==.',Me='Meisterglanz:BAAALAAECgIIAgAAAA==.Melarath:BAAALAAECgMIBQAAAA==.',Mi='Mihodh:BAAALAADCggIDwAAAA==.Mindless:BAAALAADCggICAAAAA==.Miracuthor:BAAALAADCggIDwAAAA==.',Mo='Mogdalock:BAAALAADCgcICgAAAA==.Moordredo:BAAALAAECgYIDQAAAA==.Moyramclion:BAAALAADCggIDgAAAA==.',['Má']='Mártinlooter:BAAALAADCggICgAAAA==.',['Mé']='Mélinchen:BAAALAAECgYIBgAAAA==.Mése:BAAALAAECgUICgAAAA==.',['Më']='Mëxx:BAAALAADCgQIBAABLAAECgUICgABAAAAAA==.',['Mî']='Mîgo:BAAALAAECgEIAgAAAA==.',Na='Naltrexiya:BAAALAAECgMIAwAAAA==.Nareth:BAAALAAECgYICgAAAA==.Natesh:BAAALAADCgcIBwAAAA==.Navar:BAAALAAECgYIDwAAAA==.Navur:BAAALAAECgMIBQAAAA==.',Ne='Necherophes:BAAALAADCgMIAwAAAA==.Neider:BAAALAAECgMIAwAAAA==.Netas:BAAALAAECgUIBwAAAA==.',Ni='Nibler:BAAALAADCggIEAAAAA==.Niko:BAAALAAECgQICAAAAA==.Nimrohd:BAAALAAECgUICwAAAA==.Nirmal:BAAALAADCgEIAQAAAA==.',No='Norr:BAAALAADCgEIAQAAAA==.',['Nî']='Nîcôn:BAAALAADCgEIAQAAAA==.',['Nü']='Nüwú:BAAALAAECgIIAgAAAA==.',Ok='Okami:BAAALAAECgEIAQAAAA==.Okeanos:BAAALAAECgUICgAAAA==.',['Oâ']='Oâsis:BAAALAAECgMIAwAAAA==.',Pa='Paenumbra:BAAALAAECgMIBQAAAA==.Palacios:BAAALAADCgcIBwAAAA==.Pandacetamol:BAAALAAECgcIEAAAAA==.Pandôrrá:BAAALAADCgMIAwABLAADCggIFgABAAAAAA==.Paro:BAAALAAECgYICAAAAA==.Patches:BAAALAADCgQIBAAAAA==.',Pe='Peaches:BAAALAADCgYIBgAAAA==.',Ph='Phôênix:BAAALAAECgEIAQAAAA==.',Pi='Pirak:BAAALAAECgQIBQAAAA==.',Po='Ponylol:BAAALAADCgYICwABLAAECgEIAQABAAAAAA==.',Pu='Puddinglol:BAAALAAECgEIAQAAAA==.',Py='Pyon:BAAALAAECgMIBQAAAA==.',['Pâ']='Pândemonium:BAAALAAECgEIAQAAAA==.',['Pê']='Pêanutbutter:BAAALAADCggIEgABLAADCggIFgABAAAAAA==.',Qu='Qulsic:BAAALAAECgMIBgAAAA==.',Ra='Rahnen:BAAALAADCggIDwAAAA==.Rakójenkins:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Raski:BAAALAAECgIIAwAAAA==.Rayadz:BAAALAADCggIFwAAAA==.',Re='Rekhodiah:BAAALAAECgMIBAAAAA==.Rengan:BAAALAAECgMIBgAAAA==.',Ro='Rollga:BAAALAAECgMIAwAAAA==.Roobird:BAAALAADCggICAAAAA==.Rosalee:BAAALAAECgcIEAAAAA==.Rotdrache:BAAALAADCgIIAgAAAA==.',Ru='Rushhour:BAABLAAECoEXAAICAAgIvCOqAAAkAwACAAgIvCOqAAAkAwAAAA==.',Ry='Rylona:BAAALAAECgUIAwAAAA==.',['Ré']='Réngàn:BAAALAADCgcICAAAAA==.',Sa='Sacurafee:BAAALAADCgQIAwAAAA==.Sadoriâ:BAAALAADCggIDwAAAA==.Sajurie:BAAALAAECgUICQAAAA==.Saoirsé:BAAALAAECgcIDwAAAA==.Sarki:BAAALAADCgQIBAAAAA==.Saronia:BAAALAADCgcICgAAAA==.',Sc='Schandru:BAAALAAECgIIAgAAAA==.Schelli:BAAALAAECgEIAQAAAA==.Schmierfuß:BAAALAADCgYICQAAAA==.',Se='Serraria:BAAALAADCgcIDAAAAA==.Sevara:BAAALAADCgcIDgAAAA==.',Sh='Shaimji:BAAALAADCgIIAgAAAA==.Shanteya:BAAALAADCgcIDgAAAA==.Sharkzqt:BAAALAADCgEIAQAAAA==.Shieldlady:BAAALAAECgIIAgAAAA==.Shisuna:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.Shivera:BAAALAAECgIIAgAAAA==.Shôckwave:BAAALAADCggIDwAAAA==.',Si='Sianra:BAAALAADCgcIBwABLAAECggIDAABAAAAAA==.',Sk='Skorpien:BAAALAAECgEIAQAAAA==.Skurilla:BAAALAAECgcIDAAAAA==.',Sl='Slarti:BAAALAAECgEIAQAAAA==.',Sm='Smeemie:BAAALAADCggICAABLAADCggIDgABAAAAAA==.',So='Solan:BAAALAADCgUIBQAAAA==.Songôku:BAAALAAECgEIAQAAAA==.',Sp='Spiritreaper:BAAALAADCggICQAAAA==.',St='Streuselchen:BAAALAAECgUICAAAAA==.Sturmlord:BAAALAAECgcIEAAAAA==.',Su='Supahfly:BAAALAAECggIBQAAAA==.Sushima:BAAALAAECgcIEAAAAA==.Suusi:BAAALAADCgcIBwAAAA==.',Sy='Sydana:BAAALAADCggIDgABLAAECgYICgABAAAAAA==.Syndica:BAAALAADCgYIBwAAAA==.Syranie:BAAALAAFFAEIAQAAAA==.',Ta='Talarockdh:BAAALAADCgMIAwAAAA==.Talim:BAAALAAECgMIAwAAAA==.Tareth:BAAALAAECgEIAQAAAA==.Targin:BAAALAADCggICAAAAA==.',Te='Terra:BAAALAADCggIEgAAAA==.',Th='Thegreenone:BAAALAAECgcIDgAAAA==.Thorbald:BAAALAAECgEIAQAAAA==.Thorz:BAAALAADCgQIBAAAAA==.Thranôr:BAAALAADCgcIBwAAAA==.Throloasch:BAAALAADCggICAAAAA==.Thundor:BAAALAAECggIEgAAAA==.',Ti='Tiarake:BAAALAADCgcIBwAAAA==.Tirus:BAAALAADCgMIAwAAAA==.Tiyanak:BAAALAADCggIEAAAAA==.',To='To:BAAALAAECgUIBQAAAA==.Toho:BAAALAAECgUICAAAAA==.Tonia:BAAALAAECgcIEAAAAA==.Touch:BAAALAADCggICAABLAAFFAIIBAABAAAAAA==.',Tw='Twissi:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',['Tô']='Tôhr:BAAALAADCggICwAAAA==.',['Tø']='Tøry:BAAALAADCgcIBwAAAA==.',Un='Ungoy:BAAALAADCggICAAAAA==.',Ve='Ventrax:BAAALAAECgcIDgAAAA==.',Vi='Virikas:BAAALAAECgcIEAAAAA==.',Vo='Voodoomedic:BAAALAAECgcIBwAAAA==.',Vu='Vulpi:BAAALAADCggIDAAAAA==.',Wa='Wanebi:BAAALAAECgYIBgAAAA==.Warrcrex:BAAALAAECgYICAAAAA==.',Wh='Whisch:BAAALAAECgMIBgAAAA==.',Wi='Wienix:BAAALAAECgIIAgAAAA==.',Wr='Wreckquiem:BAAALAAECgMIBAAAAA==.',Wu='Wusseltwo:BAAALAAECgIIAgAAAA==.',Wy='Wynne:BAAALAADCgYIBgAAAA==.',['Wä']='Wächterathen:BAAALAAFFAIIAgAAAA==.',Xa='Xaruria:BAAALAAECgEIAQAAAA==.',Xi='Xiara:BAAALAADCgUIBQAAAA==.Xiaufu:BAAALAADCgIIAgABLAAECggIDAABAAAAAA==.Xilu:BAAALAAECgMIBQAAAA==.',Ye='Yeree:BAAALAADCgYIBgAAAA==.',Yo='Yorndar:BAAALAADCgcIBwAAAA==.',Yu='Yuriká:BAAALAADCgcIBwAAAA==.Yuukî:BAAALAADCgcIDgAAAA==.',Za='Zapzarrapp:BAAALAADCggIFQAAAA==.',Ze='Zern:BAAALAADCgcIEgAAAA==.',Zh='Zhaabis:BAAALAAECggICQAAAA==.',Zi='Zino:BAAALAADCggICAAAAA==.',Zm='Zmokey:BAAALAADCgQIBAAAAA==.',Zo='Zourâ:BAAALAADCggIFgAAAA==.',['Zê']='Zêcks:BAAALAADCgYIBgAAAA==.',['Óg']='Óga:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end