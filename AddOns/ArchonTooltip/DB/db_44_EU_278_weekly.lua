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
 local lookup = {'Rogue-Subtlety','Rogue-Assassination','Mage-Arcane','Druid-Feral','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Priest-Holy','Priest-Shadow','Unknown-Unknown','Paladin-Retribution','DemonHunter-Havoc','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Monk-Windwalker','Warrior-Protection','Paladin-Protection','Mage-Fire','DeathKnight-Frost','Monk-Brewmaster','Hunter-Survival','Mage-Frost','Shaman-Enhancement','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Warrior-Arms','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver',}; local provider = {region='EU',realm='Darkspear',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aardmannetje:BAAALAAECgcIBwAAAA==.Aarli:BAAALAAECgcIBgAAAA==.',Ac='Acolyte:BAAALAAECgYICwAAAA==.',Ae='Aeriean:BAAALAADCgUIBQAAAA==.',Ai='Aidaanius:BAAALAADCggICAAAAA==.',Aj='Ajax:BAAALAADCgcICQAAAA==.',Ak='Akhorahil:BAAALAAECgcIEgAAAA==.',Al='Aldor:BAAALAADCgUICAAAAA==.Alinul:BAABLAAECoEYAAMBAAYISBpIDgCYAQABAAYIxhdIDgCYAQACAAQIcxmbNQAXAQAAAA==.Almisi:BAACLAAFFIEFAAIDAAII4Rs2DwDAAAADAAII4Rs2DwDAAAAsAAQKgR0AAgMACAjvI8cFADoDAAMACAjvI8cFADoDAAAA.Altares:BAAALAADCggIEQAAAA==.',Am='Amenti:BAAALAAECgYICQAAAA==.',An='Analyytikko:BAAALAADCgcIBwAAAA==.Antithesis:BAAALAADCgcIBwAAAA==.',Ar='Arcadie:BAABLAAECoEUAAIEAAcItRbxCwACAgAEAAcItRbxCwACAgAAAA==.Archius:BAAALAADCgUIBQAAAA==.Arcos:BAAALAAECgMIBwAAAA==.Ariels:BAAALAADCgEIAQAAAA==.Aristrasza:BAAALAAECgIIAgABLAAECggIHQADALsYAA==.Arjyna:BAABLAAECoEdAAIDAAgIuxjnJgA7AgADAAgIuxjnJgA7AgAAAA==.Arkjin:BAAALAADCgYIBwAAAA==.Arli:BAAALAAECgYIBwAAAA==.Arotar:BAAALAADCgUIBQAAAA==.',As='Asesusi:BAAALAAECgMIBAABLAAECggIGQAFAL0UAA==.Ashrendar:BAAALAADCgMIAwAAAA==.Ashton:BAAALAAECgYICwAAAA==.Ashvara:BAAALAADCggICAAAAA==.Asttrall:BAAALAAECgEIAQABLAAFFAMIBQAGABAjAA==.Asui:BAAALAADCgUIBQAAAA==.',At='Athela:BAAALAAECgMIBAAAAA==.Atremis:BAAALAAECgEIAQAAAA==.',Au='Aulus:BAABLAAECoEXAAIHAAcI4hf+IAAJAgAHAAcI4hf+IAAJAgAAAA==.',Av='Avicii:BAAALAAECgEIAQAAAA==.Avokado:BAAALAAECgUIBQAAAA==.Avox:BAACLAAFFIEFAAIIAAIIrg2YDgCSAAAIAAIIrg2YDgCSAAAsAAQKgR4AAggACAjsH/kFANoCAAgACAjsH/kFANoCAAAA.',Ax='Axeyoulater:BAAALAAECgYIEwAAAA==.',Ay='Aysa:BAAALAADCggIEwABLAAECggIHQADALsYAA==.',Az='Azuras:BAAALAADCggIDgAAAA==.',Ba='Baayaz:BAAALAAECgUICwAAAA==.Baelrog:BAAALAAECgIIAgAAAA==.Bajaz:BAAALAAECgMIAwAAAA==.Bajo:BAAALAADCggICQAAAA==.Baldasf:BAAALAADCgUIBQAAAA==.Bandokid:BAAALAADCgYICgAAAA==.Bangplop:BAAALAADCgUIBQAAAA==.Bartula:BAAALAADCggICAAAAA==.Bazuell:BAAALAAECgUIDAAAAA==.',Be='Beasthart:BAAALAADCgQIBAAAAA==.Belfamous:BAAALAADCggICAAAAA==.Belzee:BAAALAAECgIIAgAAAA==.Benedicitus:BAAALAAECgEIAgAAAA==.Bennedictus:BAABLAAECoEXAAMJAAcISyCvDgCSAgAJAAcISyCvDgCSAgAKAAIIMRRmVACKAAAAAA==.Bertmeister:BAAALAAECgMIAwAAAA==.',Bi='Bifkin:BAAALAADCgcIDQABLAAECgcIDwALAAAAAA==.Bistecca:BAACLAAFFIEKAAIMAAUIixXxAADIAQAMAAUIixXxAADIAQAsAAQKgSAAAgwACAjQJRsEAF4DAAwACAjQJRsEAF4DAAAA.',Bl='Blazeinyour:BAAALAAECgIIBAAAAA==.Bllué:BAACLAAFFIEFAAINAAMIURm3BgAEAQANAAMIURm3BgAEAQAsAAQKgR8AAg0ACAhVJR8GAEQDAA0ACAhVJR8GAEQDAAAA.Bloedpalli:BAAALAAECgQIBQAAAA==.',Bo='Bodele:BAAALAAECgQIBwAAAA==.Bodpala:BAAALAADCgEIAQAAAA==.Bodresto:BAAALAADCgMIAwAAAA==.Botok:BAAALAADCggICAAAAA==.Bouthazar:BAAALAADCggIFwABLAAECgMIAwALAAAAAA==.',Bu='Bublq:BAAALAAECgcIBwAAAA==.Bumbadruid:BAAALAADCgYIBQAAAA==.Burias:BAAALAAECggIEQAAAA==.Buymethings:BAAALAAECgYIDQAAAA==.',Ca='Cakeordeath:BAAALAADCggICAABLAAECgYICQALAAAAAA==.Cakura:BAAALAADCgcIDAABLAAECggIHQADALsYAA==.Carmil:BAAALAADCgMIAgABLAAECggIHQADALsYAA==.Carnifex:BAAALAADCggIFAAAAA==.Carrotpeeler:BAAALAAECgUIDgAAAA==.',Ch='Chamzer:BAAALAAECgYIEQAAAA==.Chaosragé:BAAALAAECgYIDAAAAA==.Chaosstriker:BAAALAADCggICQAAAA==.Character:BAAALAAECgEIAQABLAADCggIDwALAAAAAA==.Chichiro:BAAALAAECgUICAAAAA==.Chillindeath:BAAALAAECgYIBgAAAA==.Chlore:BAAALAADCgIIAgAAAA==.Chokopop:BAAALAADCgIIAgAAAA==.Chrille:BAAALAADCgEIAQAAAA==.Chromehound:BAAALAADCggICQAAAA==.Chrumble:BAAALAADCggIGAAAAA==.',Cm='Cmpunk:BAAALAADCgcIBwAAAA==.',Co='Cobz:BAAALAAECggICAAAAA==.Colboom:BAAALAAECgMIAwAAAA==.Colon:BAAALAAECgQICwAAAA==.Colskar:BAAALAADCgYICgAAAA==.Concate:BAAALAADCgYIBwAAAA==.Conkina:BAAALAAECgYIBgABLAAECgcIEwALAAAAAA==.Construction:BAAALAAECgEIAQAAAA==.',Cr='Crysez:BAABLAAECoEXAAQOAAcIBRyNMwCyAQAOAAYIGByNMwCyAQAPAAQIRBWkNQAfAQAQAAEI4wE0NAA4AAAAAA==.Crystallense:BAAALAAECgMIBAAAAA==.',['Cà']='Càmeltotèm:BAAALAAECgMIAwAAAA==.',Da='Dandapanda:BAAALAAECgMIAwAAAA==.Daphny:BAAALAAFFAIIBAAAAA==.Darkkhunter:BAAALAAECgMIAwAAAA==.Daruka:BAAALAAECgEIAQAAAA==.Dasein:BAAALAAECgIIBAAAAA==.Dassem:BAAALAADCgcICQAAAA==.',Dd='Ddust:BAAALAADCggICAAAAA==.',De='Deamonlord:BAAALAAFFAIIAgAAAA==.Decima:BAAALAAECgMIBwAAAA==.Defiance:BAAALAADCgQIBAAAAA==.Delija:BAAALAAECgcIDAAAAA==.Demongoyoink:BAAALAAECgMIAwAAAA==.Demônnight:BAAALAADCgYIBgAAAA==.Detlilledyr:BAAALAAECgQIBAAAAA==.Detrixdh:BAAALAAECgcIEgAAAA==.',Di='Diezel:BAAALAAECggICwAAAA==.Diorelle:BAAALAAECgYICwAAAA==.Dioria:BAAALAADCggIEAAAAA==.Divicions:BAAALAADCgcIBwAAAA==.Divinius:BAAALAADCggICwAAAA==.',Dr='Dracoulinis:BAAALAAECgcIDwABLAAECggIHQADAJMiAA==.Draegon:BAAALAAECgMIAwAAAA==.Dragite:BAAALAAECgMIAwAAAA==.Dragow:BAAALAADCgQIBAAAAA==.Draneor:BAAALAAECgEIAQAAAA==.Driggi:BAAALAADCggICAAAAA==.Driggì:BAAALAADCgYIBgAAAA==.Driggï:BAAALAAECgYIDQAAAA==.',Du='Duidii:BAABLAAECoEZAAMIAAgIjSRHAgArAwAIAAgIjSRHAgArAwARAAQIliJJKwCIAQAAAA==.Dunorange:BAAALAADCgYIBgAAAA==.',['Dé']='Décayaway:BAAALAAECgQICAAAAA==.Démonsausage:BAAALAAECgMIAwAAAA==.',Ee='Eemil:BAACLAAFFIEFAAIGAAIIwgxoFQCDAAAGAAIIwgxoFQCDAAAsAAQKgR4AAgYACAj4GMAfABMCAAYACAj4GMAfABMCAAAA.',El='Eldengoat:BAABLAAECoEZAAISAAgIQCFXBQDwAgASAAgIQCFXBQDwAgAAAA==.Elgkne:BAAALAAECgMIBwAAAA==.Elisyan:BAAALAAECgYIDgAAAA==.',Er='Erelinde:BAAALAAECgYIDgAAAA==.',Es='Escudo:BAABLAAECoEZAAMFAAgIvRSHHwAcAgAFAAgIqRSHHwAcAgATAAIIuAsSPgBmAAAAAA==.Espartaco:BAAALAADCgYIBgAAAA==.',Ev='Evkoko:BAAALAAECgcIDQAAAA==.',Ey='Eylwen:BAABLAAECoEVAAMUAAcIQxvnDwDZAQAMAAYIqBubPgDaAQAUAAcIIhfnDwDZAQAAAA==.',Ez='Eztac:BAAALAADCggIDwAAAA==.',Fa='Fatfrodo:BAAALAAECgUICAAAAA==.',Fe='Felson:BAAALAADCgcIBwAAAA==.Festo:BAAALAADCgcIBwAAAA==.',Fi='Fiktive:BAACLAAFFIEGAAIIAAIIYh+1EACIAAAIAAIIYh+1EACIAAAsAAQKgR8AAggACAg1GtAVACUCAAgACAg1GtAVACUCAAAA.Filecia:BAAALAADCgcIBwABLAAECgMIBwALAAAAAA==.Filippos:BAAALAADCgYIBgAAAA==.Firus:BAAALAAECgMIAwAAAA==.Fisteye:BAAALAADCgQIBAAAAA==.Fiula:BAAALAAECgcIEwAAAA==.',Fl='Flaiy:BAAALAAECgYICgAAAA==.',Fo='Fokafellow:BAAALAAECgcIDQABLAAECggIHwAMAHEhAA==.Footumch:BAAALAADCgUICAAAAA==.',Fr='Frasseman:BAAALAADCggIGAAAAA==.',['Fé']='Féarz:BAAALAADCgcIBwAAAA==.',['Fö']='Förvandlaren:BAAALAAECgYIBgABLAAECgcIFAAHALYbAA==.',Ga='Gaarnakarhu:BAAALAAECgYIDQAAAA==.Gailiel:BAAALAADCgEIAQAAAA==.Gamerboy:BAAALAADCgEIAQAAAA==.',Ge='Geesus:BAABLAAECoEdAAISAAgIaR2NBwC2AgASAAgIaR2NBwC2AgAAAA==.Geezagoble:BAAALAADCgEIAQAAAA==.Genghar:BAAALAADCgUIBQAAAA==.',Gh='Ghostguard:BAAALAAECgIIAgAAAA==.',Gi='Gidmonk:BAABLAAECoEUAAISAAgI6xKcEwDeAQASAAgI6xKcEwDeAQAAAA==.Ginge:BAAALAAECgUIDAAAAA==.Giodragon:BAAALAAECgMIAwAAAA==.',Gl='Glazerod:BAAALAAECgEIAQABLAAECgYIBgALAAAAAA==.Glorfidel:BAABLAAECoEdAAMDAAgIkyLkCQAUAwADAAgIkyLkCQAUAwAVAAEIvA13EwA8AAAAAA==.',Gn='Gniew:BAAALAAECgQIBwAAAA==.',Go='Goofyis:BAAALAAECgQICAAAAA==.Goofyyx:BAAALAADCgYIAwAAAA==.Gougé:BAABLAAECoEVAAICAAYIcB4ZFwALAgACAAYIcB4ZFwALAgAAAA==.Goznar:BAAALAADCggICAAAAA==.Goóse:BAAALAAECgYIDAAAAA==.',Gr='Grimwuld:BAABLAAECoEeAAIWAAgIEBWCMQARAgAWAAgIEBWCMQARAgAAAA==.Grøn:BAAALAADCgEIAQAAAA==.',Gu='Gunt:BAABLAAECoEUAAIDAAcIDh5iIQBeAgADAAcIDh5iIQBeAgAAAA==.',Gw='Gwelma:BAAALAADCgQIBAAAAA==.',Ha='Haezreal:BAAALAADCgYIBgABLAAECgYICQALAAAAAA==.',He='Healpal:BAAALAAECgMIAwAAAA==.Heedme:BAAALAADCgYIBgABLAAECgcIEwALAAAAAA==.Hekla:BAAALAADCggIFgAAAA==.Hephaestus:BAAALAAECgYIEQAAAA==.Herculees:BAAALAAECgMIBAAAAA==.Herraa:BAAALAADCggIDQAAAA==.Heéd:BAAALAAECgcIEwAAAA==.',Hi='Hippiehuman:BAAALAADCgcIBwAAAA==.',Ho='Hoffa:BAAALAADCgIIAgABLAAECgcIFgADAFcVAA==.Holybloke:BAAALAAECgMIAwABLAAECgYICQALAAAAAA==.Holycoww:BAAALAAECgIIAgAAAA==.Holymagic:BAAALAAECgYIEwAAAA==.Holymeli:BAACLAAFFIEFAAIJAAIIGxICEACqAAAJAAIIGxICEACqAAAsAAQKgRYAAwkACAhcFjweAA0CAAkACAhcFjweAA0CAAoABwgOE58mAMIBAAAA.Hopeakolikko:BAACLAAFFIEFAAIXAAIIRAWiCQBqAAAXAAIIRAWiCQBqAAAsAAQKgR4AAhcACAhhEHMPAMABABcACAhhEHMPAMABAAAA.Horazon:BAAALAAECgQIBAAAAA==.Hoshiaki:BAAALAADCgYIBgAAAA==.Hotashar:BAAALAAECgYIEAAAAA==.Hotsauce:BAAALAADCgYICQAAAA==.Hotwheelz:BAABLAAECoEaAAIMAAgIOSHEDwDnAgAMAAgIOSHEDwDnAgAAAA==.',Hu='Hunterquan:BAAALAADCggICAAAAA==.Hunterz:BAAALAAECgIIAgAAAA==.',Ic='Icefyre:BAAALAADCgIIAgAAAA==.',Id='Idunno:BAAALAAECgIIBAAAAA==.',Ih='Ihminenn:BAABLAAECoEVAAMOAAcIVx7AFgB7AgAOAAcIVx7AFgB7AgAQAAEI1Q8YMgA+AAAAAA==.',Im='Imi:BAAALAAECgEIAwAAAA==.Impaler:BAAALAADCgMIAwAAAA==.',In='Ineris:BAAALAADCggIDgAAAA==.',Ir='Irgar:BAAALAAECgYIDgAAAA==.Ironwood:BAAALAADCgEIAQAAAA==.',It='Itsademon:BAAALAAECgEIAQABLAAECggIGQAIAI0kAA==.',Ja='Jackpuck:BAAALAAECgMIBwAAAA==.Jaddo:BAABLAAECoEeAAIFAAgILSPcBwAZAwAFAAgILSPcBwAZAwAAAA==.Jadzia:BAAALAAECgMIBQAAAA==.Jaffadruid:BAAALAADCggICAABLAAECggIEQALAAAAAA==.Jaffawake:BAABLAAECoEUAAIMAAcIyR7WIABjAgAMAAcIyR7WIABjAgABLAAECggIEQALAAAAAA==.',Jd='Jdogttvbrew:BAAALAADCgQIBAABLAAECgQICAALAAAAAA==.Jdogttvdk:BAAALAAECgQICAABLAAECgQICAALAAAAAA==.Jdogttvret:BAAALAADCgcIBwAAAA==.Jdogttvww:BAAALAADCgcIBwABLAAECgQICAALAAAAAA==.Jdogttvóne:BAAALAADCgcIBwABLAAECgQICAALAAAAAA==.Jdogtvsham:BAAALAADCgYIBgABLAAECgQICAALAAAAAA==.',Je='Jeffvader:BAAALAAECgYICQAAAA==.Jeppe:BAAALAAECgYIDAAAAA==.',Jm='Jmarshall:BAAALAAECgcIEgAAAA==.',Jo='Jordí:BAAALAADCggIHQAAAA==.',Jy='Jyss:BAAALAAECgYIDgAAAA==.',['Jó']='Jóols:BAAALAADCggIBwAAAA==.',Ka='Kaathe:BAAALAAECgYIDQAAAA==.Kadrin:BAAALAAECgYIDAAAAA==.Kalynovanna:BAAALAAECgEIAQAAAA==.Kaplouwy:BAAALAAECgMIAwAAAA==.Karmaa:BAAALAAECgQIBAAAAA==.Karmelita:BAAALAADCgQIBgAAAA==.Karrygan:BAAALAAECgcIDgAAAA==.Kasha:BAACLAAFFIEHAAIEAAMI6iP8AAA8AQAEAAMI6iP8AAA8AQAsAAQKgRcAAgQACAgsJSACACIDAAQACAgsJSACACIDAAAA.Kayry:BAAALAAECgcIEQAAAA==.',Ke='Kerby:BAAALAAECgUIBgABLAAECgcIFwAIAAUiAA==.Keyah:BAAALAADCgcIBwAAAA==.',Ki='Kirb:BAAALAADCgcIDQABLAAECgcIFwAIAAUiAA==.Kirbs:BAABLAAECoEXAAIIAAcIBSLDCACvAgAIAAcIBSLDCACvAgAAAA==.',Kl='Klaara:BAAALAAECgIIAwAAAA==.',Kn='Knuffelbeer:BAAALAADCggIDwAAAA==.',Kr='Kratos:BAAALAAECgMIAwAAAA==.Krishnoff:BAAALAADCggICAAAAA==.Kronoz:BAABLAAECoE6AAINAAgIcCD9DQD1AgANAAgIcCD9DQD1AgAAAA==.',Ks='Ksipit:BAABLAAECoEUAAIYAAgIRB52AQDjAgAYAAgIRB52AQDjAgAAAA==.Kspit:BAABLAAFFIEGAAIHAAIIbBU0DQCjAAAHAAIIbBU0DQCjAAAAAA==.',Kv='Kvarkki:BAAALAAECgYIDwAAAA==.',Ky='Kyrian:BAACLAAFFIEFAAIGAAMIECNpAgA4AQAGAAMIECNpAgA4AQAsAAQKgRoAAgYACAjAJb4BAD4DAAYACAjAJb4BAD4DAAAA.Kyto:BAACLAAFFIEFAAIZAAMImwxwAgDDAAAZAAMImwxwAgDDAAAsAAQKgR8AAhkACAjOIu4CADADABkACAjOIu4CADADAAAA.Kytwo:BAABLAAECoEWAAIZAAcI9yTBBAD7AgAZAAcI9yTBBAD7AgABLAAFFAMIBQAZAJsMAA==.Kyuubs:BAAALAADCgcIBwAAAA==.',La='Lamitsu:BAAALAAECgMIAwAAAA==.Land:BAAALAAECgEIAQAAAA==.Lande:BAAALAAECgIIAgAAAA==.Lathifa:BAABLAAECoEUAAIKAAgIjyKYCAD5AgAKAAgIjyKYCAD5AgAAAA==.Latiná:BAAALAAECgYICgAAAA==.Lazar:BAAALAAECgQIBAAAAA==.',Le='Leafméaloné:BAAALAAECgcIDwAAAA==.Lebra:BAAALAADCgcICQAAAA==.Legolar:BAAALAAECgEIAQAAAA==.Leksa:BAAALAADCggICAAAAA==.Lema:BAAALAAECgQIBwAAAA==.Leodorf:BAAALAAECgYIDwAAAA==.Leyandra:BAAALAADCggIDwAAAA==.',Li='Liekitär:BAAALAADCgcIBwAAAA==.Lightsheild:BAAALAAECgQICAAAAA==.Lillematron:BAAALAAECgEIAQAAAA==.Lilyna:BAAALAADCggICwABLAAECggIHQADALsYAA==.Lilyu:BAAALAAECgYIDQAAAA==.Lionhart:BAAALAAECgYIDwAAAA==.Lisko:BAAALAADCgEIAQAAAA==.Listrom:BAAALAADCgQIBAAAAA==.Litenshaman:BAABLAAECoEUAAMHAAcIthsYHwAYAgAHAAcIlRYYHwAYAgAaAAcIvBXtCgC/AQAAAA==.Lizardlips:BAAALAADCgcIBwAAAA==.Lizzandrò:BAAALAAECgYIBwAAAA==.',Ll='Llagellwynn:BAAALAAECgMIAwAAAA==.',Lo='Lobos:BAAALAADCggICAAAAA==.Lowshammy:BAAALAADCggIFwAAAA==.Loxarica:BAAALAADCgYIBwAAAA==.',Lu='Lucifa:BAAALAAECgEIAQAAAA==.Luffy:BAAALAAECgYIBgAAAA==.',Lv='Lvmage:BAAALAADCgUIBQABLAAECgcIFAANAE0fAA==.Lvxyz:BAABLAAECoEUAAINAAcITR88HAB8AgANAAcITR88HAB8AgAAAA==.',Lw='Lwo:BAAALAAECgYIDQAAAA==.',Lx='Lx:BAAALAAECgMIBQABLAAECgcIFAANAE0fAA==.',Ly='Lynxyy:BAAALAAECggIDwAAAA==.',['Lù']='Lùsh:BAAALAADCgMIAwAAAA==.',Ma='Madiss:BAAALAAECgYIBgAAAA==.Maella:BAAALAAECgIIBgAAAA==.Magnei:BAAALAAECgcICwAAAA==.Magnolian:BAAALAAECgEIAQABLAAECgMIAwALAAAAAA==.Magnusthered:BAAALAAECgQIBgAAAA==.Mahrn:BAAALAADCgYIBgAAAA==.Maleina:BAAALAAECgcIEgAAAA==.Marschall:BAAALAAECgYICAAAAA==.Mauritius:BAAALAADCgcIBwAAAA==.',Me='Meave:BAAALAAECgEIAQAAAA==.Megashock:BAAALAAECggIEgAAAA==.Melancholy:BAAALAAECgMIAwAAAA==.Melisandra:BAAALAAECgYIBgAAAA==.Melkorh:BAACLAAFFIEFAAMPAAIIhQW1CwCSAAAPAAIIhQW1CwCSAAAOAAEIZQYjIQBDAAAsAAQKgRoABA4ACAgnHGcUAJACAA4ACAiTG2cUAJACAA8AAghYGWtMAKAAABAAAghHCR0lAHcAAAAA.',Mi='Mihu:BAAALAAECgYIDAAAAA==.Miki:BAAALAADCgUIBQAAAA==.Milkyboy:BAAALAADCgIIAgAAAA==.Mitss:BAAALAAECgcIEwAAAA==.Miwbu:BAABLAAECoEaAAIMAAgIIR9xEQDZAgAMAAgIIR9xEQDZAgAAAA==.Mizzgaia:BAAALAADCgQIBAABLAAECggIBgALAAAAAA==.Mizzgaya:BAAALAAECggIBgAAAA==.',Mk='Mk:BAAALAAECgMIAwAAAA==.Mkenziea:BAAALAAECgYICAAAAA==.',Mo='Mode:BAAALAADCggICAAAAA==.Mooletov:BAAALAAECgQICAAAAA==.',Mu='Mun:BAAALAADCggICQAAAA==.',Mw='Mwz:BAAALAAECgcIEQAAAA==.',['Mé']='Méat:BAAALAAECgMIBwAAAA==.Méwtow:BAABLAAECoEUAAIbAAcI/xB8KQCeAQAbAAcI/xB8KQCeAQAAAA==.',['Mó']='Móardots:BAAALAAECgYIDwAAAA==.',Na='Nacepen:BAAALAADCggICAAAAA==.Nakato:BAABLAAECoEZAAIDAAgICx98FQCzAgADAAgICx98FQCzAgAAAA==.',Ne='Nerate:BAAALAAECgYICwAAAA==.Nesfitus:BAAALAAECgYICwAAAA==.',Ni='Nienor:BAAALAAECgMIAwAAAA==.Niteworlok:BAAALAAECgEIAQAAAA==.',No='Noble:BAAALAAECggICgAAAA==.Noff:BAAALAAECgMIAwAAAA==.Nogrud:BAAALAADCggICAAAAA==.Northdal:BAAALAADCggICAAAAA==.Notsack:BAAALAAECgYIEQAAAA==.Nowallia:BAAALAAECgIIAgAAAA==.',Nu='Nuorimmainen:BAAALAADCggICAABLAAECgYIEQALAAAAAA==.',Ny='Nyari:BAAALAAECggICAAAAA==.Nymphet:BAAALAADCggIDwAAAA==.Nymue:BAABLAAECoEhAAIWAAgIQiXGBgAxAwAWAAgIQiXGBgAxAwAAAA==.Nynâeve:BAAALAAECgYIBAAAAA==.',['Ní']='Nísse:BAAALAADCgcIBwAAAA==.',['Nø']='Nøx:BAAALAADCggIBgAAAA==.',Ob='Oblivious:BAAALAADCgIIAgAAAA==.',Od='Odågan:BAAALAADCggIDwAAAA==.',Ol='Ollieholly:BAABLAAECoEfAAIMAAgIcSGQEADhAgAMAAgIcSGQEADhAgAAAA==.',Om='Omsa:BAAALAADCggIDwAAAA==.',Or='Orolorou:BAAALAAECgYIDwAAAA==.',Ov='Oviaukkoo:BAAALAAECgQICAAAAA==.Ovîaukko:BAAALAAECgIIAgAAAA==.Ovîukko:BAAALAADCgUIBQAAAA==.',Pa='Paladinho:BAAALAAECgYIDAAAAA==.Palaquan:BAAALAADCgcIBwAAAA==.Pallamicho:BAAALAADCgEIAQAAAA==.Pallyban:BAAALAAECggIEQAAAA==.Panserdyret:BAAALAAECgMIBQAAAA==.',Pe='Pewpewpetiew:BAAALAAECgMIAwAAAA==.',Ph='Phealan:BAAALAADCgMIAwAAAA==.Phenom:BAAALAAECgYICQAAAA==.',Pl='Plantation:BAAALAADCgcIBwAAAA==.Pluckymage:BAABLAAECoEVAAIDAAcIZhnOKwAfAgADAAcIZhnOKwAfAgAAAA==.',Po='Poing:BAAALAADCgQIBAAAAA==.Pookiemug:BAAALAADCgcIBwAAAA==.Powha:BAAALAAECgYIBgABLAAFFAIIBQAIAK4NAA==.',Pr='Proudorc:BAAALAADCggICAAAAA==.',Ps='Psykedelia:BAAALAAECgUIBQAAAA==.',Pu='Pubiruusu:BAABLAAECoEVAAMBAAYIXyKnBgBFAgABAAYI4iGnBgBFAgACAAYI0BzRHgDEAQAAAA==.Pupkat:BAAALAADCgUIBQAAAA==.Purplelilly:BAABLAAECoEXAAIcAAcImw8bPACaAQAcAAcImw8bPACaAQAAAA==.',Pw='Pwd:BAABLAAECoEWAAICAAcIUhfZFwADAgACAAcIUhfZFwADAgAAAA==.Pwgoose:BAAALAAECgMIAwAAAA==.',Py='Pyronova:BAAALAADCgEIAQAAAA==.',Qu='Quacky:BAAALAADCgYIBgAAAA==.Quietus:BAAALAADCgYIBgAAAA==.',Ra='Rachetdrake:BAAALAAECgYIDAAAAA==.Raenel:BAAALAADCggIFQAAAA==.Ragebear:BAAALAAECgYIDAAAAA==.Rakhid:BAAALAADCggIFwAAAA==.Ramicus:BAAALAAECgcIDwAAAA==.Ranzog:BAABLAAECoEUAAIWAAYIYiCKNAADAgAWAAYIYiCKNAADAgAAAA==.Raskiik:BAAALAAECgYIDQAAAA==.Rassi:BAAALAAECgQICAAAAA==.Ravenford:BAAALAAECgIIAwAAAA==.Rayo:BAAALAAECgYIDgAAAA==.Razzvy:BAAALAADCggIEAAAAA==.',Re='Reappergrimm:BAAALAADCggIFgAAAA==.Reddevíl:BAAALAADCgMIAwAAAA==.Reecicle:BAAALAAECgcIEwAAAA==.Renku:BAAALAAECgYIEQAAAA==.Resurrected:BAAALAADCgcIBwAAAA==.',Ri='Rijoca:BAAALAAECggICQAAAA==.Rijöca:BAAALAADCgcIBwABLAAECggICQALAAAAAA==.Rikbull:BAAALAADCgcIBwABLAAECgMIAwALAAAAAA==.Ritualetdudu:BAAALAAECgYICAAAAA==.Ritualetsham:BAAALAAECgMIBAAAAA==.',Ro='Rocknrollah:BAAALAAECgYIDwABLAAECgcIDgALAAAAAA==.Rookie:BAABLAAECoEUAAIGAAgICB8DDAChAgAGAAgICB8DDAChAgAAAA==.Ropet:BAAALAAECgUIBwAAAA==.Rostamdastan:BAAALAAECgYICwAAAA==.',Ru='Ruoja:BAAALAAECgYIEQAAAA==.',Ry='Ryll:BAAALAAECgYICAAAAA==.Ryuitora:BAACLAAFFIEFAAINAAIIfw0kFQCaAAANAAIIfw0kFQCaAAAsAAQKgR4AAg0ACAhIIgMLABIDAA0ACAhIIgMLABIDAAAA.Ryukim:BAAALAAECgYIDwABLAAECgcIGQAbAJ4kAA==.Ryukin:BAABLAAECoEZAAIbAAcIniTWCQDWAgAbAAcIniTWCQDWAgAAAA==.',['Rã']='Rãith:BAABLAAECoEXAAIdAAcIxhTgDQC6AQAdAAcIxhTgDQC6AQAAAA==.',['Rì']='Rìesa:BAAALAADCgcIBwAAAA==.',Sa='Saethir:BAAALAAECgcIBwAAAA==.Sainty:BAAALAADCggICAAAAA==.Saladman:BAACLAAFFIEGAAMFAAIIpyVOCADRAAAFAAIIpyVOCADRAAAeAAEIDSTeAgBuAAAsAAQKgR0AAgUACAgCJSYCAGkDAAUACAgCJSYCAGkDAAAA.Sambucaa:BAAALAADCggICAAAAA==.Sammutin:BAAALAADCgYIBgAAAA==.Sapy:BAAALAAECgEIAQAAAA==.Sargantana:BAAALAAECgUIBQAAAA==.Sarili:BAAALAAECgcIEgAAAA==.Sariza:BAAALAAECgUICAAAAA==.Sausagédan:BAAALAADCggIDwABLAAECgMIAwALAAAAAA==.Sauxor:BAAALAAECgYICgAAAA==.',Sc='Schevalier:BAAALAAFFAEIAQAAAA==.',Se='Sedavern:BAAALAAECgEIAQAAAA==.Senzo:BAAALAAECgYIBgAAAA==.',Sh='Shadopan:BAACLAAFFIEKAAIFAAQIuBckAgCZAQAFAAQIuBckAgCZAQAsAAQKgSAAAgUACAgLJokAAIkDAAUACAgLJokAAIkDAAAA.Shadowphyre:BAABLAAECoEPAAIPAAcI2xAeFwDYAQAPAAcI2xAeFwDYAQAAAA==.Shady:BAAALAAECgcIDwAAAA==.Shalendra:BAAALAADCggICgABLAAECggIHQADALsYAA==.Shamash:BAAALAAECgQIBwAAAA==.Shanna:BAAALAADCggIFQAAAA==.Shavenraven:BAAALAAECgMIAwAAAA==.Shellock:BAAALAADCgYIBgAAAA==.Shenyun:BAAALAAECgIIAwAAAA==.Shipowner:BAAALAADCgEIAQAAAA==.Shockxwave:BAAALAAECgQIBwAAAA==.Shortstoof:BAAALAADCgQIBAAAAA==.Shsks:BAABLAAECoEVAAIMAAgIIBpKIQBgAgAMAAgIIBpKIQBgAgAAAA==.Shtyt:BAAALAAECgYICgAAAA==.Shynita:BAAALAADCggIFgABLAAECggIHQADALsYAA==.',Si='Sickbats:BAABLAAECoEaAAMWAAcI0CSnFAC3AgAWAAcIDCSnFAC3AgAfAAYIpSStCABpAgAAAA==.Sindrath:BAAALAADCgMIAwAAAA==.Siperia:BAAALAAECgYIDwAAAA==.',Sk='Skitsöt:BAAALAAECgYIDwAAAA==.Skorgrim:BAAALAAECgMIAwABLAAECgMIBAALAAAAAA==.Skystar:BAAALAAECgYIDwAAAA==.',Sl='Slackadin:BAAALAADCggIGwAAAA==.Slatka:BAAALAADCgcIDAAAAA==.Sleeples:BAABLAAECoEVAAIZAAcIvxmZDwAwAgAZAAcIvxmZDwAwAgAAAA==.Sleepyjoettv:BAAALAAECgYICAAAAA==.Slonoes:BAABLAAECoEWAAIbAAcIriAvDwCOAgAbAAcIriAvDwCOAgAAAA==.Slooj:BAAALAAECgcIEgAAAA==.',Sm='Smorc:BAAALAAECgIIAQAAAA==.',Sn='Sneakyorc:BAAALAAECggICAAAAA==.Snugger:BAABLAAECoEXAAIFAAcI6h+XEQCjAgAFAAcI6h+XEQCjAgAAAA==.',So='Solfortis:BAAALAAECgIIBQAAAA==.Soljinn:BAAALAADCgQIBAAAAA==.Soluna:BAAALAADCgYICQABLAAECgIIAgALAAAAAA==.Soulbinder:BAAALAADCggIFwAAAA==.',Sp='Spagnip:BAAALAADCgcIBwAAAA==.Sparkus:BAAALAADCggIHwAAAA==.Spreadsheet:BAAALAAECgUIBQAAAA==.Spyroe:BAAALAADCgcIFAAAAA==.',St='Standale:BAAALAADCgIIAgAAAA==.Stormcloud:BAAALAAECgYICQAAAA==.Styrmir:BAAALAAECgYICgAAAA==.',Su='Sunguardmatt:BAAALAAECgQICAAAAA==.Sunriis:BAAALAAECgYIBgAAAA==.Superstar:BAACLAAFFIEJAAIbAAUIphG4AQCZAQAbAAUIphG4AQCZAQAsAAQKgRkAAxsACAhIIMcRAG0CABsACAjgH8cRAG0CABgABghnGx4GAN0BAAEsAAMKCAgPAAsAAAAA.Suyan:BAAALAADCgcIEwABLAAECggIHQADALsYAA==.',Sw='Swol:BAAALAADCgYIBgAAAA==.Swordslinger:BAAALAAECgUIDgAAAA==.',Sy='Syldara:BAAALAAECgMIAwAAAA==.Sylvix:BAAALAADCggICAAAAA==.',Ta='Tabaluga:BAAALAAECgYICwAAAA==.Taerine:BAAALAAECgYIDAAAAA==.Takara:BAABLAAECoEfAAIKAAgIKBIoHQAOAgAKAAgIKBIoHQAOAgAAAA==.Talizorrah:BAAALAAECgEIAgAAAA==.Tamissa:BAAALAAECgQIBAAAAA==.Tapi:BAABLAAECoEXAAMDAAcIIRFZQgCyAQADAAcISQ9ZQgCyAQAZAAEIXh84VQBFAAAAAA==.Tarkan:BAAALAADCgcIBwABLAAECgUIBQALAAAAAA==.',Te='Teippaajapro:BAAALAADCgcICAAAAA==.Telen:BAAALAAECgMIAwAAAA==.Tempests:BAABLAAECoEXAAIaAAcIdRQ4CQDoAQAaAAcIdRQ4CQDoAQAAAA==.Terlegkolas:BAAALAAECgYIBgABLAAECggIHQADAJMiAA==.Testosi:BAAALAADCgQIBQAAAA==.',Th='Thaiijen:BAAALAAECgMIAwAAAA==.Thandros:BAAALAADCggIEQAAAA==.Tharodin:BAAALAADCgQIBQAAAA==.Thotmep:BAAALAAECgYICwAAAA==.Three:BAAALAADCggIDwAAAA==.Thurree:BAAALAAECgUICQAAAA==.Thylluna:BAAALAAECgIIAgABLAAFFAQICgAFALgXAA==.',Ti='Tiddies:BAAALAAECgYIBwAAAA==.Tig:BAABLAAECoEVAAMgAAcIfho6EgA4AgAgAAcIfho6EgA4AgAhAAEILws6JQArAAAAAA==.Tingtalia:BAAALAAECgcIDwAAAA==.Tiqershark:BAAALAAECgYIEAAAAA==.',To='Toastylock:BAAALAAECggIEAAAAA==.Tomaas:BAAALAAECggIDQAAAA==.Tonks:BAAALAAECgYICgAAAA==.Toteemikärry:BAAALAAECgYICgAAAA==.',Tr='Tremble:BAAALAAECgUIBQAAAA==.',Tu='Tugxd:BAAALAADCgUIBQAAAA==.Tuike:BAAALAADCggIDwAAAA==.Tukadzija:BAABLAAECoEVAAISAAcIXQ5RGQCcAQASAAcIXQ5RGQCcAQAAAA==.',Tw='Twistedsoul:BAAALAAECgIIAgAAAA==.Twizzel:BAAALAAECgMIAwAAAA==.',Ty='Tynnyripää:BAACLAAFFIEFAAIiAAIImBZyBgCtAAAiAAIImBZyBgCtAAAsAAQKgRwAAiIACAjuH2sFAL4CACIACAjuH2sFAL4CAAAA.Tyrab:BAAALAAECgUICAAAAA==.Tyreal:BAAALAAECgYICQAAAA==.Tyreel:BAAALAADCggIFAAAAA==.',Va='Vanilia:BAAALAAECgMIAwAAAA==.Vanillavla:BAAALAAECgMIAwAAAA==.Vanorange:BAAALAAECgMIBgAAAA==.Varjo:BAAALAADCgEIAQAAAA==.Varjosydän:BAAALAAECgYIDwAAAA==.Varázslatos:BAAALAAECgYIDAAAAA==.',Ve='Veerje:BAAALAAECgEIAQAAAA==.Verifier:BAAALAADCgcIBwAAAA==.',Vi='Vicidan:BAAALAAECgMIAwAAAA==.Virgilus:BAAALAAECgMIBAAAAA==.',Vo='Voidblood:BAAALAAECggICAAAAA==.',Wa='Wassap:BAAALAADCgUIBQAAAA==.',Wh='Whisperclaw:BAABLAAECoEYAAIIAAcI9wgePAAyAQAIAAcI9wgePAAyAQAAAA==.Whythewhat:BAAALAADCggICAAAAA==.',Wi='Wickedmedusa:BAAALAADCgMIAwAAAA==.Wild:BAAALAAECgMIBwAAAA==.Wiseoldtwat:BAAALAADCgMIAwAAAA==.',Wo='Woofercalm:BAACLAAFFIEHAAIXAAMI8B27AgAIAQAXAAMI8B27AgAIAQAsAAQKgR8AAhcACAjNJIgBAE8DABcACAjNJIgBAE8DAAAA.Wooferisbig:BAAALAADCggICAABLAAFFAMIBwAXAPAdAA==.Woofertheman:BAAALAAECgQIBAABLAAFFAMIBwAXAPAdAA==.Wooferwings:BAAALAAECgYIBgABLAAFFAMIBwAXAPAdAA==.Wootaa:BAAALAADCggIFAAAAA==.Wosmo:BAAALAADCgcICAAAAA==.',Wr='Wrath:BAAALAAECgcIDgAAAA==.',Xa='Xal:BAAALAADCggICAAAAA==.Xandrius:BAAALAADCgcIBwAAAA==.',Xe='Xeraal:BAAALAAECgYIDwAAAA==.',Xi='Xianyi:BAAALAAECgMIAwAAAA==.Xiphop:BAABLAAECoEeAAMcAAgIwR+CEwCTAgAcAAgI1RqCEwCTAgAbAAcIVhf6JgCvAQAAAA==.',Xo='Xolon:BAAALAADCgcIBwAAAA==.',Xt='Xtwo:BAAALAAECgIIAgAAAA==.',Xu='Xueji:BAAALAADCgcIDAABLAAECggIHQADALsYAA==.',Ya='Yanling:BAAALAADCggIDwABLAAECggIHQADALsYAA==.',Yi='Yippee:BAAALAADCgYIBgAAAA==.',Yo='Yoloek:BAAALAAECgYIDgAAAA==.',Ys='Ysemera:BAAALAAECgYIEAAAAA==.',Yu='Yumi:BAAALAAECgMIAwABLAAFFAIIBAALAAAAAA==.Yuolin:BAAALAADCgcIDwABLAAECggIHQADALsYAA==.Yuzina:BAAALAADCgcICAABLAAECggIHQADALsYAA==.',Za='Zacchaeus:BAAALAAECgEIAQAAAA==.Zadakar:BAAALAAECgMIBAAAAA==.Zaijupe:BAAALAADCgEIAQAAAA==.Zalthebar:BAAALAAECgYICAAAAA==.Zaratan:BAAALAADCgEIAQAAAA==.',Ze='Zelena:BAAALAAECgMIAwAAAA==.Zemlan:BAAALAAECgYICAAAAA==.',Zi='Zirenia:BAAALAADCgQIBAAAAA==.',Zy='Zyllco:BAAALAAECgYIBgAAAA==.',['Zô']='Zôll:BAACLAAFFIEFAAIIAAIIxh+9BwC+AAAIAAIIxh+9BwC+AAAsAAQKgR0AAggACAivJesAAFsDAAgACAivJesAAFsDAAAA.',['Ás']='Ásteria:BAAALAAECgEIAQAAAA==.Ásúná:BAAALAAECgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end