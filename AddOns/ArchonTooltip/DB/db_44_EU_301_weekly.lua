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
 local lookup = {'Monk-Windwalker','Warlock-Destruction','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Unknown-Unknown','Druid-Balance','Monk-Brewmaster','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','DeathKnight-Frost','Mage-Frost','Warrior-Fury','Priest-Shadow','Priest-Discipline','Mage-Arcane','Shaman-Elemental','DemonHunter-Vengeance','Evoker-Devastation',}; local provider = {region='EU',realm='Hellscream',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adeline:BAAALAAECgUICAAAAA==.',Ae='Aei:BAAALAAECgQIAQAAAA==.',Af='Afk:BAAALAAECgYICAAAAA==.',Ag='Agrajag:BAAALAADCgcIBwAAAA==.',Ai='Aib:BAAALAADCggIFgAAAA==.Aibelf:BAACLAAFFIEIAAIBAAMIhBzOAQAlAQABAAMIhBzOAQAlAQAsAAQKgR8AAgEACAiuJQEBAG0DAAEACAiuJQEBAG0DAAAA.',Al='Algisham:BAABLAAECoEYAAICAAgIeRPmIwARAgACAAgIeRPmIwARAgAAAA==.Alitakos:BAAALAAECgUICAAAAA==.Allwin:BAAALAAECgUICwAAAA==.Altran:BAAALAADCggICAAAAA==.Alzarinet:BAAALAAECgcIDwAAAA==.',Am='Amberlea:BAAALAAECgcICwAAAA==.',An='Anglaran:BAAALAAECgQIBQAAAA==.Anvar:BAAALAAECgIIAwAAAA==.Anyadelgado:BAAALAADCgMIAwAAAA==.',Ar='Aragan:BAAALAADCgUICAAAAA==.Arbalest:BAACLAAFFIEIAAIDAAMIYBXqBAAGAQADAAMIYBXqBAAGAQAsAAQKgR8AAgMACAjXI24LABEDAAMACAjXI24LABEDAAAA.Arcyan:BAAALAADCgQIBAAAAA==.Ardor:BAAALAADCggICAAAAA==.Argoz:BAAALAAECgMIAwAAAA==.Arnfinnson:BAAALAADCggICAAAAA==.Arssling:BAAALAAECgQICQAAAA==.Arywal:BAAALAAFFAIIBAAAAA==.',As='Asir:BAACLAAFFIEGAAIEAAMIcRSFBAD8AAAEAAMIcRSFBAD8AAAsAAQKgR8AAwQACAhrI1kFADMDAAQACAhrI1kFADMDAAUAAwihD4laAIgAAAAA.Asirdam:BAABLAAECoEVAAIGAAYI2ibYCwCjAgAGAAYI2ibYCwCjAgAAAA==.Asiru:BAAALAAECgUICQABLAAFFAMIBgAEAHEUAA==.',Au='Aurae:BAAALAAECgcIDgAAAA==.',Av='Avirondeloco:BAAALAAECgYICAAAAA==.',Az='Azhe:BAAALAAECgYICgAAAA==.',Ba='Badbox:BAAALAADCggICAAAAA==.Baldúr:BAAALAAECgYICwAAAA==.Bankebiff:BAAALAAECgYIEQAAAA==.Basíl:BAAALAADCgIIAgABLAADCgQIBAAHAAAAAA==.Batholith:BAAALAAECgcIEQAAAA==.Battlehenk:BAAALAADCgcIBwAAAA==.',Be='Beana:BAAALAADCggICAAAAA==.Beermonster:BAAALAAECgUICwAAAA==.Belverinia:BAAALAADCgYICwAAAA==.',Bi='Bini:BAACLAAFFIEIAAIIAAMIRSbLAQBQAQAIAAMIRSbLAQBQAQAsAAQKgR8AAggACAjAJmsAAI8DAAgACAjAJmsAAI8DAAAA.Binifromage:BAAALAAECgUICQABLAAFFAMICAAIAEUmAA==.',Bl='Blackdk:BAAALAADCgcICAAAAA==.Blindslice:BAAALAADCggICAAAAA==.Bloodaxe:BAAALAAECgUIBQAAAA==.Bluwind:BAAALAAECgIIBAAAAA==.',Bo='Bobby:BAAALAADCggIDwAAAA==.Bobleif:BAAALAADCgQIBAAAAA==.Boldragon:BAAALAAECgYICgAAAA==.Bolinha:BAAALAAECgYICwAAAA==.Bonlo:BAABLAAECoEZAAIJAAgISxtRBwB5AgAJAAgISxtRBwB5AgAAAA==.Boxie:BAAALAAECgYIBgAAAA==.Boótybandit:BAAALAADCgMIAwAAAA==.',Br='Brawler:BAAALAADCggICAAAAA==.Brutobjonsk:BAAALAAECgUICwAAAA==.',Bu='Bubbleguts:BAAALAADCgcICwAAAA==.Bubblun:BAAALAAECgUICAAAAA==.Bunji:BAAALAADCggICwAAAA==.Buyukaltay:BAAALAAECgMIAwABLAAECgYIEgAHAAAAAA==.',['Bà']='Bàbaluba:BAAALAADCgYIBgAAAA==.',['Bé']='Béany:BAAALAAECgIIAgAAAA==.',['Bë']='Bërserk:BAAALAADCggIEAABLAAECgQIBAAHAAAAAA==.',Ca='Camonk:BAABLAAECoElAAMKAAgItBlVCgBHAgAKAAgItBlVCgBHAgABAAYIaRYyGACnAQAAAA==.',Cc='Ccreuss:BAAALAADCggIFwAAAA==.',Ce='Ceralix:BAAALAAECgIIBAAAAA==.',Ch='Changa:BAAALAADCggICgAAAA==.Cherry:BAAALAAECggICAAAAA==.Chumaka:BAAALAAECgIIAwAAAA==.',Ci='Cindarella:BAAALAADCgcIBwAAAA==.',Co='Comet:BAAALAADCggICAAAAA==.',Cr='Crab:BAAALAADCggIDwAAAA==.Craggle:BAAALAAECgMIAwAAAA==.',Cy='Cyrogen:BAAALAAECgYICgAAAA==.',Da='Daniael:BAAALAAECgMIAwAAAA==.Darkjuri:BAAALAADCgQIBAAAAA==.Darladin:BAAALAADCgEIAQABLAADCggICAAHAAAAAA==.Darthraxxion:BAAALAAECgcIDwAAAA==.Daruude:BAAALAADCgUIBQAAAA==.',De='Deathleif:BAAALAAECgYIBgAAAA==.Deathlyblade:BAAALAAECgIIAwAAAA==.Deathpulse:BAAALAAECgEIAQAAAA==.Deathtankz:BAAALAADCgcIBwAAAA==.Decailin:BAAALAAECgMIAwAAAA==.Definitely:BAAALAADCggIBwABLAAECgMICQAHAAAAAA==.Demonzac:BAAALAAECggICgAAAA==.Dezrath:BAAALAAECgUIBQAAAA==.',Di='Diedtrying:BAAALAADCgYICgAAAA==.Dimz:BAAALAAECgQICQAAAA==.Dique:BAAALAADCgMIAwAAAA==.',Dm='Dmoc:BAAALAAECgcIDQAAAA==.',Do='Domienator:BAAALAAECgcICgAAAA==.Dottingkalle:BAAALAADCgcIBwAAAA==.',Dr='Dragleif:BAAALAAECgUIBQAAAA==.Draigor:BAAALAAECgUICwAAAA==.Drakkrim:BAAALAADCgcICgAAAA==.Draksir:BAAALAAECgUIBQABLAAFFAMIBgAEAHEUAA==.Dralro:BAACLAAFFIEIAAMLAAMI8BV/BwC+AAALAAIIXRR/BwC+AAAMAAII4Q02BgCNAAAsAAQKgR8AAwwACAjZG38EAJkCAAwACAiZGn8EAJkCAAsABwgMFmAfAL8BAAAA.Draupnir:BAAALAADCgYICgAAAA==.Draven:BAAALAADCgYIBgAAAA==.Draxal:BAAALAADCgQIBQAAAA==.Drayden:BAAALAADCggIDwAAAA==.Dreamstraza:BAAALAAECgQIBAAAAA==.Drincredible:BAAALAADCgcIBwAAAA==.Drippingfang:BAAALAAECgcIDgAAAA==.',['Dæ']='Dæmonpasta:BAAALAADCgUIBQAAAA==.',Ei='Eidolon:BAAALAADCgcIBwAAAA==.',El='Eldanhar:BAAALAAECgIIBAAAAA==.Elemintt:BAAALAADCggICAABLAAECgYICAAHAAAAAA==.Elimion:BAAALAADCgYIBgAAAA==.Ellytrimix:BAAALAAECgYIDQAAAA==.Eluizu:BAAALAADCggIDAAAAA==.Elydor:BAAALAAECgIIAgAAAA==.',Er='Erigor:BAAALAAFFAIIAgAAAA==.Erinael:BAAALAADCgcICgAAAA==.Ernest:BAAALAADCgMIAwAAAA==.',Es='Esrefpasali:BAAALAAECgMIBAABLAAECgYIEgAHAAAAAA==.',Et='Ethredus:BAAALAAECgUIBwAAAA==.',Ev='Eveagora:BAAALAAECgIIAgAAAA==.',Fa='Faythe:BAAALAADCgYIBgAAAA==.',Fi='Fiskerenfisk:BAAALAAECgYIEAAAAA==.Fisky:BAAALAAECgYICgABLAAECgYIEAAHAAAAAA==.',Fl='Flamborambo:BAAALAADCgIIAgAAAA==.Flou:BAAALAAECgIIAgAAAA==.',Fo='Forsakenthor:BAAALAAECgMIAwAAAA==.',Fr='Frésh:BAAALAADCgYIBgAAAA==.',Ga='Galbraithh:BAAALAADCgQIBAAAAA==.Gamonius:BAAALAADCgUIBQAAAA==.',Ge='Genohacker:BAAALAAECgMICQAAAA==.',Gh='Ghaross:BAAALAAECgYIBgAAAA==.',Gl='Gleam:BAABLAAECoEXAAINAAcIQhl8GQAGAgANAAcIQhl8GQAGAgAAAA==.Glulir:BAAALAAECgYICwAAAA==.',Gw='Gwen:BAAALAADCggIEwAAAA==.Gwendolinee:BAAALAAECgUICwAAAA==.Gwendydd:BAAALAADCggIDQAAAA==.Gweniver:BAAALAADCgcIDAAAAA==.',Ha='Hashira:BAAALAADCgUIBQAAAA==.',He='Helrezza:BAABLAAECoEcAAMNAAgI3h3zBgDJAgANAAgI3h3zBgDJAgAIAAMIChSbRgDEAAAAAA==.Hexer:BAAALAADCgQIBAAAAA==.Hexious:BAABLAAECoEXAAIOAAcINhLGRADFAQAOAAcINhLGRADFAQAAAA==.',Hi='Hivix:BAAALAAECgYIDQABLAAECggIIAAPANojAA==.',Ho='Hoffyshammy:BAAALAADCgcIBwAAAA==.Hoofski:BAAALAAECgMICQAAAA==.Hoperock:BAAALAAECgcIDgAAAA==.Hotz:BAAALAAECgYIBwAAAA==.',['Hé']='Héx:BAAALAAECgMIBQAAAA==.',Ic='Icefox:BAAALAADCggIFgAAAA==.Icegoblin:BAAALAAECgQIDAAAAA==.',Il='Ilran:BAAALAADCgYIEgAAAA==.',Im='Imptias:BAAALAADCgIIAgAAAA==.',In='Innovision:BAAALAADCggICQABLAAECgYIDAAHAAAAAA==.',Ir='Iriacynthe:BAAALAAECgMIAwAAAA==.Irishbolt:BAAALAADCgYIBgAAAA==.Irishpi:BAAALAADCggICAABLAADCggIDAAHAAAAAA==.Irnbru:BAAALAAECgYICgAAAA==.Irnbruxtra:BAAALAAECgEIAQAAAA==.',Is='Isiatrasil:BAAALAAECgEIAQAAAA==.Isithralith:BAAALAADCgcIDwAAAA==.',Ja='Jakozzle:BAAALAAECgcIEQAAAA==.Jarrupala:BAAALAAECgYICgAAAA==.',Je='Jeia:BAAALAADCgcIBwAAAA==.',Ji='Jiegerbomb:BAAALAAECgYIEgAAAA==.Jinot:BAAALAAECggIEAAAAA==.Jinzo:BAAALAAECgYIBgAAAA==.',Jo='Johanneke:BAAALAAECgYIDAAAAA==.Josefu:BAAALAAECgMIAwAAAA==.',Ju='Jui:BAAALAADCggICAAAAA==.',Ka='Kaelyn:BAAALAAECgMIBQAAAA==.Kailiyah:BAAALAAECgMIAwAAAA==.Kaliopy:BAAALAADCggIEAAAAA==.Kaliopybg:BAAALAAECgQIBwAAAA==.Kaliopydk:BAAALAADCggIEwAAAA==.Kalokua:BAAALAAECgMIBQAAAA==.Kazama:BAAALAAECgMIBAABLAAECgMIBQAHAAAAAA==.',Ke='Keeli:BAAALAADCgcIBwAAAA==.Kennytheger:BAAALAADCggICAAAAA==.',Ki='Killerdemon:BAAALAAECgYICgAAAA==.',Kn='Knóx:BAAALAAECgcIEQAAAA==.Knôx:BAAALAADCgQIBAAAAA==.',Kr='Krazat:BAAALAAECgYICAAAAA==.Krier:BAAALAADCggICAAAAA==.Kronin:BAAALAAECgEIAQAAAA==.',Ku='Kusynlig:BAAALAADCgcIBwABLAAECgYIEQAHAAAAAA==.',Ky='Kyng:BAAALAAECgcIDgAAAA==.Kyubiistraza:BAAALAAECgMICQAAAA==.',La='Lattios:BAAALAAECgYICwABLAADCgQIBAAHAAAAAA==.',Le='Lebellel:BAAALAAECgYICgAAAA==.Lehrel:BAAALAADCgcIBwAAAA==.Leopal:BAAALAAECgIIAgAAAA==.Leousan:BAAALAAECgUIBQAAAA==.Lethalbacon:BAAALAADCgYIBgAAAA==.',Lh='Lhydia:BAAALAADCggIDwAAAA==.',Li='Lilit:BAABLAAECoEcAAICAAgICB66DwC+AgACAAgICB66DwC+AgAAAA==.Linked:BAAALAAECgYIDAAAAA==.Liontarakis:BAAALAAECgYIDwAAAA==.',Lo='Lockleif:BAAALAADCggICAAAAA==.Locohunter:BAAALAAECggIBwAAAA==.Loftus:BAABLAAECoEUAAMEAAcIsxcZNQC5AQAEAAcIqxUZNQC5AQAFAAUIWBAPQgAOAQAAAA==.Longeria:BAAALAAECgMICAAAAA==.Lozz:BAAALAADCggICAAAAA==.Lozzarino:BAAALAAECgUICgAAAA==.',Lu='Lunjun:BAAALAADCgcIBwAAAA==.Lux:BAAALAADCgcIBwAAAA==.',Ly='Lyrianna:BAAALAAECgUIAwAAAA==.Lysara:BAABLAAECoEUAAIQAAcIZwg8OgBxAQAQAAcIZwg8OgBxAQAAAA==.Lyxea:BAAALAAECgUIBwAAAA==.',['Lé']='Lémon:BAAALAAECggIEwAAAA==.',Ma='Madaline:BAAALAAECgIIBAAAAA==.Madrisa:BAAALAAECgMIAwABLAAFFAMIBgAEAHEUAA==.Madwell:BAAALAAECgYICwAAAA==.Maffi:BAAALAADCggICAAAAA==.Magí:BAAALAAECgQIBgAAAA==.Marjolein:BAAALAAECgcIEQAAAA==.Masashi:BAAALAADCggIDwAAAA==.Mastércastér:BAAALAAECgMIBAAAAA==.Maxariun:BAAALAAECgUICAAAAA==.Maxímus:BAAALAAECgQICQAAAA==.',Mc='Mcgrumpy:BAAALAAECgYIEQAAAA==.Mcivy:BAABLAAECoEYAAIGAAgIkgGSfgCvAAAGAAgIkgGSfgCvAAAAAA==.Mcpie:BAABLAAECoEXAAMRAAcIzx54EwBwAgARAAcIzx54EwBwAgASAAIIcxBVGQB6AAAAAA==.',Me='Melt:BAAALAADCgUIBQAAAA==.',Mh='Mhdk:BAAALAAECggICAAAAA==.',Mi='Mikusiek:BAAALAAECgMIAwAAAA==.Milim:BAAALAAECgQICQAAAQ==.Misteá:BAABLAAECoEXAAIKAAcIeRnDDQAFAgAKAAcIeRnDDQAFAgAAAA==.',Mo='Moltres:BAAALAADCggIGgAAAA==.Mooniania:BAAALAAFFAIIAgABLAAFFAMICAANAF4kAA==.Morphmage:BAAALAADCgMIAwABLAAECgcIEQAHAAAAAA==.Morwenys:BAAALAADCggIDQAAAA==.Motto:BAACLAAFFIEGAAISAAMIeQlZAADZAAASAAMIeQlZAADZAAAsAAQKgRcAAhIACAgxHPABAKICABIACAgxHPABAKICAAAA.',['Mé']='Méatshield:BAAALAADCggIEAABLAAECgQIBgAHAAAAAA==.',['Mí']='Míthrax:BAAALAADCgMIAwAAAA==.',['Mø']='Møhammad:BAAALAAECgEIAQABLAAECgYIEQAHAAAAAA==.',Na='Naleya:BAAALAADCggICAAAAA==.Natvera:BAAALAAECgYIAQAAAA==.',Ne='Neptun:BAAALAAECgQIBgAAAA==.Nerabus:BAAALAADCgQIBAAAAA==.Neriana:BAAALAAECgYICgAAAA==.Nerök:BAAALAADCgcIBwAAAA==.Nesyrre:BAAALAADCgYIBgAAAA==.Nethertank:BAAALAAECgMIBgAAAA==.',Ni='Niccii:BAAALAADCgIIAgAAAA==.Nightmoon:BAACLAAFFIEIAAINAAMIXiT+AQBBAQANAAMIXiT+AQBBAQAsAAQKgR8AAg0ACAj9JFYBAEoDAA0ACAj9JFYBAEoDAAAA.Nightsorrow:BAAALAAECgUIBgAAAA==.Ninaxx:BAAALAAECgYICAAAAA==.Nineoneone:BAAALAAECgMIBgAAAA==.Ninjitstu:BAAALAADCgcIBwABLAAECgYICgAHAAAAAA==.Nivix:BAABLAAECoEgAAIPAAgI2iOvAgA6AwAPAAgI2iOvAgA6AwAAAA==.',No='Norgus:BAAALAAECgUIBwAAAA==.Nothinghood:BAAALAAECgIIAgAAAA==.Notto:BAAALAADCggIDAABLAAFFAMIBgASAHkJAA==.',Nu='Nurkal:BAAALAADCgcICAAAAA==.',Ny='Nyria:BAAALAADCgcIBQAAAA==.',['Nè']='Nèd:BAAALAAECgcIDAAAAA==.',['Né']='Néédmanas:BAAALAADCggICwAAAA==.',['Në']='Nëverlucky:BAAALAADCgQIBAAAAA==.',['Nÿ']='Nÿsa:BAAALAAECgYIEgAAAA==.',Od='Oddbal:BAAALAADCgcIDgAAAA==.',Ol='Olivianne:BAAALAADCggIBgAAAA==.Olodos:BAAALAAECgIIBAAAAA==.',Om='Ompw:BAAALAADCggIEAAAAA==.',On='One:BAAALAAECgYIBwAAAA==.Onyxo:BAAALAAECgcIBwAAAA==.',Oo='Ooga:BAAALAADCggICAAAAA==.',Op='Opsie:BAAALAAECgYIDQAAAA==.',Ot='Otaval:BAAALAADCgQIBAAAAA==.',Ou='Outcome:BAAALAAECgUICQAAAA==.',Ov='Ovock:BAAALAAECgcIDQAAAA==.',Pa='Padonk:BAAALAAECgMICQAAAA==.Paimei:BAAALAADCgEIAQAAAA==.Pauldirac:BAAALAADCggIFAAAAA==.',Ph='Phoneman:BAAALAAECgEIAQAAAA==.',Pi='Pinkfury:BAAALAAECgYIEQAAAA==.Pittepatt:BAAALAADCgcIBwAAAA==.',Pl='Pleather:BAAALAADCgMIAgAAAA==.',Po='Pointillism:BAAALAAECgQIBAAAAA==.',Pr='Praxithea:BAAALAAECgIIAgAAAA==.',Ps='Psyla:BAAALAADCgYICgAAAA==.Psyló:BAAALAADCgQIBAAAAA==.',Pu='Puffy:BAAALAAECgYIEwAAAA==.',['Pí']='Pírat:BAABLAAECoEZAAIEAAgI4hoHEwCXAgAEAAgI4hoHEwCXAgAAAA==.',Qu='Quezalacotol:BAAALAADCgYICgAAAA==.',Ra='Rarion:BAAALAAECgIIAwAAAA==.Rasberry:BAAALAADCggICAAAAA==.Rasillon:BAABLAAECoEYAAITAAcICQrxZAAkAQATAAcICQrxZAAkAQAAAA==.Rastyu:BAAALAAECgUICwAAAA==.Rautakilpi:BAAALAADCgcIBwAAAA==.Ravanaa:BAAALAAECgcIDAAAAA==.Ravoy:BAAALAAECgIIAgAAAA==.Ravven:BAAALAAECgIIAgAAAA==.Rayneko:BAAALAAECgcIDQAAAA==.',Re='Reformed:BAAALAAECggICgAAAA==.Regla:BAAALAADCgcIBwAAAA==.Relent:BAAALAADCgcIBwAAAA==.Renewlock:BAABLAAECoEXAAICAAcI0x1lHABLAgACAAcI0x1lHABLAgAAAA==.Renji:BAAALAAECggICgAAAA==.Rexes:BAAALAAECgYIBgAAAA==.',Ro='Rockdoctor:BAAALAAECgUICwAAAA==.Rolicia:BAAALAADCggIEwAAAA==.Rosie:BAAALAAECgUICQAAAA==.Rothric:BAAALAAECgIIAgAAAA==.',Ru='Rumendh:BAAALAADCgcIBwAAAA==.Rumleskaft:BAAALAAECgQIBAAAAA==.',Sa='Sabatonv:BAAALAADCgcICgAAAA==.Sadelra:BAAALAAECgEIAQAAAA==.Saeko:BAAALAAECgIIBAAAAA==.Sagar:BAAALAAECgYIBgAAAA==.Salamander:BAAALAADCggICwABLAAECgIIBAAHAAAAAA==.Salvaron:BAAALAAECgYICwAAAA==.Saphiya:BAAALAAECgQICAAAAA==.Saphíra:BAAALAADCgYIBgAAAA==.Sas:BAAALAAECgcIDQAAAA==.Sasi:BAAALAADCgcIBwAAAA==.',Se='Selavy:BAAALAADCgIIAgAAAA==.Sensi:BAAALAADCgMIAwAAAA==.Sensibeam:BAAALAAECgQIBAAAAA==.Sensiuwu:BAACLAAFFIEIAAIRAAMIzSADBAAbAQARAAMIzSADBAAbAQAsAAQKgSAAAhEACAg5JskAAIIDABEACAg5JskAAIIDAAAA.Serrá:BAAALAAECgMIAwAAAA==.Sertoi:BAAALAAECgMIAwAAAA==.',Sh='Shalashovka:BAAALAAECgMIAwAAAA==.Shamandurex:BAAALAADCgcIBwAAAA==.Shambollic:BAAALAAECgUICwAAAA==.Shammyberry:BAACLAAFFIEIAAMUAAMITAYaCADbAAAUAAMITAYaCADbAAAGAAEIkgGxIAAvAAAsAAQKgR8AAxQACAj/HvMPAK4CABQACAj/HvMPAK4CAAYAAQg4CGyrACkAAAAA.Sheeshdormu:BAAALAAECgIIAgAAAA==.Sheshock:BAAALAAECgQICQAAAA==.Shinkz:BAAALAAECgcICAAAAA==.Shronky:BAAALAADCggIHgABLAAECgMICQAHAAAAAA==.',Si='Sinimonk:BAAALAADCggICAAAAA==.Sisnoir:BAAALAADCgQIBAAAAA==.',Sk='Skullsmasha:BAAALAADCgQICAAAAA==.',Sl='Slubby:BAAALAAECggIDQAAAA==.',Sm='Smäsh:BAAALAADCggIEwAAAA==.',So='Solaire:BAAALAADCgEIAQAAAA==.Sonjad:BAAALAADCgQIBAAAAA==.Sosarian:BAAALAAECgMIBQAAAA==.Sotsji:BAAALAAECgUICQABLAAECgYIDAAHAAAAAA==.Souru:BAABLAAECoEYAAIOAAgInCFREQDQAgAOAAgInCFREQDQAgAAAA==.Soá:BAAALAADCggIDQAAAA==.',Sp='Spartarion:BAAALAAECgYIDQAAAA==.Spicytofu:BAABLAAECoEZAAIVAAgIVSUdAQBXAwAVAAgIVSUdAQBXAwAAAA==.Spiokra:BAAALAAECgEIAQAAAA==.',St='Stars:BAAALAAECgYICwAAAA==.Stjernekrem:BAAALAADCgcIBwAAAA==.Storbums:BAAALAADCgUIBQAAAA==.Stormfang:BAAALAADCggIEAAAAA==.Stormspirit:BAAALAAECgMIAwAAAA==.Strel:BAAALAADCggICAAAAA==.Stu:BAAALAADCgMIAwABLAAECgYICgAHAAAAAA==.Studru:BAAALAAECgYICgAAAA==.Stuehstrasza:BAAALAADCggICAABLAAECgYICgAHAAAAAA==.Stuéh:BAAALAAECgYIBgABLAAECgYICgAHAAAAAA==.',Sw='Swagowner:BAAALAAFFAIIAgAAAA==.',Sy='Syphix:BAAALAAECgMIAwAAAA==.',Sz='Szuzsika:BAAALAAECgYIBgAAAA==.',Ta='Takala:BAAALAAECgIIAgAAAA==.Talis:BAAALAADCggIEAAAAA==.Tatalorcoie:BAAALAAFFAIIBAAAAA==.Taxus:BAAALAAECgUICgAAAA==.',Te='Tenzin:BAAALAAECgIIAwAAAA==.Teodora:BAAALAAECgEIAQAAAA==.Terrormaker:BAAALAADCgQIBAAAAA==.',Th='Thoka:BAAALAAECgcIDQAAAA==.Throngayle:BAAALAAECgYICwAAAA==.',Ti='Tikal:BAAALAAECgQIBgAAAA==.',To='Toothless:BAAALAAECgUICgAAAA==.Totemherm:BAAALAAECgQIBAAAAA==.',Tr='Treehuggre:BAAALAAECgYICgAAAA==.Trelamenos:BAAALAADCgEIAQAAAA==.',Tu='Turidemon:BAAALAADCgcICwAAAA==.Tuskka:BAAALAADCgYIBgAAAA==.',Tw='Twibble:BAAALAADCgYIBgAAAA==.',Uc='Ucharik:BAAALAAECgMICAAAAA==.',Ug='Ugliebuglie:BAAALAAECgQIBAABLAAECgYIDAAHAAAAAA==.',Uk='Ukumbe:BAAALAADCgcIBwAAAA==.',Ul='Ulthar:BAAALAADCggIDQAAAA==.',Un='Unfulfilled:BAAALAAECgcICgAAAA==.Unskilledkek:BAAALAAECgMIBQAAAA==.',Ur='Uradrel:BAAALAAECgcIDwAAAA==.',Va='Valix:BAAALAADCggICAABLAAECgcIEQAHAAAAAA==.Vallis:BAAALAAECgQIBgAAAA==.Vany:BAAALAAECgMIBAAAAA==.',Ve='Velinha:BAAALAADCggICAABLAAECgYICwAHAAAAAA==.Veszély:BAAALAADCgUIBQAAAA==.',Vi='Vibedk:BAAALAADCgYIBgAAAA==.Vind:BAAALAADCggIHQAAAA==.Violety:BAAALAADCggIDgAAAA==.Viridia:BAAALAAECgcICwAAAA==.',Vk='Vkyra:BAAALAADCggIDwAAAA==.',Vo='Vorkath:BAACLAAFFIEIAAIWAAMIVyFTAwAxAQAWAAMIVyFTAwAxAQAsAAQKgR8AAhYACAguJTQBAGwDABYACAguJTQBAGwDAAAA.Voxarria:BAAALAADCgcIDQABLAAECgEIAQAHAAAAAA==.',Vu='Vulpan:BAAALAAECgIIBAAAAA==.',Wa='Waendor:BAAALAADCggIDAAAAA==.Wannebe:BAAALAAECgMIBQAAAA==.Warlead:BAAALAAECgYIBgAAAA==.Wasa:BAAALAADCgcIBwAAAA==.',Wh='Whyrm:BAAALAADCgEIAQAAAA==.',Wo='Wonderpray:BAAALAAECgMIAwAAAA==.',Wr='Wrynn:BAAALAAECgIIBAAAAA==.',Wy='Wyran:BAAALAADCgQIBAAAAA==.Wyriaz:BAAALAAECgMIBAAAAA==.',Xe='Xelmettria:BAAALAAECgcIDgAAAA==.',Xi='Xiaara:BAAALAAECgYICAAAAA==.Xiaolongbao:BAAALAAECgEIAwAAAA==.Xiora:BAAALAAECgcIDAAAAA==.',Xl='Xlight:BAAALAAECgIIBAAAAA==.',['Xã']='Xãlatath:BAAALAADCgcIBwAAAA==.',Ya='Yagodkin:BAAALAADCgcIBwAAAA==.Yakara:BAAALAADCggICAAAAA==.',Yo='Yonhealen:BAACLAAFFIEIAAIOAAMIxyboAgBeAQAOAAMIxyboAgBeAQAsAAQKgR8AAg4ACAjyJgsAAKADAA4ACAjyJgsAAKADAAAA.',Ys='Ysrana:BAAALAADCgEIAQAAAA==.',Yu='Yuzral:BAABLAAECoEXAAIDAAcIcBggNAACAgADAAcIcBggNAACAgAAAA==.',Yv='Yva:BAAALAAECgUICwAAAA==.',Za='Zanisn:BAAALAAECggIDwAAAA==.Zarquon:BAAALAADCgcIBwAAAA==.',Ze='Zeusbeast:BAAALAADCggIDAAAAA==.',Zg='Zgykke:BAAALAAECgEIAQAAAA==.',Zi='Zinwei:BAAALAAECgUICAAAAA==.',Zo='Zoilo:BAAALAAECgIIAgAAAA==.',Zu='Zubunk:BAAALAAECgYICgAAAA==.Zuldark:BAAALAADCgcIBwAAAA==.Zulkas:BAAALAAECgIIAgAAAA==.',['Æn']='Ænerox:BAAALAAECgEIAQAAAA==.',['Íl']='Íllithane:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end