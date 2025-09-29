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
 local lookup = {'Warrior-Fury','Priest-Shadow','Unknown-Unknown','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Mage-Fire','Paladin-Holy','Warrior-Protection','Shaman-Restoration','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Feral','Hunter-Marksmanship','Druid-Guardian','Mage-Arcane','Priest-Holy','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Hunter-BeastMastery','Mage-Frost','Monk-Windwalker','Rogue-Subtlety','Priest-Discipline','Rogue-Outlaw',}; local provider = {region='EU',realm="Blade'sEdge",name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Aboudy:BAAALAAECgEIAQAAAA==.',Al='Alexander:BAABLAAECoEoAAIBAAgIGyMuCwAwAwABAAgIGyMuCwAwAwAAAA==.Aloja:BAAALAAECgQICQAAAA==.',Am='Amaliaxx:BAEALAADCggIDgABLAAFFAYIGAACALodAA==.Amidhunter:BAAALAADCgIIAgABLAAECgYIDwADAAAAAA==.',An='Angelbeatty:BAAALAADCgcIBwAAAA==.Angeleye:BAAALAADCgYIBgAAAA==.Angelvoodoo:BAAALAADCggIFQAAAA==.Angerycahlu:BAAALAADCggIFwAAAA==.Annastasya:BAAALAADCggICAAAAA==.Anomalie:BAAALAAECgYIBgABLAAECgYIEQADAAAAAA==.',Ar='Araneae:BAAALAAECgIIAgAAAA==.Arcadiaks:BAAALAADCggICAAAAA==.Arcage:BAAALAAFFAIIBAABLAAFFAUIDwAEAKcaAA==.Arcman:BAACLAAFFIEPAAIEAAUIpxqRBQDWAQAEAAUIpxqRBQDWAQAsAAQKgSAAAgQACAgoJYIHAEYDAAQACAgoJYIHAEYDAAAA.Ariaana:BAAALAAECggIEAAAAA==.Arven:BAABLAAECoEmAAQFAAgIZhxoEwB2AgAFAAgIKxxoEwB2AgAGAAgIExfOBAA9AgAHAAIIXgSGNABGAAAAAA==.Arzeldon:BAAALAADCgEIAQAAAA==.',As='Asbesta:BAAALAADCgcIBQAAAA==.',Au='Aureliya:BAAALAAFFAIIAgAAAA==.',Ay='Ayhoel:BAAALAAECgUICgABLAAECggIIgAIAP4gAA==.',Ba='Bahloo:BAAALAAECgMIBQAAAA==.Balorn:BAAALAADCgcIBwAAAA==.Bandana:BAAALAADCggIHAAAAA==.Barbossa:BAAALAAECggIDwAAAA==.Barog:BAAALAADCggIDgABLAAECgcIDAADAAAAAA==.',Be='Beinn:BAAALAADCggICAAAAA==.',Bl='Bladè:BAAALAADCggICAAAAA==.Blooddragon:BAAALAADCgYIBgAAAA==.Bloodeater:BAAALAAECgMIAwAAAA==.',Bo='Bob:BAABLAAECoErAAIJAAgItRkrEQBfAgAJAAgItRkrEQBfAgAAAA==.Boi:BAAALAAECgYIBgAAAA==.Boston:BAAALAADCggIGwAAAA==.',Br='Braindk:BAAALAADCgUIBQAAAA==.Brainhack:BAAALAADCggICAAAAA==.Brendel:BAAALAADCggICAAAAA==.Breni:BAAALAAECggICAAAAA==.Breno:BAABLAAECoErAAMBAAgI7SIOCwAxAwABAAgIlSIOCwAxAwAKAAcIAB4eHgAEAgAAAA==.Brenor:BAAALAADCggICAAAAA==.Brenthos:BAAALAADCggIDwAAAA==.Brightstars:BAAALAADCgUIBQAAAA==.',Bu='Buffy:BAAALAAECggIAgAAAA==.Bullbane:BAAALAAECgMIAwAAAA==.',['Bé']='Béat:BAAALAAECgYIDwABLAAECggIGgALAN8dAA==.Bért:BAAALAAECgEIAQAAAA==.',['Bó']='Bólt:BAABLAAECoEaAAILAAgI3x2OFwCcAgALAAgI3x2OFwCcAgAAAA==.',Ca='Cahlu:BAAALAADCggIEQAAAA==.Caxapok:BAAALAADCggIFgAAAA==.Caylyn:BAABLAAECoEaAAIMAAcIyyD2FgB5AgAMAAcIyyD2FgB5AgAAAA==.',Ch='Chimken:BAAALAADCggICAAAAA==.Choko:BAAALAAECgUIBgAAAA==.Chromasta:BAAALAADCgYIBgAAAA==.',Ci='Cinderwander:BAAALAAECgcIBwAAAA==.',Cl='Clélónna:BAAALAAECggIDwAAAA==.',Co='Comgo:BAABLAAECoEZAAMNAAcINSFkCwCQAgANAAcINSFkCwCQAgAOAAMIzQqABAGWAAABLAAECggIFwAPAFkdAA==.Constantíné:BAABLAAECoEXAAMQAAgIQQy4bwCxAQAQAAgI3Qu4bwCxAQARAAMIRAfzRwBsAAAAAA==.Covehustler:BAAALAADCgcICAAAAA==.',Da='Dahakpal:BAAALAAECgIIAgAAAA==.Dain:BAAALAAECgYICwABLAAECggIJgAFAGYcAA==.Damraseg:BAAALAADCgMIAwAAAA==.Dancewithme:BAAALAADCgQIBAAAAA==.Darksóul:BAAALAAECgIIAgABLAAECggIGgALAN8dAA==.Darkvenger:BAACLAAFFIEMAAISAAQIIhtnAQCBAQASAAQIIhtnAQCBAQAsAAQKgTMAAhIACAi9JHoBAFYDABIACAi9JHoBAFYDAAAA.Dawncaller:BAAALAAECgMICQAAAA==.',De='Deathbytoast:BAAALAADCgQIBAAAAA==.Deathnitelf:BAAALAADCgEIAQAAAA==.Deathticks:BAAALAADCgYIBgAAAA==.Deleteaug:BAAALAAECgEIAQAAAA==.Derius:BAAALAAECgIIAgAAAA==.',Di='Dianthusxx:BAEALAAECgYIDAABLAAFFAYIGAACALodAA==.Discipline:BAAALAAECggICAAAAA==.Divinehammer:BAAALAADCgcIDgABLAAECgcIHwABAPkgAA==.',Do='Doom:BAABLAAECoEUAAQSAAYIyBIJKwBJAQASAAYIogwJKwBJAQATAAQIiBVy6AD8AAAUAAMI8wpJMQCIAAABLAAECgcIHAAQAKwWAA==.',Dr='Dragonboy:BAAALAAECgYICwAAAA==.Dragoneye:BAAALAADCgcICAAAAA==.Dragonyesyes:BAAALAADCgcICQAAAA==.Dreylan:BAAALAAECgQIBgAAAA==.Druéd:BAABLAAECoEeAAMMAAcIWyEgEwCYAgAMAAcIWyEgEwCYAgAVAAIIww/SNQBzAAABLAAECggIGgALAN8dAA==.',Dw='Dwarfwind:BAABLAAECoEdAAIWAAgICxZLJwAaAgAWAAgICxZLJwAaAgAAAA==.',['Dé']='Délphine:BAAALAAECggICAAAAA==.',Eb='Ebriel:BAAALAADCgcIDwAAAA==.',Ec='Ecsztasy:BAAALAADCgcIEAAAAA==.',Eu='Eureeka:BAAALAAECgYICgAAAA==.',Fa='Faithxx:BAEALAAECgMIBAABLAAFFAYIGAACALodAA==.Fayrrel:BAAALAADCgUIBQAAAA==.',Fi='Firedt:BAAALAAECgIIBAAAAA==.',Fl='Flapaholic:BAAALAAECgMIAwAAAA==.Fleurm:BAAALAAECggICAAAAA==.',['Fö']='Föxwillfixit:BAAALAADCgYIDwAAAA==.',['Fú']='Fújin:BAAALAAFFAIIBAAAAA==.',Ga='Gabbi:BAAALAAECgcIBwAAAA==.Galarath:BAACLAAFFIEFAAIMAAIIQRlmFQClAAAMAAIIQRlmFQClAAAsAAQKgRoAAgwACAgqGR8mABsCAAwACAgqGR8mABsCAAAA.Gandraf:BAAALAADCggICwAAAA==.Garnetxx:BAECLAAFFIEYAAICAAYIuh3FAQBKAgACAAYIuh3FAQBKAgAsAAQKgSYAAgIACAiTJYYDAGADAAIACAiTJYYDAGADAAAA.',Gi='Gifgasz:BAAALAAECgUIBwAAAA==.Gingerrogue:BAAALAAECgcICQAAAA==.',Gn='Gnomosaund:BAAALAAECgUIBwAAAA==.',Go='Gorgidas:BAABLAAECoEfAAIOAAcIOxO/ewC7AQAOAAcIOxO/ewC7AQAAAA==.Gornox:BAAALAAECgYIBgAAAA==.',Gr='Grimetime:BAAALAADCgQIAwAAAA==.Grizzlebear:BAABLAAECoEUAAIXAAgIlx0cBgBvAgAXAAgIlx0cBgBvAgAAAA==.Grizzlehunt:BAAALAAECggIDgABLAAECggIFAAXAJcdAA==.Groot:BAAALAAECgMIAwAAAA==.',Gu='Gulliblehero:BAAALAAECgYIBgAAAA==.Gulliblemyth:BAAALAAECgEIAQAAAA==.Gulliblescar:BAAALAAECgQIBAAAAA==.',Ha='Haggis:BAAALAADCggIDwAAAA==.Happen:BAAALAADCggICAAAAA==.',He='Headoverheal:BAAALAAECgEIAQAAAA==.Heimdahl:BAAALAAECgUIBQABLAAECggIJgAFAGYcAA==.Helrus:BAAALAAECgMIBQAAAA==.',Hk='Hknight:BAAALAAECgQIBAAAAA==.',Ho='Hollycoww:BAAALAAECgYIDwAAAA==.Hopexx:BAEALAADCgcIEwABLAAFFAYIGAACALodAA==.',Hu='Humbee:BAABLAAECoEpAAIYAAgISSFwFgDrAgAYAAgISSFwFgDrAgAAAA==.',In='Innerflame:BAAALAAECgYIEQAAAA==.Inzanity:BAAALAADCgcIBgABLAAECggIIAAZAPQPAA==.',Ir='Iron:BAABLAAECoEoAAINAAgIxSU+AQB2AwANAAgIxSU+AQB2AwAAAA==.',Is='Ismilla:BAABLAAECoElAAIOAAgI/yXUAgB+AwAOAAgI/yXUAgB+AwAAAA==.',It='Ithania:BAAALAAECgYIBwAAAA==.',Ja='Jaffalad:BAAALAADCgYIBgABLAAFFAUIEwAaAMYYAA==.Jakelong:BAAALAADCgQIBgABLAAECggIJQAYAMQdAA==.Janken:BAAALAAECgIIAgAAAA==.',Je='Jezabelle:BAAALAAECgIIAgAAAA==.',Ji='Jibie:BAAALAADCggICgAAAA==.',Jo='Jodkin:BAAALAAECgIIAQAAAA==.Jorune:BAAALAADCgIIAgAAAA==.',Ju='Justjinger:BAAALAAECgYIDwAAAA==.',Ka='Kaiserus:BAAALAAECgYIEwAAAA==.Kalgar:BAAALAADCggICAAAAA==.Kallestare:BAAALAADCgYIBwAAAA==.Kaoleena:BAAALAAECgcIDQAAAA==.Kattigberud:BAACLAAFFIEFAAIXAAIImSV6AQDVAAAXAAIImSV6AQDVAAAsAAQKgSEAAhcACAjcJhUAAKMDABcACAjcJhUAAKMDAAAA.Kazal:BAABLAAECoErAAQPAAgIDybJAQCEAwAPAAgIDybJAQCEAwAbAAMISSJCVADuAAAcAAEI0B5/MABbAAAAAA==.Kazuneth:BAAALAAECgcICAABLAAECggIJQAbALckAA==.',Ke='Kelie:BAAALAAECgEIAQAAAA==.Kelmi:BAABLAAECoEXAAIQAAgIJiToDAAuAwAQAAgIJiToDAAuAwAAAA==.',Kh='Kherin:BAAALAADCggICwAAAA==.Khorex:BAABLAAECoErAAMOAAgISCEKFgADAwAOAAgISCEKFgADAwAJAAcIFhPCJgCuAQAAAA==.',Ki='Kiefer:BAAALAADCggICAAAAA==.Kirby:BAAALAAECgYIBQAAAA==.',Kn='Knopa:BAAALAADCgIIAgAAAA==.',Kr='Kreia:BAAALAAECgEIAQAAAA==.',['Ká']='Kálamity:BAAALAAECggICAAAAA==.',['Kâ']='Kâoleena:BAAALAADCggIDgABLAAECgcIDQADAAAAAA==.',La='Lanyto:BAAALAAECgYICgABLAAFFAUIDwAEAKcaAA==.',Le='Lekahai:BAAALAADCggICQABLAAECgUIBgADAAAAAA==.',Li='Liaponovia:BAABLAAECoEqAAIcAAgI1hFODQDAAQAcAAgI1hFODQDAAQAAAA==.Lichtridder:BAAALAADCggICAAAAA==.Lienbloom:BAAALAAFFAIIBAAAAA==.Liences:BAAALAAECgYIBgAAAA==.Lienifer:BAAALAAECgYIEgAAAA==.Light:BAAALAAECggICAAAAA==.Lilith:BAABLAAECoEXAAIPAAcIqAi3cQBjAQAPAAcIqAi3cQBjAQAAAA==.',Ll='Llamadrake:BAAALAAECgIIAgAAAA==.',Lo='Longranger:BAAALAAECgEIAQAAAA==.',Lu='Lunallama:BAAALAADCgcIBwAAAA==.Lunamortis:BAACLAAFFIEKAAITAAMIIBZNFgDuAAATAAMIIBZNFgDuAAAsAAQKgSMAAhMACAjEIZYlALMCABMACAjEIZYlALMCAAAA.Lunasan:BAAALAAECgcIEQAAAA==.Lunathalas:BAAALAAECgUIBwAAAA==.Lunoriel:BAAALAADCgcIBwABLAAFFAMICgATACAWAA==.Lutik:BAAALAADCgUIBwAAAA==.',Ly='Lydjas:BAABLAAECoEgAAIQAAcIiSM4HQDNAgAQAAcIiSM4HQDNAgAAAA==.',['Ló']='Lónghórn:BAAALAAECgIIAgAAAA==.',Ma='Maerec:BAABLAAECoEfAAISAAgI2wCXSQBkAAASAAgI2wCXSQBkAAAAAA==.Magerdas:BAAALAAECgcIEgAAAA==.Maginya:BAAALAADCggIHQAAAA==.Mallet:BAAALAADCgQIBAAAAA==.Mamiwata:BAAALAAFFAIIAgAAAA==.Mandnawe:BAABLAAECoEXAAIPAAgIWR1rGwDAAgAPAAgIWR1rGwDAAgAAAA==.Matchr:BAAALAAECgYIBwAAAA==.',Me='Meccasaund:BAAALAADCggICAAAAA==.Mehreeangry:BAAALAADCggICAAAAA==.Mehreedh:BAAALAADCgcIBwAAAA==.Mehreehunt:BAAALAAECgMIAwAAAA==.Meraxes:BAABLAAECoErAAIBAAgIjiX8AgB0AwABAAgIjiX8AgB0AwAAAA==.',Mi='Midway:BAAALAAECggIEQAAAA==.Misskt:BAAALAADCgcIBwAAAA==.Misspuff:BAAALAAECgQIBwAAAA==.',Mo='Mommydaddy:BAACLAAFFIEMAAMMAAQIOg+MBwAdAQAMAAQIOg+MBwAdAQAVAAEIlgyvDQBRAAAsAAQKgSYABBUACAieHW4WAMsBABUABgiCGm4WAMsBAAwACAgwEss7ALIBAB0AAQiZIJp/AFkAAAAA.Mon:BAAALAAECggICAABLAAECggICAADAAAAAA==.Monjah:BAAALAAECgEIAQAAAA==.Moofasa:BAAALAADCgQICQAAAA==.Mortaeus:BAAALAAECggICAABLAAECgUIDAADAAAAAQ==.Mothy:BAAALAAECgYICwAAAA==.',Mu='Mudy:BAAALAADCggICAAAAA==.',['Má']='Márog:BAAALAAECgcIDAAAAA==.',Na='Nahla:BAAALAADCgIIAgAAAA==.Nattwenty:BAAALAADCgEIAQABLAAFFAQIDAAMADoPAA==.',Ne='Necrópriest:BAAALAAECgIIAgAAAA==.Nemeea:BAAALAADCggIDgAAAA==.Nemu:BAAALAAECgIIAgAAAA==.Netharia:BAACLAAFFIEKAAIYAAMI6xSeFwD3AAAYAAMI6xSeFwD3AAAsAAQKgSQAAhgACAifH/IjAKMCABgACAifH/IjAKMCAAAA.Nevera:BAAALAAECggIBgAAAA==.',Ni='Niha:BAAALAADCggICgAAAA==.',No='Noeru:BAABLAAECoElAAMbAAgItyR5AQBhAwAbAAgItyR5AQBhAwAPAAII1h9qqAC4AAAAAA==.Nows:BAAALAADCggICAABLAAECggIGAARAPYeAA==.',['Ní']='Níght:BAAALAAECgYIEwABLAAECggIGgALAN8dAA==.',Oa='Oases:BAAALAAECgYIEwAAAA==.',Om='Ombretti:BAAALAAECgcIBwAAAA==.',On='Oniell:BAAALAADCggIDwAAAA==.Onryo:BAAALAAECggIBAABLAAFFAMICAAEAN0NAA==.',Pa='Pallidin:BAAALAADCgcIDQAAAA==.Papak:BAAALAAECgIIAgAAAA==.Paraadox:BAAALAADCgcICAAAAA==.Pardofelis:BAAALAADCgcIDQAAAA==.',Ph='Pharmakon:BAABLAAECoEbAAIeAAgImAnmhABnAQAeAAgImAnmhABnAQAAAA==.Phos:BAABLAAECoEcAAIBAAcIdxljPAAGAgABAAcIdxljPAAGAgAAAA==.',Pl='Plaguehowl:BAAALAAECgYIBgAAAA==.Plaguerot:BAAALAAECgYIDAAAAA==.',Po='Powerkallo:BAAALAAFFAIIAwAAAA==.',Pr='Prettiibear:BAABLAAECoElAAMYAAgIxB37JgCUAgAYAAgIERv7JgCUAgAfAAEIjx9ObwBfAAAAAA==.Prowl:BAAALAAFFAIIAgAAAA==.',Pt='Ptsd:BAAALAADCgMIAwAAAA==.',Pw='Pwr:BAAALAADCgcIBwAAAA==.',Ra='Raijin:BAAALAAECgYIBgAAAA==.Rakshi:BAAALAADCgcIBwAAAA==.Ramstra:BAAALAAECgMIAwAAAA==.Ravenheart:BAABLAAECoEXAAIeAAcIJhTkXQDAAQAeAAcIJhTkXQDAAQAAAA==.Ravensknight:BAAALAADCgcICgAAAA==.Raíjin:BAACLAAFFIESAAMCAAUIuyU3AgAyAgACAAUIuyU3AgAyAgAZAAMINRS+DgDqAAAsAAQKgSoAAwIACAh9JtgBAHoDAAIACAh9JtgBAHoDABkABwjIGR0mADACAAAA.',Re='Regiina:BAAALAADCgUIBQAAAA==.Rehepaps:BAAALAAECgIIAgAAAA==.Rehgar:BAAALAAECgYICwAAAA==.Reona:BAAALAAECgYIBgABLAAECgYICgADAAAAAA==.Reza:BAAALAAECggICAAAAA==.',Ri='Riptide:BAACLAAFFIEGAAILAAIIbxFoLgB7AAALAAIIbxFoLgB7AAAsAAQKgSAAAgsACAjuHVkfAHACAAsACAjuHVkfAHACAAAA.Riqor:BAAALAAECgYIAQAAAA==.Rizzladin:BAAALAAECgIIAgAAAA==.',Ro='Robo:BAAALAADCggICAAAAA==.Roq:BAAALAAECgMIBgAAAA==.',Rt='Rt:BAAALAAECgYIDQAAAA==.',Ru='Rubberkat:BAAALAADCgcIBwAAAA==.',Sa='Sahaer:BAAALAAECgYICAAAAA==.',Se='Seleenium:BAAALAAECgQIBAAAAA==.Serenhai:BAAALAAECgUIBgAAAA==.',Sh='Shamaara:BAABLAAECoEpAAILAAgIRhQESgDPAQALAAgIRhQESgDPAQAAAA==.Shamanom:BAAALAADCgcIBwABLAAECgYIEQADAAAAAA==.Shastam:BAAALAADCgIIAgAAAA==.Sherane:BAAALAADCgQIBwAAAA==.Shplain:BAABLAAECoEWAAIOAAgISh+VIgDAAgAOAAgISh+VIgDAAgAAAA==.Shádymiss:BAAALAAECgEIAQABLAAECggINgAQAKAdAA==.',Si='Simonkz:BAABLAAECoEnAAIgAAgIhx0jDACyAgAgAAgIhx0jDACyAgAAAA==.Sioli:BAAALAADCggICAAAAA==.',Sk='Skrauhg:BAAALAADCgEIAQAAAA==.',Sl='Sloeberken:BAAALAAECgQICgAAAA==.',So='Soliidd:BAAALAAECgEIAQAAAA==.',Sp='Sparklefarts:BAABLAAECoEgAAMZAAgI9A/cOQDJAQAZAAgI9A/cOQDJAQACAAgIFwjFQwCBAQAAAA==.',Sq='Squírtlé:BAAALAAECgcIAgAAAA==.',Sr='Sreena:BAAALAADCgEIAQAAAA==.Srümuw:BAAALAADCgcIDQAAAA==.',St='Starfall:BAABLAAECoEgAAIdAAgIGQlSVQAdAQAdAAgIGQlSVQAdAQAAAA==.Stefoto:BAABLAAECoEWAAIQAAgIMQ9ZXgDaAQAQAAgIMQ9ZXgDaAQAAAA==.Stârz:BAAALAAECgIIAgAAAA==.',Sw='Swiftcurse:BAAALAADCgcIDwAAAA==.Swiftdemon:BAAALAAECgMIAwAAAA==.Swiftheal:BAAALAADCggIEgAAAA==.Swiftsham:BAAALAADCggIDgAAAA==.Swiftwarrior:BAAALAADCgYIBgAAAA==.Swunk:BAAALAAFFAIIAgAAAA==.',Sy='Sylas:BAAALAAECgYIBgABLAAECggIKAABABsjAA==.',['Sé']='Séntínél:BAABLAAECoEbAAITAAgI3A7ObQDfAQATAAgI3A7ObQDfAQAAAA==.',Ta='Tarnarya:BAABLAAECoEkAAIhAAgIEBpXCQCBAgAhAAgIEBpXCQCBAgAAAA==.Taukun:BAAALAAECgMIBQAAAA==.',Te='Teddybambino:BAAALAAECgcIDwAAAA==.Tera:BAAALAADCgcIBwAAAA==.',Th='Thedruid:BAAALAADCgYIBgABLAAECggIKwAUABglAA==.Thedx:BAABLAAECoErAAIUAAgIGCUPAgBVAwAUAAgIGCUPAgBVAwAAAA==.Thehayman:BAAALAADCgQIBAAAAA==.Thrìll:BAABLAAECoEmAAIWAAgITSSMBABCAwAWAAgITSSMBABCAwAAAA==.Thunderchiëf:BAABLAAECoEgAAILAAgIziGMCgD4AgALAAgIziGMCgD4AgAAAA==.Théren:BAAALAADCgcIBwAAAA==.',Ti='Tick:BAABLAAECoEcAAIPAAcIWBd9QwD1AQAPAAcIWBd9QwD1AQAAAA==.',To='Torckel:BAABLAAECoEUAAMPAAcIChsJNQAyAgAPAAcIChsJNQAyAgAbAAQITBD8WQDTAAAAAA==.',Tr='Trumpservant:BAAALAADCgcIBwAAAA==.',Tw='Twidsham:BAAALAAECgYIBgAAAA==.Twigged:BAABLAAECoEgAAIiAAgIax3cAgCrAgAiAAgIax3cAgCrAgAAAA==.',Ul='Ulthra:BAAALAAECgYIBgAAAA==.',Un='Unalak:BAABLAAECoEcAAIBAAcIEx4sLwBBAgABAAcIEx4sLwBBAgAAAA==.',Va='Valkien:BAAALAADCgcIBwAAAA==.Valrius:BAABLAAECoEaAAIBAAgIfx8SEwD0AgABAAgIfx8SEwD0AgAAAA==.Vanduins:BAAALAADCgcIBgAAAA==.Vanhealin:BAAALAAECgQIBAAAAA==.',Ve='Ventron:BAAALAAFFAIIAgAAAA==.',Vi='Violetfury:BAAALAAECgcIBwAAAA==.',Vl='Vladilena:BAAALAAECgYIBgAAAA==.',Vy='Vypiana:BAAALAADCgQIBAAAAA==.',['Võ']='Võrukas:BAAALAADCgUIBQAAAA==.',Wd='Wdk:BAABLAAECoEdAAIeAAcI5yMwGQDHAgAeAAcI5yMwGQDHAgAAAA==.',Wh='Whitejack:BAAALAAECgYIEQAAAA==.',Wi='Willspriest:BAAALAADCgcIBwAAAA==.',Xa='Xaka:BAAALAADCgYIBwAAAA==.Xarxe:BAAALAADCgMIAwAAAA==.',Xe='Xenzil:BAAALAAECgUICgAAAA==.',Xr='Xrina:BAAALAADCggIDQAAAA==.',Xu='Xulu:BAAALAAECgcIBwABLAAECggIKAAZAA4kAA==.',Ye='Yelnasis:BAABLAAECoEVAAITAAcINx0OQQBOAgATAAcINx0OQQBOAgAAAA==.',Yo='Yonige:BAAALAADCggIBwABLAAECgcIBwADAAAAAA==.',Yr='Yrnothan:BAAALAADCgUIBQAAAA==.',Yu='Yumekosan:BAAALAADCgcIBwAAAA==.',Za='Zabra:BAAALAAECgYIDwAAAA==.Zaldarea:BAAALAAECgUIBQAAAA==.',Zh='Zhorith:BAAALAAECgQIBAAAAA==.',Zu='Zukes:BAAALAAECgYIDQABLAAECggIHwAjAGwmAA==.Zukì:BAAALAAECgIIAQABLAAECggIHwAjAGwmAA==.Zukî:BAAALAAECgYIBgAAAA==.',['Ár']='Árchon:BAAALAADCggICAAAAA==.',['Ðe']='Ðeáth:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end