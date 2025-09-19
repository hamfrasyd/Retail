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
 local lookup = {'Warlock-Demonology','Priest-Holy','Priest-Shadow','Unknown-Unknown','Mage-Arcane','Mage-Frost','DemonHunter-Havoc','Paladin-Retribution','Warrior-Fury','Evoker-Devastation','Hunter-Survival','DeathKnight-Blood','DeathKnight-Frost','Shaman-Enhancement','DemonHunter-Vengeance','Rogue-Assassination','Warlock-Affliction','Warlock-Destruction','Monk-Mistweaver','Rogue-Subtlety','Druid-Feral','Monk-Brewmaster',}; local provider = {region='EU',realm='Bronzebeard',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aande:BAAALAADCgEIAQAAAA==.',Ab='Abzynth:BAAALAADCgcIBwAAAA==.',Ad='Adamzandalar:BAAALAADCggIEQAAAA==.',Af='Afkontrash:BAABLAAECoEUAAIBAAcIXiRVAwDqAgABAAcIXiRVAwDqAgAAAA==.',Aj='Ajaks:BAAALAAECgYIDwAAAA==.',Al='Aldar:BAAALAAECgMIBwAAAA==.Alphoe:BAABLAAECoEWAAICAAgIzSIvBgAAAwACAAgIzSIvBgAAAwAAAA==.',Am='Amyrantha:BAAALAAECgYICAAAAA==.',An='Andyaib:BAAALAAECgYIDwAAAA==.Andyshamberg:BAAALAAECgMIAwAAAA==.Animafel:BAAALAAECgMIBwAAAA==.Animalistica:BAAALAADCgMIAwAAAA==.',Ar='Arkana:BAAALAADCgcIBwAAAA==.Arkefiende:BAAALAADCggIGwAAAA==.Armst:BAAALAAECgYICgAAAA==.Arvioch:BAAALAADCggIFQAAAA==.Arxalia:BAAALAAECgMIBAAAAA==.Arxaya:BAABLAAECoEYAAIDAAYI0w6PNgBWAQADAAYI0w6PNgBWAQAAAA==.',As='Ashman:BAAALAADCggIFwAAAA==.',Az='Azzandra:BAAALAAECgMIAwAAAA==.',Ba='Bambam:BAAALAADCggICAAAAA==.',Be='Belgaraht:BAAALAADCgcIDwAAAA==.Betty:BAAALAAECgMIBAAAAA==.',Bi='Bidanka:BAAALAADCgMIAwAAAA==.',Bl='Bluntclawz:BAAALAADCggIEAAAAA==.',Bo='Boarslayer:BAAALAAECgYIDAAAAA==.Bobjob:BAAALAAECgMIAwAAAA==.Boonkamp:BAAALAADCggIFQAAAA==.Booper:BAAALAADCggICAAAAA==.Bopo:BAAALAAECggIBwAAAA==.Borovnica:BAAALAAECgYICwAAAA==.Bouch:BAAALAADCggIEAABLAAECgUIBwAEAAAAAA==.',Br='Bregolas:BAAALAAECgYIEgAAAA==.Brixey:BAAALAADCgYICAABLAAECgYICQAEAAAAAA==.Brixi:BAAALAAECgYICQAAAA==.',Bu='Bulkhogan:BAAALAADCggICAAAAA==.',Ca='Cachocabra:BAAALAADCgUIBQAAAA==.Calabria:BAAALAADCggIDwAAAA==.Caldrien:BAAALAAECgMIAwAAAA==.Catspaw:BAAALAAECgEIAQAAAA==.',Ch='Chamansito:BAAALAADCgYIBgABLAAECgUIAgAEAAAAAA==.Chica:BAACLAAFFIEGAAMFAAMIEBOeCgD4AAAFAAMI3hGeCgD4AAAGAAEIth17CQBTAAAsAAQKgRsAAwYACAgNH6UJAIwCAAUACAjJHO4XAKECAAYACAi4HqUJAIwCAAAA.Chodrinks:BAAALAADCgYIBgAAAA==.Chokii:BAAALAAECgMIBAAAAA==.Chuggi:BAAALAAECgYICAAAAA==.',Ci='Cinithri:BAACLAAFFIEGAAIHAAMILhDmBwD5AAAHAAMILhDmBwD5AAAsAAQKgR4AAgcACAhlITUPAOsCAAcACAhlITUPAOsCAAAA.',Cl='Cloúd:BAAALAADCgcICwAAAA==.',Co='Col:BAAALAAECgMIBgAAAA==.Colee:BAAALAAECgMIAwAAAA==.Cormac:BAAALAADCggIDwAAAA==.',Cr='Craciun:BAAALAAECgYICwAAAA==.Cremeegg:BAAALAAECgcIEQAAAA==.Crix:BAAALAAECggICAAAAA==.Cruz:BAAALAAECgcIDwAAAA==.Crystalball:BAAALAADCgcICQAAAA==.',Da='Danray:BAACLAAFFIEGAAIIAAMIPh4RAwAmAQAIAAMIPh4RAwAmAQAsAAQKgR4AAggACAi4JJwGAEIDAAgACAi4JJwGAEIDAAAA.Danue:BAAALAAECgEIAQAAAA==.Darealnugget:BAAALAAECgYIEQAAAA==.Daxx:BAAALAADCgEIAQAAAA==.',De='Deathanya:BAAALAAECgIIAgAAAA==.Deathofrats:BAAALAAECgMIBAAAAA==.Deathsight:BAAALAAECgMIBwAAAA==.Debtstrike:BAAALAAECgYICgAAAA==.Derringer:BAAALAADCgcIDwAAAA==.Deàth:BAAALAAECgYIDwABLAAFFAMIBwAJAPsgAA==.',Di='Discobouch:BAAALAAECgQIBwABLAAECgUIBwAEAAAAAA==.',Do='Dobrous:BAAALAADCgcIGAAAAA==.Dominus:BAAALAAECgMIBgAAAA==.Dovahkiin:BAAALAAECgYICQAAAA==.Dovla:BAAALAAECgMIBQAAAA==.',Dp='Dps:BAAALAAECggIDgAAAA==.',Dr='Dragula:BAAALAADCgcIEQAAAA==.Drakarys:BAACLAAFFIEKAAIKAAQIrxlkAgByAQAKAAQIrxlkAgByAQAsAAQKgRsAAgoACAi8JM4CAEMDAAoACAi8JM4CAEMDAAAA.Druii:BAAALAAECgEIAQAAAA==.',Du='Dunban:BAAALAADCgcIBwAAAA==.Durendal:BAAALAAECgMIBwAAAA==.',Ec='Eccos:BAAALAADCgMIAwAAAA==.',Ed='Edhraan:BAAALAAECggICwAAAA==.',Ee='Eevee:BAAALAAECgYICgAAAA==.',Ei='Eirill:BAAALAADCgMIAgAAAA==.',El='Elenori:BAAALAAECgMIBwAAAA==.Ellesméra:BAAALAAECgYIDwAAAA==.',Er='Er:BAAALAAECgYICgAAAA==.Eralock:BAAALAAECgIIAgABLAAECgcIFgALAJ8YAA==.Erather:BAABLAAECoEWAAILAAcInxhjBAAfAgALAAcInxhjBAAfAgAAAA==.',Ez='Ezzar:BAAALAAECgMIAwAAAA==.',Fa='Fayed:BAAALAAECgYIEQAAAA==.Fazuli:BAAALAAECgIIAgAAAA==.',Fe='Felballz:BAAALAAECgMIBAAAAA==.',Fi='Fierabras:BAAALAAECgMIAwAAAA==.',Fl='Flamehof:BAAALAAECgYICQAAAA==.',Fo='Foxie:BAAALAAECgYIEQAAAA==.',Fr='Frang:BAAALAAECgEIAQAAAA==.Frizzels:BAAALAAECgEIAQAAAA==.From:BAAALAAECgYICgAAAA==.Frostyelf:BAAALAAECgYIDQAAAA==.Frownedupon:BAAALAADCgYIBgAAAA==.Fréd:BAAALAAECgYICAAAAA==.',Fu='Fudrick:BAAALAAECgMIAwAAAA==.',Ga='Garfield:BAAALAADCgIIAgAAAA==.',Ge='Geéspot:BAAALAAECgYICQAAAA==.',Gr='Grabmyplúms:BAAALAAECgYIDAAAAA==.Grampaw:BAAALAAECgMIBAAAAA==.Grimmen:BAAALAADCgUIBwAAAA==.Grimskull:BAAALAAECgMIBgAAAA==.Gruel:BAAALAADCgcIDAAAAA==.',Gu='Gucchitank:BAAALAAECgYIBwAAAA==.',Gw='Gwenllian:BAAALAADCgMIAwAAAA==.',Ha='Hanny:BAAALAADCggIDAABLAADCggIEQAEAAAAAA==.Happydemon:BAAALAADCggICAAAAA==.',He='Headles:BAAALAADCgYICgABLAAECgMIBQAEAAAAAA==.Hellsiege:BAAALAAECgYIDgAAAA==.',Hi='Hina:BAAALAADCgUIBQAAAA==.',Ho='Horrend:BAACLAAFFIEMAAIMAAUIpRWsAAC8AQAMAAUIpRWsAAC8AQAsAAQKgRYAAwwACAisIbcDAOwCAAwACAisIbcDAOwCAA0AAQjBE3LQACUAAAAA.',Hu='Huntauxie:BAAALAAECggICAAAAA==.',Hy='Hybiscus:BAAALAAECgYIEQAAAA==.',Ia='Iamhim:BAAALAAECgIIAgAAAA==.',Ig='Igotyoubro:BAAALAADCgQIBAABLAAECgMIAwAEAAAAAA==.',Ih='Ihunt:BAAALAADCgcICgAAAA==.',Il='Illdain:BAAALAAECgEIAQAAAA==.',In='Infreign:BAAALAAECgMIBAAAAQ==.',Ir='Irage:BAAALAADCgMIAgAAAA==.',Is='Isartais:BAAALAAECgEIAQAAAA==.Iskier:BAAALAADCgIIAgAAAA==.Israphael:BAAALAAECgYIDgABLAAFFAQICgAKAK8ZAA==.',Ja='Jackera:BAAALAADCgEIAQAAAA==.',Je='Jerbert:BAAALAAFFAIIAgAAAA==.Jerelaand:BAAALAADCgEIAQAAAA==.',Ji='Jimmï:BAAALAADCgcIBwAAAA==.Jinah:BAABLAAECoEWAAMCAAcIvSTNCADZAgACAAcIvSTNCADZAgADAAYIHRU9LQCSAQAAAA==.Jinquisitor:BAAALAADCggIEAAAAA==.Jixun:BAAALAADCggICQAAAA==.Jizum:BAAALAAECgUICgAAAA==.',Jo='Johnwárcraft:BAAALAAECggICAAAAA==.Jordz:BAAALAADCggICAABLAAECgYICQAEAAAAAA==.',Ka='Kairos:BAAALAAECgYIBgAAAA==.Kallystra:BAAALAADCgYICgAAAA==.Kallystraza:BAAALAAECgIIAwAAAA==.Katemci:BAAALAAECgMIBwAAAA==.Kattlian:BAAALAAECgMIBAAAAA==.Kaylexxl:BAAALAADCgcIDwAAAA==.',Ke='Kenta:BAAALAAECgYIDQAAAA==.Ketod:BAAALAAECgEIAQAAAA==.',Ki='Kieralock:BAAALAAECgYICgAAAA==.Kiillergiirl:BAAALAAECgYICgAAAA==.Killforblood:BAABLAAECoEWAAIOAAgIpRlPBgA/AgAOAAgIpRlPBgA/AgAAAA==.',Kr='Kroepoek:BAAALAAECgMIAwAAAA==.Krácker:BAAALAADCgUIBQAAAA==.',Ku='Kuman:BAAALAAECgEIAQAAAA==.',Ky='Kypdurron:BAAALAAECgYICwAAAA==.',Li='Lieweheksie:BAAALAADCggICAAAAA==.Lilyholy:BAAALAAECgMIBQAAAA==.Littlebetch:BAAALAAECggICAAAAA==.',Lo='Lokoth:BAAALAADCggIEgAAAA==.Lolaur:BAAALAADCgcIBwABLAAECgYIBQAEAAAAAA==.Lolayr:BAAALAAECgYIBQAAAA==.Lollypop:BAAALAADCggICAAAAA==.Lorbs:BAAALAAECggICAAAAA==.Lorther:BAAALAAECgUICwAAAA==.Lottiedottie:BAAALAADCgcIBwAAAA==.',Lu='Lucita:BAAALAADCggIGgAAAA==.Lumina:BAAALAADCgcICAAAAA==.Lumosall:BAAALAAECgEIAQAAAA==.Lurks:BAAALAADCgcIDQAAAA==.',Ma='Machoman:BAABLAAECoEXAAIHAAgINRvKHQBwAgAHAAgINRvKHQBwAgAAAA==.Machozard:BAAALAAECgYICwABLAAECggIFwAHADUbAA==.Macncheese:BAACLAAFFIEIAAIPAAMIuQ70AQDDAAAPAAMIuQ70AQDDAAAsAAQKgSAAAg8ACAgWIJgEALkCAA8ACAgWIJgEALkCAAAA.Macwhitey:BAAALAAECgUIBwAAAA==.Magganii:BAAALAADCgEIAQAAAA==.Maguna:BAAALAADCggIEAAAAA==.Malenía:BAAALAAECgUIAgABLAAECgYICAAEAAAAAA==.Mamahunu:BAAALAADCgYIBQAAAA==.Marogar:BAAALAAECgYIEAAAAA==.Marss:BAAALAAECgYIEQAAAA==.Mathalmir:BAAALAAECgQIBAAAAA==.Maxhunter:BAAALAADCggIEwAAAA==.',Mb='Mbmonk:BAAALAADCggIDAABLAAFFAQICgAKAK8ZAA==.',Mc='Mctailor:BAAALAAECgYIEQAAAA==.',Me='Meerkat:BAAALAAECgEIAQAAAA==.Merceyz:BAACLAAFFIEHAAIJAAMI+yDXAwAvAQAJAAMI+yDXAwAvAQAsAAQKgRwAAgkACAirJLADAFADAAkACAirJLADAFADAAAA.',Mi='Mickypaly:BAAALAAECgMIBAAAAA==.Mir:BAAALAAECgMIBgABLAAECgYICAAEAAAAAA==.Mirthe:BAAALAAECgMIAwAAAA==.Missfiona:BAAALAADCgUIBQAAAA==.Mittens:BAAALAAECgYIDgAAAA==.',Mo='Moobicus:BAAALAAECgMIAwAAAA==.Moonsan:BAAALAAECgYICQAAAA==.Morghunt:BAAALAADCgcIBwAAAA==.Morkish:BAAALAAECgYICAAAAA==.',Mu='Mumford:BAAALAADCgYIBgAAAA==.',Mv='Mvu:BAAALAAECgMIAwAAAA==.',My='Myth:BAACLAAFFIEQAAIPAAYIqRwGAABsAgAPAAYIqRwGAABsAgAsAAQKgRoAAg8ACAjnJhQAAJ8DAA8ACAjnJhQAAJ8DAAAA.Mythoss:BAAALAAFFAIIAgABLAAFFAQICgAKAK8ZAA==.',Na='Namibia:BAAALAAECgMIAwAAAA==.Naushika:BAAALAAECggIEQAAAA==.',Ne='Nerd:BAAALAAECgMIBAAAAA==.Netharel:BAAALAAECgQIBAAAAA==.Netheru:BAAALAAECgYIDAAAAA==.Nettleleaf:BAAALAAECgIIAwAAAA==.Newgate:BAAALAADCggICgAAAA==.Neymar:BAAALAAECgQIBAAAAA==.',Ni='Nightexecute:BAAALAAECgYICQAAAA==.Nightravenn:BAAALAADCggIFgAAAA==.Niluna:BAAALAADCgcIBwABLAAECgYIFAAQAPMhAA==.Nimms:BAAALAADCgcIEQAAAA==.Nimwen:BAAALAADCgQIBAAAAA==.Nitrazepam:BAAALAADCgQIBAAAAA==.Nixxus:BAAALAAECgcIDwAAAA==.',No='Nochipa:BAAALAADCggIDwAAAA==.Noeho:BAAALAAECgMIBwAAAA==.Noemagi:BAAALAADCggICAAAAA==.Noemata:BAAALAADCgEIAQAAAA==.',Nt='Ntraatjeerbj:BAAALAADCggICAAAAA==.',Oc='Oceanborn:BAAALAAECgMIBwAAAA==.Oceána:BAAALAADCgcICQAAAA==.',Oh='Ohiru:BAAALAADCgcIBwAAAA==.',Or='Orcztwo:BAAALAADCggIIAABLAAECgMIBgAEAAAAAA==.Orczy:BAAALAAECgMIBgAAAA==.Organa:BAAALAAECgYIDAAAAA==.',Ou='Ouchie:BAAALAAECggIDgAAAA==.',Pa='Palabrix:BAAALAADCgcIBwABLAAECgYICQAEAAAAAA==.Paladanus:BAAALAADCgcIBwAAAA==.Palisar:BAAALAADCggICAAAAA==.Pandam:BAAALAADCgQIBAAAAA==.Pants:BAAALAAECgYIDwAAAA==.',Pe='Penelope:BAAALAAECgMIBAAAAA==.',Ph='Philinoldasu:BAAALAAECgEIAQAAAA==.Phuzzy:BAAALAADCggIFAAAAA==.',Pi='Pigjuice:BAAALAAECgEIAQAAAA==.',Po='Poggish:BAAALAAECgYICQAAAA==.',Pr='Prinders:BAABLAAECoEXAAQRAAcIvxNqEQBNAQASAAYIARNvOQCUAQARAAUIkhFqEQBNAQABAAUIQBGxLQBMAQAAAA==.',Pu='Purist:BAAALAAECgMIBwAAAA==.Puríster:BAAALAAECgMIBwAAAA==.',Qu='Quartz:BAAALAADCgUIBQAAAA==.Quiz:BAAALAADCggICAAAAA==.',Ra='Raavi:BAACLAAFFIEFAAIDAAMI2x1MBAAUAQADAAMI2x1MBAAUAQAsAAQKgRsAAgMACAjkIjgGAB4DAAMACAjkIjgGAB4DAAAA.Raccon:BAAALAADCgcIBwAAAA==.Ragingemó:BAAALAADCggICAAAAA==.Raijin:BAAALAAECgIIAgAAAA==.Rakkor:BAAALAADCggICwAAAA==.Raska:BAAALAAECgIIAgAAAA==.Rayge:BAAALAADCgEIAQAAAA==.Razorstorm:BAAALAADCggIHwAAAA==.',Re='Realhunter:BAAALAADCgcIBwAAAA==.Reckzo:BAACLAAFFIEGAAIHAAMIDBBICAD0AAAHAAMIDBBICAD0AAAsAAQKgSAAAgcACAiCIPMNAPUCAAcACAiCIPMNAPUCAAAA.Redsdk:BAAALAAECgUIBQABLAAECgcIEQAEAAAAAA==.Redsdruid:BAAALAAECgcIEQAAAA==.',Rh='Rhyi:BAAALAAECgMIBQAAAA==.',Ri='Rii:BAABLAAECoEZAAITAAgIgyLsAgAEAwATAAgIgyLsAgAEAwAAAA==.Rimefrost:BAAALAADCggICAAAAA==.',Ro='Royalflush:BAAALAADCgMIAwAAAA==.',Ry='Rylanor:BAAALAADCggICwAAAA==.',['Rá']='Ráymond:BAAALAAECgEIAQAAAA==.Ráýmónd:BAAALAADCgMIAwABLAAECgEIAQAEAAAAAA==.',Sa='Saeasa:BAAALAAECgYIEAAAAA==.Salash:BAAALAAECgYICgAAAA==.Salky:BAAALAAECgMIBQAAAA==.Sassyjane:BAAALAAECggICwAAAA==.',Sc='Schildpad:BAAALAADCgcIBwAAAA==.',Se='Selket:BAAALAADCgcIBwAAAA==.',Sh='Shadopan:BAAALAAECgMIBgAAAA==.Shadymira:BAAALAADCggIDgAAAA==.Shamaraman:BAAALAADCgQIBAAAAA==.Sharpeye:BAAALAAECggIDgAAAA==.Shields:BAAALAAECgEIAQABLAAFFAUIDAAMAKUVAA==.Shifson:BAAALAAECgYICwAAAA==.Shikobo:BAAALAAECgcIEQAAAA==.Shinsoul:BAAALAAECgYIEQAAAA==.Shmeather:BAAALAADCgIIAgAAAA==.Shockahontas:BAAALAAECgcICAAAAA==.Shockrock:BAAALAADCggICwAAAA==.',Si='Siennamae:BAAALAADCggIDQAAAA==.Silchas:BAAALAAECgMIBgAAAA==.Sillbis:BAAALAAECgMIBwAAAA==.Sineeya:BAAALAAECgYICQAAAA==.Sipka:BAAALAADCggICAAAAA==.',Sk='Skeloth:BAAALAAECgYICQAAAA==.',Sl='Slå:BAAALAAECgQIBQAAAA==.',Sm='Smork:BAAALAADCgUIBQAAAA==.',Sn='Sneakycrit:BAABLAAECoEUAAMQAAYI8yEkEQBQAgAQAAYI8yEkEQBQAgAUAAMIzQ5xHgCkAAAAAA==.Sneax:BAAALAAECgMIBwAAAA==.Sneaxhunter:BAAALAADCgYIBgABLAAECgMIBwAEAAAAAA==.',So='Soladormu:BAAALAADCgEIAQAAAA==.Solaenii:BAABLAAECoEVAAMDAAcIUx7FEwBsAgADAAcIUx7FEwBsAgACAAYIlCLsFwA9AgAAAA==.Sookiie:BAABLAAECoEZAAIOAAgIvRZvBQBgAgAOAAgIvRZvBQBgAgAAAA==.',Sq='Squashy:BAAALAAECgYIDgAAAA==.',Sr='Srba:BAAALAADCggICAAAAA==.',St='Star:BAAALAAECgQICgAAAA==.Stefani:BAAALAAECgYICQAAAA==.Stenhand:BAAALAAECgMIBQAAAA==.Stoneddwarf:BAAALAADCggIDgAAAA==.Stormbinder:BAAALAADCgcIBwAAAA==.Stormovik:BAAALAAECgYIDwAAAA==.Stórmstriker:BAAALAADCggIDwABLAADCggIEAAEAAAAAA==.',Su='Sundee:BAAALAADCgYIBQAAAA==.',Sv='Svéndalos:BAAALAADCgEIAQABLAAECgQIBQAEAAAAAA==.',Sw='Swaydeh:BAABLAAECoEaAAIVAAcIxyXvAgAFAwAVAAcIxyXvAgAFAwAAAA==.Sweetlips:BAAALAAECgEIAQAAAA==.Swisstony:BAAALAAECgYICwAAAA==.',Sy='Sylvius:BAAALAAECgUIDAAAAA==.',Te='Tehenhauin:BAAALAAECgUIAgAAAA==.',Th='Thegaze:BAAALAAECgMIBQAAAA==.Themark:BAAALAAECgMIBAAAAA==.Themilfie:BAAALAADCgMIAwABLAAECgEIAQAEAAAAAA==.Thorbard:BAAALAADCgYIBgAAAA==.Thoriy:BAAALAAECgIIAgAAAA==.Thracius:BAAALAAECgMIAwAAAA==.Thunderbobs:BAAALAAECgUICAAAAA==.Thunk:BAAALAADCggIFgAAAA==.',Ti='Tinymee:BAAALAAECgMIBwAAAA==.Tirisfal:BAAALAAECgEIAQAAAA==.Tisniveel:BAAALAAECgYIDgAAAA==.',To='Tombstone:BAAALAAECgYIBwAAAA==.Totsugeki:BAAALAADCgYIBgAAAA==.',Um='Umo:BAAALAAECgYIDAAAAA==.',Uo='Uomnidas:BAAALAADCgUIBwAAAA==.',Ur='Urmehr:BAACLAAFFIEGAAIJAAMIBRKgBgAEAQAJAAMIBRKgBgAEAQAsAAQKgR4AAgkACAjdH60MAN4CAAkACAjdH60MAN4CAAAA.',Va='Valcyrie:BAAALAAFFAIIAgAAAA==.Valtari:BAAALAAECgYICQAAAA==.Vantorus:BAAALAAECgMIAwAAAA==.',Ve='Vegetaa:BAAALAADCgYICQAAAA==.Vezus:BAAALAADCgMIAwAAAA==.',Vi='Virage:BAAALAAECgEIAQAAAA==.Vistario:BAAALAADCggICAAAAA==.Vixéns:BAAALAAECggICAAAAA==.',Vr='Vritra:BAAALAADCgUIBQAAAA==.',Wa='Warkeff:BAAALAAECgMIBgAAAA==.Watkuntfoo:BAAALAAECggIEwAAAA==.',Wi='Wigzdh:BAAALAAECgYIDQAAAA==.Wildassassin:BAAALAADCgYICQAAAA==.',Wr='Wroick:BAABLAAFFIEGAAIWAAUI4RQlAQC5AQAWAAUI4RQlAQC5AQABLAAFFAUIDAAMAKUVAA==.',Wu='Wubadub:BAAALAADCggICAAAAA==.',Xa='Xavy:BAAALAAECgYIEQAAAA==.',Xe='Xenuis:BAAALAADCgYIAQAAAA==.',Xl='Xlirar:BAAALAAECgMIBAAAAA==.',Xx='Xxcoole:BAABLAAECoEZAAMBAAgI3RzcDgAhAgASAAgIwhhpGwBSAgABAAcINBzcDgAhAgAAAA==.',Ya='Yanami:BAAALAADCgcIBgAAAA==.Yanneh:BAAALAADCgYICAAAAA==.Yantiah:BAAALAADCggIFAAAAA==.Yaretzi:BAAALAADCggICAAAAA==.',Yi='Yirrae:BAAALAAECgIIAgAAAA==.',Yo='Yoink:BAAALAADCggICAAAAA==.',Za='Zagbab:BAAALAADCgYIBgAAAA==.Zalora:BAAALAADCggIEQAAAA==.Zaratta:BAAALAAECgEIAQABLAAECgMIAwAEAAAAAA==.',Ze='Zeeble:BAAALAAECgMIBwAAAA==.Zerafioo:BAAALAADCgEIAQAAAA==.',Zh='Zhaní:BAAALAADCggIFAAAAA==.',Zi='Zippy:BAABLAAECoEVAAIGAAcI3xm+EAAkAgAGAAcI3xm+EAAkAgAAAA==.Zitazen:BAAALAAECgcIDQAAAA==.Zitazigzag:BAAALAADCggIDgABLAAECgcIDQAEAAAAAA==.Zitazug:BAAALAADCggICAABLAAECgcIDQAEAAAAAA==.',Zn='Zneekhy:BAAALAAECgMIBwAAAA==.',Zo='Zoora:BAAALAAECgEIAQAAAA==.Zorga:BAAALAADCggIEgAAAA==.',Zy='Zyrelle:BAAALAAECgYICQAAAA==.',['Ðr']='Ðread:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end