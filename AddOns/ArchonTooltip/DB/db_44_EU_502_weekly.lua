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
 local lookup = {'Warlock-Destruction','Shaman-Restoration','Priest-Holy','Priest-Discipline','Unknown-Unknown','DeathKnight-Blood','Druid-Restoration',}; local provider = {region='EU',realm='Ясеневыйлес',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Аб']='Абазин:BAABLAAECoEUAAIBAAYIdxYIJgChAQABAAYIdxYIJgChAQAAAA==.',['Ав']='Авенморр:BAAALAADCgYIDAAAAA==.',['Аг']='Агашка:BAAALAADCgcIBwAAAA==.',['Ад']='Аджэ:BAACLAAFFIEFAAICAAMIghWGAgDuAAACAAMIghWGAgDuAAAsAAQKgR0AAgIACAgyIYQEANwCAAIACAgyIYQEANwCAAAA.Адэя:BAAALAADCggIFgAAAA==.',['Аз']='Азмодиан:BAAALAADCggIDgAAAA==.',['Ал']='Алазьен:BAAALAADCgcICgAAAA==.Александр:BAAALAADCggIDgAAAA==.',['Ам']='Амаури:BAAALAADCgYIBgAAAA==.Амигдала:BAAALAADCgcIBwAAAA==.Амилла:BAAALAADCggICAAAAA==.',['Ан']='Андромедаа:BAAALAAECggIEAAAAA==.Анкора:BAAALAADCgcIBgAAAA==.Анманерка:BAAALAAECgYICwAAAA==.',['Ба']='Базлайккер:BAAALAAECgYIDgAAAA==.Бакиэ:BAAALAAECggIDgAAAA==.Бартоламъю:BAAALAADCgcICwAAAA==.',['Бе']='Безлад:BAAALAAECgEIAQAAAA==.Беспопутал:BAAALAAECgEIAQAAAA==.',['Би']='Бицуха:BAABLAAECoEaAAMDAAcIdRlvFgANAgADAAcIXhhvFgANAgAEAAIIQRsXEQCjAAAAAA==.',['Ви']='Витьер:BAAALAAECgQIAgAAAA==.Вич:BAAALAAECgIIAgABLAAECgYIBgAFAAAAAA==.',['Вл']='Власина:BAAALAADCgUIBQAAAA==.',['Во']='Ворзах:BAAALAADCgYIBwAAAA==.',['Га']='Гаврик:BAAALAAECgMIAwAAAA==.',['Ге']='Гедерт:BAABLAAECoEVAAIGAAgIgSTsAABZAwAGAAgIgSTsAABZAwAAAA==.Гекконид:BAAALAAECgYIBgAAAA==.Геллатель:BAAALAAECgQIBAAAAA==.Герунд:BAAALAAECggIDwAAAA==.',['Гл']='Гладариель:BAAALAADCgEIAQAAAA==.',['Го']='Гопнниик:BAAALAAECgYIDwAAAA==.Гордарикс:BAAALAADCgcIBwAAAA==.Госум:BAAALAAECgYIBgAAAA==.',['Де']='Деткагэбби:BAAALAAECgEIAQAAAA==.',['Дж']='Джаггер:BAAALAADCggICAAAAA==.Джерси:BAAALAAECgYIDQAAAA==.',['Ди']='Дихангер:BAAALAAECggIEQAAAA==.',['Дк']='Дкалис:BAAALAAECggIDgAAAA==.',['Др']='Дракодоминус:BAAALAADCgYIBgAAAA==.',['Ее']='Еек:BAAALAADCgcIBwAAAA==.',['Еж']='Ежикь:BAAALAADCggICAAAAA==.',['За']='Зачарушка:BAAALAAECgcIEwAAAA==.',['Зл']='Злаямразь:BAAALAAECgIIAwAAAA==.Злойдэни:BAAALAADCgUIBQAAAA==.',['Ил']='Ильфина:BAAALAADCggIEAAAAA==.',['Им']='Имуэрто:BAAALAADCgEIAQABLAADCggIDgAFAAAAAA==.',['Ин']='Инсаидер:BAAALAAECggICAAAAA==.',['Йа']='Йатамат:BAABLAAECoEYAAIHAAgIURs3CACBAgAHAAgIURs3CACBAgAAAA==.',['Йо']='Йошшипитцу:BAAALAADCggICAAAAA==.',['Ке']='Кейхаос:BAAALAADCggICAAAAA==.Кертинор:BAAALAADCgYIBgAAAA==.',['Ки']='Киевлянин:BAAALAADCgYIBgAAAA==.',['Ко']='Кодзира:BAAALAAECgUIBQAAAA==.Коридорас:BAAALAADCggICAAAAA==.',['Кр']='Красафчегг:BAAALAADCgcIBwAAAA==.Кристэм:BAAALAAFFAIIAgAAAA==.',['Ку']='Кукундра:BAAALAADCgEIAQAAAA==.',['Кш']='Кшмр:BAAALAADCgcIBwAAAA==.',['Ле']='Летаэлий:BAAALAAECgcIEAAAAA==.',['Ли']='Лисандриса:BAAALAAECgIIAgAAAA==.',['Ло']='Логард:BAAALAADCgIIAgAAAA==.Лордтайм:BAAALAADCggICgAAAA==.',['Лу']='Лучвотьме:BAAALAAECgYICgAAAA==.',['Ма']='Магнетар:BAAALAADCggICQAAAA==.Маринис:BAAALAADCggIEAAAAA==.',['Ме']='Меняюпокд:BAAALAADCgUIBQAAAA==.Мерилинмонро:BAAALAADCgUIBQAAAA==.',['Ми']='Милостень:BAAALAAECgcIEQAAAA==.',['Мк']='Мкотролль:BAAALAADCgMIAwAAAA==.',['Мо']='Монакачан:BAAALAADCggIBQAAAA==.Морлеон:BAAALAAECgEIAQAAAA==.Мортдрэд:BAAALAADCgIIAgABLAADCggIDgAFAAAAAA==.',['Му']='Мумубаз:BAAALAADCggIFAAAAA==.',['Мэ']='Мэриалмахтиг:BAAALAAECgMIAwAAAA==.',['На']='Наару:BAAALAADCgEIAQAAAA==.',['Не']='Неван:BAAALAADCgcIBwAAAA==.Неприст:BAAALAAECgIIAgAAAA==.Неронун:BAAALAADCggIFAAAAA==.',['Ни']='Ниадра:BAAALAADCggIFgAAAA==.Никоретти:BAAALAAECgYIDAAAAA==.',['Ну']='Нудлес:BAAALAADCgYIBwAAAA==.',['Ок']='Оксинаген:BAAALAADCggIDgAAAA==.',['Пи']='Пивнаяволна:BAAALAADCgUIBgAAAA==.Пиво:BAAALAAFFAEIAQABLAAFFAIIAgAFAAAAAA==.Письок:BAAALAADCgcICAAAAA==.',['По']='Помпушечник:BAAALAADCgcIBwAAAA==.',['Пр']='Присумонь:BAAALAADCgMIAwAAAA==.Прохвосточка:BAAALAAECgYICAAAAA==.',['Ре']='Релиар:BAAALAADCgQIBAAAAA==.',['Са']='Сашкинс:BAAALAAECgEIAQAAAA==.',['Св']='Светоблик:BAAALAAECgYIDwAAAA==.',['Се']='Сексопотолог:BAAALAAECgYIDAAAAA==.',['Си']='Симфориом:BAAALAAECgcICgAAAA==.',['Сэ']='Сэндж:BAAALAADCgQIBAAAAA==.',['Сё']='Сё:BAAALAAECgYIDwAAAA==.',['Та']='Тавишенька:BAAALAAECgYIDwAAAA==.Таррхроник:BAAALAAECgcIEAAAAA==.',['То']='Топотелло:BAAALAAECgYIDwAAAA==.Точилочка:BAAALAADCgcICQAAAA==.',['Тр']='Трескунья:BAAALAAECgYIDwAAAA==.',['Фе']='Фелица:BAAALAAECggIDAAAAA==.Фенозепам:BAAALAAECgEIAQAAAA==.',['Фл']='Флабио:BAAALAADCgYIBgABLAAECgMIAQAFAAAAAA==.',['Фс']='Фсёмогущая:BAAALAADCggICAABLAAECgYIDQAFAAAAAA==.',['Ха']='Харонн:BAAALAAECgMIAwAAAA==.',['Хм']='Хмелеваар:BAAALAAECgEIAQAAAA==.',['Че']='Чержнок:BAAALAADCggICAAAAA==.',['Ша']='Шарик:BAAALAAECgEIAQAAAA==.',['Ши']='Шиварн:BAAALAAECgIIAgAAAA==.Шис:BAAALAAECgYICgAAAA==.',['Эм']='Эмильянка:BAAALAADCgcICQAAAA==.',['Эр']='Эрлит:BAAALAAECgEIAQABLAAECggIDwAFAAAAAA==.',['Эс']='Эскадос:BAAALAADCgQIBAAAAA==.Эскара:BAAALAADCgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end