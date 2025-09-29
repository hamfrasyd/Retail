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
 local lookup = {'Druid-Feral','DeathKnight-Frost','DeathKnight-Blood','Mage-Frost','Shaman-Enhancement','Priest-Holy','Shaman-Elemental','Warrior-Protection','Warrior-Fury','Priest-Shadow','Paladin-Retribution','Hunter-BeastMastery','Warrior-Arms','Warlock-Destruction','Unknown-Unknown','Warlock-Demonology','Mage-Arcane','Mage-Fire','Priest-Discipline','Shaman-Restoration','Monk-Windwalker','DeathKnight-Unholy','Monk-Brewmaster','Paladin-Protection','Rogue-Outlaw','DemonHunter-Vengeance','DemonHunter-Havoc','Hunter-Marksmanship','Monk-Mistweaver','Druid-Balance','Rogue-Assassination','Paladin-Holy','Warlock-Affliction',}; local provider = {region='EU',realm='Голдринн',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аб']='Абнурсик:BAAALAAECgYIBgABLAAFFAUICwABANMaAA==.',['Ав']='Авернус:BAACLAAFFIEGAAMCAAIIlxtIMQCiAAACAAIIlxtIMQCiAAADAAEILQkgEQA8AAAsAAQKgRwAAgIABwg6IWVIAD4CAAIABwg6IWVIAD4CAAAA.',['Аг']='Агрегат:BAAALAAECgYIBQAAAA==.',['Ад']='Адонит:BAAALAADCgYIBgAAAA==.',['Аз']='Азуфел:BAAALAADCggICAAAAA==.',['Ай']='Айара:BAAALAAECgMIAwABLAAFFAMIBgAEAL0HAA==.Айроон:BAAALAADCgcICwAAAA==.',['Ал']='Алексанора:BAAALAAECggIEgAAAA==.Альтэра:BAAALAAECgIIAgAAAA==.Алья:BAACLAAFFIEXAAIFAAYIVh8dAABoAgAFAAYIVh8dAABoAgAsAAQKgTYAAgUACAiAJiUAAI4DAAUACAiAJiUAAI4DAAAA.',['Ар']='Архиерий:BAAALAAECgMIAwAAAA==.',['Ау']='Ауф:BAAALAADCggICAAAAA==.Ауфидерзеин:BAAALAAECgQICwAAAA==.',['Ба']='Бабаи:BAAALAAECgYICgAAAA==.Бабаландин:BAAALAAECgYIEAAAAA==.',['Бе']='Берлио:BAAALAAECggICQAAAA==.',['Би']='Бигсисилайф:BAAALAADCgQIBAAAAA==.Бинтамин:BAABLAAECoEbAAIGAAYI2A3RYAA1AQAGAAYI2A3RYAA1AQAAAA==.Биттремар:BAAALAAECgcICgAAAA==.',['Бо']='Болан:BAABLAAECoEcAAIHAAgIzwj6ZwBMAQAHAAgIzwj6ZwBMAQAAAA==.Большоедупло:BAAALAAFFAIIAgAAAA==.',['Бр']='Броньем:BAACLAAFFIEJAAIIAAMIbRb+BwDzAAAIAAMIbRb+BwDzAAAsAAQKgS0AAwgACAiiIc4IAPcCAAgACAjMIM4IAPcCAAkACAhHGkAzADgCAAAA.Брутосвет:BAAALAADCgcICQAAAA==.Брэмбур:BAAALAAECggIDAAAAA==.',['Бу']='Бумбыч:BAACLAAFFIETAAIKAAYIORMiBADzAQAKAAYIORMiBADzAQAsAAQKgTcAAgoACAgxItwNAPUCAAoACAgxItwNAPUCAAAA.Бурляшка:BAABLAAECoEUAAILAAYILSCdXgD/AQALAAYILSCdXgD/AQAAAA==.Бурявомне:BAAALAAECgcIDwAAAA==.',['Бь']='Бьяка:BAAALAADCgYICwAAAA==.',['Ва']='Валанирр:BAAALAADCgYIBgAAAA==.Валирель:BAAALAAECgQIBAAAAA==.Валорд:BAABLAAECoEcAAIMAAcITxZFYgDAAQAMAAcITxZFYgDAAQAAAA==.Вальдракс:BAACLAAFFIEHAAICAAIIOx6ILQCoAAACAAIIOx6ILQCoAAAsAAQKgSUAAgIACAiLH7QoAKoCAAIACAiLH7QoAKoCAAAA.Варгхар:BAABLAAECoEdAAMNAAcIrR3oBwBXAgANAAcIrR3oBwBXAgAJAAcIGRXiSwDXAQAAAA==.Вардрэйн:BAAALAADCggIDwAAAA==.',['Ве']='Велизарка:BAACLAAFFIEGAAIOAAII0xhxJACmAAAOAAII0xhxJACmAAAsAAQKgRYAAg4ACAh7HIYgAKYCAA4ACAh7HIYgAKYCAAAA.Вестага:BAAALAAECggIDAAAAA==.Ветролис:BAAALAADCgYIBgAAAA==.',['Ви']='Вискарь:BAAALAAECgcIDgAAAA==.Виталаари:BAAALAAECgYICAAAAA==.',['Вл']='Влупатор:BAAALAADCgEIAQABLAAECgYIEQAPAAAAAA==.',['Во']='Вомбосан:BAAALAAECgYICwAAAA==.Вон:BAAALAADCgEIAQAAAA==.',['Вш']='Вшатаю:BAAALAAECgIIAgAAAA==.',['Вэ']='Вэййчик:BAABLAAECoEYAAMQAAgIRRtmFQAxAgAQAAgI+hdmFQAxAgAOAAYIRR4eQQAGAgAAAA==.',['Га']='Гаськин:BAAALAAECggIDwAAAA==.',['Ге']='Гелеин:BAABLAAECoEaAAILAAcIrxkHWwAIAgALAAcIrxkHWwAIAgAAAA==.Генизис:BAAALAAECgIIAgAAAA==.',['Ги']='Гилиеанна:BAABLAAECoEmAAILAAgI7RvjMgB/AgALAAgI7RvjMgB/AgAAAA==.Гильдестерн:BAAALAAECgYICgAAAA==.',['Гр']='Граунд:BAAALAAECgMIAwAAAA==.',['Да']='Даймасс:BAAALAAECggIEAAAAA==.Дасдейл:BAAALAAECgcIEAAAAA==.',['Де']='Делариоон:BAAALAADCgIIAgAAAA==.Десеспуар:BAAALAADCgEIAQAAAA==.Деталька:BAAALAADCgEIAQAAAA==.',['Дж']='Джайла:BAAALAAECgYIEgAAAA==.Джамилья:BAACLAAFFIEIAAIRAAIIOyRoIwC7AAARAAIIOyRoIwC7AAAsAAQKgSUAAxEACAgeJpoFAFkDABEACAgeJpoFAFkDABIAAgjoHZARALAAAAAA.Джедер:BAAALAAECgYIBwAAAA==.Джульете:BAAALAAECgYIDQAAAA==.',['Ди']='Диомед:BAAALAAECgYICwAAAA==.',['До']='Докторджагер:BAAALAADCgcIBwAAAA==.',['Др']='Дракулета:BAAALAAECggICgAAAA==.Друидяка:BAAALAAECgYIBwAAAA==.Друшот:BAAALAAECgYICAAAAA==.',['Ду']='Духтэнна:BAAALAADCgEIAQAAAA==.',['Дх']='Дхани:BAAALAAECgMIBQAAAA==.',['Дю']='Дюлок:BAACLAAFFIEGAAMQAAIIOBL6EQCYAAAQAAII2g36EQCYAAAOAAII/BC4LACXAAAsAAQKgRkAAw4ABggdHzhGAPMBAA4ABgh3HThGAPMBABAABAgLG9BFADQBAAAA.',['Дя']='Дяочань:BAAALAAECgYIEQAAAA==.',['Ев']='Евгрейв:BAAALAAECgQIBgAAAA==.',['Ег']='Еготрусики:BAAALAAECgUIBwAAAA==.',['Ер']='Ерихремарк:BAAALAAECgQIBAAAAA==.',['Жг']='Жгучая:BAAALAADCgUIBQAAAA==.',['За']='Зализнякус:BAAALAAECgEIAQAAAA==.Захилон:BAAALAAECggICAAAAA==.',['Зе']='Зельда:BAABLAAECoEeAAMGAAcIwxWOQACwAQAGAAcIYxWOQACwAQATAAUIDA0EGgDtAAAAAA==.',['Зл']='Злобинпавел:BAAALAAECggICAAAAA==.',['Ив']='Иввар:BAAALAADCggIHQAAAA==.',['Из']='Изих:BAAALAAECggIEAAAAA==.',['Ил']='Иливар:BAAALAADCgYIDAAAAA==.Иллиданподан:BAAALAAECgEIAQABLAAECggIHAARAHAeAA==.Иллинеилли:BAAALAAECggIBgAAAA==.Ильячума:BAAALAAECgIIAgAAAA==.',['Им']='Иммиладрес:BAAALAAECgYICwABLAAECggIHAAUAJsWAA==.',['Ин']='Инлаб:BAABLAAECoEYAAIVAAYITxTMKACKAQAVAAYITxTMKACKAQAAAA==.Интернал:BAAALAAECgEIAQABLAAFFAIICAAOADYVAA==.',['Ио']='Ионси:BAABLAAECoEVAAMWAAYIaiCfGADgAQAWAAYIcB+fGADgAQACAAQIkxXq6wAGAQAAAA==.Иотимагиуса:BAAALAADCgcIBwAAAA==.',['Ир']='Ирэнин:BAAALAAECgYIBgAAAA==.',['Йа']='Йакан:BAACLAAFFIEJAAIQAAMIqhL5AgDwAAAQAAMIqhL5AgDwAAAsAAQKgTYAAxAACAgKJIEDACgDABAACAgKJIEDACgDAA4AAwjuFri1AJ0AAAAA.',['Ка']='Камлай:BAAALAAECgMIAwAAAA==.Камлайджин:BAAALAADCgUIBQAAAA==.Каранаатур:BAAALAAECgYIBgABLAAFFAIICAAOADYVAA==.Каратедо:BAACLAAFFIEWAAIXAAUIMBIVBQBlAQAXAAUIMBIVBQBlAQAsAAQKgSsAAhcACAjiHxQHAOACABcACAjiHxQHAOACAAAA.Кардонадор:BAAALAAFFAIIAgAAAA==.Карона:BAABLAAECoEUAAIYAAYIpAr9PAD2AAAYAAYIpAr9PAD2AAAAAA==.Катиара:BAACLAAFFIEGAAIEAAMIvQdmBgC+AAAEAAMIvQdmBgC+AAAsAAQKgSgAAgQACAjMHNkOAJgCAAQACAjMHNkOAJgCAAAA.',['Кв']='Квантум:BAAALAADCggIHQAAAA==.',['Ке']='Келльма:BAAALAAECgcIEgAAAA==.Кетрира:BAAALAAECggIBgAAAA==.',['Кл']='Клиана:BAAALAADCggIIAAAAA==.',['Ко']='Колобус:BAACLAAFFIELAAIZAAMIZBalAQDuAAAZAAMIZBalAQDuAAAsAAQKgSkAAhkACAhJHioDALkCABkACAhJHioDALkCAAAA.Конверсы:BAABLAAECoEfAAMaAAcIRRhcFwDcAQAaAAcIRRhcFwDcAQAbAAMIgwV5/wBuAAAAAA==.Конфуцийй:BAAALAAFFAIIAgABLAAFFAIICAAOADYVAA==.Корокум:BAAALAAECgYIDwABLAAFFAIICAAOADYVAA==.Королькуни:BAAALAADCgUICAAAAA==.Корускон:BAAALAAFFAIIBAABLAAFFAIICAAOADYVAA==.Корхаг:BAAALAAECggIEAAAAA==.Костня:BAAALAAECgYIBgABLAAECgcIFgAHAFITAA==.',['Кр']='Криганец:BAAALAADCgcIDQAAAA==.Крутов:BAACLAAFFIEGAAIYAAIIlAcRFgBVAAAYAAIIlAcRFgBVAAAsAAQKgSgAAxgACAjaDnkmAI0BABgACAjaDnkmAI0BAAsAAwi6ARxAATQAAAAA.Крэйзишам:BAABLAAECoEjAAMHAAcICRs3LgAuAgAHAAcICRs3LgAuAgAUAAYIsiCwOgAIAgAAAA==.',['Кс']='Кситрас:BAAALAAECgEIAQAAAA==.',['Кт']='Ктотуттопдпс:BAACLAAFFIEVAAMcAAYICSCDBQCRAQAcAAUIghiDBQCRAQAMAAUIcx7RCwBBAQAsAAQKgTcAAwwACAgcJjIPAAsDAAwACAgJJjIPAAsDABwACAiRIhIOAOYCAAAA.Ктупха:BAABLAAECoEhAAMDAAgIHBK8FADPAQADAAgIHBK8FADPAQACAAEIhgT2YAEQAAAAAA==.',['Кэ']='Кэйнхёрст:BAAALAAECgYIEQAAAA==.Кэйтилин:BAABLAAECoEXAAIOAAcIsRdTTADcAQAOAAcIsRdTTADcAQAAAA==.',['Ла']='Лавинка:BAABLAAECoEbAAIUAAcIMglUpwD0AAAUAAcIMglUpwD0AAAAAA==.Ламберинн:BAABLAAECoEnAAMYAAgI/BkAEwA4AgAYAAgI/BkAEwA4AgALAAUIKQjd9ADTAAAAAA==.',['Ле']='Ледисирения:BAAALAAECgQIBQAAAA==.',['Ли']='Лиодель:BAABLAAECoEpAAIQAAgIkxXhFQAtAgAQAAgIkxXhFQAtAgAAAA==.Лиоссиан:BAACLAAFFIEKAAIJAAIIsR9WFwC4AAAJAAIIsR9WFwC4AAAsAAQKgSoAAgkACAicJVIDAHMDAAkACAicJVIDAHMDAAAA.Лиролич:BAAALAADCggIDgAAAA==.',['Ло']='Лойд:BAAALAAECgEIAQAAAA==.',['Лю']='Лютохладд:BAACLAAFFIEXAAIHAAYIECPkAQBgAgAHAAYIECPkAQBgAgAsAAQKgTcAAgcACAiqJq4BAIUDAAcACAiqJq4BAIUDAAAA.',['Ма']='Максимхелен:BAAALAADCgcIBwAAAA==.Малайбель:BAAALAADCggIFQAAAA==.Мастдаггер:BAAALAADCggICAAAAA==.',['Ме']='Мегачпок:BAAALAAECgYICQAAAA==.Мейтонг:BAAALAAECgMIAwAAAA==.Мертвячогг:BAACLAAFFIEXAAMQAAYIuw6dAgD/AAAQAAMIbxWdAgD/AAAOAAMICAhrGwDkAAAsAAQKgTcAAxAACAiEIigGAO0CABAACAiEIigGAO0CAA4ABQiFER6JAC8BAAAA.',['Ми']='Мирида:BAABLAAECoEiAAIUAAcIiArxmAARAQAUAAcIiArxmAARAQAAAA==.Мишути:BAAALAAECgYIBgAAAA==.',['Мо']='Моля:BAAALAADCggIEgAAAA==.Монахдима:BAAALAAECgQIBwAAAA==.Морегрызз:BAACLAAFFIEJAAIdAAMI5AutCADYAAAdAAMI5AutCADYAAAsAAQKgS0AAh0ACAhGGWkOAFoCAB0ACAhGGWkOAFoCAAAA.Морнгрин:BAABLAAECoEoAAINAAgITB++BAC5AgANAAgITB++BAC5AgAAAA==.Мотенька:BAAALAAECgYIBgABLAAECggIKwAeAHcZAA==.',['Мя']='Мята:BAAALAADCgYIDAABLAAECgYIFQAUANgjAA==.',['Нб']='Нбом:BAAALAAFFAIIAgAAAA==.',['Но']='Новулус:BAAALAAECgYIEgAAAA==.Нодримка:BAAALAAECgMIBgAAAA==.',['Ну']='Нуаргримуар:BAACLAAFFIERAAMQAAYIwRgtAADwAQAQAAUIuRstAADwAQAOAAEI5AkiPwBTAAAsAAQKgTMAAxAACAjpJb8AAHoDABAACAjpJb8AAHoDAA4ABQicGA9uAHUBAAAA.',['Оз']='Озаренние:BAAALAAECgYIEgAAAA==.Озулдан:BAAALAADCggICAAAAA==.',['Па']='Пастилаон:BAAALAAECgYIBwAAAA==.',['Пе']='Перчила:BAABLAAECoEfAAIMAAcI8hWvegCJAQAMAAcI8hWvegCJAQAAAA==.Перышко:BAABLAAECoErAAIeAAcIdxkxKQD5AQAeAAcIdxkxKQD5AQAAAA==.',['Пл']='Плами:BAAALAADCggIFAABLAAFFAMIEAAGACYXAA==.Плинто:BAAALAAECgUIBQAAAA==.',['По']='Полууокер:BAAALAADCgcIDAAAAA==.Посларкимаг:BAABLAAECoEcAAMRAAgIcB43JQCiAgARAAgIWh03JQCiAgAEAAMIUR4UUgD2AAAAAA==.',['Пр']='Проблиск:BAAALAADCgcIBwAAAA==.Пряник:BAAALAAECgYIBgAAAA==.',['Пу']='Пуцэ:BAAALAAECggIEgABLAAECggIHAAUAJsWAA==.',['Ра']='Ракетта:BAABLAAECoEhAAIKAAcI/gdLTgBZAQAKAAcI/gdLTgBZAQAAAA==.Рассвет:BAAALAADCgYIBgABLAAECgYIFQAUANgjAA==.Рафаэлка:BAABLAAECoEnAAIMAAgIziTGBQBRAwAMAAgIziTGBQBRAwAAAA==.',['Ре']='Ретардпалл:BAAALAADCgQIBAAAAA==.',['Ри']='Риани:BAAALAAECgcIDQAAAA==.',['Ро']='Робовариус:BAAALAADCggICAABLAAFFAMIBgAJANwNAA==.Робомага:BAABLAAECoElAAIRAAgIrxkiNABdAgARAAgIrxkiNABdAgABLAAFFAMIBgAJANwNAA==.Робошмаль:BAABLAAECoEWAAIcAAcICBptLgD1AQAcAAcICBptLgD1AQABLAAFFAMIBgAJANwNAA==.Рогаттие:BAABLAAECoEyAAIfAAgIDiXSAgBIAwAfAAgIDiXSAgBIAwAAAA==.Родомилл:BAAALAADCggIEAAAAA==.Розплата:BAAALAADCgQIBAAAAA==.Рокнролльщик:BAACLAAFFIEIAAIgAAIIcBQlEwCaAAAgAAIIcBQlEwCaAAAsAAQKgS8AAiAACAibIhkFAAADACAACAibIhkFAAADAAAA.',['Са']='Салэнс:BAAALAADCggIGgAAAA==.Сандерс:BAAALAAECgYIDQAAAA==.Сарумон:BAAALAAECgcIEgAAAA==.',['Св']='Свееточка:BAAALAAECgYIDQAAAA==.Свигибран:BAAALAADCggIEAABLAAECggIJwAYAPwZAA==.',['Се']='Сейфирот:BAAALAADCggIDgAAAA==.Селанта:BAAALAAECgYIDAABLAAECgcIGQAUAN8XAA==.',['Ск']='Скептис:BAAALAADCgcICwAAAA==.',['Сл']='Сладкаясоль:BAAALAADCgUIBQABLAAFFAIIBgALAPYRAA==.',['Сн']='Сникарс:BAAALAADCgYIBwAAAA==.',['Со']='Сонгост:BAAALAADCggIDgAAAA==.',['Сп']='Спелус:BAAALAADCgQIBAABLAADCggIKAAPAAAAAA==.',['Ст']='Старыйпредок:BAABLAAECoEhAAILAAgIRRLyZgDtAQALAAgIRRLyZgDtAQAAAA==.Столичная:BAAALAADCgEIAQAAAA==.',['Су']='Судзуширо:BAAALAAECgEIAQAAAA==.Сурица:BAAALAAECgMIBAAAAA==.',['Сэ']='Сэлли:BAAALAADCggICAAAAA==.',['Та']='Тадга:BAABLAAECoEbAAIUAAcIFxSZXQCgAQAUAAcIFxSZXQCgAQABLAAFFAQIDQARANkZAA==.Тафан:BAACLAAFFIEGAAILAAII9hEaLgCeAAALAAII9hEaLgCeAAAsAAQKgTUAAgsACAgvJEQQACUDAAsACAgvJEQQACUDAAAA.Тафандру:BAAALAAECgYICAABLAAFFAIIBgALAPYRAA==.',['Те']='Темасин:BAABLAAECoEcAAILAAcIbRR+fwC6AQALAAcIbRR+fwC6AQAAAA==.Тенсейга:BAABLAAECoEZAAMhAAcIhhjeCwDaAQAhAAcINxXeCwDaAQAOAAYIRBh9XgChAQAAAA==.Тестостерон:BAAALAAECggIBgABLAAFFAIIBAAPAAAAAA==.',['Тх']='Тхорн:BAAALAAECggIEAABLAAECggIEAAPAAAAAA==.',['Ур']='Урхаал:BAAALAAECgYICAAAAA==.',['Фл']='Фланкех:BAABLAAECoEnAAILAAcISBxmXgD/AQALAAcISBxmXgD/AQAAAA==.',['Фр']='Франческотру:BAABLAAECoEWAAIHAAcIUhOXQQDTAQAHAAcIUhOXQQDTAQAAAA==.',['Фу']='Фужн:BAABLAAECoEfAAMJAAgIpiEjGQDRAgAJAAgI6CAjGQDRAgANAAYI3yEgCABSAgAAAA==.',['Ха']='Хазот:BAAALAAECgQIBQAAAA==.Хайнвин:BAAALAAECgcIEwAAAA==.Халчиха:BAAALAADCggICAABLAAECgYIDQAPAAAAAA==.Хантерия:BAAALAADCgUIBQABLAAFFAMICwAZAGQWAA==.Хатигацу:BAAALAAECgYIBAAAAA==.',['Хе']='Хелентесс:BAAALAAECgYICwAAAA==.Хехе:BAAALAAECgcIBwAAAA==.',['Хо']='Хограйда:BAACLAAFFIEIAAIOAAIINhUGLACZAAAOAAIINhUGLACZAAAsAAQKgRkAAg4ACAiwHwMYANwCAA4ACAiwHwMYANwCAAAA.',['Хр']='Хромие:BAAALAAECgIIAgAAAA==.',['Хс']='Хсанкора:BAACLAAFFIEGAAIEAAIItxm+CQCfAAAEAAIItxm+CQCfAAAsAAQKgSAAAgQACAi8HcoLAMMCAAQACAi8HcoLAMMCAAAA.',['Ци']='Цирела:BAABLAAECoEeAAIXAAYIlRafHQB7AQAXAAYIlRafHQB7AQAAAA==.',['Чи']='Чилящийвар:BAAALAAECgYICQABLAAFFAIIBwAcACsNAA==.Чилящийхант:BAACLAAFFIEHAAIcAAIIKw0LMQAtAAAcAAIIKw0LMQAtAAAsAAQKgS8AAhwACAiNGnwwAOkBABwACAiNGnwwAOkBAAAA.Чимчи:BAABLAAECoEVAAIUAAYI2CMQLAA+AgAUAAYI2CMQLAA+AgAAAA==.',['Чп']='Чпонька:BAAALAADCggIFQAAAA==.',['Ша']='Шайни:BAAALAAECgMIBAAAAA==.Шайнни:BAAALAAECgEIAgAAAA==.Шамея:BAAALAAECgIIAgAAAA==.Шарункаан:BAAALAAFFAIIAgABLAAFFAIICAAOADYVAA==.',['Шн']='Шнырапыра:BAAALAADCggIIAAAAA==.',['Шэ']='Шэнноу:BAACLAAFFIEXAAMTAAYIryQWAAAgAgATAAUIxyQWAAAgAgAKAAEIRx4YIgBNAAAsAAQKgTcAAxMACAgyJkEAAHMDABMACAgyJkEAAHMDAAoAAQhOH85/AFkAAAAA.',['Эв']='Эвклипд:BAABLAAECoEfAAIVAAcIERnqHQDhAQAVAAcIERnqHQDhAQAAAA==.',['Эк']='Экзипауэр:BAAALAADCggIFwAAAA==.',['Эл']='Элемануэль:BAACLAAFFIEIAAIHAAYIXworDAArAQAHAAYIXworDAArAQAsAAQKgR8AAgcABwiDGo4wACECAAcABwiDGo4wACECAAAA.',['Эс']='Эсскемо:BAABLAAECoEcAAIUAAgImxa1QAD0AQAUAAgImxa1QAD0AQAAAA==.Эстиа:BAACLAAFFIEVAAICAAYIjhoMAwBAAgACAAYIjhoMAwBAAgAsAAQKgTQAAgIACAjgJQkIAE4DAAIACAjgJQkIAE4DAAAA.',['Эш']='Эшара:BAABLAAECoEkAAMdAAgIsxQgFAAHAgAdAAgIsxQgFAAHAgAVAAcIVQyELgBgAQAAAA==.',['Юн']='Юневерсал:BAAALAAECgYICQAAAA==.',['Ян']='Янешаманка:BAABLAAECoEZAAIUAAcI3xc1SwDTAQAUAAcI3xc1SwDTAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end