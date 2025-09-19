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
 local lookup = {'Unknown-Unknown','DeathKnight-Blood','Druid-Balance','Warrior-Fury','Mage-Frost','Evoker-Devastation','Evoker-Preservation','Druid-Feral','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Mage-Arcane','Hunter-Survival','Hunter-BeastMastery','Warrior-Protection','Monk-Brewmaster','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','DemonHunter-Vengeance','Warlock-Destruction','Warlock-Affliction','Paladin-Retribution','Shaman-Enhancement','Druid-Guardian','Hunter-Marksmanship','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Shaman-Restoration','Priest-Holy','Warlock-Demonology','Paladin-Protection',}; local provider = {region='EU',realm='Dragonblight',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abbysal:BAAALAAECgEIAQAAAA==.',Ac='Achilleus:BAAALAADCggICAAAAA==.',Ad='Adam:BAAALAADCggIEAAAAA==.Adil:BAAALAADCgUICAAAAA==.',Ae='Aelyra:BAAALAADCgcIBwAAAA==.Aeneus:BAAALAADCggICAAAAA==.Aeon:BAAALAADCggICwAAAA==.',Ag='Agadoo:BAAALAAECgYIDgAAAA==.',Ah='Ahreeuhtahn:BAAALAAECgMIAwAAAA==.',Ai='Aish:BAAALAAECgYICAAAAA==.',Al='Albedó:BAAALAADCgcIBwAAAA==.Albertio:BAAALAAECgYIEAAAAA==.Albihunta:BAAALAAECggIEgAAAA==.Alleryon:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.Alorioun:BAAALAAECgEIAQAAAA==.Aluthis:BAAALAADCgcIDgAAAA==.',Am='Amaturk:BAABLAAECoEfAAICAAgILQlTEgBlAQACAAgILQlTEgBlAQAAAA==.Amoonsine:BAABLAAECoEdAAIDAAgIBRZWFABEAgADAAgIBRZWFABEAgAAAA==.',An='Analogklokke:BAAALAADCgYIBQAAAA==.Anarian:BAAALAADCgYIBgAAAA==.Angvard:BAAALAADCgYIBgAAAA==.Antoridh:BAAALAADCggIHgAAAA==.',Ap='Apikus:BAABLAAECoEiAAIEAAgIYSRCCAAUAwAEAAgIYSRCCAAUAwAAAA==.Apéxes:BAABLAAECoEdAAIEAAgI/SIqDADkAgAEAAgI/SIqDADkAgAAAA==.',Aq='Aquillaa:BAAALAAECgYIBwAAAA==.',Ar='Aradonn:BAABLAAECoEXAAIFAAcIwxNFFwDeAQAFAAcIwxNFFwDeAQAAAA==.Arcanicus:BAAALAADCgYIAwAAAA==.Archiboy:BAABLAAECoEeAAMGAAgI4BkUDQCHAgAGAAgI4BkUDQCHAgAHAAEIawayIwA2AAAAAA==.Arelas:BAAALAAECgYIBgAAAA==.Aridira:BAABLAAECoEfAAIIAAgIVSYZAACVAwAIAAgIVSYZAACVAwAAAA==.Arjanna:BAAALAAECgMIAwAAAA==.Artemis:BAAALAAECgYICAAAAA==.Artmisia:BAAALAADCggICAAAAA==.',As='Ashmuncher:BAAALAADCgIIAgAAAA==.Asklepios:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.Asku:BAAALAADCggICAAAAA==.Askéw:BAABLAAECoEXAAIFAAcI4x0IDQBTAgAFAAcI4x0IDQBTAgAAAA==.',At='Athenaa:BAAALAADCggICAAAAA==.Athene:BAAALAAECgYIBgAAAA==.Atmasi:BAAALAADCgYIBgAAAA==.',Au='Autch:BAAALAAECgcIDQAAAA==.Aux:BAAALAADCggIDgAAAA==.',Av='Avatar:BAAALAAFFAIIAgAAAA==.Avicii:BAAALAAECgYICQAAAA==.Avicularia:BAAALAADCggIDwAAAA==.Avornadin:BAAALAAECgYIDQAAAA==.',Az='Azcartz:BAAALAADCgEIAQAAAA==.Azir:BAABLAAECoEbAAMJAAgImxqQJgBGAgAJAAgImxqQJgBGAgAKAAEIPxmHOgBUAAAAAA==.Azrial:BAAALAADCgMIAwAAAA==.Azuf:BAAALAADCggICAAAAA==.Azureanna:BAAALAAECggIEAAAAA==.',Ba='Bakasura:BAAALAADCggIGwAAAA==.Balbur:BAAALAADCgMIAwAAAA==.Ballou:BAAALAAECgYICAAAAA==.Bambì:BAAALAADCgcIBwABLAAECgYIFAALAFUZAA==.Battlebagel:BAAALAAECgYIEAAAAA==.Bawlz:BAAALAAECgUIBAAAAA==.',Be='Belulcinege:BAAALAAECgUIBQABLAAECgcICwABAAAAAA==.Bergs:BAABLAAECoEcAAMMAAgIcB3RFwCiAgAMAAgIcB3RFwCiAgAFAAIIjgfiTQBlAAAAAA==.',Bh='Bhuddah:BAAALAADCgIIAgAAAA==.',Bi='Bigbadbunny:BAAALAAECgYIDgAAAA==.Birchpls:BAAALAADCggIFwAAAA==.',Bj='Bjørnstjerne:BAAALAAECgYIBwAAAA==.',Bl='Blackpepper:BAAALAAECgIIAgABLAAECggIGwAJAPkjAA==.Bladedancer:BAAALAADCgUIBQAAAA==.Blanzor:BAAALAAECgIIAgAAAA==.Blâde:BAAALAADCggICAAAAA==.Blåtrold:BAAALAAECgYIDAAAAA==.',Bo='Bobpaladin:BAAALAADCggICAAAAA==.Bono:BAAALAADCggIDQAAAA==.Bonz:BAAALAAECgYICQAAAA==.Bossieke:BAAALAADCgcIDgAAAA==.',Br='Bradslock:BAAALAAECgQIBAAAAA==.Bradzmage:BAAALAADCgQIBAAAAA==.Brevhymn:BAAALAADCgMIAwAAAA==.Brevidan:BAAALAADCgcIBwAAAA==.Brielle:BAAALAAECgYIBgAAAA==.Brockie:BAAALAAECgYIDgAAAA==.Bronnjard:BAAALAAECgUIBQAAAA==.',Bu='Buggsbunny:BAAALAAECgUICgAAAA==.Bursting:BAAALAADCgUIBQAAAA==.',['Bü']='Bülly:BAAALAADCggICAAAAA==.',Ca='Cadee:BAAALAAECgYIDgAAAA==.Callelujah:BAAALAAECgcIEAAAAA==.Casket:BAAALAAECgYICAAAAA==.',Ce='Centhanos:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Ch='Charlene:BAAALAAECgMIAwABLAAECgYIFAALAFUZAA==.Chateaux:BAAALAAECgcIEAAAAA==.Chiki:BAAALAAECgMIBAAAAA==.Chimairax:BAAALAAECggIEwAAAA==.Chokee:BAAALAAECgEIAQAAAA==.Chubbydizz:BAAALAAECgcIDQAAAA==.',Cl='Claymation:BAAALAAECgMIAwAAAA==.Cleanbread:BAABLAAECoEVAAINAAgINyR6AABWAwANAAgINyR6AABWAwAAAA==.Cleanmonk:BAAALAADCggICAAAAA==.',Co='Colarius:BAAALAADCgcIBwAAAA==.',Cr='Cristyanu:BAAALAAECgIIAgAAAA==.Crocky:BAAALAADCggICAAAAA==.',Cu='Cursed:BAAALAADCgcIBwAAAA==.Cutex:BAAALAAFFAIIBAAAAA==.Cutiehooves:BAAALAAECgEIAQAAAA==.',['Cü']='Cütx:BAAALAAFFAIIBAABLAAFFAIIBAABAAAAAA==.',Da='Daemonhero:BAAALAADCgYICAAAAA==.Daigoro:BAABLAAECoEUAAIOAAgI1RXCHQA8AgAOAAgI1RXCHQA8AgAAAA==.Daina:BAAALAAECgYICQAAAA==.Dakiola:BAAALAAECgUICgAAAA==.Darlisha:BAAALAAECgYIDgAAAA==.Datguy:BAAALAAECgUICAAAAA==.Davinki:BAAALAAECgYIDgAAAA==.',De='Deadjames:BAAALAAECggIDwAAAA==.Deadpikus:BAAALAADCgcICAABLAAECggIIgAEAGEkAA==.Deathbeno:BAAALAADCgcIBwABLAAECgUICgABAAAAAA==.Deathbri:BAAALAAECgMIBAAAAA==.Deathstrike:BAAALAADCggICAAAAA==.Deathzonè:BAABLAAFFIEFAAIPAAMI2xxcAgAWAQAPAAMI2xxcAgAWAQAAAA==.Demonhot:BAAALAAECgEIAQAAAA==.Demonseeker:BAAALAAECgYIBgAAAA==.Dethray:BAAALAAECgcIBwAAAA==.',Di='Diety:BAAALAAECgEIAQAAAA==.',Dj='Djoliver:BAAALAADCgcIBwAAAA==.',Dk='Dk:BAAALAAECggICAAAAA==.Dkbatsi:BAABLAAECoEbAAIJAAgIZCFpCQAYAwAJAAgIZCFpCQAYAwAAAA==.',Do='Dofian:BAAALAAECgYIDQAAAA==.Dolcegusto:BAAALAAECgMIBQAAAA==.Domidan:BAAALAAECgcIBwABLAAECggIGAAQAFgWAA==.Domisan:BAABLAAECoEYAAIQAAgIWBZWCgAnAgAQAAgIWBZWCgAnAgAAAA==.Dorana:BAAALAAECgUICgAAAA==.Dotsy:BAAALAAECgYICAAAAA==.',Dr='Draakje:BAAALAAECgYICwAAAA==.Dragotus:BAAALAAECggIEgAAAA==.Drigga:BAAALAAECgYICAABLAAECgcICwABAAAAAA==.Drol:BAAALAAECgYIDwAAAA==.Drucaruis:BAABLAAECoEWAAIRAAcIthS5OwDVAQARAAcIthS5OwDVAQAAAA==.Druelle:BAAALAAECgIIAgAAAA==.Drukhari:BAAALAAECgcIDwAAAA==.Dráke:BAAALAADCgUIBQABLAADCgcIDQABAAAAAA==.',Du='Duloc:BAAALAADCggICAAAAA==.Duran:BAAALAAECgIIAgAAAA==.',Ec='Ecclesia:BAAALAAECgYIDAAAAA==.Echodeath:BAAALAADCggICAAAAA==.',Ed='Edea:BAAALAADCgcIEQAAAA==.',Ee='Eesel:BAAALAAECgYIEwAAAA==.Eestlane:BAAALAAECgUICAAAAA==.',Ek='Ekron:BAAALAAECgIIAgAAAA==.',El='Eldaryon:BAAALAAECgEIAQAAAA==.Elementric:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Elethiomelle:BAAALAAECgUICwAAAA==.Ellaena:BAAALAADCgYIBgAAAA==.Elysama:BAABLAAECoEdAAMDAAgI9w/QKgCLAQADAAcIPA/QKgCLAQASAAgIUgunLgB4AQAAAA==.',Em='Emliyan:BAAALAADCggIFQAAAA==.',En='Enrage:BAAALAAECgEIAQAAAA==.Enwya:BAAALAADCggIEAAAAA==.',Er='Eradán:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Eryn:BAAALAADCgYIBgAAAA==.',Ev='Evilducky:BAAALAAECgYIDgAAAA==.Evilstriker:BAAALAAECgMIAwAAAA==.',Ex='Extramedium:BAAALAAECgMIBgABLAAECgYIDAABAAAAAA==.',Ez='Ezrël:BAABLAAECoEdAAIRAAgIzR2vFgCpAgARAAgIzR2vFgCpAgAAAA==.',Fa='Facepunch:BAAALAAECgYICQABLAAECgYIDAABAAAAAA==.Falsify:BAAALAADCggIGAAAAA==.Farming:BAABLAAECoEXAAITAAgIrxWBGgA+AgATAAgIrxWBGgA+AgAAAA==.Faylane:BAABLAAECoEfAAIEAAgISh2VDwC8AgAEAAgISh2VDwC8AgAAAA==.',Fe='Fejecskee:BAAALAADCgMIBgAAAA==.Felgaze:BAAALAADCgIIAgAAAA==.Felheld:BAAALAADCggIDgAAAA==.Felshiver:BAABLAAECoEdAAMUAAgIEiFqAwDnAgAUAAgIEiFqAwDnAgARAAUI5BsYUACKAQAAAA==.Felvard:BAAALAAECgYICQAAAA==.Fenhara:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.',Fi='Fig:BAAALAADCgcIBwAAAA==.Firephoenix:BAAALAAECgYIDgAAAA==.',Fl='Flappis:BAAALAAECgIIAgAAAA==.Flashrunner:BAAALAADCgcICwAAAA==.Florika:BAAALAAECgUICwAAAA==.Fluffles:BAAALAAECgIIAgAAAA==.Fluffyr:BAAALAAECggIBgAAAA==.Fly:BAAALAAECgcIBwAAAA==.Flyssa:BAAALAAECgUICgAAAA==.',Fr='François:BAAALAADCgMIAwAAAA==.',Fu='Fuzsmage:BAAALAADCggIFQAAAA==.',['Fá']='Fáust:BAAALAAECgYICAAAAA==.',['Fï']='Fïrefly:BAABLAAECoEfAAMVAAgIryFnCAAPAwAVAAgIUiFnCAAPAwAWAAgIjhewAwB4AgAAAA==.',Ga='Gagnand:BAAALAADCgcIBwAAAA==.Galdron:BAAALAAECgYIDgAAAA==.Gang:BAAALAADCggIDwAAAA==.',Ge='Gemmysaville:BAAALAAECgYIAwAAAA==.Genkipriest:BAAALAAECgUIBQAAAA==.Gerdhal:BAAALAAECgYIEgAAAA==.',Gh='Ghorin:BAAALAADCgcIBwAAAA==.',Go='Gorax:BAAALAADCgcICgAAAA==.Goshorty:BAAALAADCgMIAwAAAA==.Gothmogs:BAAALAADCgcIEQAAAA==.Gotrek:BAAALAADCggICAAAAA==.',Gr='Grayfoot:BAAALAAECgEIAQAAAA==.Graysun:BAAALAADCggIGAABLAAECggIGwAJAJsaAA==.Gregorbrew:BAAALAADCggICAABLAAECggIEwABAAAAAA==.Gregornök:BAAALAAECggIEwAAAA==.Grenadine:BAAALAAECgIIAgAAAA==.Grimras:BAAALAADCggIDgAAAA==.Gritzei:BAAALAADCgcIBwABLAADCggIDQABAAAAAA==.Gritzii:BAAALAADCggIDQAAAA==.Grobbthyr:BAAALAAECgMIBAAAAA==.Grumhilde:BAAALAADCggIGAAAAA==.Grumpus:BAAALAAECgYIBgAAAA==.Gríndelwald:BAAALAAECgEIAQAAAA==.Grítzie:BAAALAADCgUIBAABLAADCggIDQABAAAAAA==.',Gu='Gucs:BAAALAADCggICAAAAA==.',Gy='Gyula:BAAALAAECgcICwAAAA==.',Ha='Haggard:BAAALAADCgEIAQAAAA==.Haitene:BAABLAAECoEZAAISAAgIYRw5EABXAgASAAgIYRw5EABXAgAAAA==.',He='Helpoo:BAAALAAECgYICAAAAA==.Hempodius:BAABLAAECoEdAAIXAAgIgyR0BQBPAwAXAAgIgyR0BQBPAwAAAA==.Henuttawy:BAAALAADCggIDwAAAA==.Herilane:BAAALAAECgYIEQAAAA==.Hexon:BAAALAADCgcIEgAAAA==.',Hi='Hilda:BAAALAADCggICAAAAA==.',Ho='Holia:BAAALAAECggIAQAAAA==.Holyaddvlad:BAAALAADCgcICgAAAA==.Hondo:BAAALAADCgEIAQAAAA==.Honeybunny:BAAALAAECgEIAQAAAA==.',Hu='Huggelugge:BAAALAADCgMIAwAAAA==.Huntron:BAAALAAECgEIAQAAAA==.',Hy='Hypovolemia:BAABLAAECoEdAAIIAAgIyiYMAACeAwAIAAgIyiYMAACeAwAAAA==.',Ig='Igdurmm:BAABLAAECoEcAAIYAAgI5h9FAgDvAgAYAAgI5h9FAgDvAgAAAA==.',Il='Iliadiana:BAACLAAFFIEGAAIRAAMI9AyACQDaAAARAAMI9AyACQDaAAAsAAQKgR4AAhEACAgYImoNAPsCABEACAgYImoNAPsCAAAA.Illiidan:BAAALAADCgUIBQAAAA==.Illishari:BAAALAAECgcIDwABLAAECggICAABAAAAAA==.',Im='Imphetuz:BAAALAAECgcIEQAAAA==.Impátient:BAAALAADCgQIBAAAAA==.Imzy:BAAALAAECgUICgAAAA==.',In='Inmhotep:BAAALAAECgEIAQAAAA==.Inze:BAABLAAECoEUAAIZAAYIyR12BQD/AQAZAAYIyR12BQD/AQAAAA==.',Ip='Iprenmannen:BAAALAADCgEIAQAAAA==.',It='Ithiriell:BAAALAAECgEIAgAAAA==.Itto:BAABLAAECoEfAAIOAAgIQR/TDADXAgAOAAgIQR/TDADXAgAAAA==.',Ja='Jadepaws:BAAALAADCggIDwAAAA==.Jadow:BAAALAAECgYIDgAAAA==.Janjarn:BAAALAAECgYIBgAAAA==.Jargahl:BAAALAAECgYIEAAAAA==.Jayandknight:BAAALAAECgYIDgAAAA==.Jayxd:BAAALAAECgUICQAAAA==.',Je='Jeangenie:BAAALAAECgYICwAAAA==.Jeanpierre:BAAALAAFFAEIAQAAAA==.Jessié:BAAALAAECgIIAwAAAA==.',Ji='Jimalexander:BAAALAADCggICAAAAA==.Jimjam:BAAALAAECgQICAAAAA==.',Jo='Jointdragon:BAAALAAECgEIAQAAAA==.Jointdruid:BAAALAADCgEIAQAAAA==.Jointpriesty:BAAALAADCgQIBAAAAA==.',Ju='Jubjub:BAAALAAECgYIDgAAAA==.Juicytaco:BAAALAADCggIEAAAAA==.Jun:BAAALAADCgUIBQAAAA==.Justadragon:BAAALAAECgUIBwAAAA==.',Jy='Jymy:BAAALAAECgcIBwAAAA==.',['Jë']='Jëel:BAABLAAECoEcAAICAAgIOSGeBADEAgACAAgIOSGeBADEAgAAAA==.',Ka='Kaelith:BAAALAADCgMIAwAAAA==.Kaion:BAAALAAECgEIAgAAAA==.Kajmi:BAAALAAECgEIAQAAAA==.Kalerya:BAABLAAECoEUAAMOAAYIdSHzGwBKAgAOAAYIdSHzGwBKAgAaAAIInQt+ZwBTAAABLAABCgUIBQABAAAAAA==.Kalygos:BAAALAAECgcIBwABLAAECgcIEAABAAAAAA==.Kantaras:BAAALAADCgcIDgAAAA==.Kawknala:BAAALAADCggIGQAAAA==.Kaykraz:BAAALAADCggIDwAAAA==.Kayliegh:BAAALAADCggIGwAAAA==.Kaytee:BAAALAAECgYICAAAAA==.',Kb='Kbotdh:BAABLAAECoEXAAIRAAcIfQZOZABIAQARAAcIfQZOZABIAQAAAA==.',Ke='Keyolumin:BAAALAADCggICAAAAA==.',Ki='Kiirii:BAAALAADCgIIAgAAAA==.Kikelet:BAAALAAECgEIAQAAAA==.Kilkra:BAAALAADCgcIBwABLAAECggIGQASAGEcAA==.Kisi:BAAALAADCgcIDAAAAA==.Kissii:BAAALAAECgEIAQAAAA==.Kitter:BAAALAAECgYIDgAAAA==.Kitzura:BAAALAAECgYICAABLAAECggIGQAUAMYjAA==.',Kl='Kleef:BAAALAAECgEIAQAAAA==.',Kn='Knite:BAAALAAECgEIAQAAAA==.',Ko='Kocurkowa:BAAALAAECgYICAAAAA==.Kolfinna:BAAALAAECgYIBwAAAA==.Korbá:BAAALAAECgYIDwAAAA==.Kormath:BAABLAAECoEXAAIYAAgInCO/AABIAwAYAAgInCO/AABIAwAAAA==.Kowetas:BAAALAAECgMIAwAAAA==.',Ku='Kurgon:BAAALAAECgMIBAAAAA==.Kutz:BAABLAAECoEXAAIOAAgIxBp+FQCAAgAOAAgIxBp+FQCAAgAAAA==.',La='Lafuuch:BAAALAADCggIEAABLAAFFAMIBQAbAOYbAA==.Lagswell:BAAALAAECgYIDgAAAA==.Lasarus:BAAALAADCggIHAAAAA==.Lashhunt:BAABLAAECoEcAAMNAAgI9yO7AAA0AwANAAgInCK7AAA0AwAOAAcIrSBEGgBXAgAAAA==.Lauree:BAAALAADCgcIBwAAAA==.Laurelinde:BAAALAAECgMIAwAAAA==.Laurenzium:BAAALAAECgEIAQAAAA==.Lazulia:BAAALAAECgYIEAAAAA==.Lazÿ:BAAALAAECgcIDgAAAA==.',Le='Legatrix:BAAALAAECgQIBgAAAA==.',Li='Libe:BAAALAAECgYIDQAAAA==.Lightblood:BAAALAAECgIIAgAAAA==.Lightsworn:BAABLAAECoEXAAIXAAgIoiHKCwAOAwAXAAgIoiHKCwAOAwAAAA==.Lionaa:BAABLAAECoEaAAIDAAgIsxjAEQBiAgADAAgIsxjAEQBiAgAAAA==.Lissmonk:BAAALAAECgIIAgAAAA==.',Ll='Lluucciiffer:BAAALAADCgcIBwAAAA==.',Lo='Lomiodien:BAAALAAECgYICQAAAA==.Loonyshaman:BAAALAAECgUICwAAAA==.Lorewalkerem:BAAALAAECgUICgAAAA==.Lorsal:BAAALAADCggIBAABLAAECggIHQADAAUWAA==.',Lu='Ludia:BAAALAADCggICAAAAA==.Lumememm:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Lumene:BAAALAAECgYIDAAAAA==.Lunarwalker:BAAALAAECgcIEAAAAA==.Lunia:BAAALAAECgYICwAAAA==.',Ly='Lyarii:BAAALAADCgYIBgAAAA==.',['Lâ']='Lâzîe:BAAALAAECgYIBgAAAA==.',Ma='Machiaveli:BAAALAAECgQIBwAAAA==.Machiavelii:BAAALAAECgYICAAAAA==.Macmiller:BAAALAAECggICQAAAA==.Madheal:BAAALAADCgMIAwABLAADCgcIDQABAAAAAA==.Madmagetee:BAAALAADCgYIBwAAAA==.Maedruhm:BAAALAAECgMIBAABLAAECgUIBQABAAAAAA==.Majamusen:BAAALAAECgcIDAAAAA==.Markofshadow:BAAALAADCgcICAAAAA==.Martinet:BAAALAAECgYIBgAAAA==.Mathiasrex:BAAALAADCgMIAwAAAA==.Mazrigos:BAAALAAECgcICQAAAA==.',Me='Merlìn:BAAALAADCggIFwAAAA==.Meteorrush:BAAALAAECgMIAwAAAA==.Metsavend:BAAALAAECgYIEQAAAA==.Metshaldjas:BAAALAAECgQIBAAAAA==.',Mi='Michaél:BAAALAADCgUIBQAAAA==.Michele:BAAALAADCgcIDQAAAA==.Midekai:BAAALAAECgMIBAAAAA==.Midnightvoid:BAAALAADCggIDwAAAA==.Migrin:BAAALAADCgQIBAAAAA==.Miisu:BAABLAAECoEUAAIIAAYIBCRvBwBtAgAIAAYIBCRvBwBtAgABLAABCgUIBQABAAAAAA==.Mikedr:BAAALAADCgUIBQAAAA==.Mimibun:BAAALAAECgYIBwAAAA==.Minidréas:BAABLAAECoEfAAIOAAgIcRg2FwBxAgAOAAgIcRg2FwBxAgAAAA==.Mirkoo:BAAALAAECgYIDQAAAA==.Mistyweaver:BAACLAAFFIEFAAIbAAMI5htmAgAeAQAbAAMI5htmAgAeAQAsAAQKgRcAAhsACAgVJAcCACQDABsACAgVJAcCACQDAAAA.',Mo='Modignok:BAAALAADCggICAAAAA==.Moelgardo:BAAALAAECgEIAQAAAA==.Molpadia:BAAALAAECgYIEAAAAA==.Mongin:BAAALAAECggICAAAAA==.Monshiro:BAAALAAFFAIIBAAAAA==.Monstret:BAAALAADCggIDgAAAA==.Monstretsh:BAAALAADCgcIBwAAAA==.Mordecái:BAAALAADCgMIAgAAAA==.Morguna:BAAALAADCgcIBwAAAA==.Moxxare:BAAALAAECgIIAwAAAA==.',Mu='Mungamunand:BAAALAAECggIAgAAAA==.Must:BAAALAAECgUIBwABLAAECgYIEQABAAAAAA==.',My='Mygnome:BAAALAAECgcIDwAAAA==.Myka:BAAALAAECgYIDwAAAA==.',Na='Nalla:BAAALAADCgEIAQAAAA==.Nallidi:BAAALAADCgcICgAAAA==.Narlaine:BAAALAAECgYIEQAAAA==.Nassame:BAAALAAECgYICAAAAA==.Naughtyvixen:BAAALAAECgYICgAAAA==.Nausicaä:BAAALAADCgUIBQAAAA==.',Ne='Needmoredots:BAAALAAECgYIDwAAAA==.Nelsar:BAAALAADCggIFwAAAA==.Nephatus:BAAALAADCggIEAAAAA==.Neverend:BAAALAADCgMIAgAAAA==.',Ni='Nickiminaj:BAAALAADCgMIAwAAAA==.Niharwynn:BAAALAADCgQIBAAAAA==.Nihverdis:BAABLAAECoEXAAMcAAgIUhJmHgDIAQAcAAgIMRFmHgDIAQAdAAQIfhCQGAD7AAAAAA==.Nimik:BAAALAADCgEIAQAAAA==.Nivami:BAAALAAECgUIBQABLAAECgYIEQABAAAAAA==.',No='Nogward:BAABLAAECoEaAAIXAAgI/iKrBgBCAwAXAAgI/iKrBgBCAwAAAA==.Noldus:BAAALAADCgQIBAAAAA==.Nooc:BAAALAAECgYIDgAAAA==.Notsimay:BAAALAAECgUIBQAAAA==.',['Nä']='Nämira:BAAALAADCggIBwAAAA==.',Oa='Oakshiéld:BAAALAAECgYIBgAAAA==.',Ob='Obscurial:BAAALAAECgYICAAAAA==.Obselith:BAAALAADCgQIBAAAAA==.',Od='Odin:BAAALAAECggIEAAAAA==.',Oo='Oopsidaisie:BAAALAAECgUICgAAAA==.',Or='Orevuun:BAAALAAECgEIAQABLAAECgYICQABAAAAAA==.',Pa='Palalou:BAAALAADCggICAAAAA==.Palthos:BAAALAAECgYICQAAAA==.Pandav:BAABLAAECoEUAAIeAAYIdBznEQD2AQAeAAYIdBznEQD2AQAAAA==.Pangli:BAAALAADCgEIAQAAAA==.Panko:BAAALAADCgYICAAAAA==.Panxiao:BAAALAAECgUIBQAAAA==.Paxx:BAAALAADCggIEQAAAA==.',Pe='Pennygrodan:BAAALAAECgEIAQAAAA==.Peppy:BAABLAAECoEUAAIfAAYIziRNEgBpAgAfAAYIziRNEgBpAgAAAA==.Pepsham:BAAALAADCgcIBwAAAA==.Perrywinkle:BAABLAAECoEUAAILAAYI3hL1HgB+AQALAAYI3hL1HgB+AQAAAA==.Perun:BAAALAAECgUIBwAAAA==.Peturabo:BAAALAAECgYIBgAAAA==.',Ph='Phaman:BAAALAAECgYIDAAAAA==.Phenomenom:BAAALAAECgcIDQAAAA==.Physocarpus:BAAALAAECgMIAwAAAA==.',Pi='Pinica:BAAALAADCgcIDgAAAA==.',Pl='Please:BAAALAAECgcIBwAAAA==.',Po='Podtrex:BAAALAAECgEIAQAAAA==.Pokybear:BAABLAAECoEVAAIZAAcIXx1lAwBbAgAZAAcIXx1lAwBbAgAAAA==.Popss:BAAALAADCgMIAwAAAA==.',Pr='Pride:BAAALAAECgcIEAAAAA==.Priesthealer:BAABLAAECoEYAAIgAAcIGx7CFgBGAgAgAAcIGx7CFgBGAgAAAA==.Proscrito:BAAALAAECgEIAQAAAA==.Prowlite:BAAALAAECgYIBwAAAA==.',Qu='Quiks:BAAALAAECgYIBwAAAA==.',Qw='Qwack:BAAALAADCggIFAAAAA==.',Ra='Ragavan:BAAALAADCgcICgAAAA==.Ramittin:BAAALAADCgcICgAAAA==.Ratherien:BAAALAAECggICQAAAA==.Razaael:BAAALAAECgYIDgAAAA==.Razerdfx:BAAALAADCgcIDQAAAA==.',Re='Redeyepingwu:BAAALAADCggICAAAAA==.Redleb:BAAALAAECggIBgAAAA==.Rehedh:BAAALAADCggIDgAAAA==.Rehedk:BAAALAADCggIDQAAAA==.Rehelock:BAAALAAECgYIEwAAAA==.Rehesham:BAAALAADCgcICwAAAA==.Reinhalt:BAAALAADCggICAAAAA==.Rennela:BAAALAADCgcIEwAAAA==.Reroll:BAAALAAECgMIBQAAAA==.',Rh='Rhinny:BAAALAAECgMIBgAAAA==.',Ri='Riazel:BAAALAADCggICAAAAA==.Richie:BAAALAAECgYICAAAAA==.Riff:BAAALAADCggIDgAAAA==.Rimbaldi:BAAALAAECgUICgAAAA==.Rin:BAAALAADCggIDgABLAAECgMIBgABAAAAAA==.Ringnight:BAAALAAECgEIAQAAAA==.Ringo:BAABLAAECoEXAAIgAAcIDhooHgANAgAgAAcIDhooHgANAgAAAA==.Rithcie:BAAALAAECgYICQAAAA==.',Ro='Rolerin:BAAALAADCgcIFQAAAA==.Rooko:BAAALAAECgEIAQAAAA==.Roosa:BAAALAADCgcIBwAAAA==.Rotmos:BAAALAAECgEIAQAAAA==.',Ru='Runescar:BAABLAAECoEVAAMJAAgIGSEVFQC0AgAJAAcIaiIVFQC0AgAKAAMInh8qJAAkAQAAAA==.',Ry='Ryanatwood:BAAALAAECgYIDAAAAA==.',['Rö']='Rölli:BAAALAAECgcICwAAAA==.',Sa='Sakurah:BAAALAAECgMIBgAAAA==.Saltkalvis:BAAALAAECgYIDQAAAA==.',Sc='Scarletseven:BAAALAAECggICAAAAA==.Scholastica:BAAALAAECgYICwAAAA==.',Se='Secretive:BAAALAADCgUIBgAAAA==.Sencana:BAAALAADCgcICwAAAA==.Septikx:BAABLAAECoEUAAQhAAYIdSPpJQB4AQAhAAQIQiDpJQB4AQAVAAMItCLSUgAlAQAWAAMIXxovFgAEAQAAAA==.Seragost:BAAALAADCgEIAQAAAA==.Serromin:BAABLAAECoEdAAQVAAgITBqaFwBzAgAVAAgI1xmaFwBzAgAhAAQIcBtoNgAaAQAWAAEIdgKgNAA2AAAAAA==.Servator:BAABLAAECoEVAAIXAAcI5RkNMAATAgAXAAcI5RkNMAATAgAAAA==.',Sh='Shaddrin:BAAALAAECgcIDQAAAA==.Shadowfúry:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Shadoworion:BAABLAAECoEaAAIXAAgI0x0FFgCyAgAXAAgI0x0FFgCyAgAAAA==.Shadowylulu:BAAALAADCggICgAAAA==.Shakazuluu:BAAALAAECgYIEAAAAA==.Shamassia:BAAALAAECggICAAAAA==.Shaminova:BAAALAAECgYICwAAAA==.Shamlix:BAABLAAECoEkAAMfAAgILSRsAQBHAwAfAAgILSRsAQBHAwATAAUIQiEtJQDsAQAAAA==.Shankya:BAAALAAECgQICQAAAA==.Shardina:BAAALAAECgMIAwABLAAECgYIEQABAAAAAA==.Sharighar:BAAALAAECggICAAAAA==.Sharlaine:BAAALAADCggIEAABLAAECgYIEQABAAAAAA==.Sharmand:BAAALAAECgYIDwAAAA==.Shartulga:BAAALAADCgQIBAAAAA==.Shosho:BAAALAADCgcICAAAAA==.',Si='Signora:BAABLAAECoEcAAIRAAgIXCJSCgAZAwARAAgIXCJSCgAZAwAAAA==.Sigtunapal:BAABLAAECoEUAAIiAAYIUSRTBwB/AgAiAAYIUSRTBwB/AgAAAA==.Sikdude:BAAALAAECgYIBgAAAA==.Silvermoan:BAAALAADCggICQAAAA==.Simbá:BAAALAADCgMIBAABLAAECgcIEAABAAAAAA==.Sinaris:BAAALAAECgcIEgAAAA==.Sithorion:BAAALAAECgYIDQAAAA==.',Sj='Sjotrik:BAAALAAECgMIBAAAAA==.',Sk='Skenger:BAAALAAECgcIBwAAAA==.Skeptik:BAAALAAECgUICQAAAA==.Skibididruid:BAAALAADCgcICAAAAA==.Skí:BAAALAAECgYIDQAAAA==.',Sm='Smartnok:BAABLAAECoEWAAIMAAcI6RRvOgDWAQAMAAcI6RRvOgDWAQAAAA==.Smashtron:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Smoladin:BAAALAADCgYIBgAAAA==.',So='Soos:BAAALAADCggIGgABLAAECgYIFAALAFUZAA==.Soosi:BAAALAAECgIIAgABLAAECgYIFAALAFUZAA==.Soosica:BAABLAAECoEUAAILAAYIVRkuGAC6AQALAAYIVRkuGAC6AQAAAA==.',Sp='Spiritspark:BAAALAADCggICAAAAA==.Spittingice:BAAALAAECgUICAAAAA==.',Sq='Squamosa:BAAALAAECgEIAgAAAA==.',St='Stab:BAAALAAECgMIBAAAAA==.Starstrasza:BAAALAADCggIFwAAAA==.Stinges:BAAALAADCgcIBwAAAA==.Stjärntjejen:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.Stmaria:BAAALAAECgYIBgAAAA==.Stormadin:BAAALAAECgEIAQAAAA==.Stormslayer:BAAALAAECgYIDAAAAA==.Stormxdragon:BAAALAAECgcIEAAAAA==.',Su='Sure:BAAALAAECgcIDQAAAA==.',Sy='Syx:BAAALAAECgUIBQAAAA==.',['Sé']='Séren:BAAALAADCgcIBwAAAA==.',Ta='Tagaros:BAAALAAECgMIBAAAAA==.Taggy:BAABLAAECoEaAAMOAAgI+x0SDwC/AgAOAAgI+x0SDwC/AgAaAAMIOha0TgDIAAAAAA==.Talaerax:BAAALAADCgEIAQAAAA==.Tamaduitoru:BAABLAAECoEdAAMVAAgInRdiIgAcAgAVAAgIgRZiIgAcAgAhAAIIjSPHTACeAAAAAA==.Tarathyel:BAAALAADCgQIBgABLAAECgEIAQABAAAAAA==.Tarquinshar:BAAALAADCggIEAAAAA==.Taxisifu:BAAALAADCggICAAAAA==.',Th='Thabatsi:BAAALAAECgcIEQABLAAECggIGwAJAGQhAA==.Thashami:BAAALAADCggIFwABLAAECggIGwAJAGQhAA==.Theevokersam:BAAALAAECgYICAAAAA==.Thiccdumpy:BAAALAAECgYIDwAAAA==.Thorvigilant:BAAALAAECgYIDgAAAA==.Thòrn:BAAALAAECgQIBAAAAA==.',Ti='Tiamat:BAAALAAECgcIDQAAAA==.Tiddytyrant:BAAALAADCgYIBwABLAAECggICQABAAAAAA==.Timn:BAAALAADCgEIAQABLAADCgYIBQABAAAAAA==.Timyhunter:BAAALAADCgEIAQAAAA==.Tixsey:BAAALAAECgEIAQAAAA==.',Tj='Tjacu:BAAALAAECgYIDQAAAA==.',To='Toonz:BAAALAAECgMIAwAAAA==.Torchee:BAAALAADCgcIEAAAAA==.Torchem:BAAALAADCggIEAAAAA==.Torquil:BAAALAAECgEIAQAAAA==.Torsham:BAAALAADCggIDwAAAA==.Totemlagz:BAAALAAECgUIBwAAAA==.',Tr='Trikssy:BAAALAAECgUICQAAAA==.',Tu='Turnz:BAABLAAECoEXAAIOAAcIJxOzMwDAAQAOAAcIJxOzMwDAAQAAAA==.Tusko:BAACLAAFFIEGAAIaAAII4SXkBQDgAAAaAAII4SXkBQDgAAAsAAQKgR8AAhoACAjfJaUAAHYDABoACAjfJaUAAHYDAAAA.',Ty='Tyhd:BAAALAAECgYIEQAAAA==.Tyuxar:BAAALAAECgYICQABLAAECgcICwABAAAAAA==.',Um='Umbravenandi:BAABLAAECoEaAAIOAAgIzBoAEQCrAgAOAAgIzBoAEQCrAgAAAA==.',Un='Unogym:BAAALAAECgMIBQAAAA==.',Ur='Urbandecay:BAAALAAECgYIDQAAAA==.',Va='Van:BAABLAAECoEfAAMXAAgIYBysGACcAgAXAAgIYBysGACcAgALAAEIaAUKRAA0AAAAAA==.Vanilor:BAAALAADCgQIBAAAAA==.Vardann:BAAALAADCggICAAAAA==.Varothas:BAAALAADCggIEAAAAA==.Varthen:BAAALAADCgYIBgAAAA==.',Ve='Velothas:BAAALAADCgcIBwAAAA==.Vernie:BAAALAAECgYIEQAAAA==.Versuna:BAABLAAECoEfAAIRAAgIpyBuDAADAwARAAgIpyBuDAADAwAAAA==.Vexira:BAAALAADCgUIBQAAAA==.',Vi='Vindicae:BAAALAAECgYIDwAAAA==.Vitchoklad:BAAALAAECgYIEAAAAA==.Vixion:BAAALAADCgUIBQAAAA==.',Vo='Vodball:BAAALAAECgYIDwAAAA==.Voodookiller:BAAALAADCgEIAQAAAA==.',Vs='Vscárab:BAAALAAECgYIBgAAAA==.',Vu='Vulls:BAAALAADCggIFAAAAA==.',['Vê']='Vêrsuz:BAAALAAECgMIAwAAAA==.',Wa='Wandery:BAAALAAECgIIAgAAAA==.Wargame:BAAALAADCggICAABLAAECgYIFAALAFUZAA==.Warksdk:BAABLAAECoETAAIJAAYI8h/PLgAdAgAJAAYI8h/PLgAdAgAAAA==.Warksevo:BAAALAADCgQIBAABLAAECgYIEwAJAPIfAA==.Wazappenin:BAAALAAECgEIAQAAAA==.',Wi='Widos:BAAALAADCgMIAwAAAA==.Wilson:BAAALAADCggIAgAAAA==.Withatwist:BAAALAADCgcICAAAAA==.',Wo='Woodford:BAAALAADCgYICgAAAA==.',Wr='Wrathelm:BAAALAAECgYIEAAAAA==.',Wu='Wup:BAAALAAECgcIEgAAAA==.',Xa='Xalacia:BAAALAAECgUICgAAAA==.Xalence:BAABLAAECoEZAAMSAAgIUyHcBwC8AgASAAgIUyHcBwC8AgADAAEIExeHXABFAAAAAA==.Xamr:BAAALAAECgYICwAAAA==.',Xe='Xed:BAAALAADCggIDwAAAA==.',Xi='Xialia:BAAALAAECgQIBAABLAAECgYICwABAAAAAA==.Xinmei:BAAALAAECgYIDQAAAA==.',Xr='Xrpees:BAAALAADCggIFQAAAA==.',Xs='Xshaman:BAAALAADCgMIAwAAAA==.',Xy='Xyk:BAAALAAECgIIAgAAAA==.',Ya='Yaxd:BAAALAADCggICAAAAA==.',Ye='Yelan:BAAALAAECgMIBAAAAA==.',Yg='Ygrek:BAAALAAECgIIAwAAAA==.',Ym='Ymèr:BAAALAADCgcIDwAAAA==.',Yo='Yoseizura:BAABLAAECoEZAAIUAAgIxiPuAQArAwAUAAgIxiPuAQArAwAAAA==.',Yr='Yrog:BAAALAAECgEIAQABLAAECgYIDwABAAAAAA==.',Za='Zalthore:BAAALAAECgMIBQABLAADCgYICgABAAAAAA==.Zandez:BAAALAADCggICAAAAA==.',Ze='Zealchunk:BAAALAADCggICAAAAA==.Zealdrake:BAAALAADCgYIBgAAAA==.Zealrot:BAAALAAECgMIBAAAAA==.Zealwarr:BAAALAAECggICQAAAA==.Zeep:BAAALAAECgEIAgAAAA==.Zeffner:BAABLAAECoEdAAIbAAgIoh+3BADSAgAbAAgIoh+3BADSAgAAAA==.Zeruf:BAAALAAECgQIBwAAAA==.',Zn='Znail:BAABLAAECoEZAAIiAAgIWSQAAgA/AwAiAAgIWSQAAgA/AwAAAA==.',Zo='Zoltan:BAAALAAECgIIAgABLAAECgMIBAABAAAAAA==.',Zu='Zulax:BAAALAAECgYICgAAAA==.',Zw='Zwen:BAABLAAECoEUAAIOAAYIQBhjNAC8AQAOAAYIQBhjNAC8AQAAAA==.',Zy='Zythimn:BAAALAAECgcIDQAAAA==.',['Ðr']='Ðracarys:BAAALAAECgUICgAAAA==.',['Úr']='Úrscéal:BAAALAADCggIFwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end