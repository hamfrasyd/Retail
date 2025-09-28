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
 local lookup = {'Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Paladin-Retribution','Priest-Holy','Priest-Discipline','DeathKnight-Blood','Evoker-Devastation','Mage-Frost','Hunter-Marksmanship','DeathKnight-Unholy','Mage-Arcane','Mage-Fire','Druid-Restoration','Druid-Balance','DemonHunter-Havoc','Warrior-Protection','Rogue-Assassination','Priest-Shadow','DemonHunter-Vengeance','DeathKnight-Frost','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Hunter-BeastMastery',}; local provider = {region='EU',realm='Ясеневыйлес',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аб']='Абазин:BAABLAAECoEwAAIBAAgIzhu3JwB8AgABAAgIzhu3JwB8AgAAAA==.',['Ав']='Авенморр:BAAALAADCgYIDAAAAA==.Авотисова:BAAALAAECgEIAQAAAA==.',['Аг']='Агашка:BAAALAAECgQIBAAAAA==.',['Ад']='Аджэ:BAACLAAFFIEYAAMCAAYI/RK3AwDTAQACAAYI/RK3AwDTAQADAAMIqQkAAAAAAAAsAAQKgSkAAwIACAgyIVoVAK8CAAIACAgyIVoVAK8CAAMABQjxFJtgAGUBAAAA.Адорнедаксис:BAAALAADCgIIAgAAAA==.Адэя:BAAALAAECggIEwAAAA==.',['Аз']='Азмодиан:BAAALAAECgMIBgAAAA==.',['Ак']='Акс:BAAALAAECgYIAQAAAA==.',['Ал']='Алазьен:BAAALAAECggICAAAAA==.Александр:BAAALAADCggIDgAAAA==.Алонирия:BAAALAADCggICAAAAA==.',['Ам']='Амаури:BAAALAAECgEIAQAAAA==.Амигдала:BAAALAADCgcIBwAAAA==.Амилла:BAAALAADCggIEAAAAA==.Амонзул:BAAALAADCggIDgAAAA==.Амоник:BAAALAAECggIEAAAAA==.',['Ан']='Андромедаа:BAABLAAECoEqAAICAAgIbB3cGwCJAgACAAgIbB3cGwCJAgAAAA==.Анкора:BAAALAADCggIDgAAAA==.Анманерка:BAABLAAECoElAAMEAAgI1hw3BgCHAgAEAAgI1hw3BgCHAgAFAAYIrRD5cgBkAQAAAA==.',['Ар']='Ариаднаа:BAAALAADCgEIAQABLAADCgEIAQAGAAAAAA==.',['Ба']='Баграттион:BAAALAADCgcIDQABLAAECgMIBgAGAAAAAA==.Базлайккер:BAABLAAECoEqAAIHAAgIfxiOUAAiAgAHAAgIfxiOUAAiAgAAAA==.Бакиэ:BAAALAAECggIDgAAAA==.Банкай:BAAALAADCggIDgAAAA==.Бартоламъю:BAAALAAECgQIAwAAAA==.',['Бе']='Безлад:BAAALAAECgEIAQAAAA==.Беспопутал:BAAALAAECgEIAQAAAA==.',['Би']='Бицуха:BAABLAAECoEnAAMIAAgInR1xFgCdAgAIAAgInR1xFgCdAgAJAAIIQRuNIACqAAAAAA==.',['Ва']='Валефор:BAAALAAECgEIAQAAAA==.Ванс:BAAALAAECggICAAAAA==.',['Ве']='Венесуела:BAAALAADCgEIAQAAAA==.',['Ви']='Винтерпэйн:BAAALAAECgUIBQAAAA==.Витьер:BAAALAAECgQIBgAAAA==.Вич:BAAALAAECgYIBgABLAAFFAYIGgAFAJYaAA==.',['Вл']='Власина:BAAALAADCgUIBQAAAA==.',['Во']='Ворзах:BAAALAAECgQIBgABLAAECgcIHwAHADcfAA==.',['Га']='Гаврик:BAAALAAECggICQAAAA==.',['Ге']='Гедерт:BAACLAAFFIERAAIKAAUIBB+MAgDHAQAKAAUIBB+MAgDHAQAsAAQKgSsAAgoACAgdJosBAGMDAAoACAgdJosBAGMDAAAA.Гекконид:BAABLAAECoEfAAILAAcIXA4QMgB2AQALAAcIXA4QMgB2AQAAAA==.Геллатель:BAABLAAECoEfAAIHAAcIARXsdADPAQAHAAcIARXsdADPAQAAAA==.Герунд:BAABLAAECoEWAAIMAAgIuyDbCQDiAgAMAAgIuyDbCQDiAgAAAA==.',['Гл']='Гладариель:BAAALAADCgEIAQAAAA==.',['Го']='Год:BAAALAADCgcIBwAAAA==.Гопнниик:BAABLAAECoEqAAINAAgIFxiqLgD0AQANAAgIFxiqLgD0AQAAAA==.Гордарикс:BAAALAADCggICQAAAA==.Госум:BAAALAAECgYIBgAAAA==.',['Да']='Дамасен:BAAALAAECgcIBwAAAA==.',['Де']='Деотэ:BAAALAAECgEIAQAAAA==.Деткагэбби:BAAALAAECgUICAAAAA==.',['Дж']='Джарадмайя:BAABLAAECoEWAAIHAAgI+RBnggC1AQAHAAgI+RBnggC1AQAAAA==.Джейлен:BAAALAADCggIEAAAAA==.Джерси:BAACLAAFFIEGAAIMAAIIRggIEQCDAAAMAAIIRggIEQCDAAAsAAQKgSIAAgwACAjxFXUZACsCAAwACAjxFXUZACsCAAAA.Джинтал:BAAALAAECgUIAwAAAA==.',['Ди']='Дихангер:BAABLAAECoElAAIMAAcI0CLUDgCYAgAMAAcI0CLUDgCYAgAAAA==.',['Дк']='Дкалис:BAABLAAECoEfAAIOAAgIVhlnCwCHAgAOAAgIVhlnCwCHAgAAAA==.',['Др']='Дракодоминус:BAAALAADCgYIBgAAAA==.',['Дэ']='Дэдрианна:BAAALAAECgYICwAAAA==.Дэрол:BAAALAAECgYIDQAAAA==.',['Ее']='Еек:BAAALAADCgcIBwAAAA==.',['Еж']='Ежикь:BAAALAADCggICAAAAA==.',['Жи']='Живия:BAAALAADCgEIAQAAAA==.',['За']='Залупяо:BAAALAAECgYIBgAAAA==.Зачарушка:BAACLAAFFIEGAAMPAAMIVxufIgC/AAAPAAMIVxufIgC/AAAQAAEIDQAAAAAAAAAsAAQKgS0AAg8ACAjXIzENACQDAA8ACAjXIzENACQDAAAA.',['Зв']='Зв:BAAALAAECggIBgAAAA==.',['Зл']='Злаямразь:BAABLAAECoEeAAIMAAgIpAq0PgBQAQAMAAgIpAq0PgBQAQAAAA==.Злойдэни:BAAALAAECgMICQAAAA==.',['Зу']='Зузич:BAAALAAECggIAQAAAA==.Зулатек:BAAALAAECgEIAQAAAA==.',['Ил']='Иллигран:BAAALAAECggICQABLAAECggIFgAMALsgAA==.Ильфина:BAAALAAECgMIAwAAAA==.',['Им']='Иммолатус:BAAALAADCgMIAQABLAAECgMIBgAGAAAAAA==.Имуэрто:BAAALAADCggIEQABLAAECgMIBgAGAAAAAA==.',['Ин']='Инсаидер:BAAALAAECggICAAAAA==.',['Их']='Ихвильнихт:BAAALAAECgEIAQAAAA==.',['Йа']='Йазво:BAAALAAECgcICgAAAA==.Йатамат:BAACLAAFFIEIAAIRAAMIfxUNDQDcAAARAAMIfxUNDQDcAAAsAAQKgSwAAxEACAgVIXgJAPcCABEACAgVIXgJAPcCABIABAhjCf5qAL8AAAAA.',['Йо']='Йошшипитцу:BAAALAADCggICAAAAA==.',['Ка']='Капибара:BAAALAADCgQIBAAAAA==.Капслитно:BAAALAAECgYIBgAAAA==.Каражан:BAAALAADCgcIBwAAAA==.',['Ке']='Кейхаос:BAAALAAFFAIIAgAAAA==.Кертинор:BAAALAADCgYIBgAAAA==.',['Ки']='Киевлянин:BAAALAADCgYIBgAAAA==.',['Кл']='Клер:BAAALAADCgYIBgAAAA==.',['Ко']='Кодзира:BAABLAAECoEcAAIRAAgI/xhgIgA3AgARAAgI/xhgIgA3AgAAAA==.Конкисто:BAAALAADCggIFgABLAAECgMIBgAGAAAAAA==.Кореньдруид:BAAALAAFFAIIAgAAAA==.Коридорас:BAAALAAECgcIBwAAAA==.',['Кр']='Красафчегг:BAAALAADCgcIBwAAAA==.Криматор:BAAALAADCggIDAAAAA==.Кристэм:BAACLAAFFIEMAAITAAQINBo5CwBlAQATAAQINBo5CwBlAQAsAAQKgTEAAhMACAgoJOUQABoDABMACAgoJOUQABoDAAAA.',['Ку']='Кукундра:BAAALAADCgEIAQAAAA==.',['Кш']='Кшмр:BAAALAAECgYICAAAAA==.',['Ле']='Лелок:BAAALAADCgYIBQAAAA==.Летаэлий:BAABLAAECoEcAAIUAAgItRw0DwCeAgAUAAgItRw0DwCeAgAAAA==.Лечюсексом:BAACLAAFFIEQAAICAAUIHhqsBAC4AQACAAUIHhqsBAC4AQAsAAQKgSYAAwIACAj1IN4NAOICAAIACAj1IN4NAOICAAMABAitCXCEANQAAAAA.',['Ли']='Лилайса:BAAALAAECgYIDQAAAA==.Линэдар:BAAALAAECggIDwAAAA==.Лисандриса:BAAALAAECgQIBwABLAAECgYIBgAGAAAAAA==.',['Ло']='Логард:BAAALAAECggICwABLAAFFAMICgAVAKMaAA==.Лордтайм:BAAALAADCggIDwAAAA==.',['Лу']='Лучвотьме:BAABLAAECoEYAAMIAAYIvBIqVwBXAQAIAAYIvBIqVwBXAQAWAAEIYwXckQAhAAAAAA==.',['Ма']='Магнетар:BAACLAAFFIEGAAITAAIIVx7xIACoAAATAAIIVx7xIACoAAAsAAQKgRcAAhMACAiuHu8dAM8CABMACAiuHu8dAM8CAAAA.Мареро:BAABLAAECoEgAAIUAAgIpAVoTAACAQAUAAgIpAVoTAACAQAAAA==.Маринис:BAABLAAECoEXAAIXAAgIAweELQAXAQAXAAgIAweELQAXAQAAAA==.Марселинка:BAAALAADCgIIAgAAAA==.',['Ме']='Медунна:BAAALAAECgEIAQAAAA==.Меланхолиса:BAAALAADCgYICwABLAAFFAIIBgAMAEYIAA==.Меняюпокд:BAAALAAECgYIBgAAAA==.Мерилинмонро:BAAALAADCgcIDAAAAA==.',['Ми']='Милостень:BAACLAAFFIEIAAIJAAIIfRjcAQCYAAAJAAIIfRjcAQCYAAAsAAQKgSsAAwkACAhjHhMDAKkCAAkACAhjHhMDAKkCABYABghJBI1kAOoAAAAA.Мистери:BAAALAAECggIDAAAAA==.',['Мк']='Мкотролль:BAAALAAECgEIAgAAAA==.',['Мо']='Мокрыйвесь:BAAALAAECgUIBAABLAAFFAIIAgAGAAAAAA==.Морлеон:BAAALAAECgIIAwAAAA==.Мортдрэд:BAAALAADCgIIAgABLAAECgMIBgAGAAAAAA==.',['Му']='Мумубаз:BAAALAADCggIHAAAAA==.Муррки:BAAALAAECggIAQAAAA==.',['Мэ']='Мэриалмахтиг:BAAALAAECgMIAwAAAA==.',['На']='Наару:BAAALAAECgYIEgAAAA==.',['Не']='Неван:BAAALAADCgcIBwAAAA==.Неприст:BAAALAAECgIIAgAAAA==.Неронун:BAAALAAECgEIAQAAAA==.',['Ни']='Ниадра:BAAALAADCggIHQAAAA==.Никоретти:BAABLAAECoEiAAIPAAgI9hoQOABMAgAPAAgI9hoQOABMAgAAAA==.Нитротитан:BAAALAAECggIDgAAAA==.',['Ну']='Нудлес:BAAALAADCgYIBwAAAA==.',['Ок']='Оксиморон:BAAALAAECgYIBQAAAA==.Оксинаген:BAAALAAECgEIAQAAAA==.',['Ор']='Оргнар:BAAALAAECggIEAAAAA==.',['Па']='Памиэль:BAAALAAECggIDAAAAA==.Паулус:BAAALAADCggICAAAAA==.',['Пе']='Пенталгин:BAAALAAFFAIIAgAAAA==.',['Пи']='Пиво:BAACLAAFFIEKAAIOAAMIhBEWBgDwAAAOAAMIhBEWBgDwAAAsAAQKgSUAAg4ACAjpHhcHANgCAA4ACAjpHhcHANgCAAEsAAUUAwgKAAcA7RAA.Письок:BAAALAAECgEIAQAAAA==.',['По']='Полудурак:BAAALAAECgYIEAABLAAFFAIIAgAGAAAAAA==.Помпушечник:BAAALAADCgcICQAAAA==.',['Пр']='Присумонь:BAAALAADCgYIDgAAAA==.Прохвосточка:BAABLAAECoEiAAIYAAgIZh9uHQDcAgAYAAgIZh9uHQDcAgAAAA==.',['Ра']='Распутница:BAAALAADCgcICAAAAA==.Рашгор:BAAALAAECgIIAgAAAA==.',['Ре']='Реально:BAAALAAECgYICQAAAA==.Релиар:BAAALAADCgQIBAAAAA==.',['Ру']='Руина:BAAALAADCggICAAAAA==.',['Рэ']='Рэстал:BAAALAAECggIEAAAAA==.',['Са']='Сакрифайсер:BAAALAADCggICwABLAAECgMIBgAGAAAAAA==.Самарлия:BAAALAADCggICAAAAA==.Саурэлия:BAAALAAECgQIBgAAAA==.Сашкинс:BAAALAAECgMIBQAAAA==.',['Св']='Светоблик:BAABLAAECoEjAAIHAAgIgCQ1CwBEAwAHAAgIgCQ1CwBEAwAAAA==.',['Се']='Сексопотолог:BAABLAAECoEhAAMCAAgIlx2EFwCiAgACAAgIlx2EFwCiAgADAAYI9BDzXABxAQABLAAFFAIIAgAGAAAAAA==.',['Си']='Симфориом:BAABLAAECoEdAAMPAAcIqwsNdACLAQAPAAcIqwsNdACLAQAQAAUIpwUqEQC5AAAAAA==.',['Ск']='Скриок:BAAALAADCggIEAAAAA==.',['Су']='Сурэй:BAAALAAECgYICQABLAAECggIFgAMALsgAA==.',['Сэ']='Сэндж:BAAALAAECgYIDwAAAA==.',['Сю']='Сюна:BAAALAADCgcIBwAAAA==.',['Сё']='Сё:BAABLAAECoEhAAQZAAcIHBUnNAA7AQAZAAUI0RInNAA7AQAaAAYI/xIwJgAoAQAbAAUICwlRNgC+AAAAAA==.',['Та']='Тавишенька:BAABLAAECoEqAAMCAAgIyxBoYACYAQACAAgIyxBoYACYAQADAAQISgZQiwCzAAAAAA==.Таррхроник:BAABLAAECoEnAAICAAgIexZKNwAUAgACAAgIexZKNwAUAgAAAA==.',['То']='Топотелло:BAABLAAECoEcAAIcAAcI1Re4bgCjAQAcAAcI1Re4bgCjAQAAAA==.Точилочка:BAAALAADCgcICQAAAA==.',['Тр']='Трескунья:BAABLAAECoEqAAIJAAgI1x33AgCtAgAJAAgI1x33AgCtAgAAAA==.',['Тэ']='Тэмпара:BAAALAADCgcIBwABLAAFFAIIBgAMAEYIAA==.',['Ул']='Улыбнина:BAAALAADCggICAAAAA==.',['Уф']='Уффка:BAAALAAECgYIBgABLAAFFAIIBgAMAEYIAA==.',['Фе']='Фелица:BAACLAAFFIELAAIHAAUIaw0lBwCQAQAHAAUIaw0lBwCQAQAsAAQKgSoAAgcACAiOIHIkALwCAAcACAiOIHIkALwCAAAA.Фенозепам:BAAALAAECgEIAQAAAA==.Фералхил:BAAALAAECgQIBAAAAA==.',['Фл']='Флабио:BAAALAAECggIBgABLAAFFAIIAgAGAAAAAA==.',['Фо']='Фонгорн:BAAALAAECgMIAwAAAA==.',['Фс']='Фсёмогущая:BAAALAAECgYIBgABLAAFFAIIBgAMAEYIAA==.',['Ха']='Ханн:BAAALAADCggIDwAAAA==.Харонн:BAAALAAECgcIEgAAAA==.',['Хм']='Хмелеваар:BAABLAAECoEWAAIaAAgIiRnPFADoAQAaAAgIiRnPFADoAQAAAA==.',['Че']='Чержнок:BAAALAADCggICAAAAA==.',['Ша']='Шамара:BAAALAAECgIIAgAAAA==.Шарик:BAAALAAECgUIDwABLAAECgYIDQAGAAAAAA==.',['Ши']='Шис:BAACLAAFFIEFAAMcAAIIBiA5GQDBAAAcAAIIBiA5GQDBAAANAAEIewXnLwA2AAAsAAQKgSgAAw0ACAhgJFQMAPYCAA0ACAhMIVQMAPYCABwACAiAI6wTAO4CAAAA.',['Эл']='Элинриэль:BAAALAAECgEIAgAAAA==.',['Эм']='Эмильянка:BAAALAADCgcICQAAAA==.',['Эн']='Эндалия:BAAALAADCgcIDQAAAA==.Энхмар:BAAALAADCggICAAAAA==.Энчантикс:BAAALAAECgYIDAAAAA==.',['Эр']='Эрлит:BAAALAAECggICgABLAAECggIFgAMALsgAA==.',['Эс']='Эскадос:BAAALAADCggIFwAAAA==.Эскара:BAAALAADCgIIAgAAAA==.',['Яг']='Яглухой:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end