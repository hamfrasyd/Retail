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
 local lookup = {'Druid-Balance','DeathKnight-Blood','Hunter-Marksmanship','Paladin-Holy','Druid-Restoration','Druid-Guardian','Hunter-BeastMastery','Mage-Fire','Mage-Arcane','DeathKnight-Frost','Warrior-Fury','DemonHunter-Havoc','Shaman-Restoration','Unknown-Unknown','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Holy','Shaman-Elemental','Warrior-Arms','DeathKnight-Unholy','Warlock-Destruction','Priest-Discipline','Hunter-Survival','Paladin-Retribution','Mage-Frost','Rogue-Assassination','Warlock-Demonology',}; local provider = {region='EU',realm='Гром',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ёо']='Ёода:BAABLAAECoEnAAIBAAgIqxlvHABTAgABAAgIqxlvHABTAgAAAA==.',['Ёщ']='Ёщимитсу:BAAALAAECgEIAQAAAA==.',['Ав']='Авесаллом:BAAALAAECgIIAgAAAA==.Авистар:BAAALAAECgMIBgAAAA==.',['Аз']='Азнаур:BAAALAADCggICgABLAAECgcIKQACAHQlAA==.Азович:BAABLAAECoEUAAIDAAgISQw4UABbAQADAAgISQw4UABbAQAAAA==.',['Ай']='Айсхаммер:BAAALAADCggICAAAAA==.',['Ак']='Акли:BAAALAAECgYIDwAAAA==.',['Ал']='Алистар:BAAALAAECgcIDwAAAA==.Аллерийя:BAAALAADCgYIBgAAAA==.Альвэаэнерле:BAACLAAFFIEJAAIEAAIIoxz8DgCxAAAEAAIIoxz8DgCxAAAsAAQKgSoAAgQACAgfHekMAJMCAAQACAgfHekMAJMCAAAA.Аляксия:BAABLAAECoEdAAIFAAgI2B4XFQCOAgAFAAgI2B4XFQCOAgAAAA==.',['Ам']='Амаранте:BAAALAAECggIEgAAAA==.Амелис:BAAALAAECgEIAQAAAA==.',['Ан']='Андоридалл:BAABLAAECoEdAAMBAAgIMBdPIgAlAgABAAgIMBdPIgAlAgAGAAgIcQ1mEQCDAQAAAA==.Ани:BAABLAAECoEkAAIHAAgISiLUEgD0AgAHAAgISiLUEgD0AgAAAA==.Ануб:BAAALAAECgYIBgAAAA==.Анютик:BAAALAADCgcIDQAAAA==.',['Ар']='Архиматос:BAAALAADCgMIBAAAAA==.Архонис:BAACLAAFFIEaAAMIAAYIJhemAQACAQAJAAUIfg06DwCGAQAIAAQI2RimAQACAQAsAAQKgSUAAwgACAiZIrQBAOwCAAgACAjsILQBAOwCAAkACAhvIS8qAIsCAAAA.Арчи:BAAALAAECgYIDQABLAAECgcIHgAKALIkAA==.',['Ас']='Асдрагор:BAAALAADCgQIBQAAAA==.Асулимдх:BAAALAAECgYIBwAAAA==.Асёнок:BAAALAAECgIIAgAAAA==.',['Ат']='Атоми:BAAALAAECgYIBgAAAA==.Аттерахрон:BAAALAADCgUIBQAAAA==.',['Ау']='Аугил:BAAALAAECgYIDwAAAA==.',['Ба']='Багряненко:BAAALAAECgYIEQAAAA==.Бадзу:BAABLAAECoEaAAILAAYIXxjYUwC+AQALAAYIXxjYUwC+AQAAAA==.Баррель:BAACLAAFFIELAAIMAAMI8CPzDQAmAQAMAAMI8CPzDQAmAQAsAAQKgS8AAgwACAjuJWEEAGwDAAwACAjuJWEEAGwDAAAA.',['Бе']='Безмата:BAAALAAECgIIAgAAAA==.',['Бо']='Борщ:BAAALAADCggICAAAAA==.',['Бу']='Будан:BAAALAAECggICAAAAA==.Буданенко:BAAALAAECggICAAAAA==.Будильник:BAAALAAECgIIAgAAAA==.Буйныйгрог:BAAALAAECggICAABLAAFFAMICQANAJ8bAA==.Бургерклап:BAAALAAECgEIAQAAAA==.Буча:BAABLAAECoEeAAIKAAcIsiQqGwDnAgAKAAcIsiQqGwDnAgAAAA==.',['Ва']='Вагонвожатая:BAAALAAECgIIAgAAAA==.Вазьмак:BAAALAAECggICgAAAA==.Ваймс:BAAALAADCggICgAAAA==.Варкез:BAAALAADCggIDAAAAA==.',['Ви']='Вибрисса:BAAALAAECgEIAQABLAAECgYIEwAOAAAAAA==.Виктини:BAAALAADCggICAABLAAECggIDgAOAAAAAA==.',['Во']='Войдглиф:BAAALAADCgEIAQAAAA==.',['Га']='Гаасиенда:BAAALAAECgcIDAABLAAFFAIICQAEAKMcAA==.Гаритос:BAAALAADCggIHwAAAA==.Гаррипоттер:BAAALAADCgYIBgAAAA==.',['Го']='Горвин:BAAALAADCggIGwAAAA==.',['Гр']='Грасатор:BAAALAADCgEIAQAAAA==.',['Гэ']='Гэнгсташаман:BAACLAAFFIEJAAMNAAMInxtVKQCLAAANAAIILhdVKQCLAAAPAAEI3gV4BwBOAAAsAAQKgR8AAw8ACAivH5YLABQCAA8ABgjtHpYLABQCAA0ACAhQFoJFAOUBAAAA.',['Да']='Дайв:BAACLAAFFIEGAAIQAAIIcBAhDABxAAAQAAIIcBAhDABxAAAsAAQKgRcAAhAABwjcGvgSABACABAABwjcGvgSABACAAEsAAUUBggWAAkACRcA.Далас:BAAALAAECgEIAQAAAA==.Дамир:BAAALAAECgcIEQAAAA==.',['Дв']='Дветош:BAAALAADCgUIBgAAAA==.',['Дж']='Джейин:BAAALAADCgMIAwAAAA==.Джейлен:BAAALAAECggIIwAAAQ==.Джеромай:BAAALAAECgcIDQAAAA==.Джитикс:BAAALAAECgYICAAAAA==.Джорелия:BAAALAAECggICgAAAA==.',['Ди']='Ди:BAABLAAECoEfAAIRAAcIQCP4EgC3AgARAAcIQCP4EgC3AgAAAA==.Дианси:BAAALAAECggIDgAAAA==.Дивертсс:BAABLAAFFIEFAAISAAIIVA3tJgB9AAASAAIIVA3tJgB9AAAAAA==.Дидович:BAAALAAECgcIDQAAAA==.',['Дк']='Дкан:BAAALAAECgIIAgABLAAFFAQIAgAOAAAAAA==.',['Ду']='Дурмашина:BAAALAADCggICAAAAA==.',['Ев']='Евиовар:BAAALAAECgEIAQAAAA==.Евиолок:BAAALAADCgMIAwAAAA==.',['Еж']='Ежевничка:BAAALAADCggIEAAAAA==.',['Ец']='Ецо:BAAALAADCgcIBwAAAA==.',['Же']='Железяка:BAABLAAECoEcAAISAAgI+BdzKQBJAgASAAgI+BdzKQBJAgAAAA==.',['За']='Заколот:BAAALAAECggIAgAAAA==.',['Зе']='Зерот:BAAALAAECgYIEAAAAA==.',['Зи']='Зипушечка:BAABLAAECoEWAAIMAAgI5hUeSwAWAgAMAAgI5hUeSwAWAgAAAA==.',['Зр']='Зрадич:BAAALAAECgMIAwABLAAECgYIDAAOAAAAAA==.',['Зу']='Зулабэб:BAAALAAECgEIAQAAAA==.Зулгар:BAAALAADCggIEgAAAA==.',['Ии']='Иинкс:BAAALAADCgYIBgAAAA==.',['Ин']='Инфернальный:BAAALAAECggICAAAAA==.',['Йо']='Йотакс:BAAALAADCgcICAAAAA==.',['Ка']='Капримо:BAAALAAECgYIEAAAAA==.Катаастроффа:BAAALAAECggIBgAAAA==.Кататоник:BAAALAADCgIIAwAAAA==.Катринка:BAAALAADCggIEgAAAA==.',['Ке']='Кеин:BAABLAAECoEqAAMNAAgIyR6LGACcAgANAAgIyR6LGACcAgASAAUIHA3DcwAiAQAAAA==.Кей:BAAALAAECgYIDAAAAA==.',['Ки']='Кирасу:BAAALAADCgEIAQAAAA==.',['Кл']='Клубничкакис:BAAALAAECggIDgAAAA==.',['Ко']='Комфортно:BAAALAAECggICAAAAA==.',['Кр']='Крода:BAABLAAECoEYAAMTAAYIpRnKGAA3AQATAAYIpRnKGAA3AQALAAMI7geCtgCAAAAAAA==.',['Ку']='Кузьма:BAABLAAECoEVAAIUAAgI1hO8EgAhAgAUAAgI1hO8EgAhAgAAAA==.Кумарич:BAAALAAECgYIDAAAAA==.',['Ла']='Лагерда:BAAALAAECgYICgAAAA==.',['Ле']='Легендар:BAAALAADCgcIBwAAAA==.',['Ло']='Логнор:BAAALAAECgQIBAAAAA==.Лоуран:BAAALAADCgQIBAAAAA==.',['Ме']='Метамарфа:BAAALAAECggIDgAAAA==.',['Ми']='Миньйон:BAAALAAFFAEIAgAAAA==.Мис:BAAALAAECgcIBwAAAA==.Мистерпиклз:BAAALAADCgYICAAAAA==.',['Мо']='Мокзала:BAAALAAFFAUIAgABLAAFFAYIBAAOAAAAAA==.Мощныйлук:BAAALAAECggICgAAAA==.',['Му']='Мураса:BAACLAAFFIEJAAIVAAMIxA/UGgDoAAAVAAMIxA/UGgDoAAAsAAQKgS4AAhUACAh7IIkUAPECABUACAh7IIkUAPECAAAA.',['Мё']='Мёрфи:BAAALAAECggICAAAAA==.',['На']='Найтиси:BAACLAAFFIEhAAIMAAYIniPJAQByAgAMAAYIniPJAQByAgAsAAQKgTEAAgwACAjtJrsAAJUDAAwACAjtJrsAAJUDAAAA.',['Не']='Немножко:BAABLAAECoEZAAMTAAgI8xRWEQCfAQATAAcIXBJWEQCfAQALAAYILRTEYACXAQABLAAFFAYIGQANAA4bAA==.',['Ни']='Нифалика:BAABLAAECoEjAAMRAAcIbxc1QgCpAQARAAcIyRQ1QgCpAQAWAAMIbxlBHADVAAAAAA==.',['Ну']='Нубохантик:BAABLAAECoEWAAMXAAYIrhYlDQCpAQAXAAYIGBMlDQCpAQAHAAYIhw/UogA6AQAAAA==.',['Ня']='Няшати:BAABLAAECoEhAAMSAAcIQhb/QwDJAQASAAcIQhb/QwDJAQANAAQI2wYX5gB9AAAAAA==.',['Об']='Обливиончик:BAABLAAECoEmAAIYAAgIshdHSAA5AgAYAAgIshdHSAA5AgAAAA==.',['Ок']='Оказия:BAAALAAECgYIBgAAAA==.',['Ор']='Оргазм:BAAALAAECgYIDAAAAA==.Орче:BAAALAAECggICAABLAAFFAYIGgAIACYXAA==.',['Па']='Паш:BAAALAAECgUIBgAAAA==.Пашок:BAAALAAECgQIBAAAAA==.',['Пи']='Пивазавр:BAAALAAECgYIEgAAAA==.Пивондриус:BAABLAAECoEXAAISAAcIog9+VQCJAQASAAcIog9+VQCJAQAAAA==.',['По']='Подлыйгоблин:BAABLAAECoEWAAIZAAYIrh3KIgDkAQAZAAYIrh3KIgDkAQABLAAFFAIICQAEAKMcAA==.',['Пр']='Прокси:BAABLAAECoEXAAIaAAgIrB3iHQATAgAaAAgIrB3iHQATAgABLAAFFAMICwAMAPAjAA==.',['Ра']='Рада:BAAALAADCggIDgAAAA==.Раульрамзес:BAAALAAECgEIAQAAAA==.Рахольчик:BAAALAAECgQIBwAAAA==.',['Ре']='Реван:BAAALAAECgIIAgAAAA==.Реег:BAABLAAECoEkAAINAAgIVRx0HgB7AgANAAgIVRx0HgB7AgAAAA==.Рекрутов:BAABLAAECoEeAAILAAYIBB2FTgDPAQALAAYIBB2FTgDPAQAAAA==.Ренкус:BAABLAAECoExAAIKAAgINhj7TAAxAgAKAAgINhj7TAAxAgAAAA==.Рея:BAAALAAECgIIAgABLAAECgYIEwAOAAAAAA==.',['Ру']='Румотамэ:BAAALAADCggIHAAAAA==.',['Са']='Сагукайо:BAAALAAECgIIAgAAAA==.',['Се']='Селестраза:BAABLAAECoEjAAIEAAgITxwnEABvAgAEAAgITxwnEABvAgAAAA==.',['Си']='Сильфхейм:BAAALAAFFAIIBAAAAA==.',['См']='Смертурион:BAAALAADCgMIAwAAAA==.',['Со']='Сольтушка:BAABLAAECoEuAAIKAAgItiL7GgDoAgAKAAgItiL7GgDoAgAAAA==.Сонч:BAAALAADCggICQAAAA==.',['Ст']='Старость:BAAALAAECgYIEwAAAA==.Стукнуведь:BAAALAADCgQIBAAAAA==.',['Та']='Талион:BAAALAADCgEIAQAAAA==.',['Тв']='Твойдед:BAAALAADCgYIBgAAAA==.',['Те']='Темногрив:BAABLAAECoEVAAIKAAYIMBvYZwDyAQAKAAYIMBvYZwDyAQAAAA==.Терависа:BAAALAADCggIDQAAAA==.Теруэль:BAAALAAECgYIEQAAAA==.Тессера:BAAALAADCggIBwAAAA==.',['То']='Тоомиганн:BAAALAAECgEIAQAAAA==.',['Тр']='Трупаед:BAAALAADCgcIDAAAAA==.',['Тт']='Ттшка:BAAALAAECggICAAAAA==.',['Ту']='Тунрида:BAAALAAECgYICQABLAAFFAIICQAEAKMcAA==.',['Тё']='Тёмочка:BAAALAADCgYIBgAAAA==.',['Фе']='Фейсилиус:BAAALAAFFAIIAgABLAAFFAgIJAAJAEMeAA==.Фенестра:BAAALAAECgMIBgAAAA==.',['Фл']='Флойх:BAAALAADCgUIBQAAAA==.',['Фр']='Фризея:BAAALAADCgYIAwAAAA==.',['Фу']='Футворг:BAAALAADCgcICAAAAA==.',['Хе']='Хединесея:BAAALAAECgYIBgABLAAECggIHwAbABQeAA==.Хеллесть:BAAALAAFFAYIBAAAAA==.Хеллиалл:BAABLAAECoF2AAIPAAgICCZwAAByAwAPAAgICCZwAAByAwABLAAFFAYIBAAOAAAAAA==.Хеллэльф:BAAALAADCgIIAgAAAA==.Хемофилия:BAAALAADCggIEAAAAA==.',['Хл']='Хладноножка:BAAALAADCgQIBAAAAA==.',['Хр']='Храноро:BAAALAAECgMIAwAAAA==.',['Че']='Чебаксар:BAAALAAECgYIDwAAAA==.',['Чи']='Чикаго:BAACLAAFFIEGAAIYAAIIKgndOwCLAAAYAAIIKgndOwCLAAAsAAQKgScAAhgACAjBGRBPACcCABgACAjBGRBPACcCAAAA.',['Чо']='Чорнобог:BAAALAAECgcIDQAAAA==.',['Чу']='Чухоня:BAAALAAFFAEIAQAAAA==.',['Ша']='Шако:BAAALAAECgIIAgAAAA==.Шахраш:BAAALAAECgYIDgAAAA==.',['Шт']='Штрохайм:BAAALAADCggIDAABLAAECggICgAOAAAAAA==.',['Шё']='Шёпотвремен:BAACLAAFFIEWAAIJAAYICRcNBwD3AQAJAAYICRcNBwD3AQAsAAQKgSsAAgkACAgeIV4TAAADAAkACAgeIV4TAAADAAAA.',['Эг']='Эгимон:BAAALAAECgYIEgABLAAECggILgAKALYiAA==.',['Эд']='Эдита:BAAALAAECgUIBAAAAA==.',['Эй']='Эйнхерий:BAAALAADCggIEAAAAA==.',['Эк']='Эклипсик:BAABLAAECoEvAAMXAAgIah42BACUAgAXAAgIah42BACUAgADAAcIcA7cVQBHAQAAAA==.Эксинн:BAAALAADCgMIAwABLAAECgMIBgAOAAAAAA==.',['Яш']='Яшшерка:BAAALAADCggIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end