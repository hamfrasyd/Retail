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
 local lookup = {'Warrior-Fury','Unknown-Unknown','Priest-Shadow','Shaman-Restoration','Warrior-Arms','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Blood','Druid-Feral','Priest-Holy','Warlock-Destruction','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','DeathKnight-Frost','Druid-Balance','Hunter-BeastMastery',}; local provider = {region='EU',realm='СтражСмерти',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ад']='Адиас:BAABLAAECoEZAAIBAAgIDhf3MwA1AgABAAgIDhf3MwA1AgAAAA==.',['Ак']='Аксарион:BAAALAAECggICAAAAA==.',['Ам']='Амаэн:BAAALAADCgMIAwAAAA==.Амфира:BAAALAADCgYIBgAAAA==.',['Ан']='Античный:BAAALAADCgUIBQABLAAECgMIBgACAAAAAA==.',['Ас']='Астольфо:BAABLAAECoEVAAIDAAcI9hA2UABQAQADAAcI9hA2UABQAQAAAA==.',['Ат']='Атариэль:BAAALAAECgcIDgAAAA==.Атестат:BAAALAADCgcIEQAAAA==.',['Ау']='Ауруа:BAAALAAECgYIBgABLAAECgcIDQACAAAAAA==.',['Ба']='Бабапожар:BAAALAADCgEIAQAAAA==.Баджерман:BAAALAADCgMIAwAAAA==.Балансахочу:BAAALAADCgQIBAABLAAECgYIEQACAAAAAA==.',['Бе']='Бекри:BAABLAAECoEjAAIEAAYIqCGjMQAoAgAEAAYIqCGjMQAoAgAAAA==.',['Бл']='Блайндэ:BAAALAADCggIBAAAAA==.Блейдразор:BAAALAADCggICAAAAA==.',['Бр']='Бруталдэз:BAACLAAFFIEHAAIFAAMI+g2AAQDPAAAFAAMI+g2AAQDPAAAsAAQKgSUAAgUACAgDHbUFAJYCAAUACAgDHbUFAJYCAAAA.',['Бь']='Бь:BAAALAADCgYIBgAAAA==.',['Ва']='Валирьянка:BAAALAAECgcIDQAAAA==.Вармион:BAAALAADCgYIBgAAAA==.',['Ве']='Веранотик:BAAALAADCgIIAgAAAA==.',['Ви']='Виллейна:BAACLAAFFIERAAIGAAUIQCCDCADjAQAGAAUIQCCDCADjAQAsAAQKgTgAAwYACAi0JYkLAC4DAAYACAi0JYkLAC4DAAcAAQhNEogbAEAAAAAA.Виндекс:BAABLAAECoEbAAIIAAgIVh1AMgBuAgAIAAgIVh1AMgBuAgAAAA==.Витка:BAAALAAECgcIEgAAAA==.',['Ву']='Вуд:BAAALAAECgQIBQAAAA==.',['Да']='Давидоф:BAAALAAECgMIBgAAAA==.',['Де']='Дестромен:BAAALAAECgMIAwAAAA==.',['Ди']='Дидок:BAAALAAECgYIBgABLAAECgcIFQAJAFQMAA==.',['До']='Донатос:BAAALAAECgEIAQAAAA==.',['Др']='Драккари:BAAALAAECgYIBgABLAAFFAIIBgAKAPgRAA==.',['Дэ']='Дэзгарон:BAAALAAECgYIDwAAAA==.Дэфрэд:BAAALAAECgYIDgAAAA==.',['Ех']='Ех:BAABLAAECoEbAAIBAAcIJB5MKgBkAgABAAcIJB5MKgBkAgAAAA==.',['Же']='Жених:BAAALAAECggIEAAAAA==.',['Зе']='Зеленини:BAAALAADCgMIAwAAAA==.Зеферус:BAAALAAECgcIEwAAAA==.',['Из']='Изифаза:BAAALAADCggICAAAAA==.',['Им']='Иммунира:BAAALAAECgcIEQAAAA==.',['Ир']='Ириска:BAAALAADCgcIBwAAAA==.',['Йо']='Йоноас:BAAALAADCgcIBwAAAA==.',['Ка']='Каральо:BAACLAAFFIELAAIDAAMILCCgCwAMAQADAAMILCCgCwAMAQAsAAQKgS0AAgMACAiLJOYEAFEDAAMACAiLJOYEAFEDAAAA.Карантино:BAAALAADCgcICQAAAA==.Кататумбо:BAABLAAECoEWAAIEAAcI6h5EIQBtAgAEAAcI6h5EIQBtAgAAAA==.',['Ке']='Кельтэс:BAABLAAECoEuAAMLAAgI3B9VDgDhAgALAAgI3B9VDgDhAgADAAYIbA2JVAA+AQAAAA==.',['Ки']='Кинтохо:BAAALAAECgUIBQAAAA==.Кириена:BAAALAAECgMIBQAAAA==.',['Ла']='Латирис:BAAALAADCgEIAQAAAA==.',['Ле']='Лем:BAAALAADCgEIAQAAAA==.Лемке:BAAALAADCggIDAAAAA==.Лесстра:BAAALAADCggIEAAAAA==.',['Ло']='Локомока:BAABLAAECoEVAAIMAAcIrxkyVQC+AQAMAAcIrxkyVQC+AQAAAA==.Лоргаар:BAAALAADCggIEAABLAADCggIGAACAAAAAA==.',['Ма']='Магмочка:BAAALAADCggICAABLAAECgcIDQACAAAAAA==.Маркеллозз:BAAALAAECgYIEwAAAA==.Матурбатыр:BAAALAAECgEIAQABLAAECgcIHQANAIIUAA==.Матьигната:BAAALAAECggICwAAAA==.Мах:BAAALAAECgUIBwABLAAECgcIFQAJAFQMAA==.Махакам:BAABLAAECoEbAAIOAAgIyCHDAwANAwAOAAgIyCHDAwANAwAAAA==.',['Ме']='Менчи:BAAALAADCggICAAAAA==.',['Ми']='Милкивей:BAAALAAECgUICgAAAA==.Михалч:BAAALAADCgcIBwABLAAECgcIFQAJAFQMAA==.',['Мо']='Мортарион:BAAALAADCggIGAAAAA==.',['Мя']='Мягкиелапки:BAAALAAECgcIDAAAAA==.',['Не']='Неверморганн:BAABLAAECoEQAAIGAAYIwQVdoQAKAQAGAAYIwQVdoQAKAQAAAA==.Неонит:BAAALAAECgYIDAAAAA==.',['Но']='Ночнойларек:BAAALAAECgIIAgABLAAFFAMIDQADADUSAA==.',['Нэ']='Нэдгард:BAAALAADCggIBQAAAA==.',['Ол']='Олала:BAABLAAECoEiAAIPAAgI7A6KJADiAQAPAAgI7A6KJADiAQAAAA==.',['Он']='Онмунд:BAAALAADCggICAABLAAFFAIIBgALAA0hAA==.',['Па']='Паладэцл:BAAALAADCgcIBwAAAA==.',['Пи']='Пиваспрайм:BAAALAAECggIDgAAAA==.Пивкин:BAAALAADCggIGgAAAA==.Пивпауч:BAAALAADCggICQAAAA==.',['По']='Подуха:BAABLAAECoEdAAINAAcIghQcewDDAQANAAcIghQcewDDAQAAAA==.',['Ра']='Раташ:BAAALAAECgYIEgABLAAFFAIIBgALAA0hAA==.',['Ре']='Редсайд:BAAALAAFFAIIAgAAAA==.',['Ро']='Ронодальдо:BAAALAADCgMIBwAAAA==.',['Ру']='Рубакагерой:BAAALAADCgIIAgAAAA==.Ругаш:BAAALAAECgQIBQAAAA==.',['Са']='Саангвиний:BAAALAADCggIEAABLAADCggIGAACAAAAAA==.Сайеаль:BAAALAAECgMIBAABLAAECgcIDQACAAAAAA==.Санлайн:BAAALAADCgMIAwAAAA==.',['Се']='Седойурал:BAAALAADCggICQAAAA==.Сейни:BAAALAAECgcIEAAAAA==.Секонд:BAAALAADCgcIBwAAAA==.Сепнай:BAABLAAECoEhAAIQAAgINhS8FQDxAQAQAAgINhS8FQDxAQAAAA==.',['Сл']='Слезинка:BAAALAADCggIDAAAAA==.',['См']='Смелая:BAABLAAECoElAAIIAAcIxAmAmQBlAQAIAAcIxAmAmQBlAQAAAA==.',['Сп']='Сперхей:BAAALAAECgYICQABLAAECgcIFgAEAOoeAA==.',['Ст']='Старкс:BAAALAAECgYIDwAAAA==.',['Та']='Такаянаги:BAAALAAECgYIDQAAAA==.Тамагочи:BAAALAADCgYIAgAAAA==.Танкред:BAAALAADCgQIBAAAAA==.Таронгал:BAAALAAECgEIAQAAAA==.',['Тр']='Тристам:BAABLAAECoEmAAQRAAYIxRtOEwBlAQASAAUIcxuKLwCQAQARAAUIdBlOEwBlAQAMAAEIZBV41AA/AAAAAA==.Тритопатр:BAAALAADCggIFAAAAA==.',['Ту']='Туризаз:BAAALAAECgIIBAAAAA==.',['Тэ']='Тэйлз:BAAALAADCggIDgABLAAECggILgALANwfAA==.',['Ур']='Уркожор:BAACLAAFFIEPAAITAAQIlQctDQAVAQATAAQIlQctDQAVAQAsAAQKgSsAAxMACAiSGn8hAHgCABMACAiSGn8hAHgCAAQABAgZBQAAAAAAAAAA.',['Фл']='Флаб:BAACLAAFFIEGAAILAAIIDSGyFgC9AAALAAIIDSGyFgC9AAAsAAQKgSwAAgsACAjTJZkBAG8DAAsACAjTJZkBAG8DAAAA.',['Фо']='Фогад:BAAALAAECgEIAQAAAA==.Фоксэр:BAAALAAECgYIDwAAAA==.',['Фс']='Фсоо:BAACLAAFFIEKAAIUAAMItCOPEAAvAQAUAAMItCOPEAAvAQAsAAQKgSQAAhQACAjdI0AQACADABQACAjdI0AQACADAAAA.',['Фу']='Фуджитора:BAAALAAECgUIDAAAAA==.Фурсон:BAAALAADCgEIAQAAAA==.',['Ха']='Харьков:BAAALAADCggIDgABLAAFFAYIGgABAJYaAA==.',['Хе']='Хелона:BAAALAADCggIDQAAAA==.Хемеус:BAAALAADCgEIAgABLAAFFAUIEQAEAHwcAA==.',['Хи']='Хиккара:BAAALAADCgQIBAAAAA==.',['Хэ']='Хэппенинг:BAAALAADCggICQABLAAECgcIFQAJAFQMAA==.',['Цв']='Цветаняшка:BAAALAAECgYICAAAAA==.',['Ша']='Шамми:BAAALAAECgYIBgAAAA==.',['Ше']='Шейндрал:BAAALAAECggICAABLAAECggILgALANwfAA==.',['Ши']='Шизахрения:BAAALAADCggICAAAAA==.',['Шо']='Шолиен:BAAALAADCgYIBgAAAA==.',['Ыг']='Ыгорь:BAAALAAECgUIBgAAAA==.',['Эл']='Элкиора:BAAALAAECgIIAgABLAAECggIIQAQADYUAA==.Элунастрайк:BAABLAAECoEgAAIVAAYIcBsMLwDYAQAVAAYIcBsMLwDYAQAAAA==.',['Эм']='Эмили:BAAALAADCggICAAAAA==.',['Эн']='Энра:BAABLAAECoElAAIWAAcIxRmMUADuAQAWAAcIxRmMUADuAQAAAA==.',['Эс']='Эскалон:BAABLAAECoEUAAINAAYI9R01ZgDuAQANAAYI9R01ZgDuAQAAAA==.',['Ян']='Янефрик:BAAALAAECgUIBQAAAA==.',['Яр']='Яростьсилы:BAAALAADCggIIAAAAA==.',['Яс']='Ясёна:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end