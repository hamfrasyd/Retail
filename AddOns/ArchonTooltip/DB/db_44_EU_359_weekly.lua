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
 local lookup = {'Shaman-Restoration','Shaman-Enhancement','DeathKnight-Frost','Priest-Shadow','Paladin-Retribution','Paladin-Protection','Hunter-Marksmanship','DemonHunter-Havoc','DemonHunter-Vengeance','Druid-Feral','Druid-Restoration','Shaman-Elemental','Priest-Holy','Monk-Mistweaver','Warlock-Destruction','Hunter-BeastMastery','Priest-Discipline','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Druid-Balance','Warrior-Protection','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Warlock-Affliction','DeathKnight-Blood','Druid-Guardian','Warlock-Demonology','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','Mage-Frost','Paladin-Holy','DeathKnight-Unholy',}; local provider = {region='EU',realm='Chantséternels',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abdelkrimm:BAAALAAECgMIAwABLAAFFAMICgABAMkQAA==.',Ac='Ackiliane:BAAALAAECgcIEwAAAA==.Acryllia:BAABLAAECoEYAAMCAAcIjBUwDgDcAQACAAcIjBUwDgDcAQABAAEIxQ4oDQEpAAAAAA==.Acteøn:BAAALAAECgIIAgAAAA==.',Ad='Adélaïde:BAAALAADCggIDwAAAA==.',Ag='Ageware:BAAALAADCggIDAAAAA==.Aghorah:BAABLAAECoEeAAIDAAcIigydoQCBAQADAAcIigydoQCBAQAAAA==.Agode:BAABLAAECoEfAAIEAAcIvB4DHgBhAgAEAAcIvB4DHgBhAgAAAA==.',Ak='Akanë:BAABLAAECoEWAAMFAAYIthjIhQCrAQAFAAYIthjIhQCrAQAGAAMI3A8VSQCcAAAAAA==.Akeros:BAAALAAECgYICAABLAAECgcIGQAHAPwTAA==.Akumeå:BAABLAAECoEhAAMIAAcIAhjLUAABAgAIAAcIAhjLUAABAgAJAAEIdgb/WAAoAAAAAA==.',Al='Albibiphoque:BAABLAAECoEeAAMKAAgIuCVLAQBkAwAKAAgIuCVLAQBkAwALAAEIWhb/rwBDAAAAAA==.Albismousse:BAAALAAECgMIAwAAAA==.Alcham:BAACLAAFFIEIAAIMAAQIIw2BCwAxAQAMAAQIIw2BCwAxAQAsAAQKgSsAAgwACAi+IFYPAAADAAwACAi+IFYPAAADAAAA.Aldaarya:BAAALAADCggIDQAAAA==.Aldrys:BAABLAAECoElAAMEAAgIpR9xGgB/AgAEAAcIDR9xGgB/AgANAAgIsg9ZQQCqAQAAAA==.Aleadractas:BAAALAAECgYIDQAAAA==.Alexiel:BAAALAADCggICwAAAA==.Aloouf:BAABLAAECoEYAAIOAAgIcg3bIABrAQAOAAgIcg3bIABrAQAAAA==.Alvíss:BAAALAAECgYICwAAAA==.Alïcïà:BAAALAADCggICAABLAAECggIIAAPAMgZAA==.Aløndarn:BAAALAADCgcIBwAAAA==.',Am='Amaymmon:BAAALAADCggIGwAAAA==.Amourencage:BAAALAADCggICQAAAA==.Amoxicilline:BAAALAADCgYIBgABLAAECgcIGQAGAMscAA==.Aménor:BAAALAAECgYIDwAAAA==.',An='Anastasyia:BAAALAADCgQIBAAAAA==.Andurial:BAAALAADCgYIBgABLAAECggIFwAHAPIhAA==.Andúril:BAAALAAECgcICAABLAAECggIFwAHAPIhAA==.Andúrìl:BAABLAAECoEXAAMHAAgI8iEAFQCnAgAHAAcINyEAFQCnAgAQAAYIMCCjRwABAgAAAA==.Anoquim:BAAALAADCgYICgABLAAECggIKgARAHIUAA==.Anourette:BAAALAAECgQIBAAAAA==.Anänké:BAAALAADCgcIBwAAAA==.',Ar='Arcaniox:BAAALAADCgcIBwAAAA==.Arcanis:BAAALAADCggICAAAAA==.Archévo:BAABLAAECoEdAAISAAgIZg0KKAC3AQASAAgIZg0KKAC3AQAAAA==.Ardeath:BAAALAAECgQIBAABLAAECggIHQASAGYNAA==.Ariakk:BAAALAAECgcIAQAAAA==.Arimane:BAAALAAECgYIDwAAAA==.Arka:BAAALAADCggIDAAAAA==.Arkhalys:BAABLAAECoEmAAIMAAgISxcXKABMAgAMAAgISxcXKABMAgAAAA==.Arklay:BAABLAAECoEaAAIDAAcI5w6hlgCUAQADAAcI5w6hlgCUAQAAAA==.Arley:BAAALAADCgYIBgAAAA==.Arms:BAAALAAECggICgAAAA==.Arokar:BAAALAAECgYIBgAAAA==.Arrosh:BAAALAADCggIEAAAAA==.Arròw:BAAALAAECgMIAwAAAA==.',As='Asrieladrien:BAAALAADCggICAAAAA==.Astraaroth:BAAALAADCgYIBgAAAA==.Astridormi:BAABLAAECoEgAAQSAAgIThYDHwACAgASAAgIThYDHwACAgATAAMIiBRLKgC7AAAUAAEI1gwXFgA1AAAAAA==.',At='Athoras:BAAALAADCggIEAAAAA==.',Au='Auguras:BAAALAADCgYIBgABLAAECggIIwAMAN8RAA==.',Ax='Axedark:BAAALAADCggIEAAAAA==.Axelight:BAAALAAECgcIBwAAAA==.Axtrix:BAAALAAECgQIAQABLAAFFAQIBgAGAGkRAA==.',Az='Azaell:BAAALAADCgIIAgAAAA==.Azdrielle:BAAALAAECgYICQAAAA==.Azé:BAAALAADCggIFAABLAADCggIFwAVAAAAAA==.Azémage:BAAALAADCggIFwAAAA==.',['Aÿ']='Aÿala:BAAALAADCggIGAAAAA==.',Ba='Badrass:BAAALAAECggICQAAAA==.Badwulf:BAAALAAECgYIBgAAAA==.Barbapioche:BAAALAADCggICAAAAA==.Bavette:BAAALAADCgEIAQAAAA==.',Be='Belpère:BAAALAADCgQIBAAAAA==.Belvache:BAAALAADCgcIFQAAAA==.Belïal:BAAALAADCggIBQAAAA==.Betys:BAABLAAECoEUAAIWAAYIvAkQVwAaAQAWAAYIvAkQVwAaAQAAAA==.',Bh='Bhrom:BAABLAAECoEgAAIXAAgICiW1AgBaAwAXAAgICiW1AgBaAwAAAA==.',Bi='Bimbotoy:BAAALAADCgIIAgAAAA==.Biskhot:BAAALAAECgYIEwAAAA==.Biø:BAAALAAECgIIAgAAAA==.',Bl='Blackdark:BAAALAAECgYIEwAAAA==.Bladion:BAAALAADCgMIAwAAAA==.Blaive:BAAALAAECgYIBwAAAA==.',Bo='Bogard:BAABLAAECoEcAAIFAAgIcg8bdwDHAQAFAAgIcg8bdwDHAQAAAA==.Boguépine:BAAALAADCgcIBwABLAAECgcIIAAFABccAA==.Boriss:BAAALAAECgYIBgABLAAECgYIBgAVAAAAAA==.Boréalia:BAAALAADCgcIDgAAAA==.',Br='Bressigris:BAAALAADCggIHQAAAA==.Brizä:BAABLAAECoEZAAIYAAgIwxe8FwBGAgAYAAgIwxe8FwBGAgAAAA==.Brumus:BAAALAAECggICAAAAA==.Brunicendre:BAAALAADCgcIBwAAAA==.Brynn:BAAALAAECgYIDQAAAA==.',Bu='Bunchi:BAABLAAECoEcAAMBAAcIJB6oKgBAAgABAAcIJB6oKgBAAgAMAAcI0gvwUwCJAQAAAA==.Butkus:BAAALAAECgMIBAAAAA==.',['Bã']='Bãbz:BAABLAAECoEWAAQZAAYIDBhzVgCuAQAZAAYIKBdzVgCuAQAXAAMIhAttYgCGAAAaAAEInxsOLwBJAAAAAA==.',Ca='Carlo:BAABLAAECoEbAAIbAAgIjyAlAgACAwAbAAgIjyAlAgACAwAAAA==.Cathycathy:BAAALAADCggICAAAAA==.Cathéria:BAAALAADCgMIAwAAAA==.',Ce='Cent:BAAALAADCgEIAQABLAAECgYIDgAVAAAAAA==.',Ch='Chamelya:BAABLAAECoEcAAIBAAgI2BNzSwDOAQABAAgI2BNzSwDOAQAAAA==.Chamoinemomo:BAAALAAECgEIAgAAAA==.Chassinetta:BAAALAAFFAIIAgAAAA==.Chassoukati:BAAALAAECgcIDgAAAA==.Cheekibreeki:BAAALAADCgYIBgABLAAECgcIIQAcAKUTAA==.Childerick:BAAALAADCgUIBQAAAA==.Chitzen:BAABLAAECoEYAAMdAAgIeB75BgBbAgAdAAgIrRv5BgBbAgAWAAcI0Ro+KQD0AQABLAAFFAIIAgAVAAAAAA==.',Ci='Cityhunter:BAAALAADCggIEQAAAA==.',Cl='Cleyent:BAAALAADCgcIBwAAAA==.Clémentines:BAAALAAECgMIAwAAAA==.',Co='Cordon:BAAALAAECgQIBAAAAA==.Cover:BAAALAAECgEIAQAAAA==.',Cy='Cyndraz:BAAALAADCggICgABLAAECggIJQANAAISAA==.',Da='Daktary:BAABLAAECoEfAAMQAAgItR7sHwCiAgAQAAgIxRzsHwCiAgAHAAcIyxivLAD8AQAAAA==.Damodare:BAAALAADCgQIBwABLAAECgYIBgAVAAAAAA==.Darkøsta:BAAALAADCggICAAAAA==.Dathomir:BAAALAADCggICAAAAA==.',De='Decarth:BAABLAAECoEUAAIDAAYIaR+QYgD7AQADAAYIaR+QYgD7AQABLAAFFAUIDwAYAI8gAA==.Deeper:BAAALAAECgYICAABLAAECgcIHgAIAGgjAA==.Deepér:BAABLAAECoEeAAIIAAcIaCPFHADSAgAIAAcIaCPFHADSAgAAAA==.Demaxis:BAABLAAECoEcAAIeAAcI4B66DACGAgAeAAcI4B66DACGAgAAAA==.Dered:BAABLAAECoEhAAMWAAgI8h/WEgCrAgAWAAgI8h/WEgCrAgAKAAUI+xwxHgB5AQAAAA==.Deured:BAAALAAECgQIBAAAAA==.Devlyne:BAABLAAECoEbAAMNAAcIDh47IABXAgANAAcIDh47IABXAgARAAMIpBWbHgC2AAAAAA==.',Dh='Dhealx:BAAALAAECgUICQABLAAECggIBwAVAAAAAA==.',Di='Dialfus:BAABLAAECoEkAAMGAAgIRxmdGAD5AQAGAAgIRxmdGAD5AQAFAAIIygaXIwFcAAAAAA==.Dialfuss:BAAALAAECgIIAgAAAA==.Dimanche:BAAALAAECgEIAQAAAA==.Divinia:BAAALAADCggICAAAAA==.',Do='Dovahlastraz:BAAALAAECgYIBgAAAA==.',Dr='Drackaelia:BAAALAADCggIHAAAAA==.Dranose:BAAALAAECgMIAwAAAA==.Drenna:BAAALAAECggICAAAAA==.Droft:BAAALAAECgYIDAAAAA==.',Du='Dustinbolt:BAAALAADCgIIAgABLAADCggIEAAVAAAAAA==.Dustindeath:BAAALAADCgYIBgABLAADCggIEAAVAAAAAA==.Dustinheaven:BAAALAADCgYIBAABLAADCggIEAAVAAAAAA==.Dustinshadow:BAAALAADCggIEAAAAA==.Dustinthdark:BAAALAADCgYIBgABLAADCggIEAAVAAAAAA==.Dustinthwind:BAAALAADCgMIAwABLAADCggIEAAVAAAAAA==.Dustinwood:BAAALAADCgcIBwABLAADCggIEAAVAAAAAA==.',Dy='Dyman:BAAALAADCgIIAgAAAA==.',['Dé']='Démaunio:BAAALAADCggIGAAAAA==.',['Dë']='Dëlios:BAABLAAECoEeAAIIAAcI/RxVOABQAgAIAAcI/RxVOABQAgAAAA==.',['Dü']='Dürrin:BAABLAAECoEWAAIFAAcI7AyXpgBvAQAFAAcI7AyXpgBvAQAAAA==.',Ed='Edalix:BAAALAADCgMIAwABLAAECgcIEAAVAAAAAA==.Edalya:BAAALAAECgcIEAAAAA==.Edracyr:BAAALAADCggICAAAAA==.Edrinldy:BAAALAAECgQIBAAAAA==.Eduarem:BAACLAAFFIEIAAIZAAMIMRblDwD9AAAZAAMIMRblDwD9AAAsAAQKgSgAAhkACAg/Ij8RAAQDABkACAg/Ij8RAAQDAAAA.',Ef='Efra:BAAALAAECgYIBgAAAA==.',Ek='Ekyroxx:BAAALAADCgQIBAAAAA==.',El='Elamin:BAAALAAECgYIEQAAAA==.Eldoros:BAAALAADCgcIDAAAAA==.Elgonya:BAAALAADCggICwAAAA==.Elkarh:BAAALAAECgYIDAAAAA==.Elrim:BAAALAADCgMIAwAAAA==.Elucidator:BAAALAAECgYIEwAAAA==.Elwÿn:BAAALAADCggIIgAAAA==.Elysea:BAAALAADCgcIDgAAAA==.Elîzabeth:BAAALAADCgcIBwAAAA==.',Em='Emmielleuse:BAAALAADCgcIBwAAAA==.',En='Enalora:BAABLAAECoEhAAIFAAgImRr4NwBoAgAFAAgImRr4NwBoAgABLAAFFAQICAAGABMJAA==.Enderz:BAAALAAECgUIBQAAAA==.Enmi:BAAALAADCggIEAAAAA==.',Eo='Eowïnà:BAABLAAECoEWAAIQAAgIoA0bbACiAQAQAAgIoA0bbACiAQAAAA==.',Ep='Ephraïm:BAABLAAECoEXAAIGAAcIJiEVCwCZAgAGAAcIJiEVCwCZAgABLAAECggIFAAfADggAA==.',Er='Erahdak:BAAALAAECgEIAgAAAA==.Erethia:BAAALAADCgUIBQAAAA==.Erityas:BAAALAADCgcICAAAAA==.Erudimend:BAABLAAECoEaAAINAAcI4RUzOgDLAQANAAcI4RUzOgDLAQAAAA==.Erwÿn:BAAALAAECgIIAgAAAA==.',Es='Eshizy:BAAALAAECgMIAwAAAA==.Esmeralda:BAAALAADCgUIBQAAAA==.',Et='Etis:BAAALAADCgcIFQAAAA==.',Eu='Eucalypthus:BAAALAAECgcIBwABLAAECgcIGQAGAMscAA==.',Ew='Ewalock:BAACLAAFFIEJAAMeAAMISRcuBwC6AAAeAAIIRR8uBwC6AAAPAAII2ArbLQCTAAAsAAQKgSIABA8ACAi9IncbAMICAA8ABwjPIncbAMICAB4ABQjMHT8rAKQBABsAAQi+DHE3AEMAAAAA.',['Eö']='Eöl:BAAALAADCgQIBgABLAADCgcIDAAVAAAAAA==.',Fa='Falsh:BAAALAADCggIDgAAAA==.Fantasïa:BAABLAAECoEgAAITAAcI8xZ8EQDjAQATAAcI8xZ8EQDjAQAAAA==.',Fe='Feidreva:BAAALAADCggICAAAAA==.Felheart:BAAALAAECgYIEAAAAA==.Fen:BAABLAAECoEcAAIgAAcIsRnlGQAHAgAgAAcIsRnlGQAHAgAAAA==.',Fi='Fiercejaguar:BAAALAADCggIDwAAAA==.Filisia:BAAALAAECgIIAgAAAA==.Finrael:BAAALAADCgYIBwAAAA==.',Fl='Flapok:BAAALAAECggIDgAAAA==.Fledman:BAAALAADCgYIBwAAAA==.Flintounette:BAAALAADCgcIBwAAAA==.Fléxo:BAAALAADCgIIAgABLAAECgcIGQAeAOAcAA==.',Fo='Foxminator:BAAALAAECgMICAAAAA==.',Fr='Fredyy:BAAALAAECgMIAwAAAA==.Frellon:BAABLAAECoEcAAIFAAcIXw7qiwCfAQAFAAcIXw7qiwCfAQAAAA==.',Fu='Fufuspwan:BAAALAAECgMIBgAAAA==.Funmore:BAAALAAECgEIAQAAAA==.Future:BAAALAADCggICAAAAA==.',['Fé']='Fétidø:BAAALAADCggIDwAAAA==.',['Fü']='Füshï:BAABLAAECoEkAAQKAAgIFh64CgCAAgAKAAgIiRm4CgCAAgAdAAQINR+sFQA3AQAWAAMI3w+WbwCfAAAAAA==.',Ga='Gakorikus:BAAALAAECgYIEwAAAA==.Gardener:BAAALAAECgIIBAAAAA==.',Gi='Gimlisan:BAABLAAECoEjAAIOAAgIzBvMCwCAAgAOAAgIzBvMCwCAAgAAAA==.',Gl='Gluglu:BAAALAAFFAIIAgAAAA==.',Gn='Gnomegazél:BAAALAADCggIBgAAAA==.',Go='Gobeau:BAAALAADCgUIBQAAAA==.Golth:BAABLAAECoEZAAIHAAcI/BNnPACqAQAHAAcI/BNnPACqAQAAAA==.Gonvalskyy:BAACLAAFFIEKAAIBAAMIyRDJFQDFAAABAAMIyRDJFQDFAAAsAAQKgSgAAwEACAibGeUnAEwCAAEACAibGeUnAEwCAAwABwhOBVdtADMBAAAA.Gorouane:BAAALAADCggIDgABLAAECgcIHQASAFUcAA==.Goroumu:BAABLAAECoEdAAISAAcIVRyqFwBKAgASAAcIVRyqFwBKAgAAAA==.Gortikas:BAAALAAECgUIBwAAAA==.Goudale:BAABLAAECoEmAAMGAAcIDiGfCgChAgAGAAcIDiGfCgChAgAFAAII1AqGKgFNAAAAAA==.',Gr='Grenat:BAABLAAECoEWAAIPAAYIGRYTWgCqAQAPAAYIGRYTWgCqAQAAAA==.Gribouille:BAAALAAECgYIDgAAAA==.Grosbïscuit:BAAALAADCgYIBgAAAA==.Grô:BAAALAAECgYICwAAAA==.Grøcka:BAAALAADCggICAAAAA==.',Gu='Guccishag:BAAALAAECgYIBwAAAA==.',['Gä']='Gägou:BAAALAAECgYICAAAAA==.',['Gé']='Géräldyne:BAABLAAECoEaAAIbAAgI0RhIBQB0AgAbAAgI0RhIBQB0AgAAAA==.',['Gü']='Günter:BAAALAAECgcIDwABLAAECggICQAVAAAAAA==.',Ha='Haelas:BAAALAAECgEIAQAAAA==.Halma:BAAALAADCggICAABLAAECgYIEwAVAAAAAA==.Halyzea:BAAALAADCggICAAAAA==.Hanvoc:BAAALAADCgcIEwAAAA==.Hareyaka:BAABLAAECoEZAAIFAAcINAxlnQB/AQAFAAcINAxlnQB/AQAAAA==.Harlèy:BAABLAAECoEZAAIBAAgIFCB8DgDbAgABAAgIFCB8DgDbAgAAAA==.Hartus:BAABLAAECoEeAAQbAAgI9SKjAQAiAwAbAAgI9SKjAQAiAwAeAAYIzhvJKACxAQAPAAIIeBq2sQChAAAAAA==.Hayllay:BAAALAAECgcIDQAAAA==.',He='Healianna:BAABLAAECoEYAAILAAcIfw5CUQBhAQALAAcIfw5CUQBhAQAAAA==.Hellvyra:BAAALAAECgIIAwAAAA==.Henodine:BAAALAAECgYIDwAAAA==.Hermaphrødyt:BAAALAADCggICAAAAA==.',Hi='Hirock:BAAALAADCgUIBQAAAA==.Hirrho:BAAALAAECgMIAwAAAA==.Hizallinna:BAAALAAECgYIDwABLAAECggIHwAPACcbAA==.Hizä:BAAALAADCgYIBgABLAAECggIHwAPACcbAA==.',Hy='Hybrisya:BAAALAADCggIDwAAAA==.',['Hä']='Hällay:BAABLAAECoEkAAIIAAgI8RFlUgD8AQAIAAgI8RFlUgD8AQAAAA==.',['Hæ']='Hæstia:BAAALAAECgIIAgAAAA==.',['Hè']='Hèllwen:BAABLAAECoEXAAIPAAgIyglKbgBwAQAPAAgIyglKbgBwAQAAAA==.',['Hé']='Hélgie:BAAALAADCggICAAAAA==.Héølÿs:BAAALAADCgcICwAAAA==.',['Hë']='Hëavy:BAAALAAECgQIBwAAAA==.',['Hî']='Hîsoka:BAAALAAECgYIEgAAAA==.',Id='Idel:BAAALAAECgUIBQAAAA==.',Io='Ionia:BAABLAAECoEiAAMgAAgIsBzmDQCYAgAgAAgIsBzmDQCYAgAOAAcIPA6/IwBQAQAAAA==.',Is='Isadora:BAABLAAECoEaAAIFAAcILhsqTgAlAgAFAAcILhsqTgAlAgAAAA==.Isagarran:BAAALAADCggIHAAAAA==.Isteh:BAAALAADCgQIBAAAAA==.Isthar:BAAALAADCggICAAAAA==.',Ja='Jacklamatraq:BAAALAAECgYIBgABLAAECgcIGQAeAOAcAA==.Jaimelabiere:BAAALAADCgMIAwAAAA==.',Je='Jeremchaçeur:BAAALAAECgcIDQAAAA==.Jeñny:BAAALAAECgUIBQAAAA==.',Ji='Jilkaniz:BAABLAAECoEbAAIFAAcIswgSsgBaAQAFAAcIswgSsgBaAQAAAA==.',Jo='Jobabz:BAAALAADCgcIBwAAAA==.',Jr='Jrams:BAABLAAECoEWAAIFAAgIvBXGXQD9AQAFAAgIvBXGXQD9AQAAAA==.',Ju='Jujudk:BAAALAAECgcIDAAAAA==.Junnahlaas:BAAALAADCgEIAQAAAA==.Justpango:BAAALAAECgEIAQAAAA==.',['Jä']='Jäcqueline:BAAALAADCggICAAAAA==.',['Jô']='Jônathan:BAAALAAECgYICQAAAA==.',['Jø']='Jøyce:BAAALAADCggIDQAAAA==.',Ka='Kaeldorei:BAABLAAECoEVAAIFAAgI5RMWVgAQAgAFAAgI5RMWVgAQAgAAAA==.Kaerno:BAAALAAECgEIAQAAAA==.Kaiøshin:BAAALAAECgIIAwAAAA==.Kakelmon:BAAALAADCgcIBwAAAA==.Kalipsa:BAAALAAECgYIEwAAAA==.Kalm:BAAALAADCgIIAgAAAA==.Kamaa:BAAALAAECgYIEAAAAA==.Kame:BAAALAADCggICAAAAA==.Kamélià:BAAALAAFFAIIAgABLAAFFAIICAAIANchAA==.Kananne:BAAALAAECgcIDQAAAA==.Karadraz:BAABLAAECoElAAIcAAgI2xgXDgA3AgAcAAgI2xgXDgA3AgAAAA==.Kaulendil:BAAALAAECgUIBQABLAAECgcIGQAHAPwTAA==.Kayne:BAAALAAECgMIAwAAAA==.',Kh='Khaldoran:BAAALAAECggIBgAAAA==.Khøra:BAAALAAECggIBgAAAA==.',Kk='Kkanane:BAAALAAECgMIAwAAAA==.',Kl='Klainn:BAACLAAFFIEIAAIIAAII1yExGQC/AAAIAAII1yExGQC/AAAsAAQKgSAAAggACAhHI3YTAAkDAAgACAhHI3YTAAkDAAAA.',Ko='Kouloup:BAAALAADCgEIAQAAAA==.Kovac:BAAALAADCgcIFQAAAA==.Koval:BAAALAADCggIHwAAAA==.Kovalchuck:BAAALAAECgYIEgAAAA==.',Kr='Krâkeur:BAABLAAECoEYAAIFAAgIjxgATgAmAgAFAAgIjxgATgAmAgAAAA==.',Ku='Kurohana:BAAALAAECgQIBAAAAA==.',Ky='Kyarma:BAAALAADCgQIBAAAAA==.Kyranah:BAABLAAECoEjAAIEAAgI+Q4gMwDZAQAEAAgI+Q4gMwDZAQAAAA==.Kyuby:BAAALAAECgUICAAAAA==.',['Kâ']='Kâthllyn:BAAALAAECgYIEwAAAA==.',['Kä']='Kägrïm:BAAALAADCggIAwAAAA==.',['Kæ']='Kænã:BAABLAAECoEiAAIhAAgIgQMTKwD0AAAhAAgIgQMTKwD0AAAAAA==.',['Kô']='Kôva:BAAALAADCggIDQAAAA==.',La='Lakri:BAAALAAECggIDwAAAA==.',Le='Lensorceleze:BAAALAAECgIIAgAAAA==.Leonidia:BAAALAAECgMIAwAAAA==.Leumbdrood:BAAALAAECgQIBAABLAAECggIKQASAOkdAA==.Lexya:BAAALAADCggIEgAAAA==.',Lh='Lhunhah:BAAALAAECgEIAQAAAA==.',Li='Lihz:BAAALAADCggIEwAAAA==.',Lo='Lolippop:BAABLAAECoEaAAIQAAYIsBTNfwB3AQAQAAYIsBTNfwB3AQAAAA==.Lolli:BAAALAADCgUIBQAAAA==.Lollipøps:BAAALAAECgYIDAABLAAECggIIAAPAMgZAA==.Loone:BAAALAADCggICAABLAAECgcIHQABAC8iAA==.Loupkus:BAABLAAECoEUAAIFAAgIQQ20dQDKAQAFAAgIQQ20dQDKAQAAAA==.Loupkìus:BAAALAAECgYIDAAAAA==.Louragan:BAABLAAECoEkAAMEAAgIwBo6KwAFAgAEAAcIMRk6KwAFAgANAAcInw/6SgCDAQAAAA==.Loûragan:BAAALAADCgUIBQABLAAECggIJAAEAMAaAA==.',Lu='Luhna:BAAALAADCgYIBgAAAA==.Luhnae:BAAALAADCggIEQAAAA==.Luhnah:BAAALAADCgIIAgAAAA==.Lukaélys:BAACLAAFFIELAAIDAAMIahDSGQDgAAADAAMIahDSGQDgAAAsAAQKgSQAAgMACAhfHaRDAEkCAAMACAhfHaRDAEkCAAAA.Lulabi:BAAALAADCgQIBAAAAA==.Lunnah:BAAALAADCggIDwAAAA==.Luther:BAAALAADCggIEAAAAA==.Luzim:BAABLAAECoEaAAIgAAYI4xUMKQCEAQAgAAYI4xUMKQCEAQAAAA==.',['Lé']='Lénastrasza:BAABLAAECoEgAAMUAAgIxRegBQAfAgAUAAcIGhmgBQAfAgASAAcIFxH8KwCaAQAAAA==.Léonnie:BAAALAADCggIDwAAAA==.Léønie:BAAALAADCgYIBgAAAA==.',['Lë']='Lëonidas:BAAALAADCgcIBwAAAA==.',['Lï']='Lïcht:BAABLAAECoEaAAIFAAcIWw0EkwCSAQAFAAcIWw0EkwCSAQAAAA==.Lïôh:BAAALAAECgYICgAAAA==.',['Lö']='Lööne:BAABLAAECoEdAAIBAAcILyLOHACAAgABAAcILyLOHACAAgAAAA==.',['Lø']='Løgosh:BAAALAADCgcIDQAAAA==.Løther:BAAALAAFFAIIAgABLAAFFAUIDwAYAI8gAA==.',Ma='Maena:BAABLAAECoEUAAIeAAYILhDOMwB8AQAeAAYILhDOMwB8AQAAAA==.Magehuskull:BAABLAAECoEcAAIiAAYIgx0tHgABAgAiAAYIgx0tHgABAgABLAAECgcIGgAWAA0dAA==.Mara:BAACLAAFFIELAAIKAAQIqhDeAgBGAQAKAAQIqhDeAgBGAQAsAAQKgR4AAwoACAgDGmYLAHQCAAoACAgDGmYLAHQCAB0AAwh7EbohAKAAAAAA.Marakta:BAAALAAFFAIIAgAAAA==.Marius:BAAALAAECgMIAwAAAA==.Marmonäe:BAAALAADCggIDQAAAA==.Maryløue:BAAALAADCgIIAgAAAA==.',Mc='Mcdougals:BAAALAAECgEIAQAAAA==.',Me='Medene:BAAALAADCgMIAwAAAA==.Medrasbliz:BAAALAADCggICAAAAA==.Meilya:BAAALAADCggICwAAAA==.Melyyna:BAABLAAECoEhAAIBAAcIDBQjYACUAQABAAcIDBQjYACUAQAAAA==.Merwën:BAAALAADCggICAAAAA==.Metalkid:BAAALAADCggIEAAAAA==.',Mi='Michel:BAAALAAECgUIBQABLAAECgYIBAAVAAAAAA==.Mijokii:BAAALAADCgcICAAAAA==.Mikhä:BAAALAADCgcIBwAAAA==.Minl:BAACLAAFFIELAAIDAAQIfyGsCgCGAQADAAQIfyGsCgCGAQAsAAQKgSQAAgMACAjnIFAiAMQCAAMACAjnIFAiAMQCAAAA.',Mo='Monalisa:BAAALAAECgYIEwAAAA==.Moonfurie:BAABLAAECoEVAAMLAAYI0xElVgBPAQALAAYI0xElVgBPAQAWAAQI9wpjawCzAAAAAA==.Mopsmash:BAABLAAECoEZAAMjAAgItQgqSADwAAAjAAYI7QQqSADwAAAFAAUI1Qfy6gDiAAAAAA==.Motillium:BAABLAAECoEZAAIGAAcIyxzbFQAUAgAGAAcIyxzbFQAUAgAAAA==.',Mu='Multichøuf:BAAALAADCgEIAQAAAA==.',My='Myralaza:BAABLAAECoElAAINAAgIAhIhOQDQAQANAAgIAhIhOQDQAQAAAA==.Myzerykord:BAAALAAECgYIBgAAAA==.',['Mä']='Mätaharipotr:BAAALAADCggIEAAAAA==.',['Mï']='Mïtia:BAAALAADCgQIBAAAAA==.',Na='Nagashi:BAABLAAECoEUAAIFAAcI9BThdwDGAQAFAAcI9BThdwDGAQAAAA==.Nagasumbra:BAAALAADCggICAABLAADCggIGAAVAAAAAA==.Nanïbi:BAAALAADCggICAAAAA==.Narcissa:BAAALAADCgcIBwABLAAECgcIIQABAAwUAA==.',Ne='Neazl:BAAALAADCggICAAAAA==.Necrodragon:BAAALAAECgcIEwAAAA==.Nehøsky:BAAALAAECgYIBgAAAA==.Neosto:BAAALAADCgcIGQABLAADCggIHAAVAAAAAA==.Neven:BAAALAAECgUIBgAAAA==.',Ni='Nicki:BAABLAAECoEgAAIiAAgIQRxwDgCZAgAiAAgIQRxwDgCZAgAAAA==.Nimasus:BAAALAAECgcIBwAAAA==.Nimuae:BAAALAAECgUIBQAAAA==.Nishimiya:BAABLAAECoEiAAIFAAcIsR1kRABBAgAFAAcIsR1kRABBAgAAAA==.Nivélion:BAAALAAECgMIBgAAAA==.',No='Noflowers:BAAALAADCgcIBwAAAA==.Northstar:BAAALAAECgYIEgAAAA==.Novocaïne:BAAALAADCgEIAQABLAAECgIIAgAVAAAAAA==.',Nu='Nuhara:BAABLAAECoEdAAMOAAcI9A/ZHwB1AQAOAAcI9A/ZHwB1AQAgAAcI/wtQLQBmAQABLAAFFAIIBAAVAAAAAA==.',Ny='Nycø:BAAALAADCgcIDAAAAA==.',['Nå']='Nåøh:BAAALAAECggICAABLAAECggIHQAkAAAeAA==.',['Né']='Néni:BAAALAADCggIFgABLAAECggIFgAQAKANAA==.Néphénie:BAABLAAECoEUAAIfAAgIOCDgAgDOAgAfAAgIOCDgAgDOAgAAAA==.',['Nø']='Nøpala:BAAALAADCggIFQAAAA==.',['Nÿ']='Nÿwer:BAAALAADCgUIBgAAAA==.',Ob='Obëlïx:BAABLAAECoE2AAIZAAgI8h7gFQDjAgAZAAgI8h7gFQDjAgAAAA==.',Oc='Ocpnaibus:BAAALAADCgMIBQAAAA==.',Od='Oda:BAAALAAECgIIAgAAAA==.Odeha:BAAALAADCgYIBgAAAA==.',Ol='Olberick:BAAALAADCggICAAAAA==.Oliveetconne:BAAALAAECgQIBAABLAAECgYIBgAVAAAAAA==.',Om='Omnissiah:BAAALAAECgYICgAAAA==.',Op='Ophedemo:BAAALAADCggIFwAAAA==.Ophegaelle:BAAALAAECgUICAAAAA==.',Or='Orak:BAAALAADCgQIBAABLAAECgYIBgAVAAAAAA==.Orokke:BAAALAAECgYIBgAAAA==.Orrion:BAAALAADCgcIGQABLAADCggIHAAVAAAAAA==.',Ow='Oweglacier:BAAALAAECgIIAgAAAA==.',Ox='Oxias:BAAALAAECgYIDgAAAA==.',Pa='Palafoune:BAAALAAECgcICAAAAA==.Palaghøst:BAAALAAECgUIBQAAAA==.Pancarte:BAAALAAECgYICAAAAA==.Pandragor:BAAALAADCgUIBQAAAA==.Panoramixx:BAAALAAECgMIBQAAAA==.Paÿnn:BAABLAAECoEUAAIFAAcIGRCuhwCoAQAFAAcIGRCuhwCoAQAAAA==.',Pe='Perfoura:BAAALAADCgQIBAAAAA==.Perihan:BAAALAAECgIIAgABLAAECgcIHAANAFkZAA==.Persépöils:BAAALAAECgYIDQAAAA==.Petitgibier:BAAALAAECgYICgAAAA==.',Pi='Picoldur:BAAALAAECggIBgAAAA==.Pitkonk:BAAALAADCgUIBQAAAA==.',Po='Polumental:BAAALAADCggICAAAAA==.Pompix:BAAALAAECgIIAgAAAA==.Poney:BAAALAADCgYIBwAAAA==.',Pt='Ptitcybelle:BAAALAADCggICAAAAA==.',Pu='Pulsion:BAAALAAECgEIAQABLAAECgcIHgAIAP0cAA==.',Py='Pyrocham:BAAALAAECgcIEgAAAA==.Pyrøblast:BAAALAADCgcIDgAAAA==.',['Pä']='Päuline:BAAALAADCgcIBwAAAA==.',Ra='Radoje:BAABLAAECoEYAAIEAAgIvBn7GQCDAgAEAAgIvBn7GQCDAgAAAA==.Ragnahgnah:BAAALAADCgcIBwABLAAECgcIHgADAIoMAA==.',Re='Regrets:BAAALAADCgEIAQAAAA==.Rezme:BAAALAADCggIEwAAAA==.Reÿel:BAAALAADCggIEQABLAAECgcIIgAFALEdAA==.',Rh='Rhazalmoule:BAAALAADCggICgAAAA==.Rhumcoco:BAAALAADCgIIBAABLAAECgYIBgAVAAAAAA==.',Ri='Riiddick:BAAALAAECgMIBAAAAA==.',Ro='Roasa:BAAALAAECggICAAAAA==.Rokinou:BAABLAAECoEcAAMFAAcICBh9YAD3AQAFAAcICBh9YAD3AQAjAAQIjgU3VACdAAAAAA==.Romye:BAAALAAECggICAAAAA==.Rorolasaumur:BAAALAADCggIGwAAAA==.Roufous:BAABLAAECoEiAAIFAAgIRyR2DgAvAwAFAAgIRyR2DgAvAwAAAA==.',Ry='Rydick:BAAALAAECgYICQAAAA==.Ryuji:BAAALAADCgIIAgAAAA==.',['Rð']='Rðxas:BAAALAAECgMIAwAAAA==.',['Rô']='Rôxxer:BAABLAAECoEhAAIHAAcITx6hGwBvAgAHAAcITx6hGwBvAgAAAA==.',Sa='Saadidda:BAAALAAECgMIBgAAAA==.Safirä:BAAALAAECgYICwAAAA==.Sanølya:BAAALAADCggIGwAAAA==.Satsat:BAABLAAECoEhAAIBAAgITA9eaAB+AQABAAgITA9eaAB+AQAAAA==.Satørugøjø:BAAALAADCgcIDAAAAA==.Sawa:BAABLAAECoEaAAIWAAcIDR2FJwD+AQAWAAcIDR2FJwD+AQAAAA==.Sawadatsuna:BAAALAADCgQIBAABLAAECgcIGgAWAA0dAA==.Saïkûrøn:BAAALAADCgcIBwAAAA==.',Sc='Scalliebaby:BAABLAAECoEhAAITAAgIVR2sBgCtAgATAAgIVR2sBgCtAgAAAA==.Scarmiglione:BAABLAAECoEUAAQeAAYIPyGAFgAlAgAeAAYIHR+AFgAlAgAPAAQIahUjlQAGAQAbAAIIhiJ1IADIAAAAAA==.',Se='Sek:BAAALAAECggIBwAAAA==.Seph:BAAALAAECgYIBgAAAA==.Sephi:BAABLAAECoEXAAISAAcIARrWGgAqAgASAAcIARrWGgAqAgAAAA==.Sethilperdu:BAAALAADCgcIBwAAAA==.Seykara:BAAALAADCgcICQAAAA==.',Sh='Shadraneth:BAAALAAECgcIEQABLAAECgcIGQAHAPwTAA==.Shae:BAAALAADCggIDgAAAA==.Shaldoreï:BAABLAAECoEeAAIIAAgIaw/yZADNAQAIAAgIaw/yZADNAQAAAA==.Shali:BAABLAAECoEjAAMMAAgI3xGIQwDGAQAMAAgI3xGIQwDGAQABAAYICxm6XgCYAQAAAA==.Shalteaa:BAAALAADCgcIGwAAAA==.Shayastrasha:BAABLAAECoEgAAIFAAcIFxyDQABNAgAFAAcIFxyDQABNAgAAAA==.Shelannath:BAAALAADCgMIBAABLAAECgcIHAAeAOAeAA==.Shifumeå:BAAALAADCggICAAAAA==.Shindeiwa:BAABLAAECoEhAAIjAAcI5yE0CwCkAgAjAAcI5yE0CwCkAgAAAA==.Shocan:BAAALAADCggIHgAAAA==.Shomen:BAAALAAECgYIEAAAAA==.Shootingstar:BAAALAADCggIDgAAAA==.Shyra:BAAALAAECgMIAwAAAA==.',Si='Sinahindo:BAAALAAECgcICwAAAA==.',Sk='Sky:BAAALAAECgIIAwAAAA==.',So='Somøney:BAAALAAECgEIAQAAAA==.Sornet:BAABLAAECoEUAAIXAAcIUxAzNwBiAQAXAAcIUxAzNwBiAQAAAA==.Sortha:BAAALAAECgYIEgAAAA==.',Sp='Spadiell:BAABLAAECoEgAAIQAAgIDyFkFwDUAgAQAAgIDyFkFwDUAgAAAA==.Sparta:BAAALAAECgYICQAAAA==.Spyroo:BAAALAADCgYICgABLAAECgYIBgAVAAAAAA==.Spyrou:BAAALAADCgYIBgAAAA==.',St='Stalana:BAAALAAECgQIBAAAAA==.',Su='Suguru:BAAALAADCggIDAAAAA==.Superdps:BAACLAAFFIEKAAMQAAIIXCZhEwDaAAAQAAIIXCZhEwDaAAAHAAEINh+AKQBRAAAsAAQKgSQABBAABwizJooMABsDABAABwizJooMABsDAAcABAhlHt9UAEgBAB8AAghtIdEYAKYAAAAA.Surïon:BAAALAADCgYIBgAAAA==.',['Sé']='Séräphyne:BAAALAADCggICgAAAA==.',['Sö']='Söja:BAABLAAECoEiAAQgAAgIbQmVMQBIAQAgAAcI+AiVMQBIAQAOAAgIqwdaJwAvAQAhAAIIVgKxPgA6AAAAAA==.',['Sø']='Søulwørld:BAAALAAECgYIBgAAAA==.',['Sù']='Sùbzérø:BAAALAAECgUICwAAAA==.',['Sý']='Sýhl:BAABLAAECoEdAAMkAAgIAB6kBwDLAgAkAAgIAB6kBwDLAgAcAAcIMhWtHQBaAQAAAA==.',['Sÿ']='Sÿhl:BAAALAAECgYICwABLAAECggIHQAkAAAeAA==.',Ta='Taaz:BAAALAAECgEIAQAAAA==.Taraën:BAAALAADCgUIBQAAAA==.Tarteaufruit:BAAALAAECgYIBgAAAA==.',Te='Tempax:BAAALAADCgYIBwAAAA==.Temperanceb:BAAALAAECgYIDgAAAA==.',Th='Thalorin:BAAALAADCgIIAgAAAA==.Thebird:BAAALAADCgcIBwAAAA==.Thebodjack:BAAALAAECgYIEwAAAA==.Theguy:BAACLAAFFIEGAAIZAAIIbhaNHQCkAAAZAAIIbhaNHQCkAAAsAAQKgSIAAxkACAgiHx0XANsCABkACAi2Hh0XANsCABoABwh1HBUIAE8CAAAA.Thorggyr:BAAALAAECgYIBgAAAA==.Thylte:BAABLAAECoEUAAIDAAcIURcbbQDkAQADAAcIURcbbQDkAQAAAA==.Thörvald:BAAALAADCggICAAAAA==.',Ti='Titørius:BAAALAADCgcIBwAAAA==.Tiwen:BAAALAAECgMIBgAAAA==.',To='Togurô:BAAALAAECgcIDQAAAA==.Torkîl:BAABLAAECoEZAAIhAAcIhxz2DgA6AgAhAAcIhxz2DgA6AgAAAA==.',Tr='Trolaklass:BAAALAAECgYIDgAAAA==.Trunk:BAAALAAECgYIEwAAAA==.Trégorr:BAAALAAECgYIEwAAAA==.',Ts='Tsukiken:BAABLAAECoEbAAISAAgIUiEHCAAIAwASAAgIUiEHCAAIAwAAAA==.',Tw='Twyd:BAABLAAECoEgAAMaAAgIOg/pDQDSAQAaAAgIOg/pDQDSAQAZAAYIGQkEiAAdAQAAAA==.',['Tæ']='Tænee:BAAALAADCgUIBQAAAA==.',['Tï']='Tïdeg:BAAALAAECgYICwAAAA==.Tïtanïa:BAAALAAECgYIBwAAAA==.',['Tô']='Tôtsuka:BAAALAAECgEIAQAAAA==.',Um='Umeå:BAAALAAECgYIBgAAAA==.',Un='Unmåte:BAAALAAECgcIDgAAAA==.',Va='Valyna:BAAALAADCgcIBwAAAA==.Vanish:BAAALAADCgcIBwAAAA==.',Ve='Velmeya:BAABLAAECoE6AAIZAAgIeyLoEgD4AgAZAAgIeyLoEgD4AgAAAA==.Ventor:BAAALAADCggIFwABLAAECgcIJAALAPkgAA==.Vermithor:BAAALAAECgYIDQAAAA==.Vespéron:BAAALAADCgUIBQAAAA==.',Vi='Viggnette:BAABLAAECoEWAAIYAAcITw1cLQCmAQAYAAcITw1cLQCmAQAAAA==.Virus:BAACLAAFFIEKAAMkAAIISSLtBgDOAAAkAAIISSLtBgDOAAADAAEIFA5SaQBBAAAsAAQKgRYAAyQACAgGI94IALMCACQABwhLI94IALMCAAMAAwgBI77pAAEBAAEsAAUUAggKABAAXCYA.Visaraa:BAABLAAECoEWAAIEAAYIGA4qTgBVAQAEAAYIGA4qTgBVAQAAAA==.',Vr='Vritra:BAABLAAECoEhAAIcAAcIpRM9FwCqAQAcAAcIpRM9FwCqAQAAAA==.',Vu='Vuldan:BAAALAAECgIIAgAAAA==.',['Vé']='Véradán:BAAALAADCgYIBgAAAA==.',['Vö']='Vögue:BAABLAAECoEWAAINAAcIPiH/GACIAgANAAcIPiH/GACIAgAAAA==.',['Vø']='Vømito:BAAALAAECgEIAQAAAA==.',Wa='Wahalali:BAAALAADCgcIBwAAAA==.',Wh='Whatamidoing:BAAALAAECgYICQABLAAFFAIIBgAPAFYgAA==.',Wi='Wiyll:BAAALAAECgEIAQABLAAECgYICAAVAAAAAA==.',Wo='Woldbard:BAAALAADCgUIBQAAAA==.Worgdelamort:BAABLAAECoEWAAMcAAcIYBvZDgAoAgAcAAcIYBvZDgAoAgADAAEIaQP8UwEnAAAAAA==.',['Wà']='Wàzabï:BAAALAAECgYICgABLAAECgcIGQAeAOAcAA==.',Xa='Xaliatath:BAAALAAECgcIEAAAAA==.Xaraac:BAAALAADCggIJQAAAA==.Xarya:BAACLAAFFIEMAAIEAAMInB/mCQAuAQAEAAMInB/mCQAuAQAsAAQKgS0AAgQACAgaJTgDAGQDAAQACAgaJTgDAGQDAAAA.',Xi='Xibalba:BAAALAADCgYIBgAAAA==.Xinchao:BAAALAAECgMIBQAAAA==.Xinyi:BAAALAADCgQIBAAAAA==.',Ya='Yaedïth:BAAALAADCggICAAAAA==.Yamichto:BAAALAAECgQIBQAAAA==.Yaminéral:BAAALAADCgQIAwAAAA==.Yarubo:BAAALAADCgcIEQAAAA==.',Ye='Yelgi:BAAALAADCgQIBAAAAA==.Yeus:BAAALAADCgIIAgABLAAECgYIBgAVAAAAAA==.Yeuz:BAAALAADCgQIBgABLAAECgYIBgAVAAAAAA==.',Yo='Yoleen:BAAALAAECgYIBgAAAA==.Yopimarus:BAABLAAECoEoAAINAAgIwSXuAQBpAwANAAgIwSXuAQBpAwAAAA==.Yorri:BAABLAAECoETAAIFAAcIABLbcADUAQAFAAcIABLbcADUAQABLAAECggIHgABAOodAA==.Yotnar:BAAALAAECgMIAwABLAAECggIFwAHAPIhAA==.',Yr='Yrnios:BAAALAADCggIDgAAAA==.Yrnos:BAAALAAECgUICgAAAA==.Yrzatz:BAABLAAECoEgAAIiAAgIhROXHgD+AQAiAAgIhROXHgD+AQAAAA==.',Yu='Yuichiro:BAAALAAECgYIBgAAAA==.',['Yà']='Yàms:BAABLAAECoEkAAIMAAgIpBWYKwA4AgAMAAgIpBWYKwA4AgAAAA==.',['Yû']='Yûreî:BAABLAAECoEZAAIBAAcIZhA0egBQAQABAAcIZhA0egBQAQAAAA==.',Za='Zabuzas:BAAALAAECgMIBgAAAA==.Zaggara:BAAALAADCgQIBQAAAA==.Zaktan:BAAALAADCgcIHwAAAA==.Zandou:BAAALAADCgcIDgABLAAECgYIBgAVAAAAAA==.',Ze='Zelfa:BAAALAAECgMICAAAAA==.Zelkar:BAAALAADCgEIAQAAAA==.Zenogs:BAAALAADCgQIBAAAAA==.Zestarie:BAAALAADCggICAAAAA==.Zetharis:BAAALAADCggIFgAAAA==.',Zi='Zinàcien:BAABLAAECoEbAAIhAAcIaAyqIQBLAQAhAAcIaAyqIQBLAQAAAA==.',Zo='Zorykø:BAAALAAECgMIAwAAAA==.Zoukely:BAAALAAECgYICQAAAA==.',Zu='Zulgorom:BAAALAAECgYIDQAAAA==.',Zy='Zyrix:BAABLAAECoEVAAMXAAgIVhrXIQDqAQAXAAgIThnXIQDqAQAZAAUIAhQGgAA2AQAAAA==.',['Zå']='Zåk:BAAALAAECgUIBQAAAA==.',['Às']='Àstride:BAAALAAECgYIBgAAAA==.',['Ân']='Ângélina:BAAALAADCgIIAgAAAA==.',['Él']='Élîe:BAACLAAFFIEIAAIGAAQIEwkABQDrAAAGAAQIEwkABQDrAAAsAAQKgS0AAwUACAhiITkfANMCAAUACAh5HzkfANMCAAYACAhcHXgOAGkCAAAA.',['Ér']='Érèbe:BAABLAAECoEZAAMDAAgI7CA/JwCuAgADAAgI6h8/JwCuAgAkAAUIliC8GQDVAQAAAA==.',['Ïg']='Ïgøre:BAAALAADCgIIAgAAAA==.',['Ða']='Ðarkoune:BAAALAADCggICAAAAA==.',['Ôô']='Ôô:BAAALAADCgcICAAAAA==.',['Øm']='Ømfæ:BAABLAAECoEZAAMeAAcI4Bw2EgBMAgAeAAcI+Bs2EgBMAgAPAAMIXBYupQDNAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end