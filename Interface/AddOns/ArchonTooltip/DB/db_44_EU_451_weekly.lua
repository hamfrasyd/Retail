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
 local lookup = {'DeathKnight-Frost','Priest-Shadow','Evoker-Devastation','Unknown-Unknown','Druid-Guardian','DemonHunter-Havoc','Mage-Arcane','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Druid-Restoration','Shaman-Enhancement','Warlock-Affliction','Priest-Holy','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Warrior-Protection','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Windwalker','Rogue-Assassination','Mage-Fire','Mage-Frost','Evoker-Preservation','Evoker-Augmentation','Druid-Feral','Priest-Discipline','Paladin-Protection',}; local provider = {region='EU',realm='Nathrezim',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ai='Airesh:BAAALAADCgYIBgAAAA==.',Aj='Ajuko:BAAALAADCggICwAAAA==.',Ak='Akenias:BAABLAAECoEzAAIBAAgImibGAwBuAwABAAgImibGAwBuAwABLAAFFAcIGwACAComAA==.',Al='Alecia:BAAALAAECgYIDQAAAA==.Aliranas:BAABLAAECoEcAAIDAAcIlxrzHAAbAgADAAcIlxrzHAAbAgAAAA==.',Am='Amandus:BAAALAADCggICAAAAA==.Amaranth:BAAALAAECggICwAAAA==.Ampic:BAAALAADCggICAAAAA==.Ampicillin:BAAALAAECgMIAwAAAA==.',Ar='Aristana:BAAALAAECgUICAAAAA==.Arkail:BAAALAAECgQIBwAAAA==.Arsamandi:BAAALAAECgYIEwAAAA==.',As='Ashenblade:BAAALAAECgQIBAAAAA==.Ashini:BAAALAADCggICAABLAAECgYIBgAEAAAAAA==.Asumá:BAAALAAECgQIBAAAAA==.',Au='Auxi:BAAALAAECgQIBwAAAA==.Auxii:BAAALAADCggIDwAAAA==.',Ay='Ayumii:BAABLAAECoEWAAIFAAYISCFKCQAhAgAFAAYISCFKCQAhAgAAAA==.',Az='Azazul:BAAALAAECgcIEwAAAA==.',Ba='Bacardíto:BAAALAADCgcIDwAAAA==.Bacardító:BAAALAADCgcIDQAAAA==.Baldêr:BAABLAAECoEkAAIGAAgIbxRuYADdAQAGAAgIbxRuYADdAQAAAA==.Barrin:BAABLAAECoEZAAIHAAcI6QsDcgCRAQAHAAcI6QsDcgCRAQAAAA==.',Bi='Bigscar:BAABLAAECoEcAAIIAAYIPBhcUwCRAQAIAAYIPBhcUwCRAQAAAA==.Bigyiatch:BAACLAAFFIEWAAIGAAcIKBsZAQCXAgAGAAcIKBsZAQCXAgAsAAQKgTAAAgYACAjKJpQAAJgDAAYACAjKJpQAAJgDAAAA.Bitcion:BAAALAADCggIFgAAAA==.',Bl='Blaizdh:BAAALAADCgEIAQABLAAFFAIIBgAEAAAAAA==.Blogran:BAABLAAECoEWAAIJAAYIWA/PtwBUAQAJAAYIWA/PtwBUAQAAAA==.Blooregard:BAAALAADCggIDQAAAA==.',Bo='Bofrost:BAAALAADCggICAAAAA==.Boozedh:BAAALAAECgIIAgAAAA==.',Br='Brandor:BAAALAADCgYIDAAAAA==.Brangbok:BAAALAAECgEIAQAAAA==.Bratkartoffl:BAABLAAECoEUAAMKAAYIvAw/fgBLAQAKAAYIqww/fgBLAQALAAQIjQbtYgC0AAAAAA==.Brolax:BAAALAADCgcIFAABLAAECgYIEgAEAAAAAA==.',Bu='Bulldog:BAAALAADCggICgAAAA==.Burtock:BAAALAADCgUIBQAAAA==.',['Bâ']='Bâcardito:BAAALAAECgIIAgAAAA==.',['Bó']='Bóindil:BAAALAADCgEIAQAAAA==.',['Bô']='Bôoze:BAACLAAFFIEJAAIMAAMIRR+ICAAZAQAMAAMIRR+ICAAZAQAsAAQKgTMABAwACAjmJSMFAEsDAAwACAjmJSMFAEsDAA0AAQh7DTq8AC0AAAUAAghUGwAAAAAAAAAA.',Ca='Cactus:BAAALAADCggIGAAAAA==.Calibbx:BAAALAAECggICAAAAA==.Caregiver:BAAALAAECggICQAAAA==.',Ch='Charlz:BAABLAAECoEaAAIOAAcIPhLIDwDEAQAOAAcIPhLIDwDEAQAAAA==.Cheney:BAAALAAECggICAAAAA==.Cheyenn:BAAALAADCgYIBgAAAA==.Chillerrufer:BAAALAAECgYIEgAAAA==.',Cl='Clicks:BAAALAADCgIIAgAAAA==.',Co='Coillia:BAAALAAFFAIIAgAAAA==.Cornholío:BAAALAAECgYIDAAAAA==.',Da='Damaaruhn:BAACLAAFFIENAAMLAAUIHyKCAACIAQALAAQIqCGCAACIAQAKAAIIMCFqHwC/AAAsAAQKgScABAsACAj6JekEAAYDAAsABwjyJekEAAYDAAoAAggEIo2qAMMAAA8AAgiDHcIiALUAAAAA.Darasha:BAAALAAECgYIEwAAAA==.Darkshamen:BAAALAAECggIEAAAAA==.Darksim:BAAALAAECgEIAQAAAA==.',De='Deadscar:BAAALAADCgIIAgAAAA==.Deathranger:BAABLAAECoEWAAMKAAgIkhNXcQBsAQAKAAgIlRJXcQBsAQAPAAIIUxnjKACJAAAAAA==.Decon:BAAALAADCggICAAAAA==.Deepvibes:BAAALAADCggIFAAAAA==.Deha:BAAALAAECgYIEQAAAA==.Dellana:BAACLAAFFIEJAAIQAAMIKhhVEADnAAAQAAMIKhhVEADnAAAsAAQKgSUAAxAACAg9IdgaAH8CABAACAg9IdgaAH8CAAIAAgjUC8x6AG4AAAAA.Demage:BAAALAAECgYIHAAAAQ==.Demonerich:BAAALAADCgEIAQAAAA==.Derfeige:BAAALAAECgYIDwAAAA==.Devii:BAAALAAECgYICgAAAA==.',Di='Diabolus:BAABLAAECoEUAAIGAAcIcRwzQQA2AgAGAAcIcRwzQQA2AgAAAA==.Dinora:BAAALAADCggIDgABLAAECgYIFQARAOoaAA==.',Do='Domar:BAAALAAECgEIAQAAAA==.Donnerbüchse:BAAALAAECgEIAQAAAA==.',Dr='Draglodyt:BAAALAADCggIEAAAAA==.Dreykce:BAAALAAFFAMIAwAAAA==.',Du='Dubbie:BAAALAADCggICwABLAAECgYICgAEAAAAAA==.Dunao:BAAALAADCggIDgAAAA==.',Dw='Dwain:BAAALAAECgIIAgAAAA==.',['Dâ']='Dârkrain:BAAALAAECgcIBwAAAA==.',['Dé']='Démonhunter:BAAALAADCgQIAwAAAA==.',Ea='Easydeath:BAABLAAECoEaAAMSAAYIJhbOIgCNAQASAAYILhTOIgCNAQATAAYIuROZJQAOAQAAAA==.',Eh='Ehru:BAAALAADCgcICAAAAA==.',Ei='Eisenschwein:BAABLAAECoEaAAIUAAcIThS3RAAkAQAUAAcIThS3RAAkAQAAAA==.',El='Eldrood:BAAALAAECgIIAgAAAA==.Elsaruman:BAAALAADCgcIDQAAAA==.',En='Enofa:BAAALAADCgcIBwAAAA==.Enton:BAABLAAECoEuAAMVAAgIiCJNDAD2AgAVAAgIiCJNDAD2AgAWAAQI5x1F8wB3AAAAAA==.Envy:BAAALAAECggICAAAAA==.',Es='Eskuhnor:BAAALAADCggICAABLAAECgcIJgATAAogAA==.',Ev='Evelina:BAAALAAECgEIAQAAAA==.',Fa='Faeyn:BAAALAAFFAIIBAAAAA==.Fancel:BAABLAAECoEWAAMJAAgI6xyuNAB4AgAJAAgI6xyuNAB4AgAXAAIIqRKjWgB8AAAAAA==.',Fe='Fellin:BAAALAAECggIAgABLAAFFAUIEAAJAMoZAA==.Feuerwolf:BAAALAADCgEIAQAAAA==.',Fi='Fitalitý:BAAALAAECggICAAAAA==.Fizli:BAAALAAECgYICwAAAA==.',Fr='Freya:BAAALAAECgYIDgAAAA==.Frostzwerg:BAAALAADCgcIBwAAAA==.',['Fê']='Fêârdôtcôm:BAAALAADCgIIAwAAAA==.',Ga='Gandolf:BAAALAAECgUIBgABLAAECggILgAVAIgiAA==.Ganschar:BAAALAAECgQIBgABLAAECgYIBgAEAAAAAA==.',Gh='Ghostridér:BAAALAADCggIEAAAAA==.',Go='Goblitz:BAAALAAECgMIAwAAAA==.',Gr='Grandseiko:BAABLAAECoEfAAMKAAgI+xrPJgCCAgAKAAgI+xrPJgCCAgAPAAYIcAxJFQBMAQAAAA==.Grimbadur:BAAALAADCgcIDAAAAA==.Gromalo:BAABLAAECoEpAAIYAAgIbxqpKABuAgAYAAgIbxqpKABuAgAAAA==.',Ha='Happý:BAAALAADCggIDwAAAA==.Hatley:BAAALAADCggIEAAAAA==.',Ho='Hokima:BAAALAAECggIDQAAAA==.Holun:BAAALAAECgUIBQAAAA==.Holytore:BAAALAADCggIDwAAAA==.Homero:BAAALAAECgIIBAAAAA==.',Ib='Ibraham:BAAALAADCggICwABLAAECggIJAAZAE0cAA==.',If='Ifelia:BAACLAAFFIEFAAIaAAMIwhZKAwDvAAAaAAMIwhZKAwDvAAAsAAQKgSkAAhoACAguIe0FAPACABoACAguIe0FAPACAAEsAAUUBggSABYAWxgA.',Ig='Igrett:BAAALAADCgMIAwAAAA==.',Im='Imbaness:BAAALAADCggIJQABLAAECgcIJgATAAogAA==.Imperiales:BAAALAAECgYIBgAAAA==.Imwithstupit:BAAALAAECgYIDwAAAA==.',In='Intankia:BAAALAAECgIIAwABLAAECggIIQAbABElAA==.Intankos:BAABLAAECoEhAAMbAAgIESVkAgA7AwAbAAgIESVkAgA7AwAcAAgIMiC9CQDfAgAAAA==.Intankøs:BAAALAAECgMIBQABLAAECggIIQAbABElAA==.',Is='Ishaar:BAAALAADCgMIAwAAAA==.Iskîerka:BAAALAADCggICQAAAA==.',It='Itrukaz:BAAALAADCgIIAgAAAA==.',Iz='Izeron:BAAALAADCgUIAQAAAA==.',Ja='Jadranko:BAAALAAECgYICAAAAA==.',Je='Jeathor:BAAALAAECgYIEwAAAA==.',Jo='Jockdra:BAAALAAECggICAAAAA==.Jockâ:BAABLAAECoEmAAIYAAgIhQIMqQCxAAAYAAgIhQIMqQCxAAAAAA==.',Ju='Justart:BAAALAAECgIIAgAAAA==.',['Jê']='Jênovâ:BAAALAADCgUIBQAAAA==.',['Jî']='Jînn:BAAALAAECgcIBwAAAA==.',Ka='Kamal:BAAALAADCgUIBQAAAA==.Karizma:BAAALAADCgcIAQAAAA==.Karrian:BAAALAAECgYICgAAAA==.Kayrizzma:BAAALAAECgYIDAAAAA==.',Ke='Kedoklol:BAAALAADCggICAABLAAECggIHwANAHIdAA==.Kegth:BAAALAAECgYIDwAAAA==.Keja:BAAALAADCgIIAgAAAA==.Keni:BAAALAAECgYICQAAAA==.',Kh='Khida:BAAALAAECggIBwAAAA==.',Ki='Kidleroye:BAAALAADCgcIFQAAAA==.Killerorx:BAAALAADCgYIBAAAAA==.',Kl='Klausii:BAAALAADCggICAAAAA==.',Ko='Komi:BAAALAAECgYIDAABLAAECggIDAAEAAAAAA==.',Kr='Krathor:BAABLAAECoEaAAINAAcIsBjHLQD9AQANAAcIsBjHLQD9AQAAAA==.',Ku='Kuhmosapiens:BAAALAAECgEIAQAAAA==.Kuroldan:BAAALAAECgcIDQAAAA==.',['Kû']='Kûschêl:BAAALAADCgYIBgAAAA==.',La='Lances:BAAALAAECgMIBAAAAA==.Lauracine:BAAALAAECgYIBgAAAA==.Layo:BAABLAAECoEcAAIRAAcIwA5rgwBAAQARAAcIwA5rgwBAAQAAAA==.',Le='Lehtera:BAAALAADCgYIBgAAAA==.Lemonly:BAACLAAFFIEFAAIdAAMI8BvwBgAiAQAdAAMI8BvwBgAiAQAsAAQKgS0AAh0ACAgbI9YDADgDAB0ACAgbI9YDADgDAAEsAAUUBwgWAAYAKBsA.Leome:BAABLAAECoEcAAIRAAgI8xA6YgCUAQARAAgI8xA6YgCUAQAAAA==.Levion:BAAALAADCggICAABLAAECggIIQAbABElAA==.Leyo:BAAALAADCgcIBwAAAA==.',Li='Liamos:BAAALAAECgMIBwAAAA==.Liinara:BAAALAADCgIIAgAAAA==.Lings:BAAALAAECgIIBAAAAA==.Lissandrâ:BAAALAADCgYIDgAAAA==.Liá:BAAALAAECgUIBQAAAA==.',Lo='Loggins:BAAALAADCggIEAAAAA==.Lorewalker:BAAALAAECgYIEwAAAA==.Loygdemon:BAAALAADCggICAABLAAECgcIDQAEAAAAAA==.',Lu='Lugbúrz:BAABLAAECoEXAAIJAAcIoBoocADZAQAJAAcIoBoocADZAQAAAA==.',Ly='Lycaramba:BAAALAAECgYIDQAAAA==.',Ma='Mahakali:BAAALAAECgMICAAAAA==.Maisie:BAAALAAECgYIDwAAAA==.Maki:BAAALAAECggICAABLAAFFAcIFgAGACgbAA==.Maronai:BAABLAAECoEaAAMeAAgINhjyAwBcAgAeAAgISxbyAwBcAgAfAAYI/xP9OgBgAQAAAA==.Marshadow:BAAALAADCggIDgAAAA==.Maul:BAABLAAECoEmAAITAAcICiBLCgCKAgATAAcICiBLCgCKAgAAAA==.',Me='Melèk:BAAALAAECgYICQAAAA==.Merona:BAAALAADCggICAAAAA==.',Mi='Michelangelu:BAABLAAECoEjAAMgAAgI9RlXDABAAgAgAAgI9RlXDABAAgAhAAcINw6jCgCCAQAAAA==.Milsana:BAAALAAECgYIDwAAAA==.Minami:BAABLAAECoElAAIHAAgIkA0QWQDZAQAHAAgIkA0QWQDZAQAAAA==.Minthal:BAAALAADCgYIDAABLAAFFAEIAQAEAAAAAA==.',Mo='Moonstrider:BAAALAAECgYIDAAAAA==.Mordrain:BAAALAAECgEIAQAAAA==.Morningstar:BAAALAADCggICQAAAA==.Mortìscha:BAABLAAECoEcAAIfAAYI5CIrFQBTAgAfAAYI5CIrFQBTAgAAAA==.Mourne:BAAALAADCggIDAAAAA==.',Mu='Mufasá:BAABLAAECoEbAAIiAAgILxjiFQDYAQAiAAgILxjiFQDYAQAAAA==.Muhz:BAAALAAECgYIBwAAAA==.Muuhli:BAAALAAECgIIBAAAAA==.',My='Mysery:BAAALAAECgYIBwAAAA==.Mysos:BAAALAAFFAEIAQAAAA==.Myséry:BAAALAAECgYICAAAAA==.',['Mà']='Màgistrix:BAAALAAECggIDAAAAA==.',['Mâ']='Mâusî:BAABLAAECoEZAAINAAYIMyHiKAAVAgANAAYIMyHiKAAVAgAAAA==.',['Mí']='Míyou:BAAALAADCgQIBQAAAA==.',['Mó']='Mórrígan:BAAALAAECggICAAAAA==.',Na='Narashi:BAAALAAECgYICwABLAAECgcIDQAEAAAAAA==.Naràke:BAABLAAECoEbAAIdAAgIkA1NJADkAQAdAAgIkA1NJADkAQAAAA==.',Ne='Nenys:BAAALAADCggIEAAAAA==.Neofelis:BAAALAAECgYICQAAAA==.',Ni='Nicolasrage:BAAALAADCgYIBgAAAA==.Nightbreaker:BAAALAAECgEIAQAAAA==.Nili:BAAALAADCggICAABLAAECgYIDgAEAAAAAA==.Nimueh:BAABLAAECoEVAAIRAAYI6hogUADFAQARAAYI6hogUADFAQAAAA==.Nishoola:BAABLAAECoEaAAMNAAcIuhwuNgDUAQANAAYIIBsuNgDUAQAMAAcIHQ/WjwAyAAAAAA==.',No='Norb:BAAALAAECgMIAwAAAA==.',Om='Omi:BAAALAAECgEIAQABLAAECggIDAAEAAAAAA==.Omir:BAAALAADCgcIFwAAAA==.',Ou='Outrage:BAABLAAECoEWAAMBAAgI9hTzXAAKAgABAAgI9hTzXAAKAgATAAQICwejMgCJAAAAAA==.Outráge:BAAALAAECgIIAgAAAA==.',Pa='Pange:BAAALAAECggIEQAAAA==.',Pe='Peccatum:BAAALAAECgYIDAAAAA==.Peepofeet:BAAALAAECggICAAAAA==.Perla:BAAALAADCgIIAgAAAA==.Perot:BAAALAAECgIIAwAAAA==.Pevox:BAAALAADCgcIBwAAAA==.',Pi='Pididdy:BAAALAADCgEIAQAAAA==.',Ps='Psýx:BAAALAAECggIDAAAAA==.',Ra='Rae:BAAALAADCggIDgAAAA==.Ragosa:BAAALAAECgcIDgAAAA==.Rajindo:BAAALAAECgYIDAABLAAECgYIDQAEAAAAAA==.Rakurai:BAAALAADCggICAAAAA==.Rampola:BAAALAAECgUIBQAAAA==.Rangosh:BAAALAADCggICAAAAA==.Razgúl:BAAALAADCggICAAAAA==.',Re='Reileigh:BAAALAAECgMIBwAAAA==.Rendor:BAAALAADCgcIBwABLAAECgYIDQAEAAAAAA==.',Ri='Rimuru:BAAALAADCgUIBQAAAA==.',Rn='Rngesus:BAAALAADCgYIBwAAAA==.',Ro='Roqu:BAACLAAFFIEFAAIXAAMIRhPOCQDuAAAXAAMIRhPOCQDuAAAsAAQKgR4AAhcACAgsIWwRAGICABcACAgsIWwRAGICAAAA.Rosckarnar:BAAALAADCgUIBQAAAA==.',Ru='Rubinaja:BAAALAADCggICAAAAA==.',Sa='Sailerluu:BAAALAADCgcIEgAAAA==.Sanavlys:BAAALAADCgUIBAAAAA==.',Sc='Schieba:BAAALAADCgcIBwAAAA==.Scrappy:BAAALAADCggIDQABLAAECgcIFwABAN4WAA==.',Sh='Shadowseeker:BAABLAAECoEhAAICAAgIEh+gEADZAgACAAgIEh+gEADZAgAAAA==.Shanadee:BAAALAADCgIIAgAAAA==.Shantari:BAAALAAECgcIEQAAAA==.Shîndral:BAAALAADCgUIBQAAAA==.',Si='Siebiria:BAAALAADCgEIAQAAAA==.Signum:BAAALAADCgUIBQABLAAECgYIFgAFAEghAA==.Siluro:BAAALAADCggIBwAAAA==.Sinoria:BAAALAADCgYIBgAAAA==.Sintharia:BAAALAAECgYIDwAAAA==.',Sm='Smokys:BAAALAADCgcIBwAAAA==.Smokysthane:BAAALAADCgcIDQAAAA==.',Sn='Snek:BAAALAAECgcIDQAAAA==.',So='Sora:BAAALAADCggICQAAAA==.Soulblade:BAAALAAECgYIBgAAAA==.',Sp='Speermarkus:BAAALAAECgYIDQAAAA==.',St='Stancy:BAAALAAECgcIDgAAAA==.Stiftix:BAAALAADCggIFAAAAA==.',Su='Sukkubus:BAABLAAECoEbAAIGAAYIGSG7RAAqAgAGAAYIGSG7RAAqAgAAAA==.',Sy='Syráx:BAAALAAECgUIDwABLAAECgYIFQARAOoaAA==.',['Sû']='Sûramienne:BAAALAADCggIEAAAAA==.',Ta='Talaaron:BAAALAADCgcIBwAAAA==.Tashina:BAAALAAECgYIDwAAAA==.',Te='Teldina:BAAALAAECgYIBgABLAAFFAIIAgAEAAAAAA==.Teldudk:BAAALAAFFAIIAgAAAA==.Teldumage:BAABLAAECoEjAAMHAAgI3BpZRwASAgAHAAgIqhVZRwASAgAfAAYIpRqTKQC6AQABLAAFFAIIAgAEAAAAAA==.Teldurîn:BAAALAADCggICAABLAAFFAIIAgAEAAAAAA==.Telia:BAAALAADCggIEAABLAAFFAYIEgAWAFsYAA==.Telperien:BAAALAAECgQIBAAAAA==.Terrix:BAABLAAECoEnAAIMAAgIWxQDKwDvAQAMAAgIWxQDKwDvAQAAAA==.',Ti='Tinkerbella:BAABLAAECoEeAAIWAAgI0wskfQCDAQAWAAgI0wskfQCDAQAAAA==.Tisar:BAABLAAECoEnAAQKAAgIiBwxNwAwAgAKAAcIVxoxNwAwAgALAAUIUhg5OwBeAQAPAAMIqAcDJgCcAAAAAA==.',To='Todesringo:BAAALAAECgEIAQABLAAECggIFgAKAJITAA==.Totalschaden:BAAALAADCgcICwAAAA==.',Tr='Trashadin:BAAALAADCggIDQAAAA==.Trashdeath:BAAALAAECgMIAwAAAA==.Trashdiva:BAAALAADCggICAAAAA==.Treyce:BAACLAAFFIEbAAMCAAcIKiaSAADCAgACAAYIDCeSAADCAgAQAAIIcCJcFwC4AAAsAAQKgRoAAgIACAjxJscAAI8DAAIACAjxJscAAI8DAAAA.Troxx:BAAALAADCggICQABLAAFFAYIEgAWAFsYAA==.Tryxie:BAAALAADCggIEAABLAAFFAYIEgAWAFsYAA==.',Tu='Tummillo:BAAALAADCgUIBwAAAA==.',['Té']='Tékáry:BAABLAAECoEUAAIBAAYIjxWgoACIAQABAAYIjxWgoACIAQAAAA==.',['Tô']='Tômkâr:BAAALAAECgMIBQAAAA==.',Un='Unhailbar:BAAALAADCgYIAwABLAAECgYIEgAEAAAAAA==.',Va='Vaburdine:BAAALAAECggIAQAAAA==.Vadamosky:BAAALAAECgEIAQAAAA==.Valana:BAAALAADCggICgABLAAECggICwAEAAAAAA==.Valmonsky:BAAALAADCgIIAgAAAA==.Vantura:BAAALAADCgcIBwAAAA==.Vauxen:BAAALAADCgcIBwAAAA==.',Ve='Veyo:BAABLAAECoEUAAILAAcIOxfCHAD4AQALAAcIOxfCHAD4AQAAAA==.',Vi='Vitocorleone:BAAALAAECgYIEgAAAA==.',Vo='Vollaufsmaul:BAAALAADCggIEAAAAA==.Volltroll:BAABLAAECoEaAAIBAAcIph3lVQAaAgABAAcIph3lVQAaAgAAAA==.Voluntas:BAAALAAECgYIDwAAAA==.',Wa='Wandor:BAAALAADCgUIBQAAAA==.Warfare:BAAALAAECgYIDwAAAA==.',Wi='Winc:BAAALAADCggIDAAAAA==.',Wo='Wolfdragon:BAAALAAECgYIDgAAAA==.Wootz:BAAALAAECgYICQAAAA==.',Wy='Wynardtages:BAABLAAECoElAAQQAAgI8Ro3GwB8AgAQAAgI3hk3GwB8AgAjAAgI6wonEgBTAQACAAQIlQN3egBvAAAAAA==.Wynardtagé:BAAALAAECggICAAAAA==.',['Wù']='Wùmpscut:BAABLAAECoEcAAQQAAgIEBFZQgCoAQAQAAgIEBBZQgCoAQACAAgImwM9ZwDbAAAjAAgImQPqIACmAAABLAAECggIJQAQAPEaAA==.',Xa='Xan:BAAALAAECgYIDwAAAA==.Xarona:BAAALAAECgYIDwAAAA==.Xawora:BAAALAADCggICAAAAA==.Xaworu:BAAALAADCggIEAAAAA==.',Xe='Xenn:BAAALAADCgcICQAAAA==.',Xp='Xpêndy:BAAALAAECgcICgAAAA==.',Ya='Yami:BAAALAADCgEIAQABLAAECggICwAEAAAAAA==.Yanck:BAAALAAECgYICgAAAA==.',Za='Zalana:BAAALAAECgYIDQAAAA==.',Ze='Zeno:BAAALAADCgUIBQAAAA==.Zentila:BAABLAAECoEfAAIkAAcIpSDXDACDAgAkAAcIpSDXDACDAgABLAAFFAYIEgAWAFsYAA==.Zernichtung:BAABLAAECoEaAAIYAAgIohJqRgDrAQAYAAgIohJqRgDrAQAAAA==.Zerspaltung:BAAALAADCgQIBgABLAAECggIGgAYAKISAA==.',Zi='Ziva:BAAALAADCggICAAAAA==.',['Êx']='Êxó:BAABLAAECoElAAIJAAgI5iFUGgDvAgAJAAgI5iFUGgDvAgAAAA==.',['Ðo']='Ðorfmofa:BAAALAADCggICAAAAA==.',['Ño']='Ñova:BAAALAAECggIDAAAAA==.',['Ñø']='Ñøva:BAAALAAECggIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end