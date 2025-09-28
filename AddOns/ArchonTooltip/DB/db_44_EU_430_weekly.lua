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
 local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Druid-Restoration','Priest-Shadow','Druid-Guardian','DeathKnight-Blood','Priest-Holy','Hunter-Marksmanship','Paladin-Retribution','Paladin-Protection','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Holy','Rogue-Assassination','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Druid-Balance','Druid-Feral','Shaman-Elemental','Shaman-Enhancement','Evoker-Augmentation','DemonHunter-Vengeance','Hunter-Survival','Warrior-Arms','Mage-Frost','Shaman-Restoration','Evoker-Preservation','Monk-Windwalker','Evoker-Devastation','Priest-Discipline','Mage-Arcane','Warlock-Affliction','Monk-Mistweaver','Warrior-Protection',}; local provider = {region='EU',realm='Frostmourne',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aatroce:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.',Ab='Abigaile:BAABLAAECoEjAAICAAgIvRRyUgDpAQACAAgIvRRyUgDpAQAAAA==.Abrahammer:BAAALAAECgUIBQAAAA==.',Ae='Aeluneth:BAAALAADCgIIAgAAAA==.Aenthyr:BAAALAAECgQIBAAAAA==.Aerojin:BAAALAAECggIEwAAAA==.Aeve:BAABLAAECoEXAAIDAAcIuhkfLwD2AQADAAcIuhkfLwD2AQAAAA==.',Ai='Airy:BAAALAADCggICAAAAA==.',Aj='Ajhar:BAAALAADCggICAABLAAECggIJwAEADAcAA==.Ajina:BAABLAAECoElAAIFAAcIWR8dCQAkAgAFAAcIWR8dCQAkAgAAAA==.',Ak='Akamechân:BAACLAAFFIEYAAIGAAYIjxT5AgCrAQAGAAYIjxT5AgCrAQAsAAQKgSgAAgYACAjVIZ0HAMcCAAYACAjVIZ0HAMcCAAAA.Akasha:BAAALAAECgEIAQAAAA==.',Al='Aldania:BAAALAADCgcICgAAAA==.Alessà:BAABLAAECoEWAAIEAAcI6QiuTQBcAQAEAAcI6QiuTQBcAQAAAA==.Allmight:BAAALAAECgEIAQAAAA==.',Am='Amailana:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.Amarru:BAACLAAFFIESAAIHAAYI3RHxAwDeAQAHAAYI3RHxAwDeAQAsAAQKgSUAAgcACAjdIGAOAOECAAcACAjdIGAOAOECAAAA.Ambrò:BAACLAAFFIENAAMCAAUINRxgCQB5AQACAAUIAhBgCQB5AQAIAAQIOyC+BgBnAQAsAAQKgSUAAwgACAj3I0cGADEDAAgACAjYI0cGADEDAAIAAwhlJVObAEgBAAAA.Amiley:BAAALAAECggICAAAAA==.',An='Andreá:BAAALAAECgUIBQAAAA==.Angryangel:BAAALAADCgcIDQAAAA==.Anri:BAAALAAECgYICgAAAA==.Anunnaki:BAAALAAECgcIEQAAAA==.',Ar='Arator:BAAALAAECgQIBAAAAA==.Aretiume:BAAALAADCgIIAgAAAA==.Arog:BAAALAAECgEIAQAAAA==.Aryasine:BAABLAAECoEXAAMHAAcIvANrcgD9AAAHAAcIvANrcgD9AAAEAAEICwPwjgAqAAAAAA==.',As='Ashyra:BAAALAAECgEIAQAAAA==.Asiontis:BAACLAAFFIEHAAMCAAMIqxfcHwCnAAACAAIIiSDcHwCnAAAIAAIIvRFHHgCEAAAsAAQKgSYAAwgACAgJJKwMAPMCAAgACAjTIqwMAPMCAAIACAhUI/4WANsCAAAA.Asurei:BAAALAADCggIDAAAAA==.',At='Ativivi:BAAALAAECgMIBwAAAA==.Ativiviî:BAAALAADCggICAAAAA==.',Ay='Ayana:BAABLAAECoEWAAIJAAgIaRCFZgDuAQAJAAgIaRCFZgDuAQAAAA==.Ayara:BAAALAADCgMIAwAAAA==.',Az='Azaha:BAACLAAFFIEWAAMJAAcIrxadAACEAgAJAAcIrxadAACEAgAKAAIIxRfkDACKAAAsAAQKgSAAAgkACAh6Jp0HAFoDAAkACAh6Jp0HAFoDAAAA.',Ba='Baaym:BAAALAAECgYIDwAAAA==.Backautomat:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.Balenty:BAAALAAECgcIHAAAAQ==.Bambamsen:BAAALAAECgYICwAAAA==.Bambelbe:BAAALAADCgQIBAAAAA==.Barrager:BAAALAADCggIEgAAAA==.',Be='Bellebaatar:BAAALAAFFAIIBAABLAAFFAgIFQALAIgkAA==.Benzino:BAAALAADCggIGAAAAA==.Bethen:BAABLAAECoEfAAIMAAcIfhwnDwBOAgAMAAcIfhwnDwBOAgAAAA==.',Bi='Bigboydps:BAACLAAFFIEHAAIIAAMINx8OCgAOAQAIAAMINx8OCgAOAQAsAAQKgScAAggACAg4IxYKAAsDAAgACAg4IxYKAAsDAAAA.',Bl='Blink:BAAALAAECgIIAgAAAA==.Bloodcrane:BAAALAADCgYICgAAAA==.Blóódge:BAAALAADCgIIAgAAAA==.Blôôdge:BAAALAAECgIIAgAAAA==.',Bo='Boomsenn:BAAALAAECgMIAwAAAA==.Borodir:BAAALAAECgYIBgAAAA==.Bowex:BAAALAADCggICgAAAA==.',Br='Brecs:BAABLAAECoEdAAMNAAYI4xDJNgBWAQANAAYI4xDJNgBWAQAJAAMIaheJ9wDMAAAAAA==.Brocktar:BAAALAAECggIDwAAAA==.Brojaeden:BAAALAADCgEIAQAAAA==.Brumbala:BAAALAAECgUIBQAAAA==.',Bu='Bullhahn:BAAALAADCggIDgAAAA==.Butscher:BAAALAAECgcIEwAAAA==.',['Bê']='Bêtrix:BAAALAADCgUIBQAAAA==.Bêtschêr:BAAALAADCggICAAAAA==.',Ca='Cabanossi:BAAALAAECgEIAQAAAA==.Camaguru:BAAALAADCggICAAAAA==.Cani:BAAALAADCgcIDAAAAA==.Carissima:BAAALAADCggIIgAAAA==.Cashncarry:BAAALAADCgcIBgAAAA==.',Ce='Cepheid:BAAALAADCggICAAAAA==.Cerys:BAAALAAECgUIBwABLAAFFAQICAAOAOMMAA==.Cessai:BAACLAAFFIEJAAIHAAQIhxAcCgA3AQAHAAQIhxAcCgA3AQAsAAQKgSEAAgcACAiAGrQgAFgCAAcACAiAGrQgAFgCAAAA.',Ch='Chalow:BAACLAAFFIEIAAIPAAMI5w84FADTAAAPAAMI5w84FADTAAAsAAQKgRsAAg8ACAhxHX8kAIYCAA8ACAhxHX8kAIYCAAAA.Chaoz:BAAALAADCgYIBgAAAA==.',Ci='Cirila:BAAALAAECgYIEwAAAA==.',Co='Cobi:BAABLAAECoEWAAMQAAgIqg9kJwC5AQAQAAcInhFkJwC5AQARAAII+wW31QA9AAAAAA==.Coobii:BAAALAAECggIDwAAAA==.Coshka:BAAALAADCgEIAQAAAA==.',Da='Daizawa:BAABLAAECoEWAAILAAgIXw9aoACIAQALAAgIXw9aoACIAQAAAA==.Damnbro:BAAALAADCgcIBwAAAA==.Danie:BAAALAAECgYICgAAAA==.Darkfôrce:BAAALAADCggIFQABLAAECggIJwANAPkTAA==.Darzz:BAAALAADCggIDgABLAADCggIDgABAAAAAA==.',De='De:BAABLAAECoEZAAISAAgIHyDLHQDQAgASAAgIHyDLHQDQAgAAAA==.Deathhulf:BAAALAADCgcIDQAAAA==.Deflector:BAAALAADCggIFwABLAAECggIHwATAGokAA==.Delia:BAABLAAECoElAAIUAAgICBLkEwDxAQAUAAgICBLkEwDxAQAAAA==.Demonicsoul:BAAALAADCggIJQABLAAECggIJwANAPkTAA==.Denoso:BAAALAADCgMIAwAAAA==.Dertotemtyp:BAABLAAECoEUAAMVAAYIZxVfVACNAQAVAAYIZxVfVACNAQAWAAEIKhieJAA2AAABLAAECggILQAJACghAA==.Deusregum:BAAALAAECgUIBwAAAA==.',Dh='Dhmain:BAAALAAECggIDAAAAA==.',Dk='Dkdanja:BAAALAADCggICwAAAA==.',Dm='Dmgdotcom:BAABLAAECoEUAAIPAAgIFxYDOQAfAgAPAAgIFxYDOQAfAgAAAA==.',Dn='Dny:BAACLAAFFIEUAAMLAAcIcRZZAQCGAgALAAcIpxRZAQCGAgAMAAUIKA8nAQCgAQAsAAQKgUYAAwsACAiCJawLADgDAAsACAj4JKwLADgDAAwABghNHecYAN4BAAAA.',Do='Doclynx:BAABLAAECoEgAAIHAAgI0xBzNgDgAQAHAAgI0xBzNgDgAQAAAA==.Donk:BAAALAAECgMIBQAAAA==.Dot:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',Dr='Drachenhuso:BAAALAAECggIDgAAAA==.Dragondeez:BAAALAAECggIDgAAAA==.Drecktor:BAAALAADCggIDwAAAA==.Drekakona:BAAALAAECgEIAQAAAA==.Drivebypetra:BAAALAAECggIDAAAAA==.Dromoka:BAABLAAECoEVAAIXAAcIDhCLCgCFAQAXAAcIDhCLCgCFAQAAAA==.',Ds='Dsumma:BAAALAAECgYICwAAAA==.',Dv='Dvalinn:BAAALAAECgcIEQAAAA==.',Ea='Earthbane:BAAALAADCgYIBgAAAA==.',Eb='Eblis:BAAALAAECggIDgAAAA==.',Ei='Eighthyperky:BAAALAADCgcIBwAAAA==.',El='Eldepleto:BAAALAAECgYICQAAAA==.Elânt:BAABLAAECoEXAAICAAcIJggErwAiAQACAAcIJggErwAiAQAAAA==.',En='Encor:BAAALAAECgYIDAAAAA==.Ender:BAAALAAECgIIAgAAAA==.Enorah:BAABLAAECoEZAAIDAAcIXB9VHABcAgADAAcIXB9VHABcAgAAAA==.',Er='Ereboras:BAAALAAECgYIBgAAAA==.Erikes:BAABLAAECoEkAAIPAAcIxQ8TZQCKAQAPAAcIxQ8TZQCKAQAAAA==.',Eu='Euke:BAABLAAECoEjAAMSAAcIUCCQJwCeAgASAAcIUCCQJwCeAgAYAAMInhWFUwBDAAAAAA==.',Ev='Evêyh:BAACLAAFFIEFAAMCAAQIVATaHACyAAACAAMIBwXaHACyAAAZAAII9QTsBACIAAAsAAQKgR0ABAIACAijGbJGAAsCAAIACAj7GLJGAAsCABkABAglGHQTADUBAAgAAQjmD1WxAC4AAAAA.',Fa='Falerah:BAAALAADCgYIBwAAAA==.Farvounius:BAAALAAECgEIAQAAAA==.',Fe='Ferelana:BAAALAADCggICAAAAA==.',Fi='Fion:BAABLAAECoEkAAIPAAgIjBcOMQBCAgAPAAgIjBcOMQBCAgAAAA==.',Fl='Flenny:BAAALAADCgcIBwAAAA==.',Fo='Folker:BAAALAAECgcIDgAAAA==.Forestghost:BAAALAADCggIDAAAAA==.Foria:BAAALAAECgYIDAAAAA==.Forsilaiser:BAAALAADCggIGAAAAA==.Foxdeath:BAABLAAECoEkAAILAAcIfx6aSwA1AgALAAcIfx6aSwA1AgABLAAECggIJwAEADAcAA==.',Fr='Franziskaner:BAAALAADCggIFAAAAA==.Froddel:BAAALAAECgIIAgAAAA==.',Fu='Fungî:BAAALAADCgIIAgAAAA==.',['Fü']='Fürchtegott:BAAALAAECgYICQAAAA==.',Ga='Galaniel:BAAALAADCgEIAQAAAA==.Galthaz:BAAALAADCggIDAABLAAECggIJwANAPkTAA==.Garrok:BAAALAADCggICAABLAAECggIIAAHANMQAA==.',Ge='Getreal:BAABLAAECoEkAAMPAAcINRLnZQCIAQAPAAcIvxHnZQCIAQAaAAMIPQvtJQCUAAAAAA==.',Gl='Glotzer:BAABLAAECoEVAAIRAAYI5gmojgAfAQARAAYI5gmojgAfAQAAAA==.',Go='Gojosatoru:BAABLAAECoEWAAISAAcIlBlhTgANAgASAAcIlBlhTgANAgAAAA==.Gorash:BAAALAADCgcIAwAAAA==.',Gr='Graggyice:BAAALAAECggIDwAAAA==.Gray:BAABLAAECoEXAAIKAAcIBRH6JwCBAQAKAAcIBRH6JwCBAQAAAA==.Greeven:BAABLAAECoEaAAILAAgIASCXLwCOAgALAAgIASCXLwCOAgAAAA==.Gremory:BAAALAAECgYIDgABLAAFFAYIGAAGAI8UAA==.Grishnágh:BAAALAAECgcIBwAAAA==.Groundzero:BAAALAAECgUIDAAAAA==.Großdobby:BAABLAAECoEeAAIbAAgIJyIBBwAPAwAbAAgIJyIBBwAPAwAAAA==.',Gu='Gulfim:BAABLAAECoEiAAIcAAgIuR32FgClAgAcAAgIuR32FgClAgAAAA==.Guruno:BAAALAADCggIIAAAAA==.',Gw='Gwinever:BAAALAAECgUICAAAAA==.',He='Hesekaß:BAAALAAECgIIAgAAAA==.',Hi='Hidratos:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Highsound:BAABLAAECoEgAAIEAAgI1B2rGACQAgAEAAgI1B2rGACQAgAAAA==.Hilond:BAABLAAECoEaAAMdAAgI4QzSHwAyAQAdAAcIMgrSHwAyAQAXAAgI+BAAAAAAAAAAAA==.Hinat:BAABLAAECoEYAAIbAAgIxggnNACAAQAbAAgIxggnNACAAQAAAA==.Hirru:BAAALAAECgUIBgAAAA==.',Ho='Holybleach:BAAALAADCgYIBgAAAA==.Hordée:BAACLAAFFIEHAAILAAQIrBHaDwA3AQALAAQIrBHaDwA3AQAsAAQKgR8AAgsACAhXH8UhAMgCAAsACAhXH8UhAMgCAAAA.Hornstar:BAAALAAECgIIAgAAAA==.Hotuaek:BAAALAADCggIIwAAAA==.',Hu='Hunterhulf:BAAALAAECgYICgAAAA==.',Ig='Ignorants:BAAALAADCggICAAAAA==.',Il='Illidana:BAAALAAECgEIAQAAAA==.Ilune:BAAALAADCgEIAQABLAAFFAYIGQAJAOchAA==.',In='Inaria:BAABLAAECoEeAAIRAAYI9BTdYQCXAQARAAYI9BTdYQCXAQAAAA==.Inmodudu:BAABLAAECoEXAAITAAcIASAYFwCDAgATAAcIASAYFwCDAgAAAA==.Inspekteur:BAAALAAECgYICQAAAA==.',Io='Ion:BAAALAAECgMIAwABLAAECgcIGQAeAI4XAA==.',It='Itsmelove:BAACLAAFFIEUAAIHAAYIzCH5AABZAgAHAAYIzCH5AABZAgAsAAQKgScAAwcACAhnI8AFADUDAAcACAhnI8AFADUDAAQABgj7GmA2AMoBAAAA.',Iz='Izgtokh:BAAALAADCggIDAAAAA==.',['Iò']='Iòxól:BAAALAAECgYIDQAAAA==.',Ja='Jayaa:BAAALAAECgMIAwAAAA==.',Je='Jeffeyy:BAAALAADCgMIAgAAAA==.',Jo='Jones:BAAALAAECgIIAgAAAA==.Jordy:BAABLAAECoEtAAIHAAgIWiAxIQBUAgAHAAgIWiAxIQBUAgAAAA==.Joritina:BAAALAADCggICAAAAA==.',Ka='Kadavia:BAAALAADCgIIAgAAAA==.Kalidan:BAAALAADCgcICAAAAA==.Kashram:BAAALAAECgMIAwAAAA==.Katapuldra:BAABLAAECoEWAAMfAAYIyBspLACeAQAfAAYIkxgpLACeAQAXAAQIDxk1DQA6AQABLAAFFAYIGAAKAMQkAA==.',Ke='Kekfist:BAACLAAFFIEPAAIeAAYINxoeAQAiAgAeAAYINxoeAQAiAgAsAAQKgSYAAh4ACAiMJaMCAFoDAB4ACAiMJaMCAFoDAAAA.Kekknight:BAAALAAFFAIIAgABLAAFFAYIDwAeADcaAA==.Kelathel:BAAALAADCgQIBAAAAA==.',Kh='Khorta:BAAALAAECgYIBgAAAA==.',Ki='Kirenda:BAAALAAECgQIAwAAAA==.',Kl='Kleti:BAACLAAFFIEIAAIgAAQIQB82AACdAQAgAAQIQB82AACdAQAsAAQKgSAAAiAACAj1JTkAAHYDACAACAj1JTkAAHYDAAEsAAUUBQgFABwA3RMA.Kletir:BAAALAADCggICAABLAAFFAUIBQAcAN0TAA==.Kletom:BAACLAAFFIENAAIhAAQIHR2AEABoAQAhAAQIHR2AEABoAQAsAAQKgR0AAiEACAjKI0APABgDACEACAjKI0APABgDAAEsAAUUBQgFABwA3RMA.Kletos:BAACLAAFFIEFAAIcAAUI3RNqBwBuAQAcAAUI3RNqBwBuAQAsAAQKgRYAAhwACAiwHJUcAIUCABwACAiwHJUcAIUCAAAA.',Kn='Knutschikuss:BAAALAADCgQIBAAAAA==.',Kr='Krabàt:BAAALAAECgUIBgAAAA==.Kranklur:BAAALAAECgYIEQAAAA==.',Ky='Kyrant:BAABLAAECoEZAAISAAcICB7NOQBQAgASAAcICB7NOQBQAgAAAA==.Kyrantpala:BAAALAAECggICAABLAAECggIGQASAAgeAA==.',['Kñ']='Kñøbísham:BAAALAADCggICAAAAA==.',La='Lana:BAAALAAECgYIDwAAAA==.Lanada:BAAALAADCgYIBgAAAA==.Langier:BAAALAADCgUIBQAAAA==.Larunami:BAAALAAECgYIEwAAAA==.Lauchzelot:BAACLAAFFIEYAAIKAAYIxCTUAAAfAgAKAAYIxCTUAAAfAgAsAAQKgSAAAgoACAhkJmMBAHQDAAoACAhkJmMBAHQDAAAA.',Le='Legos:BAAALAADCgYIBgAAAA==.Leline:BAABLAAECoEWAAILAAcIUBJ/ggC9AQALAAcIUBJ/ggC9AQAAAA==.Lelíana:BAAALAAECgMIAwAAAA==.',Li='Lieebe:BAAALAAECgIIAgAAAA==.Liladri:BAABLAAECoEVAAIDAAgIYgQ1dAD6AAADAAgIYgQ1dAD6AAAAAA==.Limoian:BAAALAADCgUICQAAAA==.Lionius:BAAALAAECgIIAgAAAA==.',Lo='Lolxd:BAACLAAFFIETAAIPAAYIThp2BgDaAQAPAAYIThp2BgDaAQAsAAQKgSgAAg8ACAg/JQUGAFsDAA8ACAg/JQUGAFsDAAAA.Lovemeowz:BAAALAAECgYIBgABLAAECgcIEgABAAAAAA==.',Lu='Lungenpest:BAABLAAECoEYAAQiAAcIqxlaHgDeAAARAAYIhBefawB8AQAiAAMIEBxaHgDeAAAQAAEIcw53hQA8AAAAAA==.Luri:BAABLAAECoEgAAQHAAcIUBSiPgC4AQAHAAcIUBSiPgC4AQAEAAUI6BFoYwDyAAAgAAEIgAjnNQAqAAAAAA==.Lutáwen:BAAALAADCgcICAAAAA==.',Ly='Lyskândéllia:BAAALAADCggIDwAAAA==.Lytha:BAABLAAECoEkAAIJAAcImh0QTgApAgAJAAcImh0QTgApAgAAAA==.',['Lá']='Láúrá:BAAALAAECggICwABLAAFFAYIFAAhAI4YAA==.',['Ló']='Lótta:BAAALAAECgIIAgAAAA==.',Ma='Maezee:BAAALAAECgYIBgAAAA==.Mahba:BAAALAADCggICAAAAA==.Mahina:BAAALAADCggICAAAAA==.Maja:BAAALAAECggICAABLAAECggIHwAcANAaAA==.Majiko:BAAALAAECgIIAgAAAA==.Malika:BAAALAAECgUICAAAAA==.Marvs:BAAALAAECgYIDQAAAA==.Mawu:BAAALAAECgcIEQAAAA==.Mazhug:BAACLAAFFIEGAAILAAII/RcHNACeAAALAAII/RcHNACeAAAsAAQKgSMAAgsACAjtHjUoAKwCAAsACAjtHjUoAKwCAAEsAAUUBwgWAAkArxYA.Maìa:BAABLAAECoEfAAIcAAgI0BpmJQBaAgAcAAgI0BpmJQBaAgAAAA==.',Me='Megu:BAAALAAECgIIAgAAAA==.Melvyn:BAABLAAECoEnAAIYAAgI+yMQAwA5AwAYAAgI+yMQAwA5AwAAAA==.Meridan:BAAALAAECgYIEAAAAA==.Merô:BAABLAAECoEcAAILAAgIoA/jdgDTAQALAAgIoA/jdgDTAQAAAA==.',Mi='Mieuke:BAAALAADCggIFwABLAAECgcIIwASAFAgAA==.Millimaus:BAABLAAECoEjAAIEAAcILQq8TwBSAQAEAAcILQq8TwBSAQAAAA==.',Mo='Monschi:BAAALAAECgIIBAAAAA==.',My='Myrtana:BAAALAAECgYIDwAAAA==.Myrtix:BAAALAADCgYIBgAAAA==.',['Mé']='Mégus:BAABLAAECoEZAAMcAAgIuhePNAAeAgAcAAgIuhePNAAeAgAVAAYIaRrHSAC3AQAAAA==.',Na='Nalia:BAABLAAECoEhAAIWAAcIBwUqGwD4AAAWAAcIBwUqGwD4AAAAAA==.Narak:BAABLAAECoEeAAICAAgIvxVpTgD0AQACAAgIvxVpTgD0AQAAAA==.Narkatoh:BAAALAAECgYIBAAAAA==.Nathan:BAAALAADCgcICQAAAA==.Natroll:BAAALAAECgUIBQAAAA==.Nayla:BAAALAADCggIFgAAAA==.',Ne='Neemi:BAAALAADCgUIBgAAAA==.Nekra:BAAALAAECgYIBwAAAA==.Nelfurion:BAAALAADCggIGAABLAAECggIJwANAPkTAA==.Nerevar:BAABLAAECoEbAAIPAAgIFCO2DwASAwAPAAgIFCO2DwASAwABLAAECggIIQATAEghAA==.',Ni='Nija:BAAALAAECgYIEQAAAA==.Nila:BAABLAAECoEiAAICAAgIeBXoWADYAQACAAgIeBXoWADYAQAAAA==.Nithalf:BAAALAAECggIDgAAAA==.Nizana:BAAALAAFFAYIEQAAAQ==.',No='Noemy:BAAALAAECgUIBQAAAA==.Nofugazi:BAAALAAECgYICgAAAA==.Nogí:BAAALAADCggIFQAAAA==.Notreeforyou:BAAALAAECgUIEQAAAA==.Novaz:BAACLAAFFIEUAAIGAAYI0R1VAQAdAgAGAAYI0R1VAQAdAgAsAAQKgSEAAgYACAiUJNEEABADAAYACAiUJNEEABADAAAA.Novra:BAAALAAECgYIBgAAAA==.',Nu='Nurôfen:BAABLAAECoEvAAIPAAgI8R5HHAC8AgAPAAgI8R5HHAC8AgAAAA==.',Ny='Nyissa:BAACLAAFFIEOAAIVAAMI4A7GEgDbAAAVAAMI4A7GEgDbAAAsAAQKgTUAAhUACAjEHrQWAMcCABUACAjEHrQWAMcCAAAA.Nymtex:BAAALAADCgMIAwABLAAECggIIQATAEghAA==.',['Nê']='Nêltharion:BAABLAAECoEnAAINAAgI+RMALgCIAQANAAgI+RMALgCIAQAAAA==.',On='Onkelztribut:BAABLAAECoEaAAIPAAgIRh0lIwCOAgAPAAgIRh0lIwCOAgAAAA==.',Op='Opaeuke:BAAALAADCgcIDQABLAAECgcIIwASAFAgAA==.',Or='Orcens:BAABLAAECoEcAAIVAAgI+BIVMwAUAgAVAAgI+BIVMwAUAgAAAA==.',Pa='Paralilapsi:BAAALAADCgIIAgABLAADCgcIAwABAAAAAA==.Pauwy:BAAALAAECgcIDQAAAA==.',Pe='Pewpewlove:BAAALAAECgcIEgAAAA==.',Ph='Phainon:BAAALAADCggICAABLAAECggIIgACAHgVAA==.Phänomenalia:BAAALAADCggICAAAAA==.Phänophilox:BAABLAAECoEdAAISAAYIWyBrRQAoAgASAAYIWyBrRQAoAgAAAA==.',Po='Pompa:BAAALAADCggICAAAAA==.Poonga:BAAALAADCgcIDAABLAAECggIJwANAPkTAA==.',Pr='Priceless:BAABLAAECoEXAAIVAAgI4hkwIwBuAgAVAAgI4hkwIwBuAgAAAA==.Prottipippen:BAAALAAECgEIAQAAAA==.',Pu='Puccini:BAAALAADCggIJQAAAA==.',Ra='Raisedfist:BAAALAADCgYIBgAAAA==.Rakhun:BAAALAADCgEIAQABLAAECgUICAABAAAAAA==.Ramius:BAAALAAECggIEAABLAAECggIHwAcANAaAA==.Rarg:BAAALAAECggICAAAAA==.Ravên:BAAALAAECggIDwAAAA==.Razzle:BAAALAADCgYIBgAAAA==.',Rc='Rcp:BAAALAADCgcICQAAAA==.',Re='Reduwene:BAAALAAECggIAgAAAA==.',Rh='Rhaenyra:BAAALAADCggICAAAAA==.',Ri='Rialana:BAAALAAECgUIBQABLAAFFAIICwADAHcSAA==.Rijuet:BAAALAADCggICAAAAA==.Rinda:BAAALAADCgUIBwAAAA==.',Ro='Roguemain:BAAALAAECgMIAwABLAAECggIDAABAAAAAA==.Rolan:BAAALAAECggIDwAAAA==.Roofus:BAAALAAECggIDwAAAA==.Roraria:BAAALAADCggICAAAAA==.',['Ró']='Ró:BAAALAADCgYIBgAAAA==.',['Rô']='Rômulus:BAAALAADCgYIBgAAAA==.',Sa='Sagome:BAABLAAECoEXAAIgAAcIZhz3BQA8AgAgAAcIZhz3BQA8AgAAAA==.Sangheili:BAAALAAECgYIBgAAAA==.Saro:BAACLAAFFIELAAIDAAIIdxIDJgCDAAADAAIIdxIDJgCDAAAsAAQKgSAAAwMACAhKF79UAFkBAAMABwiVGb9UAFkBABMABAgPDOxpAMUAAAAA.Sataníc:BAAALAAECgYIBgAAAA==.Saurfang:BAAALAADCggIBQAAAA==.',Sc='Schaeppy:BAAALAAECgIIAgAAAA==.Schamidog:BAAALAADCggICAAAAA==.Schamordy:BAAALAADCggICAAAAA==.Scheppy:BAAALAADCgcIBwAAAA==.Schoko:BAAALAAECgUIDgAAAA==.',Se='Sempiternai:BAAALAAECgUIBQAAAA==.Serady:BAABLAAECoEZAAICAAYIPgqYrgAiAQACAAYIPgqYrgAiAQAAAA==.Sethan:BAAALAAECgcIEQAAAA==.Sethane:BAAALAAECgcIEAAAAA==.Sethin:BAABLAAECoEYAAIfAAgITgrUKwCgAQAfAAgITgrUKwCgAQAAAA==.Sethon:BAAALAADCgEIAQAAAA==.Seygu:BAAALAADCgcIBwAAAA==.',Sh='Shadowzzarc:BAABLAAECoEUAAMEAAgIdg8LTABjAQAEAAYI4w8LTABjAQAgAAgIiQ8qHADWAAABLAAFFAIIBQAWAK0MAA==.Shalamar:BAAALAAECgYIDgAAAA==.Shampoô:BAAALAADCggIEAAAAA==.Shanie:BAABLAAECoEXAAIeAAYILBs+IQDEAQAeAAYILBs+IQDEAQAAAA==.Shaquiloheal:BAAALAADCggIEgAAAA==.Sharoko:BAABLAAECoEbAAILAAcI9RZUfQDHAQALAAcI9RZUfQDHAQAAAA==.She:BAAALAAECgYIEgAAAA==.Shihirox:BAAALAAECgYIBgAAAA==.Shinjikane:BAAALAADCggICAAAAA==.Shors:BAAALAAECgIIAgAAAA==.Shortydh:BAAALAADCgcIBwABLAAECggIIAAIAJYZAA==.Shortydk:BAAALAAECgcIBwABLAAECggIIAAIAJYZAA==.Shym:BAABLAAECoEXAAIKAAgIqRSqHADaAQAKAAgIqRSqHADaAQAAAA==.',Si='Siahra:BAAALAADCggIFgAAAA==.',Sk='Skanki:BAAALAADCgYIBgAAAA==.Skele:BAACLAAFFIETAAMQAAYI+B9vAACaAQAQAAQI5iFvAACaAQARAAQI4BjiEABRAQAsAAQKgSsAAxEACAgIJhYHAFADABEACAhdJRYHAFADABAACAisI4cEAA8DAAAA.',Sl='Slimshadow:BAAALAADCggICAAAAA==.',So='Solaron:BAAALAADCgEIAQAAAA==.Sombalius:BAAALAAECggIDwAAAA==.Soultaken:BAAALAAECgIIBAAAAA==.Soz:BAAALAAECgEIAQAAAA==.',Sp='Spectator:BAAALAAECgIIAgAAAA==.Spitzohr:BAAALAAECggICAAAAA==.',St='Stranzi:BAABLAAECoEiAAIbAAcIEyKZDAC3AgAbAAcIEyKZDAC3AgAAAA==.',Su='Suguru:BAABLAAECoEsAAIRAAgIAhljNgA0AgARAAgIAhljNgA0AgAAAA==.Superburschi:BAAALAADCgcIBwAAAA==.',Sw='Swiizy:BAACLAAFFIERAAIYAAYI9RtnAAAYAgAYAAYI9RtnAAAYAgAsAAQKgSAAAhgACAgIJasCAEMDABgACAgIJasCAEMDAAAA.Swizzy:BAAALAAECggIDgAAAA==.',Sy='Symaril:BAAALAADCggICAAAAA==.',['Sô']='Sôngôku:BAABLAAECoEXAAISAAcIrROCXwDgAQASAAcIrROCXwDgAQAAAA==.',Ta='Takashisa:BAAALAADCggICAAAAA==.Takayo:BAAALAAECgYICgAAAA==.Talapas:BAAALAADCggICAAAAA==.Taliesín:BAAALAAECgYICgAAAA==.Tallin:BAAALAAECgcIGwAAAQ==.Tamok:BAAALAADCgQIAgAAAA==.Tann:BAAALAADCgcIDQABLAADCggIDgABAAAAAA==.Tanry:BAAALAADCggIDgAAAA==.Tatia:BAAALAAECgEIAQAAAA==.',Te='Telz:BAABLAAECoEtAAIJAAgIKCE+FAAQAwAJAAgIKCE+FAAQAwAAAA==.Teresa:BAAALAAECggIDAABLAAECggIHwAcANAaAA==.',Th='Thalîonmel:BAABLAAECoEVAAIJAAcIyQvMpwBxAQAJAAcIyQvMpwBxAQAAAA==.Thanea:BAABLAAECoEWAAIJAAcIDwptpQB1AQAJAAcIDwptpQB1AQAAAA==.Therodas:BAAALAADCgYICwAAAA==.Thorge:BAAALAADCgIIAgAAAA==.Thorgâll:BAABLAAECoEcAAICAAcIThX8bACnAQACAAcIThX8bACnAQAAAA==.',Ti='Tinuviel:BAAALAADCggICAAAAA==.Tion:BAAALAADCgYIBQAAAA==.Tiranou:BAABLAAECoEZAAIJAAcIThonSwAxAgAJAAcIThonSwAxAgAAAA==.',To='Tobilicious:BAABLAAECoEVAAIjAAcILBVNIwBZAQAjAAcILBVNIwBZAQAAAA==.Torgh:BAAALAAECgQIBAAAAA==.',Tr='Tricky:BAAALAAECgEIAQAAAA==.Tristh:BAAALAAECgMIAwAAAA==.',Ts='Tsabotavoc:BAAALAAECgYIEAAAAA==.',Ty='Tykja:BAAALAAECgYIEwAAAA==.',Ut='Utopian:BAAALAAECgYIDgAAAA==.',Va='Valfá:BAABLAAECoEeAAMEAAgI9B/zDwDgAgAEAAgI9B/zDwDgAgAgAAEIVhewLwBBAAAAAA==.Vanisenpai:BAACLAAFFIEUAAMWAAYIbyRlAAAFAgAWAAUIEiRlAAAFAgAcAAEI8wSjTgBAAAAsAAQKgSgAAxYACAjoJisAAIsDABYACAjoJisAAIsDABwABQhXGAAAAAAAAAAA.Vanko:BAAALAAECggICAAAAA==.',Vi='Vior:BAAALAAECgMIBgAAAA==.',Vo='Voidstorm:BAAALAAECgcIDQABLAAECggIDwABAAAAAA==.Voltaire:BAAALAADCgMIAwAAAA==.',Vy='Vystara:BAAALAAECgMIAwAAAA==.',['Vá']='Váyné:BAAALAAECgcIDQAAAA==.',Wa='Wasserkraft:BAABLAAECoEbAAIcAAcIEQnEnQAIAQAcAAcIEQnEnQAIAQAAAA==.',Wi='Wingulin:BAAALAAECggIEwAAAA==.Winsmonk:BAAALAAECgYIDwABLAAECggIHgAHAL8bAA==.Winspriest:BAABLAAECoEeAAMHAAgIvxuwIgBLAgAHAAgINRmwIgBLAgAgAAUIvxV/EgBOAQAAAA==.',Wy='Wyzzl:BAAALAAECgIIAwAAAA==.',Xa='Xantra:BAAALAAECgQIBQAAAA==.',Xh='Xhalthurac:BAAALAADCgEIAQAAAA==.',Xi='Xinie:BAAALAAECgEIAQABLAAECgcIGwABAAAAAQ==.Xiresa:BAAALAAECgMIAwAAAA==.Xirisa:BAABLAAECoEdAAIcAAgIQCFLDQDmAgAcAAgIQCFLDQDmAgAAAA==.',Xl='Xll:BAAALAADCgYIBgAAAA==.',Xo='Xolinur:BAABLAAECoEmAAIcAAcIlBUaaQCBAQAcAAcIlBUaaQCBAQAAAA==.',Xy='Xynthia:BAABLAAECoEtAAIbAAgI+B8GDAC/AgAbAAgI+B8GDAC/AgAAAA==.',['Xê']='Xêlias:BAABLAAECoEYAAIJAAcIXyVOFgAFAwAJAAcIXyVOFgAFAwAAAA==.',Yd='Yduj:BAABLAAECoErAAIJAAgIUiJyFQAJAwAJAAgIUiJyFQAJAwAAAA==.',Yo='Yoruichì:BAAALAAECgIIAgAAAA==.',Yu='Yun:BAABLAAECoEeAAMUAAYIVBFlIgBSAQAUAAYIrRBlIgBSAQAFAAYIowsXGQARAQAAAA==.Yunaria:BAAALAADCgQIBAAAAA==.Yuukino:BAAALAAECggICgAAAA==.Yuukira:BAABLAAECoEwAAILAAgIiCTqCgA8AwALAAgIiCTqCgA8AwAAAA==.',Za='Zadru:BAAALAADCggICAABLAAECggIJwAYAPsjAA==.Zamazenta:BAABLAAECoEWAAIkAAgI1h3zDQCtAgAkAAgI1h3zDQCtAgAAAA==.',Zo='Zorro:BAABLAAECoEaAAIaAAgIiRsFBgCNAgAaAAgIiRsFBgCNAgAAAA==.',Zu='Zuhlaman:BAAALAAECggICAAAAA==.',Zy='Zykow:BAACLAAFFIEKAAMRAAMIEBcMJgCjAAARAAMIRBQMJgCjAAAQAAEIfwlPJABLAAAsAAQKgScABBEACAicH1AYANoCABEACAicH1AYANoCABAABAglGlNIACoBACIAAwiQD5siALYAAAAA.',Zz='Zzarclolz:BAACLAAFFIEFAAIWAAIIrQyUBQCYAAAWAAIIrQyUBQCYAAAsAAQKgSkAAxYACAhoJPQAAFYDABYACAhoJPQAAFYDABwAAggABsIEAUEAAAAA.',['Zä']='Zähmbar:BAAALAAECgIIAgAAAA==.',['Zü']='Züriana:BAACLAAFFIEMAAIfAAUI4QpJBwBkAQAfAAUI4QpJBwBkAQAsAAQKgSgAAx8ACAhdH/MOALECAB8ACAgUH/MOALECABcABwifHCwEAGgCAAAA.',['Ên']='Êncor:BAAALAAECgUIDwABLAAECgYIDAABAAAAAA==.',['Ín']='Ínever:BAAALAADCgcICgAAAA==.',['În']='Înurias:BAABLAAECoEZAAIJAAgIrhXqWwAFAgAJAAgIrhXqWwAFAgABLAAECggIHgACAL8VAA==.',['Ði']='Ðiana:BAAALAADCgYIBgAAAA==.',['Ÿu']='Ÿuna:BAAALAAECgcICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end