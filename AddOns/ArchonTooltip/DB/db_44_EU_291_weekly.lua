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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','Paladin-Retribution','Warrior-Arms','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Warlock-Demonology','Shaman-Restoration','Druid-Balance','Hunter-Survival','Shaman-Elemental','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','Warrior-Protection','Priest-Holy','Paladin-Holy','Warlock-Affliction','Paladin-Protection','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Mage-Fire','DeathKnight-Unholy','Rogue-Outlaw','Warrior-Fury',}; local provider = {region='EU',realm='Eonar',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Aceholy:BAAALAADCgYIBgABLAADCgYICQABAAAAAA==.Aceofwar:BAAALAADCgQIBAABLAADCgYICQABAAAAAA==.',Ag='Agarwen:BAAALAAECggICgAAAA==.Agrael:BAAALAAECgcIBwAAAA==.',Ah='Ahrodite:BAAALAAECgUICgAAAA==.',Al='Aletico:BAAALAADCgcIDgAAAA==.Alluria:BAAALAAECgEIAQAAAA==.',Am='Ameclya:BAAALAAECgcIBwAAAA==.Amfy:BAAALAAECggIBAAAAA==.Amidrake:BAABLAAECoEZAAICAAgIwBAeFwD2AQACAAgIwBAeFwD2AQAAAA==.Amiwaru:BAAALAADCggICAAAAA==.',Ap='Aphid:BAAALAADCgcIDQAAAA==.',Aq='Aqira:BAAALAAECgQICAABLAAFFAMICAADAAAIAA==.',Ar='Artemis:BAABLAAECoEZAAMEAAgIowqVMABuAQAEAAgILgqVMABuAQAFAAMIWAVnhQBmAAAAAA==.Aryna:BAAALAADCgMIBAAAAA==.',As='Asmallpillow:BAAALAAECgEIAQAAAA==.Aspallsdaddy:BAAALAAECgYIDAAAAA==.',Az='Azareal:BAAALAADCggIFQAAAA==.Azula:BAAALAAECgIIAgAAAA==.',Ba='Backpass:BAAALAAECgcIEAAAAA==.Backtobasics:BAAALAAECgEIAQAAAA==.',Be='Beaver:BAAALAAECgQIBgAAAA==.',Bh='Bhilí:BAAALAAECgIIAwAAAA==.Bhíli:BAAALAADCggICAAAAA==.',Bl='Blaine:BAAALAAECgcIEwAAAA==.Blarneymoss:BAAALAADCgcIDgAAAA==.Blodreina:BAAALAAECgcIEQAAAA==.Blödaxe:BAAALAAECgYIDAABLAAECggIEAABAAAAAA==.',Bo='Bomboclat:BAAALAADCgcIBwAAAA==.',Br='Brankan:BAAALAADCggICAAAAA==.',Bu='Bubblepop:BAAALAADCgQIBAAAAA==.',Ca='Cahalith:BAABLAAECoEYAAIGAAgIfxWCHgDhAQAGAAgIfxWCHgDhAQAAAA==.Calandrinon:BAAALAAECgMIAwAAAA==.Capella:BAAALAAECggIEQAAAA==.Casan:BAAALAAECgUICwAAAA==.',Ce='Celticmight:BAABLAAECoEdAAIHAAgIYRd8JgBCAgAHAAgIYRd8JgBCAgAAAA==.',Ch='Chedders:BAAALAADCggIDwAAAA==.Chewie:BAAALAAECgMIAwABLAAFFAMICAADAAAIAA==.Chillskill:BAAALAADCgQIBAAAAA==.Chronalys:BAAALAADCgYIBgAAAA==.Chéf:BAAALAAECgYIBwAAAA==.',Co='Cocoloco:BAAALAADCgQIBAABLAAECgcIDQABAAAAAA==.',Cr='Crimsön:BAAALAADCgMIAwAAAA==.',['Cá']='Cáp:BAAALAADCggIEAAAAA==.',['Có']='Cóffèè:BAAALAAECgUIBQAAAA==.Cóffèé:BAAALAADCgQIBAAAAA==.',Da='Daffie:BAAALAAECgUICgAAAA==.Dalkini:BAAALAAECgYIDwAAAA==.Dandadan:BAAALAAECgIIAgAAAA==.Dannic:BAABLAAECoEWAAIIAAcIORAJCgC2AQAIAAcIORAJCgC2AQAAAA==.Danyel:BAAALAADCggIDQAAAA==.Darkfayth:BAAALAAECgcIEwAAAA==.Darklorn:BAABLAAECoEVAAIJAAcIqA/XVACPAQAJAAcIqA/XVACPAQAAAA==.Darktouch:BAAALAADCggIDwAAAA==.Darrior:BAAALAAECgYIDwAAAA==.',Db='Dbacic:BAABLAAECoEZAAIJAAgIohYpJQBOAgAJAAgIohYpJQBOAgAAAA==.',De='Deathchamp:BAAALAAECgMIBQAAAA==.Delbar:BAAALAAECgYICAAAAA==.Demís:BAAALAADCggICAAAAA==.Derzix:BAAALAAECggICwAAAA==.Devilpala:BAAALAAECgUIBQAAAA==.',Dh='Dhunthor:BAAALAAECgEIAQAAAA==.',Di='Diamondrowe:BAABLAAECoEUAAMKAAcIXhIyGADUAQAKAAcIXhIyGADUAQALAAYIdwLXegCxAAABLAAECgcIDQABAAAAAA==.Discomania:BAAALAAECgUICQAAAA==.',Do='Donock:BAABLAAECoEUAAIMAAcIrgh8IACXAQAMAAcIrgh8IACXAQAAAA==.Dookookoodoo:BAAALAAECgYIEAAAAA==.',Dr='Dragonix:BAAALAADCgcIBwABLAAECggIBAABAAAAAA==.Dragonjam:BAAALAADCgcIBwAAAA==.Draktand:BAAALAAECggIAgAAAA==.Dramallama:BAAALAAECgUIBgAAAA==.Dreambot:BAAALAAECgYIEwAAAA==.Dreamspeaker:BAAALAADCgcICAAAAA==.Droganian:BAAALAAECgUIDAAAAA==.Droog:BAAALAADCggIFAAAAA==.',Du='Dubfury:BAAALAAECgUIBQAAAA==.Dudleydragon:BAAALAAECgUICgAAAA==.Dumpling:BAAALAADCgYICAABLAAFFAMICAADAAAIAA==.Duurek:BAABLAAECoEdAAINAAgI+xvcDQCOAgANAAgI+xvcDQCOAgABLAAFFAIIAgABAAAAAA==.',Ec='Eclesiarch:BAAALAAECggIEAAAAA==.',El='Elayue:BAAALAAECgUICgAAAA==.Elcamino:BAAALAADCggIDwAAAA==.Elenä:BAAALAAECgYIAgAAAA==.Elfiain:BAAALAAECgEIAQAAAA==.Elfury:BAAALAADCgMIAwAAAA==.Elileath:BAAALAAECggIEwAAAA==.Eloey:BAAALAADCggICAAAAA==.Elvari:BAABLAAECoEVAAIOAAcIKx5pEAB0AgAOAAcIKx5pEAB0AgAAAA==.Elydryn:BAABLAAECoEZAAMFAAgIkBy1FQB+AgAFAAgIShy1FQB+AgAPAAcIthz2AgBkAgAAAA==.Elymas:BAAALAADCgMIAwAAAA==.Elèssar:BAAALAAECgEIAQAAAA==.',Em='Emrysia:BAAALAADCgUIBQAAAA==.',En='Enneala:BAAALAADCgcIBwAAAA==.',Ep='Epok:BAAALAAECgEIAwAAAA==.',Er='Erannard:BAAALAAECgYIEQAAAA==.Erichspi:BAAALAAECgYICgAAAA==.Eriela:BAAALAAECgIIAgAAAA==.Eritreith:BAAALAAECgQIBAAAAA==.',Es='Estheria:BAAALAADCgcIDgAAAA==.',Ev='Evonblade:BAAALAAECgQIBwAAAA==.',Fa='Fairfield:BAAALAAECggIAgABLAAECggIBAABAAAAAA==.Faithfil:BAAALAAECgcIEAAAAA==.Fame:BAABLAAECoEUAAIHAAgIyxSFMwAEAgAHAAgIyxSFMwAEAgAAAA==.Famy:BAAALAAECgYIBgAAAA==.Fangrage:BAAALAAECgEIAQAAAA==.Farcia:BAABLAAECoEXAAIKAAgIURT2DwAsAgAKAAgIURT2DwAsAgAAAA==.',Fi='Fippi:BAABLAAECoEVAAMNAAgIahL8KgDYAQANAAgIahL8KgDYAQAQAAIIwQTDagBLAAAAAA==.',Fl='Flaskhals:BAABLAAECoEUAAMRAAcIjx2TIQAiAgARAAcISxuTIQAiAgAMAAMIYxq1PAD1AAAAAA==.',Fr='Frigidbardot:BAAALAAECgUIBQAAAA==.',Ga='Galnajävul:BAAALAADCgEIAQAAAA==.',Ge='Gelpa:BAABLAAECoEYAAIQAAgI2hZAGQBJAgAQAAgI2hZAGQBJAgAAAA==.',Go='Gondola:BAAALAADCggIDgAAAA==.Goonerboy:BAAALAADCggICAAAAA==.',Gr='Graffyre:BAAALAAECggIDwAAAA==.Granith:BAAALAAECgcIDgAAAA==.Grappriest:BAAALAAFFAMIAwAAAA==.Gratgreas:BAAALAAECgYIBwAAAA==.Greatbuddha:BAAALAAECgEIAQAAAA==.Grey:BAAALAAECgIIAgAAAA==.Grimholt:BAABLAAECoEbAAMSAAgIUx9EDgB3AgASAAcIxB9EDgB3AgATAAYIVBoKDAC/AQAAAA==.Grimn:BAAALAADCgEIAQABLAAECggIEAABAAAAAA==.',Gu='Guildofgold:BAAALAADCgYIBgAAAA==.Gullinfotm:BAAALAAECgYIDAAAAA==.Gullinkeg:BAAALAAECgIIAgAAAA==.Gullinshout:BAABLAAECoEWAAIUAAgIAR6qCACUAgAUAAgIAR6qCACUAgAAAA==.',Gy='Gyokuro:BAAALAAECgEIAQABLAAECggIFwAKAFEUAA==.',Ha='Halahar:BAAALAAECgUICgAAAA==.Halestorm:BAAALAAECgIIAgAAAA==.Hartley:BAAALAADCgcIBwABLAAECgYIDgABAAAAAA==.Harveyke:BAAALAADCggICQAAAA==.Hasse:BAAALAAFFAIIAgAAAA==.Hatefree:BAAALAAECgUICAAAAA==.',Hb='Hbshaman:BAAALAADCggIDgAAAA==.',He='Heli:BAAALAAECgYIBgAAAA==.Hernfjord:BAAALAADCggICAAAAA==.',Hi='Hidell:BAAALAADCggICAAAAA==.',Ho='Hoit:BAAALAADCggICAAAAA==.Holyflame:BAAALAAECgcIEAAAAA==.Holyphallus:BAAALAAECgEIAQABLAAECgUICwABAAAAAA==.Holypix:BAABLAAECoEZAAIVAAgI2Ry5DACnAgAVAAgI2Ry5DACnAgAAAA==.Holyprof:BAABLAAECoEWAAIWAAcIOhZmFADjAQAWAAcIOhZmFADjAQAAAA==.Holyrage:BAAALAAECgEIAQAAAA==.Holyspons:BAAALAAECgMIBAAAAA==.',Hr='Hrafn:BAAALAAECgcIEQAAAA==.',Hu='Hugekokowner:BAAALAADCggICAAAAA==.Huh:BAAALAADCgcIBgAAAA==.Hunterdrizzt:BAAALAAECggIGAAAAQ==.Hustemun:BAAALAAECgQIBAAAAA==.',Ic='Icecube:BAAALAADCggICAAAAA==.',Id='Idariel:BAAALAAECgYIEgAAAA==.',Ii='Iippi:BAAALAADCgYICgAAAA==.',Il='Illidev:BAAALAADCgQIBAAAAA==.',In='Indicud:BAAALAAECgYIDgAAAA==.Infuse:BAAALAAECgYIBgAAAA==.Innocent:BAAALAAECgYIBgAAAA==.',Is='Ishri:BAAALAAECgMICAAAAA==.',Iz='Izink:BAAALAAECggIAwAAAA==.',Ja='Jabberwocky:BAAALAADCggICAAAAA==.Jaroftears:BAAALAADCgcIBwAAAA==.Jazzor:BAAALAADCgcIDQAAAA==.',Je='Jezemalu:BAAALAAECgcIEwABLAAECggIDgABAAAAAA==.',Jh='Jhen:BAABLAAFFIEFAAMXAAMINxYCAQCtAAARAAII1RYiDwCvAAAXAAII0xUCAQCtAAAAAA==.',Ji='Jippe:BAABLAAECoEYAAIYAAgIqhyDBwB7AgAYAAgIqhyDBwB7AgAAAA==.Jippi:BAABLAAECoEUAAQZAAcI9Bu8CQA1AgAZAAcI9Bu8CQA1AgAaAAYIXhTJFgB0AQAbAAQI7wumKwDRAAAAAA==.',Ju='Justshockit:BAAALAAECgMIAwAAAA==.',['Jß']='Jß:BAAALAAECgMIBgAAAA==.',Ka='Kablamo:BAAALAADCgQIBAABLAAECgcIGQAcAIEfAA==.Kalimon:BAAALAAECgcIEQAAAA==.Kalonriel:BAAALAAECgYIDAAAAA==.Kalrissa:BAAALAADCggIFgAAAA==.Karmao:BAAALAAECgYIBwAAAA==.Karosh:BAAALAADCgYIBgAAAA==.Kassiel:BAAALAADCggICAAAAA==.',Ke='Kekkuli:BAAALAAECgcIEAAAAA==.Kevi:BAAALAADCggIHAAAAA==.',Ki='Kidagakash:BAAALAADCgcIBwABLAAECgYIEgABAAAAAA==.',Kl='Kliff:BAAALAAECgcIDQAAAA==.',Kr='Krazykilla:BAAALAADCgQIBAAAAA==.Krocken:BAAALAADCgcIFgAAAA==.Krugerr:BAAALAADCgMIAwAAAA==.',Ku='Kujatus:BAAALAADCggICgAAAA==.',La='Laina:BAAALAADCgEIAQAAAA==.Larilla:BAAALAAECgYIDgAAAA==.Laymore:BAAALAAECgUICgAAAA==.Lazycodinq:BAAALAADCgYIBgAAAA==.',Le='Leiyung:BAAALAAECgYIDAAAAA==.',Li='Lichlordess:BAAALAADCgQIBAAAAA==.Liekki:BAAALAAECgUICgAAAA==.Lillevän:BAAALAAECgQIBwAAAA==.Limoondk:BAAALAAECgMIAwAAAA==.Limtak:BAAALAADCggIFQAAAA==.',Lm='Lmnt:BAAALAAECgcIEAAAAA==.',Lo='Logobeam:BAAALAADCggICAABLAAECggIFgAdAJEcAA==.Logodk:BAABLAAECoEWAAMdAAgIkRx9DgAFAgAdAAYItRx9DgAFAgAJAAYIFRntRwC6AQAAAA==.Logolock:BAAALAAECgcICQABLAAECggIFgAdAJEcAA==.Logomidian:BAAALAAECgYIBgABLAAECggIFgAdAJEcAA==.Lolfunny:BAAALAADCgcIBwABLAAECgYIEwABAAAAAA==.Lorretchea:BAAALAADCggICwAAAA==.Loube:BAAALAAECgcIEQABLAAECgcIGQAcAIEfAA==.',Lu='Lucebree:BAAALAAFFAIIAgAAAA==.',['Lá']='Lárà:BAABLAAECoEUAAIHAAcI5yJJFwCoAgAHAAcI5yJJFwCoAgAAAA==.',Ma='Macx:BAAALAAECgYIEAAAAA==.Madista:BAAALAAECgUIBwAAAA==.Magentta:BAAALAADCggICgAAAA==.Mahaisen:BAABLAAECoEYAAIbAAgIzBX6DQAzAgAbAAgIzBX6DQAzAgAAAA==.Manifest:BAAALAAFFAEIAQAAAA==.Mannen:BAAALAAECgcICgAAAA==.Maousi:BAAALAADCgYIBgAAAA==.Marshmallows:BAAALAADCgcIBwAAAA==.',Mc='Mcchicken:BAACLAAFFIEIAAIDAAMIAAh9AQDmAAADAAMIAAh9AQDmAAAsAAQKgR0AAwMACAisGdYEAHcCAAMACAisGdYEAHcCABAABQi8EBREAEUBAAAA.Mcflurry:BAAALAADCgcIBwABLAAFFAMICAADAAAIAA==.Mcfudge:BAAALAADCgEIAQAAAA==.',Me='Mehira:BAAALAAECggIEAAAAA==.Meregob:BAAALAAECggICAABLAAECggIDwABAAAAAA==.',Mi='Mikako:BAAALAADCggIFgABLAAECgYIEgABAAAAAA==.Mileycryus:BAAALAAECgIIAgAAAA==.Milsandrea:BAAALAADCgYIBgAAAA==.Minnji:BAABLAAECoEZAAMcAAcIgR+hBwA7AQALAAcIoR6oPADMAQAcAAQIlR2hBwA7AQAAAA==.Mira:BAABLAAECoEVAAIZAAYIQCLVCABOAgAZAAYIQCLVCABOAgAAAA==.',Mo='Monkman:BAAALAADCggIBwAAAA==.Monosham:BAAALAAECggIDwAAAA==.Montide:BAAALAAECgYIDAAAAA==.Morkimus:BAAALAAECgMIAwAAAA==.',Mu='Munchkinrex:BAAALAADCgcIBwAAAA==.',My='Mydadisbald:BAAALAAECgcIEgAAAA==.',Na='Narchi:BAAALAAECgEIAgAAAA==.Natycakes:BAAALAAECgcIEgAAAA==.',Ne='Neirr:BAAALAAECgYIAgAAAA==.Nemmar:BAAALAAECgYIAgAAAA==.Nesquick:BAAALAADCgUIBQAAAA==.Ness:BAAALAADCggICAAAAA==.Nessy:BAAALAAECgYIEAAAAA==.',Ni='Nialin:BAAALAAECgYIDAAAAA==.Nitherium:BAAALAADCggICAAAAA==.',No='Nouichido:BAAALAAECgcIEQAAAA==.Novadin:BAABLAAECoEVAAIWAAgIChYCEQAIAgAWAAgIChYCEQAIAgAAAA==.Novedaddy:BAAALAAECgQIBAABLAAECggIFQAWAAoWAA==.Novedrake:BAAALAADCggICAABLAAECggIFQAWAAoWAA==.',Nq='Nquiera:BAAALAADCggIEgAAAA==.',Ny='Nyanko:BAAALAADCgYIBgABLAAECgEIAgABAAAAAA==.Nylaathria:BAAALAAECggIDgAAAA==.',Or='Orliad:BAAALAAECggICAAAAA==.',Os='Ossa:BAAALAAECgQIEAAAAA==.Oswald:BAAALAAECggICwAAAA==.',Pa='Paagrio:BAAALAAECgcICgAAAA==.',Pe='Peotrala:BAAALAADCggICAAAAA==.Pezadora:BAAALAAECgcIEgAAAA==.',Pi='Pingping:BAAALAADCggICAAAAA==.Pixiepopp:BAAALAADCgEIAQAAAA==.',Po='Poxycatdk:BAAALAADCgcIBwAAAA==.',Pr='Priestjammy:BAAALAAECgEIAQAAAA==.Priestmaster:BAAALAAECgEIAQAAAA==.',Pu='Puddleofmudd:BAAALAAECgEIAQABLAAECgYIEwABAAAAAA==.Punchyellf:BAAALAAECggIDAAAAA==.',Py='Pyrrah:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.',Ra='Raenys:BAAALAADCggICAAAAA==.Raiju:BAAALAADCgMIBAAAAA==.',Re='Rebørn:BAAALAAECgUIBgAAAA==.Redgold:BAABLAAECoEYAAMFAAgIiQn/NgCwAQAFAAgIiQn/NgCwAQAEAAYIRAR1TwDDAAAAAA==.Remorse:BAAALAAECggIAQAAAA==.',Rh='Rhaelor:BAAALAADCggICAAAAA==.Rhoadryn:BAAALAADCggICAAAAA==.Rhodryyn:BAAALAAECgYIDAAAAA==.',Ri='Ribbuli:BAAALAADCggIDAAAAA==.Rippi:BAAALAADCggICAAAAA==.',Ro='Robertha:BAAALAADCgEIAQAAAA==.Roccalex:BAABLAAECoEVAAIHAAYIXxqNRQDDAQAHAAYIXxqNRQDDAQAAAA==.Roseblue:BAAALAADCggIEAAAAA==.Rotation:BAAALAADCgMIAwAAAA==.',Rp='Rpc:BAAALAAECgYIEwAAAA==.',Ry='Rydermedusa:BAAALAADCggIDwAAAA==.',Sa='Samuraibob:BAABLAAECoEWAAIEAAcIGR8uEgBpAgAEAAcIGR8uEgBpAgAAAA==.Sanoti:BAAALAADCggICgAAAA==.Santaluz:BAAALAAECgMIAwAAAA==.Satino:BAACLAAFFIEGAAMTAAMIVhnXAQAJAQATAAMIChnXAQAJAQAeAAIIvRpiAQC2AAAsAAQKgRgAAxMACAgoJbcBABoDAB4ACAiOI80AACoDABMACAj4ILcBABoDAAAA.',Sc='Scrollzdh:BAAALAAECgcIEwAAAA==.Scrollzi:BAAALAAECgIIAgAAAA==.',Sd='Sdragon:BAAALAAECgUICgAAAA==.',Se='Seluria:BAAALAAECgEIAQAAAA==.Seorin:BAAALAADCgMIAwAAAA==.Seraphine:BAAALAADCgcIBwAAAA==.Serenmity:BAAALAAECggICAAAAA==.Serrate:BAAALAAECgcIEAAAAA==.',Sh='Shamary:BAABLAAECoEWAAINAAgIFQwPTgBGAQANAAgIFQwPTgBGAQAAAA==.Shamay:BAAALAADCggICAAAAA==.Shawoman:BAAALAAECgMIAwABLAAECgYIEwABAAAAAA==.',Si='Sillý:BAAALAADCggIDwABLAAECgYIEwABAAAAAA==.Silvermage:BAAALAAECggICAABLAAECggIDwABAAAAAA==.',Sk='Skimouri:BAAALAAECgMIBAAAAA==.Skogsvro:BAAALAADCgUIBAAAAA==.Skàrma:BAAALAADCggICAAAAA==.Skîa:BAAALAAECggIDgAAAA==.',So='Sorrowpath:BAAALAAECggICAAAAA==.',Sp='Sparklebutt:BAAALAAFFAIIAwAAAA==.Spoelio:BAAALAAECgYIBgABLAAECggIFgAdAJEcAA==.Spongie:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Spongíe:BAAALAAECgEIAQAAAA==.Spongîe:BAAALAADCggIEgABLAAECgEIAQABAAAAAA==.',St='Stabbyace:BAAALAADCgUIBQABLAADCgYICQABAAAAAA==.Stepal:BAAALAAECgcIDgAAAA==.Stinkfist:BAABLAAECoEWAAIfAAgIHBz8EACqAgAfAAgIHBz8EACqAgAAAA==.Strahil:BAAALAAECggIEAAAAA==.Strongbiceps:BAAALAADCgIIAwAAAA==.',Su='Sugarplums:BAEALAAECgUIBgAAAA==.Suhri:BAAALAAECgEIAQAAAA==.Summonamon:BAAALAADCggIFgAAAA==.Superdude:BAAALAAECgUICAAAAA==.',Sw='Swahy:BAAALAAECgIIAgAAAA==.Sweetlizzy:BAAALAADCgYIBgAAAA==.Swiftmane:BAAALAAECgIIAgAAAA==.Swoleboi:BAAALAAECggICAAAAA==.',Sy='Sylthas:BAAALAAECgYIEQAAAA==.',['Sé']='Séphyx:BAAALAAECgYIDAAAAA==.',['Sê']='Sêphyx:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',['Sò']='Sòl:BAAALAAECgcICQABLAAECggIEAABAAAAAA==.',Ta='Tacobuddy:BAAALAAECgIIAgAAAA==.',Te='Tenc:BAAALAADCggICQAAAA==.Tequima:BAAALAADCggIDgAAAA==.Tetsaaja:BAAALAAECgMIAwAAAA==.Tezs:BAAALAAECgIICAAAAA==.',Th='Therenewer:BAAALAADCggIFwAAAA==.Thesauron:BAAALAAECgcIEwAAAA==.Thorck:BAAALAADCgMIAwAAAA==.Thunderfury:BAAALAAECgcIBwAAAA==.Thyroker:BAAALAAECgYIEQAAAA==.',Ti='Ticktock:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.Tigarah:BAAALAAECgUICgAAAA==.Tightpants:BAAALAADCgEIAQAAAA==.Tinkerbull:BAAALAAECgIIAgAAAA==.Tixxy:BAABLAAECoEXAAIRAAgIsgoGPgB+AQARAAgIsgoGPgB+AQAAAA==.',To='Tourettes:BAAALAAECgcIBwABLAAFFAIIAgABAAAAAA==.Tovera:BAAALAADCgcIBwAAAA==.',Tr='Trekuplan:BAEALAAECgYIBgAAAA==.Tribunalx:BAAALAAECggICAAAAA==.Trustace:BAAALAADCgYICQAAAA==.',Tu='Turbomini:BAABLAAECoEcAAMSAAgIqxvWCgCnAgASAAgIqxvWCgCnAgATAAIIqAnVJABYAAAAAA==.',Tw='Twixie:BAAALAADCggIDQAAAA==.',Tz='Tzarkan:BAAALAAECgIIAgABLAAECgcIFQAOACseAA==.',Va='Valoria:BAAALAAECgYIEAAAAA==.Vanga:BAAALAAECgcIDgAAAA==.',Ve='Verband:BAAALAAECgYIEAAAAA==.Veroz:BAAALAADCggICAAAAA==.',Wa='Warleader:BAAALAADCgcIDAAAAA==.',We='Wetlock:BAAALAAECggIBAAAAA==.',Wi='Wildie:BAAALAAECgEIAQAAAA==.Withavoker:BAAALAAECgIIAgAAAA==.',Wo='Womannen:BAAALAAFFAMIAwAAAA==.',Xi='Xidrase:BAAALAADCgcIBwAAAA==.',Xu='Xulu:BAABLAAECoEYAAIVAAgIYSDzBwDlAgAVAAgIYSDzBwDlAgAAAA==.',Xy='Xynestra:BAAALAADCgcICAAAAA==.Xytanius:BAABLAAECoEYAAQRAAgIexrOFgB6AgARAAgI6RjOFgB6AgAMAAUIsBRhLQBOAQAXAAEI6AtrLgBIAAAAAA==.',Ya='Yagami:BAAALAAECgYICgAAAA==.Yasdnil:BAAALAADCggICAAAAA==.',Ye='Yean:BAAALAAECgYIEgAAAA==.',Yn='Ynnead:BAAALAADCgcICAAAAA==.',Za='Zamper:BAAALAADCgcICgAAAA==.Zantick:BAAALAADCgEIAQAAAA==.Zarguth:BAAALAAECgMIBQAAAA==.',Zi='Ziki:BAAALAAECgMIBAAAAA==.Zinobia:BAAALAAECgUICgAAAA==.',Zu='Zuki:BAAALAAECgYIEgAAAA==.Zuli:BAABLAAECoEWAAIYAAcIPSCcBwB4AgAYAAcIPSCcBwB4AgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end