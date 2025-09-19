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
 local lookup = {'Shaman-Restoration','Unknown-Unknown','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Druid-Restoration','DeathKnight-Unholy','Shaman-Elemental','Priest-Discipline','DeathKnight-Frost','Hunter-Marksmanship','Monk-Windwalker','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','Monk-Brewmaster','Druid-Balance','Druid-Guardian','Mage-Frost','Evoker-Preservation','Druid-Feral','Paladin-Retribution','Monk-Mistweaver','Priest-Shadow','DemonHunter-Havoc','Warrior-Protection',}; local provider = {region='EU',realm='Kargath',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Addyator:BAAALAAECgcIDQAAAA==.',Ae='Aerîthrîa:BAAALAAECgEIAgABLAAECgcIFQABAJEYAA==.',Ah='Ahrigato:BAAALAAECgEIAQAAAA==.',Ai='Aithusa:BAAALAAECgIIAgAAAA==.',Ak='Aktaíon:BAAALAADCggIDwAAAA==.',Al='Alahador:BAAALAADCgcIFAAAAA==.Aleriah:BAAALAADCgcIBgAAAA==.Allmight:BAAALAADCgcIBwAAAA==.Alunâ:BAAALAADCgcICwABLAADCgcIDQACAAAAAA==.Alysara:BAAALAADCgQIBAABLAAECggIEAACAAAAAA==.Alysîa:BAAALAADCgcIBwAAAA==.',Am='Amphiera:BAAALAAECgIIAgAAAA==.',An='Andromaeda:BAAALAADCgYICgABLAAECgMIAwACAAAAAA==.Andulina:BAAALAAECgIIBAAAAA==.Anduryoni:BAAALAADCgcIFAAAAA==.Anessar:BAAALAAECggIDwAAAA==.Anhayinn:BAAALAAECgYICAAAAA==.Animalus:BAAALAAECgYICQAAAA==.Anthorra:BAAALAADCgYIBgAAAA==.Aníko:BAAALAADCggICAAAAA==.',Ap='Apheliona:BAAALAADCgUIBQABLAAECgYICAACAAAAAA==.',Ar='Arcogul:BAAALAAECgUICQAAAA==.Arima:BAAALAAECggIEQAAAA==.',As='Asray:BAAALAAECgUICAAAAA==.Astenia:BAAALAAECgYICAAAAA==.Astraeá:BAAALAAECgMIBAAAAA==.',At='Athalein:BAAALAAECgUIBgAAAA==.',Ay='Ayarina:BAAALAADCggIDgAAAA==.',Az='Azanni:BAAALAAECgUICQAAAA==.',Ba='Bané:BAAALAADCggICAAAAA==.Bargitto:BAAALAAECgQIBgAAAA==.Baymáx:BAAALAAECgYICwAAAA==.',Be='Bearofc:BAAALAADCggICAAAAA==.Benben:BAAALAAECggICAAAAA==.',Bi='Bingas:BAAALAAECgUIBgAAAA==.',Bl='Blebon:BAABLAAECoEUAAIDAAcIcx2MDwCBAgADAAcIcx2MDwCBAgAAAA==.Blyaná:BAAALAAECgMIAwAAAA==.Blâckbûll:BAAALAADCgcIAwAAAA==.',Bo='Boneprime:BAAALAADCgMIAwAAAA==.',Br='Brülldozer:BAAALAADCggICAAAAA==.',By='Byorn:BAAALAAECgYICQAAAA==.',['Bä']='Bärty:BAAALAADCgIIAgAAAA==.',Ca='Calîgula:BAABLAAECoEUAAQEAAgIcyMKDwDuAQAEAAUIJCMKDwDuAQAFAAUIHiFqKACQAQAGAAEIyyQyIwBuAAAAAA==.Camurai:BAABLAAECoEUAAIHAAgI8g3zKwCtAQAHAAgI8g3zKwCtAQAAAA==.Carly:BAAALAAECgIIAgAAAA==.Castivar:BAAALAAECggIDAAAAA==.',Ce='Cenartyr:BAABLAAECoEVAAIIAAgIORieFADtAQAIAAgIORieFADtAQAAAA==.',Ch='Champloo:BAAALAADCgMIAwAAAA==.Chaozdh:BAAALAAECgMIAwAAAA==.Cheeky:BAAALAAECgMIAwAAAA==.Chenzen:BAAALAAECgEIAgAAAA==.Chimäraa:BAAALAAECgQICAAAAA==.Chirouge:BAAALAADCggICAAAAA==.Chrissmith:BAAALAADCgIIAgABLAADCgYIBgACAAAAAA==.',Ci='Cimmerias:BAAALAADCgMIAwABLAADCgMIAwACAAAAAA==.',Co='Condrassil:BAAALAAECgEIAgAAAA==.',Cr='Crispyrogue:BAAALAAECgYIBgAAAA==.Crispyy:BAAALAAECgcIBwABLAAECggIGAAJAOklAA==.',Cu='Cugath:BAAALAAECgYICQAAAA==.',Da='Daena:BAAALAADCgQIBAABLAAECgMIBwACAAAAAA==.Daganzandre:BAAALAADCgcIBwAAAA==.Daislon:BAAALAAECgIIAgAAAA==.Daléron:BAAALAADCgcIBwAAAA==.Danig:BAAALAAECgEIAQAAAA==.Dannyywhy:BAAALAADCgcIBwAAAA==.Dannyywhyy:BAAALAAECgYIBgAAAA==.Darkmon:BAAALAADCgMIBQAAAA==.Darksideofme:BAAALAAECgIIBAAAAA==.Daywin:BAAALAADCggICAAAAA==.Daènerys:BAAALAAECgYICAAAAA==.',De='Deadschami:BAAALAADCgcIBwAAAA==.Decay:BAAALAAECgcIDQAAAA==.Denrîa:BAAALAADCgUIBQAAAA==.Desmonica:BAAALAAECgYIDAAAAA==.Desura:BAABLAAECoEUAAIKAAcITCVeBwD0AgAKAAcITCVeBwD0AgAAAA==.',Dh='Dhofc:BAAALAADCgcIDwAAAA==.',Di='Dintalath:BAAALAAECgIIBAAAAA==.',Dk='Dkayofc:BAAALAAECgYICgAAAA==.',Do='Dodiri:BAAALAAECgEIAQAAAA==.Dohan:BAAALAAECgEIAQAAAA==.Doncochones:BAAALAADCgYIDAAAAA==.Doneras:BAAALAAECgUICQAAAA==.Donroeschen:BAAALAAECgcIDQAAAA==.Dontel:BAAALAADCggICAABLAAECgUICAACAAAAAA==.Doublejump:BAAALAAECgUICQAAAA==.',Dr='Draknor:BAAALAADCggIDgAAAA==.Dranoi:BAABLAAECoEUAAIDAAcIvSSkCQDcAgADAAcIvSSkCQDcAgAAAA==.Drogol:BAAALAAECgIIBAAAAA==.Druie:BAAALAADCgcIBwAAAA==.',Du='Dunras:BAAALAAECgEIAQAAAA==.',Dw='Dwaladin:BAAALAAECgEIAQAAAA==.Dwonk:BAAALAADCggIDgAAAA==.',Dy='Dysthymia:BAAALAADCggICAAAAA==.',Ed='Edga:BAAALAAECggICwAAAA==.',Eg='Eglath:BAAALAAECgIIAgAAAA==.',Ei='Eirmage:BAAALAAECgcIEQABLAAECgcIFAALAI4lAA==.Eirpriest:BAABLAAECoEUAAILAAcIjiWOAAAJAwALAAcIjiWOAAAJAwAAAA==.',El='Eldiablo:BAAALAADCgIIAgAAAA==.Elinia:BAAALAAECggIEAAAAA==.Ellesmára:BAAALAAECgEIAQAAAA==.Ellnora:BAAALAADCgUIBQAAAA==.Elorà:BAAALAAECggIAQAAAA==.Elunara:BAAALAADCgcIBwAAAA==.',Em='Emerellé:BAAALAAECgYICQAAAA==.Emilari:BAAALAAECgcIDwABLAAECgcIFAADAHMdAA==.',En='Endo:BAAALAAECgYIBgABLAAECgcIFQAMAGgkAA==.Endô:BAABLAAECoEVAAMMAAcIaCTtOwCWAQAMAAQIFSPtOwCWAQAJAAMILCbEFwBXAQAAAA==.Eniales:BAABLAAECoEYAAMJAAgI6SXmAABKAwAJAAgIqSTmAABKAwAMAAgIShyjEQCQAgAAAA==.',Es='Estellia:BAAALAADCgcIBwAAAA==.',Eu='Eupi:BAAALAAECgQIBAAAAA==.',Ev='Evila:BAAALAAECgQIBgAAAA==.',Ex='Exina:BAACLAAFFIEFAAMNAAMI+hvyAQAJAQANAAMI3xryAQAJAQAHAAEIcSHzCgBgAAAsAAQKgRcAAw0ACAiuIvEDAAcDAA0ACAiUIfEDAAcDAAcABwjrI6oKAMQCAAAA.',Fe='Federkleid:BAAALAADCgcIFQAAAA==.Fengschwie:BAAALAAECgIIBAAAAA==.Feride:BAAALAAFFAIIAgAAAA==.',Fi='Fioná:BAAALAADCgUIBQABLAAECggIFAAOAIchAA==.',Fr='Freyda:BAAALAAECgIIAgAAAA==.Friede:BAAALAAECgMIAwAAAA==.Frob:BAAALAAECgMIBAAAAA==.Frostyflakes:BAAALAAECgYICQAAAA==.',Fu='Funky:BAAALAAECgMIAwAAAA==.',Ga='Gaael:BAAALAAECgIIBgAAAA==.Galarian:BAABLAAECoEUAAINAAcIpCNSCQCYAgANAAcIpCNSCQCYAgAAAA==.',Ge='Genetík:BAAALAADCgcIBwAAAA==.',Gh='Ghorgoth:BAAALAADCgMIAwAAAA==.',Gi='Gimmbly:BAAALAAECgEIAgAAAA==.',Gl='Glexina:BAAALAAECgYICAAAAA==.',Go='Goldregen:BAABLAAECoEUAAIPAAcIZBh6GgDnAQAPAAcIZBh6GgDnAQAAAA==.Gorogh:BAAALAAECgcIDwAAAA==.',Gr='Grasysigirl:BAAALAAECgEIAQAAAA==.Grawndor:BAAALAADCgEIAgAAAA==.Gregpipe:BAAALAAECgYIEQAAAA==.Gregspipe:BAAALAAECgEIAQAAAA==.Gretelchen:BAABLAAECoEUAAMQAAcIriKXBAAgAgAQAAYIzh+XBAAgAgARAAQI0yJHIACLAQAAAA==.',Gu='Guglhupfl:BAAALAADCgcIEwAAAA==.Gungrâve:BAAALAADCgMIAwAAAA==.',Gy='Gyzana:BAAALAAECgYIBgAAAA==.',['Gú']='Gúts:BAAALAADCgYIBgAAAA==.',Ha='Hadéz:BAAALAAECgYIDAAAAA==.Halandor:BAAALAAECgUIAgAAAA==.Halx:BAAALAAECgEIAQAAAA==.Harbard:BAAALAAECgMIBwAAAA==.Hatsumí:BAAALAAECgUICQAAAA==.',He='Heilboy:BAAALAAECgIIAgAAAA==.Heimdallr:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.Heinoleinche:BAAALAADCgcIFAAAAA==.Henno:BAAALAAECgMIBAAAAA==.Hetja:BAAALAAECgcIDQAAAA==.Hetneoder:BAAALAADCgYIBgAAAA==.',Ho='Hogherr:BAAALAADCggICAABLAADCggICAACAAAAAA==.Holyreq:BAAALAAECgUICAAAAA==.',['Hò']='Hòrùs:BAAALAAECgMIBQAAAA==.',['Hø']='Høudini:BAAALAADCgUIBQAAAA==.',Im='Imaní:BAABLAAECoEUAAMOAAgIhyFzAwD4AgAOAAgIhyFzAwD4AgASAAII1xE7HgBsAAAAAA==.',In='Innervateboy:BAABLAAECoEUAAMTAAcILSX1BgDfAgATAAcILSX1BgDfAgAUAAQIKRNsCwDaAAAAAA==.',Ip='Ipati:BAAALAAECgMIBwAAAA==.Ipoxoql:BAAALAAECgYIDgAAAA==.',Ir='Irispallida:BAAALAAECgEIAQAAAA==.Irokan:BAAALAAECgIIAgAAAA==.Irîna:BAAALAAECgEIAgAAAA==.',Is='Isaria:BAABLAAECoEVAAIVAAgI1B0VCABkAgAVAAgI1B0VCABkAgAAAA==.Isaymoomoo:BAAALAAECgMIAwABLAAECgUICQACAAAAAA==.',It='Itzamná:BAAALAAECgQIBAAAAA==.',Ja='Jan:BAABLAAECoEUAAIMAAcI2hfWIQAVAgAMAAcI2hfWIQAVAgAAAA==.Jaydeerogue:BAAALAADCgYIBgAAAA==.',Je='Jeeper:BAAALAAECgYICQAAAA==.Jeeze:BAAALAAECgYICQAAAA==.Jensky:BAAALAADCggICAAAAA==.',Ji='Jinah:BAAALAADCgcIBwAAAA==.Jioras:BAAALAADCgIIAgAAAA==.',['Jä']='Jägermaster:BAAALAAECgIIAgAAAA==.',Ka='Kaidô:BAAALAAECgQICAABLAAECgcIFQAMAGgkAA==.Kaliandra:BAAALAADCgcIDQAAAA==.Kanisha:BAAALAADCgUIBQAAAA==.Karita:BAAALAADCggIFwABLAAFFAMIBQACAAAAAQ==.Kathleena:BAAALAADCgcIFAAAAA==.Katlystria:BAAALAAECgYICQAAAA==.Kazukamisamâ:BAACLAAFFIEGAAIWAAMIORTiAQD/AAAWAAMIORTiAQD/AAAsAAQKgSIAAhYACAh6IsgAACwDABYACAh6IsgAACwDAAAA.',Ke='Keluna:BAAALAADCgYIBgAAAA==.Kenny:BAAALAAECgMIBQAAAA==.Keolanya:BAAALAAECgIIAgAAAA==.Keolina:BAAALAADCgEIAQAAAA==.Kerby:BAABLAAECoEUAAMTAAcIaCLECAC1AgATAAcIESLECAC1AgAXAAcIKR25BgA3AgAAAA==.',Ki='Kimzy:BAAALAADCggICAAAAA==.Kitâmia:BAABLAAECoEUAAQFAAcIHyMzCQDMAgAFAAcIHyMzCQDMAgAEAAIInQ6QSQBxAAAGAAEIeQcOLgA/AAAAAA==.',Ko='Koester:BAAALAADCgcIBwAAAA==.Koihime:BAAALAAFFAMIBQAAAQ==.Korash:BAAALAAECgYIBgABLAAFFAMIBwAYAFIgAA==.Korashdk:BAAALAAFFAIIBAABLAAFFAMIBwAYAFIgAA==.Korashpal:BAACLAAFFIEHAAIYAAMIUiBXAQAgAQAYAAMIUiBXAQAgAQAsAAQKgRgAAhgACAiAJvEAAIMDABgACAiAJvEAAIMDAAAA.Kori:BAAALAADCggIEAAAAA==.Koriantha:BAAALAADCggICQAAAA==.',Kr='Kratôs:BAAALAAECgEIAQAAAA==.Kraven:BAAALAAECgIIAgAAAA==.Krelian:BAAALAAECgcICwAAAA==.Kripke:BAAALAADCggIDwABLAAFFAMIBQACAAAAAQ==.Krossel:BAAALAADCggIFwAAAA==.Kruegar:BAAALAAECgMIBwAAAA==.Kruege:BAAALAADCggICAABLAAECgMIBwACAAAAAA==.',Ky='Kyrak:BAAALAADCgUIBQAAAA==.Kyrax:BAAALAAECgYIDAAAAA==.Kyrân:BAAALAADCggICAAAAA==.',['Kà']='Kàsh:BAAALAAECgUIBQAAAA==.',['Kü']='Kücükenistee:BAAALAAECgEIAgAAAA==.',La='Lamaentchen:BAAALAADCgcIFAAAAA==.Lanek:BAAALAAECgYICQAAAA==.',Le='Leichenwagen:BAAALAADCgEIAQAAAA==.Lenti:BAAALAADCgUIBQAAAA==.Leonpardonk:BAABLAAECoEWAAMZAAcInBfJDADWAQAZAAcInBfJDADWAQASAAIIhwZpIQBFAAAAAA==.Lesnar:BAAALAADCgcIBQAAAA==.Lexer:BAAALAADCgMIAwABLAAECggIEAACAAAAAA==.',Li='Limetté:BAAALAAECgEIAQAAAA==.Littlelight:BAAALAAECgMIBgAAAA==.',Lo='Loniel:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.Loui:BAAALAAECgMIBQAAAA==.',Lu='Lucantara:BAAALAAECggICAAAAA==.Lunaticc:BAAALAADCggICAAAAA==.Luzifon:BAAALAAECgYIDgAAAA==.',Ly='Lya:BAAALAAECgIIBAAAAA==.',['Lé']='Léø:BAAALAADCgMIAwAAAA==.',['Lø']='Løoki:BAAALAADCgYIBgAAAA==.',['Lú']='Lúx:BAAALAADCggICAAAAA==.',Ma='Maccon:BAAALAAECgYIBgAAAA==.Madras:BAAALAAECgIIAgAAAA==.Mafidk:BAAALAADCggICAAAAA==.Mailín:BAAALAAECgYICwAAAA==.Majlena:BAAALAAECggIBQAAAA==.',Me='Melanna:BAAALAADCgcIEwAAAA==.Melficepimp:BAAALAADCggIEAAAAA==.Melonno:BAAALAAECgMIBgAAAA==.Melonnopries:BAAALAADCggICQAAAA==.Meredias:BAAALAADCggICAABLAAECgEIAQACAAAAAA==.Merkato:BAAALAAFFAIIAwAAAA==.Metis:BAAALAADCgYIBgAAAA==.',Mi='Midar:BAAALAAECgYICgAAAA==.Milunà:BAAALAADCggICAAAAA==.Mindraz:BAAALAAECgIIAgAAAA==.Misfire:BAAALAAECgMIBQAAAA==.Miágona:BAAALAAECgMICAAAAA==.',Mo='Mobbi:BAAALAAECgMIAwAAAA==.Mondscheîn:BAAALAAECgcIDgAAAA==.Morgâna:BAAALAAECgEIAgAAAA==.Moti:BAABLAAFFIEFAAIaAAMIQiK+AQA1AQAaAAMIQiK+AQA1AQAAAA==.Mousy:BAAALAAECgMIBwAAAA==.',Mu='Muhfasa:BAAALAADCgQIBAAAAA==.Murdogg:BAAALAADCgQIBAAAAA==.',['Mâ']='Mâmmôn:BAAALAAECggIEgAAAA==.',['Mä']='Mägni:BAAALAAECgIIBAAAAA==.',['Mé']='Médíc:BAAALAAECgUICAAAAA==.',['Mê']='Mêppo:BAAALAADCggIEAAAAA==.',['Mí']='Mínasu:BAAALAADCggIFgAAAA==.',['Mö']='Möller:BAAALAAECgEIAQAAAA==.Möw:BAAALAAECgYIEAABLAAFFAMIBwAbAEsZAA==.Möwe:BAACLAAFFIEHAAIbAAMISxmMAgAkAQAbAAMISxmMAgAkAQAsAAQKgRsAAhsACAifJjABAH0DABsACAifJjABAH0DAAAA.',Na='Nalnig:BAAALAAECgUIBwAAAA==.Namo:BAAALAAECgYICAAAAA==.Naroschima:BAABLAAECoEUAAIBAAcIjiArCgCAAgABAAcIjiArCgCAAgAAAA==.Nashoba:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.Nataku:BAAALAAECgMIBwAAAA==.Naunet:BAAALAAECgYICAAAAA==.Nayela:BAAALAAECgEIAgAAAA==.Nazguul:BAAALAADCgUIBQAAAA==.',Ne='Neevi:BAABLAAECoEXAAIHAAgIZSSMAgBMAwAHAAgIZSSMAgBMAwAAAA==.Neischa:BAAALAAECgcIEQABLAAECgcIFAATAC0lAA==.Nerîen:BAAALAAECgcIEwAAAA==.Nesoy:BAAALAADCgcIDgAAAA==.Nexxo:BAAALAADCgcIEgAAAA==.',Ni='Nilanjá:BAAALAADCgcICQAAAA==.Nima:BAAALAADCggIDgAAAA==.Nimmermehr:BAAALAAECgIIBAAAAA==.',No='Nofcksgiven:BAAALAADCgcIBwAAAA==.Nogrâd:BAAALAADCgcIDQAAAA==.Noknok:BAAALAADCggIFAAAAA==.Nonamed:BAAALAADCgEIAQAAAA==.Noobyd:BAAALAAECgYIBgAAAA==.Norge:BAAALAADCgcIDgAAAA==.Norsî:BAAALAAECgMIBAAAAA==.',Nu='Numee:BAABLAAECoEVAAIYAAgIbxqmGABMAgAYAAgIbxqmGABMAgAAAA==.',Ny='Nylaná:BAAALAADCgEIAQAAAA==.Nyssa:BAAALAADCgYIBgAAAA==.',['Ná']='Nádeshà:BAAALAADCgcIBwAAAA==.',['Nâ']='Nârôn:BAAALAAECgcIDgAAAA==.',['Nê']='Nêx:BAAALAAECgcIDQAAAA==.',['Ní']='Níní:BAAALAAECgMIBAAAAA==.',Oe='Oeten:BAAALAAECgMIAwAAAA==.',Ol='Olendo:BAAALAADCgUIBQAAAA==.',Om='Omegá:BAAALAADCgMIAwAAAA==.',Or='Orelin:BAAALAADCgcIBwAAAA==.',Os='Oscara:BAAALAADCggICAAAAA==.',Ow='Owly:BAAALAAECgMIBgAAAA==.',Pa='Padraig:BAAALAADCgMIAwAAAA==.Paltor:BAAALAADCgMIBQAAAA==.Papalegba:BAAALAADCggICAAAAA==.Parinea:BAAALAAECgYIDAAAAA==.Pat:BAAALAAECgIIBAAAAA==.',Pe='Pelzcifer:BAAALAADCggIEgAAAA==.Perathun:BAAALAAECgMIBQAAAA==.',Ph='Phoenixx:BAAALAADCgEIAQABLAAECgEIAQACAAAAAA==.Phyrra:BAAALAADCggIDQAAAA==.',Pi='Pittêy:BAAALAAECgIIAgAAAA==.Piølock:BAAALAAECgYICQAAAA==.',Pl='Planyy:BAAALAADCgcIBwAAAA==.',Pr='Prinzpipi:BAAALAADCgYIBgAAAA==.',Pu='Puhzilla:BAAALAAECgMIBwAAAA==.',['Pî']='Pîper:BAAALAAECgMIBQAAAA==.Pîttey:BAAALAAECgMIBAAAAA==.',Qi='Qi:BAAALAAECgYIDAAAAA==.',Qu='Quallina:BAAALAAECgIIAgAAAA==.Quent:BAAALAADCgcIFAAAAA==.Quälerin:BAAALAAECgEIAQAAAA==.Quèénkloede:BAAALAAECgYIDAAAAA==.',['Qé']='Qéra:BAAALAADCgcIBwAAAA==.',Ra='Raagnaar:BAAALAAECgMIBAAAAA==.Rachla:BAAALAADCggIDAAAAA==.Randor:BAAALAADCggIFAAAAA==.',Re='Rec:BAAALAAECgMIAwAAAA==.Reinold:BAAALAADCggICAAAAA==.Resort:BAAALAAECgcIEwAAAA==.Revetha:BAAALAADCggICAABLAAECgYIBgACAAAAAA==.Revn:BAAALAADCggIEAAAAA==.',Rh='Rhayn:BAAALAADCgcIBwAAAA==.',Ri='Ribblor:BAAALAADCgcIEAAAAA==.',Ro='Roal:BAAALAAECggIEQAAAA==.Rodnay:BAAALAAECgYICQAAAA==.Roguedrian:BAAALAAECgYIBgAAAA==.',Sa='Salazâr:BAAALAADCgIIAgAAAA==.Sandaîme:BAAALAAECgEIAgAAAA==.Sansoga:BAAALAADCggIDgAAAA==.Sartaríus:BAAALAAECgMIAwAAAA==.Sathanael:BAAALAAECgQIBgAAAA==.Saurfang:BAAALAADCggICAAAAA==.Sayorí:BAAALAAECgIIAgAAAA==.',Sc='Scantrax:BAAALAAFFAEIAQAAAA==.Schadoprist:BAAALAADCgYIBgAAAA==.Schnukelchen:BAAALAAECgEIAgAAAA==.Schádow:BAAALAAECgcICQAAAA==.',Se='Sephîra:BAAALAAECgcIEgAAAA==.Sethur:BAAALAADCggIEAAAAA==.',Sh='Shalíen:BAAALAADCgcICwAAAA==.Shamigaael:BAAALAADCgYICQAAAA==.Shamxter:BAAALAADCggIDwAAAA==.Shaolin:BAAALAAFFAIIBAAAAA==.Shaox:BAABLAAECoEXAAIMAAgIASFAEQCVAgAMAAgIASFAEQCVAgABLAAFFAIIBAACAAAAAA==.Shatin:BAAALAAECgcIEAAAAA==.Shayi:BAAALAAECgEIAgAAAA==.Shinoakuma:BAAALAAECgMIBwAAAA==.Shìrø:BAAALAAECggICAAAAA==.',Si='Sikudhani:BAABLAAECoEUAAIHAAcIOSR/CADmAgAHAAcIOSR/CADmAgAAAA==.Sikudhanius:BAAALAADCgEIAQAAAA==.Silax:BAAALAAECgcICgAAAA==.Simiie:BAABLAAECoEUAAIYAAcImSIBEACiAgAYAAcImSIBEACiAgAAAA==.',Sl='Slo:BAAALAAECgEIAgAAAA==.',Sm='Smashsuu:BAABLAAECoEUAAIcAAgI4BmoCQAnAgAcAAgI4BmoCQAnAgAAAA==.Smôkey:BAAALAADCgEIAQABLAAECgUICQACAAAAAA==.',Sn='Snackfist:BAAALAAECgEIAQAAAA==.',So='Soulreâver:BAAALAAECgIIAgAAAA==.',St='Stace:BAAALAADCgYIAgAAAA==.Stallknecht:BAAALAAECgMIAwAAAA==.Steppenhund:BAAALAAECgMIAQAAAA==.Sternwind:BAAALAAECgEIAQAAAA==.Stumpiline:BAAALAAECggICgAAAA==.',Su='Suì:BAAALAADCgYIBgAAAA==.',Sy='Synturia:BAAALAADCgcIEwAAAA==.',['Sâ']='Sâlixx:BAAALAAECgYIDgAAAA==.Sânâ:BAAALAAECgMIAwABLAAFFAMIBQACAAAAAQ==.',['Sí']='Sívo:BAAALAADCgcIBwAAAA==.',['Sî']='Sîvan:BAAALAAECgUIAgAAAA==.',['Sø']='Søphíá:BAAALAADCgMIAwAAAA==.',['Sý']='Sýlvanas:BAAALAADCggICAAAAA==.',Ta='Taurîn:BAAALAADCggIDQAAAA==.',Te='Telnamir:BAAALAAECgEIAQAAAA==.Temptation:BAAALAAECgEIAQAAAA==.Temári:BAAALAADCggICAAAAA==.Tentagon:BAAALAAECgYIBwAAAA==.Terraria:BAABLAAECoEUAAIZAAcIZiRTAwDZAgAZAAcIZiRTAwDZAgAAAA==.Terrodar:BAACLAAFFIEFAAMRAAMIuhWRAgATAQARAAMIfhORAgATAQAQAAEIZAysBQBKAAAsAAQKgRcAAxEACAg0IxEDAB4DABEACAi0IhEDAB4DABAABQhcGy8HALwBAAAA.Tetrapackk:BAAALAADCgYIBwAAAA==.',Th='Thalgrimm:BAAALAAECgIIBAAAAA==.Thaloria:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.Tharon:BAAALAAECgYIBgAAAA==.Thorvie:BAAALAAECgIIAgAAAA==.Thorêx:BAAALAADCgcIBwAAAA==.Thráìn:BAAALAAECgcIDgAAAA==.Thurna:BAAALAAECgEIAQAAAA==.Thyphòón:BAAALAADCggIDgAAAA==.Thánâtos:BAAALAADCggIFwAAAA==.',Ti='Tiane:BAAALAAECgEIAgABLAAECggIFAAOAIchAA==.Tiirii:BAAALAAECgIIBAAAAA==.Tissaia:BAAALAAECgQICgAAAA==.',To='Toukachi:BAABLAAECoEVAAMZAAgIpRq0CAA0AgAZAAgIpRq0CAA0AgASAAEItBHtIQA/AAAAAA==.',Tr='Trilo:BAAALAAECgIIAgAAAA==.Tryx:BAAALAADCggICAABLAAFFAMIBQARALoVAA==.',Ts='Tsunadè:BAAALAAECgYIDgAAAA==.',Tu='Tulakort:BAAALAAECgYICQAAAA==.Turinturamba:BAABLAAECoEUAAIPAAcIaBC3JQCSAQAPAAcIaBC3JQCSAQAAAA==.Turox:BAAALAAECgUICAAAAA==.',Tw='Twice:BAAALAAECgEIAQAAAA==.',['Tâ']='Târâ:BAAALAAECgMIBwAAAA==.',['Tí']='Tínkabell:BAAALAAECgYIBgAAAA==.',['Tî']='Tîlda:BAAALAAECgEIAQAAAA==.',['Tó']='Tónks:BAAALAAECgIIAgAAAA==.',Un='Unreality:BAAALAADCggICAAAAA==.',Va='Vaghortar:BAAALAAECgIIBAAAAA==.Valandriel:BAAALAAECgIIBAAAAA==.',Ve='Veganiah:BAAALAAECgIIBAAAAA==.Venatras:BAAALAAECgYIDQAAAA==.',Vi='Vicjess:BAAALAAECgQIBwAAAA==.Violanta:BAAALAAECgEIAQAAAA==.',Vu='Vulweska:BAAALAAECgEIAQAAAA==.',['Væ']='Væssel:BAAALAADCggIEAAAAA==.',Wa='Wacrafting:BAAALAAFFAIIAgAAAA==.Walsungen:BAAALAAECgEIAgAAAA==.',Wh='Whiteshade:BAAALAAECgcIEQAAAA==.Whitémoon:BAABLAAECoEVAAMPAAgIORhwFgANAgAPAAgIORhwFgANAgAaAAMIIgmfQACgAAAAAA==.',Wi='Widlu:BAAALAAECgUICAAAAA==.',['Wî']='Wîngbow:BAAALAAECgUICQAAAA==.',Xa='Xatari:BAAALAADCgUIBQABLAAECgQIBgACAAAAAA==.',Xi='Xineard:BAAALAAECgEIAgAAAA==.',Xu='Xurî:BAAALAAECgMIBAAAAA==.',['Xâ']='Xârdes:BAAALAAECgYICgAAAA==.',['Xê']='Xênyâ:BAAALAAECgEIAgAAAA==.',Ya='Yakura:BAAALAADCggICAAAAA==.Yaschida:BAAALAAECgIIBAAAAA==.',Yg='Ygthrasir:BAAALAAECgUICQAAAA==.',Yu='Yubaba:BAAALAADCggICAAAAA==.',Za='Zalandoheart:BAAALAADCggICwAAAA==.Zandos:BAAALAAECgMIBwAAAA==.Zazel:BAAALAAECgYIDwAAAA==.',Ze='Zekulrakkas:BAABLAAECoEYAAIMAAgI8CLfBAAtAwAMAAgI8CLfBAAtAwAAAA==.Zelagorr:BAAALAAECgcIEAAAAA==.',Zn='Znage:BAAALAAECgQIAwAAAA==.',Zo='Zo:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.',Zw='Zwaegwynn:BAAALAAECgMIBAAAAA==.Zwuckella:BAAALAADCgIIAgABLAAECgMIBAACAAAAAA==.',Zy='Zycanis:BAAALAAECgMIAwAAAA==.Zylen:BAAALAADCgcIDAAAAA==.Zyras:BAAALAAECgMIAwAAAA==.',['Zô']='Zôydbêrg:BAAALAAECgEIAQAAAA==.',['Áe']='Áebola:BAAALAAECgMIAwAAAA==.',['Âb']='Âbaddon:BAAALAAECgYIDAAAAA==.',['Âl']='Âlbedo:BAAALAADCggIDwAAAA==.',['Æp']='Æp:BAAALAAECgMIBwAAAA==.',['Ær']='Ærik:BAAALAAECggICQAAAA==.',['Öt']='Öthendris:BAAALAADCgYIBgAAAA==.',['Úl']='Úlfur:BAAALAAECgcIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end