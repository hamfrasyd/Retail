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
 local lookup = {'Warrior-Fury','Priest-Holy','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Brewmaster','Hunter-BeastMastery','Druid-Feral','Unknown-Unknown','Warrior-Arms','Druid-Restoration','Rogue-Assassination','Evoker-Devastation','Shaman-Elemental','Warrior-Protection','Monk-Windwalker','Shaman-Enhancement','Shaman-Restoration','DemonHunter-Havoc','Rogue-Subtlety','Priest-Shadow','Priest-Discipline','Druid-Guardian','Paladin-Protection','Hunter-Survival','Rogue-Outlaw','DeathKnight-Blood','Hunter-Marksmanship','DemonHunter-Vengeance',}; local provider = {region='EU',realm='Mannoroth',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ag='Agonizer:BAABLAAECoEYAAIBAAYI/iLFKwBcAgABAAYI/iLFKwBcAgAAAA==.',Ai='Aiolia:BAABLAAECoEdAAICAAgIBBZdKQAkAgACAAgIBBZdKQAkAgAAAA==.',Aj='Ajur:BAAALAAECgYIDAAAAA==.',Ak='Akki:BAAALAAECgYIDQAAAA==.',Al='Alfhari:BAABLAAECoEbAAIDAAcINROnJwDEAQADAAcINROnJwDEAQAAAA==.Aliurá:BAAALAADCgYIBgAAAA==.Allani:BAACLAAFFIEJAAMEAAMI5yEvAwAuAQAEAAMI5yEvAwAuAQAFAAEIexvMZgBQAAAsAAQKgS0AAwQACAi8JYcEAAsDAAQABwj3JYcEAAsDAAUABghJInd0ANgBAAAA.',Am='Amandil:BAAALAADCggICAAAAA==.',An='Anamanaguchi:BAAALAAECgYICAAAAA==.Andigossa:BAABLAAECoElAAIGAAgIMQilSwBQAQAGAAgIMQilSwBQAQAAAA==.Anduíl:BAABLAAECoEaAAMDAAcIfBl5MQCPAQAHAAcIDhG7ZQCzAQADAAYIIBh5MQCPAQAAAA==.Anima:BAAALAAECgYIEgAAAA==.',Ar='Arodberia:BAABLAAECoEeAAMIAAcIjB4fEQBlAgAIAAcIjB4fEQBlAgAJAAMI8QSWJQFhAAAAAA==.Aronui:BAAALAAECgMIAwAAAA==.Arte:BAAALAADCgYICAAAAA==.',As='Asarie:BAABLAAECoEZAAIJAAgIjg6hdADQAQAJAAgIjg6hdADQAQAAAA==.Ashena:BAAALAADCgcIBwAAAA==.Ashên:BAAALAADCggIHAAAAA==.',Av='Avarrion:BAAALAADCgYIDAAAAA==.',Az='Azubi:BAABLAAECoEdAAIKAAcIJg+iYwCSAQAKAAcIJg+iYwCSAQAAAA==.',Ba='Babba:BAAALAAECgYIEQAAAA==.Babbaohara:BAAALAADCggICAAAAA==.Babylegs:BAAALAAECgYIEAAAAA==.Balloroc:BAABLAAECoEfAAQLAAgIRRwyCwCbAgALAAgIsBsyCwCbAgAKAAgIFBJeSQDnAQAMAAIIJAsZMgBVAAAAAA==.Bandypop:BAAALAAECggIDgAAAA==.Barbar:BAAALAADCgYIBgAAAA==.Barimgar:BAABLAAECoEhAAINAAgIIiLtBQD5AgANAAgIIiLtBQD5AgAAAA==.Bava:BAABLAAECoElAAIOAAgIxCNuDgAQAwAOAAgIxCNuDgAQAwAAAA==.',Be='Berniedh:BAAALAAECgYIDAAAAA==.',Bl='Blinc:BAAALAAECggIBAAAAA==.Blinkedaway:BAABLAAECoEUAAIHAAcILh4kLACCAgAHAAcILh4kLACCAgAAAA==.Bloodrage:BAAALAADCggICAAAAA==.',Bo='Bojenn:BAAALAAECgYIDAAAAA==.Botis:BAAALAAECgQIBAABLAAECggIHwALAEUcAA==.Botistadk:BAAALAAECggIDgABLAAECggIHwALAEUcAA==.Botistadruid:BAAALAADCggICAABLAAECggIHwALAEUcAA==.Botistawl:BAAALAAECgMIAwABLAAECggIHwALAEUcAA==.',Br='Brako:BAAALAADCgIIAgAAAA==.Branx:BAAALAADCgIIBQAAAA==.Brotherpak:BAAALAAECgYICgAAAA==.Broxy:BAABLAAECoEXAAIPAAcIcBWTFwDDAQAPAAcIcBWTFwDDAQAAAA==.Broxyma:BAAALAAECgIIAwAAAA==.',Bu='Bujinkahn:BAAALAADCgcIDwAAAA==.',Ca='Cadrannax:BAAALAAECgYIBgAAAA==.Catharsia:BAAALAADCgMIAwABLAADCggIHAAQAAAAAA==.Caylee:BAAALAADCgcIBwAAAA==.Cazi:BAABLAAECoEaAAMRAAgIbRUuDQDjAQARAAcIExYuDQDjAQABAAgIoQ6vUgDBAQAAAA==.',Ch='Chiccá:BAAALAADCggIFgAAAA==.Chirte:BAAALAAECgYIBwAAAA==.Chrîsi:BAAALAAECgIIBAAAAA==.Chrütli:BAABLAAECoEnAAISAAgIcx8KDADfAgASAAgIcx8KDADfAgAAAA==.',Cl='Clapy:BAAALAAECgQIBAABLAAECgYIDgAQAAAAAA==.',Co='Cowbustion:BAAALAAECgcICwABLAAFFAMICQATAKcaAA==.',Cu='Cuki:BAAALAADCgYIBgAAAA==.Curcaryen:BAABLAAECoEeAAIBAAgItQw3UwDAAQABAAgItQw3UwDAAQAAAA==.',Da='Dalron:BAAALAAECgYICAAAAA==.Darksnaké:BAAALAADCggIDQAAAA==.Datsugokushu:BAAALAADCggICAAAAA==.',De='Deathjeep:BAAALAAECgQIBgAAAA==.Dessembrae:BAACLAAFFIEGAAIPAAII+hgZCACkAAAPAAII+hgZCACkAAAsAAQKgSsAAg8ACAiCIm0EABADAA8ACAiCIm0EABADAAAA.Devíne:BAAALAADCggICAAAAA==.',Di='Diarrha:BAABLAAECoEjAAIKAAgIYxQbQAAKAgAKAAgIYxQbQAAKAgAAAA==.Diaze:BAABLAAECoEpAAIUAAgIqhyHEgCGAgAUAAgIqhyHEgCGAgAAAA==.Dinavier:BAAALAAECgYICQAAAA==.',Do='Dohaam:BAAALAADCgEIAQAAAA==.Dohan:BAAALAADCgUIBQAAAA==.Dokmar:BAABLAAECoEcAAIVAAcI6CLFGAC3AgAVAAcI6CLFGAC3AgAAAA==.Doros:BAACLAAFFIEJAAIWAAMIihuCBwAAAQAWAAMIihuCBwAAAQAsAAQKgS0AAhYACAiNJeABAGwDABYACAiNJeABAGwDAAAA.Dorosdk:BAAALAAECggICAABLAAFFAMICQAWAIobAA==.Dorosmonk:BAABLAAECoEZAAMNAAgIGiPOBQD8AgANAAgI7SDOBQD8AgAXAAYI4h6rGgACAgABLAAFFAMICQAWAIobAA==.Dorosrogue:BAAALAADCgQIBAABLAAFFAMICQAWAIobAA==.Dotcleve:BAAALAADCggICAABLAAECggIHwALAEUcAA==.Dovahkiin:BAAALAAECgIIAgAAAA==.',Dr='Drovi:BAAALAAECgIIAgABLAAECgMIAwAQAAAAAA==.Drudax:BAAALAAFFAIIAgAAAA==.',Dy='Dyrîos:BAACLAAFFIEJAAIJAAMIUBtiDQAJAQAJAAMIUBtiDQAJAQAsAAQKgS0AAgkACAjKJA4MAD8DAAkACAjKJA4MAD8DAAAA.',Ei='Einsbäm:BAAALAAECgYIBwAAAA==.',El='Elara:BAAALAADCgQIBAAAAA==.Elcìd:BAAALAADCggIEAAAAA==.Eldarik:BAAALAAECgIIBgAAAA==.Eldreanne:BAAALAAECggICAAAAA==.Ele:BAABLAAECoEVAAIJAAYICxy+bQDeAQAJAAYICxy+bQDeAQAAAA==.Elenorus:BAAALAAECgYIDQAAAA==.Elisra:BAAALAADCgMIAwAAAA==.Elissha:BAAALAADCgMIBQAAAA==.Ellara:BAAALAADCgYIDAAAAA==.Ellendil:BAAALAAECgIIAgAAAA==.',Em='Emousa:BAAALAAECgEIAQABLAAECggIHwALAEUcAA==.',En='Engînss:BAAALAAECggICAAAAA==.Engîîns:BAAALAADCgQIBAAAAA==.',Er='Eruja:BAAALAAECgYIEgAAAA==.',Ev='Evil:BAAALAAECgIIBAAAAA==.Evoiin:BAACLAAFFIEJAAIYAAIIhyGsAwC5AAAYAAIIhyGsAwC5AAAsAAQKgSAAAhgACAh6HtYEAMMCABgACAh6HtYEAMMCAAAA.',Fa='Falkriya:BAABLAAECoEvAAIKAAgI+wgVbQB4AQAKAAgI+wgVbQB4AQAAAA==.',Fe='Feeldis:BAABLAAECoEcAAIKAAgIZwmNbwBxAQAKAAgIZwmNbwBxAQAAAA==.',Fi='Finchen:BAAALAAECgMIAwAAAA==.',Fl='Flinkxerella:BAAALAAFFAcIAgABLAAFFAcIAgAQAAAAAA==.Flinkxqt:BAAALAAECgYIBgABLAAFFAcIAgAQAAAAAA==.Flinkxrushdc:BAAALAAECggICgABLAAFFAcIAgAQAAAAAA==.Flinkxs:BAAALAAFFAcIAgAAAA==.Flinkz:BAAALAAECggICQABLAAFFAcIAgAQAAAAAA==.',Fr='Friedda:BAAALAADCgMIAwAAAA==.Fropoq:BAABLAAECoEmAAIOAAgIKB4+LgBjAgAOAAgIKB4+LgBjAgAAAA==.',['Fâ']='Fâ:BAAALAAECggIDwAAAA==.',Ga='Ganjialf:BAABLAAECoElAAIGAAcI+wuzSABdAQAGAAcI+wuzSABdAQAAAA==.Garak:BAAALAAECgQICQAAAA==.',Ge='Getshwifty:BAAALAAECgIIAgAAAA==.',Gl='Glramlin:BAAALAAECgYIDwAAAA==.',Go='Gonnameowbro:BAACLAAFFIEJAAISAAQIRRJxBwA0AQASAAQIRRJxBwA0AQAsAAQKgRoAAxIABwjdG6IgAEICABIABwjdG6IgAEICAAYAAgiNDF6QADEAAAEsAAUUBggbABkAdxoA.Gorok:BAAALAAECgQICQAAAA==.Gortan:BAAALAAECgEIAQAAAA==.',Gr='Grimstone:BAAALAAECggIAgAAAA==.Grinex:BAAALAADCgQIBAABLAAFFAUIFwABAHoeAA==.',['Gú']='Gúnner:BAAALAAECgQIBQAAAA==.',Ha='Hairbert:BAAALAADCgYIBgABLAAFFAMICQAWAIobAA==.Haruhi:BAAALAAECggIBAAAAA==.Hatemymates:BAAALAAECggIEAABLAAFFAMICQAEAOchAA==.',He='Hefesaft:BAABLAAECoEcAAIaAAcILAwunQBeAQAaAAcILAwunQBeAQAAAA==.Heimì:BAABLAAECoEeAAMTAAgIUBEXKQDEAQATAAcIBBMXKQDEAQAbAAgIOwhBIABkAQAAAA==.Hexer:BAAALAADCggICAAAAA==.',Hi='Hildeguard:BAAALAAECgYIBgABLAAECgYIDgAQAAAAAA==.',Ho='Homegrow:BAAALAAECgcIEwAAAA==.',Hu='Humanitär:BAABLAAECoEuAAICAAgIGR+iFQCjAgACAAgIGR+iFQCjAgAAAA==.',Hy='Hypothermic:BAAALAAECggICAAAAA==.',['Hä']='Härrbert:BAAALAAECgYICgAAAA==.',['Hü']='Hügelhans:BAABLAAECoEmAAIJAAgIiR/NIgDEAgAJAAgIiR/NIgDEAgAAAA==.',Ic='Icky:BAAALAADCggIDgAAAA==.',Im='Imperio:BAABLAAECoEZAAIcAAcIEhUCNADYAQAcAAcIEhUCNADYAQAAAA==.',In='Intyra:BAAALAAECgYICgABLAAECggIEAAQAAAAAA==.',Ip='Ipo:BAAALAAECgYIBgAAAA==.Ipolita:BAAALAAFFAIIAgAAAA==.',Ir='Irgendwas:BAAALAAECgQIAwABLAAECgYIDwAQAAAAAA==.',Is='Isilock:BAACLAAFFIEJAAMKAAMI5yDfEwAhAQAKAAMI5yDfEwAhAQALAAEI8RXHHwBSAAAsAAQKgS0ABAoACAhNJgUDAHUDAAoACAhBJgUDAHUDAAwABQhvIxoNAMQBAAsAAQgdJvx6AFUAAAAA.Isimage:BAACLAAFFIEHAAIHAAIIqBFNPQCOAAAHAAIIqBFNPQCOAAAsAAQKgSAAAgcACAhXI0cNACQDAAcACAhXI0cNACQDAAEsAAUUAwgJAAoA5yAA.Isome:BAACLAAFFIELAAMSAAMIgiKXBwAwAQASAAMIgiKXBwAwAQAGAAEI8R4CHgBeAAAsAAQKgSAAAxIACAgFJR0DAEkDABIACAgFJR0DAEkDAAYABgjmG2AzAMEBAAAA.Isril:BAABLAAECoEfAAIHAAgIRxT5SAAMAgAHAAgIRxT5SAAMAgAAAA==.',Iz='Izuriel:BAABLAAECoEWAAIdAAcIoCCRAwCVAgAdAAcIoCCRAwCVAgAAAA==.',Ja='Jablonek:BAABLAAECoEWAAIXAAYImR6JGgADAgAXAAYImR6JGgADAgAAAA==.Jaffia:BAABLAAECoEfAAIbAAgI+h5nBwCxAgAbAAgI+h5nBwCxAgAAAA==.Jairá:BAACLAAFFIEJAAIDAAMI1xLLAwD2AAADAAMI1xLLAwD2AAAsAAQKgS0AAwMACAhpJqUAAIsDAAMACAhpJqUAAIsDAAcABAg6FzKeABQBAAAA.Jas:BAAALAADCgcIBwAAAA==.',Je='Jenira:BAAALAADCgIIAgAAAA==.Jeraziah:BAAALAADCgcIBwAAAA==.',Jo='Joshi:BAAALAADCggIDwAAAA==.',Ka='Kaius:BAABLAAECoEVAAICAAYIjhxsOADWAQACAAYIjhxsOADWAQAAAA==.Kajany:BAAALAAECgIIBAAAAA==.Kamikaze:BAAALAAECgYIBgABLAAECggIHwALAEUcAA==.Karon:BAAALAAECggIEAAAAA==.Kateri:BAABLAAECoEiAAIZAAgI9hl/KABNAgAZAAgI9hl/KABNAgABLAAFFAMICQACAHwTAA==.Kazan:BAABLAAECoEUAAIFAAcIvh6MXQAIAgAFAAcIvh6MXQAIAgAAAA==.',Kc='Kcelsham:BAABLAAECoEeAAIVAAgIfyENDwAFAwAVAAgIfyENDwAFAwAAAA==.',Ke='Kendora:BAABLAAECoEdAAIOAAgILRTEUgDoAQAOAAgILRTEUgDoAQAAAA==.',Kj='Kjimx:BAAALAAECgUICAAAAA==.',Kl='Klappmässä:BAAALAADCgcIDwAAAA==.Kleymar:BAAALAADCgcICQAAAA==.',Km='Kmxdot:BAAALAAECgUICwAAAA==.',Ko='Koneko:BAAALAADCggIDQABLAAECggIHwALAEUcAA==.Konua:BAAALAAECgYICQAAAA==.',Kr='Kriegesgott:BAAALAAECgEIAQAAAA==.',Ku='Kux:BAAALAADCgMIBwAAAA==.Kuxqt:BAAALAAECggICAAAAA==.',Ky='Kystiran:BAAALAADCgIIAgAAAA==.',['Kâ']='Kâin:BAABLAAECoEbAAMeAAcIQwdgGQAOAQAeAAcI3QZgGQAOAQAPAAIIuAWNPABIAAAAAA==.',La='Lalatina:BAAALAAECgYICQAAAA==.Lavanda:BAAALAADCggICAAAAA==.',Le='Leoryn:BAAALAADCggIDwAAAA==.Leándra:BAAALAADCgcIDgAAAA==.',Li='Liliax:BAABLAAECoEYAAISAAcIZCKJEQCsAgASAAcIZCKJEQCsAgAAAA==.Lilijana:BAAALAAECgYIBwABLAAECgcIGAASAGQiAA==.Lingeri:BAAALAAECgYIDgAAAA==.Lissya:BAAALAADCgcIDQAAAA==.Lisyra:BAACLAAFFIEMAAIKAAMIcBUcGgDsAAAKAAMIcBUcGgDsAAAsAAQKgTcAAwoACAhVH8QYANcCAAoACAhVH8QYANcCAAwABggsBL0bAP4AAAAA.',Ll='Llewellyn:BAAALAAECgYIEgAAAA==.',Lo='Lominia:BAAALAAECgYIBgAAAA==.Lorîanna:BAACLAAFFIEJAAICAAMIfBNTEADnAAACAAMIfBNTEADnAAAsAAQKgS0AAwIACAiNIscLAPgCAAIACAiNIscLAPgCABwABAhRCbJrAMAAAAAA.Loso:BAABLAAECoEYAAIfAAgI7B1dCgCrAgAfAAgI7B1dCgCrAgAAAA==.',Lu='Lueska:BAAALAADCgcIBwAAAA==.Lumyna:BAAALAAECggIDAAAAA==.Lurckys:BAAALAADCgcIBwABLAAECggIEwAQAAAAAA==.Lurkeys:BAAALAAECggIEwAAAA==.Lurkeyz:BAAALAADCggICAABLAAECggIEwAQAAAAAA==.',Ma='Maliras:BAAALAADCggICAAAAA==.Malkus:BAABLAAECoEdAAIJAAgIFhlSWwAHAgAJAAgIFhlSWwAHAgAAAA==.Marlingo:BAAALAAECgIIAgAAAA==.Masel:BAAALAADCgQIBAAAAA==.',Me='Meron:BAAALAAECgEIAQAAAA==.Mertyria:BAAALAADCggIEAAAAA==.',Mi='Micha:BAAALAADCggICAAAAA==.Miisha:BAABLAAECoEZAAIJAAgIDx0WMgCCAgAJAAgIDx0WMgCCAgAAAA==.Mijah:BAABLAAECoEVAAIVAAcITxBRTgCiAQAVAAcITxBRTgCiAQABLAAECggIEgAQAAAAAA==.Miraculix:BAABLAAFFIEJAAIPAAMIYxwhCgCYAAAPAAMIYxwhCgCYAAAAAA==.Mirtari:BAAALAADCgYIBwAAAA==.Mirtariann:BAAALAADCggIGQAAAA==.Mirtorrion:BAAALAADCgUIBgAAAA==.Mischoki:BAAALAAECgUIBQAAAA==.',Mo='Moherty:BAAALAADCgcICQAAAA==.Mojono:BAAALAADCggICAAAAA==.Monkkong:BAAALAAECggIBgAAAA==.Morgor:BAABLAAECoEpAAIRAAgIUyQEAQBZAwARAAgIUyQEAQBZAwAAAA==.Morpheùs:BAAALAADCggICQAAAA==.',Mu='Murtan:BAAALAAECgYIEQAAAA==.Muttimitkind:BAAALAAECgYIDwAAAA==.Muukun:BAAALAAECggICgAAAA==.',My='Mylandre:BAAALAAECgYIBgAAAA==.Mylie:BAAALAADCggICAABLAAECgYIDgAQAAAAAA==.',['Mî']='Mîaný:BAAALAAECgEIAQAAAA==.',['Mô']='Môndrael:BAACLAAFFIEFAAIZAAII/RLONAB3AAAZAAII/RLONAB3AAAsAAQKgRwAAhkACAhAH7kQAM0CABkACAhAH7kQAM0CAAAA.',['Mü']='Mürtary:BAAALAADCggIFAAAAA==.',Na='Narias:BAAALAADCgcICAAAAA==.Nawakmage:BAABLAAECoEVAAIHAAcImxSWWgDUAQAHAAcImxSWWgDUAQAAAA==.Nayelí:BAAALAADCgcIBwAAAA==.',Ne='Nefalia:BAAALAADCgYIBgABLAAECggIIAACAFwXAA==.Nervnich:BAAALAADCggICAAAAA==.Neumond:BAAALAADCgcIFQAAAA==.',Ni='Niméri:BAAALAAECgYIBgABLAAFFAMICQACAHwTAA==.Nitropenta:BAAALAAECgIIBAAAAA==.',Nk='Nkaa:BAABLAAECoEvAAMbAAYIliQ4FADaAQAbAAUIbyQ4FADaAQATAAYIdBktLACwAQAAAA==.',No='Noela:BAAALAADCgcIBwAAAA==.',Nu='Nullnull:BAAALAAECggIEAAAAA==.Nuánce:BAAALAADCggIDQAAAA==.',['Nä']='Näggi:BAAALAADCggICAABLAAECggIEgAQAAAAAA==.',Oi='Oilifant:BAAALAADCgQIBAAAAA==.',Ol='Olympiâ:BAAALAAECgUICgAAAA==.',On='Onigi:BAAALAADCgcIFgAAAA==.',Or='Orethoc:BAABLAAECoEUAAIKAAYIYR2vRwDtAQAKAAYIYR2vRwDtAQAAAA==.Oretoc:BAAALAAECgEIAQAAAA==.',Pa='Palatrix:BAABLAAECoEbAAIJAAcIxQ9DigCnAQAJAAcIxQ9DigCnAQAAAA==.Panoli:BAAALAAECgUICwAAAA==.Pascal:BAAALAAECggIBgAAAA==.Pascoolism:BAABLAAECoEaAAIgAAYISBqACgDcAQAgAAYISBqACgDcAQAAAA==.',Pe='Perus:BAACLAAFFIEJAAIDAAMIyBr2AgASAQADAAMIyBr2AgASAQAsAAQKgS0AAgMACAg6JfsBAGsDAAMACAg6JfsBAGsDAAAA.',Pi='Pins:BAAALAAECgIIAgAAAA==.Pixelchen:BAAALAAECgIIAgAAAA==.Pixia:BAAALAAECgEIAQAAAA==.',Pl='Plumsbär:BAABLAAECoEbAAIVAAgIqA7tQQDRAQAVAAgIqA7tQQDRAQAAAA==.',Pr='Priestariah:BAAALAADCgcIBwAAAA==.',Pu='Pumba:BAAALAAECgIIBAAAAA==.',['Pá']='Páblo:BAAALAADCgYIBgAAAA==.',Qe='Qeeth:BAAALAADCgUIBQAAAA==.',Qu='Quinney:BAAALAAECggICAABLAAECggIEgAQAAAAAA==.',Ra='Raell:BAAALAADCgYIBgAAAA==.Ragingsoul:BAAALAAECgMIBAAAAA==.Ragnon:BAAALAAECgYICgAAAA==.Rakuyo:BAAALAAECgYIBwAAAA==.Ranya:BAABLAAECoEYAAIGAAcI7Qo7SQBaAQAGAAcI7Qo7SQBaAQAAAA==.',Re='Restofurry:BAAALAAECgYICQABLAAECggIEAAQAAAAAA==.Retro:BAAALAADCggICAABLAAECggIDgAQAAAAAA==.',Ri='Risiko:BAAALAADCggIDwAAAA==.',Ru='Rudos:BAAALAAECgYIDAAAAA==.',['Rü']='Rüwel:BAAALAADCgYICAABLAAECgYICgAQAAAAAA==.',Sa='Saberchopf:BAABLAAECoEnAAIMAAgIVCNPAQA6AwAMAAgIVCNPAQA6AwAAAA==.Sailermoon:BAAALAAECgQIAgAAAA==.Sathil:BAABLAAECoEbAAIhAAgI/wcBDQB2AQAhAAgI/wcBDQB2AQAAAA==.Sawny:BAAALAAECggIEgAAAA==.',Sc='Scheryna:BAAALAAECgYICQAAAA==.Scherýn:BAAALAAECgUICQAAAA==.Schnippler:BAAALAADCggICAAAAA==.Schæfchën:BAABLAAECoEkAAIHAAgI8xgTOQBIAgAHAAgI8xgTOQBIAgAAAA==.Scortum:BAABLAAECoEUAAIDAAYIShEUOwBfAQADAAYIShEUOwBfAQAAAA==.',Se='Selijana:BAAALAAECggICAAAAA==.Seljana:BAAALAAECggICAAAAA==.Serinya:BAAALAAECggICAAAAA==.Serraki:BAAALAAECggIEAABLAAFFAMICQATAKcaAA==.Serénity:BAAALAADCggIEAABLAAECggIEAAQAAAAAA==.',Sh='Shamfire:BAABLAAECoEbAAIZAAYIQSMSKABOAgAZAAYIQSMSKABOAgAAAA==.Shaniv:BAABLAAECoExAAIOAAcIAR6vNgBCAgAOAAcIAR6vNgBCAgAAAA==.Shapeslift:BAAALAAECggIEwAAAA==.Shiiwa:BAAALAADCgEIAQAAAA==.Shinsei:BAACLAAFFIEOAAMEAAMIYhwSCQC5AAAEAAIIUh0SCQC5AAAFAAMIZhNqNACeAAAsAAQKgTcAAwUACAhpI7kqAKECAAUACAh8ILkqAKECAAQABAg/JI4gAJ4BAAAA.Shyniil:BAAALAAECggICQAAAA==.Shòkkx:BAAALAAECgYIDgABLAAECggIDwAQAAAAAA==.Shókkx:BAAALAAECggIDwAAAA==.',Sl='Sliftbolt:BAAALAAECgQIBAABLAAECggIEwAQAAAAAA==.',Sn='Sneakyshart:BAACLAAFFIEJAAITAAMIpxruBwAVAQATAAMIpxruBwAVAQAsAAQKgS0AAxMACAg6Jv0AAHYDABMACAg6Jv0AAHYDABsABAgQG+wlADUBAAAA.',Sp='Spirulinia:BAAALAAECgIIAgAAAA==.',St='Starrsheriff:BAAALAADCgMIBAAAAA==.',Su='Subrata:BAAALAADCggICAABLAAECgcIHgAiAJsgAQ==.',Sw='Swdmiss:BAAALAAECgYIBQAAAA==.Swordmastery:BAABLAAECoEMAAIFAAcIdRWDnQCNAQAFAAcIdRWDnQCNAQABLAAFFAUIDQATAOYXAA==.',Sy='Syaoran:BAAALAADCgcICQABLAAECgcIFAAKAIUNAA==.',['Sî']='Sînah:BAAALAAECggIEAAAAA==.Sîskaja:BAAALAAECgYIBgAAAA==.',['Só']='Sólstafir:BAAALAADCggICAAAAA==.',Ta='Taduros:BAAALAAFFAIIAgABLAAFFAMICQAVALgHAA==.Takingdown:BAACLAAFFIEFAAICAAIINwYFLACBAAACAAIINwYFLACBAAAsAAQKgSAAAwIABghpFSZWAFsBAAIABghpFSZWAFsBAB0AAQh5A8Q6ABgAAAAA.Talahon:BAABLAAECoEsAAIHAAgIqSEAIgCyAgAHAAgIqSEAIgCyAgAAAA==.Tanaoi:BAAALAADCgYIBgAAAA==.Tanya:BAEALAAECgcICwAAAA==.Tarifas:BAAALAADCgEIAQAAAA==.Taselol:BAACLAAFFIEHAAIcAAMIpBAuDgDoAAAcAAMIpBAuDgDoAAAsAAQKgSAAAxwACAgFIQMaAIYCABwABwg9IgMaAIYCAAIAAQjYAbaqACQAAAAA.',Te='Terdyy:BAAALAADCggICAAAAA==.Terosdk:BAAALAAECgYIDAABLAAFFAIIBAAQAAAAAA==.',Th='Thauriel:BAABLAAECoEqAAMjAAgI6hzgIgA8AgAjAAcIuh3gIgA8AgAOAAEIPRdRDwE9AAAAAA==.Thazdingo:BAAALAAECgQICQAAAA==.Thorger:BAAALAAECgYIEQAAAA==.Thuluuna:BAAALAAECggICAAAAA==.Thunderhôrn:BAABLAAECoEWAAIVAAYIVQ2fbQA5AQAVAAYIVQ2fbQA5AQAAAA==.Thunderx:BAAALAADCgcIBwAAAA==.Thémis:BAAALAADCgIIAgABLAADCggIEAAQAAAAAA==.',Ti='Tiiramisuu:BAACLAAFFIEHAAIZAAMIUgxwGQC7AAAZAAMIUgxwGQC7AAAsAAQKgSoAAhkACAgjFSNAAPYBABkACAgjFSNAAPYBAAAA.Tiiri:BAAALAAECgIIAgABLAAFFAMIBwAZAFIMAA==.Tisari:BAAALAAECgIIAgAAAA==.',To='Toyz:BAAALAAECgYIEQAAAA==.',Tr='Tranis:BAAALAAECgYIBgAAAA==.Treejin:BAAALAADCggICAAAAA==.Trhey:BAAALAAECgIIAgAAAA==.',Ts='Tsavong:BAABLAAECoEiAAMcAAgI3ByiFgChAgAcAAgI3ByiFgChAgACAAgIeA2fRQCaAQAAAA==.Tsukihi:BAAALAAECgIIAgAAAA==.',Tu='Tuulanî:BAAALAADCggIGAABLAAECggIHwALAEUcAA==.Tuz:BAAALAAECgMIBAAAAA==.',Ty='Tycrius:BAABLAAECoEdAAIaAAgIjyHuGwDaAgAaAAgIjyHuGwDaAgAAAA==.',Ue='Uerige:BAAALAADCgcIBwAAAA==.',Um='Umága:BAAALAAECgEIAQAAAA==.',Un='Unántástbár:BAAALAAECgIIBAAAAA==.',Ur='Urbàn:BAAALAADCgcIBwAAAA==.',Va='Valadrake:BAAALAAECgUIBwAAAA==.Valandu:BAAALAADCgcICQABLAAECgUIBwAQAAAAAA==.Valavulp:BAAALAADCgEIAQABLAAECgUIBwAQAAAAAA==.Valvier:BAAALAAECgYIBwAAAA==.Vanni:BAACLAAFFIEGAAIkAAIIGBw/BwChAAAkAAIIGBw/BwChAAAsAAQKgRoAAiQACAiTIwAGAO4CACQACAiTIwAGAO4CAAAA.',Ve='Veliora:BAAALAADCgYICwAAAA==.Verbanskaste:BAAALAAECggICAAAAA==.Versan:BAAALAADCgYIBgAAAA==.',Vi='Viratos:BAAALAAECgQIBAAAAA==.',Vo='Vogel:BAAALAAECgYICwAAAA==.Vonah:BAAALAAECgMIAwAAAA==.',Vr='Vrask:BAAALAADCgEIAQAAAA==.',Wa='Waldi:BAABLAAECoEdAAMeAAcIjBnOCgAAAgAeAAcIfRnOCgAAAgAGAAcI8A8OPwCIAQAAAA==.Wanev:BAABLAAECoEVAAIKAAYIOAnuhwAzAQAKAAYIOAnuhwAzAQAAAA==.',Xa='Xalatath:BAAALAAECgYIEQAAAA==.Xandôs:BAABLAAFFIEIAAIBAAUIXQ6rCAClAQABAAUIXQ6rCAClAQAAAA==.',Xe='Xenderamonki:BAAALAAECgQICAABLAAECggIEAAQAAAAAA==.',Xy='Xynoa:BAAALAADCgYIBgAAAA==.',Ye='Yeon:BAAALAAECgMIAwABLAAECgcIFAAKAIUNAA==.',Yo='Yogibär:BAABLAAECoEdAAIOAAYIqhsndQCUAQAOAAYIqhsndQCUAQAAAA==.Yortu:BAACLAAFFIEJAAIGAAMIPAsLDQDMAAAGAAMIPAsLDQDMAAAsAAQKgS0AAwYACAg2HugQAMMCAAYACAg2HugQAMMCABIAAQj9BLfDAB8AAAAA.',['Yé']='Yésterday:BAAALAAECgYICQAAAA==.',Za='Zalandotroll:BAAALAADCggICAABLAAECggIGwAGANoRAA==.Zalasia:BAACLAAFFIEIAAIIAAIIYyKHDADOAAAIAAIIYyKHDADOAAAsAAQKgR4AAwgACAgGIsMDABcDAAgACAgGIsMDABcDAAkABgjPGreuAGUBAAAA.Zanndana:BAABLAAECoEgAAICAAgIXBchKQAlAgACAAgIXBchKQAlAgAAAA==.',Ze='Zelya:BAAALAADCgcIBwAAAA==.',Zy='Zyri:BAACLAAFFIEGAAIFAAMI6BXJKgCsAAAFAAMI6BXJKgCsAAAsAAQKgQ4AAgUACAjuD2+wAG4BAAUACAjuD2+wAG4BAAEsAAUUBAgMAAcAgw0A.',['Zê']='Zêrklor:BAABLAAECoEeAAIiAAcImyAwCgCMAgAiAAcImyAwCgCMAgAAAA==.',['Âr']='Ârrôwsmíth:BAAALAADCgcICgAAAA==.',['În']='Întellectô:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end