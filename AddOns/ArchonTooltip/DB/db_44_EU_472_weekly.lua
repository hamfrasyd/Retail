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
 local lookup = {'Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Unknown-Unknown','Rogue-Subtlety','Hunter-BeastMastery','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warlock-Demonology','Druid-Restoration','Druid-Feral','Hunter-Survival','Warrior-Arms','Hunter-Marksmanship','Shaman-Enhancement','Rogue-Outlaw','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Monk-Mistweaver','Monk-Brewmaster','Mage-Frost','Paladin-Holy','Rogue-Assassination','Mage-Arcane','Monk-Windwalker','Druid-Balance','Paladin-Protection','Druid-Guardian','Mage-Fire',}; local provider = {region='EU',realm='Todeswache',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aanwynn:BAAALAAECgUIBQAAAA==.',Ab='Abrich:BAABLAAECoEYAAIBAAcI3iD2MgA5AgABAAcI3iD2MgA5AgAAAA==.',Ak='Akando:BAAALAAECgIIAgAAAA==.Akazuki:BAAALAAFFAEIAQAAAA==.',Al='Alani:BAAALAADCggIEwAAAA==.Alastair:BAAALAADCgEIAQAAAA==.',An='Aninja:BAAALAAECgYIEAAAAA==.Annahmezwang:BAAALAAECgYIEgAAAA==.Anpu:BAABLAAECoEbAAICAAcIYh9MJABfAgACAAcIYh9MJABfAgAAAA==.Antala:BAAALAAECgIIAwAAAA==.',Ar='Aradon:BAABLAAECoEWAAIDAAgIMR8rIADEAgADAAgIMR8rIADEAgAAAA==.Aranko:BAAALAADCgcIBwAAAA==.Aredus:BAAALAADCgUIBQAAAA==.Artemïs:BAAALAADCggIDgAAAA==.',As='Asghar:BAAALAAECgcIEQAAAA==.Ashmar:BAAALAAECgcICAAAAA==.Astilan:BAAALAAECgMIAwAAAA==.Astilanas:BAAALAAECgUICgAAAA==.Asunagosa:BAAALAAECgIIAgAAAA==.',At='Athene:BAAALAAECgcIEAAAAA==.',Av='Avundadrhiel:BAABLAAECoEUAAMEAAcIhRFltABnAQAEAAYI/Q9ltABnAQAFAAIINBCHNQBwAAAAAA==.',Az='Azmodan:BAAALAADCgcIBwAAAA==.',Be='Belveth:BAAALAAECgYICAAAAA==.',Bl='Blazé:BAABLAAECoEVAAIEAAcIRQQHFgGkAAAEAAcIRQQHFgGkAAAAAA==.',Bo='Bo:BAAALAAECgUIBQAAAA==.Bodyx:BAAALAADCgIIAgABLAAECggICwAGAAAAAA==.Boldar:BAAALAAECgYIBwAAAA==.Bonobo:BAAALAADCggIDgAAAA==.',Br='Bradas:BAAALAADCgcIDQAAAA==.',Bu='Budonaga:BAAALAADCggIDwAAAA==.Bukato:BAAALAAECgUIBQABLAAECgcIBwAGAAAAAA==.',Ca='Cagen:BAABLAAECoEeAAIHAAYI9SJ5DQA3AgAHAAYI9SJ5DQA3AgAAAA==.Caladrier:BAAALAAECgYIDQAAAA==.Calypsó:BAAALAADCggICAAAAA==.Cattori:BAAALAAECgcIBwAAAA==.',Ce='Cephion:BAAALAAECgUIBwAAAA==.',Co='Contagius:BAAALAADCgUIBQAAAA==.Convei:BAAALAAECgIIAgAAAA==.Corvei:BAAALAAECgYICQAAAA==.',Cr='Creez:BAAALAAECgIIAgAAAA==.Crincher:BAABLAAECoEUAAIIAAYI8CAvYwC+AQAIAAYI8CAvYwC+AQAAAA==.',Cu='Cursedtime:BAAALAADCgIIAgAAAA==.',['Cá']='Cássándrána:BAAALAADCggICwAAAA==.',Da='Darcnight:BAAALAAECgMIAwAAAA==.Darke:BAABLAAECoEVAAMJAAcIJhGTWgCtAQAJAAcIJhGTWgCtAQAKAAEInASBPAA3AAAAAA==.',De='Delani:BAAALAADCgcIBwAAAA==.Delumine:BAAALAAECgYIDwAAAA==.Despaira:BAAALAAECgYIBgAAAA==.',Di='Dirtydetlef:BAABLAAFFIEIAAIEAAIIixt/NgCcAAAEAAIIixt/NgCcAAABLAAFFAMIBwAIADciAA==.',Do='Donkai:BAAALAADCggICAAAAA==.Dor:BAAALAAECggIEAAAAA==.Dotterl:BAAALAAECgcIEQAAAA==.',Dr='Dragongirl:BAAALAAECgEIAQAAAA==.Dragonil:BAACLAAFFIEHAAILAAMIrg+8DADaAAALAAMIrg+8DADaAAAsAAQKgSIAAwsACAjcHOkSAIECAAsACAjLHOkSAIECAAwAAwgHGCoRALsAAAAA.Dralon:BAAALAAECgYIEgAAAA==.Drix:BAAALAADCgcIBwAAAA==.Dryss:BAAALAAECggICAAAAA==.',Du='Duduperle:BAAALAADCgYIBgAAAA==.',['Dô']='Dôcválè:BAABLAAECoElAAIHAAgIDQxRFwC3AQAHAAgIDQxRFwC3AQAAAA==.',Ed='Edessa:BAABLAAECoEdAAIIAAcIIByjbACoAQAIAAcIIByjbACoAQAAAA==.Edé:BAACLAAFFIEHAAINAAMIeAjRFQDJAAANAAMIeAjRFQDJAAAsAAQKgSwAAg0ACAiYHcUmALICAA0ACAiYHcUmALICAAAA.',Ei='Eiernockerl:BAAALAAECgQIBQAAAA==.',El='Elfenglanz:BAAALAADCggIKAAAAA==.Elfron:BAABLAAECoEWAAQKAAYI/hM4HQDrAAAJAAYIXxDycwBmAQAKAAMIxBk4HQDrAAAOAAEILQQQjgAmAAAAAA==.Elunarion:BAAALAAECgYIDgAAAA==.',Er='Eradis:BAAALAADCggICAAAAA==.Erimeras:BAAALAADCggICAAAAA==.Erylai:BAABLAAECoEiAAMPAAgIyxm7HwBIAgAPAAgIyxm7HwBIAgAQAAYI+g+wIQBaAQAAAA==.',Es='Estalia:BAABLAAECoEUAAILAAcIDQ98KwCiAQALAAcIDQ98KwCiAQAAAA==.Estix:BAAALAADCgUIBQAAAA==.',Ex='Exaní:BAAALAAECggICAAAAA==.',['Eî']='Eîsblumè:BAAALAAECgYIDwAAAA==.',Fa='Failla:BAAALAAECggICAABLAAFFAIIBQARAPgMAA==.Falissa:BAAALAADCggIDgAAAA==.',Fe='Ferno:BAAALAADCggIDQAAAA==.',Fl='Flashbulb:BAABLAAECoEiAAICAAgI+RUBQAD3AQACAAgI+RUBQAD3AQAAAA==.',Fr='Freesheeps:BAAALAAECgEIAQAAAA==.',Fu='Furian:BAABLAAECoEbAAIEAAYIdBrLhwCzAQAEAAYIdBrLhwCzAQAAAA==.',Ga='Gabareth:BAAALAADCgcIDgAAAA==.Gambít:BAAALAADCgMIAwAAAA==.Garroshtv:BAABLAAECoEUAAISAAcIlRBMEQCgAQASAAcIlRBMEQCgAQAAAA==.',Ge='Gerna:BAAALAAECgYICAAAAA==.',Gh='Ghhostie:BAAALAADCgcIBwAAAA==.Ghostiee:BAAALAAECgIIAgAAAA==.Ghostiiee:BAAALAADCgcIDgAAAA==.Ghostix:BAAALAADCgYIBgAAAA==.',Gi='Girugamesh:BAAALAADCggIJQAAAA==.Gismono:BAAALAAECgUICAAAAA==.Gizmoe:BAABLAAECoEeAAMIAAgIMhCiggB4AQAIAAgIMhCiggB4AQATAAYI4AjTcgDlAAAAAA==.',Go='Goji:BAAALAADCgYIBgABLAAFFAMICQAOALYWAA==.',Gr='Grandel:BAAALAAECggICAAAAA==.Grantlbart:BAAALAADCgEIAQABLAAFFAIICAAUABAaAA==.Grimbo:BAAALAADCgcIDAAAAA==.Grimmfaust:BAAALAAECgYIDAAAAA==.Gronmór:BAAALAADCggICgABLAAECgUIDwAGAAAAAA==.Grîesgram:BAAALAADCgEIAQAAAA==.',Gu='Gufus:BAAALAAECgYICgAAAA==.Gummar:BAAALAAECgEIAQAAAA==.',Ha='Hadja:BAAALAADCggICAAAAA==.Hakanius:BAAALAADCgYIBgAAAA==.Halgrim:BAAALAAECgYIDgAAAA==.Harriola:BAABLAAECoEWAAMHAAcIZBbwGQCbAQAHAAcIZBbwGQCbAQAVAAIIagbhGABVAAAAAA==.',He='Hefekloß:BAAALAADCgMIAwAAAA==.',Hi='Historia:BAAALAADCggICAABLAAECggIHAAIAOcSAA==.',Ho='Honignockerl:BAAALAADCgcIDgAAAA==.Horat:BAAALAAECggICAAAAA==.Houdinchen:BAAALAAECgEIAQABLAAECgcIBwAGAAAAAA==.',Hu='Huntard:BAAALAAECgEIAQAAAA==.',Ic='Icedblue:BAAALAAECgYIBgAAAA==.Ichiki:BAAALAAECgcIEwAAAA==.',Ip='Ipos:BAAALAADCggICAAAAA==.',Ir='Ironhíde:BAAALAAECgMIAwAAAA==.',Is='Isea:BAAALAAECgEIAQAAAA==.',Ja='Jayh:BAABLAAECoElAAMWAAgIohCoOwDGAQAWAAgIohCoOwDGAQAXAAYIGRmCNwDFAQAAAA==.',Ji='Jihnta:BAABLAAECoEYAAIYAAcIEAz5IQCTAQAYAAcIEAz5IQCTAQAAAA==.Jinclap:BAACLAAFFIEIAAIBAAMIeB0bDgAUAQABAAMIeB0bDgAUAQAsAAQKgSUAAgEACAilI5cLADEDAAEACAilI5cLADEDAAAA.Jinoa:BAAALAAECgUICAABLAAFFAMICAABAHgdAA==.',Ka='Kacy:BAACLAAFFIEKAAMTAAUIcRnuBACnAQATAAUIcRnuBACnAQAIAAEIzAYNRgBFAAAsAAQKgRsAAxMACAgmIbcbAHECABMACAi7HbcbAHECAAgABwjuG68+ACYCAAAA.Kaffeemaus:BAAALAADCggIEAAAAA==.Kagari:BAAALAADCggICwAAAA==.Kamilia:BAABLAAECoEbAAIBAAYIiB1hQwD2AQABAAYIiB1hQwD2AQAAAA==.Kanzuli:BAAALAAECgcICgAAAA==.Karlach:BAAALAAECggIBAAAAA==.Karuzô:BAAALAAECgQIBwAAAA==.Kathor:BAAALAADCggIHAAAAA==.Kaykay:BAABLAAECoEYAAIZAAcITyWiBQD1AgAZAAcITyWiBQD1AgAAAA==.',Ke='Kelina:BAAALAAECgIIAgAAAA==.Keltaz:BAAALAAECgIIAwAAAA==.Kevin:BAAALAADCgcICQAAAA==.Keyex:BAABLAAECoEgAAIPAAcIQxxHJQAoAgAPAAcIQxxHJQAoAgAAAA==.Keyshâ:BAABLAAECoEXAAMTAAgI5AyMTwBeAQATAAgIcQyMTwBeAQAIAAEIQQn3FwExAAAAAA==.Keyterrorist:BAAALAAECgYICgAAAA==.Kezzers:BAAALAAECgcIEwAAAA==.',Ki='Kiotsu:BAABLAAECoEUAAIaAAYImhVfHgB0AQAaAAYImhVfHgB0AQAAAA==.',Kl='Klocki:BAAALAADCggICAAAAA==.',Kn='Knobi:BAAALAADCgcIBwABLAAECgcIGAAbAOkfAA==.',Ko='Koriadan:BAABLAAECoEbAAIbAAcIcSElDQCwAgAbAAcIcSElDQCwAgAAAA==.',Kr='Kramurx:BAABLAAECoEnAAMJAAgIWhx9JQCJAgAJAAgIPhx9JQCJAgAOAAIIwRwAAAAAAAAAAA==.Kristallika:BAAALAADCgcIBwABLAAECggICwAGAAAAAA==.',Ku='Kundra:BAAALAADCggICAABLAAFFAIIBQARAPgMAA==.',['Ké']='Késsý:BAABLAAECoEeAAIbAAcIogtZPQBWAQAbAAcIogtZPQBWAQAAAA==.',La='Lariena:BAAALAAECgcIEgAAAA==.',Le='Leerenpfote:BAAALAAECgUIBQAAAA==.Lenula:BAABLAAECoEkAAIbAAcIzgvyOABpAQAbAAcIzgvyOABpAQAAAA==.Levyn:BAAALAADCggIHwAAAA==.',Li='Lichtwache:BAAALAAECgIIAgAAAA==.Linaewen:BAAALAAFFAIIAgAAAA==.Lindortwo:BAAALAADCggICQAAAA==.Line:BAAALAAECggICwAAAA==.Linney:BAABLAAECoEcAAIcAAcIXQ0oNgBaAQAcAAcIXQ0oNgBaAQAAAA==.Lishia:BAAALAADCggIBwAAAA==.',Lo='Lorandia:BAAALAADCggIFAAAAA==.Lorimbur:BAAALAAECgEIAgAAAA==.Lothrax:BAABLAAECoEbAAILAAcI7hG5KAC3AQALAAcI7hG5KAC3AQAAAA==.Loxa:BAAALAADCggIEAAAAA==.',Lu='Lunz:BAAALAAECgYICwAAAA==.',Ly='Lymar:BAAALAADCggIFAAAAA==.',['Lâ']='Lâgâta:BAAALAADCgcIBwAAAA==.',['Lè']='Lègôlàs:BAAALAAECgYIEQAAAA==.',['Lí']='Lízzí:BAAALAAECggICAAAAA==.',['Lø']='Løkii:BAABLAAECoEgAAIXAAgIDCI5CwANAwAXAAgIDCI5CwANAwAAAA==.Løkîî:BAAALAADCggICAAAAA==.',['Lý']='Lýa:BAAALAADCggICAAAAA==.',Ma='Magieperle:BAAALAAECgMIAwAAAA==.Maigann:BAAALAADCggIBwAAAA==.Maldoranei:BAAALAAECgcIBwAAAA==.Malric:BAABLAAECoEiAAIDAAgI2h47JACuAgADAAgI2h47JACuAgAAAA==.Malumvulpis:BAAALAAECgEIAQAAAA==.Marf:BAAALAADCgYIDQABLAAECgcIGwAWAB4UAA==.Marshmellow:BAAALAAECgQIBgABLAAFFAMICQAOALYWAA==.Mashala:BAAALAADCggICgAAAA==.',Me='Meghara:BAACLAAFFIEJAAIIAAMIKQvdGADDAAAIAAMIKQvdGADDAAAsAAQKgSwAAggACAi4H3gdALUCAAgACAi4H3gdALUCAAAA.Melaidor:BAAALAADCgcIDAAAAA==.Melphice:BAABLAAECoEbAAMWAAcIHhQDPwC3AQAWAAcIHhQDPwC3AQAXAAYICg8VTQBeAQAAAA==.Merta:BAAALAAECgcICwAAAA==.Mesmerizêd:BAAALAADCggICAAAAA==.Metzger:BAAALAADCgUIBQAAAA==.Mexylynee:BAAALAADCggIJgAAAA==.',Mi='Mietzi:BAAALAAECggICAAAAA==.Milkmylight:BAAALAAECggICAAAAA==.Mime:BAAALAADCgEIAQAAAA==.Minua:BAAALAADCgYICwAAAA==.Mirel:BAABLAAECoEZAAIDAAcI2A18hACPAQADAAcI2A18hACPAQAAAA==.Mirgnrug:BAAALAADCgYICgAAAA==.Mirà:BAAALAADCggIDQAAAA==.Missdress:BAAALAAECgIIBgAAAA==.',Mo='Moandor:BAABLAAECoEUAAIOAAYIwA0MOQBoAQAOAAYIwA0MOQBoAQAAAA==.Moktharok:BAAALAAECgcIEQABLAAECgcIFAAEAIURAA==.Molyn:BAAALAAECgMIAwABLAAECgcIGAABAJUZAA==.Momji:BAAALAAECgQIBgAAAA==.Monti:BAABLAAECoEuAAIPAAgIdiJTCAADAwAPAAgIdiJTCAADAwAAAA==.Montihex:BAAALAAECgYIBgABLAAECggILgAPAHYiAA==.Mord:BAABLAAECoEaAAMHAAgIuBSGEQD9AQAHAAgIVhSGEQD9AQAdAAMIXBwYTwDGAAAAAA==.Morkarr:BAAALAAECgcIEQAAAA==.',Mu='Muhzan:BAAALAADCggIEQAAAA==.',My='Mydei:BAAALAADCgcIBwAAAA==.Mynxia:BAAALAADCgcIBwAAAA==.',Na='Naamah:BAAALAAECggIAQAAAA==.Nadh:BAAALAADCggIDwAAAA==.Nagar:BAAALAADCggIKAAAAA==.Nagferata:BAAALAAECgYICwAAAA==.Nathanciel:BAAALAAECgMIAgAAAA==.Nathanciél:BAAALAADCggIDAAAAA==.',Ne='Nebeliss:BAAALAAECgEIAQAAAA==.Nestaria:BAAALAAECgcIAQAAAA==.',Ni='Nichdiemamá:BAAALAADCggIDgABLAAECggICwAGAAAAAA==.Niduen:BAAALAAECgIIAgABLAAECggIIAAMANIWAA==.Nightmare:BAABLAAECoEjAAIeAAgIvhCqVwDdAQAeAAgIvhCqVwDdAQAAAA==.',No='Noktrâ:BAABLAAECoEZAAMfAAYI+hjxJwCQAQAfAAYI+hjxJwCQAQAaAAYI/A7HJgAhAQAAAA==.',['Nâ']='Nâriko:BAABLAAECoEYAAIIAAgIFg1LlABVAQAIAAgIFg1LlABVAQAAAA==.',Or='Orista:BAAALAADCggICwAAAA==.',Ou='Out:BAAALAAECgYIBAAAAA==.',Pa='Palahon:BAAALAAECgIIAwAAAA==.Palajunge:BAAALAADCgcIBwAAAA==.Paprika:BAAALAADCgIIAgAAAA==.Pastrami:BAAALAAECgMIBgAAAA==.',Pe='Peachclap:BAAALAAECgQICAABLAAFFAMICQAYAMMeAA==.Peachqt:BAACLAAFFIEJAAMYAAMIwx74BgDRAAAFAAMImRkJBgDpAAAYAAIIMyP4BgDRAAAsAAQKgSwAAxgACAgAJtwAAHADABgACAjyJdwAAHADAAUACAi0IcUFAPUCAAAA.Peachvoid:BAAALAADCgMIAwAAAA==.',Pi='Piknobi:BAAALAAECgIIAgABLAAECgcIGAAbAOkfAA==.',Pl='Plumeria:BAAALAAECgcIEgAAAA==.',Po='Poena:BAAALAAFFAIIAgABLAAFFAMICAAIAJEiAA==.',Pr='Praha:BAAALAADCggIFwAAAA==.Propatria:BAACLAAFFIEHAAIIAAMINyINEAAEAQAIAAMINyINEAAEAQAsAAQKgS8ABAgACAghJiIGAE8DAAgACAgEJiIGAE8DABEABghJI70GADcCABMAAQgYH3SfAFMAAAAA.',['Pé']='Péachqt:BAAALAAECgMIAwABLAAFFAMICQAYAMMeAA==.',Qu='Quashranadon:BAAALAAECgYIDgAAAA==.',Ra='Raidra:BAACLAAFFIEIAAIBAAMIUwpUEwDfAAABAAMIUwpUEwDfAAAsAAQKgSwAAgEACAjmF7MtAFICAAEACAjmF7MtAFICAAAA.Ravên:BAAALAAECgUIBgAAAA==.',Re='Redayra:BAAALAADCggICwAAAA==.Rezralkne:BAAALAAECgUIBQABLAAFFAQIDQAfADcIAA==.Reâlity:BAABLAAECoEbAAMQAAcItxB4HQCEAQAQAAcItxB4HQCEAQAgAAMIPg4FdgCKAAAAAA==.',Ri='Riâs:BAABLAAECoEXAAIZAAcIrQTtMADnAAAZAAcIrQTtMADnAAAAAA==.',Ro='Romancek:BAAALAADCgcIBQAAAA==.Rotunda:BAAALAAECgYIBgAAAA==.',Rt='Rtyxa:BAAALAAECgQIBQAAAA==.',Ru='Ruffnik:BAABLAAECoEbAAMEAAcI4h06VwAXAgAEAAcIFx06VwAXAgAFAAYIARXXGwB2AQAAAA==.Ruhyah:BAAALAADCggIDQABLAAECgcIFAAEAIURAA==.Rumpallotte:BAAALAAECgYIEwAAAA==.Rumpeldk:BAAALAAECgIIAgAAAA==.',['Rê']='Rêkâ:BAAALAADCggIEgAAAA==.',Sa='Sancturio:BAAALAAECgEIAgABLAAFFAMICAABAHgdAA==.Sarasarde:BAAALAAECgUICgAAAA==.Sashia:BAAALAAECgcICwAAAA==.Sashila:BAAALAAECgYIDQAAAA==.',Sc='Schatzl:BAAALAAECgMIAwAAAA==.Schnobi:BAABLAAECoEVAAICAAYIaByfRADoAQACAAYIaByfRADoAQABLAAECgcIGAAbAOkfAA==.Schokotueten:BAAALAAECgEIAQABLAAFFAMICAABAEwMAA==.',Se='Seelenmord:BAAALAAECgEIAQAAAA==.Segelohr:BAAALAADCgYIBgAAAA==.Selan:BAAALAAECgYICAAAAA==.',Sh='Shadowced:BAABLAAECoEYAAIFAAcIvh5IDABiAgAFAAcIvh5IDABiAgAAAA==.Shadowcurse:BAAALAADCggIDwAAAA==.Shadowizzy:BAAALAADCgQIBAABLAAECgYIDgAGAAAAAA==.Shadowtoxin:BAAALAADCggICgAAAA==.Shaminator:BAAALAADCgMIAwABLAAECgEIAgAGAAAAAA==.Shamizzy:BAAALAAECgYIDgAAAA==.Shanks:BAAALAADCgcIBwAAAA==.Sheilá:BAAALAADCgcIDQABLAAFFAMIBQADAKIUAA==.Shiftycent:BAAALAADCggIFQAAAA==.Shinomira:BAAALAAECgMIBAAAAA==.Shirohime:BAABLAAFFIEGAAIEAAIIZgvvTgCLAAAEAAIIZgvvTgCLAAAAAA==.Shrimp:BAACLAAFFIEJAAMOAAMIthaACACzAAAOAAII4huACACzAAAJAAEIXgz2PwBQAAAsAAQKgSwAAw4ACAjMIikLAJwCAA4ACAjmHykLAJwCAAkABggKIbUzAEACAAAA.Shrêk:BAAALAAECgMIAwAAAA==.',Si='Sidewigk:BAAALAAECgYICAAAAA==.Sinthra:BAAALAAECggIEAAAAA==.Six:BAAALAAECgIIAgAAAA==.',Sk='Skênch:BAAALAADCgMIAwAAAA==.',Sm='Smaragdfeuer:BAAALAAECgYIDwAAAA==.',St='Stillwaiting:BAABLAAECoEgAAIIAAYIaiOsPAAtAgAIAAYIaiOsPAAtAgAAAA==.Strawanza:BAACLAAFFIEIAAIUAAIIEBplBACnAAAUAAIIEBplBACnAAAsAAQKgSoAAhQACAjLIGwCABcDABQACAjLIGwCABcDAAAA.Stuffit:BAABLAAECoEWAAINAAcICRHxhQCvAQANAAcICRHxhQCvAQAAAA==.',Su='Sugarmama:BAAALAAECgQIBAABLAAFFAMIBwAIADciAA==.',Sy='Sylfiná:BAABLAAECoEaAAIfAAcIOxOEJQChAQAfAAcIOxOEJQChAQAAAA==.Sylphiê:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâgnix:BAAALAAECgYIDgAAAA==.',['Só']='Sórcery:BAAALAADCggICAAAAA==.',Ta='Taccotoya:BAAALAADCgYICgABLAADCgcIGgAGAAAAAA==.Tauriêl:BAAALAADCggIDAAAAA==.',Te='Terma:BAAALAAECgEIAQAAAA==.',Th='Thais:BAAALAADCggIKAAAAA==.Thallia:BAABLAAECoEVAAITAAgIRxcIJwAhAgATAAgIRxcIJwAhAgAAAA==.Thallium:BAAALAAECgcIEAAAAA==.Thorgash:BAABLAAECoEfAAIhAAgIrgoNLgBWAQAhAAgIrgoNLgBWAQAAAA==.Thraogg:BAAALAAFFAIIAgABLAAFFAMIBwALAK4PAA==.',Ti='Tiala:BAAALAAECgEIAQAAAA==.Tickx:BAAALAAECggICAAAAA==.Tildjar:BAAALAADCgIIAgAAAA==.Timea:BAAALAAECgYIBgAAAA==.Timerin:BAABLAAECoEYAAIiAAcIGAwXFQBIAQAiAAcIGAwXFQBIAQAAAA==.Tiríon:BAAALAADCggIDQAAAA==.',Tr='Tranista:BAAALAADCgcIBwAAAA==.Trinanis:BAAALAAECgcIBwAAAA==.Trubak:BAAALAAECgYIDwAAAA==.Trysopia:BAAALAADCggICQAAAA==.Trîstân:BAAALAAECgMIBgAAAA==.',Ts='Tsuyana:BAAALAAECggICAAAAA==.',Tu='Tuvya:BAABLAAECoEYAAMbAAcI6R9lDwCRAgAbAAcI6R9lDwCRAgAeAAYI8A9agwBjAQAAAA==.',Ty='Tyranusdra:BAABLAAECoEbAAIJAAcIggyraQCCAQAJAAcIggyraQCCAQAAAA==.',['Tâ']='Tâcheles:BAAALAADCggICgABLAAECgcIFAAEAIURAA==.',Ul='Ul:BAAALAAECgMICgAAAA==.',Un='Una:BAAALAAECggIEAAAAA==.Unbrauchbär:BAAALAAECgEIAQAAAA==.',Ur='Urssula:BAAALAAECgYIDQAAAA==.',Va='Vaelyra:BAAALAADCggICAAAAA==.Vandusen:BAAALAADCggICAABLAAECgcIGAABAN4gAA==.Vanity:BAAALAAECggIEAAAAA==.Varul:BAAALAAECgYICAAAAA==.',Ve='Vedekbareil:BAAALAADCggIDwABLAAECgYIDgAGAAAAAA==.Velcon:BAAALAADCgIIAgAAAA==.Venzend:BAABLAAECoEWAAIEAAgIpAaM4QAbAQAEAAgIpAaM4QAbAQAAAA==.',Vi='Vindicatio:BAAALAAECgMIAwABLAAFFAMICAABAHgdAA==.Violenzia:BAAALAADCggICQAAAA==.Viskay:BAAALAADCggIEwAAAA==.Viskong:BAAALAADCgQIBAABLAADCggIEwAGAAAAAA==.',Vo='Voikiria:BAAALAADCggIDgAAAA==.',Wa='Walküré:BAAALAAECgYICAAAAA==.War:BAAALAADCggICAAAAA==.Wartak:BAAALAAECgcIEgAAAA==.',Wu='Wutburger:BAABLAAECoEYAAIBAAcIlRnIQgD4AQABAAcIlRnIQgD4AQAAAA==.',Xe='Xerfît:BAAALAAECgEIAQABLAAECgcICAAGAAAAAA==.',Xi='Xirtanome:BAAALAAECgMIAwABLAAECgcIGAABAJUZAA==.',Xw='Xwave:BAAALAAECgYICAAAAA==.',Yo='Yordar:BAAALAADCggIDQAAAA==.',Yr='Yraide:BAAALAADCgEIAQABLAADCggICwAGAAAAAA==.',Yu='Yulo:BAABLAAECoEtAAMEAAgIzyShCwA4AwAEAAgIzyShCwA4AwAYAAIIchsAAAAAAAAAAA==.',['Yû']='Yûffi:BAAALAAECgIIAgAAAA==.',Ze='Zerdilla:BAACLAAFFIENAAIfAAQINwiSBQALAQAfAAQINwiSBQALAQAsAAQKgS8AAh8ACAhpIiMHAAsDAB8ACAhpIiMHAAsDAAAA.',Zi='Zimtrose:BAAALAADCggIDwAAAA==.Zippel:BAAALAAECgIIAgAAAA==.',Zo='Zon:BAAALAADCgYIDAAAAA==.Zoraderon:BAABLAAECoEZAAIjAAYILw0RCwBZAQAjAAYILw0RCwBZAQAAAA==.',Zw='Zworg:BAAALAADCgQIBAAAAA==.',['Ád']='Áda:BAAALAAECgYIDgAAAA==.',['Ês']='Êsra:BAAALAAECgIIAgAAAA==.',['Ðe']='Ðestiny:BAAALAAECgcIBwAAAA==.',['Ðæ']='Ðæmentîs:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end