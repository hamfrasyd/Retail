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
 local lookup = {'Unknown-Unknown','Rogue-Outlaw','Hunter-BeastMastery','Priest-Holy','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Evoker-Devastation','DeathKnight-Frost','DemonHunter-Havoc',}; local provider = {region='EU',realm='Gilneas',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adamantina:BAAALAAECgcIEwAAAA==.Adelmute:BAAALAAECgMIAwAAAA==.Adorabel:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Adrazil:BAAALAAECgYICwAAAA==.Adriella:BAAALAAECgIIAgAAAA==.',Ae='Aelena:BAAALAADCggIDQAAAA==.',Ak='Akui:BAAALAAECgEIAQAAAA==.',Al='Alaric:BAAALAADCggICAAAAA==.Alukarl:BAAALAAECgUIBQAAAA==.',Am='Amaly:BAAALAAECgYICQAAAA==.Amando:BAAALAADCgYIBgAAAA==.Amathalarus:BAAALAAECgMIAwAAAA==.Amokio:BAAALAAECgQICAAAAA==.',An='Anco:BAAALAADCggIEAAAAA==.Andiray:BAAALAADCgcIBwAAAA==.Angaráto:BAAALAAECgUIBwABLAAECggIFgACAGYiAA==.Annageddon:BAAALAAECgMIAwAAAA==.Anubilia:BAAALAADCgcICwABLAADCgcIEgABAAAAAA==.Anubit:BAAALAAECgMIBgAAAA==.',Ap='Apfelmusmann:BAAALAAECgUICAAAAA==.',Ar='Arthaz:BAAALAAECgcIEAAAAA==.Artikon:BAAALAAECgUICAAAAA==.',As='Asmavaeth:BAAALAAECgIIAgAAAA==.Astmatiker:BAAALAADCggICgAAAA==.',At='Attilla:BAAALAAECggICAAAAA==.',Au='Aureliá:BAAALAADCgcIBwAAAA==.',Av='Avaloniâ:BAAALAAECgEIAQAAAA==.Aveeny:BAAALAAECgcIDwAAAA==.Avri:BAAALAADCggICAAAAA==.',Aw='Awanatá:BAAALAAECgEIAQABLAAECgEIAgABAAAAAA==.',Ay='Aylea:BAAALAADCgcIBQAAAA==.',Ba='Backferry:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Bakui:BAAALAAECgMIAwAAAA==.Bandits:BAAALAADCgEIAQAAAA==.Bartkor:BAAALAAECgQIBgAAAA==.',Be='Bearforzeone:BAAALAAECgQIBAAAAA==.Beastman:BAAALAAECgMIBAAAAA==.Belofar:BAAALAAECgEIAQABLAAECgcIEQABAAAAAA==.Benjolo:BAAALAAECgEIAQAAAA==.Betsy:BAAALAAECgEIAQAAAA==.',Bi='Bigbass:BAAALAADCgMIAwAAAA==.Birma:BAAALAADCgcIDAAAAA==.Birta:BAAALAAECgcIEAAAAA==.',Bl='Blackdone:BAAALAADCggICAAAAA==.Bloodycruel:BAAALAADCggICAAAAA==.Bluughhunt:BAABLAAECoEUAAIDAAcIyB6GEAB5AgADAAcIyB6GEAB5AgAAAA==.',Bo='Boese:BAAALAAECgIIAgAAAA==.Borenzo:BAAALAADCgYICQAAAA==.Bottrom:BAAALAAECgYICQAAAA==.',Br='Brók:BAAALAAECgEIAQAAAA==.',Bu='Bubbletogo:BAAALAADCgcIBwAAAA==.Buberella:BAAALAAECgIIAgAAAA==.Bunnyhop:BAAALAADCggIFAAAAA==.Bunnymädchen:BAAALAADCgcIDAAAAA==.',By='By:BAAALAADCgYIBwAAAA==.',Ca='Cascada:BAABLAAECoEVAAIEAAgIIx8qBQDqAgAEAAgIIx8qBQDqAgAAAA==.Casnar:BAAALAADCggICAAAAA==.Castellock:BAABLAAECoEXAAQFAAgIahlFFgAkAgAFAAcIjBhFFgAkAgAGAAUI6xmjHgBxAQAHAAEIPw8VKwBIAAAAAA==.',Ce='Ceelia:BAAALAAECgYICQAAAA==.Cellypatch:BAAALAADCggICAAAAA==.',Ch='Changes:BAAALAADCgcICwAAAA==.Chaosben:BAAALAADCggICAABLAAECgUIBQABAAAAAA==.Cheri:BAAALAAECgIIBAAAAA==.Chewi:BAAALAADCgcIDQAAAA==.Châru:BAAALAADCgIIAgABLAADCggIDAABAAAAAA==.Chízú:BAAALAADCgEIAQAAAA==.',Ci='Ciarra:BAAALAAECgMIAwAAAA==.',Cl='Clangedin:BAAALAADCgcIDAAAAA==.Clira:BAAALAADCgcIFQAAAA==.',Co='Controlled:BAAALAAECgYICQAAAA==.Coínflip:BAAALAADCggICAAAAA==.',Cr='Cricx:BAAALAAECgUIBgAAAA==.',['Câ']='Cârl:BAAALAAECgYIBgAAAA==.',Da='Dakarion:BAAALAAECgMIBwAAAA==.Danielo:BAAALAADCggICAAAAA==.Darelien:BAAALAAECgYICQAAAA==.Dariarona:BAAALAADCgcIBwAAAA==.Darksel:BAAALAADCgcIBwAAAA==.',Dh='Dhazeria:BAAALAAECgYICQAAAA==.Dhukai:BAAALAAECgEIAQAAAA==.',Di='Disasterpice:BAAALAADCggIEAAAAA==.',Dj='Djarin:BAAALAAECgYIDgAAAA==.',Do='Donkaybong:BAAALAADCgcICgAAAA==.',Dr='Dracthyrian:BAAALAAECggICAAAAA==.Drakania:BAAALAAECgIIAgAAAA==.Dranhey:BAAALAADCgcIBwAAAA==.Dreist:BAAALAADCgYIBgAAAA==.Dreyken:BAAALAADCgcIBwAAAA==.Driz:BAAALAAECgYICQAAAA==.Drracona:BAAALAADCggIDwAAAA==.',Ds='Dschaffar:BAAALAAECgcIEAAAAA==.',['Dê']='Dêrg:BAAALAADCgEIAQAAAA==.',Ea='Eamane:BAAALAADCggIDwABLAADCggIFAABAAAAAA==.',Ec='Ecural:BAAALAAECgcIEAAAAA==.',El='Eldaroth:BAAALAADCgYIBgAAAA==.Element:BAAALAADCgUIBQAAAA==.',Er='Eroica:BAAALAAECgMIBgAAAA==.',Ev='Evángelos:BAAALAADCggIEAAAAA==.',Ex='Exoduz:BAAALAAECgcIBwABLAAECgcIFAADAMgeAA==.Exoma:BAAALAADCggIDwAAAA==.',Ez='Ezrì:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.',Fa='Faelas:BAABLAAECoEVAAIIAAgIqxZeGwA3AgAIAAgIqxZeGwA3AgAAAA==.',Fe='Feadale:BAAALAADCggIFwAAAA==.Feuerdráche:BAAALAADCgcIBwAAAA==.Feurouge:BAAALAADCggIDgAAAA==.',Fi='Firetropi:BAAALAADCgMIAwAAAA==.Firion:BAAALAADCggIDwAAAA==.Fistr:BAAALAAECgMIBwAAAA==.',Fl='Floresthan:BAAALAAECgYICAAAAA==.',Fo='Fourcheese:BAAALAADCgcIDgAAAA==.',Fu='Fullin:BAAALAADCggICQABLAAECgYIDQABAAAAAA==.',Fy='Fyona:BAAALAADCgcIBwAAAA==.',Ga='Galfa:BAAALAAECgIIAgABLAAECggIFgACAGYiAA==.Gamarona:BAAALAAECgcIBwAAAA==.Gandoro:BAAALAAECgIIAwAAAA==.',Ge='Gearboltless:BAAALAAECgIIAgAAAA==.Geist:BAAALAADCggICAAAAA==.',Gh='Ghazkull:BAAALAAECgYIDgAAAA==.',Gi='Ginora:BAAALAADCggICAAAAA==.',Gl='Glemgor:BAAALAAECgYIBgAAAA==.',Gn='Gnexmex:BAAALAADCggIEAAAAA==.',Go='Goggon:BAAALAADCgEIAQAAAA==.Golddorn:BAAALAADCggIFgAAAA==.Gondolin:BAAALAADCggIEAAAAA==.Goroth:BAAALAADCgEIAQAAAA==.',Gr='Greenerina:BAAALAADCgcIEQAAAA==.Greenhorn:BAAALAAECgIIAgAAAA==.Gremgar:BAAALAAECgIIAgAAAA==.Grischnax:BAAALAADCgUIBQAAAA==.Grixis:BAAALAADCgcIBwAAAA==.',Gu='Gulthar:BAAALAADCgYICQAAAA==.Gundaar:BAAALAADCggIEAAAAA==.',['Gü']='Güldenstar:BAAALAAECgcIEAAAAA==.',Ha='Hanar:BAAALAADCggIDwAAAA==.Hanfpalme:BAAALAADCgMIBQAAAA==.Hannelori:BAAALAAECggICAAAAA==.Hardès:BAAALAAECgQIBwAAAA==.Harpyie:BAAALAADCgYIBgAAAA==.',He='Heraa:BAAALAADCggICAAAAA==.',Hu='Huntinghexer:BAAALAAECgYIBgAAAA==.Huntingwarr:BAAALAAFFAIIAwAAAA==.',Hy='Hymai:BAAALAADCgYIDQAAAA==.',Ik='Iknow:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Im='Imgral:BAAALAADCggICAAAAA==.Imgrîmmsch:BAAALAADCggIEAAAAA==.',In='Inosan:BAAALAAECgYICQAAAA==.',Is='Iskeria:BAAALAAECgMIBAAAAA==.',It='Itzwarlock:BAAALAAECgYICgAAAA==.',Ji='Jinora:BAAALAAECgcIDQAAAA==.Jinoryn:BAAALAADCgMIAwAAAA==.',Jo='Jordahn:BAAALAADCgcIBwAAAA==.Joý:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',Ju='Juren:BAAALAADCggIFAAAAA==.',['Já']='Jáde:BAAALAADCggIFQAAAA==.',Ka='Kaav:BAAALAADCggICQAAAA==.Kadaj:BAAALAAECgEIAQAAAA==.Kailyna:BAAALAAECgUICQABLAAECgcIEQABAAAAAA==.Kalego:BAAALAADCggIDwAAAA==.Kaltilover:BAAALAADCgcICwAAAA==.Kampfkecks:BAAALAADCggICQAAAA==.Kampfzicke:BAAALAADCgcIBwAAAA==.Kaschira:BAAALAAECgMIAwAAAA==.Kazonk:BAAALAADCggIEAAAAA==.Kaztay:BAAALAAECgYICQAAAA==.',Ke='Kesara:BAAALAADCgEIAQAAAA==.',Kh='Khélgrar:BAAALAADCgIIAgAAAA==.',Ki='Kickingwicky:BAAALAADCgUIBQAAAA==.Kijan:BAAALAADCggIFwAAAA==.Killertaps:BAAALAADCggIFAAAAA==.Killoster:BAAALAADCggICAAAAA==.Killyoufast:BAAALAAECgYIDgAAAA==.Kishra:BAAALAADCgYIBgAAAA==.Kitkat:BAAALAADCggIDQAAAA==.',Kl='Kleener:BAAALAADCggIFgAAAA==.Klopriest:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.',Kr='Kregan:BAAALAAECgYICQAAAA==.Kriad:BAAALAAECgIIAgAAAQ==.',Ku='Kukie:BAAALAADCgUIBwAAAA==.Kurzvorelf:BAAALAAECggICAAAAA==.Kushiel:BAAALAAECgYICQAAAA==.',['Ké']='Kélath:BAAALAAECgYICQAAAA==.',['Kú']='Kú:BAAALAADCgcIBwAAAA==.',La='Lagerthå:BAAALAAECgYICwAAAA==.',Le='Leeju:BAAALAAECggIDgAAAA==.Legaia:BAAALAADCggICQAAAA==.Leva:BAAALAAECgEIAQAAAA==.',Li='Liath:BAAALAAECgYICQAAAA==.Littleham:BAAALAAECgMIBAAAAA==.Littlesanny:BAAALAADCgYIBgAAAA==.Livor:BAAALAADCgMIAwAAAA==.',Ll='Llondor:BAAALAADCggIDwAAAA==.Lloth:BAAALAAECgMIBgAAAA==.Llunafey:BAAALAAECgIIAgAAAA==.',Lo='Logaris:BAAALAADCggIFgAAAA==.Looti:BAAALAADCggIBwAAAA==.Lophera:BAAALAAECgMIAwAAAA==.',Ly='Lyssia:BAAALAAECgYICQAAAA==.Lyxiana:BAAALAAECgMIBgAAAA==.',Ma='Madclaw:BAAALAADCgcIBwABLAADCggIFAABAAAAAA==.Magdablair:BAAALAADCggIDwAAAA==.Maloj:BAAALAAECgIIAwAAAA==.Marius:BAAALAAFFAIIAwAAAA==.Mathi:BAAALAAECgMIAwAAAA==.',Me='Mellificent:BAAALAAECgMIAwAAAA==.Menion:BAAALAADCgMIAwAAAA==.Meradan:BAAALAADCggIDwAAAA==.',Mo='Monkni:BAAALAADCgUIBQAAAA==.Monuky:BAAALAADCggIFgAAAA==.Mopso:BAAALAADCgcIBwAAAA==.Mordak:BAAALAAECgcIDwAAAA==.Moriliath:BAAALAAECgQIBAAAAA==.',Mu='Muckslix:BAAALAAECgYICAAAAA==.Murkyy:BAAALAAECgMIBgAAAA==.Murmalinator:BAAALAADCggIEwAAAA==.Musaschi:BAAALAAECgEIAQAAAA==.',My='Myrîel:BAAALAADCggICAAAAA==.',['Mâ']='Mâmâ:BAAALAAECgYIDAAAAA==.Mâzaky:BAAALAADCggIEAAAAA==.',Na='Nabucco:BAAALAAECgcIBwAAAA==.Namirja:BAAALAADCggIFAAAAA==.Namorâ:BAAALAADCgEIAQAAAA==.Nasgor:BAAALAADCgYIBgAAAA==.Navily:BAAALAADCgMIAwABLAAECgYIDQABAAAAAA==.',Ne='Neffelum:BAAALAAECgMIBQAAAA==.Neleneue:BAAALAADCgcICgAAAA==.Nelia:BAAALAAECgIIAgAAAA==.',Ni='Niaolong:BAAALAADCgcIBwAAAA==.Niemert:BAAALAADCggIEwAAAA==.Nilrai:BAAALAADCgIIAgAAAA==.Nirn:BAAALAAECgMIAwAAAA==.',Nu='Nu:BAAALAADCgcIBwAAAA==.',Ny='Nybalde:BAAALAAECgIIAgAAAA==.',Od='Odin:BAAALAAECgUICAAAAA==.',Og='Ogtar:BAAALAAECgMIBAAAAA==.',Ok='Oktaviaklaud:BAAALAADCgMIAwAAAA==.',Ou='Outdunit:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.',Pa='Painrezepte:BAAALAADCgQIBgAAAA==.Palagoh:BAAALAAECgYIBgAAAA==.Paldette:BAAALAAECgEIAQAAAA==.Pallando:BAAALAADCgcIDQAAAA==.Pangea:BAAALAAECgMIAwAAAA==.',Ph='Phenom:BAAALAADCggIFAAAAA==.Phynadrea:BAAALAAECgcIDwAAAA==.Phönìx:BAAALAADCggIBgAAAA==.',Pi='Pieps:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.',Po='Pocket:BAAALAAECgQIBAAAAA==.',Pr='Pronos:BAAALAADCggIDwAAAA==.',Ps='Psycholaus:BAAALAAECgUICQAAAA==.',Pu='Puddles:BAAALAADCgEIAQABLAAECgYIBwABAAAAAA==.Puschyevoker:BAABLAAECoEZAAIJAAcIAxZHEQAFAgAJAAcIAxZHEQAFAgABLAAECggIKQAKACwXAA==.Puschymonk:BAAALAAECgcIEAABLAAECggIKQAKACwXAA==.Puschypríest:BAAALAAECgEIAQABLAAECggIKQAKACwXAA==.',Py='Pythonissam:BAAALAADCggICAAAAA==.',['Pé']='Péach:BAAALAAECgEIAQAAAA==.',Qu='Quantice:BAAALAADCgIIAgABLAADCgMIAwABAAAAAA==.',Ra='Ragnos:BAAALAAECgMIAwAAAA==.Randîr:BAAALAAECgEIAQAAAA==.Raziel:BAAALAADCggICAAAAA==.Razzha:BAAALAAECgUICQAAAA==.',Re='Reginaris:BAAALAADCgUIBQAAAA==.Reksai:BAAALAAECgEIAQAAAA==.',Ri='Ridieck:BAAALAAECgMIAwAAAA==.Rilmeya:BAAALAADCgcIEwAAAA==.',Ro='Roidmuncher:BAAALAADCgcICwAAAA==.Rosi:BAAALAAECgMIAwAAAA==.',['Ré']='Rééd:BAAALAADCgEIAQAAAA==.',['Rî']='Rînø:BAAALAAECgIIAgAAAA==.',Sa='Sahif:BAABLAAECoEUAAILAAcIMxr8GgA9AgALAAcIMxr8GgA9AgAAAA==.Saintlucifer:BAAALAADCgYIBgAAAA==.Sakajo:BAAALAADCggICwAAAA==.Sakirya:BAAALAAECgYICgAAAA==.Salemon:BAAALAAECggICAAAAA==.Salinâ:BAAALAAECgMIBAAAAA==.Sam:BAAALAADCggIDwAAAA==.Sanaru:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.Sarjna:BAAALAADCggIEwAAAA==.Sarumara:BAAALAADCggICAAAAA==.Sayacia:BAAALAADCggICAAAAA==.',Sc='Schlossoline:BAAALAADCggICQAAAA==.Schnikschnak:BAAALAAECgMIBAAAAA==.',Se='Seni:BAAALAAECgYICAAAAA==.Seviya:BAAALAAECgUIBQAAAA==.',Sh='Shadowbear:BAAALAADCggIEAAAAA==.Shakui:BAAALAAECgMIBQAAAA==.Shamanlenin:BAAALAAECgQIBAAAAA==.Shame:BAAALAAECgMIBAAAAA==.Sheltera:BAAALAAECgIIBAAAAA==.Shenyo:BAAALAADCggIEAAAAA==.Shiokekw:BAAALAADCgQIBAAAAA==.Shizzy:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Shoriah:BAAALAADCgQIBAAAAA==.Shìo:BAAALAAFFAIIAgAAAA==.',Si='Sid:BAAALAADCgcIEgAAAA==.Simsalaknall:BAAALAADCgUIAwAAAA==.Sinestra:BAAALAAECgYICQABLAAECgYICwABAAAAAA==.Sinta:BAAALAAECgMIBAAAAA==.Sister:BAAALAADCgUIBQAAAA==.Sixdrtydix:BAAALAAECgYIDgAAAA==.Sixvaadoo:BAAALAAECgQICAAAAA==.',Sk='Skie:BAAALAAECgYICQAAAA==.Skîndred:BAAALAAECgcICwAAAA==.',Sl='Slomodemon:BAAALAAECgYIDgAAAA==.Slomophob:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Sluagh:BAAALAADCggIDAAAAA==.Slîce:BAAALAADCgcIBwAAAA==.',Sn='Snuden:BAAALAAECgEIAQABLAAECgYIDgABAAAAAA==.',So='Softmage:BAAALAADCgcIDAAAAA==.Soirella:BAAALAADCggIEQAAAA==.Solandra:BAAALAADCggIDwAAAA==.Somira:BAAALAAECgEIAQAAAA==.Soni:BAAALAAECgIIAgAAAA==.Sooli:BAAALAADCggIEAAAAA==.Sorn:BAAALAADCgQIBAAAAA==.Sorren:BAAALAADCggIEwAAAA==.Sowen:BAAALAAECgYICQAAAA==.',St='Steve:BAAALAAECgcIEAAAAA==.Storolfsson:BAAALAAECgMIBgAAAA==.Stuppz:BAAALAAECgYIBwAAAA==.Styles:BAAALAAECgMIBwABLAAECgYICgABAAAAAA==.',Sy='Syrakus:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.',['Sâ']='Sânsibar:BAAALAADCggICAAAAA==.Sârphina:BAAALAAECgMIAwAAAA==.',['Sí']='Sílina:BAAALAADCggIFwAAAA==.',Ta='Taja:BAAALAADCggICAAAAA==.Tamaki:BAAALAADCggIFwABLAAECgYICgABAAAAAA==.Tankerella:BAAALAAECgYICwAAAA==.Tarijin:BAAALAAECgMIBAAAAA==.',Te='Terrence:BAAALAADCggIEAAAAA==.',Th='Thalron:BAAALAADCggIDwAAAA==.Tharom:BAAALAAECgMIAwAAAA==.Thheerryy:BAAALAAECgYIBgAAAA==.Thimorias:BAAALAAECgEIAQAAAA==.Thékron:BAAALAAECgYIBwAAAA==.',Ti='Tierlieb:BAAALAAECgcIEAAAAA==.Tintaa:BAAALAADCgUIBQAAAA==.Tipsey:BAAALAADCggICAAAAA==.',To='Tobin:BAAALAAECgcIEAAAAA==.Totemine:BAAALAADCgcIEQAAAA==.Totemtom:BAAALAADCgcIEgAAAA==.',Tr='Traktôr:BAAALAADCggICAABLAADCggIDAABAAAAAA==.Trashly:BAAALAAECgYIDQAAAA==.Treamon:BAAALAAECgUIBgAAAA==.Trkzn:BAAALAAECgUIBgAAAA==.',Tu='Tulana:BAAALAADCggIFAAAAA==.Turosto:BAAALAAECgYICQAAAA==.',Ty='Tyramon:BAAALAADCggICAAAAA==.Tyranion:BAAALAAECgcIEAAAAA==.',Un='Ungeimpft:BAAALAADCggIEAAAAA==.',Ur='Uraraka:BAAALAADCgcIBwAAAA==.',Va='Vandania:BAAALAAECgIIAgAAAA==.Vanhagen:BAAALAAECgcIEQAAAA==.Vanhelsingii:BAAALAADCgEIAQAAAA==.',Vc='Vchronic:BAAALAADCggICAAAAA==.',Ve='Velarias:BAAALAADCgEIAQAAAA==.Venatri:BAAALAADCgcIBwAAAA==.Vengahl:BAAALAAECgEIAQAAAA==.',Vi='Viore:BAAALAADCggIDwABLAAECgYICwABAAAAAA==.',Vu='Vuh:BAAALAAECgcIDQAAAA==.',Wa='Waldhexe:BAAALAAECggICwAAAA==.Waytheah:BAAALAAECgEIAgAAAA==.',We='Weewoo:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.',Wi='Willibald:BAAALAADCggIFwAAAA==.',Wo='Wolfschwanz:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Worgtamer:BAAALAAECgUIBQAAAA==.',Wr='Wryn:BAAALAAECgYIBgAAAA==.',Wu='Wuschelstern:BAAALAADCgcIDAAAAA==.',Xa='Xaraxi:BAAALAAECgMIAwABLAAECgcIFAADAIIfAA==.',Xo='Xorath:BAAALAAECgEIAQAAAA==.',Xy='Xylone:BAAALAADCggICQAAAA==.',['Xé']='Xéró:BAAALAAECgEIAQAAAA==.',Ye='Yedrin:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Yh='Yharana:BAAALAADCgMIAwAAAA==.',Yi='Yithra:BAABLAAECoEWAAICAAgIZiK1AAAVAwACAAgIZiK1AAAVAwAAAA==.',Yo='Youaredead:BAAALAADCggICwAAAA==.',Yu='Yukimaru:BAAALAADCggICAAAAA==.',Za='Zahar:BAAALAADCgcIBwAAAA==.Zakkusu:BAAALAAECgMIBAABLAAECgcIEQABAAAAAA==.Zandahli:BAAALAADCgEIAQABLAAECgYICQABAAAAAA==.Zaríma:BAAALAADCgYIBgAAAA==.Zass:BAAALAADCggIFgABLAAECgYIDQABAAAAAA==.',Ze='Zepharus:BAAALAAECgYIDQAAAA==.Zeratule:BAAALAAECgUIBQAAAA==.Zerdales:BAAALAADCgYIBgAAAA==.',Zo='Zorr:BAAALAAECgYIDQAAAA==.',Zu='Zuchiku:BAAALAAECgMIBAAAAA==.Zundhöuzli:BAAALAADCggIDAAAAA==.',['Àr']='Àrios:BAAALAADCggIEwAAAA==.',['Òd']='Òdi:BAAALAAECgYICwAAAQ==.',['Õk']='Õk:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end