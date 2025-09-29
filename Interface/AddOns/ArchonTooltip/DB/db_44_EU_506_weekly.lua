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
 local lookup = {'Druid-Balance','Druid-Feral','Druid-Restoration','Paladin-Retribution','Mage-Frost','Hunter-Marksmanship','Hunter-BeastMastery','Warrior-Fury','Unknown-Unknown','Shaman-Enhancement','Hunter-Survival','Monk-Brewmaster','Shaman-Restoration','Priest-Shadow','Warlock-Demonology','Warlock-Destruction','Paladin-Protection','Priest-Holy','Warrior-Protection','Mage-Arcane','Warlock-Affliction','DemonHunter-Vengeance','Warrior-Arms','Shaman-Elemental','Rogue-Assassination','Monk-Windwalker','Paladin-Holy','Priest-Discipline','DeathKnight-Blood','DeathKnight-Unholy','DemonHunter-Havoc','DeathKnight-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian',}; local provider = {region='EU',realm='Exodar',name='EU',type='weekly',zone=44,date='2025-09-25',data={Ab='Abalham:BAAALAAECgMIBQAAAA==.',Ae='Aedonia:BAABLAAECoEXAAIBAAYIchK5RgBmAQABAAYIchK5RgBmAQAAAA==.Aelarion:BAAALAAECgYICwAAAA==.Aerthrei:BAABLAAECoEkAAMCAAgInhz/EQALAgACAAcIxh7/EQALAgADAAgIjxEEPAC6AQAAAA==.',Af='Afy:BAAALAADCgcIDAAAAA==.',Ag='Aguda:BAABLAAECoEiAAIEAAcIKRCnlgCQAQAEAAcIKRCnlgCQAQAAAA==.',Aj='Ajjtyze:BAAALAADCgMIAwAAAA==.',Al='Alarìelle:BAAALAADCggIEAAAAA==.Aldara:BAAALAADCggIGQAAAA==.Aldreon:BAABLAAECoEhAAIBAAcIfhdpMwDAAQABAAcIfhdpMwDAAQAAAA==.Alexpik:BAAALAADCgYIBgAAAA==.Alianaa:BAAALAADCggIEAAAAA==.Alid:BAAALAAECgYICwABLAAECggILgAFAOYeAA==.Alimaño:BAAALAAECgUIBwAAAA==.Alteina:BAAALAAECgIIAgAAAA==.Althurius:BAAALAADCggIDwAAAA==.Alëu:BAAALAADCggICAAAAA==.',Am='Amandaruibis:BAAALAAECgUIBQAAAA==.',An='Anbun:BAAALAADCggIDAAAAA==.Angharad:BAAALAAECgYICAAAAA==.Ankou:BAAALAADCgIIAgAAAA==.Antonella:BAAALAADCgMIAwAAAA==.Antoniusv:BAAALAAECgIIAgAAAA==.Anux:BAAALAAECgIIAgAAAA==.Anxort:BAAALAAECgcICAAAAA==.',Ar='Aralechan:BAAALAADCgcIBwAAAA==.Arasunu:BAAALAADCgcIBwAAAA==.Archagathus:BAAALAADCgYICAAAAA==.Arcoroto:BAAALAADCggICAAAAA==.Arewan:BAAALAAECgcIEwAAAA==.Arká:BAAALAAECgYIBwAAAA==.Armsant:BAAALAAECgIIAgAAAA==.Artcangel:BAAALAAECgIIAgAAAA==.Artorias:BAAALAAECgMIAwAAAA==.Arzillidan:BAAALAADCgcICgAAAA==.Arâtor:BAAALAAECgYIDAAAAA==.',As='Asdriel:BAAALAAECgEIAQAAAA==.Aseere:BAAALAAECgYIEQAAAA==.Ashër:BAAALAADCgcIEQAAAA==.',At='Ateneadiosaa:BAAALAADCgYIBgAAAA==.',Ax='Axoreth:BAAALAAECgcIEQAAAA==.',Ay='Ayev:BAAALAAECgEIAgAAAA==.',Az='Azuladó:BAAALAADCgcICgAAAA==.Azulilla:BAAALAAECgUIDAAAAA==.Azzra:BAAALAAECgEIAQAAAA==.',['Aí']='Aíka:BAABLAAECoEaAAMGAAcIQBUIOQC9AQAGAAcIQBUIOQC9AQAHAAIImgO9CAFMAAAAAA==.',Ba='Bacon:BAAALAAECgMICAAAAA==.Bada:BAAALAADCggIIAAAAA==.Bagarok:BAAALAAECgEIAQABLAAFFAMIBwAIAE8bAA==.Balana:BAAALAADCgMIAwAAAA==.Balaurl:BAAALAADCgcICgAAAA==.Bangg:BAAALAADCggICAABLAAECgEIAQAJAAAAAA==.Banik:BAAALAADCgQIBAAAAA==.Bansheec:BAAALAAECgYIDAAAAA==.Batys:BAAALAADCgQIBAAAAA==.',Be='Belangy:BAABLAAECoEXAAIDAAYI4CPcHABYAgADAAYI4CPcHABYAgAAAA==.Bernje:BAAALAAECgYIDQAAAA==.',Bh='Bhuka:BAABLAAECoEYAAIKAAYIKBy+DQDoAQAKAAYIKBy+DQDoAQAAAA==.',Bl='Blackwiidoww:BAAALAAECgYIBgAAAA==.Bloodihammer:BAAALAAECgQIBQAAAA==.Blun:BAAALAADCgYIBgAAAA==.Blutbad:BAAALAAECgcIBwAAAA==.',Bo='Bocatajamón:BAAALAAECgUICgAAAA==.Bolg:BAAALAADCgIIAgAAAA==.Bortista:BAACLAAFFIEKAAILAAIIMiVaAQDVAAALAAIIMiVaAQDVAAAsAAQKgSUABAsACAigJA0BAEgDAAsACAigJA0BAEgDAAcABAijHlyeAEIBAAYAAwjpHbVrAP0AAAAA.',Br='Breccan:BAAALAADCggIEwAAAA==.Brochetilla:BAABLAAECoElAAIMAAgIqB4kCQCvAgAMAAgIqB4kCQCvAgAAAA==.Brombur:BAAALAADCggIFwAAAA==.Bromdk:BAAALAAECgMIAwAAAA==.Bronzer:BAAALAAECgMIAwAAAA==.Brujasagrada:BAAALAADCgQIBAAAAA==.',Bu='Bulcanuss:BAAALAADCggIDAAAAA==.',Ca='Cacuna:BAABLAAECoEYAAIEAAcIWRQxcgDVAQAEAAcIWRQxcgDVAQAAAA==.Caelfa:BAAALAAECgMIAwAAAA==.Cain:BAAALAADCgYICQAAAA==.Calau:BAAALAADCggICgAAAA==.Calihunter:BAAALAADCgUICQAAAA==.Campajunior:BAAALAADCgcICgAAAA==.Cazsolitario:BAAALAADCgcICAAAAA==.',Ce='Celtrix:BAAALAAECgYICgAAAA==.Cerian:BAABLAAECoEoAAIDAAgIYSBVDQDRAgADAAgIYSBVDQDRAgAAAA==.Cerridwenn:BAAALAADCgYIBgAAAA==.',Ch='Chanell:BAAALAADCggIIQAAAA==.Charizar:BAAALAADCgIIAgAAAA==.Chuchinho:BAAALAADCgcICQAAAA==.Chuzas:BAABLAAECoEXAAINAAcInRBKdQBhAQANAAcInRBKdQBhAQAAAA==.Chäcalote:BAAALAADCgMIAwAAAA==.',Ci='Cieloso:BAAALAAECgUIBQAAAA==.',Cl='Clarïty:BAAALAADCggICgABLAAECggIEAAJAAAAAA==.Clawd:BAAALAADCggIEAABLAAECgYIBwAJAAAAAA==.Clk:BAAALAADCgYICwAAAA==.',Co='Cooltirana:BAAALAAECgEIAQAAAA==.Cosîta:BAAALAADCgcICAAAAA==.',Cr='Croquetta:BAAALAADCgIIAgAAAA==.',Cu='Cubahabana:BAAALAADCgYIBgAAAA==.Curasion:BAAALAAECgQIBAAAAA==.Cuxiku:BAAALAAECgIIAwAAAA==.',Cy='Cyrek:BAAALAADCggIEAAAAA==.',['Cí']='Cídron:BAAALAADCgMIAwAAAA==.',Da='Daanikkendov:BAAALAADCggIDQAAAA==.Daisuka:BAAALAAECgQIBAAAAA==.Damawhite:BAAALAADCggIGAAAAA==.Danred:BAAALAAECgEIAQAAAA==.Dardinhox:BAAALAAECgYIBAABLAAECgYICAAJAAAAAA==.Darkclawss:BAAALAAECggIEwAAAA==.Darkwing:BAAALAADCgIIAgAAAA==.Darthlottus:BAAALAADCgcIBwAAAA==.',De='Deathrall:BAAALAAECgMIBAAAAA==.Dechil:BAAALAAECgUIBQAAAA==.Delaron:BAABLAAECoEYAAIOAAcI4AlzSgBqAQAOAAcI4AlzSgBqAQAAAA==.Desgadelha:BAABLAAECoEaAAMPAAcIiyHlDACHAgAPAAcIRyDlDACHAgAQAAUIOh7yZwCGAQAAAA==.Destroid:BAAALAADCgEIAQAAAA==.Destíny:BAAALAADCggIEAAAAA==.Devilmen:BAAALAADCgEIAQAAAA==.',Di='Diabolica:BAAALAADCgYIBgAAAA==.Diffâ:BAAALAADCgcICAAAAA==.Dixania:BAAALAAECgEIAQAAAA==.',Do='Doe:BAABLAAECoEgAAIHAAgI5hXnbgCiAQAHAAgI5hXnbgCiAQAAAA==.Dogmá:BAAALAADCggICAAAAA==.Domosh:BAABLAAECoEUAAIEAAYI3RcSfgC9AQAEAAYI3RcSfgC9AQABLAAECgcIFwAIAP0fAA==.',Dr='Draeniman:BAAALAAECgYIBwAAAA==.Dragonitern:BAAALAADCgEIAQAAAA==.Dragonlaysa:BAAALAADCgUIBQAAAA==.Drakoroth:BAAALAAECgYIDgAAAA==.Dranotan:BAABLAAECoEYAAIIAAYImxFwbwBuAQAIAAYImxFwbwBuAQAAAA==.Dranök:BAAALAADCgcIBwAAAA==.Draë:BAAALAAECgMICAABLAAECgYIBwAJAAAAAA==.Drinea:BAAALAAECgYICAAAAA==.Druidit:BAAALAADCgcICQAAAA==.Druidote:BAAALAADCgUIBQAAAA==.Drukhari:BAAALAADCgcIBwAAAA==.Drusk:BAAALAAECgIIAgABLAAECggIGgARAO4cAA==.Dränna:BAAALAAECgEIAQAAAA==.',Du='Dugut:BAAALAADCgcIDQAAAA==.Duquesiya:BAAALAADCggICwAAAA==.',Dw='Dwarfchuck:BAAALAADCggICwAAAA==.Dwayna:BAACLAAFFIEGAAISAAII9A1eJgCNAAASAAII9A1eJgCNAAAsAAQKgRoAAhIABwgsE8VCAKcBABIABwgsE8VCAKcBAAAA.',Dy='Dystopía:BAAALAADCgMIAwAAAA==.',['Dô']='Dômos:BAABLAAECoEXAAMIAAcI/R+nIwCLAgAIAAcI/R+nIwCLAgATAAYIfxcmLwCWAQAAAA==.',Ed='Edusite:BAAALAAECgIIAgAAAA==.',El='Elenthar:BAAALAADCggICAAAAA==.Elinath:BAAALAAECgYICQAAAA==.Elir:BAABLAAECoEXAAIIAAYIdwqpggA4AQAIAAYIdwqpggA4AQAAAA==.Elirath:BAAALAAECgYIEAABLAAECgYICQAJAAAAAA==.',En='Encenall:BAAALAAECgQIBwAAAA==.Endx:BAAALAADCggIEAAAAA==.Enrique:BAAALAAECgcIEAAAAA==.',Er='Erickasm:BAAALAADCgcIEQAAAA==.Erloba:BAAALAAECgMICAAAAA==.',Es='Eskalybusito:BAAALAADCgYIDAABLAAECggIDgAJAAAAAA==.Essedia:BAAALAADCgcICAAAAA==.',Et='Etherion:BAAALAADCgYICwAAAA==.Etimos:BAABLAAECoEZAAIUAAcIFBI9bwCZAQAUAAcIFBI9bwCZAQAAAA==.',Eu='Euu:BAAALAADCggIDQAAAA==.',Ex='Exae:BAAALAADCggIDAAAAA==.',['Eú']='Eúnice:BAAALAAECgQICwAAAA==.',Fa='Faëdra:BAAALAAECgUIDAAAAA==.',Fe='Fenixobscura:BAAALAADCgcIDgAAAA==.Fenther:BAAALAADCgYIBgAAAA==.Feralhound:BAABLAAECoEVAAIGAAYIDgeRcwDiAAAGAAYIDgeRcwDiAAAAAA==.',Fh='Fharia:BAAALAAECgEIAQAAAA==.',Fl='Flappyy:BAAALAADCgcIEAAAAA==.Flayvier:BAAALAADCggICAAAAA==.',Fo='Fokkus:BAACLAAFFIEOAAMQAAUISh3PCgDEAQAQAAUISh3PCgDEAQAPAAEIlQPiJwA+AAAsAAQKgSAABBAACAicJcUHAEsDABAACAiPJcUHAEsDAA8ABQh2FmhDAD4BABUAAggRDrAoAIoAAAAA.Forn:BAAALAADCgQIBAAAAA==.Foxe:BAAALAAECggICAAAAA==.',Fr='Fraystiek:BAAALAAECgEIAQAAAA==.Frostfault:BAAALAAECgUIDgAAAA==.Frostylime:BAAALAAECgIIAgAAAA==.Frónt:BAABLAAECoEXAAINAAYIRh3tRwDdAQANAAYIRh3tRwDdAQAAAA==.',Fu='Fujinari:BAAALAAECgMIBAAAAA==.Furîâ:BAABLAAECoEmAAIEAAcIyxmhXgD/AQAEAAcIyxmhXgD/AQAAAA==.',['Fí']='Fíttz:BAAALAADCggICQAAAA==.',['Fî']='Fîtz:BAAALAADCggICAAAAA==.Fîve:BAAALAADCggIBwAAAA==.',['Fö']='Fördragón:BAAALAAECgMIBAAAAA==.',Ga='Gallon:BAAALAAECgYIDAABLAAECgcIIQAEAD4bAA==.Garaa:BAAALAAECgYIDgAAAA==.Garatoth:BAAALAAECgQIBQAAAA==.Gargarth:BAAALAADCgUIBgAAAA==.Gazzeellee:BAAALAAECgYIBwAAAA==.',Gh='Ghostrex:BAAALAADCgMIAwAAAA==.',Gi='Gipsymoi:BAAALAADCgQIBgAAAA==.',Gl='Glaiveage:BAABLAAECoEUAAIWAAYIsyRADABuAgAWAAYIsyRADABuAgAAAA==.',Gr='Gragonus:BAAALAAECgEIAQABLAAECgcIDAAJAAAAAA==.Gragow:BAAALAAECgYIDQABLAAECgcIDAAJAAAAAA==.Graylight:BAAALAADCgYIBgAAAA==.Greenslayer:BAAALAAECgcIDQAAAA==.Greine:BAAALAAECgUICwAAAA==.Gruhto:BAAALAAECgIIAgAAAA==.',Gu='Guarrøsh:BAABLAAECoEcAAIIAAcIVRaLQQD9AQAIAAcIVRaLQQD9AQAAAA==.Guayoota:BAAALAAECgYIDwAAAA==.Guindy:BAAALAAECgMIAwAAAA==.',['Gô']='Gôldôrâk:BAAALAAECgUIBAAAAA==.',['Gø']='Gøken:BAAALAADCgUIBQAAAA==.',['Gü']='Güendel:BAAALAADCgIIAgAAAA==.',Ha='Habanerita:BAAALAADCgIIAgAAAA==.Habichuelas:BAAALAAECgYIDAAAAA==.Hahli:BAAALAAECgEIAQAAAA==.Hanja:BAAALAAECgQIBwAAAA==.Haraldir:BAAALAAECgIIAgAAAA==.Hastaroth:BAAALAAECgYIEwAAAA==.',He='Hechilinda:BAAALAAECgMICAAAAA==.Heiryc:BAAALAAECggIEgAAAA==.Heiter:BAAALAADCgcIBwAAAA==.Helerx:BAAALAADCggICAAAAA==.Helevorm:BAAALAADCggIBgAAAA==.',Hk='Hkorkst:BAAALAAECgQICAAAAA==.',Ho='Hooligan:BAAALAADCgcICwAAAA==.Hornkiller:BAAALAADCgcIBwAAAA==.',['Hé']='Hécäte:BAAALAADCggICAAAAA==.',['Hö']='Höwler:BAAALAADCgEIAQAAAA==.',['Hø']='Hølä:BAAALAADCgIIAgABLAAECgUIDAAJAAAAAA==.Høøpa:BAAALAAECgYICAAAAA==.',['Hü']='Hüor:BAABLAAECoEXAAIEAAcIYgqhsABhAQAEAAcIYgqhsABhAQAAAA==.',Ic='Icefrost:BAAALAAECgYICAABLAAECgcIDQAJAAAAAA==.Icymaster:BAAALAAECgYIBwAAAA==.',Id='Idridan:BAAALAAECgYICQAAAA==.',Ig='Igerna:BAAALAADCgQIBAAAAA==.Ignixs:BAAALAADCgYIDgAAAA==.',Ik='Ikk:BAAALAAECgYIEwAAAA==.',Il='Ilisene:BAABLAAECoEWAAIWAAgIOAkmKgAuAQAWAAgIOAkmKgAuAQAAAA==.Illthelion:BAAALAAECgIIAgAAAA==.',Im='Imnotyisus:BAAALAAECgUIBwAAAA==.Imwa:BAAALAAECgUIBgAAAA==.',In='Infernos:BAAALAADCgIIAgAAAA==.Insanë:BAACLAAFFIEHAAIIAAMITxtFDQAeAQAIAAMITxtFDQAeAQAsAAQKgSAAAwgACAg7I6kRAAUDAAgACAgJI6kRAAUDABcAAQhuJYkqAGwAAAAA.Insolencia:BAAALAAECgEIAQAAAA==.',Ir='Iráka:BAAALAADCgUIBQAAAA==.',Is='Iscc:BAABLAAECoEUAAIQAAYImQ58dQBiAQAQAAYImQ58dQBiAQAAAA==.',Iv='Ivanra:BAAALAADCgQIBAAAAA==.Ivuzfarm:BAAALAADCgMIAwAAAA==.',Iz='Izanagii:BAAALAAECgYIEQAAAA==.Izaras:BAAALAADCggIHAAAAA==.Izza:BAAALAAECgMIAwAAAA==.',Ja='Jaraksus:BAAALAADCgIIAgABLAAECgYICwAJAAAAAA==.Javirux:BAAALAAECgYICwAAAA==.Jazzminne:BAAALAAECgYIEAABLAAECggIHgAEANUaAA==.',Je='Jesudas:BAAALAADCgYIBgAAAA==.',Ji='Jiafei:BAAALAADCgEIAQAAAA==.',Ju='Jugenio:BAAALAAECgUIBwAAAA==.Jugenioo:BAAALAAECgYICgAAAA==.Jumisans:BAAALAADCgUIBQAAAA==.Junsonwon:BAAALAAECgEIAgAAAA==.Junter:BAAALAAECgcICQAAAA==.Jurian:BAAALAADCgcIBwAAAA==.',['Jí']='Jíll:BAAALAAFFAIIBAABLAAFFAMICAAIAF4mAA==.',Ka='Kadghar:BAAALAADCgEIAQAAAA==.Kadrea:BAAALAADCgcIBwAAAA==.Kaldraht:BAABLAAECoEVAAIEAAcIAR3+TwAkAgAEAAcIAR3+TwAkAgAAAA==.Kaltsit:BAAALAADCgYIBgAAAA==.Kandda:BAABLAAECoEfAAIEAAcINRIUiwClAQAEAAcINRIUiwClAQAAAA==.Kanus:BAABLAAECoEXAAMVAAYIqQXxHwDNAAAQAAYIHAWKpgDSAAAVAAYIZgPxHwDNAAAAAA==.Karlitta:BAAALAADCgIIAgAAAA==.Kashell:BAAALAAECgYIEQAAAA==.Katyanjaeh:BAAALAADCggICAAAAA==.Kavhe:BAAALAAECgQIBgABLAAFFAQICgATAL0aAA==.Kayxo:BAAALAAECgQICQAAAA==.',Ke='Kenjan:BAABLAAECoEVAAMFAAYI2RGUQgA/AQAFAAYI0w2UQgA/AQAUAAQItBNEoAANAQAAAA==.Kessëlring:BAABLAAECoEsAAIWAAgIZApTKgAtAQAWAAgIZApTKgAtAQAAAA==.Ketchupnator:BAAALAAECgYICAAAAA==.Kettchup:BAAALAADCgcIBwAAAA==.',Kh='Khada:BAAALAAECgcICAAAAA==.Khyslai:BAABLAAECoEqAAMNAAgIdSGyEADOAgANAAgIdSGyEADOAgAYAAYIHhG7YQBhAQAAAA==.Khãn:BAAALAAECgQIBQAAAA==.',Ki='Kiari:BAAALAAECggICAABLAAFFAIIAgAJAAAAAA==.Killmong:BAAALAADCgIIAgAAAA==.Kinomoto:BAAALAAECgIIBAAAAA==.Kirxzz:BAAALAADCggIFgAAAA==.Kitzuney:BAAALAADCgMIBAAAAA==.',Kl='Kleia:BAABLAAECoEaAAMRAAgI7hz8DQB0AgARAAgI7hz8DQB0AgAEAAEIfgpFRAEvAAAAAA==.Klexia:BAAALAAECggIEgABLAAECggIGgARAO4cAA==.Klunterino:BAAALAADCgIIAgAAAA==.',Ko='Kohkaul:BAAALAADCgEIAQAAAA==.Kolono:BAAALAAECgEIAQAAAA==.Kolorao:BAAALAADCgcIDwAAAA==.Konrad:BAAALAADCgMIAwAAAA==.Koshii:BAABLAAECoEjAAIZAAgIWReyGQA3AgAZAAgIWReyGQA3AgAAAA==.Kostolom:BAAALAADCggICQAAAA==.',Kr='Kracht:BAAALAAECgYIDgAAAA==.Kralidus:BAAALAAFFAIIBQAAAQ==.Krazêr:BAAALAADCggICAAAAA==.Krishnâ:BAABLAAECoEWAAIOAAYI4ANnagDIAAAOAAYI4ANnagDIAAAAAA==.Krumm:BAAALAAECgYIEgAAAA==.',Ku='Kurorogue:BAAALAAECgIIAgAAAA==.',Ky='Kyhon:BAAALAADCgIIAgAAAA==.Kyowe:BAABLAAECoEUAAIaAAgIRwflOwAGAQAaAAgIRwflOwAGAQAAAA==.Kyroxx:BAAALAADCgcIBwAAAA==.Kyríe:BAAALAAECgQIBwAAAA==.',La='La:BAAALAAECgYICAAAAA==.Laccress:BAAALAAECgYIDgAAAA==.Laerdat:BAABLAAECoEmAAINAAgITA3lfgBKAQANAAgITA3lfgBKAQAAAA==.Laevantine:BAAALAADCgcICQAAAA==.Lamoni:BAAALAADCgYIDAAAAA==.Lanegang:BAAALAAECgYIBgAAAA==.Laural:BAAALAADCgcIBwAAAA==.',Le='Lechuzon:BAAALAADCgUIBwAAAA==.Leonar:BAAALAADCgcICgAAAA==.Lethion:BAAALAAECgQIBQAAAA==.Letumortis:BAAALAADCgYICQAAAA==.',Li='Liitta:BAAALAAECgcIDQAAAA==.Linalee:BAAALAAECgUIBQAAAA==.Lingxiaøyu:BAAALAAECgIIAgABLAAECgcIFwAbAGUgAA==.',Ll='Llorim:BAAALAAECgcIAQAAAA==.',Lo='Lobiza:BAAALAADCggIEAAAAA==.',Lu='Lutel:BAAALAAECgMICAAAAA==.',Lx='Lx:BAACLAAFFIEHAAIHAAIIohoRIwCdAAAHAAIIohoRIwCdAAAsAAQKgSgAAwcACAi2IsAbAL8CAAcACAi2IsAbAL8CAAYABAjDEgVwAO8AAAAA.',Ly='Lycanon:BAABLAAECoEcAAMDAAgINxYoLgD7AQADAAgINxYoLgD7AQABAAcIKhSUNQC2AQAAAA==.Lynazara:BAAALAADCgQIBAAAAA==.',['Lî']='Lîz:BAAALAADCgcIDAAAAA==.',['Lø']='Løcknox:BAAALAAECgYICAAAAA==.Løthduin:BAAALAADCggICAAAAA==.',['Lü']='Lüxor:BAAALAADCgUIBQABLAAECgcIHQAbALkjAA==.Lüxôr:BAABLAAECoEdAAIbAAcIuSOoBwDYAgAbAAcIuSOoBwDYAgAAAA==.',['Lÿ']='Lÿla:BAAALAAECgcIDgAAAA==.',Ma='Madalena:BAAALAADCggIGgAAAA==.Magicos:BAAALAAECgUIBgAAAA==.Magoboss:BAAALAAECgYIEAAAAA==.Malamiga:BAAALAAECgMIBQAAAA==.Malpatin:BAAALAAECgEIAgAAAA==.Mamertox:BAAALAAECgMIBQAAAA==.Manaelen:BAAALAAECgEIAQAAAA==.Manje:BAAALAADCgQIBAABLAAECgQICAAJAAAAAA==.Mawii:BAAALAADCggIDwAAAA==.',Me='Mechanidhogg:BAAALAADCgYIBgAAAA==.Melpomener:BAABLAAECoEfAAMcAAYIWSOnBQBEAgAcAAYIWSOnBQBEAgAOAAUITxlISQBvAQAAAA==.Menedir:BAAALAADCggIFAAAAA==.Mennon:BAAALAAECgUICwAAAA==.Mentak:BAAALAADCgYIBgAAAA==.',Mi='Miaussita:BAABLAAECoEfAAMIAAgI6xsNJACJAgAIAAgI6xsNJACJAgATAAcI4g94NwBoAQAAAA==.Micheela:BAAALAADCgYIBgAAAA==.Midarrow:BAAALAADCgcIDwAAAA==.Miihhxrchena:BAABLAAECoEUAAMSAAcIjxQOPgC7AQASAAcIjxQOPgC7AQAcAAMI6QUjKQBiAAAAAA==.Mimic:BAAALAAECgYICgAAAA==.Minhox:BAAALAAECgIIAgAAAA==.Minhoxpal:BAAALAAECgcIDgAAAA==.Minhoxsacer:BAABLAAECoEYAAQcAAYInBg2DAC2AQAcAAYInBg2DAC2AQASAAQIrQoihQCyAAAOAAMITwlmdQCJAAAAAA==.Minhoxvalido:BAAALAAECgEIAQAAAA==.Minihealer:BAAALAADCgYIBwAAAA==.Minikuren:BAAALAADCgYIBgAAAA==.Miraunt:BAAALAADCgYICgAAAA==.Misah:BAABLAAECoEfAAISAAgIgBEqSgCIAQASAAgIgBEqSgCIAQAAAA==.',Ml='Mlynar:BAAALAADCgcIBwAAAA==.',Mo='Moimorto:BAAALAADCggICAAAAA==.Morrón:BAAALAADCgMIAwAAAA==.Moshenpo:BAAALAAECgYIDQAAAA==.',Mu='Muertchuck:BAAALAADCgMIAwAAAA==.Muffy:BAAALAAECgUIBgAAAA==.',['Mï']='Mïchi:BAAALAADCgYICgAAAA==.',['Mô']='Môrphüs:BAAALAAECgYICAAAAA==.',['Mö']='Möyra:BAAALAAECgYIEAAAAA==.',['Mø']='Mørrø:BAAALAAECgYIDAABLAAECggIHgAEANUaAA==.',Na='Nalak:BAAALAAECgEIAQAAAA==.Nalice:BAAALAADCggIDgAAAA==.Naruend:BAAALAADCgIIAgAAAA==.Narydie:BAAALAADCgcICwAAAA==.Naturebringe:BAAALAADCggIBgAAAA==.Naturecraft:BAAALAAECgYIDQAAAA==.Natáre:BAAALAAECgYIDgAAAA==.',Ne='Nealiel:BAABLAAECoEUAAIFAAcIFhZcIwDgAQAFAAcIFhZcIwDgAQAAAA==.Neferuh:BAAALAADCgcICQAAAA==.Nemur:BAAALAADCgYIBwAAAA==.Nenamia:BAAALAADCgEIAQAAAA==.Neusen:BAAALAADCgUIBQAAAA==.',Nh='Nhagash:BAAALAAECgcIDQAAAA==.',Ni='Niaoth:BAAALAAECgYIBgAAAA==.Nidhogg:BAAALAADCgYIBwAAAA==.Nikkîta:BAAALAADCggIDwAAAA==.Ningendo:BAAALAAECgYIBgAAAA==.Ningendö:BAAALAAECgYIDAAAAA==.Ninphadora:BAABLAAECoEbAAIEAAcIshcAcwDTAQAEAAcIshcAcwDTAQAAAA==.Ninphurion:BAAALAAECgIIAgAAAA==.Niohöggr:BAABLAAECoEiAAMdAAgImx6pCQCYAgAdAAgImx6pCQCYAgAeAAII3hCASQBrAAAAAA==.',No='Nocurolows:BAABLAAECoEdAAMcAAgIyB8pAgDdAgAcAAgIyB8pAgDdAgAOAAIIjgf4fgBcAAAAAA==.Nocurona:BAAALAADCgUIBQAAAA==.Nocílla:BAAALAADCgcICAAAAA==.Norawithh:BAAALAAECgUIBgAAAA==.Norbak:BAAALAADCgYIBgAAAA==.Nossel:BAAALAADCgcICAAAAA==.',Ny='Nyahunterman:BAAALAADCgYIBgAAAA==.',['Ná']='Náruta:BAAALAADCggIEAABLAAECgcIJgAEAMsZAA==.',['Nö']='Nött:BAAALAADCgUIBQABLAAECggIHwAIAOsbAA==.',Or='Orcmo:BAAALAADCgYIBgAAAA==.Orco:BAAALAAECggICgAAAA==.Oronegro:BAAALAAECgYIDwAAAA==.',Os='Oseapanda:BAABLAAECoEsAAMMAAgInRIzGwCWAQAMAAgIzg8zGwCWAQAaAAYIehJ9MQBNAQAAAA==.',Pa='Palanquetâ:BAAALAAECgUIAwAAAA==.Panacetamol:BAABLAAECoEYAAMKAAgI9xGiCwATAgAKAAgI9xGiCwATAgANAAEIYRCTDQExAAAAAA==.Pastorin:BAAALAAECgMIBgAAAA==.Pathro:BAAALAADCggIJwAAAA==.Patroz:BAAALAADCgcIBwAAAA==.',Pe='Pegamé:BAAALAAECgYIDQAAAA==.Perpon:BAAALAAECgYICgAAAA==.',Pi='Picolotres:BAAALAAECgYIDwAAAA==.Pikoalex:BAAALAADCggIDwAAAA==.Piru:BAAALAADCgYIBwAAAA==.Pitibrujo:BAAALAADCgcIBAAAAA==.Pitidh:BAAALAADCgYIBgAAAA==.',Po='Pokky:BAAALAAECgYICAAAAA==.Polamalu:BAAALAADCgUICQAAAA==.Pollidalf:BAABLAAECoEuAAMFAAgI5h4VDQCwAgAFAAgI5h4VDQCwAgAUAAYIphMXbwCZAQAAAA==.Portavoz:BAAALAAECgIIAQAAAA==.',Pr='Priestitutø:BAAALAAECgYICwAAAA==.Prmatrago:BAAALAAECgEIAQAAAA==.',Pt='Pthh:BAABLAAECoEXAAIQAAgIlw6tWACzAQAQAAgIlw6tWACzAQAAAA==.',Pu='Pub:BAAALAAECgYIEQABLAAECgcIJgAEAMsZAA==.Puthress:BAAALAADCggIJgAAAA==.',Qu='Quetecalless:BAAALAADCgEIAQAAAA==.Quetsalcoatl:BAABLAAECoEfAAIDAAcIEhJASQCEAQADAAcIEhJASQCEAQABLAAECggILgAFAOYeAA==.',Ra='Raijmh:BAAALAAECgYICwAAAA==.Rayovallecan:BAAALAADCgcICAAAAA==.Rayzenn:BAAALAAECgYICQAAAA==.',Re='Rebram:BAAALAADCgQIBAAAAA==.Reddemon:BAABLAAECoEXAAIfAAgIXBdoUAAHAgAfAAgIXBdoUAAHAgAAAA==.Redhellboy:BAAALAADCgMIAwAAAA==.Rekird:BAAALAADCgcIBwAAAA==.Reserter:BAAALAAECgYICwAAAA==.Rexs:BAAALAAECgYIBgAAAA==.',Ri='Ribk:BAAALAADCgcICAAAAA==.Rickwolf:BAAALAADCggICAAAAA==.Riika:BAAALAADCgcIBwABLAADCgcICgAJAAAAAA==.Riverwyndd:BAAALAADCgYIBwABLAADCgcIBwAJAAAAAA==.',Ro='Robabocatas:BAAALAADCgcIBwAAAA==.Rodri:BAAALAADCgcIDQAAAA==.Rouco:BAAALAADCgUIBQABLAAECgUIDAAJAAAAAA==.',Ru='Rubenalcaraz:BAAALAAECgEIAQAAAA==.',Ry='Ryuzengatsu:BAABLAAECoEtAAMIAAgIBhc0MgA9AgAIAAgIBhc0MgA9AgATAAcIUAq8QgAtAQAAAA==.',Sa='Sacervida:BAAALAADCgQIBgAAAA==.Sagiel:BAAALAADCgYIDAAAAA==.Saidra:BAABLAAECoEkAAIHAAgIFBlsUQDsAQAHAAgIFBlsUQDsAQAAAA==.Sanchuck:BAABLAAECoEcAAMTAAcISiKNDQCzAgATAAcIqiGNDQCzAgAIAAcIjR1LMABGAgAAAA==.Sanki:BAAALAAECgYICwAAAA==.Saonji:BAAALAAECgEIAQAAAA==.Satsujinpala:BAAALAADCggICAABLAAFFAIIAgAJAAAAAA==.Saved:BAAALAAECgcIEwAAAA==.',Se='Senka:BAAALAADCggIDAAAAA==.Serga:BAAALAADCgIIAgAAAA==.Seys:BAAALAAECgYIEAAAAA==.',Sh='Shadownaxan:BAAALAAECgMIBQAAAA==.Shadøwheart:BAAALAAECgYIDAAAAA==.Shamalarion:BAAALAAECgYIDgAAAA==.Shaoflight:BAAALAADCgEIAQAAAA==.Sharmei:BAABLAAECoEnAAIQAAcITBlwRQD2AQAQAAcITBlwRQD2AQABLAAECggIJAAFAMgZAA==.Shelyss:BAAALAAECgMIAwAAAA==.Shibalva:BAAALAAECgQICQAAAA==.Shisherino:BAAALAAECgcIEwAAAA==.Shonya:BAAALAAECgMIAwAAAA==.Shosimura:BAAALAADCgYIBgAAAA==.',Si='Siette:BAAALAADCggICAAAAA==.Sinlactosa:BAAALAAECgMIAwAAAA==.',Sl='Sloan:BAAALAADCgIIAgAAAA==.',So='Sombri:BAABLAAECoEWAAIOAAYITxXWSwBkAQAOAAYITxXWSwBkAQAAAA==.Souruita:BAABLAAECoEVAAMgAAYI4hPNoQCFAQAgAAYIKBPNoQCFAQAeAAUI7QkjNgD8AAAAAA==.',Sp='Spyrobuya:BAABLAAECoEVAAQhAAYIzBR3CgCIAQAhAAYIRhN3CgCIAQAiAAMIvB7HIwAIAQAjAAMI4xDFSwCwAAAAAA==.',Ss='Ssauron:BAABLAAECoEYAAMPAAcI3xFxSwAcAQAPAAYIlQtxSwAcAQAQAAUIfBEKkAAbAQAAAA==.',St='Stolas:BAAALAAECgYIDwAAAA==.Stormwing:BAAALAADCggIDQAAAA==.',Su='Subtlehunt:BAAALAADCgYICwAAAA==.Surgoncin:BAAALAAECgYIDgAAAA==.Suyou:BAAALAADCgUIDAAAAA==.',Sv='Svalæ:BAAALAAECggIBwAAAA==.',Sy='Syldavya:BAAALAADCgUIBQAAAA==.',['Sê']='Sêvïs:BAAALAADCgYIBgAAAA==.',['Sö']='Sölar:BAAALAAECgUICQAAAA==.',['Sü']='Süso:BAAALAADCggIFAAAAA==.',['Sÿ']='Sÿrö:BAABLAAECoEVAAIgAAYI6g08wQBTAQAgAAYI6g08wQBTAQAAAA==.',Ta='Taese:BAAALAADCgcIDAAAAA==.Tailong:BAAALAADCgIIAgABLAAECgYIDgAJAAAAAA==.Talions:BAAALAAECgIIBAAAAA==.Tancos:BAAALAAECgYICAAAAA==.Targaryel:BAAALAAECgYIBgAAAA==.Tarkan:BAAALAADCgcIDQAAAA==.',Te='Tecuroduro:BAAALAADCggIGAAAAA==.Tecz:BAAALAAECgIIAgAAAA==.Tedmaki:BAAALAADCggIEAAAAA==.Temaar:BAAALAADCggIEAABLAAFFAIIAgAJAAAAAA==.Temu:BAABLAAECoEaAAIYAAgIXgvyTwCcAQAYAAgIXgvyTwCcAQAAAA==.Temyble:BAAALAAECgYIBwAAAA==.Tepegoduro:BAAALAAECgUICQAAAA==.Tevildk:BAAALAAECgYIBgAAAA==.',Th='Thanguita:BAAALAADCgcIBwAAAA==.Thannatito:BAAALAAECgMIAwAAAA==.Tharalyn:BAAALAAECgYIDQAAAA==.Thau:BAABLAAFFIEGAAISAAIIfA3mJACQAAASAAIIfA3mJACQAAAAAA==.Thedárk:BAAALAAECgUIBwAAAA==.Theosham:BAAALAAFFAMIAwABLAAFFAIIBgAPAGwlAA==.Theowar:BAACLAAFFIEGAAIPAAIIbCWOBADPAAAPAAIIbCWOBADPAAAsAAQKgSYAAg8ACAgRJroAAHsDAA8ACAgRJroAAHsDAAAA.Thorduil:BAAALAADCggIEAAAAA==.Thranos:BAAALAAECgcIBgAAAA==.',Ti='Titö:BAAALAAECgcIDgAAAA==.',Tm='Tmiroitecuro:BAAALAAECgIIAgAAAA==.',To='Tolizs:BAAALAAECgYICAAAAA==.Tololoco:BAACLAAFFIEKAAIIAAQIjxJ/DgAQAQAIAAQIjxJ/DgAQAQAsAAQKgSwAAggACAgEIq8PABMDAAgACAgEIq8PABMDAAAA.Tonyton:BAAALAAECgMIAwAAAA==.Toretus:BAAALAAECgcIEAAAAA==.Totewydd:BAAALAADCgUIBQAAAA==.',Tp='Tpartoos:BAAALAAECgUIBwAAAA==.',Tr='Troyalx:BAAALAADCgcIDQAAAA==.Troywolf:BAAALAAECgEIAQAAAA==.Tröyalx:BAAALAADCgcIDgAAAA==.',Ts='Tsukiakari:BAABLAAECoEWAAINAAgIcQ/7bgBxAQANAAgIcQ/7bgBxAQAAAA==.',Tu='Turbospeed:BAAALAADCgMIAwABLAAECggIHQAcAMgfAA==.',Ty='Tyelka:BAAALAAECgQICQAAAA==.Tykong:BAAALAADCgMIAgAAAA==.',Uc='Uchiharuben:BAAALAAECggIBQAAAA==.',Un='Unneot:BAAALAAECgQIBgAAAA==.',Va='Vaalum:BAAALAADCgYIBgABLAAECgQIBwAJAAAAAA==.Vaelia:BAAALAADCggIDwAAAA==.Valdi:BAAALAADCgYIBwAAAA==.Valeför:BAAALAADCgIIAgABLAAFFAMIBwAIAE8bAA==.Valenntina:BAAALAADCggICQAAAA==.Valenzuela:BAAALAAECgYIDgAAAA==.Validus:BAAALAADCgcIBwAAAA==.Vanhelzin:BAAALAAECgUIBQAAAA==.Vascoshot:BAAALAADCggICwAAAA==.',Ve='Veestâ:BAABLAAECoEcAAISAAYIug5sYQAzAQASAAYIug5sYQAzAQAAAA==.Vermithorr:BAAALAADCgcICQAAAA==.',Vo='Voidk:BAAALAAECgEIAQAAAA==.Vozen:BAAALAADCgEIAQAAAA==.',Wa='Waffle:BAAALAAECgYICQAAAA==.Wartiorg:BAAALAADCgMIAwAAAA==.Wasakass:BAAALAADCgYIBgAAAA==.Waterandice:BAABLAAECoEXAAIVAAYIvhGDEwBjAQAVAAYIvhGDEwBjAQAAAA==.',We='Welmaster:BAAALAADCggIEgAAAA==.',Wh='Whitë:BAAALAAECgcIDAAAAA==.',Wi='Wilkas:BAAALAADCgcIDgAAAA==.Willywallace:BAAALAADCgMIBgAAAA==.',Wo='Wolfk:BAAALAADCggIDgABLAAECgcIJgAEAMsZAA==.Woolffy:BAABLAAECoEWAAIOAAYITAMYawDEAAAOAAYITAMYawDEAAAAAA==.',Xa='Xarothi:BAAALAADCgMIAwAAAA==.',Xe='Xenen:BAAALAADCgYICAAAAA==.Xephon:BAAALAAECgYIBwAAAA==.',Xh='Xhormander:BAAALAAECgYIBwAAAA==.',Xi='Xiamana:BAAALAAECgcICAAAAA==.',Xo='Xorian:BAAALAADCgUIBQAAAA==.',Xu='Xulian:BAAALAAECgUIDAAAAA==.',['Xû']='Xûrû:BAAALAAECgYIBgAAAA==.',Ya='Yaiser:BAAALAAECgcIDQAAAA==.Yamikaede:BAAALAADCgEIAQAAAA==.Yaraa:BAAALAADCggICAABLAAFFAIIAgAJAAAAAA==.Yarthasy:BAAALAAECgIIAwAAAA==.Yasariel:BAABLAAECoEqAAIEAAgI2CJsEwAUAwAEAAgI2CJsEwAUAwAAAA==.Yasho:BAACLAAFFIEGAAIGAAII/g5QHwCBAAAGAAII/g5QHwCBAAAsAAQKgQ0AAwYABwgVH6koABcCAAYABwjTGakoABcCAAcABQjiIUNQAO8BAAAA.Yayita:BAAALAAECgMIBAAAAA==.',Yn='Ynarion:BAABLAAECoEoAAIjAAgIDRAdKAC8AQAjAAgIDRAdKAC8AQAAAA==.',Yo='Yolotl:BAAALAADCgcIBwAAAA==.',Ys='Yseraa:BAABLAAECoEiAAIjAAgIPQ6hJQDPAQAjAAgIPQ6hJQDPAQAAAA==.',Yu='Yuray:BAAALAAECgMIBQAAAA==.',Za='Zagan:BAAALAADCggICAABLAAFFAMIBwAIAE8bAA==.Zahide:BAAALAAECgIIAgAAAA==.Zarpitajapan:BAAALAADCgcIBwAAAA==.',Ze='Zeratul:BAAALAADCgIIAgAAAA==.',Zh='Zhyon:BAAALAADCgMIAwAAAA==.',Zo='Zoros:BAABLAAECoEgAAIUAAcI1RmpSQAKAgAUAAcI1RmpSQAKAgAAAA==.',Zu='Zulamapi:BAAALAADCgEIAQAAAA==.Zulariv:BAAALAADCggICAAAAA==.Zularlx:BAAALAAECgQIBwAAAA==.Zularv:BAABLAAECoEhAAIkAAcIqx5zCgAHAgAkAAcIqx5zCgAHAgAAAA==.Zurimin:BAABLAAECoEWAAIHAAYIKhhaegCJAQAHAAYIKhhaegCJAQAAAA==.',['Âm']='Âmador:BAABLAAECoEaAAIHAAcIfRIncwCZAQAHAAcIfRIncwCZAQAAAA==.',['Âz']='Âzuli:BAABLAAECoEeAAINAAgI1RN2UwC7AQANAAgI1RN2UwC7AQAAAA==.',['Är']='Äräfin:BAABLAAECoEaAAIkAAYI7RMHFABXAQAkAAYI7RMHFABXAQAAAA==.',['Ås']='Åstaroth:BAAALAAECgQIBQAAAA==.',['Ël']='Ëlünë:BAABLAAECoEXAAIBAAcIbR+8LQDfAQABAAcIbR+8LQDfAQAAAA==.',['Ïr']='Ïrma:BAAALAADCgIIAgAAAA==.',['Ñâ']='Ñâmia:BAABLAAECoEjAAIfAAgIlxr2PgA9AgAfAAgIlxr2PgA9AgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end