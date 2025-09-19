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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Mage-Arcane','Mage-Frost','Warrior-Fury','Hunter-Marksmanship','Priest-Holy','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Frost','Paladin-Holy',}; local provider = {region='EU',realm='Борейскаятундра',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Ав']='Аварина:BAAALAADCgcIBwAAAA==.Авесалон:BAAALAADCgMIAwAAAA==.',['Ай']='Айронар:BAAALAADCggICAAAAA==.',['Ал']='Алексисвайс:BAAALAAECgYICAAAAA==.Алкобор:BAAALAADCggICAAAAA==.Алкосова:BAAALAAECgYIDgAAAA==.Альбирис:BAAALAADCgYIBQAAAA==.',['Ан']='Анаком:BAAALAADCggICAABLAADCggICAABAAAAAA==.Антилайф:BAAALAADCgcICwAAAA==.',['Ар']='Ариадна:BAAALAAECgYIBgAAAA==.Аркарир:BAAALAAECgQIBAAAAA==.Арката:BAAALAAECgMIAwAAAA==.Армагедон:BAAALAAECgIIAgAAAA==.Артелак:BAAALAAECgYICgAAAA==.Артемидда:BAAALAAECgMIAwAAAA==.Арука:BAAALAAECgYICAAAAA==.Архидруид:BAAALAAECgYICgAAAA==.',['Ас']='Астра:BAAALAAECgYIEgAAAA==.',['Аф']='Афанаревший:BAAALAADCgQIBAAAAA==.Афгуст:BAAALAAECgMIBQAAAA==.',['Аш']='Ашвейл:BAAALAADCggIDwAAAA==.Аштара:BAAALAADCgcIDQAAAA==.',['Ба']='Базукович:BAAALAADCgIIAgAAAA==.Барбелот:BAAALAADCgUIBQAAAA==.Бармалини:BAAALAAECgcIDwAAAA==.',['Бе']='Беймур:BAAALAAECgIIAwAAAA==.',['Би']='Биастмастер:BAAALAADCgUIBQAAAA==.Билик:BAAALAADCgMIAwAAAA==.',['Бл']='Блэквейл:BAAALAAFFAIIAgAAAA==.',['Бо']='Бокалвинишка:BAAALAAECgYIDgAAAA==.Боксерёног:BAAALAAECgEIAQAAAA==.Бомбоклат:BAAALAADCgQIBAABLAAECgMIBAABAAAAAA==.Ботася:BAAALAAFFAIIAgAAAA==.',['Бр']='Броксигара:BAAALAAECgcIDgAAAA==.',['Ва']='Вафлянутый:BAAALAADCggICAAAAA==.',['Вг']='Вгрызка:BAAALAADCgYIBgAAAA==.',['Ве']='Венэйбл:BAAALAAECgIIAwAAAA==.Вертусеич:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Вертусей:BAAALAAECgYICAAAAA==.',['Ви']='Визей:BAAALAADCggICAAAAA==.Визил:BAAALAADCgUIAwAAAA==.Винсольм:BAAALAAECgYIBgAAAA==.',['Во']='Войпель:BAACLAAFFIEFAAICAAMIaRX0AgAJAQACAAMIaRX0AgAJAQAsAAQKgRgAAgIACAiRIrMFABUDAAIACAiRIrMFABUDAAAA.Вольвелёля:BAAALAAECgYICgAAAA==.Воробейй:BAAALAAECgQIAgAAAA==.',['Вр']='Вреднюля:BAAALAAECgMIBAAAAA==.',['Вс']='Всалат:BAAALAADCggICAAAAA==.',['Га']='Гадюкинс:BAAALAAECgYICgAAAA==.Гачибосс:BAAALAAECggIDAAAAA==.',['Гл']='Глубокославх:BAAALAAECgEIAQAAAA==.',['Го']='Голтаррог:BAAALAADCggIDwAAAA==.',['Гр']='Громовина:BAAALAAECgcIDwAAAA==.Гротерр:BAAALAAECgMIAwAAAA==.',['Да']='Дайкокутэн:BAAALAADCggICAAAAA==.Дайонизос:BAAALAADCgQIBAAAAA==.Данбу:BAAALAADCggIFQAAAA==.Даркме:BAAALAADCgQIBgAAAA==.Даужповезло:BAAALAAECgEIAQAAAA==.',['Де']='Дедлукич:BAAALAAECgYIBgAAAA==.Дедтитана:BAABLAAECoEUAAMDAAcI4h8HFwBpAgADAAcI4h8HFwBpAgAEAAMI5RE+NACfAAAAAA==.Демонагонии:BAAALAADCgcIBwAAAA==.Демонмаг:BAAALAAECgYIDgAAAA==.',['Дж']='Дживиай:BAAALAADCgQIBAAAAA==.Джинтас:BAAALAAECgEIAQAAAA==.Джиудичи:BAAALAADCgYIBgAAAA==.Джонигалт:BAABLAAECoEYAAICAAgI6R3MCgC3AgACAAgI6R3MCgC3AgAAAA==.',['Ди']='Диикей:BAAALAAECgYIBgAAAA==.Дикийкал:BAAALAAECgIIAgAAAA==.Диктатус:BAAALAADCgcICQAAAA==.',['До']='Дональдпамп:BAAALAADCggICgAAAA==.Дорла:BAAALAAECgUICAAAAA==.',['Др']='Дракгатс:BAAALAAECgcIEAAAAA==.Драккарисс:BAAALAAECgYICwAAAA==.Другарика:BAAALAADCgYIBgAAAA==.Дрыгоног:BAAALAADCgEIAQAAAA==.',['Дф']='Дфлеш:BAAALAAECgYIBgAAAA==.',['Дэ']='Дэва:BAAALAAECgcIDgAAAA==.',['Дя']='Дядьковася:BAAALAADCggICwAAAA==.',['Еш']='Ешкинкрошкин:BAAALAAECgcIDQAAAA==.',['Жу']='Жупус:BAAALAADCggIEAABLAAECgYIDQABAAAAAA==.',['Жы']='Жыреч:BAAALAAECgIIAwAAAA==.',['За']='Заорду:BAAALAAECgEIAQAAAA==.Защитник:BAAALAADCgYIBgAAAA==.',['Зе']='Зеттайкен:BAAALAAECgMIBQAAAA==.',['Зо']='Зовузомби:BAAALAAECgcIEQAAAA==.',['Зр']='Зряваракачал:BAAALAADCggIEAAAAA==.',['Зу']='Зулджол:BAAALAADCggIEAAAAA==.Зулралу:BAAALAAECgcIDAAAAA==.',['Ил']='Илленгоф:BAAALAAECggIAQAAAA==.Ильичовский:BAAALAAECgMIAwAAAA==.Илэрион:BAAALAADCgcIDgAAAA==.',['Ин']='Иномарка:BAAALAAECgYIBwAAAA==.Инфлюенс:BAAALAAECgEIAQAAAA==.Инчантикс:BAAALAADCggIDwAAAA==.',['Ис']='Исильдор:BAABLAAECoEVAAIFAAgIfCGtCQDcAgAFAAgIfCGtCQDcAgAAAA==.',['Йу']='Йувикз:BAAALAAECgYIDgAAAA==.',['Ка']='Кагаяку:BAAALAAECgYIBgAAAA==.Каерея:BAAALAAECggIAgAAAA==.Кайраз:BAAALAADCgUIBQAAAA==.Камнепух:BAAALAAECggIAgAAAA==.Канакун:BAAALAAECgYICwAAAA==.Канаэль:BAAALAADCggIBQAAAA==.Карабиныч:BAAALAAECgcIEAAAAA==.Карриба:BAAALAAECgYICQAAAA==.Кацопис:BAAALAAECgQIBwAAAA==.',['Ке']='Кейрисс:BAAALAAECgcIEAAAAA==.Келлерган:BAAALAADCggICAAAAA==.',['Кз']='Кзварлок:BAAALAAECgYICgAAAA==.',['Ки']='Кимдаали:BAAALAADCgcIDgAAAA==.Киристраз:BAAALAAECgYICAAAAA==.Кифи:BAAALAADCgcIBwAAAA==.',['Кл']='Ключиломалка:BAAALAAECgQIBAABLAAFFAIIAgABAAAAAA==.',['Ко']='Кобретти:BAAALAADCggIFQAAAA==.Ковальскй:BAAALAAECgMIBwAAAA==.Козби:BAAALAAECgYICgAAAA==.Конрад:BAAALAADCgcICgAAAA==.Коппытень:BAAALAAECgYIDQAAAA==.Копчуша:BAAALAAECgEIAQAAAA==.Корешилидана:BAAALAADCgcIBwAAAA==.Косихо:BAAALAADCgMIAwAAAA==.Котэнегодует:BAAALAAECgMIBgAAAA==.',['Кр']='Красиваяшея:BAAALAAECgIIAgAAAA==.Кратконогая:BAAALAADCgUIBQAAAA==.Краямоейраны:BAAALAAECgYIBgAAAA==.Крокозябра:BAAALAAECgMIBAAAAA==.Крошкин:BAAALAAECgYICgAAAA==.',['Кт']='Ктокуда:BAAALAAECgQIBgAAAA==.',['Ку']='Кувшино:BAAALAAECgUIBwAAAA==.Кудажмать:BAAALAAECgMIBQAAAA==.Кузёныш:BAAALAAECgcIEAAAAA==.Куми:BAAALAADCggICAAAAA==.',['Кы']='Кыцуня:BAAALAAECgYICQAAAA==.',['Кэ']='Кэрриган:BAAALAADCgcICAAAAA==.',['Ла']='Лайв:BAAALAAECgYICgAAAA==.Лаймонд:BAAALAAECgcIDQAAAA==.',['Ле']='Леснаяфрея:BAAALAADCggICwAAAA==.',['Ли']='Лиен:BAAALAAECggIEQAAAA==.Лилланте:BAAALAADCgcIBwAAAA==.Лиссэн:BAAALAADCggICAAAAA==.',['Ло']='Лобаста:BAAALAAECgMIBAAAAA==.Лонька:BAAALAAECgcIBwABLAAFFAIIAgABAAAAAA==.Лоролькич:BAAALAAECggICAAAAA==.',['Лу']='Лугальмарад:BAAALAAECgQIBwAAAA==.',['Ма']='Мавпа:BAAALAADCgMIAwAAAA==.Магон:BAAALAADCgYIBgAAAA==.Максичай:BAABLAAECoEdAAIEAAgIyR4HBADbAgAEAAgIyR4HBADbAgAAAA==.Макхани:BAAALAADCgMIAwAAAA==.Малунис:BAAALAADCggICQAAAA==.Марсилес:BAABLAAECoEVAAIGAAgIuhSQEQAUAgAGAAgIuhSQEQAUAgAAAA==.Маффий:BAAALAAECgYICAAAAA==.',['Ме']='Мельнкорн:BAAALAADCgcIBwAAAA==.Менендес:BAAALAAECgIIAgAAAA==.Мерьем:BAABLAAECoEWAAIHAAgIlRBCHQDSAQAHAAgIlRBCHQDSAQAAAA==.',['Ми']='Мидиаль:BAAALAAECgUICAAAAA==.Милли:BAAALAADCggICAABLAADCggICAABAAAAAA==.Миллилол:BAAALAAECggIBgAAAA==.Минерал:BAAALAADCgEIAQAAAA==.Мифистофиль:BAAALAADCgYIBgAAAA==.',['Мо']='Молотокбика:BAAALAADCgYICwAAAA==.Молюск:BAAALAADCggIFAAAAA==.Монохром:BAAALAAECgMIBQAAAA==.Морфеа:BAAALAAECgUIBgAAAA==.',['Мр']='Мрамра:BAAALAADCgMIBAAAAA==.',['Му']='Мужтитана:BAAALAADCgcIBwAAAA==.',['Мэ']='Мэйрил:BAAALAADCgcIBwAAAA==.',['На']='Нагрогом:BAAALAADCgcICgAAAA==.Назарбаев:BAAALAAECggIEwAAAA==.Найкпро:BAAALAAECgQICQAAAA==.Найрра:BAAALAADCgcIDQAAAA==.',['Не']='Невий:BAAALAAFFAIIAgAAAA==.Негорюю:BAAALAADCgcIAQAAAA==.Немодель:BAAALAAECgMIAwAAAA==.Необия:BAAALAAECgcIEwAAAA==.Нефритянка:BAAALAAFFAIIAgAAAA==.Нехаленна:BAAALAADCggICQAAAA==.',['Ни']='Ниолетта:BAAALAAECgYICgAAAA==.Ниссин:BAAALAAECgYICgAAAA==.',['Нь']='Ньютон:BAAALAADCgYIBgABLAAECgcIDgABAAAAAA==.',['Нэ']='Нэйджи:BAAALAADCgUIBQAAAA==.',['Ню']='Нюркес:BAAALAAECgYIBgAAAA==.Нюркин:BAAALAAECgYIBgAAAA==.',['Ол']='Олета:BAABLAAECoEVAAMIAAgIox5uDgD2AQAJAAYImBukGQADAgAIAAYInx1uDgD2AQAAAA==.',['Он']='Онести:BAAALAADCgQIBAAAAA==.Онигукоосас:BAAALAADCgcIBwAAAA==.',['Ор']='Орбена:BAABLAAECoEWAAIFAAgIxBnoDwB8AgAFAAgIxBnoDwB8AgAAAA==.Орргазм:BAABLAAECoEbAAIKAAgISBaGDQBBAgAKAAgISBaGDQBBAgAAAA==.',['Па']='Паларт:BAAALAAECgYIEAAAAA==.Пандаманда:BAAALAAECgMIBQAAAA==.Пандашмыг:BAAALAAECgYICwAAAA==.Патиу:BAAALAADCgUIBQAAAA==.',['Пе']='Пельмешек:BAAALAADCgYIBgAAAA==.Пеяни:BAAALAADCggIFgAAAA==.',['Пи']='Пивашчи:BAAALAADCgcIBwAAAA==.Пижмак:BAAALAADCgcIDgAAAA==.',['Пл']='Плюс:BAAALAADCgcICwAAAA==.',['По']='Погорелый:BAAALAAECgYIDgAAAA==.Подстолпешим:BAAALAAECgUIBwAAAA==.Поиск:BAAALAAECgUICQAAAA==.',['Пр']='Простодру:BAAALAAECgYICgAAAA==.',['Пт']='Птимма:BAAALAAECgYICQAAAA==.Птюша:BAAALAAECgMIBQAAAA==.',['Пу']='Пузище:BAAALAADCgcIBgAAAA==.Пупарик:BAAALAADCggIDwAAAA==.',['Пё']='Пёрфектдемон:BAABLAAECoEYAAILAAgIEiVUAgBnAwALAAgIEiVUAgBnAwAAAA==.',['Ра']='Радамир:BAAALAADCgYIDgAAAA==.Радтхарани:BAAALAADCgcIBwAAAA==.Радфемка:BAAALAAECgcIDQAAAA==.Райталион:BAAALAAECgcIEAAAAA==.Ратха:BAAALAADCggIDwAAAA==.',['Ро']='Розоваяпопка:BAAALAAECgYIBgAAAA==.Роклин:BAAALAAECgQICQAAAA==.Россини:BAAALAAECgYICQAAAA==.',['Ру']='Руваа:BAAALAAECgMIBAAAAA==.',['Рь']='Рьюджи:BAAALAAECgYIBwAAAA==.',['Рэ']='Рэйенисс:BAAALAADCgcIDQAAAA==.',['Са']='Салтушка:BAAALAAECgYIBgABLAAECggIHQAEAMkeAA==.Сангра:BAAALAADCggICAAAAA==.Санэлиа:BAAALAAECgEIAQAAAA==.',['Св']='Свампик:BAAALAAECgYICQAAAA==.Святополк:BAAALAADCggICgAAAA==.',['Се']='Себела:BAAALAADCgUIBQAAAA==.Сенайя:BAAALAADCggIDwAAAA==.Сенамира:BAAALAAECgIIAgAAAA==.',['Си']='Сивийдуб:BAAALAADCgYICQAAAA==.Силльвана:BAAALAAECgMIBAAAAA==.Сильверпайн:BAAALAAECgQIDgAAAA==.Синийдедуля:BAAALAAECgYIDAAAAA==.',['Со']='Сонитка:BAAALAAECgEIAQAAAA==.Софако:BAAALAAECgMIBAAAAA==.Соффа:BAAALAAECgIIAgAAAA==.',['Ст']='Старсс:BAAALAAECgYIBwAAAA==.Стингрей:BAAALAADCgcICAAAAA==.Стиргвард:BAAALAAECgEIAQAAAA==.Стирдрак:BAAALAAECgMIAwAAAA==.Стоникпал:BAABLAAECoEVAAIMAAgI8iIIBgAqAwAMAAgI8iIIBgAqAwAAAA==.Стрексер:BAAALAAECgEIAQAAAA==.Стэксир:BAAALAADCggICgAAAA==.',['Су']='Суккума:BAAALAAFFAIIAgAAAA==.Супербладия:BAAALAAECgcIDgAAAA==.',['Сэ']='Сэнбонсакура:BAAALAAECgIIAgAAAA==.Сэрджавашама:BAAALAAECgIIAgAAAA==.',['Та']='Талйон:BAAALAADCggICAAAAA==.Тандеридж:BAAALAADCggIFAAAAA==.Таролог:BAAALAAECgMIBAAAAA==.',['Те']='Тейлаш:BAAALAADCggIDwAAAA==.Тефа:BAAALAADCggICQAAAA==.',['Ти']='Тиосульфат:BAAALAAECgQICQAAAA==.Тирандиель:BAAALAAECgYICAAAAA==.Титус:BAAALAADCgQIBwAAAA==.',['То']='Тоил:BAAALAAECgYIBgAAAA==.Торидал:BAAALAAECggIAQAAAA==.',['Тр']='Трахентэрн:BAAALAADCgMIAwAAAA==.Требл:BAAALAADCggICAAAAA==.Третийдоктор:BAAALAAECgYIDgAAAA==.Трипальца:BAAALAAECgYICgAAAA==.Трулендар:BAAALAAECgEIAQAAAA==.',['Ту']='Тудирим:BAAALAADCgcIAgAAAA==.Турбохомяк:BAAALAADCggICAAAAA==.',['Ть']='Тьяри:BAAALAAECgYIBgAAAA==.',['Тё']='Тёмнаякнига:BAAALAAECgYIDAAAAA==.',['Уг']='Угрюмый:BAABLAAECoEXAAIMAAgI+Bt5EwB8AgAMAAgI+Bt5EwB8AgAAAA==.',['Уд']='Ударыч:BAAALAADCggIEQAAAA==.',['Ум']='Умбилэк:BAAALAADCgQIBAAAAA==.',['Ут']='Утипуськин:BAAALAAECgYIBgAAAA==.',['Фа']='Файнол:BAAALAAECgMIAwAAAA==.Фансон:BAAALAADCggICAAAAA==.Фарамант:BAAALAADCgMIAwAAAA==.',['Фе']='Фельт:BAAALAAECgcIEAAAAA==.Фенидрон:BAAALAAECgEIAQAAAA==.',['Фи']='Фиарен:BAAALAAECgEIAQAAAA==.',['Фо']='Фоксдк:BAABLAAECoEUAAINAAgIThOEKQDrAQANAAgIThOEKQDrAQAAAA==.',['Фу']='Фукач:BAABLAAECoEWAAIOAAgIwCG/AQD/AgAOAAgIwCG/AQD/AgAAAA==.Фукичь:BAAALAAECgYIDAAAAA==.',['Хи']='Хинатахьюга:BAAALAAECgcICwAAAA==.',['Хр']='Хромойс:BAAALAADCgcIDgAAAA==.',['Це']='Целофан:BAAALAADCggICAAAAA==.Цер:BAAALAAECgcICgAAAA==.',['Ци']='Цири:BAAALAAECgUIAgAAAA==.',['Че']='Черепусечка:BAAALAAECgMIBAAAAA==.',['Чи']='Чикилоко:BAAALAADCgYICwAAAA==.',['Ша']='Шадия:BAAALAADCgMIAwABLAADCggICAABAAAAAA==.Шаксаар:BAAALAAECgMIBAAAAA==.Шаланей:BAAALAADCggICAAAAA==.',['Шо']='Шог:BAAALAAECgYICgAAAA==.Шогг:BAAALAADCggIFgAAAA==.',['Шу']='Шушпанка:BAAALAAECggIAQAAAA==.',['Щу']='Щупус:BAAALAAECgYIDQAAAA==.',['Эл']='Эльнира:BAAALAAECgYICgABLAAECggIGAALABIlAA==.Эльтараа:BAAALAAECgEIAQAAAA==.',['Эм']='Эмеркомм:BAAALAAECggIEwAAAA==.Эмпатия:BAAALAAECgMIBQAAAA==.',['Эн']='Эниса:BAAALAADCgcIBwAAAA==.',['Эр']='Эрдвадедва:BAAALAADCgYICgAAAA==.Эрунир:BAAALAAECgYICAAAAA==.',['Юн']='Юнаруками:BAAALAADCggICgAAAA==.Юность:BAAALAADCgQIBAAAAA==.',['Яр']='Яровицкая:BAAALAAECgIIAgAAAA==.',['Ях']='Яхантишка:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end