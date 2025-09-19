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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','Shaman-Restoration','Warlock-Destruction',}; local provider = {region='EU',realm='Baelgun',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aarie:BAAALAADCggIFAAAAA==.',Ab='Abby:BAAALAADCggIDAAAAA==.',Ag='Aggronator:BAAALAADCgYICQAAAA==.',Ah='Ahrgó:BAAALAAECgIIAgAAAA==.',Al='Alarjin:BAAALAAECgQIBwAAAA==.Alexis:BAAALAADCgYIBgAAAA==.Allvater:BAAALAADCgIIAgAAAA==.Alïsa:BAAALAAECgYIDgAAAA==.',Am='Ambulanz:BAAALAAECgEIAQAAAA==.Amirii:BAAALAAECgQIBgAAAA==.',An='Anastasyá:BAAALAAECgMIAwAAAA==.Ancilla:BAAALAADCgYICAAAAA==.Animàl:BAAALAADCgEIAQAAAA==.Annunaki:BAAALAADCggIEAAAAA==.Anoriel:BAAALAADCggIDwAAAA==.Ansotíca:BAAALAAECgEIAgAAAA==.Antarya:BAAALAAECgMIAwABLAAECgUICQABAAAAAA==.',As='Aseya:BAAALAAECgQIBAAAAA==.Ashinna:BAAALAADCgQIBAAAAA==.',Az='Azran:BAAALAADCgcIBwAAAA==.Azurglut:BAAALAADCgIIAgAAAA==.',Be='Beasticus:BAAALAADCgcIEgAAAA==.Belpherus:BAAALAAECgUICQAAAA==.Bendrin:BAAALAAECgEIAQAAAA==.',Bi='Bigevil:BAAALAADCggIBwAAAA==.Birtches:BAAALAADCgQIBAAAAA==.',Bl='Blackhexer:BAAALAAECgEIAQAAAA==.Blaise:BAAALAADCggIFgAAAA==.Bleakness:BAAALAAECgMIBwAAAA==.Blitzfalke:BAAALAADCgcIBwAAAA==.Bluespark:BAAALAAECgYIBgAAAA==.Bluteria:BAAALAAECgMIAwAAAA==.',Bo='Bomba:BAAALAADCggIEgAAAA==.',Br='Brang:BAAALAADCgcIDQAAAA==.Breef:BAAALAADCggIFgAAAA==.Brunt:BAAALAADCggICAAAAA==.',['Bá']='Bárbarella:BAAALAADCgUIBgAAAA==.',Ca='Cantouchthis:BAABLAAECoEVAAICAAgI4iK0CwC2AgACAAgI4iK0CwC2AgAAAA==.Carbonara:BAAALAAECgEIAQABLAAECgYIDgABAAAAAA==.Castiella:BAAALAAECgUIBQABLAAECgUICgABAAAAAA==.Catarrhini:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.',Ch='Chabo:BAAALAAECgIIAgAAAA==.Chaosmagier:BAAALAAECgMIAwAAAA==.Chast:BAAALAADCgIIAgAAAA==.Chihiro:BAAALAAECgUICgAAAA==.Chiori:BAAALAADCggIEgAAAA==.Chochang:BAAALAADCggICAAAAA==.Chumana:BAAALAADCggIEAAAAA==.',Cr='Crichton:BAAALAAECgYIDwAAAA==.',Cy='Cybercooky:BAAALAADCgIIAgAAAA==.',Da='Dabby:BAAALAADCgcIEAAAAA==.Dalma:BAAALAAECgUIBwAAAA==.Darkdestiny:BAAALAADCggICAAAAA==.Darkmouth:BAAALAADCgYICQAAAA==.Darthgustel:BAAALAADCgcIBwAAAA==.',De='Derweißè:BAAALAADCgUIBQAAAA==.Devrim:BAAALAAECgEIAQAAAA==.',Do='Donnerknolle:BAAALAADCgUIBQAAAA==.Dorgun:BAAALAAECgQIBAABLAAECgYIDwABAAAAAA==.Dovarius:BAAALAADCgQIBAAAAA==.',Dr='Drakas:BAAALAADCgcICAAAAA==.Dralgar:BAAALAAECgYIDwAAAA==.Dreadbringer:BAAALAAECgUIBwAAAA==.',Du='Dungo:BAAALAAECgQIBQAAAA==.',['Dä']='Dämom:BAAALAADCgYIBgAAAA==.',Ea='Eaglehorn:BAAALAADCgcICQABLAADCggIEgABAAAAAA==.',El='Elanya:BAAALAAECgUICQAAAA==.Elanía:BAAALAADCggICAAAAA==.Elerias:BAAALAAECgEIAQAAAA==.Ellanis:BAAALAADCggICAAAAA==.Elmentra:BAAALAADCggIFQAAAA==.Elosary:BAAALAADCgEIAQAAAA==.Elyth:BAAALAADCgQIBAAAAA==.',Em='Emorii:BAAALAAECgIIAgAAAA==.',Eq='Equinoxia:BAAALAADCgYIBgAAAA==.Equis:BAAALAAECgUICQAAAA==.',Es='Espressasino:BAAALAAECgEIAQAAAA==.',Et='Etheria:BAAALAAECgQIBwAAAA==.',Eu='Eupaisia:BAAALAAECgMIBQAAAA==.',Ev='Everend:BAAALAAECgIIAgAAAA==.',Fa='Famo:BAAALAADCgcIBwAAAA==.Faran:BAAALAAECgEIAQAAAA==.',Fe='Fengyu:BAAALAAECgMIAwAAAA==.Fenrir:BAAALAAECgYICwAAAA==.Ferrin:BAAALAAECgYIBgAAAA==.',Fl='Flauschilein:BAAALAAECgcICQAAAA==.Flintenuschi:BAAALAADCgQIBwAAAA==.',Fo='Foxit:BAAALAADCggIDgAAAA==.',Fr='Fraubesen:BAAALAAECgUICgAAAA==.Frózén:BAAALAADCgcIDQAAAA==.',Fu='Furorio:BAAALAAECgEIAQAAAA==.',Fy='Fynderis:BAAALAAECgYIBgAAAA==.',Ga='Ganjubas:BAAALAAECgMIBAAAAA==.',Ge='Getrunken:BAAALAADCgQIBAAAAA==.',Gl='Glevenluna:BAAALAAECgUIBwAAAA==.',Gr='Greatmage:BAAALAADCgcIDQAAAA==.Grimbur:BAAALAAECgIIAgAAAA==.',Ha='Haines:BAAALAADCggIEgAAAA==.Halphas:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.',['Hä']='Hässlichekuh:BAAALAAECgYIDgAAAA==.',['Hê']='Hêstiâ:BAAALAAECgIIAgAAAA==.',Ib='Ibus:BAAALAADCggICAAAAA==.',Ig='Ignia:BAAALAAECgcIDwAAAA==.',Il='Ilaria:BAAALAAECgQIBAAAAA==.',Im='Impfactory:BAAALAAECgUIBQABLAAECgYICwABAAAAAA==.',In='Inanis:BAAALAAECgQIBgAAAA==.Inurael:BAAALAAECgMIAwAAAA==.',Ir='Ironhunter:BAAALAAECgEIAgAAAA==.',Is='Ishanri:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Ishas:BAAALAAECgcIDwAAAA==.',Iv='Ivredas:BAAALAAECgMIAwAAAA==.',Ja='Jaleria:BAAALAAECgMIBQAAAA==.Jano:BAAALAAECgcIDQAAAA==.',Jo='Joyohunter:BAAALAADCgcIBwAAAA==.',Js='Js:BAAALAAECgIIAgAAAA==.',Ka='Kaelianne:BAAALAADCgMIAwAAAA==.Kalingo:BAAALAADCgEIAQAAAA==.Kaltorias:BAAALAADCgQIBwAAAA==.Kamaro:BAAALAADCggIFgAAAA==.Kamîî:BAAALAAECgMIBAAAAA==.Kandrax:BAAALAAECgIIAgAAAA==.Katzu:BAAALAAECgQIBwAAAA==.Kaìo:BAAALAAECgEIAQAAAA==.',Kh='Kheeza:BAAALAADCggICAAAAA==.',Kl='Klinge:BAAALAADCgcIBwAAAA==.',Kn='Knall:BAAALAADCggIDgAAAA==.Knatterjoe:BAAALAAECgEIAQAAAA==.',Ko='Korum:BAAALAAECgUIBQAAAA==.',Kr='Kragen:BAABLAAECoEVAAMDAAgIixTLAwBLAgADAAgIixTLAwBLAgAEAAYIaw1dJQBjAQAAAA==.Krawâll:BAAALAAECgMIBAAAAA==.Kredar:BAAALAADCggIFgAAAA==.Kri:BAAALAADCggIFgAAAA==.Kriwi:BAAALAAECgEIAQAAAA==.Krombopulos:BAAALAADCggIFQAAAA==.',['Kü']='Küstenkind:BAAALAAECgEIAQAAAA==.',La='Larakiss:BAAALAAECgEIAQAAAA==.Larissa:BAAALAAECgMIAwAAAA==.Laronian:BAAALAADCggIFgAAAA==.Lazyroshi:BAAALAAECgQIBwAAAA==.',Le='Leandrija:BAAALAAECgUICAAAAA==.Leelokar:BAAALAAECggICAAAAA==.Legionatos:BAAALAADCgcIBwAAAA==.Lelarija:BAAALAAECgYIAgAAAA==.Lemocon:BAAALAAECgUICQAAAA==.Leoknox:BAAALAADCgYICAAAAA==.Leva:BAAALAADCggICwAAAA==.',Li='Licky:BAAALAAECgcIDwAAAA==.Lieno:BAAALAADCgYIBgAAAA==.Liiará:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Linorel:BAAALAAECgYICwAAAA==.Lirath:BAAALAADCgQIBgAAAA==.',Lo='Lohse:BAAALAADCggIDwAAAA==.Loid:BAAALAADCggICAAAAA==.Lovekurdishx:BAAALAAECgEIAgAAAA==.',Lu='Luckyswan:BAAALAAECgcIEAAAAA==.',Ly='Lyrra:BAAALAADCgMIAwAAAA==.Lywellion:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Lyxae:BAAALAAECgIIAgAAAA==.',['Lé']='Lémontree:BAAALAAECgMIAwAAAA==.',['Lì']='Lìnglìng:BAAALAADCgQIBAABLAAECgQIBgABAAAAAA==.',['Lí']='Línnéa:BAAALAADCgUIBQAAAA==.',['Lî']='Lîn:BAAALAAECgEIAQAAAA==.',Ma='Madrixx:BAAALAADCggIDAAAAA==.Maerea:BAAALAADCgIIBAABLAAECgIIAgABAAAAAA==.Maethûn:BAAALAAECgEIAQAAAA==.Maggie:BAAALAAECgIIAgAAAA==.Magmaros:BAAALAAECgEIAgAAAA==.Makara:BAAALAADCgUIBQAAAA==.Mason:BAAALAAECgQICQAAAA==.Maúrix:BAAALAAECgUICgAAAA==.',Mc='Mcdrowd:BAAALAAECggICAAAAA==.Mcfree:BAAALAAECgMIBAAAAA==.',Me='Meatwatz:BAAALAAECgcIBwAAAA==.Mellow:BAAALAAECgcIDgAAAA==.Melonezorn:BAAALAADCggIDAAAAA==.',Mi='Mimii:BAAALAADCgUIBQAAAA==.Mindfreak:BAAALAAECgUICQAAAA==.Mirasori:BAAALAADCgYIBgAAAA==.Mirilena:BAAALAADCgcIBwAAAA==.Missdotter:BAAALAAECgEIAQAAAA==.',Mo='Modrolux:BAAALAADCgcICAAAAA==.Moglin:BAAALAAECgUICgAAAA==.Mokushiroku:BAABLAAECoEUAAIFAAcIZR3jBQBGAgAFAAcIZR3jBQBGAgAAAA==.Monnimon:BAAALAADCggIEAAAAA==.Monspiet:BAAALAADCggICQAAAA==.Moonjade:BAAALAADCgQIBQAAAA==.Mooped:BAAALAAECgEIAQAAAA==.',Mu='Muhdot:BAAALAADCgcIBwABLAAECgYIDgABAAAAAA==.',My='Myránda:BAAALAADCgMIBAAAAA==.Myría:BAAALAADCggIEgAAAA==.',Ne='Nedonia:BAAALAAECgcIDAAAAA==.Nehalennia:BAAALAADCggICgABLAAECgIIAgABAAAAAA==.Nerevár:BAAALAADCggIEAAAAA==.',Ni='Nighthâwk:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.',No='Nohka:BAAALAAECgIIAgAAAA==.Nonya:BAAALAADCgcIBwAAAA==.Norberto:BAAALAAECgMIAwAAAA==.Northwind:BAAALAAECgYIDQAAAA==.',Nu='Nufahpriest:BAAALAAECgUICgAAAA==.',['Nâ']='Nâssendra:BAAALAADCgcIBwAAAA==.',['Né']='Nécro:BAAALAAECgMIBQAAAA==.',['Nì']='Nìghtwish:BAAALAADCgIIAgAAAA==.',['Nô']='Nôcti:BAAALAAECgMIBQAAAA==.',['Nÿ']='Nÿx:BAAALAAECgcIEwAAAA==.',Ol='Olessia:BAAALAAECgcIEgAAAA==.',Os='Ostfriesin:BAAALAADCgMIAwAAAA==.',Pa='Pandoryá:BAAALAADCgcICQAAAA==.Pandorâ:BAAALAAECgIIAgAAAA==.',Pe='Pegga:BAAALAADCgEIAQAAAA==.',Po='Polgara:BAAALAADCgQIBwAAAA==.Pommie:BAAALAAECgIIAwAAAA==.',Pr='Presbarhorn:BAAALAADCgcIBwAAAA==.Prettyswan:BAABLAAECoEVAAIGAAgIEiFRBADgAgAGAAgIEiFRBADgAgAAAA==.',Pu='Puls:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Pupselchen:BAAALAADCggIEQAAAA==.',Qa='Qaui:BAAALAADCggICQAAAA==.',Qu='Quackfist:BAAALAAECgcIDwAAAA==.Quivyx:BAAALAADCgUIBQAAAA==.',Ra='Ralarian:BAAALAAECgIIAgAAAA==.Randalthor:BAAALAAECgIIAgAAAA==.Ratatoskr:BAAALAADCgIIAQABLAAECgYICwABAAAAAA==.Razala:BAAALAAECgIIBAAAAA==.Razzac:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Razzaraja:BAAALAAECgEIAQABLAAECgYICQABAAAAAA==.Razí:BAAALAADCgYIBgAAAA==.',Re='Rebecca:BAAALAADCggIEAAAAA==.Regentonne:BAAALAAECgYICAAAAA==.Reáper:BAAALAADCggICgAAAA==.',Ro='Rocketeér:BAAALAAECgQICQAAAA==.Rofellos:BAAALAAECgUIBQAAAA==.',Sa='Sadul:BAAALAADCgIIAgAAAA==.Sanjin:BAAALAAECgQIBgAAAA==.Santonix:BAAALAAECgMIBAAAAA==.Satoru:BAAALAADCgEIAQAAAA==.',Sc='Schaales:BAAALAAECgQIBgAAAA==.Schusselbaum:BAAALAAECgEIAQAAAA==.',Se='Servis:BAAALAADCgYIBwABLAADCgcIDQABAAAAAA==.Severuss:BAAALAADCgUIBQAAAA==.',Sh='Shadling:BAAALAADCggIDAAAAA==.Shadowfever:BAAALAAECgEIAQAAAA==.Shadowraiser:BAABLAAECoEOAAIHAAcIGQ6OLgBrAQAHAAcIGQ6OLgBrAQAAAA==.Shalissa:BAAALAADCggIFgAAAA==.Sharp:BAAALAAECgIIAgAAAA==.Shds:BAABLAAECoEVAAIGAAgIaSDCCQCEAgAGAAgIaSDCCQCEAgAAAA==.Sheris:BAAALAAECgEIAQAAAA==.Sheyanne:BAAALAADCgYIBgAAAA==.Shireen:BAAALAADCgQIBwAAAA==.',Si='Sillylilly:BAAALAADCgcIBwAAAA==.',Sm='Smiâgôl:BAAALAADCgQIBwAAAA==.',St='Stabbro:BAAALAAECgYICwAAAA==.Steelmag:BAAALAADCgcICgAAAA==.Stitchmaster:BAAALAADCgcIDAAAAA==.Streichelzoo:BAAALAADCggICAAAAA==.',Su='Sukie:BAAALAAECgEIAQAAAA==.Sumatira:BAAALAAECgMIAwAAAA==.',Sw='Swapzy:BAAALAADCgYIBgAAAA==.',['Sí']='Síná:BAAALAADCgcICgAAAA==.',Ta='Tabata:BAAALAAECgEIAQAAAA==.Takizi:BAAALAADCggICAAAAA==.Talìa:BAAALAAECgYICQAAAA==.Tankdoc:BAEALAAECgIIAgAAAA==.Tankyhunt:BAEALAAECgEIAQABLAAECgIIAgABAAAAAA==.Tarelon:BAAALAADCgQIBwAAAA==.Taureypsilon:BAAALAAECgYIDQAAAA==.',Te='Tehvil:BAAALAAECgEIAQAAAA==.Tergo:BAAALAADCggICAAAAA==.Tes:BAAALAAECgEIAQAAAA==.',Th='Thivel:BAAALAAECgEIAQAAAA==.',Tj='Tjalf:BAAALAAECgEIAQAAAA==.Tjorpel:BAAALAAECgcIEgAAAA==.',To='Tonk:BAAALAADCggIFgAAAA==.Tornianalf:BAAALAAECgYICQAAAA==.',Tr='Trews:BAAALAADCggICAAAAA==.Trixii:BAAALAAECgMIBgAAAA==.Trunks:BAAALAAECgMIBAAAAA==.Trîxo:BAAALAAECgQIBAAAAA==.',Ts='Tschacka:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Ty='Tyrlich:BAAALAADCggICwABLAAECgIIAgABAAAAAA==.',['Té']='Ténchi:BAAALAADCgcIDQAAAA==.Ténchí:BAAALAAECgYICwAAAA==.Téruan:BAAALAAECgYICgAAAA==.',Un='Unsolved:BAAALAADCgIIAgAAAA==.',Up='Upps:BAAALAADCggIGAABLAAECgIIAgABAAAAAA==.',Va='Vanderstorm:BAAALAADCgcIDQAAAA==.',Ve='Velanya:BAAALAADCgQIAQAAAA==.',Vi='Vishael:BAAALAAECgUIBQAAAA==.',Vl='Vlaushi:BAAALAADCggICAAAAA==.',Vo='Voidrax:BAAALAAECgYICQAAAA==.Voy:BAAALAADCggIFgAAAA==.',Vy='Vylnir:BAAALAADCgMIBAAAAA==.',Wa='Waidla:BAAALAADCggIDAAAAA==.Waserius:BAAALAADCggIDwAAAA==.',Wi='Windgebraus:BAAALAAECgcICAAAAA==.Wionna:BAAALAADCgcIBAAAAA==.',Xa='Xanie:BAAALAAECgEIAQAAAA==.',Xe='Xeyzadrath:BAAALAAECgEIAQAAAA==.',Xi='Ximerdh:BAAALAAECggIDgAAAA==.',Xt='Xtremruléz:BAAALAADCgcIBwABLAADCggIEAABAAAAAA==.',Ya='Yamatanoroch:BAAALAADCggICAAAAA==.Yavan:BAAALAAECgYICgAAAA==.',Za='Zalaya:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Zammi:BAAALAADCgcIBwAAAA==.',Zi='Zidane:BAAALAADCggIDwAAAA==.',['Zò']='Zògrel:BAAALAADCgcIBwAAAA==.',['Är']='Ärtémis:BAAALAADCggIDAAAAA==.',['Äs']='Äshbringer:BAAALAADCggIDgAAAA==.',['Æl']='Ælanør:BAAALAAECgMIBAAAAA==.',['Æs']='Æscanor:BAAALAADCgcIBwAAAA==.',['Ðr']='Ðragon:BAAALAAECgIIBAAAAA==.Ðravën:BAAALAAECgcIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end