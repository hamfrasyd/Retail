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
 local lookup = {'Paladin-Retribution','Shaman-Elemental','Monk-Brewmaster','Unknown-Unknown','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Blood','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Evoker-Devastation','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','Paladin-Holy','Shaman-Restoration','Druid-Feral','Mage-Arcane','Monk-Mistweaver','DeathKnight-Frost','Warrior-Protection','Paladin-Protection','Mage-Frost','Priest-Holy','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','DeathKnight-Unholy','Priest-Discipline','Rogue-Assassination','Rogue-Subtlety',}; local provider = {region='EU',realm='Saurfang',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaeran:BAAALAADCgYIBgAAAA==.Aapie:BAABLAAECoEgAAIBAAgIQRdZYgDwAQABAAgIQRdZYgDwAQAAAA==.',Ae='Aesir:BAAALAAECggICAAAAA==.Aetheria:BAAALAAECgQIBgAAAA==.Aethra:BAAALAAECgQICgAAAA==.',Ai='Aimandready:BAAALAAECggICwAAAA==.Aisae:BAAALAADCgcIBwAAAA==.',Al='Alakan:BAABLAAECoEVAAICAAgI1BdVKABIAgACAAgI1BdVKABIAgAAAA==.Alan:BAACLAAFFIESAAIDAAYIXhodAwC+AQADAAYIXhodAwC+AQAsAAQKgRsAAgMACAj2I3AEABkDAAMACAj2I3AEABkDAAAA.Alcò:BAAALAAECgYIBgAAAA==.Alise:BAAALAADCggIEAAAAA==.Alishira:BAAALAADCggIEAABLAAECgQIBQAEAAAAAA==.Alofury:BAABLAAECoEUAAIFAAgIMxJ0QgDvAQAFAAgIMxJ0QgDvAQAAAA==.Alsek:BAABLAAECoEXAAIGAAYIPA19FgBPAQAGAAYIPA19FgBPAQAAAA==.Altchamp:BAAALAAECgMIAwAAAA==.',Am='Amanari:BAABLAAECoEkAAIHAAgI6iDEFQD5AgAHAAgI6iDEFQD5AgAAAA==.Amara:BAAALAADCgcIBwABLAAECggIHwAIAJIUAA==.Amaral:BAAALAAECgQICgAAAA==.Amidrasil:BAAALAAECggIBwAAAA==.',An='Anaya:BAAALAAECgYIDAAAAA==.Antabus:BAAALAADCgYIBgAAAA==.',Ap='Apoker:BAACLAAFFIEMAAIHAAQIFBiPCgBWAQAHAAQIFBiPCgBWAQAsAAQKgSUAAgcACAiEJDIMADMDAAcACAiEJDIMADMDAAAA.',Ar='Archela:BAAALAAECggICAAAAA==.Arrhythmia:BAACLAAFFIEJAAIJAAMIRRifCwD+AAAJAAMIRRifCwD+AAAsAAQKgUUAAgkACAgJJDgIACkDAAkACAgJJDgIACkDAAAA.',As='Aspin:BAAALAAECgYIEwAAAA==.Astriaa:BAAALAAECgIIAQAAAA==.',At='Atrocity:BAAALAADCgIIAgAAAA==.',Aw='Awda:BAAALAADCgYICwAAAA==.Awoogah:BAAALAAECgYIDQAAAA==.',Az='Azerak:BAAALAAECgcIEgAAAA==.',Ba='Badel:BAAALAAECggIBQAAAA==.Baiser:BAABLAAECoEcAAQKAAgIqA5zDwCcAQAKAAcI5wxzDwCcAQALAAYIfAyseABQAQAMAAYIeAmoRwAnAQAAAA==.Bambi:BAAALAADCggIIAABLAAECgcIIAANAOMKAA==.Bangbil:BAAALAADCgYIBgAAAA==.Bayonetta:BAAALAADCgUIBQAAAA==.',Be='Bellatris:BAAALAADCgUIBQABLAAFFAMICAAOAJwTAA==.Beniu:BAAALAAECgUIAwAAAA==.Bert:BAAALAADCgMIAwAAAA==.',Bi='Bigbloodyboy:BAAALAAECgcICwABLAAFFAUIDQAMAGwfAA==.',Bl='Blitzcow:BAAALAADCgEIAQAAAA==.Bloodeye:BAAALAADCgQIBAAAAA==.Bloodgorged:BAAALAADCggICAAAAA==.Bloodmace:BAAALAAECgEIAQAAAA==.Bloodreeinaa:BAAALAADCgYIDQAAAA==.Bloodyfloof:BAAALAADCgUIBQAAAA==.Bloomkin:BAAALAADCggIHQAAAA==.Bludder:BAABLAAECoEbAAIPAAcIph+VGgB1AgAPAAcIph+VGgB1AgAAAA==.Bluerock:BAABLAAECoEhAAIQAAgInCEjFgDZAgAQAAgInCEjFgDZAgAAAA==.Bluékel:BAAALAAECgIIAgAAAA==.',Bo='Bobbie:BAAALAAECggIDgAAAA==.Boombam:BAABLAAECoEhAAIRAAgI4B3yEQCxAgARAAgI4B3yEQCxAgAAAA==.Bosston:BAAALAAECggIDAAAAA==.',Br='Brathair:BAABLAAECoElAAIDAAgIixd8EQAPAgADAAgIixd8EQAPAgAAAA==.',Bs='Bs:BAAALAAECgIIAgAAAA==.',Ca='Canieatyouup:BAACLAAFFIEFAAIHAAMIyBUGEgDxAAAHAAMIyBUGEgDxAAAsAAQKgSQAAwcACAhJIkYXAO8CAAcACAhJIkYXAO8CAA4ABghsII8QACcCAAAA.Cartron:BAABLAAECoEbAAMSAAcI3yKWDwC2AgASAAcI3yKWDwC2AgARAAEI2BQxiwAzAAAAAA==.',Ce='Ceasar:BAAALAAECgUIBwAAAA==.',Ch='Chachadans:BAAALAAECgMIAwAAAA==.Chaín:BAAALAAECgQIBAAAAA==.Chib:BAABLAAECoEgAAIJAAcI2CITEwC9AgAJAAcI2CITEwC9AgAAAA==.Chiraya:BAABLAAECoEZAAIRAAcIZxu5HwAwAgARAAcIZxu5HwAwAgAAAA==.Chrysiana:BAAALAADCgYIDAAAAA==.',Ci='Ciganin:BAAALAAECgEIAQAAAA==.',Cl='Clavain:BAAALAADCgUIBQABLAAECgYIEAAEAAAAAA==.',Co='Cogwheal:BAAALAAECgYICAAAAA==.Concord:BAAALAADCgcIGQAAAA==.Convectus:BAAALAAECgQIBAAAAA==.',Cr='Cresela:BAAALAAECgYIDgABLAAFFAUIDQATAMgdAA==.Cryerless:BAAALAAECgcIDAAAAA==.',Cy='Cynára:BAACLAAFFIENAAMMAAUIbB/vAAA+AQAMAAMIKSPvAAA+AQALAAMI2h3GEQAmAQAsAAQKgRcAAwwACAisJbIFAPECAAwABwjmJbIFAPECAAsABQiOI8ZHAOQBAAAA.',['Cí']='Círi:BAAALAAECgYIBgAAAA==.',Da='Darkflight:BAAALAADCggIEAAAAA==.Darkpanther:BAACLAAFFIEHAAIQAAMIiQtOFwC+AAAQAAMIiQtOFwC+AAAsAAQKgS4AAhAACAgKIiETAOwCABAACAgKIiETAOwCAAAA.Dawoud:BAAALAAECgUICwABLAAECggIJQADAIsXAA==.',De='Deadlift:BAAALAADCggICAAAAA==.Deadpool:BAAALAAECgIIAwAAAA==.Deadshøt:BAAALAAECgUICgABLAAECggIIgAHAIQkAA==.Deartháir:BAAALAADCgYIBgABLAAECggIJQADAIsXAA==.Deathdarh:BAAALAAECgMIBgAAAA==.Deathseekerv:BAAALAAECgYIEwAAAA==.Deathseker:BAABLAAECoEXAAMCAAcIkBHyRAC8AQACAAcIkBHyRAC8AQAUAAIIdgxP8gBVAAAAAA==.Deathurn:BAAALAADCggIEAABLAAECgcIGQAUAAAQAA==.Demoillidan:BAAALAADCgUICgAAAA==.Demonbanana:BAAALAADCgcIDQAAAA==.Demonicdina:BAAALAADCgYIBgAAAA==.Demonik:BAAALAADCggIDAAAAA==.Demonina:BAAALAAECgMIBwAAAA==.Demoniça:BAAALAAECgYIDwAAAA==.Demonsftw:BAAALAADCggIDgAAAA==.Desideria:BAAALAADCgcIBwAAAA==.Desinty:BAAALAAECgYIEQAAAA==.Deverok:BAAALAADCgYIBgAAAA==.',Di='Diallo:BAAALAADCgUIBwABLAADCgcIBwAEAAAAAA==.Dilithium:BAAALAAECgQICgAAAA==.Dimitrios:BAAALAADCgYICwAAAA==.Discotroll:BAAALAAECgcIEAAAAA==.',Do='Dorfa:BAAALAAECgQICgAAAA==.',Dr='Dragodeath:BAAALAADCgcIDgAAAA==.Dragoneye:BAAALAAECgUIBgAAAA==.Draken:BAAALAADCgYIBgAAAA==.Drakoron:BAAALAADCgYIBwAAAA==.Dreki:BAABLAAECoEaAAINAAcInAXoOgA2AQANAAcInAXoOgA2AQAAAA==.',Du='Duude:BAAALAADCgYIDAAAAA==.',Dv='Dverghamster:BAAALAAECggIDAAAAA==.',El='Eleo:BAAALAADCgYIBgAAAA==.',Em='Emzgas:BAAALAADCgEIAQAAAA==.',En='Envisious:BAAALAADCgUIBQABLAADCgcIBwAEAAAAAA==.',Et='Ethurilien:BAABLAAECoEeAAMOAAgIpBhsFQDpAQAOAAcIxxlsFQDpAQAHAAgIGhL9bwCwAQAAAA==.',Ev='Everild:BAACLAAFFIEIAAIOAAMInBOTAwDYAAAOAAMInBOTAwDYAAAsAAQKgRgAAg4ACAjeGo4PADUCAA4ACAjeGo4PADUCAAAA.',Fa='Faulissra:BAAALAAECgYIDgAAAA==.',Fe='Feoto:BAAALAAECgYIDQAAAA==.',Ff='Ffse:BAAALAADCggIEwAAAA==.',Fh='Fhatman:BAAALAADCggIDwAAAA==.',Fi='Fiorelle:BAAALAAECgYIEAAAAA==.Firepawn:BAAALAADCggICAAAAA==.Firetruck:BAAALAADCggICAAAAA==.Fizban:BAAALAADCggICAAAAA==.',Fl='Floofíe:BAAALAAECgQICgAAAA==.Flowerday:BAAALAADCggIEAAAAA==.',Fo='Foilsz:BAABLAAECoEVAAIFAAcI1R6ASADYAQAFAAcI1R6ASADYAQAAAA==.Foricky:BAAALAADCgcIBwAAAA==.Forthewild:BAAALAAECggIDgAAAA==.',Fr='Fròstmòurne:BAAALAAECgIIAgAAAA==.',Fu='Furiahal:BAAALAAECgQICgAAAA==.Fuzzibear:BAAALAAECgEIAQAAAA==.Fuzzimonk:BAAALAADCgQIBAAAAA==.',['Fá']='Fáfnir:BAAALAAECgYIBwAAAA==.Fáttpanda:BAAALAAECggIEQABLAAFFAUIDQAMAGwfAA==.',['Fí']='Fíresplash:BAAALAAECgYIBgABLAAFFAUIDQAMAGwfAA==.',Ge='Georgé:BAAALAADCgcIBwABLAADCggIGQAEAAAAAA==.',Gh='Ghanapriest:BAAALAAECgIIAgAAAA==.Ghostswed:BAAALAAECgEIAQAAAA==.Ghoulash:BAAALAAECgYIDgAAAA==.',Gn='Gnoom:BAAALAAECgYICgABLAAECgcIHgAVAEUkAA==.',Go='Goldigoddess:BAAALAAECgEIAQAAAA==.Gothevoker:BAAALAAECggICAAAAA==.',Ha='Harm:BAAALAAECgYIBwAAAA==.',Hc='Hcandersen:BAAALAADCgcIDgAAAA==.',He='Hellkeeper:BAABLAAECoEUAAIWAAgIiwc1mAAbAQAWAAgIiwc1mAAbAQAAAA==.Helneth:BAAALAADCggIHgABLAAECgcIHwATAKYiAA==.Hermanus:BAABLAAECoEgAAIVAAcIihNCFQDaAQAVAAcIihNCFQDaAQAAAA==.Heset:BAABLAAECoEVAAMXAAgIYh0cDwBJAgAXAAgIYh0cDwBJAgADAAEI+AxrQAArAAAAAA==.',Hi='Hikari:BAABLAAECoEfAAIIAAgIkhSJEgDmAQAIAAgIkhSJEgDmAQAAAA==.Hitzz:BAAALAAECggIEAAAAA==.',Ho='Holyenforcer:BAAALAADCgcIBwAAAA==.Holymonster:BAAALAAECgYIDwAAAA==.Hooklock:BAAALAADCgcIBwAAAA==.Horakel:BAABLAAECoEoAAIBAAgIKiO4EwAPAwABAAgIKiO4EwAPAwAAAA==.',Hu='Huntsekker:BAAALAAECgQIBQAAAA==.Hunturn:BAAALAADCggICAABLAAECgcIGQAUAAAQAA==.Huntärd:BAAALAADCgMIAwAAAA==.',Hy='Hybris:BAAALAAFFAIIAgAAAA==.',['Hé']='Hélléstrá:BAAALAAECggICAAAAA==.',If='Ifrita:BAABLAAECoEUAAIOAAYI+hLAJgA+AQAOAAYI+hLAJgA+AQAAAA==.',Il='Illarinn:BAAALAADCgMIBgAAAA==.Illuminatí:BAAALAADCgYICQABLAADCgcIBwAEAAAAAA==.Illuminnae:BAAALAADCggICAABLAAFFAMIBwAQAIkLAA==.Iltran:BAAALAAECgYIBgABLAAECggIFAAYAL0cAA==.',Im='Imawful:BAAALAADCgEIAQAAAA==.Imhere:BAAALAAECggICAAAAA==.Imterrible:BAAALAADCgMIAwAAAA==.',Ir='Irnbrü:BAAALAAECgYIBwAAAA==.',Is='Ishootthings:BAABLAAECoEkAAIQAAgIDwhvkABPAQAQAAgIDwhvkABPAQAAAA==.',Ja='Jayanthi:BAACLAAFFIEIAAIUAAMIWA5WFwC8AAAUAAMIWA5WFwC8AAAsAAQKgRsAAhQACAjkGGInAEsCABQACAjkGGInAEsCAAAA.Jaz:BAAALAADCggICAAAAA==.',Je='Jeezak:BAAALAADCggICAAAAA==.Jeezee:BAAALAADCggIDQAAAA==.Jellygum:BAAALAAECgQIBAAAAA==.',Jh='Jhun:BAAALAADCgYIAwAAAA==.',Jo='Joebiden:BAAALAAECgIIAgABLAAECggIIgAHAIQkAA==.',Ju='Juant:BAABLAAECoEcAAQZAAcILg5UOgBNAQAZAAcILg5UOgBNAQAGAAQIcggJIgC2AAAFAAQIHwSerwB/AAAAAA==.',Jy='Jyjiyi:BAAALAAECgIIAgAAAA==.',['Já']='Jáz:BAAALAADCgQIBAAAAA==.',Ka='Kaei:BAAALAAECgEIAQAAAA==.Kaelth:BAAALAADCgYIEgAAAA==.Kakaomælk:BAAALAADCgUIBQABLAAECggIJwABADwZAA==.Karsten:BAAALAADCggICgAAAA==.',Ke='Kebule:BAAALAAECggIAgAAAA==.Keethrax:BAAALAAECgMIBgAAAA==.Kelzo:BAAALAADCgcIBwABLAAECgIIAgAEAAAAAA==.',Ki='Killerfrozen:BAAALAAECgIIAgAAAA==.Killershot:BAAALAADCgYIBgAAAA==.Kitagawa:BAABLAAECoEYAAILAAgI5RyEHwCmAgALAAgI5RyEHwCmAgAAAA==.',Kr='Kram:BAAALAAECggIAwAAAA==.Krazay:BAABLAAECoEdAAIWAAcInQREpADvAAAWAAcInQREpADvAAAAAA==.Krispy:BAAALAAFFAQIBAABLAAFFAUIDAAJAIYSAA==.',Ku='Kuroichan:BAAALAAECgYIBgABLAAECggIHwAIAJIUAA==.',Kw='Kwoh:BAAALAADCggICAAAAA==.',['Kà']='Kàli:BAAALAADCggICQABLAAECgQICgAEAAAAAA==.',['Ké']='Kélorn:BAAALAAECgQIBQAAAA==.',La='Lalana:BAAALAADCgcIEQAAAA==.Lawr:BAAALAADCgcIBwAAAA==.',Le='Leahx:BAAALAAFFAIIAgAAAA==.Legendhusk:BAABLAAECoEUAAIOAAgIwhkSDwA8AgAOAAgIwhkSDwA8AgABLAAFFAYIDQACABYNAA==.Legionella:BAAALAADCgQIBwAAAA==.Legithusky:BAACLAAFFIENAAICAAYIFg2fBQDVAQACAAYIFg2fBQDVAQAsAAQKgSIAAwIACAj+ItoMABQDAAIACAj+ItoMABQDABQAAggJFtXdAH8AAAAA.',Li='Lion:BAABLAAECoEeAAIBAAgIKBnlOgBbAgABAAgIKBnlOgBbAgAAAA==.Liukasmuikku:BAAALAAECgYIDQABLAAECgcICgAEAAAAAA==.',Lo='Loftyy:BAAALAAECgYIDgABLAAECggIIQAQAJwhAA==.Logaan:BAABLAAECoEfAAIaAAcIthgVHADWAQAaAAcIthgVHADWAQAAAA==.Loogaan:BAAALAAECgYICgAAAA==.Lorfus:BAAALAAECgIIAgABLAAECggIHAABAFslAA==.Lorth:BAAALAADCgYIBgAAAA==.',Lu='Lunaria:BAAALAADCgYIBgABLAAECgYIEAAEAAAAAA==.Lutador:BAAALAAECgEIAQAAAA==.Luun:BAAALAAECgYICwAAAA==.Luxitedxx:BAAALAAECgYICQAAAA==.',Ly='Lyonsgldblnd:BAABLAAECoEUAAIbAAYIEhyWIQDmAQAbAAYIEhyWIQDmAQAAAA==.Lysyzfelwood:BAABLAAECoEaAAIHAAcIuyCAOwBCAgAHAAcIuyCAOwBCAgAAAA==.',Ma='Magda:BAAALAADCgYIBgAAAA==.Mahnaaz:BAAALAADCggICQAAAA==.Mailine:BAAALAAECgYIBgAAAA==.Makgora:BAAALAAECgUICwAAAA==.Mantus:BAAALAAECgMIAwAAAA==.Marathur:BAAALAAECgYIBgAAAA==.Marisan:BAABLAAECoEbAAILAAcIkAkFbgBtAQALAAcIkAkFbgBtAQAAAA==.Masien:BAAALAADCgcIBwABLAAECgcIHwAPAEokAA==.Maylora:BAAALAADCggICAAAAA==.Mazahs:BAABLAAECoEdAAIbAAcIbQ/SOQBfAQAbAAcIbQ/SOQBfAQAAAA==.Mazajaja:BAAALAADCgcIBwAAAA==.',Mc='Mcmac:BAAALAAECgcIDQAAAA==.Mcpats:BAABLAAECoEeAAIBAAcIDBP7dgDEAQABAAcIDBP7dgDEAQAAAA==.',Me='Mementomori:BAAALAAECgUIBQABLAAECggIKgMLAOYmAA==.Meowsforheal:BAAALAAFFAIIAgAAAA==.Meryn:BAABLAAECoEcAAMcAAYIAQ+XWgBFAQAcAAYIAQ+XWgBFAQAJAAUI4QNpbQCnAAAAAA==.Meso:BAAALAAECgEIAQAAAA==.Metamörph:BAAALAADCggIEgAAAA==.',Mi='Mibba:BAACLAAFFIEFAAIYAAMI4hSDFQDzAAAYAAMI4hSDFQDzAAAsAAQKgR0AAhgACAiFJIIIAEoDABgACAiFJIIIAEoDAAAA.Miko:BAAALAAECggICAAAAA==.Milixxy:BAABLAAECoEbAAIIAAcIzySuBQDxAgAIAAcIzySuBQDxAgAAAA==.Minasa:BAAALAAECgYIBgAAAA==.Minuer:BAAALAAECgQIBAAAAA==.Missiman:BAAALAADCgEIAQAAAA==.Mistresdíz:BAABLAAECoEWAAIKAAcIzRZECQAKAgAKAAcIzRZECQAKAgAAAA==.',Mo='Moonpants:BAAALAADCgYIBgABLAADCgcIBwAEAAAAAA==.Moonpantz:BAAALAADCgYICgABLAADCgcIBwAEAAAAAA==.',['Má']='Márin:BAAALAAECgYICQAAAA==.',['Må']='Månljus:BAAALAAECgEIAQAAAA==.',Na='Nakedlasagne:BAAALAADCggIDgABLAAECgYIEAAEAAAAAA==.Natur:BAACLAAFFIEPAAMdAAUI+BcWAwC5AQAdAAUI+BcWAwC5AQANAAIIlw8aEQCbAAAsAAQKgSsABA0ACAhVIXoLANgCAA0ABwicJHoLANgCAB0ABwjFH9IKAFQCAB4ABghMGhYJAKMBAAAA.Nazha:BAAALAADCggICAAAAA==.',Ne='Needdatsalt:BAAALAADCgEIAQAAAA==.',Ni='Nicolae:BAABLAAECoElAAIaAAgIVxENIwCbAQAaAAgIVxENIwCbAQAAAA==.',No='Noskillz:BAAALAADCgMIAwAAAA==.Novemberxii:BAAALAADCggICAAAAA==.',Nr='Nrgwayne:BAABLAAECoEWAAIQAAYI8w86lwBCAQAQAAYI8w86lwBCAQAAAA==.',Nu='Nutzella:BAAALAADCggIDgAAAA==.',Ny='Nyrrh:BAABLAAECoEaAAIHAAgIfhwoNQBaAgAHAAgIfhwoNQBaAgAAAA==.',Ob='Obamna:BAAALAAECgEIAQAAAA==.',Om='Omglolshadow:BAAALAADCgcIBwAAAA==.',Pa='Pallindra:BAAALAADCgcIBwAAAA==.Papamortem:BAAALAAECggIDwAAAA==.Paprikafox:BAABLAAECoEaAAIbAAYIKg1+PQBPAQAbAAYIKg1+PQBPAQAAAA==.Patsy:BAABLAAECoEiAAIQAAgIaBqMOgApAgAQAAgIaBqMOgApAgAAAA==.',Pe='Peeledbanana:BAAALAAECggIDgAAAA==.',Ph='Philelf:BAAALAAECgYIBgAAAA==.Phineas:BAABLAAECoEfAAIbAAcIXhopGgAdAgAbAAcIXhopGgAdAgAAAA==.',Po='Pooksi:BAABLAAECoEZAAIBAAgIvQxjhACqAQABAAgIvQxjhACqAQAAAA==.Popina:BAAALAAECgYIDAABLAAECggIHQAWAHceAA==.Porventi:BAABLAAECoEXAAILAAYISgg1iAAmAQALAAYISgg1iAAmAQAAAA==.',Pr='Priam:BAAALAAECgQICgAAAA==.Protadin:BAABLAAECoEcAAIBAAgIWyUGCwBDAwABAAgIWyUGCwBDAwAAAA==.Protego:BAAALAADCgYIBgAAAA==.',Ra='Radikalx:BAAALAAECgcIBwAAAA==.Rafilock:BAAALAAECgYICgAAAA==.Rangomoon:BAAALAADCgYIBgAAAA==.Rasha:BAAALAAECgcIDQAAAA==.Ravage:BAAALAAECgYIDwAAAA==.Raymist:BAAALAADCgUIBQABLAAECgcIIgALAIEZAA==.Razhonea:BAAALAADCggICAAAAA==.',Re='Restro:BAAALAAECgMIAwAAAA==.',Rh='Rhainebow:BAABLAAECoEZAAIfAAcIFiWtAgDZAgAfAAcIFiWtAgDZAgAAAA==.Rhainedance:BAAALAADCggIFAAAAA==.Rhan:BAAALAAECgUICwAAAA==.',Ri='Riptidegodx:BAAALAAECgYIBAABLAAFFAUIDAAJAIYSAA==.Rishko:BAAALAADCggIEAAAAA==.Rival:BAAALAADCggIDAAAAA==.',Ro='Rosemare:BAAALAADCgUIBQAAAA==.',Ru='Rubyi:BAAALAADCgcIDgAAAA==.Ruguwu:BAAALAADCggICAAAAA==.Runrig:BAAALAADCgcICQAAAA==.Rusmula:BAABLAAECoEcAAMgAAgItA10GQDVAQAgAAgItA10GQDVAQAYAAEIYgMGUgEfAAAAAA==.',Ry='Ryoko:BAAALAAECgMIAwAAAA==.',['Rá']='Ráyman:BAAALAADCggIDgABLAAECgcIIgALAIEZAA==.Ráymon:BAAALAAECgEIAQABLAAECgcIIgALAIEZAA==.Ráymón:BAABLAAECoEiAAILAAcIgRlwNwAnAgALAAcIgRlwNwAnAgAAAA==.',['Rì']='Rìléy:BAAALAADCgcIBwAAAA==.',['Rí']='Ríshko:BAAALAADCgcIBwAAAA==.',Sa='Saaz:BAAALAAECgcIEAAAAA==.Saerdnaa:BAAALAAECgYIEAAAAA==.Saggat:BAAALAAECgQICgAAAA==.Saltlover:BAAALAAECgYIBwAAAA==.Samistra:BAAALAADCggIFQAAAA==.Sanguellan:BAAALAADCgMIAwAAAA==.',Sc='Schindy:BAABLAAECoEmAAMTAAgIsCPuAQA6AwATAAgIsCPuAQA6AwABAAEIBwveMQE7AAAAAA==.',Sg='Sgèile:BAAALAAECgEIAQABLAAECggIJQADAIsXAA==.',Sh='Shabba:BAAALAAECgcIBwAAAA==.Shabbie:BAAALAADCgcIBwAAAA==.Shalaria:BAAALAAECgIIAgAAAA==.Shalbywalk:BAABLAAFFIEMAAMJAAUIhhJ7BgCWAQAJAAUIhhJ7BgCWAQAhAAMIDCRdAAAoAQAAAA==.Shally:BAAALAAECggIAQAAAA==.Shaloune:BAAALAADCgMIAwAAAA==.Shamansftw:BAABLAAECoEaAAMCAAgIXBzSHQCLAgACAAgIXBzSHQCLAgAUAAMIix0RngD9AAAAAA==.Shambanana:BAAALAAECgcIEgAAAA==.Shamiurn:BAABLAAECoEZAAIUAAcIABCRdwBSAQAUAAcIABCRdwBSAQAAAA==.Shandu:BAABLAAECoEeAAMVAAcIRSReCwBzAgAVAAYIXSReCwBzAgARAAII6CLPZQDLAAAAAA==.Sharkfury:BAACLAAFFIEIAAIFAAIIOxqeGgCqAAAFAAIIOxqeGgCqAAAsAAQKgTIAAgUACAiHJDwHAE4DAAUACAiHJDwHAE4DAAAA.Shelled:BAAALAAECgYICwAAAA==.Shenlong:BAAALAADCggICAAAAA==.Shnxz:BAAALAAECgYICgAAAA==.Shosànna:BAAALAAECgIIAgAAAA==.Shrikei:BAAALAADCggICAABLAAECgYIEAAEAAAAAA==.',Si='Sikser:BAAALAAECgMIAwAAAA==.Silvare:BAAALAADCggIGQAAAA==.Silvermage:BAAALAADCggIJwAAAA==.',Sk='Skogsbruden:BAAALAADCgQIBAAAAA==.',Sl='Slowly:BAAALAADCgIIAgAAAA==.Slunicko:BAAALAADCggIBQAAAA==.',Sn='Snarstucken:BAAALAADCgcIDQAAAA==.Snillida:BAAALAADCggICAABLAAECgYIEAAEAAAAAA==.',So='Solenne:BAABLAAECoEfAAMPAAcISiR1DgDgAgAPAAcISiR1DgDgAgAQAAEIWBor/ABJAAAAAA==.Solkan:BAAALAADCgYICwAAAA==.Sololeveling:BAAALAAFFAIIAgAAAA==.Sophie:BAAALAAECgYIBwAAAA==.Soupreme:BAABLAAFFIEHAAIWAAMIJxp/EgAhAQAWAAMIJxp/EgAhAQAAAA==.',Sp='Spark:BAAALAAECgMIAwAAAA==.Sparkplug:BAAALAADCgIIAgAAAA==.Spellora:BAAALAADCggIFAAAAA==.Spyrogos:BAABLAAECoEfAAIdAAgIVw+UFACyAQAdAAgIVw+UFACyAQAAAA==.',St='Stava:BAABLAAECoEaAAIPAAYIRyMNIQBDAgAPAAYIRyMNIQBDAgAAAA==.Stonesmasher:BAAALAAECgYIEAAAAA==.Stryike:BAAALAAECgMIBgAAAA==.Sturmfänger:BAACLAAFFIELAAMWAAQIBwROFgD/AAAWAAQIBwROFgD/AAAbAAIIiALYEgBlAAAsAAQKgSMAAxsACAgEGFIjANoBABYACAgXE6NNAPYBABsABwgWE1IjANoBAAAA.',Su='Sunderhowl:BAABLAAECoEcAAIgAAcI9habEwARAgAgAAcI9habEwARAgAAAA==.Suramarac:BAABLAAECoEdAAMWAAgIdx5sIAC1AgAWAAgIdx5sIAC1AgAbAAYIyg+qQgA4AQAAAA==.',Sw='Swaff:BAABLAAECoEXAAINAAcIjRZcIgDjAQANAAcIjRZcIgDjAQAAAA==.Swaffsie:BAAALAADCggICAAAAA==.',Sy='Sybilla:BAABLAAECoEdAAMiAAcIDSbWCADsAgAiAAcIDSbWCADsAgAjAAIIkxYQOAB7AAABLAAECgcIHgAVAEUkAA==.',['Sé']='Sékhmet:BAAALAAECgMIBAAAAA==.',['Sø']='Sødeida:BAAALAAECggIDAAAAA==.',Ta='Tahlin:BAAALAADCgYIBgAAAA==.Taladin:BAAALAADCgcICgAAAA==.Talrione:BAAALAADCggICAAAAA==.Tamiya:BAAALAAECgYIBgAAAA==.Tavin:BAAALAADCggICgABLAAECgYIEAAEAAAAAA==.',Te='Tevar:BAAALAADCgUIBwAAAA==.',Th='Tharaniel:BAABLAAECoEZAAIRAAcICRW5LQDXAQARAAcICRW5LQDXAQAAAA==.Tharwar:BAAALAADCgcIBwAAAA==.Thelithi:BAAALAADCggIHQABLAAFFAYIFAALAIsdAA==.Thgtuu:BAAALAADCggICAAAAA==.Thiena:BAAALAADCgYIEAAAAA==.Thoradin:BAAALAAECgMIBgAAAA==.Thorxx:BAAALAADCggIEAAAAA==.Thrawn:BAABLAAECoEfAAIBAAgIsRs8KAClAgABAAgIsRs8KAClAgAAAA==.Thrawneekaar:BAAALAAECgIIAgAAAA==.',Ti='Tigse:BAAALAADCggIFAAAAA==.Tin:BAABLAAECoEcAAIQAAgIJxVfVwDQAQAQAAgIJxVfVwDQAQAAAA==.Tinyshammy:BAAALAAECgMIAwAAAA==.Tinystab:BAAALAAECgQIBAAAAA==.Tinytracker:BAAALAADCgcIBwAAAA==.Tirilion:BAAALAADCgYIBgAAAA==.Tirius:BAABLAAECoEdAAIMAAYI3B8sFQAvAgAMAAYI3B8sFQAvAgABLAAFFAMICAAOAJwTAA==.Tirys:BAAALAADCggIDgABLAAECgcIHwATAKYiAA==.',To='Towox:BAAALAAECgQICgAAAA==.',Tr='Travar:BAAALAAECgYICwABLAAECggIHQAWAHceAA==.',Tu='Tupacshakur:BAAALAAECggICAABLAAFFAUIDQAMAGwfAA==.',Tw='Twiztednipz:BAAALAAECgIIAgAAAA==.',Tz='Tzien:BAAALAADCggIEQAAAA==.',Ud='Udder:BAAALAADCggICAAAAA==.',Va='Valentîne:BAAALAAECgYIDQAAAA==.Valfreja:BAABLAAECoEUAAIZAAYIyBR/MwBzAQAZAAYIyBR/MwBzAQAAAA==.Valyro:BAAALAADCggILQAAAA==.Vampizd:BAAALAADCgcIBgAAAA==.',Ve='Verntas:BAAALAAECgIIAgAAAA==.Vespin:BAAALAAECgEIAQAAAA==.',Vi='Vivong:BAAALAADCgcIBgAAAA==.',Vo='Voltigeuse:BAAALAAECgMIBwAAAA==.Voo:BAAALAADCggIEwAAAA==.',Vu='Vulpine:BAAALAADCgIIAgAAAA==.',Vv='Vvest:BAABLAAECoEUAAIHAAcI0xijUwD2AQAHAAcI0xijUwD2AQAAAA==.',Wa='Waroxeal:BAAALAAECgYIBgAAAA==.',Wh='Whittlers:BAAALAAECgcICwAAAA==.',Wi='Wickedwalker:BAABLAAECoEWAAMJAAcI9xhPKAAVAgAJAAcI9xhPKAAVAgAcAAMIlApNjACCAAAAAA==.Wida:BAABLAAECoEhAAILAAgIjA4eWgCmAQALAAgIjA4eWgCmAQAAAA==.',Wo='Wobert:BAAALAAECggICAAAAA==.Woodenchair:BAAALAADCgYIBwAAAA==.Wooladin:BAAALAADCggIDwAAAA==.Woolhead:BAAALAADCggICAAAAA==.Woolyish:BAABLAAECoEdAAIXAAcIoRd2HwB2AQAXAAcIoRd2HwB2AQAAAA==.',Xy='Xyphyr:BAABLAAECoEgAAIUAAcI1wmrmgADAQAUAAcI1wmrmgADAQAAAA==.',Yu='Yune:BAAALAAECgYIBgAAAA==.',Ze='Zenith:BAAALAADCggICAAAAA==.Zewei:BAAALAAECgYICwAAAA==.',['Zé']='Zérolove:BAAALAADCgMIAgAAAA==.',['Àn']='Àngh:BAAALAAECgQICgAAAA==.',['És']='És:BAAALAAECgMIAwAAAA==.',['Íl']='Ílluminati:BAAALAADCgUIBQABLAADCgcIBwAEAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end