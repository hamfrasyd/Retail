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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Frost','Priest-Shadow','Priest-Holy','Priest-Discipline','Druid-Feral','Warrior-Fury','DeathKnight-Frost','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety',}; local provider = {region='EU',realm='Галакронд',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Ав']='Авсянко:BAAALAADCggICAAAAA==.',['Ай']='Айкаа:BAAALAAECgIIAgAAAA==.Айэнир:BAAALAAECgEIAQAAAA==.',['Ал']='Алексаня:BAAALAAECgMIAwAAAA==.Алексафокси:BAAALAADCgcIBwAAAA==.Аликея:BAAALAADCggICAABLAAECggIEgABAAAAAA==.Альвансор:BAAALAAECgcIEAAAAA==.Альгаран:BAAALAADCggICAAAAA==.Альфалорд:BAAALAAECgYICwAAAA==.',['Ам']='Амассис:BAAALAADCggICAAAAA==.Амацухиконэ:BAAALAAECgUIAgAAAA==.Америикан:BAAALAADCggIDgAAAA==.Амралиме:BAAALAADCgMIAgAAAA==.',['Ан']='Андрюшамаг:BAAALAAECgcIEwAAAA==.Анкариус:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.',['Ар']='Аримка:BAAALAAECgYIBgAAAA==.Арнигольд:BAABLAAECoEXAAMCAAgIRyGFCADmAgACAAgIAiCFCADmAgADAAQIARyzLQAWAQAAAA==.Архимид:BAAALAADCggICwAAAA==.',['Ас']='Астерий:BAAALAADCggIDwAAAA==.',['Ат']='Атомныйвар:BAAALAAECgYIBgAAAA==.Атраксдк:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Атраксик:BAAALAAECgMIBQAAAA==.Атраксмонк:BAAALAAECgMIBAABLAAECgMIBQABAAAAAA==.Атраксхант:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',['Аф']='Афистэ:BAAALAAECggIEQAAAA==.',['Бе']='Белледар:BAAALAAECgMIBQAAAA==.Бенка:BAAALAAECgcIEAAAAA==.Беннингтон:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',['Би']='Бистро:BAAALAAECgYIDAAAAA==.',['Бл']='Блайд:BAAALAAECgcIEwAAAA==.',['Бо']='Боксджан:BAAALAAECgEIAQAAAA==.',['Бр']='Бреинор:BAAALAADCgYIBgAAAA==.',['Бу']='Буранги:BAAALAADCgcIBwAAAA==.',['Ва']='Вакулыч:BAAALAAECgQIBQAAAA==.Валиария:BAAALAAECgcIEwAAAA==.Вартида:BAAALAAECgMIBQAAAA==.',['Ве']='Веикики:BAAALAADCggIDAAAAA==.Вельзебасков:BAAALAADCgIIAgABLAAECgYIBwABAAAAAA==.Вельзедепп:BAAALAAECgYIBgABLAAECgYIBwABAAAAAA==.Вельзекавилл:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.Вельзеонтьев:BAAALAAECgYIBwAAAA==.',['Вл']='Владиклохх:BAAALAAECgYICwAAAA==.Владикнелохх:BAAALAADCgcIBwAAAA==.',['Во']='Воимяльда:BAABLAAECoEUAAIEAAcIBhxoCgA6AgAEAAcIBhxoCgA6AgAAAA==.',['Ву']='Вузик:BAAALAAECgMIBQAAAA==.Вузшам:BAAALAADCggICAAAAA==.',['Га']='Галинваген:BAAALAADCgcIDQAAAA==.Гареро:BAAALAADCgYICQAAAA==.Гарис:BAAALAAECgMIAwAAAA==.Гартрам:BAAALAAECgYICgAAAA==.Гачибуйный:BAAALAAECgIIAgAAAA==.Гачинелло:BAAALAAECgIIAgAAAA==.',['Ге']='Генрианна:BAAALAAECgYIDQAAAA==.',['Го']='Гонор:BAAALAAECgMIBAAAAA==.',['Гр']='Грайнда:BAAALAAECgMIAgAAAA==.',['Гу']='Гутелист:BAAALAAECgYIBwAAAA==.',['Де']='Дедсукуб:BAAALAAECgUIAgAAAA==.Деймосин:BAAALAAECgYIEQAAAA==.Дескудище:BAAALAADCgEIAQAAAA==.',['Дж']='Джонблейд:BAAALAAECgYIDQAAAA==.Джоханс:BAAALAADCgcIBwAAAA==.Джудихобс:BAAALAAECgUIDAAAAA==.',['Ди']='Динсергеевна:BAAALAAECgIIAgAAAA==.',['До']='Дозик:BAAALAADCgcICgAAAA==.',['Др']='Дреллиана:BAAALAAECgYIDQAAAA==.Дринт:BAAALAAECgEIAgAAAA==.Друдотала:BAAALAADCggICAAAAA==.',['Дэ']='Дэхан:BAAALAADCggICAAAAA==.',['За']='Забран:BAAALAADCggICAAAAA==.Заковия:BAAALAAECgYICgAAAA==.Заколино:BAAALAAECgYIDAAAAA==.Занда:BAAALAAECgYIBgAAAA==.Зараги:BAAALAAECgYIBgAAAA==.Зарезать:BAAALAAECgQIBAAAAA==.',['Зв']='Зверовище:BAAALAADCggIDAAAAA==.',['Зе']='Зелебражник:BAAALAADCgcIAwAAAA==.Зерасмус:BAAALAAECgYICwAAAA==.Зерънар:BAAALAADCggIFQAAAA==.Зефекс:BAAALAAECgYICQAAAA==.',['Зк']='Зкнопкискилл:BAAALAAECgMIBQAAAA==.',['Зл']='Злая:BAAALAAECgcIEgAAAA==.',['Ив']='Ивелденс:BAAALAADCggICgAAAA==.',['Иг']='Игнисмаг:BAAALAADCgcIDQAAAA==.',['Ик']='Икимару:BAAALAAECgEIAQABLAAECgMIBAABAAAAAA==.',['Ил']='Иливстан:BAAALAAECggIBgAAAA==.Иллюмино:BAAALAAECgMIBAAAAA==.Илювафар:BAAALAAECgMIAwAAAA==.',['Ин']='Инзоске:BAAALAAECgIIAgABLAAECgMIAwABAAAAAA==.',['Ит']='Италмас:BAAALAAECgEIAQAAAA==.',['Ка']='Кадрр:BAAALAADCggIDQABLAAECggIFQAFACEhAA==.Кайдеми:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Кайденс:BAAALAADCgUIBQAAAA==.Калдора:BAAALAADCgMIAwAAAA==.Кархарт:BAAALAADCggIDgAAAA==.Категаричу:BAAALAADCggIEQAAAA==.',['Ке']='Кельаран:BAAALAAECgYIEgAAAA==.Кертэн:BAAALAADCgEIAQAAAA==.',['Ки']='Киллмонгер:BAAALAAECgUIBQABLAAECgYICgABAAAAAA==.Кильнадис:BAAALAADCgUICAAAAA==.',['Кл']='Кларкхаос:BAAALAADCggIFQAAAA==.',['Ко']='Когратани:BAAALAAECgcIDQAAAA==.Колтрат:BAAALAAECgQIBQAAAA==.Костабиль:BAAALAADCggICgAAAA==.',['Кр']='Крапинка:BAAALAADCggIDQAAAA==.Крапка:BAAALAADCgEIAQAAAA==.Кризис:BAAALAAECgMIAwAAAA==.Кроаг:BAAALAADCgMIAQAAAA==.Крутобурен:BAAALAAECgcIDQAAAA==.',['Кс']='Ксавиус:BAAALAAECgcIEwAAAA==.',['Ку']='Куру:BAAALAADCgcIDQAAAA==.',['Ла']='Лайтбосс:BAABLAAECoEVAAQFAAgIISFMCwCjAgAFAAcIHSFMCwCjAgAGAAYI0Ra0IwChAQAHAAEIJgZLHgArAAAAAA==.Лалуу:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.',['Ле']='Лемонадовна:BAAALAADCgUIBQAAAA==.Леошама:BAAALAADCgYIDAABLAAECgcIDQABAAAAAA==.',['Ли']='Лиандея:BAAALAADCgYIBgAAAA==.Лианидас:BAAALAAECgYICQAAAA==.Либравар:BAAALAAECgcIDAAAAA==.Лилияройли:BAAALAADCgcIDQAAAA==.Лиляройя:BAAALAAECgcIEgAAAA==.Лимшива:BAAALAADCgYIBgAAAA==.Лихачок:BAAALAADCgcIBwAAAA==.',['Ло']='Локибренна:BAAALAADCgMIAwAAAA==.',['Лу']='Лунипал:BAAALAAECgYIBgAAAA==.',['Лю']='Люкенг:BAAALAADCggICAAAAA==.Люцилоки:BAAALAADCggICAAAAA==.',['Ма']='Максэкспо:BAAALAADCgcICQAAAA==.Малиндриэль:BAAALAAECgMIAwAAAA==.Малталаэль:BAAALAAECgYIDAAAAA==.Мамаскверны:BAAALAADCggIEAAAAA==.Манул:BAABLAAECoEUAAIIAAgInCOqAQASAwAIAAgInCOqAQASAwAAAA==.Маронол:BAAALAADCgcIDwAAAA==.Мархабо:BAAALAADCgcIBwAAAA==.Мастерчоппы:BAAALAAECgEIAQAAAA==.Машасрувкашу:BAAALAAECgYICQAAAA==.',['Ме']='Медовик:BAAALAADCgYIBgAAAA==.Мельхиорра:BAAALAAECgYIBgAAAA==.',['Ми']='Милостливая:BAAALAADCggIEAAAAA==.Миравинг:BAAALAAECgcICwAAAA==.Мирсалис:BAAALAAECgEIAQAAAA==.Мистут:BAAALAADCggIEAAAAA==.Мистута:BAAALAADCgIIAgABLAADCggIEAABAAAAAA==.Митронэль:BAAALAADCggIDgAAAA==.Мифистель:BAAALAAECggIEgAAAA==.',['Мо']='Молтудир:BAAALAAECgYIDQAAAA==.Монфрель:BAAALAADCgIIAgAAAA==.Мор:BAAALAAECgIIAgAAAA==.Моризель:BAAALAADCgYIBgAAAA==.',['Мь']='Мьютед:BAAALAADCggIDAAAAA==.',['На']='Наггар:BAABLAAECoEPAAIJAAcIHA2bIgC7AQAJAAcIHA2bIgC7AQAAAA==.Назимар:BAAALAADCgcIDgAAAA==.',['Не']='Небоюсь:BAAALAADCgEIAQAAAA==.Неистовец:BAAALAAECgcICQAAAA==.Некрололикон:BAAALAADCgcIBwAAAA==.Немуния:BAAALAAECgYIDQAAAA==.',['Ни']='Никапли:BAAALAAECgcIBwAAAA==.Никиба:BAAALAAECgMIAwAAAA==.Никиса:BAAALAAECgUIBQAAAA==.',['Но']='Нотянка:BAAALAAECgYIBwAAAA==.',['Ну']='Нуонами:BAAALAADCgYIBgAAAA==.Нуринель:BAAALAADCggICgAAAA==.Нутела:BAAALAADCggIDgAAAA==.',['Од']='Одала:BAAALAADCgYIBgAAAA==.',['Ож']='Ожесинь:BAAALAADCgIIAgAAAA==.',['Ом']='Омбудсмен:BAAALAADCgQICAAAAA==.',['Ор']='Орлангуресса:BAAALAAECgcIEgAAAA==.',['От']='Отецмихаил:BAAALAADCgYIDAAAAA==.',['Пи']='Пивнойсись:BAAALAAECgMIAwAAAA==.Пиошка:BAAALAADCgcIBwAAAA==.Пирохидреза:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.',['По']='Подлыйарктас:BAAALAADCggIFgAAAA==.Полимаро:BAAALAADCgcIDQAAAA==.Пони:BAAALAAECgUICAAAAA==.Постреляем:BAAALAAECgcIEQAAAA==.',['Пр']='Прайдо:BAAALAAECgQIBAAAAA==.',['Пь']='Пьюриоса:BAAALAADCgcICAAAAA==.',['Пё']='Пёжить:BAAALAADCggICAAAAA==.',['Ра']='Радиум:BAAALAADCgcIBwAAAA==.Расангул:BAAALAAECgMIAwAAAA==.Растадруль:BAAALAADCgUIBgAAAA==.',['Ре']='Редгонкинг:BAAALAAECgYIDwAAAA==.Рейерсон:BAAALAADCgcIBwAAAA==.Рекзон:BAAALAADCgEIAQAAAA==.Рефограз:BAAALAADCgcIBwAAAA==.',['Ри']='Ричардт:BAAALAAECgMIAwABLAAECgcIFAAEAAYcAA==.',['Ро']='Роганрос:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Рогафф:BAAALAADCggIEQAAAA==.Ронелли:BAAALAADCgEIAQAAAA==.',['Ру']='Руклеона:BAAALAADCggICAAAAA==.Рускиймясник:BAAALAAECgQIBAAAAA==.',['Са']='Сагым:BAAALAADCgMIAwAAAA==.Садрия:BAAALAAECgIIAQAAAA==.Сайдс:BAAALAADCggICAAAAA==.Саханна:BAAALAAECgYICgAAAA==.',['Св']='Светоубийца:BAAALAADCggIEAAAAA==.Святобор:BAAALAAECgQIBAAAAA==.',['Се']='Сельм:BAAALAAECgEIAQAAAA==.Сенягоблинус:BAAALAAECgIIAgAAAA==.Серебьо:BAAALAADCgEIAQAAAA==.',['Си']='Сильванела:BAAALAAECgcIDQAAAA==.Сильванич:BAAALAAECggIAwAAAA==.',['Ск']='Сквернолап:BAAALAADCgcIBwAAAA==.Скульптор:BAAALAADCggICAAAAA==.Скуфус:BAAALAAECgYIDgAAAA==.',['Сн']='Снайкен:BAAALAADCggICAAAAA==.',['Су']='Сумомо:BAAALAAECgIIAgAAAA==.Сургумия:BAAALAAECgYIBgAAAA==.',['Та']='Тайнюша:BAAALAADCggICAAAAA==.Таравангиан:BAAALAAECgYIBgAAAA==.Тарэлко:BAAALAAECggIBgAAAA==.Тасфиания:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',['Те']='Теньсавы:BAAALAAECgYIDQAAAA==.',['Ти']='Тим:BAAALAAECgcIEwAAAA==.Тимас:BAAALAADCggICAAAAA==.Тинтакля:BAAALAADCggICAAAAA==.',['То']='Томентос:BAAALAAECgMIAgAAAA==.Тохсик:BAAALAAECgIIAgAAAA==.',['Тр']='Трамадар:BAAALAAECggIEQAAAA==.Трамыч:BAAALAADCggIDAAAAA==.Труд:BAAALAADCgEIAQAAAA==.',['Ту']='Турзадирана:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',['Тё']='Тёмныйангел:BAAALAADCggICAAAAA==.',['Ук']='Украинець:BAAALAADCgMIAwAAAA==.',['Уо']='Уоллаах:BAAALAADCgYIBgAAAA==.Уотер:BAAALAADCgcIBwAAAA==.',['Фа']='Фальнуаци:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Фантомим:BAAALAAECgYIEAAAAA==.',['Фи']='Филренон:BAABLAAECoEXAAIKAAgIah91CwDVAgAKAAgIah91CwDVAgAAAA==.Фирамир:BAAALAAECggIDgAAAA==.Фиско:BAAALAAECgMIAwABLAAFFAUICgALAOoZAA==.',['Фо']='Фонбарон:BAAALAADCggICAAAAA==.',['Фр']='Фрейя:BAAALAAECgYIDQAAAA==.Фростмодерн:BAAALAADCgIIAgAAAA==.',['Фэ']='Фэйсролл:BAAALAAECgIIAwAAAA==.',['Ха']='Хамер:BAAALAADCgEIAQAAAA==.Хантик:BAAALAAECgcICgAAAA==.',['Хб']='Хбикс:BAAALAAECgYICgAAAA==.',['Хе']='Хеймнир:BAAALAAECgYICAAAAA==.',['Хи']='Хикори:BAAALAAECgcIDwAAAA==.Хиликус:BAAALAADCggIDgAAAA==.Хитрий:BAAALAADCgcIAQABLAADCggICAABAAAAAA==.',['Хэ']='Хэйро:BAAALAAECgMIAwAAAA==.Хэнкоок:BAAALAADCgYIBgAAAA==.',['Ча']='Чаймести:BAAALAADCgQIBAAAAA==.Чаризард:BAAALAADCggICAAAAA==.',['Чи']='Чистий:BAAALAADCggICAAAAA==.',['Чп']='Чпуньк:BAAALAADCgcIBwAAAA==.',['Чу']='Чучелинно:BAAALAAECgMIAwAAAA==.',['Ша']='Шабумда:BAAALAADCgQIBwAAAA==.Шайтанатт:BAAALAADCgYIBwAAAA==.Шалупонька:BAAALAADCgYICQAAAA==.Шамалдред:BAAALAAECgYICgAAAA==.Шармач:BAAALAADCgYIBgAAAA==.',['Ше']='Шетонар:BAAALAADCggICAABLAAECgYIEgABAAAAAA==.',['Эг']='Эгони:BAAALAAECgMIBQAAAA==.',['Эй']='Эйс:BAAALAAECgcIEwAAAA==.',['Эк']='Эксмортус:BAAALAADCggIBwAAAA==.',['Эл']='Элиуриас:BAAALAAECgQIBgAAAA==.',['Эн']='Энибель:BAAALAAECgIIAwAAAA==.',['Эр']='Эркек:BAAALAAECgMIAwAAAA==.',['Эт']='Этон:BAAALAADCgQIBAAAAA==.',['Юк']='Юкина:BAAALAAECgMIBQAAAA==.',['Юн']='Юно:BAAALAAECgUIBQAAAA==.',['Яд']='Ядик:BAABLAAECoEWAAMMAAgIbCGCBwDEAgAMAAgILR+CBwDEAgANAAYI8R28BAAaAgAAAA==.',['Яр']='Ярмина:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end