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
 local lookup = {'Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Frost','DemonHunter-Havoc','Shaman-Restoration','Mage-Arcane','Mage-Frost','Hunter-Marksmanship','Paladin-Retribution','Druid-Restoration','Druid-Balance','Warlock-Destruction','Monk-Brewmaster','Evoker-Devastation','Warlock-Demonology','Warrior-Fury','Shaman-Elemental','DeathKnight-Blood','Paladin-Protection','Warrior-Arms','Warrior-Protection','DemonHunter-Vengeance','Monk-Mistweaver','Shaman-Enhancement','Rogue-Subtlety','Rogue-Assassination','Paladin-Holy','Evoker-Preservation','Priest-Shadow','Evoker-Augmentation','Monk-Windwalker','Priest-Holy','Priest-Discipline','Druid-Feral','DeathKnight-Unholy',}; local provider = {region='EU',realm='Illidan',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Ackö:BAABLAAECoEZAAIBAAYINxHglQBSAQABAAYINxHglQBSAQAAAA==.',Ad='Adoloes:BAAALAAECgMIBwAAAA==.',Ae='Aelius:BAAALAADCgYIBgAAAA==.Aerielle:BAAALAADCgIIAgAAAA==.',Ak='Akantis:BAAALAAECgIIAgABLAAECgYIDgACAAAAAA==.',Al='Allhin:BAAALAADCgcIBwABLAAECgUICAACAAAAAA==.Alluna:BAABLAAECoEwAAIDAAgI/yKZFwD5AgADAAgI/yKZFwD5AgAAAA==.Aloneth:BAAALAADCgMIAwAAAA==.',Am='Amarih:BAABLAAECoEWAAIEAAgI0R6+HgDKAgAEAAgI0R6+HgDKAgAAAA==.',An='Antifascista:BAAALAAECgIIAgAAAA==.',As='Ashenshugar:BAABLAAECoEaAAIFAAgIQx42JgBXAgAFAAgIQx42JgBXAgAAAA==.Aspargus:BAAALAADCgcICQAAAA==.Asté:BAAALAADCgMIAwAAAA==.Asumix:BAAALAAECgIIAgAAAA==.',At='Atixay:BAAALAADCggICAABLAAECgYICgACAAAAAA==.',Au='Aurahn:BAAALAADCggIDAAAAA==.',Ax='Axo:BAAALAADCgMIAwAAAA==.',Ay='Ayshare:BAAALAADCggICgAAAA==.',Az='Azalìe:BAAALAADCgYIBgAAAA==.',['Aý']='Aýla:BAAALAAECgMIBQAAAA==.',Ba='Baconhunter:BAAALAAECgcIDgAAAA==.Badnos:BAABLAAECoEgAAIGAAgIKg1yYgC9AQAGAAgIKg1yYgC9AQAAAA==.Bandos:BAAALAADCggICAAAAA==.',Be='Beckett:BAAALAADCggIFwAAAA==.Beepp:BAABLAAECoEWAAIHAAgIVRnNFQBNAgAHAAgIVRnNFQBNAgAAAA==.Berym:BAAALAADCgcIBwAAAA==.',Bo='Bongabin:BAABLAAECoEfAAMIAAYI0hZCRwB/AQAIAAYIaRZCRwB/AQABAAMIjwn3KgEJAAAAAA==.Boontar:BAACLAAFFIEIAAIEAAII8RsVJgCfAAAEAAII8RsVJgCfAAAsAAQKgSYAAgQACAj6IB0WAPwCAAQACAj6IB0WAPwCAAAA.Bordosan:BAAALAAECggICAAAAA==.Boublo:BAAALAAECgMIAwAAAA==.Boukàry:BAAALAAECgIIAgAAAA==.',Br='Bratkick:BAAALAAECgYICQAAAA==.Bromuldir:BAABLAAECoEbAAIJAAcIyhZtZwDsAQAJAAcIyhZtZwDsAQAAAA==.Brutizy:BAAALAAECgYICAAAAA==.',Bu='Buissøn:BAABLAAECoEcAAMKAAcImg+TTwBsAQAKAAcImg+TTwBsAQALAAcIxgcsUQA5AQAAAA==.Buritos:BAABLAAECoElAAIMAAgI7RDfWwCpAQAMAAgI7RDfWwCpAQAAAA==.',Bz='Bzhcoco:BAACLAAFFIEKAAIEAAIIixZtJwCdAAAEAAIIixZtJwCdAAAsAAQKgUkAAgQACAioI8URABUDAAQACAioI8URABUDAAAA.',['Bê']='Bêëtle:BAABLAAECoEoAAINAAgIORCHGgCeAQANAAgIORCHGgCeAQAAAA==.',Ca='Caa:BAAALAAECgIIAgAAAA==.',Ch='Chakie:BAAALAAECgUICAABLAAECgYIIQADAOshAA==.Chamajah:BAAALAADCggIDQAAAA==.Chanla:BAAALAADCggICAAAAA==.Chatdique:BAAALAADCgcICgAAAA==.Chibracier:BAAALAAECgcIDQAAAA==.Chickaru:BAAALAADCgcICQABLAAFFAIIBgAHAGIhAA==.Choumami:BAABLAAECoEaAAIOAAgI6hZAHQAYAgAOAAgI6hZAHQAYAgAAAA==.',Cl='Cleveland:BAABLAAECoEaAAMPAAYIIRXaPABXAQAPAAUIahTaPABXAQAMAAQIGwyHqgDDAAAAAA==.Clôchêtte:BAACLAAFFIEKAAIBAAIIxxaQIwCcAAABAAIIxxaQIwCcAAAsAAQKgUgAAgEACAjgHGMyAFICAAEACAjgHGMyAFICAAAA.',Co='Corana:BAAALAADCgUIBgABLAAECgIIBAACAAAAAA==.Cornedbeef:BAAALAAECgYIDQAAAA==.',Cr='Crùsaders:BAAALAAECgcICgAAAA==.',Cu='Cute:BAAALAAECgcIBwAAAA==.',['Cï']='Cïrion:BAABLAAECoEfAAIQAAgIcBlrLwBKAgAQAAgIcBlrLwBKAgAAAA==.',['Cø']='Cøcø:BAACLAAFFIEIAAIKAAIIMR/1EwC0AAAKAAIIMR/1EwC0AAAsAAQKgSgAAwoACAg6IB4QALkCAAoACAg6IB4QALkCAAsABwi6DuVIAFwBAAAA.',Da='Dardan:BAABLAAECoEYAAIRAAcIpR+aHwCFAgARAAcIpR+aHwCFAgAAAA==.',De='Deidarra:BAABLAAECoEdAAIJAAgIdyHvLgCPAgAJAAgIdyHvLgCPAgAAAA==.Delbhord:BAAALAAECgYICgAAAA==.Deviljäh:BAAALAAECgcIDwABLAAECggIIQARAIUbAA==.Deviltchad:BAABLAAECoEhAAIRAAgIhRsYHQCXAgARAAgIhRsYHQCXAgAAAA==.',Di='Diàblofx:BAAALAAECgUIBgAAAA==.',Dk='Dklamite:BAACLAAFFIEKAAMSAAIIOSCaBwC+AAASAAIIOSCaBwC+AAADAAIIfB3TMwCfAAAsAAQKgUcAAwMACAj2JaoLADgDAAMACAhgJaoLADgDABIABQhWJYwUANEBAAAA.',Dm='Dmü:BAAALAAECgIIAgAAAA==.',Do='Dorak:BAABLAAECoEUAAIHAAcIoBQXJwDIAQAHAAcIoBQXJwDIAQAAAA==.',Dr='Draguanos:BAABLAAECoElAAIJAAgI+BuoNwBtAgAJAAgI+BuoNwBtAgAAAA==.Draktarre:BAAALAADCgcICQAAAA==.Dreinisse:BAACLAAFFIEPAAIFAAMIXhe7DwDlAAAFAAMIXhe7DwDlAAAsAAQKgSYAAwUACAjRGbY2ABYCAAUACAjRGbY2ABYCABEABwiHEjtEAMgBAAAA.Drägny:BAAALAAECgIIBAAAAA==.',Du='Dumblol:BAAALAAECgMICAAAAA==.',['Dâ']='Dânestan:BAAALAAECgcICAAAAA==.',['Dï']='Dïxîkry:BAAALAAECgcIDQAAAA==.',Ea='Easier:BAAALAAFFAIIAgAAAA==.',Ek='Ektyno:BAAALAADCgMIAwAAAA==.',El='Elaidja:BAABLAAECoE5AAMJAAgIkSJDJgC0AgAJAAcI8SFDJgC0AgATAAgIGyBRJACcAQAAAA==.Elf:BAAALAAECgIIAgAAAA==.Ellenae:BAABLAAECoEpAAIHAAgIxh5sEQB5AgAHAAgIxh5sEQB5AgAAAA==.Elunara:BAAALAAECgYIDAAAAA==.Elyz:BAAALAAECgIIAgAAAA==.Eléria:BAABLAAECoEiAAIFAAgIOxo0JgBXAgAFAAgIOxo0JgBXAgAAAA==.Eløyä:BAABLAAECoEWAAQQAAgIPg9iVAC8AQAQAAgIpg5iVAC8AQAUAAQIvAx0IADTAAAVAAgIqgBDgQAZAAAAAA==.',En='Enõla:BAAALAAECgcIDgAAAA==.',Eo='Eolia:BAAALAADCgQIBAAAAA==.',Ep='Epsilardon:BAAALAAECgEIAQAAAA==.',Er='Erathole:BAAALAAECgEIAQAAAA==.',Ew='Ewilon:BAAALAAECgEIAQAAAA==.',Fa='Fakekigrif:BAAALAAFFAIIAgAAAA==.Falcor:BAABLAAECoEcAAIWAAcIgRGCIgBnAQAWAAcIgRGCIgBnAQAAAA==.Faux:BAAALAADCggICAAAAA==.Favelinha:BAAALAADCggIIwAAAA==.',Fe='Fear:BAAALAAECgMIAQAAAA==.Fearfearfear:BAAALAAECgMIAwAAAA==.Feigndeath:BAAALAAECgYIDAABLAAECggIKQAXAHUgAA==.Fenwell:BAACLAAFFIELAAIYAAQIUhtaAQBwAQAYAAQIUhtaAQBwAQAsAAQKgSoAAhgACAj5IEUEANUCABgACAj5IEUEANUCAAAA.',Fi='Ficelle:BAACLAAFFIEKAAIBAAIIxRQRMQCJAAABAAIIxRQRMQCJAAAsAAQKgScAAgEACAgEImUaAMcCAAEACAgEImUaAMcCAAAA.Filly:BAABLAAECoEmAAIMAAgInRzrKAB2AgAMAAgInRzrKAB2AgAAAA==.Firefisher:BAAALAAECgUIAwAAAA==.',Fl='Flemeths:BAAALAADCggICAAAAA==.',Fo='Fouet:BAAALAAECgMIBgAAAA==.',Fr='Freeya:BAAALAAECgUIAwAAAA==.',Fu='Fufuti:BAABLAAECoEYAAIZAAcIYB17CgBvAgAZAAcIYB17CgBvAgAAAA==.Furïæ:BAAALAADCggICAAAAA==.',['Fâ']='Fâvêlinhâ:BAAALAADCggIIAAAAA==.',['Fë']='Fëanôr:BAAALAADCggIBgAAAA==.',['Fÿ']='Fÿri:BAAALAAECgYIBgAAAA==.',Ga='Gastmort:BAABLAAECoEmAAMSAAgIrxqAEgDyAQASAAgIrxqAEgDyAQADAAUInAN1CwG9AAAAAA==.',Ge='Geb:BAAALAAECgYIBwAAAA==.',Gh='Ghaffas:BAAALAAECgYICwAAAA==.Ghostuns:BAABLAAECoEVAAMZAAYIFholIABkAQAZAAUIARklIABkAQAaAAQIwhOlRQATAQAAAA==.',Gl='Globok:BAAALAAECgYIDQAAAA==.',Go='Gothiika:BAAALAADCgYIBgAAAA==.',Gr='Grimmjôww:BAABLAAECoEgAAIaAAYIyBtCJQDdAQAaAAYIyBtCJQDdAQAAAA==.Grlm:BAABLAAECoEgAAMFAAgI9RuQXgCdAQAFAAgI9RuQXgCdAQARAAUIgRJ3cQArAQAAAA==.Grunbeld:BAAALAADCgQIBAAAAA==.',Gu='Guljaeden:BAAALAAECgMIAwAAAA==.Guuldaan:BAAALAAECgYIBgAAAA==.',['Gü']='Gürdan:BAAALAAECgQIBwAAAA==.',He='Heldios:BAAALAAECggIEwABLAAECggIHAAHAP0gAA==.Heyrazmo:BAABLAAECoEVAAMNAAYIGBg8JgAnAQANAAUILBg8JgAnAQAXAAYIzQvWLAAFAQAAAA==.Heållusiðn:BAAALAAECgcIDgAAAA==.',Ho='Hoprytal:BAABLAAECoEXAAIGAAgIbwwwZAC4AQAGAAgIbwwwZAC4AQAAAA==.',Hu='Humanisse:BAAALAAECgcIDAABLAAFFAMIDwAFAF4XAA==.',Hy='Hyosube:BAAALAADCgcIBwAAAA==.',['Hä']='Häussen:BAABLAAECoEjAAMJAAcIOA+wpgBzAQAJAAcIOA+wpgBzAQAbAAcIVglEPQAxAQAAAA==.Häxbrygd:BAAALAADCgcIBwAAAA==.',['Hù']='Hùtch:BAABLAAECoEOAAIHAAYICQrvRQAxAQAHAAYICQrvRQAxAQAAAA==.',['Hü']='Hünk:BAAALAADCggIIwAAAA==.',Ia='Iadok:BAAALAADCgcIBwABLAAECggIGgAPAHokAA==.',Ic='Ichïmaru:BAAALAADCgcIDgAAAA==.',Il='Ilithya:BAAALAADCggIFQAAAA==.Ilwyna:BAAALAADCgcICAAAAA==.',Im='Immuane:BAAALAAECgYICAAAAA==.',Ir='Iruushisama:BAAALAAECggIEQAAAA==.',Is='Istos:BAAALAADCgYIBgAAAA==.',Iy='Iyonas:BAAALAAECgYIDgAAAA==.',Ja='Jackpote:BAAALAAECgYIBgAAAA==.',Jo='Jozbelu:BAAALAAECgUICAABLAAECgYICAACAAAAAA==.',['Jä']='Jäckz:BAAALAAECggICAAAAA==.Jähreg:BAAALAAECgYIBgABLAAECgcIHgADAIQiAA==.Järjär:BAAALAAECgYICAAAAA==.',['Jö']='Jöthun:BAABLAAECoEdAAIFAAcIsROzZQCKAQAFAAcIsROzZQCKAQAAAA==.',Ka='Kactus:BAAALAAECgYIBwAAAA==.Kadlaxyr:BAACLAAFFIELAAIcAAIIEyZwCADeAAAcAAIIEyZwCADeAAAsAAQKgTYAAhwACAiXHZgHAJ0CABwACAiXHZgHAJ0CAAAA.Kakkette:BAAALAAECgcICQAAAA==.Kalaer:BAAALAAECggIEwABLAAFFAQICQAdANsTAA==.Kallaye:BAAALAADCgQIBAAAAA==.Karden:BAABLAAECoEZAAIBAAcI6RQwYQDDAQABAAcI6RQwYQDDAQAAAA==.Karduza:BAAALAADCgcIBwAAAA==.',Ke='Keelea:BAACLAAFFIEJAAIdAAQI2xPQCQA4AQAdAAQI2xPQCQA4AQAsAAQKgScAAh0ACAgnIeUPAOECAB0ACAgnIeUPAOECAAAA.Keilerr:BAABLAAECoEUAAIOAAcItx5hGABHAgAOAAcItx5hGABHAgAAAA==.Keirà:BAAALAAECgEIAQAAAA==.Ketapokolips:BAAALAADCggIGQAAAA==.Keyn:BAABLAAECoEbAAIHAAYI7AbSTwABAQAHAAYI7AbSTwABAQAAAA==.Keïlà:BAAALAADCgYIEQAAAA==.',Kh='Khaya:BAAALAAECgYICwABLAAECggIGgADALQUAA==.Kheph:BAABLAAECoEfAAIbAAgIQhlsDwB3AgAbAAgIQhlsDwB3AgAAAA==.',Ki='Kikelfe:BAAALAAECgUICQAAAA==.',Kn='Knuh:BAAALAADCggICwAAAA==.',Ko='Korak:BAAALAAECgIIAgAAAA==.',Kr='Krapoc:BAAALAAECgUIBgABLAAECggIGQAQAFQUAA==.Krapock:BAABLAAECoEZAAMQAAgIVBTjTQDRAQAQAAcIihXjTQDRAQAVAAMITQjAaAByAAAAAA==.Kraven:BAABLAAECoEVAAIBAAYIURnDcwCXAQABAAYIURnDcwCXAQAAAA==.Krolox:BAAALAAECgcIBwAAAA==.',Ky='Kylana:BAAALAADCggIGwAAAA==.Kynvaras:BAAALAAECgUIBQAAAA==.',['Kâ']='Kâlaye:BAAALAAECgEIAQAAAA==.',['Kä']='Kämikazy:BAABLAAECoEbAAIJAAcIBx5VWwAHAgAJAAcIBx5VWwAHAgAAAA==.',La='Lashaya:BAAALAADCgIIAgAAAA==.Laucéane:BAAALAADCggICQAAAA==.Laël:BAABLAAECoEUAAIXAAYIRhBRJgA9AQAXAAYIRhBRJgA9AQAAAA==.',Le='Leemyungbak:BAACLAAFFIEKAAIQAAUI8xqMCwA8AQAQAAUI8xqMCwA8AQAsAAQKgTIAAhAACAirJZEHAE4DABAACAirJZEHAE4DAAAA.Leffedral:BAAALAAECgUICwAAAA==.Lewelyn:BAAALAADCggICAAAAA==.Lexious:BAAALAADCgYIBgAAAA==.Leyvina:BAAALAADCggIDgAAAA==.',Li='Lighthammer:BAAALAAECgEIAQAAAA==.Linkshay:BAAALAADCgYIBgAAAA==.',Lo='Loraën:BAAALAAECgUIBQAAAA==.Loreleïla:BAAALAAECgcIDAAAAA==.',Lu='Lubellion:BAABLAAECoEhAAMcAAcI+xa7EQDkAQAcAAcI+xa7EQDkAQAeAAQIQRQgDwACAQAAAA==.',Ly='Lyca:BAAALAAECgIIAgAAAA==.',['Lè']='Lèd:BAAALAADCgQIBAAAAA==.',['Lê']='Lêd:BAABLAAECoEeAAIWAAgIJBs3DABuAgAWAAgIJBs3DABuAgAAAA==.',['Lë']='Lëdd:BAAALAAECgcIDQAAAA==.',['Lì']='Lìnk:BAAALAAECgcIDgAAAA==.',Ma='Madamepo:BAAALAADCgMIAwAAAA==.Maduelyn:BAAALAAECgYIBgAAAA==.Maelwyn:BAABLAAECoEUAAIKAAYIixG4WQBIAQAKAAYIixG4WQBIAQABLAAECggIHAAHAP0gAA==.Maestrø:BAAALAADCgMIAwAAAA==.Mahito:BAAALAAECgIIAgAAAA==.Majoxy:BAAALAADCggIDwAAAA==.Marheaven:BAABLAAECoEXAAILAAcIExWMMQDKAQALAAcIExWMMQDKAQAAAA==.Maxinaz:BAAALAADCggIGwAAAA==.',Mb='Mbaka:BAAALAADCgcIBwABLAAFFAMIBwAIAM4RAA==.',Mc='Mckay:BAAALAAECgIIAwAAAA==.',Me='Medipac:BAAALAAECgIIAgAAAA==.Meldan:BAABLAAECoE7AAIRAAgILhLDPwDbAQARAAgILhLDPwDbAQAAAA==.Meljânz:BAABLAAECoEVAAIBAAcINQ6urwAgAQABAAcINQ6urwAgAQAAAA==.Memel:BAAALAADCgIIAgAAAA==.Mentalyill:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.Meraxes:BAACLAAFFIEIAAIXAAMI1g8OCADhAAAXAAMI1g8OCADhAAAsAAQKgRcAAxcACAhnEoQaALQBABcACAhnEoQaALQBAB8ABwgYCHo0ADkBAAAA.Merckava:BAAALAAECgYIDAAAAA==.',Mi='Miketysôn:BAAALAADCgcIBwAAAA==.Mirack:BAAALAAECgMIAwAAAA==.',Mo='Monahlisa:BAAALAAECgMIBgAAAA==.Monbazillac:BAABLAAECoEdAAIHAAYI2hhfLwCaAQAHAAYI2hhfLwCaAQAAAA==.Monsu:BAAALAAECgMIAwAAAA==.Montoya:BAAALAAECgQIBAAAAA==.Moonform:BAAALAAECggICAAAAA==.Morphey:BAAALAADCggIDgAAAA==.Mouchoustyle:BAABLAAECoEZAAIEAAYI5R34eQCkAQAEAAYI5R34eQCkAQAAAA==.',Mu='Murderdollz:BAAALAADCggICAAAAA==.',['Mé']='Méliødas:BAAALAAECgMIBQABLAAFFAIICgASADkgAA==.',['Mï']='Mïnuït:BAABLAAECoEVAAIBAAcInwbrtAAWAQABAAcInwbrtAAWAQAAAA==.Mïra:BAAALAADCggICAAAAA==.',Na='Nadyie:BAABLAAECoEYAAIdAAcIPRtsJwAgAgAdAAcIPRtsJwAgAgAAAA==.Nalagos:BAAALAAECgIIAgAAAA==.Nasthya:BAAALAAECgIIAgAAAA==.Nayma:BAAALAADCggIDwAAAA==.',Ne='Necrogodx:BAAALAAECggIDgAAAA==.Nectarinee:BAABLAAECoEtAAMgAAgIYRjQIgBKAgAgAAgIYRjQIgBKAgAhAAUIDRM+FgAaAQAAAA==.',No='Nonverbal:BAABLAAFFIEHAAIGAAMIJx/eFQATAQAGAAMIJx/eFQATAQAAAA==.Notsgar:BAAALAAECgYICgAAAA==.',Ns='Nsomnia:BAAALAAECgYICgABLAAFFAMIBgAKAIcfAA==.',['Nà']='Nàm:BAAALAAECgMIAwAAAA==.',['Né']='Nécroh:BAAALAAECgYIDQAAAA==.',['Nø']='Nøvä:BAAALAAECggICAAAAA==.',Oi='Oil:BAAALAAECgIIAgAAAA==.',Ol='Olya:BAAALAAECggICAABLAAECggIHAAHAP0gAA==.',Om='Omerdalors:BAAALAAECgMIAwAAAA==.',Ou='Ouique:BAAALAAECgcIDAAAAA==.',Ov='Overlords:BAAALAADCgcIDgAAAA==.',Ox='Oxmolol:BAAALAAECgMIBgAAAA==.',Pa='Painful:BAAALAADCgYIBgAAAA==.Palapin:BAAALAAECgQIBgAAAA==.Palcorico:BAAALAADCgQIBAABLAAFFAIICgAEAIsWAA==.Panorhamix:BAABLAAECoEWAAIiAAcI9wjbIgBOAQAiAAcI9wjbIgBOAQAAAA==.Panpërse:BAAALAADCggICAAAAA==.Papis:BAAALAADCgcIBwAAAA==.Parisnovotel:BAAALAADCgcIDAAAAA==.Pasteques:BAAALAADCggIFwAAAA==.Patoune:BAAALAAECgcICAAAAA==.',Pe='Pekinexpress:BAAALAAECggICAAAAA==.',Ph='Phasma:BAAALAAECgYIBwABLAAFFAIICgASADkgAA==.Phasmålia:BAAALAAECgcIBwABLAAFFAIICgASADkgAA==.Phâsma:BAAALAADCgcIBwABLAAFFAIICgASADkgAA==.',Pi='Piflya:BAAALAADCggIDQAAAA==.',Pl='Plopute:BAACLAAFFIEKAAIHAAII2yHCBgC5AAAHAAII2yHCBgC5AAAsAAQKgUAAAgcACAjhJE4DAFADAAcACAjhJE4DAFADAAAA.Ploum:BAAALAAECgYIBwAAAA==.Ploumi:BAAALAAECgYIDAAAAA==.',Po='Poeleaheal:BAACLAAFFIEIAAIgAAII8h9xFgC/AAAgAAII8h9xFgC/AAAsAAQKgTgAAiAACAi8IbgMAPACACAACAi8IbgMAPACAAAA.Popotin:BAAALAAECgQICAAAAA==.',Ra='Raghnall:BAAALAADCgIIAgAAAA==.Rambi:BAAALAADCggICAABLAAFFAIICAAIAHwWAA==.Randeng:BAAALAAECgYICQAAAA==.',Re='Redbreath:BAABLAAECoEpAAQXAAgIdSBbBwDYAgAXAAgIdSBbBwDYAgAfAAUIIhCxPAAAAQANAAQIQhCYMADJAAAAAA==.Redvokers:BAAALAAECgcIDQABLAAECggIKQAXAHUgAA==.Rehgård:BAAALAADCggICAABLAAFFAUIEQABAC8bAA==.Reiser:BAAALAAECggIEAABLAAECggIHAAHAP0gAA==.Reyden:BAAALAAECgIIAgAAAA==.',Ro='Rooffe:BAABLAAECoEYAAIQAAcITxt8NQAuAgAQAAcITxt8NQAuAgABLAAECggIGAAZAGAdAA==.',Ru='Rubilax:BAABLAAECoEiAAMSAAcIjB7bDABVAgASAAcIjB7bDABVAgAjAAYILgo9MgAbAQAAAA==.',Ry='Ryze:BAAALAAECgYICwABLAAECggIGgADALQUAA==.',['Rî']='Rîgald:BAAALAADCggILgAAAA==.',Sa='Sabri:BAAALAADCgYIBgAAAA==.Sadako:BAAALAAECgYICAAAAA==.Sadouque:BAAALAAECgUIEwAAAA==.Salzburg:BAAALAAECgYIBgAAAA==.',Sc='Scorpiondoré:BAAALAADCgcIBwAAAA==.',Se='Seekffu:BAAALAAECgIIAwAAAA==.',Sh='Shakano:BAAALAAECgUICAAAAA==.Shingen:BAABLAAECoEYAAIfAAgI9RalFABFAgAfAAgI9RalFABFAgABLAAECggIHAAHAP0gAA==.Shïbakø:BAAALAADCgUIBQAAAA==.',Si='Siffride:BAAALAAECgMIAwAAAA==.',Sk='Skeptgalileo:BAABLAAECoEYAAIEAAgIEyGEFwD0AgAEAAgIEyGEFwD0AgABLAAFFAIICgAJAAgjAA==.Skirner:BAABLAAECoElAAIDAAgIrRs9PQBfAgADAAgIrRs9PQBfAgAAAA==.Sky:BAAALAAECgEIAQAAAA==.Skyshee:BAAALAAECgEIAQAAAA==.',So='Soeurâltà:BAAALAADCgcIDQAAAA==.',St='Stormax:BAAALAAECgQICQAAAA==.',Su='Subzerocool:BAABLAAECoEkAAIHAAcIOBkKJwDIAQAHAAcIOBkKJwDIAQAAAA==.',['Sê']='Sêifer:BAAALAADCgUIBgAAAA==.Sêênsî:BAABLAAECoEVAAIFAAYIJBewiwAuAQAFAAYIJBewiwAuAQAAAA==.',['Sö']='Sörrowz:BAAALAAECggICAAAAA==.',['Sø']='Søà:BAAALAAECggICQAAAA==.',['Sü']='Sünlock:BAAALAADCgMIAwAAAA==.Sünsay:BAAALAADCgIIAgAAAA==.',Ta='Taboune:BAABLAAECoEdAAIRAAcIUAqjbAA9AQARAAcIUAqjbAA9AQAAAA==.Talesse:BAAALAADCgEIAQABLAAECggIOwARAC4SAA==.Tanös:BAAALAADCgMIAwAAAA==.Tarakzul:BAAALAADCgEIAQAAAA==.Tarkalian:BAAALAAECgMIAwAAAA==.',Td='Tdmort:BAAALAAECgYIDAAAAA==.',Te='Telilenn:BAAALAADCgIIAgABLAADCggICAACAAAAAA==.Tessalia:BAAALAADCggIEAAAAA==.',Th='Thyraël:BAAALAADCggIDgAAAA==.',Ti='Tidjani:BAABLAAECoEgAAQTAAgIqQ9IJwCGAQATAAgIqQ9IJwCGAQAbAAQItgrEUADAAAAJAAEItgHrTQEbAAAAAA==.Titleist:BAAALAADCggIFwAAAA==.',To='Tokinooki:BAAALAAECgEIAgAAAA==.Tortueninja:BAAALAADCggICAAAAA==.Touklakos:BAABLAAECoEmAAIfAAgItR0cEwBYAgAfAAgItR0cEwBYAgAAAA==.Touklarkhaos:BAAALAADCgYIBgAAAA==.',Ty='Tyraniss:BAAALAAECgYIDgAAAA==.',['Tä']='Tärentio:BAAALAAECgIIAgAAAA==.',Um='Umbrös:BAABLAAECoEnAAIdAAgIhBvQGwB2AgAdAAgIhBvQGwB2AgAAAA==.',Ur='Urrax:BAAALAAECgYIDAABLAAFFAMICAAXANYPAA==.',Us='Usurpater:BAACLAAFFIEKAAIJAAIICCNkFgDHAAAJAAIICCNkFgDHAAAsAAQKgUoAAgkACAiIJXMFAGkDAAkACAiIJXMFAGkDAAAA.',Va='Valunistar:BAABLAAECoEpAAIgAAgIWwvuSwCCAQAgAAgIWwvuSwCCAQAAAA==.Vanadis:BAACLAAFFIENAAIEAAMIvBjOEAAFAQAEAAMIvBjOEAAFAQAsAAQKgS0AAgQACAjZI6MLADoDAAQACAjZI6MLADoDAAAA.',Ve='Vengeance:BAAALAADCgEIAQAAAA==.',Vi='Victim:BAAALAADCggIFQAAAA==.Vikkos:BAAALAAECgYIDQAAAA==.',['Vë']='Vënøm:BAAALAAECgIIAgAAAA==.',['Vî']='Vîdâlôcâ:BAAALAAECgYIDAAAAA==.Vîgald:BAAALAADCggIHQAAAA==.',Wa='Wakkam:BAAALAAECgYIBwAAAA==.Wakkaï:BAAALAADCggICgAAAA==.Wapz:BAAALAAECgYIEgAAAA==.',We='Welouh:BAAALAAECgEIAQAAAA==.',Wh='Whispaa:BAABLAAECoEgAAIEAAgIsgequgAjAQAEAAgIsgequgAjAQAAAA==.Whisper:BAAALAAECggICgAAAA==.Whitecat:BAAALAAECggICAAAAA==.',Wi='Wiloo:BAAALAAECgMIBAAAAA==.Witsch:BAAALAADCgYIBgAAAA==.',Wo='Wolfiling:BAAALAAECgYIEQAAAA==.Woodland:BAACLAAFFIEIAAIIAAIIfBZgGgCNAAAIAAIIfBZgGgCNAAAsAAQKgS0AAggACAjIHj0XAJYCAAgACAjIHj0XAJYCAAAA.',['Wâ']='Wâtêrfâll:BAAALAADCggIHAAAAA==.',Xe='Xernes:BAABLAAECoEcAAIHAAgI/SA3BwALAwAHAAgI/SA3BwALAwAAAA==.',Ya='Yannoubass:BAAALAADCggIDAABLAAECggIFwAOAJ8ZAA==.',Ym='Ymïr:BAAALAAECgEIAQAAAA==.',Yo='Yobit:BAAALAADCgIIAgAAAA==.Yoirgl:BAAALAAECgYIDwAAAA==.Yoirgll:BAAALAADCggICAAAAA==.Yoirglë:BAAALAADCggICAAAAA==.',Za='Zaacksx:BAAALAAECgYIBwAAAA==.Zayos:BAAALAAECgUIDAAAAA==.',Zk='Zkittlez:BAAALAADCggICgAAAA==.',Zl='Zlatopramen:BAAALAAECgQIBAAAAA==.',Zo='Zock:BAAALAADCggIDgAAAA==.Zogi:BAAALAADCggICAAAAA==.',Zu='Zumajiji:BAAALAAECgYIDwAAAA==.',Zz='Zzeellisback:BAAALAADCgcIBwAAAA==.',['Zâ']='Zâcâpâ:BAABLAAECoEeAAMbAAYIUg7CPgApAQAbAAYIUg7CPgApAQAJAAUIbwil7wDgAAAAAA==.',['Zé']='Zéloth:BAAALAADCgQIBAAAAA==.',['Zø']='Zøkar:BAAALAAECgYICwAAAA==.',['Ãl']='Ãlphã:BAAALAADCggICAABLAAECgcIJAAPAO0QAA==.',['År']='Årchimède:BAAALAAECgQIBgAAAA==.',['Ém']='Émoi:BAAALAADCgEIAQAAAA==.',['Ét']='Étincelle:BAAALAADCgYIBgAAAA==.',['În']='Înorie:BAABLAAECoEcAAIjAAgI5CBlBQD5AgAjAAgI5CBlBQD5AgAAAA==.',['Ðe']='Ðeinos:BAAALAAECggIBwAAAA==.',['Øb']='Øbëlïx:BAAALAADCgIIAgAAAA==.',['ßå']='ßåby:BAAALAAECgYIBgABLAAFFAQICgAQALsZAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end