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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Druid-Balance','Warrior-Fury','Hunter-BeastMastery','Druid-Feral','Warrior-Protection','Evoker-Devastation','Priest-Holy','Warlock-Destruction','Paladin-Holy','Druid-Guardian','Paladin-Retribution','Paladin-Protection','DeathKnight-Frost','Shaman-Elemental','Warlock-Demonology','Rogue-Subtlety','Rogue-Assassination','Mage-Frost','Evoker-Preservation','Priest-Shadow','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Hunter-Survival','Monk-Brewmaster','Evoker-Augmentation','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','Hunter-Marksmanship','Priest-Discipline','DemonHunter-Havoc','Warrior-Arms',}; local provider = {region='EU',realm='Борейскаятундра',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Ав']='Аварина:BAAALAADCgcIBwAAAA==.Авесалон:BAAALAAECgYIBgAAAA==.Авонис:BAAALAAECgcICwAAAA==.',['Аг']='Агниан:BAAALAADCgYIBgAAAA==.',['Ад']='Адскийкиллер:BAAALAADCgcIBwABLAAECgcICgABAAAAAA==.',['Ай']='Айри:BAAALAAECgYIBgAAAA==.Айсанэфенди:BAAALAADCgEIAQAAAA==.',['Ак']='Акунокихцира:BAAALAAFFAEIAQAAAA==.',['Ал']='Алексисвайс:BAABLAAECoEfAAICAAYIHxbWawCiAQACAAYIHxbWawCiAQAAAA==.Алеф:BAAALAADCggICQAAAA==.Алефант:BAAALAADCgIIAQAAAA==.Алкобор:BAAALAADCggICAAAAA==.Алкосова:BAABLAAECoElAAIDAAgI9CCoDADxAgADAAgI9CCoDADxAgAAAA==.Альбирис:BAAALAADCgYIBQAAAA==.',['Ам']='Амменра:BAAALAADCgEIAQAAAA==.Амфея:BAAALAADCgcIBwAAAA==.',['Ан']='Анаком:BAAALAADCggIFgAAAA==.Антилайф:BAAALAAECgIIAgAAAA==.',['Ар']='Ариадна:BAAALAAECgYIBgAAAA==.Аркарир:BAABLAAECoEYAAIEAAcIog+nWgCoAQAEAAcIog+nWgCoAQAAAA==.Арката:BAAALAAECgMIAwAAAA==.Армагедон:BAAALAAECgIIAgAAAA==.Артелак:BAABLAAECoEaAAIFAAYI/hj/oQA7AQAFAAYI/hj/oQA7AQAAAA==.Артемидда:BAABLAAECoEZAAIFAAYI3AXgxwDrAAAFAAYI3AXgxwDrAAAAAA==.Арука:BAAALAAECgYICAAAAA==.Архидруид:BAABLAAECoEfAAIGAAcIdRgKEwD9AQAGAAcIdRgKEwD9AQAAAA==.',['Ас']='Аскх:BAAALAAECgYIDAAAAA==.Астра:BAABLAAECoEqAAIHAAgIKCPuBAAyAwAHAAgIKCPuBAAyAwAAAA==.',['Аф']='Афанаревший:BAAALAADCgQIBAAAAA==.Афгуст:BAABLAAECoEWAAIIAAcIFRCrKgCoAQAIAAcIFRCrKgCoAQAAAA==.Аффторитет:BAAALAAECggICAAAAA==.',['Ац']='Ацкийдрактир:BAAALAADCggICAABLAAECgcICgABAAAAAA==.',['Аш']='Ашвейл:BAAALAAECgQIBAAAAA==.Аштара:BAAALAAECgEIAQAAAA==.',['Ба']='Бабкатитана:BAAALAAECgYIDAABLAAFFAIIBwACAIMWAA==.Бабовна:BAAALAAECgIIAwABLAAECgcIFQAJABkUAA==.Базукович:BAAALAADCgIIAgAAAA==.Барбелот:BAAALAADCgUIBQAAAA==.Бардюр:BAAALAAECgYIEAAAAA==.Бармалини:BAABLAAECoEVAAIKAAcI9AtHbwByAQAKAAcI9AtHbwByAQAAAA==.Бартонбёргер:BAAALAAECgIIAgAAAA==.',['Бе']='Беймур:BAAALAAECgIIAwAAAA==.',['Би']='Биастмастер:BAAALAAECgIIAgAAAA==.Бибастрел:BAAALAAECggIDQAAAA==.Билик:BAAALAADCggICgAAAA==.Бирский:BAAALAADCgcIDQAAAA==.',['Бл']='Блэквейл:BAABLAAECoElAAILAAgIACDtCADGAgALAAgIACDtCADGAgAAAA==.',['Бо']='Бокалвинишка:BAABLAAECoElAAIMAAgI0CIJAgAnAwAMAAgI0CIJAgAnAwAAAA==.Боксерёног:BAAALAAECgcIEwAAAA==.Большойгрызь:BAAALAAECgYIDQAAAA==.Бомбоклат:BAAALAADCgQIBAABLAAECgYICgABAAAAAA==.Ботася:BAACLAAFFIESAAMNAAUI+Q0gBwCQAQANAAUIJQ0gBwCQAQAOAAUIvAaQFwA8AAAsAAQKgScAAw0ACAhEIe4dAN0CAA0ACAhEIe4dAN0CAA4AAwirCm1UAGEAAAAA.',['Бр']='Брбррпатапим:BAAALAAECgYICgAAAA==.Броксигара:BAABLAAECoEsAAIHAAgIDSNWBwAOAwAHAAgIDSNWBwAOAwAAAA==.',['Бу']='Бургеркинг:BAAALAADCggICAAAAA==.Бутылкарома:BAAALAAECgYIDAAAAA==.',['Ва']='Вайб:BAAALAADCgYIBgAAAA==.Василиск:BAAALAAECgYIBgAAAA==.Вафлянутый:BAAALAADCggICAAAAA==.',['Вг']='Вгрызка:BAAALAADCgYIBgAAAA==.',['Ве']='Венэйбл:BAAALAAFFAEIAQAAAA==.Венявялый:BAAALAAECgYICQAAAA==.Вертусеич:BAAALAAECgIIAgABLAAECgcIGwAPAMEeAA==.Вертусей:BAABLAAECoEbAAIPAAcIwR7TPgBaAgAPAAcIwR7TPgBaAgAAAA==.',['Ви']='Визей:BAAALAADCggIDgAAAA==.Визил:BAAALAADCgUIAwAAAA==.Викз:BAAALAADCggIDAAAAA==.Винсольм:BAABLAAECoEaAAIPAAcIdR27RABJAgAPAAcIdR27RABJAgAAAA==.',['Во']='Водковар:BAAALAAECgMIAwAAAA==.Войпель:BAACLAAFFIEcAAIQAAYIJR/sAgAvAgAQAAYIJR/sAgAvAgAsAAQKgR4AAhAACAhVJUgFAFwDABAACAhVJUgFAFwDAAAA.Вольвелёля:BAAALAAFFAIIAgAAAA==.Воробейй:BAAALAAECggIAwAAAA==.',['Вр']='Вреднюля:BAABLAAECoEaAAIGAAYI7xKfHgB4AQAGAAYI7xKfHgB4AQAAAA==.',['Вс']='Всалат:BAAALAAECgYIBgAAAA==.',['Га']='Гаалеэль:BAAALAADCggIFAAAAA==.Гадюкинс:BAABLAAECoEgAAIRAAgI7RZFEgBNAgARAAgI7RZFEgBNAgAAAA==.Гачибосс:BAACLAAFFIENAAMSAAUIlhNqAwCTAQASAAUIlhNqAwCTAQATAAMIagd3CwDjAAAsAAQKgSQAAxIACAhBIIkHAK0CABIACAj9HYkHAK0CABMACAhoG5AXAEoCAAAA.',['Ге']='Гензо:BAAALAADCgcICAAAAA==.Герал:BAAALAAECgcICQAAAA==.',['Гл']='Глубокославх:BAAALAAECgEIAQAAAA==.',['Го']='Гожира:BAAALAADCggICAAAAA==.Голтаррог:BAAALAAECgQIBAAAAA==.',['Гр']='Громовина:BAABLAAECoElAAIQAAgIohsGHwCJAgAQAAgIohsGHwCJAgAAAA==.Гротерр:BAAALAAECgMIAwAAAA==.',['Гу']='Гуржейка:BAAALAAECgIIAgAAAA==.',['Да']='Дайкокутэн:BAAALAADCggIIQAAAA==.Дайонизос:BAAALAADCgQIBAAAAA==.Данбу:BAAALAAECgYIDQAAAA==.Дарион:BAAALAAECgMIBQAAAA==.Даркме:BAAALAAECgcIDwAAAA==.Даужповезло:BAAALAAECgEIAQAAAA==.',['Де']='Дедлукич:BAABLAAECoEWAAIFAAcIbBPVdgCRAQAFAAcIbBPVdgCRAQAAAA==.Дедтитана:BAACLAAFFIEHAAICAAIIgxZYMACdAAACAAIIgxZYMACdAAAsAAQKgS4AAwIACAjEI+ARAAkDAAIACAjEI+ARAAkDABQAAwjlEdBlAI8AAAAA.Дезл:BAAALAADCggICAAAAA==.Деллая:BAAALAADCggICAAAAA==.Демарт:BAAALAAECgcIBwAAAA==.Демонагонии:BAAALAADCgcIBwAAAA==.Демонмаг:BAABLAAECoEjAAIUAAgIGySNBAA8AwAUAAgIGySNBAA8AwAAAA==.Дентко:BAAALAAECgYICAAAAA==.Дестролокии:BAAALAAECgMIAwAAAA==.',['Дж']='Джеекк:BAAALAADCgUIBQAAAA==.Джезабель:BAAALAAECgYIDAAAAA==.Дживиай:BAAALAADCgQIBAAAAA==.Джинтас:BAAALAAECgcIDwAAAA==.Джиудичи:BAAALAADCgYIBgAAAA==.Джонигалт:BAACLAAFFIEKAAIQAAQIfxQvDAArAQAQAAQIfxQvDAArAQAsAAQKgTAAAhAACAj6IgsKADADABAACAj6IgsKADADAAAA.',['Ди']='Диикей:BAAALAAECgYIEQABLAAFFAMIDQAEAHUiAA==.Дикеечка:BAAALAADCggIFQAAAA==.Дикийкал:BAAALAAECgIIAgAAAA==.Диктатус:BAAALAADCgcICgAAAA==.',['До']='Дональдпамп:BAAALAADCggICwAAAA==.Дорла:BAAALAAECgUICAAAAA==.',['Др']='Дракгатс:BAABLAAECoEhAAIIAAcIgReyIgDmAQAIAAcIgReyIgDmAQAAAA==.Драккарисс:BAABLAAECoEdAAMVAAcIUiBiCACMAgAVAAcIUiBiCACMAgAIAAQI3hLFPwAeAQAAAA==.Другарика:BAAALAAECgMIAwAAAA==.Дрыгоног:BAAALAADCgEIAQAAAA==.',['Дф']='Дфлеш:BAABLAAECoEeAAINAAgIDBaWVAAXAgANAAgIDBaWVAAXAgAAAA==.',['Дэ']='Дэва:BAAALAAECgcIDgAAAA==.Дэлайт:BAAALAAECgIIAgABLAAFFAMIDQAEAHUiAA==.',['Дя']='Дядьковася:BAAALAAECgcIEAAAAA==.Дядяпрок:BAAALAADCgUIBQAAAA==.',['Ек']='Екарныйбабай:BAAALAAECggIDgABLAAECggIIwAWANEZAA==.',['Еш']='Ешкинкрошкин:BAABLAAECoEXAAIXAAcIOBd6DAABAgAXAAcIOBd6DAABAgAAAA==.',['Жа']='Жанвальжан:BAAALAAECgYICgAAAA==.Жанполье:BAAALAADCgIIAgAAAA==.',['Жу']='Жупус:BAAALAADCggIEAABLAAECgcIFAAYANwgAA==.',['Жы']='Жыреч:BAAALAAECgMIBAAAAA==.',['За']='Заорду:BAAALAAECgEIAQAAAA==.Защитник:BAAALAADCgYIBgAAAA==.',['Зе']='Зеттайкен:BAAALAAECgYIEAAAAA==.',['Зо']='Зовузомби:BAABLAAECoEhAAIZAAgI4xXsEgAfAgAZAAgI4xXsEgAfAgAAAA==.',['Зр']='Зряваракачал:BAAALAADCggIHwAAAA==.',['Зу']='Зулджол:BAAALAADCggIEAAAAA==.Зулралу:BAABLAAECoEfAAMQAAcIqxBNSgCxAQAQAAcIbRBNSgCxAQAXAAYIugh3GQAfAQAAAA==.',['Зы']='Зын:BAABLAAECoEWAAMHAAgILgcjUQDsAAAHAAgI0gYjUQDsAAAEAAQIjwIAAAAAAAAAAA==.',['Иг']='Игуменныч:BAAALAADCggIDgAAAA==.',['Ил']='Илленгоф:BAAALAAECggIEAAAAA==.Ильичовский:BAAALAAECgcIEgAAAA==.Илэрион:BAAALAADCgcIDgAAAA==.Илюшпа:BAAALAAECgcIDgAAAA==.',['Им']='Импуссибле:BAAALAADCgcIBwAAAA==.',['Ин']='Индива:BAAALAADCgQIBAAAAA==.Иномарка:BAAALAAECgYIBwAAAA==.Инфлюенс:BAAALAAECgUICQAAAA==.Инчантикс:BAAALAAECgcICwAAAA==.',['Ио']='Иошихиро:BAAALAAECgcICgAAAA==.',['Ис']='Исильдор:BAABLAAECoErAAIEAAgI2CP8CwAuAwAEAAgI2CP8CwAuAwAAAA==.',['Ит']='Итебявылечу:BAAALAADCgcIBwAAAA==.',['Йу']='Йувакз:BAAALAADCggIEAAAAA==.Йувикз:BAABLAAECoElAAIaAAgIYSTBAABZAwAaAAgIYSTBAABZAwAAAA==.',['Ка']='Каболкар:BAAALAAECgMIAwAAAA==.Кагаяку:BAAALAAECgYIBgAAAA==.Каерея:BAAALAAECggIDgAAAA==.Кайраз:BAAALAADCggIDwAAAA==.Какаскил:BAAALAAECgYICAABLAAECggILAAHAA0jAA==.Калапусик:BAAALAAECgYIBgAAAA==.Календулриан:BAAALAAECgYICwAAAA==.Камазкун:BAAALAAECggIDgAAAA==.Камнепух:BAAALAAECggIAgAAAA==.Канакун:BAABLAAECoEnAAMNAAcI3BDjxgA5AQANAAYIvw7jxgA5AQALAAcIoAPjRQADAQAAAA==.Канаэль:BAAALAAECggIDAAAAA==.Карабиныч:BAABLAAECoEmAAIFAAgIJxs1PAAuAgAFAAgIJxs1PAAuAgAAAA==.Каринторн:BAAALAADCggICAAAAA==.Карриба:BAAALAAECgYICQAAAA==.Касскыр:BAAALAAFFAIIBAAAAA==.Кацопис:BAAALAAECgYIDAAAAA==.',['Кв']='Квестунчик:BAAALAAECgEIAQAAAA==.',['Ке']='Кейрисс:BAACLAAFFIEFAAIKAAIIeQexNQCHAAAKAAIIeQexNQCHAAAsAAQKgSgAAgoACAjzEBVHAO8BAAoACAjzEBVHAO8BAAAA.',['Кз']='Кзварлок:BAABLAAECoEUAAMRAAcIgCCGKAC0AQAKAAYIwB29QwD8AQARAAUIliGGKAC0AQAAAA==.',['Ки']='Килерок:BAAALAADCggICAAAAA==.Кимдаали:BAAALAADCgcIDgAAAA==.Киристраз:BAAALAAECgYICAAAAA==.Кифи:BAAALAADCgcIBwAAAA==.',['Кл']='Клэптрэп:BAAALAADCgcIBwAAAA==.Ключиломалка:BAAALAAECgQIBAABLAAFFAUIEgAbAG4YAA==.',['Ко']='Кобретти:BAAALAADCggIFQAAAA==.Ковальскй:BAABLAAECoEiAAQVAAcI8BnSEwDDAQAVAAcI8BnSEwDDAQAIAAII7RHCUgBwAAAcAAII4RD0FQA/AAAAAA==.Козби:BAAALAAFFAEIAQAAAA==.Конрад:BAAALAADCgcICgAAAA==.Коорин:BAAALAAECggIAgAAAA==.Коппытень:BAABLAAECoElAAQDAAcIShgELwDYAQADAAcIixUELwDYAQAGAAcIfBRTFwDGAQAdAAMIwhJ8kgCjAAAAAA==.Копчуша:BAABLAAECoEYAAIaAAYIjRKbDgCSAQAaAAYIjRKbDgCSAQAAAA==.Кордак:BAAALAAECgYIBgAAAA==.Корешилидана:BAAALAADCgcIBwAAAA==.Косихо:BAAALAADCggICgAAAA==.',['Кр']='Красиваяшея:BAAALAAECgIIAgAAAA==.Кратконогая:BAAALAADCgUIBQAAAA==.Краямоейраны:BAAALAAECgYIBgAAAA==.Крокозябра:BAAALAAECgMIBAABLAAECgYICgABAAAAAA==.Крошкин:BAAALAAECgcIEQAAAA==.',['Кт']='Ктокуда:BAABLAAECoEZAAIUAAcI9xRsJgDMAQAUAAcI9xRsJgDMAQAAAA==.',['Ку']='Кувшино:BAAALAAECgYICQAAAA==.Кудажмать:BAAALAAECgMIBQABLAAECggIGQAJAEwVAA==.Кузёныш:BAACLAAFFIEKAAIeAAMIiBzBBgD9AAAeAAMIiBzBBgD9AAAsAAQKgScAAx4ACAjnI/8CAC8DAB4ACAjnI/8CAC8DAB8ABAjKBltGAK4AAAAA.Кукловод:BAAALAAECggIEAAAAA==.Куколдунчик:BAAALAAECggIEwAAAA==.Куми:BAAALAADCggIDAAAAA==.Кунница:BAAALAADCgUIBwAAAA==.',['Кы']='Кыцуня:BAABLAAECoEdAAIWAAcI2wZzVgA1AQAWAAcI2wZzVgA1AQAAAA==.',['Кэ']='Кэрриган:BAAALAADCgcICAAAAA==.',['Ла']='Лайв:BAABLAAECoElAAIeAAgILhUWFQD6AQAeAAgILhUWFQD6AQAAAA==.Лаймонд:BAABLAAECoEaAAUdAAgIdBSLUABpAQAdAAcILhOLUABpAQAGAAQI/QYINACTAAADAAMIJAwrdwCFAAAMAAIIVxOsJgBuAAAAAA==.',['Ле']='Легенданадц:BAAALAAECgEIAgAAAA==.Лесми:BAAALAAECgYIEAAAAA==.Леснаяфрея:BAAALAADCggICwAAAA==.',['Ли']='Лиен:BAABLAAECoEnAAINAAcIjBwtTQAsAgANAAcIjBwtTQAsAgAAAA==.Лилланте:BAAALAADCgcIBwAAAA==.Лиллилол:BAAALAAECggICAABLAAECggIHAAUAHcXAA==.Лиссэн:BAAALAAECgYIEgAAAA==.',['Ло']='Лобаста:BAABLAAECoEaAAIgAAYIFxuUGwCsAQAgAAYIFxuUGwCsAQAAAA==.Лонька:BAACLAAFFIEHAAISAAUIdxfQCwCfAAASAAUIdxfQCwCfAAAsAAQKgRgAAhIACAgCH1oHALICABIACAgCH1oHALICAAEsAAUUBQgJAAoAhRQA.Лоролькич:BAAALAAECggICgABLAAECggIHAAUAHcXAA==.',['Лу']='Лугальмарад:BAABLAAECoEdAAIFAAcI3BByhQByAQAFAAcI3BByhQByAQAAAA==.',['Ля']='Лять:BAAALAAFFAQIAQAAAA==.',['Ма']='Мааргрета:BAAALAADCggICAAAAA==.Мавпа:BAAALAADCgMIAwAAAA==.Магон:BAAALAADCgcICAAAAA==.Мадейв:BAAALAAECggIEQAAAA==.Максичай:BAACLAAFFIEQAAMUAAUIgxcSAQDBAQAUAAUIgxcSAQDBAQACAAIIFwkAAAAAAAAsAAQKgUIAAxQACAjoJHICAGIDABQACAjoJHICAGIDAAIABghwEk11AIgBAAAA.Макхани:BAAALAADCgMIAwAAAA==.Малбрукс:BAAALAADCggICwABLAAECgcIIgAVAPAZAA==.Малунис:BAAALAAECgMIAwAAAA==.Марсилес:BAACLAAFFIEOAAIhAAUIIhAYCAA5AQAhAAUIIhAYCAA5AQAsAAQKgTUAAiEACAg3HXkYAIsCACEACAg3HXkYAIsCAAAA.Маффий:BAABLAAECoEfAAIJAAgIABdUKAApAgAJAAgIABdUKAApAgAAAA==.',['Ме']='Мелития:BAAALAADCgcICwAAAA==.Мелкота:BAAALAAECgYIBgAAAA==.Мельнкорн:BAAALAADCgcICQAAAA==.Менендес:BAAALAAECgYIEAAAAA==.Мерьем:BAACLAAFFIEQAAIJAAQIFwwzCwAlAQAJAAQIFwwzCwAlAQAsAAQKgSsAAwkACAieFloyAPUBAAkACAieFloyAPUBABYAAgjwBPiCAEsAAAAA.Мечомрубилка:BAAALAAECgYICgABLAAFFAUIEgAbAG4YAA==.',['Ми']='Мидиаль:BAAALAAECgYIEgAAAA==.Милкивейчикс:BAAALAAECgYICAABLAAECgYICgABAAAAAA==.Милли:BAAALAADCggICAABLAADCggIFgABAAAAAA==.Миллилол:BAABLAAECoEcAAMUAAgIdxcsKgC2AQACAAgIRhCaXADOAQAUAAgIoxEsKgC2AQAAAA==.Минерал:BAAALAADCgEIAQAAAA==.Мифистофиль:BAAALAADCggICgAAAA==.',['Мо']='Мозг:BAAALAADCgcIBwAAAA==.Молотокбика:BAAALAADCgYICwAAAA==.Молюск:BAAALAADCggIFAAAAA==.Монохром:BAABLAAECoEWAAMfAAcIahKWLQBmAQAfAAYIRBSWLQBmAQAbAAcIyQgxJwAeAQAAAA==.Моорти:BAAALAADCgYIBgAAAA==.Морфеа:BAAALAAECgYIEQAAAA==.',['Мр']='Мраксевера:BAAALAAECggIBwAAAA==.Мрамра:BAAALAADCgMIBAAAAA==.',['Му']='Мужтитана:BAAALAADCgcIBwAAAA==.',['Мэ']='Мэйрил:BAAALAADCggIEAAAAA==.',['Мя']='Мягкаялапкаа:BAAALAADCgcICwAAAA==.',['На']='Нагрогом:BAAALAADCgcICgAAAA==.Надалия:BAAALAADCggIGQAAAA==.Назарбаев:BAACLAAFFIEIAAINAAIINCUlGgC7AAANAAIINCUlGgC7AAAsAAQKgTEAAg0ACAisJc0FAGYDAA0ACAisJc0FAGYDAAAA.Найкпро:BAAALAAECgcIEAAAAA==.Найрра:BAAALAADCgcIDQAAAA==.Нананана:BAAALAADCggICQAAAA==.Наполеон:BAAALAAECgIIAgAAAA==.',['Не']='Невий:BAACLAAFFIERAAINAAUIPx1qBADeAQANAAUIPx1qBADeAQAsAAQKgScAAg0ACAhUJc4GAGADAA0ACAhUJc4GAGADAAAA.Негорюю:BAAALAAECgYIEwAAAA==.Немодель:BAABLAAECoEUAAIKAAcIjQudbAB5AQAKAAcIjQudbAB5AQAAAA==.Необия:BAACLAAFFIEFAAIIAAIItSJpDgDBAAAIAAIItSJpDgDBAAAsAAQKgSYAAggABwjAI7oMAMsCAAgABwjAI7oMAMsCAAAA.Нероняймыло:BAAALAAECgEIAQAAAA==.Нескорена:BAAALAADCgQIBAAAAA==.Нефритянка:BAACLAAFFIESAAIbAAUIbhiBBACHAQAbAAUIbhiBBACHAQAsAAQKgSQAAhsACAj3GtoNAFECABsACAj3GtoNAFECAAAA.Нехаленна:BAAALAAECgIIAwAAAA==.',['Ни']='Ниолетта:BAAALAAECgcIEgAAAA==.Нипадохля:BAAALAADCggICAABLAAECgYIGgAgABcbAA==.Ниссин:BAABLAAECoElAAMeAAcIChFSIAB1AQAeAAcIChFSIAB1AQAfAAcI9hLtNwAgAQAAAA==.',['Но']='Норагаими:BAAALAADCgcIDAAAAA==.Нория:BAAALAADCggIHAAAAA==.',['Ну']='Нуканука:BAAALAAECgUICgAAAA==.',['Нь']='Ньютон:BAAALAAECgUIBQABLAAECggILAAHAA0jAA==.',['Нэ']='Нэйджи:BAAALAADCgUIBQAAAA==.',['Ню']='Нюркес:BAACLAAFFIEGAAINAAIIlhHYKwChAAANAAIIlhHYKwChAAAsAAQKgRcAAg0ACAifGL5FAEACAA0ACAifGL5FAEACAAAA.Нюркин:BAAALAAECgcIDQAAAA==.',['Ол']='Олета:BAACLAAFFIERAAMKAAUIuhPKDACkAQAKAAUIuhPKDACkAQARAAEIQAocJABLAAAsAAQKgSoAAwoACAhTIs4TAPYCAAoACAh1Ic4TAPYCABEABgifHQEoALYBAAAA.',['Он']='Онести:BAAALAADCgQIBAABLAAECgQIBAABAAAAAA==.Онигукоосас:BAAALAADCgcIBwAAAA==.',['Ор']='Орбена:BAACLAAFFIEJAAIEAAUIwg89EgDtAAAEAAUIwg89EgDtAAAsAAQKgR4AAgQACAjvHdEkAIQCAAQACAjvHdEkAIQCAAAA.Оргазмика:BAAALAAECgYIBgABLAAECggIHAAUAHcXAA==.Орргазм:BAACLAAFFIEIAAIIAAMInQe7EQCcAAAIAAMInQe7EQCcAAAsAAQKgSYAAggACAjuGK0VAGICAAgACAjuGK0VAGICAAAA.',['Оу']='Оушенмай:BAAALAADCgcIBwAAAA==.',['Па']='Паларт:BAABLAAECoEfAAMOAAgIrSGCBwDlAgAOAAgIfSGCBwDlAgANAAYI0B8CkQCaAQAAAA==.Пандаманда:BAAALAAECgcIEQAAAA==.Пандашмыг:BAABLAAECoEeAAIQAAgIHCNxCQA1AwAQAAgIHCNxCQA1AwAAAA==.Патиу:BAAALAADCgUIBQAAAA==.',['Пе']='Пельмешек:BAAALAAECgUIBQAAAA==.Пеяни:BAAALAADCggIHQAAAA==.',['Пи']='Пивашчи:BAAALAADCgcIBwAAAA==.Пилз:BAAALAAECgQIBAAAAA==.',['Пл']='Плюс:BAAALAADCgcICwAAAA==.',['По']='Погорелый:BAABLAAECoEkAAIKAAgIiRtnIwCVAgAKAAgIiRtnIwCVAgAAAA==.Подстолпешим:BAABLAAECoEVAAIUAAcICxoWHgAEAgAUAAcICxoWHgAEAgAAAA==.Поиск:BAABLAAECoEaAAMLAAgI3wtgNABkAQALAAcIGg1gNABkAQANAAgImgIxBAGrAAAAAA==.Порожнеча:BAAALAAECgYIBgAAAA==.',['Пп']='Пптимаа:BAAALAAECgUICQAAAA==.',['Пр']='Простодру:BAAALAAECgcICwAAAA==.',['Пт']='Птимма:BAAALAAECggIEwAAAA==.Птюша:BAABLAAECoEWAAMJAAcIQhvBLQANAgAJAAcI2BjBLQANAgAiAAIISCFFHgDAAAAAAA==.',['Пу']='Пузище:BAAALAADCgcIBgAAAA==.Пупарик:BAAALAAECgQIBAAAAA==.',['Пё']='Пёрфектдемон:BAACLAAFFIEPAAIjAAMIrSKuDQArAQAjAAMIrSKuDQArAQAsAAQKgTYAAiMACAh7JusDAHADACMACAh7JusDAHADAAAA.',['Ра']='Радамир:BAAALAAECgUIBQAAAA==.Радтхарани:BAAALAADCgcIDQAAAA==.Радфемка:BAABLAAECoEiAAMYAAgIwB+NEwC7AgAYAAgIwB+NEwC7AgAQAAYILA7AYQBhAQAAAA==.Райталион:BAACLAAFFIEIAAQcAAMILCD+AgAUAQAcAAMILBz+AgAUAQAIAAIIyR+sDwCtAAAVAAEIUBaeEwBJAAAsAAQKgRcAAwgACAgLIQkWAF4CAAgABwiZIQkWAF4CABwAAQgnHacUAFcAAAAA.Рандгрид:BAAALAADCgIIAgAAAA==.Ратха:BAAALAADCggIDwAAAA==.',['Ре']='Рейдарк:BAAALAADCgcIBwAAAA==.Рейлганх:BAAALAAECggIDwABLAAECggIHAAUAHcXAA==.Рентар:BAAALAAECggIDQAAAA==.',['Ри']='Ривенель:BAAALAADCgMIAwAAAA==.',['Ро']='Робгад:BAAALAADCgMIAwAAAA==.Розоваяпопка:BAAALAAECgcIBwAAAA==.Роклин:BAAALAAECgYIDwAAAA==.Россини:BAABLAAECoEkAAIFAAcImR3SQQAbAgAFAAcImR3SQQAbAgAAAA==.Роувена:BAAALAAECgQICAAAAA==.Роху:BAAALAADCgYICwAAAA==.',['Ру']='Руваа:BAAALAAECgYICgAAAA==.Румс:BAAALAADCgYICQAAAA==.',['Рь']='Рьюджи:BAABLAAECoEZAAIjAAcIwRBJdwCpAQAjAAcIwRBJdwCpAQAAAA==.',['Рэ']='Рэйенисс:BAAALAADCggIEgAAAA==.Рэмбосоид:BAAALAADCggICAAAAA==.',['Са']='Саленлион:BAAALAAECggIDQAAAA==.Салтушка:BAABLAAECoEfAAMLAAcIihf+HwDkAQALAAcIihf+HwDkAQAOAAYIzRHOLgBRAQABLAAFFAUIEAAUAIMXAA==.Сангра:BAAALAAECgYIBgAAAA==.Санэлиа:BAAALAAECgUIBgAAAA==.',['Св']='Свампик:BAABLAAECoEjAAIWAAgI0RlvHgBhAgAWAAgI0RlvHgBhAgAAAA==.Светопепел:BAAALAADCggICAAAAA==.Свойчелик:BAAALAADCgYIBgAAAA==.Святойдионис:BAAALAAECgMIAwABLAAECggILAAHAA0jAA==.Святополк:BAAALAADCggIEAAAAA==.',['Се']='Себела:BAAALAADCgUIBQAAAA==.Сенайя:BAAALAAECgEIAQAAAA==.Сенамира:BAAALAAECgIIAgAAAA==.Сестрёнкарег:BAAALAADCgYIBgAAAA==.',['Си']='Сивийдуб:BAAALAAECgMIAgAAAA==.Силльвана:BAABLAAECoEUAAIFAAYICxAXoQA9AQAFAAYICxAXoQA9AQAAAA==.Сильверпайн:BAABLAAECoEjAAIQAAYIjw9ZYABmAQAQAAYIjw9ZYABmAQAAAA==.Симбера:BAAALAADCgYICwAAAA==.Синдрен:BAAALAADCgcICAAAAA==.Синийдедуля:BAABLAAECoEpAAIhAAgINhaZLQD6AQAhAAgINhaZLQD6AQAAAA==.Ситания:BAAALAAECgIIAgAAAA==.',['Ск']='Скири:BAAALAADCggIDAAAAA==.',['Со']='Сонитка:BAAALAAECgYICgABLAAECggIHgAJAGkiAA==.Софако:BAAALAAECgMIBAAAAA==.Соффа:BAABLAAECoEUAAIFAAYIBxlKfgCBAQAFAAYIBxlKfgCBAQAAAA==.',['Ст']='Старсс:BAAALAAECgYIBwAAAA==.Стингрей:BAAALAADCggIEgAAAA==.Стиргвард:BAAALAAECgEIAQABLAAECgYIGQAIAJYTAA==.Стирдрак:BAABLAAECoEZAAIIAAYIlhMlMgB1AQAIAAYIlhMlMgB1AQAAAA==.Стоникпал:BAACLAAFFIEFAAINAAII7R88GADAAAANAAII7R88GADAAAAsAAQKgR4AAg0ACAgzIz4ZAPUCAA0ACAgzIz4ZAPUCAAAA.Стрексер:BAAALAAECgcICAAAAA==.Стэксир:BAAALAADCggICgAAAA==.',['Су']='Суккума:BAABLAAFFIEJAAIKAAUIhRTLDACkAQAKAAUIhRTLDACkAQAAAA==.Супербладия:BAACLAAFFIEIAAIKAAMISRM3HADeAAAKAAMISRM3HADeAAAsAAQKgS0AAxEACAhMIIgSAEsCAAoACAjqHxgfAK8CABEACAhaG4gSAEsCAAAA.',['Сэ']='Сэдрик:BAAALAADCgYIBgAAAA==.Сэнбонсакура:BAAALAAECgIIAgAAAA==.Сэрджавашама:BAAALAAECgIIAgAAAA==.',['Та']='Талйон:BAAALAAECgUIBQAAAA==.Тандеридж:BAAALAADCggIKgAAAA==.Таролог:BAAALAAECgYIDwAAAA==.Таэль:BAAALAADCgMIAwAAAA==.',['Те']='Тейлаш:BAABLAAECoEVAAIJAAYIaRgOQgCqAQAJAAYIaRgOQgCqAQAAAA==.Терозерг:BAAALAADCgIIAgAAAA==.Тефа:BAAALAAECgEIAQAAAA==.',['Ти']='Тиосульфат:BAAALAAECggIDwAAAA==.Тирандиель:BAABLAAECoEUAAIjAAcI9xtbSgAYAgAjAAcI9xtbSgAYAgAAAA==.Титус:BAAALAADCgQIBwAAAA==.',['То']='Тоил:BAAALAAECgYIBgAAAA==.Торидал:BAABLAAECoEVAAIhAAgI5x08HwBVAgAhAAgI5x08HwBVAgAAAA==.Торналтор:BAAALAAECggIEAAAAA==.',['Тр']='Трахентэрн:BAAALAADCgMIAwAAAA==.Требл:BAAALAADCggICAAAAA==.Третийдоктор:BAABLAAECoElAAIfAAgI2BwDDgCbAgAfAAgI2BwDDgCbAgAAAA==.Трипальца:BAABLAAECoEYAAIdAAcIfyDiFwB5AgAdAAcIfyDiFwB5AgAAAA==.Трулендар:BAAALAAECgEIAQAAAA==.',['Ту']='Тудирим:BAAALAADCgcIBwAAAA==.Турбохомяк:BAAALAADCggICAABLAADCggIFgABAAAAAA==.',['Ть']='Тьяри:BAABLAAECoEWAAMFAAgIXwfHqQAsAQAFAAgIUwXHqQAsAQAhAAcIDwZFcwDjAAAAAA==.',['Тё']='Тёмнаякнига:BAABLAAECoEbAAIPAAgIRwqfnACOAQAPAAgIRwqfnACOAQAAAA==.Тёмноепиво:BAAALAADCggICAAAAA==.',['Уг']='Угроза:BAAALAAECgYICQAAAA==.Угрюмый:BAACLAAFFIEMAAINAAQI9RPzCQA4AQANAAQI9RPzCQA4AQAsAAQKgS8AAg0ACAg8JFEKAEkDAA0ACAg8JFEKAEkDAAAA.',['Уд']='Ударыч:BAAALAADCggIJAAAAA==.',['Ул']='Улитуля:BAAALAADCgQIBAAAAA==.',['Ум']='Умбилэк:BAAALAADCgQIBAAAAA==.',['Ут']='Утипуськин:BAABLAAECoEZAAIPAAcIWBLkhAC5AQAPAAcIWBLkhAC5AQAAAA==.',['Фа']='Фаантик:BAAALAAECgUIBQABLAAECgcIFQAJABkUAA==.Файнол:BAAALAAECgMIAwAAAA==.Фансон:BAAALAADCggICAAAAA==.Фарамант:BAAALAADCgMIAwAAAA==.Фашадра:BAAALAAECgMIAwAAAA==.Фаэтрен:BAAALAAFFAIIBAAAAA==.',['Фе']='Фельт:BAACLAAFFIEJAAMkAAMIhR9+AQDQAAAEAAMIBhwUDQAhAQAkAAIIISR+AQDQAAAsAAQKgScAAyQACAhgJAUBAFkDACQACAgtJAUBAFkDAAQABwilISAgAKICAAAA.Фенидрон:BAAALAAECgEIAQAAAA==.Фессалина:BAAALAAECggICAAAAA==.',['Фи']='Фиарен:BAAALAAECgYIEwAAAA==.Фирала:BAAALAAECggIAgAAAA==.',['Фо']='Фоксдк:BAACLAAFFIEFAAIPAAMIwQuNTQCMAAAPAAMIwQuNTQCMAAAsAAQKgS4AAg8ACAhIHcoyAIICAA8ACAhIHcoyAIICAAAA.',['Фу']='Фукач:BAACLAAFFIERAAILAAUIexqLAwDRAQALAAUIexqLAwDRAQAsAAQKgSsAAgsACAinInkFAPkCAAsACAinInkFAPkCAAAA.Фукич:BAAALAADCggICAAAAA==.Фукичь:BAABLAAECoEjAAIPAAgI/yK7EAAdAwAPAAgI/yK7EAAdAwAAAA==.',['Ха']='Хабенский:BAAALAADCggIFwAAAA==.Хантышка:BAAALAAECggIEAAAAA==.Хантэро:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Хатоши:BAAALAAECgIIAgAAAA==.',['Хе']='Хеллансар:BAAALAADCgYIBgAAAA==.',['Хи']='Хинатахьюга:BAAALAAECgcIEAAAAA==.',['Хо']='Хорана:BAAALAAECgYICAAAAA==.',['Хр']='Хромойс:BAAALAAECgIIAgAAAA==.',['Це']='Целофан:BAAALAADCggICwAAAA==.Цер:BAAALAAECgcIEQAAAA==.',['Ци']='Цири:BAAALAAECgYICAAAAA==.',['Че']='Челикк:BAAALAAECgYICgAAAA==.Черепусечка:BAABLAAECoEaAAIZAAYIHgf5MAAlAQAZAAYIHgf5MAAlAQAAAA==.',['Чи']='Чибх:BAAALAAECggIBgABLAAECggIHAAUAHcXAA==.Чикилоко:BAAALAADCggIHgAAAA==.',['Ша']='Шадия:BAAALAADCggICwABLAADCggIFgABAAAAAA==.Шаксаар:BAABLAAECoEaAAIKAAYIdRktVwC3AQAKAAYIdRktVwC3AQAAAA==.Шаланей:BAABLAAECoEXAAIPAAgIARoOLwCPAgAPAAgIARoOLwCPAgAAAA==.',['Шо']='Шог:BAABLAAECoEUAAQdAAYI/hcuUABqAQAdAAUI/RguUABqAQADAAYIPRLdUAA6AQAGAAIIARWpNACNAAAAAA==.Шогг:BAAALAAECgcIEgAAAA==.',['Шу']='Шушпанка:BAAALAAECggIAQAAAA==.',['Щу']='Щупус:BAABLAAECoEUAAIYAAcI3CByGgCRAgAYAAcI3CByGgCRAgAAAA==.',['Эв']='Эвкливуд:BAAALAAECgYIBgAAAA==.',['Эл']='Эльнарис:BAAALAAECgcIBwAAAA==.Эльнира:BAAALAAECgYICgABLAAFFAMIDwAjAK0iAA==.Эльтараа:BAAALAAECgMIBwAAAA==.',['Эм']='Эмеркомм:BAACLAAFFIEIAAICAAUIVgqyFQAVAQACAAUIVgqyFQAVAQAsAAQKgSMAAgIACAh7HNMtAHoCAAIACAh7HNMtAHoCAAAA.Эмпатия:BAAALAAFFAEIAQAAAA==.',['Эн']='Эниса:BAAALAADCgcIBwAAAA==.',['Эр']='Эрдвадедва:BAAALAADCgYICgAAAA==.Эрунир:BAAALAAECgYICQAAAA==.',['Юй']='Юйника:BAAALAAECggICAAAAA==.',['Юн']='Юнаруками:BAAALAAECgYIDgAAAA==.Юность:BAAALAADCgQIBAAAAA==.',['Яр']='Яровицкая:BAAALAAECgIIAgAAAA==.',['Ях']='Яхантишка:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end