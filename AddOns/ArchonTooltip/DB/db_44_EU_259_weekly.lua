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
 local lookup = {'Druid-Restoration','Unknown-Unknown','Monk-Windwalker','Mage-Arcane','DeathKnight-Blood','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Paladin-Retribution','Warrior-Fury','Rogue-Outlaw','Druid-Feral','Paladin-Protection','Shaman-Elemental','Evoker-Devastation','Mage-Frost','Warlock-Demonology','Paladin-Holy','DeathKnight-Unholy','Warlock-Destruction','DemonHunter-Vengeance','Mage-Fire','Druid-Balance','Shaman-Restoration','Warrior-Protection','DemonHunter-Havoc','Druid-Guardian','Warlock-Affliction','Hunter-Marksmanship','Warrior-Arms','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival',}; local provider = {region='EU',realm='Azuremyst',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaylara:BAABLAAECoEUAAIBAAcIlxv8KgACAgABAAcIlxv8KgACAgABLAAECggIAwACAAAAAA==.',Ag='Agatone:BAAALAAECgEIAQABLAAECgcIGQADANEaAA==.Aggromuffin:BAAALAAECggIEAAAAA==.Agmax:BAAALAAFFAMIAwAAAA==.',Ak='Akenno:BAAALAADCggIDgAAAA==.',Al='Alakezan:BAACLAAFFIEKAAIEAAMIgRrbFgD8AAAEAAMIgRrbFgD8AAAsAAQKgSMAAgQACAjwH2YYAN8CAAQACAjwH2YYAN8CAAAA.Alarica:BAAALAADCggIDwAAAA==.Alexandro:BAAALAAECgQIBAABLAAECgcIJgAFAAMlAA==.Alira:BAAALAADCgYIBgAAAA==.Aliyan:BAAALAADCgIIAgAAAA==.Alizra:BAAALAAECgYIEgAAAA==.Allvarus:BAAALAADCggIDQAAAA==.Aloneintokyo:BAAALAAECgIIAgABLAAECgYICwACAAAAAA==.',Am='Amaliã:BAAALAADCggICAAAAA==.Amarie:BAAALAAECgMIBAAAAA==.Ammut:BAAALAAECgQIBAAAAA==.',An='Annao:BAAALAAECgEIAgAAAA==.Antygona:BAAALAADCggICAAAAA==.',Ar='Arcanyx:BAAALAADCggICAAAAA==.Aredhel:BAABLAAECoEsAAIGAAgI5h1YNABAAgAGAAgI5h1YNABAAgAAAA==.Artus:BAAALAAECgYIBgAAAA==.',As='Asmodan:BAAALAAECgMIAwAAAA==.Astrafox:BAAALAADCggIDgAAAA==.Astria:BAAALAAECgEIAQAAAA==.',At='Ateist:BAACLAAFFIEIAAIHAAMIuQtuEQDaAAAHAAMIuQtuEQDaAAAsAAQKgSUAAwcACAglHKwXAJACAAcACAglHKwXAJACAAgABggjDDtRAEQBAAAA.',Av='Avelline:BAABLAAECoEoAAIGAAgIThqMOAAwAgAGAAgIThqMOAAwAgAAAA==.',Aw='Awu:BAAALAAECgUIBwABLAAECgYIFQAJANkeAA==.',Ax='Axl:BAAALAAECgMIBgAAAA==.',Az='Azhag:BAABLAAECoEdAAIKAAgIURvYMwB5AgAKAAgIURvYMwB5AgAAAA==.',Ba='Bababooey:BAAALAAECgEIAQAAAA==.Baelim:BAAALAAECggICAAAAA==.Baki:BAAALAADCggIDwABLAAECgYIEwACAAAAAA==.Bal:BAAALAAECggIDwAAAA==.Baonty:BAAALAADCggICAAAAA==.Barrom:BAAALAADCggIDwAAAA==.Basadin:BAAALAADCgYIBgAAAA==.Basseele:BAAALAAECgUIDAABLAAECggICQACAAAAAA==.',Be='Bearcareful:BAAALAAECgYIEAAAAA==.Beastfall:BAAALAADCgcIBwAAAA==.Beldri:BAAALAAECgcIDgAAAA==.Bellzar:BAAALAADCgcIBwABLAAECggIJAALAGcWAA==.Berserk:BAABLAAECoEXAAIMAAcI+xIbUwC0AQAMAAcI+xIbUwC0AQAAAA==.',Bi='Bii:BAACLAAFFIESAAMIAAUI4xJPBgCbAQAIAAUI4xJPBgCbAQAHAAEIkADsNAAxAAAsAAQKgRwAAwgABwiKHUIjADcCAAgABwiKHUIjADcCAAcABAiYBtWBALMAAAAA.Birta:BAABLAAECoEkAAIIAAgIhRgiIABOAgAIAAgIhRgiIABOAgAAAA==.Biscuits:BAAALAADCgMIAwAAAA==.',Bj='Björnbus:BAAALAADCgMIBQAAAA==.Bjørn:BAAALAAECgcIBwAAAA==.',Bl='Blackthorne:BAAALAAECggIDgAAAA==.',Bo='Boldy:BAAALAADCggIDgAAAA==.Bonebroken:BAAALAADCggIEgAAAA==.Bonusbuff:BAAALAADCggIEwAAAA==.Borrie:BAAALAADCggICAABLAAECggIIgANAPcdAA==.Borryblast:BAAALAADCgcIBwABLAAECggIIgANAPcdAA==.Borrydk:BAAALAAECgIIAgABLAAECggIIgANAPcdAA==.Bowme:BAABLAAECoEUAAIMAAcIAwU5jQACAQAMAAcIAwU5jQACAQAAAA==.',Br='Bry:BAAALAADCgcIBwAAAA==.Brítneyfeárs:BAACLAAFFIEHAAIIAAMIpRiEDADzAAAIAAMIpRiEDADzAAAsAAQKgSAAAwgACAh6IuIJABgDAAgACAh6IuIJABgDAAcAAQh+Bc+gADEAAAAA.',Bu='Buffyflewbs:BAABLAAECoEUAAILAAYI/BOhmwB+AQALAAYI/BOhmwB+AQAAAA==.',['Bö']='Böbcat:BAAALAADCgQIBAABLAAECgIIAgACAAAAAA==.',Ca='Calix:BAABLAAECoEXAAIOAAgIjhBFFQDaAQAOAAgIjhBFFQDaAQAAAA==.Cameow:BAAALAADCgcIDQAAAA==.Castellan:BAAALAADCggICAABLAAECggIJQAPAPIRAA==.Caylum:BAAALAADCgcICwABLAAECgYIFgAGAO8dAA==.',Cd='Cdevilfish:BAAALAADCggICAAAAA==.',Ce='Ceesayby:BAAALAADCgUIBQAAAA==.Celimbrimbor:BAABLAAECoEXAAIGAAYILBHjkwBJAQAGAAYILBHjkwBJAQABLAAECggIGwAQAA8JAA==.',Ch='Chat:BAAALAADCgMIBAABLAAFFAYIEQARAKsYAA==.Chemosh:BAABLAAECoEfAAISAAcIcyOGDACxAgASAAcIcyOGDACxAgAAAA==.',Ci='Cinema:BAAALAAFFAIIBAAAAA==.',Cl='Clevster:BAABLAAECoEnAAITAAgItyZMAACRAwATAAgItyZMAACRAwAAAA==.',Co='Cocojumbo:BAAALAAECgcIBwAAAA==.Cofejjarr:BAAALAADCggIEAABLAAECgYICAACAAAAAA==.Cofelock:BAAALAADCggIGwABLAAECgYICAACAAAAAA==.Coffejar:BAAALAAECgYICAAAAA==.Copies:BAAALAADCggIEAAAAA==.',Ct='Cthon:BAAALAAECgIIAgABLAAECgcIHQAGAEQZAA==.',Cu='Cujek:BAAALAAECggICAAAAA==.Currykungen:BAAALAADCgYIBgAAAA==.Curryson:BAAALAADCggICAAAAA==.',['Cé']='Célés:BAACLAAFFIEKAAIUAAMIMCT9BQBFAQAUAAMIMCT9BQBFAQAsAAQKgSMAAhQACAjdJC8BAFIDABQACAjdJC8BAFIDAAAA.',Da='Daemonic:BAAALAADCggICgAAAA==.Daniellos:BAAALAADCgYIBgAAAA==.Darkmaster:BAAALAADCgIIAgAAAA==.Darling:BAABLAAECoEmAAIKAAgIExjjPgBUAgAKAAgIExjjPgBUAgAAAA==.',De='Demolision:BAABLAAECoEoAAMFAAgIxhv9CQCJAgAFAAgIxhv9CQCJAgAVAAII0wYhSwBaAAAAAA==.Demolisious:BAAALAAECgYIDAABLAAECggIKAAFAMYbAA==.Desdemora:BAABLAAECoEVAAMVAAYI4x0bEwAXAgAVAAYI4x0bEwAXAgAKAAIIsBEBJwFsAAAAAA==.Destrospoon:BAABLAAECoEtAAMTAAgIBiPrBAABAwATAAgIdiLrBAABAwAWAAgI+hsuIQCcAgAAAA==.Destructon:BAAALAAECggIEAAAAA==.',Di='Dirkpitt:BAAALAADCgEIAgAAAA==.',Dr='Dracena:BAAALAAECgMIBAABLAAECggIKAAFAMYbAA==.Draenier:BAABLAAECoElAAIPAAgI8hE2IACzAQAPAAgI8hE2IACzAQAAAA==.Dreklay:BAAALAAECgYICgAAAA==.',Du='Dudububz:BAABLAAECoEXAAIQAAYIyiEZKgA9AgAQAAYIyiEZKgA9AgAAAA==.Duggu:BAAALAAECgcIEgABLAAECgcIJgAFAAMlAA==.Dugguxii:BAABLAAECoEmAAIFAAcIAyVkBgDeAgAFAAcIAyVkBgDeAgAAAA==.Durinaz:BAAALAADCgEIAQAAAA==.',Dw='Dwolk:BAAALAADCggIDwAAAA==.',['Dí']='Dína:BAABLAAECoEWAAIGAAYI7x0lTQDtAQAGAAYI7x0lTQDtAQAAAA==.',['Dó']='Dóakey:BAAALAADCggIDQAAAA==.',Ea='Eallara:BAAALAAFFAEIAQAAAA==.',El='Elelia:BAAALAAECggIDQAAAA==.Elitebih:BAAALAAECggIBwAAAA==.Elriel:BAAALAAECgYICAAAAA==.Elviass:BAAALAAECggICQAAAA==.Elvisbacon:BAAALAAECgUIBgAAAA==.Elíza:BAABLAAECoEkAAIWAAgIDBq8KQBrAgAWAAgIDBq8KQBrAgAAAA==.',Em='Embery:BAAALAAECgcIDgAAAA==.',['Eø']='Eøs:BAAALAADCgIIAgAAAA==.',Fa='Faereen:BAAALAADCggICAABLAAFFAYIGAABAK0iAA==.Faerion:BAAALAADCggICAABLAAFFAYIGAABAK0iAA==.Fareon:BAACLAAFFIEYAAIBAAYIrSKeAABrAgABAAYIrSKeAABrAgAsAAQKgRcAAgEACAiCIj4OAMMCAAEACAiCIj4OAMMCAAAA.Farithh:BAAALAADCggIEQAAAA==.Farky:BAAALAADCgIIAgAAAA==.Farrith:BAAALAAECgIIAgAAAA==.',Fe='Feldari:BAAALAAECgEIAQAAAA==.Felnight:BAAALAAECgYIBgABLAAECggIHwAXANYXAA==.Feroz:BAAALAAECgUIBQABLAAFFAYIGAABAK0iAA==.',Fi='Fierynoodle:BAAALAAECgcICwAAAA==.Fizziepop:BAAALAADCggIGQAAAA==.',Fl='Flatwhite:BAABLAAECoEUAAMEAAcIAxr8SAAGAgAEAAcIWBf8SAAGAgAYAAQIDg2XDgDrAAAAAA==.Flayem:BAAALAAECgYIDAAAAA==.Fliplock:BAAALAADCggIEAAAAA==.Flippala:BAABLAAECoEhAAMLAAgIfBnvQQBGAgALAAgIfBnvQQBGAgAUAAQIpAOyUgChAAAAAA==.Flipperboy:BAAALAADCggIBwAAAA==.Flippoker:BAAALAADCgMIAwAAAA==.Fluffytaco:BAAALAAECgYIBgABLAAECggIHQAKAFEbAA==.',Fo='Fora:BAAALAADCgUIBQAAAA==.',Fr='Frag:BAAALAAECgEIAgAAAA==.Frankherbert:BAAALAADCgYIBgAAAA==.Frieren:BAAALAAECgIIAgAAAA==.Fristy:BAABLAAECoEbAAIIAAgIFhEALgDyAQAIAAgIFhEALgDyAQAAAA==.',Fu='Fu:BAABLAAECoEhAAIDAAgIqRyHDgCPAgADAAgIqRyHDgCPAgAAAA==.Furliss:BAAALAAECggIDgAAAA==.Fuzzywuzzy:BAAALAAECgYIEwAAAA==.',['Fù']='Fù:BAAALAADCggICAABLAAECggIIQADAKkcAA==.',Ga='Gastromix:BAABLAAECoEWAAMZAAYIEAqmVQAcAQAZAAYIEAqmVQAcAQABAAIIVwnBqwBHAAAAAA==.Gay:BAAALAAECgEIAQAAAA==.',Ge='Gerrardnoone:BAABLAAECoEWAAMLAAYIjRqwbADZAQALAAYIjRqwbADZAQAPAAQI7wv4QwC0AAAAAA==.',Gh='Ghumbie:BAAALAADCggICAAAAA==.',Gi='Gio:BAAALAADCgcIDQAAAA==.',Go='Goodnight:BAAALAADCggICwAAAA==.Gorion:BAABLAAECoEZAAIXAAcIHCOJBwDBAgAXAAcIHCOJBwDBAgABLAAECgcIJgAFAAMlAA==.Gork:BAAALAAECgYIEAAAAA==.Goy:BAAALAADCgYICQAAAA==.',Gr='Gracie:BAABLAAECoEbAAIQAAcIXxJoQwDDAQAQAAcIXxJoQwDDAQAAAA==.Greer:BAAALAADCggIGgAAAA==.Greertv:BAACLAAFFIEHAAIKAAIImhOQRQCOAAAKAAIImhOQRQCOAAAsAAQKgRcAAgoABwgaIHhGAD4CAAoABwgaIHhGAD4CAAAA.',Gu='Gup:BAAALAAFFAIIAgAAAA==.Gurligris:BAAALAADCggICAAAAA==.',Ha='Hakuren:BAABLAAECoEkAAIPAAgIkSOUAwA5AwAPAAgIkSOUAwA5AwAAAA==.Halz:BAAALAAECggICgAAAA==.Hasturian:BAAALAADCgYIBgAAAA==.Hasturist:BAAALAAECggIEwAAAA==.Havs:BAAALAADCgcIEQABLAADCggIDgACAAAAAA==.Havsdeam:BAAALAADCggIDgAAAA==.Havumetted:BAAALAAECgQIBAABLAAECggIJAAaAC4gAA==.',Hi='Hihihihi:BAAALAAECgEIAQAAAA==.',Hu='Huehuehhue:BAAALAADCgEIAQAAAA==.Hunterskills:BAAALAADCgcIBwAAAA==.Hunttopia:BAAALAADCgIIAgAAAA==.Hunttrex:BAAALAADCggIGwAAAA==.Hurm:BAAALAAECgYIDQAAAA==.',Hy='Hydreigon:BAAALAADCggIEAAAAA==.',Ic='Icekizz:BAABLAAECoEkAAIHAAgIiwvcRwCMAQAHAAgIiwvcRwCMAQAAAA==.',Il='Illit:BAAALAAECgIIAwAAAA==.',In='Injured:BAAALAAECggICAAAAA==.Inmedk:BAABLAAECoEQAAMKAAgISx13LQCSAgAKAAgISx13LQCSAgAFAAEIXgeOPwApAAABLAAFFAMICAAZAEAKAA==.Inquis:BAAALAAECgIIAgAAAA==.',Ir='Iriak:BAAALAADCggICAAAAA==.Irydion:BAAALAAECgYICgAAAA==.',Is='Ishtarion:BAAALAAECgEIAgAAAA==.Ismere:BAAALAADCgIIAgABLAAECggIDQACAAAAAA==.',Ja='Jaeger:BAAALAAECgMIBQAAAA==.',Je='Jenn:BAAALAADCggICAABLAAECgcIEwACAAAAAA==.',Ji='Jishin:BAAALAAECgIIAgAAAA==.',Jo='Jolia:BAAALAAECgYICQABLAAECggICAACAAAAAA==.Joob:BAAALAAECgYIBgAAAA==.Jovanasi:BAAALAAECgEIAgAAAA==.',['Jó']='Jónus:BAAALAADCgYIBgAAAA==.',Ka='Kaelyr:BAABLAAECoEdAAIaAAgIaxqJJgBOAgAaAAgIaxqJJgBOAgAAAA==.Kahmu:BAAALAADCgcIDQAAAA==.Kaidø:BAAALAAECgcIDQAAAA==.Karengosa:BAAALAADCggIFAAAAA==.Karub:BAABLAAECoEfAAIbAAcIkwy1OwBFAQAbAAcIkwy1OwBFAQAAAA==.Kasteld:BAABLAAECoEoAAIaAAgIgRjbKQBBAgAaAAgIgRjbKQBBAgAAAA==.Katsi:BAABLAAECoEUAAIGAAYIPhVndACKAQAGAAYIPhVndACKAQAAAA==.',Ke='Keket:BAABLAAECoEWAAITAAcIORMCIwDPAQATAAcIORMCIwDPAQAAAA==.Ketanako:BAABLAAECoEhAAIVAAgIrh+VBgDeAgAVAAgIrh+VBgDeAgAAAA==.',Ki='Kiro:BAAALAADCgIIAgAAAA==.',Kk='Kkerr:BAAALAAECgEIAgAAAA==.',Kn='Knitingale:BAAALAAECgcICQAAAA==.',Ko='Kopimage:BAABLAAECoEkAAIEAAgICB8oIAC2AgAEAAgICB8oIAC2AgABLAAECggIJAAHAIsLAA==.Kopster:BAAALAADCgYIBgABLAAECggIJAAHAIsLAA==.Koradji:BAAALAADCggICQAAAA==.',Kr='Kragok:BAAALAAECgIIBAAAAA==.Kraytosz:BAAALAAECgQIBAAAAA==.',Ku='Kuchidh:BAACLAAFFIEIAAIcAAMIXxP4EQDxAAAcAAMIXxP4EQDxAAAsAAQKgSIAAhwACAhvIdwSAAsDABwACAhvIdwSAAsDAAAA.Kuchimage:BAAALAADCgYIBgABLAAFFAMICAAcAF8TAA==.Kurojii:BAAALAADCgMIAwAAAA==.Kurtie:BAAALAADCgcIBwAAAA==.Kurtié:BAAALAADCgEIAQABLAADCgcIBwACAAAAAA==.',Ky='Kyutoryuzoro:BAAALAADCgYIBgAAAA==.',La='Ladasha:BAAALAAECggIDgABLAAFFAYICwAEAJYWAA==.Lazarion:BAABLAAECoEWAAIGAAYI/RGjjwBRAQAGAAYI/RGjjwBRAQAAAA==.Lazek:BAABLAAECoEXAAIGAAcIlQ/NdwCDAQAGAAcIlQ/NdwCDAQAAAA==.',Le='Leandra:BAAALAADCggIFQAAAA==.Leijóna:BAABLAAECoEdAAMJAAgIIguZDwBzAQAJAAgIIguZDwBzAQAHAAEIhgFkqgAVAAAAAA==.Lerouge:BAAALAADCggIDAAAAA==.Lexå:BAAALAADCgQIBgAAAA==.',Li='Lightbeard:BAAALAADCggICAABLAAFFAUIDQALAFgaAA==.Lighttrooper:BAAALAAECgQIBAAAAA==.Lighttside:BAAALAADCgMIAwAAAA==.Lipinizzi:BAAALAAECgYICgAAAA==.Lirishax:BAAALAAECgUICAAAAA==.Lisstwo:BAAALAAECgYIBgABLAAECggIDgACAAAAAA==.',Ll='Llabnalla:BAABLAAECoEbAAIGAAgIXBGgYAC4AQAGAAgIXBGgYAC4AQAAAA==.',Lo='Loralia:BAAALAAECgYICAAAAA==.Loudair:BAAALAAECgQIBAAAAA==.Loveslove:BAABLAAECoEVAAITAAgInQO4SAAiAQATAAgInQO4SAAiAQAAAA==.',Lu='Lucil:BAABLAAECoEaAAMPAAcI8RWNJQCIAQAPAAcIyxKNJQCIAQALAAQIsRc35gDmAAAAAA==.Lucitia:BAAALAAECgQIBAABLAAECgcIHQAGAEQZAA==.Lucivar:BAABLAAECoEZAAMLAAcIqRTiZwDkAQALAAcIqRTiZwDkAQAPAAEI0QVvXwAmAAABLAAECggIKAAFAMYbAA==.Lunashade:BAABLAAECoEjAAMOAAgIcxgMDgBBAgAOAAgIcxgMDgBBAgAZAAMIdwukdACCAAAAAA==.Luntytbh:BAAALAAFFAIIBAAAAA==.Luná:BAAALAADCggIDwABLAAECggIJAAWAAwaAA==.',Ly='Lyktan:BAABLAAECoElAAIdAAgI+xj4BwA4AgAdAAgI+xj4BwA4AgAAAA==.',['Lø']='Løvblåser:BAAALAAECggIEAAAAA==.',Ma='Madspedersen:BAAALAADCgYIBgAAAA==.Mageffic:BAABLAAECoEpAAIEAAgIbxnILgBuAgAEAAgIbxnILgBuAgAAAA==.Magestix:BAAALAAECgYIBgABLAAFFAYIGQAFAAMdAA==.Mansk:BAAALAADCggIDwAAAA==.Martonionlux:BAAALAADCggIGAAAAA==.Maëllys:BAABLAAECoEbAAIcAAcIuR5zKwCEAgAcAAcIuR5zKwCEAgAAAA==.Maÿhem:BAAALAAECgIIAwAAAA==.',Me='Menibanni:BAAALAAECgYIEQAAAA==.',Mi='Microvlot:BAAALAAECgYIEwAAAA==.Mieka:BAAALAAECgEIAgABLAAECgcIHQAGAEQZAA==.Mightythrall:BAAALAADCgUIBQAAAA==.Mileyscythe:BAACLAAFFIEMAAQKAAMIbB56EgAKAQAKAAMIsRp6EgAKAQAFAAMI0BvcBAAJAQAVAAEIKx/MEwBbAAAsAAQKgRgAAwUACAgzIT0JAJoCAAUACAiOID0JAJoCAAoABgiDHovCAEcBAAEsAAUUCAgVAAoAiCQA.',Mj='Mjos:BAACLAAFFIEOAAQWAAQIkhoGDgBtAQAWAAQIkhoGDgBtAQAeAAEIsA9mBABcAAATAAEIvQh2IwBKAAAsAAQKgSAABBYACAhjJAQOABoDABYACAiAIwQOABoDAB4ABAjvIJITAGIBABMABAhmIF5EADYBAAAA.Mjölnir:BAAALAADCgcICgAAAA==.',Mo='Monkeymind:BAAALAAECgcIDQAAAA==.Mooberry:BAAALAAECgYIDAAAAA==.Mordale:BAAALAAECggIDQAAAA==.Mordollwen:BAAALAADCggIGAAAAA==.Mothem:BAAALAAECgYIDAAAAA==.',Mt='Mtfgamer:BAAALAADCgcICwAAAA==.',My='Mysec:BAACLAAFFIEIAAIBAAIIJSB8EQC7AAABAAIIJSB8EQC7AAAsAAQKgRwAAgEABgjPI2kaAGECAAEABgjPI2kaAGECAAAA.',['Mé']='Mégaira:BAAALAAECgEIAQAAAA==.',Na='Naras:BAAALAAECgUIBAABLAAECgcIEwACAAAAAA==.Navier:BAABLAAECoEVAAMdAAcIBQmoFwAXAQAdAAcIDQioFwAXAQAZAAIIQw2NfQBfAAAAAA==.Nayah:BAABLAAECoEaAAIBAAYIDxKBWQBAAQABAAYIDxKBWQBAAQAAAA==.',Ne='Necropium:BAAALAADCgcIBwAAAA==.',Ni='Nibbø:BAABLAAECoEmAAIeAAgIvh0tAwDJAgAeAAgIvh0tAwDJAgAAAA==.Nimerya:BAABLAAECoEZAAIKAAcIQweFxABEAQAKAAcIQweFxABEAQAAAA==.Nivek:BAAALAAECgMIAwABLAAECggIKAAFAMYbAA==.',No='Nonesovile:BAABLAAECoEdAAIEAAcI0x1bMwBaAgAEAAcI0x1bMwBaAgAAAA==.Noorke:BAAALAAECgIIAgAAAA==.Nopsalock:BAAALAADCgcIBwAAAA==.Noryxith:BAAALAADCggIDwAAAA==.Novareaper:BAAALAAECggICAAAAA==.',Nu='Nubbish:BAAALAADCgEIAQAAAA==.',Ny='Nyehehe:BAAALAAECgQIBAAAAA==.',['Nú']='Núgzz:BAABLAAECoEkAAIQAAgIdCAiEQDuAgAQAAgIdCAiEQDuAgAAAA==.',Og='Ogmalog:BAAALAAECgEIAgAAAA==.',Op='Ophelhia:BAAALAADCgUIBQAAAA==.',Or='Oranges:BAAALAADCggICAAAAA==.',Os='Osferth:BAABLAAECoEgAAITAAcIrRWXHgDpAQATAAcIrRWXHgDpAQAAAA==.',Pa='Pallasathene:BAAALAADCgcIDQAAAA==.Pallygoat:BAAALAADCggICAABLAAECgYIFgAGAO8dAA==.Pandàmonium:BAAALAAECgYICQAAAA==.Panicore:BAAALAAECgYIDAAAAA==.Pavwo:BAAALAAECgMIBQAAAA==.',Pi='Picerusonix:BAAALAAECgUICAABLAAFFAQIBAACAAAAAA==.Pippuri:BAAALAADCgQIBAAAAA==.',Pl='Plainrenew:BAAALAADCggIDwABLAAECggIJAAfAHoiAA==.Plainview:BAABLAAECoEkAAMfAAgIeiItGQCBAgAfAAcIqCEtGQCBAgAGAAYIpRy2TADuAQAAAA==.Plonk:BAAALAADCgYIBgAAAA==.Plop:BAAALAAECgcIEwAAAA==.',Po='Poottle:BAAALAAECgEIAgAAAA==.Poprose:BAAALAADCgYICQAAAA==.',Pr='Priskù:BAAALAADCgcIBwAAAA==.Proclusangel:BAAALAAECgIIBQAAAA==.',Qu='Quylsta:BAAALAAECgIIAgAAAA==.',Ra='Ragamuffinb:BAAALAAECgEIAQAAAA==.Ragamuffinc:BAAALAADCggICAAAAA==.Ragamuffind:BAAALAADCggICQAAAA==.Raidium:BAAALAAFFAIIAgAAAQ==.Razorslock:BAABLAAECoEWAAIWAAcIhgjxdQBXAQAWAAcIhgjxdQBXAQAAAA==.Razsalgul:BAABLAAECoEoAAMTAAgIDyMTHgDtAQATAAUIMyQTHgDtAQAWAAUIDCHdVgCxAQAAAA==.',Re='Redstagger:BAAALAAECgMIBAAAAA==.Rekinbull:BAAALAAECggICAAAAA==.',Rh='Rheanyraa:BAAALAADCgEIAQAAAA==.Rhine:BAABLAAECoEWAAMMAAYIlCMCKABoAgAMAAYIlCMCKABoAgAgAAEIkiOlKgBkAAAAAA==.',Ri='Rillarosa:BAAALAAECgYIDgAAAA==.Ripson:BAAALAAECgYICgAAAA==.',Ro='Rottan:BAAALAADCgQIBAABLAAECggIJQAdAPsYAA==.',Ru='Ruffepuffe:BAABLAAECoEkAAMPAAcIOhvHEwAnAgAPAAcIOhvHEwAnAgALAAcISxLPiAChAQAAAA==.Ruin:BAAALAAECgYIBwABLAAFFAUIDgAKAJwcAA==.',Ry='Ryoku:BAAALAAECgYIDAAAAA==.',Se='Seasalts:BAAALAADCgYICwAAAA==.Sebasalfie:BAAALAADCgcICgAAAA==.Semlan:BAAALAAECgYICgABLAAECggIHQAJACILAA==.Senara:BAAALAADCggIHQAAAA==.',Sh='Shaloom:BAAALAADCggIEwAAAA==.Shinx:BAAALAAECgMIAwAAAA==.Shuriken:BAAALAADCgQIBAAAAA==.',Si='Silvercurse:BAAALAADCgcIDAAAAA==.Simbalu:BAAALAADCgQIAgAAAA==.Sixpacc:BAAALAADCggIEwAAAA==.',Sk='Skruxy:BAAALAAECgYICAABLAAFFAIIAgACAAAAAA==.Skychaser:BAABLAAECoEbAAIQAAgIDwnjXQBkAQAQAAgIDwnjXQBkAQAAAA==.',Sl='Sleepy:BAAALAAECggICAAAAA==.',Sm='Sminted:BAAALAAECgEIAgAAAA==.',Sn='Sneakyborry:BAABLAAECoEiAAINAAgI9x3iAgDIAgANAAgI9x3iAgDIAgAAAA==.',So='Soapytw:BAAALAAECgEIAQAAAA==.Soulavenger:BAAALAADCggICAAAAA==.Soulevoker:BAABLAAECoEcAAMhAAgI1hPsBQANAgAhAAgI1hPsBQANAgAiAAEIOgf1NwArAAAAAA==.Soulsavior:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.',Sp='Speiredonia:BAAALAADCgcICAAAAA==.',St='Stormez:BAAALAAECggICAAAAA==.Stormsorrow:BAAALAADCgYIBgAAAA==.',Su='Summy:BAACLAAFFIELAAIEAAYIlhb3BAAJAgAEAAYIlhb3BAAJAgAsAAQKgSIAAwQACAg3IhgcAMwCAAQACAgiIhgcAMwCABIAAwgnFrllAIQAAAAA.',Sw='Swifttiffany:BAABLAAECoEkAAMaAAgILiBFEwC4AgAaAAgILiBFEwC4AgAQAAcIDQ9OSQCsAQAAAA==.',Sy='Sylve:BAAALAAECggICAAAAA==.',Ta='Tadmoh:BAAALAADCggICAAAAA==.',Td='Tdevilfish:BAABLAAECoEYAAIUAAgIzxqxDgB7AgAUAAgIzxqxDgB7AgAAAA==.',Te='Tenshó:BAAALAADCgcIBwABLAAECggIJAAPAJEjAA==.Terrorglaive:BAABLAAECoEeAAIcAAgIZBVWRwAZAgAcAAgIZBVWRwAZAgAAAA==.',Th='Thuba:BAAALAADCggICgAAAA==.',Ti='Tink:BAAALAADCggIGAAAAA==.Tiotis:BAABLAAECoEWAAIEAAYIvguUiABLAQAEAAYIvguUiABLAQAAAA==.',To='Tofu:BAAALAADCggICAABLAAECggIHQAKAFEbAA==.',Tr='Trebold:BAAALAADCgIIAgAAAA==.',Tu='Turaath:BAAALAAECgUICwAAAA==.',Ul='Ulir:BAAALAAECgQIAwAAAA==.',Uz='Uzu:BAABLAAECoEhAAMGAAgIZRPnTwDlAQAGAAgIZRPnTwDlAQAfAAEItga5rgAtAAAAAA==.',Va='Vaccine:BAAALAAECgIIBAAAAA==.Valeryah:BAABLAAECoESAAIjAAYISBGkDgCIAQAjAAYISBGkDgCIAQAAAA==.Valsa:BAAALAADCgMIAwAAAA==.',Ve='Veidec:BAAALAADCgcIBwAAAA==.Vexxen:BAAALAAECggIDQAAAA==.',Vi='Viccky:BAAALAAECgYICwAAAA==.Vinara:BAAALAADCgEIAQAAAA==.',Vu='Vuurdoop:BAAALAADCgYIBgAAAA==.',Wa='Wabiskai:BAABLAAECoEZAAIKAAcIhxHzfQC/AQAKAAcIhxHzfQC/AQAAAA==.Warbornlock:BAAALAAECgYIBgAAAA==.Warorr:BAAALAADCggICAAAAA==.Warriorsas:BAAALAAECgIIAgAAAA==.Warrmann:BAAALAADCgcIBwAAAA==.Warthun:BAAALAADCggIFgAAAA==.',Wh='What:BAAALAADCggICgABLAAECgYIFAALAPwTAA==.',Wi='Wiccaa:BAAALAAECgYICgAAAA==.',Wo='Woudk:BAAALAADCggIEAAAAA==.Wox:BAAALAADCggIDwABLAAECgcIHQAGAEQZAA==.',['Wë']='Wëlkín:BAAALAADCggICAAAAA==.',Xa='Xandhorian:BAAALAAECggIEgAAAA==.Xaviera:BAABLAAECoEkAAIPAAgIvhtEDwBaAgAPAAgIvhtEDwBaAgAAAA==.',Xg='Xgén:BAABLAAECoEWAAMPAAYIoBIPLgBJAQAPAAYIoBIPLgBJAQAUAAEIVBnwYABEAAAAAA==.',Xt='Xtal:BAAALAAECgEIAQAAAA==.',Ya='Yasmin:BAAALAADCggICAAAAA==.Yastepdaa:BAAALAAECgEIAQAAAA==.',Ye='Yeat:BAAALAAECgEIAQAAAA==.Yesugei:BAABLAAECoEZAAIDAAcI0RoqFQA5AgADAAcI0RoqFQA5AgAAAA==.',Yo='Yoghe:BAAALAADCgQIBAAAAA==.Yomifour:BAAALAAECgEIAQABLAAFFAYIFAABAMkYAA==.',Za='Zaafira:BAABLAAECoEkAAILAAgIZxZjSgAtAgALAAgIZxZjSgAtAgAAAA==.',Ze='Zekrom:BAAALAADCgYIBgAAAA==.',Zi='Zilark:BAAALAAECgYIBgAAAA==.Zimerion:BAABLAAECoEcAAIRAAcI5BJpJADSAQARAAcI5BJpJADSAQAAAA==.',Zu='Zugfu:BAAALAAECggICAAAAA==.Zultax:BAAALAAECggIDAAAAA==.',['Ån']='Ånaire:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end