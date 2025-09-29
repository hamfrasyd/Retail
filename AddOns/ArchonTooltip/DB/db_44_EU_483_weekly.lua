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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Mage-Arcane','Shaman-Restoration','Priest-Shadow','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Destruction','Hunter-Survival','Warrior-Fury','Monk-Windwalker','Priest-Holy','Priest-Discipline','Monk-Brewmaster','Paladin-Protection','Paladin-Retribution','DeathKnight-Unholy','Druid-Guardian','Warlock-Affliction','Shaman-Enhancement','DemonHunter-Havoc','Paladin-Holy','Mage-Fire','Rogue-Assassination','DeathKnight-Blood','Warlock-Demonology','DeathKnight-Frost','Warrior-Protection',}; local provider = {region='EU',realm='Азурегос',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ёт']='Ётта:BAAALAAECgcIDwAAAA==.',['Аб']='Абсолют:BAAALAAECgYIDAAAAA==.',['Аз']='Аззанулбизар:BAAALAADCgUIBQAAAA==.',['Аи']='Аиланна:BAAALAAECgUICgAAAA==.',['Ай']='Айбан:BAAALAAECgUICAABLAAECgYICgABAAAAAA==.Айленсия:BAAALAAECgYIBgAAAA==.',['Ал']='Алакона:BAAALAADCggIDAAAAA==.Алариэн:BAAALAAECgYIBgAAAA==.Алиси:BAAALAAECggICgAAAA==.Алтрея:BAAALAAECgQIBAAAAA==.Альрик:BAAALAADCgYIEQAAAA==.Альчибот:BAAALAADCggIDwABLAAECggIEQABAAAAAA==.',['Ам']='Амани:BAACLAAFFIEYAAICAAgI1h8nAAA0AwACAAgI1h8nAAA0AwAsAAQKgSAAAgIACAiHJl4BAIoDAAIACAiHJl4BAIoDAAAA.',['Ан']='Аналидзе:BAAALAADCgMIAwAAAA==.Ангелп:BAAALAAECgEIAQAAAA==.Андерлайт:BAAALAAECgEIAQAAAA==.Аннадарк:BAAALAADCgYICAAAAA==.Ансин:BAAALAADCggICAAAAA==.Антрагор:BAABLAAECoEvAAIDAAgIvRiJPQA2AgADAAgIvRiJPQA2AgAAAA==.',['Ап']='Аптечка:BAACLAAFFIEFAAIEAAIIaxosJACYAAAEAAIIaxosJACYAAAsAAQKgS4AAwQACAgpG14lAFoCAAQACAgpG14lAFoCAAIABAjpCAAAAAAAAAAA.',['Ар']='Аррам:BAAALAADCgcIDgAAAA==.Артурос:BAAALAAECggIEAAAAA==.',['Ас']='Асб:BAAALAADCggIDwAAAA==.Асенаги:BAABLAAECoEuAAIFAAgIOyM6CwANAwAFAAgIOyM6CwANAwAAAA==.Асцендер:BAAALAAECgMIAwAAAA==.',['Ат']='Атайлис:BAAALAADCgQIBAAAAA==.Атрианикс:BAAALAADCgYIBgAAAA==.Атэйя:BAABLAAECoEWAAMGAAcIwBEFWQBLAQAGAAcIwBEFWQBLAQAHAAEIxQO+kgAtAAAAAA==.',['Ау']='Ауринаии:BAAALAADCggICAAAAA==.',['Ах']='Ахахахахах:BAAALAAECgMIAwABLAAECggIJAAIACcmAA==.',['Аэ']='Аэрлиса:BAAALAAECggIEAAAAA==.',['Ба']='Балашов:BAABLAAECoEUAAMJAAcISB1VJQArAgAJAAcISB1VJQArAgAKAAMIcQM0CgFIAAAAAA==.Барристанн:BAAALAAECgYIEgABLAAECgcIDgABAAAAAA==.',['Би']='Биоинжектор:BAABLAAECoEWAAILAAYIXhBedABlAQALAAYIXhBedABlAQAAAA==.Биофлор:BAAALAAECggIEAAAAA==.Бирутэ:BAABLAAECoEgAAICAAcI4hT8TwCcAQACAAcI4hT8TwCcAQAAAA==.',['Бу']='Бубзон:BAAALAAECgYIDQAAAA==.Бубзоня:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.',['Бь']='Бьянэ:BAAALAAECgQIBAAAAA==.',['Ва']='Валилий:BAACLAAFFIEJAAIKAAMIqB43EQD3AAAKAAMIqB43EQD3AAAsAAQKgS4AAgoACAhGJQEFAFkDAAoACAhGJQEFAFkDAAEsAAUUBggcAAwAfSIA.Варона:BAABLAAECoEeAAINAAgIRRR0OgAZAgANAAgIRRR0OgAZAgAAAA==.Варрус:BAABLAAECoEZAAIOAAcIuxl+GQAOAgAOAAcIuxl+GQAOAgAAAA==.Ватрунька:BAAALAADCggIBgAAAA==.Вашаняша:BAABLAAECoEdAAIEAAYIDiKgMgAlAgAEAAYIDiKgMgAlAgAAAA==.',['Ве']='Веруюший:BAABLAAECoEYAAMPAAYIphGuVQBcAQAPAAYIphGuVQBcAQAQAAEITQNJOQAhAAAAAA==.',['Ви']='Виплок:BAAALAADCggILQAAAA==.Випшам:BAAALAADCggIHAAAAA==.',['Вл']='Владленчик:BAAALAADCggIFQAAAA==.Власть:BAAALAAECgYIDwAAAA==.',['Во']='Воинбурь:BAABLAAECoExAAIEAAgIEhsbJQBbAgAEAAgIEhsbJQBbAgAAAA==.Войналицо:BAAALAADCgcIFAAAAA==.',['Гд']='Гдемойсефуз:BAAALAADCggIBwAAAA==.Гдемойхилл:BAAALAADCgIIBQABLAAECgcIHgARAJUWAA==.',['Ге']='Герти:BAAALAADCgEIAQAAAA==.',['Ги']='Гидсор:BAAALAADCgcIBwAAAA==.Гипотер:BAAALAADCgYIBgAAAA==.',['Го']='Готфред:BAAALAAECgYIBgAAAA==.Готфри:BAAALAAECgcICAAAAA==.',['Гр']='Гремльн:BAAALAADCgYIAgAAAA==.Греночка:BAACLAAFFIEGAAISAAIItyHhBgDGAAASAAIItyHhBgDGAAAsAAQKgTgAAxIACAhFJZQCAFUDABIACAhFJZQCAFUDABMABgj2DqSvAGMBAAAA.Гронкяйр:BAAALAADCgcIBwAAAA==.Грязныйвагон:BAACLAAFFIEGAAIOAAMI1gn4CAC3AAAOAAMI1gn4CAC3AAAsAAQKgSMAAw4ACAiJHQcPAI0CAA4ACAiJHQcPAI0CAAgABgiGDZIpACABAAAA.Грязныйлуи:BAAALAADCgYIBgAAAA==.',['Гу']='Гулфак:BAABLAAECoEeAAMEAAcIkB1zNAAeAgAEAAYIph9zNAAeAgACAAQItAY+igC4AAAAAA==.',['Гэ']='Гэндельф:BAAALAADCgYIBgAAAA==.',['Да']='Данженгачипа:BAAALAAECgYIBgAAAA==.Датрион:BAABLAAECoEdAAIUAAgIRwhpHwCnAQAUAAgIRwhpHwCnAQAAAA==.Датрэмар:BAAALAADCgIIAgAAAA==.',['Де']='Дентари:BAAALAADCgEIAQAAAA==.Дервиш:BAAALAADCgYIDAAAAA==.',['Дж']='Джастэнгрит:BAABLAAECoEUAAIVAAYIMhz2CwDnAQAVAAYIMhz2CwDnAQAAAA==.Джетбрейн:BAACLAAFFIEGAAMKAAMIkQ+oFgDPAAAKAAMIkQ+oFgDPAAAJAAII8w6wHwCBAAAsAAQKgRYAAgkACAi3GtQgAEoCAAkACAi3GtQgAEoCAAAA.Джигурдяша:BAAALAAECgcIDgAAAA==.',['Ди']='Диззаер:BAAALAAECgYIBgAAAA==.Дикий:BAAALAAECgYICQAAAA==.Димн:BAABLAAECoEeAAMLAAYIHh1vTwDRAQALAAYIHh1vTwDRAQAWAAMIuBLwIwCrAAAAAA==.Дирлеона:BAAALAADCgIIAgAAAA==.',['До']='Добряшшка:BAAALAAECggIDQAAAA==.Докконнорс:BAAALAADCgIIAgAAAA==.',['Др']='Драггар:BAAALAAECgQIBwAAAA==.Драйана:BAAALAAECgMIAwABLAAECgcIIAACAOIUAA==.Дракдиллер:BAAALAAECgYIDgAAAA==.Драконтар:BAAALAAECgYIBgAAAA==.',['Ду']='Душадевица:BAAALAADCgYIAgAAAA==.',['Дэ']='Дэйрина:BAAALAADCgcIBwAAAA==.',['Жа']='Жакир:BAAALAADCggICAAAAA==.',['За']='Заземлитель:BAABLAAECoEdAAIXAAgIvCHlAgAGAwAXAAgIvCHlAgAGAwAAAA==.',['Зе']='Зерадорми:BAAALAADCggIEAAAAA==.',['Зи']='Зирулен:BAAALAADCggICAAAAA==.',['Зл']='Злёба:BAAALAAECgYICgAAAA==.Злёй:BAAALAAECgYIDAAAAA==.',['Ил']='Иллиданьчек:BAAALAAECggIBAAAAA==.',['Ин']='Инерция:BAAALAAECggICAAAAA==.Интус:BAAALAAECgcIDwAAAA==.',['Ир']='Ирита:BAAALAAECgYIBgAAAA==.',['Ис']='Иснокрут:BAAALAADCggIHAAAAA==.Исцелинка:BAAALAAECgcIEAAAAA==.',['Ич']='Ичибичитудай:BAAALAAECgIIBAAAAA==.',['Ка']='Кайлитира:BAACLAAFFIEHAAIYAAIIRhP7LACXAAAYAAIIRhP7LACXAAAsAAQKgUwAAhgACAi5IVkXAPUCABgACAi5IVkXAPUCAAAA.Кайриза:BAABLAAECoEVAAINAAcIghILUgDDAQANAAcIghILUgDDAQAAAA==.Калдуньябк:BAAALAADCgcIBwAAAA==.Камиш:BAAALAAECgcIDAABLAAFFAMIBgALABMgAA==.Каркуша:BAABLAAECoEbAAIGAAYI1B1dNgDTAQAGAAYI1B1dNgDTAQAAAA==.Катаклизм:BAAALAAFFAIIAgAAAA==.Катарида:BAAALAADCgcIBwAAAA==.Катая:BAAALAAECgEIAQAAAA==.Катушка:BAABLAAECoE3AAINAAgIhR3aIwCKAgANAAgIhR3aIwCKAgAAAA==.',['Ке']='Кедасс:BAAALAAECgcIEAAAAA==.Кейджол:BAABLAAECoEUAAMJAAgINBcBJQAuAgAJAAgI2xYBJQAuAgAKAAIIvROC+QBqAAAAAA==.',['Ки']='Кирута:BAAALAADCggIFwAAAA==.Киттенбой:BAAALAAECggICAAAAA==.',['Кл']='Кладра:BAABLAAECoEXAAIFAAYIHhXYQACXAQAFAAYIHhXYQACXAQAAAA==.Клептоман:BAAALAAECgIIAgAAAA==.',['Ко']='Колосса:BAABLAAECoEWAAMTAAgI7AiUnACFAQATAAgI7AiUnACFAQAZAAcIaAz4NgBVAQAAAA==.Котогум:BAAALAAECgMIBgABLAAECgYICgABAAAAAA==.',['Кр']='Кронакс:BAAALAAECgYIBgAAAA==.Крумпа:BAAALAADCgUIBQAAAA==.',['Кс']='Ксалатат:BAABLAAECoEYAAILAAgIaQ7qTQDWAQALAAgIaQ7qTQDWAQAAAA==.Ксеониса:BAAALAAECggICAAAAA==.',['Ку']='Кукуха:BAAALAAECgcIBwAAAA==.Кумалиса:BAABLAAECoEjAAMEAAcIrxvnNgAVAgAEAAcIrxvnNgAVAgACAAYIIBRqaQBIAQAAAA==.Куржин:BAACLAAFFIEGAAIKAAQItA/0DgASAQAKAAQItA/0DgASAQAsAAQKgSQAAgoACAgOIwsfAKwCAAoACAgOIwsfAKwCAAAA.',['Кь']='Кьютя:BAAALAAECgQICgABLAAECgYIFAAVADIcAA==.',['Ла']='Лайтснэтчер:BAAALAADCggIDwAAAA==.Ланаэт:BAAALAADCgIIAwAAAA==.',['Ле']='Леми:BAAALAAECgYIEAAAAA==.Лесишкотян:BAAALAADCgcICAAAAA==.',['Ли']='Лилиан:BAAALAAECgYIEQAAAA==.Лиорен:BAAALAAECgEIAQAAAA==.Липрон:BAAALAAECgYIDAAAAA==.Литавия:BAAALAAECgYIEAAAAA==.',['Ло']='Лоулес:BAAALAADCgMIAwABLAAECggILAANAF4hAA==.Лоутаб:BAABLAAECoEYAAMDAAgI5xx0KgCKAgADAAgI5xx0KgCKAgAaAAMIdA8OEgCmAAAAAA==.',['Лу']='Луджейн:BAAALAADCggICgAAAA==.',['Ля']='Лялядру:BAABLAAECoEkAAIVAAYICxjGEQB9AQAVAAYICxjGEQB9AQAAAA==.',['Ма']='Мамаиллидана:BAAALAAECgYIDQABLAAECgYIDwABAAAAAA==.Мамбиха:BAAALAAECgQIBAABLAAECgYICgABAAAAAA==.Маэна:BAAALAAECgUIBQABLAAECgcIIAACAOIUAA==.',['Ме']='Мегуста:BAAALAADCgEIAQAAAA==.Медее:BAAALAAECgYIDAABLAAFFAMIDQAbAI0aAA==.Меркатор:BAAALAAECgYIBgAAAA==.Меротана:BAACLAAFFIEMAAIcAAMIVQ+yBwC8AAAcAAMIVQ+yBwC8AAAsAAQKgTQAAhwACAjCGmcOADcCABwACAjCGmcOADcCAAAA.Мерсилония:BAAALAAECgcIEgAAAA==.Механика:BAACLAAFFIEIAAIYAAII2A/MLwCUAAAYAAII2A/MLwCUAAAsAAQKgR8AAhgABwi0GCpKABkCABgABwi0GCpKABkCAAAA.',['Ми']='Микил:BAABLAAECoEgAAMXAAgIEheeFAB1AQAXAAgIEheeFAB1AQAEAAcIfg8xdQBiAQAAAA==.Микки:BAAALAAECgEIAQAAAA==.',['Мо']='Мойра:BAAALAAFFAEIAQAAAA==.Молон:BAAALAADCggICAAAAA==.',['Му']='Мунспэл:BAABLAAECoEUAAIHAAYINxPbUwAuAQAHAAYINxPbUwAuAQAAAA==.Мустакиви:BAAALAADCggICAAAAA==.',['На']='Наабе:BAAALAADCggIGAAAAA==.',['Не']='Недоуч:BAAALAADCgYIBwAAAA==.Нейровэлл:BAAALAAECgYIEQAAAA==.Нексюша:BAABLAAECoEWAAIDAAYI4SFJPAA7AgADAAYI4SFJPAA7AgAAAA==.Неспра:BAAALAAECgYIDAAAAA==.',['Но']='Нонтоксик:BAAALAADCggICAAAAA==.Носок:BAABLAAECoEkAAIIAAgIJyZ2AAB8AwAIAAgIJyZ2AAB8AwAAAA==.',['Нэ']='Нэксиа:BAAALAADCggIEAAAAA==.',['Ог']='Огоний:BAABLAAECoEhAAIIAAcIYQfILgD3AAAIAAcIYQfILgD3AAAAAA==.',['Ок']='Оккультистка:BAAALAAECgQIBAAAAA==.',['Ол']='Оленюшка:BAABLAAECoEYAAIEAAcIix1jNQAbAgAEAAcIix1jNQAbAgAAAA==.',['Он']='Онаи:BAAALAADCgUIBQAAAA==.',['Па']='Пазузу:BAABLAAECoEXAAIdAAYIrBmkIADgAQAdAAYIrBmkIADgAQAAAA==.Паладинция:BAAALAADCgYIBgAAAA==.Палычь:BAAALAAECgYIDAABLAAECggIIwAKAN0jAA==.Пан:BAAALAAECggIDwABLAAECggIHwACAAQZAA==.Пашаубийца:BAABLAAECoEZAAIeAAYICBNBtQBmAQAeAAYICBNBtQBmAQAAAA==.',['Пе']='Пеймыт:BAAALAAECgUIBwAAAA==.Пемфедо:BAACLAAFFIENAAIbAAMIjRofCQAIAQAbAAMIjRofCQAIAQAsAAQKgTcAAhsACAi2I0IHAAMDABsACAi2I0IHAAMDAAAA.Песняветров:BAAALAAECggICQAAAA==.',['Пл']='Плэгус:BAAALAAECgIIAgAAAA==.',['По']='Пододеяльник:BAABLAAECoEZAAIYAAYIvBrgagDEAQAYAAYIvBrgagDEAQAAAA==.Покетик:BAABLAAECoEjAAIKAAgI3SMbFQDlAgAKAAgI3SMbFQDlAgAAAA==.Покотун:BAAALAADCgUIBQABLAAECgIIAwABAAAAAA==.Похороны:BAAALAAECggICAAAAA==.',['Пр']='Пранкстэр:BAAALAADCggICAAAAA==.Прянчик:BAAALAAECggICwAAAA==.',['Пс']='Псиблейдс:BAABLAAECoEnAAIYAAgIaCDnGgDgAgAYAAgIaCDnGgDgAgAAAA==.',['Пу']='Пулеметчик:BAAALAAECgcIBwAAAA==.Пупсикгёрл:BAAALAAECgYIDAAAAA==.Пуфик:BAAALAAECgYIDgAAAA==.Пуффия:BAAALAADCgYIBgAAAA==.',['Ра']='Райзгуд:BAAALAAECgEIAQABLAAFFAIIBAABAAAAAA==.Расп:BAAALAAECgYIDQAAAA==.Рачекан:BAAALAAECgYIDwAAAA==.',['Ре']='Ревендрэт:BAAALAAECgYIEAABLAAFFAMICQALAEAKAA==.Редэвил:BAAALAADCgQIBAAAAA==.Релаинда:BAAALAADCggICAABLAAECgcIHgARAJUWAA==.Реламрачная:BAAALAAECgYICgABLAAECgcIHgARAJUWAA==.Реласветлая:BAAALAAECgEIAQABLAAECgcIHgARAJUWAA==.Релуяси:BAAALAADCggIHgABLAAECgcIHgARAJUWAA==.',['Ри']='Ридорка:BAAALAADCggIIwAAAA==.Рикиморис:BAAALAAECgYICQAAAA==.',['Ру']='Рубисплеча:BAAALAADCggICAAAAA==.Русстикк:BAAALAADCgQIBAAAAA==.Руфало:BAAALAAECggICAAAAA==.',['Са']='Сантура:BAABLAAECoEsAAMNAAgIXiG7FgDgAgANAAgIXiG7FgDgAgAfAAMIwxY4ZwB6AAAAAA==.Сапфиира:BAAALAADCgcICAABLAAECgcIEgABAAAAAA==.Сартариона:BAAALAADCggICAAAAA==.Саториэл:BAAALAAECggIBgAAAA==.',['Св']='Светорина:BAAALAAECgYICAAAAA==.Светосила:BAAALAAECgEIAQAAAA==.Светослав:BAAALAAECggIBQAAAA==.',['Се']='Серега:BAAALAAECgUIBwAAAA==.Сестренкаджа:BAAALAADCgYIBgAAAA==.Сечер:BAAALAAECgcIEQAAAA==.',['Си']='Симарика:BAAALAAECgcIEwAAAA==.',['Сл']='Случайныйджо:BAAALAADCgcIEAAAAA==.',['См']='Смотрящая:BAAALAAECggIDQAAAA==.',['Сн']='Снайпик:BAAALAADCgUIBQAAAA==.',['Со']='Совенькотень:BAABLAAECoEXAAIGAAgITx1GEgCmAgAGAAgITx1GEgCmAgAAAA==.Солериний:BAAALAAECggIEQAAAA==.',['Ст']='Старволкер:BAAALAAECgYIEgAAAA==.Степанодин:BAACLAAFFIEGAAIWAAII7RdmAgCoAAAWAAII7RdmAgCoAAAsAAQKgS8AAhYACAg8JHwBAC8DABYACAg8JHwBAC8DAAAA.',['Су']='Суита:BAAALAAECgYICgAAAA==.Суро:BAAALAAECgYICAAAAA==.Суруми:BAAALAADCggIDgAAAA==.',['Сы']='Сыроежкин:BAAALAAECgIIAgAAAA==.',['Сё']='Сёно:BAABLAAECoEXAAIKAAcIYSH3QQAaAgAKAAcIYSH3QQAaAgAAAA==.',['Та']='Тайроли:BAAALAADCggICAABLAAECgcIIAACAOIUAA==.Талрунил:BAAALAAECgcIEAAAAA==.Танкопусс:BAAALAAFFAIIAgABLAAFFAUIDwAeAN4gAA==.Таограц:BAAALAAECgYIEAAAAA==.',['Те']='Теркель:BAAALAADCggIHQAAAA==.',['Ти']='Тирмониам:BAABLAAECoEhAAIYAAcImA+2jQB9AQAYAAcImA+2jQB9AQAAAA==.',['Тр']='Травофил:BAABLAAECoEgAAMKAAYIryHmTAD4AQAKAAYIryHmTAD4AQAJAAEILQqVtQApAAAAAA==.Третийбог:BAAALAAECgYIBwABLAAFFAMIBgALABMgAA==.Трикаста:BAAALAAECgMIAwABLAAECggIIQALAMsUAA==.Трупоед:BAAALAAECgIIAgAAAA==.',['Ту']='Тума:BAACLAAFFIEKAAMLAAMI+RP6LACXAAALAAMIyBH6LACXAAAWAAEIaRPpBQBOAAAsAAQKgSgABAsACAhDGgM0AD4CAAsACAgUGAM0AD4CABYABQgzEpAUAFUBAB0AAgjKBHR4AF8AAAAA.',['Ты']='Тык:BAAALAADCgYIBwAAAA==.',['Тя']='Тяланда:BAAALAAECggIDgAAAA==.',['Ус']='Усубб:BAAALAADCgMIAwAAAA==.',['Уш']='Ушастик:BAAALAADCggICAAAAA==.',['Фа']='Фаланхор:BAACLAAFFIEHAAIVAAIIlRHzBAB1AAAVAAIIlRHzBAB1AAAsAAQKgWEAAhUACAi+GwkHAFwCABUACAi+GwkHAFwCAAAA.Фантер:BAAALAADCgYIBgAAAA==.Фатаморфана:BAAALAAECgIIAgAAAA==.',['Фе']='Фенри:BAABLAAECoEcAAIeAAYIMh08iwCtAQAeAAYIMh08iwCtAQAAAA==.Фералпранк:BAAALAADCgcIBwAAAA==.',['Фи']='Филдур:BAABLAAECoEwAAIHAAgImBSHMgDFAQAHAAgImBSHMgDFAQAAAA==.',['Фо']='Форм:BAABLAAECoEzAAIKAAgIuB/ZJQCIAgAKAAgIuB/ZJQCIAgAAAA==.Фотон:BAAALAADCggIMwAAAA==.',['Фу']='Фуналекс:BAAALAAECgYIDwAAAA==.Фуркаа:BAAALAAECgQIBQAAAA==.',['Фь']='Фьяра:BAABLAAECoEaAAIfAAcIfBA4NgBuAQAfAAcIfBA4NgBuAQAAAA==.Фьёрика:BAACLAAFFIEQAAIUAAUIABt+AAD8AQAUAAUIABt+AAD8AQAsAAQKgR8AAhQACAjZJSsCAEQDABQACAjZJSsCAEQDAAAA.',['Ха']='Хаверон:BAAALAADCgQIBAAAAA==.Хаджибей:BAAALAAECgMIBQAAAA==.Халэ:BAAALAAECgYICwAAAA==.Хардрок:BAABLAAECoEWAAIEAAgIrxfmNQAZAgAEAAgIrxfmNQAZAgAAAA==.Хасаши:BAAALAADCgcIBwAAAA==.',['Хв']='Хвилдмонк:BAAALAAECgYIEQAAAA==.',['Хе']='Хеллбаффи:BAABLAAECoEiAAMQAAYIciJOBQBPAgAQAAYIciJOBQBPAgAPAAYI3wrsaQAYAQAAAA==.Хеллизи:BAAALAAECgMIAwAAAA==.Хеллчу:BAAALAAECgYIDgAAAA==.Хентари:BAAALAAECgYIEwAAAA==.Хетвилд:BAAALAADCggIFAAAAA==.Хетвилт:BAAALAAECgEIAQAAAA==.',['Хи']='Хилл:BAAALAAECgIIAgAAAA==.',['Хм']='Хмурыйчёрт:BAABLAAECoEZAAILAAYI+B3KQAAHAgALAAYI+B3KQAAHAgAAAA==.',['Хо']='Холлс:BAABLAAECoEUAAMHAAcIWhIEXwD9AAAHAAUIiw4EXwD9AAAGAAYIzwokdQD4AAAAAA==.',['Хр']='Хризантемия:BAAALAAECgcIDgAAAA==.',['Ци']='Циэль:BAABLAAECoEhAAIEAAcIiRkwQQDzAQAEAAcIiRkwQQDzAQAAAA==.',['Че']='Черемша:BAAALAADCgcICQAAAA==.Чермантий:BAAALAAECgYIDgABLAAECgcIIQAYAJgPAA==.Чертовски:BAAALAADCggICAAAAA==.',['Эк']='Эксклюзив:BAABLAAECoEVAAIVAAYIahNJFgA2AQAVAAYIahNJFgA2AQAAAA==.',['Эл']='Элонэр:BAAALAAECgcIEAAAAA==.',['Эм']='Эмонгэсс:BAAALAAECgYIDwAAAA==.',['Эн']='Эндерсторф:BAACLAAFFIEGAAMLAAMIEyBWFQAPAQALAAMIbB5WFQAPAQAdAAEIeiFkGwBbAAAsAAQKgTEABAsACAhIJnMYANkCAAsABwgzJXMYANkCAB0ABQhbJQYZABMCABYABQiBHc4NALkBAAAA.Энхпранк:BAAALAAECgYIEAAAAA==.',['Эс']='Эсария:BAABLAAECoEoAAIXAAgI9iP2AQArAwAXAAgI9iP2AQArAwAAAA==.',['Эу']='Эурлин:BAAALAADCgEIAQABLAAECgcIEgABAAAAAA==.',['Юг']='Югвогне:BAABLAAECoEhAAILAAgIyxRRPQAWAgALAAgIyxRRPQAWAgAAAA==.',['Юл']='Юлара:BAAALAAECgUIBwABLAAECgcIIAACAOIUAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end