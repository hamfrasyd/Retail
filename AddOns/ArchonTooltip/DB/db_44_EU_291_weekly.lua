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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Druid-Feral','Druid-Restoration','Evoker-Devastation','Shaman-Enhancement','Hunter-Marksmanship','Mage-Arcane','Mage-Frost','Paladin-Holy','Druid-Balance','Warrior-Protection','Monk-Mistweaver','Paladin-Retribution','Monk-Brewmaster','Paladin-Protection','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','Warrior-Fury','Priest-Holy','Priest-Discipline','Warlock-Demonology','DeathKnight-Unholy','Hunter-Survival','Shaman-Elemental','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Warlock-Affliction','Monk-Windwalker','Mage-Fire','Evoker-Augmentation','Rogue-Outlaw','Evoker-Preservation',}; local provider = {region='EU',realm='Eonar',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Aceholy:BAAALAADCgYIBgABLAADCgcIDAABAAAAAA==.Aceofwar:BAAALAADCgYICgABLAADCgcIDAABAAAAAA==.',Ad='Adamantia:BAAALAADCggIEAAAAA==.',Ae='Aetherin:BAAALAADCggICQAAAA==.',Ag='Agarwen:BAAALAAECggIDQAAAA==.Agrael:BAABLAAECoEXAAICAAgIWBobNgA5AgACAAgIWBobNgA5AgAAAA==.',Ah='Ahrodite:BAABLAAECoEXAAIDAAYIsiX8HQB3AgADAAYIsiX8HQB3AgAAAA==.',Ak='Akiwaki:BAAALAADCggICwAAAA==.',Al='Aletico:BAAALAAECgMIBAAAAA==.Alexstrasza:BAAALAAECgIIAgAAAA==.Alluria:BAAALAAECgEIAQAAAA==.',Am='Ameclya:BAABLAAECoEZAAMEAAgIyw9yGgCdAQAEAAcIrhByGgCdAQAFAAgI7w2tSQB5AQAAAA==.Amfy:BAAALAAECggIBAAAAA==.Amidrake:BAABLAAECoEZAAIGAAgIwBCHJADRAQAGAAgIwBCHJADRAQAAAA==.Amiwaru:BAAALAAECgMIBgAAAA==.',An='Angarus:BAAALAADCggICAAAAA==.Anubipala:BAAALAADCgcIBwAAAA==.',Ap='Aphid:BAAALAADCgcIDQAAAA==.',Aq='Aqira:BAAALAAECgQICgABLAAFFAQICwAHADQKAA==.',Ar='Artemis:BAABLAAECoEhAAMCAAgIvBInSgD1AQACAAgIvBInSgD1AQAIAAgILgrQTwBXAQAAAA==.Aryna:BAAALAADCgMIBAAAAA==.',As='Asmallpillow:BAAALAAECgEIAQAAAA==.Aspallsdaddy:BAABLAAECoEMAAMJAAYIlhE8jQA9AQAJAAYIkRA8jQA9AQAKAAMIVQviYACdAAAAAA==.Asperax:BAAALAADCggICAAAAA==.Asurian:BAAALAADCgEIAQAAAA==.',At='Atisha:BAAALAADCgIIAgAAAA==.',Av='Avatarr:BAAALAADCgcIBwAAAA==.',Az='Azareal:BAAALAADCggIFgAAAA==.Azula:BAAALAAECgIIAgAAAA==.',Ba='Backpass:BAABLAAECoEdAAIIAAcIigMefAC5AAAIAAcIigMefAC5AAAAAA==.Backtobasics:BAAALAAECgEIAQAAAA==.Bacon:BAAALAAECgYIBgABLAAFFAQICwAHADQKAA==.Baitslayer:BAAALAADCgMIAwAAAA==.',Be='Beaver:BAAALAAECgYIDgAAAA==.Beepo:BAAALAADCgUIBQAAAA==.Belrisha:BAAALAADCggICAABLAAECgcIHAALAIEiAA==.Bethany:BAAALAADCgIIAgAAAA==.',Bh='Bhilí:BAAALAAECgIIAwAAAA==.Bhíli:BAAALAAECgIIAgAAAA==.',Bi='Biblidru:BAABLAAECoEUAAIMAAgI5xzgEgCoAgAMAAgI5xzgEgCoAgABLAAECgcIHAALAIEiAA==.Bitm:BAAALAAECgcIBwAAAA==.',Bl='Blaine:BAABLAAECoEaAAINAAcI7iOaCgDXAgANAAcI7iOaCgDXAgAAAA==.Blarneymoss:BAAALAAECgEIAQAAAA==.Blodreina:BAABLAAECoEZAAIOAAgIyRQZFgDlAQAOAAgIyRQZFgDlAQAAAA==.Blödaxe:BAAALAAECgYIDAABLAAECggIGAAEAHAaAA==.',Bo='Bobbiee:BAAALAAECgQIBAAAAA==.Bodkin:BAAALAADCgQIBAAAAA==.Bomboclat:BAAALAADCgcIBwAAAA==.Boongo:BAAALAADCggIBgABLAAECgcIGgANAO4jAA==.',Br='Brankan:BAAALAADCggICAAAAA==.',Bu='Bubblepop:BAAALAAECgUIBgAAAA==.',Ca='Cahalith:BAABLAAECoEoAAIFAAgIzRehMADlAQAFAAgIzRehMADlAQAAAA==.Calandrinon:BAAALAAECgYICQAAAA==.Capella:BAABLAAECoEhAAICAAgIBhCJWADNAQACAAgIBhCJWADNAQAAAA==.Casan:BAAALAAECgYIEQAAAA==.',Ce='Celticmight:BAACLAAFFIEFAAIPAAIIBQ8dLQCcAAAPAAIIBQ8dLQCcAAAsAAQKgSwAAg8ACAgBHIcrAJcCAA8ACAgBHIcrAJcCAAAA.',Ch='Chedders:BAAALAADCggIDwAAAA==.Chewie:BAAALAAECgQIBwABLAAFFAQICwAHADQKAA==.Chillskill:BAAALAADCgQIBAAAAA==.Chorizo:BAAALAAECgQIBAABLAAFFAQICwAHADQKAA==.Chronalys:BAAALAADCgYIBgAAAA==.Chéf:BAAALAAECgcIDAAAAA==.',Cl='Clishor:BAAALAAECggIDwAAAA==.',Co='Cocoloco:BAAALAADCgQIBAABLAAFFAMIBwAQAF4KAA==.',Cr='Crimsön:BAAALAADCgMIAwAAAA==.Cringepuff:BAAALAAECgUIBQABLAAECggIJgARAD8iAA==.Croatiia:BAAALAADCgcIDQAAAA==.',['Cá']='Cáp:BAAALAADCggIEAAAAA==.',['Có']='Cóffèè:BAAALAAECgUIBQAAAA==.Cóffèé:BAAALAADCgQIBAAAAA==.',Da='Daffie:BAABLAAECoEQAAIIAAYIVh4jLAD9AQAIAAYIVh4jLAD9AQAAAA==.Dalkini:BAABLAAECoEaAAISAAcImg0QgwCIAQASAAcImg0QgwCIAQAAAA==.Dandadan:BAAALAAECgQIBAAAAA==.Dannic:BAABLAAECoEjAAITAAgIyxMwCgAaAgATAAgIyxMwCgAaAgAAAA==.Dannicd:BAAALAAECgIIAgAAAA==.Danyel:BAAALAADCggIFQAAAA==.Darkfayth:BAABLAAECoEaAAIFAAcIyB+wFwBzAgAFAAcIyB+wFwBzAgAAAA==.Darklorn:BAABLAAECoEiAAMUAAcITx0hDABbAgAUAAcITx0hDABbAgAVAAcIfRCkmgCKAQAAAA==.Darktouch:BAAALAADCggIFgAAAA==.Darkul:BAAALAADCggICAAAAA==.Darrior:BAABLAAECoEVAAIWAAcIBhMKRwDdAQAWAAcIBhMKRwDdAQAAAA==.',Db='Dbacic:BAABLAAECoEpAAIVAAgILBwUNQB1AgAVAAgILBwUNQB1AgAAAA==.',De='Deathchamp:BAAALAAECgMIBgAAAA==.Deathmutt:BAAALAADCggICAAAAA==.Delbar:BAABLAAECoEUAAIJAAYIHAopiwBEAQAJAAYIHAopiwBEAQAAAA==.Demostick:BAAALAADCggICAABLAAECggIJgARAD8iAA==.Demís:BAAALAADCggICAAAAA==.Derzix:BAAALAAECggICwAAAA==.Devilpala:BAAALAAECgUIBQAAAA==.',Dh='Dhunthor:BAAALAAECgEIAQAAAA==.',Di='Diamondrowe:BAABLAAECoEZAAMKAAcIixfAHQACAgAKAAcIixfAHQACAgAJAAYIdwJctQCqAAABLAAFFAMIBwAQAF4KAA==.Dikken:BAAALAADCggICAAAAA==.Discomania:BAABLAAECoEfAAMXAAgIVQlgVQBYAQAXAAgIjAZgVQBYAQAYAAQIqAmEIACgAAAAAA==.Discomon:BAAALAADCggICAAAAA==.',Do='Donock:BAABLAAECoEUAAIZAAcIrgjOMgB/AQAZAAcIrgjOMgB/AQAAAA==.Dookookoodoo:BAABLAAECoEgAAIUAAgIrx2rCACnAgAUAAgIrx2rCACnAgAAAA==.Doritos:BAAALAADCgIIAgABLAAFFAQICwAHADQKAA==.',Dr='Dracopuss:BAAALAADCgYIBgAAAA==.Dragonix:BAAALAADCgcIBwABLAAECggICgABAAAAAA==.Dragonjam:BAAALAAECgEIAQAAAA==.Draktand:BAAALAAECggIAgAAAA==.Dramallama:BAAALAAECgYICAAAAA==.Dreambot:BAABLAAECoEhAAMFAAcISSIeFwB4AgAFAAYIuCQeFwB4AgAMAAcIThxBHwAzAgABLAAFFAQIBgAZANQUAA==.Dreamspeaker:BAAALAADCgcICAAAAA==.Droganian:BAABLAAECoEbAAMTAAcIDR6iCgARAgATAAYI9R2iCgARAgAWAAcInBaOQgDuAQAAAA==.Droog:BAAALAAECgIIAgAAAA==.',Du='Dubfury:BAAALAAECgUIBQAAAA==.Dudleydragon:BAABLAAECoEXAAIWAAYIGwQ3mADZAAAWAAYIGwQ3mADZAAAAAA==.Dumpling:BAAALAAECgQIBAABLAAFFAQICwAHADQKAA==.Duurek:BAACLAAFFIEKAAIDAAMIfBX7DQDoAAADAAMIfBX7DQDoAAAsAAQKgSkAAgMACAgAHRUZAJICAAMACAgAHRUZAJICAAAA.',Dw='Dwuurek:BAAALAAFFAIIAgABLAAFFAMICgADAHwVAA==.',Ec='Eclesiarch:BAABLAAECoEWAAMaAAgIuSBjBgDhAgAaAAgIuSBjBgDhAgAVAAEIxRrqNgFLAAAAAA==.',El='Elayue:BAABLAAECoEXAAIPAAYItBAsqABoAQAPAAYItBAsqABoAQAAAA==.Elcamino:BAAALAADCggIDwAAAA==.Elenä:BAAALAAECgYICAAAAA==.Elfiain:BAAALAAECgMIAwAAAA==.Elfury:BAAALAADCgYICQAAAA==.Elileath:BAABLAAECoEZAAIMAAgIUxQAKgDtAQAMAAgIUxQAKgDtAQAAAA==.Eloey:BAAALAADCggICAAAAA==.Elvari:BAABLAAECoEhAAMMAAcIxCEfEwClAgAMAAcIxCEfEwClAgAFAAEI7RIZsgA2AAAAAA==.Elydryn:BAACLAAFFIEFAAMbAAIIbw75AwCbAAAbAAIIDgv5AwCbAAACAAEIchW3PQBHAAAsAAQKgSIAAxsACAhAH5ADAKkCABsACAhJHZADAKkCAAIACAhHHpxAABMCAAAA.Elymas:BAAALAADCgMIAwAAAA==.Elèssar:BAAALAAECgEIAQAAAA==.',Em='Emma:BAABLAAECoEkAAIOAAgIDxD0GgCoAQAOAAgIDxD0GgCoAQAAAA==.Emrysia:BAAALAADCgUIBQAAAA==.',En='Enneala:BAAALAADCgcIBwAAAA==.',Ep='Epok:BAAALAAECgEIAwAAAA==.',Er='Erannard:BAABLAAECoEcAAMaAAgIIRtzCwCBAgAaAAgIIRtzCwCBAgAVAAEIUQ73SgEsAAAAAA==.Erichspi:BAAALAAECgYICgAAAA==.Eriela:BAAALAAECgIIAgAAAA==.Eritreith:BAAALAAECggIEgAAAA==.',Es='Estheria:BAAALAADCgcIDgAAAA==.',Ev='Evonblade:BAAALAAECgYIEgAAAA==.',Fa='Fairfield:BAAALAAECggIBAABLAAECggICgABAAAAAA==.Faithfil:BAABLAAECoEYAAIXAAgIXRCnPAC8AQAXAAgIXRCnPAC8AQAAAA==.Fame:BAABLAAECoEaAAIPAAgI7hgXPwBPAgAPAAgI7hgXPwBPAgAAAA==.Famy:BAAALAAFFAIIAgAAAA==.Farcia:BAABLAAECoElAAIKAAgI8RqbDgCUAgAKAAgI8RqbDgCUAgABLAAFFAEIAQABAAAAAA==.Farel:BAAALAAECgIIAQAAAA==.',Fe='Feylaria:BAAALAADCgcIBwAAAA==.',Fi='Fino:BAAALAAECgQIBAAAAA==.Fippi:BAABLAAECoEfAAMDAAgI7RIDSgDPAQADAAgI7RIDSgDPAQAcAAMI1wd3kgB+AAAAAA==.',Fl='Flameboy:BAAALAADCgYIBgAAAA==.Flaskhals:BAABLAAECoEiAAMdAAgIHx5EJQCDAgAdAAgIJBxEJQCDAgAZAAMIYxqJUwDyAAAAAA==.Fleni:BAAALAADCggIDgAAAA==.',Fo='Fokuhila:BAAALAAECgYIDAAAAA==.',Fr='Friggadin:BAAALAADCggIBgAAAA==.Frigidbardot:BAAALAAECgUIBQAAAA==.',Ga='Galnajävul:BAAALAADCgEIAQAAAA==.Garlic:BAAALAADCgQIBAABLAAFFAQICwAHADQKAA==.',Ge='Gelpa:BAABLAAECoEdAAIcAAgI8RfjKgA5AgAcAAgI8RfjKgA5AgAAAA==.',Gi='Giracuza:BAAALAAECgQIBgAAAA==.',Go='Gondola:BAAALAADCggIDgAAAA==.Goonerboy:BAAALAADCggICAAAAA==.',Gr='Graffyre:BAAALAAECggIDwABLAAECggIEAABAAAAAA==.Granith:BAABLAAECoEWAAIcAAgIixtbHwB/AgAcAAgIixtbHwB/AgAAAA==.Grappriest:BAAALAAFFAMIAwAAAA==.Gratgreas:BAAALAAECgcIEAAAAA==.Greatbuddha:BAAALAAECgEIAQAAAA==.Grey:BAAALAAECgIIAgAAAA==.Grimholt:BAABLAAECoElAAMeAAgIJyJoCwBWAgAfAAcIviD2EgB0AgAeAAcIgx5oCwBWAgAAAA==.Grimn:BAAALAADCgEIAQABLAAECggIFgAaALkgAA==.',Gu='Guildofgold:BAAALAADCgcIDAABLAAECggIJAACAMAfAA==.Gullinfotm:BAAALAAECgYIDAAAAA==.Gullinkeg:BAAALAAECgIIAgAAAA==.Gullinshout:BAABLAAECoEeAAINAAgIqh/6DgCaAgANAAgIqh/6DgCaAgAAAA==.',Gy='Gyokuro:BAAALAAFFAEIAQAAAA==.',Ha='Halahar:BAAALAAECgYIEQAAAA==.Halestorm:BAAALAAECgMIAwAAAA==.Handsomebob:BAAALAADCggICAAAAA==.Hartley:BAAALAADCgcIBwABLAAECgYIGgAfAFElAA==.Harveyke:BAAALAADCggICQAAAA==.Hasse:BAABLAAFFIEGAAIeAAMIAwfgBwDKAAAeAAMIAwfgBwDKAAAAAA==.Hatefree:BAABLAAECoEUAAQEAAYIFg1uKgD0AAAEAAQIahJuKgD0AAAFAAUIagv8eADiAAAgAAYIQgMhIACwAAAAAA==.',Hb='Hbshaman:BAAALAADCggIDgABLAAECggIHAAPAIsLAA==.',He='Heli:BAAALAAECgYIBgAAAA==.Hernfjord:BAAALAADCggIGAAAAA==.',Hi='Hidell:BAAALAADCggICAAAAA==.',Ho='Hoit:BAAALAAFFAEIAQAAAA==.Holyflame:BAABLAAECoEUAAMRAAgIahrXGQDrAQARAAgIahrXGQDrAQAPAAIIgQ0hDwF+AAAAAA==.Holyphallus:BAAALAAECgEIAQABLAAECgYIEQABAAAAAA==.Holypix:BAACLAAFFIEFAAIXAAMIFhrkCwAJAQAXAAMIFhrkCwAJAQAsAAQKgSkAAxcACAjuIZwJAAoDABcACAjuIZwJAAoDACEABgglEnBHAHABAAAA.Holyprof:BAABLAAECoEnAAILAAgIwhYyFwAlAgALAAgIwhYyFwAlAgAAAA==.Holyrage:BAAALAAECggIEAAAAA==.Holyspons:BAAALAAECgYIEQAAAA==.',Hr='Hrafn:BAABLAAECoEeAAMdAAcImArwbQBtAQAdAAcIqQnwbQBtAQAZAAYIfgZsUAAAAQAAAA==.',Hu='Hugekokowner:BAAALAADCggICAAAAA==.Huh:BAAALAADCgcIBgAAAA==.Hunterdrizzt:BAAALAAFFAEIAgAAAQ==.Huntzil:BAAALAAECgYIBgABLAAECggIJgARAD8iAA==.Hustemun:BAAALAAECgYICwAAAA==.',Id='Idariel:BAABLAAECoEgAAIiAAcI2h8MCwB5AgAiAAcI2h8MCwB5AgAAAA==.',Ii='Iippi:BAAALAAECgQIBAAAAA==.',Ik='Ikthalon:BAAALAAECgUIBQABLAAECggIHAAaACEbAA==.',Il='Illidev:BAAALAADCgQIBAAAAA==.Illirock:BAAALAAECggICAAAAA==.',In='Indicud:BAABLAAECoEaAAIfAAYIUSV1EACQAgAfAAYIUSV1EACQAgAAAA==.Infuse:BAAALAAECgYIBgAAAA==.Innocent:BAAALAAECgYICgABLAAECggIIAAIAGIjAA==.',Ir='Irnbrew:BAAALAADCgQIBAAAAA==.',Is='Ishri:BAAALAAECgMICAAAAA==.',Ja='Jabberwocky:BAAALAADCggICAAAAA==.Jackichan:BAAALAADCgYIBgAAAA==.Jallena:BAAALAADCggIDgAAAA==.Jaroftears:BAAALAADCgcIBwAAAA==.Jazzor:BAAALAADCgcIDQAAAA==.',Je='Jezemalu:BAABLAAECoEaAAIDAAcI2AwbhwAuAQADAAcI2AwbhwAuAQABLAAECggIFAARAOASAA==.',Jh='Jhen:BAACLAAFFIENAAMjAAQInSFeAACiAQAjAAQInSFeAACiAQAdAAII2xgKIgCmAAAsAAQKgSEAAyMACAgWJjkAAIcDACMACAgWJjkAAIcDAB0AAQiGIz7BAGYAAAAA.',Ji='Jippe:BAABLAAECoEoAAIRAAgIuh6CCQCzAgARAAgIuh6CCQCzAgAAAA==.Jippi:BAABLAAECoEXAAQQAAcI9BsiEgAGAgAQAAcI9BsiEgAGAgAOAAcIGhTRGwCeAQAkAAQI7wtgQgDBAAAAAA==.',Ju='Justafrostie:BAAALAAECgcIDQAAAA==.Justshockit:BAAALAAECgcICgAAAA==.',['Jß']='Jß:BAABLAAECoEUAAIjAAgIdiS6AABiAwAjAAgIdiS6AABiAwAAAA==.',Ka='Kablamo:BAAALAADCgYICgABLAAECggIIgAlAP4gAA==.Kalimon:BAABLAAECoEmAAISAAgICyBQGQDkAgASAAgICyBQGQDkAgAAAA==.Kalonriel:BAABLAAECoEaAAICAAcISSH8KQBrAgACAAcISSH8KQBrAgAAAA==.Kalrissa:BAAALAADCggIHgAAAA==.Kamala:BAAALAAECgYIBQAAAA==.Karmao:BAAALAAECgYIBwAAAA==.Karosh:BAAALAADCgYIBgAAAA==.Kassiel:BAAALAADCggICAAAAA==.',Ke='Kekkuli:BAABLAAECoEmAAIdAAgIbBNnPQAMAgAdAAgIbBNnPQAMAgAAAA==.Kevi:BAAALAAECgEIAQAAAA==.',Ki='Kiama:BAAALAADCggICAAAAA==.Kidagakash:BAAALAADCgcIBwABLAAECgcIIAAiANofAA==.',Kl='Kliff:BAAALAAECgcIEgAAAA==.',Kr='Krazykilla:BAAALAADCgQIBAAAAA==.Krocken:BAAALAADCgcIFgAAAA==.Krugerr:BAAALAADCgcICQAAAA==.',Ks='Ksitzo:BAAALAADCgIIAgAAAA==.',Ku='Kujatus:BAAALAADCggICgAAAA==.',La='Laina:BAAALAAECgIIBAAAAA==.Larilla:BAABLAAECoEbAAIlAAcIPQNqDgDwAAAlAAcIPQNqDgDwAAAAAA==.Laundry:BAAALAAECgQIBAAAAA==.Laymore:BAABLAAECoEZAAITAAgIdh89AwDvAgATAAgIdh89AwDvAgAAAA==.Lazycodinq:BAAALAADCgYIBgAAAA==.',Le='Leiyung:BAABLAAECoEVAAIDAAYIxQoxrQDeAAADAAYIxQoxrQDeAAAAAA==.',Li='Lichlordess:BAAALAADCgQIBAAAAA==.Liekki:BAAALAAECgYIEQAAAA==.Lightelf:BAAALAAECggIEAABLAAECggIEAABAAAAAA==.Lillevän:BAAALAAECgQIBwAAAA==.Limoondk:BAAALAAECgMIAwAAAA==.Limtak:BAAALAAECgYIDAAAAA==.',Lm='Lmnt:BAABLAAECoEYAAIDAAgIZyLMCwDtAgADAAgIZyLMCwDtAgAAAA==.',Lo='Logo:BAAALAADCgEIAQABLAAECggIHgAVAG0gAA==.Logobeam:BAAALAADCggICAABLAAECggIHgAVAG0gAA==.Logodk:BAABLAAECoEeAAMVAAgIbSBBJgCwAgAVAAgI5h5BJgCwAgAaAAYItRwcGADhAQAAAA==.Logolock:BAAALAAECgcICQABLAAECggIHgAVAG0gAA==.Logomid:BAAALAADCggIBgABLAAECggIHgAVAG0gAA==.Logomidian:BAAALAAECgYIBgABLAAECggIHgAVAG0gAA==.Lolfunny:BAAALAADCgcIBwABLAAECgcIIgAYAKoZAA==.Loneflame:BAAALAADCgcICAAAAA==.Lorretchea:BAAALAADCggIEgAAAA==.Loube:BAAALAAECgcIEQABLAAECggIIgAlAP4gAA==.',Lu='Lucebree:BAAALAAFFAIIBAABLAAFFAMICgADAHwVAA==.Lumenar:BAAALAADCggIDAAAAA==.Luminate:BAAALAAFFAIIAgAAAA==.Lumos:BAAALAADCggIEQAAAA==.',['Lá']='Lárà:BAACLAAFFIEIAAIPAAIIRB1vHQCuAAAPAAIIRB1vHQCuAAAsAAQKgR4AAg8ACAj6Ic8WAP4CAA8ACAj6Ic8WAP4CAAAA.',Ma='Maaria:BAAALAADCggICAAAAA==.Macx:BAABLAAECoEcAAIdAAYI1Q3jdgBVAQAdAAYI1Q3jdgBVAQAAAA==.Madista:BAAALAAECgUIBwAAAA==.Magentta:BAAALAADCggICgAAAA==.Mahaisen:BAABLAAECoEoAAIkAAgILxdMFgArAgAkAAgILxdMFgArAgAAAA==.Mamacitapint:BAAALAAECggIBgAAAA==.Manifest:BAAALAAFFAEIAQAAAA==.Mannen:BAAALAAECgcICgAAAA==.Maousi:BAAALAADCgYIBgAAAA==.Marshmallows:BAAALAADCgcICQAAAA==.Maybé:BAAALAAECgYIDgAAAA==.',Mc='Mcb:BAAALAADCggIDgABLAAECgcIIgAYAKoZAA==.Mcchicken:BAACLAAFFIELAAIHAAQINAq3AQAfAQAHAAQINAq3AQAfAQAsAAQKgR0AAwcACAisGQQJAEcCAAcACAisGQQJAEcCABwABQi8EEduACkBAAAA.Mcflurry:BAAALAAECgQIBwABLAAFFAQICwAHADQKAA==.Mcfudge:BAAALAADCgEIAQAAAA==.',Me='Mehira:BAABLAAECoEYAAIEAAgIcBr+CwBmAgAEAAgIcBr+CwBmAgAAAA==.Meregob:BAAALAAECggIEAAAAA==.',Mi='Mikako:BAAALAADCggIFgABLAAECgcIIAAiANofAA==.Mileycryus:BAAALAAECgIIAgAAAA==.Milsandrea:BAAALAADCgYIBgAAAA==.Minnji:BAABLAAECoEiAAMlAAgI/iCvBAAvAgAJAAgI9B3oOABCAgAlAAYIHyGvBAAvAgAAAA==.Mira:BAACLAAFFIEHAAIQAAII9RjkCgCiAAAQAAII9RjkCgCiAAAsAAQKgSEAAhAABgjYIkwOAEICABAABgjYIkwOAEICAAAA.',Mo='Monkman:BAAALAADCggIBwAAAA==.Monosham:BAABLAAECoEfAAIcAAgInRXSKgA5AgAcAAgInRXSKgA5AgAAAA==.Montide:BAABLAAECoEWAAIDAAcILyGGHwBvAgADAAcILyGGHwBvAgAAAA==.Morkimus:BAAALAAECggIEwAAAA==.Morthill:BAAALAAECgIIAgABLAAECggIKAAkAC8XAA==.',Mu='Munchkinrex:BAAALAADCgcIBwAAAA==.',My='Mydadisbald:BAACLAAFFIEFAAIKAAIITRaWCACjAAAKAAIITRaWCACjAAAsAAQKgRcAAgoACAi6IbIHAP4CAAoACAi6IbIHAP4CAAAA.',Na='Nannyogg:BAEALAADCggIBwABLAAECgUIBwABAAAAAA==.Narchi:BAAALAAECgcIDgAAAA==.Natycakes:BAABLAAECoEkAAIFAAcIRxN6QgCVAQAFAAcIRxN6QgCVAQAAAA==.',Ne='Neirr:BAAALAAECgYICAAAAA==.Nemmar:BAAALAAECgYICAAAAA==.Nes:BAAALAADCggICAABLAAECgcIHgAOADggAA==.Nesquick:BAAALAADCgUIBQAAAA==.Ness:BAAALAADCggIEAABLAAECgcIHgAOADggAA==.Nessy:BAABLAAECoEeAAIOAAcIOCD8CgCNAgAOAAcIOCD8CgCNAgAAAA==.Neverdiesbtw:BAAALAAECgYIBgABLAAECgcIHAALAIEiAA==.',Ni='Nialin:BAAALAAECgYIEgAAAA==.Niezwykla:BAAALAADCggIDwAAAA==.Nitherium:BAABLAAECoEXAAIJAAcIbRnCQwAYAgAJAAcIbRnCQwAYAgABLAAFFAYIEQAZAMYcAA==.',No='Nonamee:BAAALAAECgEIAQAAAA==.Noodles:BAAALAADCgQIBAABLAAFFAQICwAHADQKAA==.Notpixie:BAAALAADCggICAAAAA==.Nouichido:BAABLAAECoEiAAISAAgI9hRmRgAcAgASAAgI9hRmRgAcAgAAAA==.Novadin:BAABLAAECoEZAAILAAgIAxekGQAPAgALAAgIAxekGQAPAgAAAA==.Novedaddy:BAAALAAECgQIBAABLAAECggIGQALAAMXAA==.Novedrake:BAAALAADCggICAABLAAECggIGQALAAMXAA==.Novemonk:BAAALAAECgYICAABLAAECggIGQALAAMXAA==.',Nq='Nquiera:BAAALAADCggIEwAAAA==.',Nu='Nuvgrkkr:BAAALAAECgYIBgAAAA==.',Ny='Nyanko:BAAALAADCgYIBgABLAAECgcIDgABAAAAAA==.Nylaathria:BAABLAAECoEUAAIRAAgI4BKCIQCnAQARAAgI4BKCIQCnAQAAAA==.',Or='Orliad:BAAALAAECggIEAAAAA==.',Os='Ossa:BAABLAAECoEfAAIfAAYIeQ5xOABlAQAfAAYIeQ5xOABlAQAAAA==.Oswald:BAAALAAECggIEwAAAA==.',Pa='Paagrio:BAAALAAECgcIEgAAAA==.Palyman:BAAALAAECgcICQABLAAECggIEAABAAAAAA==.',Pe='Peaceswallow:BAAALAAECggICwAAAA==.Peotrala:BAAALAADCggICAAAAA==.Pezadora:BAABLAAECoEjAAIJAAgIcBfxNgBKAgAJAAgIcBfxNgBKAgAAAA==.',Ph='Phlub:BAAALAADCggICAABLAAECgcIIAAmADcbAA==.',Pi='Pingping:BAAALAADCggICAAAAA==.Pixiepopp:BAAALAADCgMIBAAAAA==.',Po='Poerkies:BAAALAAECgYIBQAAAA==.Pondamork:BAAALAADCggICAAAAA==.Pooj:BAAALAAECggIBwAAAA==.Poxycatdk:BAAALAAECgYIBgAAAA==.',Pr='Priestjammy:BAAALAAECgcIDAAAAA==.Priestmaster:BAAALAAECgEIAQAAAA==.Profxsnape:BAAALAAECggICAAAAA==.',Pu='Puddleofmudd:BAAALAAECgIIBgABLAAECgcIIgAYAKoZAA==.Punchyellf:BAABLAAECoEdAAIQAAgIBBUPEgAHAgAQAAgIBBUPEgAHAgAAAA==.',Py='Pyrrah:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.',Qu='Quzkin:BAAALAADCgcICgAAAA==.',Ra='Raenys:BAAALAADCggICAAAAA==.Raiju:BAAALAADCgMIBAAAAA==.',Re='Rebørn:BAAALAAECgUIBgAAAA==.Redgold:BAABLAAECoEoAAMCAAgIyg6gZgCqAQACAAgIyg6gZgCqAQAIAAYIRARifAC4AAAAAA==.Redkill:BAAALAADCggIDgAAAA==.Remorse:BAAALAAECggIAQAAAA==.',Rh='Rhaelor:BAAALAADCggICAAAAA==.Rhoadryn:BAAALAADCggICAAAAA==.Rhodryyn:BAABLAAECoEZAAMUAAcIyBgyEgDtAQAUAAcIyBgyEgDtAQAVAAEIhRe+PAFBAAAAAA==.',Ri='Ribbuli:BAAALAAECgUIBQAAAA==.Rippi:BAAALAADCggIDgAAAA==.',Ro='Robertha:BAAALAAECgUIBQAAAA==.Roccalex:BAABLAAECoEkAAIPAAgIQxocLwCIAgAPAAgIQxocLwCIAgAAAA==.Roseblue:BAAALAADCggIHQAAAA==.Roserage:BAAALAADCggICwAAAA==.Rotation:BAAALAADCgcICgAAAA==.',Rp='Rpc:BAABLAAECoEiAAIYAAcIqhmOBwAPAgAYAAcIqhmOBwAPAgAAAA==.',Ry='Rydermedusa:BAAALAADCggIDwAAAA==.',Sa='Samuraibob:BAABLAAECoEmAAIIAAgIDyF6CwD6AgAIAAgIDyF6CwD6AgAAAA==.Sanoti:BAAALAAECgUIBQAAAA==.Santaluz:BAAALAAECgYICQAAAA==.Saphoura:BAAALAAECgcIBwABLAAECggIDgABAAAAAA==.Satino:BAACLAAFFIEOAAMeAAQIBB/RAgCfAQAeAAQIBB/RAgCfAQAnAAMIqRlVAQACAQAsAAQKgSgAAx4ACAgRJqgAAHYDAB4ACAi0JagAAHYDACcACAiOI9wBAAQDAAAA.Savíor:BAAALAADCggIDgABLAAECgcIIgAYAKoZAA==.',Sc='Scrollzdh:BAABLAAECoEfAAISAAcIDB98NQBYAgASAAcIDB98NQBYAgAAAA==.Scrollzi:BAAALAAECgIIAgAAAA==.',Sd='Sdragon:BAABLAAECoEWAAIQAAYIOxfVHAB7AQAQAAYIOxfVHAB7AQAAAA==.',Se='Seluria:BAAALAAECgQIBQAAAA==.Seorin:BAAALAADCgMIAwAAAA==.Seraphine:BAAALAADCgcIBwABLAADCggIEAABAAAAAA==.Serenmity:BAABLAAECoEWAAIQAAgIMATXKQD7AAAQAAgIMATXKQD7AAAAAA==.Serrate:BAAALAAFFAEIAQAAAA==.Sewendejsik:BAAALAADCggIBwAAAA==.',Sh='Shadybuddha:BAAALAADCgQIBAAAAA==.Shamary:BAABLAAECoEkAAIDAAgIdxBHZACFAQADAAgIdxBHZACFAQAAAA==.Shamay:BAAALAADCggICAAAAA==.Shawoman:BAAALAAECgMIAwABLAAFFAQIBgAZANQUAA==.',Si='Sillý:BAAALAAECgYIEAABLAAECgcIIgAYAKoZAA==.Silvermage:BAAALAAECggICAABLAAECggIEAABAAAAAA==.',Sk='Skimouri:BAABLAAECoEUAAMbAAYIGRaDDACsAQAbAAYIGRaDDACsAQACAAEIjglcBwE0AAAAAA==.Skogsvro:BAAALAADCgUIBAAAAA==.Skàrma:BAAALAADCggICAAAAA==.Skîa:BAABLAAECoEaAAIhAAgIIhUCLwDtAQAhAAgIIhUCLwDtAQAAAA==.',Sl='Slugstick:BAAALAAECgIIAgABLAAECggIJgARAD8iAA==.',So='Sorrowpath:BAAALAAECggICAAAAA==.',Sp='Sparklebutt:BAAALAAFFAMIBAAAAA==.Spoelio:BAAALAAECgcIBwABLAAECggIHgAVAG0gAA==.Spongie:BAAALAAECgUICQAAAA==.Spongíe:BAAALAAECgQIBAABLAAECgUICQABAAAAAA==.Spongîe:BAAALAADCggIGgABLAAECgUICQABAAAAAA==.',St='Stabbyace:BAAALAADCgUIBQABLAADCgcIDAABAAAAAA==.Stepal:BAAALAAECgcIDwAAAA==.Stinkfist:BAABLAAECoEhAAIWAAgIYSAWFwDYAgAWAAgIYSAWFwDYAgAAAA==.Strahil:BAAALAAECggIEAAAAA==.Strongbiceps:BAAALAADCgIIAwAAAA==.Studelf:BAAALAAECgMIAwABLAAFFAMIAwABAAAAAA==.',Su='Sugarplums:BAEALAAECgUIBwAAAA==.Suhri:BAAALAAECgEIAQAAAA==.Summonamon:BAAALAADCggIFgAAAA==.Superdude:BAAALAAECgYIEwAAAA==.',Sw='Swahy:BAAALAAECgIIAgAAAA==.Sweetlizzy:BAAALAAECgYICgAAAA==.Swiftmane:BAAALAAECgIIAgAAAA==.Swoleboi:BAAALAAECggIEAAAAA==.',Sy='Sylthas:BAABLAAECoEfAAIIAAcIoBNnPwCaAQAIAAcIoBNnPwCaAQAAAA==.',['Sé']='Séphyx:BAAALAAECgcIEwAAAA==.',['Sê']='Sêphyx:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.',['Sò']='Sòl:BAAALAAECgcICQABLAAECggIGAAEAHAaAA==.',Ta='Tacobuddy:BAAALAAECgIIBAAAAA==.',Te='Tenc:BAAALAADCggICQAAAA==.Tequima:BAAALAADCggIDgAAAA==.Tetsaaja:BAAALAAECgMIAwAAAA==.Tezs:BAAALAAECgIICAAAAA==.',Th='Therenewer:BAAALAAECgcIDAAAAA==.Thesauron:BAABLAAECoEkAAICAAgIwB+SFgDXAgACAAgIwB+SFgDXAgAAAA==.Thorck:BAAALAADCgMIAwAAAA==.Thorgrim:BAAALAAECgUIBQABLAAECgYIDwABAAAAAA==.Thunderfury:BAAALAAECgcIBwAAAA==.Thyroker:BAABLAAECoEfAAMmAAcIABiGBgD2AQAmAAcIABiGBgD2AQAoAAMIcASwMABrAAAAAA==.',Ti='Ticktock:BAAALAADCggICAABLAAECgcIGgANAO4jAA==.Tidebringer:BAAALAADCgcIBwABLAAECgcIIgAYAKoZAA==.Tigaleia:BAAALAADCgMIAwAAAA==.Tigarah:BAABLAAECoEXAAIcAAYIpwrjZgBFAQAcAAYIpwrjZgBFAQAAAA==.Tightpants:BAAALAADCgEIAQAAAA==.Tinkerbull:BAAALAAECgIIAgAAAA==.Tixxy:BAABLAAECoEkAAIdAAgIqhFoSQDeAQAdAAgIqhFoSQDeAQAAAA==.',To='Tourettes:BAABLAAECoEUAAIWAAgI5B5/FgDcAgAWAAgI5B5/FgDcAgABLAAFFAMIBgAeAAMHAA==.Tovera:BAAALAADCggIFwAAAA==.',Tr='Trekuplan:BAEALAAECgYIBgAAAA==.Tribunalx:BAAALAAECggICAAAAA==.Trustace:BAAALAADCgcIDAAAAA==.',Tu='Turbomini:BAACLAAFFIEHAAIfAAMIwg1UCgDxAAAfAAMIwg1UCgDxAAAsAAQKgSwAAx8ACAgvHzMMAMACAB8ACAisHjMMAMACAB4ABwj9FysRAPoBAAAA.',Tw='Twixie:BAAALAAECgYIBgAAAA==.',Tz='Tzarkan:BAAALAAECgIIAgABLAAECgcIIQAMAMQhAA==.',Va='Valoria:BAABLAAECoEdAAIJAAcIdgpWiABMAQAJAAcIdgpWiABMAQAAAA==.Vanga:BAAALAAFFAIIAgAAAA==.Vathrar:BAAALAADCggICAAAAA==.',Ve='Verani:BAAALAADCggICwABLAAFFAMICgALAI0dAA==.Verband:BAAALAAECgYIEAAAAA==.Veroz:BAAALAADCggICAAAAA==.',Wa='Warleader:BAAALAADCggIFAAAAA==.',We='Wetlock:BAAALAAECggICgAAAA==.',Wi='Wichajster:BAAALAADCggICAAAAA==.Wildie:BAAALAAECgEIAQAAAA==.Withavoker:BAAALAAECgIIAgAAAA==.',Wo='Womannen:BAABLAAECoEQAAMJAAgIAB+TTgDzAQAJAAgIbRyTTgDzAQAKAAIIaSAmYwCRAAAAAA==.',Wr='Wralock:BAAALAADCgcIBwAAAA==.',Xa='Xanador:BAAALAAECgQIBAAAAA==.',Xi='Xidrase:BAAALAADCgcIFAAAAA==.',Xu='Xulu:BAABLAAECoEoAAMXAAgIDiTsBAA9AwAXAAgIDiTsBAA9AwAhAAIICBP1cQCOAAAAAA==.',Xy='Xynestra:BAAALAAECggICAAAAA==.Xytanius:BAABLAAECoEgAAQdAAgI7R0nIAChAgAdAAgIHx0nIAChAgAZAAUIsBQkRAA2AQAjAAEI6AsRNwBDAAAAAA==.',Ya='Yagami:BAABLAAECoEYAAIVAAcINxTsbgDdAQAVAAcINxTsbgDdAQAAAA==.Yasdnil:BAAALAADCggICAAAAA==.',Ye='Yean:BAABLAAECoEYAAIPAAYIARSxoQBzAQAPAAYIARSxoQBzAQAAAA==.',Yn='Ynnead:BAAALAADCgcICAAAAA==.',Za='Zamper:BAAALAAECgYICgAAAA==.Zantick:BAAALAAECgYIBgABLAAECggIJgARAD8iAA==.Zarguth:BAAALAAECgQIBwAAAA==.',Zh='Zhulbrek:BAAALAAECgYICwAAAA==.',Zi='Ziki:BAAALAAFFAIIAgAAAA==.Zinobia:BAABLAAECoEXAAIhAAYI6gvIUABHAQAhAAYI6gvIUABHAQAAAA==.',Zu='Zukes:BAAALAAECgcIDQABLAAECggIHwAnAGwmAA==.Zuki:BAABLAAECoEfAAInAAcIbCZ8AQAaAwAnAAcIbCZ8AQAaAwAAAA==.Zuli:BAABLAAECoEmAAIRAAgIPyJLBgD4AgARAAgIPyJLBgD4AgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end