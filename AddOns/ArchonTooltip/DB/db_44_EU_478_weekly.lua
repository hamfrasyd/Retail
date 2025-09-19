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
 local lookup = {'Shaman-Elemental','Unknown-Unknown','Warrior-Protection','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Priest-Holy','DeathKnight-Blood','Druid-Balance','Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Evoker-Preservation','Druid-Restoration','Paladin-Holy','Monk-Mistweaver','Priest-Discipline','Evoker-Devastation','Evoker-Augmentation','Mage-Arcane','Mage-Fire','Hunter-Survival',}; local provider = {region='EU',realm='ZirkeldesCenarius',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abendsang:BAAALAAECgEIAQAAAA==.Abàddón:BAAALAADCgYIDQAAAA==.',Ad='Adsartha:BAAALAAECgQIBQAAAA==.',Ae='Aerthen:BAAALAAECgYIBwAAAA==.',Ag='Aginolf:BAAALAADCgcICgAAAA==.',Ah='Ahlstorm:BAAALAADCgEIAQAAAA==.',Ai='Aigaidya:BAAALAAECgEIAQAAAA==.',Ak='Akamiana:BAAALAADCgcIDQAAAA==.Akhshami:BAAALAADCgYIDQAAAA==.Akmonedia:BAAALAADCgcIBwAAAA==.',Al='Alanari:BAAALAAECgYICgAAAA==.Aleesha:BAAALAAFFAIIAgAAAA==.Alimonera:BAAALAADCgEIAQAAAA==.Alironka:BAAALAAECggICAAAAA==.Aliryâ:BAAALAAECgEIAQAAAA==.Alixd:BAACLAAFFIEPAAIBAAYIixdRAAA7AgABAAYIixdRAAA7AgAsAAQKgRgAAgEACAi/JMUDADoDAAEACAi/JMUDADoDAAAA.Alizià:BAAALAADCgUICQAAAA==.Almexxia:BAAALAADCgcIEwAAAA==.Almindem:BAAALAADCgcIBwAAAA==.Alminin:BAAALAADCgUIBQAAAA==.Alpiz:BAAALAADCgUIBQAAAA==.Alyssera:BAAALAAECgYIAQAAAA==.',Am='Amalie:BAAALAAECgIIBAAAAA==.Amaras:BAAALAADCggICAABLAADCggICwACAAAAAA==.Amerah:BAAALAAECgIIAgAAAA==.Amrak:BAAALAADCgcIDAAAAA==.',An='Anarr:BAAALAADCgEIAQAAAA==.Anathdra:BAACLAAFFIEPAAIDAAYIehVQAAACAgADAAYIehVQAAACAgAsAAQKgRgAAgMACAjHI8IBADYDAAMACAjHI8IBADYDAAAA.Andreansella:BAAALAADCggIDgAAAA==.',Ap='Apfel:BAAALAADCgMIAwAAAA==.Aprikano:BAACLAAFFIEPAAMEAAYIBCR6AAA7AgAEAAUIwCV6AAA7AgAFAAIIpxxVAAC6AAAsAAQKgRgABAQACAiNJl4AAIwDAAQACAiNJl4AAIwDAAUABghmHqsFABgCAAYAAQiwD5JXADsAAAAA.',Ar='Arann:BAAALAADCggICAAAAA==.Arcádia:BAABLAAECoEYAAIHAAgIqQ0LHADSAQAHAAgIqQ0LHADSAQAAAA==.Arissim:BAAALAADCgcIBwAAAA==.Arizal:BAAALAAECgIIAgAAAA==.Arjana:BAAALAADCgcIBwAAAA==.Arlok:BAAALAADCgIIAgAAAA==.Arodaan:BAAALAAECgcIDQAAAA==.Arrajina:BAAALAADCggIDgABLAAECgYICgACAAAAAA==.Arthurian:BAAALAAECgMIBQAAAA==.Artielle:BAAALAADCgMIAwAAAA==.',As='Askanius:BAAALAAECgMIBQAAAA==.Aspergillus:BAAALAADCgEIAQAAAA==.Astellar:BAAALAADCgUIBQAAAA==.Astronomíx:BAAALAAECgQIBwAAAA==.',At='Atomi:BAAALAADCggIEAAAAA==.',Av='Avalas:BAAALAAECgMIAwAAAA==.',Aw='Awoo:BAAALAAECgIIAgAAAA==.',Ay='Ayslyn:BAAALAAECgEIAQAAAA==.',Az='Azarack:BAAALAAECgEIAQAAAA==.Azmoderia:BAAALAAECgEIAQAAAA==.Azulina:BAAALAAECgMIAwAAAA==.Azzekziraita:BAAALAADCgEIAQABLAADCgcIBwACAAAAAA==.',['Aî']='Aîlean:BAAALAADCggIDgAAAA==.',Ba='Bagorox:BAAALAADCgEIAQAAAA==.Bashnuell:BAAALAADCgMIAwAAAA==.Basterix:BAAALAADCggIDgAAAA==.Batzbenzer:BAAALAADCggIEQAAAA==.',Be='Beatríce:BAAALAAECggIDgAAAA==.Beda:BAAALAADCggIFQAAAA==.Begreen:BAAALAAECgYIDgAAAA==.',Bi='Biogas:BAAALAADCggIDgAAAA==.',Bl='Blxckbrew:BAAALAAECgcIDwAAAA==.Blyadmachine:BAACLAAFFIENAAMIAAYIPxovAABWAQAJAAQI7BA5AQBXAQAIAAMIgCQvAABWAQAsAAQKgRgAAwkACAjPJWsXAFwCAAkABgjlImsXAFwCAAgABQjhJPsIACECAAAA.',Bo='Booya:BAAALAADCgcIFQAAAA==.',Br='Brabusch:BAACLAAFFIEPAAIHAAYIECQbAACLAgAHAAYIECQbAACLAgAsAAQKgRgAAgcACAiWJeMBAFsDAAcACAiWJeMBAFsDAAEsAAQKCAgUAAoAeyQA.Brabut:BAABLAAECoEUAAMKAAgIeySfBQDrAgAKAAcICiSfBQDrAgALAAII1CKyEADSAAAAAA==.Brabutdruid:BAAALAADCgIIAgABLAAECggIFAAKAHskAA==.Brownie:BAAALAADCggICAAAAA==.Brutzelbart:BAAALAADCgcIAwAAAA==.',['Bó']='Bóbrdin:BAAALAAECgcIDAAAAA==.',Ca='Caein:BAAALAADCggIDgAAAA==.Cait:BAAALAADCgcIBwABLAAECggICQACAAAAAA==.Calypso:BAAALAADCgEIAQABLAADCgcIEQACAAAAAA==.Carabert:BAABLAAECoEUAAIMAAgIKiT2AABYAwAMAAgIKiT2AABYAwABLAAFFAQIBgAHANkJAA==.Caraloni:BAACLAAFFIEGAAMHAAQI2QnqAwDqAAAHAAMI9QzqAwDqAAANAAIIYwIsDACWAAAsAAQKgRgAAgcACAgjHwMIAN4CAAcACAgjHwMIAN4CAAAA.Carmelina:BAAALAADCgcIBwAAAA==.Casmera:BAAALAADCgYIBgAAAA==.Cay:BAAALAAECggICAABLAAECggIFQANACAkAA==.Caydas:BAABLAAECoEVAAINAAgIICRYAQBOAwANAAgIICRYAQBOAwAAAA==.Caymi:BAAALAAECgYICwABLAAECggIFQANACAkAA==.',Ce='Cede:BAAALAAECgYIDwAAAA==.Celalinda:BAACLAAFFIEPAAIOAAYIbh0NAABvAgAOAAYIbh0NAABvAgAsAAQKgRgAAg4ACAibIzIBAEcDAA4ACAibIzIBAEcDAAAA.',Ch='Chipauline:BAAALAAECgQIBAAAAA==.Chlamydomon:BAAALAADCgcICQAAAA==.',Ci='Ciara:BAAALAADCggIFQABLAAECgEIAQACAAAAAA==.Cilyana:BAAALAADCggICAAAAA==.',Cl='Clericer:BAAALAAECgEIAQAAAA==.Cloudless:BAAALAADCggIDgAAAA==.Cloudpriest:BAAALAADCgcIDgAAAA==.',Cy='Cyllona:BAAALAAECgEIAQAAAA==.Cyresa:BAABLAAECoEWAAIPAAgIjh4wCQCsAgAPAAgIjh4wCQCsAgAAAA==.Cysîrra:BAAALAADCgUIBAAAAA==.',['Câ']='Câylinaz:BAAALAAFFAEIAQAAAA==.',Da='Daichisho:BAAALAADCgcIEwAAAA==.Darbolosch:BAAALAAECgQICQAAAA==.Darekras:BAAALAADCggIDAAAAA==.Darkless:BAAALAADCggIEgAAAA==.Dayone:BAAALAADCgIIAgABLAADCgcIBwACAAAAAA==.',De='Degor:BAAALAADCgQIBwAAAA==.Demaycy:BAAALAADCggICgABLAAECgEIAQACAAAAAA==.Demonion:BAAALAADCgcIBwAAAA==.Derron:BAAALAADCggICAAAAA==.',Di='Dimauzzius:BAAALAADCggIEAABLAAECgcIDAACAAAAAA==.Dimmalimm:BAAALAAECgUIBQABLAAECgYIDgACAAAAAA==.Dirtyfox:BAAALAAECgcIDwAAAA==.Diwil:BAAALAAECgMIBwAAAA==.',Dj='Djehuti:BAAALAADCggIDQAAAA==.',Dn='Dnblifestyle:BAAALAAFFAEIAQAAAQ==.',Do='Doomish:BAABLAAECoEUAAIHAAgIdBoQDACVAgAHAAgIdBoQDACVAgAAAA==.Doraghan:BAAALAADCgcIEwAAAA==.',Dr='Draxxus:BAABLAAECoEYAAMBAAgI8xDoFgAPAgABAAgI8xDoFgAPAgAQAAEIlwSBhwAtAAAAAA==.Drish:BAAALAAECgEIAQAAAA==.Drutus:BAAALAADCgEIAQAAAA==.Drägen:BAAALAADCggIDwAAAA==.',Du='Dulnaar:BAAALAADCgQIBAAAAA==.Dummbatz:BAAALAAECggIEAABLAAECgYIBgACAAAAAA==.',Ed='Edius:BAAALAADCgcIBwAAAA==.',Ei='Einalema:BAAALAAECgcIDwAAAA==.',Ej='Eja:BAAALAADCggIFQAAAA==.',Ek='Ekazil:BAAALAADCggIDAAAAA==.',El='Elarah:BAAALAADCgYIBgAAAA==.Elesandria:BAAALAAECgMIBQAAAA==.Elrin:BAAALAADCggIBAABLAADCggICAACAAAAAA==.Elustrasza:BAAALAAECgEIAQAAAA==.Eléven:BAAALAAECgMIBAAAAA==.',Ep='Eph:BAAALAADCgUIBQABLAADCgcIEwACAAAAAA==.',Er='Erazor:BAAALAAECgMIBQAAAA==.',Es='Espid:BAAALAAECgYIBwAAAA==.Esquie:BAAALAADCgYICwAAAA==.',Ev='Evoni:BAAALAADCgYIBwAAAA==.Evy:BAAALAAECgMIBQAAAA==.',Ew='Ewho:BAACLAAFFIEFAAIRAAMIGg/DBwCQAAARAAMIGg/DBwCQAAAsAAQKgRUAAxEACAjBIYMJAJUCABEABwj9IYMJAJUCABIABwibFCknAMcBAAAA.',Fa='Fanisa:BAAALAAECgYIDgAAAA==.Fatira:BAAALAAECgMIBQAAAA==.',Fe='Feisty:BAAALAADCgcIDAAAAA==.Feliris:BAAALAADCgcIBwAAAA==.Ferenoth:BAAALAAECgUIBQAAAA==.Ferria:BAAALAAECgMIAwAAAA==.Festara:BAAALAAECgUIBQAAAA==.',Fi='Fiddlestickz:BAAALAADCggICgAAAA==.Filli:BAAALAAECgcICQAAAA==.Firehawk:BAAALAADCgcIBwAAAA==.',Fl='Flopsadin:BAAALAAECgYIBgAAAA==.Flox:BAAALAAECgcIEAAAAA==.',Fo='Fortimela:BAAALAAECgYICgAAAA==.',Fr='Freylia:BAAALAAECgMIBAAAAA==.Frezzas:BAAALAADCgEIAQAAAA==.Frøs:BAAALAADCggIDgAAAA==.',['Fê']='Fêenexús:BAAALAADCgcIBwABLAAECggICgACAAAAAA==.Fêénexus:BAAALAADCggIEAABLAAECggICgACAAAAAA==.',['Fí']='Fílou:BAAALAADCgMIAwAAAA==.',['Fô']='Fôrcê:BAAALAAECgMIBAABLAAECggICgACAAAAAA==.',['Fû']='Fûriel:BAABLAAECoEYAAMSAAgIeSIVCgDNAgASAAgIHiEVCgDNAgARAAgIph6UBwC7AgAAAA==.',Ga='Ganran:BAAALAADCgQIBAAAAA==.Garanthir:BAAALAADCgEIAQAAAA==.Garbrosh:BAAALAADCgMIAwAAAA==.Garon:BAAALAAECgEIAQAAAA==.',Ge='Geduldige:BAAALAADCgYIEQAAAA==.Geralt:BAAALAAECgMIBAAAAA==.',Gh='Ghura:BAAALAADCgcIBwAAAA==.',Gi='Gilgameasch:BAAALAADCggICgAAAA==.Gineriá:BAAALAADCggICAAAAA==.Giyujin:BAAALAADCgcIEQAAAA==.',Gl='Gladion:BAAALAADCggICwABLAAECgMIBwACAAAAAA==.Glenroy:BAAALAAECgIIAgAAAA==.',Gn='Gnusella:BAAALAADCgEIAQAAAA==.',Go='Gomlit:BAAALAADCggIDwAAAA==.Goodnamehere:BAAALAADCgIIAgAAAA==.',Gr='Grumbil:BAAALAADCgcIDQAAAA==.',Ha='Hackz:BAAALAADCgcIBwAAAA==.Hairymetal:BAAALAAECgMIAwAAAA==.Hanký:BAAALAADCggICAAAAA==.Hargrimm:BAAALAADCgcIDQAAAA==.',He='Heiteira:BAAALAADCgUIBQAAAA==.Hennix:BAAALAADCgcIFQAAAA==.',Ho='Holyspell:BAAALAADCggICAABLAAECggICgACAAAAAA==.Homer:BAAALAAECgEIAQAAAA==.Hotalot:BAAALAAECgYICAAAAA==.Hoturi:BAAALAAECgYIBgAAAA==.',Hr='Hrandusek:BAAALAAECgYIDwAAAA==.',Hu='Hursti:BAECLAAFFIEMAAITAAYIMRUdAAAaAgATAAYIMRUdAAAaAgAsAAQKgRgAAhMACAhJJdkAAGEDABMACAhJJdkAAGEDAAAA.',Hy='Hyliaa:BAAALAADCgcIBwAAAA==.',['Hà']='Hàgen:BAAALAADCggICAAAAA==.',['Hó']='Hórcus:BAAALAADCgYIDAAAAA==.',Il='Ilckar:BAAALAADCggIFwAAAA==.',In='Inaku:BAAALAADCggICwAAAA==.Influhancer:BAACLAAFFIEFAAIUAAMIRSLtAADMAAAUAAMIRSLtAADMAAAsAAQKgRYAAhQACAh3JJYAAEUDABQACAh3JJYAAEUDAAAA.Inujiasha:BAAALAAECgMIAwAAAA==.Inurya:BAABLAAECoEUAAIBAAgIuCHhBAAkAwABAAgIuCHhBAAkAwABLAAFFAYIDwANAHsYAA==.',Ir='Iris:BAAALAAECgIIAgAAAA==.',Ja='Jadelyn:BAAALAAECgEIAQAAAA==.Jageros:BAAALAAECgYICgAAAA==.Jaidenhaze:BAAALAADCggIDwAAAA==.Jaimee:BAAALAAECgMIBQAAAA==.Jakon:BAAALAADCgYIBgABLAAECgMIBwACAAAAAA==.',Je='Jelissa:BAAALAAECgEIAQAAAA==.Jenora:BAAALAADCgEIAQAAAA==.Jeriko:BAAALAADCgUIBQAAAA==.',Jh='Jhin:BAAALAADCggIEAABLAAECggIFQANACAkAA==.',Jo='Johzi:BAAALAAECgMIBgAAAA==.Jomon:BAAALAADCgYIBgAAAA==.Josie:BAAALAADCggICAAAAA==.Joweniter:BAAALAAECgEIAQAAAA==.',Ju='Jubél:BAAALAADCgYICgAAAA==.Juleene:BAAALAAECgUIBwABLAAECgYIBgACAAAAAA==.Juluna:BAAALAAECgYIBgAAAA==.Jurihan:BAACLAAFFIEPAAIVAAYIJRoxAAB0AgAVAAYIJRoxAAB0AgAsAAQKgRgAAhUACAgnJU8CAGcDABUACAgnJU8CAGcDAAAA.Jushiro:BAAALAADCggIDwAAAA==.Juxea:BAAALAAECgcICQAAAA==.',['Jä']='Jägerling:BAAALAADCgcIDgAAAA==.',['Jò']='Jò:BAABLAAECoEVAAIWAAgITR21AwCQAgAWAAgITR21AwCQAgAAAA==.',['Jö']='Jörgen:BAAALAAECgMIAwAAAA==.',['Jû']='Jûnâ:BAAALAADCggICAAAAA==.',Ka='Kadavér:BAAALAAECgMIBQAAAA==.Kaethol:BAAALAAECgYIDAAAAA==.Kahlîm:BAAALAADCgcIDQAAAA==.Kakuzu:BAAALAAECgQIBQAAAA==.Kalique:BAAALAAECggIDwAAAQ==.Kaoríe:BAAALAADCggIDgAAAA==.Kappadozius:BAAALAAECgcIDgAAAA==.Karious:BAAALAADCggIDwAAAA==.Kasarî:BAAALAADCgYICwAAAA==.Kavka:BAAALAAECgIIAgAAAA==.',Ke='Kearon:BAAALAAECgYICQAAAA==.',Kh='Khashièl:BAAALAAECgUIBwAAAA==.',Ki='Kiga:BAAALAAECgcIDQAAAA==.Killkrush:BAAALAAECgYICwAAAA==.Kirgarn:BAAALAADCgcIDAAAAA==.Kitanos:BAAALAAECggIDQAAAA==.Kizu:BAABLAAECoEUAAIXAAcIuBtSGQBHAgAXAAcIuBtSGQBHAgAAAA==.',Kl='Kleinholz:BAAALAAECgIIAgAAAA==.',Ko='Kollabieren:BAAALAAECgUIBQAAAA==.Koraidon:BAAALAADCggICAABLAAECggICgACAAAAAA==.Koreena:BAAALAADCggICAAAAA==.Korthok:BAAALAADCgUIBgAAAA==.Korui:BAAALAAECgIIAgAAAA==.Kotflügel:BAAALAAECgEIAQAAAA==.',Ky='Kyliê:BAAALAAECggICgAAAA==.',['Ká']='Káthey:BAAALAAECgMIBQAAAA==.',['Kî']='Kîa:BAAALAADCggICwAAAA==.Kîki:BAAALAAECgMIBAAAAA==.',La='Lacia:BAAALAAECgUIBwAAAA==.Laputa:BAAALAADCggIFQAAAA==.Lashar:BAAALAADCgMIAwAAAA==.Laylon:BAAALAAECgQIAwAAAA==.Laíka:BAAALAADCggIFwAAAA==.',Le='Leebuun:BAAALAADCggIFQAAAA==.Lerra:BAAALAAECgUIBQABLAAFFAYIDwAYAIQlAA==.Lerralol:BAABLAAECoEWAAIZAAgIDSWtAABVAwAZAAgIDSWtAABVAwABLAAFFAYIDwAYAIQlAA==.Lerrastrasza:BAACLAAFFIEPAAIYAAYIhCUGAACXAgAYAAYIhCUGAACXAgAsAAQKgRgAAhgACAiCJV8AAFQDABgACAiCJV8AAFQDAAAA.Lerâ:BAAALAADCgcIEwAAAA==.Lexpala:BAAALAADCggICAABLAAECggIFAASACYcAA==.',Lh='Lhorsha:BAAALAAECgUIBwAAAA==.',Li='Lieb:BAAALAADCggICAAAAA==.Linamaxima:BAAALAADCggIFAAAAA==.Lirania:BAAALAADCggIEAAAAA==.Lishayin:BAAALAAECgIIAwAAAA==.Livariel:BAAALAAECgYICgAAAA==.Liónde:BAAALAADCgQIBAAAAA==.',Lo='Loranas:BAAALAADCgcIBwAAAA==.',Lu='Lubra:BAAALAADCgcIFAAAAA==.Lucìen:BAAALAAECgYICQAAAA==.Lumaya:BAAALAADCggICQAAAA==.Luziá:BAAALAADCggICAAAAA==.',Ly='Lyará:BAAALAAECgEIAQAAAA==.Lykanthro:BAAALAAECgEIAQAAAA==.Lyndariel:BAAALAADCggICAAAAA==.Lynîe:BAAALAAECgYIBgAAAA==.Lyphatea:BAAALAADCggICAAAAA==.Lyso:BAAALAADCgIIAgAAAA==.Lyss:BAAALAADCgQIBgAAAA==.',['Lê']='Lêx:BAABLAAECoEUAAISAAgIJhy3EgBiAgASAAgIJhy3EgBiAgAAAA==.',['Lí']='Lírs:BAAALAAECgMIAgAAAA==.',['Lï']='Lïrs:BAAALAAECgYIDgAAAA==.',['Ló']='Lóriana:BAAALAADCggICAAAAA==.',['Lô']='Lôan:BAAALAAECggIEwABLAAFFAIIAgACAAAAAA==.',Ma='Magimus:BAAALAADCggICAAAAA==.Mahema:BAAALAADCgQIBAAAAA==.Malius:BAAALAAECgEIAQAAAA==.Mapko:BAABLAAECoEYAAILAAgIEiFIAQD/AgALAAgIEiFIAQD/AgAAAA==.Mardakqt:BAAALAAFFAIIAwAAAA==.Mathouf:BAAALAADCggICAAAAA==.Matthias:BAAALAAECggICAAAAA==.Matukufnukus:BAABLAAECoEVAAMXAAgI7CAkCQD7AgAXAAgI7CAkCQD7AgAaAAQITgLZKwChAAABLAAFFAEIAQACAAAAAA==.Maytira:BAAALAAECgEIAQAAAA==.',Me='Mebibeam:BAAALAAECgYIDwAAAA==.Meenzi:BAAALAAECgEIAQAAAA==.Meglaut:BAAALAADCgYIBgAAAA==.Melamin:BAABLAAECoEUAAISAAgI5BkAEAB/AgASAAgI5BkAEAB/AgAAAA==.Melindari:BAAALAADCgQIBAAAAA==.Melrot:BAAALAAECgMIBQAAAA==.Meo:BAAALAAECgYICgAAAA==.Meril:BAAALAAECgYIDAAAAA==.Method:BAAALAAECgEIAQAAAA==.Metzelmauzz:BAAALAAECgcIDAAAAA==.',Mi='Midget:BAAALAADCgQIBAAAAA==.Minsc:BAAALAAECgMIAwAAAA==.Miraculixus:BAAALAAECgMIBQAAAA==.Miramina:BAEALAADCgcIDgABLAADCggIBAACAAAAAA==.Miranea:BAAALAADCgQIBAAAAA==.Miribayh:BAAALAADCgcIEQAAAA==.',Mo='Moadess:BAAALAADCgEIAQAAAA==.Mobo:BAAALAAECgIIAgAAAA==.Mogur:BAAALAAECgYIDwAAAA==.Monchia:BAAALAAECgUIBQABLAAECgYICgACAAAAAA==.Moonwillow:BAAALAADCgQIBAAAAA==.Moosferati:BAAALAADCgEIAQAAAA==.Mortanir:BAAALAADCgIIAgAAAA==.Morticiâ:BAAALAADCgcIEQAAAA==.Mothyr:BAAALAADCggICAAAAA==.',Mu='Murîe:BAABLAAECoEUAAIXAAgI5QfWPACIAQAXAAgI5QfWPACIAQAAAA==.',My='Myku:BAAALAADCggIEAAAAA==.',['Má']='Mággý:BAAALAADCggIDwAAAA==.Máldina:BAAALAADCgYIBgAAAA==.',['Mê']='Mêkrath:BAAALAADCggIEAAAAA==.',['Mî']='Mîrei:BAAALAAECgEIAQAAAA==.',['Mô']='Mô:BAAALAADCggIGAAAAA==.',Na='Naethra:BAAALAAECgYICgAAAA==.Najienda:BAAALAAECggICgAAAA==.Nakun:BAAALAAECgIIAgAAAA==.Nakusa:BAAALAAECggIEQAAAA==.Nalany:BAAALAADCggICAAAAA==.Nalgrâsh:BAAALAADCggIDgAAAA==.Namrae:BAAALAADCggICAAAAA==.Nanami:BAAALAADCgQIBAAAAA==.Nanet:BAAALAADCgcIBwAAAA==.Nanoc:BAAALAAECgIIAwAAAA==.Naofumi:BAAALAADCggICAABLAAECggICgACAAAAAA==.Narrak:BAAALAADCgcIDAABLAADCggIDgACAAAAAA==.Narubí:BAAALAAECgIIAgAAAA==.Nashiya:BAAALAADCgcIEAAAAA==.Nasinhdra:BAAALAADCgcIEQAAAA==.Nathaya:BAAALAAECgEIAQAAAA==.',Ne='Necrama:BAAALAADCggIFwAAAA==.Neferêt:BAAALAADCgcIBwAAAA==.Neiru:BAACLAAFFIELAAIaAAUInwe3AACLAQAaAAUInwe3AACLAQAsAAQKgRgAAhoACAgoEuYMAAwCABoACAgoEuYMAAwCAAAA.Nerexina:BAAALAADCggICAAAAA==.Nesarina:BAAALAADCgcIEgAAAA==.',Ni='Nihilya:BAAALAAECgYIBQAAAA==.Nijenna:BAAALAADCggIDQAAAA==.Nividím:BAAALAAECgEIAQAAAA==.',Nn='Nnyx:BAAALAAECggIEwAAAA==.',No='Noellé:BAAALAAECggICgAAAA==.Noisia:BAAALAAECgYICQAAAA==.Noksu:BAAALAADCggIBAAAAA==.Nomercy:BAAALAADCggICAAAAA==.',Ny='Nydena:BAAALAADCggIDwAAAA==.Nynagos:BAAALAAECgcIDAABLAAECggIGAABAMweAA==.Nynas:BAABLAAECoEYAAIBAAgIzB5/CQDMAgABAAgIzB5/CQDMAgAAAA==.',['Ná']='Náchtára:BAAALAADCgYIBgAAAA==.',Oj='Ojin:BAAALAAECgEIAQABLAAECgMIBwACAAAAAA==.',Ok='Okko:BAAALAADCgcIEQAAAA==.',Ol='Olóri:BAAALAADCgIIAgAAAA==.',On='Onocthor:BAAALAADCgYICwAAAA==.Onyx:BAAALAADCggICAAAAA==.',Or='Orber:BAAALAAECgYICwAAAA==.Orca:BAAALAADCggIFgAAAA==.',Pa='Pachomia:BAAALAADCgcIEQAAAA==.Palagos:BAAALAAECgEIAQAAAA==.Palamatsch:BAAALAADCgYIBgAAAA==.Palgor:BAAALAAECgMIAwAAAA==.Pankari:BAAALAAECgcICgAAAA==.Panzerfahrer:BAAALAAECgYIBgABLAAFFAMIBQAUAEUiAA==.',Pe='Peachicetea:BAAALAADCgcIEwAAAA==.Peas:BAAALAAECgYIBgAAAA==.Peranoid:BAAALAAECgIIAgAAAA==.Perdita:BAAALAADCgUIBQAAAA==.Persé:BAAALAAECgIIAgAAAA==.',Pf='Pfalzgräfin:BAAALAADCggIEQAAAA==.',Ph='Phidi:BAAALAADCgcICgAAAA==.Philmanyat:BAAALAAECgQIBwAAAA==.',Pi='Pingwin:BAAALAAECggICAAAAA==.',Po='Pollyana:BAAALAADCgcIDAAAAA==.Porch:BAACLAAFFIEPAAIbAAYIlRgTAABOAgAbAAYIlRgTAABOAgAsAAQKgRgAAhsACAhAIFoDANkCABsACAhAIFoDANkCAAAA.Porchini:BAABLAAECoEUAAIQAAgI0yOdAQApAwAQAAgI0yOdAQApAwABLAAFFAYIDwAbAJUYAA==.',Pr='Prudenc:BAAALAAECgMIBgAAAA==.',['Pá']='Páîn:BAAALAADCgYIBgAAAA==.',['På']='Pållas:BAAALAADCggICAAAAA==.',Qr='Qrva:BAAALAADCggICAAAAA==.',Qu='Qualadrine:BAAALAAECgcIDgAAAA==.',Ra='Radieschen:BAAALAADCgEIAQAAAA==.Raiguy:BAAALAADCgcICwAAAA==.Rattebisst:BAAALAADCgcIDQAAAA==.',Re='Reowen:BAAALAADCgcIDAAAAA==.',Rh='Rhaenyá:BAAALAAECgUIBgAAAA==.',Ri='Rihsa:BAAALAADCgEIAQAAAA==.',Ro='Roarabar:BAAALAAECgUIBQAAAA==.Rogat:BAAALAAECgEIAQAAAA==.Romalus:BAAALAAECgEIAQAAAA==.Rosarìa:BAAALAADCgYIBgAAAA==.Rotag:BAAALAAECgQIBwAAAA==.',Ru='Ruckzuckvoll:BAAALAADCgYIBgAAAA==.Rufmichan:BAAALAAECgYIDAABLAAFFAMIBQAUAEUiAA==.Runah:BAAALAADCgMIAwAAAA==.Rushgarroth:BAABLAAECoEUAAQEAAgIDxjzEQBTAgAEAAgIKhbzEQBTAgAGAAcI7hMTDwDuAQAFAAEI+AvDKQBMAAABLAAECggIGAABAPMQAA==.',['Rê']='Rêdsnake:BAABLAAECoEZAAITAAgIhh9TBQC5AgATAAgIhh9TBQC5AgAAAA==.',Sa='Saghaîa:BAABLAAECoEUAAMLAAcIaSH4BQDlAQALAAYIUh74BQDlAQAKAAUIfyBFFwDbAQAAAA==.Sakisaka:BAAALAAECgIIAwAAAA==.Salocin:BAAALAADCgcIDQAAAA==.Salubri:BAAALAAECgMIAwAAAA==.Salyria:BAAALAADCggIDgAAAA==.Samiraa:BAAALAADCggIFQAAAA==.Samús:BAAALAAECgQIAgAAAA==.Sanaky:BAAALAADCggIDwABLAADCggIEAACAAAAAA==.Sanuri:BAAALAAECgMIBQAAAA==.Sarisma:BAAALAADCggIEwAAAA==.Sarolf:BAAALAADCgEIAQAAAA==.Sastran:BAAALAADCgUIBgAAAA==.',Sb='Sbones:BAAALAADCggICAAAAA==.',Sc='Schakar:BAAALAADCgcIBwAAAA==.Schanimani:BAAALAADCgYICgAAAA==.Schattenmond:BAAALAAECgMIAwAAAA==.Schlabotta:BAAALAADCggIEAAAAA==.Schnauzer:BAAALAADCgcIBwAAAA==.Scratchy:BAAALAAECgQIBAABLAADCgcIDAACAAAAAA==.',Se='Seiki:BAAALAAECgEIAQABLAAECgYIBwACAAAAAA==.Seiryssa:BAAALAAECgYIDQAAAA==.Sekhmet:BAAALAADCgcIEQAAAA==.Selisa:BAAALAADCgcIDAAAAA==.Sensei:BAAALAADCgYIDQAAAA==.Seraclayton:BAAALAAECgcIDwAAAA==.Servena:BAAALAADCgcIBwAAAA==.Sezaî:BAAALAAECgQIBAABLAAECggIEwACAAAAAA==.',Sh='Shadunja:BAAALAAECgcIEgAAAA==.Shafirah:BAAALAADCgcIEQAAAA==.Shakota:BAAALAAECgIIAgAAAA==.Shaladril:BAAALAADCggIDgAAAA==.Shallina:BAAALAAECgUICgAAAA==.Shamanthul:BAAALAADCggICAAAAA==.Shameniac:BAAALAADCgYICAAAAA==.Shanata:BAAALAADCggICAAAAA==.Shanlee:BAAALAADCggIFwABLAAECggICgACAAAAAA==.Sharaiâ:BAAALAADCgEIAQAAAA==.Sharku:BAAALAADCgcICgAAAA==.Shassara:BAAALAADCgEIAQAAAA==.Shimokami:BAAALAADCggICAAAAA==.Shinay:BAAALAADCggIFwAAAA==.Shirókiel:BAAALAAECgcIEQAAAA==.Shoraz:BAAALAAECgIIAgAAAA==.Shyreen:BAABLAAECoEUAAIbAAgIMhVZCgALAgAbAAgIMhVZCgALAgAAAA==.Shíera:BAAALAADCggICAAAAA==.Shîn:BAACLAAFFIEPAAMNAAYIexhMAADbAQANAAUI2RdMAADbAQAcAAEIoxvcAABlAAAsAAQKgRgAAg0ACAgqHgMJAKkCAA0ACAgqHgMJAKkCAAAA.',Si='Sillywonka:BAAALAADCgcIBwAAAA==.Simivoker:BAACLAAFFIEFAAIdAAMIhRM+AgAXAQAdAAMIhRM+AgAXAQAsAAQKgRgAAh0ACAgRJLsBAEsDAB0ACAgRJLsBAEsDAAAA.',Sj='Sjur:BAAALAADCgcIBwAAAA==.',Sk='Skarael:BAAALAADCggIFQABLAAECgIIAgACAAAAAA==.Skyneed:BAAALAAECggICAAAAA==.',Sl='Slick:BAAALAAECgQIBgAAAA==.',Sm='Smelly:BAAALAADCgcIBwAAAA==.',Sn='Snacks:BAAALAADCgYIBgAAAA==.Snooze:BAACLAAFFIEPAAIeAAYIECcBAADKAgAeAAYIECcBAADKAgAsAAQKgRgAAx4ACAgOJwEAALYDAB4ACAgOJwEAALYDAB0AAQhGIxk2AE0AAAAA.Snus:BAAALAAECggIDgAAAA==.',So='Sokí:BAAALAAECgEIAQAAAA==.Sonaya:BAAALAADCggIDAAAAA==.Sonèa:BAAALAAECgIIAgAAAA==.Souless:BAAALAADCggICAAAAA==.Sousá:BAACLAAFFIEKAAMfAAYIoBvWAADpAQAfAAUIiRvWAADpAQAgAAEIERy+AQBmAAAsAAQKgRUAAh8ACAgxIM0GABQDAB8ACAgxIM0GABQDAAAA.',St='Starknight:BAAALAADCggICAAAAA==.',Su='Summoning:BAAALAADCgcIDAABLAADCggIDgACAAAAAA==.Sumí:BAABLAAECoEUAAIhAAgIVRJXAgBDAgAhAAgIVRJXAgBDAgAAAA==.Supana:BAABLAAECoEWAAMdAAcIsyH8CACbAgAdAAcIsyH8CACbAgAYAAUIfxn0DABkAQAAAA==.Surikal:BAAALAADCgMIAwAAAA==.Susthania:BAAALAAECgEIAQAAAA==.',Sy='Syna:BAAALAADCggICAAAAA==.Syries:BAAALAADCggIDwAAAA==.',['Sâ']='Sâgvallah:BAAALAAECgEIAQAAAA==.',['Sê']='Sêrená:BAAALAAECgMIBAAAAA==.',['Sô']='Sôphîa:BAAALAADCgYIBwAAAA==.Sôrá:BAAALAADCgEIAQAAAA==.',Ta='Taccros:BAAALAADCggIBwAAAA==.Talyhia:BAAALAAECgIIAgAAAA==.Tamrock:BAAALAADCggIDwAAAA==.Tanicar:BAAALAAECgYICAAAAA==.Tapacina:BAAALAAECgEIAQAAAA==.Tarawildhoof:BAAALAAECgYICAAAAA==.Taryosa:BAACLAAFFIEFAAIWAAMIehEZAgCTAAAWAAMIehEZAgCTAAAsAAQKgRcAAhYACAjkIjkBACYDABYACAjkIjkBACYDAAAA.Tarín:BAAALAAECgMIAwAAAA==.Tasteless:BAAALAADCgEIAQAAAA==.',Te='Tedi:BAAALAADCggIEgAAAA==.Tekinar:BAEALAADCgcIBwABLAADCggIBAACAAAAAA==.Telhari:BAAALAADCgUIBQAAAA==.Temeraira:BAABLAAECoEUAAIQAAgICBW3GgDzAQAQAAgICBW3GgDzAQAAAA==.Teori:BAACLAAFFIEPAAMRAAYIPyAMAABUAgARAAYIPyAMAABUAgASAAEIOAtQDABVAAAsAAQKgRgAAxEACAhXJNABAD0DABEACAhXJNABAD0DABIAAQhLGhRzAE8AAAAA.Teufelix:BAAALAADCgUIBQAAAA==.',Th='Thabita:BAAALAADCgYIDwAAAA==.Tharliá:BAAALAAECggIDgAAAA==.Theomi:BAAALAAFFAIIAgAAAA==.Thisarian:BAAALAADCgYIDQAAAA==.Thorthok:BAAALAAECgIIAgAAAA==.Thunderhóóf:BAAALAADCggIDwAAAA==.Thuradim:BAAALAADCggICAAAAA==.Thurios:BAAALAADCgcICAABLAAECgMIBwACAAAAAA==.Thòka:BAAALAAECggIBgAAAA==.',Ti='Tigris:BAAALAADCgYIBQABLAAECgMIAwACAAAAAA==.Tingfeng:BAAALAADCggIGAAAAA==.Tisua:BAAALAADCgcIBwAAAA==.',To='Todesball:BAAALAADCggIDwABLAAECggICQACAAAAAA==.Todestaxi:BAAALAADCgYIBgAAAA==.Todsvalkyr:BAAALAADCggIFwAAAA==.Tondar:BAAALAADCgcIBwAAAA==.Tonkî:BAAALAAECgYICgAAAA==.Tootem:BAAALAADCgMIAwAAAA==.Toraline:BAAALAAECgYICQAAAA==.',Tr='Trebdlored:BAAALAAECgIIAgAAAA==.Trebwenad:BAAALAAECgYIDgAAAA==.Triclopsa:BAAALAADCggIEAAAAA==.Triggy:BAAALAADCgcIBwAAAA==.Tríss:BAAALAADCgMIAwAAAA==.',Tu='Tufen:BAAALAADCgcICAABLAAECgMIBwACAAAAAA==.Tuldanis:BAAALAAECggICAAAAA==.Tumbleweed:BAAALAADCgYIBgAAAA==.',Ty='Tyfuun:BAAALAAECgEIAQAAAA==.Tylirion:BAAALAADCgcICAAAAA==.Tymyl:BAAALAADCggIEQAAAA==.',['Tí']='Tílda:BAAALAAECgYIDwAAAA==.Tínitus:BAAALAADCgIIAgAAAA==.',Ul='Uldren:BAAALAADCgQIBAAAAA==.Ulrezaj:BAAALAADCgMIAwAAAA==.',Un='Unforgiven:BAAALAADCggIFQAAAA==.',Ut='Utena:BAAALAADCgcIEQAAAA==.',Uu='Uulthok:BAAALAAECgcIDwAAAA==.',Va='Vaelnyra:BAAALAAECgQIBAAAAA==.Valdori:BAAALAADCggIDAAAAA==.Valyora:BAAALAADCggIEAAAAA==.Varenna:BAAALAADCgYIBgAAAA==.',Vi='Victore:BAAALAAECggICQAAAA==.Viovaleriaz:BAAALAAECgcICgAAAA==.Viren:BAAALAADCgYICgAAAA==.Virgus:BAAALAADCggICAAAAA==.',Vj='Vjelnara:BAAALAADCgcIDwAAAA==.',Vo='Voidkamitv:BAAALAAECgYIBgAAAA==.',['Vé']='Vénús:BAAALAADCggIFwAAAA==.',Wa='Wahkan:BAAALAADCgEIAQAAAA==.Warritank:BAAALAADCggICAAAAA==.',We='Weiserwólf:BAAALAAECgMIBQAAAA==.Wentlin:BAAALAADCgYIBgAAAA==.',Wh='Whydoi:BAAALAAECgYIBwAAAA==.',Wi='Willidan:BAAALAADCgMIAwABLAAECggIFAAHAHQaAA==.Wilt:BAAALAADCgcIBwAAAA==.',Wo='Woka:BAAALAAECgYIDQAAAA==.Wolkil:BAAALAAECgEIAQAAAA==.Wolkirial:BAABLAAECoEXAAIdAAgIASD8BQDeAgAdAAgIASD8BQDeAgAAAA==.Woofel:BAAALAAECgIIAgAAAA==.Wooze:BAAALAAECgYIDgAAAA==.',Wu='Wulffrok:BAAALAADCgcIDgAAAA==.',Xa='Xalirou:BAAALAADCgUIBQABLAADCgcIBwACAAAAAA==.Xantarua:BAAALAADCgMIAwABLAAECggICgACAAAAAA==.Xaspir:BAAALAADCgcIBwAAAA==.',Xi='Xiina:BAAALAADCgUIBQAAAA==.',['Xá']='Xándunari:BAAALAAECgMIBgAAAA==.',Ya='Yaele:BAAALAADCggIDgAAAA==.Yannah:BAAALAADCgYIBgAAAA==.Yasa:BAECLAAFFIEPAAIPAAYIoSYCAAC6AgAPAAYIoSYCAAC6AgAsAAQKgRgAAg8ACAjqJgcAAKUDAA8ACAjqJgcAAKUDAAAA.',Yg='Ygdrael:BAAALAAECgIIAgAAAA==.',Yo='Yoko:BAAALAADCgYIBgAAAA==.',Ys='Yssandre:BAAALAADCggICAAAAA==.',Yu='Yudas:BAAALAAECgcIEQABLAAECggIFQANACAkAA==.Yunos:BAAALAAECggIAgABLAAFFAYIDwANAHsYAA==.',Za='Zaniyara:BAAALAADCggICAAAAA==.Zardox:BAAALAADCgEIAQAAAA==.Zayala:BAAALAAECgIIAgAAAA==.',Ze='Zelphira:BAAALAAECgYIDQAAAA==.Zephar:BAAALAAECgcIDwAAAA==.Zerinka:BAAALAADCgUIBQAAAA==.Zerô:BAAALAADCggIDgAAAA==.',Zh='Zhànshi:BAAALAADCgcIBwAAAA==.',Zy='Zyshira:BAAALAADCgEIAQAAAA==.',['Zó']='Zóys:BAAALAAECgEIAQAAAA==.',['Æl']='Ælessia:BAAALAAECgMIBgAAAA==.',['Óò']='Óò:BAAALAADCgcIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end