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
 local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Balance','Hunter-BeastMastery','Warlock-Demonology','Warlock-Destruction','Priest-Shadow','Mage-Arcane','Warlock-Affliction','Warrior-Arms','Warrior-Protection','Shaman-Restoration','Evoker-Devastation','Evoker-Preservation','Unknown-Unknown','Paladin-Retribution','Shaman-Enhancement','Paladin-Holy','Druid-Restoration','DeathKnight-Unholy','Druid-Feral','Druid-Guardian','Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Shaman-Elemental','Evoker-Augmentation',}; local provider = {region='EU',realm='Mazrigos',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aattrox:BAABLAAECoEnAAMBAAcIBxYkWQDnAQABAAcIiBUkWQDnAQACAAIIDRmWQwCGAAAAAA==.',Ad='Adelia:BAAALAADCgYIDAAAAA==.',Ak='Akane:BAABLAAECoEdAAIDAAgIqxAdOwCSAQADAAgIqxAdOwCSAQAAAA==.',Al='Alsarath:BAAALAAECgUICgAAAA==.',An='Anarcrothe:BAAALAADCgcIBgAAAA==.Angelluss:BAACLAAFFIEKAAIEAAIIxBjzLQCEAAAEAAIIxBjzLQCEAAAsAAQKgR8AAgQACAh7G6Y1ADsCAAQACAh7G6Y1ADsCAAAA.Angrymuffin:BAAALAADCggIEAAAAA==.Annelise:BAAALAADCgMIAwAAAA==.',Ar='Arkadia:BAAALAADCgcIDAAAAA==.Arkaedus:BAABLAAECoEdAAMFAAgI7hRaGgAGAgAFAAgI7hRaGgAGAgAGAAII0hLouwB1AAAAAA==.Arrivol:BAACLAAFFIEMAAIHAAMIVBkiDAD4AAAHAAMIVBkiDAD4AAAsAAQKgSQAAgcACAgDIywKABYDAAcACAgDIywKABYDAAAA.',As='Ashar:BAAALAADCggICAAAAA==.Astoxidis:BAABLAAECoEVAAIEAAYIHQUuvwDnAAAEAAYIHQUuvwDnAAAAAA==.',At='Atreu:BAAALAADCgYIEQAAAA==.',Av='Avrem:BAAALAADCgQICAAAAA==.',Az='Azaliya:BAAALAAECgMIAwAAAA==.Aziray:BAAALAAECgYICQAAAA==.Azniren:BAAALAADCgIIAgAAAA==.Azzimage:BAABLAAECoEYAAIIAAYIQgyvhABXAQAIAAYIQgyvhABXAQAAAA==.',Ba='Backstabs:BAAALAADCggIBwAAAA==.Badomens:BAAALAADCgcIBwAAAA==.',Be='Belatherix:BAAALAADCgYIBgAAAA==.',Bi='Billibob:BAAALAAECgEIAQAAAA==.',Bu='Bumbumpoc:BAAALAAECgMIAwAAAA==.Burritos:BAAALAADCgYIBwAAAA==.Butchvirgo:BAAALAADCgYIBgAAAA==.',['Bæ']='Bædønthurtmë:BAAALAADCgcIDgAAAA==.',Ca='Capensis:BAAALAADCggIEQABLAAECggIIQAIAHcQAA==.Carthego:BAAALAADCggIDwAAAA==.Caseille:BAAALAADCgYIBgAAAA==.Cayles:BAAALAAECgQICAAAAA==.',Cb='Cballs:BAABLAAECoEdAAQGAAgIHSRGHAC6AgAGAAcIOSRGHAC6AgAFAAYIVh14KQCrAQAJAAEI5AyQNgBEAAAAAA==.',Ce='Ceire:BAAALAAECgEIAQAAAA==.Cerulrath:BAAALAAECgYIEgABLAAFFAMIDAAHAFQZAA==.',Ch='Chilla:BAABLAAECoEZAAMKAAcIXyQ5AwDvAgAKAAcIXyQ5AwDvAgALAAEIVxIOeAAoAAAAAA==.Choppaninyo:BAAALAADCgEIAQAAAA==.',Co='Corukh:BAAALAADCggICAABLAAECgcIGQAKAF8kAA==.',Cr='Cruz:BAAALAADCggICAAAAA==.',Ct='Cthullu:BAAALAAECgEIAQABLAAECggIFwAMAGMUAA==.',Da='Daria:BAAALAAECgUIDgAAAA==.Darlíng:BAAALAAECgUIEAAAAA==.Darow:BAAALAADCggIHAAAAA==.',De='Dealylama:BAAALAAECgYIEAAAAA==.Devinecow:BAAALAAECggIEAAAAA==.',Do='Dolarel:BAAALAADCggIGAAAAA==.Douce:BAAALAADCgYIBgAAAA==.',Dr='Dracaris:BAACLAAFFIEIAAINAAIItBRPEQCaAAANAAIItBRPEQCaAAAsAAQKgRwAAw0ACAhrGmoVAGACAA0ACAhrGmoVAGACAA4AAwgXBY0vAHcAAAEsAAUUAggKAAQAxBgA.Draggus:BAAALAADCggIEAABLAAECggIJgAEACUUAA==.Drama:BAAALAADCggICAAAAA==.Dreamie:BAAALAAECgMIAwAAAA==.Drêåd:BAABLAAECoEUAAIMAAYIhCMkKABIAgAMAAYIhCMkKABIAgAAAA==.',Du='Durwin:BAAALAADCgYICAAAAA==.',Eb='Ebenezergood:BAAALAADCggICAABLAAECgQICAAPAAAAAA==.',Ed='Ednarix:BAABLAAECoEdAAIQAAcIrBq9SQAvAgAQAAcIrBq9SQAvAgAAAA==.',Eh='Ehunterharry:BAAALAADCgUIBQAAAA==.',El='Elariah:BAAALAADCgYIBgAAAA==.Elivia:BAABLAAECoEVAAIRAAcI5xcsDgDZAQARAAcI5xcsDgDZAQAAAA==.Elmroot:BAAALAADCgMIAwAAAA==.Eloise:BAAALAADCgYIBgAAAA==.',En='Endeavor:BAABLAAECoElAAMSAAgIBQjWMgBkAQASAAgIBQjWMgBkAQAQAAYI0AMM5wDjAAAAAA==.Engora:BAAALAAECggIBAAAAA==.',Ew='Ewilyn:BAABLAAFFIEFAAIMAAIIAgo2OABwAAAMAAIIAgo2OABwAAABLAAFFAIICgAEAMQYAA==.',Fa='Faerill:BAAALAAECgYIEgAAAA==.Faiythe:BAAALAAECgQIBwAAAA==.',Fe='Felbíte:BAAALAAECgcIEAAAAA==.Feral:BAAALAADCgIIAgAAAA==.',Ga='Gabinka:BAAALAADCgcIBwAAAA==.Garks:BAAALAAECgEIAQAAAA==.Garnath:BAAALAAECgEIAQAAAA==.',Ge='Gengir:BAABLAAECoEaAAMDAAgIjRK+MwC3AQADAAcIDhO+MwC3AQATAAcIBA3wUwBSAQAAAA==.',Gi='Gibbs:BAABLAAECoEUAAIQAAcIIwy0kwCNAQAQAAcIIwy0kwCNAQAAAA==.',Gr='Gromshy:BAAALAAECgIIAgABLAAECggIGgADAI0SAA==.Groulfor:BAAALAAECgYICgAAAA==.Grromash:BAAALAADCggIDAAAAA==.',Gy='Gyatt:BAAALAADCgEIAQAAAA==.',Ha='Hagbard:BAABLAAECoEUAAISAAYIygdiRAABAQASAAYIygdiRAABAQAAAA==.Haryi:BAAALAAECgUICAAAAA==.Hassedeathz:BAAALAADCgIIAgAAAA==.Hawkblade:BAACLAAFFIENAAIUAAUIrx4lAQCVAQAUAAUIrx4lAQCVAQAsAAQKgRcAAhQACAjzJcUBAE8DABQACAjzJcUBAE8DAAAA.',He='Hellios:BAAALAADCgEIAQAAAA==.',Hi='Highlander:BAAALAADCgYICwAAAA==.Hitmonjam:BAAALAAECgYICQAAAA==.',Ho='Holyazzi:BAAALAADCggICAAAAA==.Holysheeyt:BAAALAAECgQIBgAAAA==.',Hu='Hubavelka:BAABLAAECoEUAAIIAAcIDwcYhgBTAQAIAAcIDwcYhgBTAQAAAA==.',['Hä']='Hästpräst:BAAALAAECgYICgAAAA==.',Ia='Iamdruid:BAAALAAECgYICgAAAA==.',Il='Illirage:BAAALAADCgUIBQAAAA==.',Io='Iol:BAAALAAECgMICAAAAA==.',Je='Jesster:BAAALAADCggIDwAAAA==.',Jo='Johnsmith:BAAALAAECgUIDgAAAA==.Jorgoman:BAAALAADCgcIBwAAAA==.',Ka='Kaela:BAAALAAECgcIBAAAAA==.Kagome:BAAALAADCggIEAABLAAECggIKQATAJoUAA==.Kaiyra:BAAALAADCgUIBQAAAA==.Karkand:BAAALAADCggIEAAAAA==.',Kh='Khabecim:BAAALAADCggIFwAAAA==.',Ki='Killerweasel:BAAALAAECgcIEgABLAAECgQICAAPAAAAAA==.Kinara:BAAALAAECggIEwAAAA==.Kiritomusha:BAAALAAECgIIAgAAAA==.Kiyomi:BAABLAAECoEXAAINAAcIYRTYJQDHAQANAAcIYRTYJQDHAQAAAA==.',Ko='Komarcek:BAAALAAECgYICwAAAA==.',Kr='Krexx:BAABLAAECoEWAAUTAAgIuhlyJwAUAgATAAcIwBpyJwAUAgAVAAUIXhMXLwC7AAADAAMIbxOEaQC2AAAWAAIIRRKGJAB2AAABLAAECggIIAAHACIZAA==.',Kv='Kvinnfolket:BAAALAADCggIFgAAAA==.',La='Lapun:BAABLAAECoEhAAIIAAgIdxDkUwDiAQAIAAgIdxDkUwDiAQAAAA==.',Le='Leonardo:BAAALAAECgcIAQAAAA==.Leporidae:BAAALAADCggIDAABLAAECggIIQAIAHcQAA==.',Li='Lidrin:BAAALAAECggIEQAAAA==.Littlebige:BAAALAADCggIDQAAAA==.',Lu='Lukadh:BAAALAAECggIDgAAAA==.Lumiruusa:BAAALAADCggICAAAAA==.',Ma='Maddicuss:BAAALAADCgYICAAAAA==.Madstepsx:BAAALAADCgEIAQAAAA==.Mahemi:BAAALAAECgIIAgAAAA==.Mariamukry:BAAALAADCgYIBgAAAA==.Marmelladin:BAAALAAECgUIDgAAAA==.Marmellin:BAAALAAECgIIAgABLAAECgUIDgAPAAAAAA==.Massblast:BAAALAAECgIIAgAAAA==.Mayuri:BAAALAAECgYIBwAAAA==.',Me='Megastides:BAAALAAECgUIBQABLAAFFAIICgAEAMQYAA==.Meh:BAAALAADCgYIEAAAAA==.Mercus:BAAALAAECgQIBAABLAAECgcIHwADAMskAA==.Merendis:BAAALAAECgYICwAAAA==.',Mi='Mildread:BAAALAADCggICgAAAA==.Minothauri:BAAALAADCggICgAAAA==.',Mo='Mohawk:BAAALAAECgcIDQAAAA==.Monkeyhealer:BAAALAADCggIKQAAAA==.Moongoddess:BAAALAADCgYIBgABLAAECgYICAAPAAAAAA==.Motomatsu:BAAALAAECgcIBwAAAA==.',Mu='Munnu:BAAALAAECggIAgAAAA==.',Na='Nagini:BAAALAAECgUIDAAAAA==.Nahlind:BAAALAADCggICQAAAA==.',Ne='Nebuchadnezz:BAAALAADCgEIAQAAAA==.Neeya:BAAALAADCgUIBQAAAA==.Nemetsk:BAACLAAFFIEOAAMGAAQIRBRNDwBTAQAGAAQIRBRNDwBTAQAFAAEIaQtOIgBMAAAsAAQKgSQAAwYACAjMH/kTAPACAAYACAjMH/kTAPACAAUABwgJEdwoAK8BAAEsAAUUAwgMAAcAVBkA.',No='Nooni:BAAALAAECggICAAAAA==.',Nr='Nrala:BAABLAAECoEmAAIEAAgIJRRPVADYAQAEAAgIJRRPVADYAQAAAA==.',Nu='Nubbski:BAAALAAECgYIDwAAAA==.Nuclearpala:BAAALAADCggIEwAAAA==.Nusherina:BAAALAADCgcICAAAAA==.Nushina:BAABLAAECoEUAAMXAAYIZhCfHADGAAAYAAYIuw0gYAAyAQAXAAQI/w+fHADGAAAAAA==.',Ob='Obasen:BAAALAAECgYICwAAAA==.',Or='Orylag:BAAALAADCggICAAAAA==.',Pa='Pahar:BAAALAAECgQIBAAAAA==.Patek:BAAALAAECggICAAAAA==.',Pe='Penguin:BAAALAADCgcIBwAAAA==.',Ph='Philipe:BAAALAAECgcIBAAAAA==.',Pi='Pim:BAABLAAECoEjAAMSAAgIsiK/AgAmAwASAAgIsiK/AgAmAwAQAAMIawQgDwF+AAAAAA==.Pimm:BAAALAADCgcIBwABLAAECggIIwASALIiAA==.',Pr='Process:BAAALAADCgcIEAAAAA==.Prothnus:BAABLAAECoErAAIWAAgIUCN+AQBBAwAWAAgIUCN+AQBBAwAAAA==.',Ra='Ramash:BAAALAAECgMIAwAAAA==.Ravenshadow:BAAALAAECgYIDAABLAAECggIEwAPAAAAAA==.',Re='Realion:BAAALAADCggIEAAAAA==.Redwynd:BAABLAAECoEVAAIYAAYIwwRxdADuAAAYAAYIwwRxdADuAAAAAA==.Resisto:BAAALAAECgUIDgAAAA==.',Rh='Rhika:BAAALAADCgYIBgAAAA==.',Ri='Ripped:BAACLAAFFIEJAAILAAUIVBcEAwDBAQALAAUIVBcEAwDBAQAsAAQKgRgAAwoACAhfH7sGAHMCAAoACAhBHLsGAHMCAAsABghBIgEXAEMCAAAA.Ritual:BAAALAAECgQIBQABLAAECgcIFgALAI0eAA==.',Ro='Rocksalt:BAAALAADCggIGQAAAA==.',['Rö']='Rölli:BAAALAADCggIDgAAAA==.',Sa='Salemcraft:BAABLAAECoEPAAIFAAYIPxaLKwChAQAFAAYIPxaLKwChAQABLAAFFAIICgAEAMQYAA==.Sawator:BAAALAAECgEIAQAAAA==.Sayf:BAAALAAECgEIAQAAAA==.',Sc='Scai:BAAALAAECgcIEwABLAAECggILAALADMbAA==.',Se='Separi:BAAALAADCgYIBgAAAA==.Sewwal:BAABLAAECoElAAMEAAgIwRB6XgC+AQAEAAgIwRB6XgC+AQAZAAMISAMWpAA/AAAAAA==.',Sh='Shamanstyles:BAABLAAECoEXAAQMAAgIYxRQYQCNAQAMAAcI2xJQYQCNAQAaAAQIGwSSmgBfAAARAAEI3AHdJQAXAAAAAA==.Shanai:BAAALAAECgYIBwAAAA==.Shindriell:BAABLAAECoEgAAMHAAcIIhn1LAD4AQAHAAcIIhn1LAD4AQAXAAUI6BgiEQBZAQAAAA==.Shirai:BAABLAAECoEYAAMbAAYIYQ1+DAA9AQAbAAYIYQ1+DAA9AQAOAAYI5w8XIQAYAQABLAAECggIIAAHACIZAA==.Shiso:BAAALAAECgYIBgAAAA==.Shuitu:BAABLAAECoEZAAIMAAgIfhNkUgC2AQAMAAgIfhNkUgC2AQABLAAECggIIAAHACIZAA==.',Sj='Sjukdom:BAAALAADCgYICAAAAA==.',Sk='Skelde:BAAALAAECggIEgABLAAECggIIQAZAFMTAA==.',St='Stiil:BAABLAAECoEmAAITAAgItR3jDwCzAgATAAgItR3jDwCzAgAAAA==.',Ta='Tacticus:BAABLAAECoEhAAMZAAgIUxPBOQC0AQAZAAgIXxHBOQC0AQAEAAYIxA/tgQBtAQAAAA==.Tahlut:BAAALAAECgYIBgAAAA==.',Te='Tessarion:BAABLAAECoEZAAMOAAcIaxSWEwC/AQAOAAcIaxSWEwC/AQANAAUInRYaNgBVAQAAAA==.',Th='Thejudge:BAAALAAECggICAAAAA==.Thekaypriest:BAACLAAFFIELAAIYAAUIVxk2BwBmAQAYAAUIVxk2BwBmAQAsAAQKgS0ABBgACAhPJDkEAEYDABgACAhPJDkEAEYDAAcAAwhIEt1qALcAABcAAwgaEWMfAKoAAAAA.Thekayshaman:BAAALAADCggICAABLAAFFAUICwAYAFcZAA==.',To='Toive:BAAALAAECgMICAAAAA==.Tossuman:BAAALAAECgMICAAAAA==.Totemklarna:BAAALAADCggICAAAAA==.',Tr='Trap:BAABLAAECoEWAAIEAAgILhLNbQCZAQAEAAgILhLNbQCZAQABLAAFFAYIGQAGAOgfAA==.',Ts='Tsukimusha:BAAALAADCggIGwAAAA==.Tsún:BAAALAAECgEIAQAAAA==.Tsúnzu:BAAALAAECgMIAgAAAA==.',Ty='Tyraumort:BAAALAAECggICAAAAA==.',Va='Varthyr:BAAALAADCgcIBwAAAA==.',Ve='Velynar:BAAALAAECgYIDQAAAA==.Veridis:BAAALAAECgUIBwAAAA==.Vesanus:BAAALAADCgUIBgAAAA==.',Vo='Vogusan:BAAALAADCgQIBAAAAA==.',Vu='Vulzalh:BAAALAADCgYICQAAAA==.',Wa='Warweasel:BAAALAAECgQICAAAAA==.',Xe='Xeal:BAACLAAFFIEHAAIGAAMIFRpPFAAJAQAGAAMIFRpPFAAJAQAsAAQKgR0AAwYACAihI2URAAIDAAYACAihI2URAAIDAAkAAggzCNIuAGQAAAAA.Xelyth:BAABLAAECoEdAAIHAAcI9RS9MwDSAQAHAAcI9RS9MwDSAQAAAA==.Xerphos:BAAALAADCgEIAgAAAA==.',Ya='Yamihime:BAAALAADCggICAAAAA==.',['Yö']='Yöruichi:BAAALAAECgUICQAAAA==.',Za='Zandhal:BAAALAAECgYICQAAAA==.Zayn:BAAALAAECgcIEwAAAA==.',Ze='Zedardai:BAAALAADCgUIBQABLAAECggIJAAVAD0gAA==.Zefer:BAABLAAECoEZAAITAAcIESG3FACKAgATAAcIESG3FACKAgAAAA==.',Zi='Zirriath:BAAALAADCgYIEQAAAA==.',['ßa']='ßadßoy:BAAALAAECgYIBgABLAAFFAIICgAEAMQYAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end