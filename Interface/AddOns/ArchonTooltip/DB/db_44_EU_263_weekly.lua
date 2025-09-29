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
 local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Paladin-Protection','Shaman-Enhancement','Mage-Arcane','Warrior-Fury','Druid-Restoration','Monk-Windwalker','Druid-Feral','DemonHunter-Vengeance','Mage-Frost','Priest-Discipline','Paladin-Holy','Mage-Fire','Evoker-Augmentation','Rogue-Outlaw','DeathKnight-Blood','Hunter-Survival','Monk-Mistweaver',}; local provider = {region='EU',realm='Bloodfeather',name='EU',type='weekly',zone=44,date='2025-09-22',data={Al='Aldanil:BAAALAADCggIGwABLAAECggIDAABAAAAAA==.Aldriel:BAACLAAFFIEOAAMCAAUIFBQAAgC1AQACAAUIFBQAAgC1AQADAAII4gMsEAB9AAAsAAQKgSoAAwIACAjKHRsQAJQCAAIACAiUHBsQAJQCAAMACAicEVEUANMBAAAA.Almir:BAAALAADCggICAABLAAECggIIQAEAHsXAA==.',An='Antimage:BAAALAAECgYIBgAAAA==.Antimuu:BAACLAAFFIEMAAIFAAQIjw5tDAAqAQAFAAQIjw5tDAAqAQAsAAQKgSgAAgUACAguIzUUAAIDAAUACAguIzUUAAIDAAAA.',Ap='Aphraël:BAAALAAECgcIBwAAAA==.Aprak:BAAALAAECgYIDAAAAA==.',Ar='Aradyl:BAAALAADCgMIAwAAAA==.Arathene:BAACLAAFFIETAAIGAAUI/hPgBwC2AQAGAAUI/hPgBwC2AQAsAAQKgS8AAgYACAhLI20OACgDAAYACAhLI20OACgDAAAA.Arte:BAAALAAECgUIBQAAAA==.',As='Ashgan:BAAALAADCggICAAAAA==.Astoria:BAAALAADCgYIBgABLAAFFAMICwAHAMUMAA==.',At='Ataraxy:BAAALAADCggICAABLAAFFAUIEAAIADsZAA==.',Av='Avakin:BAACLAAFFIETAAIIAAUI1BonAwC8AQAIAAUI1BonAwC8AQAsAAQKgS8AAggACAgUJMICAEEDAAgACAgUJMICAEEDAAAA.',Ax='Axis:BAAALAAFFAQICAABLAAFFAYIFAABAAAAAQ==.',Ba='Bachius:BAAALAADCgQIBAAAAA==.Bajceps:BAAALAAECgYIBgAAAA==.Balcones:BAABLAAECoEfAAQJAAgIsxd5FAA1AgAJAAgIsxd5FAA1AgAKAAgICwuAZQCFAQALAAEI5xcoNABLAAAAAA==.Ball:BAAALAADCggICAAAAA==.Balra:BAAALAADCggICAAAAA==.',Be='Beargrylls:BAAALAAECgYICQABLAAFFAUIEAAIADsZAA==.Beregor:BAAALAAECgMIAwAAAA==.Berttdk:BAAALAAECgYIEQAAAA==.Bertthunter:BAAALAAECggICQAAAA==.',Bi='Bigfistalert:BAAALAADCgcIBwAAAA==.Bigzortax:BAAALAAECgQIBgAAAA==.Bikdmg:BAAALAADCggIEwAAAA==.Bip:BAAALAADCgYIBgAAAA==.',Bl='Blackfyre:BAACLAAFFIEOAAMMAAUILxHDBQCLAQAMAAUILxHDBQCLAQANAAEI3wBHFAAwAAAsAAQKgTAAAwwACAh8Ig0IAAcDAAwACAh8Ig0IAAcDAA0ACAhCC8oXAIYBAAAA.Blade:BAAALAAECgcIEgABLAAFFAMICwAFAKwYAA==.Bloodyrain:BAAALAAECgcIDAAAAA==.Blueeyes:BAABLAAECoEcAAIOAAcIVA30QwBpAQAOAAcIVA30QwBpAQAAAA==.',Bo='Bobjohnny:BAABLAAECoEaAAIEAAgIWiFFFQAHAwAEAAgIWiFFFQAHAwAAAA==.Borjeq:BAABLAAECoEaAAIKAAcI4xjgRgDoAQAKAAcI4xjgRgDoAQAAAA==.',Br='Brakstad:BAABLAAECoEnAAMPAAgILxyqGgCiAgAPAAgILxyqGgCiAgAQAAQIPxkUkwATAQAAAA==.Brungus:BAAALAADCgYIDAAAAA==.',Bu='Bubbleguy:BAABLAAECoEhAAIEAAgIexfXRQA6AgAEAAgIexfXRQA6AgAAAA==.Bunnymann:BAABLAAECoEnAAMRAAgIKiKAIACbAgARAAgIKiKAIACbAgASAAUIixwoSgBtAQAAAA==.Buq:BAAALAAECgIIAgAAAA==.',Ca='Carla:BAAALAAECgIIAgABLAAFFAIIBQATADAgAA==.Carwick:BAABLAAECoEpAAIGAAgIpSE/HwDQAgAGAAgIpSE/HwDQAgAAAA==.',Ch='Choccie:BAABLAAECoEkAAIQAAcILhY1TQDFAQAQAAcILhY1TQDFAQAAAA==.Chriska:BAAALAADCgcICQAAAA==.Chromatica:BAAALAADCgQIAwAAAA==.',Co='Corridan:BAAALAADCggICgAAAA==.',Cr='Crazath:BAAALAAECgcIDAAAAA==.',Cs='Csempe:BAAALAADCgcIEgAAAA==.',Cu='Cupcakedemon:BAAALAAECggIDAAAAA==.',Da='Dakman:BAAALAADCggICAAAAA==.Dalatu:BAACLAAFFIEWAAITAAYIvRQcAgAOAgATAAYIvRQcAgAOAgAsAAQKgTAAAxMACAjkHXwUAKcCABMACAjkHXwUAKcCABQAAghuHPhtAKQAAAAA.Daldu:BAAALAAECgQIBAAAAA==.Darion:BAAALAAECgYIEgAAAA==.Darkjukka:BAACLAAFFIETAAIVAAUIOiAkAQDzAQAVAAUIOiAkAQDzAQAsAAQKgS8AAhUACAjiJXMBAHADABUACAjiJXMBAHADAAAA.',De='Deadstad:BAAALAAECgEIAQABLAAECggIJwAPAC8cAA==.Deepbear:BAAALAADCgYIBgABLAAFFAMICgAWAKgaAA==.Deepspark:BAACLAAFFIEKAAIWAAMIqBr2AQALAQAWAAMIqBr2AQALAQAsAAQKgS4AAhYACAhJI60BADQDABYACAhJI60BADQDAAAA.Delyraidë:BAACLAAFFIELAAIHAAMIxQx6BQD0AAAHAAMIxQx6BQD0AAAsAAQKgSgAAwcACAhsIJQFAPECAAcACAhsIJQFAPECAAYAAggsAtw7AUIAAAAA.Delystrasza:BAAALAADCggIDQABLAAFFAMICwAHAMUMAA==.Demonui:BAAALAAECgYIDgAAAA==.',Di='Digtini:BAABLAAECoEVAAIXAAgI9gynYgC1AQAXAAgI9gynYgC1AQAAAA==.Dina:BAABLAAECoEhAAIYAAgInRZ0MwAtAgAYAAgInRZ0MwAtAgAAAA==.Dip:BAAALAAECgIIAQAAAA==.',Dk='Dksiipi:BAAALAADCgQIBAAAAA==.',Do='Donkraften:BAAALAADCggICwAAAA==.Dorius:BAAALAAECgQIBQAAAA==.Dozzohunter:BAAALAADCgYIBgAAAA==.',Dr='Dracsel:BAAALAAECgcIBwAAAA==.Drainwife:BAACLAAFFIETAAMKAAYIRxufCQDIAQAKAAUI3BqfCQDIAQAJAAII7h9HCQCuAAAsAAQKgS8ABAoACAgQJSkHAE4DAAoACAh8JCkHAE4DAAsABwjDEkwJAAoCAAkAAgibJuJXANwAAAAA.Drakkaris:BAAALAADCggIGAABLAAECgcIFgATACwbAA==.Drotan:BAAALAADCggICAABLAAFFAYIFwAPAEIiAA==.Druue:BAAALAAECgUIBQAAAA==.',Du='Durzag:BAABLAAECoEhAAISAAgIMxv5GwBqAgASAAgIMxv5GwBqAgAAAA==.',Dw='Dwarvlars:BAABLAAECoEZAAITAAgI7AOIYgAqAQATAAgI7AOIYgAqAQAAAA==.',Eb='Ebrel:BAACLAAFFIEGAAIZAAIIfBZYGgCSAAAZAAIIfBZYGgCSAAAsAAQKgR8AAxkACAgrHwAWAIACABkACAgrHwAWAIACAA4ABwg3Eso6AJQBAAAA.',Ed='Edinprime:BAAALAADCggIDAAAAA==.',Eh='Ehrys:BAABLAAECoEgAAITAAgIFhuDGwB0AgATAAgIFhuDGwB0AgAAAA==.',El='Eldrid:BAAALAAECgQIBgAAAA==.Elee:BAAALAADCggICAAAAA==.Elf:BAAALAAECgYICwAAAA==.Elie:BAAALAAFFAMIBgAAAQ==.Ells:BAAALAAECgYIBgAAAA==.',Em='Emberlyn:BAAALAADCgEIAQAAAA==.Emidar:BAACLAAFFIETAAIFAAUI7h9uBQDwAQAFAAUI7h9uBQDwAQAsAAQKgTAAAgUACAjDJsEAAJQDAAUACAjDJsEAAJQDAAAA.Emofrost:BAAALAADCgQIBAAAAA==.Emoshaman:BAAALAAECgYIBwAAAA==.',Ep='Epicone:BAAALAAECgIIAgABLAAECggIJwARACoiAA==.',Er='Erak:BAAALAADCggICAAAAA==.Erooxdruid:BAACLAAFFIEWAAMOAAYIthq7BQBrAQAOAAQI1B+7BQBrAQAZAAQIUBkXBgBFAQAsAAQKgSsAAw4ACAhoJe0DAFkDAA4ACAhoJe0DAFkDABkACAieDsxXAEUBAAAA.',Et='Etra:BAAALAADCgYICAAAAA==.Etran:BAAALAAECgYIDgAAAA==.',Ev='Evejk:BAAALAAECgYIEAAAAA==.Evenia:BAACLAAFFIETAAIRAAUIxRnxBgCSAQARAAUIxRnxBgCSAQAsAAQKgS8AAhEACAgvI88OAAkDABEACAgvI88OAAkDAAAA.Evoke:BAAALAADCgYIBgAAAA==.Evokeli:BAAALAADCgYIBgAAAA==.Evopei:BAAALAADCgcIEwABLAAECgcIHwAKABUiAA==.',Ex='Executie:BAAALAADCggIFgABLAAECggIHAAEAOAgAA==.',Fe='Felglider:BAAALAAECgYICAABLAAECggIIQAEAHsXAA==.Felyssra:BAAALAAECgYIDAABLAAFFAMICQAaAKAQAA==.Fermoza:BAACLAAFFIEXAAIPAAYIQiJkAQBvAgAPAAYIQiJkAQBvAgAsAAQKgS8AAg8ACAhsJtUAAJIDAA8ACAhsJtUAAJIDAAAA.',Fl='Floris:BAAALAADCggIEAAAAA==.',Fo='Fohi:BAAALAAECgYIDwAAAA==.',Fr='Frostfyre:BAAALAAECggIDgABLAAFFAUIDgAMAC8RAA==.Frostvoid:BAACLAAFFIESAAIUAAUISh8kBADkAQAUAAUISh8kBADkAQAsAAQKgSgAAhQACAiHJAMFAE0DABQACAiHJAMFAE0DAAAA.',Fu='Fudokarion:BAAALAADCggICAAAAA==.Fudoki:BAABLAAECoEWAAIbAAcI7RUBFQDdAQAbAAcI7RUBFQDdAQAAAA==.Fudokiel:BAAALAADCgEIAQAAAA==.Fudoshin:BAAALAADCgUIBQAAAA==.Fullos:BAAALAAECgIIAgAAAA==.',Fw='Fwiti:BAAALAAFFAYIFAAAAQ==.',Gi='Gidorah:BAAALAADCgcIBQAAAA==.Girthp:BAACLAAFFIEGAAIUAAMIGgvqDgDUAAAUAAMIGgvqDgDUAAAsAAQKgSwAAhQACAgtH/8PANsCABQACAgtH/8PANsCAAAA.',Gl='Glinda:BAAALAAECgYIDAAAAA==.Glitchesx:BAAALAADCggICAABLAAECggIKAAcAG8iAA==.',Go='Gobsmaker:BAAALAADCgMIBAAAAA==.Goofydk:BAAALAADCggICAAAAA==.Goresorrow:BAAALAAECggIEQAAAA==.',Gr='Greeze:BAAALAADCgIIAgAAAA==.',Ha='Haelinn:BAAALAAECgYIEAAAAA==.Haki:BAAALAAECgMIBAAAAA==.Harboe:BAAALAADCgMIAwAAAA==.Havnzilla:BAAALAADCgYIBgAAAA==.',He='Healur:BAAALAAECgcIEwABLAAECgcIJAAQAC4WAA==.Hellzpals:BAAALAADCggICAAAAA==.Hemmelig:BAAALAADCggICAABLAAECggIIAAZAL8TAA==.Hennyman:BAAALAAECgYICQAAAA==.',Hi='Hiimlorenzo:BAAALAADCgEIAQAAAA==.',Ho='Holyskyer:BAAALAADCgcIBwAAAA==.Hopsukka:BAAALAAECgcIEwAAAA==.Hotgirth:BAAALAADCggICAABLAAFFAMIBgAUABoLAA==.',Ic='Icastspells:BAAALAADCggIHgAAAA==.',Im='Iminari:BAAALAADCggIHwAAAA==.Imperius:BAABLAAECoEdAAMEAAgILASI5ADqAAAEAAgILASI5ADqAAAVAAEIxgA8ZgAGAAAAAA==.',Iv='Ivee:BAAALAAECgEIAQAAAA==.',Ja='Jameroz:BAAALAAECgUIDgAAAA==.Jammer:BAACLAAFFIENAAMdAAUIPg3KBADSAAAXAAQIvwjDFAALAQAdAAMIIQ3KBADSAAAsAAQKgSAAAx0ACAgaI3wJAOICAB0ACAgaI3wJAOICABcAAghPGJq5AJkAAAAA.Jappew:BAACLAAFFIEPAAQKAAUIViPRCgC0AQAKAAQI0CHRCgC0AQALAAEIqRv6AwBiAAAJAAEI1CKLGQBgAAAsAAQKgSUABAoACAjfJQEFAGADAAoACAh7JQEFAGADAAsABAhyHPQUAFABAAkAAQgpJE9zAGoAAAAA.Jawsy:BAAALAAECgIIAgAAAA==.',Je='Jessâ:BAACLAAFFIEWAAIRAAYIUR5uAgALAgARAAYIUR5uAgALAgAsAAQKgTAAAhEACAjnJUMDAGgDABEACAjnJUMDAGgDAAAA.',Jk='Jkillop:BAAALAAECgUIBQAAAA==.',Jo='Joikabyte:BAEBLAAECoEpAAITAAgIVibrAAB9AwATAAgIVibrAAB9AwAAAA==.Joyful:BAAALAADCggIEAAAAA==.',Ju='Juicyscale:BAACLAAFFIEHAAMMAAMIeA1yDADYAAAMAAMIeA1yDADYAAANAAII5wUxEACFAAAsAAQKgSYAAwwACAgKIwwFADIDAAwACAgKIwwFADIDAA0AAQjWCG84ACkAAAAA.',Ka='Kakansson:BAAALAADCggICwAAAA==.Kamiipappi:BAACLAAFFIETAAITAAUIfRccBQCqAQATAAUIfRccBQCqAQAsAAQKgS8ABBMACAiVG54bAHQCABMACAiVG54bAHQCABQAAggeE6t0AH8AAB4AAQiUBBM3ACIAAAAA.Katamurr:BAAALAAECgIIAgAAAA==.Kaunisnaama:BAAALAAECgQIBAABLAAECggIBwABAAAAAA==.Kazumi:BAABLAAECoEoAAIUAAgIDQbtXQAGAQAUAAgIDQbtXQAGAQAAAA==.',Ke='Kelbner:BAAALAADCgYIBwAAAA==.Kenonk:BAACLAAFFIENAAIIAAUIzBLQAwCUAQAIAAUIzBLQAwCUAQAsAAQKgSQAAggACAh/HlUKAI0CAAgACAh/HlUKAI0CAAAA.',Kh='Khtafury:BAAALAADCgcIDAAAAA==.',Ki='Kickatoir:BAACLAAFFIEJAAMaAAMIoBDTBgDkAAAaAAMIoBDTBgDkAAAIAAMIUQn7CQCvAAAsAAQKgRoAAhoACAiAGosVADUCABoACAiAGosVADUCAAAA.',Kj='Kjelliss:BAAALAAECgUICQAAAA==.',Ko='Kosser:BAABLAAECoEoAAMcAAgIbyL9BwC2AgAcAAcIKCP9BwC2AgAFAAgISB7WJQCfAgAAAA==.Kosserw:BAAALAAECgYIBgABLAAECggIKAAcAG8iAA==.Kosserz:BAAALAADCgcIDQABLAAECggIKAAcAG8iAA==.Kozzer:BAAALAADCggIEAABLAAECggIKAAcAG8iAA==.',Kr='Kratosex:BAABLAAECoEjAAQVAAgI0xvIDwBUAgAVAAgInhvIDwBUAgAfAAQIrRObRgD1AAAEAAIIRBYUBwGRAAAAAA==.Krisser:BAAALAADCgUIBQAAAA==.Krys:BAAALAADCgIIAgABLAAECgUICQABAAAAAA==.',Ku='Kugisaki:BAAALAADCgcIBwAAAA==.',Ky='Kyntsi:BAAALAADCgIIAgAAAA==.',La='Lafranarti:BAAALAADCgcICwAAAA==.Lasikchic:BAAALAADCgIIAgAAAA==.',Le='Leigeuke:BAAALAAECgUIBQABLAAFFAUIDgAMAC8RAA==.Lemon:BAAALAAECgMIAwAAAA==.Leonesh:BAAALAADCggICAAAAA==.',Li='Lilbird:BAAALAAECgYIBQAAAA==.Lilcuv:BAAALAADCgYIBgAAAA==.Liljah:BAACLAAFFIEGAAIRAAIItxt6HgCgAAARAAIItxt6HgCgAAAsAAQKgRoAAxEACAizI2wcALMCABEACAizI2wcALMCABIAAQjdF3OmADoAAAEsAAUUBQgTAAUA7h8A.Lillith:BAAALAAECgYIBgAAAA==.Linnormen:BAAALAADCggIDwABLAAECggIJwARACoiAA==.Lionell:BAAALAADCgcICgAAAA==.Littledickus:BAAALAADCgYIBgABLAAECggIIQAEAHsXAA==.Littletitan:BAAALAAECgMIAwAAAA==.',Lo='Lockstad:BAAALAADCggICAABLAAECggIJwAPAC8cAA==.Logrek:BAAALAADCggICAABLAAFFAYIFwAUAP0jAA==.',Lu='Lucyón:BAAALAADCgcIDgABLAAECgUIBAABAAAAAA==.Lume:BAAALAADCggIHAAAAA==.Lumoava:BAACLAAFFIERAAIdAAUIERj5AAC3AQAdAAUIERj5AAC3AQAsAAQKgSsAAh0ACAhVJZEBAHMDAB0ACAhVJZEBAHMDAAAA.Lun:BAABLAAECoEkAAIIAAgI/yKAAwAwAwAIAAgI/yKAAwAwAwAAAA==.Lunaci:BAAALAAECggIDgAAAA==.Lunalei:BAAALAADCggIEQAAAA==.Lunapollo:BAAALAAECgYICQAAAA==.Luv:BAAALAAECgMIBQAAAA==.',Ly='Lyatha:BAAALAAFFAIIAgABLAAFFAYIEAAfAC8dAA==.Lynise:BAAALAADCgYIBgAAAA==.Lyrie:BAABLAAECoEUAAIXAAYIhBHTeQB1AQAXAAYIhBHTeQB1AQABLAAFFAYIGgAfABghAA==.Lysia:BAAALAAECgEIAQAAAA==.Lythi:BAACLAAFFIEQAAIfAAYILx0oAQA/AgAfAAYILx0oAQA/AgAsAAQKgRwAAh8ACAheIkAEAAwDAB8ACAheIkAEAAwDAAAA.',Ma='Macgreger:BAAALAADCggIFwAAAA==.Madrena:BAAALAAECgcIBwAAAA==.Magen:BAAALAADCggICAABLAAECggIIwACAAkXAA==.Maguz:BAABLAAECoEWAAMXAAgI8Q6tUwDiAQAXAAgI8Q6tUwDiAQAgAAEIsBJ7GQBFAAAAAA==.Marlon:BAAALAAECgYIEAAAAA==.Mato:BAACLAAFFIEHAAIdAAUIfxCDAQBlAQAdAAUIfxCDAQBlAQAsAAQKgSwAAh0ACAgDJkwBAHoDAB0ACAgDJkwBAHoDAAAA.',Me='Medesimus:BAAALAADCggICgAAAA==.Mehukatti:BAAALAAECgYIBgAAAA==.Meneldur:BAAALAAECgYIEQABLAAFFAYIEQAYALEaAA==.',Mi='Micolash:BAABLAAECoEcAAIEAAgI4CBLGQDxAgAEAAgI4CBLGQDxAgAAAA==.Missie:BAACLAAFFIETAAIFAAYIzRHQBAAAAgAFAAYIzRHQBAAAAgAsAAQKgSkAAgUACAh3JawIAEoDAAUACAh3JawIAEoDAAAA.',Mo='Monarch:BAABLAAECoEhAAIdAAgIAhklEwBgAgAdAAgIAhklEwBgAgAAAA==.Moonfighter:BAABLAAECoEeAAIFAAcI4RwLPQA8AgAFAAcI4RwLPQA8AgAAAA==.Mosmendrain:BAAALAAECgMICQAAAA==.',Mu='Musashi:BAAALAADCggIFQAAAA==.',['Mò']='Mòrgoth:BAABLAAECoEZAAIHAAgIsxZDEQAtAgAHAAgIsxZDEQAtAgAAAA==.',Na='Nali:BAACLAAFFIEaAAIfAAYIGCHUAABcAgAfAAYIGCHUAABcAgAsAAQKgTAAAh8ACAgOJmMAAHQDAB8ACAgOJmMAAHQDAAAA.Nasiahaze:BAAALAADCgcICQAAAA==.',Ne='Negeroth:BAAALAADCggIEAAAAA==.Nellithedog:BAAALAAECgIIAgAAAA==.Nemaro:BAAALAAECgIIAgAAAA==.Netflix:BAAALAADCggICAAAAA==.Newt:BAAALAADCggICAABLAAECgcIJAAQAC4WAA==.Nezzom:BAAALAAECgEIAQAAAA==.',Ni='Nipe:BAAALAADCgcICQAAAA==.Niriya:BAAALAADCggIFAABLAAFFAYIGgAfABghAA==.',No='Norag:BAAALAADCggIDgAAAA==.',Nu='Nugsnugs:BAACLAAFFIEQAAIIAAUIOxnXBABQAQAIAAUIOxnXBABQAQAsAAQKgRoAAwgACAgrG4QUAOQBAAgACAgrG4QUAOQBABoABQiGDoY7APwAAAAA.',Ny='Nymphor:BAAALAAECgIIAgAAAA==.',Ob='Obey:BAAALAAECgMIAwAAAA==.',Ok='Okafor:BAAALAADCgcIBwAAAA==.',On='Onoxous:BAAALAAECgUICQAAAA==.',Op='Oppsi:BAAALAAECgMIBAAAAA==.',Pa='Paladinen:BAAALAAECgMIAwABLAAECggIIwACAAkXAA==.Paleli:BAAALAADCgYIBgABLAAFFAMIBgABAAAAAQ==.Pallacossi:BAAALAAECgYIDAAAAA==.Pawpatine:BAAALAADCggICwAAAA==.',Po='Polishmafia:BAACLAAFFIEMAAIGAAQIgx49CgB9AQAGAAQIgx49CgB9AQAsAAQKgSMAAgYACAiLIrAUAAUDAAYACAiLIrAUAAUDAAAA.Popsicle:BAAALAAECgQIBQAAAA==.',Pu='Punasiipi:BAAALAAECgIIAgAAAA==.',Qa='Qashalari:BAAALAADCgUIBQAAAA==.Qashanova:BAAALAAECgMIBQAAAA==.Qast:BAAALAADCgIIAgAAAA==.',Ra='Raghok:BAABLAAECoEVAAIGAAgIQyTsEQAVAwAGAAgIQyTsEQAVAwAAAA==.Rajraj:BAAALAAECgYIDAAAAA==.Rantakäärme:BAACLAAFFIEQAAQMAAUIwBTfBQCGAQAMAAUIvxDfBQCGAQAhAAQImxNRAgBIAQANAAEIKhZ0EgBQAAAsAAQKgS8ABCEACAjKIUgBABADACEACAjDIUgBABADAAwACAhgGxsUAG4CAA0ABwiQFWUUALQBAAAA.Raraldin:BAAALAADCgcIHwAAAA==.Razzo:BAAALAAECgEIAQAAAA==.',Re='Resozen:BAABLAAECoEeAAIaAAgImCU6AwBOAwAaAAgImCU6AwBOAwAAAA==.',Rh='Rhosyn:BAAALAAECggIEAABLAAECggIIAATABYbAA==.',Ro='Rocks:BAAALAAECgUIDAAAAA==.Roguen:BAABLAAECoEjAAMCAAgICRftFwBDAgACAAgICRftFwBDAgAiAAQIHwqzEgDPAAAAAA==.Roguer:BAAALAAECgIIAgABLAAECggIIwAVANMbAA==.Romppadru:BAAALAAFFAIIAgABLAAFFAUIEwACAEUjAA==.Roxybabe:BAAALAAECgcIDQAAAA==.',Ru='Rubbz:BAAALAAECgYIEQAAAA==.Runkemonk:BAABLAAECoEXAAMaAAgIehjMFwAaAgAaAAgIehjMFwAaAgAIAAcIdQptJQAkAQAAAA==.',Sa='Salaatti:BAACLAAFFIETAAIYAAUIIBQEBwC8AQAYAAUIIBQEBwC8AQAsAAQKgSkAAhgACAjnI6oNABwDABgACAjnI6oNABwDAAAA.Sazakan:BAAALAADCggIDwAAAA==.',Sc='Scuffed:BAAALAAECgEIAQAAAA==.',Se='Sebahunt:BAACLAAFFIEGAAISAAIIVR73EgCqAAASAAIIVR73EgCqAAAsAAQKgScAAhIACAgpHyIPANoCABIACAgpHyIPANoCAAEsAAUUBAgMAAYAgx4A.Sebby:BAACLAAFFIEPAAIMAAUIPhsZBADDAQAMAAUIPhsZBADDAQAsAAQKgSMAAgwACAjVIkkHABEDAAwACAjVIkkHABEDAAAA.Señormoist:BAAALAAECgMIBgABLAAECggIJwARACoiAA==.',Sh='Shaboo:BAAALAADCggICAAAAA==.Sharmud:BAAALAADCggIDgAAAA==.Shasur:BAABLAAECoEZAAIGAAYIlBYPlwCQAQAGAAYIlBYPlwCQAQAAAA==.Shasuri:BAAALAAECgYICgAAAA==.Shawski:BAABLAAECoEfAAIjAAgIXRtvDABVAgAjAAgIXRtvDABVAgAAAA==.Shibaevo:BAAALAADCggICAAAAA==.Shibaw:BAAALAAECgIIAgAAAA==.Shindy:BAAALAAECgcIDAAAAA==.Showstopper:BAAALAADCggICAAAAA==.Shumumu:BAACLAAFFIEIAAIWAAIIFRgvBACmAAAWAAIIFRgvBACmAAAsAAQKgSIAAhYACAh3Iq4CAAoDABYACAh3Iq4CAAoDAAAA.',Si='Sian:BAAALAAECgEIAgAAAA==.Silence:BAACLAAFFIEFAAITAAIIMCCzFQC6AAATAAIIMCCzFQC6AAAsAAQKgSAAAhMACAgrIC8OAN4CABMACAgrIC8OAN4CAAAA.',Sk='Skeleton:BAABLAAECoEUAAIJAAYIyQiXQQBBAQAJAAYIyQiXQQBBAQAAAA==.Sketchythott:BAAALAAECgcIBwAAAA==.Skipperz:BAABLAAECoEaAAIEAAgIDR6kJQCyAgAEAAgIDR6kJQCyAgAAAA==.Skipperza:BAAALAADCggICAAAAA==.Skogspingvin:BAABLAAECoEbAAIOAAgItxm8HQBAAgAOAAgItxm8HQBAAgAAAA==.Skrumps:BAAALAADCggIDgAAAA==.',Sl='Slashbuster:BAAALAAECgYIBwAAAA==.Slimshammy:BAAALAAECgcIBwAAAA==.Slipnir:BAAALAADCggICAAAAA==.Slöpåslå:BAAALAAECggICgAAAA==.',Sm='Smasher:BAAALAAECgQIBAAAAA==.Smekereven:BAAALAAECggICAAAAA==.Smiskk:BAABLAAECoEcAAIPAAgIwQ7COwDkAQAPAAgIwQ7COwDkAQAAAA==.Smuc:BAAALAAECgEIAQAAAA==.',Sn='Snipedamage:BAACLAAFFIEPAAIXAAQIZyFqDQCGAQAXAAQIZyFqDQCGAQAsAAQKgTEAAxcACAgQJHINACADABcACAjuI3INACADACAABAh0IPkJAG8BAAAA.Snipedamagee:BAAALAADCggICQABLAAFFAQIDwAXAGchAA==.Snipeknight:BAAALAAECgYIDAABLAAFFAQIDwAXAGchAA==.Snipeshaman:BAABLAAECoEUAAMQAAYIzBpvVACxAQAQAAYIzBpvVACxAQAPAAYIuRVFSwCkAQABLAAFFAQIDwAXAGchAA==.',So='Soare:BAAALAADCggIGQAAAA==.Sontaseppo:BAAALAAECgYIEwAAAA==.',Sp='Spazzio:BAAALAAECgQIBAAAAA==.Spoonfork:BAAALAAECgIIAgABLAAFFAUIDQAIAMwSAA==.Sprite:BAAALAAECgYIDwAAAA==.Spyroq:BAAALAADCgcICgAAAA==.',St='Stinkynator:BAACLAAFFIEJAAIFAAMIDhfZDwADAQAFAAMIDhfZDwADAQAsAAQKgScAAgUACAh8JQwEAG0DAAUACAh8JQwEAG0DAAAA.Stinkypete:BAAALAAECgYIBgABLAAFFAMICQAFAA4XAA==.Stormalia:BAABLAAECoEcAAIQAAcIrwp0lQAOAQAQAAcIrwp0lQAOAQAAAA==.',Su='Subordigent:BAAALAAFFAEIAQABLAAFFAYIFwAUAP0jAA==.Suomulainen:BAACLAAFFIEOAAIMAAUI6BVOBQCZAQAMAAUI6BVOBQCZAQAsAAQKgS8AAgwACAh3IdEIAPsCAAwACAh3IdEIAPsCAAAA.',Sy='Synchro:BAAALAADCggICQAAAA==.',Ta='Tamriel:BAAALAADCggICAABLAAECggIIAATABYbAA==.Taylorswìft:BAAALAADCgQIBAAAAA==.',Te='Temmu:BAAALAADCgcIGgAAAA==.Tempest:BAAALAAECgEIAQAAAA==.',Th='Thanil:BAAALAADCggIGgAAAA==.Thanthalas:BAABLAAECoEvAAIRAAgIdR7JLABfAgARAAgIdR7JLABfAgAAAA==.Thebusdriver:BAAALAAECgEIAQAAAA==.Thrunde:BAAALAADCggIDwAAAA==.',Ti='Tinkarti:BAACLAAFFIETAAIdAAUIeiNYAAAUAgAdAAUIeiNYAAAUAgAsAAQKgS8AAh0ACAhvJrQAAIoDAB0ACAhvJrQAAIoDAAAA.Tipslock:BAABLAAECoEiAAQKAAgI7CA8GADVAgAKAAgIJR88GADVAgAJAAMIzh1SVwDfAAALAAEI1yMZLgBnAAAAAA==.Tipsmage:BAAALAADCggIEAAAAA==.Titaa:BAAALAADCggIFwAAAA==.',To='Tone:BAAALAAECgcICAABLAAECggIBwABAAAAAA==.Tordentor:BAEALAAECggIBwAAAA==.',Tr='Trapkers:BAACLAAFFIEOAAMkAAUITxl0AAB3AQAkAAQIBRh0AAB3AQARAAMI7hW8DwDxAAAsAAQKgS8AAyQACAh8JR0BAD4DACQACAgFJB0BAD4DABEABQjeIilIAPsBAAAA.Trusetyven:BAAALAAECgcIDAABLAAECggIFgAXAPEOAA==.',Tu='Tukiainen:BAAALAAECgUIBQABLAAFFAUIEAAMAMAUAA==.Turker:BAAALAADCggIDwABLAAECgYIEQABAAAAAA==.',Ty='Tyrdan:BAACLAAFFIESAAIfAAUIoRvfAgDeAQAfAAUIoRvfAgDeAQAsAAQKgSgAAh8ACAjiIV4GAOcCAB8ACAjiIV4GAOcCAAAA.',['Tí']='Títanium:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',['Tö']='Tötterö:BAAALAAECgQIAgAAAA==.',Ui='Uisce:BAAALAAECgYIEQAAAA==.',Uk='Uklu:BAAALAADCgcIDgAAAA==.',Ul='Ulio:BAABLAAECoEgAAMZAAgIvxO+NADSAQAZAAgIvxO+NADSAQAOAAgI8g8ZMADKAQAAAA==.',Um='Umisia:BAAALAAECgYIBgAAAA==.',Ut='Utnola:BAABLAAECoEaAAIYAAgIKSDIFwDTAgAYAAgIKSDIFwDTAgAAAA==.',Va='Valaiseva:BAAALAADCgYIBgAAAA==.Valantyr:BAAALAAECgEIAQAAAA==.',Ve='Veggis:BAAALAADCggIHwAAAA==.Veilside:BAAALAAECgIIAgAAAA==.Ver:BAAALAAECggICAAAAA==.Vespera:BAABLAAECoEkAAIlAAgIBhsgDgBYAgAlAAgIBhsgDgBYAgAAAA==.',Vo='Voidlisa:BAABLAAECoEbAAIJAAgIzRhPDgByAgAJAAgIzRhPDgByAgAAAA==.Volcan:BAAALAAECgMIBwAAAA==.',Vy='Vynthas:BAAALAADCgMIAwAAAA==.Vynzi:BAAALAADCggICAAAAA==.',Wt='Wtdouservher:BAAALAAECgUIDQAAAA==.',Xa='Xad:BAAALAADCgcIBwAAAA==.Xanyy:BAAALAADCggICQAAAA==.',Xi='Xien:BAAALAAECgQIBAAAAA==.Xienswar:BAAALAAECgcIBwAAAA==.',Xy='Xye:BAAALAAECgMIBQAAAA==.',Ya='Yadena:BAAALAADCgMIAwAAAA==.Yaederiel:BAAALAADCggIDQAAAA==.Yahenni:BAACLAAFFIEXAAIUAAYI/SPDAACXAgAUAAYI/SPDAACXAgAsAAQKgTIAAhQACAi4JoEAAJQDABQACAi4JoEAAJQDAAAA.',Yo='Yopp:BAAALAAECgYIDAAAAA==.',Zh='Zhad:BAAALAADCgEIAQAAAA==.',Zo='Zoeý:BAAALAAECgMIBAAAAA==.',Zu='Zugmar:BAAALAAECgQIBAAAAA==.',Zy='Zyarel:BAAALAADCggIHwABLAAECggIDAABAAAAAA==.',['Öo']='Öo:BAAALAAECggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end