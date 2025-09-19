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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','DemonHunter-Havoc','Warlock-Affliction','Warrior-Fury','Rogue-Assassination','Druid-Guardian','DeathKnight-Unholy','Warlock-Demonology','Warlock-Destruction',}; local provider = {region='EU',realm='Азурегос',name='EU',type='weekly',zone=44,date='2025-08-31',data={['Ёт']='Ётта:BAAALAAECgUIBwAAAA==.',['Аб']='Абсолют:BAAALAAECgYIBgAAAA==.',['Аи']='Аиланна:BAAALAAECgQICAAAAA==.',['Ай']='Айбан:BAAALAAECgMIBAABLAAECgQIBAABAAAAAA==.',['Ал']='Алариэн:BAAALAADCggIFQAAAA==.Алтрея:BAAALAAECgQIBAAAAA==.Альрик:BAAALAADCgYIEQAAAA==.Альчибот:BAAALAADCggIDwAAAA==.',['Ам']='Амани:BAAALAAFFAIIAgAAAA==.',['Ан']='Антрагор:BAAALAAECgYIDwAAAA==.',['Ап']='Аптечка:BAAALAAECgcIEgAAAA==.',['Ар']='Аррам:BAAALAADCgcIBwAAAA==.',['Ас']='Асенаги:BAAALAAECgcIDwAAAA==.',['Ат']='Атайлис:BAAALAADCgQIBAAAAA==.Атэйя:BAAALAAFFAEIAQAAAA==.',['Ба']='Балашов:BAAALAAFFAEIAQAAAA==.Барристанн:BAAALAAECgQIBgAAAA==.',['Би']='Биоинжектор:BAAALAAECgYICAAAAA==.Биофлор:BAAALAAECggICAAAAA==.Бирутэ:BAAALAAECgYICAAAAA==.',['Бь']='Бьянэ:BAAALAAECgQIBAAAAA==.',['Ва']='Валилий:BAABLAAECoEWAAICAAgIZSF0BgAGAwACAAgIZSF0BgAGAwAAAA==.Варона:BAAALAAECgcIDgAAAA==.Варрус:BAAALAAECgQIBgAAAA==.Ватрунька:BAAALAADCggIBgAAAA==.Вашаняша:BAAALAAECgYICgAAAA==.',['Ве']='Веруюший:BAAALAADCgYIBgAAAA==.',['Ви']='Виплок:BAAALAADCggIFgAAAA==.Випшам:BAAALAADCggICAAAAA==.',['Вл']='Владленчик:BAAALAADCggIFQAAAA==.Власть:BAAALAAECgMIAwAAAA==.',['Во']='Воинбурь:BAAALAAECgcIEAAAAA==.',['Гд']='Гдемойхилл:BAAALAADCgIIBAABLAAECgEIAQABAAAAAA==.',['Ги']='Гидсор:BAAALAADCgcIBwAAAA==.Гипотер:BAAALAADCgYIBgAAAA==.',['Го']='Готфред:BAAALAADCggICAAAAA==.Готфри:BAAALAADCgQIBQAAAA==.',['Гр']='Греночка:BAAALAAECgcIEQAAAA==.Грязныйвагон:BAAALAAECgYIDwAAAA==.Грязныйлуи:BAAALAADCgYIBgAAAA==.',['Гу']='Гулфак:BAAALAAECgYICQAAAA==.',['Да']='Датрион:BAAALAAECggIDAAAAA==.',['Де']='Дервиш:BAAALAADCgYIDAAAAA==.',['Дж']='Джастэнгрит:BAAALAAECgMIBAABLAAECgMIBgABAAAAAA==.Джетбрейн:BAAALAAECgcIDQAAAA==.Джигурдяша:BAAALAAECgQIBAABLAAECgQIBgABAAAAAA==.',['Ди']='Дикий:BAAALAAECgYICQAAAA==.Димн:BAAALAAECgYICgAAAA==.Дирлеона:BAAALAADCgIIAgAAAA==.',['До']='Добряшшка:BAAALAAECggIBQAAAA==.',['Др']='Драггар:BAAALAADCggIGQAAAA==.Дракдиллер:BAAALAAECgYIBgAAAA==.',['Дэ']='Дэйрина:BAAALAADCgcIBwAAAA==.',['Жа']='Жакир:BAAALAADCggICAAAAA==.',['За']='Заземлитель:BAAALAAECgcIDAAAAA==.',['Зл']='Злёй:BAAALAAECgEIAQAAAA==.',['Ир']='Ирита:BAAALAADCgIIAgAAAA==.',['Ис']='Иснокрут:BAAALAADCggIGgAAAA==.Исцелинка:BAAALAAECgMIAwAAAA==.',['Ич']='Ичибичитудай:BAAALAAECgIIAgAAAA==.',['Ка']='Кайлитира:BAABLAAECoEdAAIDAAcI9BnzHgAhAgADAAcI9BnzHgAhAgAAAA==.Камиш:BAAALAAECgcIBgABLAAECgcIFQAEAI0iAA==.Каркуша:BAAALAAECgQIBAAAAA==.Катаклизм:BAAALAADCgYIBgAAAA==.Катарида:BAAALAADCgcIBwAAAA==.Катая:BAAALAADCggICAAAAA==.Катушка:BAABLAAECoEZAAIFAAcIyRCtHADtAQAFAAcIyRCtHADtAQAAAA==.',['Ке']='Кедасс:BAAALAAECgcICwAAAA==.Кейджол:BAAALAAECgYIBwAAAA==.',['Ки']='Кирута:BAAALAADCgcIDAAAAA==.',['Ко']='Котогум:BAAALAAECgMIBgABLAAECgQIBAABAAAAAA==.',['Кс']='Ксалатат:BAAALAAECggICgAAAA==.',['Ку']='Кумалиса:BAAALAAECgQICgAAAA==.Куржин:BAABLAAECoEWAAICAAgIHSF+BgAFAwACAAgIHSF+BgAFAwAAAA==.',['Кь']='Кьютя:BAAALAAECgMIBgAAAA==.',['Ла']='Лайтснэтчер:BAAALAADCgcIBwAAAA==.Ланаэт:BAAALAADCgIIAwAAAA==.',['Ле']='Лесишкотян:BAAALAADCgcICAAAAA==.',['Ли']='Лилиан:BAAALAADCggIFgAAAA==.Липрон:BAAALAADCgIIAgAAAA==.Литавия:BAAALAADCggIDAAAAA==.',['Ло']='Лоулес:BAAALAADCgMIAwABLAAECggIEwABAAAAAA==.Лоутаб:BAAALAAECgcIEAAAAA==.',['Ля']='Лялядру:BAAALAAECgYICgAAAA==.',['Ма']='Мамаиллидана:BAAALAAECgMIBwAAAA==.Мамбиха:BAAALAAECgQIBAAAAA==.',['Ме']='Медее:BAAALAAECgYIBgAAAA==.Меркатор:BAAALAADCgMIAwAAAA==.Меротана:BAAALAAECgcIEwAAAA==.Мерсилония:BAAALAAECgMIBQAAAA==.Механика:BAAALAAECgcICQAAAA==.',['Ми']='Микил:BAAALAAECgYIBgAAAA==.Микки:BAAALAADCggIDAAAAA==.',['Мо']='Мойра:BAAALAAFFAEIAQAAAA==.',['Му']='Мунспэл:BAAALAAECgIIAgAAAA==.Мустакиви:BAAALAADCggICAAAAA==.',['На']='Наабе:BAAALAADCggICAAAAA==.',['Не']='Недоуч:BAAALAADCgYIBwAAAA==.Нейровэлл:BAAALAAECgMIBgAAAA==.Нексюша:BAAALAAECgMIBgAAAA==.',['Но']='Носок:BAAALAAECgcIEAAAAA==.',['Ог']='Огоний:BAAALAAECgQIBwAAAA==.',['Ол']='Оленюшка:BAAALAAECgMIBQAAAA==.',['Па']='Пазузу:BAAALAAECgMIBwAAAA==.Паладинция:BAAALAADCgYIBgAAAA==.Палычь:BAAALAAECgYIBgABLAAECgcIDQABAAAAAA==.Пашаубийца:BAAALAAECgYIDQAAAA==.',['Пе']='Пемфедо:BAABLAAECoEXAAIGAAgIIRkZCwCCAgAGAAgIIRkZCwCCAgAAAA==.',['Пл']='Плэгус:BAAALAAECgIIAgAAAA==.',['По']='Пододеяльник:BAAALAAECgYICAAAAA==.Покетик:BAAALAAECgcIDQAAAA==.',['Пр']='Прянчик:BAAALAAECgMIAwAAAA==.',['Пс']='Псиблейдс:BAAALAAECgcIEAAAAA==.',['Пу']='Пуфик:BAAALAADCgcICAAAAA==.',['Ра']='Рачекан:BAAALAAECgIIBAAAAA==.',['Ре']='Ревендрэт:BAAALAAECgYIBgAAAA==.Реламрачная:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.Реласветлая:BAAALAAECgEIAQAAAA==.Релуяси:BAAALAADCggIEQABLAAECgEIAQABAAAAAA==.',['Ри']='Ридорка:BAAALAADCggIFgAAAA==.Рикиморис:BAAALAAECgMIAwAAAA==.',['Ру']='Русстикк:BAAALAADCgQIBAAAAA==.',['Са']='Сантура:BAAALAAECggIEwAAAA==.Сартариона:BAAALAADCggICAAAAA==.Саториэл:BAAALAAECggIBgAAAA==.',['Св']='Светорина:BAAALAAECgEIAQAAAA==.Светосила:BAAALAADCggICgAAAA==.',['Се']='Серега:BAAALAADCgYIBgAAAA==.Сестренкаджа:BAAALAADCgYIBgAAAA==.Сечер:BAAALAAECgIIAgAAAA==.',['Си']='Симарика:BAAALAAECgQIBAAAAA==.',['Сл']='Случайныйджо:BAAALAADCgcIEAAAAA==.',['См']='Смотрящая:BAAALAADCgcIBwAAAA==.',['Сн']='Снайпик:BAAALAADCgQIBAAAAA==.',['Со']='Совенькотень:BAAALAAECgcIBwAAAA==.Солериний:BAAALAAECgcIEAAAAA==.',['Ст']='Старволкер:BAAALAAECgEIAQAAAA==.Степанодин:BAAALAAECgcIEQAAAA==.',['Су']='Суро:BAAALAAECgYICAAAAA==.Суруми:BAAALAADCgcIBwAAAA==.',['Сё']='Сёно:BAAALAAECgQICgAAAA==.',['Та']='Таймэль:BAAALAAECgMIBAAAAA==.Тайроли:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Талрунил:BAAALAAECgMIAwAAAA==.Таограц:BAAALAAECgYICAAAAA==.',['Те']='Теркель:BAAALAADCggIDgAAAA==.',['Ти']='Тирмониам:BAAALAAECgYICAAAAA==.',['Тр']='Травофил:BAAALAAECgYICAAAAA==.',['Ту']='Тума:BAAALAAECgcIEgAAAA==.',['Ты']='Тык:BAAALAADCgYIBwAAAA==.',['Тя']='Тяланда:BAAALAAECgYIBgAAAA==.',['Ус']='Усубб:BAAALAADCgMIAwAAAA==.',['Фа']='Фаланхор:BAABLAAECoEgAAIHAAcIng6kBgBmAQAHAAcIng6kBgBmAQAAAA==.Фатаморфана:BAAALAAECgIIAgAAAA==.',['Фе']='Фенри:BAAALAAECgIIAgAAAA==.Фенук:BAAALAADCgYIBwAAAA==.Фералпранк:BAAALAADCgcIBwAAAA==.',['Фи']='Филдур:BAAALAAECgYIDwAAAA==.',['Фо']='Форм:BAAALAAECgcIEQAAAA==.Фотон:BAAALAADCggIGAAAAA==.',['Фу']='Фуналекс:BAAALAAECgQIBgAAAA==.Фуркаа:BAAALAAECgMIAwAAAA==.',['Фь']='Фьяра:BAAALAAECgYICAAAAA==.Фьёрика:BAABLAAECoEcAAIIAAgIwiU2AACCAwAIAAgIwiU2AACCAwAAAA==.',['Ха']='Хаверон:BAAALAADCgQIBAAAAA==.Хардрок:BAAALAAECgYIBgAAAA==.',['Хв']='Хвилдмонк:BAAALAAECgQIBQAAAA==.',['Хе']='Хеллбаффи:BAAALAAECgYICgAAAA==.Хеллизи:BAAALAADCgcIBwAAAA==.Хеллчу:BAAALAADCggICQAAAA==.Хентари:BAAALAADCgQIBAAAAA==.',['Хм']='Хмурыйчёрт:BAAALAAECgYICgAAAA==.',['Хо']='Холлс:BAAALAAECgYIBwAAAA==.',['Хр']='Хризантемия:BAAALAAECgQIBAAAAA==.',['Ци']='Циэль:BAAALAAECgYIDgAAAA==.',['Че']='Черемша:BAAALAADCgcICQAAAA==.Чермантий:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.',['Эк']='Эксклюзив:BAAALAAECgYIDwAAAA==.',['Эл']='Элонэр:BAAALAAECgMIAwAAAA==.',['Эн']='Эндерсторф:BAABLAAECoEVAAQEAAcIjSKfCADNAQAEAAUIyhyfCADNAQAJAAQIhhrZJwAzAQAKAAMIiCEIOgAkAQAAAA==.Энхпранк:BAAALAAECgMIBAAAAA==.',['Эс']='Эсария:BAAALAAECgYIDAAAAA==.',['Юг']='Югвогне:BAAALAAECgYICQAAAA==.',['Юл']='Юлара:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end