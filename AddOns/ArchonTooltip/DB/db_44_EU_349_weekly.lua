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
 local lookup = {'Mage-Arcane','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Priest-Holy','Hunter-Marksmanship',}; local provider = {region='EU',realm="Twilight'sHammer",name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abracädabruh:BAAALAAECgMIAwABLAAECggIFgABADgfAA==.Abzinthe:BAAALAAECgMIAwAAAA==.',Ae='Aerisz:BAAALAAECgYIBgAAAA==.Aeshma:BAABLAAECoEUAAICAAcI1h3aFwBMAgACAAcI1h3aFwBMAgAAAA==.',Ak='Akio:BAAALAAECgQIBAAAAA==.Akla:BAAALAAECgQIBAAAAA==.',Al='Alanbates:BAAALAADCgYICAAAAA==.Alepouditsos:BAAALAADCgcIBwAAAA==.Alira:BAAALAAECgYIDwAAAA==.Allukkard:BAAALAAECgMIBgAAAA==.',An='Antimidgets:BAAALAAECgcICwAAAA==.Anywai:BAAALAADCggIEAAAAA==.',Ao='Aoibhean:BAAALAAECgIIAwAAAA==.',Ar='Arcticblood:BAAALAAECgYICQAAAA==.Argentrenard:BAAALAAECgcIDAAAAA==.Argodk:BAAALAADCgUIBQABLAAECgQIBAADAAAAAA==.Argø:BAAALAAECgQIBAAAAA==.Arjuna:BAAALAAECggIDAAAAA==.',As='Ashghul:BAAALAAECgYIDQAAAA==.Astraxius:BAAALAADCggICAAAAA==.',At='Atréia:BAAALAADCgUIBQAAAA==.Atta:BAAALAAECgcIEAAAAA==.',Az='Azassin:BAAALAADCggICAAAAA==.Aznag:BAAALAAECggIDgAAAA==.Azwyr:BAAALAAECgcIDAAAAA==.',Ba='Babayagka:BAAALAAECgMIBQAAAA==.',Be='Benefit:BAAALAADCgYIDAAAAA==.',Bi='Bigmongo:BAAALAAECgcIDAAAAA==.Bikit:BAAALAADCggICAAAAA==.Billtong:BAAALAADCgcIDAAAAA==.',Bl='Blightfang:BAAALAAECgMIBAAAAA==.Bläeze:BAAALAAECgMIBAAAAA==.',Bo='Boomslangx:BAAALAAECgYICQAAAA==.',Br='Brewjitsu:BAAALAAECgYIBgAAAA==.',Bu='Buster:BAAALAADCgUICQAAAA==.Buxesas:BAAALAADCggIEwAAAA==.',['Bä']='Bäbydoll:BAAALAADCgUIBQAAAA==.',['Bé']='Bérptank:BAAALAAECgEIAQAAAA==.',Ch='Chamelea:BAAALAAECgIIAwAAAA==.Chaocrusher:BAAALAADCggIEAAAAA==.Chappié:BAAALAAECgYIBgAAAA==.',Co='Cobrajack:BAAALAADCggICAAAAA==.Cobrajaçk:BAAALAADCgcIBwAAAA==.Cobrajàck:BAAALAAECgcIEAAAAA==.Commandoxx:BAAALAAECggICQAAAA==.',['Cë']='Cëridweñ:BAABLAAECoEWAAIBAAgIOB+tDQDCAgABAAgIOB+tDQDCAgAAAA==.',Da='Dagshaman:BAAALAAECgMIBQAAAA==.Darkomen:BAAALAADCgQIBAAAAA==.Datsnowsky:BAAALAADCgcIDgAAAA==.Dazed:BAAALAADCggIEgAAAA==.',De='Destinelxx:BAAALAADCgcIBwABLAAECggIGAAEAIgiAA==.Destinelz:BAABLAAECoEYAAIEAAgIiCKJBQASAwAEAAgIiCKJBQASAwAAAA==.',Di='Dimoneski:BAAALAAECgIIAwAAAA==.',Dk='Dkdon:BAAALAAECgcIDgAAAA==.',Do='Domiknee:BAAALAAECgcICgAAAA==.',Dr='Drakaras:BAAALAAECggICAAAAA==.Drbackup:BAAALAAECgcIEAAAAA==.Druidxdruid:BAAALAAECgYIDwAAAA==.',Dt='Dtouch:BAAALAAECgcIDgAAAA==.',Du='Dumitore:BAAALAADCggICAAAAA==.',['Dá']='Dárkcurè:BAAALAADCggIDwAAAA==.',Ed='Eddierip:BAAALAAECgEIAQAAAA==.',Ei='Eith:BAAALAADCggICAABLAAECgMIBQADAAAAAA==.',El='Eldenil:BAAALAAECgYICQAAAA==.Eldánar:BAAALAADCggIFwAAAA==.Ely:BAAALAADCggIFQAAAA==.',En='Endowed:BAAALAAECgYIBgAAAA==.',Ep='Ephey:BAAALAADCggICQAAAA==.Epictv:BAAALAADCgcIBwAAAA==.',Er='Eriadorn:BAAALAADCgYICgAAAA==.Erineth:BAAALAAECgQIBAAAAA==.Erosdeath:BAAALAAECgUIBQAAAA==.',Ex='Extremus:BAAALAADCgIIAgAAAA==.',Fa='Fabarizo:BAAALAADCgIIAgABLAAECgYIBgADAAAAAA==.Fangborn:BAAALAADCgYIBgAAAA==.Fanghörn:BAAALAADCgQIBAAAAA==.Fareastbeast:BAAALAAECgcIDAAAAA==.',Fe='Fearnaut:BAAALAAECgcIDAAAAA==.',Fi='Firelighter:BAAALAADCgcICQAAAA==.',Fl='Flarro:BAAALAAECgUICAAAAA==.',Fo='Foomanchoo:BAAALAADCgcICwAAAA==.Forastai:BAAALAAECgEIAQAAAA==.Forgotenmage:BAAALAADCgcIBwABLAAECgUICQADAAAAAA==.Forgottenpal:BAAALAADCgYIBgABLAAECgUICQADAAAAAA==.Foukousima:BAAALAADCgUIBQAAAA==.',Fr='Frostmaagi:BAAALAADCgcIBwAAAA==.Frozex:BAAALAAECgMIBwAAAA==.Frukha:BAAALAAECgQIBAAAAA==.',['Fí']='Fíddler:BAAALAAECggICAAAAA==.',Ga='Garrinchá:BAAALAAECgIIAgAAAA==.',Gh='Ghostnyx:BAAALAAECgUICAAAAA==.',Gi='Girthquake:BAAALAAECgEIAQAAAA==.',Gk='Gkara:BAAALAADCggICwABLAAECgMIBQADAAAAAA==.Gkatoua:BAAALAADCggICwAAAA==.',Go='Gourmand:BAAALAAECgMIBAAAAA==.',Gr='Greengerasim:BAAALAAECgMIAwAAAA==.Grigory:BAAALAAECgQIBQAAAA==.Grimwarry:BAAALAAECgIIAwAAAA==.Grolm:BAAALAAECgIIAwAAAA==.Grùll:BAAALAAECgYIDgAAAA==.',Gu='Gunsiej:BAAALAAECggICAAAAA==.Gurr:BAAALAAECgcIDAAAAA==.',Ha='Hamada:BAAALAAECggIEAAAAA==.Hardnekkig:BAAALAAECgIIAwAAAA==.',He='Heartburn:BAAALAADCgcICQAAAA==.Herja:BAAALAAECgEIAQABLAAECgYICAADAAAAAA==.',Ho='Hopper:BAAALAADCggIDgAAAA==.',['Há']='Hármón:BAAALAAECgQIBwAAAA==.',In='Incredi:BAAALAAECgcIDAAAAA==.Inkimoon:BAAALAAECgIIAwAAAA==.Insomnima:BAAALAAECgYIDQAAAA==.',Io='Iounothing:BAAALAADCgcICwAAAA==.',Ja='Jahtimestari:BAAALAAECgYIBgAAAA==.',Je='Jedisauce:BAAALAAECgMIBQABLAAECggIFgABADgfAA==.',Jo='Joeysinns:BAAALAAECgYIAwAAAA==.Joeyslam:BAAALAADCgEIAQAAAA==.',Ju='Juhlaörkki:BAAALAAECgMIBgAAAA==.',Ka='Kabooze:BAAALAADCggICAAAAA==.Karvaperse:BAAALAAECgYIBgAAAA==.Kat:BAAALAADCgcIDQAAAA==.Katumus:BAAALAAECgYIBgAAAA==.',Ke='Kealthar:BAAALAAECgYICQAAAA==.Keiria:BAAALAAECgQIBwAAAA==.Kelrisa:BAAALAADCggIGAABLAAECgQIBwADAAAAAA==.Kelsair:BAAALAAECgQIBwAAAA==.Kerauno:BAAALAADCggIEwAAAA==.Kesselrun:BAAALAAECgcIEAAAAA==.',Kh='Khakrovin:BAAALAAECgYIDwAAAA==.',Ko='Koalapoo:BAAALAAECgYICAAAAA==.Kolwyntjie:BAAALAAECgIIAgAAAA==.Kozbara:BAAALAADCggICQABLAAECgYIBgADAAAAAA==.',['Kâ']='Kâthina:BAAALAAECgYICgAAAA==.',['Kä']='Käido:BAAALAADCggIDAAAAA==.',La='Lashina:BAAALAADCgYIBgAAAA==.',Le='Leimahdus:BAAALAADCgcIBwAAAA==.',Li='Lichstorm:BAAALAADCggIGAAAAA==.Lifereborn:BAAALAADCgEIAQAAAA==.Lippey:BAAALAADCgcIBwABLAAECgMIAwADAAAAAA==.',Ll='Llust:BAAALAAECgIIAwAAAA==.Llyrdwr:BAAALAADCggICAAAAA==.',Lo='Loaf:BAAALAAECgMIAwAAAA==.Lockin:BAAALAAECggICQAAAA==.Lorky:BAAALAAECgcIBwAAAA==.',Lu='Lucy:BAAALAAECgcIEAAAAA==.Ludoki:BAAALAADCgcIDQAAAA==.Luicifer:BAAALAAECgIIAwAAAA==.',['Lä']='Läka:BAAALAAECgMIAwAAAA==.',['Lø']='Løwmana:BAAALAADCgcICwAAAA==.',Ma='Magerage:BAAALAADCgcICwAAAA==.Maghilla:BAAALAADCgEIAQAAAA==.Magë:BAAALAADCgMIAwAAAA==.Mainrak:BAAALAAECgEIAQAAAA==.Malik:BAAALAADCggICAAAAA==.Margorie:BAAALAAECgUIBQAAAA==.Margoth:BAAALAADCggIFwAAAA==.',Mc='Mcdora:BAAALAADCgUIBQAAAA==.Mcpaw:BAAALAAECgEIAQAAAA==.Mcwild:BAAALAAECgIIAwAAAA==.',Me='Meatman:BAAALAAECgEIAQAAAA==.Menoengrish:BAAALAADCggIDwAAAA==.',Mi='Minarasmán:BAAALAAECgQICAAAAA==.Mitzys:BAAALAADCgYIBgAAAA==.',Mo='Montano:BAAALAADCggIEwAAAA==.Morfini:BAAALAAECgcICAAAAA==.Morídín:BAAALAAECgcIEAABLAAECggICAADAAAAAA==.',Mp='Mpampisoflou:BAAALAADCgYIBgAAAA==.',Na='Naomi:BAAALAADCgEIAQAAAA==.',Ne='Necronova:BAAALAADCgQIBwAAAA==.Necrotroll:BAAALAAECgMIAwAAAA==.Necrowyrm:BAAALAADCggICAAAAA==.',Ni='Nidalap:BAAALAAECgMIBQAAAA==.',No='Novingen:BAAALAAECgIIAgAAAA==.',Nu='Nuolipersees:BAAALAAECgYIBgABLAAECgYIBgADAAAAAA==.',Ny='Nyctia:BAAALAADCggICAAAAA==.Nyctophilia:BAAALAAECgYIDQAAAA==.',['Nå']='Nåmi:BAAALAAECgMIBAAAAA==.',Od='Odinsblade:BAAALAAECgYIDwAAAA==.',Ol='Oldschool:BAAALAAECgUIBQAAAA==.',Or='Orctheguy:BAAALAAECgEIAQAAAA==.Orhura:BAAALAAECgQIBwAAAA==.Orphis:BAAALAAECgUICwAAAA==.',Ou='Ouiski:BAAALAAECgcIEAAAAA==.',Pa='Padazun:BAAALAAECgcIDwAAAA==.Paladari:BAAALAAECgYIBwAAAA==.Paladinix:BAAALAAECgMIBQAAAA==.Palydoon:BAAALAAECgUIBQABLAAECgcIDgADAAAAAA==.Papper:BAAALAADCgcIBwAAAA==.Parawietje:BAAALAAECgYICAAAAA==.Payn:BAAALAADCgUIBQAAAA==.',Pe='Pellaagarion:BAAALAADCgcIBwAAAA==.Perdepis:BAAALAAECgMIAwAAAA==.Petula:BAABLAAECoEYAAIFAAgI4CTxAABdAwAFAAgI4CTxAABdAwAAAA==.',Ph='Phase:BAAALAAECgMIBgAAAA==.Phiinom:BAAALAADCggICAAAAA==.',Pi='Pitoor:BAAALAADCgcIBwAAAA==.Pixiel:BAAALAADCgYIBgAAAA==.',Pl='Plushin:BAAALAAECgcIDwAAAA==.',Po='Porkchop:BAAALAADCggICAAAAA==.',Pr='Probeard:BAAALAADCgIIAgABLAAECgIIAwADAAAAAA==.Profound:BAAALAAECgIIAwAAAA==.Proktosauros:BAAALAAECgYICQAAAA==.Prowakidx:BAAALAAECgYICQAAAA==.Prîestah:BAAALAADCgcIBwABLAAECggIFgABADgfAA==.',Ps='Psykovsky:BAAALAAECgUICwAAAA==.',Pu='Puffdaßigmac:BAAALAAECgcIDwAAAA==.Pungendin:BAAALAADCgIIAgAAAA==.',Pw='Pwnpwnhaxx:BAAALAAECgcIEAAAAA==.',Py='Pyörre:BAAALAAECgYIBgAAAA==.',Qo='Qoy:BAAALAAECgIIAgAAAA==.',Ra='Rahgar:BAAALAAECgYIBgAAAA==.Raphaell:BAAALAAECgYICQAAAA==.',Re='Redgajol:BAAALAAECgcIDwAAAA==.Relthorn:BAAALAADCggIDAAAAA==.Requiem:BAAALAAECgYIBwAAAA==.',Ro='Rochirielon:BAAALAADCgEIAQAAAA==.Rofbul:BAAALAADCggIEgAAAA==.Rolynne:BAAALAAECgUIBQAAAA==.',Ru='Rubíks:BAAALAADCgUIBQAAAA==.',Sa='Saiaman:BAAALAAECgYIBgAAAA==.Saintdamien:BAAALAAECgMIBAAAAA==.Salmena:BAAALAAECgcIDQAAAA==.Sammo:BAAALAAECgMIAwAAAA==.Samwise:BAAALAAECggIAgAAAA==.',Sc='Scaly:BAAALAAECgMIBgAAAA==.Schoeps:BAAALAAECgcIEAAAAA==.',Sg='Sgourakoss:BAAALAAECgEIAQAAAA==.',Sh='Shaded:BAAALAAECgEIAQAAAA==.Shai:BAAALAAECgYIBgAAAA==.Shaidh:BAAALAAECgYIBgAAAA==.Shaidk:BAAALAADCggICAAAAA==.Sheandran:BAABLAAECoEYAAIGAAgIISGxBQDaAgAGAAgIISGxBQDaAgAAAA==.Sheathledger:BAAALAAECgYICQAAAA==.Shion:BAAALAAECgMIAwABLAAECgQIBAADAAAAAA==.Shockolate:BAAALAADCgcICwAAAA==.Shöman:BAAALAAECgQIBwAAAA==.',Si='Siiggee:BAAALAAECgYIBgAAAA==.Sindarela:BAAALAADCgcIBwAAAA==.Sintti:BAAALAAECgYIBgAAAA==.',Sk='Skapíe:BAAALAADCgMIAwAAAA==.',Sl='Slingy:BAAALAADCgQIBAAAAA==.',Sm='Smartazz:BAAALAAECgIIAwAAAA==.',So='Sootglow:BAAALAADCggIFQAAAA==.',Sp='Spicyshots:BAAALAADCggICAABLAAECggIFgABADgfAA==.Spinmeister:BAAALAAECgYIDQAAAA==.Spirakoss:BAAALAAECgYICAAAAA==.',St='Stavrogin:BAAALAAECgIIAwAAAA==.Stavrou:BAAALAADCgcIEgAAAA==.Stenbumling:BAAALAADCgYIBgAAAA==.Stikgarzuk:BAAALAADCgcIBwAAAA==.Stormangels:BAAALAADCggICAABLAAECggICAADAAAAAA==.Stárscream:BAAALAADCgMIAwAAAA==.',Su='Sukcmydisc:BAAALAAECgYIBgAAAA==.Sulrette:BAAALAADCgYIBgAAAA==.Sunnyside:BAAALAADCgcIBwAAAA==.',Ta='Taikamatto:BAAALAAECgYIBgAAAA==.',Th='Thetanknaut:BAAALAAECgcIDAAAAA==.Thiresios:BAAALAADCgMIAwAAAA==.Thristen:BAAALAAECgcIEAAAAA==.Thwra:BAAALAADCgcICAAAAA==.',To='Toké:BAAALAAECgYIBgAAAA==.Topnepneko:BAAALAADCgYIBgAAAA==.',Tr='Trath:BAAALAAECgcIEAAAAA==.Trikadin:BAAALAAECgcIEAAAAA==.Trikaevo:BAAALAADCgcIDQABLAAECgcIEAADAAAAAA==.Trishes:BAAALAADCggICAAAAA==.',Ts='Tsigaros:BAAALAADCgEIAQAAAA==.',Tz='Tzunic:BAAALAADCgcIBwAAAA==.',Uf='Ufer:BAAALAAECgIIBAAAAA==.',Ur='Urcaguarcy:BAAALAAECggIAwAAAA==.',Ve='Vesipuhveli:BAAALAAECgYIBgAAAA==.Vexis:BAAALAADCgEIAQAAAA==.',Vi='Vivian:BAAALAAECgMIAwAAAA==.',Vo='Vosjaw:BAAALAADCggICAAAAA==.',Vr='Vrigka:BAAALAADCggICAAAAA==.',Vu='Vulpie:BAAALAADCgQICAAAAA==.',['Vï']='Vï:BAAALAAECgMIBAAAAA==.',Wa='Warriortje:BAAALAAECgIIAgAAAA==.',Xa='Xaks:BAAALAADCggICAAAAA==.Xaphan:BAAALAADCggICQAAAA==.',Xe='Xenize:BAAALAAECgYIBgAAAA==.Xervaz:BAAALAAECgcIEQAAAA==.',Xg='Xgemeaux:BAAALAAECgYIDQAAAA==.',Ya='Yarphead:BAAALAADCgEIAQAAAA==.Yaseravoke:BAAALAADCggICAABLAAECggIGAAFAOAkAA==.Yawanna:BAAALAAECgMIBQAAAA==.',Yo='Yomasepoes:BAAALAAECgUICQAAAA==.Yorkii:BAAALAADCgUIBQAAAA==.',Za='Zaazu:BAAALAAECgYIEAAAAA==.Zabimaru:BAAALAAECgYIDQAAAA==.Zackeriah:BAAALAAECgcIEAAAAA==.Zapp:BAAALAAECgIIAwAAAA==.',Zo='Zorar:BAAALAAECgYICgAAAA==.',Zz='Zz:BAAALAAECgUIBQAAAA==.',['Ùb']='Ùberskyllou:BAAALAADCgcIBwAAAA==.',['Ýl']='Ýloar:BAAALAAECgUIBQAAAA==.',['ßi']='ßigmâc:BAAALAADCgcIBwABLAAECgcIDwADAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end