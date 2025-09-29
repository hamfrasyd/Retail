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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Priest-Shadow','Warrior-Fury','Monk-Mistweaver','Hunter-Marksmanship','Mage-Frost','Shaman-Restoration','Priest-Holy','Mage-Arcane','Druid-Restoration','Druid-Balance','Paladin-Protection','Warrior-Protection','Warrior-Arms','Hunter-Survival','DeathKnight-Frost','Druid-Guardian',}; local provider = {region='EU',realm='Седогрив',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ёт']='Ётта:BAAALAADCgYIBgAAAA==.',['Ал']='Аликаним:BAAALAADCggIEAAAAA==.Альмодора:BAAALAAECggIBQAAAA==.',['Ам']='Амайма:BAAALAAFFAIIBAAAAA==.Амаймо:BAAALAAECggICAABLAAFFAIIBAABAAAAAA==.Амантиш:BAAALAAECgEIAQAAAA==.',['Ан']='Анок:BAABLAAECoEbAAICAAcItxb1LACOAQACAAcItxb1LACOAQAAAA==.',['Ас']='Аст:BAAALAAECgUIBQAAAA==.',['Ат']='Атаман:BAABLAAECoEgAAIDAAgIbQUa2AC/AAADAAgIbQUa2AC/AAAAAA==.',['Ба']='Бабабой:BAAALAADCggICQAAAA==.',['Ва']='Вальдо:BAACLAAFFIEIAAIEAAMI8gj+DwDPAAAEAAMI8gj+DwDPAAAsAAQKgSYAAgQACAiQFDAqABACAAQACAiQFDAqABACAAAA.Варакавайка:BAAALAAECgMIBgAAAA==.',['Ви']='Виадар:BAAALAADCgIIAgAAAA==.Вик:BAAALAADCgMIBAAAAA==.Виксария:BAAALAAECgMICgAAAA==.Вираас:BAAALAADCgEIAQAAAA==.',['Во']='Волосатистый:BAAALAADCggIFQAAAA==.',['Ге']='Генан:BAACLAAFFIEUAAIFAAUIjwepCQB8AQAFAAUIjwepCQB8AQAsAAQKgTcAAgUACAjCHpIgAJ8CAAUACAjCHpIgAJ8CAAAA.',['Го']='Гокс:BAAALAADCgcICgAAAA==.Гонгу:BAAALAAECgYICwAAAA==.Готфрида:BAAALAADCgcIBwAAAA==.',['Да']='Даэгарх:BAAALAADCgIIAgAAAA==.',['Дж']='Джублинатор:BAAALAAECgEIAQABLAAFFAUIEgAFAIQVAA==.',['Др']='Драник:BAAALAAECggICAABLAAFFAYIFwAGAFAWAA==.',['Ды']='Дыха:BAAALAADCggIEgABLAAFFAIICAAHADMMAA==.',['Ел']='Елайза:BAABLAAECoEZAAIIAAcIER1wHQAKAgAIAAcIER1wHQAKAgAAAA==.',['Жб']='Жбых:BAAALAAECgIIAwAAAA==.',['Жн']='Жнсу:BAAALAAECgEIAQAAAA==.',['За']='Зайзен:BAAALAAECgYIBgAAAA==.Занозза:BAAALAAECgIIAgAAAA==.',['Зе']='Зерелия:BAAALAAECgIIAwAAAA==.',['Зи']='Зилёненькая:BAAALAADCggIFAAAAA==.',['Зл']='Злойкозёл:BAAALAADCgIIAgAAAA==.',['Зы']='Зыба:BAAALAAECgYIEQAAAA==.',['Ин']='Инари:BAAALAADCggIKAAAAA==.',['Ки']='Киеши:BAAALAAECgYIEQAAAA==.',['Кл']='Клеофина:BAAALAAECgMIAwAAAA==.',['Ко']='Кои:BAAALAADCgEIAQAAAA==.Коушин:BAAALAAECgYIBgAAAA==.',['Кр']='Кроваваямгла:BAAALAADCggIIgAAAA==.',['Кс']='Кседоларай:BAAALAADCggIHwAAAA==.Ксорос:BAAALAAECgMIAwAAAA==.',['Ла']='Ланпу:BAABLAAECoEuAAIJAAgINBuuIwBjAgAJAAgINBuuIwBjAgAAAA==.',['Ле']='Лексдефендер:BAABLAAECoEbAAIIAAYIYA16QwA8AQAIAAYIYA16QwA8AQAAAA==.Лексычус:BAAALAAECgEIAQAAAA==.Лексычч:BAAALAAECgIIAgAAAA==.Летрикс:BAABLAAECoEfAAIKAAYIwRk4PwC2AQAKAAYIwRk4PwC2AQAAAA==.',['Ля']='Ляна:BAABLAAECoEcAAIIAAYI2wrYRAA2AQAIAAYI2wrYRAA2AQAAAA==.',['Ма']='Маомао:BAACLAAFFIEXAAIGAAYIUBYZAgDyAQAGAAYIUBYZAgDyAQAsAAQKgTcAAgYACAhTIakFAPUCAAYACAhTIakFAPUCAAAA.',['Ме']='Медь:BAAALAAECgIIAgAAAA==.Мерлина:BAAALAAECgYIBwAAAA==.Метео:BAABLAAECoEdAAIJAAYI5RYGbAB5AQAJAAYI5RYGbAB5AQABLAAFFAIICAAHADMMAA==.',['Ми']='Мизраиль:BAAALAAECgEIAQAAAA==.Микилянджело:BAAALAAECgYIDQAAAA==.Минимэ:BAABLAAECoEiAAMIAAcIFhoEGwAdAgAIAAcIFhoEGwAdAgALAAEIZAo83wA1AAAAAA==.Мишелин:BAAALAADCgUIBAAAAA==.',['Му']='Муськамяу:BAAALAADCggICQAAAA==.',['На']='Нарахирн:BAABLAAECoElAAMMAAgIkBf/JQAkAgAMAAgIkBf/JQAkAgANAAEIIAhHlAAqAAAAAA==.Нашслоняра:BAAALAAECgUIDwAAAA==.',['Не']='Нерох:BAAALAAECgYIBgAAAA==.',['Ну']='Нуш:BAABLAAECoEaAAMCAAgInRB1MgBuAQACAAcIkA11MgBuAQAOAAgI7hI3OQAOAQAAAA==.',['Ня']='Няшаубиваша:BAAALAAECgUIBQAAAA==.',['Ор']='Орбобра:BAAALAADCggIJgAAAA==.',['По']='Позоразерота:BAAALAAECgcIEgABLAAFFAIICgAGADQlAA==.Полочка:BAAALAAECgMIAwAAAA==.Попрыгун:BAAALAAECgIIAgAAAA==.',['Пё']='Пёсикк:BAAALAAECgEIAQAAAA==.',['Ре']='Реви:BAAALAAECgIIAwAAAA==.',['Со']='Соплябобра:BAAALAADCggIFgAAAA==.',['Та']='Табуретка:BAAALAAECgIIAwAAAA==.Таймдк:BAAALAADCgYIBgAAAA==.Талдрис:BAAALAAECgMIAwAAAA==.Тандерфурия:BAAALAADCgcIDQAAAA==.Танюхин:BAAALAAECgYICwAAAA==.',['Тр']='Трактористка:BAACLAAFFIEGAAMFAAIINxMtJACbAAAFAAIINxMtJACbAAAPAAEIuA/EIQA+AAAsAAQKgSgAAwUACAj/IWwOABsDAAUACAj/IWwOABsDAA8ABgikFsU4AGABAAEsAAUUBQgPAA0ANiMA.Трацеригос:BAAALAADCgYIBgAAAA==.Трацерион:BAAALAAECgYIEQAAAA==.Трисстам:BAABLAAECoEfAAMFAAgIzyJ8DQAiAwAFAAgIzyJ8DQAiAwAQAAQIqiDdFgBRAQAAAA==.',['Ту']='Тунго:BAAALAAECgYIEgAAAA==.',['Фа']='Фаяла:BAACLAAFFIEGAAIKAAIICg4vJACRAAAKAAIICg4vJACRAAAsAAQKgR0AAwoABgg4HtwtAAwCAAoABgg4HtwtAAwCAAQABghjC1BYAC0BAAEsAAUUBggXAAYAUBYA.',['Фи']='Финнмо:BAAALAADCggIDgAAAA==.Фистер:BAACLAAFFIEXAAIRAAYIUh0NAAB8AgARAAYIUh0NAAB8AgAsAAQKgTcAAhEACAjYJkwAAIADABEACAjYJkwAAIADAAAA.',['Хо']='Холикприст:BAAALAAECgEIAQAAAA==.',['Хэ']='Хэйнур:BAACLAAFFIEIAAISAAIIFRQvSACQAAASAAIIFRQvSACQAAAsAAQKgTAAAhIACAirIKIfANICABIACAirIKIfANICAAAA.',['Ше']='Шериф:BAAALAADCggICQAAAA==.',['Эз']='Эзеарэнель:BAACLAAFFIEJAAITAAMILh/uAAAhAQATAAMILh/uAAAhAQAsAAQKgS0AAhMACAi6I54BAD4DABMACAi6I54BAD4DAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end