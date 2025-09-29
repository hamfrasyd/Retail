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
 local lookup = {'Paladin-Protection','DemonHunter-Havoc','DeathKnight-Frost','Mage-Arcane','Mage-Frost','Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Shadow','Warrior-Fury','Warrior-Protection','Monk-Mistweaver','Paladin-Retribution','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Vengeance','Evoker-Preservation','Hunter-Survival','Druid-Balance','Priest-Holy','Rogue-Outlaw','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Warrior-Arms','Druid-Feral','Druid-Restoration','Monk-Windwalker','Mage-Fire','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Evoker-Augmentation',}; local provider = {region='EU',realm='Галакронд',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ав']='Авсянко:BAAALAAECgYIBgAAAA==.',['Аз']='Азалекс:BAAALAAECggIAwAAAA==.Азатрон:BAAALAADCgQIBAAAAA==.',['Ай']='Айдаданик:BAAALAADCgcICwAAAA==.Айкаа:BAAALAAECgQICAAAAA==.Айэнир:BAAALAAECgYIEwAAAA==.',['Ал']='Алексаня:BAAALAAECgQICgAAAA==.Алексафокси:BAAALAAECgMIBgAAAA==.Алексиос:BAAALAAECgYIDAAAAA==.Аликея:BAAALAAFFAEIAQAAAA==.Альвансор:BAACLAAFFIEHAAIBAAMI0gixCQClAAABAAMI0gixCQClAAAsAAQKgSgAAgEACAg9FXsaAO4BAAEACAg9FXsaAO4BAAAA.Альгаран:BAAALAAECgYIDgAAAA==.Альфалорд:BAABLAAECoEhAAICAAcIQRRMagDGAQACAAcIQRRMagDGAQAAAA==.',['Ам']='Амассис:BAAALAAECgcIBwAAAA==.Аматори:BAAALAADCggIDQAAAA==.Амацухиконэ:BAABLAAECoEbAAIDAAcIhBzSWQARAgADAAcIhBzSWQARAgAAAA==.Америикан:BAAALAADCggIDgAAAA==.Амралиме:BAAALAADCggIDwAAAA==.',['Ан']='Анамниз:BAAALAADCgEIAQABLAAECggIHQAEAKYcAA==.Андрюшамаг:BAACLAAFFIEHAAIFAAIIMA2BEQCAAAAFAAIIMA2BEQCAAAAsAAQKgSsAAgUACAiXG8AOAJkCAAUACAiXG8AOAJkCAAAA.Анен:BAAALAADCggICgAAAA==.Анимишка:BAAALAAECgEIAQAAAA==.Анкариус:BAAALAADCggIFQABLAAFFAIIBwACAKQJAA==.Анлерия:BAAALAADCgYIBgAAAA==.Аннимечник:BAAALAAECgYIBgAAAA==.Анфирида:BAAALAAECgEIAQAAAA==.',['Ар']='Аримка:BAABLAAECoEWAAIGAAcIDw2MhQA7AQAGAAcIDw2MhQA7AQAAAA==.Аринневья:BAAALAADCggICQAAAA==.Арнигольд:BAACLAAFFIEMAAMHAAUI2RcGCAA6AQAHAAQI8hkGCAA6AQAIAAMIsg83FgDRAAAsAAQKgSwAAwgACAgxI5ERAPwCAAgACAgEI5ERAPwCAAcACAgtHnAXAJQCAAAA.Архимид:BAAALAAECgYIEQAAAA==.',['Ас']='Аскольда:BAAALAAECgEIAQABLAAECggIJAAJAF4PAA==.Асмодусик:BAAALAADCgUIBQAAAA==.Асстериксс:BAAALAADCggIEAAAAA==.Астерий:BAAALAADCggIDwAAAA==.',['Ат']='Атомныйвар:BAAALAAECgcIDQAAAA==.Атраксар:BAAALAADCggICAABLAAECgcIGwAKAAcbAA==.Атраксарон:BAAALAADCggIEAABLAAECgcIGwAKAAcbAA==.Атраксдк:BAAALAAECgYIBgABLAAECgcIGwAKAAcbAA==.Атраксдх:BAAALAADCggIGAABLAAECgcIGwAKAAcbAA==.Атраксик:BAABLAAECoEbAAMKAAcIBxszMABHAgAKAAcIBxszMABHAgALAAYIIhAzQwArAQAAAA==.Атраксмонк:BAABLAAECoEZAAIMAAcI1CGcCQCsAgAMAAcI1CGcCQCsAgABLAAECgcIGwAKAAcbAA==.Атракспал:BAAALAADCggIDgABLAAECgcIGwAKAAcbAA==.Атраксприст:BAAALAADCggIEQABLAAECgcIGwAKAAcbAA==.Атраксхант:BAAALAADCggIKAABLAAECgcIGwAKAAcbAA==.Атраксшам:BAAALAADCggIFAABLAAECgcIGwAKAAcbAA==.',['Аф']='Афисто:BAAALAAECgYIDAABLAAECggIHQAEAKYcAA==.Афистэ:BAABLAAECoEdAAIEAAgIphxzLgB3AgAEAAgIphxzLgB3AgAAAA==.',['Аэ']='Аэлира:BAAALAADCggICAAAAA==.',['Ба']='Банни:BAAALAADCgEIAQAAAA==.',['Бе']='Белледар:BAAALAAECgMIBgAAAA==.Бенка:BAABLAAECoEnAAINAAgIEiIWFwABAwANAAgIEiIWFwABAwAAAA==.Беннингтон:BAAALAAECgQIBAABLAAECgYICgAOAAAAAA==.',['Би']='Бирель:BAAALAADCgIIAgAAAA==.Бистро:BAABLAAECoEZAAIFAAcIkBMXKQC8AQAFAAcIkBMXKQC8AQAAAA==.',['Бл']='Блайд:BAACLAAFFIEJAAIPAAIIJBa0CgCLAAAPAAIIJBa0CgCLAAAsAAQKgSoAAg8ACAifHxsIALoCAA8ACAifHxsIALoCAAAA.',['Бо']='Боксджан:BAACLAAFFIEGAAIFAAIIxhrtCgCZAAAFAAIIxhrtCgCZAAAsAAQKgRgAAgUACAjwH+MIAPACAAUACAjwH+MIAPACAAAA.Бонфина:BAAALAADCggIGAAAAA==.',['Бр']='Бргр:BAAALAAECgYIBgAAAA==.Бреинор:BAAALAADCgYICwAAAA==.',['Бу']='Буранги:BAAALAAECgcIBwAAAA==.',['Ва']='Вакулыч:BAABLAAECoEfAAIGAAgIGBrPLgAzAgAGAAgIGBrPLgAzAgAAAA==.Валиария:BAACLAAFFIEGAAICAAIImRO0KgCaAAACAAIImRO0KgCaAAAsAAQKgR0AAwIABwh/GmVmAM4BAAIABwh/GmVmAM4BABAAAQiMDalXADEAAAAA.Вартида:BAAALAAECgQIDgAAAA==.Васянпотато:BAAALAADCgcICAAAAA==.',['Ве']='Веикики:BAAALAAECgEIAQAAAA==.Вельзебасков:BAAALAADCgIIAgABLAAECgcIEAAOAAAAAA==.Вельзедепп:BAAALAAECgYIBgABLAAECgcIEAAOAAAAAA==.Вельзекавилл:BAAALAAECgcIEAAAAA==.Вельзеонтьев:BAAALAAECgYIEgABLAAECgcIEAAOAAAAAA==.',['Вл']='Владиклохх:BAACLAAFFIEFAAIRAAMICxXWBwDoAAARAAMICxXWBwDoAAAsAAQKgRoAAhEACAhbGJwLAE4CABEACAhbGJwLAE4CAAAA.Владикнелохх:BAAALAAECgYIBgAAAA==.',['Во']='Воимяльда:BAABLAAECoEvAAIFAAgIUSOwBgAVAwAFAAgIUSOwBgAVAwABLAAFFAIIAgAOAAAAAA==.Вокинел:BAAALAAECgYIDgAAAA==.',['Ву']='Вузик:BAABLAAECoEYAAQSAAcIeRh3DAC1AQASAAYIFhR3DAC1AQAIAAcIehYbcACgAQAHAAII/hNllQBsAAAAAA==.Вузшам:BAAALAAECgYIDgAAAA==.',['Га']='Галимеда:BAAALAADCggIDgAAAA==.Галинваген:BAAALAADCgcIDQAAAA==.Гареро:BAAALAAECgYIBgAAAA==.Гарис:BAAALAAECgQIBwAAAA==.Гарос:BAAALAADCgUIBwAAAA==.Гартрам:BAABLAAECoEnAAICAAgIaB8sIgC5AgACAAgIaB8sIgC5AgAAAA==.Гачибуйный:BAAALAAECgMIBAAAAA==.Гачинелло:BAAALAAECgIIAgAAAA==.',['Гв']='Гвоздар:BAAALAADCgUIBQAAAA==.',['Ге']='Гевея:BAAALAADCgUIBQAAAA==.Генрианна:BAABLAAECoEbAAIHAAgIuB1KFQCnAgAHAAgIuB1KFQCnAgAAAA==.',['Ги']='Гибон:BAAALAAECgMIAwAAAA==.',['Го']='Гонор:BAAALAAECgYIDQAAAA==.',['Гу']='Гутелист:BAABLAAECoEkAAMPAAgInhFwGgCHAQAPAAgInhFwGgCHAQADAAUIrwINHAGWAAAAAA==.',['Да']='Дагнии:BAAALAADCgMIAwABLAAECggIHwALAPkbAA==.Далайла:BAAALAADCgcIDAAAAA==.Даркнери:BAAALAAECgQIBAABLAAECgYIEAAOAAAAAA==.Дарм:BAAALAAECggIEQAAAA==.Дарос:BAAALAADCggICAAAAA==.',['Де']='Дедсукуб:BAABLAAECoEbAAIQAAcIQSKHCwB5AgAQAAcIQSKHCwB5AgAAAA==.Деймосин:BAAALAAECgYIEQABLAAFFAYIFgAKALsWAA==.Дескудище:BAAALAADCgEIAQABLAAECgYIBwAOAAAAAA==.',['Дж']='Джозити:BAAALAADCgQIBAAAAA==.Джонблейд:BAABLAAECoEmAAITAAgIXiB4GQBsAgATAAgIXiB4GQBsAgAAAA==.Джоханс:BAAALAADCgcIBwAAAA==.Джудихобс:BAABLAAECoEnAAIUAAgIeQqsWwBGAQAUAAgIeQqsWwBGAQAAAA==.',['Ди']='Димон:BAAALAADCgUIBQAAAA==.Динсергеевна:BAAALAAECgYIDQAAAA==.Дитябурь:BAAALAADCggICAABLAAFFAIIAgAOAAAAAA==.',['До']='Дозик:BAAALAADCggIDwAAAA==.',['Др']='Драмси:BAAALAAECggICAAAAA==.Дреллиана:BAAALAAECgYIEwAAAA==.Дринт:BAAALAAECgEIAgAAAA==.Друдотала:BAAALAAECgEIAQAAAA==.',['Дэ']='Дэхан:BAAALAAECggICAAAAA==.',['Ер']='Еретрея:BAAALAAECgEIAQAAAA==.',['За']='Забран:BAAALAAECgcIEwAAAA==.Заковия:BAAALAAECgYICgAAAA==.Заколино:BAACLAAFFIEHAAIVAAIIZAloBACNAAAVAAIIZAloBACNAAAsAAQKgSMAAhUACAhYFxYFAFwCABUACAhYFxYFAFwCAAAA.Занда:BAAALAAECgYIEAAAAA==.Зандалора:BAABLAAECoEbAAIUAAYILB+JMAD+AQAUAAYILB+JMAD+AQABLAAECgYIEAAOAAAAAA==.Зараги:BAAALAAECgYIDAAAAA==.Зарезать:BAAALAAECgQIBAAAAA==.',['Зв']='Зверовище:BAAALAADCggIDAAAAA==.',['Зе']='Зелебражник:BAAALAADCgcIAwAAAA==.Земфирка:BAAALAADCgMIBAAAAA==.Зерасмус:BAABLAAECoEkAAMNAAcIPBwZZQDwAQANAAcIPBwZZQDwAQABAAYITQfTPwDjAAAAAA==.Зерънар:BAAALAADCggIHQAAAA==.Зефекс:BAAALAAECgYICQAAAA==.',['Зк']='Зкнопкискилл:BAAALAAECgQIBgABLAAECgcIDwAOAAAAAA==.',['Зл']='Злая:BAACLAAFFIEGAAMIAAIIFhN2NQCCAAAIAAIIFhN2NQCCAAAHAAEInwGSMQAlAAAsAAQKgSYAAwgABwi4IaQoAHsCAAgABwhwIaQoAHsCAAcABgixFtlDAI4BAAAA.',['Ив']='Ивелденс:BAAALAADCggICgAAAA==.',['Иг']='Игнисмаг:BAAALAADCgcIDQAAAA==.',['Ик']='Икимару:BAAALAAECgEIAQABLAAECggILAAUAGAOAA==.',['Ил']='Иливстан:BAAALAAECggIBwAAAA==.Иллюмино:BAAALAAECgQIBwAAAA==.Илювафар:BAABLAAECoEVAAIUAAYI8RNuUgBpAQAUAAYI8RNuUgBpAQAAAA==.',['Ин']='Инзоске:BAABLAAECoEUAAIDAAYIPB9jlgCZAQADAAYIPB9jlgCZAQAAAA==.Инсанра:BAABLAAECoEdAAMEAAgI6wquigBPAQAEAAgI6wquigBPAQAFAAMIHAbbbABwAAAAAA==.',['Ио']='Иокаста:BAAALAADCggICAAAAA==.',['Ис']='Исиллу:BAAALAADCgUIBQABLAAECggILAAUAGAOAA==.',['Ит']='Италмас:BAAALAAECgYIBwAAAA==.',['Ка']='Кадрр:BAAALAAECgYIBgABLAAFFAMIDAAJAHAZAA==.Кайдеми:BAAALAADCgcIDAABLAAECgYICgAOAAAAAA==.Кайденс:BAAALAADCgUIBQABLAAECgYIFgAWAAgQAA==.Калдора:BAAALAADCgMIAwAAAA==.Камнезара:BAAALAADCgcICQAAAA==.Картавый:BAAALAAECgYIBgAAAA==.Кархарт:BAAALAAECgIIAgAAAA==.Катык:BAAALAAECgYIBwAAAA==.',['Ке']='Кельаран:BAABLAAECoEgAAIUAAgIwyAvEADRAgAUAAgIwyAvEADRAgAAAA==.Кертэн:BAAALAADCgEIAQAAAA==.',['Ки']='Киалла:BAAALAAECgYIDgAAAA==.Киллмонгер:BAAALAAFFAIIBAABLAAECgYICgAOAAAAAA==.Кильнадис:BAABLAAECoEZAAICAAcInwyPugAjAQACAAcInwyPugAjAQAAAA==.',['Кл']='Кларкхаос:BAAALAADCggIIQAAAA==.',['Ко']='Когараси:BAAALAAECgYICQAAAA==.Когратани:BAABLAAECoEvAAMXAAgIERygCACXAgAXAAgI7hqgCACXAgAYAAgIPBWuHQAVAgAAAA==.Колтрат:BAAALAAECggIEwAAAA==.Кольтирия:BAAALAAECgEIAQAAAA==.Контентерика:BAAALAAECgYICQABLAAECgYIFAADADwfAA==.Корейка:BAAALAAECgIIAgAAAA==.Коско:BAAALAAECgYICQAAAA==.Костабиль:BAAALAADCggICgAAAA==.Кошечка:BAAALAADCgcIBwAAAA==.',['Кр']='Кранч:BAAALAADCggICwAAAA==.Крапинка:BAAALAADCggIGAAAAA==.Крапка:BAAALAAECgYIBwAAAA==.Кризис:BAAALAAECgMIAwAAAA==.Кроаг:BAAALAADCgMIAQAAAA==.Крутобурен:BAACLAAFFIEJAAIGAAIIqRSzKgCIAAAGAAIIqRSzKgCIAAAsAAQKgSQAAgYACAhHIpcKAPsCAAYACAhHIpcKAPsCAAAA.',['Кс']='Ксавиус:BAACLAAFFIEHAAICAAIIpAkJOQCKAAACAAIIpAkJOQCKAAAsAAQKgTIAAgIACAi/Gl44AFUCAAIACAi/Gl44AFUCAAAA.',['Ку']='Куропаткина:BAAALAADCgMIAwAAAA==.Куру:BAAALAADCgcIDQAAAA==.',['Ла']='Лайтбосс:BAACLAAFFIEMAAIJAAMIcBnHDQDtAAAJAAMIcBnHDQDtAAAsAAQKgSUABAkACAjPIWMNAPoCAAkACAjPIWMNAPoCABQABgjRFuRPAHIBABkAAQgmBtk4ACMAAAAA.Лактрания:BAAALAADCgMIAwAAAA==.Лалуу:BAAALAAECgYICgABLAAECgYIEQAOAAAAAA==.Лафия:BAAALAADCgEIAQAAAA==.',['Ле']='Лемонадовна:BAAALAADCgUIBQAAAA==.Ления:BAAALAADCgYICwAAAA==.Леошама:BAAALAADCggIHAABLAAFFAIICQAGAKkUAA==.',['Ли']='Лиандея:BAAALAAECgQIAgABLAAECgYIDgAOAAAAAA==.Лианидас:BAAALAAECgYICQAAAA==.Лиантея:BAAALAAECgYIDQABLAAECgYIDgAOAAAAAA==.Лиастраза:BAAALAADCgUIBQABLAAECgYIDgAOAAAAAA==.Либравар:BAABLAAECoElAAIKAAcIBx0JKwBhAgAKAAcIBx0JKwBhAgAAAA==.Лилияройли:BAAALAADCgcIDQAAAA==.Лиляройя:BAABLAAECoEmAAMKAAgIextvKQBqAgAKAAgIIhtvKQBqAgAaAAcI1xcWDQDkAQAAAA==.Лихачок:BAAALAADCgcIBwAAAA==.',['Ло']='Локибренна:BAAALAADCgMIAwAAAA==.Локмадама:BAAALAADCggICAAAAA==.',['Лу']='Лунипал:BAAALAAECgYIBgAAAA==.Луноклык:BAAALAADCgcICgAAAA==.',['Лы']='Лысыйх:BAAALAADCgQIBAAAAA==.',['Лю']='Люкенг:BAAALAADCggICAAAAA==.Люмерия:BAAALAADCggIDwAAAA==.Люцилоки:BAAALAADCggIDwAAAA==.',['Ма']='Максэкспо:BAAALAAECggIAwAAAA==.Малиндриэль:BAAALAAECgQIBwAAAA==.Малкинское:BAAALAADCgIIAgAAAA==.Малталаэль:BAABLAAECoEUAAIDAAgIsgjrogCDAQADAAgIsgjrogCDAQAAAA==.Мамаскверны:BAAALAAECgYIDAABLAAFFAIIAgAOAAAAAA==.Манул:BAABLAAECoEjAAIbAAgItSW3AAB2AwAbAAgItSW3AAB2AwAAAA==.Маронол:BAAALAAECgEIAgABLAAECgYIBwAOAAAAAA==.Мархабо:BAAALAADCgcIBwAAAA==.Мастерчоппы:BAAALAAECgcIEwAAAA==.Мах:BAAALAADCggICAAAAA==.Машасрувкашу:BAAALAAECggICQAAAA==.',['Ме']='Медан:BAAALAADCgUIBAAAAA==.Медовик:BAAALAAECgYIDAAAAA==.Мельхиорра:BAABLAAECoEaAAMcAAcI/SAVJQApAgAcAAYI3iAVJQApAgATAAEIcQackQAvAAAAAA==.Мефистэ:BAAALAAFFAIIAgABLAAECggIHQAEAKYcAA==.',['Ми']='Миаллей:BAAALAAECgMIAwAAAA==.Микалиэль:BAAALAAECgYICwABLAAECgYIEAAOAAAAAA==.Милизея:BAAALAAECgMIBgABLAAECgYIDgAOAAAAAA==.Милостливая:BAAALAADCggIFQAAAA==.Миничика:BAAALAADCgcIBwABLAAFFAQICQAXAGANAA==.Миравинг:BAABLAAECoEkAAINAAgIxhohPQBaAgANAAgIxhohPQBaAgAAAA==.Мирсалис:BAAALAAECgEIAQAAAA==.Мистут:BAAALAAECgEIAQABLAAECggIHwALAPkbAA==.Мистута:BAAALAAECgYIEAABLAAECggIHwALAPkbAA==.Митронэль:BAAALAADCggIFgAAAA==.Мифистель:BAABLAAECoEfAAIDAAgI6RyQPQBeAgADAAgI6RyQPQBeAgABLAAFFAEIAQAOAAAAAA==.',['Мо']='Молтудир:BAABLAAECoEdAAIBAAgIThvEDwBcAgABAAgIThvEDwBcAgAAAA==.Монфрель:BAAALAADCgIIAgAAAA==.Мор:BAAALAAECgUICAAAAA==.Моризель:BAAALAADCgYIBgAAAA==.',['Му']='Мухен:BAAALAADCggIDgAAAA==.',['Мь']='Мьютед:BAAALAADCggIDAAAAA==.',['На']='Наггар:BAABLAAECoEhAAIKAAcIEBV6SADjAQAKAAcIEBV6SADjAQAAAA==.Назимар:BAAALAADCgcIDgAAAA==.',['Не']='Небоюсь:BAAALAADCgEIAQAAAA==.Неистовец:BAAALAAECggICgAAAA==.Некрололикон:BAAALAADCgcIBwAAAA==.Немуния:BAABLAAECoEjAAMdAAgI7QcPLwBcAQAdAAgI7QcPLwBcAQAMAAcIAw23JABMAQAAAA==.',['Ни']='Никапли:BAAALAAECgcIDQAAAA==.Никиба:BAAALAAECgYIDAAAAA==.Никиса:BAABLAAECoEXAAIeAAgIRgMjEADQAAAeAAgIRgMjEADQAAAAAA==.',['Но']='Нотянка:BAABLAAECoEbAAIGAAcIwgiSpgD2AAAGAAcIwgiSpgD2AAAAAA==.',['Ну']='Нуонами:BAAALAADCgYIBgAAAA==.Нуринель:BAAALAADCggICgAAAA==.Нутела:BAAALAAECggIEQAAAA==.',['Об']='Оберонн:BAAALAADCggICAAAAA==.',['Ов']='Оверлордка:BAAALAADCgUIBQAAAA==.',['Од']='Одала:BAAALAADCgYIBgAAAA==.',['Ож']='Ожесинь:BAAALAADCgIIAgAAAA==.',['Ом']='Омбудсмен:BAAALAADCgQICAAAAA==.',['Он']='Онаар:BAAALAADCggICAABLAAECgcIEQAOAAAAAA==.',['Ор']='Орлангуресса:BAABLAAECoEfAAMfAAcIFB4MEQBZAgAfAAcIFB4MEQBZAgAgAAMIRwsVwQB3AAAAAA==.',['От']='Отецмихаил:BAAALAADCgYIEQAAAA==.',['Па']='Патентован:BAAALAAECggICQAAAA==.',['Пе']='Пепэ:BAAALAADCgYIBgAAAA==.',['Пи']='Пивнойсись:BAAALAAECgMIBQAAAA==.Пиошка:BAAALAADCgcIDgAAAA==.Пирохидреза:BAAALAADCgIIAgABLAAECgYIFAADADwfAA==.',['По']='Подлыйарктас:BAAALAAECggIDAAAAA==.Пойнт:BAAALAADCggIDQAAAA==.Полимаро:BAAALAAECgYIBwAAAA==.Пони:BAABLAAECoESAAIDAAYIGg+ywwBPAQADAAYIGg+ywwBPAQAAAA==.Поохотимся:BAAALAAECggIDQAAAA==.Постреляем:BAABLAAECoEnAAIIAAgIzxS9aACxAQAIAAgIzxS9aACxAQAAAA==.',['Пр']='Прайдо:BAAALAAECgQICwAAAA==.Простосашка:BAAALAAECgcIBwAAAA==.Профексор:BAAALAADCggICAABLAAECgYIBwAOAAAAAA==.',['Пс']='Психолёт:BAAALAAECgYIBgAAAA==.',['Пь']='Пьюриоса:BAAALAADCgcICAAAAA==.',['Пё']='Пёжить:BAAALAAECgYIBgAAAA==.',['Ра']='Радиум:BAAALAAECgYIBgAAAA==.Разгельдяй:BAAALAADCgYIBgAAAA==.Расангул:BAAALAAECgMIAwABLAAECggIHQAEAKYcAA==.Растадруль:BAAALAADCgUIBgAAAA==.',['Ре']='Редгонкинг:BAAALAAECgYIDwABLAAFFAUIEwAGAFcYAA==.Рейерсон:BAABLAAECoEUAAIbAAcI0x7jCwBvAgAbAAcI0x7jCwBvAgAAAA==.Рейхризалора:BAAALAAECgMIBAABLAAECgYIFAADADwfAA==.Рекзон:BAAALAADCgEIAQAAAA==.Рефограз:BAAALAAECgQIBAAAAA==.',['Ри']='Ричардт:BAAALAAFFAIIAgAAAA==.',['Ро']='Роганрос:BAAALAADCgcIBwABLAAECgcIEQAOAAAAAA==.Рогафф:BAAALAADCggIJgAAAA==.Ронелли:BAAALAADCgEIAQAAAA==.Рониши:BAABLAAECoEUAAQhAAgIzRBAJADaAQAhAAgIzRBAJADaAQAiAAEIxAJ0FwArAAARAAEICgelOgAnAAABLAAECgYICgAOAAAAAA==.',['Ру']='Руклеона:BAAALAADCggICAAAAA==.Рускиймясник:BAAALAAECgQIBAAAAA==.',['Са']='Сагым:BAAALAADCgMIAwAAAA==.Садрия:BAAALAAECgcIDgAAAA==.Сайдс:BAAALAADCggICAAAAA==.Самкакдемон:BAAALAADCgUICAAAAA==.Саханна:BAAALAAECgYICgAAAA==.',['Св']='Светоубийца:BAAALAAECgYIDgAAAA==.Святобор:BAAALAAECgYIDQAAAA==.',['Се']='Сельм:BAAALAAECgMIAgAAAA==.Сенягоблинус:BAABLAAECoEgAAILAAgI1RB7MACPAQALAAgI1RB7MACPAQAAAA==.Сеонайд:BAAALAADCgcIBwAAAA==.Серебьо:BAAALAADCgEIAQAAAA==.',['Си']='Сибирь:BAAALAAECgYIBgAAAA==.Сильванела:BAABLAAECoEYAAIUAAgIoR3oFwCTAgAUAAgIoR3oFwCTAgAAAA==.Сильванич:BAABLAAECoEUAAINAAYIURtsaQDoAQANAAYIURtsaQDoAQAAAA==.Сильвиния:BAAALAAECgYIBgABLAAECgYIDgAOAAAAAA==.Ситариис:BAAALAADCgYIBwABLAAFFAIIAgAOAAAAAA==.',['Ск']='Скватчхантер:BAAALAADCggICAABLAAECggICAAOAAAAAA==.Сквернолап:BAAALAADCgcIBwAAAA==.Скульптор:BAAALAADCggICAAAAA==.Скуфус:BAABLAAECoEZAAMHAAYI1hwjRgCEAQAHAAYIfRcjRgCEAQAIAAUIFRgCqAAvAQAAAA==.',['Сл']='Сларион:BAAALAAECgYIBgAAAA==.',['См']='Смайлфейс:BAAALAAECggIDQAAAA==.',['Сн']='Снайкен:BAAALAADCggICAAAAA==.',['Со']='Сольварпа:BAAALAADCgQIBAAAAA==.',['Ст']='Старыйхазгор:BAAALAADCgcIBwAAAA==.',['Су']='Сумомо:BAAALAAECgIIAgAAAA==.Сургумия:BAAALAAECggIDgAAAA==.',['Сэ']='Сэни:BAAALAADCggICAAAAA==.',['Та']='Тайнюша:BAAALAAECggICAAAAA==.Таравангиан:BAAALAAECgYIBgAAAA==.Тарэлко:BAAALAAECggIBgAAAA==.Тасфиания:BAAALAADCgYIBgABLAAECgYIFAADADwfAA==.',['Те']='Текиллашот:BAAALAADCgcIEQAAAA==.Телуурт:BAAALAADCgUIBwAAAA==.Теньсавы:BAABLAAECoEoAAIcAAcIfgyrZQAkAQAcAAcIfgyrZQAkAQAAAA==.Теранол:BAAALAAECgYIBgAAAA==.Тесанндра:BAAALAAECgYIBgAAAA==.Тесарион:BAAALAAECggICAAAAA==.',['Ти']='Тиливина:BAAALAADCgMIBAAAAA==.Тим:BAACLAAFFIEJAAIHAAIIFxTUHACHAAAHAAIIFxTUHACHAAAsAAQKgSoAAgcACAjCG9oXAJACAAcACAjCG9oXAJACAAAA.Тима:BAAALAADCggIFQAAAA==.Тимас:BAAALAADCggICAAAAA==.Тинтакля:BAAALAAECgYIBgAAAA==.Тиссота:BAAALAADCggICQABLAAECgYIFAADADwfAA==.',['То']='Томентос:BAAALAAECgYIDwAAAA==.Тохсик:BAAALAAECgYIEwAAAA==.',['Тр']='Трамадар:BAABLAAECoEyAAMgAAgIghsaJACRAgAgAAgIaRoaJACRAgAfAAcIBRHuJADGAQAAAA==.Трамыч:BAAALAAECgYIBgAAAA==.Труд:BAAALAAECgIIAgAAAA==.',['Ту']='Турзадирана:BAAALAAECgYIEgABLAAECgYIFAADADwfAA==.',['Тё']='Тёмныйангел:BAAALAADCggICAAAAA==.',['Ук']='Украинець:BAAALAADCgMIAwAAAA==.',['Уо']='Уоллаах:BAAALAADCgYICgAAAA==.Уотер:BAAALAAECgYIBgAAAA==.',['Ух']='Ухуткалеш:BAAALAAECgEIAQABLAAECgYIFAADADwfAA==.',['Фа']='Фальнуаци:BAAALAADCggICgABLAAECgYIFAADADwfAA==.Фантастика:BAAALAADCggICAAAAA==.Фантомим:BAAALAAECggIEgAAAA==.',['Фи']='Филренон:BAACLAAFFIEGAAIDAAMIlxhWFgD9AAADAAMIlxhWFgD9AAAsAAQKgS8AAgMACAhwJJMLADgDAAMACAhwJJMLADgDAAAA.Фирамир:BAACLAAFFIEIAAIKAAIINw81JgCYAAAKAAIINw81JgCYAAAsAAQKgR8AAgoACAg/HbAkAIUCAAoACAg/HbAkAIUCAAAA.Фиско:BAAALAAECggIDQABLAAFFAcIIwAgAJsiAA==.Фистинк:BAAALAADCgIIAgAAAA==.',['Фо']='Фонбарон:BAAALAADCggICAAAAA==.',['Фр']='Фрейя:BAABLAAECoErAAIhAAgI7BloGgAzAgAhAAgI7BloGgAzAgAAAA==.Фрейян:BAAALAAECgUIBwAAAA==.Фростмодерн:BAAALAADCgIIAgABLAADCgYIAgAOAAAAAA==.',['Фэ']='Фэйсролл:BAAALAAFFAIIAgAAAA==.',['Ха']='Халазия:BAAALAAECgEIAQABLAAECgcIKQAgAFMNAA==.Хамер:BAAALAADCggICQAAAA==.Хантик:BAABLAAECoEhAAIIAAgIMQswhgBxAQAIAAgIMQswhgBxAQAAAA==.',['Хб']='Хбикс:BAAALAAECgYIDwAAAA==.',['Хе']='Хеймнир:BAABLAAECoEfAAINAAgItxbDVQAUAgANAAgItxbDVQAUAgAAAA==.',['Хи']='Хикори:BAABLAAECoEkAAIdAAgI8RgJEgBmAgAdAAgI8RgJEgBmAgAAAA==.Хиликус:BAAALAADCggIDgAAAA==.Хилс:BAAALAADCgYIBgAAAA==.Хитрий:BAAALAAECgMIAwAAAA==.',['Хэ']='Хэйро:BAABLAAECoEXAAIGAAcIPhcyTADQAQAGAAcIPhcyTADQAQAAAA==.Хэнкоок:BAAALAADCgYIBgAAAA==.',['Ча']='Чаймести:BAAALAADCgQIBAAAAA==.Чаризард:BAAALAADCggIEAAAAA==.Чаёк:BAAALAAECggIDQAAAA==.',['Чи']='Чистий:BAAALAADCggICAABLAAECgMIAwAOAAAAAA==.',['Чп']='Чпуньк:BAAALAADCgcIBwAAAA==.',['Чу']='Чучелинно:BAAALAAECgUICAABLAAECgYIFAADADwfAA==.',['Ша']='Шабумда:BAAALAADCgQIBwAAAA==.Шайтанатт:BAAALAAECgIIAgAAAA==.Шалупонька:BAAALAADCgYICQAAAA==.Шамалдред:BAAALAAECgcIEQAAAA==.',['Шб']='Шбурко:BAAALAADCggICAAAAA==.',['Ше']='Шетонар:BAAALAAECgEIAQABLAAECggIIAAUAMMgAA==.',['Шэ']='Шэйхе:BAABLAAECoEbAAIiAAgIBw7BCAC8AQAiAAgIBw7BCAC8AQAAAA==.',['Эг']='Эгони:BAABLAAECoEVAAMUAAYIlxIvXQBBAQAUAAYIkBAvXQBBAQAZAAEIgRwXLQBOAAAAAA==.',['Эй']='Эйс:BAACLAAFFIEKAAMRAAMI2ghECgDAAAARAAMI2ghECgDAAAAhAAMIXxbuEgCWAAAsAAQKgSgAAyEACAgoJFUGACEDACEACAgoJFUGACEDABEACAglF48NACkCAAAA.',['Эк']='Эксмортус:BAAALAAECgMIBAAAAA==.',['Эл']='Элиуриас:BAABLAAECoEaAAMQAAcISwpMMgD2AAACAAcIwQghwAAWAQAQAAcIxwdMMgD2AAAAAA==.',['Эм']='Эмолайф:BAAALAADCgQIBAABLAAECgYIFAADADwfAA==.',['Эн']='Энеас:BAAALAADCgQIBQAAAA==.Энибель:BAAALAAECgYIEQAAAA==.',['Эр']='Эринома:BAAALAADCgMIBgAAAA==.Эркек:BAAALAAECgMIAwAAAA==.',['Эс']='Эсеторо:BAAALAAECgUIBwAAAA==.Эслурия:BAAALAADCggIBwAAAA==.',['Эт']='Этодд:BAAALAADCggICAAAAA==.Этон:BAAALAADCggIDAABLAAECgYICQAOAAAAAA==.',['Юк']='Юкина:BAAALAAECgMIBQAAAA==.',['Юн']='Юно:BAAALAAECgUIBQAAAA==.',['Яд']='Ядик:BAACLAAFFIEJAAMXAAQIYA2oDACaAAAXAAMIKQ+oDACaAAAYAAMI3gp+FQCXAAAsAAQKgSMAAxcACAhVIngGAMcCABcACAjTHngGAMcCABgACAgtH0kTAHUCAAAA.',['Яр']='Ярмина:BAAALAAECgYIDgAAAA==.',['Ящ']='Ящер:BAAALAAECgYICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end