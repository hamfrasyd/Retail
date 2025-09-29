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
 local lookup = {'Warrior-Protection','Paladin-Retribution','Shaman-Elemental','DemonHunter-Vengeance','DeathKnight-Frost','Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Affliction','Priest-Holy','Priest-Discipline','Warrior-Fury','Shaman-Restoration','DeathKnight-Unholy','Warlock-Destruction','Warlock-Demonology','Shaman-Enhancement','Rogue-Assassination','Paladin-Holy','Paladin-Protection','Druid-Feral','Druid-Balance','DemonHunter-Havoc','Hunter-Survival','Druid-Restoration','Monk-Windwalker','Mage-Arcane',}; local provider = {region='EU',realm='Дракономор',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аг']='Агропром:BAABLAAECoEcAAIBAAcIOyLgDwCVAgABAAcIOyLgDwCVAgAAAA==.',['Ае']='Аерлис:BAAALAADCgUIAgAAAA==.',['Ай']='Айдаборщ:BAAALAAECgcIBwAAAA==.Айникас:BAABLAAECoEUAAICAAYIOSMHQwBIAgACAAYIOSMHQwBIAgAAAA==.',['Ак']='Аксон:BAAALAAECgcIEQAAAA==.',['Ал']='Алазора:BAAALAAECgYIDQAAAA==.Алариус:BAAALAAECgYIBgAAAA==.Александр:BAAALAAECgMIAwAAAA==.Алинерия:BAAALAAECgYIEQAAAA==.Аллатэя:BAAALAADCggIEAAAAA==.Алмахант:BAAALAAECgYIDgAAAA==.',['Ам']='Аминадюэль:BAAALAAECgMIAwABLAAFFAQIDQADANoRAA==.',['Ан']='Аннавата:BAAALAAFFAIIAgAAAA==.Антиутер:BAAALAAECgIIAgABLAAECggILAAEAPUlAA==.',['Ап']='Апогелия:BAAALAADCgYIBgABLAAECgYIFQAFAAoeAA==.',['Ар']='Аргуснат:BAAALAAECgUIBQABLAAFFAQIDQADANoRAA==.Аренианна:BAAALAADCggICAAAAA==.Аркадий:BAACLAAFFIEVAAMGAAYIACIDAQD7AQAGAAYIACIDAQD7AQAHAAMIwg6oDADbAAAsAAQKgSYAAwYACAhVJcAAAEoDAAYACAgmJMAAAEoDAAcACAjaILkIAAADAAAA.Артастутуэйт:BAAALAADCgcIBQAAAA==.Артёмиз:BAAALAAECgYIDAAAAA==.Арутиус:BAAALAADCggIFAAAAA==.Арфериус:BAAALAADCgQIBAAAAA==.',['Ат']='Атаракс:BAAALAAECgIIAgAAAA==.',['Ау']='Аурамен:BAAALAADCgEIAQAAAA==.',['Ба']='Бабэта:BAAALAADCgcICAABLAAECgYICgAIAAAAAA==.Балбеска:BAAALAADCgYIBgAAAA==.Баракиэль:BAAALAADCgcIBwAAAA==.',['Бе']='Бейбегилун:BAAALAADCggICAABLAAECggIJAAJAEceAA==.Бенлогос:BAAALAAECggIDgAAAA==.Березинский:BAABLAAECoEkAAMJAAgIRx4/KgB0AgAJAAgIRx4/KgB0AgAKAAEI5AsAAAAAAAAAAA==.',['Бл']='Блеклайт:BAAALAAECgYIBgAAAA==.Блекпинкк:BAAALAADCgcIBwAAAA==.Блэйден:BAAALAADCgIIAgAAAA==.',['Бо']='Богиняфрэйя:BAAALAADCgcIBwAAAA==.Бодрый:BAAALAAECggICAAAAA==.Бойсячел:BAAALAAECgYIEQABLAAECgcIEgAIAAAAAA==.Болчив:BAAALAAECgYIBgAAAA==.Больтазар:BAABLAAECoEVAAILAAcIUg0sDwChAQALAAcIUg0sDwChAQAAAA==.',['Бр']='Брилианна:BAABLAAECoEgAAMMAAgIjBZkJQA6AgAMAAgIjBZkJQA6AgANAAMIrQzBIwCMAAAAAA==.Бром:BAAALAADCgYIDAAAAA==.',['Бу']='Буллка:BAABLAAECoEXAAIOAAYIFxvfSwDXAQAOAAYIFxvfSwDXAQAAAA==.',['Ва']='Вайтвульф:BAAALAAECgMIAwABLAAECgYIFQAFAAoeAA==.Васера:BAAALAADCggICwAAAA==.',['Ве']='Веорра:BAAALAAECgEIAQAAAA==.Вессильра:BAAALAAECgYIEgAAAA==.',['Ви']='Виндшир:BAAALAADCgYIBgAAAA==.Виталийон:BAAALAAECggIAQAAAA==.',['Ву']='Вульзевилла:BAAALAADCgYIBgABLAAECgYIFQAFAAoeAA==.Вульфкнайт:BAABLAAECoEVAAIFAAYICh4kZQD3AQAFAAYICh4kZQD3AQAAAA==.',['Го']='Гозельтрон:BAAALAAECgcIDgAAAA==.Горныйволк:BAAALAADCgcIEQAAAA==.',['Гр']='Грассхоппер:BAAALAAECgYICgAAAA==.Грехокот:BAAALAAECgYIDgAAAA==.Грибуся:BAAALAADCgcIEwAAAA==.Грэниэль:BAAALAAECgIIAgAAAA==.',['Да']='Дарникус:BAABLAAECoEgAAIBAAgIzCCJCAD7AgABAAgIzCCJCAD7AgAAAA==.',['Дв']='Двухстволкаа:BAAALAAECgcICAAAAA==.',['Де']='Дезерти:BAABLAAECoEaAAIJAAgIEB7aHAC5AgAJAAgIEB7aHAC5AgAAAA==.Держись:BAAALAADCggIFgAAAA==.Дерокрас:BAACLAAFFIENAAIDAAQI2hEKCwBLAQADAAQI2hEKCwBLAQAsAAQKgSQAAwMACAjlGz8cAJ0CAAMACAjlGz8cAJ0CAA8AAgg6BGUHAT0AAAAA.',['Дж']='Джастдруид:BAAALAADCgcIBwABLAAECggIJAAJAEceAA==.Джей:BAAALAADCggIDwAAAA==.Джеки:BAABLAAECoEZAAIQAAYIXhakHQC2AQAQAAYIXhakHQC2AQAAAA==.Джиниу:BAAALAAECggICwAAAA==.Джокерша:BAAALAAECgYIBwAAAA==.Джонникеш:BAAALAADCgcIBwAAAA==.Джорджия:BAAALAADCggIDQAAAA==.',['Ди']='Дикэ:BAABLAAECoEWAAIRAAgIgAXJmQD/AAARAAgIgAXJmQD/AAAAAA==.Диллиана:BAAALAAECgMIBQAAAA==.Димасикк:BAAALAADCggIIQAAAA==.',['До']='Доктордруу:BAAALAADCgMIBAABLAAECggIKQABAAMXAA==.Донкихот:BAAALAADCgYIBgAAAA==.Дооротея:BAAALAAECgYIDAAAAA==.',['Др']='Драгур:BAAALAAECgUICgAAAA==.Дратанг:BAAALAAECgQIBwAAAA==.',['Дэ']='Дэнаа:BAABLAAECoEsAAQSAAgIMyRLEABiAgASAAYImSRLEABiAgARAAYI9SAaSwDgAQALAAII4haQKwB3AAAAAA==.',['Дя']='Дядяэл:BAABLAAECoEsAAIEAAgI9SX8AQBXAwAEAAgI9SX8AQBXAwAAAA==.',['Ег']='Егурец:BAAALAADCgMIAwABLAAECggIBgAIAAAAAA==.',['Еж']='Ежихоголовая:BAAALAADCggIEgAAAA==.',['Ех']='Ех:BAAALAADCgMIAwAAAA==.',['За']='Заназил:BAACLAAFFIEFAAITAAIImhkqBACrAAATAAIImhkqBACrAAAsAAQKgR8AAhMACAilHHkFALECABMACAilHHkFALECAAAA.Защищайкин:BAABLAAECoEpAAIBAAgIAxedIgDrAQABAAgIAxedIgDrAQAAAA==.',['Зд']='Здоровенный:BAAALAAECgYICQAAAA==.',['Зи']='Зианджа:BAAALAAECgIIBQAAAA==.',['Зл']='Златтка:BAAALAAECgYIDwAAAA==.',['Зу']='Зумлош:BAAALAADCggIEQAAAA==.',['Ил']='Иллидрун:BAAALAAECgMIAwAAAA==.Иллэрия:BAAALAADCggIEwAAAA==.Илрондор:BAAALAADCggICAAAAA==.',['Им']='Имфераэль:BAABLAAECoEfAAICAAcIhRr2UgAbAgACAAcIhRr2UgAbAgAAAA==.Имферион:BAAALAADCggICgAAAA==.',['Ин']='Инестра:BAABLAAECoEdAAIUAAYIJhVOMQCSAQAUAAYIJhVOMQCSAQABLAAECgYIKgAKALceAA==.Инзорн:BAAALAADCggICAAAAA==.Инфра:BAAALAADCgIIAgAAAA==.Инфрагилис:BAABLAAECoEhAAQVAAgI2xeTGQAWAgAVAAYICh+TGQAWAgACAAYIsAxz4AAFAQAWAAEI7hwAAAAAAAAAAA==.',['Ир']='Ириана:BAAALAAECggIEAAAAA==.',['Ис']='Исфат:BAAALAADCgcICAAAAA==.',['Ка']='Кайймира:BAAALAADCggIDwAAAA==.Кайэна:BAAALAADCgMIAwAAAA==.Камерамен:BAAALAAECgEIAQAAAA==.Карамбут:BAAALAAECgYIEgAAAA==.Карноши:BAAALAAECgYICAAAAA==.Картманот:BAAALAAECgYIDgAAAA==.Картьебугати:BAAALAAECgYIBgAAAA==.Катэш:BAABLAAECoEXAAICAAcIfwQZ2QAVAQACAAcIfwQZ2QAVAQAAAA==.Катёнка:BAAALAADCgQIBAAAAA==.Кашивар:BAAALAAECgYIDAAAAA==.',['Ке']='Кейлетт:BAAALAADCggICAAAAA==.Кеничко:BAAALAAECggIAwAAAA==.Кефирчиг:BAAALAAECgEIAQABLAAECggIKQABAAMXAA==.Кефрон:BAAALAAECgcIEwAAAA==.',['Ки']='Кидкити:BAAALAADCggICAAAAA==.Киеши:BAAALAADCgQIBAAAAA==.',['Кл']='Клёпа:BAAALAADCgYICgABLAAECgYIFQAFAAoeAA==.',['Ко']='Който:BAAALAAECggICAAAAA==.Коррислия:BAABLAAECoEaAAIVAAcIhCDaDACTAgAVAAcIhCDaDACTAgAAAA==.Кортес:BAABLAAECoEdAAIJAAgIgg5HbwChAQAJAAgIgg5HbwChAQAAAA==.Котозавр:BAABLAAECoEZAAIXAAcI5BxvDQBTAgAXAAcI5BxvDQBTAgAAAA==.',['Кр']='Креавар:BAAALAADCggICAABLAAECgYIFQASAPAiAA==.Кринжуль:BAAALAADCggIDgABLAAECgcIGQAXAOQcAA==.Кротслеп:BAAALAAECgUIBQAAAA==.Круглогадя:BAAALAAECggICgAAAA==.Крускор:BAABLAAECoEYAAIBAAYIFh9LHQATAgABAAYIFh9LHQATAgABLAAFFAIIAgAIAAAAAA==.',['Кс']='Ксенара:BAABLAAECoEiAAISAAcIvhuxHAD5AQASAAcIvhuxHAD5AQAAAA==.',['Кт']='Ктхула:BAAALAAECgYIBgAAAA==.',['Ку']='Куанарин:BAAALAAECgYIDAAAAA==.Кубинус:BAAALAAECggICAAAAA==.',['Кы']='Кылликанзера:BAAALAADCgEIAQAAAA==.',['Ла']='Лакрю:BAAALAAECgcICgAAAA==.Ластралия:BAAALAADCggIFwAAAA==.Латарм:BAAALAADCgUIBQAAAA==.',['Ле']='Лейката:BAABLAAFFIEHAAIMAAIIog64IwCSAAAMAAIIog64IwCSAAABLAAFFAUIEAAMAGUQAA==.Летучийсапог:BAAALAAECgEIAQAAAA==.',['Ли']='Лиджети:BAAALAADCggICAABLAAECgYIBgAIAAAAAA==.Линеля:BAAALAAECgIIAgAAAA==.Литавия:BAAALAAECgcIEQAAAA==.',['Ло']='Локерт:BAABLAAECoEVAAISAAYI8CKrEQBTAgASAAYI8CKrEQBTAgAAAA==.',['Лу']='Лугажуй:BAABLAAECoEoAAIXAAgIzxqhEQAQAgAXAAgIzxqhEQAQAgAAAA==.',['Лы']='Лысак:BAAALAADCgIIAgAAAA==.',['Лэ']='Лэттиси:BAAALAAECgEIAQAAAA==.',['Лю']='Люблю:BAAALAAECgYIBwAAAA==.',['Ма']='Маати:BAAALAAECgYIDAAAAA==.Магкликер:BAAALAAECgYICgAAAA==.Мадолориан:BAAALAAECgYICAABLAAFFAQIDQADANoRAA==.Малиас:BAAALAAECgYICQAAAA==.Манриса:BAAALAADCgMIAwABLAAECgYIEAAIAAAAAA==.Маринако:BAAALAADCgUIBQAAAA==.Марияджей:BAAALAADCgcIBwAAAA==.Махвальт:BAAALAAECgcIEQAAAA==.',['Ме']='Мексиканка:BAAALAADCgEIAQAAAA==.Мелантиос:BAAALAADCggICAAAAA==.Мелькорис:BAABLAAECoElAAIUAAgIKBtVEQCKAgAUAAgIKBtVEQCKAgAAAA==.',['Ми']='Микури:BAAALAAECgYIDgAAAA==.Минеррва:BAAALAAECgIIAgAAAA==.Миссджеей:BAAALAADCggIDQAAAA==.',['Мо']='Можетпиво:BAAALAADCgEIAQAAAA==.Мойэльф:BAAALAAECgYIEgAAAA==.Молдрен:BAAALAADCggIDAAAAA==.Мордром:BAAALAADCgcIBwAAAA==.Мошер:BAAALAAECgEIAQAAAA==.',['Му']='Муракки:BAAALAAECgYIEgAAAA==.Муфлоняка:BAAALAAECgUIBQAAAA==.',['Мы']='Мышка:BAAALAADCgYIBgAAAA==.',['Мэ']='Мэйдзин:BAAALAADCggIFwAAAA==.Мэлонис:BAAALAAECgUICQAAAA==.',['На']='Найка:BAAALAADCgIIAgAAAA==.Нанаська:BAABLAAECoEXAAIYAAgIzh16EgCxAgAYAAgIzh16EgCxAgAAAA==.Начальникэ:BAAALAADCgMIAwAAAA==.',['Не']='Неверлорд:BAAALAADCgUICAAAAA==.Негинд:BAABLAAECoEhAAIFAAcICw4GxwBJAQAFAAcICw4GxwBJAQAAAA==.Нейронка:BAAALAAECgYICQAAAA==.Некоренна:BAAALAADCgcICQAAAA==.Некромантиус:BAAALAAECgUICAAAAA==.Непеня:BAABLAAECoEpAAIXAAgIsx/QBwC+AgAXAAgIsx/QBwC+AgAAAA==.',['Ни']='Николай:BAAALAADCgcIBwAAAA==.Нимезида:BAAALAAFFAIIAgAAAA==.',['Но']='Ноулимит:BAAALAAFFAIIAgAAAA==.Ноури:BAABLAAECoEpAAIZAAgIkhwVMwBqAgAZAAgIkhwVMwBqAgAAAA==.',['Нэ']='Нэсиха:BAAALAADCggICAAAAA==.',['Он']='Онзи:BAABLAAECoEaAAIaAAcIEBHSCgDWAQAaAAcIEBHSCgDWAQAAAA==.',['Ор']='Оркварлок:BAAALAADCggICAAAAA==.Оругец:BAAALAADCgEIAQAAAA==.',['Оц']='Оципиталлис:BAAALAAECgYIBwAAAA==.',['Пе']='Педраса:BAAALAAECgYIBgAAAA==.Пеппилота:BAAALAADCggIDQAAAA==.Перетти:BAAALAAECgQIBAABLAAECgYIBgAIAAAAAA==.',['Пи']='Пиплик:BAAALAADCgcIBQAAAA==.Писюныш:BAAALAAECgIIAwAAAA==.',['По']='Поло:BAABLAAECoEeAAMbAAgInBaEPwCrAQAbAAcInRaEPwCrAQAYAAEIrgetlgAkAAAAAA==.Поражений:BAAALAAECgYIBwAAAA==.Похметолог:BAABLAAECoEVAAICAAcI3QuRnACFAQACAAcI3QuRnACFAQAAAA==.',['Пр']='Приемыш:BAAALAAECgQIBQAAAA==.Прю:BAAALAAECgcIEQAAAA==.',['Ра']='Радиэль:BAABLAAECoEbAAMKAAcI9Aa3ZwAKAQAKAAcI9Aa3ZwAKAQAJAAIItwMtFAE2AAAAAA==.Раймэй:BAAALAAECgYICwAAAA==.Ранден:BAABLAAECoEoAAIJAAcIVRk3hQBzAQAJAAcIVRk3hQBzAQAAAA==.',['Ри']='Риверблейд:BAAALAADCgYICAABLAAECgYIFQAFAAoeAA==.Ринзлок:BAAALAAECgYIBgAAAA==.Рипчик:BAAALAAECgQIBAAAAA==.',['Ро']='Рогуэра:BAAALAAECgQIBAAAAA==.Ронин:BAAALAADCgYIBwAAAA==.',['Ру']='Рунаар:BAABLAAECoEhAAQVAAcINRHjLQCJAQAVAAcINRHjLQCJAQACAAEIZAXOSQEmAAAWAAYIBBgAAAAAAAAAAA==.Рустем:BAAALAAECgMIAwAAAA==.',['Са']='Самантра:BAABLAAECoEcAAMFAAcIKRSYoQCGAQAFAAcIIw+YoQCGAQAQAAIIpx3EPQC8AAAAAA==.Самохил:BAAALAAECgYIDAAAAA==.Сапнаполгода:BAAALAAECggICQAAAA==.Сафирон:BAAALAAECgEIAQAAAA==.Саципус:BAAALAADCggICAAAAA==.',['Св']='Светомолот:BAAALAADCggIEAAAAA==.',['Се']='Серафимика:BAAALAADCgYIBgABLAAECgYIFQAFAAoeAA==.Сердцеежа:BAAALAAECgMIAwAAAA==.Сетилайн:BAAALAADCgYIBgAAAA==.',['Си']='Сигурдия:BAAALAAECgEIAQAAAA==.Сиквенс:BAAALAAECgYICQAAAA==.Силендра:BAAALAADCggIHAAAAA==.Сиунэ:BAAALAAECgYIBgAAAA==.',['Ск']='Скандинавиц:BAAALAADCgcIBwABLAAECggIKQABAAMXAA==.Скарпирити:BAAALAADCgEIAgAAAA==.Скочь:BAAALAAECgMIAwAAAA==.',['Сл']='Следкопыт:BAABLAAECoEsAAIJAAgI7yC7GADRAgAJAAgI7yC7GADRAgAAAA==.Слешвен:BAABLAAECoEaAAIKAAYI4hLXUQBVAQAKAAYI4hLXUQBVAQAAAA==.',['Со']='Сонарес:BAACLAAFFIELAAICAAIIex9CGQC9AAACAAIIex9CGQC9AAAsAAQKgS4AAgIACAgmI8YaAO0CAAIACAgmI8YaAO0CAAAA.',['Сп']='Спайсигёрл:BAAALAAECgEIAQABLAAECgYICgAIAAAAAA==.',['Ст']='Стасик:BAAALAADCggICAAAAA==.',['Су']='Сурлан:BAAALAADCggICAABLAAECgcIIQAVADURAA==.',['Та']='Тайлуна:BAAALAAECgYIBgAAAA==.Талариус:BAAALAAECgMIAwAAAA==.Тарасарн:BAAALAADCgIIAgAAAA==.Тарилисса:BAABLAAECoEaAAMbAAYImR5hKwAIAgAbAAYImR5hKwAIAgAYAAMIOwtieACAAAAAAA==.Таунсантрос:BAAALAAECgMIAwABLAAFFAQIDQADANoRAA==.Ташра:BAAALAADCgIIAgAAAA==.',['Те']='Тека:BAABLAAECoEXAAIDAAcIPhHQSQCzAQADAAcIPhHQSQCzAQAAAA==.Телана:BAABLAAECoEpAAIWAAgIiyBRBwDpAgAWAAgIiyBRBwDpAgAAAA==.Темпорус:BAAALAADCggICAAAAA==.Тестиада:BAABLAAECoEbAAIJAAYIaw1epwAxAQAJAAYIaw1epwAxAQAAAA==.',['Ти']='Тибблдорф:BAAALAADCgIIAgAAAA==.Тизвиш:BAAALAADCggIHwAAAA==.Тииса:BAABLAAECoEXAAIYAAcIdw9cPgCMAQAYAAcIdw9cPgCMAQAAAA==.Тинирия:BAAALAADCggICAAAAA==.',['То']='Тотор:BAAALAAECgMIBgAAAA==.',['Тр']='Трейгар:BAAALAAECgQIBQAAAA==.',['Уд']='Удирша:BAABLAAECoEuAAMbAAgITxpcIwAxAgAbAAgITxpcIwAxAgAYAAII3QoSgwBZAAAAAA==.',['Уж']='Ужасныйволк:BAAALAADCggICAAAAA==.',['Уи']='Уивер:BAAALAADCgcIDQAAAA==.',['Уо']='Уолтерик:BAACLAAFFIEGAAICAAIIXRD+NgCUAAACAAIIXRD+NgCUAAAsAAQKgSsAAgIACAjfHRsoAKwCAAIACAjfHRsoAKwCAAAA.',['Ур']='Урель:BAABLAAECoEmAAIHAAgIqxkbFgBeAgAHAAgIqxkbFgBeAgAAAA==.',['Фа']='Фанфукрик:BAAALAADCggIDwAAAA==.Фарес:BAAALAAECgYIBgAAAA==.Фаррула:BAAALAAECgcIEQAAAA==.',['Фе']='Феннипей:BAAALAADCggIDgABLAAECgYIBgAIAAAAAA==.',['Фо']='Форсфул:BAAALAAECgIIAwAAAA==.',['Ха']='Хартандер:BAAALAAECgYIBgAAAA==.',['Хе']='Хеночка:BAAALAADCggICAAAAA==.',['Хи']='Хидзи:BAAALAAECgYIDwAAAA==.Хилвэр:BAABLAAECoElAAMSAAgI6R1OCQC2AgASAAgIWx1OCQC2AgARAAIISRxKsgCoAAAAAA==.Хисара:BAAALAAECggICAAAAA==.Хитари:BAACLAAFFIEMAAIcAAQIJBPgBQACAQAcAAQIJBPgBQACAQAsAAQKgSYAAhwACAhLIy4FACsDABwACAhLIy4FACsDAAAA.',['Хо']='Хоук:BAAALAADCggICAAAAA==.',['Хэ']='Хэйча:BAAALAAECggICAAAAA==.',['Ци']='Цилистина:BAABLAAECoEUAAIdAAcI9wrZdQCGAQAdAAcI9wrZdQCGAQABLAAECggICwAIAAAAAA==.',['Цу']='Цунаёши:BAAALAADCgQIBAAAAA==.',['Ча']='Чанжуньсуй:BAAALAADCggIEAAAAA==.',['Чж']='Чжицзин:BAAALAADCgIIAgABLAAECgcIHAAFACkUAA==.',['Чи']='Чиллуф:BAABLAAECoEWAAIbAAcINhBpTQB0AQAbAAcINhBpTQB0AQAAAA==.Читаря:BAAALAADCgMIAwAAAA==.Чихэру:BAAALAAECgYIBgAAAA==.',['Чо']='Чос:BAAALAAECgcIEAAAAA==.',['Чю']='Чюда:BAABLAAECoErAAMPAAgIFBbwRADnAQAPAAgIFBbwRADnAQATAAEIngFQJgAjAAAAAA==.',['Ша']='Шалдрис:BAAALAAECgIIAgAAAA==.Шальнаящама:BAABLAAECoEpAAMDAAgIBR++FgDGAgADAAgIBR++FgDGAgAPAAIIBgnbAgFEAAAAAA==.Шамике:BAAALAADCggICAABLAAFFAUIEAAMAGUQAA==.Шамисвами:BAAALAAECgYIEQAAAA==.Шамом:BAAALAADCggICAAAAA==.Шапка:BAAALAAECgYIDgAAAA==.',['Ше']='Шенлана:BAAALAADCgcIBwAAAA==.',['Ши']='Шишь:BAAALAAECgYIEAAAAA==.',['Шу']='Шуна:BAABLAAECoEWAAIPAAgI0QpsjAAsAQAPAAgI0QpsjAAsAQAAAA==.',['Эв']='Эверлост:BAAALAAECgQIBAAAAA==.',['Эк']='Эклиптик:BAAALAADCgcICgAAAA==.',['Эл']='Элдрагоса:BAACLAAFFIEGAAIJAAIIBhMZKgCRAAAJAAIIBhMZKgCRAAAsAAQKgSIAAgkACAjtIA0iAJwCAAkACAjtIA0iAJwCAAAA.Элизабелла:BAAALAADCgIIAgAAAA==.Элураэль:BAAALAADCggICQAAAA==.Элфиш:BAABLAAECoEqAAIdAAgIQhNQTgD7AQAdAAgIQhNQTgD7AQAAAA==.',['Эм']='Эмптинэсс:BAABLAAECoEVAAIQAAgI7gh5JAB/AQAQAAgI7gh5JAB/AQAAAA==.',['Эр']='Эрнэтта:BAAALAAECgcIDwAAAA==.',['Эс']='Эсканор:BAAALAADCggIEAAAAA==.Эстэра:BAAALAAECgYIDAAAAA==.',['Эф']='Эффаэ:BAAALAAECgYIEQAAAA==.',['Юл']='Юлси:BAABLAAECoEUAAIPAAYIRA49rADrAAAPAAYIRA49rADrAAAAAA==.',['Юн']='Юнимас:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end