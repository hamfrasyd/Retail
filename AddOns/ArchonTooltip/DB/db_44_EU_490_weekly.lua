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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Evoker-Devastation','Monk-Windwalker',}; local provider = {region='EU',realm='Дракономор',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Аг']='Агропром:BAAALAAECgYICAAAAA==.',['Ае']='Аерлис:BAAALAADCgUIAgAAAA==.',['Ай']='Айдаборщ:BAAALAADCggIFAAAAA==.Айникас:BAAALAAECggIBgAAAA==.',['Ак']='Аксон:BAAALAADCggIEQAAAA==.',['Ал']='Александр:BAAALAAECgMIAwAAAA==.Алинерия:BAAALAAECgIIAgAAAA==.Алмахант:BAAALAAECgYIBgAAAA==.',['Ан']='Аннавата:BAAALAADCgcIAQABLAAECgYIBgABAAAAAA==.',['Ап']='Апогелия:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',['Ар']='Аркадий:BAAALAAFFAIIAgAAAA==.Артастутуэйт:BAAALAADCgYIAgAAAA==.Арутиус:BAAALAADCggIDwAAAA==.',['Ат']='Атаракс:BAAALAAECgIIAgAAAA==.',['Ба']='Балбеска:BAAALAADCgYIBgAAAA==.Баракиэль:BAAALAADCgcIBwAAAA==.',['Бе']='Березинский:BAAALAAECgYIBgAAAA==.',['Бл']='Блеклайт:BAAALAADCggICAAAAA==.Блекпинкк:BAAALAADCgcIBwAAAA==.',['Бо']='Богиняфрэйя:BAAALAADCgcIBwAAAA==.Бодрый:BAAALAADCgcIDQAAAA==.Бойсячел:BAAALAAECgQIBAAAAA==.Больтазар:BAAALAAECgYIDgAAAA==.',['Бр']='Брилианна:BAAALAAECgYICQAAAA==.',['Бу']='Буллка:BAAALAAECgYICwAAAA==.',['Ва']='Вайтвульф:BAAALAAECgMIAwAAAA==.Васера:BAAALAADCggICwAAAA==.',['Ве']='Вессильра:BAAALAAECgEIAgAAAA==.',['Ви']='Виталийон:BAAALAAECgcIAQAAAA==.',['Ву']='Вульзевилла:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Вульфкнайт:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.',['Га']='Галльский:BAAALAADCgIIAgAAAA==.',['Го']='Гозельтрон:BAAALAAECgEIAQAAAA==.Горныйволк:BAAALAADCgMIAwAAAA==.',['Гр']='Грассхоппер:BAAALAADCggIDQAAAA==.Грехокот:BAAALAAECgIIAwAAAA==.Грибуся:BAAALAADCgcIEwAAAA==.',['Да']='Дарникус:BAAALAAECgcICgAAAA==.',['Де']='Дезерти:BAAALAAECgYIBgAAAA==.Держись:BAAALAADCgcIBwAAAA==.Дерокрас:BAABLAAECoEUAAMCAAcIvBdfGQD2AQACAAcIvBdfGQD2AQADAAIIOgQSfwBIAAAAAA==.',['Дж']='Джей:BAAALAADCggIDwAAAA==.Джеки:BAAALAAECgEIAgAAAA==.Джиниу:BAAALAAECgIIAgAAAA==.Джонникеш:BAAALAADCgcIBwAAAA==.',['Ди']='Дикэ:BAAALAAECggICAAAAA==.Диллиана:BAAALAADCggIEQAAAA==.Димасикк:BAAALAADCggIEAAAAA==.',['До']='Доктордруу:BAAALAADCgIIAgABLAAECgYICwABAAAAAA==.Донкихот:BAAALAADCgYIBgAAAA==.Дооротея:BAAALAADCgcICwAAAA==.',['Др']='Драгур:BAAALAAECgIIAgAAAA==.Дратанг:BAAALAADCgEIAQAAAA==.',['Дэ']='Дэнаа:BAAALAAECgYIDwAAAA==.',['Дя']='Дядяэл:BAAALAAECgYIDwAAAA==.',['Ег']='Егурец:BAAALAADCgMIAwAAAA==.',['Еж']='Ежихоголовая:BAAALAADCggIEgAAAA==.',['Ех']='Ех:BAAALAADCgMIAwAAAA==.',['За']='Заназил:BAAALAAECgYICQAAAA==.Защищайкин:BAAALAAECgYICwAAAA==.',['Зд']='Здоровенный:BAAALAAECgEIAQAAAA==.',['Зи']='Зианджа:BAAALAAECgIIAwAAAA==.',['Зл']='Златтка:BAAALAADCgcIDQAAAA==.',['Зу']='Зумлош:BAAALAADCggIEQAAAA==.',['Ил']='Иллидрун:BAAALAAECgMIAwAAAA==.Иллэрия:BAAALAADCgcIBwAAAA==.Илрондор:BAAALAADCggICAAAAA==.',['Им']='Имфераэль:BAAALAAECgUIBwAAAA==.',['Ин']='Инестра:BAAALAAECgYICgABLAAECgYIDgABAAAAAA==.Инзорн:BAAALAADCggICAAAAA==.Инфрагилис:BAAALAAECgYICQAAAA==.',['Ис']='Исфат:BAAALAADCgEIAQAAAA==.',['Ка']='Кайймира:BAAALAADCggIDwAAAA==.Камерамен:BAAALAAECgEIAQAAAA==.Карамбут:BAAALAAECgMIBgAAAA==.Карноши:BAAALAADCggIHAAAAA==.Картманот:BAAALAAECgMIBQAAAA==.Картьебугати:BAAALAAECgYIBgAAAA==.Катэш:BAAALAAECgYICAAAAA==.',['Ке']='Кеничко:BAAALAADCggICAAAAA==.Кефирчиг:BAAALAAECgEIAQABLAAECgYICwABAAAAAA==.Кефрон:BAAALAAECgYIDAAAAA==.',['Ки']='Кидкити:BAAALAADCggICAAAAA==.',['Кл']='Клёпа:BAAALAADCgYICgABLAAECgMIAwABAAAAAA==.',['Ко']='Коррислия:BAAALAAECgYIBwAAAA==.Кортес:BAAALAAECgUIBgAAAA==.Котозавр:BAAALAAECgYICAAAAA==.',['Кр']='Кринжуль:BAAALAADCggIDgABLAAECgYICAABAAAAAA==.Крускор:BAAALAAECgYIBgAAAA==.',['Кс']='Ксенара:BAAALAAECgMIBwAAAA==.',['Кт']='Ктхула:BAAALAAECgYIBgAAAA==.',['Ку']='Куанарин:BAAALAADCgEIAQAAAA==.',['Ла']='Лакрю:BAAALAADCggICAAAAA==.Ластралия:BAAALAADCggIFwAAAA==.',['Ле']='Летучийсапог:BAAALAAECgEIAQAAAA==.',['Ли']='Лиджети:BAAALAADCggICAAAAA==.Линеля:BAAALAAECgIIAgAAAA==.Литавия:BAAALAADCggIEgAAAA==.',['Ло']='Локерт:BAAALAAECgYICQAAAA==.',['Лу']='Лугажуй:BAAALAAECgYIDgAAAA==.',['Лы']='Лысак:BAAALAADCgIIAgAAAA==.',['Лэ']='Лэттиси:BAAALAAECgEIAQAAAA==.',['Лю']='Люблю:BAAALAAECgYIBwAAAA==.',['Ма']='Маати:BAAALAAECgUIBwAAAA==.Магкликер:BAAALAADCggICAAAAA==.Мадолориан:BAAALAADCgcICAABLAAECgcIFAACALwXAA==.Малиас:BAAALAADCgcIBwAAAA==.Манриса:BAAALAADCgMIAwABLAAECgYIBgABAAAAAA==.Махвальт:BAAALAAECgQIBQAAAA==.',['Ме']='Мексиканка:BAAALAADCgEIAQAAAA==.Мелькорис:BAAALAAECgYIDgAAAA==.',['Ми']='Микури:BAAALAADCgcIBwAAAA==.Минеррва:BAAALAAECgIIAgAAAA==.Миссджеей:BAAALAADCggIDQAAAA==.',['Мо']='Мойэльф:BAAALAADCgcIBwAAAA==.Молдрен:BAAALAADCggIDAAAAA==.Мошер:BAAALAAECgEIAQAAAA==.',['Му']='Муракки:BAAALAAECgMIAwAAAA==.',['Мы']='Мышка:BAAALAADCgYIBgAAAA==.',['На']='Нанаська:BAAALAADCgYIBgAAAA==.',['Не']='Неверлорд:BAAALAADCgUICAAAAA==.Негинд:BAAALAAECgYICAAAAA==.Нейронка:BAAALAAECgYICQAAAA==.Некоренна:BAAALAADCgcICQAAAA==.Некромантиус:BAAALAAECgIIAwAAAA==.Непеня:BAAALAAECgYICwAAAA==.Нест:BAAALAADCggIEAAAAA==.',['Ни']='Нимезида:BAAALAAECgMIAwAAAA==.',['Но']='Ноулимит:BAAALAADCgUIBwAAAA==.Ноури:BAAALAAECgYICwAAAA==.',['Он']='Онзи:BAAALAAECgYICAAAAA==.',['Ор']='Оругец:BAAALAADCgEIAQAAAA==.',['Оц']='Оципиталлис:BAAALAAECgYIBwAAAA==.',['Пе']='Пеппилота:BAAALAADCgcICQAAAA==.',['По']='Поло:BAAALAAECgQIBAAAAA==.Поражений:BAAALAAECgYIBwAAAA==.Похметолог:BAAALAAECgQIBQAAAA==.',['Пр']='Приемыш:BAAALAADCggIEQAAAA==.Прю:BAAALAAECgYICQAAAA==.',['Ра']='Радиэль:BAAALAAECgYICAAAAA==.Раймэй:BAAALAAECgIIAgAAAA==.Ранден:BAAALAAECgYIDAAAAA==.',['Ри']='Риверблейд:BAAALAADCgYICAABLAAECgMIAwABAAAAAA==.Ринзлок:BAAALAADCgYIBgAAAA==.Рипчик:BAAALAAECgQIBAAAAA==.',['Ро']='Рогуэра:BAAALAADCgYIBgAAAA==.Ронин:BAAALAADCgYIBwAAAA==.',['Ру']='Рунаар:BAAALAAECgUIBgAAAA==.',['Са']='Самантра:BAAALAAECgYICAAAAA==.Сапнаполгода:BAAALAAECggICQAAAA==.Сафирон:BAAALAADCggIBwAAAA==.',['Се']='Серафимика:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',['Си']='Сигурдия:BAAALAADCggIBwAAAA==.Силендра:BAAALAADCggIDQAAAA==.Сиунэ:BAAALAADCggIGAAAAA==.',['Ск']='Скочь:BAAALAAECgMIAwAAAA==.',['Сл']='Следкопыт:BAAALAAECgYIDwAAAA==.Слешвен:BAAALAAECgEIAgAAAA==.',['Со']='Сонарес:BAAALAAFFAIIAgAAAA==.',['Сп']='Спайсигёрл:BAAALAAECgEIAQAAAA==.',['Та']='Талариус:BAAALAADCgEIAQAAAA==.Тарилисса:BAAALAAECgEIAgAAAA==.Таунсантрос:BAAALAAECgMIAwABLAAECgcIFAACALwXAA==.Ташра:BAAALAADCgIIAgAAAA==.',['Те']='Тека:BAAALAAECgMIBAAAAA==.Телана:BAAALAAECgYICwAAAA==.Темпорус:BAAALAADCggICAAAAA==.Тестиада:BAAALAAECgYICwAAAA==.',['Ти']='Тизвиш:BAAALAADCggIFAAAAA==.Тииса:BAAALAAECgMIBAAAAA==.',['То']='Тотор:BAAALAAECgMIBQAAAA==.',['Тр']='Трейгар:BAAALAADCgcIDQAAAA==.',['Уд']='Удирша:BAAALAAECgYIEQAAAA==.',['Уж']='Ужасныйволк:BAAALAADCggICAAAAA==.',['Уи']='Уивер:BAAALAADCgcIDQAAAA==.',['Уо']='Уолтерик:BAAALAAECgcIEwAAAA==.',['Ур']='Урель:BAABLAAECoEWAAIEAAgIehdCEgD1AQAEAAgIehdCEgD1AQAAAA==.',['Фа']='Фанфукрик:BAAALAADCgcIBwAAAA==.Фаррула:BAAALAAECgYICAAAAA==.',['Фе']='Феннипей:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',['Фо']='Форсфул:BAAALAAECgIIAwAAAA==.',['Хи']='Хидзи:BAAALAADCgEIAQAAAA==.Хилвэр:BAAALAAECggIEQAAAA==.Хитари:BAABLAAECoEXAAIFAAgIHx7iBQChAgAFAAgIHx7iBQChAgAAAA==.',['Хо']='Хоук:BAAALAADCggICAAAAA==.',['Хэ']='Хэйча:BAAALAAECggICAAAAA==.',['Ци']='Цилистина:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',['Чж']='Чжицзин:BAAALAADCgIIAgABLAAECgYICAABAAAAAA==.',['Чи']='Чиллуф:BAAALAAECgIIAwAAAA==.',['Чо']='Чос:BAAALAADCgEIAQAAAA==.',['Чю']='Чюда:BAAALAAECgYIDgAAAA==.',['Ша']='Шальнаящама:BAAALAAECgYICwAAAA==.Шамисвами:BAAALAAECgEIAQAAAA==.Шамом:BAAALAADCggICAAAAA==.Шапка:BAAALAADCggIDwAAAA==.',['Ше']='Шенлана:BAAALAADCgcIBwAAAA==.',['Ши']='Шишь:BAAALAAECgYIBgAAAA==.',['Шу']='Шуна:BAAALAAECgIIBAAAAA==.',['Эв']='Эверлост:BAAALAAECgEIAQAAAA==.',['Эк']='Эклиптик:BAAALAADCgcICgAAAA==.',['Эл']='Элдрагоса:BAAALAAECgYIEgAAAA==.Элизабелла:BAAALAADCgIIAgAAAA==.Элфиш:BAAALAAECgYIDgAAAA==.',['Эр']='Эрнэтта:BAAALAAECgYICAAAAA==.',['Эс']='Эстэра:BAAALAADCgUIBQAAAA==.',['Юл']='Юлси:BAAALAADCggICQAAAA==.',['Юн']='Юнимас:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end