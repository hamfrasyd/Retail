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
 local lookup = {'Priest-Shadow','Druid-Balance','Paladin-Retribution','Priest-Holy','DeathKnight-Frost','Druid-Restoration','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','DeathKnight-Blood','Unknown-Unknown','Monk-Windwalker','Hunter-Marksmanship','Warlock-Demonology','Hunter-BeastMastery','Warlock-Destruction','Warrior-Fury','Mage-Frost','DemonHunter-Havoc','Paladin-Protection','Priest-Discipline','Paladin-Holy','Rogue-Assassination','Warrior-Arms','DemonHunter-Vengeance','Rogue-Subtlety',}; local provider = {region='EU',realm='LosErrantes',name='EU',type='weekly',zone=44,date='2025-09-25',data={Ac='Acay:BAAALAAECgUIBQAAAA==.',Ae='Aellenris:BAAALAADCgcIDAAAAA==.',Ai='Aidenkrant:BAAALAAECgQIBAAAAA==.',Ak='Akathya:BAAALAAECgYICwAAAA==.Akrome:BAAALAAECgIIAwAAAA==.',Al='Alanarya:BAAALAAECggICwAAAA==.Albaa:BAAALAAECgYIBwAAAA==.Alila:BAAALAAECgMIAwAAAA==.Alileath:BAAALAADCgYIBgAAAA==.Aloestra:BAAALAADCgcIDwAAAA==.Alonsux:BAAALAAECgIIAwABLAAECggILAABAKEXAA==.Althuro:BAAALAAECgMIAwAAAA==.',Am='Amapelita:BAAALAADCggICQAAAA==.Amapolito:BAAALAADCgcIBwAAAA==.Amapolíto:BAAALAADCgcIEAAAAA==.',An='Anderkaz:BAAALAAECgYICAAAAA==.Andoerian:BAAALAAECgIIAgAAAA==.Androx:BAAALAADCggIEQAAAA==.Anthirell:BAAALAAECgcICwAAAA==.Anubiswar:BAAALAADCgcIDgAAAA==.',Aq='Aquerontes:BAAALAAECgIIAwAAAA==.',Ar='Arcanimal:BAABLAAECoEiAAICAAcI0iNKEgC0AgACAAcI0iNKEgC0AgAAAA==.Aristoi:BAAALAADCggICAAAAA==.Artripodes:BAAALAADCgcICgAAAA==.',As='Asfald:BAABLAAECoEVAAIDAAcIiAh3rwBkAQADAAcIiAh3rwBkAQAAAA==.Asheria:BAAALAADCggICAAAAA==.Asiulfer:BAAALAAECgIIAgAAAA==.Assunamun:BAAALAAECgQIBQAAAA==.Astaaldë:BAAALAAFFAEIAQAAAA==.Astar:BAAALAADCggIHQAAAA==.Astarz:BAAALAADCgQIBAAAAA==.Astredius:BAAALAADCggIEAAAAA==.Asyndh:BAAALAAECgcIDgAAAA==.',At='Athaeri:BAABLAAECoEcAAIBAAgIkxavOAC+AQABAAgIkxavOAC+AQAAAA==.Athïca:BAAALAADCgYIBgAAAA==.',Ay='Ayakadina:BAAALAAECgEIAQAAAA==.Ayakaplay:BAAALAAECgIIAgAAAA==.',['Aé']='Aérys:BAAALAADCgEIAQAAAA==.',Be='Bearnoid:BAAALAAECgEIAQAAAA==.Bearnold:BAAALAADCggICAAAAA==.Beldruck:BAAALAADCgUIBQAAAA==.',Bl='Blackorion:BAAALAADCgEIAQAAAA==.Bluesoul:BAAALAADCgcIBQAAAA==.',Bo='Bombillita:BAABLAAECoElAAIEAAgI8g+7NwDaAQAEAAgI8g+7NwDaAQAAAA==.',Br='Breinnon:BAAALAAECggICAAAAA==.Briëna:BAAALAADCggICQAAAA==.',Bu='Bursting:BAABLAAECoEVAAIFAAgI8gYIuABiAQAFAAgI8gYIuABiAQAAAA==.',['Bó']='Bóromír:BAAALAAECggIBQAAAA==.',Ca='Caricias:BAAALAAECgYICAAAAA==.Caspper:BAABLAAECoEaAAIGAAcI8hW9OADIAQAGAAcI8hW9OADIAQAAAA==.Castóreo:BAAALAADCgYIBgAAAA==.Cazapoder:BAAALAAECgUICAAAAA==.',Ch='Chony:BAABLAAECoEbAAIHAAcI4h/qLAB+AgAHAAcI4h/qLAB+AgAAAA==.Chrox:BAAALAADCggIEQAAAA==.Chunlio:BAAALAADCggICgAAAA==.',Ci='Cinabrio:BAAALAADCgYIBgAAAA==.',Co='Colavil:BAAALAADCggICAAAAA==.Comemontruos:BAAALAAECgYICAAAAA==.',Cr='Crac:BAAALAAECgMIAwAAAA==.Crantox:BAABLAAECoEiAAIBAAgIQRzYFwCXAgABAAgIQRzYFwCXAgAAAA==.',Da='Dagam:BAAALAAECgYIBgAAAA==.Daggam:BAABLAAECoEkAAMIAAcIWRe0TgDJAQAIAAcIWRe0TgDJAQAJAAUI7gJxiwCyAAAAAA==.Dameungrr:BAAALAAECgcIDQAAAA==.Danielbc:BAAALAADCgUIBQAAAA==.Danielbcn:BAAALAAECgMIAwAAAA==.Darkpiark:BAABLAAECoEZAAIKAAcIwhQ8GgCJAQAKAAcIwhQ8GgCJAQABLAAECggIDgALAAAAAA==.Darkusys:BAAALAADCgcIFwAAAA==.Darphal:BAAALAAECgQICwAAAA==.Dayha:BAAALAAECgYIDAAAAA==.Daêron:BAAALAAECgMIBgAAAA==.',De='Deadpul:BAAALAAECgcIDQAAAA==.Deblester:BAAALAAFFAEIAQAAAA==.Deborman:BAAALAADCgcIBwAAAA==.Demontes:BAAALAADCggICAAAAA==.Deren:BAAALAADCggIDwAAAA==.Descartep:BAAALAAECgMIBAAAAA==.Desrya:BAAALAAECgYIBwAAAA==.Destrals:BAAALAAECgcICAAAAA==.',Dh='Dhh:BAAALAAECgEIAgAAAA==.',Di='Diriel:BAAALAADCggIAwABLAAECgMICAALAAAAAA==.Ditalco:BAAALAAECgEIAQAAAA==.Diâna:BAAALAADCgYIDAABLAADCgcIBwALAAAAAA==.',Do='Domi:BAABLAAECoEWAAIHAAgITRR6SgAHAgAHAAgITRR6SgAHAgAAAA==.Dontrabuco:BAAALAADCggICQAAAA==.',Dr='Droidiuss:BAAALAAECgQIBgAAAA==.Drÿox:BAAALAAECgIIAgAAAA==.',Du='Duendexl:BAABLAAECoE2AAIMAAgIhRFDIADMAQAMAAgIhRFDIADMAQAAAA==.Duggam:BAAALAAECgYIDAAAAA==.',Dw='Dwoly:BAAALAAECgUIAQAAAA==.',['Dæ']='Dærius:BAAALAAECgMIBgAAAA==.',Ed='Edelgard:BAAALAAECgcIDQAAAA==.',El='Elfyto:BAAALAAECgMIBAAAAA==.Elmetal:BAABLAAECoEgAAINAAcIhh4PIgBCAgANAAcIhh4PIgBCAgAAAA==.Elynara:BAABLAAECoEpAAIOAAgIzCUPAQBuAwAOAAgIzCUPAQBuAwAAAA==.Elëazar:BAAALAADCggIFwAAAA==.',Er='Erastil:BAAALAADCgYICAAAAA==.Eruanne:BAAALAAECgIIAwAAAA==.',['Eä']='Eälara:BAABLAAECoEXAAIPAAcIUg3KhwBuAQAPAAcIUg3KhwBuAQAAAA==.',Fa='Faennil:BAAALAADCgMIAwAAAA==.Fatalision:BAAALAADCggICAAAAA==.',Fe='Fereya:BAAALAAECgUIAQAAAA==.Ferritina:BAAALAADCggIEgAAAA==.',Fh='Fhraín:BAAALAADCgIIAgAAAA==.',Fo='Forellas:BAAALAAECgYIEAAAAA==.Fortipiri:BAAALAADCgYIBwAAAA==.Fourrouses:BAAALAADCgYIBgAAAA==.',Fu='Furìa:BAAALAAECgYICQABLAAECgcIHQANAPMaAA==.',['Fé']='Fédra:BAAALAAECgEIAQAAAA==.',Ga='Garar:BAAALAAECggICgAAAA==.Garraatroz:BAAALAADCgYIBgAAAA==.Gatitopiloto:BAABLAAECoEkAAIQAAgIAwQ0mwD6AAAQAAgIAwQ0mwD6AAAAAA==.Gaunt:BAAALAADCgcIFAAAAA==.',Ge='Genpachi:BAAALAAECgUIBgAAAA==.',Gi='Gioka:BAAALAADCgMIAwAAAA==.Giokar:BAAALAADCggIDwAAAA==.Giste:BAABLAAECoEVAAIRAAcIuA4nZACNAQARAAcIuA4nZACNAQAAAA==.',Gn='Gnotorioum:BAABLAAECoEXAAISAAcIPSSUEwBiAgASAAcIPSSUEwBiAgAAAA==.',Gr='Gratzel:BAAALAAECgYIBgAAAQ==.Greed:BAAALAADCggIDwABLAAFFAMICgAKAB0lAA==.Greish:BAAALAAECgUIDQAAAA==.Gritherl:BAAALAAECgIIAgAAAA==.Grow:BAAALAAECgMIAwAAAA==.',Gu='Gulthix:BAAALAAECggIDgAAAA==.Gunark:BAABLAAECoEZAAIJAAcIABGMTQClAQAJAAcIABGMTQClAQAAAA==.Gurromina:BAAALAADCgYIBgAAAA==.',['Gò']='Gòdofredo:BAAALAADCggIFwABLAAECggIKQAOAMwlAA==.',Ha='Haku:BAAALAAECgEIAQAAAA==.Halimath:BAAALAADCgIIAgAAAA==.Hashashino:BAAALAADCgQIBAAAAA==.',He='Heafry:BAAALAAECgUIBQAAAA==.Helya:BAAALAAECgEIAQAAAA==.',Ih='Ihenar:BAAALAADCgUIBQAAAA==.',Il='Illidiam:BAAALAADCgQIBAAAAA==.',Ju='Juananx:BAAALAAECgcIDgAAAA==.Juanoton:BAAALAADCggIIAAAAA==.Junio:BAAALAAECgYIEwAAAA==.',Ka='Kadran:BAABLAAECoEfAAIDAAcIpw9RjACjAQADAAcIpw9RjACjAQAAAA==.Kairel:BAAALAAECgEIAQAAAA==.Kaiton:BAAALAADCggICQAAAA==.Karakator:BAABLAAECoEdAAIDAAgIah6GNgBxAgADAAgIah6GNgBxAgAAAA==.Karslah:BAABLAAECoEUAAITAAYIZBJMkwByAQATAAYIZBJMkwByAQAAAA==.Kathiane:BAAALAAECgYICQAAAA==.Kattysha:BAAALAAECgIIAgAAAA==.Kauki:BAAALAAECgQIBQAAAA==.Kayl:BAAALAADCgYICAAAAA==.',Kh='Khelara:BAABLAAECoEcAAIGAAYIUxWATQB0AQAGAAYIUxWATQB0AQAAAA==.Khrona:BAAALAADCgcIBwAAAA==.',Ki='Kiiraa:BAAALAADCggICAAAAA==.',Kl='Kleir:BAAALAAECgYIEQAAAA==.Kloso:BAAALAADCgIIAQAAAA==.',Ko='Komorebi:BAAALAAECggICQAAAA==.',Kr='Kraigon:BAAALAADCgYIBgAAAA==.Krisko:BAABLAAECoEYAAINAAgIVhMEMQDmAQANAAgIVhMEMQDmAQAAAA==.Kroxas:BAAALAAECgYICwAAAA==.Krughok:BAAALAADCgYIBgAAAA==.Krympal:BAAALAADCggIGQAAAA==.Krâven:BAAALAAECgMIAwAAAA==.',Ku='Kultank:BAAALAADCgYIBgAAAA==.',['Ké']='Kélya:BAAALAAECgUIBwAAAA==.',La='Laofendida:BAAALAAECggICAAAAA==.Larryworrier:BAAALAAECgEIAQAAAA==.Larrÿ:BAACLAAFFIEJAAIDAAMIwBmTDAARAQADAAMIwBmTDAARAQAsAAQKgSYAAgMACAhgJHISABoDAAMACAhgJHISABoDAAAA.Laudana:BAAALAADCggIBQAAAA==.Layon:BAAALAADCgcIGAAAAA==.',Le='Ledolian:BAABLAAECoEgAAIUAAcIwBkeHADfAQAUAAcIwBkeHADfAQAAAA==.',Lo='Lokdevil:BAAALAAECgQIDQAAAA==.Lolailo:BAAALAAECgYIDgAAAA==.Lolamentos:BAAALAADCgcIBwAAAA==.Lorlorde:BAAALAADCggIEgAAAA==.',Lu='Lunyta:BAAALAAECgYIDQAAAA==.Luraan:BAAALAAECgEIAgAAAA==.Luzbuena:BAAALAAECgIIAwAAAA==.',Ly='Lybra:BAABLAAECoEpAAIHAAgIoR1gKgCKAgAHAAgIoR1gKgCKAgAAAA==.Lyùlkæ:BAAALAADCggICAAAAA==.',Ma='Madôwk:BAAALAADCgcICQAAAA==.Magiister:BAAALAAECgYIDQAAAA==.Makami:BAABLAAECoEZAAIDAAcIBh0rQwBIAgADAAcIBh0rQwBIAgAAAA==.Maldite:BAAALAADCggIEgAAAA==.Maldixo:BAAALAAECgQIAQAAAA==.Maléfïca:BAAALAAECgQIAwAAAA==.Marduk:BAAALAADCggIDwAAAA==.Martína:BAAALAAECgMIAQAAAA==.Matildabrujo:BAAALAADCgIIAgABLAAECgIIAwALAAAAAA==.Matisa:BAAALAADCgIIAgAAAA==.Mayacz:BAAALAAECggIEQAAAA==.Mayaibuky:BAABLAAECoEjAAIJAAcI+RyfNQAIAgAJAAcI+RyfNQAIAgAAAA==.Maÿä:BAABLAAECoEdAAINAAcI8xowKAAaAgANAAcI8xowKAAaAgAAAA==.',Me='Meleblanca:BAABLAAECoEZAAMVAAYI0h4GCgDiAQAVAAYI0BwGCgDiAQAEAAUICxzSSQCKAQAAAA==.Merilas:BAAALAADCggIDAABLAAECgMICAALAAAAAA==.',Mi='Milene:BAAALAAECgYIEwAAAA==.Miletwo:BAAALAADCgUIBgAAAA==.Mirandagr:BAAALAAECgUIDAAAAA==.',Mo='Moniná:BAAALAAECgMIAwAAAA==.Mordres:BAAALAADCggIDgAAAA==.Moribundilla:BAAALAADCgQIBAAAAA==.',Mu='Muerteignea:BAAALAAECgcIEAAAAA==.Multimuerte:BAAALAAECgYIDgAAAA==.Mumscatha:BAAALAADCgcIDQAAAA==.Muriel:BAAALAADCggIFQAAAA==.Musimalapagu:BAAALAAECgYIBwAAAA==.',My='Mythranar:BAAALAAECgEIAgAAAA==.',Na='Nahiris:BAABLAAECoEgAAIPAAcIrBjdXgDJAQAPAAcIrBjdXgDJAQAAAA==.Naruat:BAAALAADCgMIAwAAAA==.Naturas:BAAALAADCggIEwAAAA==.Naylz:BAAALAAECgYIEwAAAA==.Nazryl:BAAALAADCgcICwAAAA==.',Ni='Nind:BAAALAADCggIJQAAAA==.Nindal:BAAALAADCggICAAAAA==.Nizendra:BAAALAADCgcIEgAAAA==.Niznik:BAAALAADCgcIDgAAAA==.Niøh:BAAALAADCggICAABLAAFFAIICAAFAJUaAA==.',No='Notheafry:BAAALAADCggICAAAAA==.Notoriouh:BAAALAAECgEIAQAAAA==.Noxun:BAAALAAECgEIAQAAAA==.',Nu='Nusus:BAAALAADCgMIAwAAAA==.Nuyou:BAAALAADCgYIBQAAAA==.',Ny='Nyx:BAAALAAECgYIBwAAAA==.',['Nò']='Nòctis:BAAALAADCgYIBgAAAA==.',Oc='Oceiiros:BAAALAADCggIBwAAAA==.',Ol='Oldxlogan:BAABLAAECoEhAAMWAAgI6xWbEwBMAgAWAAgI6xWbEwBMAgADAAcI/RUgegDFAQAAAA==.',On='Onîll:BAAALAADCgMIAwAAAA==.',Os='Osdir:BAAALAAECgUIBwAAAA==.',Pa='Paladoña:BAABLAAECoEiAAIDAAgIjA1zfQC+AQADAAgIjA1zfQC+AQAAAA==.Parteviudas:BAAALAAECgQIBAAAAA==.Payumpayum:BAABLAAECoEcAAIXAAgIwRaMFwBLAgAXAAgIwRaMFwBLAgAAAA==.',Pe='Peloso:BAAALAAECgUICAAAAA==.Pepesonrisas:BAABLAAECoEcAAMYAAcI+h+vBgB5AgAYAAYIxSSvBgB5AgARAAQI0hGuoADQAAAAAA==.Petitcherile:BAAALAAECgMIAwAAAA==.',Ph='Phalhun:BAAALAADCggIDQAAAA==.Phantom:BAAALAAECgEIAQAAAA==.',Pi='Pirula:BAAALAADCgcIBwAAAA==.Pixxie:BAAALAADCggIFQAAAA==.',Po='Poppyofmercy:BAAALAAECgIIAgAAAA==.Potolech:BAAALAADCgUIBQAAAA==.',Pr='Protoescroto:BAAALAADCgYIBgAAAA==.',Ra='Radagaxt:BAAALAADCggIDgAAAA==.Raidenazo:BAACLAAFFIEFAAIFAAIIGhhoNwCbAAAFAAIIGhhoNwCbAAAsAAQKgS0AAgUACAiaIUwWAAADAAUACAiaIUwWAAADAAAA.Rasgamuerta:BAAALAAECgYIDQAAAA==.Rasu:BAAALAADCgcIBwAAAA==.Ratsa:BAAALAADCggIGgAAAA==.Razputin:BAAALAADCggICAAAAA==.Raÿk:BAABLAAECoEbAAIEAAcIvR6QJABAAgAEAAcIvR6QJABAAgAAAA==.',Re='Renkor:BAAALAAECgUICQAAAA==.Retrasovil:BAAALAAECgEIAQAAAA==.Reyku:BAAALAAECgUICQABLAAECgcIGwAHAOIfAA==.',Ru='Ruvy:BAAALAADCgIIAgAAAA==.',Ry='Ryun:BAAALAADCgcIEQAAAA==.',['Ré']='Révan:BAAALAADCgYIBAAAAA==.',Sa='Sacarossa:BAAALAAECgEIAQAAAA==.Saioablack:BAABLAAECoEbAAIBAAgIfBVrJgAnAgABAAgIfBVrJgAnAgAAAA==.Sakher:BAAALAADCgcIBwAAAA==.Samigauren:BAAALAAECgQICAAAAA==.Sanasanita:BAAALAAECgYIEAAAAA==.Sanméi:BAABLAAECoEYAAMVAAcIcxDkGAD7AAAEAAcI7g0mUABxAQAVAAUIhA3kGAD7AAAAAA==.Saturnio:BAAALAAECgYIEgAAAA==.',Se='Sefirol:BAAALAAECgUIBgAAAA==.Selee:BAAALAADCgcIBwAAAA==.',Sf='Sfuss:BAAALAADCggIHQAAAA==.',Sh='Shaelrya:BAAALAADCggICAAAAA==.Shamp:BAAALAAECgYICAAAAA==.Shampu:BAAALAADCgUIBQAAAA==.Shando:BAAALAAECgcIBwAAAA==.Shijan:BAAALAADCgYIBgAAAA==.Shurtugaal:BAAALAADCggICAAAAA==.Shyrali:BAABLAAECoEaAAMIAAgI2RYJNwAVAgAIAAgI2RYJNwAVAgAJAAEI8waurwAvAAAAAA==.Shâÿ:BAAALAADCggIDgAAAA==.Shëra:BAAALAADCggICAAAAA==.Shöwbiz:BAAALAADCgYIBgAAAA==.',Si='Sieria:BAAALAADCgUIBQAAAA==.Sigfredo:BAAALAAECgYIDAAAAA==.Sigfry:BAAALAAECgEIAQAAAA==.Sinlorei:BAAALAADCgQIBAAAAA==.',Sk='Skeleton:BAAALAADCggIEwAAAA==.Skytorus:BAAALAADCgcIDwAAAA==.',So='Soolahi:BAAALAAECgYIDwAAAA==.',St='Starnight:BAAALAAECgYIDgAAAA==.Starshadow:BAAALAAECgMIAwAAAA==.Stormentor:BAABLAAECoEiAAIIAAcIJyBAMgAmAgAIAAcIJyBAMgAmAgAAAA==.',Su='Sunetra:BAABLAAECoEfAAIZAAcITwq8LgANAQAZAAcITwq8LgANAQAAAA==.Supther:BAAALAADCgUIBQAAAA==.',Sy='Sylwën:BAAALAADCgUIBAAAAA==.',['Sæ']='Særiel:BAABLAAECoEdAAITAAgIkyJqDwAiAwATAAgIkyJqDwAiAwAAAA==.',Ta='Talika:BAAALAADCggICAAAAA==.Tanix:BAAALAAECgcIDgAAAA==.Tansiss:BAAALAAECgEIAQAAAA==.Taunico:BAAALAADCggIGAAAAA==.',Te='Tekahn:BAAALAAECgIIAgAAAA==.Terodactilo:BAAALAADCgcIDgAAAA==.',Th='Thebeast:BAAALAAECgQIBAAAAA==.Thepøpe:BAABLAAECoEbAAIEAAgIRR2lFgCcAgAEAAgIRR2lFgCcAgAAAA==.Thornblade:BAAALAAECgYIBgAAAA==.Throrin:BAAALAADCggICQABLAAFFAQIDgAMAJwRAA==.',To='Torkus:BAAALAADCggIGQAAAA==.Totemigneo:BAAALAAECgcICwAAAA==.',Tr='Tramdel:BAAALAADCgYIBAAAAA==.Trampascaza:BAAALAAECgIIAgAAAA==.Trebellä:BAAALAADCgcIBwAAAA==.Trilko:BAAALAAECgYICQABLAAECgcIGwAHAOIfAA==.Truerayo:BAAALAAECgIIAgAAAA==.',Ts='Tsukuyômi:BAAALAADCggIFAAAAA==.',Ul='Uleria:BAAALAADCgYIBgABLAADCgcIBwALAAAAAA==.Ulfgürd:BAACLAAFFIEJAAIFAAII6CTRKgCsAAAFAAII6CTRKgCsAAAsAAQKgR8AAgUACAhKIlAeANgCAAUACAhKIlAeANgCAAAA.',Un='Uncia:BAAALAADCgYIBgAAAA==.',Va='Vadek:BAAALAADCgUIBQAAAA==.Vardena:BAAALAADCggIDQAAAA==.',Ve='Velenia:BAAALAAECggICQAAAA==.Verdepicaro:BAAALAAECgUIAQABLAAECgYIGwAFAHAiAA==.Veresh:BAAALAADCggIDQAAAA==.Verial:BAAALAAECgMICAAAAA==.',Vi='Vighoc:BAAALAAECgEIAQAAAA==.Vizzic:BAAALAADCgQIBAAAAA==.',Vo='Vonthar:BAAALAADCggIDgAAAA==.',['Vë']='Vëga:BAAALAADCgIIAgAAAA==.',Wa='Warribum:BAAALAADCggICAAAAA==.',Wi='Wilframe:BAABLAAECoEhAAIRAAgIGBi3LgBNAgARAAgIGBi3LgBNAgAAAA==.',['Wô']='Wôlfÿx:BAAALAAECgMIAwAAAA==.',Xa='Xaka:BAAALAADCgcIDgAAAA==.Xanya:BAAALAAECgUIDQAAAA==.',Xe='Xelia:BAAALAADCggIEQAAAA==.',Xi='Xikven:BAAALAADCggIEgAAAA==.Xiongzhao:BAAALAADCggICwAAAA==.',Xx='Xxlegol:BAAALAADCgYIBQAAAA==.',Xy='Xyfusino:BAAALAADCgIIAwAAAA==.Xyzxamm:BAAALAAECgQIBAAAAA==.',Ya='Yazmine:BAAALAAECgYICQAAAA==.',Yi='Yis:BAABLAAECoEpAAMXAAgIIiVsAgBRAwAXAAgIdSRsAgBRAwAaAAUIgBxTGgCYAQAAAA==.',Yo='Yolii:BAAALAAECgYICgAAAA==.Yoonahera:BAAALAAECgcICQAAAA==.',Yr='Yrai:BAABLAAECoEYAAIDAAcIoQiwwgBAAQADAAcIoQiwwgBAAQAAAA==.Yrelis:BAAALAADCggIFAAAAA==.Yrêll:BAAALAADCgcIBwAAAA==.',Ys='Yserá:BAAALAAECgMIAwAAAA==.',['Yì']='Yìll:BAAALAAECgcIBwABLAAECggIKQAXACIlAA==.',Za='Zamelnar:BAAALAAECgQIDAAAAA==.Zarfi:BAABLAAECoEfAAICAAcITxKHOQCjAQACAAcITxKHOQCjAQAAAA==.',Ze='Zeykuu:BAAALAAECgYICwAAAA==.',Zy='Zylenn:BAAALAAECgYICgAAAA==.',['Äl']='Älfil:BAABLAAECoEUAAIPAAYIRAYe3AC1AAAPAAYIRAYe3AC1AAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end