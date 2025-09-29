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
 local lookup = {'Mage-Frost','Monk-Mistweaver','DemonHunter-Havoc','Mage-Arcane','Paladin-Retribution','Hunter-BeastMastery','Warrior-Fury','Priest-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Priest-Shadow','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','Shaman-Enhancement','Monk-Windwalker','Hunter-Marksmanship','Shaman-Restoration','Paladin-Holy','Druid-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Blood','Warrior-Protection','Paladin-Protection','Mage-Fire',}; local provider = {region='EU',realm="TheSha'tar",name='EU',type='weekly',zone=44,date='2025-09-23',data={Aa='Aardin:BAAALAADCgEIAQABLAAECggIIwABAEkgAA==.',Ac='Achlys:BAAALAAECgIIAgAAAA==.',Ae='Aehra:BAABLAAECoEWAAICAAcI2wlrKQAdAQACAAcI2wlrKQAdAQAAAA==.Aelia:BAAALAAECgQIBgAAAA==.Aelria:BAACLAAFFIEJAAIDAAMIbRy4DwAKAQADAAMIbRy4DwAKAQAsAAQKgScAAgMACAj5IhwRABYDAAMACAj5IhwRABYDAAAA.Aeonya:BAAALAADCggIDwAAAA==.',Af='Afye:BAAALAADCgMIBAABLAAECggIHwAEAI4gAA==.Afyxpaladin:BAABLAAECoEUAAIFAAcIThTQeADEAQAFAAcIThTQeADEAQABLAAECggIHwAEAI4gAA==.',Ah='Ahrimhyn:BAAALAAECgcIBwAAAA==.',Al='Alamak:BAAALAADCgUICQAAAA==.Alatáriel:BAAALAAECgQIBAAAAA==.Alenêa:BAABLAAECoEjAAIGAAcIDhLydQCMAQAGAAcIDhLydQCMAQAAAA==.Alieadore:BAAALAADCgcIBwAAAA==.Alliwar:BAABLAAECoEXAAIHAAYIUCBVNAAtAgAHAAYIUCBVNAAtAgAAAA==.Almighty:BAAALAADCgQIBwAAAA==.Altegos:BAAALAAECgYIEAAAAA==.',An='Analda:BAAALAAECgYIEgAAAA==.',Ao='Aodha:BAAALAAECgYIEQAAAA==.',Aq='Aquadevil:BAAALAAECggIBgAAAA==.',Ar='Archonas:BAAALAADCgIIAgAAAA==.Arcstwin:BAAALAAECggICAAAAA==.Arius:BAAALAAECgQIBAAAAA==.Arreas:BAAALAAECgcICwAAAA==.Arthoríus:BAACLAAFFIEFAAIFAAIImgnSOACOAAAFAAIImgnSOACOAAAsAAQKgRgAAgUACAg0GflAAEwCAAUACAg0GflAAEwCAAAA.Arvensis:BAABLAAECoEUAAIIAAYIDgYLcwD4AAAIAAYIDgYLcwD4AAAAAA==.',As='Assos:BAAALAADCggIEQAAAA==.',Au='Augustipo:BAAALAADCggIHQAAAA==.Aurora:BAAALAAECgUICQAAAA==.',Az='Azaila:BAAALAADCgcIBwAAAA==.Azgor:BAAALAADCggICAAAAA==.',['Aé']='Aéther:BAAALAAECgcIDgAAAA==.',Ba='Baelmun:BAAALAAECgUICAAAAA==.Baelos:BAAALAADCggICAAAAA==.Bahämut:BAACLAAFFIEHAAIJAAMI+QrFAwDbAAAJAAMI+QrFAwDbAAAsAAQKgSUAAgkABwghHKAEAEwCAAkABwghHKAEAEwCAAAA.Bailsong:BAABLAAECoEaAAMKAAcIYBYWMQB3AQAKAAYIyhMWMQB3AQALAAcIaw4uGgBsAQAAAA==.Bananas:BAABLAAECoEUAAMIAAcIQg7hTQB4AQAIAAcIQg7hTQB4AQAMAAEIowmnjAArAAAAAA==.Baxii:BAAALAADCggIDgAAAA==.',Be='Be:BAACLAAFFIEJAAMNAAQItw1yEQA+AQANAAQItw1yEQA+AQAOAAIISwsPFQCMAAAsAAQKgS4ABA0ACAhwIMwZAM4CAA0ACAjJH8wZAM4CAA4ABggIHTkaAAkCAA8AAwh3FBEdAOwAAAAA.Benglish:BAAALAAECgIIBAAAAA==.Berthbrew:BAAALAAECgYIBgAAAA==.',Bi='Bigdragonuk:BAAALAADCgEIAQABLAAECgUICAAQAAAAAA==.',Bl='Blackpink:BAAALAAECgIIAQAAAA==.Bleaik:BAAALAAECgIIAgAAAA==.Blinkblin:BAABLAAECoEoAAIBAAgIQhtxEQB0AgABAAgIQhtxEQB0AgAAAA==.Blitzø:BAAALAADCgYIBgABLAAECgIIAgAQAAAAAA==.Bloodforgive:BAAALAADCggICAAAAA==.',Bo='Bolverkr:BAABLAAECoEVAAMNAAgIcQ1zVQC5AQANAAgIQgxzVQC5AQAOAAYIFAt6QwA8AQAAAA==.Bonnybon:BAAALAADCgcICQAAAA==.Bos:BAAALAADCggIDwAAAA==.',Br='Brenwan:BAABLAAECoEYAAIRAAcIgBWWDAD7AQARAAcIgBWWDAD7AQAAAA==.Brockus:BAAALAAFFAIIAwAAAA==.',Bu='Bupsik:BAAALAADCggIDwABLAAECggIEQAQAAAAAA==.',Ca='Cach:BAAALAAECgYIDQAAAA==.Caladrius:BAAALAADCggIDwAAAA==.Callixtus:BAAALAADCgcIBwAAAA==.Cartoons:BAAALAAECgEIAQAAAA==.',Ce='Cele:BAABLAAECoEaAAMSAAgIbhviDwB9AgASAAgIbhviDwB9AgACAAMI7QfuPAB7AAAAAA==.',Ch='Chamsin:BAAALAADCggICQAAAA==.Chaosnoodle:BAAALAAECgQIBAABLAAECggIJAACABEaAA==.Chaupté:BAAALAAECgYICAAAAA==.Chrysaor:BAAALAADCgcIBwAAAA==.',Co='Coeus:BAABLAAECoEfAAIEAAgIjiBWFQDyAgAEAAgIjiBWFQDyAgAAAA==.Contempt:BAABLAAECoEkAAMGAAgI5SQLCAA+AwAGAAgI5SQLCAA+AwATAAYIuBOkTgBeAQAAAA==.',Cr='Cressidae:BAAALAAECgYIEAAAAA==.',Da='Daffid:BAABLAAECoEbAAIIAAgI+w7+PQC5AQAIAAgI+w7+PQC5AQAAAA==.Dafid:BAAALAADCggICQAAAA==.Dagath:BAAALAADCggIEAAAAA==.Dairon:BAAALAAECgcIEwAAAA==.Darkstyler:BAAALAADCgEIAQAAAA==.',De='Deathwhisper:BAAALAAECgEIAgAAAA==.Deckedout:BAAALAAECgQIBAABLAAECgQICQAQAAAAAA==.Delola:BAACLAAFFIEGAAIGAAIIdBM/KQCPAAAGAAIIdBM/KQCPAAAsAAQKgSwAAgYACAjoIXQWANoCAAYACAjoIXQWANoCAAEsAAUUAggIAAUAiBwA.Delori:BAACLAAFFIEIAAIFAAIIiBwtHACzAAAFAAIIiBwtHACzAAAsAAQKgS0AAgUACAhIJGcIAFUDAAUACAhIJGcIAFUDAAAA.Delulu:BAAALAAECgYIDQABLAAFFAIICAAFAIgcAA==.Demonchase:BAAALAAECggIEAAAAA==.',Dh='Dharek:BAAALAADCgcICQABLAADCggIEAAQAAAAAA==.',Di='Dian:BAABLAAFFIEJAAINAAYIoBLhBgAFAgANAAYIoBLhBgAFAgAAAA==.Diane:BAAALAAECgYICgAAAA==.Diara:BAAALAADCggIDAAAAA==.Dieven:BAAALAAECgQIBAAAAA==.Digitalocean:BAAALAAECgUIBQAAAA==.Dironel:BAAALAAECgIIAgAAAA==.',Dr='Dragonite:BAABLAAECoEgAAIKAAgI2Ri/FwBJAgAKAAgI2Ri/FwBJAgABLAAFFAIIBwAUAOseAA==.',Du='Dumari:BAAALAAECgMIAwAAAA==.Durreos:BAAALAAECggIEwAAAA==.',['Dø']='Dødsdrengen:BAAALAADCgYIBQAAAA==.',Eb='Ebiglogbe:BAAALAADCgcIBwAAAA==.',El='Ellyara:BAAALAADCggIDgAAAA==.Elorë:BAAALAAECgEIAQAAAA==.Elwari:BAAALAAECgYIBgAAAA==.Elyra:BAAALAADCgcIBwAAAA==.',Em='Emb:BAAALAAECgYICgAAAA==.',Et='Ethenone:BAAALAAECgUIBQAAAA==.Etherweed:BAAALAAECgYIBgAAAA==.',Ev='Evikin:BAAALAADCggICAAAAA==.',Fa='Faeridius:BAAALAADCgEIAQAAAA==.Faith:BAABLAAECoEgAAIVAAgInxh7FABBAgAVAAgInxh7FABBAgAAAA==.Falthas:BAAALAADCgYIBgAAAA==.Falthus:BAAALAAECgYIEgAAAA==.',Fi='Fission:BAAALAAECgQICQAAAA==.',Fl='Flexie:BAABLAAECoEYAAIDAAcI6wrojgB1AQADAAcI6wrojgB1AQAAAA==.Flufy:BAABLAAFFIEIAAIWAAII8BSnHACQAAAWAAII8BSnHACQAAAAAA==.',Fn='Fnxbuss:BAAALAADCggICAABLAAFFAYIFAAXAFkhAA==.',Fo='Forang:BAAALAAECgQICgAAAA==.Foxielady:BAAALAADCggIGgAAAA==.',Fr='Freejon:BAACLAAFFIEPAAMYAAUI9SBdAgBFAQAYAAMITSZdAgBFAQAXAAMIQx2pEAAjAQAsAAQKgSYAAxcACAhEJVMqAKACABcABwjUJFMqAKACABgABAi+JVMcAL8BAAAA.Fruitpaste:BAACLAAFFIEHAAIZAAMInxROCQADAQAZAAMInxROCQADAQAsAAQKgTEAAxkACAjkIvUGAAcDABkACAjkIvUGAAcDABoAAQhNEv9AAD4AAAAA.',Ge='Getåfix:BAAALAADCgMIAwABLAADCgcIBwAQAAAAAA==.',Gh='Ghaos:BAAALAAECgYIEwAAAA==.Ghuoldan:BAAALAADCgcIDAAAAA==.',Gl='Glorim:BAAALAAECgcIEQAAAA==.',Gr='Grengan:BAABLAAECoEcAAIbAAcIRw/KSgCqAQAbAAcIRw/KSgCqAQAAAA==.Greytlee:BAABLAAECoEUAAIcAAgINCSxBAAVAwAcAAgINCSxBAAVAwAAAA==.Griffy:BAABLAAFFIEHAAIUAAII6x7pGQC1AAAUAAII6x7pGQC1AAAAAA==.Grimlock:BAAALAADCgQIBwAAAA==.Grúmpz:BAAALAAECggIDwAAAA==.',Ha='Happydotter:BAAALAADCggIDwAAAA==.Harkevich:BAABLAAECoEbAAIHAAgIVgoMYwCJAQAHAAgIVgoMYwCJAQAAAA==.',He='Helenikemen:BAAALAAECggIBgABLAAFFAgIAgAQAAAAAA==.',Hi='Hialoun:BAABLAAECoEfAAMCAAcIZBB4HwB5AQACAAcIZBB4HwB5AQASAAIIlQP3UgBMAAAAAA==.',Ho='Hog:BAAALAAECgcIEQAAAA==.Hornblack:BAAALAADCggICAAAAA==.Hozorun:BAAALAADCgcIDQAAAA==.',Hu='Huntarina:BAAALAADCggICAAAAA==.Hunvel:BAAALAAECgYIDwAAAA==.',Il='Ilisara:BAAALAAECgYIDAAAAA==.Illien:BAAALAAECgMIAwAAAA==.Ilufana:BAAALAAECgQICAAAAA==.',Im='Imizael:BAABLAAECoEcAAIHAAcIEBjqPwD9AQAHAAcIEBjqPwD9AQAAAA==.',In='Inanna:BAAALAADCgcICQAAAA==.Indraneth:BAAALAAECgcIEwAAAA==.',Ir='Irkalla:BAAALAADCgYIBgABLAADCgcICQAQAAAAAA==.',Is='Isuckatnames:BAAALAADCggICAABLAADCgYIDQAQAAAAAA==.',It='Ittygritty:BAAALAADCgUIBQAAAA==.',Je='Jerboa:BAABLAAECoEaAAIGAAgIhCBSIQCbAgAGAAgIhCBSIQCbAgAAAA==.',Ji='Jineve:BAABLAAECoEYAAITAAgIVQwzSAB4AQATAAgIVQwzSAB4AQAAAA==.',['Jú']='Jústícé:BAAALAADCgUIAQAAAA==.',Ka='Kardam:BAAALAAECgEIAQAAAA==.Kaziel:BAAALAAECgYICAAAAA==.',Kj='Kjelde:BAAALAAFFAEIAQAAAA==.',Kl='Klaskadin:BAAALAAECgYICgAAAA==.',Kn='Knezir:BAAALAAECgQICQAAAA==.',Ko='Kolkman:BAAALAADCgIIAgABLAADCggIDwAQAAAAAA==.',Ku='Kurzog:BAAALAAECgIIAgAAAA==.',La='Laskey:BAAALAAECgEIAQAAAA==.Lays:BAABLAAECoEhAAMDAAgI9CH6EAAXAwADAAgI1CH6EAAXAwAdAAMISyacJQBKAQAAAA==.',Le='Lemmony:BAAALAAECgQICwAAAA==.',Li='Lightningz:BAAALAAECgYICAAAAA==.Lilystar:BAAALAAECgYIEQAAAA==.',Lo='Loverbull:BAAALAAECgcIEwAAAA==.',Lu='Lunadawn:BAAALAAECgIIAgAAAA==.Lundsham:BAAALAADCggICAAAAA==.Lundsveen:BAAALAAECgIIAgAAAA==.Lundsvinet:BAAALAADCgYICgAAAA==.',Ly='Lyaelor:BAAALAADCgEIAQABLAAECgcIGwAFAIodAA==.',['Lí']='Lía:BAAALAAECgIIAgAAAA==.',Ma='Magfaeridon:BAAALAADCgcIDQAAAA==.Magfiredon:BAAALAADCgQIBAAAAA==.Malaarad:BAAALAADCgEIAQABLAAECgcIEwAQAAAAAA==.Malachór:BAAALAAECgMIAwAAAA==.Malakin:BAABLAAECoEUAAIDAAcI5iIjHgDLAgADAAcI5iIjHgDLAgAAAA==.Mammu:BAAALAADCggIFwAAAA==.Manapoly:BAABLAAECoEgAAIeAAcIFA/PHABkAQAeAAcIFA/PHABkAQAAAA==.Maraat:BAAALAAECgEIAQAAAA==.Marcine:BAAALAAECgcIEAAAAA==.Maxïmo:BAAALAAECgQICwAAAA==.',Mc='Mcfappious:BAAALAAECgYIEQAAAA==.Mcgun:BAAALAADCgYIBgAAAA==.',Me='Megwyn:BAABLAAECoEcAAIXAAgI5h/+FgD7AgAXAAgI5h/+FgD7AgAAAA==.Mercsy:BAABLAAECoEaAAIFAAgI1QxVgQCzAQAFAAgI1QxVgQCzAQAAAA==.Merlot:BAAALAAECgUIBQAAAA==.Metrovoid:BAAALAAECgMIAwAAAA==.Meximo:BAAALAADCggIDAAAAA==.',Mi='Mikira:BAAALAADCgcICgAAAA==.Milgrym:BAAALAAECgEIAQAAAA==.Milne:BAAALAAECgcICwAAAA==.Mindafy:BAAALAADCggICAAAAA==.Missandy:BAAALAADCggIDwAAAA==.Missbhave:BAAALAAECgYIEgAAAA==.Misself:BAAALAAECggIEQAAAA==.',My='Myrmidons:BAACLAAFFIEJAAIBAAQIyxqeAQBmAQABAAQIyxqeAQBmAQAsAAQKgS4AAgEACAjBJA0DAFQDAAEACAjBJA0DAFQDAAAA.',Na='Naristi:BAAALAADCggIGAAAAA==.Nathari:BAAALAADCgYIBwAAAA==.Nathelsa:BAAALAAECgYIEAAAAA==.',Ne='Neracio:BAAALAADCggICAAAAA==.Neruatnamash:BAABLAAECoEaAAMRAAcIQQ+0EwB+AQARAAcI0w60EwB+AQAbAAMIcwlNjwCUAAAAAA==.',Ni='Nirco:BAABLAAECoEUAAIfAAcIDBtmGQAuAgAfAAcIDBtmGQAuAgAAAA==.Nirtak:BAAALAAECggIEQAAAA==.',No='Noralina:BAAALAADCgYIEAAAAA==.Nour:BAAALAADCgcIBwAAAA==.Novaknight:BAAALAADCgYIBwABLAAECgcIDgAQAAAAAA==.Novalok:BAAALAAECgcIDgAAAA==.Novawólf:BAAALAADCggIFAABLAAECgcIDgAQAAAAAA==.',['Nó']='Nóva:BAAALAAECgcIDQABLAAECgcIDgAQAAAAAA==.',['Nø']='Nøvawølf:BAAALAAECgQIBAABLAAECgcIDgAQAAAAAA==.',Ob='Obichewie:BAAALAAFFAIIAgABLAAFFAIICAAXADwkAA==.Obihave:BAACLAAFFIEIAAIXAAIIPCQwHADUAAAXAAIIPCQwHADUAAAsAAQKgSYAAxcACAgUIywRABoDABcACAjuIiwRABoDABgABQi1HTIhAJcBAAAA.Obihiro:BAABLAAECoEeAAISAAcI+hoUGAAZAgASAAcI+hoUGAAZAgABLAAFFAIICAAXADwkAA==.Obinobi:BAAALAADCggICAABLAAFFAIICAAXADwkAA==.Obisama:BAABLAAFFIEFAAIDAAII5xnpIQCjAAADAAII5xnpIQCjAAABLAAFFAIICAAXADwkAA==.',Os='Oshosi:BAAALAAECgYIBgABLAAECggIFQANAHENAA==.',Pa='Palnaru:BAAALAAECgYIDgAAAA==.Parra:BAAALAADCggIDwAAAA==.Parzivaleu:BAAALAAECgQIBAAAAA==.',Pi='Pingunoot:BAAALAAECgcICgAAAA==.Pixí:BAAALAADCgcIDQAAAA==.',Pr='Praehra:BAAALAAECggIEAAAAA==.Prinpringles:BAABLAAECoEcAAIZAAcIShwZGABDAgAZAAcIShwZGABDAgABLAAECggIIQADAPQhAA==.',Pt='Pthar:BAAALAAECggICwAAAA==.',Qu='Quenivere:BAAALAADCgcIBwAAAA==.',Ra='Ragnarokrïze:BAAALAADCgYIBgABLAADCgYIDQAQAAAAAA==.Ramalama:BAAALAAECgcIDgAAAA==.',Re='Rends:BAABLAAECoEgAAIHAAgI5CHiEAAHAwAHAAgI5CHiEAAHAwAAAA==.Revlen:BAABLAAECoEoAAIgAAgIzxZlHADXAQAgAAgIzxZlHADXAQAAAA==.Rexina:BAAALAADCgQIBAABLAAECgcIGwAFAIodAA==.',Rh='Rhodesia:BAAALAADCgEIAQAAAA==.',Ri='Rich:BAAALAADCgYIDAABLAAECggIJQAXAJckAA==.Riseragnarok:BAAALAADCggIFgABLAADCgYIDQAQAAAAAA==.Rizerägnarok:BAAALAADCgYIDQAAAA==.Rizëragnarok:BAAALAADCgUICQABLAADCgYIDQAQAAAAAA==.',Ro='Robbadin:BAAALAAECgIIAgAAAA==.Robinjur:BAAALAADCggIEwAAAA==.Romzi:BAAALAADCggIDwAAAA==.Roomi:BAAALAADCgUIBQAAAA==.Roulder:BAAALAAECgcIDAAAAA==.',['Rï']='Rïsëragnarok:BAAALAADCgUIBQABLAADCgYIDQAQAAAAAA==.Rïzeragnarok:BAAALAADCgcIDAABLAADCgYIDQAQAAAAAA==.',Sa='Sajoni:BAAALAADCgIIAgAAAA==.Sandarin:BAAALAAECgQICwAAAA==.Satyco:BAAALAAECgMIAwAAAA==.Sautros:BAABLAAECoEjAAIBAAgISSA4CAD4AgABAAgISSA4CAD4AgAAAA==.',Se='Seanser:BAAALAAECgcIDwAAAA==.Sebyz:BAABLAAECoEZAAIfAAgIOxCjKwClAQAfAAgIOxCjKwClAQAAAA==.Serpard:BAAALAADCggIDwAAAA==.Serpico:BAAALAAECggIDgABLAAFFAQICwANANQXAA==.Seskâ:BAAALAAECgYIEQAAAA==.',Sh='Shendaral:BAAALAAECgQICAABLAAECggICgAQAAAAAA==.Shinayne:BAAALAAECggICgAAAA==.Shinsei:BAAALAAECgYIBgABLAAECggIIQADAPQhAA==.Shylynn:BAAALAAECgcICgAAAA==.',Si='Sidera:BAAALAAECgYIEQAAAA==.',Sl='Slashfeast:BAAALAADCggIEAAAAA==.',Sm='Smìgu:BAAALAADCgcIBwAAAA==.',Sn='Sneb:BAAALAAECggIBAAAAA==.',So='Sorvahr:BAAALAAECgEIAQAAAA==.Soyeonn:BAAALAAECgUICgAAAA==.',Sp='Spiron:BAABLAAECoEdAAIGAAcI7g1WhQBsAQAGAAcI7g1WhQBsAQAAAA==.',Sq='Squirrelle:BAAALAADCgcIDgAAAA==.',St='Stich:BAAALAAECgcICQAAAA==.Stokie:BAAALAAECgYIEQAAAA==.',Su='Sunsèt:BAABLAAECoEgAAIIAAgIXyH3DADsAgAIAAgIXyH3DADsAgAAAA==.',Sw='Sweeny:BAABLAAECoEmAAISAAgIiR/CCQDaAgASAAgIiR/CCQDaAgAAAA==.Swo:BAACLAAFFIEGAAIDAAYICACLRwAUAAADAAYICACLRwAUAAAsAAQKgRoAAgMACAjPDyB5AKABAAMACAjPDyB5AKABAAAA.Swzzer:BAAALAADCggICAAAAA==.',Ta='Taqui:BAABLAAECoEZAAIUAAgINRbzOwAAAgAUAAgINRbzOwAAAgAAAA==.Tavore:BAABLAAECoEUAAINAAcIaAwxZQCJAQANAAcIaAwxZQCJAQAAAA==.',Te='Teelna:BAAALAAECgcIEwAAAA==.Tellwinna:BAAALAAECgUIBgAAAA==.Terressio:BAAALAAECgUIBQAAAA==.Tesaki:BAAALAADCgcIBwAAAA==.',Th='Tharaline:BAAALAADCgcIBwAAAA==.Thelei:BAABLAAECoEYAAIYAAcImhIRGADkAQAYAAcImhIRGADkAQAAAA==.Thetruedead:BAAALAAECgcIEQAAAA==.Thorak:BAAALAAECgMIAwABLAAECgcIEwAQAAAAAA==.Thunderpaw:BAAALAAFFAIIAgAAAA==.Thuridain:BAABLAAECoEbAAIFAAcIih0yPgBTAgAFAAcIih0yPgBTAgAAAA==.',To='Tommzan:BAABLAAECoEdAAIfAAcI7QQUUQDjAAAfAAcI7QQUUQDjAAAAAA==.Torke:BAAALAADCgcIBwAAAA==.',Tr='Tryggt:BAAALAADCggICAAAAA==.',Tw='Twigglet:BAAALAADCgcICgAAAA==.',Ut='Utzela:BAAALAADCggICgAAAA==.',Va='Vaekith:BAAALAAECgIIAgAAAA==.',Ve='Velskabt:BAAALAADCggIFwAAAA==.Vensom:BAAALAAECgMIAwAAAA==.Verdany:BAABLAAECoEXAAIDAAgIdBf0QAAyAgADAAgIdBf0QAAyAgAAAA==.',Vi='Viathon:BAABLAAECoEWAAIZAAcIGxZqIAD8AQAZAAcIGxZqIAD8AQAAAA==.Victos:BAAALAADCgcIGQAAAA==.Vidor:BAAALAADCggICAAAAA==.Vifit:BAAALAADCgYIBgAAAA==.Vizindra:BAACLAAFFIEKAAQBAAMITRxfBwCxAAABAAIIxx9fBwCxAAAEAAII7AvSOQCQAAAhAAEIWRXsBwBRAAAsAAQKgTEABAEACAgcIrUVAEoCAAQACAg5Gr8tAHUCAAEABwgMHrUVAEoCACEAAwgNGv8OAOMAAAAA.',Vo='Voidmilf:BAAALAADCggICAAAAA==.Voidrin:BAAALAADCggIDgAAAA==.',Wa='Waldo:BAAALAAECggIEwAAAA==.',Wh='Whó:BAAALAAECggICwAAAA==.',Wi='Wize:BAAALAAECgYIBgAAAA==.',Wo='Wolfstar:BAAALAAECgcIEgAAAA==.',Xa='Xanomeline:BAACLAAFFIEJAAMPAAMI6xkeAgCsAAANAAMIxAwVGwDiAAAPAAIIfhseAgCsAAAsAAQKgS0AAw8ACAhNIicCAAEDAA8ACAhNIicCAAEDAA0AAwh5Gh+ZAPgAAAAA.Xaramithrias:BAAALAADCgIIAgAAAA==.',Yu='Yunyevan:BAAALAADCggICAAAAA==.',Za='Zaramoo:BAAALAADCggIDwAAAA==.',Ze='Zebta:BAAALAADCgUIBgAAAA==.Zeldris:BAAALAAECggICAAAAA==.Zeytinbass:BAAALAAFFAIIAgAAAA==.',Zh='Zhon:BAAALAAECgYIDQAAAA==.',['Ár']='Ártemiss:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end