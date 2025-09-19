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
 local lookup = {'Evoker-Preservation','Evoker-Devastation','DemonHunter-Havoc','Unknown-Unknown','Warlock-Destruction','Shaman-Restoration','Druid-Restoration','Shaman-Elemental','Druid-Guardian','Paladin-Protection','Warrior-Fury','Warrior-Arms','Mage-Arcane','Paladin-Retribution','Druid-Balance','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Priest-Shadow','Monk-Mistweaver','Mage-Frost','Warlock-Demonology','Warlock-Affliction',}; local provider = {region='EU',realm='Deathwing',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abashka:BAAALAAECgMIAwAAAA==.',Ad='Aderan:BAABLAAECoEUAAMBAAcIEA0WEgBSAQABAAcIEA0WEgBSAQACAAEIbARORwAXAAAAAA==.',Ae='Aesthedh:BAABLAAECoEcAAIDAAgIKBD6OADgAQADAAgIKBD6OADgAQAAAA==.',Ak='Akaame:BAAALAADCgcIDAAAAA==.Akonkkagva:BAAALAAECgYICAAAAA==.',Al='Allura:BAAALAAECgMIAwAAAA==.',An='Anabelle:BAAALAAECgIIAgAAAA==.Analgia:BAAALAADCgcIBwAAAA==.Andoomi:BAAALAAECgYICwABLAAFFAIIAgAEAAAAAA==.Angelica:BAAALAAECgUIBQAAAA==.Annarion:BAAALAAECgYICQAAAA==.',Ao='Aongusha:BAAALAAECggICwAAAA==.',Ar='Arbores:BAAALAAECgMIAwAAAA==.Arckraptor:BAAALAAECgMIBAAAAA==.Arkie:BAABLAAECoEbAAICAAgIyA4YGADqAQACAAgIyA4YGADqAQAAAA==.Arwolia:BAAALAAECgEIAQAAAA==.Aryndyr:BAAALAAECgMIBAAAAA==.',As='Ascensionism:BAAALAADCggICAAAAA==.Asdrybal:BAAALAADCgcIBwAAAA==.Asztar:BAABLAAECoESAAIFAAcI8iSqDwC/AgAFAAcI8iSqDwC/AgAAAA==.',At='Atia:BAAALAAECgcICgABLAAECggIHwAGAF0jAA==.Atraxia:BAAALAAECgUIBwAAAA==.',Au='Auburnfury:BAAALAAECgYIDwAAAA==.Auwyn:BAAALAAECgcIEAAAAA==.',Aw='Awake:BAAALAADCgUIBQABLAAECggICgAEAAAAAA==.',Ay='Ayzen:BAAALAAECgYICwAAAA==.',Az='Azirel:BAAALAADCggIDwAAAA==.',Ba='Balak:BAAALAAECgQICQAAAA==.Barrdi:BAAALAAECgcIDQAAAA==.',Be='Bearcowtree:BAABLAAECoEWAAIHAAgIRhm2DgBnAgAHAAgIRhm2DgBnAgAAAA==.Bearied:BAAALAAECgcIEgAAAA==.Beastworm:BAAALAAECgcIEwAAAA==.Beefsaucer:BAAALAAECgUIBwAAAA==.Bergzdh:BAAALAADCggICAABLAAECggIFwAIAHIUAA==.Bergzdk:BAAALAADCggIGAABLAAECggIFwAIAHIUAA==.Bergzsham:BAABLAAECoEXAAIIAAgIchTiHgAZAgAIAAgIchTiHgAZAgAAAA==.Beurko:BAAALAADCgEIAQAAAA==.Bezla:BAAALAADCggICAAAAA==.',Bi='Bigholes:BAAALAADCggICAAAAA==.Bildrulle:BAAALAAECggIEAAAAA==.Billan:BAAALAADCggICAAAAA==.',Bl='Blacksnake:BAAALAADCgIIAgABLAAECgEIAQAEAAAAAA==.Bladeedge:BAAALAADCggIDQAAAA==.Bloodberry:BAABLAAECoEXAAIJAAcI3B+wAgCEAgAJAAcI3B+wAgCEAgAAAA==.Blothr:BAAALAAECgUICAAAAA==.',Bo='Bobi:BAAALAAECggICgAAAA==.Bongowa:BAAALAAECgcIEQAAAA==.',Br='Brossezmode:BAAALAAECggIEwAAAA==.Brossio:BAAALAAECgYIBgABLAAECggIEwAEAAAAAA==.',Bu='Burnlight:BAAALAADCggIDgAAAA==.',['Bá']='Báné:BAAALAAECgEIAQAAAA==.',['Bä']='Bäddie:BAAALAADCggIHQAAAA==.',['Bé']='Bécks:BAAALAAECgQIBwAAAA==.',Ca='Cactuslux:BAAALAAECgUIBQAAAA==.Calsy:BAAALAADCgUIBAAAAA==.Catchway:BAAALAADCgQIBAAAAA==.',Ch='Chikenugges:BAAALAADCggICAAAAA==.Chizbee:BAAALAAECgcIDgAAAA==.Chras:BAABLAAECoEfAAIKAAgIpyJJBADnAgAKAAgIpyJJBADnAgAAAA==.Chrascor:BAAALAAECgcIDAABLAAECggIHwAKAKciAA==.Chrasivae:BAAALAADCgYIBgABLAAECggIHwAKAKciAA==.Chrastina:BAAALAAECgIIAgABLAAECggIHwAKAKciAA==.Chrasyrax:BAAALAADCggICAABLAAECggIHwAKAKciAA==.Chrazen:BAAALAADCgQIBAAAAA==.Chrislee:BAAALAAECgYIDgAAAA==.Chronios:BAAALAAECgYIEAAAAA==.Chtulhu:BAAALAADCggIDwABLAAECggIFgADAHYZAA==.Chucknourish:BAAALAADCggICAAAAA==.',Ci='Cifer:BAABLAAECoEfAAMLAAgIPCNoDgDJAgALAAgI9iFoDgDJAgAMAAUI8iAbCADmAQAAAA==.Ciphery:BAAALAADCgYIBgAAAA==.',Cl='Clarity:BAAALAAECgMIAwAAAA==.',Co='Colours:BAABLAAECoEdAAINAAgI/SM+BgA2AwANAAgI/SM+BgA2AwAAAA==.Composter:BAAALAADCggICQAAAA==.Coronilia:BAAALAAFFAIIAgAAAA==.',Cr='Crownilla:BAABLAAFFIEGAAICAAIIxxt4CACyAAACAAIIxxt4CACyAAAAAA==.',Ct='Cthlolo:BAAALAAECggICAAAAA==.Cthvijaager:BAAALAAECggICAAAAA==.',Cu='Cutter:BAAALAADCgMIAwAAAA==.',Cy='Cyphër:BAAALAAECgEIAQAAAA==.',Da='Dacitrone:BAAALAADCgQIBAAAAA==.Dacresha:BAAALAADCgMIAwAAAA==.Dantez:BAAALAAECgMIAwAAAA==.Darkanzali:BAAALAAECgYICAAAAA==.Darkcurse:BAAALAAECgEIAQAAAA==.Darthness:BAAALAADCgYIBwAAAA==.Dashilong:BAAALAADCggICAAAAA==.',De='Deathmandom:BAAALAADCgcIBwAAAA==.Deathon:BAAALAAECgIIAgAAAA==.Deathrunner:BAAALAAECgMIAwAAAA==.Deathtasy:BAAALAAECgYIDQAAAA==.Deedgenutss:BAAALAADCgIIAgAAAA==.Demondice:BAAALAAECgQICAAAAA==.Demonrat:BAAALAAECggICAAAAA==.Derf:BAAALAADCgUIBQAAAA==.Devilie:BAAALAADCgcICQAAAA==.Devyata:BAABLAAECoEUAAIGAAcILyAYEQBzAgAGAAcILyAYEQBzAgAAAA==.',Dh='Dhdvl:BAAALAADCgIIAgABLAAECgMIAwAEAAAAAA==.',Di='Dielectric:BAAALAAECgEIAQAAAA==.',Do='Dogbeerpig:BAACLAAFFIEFAAIOAAIIQhteCQC/AAAOAAIIQhteCQC/AAAsAAQKgRoAAg4ACAivJYoCAHADAA4ACAivJYoCAHADAAAA.Donakebro:BAAALAAECgEIAQAAAA==.Doomtaketwo:BAAALAAFFAIIAgAAAA==.',Dr='Dragiz:BAAALAAECgIIBAAAAA==.Drutasy:BAABLAAECoEXAAMHAAcIyyKgCACxAgAHAAcIyyKgCACxAgAPAAEIpwN2ZAAuAAAAAA==.',['Dé']='Déáth:BAABLAAECoEZAAQQAAcIhB+kIwBWAgAQAAcIhh6kIwBWAgARAAUI/RQjIgA3AQASAAMICBYaHwCYAAAAAA==.',El='Elisanthe:BAAALAADCgUIBQAAAA==.Elluria:BAAALAADCgYIBgAAAA==.Eléssár:BAAALAADCgYIBgAAAA==.',En='Enyo:BAAALAAECgUICgAAAA==.',Er='Erosco:BAAALAAECgUIBAAAAA==.',Ev='Evemke:BAAALAADCgEIAQAAAA==.Everhate:BAAALAAECggIDgAAAA==.Evianna:BAAALAADCgYIBwABLAAECgcIFwADAP8VAA==.',Ex='Exiledcow:BAAALAADCgcIDQAAAA==.',Ez='Ezzergeezer:BAAALAAECgUIBwAAAA==.',Fa='Farigrim:BAAALAAECgUICgAAAA==.Fatigue:BAAALAAECgYICgAAAA==.',Fe='Felrath:BAAALAADCgcIEQAAAA==.Femke:BAAALAAECgMIBAAAAA==.',Fi='Fionnaghal:BAAALAADCggICwAAAA==.Firefighter:BAAALAAECgMIBwAAAA==.',Fo='Forta:BAABLAAECoEVAAILAAgIshXSGwA7AgALAAgIshXSGwA7AgAAAA==.Foxey:BAAALAADCgcIBwAAAA==.',Fr='Frieren:BAAALAADCgYIBgAAAA==.',Fu='Fumiko:BAAALAAECgQIBwAAAA==.',Gh='Gharmoul:BAABLAAECoEeAAMTAAgIgCUZAQBnAwATAAgIgCUZAQBnAwAUAAcITAWWPgAlAQAAAA==.',Gi='Ginja:BAAALAADCgIIAgABLAAECgcIFwADAP8VAA==.',Gl='Globalwarnin:BAAALAADCggIGAAAAA==.',Go='Goodfellar:BAAALAADCggICQAAAA==.Gorepour:BAAALAADCggIDwAAAA==.',Gr='Grebie:BAAALAAECgQIBgABLAAECggIHwAGAF0jAA==.Gregorfilth:BAAALAADCggICAAAAA==.Gromit:BAAALAAECgMIBQAAAA==.',Gu='Gunugg:BAAALAAECgcIEQAAAA==.',Gw='Gwynbleïdd:BAAALAAECggIAgAAAA==.',Ha='Hackebaer:BAAALAADCgcIBwAAAA==.Hadisan:BAABLAAECoElAAIOAAgI3CNeBwA7AwAOAAgI3CNeBwA7AwAAAA==.Hamon:BAAALAADCggICAABLAAECggICgAEAAAAAA==.',Hi='Hidan:BAAALAAECgYIBwAAAA==.Highroll:BAAALAADCggIEAAAAA==.Hips:BAAALAAECgYICgAAAA==.Hipsthepeeps:BAAALAADCggIDQAAAA==.',Ho='Holygoat:BAAALAADCggICgAAAA==.Hoothoot:BAAALAADCggIFwAAAA==.Hothone:BAAALAAECgEIAQAAAA==.Houlon:BAAALAADCgUIBQAAAA==.Hovezina:BAAALAADCggIFQAAAA==.',Hu='Hunsolo:BAAALAADCgYICwABLAAECgEIAQAEAAAAAA==.',Ic='Ice:BAAALAAECggICgAAAA==.',Im='Imaginetwo:BAAALAAECgMIAwAAAA==.',Is='Iserhalls:BAAALAAECgYICwAAAA==.Isonol:BAAALAADCgUIBQABLAAECgEIAQAEAAAAAA==.',Iz='Izanghi:BAAALAADCggIDwAAAA==.Izrodaa:BAAALAADCgcIBwAAAA==.',Je='Jensunwalker:BAAALAADCgcIBwAAAA==.',Ju='Justlass:BAAALAAECgYIBgABLAAECgcIEwAEAAAAAA==.',Ka='Kabat:BAAALAADCgQIBAAAAA==.Kaboochu:BAAALAADCggICAAAAA==.Kaerial:BAAALAADCgQIBAABLAAECgcIFwAVAMQOAA==.Kallez:BAAALAADCgEIAQAAAA==.Karen:BAAALAAECgEIAQAAAA==.Katdragontwo:BAAALAAECgIIAgAAAA==.Katza:BAAALAAECgIIAgABLAAECggIHwAKAKciAA==.',Kh='Khaosin:BAAALAADCggIHAAAAA==.',Ki='Kilga:BAAALAAECgUIBQAAAA==.Kinshi:BAAALAAECgIIAgAAAA==.',Ko='Kolour:BAAALAADCgYIBgABLAAECggIHQANAP0jAA==.Koncz:BAAALAAECgEIAQAAAA==.',Kr='Krammebamsen:BAAALAADCgcIBwAAAA==.Kravata:BAAALAADCgEIAQAAAA==.Krelas:BAAALAADCggICAAAAA==.Krezmeth:BAAALAAECgQIBAAAAA==.Kripxus:BAABLAAECoEdAAIQAAgIbCNuCAAhAwAQAAgIbCNuCAAhAwAAAA==.',Ku='Kungpowfury:BAAALAADCgQIBAAAAA==.Kusojiji:BAAALAAECggICAAAAA==.',La='Lassaila:BAAALAAECgcIEwAAAA==.',Le='Leonuts:BAAALAAECgYIBQAAAA==.Leori:BAAALAADCggICAABLAAECggIHwAGAF0jAA==.',Li='Lilydan:BAAALAAECgMIAwAAAA==.Lirial:BAAALAADCgYIBgAAAA==.',Lo='Lopovcina:BAAALAAECgYICgAAAA==.Loric:BAAALAAECggIEgAAAA==.',Lu='Lunora:BAAALAADCgcIBwAAAA==.',Ly='Lyfe:BAAALAAECgYIDQAAAA==.Lyjitsu:BAAALAAECgQIBwAAAA==.Lynn:BAABLAAECoEWAAIDAAcIvRomKAAwAgADAAcIvRomKAAwAgAAAA==.',['Lä']='Lättoriginal:BAAALAADCgUIBQAAAA==.',Ma='Madeleine:BAABLAAECoEjAAIFAAgIehWKIAAqAgAFAAgIehWKIAAqAgAAAA==.Makke:BAAALAAECgcIEgAAAA==.Maraa:BAABLAAECoEgAAIKAAgIGRy3BgCNAgAKAAgIGRy3BgCNAgAAAA==.Mayizengg:BAAALAAECgYICgAAAA==.',Mc='Mcflash:BAAALAAECgYIBgAAAA==.',Me='Merely:BAAALAADCgIIAgAAAA==.',Mh='Mheesa:BAABLAAECoEfAAMGAAgIXSOJBQDyAgAGAAgIXSOJBQDyAgAIAAQIpiDfNwCGAQAAAA==.Mheon:BAAALAADCggICAABLAAECggIHwAGAF0jAA==.Mhynnae:BAAALAAECgYICwAAAA==.',Mi='Milkshocklat:BAAALAAECgUIBwAAAA==.Miyahturbo:BAABLAAFFIEFAAIIAAMIGSOWAwA8AQAIAAMIGSOWAwA8AQAAAA==.',Mo='Mob:BAAALAAECggICgAAAA==.Monkeywar:BAAALAAECgcIEgAAAA==.Monkiatso:BAAALAAECgQIBAAAAA==.Moo:BAABLAAECoEZAAIRAAgIPyQLAQBWAwARAAgIPyQLAQBWAwAAAA==.Moojito:BAAALAAECgUIBwAAAA==.Mordesh:BAAALAADCgYIBgAAAA==.Morgaunie:BAAALAADCggIIAAAAA==.Mortem:BAAALAADCggICAAAAA==.Morwen:BAABLAAECoEXAAIDAAcI/xUaOwDYAQADAAcI/xUaOwDYAQAAAA==.Morydin:BAAALAAECgcIDgAAAA==.Moshakk:BAAALAAECgQIBQAAAA==.',Mu='Mullez:BAAALAADCgcIBwAAAA==.Mushroompie:BAAALAADCggICAABLAAECggIGQAFAGMfAA==.',My='Mybigpriest:BAABLAAECoEbAAITAAgISh7bDACmAgATAAgISh7bDACmAgAAAA==.',Na='Nadshu:BAAALAADCgEIAQAAAA==.Namitahun:BAAALAADCgUIBQAAAA==.Naturalthing:BAAALAADCgQIBAABLAADCggICgAEAAAAAA==.Nazgard:BAAALAADCgYIBgAAAA==.',Ne='Neikien:BAAALAAECgMICQAAAA==.Neirok:BAAALAAECgMIBAAAAA==.Nero:BAABLAAECoEWAAIDAAgIdhnKHgBpAgADAAgIdhnKHgBpAgAAAA==.Nerzhulrrosh:BAAALAAECggIEwAAAA==.Netpeb:BAAALAAECgYIDwAAAA==.Nezquick:BAAALAAECggIEwAAAA==.',Ni='Nightliee:BAAALAADCgcIBwABLAADCgcICQAEAAAAAA==.Ninjapull:BAAALAAECgcICgAAAA==.Nipha:BAAALAADCgUIBQAAAA==.Niq:BAABLAAECoEUAAIDAAcIISJhFwCjAgADAAcIISJhFwCjAgAAAA==.',No='Noblesse:BAAALAADCggIAgAAAA==.Noderneder:BAACLAAFFIEGAAIOAAMIGCbyAQBWAQAOAAMIGCbyAQBWAQAsAAQKgRYAAw4ACAgMJpAFAE4DAA4ACAj/JZAFAE4DAAoABwiQH7cMAAwCAAAA.Nothing:BAAALAADCgcIBwAAAA==.',['Në']='Nëro:BAAALAAECgcIDQABLAAECggIFgADAHYZAA==.',Ob='Obley:BAAALAADCggICgAAAA==.',Oc='Octavius:BAAALAAECgYIBwAAAA==.',Oh='Ohnezahn:BAABLAAECoEZAAIBAAgI7QqtDgCTAQABAAgI7QqtDgCTAQAAAA==.Ohshamtastic:BAAALAAECggIAQAAAA==.',On='Onkelpål:BAAALAADCgcIBwAAAA==.Onlybans:BAAALAADCgEIAQAAAA==.',Op='Ophien:BAAALAADCgEIAQAAAA==.',Or='Ortzi:BAABLAAECoEXAAIIAAcIHR0iGQBKAgAIAAcIHR0iGQBKAgAAAA==.',Pa='Paladvl:BAAALAAECgMIAwAAAA==.Palandoraii:BAAALAADCggIEAABLAAECggIGQANAOAgAA==.Palasonic:BAAALAADCggICQAAAA==.Palesyan:BAAALAADCgcIBwAAAA==.Pallastine:BAAALAAECgIIAgABLAAFFAIIAgAEAAAAAA==.Pandvoidaii:BAABLAAECoEZAAMNAAgI4CCgCwAFAwANAAgI4CCgCwAFAwAWAAMI8hI2QwCeAAAAAA==.Panghe:BAAALAAECgMIAwAAAA==.Pawnfoo:BAABLAAECoEXAAIVAAcIxA67FwBoAQAVAAcIxA67FwBoAQAAAA==.',Ph='Phteven:BAABLAAECoEYAAIFAAcIhBknIgAeAgAFAAcIhBknIgAeAgAAAA==.',Pi='Pinkthunder:BAAALAADCggICgAAAA==.Pituce:BAAALAADCggICAABLAAECggIFwAIAJgkAA==.Pizzasnegl:BAAALAAECgYIDwAAAA==.Pizzawich:BAAALAADCgUIBQAAAA==.',Pl='Plumm:BAAALAAECgUIBgAAAA==.',Po='Poshunsella:BAAALAAECgMIAwAAAA==.Potetjon:BAAALAADCgcIBwAAAA==.',Pr='Pratt:BAAALAAECgUICgAAAA==.Priestfus:BAAALAAECgYIBgAAAA==.Priset:BAAALAAECgYICQAAAA==.',['På']='Pålina:BAAALAADCggICAABLAAECggIEAAEAAAAAA==.',Qu='Quenching:BAAALAAECgYICgAAAA==.Quilldraka:BAABLAAECoEXAAICAAcIixXHGADiAQACAAcIixXHGADiAQAAAA==.',Ra='Rachaa:BAAALAAECgEIAQABLAAFFAIIBQAFAP4dAA==.Rachmana:BAAALAAFFAIIAgABLAAFFAIIBQAFAP4dAA==.Rachmania:BAACLAAFFIEFAAIFAAII/h3GDAC+AAAFAAII/h3GDAC+AAAsAAQKgRkAAwUACAihHioMAOQCAAUACAihHioMAOQCABcABQhEE3MvAEIBAAAA.Rachún:BAAALAAECgYICwABLAAFFAIIBQAFAP4dAA==.Raendin:BAAALAAECgUIBwAAAA==.Razrex:BAAALAADCgMIAgAAAA==.',Re='Rehvis:BAAALAAECgcIDAAAAA==.Renfein:BAAALAADCgMIAwAAAA==.Rennzath:BAAALAAECgYIDwAAAA==.Reroll:BAAALAADCggICAAAAA==.Revzt:BAAALAAECgUIBQAAAA==.',Ri='Riftwar:BAAALAADCgcIBwAAAA==.Riteuros:BAAALAAECggIDAAAAA==.Riv:BAAALAADCgIIAgAAAA==.Rivzouchat:BAAALAADCgcIBwAAAA==.',Ro='Robii:BAAALAAECgMIBgAAAA==.Ronning:BAAALAAFFAIIBAABLAAFFAMIBgAOABgmAA==.Ronnings:BAAALAAFFAIIBAABLAAFFAMIBgAOABgmAA==.',Ru='Rugar:BAAALAAECgUIBQAAAA==.Rumbatak:BAAALAADCggIGwAAAA==.',Sa='Saberstalker:BAAALAAECgMIAwAAAA==.Sacerdos:BAAALAADCggICAAAAA==.Sage:BAABLAAECoEXAAIDAAgIRSFOCwAOAwADAAgIRSFOCwAOAwAAAA==.',Sb='Sbkwar:BAAALAADCgEIAQAAAA==.',Sc='Scarletmoon:BAAALAAECgQIBAAAAA==.Schokolade:BAAALAADCgMIAwAAAA==.',Se='Secrid:BAAALAAECgMIBgAAAA==.Sehzei:BAAALAAECgEIAQAAAA==.Selja:BAAALAAECgUICgAAAA==.Selle:BAAALAAECgIIAwAAAA==.Selne:BAABLAAECoEXAAIOAAcIHh5jJABNAgAOAAcIHh5jJABNAgAAAA==.Seymóur:BAABLAAECoEXAAIIAAgI7RyPEACnAgAIAAgI7RyPEACnAgAAAA==.',Sh='Shadiedeath:BAAALAADCgYIBgAAAA==.Shadowzz:BAAALAAECgUICwAAAA==.Shaggers:BAAALAAECgcIDAAAAA==.Shakelia:BAAALAADCggICQAAAA==.Shamea:BAAALAAECgYICAAAAA==.Shamob:BAAALAAECgMIBQABLAAECggICgAEAAAAAA==.Shamperor:BAAALAADCgYIBgAAAA==.Shanoodle:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.Sheina:BAAALAADCggIFgAAAA==.Shinyraquaza:BAAALAAECgEIAQAAAA==.',Si='Sicarius:BAAALAAECgIIAgAAAA==.Silverpaws:BAAALAAECgcICAAAAA==.Sinnr:BAECLAAFFIEIAAITAAMI4SVfAgBUAQATAAMI4SVfAgBUAQAsAAQKgSAAAhMACAimJpEAAHoDABMACAimJpEAAHoDAAAA.',Sl='Slaughtie:BAAALAAECgUIBQAAAA==.Sliferdemon:BAAALAADCgcIDQAAAA==.',So='Soniç:BAAALAADCgYIAgAAAA==.Sorina:BAAALAADCgcIDQAAAA==.Sorìna:BAAALAADCgcICAAAAA==.',St='Stabbymcnuts:BAAALAAFFAIIAgAAAA==.Stack:BAAALAAECgQIBwAAAA==.Stampsalot:BAAALAAECgEIAQAAAA==.Stenton:BAAALAAECgUIBgAAAA==.Stfluffy:BAAALAADCgcICQAAAA==.Stjärna:BAAALAADCgQIBAAAAA==.Stolpskott:BAAALAAECgIIAgABLAAECgYICgAEAAAAAA==.Stony:BAABLAAECoEbAAIQAAgIlBx3GACcAgAQAAgIlBx3GACcAgAAAA==.Stopmenow:BAABLAAECoEUAAMHAAcIMBfFHQDnAQAHAAcIMBfFHQDnAQAPAAMIDxRuRwC+AAAAAA==.Strafe:BAAALAAECgUICQAAAA==.',Sy='Symore:BAAALAAECgYICwAAAA==.',['Sè']='Sèt:BAAALAAECggICAAAAA==.',['Sú']='Súmtingwong:BAAALAADCgcIBwAAAA==.',Ta='Tanduine:BAAALAAECgMIBAAAAA==.Tast:BAAALAAECgUIBwAAAA==.Tathamet:BAAALAADCgUIAQAAAA==.',Te='Temma:BAAALAAECgMIAwAAAA==.Temu:BAAALAAECgYIAgAAAA==.Terok:BAAALAADCgcIBwAAAA==.',Th='Thaerox:BAABLAAECoEaAAIQAAgINxjdIgBaAgAQAAgINxjdIgBaAgAAAA==.Thehunterdz:BAAALAAECgQIBAAAAA==.Thibruli:BAAALAAECgYIDQABLAAECgcIFwADAP8VAA==.Thohim:BAAALAAECgIIAQAAAA==.Thors:BAAALAAECgEIAQAAAA==.Thumper:BAAALAAECgcIEgAAAA==.',Ti='Timmietimtom:BAABLAAECoEZAAMFAAgIYx/JEgCfAgAFAAgIuxzJEgCfAgAYAAYIQxwdBwAPAgAAAA==.',To='Totemmogens:BAAALAAECgMIBQAAAA==.',Tr='Tranza:BAAALAAECgUIBwAAAA==.Trapinek:BAABLAAECoEXAAIIAAgImCQZBABNAwAIAAgImCQZBABNAwAAAA==.Trolloc:BAAALAADCggICQAAAA==.Tropicalmage:BAAALAADCgMIAwAAAA==.Truesilver:BAAALAAECgIIAgAAAA==.',Um='Umaroth:BAAALAADCggICAABLAAECgcIFwADAP8VAA==.',Un='Unknownvoid:BAABLAAECoEUAAIFAAgIrAncNQCmAQAFAAgIrAncNQCmAQAAAA==.Unofficial:BAAALAADCgMIAwAAAA==.Untrusty:BAAALAADCgYIBgAAAA==.',Ut='Uthar:BAAALAADCgcIDgABLAAECgcIFwADAP8VAA==.',Va='Vaell:BAAALAADCggICAAAAA==.Vaitaly:BAAALAAECgYIBgAAAA==.',Ve='Veeto:BAAALAAECgYICQAAAA==.Vengaboy:BAAALAAECgEIAQAAAA==.Veylith:BAAALAADCgYIBwAAAA==.',Vi='Vikjet:BAAALAAECgUIBQAAAA==.Vinbär:BAAALAADCggIEwAAAA==.Vitaly:BAAALAADCgYIBgAAAA==.',Vo='Voidtina:BAAALAAECgYIBgAAAA==.',Vu='Vulperatrade:BAAALAADCggICAABLAAECggIGQAFAGMfAA==.',Vy='Vyraxik:BAAALAAECgMIBAAAAA==.',Wa='Wacemindu:BAAALAADCgYIBwABLAAECgEIAQAEAAAAAA==.Wakan:BAAALAADCgcIBwAAAA==.Walkingkeg:BAAALAAECgIIAwAAAA==.Wapel:BAAALAADCgIIAgAAAA==.Warvulp:BAAALAAECgYICgAAAA==.',We='Weizmann:BAAALAAECgYIDAAAAA==.',Wh='Whysosoft:BAAALAADCgEIAQAAAA==.',Wi='Wicaliss:BAAALAAECgUIBgAAAA==.',Xa='Xand:BAAALAAECggIEAAAAA==.Xavirat:BAAALAADCggICAAAAA==.',Xe='Xeg:BAABLAAECoEdAAIOAAgIYCAFEADlAgAOAAgIYCAFEADlAgAAAA==.Xeraphine:BAAALAAECgQIAwAAAA==.',Xi='Xina:BAAALAADCgIIAgAAAA==.',Xk='Xkairi:BAAALAAECgYICAAAAA==.',Xo='Xolarian:BAAALAADCgEIAQAAAA==.',Ya='Yatozin:BAAALAADCgcICgABLAAECgQIBwAEAAAAAA==.',Ym='Ymva:BAAALAADCgUIBQAAAA==.',Yo='Yoruha:BAAALAADCggIFwAAAA==.Yoududu:BAAALAADCgEIAQAAAA==.',['Yö']='Yötzy:BAAALAADCggICAAAAA==.',Za='Zagan:BAAALAADCgUIBQAAAA==.Zanbar:BAAALAADCgIIAgABLAAECgYICgAEAAAAAA==.Zathana:BAAALAAECgMIBAAAAA==.',Ze='Zein:BAAALAAECgEIAQAAAA==.Zerux:BAAALAADCgEIAQAAAA==.',Zh='Zhareli:BAAALAAECgIIAwAAAA==.',Zi='Zirnidan:BAAALAADCgUIBQAAAA==.',Zu='Zulamana:BAAALAAECgUIBQABLAAECggIFwAIAJgkAA==.',Zy='Zyrrah:BAAALAADCggICAABLAAECggIHwAGAF0jAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end