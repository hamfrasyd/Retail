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
 local lookup = {'Druid-Restoration','Hunter-Marksmanship','DeathKnight-Unholy','Priest-Holy','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Monk-Brewmaster','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Mage-Frost','Evoker-Devastation','Priest-Discipline','Warrior-Fury','Mage-Fire','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Paladin-Holy','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Hunter-Survival','Warrior-Protection','Warrior-Arms','Mage-Arcane','Druid-Guardian','DemonHunter-Vengeance',}; local provider = {region='EU',realm='ЧерныйШрам',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аб']='Абъюзер:BAAALAAECgYIBgAAAA==.',['Ав']='Авторитет:BAAALAAECgYIDgAAAA==.',['Ае']='Аелин:BAABLAAECoEmAAIBAAgIOyJzCQD4AgABAAgIOyJzCQD4AgAAAA==.',['Аз']='Азамагг:BAACLAAFFIEGAAICAAIIugrxIQB7AAACAAIIugrxIQB7AAAsAAQKgSEAAgIABwh7G+8nABsCAAIABwh7G+8nABsCAAAA.',['Аи']='Аилдозер:BAAALAAECgQIAgAAAA==.Аиса:BAAALAAECgIIAgAAAA==.',['Ай']='Айдвэйн:BAAALAAECggICAAAAA==.',['Ак']='Акена:BAAALAADCgcIBwAAAA==.',['Ал']='Алаявишня:BAAALAAECgYIBgAAAA==.Албедо:BAACLAAFFIEHAAIDAAMIZBicBAATAQADAAMIZBicBAATAQAsAAQKgSAAAgMACAhUJS4CAEQDAAMACAhUJS4CAEQDAAAA.Алитэя:BAACLAAFFIEIAAIEAAIIUB6qGwCiAAAEAAIIUB6qGwCiAAAsAAQKgSgAAgQABwhvIZAWAJwCAAQABwhvIZAWAJwCAAAA.Альбедоо:BAAALAADCgIIAgAAAA==.Альгуль:BAABLAAECoEWAAIFAAgIQQSyXgAMAQAFAAgIQQSyXgAMAQAAAA==.',['Ам']='Амарторион:BAAALAADCggIDgAAAA==.',['Ан']='Анахранист:BAAALAADCgcICwAAAA==.Андлонель:BAAALAADCggIDgAAAA==.',['Ап']='Апоне:BAAALAADCggIDAAAAA==.',['Ар']='Арба:BAAALAAECgIIAgAAAA==.Аристократка:BAAALAAECggIBQAAAA==.Арленто:BAAALAAECgYICgAAAA==.Арокс:BAAALAADCggICAAAAA==.Аронас:BAAALAAECgEIAQAAAA==.Артасх:BAAALAAECggICgAAAA==.',['Ас']='Аскагат:BAAALAAECgQIBQAAAA==.Ассонанс:BAAALAADCgUICAAAAA==.Асфоделика:BAAALAADCggIDQAAAA==.',['Ат']='Атомик:BAAALAADCggIEAAAAA==.',['Ау']='Аурел:BAAALAADCgEIAQAAAA==.',['Аш']='Ашер:BAAALAAECggICwABLAAFFAQIBgAGAOgPAA==.',['Ба']='Бабадемон:BAAALAAECgEIAQABLAAFFAMICgAHAJQTAA==.Базилс:BAAALAADCgEIAQAAAA==.Батбат:BAAALAADCgMIAwAAAA==.Баття:BAAALAAECgYIDAAAAA==.Бахус:BAAALAAECgEIAQAAAA==.',['Бе']='Бейнен:BAAALAAECgYIBgAAAA==.Бесоватный:BAAALAADCgIIAgAAAA==.Бесточечно:BAABLAAECoEZAAIEAAgITBUAMQD8AQAEAAgITBUAMQD8AQAAAA==.',['Би']='Бигмакич:BAAALAAECgMIAwAAAA==.Бикко:BAABLAAECoEfAAIEAAgIvx9UFgCeAgAEAAgIvx9UFgCeAgAAAA==.Биочифир:BAAALAAECgYIDAAAAA==.',['Бо']='Боблик:BAAALAAECgYIBgAAAA==.Болтпро:BAAALAAECgYICQAAAA==.',['Бр']='Бриз:BAAALAAECggICwAAAA==.Бринна:BAAALAAECggIDwAAAA==.Бровидеда:BAAALAADCgQIBAAAAA==.Брфф:BAABLAAECoEoAAIIAAgIuBpyDAB5AgAIAAgIuBpyDAB5AgABLAAFFAUIEgAJAH0TAA==.',['Бу']='Бурбон:BAACLAAFFIEKAAIKAAMIdCSDDwA7AQAKAAMIdCSDDwA7AQAsAAQKgR8AAwoACAi1Je8OACcDAAoACAi1Je8OACcDAAsAAwiTE4AuALMAAAAA.Бурбонд:BAAALAADCggICAABLAAFFAMICgAKAHQkAA==.Бурбэн:BAAALAAECggIEwABLAAFFAMICgAKAHQkAA==.',['Бы']='Бычказавр:BAABLAAECoEWAAIMAAcIvB0GDwA+AgAMAAcIvB0GDwA+AgAAAA==.',['Бэ']='Бэдман:BAAALAADCgQIBQAAAA==.',['Ва']='Вайлинкс:BAABLAAECoEqAAIFAAgIKRQ0KgAQAgAFAAgIKRQ0KgAQAgAAAA==.Вайпупали:BAAALAAECgcIBgAAAA==.Ванястрела:BAAALAADCggICAABLAAFFAMICgAKAHQkAA==.Вараронкс:BAAALAAECgQIBQABLAAECgYIEAANAAAAAA==.Вареныйбычок:BAAALAADCgQIBAAAAA==.Васильок:BAAALAADCgQIBAAAAA==.',['Ве']='Великийпал:BAAALAAECgUICQAAAA==.Вечнодум:BAABLAAECoEVAAIOAAcIEgwLswBdAQAOAAcIEgwLswBdAQAAAA==.',['Ви']='Вианда:BAAALAAECgIIAgAAAA==.Вивисектор:BAAALAADCggICAAAAA==.Винлиден:BAAALAADCgYIFgAAAA==.Винтерфел:BAAALAAECgMIBQAAAA==.',['Вл']='Влажка:BAAALAADCggICAAAAA==.Влатали:BAAALAADCggICAAAAA==.',['Во']='Водочница:BAABLAAECoEfAAIJAAcItRdKRADpAQAJAAcItRdKRADpAQAAAA==.Волосатыйдяд:BAAALAADCgYIBwAAAA==.Вомачка:BAAALAAECggIBgAAAA==.Вонамор:BAAALAAECgEIAQAAAA==.',['Вр']='Врагславян:BAAALAAECggIAgAAAA==.',['Вс']='Вспинуножик:BAAALAADCgcICAAAAA==.',['Вэ']='Вэйди:BAAALAAFFAIIAgAAAA==.',['Га']='Гаальвис:BAAALAAECggICAAAAA==.Галлиано:BAAALAADCggIDQAAAA==.Ганнерх:BAAALAAECggICAABLAAFFAMICgAHAJQTAA==.Гасслин:BAABLAAECoEtAAIGAAgIxB3HKgCPAgAGAAgIxB3HKgCPAgAAAA==.',['Ге']='Гервулф:BAABLAAECoEfAAIPAAcIxRmpUwDmAQAPAAcIxRmpUwDmAQAAAA==.Герчат:BAAALAAECggICAAAAA==.',['Гр']='Граната:BAAALAAECgUIBQABLAAECgcIGAAOAP4cAA==.Гримбальд:BAAALAADCgQIBAAAAA==.',['Гу']='Гулидан:BAAALAAECgEIAQAAAA==.',['Да']='Дайсисю:BAAALAAECggICAAAAA==.Далас:BAAALAAECgcIEAAAAA==.Данталиа:BAAALAADCggIBwAAAA==.Даридобро:BAABLAAECoEUAAIQAAcIKBWEJQDTAQAQAAcIKBWEJQDTAQAAAA==.Даюмракстоим:BAAALAADCgcIBwAAAA==.',['Де']='Демлун:BAABLAAECoEbAAIGAAYI+BITjgB8AQAGAAYI+BITjgB8AQAAAA==.Держивщи:BAABLAAECoEjAAMEAAcILApgaQAaAQAEAAcILApgaQAaAQAFAAEIvQSYkAAlAAAAAA==.Держисвет:BAAALAADCggIIAABLAAECgcIIwAEACwKAA==.Детстроук:BAABLAAECoEXAAIPAAgICxq4TwDxAQAPAAgICxq4TwDxAQAAAA==.',['Дж']='Джаганат:BAAALAADCggICAAAAA==.Джайнт:BAAALAADCgYIBgAAAA==.Джиммирейнор:BAAALAADCgEIAQAAAA==.Джоахим:BAACLAAFFIEHAAIPAAMIChvzJACZAAAPAAMIChvzJACZAAAsAAQKgScAAg8ACAiJIUkZAM0CAA8ACAiJIUkZAM0CAAAA.',['Ди']='Диаблох:BAAALAAECgUIBQAAAA==.Дивипи:BAAALAAECggICwAAAA==.',['Дм']='Дметриос:BAAALAADCgcICwAAAA==.',['До']='Доллар:BAAALAAECgYICgAAAA==.Долрун:BAAALAADCggICAAAAA==.Дорн:BAAALAADCggICAAAAA==.',['Др']='Дракаронкс:BAAALAAECgYIEAAAAA==.Дриадея:BAAALAAECgYICQABLAAECggIHAARABIPAA==.Дрогаш:BAAALAADCgcIBwABLAAFFAMICQAJAFUSAA==.Дроухарт:BAABLAAECoEYAAISAAYIRB+1BwATAgASAAYIRB+1BwATAgAAAA==.Друидка:BAAALAADCggICgAAAA==.Друидло:BAAALAAECgYIEQABLAAECggIJwAOAJAhAA==.',['Ду']='Душку:BAAALAAECgUIDQAAAA==.',['Дэ']='Дэксич:BAAALAADCggICQAAAA==.Дэлой:BAAALAAECgYIBgAAAA==.Дэцолог:BAAALAADCgEIAQAAAA==.',['Дё']='Дёминг:BAAALAADCggICAAAAA==.',['Ел']='Елань:BAAALAAECgEIAQAAAA==.',['Ем']='Емели:BAAALAAECgMIAwAAAA==.Емки:BAAALAAECgcIEQAAAA==.Еммел:BAAALAADCggICAAAAA==.',['Жд']='Ждиа:BAAALAADCgcIBwAAAA==.',['Жи']='Жигулевский:BAAALAAECgYIDQAAAA==.',['Жр']='Жрицальвица:BAAALAAECgYIBwAAAA==.',['Жу']='Жушка:BAAALAAECgEIAQABLAAECgcIIwAEACwKAA==.',['За']='Завран:BAAALAAECgcIBwAAAA==.',['Зе']='Зекхан:BAAALAADCgUIBQAAAA==.Зефара:BAAALAAECgYIBwAAAA==.',['Зо']='Золоман:BAABLAAECoEWAAITAAcIMBN3ZgCHAQATAAcIMBN3ZgCHAQAAAA==.Золотойбой:BAAALAADCgcICAAAAA==.',['Зу']='Зуба:BAAALAAECgYIBgAAAA==.Зубаскалл:BAAALAADCggICwAAAA==.',['Зэ']='Зэфирчик:BAABLAAECoEfAAIKAAgIJgsViwCtAQAKAAgIJgsViwCtAQAAAA==.',['Ив']='Ивеллиос:BAAALAAECgYIEwAAAA==.',['Иг']='Игрунья:BAABLAAECoEaAAMUAAcISA25CgBiAQAUAAcISAi5CgBiAQAQAAUIOw0+TQAOAQAAAA==.',['Ил']='Иллиинэль:BAAALAADCgEIAQAAAA==.',['Им']='Иммельшторм:BAAALAADCgYIBgAAAA==.',['Ин']='Инши:BAAALAAECgYIBgAAAA==.',['Иш']='Ишараджи:BAAALAADCgcICwAAAA==.',['Йо']='Йолаанди:BAABLAAECoEeAAIQAAcI0SFtDQCrAgAQAAcI0SFtDQCrAgAAAA==.Йордлс:BAAALAAECgQIBQAAAA==.',['Ка']='Кайк:BAABLAAECoEhAAITAAcIfAwRaQCAAQATAAcIfAwRaQCAAQAAAA==.Кайфушка:BAAALAAECgcIDgAAAA==.Калезгос:BAAALAADCggIDAAAAA==.Камазкала:BAABLAAECoEUAAIMAAcIBB73DABhAgAMAAcIBB73DABhAgAAAA==.Камелия:BAAALAADCggICgAAAA==.Капеллан:BAAALAAECggICAAAAA==.Караумка:BAABLAAECoEWAAIVAAcIQxV6FQDdAQAVAAcIQxV6FQDdAQAAAA==.Карианочка:BAAALAAECggICQAAAA==.Каёни:BAAALAAFFAIIBAAAAA==.',['Кв']='Квадробр:BAAALAADCggICAAAAA==.',['Ке']='Кекл:BAAALAAECgEIAQABLAAFFAIICAAPAHgaAA==.Кералир:BAAALAAECgIIAgAAAA==.Кериган:BAAALAADCgYIBgAAAA==.',['Ки']='Кикей:BAAALAADCggIDgAAAA==.Кингдрагон:BAAALAADCgYIBgAAAA==.Киоя:BAAALAADCggIFQAAAA==.',['Кн']='Кнама:BAABLAAECoEYAAIPAAgIWAOb4QCmAAAPAAgIWAOb4QCmAAAAAA==.',['Ко']='Коварныйкусь:BAAALAAECgMIAwAAAA==.Космическая:BAAALAAECgIIAgAAAA==.',['Кр']='Красняш:BAABLAAECoEiAAIQAAcIJh+RFQBPAgAQAAcIJh+RFQBPAgAAAA==.Крип:BAAALAAECggIBgAAAA==.Кружкапота:BAAALAAECgMIAwAAAA==.Крушимир:BAAALAAECgEIAQAAAA==.',['Кс']='Ксалотат:BAAALAADCgIIAgAAAA==.',['Ку']='Кузенвов:BAAALAADCggICAAAAA==.Куркума:BAAALAADCgIIAgAAAA==.Курящийпро:BAAALAAFFAIIBAAAAA==.',['Къ']='Къюби:BAAALAAECgUIBAAAAA==.',['Ла']='Лавандоблеба:BAAALAADCgYIBgAAAA==.Лайтсмит:BAAALAADCgUIBQAAAA==.Ламаэ:BAACLAAFFIEQAAMWAAUIyh64BQA/AQAWAAMI3iS4BQA/AQAXAAIIrBXFCgCmAAAsAAQKgSgAAxYACAhTJfoBAFsDABYACAhTJfoBAFsDABcABAgFFvIpABIBAAAA.Ланиспорт:BAAALAADCgMIAwAAAA==.',['Ле']='Лейфх:BAAALAAECgQIBAAAAA==.Леонус:BAAALAAECggIEAAAAA==.Леопарддва:BAAALAADCgcIDAAAAA==.Леримель:BAAALAADCgUIAgAAAA==.',['Ли']='Либерал:BAACLAAFFIEHAAIYAAMIBhOUBQDeAAAYAAMIBhOUBQDeAAAsAAQKgRkAAhgACAgyHrwKAKQCABgACAgyHrwKAKQCAAAA.Лисанлей:BAAALAAECggIEgAAAA==.Литий:BAAALAADCggIEgAAAA==.',['Ло']='Ловиторпеду:BAAALAADCgcICgAAAA==.Логон:BAAALAAECgUICQAAAA==.Лордлёд:BAAALAADCggIFgAAAA==.Лордпафос:BAAALAAECgYIDgAAAA==.',['Лу']='Луносвет:BAAALAAECgEIAQAAAA==.',['Лю']='Люйкасу:BAAALAADCggIEAAAAA==.Лютиен:BAAALAAECgYIDwAAAA==.Лютина:BAAALAAECgYIBgAAAA==.',['Лё']='Лёшик:BAAALAAECggIDAAAAA==.',['Ма']='Маазик:BAAALAAECggICAAAAA==.Мадлайт:BAAALAAECgIIAwAAAA==.Майяноулав:BAAALAADCggIDgAAAA==.Макгонагл:BAAALAADCgYIBgAAAA==.Малейн:BAACLAAFFIEHAAIPAAMIlA6IIACkAAAPAAMIlA6IIACkAAAsAAQKgSQAAg8ACAjAH80oAHoCAA8ACAjAH80oAHoCAAAA.Маллибу:BAAALAAECggIDQAAAA==.Мальвиви:BAAALAAECgEIAQAAAA==.Маромаса:BAABLAAECoEcAAIKAAYICh+7XQAIAgAKAAYICh+7XQAIAgAAAA==.Мароша:BAAALAAFFAIIBAAAAA==.Марфушка:BAAALAAECgMIAwAAAA==.Матрада:BAAALAADCgcIDAAAAA==.',['Мд']='Мджит:BAACLAAFFIEIAAIHAAMIlROoCgDvAAAHAAMIlROoCgDvAAAsAAQKgSgAAgcACAgMIHkPANICAAcACAgMIHkPANICAAAA.',['Ме']='Мейер:BAACLAAFFIEFAAIGAAIINAl4OQCJAAAGAAIINAl4OQCJAAAsAAQKgR0AAgYACAi8HZ8mAKMCAAYACAi8HZ8mAKMCAAAA.Мейникс:BAACLAAFFIEHAAIFAAQIeh//BwB7AQAFAAQIeh//BwB7AQAsAAQKgRcAAgUACAgVJNEEAFIDAAUACAgVJNEEAFIDAAAA.Мекран:BAABLAAECoEZAAIOAAcIDg8BjwCeAQAOAAcIDg8BjwCeAQAAAA==.Мелемир:BAAALAAECgYIDAAAAA==.Мелиноя:BAABLAAECoEcAAIRAAgIEg/AIwDeAQARAAgIEg/AIwDeAQAAAA==.Мелифарро:BAAALAAECggICAAAAA==.Меломениа:BAAALAAECgYIEAAAAA==.Менрис:BAAALAADCgYIBQAAAA==.Мертвечино:BAAALAADCgIIAgAAAA==.Меснта:BAAALAADCgMIAwAAAA==.Мечтанец:BAAALAAECgYIDwAAAA==.',['Ми']='Миникол:BAAALAADCgIIAgAAAA==.Мисмунлайт:BAABLAAECoEbAAMZAAgIFhXeGwAEAgAZAAgIFhXeGwAEAgAOAAEI/QcQRQEuAAAAAA==.Митра:BAAALAADCgMIAQAAAA==.',['Мо']='Могуччи:BAAALAAECgYICwAAAA==.Монархсатору:BAAALAAECgcIDwAAAA==.Монахеня:BAAALAADCggIAwAAAA==.Монфрэди:BAABLAAECoEVAAIFAAcIGRWTNgDJAQAFAAcIGRWTNgDJAQAAAA==.Мортиз:BAAALAAECggIEAAAAA==.Моэндар:BAAALAAECgMIAwABLAAECgYICQANAAAAAA==.',['Му']='Муарен:BAAALAADCgIIAgAAAA==.Музыкант:BAAALAADCgcIBwAAAA==.Муррчачо:BAACLAAFFIEPAAIBAAMI/x8xCAAiAQABAAMI/x8xCAAiAQAsAAQKgTUAAgEACAiTJO0DADwDAAEACAiTJO0DADwDAAAA.Муунбиам:BAAALAADCggICQAAAA==.',['Мь']='Мьюта:BAABLAAECoEUAAIGAAgINRuTQQA1AgAGAAgINRuTQQA1AgAAAA==.',['Мя']='Мяула:BAAALAAECgQIBAAAAA==.',['На']='Намгала:BAAALAADCgIIAgAAAA==.Натризим:BAAALAAECggIEwAAAA==.',['Не']='Негля:BAAALAADCgIIAgAAAA==.Недовольний:BAAALAAECgYIBgAAAA==.Неиджи:BAABLAAECoEgAAITAAcIxBW8UwC+AQATAAcIxBW8UwC+AQAAAA==.Нейтирис:BAAALAADCggIDAAAAA==.Нелифер:BAABLAAECoEhAAIJAAcIKBZKXwCbAQAJAAcIKBZKXwCbAQAAAA==.Нелюфка:BAAALAAECggIEAABLAAECggIFgABACEWAA==.',['Ни']='Нинзя:BAAALAADCggILAABLAAECgcIIwAEACwKAA==.Ниоктанк:BAAALAAECgEIAQABLAAFFAMICgAHAJQTAA==.Нирелин:BAAALAADCgcIAQAAAA==.Нитида:BAABLAAECoEwAAIJAAgIpRz1HACDAgAJAAgIpRz1HACDAgAAAA==.',['Но']='Номерс:BAAALAAECgMIAQABLAAFFAMICgAHAJQTAA==.',['Од']='Оджи:BAAALAAFFAIIAgAAAA==.',['Ок']='Окитсу:BAAALAAECgIIAgAAAA==.',['Ол']='Ольгерд:BAAALAAECgYIDQAAAA==.',['Ор']='Ороро:BAAALAAECgYICQAAAA==.',['От']='Отсаске:BAAALAAECgEIAQABLAAECgYIBgANAAAAAA==.Оттис:BAAALAADCgcIDgAAAA==.',['Оу']='Оудин:BAAALAAECggIAgAAAA==.',['Па']='Палаводная:BAABLAAECoEnAAIOAAgIkCEiGAD7AgAOAAgIkCEiGAD7AgAAAA==.Палапалинт:BAAALAAECgUIBQAAAA==.Пардонь:BAAALAAECgYIEQAAAA==.Пардоньти:BAAALAADCggICAAAAA==.Пачамама:BAAALAADCgcICQAAAA==.',['Пе']='Перрсиваль:BAACLAAFFIEHAAIaAAMIexGuGQDvAAAaAAMIexGuGQDvAAAsAAQKgSoABBoACAgAH6scAL4CABoACAgAH6scAL4CABsABAivD78cAPIAABwAAQi0CLGMACwAAAAA.',['Пи']='Пивозаврус:BAAALAAECggICAAAAA==.Пигис:BAAALAADCgEIAQAAAA==.',['По']='Позитивх:BAACLAAFFIEKAAIHAAMI5RVHCwDmAAAHAAMI5RVHCwDmAAAsAAQKgRYAAgcACAhUHhAUAKICAAcACAhUHhAUAKICAAAA.Полдеда:BAAALAAECgcIEgAAAA==.Порнхасбик:BAAALAADCgEIAQAAAA==.Похилюшка:BAAALAADCggICAAAAA==.Похмельмен:BAAALAADCgYIBgAAAA==.',['Пр']='Приватбанк:BAAALAADCggIBwAAAA==.Примейлин:BAAALAADCggIGQAAAA==.Просекориане:BAAALAADCgcIEgAAAA==.',['Пы']='Пыхтарчок:BAAALAADCgcIDQAAAA==.Пыщпыщазаза:BAAALAAECggICAABLAAFFAMICgAHAJQTAA==.',['Пэ']='Пэдров:BAAALAADCgYIBgAAAA==.Пэдропал:BAAALAAECgMIAwAAAA==.',['Ра']='Раанеш:BAABLAAECoEaAAIIAAcIGRntFQDuAQAIAAcIGRntFQDuAQAAAA==.Райям:BAAALAAECgIIAgAAAA==.Рантра:BAAALAAECgYIBgAAAA==.Рарочка:BAAALAADCgMIAwAAAA==.',['Ре']='Рейнджшот:BAABLAAECoEkAAMPAAcIuxzCPQApAgAPAAcIuxzCPQApAgACAAEI+AS3vAAeAAAAAA==.Рейханд:BAAALAADCgYIDAAAAA==.Рейши:BAAALAAECgYICQAAAA==.Рекл:BAABLAAFFIEIAAQPAAIIeBrzIQChAAAPAAIIShnzIQChAAACAAIImxY8GQCRAAAdAAEIwRPvBQBWAAAAAA==.',['Рж']='Ржаваборода:BAAALAADCgYIBgAAAA==.',['Ри']='Риденс:BAAALAADCggIEAAAAA==.Ринали:BAAALAADCgcIBwAAAA==.',['Ро']='Рокбэби:BAAALAAECgYIEwAAAA==.Ромеох:BAAALAAECggICAAAAA==.',['Рэ']='Рэйзерх:BAAALAADCggIDAAAAA==.',['Са']='Сангвион:BAAALAAECgEIAQABLAAECgYIFQAKADAbAA==.Санджи:BAAALAADCgYICwAAAA==.Сарквард:BAAALAADCggIEAAAAA==.',['Св']='Святобронь:BAABLAAECoEWAAIOAAgIzRvIKQCkAgAOAAgIzRvIKQCkAgAAAA==.',['Се']='Сендж:BAAALAADCgcIBwAAAA==.Серебряная:BAAALAADCggICAAAAA==.',['Си']='Сильварил:BAAALAADCgcIBwAAAA==.Синьий:BAAALAAECggICgAAAA==.Синэстр:BAAALAAECgYIEgAAAA==.Сирадолина:BAAALAAECggICAAAAA==.Ситлалли:BAABLAAECoEYAAIPAAYIXBr9aQCuAQAPAAYIXBr9aQCuAQAAAA==.',['Ск']='Сквернопопа:BAABLAAECoEcAAMcAAgInBBGIgDWAQAcAAgInBBGIgDWAQAaAAIIogYAAAAAAAAAAA==.Скехит:BAABLAAECoEeAAITAAgI+wScjQAVAQATAAgI+wScjQAVAQAAAA==.',['Сл']='Славинк:BAAALAADCgYIBgAAAA==.Сладкаяватаа:BAAALAADCgEIAQAAAA==.',['См']='Смелслаиктин:BAAALAAECgUIBQABLAAECgYICQANAAAAAA==.Смелслайктин:BAAALAAECgYICQAAAA==.Смерчикс:BAAALAAECgcIBwAAAA==.Смокерро:BAABLAAECoEWAAMeAAgIahU0KgC2AQAeAAgIlhM0KgC2AQAfAAMIORCxIgC3AAAAAA==.',['Со']='Собакапёс:BAAALAAECgYIEQAAAA==.Сонако:BAAALAAECgQIBAAAAA==.Соняшерсть:BAABLAAECoEYAAIPAAgIhRpJNgBDAgAPAAgIhRpJNgBDAgAAAA==.Сопляя:BAAALAAECgEIAQAAAA==.Соргвей:BAAALAADCgQIBQAAAA==.',['Ст']='Стелтон:BAAALAAECgIIAwAAAA==.Стендерс:BAACLAAFFIEJAAIJAAMIVRIgFwDDAAAJAAMIVRIgFwDDAAAsAAQKgR8AAgkABwj3IBUjAGUCAAkABwj3IBUjAGUCAAAA.',['Су']='Супэр:BAAALAAECggICwAAAA==.',['Сь']='Сьюзи:BAAALAAECgQIBgAAAA==.',['Та']='Танхорхеус:BAAALAAECggIDQAAAA==.Тариф:BAABLAAECoEeAAIPAAcI5RyGWADZAQAPAAcI5RyGWADZAQAAAA==.Тариэлья:BAAALAAECgUICAAAAA==.Тарриль:BAACLAAFFIEYAAIUAAUINSGIAADpAQAUAAUINSGIAADpAQAsAAQKgScAAxQACAh2JYEAAF8DABQACAh2JYEAAF8DACAABwjfEdSJAFEBAAAA.',['Тв']='Твики:BAABLAAECoEdAAIgAAgIihcQOQBIAgAgAAgIihcQOQBIAgAAAA==.',['Те']='Тейтелан:BAAALAAECgYIBgAAAA==.Техноярл:BAAALAAECgYICwAAAA==.',['Ти']='Тининка:BAAALAAECggIEAAAAA==.Тинли:BAAALAAECgUIBQAAAA==.',['То']='Тобдру:BAACLAAFFIEKAAIHAAMIlBNXCwDlAAAHAAMIlBNXCwDlAAAsAAQKgS0AAgcACAhSI44IAB8DAAcACAhSI44IAB8DAAAA.Тобприст:BAAALAAECggICAABLAAFFAMICgAHAJQTAA==.Толян:BAAALAAECgEIAQAAAA==.Топоромврыло:BAAALAADCgYIBgAAAA==.Торелия:BAABLAAECoEVAAIgAAgI2xDckQA6AQAgAAgI2xDckQA6AQAAAA==.Тотеммневрот:BAAALAAECggIDQABLAAFFAMICgAHAJQTAA==.Тотемский:BAAALAAECgYIBgAAAA==.',['Тр']='Тратата:BAAALAAECgUIBQAAAA==.Трувор:BAAALAAECggIEwAAAA==.',['Тэ']='Тэльдрассил:BAAALAAECgYIBgAAAA==.',['Тё']='Тёмнаяскорбь:BAAALAADCggICAAAAA==.',['Уб']='Убегато:BAAALAADCgUIBQAAAA==.',['Уз']='Узаан:BAAALAAECgEIAQAAAA==.',['Уи']='Уилхуфф:BAAALAAECgYIBgAAAA==.',['Ул']='Ульянчик:BAABLAAECoEXAAMcAAcIjQsqRgAzAQAaAAYILAwbgQBEAQAcAAcIkQYqRgAzAQAAAA==.',['Уо']='Уооуоо:BAAALAADCgUIBgABLAAECgQIBQANAAAAAA==.',['Ур']='Урурубетон:BAAALAAECgQICwAAAA==.',['Ус']='Устым:BAAALAADCggIEQAAAA==.',['Уш']='Ушко:BAAALAAECgYIDAAAAA==.',['Фа']='Фаворытка:BAAALAADCgcICwAAAA==.Фагот:BAAALAAFFAIIAwAAAA==.Фаеркайс:BAAALAADCgYIBwAAAA==.Фалисо:BAAALAAECgMIAwABLAAECgcIFAAMAAQeAA==.Фанфурик:BAAALAAECgEIAQAAAA==.Фармацевт:BAAALAADCggIBwAAAA==.',['Фе']='Фелард:BAAALAAECggIBwAAAA==.',['Фи']='Физикаводы:BAAALAAECgUIBAAAAA==.',['Фл']='Флора:BAAALAAECgYIEAAAAA==.',['Фо']='Фордис:BAAALAADCgUIBQAAAA==.Форяльда:BAAALAAECgcIBwAAAA==.',['Фр']='Фрейз:BAAALAAECgYICAAAAA==.',['Фу']='Фуфанон:BAAALAAECggICAAAAA==.',['Фэ']='Фэйсонфаер:BAAALAAECgMIAwAAAA==.Фэйтеддру:BAAALAAECgIIAgAAAA==.Фэйтедшам:BAAALAADCgMIAwAAAA==.',['Ха']='Хабрези:BAAALAAECgcIEgAAAA==.',['Хе']='Хеллсинг:BAAALAADCggICAAAAA==.Хенесби:BAAALAADCggIHgAAAA==.',['Хи']='Хитава:BAAALAAECgYIBQAAAA==.',['Хл']='Хлаповинка:BAAALAAECgEIAQAAAA==.',['Хо']='Хо:BAABLAAECoEZAAIKAAYIIBFltgBkAQAKAAYIIBFltgBkAQAAAA==.Хорхеус:BAABLAAECoEeAAIPAAgIQxPChgBwAQAPAAgIQxPChgBwAQAAAA==.Хотадиллер:BAAALAAECggIAgAAAA==.',['Ху']='Хурделиця:BAAALAADCggIFgAAAA==.',['Че']='Чесюньчик:BAAALAAECgEIAQAAAA==.Чефирка:BAAALAADCggICAAAAA==.',['Чи']='Чикато:BAABLAAECoEZAAIaAAcI6wx7ZwCHAQAaAAcI6wx7ZwCHAQAAAA==.',['Ша']='Шазамен:BAAALAAECgUICQAAAA==.Шаргир:BAAALAADCgEIAQAAAA==.Шатриэль:BAAALAADCgQIBAAAAA==.',['Ше']='Шервалла:BAAALAADCggICAAAAA==.',['Ши']='Шигеру:BAAALAADCggIDgAAAA==.',['Шк']='Шкодница:BAAALAAECgMIBwAAAA==.',['Шл']='Шляпшля:BAABLAAECoEVAAMBAAgIPwQQhADOAAABAAgIPwQQhADOAAAHAAEIDAKVmQAcAAAAAA==.',['Шм']='Шмиксель:BAAALAAECgcIBwAAAA==.',['Шр']='Шракус:BAAALAAECgYIEwAAAA==.',['Шу']='Шуршаня:BAABLAAECoEVAAIDAAYICxTCIQCVAQADAAYICxTCIQCVAQAAAA==.',['Шэ']='Шэйнэс:BAAALAADCgcIBwAAAA==.',['Эв']='Эвистар:BAAALAAECgEIAQAAAA==.',['Эй']='Эйласекура:BAAALAAECgIIAgAAAA==.',['Эк']='Эксита:BAAALAADCggIEwAAAA==.',['Эл']='Элайниель:BAAALAAECgcIDwAAAA==.Элуннсис:BAABLAAECoEcAAMhAAcIbhlMCwD2AQAhAAcImBhMCwD2AQAVAAYIxxIiHgB9AQAAAA==.Эльза:BAAALAAECggICAAAAA==.Эльрилион:BAACLAAFFIEIAAITAAMItBoADgAWAQATAAMItBoADgAWAQAsAAQKgSYAAhMACAhvI0cLADMDABMACAhvI0cLADMDAAAA.',['Эо']='Эолус:BAAALAAECgYIEQAAAA==.',['Эр']='Эрешкегаль:BAAALAAECgUICQAAAA==.Эригранд:BAABLAAECoEWAAITAAcIBx+dPAARAgATAAcIBx+dPAARAgAAAA==.',['Эс']='Эсиель:BAAALAAECgEIAQAAAA==.Эсферо:BAAALAAECgQIBgAAAA==.',['Эт']='Этобудетдх:BAABLAAFFIEGAAIGAAIIWwz4MwCQAAAGAAIIWwz4MwCQAAAAAA==.',['Юс']='Юсь:BAACLAAFFIENAAIgAAYIHQ6yEQBPAQAgAAYIHQ6yEQBPAQAsAAQKgSUAAiAACAgXJP0NACADACAACAgXJP0NACADAAAA.',['Яг']='Ягос:BAAALAAECgcIEQAAAA==.',['Як']='Якожид:BAAALAAECggICAAAAA==.',['Ян']='Янекот:BAAALAADCgEIAQAAAA==.Янь:BAAALAAECgcICQAAAA==.',['Яс']='Ясил:BAACLAAFFIEGAAIGAAQI6A8kDgAjAQAGAAQI6A8kDgAjAQAsAAQKgRYAAwYACAgRICwdANMCAAYACAjzHywdANMCACIAAQh1G9VSAEYAAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end