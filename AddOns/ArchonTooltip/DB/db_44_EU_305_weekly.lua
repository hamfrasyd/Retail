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
 local lookup = {'DemonHunter-Havoc','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Affliction','Warlock-Destruction','Warrior-Protection','DeathKnight-Frost','Druid-Balance','Rogue-Assassination','Monk-Windwalker','Unknown-Unknown','Monk-Brewmaster','Monk-Mistweaver','DeathKnight-Blood','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Priest-Shadow','Priest-Discipline','Druid-Restoration','Paladin-Protection','Rogue-Subtlety','Paladin-Retribution','Warrior-Fury','DemonHunter-Vengeance','Mage-Frost','Druid-Guardian','Shaman-Elemental','Mage-Fire','DeathKnight-Unholy',}; local provider = {region='EU',realm='Khadgar',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abcd:BAAALAADCggIJgABLAAECgcIGQABAKwbAA==.',Ac='Acina:BAAALAAECgIIAgAAAA==.',Ae='Aeonyan:BAAALAAECgYIBgABLAAECggIJQACAGMbAA==.',Ai='Aiming:BAACLAAFFIEIAAMDAAMIyhrfCwDkAAADAAMIyhrfCwDkAAAEAAIIFhkAAAAAAAAsAAQKgSUAAwMACAgZI3wIABgDAAMACAgZI3wIABgDAAQAAwhJCsTfAIsAAAAA.Aithir:BAAALAAECgMIAwAAAA==.',Al='Alanz:BAABLAAECoEZAAMFAAYIphYfDwCiAQAFAAYI9BUfDwCiAQAGAAIIpRXzuAB+AAAAAA==.Alcarinquë:BAAALAAECgYIBgAAAA==.Alfwar:BAABLAAECoEVAAIHAAcI2xbAJwC9AQAHAAcI2xbAJwC9AQAAAA==.Aljazi:BAAALAADCggIDgAAAA==.Altemo:BAAALAADCggIGwAAAA==.',Am='Amaranthes:BAAALAAECgYIDAAAAA==.Ambrosios:BAABLAAECoEeAAIIAAYIoR7EZQDwAQAIAAYIoR7EZQDwAQAAAA==.',An='Angëlbaby:BAAALAADCgQIBAAAAA==.Annanninai:BAAALAADCgYIBgAAAA==.Anodir:BAAALAAECgIIAgAAAA==.Ansuz:BAABLAAECoEVAAIBAAgIOhWiVwDrAQABAAgIOhWiVwDrAQAAAA==.Anun:BAABLAAECoEkAAIJAAcIoCDtFQCGAgAJAAcIoCDtFQCGAgAAAA==.',Ar='Arkill:BAABLAAECoEUAAIKAAYIQQ1ZNwBrAQAKAAYIQQ1ZNwBrAQAAAA==.Arèon:BAABLAAECoEgAAILAAcINyJbDACuAgALAAcINyJbDACuAgAAAA==.',As='Ashimat:BAAALAADCgcIDgAAAA==.',Av='Avoidwings:BAAALAAECgIIAgAAAA==.',Ay='Ayasha:BAAALAADCggIEgAAAA==.',Ba='Badgerclaw:BAAALAAECgUICwAAAA==.Badseed:BAAALAAECgUICwAAAA==.Balboola:BAAALAADCggIHAAAAA==.Balerion:BAAALAADCgcIBwAAAA==.Bandagespex:BAAALAAECgYICAABLAAECgYIDAAMAAAAAA==.Barrbjörn:BAAALAAECgQICgAAAA==.',Be='Beasttamer:BAAALAAECgYIDgAAAA==.Behegor:BAAALAADCggICAAAAA==.Behemight:BAABLAAECoEhAAIHAAgIjyIEBgAeAwAHAAgIjyIEBgAeAwAAAA==.',Bi='Biodriud:BAAALAADCggIFQAAAA==.',Bl='Bladesmith:BAABLAAECoEnAAQNAAgI1BghDwA0AgANAAgI1BghDwA0AgAOAAUIVwP1OgCIAAALAAIIaAzGSgB5AAAAAA==.Blames:BAAALAADCgIIAgABLAAECggICQAMAAAAAA==.Blöodshot:BAAALAAECgcIBQAAAA==.',Bo='Boldi:BAAALAADCgYIBwAAAA==.Bombastic:BAAALAAECgQIBQABLAAFFAMIBwAPAEUbAA==.Bomshakalaka:BAAALAAECgMIBgAAAA==.Booss:BAAALAADCggIIAAAAA==.Bowe:BAAALAADCgIIAgAAAA==.',Br='Bravepeter:BAAALAAECgEIAQAAAA==.Brokevoker:BAACLAAFFIELAAIQAAQIFxIIBQBDAQAQAAQIFxIIBQBDAQAsAAQKgSwAAxAACAgiGzUJAHQCABAACAgiGzUJAHQCABEABgjPF9olAMYBAAAA.Bruv:BAAALAADCggICQABLAAECgYIBgAMAAAAAQ==.',Bu='Bullmeister:BAABLAAECoEqAAIHAAgIqB8cCgDdAgAHAAgIqB8cCgDdAgAAAA==.Bulverik:BAABLAAECoEgAAIHAAgI8RMAIgDnAQAHAAgI8RMAIgDnAQAAAA==.',['Bå']='Bågsträngen:BAABLAAECoEUAAIEAAYIuBfhdQCHAQAEAAYIuBfhdQCHAQAAAA==.',['Bí']='Bíffy:BAAALAADCggICwAAAA==.',Ch='Chacinga:BAAALAAECgQIBAABLAAECggIIQASAKoWAA==.Chamber:BAAALAADCggIDgAAAA==.Chaosbôlt:BAAALAAECggICwAAAA==.',Cl='Clangeddin:BAAALAADCgYIBgAAAA==.Classic:BAAALAAECgMIAwAAAA==.Classiker:BAAALAAECgIIAgAAAA==.',Co='Codebreakeer:BAAALAADCgYIBwAAAA==.Cohdii:BAAALAAECgYIEwAAAA==.Cokekiller:BAABLAAECoEaAAIHAAcIvyD8EACCAgAHAAcIvyD8EACCAgAAAA==.Colosall:BAAALAAECgYIBgAAAA==.Conn:BAAALAAECgcIDQAAAA==.Corax:BAAALAAECggIBwAAAA==.Corgihymn:BAABLAAECoEcAAQCAAcICiHWFQCdAgACAAcICiHWFQCdAgATAAYIhx2nMQDeAQAUAAEImA98MAA1AAAAAA==.Corgillidan:BAAALAADCggICAABLAAECgcIHAACAAohAA==.',Cr='Crepuscule:BAABLAAECoEgAAIEAAcIryMFGQDHAgAEAAcIryMFGQDHAgAAAA==.Cretin:BAAALAADCggICAAAAA==.',Cu='Cujo:BAAALAADCgMIAwABLAAECgYIGgAVANcVAA==.',Da='Danty:BAAALAAECgMIBQAAAA==.Daranor:BAAALAADCgIIAgAAAA==.Darkinside:BAAALAAECggICAAAAA==.Darkwa:BAAALAADCggIFwAAAA==.Dastridos:BAAALAADCgcIBwABLAAECgYIDgAMAAAAAA==.',Db='Dbow:BAAALAAECgMIAwAAAA==.',De='Deadcenter:BAABLAAECoEgAAMEAAgIoxVKYAC5AQAEAAcIbxhKYAC5AQADAAcI1QWPdADWAAAAAA==.Dementhea:BAAALAADCggIGAAAAA==.Demonicess:BAAALAADCggIKwAAAA==.Demonlorrd:BAABLAAECoElAAIBAAgIzx4WHgDJAgABAAgIzx4WHgDJAgAAAA==.',Di='Dirtydeeds:BAAALAAECggICAAAAA==.',Do='Doflamíngo:BAAALAAECgYICwAAAA==.Dojoon:BAAALAADCgcIDgAAAA==.Dotdamien:BAAALAADCggIGwAAAA==.Dottipotti:BAAALAADCggIFAAAAA==.',Dr='Draenerion:BAAALAAECgMIBwAAAA==.Drargonia:BAAALAADCgQIBwAAAA==.Druidicc:BAAALAADCgYICgAAAA==.',Du='Duxpriest:BAAALAAECgQIBQAAAA==.',Ea='Earthward:BAABLAAECoEiAAIWAAgIyCUwAQB3AwAWAAgIyCUwAQB3AwAAAA==.Eatmenot:BAAALAAECgIIAgAAAA==.',Eg='Eggnoodle:BAAALAAECgcIBwAAAA==.',El='Elém:BAAALAAECgUICwAAAA==.',Em='Emberhead:BAAALAADCgUIBQAAAA==.',Er='Erocc:BAACLAAFFIEIAAIQAAMIVAKrCgCzAAAQAAMIVAKrCgCzAAAsAAQKgR8AAhAACAglEIYUALIBABAACAglEIYUALIBAAAA.Erth:BAAALAAECgIIAgABLAAECgYIBgAMAAAAAQ==.',Eu='Eurus:BAAALAADCgcIBwAAAA==.',Ev='Evoks:BAAALAADCgcIBwAAAA==.',Fa='Fattyelf:BAAALAADCggIIAAAAA==.',Fe='Feldemon:BAAALAAECgYIBgABLAAECgcIEgAMAAAAAA==.',Fo='Foamix:BAABLAAECoEYAAMXAAcIpAwpHQB4AQAXAAcIJAwpHQB4AQAKAAQIiwglTADXAAAAAA==.Footsize:BAAALAAECggIBgAAAA==.',Fr='Frankzapper:BAAALAAECgYIDQAAAA==.Frozenheart:BAAALAADCggIDwABLAAECgIIAgAMAAAAAA==.Frys:BAAALAAECgYIBgAAAA==.',Ga='Ganon:BAAALAAECgcIDAAAAA==.',Gi='Gillton:BAAALAADCgYICQAAAA==.',Gl='Gloline:BAAALAAECgEIAgAAAA==.',Gn='Gneisshammer:BAAALAAECgYIBgAAAA==.',Go='Gonville:BAAALAADCgEIAQAAAA==.Goodshag:BAABLAAECoEjAAIYAAgIvRy9MQB9AgAYAAgIvRy9MQB9AgAAAA==.Gorthek:BAAALAAECgYICAAAAA==.',Gr='Grippér:BAAALAADCggIDwAAAA==.Grønnjævel:BAAALAAECggICAAAAA==.',Ha='Hammerfall:BAAALAADCggIFQAAAA==.Hastings:BAAALAADCggIEAAAAA==.Haywyre:BAAALAAECgEIAQAAAA==.Hazeygrom:BAAALAAECgYIDAAAAA==.',He='Heck:BAAALAADCggICAABLAAECgcIGQABAKwbAA==.Hektelion:BAAALAAECggICAAAAA==.Hellsz:BAAALAADCgMIAwABLAAECggIJQACAGMbAA==.Helvexc:BAACLAAFFIEIAAIIAAIIcyIwJQCxAAAIAAIIcyIwJQCxAAAsAAQKgRgAAggABwisIsIxAIECAAgABwisIsIxAIECAAAA.',Hi='Hirviowner:BAAALAADCggIFwAAAA==.',Ho='Holyomen:BAAALAAECgcIDQABLAAECggIJwANANQYAA==.',Hu='Hunterofdoom:BAAALAAECgcIDgAAAA==.',['Hé']='Hép:BAABLAAECoEdAAIZAAcIEQ4/XACZAQAZAAcIEQ4/XACZAQAAAA==.',Ic='Ice:BAAALAADCgcIBwAAAA==.Ichinose:BAAALAADCgcIDgAAAA==.',Il='Ilicadaver:BAABLAAECoEUAAIBAAYI4Qv6qAA8AQABAAYI4Qv6qAA8AQAAAA==.',Im='Imteh:BAAALAAECggICAAAAA==.',In='Inciter:BAABLAAECoEcAAIDAAcItA9zRwB4AQADAAcItA9zRwB4AQAAAA==.Inyourmind:BAACLAAFFIEGAAIGAAMI1wsRGgDhAAAGAAMI1wsRGgDhAAAsAAQKgR8AAgYACAg9GT0oAHICAAYACAg9GT0oAHICAAAA.',Ir='Irisis:BAABLAAECoEXAAIEAAgIchUTZgCrAQAEAAgIchUTZgCrAQAAAA==.Irídi:BAAALAADCgMIAwAAAA==.',It='Itseperkele:BAAALAADCgcIEQAAAA==.',Je='Jenvy:BAAALAAECggICAAAAA==.',Ka='Kabell:BAAALAAECgMIBgAAAA==.Kail:BAABLAAECoEUAAIZAAcIDg9XWACkAQAZAAcIDg9XWACkAQAAAA==.Kamu:BAAALAAECgEIAQAAAA==.Karlovacko:BAAALAAECggICQAAAA==.Kaz:BAAALAAECgUICwAAAA==.Kazlogic:BAAALAADCgUIBQAAAA==.Kazlol:BAAALAADCgYIBgAAAA==.',Ke='Kelsar:BAAALAADCgIIAQAAAA==.Kevin:BAAALAADCgcIBwAAAA==.',Ki='Kigamor:BAAALAAECgYIEAAAAA==.Kitagawa:BAAALAAECgIIBQAAAA==.',Ko='Konàn:BAAALAAECgMIAwAAAA==.Koydai:BAAALAADCggICAAAAA==.',Kr='Kraziekenan:BAAALAAECgYICwAAAA==.Krygem:BAAALAAECgYIDQAAAA==.',Ku='Kuzco:BAABLAAECoEcAAIWAAcIFR2KEgA1AgAWAAcIFR2KEgA1AgAAAA==.',['Kä']='Kääriäinen:BAABLAAECoEhAAIYAAgI+B5wHwDQAgAYAAgI+B5wHwDQAgAAAA==.',['Kí']='Kírá:BAAALAADCgYIBgABLAADCgcIBwAMAAAAAA==.',La='Lakegrove:BAAALAADCggIFQAAAA==.Larastraza:BAAALAADCggICAABLAAECggIJQAaAMAYAA==.Lavacalling:BAAALAAECgUICAABLAAECggIGwAJALwbAA==.Laveeni:BAAALAADCggIDgABLAAECgYIFAAVAPQLAA==.',Le='Legollas:BAAALAAECgIIBgAAAA==.',Li='Liandriala:BAABLAAECoEcAAIRAAcIjQkXMgBvAQARAAcIjQkXMgBvAQAAAA==.Lighier:BAACLAAFFIEIAAIVAAMIkBEcDQDVAAAVAAMIkBEcDQDVAAAsAAQKgSYAAhUACAgcH6IMANMCABUACAgcH6IMANMCAAEsAAUUBggRAAIAWhcA.Lilistrasza:BAAALAAECgIIAgAAAA==.Linwee:BAAALAADCgcIEQABLAAECgEIAQAMAAAAAA==.',Lm='Lm:BAAALAADCgcIFAAAAA==.',Lo='Lolxd:BAAALAADCggIEAABLAAECgcIGQABAKwbAA==.Longdonngg:BAAALAAECgYIDAAAAA==.Lorgaalis:BAABLAAECoEcAAMCAAcIAxYSNQDhAQACAAcIAxYSNQDhAQAUAAEItgYANwAjAAAAAA==.',Lu='Lutyo:BAAALAAECgYICAAAAA==.',['Lí']='Líllithania:BAAALAAECgIIAgAAAA==.',Ma='Macarenna:BAAALAADCggIFgAAAA==.Magickka:BAAALAAECggIAgAAAA==.Magliana:BAAALAADCgcIDQAAAA==.Mahtilisko:BAAALAADCgcIBwAAAA==.Maiëv:BAAALAADCgcIBwABLAAECgQIBgAMAAAAAA==.Margo:BAAALAAECggIDgAAAA==.Matthek:BAAALAADCgIIAgAAAA==.',Mc='Mcboogerbals:BAAALAADCggIEAAAAA==.',Me='Meekadin:BAAALAAECgcIBwAAAA==.Meleth:BAAALAAECgYIBwAAAA==.Menarath:BAAALAADCggIEQAAAA==.Mercryn:BAAALAADCgMIAwAAAA==.Metallíca:BAAALAADCgcIBwAAAA==.',Mi='Minatriel:BAAALAAECgcICgAAAA==.Misty:BAAALAAECgYIEQAAAA==.Mixtape:BAAALAADCgQICAAAAA==.Mizanthien:BAABLAAECoElAAMaAAgIwBh9EgANAgAaAAgIwBh9EgANAgABAAcIpwh/nABVAQAAAA==.',Mo='Mony:BAAALAADCggIIAAAAA==.Morrior:BAABLAAECoEVAAIGAAYIYgcbjAAbAQAGAAYIYgcbjAAbAQAAAA==.',Mu='Murdåck:BAAALAAECgcIEgAAAA==.Muwumw:BAAALAAECgIIAgABLAAECgYIGgAVANcVAA==.',My='Mydarling:BAAALAAECgUIBQAAAA==.Mylonniy:BAABLAAECoEVAAIbAAcIQxNfKQC1AQAbAAcIQxNfKQC1AQAAAA==.Mystogan:BAAALAADCgYIBgAAAA==.',['Mí']='Mík:BAABLAAECoEaAAIFAAcIuh4jBQB2AgAFAAcIuh4jBQB2AgAAAA==.',Na='Nachtmerrie:BAAALAAECgYIDwAAAA==.Naroses:BAAALAADCgcIBwAAAA==.',Ne='Nephelim:BAAALAADCgcIBgABLAAECgcIFwAcAHQcAA==.Nevermore:BAAALAAECgMICAAAAA==.Neyrath:BAAALAAECgYIBgAAAA==.',Nh='Nhash:BAAALAAECggIDgAAAA==.',Ni='Nightfader:BAABLAAECoEgAAIEAAgI0xwpLwBVAgAEAAgI0xwpLwBVAgAAAA==.',Ny='Nyckene:BAAALAAECgYIDwAAAA==.Nyxara:BAAALAAECgYIDwABLAAECgcIFQAaAN0RAA==.',Od='Ody:BAAALAAECgYIDQAAAA==.',Ok='Ok:BAAALAAECgQIBAAAAA==.Okye:BAAALAADCggIEQAAAA==.',Ol='Oldboy:BAAALAAECgYIDAAAAA==.Olum:BAAALAADCgcIBwAAAA==.',Or='Orumi:BAAALAAECgMIAwAAAA==.',Pa='Painsha:BAAALAAECgcIDwAAAA==.Panda:BAABLAAECoEUAAIEAAYIBxkMaACmAQAEAAYIBxkMaACmAQAAAA==.Panser:BAAALAAECgYIBgAAAA==.Panthers:BAAALAADCgMIAwAAAA==.',Pe='Pearlfinder:BAAALAADCggIGAAAAA==.Pendragôn:BAAALAAECggIDQAAAA==.Pezp:BAAALAAECgYIBgABLAAECgcIEwAMAAAAAA==.Pezpix:BAAALAAECgcIEwAAAA==.',Pi='Piciu:BAAALAADCggICAAAAA==.Pilgara:BAAALAADCgEIAQAAAA==.Pirì:BAAALAAECgMIBAAAAA==.',Po='Poddo:BAAALAADCgUIBgAAAA==.Popcat:BAAALAAFFAMIAwABLAAFFAYIEQAQAPUSAA==.Portemonnaie:BAAALAADCggIHwAAAA==.Postmalorn:BAAALAADCggICAAAAA==.',Pp='Pphole:BAAALAADCgcIBwAAAA==.',Pr='Pravús:BAABLAAECoEaAAIRAAgIeRSZHgAEAgARAAgIeRSZHgAEAgAAAA==.Prettywhite:BAAALAADCgUIBQABLAADCggICAAMAAAAAA==.',Pu='Puffi:BAAALAAECgYIDAAAAA==.',Py='Pyra:BAAALAADCgcIBwAAAA==.',Qa='Qatari:BAAALAAECgQIBAAAAA==.Qatarie:BAAALAADCggIKAAAAA==.',Qt='Qtri:BAAALAADCggIHQAAAA==.Qtrvip:BAAALAADCggIIwAAAA==.',Ra='Ragedcorpse:BAAALAAECgMIAwAAAA==.Rammex:BAAALAADCggICAABLAAECgYIFAAKAEENAA==.Rayce:BAECLAAFFIENAAIGAAQIdSA6DQB+AQAGAAQIdSA6DQB+AQAsAAQKgS8AAgYACAjMI9kMACMDAAYACAjMI9kMACMDAAAA.Raynn:BAAALAAECgcIEQAAAA==.',Re='Relistrix:BAAALAADCgcIBwAAAA==.',Rh='Rhyhad:BAAALAAECgYIDgAAAA==.',Ri='Rivianne:BAAALAADCggICAAAAA==.',Ro='Robthehusky:BAAALAAECgIIBAAAAA==.Rollyboi:BAAALAADCggIDwABLAAECgcIGgAHAL8gAA==.Rostislav:BAAALAADCggIJQAAAA==.Roton:BAAALAADCgcIBwAAAA==.',['Rö']='Röß:BAAALAAECgMIAwAAAA==.',Sa='Saffiron:BAAALAAECgIIAgAAAA==.Salubris:BAAALAADCgcIGAAAAA==.Samtyler:BAAALAAECgIIAgAAAA==.Sandblood:BAAALAAECgMIAwAAAA==.Saximus:BAAALAADCggICAAAAA==.',Sc='Scarymonstrs:BAABLAAECoEaAAIVAAYI1xXcRACLAQAVAAYI1xXcRACLAQAAAA==.Scuz:BAAALAAECgYICQAAAA==.Scuzz:BAAALAAECgYIDQAAAA==.',Sh='Shadowelf:BAAALAADCggICAAAAA==.Shahd:BAAALAADCggIHAAAAA==.Shamish:BAAALAAECgIIAgAAAA==.Shamonk:BAAALAADCgMIAwABLAAECgIIAgAMAAAAAA==.Shermán:BAAALAAECgUIDQAAAA==.Shoq:BAAALAADCggIGAAAAA==.Shämán:BAAALAAECgMIAwAAAA==.',Si='Sid:BAAALAAECggICQAAAA==.Silverblue:BAAALAADCgYIBgAAAA==.',Sl='Sláshdk:BAAALAAECgEIAgAAAA==.',Sn='Snapjaw:BAAALAAECggIEQAAAA==.',So='Softis:BAABLAAECoEYAAIbAAcINw8UMACQAQAbAAcINw8UMACQAQAAAA==.Solace:BAAALAADCggICAABLAAFFAYIEQAQAPUSAA==.Sotajumala:BAABLAAECoEUAAIBAAcIGxTlaADAAQABAAcIGxTlaADAAQAAAA==.Soulscarr:BAAALAAECgUIAwAAAA==.',Sp='Spacegoat:BAAALAAECgMIAwAAAA==.Spidéy:BAAALAAECgUIBwAAAA==.Spiritu:BAAALAADCgMIBAABLAAECgYIBgAMAAAAAA==.Spriggz:BAAALAAECgYIDAABLAAECggIGAAdAPUhAA==.',St='Stabbybobby:BAAALAADCggIEwAAAA==.Starcalling:BAABLAAECoEbAAMJAAgIvBtbGQBlAgAJAAgIvBtbGQBlAgAVAAMIRAoDmQB9AAAAAA==.Starguide:BAAALAADCgYICQABLAAECggIGwAJALwbAA==.Stephywefy:BAAALAAECgYIDQAAAA==.Stinkyboi:BAAALAAECgYIBgABLAAECgcIGgAHAL8gAA==.Strikster:BAAALAAECgMIBQAAAA==.',Su='Sunrose:BAAALAADCgYIBgABLAAECgYICQAMAAAAAA==.Superdps:BAABLAAECoEZAAIBAAcIrBvUPAA9AgABAAcIrBvUPAA9AgAAAA==.',Sv='Svea:BAAALAAECgMICgAAAA==.',Sw='Sweasta:BAAALAAECgYICQAAAA==.Sweetwather:BAAALAADCggICAAAAA==.Swytchh:BAAALAAECgIIAwAAAA==.',Sy='Synapse:BAAALAADCgcIBwAAAA==.',Ta='Talizha:BAAALAAECgYIDwABLAAECgcIEwAMAAAAAA==.Talys:BAABLAAECoEUAAIIAAYI/RAoqABzAQAIAAYI/RAoqABzAQAAAA==.Tankyskills:BAAALAADCggIEAABLAAECgcIGgAHAL8gAA==.Tarecgosa:BAABLAAECoEoAAMWAAgIuhwVDgBrAgAWAAgIuhwVDgBrAgAYAAEIFRJ3LAFCAAAAAA==.Tarithel:BAAALAAECgYIDQAAAA==.Taurine:BAAALAADCggIEgAAAA==.',Te='Teegnome:BAAALAAECgcIBwAAAA==.Tekkz:BAAALAADCgIIAgAAAA==.Tekz:BAAALAADCgIIAgAAAA==.Terosh:BAAALAADCgQIBAAAAA==.',Th='Theldrasol:BAAALAADCggIDwAAAA==.Theonewizard:BAABLAAECoEVAAIeAAcIugu1CACWAQAeAAcIugu1CACWAQAAAA==.Therön:BAAALAADCggIEQAAAA==.Throe:BAAALAAECggIEgAAAA==.Thánatus:BAAALAAECgYICQAAAA==.Thällasillor:BAAALAAECgQIBgAAAA==.',Ti='Timmee:BAABLAAECoEfAAIVAAgIegu9TQBpAQAVAAgIegu9TQBpAQAAAA==.Tirinee:BAAALAADCggIFAAAAA==.',To='Tofstrun:BAAALAAECggICAAAAA==.Toradriel:BAAALAADCggICAABLAAECgYICQAMAAAAAA==.Totemew:BAAALAADCggIHwABLAAECgYIGgAVANcVAA==.',Tp='Tpyo:BAABLAAECoEaAAISAAgIrRS3OQA+AgASAAgIrRS3OQA+AgAAAA==.',Tr='Trinky:BAAALAADCgcIBwAAAA==.',Tu='Turvungezux:BAAALAAECggIAgAAAA==.',Ut='Utaab:BAAALAADCgIIAgAAAA==.',Uu='Uunimaestro:BAAALAAECgUIBQAAAA==.',Va='Valethria:BAABLAAECoEbAAMEAAcIFxxBOAAxAgAEAAcIFxxBOAAxAgADAAcI2wUGawD5AAAAAA==.Vanthryn:BAAALAAECgYIBgAAAA==.',Ve='Veloarc:BAAALAAECgYIDAAAAA==.Vermithrax:BAABLAAECoEhAAMQAAgITgw4FwCNAQAQAAgITgw4FwCNAQARAAEIIwF2XgAbAAAAAA==.Vesipuhveli:BAAALAAECgYICQAAAA==.',Vo='Volbeat:BAAALAADCgYIBgAAAA==.',Vr='Vrath:BAAALAAECgYIDQAAAA==.',Vu='Vulk:BAABLAAECoEeAAMbAAcI8Rk+MACPAQASAAcIIxT5WADSAQAbAAYIJBg+MACPAQAAAA==.Vulksp:BAAALAAECgUIBgAAAA==.Vulkswagen:BAAALAADCggIDQAAAA==.',Vy='Vyrith:BAABLAAECoEbAAIJAAgIHiAvEADEAgAJAAgIHiAvEADEAgAAAA==.',Wa='Waiteyak:BAAALAAECgQIBAAAAA==.Wals:BAAALAAECgUIDQAAAA==.Warbringer:BAAALAAECgEIAQAAAA==.Waroftunder:BAAALAADCggIEwAAAA==.Warrirors:BAABLAAECoEfAAIZAAgIJiJxDgAXAwAZAAgIJiJxDgAXAwAAAA==.Wauweltesjch:BAAALAADCggICgAAAA==.',We='Wealing:BAABLAAECoEdAAICAAcIcRDpRQCUAQACAAcIcRDpRQCUAQAAAA==.Weurrior:BAAALAADCgcIDgABLAAECgYIDQAMAAAAAA==.',Wh='Whomeno:BAAALAAECgYIDAAAAA==.',Wi='Wildd:BAAALAADCggIFwAAAA==.',Wu='Wubbish:BAAALAAECgEIAQAAAA==.',['Wô']='Wôlfsbane:BAAALAAECggIDAAAAA==.',Xi='Xiangao:BAAALAADCggICgAAAA==.',['Xé']='Xénophon:BAAALAADCgMIBQAAAA==.',Ye='Yeshua:BAABLAAECoEjAAQPAAgI5Q16HABjAQAPAAgI+Qx6HABjAQAIAAQIkglSBAG4AAAfAAEI8gH0VAAwAAAAAA==.',Yp='Yperbarrage:BAAALAAECgYIBgABLAAECggIJwANANQYAA==.',Ze='Zedrina:BAAALAADCgIIAgAAAA==.Zeldora:BAAALAAECgMIBwAAAA==.Zenon:BAAALAAECgYICQAAAA==.Zeroblood:BAAALAAECggIEgAAAA==.Zeús:BAABLAAECoElAAICAAgIYxvCFwCPAgACAAgIYxvCFwCPAgAAAA==.',Zs='Zsana:BAAALAAECgMIBwAAAA==.',Zu='Zurlox:BAAALAAECgMIAwAAAA==.',['Âk']='Âkmunrâ:BAABLAAECoEYAAIEAAcIoA+/dwCDAQAEAAcIoA+/dwCDAQAAAA==.',['Îb']='Îbitê:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end