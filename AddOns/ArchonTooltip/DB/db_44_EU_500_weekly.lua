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
 local lookup = {'Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Druid-Restoration','Shaman-Restoration','Shaman-Elemental','Warrior-Protection','Unknown-Unknown','Priest-Holy','Priest-Shadow','Hunter-Survival','DeathKnight-Frost','Druid-Balance','Druid-Feral','Monk-Brewmaster','DemonHunter-Havoc','Paladin-Retribution','Shaman-Enhancement','Priest-Discipline','Paladin-Holy','Monk-Mistweaver',}; local provider = {region='EU',realm='ТкачСмерти',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аа']='Ааркеносс:BAABLAAECoEfAAQBAAcIsR/5EgBHAgABAAcI7xv5EgBHAgACAAIIehQJKACOAAADAAIIoAykyABiAAAAAA==.',['Аб']='Абракадабу:BAAALAADCggICwAAAA==.Абриска:BAACLAAFFIEJAAIEAAQI3BBJCAAfAQAEAAQI3BBJCAAfAQAsAAQKgSYAAgQACAgxIp0GABcDAAQACAgxIp0GABcDAAAA.',['Аг']='Агамон:BAAALAADCggIDwAAAA==.Агамор:BAABLAAECoEfAAICAAcIqyHOAwCwAgACAAcIqyHOAwCwAgAAAA==.Агмен:BAAALAAECgQIBAAAAA==.',['Ал']='Алрокс:BAAALAADCggICAAAAA==.Алыйзверь:BAAALAAECggIDwAAAA==.',['Ар']='Арзес:BAAALAADCgYIBgAAAA==.Армил:BAAALAAECgcIEwAAAA==.',['Ас']='Астия:BAAALAAECgcIDwAAAA==.',['Ау']='Ауфри:BAAALAADCgcIBwAAAA==.',['Ба']='Барони:BAAALAAECgEIAQAAAA==.',['Бл']='Блазред:BAAALAAECgYIDAAAAA==.',['Бр']='Бравосуслов:BAAALAAECgMIAwAAAA==.',['Ва']='Вальденвелл:BAAALAADCgEIAwAAAA==.',['Вд']='Вдох:BAABLAAECoEjAAMFAAgIzBkFLAA+AgAFAAgIzBkFLAA+AgAGAAMI2Qr/jACrAAAAAA==.',['Ве']='Вечныйслон:BAABLAAECoEbAAIGAAcIFCDSHgCKAgAGAAcIFCDSHgCKAgAAAA==.',['Вж']='Вжик:BAAALAADCgEIAQAAAA==.',['Ви']='Вибраниум:BAAALAADCgcIBwABLAAFFAUIDAAHABsjAA==.',['Во']='Вованвовчик:BAAALAADCggICAAAAA==.',['Вт']='Втениночной:BAAALAAECgYIBgAAAA==.',['Вэ']='Вэшураган:BAAALAADCgcIBwAAAA==.',['Га']='Гаутс:BAAALAADCgEIAQAAAA==.',['Го']='Гойчик:BAAALAADCgMIAgAAAA==.',['Да']='Дамо:BAAALAAECgMIAwAAAA==.Даркрай:BAAALAADCgQIBQABLAAECggIDgAIAAAAAA==.',['Де']='Делаэль:BAAALAAECgEIAQAAAA==.Денвиин:BAAALAAECgUIDgAAAA==.',['Ди']='Дитатси:BAACLAAFFIESAAIJAAUI/CBEBADXAQAJAAUI/CBEBADXAQAsAAQKgSsAAwkACAj7HvIVAKACAAkACAj7HvIVAKACAAoAAgjDEu12AIEAAAAA.',['До']='Довакин:BAACLAAFFIEMAAIHAAUIGyPYAQAWAgAHAAUIGyPYAQAWAgAsAAQKgTAAAgcACAihJroAAIgDAAcACAihJroAAIgDAAAA.Дочькенария:BAAALAAECggICAAAAA==.',['Др']='Дримсфера:BAAALAADCgUIBQAAAA==.',['Дю']='Дюфкорнеж:BAAALAADCggICAAAAA==.',['Же']='Желандир:BAABLAAECoEVAAILAAYI+hFVDwCGAQALAAYI+hFVDwCGAQAAAA==.',['За']='Зарианис:BAAALAADCgQIBAAAAA==.',['Зв']='Зверг:BAABLAAECoEXAAIMAAgIVxgHPgBcAgAMAAgIVxgHPgBcAgAAAA==.',['Зк']='Зкс:BAABLAAECoEbAAQEAAYIUxkQPAC6AQAEAAYIUxkQPAC6AQANAAQINA9LZwDTAAAOAAEIjwi9PwA2AAAAAA==.',['Зо']='Золомон:BAABLAAECoEcAAIPAAgI0CWWAQBkAwAPAAgI0CWWAQBkAwAAAA==.',['Ик']='Иктарион:BAAALAADCgcICAAAAA==.',['Ил']='Иллиона:BAABLAAECoEjAAMJAAgIShw8JABCAgAJAAgIShw8JABCAgAKAAEIww7djAAvAAAAAA==.',['Им']='Императрицао:BAAALAAECgUIBQAAAA==.',['Их']='Ихния:BAABLAAECoEUAAIQAAgIiQx5kgB0AQAQAAgIiQx5kgB0AQAAAA==.',['Кв']='Квенси:BAAALAAECgUIBwAAAA==.',['Ки']='Кисакаи:BAAALAADCggICAAAAA==.',['Кн']='Кноппка:BAAALAADCgMIBAAAAA==.Князьмолнии:BAAALAAECgMIAwAAAA==.Князьсвета:BAAALAAECgYIBgAAAA==.',['Ко']='Коминами:BAAALAAECgYICQAAAA==.Корольличи:BAAALAAECgUIBQAAAA==.',['Кс']='Ксал:BAABLAAECoEWAAIJAAcIryBgFwCWAgAJAAcIryBgFwCWAgAAAA==.Ксандрия:BAAALAADCgYIDAAAAA==.',['Ле']='Лекъса:BAAALAADCgcIBwAAAA==.',['Ли']='Линьшуй:BAAALAADCgQIBAAAAA==.',['Ма']='Малишта:BAAALAAECgIIAgAAAA==.Мамавар:BAAALAAFFAEIAQAAAA==.Мариарти:BAAALAAECgYICgAAAA==.',['Ме']='Медуза:BAAALAADCgcIBwAAAA==.Мелоронтор:BAAALAADCgQIAgAAAA==.',['Ми']='Митрикс:BAAALAADCggIEAAAAA==.',['Мо']='Мозай:BAAALAAECgQIBAAAAA==.Монахтан:BAAALAADCgYIBgAAAA==.',['На']='Нарсилэн:BAAALAADCgIIAgAAAA==.',['Не']='Неуловим:BAABLAAECoEXAAIRAAYITBCosgBeAQARAAYITBCosgBeAQAAAA==.',['Но']='Норгана:BAAALAAECggICAAAAA==.',['Об']='Обматерю:BAAALAAECggICAAAAA==.',['Ор']='Ораксия:BAAALAADCgYIBgAAAA==.Оракул:BAAALAADCgIIAgAAAA==.Ореешек:BAAALAADCgQIBAAAAA==.',['Па']='Пантеонбогов:BAAALAADCgcIDQAAAA==.',['По']='Понжик:BAAALAAECgMIAgAAAA==.',['Пр']='Прошмотрэ:BAABLAAECoEUAAINAAcIGhqLMQDKAQANAAcIGhqLMQDKAQAAAA==.',['Ре']='Редгал:BAAALAADCggICAAAAA==.Рен:BAABLAAECoEWAAIDAAYIsQrChAA7AQADAAYIsQrChAA7AQAAAA==.',['Ри']='Рисед:BAACLAAFFIEGAAIFAAII1R+6GwCyAAAFAAII1R+6GwCyAAAsAAQKgR0AAwUACAi4H18WAKkCAAUACAi4H18WAKkCABIAAgihCgAAAAAAAAAA.',['Ро']='Ромбикк:BAAALAADCggICAAAAA==.',['Ры']='Рыжийброц:BAAALAAECgUICQAAAA==.',['Рэ']='Рэйджер:BAAALAADCgYIBwAAAA==.Рэн:BAAALAADCggICgAAAA==.',['Са']='Саврик:BAABLAAECoEWAAIKAAcIfxzeMADqAQAKAAcIfxzeMADqAQAAAA==.Садаор:BAAALAADCgQIBAAAAA==.Сайгак:BAAALAADCgMIAwAAAA==.Салюки:BAAALAAECgIIAgAAAA==.Санчоус:BAAALAAECggIBAAAAA==.',['Св']='Святотатство:BAABLAAECoEUAAMJAAcItgaEYQAyAQAJAAcItgaEYQAyAQATAAEI8AG5NgAoAAAAAA==.',['Сг']='Сгаэль:BAAALAAECgIIBAAAAA==.',['Се']='Сестрёнка:BAAALAADCgEIAQAAAA==.',['Си']='Сибирь:BAACLAAFFIEPAAIRAAcIfhTFAAB4AgARAAcIfhTFAAB4AgAsAAQKgSsAAxEACAjBJSkIAFcDABEACAjBJSkIAFcDABQACAh6FDslAMABAAAA.',['Ск']='Скиминок:BAAALAADCgcIBwABLAAECgcIFAAJALYGAA==.Скромняга:BAAALAADCgYIBgAAAA==.',['Сл']='Слуфи:BAAALAAECgIIAgAAAA==.',['Сп']='Сприбабахом:BAABLAAECoEgAAIFAAcITBWVWwClAQAFAAcITBWVWwClAQAAAA==.',['Ст']='Старкиллер:BAAALAAECggIEQAAAA==.Степнойволк:BAAALAAECgYIBgAAAA==.',['Су']='Суккубаа:BAAALAAECggIBwAAAA==.Супбро:BAAALAADCgcIBwAAAA==.',['Та']='Тазикмахорки:BAAALAAECgYIDgAAAA==.Тальгранис:BAABLAAECoEZAAIMAAYICgsr0wA1AQAMAAYICgsr0wA1AQAAAA==.Тамиса:BAAALAADCgIIAgAAAA==.Тарнезиз:BAAALAAECggIBwAAAA==.Таутау:BAAALAADCgEIAQAAAA==.',['Те']='Телега:BAAALAAECgEIAQAAAA==.Теребосик:BAAALAAECgYIBgAAAA==.',['Ти']='Тимальт:BAAALAAECgUIBwAAAA==.Типос:BAAALAAECgYIEQAAAA==.',['То']='Тодэш:BAAALAADCgcICAAAAA==.Тонда:BAABLAAECoEYAAIQAAYIHAVCzgDyAAAQAAYIHAVCzgDyAAAAAA==.Топлес:BAAALAADCggICAAAAA==.',['Уз']='Узундара:BAAALAAECgEIAQAAAA==.',['Ул']='Ультремщещес:BAAALAADCgcIDgAAAA==.',['Фа']='Фастмен:BAAALAADCggICgAAAA==.',['Фо']='Фоксхаунд:BAABLAAECoEcAAIFAAgIhyMDBwAbAwAFAAgIhyMDBwAbAwAAAA==.Фофинчик:BAABLAAECoEZAAIVAAYIsRW/HwB7AQAVAAYIsRW/HwB7AQAAAA==.',['Фр']='Фродыч:BAAALAADCgYIBgAAAA==.',['Фу']='Фу:BAAALAADCgUIBQAAAA==.',['Фэ']='Фэоми:BAAALAADCgcIBwAAAA==.',['Ха']='Хакиро:BAAALAAECgcIDwAAAA==.',['Хв']='Хвэй:BAAALAAECggICAAAAA==.',['Хе']='Хеллсинг:BAAALAADCgMIBAAAAA==.',['Хо']='Хорланд:BAAALAAECgYIDgAAAA==.',['Цз']='Цзицзан:BAAALAADCgcIBwAAAA==.',['Ци']='Циркут:BAAALAAECggIBwAAAA==.',['Чи']='Читах:BAAALAAECgYICAAAAA==.Чичикоричи:BAAALAADCgYIBgAAAA==.',['Чу']='Чупикс:BAAALAADCgYIBgAAAA==.',['Ша']='Шарлотта:BAAALAADCggICAAAAA==.',['Ши']='Шиккари:BAAALAAECggIEQAAAA==.',['Шм']='Шмоукамнезию:BAAALAADCggIEAAAAA==.',['Эд']='Эдвана:BAAALAADCggIEAAAAA==.',['Эз']='Эзра:BAAALAAECgUICQAAAA==.',['Эл']='Эльдраторий:BAAALAADCgYIBgAAAA==.',['Эн']='Энкрасс:BAABLAAECoEYAAIQAAcIAA5VhgCLAQAQAAcIAA5VhgCLAQAAAA==.',['Ям']='Ями:BAAALAAECgYIBgAAAA==.',['Ят']='Яторо:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end