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
 local lookup = {'Warlock-Demonology','Warlock-Destruction','Paladin-Retribution','Mage-Frost','Priest-Holy','Hunter-BeastMastery','Shaman-Elemental','Warlock-Affliction','Evoker-Devastation','DemonHunter-Havoc','Priest-Shadow','Unknown-Unknown','Evoker-Preservation','Monk-Brewmaster','Paladin-Protection','Paladin-Holy','Mage-Arcane','Shaman-Restoration','Hunter-Marksmanship','DeathKnight-Frost','DeathKnight-Blood','Warrior-Fury','Evoker-Augmentation','Priest-Discipline','Hunter-Survival','Druid-Restoration','DemonHunter-Vengeance','DeathKnight-Unholy','Monk-Mistweaver','Warrior-Protection','Shaman-Enhancement','Druid-Balance','Warrior-Arms','Rogue-Assassination','Monk-Windwalker','Mage-Fire','Rogue-Outlaw','Rogue-Subtlety','Druid-Feral',}; local provider = {region='EU',realm='Bronzebeard',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aande:BAAALAAECgcIBwAAAA==.',Ab='Abzynth:BAAALAADCgcIBwAAAA==.',Ad='Adamzandalar:BAAALAAECgIIAgAAAA==.',Af='Afkontrash:BAABLAAECoEkAAMBAAgI0CW5AAB8AwABAAgI0CW5AAB8AwACAAEIwR8txABeAAAAAA==.',Aj='Ajaks:BAABLAAECoEdAAIDAAcIRAkEqQBmAQADAAcIRAkEqQBmAQAAAA==.',Al='Alcove:BAAALAADCggICAAAAA==.Aldar:BAABLAAECoEXAAIEAAcIehCbLQCdAQAEAAcIehCbLQCdAQAAAA==.Alkhan:BAAALAAECgIIAgAAAA==.Alphoe:BAACLAAFFIEJAAIFAAUIxxpCBADCAQAFAAUIxxpCBADCAQAsAAQKgRYAAgUACAjNIgUOAOACAAUACAjNIgUOAOACAAAA.',Am='Amyrantha:BAAALAAFFAEIAQAAAA==.',An='Andromath:BAAALAAECgcIDQAAAA==.Andyaib:BAABLAAECoEcAAIGAAcInRh1SAD6AQAGAAcInRh1SAD6AQAAAA==.Andyshamberg:BAABLAAECoERAAIHAAYIWBfUSQCqAQAHAAYIWBfUSQCqAQAAAA==.Animafel:BAABLAAECoEXAAQIAAcI8RTqCgDqAQAIAAcIthPqCgDqAQABAAMIWwsxYwCrAAACAAEIrwG+4QAMAAAAAA==.Animalistica:BAAALAADCgMIAwAAAA==.',Ar='Aris:BAAALAADCgEIAQAAAA==.Arkana:BAAALAADCgcIBwAAAA==.Arkefiende:BAAALAADCggIGwAAAA==.Arki:BAAALAAECgcICAABLAAFFAYIEQAJAG8cAA==.Armst:BAAALAAECgcIEQAAAA==.Arvioch:BAAALAADCggIFQAAAA==.Arxalia:BAABLAAECoEcAAIKAAcILRlERwAZAgAKAAcILRlERwAZAgAAAA==.Arxaya:BAABLAAECoEjAAILAAYILBV6PwCWAQALAAYILBV6PwCWAQAAAA==.',As='Ashman:BAAALAADCggIFwAAAA==.Astral:BAAALAADCgUIBQAAAA==.',Ax='Axington:BAAALAAECgUICAAAAA==.',Az='Azzandra:BAAALAAECgcICgAAAA==.',Ba='Baabaa:BAAALAADCggIAQAAAA==.Baltar:BAAALAADCggICAAAAA==.Bambam:BAAALAADCggICAAAAA==.Barstardo:BAAALAADCgQIBAABLAAECgYIEAAMAAAAAA==.Batrachotoxi:BAAALAADCgQIBAAAAA==.',Be='Belgaraht:BAAALAADCgcIFAAAAA==.Benetleilax:BAAALAADCgcIBwABLAADCggIGQAMAAAAAA==.Bengrimm:BAAALAADCggICAAAAA==.Betty:BAABLAAECoEUAAMNAAcIZwlbHwAsAQANAAcIZwlbHwAsAQAJAAII3Qi8UwBeAAAAAA==.',Bi='Bidanka:BAAALAADCgMIAwAAAA==.',Bl='Blockbuster:BAAALAAECggIDgABLAAFFAYICwAOAB4TAA==.Bloodfavor:BAAALAADCgMIAwABLAAECgEIAQAMAAAAAA==.Bluntclawz:BAAALAADCggIEAABLAAFFAIICAACALQHAA==.',Bo='Boarslayer:BAABLAAECoEeAAIGAAYIOx8uUQDhAQAGAAYIOx8uUQDhAQAAAA==.Bobjob:BAAALAAECgYICQAAAA==.Boonkamp:BAAALAADCggIFQAAAA==.Booper:BAAALAADCggICAAAAA==.Bopo:BAAALAAECggIDQAAAA==.Borovnica:BAAALAAECgYIEAAAAA==.Bouch:BAAALAADCggIEAABLAAECgcIFAAFAK4HAA==.Bourbonbane:BAAALAADCgMIAwAAAA==.',Br='Bregolas:BAABLAAECoEcAAMPAAgIyBUwHQDNAQAPAAgIyBUwHQDNAQAQAAEIvAEFaAAjAAAAAA==.Bregor:BAAALAAECgYIBgAAAA==.Brixey:BAAALAADCggIEAABLAAECgYIEAAMAAAAAA==.Brixi:BAAALAAECgYIEAAAAA==.Brolyy:BAAALAADCgEIAQABLAAECgQIBAAMAAAAAA==.',Bu='Bulkhogan:BAAALAADCggICAAAAA==.Burst:BAAALAADCggICAAAAA==.',Ca='Cachocabra:BAAALAADCggIEwAAAA==.Calabria:BAAALAADCggIDwAAAA==.Caldrien:BAAALAAECggICwAAAA==.Catspaw:BAAALAAECgEIAQAAAA==.Cawpse:BAAALAAECggICAAAAA==.',Ch='Chakax:BAAALAAECgYIEQABLAAECgYIFAAJAD0UAA==.Chamansito:BAAALAAECgIIAgABLAAECgUIAgAMAAAAAA==.Cheeseflap:BAAALAAECggICAAAAA==.Chelioschev:BAAALAAECgMIAwAAAA==.Chica:BAACLAAFFIELAAMRAAQIgxgEDwBgAQARAAQIgxgEDwBgAQAEAAEIth0hFgBIAAAsAAQKgSUAAxEACAiuIi8fALsCABEACAjbIC8fALsCAAQACAi4HgEUAFgCAAAA.Chodrinks:BAAALAADCgYIBgAAAA==.Chokii:BAAALAAECgYIDQAAAA==.Chubbs:BAAALAAECgEIAQABLAAFFAYIEQAJAG8cAA==.Chuggi:BAAALAAECggIEAAAAA==.',Ci='Cinithri:BAACLAAFFIENAAIKAAQIkRlLCQCFAQAKAAQIkRlLCQCFAQAsAAQKgS4AAgoACAjNIgUQABsDAAoACAjNIgUQABsDAAAA.',Cl='Cloúd:BAAALAADCgcICwAAAA==.',Co='Col:BAAALAAECgMIBgABLAAECgcICgAMAAAAAA==.Colee:BAAALAAECgcICgAAAA==.Cormac:BAAALAAECgUIBQAAAA==.',Cr='Craciun:BAABLAAECoEXAAIHAAYIAghZbQAtAQAHAAYIAghZbQAtAQAAAA==.Cremeegg:BAABLAAECoEYAAICAAgIgCAFHwCpAgACAAgIgCAFHwCpAgABLAAFFAIIBQASALAiAA==.Crix:BAAALAAECggIDgAAAA==.Cruz:BAABLAAECoEZAAMTAAgIjx0EGgB6AgATAAgIjx0EGgB6AgAGAAUIBRSIqQAcAQAAAA==.Crystalball:BAAALAAECgYIBwAAAA==.',Da='Danray:BAACLAAFFIEMAAMDAAQISCF5BgCCAQADAAQISCF5BgCCAQAPAAEIgQxrFQBGAAAsAAQKgSYAAgMACAgGJRQNADYDAAMACAgGJRQNADYDAAAA.Danue:BAAALAAECgEIAQAAAA==.Darealnugget:BAABLAAECoEhAAMHAAgI1xAcNwD5AQAHAAgI1xAcNwD5AQASAAMIExEI1wCPAAAAAA==.Darkarrow:BAAALAAECgcIBwABLAAECgcIDgAMAAAAAA==.Darkillusion:BAAALAAECgYIBgABLAAECgYIEAAMAAAAAA==.Daxx:BAAALAAECgYIBgAAAA==.',De='Deathanya:BAAALAAECgIIAgAAAA==.Deathofrats:BAABLAAECoEVAAIGAAYInQs2nwAyAQAGAAYInQs2nwAyAQAAAA==.Deathsight:BAABLAAECoEXAAIKAAcIHR1LNwBRAgAKAAcIHR1LNwBRAgAAAA==.Debtstrike:BAABLAAECoEZAAIUAAgIxx9+IgDBAgAUAAgIxx9+IgDBAgAAAA==.Derringer:BAAALAADCgcIDwAAAA==.Deàth:BAABLAAECoEXAAIVAAgIJSa5AAB9AwAVAAgIJSa5AAB9AwABLAAFFAMIDAAWAFshAA==.',Di='Discobouch:BAABLAAECoEUAAMFAAcIrgckXwA1AQAFAAcIrgckXwA1AQALAAIIgQI6hAA9AAAAAA==.Dizziet:BAAALAAECgYIBgAAAA==.',Do='Dobrous:BAAALAADCggIJgAAAA==.Dominus:BAAALAAECgcIEAAAAA==.Donat:BAAALAADCggIEAAAAA==.Dovahkiin:BAABLAAECoEUAAIJAAYIPRRPMgBuAQAJAAYIPRRPMgBuAQAAAA==.Dovla:BAABLAAECoETAAIUAAcIEB2SRABDAgAUAAcIEB2SRABDAgAAAA==.',Dp='Dps:BAABLAAECoEdAAIDAAgIWCGOGAD1AgADAAgIWCGOGAD1AgAAAA==.',Dr='Dragula:BAAALAADCggIGQAAAA==.Drakarys:BAACLAAFFIERAAMJAAYIbxy0BACtAQAJAAUIjBi0BACtAQAXAAIImxwCBAC1AAAsAAQKgScAAwkACAgQJd0DAEYDAAkACAgDJd0DAEYDABcABQhDHB4JAKMBAAAA.Dreamoflesh:BAAALAADCggICAAAAA==.Druii:BAAALAAECgUICQAAAA==.',Du='Dunban:BAAALAADCgcIBwAAAA==.Durendal:BAABLAAECoEVAAIDAAcIah48NwBoAgADAAcIah48NwBoAgAAAA==.',['Dí']='Dínkleberg:BAAALAAECgYIBgABLAAECgYIEgAMAAAAAA==.',Ec='Eccos:BAAALAADCgMIAwAAAA==.',Ed='Edhraan:BAAALAAECggICwAAAA==.',Ee='Eevee:BAABLAAECoEZAAIKAAgIwRJiTAAKAgAKAAgIwRJiTAAKAgAAAA==.',Ei='Eirill:BAAALAADCgYICAAAAA==.',El='Elenori:BAABLAAECoEXAAIYAAcIeA/bDwBuAQAYAAcIeA/bDwBuAQAAAA==.Ellesméra:BAABLAAECoEeAAIDAAgIcQ1CggCuAQADAAgIcQ1CggCuAQAAAA==.Elliora:BAAALAADCggIDgAAAA==.',Er='Er:BAAALAAECgYIEAAAAA==.Eralock:BAAALAAECgUICwABLAAECggIJgAZAF4aAA==.Erather:BAABLAAECoEmAAIZAAgIXhpcBACHAgAZAAgIXhpcBACHAgAAAA==.Eruthar:BAAALAAECgIIAgABLAAECggIJgAZAF4aAA==.',Ex='Explosion:BAAALAADCggIEAAAAA==.',Ez='Ezzar:BAAALAAECgQIBAAAAA==.',Fa='Faladorus:BAAALAADCgUIBQABLAAECggICAAMAAAAAA==.Fayed:BAABLAAECoEfAAIaAAcIiBolJgAbAgAaAAcIiBolJgAbAgAAAA==.Fazuli:BAAALAAECgIIAgAAAA==.',Fe='Felballz:BAABLAAECoEUAAIbAAYIMxVKIQBpAQAbAAYIMxVKIQBpAQAAAA==.Feloni:BAAALAADCggICAAAAA==.',Fi='Fierabras:BAAALAAECgYICQAAAA==.Firisti:BAAALAADCggICAAAAA==.',Fl='Flamehof:BAABLAAECoEVAAIDAAcIARnOWwD/AQADAAcIARnOWwD/AQAAAA==.Flonk:BAAALAADCgcIBwAAAA==.Flygeknurr:BAAALAAECgMIAwAAAA==.',Fo='Foxie:BAABLAAECoEfAAICAAcIowkZdABcAQACAAcIowkZdABcAQAAAA==.',Fr='Frang:BAAALAAECgEIAQAAAA==.Frizzels:BAAALAAECgUICQAAAA==.From:BAAALAAECggIEQAAAA==.Frostbat:BAAALAADCgEIAQAAAA==.Frostyelf:BAABLAAECoEXAAIRAAgIIxzwJQCaAgARAAgIIxzwJQCaAgAAAA==.Frownedupon:BAAALAADCgYIBgAAAA==.Fréd:BAAALAAECgYIEgAAAA==.',Fu='Fudrick:BAAALAAECgcICgAAAA==.',['Fú']='Fúbarr:BAAALAADCggICAAAAA==.',Ga='Garfield:BAAALAADCgIIAgAAAA==.',Ge='Gea:BAAALAADCggICAAAAA==.Gehaktmolen:BAAALAADCgUIBQAAAA==.Gelato:BAAALAADCgYICgABLAAECgYIEAAMAAAAAA==.Geéspot:BAABLAAECoEZAAIDAAgIXxLMWAAGAgADAAgIXxLMWAAGAgAAAA==.',Go='Golem:BAAALAADCgcIBwAAAA==.',Gr='Grabmyplúms:BAABLAAECoEaAAMUAAcI+wWA0AAuAQAUAAcIBAWA0AAuAQAcAAMIZwV2QwCMAAAAAA==.Grampaw:BAABLAAECoEUAAIaAAcI/hffMADkAQAaAAcI/hffMADkAQAAAA==.Grimmen:BAAALAADCggIEAAAAA==.Grimskull:BAABLAAECoEUAAIWAAcIlhuLMAA6AgAWAAcIlhuLMAA6AgAAAA==.Gruel:BAAALAADCgcIDAAAAA==.',Gu='Gucchitank:BAAALAAECgcIEgAAAA==.',Gw='Gwenllian:BAAALAADCggIDwAAAA==.',Ha='Haitch:BAAALAAECgMIBQAAAA==.Hanny:BAAALAADCggIDQABLAAECgMIBgAMAAAAAA==.Happydemon:BAAALAADCggICAAAAA==.',He='Headles:BAAALAADCgYICgABLAAECgcIEwAUABAdAA==.Hellsiege:BAABLAAECoEZAAIKAAYIeyWDKACSAgAKAAYIeyWDKACSAgAAAA==.',Hi='Hina:BAAALAADCgUIBQABLAADCgcIBAAMAAAAAA==.',Ho='Horrend:BAACLAAFFIEOAAIVAAUIpRUcAwCJAQAVAAUIpRUcAwCJAQAsAAQKgRYAAxUACAisIWgIAKwCABUACAisIWgIAKwCABQAAQjBE4RGATMAAAEsAAUUBggLAA4AHhMA.',Hr='Hrappur:BAAALAAECgEIAQAAAA==.',Hu='Huntauxie:BAAALAAECggICAAAAA==.',Hy='Hybiscus:BAABLAAECoEfAAIKAAcIug+yfgCSAQAKAAcIug+yfgCSAQAAAA==.',['Hô']='Hôly:BAAALAAECgQIBAABLAAFFAMIDAAWAFshAA==.',Ia='Iamhim:BAAALAAECgIIAgAAAA==.',Ig='Igotyoubro:BAAALAADCgQIBAABLAAECgYICQAMAAAAAA==.',Ih='Ihunt:BAAALAADCgcIDgAAAA==.',Il='Illdain:BAAALAAECgIIAQAAAA==.',In='Infreign:BAAALAAECgYIDAAAAQ==.',Io='Ionut:BAAALAAECgUIBQABLAAFFAMICwAGAAIKAA==.',Ir='Irage:BAAALAADCgYICAAAAA==.Irasnus:BAAALAAECgYIAQAAAA==.',Is='Isartais:BAAALAAECgUICQAAAA==.Iskier:BAAALAADCgIIAgAAAA==.Israphael:BAACLAAFFIEFAAIKAAMI+xMQEAAAAQAKAAMI+xMQEAAAAQAsAAQKgRYAAgoABgi8I501AFgCAAoABgi8I501AFgCAAEsAAUUBggRAAkAbxwA.',Ja='Jackera:BAAALAADCgEIAQAAAA==.',Je='Jerbert:BAABLAAFFIEGAAIOAAII5RfmCwCVAAAOAAII5RfmCwCVAAAAAA==.Jerelaand:BAAALAADCgEIAQAAAA==.',Ji='Ji:BAAALAAECgIIAgABLAAECggIJAAdAH4kAA==.Jimmï:BAAALAADCgcIBwAAAA==.Jinah:BAABLAAECoEmAAMFAAgIaSXSAgBbAwAFAAgIaSXSAgBbAwALAAYIPBdJPQChAQAAAA==.Jinladen:BAAALAAECgUIBwAAAA==.Jinquisitor:BAAALAAECggICAAAAA==.Jinsolini:BAAALAADCggICAAAAA==.Jixun:BAAALAAECgUIBgAAAA==.Jizum:BAABLAAECoEXAAICAAYIFw5negBMAQACAAYIFw5negBMAQAAAA==.',Jo='Johnwárcraft:BAAALAAFFAEIAQAAAA==.Jordz:BAAALAAECgYIDAABLAAECgYIFAAJAD0UAA==.',Ju='Judgemental:BAAALAAECgYIBgABLAAECggIGQATAI8dAA==.',Ka='Kairos:BAABLAAECoEVAAIQAAgIrRY4FgAtAgAQAAgIrRY4FgAtAgAAAA==.Kallystra:BAAALAAECgIIAgAAAA==.Kallystraza:BAAALAAECgUIDAAAAA==.Katemci:BAABLAAECoEXAAIeAAcIIAjYRAAYAQAeAAcIIAjYRAAYAQAAAA==.Kattlian:BAAALAAECgYIEwAAAA==.Kaylexxl:BAAALAAECgMIAgAAAA==.',Ke='Kelogg:BAAALAADCggIBgAAAA==.Kennoby:BAAALAADCggICAAAAA==.Kenta:BAAALAAECgcIDwAAAA==.Ketod:BAAALAAECgEIAQAAAA==.',Ki='Kieralock:BAABLAAECoEZAAMCAAgIVgrDXwCVAQACAAgIVgrDXwCVAQABAAEIVATgjAAfAAAAAA==.Kiillergiirl:BAAALAAECgcIDAAAAA==.Killforblood:BAABLAAECoEWAAIfAAgIpRnbCgAbAgAfAAgIpRnbCgAbAgAAAA==.',Kl='Klinker:BAAALAADCggIDQAAAA==.',Kn='Knom:BAAALAAECgUIBQABLAAECgYIEgAMAAAAAA==.',Kr='Kroepoek:BAAALAAECgMIAwAAAA==.Krácker:BAAALAADCgUIBQAAAA==.',Ku='Kuman:BAAALAAECgcICgAAAA==.',Kv='Kvetina:BAAALAADCgUIBQAAAA==.',Ky='Kypdurron:BAABLAAECoEYAAIDAAgILxrKNABxAgADAAgILxrKNABxAgAAAA==.',La='Lapiscub:BAAALAAECgMIAwAAAA==.',Li='Lieweheksie:BAAALAADCggICAAAAA==.Lilb:BAAALAAECgIIAgABLAAFFAYIEQAJAG8cAA==.Lilyholy:BAAALAAECgMIBQAAAA==.Linkle:BAAALAAECgUIBQAAAA==.Littlebetch:BAAALAAECggIDwAAAA==.',Ll='Llamabell:BAAALAADCgYICQABLAAECgYIFwACABcOAA==.',Lo='Lokoth:BAAALAADCgcIFAAAAA==.Lolaur:BAAALAAECgMIAwABLAAECgYIEAAMAAAAAA==.Lolayr:BAAALAAECgYIEAAAAA==.Lollypop:BAAALAADCggICAAAAA==.Lorbs:BAABLAAECoEYAAIGAAgIEAZSnwAxAQAGAAgIEAZSnwAxAQAAAA==.Lorther:BAABLAAECoEbAAMQAAgI8A+lIgDLAQAQAAgI8A+lIgDLAQADAAYIGAUo3wD4AAAAAA==.Lottiedottie:BAAALAADCgcIBwAAAA==.',Lu='Lucita:BAAALAAECgYICwAAAA==.Lumihiutale:BAAALAADCggICAAAAA==.Lumina:BAAALAADCggIEgAAAA==.Lumosall:BAAALAAECgEIAQAAAA==.Lurks:BAAALAADCgcIFAAAAA==.',Ma='Machodoom:BAAALAADCggICAABLAAECggIJgAKAFolAA==.Machoman:BAABLAAECoEmAAIKAAgIWiUzBABsAwAKAAgIWiUzBABsAwAAAA==.Machozard:BAAALAAECgYICwABLAAECggIJgAKAFolAA==.Macncheese:BAACLAAFFIERAAIbAAUICRcLAQCbAQAbAAUICRcLAQCbAQAsAAQKgSgAAhsACAjPItoDAB8DABsACAjPItoDAB8DAAAA.Macwhitey:BAAALAAECgYICAABLAAECgcIFAAFAK4HAA==.Magganii:BAAALAAECgIIAgAAAA==.Maggle:BAAALAAECgIIAgAAAA==.Maguna:BAAALAAECgIIAgAAAA==.Malenía:BAAALAAECgUIBQABLAAECgYIEgAMAAAAAA==.Mamahunu:BAAALAAECgEIAQAAAA==.Margiel:BAAALAAECggICAAAAA==.Marogar:BAABLAAECoEdAAMUAAcI1SFgLwCKAgAUAAcIKCFgLwCKAgAcAAQI3iHpLQA1AQAAAA==.Marss:BAABLAAECoEgAAMBAAgIrCDWEwA7AgACAAgIkRfYMgA8AgABAAYI5CDWEwA7AgAAAA==.Mathalmir:BAAALAAECgcIDwAAAA==.Maxhunter:BAAALAADCggIGQAAAA==.',Mb='Mbmonk:BAAALAADCggIDAABLAAFFAYIEQAJAG8cAA==.',Mc='Mcflanwee:BAAALAAECgYIAgABLAAECgYIEgAMAAAAAA==.Mctailor:BAABLAAECoEfAAISAAcIARZGTgDCAQASAAcIARZGTgDCAQAAAA==.',Me='Meerkat:BAAALAAECgUICQAAAA==.Merceyz:BAACLAAFFIEMAAIWAAMIWyEqDAAdAQAWAAMIWyEqDAAdAQAsAAQKgTQAAhYACAhqJkgBAIoDABYACAhqJkgBAIoDAAAA.',Mi='Mickypaly:BAAALAAECgYIDwAAAA==.Mir:BAAALAAECgYICwABLAAECgYIEgAMAAAAAA==.Mirthe:BAAALAAECgYIDwAAAA==.Missfiona:BAAALAADCgUIBQAAAA==.Misspaladin:BAAALAADCgIIAgAAAA==.Mistorca:BAAALAADCgYIBgAAAA==.Mittens:BAABLAAECoEUAAIFAAYIjxYuSgCDAQAFAAYIjxYuSgCDAQAAAA==.Mitts:BAAALAADCgIIAgAAAA==.',Mo='Moobicus:BAAALAAECgMIAwAAAA==.Moonsan:BAABLAAECoEYAAMgAAgIsAxqOACfAQAgAAgIsAxqOACfAQAaAAcIhgxVVABRAQAAAA==.Morgagni:BAAALAADCgcIBwAAAA==.Morghunt:BAAALAADCgcICQAAAA==.Morkish:BAAALAAECgYIDgAAAA==.',Mu='Mumford:BAAALAADCgYIBgAAAA==.',Mv='Mvu:BAAALAAECgYIDAAAAA==.',My='Myth:BAACLAAFFIEWAAIbAAYIPR05AAA5AgAbAAYIPR05AAA5AgAsAAQKgSIAAhsACAj1JhQAAJ4DABsACAj1JhQAAJ4DAAAA.Mythoss:BAAALAAFFAIIBAABLAAFFAYIEQAJAG8cAA==.',['Mí']='Mírr:BAAALAAECgMIAwABLAAECgYIEgAMAAAAAA==.',Na='Namibia:BAAALAAECgMIAwAAAA==.Naushika:BAABLAAECoEgAAIhAAgIVBwBBgCIAgAhAAgIVBwBBgCIAgAAAA==.',Ne='Nerd:BAAALAAECgYICwAAAA==.Netharel:BAAALAAFFAIIBAAAAA==.Netheru:BAABLAAECoEZAAIeAAcIHxeNJADTAQAeAAcIHxeNJADTAQAAAA==.Nettleleaf:BAAALAAECgcIEgAAAA==.Newgate:BAAALAADCggICgAAAA==.Neymar:BAAALAAFFAEIAQAAAA==.',Ni='Nightexecute:BAABLAAECoEXAAIWAAcINA1BXwCPAQAWAAcINA1BXwCPAQAAAA==.Nightlord:BAAALAADCgMIAwAAAA==.Nightravenn:BAAALAADCggIJgAAAA==.Niluna:BAAALAAECgcIDAABLAAECggIHwAiAF4gAA==.Nimms:BAAALAADCgcIEQAAAA==.Nimwen:BAAALAADCgQIBAAAAA==.Nitrazepam:BAAALAADCgQIBAAAAA==.Nixxus:BAABLAAECoEdAAMXAAgIDRqABQAgAgAXAAcIyhuABQAgAgAJAAYIvxQ7LQCRAQAAAA==.',No='Nochipa:BAAALAAECgYIBwAAAA==.Noeevil:BAAALAADCgUIBQAAAA==.Noeho:BAABLAAECoESAAMJAAYIBRmQJQDJAQAJAAYIBRmQJQDJAQANAAUIqw7MIgAIAQAAAA==.Noemagi:BAAALAADCggICAAAAA==.Noemata:BAAALAADCgEIAQAAAA==.Nolbyfied:BAAALAAECgEIAQAAAA==.Notchaggo:BAAALAADCgUIBQAAAA==.',Nt='Ntraatjeerbj:BAAALAAECggIEAAAAA==.',Ny='Nyende:BAAALAAECgcIBwAAAA==.',['Næ']='Næl:BAAALAADCgcIBwABLAAECggIHQADAFghAA==.',Oc='Oceanborn:BAAALAAECgcIEQAAAA==.Oceána:BAAALAADCgcICQAAAA==.',Oh='Ohiru:BAAALAADCgcIBwAAAA==.',Or='Orcztwo:BAAALAADCggIIAABLAAECgYIDgAMAAAAAA==.Orczy:BAAALAAECgYIDgAAAA==.Organa:BAABLAAECoEXAAIjAAYIthy2HADoAQAjAAYIthy2HADoAQAAAA==.',Ou='Ouchie:BAACLAAFFIEGAAIDAAIIyRzdGAC5AAADAAIIyRzdGAC5AAAsAAQKgRYAAwMACAhpFhpCAEUCAAMACAhpFhpCAEUCAA8AAQhrFsNcAC8AAAEsAAUUAwgFABYAExIA.',Pa='Palabrix:BAAALAAECgYIBgABLAAECgYIEAAMAAAAAA==.Paladanus:BAAALAADCgcIBwAAAA==.Paladef:BAAALAADCgYIBgAAAA==.Palisar:BAAALAAECgcIDQAAAA==.Pandam:BAAALAADCgQIBQAAAA==.Pants:BAABLAAECoEdAAIEAAcIkg/6LwCQAQAEAAcIkg/6LwCQAQAAAA==.',Pe='Penelope:BAAALAAECgMIBAAAAA==.',Ph='Phewphew:BAAALAADCgIIAQAAAA==.Philinoldasu:BAAALAAECgEIAQAAAA==.Phuzzy:BAAALAADCggIFAABLAAECggIFwAjACIXAA==.',Pi='Pigjuice:BAAALAAECgEIAQAAAA==.',Po='Poggish:BAABLAAECoEZAAIDAAgIshauQgBDAgADAAgIshauQgBDAgAAAA==.',Pp='Pphhuckdup:BAAALAAECggIEAAAAA==.',Pr='Primea:BAAALAAECgYIEAAAAA==.Primewylea:BAAALAAECgIIAgAAAA==.Prinders:BAABLAAECoElAAQCAAgIfhg3LQBZAgACAAgIfhg3LQBZAgABAAUIQBHRQwA4AQAIAAUIkhE7FwAxAQAAAA==.Provectus:BAAALAADCgYIBgAAAA==.',Pu='Purist:BAAALAAECgcIDwAAAA==.Puríster:BAABLAAECoEVAAIGAAcIXxclVgDUAQAGAAcIXxclVgDUAQAAAA==.',Qu='Quartz:BAAALAADCgUIBQAAAA==.Quiz:BAAALAAECgYIEAAAAA==.',Ra='Raavi:BAACLAAFFIENAAMLAAQIxRsXBwCAAQALAAQIxRsXBwCAAQAFAAMIEgMlFgC3AAAsAAQKgSsAAwsACAhWJCIFAEwDAAsACAhWJCIFAEwDAAUAAQhUDKGeADcAAAAA.Raccon:BAAALAADCgcIEgAAAA==.Ragingemó:BAAALAADCggICAAAAA==.Raijin:BAAALAAECgIIAgAAAA==.Raijín:BAAALAADCggIDAAAAA==.Rainiél:BAAALAAECgIIAgAAAA==.Rakkor:BAAALAADCggICwAAAA==.Raska:BAAALAAECgYIDwAAAA==.Rayge:BAAALAADCgEIAQAAAA==.Razorstorm:BAAALAAECgMIAwAAAA==.Razza:BAAALAAECggICAAAAA==.',Re='Realhunter:BAAALAADCgcIBwAAAA==.Reckzo:BAACLAAFFIENAAIKAAMIWxkSDwAKAQAKAAMIWxkSDwAKAQAsAAQKgTIAAgoACAjcIxwNAC0DAAoACAjcIxwNAC0DAAAA.Redsdk:BAAALAAECggIEwABLAAECggIFwAaALwMAA==.Redsdragon:BAAALAADCgMIAwABLAAECggIFwAaALwMAA==.Redsdruid:BAABLAAECoEXAAMaAAgIvAzSUABeAQAaAAgIvAzSUABeAQAgAAEIRggGiwAzAAAAAA==.Rellena:BAAALAAECggICAAAAA==.',Rh='Rhyi:BAABLAAECoEUAAIgAAcIEB5qGwBTAgAgAAcIEB5qGwBTAgAAAA==.',Ri='Rii:BAABLAAECoEkAAIdAAgIfiRgAgA5AwAdAAgIfiRgAgA5AwAAAA==.Rimefrost:BAAALAADCggICAAAAA==.',Ro='Rookie:BAAALAADCgUIBQAAAA==.Roseknightk:BAAALAAECggICAAAAA==.Royalflush:BAAALAADCgMIAwAAAA==.',Ry='Rylanor:BAAALAADCggIEwAAAA==.',['Rá']='Rátchet:BAAALAAECgYIDAAAAA==.Ráymond:BAAALAAECgEIAQAAAA==.Ráýmónd:BAAALAADCgcICgABLAAECgEIAQAMAAAAAA==.',['Rí']='Rí:BAAALAAECgcIBwABLAAECggIJAAdAH4kAA==.',Sa='Saeasa:BAABLAAECoEhAAIbAAgIDBJIGQC+AQAbAAgIDBJIGQC+AQAAAA==.Sakraú:BAAALAAECgEIAQAAAA==.Salash:BAABLAAECoEZAAICAAcIsgg9cgBhAQACAAcIsgg9cgBhAQAAAA==.Salky:BAAALAAECgYICgAAAA==.Sassyjane:BAAALAAECggIDwAAAA==.Savagejane:BAAALAAECgEIAgAAAA==.',Sc='Schildpad:BAAALAADCgcIBwAAAA==.',Se='Seiberrawr:BAAALAAECggIBgAAAA==.Selket:BAAALAADCgcIDgAAAA==.',Sh='Shadopan:BAABLAAECoEVAAIYAAcIwh4fBAByAgAYAAcIwh4fBAByAgAAAA==.Shadymira:BAAALAADCggIEQAAAA==.Shamaraman:BAAALAADCgQIBAAAAA==.Shamharoth:BAAALAADCgIIAgAAAA==.Shamkill:BAAALAADCgcIBwAAAA==.Shampons:BAAALAADCgUIAQAAAA==.Shamíx:BAAALAAECgUIAwAAAA==.Sharilyn:BAAALAAECgYICAAAAA==.Sharpeye:BAABLAAECoEcAAISAAgItwpljAAiAQASAAgItwpljAAiAQAAAA==.Shields:BAAALAAECgEIAQABLAAFFAYICwAOAB4TAA==.Shifson:BAABLAAECoEUAAMGAAgIZBOCjwBRAQAGAAYIwBKCjwBRAQATAAMI7g9lgQClAAAAAA==.Shikobo:BAAALAAECgcIEwAAAA==.Shinsoul:BAABLAAECoEeAAMCAAcI5RmRPQAMAgACAAcI5RmRPQAMAgABAAEITAy4iAAwAAAAAA==.Shmeather:BAAALAADCgIIAgAAAA==.Shockahontas:BAAALAAECgcICAAAAA==.Shockrock:BAAALAADCggICwAAAA==.',Si='Siennamae:BAAALAAECgMIBQAAAA==.Silchas:BAABLAAECoEUAAIkAAcIZRg1BQAYAgAkAAcIZRg1BQAYAgAAAA==.Sillbis:BAABLAAECoEXAAMjAAcI0QysKwBuAQAjAAcI0QysKwBuAQAdAAMIPQIuQgBIAAAAAA==.Sindrah:BAAALAADCggIDgAAAA==.Sineeya:BAABLAAECoEWAAISAAcI5hkQOgADAgASAAcI5hkQOgADAgAAAA==.Sinnersmark:BAAALAAECgYIBgABLAAECgYIFAAJAD0UAA==.Sipka:BAAALAADCggICAAAAA==.',Sk='Skeloth:BAABLAAECoEaAAIlAAYIvgcYEAAgAQAlAAYIvgcYEAAgAQAAAA==.',Sl='Slaminshamen:BAAALAAECgYIBgAAAA==.Slepy:BAAALAADCggIEAAAAA==.Slå:BAAALAAECgUICAAAAA==.',Sm='Smork:BAAALAADCgUIBQABLAAFFAIIBQAKAOIkAA==.',Sn='Sneakycrit:BAABLAAECoEfAAMiAAgIXiCdCgDWAgAiAAgIXiCdCgDWAgAmAAMI/BnwLQDcAAAAAA==.Sneax:BAABLAAECoEXAAIiAAcI9h9sEACQAgAiAAcI9h9sEACQAgAAAA==.Sneaxdruid:BAAALAAECgYIBgABLAAECgcIFwAiAPYfAA==.Sneaxhunter:BAAALAADCgYIBgABLAAECgcIFwAiAPYfAA==.',So='Soladormu:BAAALAADCgEIAQAAAA==.Solaenii:BAABLAAECoEcAAMLAAcIviGsFgCcAgALAAcIviGsFgCcAgAFAAYIlCIsKQAgAgAAAA==.Sookiie:BAABLAAECoEpAAIfAAgICh+AAwDqAgAfAAgICh+AAwDqAgAAAA==.Sova:BAAALAAECgcIEwABLAAECgYIEgAMAAAAAA==.',Sp='Spankytanky:BAAALAAECgMIAwABLAAECgYICQAMAAAAAA==.',Sq='Squashy:BAABLAAECoEYAAIUAAgICR9lIQDGAgAUAAgICR9lIQDGAgAAAA==.',Sr='Srba:BAAALAADCggICAAAAA==.',St='Star:BAAALAAECgQICgAAAA==.Stefani:BAABLAAECoEWAAIgAAcIGB2EHgA5AgAgAAcIGB2EHgA5AgAAAA==.Stella:BAAALAADCggIFwAAAA==.Stenhand:BAAALAAECgMIBQAAAA==.Stoneddwarf:BAAALAADCggIDgAAAA==.Stormbinder:BAAALAADCggIDgAAAA==.Stormovik:BAABLAAECoEdAAIGAAcIkQoQkABQAQAGAAcIkQoQkABQAQAAAA==.Stupido:BAAALAADCgQIAwABLAAECgYIEAAMAAAAAA==.Stórmstriker:BAAALAADCggIDwABLAAFFAIICAACALQHAA==.',Su='Sundee:BAAALAADCgYIBQAAAA==.Sunstars:BAAALAADCggIEQAAAA==.',Sv='Svéndalos:BAAALAADCgEIAQABLAADCgcIBwAMAAAAAA==.',Sw='Swaydeh:BAABLAAECoErAAInAAgIwyW8AAB1AwAnAAgIwyW8AAB1AwAAAA==.Sweetlips:BAAALAAECgYICgAAAA==.Swisstony:BAAALAAECgcIEwAAAA==.',Sy='Sylvius:BAABLAAECoEbAAMLAAgIlw/jNQDHAQALAAgIlw/jNQDHAQAYAAEI8RPULwA4AAAAAA==.',Ta='Tankaya:BAAALAADCgIIAgAAAA==.',Te='Tehenhauin:BAAALAAECgUIAgAAAA==.',Th='Thegaze:BAAALAAECgYIDQAAAA==.Themark:BAAALAAECgYICgAAAA==.Themilfie:BAAALAADCggIEQABLAAECgYICgAMAAAAAA==.Thoraahh:BAAALAADCgUICQABLAAECgYIFwAjALYcAA==.Thorbard:BAAALAADCgYICwAAAA==.Thoriy:BAAALAAECgcICgAAAA==.Thracius:BAAALAAECgYIDwAAAA==.Thunderbobs:BAABLAAECoEaAAIHAAcIoRXWOADxAQAHAAcIoRXWOADxAQAAAA==.Thunk:BAAALAAECgEIAQAAAA==.',Ti='Tinymee:BAABLAAECoEXAAIPAAcI7BlrGQDuAQAPAAcI7BlrGQDuAQAAAA==.Tirisfal:BAAALAAECgUICQAAAA==.Tisniveel:BAABLAAECoEWAAILAAgI6xsFFwCZAgALAAgI6xsFFwCZAgAAAA==.',Tn='Tnt:BAAALAADCggIGAAAAA==.',To='Tombstone:BAAALAAECgYIBwAAAA==.Totsugeki:BAAALAADCggICAAAAA==.',Tr='Trapezia:BAAALAADCgYIBgAAAA==.Trumber:BAAALAAFFAIIAgABLAAFFAUIAgAMAAAAAA==.',Tw='Twistedangel:BAAALAAECgUIBwABLAAFFAQIDAADAEghAA==.',Um='Umo:BAABLAAECoEdAAIhAAgIgw8tDQDfAQAhAAgIgw8tDQDfAQAAAA==.',Uo='Uomnidas:BAAALAADCgUIBwAAAA==.',Ur='Urmehr:BAACLAAFFIELAAIWAAQIORLoCQBMAQAWAAQIORLoCQBMAQAsAAQKgSYAAhYACAimIS0UAOwCABYACAimIS0UAOwCAAAA.',Va='Valcyrie:BAABLAAECoEhAAIGAAgIMRnAOAAvAgAGAAgIMRnAOAAvAgAAAA==.Valtari:BAAALAAECggIEwAAAA==.Vantorus:BAAALAAECgMIAwAAAA==.',Ve='Vegetaa:BAAALAAECgQIBAAAAA==.Vezus:BAAALAAECgYIDAAAAA==.',Vi='Villanelle:BAAALAAECgYIBgAAAA==.Virage:BAAALAAECgEIAQAAAA==.Vistario:BAAALAADCggICAAAAA==.Vixéns:BAAALAAECggICAAAAA==.',Vo='Voidrea:BAAALAADCggICAAAAA==.Voncarstein:BAAALAAECgQIBAABLAAECgYIEgAMAAAAAA==.',Vr='Vritra:BAAALAADCggIFgAAAA==.',Wa='Warinier:BAAALAADCgUIBQAAAA==.Warkeff:BAABLAAECoEVAAIeAAcI2xu0GgAhAgAeAAcI2xu0GgAhAgAAAA==.Watkuntfoo:BAABLAAECoEbAAIdAAgIExdVEQAoAgAdAAgIExdVEQAoAgAAAA==.',We='Welf:BAAALAAECgMIAwAAAA==.',Wi='Wigzdh:BAABLAAECoEUAAIbAAcIWQs4KwAeAQAbAAcIWQs4KwAeAQAAAA==.Wigzpreest:BAAALAADCgUIAQAAAA==.Wildassassin:BAAALAADCgYICQAAAA==.',Wr='Wroick:BAABLAAFFIELAAIOAAYIHhN5AgDlAQAOAAYIHhN5AgDlAQAAAA==.',Wu='Wubadub:BAAALAADCggICAAAAA==.',Xa='Xavy:BAABLAAECoEfAAILAAcIfwsoRAB/AQALAAcIfwsoRAB/AQAAAA==.',Xe='Xenuis:BAAALAADCgYIAQAAAA==.Xerelia:BAAALAAECgQIBQAAAA==.',Xl='Xlirar:BAAALAAECgYIEQAAAA==.',Xx='Xxcolee:BAAALAAECgIIAgABLAAECggIKQACAP0eAA==.Xxcoole:BAABLAAECoEpAAMCAAgI/R5qIgCUAgACAAgImxxqIgCUAgABAAcINBxpHAD3AQAAAA==.',Ya='Yanami:BAAALAADCgcIBgAAAA==.Yanneh:BAAALAADCgcIDwAAAA==.Yantiah:BAAALAAECgEIAQAAAA==.Yaretzi:BAAALAADCggICAABLAAECgYIBgAMAAAAAA==.',Ye='Yeiboi:BAAALAADCgQIBAAAAA==.Yeronimo:BAAALAADCggIFwAAAA==.',Yi='Yirrae:BAABLAAECoEWAAMRAAgIvxWIRgAOAgARAAgIvxWIRgAOAgAkAAEI9RBCGgBCAAAAAA==.',Yo='Yoink:BAAALAADCggICAAAAA==.',Za='Zagbab:BAAALAADCgYIBgAAAA==.Zalora:BAAALAAECgMIBgAAAA==.Zaratta:BAAALAAECgYIDAABLAAECgYIDwAMAAAAAA==.Zavaca:BAAALAADCggICAABLAAECgYIDwAMAAAAAA==.',Ze='Zeeble:BAABLAAECoEXAAIKAAcINiIZIwCtAgAKAAcINiIZIwCtAgAAAA==.Zelixyo:BAAALAAECgYIBgABLAAFFAMIBQAWABMSAA==.Zerafioo:BAAALAADCgEIAQABLAADCgUIAQAMAAAAAA==.',Zh='Zhaní:BAAALAAECgUIBQAAAA==.',Zi='Zippy:BAABLAAECoEcAAIEAAcIOxqMGwASAgAEAAcIOxqMGwASAgAAAA==.Zitazen:BAABLAAECoEZAAIjAAcISCE7DQChAgAjAAcISCE7DQChAgAAAA==.Zitazeth:BAAALAADCggIDQABLAAECgcIGQAjAEghAA==.Zitazigzag:BAAALAAECgEIAgABLAAECgcIGQAjAEghAA==.Zitazonk:BAAALAADCggIEAABLAAECgcIGQAjAEghAA==.Zitazug:BAAALAADCggICAABLAAECgcIGQAjAEghAA==.',Zn='Zneekhy:BAAALAAECgcIDgAAAA==.',Zo='Zoora:BAAALAAECgUICQAAAA==.Zorga:BAAALAADCggIGAAAAA==.',Zu='Zuco:BAAALAAECgYIBgAAAA==.',Zy='Zyrelle:BAABLAAECoEYAAIFAAgIpBYNJgAwAgAFAAgIpBYNJgAwAgAAAA==.',['Ðr']='Ðread:BAAALAAECgcIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end