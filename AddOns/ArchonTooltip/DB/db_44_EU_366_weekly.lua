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
 local lookup = {'Priest-Holy','Unknown-Unknown','Mage-Fire','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','DeathKnight-Blood','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Mage-Arcane','Warlock-Destruction','Paladin-Protection','Paladin-Retribution','Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Druid-Feral','Warrior-Fury','DemonHunter-Havoc','Warlock-Demonology','DemonHunter-Vengeance','Evoker-Preservation','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Frost','Paladin-Holy','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Hunter-Survival','DeathKnight-Unholy','Monk-Windwalker',}; local provider = {region='EU',realm='Eitrigg',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adalarià:BAABLAAECoEbAAIBAAcIEQ1oTwB0AQABAAcIEQ1oTwB0AQAAAA==.',Ae='Aegis:BAAALAAECgQICgABLAAECgYIDgACAAAAAA==.Aelnor:BAAALAADCgcIBwABLAAECgQIBgACAAAAAA==.',Ag='Agreûs:BAAALAADCggIEgAAAA==.Agriøs:BAAALAADCgcICAAAAA==.',Al='Alectinib:BAAALAAECgQIDQAAAA==.Aleocrast:BAAALAAECgUIEAAAAA==.Alexm:BAABLAAECoEWAAIDAAYIxAcLDQAlAQADAAYIxAcLDQAlAQAAAA==.Alitia:BAAALAADCgMIAwAAAA==.Almäh:BAACLAAFFIEWAAIEAAYIrBSIBgCGAQAEAAYIrBSIBgCGAQAsAAQKgSoAAwQACAhGIpwWAKcCAAQACAhGIpwWAKcCAAUABwiQHTgwACMCAAAA.Alzoran:BAABLAAECoEVAAIGAAYI6xBOPQBIAQAGAAYI6xBOPQBIAQAAAA==.Aléria:BAAALAAECgMIBwAAAA==.',An='Angalis:BAAALAAECgQIDgAAAA==.',Ar='Arima:BAAALAADCggICAAAAA==.Arimas:BAAALAAECgQIDAAAAA==.Arkathenzis:BAAALAADCggIDAAAAA==.Armablood:BAAALAAECgYIEQAAAA==.Arrok:BAAALAADCggIDgAAAA==.Arthias:BAABLAAECoElAAIHAAcIJRpMEgD2AQAHAAcIJRpMEgD2AQAAAA==.Arthür:BAAALAADCgcICgAAAA==.',As='Assala:BAAALAADCgcIBwAAAA==.Astâl:BAAALAADCgYIBgABLAAECgYIDgACAAAAAA==.Asuhna:BAAALAAECgMIAwAAAA==.',At='Atalea:BAABLAAECoEUAAIBAAYIMR7cLAASAgABAAYIMR7cLAASAgAAAA==.Atrelya:BAABLAAECoEbAAIIAAcI5SE6FgCLAgAIAAcI5SE6FgCLAgAAAA==.',Av='Avra:BAAALAADCgcIHAAAAA==.Avryl:BAAALAAECgYIBwAAAA==.',Az='Azral:BAAALAADCgEIAQAAAA==.Azumî:BAAALAADCgYIBAAAAA==.Azôg:BAAALAAECgIIAgAAAA==.',['Aé']='Aégis:BAAALAAECgYIDgAAAA==.',['Aë']='Aëpyx:BAAALAAECgcIEwAAAA==.',['Añ']='Añi:BAAALAAECgIIAgAAAA==.',['Aü']='Aürane:BAAALAADCggIEQAAAA==.',Ba='Badoy:BAAALAAECgYIEgAAAA==.Baeliggs:BAAALAAECgcICwAAAA==.Bahamumuth:BAAALAADCgMIAwABLAAECgcIBwACAAAAAA==.Bahamuth:BAAALAAECgcIBwAAAA==.Baiyta:BAABLAAECoEbAAIEAAgIZBW5SgDVAQAEAAgIZBW5SgDVAQAAAA==.Bakadash:BAAALAAECggIEwAAAA==.Balou:BAAALAAECgYIDgAAAA==.Baltazarette:BAAALAAECgQIBgAAAA==.Bananette:BAAALAAECgIIAgAAAA==.Basolipala:BAAALAADCggICAAAAA==.',Be='Beaucouteau:BAAALAADCgIIAgAAAA==.Beaumarteau:BAAALAADCgcIEQAAAA==.Belissima:BAAALAADCgUIBQAAAA==.Betaicks:BAAALAAECgUIBgAAAA==.Beäuregard:BAAALAADCgQIBAAAAA==.',Bi='Bigheart:BAAALAAECgQIBAAAAA==.Birnäm:BAAALAAECgIIAgAAAA==.Biscköotte:BAABLAAECoEdAAQJAAcI5hcaKQDEAQAJAAYIMhkaKQDEAQAKAAUIXg5EKAAhAQALAAEInQZOHAArAAAAAA==.Biînd:BAAALAAECggICwAAAA==.',Bl='Bllou:BAABLAAECoEWAAIMAAYIxwWqhADNAAAMAAYIxwWqhADNAAAAAA==.',Bo='Bobodet:BAABLAAECoEUAAINAAgI0RAEfAB3AQANAAgI0RAEfAB3AQAAAA==.Boigi:BAABLAAECoEVAAIOAAYIaQvwggBAAQAOAAYIaQvwggBAAQAAAA==.Bolg:BAAALAAECggICAAAAA==.Boniandclyde:BAAALAAECgQIBwAAAA==.Borîs:BAABLAAECoEYAAIEAAYIihcVXwCcAQAEAAYIihcVXwCcAQAAAA==.',Br='Brackcham:BAABLAAECoEcAAIEAAgI0h0lGwCNAgAEAAgI0h0lGwCNAgAAAA==.Brackevok:BAAALAADCggICAABLAAECggIHAAEANIdAA==.Brackhunt:BAAALAAECgYICQABLAAECggIHAAEANIdAA==.Brackis:BAAALAADCggICAABLAAECggIHAAEANIdAA==.Brackprêtre:BAAALAAECgYIDAABLAAECggIHAAEANIdAA==.Brôxigar:BAAALAADCgcIHgAAAA==.',Bu='Buffi:BAAALAAECgMIBwAAAA==.',Ca='Cajôu:BAABLAAECoEqAAIEAAgIQBMFUgC/AQAEAAgIQBMFUgC/AQAAAA==.Calcalou:BAACLAAFFIEHAAIPAAMIYx0CDQCKAAAPAAMIYx0CDQCKAAAsAAQKgRkAAw8ACAhcHjgKAK0CAA8ACAhcHjgKAK0CABAAAQhxAStRARAAAAAA.Calinea:BAAALAADCgUIAQAAAA==.Calvatius:BAAALAAECgcIDgAAAA==.Calymnos:BAAALAADCgcIBwAAAA==.Carleenne:BAAALAAECgUIEAAAAA==.Carmelita:BAAALAAECgQIBQAAAA==.Cartoon:BAAALAADCgcIBwAAAA==.Catzonegro:BAAALAAECgYIBgAAAA==.',Ce='Celsor:BAAALAAECgUIBQAAAA==.Centrifuge:BAAALAADCgUIBQAAAA==.Cesandra:BAAALAADCggICAAAAA==.',Ch='Chamalolaï:BAAALAAECgYIEQABLAAECgcIIgARAOQaAA==.Chamanamanah:BAAALAAECgYIEgABLAAECggIEwACAAAAAA==.Chamomille:BAAALAAECggICAAAAA==.Chlore:BAAALAADCgYIBwAAAA==.Chouchou:BAAALAADCgEIAQAAAA==.Choukrette:BAAALAADCggIFAABLAAECgcIEQACAAAAAA==.',Ci='Cinedelle:BAAALAAECgYIBwAAAA==.',Cl='Cliff:BAAALAAECgMIAwAAAA==.',Co='Coeos:BAACLAAFFIEYAAMSAAYICBuWBgC1AQASAAYILRmWBgC1AQATAAQIPRSRCQAZAQAsAAQKgSkAAxIACAiQJUELACcDABIACAgFJUELACcDABMACAiMIMAOAOACAAAA.Colte:BAAALAADCggICAAAAA==.Cooperoberts:BAAALAADCgYIBgAAAA==.Coprophage:BAAALAAECgIIAgABLAAFFAMIDQAUAEwhAA==.Corder:BAAALAADCgcIBwAAAA==.',Cr='Crapulitas:BAAALAADCggIDAAAAA==.Crapulitos:BAABLAAECoEVAAIVAAYI3RGRHwBuAQAVAAYI3RGRHwBuAQAAAA==.Crhome:BAAALAAECgMIAwAAAA==.Cropta:BAAALAADCgcIBwAAAA==.Crossby:BAAALAADCgQIBAAAAA==.Crowstorm:BAAALAAECgYIEwAAAA==.Crùsi:BAAALAADCgYICwAAAA==.',Cy='Cybe:BAAALAAECgUIBgAAAA==.Cybèlia:BAAALAAECgYICgAAAA==.',['Cé']='Céhunskandal:BAABLAAECoEWAAIWAAYIswdtiQAjAQAWAAYIswdtiQAjAQAAAA==.',['Cö']='Cörazon:BAAALAAECgYIDAAAAA==.',Da='Daante:BAAALAAECgcIEAAAAA==.Daddy:BAAALAADCggICAAAAA==.Daemonstorm:BAACLAAFFIEHAAIXAAMI0BIaKgCaAAAXAAMI0BIaKgCaAAAsAAQKgScAAhcACAiKH8McANYCABcACAiKH8McANYCAAAA.Daerron:BAAALAAECgQIBgAAAA==.Dardarph:BAAALAAECgMIBwAAAA==.Darkats:BAABLAAECoEWAAIYAAYIdBhjJwC5AQAYAAYIdBhjJwC5AQAAAA==.Darkblod:BAAALAADCgYIBgAAAA==.Darkmør:BAABLAAECoEdAAIHAAcIiBZTFwCvAQAHAAcIiBZTFwCvAQAAAA==.Darkrus:BAAALAADCgcIBwAAAA==.Darkwraith:BAAALAAECgQIDAAAAA==.Dastru:BAAALAADCggIEQAAAA==.',De='Deaktàrion:BAABLAAECoEdAAMZAAcI8hhbIgBoAQAXAAYI3RfcbgC8AQAZAAYI0BZbIgBoAQABLAAFFAMIDQAUAEwhAA==.Deepbloom:BAABLAAECoEWAAIIAAYIHQtCVwAgAQAIAAYIHQtCVwAgAQAAAA==.Deflora:BAACLAAFFIEKAAIBAAQIBQp5CwAhAQABAAQIBQp5CwAhAQAsAAQKgSoAAgEACAjAIX8KAAQDAAEACAjAIX8KAAQDAAAA.Dexforitas:BAABLAAECoEfAAINAAgIGxymJgCcAgANAAgIGxymJgCcAgAAAA==.',Di='Diaries:BAAALAADCggIDAAAAA==.Didormu:BAABLAAECoEYAAIaAAcIHhoWDgAfAgAaAAcIHhoWDgAfAgAAAA==.',Do='Donald:BAABLAAECoEYAAIUAAgIDRhcCABeAgAUAAgIDRhcCABeAgAAAA==.Dortar:BAACLAAFFIEaAAIRAAYI7xO1AADtAQARAAYI7xO1AADtAQAsAAQKgScAAhEACAgxJfsCAFcDABEACAgxJfsCAFcDAAAA.Doum:BAABLAAECoEVAAINAAYINBA8hwBZAQANAAYINBA8hwBZAQAAAA==.',Dr='Dractynay:BAAALAAFFAEIAQAAAA==.Dradoria:BAAALAAECgMIAwAAAA==.Dradoshadow:BAAALAADCgYIBgAAAA==.Draenosh:BAAALAADCggIEAAAAA==.Drakatrey:BAAALAADCggIDwAAAA==.Drakinchu:BAAALAADCgcICgABLAAECgcIFwAbAMwWAA==.Drakkär:BAAALAAECgYIDgAAAA==.Dravën:BAAALAAECggIBwAAAA==.Drift:BAAALAAECgYICAAAAA==.Drøødix:BAAALAADCgUIBQAAAA==.',['Dé']='Défonz:BAAALAADCgEIAQAAAA==.Démonelle:BAAALAAECgUIBQABLAAECggIEwACAAAAAA==.',['Dë']='Dëmonïak:BAAALAAECgYICQAAAA==.',Ed='Edorph:BAAALAADCgEIAQAAAA==.',El='Elaendhil:BAAALAADCgYIBgABLAAECggIGwAbAIgMAA==.Elfury:BAAALAAECgQIBgAAAA==.Elistra:BAAALAADCggICAAAAA==.Elohunt:BAAALAAECgYIEwAAAA==.Elphi:BAAALAAECggIDQAAAA==.Elrelia:BAAALAAECgQIDAAAAA==.Elyndraë:BAAALAAECgUICwAAAA==.Eléazar:BAAALAADCgEIAQAAAA==.',Em='Empalôx:BAAALAAECgMIBAAAAA==.',En='Enoä:BAAALAADCggIEAAAAA==.',Eo='Eoin:BAAALAAECgQIBgAAAA==.Eomen:BAABLAAECoEbAAIbAAgIiAzYOAC+AQAbAAgIiAzYOAC+AQAAAA==.',Er='Eranoth:BAABLAAECoEWAAMZAAcI1yP8BwC+AgAZAAcI1yP8BwC+AgAXAAIIiho18QCQAAABLAAECggIIAAWACYlAA==.Erigion:BAAALAADCgQICAAAAA==.',Es='Esrea:BAAALAAECgIIAQAAAA==.Estawn:BAAALAAECgQIDQAAAA==.',Et='Etërnäm:BAAALAAECgEIAQAAAA==.',Ev='Evospeed:BAAALAADCgYIBgAAAA==.',['Eï']='Eïlkas:BAABLAAECoEWAAIbAAYIvh1XLgD4AQAbAAYIvh1XLgD4AQAAAA==.',Fa='Farella:BAAALAADCggIGAAAAA==.Fatalys:BAAALAAECgQIBgAAAA==.Fatrog:BAACLAAFFIEJAAIKAAMI+xQcCwCjAAAKAAMI+xQcCwCjAAAsAAQKgSIAAgoACAiOHnAHALACAAoACAiOHnAHALACAAAA.',Fe='Felingel:BAAALAAECgUIBQAAAA==.Fellem:BAAALAADCgcIDgAAAA==.Feur:BAABLAAECoEVAAMKAAcIVBFqGgCXAQAKAAcIHhBqGgCXAQAJAAQIUBOZSQDzAAAAAA==.',Fi='Fileal:BAAALAADCggIFgAAAA==.Firien:BAAALAAECgYIDwAAAA==.',Fl='Flnc:BAAALAADCgEIAQAAAA==.Flors:BAAALAAECgYIDgAAAA==.',Fo='Forgelumière:BAAALAAECgEIAQAAAA==.Foubre:BAAALAAECgEIAQAAAA==.',Fr='Fredo:BAACLAAFFIEMAAIIAAQIsx5YBgBvAQAIAAQIsx5YBgBvAQAsAAQKgS0AAwgACAgLJj4CAHMDAAgACAgLJj4CAHMDAAwAAwh8F8iTAJ8AAAAA.',Ga='Gaelam:BAAALAAECgYICwAAAA==.Gaelfive:BAAALAAECggIDAAAAA==.Gaeliade:BAAALAAECggIDQAAAA==.Galaonar:BAAALAADCgYICAAAAA==.Galinette:BAAALAAECgYIDgAAAA==.Gamjatgaming:BAAALAADCggICAAAAA==.Ganondorfe:BAAALAADCggICAAAAA==.Gaviscon:BAAALAAFFAIICQAAAQ==.',Ge='Gegett:BAABLAAECoErAAIEAAgIHRYLPwD6AQAEAAgIHRYLPwD6AQAAAA==.',Gr='Graelt:BAAALAADCgIIAgAAAA==.Gregnêss:BAABLAAECoEgAAIWAAcIQxN5UQDFAQAWAAcIQxN5UQDFAQAAAA==.Grômdar:BAAALAADCgcIBwAAAA==.Grömsha:BAAALAAECgYIBgAAAA==.',Gu='Guldok:BAAALAADCggIEQAAAA==.Gunnar:BAAALAADCgYIBgAAAA==.',Gy='Gymkhana:BAABLAAECoEXAAMcAAYI2SG7DwBGAgAcAAYI2SG7DwBGAgAdAAYITB7qFwC+AQAAAA==.',['Gä']='Gäbriëll:BAAALAADCggIEwAAAA==.',Ha='Hanâe:BAAALAAECgMIAwAAAA==.Harloc:BAAALAAECgUIBgAAAA==.Harmonie:BAAALAAECgYIDQAAAA==.Haya:BAAALAAECgQICQAAAA==.',He='Heelia:BAAALAAECgcIBwAAAA==.Heihashi:BAAALAAECgYICwAAAA==.Helyoss:BAAALAAECgQIDQAAAA==.Hentaïs:BAAALAAECgEIAQAAAA==.',Hi='Highvory:BAEBLAAECoEaAAIeAAYIORZknACOAQAeAAYIORZknACOAQAAAA==.Hinami:BAAALAAECgcICAAAAA==.Hiroshige:BAAALAAECgEIAQABLAAECgcIFgAEAP8VAA==.',Ho='Hokamy:BAAALAADCgEIAQAAAA==.Holight:BAACLAAFFIEGAAIfAAMIsROxEQCfAAAfAAMIsROxEQCfAAAsAAQKgR4AAh8ACAgpHFYOAIICAB8ACAgpHFYOAIICAAAA.Homu:BAAALAAECgEIAQAAAA==.Hooli:BAAALAADCgIIAgAAAA==.Howbeesare:BAAALAADCgcIDQAAAA==.',Hu='Hunterox:BAAALAAECgMIAwAAAA==.',Hy='Hydra:BAAALAADCgYIBgAAAA==.Hydril:BAAALAADCgIIAgABLAAECgYIDgACAAAAAA==.Hygiea:BAABLAAECoEbAAIBAAgIPx7lEgC4AgABAAgIPx7lEgC4AgAAAA==.',['Hé']='Hérica:BAAALAADCgcIBwAAAA==.',['Hî']='Hînata:BAAALAADCggICAAAAA==.',['Hû']='Hûrïel:BAAALAADCgcIBwAAAA==.',Ic='Ichtar:BAAALAADCggICAAAAA==.',If='Ifreann:BAABLAAECoEVAAIYAAgIUx1NCQC2AgAYAAgIUx1NCQC2AgAAAA==.',Il='Illidanettë:BAACLAAFFIEFAAIXAAIImQw9RABZAAAXAAIImQw9RABZAAAsAAQKgRcAAhcACAhaGvUwAHMCABcACAhaGvUwAHMCAAAA.Ilâhir:BAAALAADCggICQAAAA==.',In='Ingwë:BAAALAADCgQIBAAAAA==.Injust:BAAALAAECgUIDwAAAA==.',It='Itikastrophe:BAACLAAFFIEHAAMgAAMIFxwZAgCRAAABAAMIFxxPIACYAAAgAAII2RQZAgCRAAAsAAQKgRoAAyAACAhwHxIHACECAAEACAhaHuYVAKECACAABwj1GRIHACECAAAA.Itikatchi:BAAALAAECgUIBQABLAAFFAMIBwAgABccAA==.',Iw='Iwan:BAAALAADCggICQAAAA==.',Iz='Izhandre:BAABLAAECoEXAAIRAAYIfRenMgCIAQARAAYIfRenMgCIAQAAAA==.',Ja='Jamoneur:BAACLAAFFIEZAAMhAAYIdiI/AQBTAgAhAAYIdiI/AQBTAgAiAAEIthokCABFAAAsAAQKgSUAAyEACAgaJu8BAGkDACEACAgaJu8BAGkDACIABAinIUwOABwBAAAA.',Je='Jepp:BAABLAAECoEgAAIWAAgIJiXlCgA2AwAWAAgIJiXlCgA2AwAAAA==.Jessicat:BAACLAAFFIEFAAIVAAMIEhvFAwATAQAVAAMIEhvFAwATAQAsAAQKgR0AAhUACAgjItMEAAUDABUACAgjItMEAAUDAAAA.Jessiluna:BAAALAAECgMIAwABLAAFFAMIBQAVABIbAA==.',Jh='Jhin:BAAALAADCgEIAQAAAA==.',Ji='Jinnette:BAAALAADCggIGgABLAAECgYIBgACAAAAAA==.',Ju='Justicelight:BAAALAAECgYIEQAAAA==.Justmétéor:BAAALAAECgYICQAAAA==.',Ka='Kamadark:BAAALAADCggICAAAAA==.Kandal:BAAALAADCgIIAgAAAA==.Karz:BAACLAAFFIEYAAIQAAYIbSEOAwAAAgAQAAYIbSEOAwAAAgAsAAQKgSYAAhAACAhGJnIGAGMDABAACAhGJnIGAGMDAAAA.Katsù:BAAALAAECgYIEQAAAA==.',Ke='Kek:BAACLAAFFIESAAIjAAYIDCQRAAA/AgAjAAYIDCQRAAA/AgAsAAQKgR4AAyMACAhkJkMAAIQDACMACAhkJkMAAIQDABMAAQjiIZGrADcAAAAA.Keliz:BAAALAAECgYIEgAAAA==.Kelthas:BAAALAADCgEIAQAAAA==.Kenpachi:BAAALAAECgIIAgAAAA==.Kensero:BAABLAAECoEsAAIkAAgImCNFBAARAwAkAAgImCNFBAARAwAAAA==.Keops:BAAALAADCgYIBgAAAA==.',Kh='Khâli:BAAALAAECgYIDQAAAA==.',Ki='Kily:BAAALAAECgEIAQAAAA==.Kinchuka:BAABLAAECoEXAAIbAAcIzBYINwDHAQAbAAcIzBYINwDHAQAAAA==.Kindor:BAAALAADCgMIAwAAAA==.Kisscools:BAABLAAECoEcAAIQAAcIPCAcKQCnAgAQAAcIPCAcKQCnAgAAAA==.',Kl='Klikor:BAABLAAECoEaAAIGAAgIHSDQCgDaAgAGAAgIHSDQCgDaAgAAAA==.Klikorio:BAAALAAECgYIBgABLAAECggIGgAGAB0gAA==.',Ko='Koddy:BAABLAAECoEaAAMUAAcI9RAXEAC+AQAUAAcI9RAXEAC+AQAEAAYIoxK1gwA/AQAAAA==.Kolossus:BAAALAADCggIEwAAAA==.Kouwock:BAAALAADCgYIDAAAAA==.Kowalsky:BAAALAAECgUIBQAAAA==.',Kr='Krawøw:BAAALAAECgYICwAAAA==.Kristhal:BAAALAAECgQICQAAAA==.Kromka:BAAALAADCggIHAAAAA==.Krøkrø:BAAALAAECgcIEgAAAA==.',Ks='Ksskouille:BAAALAAECgMIBAAAAA==.',Ku='Kumaavion:BAAALAAECgYIBwABLAAECggIGgAbAKggAA==.Kumasake:BAAALAAECgYICwABLAAECgcIJQAHACUaAA==.',Ky='Kyansâ:BAABLAAECoEWAAIQAAYIJQ1tvABMAQAQAAYIJQ1tvABMAQAAAA==.Kylyam:BAAALAADCgYICgAAAA==.Kyôko:BAABLAAECoEWAAIbAAYIVgkdVwAyAQAbAAYIVgkdVwAyAQAAAA==.',['Kä']='Kära:BAABLAAECoEeAAIIAAcIsBUfMQDNAQAIAAcIsBUfMQDNAQAAAA==.Kärz:BAAALAAECgYIBgAAAA==.',['Kï']='Kïpïk:BAAALAADCggICwAAAA==.',La='Lainai:BAAALAADCgUIBQAAAA==.Lamelonoth:BAAALAADCgYIBgAAAA==.Lapinator:BAABLAAECoEUAAMNAAcI9hT7VADlAQANAAcI9hT7VADlAQADAAEIwQQLIgAfAAAAAA==.Lapisugar:BAAALAAECgQICQABLAAECgcIFAANAPYUAA==.Laynïe:BAAALAAFFAIIAgABLAAFFAYIFQAIAP0dAA==.',Le='Legencia:BAAALAADCgQIBAAAAA==.Legencÿ:BAAALAADCgcIBwAAAA==.Lemelonoth:BAAALAAECggIEwAAAA==.Leviator:BAAALAAECggIDwAAAA==.',Li='Lienoa:BAAALAADCggICAAAAA==.Lightkira:BAAALAAECgIIAgAAAA==.',Lo='Londuzboub:BAAALAADCgEIAQAAAA==.Lorassor:BAAALAAECgQIBQAAAA==.Losc:BAAALAADCgMIAwAAAA==.Louidefunnel:BAAALAADCgcIDgAAAA==.',Lu='Luender:BAAALAADCgYICwAAAA==.Lunaria:BAAALAAECgYICQABLAAFFAMIBQAVABIbAA==.Lunelle:BAAALAADCggICAAAAA==.Lutila:BAABLAAECoEkAAIQAAcItyDLOABpAgAQAAcItyDLOABpAgAAAA==.',Ly='Lyaran:BAAALAAECgYIDQAAAA==.',['Lâ']='Lânaa:BAABLAAECoEgAAIMAAgICBQQMQDsAQAMAAgICBQQMQDsAQAAAA==.',['Lï']='Lïfÿa:BAAALAADCgYICwAAAA==.',['Lû']='Lûbite:BAAALAADCggICAAAAA==.',['Lü']='Lübu:BAABLAAECoEbAAIYAAgIHRsMDQCFAgAYAAgIHRsMDQCFAgAAAA==.Lücette:BAABLAAECoEqAAMSAAgIlSJpHwCqAgASAAgIlSJpHwCqAgATAAUIcRU2ZAAVAQAAAA==.',Ma='Magestral:BAABLAAECoEXAAIRAAYIBg8JPQBXAQARAAYIBg8JPQBXAQAAAA==.Magixevo:BAAALAAECggICAAAAA==.Magixo:BAAALAAECggICAAAAA==.Magixpala:BAABLAAECoEVAAIQAAYIzAk/zQAtAQAQAAYIzAk/zQAtAQAAAA==.Malivaï:BAAALAAECgQIBgAAAA==.Mandrakh:BAAALAADCgcIBwAAAA==.Mangemonheal:BAAALAAECgcIEAAAAA==.Massanthrax:BAABLAAECoEWAAIOAAYIqQs0gQBEAQAOAAYIqQs0gQBEAQAAAA==.Maédhros:BAABLAAECoEcAAIRAAcIOBtMGgAjAgARAAcIOBtMGgAjAgAAAA==.',Me='Meka:BAAALAAECgUIBQAAAA==.Mekasha:BAAALAADCggIGAAAAA==.Mennethil:BAAALAADCgMIAwAAAA==.Meo:BAABLAAECoEeAAIOAAgIpREuSgDkAQAOAAgIpREuSgDkAQAAAA==.',Mi='Minnain:BAAALAAECgMIAwAAAA==.Mirage:BAAALAADCgMIAwAAAA==.Mistrall:BAAALAADCgcIEgAAAA==.Mitsurii:BAAALAADCgMIAwAAAA==.',Mo='Mokha:BAAALAAECgMIAwAAAA==.Morania:BAAALAADCgMIAwAAAA==.Morgarat:BAAALAAECgEIAQABLAAECgcIHQABAPUXAA==.Morlaf:BAAALAAECgcIEQAAAA==.Mortibus:BAAALAAECgYIEgAAAA==.Mouah:BAAALAADCgIIAgAAAA==.',Mu='Mualph:BAABLAAECoEdAAIIAAcIXhflMADOAQAIAAcIXhflMADOAQAAAA==.Mutsuu:BAAALAAECgIIAgAAAA==.',['Mè']='Mèli:BAAALAAECgYIEQAAAA==.',['Mé']='Mélomage:BAAALAADCgcIBwABLAAECggIEwACAAAAAA==.Mélomoine:BAAALAADCgcIAwABLAAECggIEwACAAAAAA==.Méphala:BAAALAAECggIEwAAAA==.',Na='Narma:BAABLAAECoEXAAIUAAYIvBZOEQCqAQAUAAYIvBZOEQCqAQAAAA==.Naugrim:BAAALAADCggIIQAAAA==.Naxxars:BAAALAAECgYIEQAAAQ==.Naÿraa:BAAALAAECgcIDAAAAA==.',Ne='Nebula:BAAALAADCggIFAAAAA==.Nelarielle:BAAALAAECgYIBgAAAA==.Nemesys:BAAALAAECgYIBwAAAA==.Nephertiti:BAAALAADCggIDgAAAA==.Nerissa:BAAALAADCgEIAQAAAA==.Netzach:BAAALAADCgcIDQAAAA==.Neuil:BAAALAADCgcICgAAAA==.Neyldari:BAABLAAECoEdAAMBAAcI9RcOMQD8AQABAAcI9RcOMQD8AQAbAAcIZQlbTABiAQAAAA==.',Ni='Niall:BAAALAADCggICQAAAA==.Ninjini:BAAALAAECgcIEQAAAA==.Ninjutsu:BAAALAADCgcIBwAAAA==.Niwar:BAAALAAECgIIAQAAAA==.',No='Noahdh:BAABLAAECoEWAAIXAAcI4BVfVwD0AQAXAAcI4BVfVwD0AQAAAA==.Nothil:BAAALAADCgYIBgAAAA==.',Nu='Nutælâ:BAAALAADCgMIBQAAAA==.',Nx='Nxia:BAAALAADCggICQAAAA==.',Ny='Nyouch:BAAALAADCgcIBwAAAA==.',['Nø']='Nøxxmøre:BAAALAAECgcIDQAAAA==.',Oi='Oignion:BAAALAAECgEIAQAAAA==.',Ok='Oklaf:BAAALAADCgQIBAABLAAECgcIJAAQALcgAA==.',On='Onidark:BAABLAAECoEZAAIkAAgIfQ/wFwDnAQAkAAgIfQ/wFwDnAQAAAA==.',Oo='Ooga:BAAALAADCgMIBQAAAA==.',Os='Oskur:BAAALAAECgQIDQAAAA==.',Ou='Ouftih:BAABLAAECoEcAAIBAAgIFwWRYgAvAQABAAgIFwWRYgAvAQAAAA==.',Ox='Oxye:BAABLAAECoE1AAIDAAgIPR54AgCvAgADAAgIPR54AgCvAgAAAA==.Oxymore:BAAALAAECgYIEQAAAA==.',Oz='Ozàs:BAAALAAECgUIBQAAAA==.',Pa='Pakerett:BAAALAADCggICAABLAAECgUIEAACAAAAAA==.Paladinas:BAABLAAECoEoAAIQAAcIzhsMVwARAgAQAAcIzhsMVwARAgAAAA==.Palady:BAAALAAECggIEQAAAA==.Palael:BAAALAADCggICAAAAA==.Palaga:BAAALAAECgUIBwABLAAFFAIIBQAXAJkMAA==.Palapilou:BAABLAAECoEWAAIPAAYIdyFDEgBAAgAPAAYIdyFDEgBAAgAAAA==.Palaspeed:BAAALAAECgYIDwAAAA==.Pandaerion:BAAALAAECgUIBwABLAAFFAMIDQAUAEwhAA==.Pandaspeed:BAAALAAECgIIAgAAAA==.Patrøletime:BAAALAADCgUIBQAAAA==.',Pe='Peket:BAAALAAECgIIAgAAAA==.Pelford:BAAALAAECgIIAgAAAA==.Pelzine:BAABLAAECoEeAAIlAAgIySL5BgAOAwAlAAgIySL5BgAOAwAAAA==.Pendulum:BAAALAADCgQIBgAAAA==.Peny:BAAALAADCggICQAAAA==.Petitbou:BAAALAAECgUIBQAAAA==.',Ph='Phantøm:BAAALAADCggIEgAAAA==.',Pl='Ploukine:BAAALAADCgcIEwAAAA==.',Po='Polterprïest:BAAALAAECgEIAQABLAAECgYICgACAAAAAA==.',Pr='Prat:BAAALAADCgcICAABLAAECgcIGgAFABoeAA==.Pretasus:BAAALAADCgcIDAAAAA==.Prouty:BAABLAAECoEaAAIFAAcIGh5jLwAoAgAFAAcIGh5jLwAoAgAAAA==.Prïma:BAACLAAFFIEWAAIBAAYI7hRMBgCcAQABAAYI7hRMBgCcAQAsAAQKgSkAAwEACAh1HTgaAIMCAAEACAh1HTgaAIMCABsABwjPFQUyAOMBAAAA.',Ps='Psiichokille:BAABLAAECoEVAAMWAAYIixXOXgCdAQAWAAYIhBXOXgCdAQAGAAUIQA6/UADuAAAAAA==.',['Pâ']='Pâmelâ:BAAALAADCgEIAQAAAA==.',['Pø']='Pøupette:BAACLAAFFIEKAAIEAAQImxkFCABdAQAEAAQImxkFCABdAQAsAAQKgSIAAwQACAg9JL0EADUDAAQACAg9JL0EADUDAAUAAwgWGgAAAAAAAAAA.',['Pù']='Pùnîsher:BAAALAAECgMIBQAAAA==.',Ra='Radhruin:BAAALAADCggIEAAAAA==.Raelya:BAAALAAECgYIDgAAAA==.Rafalmistral:BAAALAAECgYIEAAAAA==.Ragdoll:BAABLAAECoEcAAIZAAcI1hGxIAB3AQAZAAcI1hGxIAB3AQAAAA==.Ragior:BAAALAADCggIDgAAAA==.Ragnarøs:BAAALAAECggICQAAAA==.Rakib:BAAALAADCggICAABLAAECggIHAAEANIdAA==.Raphatytan:BAAALAAECgYIBwAAAA==.Ratüs:BAAALAADCgMIAwAAAA==.Rayton:BAAALAAECgMIAwAAAA==.',Re='Rebelöotte:BAAALAADCgYICQABLAAECgcIHQAJAOYXAA==.Rehn:BAABLAAECoEZAAIXAAgIrRu2MgBsAgAXAAgIrRu2MgBsAgAAAA==.Rektarion:BAAALAAFFAIIAgABLAAFFAMIDQAUAEwhAA==.',Rh='Rhast:BAABLAAECoEZAAIXAAcIrxzIPgA+AgAXAAcIrxzIPgA+AgAAAA==.',Ro='Rockhette:BAAALAADCggICQAAAA==.Rommy:BAAALAAECgQIBgAAAA==.Rotideboeuf:BAAALAAECgcIEwAAAA==.',['Ré']='Rénalath:BAAALAAECgUIBQAAAA==.',Sa='San:BAAALAAECgYIDQAAAA==.Sanhosuké:BAAALAAECgUIDgAAAA==.Sanvoix:BAAALAAECgYIEQAAAA==.Saucedio:BAABLAAECoEYAAITAAgIeSLWCAAXAwATAAgIeSLWCAAXAwABLAAECggIIAAWACYlAA==.Saïne:BAAALAAECgEIAgABLAAECgQIDAACAAAAAA==.',Sc='Scavenger:BAAALAADCggIEAABLAAECgcIJQAHACUaAA==.',Se='Seeker:BAAALAADCgcIDQAAAA==.Senturus:BAAALAAECgUICgAAAA==.',Sh='Shadowlight:BAAALAADCgUIBgAAAA==.Shagma:BAAALAAECggIAQAAAA==.Shalias:BAAALAADCgMIAwAAAA==.Shamaëll:BAAALAADCgYIBgAAAA==.Shana:BAAALAADCggIEAAAAA==.Sharthas:BAAALAADCgcIBwAAAA==.Sheila:BAABLAAECoEcAAQdAAYIziQVDAByAgAdAAYIwyQVDAByAgAcAAYIPh31FAD8AQAlAAYIlBy1NAA3AQAAAA==.Shimura:BAABLAAECoEcAAIUAAcIsQ+XEgCWAQAUAAcIsQ+XEgCWAQAAAA==.Sht:BAAALAAECgYIBgAAAA==.Shãdow:BAAALAADCgQIBQAAAA==.',Si='Siobhan:BAAALAAECgQIBgAAAA==.',Sk='Skank:BAABLAAECoEfAAIRAAgIhh/8CADvAgARAAgIhh/8CADvAgAAAA==.',Sm='Smîrnøff:BAAALAAECgMIAwAAAA==.',So='Soap:BAAALAAECgIIAgAAAA==.Sorme:BAAALAADCggIDwAAAA==.',Sp='Speedmäster:BAAALAAECgYICgAAAA==.',St='Stronghold:BAAALAAECgQICgAAAA==.Stéarine:BAAALAAECgYIDQAAAA==.Størmrage:BAAALAADCgUIBQAAAA==.',Su='Sunjia:BAAALAADCgYIBwAAAA==.',Sy='Syléçaø:BAAALAAECgcIBwAAAA==.',['Sé']='Séréphine:BAAALAADCgMIAwABLAAECgcIDgACAAAAAA==.Séverine:BAAALAAECgYIBgAAAA==.',Ta='Tagy:BAAALAADCggIBgABLAAECgYIDgACAAAAAA==.Tagyrra:BAAALAAECgYIDgAAAA==.Takkar:BAAALAADCgUIBQAAAA==.Talthara:BAAALAAECgEIAQAAAA==.Tarocks:BAAALAAECgcIBwAAAA==.Tarro:BAACLAAFFIEZAAMFAAYInxuQBQDkAQAFAAUIlR+QBQDkAQAEAAEIzBKBTQBIAAAsAAQKgSYAAgUACAi4JVUFAFwDAAUACAi4JVUFAFwDAAAA.Taumah:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.',Te='Teepo:BAAALAADCggICAAAAA==.Teyi:BAAALAADCggICAAAAA==.',Th='Thaelynna:BAAALAADCgcIDQAAAA==.Thanatøs:BAAALAADCgcIDQAAAA==.Tharÿa:BAAALAAECgUICgAAAA==.Theonora:BAAALAAECgcIEAAAAA==.Thomas:BAACLAAFFIEHAAMkAAII7yRJBwDMAAAkAAII7yRJBwDMAAAeAAEItgydagBGAAAsAAQKgSMAAyQACAjMIXADACgDACQACAjMIXADACgDAB4ABwg4HKVxAN4BAAAA.Thompson:BAAALAAECgMIBAAAAA==.Thorgir:BAAALAADCggIFAAAAA==.Thornium:BAAALAADCgQIAgAAAA==.Thydearth:BAABLAAECoEVAAIIAAYIrBckOgCgAQAIAAYIrBckOgCgAQAAAA==.Théos:BAAALAADCgQIBAAAAA==.Thîef:BAAALAAECgYICgAAAA==.',Ti='Tibgnd:BAAALAAECgMICAAAAA==.Tigou:BAAALAADCgYIBgAAAA==.Tinúviel:BAAALAADCgUIBQAAAA==.',To='Tochô:BAAALAAECgcICAAAAA==.Tomah:BAAALAAECgMIBAAAAA==.Tontonbil:BAAALAAECgMIBQAAAA==.Tonyup:BAAALAADCgEIAQAAAA==.Toulipan:BAAALAADCgYIBgAAAA==.',Tr='Traïnos:BAABLAAECoEWAAIXAAcIdB1IOwBKAgAXAAcIdB1IOwBKAgAAAA==.Trichlieu:BAAALAAECgMIAwABLAAFFAIICQACAAAAAQ==.',Ts='Tsûnadé:BAAALAAECgMIBQAAAA==.',['Tô']='Tôsu:BAAALAAECgcICQAAAA==.',['Tÿ']='Tÿrïon:BAAALAADCgcICwAAAA==.',Uk='Ukkonen:BAAALAADCgcIBwAAAA==.',Ul='Ulhysse:BAAALAAECgMIAwAAAA==.',Ur='Uriel:BAAALAADCggIFgAAAA==.',Va='Valanka:BAAALAAECgcIDQAAAA==.Vanion:BAAALAAECggICwAAAA==.',Ve='Vexhalia:BAABLAAECoEYAAMLAAcIghrZBQA+AgALAAcIghrZBQA+AgAJAAQIoAxJTQDWAAAAAA==.',Vi='Victàrion:BAACLAAFFIENAAIUAAMITCEWBACtAAAUAAMITCEWBACtAAAsAAQKgTQAAxQACAh3I44DAOwCABQACAgkI44DAOwCAAUABgipHSs3AAECAAAA.Videoeuf:BAAALAADCgYIBgAAAA==.Vilfendrer:BAABLAAECoEiAAMNAAgImyHiEwD9AgANAAgIhSHiEwD9AgARAAEI0yGlcABjAAAAAA==.Vinyato:BAAALAAECgEIAgAAAA==.Violinne:BAAALAAECgQICwAAAA==.Virilia:BAAALAAECgYIEgAAAA==.',Vo='Voclya:BAAALAAECgcIBwAAAA==.Vogador:BAAALAAECgYIDAAAAA==.Volkam:BAACLAAFFIEIAAIeAAIIdxw5KwCrAAAeAAIIdxw5KwCrAAAsAAQKgSsAAh4ABwgbJRohAMsCAB4ABwgbJRohAMsCAAAA.',Wa='Walanardine:BAAALAAECgcIEwABLAAFFAMICQAKAPsUAA==.Warox:BAAALAADCgcIBwAAAA==.Warzzazate:BAAALAAECgYIEgAAAA==.Wazyi:BAAALAADCgcIDQAAAA==.',Wi='Wildstorm:BAAALAAECgIIBAAAAA==.Willowy:BAAALAAECgYIAQAAAA==.',Wy='Wynnie:BAAALAAECgUICAAAAA==.',Xa='Xakor:BAAALAADCggIDQAAAA==.',Ya='Yaeshann:BAAALAAECgUIDAABLAAECgUIEAACAAAAAA==.Yashak:BAABLAAECoEiAAIEAAYI3hDZiAA0AQAEAAYI3hDZiAA0AQAAAA==.Yassuke:BAAALAADCggICAAAAA==.Yavanah:BAAALAADCgQIBAAAAA==.',Yn='Ynkasable:BAAALAAECgcIEwAAAA==.',Yq='Yquefue:BAAALAAECgcICgAAAA==.',Yu='Yumekui:BAAALAAECgYIBwAAAA==.',Yy='Yyohan:BAACLAAFFIEFAAIfAAIIQw2UFwCLAAAfAAIIQw2UFwCLAAAsAAQKgScAAh8ACAgdF0sTAE8CAB8ACAgdF0sTAE8CAAAA.',Za='Zarein:BAAALAADCgEIAQAAAA==.Zarokk:BAAALAADCggIEAAAAA==.',Ze='Zerstörer:BAAALAADCgcIBwAAAA==.Zeux:BAAALAADCggICAAAAA==.',Zo='Zoukini:BAAALAADCgcIBwAAAA==.Zozio:BAAALAAECgIIAQAAAA==.',Zy='Zyrad:BAABLAAECoEpAAIdAAgImB05CQCsAgAdAAgImB05CQCsAgAAAA==.',['Zé']='Zétheus:BAABLAAECoEUAAISAAYIFwP07QCGAAASAAYIFwP07QCGAAAAAA==.',['Ær']='Ærthemys:BAAALAAECgUIBgAAAA==.',['Ép']='Épectase:BAAALAADCggIBwAAAA==.Épectøz:BAAALAAECgUICwAAAA==.',['Év']='Évanescence:BAAALAADCgYIBQAAAA==.',['Îl']='Îlmarë:BAABLAAECoEaAAIEAAgInhWZQgDuAQAEAAgInhWZQgDuAQAAAA==.',['Ïl']='Ïllyanä:BAACLAAFFIEJAAIaAAMIMgn7CQDGAAAaAAMIMgn7CQDGAAAsAAQKgSUAAhoACAjKGxcMAEUCABoACAjKGxcMAEUCAAAA.',['Ðe']='Ðemønø:BAABLAAECoEWAAIYAAYIrAyjQQBFAQAYAAYIrAyjQQBFAQAAAA==.',['Öl']='Ölhaf:BAAALAAECgYICQAAAA==.',['Ør']='Ørriøn:BAABLAAECoEbAAIRAAcIoxheJgDNAQARAAcIoxheJgDNAQAAAA==.',['Øs']='Øsmøze:BAAALAADCgcICAAAAA==.',['ßë']='ßëlla:BAAALAAECgYIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end