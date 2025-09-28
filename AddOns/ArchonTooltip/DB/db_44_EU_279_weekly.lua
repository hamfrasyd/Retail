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
 local lookup = {'Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Warlock-Destruction','DeathKnight-Frost','Rogue-Assassination','Hunter-Marksmanship','Mage-Arcane','Shaman-Restoration','Paladin-Protection','Warrior-Arms','Mage-Frost','Druid-Restoration','DeathKnight-Blood','Druid-Feral','Shaman-Elemental','Monk-Windwalker','Unknown-Unknown','Druid-Guardian','Paladin-Retribution','Warrior-Fury','Warrior-Protection','Druid-Balance','DeathKnight-Unholy','Paladin-Holy','Priest-Holy','Priest-Shadow','Warlock-Demonology','Monk-Mistweaver','Priest-Discipline','Hunter-BeastMastery','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Outlaw','Warlock-Affliction',}; local provider = {region='EU',realm='Deathwing',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abashka:BAAALAAECgMIBgAAAA==.',Ad='Aderan:BAABLAAECoEkAAMBAAgIWhJAEQDjAQABAAgIWhJAEQDjAQACAAEIbAT7XgAWAAAAAA==.',Ae='Aesthedh:BAABLAAECoEpAAIDAAgIbxQsVQDyAQADAAgIbxQsVQDyAQAAAA==.',Ak='Akaame:BAAALAAECgEIAQAAAA==.Akonkkagva:BAAALAAECgYICAAAAA==.',Al='Aleras:BAAALAADCggICAAAAA==.Allura:BAAALAAECggIEgAAAA==.Alvilda:BAAALAAECgYIBgABLAAFFAMIBwAEANMKAA==.',An='Anabelle:BAAALAAECgIIAgAAAA==.Analgia:BAAALAAECgIIAgAAAA==.Andoomi:BAABLAAECoETAAIFAAgIchgqPABdAgAFAAgIchgqPABdAgABLAAFFAQICAADAI0RAA==.Angelica:BAAALAAECgcIDgAAAA==.Angerdx:BAAALAADCggICAAAAA==.Annarion:BAABLAAECoEVAAIGAAYIuwuYOwBSAQAGAAYIuwuYOwBSAQAAAA==.Anthisa:BAAALAAECgUIBQAAAA==.',Ao='Aongusha:BAABLAAECoEUAAIHAAgIvRKCMADjAQAHAAgIvRKCMADjAQAAAA==.',Ap='Apricity:BAAALAAECgQIBQAAAA==.',Ar='Arbores:BAAALAAECgMIAwAAAA==.Archdruid:BAAALAADCggICAAAAA==.Arckraptor:BAAALAAECgMIBAAAAA==.Arkie:BAABLAAECoErAAICAAgIwxa1FgBTAgACAAgIwxa1FgBTAgAAAA==.Arröwshot:BAAALAADCgcIBwAAAA==.Arwolia:BAAALAAECgEIAQAAAA==.Aryndyr:BAAALAAECgYIDAAAAA==.',As='Ascensionism:BAAALAAECgYICAAAAA==.Asdrybal:BAAALAADCgcIBwABLAAFFAMIBgAIAP4OAA==.Asztar:BAABLAAECoEjAAIEAAgIKiXTBQBZAwAEAAgIKiXTBQBZAwAAAA==.',At='Atia:BAAALAAECgcICgABLAAFFAMICgAJACkWAA==.Atraxia:BAAALAAECgYIEwAAAA==.',Au='Auburnfury:BAABLAAECoEcAAIHAAcIsRCZQwCJAQAHAAcIsRCZQwCJAQAAAA==.Auwyn:BAABLAAECoEbAAIKAAcIDhs4FQAYAgAKAAcIDhs4FQAYAgAAAA==.',Aw='Awake:BAAALAADCgUIBQABLAAFFAUIBwADAFQbAA==.',Ay='Ayzen:BAAALAAECgYICwAAAA==.',Az='Azirel:BAAALAADCggIDwAAAA==.Azryâm:BAAALAADCgcIBwAAAA==.',Ba='Balak:BAABLAAECoEYAAILAAcIQQ51EQCXAQALAAcIQQ51EQCXAQAAAA==.Barrdi:BAABLAAECoEYAAMIAAgIzBiGOwA3AgAIAAgIWBWGOwA3AgAMAAYI0hYXNgBwAQAAAA==.',Be='Bearcowtree:BAABLAAECoEWAAINAAgIRhkJHQBRAgANAAgIRhkJHQBRAgAAAA==.Bearhexile:BAAALAAECgIIAgABLAAECggIHwAFAIcbAA==.Bearied:BAABLAAECoEfAAMFAAgIhxsiSAA5AgAFAAgIhxsiSAA5AgAOAAII+hZzMQCGAAAAAA==.Beastworm:BAABLAAECoEgAAIPAAgIhSEfBQD6AgAPAAgIhSEfBQD6AgAAAA==.Beefsaucer:BAABLAAECoEZAAMPAAcIgxbLEwDtAQAPAAcIgxbLEwDtAQANAAIIOQ00pwBTAAAAAA==.Bergzdh:BAAALAAECgcIBwABLAAECggIJwAQAPgWAA==.Bergzdk:BAAALAAECgMIBAABLAAECggIJwAQAPgWAA==.Bergzmage:BAAALAADCgYIBgABLAAECggIJwAQAPgWAA==.Bergzsham:BAABLAAECoEnAAIQAAgI+Bb+KQA+AgAQAAgI+Bb+KQA+AgAAAA==.Berserkèr:BAAALAAECgcIDQAAAA==.Beurko:BAAALAADCgEIAQAAAA==.Bezla:BAAALAADCggICAAAAA==.',Bi='Bigholes:BAAALAAECgYIBgAAAA==.Bigtimmy:BAAALAADCggICAAAAA==.Bildrulle:BAABLAAECoEgAAINAAgICCNVBQAlAwANAAgICCNVBQAlAwAAAA==.Billan:BAAALAADCggICAAAAA==.Bionaire:BAAALAADCgcIBgABLAAECgYIFgARAEgiAA==.',Bl='Blacksnake:BAAALAADCgIIAgABLAAECgEIAQASAAAAAA==.Bladeedge:BAAALAAECggIDgAAAA==.Bledgar:BAABLAAECoEYAAIOAAgIRQDyQgAUAAAOAAgIRQDyQgAUAAAAAA==.Blindfurywar:BAAALAAECgQIBAAAAA==.Bloodberry:BAABLAAECoEoAAITAAgIyiOPAQA+AwATAAgIyiOPAQA+AwAAAA==.Blothr:BAAALAAECgYICQAAAA==.Blåost:BAAALAAECgEIAQAAAA==.',Bo='Bobi:BAAALAAECggIEAABLAAFFAIIAgASAAAAAA==.Bongowa:BAAALAAECgcIEQAAAA==.',Br='Bradzilla:BAAALAAECgIIAgAAAA==.Brahzilla:BAAALAADCgQIBAAAAA==.Brossezmode:BAACLAAFFIEFAAIOAAIIxiGrBgDHAAAOAAIIxiGrBgDHAAAsAAQKgRYAAg4ACAi2If0IAKACAA4ACAi2If0IAKACAAAA.Brossio:BAAALAAECgYIDAABLAAFFAIIBQAOAMYhAA==.',Bu='Burnlight:BAAALAADCggIDgAAAA==.',['Bá']='Báné:BAAALAAECgEIAQAAAA==.',['Bä']='Bäddie:BAAALAAECgUICQAAAA==.',['Bé']='Bécks:BAAALAAECgQICQAAAA==.',Ca='Cactuslux:BAAALAAECgUIBQAAAA==.Calsy:BAAALAADCgUIBAAAAA==.Catchway:BAAALAADCgQIBAAAAA==.',Ch='Chenoa:BAAALAADCggICQAAAA==.Chikenugges:BAAALAAECgIIAgAAAA==.Chizbee:BAAALAAECgcIDgAAAA==.Chras:BAACLAAFFIEKAAIKAAMI+Rp9BAD2AAAKAAMI+Rp9BAD2AAAsAAQKgSsAAwoACAhXIwoGAP0CAAoACAgaIwoGAP0CABQAAggxH7P4ALQAAAAA.Chrascor:BAAALAAECgcIEwABLAAFFAMICgAKAPkaAA==.Chrasivae:BAAALAADCggIDgABLAAFFAMICgAKAPkaAA==.Chrastina:BAAALAAECgIIAgABLAAFFAMICgAKAPkaAA==.Chrasyrax:BAAALAADCggICAABLAAFFAMICgAKAPkaAA==.Chrazen:BAAALAADCgQIBAAAAA==.Chrislee:BAABLAAECoEkAAITAAcINhgvCwDvAQATAAcINhgvCwDvAQAAAA==.Chronios:BAABLAAECoEbAAIUAAYIHBlPdADKAQAUAAYIHBlPdADKAQAAAA==.Chtulhu:BAAALAAECgYIEgABLAAFFAIIBwADAAQeAA==.Chucknourish:BAAALAAECgQIBAAAAA==.',Ci='Cifer:BAACLAAFFIEIAAMVAAII8COqEgDWAAAVAAII8COqEgDWAAALAAEIzBCfBgBLAAAsAAQKgSsAAxUACAh0JPwIAEEDABUACAg2JPwIAEEDAAsABQjyIIsNANcBAAAA.Ciphery:BAAALAADCgYIBgAAAA==.',Cl='Clarity:BAAALAAECgMIAwAAAA==.',Co='Colours:BAACLAAFFIEHAAIIAAMI5x+UIgC1AAAIAAMI5x+UIgC1AAAsAAQKgS0AAggACAh0JYYEAGEDAAgACAh0JYYEAGEDAAAA.Composter:BAAALAADCggICQAAAA==.Coronilia:BAACLAAFFIEGAAMVAAIIxBX+IQCcAAAVAAIIBhH+IQCcAAAWAAEI4Q6eHwA9AAAsAAQKgRcAAxUACAjpHGQpAGACABUACAgxHGQpAGACABYABgh8EyU1AGoBAAAA.',Cr='Crancky:BAAALAADCgcIBwAAAA==.Crownilla:BAACLAAFFIEJAAICAAII6xvcDgCtAAACAAII6xvcDgCtAAAsAAQKgRkAAwIABwjXGaQfAPoBAAIABwjXGaQfAPoBAAEABghvClIiAAwBAAAA.',Ct='Cthlolo:BAAALAAECggIEAAAAA==.Cthroro:BAAALAAECggIBwAAAA==.Cthvijaager:BAAALAAECggICAAAAA==.',Cu='Cutter:BAAALAAECgMIBAAAAA==.',Cy='Cyphër:BAAALAAECgEIAQAAAA==.',['Cô']='Côcô:BAAALAAECgQIBAABLAAFFAIIBgANAKYeAA==.',Da='Dacitrone:BAAALAADCgQIBAAAAA==.Dacresha:BAAALAADCgMIAwAAAA==.Dannal:BAAALAAECgcIBwABLAAFFAIIBgAQAFwdAA==.Dantez:BAAALAAECgQIBwAAAA==.Darkanzali:BAAALAAECgYICAAAAA==.Darkcurse:BAAALAAECggIDQAAAA==.Darthness:BAAALAADCgYIBwAAAA==.Dashilong:BAAALAADCggICAAAAA==.',De='Deadpull:BAAALAAECgIIAgAAAA==.Deathmandom:BAAALAADCgcIBwAAAA==.Deathon:BAAALAAECgIIAgAAAA==.Deathrunner:BAAALAAECgMIAwAAAA==.Deathtasy:BAAALAAECgYIDQAAAA==.Deedgenutss:BAAALAAECgMIAwAAAA==.Demke:BAAALAADCgMIAwAAAA==.Demondice:BAAALAAECgQICAAAAA==.Demonrat:BAABLAAECoEaAAIDAAgIngLL5wCVAAADAAgIngLL5wCVAAAAAA==.Derf:BAAALAADCgUIBQAAAA==.Devilie:BAAALAAECgYICwABLAAECggIDgASAAAAAA==.Devyata:BAABLAAECoEkAAIJAAgI8CAhDQDjAgAJAAgI8CAhDQDjAgAAAA==.Dezelle:BAAALAADCgYIBgAAAA==.',Dh='Dhdvl:BAAALAADCgIIAgABLAAECgUIBQASAAAAAA==.',Di='Dielectric:BAAALAAECgYICAAAAA==.',Do='Dogbeerpig:BAACLAAFFIEKAAIUAAMI7yJVCQAuAQAUAAMI7yJVCQAuAQAsAAQKgSoAAhQACAgQJv4DAHMDABQACAgQJv4DAHMDAAAA.Donakebro:BAAALAAECgIIAgAAAA==.Doomtaketwo:BAACLAAFFIEIAAIDAAQIjREcCwBIAQADAAQIjREcCwBIAQAsAAQKgR0AAgMACAhPHxcfAMMCAAMACAhPHxcfAMMCAAAA.Dotpurri:BAAALAADCgcIBwABLAAECggIIAANAAgjAA==.',Dr='Dracarus:BAAALAAECgcICgAAAA==.Dractyyr:BAAALAADCgIIAgAAAA==.Dragiz:BAAALAAECgYIDwAAAA==.Drutasy:BAABLAAECoEmAAMNAAgIgCO8BAAtAwANAAgIgCO8BAAtAwAXAAEIpwMYkAAqAAAAAA==.',['Dé']='Déáth:BAABLAAECoEqAAQFAAgI+x+3JQCzAgAFAAgI+x+3JQCzAgAYAAUI/RQFMQAfAQAOAAMICBZ4MQCGAAAAAA==.',El='Eldritchtale:BAAALAAECgIIAgAAAA==.Elia:BAAALAADCggICAABLAAFFAMICgAJACkWAA==.Elisanthe:BAAALAAECgUIBQAAAA==.Elluria:BAAALAADCgYIBgAAAA==.Eléssár:BAAALAADCgYIBgAAAA==.',En='Enyo:BAABLAAECoEVAAIKAAYICgqvOgD1AAAKAAYICgqvOgD1AAAAAA==.',Er='Erosco:BAAALAAECgUIBAAAAA==.',Ev='Evemke:BAAALAADCgEIAQAAAA==.Everhate:BAABLAAECoEWAAIVAAgIRAEQvgBQAAAVAAgIRAEQvgBQAAAAAA==.Evianna:BAAALAADCgYIBwABLAAECggIJQADACMWAA==.',Ex='Exiledcow:BAAALAADCgcIDQAAAA==.',Ez='Ezzergeezer:BAABLAAECoEZAAIEAAcIdhkBQQD/AQAEAAcIdhkBQQD/AQAAAA==.',Fa='Farigrim:BAABLAAECoEVAAIZAAYIwiLPEABjAgAZAAYIwiLPEABjAgAAAA==.Fatigue:BAAALAAECgYIEAAAAA==.',Fe='Felovich:BAAALAAECgYIBAAAAA==.Felrath:BAAALAADCggIFAAAAA==.Femke:BAAALAAECgMIBAAAAA==.Fettemcdau:BAAALAAECgYIBgABLAAECgYIFgAHAHscAA==.',Fi='Fionnaghal:BAAALAADCggIFwAAAA==.Firefighter:BAABLAAECoEUAAMJAAYIOQ3jnAD/AAAJAAYIOQ3jnAD/AAAQAAQIvQObjgCPAAAAAA==.Fixonomicon:BAAALAAECgYIBgAAAA==.',Fl='Flaxly:BAAALAADCggICAAAAA==.',Fo='Foregone:BAAALAADCgcIBwAAAA==.Forta:BAACLAAFFIEGAAIVAAIIlRrfFwCwAAAVAAIIlRrfFwCwAAAsAAQKgScAAhUACAirHRIcALUCABUACAirHRIcALUCAAAA.Foxey:BAAALAADCgcIBwAAAA==.',Fr='Frieren:BAAALAADCgYIBgABLAAECggIHwAXAGQiAA==.',Fu='Fumiko:BAAALAAECgUICwABLAAECgYIDAASAAAAAA==.',['Fá']='Fánderay:BAAALAAECgYIDAAAAA==.',Ga='Galliard:BAAALAAECggICAAAAA==.',Gh='Gharmoul:BAABLAAECoErAAMaAAgIJiayAQBsAwAaAAgIJiayAQBsAwAbAAcIaAulRQB4AQAAAA==.',Gi='Gibor:BAAALAADCgcIBwAAAA==.Ginja:BAAALAAECgYIBgABLAAECggIJQADACMWAA==.',Gl='Glacielle:BAAALAADCgcICwAAAA==.Glaivera:BAAALAADCgIIAgABLAAECggIIAANAAgjAA==.Globalwarnin:BAAALAADCggIGAAAAA==.',Go='Goodfellar:BAAALAADCggIEQAAAA==.Gooroom:BAAALAADCgYIBgAAAA==.Gorepour:BAAALAADCggIDwABLAAECgcIFAAcAOMRAA==.Gossip:BAAALAAECgMIAwAAAA==.',Gr='Grebie:BAAALAAECgQIBgABLAAFFAMICgAJACkWAA==.Gregorfilth:BAAALAADCggICAAAAA==.Grimdoc:BAAALAAECgYIEQAAAA==.Grir:BAAALAAECgQIBAAAAA==.Gromit:BAAALAAECgQICQAAAA==.',Gu='Gunugg:BAABLAAECoEgAAIVAAgIJyI4EwDzAgAVAAgIJyI4EwDzAgAAAA==.',Gw='Gwynbleïdd:BAAALAAECggIBAAAAA==.',Ha='Hackebaer:BAAALAADCgcIBwAAAA==.Hadisan:BAABLAAECoEmAAIUAAgI3CMcFAANAwAUAAgI3CMcFAANAwAAAA==.Hairyboom:BAAALAAECgUICQAAAA==.Hamon:BAAALAADCggICAABLAAFFAUIBwADAFQbAA==.',He='Hephaistos:BAAALAADCgIIAgAAAA==.',Hi='Hidan:BAAALAAECgcIDQAAAA==.Highroll:BAAALAADCggIFAAAAA==.Hips:BAAALAAECgYIEAAAAA==.Hipsthepeeps:BAAALAADCggIDQAAAA==.',Ho='Holydread:BAAALAAECgMIBQAAAA==.Holygoat:BAAALAADCggIGgAAAA==.Hoothoot:BAAALAADCggIJQAAAA==.Hothone:BAAALAAECgEIAQAAAA==.Houlon:BAAALAADCgUIBQAAAA==.Hovezina:BAAALAADCggIGAAAAA==.',Hu='Hunsolo:BAAALAADCgYICwABLAAECgEIAQASAAAAAA==.Hunt:BAAALAADCgQIBAABLAAFFAUIBwADAFQbAA==.',Ic='Ice:BAABLAAECoEVAAMJAAcIJRhuRwDXAQAJAAYIABxuRwDXAQAQAAEIKAM+tAAKAAAAAA==.Icer:BAAALAADCgcIBwAAAA==.',Ig='Ignardor:BAAALAADCgYIBgAAAA==.',Il='Illian:BAAALAAECggIDgAAAA==.',Im='Imaginetwo:BAAALAAECgcIEQAAAA==.',Is='Isaador:BAAALAADCgcIBwAAAA==.Iserhalls:BAABLAAECoEaAAIHAAcIQiPpFwCLAgAHAAcIQiPpFwCLAgAAAA==.Isonol:BAAALAADCggIGQABLAAECgEIAQASAAAAAA==.',Iz='Izanghi:BAAALAADCggIDwAAAA==.Izrodaa:BAAALAAECgQIBAAAAA==.',Je='Jensunwalker:BAAALAADCgcIBwAAAA==.',Ju='Justlass:BAAALAAECgYIBwABLAAECgcIGgANAMAgAA==.',Ka='Kabat:BAAALAAECgYIBgAAAA==.Kaboochu:BAAALAADCggICAAAAA==.Kaerial:BAAALAADCgQIBAABLAAECggIHAAdAHIPAA==.Kallez:BAAALAADCgEIAQAAAA==.Karen:BAAALAAECgEIAQAAAA==.Katdragontwo:BAAALAAECgIIAgAAAA==.Katza:BAAALAAECgIIAgABLAAFFAMICgAKAPkaAA==.',Kh='Khaosin:BAAALAADCggIIAAAAA==.',Ki='Kilga:BAAALAAECgcIDgAAAA==.Killerdeluxe:BAAALAADCgcIBwAAAA==.Kinshi:BAAALAAECgIIAgAAAA==.',Kl='Klampe:BAAALAAECggICAAAAA==.',Ko='Kolour:BAAALAADCggIDgABLAAFFAMIBwAIAOcfAA==.Koncz:BAAALAAECgQIBQAAAA==.',Kr='Krammebamsen:BAAALAADCgcIBwAAAA==.Kravata:BAAALAADCgEIAQAAAA==.Krelas:BAAALAADCggIDgAAAA==.Krezmeth:BAAALAAECgQIBwAAAA==.Kripxus:BAACLAAFFIEHAAIFAAMIJCCmDwAjAQAFAAMIJCCmDwAjAQAsAAQKgR0AAgUACAhsI9UeANICAAUACAhsI9UeANICAAAA.',Ku='Kukskott:BAAALAADCgQIBAAAAA==.Kungpowfury:BAAALAADCgQIBAAAAA==.Kusojiji:BAAALAAECggICAAAAA==.',La='Lanxy:BAAALAAECgcIDQAAAA==.Lassaila:BAABLAAECoEaAAINAAcIwCBjGABvAgANAAcIwCBjGABvAgAAAA==.Lassmeep:BAAALAAECgUICQABLAAECgcIGgANAMAgAA==.',Le='Leonuts:BAAALAAECggIEgAAAA==.Leori:BAAALAADCggICAABLAAFFAMICgAJACkWAA==.Lethanî:BAAALAAECgMIAwAAAA==.',Li='Lilydan:BAAALAAECgYIDAAAAA==.Lirial:BAAALAADCgYIBgAAAA==.',Lo='Lopovcina:BAAALAAECgYIEQAAAA==.Loric:BAABLAAECoEhAAIGAAgI5whbKgC3AQAGAAgI5whbKgC3AQAAAA==.',Lu='Lunora:BAAALAADCgcIBwAAAA==.',Ly='Lyfe:BAAALAAECgYIDQAAAA==.Lyjitsu:BAAALAAECgQICQAAAA==.Lynn:BAABLAAECoEcAAIDAAcI6xowTgAFAgADAAcI6xowTgAFAgAAAA==.',['Lä']='Lättoriginal:BAAALAADCgUIBQAAAA==.',Ma='Madeleine:BAACLAAFFIEHAAIEAAMI0wq5LACTAAAEAAMI0wq5LACTAAAsAAQKgTUAAgQACAj8GRUnAHkCAAQACAj8GRUnAHkCAAAA.Makke:BAABLAAECoEWAAIMAAYItyKJFwA2AgAMAAYItyKJFwA2AgAAAA==.Malemuu:BAAALAADCgQIBAAAAA==.Maraa:BAACLAAFFIEIAAIKAAMIKxCnBgDEAAAKAAMIKxCnBgDEAAAsAAQKgSwAAwoACAgZHAoPAF0CAAoACAgZHAoPAF0CABQABgjsEKymAGoBAAAA.Mayizengg:BAABLAAECoEfAAMeAAcItRv5BQA1AgAeAAcItRv5BQA1AgAaAAcIagWHZQAhAQAAAA==.',Mc='Mcflash:BAABLAAECoEYAAMUAAgIfQt4lQCJAQAUAAcIrwt4lQCJAQAKAAgI4QayMwAhAQAAAA==.',Me='Merely:BAAALAAECgIIAgAAAA==.',Mh='Mheesa:BAACLAAFFIEKAAMJAAMIKRawEgDPAAAJAAMIKRawEgDPAAAQAAEIlg78KABOAAAsAAQKgScAAwkACAhdIyMPANQCAAkACAhdIyMPANQCABAABghDI9kjAGECAAAA.Mheon:BAAALAADCggICAABLAAFFAMICgAJACkWAA==.Mhynnae:BAAALAAECgcIEgAAAA==.',Mi='Milav:BAAALAADCggICAAAAA==.Milkshocklat:BAABLAAECoEVAAIQAAcIlRGUQwDCAQAQAAcIlRGUQwDCAQAAAA==.Miyahturbo:BAACLAAFFIEPAAIQAAYIjyFuAQBtAgAQAAYIjyFuAQBtAgAsAAQKgRoAAhAACAjAJZwDAGwDABAACAjAJZwDAGwDAAAA.',Mo='Mob:BAACLAAFFIEHAAIDAAUIVBs+BQD0AQADAAUIVBs+BQD0AQAsAAQKgRUAAgMACAh7I1UMADIDAAMACAh7I1UMADIDAAAA.Monkeywar:BAABLAAECoEZAAIWAAYI9R/CGgAgAgAWAAYI9R/CGgAgAgAAAA==.Monkiatso:BAAALAAECgQIBAAAAA==.Moo:BAACLAAFFIEHAAIYAAMIeRktBgDYAAAYAAMIeRktBgDYAAAsAAQKgSQAAhgACAhrJo4AAH8DABgACAhrJo4AAH8DAAAA.Moojito:BAABLAAECoEZAAIJAAcIpBkCOwAAAgAJAAcIpBkCOwAAAgAAAA==.Mordesh:BAAALAADCgYIBgAAAA==.Morgaunie:BAAALAAECggICwAAAA==.Mortem:BAAALAADCggICAAAAA==.Morwen:BAABLAAECoElAAIDAAgIIxYTQgArAgADAAgIIxYTQgArAgAAAA==.Morydin:BAAALAAECggIDwAAAA==.Moshakk:BAAALAAECgcIDAAAAA==.',Mu='Mullez:BAAALAADCgcIBwAAAA==.Munajunior:BAAALAAECgIIAgAAAA==.Munyanyo:BAAALAADCgEIAQAAAA==.Mushroompie:BAAALAADCggICAABLAAFFAIIBQAEAK8OAA==.',My='Mybigpriest:BAACLAAFFIEGAAIaAAII5x8lFQC+AAAaAAII5x8lFQC+AAAsAAQKgSkAAhoACAiOIXcKAAEDABoACAiOIXcKAAEDAAAA.',Na='Nadshu:BAAALAADCgEIAQAAAA==.Namitahun:BAAALAAECgMIBAAAAA==.Naturalthing:BAAALAADCgYIEAABLAADCggIGgASAAAAAA==.Nazgard:BAAALAADCgYIBgAAAA==.',Ne='Neight:BAAALAAECggICwAAAA==.Neikien:BAAALAAECgUIEwAAAA==.Neirok:BAAALAAECgYIEAAAAA==.Nero:BAACLAAFFIEHAAIDAAIIBB50GgC2AAADAAIIBB50GgC2AAAsAAQKgSgAAgMACAi9ISUSAA8DAAMACAi9ISUSAA8DAAAA.Nerzhulrrosh:BAAALAAECggIEwAAAA==.Netpeb:BAABLAAECoEWAAMHAAYIexxTOAC7AQAHAAYIDRtTOAC7AQAfAAII0RD66QBwAAAAAA==.Nezfariel:BAAALAADCgcIBAAAAA==.Nezquick:BAAALAAECggIEwAAAA==.',Ni='Nightliee:BAAALAAECggIDgAAAA==.Ninjapull:BAAALAAECgcIEQAAAA==.Nipha:BAAALAADCgYIDwAAAA==.Niq:BAABLAAECoEcAAIDAAgIjyHlGADmAgADAAgIjyHlGADmAgAAAA==.Niqp:BAAALAAECgcIBwABLAAECggIHAADAI8hAA==.Niro:BAAALAADCggIDgAAAA==.Nixie:BAAALAAECgUICQAAAA==.',No='Noblesse:BAAALAADCggIAgAAAA==.Noderneder:BAACLAAFFIERAAQUAAYIoSXZAQAiAgAUAAUI0SXZAQAiAgAKAAMIoRv4AwANAQAZAAEIkxPLGgBWAAAsAAQKgRwABBQACAgZJkYLAEEDABQACAgLJkYLAEEDAAoABwiQHxwcANUBABkAAQjqFXdhAEEAAAAA.Nothing:BAAALAAECgUIBQAAAA==.',['Në']='Nëro:BAABLAAECoEVAAIVAAgIhRM+OwAMAgAVAAgIhRM+OwAMAgABLAAFFAIIBwADAAQeAA==.',Ob='Obley:BAAALAAECgYIDAAAAA==.',Oc='Octavius:BAAALAAECgYIEQAAAA==.',Oh='Oh:BAAALAAECgIIAgAAAA==.Ohnezahn:BAABLAAECoEZAAIBAAgI7QpxFwCKAQABAAgI7QpxFwCKAQAAAA==.Ohshamtastic:BAAALAAECggICAAAAA==.',On='Onkelpål:BAAALAAECgYICQAAAA==.Onlybans:BAAALAAECgYICwAAAA==.',Op='Ophien:BAAALAADCgEIAQAAAA==.',Or='Ortzi:BAABLAAECoEgAAIQAAgIwBp9IQBxAgAQAAgIwBp9IQBxAgAAAA==.',Pa='Paladvl:BAAALAAECgUIBQAAAA==.Palandoraii:BAAALAADCggIEAABLAAECggIHAAIAG0hAA==.Palasonic:BAAALAADCggICQAAAA==.Palesyan:BAAALAADCgcIBwAAAA==.Pallastine:BAAALAAECgYIDQABLAAFFAQICAADAI0RAA==.Pandvoidaii:BAABLAAECoEcAAMIAAgIbSEtGgDVAgAIAAgIbSEtGgDVAgAMAAMI8hKAYgCVAAAAAA==.Panghe:BAAALAAECgMICAAAAA==.Papaver:BAAALAAECgUICQAAAA==.Pawnfoo:BAABLAAECoEcAAIdAAgIcg9qHACXAQAdAAgIcg9qHACXAQAAAA==.',Pe='Pepion:BAAALAAECgYIBgABLAAFFAUIDQAEAMUSAA==.Peretz:BAAALAADCggICAABLAAECgcIEgASAAAAAA==.',Ph='Phteven:BAABLAAECoEYAAIEAAcIhBl0QgD5AQAEAAcIhBl0QgD5AQAAAA==.',Pi='Pinkthunder:BAAALAADCggICgAAAA==.Pituce:BAAALAAECgcIBwABLAAFFAIIBgAQAFwdAA==.Pizzasnegl:BAABLAAECoEdAAIDAAcIuA+odgCiAQADAAcIuA+odgCiAQAAAA==.Pizzawich:BAAALAADCgUIBQAAAA==.',Pl='Plumm:BAAALAAECggIEQAAAA==.',Po='Poshunsella:BAAALAAECgMIAwAAAA==.Potetjon:BAAALAADCgcICQAAAA==.Powithabow:BAAALAADCggICAAAAA==.',Pr='Pratt:BAABLAAECoEVAAIUAAYIFhlzfAC5AQAUAAYIFhlzfAC5AQAAAA==.Priestfus:BAAALAAECgYIBgAAAA==.Primoplex:BAAALAADCggICAAAAA==.Priset:BAAALAAECgYIDwAAAA==.',Pu='Puncture:BAAALAADCggICAAAAA==.',['På']='Pålina:BAAALAAECgYIEgABLAAECggIIAANAAgjAA==.',Qu='Quenching:BAAALAAECgYIDAAAAA==.Quilldraka:BAABLAAECoEjAAICAAgI7RSPHAAXAgACAAgI7RSPHAAXAgAAAA==.Quillidania:BAAALAAECgUIBQABLAAECggIIwACAO0UAA==.Quixpot:BAAALAADCggIEQAAAA==.',Ra='Rachaa:BAAALAAECgEIAQABLAAFFAIICAAEAP4dAA==.Rachmana:BAACLAAFFIEGAAIZAAII0hNfEQCcAAAZAAII0hNfEQCcAAAsAAQKgRwAAhkACAglIAIFAP4CABkACAglIAIFAP4CAAEsAAUUAggIAAQA/h0A.Rachmania:BAACLAAFFIEIAAIEAAII/h30HwCvAAAEAAII/h30HwCvAAAsAAQKgSQAAwQACAhoIRAVAOkCAAQACAhoIRAVAOkCABwABQhEE/lFAC4BAAAA.Rachún:BAAALAAFFAIIAgABLAAFFAIICAAEAP4dAA==.Raendin:BAABLAAECoEZAAIgAAcIXB0pEQAfAgAgAAcIXB0pEQAfAgABLAAECggIDgASAAAAAA==.Razrex:BAAALAADCgMIAgAAAA==.',Re='Rehvis:BAABLAAECoEZAAMDAAgI2A5EhACGAQADAAcIbBBEhACGAQAgAAcIgwSGNwDPAAAAAA==.Reighnar:BAAALAAECgYICgABLAAECggIDgASAAAAAA==.Rektalot:BAAALAAECggIDgAAAA==.Renfein:BAAALAADCgMIAwAAAA==.Rennzath:BAABLAAECoEeAAICAAcIKR5IFABsAgACAAcIKR5IFABsAgAAAA==.Reroll:BAAALAADCggICAAAAA==.Restorationx:BAAALAADCgYIBwAAAA==.Revzt:BAAALAAECgYIEAAAAA==.',Ri='Riftwar:BAAALAADCgcIDQAAAA==.Riteuros:BAABLAAECoEeAAMhAAgIihrxCACJAgAhAAgIihrxCACJAgAiAAMIpQdzFQCLAAAAAA==.Riv:BAAALAADCgIIAgAAAA==.Rivzouchat:BAAALAADCgcIBwABLAAECggIJAAJAAIhAA==.',Ro='Robbie:BAAALAADCgcIBwAAAA==.Robii:BAAALAAECgMICQAAAA==.Ronning:BAABLAAFFIEHAAIQAAMI5xUGDwDzAAAQAAMI5xUGDwDzAAABLAAFFAYIEQAUAKElAA==.Ronnings:BAABLAAFFIEJAAIbAAMIlBMoDQDrAAAbAAMIlBMoDQDrAAABLAAFFAYIEQAUAKElAA==.Rozhen:BAAALAADCggICAAAAA==.',Ru='Rugar:BAABLAAECoEWAAIfAAYI8BW+gABvAQAfAAYI8BW+gABvAQAAAA==.Rumbatak:BAAALAAECgEIAQAAAA==.',['Rä']='Räven:BAAALAAFFAEIAQAAAA==.',Sa='Saberstalker:BAAALAAECgMIAwAAAA==.Sacerdos:BAAALAADCggICAAAAA==.Sage:BAACLAAFFIEHAAIDAAMIAQycFADdAAADAAMIAQycFADdAAAsAAQKgRwAAgMACAhFIa4bANYCAAMACAhFIa4bANYCAAAA.',Sb='Sbkwar:BAAALAADCgEIAQAAAA==.',Sc='Scarletmoon:BAAALAAECgQIBAAAAA==.Schokolade:BAAALAADCgMIAwAAAA==.',Se='Secrid:BAAALAAECgMIBgAAAA==.Sehzei:BAAALAAECgEIAQAAAA==.Selja:BAABLAAECoEXAAIfAAcIJg2UgABvAQAfAAcIJg2UgABvAQAAAA==.Selle:BAAALAAECgIIAwAAAA==.Selne:BAABLAAECoEnAAIUAAgIKx4eJgCvAgAUAAgIKx4eJgCvAgAAAA==.Seymóur:BAABLAAECoEZAAIQAAgI7RyBIAB4AgAQAAgI7RyBIAB4AgAAAA==.',Sh='Shadiedeath:BAAALAAECgcIBwAAAA==.Shadowzz:BAAALAAECgYIEgAAAA==.Shaggers:BAABLAAECoEUAAMgAAgIRA8JLwACAQADAAgIEAiImgBZAQAgAAUIKBMJLwACAQAAAA==.Shakelia:BAAALAADCggICQAAAA==.Shamea:BAAALAAECgYIDQAAAA==.Shamob:BAAALAAECgMIBQABLAAFFAUIBwADAFQbAA==.Shamperor:BAAALAADCgYIBgAAAA==.Shanoodle:BAAALAADCggICAABLAAFFAIIBQAOAMYhAA==.Sheina:BAAALAADCggIEAAAAA==.Shinyraquaza:BAAALAAECgEIAQAAAA==.',Si='Sicarius:BAAALAAECgQIBgAAAA==.Silverpaws:BAAALAAECggIEQAAAA==.Sinnr:BAECLAAFFIEQAAIaAAUIdSVKAQA1AgAaAAUIdSVKAQA1AgAsAAQKgSoAAhoACAjDJmwAAIkDABoACAjDJmwAAIkDAAAA.',Sl='Slaughtie:BAAALAAECgYICAAAAA==.Sliferdemon:BAAALAAECgQIBAAAAA==.',Sn='Snêak:BAAALAADCgQIBAAAAA==.',So='Sober:BAAALAADCggIEAABLAAFFAMIBwAIAOcfAA==.Soltor:BAAALAADCgcICQAAAA==.Soniç:BAAALAADCgYIAwAAAA==.Sorina:BAAALAADCgcIEAAAAA==.Sorìna:BAAALAADCgcICAAAAA==.',St='Stabbymcnuts:BAACLAAFFIEGAAMGAAIISRt4DwCrAAAGAAIISRt4DwCrAAAhAAIIbQYAAAAAAAAsAAQKgRsAAwYABwjNIngOAKYCAAYABwilIXgOAKYCACEABggeHQAAAAAAAAEsAAUUBAgNAAQADxwA.Stack:BAAALAAECgQIBwAAAA==.Stampsalot:BAAALAAECgYICwAAAA==.Stanwyck:BAAALAAECgYIBgABLAAECggIJQADACMWAA==.Stenton:BAAALAAECgYIDAAAAA==.Stfluffy:BAAALAADCggIFwAAAA==.Stjärna:BAAALAADCgQIBAAAAA==.Stolpskott:BAAALAAECgIIAgABLAAECgYIDAASAAAAAA==.Stony:BAABLAAECoErAAIFAAgIkR7RLQCQAgAFAAgIkR7RLQCQAgAAAA==.Stopmenow:BAACLAAFFIEFAAINAAII7h3gEwCtAAANAAII7h3gEwCtAAAsAAQKgSAAAw0ACAglIIgMANQCAA0ACAglIIgMANQCABcABAjZE8pgAOYAAAAA.Strafe:BAAALAAECgcIEwAAAA==.',Sy='Symore:BAABLAAECoEfAAIZAAcI3RDzLACHAQAZAAcI3RDzLACHAQAAAA==.Syxpacs:BAEALAAECgYIBgABLAAFFAUIEAAaAHUlAA==.',['Sè']='Sèt:BAAALAAECggICAAAAA==.',Ta='Tanduine:BAAALAAECgMIBAAAAA==.Tast:BAABLAAECoEYAAIVAAcIdxHsWQCfAQAVAAcIdxHsWQCfAQAAAA==.Tathamet:BAAALAADCgUIAQAAAA==.',Te='Temma:BAAALAAECgMIAwAAAA==.Temu:BAAALAAECggIEQAAAA==.Terok:BAAALAADCgcIBwAAAA==.',Th='Thaerox:BAABLAAECoEaAAIFAAgINxi5WAAOAgAFAAgINxi5WAAOAgAAAA==.Thehunterdz:BAAALAAECgQIBAAAAA==.Thibruli:BAABLAAECoEXAAMJAAcIjwmmnQD9AAAJAAcIjwmmnQD9AAAQAAYIlQIwiACtAAABLAAECggIJQADACMWAA==.Thors:BAAALAAECgEIAQAAAA==.Thumper:BAABLAAECoEjAAIKAAgIfxhQFAAhAgAKAAgIfxhQFAAhAgAAAA==.',Ti='Timmietimtom:BAACLAAFFIEFAAIEAAIIrw5BLQCSAAAEAAIIrw5BLQCSAAAsAAQKgRoAAyMACAhjH7IKAO8BAAQACAi7HBAoAHMCACMABghDHLIKAO8BAAAA.',To='Tohsaka:BAAALAADCgUIBQABLAAECggIHwAXAGQiAA==.Totemmogens:BAAALAAECgMIBQAAAA==.',Tr='Tranza:BAABLAAECoEZAAIaAAcIHRDFSgCBAQAaAAcIHRDFSgCBAQAAAA==.Trapinek:BAACLAAFFIEGAAIQAAIIXB1nFQCvAAAQAAIIXB1nFQCvAAAsAAQKgSAAAhAACAiwJbsDAGsDABAACAiwJbsDAGsDAAAA.Trolloc:BAAALAAECgYIBgAAAA==.Tropicalmage:BAAALAADCgMIAwAAAA==.Truesilver:BAAALAAECgIIAgAAAA==.',['Tí']='Tím:BAEALAADCgcIBwABLAAECggIJgACAHAgAA==.',Um='Umaroth:BAAALAADCggIFgABLAAECggIJQADACMWAA==.',Un='Unknowncow:BAAALAAECgEIAQAAAA==.Unknownvoid:BAABLAAECoEkAAIEAAgIyg+7RgDoAQAEAAgIyg+7RgDoAQAAAA==.Unofficial:BAAALAADCgMIAwAAAA==.Untrusty:BAAALAAECgIIAgAAAA==.',Ut='Uthar:BAAALAADCgcIDgABLAAECggIJQADACMWAA==.',Va='Vaell:BAAALAAECgYIBgAAAA==.Vaitaly:BAAALAAECgYIBgAAAA==.Vangarrett:BAAALAADCggICAAAAA==.',Ve='Veeto:BAABLAAECoEXAAMjAAcIbB+sBACKAgAjAAcIbB+sBACKAgAEAAEIEQio1gAxAAAAAA==.Vehemence:BAAALAADCgYICwAAAA==.Veneficar:BAAALAADCggICAAAAA==.Vengaboy:BAAALAAECgMIBAAAAA==.Venos:BAAALAAECgcICgAAAA==.Vermitor:BAAALAAECgcIBwAAAA==.Vesemirr:BAAALAAECgcIDgAAAA==.Veylith:BAAALAADCgYIBwAAAA==.',Vi='Vikjet:BAABLAAECoEXAAIcAAcIWA2hMQCDAQAcAAcIWA2hMQCDAQAAAA==.Vinbär:BAAALAAECgYICgAAAA==.Vitaly:BAAALAADCgYIBgAAAA==.',Vo='Voidtina:BAAALAAECgYIDAAAAA==.',Vu='Vulperatrade:BAAALAADCggICAABLAAFFAIIBQAEAK8OAA==.',Vy='Vyraxik:BAAALAAECgMIBAAAAA==.',Wa='Wacemindu:BAAALAADCgYIBwABLAAECgEIAQASAAAAAA==.Wakan:BAAALAADCggIDwAAAA==.Walkingkeg:BAAALAAECgYICQAAAA==.Wannabepanda:BAAALAADCggICAABLAADCggICAASAAAAAA==.Wapel:BAAALAADCgIIAgAAAA==.Wapelsmrdí:BAABLAAECoEUAAIFAAgI8xiFPQBZAgAFAAgI8xiFPQBZAgAAAA==.Warvulp:BAABLAAECoEYAAIEAAgIDhM1PAASAgAEAAgIDhM1PAASAgAAAA==.Waycrest:BAAALAAECgcIDQAAAA==.',We='Weizmann:BAAALAAECgcIEgAAAA==.',Wh='Whysosoft:BAAALAAECgEIAQAAAA==.',Wi='Wicaliss:BAAALAAECgYIEgAAAA==.',Wu='Wulfenheimer:BAAALAAECgEIAQAAAA==.',Xa='Xand:BAABLAAECoEXAAIFAAgI0x1XMQCDAgAFAAgI0x1XMQCDAgAAAA==.Xaruon:BAAALAADCggICAAAAA==.Xavirat:BAAALAAECgYIBgAAAA==.',Xe='Xeg:BAACLAAFFIEGAAIUAAIINhfzIACpAAAUAAIINhfzIACpAAAsAAQKgTMAAhQACAhrIyEMADwDABQACAhrIyEMADwDAAAA.Xeraphine:BAAALAAECgQIBQAAAA==.',Xi='Xina:BAAALAADCgYICAAAAA==.',Xk='Xkairi:BAAALAAECgYICAAAAA==.',Xo='Xolarian:BAAALAADCgcIEAAAAA==.',Xs='Xsinsane:BAAALAAECggICAAAAA==.',Ya='Yatozin:BAAALAADCgcICgABLAAECgQICQASAAAAAA==.',Ym='Ymva:BAAALAAECgUIBQAAAA==.',Yo='Yoruha:BAAALAADCggIJQAAAA==.Yoududu:BAAALAADCgEIAQAAAA==.',['Yö']='Yötzy:BAAALAADCggICAAAAA==.',Za='Zagan:BAAALAADCgUIBQAAAA==.Zanbar:BAAALAAECgUIBQABLAAECgYIDAASAAAAAA==.Zandrek:BAAALAAFFAEIAQAAAA==.Zank:BAAALAAECgQIBAABLAAECgYIDAASAAAAAA==.Zathana:BAAALAAECgYIDQAAAA==.',Ze='Zealus:BAAALAAECggIDgAAAA==.Zein:BAAALAAECgMIBAAAAA==.Zerux:BAAALAADCgIIAgAAAA==.',Zh='Zhareli:BAAALAAECgIIAwAAAA==.Zhoin:BAAALAADCgYICQAAAA==.',Zi='Zirnidan:BAAALAAECgYIBgAAAA==.',Zu='Zulamana:BAAALAAFFAIIAwABLAAFFAIIBgAQAFwdAA==.',Zy='Zyrrah:BAAALAAECgcIBwABLAAFFAMICgAJACkWAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end