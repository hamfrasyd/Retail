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
 local lookup = {'DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Druid-Restoration','Warrior-Protection','Mage-Frost','Mage-Arcane','Paladin-Protection','Paladin-Retribution','Evoker-Preservation','Priest-Shadow','Shaman-Elemental','Druid-Guardian','Hunter-Marksmanship','Warrior-Fury','Hunter-BeastMastery','DemonHunter-Havoc','Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Unknown-Unknown','Druid-Feral','Shaman-Enhancement','Evoker-Devastation','Mage-Fire','Paladin-Holy','DemonHunter-Vengeance',}; local provider = {region='EU',realm='Пиратскаябухта',name='EU',type='weekly',zone=44,date='2025-09-25',data={['Аб']='Абаюндич:BAAALAAECggICQAAAA==.Абубун:BAAALAADCggICAAAAA==.',['Ав']='Авгалон:BAAALAAECgEIAQAAAA==.',['Аз']='Азнаур:BAAALAAECgYICQABLAAECgcIKQABAHQlAA==.',['Ак']='Акэти:BAABLAAECoEbAAQCAAcIkRsGOQApAgACAAcIJhsGOQApAgADAAMIzRh2WwDUAAAEAAMIfgvIIwCtAAAAAA==.',['Ал']='Алатена:BAAALAADCggICAAAAA==.Алиста:BAAALAADCggICAAAAA==.Алондий:BAAALAAECgEIAQAAAA==.Алундрин:BAAALAAECgYIEAAAAA==.',['Ам']='Амалина:BAABLAAECoElAAMFAAgIsxxNHwA7AgAFAAgIsxxNHwA7AgAGAAIICQO1tQA9AAAAAA==.Амароун:BAAALAAFFAIIBAAAAA==.Ампецилинка:BAAALAADCggIFwABLAAECgcIGAAHAPsYAA==.',['Ан']='Анармаг:BAAALAADCggICAAAAA==.Анарпалла:BAAALAADCggICAAAAA==.Анархант:BAAALAADCggICAAAAA==.Ангмар:BAABLAAECoElAAMIAAgItBx0DgCdAgAIAAgItBx0DgCdAgAJAAYISA4vgQBpAQAAAA==.Анкноун:BAAALAADCgcICAAAAA==.Анномаг:BAAALAAECgQIBAAAAA==.',['Ап']='Аппафеоз:BAABLAAECoEhAAMKAAcIDhJPPQD0AAAKAAUIMRZPPQD0AAALAAIItAfgJQFgAAAAAA==.Апритулл:BAAALAADCgEIAQAAAA==.',['Ар']='Аркар:BAAALAADCgQIBAAAAA==.Аркрай:BAABLAAECoEjAAMGAAcIdyKUEgCkAgAGAAcIdyKUEgCkAgAFAAEImAHanQAJAAAAAA==.Арнульв:BAAALAADCggICAAAAA==.Архонти:BAAALAADCgIIAgAAAA==.',['Ат']='Атеист:BAABLAAECoEXAAIMAAgIXxbeCwBJAgAMAAgIXxbeCwBJAgAAAA==.Атмороз:BAAALAAECggICQAAAA==.Атышо:BAAALAAECggIDgAAAA==.',['Ау']='Ауешка:BAACLAAFFIEYAAINAAUIgSMSBAD3AQANAAUIgSMSBAD3AQAsAAQKgTMAAg0ACAghJtUDAF4DAA0ACAghJtUDAF4DAAAA.',['Аф']='Африка:BAAALAADCggIFAAAAA==.',['Ба']='Байсангур:BAAALAAECggICAAAAA==.',['Бе']='Безумныйбык:BAAALAAECggICAABLAAECggIJQAOAGogAA==.Бейбушка:BAABLAAECoEVAAMPAAgI6gViJgBxAAAPAAgIsQFiJgBxAAAFAAgIoAUAAAAAAAAAAA==.',['Би']='Бигмак:BAAALAADCgcIBwAAAA==.Бирский:BAAALAADCgcIBwAAAA==.',['Бл']='Блошка:BAABLAAECoEbAAIQAAcIpREvRQCIAQAQAAcIpREvRQCIAQAAAA==.',['Бо']='Богмар:BAAALAAECgQIAQAAAA==.',['Бр']='Братгаашека:BAABLAAECoEZAAIIAAYIGBkxMACVAQAIAAYIGBkxMACVAQAAAA==.',['Бу']='Бууча:BAABLAAECoESAAIRAAcI7R3gMABDAgARAAcI7R3gMABDAgAAAA==.Буффал:BAAALAADCgcIDAAAAA==.',['Бь']='Бьёринг:BAABLAAECoEYAAIGAAgIgRY7KQATAgAGAAgIgRY7KQATAgAAAA==.',['Ва']='Ваар:BAAALAADCgQIBAAAAA==.Валаир:BAABLAAECoEXAAISAAYIfhyfegCJAQASAAYIfhyfegCJAQAAAA==.Валки:BAABLAAECoEZAAIQAAcIBxeYNQDNAQAQAAcIBxeYNQDNAQAAAA==.',['Ве']='Велита:BAAALAADCgMIAwAAAA==.',['Ви']='Вирго:BAAALAAECgYIBgAAAA==.',['Вк']='Вкусныйторт:BAAALAAFFAIIBAAAAA==.',['Вл']='Владислов:BAABLAAECoEYAAITAAcIrQ3glQBtAQATAAcIrQ3glQBtAQAAAA==.Владлекс:BAAALAAECgEIAQAAAA==.Владыкаэльф:BAAALAAECgYICAAAAA==.',['Во']='Вовилем:BAACLAAFFIEPAAIUAAQI0hwkBABZAQAUAAQI0hwkBABZAQAsAAQKgTQAAxQACAi1I/0FAB4DABQACAi1I/0FAB4DABUAAwhBCHo/AGwAAAAA.Водкашпротка:BAAALAADCggICAAAAA==.',['Ву']='Вудмен:BAABLAAECoEcAAISAAgIbQ6QjgBhAQASAAgIbQ6QjgBhAQAAAA==.Вульфис:BAABLAAECoEZAAIFAAcIKgQPYQDzAAAFAAcIKgQPYQDzAAAAAA==.',['Вя']='Вялыйкракен:BAAALAADCgcIAwAAAA==.',['Га']='Гаврошег:BAAALAAECgEIAQAAAA==.Гайдзин:BAAALAAECgYIDAAAAA==.',['Гз']='Гзу:BAABLAAECoEcAAIWAAcIOhm5QQDxAQAWAAcIOhm5QQDxAQAAAA==.',['Гл']='Глиптодонт:BAAALAAECggICAAAAA==.',['Гн']='Гномхуекрад:BAAALAADCggICQAAAA==.',['Го']='Гозешечка:BAAALAAFFAEIAQABLAAFFAUIFAAXAA8cAA==.Гозешка:BAACLAAFFIEUAAMXAAUIDxypDQBVAQAXAAQIfR+pDQBVAQAYAAMIVhLbBAANAQAsAAQKgSoAAxcACAh8JKUjAMACABcACAh4JKUjAMACABgABAj+Io8vAC8BAAAA.Горболом:BAABLAAECoEhAAICAAYI/wjOjAAkAQACAAYI/wjOjAAkAQAAAA==.',['Гр']='Грикар:BAAALAAECgYICwAAAA==.',['Да']='Даксилус:BAABLAAECoEiAAIOAAgIGA8SSAC5AQAOAAgIGA8SSAC5AQAAAA==.Данако:BAABLAAECoEeAAMLAAcIsCNrJQC3AgALAAcIsCNrJQC3AgAKAAEIwBJGZAAiAAAAAA==.',['Де']='Девола:BAAALAAECgcICQAAAA==.Дельоро:BAAALAAECggICQAAAA==.Деринат:BAAALAAECggIDAAAAA==.',['Дж']='Джанзи:BAAALAAECgYIEAAAAA==.Джокерфейк:BAAALAADCgUIBQAAAA==.Джокерфейс:BAAALAAECgYIBgAAAA==.Джостан:BAAALAADCgYIBgAAAA==.',['Ди']='Дисальво:BAAALAAECgQIBQAAAA==.',['До']='Добраякола:BAAALAADCggIDwAAAA==.',['Дп']='Дпссэр:BAACLAAFFIEIAAIWAAIIMBMOKACOAAAWAAIIMBMOKACOAAAsAAQKgSkAAhYACAg0Gqc/APgBABYACAg0Gqc/APgBAAAA.',['Др']='Драго:BAAALAADCggICAABLAAECggIJQAOAGogAA==.Друландус:BAAALAAECggIDQAAAA==.Друстэ:BAAALAAECgUIDAAAAA==.',['Ду']='Дугза:BAAALAAECgEIAQAAAA==.Дураюля:BAABLAAECoEUAAIOAAcIahToPwDaAQAOAAcIahToPwDaAQAAAA==.',['Дэ']='Дэксич:BAABLAAECoEVAAIJAAgIiRaVTAAAAgAJAAgIiRaVTAAAAgAAAA==.',['Ер']='Еренити:BAAALAADCgYIBgAAAA==.',['Же']='Женёчек:BAAALAADCggIFgABLAAFFAUIFAAXAA8cAA==.',['Жм']='Жмыховуха:BAACLAAFFIEKAAMZAAQIVA8hBQApAQAZAAQIVA8hBQApAQAaAAIIqgeaGwBSAAAsAAQKgTAABBkACAhZHjEMAE0CABkACAhjGTEMAE0CABsACAgTE2UHAAkCABoAAwgxIjBGAA8BAAAA.',['Жо']='Жозефина:BAAALAAECgIIAwAAAA==.',['За']='Залария:BAAALAAECgIIAgAAAA==.Залтан:BAAALAADCggICAAAAA==.Зандис:BAAALAADCggICAABLAAECgYIBgAcAAAAAA==.',['Зв']='Звёзднаяпыль:BAAALAAECgYIBgAAAA==.',['Зи']='Зизич:BAAALAAECgYIBgAAAA==.',['Зм']='Змейй:BAAALAADCggIEAAAAA==.',['Зо']='Золтанхайвей:BAAALAAECgMIAwAAAA==.Зомбака:BAABLAAECoEVAAIJAAcIPAhclAAzAQAJAAcIPAhclAAzAQAAAA==.',['Из']='Изысканность:BAAALAADCggIGQAAAA==.',['Ил']='Илисандр:BAAALAADCgcIDQAAAA==.Иллорианшам:BAAALAADCgcIBwAAAA==.Иллорнадестр:BAAALAAECggIEAAAAA==.Иллорнаприст:BAAALAAECggIEAAAAA==.',['Им']='Император:BAAALAADCggICAAAAA==.',['Ин']='Индиана:BAAALAAECgYIBgAAAA==.',['Ит']='Итариона:BAAALAAECgMIBAAAAA==.',['Йл']='Йлофлждвлфвд:BAAALAAECgYIBwAAAA==.',['Йо']='Йолодрыг:BAAALAAECgMIAwAAAA==.Йолохайп:BAAALAAECgMIAwAAAA==.',['Ка']='Кайсастина:BAABLAAECoEwAAICAAgI8xtuIgCaAgACAAgI8xtuIgCaAgAAAA==.Какзабадаю:BAABLAAECoEbAAIdAAYIUxP6HQB+AQAdAAYIUxP6HQB+AQAAAA==.Каллевала:BAAALAADCgUIBQAAAA==.Капо:BAAALAADCggIEQAAAA==.Катрисия:BAACLAAFFIENAAIdAAUI3xATAwA8AQAdAAUI3xATAwA8AQAsAAQKgSoAAh0ACAiAJIkBAF4DAB0ACAiAJIkBAF4DAAAA.',['Ки']='Кибер:BAABLAAECoElAAMOAAgIaiBmFADZAgAOAAgIyh1mFADZAgAeAAgIkBqQCABZAgAAAA==.Кирюсанна:BAAALAAECgIIAgAAAA==.Кирял:BAAALAADCgUIBQAAAA==.Китюня:BAAALAAECgEIAQAAAA==.',['Ко']='Коверчик:BAABLAAECoEUAAIFAAYIlRiOPgCLAQAFAAYIlRiOPgCLAQABLAAECgcIGAAHAPsYAA==.',['Кр']='Крейш:BAAALAAECgMIBQAAAA==.Крутоф:BAAALAADCgcIEgAAAA==.',['Ку']='Кудиграс:BAACLAAFFIEdAAIfAAYIPiXMAAB5AgAfAAYIPiXMAAB5AgAsAAQKgRcAAh8ACAidJYAJAPYCAB8ACAidJYAJAPYCAAAA.Кукумба:BAACLAAFFIEIAAILAAUI1g25BwB3AQALAAUI1g25BwB3AQAsAAQKgSYAAgsACAj6IoQOADADAAsACAj6IoQOADADAAAA.Кусанали:BAAALAAECgUICAAAAA==.Кутто:BAAALAADCgMIAwAAAA==.',['Кэ']='Кэлгор:BAAALAADCgcIBwAAAA==.',['Ла']='Лаит:BAABLAAECoEpAAIBAAcIdCVtBQD/AgABAAcIdCVtBQD/AgAAAA==.Лайнис:BAACLAAFFIEGAAIMAAIIWSYSCADkAAAMAAIIWSYSCADkAAAsAAQKgR4AAwwABwhqJuMCABUDAAwABwhqJuMCABUDAB8AAgjlFghQAIYAAAAA.Лайнисс:BAAALAAECgYIBAAAAA==.Лайтлин:BAAALAAECgYIBgAAAA==.Ландриса:BAAALAADCgcIBwAAAA==.',['Ле']='Ленапаравоз:BAAALAAECgcICQAAAA==.Леонато:BAAALAADCgQIBAAAAA==.Лестреиндж:BAAALAAECgIIAgAAAA==.',['Ли']='Либрариан:BAAALAADCggICAAAAA==.Лисков:BAAALAAECgUICQAAAA==.',['Ло']='Лорадос:BAAALAAECggIEAAAAA==.',['Лю']='Люцив:BAAALAAECgMIAwAAAA==.',['Ма']='Мабумба:BAAALAADCggIFwAAAA==.Маварэ:BAAALAAECgYIBwAAAA==.Макина:BAAALAAFFAEIAQAAAA==.Малениа:BAAALAAECgQIBgAAAA==.Малибу:BAACLAAFFIEIAAIdAAII8Bv2CACfAAAdAAII8Bv2CACfAAAsAAQKgS0AAh0ABwj/I8oKAIICAB0ABwj/I8oKAIICAAAA.Мантра:BAAALAADCggIGwAAAA==.Марик:BAAALAAECggIBQABLAAECggIGAAPADwLAA==.Массарахш:BAABLAAECoEYAAIPAAgIPAtnFQBDAQAPAAgIPAtnFQBDAQAAAA==.',['Ме']='Мефидрун:BAAALAADCgcICgAAAA==.Мефик:BAABLAAECoEjAAMMAAgIhRFjEwDJAQAMAAgIhRFjEwDJAQAfAAIIUgUfVgBaAAAAAA==.',['Ми']='Микелла:BAAALAAECgUIBgAAAA==.Минивэн:BAAALAAECgEIAQAAAA==.Мириэль:BAAALAAECggIBwAAAA==.',['Му']='Мудзан:BAAALAADCggIDwAAAA==.Мультяшик:BAAALAADCggIEQAAAA==.Муркотя:BAABLAAECoEuAAIGAAgIVg9lSACHAQAGAAgIVg9lSACHAQAAAA==.Мурхард:BAABLAAECoEYAAIHAAcI+xjOJADaAQAHAAcI+xjOJADaAQAAAA==.',['На']='Нанака:BAAALAADCgcIBgAAAA==.',['Не']='Неадекватная:BAABLAAECoEpAAIRAAgIjCUWBQBjAwARAAgIjCUWBQBjAwAAAA==.Нева:BAAALAADCggICQAAAA==.Неевернный:BAAALAADCgYIBgAAAA==.Незнаком:BAAALAAECgIIAgAAAA==.Нейтан:BAACLAAFFIEEAAILAAIIRgWzPACJAAALAAIIRgWzPACJAAAsAAQKgSoAAgsACAgRHQU4AGsCAAsACAgRHQU4AGsCAAAA.Некровейн:BAAALAAECgcIDQAAAA==.Немуму:BAABLAAECoEfAAMFAAgI0g94RgBnAQAFAAgI0g94RgBnAQAPAAEI7QKaMQAYAAAAAA==.Неоспоримая:BAAALAAECggIEAAAAA==.Нефтегаз:BAAALAAECgMIAwAAAA==.Нечто:BAABLAAECoEVAAIQAAcI2QUMbgD2AAAQAAcI2QUMbgD2AAAAAA==.',['Ни']='Нифф:BAABLAAECoEfAAMDAAgI3RoYEQBZAgADAAgI3RoYEQBZAgACAAIISBWPuwCJAAAAAA==.',['Но']='Номевоу:BAAALAAECgEIAgAAAA==.',['Ны']='Нывка:BAAALAAECggIEAABLAAFFAYIHQAfAD4lAA==.',['Нэ']='Нэриал:BAAALAAECggICAAAAA==.',['Об']='Обамеянг:BAAALAADCgcIBwAAAA==.',['Оп']='Опетушитель:BAAALAAECgYIDgAAAA==.',['Ор']='Оркшаман:BAAALAADCggIEgAAAA==.Орнея:BAAALAAECgYIBgAAAA==.',['Ос']='Осенний:BAAALAADCgcIBwAAAA==.',['Пи']='Пиксалина:BAACLAAFFIELAAIWAAMIMiADDQAFAQAWAAMIMiADDQAFAQAsAAQKgSwAAhYACAhJI6sJAAMDABYACAhJI6sJAAMDAAAA.Пипика:BAAALAADCgUIBgAAAA==.Пираксилин:BAAALAAECggIEAAAAA==.',['Пк']='Пкилд:BAAALAAECgYIDAAAAA==.',['По']='Погладькотят:BAAALAADCggICwAAAA==.Позорница:BAAALAADCggICAAAAA==.Полныйпандец:BAAALAADCgcIBwABLAAECggIJQAOAGogAA==.',['Пр']='Пресцилла:BAAALAAECgcIEwAAAA==.Примор:BAAALAAECgYICQAAAA==.',['Пс']='Псинасутулая:BAAALAADCggICQAAAA==.Психоза:BAAALAADCgYIBgAAAA==.',['Пё']='Пёсьяденьга:BAAALAADCggIDQAAAA==.',['Ре']='Реалайн:BAAALAADCggICAAAAA==.',['Ро']='Рокертравли:BAABLAAECoEWAAIEAAYIuBJaEgByAQAEAAYIuBJaEgByAQAAAA==.',['Ру']='Руго:BAAALAAECgMIAwAAAA==.Рулер:BAAALAADCggICAAAAA==.Руснёва:BAAALAADCggIFQAAAA==.',['Ры']='Рыська:BAABLAAECoEZAAISAAgIABtvLQBmAgASAAgIABtvLQBmAgAAAA==.',['Са']='Сангвинор:BAAALAADCggICAAAAA==.Саро:BAAALAADCggIDgAAAA==.',['Св']='Светодар:BAABLAAECoEZAAMKAAYIaggAQQDcAAAKAAYI9wYAQQDcAAALAAQIBAgAAAAAAAAAAA==.',['Се']='Седобородыч:BAAALAAECgMIAwAAAA==.Сексигетрект:BAACLAAFFIEMAAISAAUI+xUzCwBMAQASAAUI+xUzCwBMAQAsAAQKgS4AAxIACAhlJBYJADgDABIACAhlJBYJADgDABAAAQi5AhG5ACQAAAAA.Серасвати:BAAALAAECgIIAgAAAA==.',['Си']='Силвиан:BAACLAAFFIEIAAMIAAIImhvHCgCZAAAIAAIImhvHCgCZAAAJAAIIkgWpRQB/AAAsAAQKgRQAAwgABwjCHRkhAO8BAAgABQhxIRkhAO8BAAkABwhYF5RWAOEBAAAA.Симфовокер:BAACLAAFFIEJAAIMAAMIaQn2CQDGAAAMAAMIaQn2CQDGAAAsAAQKgTMAAwwACAgCGjwLAFQCAAwACAgCGjwLAFQCAB8ABQgmC11DAAIBAAAA.Сиэла:BAAALAADCggIDwAAAA==.',['Ск']='Скитатель:BAAALAAECgYIEwAAAA==.',['Сл']='Слава:BAABLAAECoEWAAMaAAYInRsqKwC3AQAaAAYInRsqKwC3AQAbAAIIMg44FwBvAAAAAA==.',['См']='Смертоштанец:BAAALAAECggIAQAAAA==.Смертьваша:BAAALAAECgYIEgABLAAECgcIGAAHAPsYAA==.',['Сн']='Снорлакс:BAABLAAECoEVAAIWAAgI6hNsRADoAQAWAAgI6hNsRADoAQAAAA==.',['Со']='Содалов:BAAALAAECgYIDgABLAAECggIGwAGABogAA==.',['Сп']='Спидвагонка:BAABLAAECoEWAAIZAAgI2w7PFwCxAQAZAAgI2w7PFwCxAQAAAA==.',['Ст']='Стромае:BAAALAADCggICQAAAA==.',['Су']='Субстанция:BAAALAAECggIBgAAAA==.Супергерл:BAAALAAECggICAAAAA==.Суровыйв:BAAALAAECgcIEAAAAA==.',['Сы']='Сын:BAAALAAECgIIAQAAAA==.',['Сю']='Сюреализм:BAAALAAECggICQAAAA==.',['Та']='Тандери:BAABLAAECoEaAAMOAAcIEhdDOgDzAQAOAAcIEhdDOgDzAQAWAAIIthd95gB8AAAAAA==.',['Те']='Техноересь:BAAALAADCggIEAAAAA==.',['Ти']='Тибетман:BAAALAAECgcIDAAAAA==.Тиккре:BAAALAAECgIIAgAAAA==.',['Тк']='Ткачсвета:BAAALAADCgUIBQAAAA==.',['То']='Толстолинь:BAAALAAECgcIDwAAAA==.Торадин:BAAALAAECgYICgAAAA==.',['Тр']='Транкв:BAAALAADCgcIBwAAAA==.Трикснаноль:BAACLAAFFIEJAAIZAAYIYiEVAQBKAgAZAAYIYiEVAQBKAgAsAAQKgRcAAxkACAhyJY4EAPYCABkABwhvJY4EAPYCABoACAihIhkRAI0CAAEsAAUUCAgdACAAbCUA.Трион:BAAALAADCgYIBgAAAA==.',['Ту']='Тур:BAABLAAECoEnAAILAAgI8xBmYwD0AQALAAgI8xBmYwD0AQAAAA==.Тучный:BAAALAAECgMIAwAAAA==.',['Ул']='Ульдум:BAAALAAECgIIAgAAAA==.',['Фа']='Фанатпива:BAAALAADCgcICgAAAA==.Фапкитапки:BAABLAAECoEXAAIOAAgIyxwgGgCtAgAOAAgIyxwgGgCtAgAAAA==.',['Фо']='Фод:BAABLAAECoEeAAIPAAcIbRPTDwCdAQAPAAcIbRPTDwCdAQAAAA==.Фонаббадон:BAAALAADCgUIBQAAAA==.Фонсвят:BAAALAADCgcIEgAAAA==.Фонтень:BAAALAADCgYIBgAAAA==.Фонтьма:BAAALAADCgYIBgAAAA==.Фончпокер:BAACLAAFFIEGAAMaAAIIBR4ODwCwAAAaAAIIBR4ODwCwAAAZAAIIlRHSDACZAAAsAAQKgSgAAxoABwgdG2MgAP8BABoABwipFmMgAP8BABkABQgoGMcfAGgBAAAA.',['Фу']='Фуджи:BAACLAAFFIEPAAMJAAUI5hz8CgDGAQAJAAUITxv8CgDGAQAgAAMIySAAAAAAAAAsAAQKgR0AAwgACAgXJk0IAPkCAAgABwiBJU0IAPkCAAkACAg7JXIeAMUCAAAA.',['Ха']='Хано:BAAALAADCgIIAgAAAA==.Харасмент:BAAALAADCgIIAgAAAA==.Хаюка:BAAALAAECgYICgAAAA==.',['Хв']='Хвоствогне:BAAALAAECgYICwAAAA==.',['Хо']='Холипандец:BAAALAADCggICAABLAAECggIJQAOAGogAA==.Хонели:BAAALAADCggICAABLAAECgcIDAAcAAAAAA==.Хорман:BAAALAAECgQIBAAAAA==.',['Хр']='Хрюхрум:BAABLAAECoEdAAILAAYI4hz0cQDVAQALAAYI4hz0cQDVAQAAAA==.',['Хэ']='Хэлисон:BAAALAADCgcIBwAAAA==.',['Ца']='Цапуля:BAAALAADCgEIAQAAAA==.',['Че']='Челсинах:BAABLAAECoEWAAIEAAcIxBp8BwA0AgAEAAcIxBp8BwA0AgAAAA==.',['Чо']='Чорт:BAAALAAECgMIBQAAAA==.',['Чу']='Чубаакаа:BAAALAADCgYICAAAAA==.Чувачёк:BAABLAAECoEZAAIDAAYIFBqwNgBxAQADAAYIFBqwNgBxAQAAAA==.',['Ша']='Шамазюка:BAABLAAECoEmAAIWAAgIoB6eGgCPAgAWAAgIoB6eGgCPAgAAAA==.Шамохайп:BAAALAAECgMIAwAAAA==.',['Ши']='Шидзука:BAAALAADCgYIBgAAAA==.Шис:BAAALAADCggICQABLAAFFAIIBQASAAYgAA==.',['Шк']='Шкуровоз:BAACLAAFFIEIAAISAAYIeBhYAgAfAgASAAYIeBhYAgAfAgAsAAQKgRYAAxIACAhXH40UAOkCABIACAibHo0UAOkCABAACAiBCyROAGMBAAAA.',['Шо']='Шои:BAAALAADCggIDwABLAAECggIMAACAPMbAA==.',['Шп']='Шпунтикк:BAAALAADCggICAAAAA==.',['Шт']='Штурман:BAABLAAECoEUAAIhAAYIIQtBSwDlAAAhAAYIIQtBSwDlAAAAAA==.Штурманюга:BAABLAAECoEXAAIRAAYI4RkXUADJAQARAAYI4RkXUADJAQAAAA==.',['Шу']='Шурёна:BAABLAAECoEVAAIWAAgIRxHGYgCSAQAWAAgIRxHGYgCSAQAAAA==.',['Эб']='Эбфид:BAACLAAFFIEbAAINAAYIJxjOAwABAgANAAYIJxjOAwABAgAsAAQKgTAAAg0ACAjLJGQDAGMDAA0ACAjLJGQDAGMDAAAA.',['Эл']='Элнис:BAAALAADCgYIBgAAAA==.Эльмехор:BAAALAADCggIFAAAAA==.',['Эм']='Эмильрина:BAAALAAECggIAgAAAA==.',['Эф']='Эфочка:BAABLAAECoEfAAIiAAcIyBVQHQCaAQAiAAcIyBVQHQCaAQAAAA==.',['Юа']='Юана:BAAALAAFFAIIBAAAAA==.',['Юз']='Юзура:BAABLAAECoEYAAIOAAYI2R7BNQAIAgAOAAYI2R7BNQAIAgAAAA==.',['Юн']='Юна:BAABLAAECoEeAAIXAAgIvx3bPgBaAgAXAAgIvx3bPgBaAgAAAA==.',['Ян']='Яневответе:BAAALAAECggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end