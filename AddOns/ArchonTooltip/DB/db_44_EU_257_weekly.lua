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
 local lookup = {'DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','DeathKnight-Blood','Mage-Frost','Paladin-Retribution','Evoker-Preservation','Unknown-Unknown','Priest-Shadow','Priest-Holy','Druid-Guardian','Hunter-BeastMastery','Paladin-Protection','Monk-Windwalker','Warrior-Fury','Shaman-Restoration','DemonHunter-Havoc','Paladin-Holy','Rogue-Assassination','Warlock-Affliction','Druid-Balance','Druid-Restoration','Warlock-Destruction','Hunter-Survival','Shaman-Elemental','Hunter-Marksmanship','Warrior-Protection','Evoker-Devastation',}; local provider = {region='EU',realm='Auchindoun',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abezethibou:BAACLAAFFIEHAAMBAAMIMg5OAgD/AAABAAMIMg5OAgD/AAACAAEI/AbkKQBHAAAsAAQKgR8AAwEACAhHJPQBAC0DAAEACAhHJPQBAC0DAAIAAwiWGFeRANEAAAAA.Abhor:BAAALAADCgYIBgAAAA==.Aboveyou:BAAALAADCggICAABLAAECggIHgADADAbAA==.',Ad='Addeshammy:BAAALAADCgIIAgAAAA==.Adelard:BAAALAAECgYIBgABLAAFFAQIBwADAGsUAA==.Adernal:BAAALAADCgYIBgAAAA==.',Ae='Aellowyn:BAAALAAECggIEwAAAA==.',Ah='Ahnfrau:BAABLAAECoEbAAMCAAgIdBtpIgBcAgACAAgIzBppIgBcAgAEAAcI4hYmDQDIAQAAAA==.Ahriman:BAABLAAECoEVAAMFAAgIOhffEAAiAgAFAAgIOhffEAAiAgADAAEIjAqvnAArAAAAAA==.',Ai='Ainaria:BAAALAAECgMIAwAAAA==.',Ak='Akatamaxitos:BAAALAADCgQIBAAAAA==.Akuuru:BAAALAADCgYIBgAAAA==.',Al='Aldamsk:BAAALAADCggICAAAAA==.Alikax:BAAALAAECgMIBAAAAA==.Alleiheim:BAABLAAECoEVAAIGAAcITSHEGACcAgAGAAcITSHEGACcAgAAAA==.Almirona:BAAALAADCgcIBwAAAA==.Alumno:BAAALAAECgYIDgAAAA==.',An='Anarkuid:BAAALAADCgIIAgAAAA==.Andeles:BAAALAADCgcIDAAAAA==.Anointing:BAAALAAECgcIDAAAAA==.Antifun:BAAALAAECgMIAwAAAA==.',Ap='Apoc:BAAALAADCgUICAAAAA==.',Aq='Aqualock:BAAALAADCggICAAAAA==.',Ar='Arcanaan:BAAALAADCgEIAQAAAA==.Arff:BAAALAAECgUICQAAAA==.Arginoth:BAAALAAECgUIBQAAAA==.Arrinita:BAAALAADCggICAAAAA==.',As='Asclepius:BAAALAAECgYIDgAAAA==.Asiet:BAAALAADCggICAAAAA==.Asserborges:BAAALAADCgQIBAAAAA==.',At='Atromitos:BAAALAADCgQIBAAAAA==.',Au='Auroc:BAAALAADCggIDwABLAAECggIFwAHAHkZAA==.Auron:BAAALAADCggICAABLAAECggIFwAHAHkZAA==.Autistikos:BAAALAADCggIDQAAAA==.',Ay='Ayene:BAAALAAECgEIAQAAAA==.',Az='Azareth:BAAALAAECgEIAQABLAAECgMIAwAIAAAAAA==.Aztharooth:BAAALAAECgUICwAAAA==.Azurael:BAABLAAECoEbAAMJAAgILyBqEgB8AgAJAAcIeyBqEgB8AgAKAAUIoBSOQwAzAQAAAA==.',Ba='Bacpelas:BAAALAAFFAIIAgAAAA==.Badshuvo:BAAALAADCgMIAwAAAA==.Balmung:BAABLAAECoEXAAIHAAgIeRmKBgBZAgAHAAgIeRmKBgBZAgAAAA==.Bamboolic:BAAALAADCggICAAAAA==.Batbayar:BAAALAADCggICwAAAQ==.',Bb='Bbldrizzy:BAAALAAECgYIBwABLAAECggIHwALAEceAA==.',Be='Bearhanded:BAAALAAECgUICwABLAAECggIFAAMAOERAA==.Beeffcake:BAABLAAECoEaAAINAAcIMB11CgA3AgANAAcIMB11CgA3AgAAAA==.Begouri:BAAALAAECgYIBgAAAA==.Bendis:BAAALAADCggICAAAAA==.',Bh='Bhenchod:BAAALAAFFAIIAgAAAA==.',Bi='Biberce:BAAALAAECgcIEwAAAA==.Biisch:BAAALAAECgYICgAAAQ==.Bitmin:BAAALAAECgEIAQAAAA==.',Bl='Blacksunday:BAAALAAECgMIAwAAAA==.Blantak:BAAALAADCgYICwAAAA==.Blayai:BAAALAADCgcIDgAAAA==.Blockongcd:BAAALAAFFAIIAgAAAA==.Bluebee:BAAALAAECgYIEgAAAA==.Bláin:BAAALAAECgMIBgAAAA==.',Bo='Bobs:BAABLAAECoEUAAIGAAcIqyFqFADAAgAGAAcIqyFqFADAAgAAAA==.Bodyee:BAAALAADCgcIBwAAAA==.Bodzilla:BAAALAADCggIBAAAAA==.Bomba:BAAALAAECgcIDQAAAA==.Boogie:BAAALAAECgYICQAAAA==.Bowmont:BAAALAADCggICAAAAA==.Boxanne:BAAALAADCggICAAAAA==.Boxley:BAAALAAECgYIBgAAAA==.',Br='Bronzeird:BAAALAAECggIDgAAAA==.Brostrøm:BAAALAAECgYICwAAAA==.Brutalbacon:BAAALAAECgMIBwAAAA==.Brutalmayo:BAAALAADCgcICwAAAA==.',Bu='Bubbler:BAAALAADCggICAABLAAFFAMIBwABADIOAA==.Bumbaclart:BAABLAAECoETAAIOAAgIcxM6GgCSAQAOAAgIcxM6GgCSAQAAAA==.Buuhu:BAABLAAECoEYAAIPAAcI6yKKEACwAgAPAAcI6yKKEACwAgAAAA==.Buutje:BAABLAAECoEXAAICAAgIeSMZBwAuAwACAAgIeSMZBwAuAwAAAA==.',['Bä']='Bäbävitaröv:BAAALAAECggIDAAAAA==.',['Bú']='Búbblegum:BAAALAAECgEIAQAAAA==.',Ca='Ca:BAAALAAECgIIAwAAAA==.Cadush:BAACLAAFFIEJAAIPAAUILRaZAQDXAQAPAAUILRaZAQDXAQAsAAQKgR0AAg8ACAi7I8QFADQDAA8ACAi7I8QFADQDAAAA.Caelum:BAABLAAECoEYAAINAAgIIxpECQBRAgANAAgIIxpECQBRAgAAAA==.Callisto:BAAALAAECgIIAgABLAAFFAIIAgAIAAAAAA==.Camooflage:BAAALAAECggICAAAAA==.Carlos:BAAALAADCgYIBgAAAA==.Caspari:BAAALAADCggIFQAAAA==.Castillian:BAAALAAECgYIBgAAAA==.Cazira:BAAALAAECgYICQAAAA==.',Ce='Celestrîa:BAAALAAECgMIBQAAAA==.Celots:BAAALAADCgIIAQAAAA==.Cenaria:BAAALAADCgYIBgAAAA==.',Ch='Charok:BAAALAADCgYIBgABLAADCgcIBwAIAAAAAA==.Chinpokemon:BAABLAAECoEWAAIQAAgIQQ23RABpAQAQAAgIQQ23RABpAQAAAA==.Chocomel:BAAALAADCgYIBgABLAADCgcIBwAIAAAAAA==.Chïps:BAAALAAECgUIDAAAAA==.',Co='Coulson:BAAALAAECgQIBAAAAA==.',Cr='Crusto:BAAALAADCggICAAAAA==.Cruz:BAAALAAECgUIBAAAAA==.Cryptoscam:BAAALAADCggIFQAAAA==.',Cu='Cuckman:BAAALAADCggIFwABLAAFFAMICAADALAQAA==.',Cy='Cy:BAAALAAFFAIIAgAAAA==.Cyguli:BAAALAAECgYIBgABLAAECggIHwARACYeAA==.',Da='Dalish:BAAALAAECgcIEAAAAA==.Dalouch:BAAALAAECgUIBwAAAA==.Damae:BAAALAAECgEIAQAAAA==.Danii:BAAALAADCgcIBwAAAA==.Dankbemes:BAAALAAECgYIBgAAAA==.Dariann:BAAALAADCgIIAwAAAA==.Darkbee:BAABLAAECoEWAAIOAAcI0BOOFQDFAQAOAAcI0BOOFQDFAQAAAA==.',De='Deathanger:BAAALAAECggICAAAAA==.Demondög:BAAALAADCgQIBAAAAA==.Demonimies:BAAALAAECgMIAwAAAA==.Desepticon:BAABLAAECoEVAAICAAgI4xhQIwBYAgACAAgI4xhQIwBYAgAAAA==.Destromo:BAAALAAECgIIAwAAAA==.Detgodtrug:BAAALAADCgcIBwAAAA==.',Di='Dialga:BAAALAADCgcICAAAAA==.Dingodile:BAAALAAECgIIAgAAAA==.Disarmed:BAAALAAECgQIBAAAAA==.Divinus:BAABLAAECoEeAAMKAAgIzySZAgBBAwAKAAgIzySZAgBBAwAJAAII9B+STAC8AAAAAA==.',Dm='Dmgdmgdmgdmg:BAAALAAECgYIDQAAAA==.',Do='Dodor:BAAALAADCggICAAAAA==.Dom:BAAALAAECgYIBAAAAA==.Donja:BAAALAADCggICAABLAAECgcIGAAPAOsiAA==.',Dr='Dredex:BAAALAAECgYIBwAAAA==.Drunkenmonk:BAAALAAECgcIDgAAAA==.Druoc:BAAALAAECgIIAgAAAA==.Druthus:BAAALAAECgIIAgAAAA==.Dryath:BAAALAAECggIAQAAAA==.',Dt='Dtrix:BAAALAADCgYIBgAAAA==.',Du='Dukan:BAAALAAECgcIDQAAAA==.',Dz='Dziaduch:BAAALAAECgIIAgAAAA==.',['Dø']='Dødskriger:BAAALAAECgEIAQAAAA==.',El='Elandriana:BAAALAADCgcIFQAAAA==.Eldric:BAAALAADCgcIBwAAAA==.Elektraz:BAAALAADCggIEAAAAA==.Elementalls:BAAALAADCgQIBQAAAA==.Ellathil:BAAALAAECgQICwAAAA==.Elthalas:BAAALAADCgcIBwAAAA==.Elvost:BAAALAAECgYICQAAAA==.',Ep='Ephemei:BAAALAAECgUIBQAAAA==.',Er='Erlich:BAABLAAECoEVAAMGAAcIURqKJwA8AgAGAAcIURqKJwA8AgASAAYIww7YJABLAQAAAA==.Erymanthos:BAAALAAECgYIBgAAAA==.',Es='Eskimos:BAAALAADCgcIBwAAAA==.Esrya:BAAALAAECggIEgAAAA==.',Eu='Eunie:BAABLAAECoEaAAIKAAgIjyRcAgBFAwAKAAgIjyRcAgBFAwABLAAFFAIIAgAIAAAAAA==.',Ev='Evokussy:BAAALAAECggIEAAAAA==.Evöker:BAAALAAECgEIAQAAAA==.',Fa='Faitlesy:BAAALAAECgcIEQAAAA==.Falcone:BAAALAADCggICAAAAA==.Falsorick:BAAALAADCgQIBAAAAA==.Fatboss:BAAALAADCgcIBwAAAA==.',Fe='Fear:BAAALAADCgYIBgAAAA==.',Fi='Fiendall:BAAALAADCggICAABLAAECggIIQABAGwYAA==.Fiendari:BAAALAAECgYICgABLAAECggIIQABAGwYAA==.Fiendisha:BAABLAAECoEhAAIBAAgIbBh/CQBYAgABAAgIbBh/CQBYAgAAAA==.Finbebiz:BAAALAAECgMIAwAAAA==.Firebread:BAAALAADCgcIDQABLAAECgcIEQAIAAAAAA==.Firnae:BAAALAAECgMIBAAAAA==.Fisaar:BAAALAAECgMIAwAAAA==.',Fl='Flage:BAAALAADCgcIBwAAAA==.Flendurs:BAAALAAECgIIAwAAAA==.Flonsky:BAAALAAECgYIBgAAAA==.',Fo='Forestdaddy:BAAALAAECgYICgAAAA==.',Fr='Fristi:BAAALAADCgcIBwAAAA==.Frostiaz:BAAALAADCggIEAAAAA==.',Ga='Gael:BAAALAADCgYIBgAAAA==.Gaintrain:BAABLAAECoEXAAIPAAgIxR+ADwC8AgAPAAgIxR+ADwC8AgAAAA==.Galadrielq:BAAALAADCgYICwAAAA==.Galagond:BAAALAADCgYIBgAAAA==.Gapehòrn:BAAALAADCggIDwAAAA==.Garzhaoel:BAAALAAECgcIEwAAAA==.',Ge='Geoand:BAAALAADCggIDAAAAA==.Georgemooney:BAAALAAECgEIAQAAAA==.',Gi='Gimlêe:BAAALAAECgcIEAAAAA==.Gipsymagic:BAAALAADCgUIBQAAAA==.Gitt:BAAALAADCgcIDQAAAA==.',Go='Gorethidus:BAAALAADCgYIBgABLAAECgQIBAAIAAAAAA==.Gorgothra:BAAALAADCgcIBwAAAA==.',Gr='Grevane:BAAALAAECgYICgAAAA==.Griever:BAAALAADCgcIDgAAAA==.',Gu='Guido:BAAALAAECgYIDwAAAA==.',Gw='Gwinny:BAAALAADCgcIBwAAAA==.',Gy='Gygax:BAAALAADCgMIAwAAAA==.',Ha='Haagseharrie:BAAALAAECgMICAAAAA==.Hairyshooter:BAAALAADCgEIAQABLAAECgEIAQAIAAAAAA==.Harrison:BAAALAADCgcIBwAAAA==.Hatchet:BAABLAAECoEXAAIPAAgISwmkQgBCAQAPAAgISwmkQgBCAQAAAA==.Haude:BAAALAAECgQIBAAAAA==.',He='Hedra:BAAALAADCggIDwAAAA==.',Hi='Hildurr:BAAALAADCgUIBQAAAA==.',Ho='Holyeras:BAAALAAECgEIAQABLAAECgIIAgAIAAAAAA==.Holykoli:BAAALAADCggICAABLAAECggIHgADADAbAA==.Holyra:BAAALAAECgYIDQAAAA==.Holyshield:BAAALAAECgIIAgAAAA==.',Hu='Hulm:BAAALAADCggICAABLAAFFAMICAADALAQAA==.Humppa:BAAALAADCgQIBAAAAA==.Huntdany:BAAALAADCgUIBQABLAAECgIIAgAIAAAAAA==.Hunteror:BAAALAADCggICQABLAAECgMIBQAIAAAAAA==.',['Hé']='Héllsangel:BAAALAAECgUICwAAAA==.Hézdrøøn:BAAALAAECgQIBAAAAA==.',Ii='Iiana:BAAALAAECgYICgAAAA==.',Il='Illemnorh:BAAALAADCgIIAgAAAA==.Illidanas:BAAALAAECgMIBgAAAA==.',Im='Imagiination:BAAALAAECgMIBgAAAA==.Iminpain:BAABLAAECoEUAAITAAcIIBh0FwAHAgATAAcIIBh0FwAHAgAAAA==.Imka:BAAALAAECgYICgABLAAECgYIDAAIAAAAAA==.Impact:BAAALAAECggICAAAAA==.',In='Indiahna:BAAALAADCgcIBwAAAA==.Inferna:BAAALAADCggIDQABLAAECgcIFgAGAIsdAA==.Infestant:BAAALAADCgMIAwABLAADCgUIBQAIAAAAAA==.Infliction:BAAALAAECgYIDAAAAA==.Insanity:BAABLAAFFIEFAAIJAAMICRpPBQAAAQAJAAMICRpPBQAAAQAAAA==.Inushi:BAABLAAECoEbAAIQAAgIUhxbEAB5AgAQAAgIUhxbEAB5AgABLAAECggIHwARACYeAA==.Invisium:BAABLAAECoEUAAIPAAcIDxpgHAA2AgAPAAcIDxpgHAA2AgAAAA==.',Ir='Ironbru:BAAALAAECgYIBgAAAA==.Irridar:BAAALAAECggIDgAAAA==.',Ja='Jagguu:BAAALAADCgcIDwAAAA==.Jakeir:BAAALAADCgYIBgABLAAECgYICAAIAAAAAA==.Jakpala:BAAALAAECgYIBwABLAAECgYICAAIAAAAAA==.Jakunt:BAAALAAECgYICAAAAA==.Jammi:BAAALAAECggIEAAAAA==.Jaysdead:BAAALAAECgIIBAAAAA==.',Je='Jeralt:BAAALAADCggICAABLAAFFAIIAgAIAAAAAA==.',Ji='Jigsaw:BAAALAADCggICAAAAA==.Jilf:BAAALAAECgMIAwABLAAECgYIDAAIAAAAAA==.Jilfie:BAAALAADCggIBgABLAAECgYIDAAIAAAAAA==.Jilfs:BAAALAAECgYIDAAAAA==.',Jo='Joelgeorge:BAAALAAFFAIIAgAAAA==.Jollymeroger:BAAALAAFFAIIAgABLAAFFAQIBAAIAAAAAA==.Jostivos:BAABLAAECoEUAAIMAAgI4REHJQANAgAMAAgI4REHJQANAgAAAA==.',Ju='Justholdthis:BAAALAADCgcIDgAAAA==.Jux:BAAALAADCgUIBQAAAA==.',Ka='Kadru:BAAALAAECggIDAAAAA==.Kaehl:BAAALAADCggICAAAAA==.Kantanja:BAAALAADCgcIDQAAAA==.Kanylekalle:BAAALAAECggICAAAAA==.Kathrina:BAAALAADCgMIAwAAAA==.Kaziulek:BAAALAADCgcICQAAAA==.Kazuki:BAAALAAECgQIBQAAAA==.',Ke='Kecteh:BAABLAAECoEaAAICAAgItyEvCwAGAwACAAgItyEvCwAGAwAAAA==.Kedra:BAAALAAECgYIBgAAAA==.Kenita:BAAALAADCgYIBgAAAA==.Kenty:BAABLAAECoERAAIUAAcIzRSABwAGAgAUAAcIzRSABwAGAgAAAA==.',Kh='Khaluna:BAAALAADCgcIDgAAAA==.Khâmul:BAAALAAECgMIAwAAAA==.',Ki='Killghost:BAAALAAECgcIEgAAAA==.Killwill:BAAALAAECgYIBgAAAA==.Kitea:BAAALAAECgYIBgAAAA==.',Kn='Knab:BAAALAAECgIIAgAAAA==.',Ko='Kolinje:BAABLAAECoEaAAIVAAgIOR5pCwC9AgAVAAgIOR5pCwC9AgABLAAECggIHgADADAbAA==.',Ku='Kurrosh:BAAALAAECgcIDgAAAA==.Kushrock:BAAALAAECgYIBgAAAA==.Kuzi:BAAALAADCggIFwAAAA==.',Kv='Kvòthe:BAAALAAECgcIEgAAAA==.',['Ké']='Kéno:BAAALAAECgEIAQAAAA==.',La='Laguna:BAAALAADCgYIDwABLAAECgYIDAAIAAAAAA==.Lakaz:BAAALAADCgQIBAAAAA==.Lamindra:BAAALAADCggIEAAAAA==.Lastent:BAAALAAECgcIEQAAAA==.Lavsan:BAABLAAECoEUAAIPAAcIDhrGHwAbAgAPAAcIDhrGHwAbAgAAAA==.',Le='Lelthaes:BAAALAAECgYIDgAAAA==.Lethallars:BAAALAAECgUICQAAAA==.',Li='Lightknight:BAAALAAECggIEQAAAA==.Lightwork:BAAALAAECgcIBwAAAA==.Liinx:BAAALAAECgYIBgAAAA==.Lillath:BAAALAADCgcICwAAAA==.Lillea:BAABLAAECoEfAAIWAAgItCW0AABjAwAWAAgItCW0AABjAwAAAA==.Lilli:BAAALAAECggIAwAAAA==.Lilyth:BAAALAADCggIDwAAAA==.Lionjr:BAAALAAECgUIBQAAAA==.',Ll='Lliane:BAAALAAECgcIEQAAAA==.',Lo='Lokastico:BAAALAADCgUIBQAAAA==.Loker:BAACLAAFFIEFAAINAAIIABT2BQCKAAANAAIIABT2BQCKAAAsAAQKgRsAAw0ACAjbJBABAGgDAA0ACAjbJBABAGgDAAYABwjXHoYjAFICAAAA.Lolibomb:BAAALAADCgUIBQAAAA==.Loodakl:BAAALAADCggIDwAAAA==.Lotsalight:BAABLAAECoEYAAIGAAgIJR3gHQB1AgAGAAgIJR3gHQB1AgAAAA==.',Lu='Luftey:BAAALAAECgIIAgAAAA==.Lumrene:BAAALAADCgIIAgAAAA==.',Ly='Lythria:BAABLAAECoEfAAIRAAgIJh4hEwDHAgARAAgIJh4hEwDHAgAAAA==.',Ma='Magiemagie:BAAALAADCgUICQAAAA==.Magios:BAAALAAECgEIAQAAAA==.Maiznieks:BAAALAAECgYICQAAAA==.Malefìco:BAAALAAECggICAAAAA==.Malys:BAAALAAECgMIAwABLAAECgYIBgAIAAAAAA==.Marben:BAAALAADCgUIBQAAAA==.Mariahscary:BAAALAAECgEIAQAAAA==.Marinadomine:BAAALAAECgYIBwAAAA==.Maugar:BAAALAADCgcICAAAAA==.Mayko:BAAALAADCgcIBwAAAA==.',Me='Melhøna:BAAALAADCggICAAAAA==.Melkrek:BAAALAAECggICQAAAA==.Mellerr:BAAALAAECgMICAAAAA==.Membrain:BAABLAAECoEMAAITAAgIkgIZNQAcAQATAAgIkgIZNQAcAQAAAA==.Metallicat:BAAALAAECgQIBAAAAA==.Mewtwoo:BAAALAAECggIBgAAAA==.',Mi='Milkhammer:BAAALAAECgYIDwAAAA==.Miniglowjob:BAAALAAECgQIDwAAAA==.Mistet:BAABLAAECoEfAAILAAgIRx7RAQDGAgALAAgIRx7RAQDGAgAAAA==.Mizhadin:BAAALAADCggICwAAAA==.',Mo='Molybdenum:BAAALAADCgUIBQAAAA==.Momoayase:BAAALAADCgIIAgAAAA==.Moonduck:BAAALAAECgEIAQAAAA==.Moonstar:BAAALAADCgYIBgAAAA==.Morii:BAAALAAECgYIDQAAAA==.',Mu='Mubeen:BAAALAADCgQIBAAAAA==.Murdorer:BAAALAAECgYICwABLAAECggIHgADADAbAA==.Murlock:BAAALAADCgMIAwAAAA==.',My='Mysticpete:BAAALAAECgYIDAAAAA==.',Na='Nahsoor:BAAALAADCgMIAwAAAA==.Navleuld:BAAALAAECgYIBwAAAA==.Nayla:BAAALAADCgcICgAAAA==.Nazztwink:BAAALAADCggIDwABLAAFFAcIEwADALAaAA==.',Ne='Neophyte:BAAALAAECgcIAgAAAA==.Nesyaa:BAAALAAECgYICgAAAA==.Nezarecc:BAABLAAECoEXAAIXAAgInR1KDwDDAgAXAAgInR1KDwDDAgAAAA==.',Ni='Nidanur:BAAALAADCggICAAAAA==.Nightprowler:BAAALAAECgMIBAAAAA==.Niias:BAAALAADCgMIAwAAAA==.Nilsah:BAAALAAECggIEgAAAA==.',Nk='Nkaral:BAAALAADCggICAAAAA==.',No='Noexcuses:BAAALAAECgQIBQABLAAECgYIEAAIAAAAAA==.Nolin:BAAALAADCgYICQAAAA==.Notarms:BAAALAADCgUIBQABLAAECggIGwACAHQbAA==.Notinpain:BAAALAADCggICAAAAA==.Nototemz:BAAALAADCgYIBgABLAAECgYICQAIAAAAAA==.',Nu='Nuggee:BAAALAADCgcIEAAAAA==.',Ob='Obilivian:BAAALAADCgcIBwAAAA==.Obliivian:BAAALAADCgMIAwAAAA==.Obliviaan:BAAALAADCggIBwAAAA==.',Ol='Oldalanor:BAAALAAECgMIBgAAAA==.',Oo='Ooz:BAAALAAECgQIBAAAAA==.',Or='Oreó:BAAALAAECgMIAwAAAA==.Orsoeus:BAAALAADCggICAAAAA==.',Pa='Palahoof:BAABLAAECoEWAAIGAAcIix2tIgBXAgAGAAcIix2tIgBXAgAAAA==.Paldin:BAAALAAECgIIBAAAAA==.Papithiccums:BAAALAAECgYICAAAAA==.Parlé:BAABLAAECoEWAAIYAAcISR5rAgCKAgAYAAcISR5rAgCKAgAAAA==.Particle:BAABLAAECoEUAAIZAAgIlh9RCgD6AgAZAAgIlh9RCgD6AgAAAA==.Pawkosmosu:BAAALAADCgQIBAAAAA==.',Pe='Perineum:BAAALAAECgUIBgABLAAFFAMICAADALAQAA==.',Pi='Pitulica:BAAALAADCggIEAAAAA==.',Po='Pointblanc:BAAALAADCggICAAAAA==.',Pr='Prajala:BAAALAAECggIEwAAAA==.Prawnhub:BAAALAAECgYIBwAAAA==.Predatorian:BAAALAADCgYICgAAAA==.Prospectss:BAAALAAECgcIDwAAAA==.Prïesty:BAAALAAECgYIDwAAAA==.',Pu='Purkkapallo:BAAALAAECgYICQAAAA==.Purpleboii:BAAALAADCgYIBgAAAA==.',['Pá']='Pálm:BAAALAAECgYIBgAAAA==.',Qu='Quill:BAAALAADCggIDwAAAA==.Quistis:BAAALAAECgYIDAAAAA==.',Ra='Rakeland:BAACLAAFFIEIAAIDAAMIsBASCwDzAAADAAMIsBASCwDzAAAsAAQKgRwAAgMACAg4IKwPAOMCAAMACAg4IKwPAOMCAAAA.Rakke:BAAALAADCggIFgABLAAFFAMICAADALAQAA==.Rawked:BAAALAAECgcIBwAAAA==.Rayalyn:BAAALAAECgMIAwAAAA==.',Re='Realia:BAABLAAECoEaAAIRAAgISx8aFgCuAgARAAgISx8aFgCuAgAAAA==.Refra:BAAALAAECgcIEAAAAA==.Rejseholdet:BAAALAADCgcIDQAAAA==.Rengos:BAAALAAECgMIBgAAAA==.',Rf='Rflex:BAABLAAECoEYAAIaAAgI6hevFwAsAgAaAAgI6hevFwAsAgAAAA==.',Rh='Rhollor:BAAALAAECgMIAwAAAA==.',Ri='Rife:BAAALAADCgYICQAAAA==.',Ro='Robdobbob:BAAALAAECgcIDQAAAA==.Rockerul:BAAALAADCgcIBwAAAA==.Royal:BAAALAAECgYIDAAAAA==.',Ru='Ruggi:BAAALAAECgMIBgAAAA==.Runeforged:BAAALAAECgMIBQAAAA==.',Sa='Sabtism:BAABLAAECoEUAAIDAAcIWBj2MwD1AQADAAcIWBj2MwD1AQAAAA==.Sadness:BAAALAAECggIEAAAAA==.Sangraal:BAACLAAFFIEIAAIGAAMIMyUOAgBOAQAGAAMIMyUOAgBOAQAsAAQKgSAAAgYACAjRJmsAAJcDAAYACAjRJmsAAJcDAAAA.Saragosa:BAAALAAECgYIBgAAAA==.Sarvon:BAAALAADCgYIBwAAAA==.Sathrago:BAAALAAECgUIBQAAAA==.Savaged:BAAALAADCgYIBgABLAAECgcIDwAIAAAAAA==.',Sc='Scxrm:BAAALAAECgYIEQAAAA==.',Se='Secho:BAAALAAECgUICAAAAA==.Sempie:BAAALAAECgcIDwAAAA==.Serialhealer:BAAALAAECgMIBwAAAA==.',Sh='Shadowfalcón:BAAALAAECgYIDgAAAA==.Shadowmeld:BAAALAAECgMIBgAAAA==.Shadowvirus:BAAALAAECgMIAwAAAA==.Shaku:BAAALAAECgQIBAAAAA==.Shaldir:BAAALAADCgcIBwAAAA==.Shanked:BAAALAAECgIIAgAAAA==.Shekah:BAAALAAFFAEIAQAAAA==.Shivadestroy:BAAALAADCggICAAAAA==.Shuvodk:BAAALAAECgYIDwAAAA==.Shèrlock:BAABLAAECoEbAAMXAAgIZyJdBwAbAwAXAAgIZyJdBwAbAwAUAAEIsBLxLABNAAAAAA==.',Si='Sicklikenes:BAAALAAECgIIAgAAAA==.Silverspring:BAAALAADCgcICAAAAA==.Sindrala:BAAALAAECggIAgABLAAECggIDgAIAAAAAA==.',Sj='Sjåman:BAAALAADCgcIBwAAAA==.',Sm='Smaky:BAAALAADCgUIBQAAAA==.',Sn='Snegla:BAAALAADCgQIBAAAAA==.Snáil:BAAALAADCggICAAAAA==.',So='Sockybean:BAAALAAECgIIAgAAAA==.Solibell:BAABLAAECoEXAAIVAAgI5Q+nHADzAQAVAAgI5Q+nHADzAQAAAA==.Soulstorm:BAAALAADCggICAABLAAECgcIDQAIAAAAAA==.',Sp='Spacecoconut:BAAALAAECggICAAAAA==.',Sr='Srf:BAAALAADCgMIAwAAAA==.',St='Starnote:BAAALAADCggIFQAAAA==.Stax:BAAALAAECgIIAgAAAA==.Steelrose:BAAALAAECggIDwAAAA==.Stormbloodia:BAAALAADCgcIBwAAAA==.Stow:BAAALAAECggIEAAAAA==.Stststutter:BAAALAADCgEIAQAAAA==.Stylios:BAAALAADCgMIAwAAAA==.',Su='Substealth:BAAALAAFFAIIAgAAAA==.Sujiro:BAAALAADCgcIBwAAAA==.',Sw='Sweatypumpum:BAAALAADCggICAAAAA==.',Sy='Sylfer:BAAALAAECgMIAwAAAA==.',['Sé']='Séxydk:BAAALAAECgYICgAAAA==.Séxyshammy:BAABLAAECoEdAAIZAAgIayJgBgAtAwAZAAgIayJgBgAtAwAAAA==.',Ta='Tame:BAAALAAECgQIBQAAAA==.',Te='Teeqrah:BAAALAAECgcIDwAAAA==.Tenebrous:BAAALAADCgUIBQAAAA==.Tentac:BAAALAADCgUIBQAAAA==.Testudo:BAAALAAECgQIBwAAAA==.',Th='Thale:BAAALAADCgEIAQAAAA==.Theevil:BAAALAADCgcIDgAAAA==.Thicbackshot:BAAALAADCgYICAAAAA==.Thiccnsaucy:BAAALAADCgcIBwAAAA==.Thorinn:BAAALAADCgYIBgAAAA==.Thorontur:BAAALAAECgMIAgAAAA==.Thunderfist:BAAALAAECgMIBAABLAAECggIFQARAAUPAA==.',Ti='Tiggi:BAAALAAECgIIAgABLAAFFAMIBgAKAKsVAA==.Tiggye:BAAALAAECgYIEAABLAAFFAMIBgAKAKsVAA==.Titancore:BAAALAAECgYICAAAAA==.',Tj='Tjòngejonge:BAAALAAECgYIEwAAAA==.',To='Toffifee:BAAALAAECggIEQAAAA==.',Tr='Trainerdirk:BAAALAAECgMIBQAAAA==.Trickis:BAAALAADCgcIBwAAAA==.Tricksis:BAABLAAECoEaAAIMAAgIXiO6BQAuAwAMAAgIXiO6BQAuAwAAAA==.Trippin:BAAALAAECggIEQAAAA==.Trophybf:BAAALAAECgMIBAABLAAFFAMICAADALAQAA==.',Ts='Tsulix:BAAALAAECggICgAAAA==.',Tu='Tuntamage:BAABLAAECoEeAAIDAAgIMBsXHACDAgADAAgIMBsXHACDAgAAAA==.Turnip:BAAALAAECgcIDgAAAA==.Tuska:BAAALAAECgYIBgABLAAECgYIBgAIAAAAAA==.Tuunta:BAAALAADCgQIBAABLAAECggIHgADADAbAA==.',Tw='Twilightbeam:BAAALAAECgYICgAAAA==.Twìxx:BAABLAAECoEUAAIGAAcIzhgGNwD2AQAGAAcIzhgGNwD2AQAAAA==.',Ty='Tydus:BAAALAADCgYIDAABLAAECgYIDAAIAAAAAA==.Tygaren:BAAALAADCgcIEgAAAA==.Tygran:BAAALAAECgEIAQAAAA==.',Tz='Tzüky:BAAALAADCgYICgAAAA==.',Un='Unimagi:BAAALAAFFAIIAgAAAA==.',Us='Ustári:BAAALAAECgIIAgAAAA==.',Va='Vanderguard:BAAALAADCgMIAwAAAA==.Vanesa:BAABLAAECoEbAAIXAAgIThI7JgAAAgAXAAgIThI7JgAAAgAAAA==.',Ve='Vektron:BAAALAAECgIIAgAAAA==.Venoms:BAAALAAECgMIAwAAAA==.Vespera:BAAALAADCggICAAAAA==.',Vi='Viranty:BAAALAADCgcIBwAAAA==.',Vo='Voidhoe:BAAALAAECgMIAgAAAA==.Voidlord:BAAALAADCggIGQAAAA==.Voidstalker:BAAALAAECgMIBgAAAA==.Volkar:BAAALAAECgYIBgAAAA==.Voodoodudu:BAABLAAECoEZAAILAAgI4yO/AAA8AwALAAgI4yO/AAA8AwAAAA==.Voodoojuju:BAAALAAECgIIAgAAAA==.Voof:BAAALAADCggICAAAAA==.',Vt='Vtz:BAAALAAECggIDQAAAA==.',Vu='Vuurvlaag:BAAALAADCgcICAAAAA==.',['Vå']='Våjdälfmage:BAAALAADCgcICgAAAA==.',Wa='Warchiéf:BAAALAADCgcIBwAAAA==.Warnarki:BAAALAAECgQIBQAAAA==.Wasnar:BAAALAAECgQIBwAAAA==.Wata:BAAALAADCgEIAQAAAA==.Waterboyxd:BAAALAAECggICgAAAA==.',We='Wees:BAABLAAECoEaAAIHAAgI2gvsDgCOAQAHAAgI2gvsDgCOAQAAAA==.',Wh='Whez:BAAALAAECgYICQAAAA==.Whumle:BAAALAADCggIDwABLAAECggIHgAbAKYhAA==.',Wi='Wildstorm:BAAALAAECgcIDQAAAA==.',Wo='Wombo:BAABLAAECoEeAAIbAAgIpiEZBAAIAwAbAAgIpiEZBAAIAwAAAA==.',Wr='Wrain:BAAALAAECggIBQAAAA==.',Xa='Xandre:BAAALAAECgYIBgABLAAECggIHgAbAKYhAA==.',Xe='Xeld:BAAALAADCgcIBwAAAA==.Xenodrood:BAAALAADCggICAABLAAFFAMICAAGADMlAA==.',Ya='Yabas:BAAALAAECgYIDAAAAA==.',Ye='Yelunara:BAAALAAECgYICgAAAA==.',Yi='Yimoo:BAAALAAECgYIDgAAAA==.',Yo='Yoshihoudini:BAAALAADCgQIBAAAAA==.Yoshinoel:BAAALAAECgEIAQAAAA==.Yoshix:BAAALAAECgIIAgAAAA==.',Ys='Yserah:BAABLAAECoEVAAIcAAgIqxDLFQAGAgAcAAgIqxDLFQAGAgAAAA==.Ysèra:BAAALAADCgcIDAAAAA==.',Yu='Yuma:BAABLAAECoEVAAIQAAcIyQ4PTABOAQAQAAcIyQ4PTABOAQAAAA==.Yumeth:BAAALAAECgMIBAAAAA==.Yumyam:BAAALAADCggICAAAAA==.Yunalesca:BAAALAAECgEIAQAAAA==.',Za='Zaratavex:BAAALAADCgIIAgAAAA==.',Ze='Zealicious:BAABLAAECoEYAAIDAAgIJSNLDwDnAgADAAgIJSNLDwDnAgAAAA==.Zedomeld:BAAALAAECgUICAAAAA==.Zellon:BAAALAADCgYIBwAAAA==.Zendh:BAAALAAECgYIDwAAAA==.Zeneve:BAAALAAECgEIAQAAAA==.Zerethia:BAAALAAECgIIAgAAAA==.Zeriza:BAAALAAECgUIBQAAAA==.Zerryx:BAAALAADCgYIBgAAAA==.',Zh='Zhug:BAAALAAECgQICQAAAA==.',Zi='Zigeuner:BAAALAADCgcIBwAAAA==.Ziyech:BAAALAAECgYICgAAAA==.',['Ás']='Ása:BAAALAAECgMIBQAAAA==.',['Él']='Élmo:BAABLAAECoEYAAIQAAgIOCE4BgDpAgAQAAgIOCE4BgDpAgAAAA==.',['Ón']='Óni:BAAALAAECgEIAQAAAA==.',['Öh']='Öhbrudar:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end