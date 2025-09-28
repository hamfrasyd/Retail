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
 local lookup = {'DeathKnight-Blood','Warrior-Fury','Paladin-Retribution','Hunter-BeastMastery','Druid-Restoration','Shaman-Elemental','DeathKnight-Unholy','Shaman-Restoration','Druid-Balance','Unknown-Unknown','Hunter-Marksmanship','Paladin-Protection','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Mage-Arcane','Monk-Windwalker','Druid-Feral','DeathKnight-Frost','Mage-Fire','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Arms','Hunter-Survival',}; local provider = {region='EU',realm='Ulduar',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ae='Aeëtes:BAABLAAECoEXAAIBAAYIhxcXGgCLAQABAAYIhxcXGgCLAQAAAA==.',Ai='Airvossone:BAAALAAECgIIAwAAAA==.',Al='Alabkuhlabär:BAAALAAECgcIEgAAAA==.Alector:BAABLAAECoEtAAICAAgIKxpiLgBOAgACAAgIKxpiLgBOAgAAAA==.Aleona:BAAALAADCgQIBAAAAA==.',An='Andrenda:BAAALAADCggIGAAAAA==.',Ap='Apollo:BAABLAAECoEeAAIDAAcIIB9fOABqAgADAAcIIB9fOABqAgAAAA==.',Ar='Arcadius:BAAALAADCggIDwAAAA==.Arcticor:BAAALAAFFAIIAgAAAA==.Arithawn:BAABLAAECoEdAAIEAAgIbxicQQAbAgAEAAgIbxicQQAbAgAAAA==.Arlathiel:BAABLAAECoEZAAIFAAcImxSvRgCNAQAFAAcImxSvRgCNAQAAAA==.Aruk:BAAALAAECgMIAwAAAA==.',As='Ashitaka:BAAALAAECgMICAAAAA==.',Az='Aza:BAAALAAECgEIAQAAAA==.Azara:BAAALAADCggICwAAAA==.',['Aü']='Aü:BAAALAAECggICAAAAA==.',Ba='Baratos:BAAALAADCggICAAAAA==.Baval:BAAALAADCgcIBwAAAA==.',Be='Beutlîn:BAAALAADCgcIBwAAAA==.',Bi='Bienenstich:BAAALAADCgYIBgAAAA==.Bislipur:BAABLAAECoEVAAIGAAcIuhABSgCyAQAGAAcIuhABSgCyAQAAAA==.',Bl='Bloodangel:BAACLAAFFIEGAAIHAAIIFxwwCgCxAAAHAAIIFxwwCgCxAAAsAAQKgSIAAgcACAigHk4MAHkCAAcACAigHk4MAHkCAAAA.Blóodangel:BAAALAAECgcIBwABLAAFFAIIBgAHABccAA==.',Br='Braindeath:BAAALAADCggICAAAAA==.Brucee:BAAALAAECgcICwAAAA==.',Bu='Bundi:BAAALAAFFAIIAgAAAA==.Bundih:BAAALAADCgYIBgAAAA==.Bundiqt:BAAALAADCggIDAAAAA==.Buzza:BAAALAADCgQIBAAAAA==.',Ca='Caacrinolas:BAAALAAECgcIEQAAAA==.Carato:BAAALAAECgcIEgAAAA==.Cassedi:BAAALAAECgUICQAAAA==.Cassedî:BAAALAADCgcICgAAAA==.Catonia:BAAALAAECgMICAAAAA==.Catschvank:BAAALAAECgcICwAAAA==.',Ce='Cesa:BAAALAAECgQICAAAAA==.',Ch='Chadirra:BAAALAADCgEIAQAAAA==.Cheesê:BAAALAADCggICQAAAA==.Chelchia:BAAALAAECgMICAAAAA==.Chellesia:BAAALAAECgEIAQAAAA==.Cherubín:BAAALAAECgEIAQAAAA==.Chiik:BAAALAADCgQIBAAAAA==.',Cr='Crassus:BAAALAAECgQICAAAAA==.',Cy='Cyliane:BAABLAAECoEVAAMGAAYIQx8OPADrAQAGAAYIQx8OPADrAQAIAAMIUw77GwEbAAABLAAFFAMIBwAJADkZAA==.',Da='Dajanera:BAAALAADCgMIAwAAAA==.Daki:BAAALAADCggIEAAAAA==.Daya:BAAALAAECgMIBgAAAA==.',De='Demigðd:BAAALAADCgYIBgAAAA==.Derdickemønk:BAAALAAECgMICAAAAA==.Devidon:BAAALAAECgMIBgAAAA==.',Dl='Dlinx:BAAALAAECgcIEQAAAA==.',Do='Dobrinja:BAAALAADCggICAABLAAECgcIEQAKAAAAAA==.Donhexa:BAAALAAECggIBAAAAA==.',Dr='Drakonos:BAAALAAECggIDwAAAA==.Draxastor:BAAALAAECgMIBQAAAA==.Drukra:BAABLAAECoEiAAMEAAgI5SOwFgDdAgAEAAgIxiKwFgDdAgALAAgIyRvBGgB5AgAAAA==.Dràco:BAAALAADCgMIAwAAAA==.',Du='Dudurus:BAAALAADCggICQAAAA==.',['Dá']='Dáryl:BAAALAAECgYIBgAAAA==.',['Dø']='Døncamillø:BAAALAADCgMIAwAAAA==.',Ea='Easý:BAAALAADCggIDgABLAAECggIHAAEAO8aAA==.',Ef='Efix:BAAALAADCgMIAwAAAA==.',El='Elchknecht:BAAALAAECgcICAAAAA==.Eliela:BAAALAAECgMICAAAAA==.',En='Enallia:BAAALAADCggIFgAAAA==.',Ey='Eyeliner:BAAALAADCgYIBgAAAA==.',Fa='Faciella:BAAALAAECgUIBQAAAA==.Faerwynd:BAACLAAFFIEGAAIMAAII2RaACwCUAAAMAAII2RaACwCUAAAsAAQKgScAAwwACAiiHjoKAK0CAAwACAiIHjoKAK0CAAMAAgjiHe0iAWYAAAAA.',Fe='Fendris:BAAALAAECgYIBgABLAAFFAIIAgAKAAAAAA==.',Fi='Fiesealteoma:BAABLAAECoEUAAQNAAcIsBADPABUAQANAAYIbg0DPABUAQAOAAUIQxB8KQAWAQAPAAYIGQlmEQAGAQAAAA==.',Fl='Flamesword:BAAALAAECggIEwAAAA==.',Fo='Foxxylove:BAAALAADCggIDwAAAA==.',Fr='Freazz:BAAALAAECgIIAgAAAA==.Fritz:BAAALAADCgcIDQABLAAECgcIDQAKAAAAAA==.',['Fé']='Féana:BAAALAADCgEIAQAAAA==.',Ge='Geileelfe:BAAALAAECgYIBwAAAA==.Genos:BAAALAADCgYIBgAAAA==.',['Gé']='Gérin:BAAALAAECgEIAQAAAA==.',Ha='Hanako:BAAALAAECgYICQAAAA==.Hannáh:BAABLAAECoEmAAMQAAcIQBqFOgAiAgAQAAcItBmFOgAiAgARAAUIrBDMFQBGAQAAAA==.',He='Heimdalx:BAABLAAECoEUAAIMAAYIIxZkKgBvAQAMAAYIIxZkKgBvAQAAAA==.Helgazocktt:BAAALAADCgMIAwAAAA==.Hellknight:BAAALAAECgcIBgAAAA==.Hellraiser:BAAALAAECgcIEwAAAA==.',Ir='Ironjaws:BAAALAAECgMIBQAAAA==.',Is='Iseria:BAAALAAFFAIIAwAAAA==.Isilra:BAAALAAECgYIBgAAAA==.Isiría:BAAALAADCgcIEwAAAA==.Isuzu:BAAALAADCgcIDgAAAA==.',Ja='Jaélyn:BAAALAAECgMIAwAAAA==.',Je='Jeeme:BAABLAAECoEbAAISAAcIzR6zDwB0AgASAAcIzR6zDwB0AgAAAA==.',Ji='Jiindu:BAAALAAECgEIAgAAAA==.',Jr='Jre:BAAALAADCgUIBQAAAA==.',['Jø']='Jøker:BAAALAADCgEIAQAAAA==.',Ka='Kagemage:BAAALAADCgcIEgAAAA==.',Ke='Keno:BAAALAADCgcIBwAAAA==.',Ki='Kidd:BAAALAADCgcIDQAAAA==.Kijuka:BAAALAAECgQIBAAAAA==.Killbar:BAAALAAECgYICgABLAAECggIGQAFAJEYAA==.',Kn='Knolam:BAAALAADCgcIBwABLAAECgcICwAKAAAAAA==.',Ko='Kompsaa:BAAALAAECgcIEwAAAA==.Kopfschuss:BAAALAADCgcIBwAAAA==.',Kr='Krawozi:BAABLAAECoEUAAMTAAYIkRPoGgBoAQATAAYIkRPoGgBoAQAUAAUIZQlDRQDxAAAAAA==.Kreshnak:BAABLAAECoEZAAIQAAgI1xj2MwA/AgAQAAgI1xj2MwA/AgAAAA==.',Kw='Kwang:BAAALAAFFAIIAgAAAA==.',['Ká']='Káiri:BAABLAAECoEpAAIDAAgIniGKKwCdAgADAAgIniGKKwCdAgAAAA==.Kármà:BAAALAADCgQIBAAAAA==.',['Kó']='Kórlic:BAAALAAECgYIBgABLAAECggIHQAEAG8YAA==.',La='Lance:BAAALAAECgYICgAAAA==.Lawia:BAAALAAECggIEAAAAA==.Lazalo:BAAALAAECgcIEQAAAA==.',Le='Leonus:BAAALAAECgQICAAAAA==.Leonxx:BAAALAADCgEIAQAAAA==.Lexyprots:BAAALAADCgUIBQABLAAECgcIEQAKAAAAAA==.Lexyshoxx:BAAALAAECgcIEQAAAA==.',Li='Lillet:BAABLAAECoEXAAIGAAYI2wchcwAlAQAGAAYI2wchcwAlAQAAAA==.',Lo='Lochimsocken:BAABLAAECoE6AAIPAAgI0Rs4BQBWAgAPAAgI0Rs4BQBWAgAAAA==.Lolligoanimâ:BAAALAAECgMIAwAAAA==.Lolly:BAAALAAECgUIBwAAAA==.Longschlóng:BAABLAAECoEWAAICAAgIZRNXPQAOAgACAAgIZRNXPQAOAgAAAA==.Lorelei:BAAALAAECgMICAAAAA==.',Lu='Lucille:BAAALAADCgMIAwAAAA==.Luilania:BAAALAAECgEIAgAAAA==.Lumyr:BAAALAAECgcIEwAAAA==.Lunamis:BAAALAADCgIIAgAAAA==.Lunasia:BAAALAADCgYIBgAAAA==.',Ly='Lynn:BAAALAAECgcICQAAAA==.',['Lâ']='Lâvia:BAAALAAECgYIBgAAAA==.',Ma='Magicdragon:BAABLAAECoEZAAIVAAgIvBa6RwAQAgAVAAgIvBa6RwAQAgAAAA==.Malenia:BAAALAAECgYICAAAAA==.Matagi:BAAALAAECgUIBwAAAA==.',Me='Mechamitch:BAACLAAFFIEGAAIWAAIIghYQDACaAAAWAAIIghYQDACaAAAsAAQKgSgAAhYACAgyIK4KAM4CABYACAgyIK4KAM4CAAAA.Medioz:BAABLAAECoEeAAICAAcIqBpgNgAqAgACAAcIqBpgNgAqAgAAAA==.Melodia:BAAALAADCgcIBwAAAA==.Mepeilo:BAAALAADCgcIDAAAAA==.Meridia:BAAALAAECgEIAQAAAA==.Merlax:BAAALAAECgYIEgAAAA==.Meshadorem:BAAALAADCggICAAAAA==.',Mi='Milkaskjomi:BAAALAADCggICAAAAA==.Minatsuki:BAAALAAECgMIBAAAAA==.Mindaya:BAAALAAECgMIAwAAAA==.Minilie:BAAALAADCgYIBgABLAAECggIHAAEAO8aAA==.Mitchi:BAAALAAECggICAABLAAFFAIIBgAWAIIWAA==.',Mo='Monutaria:BAABLAAECoEXAAIDAAYIFRh6jACiAQADAAYIFRh6jACiAQAAAA==.Mooncat:BAACLAAFFIEHAAIJAAMIORkqDgC7AAAJAAMIORkqDgC7AAAsAAQKgSEABAkACAgaIq4bAFkCAAkABwiJIa4bAFkCAAUABgglIH4jADECABcAAQjAEmU/ADcAAAAA.Mor:BAAALAAECgYICQABLAAECggIHQAEAG8YAA==.',['Mî']='Mîtchi:BAAALAAECgQIBAABLAAFFAIIBgAWAIIWAA==.',Na='Nahilne:BAAALAAECgUIBgABLAAECggIIgAWAPQVAA==.Nakaro:BAAALAADCggICAAAAA==.',Ne='Nebeloli:BAAALAAECggIEAAAAA==.',Nu='Nunchok:BAAALAAECgYIBgAAAA==.Nurf:BAABLAAECoEdAAIGAAcI2x+4IgBxAgAGAAcI2x+4IgBxAgAAAA==.',Ny='Nyce:BAAALAADCgUIBQABLAAECggIHwAGAEofAA==.',['Nâ']='Nârâ:BAAALAADCgYIBwAAAA==.',['Nó']='Nóctua:BAABLAAECoEUAAIEAAYIphVnggB5AQAEAAYIphVnggB5AQAAAA==.',Od='Oderschvank:BAABLAAECoEhAAQYAAgI1RH9gwC6AQAYAAgI1RH9gwC6AQABAAUI2wewLgCyAAAHAAEIhQUJWAApAAAAAA==.',Ol='Oldybutgoldy:BAAALAADCggIDQAAAA==.',Pa='Papalegba:BAABLAAECoEXAAIQAAYICw7ZgABFAQAQAAYICw7ZgABFAQAAAA==.',Pe='Peheleas:BAAALAAECgQIBwAAAA==.',Ph='Philux:BAAALAAECgMICAAAAA==.',Pl='Playman:BAAALAAECggICAAAAA==.',Po='Ponter:BAAALAAECgcIEQAAAA==.Poro:BAAALAAECgMIAwAAAA==.',Pu='Pumpkinhead:BAAALAAECgIIAgAAAA==.',['Pè']='Pèppì:BAAALAAECgQIBAAAAA==.',['Pé']='Péppì:BAAALAAECgEIAQAAAA==.',Ra='Ragosh:BAABLAAECoEdAAIEAAgIsxmUOQA3AgAEAAgIsxmUOQA3AgAAAA==.Rainweather:BAACLAAFFIEGAAIZAAIIjwYnBQCIAAAZAAIIjwYnBQCIAAAsAAQKgSkAAhkACAgmGM0DAGICABkACAgmGM0DAGICAAAA.Raljin:BAAALAADCgcIEwAAAA==.Ray:BAAALAAECgMIAwAAAA==.',Re='Regínald:BAABLAAECoEvAAILAAgI7SMyBwAnAwALAAgI7SMyBwAnAwAAAA==.',['Rà']='Rày:BAAALAADCggICAAAAA==.',['Rî']='Rîse:BAAALAADCgcICwAAAA==.',Sa='Saona:BAAALAAECgUIDQAAAA==.Saphir:BAAALAADCggIEAABLAAECgcIEQAKAAAAAA==.',Sc='Schleichero:BAAALAADCggIGAAAAA==.Schmittyy:BAABLAAECoEUAAIEAAYIrw1JpwAxAQAEAAYIrw1JpwAxAQAAAA==.',Se='Seraphyra:BAABLAAECoEUAAIaAAYI3xwVMwDxAQAaAAYI3xwVMwDxAQAAAA==.',Sh='Shiero:BAAALAAFFAMIAwAAAA==.Shiik:BAACLAAFFIEGAAMaAAIIoSKVFQDFAAAaAAIIoSKVFQDFAAAbAAIIqhmOFgCXAAAsAAQKgSUAAxsACAhJJUQEAFgDABsACAhJJUQEAFgDABoAAwjtI6RjACwBAAAA.Shik:BAABLAAECoEiAAIcAAgIoiUuBABuAwAcAAgIoiUuBABuAwAAAA==.Shyro:BAAALAADCggICAAAAA==.Shângria:BAAALAADCgcIGAAAAA==.',Si='Sickdude:BAEBLAAECoEUAAIDAAYIMyH1VQAUAgADAAYIMyH1VQAUAgAAAA==.Silkö:BAAALAAECgcIDQAAAA==.Simita:BAABLAAECoEfAAMdAAgIVh/aEAArAgAcAAcIwB+cOgBNAgAdAAcIKhzaEAArAgAAAA==.Sindragon:BAAALAAECgMIBwAAAA==.Sippie:BAAALAADCgQIBAAAAA==.',Sk='Skeltar:BAAALAAECgYIEgAAAA==.',Sm='Smorg:BAABLAAECoEaAAIEAAcIcROxgQB6AQAEAAcIcROxgQB6AQAAAA==.Smushhunt:BAAALAAECggIDwAAAA==.',Sn='Sniperboi:BAABLAAECoEdAAIEAAgI6STZBwBBAwAEAAgI6STZBwBBAwAAAA==.',Sw='Switch:BAAALAAECgUICQAAAA==.',['Sá']='Sánti:BAAALAAECggIDgAAAA==.',['Sî']='Sîrina:BAAALAAECgQIBQAAAA==.',Ta='Tassal:BAAALAADCggIHwAAAA==.',Th='Thala:BAAALAADCggIDgAAAA==.Thalîa:BAAALAADCggIDAAAAA==.Thargrin:BAAALAADCggICAAAAA==.Thedarksider:BAAALAADCgMIAwAAAA==.Thraenda:BAAALAADCgcICwAAAA==.',Ti='Timelord:BAAALAADCgcIBQAAAA==.Tiradon:BAAALAAECgYIDwAAAA==.Tixi:BAAALAAECgQIBQAAAA==.',To='Totemic:BAAALAAECgIIAgAAAA==.',Tr='Tristeca:BAAALAAECgcIEQAAAA==.',Tw='Twentytwo:BAAALAAECgQIBwAAAA==.',Ul='Ultired:BAAALAAECggICAAAAA==.',Um='Umiel:BAABLAAECoEWAAIFAAcI6xrdKAAVAgAFAAcI6xrdKAAVAgAAAA==.',Ur='Urdulan:BAAALAAECgQIBAAAAA==.Uru:BAAALAADCgUIBQAAAA==.',Va='Vadghahriel:BAAALAADCgUIBQAAAA==.Valdemar:BAAALAAECggIDAAAAA==.Valkyra:BAAALAAECgMIBwAAAA==.Vark:BAAALAAECgUICgAAAA==.Varkar:BAAALAAECgMIAwABLAAECgUICgAKAAAAAA==.',Ve='Veehla:BAAALAAECgEIAQAAAA==.Velveth:BAAALAADCggICAAAAA==.Veront:BAAALAAECgcICwAAAA==.',Vi='Viridium:BAABLAAECoEaAAMCAAgIJxldNgAqAgACAAgIgBhdNgAqAgAeAAMI8xuCHQD6AAAAAA==.Viridius:BAABLAAECoEdAAIfAAgI3iCVAwCuAgAfAAgI3iCVAwCuAgAAAA==.',Vr='Vrandal:BAAALAADCgcIBwABLAAECgcIEQAKAAAAAA==.',['Vá']='Váelen:BAAALAADCgQIBAAAAA==.',Wu='Wulfrig:BAAALAAECggICgAAAA==.Wutzäpfchen:BAAALAAECgIIBAAAAA==.',Xe='Xereena:BAAALAADCggICAAAAA==.Xernok:BAAALAADCgcIDQAAAA==.',Xh='Xhaldora:BAAALAADCggIDQAAAA==.',Xu='Xuljun:BAABLAAECoEUAAIVAAcIURf8UADyAQAVAAcIURf8UADyAQABLAAECggIIgAEAOUjAA==.Xunalol:BAAALAAECggICAAAAA==.',Xy='Xyl:BAAALAAECggIDAAAAA==.',Zu='Zuljian:BAAALAAECggICAAAAA==.',['Zø']='Zøro:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end