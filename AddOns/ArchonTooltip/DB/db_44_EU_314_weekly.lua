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
 local lookup = {'Druid-Balance','Unknown-Unknown','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Warlock-Destruction','Priest-Shadow','Priest-Holy','Hunter-Marksmanship','Mage-Frost','DemonHunter-Havoc','Shaman-Elemental','Shaman-Enhancement','Hunter-Survival','Druid-Guardian','Monk-Mistweaver','Priest-Discipline','Druid-Restoration','Warrior-Protection','Warrior-Fury','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Warlock-Demonology','Paladin-Holy','Warlock-Affliction','Paladin-Protection','Warrior-Arms','Mage-Fire','Druid-Feral','Monk-Windwalker','Hunter-BeastMastery','DeathKnight-Frost','Rogue-Outlaw','Monk-Brewmaster',}; local provider = {region='EU',realm='Moonglade',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Achelois:BAAALAAECgIIAwAAAA==.',Ae='Aegeus:BAAALAAECgcIDgAAAA==.Aeris:BAAALAAECgYIBgAAAA==.',Ah='Ahildan:BAAALAADCgEIAQABLAAFFAIICQABACYjAA==.',Ai='Airima:BAAALAADCggICAAAAA==.Aiyvah:BAAALAADCgEIAQAAAA==.',Ak='Akamë:BAAALAAECgQIBAABLAAFFAIIBAACAAAAAA==.',Al='Alarid:BAABLAAECoEUAAIDAAcIvh5BCwCDAgADAAcIvh5BCwCDAgAAAA==.Alarïc:BAAALAAECgYIDwAAAA==.Albane:BAACLAAFFIEJAAMEAAQIShYXCgClAAAFAAIIhRMfDgCzAAAEAAIIDxkXCgClAAAsAAQKgS0AAwQACAi1IbMQAAECAAQABwjHFrMQAAECAAUABAhWI4MxAIwBAAAA.Aldrien:BAAALAAECgIIAwAAAA==.Alexandèr:BAABLAAECoEWAAIGAAgIYR6NHwBvAgAGAAgIYR6NHwBvAgAAAA==.Alexius:BAAALAAECgIIAgAAAA==.Aloele:BAAALAADCggIIAABLAAECgEIAQACAAAAAA==.Altum:BAAALAADCgIIAgAAAA==.',Am='Ambulance:BAAALAADCggIHgAAAA==.Ammathrel:BAABLAAECoEYAAIHAAgINhSZOAAiAgAHAAgINhSZOAAiAgAAAA==.',An='Anavael:BAAALAAECgYIBgAAAA==.Andridari:BAAALAADCgMIAwAAAA==.Andrijavas:BAAALAAECgcIEAAAAA==.Andriukas:BAAALAAECgUIBwAAAA==.Antosh:BAABLAAECoEbAAIDAAcIvheREgAdAgADAAcIvheREgAdAgAAAA==.',Ar='Arandor:BAAALAAECgYIDQAAAA==.Araysh:BAABLAAECoEfAAMIAAgISBe3JgAfAgAIAAgISBe3JgAfAgAJAAYIlRryOgDEAQAAAA==.Arloth:BAAALAAECgYICAAAAA==.',As='Ashadori:BAAALAAECgYIEgAAAA==.Ashami:BAACLAAFFIEMAAMJAAQIURZgDAACAQAJAAMI9BxgDAACAQAIAAEIewuAIABNAAAsAAQKgS4AAwkACAjYI5MLAPYCAAkACAjYI5MLAPYCAAgABQhAIiQvAOwBAAAA.',At='Atarishe:BAAALAADCggICAABLAAECgYIEAACAAAAAA==.Athel:BAACLAAFFIEHAAIKAAMIYhfVCgDzAAAKAAMIYhfVCgDzAAAsAAQKgS4AAgoACAiQIfcKAAADAAoACAiQIfcKAAADAAAA.',Az='Azarion:BAAALAADCgYIBgAAAA==.Azeldots:BAAALAADCggICAAAAA==.Azurea:BAABLAAECoEUAAILAAcIpAVPRgAoAQALAAcIpAVPRgAoAQAAAA==.Azuriana:BAABLAAECoEeAAIMAAgI3h9aMQBqAgAMAAgI3h9aMQBqAgAAAA==.',Ba='Baklengsbæsj:BAAALAAECggICAAAAA==.Baroi:BAAALAADCgEIAQAAAA==.',Be='Beladir:BAAALAADCgEIAQAAAA==.',Bi='Bigpurple:BAAALAAECgQICwAAAA==.',Bl='Blackarm:BAABLAAECoEkAAQNAAgIeBtUHQCOAgANAAgIZBtUHQCOAgAGAAQI/RdhmgAEAQAOAAMIThHIHQCoAAAAAA==.Blast:BAAALAAECgYIBgAAAA==.Blowmie:BAAALAAECggIAwAAAA==.',Bo='Boffeloff:BAAALAAECgYIDgAAAA==.Bonezee:BAAALAADCgcIBwAAAA==.Bopan:BAAALAADCgcIDQAAAA==.Boug:BAAALAAECgcIDwAAAA==.',Br='Bradyn:BAAALAAECgEIAQAAAA==.Braol:BAAALAAECgcIEgAAAA==.Brenna:BAAALAADCggIEAAAAA==.Briyar:BAAALAADCggIDwAAAA==.',Bu='Burebeasta:BAAALAAECgYIBgAAAA==.',['Bú']='Búlma:BAAALAADCggICAAAAA==.',Ca='Cadmarus:BAAALAADCgMIAwAAAA==.Caelenne:BAABLAAECoEaAAMPAAcI+R5IBACLAgAPAAcI+R5IBACLAgAKAAIItghyngBNAAAAAA==.Caliras:BAAALAADCggIDAABLAAECggIHgAJAD4aAA==.Cane:BAAALAAECgYIBwAAAA==.Casturbation:BAAALAADCggICAAAAA==.Catease:BAABLAAECoEbAAIQAAgIiBDBDQC4AQAQAAgIiBDBDQC4AQAAAA==.',Ce='Celaená:BAAALAADCgcIBwAAAA==.Celata:BAAALAAECgQICQAAAA==.Celestiné:BAAALAADCgQIBAAAAA==.Celinette:BAAALAADCgcIEwAAAA==.',Ch='Chaosnoodle:BAAALAAECgUIBgABLAAECggIJAARABEaAA==.Charnvan:BAAALAAECgcIEAABLAAECgcIFwANAHEiAA==.Chichi:BAAALAAECgYICwAAAA==.Chiepa:BAAALAADCggIGwAAAA==.Cholik:BAAALAADCgYIBgABLAAFFAMIBwAHAG0lAA==.Chooby:BAAALAADCggIDgAAAA==.Choppá:BAAALAAECgIIAgAAAA==.Chulun:BAAALAADCggIGAAAAA==.',Ci='Citra:BAAALAADCgIIAgAAAA==.',Co='Colonthree:BAABLAAECoEeAAMSAAgIliFhAQAPAwASAAgIliFhAQAPAwAIAAYI4hVDQQCMAQABLAAECggIIwATAJQhAA==.Cordyceps:BAABLAAECoEfAAIDAAgI2g/dHQCwAQADAAgI2g/dHQCwAQAAAA==.Corintz:BAAALAADCggICAABLAAECggIJgAUAIsXAA==.',['Có']='Córa:BAAALAADCggIFAAAAA==.',Da='Daemin:BAAALAADCggIFwAAAA==.Dakcota:BAAALAAECgYIDQABLAAFFAQICgAVAP0UAA==.Dakcotaa:BAACLAAFFIEKAAIVAAQI/RR/CQBaAQAVAAQI/RR/CQBaAQAsAAQKgS4AAhUACAiwIoAPAA8DABUACAiwIoAPAA8DAAAA.Dantel:BAABLAAECoEhAAIWAAgIxyAmBgDlAgAWAAgIxyAmBgDlAgAAAA==.Darforth:BAABLAAECoEYAAIXAAgIpxJTXQDFAQAXAAgIpxJTXQDFAQAAAA==.Darkdash:BAAALAADCgUIBQAAAA==.Darraka:BAAALAADCgYIBgABLAAFFAMICwAYAKAgAA==.Darravin:BAAALAADCggIDwAAAA==.',De='Deathrow:BAAALAAECgcIEgAAAA==.Deathwhis:BAAALAADCggIDwAAAA==.Defauxs:BAAALAADCgYIBgAAAA==.Denoreth:BAAALAADCgYIBgAAAA==.',Di='Dibidyus:BAAALAADCgUIBQAAAA==.Diemand:BAAALAADCggICAAAAA==.Dippingsauce:BAAALAADCgEIAQAAAA==.Ditá:BAAALAADCgEIAQAAAA==.Dizsiee:BAAALAAECgIIBQAAAA==.Diás:BAABLAAECoEjAAIZAAgIWyATGwDoAgAZAAgIWyATGwDoAgAAAA==.',Dj='Djenga:BAAALAADCggIFAAAAA==.',Do='Doofybot:BAABLAAECoEfAAIVAAgIPSM6BwBOAwAVAAgIPSM6BwBOAwAAAA==.Doric:BAABLAAECoEkAAIGAAgI7yLQCAAHAwAGAAgI7yLQCAAHAwAAAA==.',Dr='Draevoris:BAAALAAECgIIAgAAAA==.Dragonmaster:BAAALAADCgUIBQAAAA==.Drbrainfriez:BAAALAAECgYIDQAAAA==.Drgoodheals:BAAALAAECggIEQAAAA==.Drulasera:BAABLAAECoEbAAMTAAgIRRe6KAAOAgATAAgIRRe6KAAOAgABAAIIGgirfABiAAAAAA==.Drunkster:BAABLAAECoEUAAIOAAcI2xKFDgDSAQAOAAcI2xKFDgDSAQAAAA==.',Du='Dutara:BAAALAADCggIDgAAAA==.',Ea='Earvin:BAAALAADCggICAABLAAECgQIBgACAAAAAA==.',Ee='Eerion:BAACLAAFFIEHAAMXAAMITRHyHADWAAAXAAMIuwnyHADWAAALAAIIJhY9CgCZAAAsAAQKgSoAAwsACAjcIw4GABwDAAsACAiiIw4GABwDABcACAiQGmgoAI0CAAAA.Eesymode:BAAALAADCggICAAAAA==.',El='Elariía:BAAALAADCgQIBAAAAA==.Ellin:BAAALAAECgYIDAABLAAFFAQICwANAGwRAA==.Ellisd:BAAALAAECgcIDwAAAA==.Ellunar:BAAALAADCgYIBgAAAA==.Elléy:BAAALAADCgYIBgAAAA==.Eltoa:BAABLAAECoEVAAIOAAcIQyJQBQCtAgAOAAcIQyJQBQCtAgAAAA==.Eléazar:BAAALAAECgYICQAAAA==.',Em='Embodruid:BAAALAAECgEIAQABLAAFFAUIDgAWAKkmAA==.Emboholy:BAAALAAECgcIDAABLAAFFAUIDgAWAKkmAA==.',En='Enyani:BAAALAAECgYIDQAAAA==.',Er='Erbstoo:BAAALAADCgEIAQAAAA==.Erfwyll:BAAALAAECgcIDgAAAA==.Erthus:BAAALAAECgcIDAAAAA==.',Es='Eshaldadh:BAAALAAECggIEQAAAA==.Esmo:BAAALAAECgYIDgAAAA==.Espírito:BAABLAAECoEdAAINAAgIZBPjMQATAgANAAgIZBPjMQATAgAAAA==.Essari:BAAALAADCggICAAAAA==.',Ev='Evikin:BAAALAADCgUIBQAAAA==.Evoklasera:BAAALAAECgYIBgAAAA==.Evokslay:BAACLAAFFIELAAIYAAMIoCDaBQAgAQAYAAMIoCDaBQAgAQAsAAQKgSkAAxgACAjcGXYLAEgCABgACAjcGXYLAEgCABoABwiAG9MYAD0CAAAA.',Ex='Exceed:BAABLAAECoEVAAMGAAYIXxHK1wCNAAAGAAQIJQfK1wCNAAAOAAMIoQKeIABsAAAAAA==.',Fa='Faldran:BAACLAAFFIEJAAIUAAMIBB8LBgAbAQAUAAMIBB8LBgAbAQAsAAQKgSkAAxQACAj1JG0DAEwDABQACAj1JG0DAEwDABUABwhgHtIlAHUCAAAA.Fandro:BAAALAADCgcIBwAAAA==.',Fe='Feisar:BAAALAADCggICAAAAA==.',Fl='Flasher:BAABLAAECoEkAAIZAAgI6hq3MgB5AgAZAAgI6hq3MgB5AgAAAA==.Flíbz:BAAALAAECgQIBgAAAA==.',Fo='Fonkeys:BAAALAAECggIEAAAAA==.Forsythra:BAAALAAECggICQABLAAECggIIQAbAFUUAA==.Forsythria:BAABLAAECoEhAAMbAAgIVRTnEwA7AgAbAAgIVRTnEwA7AgAHAAYIww23dQBYAQAAAA==.Fortissimus:BAAALAAECgUIBQAAAA==.',Fr='Fredryn:BAABLAAECoEUAAIHAAcIQQu2ZwB/AQAHAAcIQQu2ZwB/AQAAAA==.Freesya:BAAALAAECgYIDQAAAA==.Frozello:BAABLAAECoEhAAIcAAgIug58JQC3AQAcAAgIug58JQC3AQAAAA==.',Fu='Futiko:BAABLAAECoEeAAITAAgIBBd/KAAPAgATAAgIBBd/KAAPAgAAAA==.',Fy='Fyria:BAABLAAECoEmAAIUAAgIixf7GwAVAgAUAAgIixf7GwAVAgAAAA==.',Ga='Galmorag:BAABLAAECoEeAAQbAAgI0h0ZCADGAgAbAAgI0h0ZCADGAgAHAAUIhwdQogDPAAAdAAIIYQmNLgBlAAAAAA==.Garretth:BAAALAAECgYICwAAAA==.Gastly:BAAALAAECgYIDQAAAA==.',Ge='Gentoo:BAAALAADCgcIBwAAAQ==.Gentras:BAAALAADCggIEAABLAAECgQIBgACAAAAAA==.',Gh='Ghaith:BAAALAADCgQIBAABLAAECggIIwATAJQhAA==.',Gi='Gimlijrd:BAABLAAECoEaAAIeAAgIyhFJIwCZAQAeAAgIyhFJIwCZAQAAAA==.Giovani:BAAALAAECgIIAgAAAA==.',Gl='Glóinzhifu:BAAALAADCggICAAAAA==.',Go='Golddark:BAAALAADCggICAAAAA==.Goukí:BAABLAAECoEmAAIGAAgIphpjJwBLAgAGAAgIphpjJwBLAgAAAA==.',Gr='Grail:BAACLAAFFIEGAAIVAAMI0hTSDgADAQAVAAMI0hTSDgADAQAsAAQKgS4AAxUACAivHecdAKgCABUACAivHecdAKgCAB8AAggPFxclAJUAAAAA.Gratjak:BAAALAAECgIIAgAAAA==.Grispuncher:BAAALAADCggICAAAAA==.Growth:BAAALAAECgQIBgAAAA==.',Gu='Gunthaa:BAAALAADCgYIBgAAAA==.Gurm:BAABLAAECoEgAAMGAAgIYRrlIwBbAgAGAAgIYRrlIwBbAgANAAcIPA7ZVACCAQAAAA==.',Ha='Hashira:BAAALAADCggICAAAAA==.',He='Heftan:BAABLAAECoEdAAIeAAgICA3JJwB3AQAeAAgICA3JJwB3AQAAAA==.Helekõre:BAABLAAECoEmAAIgAAgI7Q+SBQAIAgAgAAgI7Q+SBQAIAgAAAA==.Herrá:BAACLAAFFIEFAAIGAAMIehBxJwCJAAAGAAMIehBxJwCJAAAsAAQKgRgAAgYACAggFJRKAM0BAAYACAggFJRKAM0BAAAA.',Hu='Huffyash:BAAALAAECgYICAAAAA==.Huntermand:BAAALAADCggIEAAAAA==.',Hy='Hygge:BAAALAAFFAIIAgABLAAFFAIIBwATAHUiAA==.Hymdall:BAAALAAECgMIAwAAAA==.',['Hé']='Héimdall:BAAALAADCggIGAAAAA==.',Ic='Icelord:BAAALAAECgcIEgAAAA==.Icetails:BAAALAADCgIIAgABLAAFFAIIAgACAAAAAA==.',Il='Ilanara:BAABLAAECoEnAAIZAAgILBmUNwBmAgAZAAgILBmUNwBmAgAAAA==.',In='Inala:BAAALAADCgMIAwAAAA==.Incisor:BAAALAAECgIIBAABLAAECggIHAALALAdAA==.',Ip='Ippe:BAAALAADCggICAAAAA==.',It='Ittygritty:BAAALAADCgQIBAAAAA==.',Iz='Izemayn:BAAALAAECggIEQAAAA==.',Ja='Jamonshamon:BAACLAAFFIEOAAINAAUIsxkIBgDLAQANAAUIsxkIBgDLAQAsAAQKgSAAAg0ACAhUI9kMABQDAA0ACAhUI9kMABQDAAAA.Jarondar:BAAALAAECgMIBAAAAA==.',Ju='Juksmonk:BAAALAAECggIEgAAAA==.Jull:BAAALAAECgYICAABLAAECggIFAANACAVAA==.',['Já']='Jábz:BAAALAADCggICAAAAA==.',['Jæ']='Jægeren:BAAALAADCggICAAAAA==.',['Jö']='Jönssi:BAAALAADCggICQAAAA==.',Ka='Kaedhunt:BAAALAADCggICAAAAA==.Kaedshadow:BAAALAADCggICAAAAA==.Kaelthir:BAAALAADCgQIBAAAAA==.Kanters:BAABLAAECoEZAAINAAgIThTjNwD1AQANAAgIThTjNwD1AQAAAA==.Kasamuthardi:BAAALAAECggIEgAAAA==.Kasuml:BAAALAAECgYICQAAAA==.Kattalia:BAABLAAECoEcAAMhAAgIfBVcEAAeAgAhAAgIfBVcEAAeAgATAAEI7QLsvAAgAAAAAA==.Kazeshíní:BAABLAAECoEZAAIMAAcI5RKYbQC2AQAMAAcI5RKYbQC2AQAAAA==.',Ke='Kerae:BAAALAADCgcIBgAAAA==.Kery:BAAALAAECgMIBAAAAA==.',Kh='Kharandriel:BAAALAAECgQIBAAAAA==.Khazradin:BAAALAAECgEIAQAAAA==.Khels:BAABLAAECoEnAAIMAAgInyAzGADqAgAMAAgInyAzGADqAgAAAA==.Khelss:BAAALAADCggIEAABLAAECggIJwAMAJ8gAA==.',Ki='Killerwomen:BAABLAAECoEjAAMhAAgIbB+qCwBsAgAhAAcIDx+qCwBsAgATAAEIoxB9sgA1AAAAAA==.Killted:BAAALAAFFAEIAQABLAAFFAMIBgAVAP4TAA==.Killtless:BAAALAADCggICAABLAAFFAMIBgAVAP4TAA==.',Kl='Kligz:BAABLAAECoEZAAMcAAgIIB31CQCzAgAcAAgIIB31CQCzAgAZAAEIWQ1DKwFFAAAAAA==.',Kn='Kneecaps:BAABLAAECoEhAAIiAAgIQhEWHADuAQAiAAgIQhEWHADuAQAAAA==.',Ko='Kobra:BAAALAADCggICAAAAA==.Koekmonster:BAAALAAECgYICgAAAA==.Kongarthur:BAAALAADCggICAAAAA==.Koxypie:BAAALAADCgUICAAAAA==.',Kr='Krieltje:BAAALAAECgUIBwAAAA==.',La='Lachdanan:BAAALAAECgcIDgAAAA==.Lajablesse:BAAALAAECgYIBwAAAA==.Lankey:BAACLAAFFIEJAAIjAAQIKBg7DAAeAQAjAAQIKBg7DAAeAQAsAAQKgS4AAiMACAi+InMQAP4CACMACAi+InMQAP4CAAAA.Lasandra:BAAALAADCgcIDgAAAA==.',Le='Lekuna:BAAALAAECgYIBgAAAA==.Lennaya:BAAALAAECgYIDwABLAAECgcIGgAPAPkeAA==.Lexikon:BAAALAAECgQIBAAAAA==.',Li='Liathin:BAABLAAECoEjAAQTAAgIlCH4CAD4AgATAAgIlCH4CAD4AgAQAAMIVBFrIQCeAAABAAMIFwzjcQCOAAAAAA==.Lightblossom:BAAALAAECgYIEwAAAA==.Lilipéd:BAAALAAECgYICgAAAA==.Lilitawa:BAAALAADCgcIBwAAAA==.Lillorigga:BAACLAAFFIEJAAINAAQIlhWXCQBZAQANAAQIlhWXCQBZAQAsAAQKgS4AAg0ACAhEJMkGAEwDAA0ACAhEJMkGAEwDAAAA.Lisburn:BAAALAADCggICAAAAA==.Lizia:BAAALAADCgUIBQAAAA==.',Ll='Llayla:BAABLAAECoEhAAIjAAgIVBSrUQDgAQAjAAgIVBSrUQDgAQAAAA==.',Lo='Lodare:BAAALAAECgEIAQAAAA==.Loktagar:BAAALAADCggIFgAAAA==.Lonelytotem:BAAALAAECgQIBQAAAA==.Lorgo:BAABLAAECoEZAAIFAAcIBA+kKgC1AQAFAAcIBA+kKgC1AQAAAA==.Loriqey:BAABLAAECoEjAAIiAAgIPRVuGAAUAgAiAAgIPRVuGAAUAgAAAA==.',Ly='Lyzara:BAACLAAFFIEKAAITAAQIESGGBACJAQATAAQIESGGBACJAQAsAAQKgS4AAhMACAgtJNkDADoDABMACAgtJNkDADoDAAAA.',Ma='Maeven:BAABLAAECoEUAAIBAAgIJSEfCgAKAwABAAgIJSEfCgAKAwAAAA==.Magicbowl:BAABLAAECoEbAAIcAAgIxhqBDQCHAgAcAAgIxhqBDQCHAgAAAA==.Maire:BAABLAAECoEhAAIjAAgImgxqbgCXAQAjAAgImgxqbgCXAQAAAA==.Makaveliuk:BAAALAADCgYICQAAAA==.Makorr:BAAALAADCggIDQAAAA==.Malachi:BAAALAAECgIIAgAAAA==.Malavai:BAABLAAECoEgAAIMAAgIKCKpEgAMAwAMAAgIKCKpEgAMAwAAAA==.Mannchu:BAAALAADCgUIBgAAAA==.Marvyn:BAAALAAECgcIEgAAAA==.',Me='Megashira:BAAALAADCgYIBgAAAA==.Meowforheals:BAAALAAECggICAABLAAECggIHwAYAL8dAA==.Meowmeow:BAAALAAFFAIIBAAAAA==.Meridian:BAAALAADCggICAAAAA==.Metalelf:BAAALAADCgYIBgAAAA==.Metalpala:BAAALAAECgYIEgAAAA==.Metalpriest:BAAALAADCggIEAAAAA==.',Mi='Mifurey:BAABLAAECoEUAAIcAAcIeBwfEwBMAgAcAAcIeBwfEwBMAgAAAA==.Mikiyaki:BAAALAADCgEIAQAAAA==.Minari:BAAALAADCggICAABLAAECgYIEAACAAAAAA==.Minudh:BAAALAADCggIEAAAAA==.Minupriest:BAAALAADCgIIAgAAAA==.Mirandanas:BAAALAAECgYIDQABLAAFFAMICAANAFEMAA==.',Mo='Monkslay:BAAALAADCgYIBgABLAAFFAMICwAYAKAgAA==.Moondancêr:BAAALAAECgUIBQAAAA==.Morpheus:BAABLAAECoEYAAIkAAYI+SLlTQApAgAkAAYI+SLlTQApAgAAAA==.',Ms='Msrgrundie:BAABLAAECoEUAAIdAAYIwhMFEACTAQAdAAYIwhMFEACTAQAAAA==.',Mt='Mt:BAAALAAECgYIBgAAAA==.',Mu='Mudhide:BAABLAAECoEYAAIKAAcIyQu/VgA+AQAKAAcIyQu/VgA+AQAAAA==.Musgrus:BAABLAAECoEUAAIMAAcI7RlqXQDcAQAMAAcI7RlqXQDcAQAAAA==.',Na='Naaiaa:BAAALAAECgMIAwAAAA==.Nadjai:BAACLAAFFIEHAAMXAAQIBQuZFQAFAQAXAAQICwmZFQAFAQAgAAEI+gjvCQBFAAAsAAQKgSYAAxcACAitH9seAL0CABcACAitH9seAL0CACAAAQjTAC8iAAkAAAAA.Naffaviel:BAAALAADCgYIBgABLAAECgcIFAAUAAwbAA==.Nakwena:BAAALAADCgcIBwABLAAECgcIGgAPAPkeAA==.Namnam:BAAALAAFFAEIAQAAAA==.Naota:BAAALAAECgQIBQAAAA==.Natf:BAAALAADCgcIBwABLAAECgcIFAAUAAwbAA==.Nazus:BAAALAAECgEIAQAAAA==.',Nb='Nbg:BAAALAADCgcIBwAAAA==.',Ne='Nephos:BAAALAADCgEIAQAAAA==.Nes:BAAALAAFFAIIAgABLAAFFAUIDQAZAEQeAA==.',Ni='Nicomachus:BAAALAADCgcIBwAAAA==.Nightssorrow:BAAALAAECgcIEAABLAAFFAMIBgAaAF0LAA==.Nilvek:BAAALAAECgcIEAAAAA==.Ninpod:BAAALAAECgUICAABLAAECggIIQAUAOYXAA==.Niriana:BAABLAAECoEfAAIaAAgIfREjIAD1AQAaAAgIfREjIAD1AQAAAA==.Nixage:BAABLAAECoEiAAIXAAcInxj4SgD/AQAXAAcInxj4SgD/AQAAAA==.',Nj='Njordis:BAAALAADCgcIBwAAAA==.',No='Novo:BAABLAAECoEdAAIaAAcI0R+GEQCMAgAaAAcI0R+GEQCMAgAAAA==.',Nu='Nurrien:BAABLAAECoEaAAIiAAgIVhV/FwAdAgAiAAgIVhV/FwAdAgAAAA==.',Nw='Nw:BAABLAAECoEVAAIVAAgIkhwtHwCfAgAVAAgIkhwtHwCfAgAAAA==.',Ny='Nythiera:BAACLAAFFIEGAAIaAAMIXQvxDADQAAAaAAMIXQvxDADQAAAsAAQKgSkAAhoACAi2Il0FAC4DABoACAi2Il0FAC4DAAAA.Nyxithra:BAABLAAECoEmAAMXAAgIDh62MABlAgAXAAcIhh62MABlAgALAAIIJBplZQCGAAAAAA==.',Op='Opheliá:BAABLAAECoEWAAITAAgIyRE7OgC5AQATAAgIyRE7OgC5AQAAAA==.',Pa='Paladinmarst:BAAALAADCgYIBgAAAA==.Palea:BAAALAADCgcIGAAAAA==.Pathra:BAAALAADCgEIAQAAAA==.Patróklos:BAAALAADCgEIAQAAAA==.',Pe='Petrichi:BAABLAAECoEZAAIRAAcIuhzyDwA8AgARAAcIuhzyDwA8AgAAAA==.',Po='Pogothy:BAAALAADCggICAAAAA==.',Ps='Ps:BAAALAADCggIDgAAAA==.',Pu='Puddles:BAAALAADCggICAAAAA==.',['Pé']='Pétri:BAAALAAECgIIAgAAAA==.',Qe='Qerthal:BAABLAAECoEoAAIHAAgIPB7/HQCvAgAHAAgIPB7/HQCvAgAAAA==.',Qu='Quakak:BAAALAAECgYIBwAAAA==.Quintraine:BAAALAADCggICAABLAAFFAQICQANAJYVAA==.Quizan:BAAALAAECgYIEAAAAA==.',Ra='Raidiant:BAAALAADCgEIAQAAAA==.Rathollo:BAAALAAECgQIBwAAAA==.Rauelduke:BAAALAAECggIEgAAAA==.Ravenian:BAAALAAECgIIAgAAAA==.Rawdy:BAAALAADCgcICAAAAA==.Rayaa:BAAALAADCgYIBgAAAA==.',Re='Regolan:BAAALAAECggIAQAAAA==.Reidens:BAAALAAECgYICgAAAA==.Remi:BAAALAAECgEIAQAAAA==.Rendalar:BAAALAADCggIFwAAAA==.Resynsham:BAAALAAECgYIBgAAAA==.Retrimootion:BAAALAAECgQICQAAAA==.Rezet:BAABLAAECoEjAAMOAAgIWha1CQAyAgAOAAgIWha1CQAyAgANAAEITRDmowA8AAAAAA==.',Ro='Rogueckle:BAAALAAECgIIAgAAAA==.Rootin:BAAALAADCggIGQABLAAECgcIFAAUAMohAA==.Roseheart:BAAALAADCggICAAAAA==.Rova:BAAALAADCgYIBAAAAA==.',Ru='Ruunal:BAAALAADCgcIDgAAAA==.',Sa='Safarax:BAAALAAECgcIDwAAAA==.Sangrielle:BAAALAAECgYICQAAAA==.Sarafan:BAAALAAECgEIAQAAAA==.',Sc='Schwerrie:BAAALAADCggIEAABLAAECgQIBgACAAAAAA==.',Se='Senketsu:BAAALAAECgYICAAAAA==.Sentenced:BAAALAADCgEIAQAAAA==.Seung:BAAALAAECgYICwAAAA==.',Sh='Shabu:BAAALAAECgYIDAAAAA==.Shamone:BAABLAAECoEXAAINAAcIgBkcOQDwAQANAAcIgBkcOQDwAQAAAA==.Shamoss:BAAALAADCgcIBwAAAA==.Sheiken:BAAALAAECggICAAAAA==.Shershagin:BAAALAADCggIDgAAAA==.Shiemba:BAAALAADCgYIBgAAAA==.Shongtar:BAABLAAECoEYAAIVAAYIHRa6VgCpAQAVAAYIHRa6VgCpAQAAAA==.Shuvi:BAACLAAFFIEKAAIXAAMIsBVrGADyAAAXAAMIsBVrGADyAAAsAAQKgScAAhcACAi8H5YdAMQCABcACAi8H5YdAMQCAAAA.',Si='Silentfist:BAAALAADCgYIBgAAAA==.Sinew:BAAALAAECgQIBwAAAA==.',Sj='Sjoeke:BAAALAADCgEIAQAAAA==.',Sk='Skullyboi:BAAALAAECgIIAgAAAA==.Skurkagurken:BAAALAADCgYIBgAAAA==.',Sn='Snoot:BAABLAAECoEUAAIUAAcIyiGNDQCsAgAUAAcIyiGNDQCsAgAAAA==.Snugglez:BAAALAADCgQIBAAAAA==.',So='Sofì:BAAALAAECgYICgABLAAFFAMICgAPAOchAA==.Solaría:BAAALAAECgYICQAAAA==.Soukar:BAAALAAECgUIBAABLAAFFAQIDAAJAFEWAA==.',Sp='Spicykebabs:BAABLAAECoEXAAMiAAcIgwaPNQAoAQAiAAcIgwaPNQAoAQARAAcIwwRgLwDqAAAAAA==.Splobotnik:BAACLAAFFIELAAIUAAMI7iXSBABSAQAUAAMI7iXSBABSAQAsAAQKgSIAAhQACAgEJAIEAD8DABQACAgEJAIEAD8DAAEsAAQKBggJAAIAAAAA.Sprockettrap:BAABLAAECoEaAAIjAAgI+hECVQDXAQAjAAgI+hECVQDXAQAAAA==.Spudfyre:BAABLAAECoEdAAMJAAgIlx3PEQC9AgAJAAgIlx3PEQC9AgAIAAYItw7VTQBUAQAAAA==.',St='Stepbro:BAABLAAECoEUAAIlAAcIKhkkBgAsAgAlAAcIKhkkBgAsAgAAAA==.Stereotype:BAAALAADCgEIAQAAAA==.Stormrow:BAABLAAECoEgAAIJAAgIQAruTAB4AQAJAAgIQAruTAB4AQAAAA==.',Sy='Sylawyn:BAABLAAECoEUAAIJAAcIPAnTWgBEAQAJAAcIPAnTWgBEAQAAAA==.Synth:BAACLAAFFIEJAAIVAAMIhhKSDwD9AAAVAAMIhhKSDwD9AAAsAAQKgSkAAhUACAjGHgEaAMQCABUACAjGHgEaAMQCAAAA.Syrax:BAAALAAECgYICQAAAA==.',Ta='Taijie:BAAALAAECgYIDQAAAA==.Talandareth:BAAALAADCgYIBgAAAA==.Targaryen:BAABLAAECoEaAAMYAAcIygltHwArAQAYAAcIygltHwArAQAaAAUIwgcbRADuAAAAAA==.Tastin:BAAALAADCgYIBgABLAAFFAQIDAAmAE8hAA==.',Tb='Tbh:BAABLAAECoEfAAIYAAgIvx26BQDEAgAYAAgIvx26BQDEAgAAAA==.',Te='Telkhuzad:BAAALAAECggIEwAAAA==.Terthor:BAAALAADCggIEAABLAAFFAQIDAAmAE8hAA==.',Th='Thelgrim:BAAALAADCgQIBAAAAA==.',Ti='Tiaana:BAABLAAECoEXAAIZAAcIzxwwQgBFAgAZAAcIzxwwQgBFAgABLAAECggIJQAaADQeAA==.Tiaanstrasza:BAABLAAECoElAAIaAAgINB7mDgCtAgAaAAgINB7mDgCtAgAAAA==.Tinodith:BAAALAADCggIEAAAAA==.',To='Toivodk:BAAALAAECgMIAwAAAA==.Tokajin:BAABLAAECoEdAAMHAAgImBhCLABeAgAHAAgImBhCLABeAgAbAAII6g0sbQCAAAAAAA==.Tokashot:BAAALAAECgcIDgABLAAECggIHQAHAJgYAA==.Tolson:BAAALAADCgcICwAAAA==.Tozie:BAABLAAECoEtAAIkAAgIBhvzQABOAgAkAAgIBhvzQABOAgAAAA==.',Tr='Treasach:BAACLAAFFIEMAAImAAQITyEGBACGAQAmAAQITyEGBACGAQAsAAQKgS4AAiYACAhXI2EEABoDACYACAhXI2EEABoDAAAA.Tricksa:BAAALAADCggIEgAAAA==.Troopp:BAABLAAECoEkAAMJAAcI1wYHYgAsAQAJAAcI1wYHYgAsAQAIAAUIfQTLagC3AAAAAA==.',Tu='Turkeychopio:BAAALAAECgYIBgABLAAFFAYIFwAZAMMkAA==.',Tw='Tweara:BAAALAAECgYICwABLAAECgcIGgAPAPkeAA==.',Ul='Ulthwé:BAAALAADCggIHgAAAA==.',Un='Unkillted:BAACLAAFFIEGAAIVAAMI/hNSDwD/AAAVAAMI/hNSDwD/AAAsAAQKgTEAAxUACAguI+ALACsDABUACAguI+ALACsDAB8ACAhqC/0TAHABAAAA.Unkuhl:BAAALAAECgMIAwAAAA==.Unnholyone:BAAALAADCggICAAAAA==.',Ur='Uria:BAABLAAECoEoAAMJAAcIIyPUDwDQAgAJAAcIIyPUDwDQAgAIAAEICRJggwBAAAAAAA==.Ursaluna:BAAALAADCgIIAgAAAA==.',Va='Vadlianof:BAAALAADCgYIBgAAAA==.Vados:BAAALAADCgIIAgAAAA==.Valenyr:BAAALAAECgQIBAAAAA==.Valerios:BAAALAAECgYICQAAAA==.Vallik:BAAALAAECgMIBAAAAA==.Vampella:BAABLAAECoEXAAMDAAcIuRBqHQCzAQADAAcIuRBqHQCzAQAkAAQImQx+AQG/AAAAAA==.Varella:BAAALAADCgEIAQAAAA==.Varila:BAAALAAFFAIIAgAAAA==.Vashine:BAAALAADCgQIBAAAAA==.',Ve='Velinas:BAAALAADCggICAAAAA==.Vennex:BAAALAAECgYIBgAAAA==.Vermminard:BAAALAAECgQIBAAAAA==.Vers:BAAALAADCgYIBgAAAA==.',Vo='Volteer:BAAALAAECgcIDwAAAA==.Voodooist:BAAALAAECgYIEAAAAA==.',['Ví']='Ví:BAABLAAECoEUAAIMAAgISh4oKQCPAgAMAAgISh4oKQCPAgAAAA==.',Wa='Wackle:BAAALAAECgEIAQAAAA==.',Wi='Wilkiee:BAAALAAECgIIAgAAAA==.Wilkiena:BAAALAAECgIIAgAAAA==.',Wy='Wy:BAAALAADCggICAAAAA==.Wynie:BAAALAAECgYIEgAAAA==.',Xo='Xora:BAECLAAFFIEbAAIQAAYIFiUNAACmAgAQAAYIFiUNAACmAgAsAAQKgTAAAhAACAgMJwMAALEDABAACAgMJwMAALEDAAAA.',Xy='Xyri:BAAALAADCggIDwAAAA==.',Ya='Yanshi:BAACLAAFFIEMAAIcAAQI7SPWAwCyAQAcAAQI7SPWAwCyAQAsAAQKgS4AAhwACAiXJdsAAF8DABwACAiXJdsAAF8DAAAA.Yarble:BAABLAAECoEUAAMNAAgIIBXvXgBgAQANAAYIPBDvXgBgAQAGAAYIOwgKtwDLAAAAAA==.',Ye='Yemy:BAABLAAECoEkAAIZAAgIgh42KAClAgAZAAgIgh42KAClAgABLAAFFAIIAgACAAAAAA==.Yesmer:BAABLAAECoEYAAIZAAcITB8mRAA/AgAZAAcITB8mRAA/AgAAAA==.',Ys='Ys:BAAALAAECgMIAwAAAA==.Ysra:BAABLAAECoEgAAIIAAgI0xhtIQBEAgAIAAgI0xhtIQBEAgAAAA==.',Yu='Yunara:BAAALAADCggIDgAAAA==.Yunsi:BAABLAAECoEcAAIWAAgIwCGGBAAOAwAWAAgIwCGGBAAOAwAAAA==.',Za='Zamira:BAAALAADCggICgAAAA==.Zannek:BAAALAADCgYIDAAAAA==.',Zc='Zc:BAAALAAECgYICgAAAA==.',Ze='Zeronara:BAAALAAECgYIDAAAAA==.',Zh='Zhourei:BAABLAAECoEbAAIfAAcIUwc7GgAeAQAfAAcIUwc7GgAeAQAAAA==.',Zi='Zizzlefizzle:BAAALAAECgMIAwAAAA==.',Zo='Zotroz:BAAALAADCgcICAAAAA==.',Zu='Zulrak:BAAALAAECgYIBgAAAA==.Zulrot:BAABLAAECoEhAAMkAAgIeBjfWAAOAgAkAAgInxffWAAOAgADAAcIHRF+HAC7AQAAAA==.',['Zó']='Zóresia:BAAALAADCggIDwABLAAECgcIDQACAAAAAA==.',['Äm']='Ämadeus:BAAALAAECgYICwAAAA==.',['Él']='Élune:BAAALAADCgcIBwAAAA==.',['Êu']='Êuclid:BAAALAADCgcICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end