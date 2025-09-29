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
 local lookup = {'DeathKnight-Frost','Druid-Restoration','Monk-Brewmaster','Unknown-Unknown','Warrior-Fury','DeathKnight-Unholy','Priest-Holy','Shaman-Elemental','DeathKnight-Blood','Hunter-BeastMastery','Druid-Balance','Shaman-Restoration','Mage-Frost','Warrior-Protection','Mage-Fire','Priest-Shadow','Mage-Arcane','Hunter-Marksmanship','Evoker-Devastation','Evoker-Preservation','Paladin-Holy','Paladin-Retribution','Priest-Discipline','DemonHunter-Havoc','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Paladin-Protection','Warrior-Arms','Monk-Mistweaver','Warlock-Destruction',}; local provider = {region='EU',realm='Durotan',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarona:BAABLAAECoEWAAIBAAYItgXU7QACAQABAAYItgXU7QACAQAAAA==.',Ad='Adelindar:BAAALAAECgEIAgAAAA==.',Ai='Aida:BAAALAAECgMIBwAAAA==.Aitno:BAAALAADCgYIBgAAAA==.',Ak='Akame:BAAALAAECgEIAgAAAA==.Akirasama:BAAALAAECgYIEQABLAAECggIJgACAMgUAA==.',Al='Alicìa:BAAALAAECgYIDAAAAA==.Alkzaba:BAABLAAECoEeAAIDAAcIPRpAEwD/AQADAAcIPRpAEwD/AQAAAA==.Almeya:BAAALAADCgMIAwAAAA==.Alorien:BAAALAAECggICAAAAA==.Altekuh:BAAALAADCggIFwAAAA==.',An='Andelton:BAAALAADCgQIBAAAAA==.Angelforyou:BAAALAAECgcIEwAAAA==.Anulû:BAAALAADCgIIAgABLAADCggIEAAEAAAAAA==.',As='Aschenstølle:BAAALAADCggIEgAAAA==.Ashenbeârd:BAAALAADCggICAAAAA==.Ashunae:BAAALAADCgUIBQAAAA==.',At='Attilem:BAAALAADCgYIBgAAAA==.',Au='Aurøra:BAAALAAECgEIAQAAAA==.',Az='Azzinoth:BAAALAADCgcIBwAAAA==.',Ba='Babypowder:BAAALAADCggIHAAAAA==.Bactar:BAAALAADCggICwABLAABCgcIGQAEAAAAAA==.Badbcatha:BAAALAADCggICAAAAA==.Bakida:BAAALAAECggIDAAAAA==.Balver:BAABLAAECoEgAAIFAAgIihV9MgA7AgAFAAgIihV9MgA7AgAAAA==.Barbeque:BAAALAAECgYIDQAAAA==.Barcodé:BAAALAAECgEIAQABLAADCgcIBwAEAAAAAA==.Bathrum:BAAALAADCgMIAwAAAA==.',Be='Beatya:BAABLAAECoETAAMBAAYIFyCPjwClAQABAAYIdRyPjwClAQAGAAMIFR/fNgD2AAAAAA==.Beefkeeper:BAAALAAECgIIBQAAAA==.Beetroot:BAAALAADCgYIBgAAAA==.Befibe:BAAALAAECgIIAwAAAA==.',Bi='Bibabub:BAAALAAECgMIAwAAAA==.Bigs:BAAALAADCgYIBgAAAA==.Bimbam:BAAALAADCggIEgABLAAECgUIBwAEAAAAAA==.',Bl='Blackmaw:BAAALAADCgUIBQABLAADCgcIBwAEAAAAAA==.Blackseeker:BAAALAAECgUICQAAAA==.Bloodhunter:BAAALAAECggICAAAAA==.Bluelux:BAAALAAECgYIDQAAAA==.Blîxen:BAAALAADCgQIBAABLAAECgEIAgAEAAAAAA==.',Bo='Bonni:BAAALAAECggIAgAAAA==.Borado:BAAALAAECgYIBgAAAA==.',Br='Brachhus:BAAALAAECgEIAgAAAA==.Brolý:BAAALAADCggIFgAAAA==.Brubi:BAAALAADCgcIDAAAAA==.Brubii:BAAALAADCgYIBgAAAA==.Brutitis:BAAALAADCgcIBwAAAA==.',Bu='Bubblepot:BAAALAAECgYIEAABLAADCgcIBwAEAAAAAA==.Bubblerunner:BAAALAADCgIIAgAAAA==.Butny:BAAALAAECggICgAAAA==.',['Bæ']='Bætý:BAAALAADCgQIBAABLAAECgYIEwABABcgAA==.',['Bê']='Bêlial:BAAALAADCggICAAAAA==.',Ca='Candrima:BAAALAAECgEIAQAAAA==.Capernián:BAAALAADCggIGgAAAA==.Casjiopaja:BAAALAAECggICAAAAA==.',Ce='Celibrew:BAAALAADCgMIAwAAAA==.',Ch='Chrishh:BAABLAAECoEjAAIHAAgIYx2HEwCzAgAHAAgIYx2HEwCzAgAAAA==.Chàntál:BAABLAAECoEcAAIGAAcIGhx2DgBXAgAGAAcIGhx2DgBXAgABLAAECgcILAAIABgkAA==.',Cl='Clarafall:BAAALAADCggIDwAAAA==.Claîr:BAAALAAECgUIBQAAAA==.Clyde:BAAALAAECggIAgAAAA==.',Co='Cocó:BAAALAADCgYIGAAAAA==.Columbu:BAAALAAECgEIAQAAAA==.Cong:BAAALAADCgIIAgAAAA==.Conqueror:BAAALAAECgEIAQAAAA==.',Cr='Crx:BAAALAADCgEIAQAAAA==.',Da='Dady:BAAALAADCgcIBwAAAA==.Dahrzit:BAAALAADCggICAABLAAECggILgAJAOgSAA==.Daisycutter:BAAALAAECggICAAAAA==.Damanda:BAAALAADCggIDAAAAA==.Darklakai:BAAALAAECgMIAwAAAA==.Datios:BAAALAAECgIIAgAAAA==.',De='Deadlef:BAAALAADCggIFgABLAABCgcIGQAEAAAAAA==.Deandrâ:BAAALAAECgYIBgAAAA==.Demetos:BAAALAADCgYIBwAAAA==.Deo:BAAALAADCggICQAAAA==.Derjeniche:BAAALAADCgEIAQAAAA==.Desolater:BAAALAADCggIDgAAAA==.Detania:BAAALAAECgIIAgAAAA==.Devilpeace:BAABLAAECoEmAAIKAAgIVR4OKQB5AgAKAAgIVR4OKQB5AgAAAA==.',Di='Dinarya:BAAALAADCggICAABLAAECgYIEwAEAAAAAA==.Dirando:BAAALAAECgYIBwAAAA==.',Do='Dobs:BAABLAAECoEWAAIIAAYIgwMUggDgAAAIAAYIgwMUggDgAAAAAA==.Domibärt:BAAALAAECgYICQAAAA==.Doneran:BAAALAADCgIIAgAAAA==.Doommortar:BAAALAADCggIEAAAAA==.',Dr='Dragonmaster:BAAALAADCgcICAAAAA==.Drakaris:BAAALAAECgQIBQAAAA==.Drenâ:BAAALAAECgcIEQAAAA==.Drinali:BAAALAADCggICgAAAA==.Druitrox:BAABLAAECoEmAAILAAgIxB7uEQC4AgALAAgIxB7uEQC4AgAAAA==.Dráyko:BAAALAADCgcIBwAAAA==.',Du='Durima:BAAALAAECgQIBAAAAA==.',['Dê']='Dêxo:BAAALAAECgIIAgAAAA==.',['Dï']='Dïandra:BAAALAADCggICgAAAA==.',Ea='Earthfighter:BAAALAAECgMIBQAAAA==.Easymilow:BAABLAAECoEjAAILAAgIxhDcPgCJAQALAAgIxhDcPgCJAQAAAA==.',El='Elcombo:BAAALAADCgcIFwAAAA==.Elementwings:BAAALAAECgYIBgAAAA==.Elenoar:BAAALAADCggIDgAAAA==.Elorien:BAAALAAECgMIAwAAAA==.Elyos:BAABLAAECoEhAAMMAAgIShYpXgCeAQAMAAcIHxQpXgCeAQAIAAUIrgT4ggDbAAAAAA==.',En='Enchantrezz:BAAALAADCgcIBwAAAA==.Ent:BAAALAAECggIEAAAAA==.',Er='Eredin:BAABLAAECoEwAAINAAgIhSYqAQB+AwANAAgIhSYqAQB+AwAAAA==.Erleuchter:BAAALAAFFAEIAQAAAA==.Eruearendil:BAAALAAECgIIAgAAAA==.',Es='Esdurial:BAAALAADCggICAAAAA==.',Eu='Euka:BAAALAAECgEIAgAAAA==.',Ex='Exqz:BAAALAADCggICAAAAA==.',Fa='Fanuriel:BAAALAADCggIDgAAAA==.Fataldeath:BAAALAAECgIIAgAAAA==.Fatality:BAAALAADCgcIFAAAAA==.Fattixx:BAAALAADCgMIAwABLAAECgcIFgAMAMkgAA==.Fattîxx:BAABLAAECoEWAAIMAAcIySBwIABxAgAMAAcIySBwIABxAgAAAA==.',Fe='Febbo:BAAALAADCggIDgABLAAECgUIEQAEAAAAAA==.Feen:BAABLAAECoEZAAIMAAYIESOXKgBFAgAMAAYIESOXKgBFAgAAAA==.Feená:BAAALAADCggICAAAAA==.Feger:BAAALAAECgMIBAAAAA==.Fenneco:BAAALAADCgcIDQAAAA==.',Fi='Fingolfin:BAABLAAECoEbAAIOAAYIiyL5FQBVAgAOAAYIiyL5FQBVAgAAAA==.',Fr='Frostluna:BAAALAADCggIEAAAAA==.',Ga='Gaku:BAAALAADCgYIEAAAAA==.Gamba:BAAALAADCgcIBwABLAAECgUIBwAEAAAAAA==.Garuk:BAAALAAECgUIDwABLAAECggIEQAEAAAAAA==.',Ge='Geekschnabel:BAAALAADCgYIBgAAAA==.',Gh='Ghostah:BAAALAADCgQIBAABLAAECggIHwAPAO8WAA==.',Go='Goblynn:BAAALAADCggICAAAAA==.Goldhasepal:BAAALAADCggIDQAAAA==.Goollum:BAAALAADCggIBAAAAA==.Goêll:BAAALAADCgQIBAAAAA==.',['Gá']='Gándalf:BAAALAAECggICwAAAA==.',['Gä']='Gänsehose:BAAALAADCgIIAgAAAA==.',Ha='Habschhumpen:BAACLAAFFIEHAAIDAAIIrg8KEAB5AAADAAIIrg8KEAB5AAAsAAQKgSwAAgMACAijFQ0SAA8CAAMACAijFQ0SAA8CAAAA.Halsey:BAAALAADCgUIBQABLAAFFAIIBwAQALMWAA==.Hasinator:BAABLAAECoEmAAICAAgIyBSTLAADAgACAAgIyBSTLAADAgAAAA==.Haxus:BAAALAADCgcIBwABLAAECgEIAgAEAAAAAA==.',He='Healflame:BAAALAADCgYIBgAAAA==.Hellboyy:BAAALAADCgIIAgAAAA==.Hephâistos:BAAALAAECgcIEwAAAA==.Hessi:BAAALAADCgcICQAAAA==.',Hi='Hiereia:BAAALAADCggIFAAAAA==.',Ho='Hobbert:BAAALAAFFAIIBAAAAA==.Holygrail:BAAALAADCgcIBwAAAA==.Holyscchiet:BAAALAAECgEIAQAAAA==.Honeykíss:BAAALAADCgMIAwAAAA==.Hotwife:BAAALAAECgIIBAAAAA==.',['Hê']='Hêfaisto:BAAALAADCggIDgABLAAECgcIEwAEAAAAAA==.',Ib='Ibirarwen:BAABLAAECoEWAAIIAAcIOyH/KQBFAgAIAAcIOyH/KQBFAgAAAA==.',Id='Ideria:BAACLAAFFIEHAAMQAAIIsxbNFQCZAAAQAAIIsxbNFQCZAAAHAAEIbwFkNwA2AAAsAAQKgSYAAhAACAi0I4IIACgDABAACAi0I4IIACgDAAAA.',Ih='Iheridas:BAAALAADCggIDgAAAA==.',Il='Illumie:BAAALAADCgIIAgAAAA==.',In='Inez:BAAALAADCggIJAAAAA==.Inferion:BAAALAADCggIKAAAAA==.',Iv='Ivalina:BAAALAAECgEIAQAAAA==.Iváná:BAAALAADCgYIBwABLAAECgcIFgAMAMkgAA==.',Iz='Izir:BAAALAADCggIDwAAAA==.',Ja='Jacob:BAAALAADCgYIBgAAAA==.Jarûn:BAABLAAECoEfAAMPAAgI7xZ5BwDMAQARAAcIjhmaRAAcAgAPAAgIWBB5BwDMAQAAAA==.',Jd='Jdm:BAAALAADCgcICgAAAA==.',Je='Jebolaren:BAABLAAECoEZAAIQAAcIHRZZLgD4AQAQAAcIHRZZLgD4AQAAAA==.Jenna:BAABLAAECoEjAAIBAAgIEhrkYgD8AQABAAgIEhrkYgD8AQAAAA==.',Jo='Jojo:BAAALAAECgEIAgAAAA==.',Ju='Julimond:BAAALAAECgYICwABLAAECgYIEAAEAAAAAA==.',['Já']='Jásana:BAAALAAECgIIAgAAAA==.',['Jè']='Jèssy:BAAALAADCgQIAwAAAA==.',Ka='Kahdse:BAAALAADCggIDQAAAA==.Kaine:BAAALAADCgcICAAAAA==.Kalinga:BAAALAAECgEIAQAAAA==.Kallay:BAAALAAECgYIBgAAAA==.Kaltkaltauau:BAAALAAECgIIAwAAAA==.Kanê:BAAALAADCggIEAAAAA==.Karanda:BAABLAAECoEeAAICAAcI1xAmUQBnAQACAAcI1xAmUQBnAQAAAA==.Karogas:BAAALAAECgYIEQAAAA==.Kartoffelaim:BAAALAADCgYICQAAAA==.Kasdeya:BAAALAADCggIEAABLAAFFAIIBQALAFURAA==.Kasina:BAAALAADCgMIAwAAAA==.',Ke='Keelgarr:BAAALAAECgIIAgAAAA==.Kekz:BAAALAAECgcIEAAAAA==.Keratos:BAAALAAECggIDAAAAA==.',Ki='Kiyoshi:BAAALAAECgEIAgAAAA==.',Kn='Knochenhatz:BAAALAADCgUIBQAAAA==.',Ku='Kuranami:BAAALAAECggIDgAAAA==.Kuromi:BAAALAAECgYIEwAAAA==.',Ky='Kyuubii:BAAALAAECgYIEgAAAA==.',['Kò']='Kòrrá:BAABLAAECoEfAAISAAYIoxwaMQDlAQASAAYIoxwaMQDlAQABLAAECgcILAAIABgkAA==.',La='Laban:BAAALAADCggIGwAAAA==.Lachrìzì:BAABLAAECoEwAAMTAAgIHSDZDgCyAgATAAgIHSDZDgCyAgAUAAEIgQkAAAAAAAAAAA==.Lamalover:BAAALAAECgYICgAAAA==.Lamastu:BAAALAADCggIBgABLAAFFAIIBQALAFURAA==.Lanistas:BAAALAAECgMIBQAAAA==.Laroras:BAAALAAECgIIAgAAAA==.',Le='Leenïe:BAAALAAECgMIAwAAAA==.Lelanie:BAABLAAECoEUAAMCAAYI4hOvUgBhAQACAAYI4hOvUgBhAQALAAMIkhIucAClAAAAAA==.Lengadanger:BAAALAAECgYICgAAAA==.Letsshame:BAAALAAECgYIBQAAAA==.',Lh='Lhykis:BAAALAADCgMIAwAAAA==.',Li='Lightlucifer:BAABLAAECoEeAAIIAAgI2RjIIwBqAgAIAAgI2RjIIwBqAgABLAAECggIFQAKAN0hAA==.Lightwings:BAAALAADCgcIBwAAAA==.Likra:BAAALAAECgcICgAAAA==.Linelly:BAAALAADCgUIBwAAAA==.Liszy:BAAALAADCgUIBQAAAA==.Livenia:BAAALAAECgcICgAAAA==.',Lo='Loardi:BAAALAAECgYIEgAAAA==.Lockone:BAAALAADCgYIBgAAAA==.Lola:BAAALAADCggICAAAAA==.Lomo:BAAALAADCggIGgAAAA==.Lomyta:BAAALAAECgcIEAAAAA==.Lorêa:BAAALAADCgUIBQAAAA==.Losan:BAAALAADCgQIBAABLAAECggIEQAEAAAAAA==.',Lu='Lugga:BAAALAAECgIIAwAAAA==.Lumistrasza:BAAALAADCgcIBwAAAA==.',Ly='Lyrenda:BAABLAAECoEbAAMCAAYI2BsKPQC1AQACAAYI2BsKPQC1AQALAAYI/xVVQQB+AQAAAA==.Lyzzi:BAAALAADCgcIDwAAAA==.',['Lí']='Líria:BAAALAAECgUICAAAAA==.',Ma='Maegi:BAAALAADCggIBwAAAA==.Maggi:BAAALAAECgUIBwAAAA==.Maguma:BAAALAADCggIGwAAAA==.Maige:BAAALAADCgUIBQAAAA==.Maniaib:BAABLAAECoEbAAIQAAYIiw4tTwBVAQAQAAYIiw4tTwBVAQAAAA==.Maruuhn:BAAALAAECgYIDwAAAA==.Marxos:BAAALAAECgEIAQAAAA==.Maskeraith:BAAALAADCggIGgAAAA==.Maurîce:BAAALAADCggIEAABLAAECgcIEwAEAAAAAA==.',Mc='Mckay:BAAALAADCggIKAAAAA==.',Me='Medikus:BAAALAADCggIDgABLAAECgYIEwABABcgAA==.Melave:BAAALAADCggICAABLAAECgYICgAEAAAAAA==.Mellicat:BAAALAADCgIIAgAAAA==.Mephyna:BAAALAAECggICgAAAA==.Mevamber:BAAALAADCgYIBgAAAA==.Mevâmber:BAAALAAECgYIDAAAAA==.Meyonix:BAAALAADCgQIBAAAAA==.',Mi='Micorazón:BAAALAADCggICAAAAA==.Miib:BAAALAAECgcIEwAAAA==.Milyna:BAAALAADCggIHwAAAA==.Minzchen:BAAALAAECgMIBQAAAA==.Mirakuru:BAAALAADCgYIFQAAAA==.Mizugorou:BAAALAAECgMIAwAAAA==.',Mo='Moametal:BAAALAAECgYIEAAAAQ==.Moar:BAAALAADCgYIEgAAAA==.Modock:BAACLAAFFIEMAAIFAAUI+A7uCACdAQAFAAUI+A7uCACdAQAsAAQKgSkAAgUACAivJNIHAEwDAAUACAivJNIHAEwDAAAA.Moncler:BAAALAADCggIHAAAAA==.Moonchéri:BAAALAAECgEIAQABLAAECgEIAQAEAAAAAA==.Mortanius:BAAALAAECgIIAgAAAA==.',Mu='Murfo:BAAALAADCggIDwAAAA==.',My='Myitare:BAABLAAECoEbAAMVAAYImBuFIwDMAQAVAAYImBuFIwDMAQAWAAEIdAaqQwEwAAAAAA==.Mynthura:BAAALAADCggICAAAAA==.Mythra:BAABLAAECoEfAAQHAAcIoBzPIwBEAgAHAAcIoBzPIwBEAgAQAAcIOBGWOwCwAQAXAAUINw57GQD0AAAAAA==.',['Mâ']='Mâdâra:BAAALAADCggICAAAAA==.Mârsî:BAAALAAECgYIEAAAAA==.',['Mä']='Mäxii:BAAALAAECgUIEQAAAA==.',Na='Nadezhda:BAAALAAECgIIAgABLAAECgYIEAAEAAAAAQ==.Naitras:BAAALAADCgcIDwAAAA==.Naljia:BAAALAAECgYICgAAAA==.Namysan:BAAALAADCggIEwAAAA==.Namìleìn:BAAALAADCgYIBgAAAA==.Naniki:BAAALAAECgYIBgABLAAFFAIIBwAQALMWAA==.Narukâ:BAAALAADCggICAAAAA==.Naschbär:BAAALAADCgQIBAAAAA==.',Ne='Nemedi:BAAALAADCgYIBwAAAA==.',Ni='Nightbann:BAAALAAECgcIEAAAAA==.Nikã:BAAALAADCgcIBwAAAA==.Nimoeh:BAAALAAECgMIBAAAAA==.',No='Noducor:BAAALAADCgUICQAAAA==.Notmounty:BAAALAADCggIBwAAAA==.Notthehealer:BAAALAAECgIIAwAAAA==.',Nu='Nuath:BAAALAADCggICAABLAAECgYIEAAEAAAAAQ==.Nudelführer:BAABLAAECoEfAAIYAAcIWgpPlgBsAQAYAAcIWgpPlgBsAQAAAA==.',Ny='Nyrokdh:BAAALAADCggIDwABLAAECggIIAAZAP4XAA==.Nyrokdruid:BAAALAADCggICAABLAAECggIIAAZAP4XAA==.Nyrokpal:BAAALAAECgYIDAABLAAECggIIAAZAP4XAA==.Nyrokrouge:BAABLAAECoEgAAMZAAgI/hecDABHAgAZAAgI/hecDABHAgAaAAQIbBdeSAD9AAAAAA==.Nyu:BAABLAAECoEhAAIYAAgIhxflcAC3AQAYAAgIhxflcAC3AQAAAA==.Nyzit:BAABLAAECoEuAAMJAAgI6BJ8FwCsAQAJAAgI6BJ8FwCsAQABAAEIqQOfWwEjAAAAAA==.',Od='Oddos:BAAALAAECgIIAwAAAA==.',Og='Ogartar:BAAALAAECgIIAgAAAA==.Oggsor:BAABLAAECoEiAAISAAgI0hwCGQCHAgASAAgI0hwCGQCHAgAAAA==.Oggtus:BAAALAAECgEIAQABLAAECggIIgASANIcAA==.',Oh='Ohaa:BAAALAADCgYICQAAAA==.',Op='Opflstruddl:BAAALAAECgYIDAAAAA==.',Or='Orms:BAAALAADCggIFwAAAA==.Orogtar:BAAALAAECgYICgAAAA==.',Os='Oshkosh:BAABLAAECoEdAAIMAAcIziE7GACeAgAMAAcIziE7GACeAgAAAA==.Osirys:BAAALAADCgcICQAAAA==.',Ot='Otis:BAABLAAECoEbAAITAAYIbBrjLQCTAQATAAYIbBrjLQCTAQAAAA==.Ottilli:BAABLAAECoEWAAIKAAcI/hHRewCGAQAKAAcI/hHRewCGAQAAAA==.',Pa='Paladirne:BAAALAADCgcIBwABLAAFFAIIBwADAK4PAA==.Pande:BAAALAADCgMIAwAAAA==.',Pe='Peacebreaker:BAAALAADCgIIAgAAAA==.Pedin:BAAALAADCgQIBgAAAA==.Pelagra:BAAALAAECgEIAQAAAA==.Pelagrus:BAAALAAECgEIAQAAAA==.Pershaw:BAAALAADCggICAAAAA==.',Ph='Phîona:BAAALAADCgcIDQAAAA==.',Pr='Prositas:BAAALAAECgMIAwAAAA==.Proxa:BAAALAAECgIIBQAAAA==.',Ra='Rafo:BAAALAADCgYIBgAAAA==.Ragnaröck:BAAALAAECggIBwAAAA==.Rakuls:BAAALAADCggIJAAAAA==.Rasika:BAABLAAECoEoAAMIAAgI8CGFDQASAwAIAAgI8CGFDQASAwAMAAMI6BMR0QCnAAAAAA==.Raspyrrha:BAAALAADCggIHwAAAA==.',Re='Reginald:BAAALAAECgYIDAAAAA==.',Ri='Rilanía:BAAALAAECggICQAAAA==.',Ro='Rocksor:BAABLAAECoEbAAIKAAYIMxilfACEAQAKAAYIMxilfACEAQAAAA==.',Ru='Rumcas:BAAALAADCgcIEgAAAA==.Rumper:BAAALAAECgMIAwAAAA==.',Ry='Ryazit:BAAALAAECgUICgABLAAECggILgAJAOgSAA==.',['Ré']='Rémì:BAABLAAECoEfAAIJAAcIAhYtFwCxAQAJAAcIAhYtFwCxAQAAAA==.',Sa='Saio:BAACLAAFFIEFAAMCAAMI/AGgGACeAAACAAMI/AGgGACeAAAbAAIInABDDwBAAAAsAAQKgSwABAIACAhKFyshAD8CAAIACAhKFyshAD8CAAsACAhgFBonAAcCABsABwgDCysgAGkBAAAA.Samará:BAAALAAECggICwAAAA==.Samæl:BAAALAAECgEIAQAAAA==.Saronas:BAAALAADCggIGAAAAA==.Sashy:BAAALAADCggIBgAAAA==.',Sc='Schamanski:BAAALAADCgMIBAAAAA==.Schnabio:BAAALAAECgYIDwAAAA==.',Se='Seick:BAAALAAECgYIDwAAAA==.Seidenpfote:BAACLAAFFIEFAAIbAAIIDRIDCwCSAAAbAAIIDRIDCwCSAAAsAAQKgSYAAhsACAjsHbIJAJcCABsACAjsHbIJAJcCAAAA.Selènia:BAACLAAFFIEGAAIcAAMI7QSbCgCcAAAcAAMI7QSbCgCcAAAsAAQKgRoAAhwACAgnFAEfAMcBABwACAgnFAEfAMcBAAAA.',Sh='Shadowmina:BAAALAAECgIIAgAAAA==.Shaileen:BAABLAAECoEZAAIFAAgIVhoDPQAPAgAFAAgIVhoDPQAPAgAAAA==.Shalan:BAAALAAECgYIBwAAAA==.Shalandria:BAAALAADCggICAAAAA==.Shamasutra:BAAALAAECgYICwABLAAFFAIIBwADAK4PAA==.Shambo:BAAALAADCgcIDAABLAAECgYIDwAEAAAAAA==.Shamir:BAAALAAECgUIDAABLAAECggIEQAEAAAAAA==.Shedou:BAAALAAECgEIAQAAAA==.Shizuyona:BAABLAAECoEqAAIbAAgIQSK/CACrAgAbAAgIQSK/CACrAgAAAA==.Shogun:BAAALAAECgYIEgAAAA==.',Si='Sidina:BAAALAADCgYIBgAAAA==.Silivra:BAABLAAECoEbAAMBAAcIQB+CWgAPAgABAAcIQB+CWgAPAgAGAAIIKBJhRwB3AAAAAA==.Sinria:BAAALAADCggIGAAAAA==.',Sl='Slowmarri:BAAALAADCgYIBgAAAA==.',Sm='Smico:BAAALAADCggIBwAAAA==.Smilina:BAAALAADCgcICwAAAA==.',Sn='Sneewante:BAAALAAECgcIDwAAAA==.Snowbâll:BAAALAAECgYIEgAAAA==.Snówwhite:BAABLAAECoEaAAMVAAcIrxKnKACpAQAVAAcIrxKnKACpAQAWAAYICwac4wD+AAAAAA==.',So='Sorgas:BAAALAAECgUICAAAAA==.',Sp='Spooner:BAAALAAECgMIBAAAAA==.',Sr='Sranus:BAAALAADCgcIBwAAAA==.',Su='Subscriber:BAAALAADCgcIDgAAAA==.Sucara:BAAALAADCgMIBAAAAA==.Suvi:BAAALAADCgYIBgAAAA==.',Sz='Szedu:BAAALAADCggIEgAAAA==.',['Sâ']='Sâsûke:BAABLAAECoEVAAIWAAYIbBRBlQCSAQAWAAYIbBRBlQCSAQAAAA==.',Ta='Taeas:BAAALAADCggIGgAAAA==.Tagol:BAAALAAECggIBAAAAA==.Takeza:BAAALAADCgcIBwAAAA==.Talysra:BAAALAADCggIFwAAAA==.Tatà:BAAALAAECgcIEgAAAA==.',Te='Teelia:BAABLAAECoEgAAIRAAcIqQ92ZgCxAQARAAcIqQ92ZgCxAQAAAA==.Tekôda:BAAALAAECgYIDwAAAA==.Tenkjin:BAAALAADCggIDgAAAA==.Testoot:BAAALAADCgcICwAAAA==.',Th='Thalknight:BAAALAAECgMIAQAAAA==.Thallô:BAAALAAECgIIAgAAAA==.Thalocki:BAAALAADCggICAAAAA==.Theres:BAAALAADCgcIBAABLAAECggIJgAaAMshAA==.Thyrisa:BAAALAAECgYIDgAAAA==.',To='Tomagos:BAAALAADCgQIBAAAAA==.',Tr='Trace:BAAALAAECgYICQAAAA==.Trekar:BAAALAADCggICAABLAAECgcIHgADAD0aAA==.Tryna:BAAALAADCgYIBgAAAA==.',Ty='Tyny:BAAALAADCggICAAAAA==.',Un='Unithral:BAAALAAECgcICgAAAA==.Unkabale:BAAALAADCgIIAQAAAA==.',Va='Variel:BAAALAADCggICAAAAA==.',Ve='Vehlara:BAAALAADCggICAAAAA==.Venooro:BAAALAAECgIIAgABLAAECggIJgAdAHkdAA==.Venuro:BAABLAAECoEmAAIdAAgIeR1XBADGAgAdAAgIeR1XBADGAgAAAA==.',Vn='Vnf:BAAALAADCgcIDwAAAA==.',Vo='Vorletzter:BAAALAADCggIHQAAAA==.',['Vâ']='Vâlaria:BAAALAADCgcIBwAAAA==.',['Vé']='Vérion:BAAALAADCgcIDgAAAA==.',Wa='Walisdudu:BAABLAAECoEUAAICAAgIyBCiPgCvAQACAAgIyBCiPgCvAQABLAAFFAUIEwAHALkUAA==.Walisschami:BAAALAAECgcIEQABLAAFFAUIEwAHALkUAA==.Walíss:BAACLAAFFIETAAIHAAUIuRTSBQCsAQAHAAUIuRTSBQCsAQAsAAQKgScAAwcACAhsG14cAHUCAAcACAhsG14cAHUCABAABAgVCvdqAMUAAAAA.Watc:BAAALAADCgcIDQAAAA==.',Wr='Wroglen:BAAALAADCggICQAAAA==.',Yi='Yingtao:BAABLAAECoEUAAIeAAgIQgmxJABMAQAeAAgIQgmxJABMAQAAAA==.',Yo='You:BAAALAADCgcIBwAAAA==.',Yu='Yuimetal:BAAALAAECgQIBQABLAAECgYIEAAEAAAAAQ==.Yukishiro:BAABLAAECoEfAAICAAcIHho5KQATAgACAAcIHho5KQATAgAAAA==.Yukti:BAAALAADCgYIBgAAAA==.Yuula:BAAALAADCggICAAAAA==.',['Yé']='Yénnefer:BAAALAAECgYIEwAAAA==.',Za='Zablo:BAAALAAECgYIEQAAAA==.Zaccharia:BAAALAAECgIIBQABLAAECgYIHQAWAOUUAA==.Zando:BAAALAADCgYICQAAAA==.Zaraya:BAAALAAECgQICAAAAA==.',Ze='Zeko:BAAALAADCgUIBwAAAA==.Zerrox:BAAALAADCgUIBQAAAA==.',Zu='Zuckerstange:BAAALAAECgIIAgAAAA==.',Zv='Zvrk:BAAALAADCgYIBgAAAA==.',['Âk']='Âkina:BAAALAAECgUIBQAAAA==.',['Ér']='Ériu:BAACLAAFFIEFAAILAAIIVRGyFACVAAALAAIIVRGyFACVAAAsAAQKgRoAAgsABghqHU8mAAwCAAsABghqHU8mAAwCAAAA.',['Ðr']='Ðragon:BAABLAAECoEWAAIfAAYIWgwVhgA3AQAfAAYIWgwVhgA3AQAAAA==.',['Øz']='Øzzem:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end