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
 local lookup = {'Warlock-Destruction','DeathKnight-Frost','DeathKnight-Blood','Monk-Windwalker','Paladin-Retribution','Unknown-Unknown','DeathKnight-Unholy','Paladin-Protection','Priest-Shadow','Warrior-Fury','Warrior-Arms','Shaman-Elemental','Priest-Holy','Druid-Restoration','Druid-Feral','Rogue-Assassination','Warlock-Demonology','Mage-Arcane','Hunter-BeastMastery','Druid-Balance','Paladin-Holy','Shaman-Restoration','Warlock-Affliction','DemonHunter-Havoc','Mage-Frost','Shaman-Enhancement','Warrior-Protection','Rogue-Subtlety','Hunter-Marksmanship',}; local provider = {region='EU',realm='Dethecus',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abêndstern:BAABLAAECoEYAAIBAAgIEQr2XgCgAQABAAgIEQr2XgCgAQAAAA==.',Ad='Adremos:BAABLAAECoEpAAMCAAgIWRu9MgCCAgACAAgI7Rq9MgCCAgADAAgIMApyKgDfAAAAAA==.',Ah='Ahmshere:BAAALAAECgQIBwAAAA==.',Ai='Aiakan:BAAALAADCgcICQAAAA==.Aileên:BAAALAAECgMIAQAAAA==.Aishá:BAAALAADCggIGwAAAA==.',Al='Alezar:BAAALAADCggIDAAAAA==.',An='Analijah:BAAALAAECgYICgAAAA==.',Ao='Aopex:BAAALAADCgEIAQAAAA==.',Ap='Apoçalypto:BAAALAAECgYIBwAAAA==.',Ar='Arathon:BAAALAAECgUIBQAAAA==.Artemïs:BAAALAAECgYICgAAAA==.Arthoríos:BAAALAAECggICAABLAAECgcIFwAEAAgXAA==.',As='Assamausi:BAAALAADCgEIAQABLAAECgYIFAAFAN8PAA==.Asterin:BAAALAAECgYIDAAAAA==.',Av='Avathar:BAAALAAECgUICAAAAA==.Avee:BAAALAADCgYIBgAAAA==.',Ay='Ayra:BAAALAAECgMIBAABLAAECgYICQAGAAAAAA==.',Az='Azalèn:BAAALAADCgQIBAABLAAFFAIICAAHAF0hAA==.',Ba='Baass:BAABLAAECoEXAAIIAAcIxRrFGAD9AQAIAAcIxRrFGAD9AQAAAA==.Bamertok:BAAALAAECgcIBwAAAA==.Banabas:BAAALAAECgYIEQAAAA==.Bananabee:BAAALAAECggIEAAAAA==.Banshees:BAAALAAECggICAAAAA==.',Be='Bedrull:BAAALAAECgMIAwAAAA==.',Bl='Blind:BAABLAAECoEWAAIJAAYI0RFsTwBUAQAJAAYI0RFsTwBUAQAAAA==.Bloodsportt:BAAALAAECgEIAQAAAA==.Bloodveil:BAAALAADCggIDwAAAA==.Bláckhórn:BAABLAAECoEYAAIKAAYIDh8+PgAKAgAKAAYIDh8+PgAKAgAAAA==.',Bo='Bonzu:BAAALAAECgYIBwAAAA==.Borsti:BAAALAADCggICAAAAA==.Bowsa:BAAALAAECgIIAgAAAA==.',Br='Brontos:BAABLAAECoEsAAILAAgInSRZAQBIAwALAAgInSRZAQBIAwAAAA==.',Bt='Btx:BAAALAADCggIDwAAAA==.',Bu='Bulsay:BAABLAAECoEVAAMLAAYIdCC9DADrAQAKAAYIwx/yNgAnAgALAAYImBu9DADrAQABLAAFFAMIBgAMAIgRAA==.',['Bâ']='Bâdgírl:BAAALAADCgYIBgAAAA==.',['Bû']='Bûgoo:BAAALAAECggICAAAAA==.',Ca='Caldena:BAAALAADCgMIAwAAAA==.Camyra:BAAALAADCggICAAAAA==.Caramôn:BAAALAADCggICgAAAA==.Cathya:BAABLAAECoEgAAINAAcIBA9OTwB0AQANAAcIBA9OTwB0AQAAAA==.Catman:BAAALAADCgUIBQAAAA==.',Ce='Celestia:BAAALAADCggICAAAAA==.',Ch='Chukuh:BAAALAAECgYIBwAAAA==.',Co='Conek:BAAALAADCgIIAgAAAA==.Contess:BAAALAADCgEIAQABLAAECgYICgAGAAAAAA==.',Cr='Crafclown:BAAALAAECgEIAQAAAA==.Crayson:BAAALAADCgMIAwAAAA==.Creyen:BAAALAAECgIIAgAAAA==.',Da='Dalvor:BAAALAADCgYIBwABLAAFFAIICgAKAB8hAA==.Davyna:BAAALAADCggICQAAAA==.',De='Deathfox:BAAALAADCgYIAgAAAA==.Demontank:BAAALAAECgYIDQAAAA==.',Di='Diesermonk:BAABLAAECoEXAAIEAAcICBffHgDZAQAEAAcICBffHgDZAQAAAA==.',Do='Dondaryon:BAAALAADCgIIAgAAAA==.',Dr='Drabbers:BAAALAAECgEIAQABLAAFFAYIFAAOAK4fAA==.Drainheal:BAACLAAFFIEUAAIOAAYIrh8GAQBJAgAOAAYIrh8GAQBJAgAsAAQKgSEAAw4ACAiFIMULAOECAA4ACAiFIMULAOECAA8AAQjyBVNBAC8AAAAA.Drhexe:BAAALAADCgYIBgAAAA==.Droka:BAAALAADCggICgAAAA==.Drzwikl:BAAALAADCgcIBwAAAA==.Dráz:BAAALAAECggIBwAAAA==.Drúidika:BAAALAAECgYICQAAAA==.',Dt='Dtm:BAAALAAECgQICAAAAA==.',Du='Durungar:BAABLAAECoEXAAIQAAYI9RuVIgDvAQAQAAYI9RuVIgDvAQABLAAFFAMIBgAMAIgRAA==.',['Dä']='Däimonia:BAABLAAECoEkAAMBAAgILw26UgDGAQABAAgILw26UgDGAQARAAQI8Qd9XgDFAAAAAA==.',Es='Escânor:BAAALAADCgcICAAAAA==.',Fe='Femme:BAAALAADCgcIDgAAAA==.Fern:BAABLAAECoEdAAISAAcI5BbBWgDUAQASAAcI5BbBWgDUAQAAAA==.',Fi='Finezh:BAAALAADCgcIAQAAAA==.Fingerinpo:BAAALAAECggIEAAAAA==.',Fk='Fk:BAAALAADCggICAAAAA==.',Fr='Frozenwrath:BAACLAAFFIEIAAMHAAIIXSEIFgBWAAACAAEINCYXYQByAAAHAAEIhhwIFgBWAAAsAAQKgSgAAwcACAhHJRcEABYDAAcACAjgIxcEABYDAAIABwjtIeslALYCAAAA.',Fu='Fuckgravity:BAAALAADCggICAAAAA==.Funkuchen:BAAALAADCgcIBwAAAA==.',Ga='Gaffel:BAAALAADCggICAAAAA==.Galdrian:BAAALAAECgYIEgAAAA==.Galfor:BAAALAAECgcIEwABLAAFFAMIBgAMAIgRAA==.Gambino:BAAALAAECgUIBQAAAA==.Gawas:BAAALAADCgMIAwAAAA==.',Go='Goemon:BAABLAAECoEaAAIEAAcIgSL4DwCAAgAEAAcIgSL4DwCAAgAAAA==.Goldosh:BAAALAADCgUIBgAAAA==.Gormara:BAAALAADCgcIDQAAAA==.Gorschar:BAACLAAFFIEGAAIMAAMIiBHPEADuAAAMAAMIiBHPEADuAAAsAAQKgRwAAgwACAimG7seAIsCAAwACAimG7seAIsCAAAA.Gotta:BAAALAAECgYIBgAAAA==.',Gr='Gréngster:BAAALAADCgcIEQAAAA==.Grünklein:BAAALAAECgYICQAAAA==.',Gu='Guldano:BAABLAAECoEaAAIJAAgI5hYPIwA+AgAJAAgI5hYPIwA+AgABLAAFFAMIBgAMAIgRAA==.',Gw='Gwizdo:BAABLAAECoEbAAITAAYIPh5AWQDXAQATAAYIPh5AWQDXAQAAAA==.',Ha='Haaldarin:BAAALAAECgYICAAAAA==.',He='Helldorado:BAABLAAECoEdAAIIAAgI0h7WCQC2AgAIAAgI0h7WCQC2AgAAAA==.',Ik='Ikumi:BAAALAAECggICAAAAA==.',Il='Illuena:BAAALAADCggIDQABLAAECgcIDQAGAAAAAA==.Illyasviell:BAAALAAECgYICwAAAA==.',Ip='Ipheion:BAABLAAECoEXAAIUAAgIaBacNgCxAQAUAAgIaBacNgCxAQAAAA==.',Iq='Iqpl:BAABLAAECoEmAAIEAAgIkB7sCwC6AgAEAAgIkB7sCwC6AgAAAA==.',Is='Isakara:BAABLAAECoEdAAIOAAYIyRrZSQCBAQAOAAYIyRrZSQCBAQAAAA==.Ishadk:BAAALAAECgUIBQAAAA==.Ishah:BAACLAAFFIEQAAIMAAUIOB70BQDaAQAMAAUIOB70BQDaAQAsAAQKgSsAAgwACAjOJJcEAGMDAAwACAjOJJcEAGMDAAAA.',Ja='Jabjapriest:BAAALAAECgcIDgABLAAFFAMICAAVADkSAA==.Jaevo:BAAALAADCgcIDQAAAA==.Jagakan:BAAALAADCgMIAwABLAAFFAUIDwANAGgPAA==.',Ka='Kaeldrin:BAAALAAFFAEIAQAAAA==.Kariria:BAAALAADCgcIBwAAAA==.Kavarill:BAAALAADCgYIBgAAAA==.Kazzhul:BAAALAAECgcIDgAAAA==.',Ke='Kelthazad:BAAALAADCgEIAQAAAA==.Kernighan:BAABLAAECoEkAAIWAAcILCMeFQCwAgAWAAcILCMeFQCwAgAAAA==.',Kh='Khazerak:BAACLAAFFIEKAAIRAAIIxiSgAwDdAAARAAIIxiSgAwDdAAAsAAQKgR0ABBEACAhoItMEAAgDABEACAhQIdMEAAgDAAEAAgjcEIDAAHkAABcAAQh5JowsAHIAAAAA.Khazrak:BAABLAAECoEUAAITAAYI9SG+RAARAgATAAYI9SG+RAARAgABLAAFFAIICgARAMYkAA==.',Ki='Kiladar:BAAALAADCgQIBAAAAA==.Kindermilch:BAABLAAECoEaAAIYAAgIYRxrOQBRAgAYAAgIYRxrOQBRAgAAAA==.Kirchenrolf:BAAALAAECgMIAwABLAAFFAYIEgARABodAA==.Kiri:BAAALAAECggICAAAAA==.',Ko='Kopfwunde:BAAALAADCgYIBgAAAA==.',Kr='Krem:BAAALAAECgYIDAAAAA==.Krâksham:BAAALAAECgYIDQAAAA==.',['Kÿ']='Kÿlíêmìrøgûë:BAAALAADCgYIBgAAAA==.',La='Lailaleon:BAAALAADCgIIAgAAAA==.Lasskickerin:BAAALAADCggIEAABLAAECggIHQAIANIeAA==.',Le='Legula:BAAALAAECgUIBgAAAA==.Legulana:BAAALAADCgIIAgAAAA==.Lenariá:BAAALAAECgYIBgAAAA==.',Li='Lilliana:BAABLAAECoEbAAIRAAcIRRkbGQATAgARAAcIRRkbGQATAgAAAA==.Lissii:BAAALAADCgYIBgAAAA==.',Lo='Lorani:BAAALAAECgcIBwABLAAECggIGQAFANUdAA==.',Ly='Lyínn:BAAALAADCgcIBwAAAA==.',['Lâ']='Lâphira:BAAALAADCgEIAQAAAA==.',['Lí']='Línch:BAAALAAECgYIDAAAAA==.',Ma='Maaxzibit:BAAALAADCgcIBwABLAADCggICAAGAAAAAA==.Magnador:BAABLAAECoElAAIFAAgIKR0bKQCnAgAFAAgIKR0bKQCnAgAAAA==.Massamafaxen:BAAALAAECgYIDQAAAA==.',Mc='Mcrip:BAAALAAECgcIBwAAAA==.',Me='Megumin:BAABLAAECoEZAAMZAAcIehwiFQBTAgAZAAcIehwiFQBTAgASAAEIuglk4AAzAAABLAAECgcIFwAEAAgXAA==.Mekaar:BAAALAADCggICAAAAA==.Mesfer:BAAALAADCgcIBwAAAA==.',Mi='Miishuna:BAABLAAECoEjAAMMAAgIdiMOCABDAwAMAAgIdiMOCABDAwAWAAEI1wLaHAEZAAABLAAECggILAAPAIAiAA==.Misantropie:BAAALAAECgYIBgAAAA==.',Mo='Moroqt:BAAALAADCggIDQAAAA==.Mortanius:BAAALAADCgYICAAAAA==.',Mu='Mupf:BAAALAAECgYIDwAAAA==.Murdin:BAAALAAECgYIDAAAAA==.',['Mä']='Mäxzibit:BAAALAADCggICAABLAADCggICAAGAAAAAA==.',['Mé']='Méngís:BAAALAAECgcIBwABLAAECggINQAYAOkkAA==.',['Mê']='Mêngiz:BAABLAAECoE1AAIYAAgI6SQgDQAxAwAYAAgI6SQgDQAxAwAAAA==.',Na='Naera:BAAALAAECgYIDAAAAA==.Nanî:BAAALAADCggIDwAAAA==.Naradan:BAAALAADCggIDAAAAA==.Nargatzwog:BAAALAAECgEIAQAAAA==.Navori:BAABLAAECoEUAAIFAAYI3w+PuQBRAQAFAAYI3w+PuQBRAQAAAA==.',Ne='Nedya:BAAALAAECgYICAAAAA==.Nell:BAAALAAECggICAAAAA==.Nephilos:BAAALAADCgQIBAAAAA==.Nerodon:BAAALAAECgYICgAAAA==.Nerolan:BAAALAAFFAIIAgABLAAFFAIICAAHAF0hAA==.Nevasjin:BAAALAAECgYIBAAAAA==.',['Nï']='Nïx:BAAALAADCgIIAgAAAA==.',Ok='Okinan:BAABLAAECoEUAAIEAAYIohreIQC/AQAEAAYIohreIQC/AQABLAAFFAMIBgAMAIgRAA==.',On='Onebutton:BAAALAAECgYIBgAAAA==.',Pi='Pieslisenpai:BAAALAADCggICAAAAA==.Pirulita:BAAALAAECgIIAgAAAA==.',Po='Powershoot:BAAALAAECgEIAQAAAA==.',Pu='Punji:BAAALAAECggIDQAAAA==.Punjí:BAAALAAECgcIEgAAAA==.',Py='Pythonisam:BAAALAADCgIIAgAAAA==.',['Pü']='Püpyy:BAABLAAECoEVAAIaAAYI3iAmCgAxAgAaAAYI3iAmCgAxAgAAAA==.',Qa='Qah:BAAALAAECgYIDAAAAA==.',Ro='Robertos:BAAALAADCgQIBAAAAA==.',Ru='Rujin:BAABLAAECoEaAAIIAAYIxwxAOgAIAQAIAAYIxwxAOgAIAQAAAA==.',['Rî']='Rîn:BAAALAAECgIIAgAAAA==.',Sa='Sandrik:BAAALAAECgcIEwAAAA==.',Sc='Schôrsch:BAAALAADCggICAAAAA==.',Se='Señora:BAAALAADCgUIBQABLAAFFAUIDwANAGgPAA==.',Sh='Shaikun:BAAALAADCggICgAAAA==.Shalia:BAAALAADCgYICwABLAAECgYIFAAFAN8PAA==.Shayhulud:BAAALAAECggIEAAAAA==.Shirâj:BAAALAAECgIIAgAAAA==.Shurugaa:BAAALAAECgYICAAAAA==.Shurugawarry:BAABLAAECoEUAAIbAAYIqROYPgBCAQAbAAYIqROYPgBCAQAAAA==.Shánk:BAABLAAECoEmAAIFAAgIJB+pIwDAAgAFAAgIJB+pIwDAAgAAAA==.Shý:BAAALAAECggICAAAAA==.',Sk='Skillumina:BAAALAAECgYICAAAAA==.',Sl='Slingshot:BAACLAAFFIEIAAITAAIIrSP5GwC1AAATAAIIrSP5GwC1AAAsAAQKgR0AAhMACAjLJXkJADQDABMACAjLJXkJADQDAAEsAAUUAggIAAcAXSEA.',Sm='Smauganon:BAAALAAECgYIDwABLAAFFAMIBgAMAIgRAA==.',So='Soulslayer:BAACLAAFFIEIAAIBAAMI7QhkHwC/AAABAAMI7QhkHwC/AAAsAAQKgSYAAgEACAjTFoE7AB4CAAEACAjTFoE7AB4CAAAA.',Sp='Spektrum:BAAALAAECgcIEwAAAA==.',Sq='Squanchi:BAAALAADCgcIBwAAAA==.',St='Sternchên:BAAALAADCgQIBAABLAAECgYIFAAFAN8PAA==.',Su='Supstral:BAAALAAECgYIEQAAAA==.',Sv='Svobo:BAAALAADCggIJgAAAA==.',['Sæ']='Sæmmy:BAAALAAECgYICAAAAA==.',Ta='Tavilá:BAABLAAECoEZAAIFAAgI1R0jKwCeAgAFAAgI1R0jKwCeAgAAAA==.',Te='Teylor:BAABLAAFFIEJAAMMAAUIdQnaCQB2AQAMAAUIdQnaCQB2AQAWAAIIsB5tHACwAAABLAAFFAgIFgAVAPoMAA==.',Ti='Tiesta:BAAALAAECgYIDQAAAA==.Tildá:BAABLAAECoEUAAMBAAYIlhOaZQCNAQABAAYIlhOaZQCNAQAXAAEIQgfhPwAsAAAAAA==.',To='Todesmarf:BAAALAAECgcIDQAAAA==.Toitoi:BAAALAADCgMIBAAAAA==.Tomimba:BAAALAADCgcIBwAAAA==.Toto:BAAALAAECgcICgAAAA==.',Tr='Triligon:BAAALAADCgMIAwABLAAECgYICQAGAAAAAA==.',Tu='Turnschuhman:BAAALAAECgUICAAAAA==.',Tw='Tweyen:BAAALAADCggIDwAAAA==.',Ty='Tyroth:BAAALAAECggICAAAAA==.',Ve='Venem:BAAALAAECgMIAwAAAA==.Venturian:BAAALAADCggIDQAAAA==.Verania:BAAALAAECgEIAQABLAAECgYICgAGAAAAAA==.Veros:BAABLAAECoEXAAMHAAcIchecFwDqAQAHAAcIOxWcFwDqAQADAAcInROwFwCqAQAAAA==.',Vi='Visji:BAAALAAECgcIBwAAAA==.',Vr='Vrakor:BAAALAADCgMIAwAAAA==.',Vu='Vulpaxx:BAAALAADCgYIBgAAAA==.',['Ví']='Vírus:BAAALAAECgIIAgAAAA==.',Wa='Warshock:BAABLAAECoErAAIWAAgIiSM/BwAZAwAWAAgIiSM/BwAZAwAAAA==.',Wi='Widogard:BAAALAADCggICAABLAAECggICAAGAAAAAA==.',Wu='Wurzelberta:BAAALAAECgYIBgAAAA==.',Xa='Xatas:BAAALAAECgYIBgAAAA==.',Xe='Xenoros:BAABLAAECoEbAAIVAAcI7huGGAAfAgAVAAcI7huGGAAfAgAAAA==.',Ya='Yakuzor:BAACLAAFFIELAAIQAAMIIiOiBwAYAQAQAAMIIiOiBwAYAQAsAAQKgSoAAxAACAhXJbEBAGIDABAACAhXJbEBAGIDABwAAQiXCeREADEAAAAA.',Yo='Yoru:BAAALAADCgcIBwAAAA==.',Za='Zagmoth:BAAALAAECgYIDAABLAAFFAMIBgAMAIgRAA==.Zarroc:BAABLAAECoEjAAQLAAgIhxWWEgCMAQALAAgIURSWEgCMAQAbAAcIZxELNwBqAQAKAAMIeAaGvABuAAAAAA==.',Ze='Zerokz:BAAALAADCggICAAAAA==.',Zi='Zilfallon:BAABLAAECoEjAAIdAAcItRObRQCHAQAdAAcItRObRQCHAQAAAA==.',['Zê']='Zêrekthul:BAAALAAECgYIAQABLAAFFAIICAAHAF0hAA==.',['Àk']='Àkìrá:BAAALAAECgMIAwAAAA==.',['Âr']='Ârkano:BAAALAADCgYIBgAAAA==.',['És']='Ésmé:BAAALAAECgMIAgAAAA==.',['Ûl']='Ûltima:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end