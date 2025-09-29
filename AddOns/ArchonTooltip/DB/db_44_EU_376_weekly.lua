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
 local lookup = {'Priest-Holy','DemonHunter-Havoc','Unknown-Unknown','DeathKnight-Frost','Rogue-Assassination','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Protection','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Warrior-Protection','Druid-Feral','Hunter-BeastMastery','Rogue-Subtlety','Mage-Arcane','Shaman-Elemental','Evoker-Devastation','Hunter-Marksmanship','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Druid-Balance','Mage-Frost','Druid-Restoration','Druid-Guardian','Mage-Fire','Rogue-Outlaw','Hunter-Survival','Priest-Shadow','DemonHunter-Vengeance','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Preservation','Priest-Discipline',}; local provider = {region='EU',realm='LaCroisadeécarlate',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abd:BAAALAAECgQIBwAAAA==.Abelouss:BAAALAAECgQIBAAAAA==.Abeluss:BAAALAADCggICAAAAA==.Abëlus:BAAALAADCgEIAQAAAA==.',Ac='Acellân:BAAALAADCgcIBwAAAA==.',Ad='Adhir:BAAALAADCggIDgABLAAFFAIIBgABAK4RAA==.Adremalech:BAABLAAECoEZAAICAAYIphcsdwCqAQACAAYIphcsdwCqAQAAAA==.',Ah='Ahestrasza:BAAALAADCggICAABLAAECgYIJwADAAAAAQ==.',Ai='Aimable:BAAALAAECgIIBAAAAA==.',Al='Albis:BAAALAADCgcIBwAAAA==.Alekså:BAAALAAECgYICQABLAADCgQIBAADAAAAAA==.Alfötracy:BAAALAAECgEIAQAAAA==.Alkknight:BAABLAAECoEVAAIEAAcIXBUddQDXAQAEAAcIXBUddQDXAQAAAA==.Alkpaladin:BAAALAAECgIIAgABLAAECgcIFQAEAFwVAA==.Alkrogue:BAABLAAECoEYAAIFAAYIPBkoLQCqAQAFAAYIPBkoLQCqAQABLAAECgcIFQAEAFwVAA==.Alsynea:BAABLAAECoEbAAIGAAgICB54CwCkAgAGAAgICB54CwCkAgAAAA==.Alysaïa:BAABLAAECoEcAAQHAAgI8A/SGwD+AQAHAAgI8A/SGwD+AQAIAAYIUAPJHADxAAAJAAIIIwvTwwBvAAAAAA==.Alïss:BAAALAAECgMIBAAAAA==.',An='Anamelorn:BAAALAAECgcIBwAAAA==.Andariel:BAAALAAECgUIBgAAAA==.Andariyel:BAAALAAECgYIBgAAAA==.Andoros:BAAALAAECgUIBQAAAA==.Anwynn:BAAALAAECgQICgAAAA==.Anwÿnn:BAAALAADCgEIAQAAAA==.Anïlya:BAAALAADCgcIBwAAAA==.',Ar='Arelline:BAACLAAFFIEbAAIKAAYInBsMAQAJAgAKAAYInBsMAQAJAgAsAAQKgSwAAgoACAg+JWsCAFkDAAoACAg+JWsCAFkDAAAA.Arifaeapo:BAAALAADCgQIBAAAAA==.Arius:BAAALAADCgQIBAAAAA==.Arkayl:BAAALAAECgMIAwAAAA==.Arksham:BAABLAAECoEtAAMLAAgI7hSEPwD4AQALAAgI7hSEPwD4AQAMAAQIjQsAAAAAAAAAAA==.Artipal:BAABLAAECoEfAAINAAcI5xICiACrAQANAAcI5xICiACrAQAAAA==.',As='Ascavyr:BAAALAADCggIFgAAAA==.Aseiah:BAAALAADCggICAABLAAFFAIIBgABAK4RAA==.Asûne:BAAALAADCggICAAAAA==.',At='Ataria:BAAALAADCggIDQAAAA==.Atekovoo:BAAALAADCggICQAAAA==.',Au='Auric:BAAALAADCggIDgAAAA==.',Av='Avadar:BAAALAAECgYICAAAAA==.',Aw='Awarnach:BAAALAADCggICAAAAA==.',Az='Azymondias:BAAALAAECgUIBQAAAA==.Azyris:BAABLAAECoEXAAIOAAcIGxacKgCzAQAOAAcIGxacKgCzAQAAAA==.',Ba='Balarog:BAAALAAFFAEIAQAAAA==.Barbaroze:BAAALAADCggICwABLAADCgcIDQADAAAAAA==.Barbouc:BAAALAADCgcIEQABLAAECgMIAwADAAAAAA==.',Be='Beastabber:BAACLAAFFIEPAAIPAAMIcCQBAwBBAQAPAAMIcCQBAwBBAQAsAAQKgSMAAg8ACAhhJZcBAFwDAA8ACAhhJZcBAFwDAAAA.Beerus:BAAALAADCgYIBgAAAA==.Belennos:BAAALAADCggIEwAAAA==.Belhan:BAAALAAECggIDgABLAAECggIEQADAAAAAA==.Belhian:BAAALAAECggIEQAAAA==.Benii:BAABLAAECoEcAAMKAAgI+g7CKwBmAQAKAAcIYQ7CKwBmAQAGAAgIggPlPgAoAQAAAA==.',Bi='Bianco:BAABLAAECoEaAAIQAAYIDhW4hgBwAQAQAAYIDhW4hgBwAQAAAA==.',Bl='Bloodrops:BAAALAADCggIDwABLAAECggIGQARALMXAA==.Bloodshark:BAABLAAECoEWAAIGAAcIiw9qMQB0AQAGAAcIiw9qMQB0AQAAAA==.Blubibulga:BAABLAAECoEcAAMHAAcI/w5GSQAmAQAJAAYIMQwHfwBJAQAHAAcILw1GSQAmAQAAAA==.',Bo='Bodwick:BAAALAAECgYICwAAAA==.Bouilloncube:BAACLAAFFIEIAAILAAIIVCUZEwDTAAALAAIIVCUZEwDTAAAsAAQKgSAAAgsACAjgImIPANcCAAsACAjgImIPANcCAAAA.Bouillonrond:BAAALAADCgIIAgABLAAFFAIICAALAFQlAA==.Bouledefuri:BAAALAADCgcIDQAAAA==.Bouletos:BAAALAAECgEIAQAAAA==.',Br='Brucius:BAABLAAECoEbAAISAAgI6hkgNABdAgASAAgI6hkgNABdAgAAAA==.Brïdges:BAAALAAECgcIBwABLAAECggIKAAOAEodAA==.',Bu='Bullybob:BAAALAAFFAIIBAAAAA==.',Ch='Chamclya:BAACLAAFFIEaAAMLAAYI8h8bAQBIAgALAAYI8h8bAQBIAgATAAUI/R41BQDtAQAsAAQKgS0AAxMACAiWJlMBAIoDABMACAiWJlMBAIoDAAsABwguHCBEAOkBAAAA.Chamzozor:BAAALAADCggICAAAAA==.Chibross:BAAALAADCggICAAAAA==.Chromo:BAAALAAECgYIDAAAAA==.Chrysalis:BAAALAADCgUIBQAAAA==.',Cl='Clang:BAAALAAECggIAwAAAA==.Clöé:BAABLAAECoEYAAMIAAYIbBiwDgCqAQAIAAYIWhawDgCqAQAJAAYIbRPapgDQAAAAAA==.',Co='Coldscale:BAABLAAECoEoAAIUAAgIqCNoBAA/AwAUAAgIqCNoBAA/AwAAAA==.Colorioz:BAACLAAFFIEOAAIBAAQI8hbiCABQAQABAAQI8hbiCABQAQAsAAQKgSsAAgEACAh2Ic8MAO8CAAEACAh2Ic8MAO8CAAAA.',Cp='Cpthook:BAAALAAECgEIAQAAAA==.Cptobvious:BAAALAAECgYIDwAAAA==.',Cr='Crystä:BAACLAAFFIEYAAMQAAYIahXFBADcAQAQAAYIahXFBADcAQAVAAQIdAbQDADiAAAsAAQKgTAAAxAACAgBJH8MAB0DABAACAimI38MAB0DABUACAi0GbsiAD0CAAAA.Crømãc:BAAALAADCgcIBwABLAAECgYIDQADAAAAAA==.',['Cé']='Céno:BAAALAAECggIEAAAAA==.',Da='Dalakjr:BAABLAAECoEZAAICAAcIfRsAUAAIAgACAAcIfRsAUAAIAgAAAA==.Dalakz:BAAALAAFFAIIAgAAAA==.Danïaleth:BAACLAAFFIEaAAMJAAcI/h1JAQCjAgAJAAcI/h1JAQCjAgAHAAEIYR8KIQBQAAAsAAQKgSEABAkACAiDJu4DAG0DAAkACAhVJu4DAG0DAAgABgjzHpwJAAMCAAcAAwiwFaFcAM4AAAAA.Darkh:BAAALAAECgMIAwABLAAECggILQALAO4UAA==.Dartt:BAABLAAECoEiAAMWAAcI+RV7JQCiAQAWAAYIghh7JQCiAQAXAAcINwc3MQDEAAAAAA==.',De='Deamonslayer:BAAALAADCggIDgABLAAECggIKAAUAKgjAA==.Deina:BAAALAAECgcIEgAAAA==.Dekuhunter:BAAALAADCgUICgABLAAECgYIDgADAAAAAA==.Delmort:BAAALAADCggIEAAAAA==.Denne:BAAALAAECgMIBgAAAA==.Destiny:BAAALAAECgIIAgAAAA==.Destinÿ:BAABLAAECoEZAAISAAcIKR1KSAAOAgASAAcIKR1KSAAOAgAAAA==.',Di='Diamare:BAAALAADCgcICAAAAA==.Diether:BAABLAAECoEfAAIBAAYIhAnibgAJAQABAAYIhAnibgAJAQAAAA==.Dink:BAAALAADCgcIDAAAAA==.',Dk='Dklqué:BAAALAAECgMIAwAAAA==.',Do='Dogui:BAABLAAECoEZAAILAAYIIhM1qwDtAAALAAYIIhM1qwDtAAAAAA==.Domastoc:BAAALAAECgcICQABLAAECggIHAAYAGwYAA==.',Dr='Dragoniste:BAAALAAECgMIAwAAAA==.Dromar:BAACLAAFFIEOAAIZAAUIuiEkBQD4AQAZAAUIuiEkBQD4AQAsAAQKgTYAAxkACAh+JnMEAGgDABkACAh+JnMEAGgDABoABghEJRgHAG4CAAAA.Drustan:BAABLAAECoEiAAIOAAcIVRJFMgCFAQAOAAcIVRJFMgCFAQAAAA==.',Dz='Dzertik:BAABLAAECoEWAAISAAYIKCDVRAAbAgASAAYIKCDVRAAbAgAAAA==.',['Dé']='Déku:BAAALAADCgUIBwABLAAECgYIDgADAAAAAA==.Dékû:BAAALAAECgEIAQABLAAECgYIDgADAAAAAA==.Dékûpriest:BAAALAADCgcIBwAAAA==.Délandra:BAABLAAECoEoAAMTAAgIuR1JFwDBAgATAAgIuR1JFwDBAgALAAIIyQUAAAAAAAAAAA==.',Ed='Edgy:BAAALAAECgcIDgAAAA==.Edrahil:BAAALAAECgYIDAAAAA==.',Ek='Ekan:BAAALAAECgMIAwAAAA==.',El='Elboukk:BAAALAAECgMIAwAAAA==.Eldragogol:BAACLAAFFIEdAAQJAAYIOh4gBwAEAgAJAAYIOh4gBwAEAgAHAAIILBHREACbAAAIAAEIZh0gBgBMAAAsAAQKgSkABAkACAgEJjoHAE8DAAkACAilJToHAE8DAAcABQhzIWknALkBAAgABggcFLEPAJkBAAAA.Eldrâ:BAAALAAECgYIEQAAAA==.Elenthus:BAAALAAECgYICgAAAA==.Elhìn:BAAALAAECgUICQABLAAFFAIICwASAJ0fAA==.Elihn:BAACLAAFFIELAAISAAIInR9FJQC0AAASAAIInR9FJQC0AAAsAAQKgSgAAhIABggHJccxAGgCABIABggHJccxAGgCAAAA.Elnéas:BAAALAAECgYICgAAAA==.Elrodk:BAAALAADCggIDgAAAA==.Elsiom:BAAALAADCgcIBwAAAA==.Elyvoker:BAABLAAECoEdAAMUAAcIfxidJQDPAQAUAAcIfxidJQDPAQAbAAQIgA+LDwD0AAAAAA==.Elëdhwën:BAABLAAECoEVAAIcAAYIEBAaUQA5AQAcAAYIEBAaUQA5AQAAAA==.',En='Enitonora:BAABLAAECoErAAIdAAcIdBzJHAAOAgAdAAcIdBzJHAAOAgAAAA==.Enitonòra:BAAALAADCgMIAwAAAA==.',Er='Eresarn:BAAALAAECgYIBgAAAA==.',Es='Escarcha:BAABLAAECoEiAAIeAAcIExwjKgAPAgAeAAcIExwjKgAPAgAAAA==.Estesia:BAAALAAECgUIBQAAAA==.',Et='Etania:BAAALAADCgMIBQAAAA==.',Ev='Evhen:BAABLAAECoEiAAIfAAgIBSJ+AgAOAwAfAAgIBSJ+AgAOAwAAAA==.Evokyse:BAAALAAECggICAAAAA==.',Fa='Facepàlm:BAEALAADCggIFgABLAAECgcIIgAFADYbAA==.Faellyanne:BAACLAAFFIEbAAMSAAYIjiAYBgAEAgASAAUI1B8YBgAEAgAgAAEILyTYBQBrAAAsAAQKgSgAAxIACAgAJqYEAGIDABIACAgAJqYEAGIDACAAAQivH3gYAFEAAAAA.Fakania:BAAALAAECgYICAAAAA==.Fawkkes:BAABLAAECoEXAAMFAAcIqR7gGAA/AgAFAAcIqR7gGAA/AgARAAEIcQ0rRAA0AAAAAA==.',Fe='Feamago:BAACLAAFFIERAAISAAUIyBfxCgDGAQASAAUIyBfxCgDGAQAsAAQKgTMAAhIACAgyJTsHAE0DABIACAgyJTsHAE0DAAAA.',Fi='Filsae:BAAALAAECgYIDwAAAA==.',Fl='Fléchette:BAAALAAECgIIAgAAAA==.',Ga='Gaambit:BAABLAAECoEVAAMIAAYIqQ20FwAtAQAIAAUIbA+0FwAtAQAHAAEI3AQYiwAwAAAAAA==.Gabiru:BAABLAAECoEUAAMUAAYIhwj7RADzAAAUAAYI9AT7RADzAAAbAAYISwgAAAAAAAABLAAECggIFQAcALEVAA==.Galathil:BAAALAAECgYICAAAAA==.Galaxciel:BAAALAAECgUIBAAAAA==.Galazare:BAABLAAECoEcAAIPAAcITx7wDABbAgAPAAcITx7wDABbAgAAAA==.Galz:BAAALAAECgIIAgAAAA==.Gandâlf:BAAALAAECgYIDgAAAA==.',Ge='Genovha:BAAALAAECgYIBgABLAAECgcIGQASACkdAA==.',Gh='Ghand:BAAALAAECgcIDQABLAAFFAIIBgABAK4RAA==.',Gl='Glargh:BAABLAAECoEcAAMHAAgImCQ7DQCDAgAHAAYIqSQ7DQCDAgAIAAYIfSIBBwBAAgAAAA==.',Go='Gouki:BAABLAAECoEWAAIVAAcIWRgGLgD3AQAVAAcIWRgGLgD3AQAAAA==.Gouteça:BAAALAAECgEIAQAAAA==.',Gr='Grandpas:BAAALAADCgYIBgAAAA==.Gronion:BAAALAAECgcICQAAAA==.Grumpy:BAAALAAECgIIAgAAAA==.',Ha='Habanera:BAAALAAECgcIEwAAAA==.Hamaytiste:BAAALAADCgYIDAAAAA==.Hantman:BAACLAAFFIEIAAMhAAMIfRW0AgCsAAAhAAIIlh60AgCsAAAFAAIInAwaEgCkAAAsAAQKgRcAAyEACAjcG88DAJcCACEACAjcG88DAJcCAAUAAQjFAxJlADYAAAAA.Harno:BAABLAAECoEaAAIiAAcIzBCiCgDaAQAiAAcIzBCiCgDaAQAAAA==.',He='Herrellius:BAAALAAECgYIEQAAAA==.',Hi='Hibouh:BAAALAADCggIFgAAAA==.Hitagi:BAABLAAECoEiAAINAAgIuSRKDQA3AwANAAgIuSRKDQA3AwAAAA==.',Ho='Horochii:BAABLAAECoEfAAIQAAYIhSQnMgBTAgAQAAYIhSQnMgBTAgAAAA==.',Hu='Huminob:BAACLAAFFIEFAAIUAAIIYxpCEACmAAAUAAIIYxpCEACmAAAsAAQKgRsAAhQACAiMHqQTAHkCABQACAiMHqQTAHkCAAAA.',['Hä']='Häçéæ:BAAALAAECgYIDQAAAA==.',['Hé']='Hélèonor:BAAALAAFFAMIAgAAAA==.',['Hö']='Höyhen:BAAALAADCggICQAAAA==.',Ic='Icekrim:BAAALAAECgYIDAAAAA==.',Ig='Igdan:BAAALAAECgcICQAAAA==.',Il='Ilidark:BAAALAAECgcIDQAAAA==.Illsira:BAABLAAECoEZAAMfAAcItw9sGQANAQAfAAYIZw1sGQANAQAeAAQIjhGrhADNAAAAAA==.',Im='Iman:BAAALAAECgIIAgAAAA==.',Ir='Iriz:BAAALAADCgIIAgAAAA==.Ironerf:BAAALAADCgcICgAAAA==.',It='Itorabbi:BAAALAAECgcIBwAAAA==.',Ja='Jaesthènis:BAABLAAECoEfAAIJAAgIQx+9GwDEAgAJAAgIQx+9GwDEAgAAAA==.Jassen:BAAALAAECgEIAQAAAA==.',Jc='Jcvð:BAAALAAECgYIDAAAAA==.',Ji='Jibile:BAAALAADCggICQAAAA==.',Ju='Jujunull:BAACLAAFFIEMAAIeAAMIcCNWBwA2AQAeAAMIcCNWBwA2AQAsAAQKgSUABB4ACAhRJJIIAAEDAB4ACAhRJJIIAAEDAA8ABAjZFawoABMBABwAAQiJCB6PADMAAAAA.Junia:BAAALAAECgMIAwAAAA==.',Jy='Jynn:BAAALAADCgEIAQAAAA==.',Ka='Kaahaly:BAABLAAECoEiAAMBAAgIIh98DwDWAgABAAgIIh98DwDWAgAjAAUIug5lXAAZAQAAAA==.Kaledar:BAAALAAECgQIBAABLAAECgYIBgADAAAAAA==.Kaliri:BAAALAADCggICAAAAA==.Kamoraz:BAAALAADCggICAAAAA==.Kamui:BAAALAADCgMIAwAAAA==.Karkadroodof:BAAALAAECgcIDAAAAA==.Karnicou:BAAALAADCggIEAABLAAECgcIGgAiAMwQAA==.Kazuki:BAAALAADCgYICQAAAA==.Kaëdinia:BAAALAADCgcIBwAAAA==.',Ke='Keibou:BAACLAAFFIEMAAIGAAMIbB88CAAPAQAGAAMIbB88CAAPAQAsAAQKgTAAAgYACAg3HvsLAJ4CAAYACAg3HvsLAJ4CAAAA.Ketebesedd:BAAALAAECgcIDQAAAA==.',Kh='Khaltarion:BAAALAAECgQIDQAAAA==.',Ko='Koringar:BAACLAAFFIEYAAIZAAYI7SCLAQBuAgAZAAYI7SCLAQBuAgAsAAQKgTAAAhkACAiKJoQCAHwDABkACAiKJoQCAHwDAAAA.',Kr='Krosus:BAAALAADCgUICAAAAA==.Krønik:BAAALAAECgUIBQAAAA==.',Ku='Kurosagi:BAAALAADCggIEwABLAAECgYIGAAIAGwYAA==.',Kw='Kwacha:BAABLAAECoEUAAIeAAgIkhbWKQAQAgAeAAgIkhbWKQAQAgAAAA==.',Ky='Kyzer:BAAALAAECgEIAQAAAA==.',['Kè']='Kèlls:BAAALAAECgYIBgAAAA==.',['Kø']='Køruptiøn:BAAALAAECgUIBwAAAA==.',La='Laboulaite:BAAALAAECgIIAgAAAA==.Laenihunt:BAABLAAECoEhAAIVAAgITiT7CwD5AgAVAAgITiT7CwD5AgAAAA==.Lankaï:BAABLAAECoEXAAIJAAgIRRceOAAtAgAJAAgIRRceOAAtAgAAAA==.Larililarila:BAAALAADCgcIBwAAAA==.Laryfishrman:BAAALAAECgYIDgAAAA==.Layñie:BAACLAAFFIEVAAMcAAYI/R0iAQBLAgAcAAYI/R0iAQBLAgAPAAQIbhD5AgBEAQAsAAQKgSwABR8ACAi6JFMDAOcCAB8ACAifH1MDAOcCABwACAjJI5IPANICAA8ABwitHz0NAFYCAB4AAwipGPuAANcAAAAA.',Le='Lendri:BAAALAADCggICAABLAAECgQIDQADAAAAAA==.Leyth:BAACLAAFFIEGAAIBAAIIrhHsIACXAAABAAIIrhHsIACXAAAsAAQKgSEAAgEACAj2HWwNAOoCAAEACAj2HWwNAOoCAAAA.',Li='Lidenbrock:BAAALAAECgEIAgAAAA==.Ligthbringer:BAABLAAECoEgAAINAAgIHxQ0ZQDwAQANAAgIHxQ0ZQDwAQAAAA==.Lineelith:BAAALAAFFAIIAgABLAAFFAcIGgAJAP4dAA==.',Lo='Loonies:BAABLAAECoEVAAITAAgIZR8xFwDCAgATAAgIZR8xFwDCAgAAAA==.Loonwolf:BAAALAAECgQIBwAAAA==.',Lu='Lurik:BAAALAAECgcIEAAAAA==.Luthielle:BAAALAAECgQIBgAAAA==.',Ly='Lysna:BAABLAAECoEfAAMQAAgIZRH+fgCAAQAQAAcI2w/+fgCAAQAVAAYIVQtxaQAEAQAAAA==.Lyxiane:BAAALAAECgYICQABLAAFFAcIGgAJAP4dAA==.',['Lå']='Låyñie:BAAALAADCggICAABLAAFFAYIFQAcAP0dAA==.',['Lû']='Lûcian:BAAALAAECgYIDQAAAA==.',Ma='Mahesha:BAAALAADCggICAAAAA==.Malatiki:BAAALAADCgYIBgAAAA==.Malentir:BAAALAADCggICAAAAA==.Manubrium:BAABLAAECoEXAAIjAAcItxjWKAAYAgAjAAcItxjWKAAYAgAAAA==.Marsmara:BAABLAAECoEgAAIEAAcIjhwRSgA6AgAEAAcIjhwRSgA6AgAAAA==.Marîkâ:BAAALAAECgYIDwAAAA==.Maseidr:BAAALAAECggIEwAAAA==.Maveilatitan:BAAALAADCggIEwABLAAECgMIAwADAAAAAA==.Maënor:BAABLAAECoEdAAIaAAgIRBe3CABCAgAaAAgIRBe3CABCAgAAAA==.',Me='Meitav:BAAALAAECgMIAwAAAA==.Mezankor:BAABLAAECoEeAAIeAAcILxhCLwD1AQAeAAcILxhCLwD1AQAAAA==.',Mi='Mikasasept:BAAALAAECggIDQAAAA==.Mimita:BAABLAAECoEXAAIVAAcIfQhkZAAVAQAVAAcIfQhkZAAVAQAAAA==.Mirad:BAABLAAECoEcAAITAAgI5xksIwBuAgATAAgI5xksIwBuAgAAAA==.Mirron:BAAALAAECgQIBQAAAA==.Miâ:BAAALAADCgEIAQAAAA==.',Mo='Moki:BAABLAAECoEXAAIkAAYIpRN6KgAsAQAkAAYIpRN6KgAsAQAAAA==.Monkeybeam:BAAALAAECgMIAwAAAA==.Monklya:BAAALAAECgcIEQABLAAFFAYIGgALAPIfAA==.',Mu='Muyo:BAAALAAECgcIDwAAAA==.',My='Mystiphia:BAAALAAECgYIDwAAAA==.',['Mâ']='Mâkâ:BAABLAAECoEbAAILAAgI9RktJwBSAgALAAgI9RktJwBSAgAAAA==.Mârika:BAAALAAECgcIEAAAAA==.',['Mû']='Mûtenroshi:BAABLAAECoEgAAMlAAgIFh1SCgCbAgAlAAgImRpSCgCbAgAmAAMI2iMHJwAAAQAAAA==.',Na='Naedra:BAAALAADCgIIAgAAAA==.Nainlando:BAAALAAECgYIDQABLAAECggIEQADAAAAAA==.Nairf:BAACLAAFFIEXAAITAAYIcR7CAgA4AgATAAYIcR7CAgA4AgAsAAQKgSgAAhMACAiNJnsBAIgDABMACAiNJnsBAIgDAAAA.Nairøx:BAAALAAECgYIDwAAAA==.Nastyy:BAACLAAFFIEYAAIQAAYIzhd3BADjAQAQAAYIzhd3BADjAQAsAAQKgSgAAxAACAi+IygWAN8CABAACAi+IygWAN8CABUABwgFFWg6ALcBAAAA.',Ne='Nelmara:BAAALAAECgYIBgABLAAECggIGQAXALQfAA==.Nelmy:BAABLAAECoEZAAIXAAgItB8RCADJAgAXAAgItB8RCADJAgAAAA==.Nemia:BAAALAADCgIIAgAAAA==.Nezaa:BAAALAADCgYIBgAAAA==.',Ng='Nguyen:BAAALAADCggIBwAAAA==.',Ni='Nibelheimr:BAABLAAECoEUAAQZAAcIwxzuOQAbAgAZAAcIdhnuOQAbAgAaAAMIGRiVIQDFAAAOAAYI/BzrdwA2AAAAAA==.Nibraisheimr:BAAALAADCggICwAAAA==.Nigthwing:BAAALAADCggIEAAAAA==.Nigun:BAAALAADCgcIBwAAAA==.Niline:BAAALAADCgcIBwAAAA==.Ninote:BAAALAADCggICgAAAA==.Nitrojunkie:BAAALAAECgYICgAAAA==.',No='Nobsham:BAAALAAECgQIAwABLAAECgQIBgADAAAAAA==.Nokomis:BAAALAADCggICAABLAAECgQIBQADAAAAAA==.Norigosa:BAABLAAECoEXAAMUAAcIrAhRNQBgAQAUAAcIrAhRNQBgAQAbAAIISgOFFQBGAAAAAA==.Nouht:BAAALAADCgUIBQAAAA==.',Nu='Nuka:BAAALAAECgYIBwAAAA==.',Ny='Nyna:BAAALAAECgEIAQAAAA==.Nyrven:BAABLAAECoEUAAInAAgIKxLGEgDTAQAnAAgIKxLGEgDTAQAAAA==.Nyë:BAAALAADCggIDQAAAA==.',['Nø']='Nøløsham:BAAALAAECgUICAABLAAECggIHQAeAOYkAA==.',Ob='Obak:BAABLAAECoEcAAIYAAgIbBj5DwBDAgAYAAgIbBj5DwBDAgAAAA==.',Ol='Oliu:BAABLAAECoEbAAMIAAcI3Bk5EgB0AQAJAAcIuxdLRwDvAQAIAAUIHxk5EgB0AQAAAA==.',Om='Omni:BAAALAAECgUIBQAAAA==.',Or='Orloom:BAAALAADCggIDwAAAA==.',Ou='Ouiskydye:BAAALAAECgYIDAABLAAECgYIDgADAAAAAA==.',Pa='Pajeh:BAABLAAECoEZAAIBAAcI/QvxWQBNAQABAAcI/QvxWQBNAQAAAA==.Paldrai:BAAALAAECgEIAQAAAA==.Palucheur:BAAALAADCgMIAwAAAA==.Pandarbare:BAAALAAFFAEIAQAAAA==.Pantherevok:BAAALAADCggIDQABLAAECgYICAADAAAAAA==.Parrish:BAAALAADCgcIDQAAAA==.Parsifal:BAAALAAECgMIBgAAAA==.Partialymoon:BAAALAADCgcIBwAAAA==.',Pe='Penuts:BAABLAAECoEWAAINAAcIKxObbwDaAQANAAcIKxObbwDaAQAAAA==.Perihan:BAABLAAECoEcAAIBAAcIWRmeLQAOAgABAAcIWRmeLQAOAgAAAA==.Persélock:BAAALAAFFAYIAgAAAA==.Persépriest:BAAALAADCggICAABLAAFFAYIAgADAAAAAA==.',Pi='Piksza:BAAALAADCgEIAQAAAA==.Pimlarou:BAAALAAECgMIAwAAAA==.',Pl='Pléospouge:BAAALAAECgMIAwAAAA==.',Po='Poilo:BAAALAADCgIIAgABLAAFFAMIBwAIAG0UAA==.Poilochon:BAACLAAFFIEHAAIIAAMIbRQgAQACAQAIAAMIbRQgAQACAQAsAAQKgUAAAggACAgwJRQBAEwDAAgACAgwJRQBAEwDAAAA.Polauchon:BAAALAADCggICQABLAAFFAMIBwAIAG0UAA==.',Pt='Pticaillou:BAAALAAECgIIBAAAAA==.Ptigro:BAAALAADCgUIBQAAAA==.Ptitekanine:BAAALAADCgcIBwAAAA==.',Py='Pyrite:BAAALAADCgMIAwAAAA==.Pyxi:BAEBLAAECoEiAAIFAAcINhs8HwAHAgAFAAcINhs8HwAHAgAAAA==.',['Pø']='Pøupøugne:BAAALAAECgcIDAAAAA==.',Qu='Quinthessa:BAAALAADCgcIBwAAAA==.',Ra='Ragnâr:BAAALAAECggICwAAAA==.Rahan:BAAALAADCggICAABLAAECgcIEgADAAAAAA==.Ranaka:BAACLAAFFIEbAAMJAAYI5SE0AwBaAgAJAAYI5SE0AwBaAgAHAAIIDxwaCAC1AAAsAAQKgTAABAkACAjgJoAAAJkDAAkACAjDJoAAAJkDAAgABAjuIGQTAGQBAAcAAgh8JE9nAKIAAAAA.Rappsnitch:BAAALAADCggIDQAAAA==.Rarespawn:BAABLAAECoEZAAICAAcIjRuxOABUAgACAAcIjRuxOABUAgAAAA==.Rayden:BAABLAAECoEkAAIFAAgIxSHLCADuAgAFAAgIxSHLCADuAgAAAA==.Razuvious:BAAALAAECgEIAQAAAA==.',Re='Reds:BAABLAAECoEVAAMJAAYIbRQjaACFAQAJAAYIbRQjaACFAQAIAAEI+QuwPQA0AAAAAA==.Rembie:BAABLAAECoEYAAIFAAcItw44LwCeAQAFAAcItw44LwCeAQAAAA==.',Rh='Rheya:BAAALAAECgYIBgAAAA==.Rheyf:BAAALAADCgcIBwAAAA==.Rhum:BAAALAAECgUIBgAAAA==.',Ri='Rireelfique:BAABLAAECoEaAAQFAAgIQAs4NwBwAQAFAAcIbgs4NwBwAQARAAQIgwpvMADPAAAhAAEIEgaVHAAoAAAAAA==.',Ro='Rorschach:BAAALAAFFAIIBAABLAAFFAIIBQAeAI4iAA==.Rorschiasse:BAACLAAFFIEFAAIeAAIIjiLPEADGAAAeAAIIjiLPEADGAAAsAAQKgR4AAh4ACAhAJmcBAGkDAB4ACAhAJmcBAGkDAAAA.',Ru='Rui:BAAALAADCgcIBwAAAA==.',Ry='Rynne:BAAALAADCggIEwAAAA==.',['Rï']='Rïeka:BAABLAAECoEfAAIeAAcI5CGTFgCDAgAeAAcI5CGTFgCDAgAAAA==.',['Rø']='Røn:BAAALAADCgUIDwAAAA==.',Sa='Sabato:BAAALAAECgQIBAAAAA==.Sabôt:BAABLAAECoEXAAMVAAcI1R5EIABOAgAVAAcI1R5EIABOAgAQAAIIiQq5AQFaAAAAAA==.Saeka:BAAALAADCgcIBwAAAA==.Sandre:BAAALAAECgEIAQAAAA==.Sangrina:BAAALAAECgMIBQAAAA==.Sarakos:BAAALAAECgYIDQAAAA==.Saykaptain:BAAALAAECgQIBQAAAA==.',Sc='Scrib:BAAALAADCggIEAAAAA==.',Se='Sealennrv:BAABLAAECoE0AAMlAAgI0R35DgBQAgAlAAgIBxv5DgBQAgAEAAgIuxpoSgA5AgAAAA==.Sedu:BAAALAAECgMIBAAAAA==.Sekhret:BAACLAAFFIEIAAMHAAQIVBqUAgAAAQAHAAMIChqUAgAAAQAJAAEIMxuMPQBdAAAsAAQKgSoAAwcACAjBIoIIAMMCAAcABwhNJIIIAMMCAAkABAhsHfd1AGEBAAAA.Sethix:BAABLAAECoEWAAILAAgITQXftQDYAAALAAgITQXftQDYAAAAAA==.',Sh='Sharolix:BAABLAAECoEXAAMeAAYIChoePAC5AQAeAAYIChoePAC5AQAcAAIISwW4hwBIAAAAAA==.Shhira:BAAALAADCgUICQAAAA==.Shhirayuki:BAAALAADCgMIAwAAAA==.Sholla:BAAALAADCgUIBQAAAA==.Shêem:BAAALAAECgIIAgAAAA==.Shïva:BAAALAAECgEIAQAAAA==.',Si='Sidon:BAAALAAECgYICgAAAA==.Sii:BAAALAADCggIDQAAAA==.Sinolia:BAAALAAECggIDgABLAAFFAIICAAkAJMQAA==.Sipyx:BAABLAAECoEdAAIJAAcI/RH6XwCdAQAJAAcI/RH6XwCdAQAAAA==.Sita:BAAALAAECgMIAwAAAA==.Siéa:BAAALAADCggIGAAAAA==.',Sk='Skaff:BAABLAAECoEoAAIOAAgISh38EQB9AgAOAAgISh38EQB9AgAAAA==.Skelton:BAAALAADCgcIBwAAAA==.Skyro:BAAALAAECgQIBAAAAA==.',So='Solarya:BAABLAAECoEYAAIBAAcIzhEjVgBbAQABAAcIzhEjVgBbAQAAAA==.Souleather:BAAALAAECgYIBgAAAA==.Soyboy:BAAALAAECgUIBgAAAA==.',St='Stefler:BAABLAAECoEeAAILAAgI8B1NKwBBAgALAAgI8B1NKwBBAgAAAA==.',Su='Suprdiscount:BAAALAAECgYIDgAAAA==.',Sy='Sylandre:BAAALAAECgYIBwABLAAFFAIICAALAFQlAA==.Symbule:BAAALAAECgYIEgAAAA==.',['Sê']='Sêraphine:BAAALAADCgcIBwAAAA==.',['Së']='Sëlkys:BAAALAAECgEIAQAAAA==.',Ta='Tafaim:BAAALAADCggICAAAAA==.Takhisis:BAAALAAECgIIAgAAAA==.Taliani:BAAALAADCggIDAAAAA==.Talïani:BAAALAADCgcIDAAAAA==.Tangri:BAAALAADCgYIBgAAAA==.Tarkivh:BAAALAAECgYIBgABLAAECggIJQASAI8kAA==.Tarkuzad:BAABLAAECoElAAMSAAgIjyQrDQAkAwASAAgISyQrDQAkAwAgAAgILR0OAgDQAgAAAA==.Taurentoro:BAABLAAECoEUAAINAAcI5xbjaQDnAQANAAcI5xbjaQDnAQAAAA==.',Th='Thaldriel:BAAALAAECgYIDQAAAA==.Thorfeng:BAAALAADCgcIDQAAAA==.Thorvx:BAAALAAECgEIAQAAAA==.Thundder:BAAALAADCgYIBgAAAA==.Thäwäl:BAAALAAECgYIBgAAAA==.',To='Torendivin:BAAALAADCggICgAAAA==.Touchsky:BAAALAAECgYIDgAAAA==.Toutdur:BAAALAAECggIDQAAAA==.',Tr='Tryxe:BAABLAAECoEtAAINAAgISyGzFwD+AgANAAgISyGzFwD+AgAAAA==.',Ts='Tsünia:BAAALAAECgYIEgAAAA==.',Ty='Tyes:BAAALAADCggICAAAAA==.',['Tï']='Tïll:BAABLAAECoEaAAILAAYIYw/dnAAJAQALAAYIYw/dnAAJAQAAAA==.',['Tö']='Törr:BAAALAADCgcIBwAAAA==.',Un='Unholy:BAAALAAECgQIBgAAAA==.',Ur='Urunjin:BAAALAADCgcIDQABLAAECggIHAAYAGwYAA==.',Va='Vahslof:BAAALAADCgIIAQAAAA==.Valessa:BAAALAADCgQIBAAAAA==.Vanaderad:BAABLAAECoEXAAIHAAcIehJDIADiAQAHAAcIehJDIADiAQAAAA==.Varad:BAAALAAECgQIBwAAAA==.Varya:BAAALAADCgYIDAABLAAFFAIIBgABAK4RAA==.Varyn:BAAALAAECgEIAQAAAA==.Varä:BAAALAADCgMIAwAAAA==.',Ve='Venom:BAAALAAECgYICgAAAA==.',Vl='Vlaskalas:BAAALAADCggICQAAAA==.',Vo='Voraj:BAACLAAFFIEWAAIOAAYIQiI3AQBKAgAOAAYIQiI3AQBKAgAsAAQKgSAAAg4ACAhWJlIBAHgDAA4ACAhWJlIBAHgDAAAA.Vorajrogue:BAAALAADCgYIBgAAAA==.Vorajwarrior:BAAALAAECggIBQAAAA==.',Wa='Waban:BAAALAAECgYICgAAAA==.Wanderlei:BAAALAAFFAIIAgAAAA==.Wartotem:BAAALAAECgYICwAAAA==.',We='Weisheng:BAAALAAECgYIDwAAAA==.',Wo='Wouallybis:BAABLAAECoEiAAISAAgI8BQSRQAaAgASAAgI8BQSRQAaAgAAAA==.',['Wæ']='Wædøw:BAAALAADCggIDQAAAA==.',Xa='Xalatath:BAABLAAECoEZAAQjAAYIPhD7YgD0AAAjAAUINQz7YgD0AAAoAAIIcw2ZKQBfAAABAAEIbAYAAAAAAAAAAA==.Xamoof:BAAALAAECgYICwAAAA==.',Xi='Xilaka:BAAALAAECgIIAwAAAA==.',Ya='Yaeluira:BAAALAADCgYIBwAAAA==.Yasu:BAACLAAFFIEZAAISAAYIYCKWAgBSAgASAAYIYCKWAgBSAgAsAAQKgSsAAhIACAhZJkYEAGUDABIACAhZJkYEAGUDAAAA.',Yo='Yocrita:BAAALAAECgQIBwAAAA==.Yonétsu:BAAALAAECgMIAwAAAA==.Yoone:BAAALAADCggIDAAAAA==.',Yr='Yragosa:BAAALAADCgUIBAAAAA==.',Ys='Ysae:BAAALAAECgQICgAAAA==.',Yu='Yulia:BAABLAAECoEYAAMlAAcIXxNnFgD2AQAlAAcIXxNnFgD2AQAEAAYI8QwO0AA6AQAAAA==.Yushei:BAACLAAFFIEFAAIQAAII/gtaNACEAAAQAAII/gtaNACEAAAsAAQKgS0AAhAACAj6G841AEUCABAACAj6G841AEUCAAAA.',['Yè']='Yèwéi:BAAALAADCggIFQAAAA==.',Za='Zaaléone:BAAALAADCggIGQAAAA==.Zadimus:BAAALAAECgMIAwAAAA==.Zazalolo:BAABLAAECoEUAAIOAAYI1RiILQCgAQAOAAYI1RiILQCgAQAAAA==.',Zh='Zhanä:BAAALAAFFAIIBAAAAQ==.',Zi='Zingiber:BAABLAAECoEnAAIXAAgIFiHwBwDNAgAXAAgIFiHwBwDNAgAAAA==.Zinjho:BAAALAAECgMIAwAAAA==.',Zo='Zola:BAAALAAECgYIBgAAAA==.Zolas:BAAALAAECgIIAwABLAAECgYIBgADAAAAAA==.Zouz:BAAALAAECggIDwAAAA==.',Zy='Zyf:BAAALAADCggICAAAAA==.Zyzi:BAABLAAECoEWAAMQAAgIixplNABKAgAQAAgIixplNABKAgAVAAQInhQadADgAAAAAA==.',['Zé']='Zélyna:BAAALAADCgYIBwAAAA==.',['Zë']='Zëkhæ:BAABLAAECoEgAAIQAAgIVx/qJQCIAgAQAAgIVx/qJQCIAgAAAA==.',['Âr']='Ârkhaam:BAAALAAECggICQABLAAECggILQALAO4UAA==.',['Éh']='Éh:BAAALAAECggICAAAAA==.',['Én']='Énariel:BAAALAADCgIIAgAAAA==.',['Év']='Évarion:BAAALAADCgcIBwAAAA==.',['Ët']='Ëthån:BAABLAAECoEZAAIKAAcIiB3GEQBFAgAKAAcIiB3GEQBFAgAAAA==.',['Ôr']='Ôrazumî:BAAALAAECgIIAwAAAA==.',['Øz']='Øzdva:BAAALAADCgUIBQAAAA==.',['Ùn']='Ùnder:BAAALAAECgYIDgAAAA==.',['Ür']='Üranium:BAABLAAECoEqAAMQAAgIVCUNBwBIAwAQAAgIVCUNBwBIAwAVAAUIIBsfTQBoAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end