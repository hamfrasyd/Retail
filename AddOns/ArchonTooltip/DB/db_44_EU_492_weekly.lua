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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Warlock-Destruction','Druid-Feral','Shaman-Enhancement','Shaman-Elemental','Evoker-Devastation','Paladin-Retribution','Shaman-Restoration','Hunter-Marksmanship','Evoker-Preservation','Mage-Frost','DeathKnight-Frost',}; local provider = {region='EU',realm='Пиратскаябухта',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Аб']='Абаюндич:BAAALAAECggICQAAAA==.',['Ав']='Авгалон:BAAALAADCgYIBgAAAA==.',['Аз']='Азнаур:BAAALAAECgMIAwABLAAECgYIEAABAAAAAA==.',['Ак']='Акэти:BAAALAAECgYICgAAAA==.',['Ал']='Алиста:BAAALAADCggICAAAAA==.Алондий:BAAALAAECgEIAQAAAA==.Алундрин:BAAALAAECgEIAQAAAA==.',['Ам']='Амагальма:BAAALAADCggICAAAAA==.Амалина:BAAALAAECggIEAAAAA==.Ампецилинка:BAAALAADCgcIDgABLAAECgYICgABAAAAAA==.',['Ан']='Ангмар:BAAALAAECggIEQAAAA==.Анномаг:BAAALAAECgQIBAAAAA==.',['Ап']='Аппафеоз:BAAALAAECgMIBwAAAA==.',['Ар']='Аркрай:BAAALAAECgMIBwAAAA==.Аркт:BAAALAADCgYICgAAAA==.Арнульв:BAAALAADCggICAAAAA==.',['Ау']='Ауешка:BAACLAAFFIEFAAICAAMITBcIAwAFAQACAAMITBcIAwAFAQAsAAQKgRgAAgIACAgkJA0EACoDAAIACAgkJA0EACoDAAAA.',['Бе']='Бейбушка:BAAALAADCggICAAAAA==.',['Би']='Бигмак:BAAALAADCgcIBwAAAA==.',['Бл']='Блошка:BAAALAAECgMIBwAAAA==.',['Бр']='Братгаашека:BAAALAADCggIDQAAAA==.',['Бу']='Бууча:BAAALAAECgcIDAAAAA==.',['Бь']='Бьёринг:BAAALAAECgcIEQAAAA==.',['Ва']='Валаир:BAABLAAECoEUAAIDAAYIgxsbIQDsAQADAAYIgxsbIQDsAQAAAA==.Валки:BAAALAAECgQICAAAAA==.',['Вк']='Вкусныйторт:BAAALAAECgIIBAAAAA==.',['Вл']='Владислов:BAAALAAECgcICgAAAA==.Владлекс:BAAALAAECgEIAQAAAA==.Владыкаэльф:BAAALAAECgIIAgAAAA==.',['Во']='Вовилем:BAABLAAECoEWAAMEAAgIaBtIBwB4AgAEAAgIaBtIBwB4AgAFAAMIQQiFIwB/AAAAAA==.',['Ву']='Вудмен:BAAALAAECgMIBQAAAA==.Вульфис:BAAALAAECgUIBQAAAA==.',['Га']='Гаврошег:BAAALAAECgEIAQAAAA==.Гайдзин:BAAALAAECgEIAQAAAA==.',['Гз']='Гзу:BAAALAAECgMIBQAAAA==.',['Гн']='Гномхуекрад:BAAALAADCggICQAAAA==.',['Го']='Гозешечка:BAAALAAFFAEIAQAAAA==.Гозешка:BAAALAAFFAEIAQABLAAFFAEIAQABAAAAAA==.Горболом:BAAALAAECgMICAAAAA==.',['Гр']='Грикар:BAAALAADCggICAAAAA==.',['Да']='Даксилус:BAAALAAECgYICgAAAA==.Данако:BAAALAAECgYICgAAAA==.',['Де']='Девола:BAAALAADCgYIBgAAAA==.',['Дж']='Джанзи:BAAALAADCggIEAAAAA==.Джокерфейк:BAAALAADCgUIBQAAAA==.Джостан:BAAALAADCgYIBgAAAA==.',['Ди']='Дисальво:BAAALAAECgEIAQAAAA==.',['До']='Добраякола:BAAALAADCgcIBwAAAA==.',['Дп']='Дпссэр:BAAALAAFFAIIAgAAAA==.',['Др']='Друландус:BAAALAADCggIDgAAAA==.Друстэ:BAAALAAECgQIBAAAAA==.',['Ду']='Дураюля:BAAALAAECgYICAAAAA==.',['Дэ']='Дэксич:BAABLAAECoEVAAIGAAgIiRa4JgD1AQAGAAgIiRa4JgD1AQAAAA==.',['Ер']='Еренити:BAAALAADCgYIBgAAAA==.',['Же']='Женёчек:BAAALAADCggIDgABLAAFFAEIAQABAAAAAA==.',['Жм']='Жмыховуха:BAAALAAECgYIEgAAAA==.',['Жо']='Жозефина:BAAALAAECgIIAwAAAA==.',['За']='Залария:BAAALAADCgYIBwAAAA==.',['Зв']='Звёзднаяпыль:BAAALAADCgYIBgAAAA==.',['Зи']='Зизич:BAAALAAECgYIBgAAAA==.',['Зо']='Золтанхайвей:BAAALAAECgMIAwAAAA==.Зомбака:BAAALAADCgMIAwAAAA==.',['Ил']='Илисандр:BAAALAADCgcIDQAAAA==.Иллорианшам:BAAALAADCgcIBwAAAA==.',['Ин']='Индиана:BAAALAADCggICgAAAA==.',['Ит']='Итариона:BAAALAADCggICAAAAA==.',['Йл']='Йлофлждвлфвд:BAAALAADCgcIBwAAAA==.',['Йо']='Йолодрыг:BAAALAADCgcIBwAAAA==.',['Ка']='Кайсастина:BAABLAAECoEXAAIHAAgIBRJWGQAFAgAHAAgIBRJWGQAFAgAAAA==.Какзабадаю:BAAALAAECgUICQAAAA==.Каллевала:BAAALAADCgUIBQAAAA==.Капо:BAAALAADCggIEQAAAA==.Катрисия:BAABLAAECoEWAAIIAAgIzx1ZAwC8AgAIAAgIzx1ZAwC8AgAAAA==.',['Ки']='Кибер:BAABLAAECoEVAAMJAAgIoBoPBQAyAgAJAAcIERwPBQAyAgAKAAgI4RMrFQAiAgAAAA==.Кирюсанна:BAAALAADCgcIBwAAAA==.Кирял:BAAALAADCgUIBQAAAA==.Китюня:BAAALAAECgEIAQAAAA==.',['Ко']='Коверчик:BAAALAADCggIGAABLAAECgYICgABAAAAAA==.',['Кр']='Крейш:BAAALAAECgMIBQAAAA==.Крутоф:BAAALAADCgcIDQAAAA==.',['Ку']='Кудиграс:BAACLAAFFIEIAAILAAMIQSSOAQBAAQALAAMIQSSOAQBAAQAsAAQKgRcAAgsACAidJa4BAE0DAAsACAidJa4BAE0DAAAA.Кукумба:BAABLAAECoEWAAIMAAgISh9FEgCIAgAMAAgISh9FEgCIAgAAAA==.Кусанали:BAAALAADCgYIBgAAAA==.Кутто:BAAALAADCgMIAwAAAA==.',['Кэ']='Кэлгор:BAAALAADCgcIBwAAAA==.',['Ла']='Лаит:BAAALAAECgYIEAAAAA==.Лайнис:BAAALAAECgYICgAAAA==.Ландриса:BAAALAADCgcIBwAAAA==.',['Ле']='Ленапаравоз:BAAALAAECgIIAgAAAA==.',['Ли']='Либрариан:BAAALAADCggICAAAAA==.Лисков:BAAALAADCgMIAwAAAA==.',['Ло']='Лорадос:BAAALAADCggIDwAAAA==.',['Лю']='Люцив:BAAALAAECgMIAwAAAA==.',['Ма']='Мабумба:BAAALAADCggIDQAAAA==.Маварэ:BAAALAADCggIDwAAAA==.Макина:BAAALAAECgYICQAAAA==.Малибу:BAAALAAECggIEgAAAA==.Мантра:BAAALAADCggICwAAAA==.Марик:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Массарахш:BAAALAAECgIIAgAAAA==.',['Ме']='Мефидрун:BAAALAADCgcICgAAAA==.Мефик:BAAALAAECgcIDgAAAA==.',['Ми']='Микелла:BAAALAADCgYIBgAAAA==.Мириэль:BAAALAADCgcIDQAAAA==.',['Му']='Мудзан:BAAALAADCgUIBQAAAA==.Мультяшик:BAAALAADCggIEQAAAA==.Муркотя:BAAALAAECgcIDwAAAA==.Мурхард:BAAALAAECgYICgAAAA==.',['На']='Нанака:BAAALAADCgcIBgAAAA==.',['Не']='Неадекватная:BAAALAAECgYIDwAAAA==.Неевернный:BAAALAADCgYIBgAAAA==.Нейтан:BAAALAAECgcIDQAAAA==.Немуму:BAAALAAECgcICgAAAA==.Нефтегаз:BAAALAAECgMIAwAAAA==.Нечто:BAAALAADCggIDwAAAA==.',['Ни']='Нифф:BAAALAAECgcIEQAAAA==.',['Но']='Номевоу:BAAALAADCgMIAwAAAA==.',['Об']='Обамеянг:BAAALAADCgcIBwAAAA==.',['Ор']='Оркшаман:BAAALAADCggIEgAAAA==.',['Ос']='Осенний:BAAALAADCgcIBwAAAA==.',['Пи']='Пиксалина:BAABLAAECoEVAAINAAgIbyBHBADhAgANAAgIbyBHBADhAgAAAA==.Пираксилин:BAAALAADCgIIAgAAAA==.',['Пк']='Пкилд:BAAALAAECgYIBgAAAA==.',['По']='Позорница:BAAALAADCggICAAAAA==.',['Пр']='Пресцилла:BAAALAADCgIIAgAAAA==.',['Пс']='Псинасутулая:BAAALAADCggICQAAAA==.Психоза:BAAALAADCgYIBgAAAA==.',['Ре']='Реалайн:BAAALAADCggICAAAAA==.Рейгар:BAAALAAECgYIDAAAAA==.',['Ро']='Рокертравли:BAAALAAECgYIEgAAAA==.',['Ру']='Руго:BAAALAAECgMIAwAAAA==.Руснёва:BAAALAADCggIFQAAAA==.',['Ры']='Рыська:BAAALAAECggICgAAAA==.',['Са']='Сангвинор:BAAALAADCggICAAAAA==.Саро:BAAALAADCggICAAAAA==.',['Св']='Светодар:BAAALAAECgEIAgAAAA==.',['Се']='Седобородыч:BAAALAADCgYIBgAAAA==.Сексигетрект:BAABLAAECoEWAAMDAAgIZhzPFQBDAgADAAgIZhzPFQBDAgAOAAEIuQJHWwAoAAAAAA==.',['Си']='Силвиан:BAAALAAECgcIBwAAAA==.Симфовокер:BAABLAAECoEVAAIPAAgIRRSqBwDvAQAPAAgIRRSqBwDvAQAAAA==.',['Ск']='Скитатель:BAAALAAECgIIAgAAAA==.',['Сл']='Слава:BAAALAADCggICgAAAA==.',['См']='Смертьваша:BAAALAADCggIDAABLAAECgYICgABAAAAAA==.',['Сн']='Снорлакс:BAAALAAECgcIBwAAAA==.',['Со']='Содалов:BAAALAAECgIIAgAAAA==.',['Су']='Субстанция:BAAALAAECgIIAgAAAA==.Суровыйв:BAAALAAECgQIBAAAAA==.',['Сы']='Сын:BAAALAAECgIIAQAAAA==.',['Сю']='Сюреализм:BAAALAAECggICQAAAA==.',['Та']='Тандери:BAAALAADCggICAAAAA==.',['Ти']='Тибетман:BAAALAAECgMIAwAAAA==.Тиккре:BAAALAADCgEIAQAAAA==.',['То']='Толстолинь:BAAALAAECgUIBwAAAA==.',['Тр']='Трикснаноль:BAAALAAECggIEAAAAA==.Трион:BAAALAADCgYIBgAAAA==.',['Ту']='Тур:BAAALAAECgYICQAAAA==.Тучный:BAAALAAECgMIAwAAAA==.',['Ул']='Ульдум:BAAALAAECgIIAgAAAA==.',['Фа']='Фанатпива:BAAALAADCgcICgAAAA==.Фапкитапки:BAAALAAECgIIBQAAAA==.',['Фо']='Фод:BAAALAAECgYICgAAAA==.Фонаббадон:BAAALAADCgUIBQAAAA==.Фонтьма:BAAALAADCgYIBgAAAA==.Фончпокер:BAAALAAECgcIEwAAAA==.',['Фу']='Фуджи:BAABLAAECoEVAAMGAAgIOyU7BAA5AwAGAAgIOyU7BAA5AwAQAAEIhhpLRgBBAAAAAA==.',['Ха']='Хано:BAAALAADCgIIAgAAAA==.Харасмент:BAAALAADCgIIAgAAAA==.',['Хв']='Хвоствогне:BAAALAADCggIFgAAAA==.',['Хо']='Холипандец:BAAALAADCggICAABLAAECggIFQAJAKAaAA==.Хонели:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Хорман:BAAALAAECgQIBAAAAA==.',['Хр']='Хрюхрум:BAAALAAECgYIBgAAAA==.',['Хэ']='Хэлисон:BAAALAADCgcIBwAAAA==.',['Ца']='Цапуля:BAAALAADCgEIAQAAAA==.',['Че']='Челсинах:BAAALAAECgYIDgAAAA==.',['Чо']='Чорт:BAAALAAECgMIAwAAAA==.',['Чу']='Чубаакаа:BAAALAADCgYICAAAAA==.Чувачёк:BAAALAAECgUICQAAAA==.',['Ша']='Шамазюка:BAAALAAECgYIDQAAAA==.Шамохайп:BAAALAADCgIIAgAAAA==.',['Ши']='Шидзука:BAAALAADCgYIBgAAAA==.Шис:BAAALAADCggICQAAAA==.',['Шт']='Штурманюга:BAAALAAECgYIBgAAAA==.',['Шу']='Шурёна:BAAALAAECgEIBAAAAA==.',['Эб']='Эбфид:BAACLAAFFIEFAAICAAMIBQ+JAwD3AAACAAMIBQ+JAwD3AAAsAAQKgRgAAgIACAjxIPYGAPICAAIACAjxIPYGAPICAAAA.',['Эл']='Элистра:BAAALAADCggICAAAAA==.Элнис:BAAALAADCgYIBgAAAA==.',['Эм']='Эмильрина:BAAALAAECgIIAgAAAA==.',['Эф']='Эфочка:BAAALAAECgYICgAAAA==.',['Юа']='Юана:BAAALAAECgUICAAAAA==.',['Юз']='Юзура:BAAALAADCgcIFAAAAA==.',['Юн']='Юна:BAABLAAECoEVAAIRAAgIER0AEQCXAgARAAgIER0AEQCXAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end