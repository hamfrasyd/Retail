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
 local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Druid-Feral','DeathKnight-Blood','Mage-Arcane','Monk-Brewmaster','Warrior-Protection','Warlock-Destruction','Druid-Balance','Mage-Fire','DemonHunter-Havoc','Druid-Guardian','Evoker-Preservation','Paladin-Retribution','Paladin-Holy','Evoker-Devastation','Druid-Restoration','Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Priest-Holy','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Priest-Discipline','Mage-Frost','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Outlaw','Warrior-Fury','Rogue-Assassination','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Shaman-Enhancement','Rogue-Subtlety','Warrior-Arms',}; local provider = {region='EU',realm='LaughingSkull',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Absoul:BAAALAADCggIFwAAAA==.',Ac='Acidxoxo:BAAALAADCggIDwAAAA==.Acoldbeer:BAAALAADCgYIBgAAAA==.',Ad='Ada:BAAALAADCggICAAAAA==.',Al='Albu:BAAALAADCgcICAAAAA==.Aleksz:BAAALAADCggICAAAAA==.Alexxya:BAAALAAECggIDAAAAA==.Alina:BAAALAAECgcIDgAAAA==.Allannia:BAAALAADCgYIBgABLAAECggIGAABAGAcAA==.Alzerax:BAAALAAECgYIEAAAAA==.',Am='Ambush:BAAALAAECggIBwAAAA==.Amosel:BAAALAAECgcIBwAAAA==.',An='Anatolia:BAAALAAECgQIBAAAAA==.Animaknight:BAAALAAECggICwAAAA==.',Ar='Archimedes:BAAALAADCgYIBgAAAA==.',Au='Aurum:BAAALAAECgQIBgABLAAFFAIIAgACAAAAAA==.',Aw='Aw:BAAALAAECgIIAgABLAAFFAcIHAADADQhAA==.Awoken:BAAALAAECggICAAAAA==.',Ax='Axewrath:BAACLAAFFIEGAAIEAAIIKxpqCACfAAAEAAIIKxpqCACfAAAsAAQKgSoAAgQACAiGIucEAAcDAAQACAiGIucEAAcDAAAA.Axi:BAACLAAFFIEGAAIFAAIIZgoEPQCJAAAFAAIIZgoEPQCJAAAsAAQKgSgAAgUACAjcH+AkAJ4CAAUACAjcH+AkAJ4CAAAA.',Ba='Balddozer:BAACLAAFFIEMAAIGAAUIXgyiBABdAQAGAAUIXgyiBABdAQAsAAQKgSwAAgYACAj6H4MHANECAAYACAj6H4MHANECAAEsAAUUBwgYAAcAExQA.Barbrodoom:BAACLAAFFIEGAAIIAAIIcxj3IgCkAAAIAAIIcxj3IgCkAAAsAAQKgSwAAggACAh1IcMSAPgCAAgACAh1IcMSAPgCAAAA.',Be='Benkei:BAAALAADCgIIAgAAAA==.Bevaragåsen:BAAALAADCgcICgAAAA==.',Bi='Bigblast:BAACLAAFFIESAAIFAAUInBoOCADaAQAFAAUInBoOCADaAQAsAAQKgSQAAgUACAiHI4oSAAIDAAUACAiHI4oSAAIDAAEsAAUUBwgTAAEAAx8A.Bigboss:BAAALAAFFAIIAgABLAAFFAgIGAAHAPEjAA==.Bigdruid:BAABLAAECoEXAAIJAAgIMxrNJgAAAgAJAAgIMxrNJgAAAgABLAAFFAcIEwABAAMfAA==.Bigpee:BAACLAAFFIETAAIBAAcIAx8wAACmAgABAAcIAx8wAACmAgAsAAQKgR4AAgEACAivJtEBAGkDAAEACAivJtEBAGkDAAAA.Bingehealer:BAAALAADCgUIBQAAAA==.',Bl='Blayze:BAAALAADCggIFAAAAA==.Blitz:BAAALAADCgcIBwAAAA==.Bluewarlock:BAACLAAFFIEKAAMFAAQI6R1mDQCGAQAFAAQI6R1mDQCGAQAKAAEIURwWBgBcAAAsAAQKgSEAAwUACAhJJI0SAAIDAAUACAhJJI0SAAIDAAoAAQiSIXUWAF0AAAAA.',Bo='Boutacum:BAAALAAECgYIBgABLAAFFAIIBgALANchAA==.',Br='Brena:BAAALAAECgMIBwAAAA==.Brenson:BAAALAAECgYIEwAAAA==.Bromire:BAAALAAECgUIBQABLAAECgYIEwACAAAAAA==.',Bu='Buldog:BAAALAAECgUIBwAAAA==.Bullydozer:BAACLAAFFIEFAAIMAAMIpxR2AQDWAAAMAAMIpxR2AQDWAAAsAAQKgRwAAgwACAi3HKwEAKICAAwACAi3HKwEAKICAAEsAAUUBwgYAAcAExQA.Burnings:BAABLAAECoEsAAIFAAgI8RuYJwCRAgAFAAgI8RuYJwCRAgAAAA==.',By='Byrrah:BAAALAAECgUICQAAAA==.',['Bü']='Bürstbürn:BAAALAAECgMIAwAAAA==.',Ca='Caeruleus:BAACLAAFFIEGAAINAAIIKh+GCgC1AAANAAIIKh+GCgC1AAAsAAQKgSwAAg0ACAgPJCkBAE8DAA0ACAgPJCkBAE8DAAAA.Canine:BAAALAADCgcIBwAAAA==.',Ce='Cebiz:BAAALAADCgQIBAAAAA==.Centyfive:BAAALAADCggIDgAAAA==.',Ch='Chielsmaider:BAAALAADCgMIAwAAAA==.Chlochii:BAACLAAFFIEFAAIOAAIIwgRnOgCEAAAOAAIIwgRnOgCEAAAsAAQKgSIAAg4ACAgZG9wvAIQCAA4ACAgZG9wvAIQCAAAA.Choke:BAACLAAFFIEGAAIPAAII4hjRDgCpAAAPAAII4hjRDgCpAAAsAAQKgR4AAw8ACAhfIcsGAOACAA8ACAhfIcsGAOACAA4AAQh5FYEoAUkAAAAA.Chumbawumba:BAAALAADCggIDwAAAA==.',Co='Cobaltine:BAABLAAECoEgAAIQAAcIgBdTIgDjAQAQAAcIgBdTIgDjAQAAAA==.Coldbeer:BAAALAAECgIIAgAAAA==.',Cr='Craitz:BAAALAAECgMIAwAAAA==.Craitza:BAAALAAECgUIBQAAAA==.Crusherdruid:BAACLAAFFIEFAAIRAAMIPh65CAAHAQARAAMIPh65CAAHAQAsAAQKgRQAAhEACAi/HjAcAFUCABEACAi/HjAcAFUCAAEsAAUUBwgVABIA0x4A.',Da='Danderion:BAAALAAECgcIEgAAAA==.Darkvagician:BAAALAAECgQIBAABLAAECggIEQACAAAAAA==.Darkweaver:BAAALAAECgYIBgAAAA==.Daunt:BAABLAAECoEWAAIBAAgIbSQQDAD2AgABAAgIbSQQDAD2AgAAAA==.',De='Deatheclipse:BAAALAAECgYIEQAAAA==.Deathguard:BAAALAADCggICAABLAAFFAMIBwAQAHYOAA==.Deathmones:BAACLAAFFIEGAAIIAAIIFxffJQCeAAAIAAIIFxffJQCeAAAsAAQKgSkAAggACAhnJOMGAFADAAgACAhnJOMGAFADAAAA.Deathwish:BAAALAAECgEIAQABLAAECgcIDQACAAAAAA==.Defect:BAAALAADCgQIBAAAAA==.Defectx:BAAALAADCggICAAAAA==.Demongoon:BAABLAAECoEjAAQIAAgIaxJxTwDJAQAIAAgIug1xTwDJAQATAAcIcg8xOwBbAQAUAAMInQ76IwCoAAAAAA==.Dendario:BAAALAAECgQIBAAAAA==.Dethalex:BAAALAAECgYIDAAAAA==.Dezure:BAAALAAECgEIAQAAAA==.',Dh='Dholy:BAABLAAECoEWAAMVAAgIqxykFwDQAQALAAgI5BN3VQDxAQAVAAYIXyGkFwDQAQABLAAFFAcIFgAEAO4kAA==.Dháegon:BAAALAAECggICAAAAA==.',Di='Didntask:BAACLAAFFIEQAAIRAAYIVxcPAgD7AQARAAYIVxcPAgD7AQAsAAQKgRcAAhEACAhfIcYKAOUCABEACAhfIcYKAOUCAAAA.Dimonda:BAACLAAFFIEGAAIWAAIIyRKmHgCYAAAWAAIIyRKmHgCYAAAsAAQKgSoAAhYACAjHIHQLAPcCABYACAjHIHQLAPcCAAAA.Dimoond:BAAALAAECgQIBgABLAAFFAIIBgAWAMkSAA==.Divinedaf:BAAALAAECgUICwAAAA==.',Dk='Dkangel:BAAALAAECgMIAwAAAA==.Dkdozer:BAABLAAECoEWAAIEAAcIThaTFQC9AQAEAAcIThaTFQC9AQABLAAFFAcIGAAHABMUAA==.',Do='Dozydoo:BAAALAAECgQIAwAAAA==.',Dr='Dracodraco:BAACLAAFFIETAAMXAAYIrRcJAwD2AQAXAAYIrRcJAwD2AQABAAQIpBnCBgBOAQAsAAQKgSwAAwEACAghJlgLAPwCAAEACAgII1gLAPwCABcACAghJm0ZAMUCAAAA.Draconorea:BAACLAAFFIEGAAIEAAIIVBNTCgCIAAAEAAIIVBNTCgCIAAAsAAQKgSAAAgQACAjIHywGAOQCAAQACAjIHywGAOQCAAEsAAUUBggTABcArRcA.Dracostralz:BAACLAAFFIEOAAIYAAUIfhpeBQDcAQAYAAUIfhpeBQDcAQAsAAQKgScAAhgACAibI30LACADABgACAibI30LACADAAEsAAUUBggTABcArRcA.Dracothyr:BAACLAAFFIEOAAIQAAQIeBqfBgBnAQAQAAQIeBqfBgBnAQAsAAQKgSAAAhAACAgrIvAIAPoCABAACAgrIvAIAPoCAAAA.Dragonmaul:BAAALAAECgYIDQAAAA==.Drakeondeez:BAABLAAECoEiAAMNAAgIvBbTDAAuAgANAAgIvBbTDAAuAgAQAAcINhRIJwC8AQAAAA==.Dreadtotem:BAAALAAECggIAQAAAA==.',Du='Dunders:BAAALAADCggIDwABLAAECgcIEgACAAAAAA==.Durgus:BAACLAAFFIEKAAISAAMIZx9sCgAWAQASAAMIZx9sCgAWAQAsAAQKgSQAAhIACAh9IowIAAkDABIACAh9IowIAAkDAAAA.',Dw='Dw:BAACLAAFFIEMAAIYAAQIDRg2CQBnAQAYAAQIDRg2CQBnAQAsAAQKgRUAAhgABwi4HtotACgCABgABwi4HtotACgCAAEsAAUUBwgcAAMANCEA.',Dz='Dzamino:BAABLAAECoEWAAISAAgILRg/LgAuAgASAAgILRg/LgAuAgAAAA==.',['Dø']='Dødsridderen:BAAALAADCgIIAgAAAA==.',Ea='Eatmyaura:BAACLAAFFIELAAIPAAcIhg1iAQAtAgAPAAcIhg1iAQAtAgAsAAQKgRoAAw8ABwgBGlYhANMBAA8ABwgBGlYhANMBABkAAQgTFJJbADMAAAAA.',Ei='Eiku:BAABLAAECoEdAAIXAAgIaRp0LABhAgAXAAgIaRp0LABhAgAAAA==.',Ek='Ekuliser:BAACLAAFFIEJAAIDAAMIrxu5BgCxAAADAAMIrxu5BgCxAAAsAAQKgSoAAgMACAgUHRwIALMCAAMACAgUHRwIALMCAAAA.',Em='Emu:BAAALAAECgYIDgAAAA==.',En='Enviwar:BAAALAAECggICwABLAAFFAgIHgAFALcdAA==.',Es='Eskan:BAAALAADCggIEwAAAA==.',Ex='Exephia:BAAALAAECgYICwAAAA==.',Fe='Feibo:BAAALAADCgYIBgAAAA==.Fetacheese:BAAALAAECgUIBQAAAA==.',Fi='Fiskmåsyolo:BAAALAADCgcIBwAAAA==.',Fl='Flaggermus:BAAALAAECgUIBwAAAA==.',Fr='Frostnut:BAAALAAECggIDAAAAA==.Frosty:BAACLAAFFIEFAAIFAAIIKxiQKgChAAAFAAIIKxiQKgChAAAsAAQKgSIAAgUACAjpIuQNAB4DAAUACAjpIuQNAB4DAAAA.Frostytips:BAABLAAECoEWAAIFAAgIGRl1SgAAAgAFAAgIGRl1SgAAAgAAAA==.Froxine:BAAALAAECgIIAgAAAA==.',Fu='Futtiwar:BAAALAAECgUICwAAAA==.',Fy='Fya:BAACLAAFFIEHAAIOAAMISSBICwASAQAOAAMISSBICwASAQAsAAQKgSUAAg4ACAg2JEIPACkDAA4ACAg2JEIPACkDAAAA.',Ga='Gamz:BAECLAAFFIEUAAMJAAcIdhwOAQBEAgAJAAYIzh8OAQBEAgADAAUIXQwyAgCOAQAsAAQKgToAAwkACAjiJrgAAIwDAAkACAjiJrgAAIwDAAMACAigITwFAPcCAAAA.Gamzster:BAEALAAECgYICwABLAAFFAcIFAAJAHYcAA==.Gaozhan:BAAALAADCggICAAAAA==.Garamala:BAABLAAECoEaAAMVAAgIzw6GKAAxAQALAAYI8xCUjAB2AQAVAAgIuwqGKAAxAQABLAAFFAIIBgASACcOAA==.Garendor:BAAALAAECgYICQAAAA==.',Ge='Gedebanger:BAAALAAFFAcIAgAAAA==.Geostigma:BAAALAAECgUICwAAAA==.',Gi='Gis:BAAALAAECgYIEgAAAA==.',Go='Gossykin:BAACLAAFFIEPAAISAAUIOQsxCABAAQASAAUIOQsxCABAAQAsAAQKgRwAAhIACAjzFcVMAMYBABIACAjzFcVMAMYBAAAA.',Gr='Gretha:BAAALAAECgQIBgAAAA==.Griever:BAABLAAECoEUAAIDAAgIOhPAFQDUAQADAAgIOhPAFQDUAQAAAA==.Grimzau:BAAALAAECgYIDwAAAA==.',Gu='Gunna:BAAALAADCggIDQABLAAFFAIIBgALAJkfAA==.Gupuwarlock:BAABLAAECoEWAAMIAAgIUh5+FgDgAgAIAAgISx5+FgDgAgATAAcIThfNJADEAQABLAAFFAcIEgAFAJ0jAA==.Guspriest:BAACLAAFFIEKAAMWAAMIZhNvDwDmAAAWAAMI7hBvDwDmAAAaAAIIlxXRAQCUAAAsAAQKgRkAAxoACAgEInsBAAcDABoACAjhIXsBAAcDABYACAihEi00AOUBAAEsAAUUBwgWAA0AphkA.',Ha='Halo:BAAALAAECgcIDAAAAA==.Hawktuæh:BAAALAADCggICAAAAA==.',Hi='Hilga:BAAALAADCggIFQAAAA==.',Ho='Holyana:BAAALAAECgEIAgAAAA==.',Hu='Huntinit:BAAALAAECgYICQABLAAFFAIIBgASACcOAA==.',Hy='Hybridowner:BAABLAAECoEUAAIYAAYIGxFCWgBwAQAYAAYIGxFCWgBwAQAAAA==.',Ic='Ice:BAAALAAFFAIIAgAAAA==.',Ig='Ignorebull:BAACLAAFFIEYAAIHAAcIExQuAQBEAgAHAAcIExQuAQBEAgAsAAQKgSgAAgcACAgAJOEFACADAAcACAgAJOEFACADAAAA.',Il='Illidana:BAAALAAECgIIAgAAAA==.',Iz='Izánami:BAAALAADCggICQAAAA==.',Je='Jeeves:BAAALAAECgYICQAAAA==.',Jo='Joenz:BAAALAAECgYIDAAAAA==.Joppekpist:BAAALAAECgEIAQABLAAECggIDAACAAAAAA==.',Ju='Justfadelol:BAAALAAECggIEQAAAA==.Justus:BAAALAADCggICAAAAA==.',Ka='Kabal:BAAALAADCgMIAwAAAA==.Karolain:BAABLAAECoEhAAIbAAgIkhDiIQDkAQAbAAgIkhDiIQDkAQAAAA==.Karén:BAAALAAECggIEgAAAA==.Kathael:BAAALAAECgQIBAAAAA==.Kazrii:BAABLAAECoEUAAIYAAgIDAYKXwBgAQAYAAgIDAYKXwBgAQAAAA==.',Ke='Keb:BAABLAAECoEpAAMcAAgIJiFrLACWAgAcAAcIHyJrLACWAgAdAAcIdxo8EgAhAgAAAA==.Kebkeb:BAAALAAECgQIBAAAAA==.Keito:BAAALAADCgEIAQAAAA==.Kevin:BAAALAADCggICAABLAAECgYIEgACAAAAAA==.',Kh='Khornez:BAAALAAECgIIAgAAAA==.',Ki='Kijo:BAAALAADCgEIAQAAAA==.',Kn='Knex:BAAALAADCggIFwAAAA==.Knives:BAACLAAFFIEGAAIeAAIINBFpAwCeAAAeAAIINBFpAwCeAAAsAAQKgSwAAh4ACAgbHvUCAMMCAB4ACAgbHvUCAMMCAAAA.',Kr='Krigarson:BAAALAAFFAIIBAABLAAFFAIIBgAFAJYfAA==.',Ku='Kungfupo:BAAALAADCgQIBgAAAA==.',La='Lancelock:BAAALAADCgMIAwABLAAFFAYIAgACAAAAAA==.Lariath:BAAALAAECggIEAAAAA==.',Le='Leekolasse:BAAALAAECgUIBQABLAAECggIIQAOAPgeAA==.Leif:BAAALAAECgYIEAAAAA==.Lempo:BAAALAADCggICAAAAA==.Lensi:BAABLAAECoEeAAIKAAcIbB7hAgCQAgAKAAcIbB7hAgCQAgABLAAFFAYIAgACAAAAAA==.Lenso:BAACLAAFFIEGAAIfAAIIlBZVGwCoAAAfAAIIlBZVGwCoAAAsAAQKgRQAAh8ABghLHuQ2AB4CAB8ABghLHuQ2AB4CAAEsAAUUBggCAAIAAAAA.Leostrasz:BAAALAADCgUIBQABLAAECgYIEwACAAAAAA==.',Li='Lifar:BAAALAADCgQIBAAAAA==.Liganw:BAAALAAECgYIBgABLAAFFAIIBQALALMWAA==.Lilhunter:BAAALAADCgMIAwABLAAFFAcIFAAIAEceAA==.Lilsbank:BAABLAAECoEeAAISAAgI0gp4jQAfAQASAAgI0gp4jQAfAQAAAA==.Liss:BAAALAADCggIDgAAAA==.',Lo='Lobla:BAAALAAECgYIDAABLAAFFAIIBgAfAC4cAA==.Lolba:BAACLAAFFIEGAAIfAAIILhwHFwCzAAAfAAIILhwHFwCzAAAsAAQKgSQAAh8ACAiiJOUFAFoDAB8ACAiiJOUFAFoDAAAA.Lollba:BAAALAADCgMIAwAAAA==.Lootti:BAAALAAECgQICAAAAA==.Loti:BAABLAAECoEUAAISAAcIPBr3PAD6AQASAAcIPBr3PAD6AQAAAA==.Lovia:BAAALAAECggIBAAAAA==.',Lu='Lucky:BAAALAAFFAcIGAAAAQ==.Luckymonkas:BAAALAAFFAMICQABLAAFFAcIGAACAAAAAQ==.Luckyone:BAAALAAFFAUIEAABLAAFFAcIGAACAAAAAQ==.Luckytwo:BAAALAAFFAQICwABLAAFFAcIGAACAAAAAQ==.Lulba:BAABLAAECoEbAAIIAAcIeR+MJQCCAgAIAAcIeR+MJQCCAgAAAA==.Luntraria:BAAALAAECgQIBAABLAAECggIGAABAGAcAA==.Lurks:BAABLAAECoEXAAILAAgI0iPwFQD4AgALAAgI0iPwFQD4AgABLAAFFAQIDAAcACkiAA==.Lurx:BAACLAAFFIEMAAMcAAQIKSJmEQATAQAcAAMI+CNmEQATAQAdAAEIuxy9EgBgAAAsAAQKgSoAAxwACAheJkkKAD8DABwACAj0JUkKAD8DAB0AAwi1IkguADIBAAAA.Luti:BAAALAAECgMIAwAAAA==.',['Lá']='Lácuna:BAABLAAECoEXAAIRAAgINxIJQQCcAQARAAgINxIJQQCcAQAAAA==.',Ma='Malefice:BAABLAAECoEUAAIFAAYI+RJ/cACOAQAFAAYI+RJ/cACOAQABLAAFFAMIBwAOAEkgAA==.Manded:BAAALAAECgIIAgABLAAFFAMICgAJAHggAA==.Mandedamus:BAAALAADCgcIBwAAAA==.Matdk:BAACLAAFFIEGAAIcAAIILweGUQCDAAAcAAIILweGUQCDAAAsAAQKgR0AAxwACAjWGEhEAEQCABwACAhQGEhEAEQCAAQAAgiFFrMzAHIAAAAA.Matthia:BAAALAAECgUICwAAAA==.Maugrim:BAAALAADCgcIBwAAAA==.',Mc='Mcdwarf:BAAALAADCgYIBgAAAA==.Mcindk:BAAALAAECgMIBQAAAA==.Mcmaistro:BAABLAAFFIEGAAIFAAIIlh9cIwCyAAAFAAIIlh9cIwCyAAAAAA==.',Md='Mdmx:BAAALAADCgUIBQAAAA==.',Me='Meredy:BAACLAAFFIEGAAIgAAIIjQlFFACYAAAgAAIIjQlFFACYAAAsAAQKgSsAAiAACAiEH5AKANYCACAACAiEH5AKANYCAAAA.Merrlin:BAAALAADCggIDwAAAA==.',Mi='Midnight:BAAALAADCgEIAQAAAA==.Mijes:BAAALAADCggIGAABLAAECggIIAAIAJ8kAA==.Mikeyp:BAABLAAFFIEKAAIPAAYIPwoVAwDUAQAPAAYIPwoVAwDUAQAAAA==.Mikeypi:BAABLAAECoEYAAIWAAgIpiADEQDFAgAWAAgIpiADEQDFAgAAAA==.Miloktor:BAABLAAECoEhAAILAAgIPBP9TwAAAgALAAgIPBP9TwAAAgAAAA==.Miloraddodik:BAABLAAECoEdAAIcAAgI0xOjXQACAgAcAAgI0xOjXQACAgABLAAFFAIIBgASACcOAA==.Milosha:BAAALAADCggIDQAAAA==.Mirthshadow:BAABLAAECoEVAAILAAgIThUWVAD1AQALAAgIThUWVAD1AQAAAA==.Mistlock:BAAALAAECggIEAAAAA==.',Mo='Monoroth:BAACLAAFFIEVAAIOAAcI9Bo9AACwAgAOAAcI9Bo9AACwAgAsAAQKgSgAAg4ACAhLJo0FAGcDAA4ACAhLJo0FAGcDAAAA.Monsieurmoat:BAAALAAECgUIBgAAAA==.Monstrul:BAAALAAECgEIAQAAAA==.Mopsi:BAACLAAFFIEOAAIFAAUI4B2fCQDFAQAFAAUI4B2fCQDFAQAsAAQKgSQAAwUACAh5JLkKADADAAUACAh5JLkKADADAAoABghDFKALAEEBAAAA.Mopsidots:BAAALAAECgYIBwABLAAFFAUIDgAFAOAdAA==.',Ms='Msdemonhunt:BAAALAADCgIIAgAAAA==.',Na='Nalgust:BAACLAAFFIEQAAIhAAUI3BUcAwCsAQAhAAUI3BUcAwCsAQAsAAQKgScAAiEACAjoIv0EAP8CACEACAjoIv0EAP8CAAEsAAUUBwgWAA0AphkA.',Ne='Necronix:BAAALAADCgcIBwAAAA==.',Ni='Nicolas:BAAALAAECgcIEQAAAA==.Nightmares:BAAALAAECggICAAAAA==.Nightshadow:BAAALAADCgIIAgAAAA==.Nikifox:BAAALAAECgcIEwAAAA==.Ninjagoat:BAACLAAFFIESAAIYAAcI3SGGAADEAgAYAAcI3SGGAADEAgAsAAQKgScAAhgACAjxJhcAAKkDABgACAjxJhcAAKkDAAAA.Ninjakin:BAAALAAECggIDQAAAA==.Ninjalock:BAACLAAFFIEJAAIIAAQIUSEhDACVAQAIAAQIUSEhDACVAQAsAAQKgSAAAggACAhRJucAAJEDAAgACAhRJucAAJEDAAAA.Ninjalol:BAACLAAFFIEHAAIFAAUIpwsoDgB0AQAFAAUIpwsoDgB0AQAsAAQKgR4AAgUACAiBJIUgALQCAAUACAiBJIUgALQCAAAA.',No='Noorda:BAAALAAECgYIBgAAAA==.Nottango:BAAALAAECgcIBwAAAA==.',Ob='Obipan:BAAALAADCgEIAQAAAA==.',Og='Ogreshaman:BAAALAADCgUIBQAAAA==.',Pa='Paina:BAAALAAECgQIBAAAAA==.Paladingus:BAABLAAECoEUAAMPAAcI9BIsKgCYAQAPAAcI9BIsKgCYAQAOAAUIEBJlvgA+AQAAAA==.Pallydozer:BAAALAAECgUIBQABLAAFFAcIGAAHABMUAA==.Papi:BAAALAAECgUICwAAAA==.Pawnstar:BAABLAAECoEZAAIdAAcIpCPLBgDZAgAdAAcIpCPLBgDZAgAAAA==.Payna:BAABLAAECoEWAAIcAAcIQBgtcQDYAQAcAAcIQBgtcQDYAQAAAA==.',Pe='Pewpaw:BAAALAAFFAIIAgABLAAFFAMIBwAOAEkgAA==.',Pi='Piper:BAAALAAECgIIAgAAAA==.',Pl='Placebø:BAACLAAFFIEGAAILAAIImR95GQC5AAALAAIImR95GQC5AAAsAAQKgSAAAgsACAjIJEAHAFQDAAsACAjIJEAHAFQDAAAA.Plattfisk:BAAALAADCgMIAwAAAA==.',Pr='Proxi:BAABLAAECoEUAAIOAAYIGRcYhgCnAQAOAAYIGRcYhgCnAQAAAA==.',Pu='Puddy:BAAALAAFFAIIAgAAAA==.Pukki:BAAALAAFFAIIAgABLAAFFAMIBwAOAEkgAA==.',['Pä']='Pändora:BAAALAAECggIDgAAAA==.',Qu='Quannah:BAAALAAECgYIBgAAAA==.',Ra='Ragausalsa:BAACLAAFFIEGAAIHAAIIVhGlEwB/AAAHAAIIVhGlEwB/AAAsAAQKgSwAAwcACAjcHakQAIYCAAcACAhgHKkQAIYCAB8ABQjGHFZsAGoBAAAA.Rats:BAAALAAECgEIAQAAAA==.Razorcow:BAAALAAECgUIBgAAAA==.',Re='Reholy:BAACLAAFFIEWAAIEAAcI7iQSAADqAgAEAAcI7iQSAADqAgAsAAQKgSgAAgQACAjuJnQAAIkDAAQACAjuJnQAAIkDAAAA.Reholyfan:BAAALAAECgYIBQABLAAFFAQICgAFAOkdAA==.Rekyyli:BAABLAAECoEdAAIXAAcI0AiblABHAQAXAAcI0AiblABHAQAAAA==.Rerolly:BAAALAAECgYIDAABLAAFFAcIFgAEAO4kAA==.Revoked:BAACLAAFFIEOAAMQAAUIixwjBwBPAQAQAAQIsBojBwBPAQANAAQIogJ6CADeAAAsAAQKgSUAAxAACAh3JLQHAAwDABAACAh3JLQHAAwDAA0AAQifBNQ3ACwAAAEsAAUUBwgWAAQA7iQA.',Rh='Rhaegon:BAAALAADCggICAABLAAECggICAACAAAAAA==.Rháegon:BAAALAAECggICAABLAAECggICAACAAAAAA==.',Ri='Rilmaclya:BAACLAAFFIEOAAIfAAQIhRmHCACAAQAfAAQIhRmHCACAAQAsAAQKgTYAAh8ACAiwJdYEAGMDAB8ACAiwJdYEAGMDAAAA.Rilmaclyå:BAAALAAECgUICQAAAA==.',Ro='Rokir:BAAALAADCgEIAQAAAA==.Rorschach:BAABLAAECoEaAAIiAAgIdBPrGQAEAgAiAAgIdBPrGQAEAgAAAA==.Rosalia:BAAALAAECgUICQAAAA==.Rosaluma:BAAALAADCggIDQAAAA==.Rottington:BAAALAAECgYIEAAAAA==.',['Rï']='Rïlmaclya:BAACLAAFFIEGAAIcAAII2x3LLwCeAAAcAAII2x3LLwCeAAAsAAQKgRoAAhwACAhnHxUcAN8CABwACAhnHxUcAN8CAAEsAAUUBAgOAB8AhRkA.',Sa='Sager:BAABLAAFFIEHAAIPAAQIdh7CBACHAQAPAAQIdh7CBACHAQAAAA==.Sasori:BAAALAAECgEIAQAAAA==.',Sc='Schmutz:BAAALAAECggICAAAAA==.Scriim:BAABLAAECoEYAAIJAAcIew7uUAAwAQAJAAcIew7uUAAwAQAAAA==.',Se='Servus:BAAALAAECgIIAgAAAA==.',Sh='Sh:BAACLAAFFIEKAAILAAII8SDNFwDCAAALAAII8SDNFwDCAAAsAAQKgRYAAgsABwj7INklAJ8CAAsABwj7INklAJ8CAAEsAAUUBwgcAAMANCEA.Shader:BAAALAAECgQIBQABLAAECgYIBgACAAAAAA==.Shaderz:BAAALAADCgEIAQABLAAECgYIBgACAAAAAA==.Shadimar:BAAALAAECgYIBgAAAA==.Shadowlock:BAACLAAFFIEGAAIjAAIIkRVUFACaAAAjAAIIkRVUFACaAAAsAAQKgRQAAiMACAjwGo8iADwCACMACAjwGo8iADwCAAAA.Shadyn:BAAALAAECgQIBAABLAAECgYIBgACAAAAAA==.Shallan:BAAALAAECgUICwAAAA==.Shamu:BAAALAADCgEIAQAAAA==.Sharkhan:BAAALAADCggICAAAAA==.Sharpsong:BAAALAADCgEIAQABLAAECgYIEwACAAAAAA==.Shieldman:BAACLAAFFIEGAAIZAAQISBdsAwAmAQAZAAQISBdsAwAmAQAsAAQKgRgAAxkACAhUJLYEABsDABkACAhUJLYEABsDAA4AAQimHPEnAUoAAAEsAAUUBwgWAAQA7iQA.Shinfo:BAAALAAECgQIBAAAAA==.Shoots:BAAALAADCgQICQAAAA==.Sháegon:BAABLAAECoEZAAMSAAcIgiV9GgCKAgASAAcIgiV9GgCKAgAYAAQIbxbdcwASAQABLAAECggICAACAAAAAA==.',Si='Sinne:BAABLAAECoEVAAIfAAgImyPcDQAbAwAfAAgImyPcDQAbAwAAAA==.',Sk='Skaven:BAAALAAECgEIAQAAAA==.',Sl='Slade:BAAALAAECggIBgAAAA==.',Sm='Smauglypuff:BAAALAAECgIIAgABLAAFFAIIBgALANchAA==.Smyleedemon:BAAALAAECggIDAAAAA==.Smyleedrawar:BAAALAAECgYIBgAAAA==.Smyleedruid:BAAALAAECgYIBwAAAA==.Smörblomman:BAAALAAECgIIAgAAAA==.',So='Soulstéaler:BAAALAAECggIDAAAAA==.',Sp='Spalavac:BAACLAAFFIEGAAISAAIIJw6IMgB2AAASAAIIJw6IMgB2AAAsAAQKgSEAAhIACAiaGRwuAC8CABIACAiaGRwuAC8CAAAA.Spiritusks:BAACLAAFFIEKAAIJAAMIeCBeCAAKAQAJAAMIeCBeCAAKAQAsAAQKgS0AAgkACAixJZEDAF0DAAkACAixJZEDAF0DAAAA.Spìnxy:BAAALAAECgIIAgABLAAECgYIBwACAAAAAA==.',St='Stabnhide:BAAALAADCggICAAAAA==.Stephenlogic:BAAALAAECgUICgAAAA==.Stew:BAABLAAECoEbAAIXAAgI2B2lRgD/AQAXAAgI2B2lRgD/AQAAAA==.Stilnox:BAAALAAECgcICwAAAA==.Stingos:BAAALAAECgYIDAABLAAFFAIIBgASACcOAA==.Stonedh:BAACLAAFFIEaAAILAAcIdBkgAQCMAgALAAcIdBkgAQCMAgAsAAQKgSgAAgsACAhjJa4GAFgDAAsACAhjJa4GAFgDAAAA.Stonedru:BAAALAAECgcIEwABLAAFFAcIGgALAHQZAA==.Stonepal:BAABLAAFFIEJAAMZAAQIIx1bAgBxAQAZAAQIIx1bAgBxAQAOAAIIPg+PLQCbAAABLAAFFAcIGgALAHQZAA==.Stonewar:BAABLAAFFIEKAAMHAAUIMQkNBQBFAQAHAAUIHQkNBQBFAQAfAAMITQoDEwDRAAABLAAFFAcIGgALAHQZAA==.',Su='Suresokker:BAAALAADCgcIBwAAAA==.',Sy='Syks:BAAALAAFFAIIBAAAAA==.Syllvana:BAAALAADCggICAAAAA==.Synida:BAACLAAFFIEGAAIBAAIIDRDpHgB/AAABAAIIDRDpHgB/AAAsAAQKgSwAAgEACAgBI6MGACwDAAEACAgBI6MGACwDAAAA.',Ta='Tallfoot:BAAALAAECggIDQAAAA==.Tango:BAAALAAECggIDwAAAA==.Taobao:BAAALAADCgEIAQAAAA==.',Te='Tersilla:BAAALAADCggIIAAAAA==.',Th='Themanslayer:BAAALAAECggICgAAAA==.Thock:BAACLAAFFIEFAAIHAAMIAhO6CADXAAAHAAMIAhO6CADXAAAsAAQKgSoAAgcACAg5IG0NAK4CAAcACAg5IG0NAK4CAAAA.Thonne:BAAALAADCgEIAQABLAAECgcIFQAdAHMcAA==.',Ti='Tinhay:BAAALAAECgcIDgAAAA==.',To='Tomikadzi:BAAALAAECgYIDgABLAAFFAQICQAFAFgaAA==.Tomïkadzi:BAACLAAFFIEJAAIFAAQIWBqADgBrAQAFAAQIWBqADgBrAQAsAAQKgSkAAgUACAgSIYIQAA4DAAUACAgSIYIQAA4DAAAA.Toshiro:BAAALAADCgYIBgAAAA==.',Tr='Trzuncek:BAAALAAECgYIEAAAAA==.',Tu='Tutancumon:BAAALAAECgcIBwAAAA==.Tuuletar:BAAALAAECggICAAAAA==.',Tw='Twíst:BAAALAAECgYIBwAAAA==.',Ty='Tya:BAAALAAECgUIBQAAAA==.',['Tø']='Tøxik:BAABLAAECoEYAAISAAgIyyVCAQBmAwASAAgIyyVCAQBmAwABLAAFFAIIBAACAAAAAA==.Tøxîk:BAAALAAFFAIIBAAAAA==.',Ur='Urthadur:BAABLAAECoEXAAILAAgIkSAKKACUAgALAAgIkSAKKACUAgABLAAFFAcIFQAOAPQaAA==.',Va='Vacaria:BAABLAAECoEYAAIBAAgIYByJFQCfAgABAAgIYByJFQCfAgAAAA==.Vassagô:BAAALAADCggICAAAAA==.',Vo='Voidshuffle:BAACLAAFFIEXAAIjAAcIuSBjAADTAgAjAAcIuSBjAADTAgAsAAQKgSMAAiMACAieJjIBAIUDACMACAieJjIBAIUDAAAA.Voidstar:BAAALAAECgIIAwAAAA==.Voodooms:BAABLAAECoEZAAIkAAcIjBXBEQCbAQAkAAcIjBXBEQCbAQAAAA==.',Vu='Vulgrìm:BAAALAADCggICAAAAA==.',Wa='Wassersager:BAAALAAECgQIBAABLAAFFAQIBwAPAHYeAA==.',Wh='Whiplasher:BAABLAAECoEcAAIbAAgIlB08EgBpAgAbAAgIlB08EgBpAgAAAA==.',Wi='Winstrol:BAAALAAECgUIBgABLAAFFAIIBgAfAC4cAA==.Winxi:BAABLAAECoEWAAIWAAYIDxY/RwCPAQAWAAYIDxY/RwCPAQAAAA==.Withinterest:BAAALAAECgUICwAAAA==.Wiztuin:BAAALAADCgQIBAAAAA==.',Wr='Wrath:BAAALAADCgYIBgABLAAFFAIIAgACAAAAAA==.',Wu='Wuguene:BAABLAAECoEVAAITAAcIbx/xDACCAgATAAcIbx/xDACCAgAAAA==.',Xe='Xelion:BAACLAAFFIEUAAMgAAcIeyKfAAAZAgAgAAUIfiafAAAZAgAlAAMI/BxIBAA9AQAsAAQKgSgAAyAACAiFJtMAAHoDACAACAhuJtMAAHoDACUAAQjfJkA5AHEAAAAA.Xelionsplit:BAACLAAFFIEHAAMgAAMI2BxwBwAWAQAgAAMI2BxwBwAWAQAlAAEIbxrpEgBPAAAsAAQKgR0AAyAACAh/JOoEACMDACAACAjtIeoEACMDACUAAwj2HZQrAPUAAAEsAAUUBwgUACAAeyIA.',Ya='Yasar:BAAALAADCgQIBAAAAA==.',Ye='Yearofspear:BAAALAAECggIDAABLAAFFAcIFgACAAAAAQ==.',Yu='Yunited:BAABLAAECoEcAAITAAcIvRqcFQArAgATAAcIvRqcFQArAgAAAA==.',Zi='Zirick:BAABLAAECoEjAAIOAAgI/hsXLQCRAgAOAAgI/hsXLQCRAgAAAA==.',Zu='Zugzugz:BAACLAAFFIEHAAQfAAMIDBKQDwD9AAAfAAMIDBKQDwD9AAAmAAIIlwwXBACNAAAHAAIIjxV1EQCHAAAsAAQKgRwABCYACAhEILIGAHQCAB8ACAiMHV4bALoCACYABwj+H7IGAHQCAAcAAghjIFRgAIkAAAAA.',['Zó']='Zóroark:BAABLAAECoEnAAIIAAgI7ws0VAC5AQAIAAgI7ws0VAC5AQAAAA==.',['Ða']='Ðanter:BAAALAAECgQIBAAAAA==.',['Ðö']='Ðööm:BAAALAAECgMIAwABLAAECgYIBwACAAAAAA==.',['Óx']='Óxxen:BAAALAADCgcIBwABLAAECggICAACAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end