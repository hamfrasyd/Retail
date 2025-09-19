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
 local lookup = {'Warrior-Fury','Priest-Shadow','Shaman-Elemental','Evoker-Devastation','Paladin-Holy','Warrior-Protection','Unknown-Unknown','DeathKnight-Unholy','Mage-Arcane','Paladin-Protection','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Frost','Druid-Feral','Druid-Restoration','Druid-Balance','Shaman-Restoration','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship',}; local provider = {region='EU',realm="Blade'sEdge",name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Aboudy:BAAALAADCgcIDAAAAA==.',Al='Alexander:BAABLAAECoEYAAIBAAgI2Rf+GABUAgABAAgI2Rf+GABUAgAAAA==.Aloja:BAAALAAECgQIBgAAAA==.',Am='Amaliaxx:BAEALAADCggIDgABLAAFFAQIDAACAEoaAA==.',An='Angelbeatty:BAAALAADCgcIBwAAAA==.Angelvoodoo:BAAALAADCggIEAAAAA==.Angerycahlu:BAAALAADCggIFwAAAA==.Annastasya:BAAALAADCggICAAAAA==.',Ar='Araneae:BAAALAAECgIIAgAAAA==.Arcage:BAAALAAFFAIIAgABLAAFFAMIBgADALgYAA==.Arcman:BAACLAAFFIEGAAIDAAMIuBjJBQAEAQADAAMIuBjJBQAEAQAsAAQKgRwAAgMACAiKJLwDAFIDAAMACAiKJLwDAFIDAAAA.Ariaana:BAAALAAECggICgAAAA==.Arven:BAABLAAECoEaAAIEAAgIExxkDACRAgAEAAgIExxkDACRAgAAAA==.Arzeldon:BAAALAADCgEIAQAAAA==.',Au='Aureliya:BAAALAAECgYIBgAAAA==.',Ay='Ayhoel:BAAALAAECgIIAgAAAA==.',Ba='Bahloo:BAAALAAECgMIBQAAAA==.Balorn:BAAALAADCgcIBwAAAA==.Bandana:BAAALAADCggIDAAAAA==.Barbossa:BAAALAAECgcICAAAAA==.',Be='Beinn:BAAALAADCggICAAAAA==.',Bl='Bladè:BAAALAADCggICAAAAA==.',Bo='Bob:BAABLAAECoEaAAIFAAgIehZsCwBOAgAFAAgIehZsCwBOAgAAAA==.Boi:BAAALAAECgYIBgAAAA==.Boston:BAAALAADCggIEAAAAA==.',Br='Braindk:BAAALAADCgUIBQAAAA==.Brainhack:BAAALAADCggICAAAAA==.Breno:BAABLAAECoEaAAMGAAgIeh6bDgArAgABAAgIvRsrFwBlAgAGAAcIAB6bDgArAgAAAA==.Brenthos:BAAALAADCggIDwAAAA==.Brightstars:BAAALAADCgUIBQAAAA==.',Bu='Buffy:BAAALAAECgIIAgAAAA==.Bullbane:BAAALAAECgMIAwAAAA==.',['Bé']='Béat:BAAALAAECgYIDAABLAAECgYIEwAHAAAAAA==.Bért:BAAALAADCgcIEQAAAA==.',['Bó']='Bólt:BAAALAAECgYIBwABLAAECgYIEwAHAAAAAA==.',Ca='Cahlu:BAAALAADCggIEQAAAA==.Caxapok:BAAALAADCggIFgAAAA==.Caylyn:BAAALAAECgMICQAAAA==.',Ch='Chimken:BAAALAADCggICAAAAA==.Chromasta:BAAALAADCgYIBgAAAA==.',Co='Comgo:BAAALAAECgcIEwAAAA==.Constantíné:BAAALAAECggIBwAAAA==.',Da='Dain:BAAALAAECgEIAQABLAAECggIGgAEABMcAA==.Damraseg:BAAALAADCgMIAwAAAA==.Darkvenger:BAABLAAECoEeAAIIAAgIpiPuAQAvAwAIAAgIpiPuAQAvAwAAAA==.Dawncaller:BAAALAAECgMIBAAAAA==.',De='Deathbytoast:BAAALAADCgQIBAAAAA==.Deleteaug:BAAALAAECgEIAQAAAA==.Derius:BAAALAAECgIIAgAAAA==.',Di='Dianthusxx:BAEALAAECgYIDAABLAAFFAQIDAACAEoaAA==.',Do='Doom:BAAALAAECgYIDAAAAA==.',Dr='Dragonboy:BAAALAAECgYICwAAAA==.Dragoneye:BAAALAADCgcICAAAAA==.Dragonyesyes:BAAALAADCgcICQAAAA==.Dreylan:BAAALAAECgEIAQAAAA==.Druéd:BAAALAAECgYIEwAAAA==.',Dw='Dwarfwind:BAAALAAECgYIDgAAAA==.',Eb='Ebriel:BAAALAADCgYIDwAAAA==.',Ec='Ecsztasy:BAAALAADCgcIEAAAAA==.',Eu='Eureeka:BAAALAADCggIFAAAAA==.',Fa='Faithxx:BAEALAAECgIIAwABLAAFFAQIDAACAEoaAA==.',Fi='Firedt:BAAALAADCggIFwAAAA==.',Fl='Flapaholic:BAAALAAECgMIAwAAAA==.Fleurm:BAAALAADCggICAAAAA==.',Ga='Gabbi:BAAALAAECgcIBwAAAA==.Galarath:BAAALAAFFAEIAQAAAA==.Gandraf:BAAALAADCggICwAAAA==.Garnetxx:BAECLAAFFIEMAAICAAQIShpYAgB0AQACAAQIShpYAgB0AQAsAAQKgSAAAgIACAjzJIECAFsDAAIACAjzJIECAFsDAAAA.',Gi='Gingerrogue:BAAALAAECgYIAgAAAA==.',Gn='Gnomosaund:BAAALAADCggIEAAAAA==.',Go='Gorgidas:BAAALAAECgcIEQAAAA==.Gornox:BAAALAADCggICwAAAA==.',Gr='Grimetime:BAAALAADCgQIAwAAAA==.Grizzlebear:BAAALAAECgcIEQAAAA==.Groot:BAAALAADCggIEQAAAA==.',Gu='Gulliblemyth:BAAALAAECgEIAQAAAA==.Gulliblescar:BAAALAADCggIDwAAAA==.',Ha='Haggis:BAAALAADCggIDwAAAA==.Happen:BAAALAADCggICAAAAA==.',He='Headoverheal:BAAALAADCgcIFQAAAA==.Helrus:BAAALAAECgIIAgAAAA==.',Hk='Hknight:BAAALAADCgMIBAAAAA==.',Ho='Hollycoww:BAAALAAECgMIBQAAAA==.Hopexx:BAEALAADCgcIDQABLAAFFAQIDAACAEoaAA==.',Hu='Humbee:BAABLAAECoEZAAIJAAgIgCDvDQDyAgAJAAgIgCDvDQDyAgAAAA==.',In='Innerflame:BAAALAAECgYICwAAAA==.Inzanity:BAAALAADCgcIBgABLAAECggIEAAHAAAAAA==.',Ir='Iron:BAABLAAECoEXAAIKAAcIxCO+BADSAgAKAAcIxCO+BADSAgAAAA==.',Is='Ismilla:BAABLAAECoEUAAILAAcI/iMTEADlAgALAAcI/iMTEADlAgAAAA==.',It='Ithania:BAAALAAECgMIAwAAAA==.',Ji='Jibie:BAAALAADCgIIAgAAAA==.',Jo='Jodkin:BAAALAADCggIDwAAAA==.Jorune:BAAALAADCgIIAgAAAA==.',Ju='Justjinger:BAAALAAECgUICQAAAA==.',Ka='Kaiserus:BAAALAAECgMIAwAAAA==.Kalgar:BAAALAADCggICAAAAA==.Kaoleena:BAAALAADCggIHwAAAA==.Kattigberud:BAAALAAECgcIDwAAAA==.Kazal:BAABLAAECoEaAAQMAAgIWCT+BAA5AwAMAAgIJST+BAA5AwANAAMISSIRPAD5AAAOAAEI0B7HKABfAAAAAA==.',Ke='Kelie:BAAALAADCgcIEAAAAA==.Kelmi:BAABLAAECoEXAAIPAAgIJiRnBABWAwAPAAgIJiRnBABWAwAAAA==.',Kh='Kherin:BAAALAADCggICwAAAA==.Khorex:BAABLAAECoEaAAMLAAgIfBzlFwCjAgALAAgIfBzlFwCjAgAFAAcIFhPzFwC9AQAAAA==.',Ki='Killerb:BAAALAAECgYIDAAAAA==.',Kr='Kreia:BAAALAADCgcIEQAAAA==.',['Ká']='Kálamity:BAAALAAECggICAAAAA==.',La='Lanyto:BAAALAAECgYICgABLAAFFAMIBgADALgYAA==.',Li='Liaponovia:BAABLAAECoEaAAIOAAgI4QuVCQDXAQAOAAgI4QuVCQDXAQAAAA==.Lichtridder:BAAALAADCggICAAAAA==.Lienbloom:BAAALAAFFAIIAgAAAA==.Lienifer:BAAALAAECgYIEgAAAA==.Light:BAAALAAECggICAAAAA==.Lilith:BAAALAAECgYIEAAAAA==.',Lo='Longranger:BAAALAAECgEIAQAAAA==.',Lu='Lunamortis:BAACLAAFFIEGAAIQAAIIshjZEACuAAAQAAIIshjZEACuAAAsAAQKgRUAAhAACAiHHv0dAHcCABAACAiHHv0dAHcCAAAA.Lunasan:BAAALAAECgcICwAAAA==.Lunathalas:BAAALAAECgIIAgAAAA==.Lunoriel:BAAALAADCgcIBwABLAAFFAIIBgAQALIYAA==.',Ly='Lydjas:BAAALAAECgYIEwAAAA==.',Ma='Maerec:BAABLAAECoEXAAIIAAgIqQCdOQBdAAAIAAgIqQCdOQBdAAAAAA==.Magerdas:BAAALAAECgMIBQAAAA==.Maginya:BAAALAADCggIFQAAAA==.Mallet:BAAALAADCgQIBAAAAA==.Mamiwata:BAAALAAECggICAAAAA==.Mandnawe:BAAALAADCggIFAABLAAECgcIEwAHAAAAAA==.Matchr:BAAALAAECgYIBwAAAA==.',Me='Mehreeangry:BAAALAADCggICAAAAA==.Mehreehunt:BAAALAAECgMIAwAAAA==.Meraxes:BAABLAAECoEaAAIBAAgIsiEcCQAKAwABAAgIsiEcCQAKAwAAAA==.',Mi='Midway:BAAALAAECgYICQAAAA==.Misskt:BAAALAADCgcIBwAAAA==.Misspuff:BAAALAAECgQIBwAAAA==.',Mo='Mommydaddy:BAABLAAECoEWAAQRAAgIjB3DDADyAQARAAYIghrDDADyAQASAAgIYQyoMgBhAQATAAEItQjGZQAqAAAAAA==.Mon:BAAALAAECggICAAAAA==.Monjah:BAAALAAECgEIAQAAAA==.Moofasa:BAAALAADCgQIBAAAAA==.Mothy:BAAALAAECgMIBQAAAA==.',['Má']='Márog:BAAALAADCggIHwAAAA==.',Na='Nahla:BAAALAADCgIIAgAAAA==.',Ne='Necrópriest:BAAALAADCggIDgAAAA==.Nemeea:BAAALAADCgYIBgAAAA==.Nemu:BAAALAADCgcIBwAAAA==.Netharia:BAABLAAECoEdAAIJAAgI2x4JFQC3AgAJAAgI2x4JFQC3AgAAAA==.Nevera:BAAALAADCggICAAAAA==.',Ni='Niha:BAAALAADCggICgAAAA==.',No='Noeru:BAABLAAECoEUAAINAAcIWiH7BAC8AgANAAcIWiH7BAC8AgAAAA==.Nows:BAAALAADCggICAAAAA==.',['Ní']='Níght:BAAALAAECgYICAABLAAECgYIEwAHAAAAAA==.',Oa='Oases:BAAALAAECgMIBgAAAA==.',Om='Ombretti:BAAALAADCgMIAwAAAA==.',On='Oniell:BAAALAADCggIDwAAAA==.Onryo:BAAALAADCgYIBgAAAA==.',Pa='Painbringer:BAAALAADCgcIBwAAAA==.Pallidin:BAAALAADCgYIBgAAAA==.Papak:BAAALAAECgIIAgAAAA==.Paraadox:BAAALAADCgcICAAAAA==.Pardofelis:BAAALAADCgcIDQAAAA==.',Ph='Pharmakon:BAAALAAECgYICwAAAA==.Phos:BAAALAAECgcIEAAAAA==.',Pl='Plaguerot:BAAALAAECgUIBgAAAA==.',Po='Powerkallo:BAAALAAECgYICQAAAA==.',Pr='Prettiibear:BAAALAAECggIEwAAAA==.Prowl:BAAALAAECgIIAgAAAA==.',Pw='Pwr:BAAALAADCgcIBwAAAA==.',Ra='Raijin:BAAALAAECgYIBgAAAA==.Rakshi:BAAALAADCgcIBwAAAA==.Ramstra:BAAALAAECgMIAwAAAA==.Ravenheart:BAAALAAECgYICQAAAA==.Ravensknight:BAAALAADCgcICgAAAA==.Raíjin:BAACLAAFFIEIAAICAAMI0SNZAwA0AQACAAMI0SNZAwA0AQAsAAQKgR4AAgIACAiHJdsBAGYDAAIACAiHJdsBAGYDAAAA.',Re='Rehgar:BAAALAADCgMIBAAAAA==.Reona:BAAALAADCgcIDQABLAADCggIFAAHAAAAAA==.Reza:BAAALAADCggICAAAAA==.',Ri='Riptide:BAABLAAECoEUAAIUAAcIyB1YHAAnAgAUAAcIyB1YHAAnAgAAAA==.Riqor:BAAALAADCgYICAAAAA==.Rizzladin:BAAALAAECgEIAQAAAA==.',Ro='Robo:BAAALAADCggICAAAAA==.Roq:BAAALAAECgMIBgAAAA==.',Rt='Rt:BAAALAAECgIIBQAAAA==.',Sa='Sahaer:BAAALAAECgYIAgAAAA==.',Se='Serenhai:BAAALAADCggIEQAAAA==.',Sh='Shamaara:BAABLAAECoEZAAIUAAgI1xPRLQDKAQAUAAgI1xPRLQDKAQAAAA==.Shastam:BAAALAADCgIIAgAAAA==.Sherane:BAAALAADCgQIBwAAAA==.Shplain:BAAALAAECggIDwAAAA==.',Si='Siananda:BAAALAADCggICAAAAA==.Simonkz:BAABLAAECoEYAAIVAAgIXRfvDQA0AgAVAAgIXRfvDQA0AgAAAA==.',Sk='Skrauhg:BAAALAADCgEIAQAAAA==.',Sl='Sloeberken:BAAALAAECgEIAgAAAA==.',So='Soliidd:BAAALAAECgEIAQAAAA==.',Sp='Sparklefarts:BAAALAAECggIEAAAAA==.',Sq='Squírtlé:BAAALAAECgUIAgAAAA==.',Sr='Sreena:BAAALAADCgEIAQAAAA==.Srümuw:BAAALAADCgQIBgAAAA==.',St='Starfall:BAAALAAECggIEAAAAA==.Stefoto:BAAALAAECgUICQAAAA==.Stârz:BAAALAAECgIIAgAAAA==.',Sw='Swiftheal:BAAALAADCggIEgAAAA==.Swiftwarrior:BAAALAADCgYIBgAAAA==.Swunk:BAAALAAECgMIBQAAAA==.',['Sé']='Séntínél:BAAALAAECgcIEgAAAA==.',Ta='Taukun:BAAALAAECgMIBQAAAA==.',Te='Teddybambino:BAAALAAECgcIDwAAAA==.Tera:BAAALAADCgcIBwAAAA==.',Th='Thedx:BAABLAAECoEaAAIWAAgIKSM8AgAwAwAWAAgIKSM8AgAwAwAAAA==.Thehayman:BAAALAADCgQIBAAAAA==.Thrìll:BAABLAAECoEWAAIXAAgIKiN6BQATAwAXAAgIKiN6BQATAwAAAA==.Thunderchiëf:BAAALAAECggIDwAAAA==.',Ti='Tick:BAAALAAECgcIDQAAAA==.',To='Torckel:BAAALAAECgQIBQAAAA==.',Tr='Trumpservant:BAAALAADCgcIBwAAAA==.',Tw='Twidsham:BAAALAAECgYIBgAAAA==.Twigged:BAAALAAECgYIEAAAAA==.',Un='Unalak:BAAALAAECgYIDgAAAA==.',Va='Valkien:BAAALAADCgcIBwAAAA==.Valrius:BAAALAAECggICQAAAA==.Vanduins:BAAALAADCgcIBgAAAA==.Vanhealin:BAAALAADCgUIBQAAAA==.',Vl='Vladilena:BAAALAADCgYIBgAAAA==.',Vy='Vypiana:BAAALAADCgQIBAAAAA==.',Wd='Wdk:BAAALAAECgYIEAAAAA==.',Wh='Whitejack:BAAALAAECgYIBgAAAA==.',Wi='Willspriest:BAAALAADCgcIBwAAAA==.',Xa='Xaka:BAAALAADCgYIBwAAAA==.',Xe='Xenzil:BAAALAAECgIIAgAAAA==.',Ye='Yelnasis:BAAALAAECgYIDQAAAA==.',Yo='Yonige:BAAALAADCggIBwAAAA==.',Yu='Yumekosan:BAAALAADCgcIBwAAAA==.',Za='Zabra:BAAALAAECgQIBwAAAA==.Zaldarea:BAAALAAECgUIBQAAAA==.',Zu='Zukes:BAAALAAECgYICQABLAAECgYIEgAHAAAAAA==.Zukì:BAAALAAECgIIAQABLAAECgYIEgAHAAAAAA==.Zukî:BAAALAAECgYIBgAAAA==.',['Ár']='Árchon:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end