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
 local lookup = {'Unknown-Unknown','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','DemonHunter-Havoc','Druid-Restoration','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Warrior-Protection','Warrior-Fury','Priest-Holy','Priest-Shadow','Warlock-Affliction','Hunter-Marksmanship','Paladin-Retribution','Druid-Balance','Evoker-Devastation','Druid-Guardian','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Shaman-Enhancement','Paladin-Protection','Hunter-BeastMastery','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Evoker-Preservation','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','DeathKnight-Unholy','Mage-Fire','Rogue-Outlaw',}; local provider = {region='EU',realm='KultderVerdammten',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aabaddon:BAAALAADCgYIBgABLAAECgYIEgABAAAAAA==.',Ad='Adeltraud:BAAALAAECgYIBgABLAAECgYIBgABAAAAAA==.Adradia:BAAALAAECgYIBgAAAA==.Adratea:BAAALAAECgEIAQAAAA==.',Ag='Agathon:BAAALAAECgIIAQABLAAECggIDgABAAAAAA==.Agrajag:BAAALAAECgYIBgABLAAECggIJAACAPwdAA==.',Ak='Akariel:BAAALAADCgcIDgAAAA==.Akári:BAAALAADCgYIBgAAAA==.',Al='Alaraa:BAAALAADCgEIAQAAAA==.Aleanâ:BAAALAADCgQIBAAAAA==.Alexantria:BAABLAAECoEcAAMDAAcI5BhSWAC0AQADAAcI8BJSWAC0AQAEAAYIeRdfOQBmAQAAAA==.Alfrothul:BAAALAAECgIIAwAAAA==.Allenor:BAAALAADCgEIAQAAAA==.Almî:BAAALAAECgYIDAAAAA==.Alysandra:BAAALAADCggIDAAAAA==.',Am='Amduscias:BAAALAADCgUICQAAAA==.',An='Andoki:BAABLAAECoEeAAIFAAcIthXzZQDQAQAFAAcIthXzZQDQAQAAAA==.Anilari:BAAALAAECgYIDwAAAA==.Anjanath:BAAALAAECgIIAgAAAA==.Anjàly:BAAALAAECgQIBAAAAA==.Anorielle:BAAALAADCggICwAAAA==.Anschan:BAAALAAECgcIBwAAAA==.Anthar:BAAALAADCgQIBAAAAA==.',Aq='Aquacyrex:BAAALAAECgYICwAAAA==.',Ar='Archowa:BAAALAADCggIEwAAAA==.Aristophat:BAAALAAECgYIBgAAAA==.Arubar:BAAALAAECgYICwAAAA==.',As='Ashtaka:BAABLAAECoEhAAIGAAYI5CIwIQA+AgAGAAYI5CIwIQA+AgAAAA==.Aswelden:BAABLAAECoEfAAIHAAcIXAvvJgA4AQAHAAcIXAvvJgA4AQAAAA==.Asøk:BAAALAAECgMIBAAAAA==.',At='Athrian:BAACLAAFFIERAAIIAAUIGhY8BACXAQAIAAUIGhY8BACXAQAsAAQKgSsAAggACAjPI2EEAB0DAAgACAjPI2EEAB0DAAAA.',Au='Aurin:BAAALAADCggIDwAAAA==.',Ay='Ayà:BAACLAAFFIEGAAIJAAIIMA60FACVAAAJAAIIMA60FACVAAAsAAQKgSgAAgkACAgZFUcbAAgCAAkACAgZFUcbAAgCAAAA.',Az='Azoc:BAAALAAECgQIBAAAAA==.',Ba='Backlit:BAAALAAECgYIEQAAAA==.Baelari:BAABLAAECoEhAAMKAAgIcxjdIAD2AQAKAAcITBvdIAD2AQALAAEIiQRY3gAQAAAAAA==.Baella:BAABLAAECoEkAAMMAAgIbx80GACRAgAMAAcI+SA0GACRAgANAAgISx3cGQCHAgAAAA==.Bahamuht:BAABLAAECoEdAAQOAAYIoxgXHQDtAAADAAUINReZdwBcAQAOAAMIYhkXHQDtAAAEAAQIMhcvYgC3AAAAAA==.Baratoss:BAAALAADCggIHQAAAA==.Barlogo:BAAALAAECgYIDwAAAA==.Batziwal:BAAALAAECgMIAwAAAA==.',Be='Bendagar:BAAALAADCgcIEgAAAA==.Benjihunt:BAABLAAECoEiAAIPAAYINB+CMgDdAQAPAAYINB+CMgDdAQABLAAFFAUIEgALAAgOAA==.Benjilock:BAAALAADCgQIBAABLAAFFAUIEgALAAgOAA==.Benjipala:BAABLAAECoEZAAIQAAcIDhxlQwBHAgAQAAcIDhxlQwBHAgABLAAFFAUIEgALAAgOAA==.Benjiwarri:BAACLAAFFIESAAILAAUICA4TCQCXAQALAAUICA4TCQCXAQAsAAQKgTEAAgsACAjmIbQTAPYCAAsACAjmIbQTAPYCAAAA.Berzerkuss:BAAALAAECgMIAwAAAA==.',Bl='Blues:BAAALAADCgQIBAAAAA==.Blutsturm:BAAALAAECgMIBgAAAA==.',Bo='Boindîl:BAAALAAECgIIAgAAAA==.Borold:BAACLAAFFIEGAAIDAAIIXRALMACSAAADAAIIXRALMACSAAAsAAQKgR4AAgMACAjtGbIxAEkCAAMACAjtGbIxAEkCAAAA.Bountzi:BAAALAADCggICAABLAAECggIAQABAAAAAA==.',Br='Brucehealee:BAAALAAECgYIDAAAAA==.',['Bä']='Bärrtram:BAAALAADCgEIAQAAAA==.',['Bô']='Bôrim:BAAALAADCgcIBwAAAA==.',Ca='Calani:BAAALAAECgYIBgAAAA==.Calanii:BAAALAAECgYIBAAAAA==.Calenne:BAAALAADCggICAAAAA==.Camîlla:BAABLAAECoEaAAIQAAYIbAWO5wD0AAAQAAYIbAWO5wD0AAAAAA==.Carel:BAABLAAECoEWAAIEAAgIyxuVDACLAgAEAAgIyxuVDACLAgAAAA==.Cascal:BAAALAADCgMIAwAAAA==.Cattleyà:BAAALAADCgQIBAAAAA==.',Ce='Ceeroma:BAAALAAECgYICwAAAA==.Celaira:BAAALAAECgUIBQAAAA==.',Ch='Chacarron:BAAALAAECgYIBgABLAAECggIJAACAPwdAA==.Chanceux:BAAALAADCgYIBgAAAA==.Chipendale:BAAALAAECgYICAAAAA==.Chippiee:BAAALAAECgUIDgAAAA==.Chogar:BAAALAAECggIEwAAAA==.Chosayo:BAAALAADCgcIDwAAAA==.',Cl='Cleoras:BAABLAAECoEkAAIGAAgIXh/WDADXAgAGAAgIXh/WDADXAgAAAA==.',Co='Corvex:BAAALAADCgcIBwAAAA==.Coryandr:BAAALAADCggIDgAAAA==.Cowwow:BAAALAAECggICAAAAA==.',Cr='Crowley:BAAALAAECgYIDAAAAA==.Crxzydk:BAAALAAECgYIDwAAAA==.',['Có']='Cóker:BAABLAAECoEdAAMGAAgI+Bx9IgA3AgAGAAcIlht9IgA3AgARAAcIDRc0PgCMAQAAAA==.',Da='Dabidoo:BAAALAAECgYIDwAAAA==.Dalrak:BAAALAAECgYIDgAAAA==.Danuris:BAAALAADCggIFwAAAA==.Darkchylde:BAAALAADCgMIAwAAAA==.Darliko:BAAALAADCgIIAgAAAA==.Daronil:BAABLAAECoEtAAMDAAgIwBv7IQCdAgADAAgIwBv7IQCdAgAEAAgIVhTiGwD+AQAAAA==.Darragh:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Dateho:BAAALAADCgIIAgAAAA==.',De='Defandér:BAAALAAECggICAAAAA==.Deliyah:BAAALAAECgYIEAAAAA==.Demala:BAAALAAECgQIBAAAAA==.Demistraza:BAABLAAECoEVAAISAAgIfw4HJQDUAQASAAgIfw4HJQDUAQAAAA==.Demonsadi:BAAALAAECgMICAAAAA==.Demonyo:BAAALAAECgcIBwAAAA==.Denji:BAAALAADCgQIBwAAAA==.Dersonne:BAAALAADCggIFAAAAA==.Deucalion:BAAALAADCgcIBwAAAA==.Devakí:BAAALAADCggIBwAAAA==.Devilon:BAAALAAECgYIDAAAAA==.Devius:BAABLAAECoEeAAMRAAYIZhy1LwDUAQARAAYIZhy1LwDUAQATAAIIUBNuJgBwAAAAAA==.',Di='Dilari:BAABLAAECoEWAAIRAAcIpha0LgDaAQARAAcIpha0LgDaAQAAAA==.Dilaro:BAAALAAECgYIEwABLAAECgcIFgARAKYWAA==.',Do='Dogak:BAAALAADCggIDAAAAA==.Dorgrin:BAAALAADCggIEgAAAA==.',Dr='Dracis:BAAALAAECggICAAAAA==.Dracthyra:BAAALAADCggIFAAAAA==.Draggow:BAACLAAFFIEPAAMSAAUIJSYpAgAcAgASAAUIJSYpAgAcAgAUAAEIVh9KBwBVAAAsAAQKgTMAAxIACAi0JhoDAFUDABIACAi0JhoDAFUDABQACAhaJOgAADYDAAAA.Drogos:BAAALAADCgQIBAABLAAECgYIDwABAAAAAA==.Druideheinz:BAAALAADCgcIBwAAAA==.Drôll:BAABLAAECoEdAAIKAAcIQwz/RQAeAQAKAAcIQwz/RQAeAQAAAA==.Drüíd:BAAALAAECgMIAwAAAA==.',Ec='Ecylar:BAAALAAECggICAAAAA==.',Ed='Edichán:BAAALAAECgMICQAAAA==.',Eh='Ehmi:BAACLAAFFIEPAAMVAAUIlBNFBQBTAQAVAAQInRRFBQBTAQAWAAQIIQmQCADIAAAsAAQKgTMAAxUACAhaI10FAB4DABUACAhxIl0FAB4DABYACAjZHZ4PABcCAAAA.',El='Elixiu:BAABLAAECoEaAAIXAAYIMxgSMACWAQAXAAYIMxgSMACWAQAAAA==.Elkje:BAAALAADCggIEwABLAAECgYIBgABAAAAAA==.Eltharon:BAABLAAECoEWAAIJAAYIBBOMNgBYAQAJAAYIBBOMNgBYAQAAAA==.Elunasil:BAAALAADCgEIAQABLAAECgcIBwABAAAAAA==.',Em='Emol:BAAALAAECgYIBwAAAA==.',En='Enno:BAACLAAFFIEGAAITAAIInhGtBAB5AAATAAIInhGtBAB5AAAsAAQKgSEAAhMACAhwHKsFAIcCABMACAhwHKsFAIcCAAAA.Envi:BAABLAAECoEZAAIDAAgImRUTPQAXAgADAAgImRUTPQAXAgAAAA==.',Er='Eratora:BAAALAADCgYIBgAAAA==.Erinnya:BAAALAADCggIFAAAAA==.',Ex='Exakun:BAAALAADCgUIBQAAAA==.',Ey='Eylo:BAAALAAECgEIAQABLAAFFAUIDwAVAJQTAA==.',Fe='Feez:BAAALAAECgUICwAAAA==.Felicea:BAAALAAECgYIEAAAAA==.Fenja:BAAALAAECgcIDgAAAA==.Fenriel:BAAALAADCgEIAQAAAA==.Feuil:BAACLAAFFIEQAAMMAAUIfyOHAgAOAgAMAAUIfyOHAgAOAgANAAEIFRoAAAAAAAAsAAQKgTMAAw0ACAhYJX0DAGIDAA0ACAhYJX0DAGIDAAwABwiDHmErABkCAAAA.',Fh='Fhel:BAAALAAECgYIDAAAAA==.',Fi='Fighjo:BAABLAAECoEeAAIYAAcIOhKFDwDJAQAYAAcIOhKFDwDJAQAAAA==.Filix:BAAALAAECgYIDAAAAA==.Fishbonez:BAAALAAECgcIEgAAAA==.Fixfoxi:BAAALAAECggICAAAAA==.',Fl='Florin:BAACLAAFFIEPAAIMAAUIiRBvBwCBAQAMAAUIiRBvBwCBAQAsAAQKgTIAAgwACAhPH6oZAIYCAAwACAhPH6oZAIYCAAAA.',Fr='Franki:BAAALAAECgYIBgAAAA==.Frànbubble:BAABLAAECoEYAAIZAAcIXCWuBgD2AgAZAAcIXCWuBgD2AgABLAAECggIDwABAAAAAA==.Frànmooscle:BAAALAAECgYIDQAAAA==.Frànpoteto:BAAALAAECggIDwAAAA==.Frêssh:BAABLAAECoEeAAIVAAgI3h62CQDjAgAVAAgI3h62CQDjAgAAAA==.',Fu='Funfool:BAABLAAECoEZAAIRAAcInAQuYgDuAAARAAcInAQuYgDuAAAAAA==.Furion:BAAALAADCgcIEgAAAA==.Furiosah:BAAALAAECgIIAgAAAA==.',['Fü']='Fünfkanter:BAAALAADCggICAAAAA==.',Ga='Ganzo:BAABLAAECoEYAAIaAAYIrxtvfACFAQAaAAYIrxtvfACFAQAAAA==.Garguraz:BAAALAADCgcICwAAAA==.Garune:BAAALAADCgcIDQABLAAECggIDgABAAAAAA==.Gaviel:BAAALAADCggIFgABLAAFFAIIBgADAF0QAA==.',Ge='Gelimer:BAAALAADCgcIBwAAAA==.Genø:BAAALAAECggICAAAAA==.',Gl='Glàdíus:BAAALAAECgMIAwAAAA==.Glôin:BAAALAADCgQIAwAAAA==.',Go='Goldenswoord:BAAALAADCggIEAAAAA==.Gondrall:BAAALAADCggIBwAAAA==.Goosu:BAAALAAECgIIBAAAAA==.',Gr='Grecosa:BAAALAAECgYIDgAAAA==.Grimfang:BAAALAAECgMIAwAAAA==.Grishnar:BAAALAAECgYICAAAAA==.Grizzlysin:BAAALAADCgcIDgAAAA==.Gromz:BAABLAAECoEVAAIEAAYIjhzVIADfAQAEAAYIjhzVIADfAQAAAA==.Grîffith:BAAALAAECgcIEwAAAA==.',Gu='Gufte:BAAALAAECggIEQAAAA==.Guidan:BAAALAADCggICAAAAA==.',['Gô']='Gôr:BAAALAAECgcIEgAAAA==.',['Gö']='Göndula:BAAALAAECgYICQAAAA==.',Ha='Hagitakamich:BAAALAAECgYICQAAAA==.',He='Headlock:BAAALAADCgEIAQAAAA==.Helgå:BAAALAAECgYIEAAAAA==.Herazek:BAAALAADCgcIBwAAAA==.',Hi='Hiloria:BAAALAADCggICAAAAA==.',Ho='Honeyranger:BAAALAAECgUICAAAAA==.Hornochs:BAAALAADCgYIBgAAAA==.',Hu='Hu:BAABLAAECoEdAAIRAAgIXx3fEwCkAgARAAgIXx3fEwCkAgAAAA==.Hufenjunge:BAABLAAECoEWAAIKAAgIzh5OEACQAgAKAAgIzh5OEACQAgAAAA==.',Ik='Ikal:BAAALAAECggICAAAAA==.',Il='Ilanah:BAAALAADCggIDgAAAA==.Illandore:BAABLAAECoEeAAIFAAcIoQwljgB8AQAFAAcIoQwljgB8AQAAAA==.',In='Inoúla:BAAALAAECgIIAgAAAA==.Inuk:BAAALAAECgYIBwABLAAECggICAABAAAAAA==.',Iz='Izomoncherie:BAAALAAECgYICAAAAA==.',Ja='Jazabella:BAABLAAECoEZAAMGAAcIrB7AIgA1AgAGAAcIrB7AIgA1AgARAAEIRhI2kAAxAAAAAA==.Jazabelly:BAAALAAECgQIBQABLAAECgcIGQAGAKweAA==.',Jo='Johnsinclair:BAAALAAECgcICAAAAA==.Jolo:BAABLAAECoEtAAIaAAgImyN5FADpAgAaAAgImyN5FADpAgAAAA==.Jolreal:BAABLAAECoEkAAIKAAgIfx56DgCmAgAKAAgIfx56DgCmAgAAAA==.Jonez:BAABLAAECoEVAAIQAAgIkxQ3VQAWAgAQAAgIkxQ3VQAWAgAAAA==.Joññy:BAABLAAECoEWAAIDAAcIGRNKUgDHAQADAAcIGRNKUgDHAQAAAA==.',Ju='Julee:BAAALAAECgIIAgAAAA==.Juros:BAAALAAECgQIBAAAAA==.',Ka='Kagall:BAAALAAECgcIEwAAAA==.Kahlegrimdo:BAAALAADCgIIAgAAAA==.Kaitoo:BAAALAADCggICAAAAA==.Kaleidos:BAABLAAECoEYAAIXAAYI7h3MHQAHAgAXAAYI7h3MHQAHAgAAAA==.Kaleyna:BAAALAADCgEIAQAAAA==.Kalitha:BAAALAADCgYIBgAAAA==.Kaneo:BAAALAADCggIDAAAAA==.Kapier:BAAALAAFFAIIBAABLAAFFAQIDgARAHIdAA==.Karaschie:BAABLAAECoEpAAIaAAgIIyDfHgCtAgAaAAgIIyDfHgCtAgAAAA==.Karimor:BAAALAAECgQICAAAAA==.Kathlynna:BAAALAAECgYIEgAAAA==.Kazdul:BAAALAADCggIDgABLAAECgcIIwAaAPEhAA==.',Ke='Keald:BAAALAADCgUIBQAAAA==.Kejadyr:BAABLAAECoEWAAMbAAcIjBlDEQAWAgAbAAcIjBlDEQAWAgARAAEImwyelAApAAAAAA==.Keksmistress:BAAALAAECgEIAQAAAA==.Keori:BAACLAAFFIEFAAIaAAIIrgHaQQBXAAAaAAIIrgHaQQBXAAAsAAQKgRUAAhoACAhMDxhuAKQBABoACAhMDxhuAKQBAAAA.Kerrag:BAAALAAECgYIBgAAAA==.',Ki='Killder:BAAALAADCgUIBQAAAA==.Kirell:BAAALAADCggICAAAAA==.Kirigo:BAACLAAFFIEQAAIGAAUI0AiVBgBNAQAGAAUI0AiVBgBNAQAsAAQKgTMAAgYACAhBHWobAGICAAYACAhBHWobAGICAAAA.',Kl='Kladx:BAAALAAECggIDgAAAA==.',Kn='Knani:BAAALAAECgMIAwAAAA==.',Ko='Kobedin:BAAALAADCgYIBgAAAA==.Kolarak:BAABLAAECoEfAAMcAAgIZx/mFACyAgAcAAgIZx/mFACyAgAdAAEIEBHLqQA6AAAAAA==.Koli:BAAALAAECgcIEwAAAA==.Koshí:BAAALAADCgcIBwAAAA==.',Kr='Krônos:BAABLAAECoEYAAIMAAYI+hA0WABTAQAMAAYI+hA0WABTAQAAAA==.',Ku='Kuraj:BAAALAAECgEIAQAAAA==.Kurokuma:BAABLAAECoEaAAIaAAYIVxJlmgBKAQAaAAYIVxJlmgBKAQAAAA==.Kurthustle:BAAALAAECgMIAwAAAA==.',Ky='Kyressa:BAAALAAECgYICwAAAA==.',['Kí']='Kírá:BAAALAAECgIIAgAAAA==.',['Kî']='Kîmbaley:BAAALAADCggICwAAAA==.',['Kô']='Kôba:BAAALAADCgcIBwAAAA==.',La='Lanthas:BAAALAADCgMIAwAAAA==.Laschy:BAAALAAECgMIAwAAAA==.Laurana:BAAALAAECgQIBwAAAA==.Laureen:BAABLAAECoEjAAIDAAgIHBxyJQCJAgADAAgIHBxyJQCJAgAAAA==.',Le='Learichi:BAAALAADCgMIAwAAAA==.Lefarion:BAAALAADCggIFAAAAA==.Lefunky:BAAALAADCgcIBwAAAA==.Legosch:BAAALAADCgYIBgAAAA==.Lenary:BAAALAADCggICAAAAA==.',Li='Licay:BAAALAADCgYIBgAAAA==.Lightson:BAAALAAECggIDAAAAA==.Linaera:BAACLAAFFIEIAAIMAAIIyiM8FgDBAAAMAAIIyiM8FgDBAAAsAAQKgRgAAgwACAj7I7AMAPACAAwACAj7I7AMAPACAAAA.Lionedda:BAABLAAECoEdAAIXAAcIRAyuNQB4AQAXAAcIRAyuNQB4AQAAAA==.Listre:BAAALAAECgYIDQAAAA==.Litherie:BAAALAADCggICAAAAA==.',Lo='Loliksdeh:BAAALAAECgYIEgAAAA==.Lorelaya:BAAALAAECgYIDwAAAA==.Lorleen:BAABLAAECoEeAAIMAAYIAxEsXgA+AQAMAAYIAxEsXgA+AQAAAA==.',Lu='Luvilyen:BAAALAAECgIIAwAAAA==.Luxa:BAABLAAECoEYAAIeAAcIBxivTQD8AQAeAAcIBxivTQD8AQAAAA==.',['Lî']='Lîllîe:BAAALAADCgYIBwAAAA==.',['Lú']='Lúna:BAAALAAECgYIAwAAAA==.',Ma='Machmantis:BAAALAAECgYIEwABLAAFFAUIDwAVAJQTAA==.Madhunt:BAAALAAECggICAAAAA==.Madom:BAAALAADCggICAAAAA==.Madwarr:BAABLAAECoEaAAILAAcINRssQgD6AQALAAcINRssQgD6AQAAAA==.Maevina:BAAALAAECgIIAgAAAA==.Mag:BAAALAADCgYIDAAAAA==.Magia:BAABLAAECoEYAAIeAAcIBAUTlwArAQAeAAcIBAUTlwArAQAAAA==.Majak:BAAALAAECgEIAQAAAA==.Malicia:BAAALAAECgMIBgAAAA==.Manadis:BAAALAAECgIIAwAAAA==.Mandalich:BAAALAAECgMIBgABLAAECgYICAABAAAAAA==.Mandelmane:BAAALAAECgQIBAAAAA==.Mandrake:BAAALAAECgIIAgAAAA==.Marosgg:BAAALAADCgcIBwABLAAECggIKQAaACMgAA==.Marren:BAAALAAECgYIDQAAAA==.Massanie:BAABLAAECoEeAAIZAAcINhcVHgDPAQAZAAcINhcVHgDPAQAAAA==.Mayurî:BAACLAAFFIEGAAIaAAIIegcSOwB3AAAaAAIIegcSOwB3AAAsAAQKgScAAhoACAhNGXs4ADsCABoACAhNGXs4ADsCAAAA.',Me='Meatloaf:BAAALAAECggICAAAAA==.Meijra:BAAALAAECgIIBAAAAA==.Melwumonk:BAAALAAECgQIBgAAAA==.Menator:BAAALAADCgcIBwAAAA==.Mettîgel:BAAALAADCggIDgAAAA==.Meuchex:BAAALAAECgMIAwAAAA==.',Mi='Mietschi:BAAALAADCgIIAwAAAA==.Miiá:BAAALAADCggIFgAAAA==.Mikasà:BAAALAADCgUIBQAAAA==.Milinka:BAAALAADCggIDgAAAA==.Mimichân:BAAALAADCgYIBwAAAA==.Minicharles:BAAALAAECgUICAABLAAECgcIHwAHAFwLAA==.Miraculiixx:BAAALAADCggIGgAAAA==.',Mo='Mondprinzess:BAAALAADCggIJQABLAAECgcIBwABAAAAAA==.Monáchá:BAAALAAECgcIDQAAAA==.Moxxly:BAAALAADCgMIAwAAAA==.',Mu='Muhkulo:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.Muhtig:BAABLAAECoEbAAITAAcIaRbUDQDBAQATAAcIaRbUDQDBAQAAAA==.Mumble:BAAALAAECgUIBQABLAAECggICgABAAAAAA==.',['Mä']='Märtyria:BAAALAAECgYIDgAAAA==.',['Mó']='Móón:BAABLAAECoEkAAIcAAgIxB4tFgCqAgAcAAgIxB4tFgCqAgAAAA==.',Na='Nahida:BAABLAAECoEXAAMSAAcIFg72LgCLAQASAAcIFg72LgCLAQAfAAMIQAX8MQBuAAAAAA==.Nanamií:BAAALAAECgEIAQAAAA==.Narikela:BAABLAAECoEgAAIMAAcI9xtBJwAvAgAMAAcI9xtBJwAvAgAAAA==.Narkan:BAAALAADCgUICAAAAA==.Narrow:BAACLAAFFIEIAAMgAAIIZCA2BQDAAAAgAAIIZCA2BQDAAAAFAAIIuR7bIgCjAAAsAAQKgRoAAiAABwhaIsUIAKwCACAABwhaIsUIAKwCAAEsAAUUBQgPABIAJSYA.',Ne='Nealla:BAAALAADCggIGAAAAA==.Necrosia:BAABLAAECoEbAAIhAAgIQCDbHgDWAgAhAAgIQCDbHgDWAgAAAA==.Neferite:BAAALAADCggICAAAAA==.Nekoyasei:BAACLAAFFIERAAMGAAYIiw+qAwDCAQAGAAYIiw+qAwDCAQARAAQIXBMjBwBKAQAsAAQKgRkAAwYACAhsHDwVAI0CAAYACAhsHDwVAI0CABEABwh5G4ArAOwBAAAA.Nerîell:BAAALAAECgYIEAAAAA==.Neyrdok:BAAALAADCgcIDQABLAAECggIKQAaACMgAA==.',Ni='Niffty:BAAALAADCgYIBgAAAA==.Nilsa:BAAALAAECgcIDwAAAA==.',Nn='Nnoitra:BAACLAAFFIEFAAIFAAMIuRHMEwDtAAAFAAMIuRHMEwDtAAAsAAQKgRoAAgUABwi+IesjALACAAUABwi+IesjALACAAAA.',No='Nohand:BAAALAAECgMIAwAAAA==.Noshok:BAABLAAECoEYAAIcAAcI2Q3JiAA0AQAcAAcI2Q3JiAA0AQAAAA==.Nostii:BAAALAAECgYIDAAAAA==.Notafurry:BAAALAADCggICAAAAA==.Notaq:BAACLAAFFIERAAIQAAUIISbSAQAwAgAQAAUIISbSAQAwAgAsAAQKgTMAAhAACAiqJu4AAJQDABAACAiqJu4AAJQDAAAA.Notschy:BAAALAADCgEIAQAAAA==.',Ny='Nyzx:BAAALAAECggICgAAAA==.',['Ná']='Nárrow:BAAALAADCgUIBQABLAAFFAUIDwASACUmAA==.',['Nê']='Nêas:BAAALAAECggIEAAAAA==.',['Nò']='Nòtschy:BAAALAADCgcIDQAAAA==.',['Nû']='Nûrû:BAAALAADCggIEAAAAA==.',Oc='Ociussosus:BAAALAADCgMIAwAAAA==.',Od='Odrando:BAAALAAECgQIBAABLAAECgYIBgABAAAAAA==.',Og='Oglârun:BAAALAADCgcIBwAAAA==.',Oh='Oh:BAAALAAECgIIBAAAAA==.',On='Ongrin:BAAALAADCggIJQABLAAECgMIAwABAAAAAA==.Onugh:BAAALAAECgMIAwAAAA==.',Or='Orkzäpfchen:BAAALAADCgcIBwAAAA==.Orphileindos:BAAALAADCgcIBAAAAA==.',Ot='Otko:BAAALAAECgUIBQAAAA==.',Ov='Overdozer:BAAALAAECgEIAQAAAA==.',Pa='Pandemor:BAAALAAECggICgAAAA==.Paran:BAAALAAECgYIDgAAAA==.Paruktul:BAAALAAECgYICwAAAA==.Paulá:BAAALAAECgIIAgAAAA==.',Pe='Perverz:BAAALAADCgIIAgAAAA==.Pestarzt:BAAALAADCggICAABLAAECgYIEAABAAAAAA==.',Ph='Phillipp:BAAALAAECgQICwAAAA==.',Pi='Pixone:BAAALAAECgYIDAAAAA==.',Pl='Plampel:BAAALAADCgUIBQAAAA==.',Po='Polyphemus:BAAALAADCggICAAAAA==.',Pr='Prexqq:BAAALAADCggICwAAAA==.Prulig:BAABLAAECoEkAAIaAAgIVRcaPAAvAgAaAAgIVRcaPAAvAgAAAA==.',['Pé']='Pénthesilea:BAABLAAECoEdAAIJAAgIIw2dKgCdAQAJAAgIIw2dKgCdAQABLAAFFAIIBQAaAK4BAA==.',Qa='Qaigon:BAAALAADCgIIAgAAAA==.',Qw='Qwelsi:BAABLAAECoEWAAIMAAgIkQlTTQB8AQAMAAgIkQlTTQB8AQAAAA==.',Ra='Rakkavu:BAAALAADCggIDgABLAAECggIKQAaACMgAA==.Raldrak:BAABLAAECoEYAAISAAYI9RFrNgBZAQASAAYI9RFrNgBZAQAAAA==.Ralnaria:BAAALAAECgYIBgAAAA==.Rapuun:BAAALAAFFAIIAgABLAAFFAMIDQAeALoeAA==.Raychel:BAABLAAECoEYAAINAAcIZAiiUABPAQANAAcIZAiiUABPAQAAAA==.',Re='Reekha:BAAALAAECgMIBQAAAA==.Renlarian:BAAALAADCggICAAAAA==.Reínerzufall:BAAALAAECgYIDwAAAA==.',Ri='Riya:BAABLAAECoEeAAIGAAcIXRnoKgALAgAGAAcIXRnoKgALAgAAAA==.',Ro='Rokdan:BAAALAAECgMIAwAAAA==.Rondal:BAAALAADCgMIAwAAAA==.Rondâ:BAAALAAECgYICgAAAA==.',Ru='Russel:BAABLAAECoElAAIMAAgIghgWIABbAgAMAAgIghgWIABbAgAAAA==.Ruvik:BAAALAAECgcIEwAAAA==.',Ry='Ryokaji:BAAALAADCgcICAAAAA==.',Sa='Sadará:BAAALAAECggIBQAAAA==.Sahri:BAAALAAECgUICgAAAA==.Salah:BAAALAADCgYIBgAAAA==.Salarah:BAAALAAECgYIBwAAAA==.Salhia:BAAALAADCggICAAAAA==.Sanadriel:BAAALAADCgMIAwAAAA==.Sanraku:BAACLAAFFIEFAAIQAAIIRwrDNQCWAAAQAAIIRwrDNQCWAAAsAAQKgSUAAhAACAiVIDobAOsCABAACAiVIDobAOsCAAAA.Sarifa:BAAALAAECggICwAAAA==.Sathivae:BAAALAAECgYIDgAAAA==.Sazary:BAAALAAECgYIBgAAAA==.',Sc='Schlîtzohr:BAAALAAECgMIBAAAAA==.Schuäänzmän:BAAALAADCgEIAQAAAA==.Scoldy:BAAALAAFFAIIAgABLAAFFAMIBQAhAAcXAA==.Scrajak:BAABLAAECoEaAAINAAcIuRGjOAC/AQANAAcIuRGjOAC/AQAAAA==.',Se='Setareh:BAAALAAECgMIBAAAAA==.Seuchenwind:BAACLAAFFIEGAAIDAAII+BKuKgCbAAADAAII+BKuKgCbAAAsAAQKgSEAAgMACAgaHFcgAKcCAAMACAgaHFcgAKcCAAAA.Seyqt:BAAALAADCgQIBAAAAA==.',Sh='Shaah:BAAALAAECgYIBgAAAA==.Shaylaah:BAAALAAECgYICwAAAA==.Shenlo:BAAALAADCgEIAQAAAA==.Sheylá:BAAALAADCgMIAwAAAA==.Shiasa:BAAALAAECgMIAQAAAA==.Shyrianâ:BAAALAAECgEIAQAAAA==.',Si='Sichelhammer:BAAALAAECgMIAwAAAA==.Sickshots:BAAALAAECgUIBQAAAA==.Silare:BAAALAAECgEIAQAAAA==.Silimauré:BAAALAADCggICAAAAA==.Simâr:BAABLAAECoEYAAMdAAgIhRgzJgBbAgAdAAgIhRgzJgBbAgAcAAUI5xYbjgApAQAAAA==.Sintheras:BAAALAADCgYIDAAAAA==.Sippê:BAAALAADCgcIBgAAAA==.',Sk='Skizzl:BAAALAAECgYIBwAAAA==.Skylarked:BAAALAADCgYIBgAAAA==.',Sl='Slacé:BAAALAAECgIIAwAAAA==.Slany:BAAALAADCgMIAwAAAA==.Slater:BAAALAADCgQIBAAAAA==.Slaxxstarsha:BAAALAADCgEIAQAAAA==.Slaxxstarwar:BAAALAADCgYIBgAAAA==.Slickdaddy:BAAALAAECgMIBQAAAA==.',Sn='Snaxace:BAAALAAECggIEQAAAA==.Snâx:BAAALAAECgYIDAAAAA==.',So='Sokeni:BAAALAAECgUICAAAAA==.Solu:BAAALAADCggICAAAAA==.Sorenta:BAAALAADCgYICQAAAA==.',Sq='Squäbble:BAABLAAECoEgAAIcAAgIVgnFkQAhAQAcAAgIVgnFkQAhAQAAAA==.',St='Strolchî:BAAALAADCgcIBwAAAA==.',Su='Suncliv:BAAALAADCgIIAgAAAA==.',Sy='Syre:BAAALAAECggIDgAAAA==.',['Sâ']='Sâmolia:BAAALAAECgMICAAAAA==.',['Sé']='Séraphéná:BAAALAAECgYICwAAAA==.',Ta='Tabanddot:BAAALAAECgcICAAAAA==.Tahlis:BAABLAAECoEgAAMiAAgIqxV6CAAAAgAiAAgIqxV6CAAAAgANAAYIug++SwBkAQAAAA==.Tainois:BAAALAAECggICQAAAA==.Tanlia:BAABLAAECoEeAAMJAAcIdA5cMAB7AQAJAAcIdA5cMAB7AQAQAAYILQi+zgAqAQAAAA==.Tantela:BAAALAAECgYIBwAAAA==.',Te='Terônas:BAABLAAECoEUAAIjAAYICxIFJgBzAQAjAAYICxIFJgBzAQAAAA==.',Th='Thalia:BAAALAAECgcIBQAAAA==.Thranka:BAAALAADCggIDwAAAA==.Thrun:BAAALAAECgMIBAAAAA==.',Ti='Timox:BAAALAAECgQIBQAAAA==.Tintax:BAABLAAECoEjAAMcAAgInBhNLgA1AgAcAAgInBhNLgA1AgAdAAgI0gtNSQC1AQAAAA==.Tirana:BAAALAADCgcIEwAAAA==.',To='Togur:BAABLAAECoElAAIdAAgIsBvsGgCnAgAdAAgIsBvsGgCnAgAAAA==.Tombkiller:BAAALAAECggIEAAAAA==.Tooytwoo:BAAALAAECgYICQABLAAECgYIDAABAAAAAA==.Toroc:BAAALAADCgYIBgAAAA==.',Tr='Treamweaver:BAAALAAECgQIBgAAAA==.Trok:BAAALAADCggICAAAAA==.Trullalala:BAAALAADCggICAAAAA==.Truntio:BAAALAADCgQIBAAAAA==.',Ts='Tschurke:BAAALAAECggICAABLAAECgcIGwAeAKkWAA==.Tsheyari:BAACLAAFFIEPAAIeAAUIvB2WCQDWAQAeAAUIvB2WCQDWAQAsAAQKgTMAAx4ACAhoJdgNACADAB4ACAg/JdgNACADACQABgh9IQAAAAAAAAAA.',Tu='Tur:BAAALAAECgYIBgABLAAECggIJAAIAAoiAA==.Turbospaten:BAAALAADCggICAAAAA==.',Ty='Tyracos:BAAALAAECggIDAAAAA==.Tyrahilda:BAAALAADCgYIBgAAAA==.Tyriane:BAABLAAECoEfAAIeAAgI/xLlRQAXAgAeAAgI/xLlRQAXAgAAAA==.',['Tì']='Tìbbìt:BAAALAAECgMIBAAAAA==.',Un='Uniquex:BAABLAAECoEgAAIDAAgISw5zcABvAQADAAgISw5zcABvAQAAAA==.',Va='Valeri:BAABLAAECoEaAAIQAAYIYhqriwCkAQAQAAYIYhqriwCkAQAAAA==.Valkyrja:BAAALAAECggIBwAAAA==.Valstrax:BAAALAAECgYIBgABLAAECggIJQAMAIIYAA==.',Ve='Vertiko:BAACLAAFFIEIAAIVAAIIvBZUEACrAAAVAAIIvBZUEACrAAAsAAQKgR0AAhUACAjzHWwNALUCABUACAjzHWwNALUCAAAA.',Vi='Vierkanter:BAABLAAECoEYAAIPAAcIVh6/HQBhAgAPAAcIVh6/HQBhAgAAAA==.Vimzo:BAAALAADCggICAAAAA==.Vine:BAAALAAFFAEIAQAAAA==.Violaalexiel:BAAALAAECgYIDQAAAA==.',Vl='Vlubbax:BAABLAAECoEhAAQWAAgI/RiYDABHAgAWAAgI7xaYDABHAgAVAAUI1hq8MwCEAQAlAAEIRg3gGgA5AAAAAA==.',Vo='Vordan:BAAALAAECgYIBgAAAA==.Vortac:BAABLAAECoEeAAIcAAcIghaCUADDAQAcAAcIghaCUADDAQAAAA==.',Vu='Vuldurdeath:BAABLAAECoEWAAIPAAcI7hBWRwB/AQAPAAcI7hBWRwB/AQAAAA==.Vulkanius:BAAALAADCgMIAwABLAADCggIDAABAAAAAA==.',['Vó']='Vóie:BAAALAAECgMIBQAAAA==.',Wa='Waltraudt:BAABLAAECoEfAAMDAAYI+h+FOwAeAgADAAYI2B+FOwAeAgAEAAYInBWCMwB+AQAAAA==.',We='Weroth:BAAALAADCgEIAQAAAA==.',Wi='Wis:BAAALAAECggICQAAAA==.Wispal:BAABLAAECoEgAAIZAAcIsRXEJACZAQAZAAcIsRXEJACZAQAAAA==.',Wo='Wohgan:BAAALAAECgYIEAAAAA==.Worgoth:BAAALAADCggICAAAAA==.Worloc:BAAALAADCgcIBwAAAA==.',Xa='Xartismandra:BAAALAAECggIEAAAAA==.',Xe='Xelestin:BAAALAADCgYIBgAAAA==.Xelo:BAAALAAECggIEAAAAA==.Xena:BAACLAAFFIEFAAILAAIIdxpXFwC4AAALAAIIdxpXFwC4AAAsAAQKgSoAAgsACAiwI2wKADkDAAsACAiwI2wKADkDAAAA.Xeremiozar:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Xy='Xymbram:BAAALAADCgcIBgAAAA==.Xyris:BAAALAAECgcIEQAAAA==.',Ys='Ysondré:BAAALAAECgEIAQAAAA==.',Yu='Yunxu:BAAALAAECggIEQAAAA==.',Yv='Yvainè:BAABLAAECoEdAAIFAAYIbBSanABfAQAFAAYIbBSanABfAQAAAA==.',['Yâ']='Yâri:BAAALAAECgYICAABLAAFFAUIDwAeALwdAA==.',Za='Zaphir:BAAALAADCggIDwAAAA==.Zarantor:BAAALAAECgYIEgAAAA==.Zaubberer:BAABLAAECoEbAAIeAAcIqRYVVwDfAQAeAAcIqRYVVwDfAQAAAA==.',Ze='Zedora:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.Zeizt:BAAALAAECgQIBgAAAA==.Zewana:BAAALAADCggIFAAAAA==.',Zu='Zuan:BAAALAADCgIIAgABLAAECgYIEQABAAAAAA==.Zujan:BAAALAADCgYIBwABLAAECggIHQAGAPgcAA==.Zuria:BAABLAAECoEXAAINAAcIcg2JVQA5AQANAAcIcg2JVQA5AQAAAA==.',Zw='Zwonki:BAABLAAECoEkAAMCAAgI/B0ODQCpAgACAAgI/B0ODQCpAgAIAAEIQBv4PABPAAAAAA==.',['Zá']='Zá:BAAALAADCggICAAAAA==.',['Zì']='Zìm:BAABLAAECoEXAAIXAAcIvSB5DQCqAgAXAAcIvSB5DQCqAgAAAA==.',['Zò']='Zòrn:BAABLAAECoEWAAIDAAYI2g0oegBVAQADAAYI2g0oegBVAQAAAA==.',['Âm']='Âmlîn:BAAALAAECgYIDAAAAA==.',['Æw']='Æw:BAAALAAECgIIAgABLAAFFAIIBgAPAGIhAA==.',['Æz']='Æz:BAACLAAFFIEGAAIPAAIIYiGjDwDHAAAPAAIIYiGjDwDHAAAsAAQKgSgAAg8ACAhdIR8LAAEDAA8ACAhdIR8LAAEDAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end