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
 local lookup = {'Warlock-Destruction','Paladin-Retribution','Druid-Feral','Druid-Restoration','Unknown-Unknown','Priest-Holy','Mage-Arcane','Shaman-Enhancement','Hunter-BeastMastery','Druid-Balance','DeathKnight-Unholy','Paladin-Protection','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','Warlock-Affliction','Warrior-Protection','Hunter-Marksmanship','Priest-Shadow','Rogue-Assassination','Warlock-Demonology','DeathKnight-Frost','Monk-Windwalker','Mage-Frost','Paladin-Holy','DemonHunter-Havoc','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','Monk-Mistweaver',}; local provider = {region='EU',realm="Sen'jin",name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarany:BAAALAAECgQIBAAAAA==.',Ab='Abate:BAABLAAECoEdAAIBAAgIPgjTggBAAQABAAgIPgjTggBAAQAAAA==.',Ag='Age:BAABLAAECoEUAAICAAYIPBu/cADYAQACAAYIPBu/cADYAQAAAA==.',Aj='Ajina:BAABLAAECoEWAAMDAAcIHg5WJQA2AQADAAYI/wtWJQA2AQAEAAYI+wZsewDmAAAAAA==.',Ak='Akhár:BAAALAADCgQIBAAAAA==.Akrasia:BAAALAAECgYIDQABLAAECgcICwAFAAAAAA==.Akrasiabow:BAAALAAECgEIAQABLAAECgcICwAFAAAAAA==.Akrasiaclap:BAAALAAECgUIBwABLAAECgcICwAFAAAAAA==.Akrasiapally:BAAALAAECgcICwAAAA==.',Al='Alession:BAAALAADCgcIBwAAAA==.Altfvier:BAAALAAECgYIEgAAAA==.',Am='Amberle:BAAALAAECgMIBAAAAA==.',An='Angelqt:BAAALAAECgYICgAAAA==.Animalía:BAAALAAECgYIDwAAAA==.Anolahshuri:BAABLAAECoEVAAIGAAcI0gb+bgAIAQAGAAcI0gb+bgAIAQAAAA==.Anuksa:BAAALAAECggIEgAAAA==.',Ap='Apollonier:BAAALAADCgQIBAAAAA==.',Ar='Artendor:BAAALAAECgMICAAAAA==.Artiø:BAAALAADCgMIAwAAAA==.Artío:BAAALAAECgIIAgAAAA==.Arwenus:BAAALAADCgEIAQAAAA==.Ary:BAABLAAECoEbAAIHAAcINhGeYgC9AQAHAAcINhGeYgC9AQAAAA==.Arylon:BAAALAADCgMIAwAAAA==.',As='Aselage:BAAALAAECgYIDgAAAA==.Asmodinâ:BAAALAAECgYIDAAAAA==.',At='Ataa:BAABLAAECoEaAAICAAYIcB3IYAD6AQACAAYIcB3IYAD6AQAAAA==.',Au='Auabär:BAAALAADCggIFAAAAA==.',Av='Avéne:BAAALAAECgMIAwAAAA==.',Ay='Aynn:BAABLAAECoEaAAIIAAgIzh/jAwDgAgAIAAgIzh/jAwDgAgAAAA==.',Az='Azra:BAABLAAECoEYAAIJAAcI7Q5ngAB9AQAJAAcI7Q5ngAB9AQAAAA==.',Ba='Baahlarina:BAAALAADCggICAAAAA==.Barbo:BAAALAADCggIEAAAAA==.Baschtl:BAAALAAECggICAAAAA==.',Be='Beasst:BAAALAADCgEIAQAAAA==.Belisama:BAABLAAECoEbAAIKAAcI+xHiOwCXAQAKAAcI+xHiOwCXAQAAAA==.',Bl='Blackbubble:BAAALAAECgYIEQABLAAECggIIgALABwTAA==.Bloodheart:BAAALAAECggICwAAAA==.',Bo='Bonzzo:BAAALAADCgcIAwAAAA==.Boouhjit:BAAALAAECgYIEQAAAA==.',Br='Breadhead:BAABLAAECoEjAAICAAcIaB8ZQQBOAgACAAcIaB8ZQQBOAgAAAA==.Brightmaster:BAAALAADCggICAAAAA==.Broxara:BAAALAAECgQIBQABLAAECgUIDAAFAAAAAA==.Broxigah:BAAALAAECgEIAQABLAAECgUIDAAFAAAAAA==.Broxxa:BAAALAAECgUIDAAAAA==.Bruno:BAAALAADCgcIEAAAAA==.',Bu='Burt:BAAALAAECgYIDAAAAA==.Buseraa:BAAALAAECgQIBAAAAA==.',['Bà']='Bàlîn:BAABLAAECoEZAAMCAAYIMRtPdADRAQACAAYIgxlPdADRAQAMAAMIFRegTACPAAAAAA==.',['Bá']='Báschtl:BAAALAAECggICAAAAA==.',['Bâ']='Bârrio:BAAALAADCgEIAQAAAA==.',['Bø']='Bønes:BAAALAADCggIEAAAAA==.',['Bù']='Bùdspencer:BAABLAAECoEXAAINAAcIpA+CTACpAQANAAcIpA+CTACpAQAAAA==.',Ca='Caetheas:BAAALAADCgYIBgAAAA==.Candela:BAAALAADCgUIBQAAAA==.Caprina:BAAALAAECgYIEgAAAA==.Cattleyá:BAAALAAECgUICgAAAA==.',Ce='Cediiy:BAAALAADCggICAAAAA==.Cein:BAAALAAECgYIDAAAAA==.Cernius:BAAALAADCggIGAAAAA==.',Ch='Chanakra:BAAALAAECggIAQAAAA==.Charas:BAAALAAECgcIEwAAAA==.Chenna:BAABLAAECoEUAAIGAAYIwwLGfgDPAAAGAAYIwwLGfgDPAAAAAA==.Chillig:BAAALAADCggICAAAAA==.Chronormo:BAAALAADCgcICgAAAA==.',Ci='Cianna:BAAALAADCggICAAAAA==.',Cl='Claidissa:BAABLAAECoEaAAIGAAcIYhOYRgCWAQAGAAcIYhOYRgCWAQAAAA==.Clêptô:BAAALAAECggICAAAAA==.',Co='Copgun:BAAALAAECggICAAAAA==.',Cr='Croffle:BAAALAADCggICAAAAA==.',Da='Dalegus:BAAALAADCgcIFQAAAA==.Daniel:BAABLAAECoEdAAIOAAgImxhoLgA0AgAOAAgImxhoLgA0AgAAAA==.Danielr:BAAALAAECgEIAQABLAAECggIHQAOAJsYAA==.Dantè:BAAALAAECgUIBQAAAA==.Darkîne:BAAALAADCgYICAAAAA==.',De='Deathdome:BAAALAADCgcIDgAAAA==.Deathmakke:BAABLAAECoEdAAIPAAYItBr+FQC/AQAPAAYItBr+FQC/AQAAAA==.Deldoron:BAAALAAECgYIDwAAAA==.Desaster:BAAALAAECggICAAAAA==.',Dj='Djunen:BAAALAAECgIIAgAAAA==.',Do='Dodottot:BAABLAAECoElAAIQAAgIthCOCgDyAQAQAAgIthCOCgDyAQAAAA==.Doki:BAABLAAECoEnAAIRAAgIRR1VDwCcAgARAAgIRR1VDwCcAgAAAA==.',Dr='Dracwingduck:BAAALAAECgcICAAAAA==.Dragonmaik:BAAALAADCgcIEwAAAA==.Dragonos:BAAALAADCggICAAAAA==.Drendor:BAAALAAECgIIAgABLAAFFAMIBgASAOkWAA==.Drowranger:BAAALAADCgYICgABLAAECgYIFQATAHIWAA==.',Du='Dumesa:BAAALAAECgYIDgAAAA==.Dunreb:BAAALAADCgcIDgAAAA==.',Dw='Dwarjon:BAAALAAECgMIAwAAAA==.',Dy='Dylara:BAAALAAECgYIDwAAAA==.',['Dâ']='Dânte:BAAALAAECgQIBAABLAAECggIIgALABwTAA==.Dânyel:BAAALAADCgcIBwABLAAECggIHQAOAJsYAA==.Dârîa:BAAALAADCggIFAAAAA==.',['Dí']='Díego:BAAALAAECgcIDAAAAA==.',['Dî']='Dîlara:BAAALAADCggICQAAAA==.',Ed='Edrélua:BAAALAAECgIIAgAAAA==.',El='Elavwen:BAAALAAECgYIBgAAAA==.Eldria:BAAALAAECgYIEAAAAA==.Elemdor:BAABLAAECoEVAAIUAAYIgxE6OgBgAQAUAAYIgxE6OgBgAQAAAA==.Elfenliied:BAAALAADCggIDwAAAA==.Elisar:BAAALAADCgIIAgAAAA==.Elizara:BAAALAAECgYIBgAAAA==.Ellisha:BAABLAAECoEdAAIEAAcIAR69HABZAgAEAAcIAR69HABZAgAAAA==.',Em='Emaríel:BAAALAAECgYIEgAAAA==.',En='Endimion:BAAALAAECgIIBAAAAA==.Enterprise:BAAALAADCgEIAQAAAA==.',Er='Erendis:BAAALAADCgcICQAAAA==.',Es='Estaruu:BAAALAADCgcIRAAAAA==.',Et='Ethelenor:BAAALAADCggIFAAAAA==.Ethelyn:BAAALAAECgcIBwAAAA==.',Eu='Euchrid:BAAALAAECggICwAAAA==.Eurytion:BAABLAAECoEdAAMCAAcIoB3ZTgAnAgACAAcIoB3ZTgAnAgAMAAUIjRVYMQBAAQAAAA==.',Ex='Exíl:BAAALAADCggICAAAAA==.',Ey='Eynn:BAAALAAECgIIAgABLAAECggIGgAIAM4fAA==.Eyr:BAAALAADCgMIBQABLAADCgcIDQAFAAAAAA==.',Ez='Ezra:BAAALAAECgIIBAAAAA==.',['Eö']='Eöl:BAABLAAECoEZAAIJAAcIvg1WiwBnAQAJAAcIvg1WiwBnAQAAAA==.',Fa='Fanris:BAAALAADCgIIAgAAAA==.',Fe='Fellily:BAAALAADCggIFQAAAA==.',Fi='Figgo:BAABLAAECoEUAAICAAgIpBXVRwA6AgACAAgIpBXVRwA6AgAAAA==.Finsterbart:BAABLAAECoEqAAMBAAgIUCKKGADYAgABAAgIUCKKGADYAgAVAAMIkh0GVwDpAAAAAA==.Firoh:BAABLAAECoEjAAIGAAcIgiLUEwCwAgAGAAcIgiLUEwCwAgABLAAECgcIIQAWAAwiAA==.Firstdark:BAABLAAECoErAAIJAAgIFxASagCuAQAJAAgIFxASagCuAQAAAA==.',Fl='Flattervieh:BAAALAADCggICAAAAA==.Fliki:BAAALAADCgIIAgAAAA==.',Fr='Frayta:BAAALAADCggIDwABLAAECgYIBgAFAAAAAA==.Freeya:BAAALAADCgcIDQAAAA==.Fridlin:BAAALAAECgQICQAAAA==.Frostweber:BAAALAAECgYIDgAAAA==.Fréyà:BAAALAAECgYIDAAAAA==.',['Fä']='Fährtenleser:BAAALAADCgYIBgABLAAECgYIBgAFAAAAAA==.',Ga='Galður:BAAALAAECgMIBQAAAA==.Gargora:BAAALAAECgcIDAAAAA==.',Gi='Gizzmondo:BAACLAAFFIEGAAIXAAII8AsQDwCKAAAXAAII8AsQDwCKAAAsAAQKgSQAAhcABwg0HbgSAF0CABcABwg0HbgSAF0CAAAA.',Go='Goas:BAAALAAECgUICwAAAA==.Goasol:BAAALAAECgYICAAAAA==.Golare:BAAALAAECgUICgAAAA==.Goldkehlchen:BAAALAADCggIDAAAAA==.Gorgumenta:BAAALAADCgYIBgAAAA==.',Gr='Greed:BAAALAAECgYICgAAAA==.Greendevile:BAABLAAECoEWAAISAAYIDQmGbgD0AAASAAYIDQmGbgD0AAAAAA==.Greensnow:BAAALAAECgYIEAAAAA==.Gremoria:BAAALAADCgMIAgAAAA==.Grimjoura:BAAALAADCggIBwAAAA==.Grindol:BAAALAAECgYIDQAAAA==.Grischa:BAAALAAECgIIAgAAAA==.Groég:BAAALAADCgUIBQAAAA==.Grünhornet:BAAALAAECgQICgAAAA==.',Gu='Gurawl:BAAALAAECggIBAAAAA==.',['Gê']='Gêriêr:BAAALAAECgYIDAAAAA==.',Ha='Haetni:BAAALAADCgYIBgAAAA==.Hawkmoon:BAAALAADCgQIBAAAAA==.',He='Headnor:BAAALAAECgUIBAAAAA==.Heidenblut:BAAALAADCggICAAAAA==.Hellhunter:BAAALAAECgIIAwAAAA==.Herares:BAAALAAECgYIBgAAAA==.Herry:BAAALAADCgIIAgAAAA==.Hexenlády:BAAALAAECgYIBgABLAAECgcIEwAFAAAAAA==.',Hi='Hisaki:BAAALAADCggIDwAAAA==.',Ho='Howdini:BAAALAADCggIDwABLAAECgYIBgAFAAAAAA==.',['Hí']='Hínatá:BAAALAAECgYIEAAAAA==.',['Hî']='Hîsuka:BAAALAAECggIDgAAAA==.',Ic='Ich:BAAALAADCggIDAABLAAECgcIFwAVAGgHAA==.',Im='Imbaer:BAAALAAECgEIBQAAAA==.',In='Innabis:BAAALAAECgYIDAAAAA==.Inxoy:BAAALAAECggICwAAAA==.',Is='Isabellá:BAAALAADCggIIAAAAA==.',Ja='Jamila:BAAALAADCggIEAAAAA==.Jassi:BAAALAADCggIFAAAAA==.Jaímy:BAAALAADCggIDQAAAA==.',Ji='Jiain:BAAALAADCggICAABLAAECgYIBgAFAAAAAA==.Jinsuan:BAAALAAECggICAAAAA==.',Jy='Jyinara:BAAALAADCggIIAAAAA==.',Ka='Kaida:BAABLAAECoEfAAIYAAgIeyGOCAD1AgAYAAgIeyGOCAD1AgABLAAFFAMIBgASAOkWAA==.Kais:BAAALAAECgYIDAAAAA==.Kaiyora:BAACLAAFFIEGAAISAAIIYhd2FgCdAAASAAIIYhd2FgCdAAAsAAQKgSEAAhIACAj6IK4MAPMCABIACAj6IK4MAPMCAAAA.Kalista:BAAALAAECgIIAgAAAA==.Karatee:BAAALAADCgcIDwAAAA==.Karazek:BAABLAAECoEhAAIUAAcIrxQlIQD6AQAUAAcIrxQlIQD6AQAAAA==.',Ki='Kiinea:BAABLAAECoEuAAIZAAgI5iIOAwAjAwAZAAgI5iIOAwAjAwAAAA==.Kiwî:BAABLAAECoEdAAIRAAcIhiKmDAC/AgARAAcIhiKmDAC/AgAAAA==.',Ko='Komrod:BAABLAAECoEeAAIOAAgIShaLOwAGAgAOAAgIShaLOwAGAgAAAA==.',Kr='Kratos:BAABLAAECoEmAAICAAgIDBlmQgBKAgACAAgIDBlmQgBKAgAAAA==.Kristallica:BAAALAADCggICAAAAA==.',Ky='Kytanix:BAAALAADCggIGwAAAA==.',['Kâ']='Kâri:BAAALAAECgYICgAAAA==.',['Kå']='Kåscha:BAAALAADCggIEgAAAA==.',La='Lahrsen:BAAALAADCgYIBgAAAA==.Lanzelot:BAAALAADCggICAAAAA==.Lauch:BAABLAAECoEUAAIKAAcIMhcZLgDdAQAKAAcIMhcZLgDdAQAAAA==.Layonlonso:BAAALAADCgcIDQABLAAECggIDQAFAAAAAA==.',Le='Leblack:BAABLAAECoEiAAMLAAgIHBMiEgAoAgALAAgIHBMiEgAoAgAWAAQI3QRxHgGRAAAAAA==.Legendb:BAAALAADCggICAAAAA==.Leja:BAAALAADCggIEAAAAA==.Lenalovegood:BAAALAADCgYIBgAAAA==.Lerch:BAAALAADCgYIBgAAAA==.Leshrak:BAAALAADCgMIAgAAAA==.Leukothea:BAABLAAECoEcAAIOAAcIORkrQQDzAQAOAAcIORkrQQDzAQAAAA==.',Li='Lisanna:BAABLAAECoEZAAIaAAYI3RIxlgBsAQAaAAYI3RIxlgBsAQAAAA==.',Lo='Lonsman:BAAALAAECggIDQAAAA==.',Lu='Lupusius:BAAALAAECggIDgAAAA==.',Ly='Lypsil:BAAALAADCggIDAAAAA==.Lyvaria:BAAALAAECgUIDgAAAA==.',['Lé']='Léa:BAABLAAECoEmAAIbAAgIJRugCQBzAgAbAAgIJRugCQBzAgAAAA==.',['Lö']='Löschpapier:BAAALAADCggICAABLAAECgYIHAAcAM4WAA==.',Ma='Magentis:BAAALAADCggIHQAAAA==.Magior:BAABLAAECoEgAAIHAAgIviI3EAASAwAHAAgIviI3EAASAwAAAA==.Maikj:BAAALAAECgUICwAAAA==.Maleachi:BAABLAAECoEYAAMTAAcIggdlVAA/AQATAAcIggdlVAA/AQAGAAYIdQ4pYgAwAQAAAA==.Mannilein:BAAALAAECgYIEQAAAA==.Maru:BAAALAAECggIEQAAAA==.Maylin:BAAALAAECgIIBgAAAA==.',Me='Medícus:BAAALAAECgMIAwAAAA==.Melasculá:BAAALAAECgIIAwAAAA==.Melisándre:BAAALAAECgYICwABLAAECggIFAABANISAA==.',Mh='Mherin:BAAALAADCgIIAgAAAA==.',Mi='Mijke:BAAALAADCgMIAwAAAA==.Mirell:BAAALAAECgYIDAAAAA==.Mireyla:BAAALAAECgYIDAABLAAECggIGwAJAMIbAA==.Miristkalt:BAAALAADCgcIDAAAAA==.',Mo='Molgren:BAAALAAECgYICgAAAA==.Monari:BAAALAADCgYICgAAAA==.Moorlord:BAAALAAECggICAAAAA==.Morida:BAAALAAECgYIEQAAAA==.Morteques:BAAALAAECgYICQAAAA==.',Mu='Mugand:BAAALAAECgMIAwAAAA==.Muhzifer:BAAALAADCggIEgAAAA==.Muspek:BAAALAADCgQICAAAAA==.Muspell:BAAALAADCgQIBAAAAA==.',My='Myrdania:BAAALAAECgUICwAAAA==.Mystiqué:BAAALAADCgcIDAAAAA==.Mystìque:BAABLAAECoEWAAIOAAgIxwjolAAZAQAOAAgIxwjolAAZAQAAAA==.',['Má']='Mágyx:BAAALAAECgQICwAAAA==.',['Mì']='Mìssy:BAAALAAECgcIEwAAAA==.',['Mî']='Mîndgâmes:BAAALAAECgYIEAAAAA==.',Na='Nali:BAAALAAECgcIDwAAAA==.Natnat:BAABLAAECoEUAAIWAAcIux6kTgAtAgAWAAcIux6kTgAtAgAAAA==.Naømi:BAABLAAECoEUAAMRAAYIGxP+OABfAQARAAYIGxP+OABfAQAdAAQI9ASYsgCPAAAAAA==.Naýa:BAAALAAECgcIBwAAAA==.',Ne='Nekrovir:BAABLAAECoEcAAINAAcIeSD3HgCKAgANAAcIeSD3HgCKAgAAAA==.Nelezwei:BAAALAAECgYICAAAAA==.Neptun:BAAALAAECggICQAAAA==.Nexarion:BAAALAADCggIEAABLAAFFAIIBgAWAMUdAA==.Nexartus:BAAALAADCggIFwABLAAFFAIIBgAWAMUdAA==.Nexina:BAAALAADCggICAABLAAFFAIIBgAWAMUdAA==.',Ni='Nightsûn:BAAALAAECgIIAgABLAAECgYICAAFAAAAAA==.Nikimia:BAAALAAECgQIBAAAAA==.Nimoria:BAAALAADCggICAAAAA==.Nità:BAAALAADCgEIAQABLAAECgcIBwAFAAAAAA==.Nitâ:BAAALAAECgcIBwAAAA==.',Nu='Nutzlose:BAABLAAECoEUAAIBAAgI0hJARAD6AQABAAgI0hJARAD6AQAAAA==.',Ny='Nyx:BAAALAAECgYICAAAAA==.Nyxarona:BAAALAADCgcIBwABLAAECgYICAAFAAAAAA==.Nyxoia:BAAALAAECgYIBgABLAAECgYICAAFAAAAAA==.Nyxona:BAAALAADCgQIBAABLAAECgYICAAFAAAAAA==.Nyz:BAAALAADCgMIAwAAAA==.',['Né']='Nél:BAAALAADCgQIBAABLAAECggIJgAbACUbAA==.',['Nê']='Nêphilim:BAABLAAECoEWAAILAAYIBwQVNQAFAQALAAYIBwQVNQAFAQAAAA==.',['Nî']='Nîne:BAAALAADCggICAAAAA==.',Od='Odon:BAABLAAECoEdAAILAAgI0BP1EAA1AgALAAgI0BP1EAA1AgAAAA==.',Ol='Oldí:BAAALAAECgQIDwAAAA==.Olorim:BAAALAADCggIFQAAAA==.',Or='Orkfrieda:BAAALAADCggIDAAAAA==.',Pa='Palatarn:BAAALAAECggIDgAAAA==.Palpal:BAAALAAECgYICQAAAA==.Pappagallo:BAAALAADCgMIBwAAAA==.Pappknight:BAAALAADCggICAAAAA==.Paschah:BAABLAAECoEkAAIaAAgIGB4RIADEAgAaAAgIGB4RIADEAgAAAA==.Pasha:BAABLAAECoEVAAIKAAYINxyKLwDVAQAKAAYINxyKLwDVAQAAAA==.',Pi='Piffpaffpúff:BAAALAAECgMIBgAAAA==.Pilua:BAAALAADCggICAABLAAECggIDgAFAAAAAA==.Pinea:BAAALAADCgUIBQAAAA==.',Po='Polocross:BAAALAADCggIGQAAAA==.Porir:BAAALAAECgUICQAAAA==.',Pr='Preus:BAAALAAECgIIAgAAAA==.',['Pü']='Pürzelchen:BAAALAAECgIIAgAAAA==.',Qu='Quastrus:BAAALAADCggIEAAAAA==.',Ra='Raagna:BAAALAADCgcIIgAAAA==.Raggna:BAAALAAECgYIEQAAAA==.Rahem:BAAALAAECgYIEgAAAA==.Raimei:BAAALAADCggICQAAAA==.Rainshowers:BAAALAAECgYICwAAAA==.Rakr:BAAALAADCgIIAgAAAA==.Razalmur:BAAALAADCgcICgAAAA==.Raýa:BAAALAAECgUIBgAAAA==.',Re='Reapia:BAAALAAECgMIBAAAAA==.Renenet:BAAALAADCggIFAAAAA==.Rexin:BAAALAADCggIMwAAAA==.Reyka:BAAALAADCggIEAAAAA==.Reýla:BAAALAADCggIEAAAAA==.',Ro='Româno:BAAALAAECgMIAwAAAA==.',['Rá']='Ráyna:BAAALAAECgYIBgAAAA==.',['Rì']='Rìn:BAABLAAECoEcAAIaAAcIPBWnYQDaAQAaAAcIPBWnYQDaAQAAAA==.',Sa='Sangreal:BAAALAAECggICAAAAA==.Saphir:BAABLAAECoEXAAMVAAcIaAd4PgBRAQAVAAcIJQZ4PgBRAQAQAAQIMgfPJACkAAAAAA==.Saphiron:BAAALAAECggIEAAAAA==.Sarshiva:BAAALAAECgUIDwAAAA==.Sarwenia:BAAALAAECgYICwAAAA==.Sasmora:BAAALAADCggICAAAAA==.',Sc='Schamadie:BAAALAAECgYIEQAAAA==.Schamakko:BAAALAADCgUIBwAAAA==.Schandra:BAAALAAECgYIEwAAAA==.Schokominzaa:BAAALAAECgYICwAAAA==.Schurkdili:BAAALAADCgcIBwAAAA==.',Se='Sebbi:BAAALAADCggIEQAAAA==.',Sh='Shandrâ:BAABLAAECoEdAAIBAAgIVwktYgCWAQABAAgIVwktYgCWAQAAAA==.Shaonling:BAAALAAECgYIDwAAAA==.Sharky:BAABLAAECoEwAAIeAAgIiCGrBQD3AgAeAAgIiCGrBQD3AgAAAA==.Sharkyna:BAAALAAECgQIBAABLAAECggIMAAeAIghAA==.Sheeva:BAAALAADCgcIFAAAAA==.Sherkol:BAAALAADCggICAAAAA==.Shimatsu:BAAALAADCgcIBwAAAA==.Shyva:BAAALAADCgUIBQAAAA==.Shôcky:BAAALAADCgcIDAAAAA==.',Si='Sindiu:BAAALAAECgUIDAAAAA==.',Sk='Skender:BAAALAAECgYIDAAAAA==.',Sn='Snôw:BAABLAAECoEVAAMTAAYIchZOQgCPAQATAAYIchZOQgCPAQAfAAMIkBKXIACpAAAAAA==.',So='Solkai:BAAALAAECgcIEQAAAA==.Somuna:BAAALAADCggICAAAAA==.',Sp='Spin:BAABLAAECoEdAAIBAAgIUwSDowDdAAABAAgIUwSDowDdAAAAAA==.Spogy:BAAALAAECgYIEwAAAA==.',St='Staarkimarm:BAAALAADCggICAAAAA==.Starspieler:BAAALAAECgYICQAAAA==.Stevie:BAABLAAECoEuAAIbAAgItBlwCgBiAgAbAAgItBlwCgBiAgAAAA==.Stichy:BAABLAAECoEqAAIJAAcIbxcaawCrAQAJAAcIbxcaawCrAQAAAA==.Stubenfliege:BAAALAAECgIIAgAAAA==.',Su='Sule:BAABLAAECoEVAAMYAAcI1RDXSAAkAQAHAAcIqgephwBYAQAYAAUICRTXSAAkAQAAAA==.Suppentrulli:BAAALAADCggIDAAAAA==.',Sy='Syrantia:BAAALAADCggICAAAAA==.',['Sé']='Sérénítý:BAAALAAECgYICgAAAA==.',['Sô']='Sôngo:BAABLAAECoEcAAIdAAcIKxnLOwAUAgAdAAcIKxnLOwAUAgAAAA==.',['Sü']='Süßbär:BAAALAADCgcIBwAAAA==.',['Sý']='Sýlphiette:BAAALAADCgcICAABLAAFFAMIBgAJAAUNAA==.',Ta='Tamitira:BAAALAAECgYIEAAAAA==.Tarvik:BAABLAAECoEUAAIXAAcIUAnBNAA3AQAXAAcIUAnBNAA3AQAAAA==.Taurifax:BAAALAAECgMIBwAAAA==.',Te='Temperancè:BAABLAAECoEcAAICAAgIdQm/owB4AQACAAgIdQm/owB4AQAAAA==.Testman:BAAALAADCggICAABLAAECggILQAJAJgkAA==.Teublitzer:BAABLAAECoEeAAIdAAgI/xTEOgAYAgAdAAgI/xTEOgAYAgAAAA==.',Th='Thalesea:BAABLAAECoErAAMEAAgIoBjLLQD8AQAEAAgIoBjLLQD8AQAKAAcIQxN3NgCyAQAAAA==.Thanatol:BAAALAAECgMIAwABLAAECggIMAAeAIghAA==.Tharalla:BAAALAAECgYIDgAAAA==.Theoverlord:BAABLAAECoEbAAICAAcI6hYjYgD3AQACAAcI6hYjYgD3AQAAAA==.Thríller:BAAALAAECgYIEQAAAA==.Thôr:BAABLAAECoEbAAMMAAYIFh6kHgDKAQAMAAYIFh6kHgDKAQACAAQIxxWU3AANAQAAAA==.',Ti='Tingol:BAAALAAECgIIBAAAAA==.Tistaria:BAAALAADCgIIAgAAAA==.',Tj='Tjuvar:BAABLAAECoEYAAMUAAYIux/3HwACAgAUAAYIux/3HwACAgAgAAEIFBNqQwA3AAAAAA==.',To='Totalschaden:BAAALAAECgYICgAAAA==.',Tr='Trendina:BAACLAAFFIEGAAISAAMI6RaVDADlAAASAAMI6RaVDADlAAAsAAQKgSgAAhIACAg3JGgHACUDABIACAg3JGgHACUDAAAA.Trinitara:BAAALAADCggIDAAAAA==.Trinitat:BAABLAAECoEgAAITAAcIKSPXEwC6AgATAAcIKSPXEwC6AgAAAA==.Trnty:BAABLAAECoEmAAIZAAgIghqTEQBgAgAZAAgIghqTEQBgAgAAAA==.Trntyxmw:BAAALAAECgEIAQABLAAECggIJgAZAIIaAA==.',Tu='Tuna:BAAALAADCggIFQABLAAECggIDgAFAAAAAA==.',Ty='Tyraiel:BAAALAAECgMIAQAAAA==.Tyréza:BAAALAAECgYICAAAAA==.',['Tê']='Têjsha:BAAALAAECgEIAQAAAA==.',Ud='Udai:BAAALAADCgEIAQAAAA==.',Ue='Uee:BAAALAAFFAIIAgAAAA==.',Va='Vaelaris:BAAALAADCgcIBwAAAA==.Vallyra:BAABLAAECoEpAAMaAAgI4h64OgBMAgAaAAgIOR64OgBMAgAeAAgIYRC+HQCWAQAAAA==.Vanu:BAAALAAECgYIBgAAAA==.Varaany:BAAALAAECggIEwAAAA==.',Ve='Velathra:BAAALAAECgMIAwAAAA==.Velá:BAAALAAECgMIAwAAAA==.Veláya:BAAALAAECgYIDAAAAA==.Verlax:BAABLAAECoEaAAMYAAcIEguPNgBzAQAYAAcIEguPNgBzAQAHAAUIiANAuwCmAAAAAA==.',Vi='Victania:BAABLAAECoErAAIOAAgIsyCnDwDVAgAOAAgIsyCnDwDVAgAAAA==.Vindale:BAAALAADCggICAAAAA==.Vindiva:BAAALAADCggIGAAAAA==.Viraia:BAAALAADCgIIAgAAAA==.Viro:BAAALAADCggICAABLAAECgcIIQAWAAwiAA==.Virodk:BAABLAAECoEhAAIWAAcIDCIwJwCxAgAWAAcIDCIwJwCxAgAAAA==.',Vl='Vlyana:BAAALAADCggICAAAAA==.',Vo='Voiel:BAAALAADCggICAAAAA==.Vollgeill:BAAALAADCggIGQAAAA==.',Wa='Waldhüterin:BAAALAAECgQICwAAAA==.Wassermaxi:BAABLAAECoEjAAIYAAcIDBpLKADBAQAYAAcIDBpLKADBAQAAAA==.',Wi='Wildboy:BAABLAAECoEUAAIJAAYIYBC9mwBHAQAJAAYIYBC9mwBHAQAAAA==.Willas:BAAALAAECggIDgABLAAECggIDgAFAAAAAA==.',Wu='Wummel:BAAALAADCggIFAAAAA==.',Wy='Wynn:BAABLAAECoEYAAIbAAYIXiELDABGAgAbAAYIXiELDABGAgABLAAECggIGgAIAM4fAA==.',['Wé']='Wéifêng:BAAALAADCggIDAAAAA==.',['Wü']='Wüstenrose:BAAALAAECgIIBAAAAA==.',Xe='Xexxa:BAAALAADCgYIBgAAAA==.',Xi='Xiar:BAAALAADCggICAAAAA==.Xixu:BAAALAADCgYIBgAAAA==.',Xn='Xnúj:BAAALAAECgYIEwAAAA==.',['Xî']='Xîîânny:BAABLAAECoEgAAIEAAcICCEPFQCOAgAEAAcICCEPFQCOAgAAAA==.',Yo='Yodax:BAAALAAECggIEAAAAA==.Youroichi:BAAALAADCgYIBgAAAA==.',Yr='Yrel:BAAALAADCgcIFAAAAA==.',Ys='Yserâ:BAABLAAECoEdAAMEAAcIORZ6OwC8AQAEAAcIORZ6OwC8AQAKAAMIswgeegB4AAAAAA==.',Za='Zandalpakala:BAABLAAECoEZAAMhAAYIvBcNHgCNAQAhAAYIvBcNHgCNAQAXAAYIthnUPwDnAAAAAA==.Zarin:BAAALAADCggIFgAAAA==.Zauberfeê:BAABLAAECoEdAAIBAAcISwV+iwAoAQABAAcISwV+iwAoAQAAAA==.Zawadî:BAAALAAECgcIBwAAAA==.Zayaleth:BAAALAAECgEIAQAAAA==.Zaydru:BAAALAADCggIDwAAAA==.Zaylistra:BAABLAAECoEVAAIVAAcI+RU0IwDQAQAVAAcI+RU0IwDQAQAAAA==.Zaystrasza:BAAALAADCggIDgAAAA==.Zayumi:BAAALAADCggICgAAAA==.',Ze='Zenythía:BAAALAAECgYIDAAAAA==.Zephyristraz:BAAALAADCggIEQAAAA==.',Zo='Zordrak:BAAALAADCggIEAAAAA==.Zoroha:BAAALAAECgYIEgAAAA==.Zosly:BAAALAADCgcIEQAAAA==.',Zw='Zwiebelyn:BAAALAADCggICAAAAA==.',Zy='Zylana:BAAALAAECgMIBAAAAA==.Zymos:BAAALAADCgEIAQAAAA==.Zynaris:BAAALAAECgYIDgAAAA==.',['Áz']='Ázrá:BAAALAAECgUIBQAAAA==.',['Âr']='Âry:BAAALAAECgQIBwAAAA==.',['Æø']='Æøm:BAAALAAECggICAAAAA==.',['Îk']='Îkîllyoûsoon:BAAALAAECgIIAgAAAA==.',['Ît']='Îtsddt:BAABLAAECoEjAAIaAAcIvCRtIgC4AgAaAAcIvCRtIgC4AgAAAA==.',['ßl']='ßloodhound:BAACLAAFFIEGAAIWAAIIxR2RKgCtAAAWAAIIxR2RKgCtAAAsAAQKgSwAAhYACAjoHx4eANkCABYACAjoHx4eANkCAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end