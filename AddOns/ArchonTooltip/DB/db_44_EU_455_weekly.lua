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
 local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Shaman-Elemental','Paladin-Protection','Mage-Arcane','Rogue-Assassination','Druid-Guardian','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Rogue-Subtlety','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Shaman-Restoration','Warrior-Protection','Warrior-Fury','Priest-Shadow','Mage-Frost','Warlock-Destruction','Monk-Mistweaver','Paladin-Holy','Rogue-Outlaw','Evoker-Preservation','Evoker-Devastation','Monk-Windwalker','Monk-Brewmaster','Warrior-Arms','Shaman-Enhancement','Evoker-Augmentation','Priest-Holy',}; local provider = {region='EU',realm='Nethersturm',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Achéron:BAAALAAECgMIAwAAAA==.Acielle:BAABLAAECoEcAAMBAAcIGh4scQC3AQABAAcIGh4scQC3AQACAAIIZA3uUgBFAAAAAA==.',Ad='Adanaran:BAAALAAECgYIBgABLAAECgcICgADAAAAAA==.',Ai='Aigil:BAABLAAECoEUAAIEAAcIzBvzOwAvAgAEAAcIzBvzOwAvAgAAAA==.Ailani:BAAALAAECggIEAAAAA==.',Ak='Akiyo:BAAALAAECgIIAgAAAA==.Akra:BAAALAADCggIEAAAAA==.',Al='Alery:BAABLAAECoEdAAIEAAgIQR7BJgCDAgAEAAgIQR7BJgCDAgAAAA==.Alira:BAAALAAECggICAAAAA==.Alizeá:BAABLAAECoEWAAMFAAcIyyG5EgCjAgAFAAcIyyG5EgCjAgAGAAUIZQpOZwDTAAAAAA==.Alleriaa:BAAALAAECggIDwAAAA==.',Am='Amadea:BAAALAADCgcIEwAAAA==.Amary:BAABLAAECoEZAAMGAAcIyh9RFwCBAgAGAAcIyh9RFwCBAgAFAAEI/xI9ugAwAAAAAA==.Amatukani:BAAALAADCggICQAAAA==.',An='Anidera:BAAALAAECgYIEQAAAA==.Annuxia:BAAALAAECgQICAAAAA==.Anoe:BAAALAAECgYIBgAAAA==.',Ar='Aramòr:BAAALAADCggICQABLAAECgQICAADAAAAAA==.Aramór:BAAALAAECgQICAAAAA==.Aramôr:BAAALAAECgYIBgABLAAECgQICAADAAAAAA==.Ardeny:BAAALAAECgYIDQAAAA==.Arianeira:BAABLAAECoEYAAIHAAgIfQLSigC1AAAHAAgIfQLSigC1AAAAAA==.Arinja:BAAALAAECgYIDwAAAA==.Arrexxin:BAAALAADCgcIBwAAAA==.Arthag:BAAALAAECgUIBgAAAA==.',As='Asca:BAAALAADCggIDwAAAA==.Ascador:BAAALAAECgYICQAAAA==.Ascari:BAABLAAECoEaAAIIAAcIahX9MwAvAQAIAAcIahX9MwAvAQAAAA==.Asgorath:BAAALAAECgMIBQABLAAECgYIDAADAAAAAA==.Astralina:BAABLAAECoEUAAMFAAcI+R8vGAB3AgAFAAcI+R8vGAB3AgAGAAMIyBMAAAAAAAAAAA==.',At='Ataxa:BAAALAADCgQIAwAAAA==.Ataxie:BAAALAAECgYIEAAAAA==.Atlandegoloz:BAABLAAECoEgAAIJAAcIxgSboQAJAQAJAAcIxgSboQAJAQAAAA==.',Ax='Axtolotllol:BAAALAADCgYIBgABLAAECgMICQADAAAAAA==.',Ay='Ayasa:BAAALAADCgcIBwAAAA==.',Az='Azelîa:BAAALAAECgIIAgAAAA==.Aziron:BAABLAAECoEfAAIKAAcIcBI4JgDXAQAKAAcIcBI4JgDXAQAAAA==.',['Aý']='Aýahuasca:BAACLAAFFIEFAAILAAIIORy/AgCpAAALAAIIORy/AgCpAAAsAAQKgS4AAgsACAjpIOgDAM8CAAsACAjpIOgDAM8CAAAA.',Ba='Baasshunter:BAAALAADCgYIBgAAAA==.Balodir:BAAALAAECgMIAwAAAA==.Bastos:BAABLAAECoEZAAMMAAcIFgkcSgAiAQAMAAcICwccSgAiAQANAAMILQwqJwCUAAAAAA==.Baturios:BAAALAADCgcIBwABLAAECgcIHQAMAF0YAA==.Baumfloh:BAAALAAECgYIDQAAAA==.',Be='Beater:BAAALAAECgIIAwABLAAFFAMICQAOAFcYAA==.Belebend:BAAALAAECgYIDAAAAA==.Belicitas:BAAALAAECgYIAgAAAA==.',Bi='Bigpaws:BAAALAAECgYIBgAAAA==.Biérkules:BAAALAADCgYICQAAAA==.',Bj='Björnogan:BAABLAAECoEjAAMPAAcI9gwXIABlAQAPAAcIeQsXIABlAQAKAAYIhAthQAA6AQAAAA==.',Bl='Blobtop:BAAALAAECgIIAgAAAA==.Bloodshield:BAABLAAECoEhAAMQAAgIexbIDwBFAgAQAAgIexbIDwBFAgARAAIISgc0NwFfAAAAAA==.',Bo='Bode:BAAALAADCgMIBAABLAAECgQIEAADAAAAAA==.Bombi:BAAALAAECgYIDQAAAA==.Borouk:BAAALAADCgEIAQAAAA==.',Br='Branken:BAABLAAECoEaAAISAAcIfhNdIABCAQASAAcIfhNdIABCAQAAAA==.Brehm:BAAALAAECgYICQAAAA==.Brewio:BAAALAADCgUIBQAAAA==.Brownielol:BAAALAAECgEIAQABLAAECgMICQADAAAAAA==.Brummelbaer:BAAALAADCgYIBgAAAA==.',Bu='Bubuhase:BAAALAADCgcIBwAAAA==.Bumî:BAABLAAECoEiAAIHAAgI7iJxDQASAwAHAAgI7iJxDQASAwAAAA==.Bumîali:BAAALAAECgMIAwABLAAECggIIgAHAO4iAA==.Buuhhaua:BAAALAADCgcIBwAAAA==.',['Bê']='Bêrrók:BAAALAAECggIAQAAAA==.',Ca='Caindral:BAAALAAECgcICQAAAA==.Cakelol:BAAALAADCgIIAgABLAAECgMICQADAAAAAA==.Calistros:BAAALAAECgMIDAAAAA==.Calurosa:BAAALAAECggIEAAAAA==.Cannibale:BAAALAAECgUIDgAAAA==.Caprícorn:BAAALAADCgcIDgAAAA==.Capubell:BAAALAAECgYIBgAAAA==.Carishia:BAAALAAECgYICwABLAAECgcIGAATAG8dAA==.Carstelia:BAAALAAECgEIAQABLAAECgMIDAADAAAAAA==.Cash:BAAALAADCgUIBQAAAA==.Castelia:BAAALAAECgIIAgABLAAECgMIDAADAAAAAA==.',Ce='Cerdox:BAABLAAECoEUAAIHAAcIGhr4NAALAgAHAAcIGhr4NAALAgAAAA==.',Ch='Changlol:BAAALAADCgMIAwABLAAECgMICQADAAAAAA==.Chicrex:BAAALAAECgMIBgAAAA==.',Cl='Clericus:BAAALAAECgcIDAAAAA==.',Co='Colada:BAAALAAECggICwAAAA==.Cordulagrün:BAAALAADCgYIBgABLAAECggICgADAAAAAA==.Coronalol:BAAALAAECgEIAQABLAAECgMICQADAAAAAA==.',Cp='Cptgerlaf:BAAALAAECggICAAAAA==.',Cr='Crobate:BAABLAAECoEYAAMUAAcIOBvIGwAfAgAUAAYIbh/IGwAfAgAVAAMI2REAAAAAAAAAAA==.',Cu='Currysbabe:BAAALAAECgYIEwAAAA==.',Da='Daemonbane:BAAALAAECgYICwABLAAFFAIIAgADAAAAAA==.Dafrá:BAAALAAECgYIEAAAAA==.Dangerest:BAAALAAECgUICgABLAAECggIGQATAJ0FAA==.Dargon:BAABLAAECoEZAAIUAAcISx/FEgB0AgAUAAcISx/FEgB0AgAAAA==.Darteon:BAAALAAFFAIIAgAAAA==.',De='Death:BAACLAAFFIENAAIBAAUI4R+aBgDjAQABAAUI4R+aBgDjAQAsAAQKgSkAAgEACAg2JiIDAHcDAAEACAg2JiIDAHcDAAAA.Deatpool:BAAALAAECggIBwAAAA==.Debbu:BAAALAAECgYIEAAAAA==.Dendarah:BAAALAAECgQIBAAAAA==.Denden:BAAALAAECgYIEAAAAA==.Dennyo:BAAALAADCggIDwAAAA==.Dennyyo:BAAALAAECgIIBQAAAA==.Destlight:BAAALAADCggIFgAAAA==.Destrower:BAACLAAFFIEKAAIFAAII7RZ3HACSAAAFAAII7RZ3HACSAAAsAAQKgR0AAgUABgg7IOomAB8CAAUABgg7IOomAB8CAAAA.Destsilk:BAABLAAECoEaAAIWAAcIhxfcLAAAAgAWAAcIhxfcLAAAAgAAAA==.Devil:BAAALAADCggICAAAAA==.',Di='Diene:BAAALAADCgcICgAAAA==.',Dj='Djangzu:BAAALAAECgEIAQAAAA==.Djaydi:BAAALAADCgUIBQAAAA==.',Do='Dommie:BAAALAAECgQICQAAAA==.Doorixdru:BAAALAADCgUIAgAAAA==.Dots:BAAALAAECgYIBgAAAA==.',Dr='Dracthyrus:BAAALAAECgMIBQAAAA==.Draiden:BAABLAAECoEZAAIWAAgI3BeMKwAIAgAWAAgI3BeMKwAIAgAAAA==.Drinsteffus:BAAALAAECgIIAgAAAA==.Dropschleger:BAAALAAECgIIAgAAAA==.Druidora:BAAALAADCgcIBwABLAAECgcIGAATAG8dAA==.',Du='Dudolino:BAABLAAECoEcAAIFAAcI8RjMMADuAQAFAAcI8RjMMADuAQAAAA==.Dudri:BAAALAADCgEIAQAAAA==.Duint:BAAALAAECgYIBgAAAA==.',Dw='Dwaalina:BAAALAADCggIGAAAAA==.',Dy='Dylies:BAABLAAECoEaAAIMAAcI/Qm5RgAxAQAMAAcI/Qm5RgAxAQAAAA==.Dywana:BAABLAAECoEZAAIEAAcI2R0EOAA9AgAEAAcI2R0EOAA9AgAAAA==.',['Dé']='Déyna:BAAALAAECgYICQAAAA==.',['Dô']='Dôze:BAABLAAECoEcAAIRAAcIxBTGfgDEAQARAAcIxBTGfgDEAQAAAA==.',Ed='Edi:BAAALAAECgIIAgAAAA==.',Eh='Ehlo:BAAALAAECgIIAgAAAA==.',El='Elartus:BAABLAAECoEYAAITAAcIbx3+KwA/AgATAAcIbx3+KwA/AgAAAA==.Eliondra:BAABLAAECoEmAAIXAAgIbSE7CgDdAgAXAAgIbSE7CgDdAgAAAA==.Eliyah:BAAALAADCgUIBQABLAADCgcIDgADAAAAAA==.Elnoble:BAAALAAECggICgAAAA==.Elsu:BAAALAAECggICAAAAA==.',Em='Emmó:BAAALAAECgEIAQABLAAECgcIGQAFAG0bAA==.Empar:BAABLAAECoEeAAIRAAcIOCI/KgCjAgARAAcIOCI/KgCjAgAAAA==.',En='Ensiâ:BAAALAADCgQIBAABLAAECgcIGAATAG8dAA==.Entanôtwo:BAAALAAECgIIBAAAAA==.Entendh:BAAALAAECgQIBQAAAA==.Entetot:BAAALAADCgUIBQAAAA==.Entevanquack:BAABLAAECoEgAAIVAAcIMBu0OgAYAgAVAAcIMBu0OgAYAgAAAA==.Entewl:BAAALAAECgUICQAAAA==.',Er='Erdenbrecher:BAAALAADCgYICQAAAA==.Erdenherz:BAAALAADCggIDwAAAA==.',Eu='Eula:BAAALAAECgUICAAAAA==.',Ex='Exbruno:BAABLAAECoEZAAIFAAcIbRu1KAAVAgAFAAcIbRu1KAAVAgAAAA==.Exorcizamús:BAAALAADCgcIDQAAAA==.',Fa='Fausi:BAAALAADCgQIBgABLAAECgMICQADAAAAAA==.',Fe='Ferialana:BAAALAADCgEIAQAAAA==.Ferleinix:BAAALAADCgcIGAAAAA==.Feuersturm:BAAALAADCgUIBAAAAA==.',Fi='Finishyou:BAAALAADCggICAAAAA==.',Fo='Forti:BAAALAAECgUIDgAAAA==.Foxtra:BAAALAAECgQIBAAAAA==.',Fr='Frostcrex:BAAALAAFFAIIBAAAAA==.Frostkîller:BAAALAADCgYICgAAAA==.',Fu='Fuchsteufel:BAAALAAECgQICAAAAA==.Fuchur:BAAALAAECgcICQAAAA==.',['Fû']='Fûchur:BAAALAAECggIBgAAAA==.',Ge='Gelgaz:BAAALAADCggIEAAAAA==.Geojin:BAAALAAECgYIBQAAAA==.Geran:BAAALAAECgMICAAAAA==.',Gi='Gichtknochen:BAAALAAECgcIEwAAAA==.Gidhora:BAAALAADCgYIBgAAAA==.Ginette:BAAALAAECgcIDgAAAA==.',Go='Gorshok:BAAALAAECgYIBwAAAA==.',Gr='Gram:BAABLAAECoEjAAMNAAcIMg33DwCUAQANAAcI+gv3DwCUAQAYAAcILwvabgBzAQAAAA==.Grarrg:BAAALAAECgcIDwAAAA==.Greenmile:BAAALAADCggIDgAAAA==.Gripexx:BAABLAAECoEiAAIZAAYIPQ5WKwAQAQAZAAYIPQ5WKwAQAQAAAA==.Griswold:BAABLAAECoEaAAIaAAcIyxZiLgCGAQAaAAcIyxZiLgCGAQAAAA==.Grodin:BAAALAAECgMIBAAAAA==.Grodon:BAAALAAECgUIAwAAAA==.Grokdrek:BAAALAADCggICQAAAA==.Grumbledour:BAABLAAECoEjAAIXAAgI6xEsKQC8AQAXAAgI6xEsKQC8AQAAAA==.Gróm:BAAALAADCgYIBgAAAA==.',Gu='Gutesdmg:BAAALAAECgYIBgAAAA==.',Gw='Gwennefer:BAAALAAECgQICQAAAA==.',Gy='Gyniverde:BAAALAAECggICAAAAA==.',['Gã']='Gãntu:BAAALAADCggIJwAAAA==.',['Gö']='Göks:BAAALAAECgYIDQAAAA==.',['Gü']='Gümli:BAAALAAECgEIAQAAAA==.',Ha='Habilol:BAABLAAECoEjAAMOAAgIFh5+KwCdAgAOAAgIFh5+KwCdAgAIAAcI2BZMHgDNAQAAAA==.Handara:BAAALAADCggIFAABLAAECggIFgAOAJsHAA==.Haribo:BAABLAAECoEpAAMOAAgI1R6mJgCyAgAOAAgI1R6mJgCyAgAaAAIIMgkHYABZAAAAAA==.',He='Hendt:BAAALAAECgEIAQABLAAECggIIgAHAO4iAA==.',Hi='Himiko:BAABLAAECoEUAAIbAAYInSLiBABmAgAbAAYInSLiBABmAgAAAA==.',Ho='Hodoor:BAAALAADCgEIAQAAAA==.Holet:BAAALAADCggIHAAAAA==.Holycrex:BAAALAADCgIIAgABLAAECgMIBgADAAAAAA==.',Hu='Huhn:BAAALAADCggICQAAAA==.Hullá:BAAALAAECgcICQAAAA==.',['Hé']='Héllhound:BAAALAADCggIEAABLAAECggIFgAOAJsHAA==.',Ig='Igris:BAAALAAECgYICgAAAA==.',Il='Ilian:BAACLAAFFIEOAAQYAAUIEQ1QEwApAQAYAAQI/gtQEwApAQANAAEIXBHNBABaAAAMAAEIXArTIwBMAAAsAAQKgSEAAxgACAhKH0cVAOwCABgACAhKH0cVAOwCAAwAAQgjEnuIADYAAAAA.Ilnea:BAAALAAECgIIAgAAAA==.Ilîan:BAAALAAECgIIAgAAAA==.',Im='Image:BAAALAADCgcIBwAAAA==.Imposterkeck:BAACLAAFFIEGAAIRAAIIahcWOQCaAAARAAIIahcWOQCaAAAsAAQKgSIAAhEABghtGd+CALwBABEABghtGd+CALwBAAEsAAUUAwgJAA4AVxgA.',In='Inastrasza:BAAALAADCggIGAAAAA==.Inazuma:BAAALAAECgcIDQAAAA==.Insata:BAAALAAECgIIAgAAAA==.',Io='Ioné:BAAALAAECgUIDAAAAA==.',Is='Isezwerche:BAAALAADCggICAAAAA==.Isiltur:BAAALAADCgcIBwAAAA==.Isternochda:BAAALAADCgcIBwABLAAECgYIDQADAAAAAA==.',Ja='Jadedrache:BAAALAADCggIDwAAAA==.',Je='Jente:BAAALAADCgIIAgAAAA==.',Jh='Jhuugrym:BAAALAAECgIIAgABLAAECgUIDgADAAAAAA==.',Ji='Jimmyoyang:BAAALAAECgMIAwABLAAECgcIFAAFAPkfAA==.',Jo='Jokerdrache:BAAALAAECgEIAQAAAA==.Jorom:BAAALAADCggICAAAAA==.',Ju='Justdoit:BAAALAAECgIIBAAAAA==.',Ka='Kadiana:BAABLAAFFIEKAAIFAAQI3Q89CAAgAQAFAAQI3Q89CAAgAQAAAA==.Karnic:BAAALAADCgcIBwAAAA==.Kayajina:BAAALAADCgYICAAAAA==.',Ke='Kendár:BAABLAAECoEmAAIGAAcI5h7sIAAvAgAGAAcI5h7sIAAvAgAAAA==.Kerales:BAAALAAECgIIBAABLAAECgcIGQAFAG0bAA==.',Kh='Khazir:BAABLAAECoElAAIcAAcINyHbBwCXAgAcAAcINyHbBwCXAgAAAA==.',Ko='Koriander:BAAALAAECgYIEAAAAA==.',Kr='Krids:BAAALAAECgQIBgAAAA==.Krigsblut:BAAALAAECgUIBQAAAA==.',Ku='Kurdal:BAAALAAECgYIDwAAAA==.Kurgar:BAAALAADCggICQAAAA==.',Ky='Kyorãku:BAAALAADCggICAAAAA==.',['Kî']='Kîrîto:BAAALAAECgYICAAAAA==.Kîthana:BAAALAADCggICAAAAA==.',['Kö']='Königlooter:BAAALAADCgEIAQAAAA==.',La='Lacazadora:BAAALAAECggICgAAAA==.Laez:BAAALAADCgYIBgAAAA==.Laluzsolar:BAAALAAECgIIAgAAAA==.Langoras:BAAALAAECggICAAAAA==.Large:BAAALAAECgYIBgABLAAECgcIKAAdACshAA==.Layzem:BAAALAADCgQIBAAAAA==.',Le='Leanora:BAAALAAECgYIBwAAAA==.Lehuskyh:BAAALAADCgUIBQAAAA==.Leoras:BAAALAAECggICAAAAA==.Leuchtetatze:BAAALAAECgMIBQAAAA==.Lexe:BAAALAADCggICAAAAA==.Lexea:BAAALAADCgcIDwAAAA==.',Li='Lik:BAAALAAECgcIEwAAAA==.Lilithi:BAAALAAECgIIAgAAAA==.Lillandra:BAAALAADCgEIAQAAAA==.Lillebror:BAAALAADCggIHQAAAA==.Littletomtom:BAAALAAECgYIBgAAAA==.Lizcore:BAABLAAECoEeAAIEAAcINB6YMABZAgAEAAcINB6YMABZAgAAAA==.Lizentia:BAAALAAECgYICgAAAA==.',Lo='Lockmore:BAAALAAECgYICgAAAA==.Lonewolf:BAAALAAECgQIBwABLAAECggIFgAOAJsHAA==.Lorebear:BAAALAAECgEIAQAAAA==.Losdorea:BAAALAADCgcIBwABLAAECgQICAADAAAAAA==.',Lu='Lulâ:BAAALAADCggICgAAAA==.Lustiger:BAAALAADCggIDgAAAA==.Lutimarus:BAAALAAECgYIDAAAAA==.',Ly='Lycanto:BAAALAAECgMIBAAAAA==.Lyxie:BAAALAADCggIDwAAAA==.',['Lê']='Lêylia:BAAALAADCggICAAAAA==.',['Lí']='Límos:BAAALAADCggIHgAAAA==.',['Lî']='Lîllît:BAAALAAECgMICAAAAA==.',['Lû']='Lûmiel:BAAALAADCgYICAAAAA==.',Ma='Maarvxdh:BAAALAADCgUIAgAAAA==.Magnolie:BAABLAAECoEXAAIOAAcIiAgM5wD2AAAOAAcIiAgM5wD2AAAAAA==.Malena:BAAALAADCgYIBgAAAA==.Manadriel:BAAALAAECgYIBgAAAA==.Marsellus:BAAALAAECgYICAAAAA==.Martho:BAAALAADCgcIDgAAAA==.Maybach:BAAALAAECggICAAAAA==.',Mc='Mccevap:BAAALAADCggICAAAAA==.',Me='Meisterglanz:BAABLAAECoEYAAIMAAYIqx+kFwAeAgAMAAYIqx+kFwAeAgAAAA==.Melarath:BAABLAAECoEcAAIYAAcIUxY6RgDzAQAYAAcIUxY6RgDzAQAAAA==.',Mi='Mihodh:BAAALAADCggIDwAAAA==.Mindless:BAAALAADCggICAAAAA==.Miracuthor:BAAALAAECgYIBgAAAA==.',Mo='Mogdalock:BAAALAADCgcIDgAAAA==.Monstar:BAAALAAECgIIAgAAAA==.Moordredo:BAABLAAECoEoAAIBAAcIexerZgDOAQABAAcIexerZgDOAQAAAA==.Morphoiss:BAAALAAECggICAAAAA==.Moyramclion:BAAALAAECggICgAAAA==.',My='Mysteriös:BAAALAADCggICAAAAA==.',['Má']='Mártinlooter:BAAALAADCggIEgAAAA==.',['Mä']='Mädchen:BAABLAAECoEYAAMMAAgIHQ9oKwCkAQAMAAgIHQ9oKwCkAQAYAAEI9AVe4QAoAAAAAA==.',['Mé']='Mélinchen:BAAALAAECgYIDAAAAA==.Mése:BAABLAAECoEXAAIYAAYI7hl0VADAAQAYAAYI7hl0VADAAQAAAA==.',['Më']='Mëxx:BAAALAADCgQIBAABLAAECgcIHwATAEcVAA==.',['Mî']='Mîgo:BAAALAAECgYIDwAAAA==.',['Mù']='Mùradi:BAAALAADCgEIAQAAAA==.',Na='Nahimana:BAAALAAECgIIAgABLAAECgcIHAAIAEIhAA==.Nakiarà:BAAALAAECggIBwAAAA==.Naltrexiya:BAAALAAECgMIAwAAAA==.Nareth:BAABLAAECoEfAAIbAAgIXRtKBACCAgAbAAgIXRtKBACCAgAAAA==.Natesh:BAAALAADCggIHwAAAA==.Navar:BAACLAAFFIEGAAIFAAIITxCoJACFAAAFAAIITxCoJACFAAAsAAQKgS4AAwUACAhaHMkWAIICAAUACAhaHMkWAIICAAYABwjsEXU/AIYBAAAA.Navur:BAAALAAECgMIBQAAAA==.',Ne='Necherophes:BAAALAADCgcIDgABLAAECgMIBgADAAAAAA==.Neider:BAABLAAECoEVAAIVAAYI3AyddwBXAQAVAAYI3AyddwBXAQAAAA==.Neschlim:BAAALAAECggICAAAAA==.Netas:BAABLAAECoEYAAIQAAcIXg1AHgCwAQAQAAcIXg1AHgCwAQAAAA==.',Ni='Nibler:BAAALAADCggIEAAAAA==.Niko:BAABLAAECoEbAAIBAAYIlQ3LpgBMAQABAAYIlQ3LpgBMAQAAAA==.Nimmduhabich:BAAALAAECgYIBgABLAAECgYIDQADAAAAAA==.Nimrohd:BAABLAAECoEdAAIMAAYIRBr1IwDMAQAMAAYIRBr1IwDMAQAAAA==.Nirmal:BAAALAADCggICgAAAA==.',No='Nomzx:BAAALAAECggIDgAAAA==.Noobsaimop:BAAALAADCggICAAAAA==.Noonia:BAABLAAECoEVAAIRAAcIxAhgEAGxAAARAAcIxAhgEAGxAAAAAA==.Norr:BAAALAADCgEIAQAAAA==.',Ny='Nymira:BAAALAADCggICAABLAAECggIHwAbAF0bAA==.Nyríe:BAAALAADCggICAABLAAECggIIwANADINAA==.',['Nî']='Nîcôn:BAAALAADCgEIAQABLAAECggIHwAHALEXAA==.',['Nü']='Nüwú:BAAALAAECgIIAgAAAA==.',Ok='Okami:BAAALAAECgYICgAAAA==.Okeanos:BAABLAAECoEfAAITAAcIRxVsXQChAQATAAcIRxVsXQChAQAAAA==.',Oo='Oodelally:BAAALAAECgIIAgAAAA==.',Ov='Ovinax:BAAALAADCgcIDQAAAA==.',['Oâ']='Oâsis:BAAALAAECgYIEAAAAA==.',Pa='Paenumbra:BAABLAAECoEaAAIRAAcIdAiJ7QADAQARAAcIdAiJ7QADAQAAAA==.Palacios:BAAALAADCggIDQAAAA==.Pandacetamol:BAACLAAFFIEGAAIZAAIIMhc0CwClAAAZAAIIMhc0CwClAAAsAAQKgSwABBkABwgHFnQZAMIBABkABwgHFnQZAMIBAB4ABwhKE+UlAJ4BAB8ABAhBEJw0AJ8AAAAA.Pandôrrá:BAAALAADCgcIDgABLAAECgUICgADAAAAAA==.Paro:BAABLAAECoEUAAIQAAcIvxxbEQAxAgAQAAcIvxxbEQAxAgAAAA==.Patches:BAABLAAECoEXAAITAAYIMhRtfwBJAQATAAYIMhRtfwBJAQAAAA==.',Pe='Peaches:BAAALAADCgYIBgAAAA==.',Ph='Phôênix:BAAALAAECgMIBAAAAA==.',Pi='Pippilotta:BAAALAADCgYIBgAAAA==.Pirak:BAAALAAECgUICgAAAA==.',Po='Ponylol:BAAALAAECgIIBAABLAAECgMICQADAAAAAA==.',Pu='Puddinglol:BAAALAAECgMICQAAAA==.',Py='Pyon:BAABLAAECoEXAAIEAAcIUxdhlQBTAQAEAAcIUxdhlQBTAQAAAA==.Pype:BAAALAADCgcIBwAAAA==.',['Pâ']='Pândemonium:BAAALAAECgYIDAAAAA==.',['Pê']='Pêanutbutter:BAAALAAECgMICAABLAAECgUICgADAAAAAA==.',Qu='Questlove:BAAALAADCgcIDAABLAAECggIFQAFAF8XAA==.Qulsic:BAABLAAECoEdAAIMAAcIXRgxGQASAgAMAAcIXRgxGQASAgAAAA==.',Ra='Rahnen:BAAALAAECgYIBgAAAA==.Rainyday:BAAALAAECgcICAAAAA==.Rakójenkins:BAAALAADCggICAABLAAECggIIQARADkYAA==.Raski:BAABLAAECoEWAAITAAYI3xKWgABGAQATAAYI3xKWgABGAQAAAA==.Rayadz:BAAALAADCggIFgAAAA==.',Re='Rekhodiah:BAABLAAECoEVAAIFAAYI7h+pJgAgAgAFAAYI7h+pJgAgAgAAAA==.Rengan:BAABLAAECoEZAAMQAAYIURZbKABhAQARAAYIBBKMtwBiAQAQAAUITRhbKABhAQAAAA==.',Ro='Rollga:BAAALAAECgYICwAAAA==.Roobird:BAAALAAECggICAAAAA==.Rosalee:BAABLAAECoEkAAIZAAcI/gsRJwA2AQAZAAcI/gsRJwA2AQAAAA==.Rotdrache:BAAALAADCgIIAgAAAA==.Rotzgöre:BAAALAAECgEIAQAAAA==.',Ru='Rushhour:BAACLAAFFIEJAAIgAAQI4Q2HAABEAQAgAAQI4Q2HAABEAQAsAAQKgSUAAiAACAgZJfAAAF4DACAACAgZJfAAAF4DAAEsAAUUBQgNAAEA4R8A.',Ry='Rye:BAAALAAECgYICAAAAA==.Rylena:BAAALAAECggICAAAAA==.Rylona:BAAALAAECgcICgAAAA==.Ryôko:BAAALAADCgcIFAABLAAFFAIIBgAgAMkbAA==.',['Ré']='Réngàn:BAAALAADCgcICAAAAA==.',['Rø']='Røckstars:BAAALAAECgEIAQABLAAECggIIgAHAO4iAA==.',Sa='Sacurafee:BAAALAADCgQIAwAAAA==.Sadoriâ:BAAALAADCggIDwAAAA==.Saelly:BAAALAAECggICAAAAA==.Sahtra:BAAALAADCggIEAAAAA==.Sajurie:BAABLAAECoEdAAIEAAcIjRZuXwDHAQAEAAcIjRZuXwDHAQAAAA==.Sansa:BAAALAADCggIDwAAAA==.Saoirsé:BAABLAAECoEWAAIEAAcIFyQtKAB9AgAEAAcIFyQtKAB9AgAAAA==.Sarki:BAAALAADCgQIBAAAAA==.Saronia:BAAALAADCgcICgAAAA==.',Sc='Schandris:BAAALAADCggICwAAAA==.Schandru:BAABLAAECoEVAAQOAAcIrSAzLACaAgAOAAcIrSAzLACaAgAIAAEIExacWwBBAAAaAAEI5QOjagAkAAAAAA==.Schelli:BAABLAAECoEWAAIYAAcIog9RYACcAQAYAAcIog9RYACcAQAAAA==.Schmierfuß:BAAALAADCgYICQAAAA==.',Se='Second:BAAALAADCggIBgAAAA==.Serraria:BAAALAADCgcIDAABLAAECgYIBwADAAAAAA==.Sevara:BAAALAAECgcIDQAAAA==.',Sh='Shaimji:BAAALAADCgIIAgAAAA==.Shanteya:BAAALAAECgQICAAAAA==.Sharkzqt:BAAALAADCgEIAQAAAA==.Shieldlady:BAAALAAECgIIAgAAAA==.Shisuna:BAAALAADCggICAABLAAECggIIgAHAO4iAA==.Shivera:BAAALAAECgQIEAAAAA==.Shiveraia:BAAALAADCgcIBwABLAAECgQIEAADAAAAAA==.Shôckwave:BAAALAAECgYIBQAAAA==.',Si='Sianra:BAAALAAECgYIDAABLAAFFAQICgAFAN0PAA==.Silea:BAAALAADCgcIFQAAAA==.',Sk='Skorpien:BAAALAAECgYIEwAAAA==.Skurilla:BAABLAAECoElAAIEAAcIlBivUwDmAQAEAAcIlBivUwDmAQAAAA==.',Sl='Slarti:BAAALAAECgYIEAAAAA==.',Sm='Smeemie:BAAALAADCggIFgABLAAECggICgADAAAAAA==.',So='Sofija:BAAALAADCggICAAAAA==.Solan:BAAALAADCgUIBQAAAA==.Songôku:BAAALAAECgEIAQAAAA==.',Sp='Spiritreaper:BAAALAAECgMIAwAAAA==.',St='Streuselchen:BAABLAAECoEdAAIGAAcIOw36QwByAQAGAAcIOw36QwByAQAAAA==.Sturmlord:BAABLAAECoEsAAIhAAcIeSFaCQBFAgAhAAcIeSFaCQBFAgAAAA==.',Su='Supahfly:BAAALAAECggICgAAAA==.Sushima:BAABLAAECoEkAAIEAAcIMBtdYwC+AQAEAAcIMBtdYwC+AQAAAA==.Suusi:BAAALAADCgcIBwAAAA==.',Sy='Sydana:BAAALAAECgYIBwABLAAECggIHwAbAF0bAA==.Syndica:BAAALAADCgYIBwAAAA==.Syranie:BAAALAAFFAEIAQAAAA==.',['Sø']='Sølveig:BAAALAAECgMIBAAAAA==.',['Sû']='Sûpernatural:BAAALAAECgcIBwAAAA==.',['Sü']='Süleyman:BAAALAADCgQIBAAAAA==.',Ta='Talarockdh:BAAALAADCgMIAwAAAA==.Talim:BAABLAAECoEWAAIZAAYIwQLtNwCwAAAZAAYIwQLtNwCwAAAAAA==.Tareth:BAAALAAECgYIEAAAAA==.Targin:BAAALAADCggICAAAAA==.',Te='Tegaai:BAAALAADCgcICgAAAA==.Temani:BAAALAAECgQIBAAAAA==.Teney:BAAALAADCgcIBwAAAA==.Terra:BAAALAADCggIEgAAAA==.Terrastas:BAAALAADCggICAAAAA==.',Th='Thalarian:BAAALAAECgIIAgAAAA==.Thegreenone:BAABLAAECoEVAAQYAAcIOiOSHgCyAgAYAAcIOiOSHgCyAgAMAAMIRQxDbACMAAANAAIIMxTZKACJAAAAAA==.Thorbald:BAAALAAECgYICAAAAA==.Thorz:BAAALAADCgUIBgAAAA==.Thranôr:BAAALAAECgEIAQAAAA==.Throloasch:BAABLAAECoEcAAIIAAcIQiE7DACLAgAIAAcIQiE7DACLAgAAAA==.Thundor:BAABLAAECoEmAAIHAAgIZxQbOAD9AQAHAAgIZxQbOAD9AQAAAA==.',Ti='Tiarake:BAAALAAECgYIBgAAAA==.Tirus:BAAALAADCgcIDgAAAA==.Tiyanak:BAAALAADCggIMAAAAA==.',To='To:BAAALAAECggIDwAAAA==.Toho:BAABLAAECoEdAAMfAAcIRBUUGAC8AQAfAAcIRBUUGAC8AQAeAAMI0wacTwBpAAAAAA==.Tomberie:BAAALAADCgIIAgAAAA==.Tonia:BAABLAAECoEoAAMdAAcIKyFeFABwAgAdAAcI6h9eFABwAgAiAAUIhBp6CgCHAQAAAA==.Touch:BAAALAADCggICAABLAAFFAYIFwAaAK8QAA==.',Tw='Twissi:BAAALAADCggICAABLAAECgcIGAATAG8dAA==.',['Tô']='Tôhr:BAAALAADCggIFgAAAA==.',['Tø']='Tøry:BAAALAADCgcIBwAAAA==.',Un='Ungoy:BAAALAAECgYICQAAAA==.',Ve='Ventrax:BAAALAAECgcIDgAAAA==.Vesúvîo:BAAALAADCggIDgAAAA==.',Vi='Vietchad:BAAALAAECgIIAgAAAA==.Virelia:BAAALAAECgYIDAAAAA==.Virikas:BAABLAAECoEsAAMWAAcIaiG9GgB/AgAWAAcIaiG9GgB/AgAjAAYILR75OQDPAQAAAA==.',Vo='Voodoomedic:BAABLAAECoEbAAITAAgIvxZfQQDyAQATAAgIvxZfQQDyAQAAAA==.',Vu='Vulpi:BAAALAAECgMICAAAAA==.',Vy='Vykaz:BAAALAAECgQIBgAAAA==.',Wa='Wanebi:BAABLAAECoEVAAMUAAYIviBjGAA+AgAUAAYIviBjGAA+AgAVAAYI+QecjgASAQABLAAECggIIgAHAMwgAA==.Warrcrex:BAAALAAFFAIIAgAAAA==.Wasislos:BAAALAADCggICAABLAAECgYIDQADAAAAAA==.',We='Werwolff:BAAALAADCggICAAAAA==.',Wh='Whisch:BAABLAAECoEeAAIBAAcIAyFkKACaAgABAAcIAyFkKACaAgAAAA==.',Wi='Wienix:BAAALAAECgIIAgAAAA==.',Wr='Wreckquiem:BAAALAAECgYIEAAAAA==.',Wu='Wusseltwo:BAAALAAECgMICgAAAA==.',Wy='Wynne:BAAALAADCgYIBgAAAA==.',['Wä']='Wächterathen:BAACLAAFFIEJAAIOAAMIVxjxDgD8AAAOAAMIVxjxDgD8AAAsAAQKgTIAAg4ACAidIx4QACYDAA4ACAidIx4QACYDAAAA.',Xa='Xaruria:BAABLAAECoEhAAIRAAgIORjIWAAUAgARAAgIORjIWAAUAgAAAA==.',Xb='Xbaze:BAAALAADCgEIAQAAAA==.',Xe='Xenmas:BAAALAADCggICAAAAA==.',Xi='Xiara:BAAALAADCgUIBQAAAA==.Xiaufu:BAAALAADCgIIAgABLAAFFAQICgAFAN0PAA==.Xilu:BAABLAAECoEcAAIYAAcIkgxMaACFAQAYAAcIkgxMaACFAQAAAA==.Xinara:BAAALAADCgUIBQAAAA==.',Xu='Xu:BAAALAADCgYIBwAAAA==.',Ye='Yeree:BAAALAADCgYIBgAAAA==.',Yi='Yilvinia:BAAALAAECgIIBAAAAA==.',Yo='Yorndar:BAAALAAECgYIDQAAAA==.Yoshî:BAAALAADCgQIBAAAAA==.',Yu='Yuralia:BAAALAAECgYICwAAAA==.Yuriká:BAAALAAECgYIBgAAAA==.Yuukî:BAAALAADCgcIDgAAAA==.',Za='Zalduun:BAAALAAECggIBQAAAA==.Zapzarrapp:BAAALAAECgYIDQAAAA==.',Ze='Zern:BAAALAADCggIIgAAAA==.',Zh='Zhaabis:BAABLAAECoEXAAMMAAgICRmHLgCVAQAMAAQIiySHLgCVAQAYAAgIgQ1chQA5AQAAAA==.',Zi='Zino:BAAALAADCggIIQAAAA==.',Zm='Zmokey:BAAALAADCgQIBAAAAA==.',Zo='Zourâ:BAAALAAECgUICgAAAA==.',['Zê']='Zêcks:BAAALAADCgYIBgAAAA==.',['Ðe']='Ðeathcurry:BAAALAAECgcIBwAAAA==.',['Ñy']='Ñyx:BAAALAAECgQICAAAAA==.',['Óg']='Óga:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end