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
 local lookup = {'DeathKnight-Unholy','Unknown-Unknown','Hunter-BeastMastery','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Druid-Balance','Druid-Restoration','Mage-Fire','Mage-Arcane',}; local provider = {region='EU',realm='ЧерныйШрам',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Ав']='Авторитет:BAAALAAECgMIBQAAAA==.',['Ае']='Аелин:BAAALAAECgYICQAAAA==.',['Аз']='Азамагг:BAAALAAECgcIDwAAAA==.',['Аи']='Аилдозер:BAAALAAECgIIAgAAAA==.Аиса:BAAALAAECgIIAgAAAA==.',['Ак']='Акена:BAAALAADCgcIBwAAAA==.',['Ал']='Алаявишня:BAAALAADCgUIBQAAAA==.Албедо:BAABLAAECoEYAAIBAAgIyCSwAABXAwABAAgIyCSwAABXAwAAAA==.Алитэя:BAAALAAECgcIEwAAAA==.Альгуль:BAAALAAECgcIDgAAAA==.',['Ам']='Амарторион:BAAALAADCggIDQAAAA==.',['Ан']='Анахранист:BAAALAADCgUIBQAAAA==.Андлонель:BAAALAADCggICQAAAA==.',['Ап']='Апоне:BAAALAADCggICAAAAA==.',['Ар']='Арба:BAAALAADCgIIAgAAAA==.Арокс:BAAALAADCggICAAAAA==.',['Ас']='Аскагат:BAAALAAECgQIBQAAAA==.Ассонанс:BAAALAADCgUICAAAAA==.Асфоделика:BAAALAADCggIDQAAAA==.',['Ау']='Аурел:BAAALAADCgEIAQAAAA==.',['Ба']='Батбат:BAAALAADCgMIAwAAAA==.Баття:BAAALAAECgUIBgAAAA==.',['Бе']='Бесоватный:BAAALAADCgIIAgAAAA==.Бесточечно:BAAALAAECgYICQAAAA==.',['Би']='Бикко:BAAALAAECgUIBQAAAA==.Биочифир:BAAALAAECgUICQAAAA==.',['Бл']='Блеба:BAAALAAECggICAAAAA==.',['Бо']='Болтпро:BAAALAAECgYICQAAAA==.',['Бр']='Бринна:BAAALAAECgEIAQAAAA==.Брфф:BAAALAAECggIEQAAAA==.',['Бу']='Бурбон:BAAALAAECgcIEgAAAA==.Бурбонд:BAAALAADCggICAABLAAECgcIEgACAAAAAA==.Бурбэн:BAAALAAECgYIBgABLAAECgcIEgACAAAAAA==.',['Бы']='Бычказавр:BAAALAAECgMIBQAAAA==.',['Ва']='Вайлинкс:BAAALAAECgYIDAAAAA==.Ванястрела:BAAALAADCggICAABLAAECgcIEgACAAAAAA==.Вареныйбычок:BAAALAADCgQIBAAAAA==.',['Ве']='Вечнодум:BAAALAAECgYIBgAAAA==.',['Ви']='Вианда:BAAALAADCgUIBgAAAA==.Вивисектор:BAAALAADCggICAAAAA==.Винлиден:BAAALAADCgYIDAAAAA==.',['Вл']='Влатали:BAAALAADCggICAAAAA==.',['Во']='Водочница:BAAALAAECgcICAAAAA==.Волосатыйдяд:BAAALAADCgYIBwAAAA==.Вомачка:BAAALAAECggIBgAAAA==.',['Вэ']='Вэйди:BAAALAAECgIIAwAAAA==.',['Га']='Галлиано:BAAALAADCggIDQAAAA==.Гасслин:BAAALAAECgcIDAAAAA==.',['Ге']='Гервулф:BAAALAAECgYIEwAAAA==.',['Да']='Далас:BAAALAAECgYICQAAAA==.Данталиа:BAAALAADCggIBwAAAA==.Даридобро:BAAALAAECgYICQAAAA==.Даюмракстоим:BAAALAADCgcIBwAAAA==.',['Де']='Демлун:BAAALAAECgYICQAAAA==.Держивщи:BAAALAAECgIIAgAAAA==.Держисвет:BAAALAADCggIDwABLAAECgIIAgACAAAAAA==.Детстроук:BAABLAAECoEWAAIDAAgIAxp7EAB6AgADAAgIAxp7EAB6AgAAAA==.',['Дж']='Джоахим:BAAALAAECgcIEAAAAA==.',['Ди']='Диаблох:BAAALAADCgMIAwAAAA==.',['Дм']='Дметриос:BAAALAADCgcIBwAAAA==.',['До']='Доллар:BAAALAAECgYICgAAAA==.Долрун:BAAALAADCggICAAAAA==.Дорн:BAAALAADCggICAAAAA==.',['Др']='Дракаронкс:BAAALAAECgYIBwAAAA==.Дрогаш:BAAALAADCgcIBwABLAAECgcIFAAEAPcgAA==.Дроухарт:BAAALAAECgYIDAAAAA==.Друидка:BAAALAADCgIIAgAAAA==.',['Ду']='Душку:BAAALAADCgYIBgAAAA==.',['Дэ']='Дэксич:BAAALAADCggICQAAAA==.',['Ел']='Елань:BAAALAAECgEIAQAAAA==.',['Ем']='Емели:BAAALAAECgMIAwAAAA==.Емки:BAAALAAECgMIBAAAAA==.Еммел:BAAALAADCggICAAAAA==.',['Жи']='Жигулевский:BAAALAADCggICAAAAA==.',['Жр']='Жрицальвица:BAAALAADCgcIBwAAAA==.',['Жу']='Жушка:BAAALAADCggIHQABLAAECgIIAgACAAAAAA==.',['За']='Завран:BAAALAADCggIDgAAAA==.Завязываю:BAAALAADCggICAAAAA==.',['Зе']='Зекхан:BAAALAADCgUIBQAAAA==.',['Зо']='Золоман:BAAALAAECgQIBAAAAA==.Золотойбой:BAAALAADCgcICAAAAA==.',['Зу']='Зубаскалл:BAAALAADCggICwAAAA==.',['Зэ']='Зэфирчик:BAAALAAECgYICQAAAA==.',['Ив']='Ивеллиос:BAAALAAECgQICAAAAA==.',['Иг']='Игрунья:BAAALAAECgYIDQAAAA==.',['Ил']='Иллиинэль:BAAALAADCgEIAQAAAA==.Иллитида:BAAALAAECgYIBwAAAA==.',['Иш']='Ишараджи:BAAALAADCgYIBgAAAA==.',['Йо']='Йолаанди:BAAALAAECgYICwAAAA==.Йордлс:BAAALAAECgEIAgAAAA==.',['Ка']='Кайк:BAAALAAECgYIDAAAAA==.Кайфушка:BAAALAADCggICAAAAA==.Калезгос:BAAALAADCggIDAAAAA==.Камазкала:BAAALAAECgUIBgAAAA==.Караумка:BAAALAADCgMIAwAAAA==.Каёни:BAAALAAECgIIAgAAAA==.',['Ке']='Кекл:BAAALAAECgEIAQABLAAFFAIIBAACAAAAAA==.',['Ки']='Кикей:BAAALAADCggICQAAAA==.Киоя:BAAALAADCggICAAAAA==.',['Кн']='Кнама:BAAALAAECggICAAAAA==.',['Ко']='Коварныйкусь:BAAALAAECgMIAwAAAA==.',['Кр']='Красняш:BAAALAAECgMIBwAAAA==.Крушимир:BAAALAAECgEIAQAAAA==.',['Кс']='Ксалотат:BAAALAADCgIIAgAAAA==.',['Ку']='Курящийпро:BAAALAAECgYICAAAAA==.',['Къ']='Къюби:BAAALAADCgcIBwAAAA==.',['Ла']='Лавандоблеба:BAAALAADCgYIBgABLAAECggICAACAAAAAA==.Ламаэ:BAABLAAECoEVAAMFAAgIRCN0AgAvAwAFAAgIRCN0AgAvAwAGAAEIuxe4GQBGAAAAAA==.Ланиспорт:BAAALAADCgMIAwAAAA==.',['Ле']='Леонус:BAAALAAECgYIBgAAAA==.Леопарддва:BAAALAADCgcIBwAAAA==.',['Ли']='Либерал:BAAALAAECggICQAAAA==.Литий:BAAALAADCggIDwAAAA==.',['Ло']='Логон:BAAALAAECgIIAgAAAA==.Лордпафос:BAAALAADCgYIBgAAAA==.',['Лю']='Люйкасу:BAAALAADCggIEAAAAA==.Лютиен:BAAALAAECgMICQAAAA==.',['Ма']='Маазик:BAAALAAECgIIAgAAAA==.Мадлайт:BAAALAAECgIIAwAAAA==.Макгонагл:BAAALAADCgYIBgAAAA==.Малейн:BAABLAAECoEUAAIDAAgI1Rp3DQCfAgADAAgI1Rp3DQCfAgAAAA==.Маромаса:BAAALAAECgYICgAAAA==.Марфушка:BAAALAADCggIGAAAAA==.Матрада:BAAALAADCgUIBQAAAA==.',['Мд']='Мджит:BAABLAAECoEUAAIHAAgIahvYEwAIAgAHAAgIahvYEwAIAgAAAA==.',['Ме']='Мейер:BAAALAAFFAEIAQAAAA==.Мейникс:BAAALAAECggICAAAAA==.Мекран:BAAALAAECgMIAwAAAA==.Мелиноя:BAAALAAECgQIBAAAAA==.Мелифарро:BAAALAADCggICAAAAA==.Меломениа:BAAALAAECgUIBQAAAA==.Мертвечино:BAAALAADCgIIAgAAAA==.Меснта:BAAALAADCgMIAwAAAA==.',['Ми']='Мисмунлайт:BAAALAAECgQIBAAAAA==.Митра:BAAALAADCgMIAQAAAA==.',['Мо']='Могуччи:BAAALAAECgYIBwAAAA==.Монархсатору:BAAALAAECgQIAwAAAA==.Монфрэди:BAAALAAECgYIDQAAAA==.',['Му']='Музыкант:BAAALAADCgcIBwAAAA==.Муррчачо:BAABLAAECoEUAAIIAAgI5yCcBQCxAgAIAAgI5yCcBQCxAgAAAA==.',['Мь']='Мьюта:BAAALAAECgcIDQAAAA==.',['На']='Намгала:BAAALAADCgIIAgAAAA==.Натризим:BAAALAAECgIIAgAAAA==.',['Не']='Негля:BAAALAADCgIIAgAAAA==.Неиджи:BAAALAAECgcIEgAAAA==.Нелифер:BAAALAAECgYIBgAAAA==.',['Ни']='Нинзя:BAAALAADCgcIDQABLAAECgIIAgACAAAAAA==.Нирелин:BAAALAADCgcIAQAAAA==.Нитида:BAAALAAECggIDwAAAA==.',['Нэ']='Нэскк:BAAALAADCggIEAAAAA==.',['Од']='Оджи:BAAALAADCggIEQAAAA==.',['Ок']='Окитсу:BAAALAADCgcICQAAAA==.',['Ом']='Омегаблеба:BAAALAADCggIBAABLAAECggICAACAAAAAA==.',['Ор']='Ороро:BAAALAADCgEIAQAAAA==.',['От']='Отсаске:BAAALAADCgQIAgAAAA==.Оттис:BAAALAADCgcIDgAAAA==.',['Па']='Палаводная:BAAALAAECgUIDgAAAA==.Палапалинт:BAAALAADCgcIDQAAAA==.Пардонь:BAAALAAECgMIBAAAAA==.Пардоньти:BAAALAADCggICAAAAA==.',['Пе']='Перрсиваль:BAAALAAECgcIEgAAAA==.',['Пи']='Пивозаврус:BAAALAAECggICAAAAA==.',['По']='Позитивх:BAAALAAECggIBgAAAA==.Полдеда:BAAALAAECgMICAAAAA==.Порнхасбик:BAAALAADCgEIAQAAAA==.Похмельмен:BAAALAADCgYIBgAAAA==.',['Пр']='Примейлин:BAAALAADCgcIBwAAAA==.Просекориане:BAAALAADCgcICwAAAA==.',['Пы']='Пыхтарчок:BAAALAADCgcICAAAAA==.',['Пэ']='Пэдров:BAAALAADCgYIBgAAAA==.Пэдропал:BAAALAAECgMIAwAAAA==.',['Ра']='Раанеш:BAAALAAECgcIEAAAAA==.Рантра:BAAALAADCgMIAwAAAA==.Рарочка:BAAALAADCgMIAwAAAA==.',['Ре']='Рейнджшот:BAAALAAECgYIBwAAAA==.Рейханд:BAAALAADCgYIDAAAAA==.Рейши:BAAALAAECgYICQAAAA==.Рекл:BAAALAAFFAIIBAAAAA==.',['Рж']='Ржаваборода:BAAALAADCgYIBgAAAA==.',['Ри']='Ринали:BAAALAADCgcIBwAAAA==.',['Ро']='Рокбэби:BAAALAAECgYIBgAAAA==.',['Са']='Сангвион:BAAALAADCgcIEgAAAA==.Санджи:BAAALAADCgYICwAAAA==.Сарквард:BAAALAADCggIEAAAAA==.',['Си']='Сильварил:BAAALAADCgcIBwAAAA==.Синэстр:BAAALAADCggICAAAAA==.Сирадолина:BAAALAAECggICAAAAA==.Ситлалли:BAAALAAECgYIDAAAAA==.',['Ск']='Сквернопопа:BAAALAAECggICgAAAA==.Скехит:BAAALAAECggIEAAAAA==.',['Сл']='Славинк:BAAALAADCgYIBgAAAA==.Сладкаяватаа:BAAALAADCgEIAQAAAA==.',['См']='Смерчикс:BAAALAADCggICAAAAA==.Смокерро:BAAALAAECgcIDgAAAA==.',['Со']='Собакапёс:BAAALAAECgEIAQAAAA==.Сонако:BAAALAAECgQIBAAAAA==.Соняшерсть:BAAALAAECggIBAAAAA==.Сопляя:BAAALAAECgEIAQAAAA==.Соргвей:BAAALAADCgQIBQAAAA==.',['Ст']='Стелтон:BAAALAAECgIIAwAAAA==.Стендерс:BAABLAAECoEUAAIEAAcI9yARCgCBAgAEAAcI9yARCgCBAgAAAA==.',['Сь']='Сьюзи:BAAALAAECgIIAgAAAA==.',['Та']='Тариф:BAAALAAECgYIEAAAAA==.Тарриль:BAACLAAFFIEFAAIJAAMIrRU7AAAbAQAJAAMIrRU7AAAbAQAsAAQKgRcAAwkACAhRIZoAAPMCAAkACAguIZoAAPMCAAoABwjfEfg9AHcBAAAA.',['Тв']='Твики:BAAALAAECgEIAQAAAA==.',['Те']='Тейтелан:BAAALAAECgYIBgAAAA==.Техноярл:BAAALAAECgMIBQAAAA==.',['Ти']='Тинли:BAAALAADCgcIDQAAAA==.',['То']='Тобдру:BAABLAAECoEVAAIHAAgI3B6kBwDRAgAHAAgI3B6kBwDRAgAAAA==.Торелия:BAAALAAECgYICgAAAA==.',['Тр']='Трувор:BAAALAAECgYICwAAAA==.',['Тэ']='Тэльдрассил:BAAALAAECgYIBgAAAA==.',['Ул']='Ульянчик:BAAALAAECgYICgAAAA==.',['Ур']='Урурубетон:BAAALAAECgMIAwAAAA==.',['Уш']='Ушко:BAAALAADCgYIBgAAAA==.',['Фа']='Фаворытка:BAAALAADCgcICwAAAA==.Фаеркайс:BAAALAADCgYIBwAAAA==.',['Фи']='Физикаводы:BAAALAADCgUICQAAAA==.',['Фл']='Флора:BAAALAADCgIIAgAAAA==.',['Фо']='Фордис:BAAALAADCgUIBQAAAA==.',['Фр']='Фрейз:BAAALAADCgcIAgAAAA==.',['Фу']='Фуфанон:BAAALAAECggICAAAAA==.',['Фэ']='Фэйсонфаер:BAAALAAECgIIAgAAAA==.Фэйтеддру:BAAALAAECgEIAQAAAA==.Фэйтедшам:BAAALAADCgMIAwAAAA==.',['Ха']='Хабрези:BAAALAADCggIDwAAAA==.',['Хе']='Хенесби:BAAALAADCgcICwAAAA==.',['Хи']='Хитава:BAAALAADCgcIBwAAAA==.',['Хл']='Хлаповинка:BAAALAADCggICAAAAA==.',['Хо']='Хо:BAAALAAECgMIBwAAAA==.Хорхеус:BAAALAAECgcICgAAAA==.Хотадиллер:BAAALAADCggICAAAAA==.',['Ху']='Хурделиця:BAAALAADCggIFgAAAA==.',['Чи']='Чикато:BAAALAAECgUIBwAAAA==.',['Ша']='Шаргир:BAAALAADCgEIAQAAAA==.',['Ши']='Шигеру:BAAALAADCggIDgAAAA==.',['Шк']='Шкодница:BAAALAAECgMIBwAAAA==.',['Шл']='Шляпшля:BAAALAAECgEIAQAAAA==.',['Шм']='Шмиксель:BAAALAADCgIIAgAAAA==.',['Шр']='Шракус:BAAALAAECgUICAAAAA==.',['Шу']='Шуршаня:BAAALAAECgUICAAAAA==.',['Шэ']='Шэйнэс:BAAALAADCgcIBwAAAA==.',['Эл']='Элайниель:BAAALAADCggIEQAAAA==.Элуннсис:BAAALAAECgUIBQAAAA==.Эльрилион:BAAALAAECgYIDwAAAA==.',['Эо']='Эолус:BAAALAADCggIDgAAAA==.',['Эр']='Эрешкегаль:BAAALAAECgUICQAAAA==.Эригранд:BAAALAAECgYICQAAAA==.',['Эс']='Эсиель:BAAALAAECgEIAQAAAA==.',['Эт']='Этобудетдх:BAAALAAECgcICAAAAA==.',['Юс']='Юсь:BAABLAAECoEYAAIKAAgIhyInDQDLAgAKAAgIhyInDQDLAgAAAA==.',['Яг']='Ягос:BAAALAAECgMIBQAAAA==.',['Ян']='Янекот:BAAALAADCgEIAQAAAA==.',['Яс']='Ясил:BAAALAAECgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end