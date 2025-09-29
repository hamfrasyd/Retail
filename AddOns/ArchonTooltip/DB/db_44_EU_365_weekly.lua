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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Monk-Mistweaver','Warrior-Arms','Shaman-Restoration','Shaman-Enhancement','Druid-Balance','Paladin-Retribution','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Holy','Mage-Arcane','Priest-Holy','DemonHunter-Havoc','Evoker-Preservation','Paladin-Protection','DeathKnight-Frost','Priest-Shadow','Mage-Frost','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Warrior-Protection','DemonHunter-Vengeance','DeathKnight-Blood','Hunter-Survival','Mage-Fire','DeathKnight-Unholy','Druid-Feral',}; local provider = {region='EU',realm="Drek'Thar",name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abaddonn:BAAALAADCgcIBwAAAA==.',Ad='Adriou:BAAALAADCgYICgABLAADCggIGQABAAAAAA==.',Ae='Aech:BAABLAAECoEUAAICAAcIXQ2eXwCTAQACAAcIXQ2eXwCTAQAAAA==.Aechmort:BAAALAAECgIIAwAAAA==.Aelinth:BAAALAAECgcIEwAAAA==.Aesindral:BAAALAAECgUIBQAAAA==.',Ai='Airka:BAAALAADCggICAAAAA==.',Ak='Akie:BAAALAAECgYICgAAAA==.Akätsükï:BAAALAAECgYIDgAAAA==.',Al='Alasthôr:BAAALAAECgEIAQAAAA==.Albaphiqua:BAAALAAECgYICQAAAA==.Alduine:BAAALAAECgMIBwAAAA==.Alfond:BAAALAADCgIIAgAAAA==.Aliella:BAABLAAECoEfAAIDAAgIyyXUAAB2AwADAAgIyyXUAAB2AwAAAA==.Allerya:BAAALAADCgEIAQAAAA==.Alopus:BAABLAAECoEZAAMEAAcIbhw3QQAWAgAEAAcIbhw3QQAWAgAFAAMIShnvcgDhAAAAAA==.Altessà:BAAALAADCggIEAAAAA==.Althéa:BAABLAAECoEZAAMGAAcIgBu5GQAIAgAGAAcIgBu5GQAIAgAHAAYISgjgMADjAAAAAA==.Alästhor:BAAALAAFFAIIAgABLAAFFAIIBwAIABEdAA==.Alücärd:BAAALAADCggIBgABLAAECggIEgABAAAAAA==.',Am='Amatøx:BAABLAAECoEdAAMJAAcISBS+WgCjAQAJAAcISBS+WgCjAQAKAAYIxhkHFgBZAQAAAA==.Amäelle:BAAALAAECgYIBgAAAA==.',An='Anarkya:BAABLAAECoEaAAILAAcImQTuXQD6AAALAAcImQTuXQD6AAAAAA==.Andalucia:BAAALAAECgMIAwAAAA==.Angelito:BAAALAAECgYIEQAAAA==.',Ar='Aradil:BAAALAAECgIIAgAAAA==.Aragore:BAABLAAECoEWAAIMAAYIUxekhwCoAQAMAAYIUxekhwCoAQAAAA==.Arch:BAACLAAFFIERAAIFAAYI9iNkAAB9AgAFAAYI9iNkAAB9AgAsAAQKgScAAwUACAhYJl8CAGADAAUACAhHJV8CAGADAAQACAiaI+AhAJcCAAAA.Archanologie:BAAALAAECgQIBgABLAAFFAYIEQAFAPYjAA==.Archany:BAAALAAECgEIAgABLAAFFAYIEQAFAPYjAA==.Arinn:BAAALAAECgIIAgAAAA==.Armogos:BAABLAAECoEYAAINAAcIKBVxKQCsAQANAAcIKBVxKQCsAQAAAA==.Arthlas:BAAALAADCggIDwAAAA==.Artory:BAABLAAECoEsAAQOAAgIvCKKDgByAgAOAAYI1yOKDgByAgAPAAcIbB5lMgBCAgAQAAIIvxHRKwB1AAAAAA==.',As='Asmm:BAAALAADCgQIBAAAAA==.Astroo:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Asyliaa:BAAALAADCgcIBwAAAA==.',Au='Aulit:BAABLAAECoEVAAMRAAcI7QY3PgAnAQARAAcI7QY3PgAnAQAMAAcIsgTmzgAjAQAAAA==.Aunix:BAAALAADCggICAABLAAECgcIGQASAMQdAA==.',Av='Avacrown:BAAALAAECggICAAAAA==.',Ay='Ayakan:BAAALAAECgYIBwAAAA==.',Az='Azraëlle:BAAALAAECgUICgAAAA==.Azürÿa:BAAALAADCgcIDgAAAA==.',Ba='Bahpkpas:BAAALAAECgYIBwAAAA==.Bailla:BAAALAADCggIDgAAAA==.Balybalo:BAAALAAECgYIEQABLAAECgYIFAATAKANAA==.Baqui:BAAALAADCgIIAgAAAA==.Barpos:BAAALAADCggIDAAAAA==.Barthas:BAAALAAECgMIAwAAAA==.',Be='Beleti:BAAALAAECgUIBwAAAA==.Belgafon:BAABLAAECoEiAAIEAAgIASTfDgAKAwAEAAgIASTfDgAKAwAAAA==.Beÿla:BAAALAADCgYIBgAAAA==.',Bi='Bibinounette:BAAALAADCgcICQAAAA==.Bipboup:BAAALAADCgMIBAAAAA==.Bistouris:BAAALAADCgcICgAAAA==.',Bl='Blackfast:BAABLAAECoEeAAIEAAcIOQuMjQBbAQAEAAcIOQuMjQBbAQAAAA==.Blacknike:BAAALAADCgMIBQABLAAECgYIHgAUAFsMAA==.',Bo='Bonnepinte:BAAALAAECgYIBgABLAAECgcIGAAJAFocAA==.Boomeuh:BAAALAADCgcIBwAAAA==.Borussia:BAAALAAECgIIAgAAAA==.Boukitoos:BAAALAAECgYICgABLAAECggIFAAFALccAA==.Boupboup:BAAALAAECgEIAwAAAA==.',Bu='Bubss:BAAALAADCggIEAAAAA==.',['Bø']='Børatgirl:BAAALAAECggICwABLAAECggIDgABAAAAAA==.Børk:BAAALAAECgYIBwAAAA==.',Ca='Carenath:BAAALAAFFAIIAwAAAA==.Cataleyaa:BAAALAAECgYIBgABLAAFFAIIBQAPAOAQAA==.Catalleya:BAABLAAECoEUAAMVAAgIvR8fDAA/AgAVAAYIhiAfDAA/AgANAAYINxcZKQCvAQABLAAFFAIIBQAPAOAQAA==.Catalleyaa:BAACLAAFFIEFAAIPAAII4BAtKgCZAAAPAAII4BAtKgCZAAAsAAQKgRwAAw8ACAjhHR0mAIECAA8ACAh5Gx0mAIECAA4ABQi2H/owAIgBAAAA.Cattalleya:BAAALAAECgYIEwABLAAFFAIIBQAPAOAQAA==.Catäclysme:BAAALAAECgMIAwAAAA==.',Ch='Chamaro:BAAALAAECgYICAABLAAECggIIwAMAL4kAA==.Chamezouls:BAAALAAECgQIBAABLAAECggIKgAJAJYeAA==.Chamøu:BAAALAAECgEIAQAAAA==.Chandail:BAABLAAECoEhAAIEAAcIeRPOagClAQAEAAcIeRPOagClAQABLAAECggIMAADAEINAA==.Chlo:BAAALAAECgcICgAAAA==.Chmanamie:BAAALAAECgEIAQAAAA==.Chtibidi:BAAALAAECgYIEwAAAA==.Chucknorriz:BAACLAAFFIEIAAISAAMIawgCIADHAAASAAMIawgCIADHAAAsAAQKgScAAhIACAhmGq0vAGwCABIACAhmGq0vAGwCAAAA.Chuupiih:BAABLAAECoEeAAIJAAgIGhdrOgAGAgAJAAgIGhdrOgAGAgAAAA==.',Ci='Cibella:BAAALAADCggIJQAAAA==.Cide:BAABLAAECoEWAAMLAAYItB1iKgDuAQALAAYItB1iKgDuAQADAAII8xOyoABtAAAAAA==.',Co='Coldn:BAAALAAECggICAAAAA==.',Cr='Crackitos:BAABLAAECoEUAAIFAAgItxxxFQCjAgAFAAgItxxxFQCjAgAAAA==.Cranemp:BAAALAADCgQIBAABLAAECgYIFQAWABkfAA==.',['Câ']='Câlindra:BAAALAADCggIDwAAAA==.',['Cå']='Cållisto:BAAALAADCgcIBwAAAA==.',Da='Daliâ:BAABLAAECoEXAAIXAAcIQg26nwCEAQAXAAcIQg26nwCEAQABLAAECggIHAAMANIYAA==.Damvache:BAAALAAECggIEAAAAA==.Daneo:BAAALAAECgYIDgAAAA==.Daria:BAAALAAFFAMIAwAAAA==.Darkjackblak:BAAALAAECgYIBgAAAA==.',De='Demoniakie:BAABLAAECoEdAAMOAAgIORdVEwBCAgAOAAgIAxZVEwBCAgAQAAcIMBE7DADUAQAAAA==.Demora:BAAALAADCggICAABLAAECgcIHgAOAHsbAA==.Demyxo:BAAALAAECgcIBwAAAA==.Destring:BAAALAADCggIHgAAAA==.',Dh='Dheekay:BAAALAADCgcICQABLAAFFAMICAASAGsIAA==.Dhibride:BAABLAAECoEbAAIUAAYI8RUhgQCQAQAUAAYI8RUhgQCQAQAAAA==.',Di='Diukez:BAACLAAFFIEGAAMFAAIIDRfFGgCLAAAFAAIIixPFGgCLAAAEAAEIZyNJPQBeAAAsAAQKgR0AAwUACAg/IDscAGsCAAUACAiEGzscAGsCAAQACAiHG0UvAFkCAAAA.',Dk='Dkapitch:BAAALAAECgEIAQAAAA==.',Dr='Dracobuzz:BAAALAAECgYIDQAAAA==.Drakotec:BAAALAAECgYIBgAAAA==.Dreyk:BAAALAAECgYICwAAAA==.Droganz:BAABLAAECoEnAAIYAAgIZhoLHQBpAgAYAAgIZhoLHQBpAgAAAA==.Droopi:BAABLAAECoEUAAIXAAgIKBlHOwBjAgAXAAgIKBlHOwBjAgAAAA==.',Dw='Dwala:BAAALAAECgYIEQAAAA==.',['Dä']='Dätcham:BAAALAAECgMIBgAAAA==.',['Dé']='Démézia:BAABLAAECoEWAAIHAAcINhwsEQAsAgAHAAcINhwsEQAsAgAAAA==.',Ed='Edrok:BAAALAAECgQIBAAAAA==.',Ef='Efinwel:BAACLAAFFIEHAAIDAAMImhngCAAPAQADAAMImhngCAAPAQAsAAQKgSwAAgMACAgpI1cFACcDAAMACAgpI1cFACcDAAAA.',El='Eldenmer:BAAALAADCggICAAAAA==.Elfanaa:BAAALAAECggIDwAAAA==.Ellenya:BAAALAAECgcIEwAAAA==.Ellîath:BAAALAADCggICAAAAA==.Elrin:BAAALAADCggIDQAAAA==.Eltinoo:BAAALAAECgYICAABLAAECggIIwAMAL4kAA==.Elundril:BAACLAAFFIEIAAIZAAMISRMdBADlAAAZAAMISRMdBADlAAAsAAQKgScAAxkACAjjI8ADAEgDABkACAjjI8ADAEgDABIAAghFD0nHAHIAAAAA.Elunlock:BAAALAADCgYICwAAAA==.',Em='Emeental:BAAALAADCggIFgABLAAECgYICgABAAAAAA==.Emilayah:BAAALAAECgEIAQAAAA==.',En='Enaeco:BAAALAAECgQIBgAAAA==.',Er='Erandil:BAAALAAECgYICgAAAA==.Eregrith:BAAALAADCgQIBAAAAA==.',Ev='Evengelion:BAABLAAECoEWAAIKAAYIIBwNDQDwAQAKAAYIIBwNDQDwAQAAAA==.',Ex='Exonar:BAABLAAECoEeAAIDAAgIqRlCJwAYAgADAAgIqRlCJwAYAgAAAA==.',Fa='Falaris:BAAALAADCggIEwAAAA==.Favylhee:BAAALAAECgQIBAAAAA==.Favymorph:BAAALAAECgQIBAAAAA==.',Fe='Feeg:BAAALAADCggIDAABLAAECgQIBAABAAAAAA==.Feig:BAAALAAECgQIBAAAAA==.Felicita:BAAALAADCgYIBgAAAA==.Felistìria:BAACLAAFFIEHAAIDAAMIYBYwDADfAAADAAMIYBYwDADfAAAsAAQKgSEAAgMACAjyIBsMANsCAAMACAjyIBsMANsCAAAA.',Fg='Fgez:BAAALAAECgIIAQABLAAECggIGgAMADobAA==.',Fl='Flemethe:BAAALAAECgYICQAAAA==.Floribella:BAAALAAECgYICwAAAA==.',Fr='Francislalam:BAABLAAECoEeAAIIAAcICBIoDwC8AQAIAAcICBIoDwC8AQAAAA==.Frostal:BAABLAAECoEcAAMaAAgIfh2+DAC6AgAaAAgIfh2+DAC6AgAbAAcIaxNuGACoAQABLAAFFAIIBgAXAJASAA==.Frostaldk:BAACLAAFFIEGAAIXAAIIkBKaPwCUAAAXAAIIkBKaPwCUAAAsAAQKgRcAAhcACAiuILwXAPcCABcACAiuILwXAPcCAAAA.Frst:BAAALAAECgYIEQAAAA==.Frøstal:BAAALAAFFAIIAgABLAAFFAIIBgAXAJASAA==.Frøstaly:BAAALAAFFAIIAgABLAAFFAIIBgAXAJASAA==.Frøøsty:BAABLAAECoEVAAIZAAYItwveQgA7AQAZAAYItwveQgA7AQAAAA==.',Fu='Furyh:BAAALAAECgMIAwABLAAECggIHwAMAJgdAA==.',['Fâ']='Fâfnir:BAAALAADCgcIBwAAAA==.',['Fä']='Fäuust:BAABLAAECoEcAAIPAAgIxgvXVAC6AQAPAAgIxgvXVAC6AQAAAA==.',Ga='Gabyy:BAAALAAECgcIBQABLAAECggIIwAMAL4kAA==.Galounaïaa:BAAALAADCgQIBAAAAA==.Gargöl:BAAALAAECgYIEwAAAA==.',Ge='Gemna:BAAALAADCggIDAABLAAECgMIBgABAAAAAA==.',Gh='Ghorim:BAAALAADCgUIBQAAAA==.',Gl='Glenn:BAAALAADCggICAAAAA==.',Gn='Gnömînette:BAAALAADCgQIBAAAAA==.',Go='Gougueulkar:BAAALAAECgcIEQAAAA==.Gozz:BAAALAADCgcIBwAAAA==.',Gr='Granork:BAAALAADCggIEAAAAA==.Grimlemort:BAAALAADCgcIBwAAAA==.Grinderwald:BAAALAAECgYIBgABLAAECggIIgAbAO8fAA==.',Gu='Gunterr:BAAALAAECggIDgAAAA==.',['Gä']='Gällaad:BAAALAADCgYIBgAAAA==.',['Gë']='Gënocee:BAAALAAECgYIDAAAAA==.',Ha='Hadryel:BAABLAAECoEVAAIcAAYIMhaWDgCHAQAcAAYIMhaWDgCHAQAAAA==.Haldises:BAAALAAECgEIAQAAAA==.Haldra:BAAALAADCgcIBwABLAAFFAYIDwANABkkAA==.Hanax:BAACLAAFFIEHAAIIAAIIER1RAgCvAAAIAAIIER1RAgCvAAAsAAQKgSwAAggACAidJaIAAG8DAAgACAidJaIAAG8DAAAA.Hansa:BAAALAADCgEIAQAAAA==.Hansah:BAAALAAECggIDgAAAA==.Hansaplastus:BAABLAAECoEbAAMdAAgI4BarJgBUAgAdAAgI4BarJgBUAgAJAAEIrA+DDAEqAAAAAA==.Hastérion:BAAALAAECgUIBwAAAA==.',He='Hesseth:BAAALAAECgQICAAAAA==.',Hi='Hillidanl:BAAALAADCgcIBwAAAA==.Hixae:BAABLAAECoEZAAISAAcIxB0qNwBLAgASAAcIxB0qNwBLAgAAAA==.',Hj='Hjell:BAAALAAECgYIDQAAAA==.',Hu='Hugnir:BAABLAAECoEYAAIJAAcIWhwxNAAcAgAJAAcIWhwxNAAcAgAAAA==.Hulktar:BAAALAADCggICAAAAA==.Hulkutir:BAAALAAECgUICgAAAA==.Huma:BAAALAAECgcICwAAAA==.Hunthera:BAAALAAECgYIEQAAAA==.',Ib='Ibrides:BAAALAADCggICwAAAA==.',Id='Idres:BAAALAADCggICAAAAA==.',If='Ifagwe:BAABLAAECoEkAAIDAAgI4iHxCAD6AgADAAgI4iHxCAD6AgAAAA==.Ifni:BAABLAAECoEXAAIRAAcIohmbGwADAgARAAcIohmbGwADAgAAAA==.',Ir='Irzak:BAAALAADCggIIAABLAAECgcIHwAEAHoeAA==.',Is='Isilan:BAAALAADCgYIBgAAAA==.Isille:BAAALAAECgYIEQAAAA==.Ismir:BAAALAADCgUICAABLAADCggIGQABAAAAAA==.',Ja='Jackychäm:BAACLAAFFIEGAAIdAAII9AZ6IwCGAAAdAAII9AZ6IwCGAAAsAAQKgSYAAh0ACAjkG48dAI8CAB0ACAjkG48dAI8CAAAA.Jaladin:BAAALAADCgcIBwAAAA==.Janalai:BAAALAAECgIIAgAAAA==.Janopetrus:BAABLAAECoEUAAITAAYIoA3rYQAvAQATAAYIoA3rYQAvAQAAAA==.',Je='Jessica:BAAALAADCggIFgAAAA==.Jesterdead:BAAALAADCggIHAAAAA==.',Ji='Jiltz:BAABLAAECoEaAAIeAAcI7CF+DwCVAgAeAAcI7CF+DwCVAgAAAA==.Jimangel:BAABLAAECoEfAAIDAAcIshuGIgAyAgADAAcIshuGIgAyAgAAAA==.Jimillin:BAABLAAECoEZAAIMAAgI6BroNAB0AgAMAAgI6BroNAB0AgAAAA==.',Ju='Juc:BAAALAAECgQIBAAAAA==.Julrican:BAAALAAECgYIBgAAAA==.Junip:BAAALAADCggIDgABLAAECgMIBgABAAAAAA==.',['Jé']='Jékill:BAAALAADCggICAAAAA==.',Ka='Kaalos:BAAALAADCgEIAQAAAA==.Kapitch:BAABLAAECoEfAAIMAAYIKBvDcADUAQAMAAYIKBvDcADUAQAAAA==.Karaël:BAAALAADCgYICgAAAA==.Kassyky:BAAALAADCgIIAgAAAA==.Kattarakte:BAAALAAECgYICgAAAA==.Kayanhi:BAAALAADCggIHQAAAA==.',Ke='Kealia:BAAALAADCggIDQAAAA==.Kellow:BAAALAADCggIGAAAAA==.Kelra:BAAALAADCgYICgAAAA==.Kelrà:BAAALAADCgYIBgABLAADCgYICgABAAAAAA==.Keridan:BAABLAAECoEZAAIfAAcI8BlbFAD5AQAfAAcI8BlbFAD5AQAAAA==.Kerrigan:BAAALAAECgIIAgAAAA==.Ketamïne:BAAALAAECgYICwABLAAECggIEgABAAAAAA==.Kewaux:BAAALAAECggIDgAAAA==.',Kh='Khaliks:BAAALAAECgcIDQAAAA==.Khayani:BAAALAADCggIFgAAAA==.',Kl='Klaplouf:BAAALAADCgYICQABLAAECgYICgABAAAAAA==.',Ko='Kouna:BAAALAADCgEIAQABLAAECggIAQABAAAAAA==.Kouná:BAAALAAECggIAQAAAA==.Koya:BAAALAADCgUIBQAAAA==.',Kr='Krakovia:BAAALAADCgYIBQABLAAECggIIgAEAAEkAA==.Kraoseur:BAAALAAECgYIBgAAAA==.Krimy:BAAALAAECgUIBQAAAA==.',['Kí']='Kíwí:BAAALAADCgEIAQAAAA==.Kíwï:BAAALAADCgYIBgAAAA==.',['Kî']='Kîlâ:BAAALAADCggICQAAAA==.',La='Lacamarde:BAAALAADCggIDwAAAA==.Lanaa:BAAALAAECgQIBAAAAA==.Laênae:BAAALAADCgcIBwAAAA==.',Le='Leelee:BAAALAADCgMIAwAAAA==.Leshammy:BAAALAAECggIEAABLAAFFAIIBgAPAFYgAA==.',Li='Lidius:BAAALAAECgEIAQAAAA==.Lightfor:BAAALAADCggIEAAAAA==.Liivia:BAAALAADCggIFwAAAA==.Liloü:BAAALAADCgYICgAAAA==.Lincce:BAAALAAECgUIBwAAAA==.Litvhi:BAAALAAECgcIDwAAAA==.',Lo='Lovst:BAABLAAECoEWAAIDAAcI4yBwFACPAgADAAcI4yBwFACPAgAAAA==.',Lu='Lulumi:BAAALAADCgUIBgAAAA==.',Ly='Lydhïa:BAAALAADCgcIBwAAAA==.Lystys:BAABLAAECoEsAAITAAgIFQwLRQCbAQATAAgIFQwLRQCbAQAAAA==.',['Là']='Làilah:BAAALAADCggIEAAAAA==.',['Lé']='Léoline:BAABLAAECoEWAAIEAAcI4QyrhgBpAQAEAAcI4QyrhgBpAQAAAA==.Léopard:BAAALAADCgIIAgAAAA==.',['Lë']='Lëön:BAABLAAECoEZAAIUAAcIdxJLbwC1AQAUAAcIdxJLbwC1AQAAAA==.',Ma='Malalesprit:BAAALAADCggICAABLAAECgcIGAAUAFghAA==.Malaufoie:BAAALAADCggICAABLAAECgcIGAAUAFghAA==.Malautronc:BAAALAAECgMIBAABLAAECgcIGAAUAFghAA==.Malauxyeux:BAABLAAECoEYAAIUAAcIWCG0KQCPAgAUAAcIWCG0KQCPAgAAAA==.Malkut:BAAALAAECgQIBgAAAA==.Mamayet:BAAALAAECgMIAwABLAAFFAIIBQAPAOAQAA==.Margaüx:BAAALAAECgEIAQAAAA==.Maria:BAAALAADCgcIBwAAAA==.Marlo:BAAALAADCgYIBgAAAA==.Maylyne:BAAALAAECgEIAQAAAA==.Mayween:BAAALAAECgYIDQAAAA==.Mañìgøldø:BAAALAADCgQIBAAAAA==.',Me='Meilleur:BAACLAAFFIEGAAICAAIIPQxrJwCTAAACAAIIPQxrJwCTAAAsAAQKgRwAAwIACAhcF+UwAD0CAAIACAhcF+UwAD0CAAgAAQgGD901ACgAAAAA.Melioka:BAAALAADCgcICQAAAA==.Menelle:BAAALAAECgYIBgAAAA==.Meta:BAABLAAECoEnAAIFAAgIMSD9DQDmAgAFAAgIMSD9DQDmAgAAAA==.Metablack:BAAALAAECgEIAQABLAAECggIJwAFADEgAA==.',Mi='Mibz:BAAALAAECgEIAQAAAA==.Mikael:BAAALAAECgYIEQAAAA==.Mikkadoo:BAAALAADCggICAAAAA==.Milléna:BAAALAAECgMIAwAAAA==.Milune:BAAALAAECgQICgAAAA==.Minifigue:BAAALAADCgIIAgAAAA==.',Mo='Mohican:BAAALAADCgcIBwAAAA==.Morbax:BAAALAADCgcIBwAAAA==.Mordore:BAABLAAECoEaAAIZAAcImyEJDQCsAgAZAAcImyEJDQCsAgAAAA==.Mou:BAAALAADCgcIBwAAAA==.',Mu='Mucus:BAAALAAECgQICAAAAA==.Muradroud:BAABLAAECoEbAAIDAAgIJxjRIQA2AgADAAgIJxjRIQA2AgAAAA==.Murasonper:BAAALAADCgIIAgAAAA==.Muroorgamd:BAABLAAECoEUAAMVAAYI3BubEQDhAQAVAAYI3BubEQDhAQANAAMIERVbRwDTAAAAAA==.Musôtensei:BAABLAAECoEXAAMPAAcI0yAUJQCHAgAPAAcI0yAUJQCHAgAQAAMICAz9IQC6AAAAAA==.',My='Myho:BAAALAADCgcICwAAAA==.',['Mà']='Mààt:BAABLAAECoEaAAIMAAgIOhu6OwBbAgAMAAgIOhu6OwBbAgAAAA==.',['Má']='Málycia:BAABLAAECoEYAAIZAAYIsROvNAB6AQAZAAYIsROvNAB6AQAAAA==.',['Mä']='Mäze:BAAALAADCggICgABLAAECgcIFwADAM4SAA==.',['Mé']='Méphystø:BAAALAADCgMIAwAAAA==.',['Më']='Mërlin:BAABLAAECoEVAAILAAgIfg6mNAC2AQALAAgIfg6mNAC2AQAAAA==.',['Mî']='Mîhawk:BAAALAAECgIIAgAAAA==.',Na='Naamu:BAABLAAECoEfAAIUAAgIxRolOwBGAgAUAAgIxRolOwBGAgAAAA==.Nanko:BAACLAAFFIEPAAINAAYIGSTZAABzAgANAAYIGSTZAABzAgAsAAQKgSYAAg0ACAggJqgBAG8DAA0ACAggJqgBAG8DAAAA.Narwel:BAAALAAECgYIDAAAAA==.Nausicää:BAAALAADCgQIBAAAAA==.',Ne='Necronomecan:BAABLAAECoEeAAMOAAcIexsLMACMAQAOAAUIchoLMACMAQAQAAMIuxtAHAD2AAAAAA==.Neer:BAAALAADCggICAAAAA==.',Nh='Nhikell:BAAALAAECgYIDgAAAA==.',Ni='Nielthi:BAAALAADCgQIBAAAAA==.Nightfly:BAAALAAECgQIBAAAAA==.Ninial:BAABLAAECoEdAAIXAAcIyRozWgANAgAXAAcIyRozWgANAgAAAA==.Nitø:BAAALAAECgYIEAABLAAECgcIFwADAM4SAA==.',No='Noadk:BAABLAAECoEaAAMXAAcIQxlBZAD3AQAXAAcIQxlBZAD3AQAgAAEIYAGTQwAXAAAAAA==.Nolah:BAAALAADCgEIAQAAAA==.Normal:BAABLAAECoEWAAIhAAYIXRqWCgDWAQAhAAYIXRqWCgDWAQAAAA==.Nourgortan:BAAALAAECgUICAAAAA==.',Nr='Nretim:BAAALAAECgYIDQAAAA==.',Nu='Nunderran:BAABLAAECoEbAAMSAAgIcBNMQwAcAgASAAgIcBNMQwAcAgAZAAUI7ALJZQCJAAAAAA==.Nuruk:BAAALAADCggICAAAAA==.',['Né']='Néreis:BAAALAAECgcIDgAAAA==.Néreos:BAAALAADCggICAAAAA==.',Ob='Oblione:BAAALAAECgYIDQAAAA==.',Od='Odinsilvest:BAAALAAECgMIAwAAAA==.',Oe='Oeildeglace:BAAALAAECgYIEwAAAA==.',Ol='Olÿmpe:BAAALAADCgUIBQAAAA==.',Or='Orkacham:BAAALAAECgUIBwABLAAECggIHAAUACYcAA==.Orkadk:BAAALAAECgUIBQABLAAECggIHAAUACYcAA==.Orkahunt:BAAALAAECgIIBAABLAAECggIHAAUACYcAA==.Orkaya:BAABLAAECoEcAAIUAAgIJhzyKQCOAgAUAAgIJhzyKQCOAgAAAA==.Orphée:BAAALAADCggICAAAAA==.',Os='Osbørn:BAAALAAECgIIAgAAAA==.',Ox='Oxfuz:BAABLAAECoEiAAMbAAgI7x8EBgDQAgAbAAgIVh8EBgDQAgAaAAcIrhjmHQAPAgAAAA==.',Pa='Palacoco:BAAALAADCggICQAAAA==.Paladania:BAAALAADCgIIAgAAAA==.Paladina:BAAALAADCgcICAAAAA==.Palaric:BAACLAAFFIEMAAIZAAMIyCXcAQBGAQAZAAMIyCXcAQBGAQAsAAQKgSwAAhkACAjXJeoBAG0DABkACAjXJeoBAG0DAAAA.Palibis:BAAALAADCgYICQAAAA==.Paltauren:BAAALAADCgUIBQAAAA==.Papayet:BAABLAAECoEWAAQTAAYI7x/bLgAEAgATAAYIch7bLgAEAgAYAAUIzAwvXAATAQAcAAMIYSDoFwABAQABLAAFFAIIBQAPAOAQAA==.Papillimp:BAABLAAECoEWAAIEAAcIlQyfnAA+AQAEAAcIlQyfnAA+AQAAAA==.',Pe='Peachounette:BAAALAADCggIDwAAAA==.',Ph='Phyçôs:BAAALAAECgYICQAAAA==.',Pi='Pibo:BAABLAAECoEVAAIWAAYIGR9IFgAQAgAWAAYIGR9IFgAQAgAAAA==.Pietà:BAAALAADCgYICgAAAA==.',Po='Poylder:BAABLAAECoEcAAIMAAgI0hhWPABZAgAMAAgI0hhWPABZAgAAAA==.',Pr='Prandine:BAAALAAECgIIAgAAAA==.Pretous:BAABLAAECoEVAAITAAYIUQu/ZAAmAQATAAYIUQu/ZAAmAQAAAA==.Primalforge:BAAALAAECgYIBgABLAAECggIJwAFADEgAA==.',Pu='Purgen:BAAALAAECgMIAwAAAA==.',['Pà']='Pàladine:BAAALAADCgIIAgAAAA==.',Qu='Quake:BAAALAAECgUICAAAAA==.',Ra='Ragasoniic:BAABLAAECoEVAAIFAAYIfg8aXQAqAQAFAAYIfg8aXQAqAQAAAA==.Raglar:BAAALAAECgIIAgAAAA==.Ragoune:BAAALAAECgMIAwAAAA==.Rannèk:BAABLAAECoEZAAIMAAYIAhzSbgDYAQAMAAYIAhzSbgDYAQAAAA==.Ratchet:BAABLAAECoElAAIHAAgImRguDwBLAgAHAAgImRguDwBLAgAAAA==.',Ro='Rocks:BAAALAADCggICAAAAA==.Rodølfus:BAABLAAECoEjAAIMAAYIviQcNQBzAgAMAAYIviQcNQBzAgAAAA==.Rominoo:BAABLAAECoEVAAMiAAYI+hPuDwDOAAASAAUIIRA+lAAsAQAiAAMIohbuDwDOAAAAAA==.Roustougnouk:BAAALAAECggIEwAAAA==.',Rr='Rrocco:BAAALAAECgMIAwAAAA==.Rromanne:BAAALAAECgYIEwAAAA==.',['Ré']='Réjène:BAACLAAFFIEGAAIWAAQIaRGIAwAqAQAWAAQIaRGIAwAqAQAsAAQKgR0AAwwACAiiHnskALkCAAwACAiiHnskALkCABEABggxBslIAO0AAAAA.',Sa='Sacrwar:BAAALAAECgMIAwAAAA==.Saiks:BAAALAAECgYIBgAAAA==.Sazoulsia:BAAALAADCgYIBgAAAA==.',Se='Seipth:BAABLAAECoEdAAIEAAgIpQuWfAB+AQAEAAgIpQuWfAB+AQAAAA==.Senthiene:BAAALAADCggICAAAAA==.Sephreina:BAABLAAECoEmAAIPAAgINRboNAA2AgAPAAgINRboNAA2AgAAAA==.',Sh='Shadka:BAAALAAECgcICwAAAA==.Shadowzoulls:BAAALAADCggIDgABLAAECggIKgAJAJYeAA==.Shank:BAAALAADCgYIBwAAAA==.Sheitann:BAAALAAECgEIAQAAAA==.Shellh:BAAALAADCgUIBAAAAA==.Shemira:BAABLAAECoEkAAIXAAgICBtaMACJAgAXAAgICBtaMACJAgAAAA==.Sheìtan:BAAALAAECgYICgAAAA==.Shoeiliche:BAAALAAECgYIEgAAAA==.',Si='Silverâzz:BAAALAADCggIEAAAAA==.Simbiotik:BAABLAAECoEdAAIJAAcIoyCnJwBNAgAJAAcIoyCnJwBNAgAAAA==.Sindira:BAACLAAFFIEGAAIDAAQIkgSoCgDvAAADAAQIkgSoCgDvAAAsAAQKgRoAAgMACAgWFRw2ANABAAMACAgWFRw2ANABAAAA.Sinergi:BAABLAAECoEmAAIdAAgIbiBIDgAJAwAdAAgIbiBIDgAJAwAAAA==.',Sk='Skildoux:BAABLAAECoEXAAIjAAcI9CBFCwCGAgAjAAcI9CBFCwCGAgAAAA==.',Sn='Snoww:BAAALAAECgYIEQAAAA==.',So='Sobad:BAABLAAECoEXAAIjAAcInAtKIACeAQAjAAcInAtKIACeAQAAAA==.Sohryø:BAAALAAECgYICQAAAA==.Soomeoone:BAABLAAECoEoAAIQAAgIYyNrAQA0AwAQAAgIYyNrAQA0AwAAAA==.',Sq='Squalise:BAAALAADCgEIAQAAAA==.',St='Strikx:BAAALAAECgYIDQAAAA==.Strïke:BAAALAADCgYIBwAAAA==.',Su='Sunkiss:BAAALAADCggICAAAAA==.',Sw='Swaizer:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.',Sy='Sylvariel:BAAALAADCgQIBgAAAA==.Sylyas:BAAALAADCgcIBwAAAA==.Synapse:BAAALAAECggIEgAAAA==.Syska:BAAALAAECgYIDQAAAA==.',['Sé']='Sélénys:BAAALAADCggICAAAAA==.Sémiramis:BAAALAADCgcIBwAAAA==.',['Sê']='Sêven:BAABLAAECoEeAAIUAAYIWwxnrgA2AQAUAAYIWwxnrgA2AQAAAA==.',['Sî']='Sîlverâzz:BAAALAAECgIIAgAAAA==.',Ta='Taehlx:BAABLAAECoElAAIXAAgIYyQqCQBHAwAXAAgIYyQqCQBHAwAAAA==.Takalove:BAAALAADCggIDwAAAA==.Talianna:BAAALAADCgYIBgAAAA==.Talulah:BAABLAAECoErAAIFAAgI1hhRIgA9AgAFAAgI1hhRIgA9AgAAAA==.Taralor:BAABLAAECoEVAAIWAAYI6h6sFgAMAgAWAAYI6h6sFgAMAgAAAA==.Tarsillia:BAAALAAECgYIDQAAAA==.',Te='Teclïs:BAAALAADCggICgAAAA==.Tempestiria:BAAALAAECgYIBgAAAA==.Teraa:BAACLAAFFIELAAIdAAMIjxeoDgD7AAAdAAMIjxeoDgD7AAAsAAQKgSgAAh0ACAgcI1UJADUDAB0ACAgcI1UJADUDAAAA.Tetra:BAAALAAECgMIBgAAAA==.',Th='Thalira:BAACLAAFFIEGAAIYAAII9RfUEwCfAAAYAAII9RfUEwCfAAAsAAQKgRsAAhgACAgZHxEOAPACABgACAgZHxEOAPACAAAA.Thanarion:BAABLAAECoEeAAIMAAcIvRdyZwDoAQAMAAcIvRdyZwDoAQAAAA==.Thaïfaros:BAAALAADCgUIBQABLAAECgcIGgAeAOwhAA==.Thelduin:BAAALAADCggIDAAAAA==.Thingol:BAAALAAECgYICQAAAA==.Thirassi:BAAALAAECgQIBAAAAA==.Thirassy:BAAALAAECgMIAwAAAA==.Thorgniark:BAAALAADCgIIAgAAAA==.Thorpath:BAAALAAECgYIBwAAAA==.Thorpem:BAAALAADCgcIBwAAAA==.Thunringweth:BAAALAADCggICAAAAA==.',Ti='Tiffus:BAAALAADCgEIAQAAAA==.Tigergrrbear:BAAALAAECgMIAwAAAA==.Tiipol:BAAALAAECgYICQAAAA==.Timey:BAAALAAECgEIAQAAAA==.Tiss:BAABLAAECoEVAAIWAAYINxGeLwBEAQAWAAYINxGeLwBEAQAAAA==.',Tm='Tmah:BAACLAAFFIEGAAIYAAUIDQdCCABjAQAYAAUIDQdCCABjAQAsAAQKgRwAAhgACAhdHNcTALgCABgACAhdHNcTALgCAAAA.Tmahunt:BAAALAAECggICAABLAAFFAUIBgAYAA0HAA==.',To='Totemi:BAAALAAECgYIEgAAAA==.Toupits:BAAALAADCggICQAAAA==.',Tr='Trakcost:BAAALAAECgYIEQAAAA==.Trollolol:BAAALAADCggICAAAAA==.Troolli:BAAALAADCgcIBwAAAA==.',['Tø']='Tørmentsnøw:BAAALAADCgYIBwAAAA==.',Ul='Ulticre:BAAALAAECgYICQAAAA==.Ultran:BAAALAADCgcICgAAAA==.',Ut='Utbahit:BAAALAAECgYIBgAAAA==.',Uz='Uzukolyo:BAAALAADCggIJgAAAA==.',Va='Vaampa:BAABLAAECoEpAAIEAAgI1h9qFwDUAgAEAAgI1h9qFwDUAgAAAA==.Vadorette:BAAALAADCggIBwAAAA==.Valithria:BAAALAADCgYIBgAAAA==.Valkorius:BAAALAADCgQIBAAAAA==.Valtorta:BAAALAADCgUIBQAAAA==.Valtéria:BAAALAAECgYIDAAAAA==.Varay:BAABLAAECoEbAAIXAAYIECV2OwBiAgAXAAYIECV2OwBiAgAAAA==.',Ve='Versyngetori:BAAALAADCggIGQAAAA==.',Vh='Vhal:BAAALAAECgUIBQAAAA==.',Vi='Vieillepoo:BAAALAADCgcIEwABLAAECgYICgABAAAAAA==.Vin:BAAALAAECgcIDwAAAA==.',Vl='Vlaad:BAAALAADCgcIBwAAAA==.Vladiléna:BAAALAAECgUIBQAAAA==.',Vo='Volôloîn:BAAALAADCgQIBQAAAA==.',Vy='Vyraik:BAABLAAECoEXAAMJAAYImh91OwACAgAJAAYImh91OwACAgAdAAYIqg4/XgBmAQABLAAECgcIHwAEAHoeAA==.Vyvette:BAAALAAECgEIAQABLAAECgcIHwAEAHoeAA==.Vyvy:BAABLAAECoEfAAIEAAcIeh5dNABEAgAEAAcIeh5dNABEAgAAAA==.',['Và']='Vàldismonk:BAAALAAECgYIEAAAAA==.',['Vî']='Vîncus:BAAALAAFFAIIBAAAAA==.',['Vô']='Vôlo:BAAALAADCgcICQAAAA==.',Wa='Warnou:BAAALAAECgEIAQAAAA==.Wayreth:BAACLAAFFIEHAAISAAIIWBY6LQCfAAASAAIIWBY6LQCfAAAsAAQKgSwAAxIACAiMHcMkAKECABIACAiMHcMkAKECABkAAQhUIZFxAFsAAAAA.Waytt:BAAALAADCgUIBQAAAA==.',We='Wespe:BAABLAAECoEgAAIHAAgIHBjNDwBAAgAHAAgIHBjNDwBAAgAAAA==.',Wu='Wurta:BAAALAAECgcIEwAAAA==.',Wy='Wyksaelle:BAABLAAECoElAAIFAAgIaRocHQBjAgAFAAgIaRocHQBjAgAAAA==.',['Wä']='Wäyätt:BAAALAAECgUICAAAAA==.',Xa='Xaltor:BAAALAADCgMIAwAAAA==.Xaluneth:BAAALAADCgcIBwAAAA==.Xare:BAAALAADCgIIAgAAAA==.',Ya='Yapa:BAABLAAECoEUAAIDAAYISBcrPQCwAQADAAYISBcrPQCwAQAAAA==.',Ye='Yetibigoo:BAAALAAECggIDgAAAA==.',Yg='Yggdräsïl:BAABLAAECoEXAAQDAAcIzhK9PwClAQADAAcIzhK9PwClAQAkAAYISwvJJQAsAQALAAQIgRDKYADsAAAAAA==.',Yo='Yolos:BAAALAADCggICAAAAA==.Yoxi:BAAALAAECgYICwAAAA==.',Yu='Yuurei:BAABLAAECoEfAAIEAAgIeSExFQDiAgAEAAgIeSExFQDiAgAAAA==.',Za='Zangatsu:BAAALAADCgMIAwAAAA==.Zargos:BAAALAADCggIFQAAAA==.',Ze='Zedya:BAAALAAECgMIAwAAAA==.',Zi='Ziboud:BAAALAAECgYIEwAAAA==.',Zl='Zllatan:BAAALAADCgcIBwAAAA==.',Zo='Zolyme:BAAALAAFFAIIAgAAAA==.',['Zä']='Zängarrä:BAAALAADCggIEgAAAA==.',['Äl']='Äldaron:BAAALAAECgYIEQAAAA==.',['Är']='Ärch:BAAALAAECgYICwABLAAFFAYIEQAFAPYjAA==.',['Él']='Élium:BAABLAAECoEjAAIPAAgIIyACFgDlAgAPAAgIIyACFgDlAgAAAA==.',['Îp']='Îphyøs:BAAALAADCgYIBgAAAA==.',['Ïw']='Ïwïi:BAAALAAECggICQAAAA==.Ïwïidrood:BAAALAAECggIDgAAAA==.',['Øm']='Ømbré:BAABLAAECoEWAAMaAAYIYRp8KADFAQAaAAYIahh8KADFAQAbAAUIHhDXJgAqAQAAAA==.Ømégã:BAAALAAECgEIAQAAAA==.',['Ým']='Ýmir:BAAALAADCggICAAAAA==.',['ßo']='ßoukitos:BAAALAAECgYIEAABLAAECggIFAAFALccAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end