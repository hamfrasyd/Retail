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
 local lookup = {'DemonHunter-Vengeance','Warrior-Arms','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Rogue-Outlaw','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','Druid-Feral','Druid-Guardian','Hunter-BeastMastery','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Shaman-Restoration','Mage-Arcane','Warrior-Protection','Priest-Shadow','Paladin-Retribution','Druid-Balance','Mage-Frost','DemonHunter-Havoc','Paladin-Protection','Evoker-Preservation','Warrior-Fury','Warlock-Affliction','Paladin-Holy','Priest-Holy','Druid-Restoration','DeathKnight-Blood','Shaman-Elemental','Evoker-Devastation','Mage-Fire','Monk-Brewmaster','DeathKnight-Unholy','Priest-Discipline','Hunter-Survival',}; local provider = {region='EU',realm='Frostwhisper',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaphexx:BAABLAAECoEYAAIBAAYIhxNtJgBAAQABAAYIhxNtJgBAAQAAAA==.',Ab='Abnormal:BAAALAADCggIFQAAAA==.',Ac='Acesulfam:BAAALAAECggIBgAAAA==.',Ae='Aeilhunt:BAAALAAECgYICQAAAA==.Aevyn:BAAALAAECggIDwAAAA==.',Ai='Airolite:BAAALAAECgQIBAAAAA==.',Ak='Akandu:BAAALAAECgYIBgAAAA==.',Al='Alaivia:BAAALAADCgMIAwAAAA==.Alakasama:BAAALAADCgYIBgAAAA==.',Am='Amaha:BAABLAAECoEWAAICAAYI9whKGgAeAQACAAYI9whKGgAeAQAAAA==.Ameth:BAAALAADCgQIBwABLAAFFAMIBwADAHQSAA==.Amethuil:BAAALAADCggICwABLAAFFAMIBwADAHQSAA==.',An='Anaesthesia:BAAALAAECgIIAgAAAA==.Anchev:BAAALAADCgYIBgAAAA==.Ancientthor:BAAALAAECggIEwAAAA==.Anomic:BAABLAAECoEbAAQEAAgIbBllDABEAgAEAAgIThhlDABEAgAFAAMIMhxGRwD+AAAGAAEICRAFGgA7AAAAAA==.Ansaaja:BAAALAAECggIDQAAAA==.',Ap='Apricus:BAABLAAECoEjAAIHAAgI9RBgOAC7AQAHAAgI9RBgOAC7AQAAAA==.',Ar='Arcanon:BAAALAAECgEIAQAAAA==.Armben:BAAALAAECgQIBgAAAA==.',As='Aseeton:BAAALAADCgcIFAAAAA==.Asunabestgrl:BAAALAAECgcIDQAAAA==.',At='Athral:BAAALAADCgUIBQAAAA==.Atroux:BAABLAAECoEcAAMIAAgIvRyhGgAEAgAIAAcIGxmhGgAEAgAJAAYIqRgHTwDKAQAAAA==.',Av='Avengingzero:BAAALAAECgMIAwAAAA==.',Ay='Ayami:BAABLAAECoEVAAMKAAYIYh1aEgABAgAKAAYISh1aEgABAgALAAMINhIKIgCXAAAAAA==.',Ba='Baconnaise:BAAALAADCggICAAAAA==.Badox:BAAALAAECgYIEAAAAA==.Baealdrian:BAAALAADCggIBAAAAA==.Baransu:BAAALAAECgIIAgAAAA==.Barefists:BAAALAAECggIAgAAAA==.Barnold:BAAALAADCggICAAAAA==.',Be='Beater:BAAALAAECgMIAwAAAA==.Bernadina:BAAALAAECgIIAwAAAA==.',Bi='Bighuntz:BAABLAAECoEhAAIMAAgIdx7jHACwAgAMAAgIdx7jHACwAgAAAA==.Birchie:BAAALAAECgcIBwAAAA==.',Bj='Bjarnedragen:BAAALAAECgEIAQAAAA==.',Bl='Blackslasher:BAAALAAECggIDgAAAA==.Blondjanoll:BAAALAAECgYIDwABLAAFFAEIAQANAAAAAA==.Bluedabedee:BAAALAADCggIEwAAAA==.',Bo='Boltz:BAAALAAECgcIEAAAAA==.Boopsboops:BAABLAAECoEVAAMOAAgIUx8YDAB4AgAOAAcIJSAYDAB4AgAPAAEI4g4GVQA7AAAAAA==.',Br='Brbcs:BAAALAAECgQICQAAAA==.Brotato:BAAALAAECggICAAAAA==.Bräw:BAAALAADCggICgABLAAECggIJwAQABMkAA==.Brödmannen:BAAALAADCgIIAgABLAAFFAUIDgARAAoVAA==.',Bu='Budbundy:BAAALAADCgYIBQAAAA==.Bull:BAABLAAECoEYAAISAAcIMh5FFQBUAgASAAcIMh5FFQBUAgAAAA==.Bullcheat:BAAALAAECgYIDAAAAA==.Bullvar:BAAALAADCggICAAAAA==.Bumblebèé:BAAALAADCggIEQAAAA==.',['Bé']='Bébbí:BAABLAAECoEpAAITAAgILB8FEQDRAgATAAgILB8FEQDRAgAAAA==.',Ca='Caprian:BAAALAAECgYIEwAAAA==.',Ce='Cevion:BAABLAAECoEpAAIUAAgIiCAWGAD3AgAUAAgIiCAWGAD3AgAAAA==.',Ch='Chiboisdead:BAAALAADCggICAAAAA==.Chiea:BAAALAAECgYICgAAAA==.Chronoa:BAABLAAECoEVAAIVAAYIqhL1RABkAQAVAAYIqhL1RABkAQAAAA==.',Ci='Cindy:BAAALAADCgYIBgAAAA==.',Cl='Cleavesteve:BAAALAAECggIEAAAAA==.',Co='Coldveins:BAAALAAECgEIAQAAAA==.Conaann:BAAALAAECggIEQAAAA==.Coolikeafool:BAAALAAECgIIAgAAAA==.Copper:BAAALAADCggICAAAAA==.Corpotaurus:BAAALAAECgQIBQABLAAECggIJgAWAMUiAA==.Cowbrisket:BAAALAAECgYIBgAAAA==.',Cr='Cranpyz:BAAALAAECgYICwAAAA==.Cryllez:BAAALAADCgEIAQAAAA==.',Cu='Cupcakke:BAAALAAECgUIBQAAAA==.',['Cá']='Cáryoxz:BAABLAAECoEnAAIXAAgIKxGbXQDcAQAXAAgIKxGbXQDcAQAAAA==.',Da='Daddyknight:BAAALAADCgcICAAAAA==.Dannus:BAAALAADCgYIBgAAAA==.',De='Deadhorny:BAAALAAECgYIEAAAAA==.Deathlight:BAAALAAECgEIAQAAAA==.Decilla:BAAALAAECggIDwAAAA==.Deefer:BAAALAADCgMIAwAAAA==.Deekaý:BAAALAAECgUIAgAAAA==.Deekoo:BAAALAADCggICAABLAAECggIJwAUAPUhAA==.Deltagoodrem:BAAALAAECgIIAgAAAA==.Demonclave:BAAALAADCgUIBQAAAA==.Derach:BAAALAADCggICAAAAA==.Desaanix:BAAALAADCggICAAAAA==.Deviil:BAABLAAECoEVAAIXAAcI+xjfTgADAgAXAAcI+xjfTgADAgAAAA==.Devour:BAAALAAECgYIDAAAAA==.',Dg='Dgb:BAAALAAECgYIBgAAAA==.',Dh='Dhturka:BAAALAAECgYIBwAAAA==.',Di='Didres:BAAALAADCgYIBwAAAA==.Digpics:BAAALAAECgQIBAAAAA==.Diklorvos:BAAALAADCgcIBwAAAA==.Dilweed:BAAALAAECggICAAAAA==.Dinglebaer:BAAALAAECgYIBwABLAAECggIGAAPAKETAA==.Dispare:BAAALAAECgYIEwAAAA==.',Do='Dolfildor:BAABLAAECoEWAAIYAAYIERnhIACsAQAYAAYIERnhIACsAQAAAA==.Dondoo:BAAALAAECgIIAgAAAA==.Doodoomies:BAABLAAECoEoAAIRAAgIJB8FGgDWAgARAAgIJB8FGgDWAgAAAA==.Dorror:BAAALAAECgMIBwAAAA==.Dotctor:BAAALAAECgcIEQAAAA==.',Dr='Draald:BAABLAAECoEUAAISAAYI7iCcGAA0AgASAAYI7iCcGAA0AgAAAA==.Drakela:BAABLAAECoEYAAIZAAYIaB8qDQAnAgAZAAYIaB8qDQAnAgABLAAECgcIHgAQAHMjAA==.Drakoulaki:BAAALAADCggICAABLAAECggIIwAaACoKAA==.Drakén:BAAALAAECggICAAAAA==.Drimen:BAABLAAECoEoAAIaAAgIVyWzAgB3AwAaAAgIVyWzAgB3AwAAAA==.Drunkenmasta:BAAALAADCggIFQAAAA==.',Du='Dumbasshuntz:BAABLAAECoEcAAIHAAgIlRRRNADOAQAHAAgIlRRRNADOAQAAAA==.',Dw='Dwarfkingg:BAAALAAECgIIAgAAAA==.',['Dó']='Dóris:BAAALAAECgYIDwAAAA==.',['Dö']='Dödsmåns:BAAALAAECgcIEAAAAA==.',['Dø']='Dødballe:BAAALAAECgcIBwAAAA==.',Ed='Edkemper:BAAALAAECgEIAQABLAAECgcIGQAPAGYeAA==.',Ee='Eek:BAAALAAECggICgAAAA==.',Ef='Efedrea:BAAALAAECgMIBQAAAA==.',Eg='Egotastic:BAACLAAFFIEHAAIJAAIIBxRyJwCcAAAJAAIIBxRyJwCcAAAsAAQKgSgAAgkACAiPH0MVAOgCAAkACAiPH0MVAOgCAAAA.',El='Elighost:BAAALAAECgMIBQABLAAECgYIBgANAAAAAA==.',Em='Emorager:BAABLAAECoEjAAIYAAgITB4+CgCkAgAYAAgITB4+CgCkAgAAAA==.',En='Enforcerer:BAABLAAECoEZAAQJAAgIERQERwDnAQAJAAgIERQERwDnAQAIAAYImQq3QABEAQAbAAEI4gWYPgAuAAAAAA==.Envy:BAABLAAECoEbAAMcAAgIYxUaGwAEAgAcAAgIYxUaGwAEAgAUAAQI3Rfk2AAHAQAAAA==.',Ep='Epicmeal:BAAALAADCgYIBgAAAA==.',Er='Erik:BAAALAAECgYIDAAAAA==.Erue:BAAALAAECgYIBgAAAA==.',Es='Espen:BAAALAAECgUIBQAAAA==.',Ex='Exhusband:BAAALAADCgUIBQAAAA==.',Fa='Faceblock:BAAALAAECggIAQAAAA==.Faizan:BAABLAAECoEYAAIcAAgIzR0/CwCiAgAcAAgIzR0/CwCiAgAAAA==.Falcore:BAAALAADCggICAAAAA==.Falsudk:BAAALAAECggICAAAAA==.',Fd='Fdszirius:BAABLAAECoEnAAISAAgIjxaLJADTAQASAAgIjxaLJADTAQAAAA==.',Fe='Felangel:BAABLAAECoEYAAMBAAgIYRI9GwCoAQABAAgIYRI9GwCoAQAXAAEIZQDuJgEDAAAAAA==.Felene:BAABLAAECoEVAAIUAAYIcQsUugBGAQAUAAYIcQsUugBGAQAAAA==.Felevalin:BAAALAAECgYIBgABLAAECgYIFgAPAEgiAA==.Felissa:BAABLAAECoEWAAIXAAcIHhQfXQDdAQAXAAcIHhQfXQDdAQAAAA==.Felocity:BAAALAADCgUIBQAAAA==.Femmern:BAAALAADCggICgAAAA==.Fendal:BAAALAADCgMIAwAAAA==.Fendalla:BAAALAADCgQIBwABLAAFFAIIBQAdAH0YAA==.Fera:BAABLAAECoEnAAIUAAgI9SE9GwDnAgAUAAgI9SE9GwDnAgAAAA==.Feraldruíd:BAABLAAECoEUAAQVAAYI8Q8+XAD9AAAVAAUISg4+XAD9AAAeAAQIyRQ6cgD2AAAKAAEI0w9FPQA5AAAAAA==.Ferocious:BAAALAAECgYICwABLAAECggIJwAUAPUhAA==.Feylin:BAAALAADCgQIBAAAAA==.',Fi='Fiddlesworth:BAABLAAECoEYAAIfAAcIzBYIFQDDAQAfAAcIzBYIFQDDAQAAAA==.Filo:BAABLAAECoEdAAIeAAgIliXBAQBeAwAeAAgIliXBAQBeAwAAAA==.Firebrand:BAABLAAECoEmAAMXAAgI0yH6FAD+AgAXAAgI0yH6FAD+AgABAAcIcBIaJQBKAQAAAA==.',Fk='Fks:BAAALAAECggICAAAAA==.',Fl='Flaggermus:BAACLAAFFIEGAAIgAAMIohl4DwDwAAAgAAMIohl4DwDwAAAsAAQKgSAAAyAACAhIIs4LAB4DACAACAhIIs4LAB4DABAAAwiDCDzqAGQAAAAA.',Fr='Frackson:BAABLAAECoEWAAIMAAgIYyA9EwDrAgAMAAgIYyA9EwDrAgAAAA==.Freak:BAAALAADCggIDwABLAAECgYIHAAQAA4iAA==.Freakzie:BAABLAAECoEcAAIQAAYIDiLxLQAwAgAQAAYIDiLxLQAwAgAAAA==.Fregar:BAAALAADCgIIAgAAAA==.Frickintusks:BAAALAADCggICAABLAAECgcIDQANAAAAAA==.Frostching:BAABLAAECoEbAAIRAAgICBgEPwAqAgARAAgICBgEPwAqAgAAAA==.Frëyä:BAAALAAECgYIDAAAAA==.',Fu='Futhark:BAAALAAECgcIEAAAAA==.',Ga='Gagic:BAAALAADCgYICgAAAA==.Galder:BAAALAAECgYICQAAAA==.Ganeshá:BAAALAAECgMIAwAAAA==.Ganmcdaddy:BAAALAADCgYIBgAAAA==.Garelt:BAAALAADCggICAAAAA==.Gathma:BAAALAAECgcIBwAAAA==.',Ge='Gem:BAAALAAECggICgAAAA==.',Gi='Gilal:BAAALAADCgcIBwAAAA==.',Gl='Gltyasfk:BAAALAAECgQIBAAAAA==.',Gn='Gnd:BAAALAAECggIDQAAAA==.Gnetp:BAABLAAECoEVAAIUAAcIHB61OgBcAgAUAAcIHB61OgBcAgAAAA==.',Go='Gotrek:BAABLAAECoEXAAMaAAgIpRlRLQBKAgAaAAgIxhdRLQBKAgACAAYIDxjoDwCvAQABLAAFFAIIBgAHAMAhAA==.',Gr='Gralf:BAAALAADCggICAAAAA==.Groge:BAABLAAECoEdAAITAAgILBddIwA3AgATAAgILBddIwA3AgAAAA==.',Gu='Guts:BAAALAAECgcIDwAAAA==.',Ha='Hanalla:BAAALAAECgYIBgAAAA==.Haqua:BAAALAADCggICAAAAA==.Haya:BAAALAAECgQIBAAAAA==.',He='Heckraiser:BAAALAADCgYIBgAAAA==.Heisman:BAAALAADCgIIAgABLAADCgYIBgANAAAAAA==.Heistrapp:BAAALAADCgYIBgAAAA==.Heligagudrun:BAAALAAECgUIBwAAAA==.',Hi='Hilyna:BAAALAADCggIFQABLAAFFAMIBwADAHQSAA==.Hippoo:BAAALAAECgYIDAAAAA==.',Hj='Hjørdiss:BAABLAAECoEmAAQbAAgItRtOBQBxAgAbAAcIbR1OBQBxAgAIAAcIChJZJQDBAQAJAAUI9xCkigAfAQAAAA==.',Ho='Holli:BAAALAAECggIDwABLAAFFAIIBQAdAH0YAA==.Holygoat:BAAALAAECgYIDAAAAA==.Hork:BAABLAAECoEgAAIDAAgIuRvRUgAcAgADAAgIuRvRUgAcAgAAAA==.Hornette:BAAALAADCggIGAABLAAECgcIGAASADIeAA==.Houdin:BAAALAADCggICAAAAA==.',Hu='Hunterbadger:BAAALAAECgEIAQAAAA==.',['Hà']='Hàmstern:BAACLAAFFIEOAAIfAAUIfRIYAwCJAQAfAAUIfRIYAwCJAQAsAAQKgS4AAh8ACAgtITAGAOQCAB8ACAgtITAGAOQCAAAA.',['Hâ']='Hâmstern:BAAALAAECgEIAQAAAA==.',['Hä']='Häjy:BAAALAADCgcIBwAAAA==.Härkäpapu:BAABLAAECoEmAAMQAAgIwhZjMwAbAgAQAAgIwhZjMwAbAgAgAAcIGRDNSQCqAQAAAA==.',Ig='Ig:BAAALAAECgYICwAAAA==.Igumeemi:BAAALAAECgYICQAAAA==.',Ih='Ihananirstas:BAACLAAFFIEGAAIQAAII/xDjLgB6AAAQAAII/xDjLgB6AAAsAAQKgSYAAhAACAhtGuAoAEUCABAACAhtGuAoAEUCAAAA.',Ik='Ikbenmarc:BAAALAADCgEIAQAAAA==.',In='Iniqa:BAAALAAECgIIAgAAAA==.Instability:BAAALAAECggIDwAAAA==.',Ip='Ipokestuff:BAABLAAECoEoAAISAAgIyR71DAC0AgASAAgIyR71DAC0AgAAAA==.',Ir='Ira:BAABLAAECoEkAAIfAAgIzRmyDgAoAgAfAAgIzRmyDgAoAgAAAA==.Irlin:BAAALAADCggICAAAAA==.',Is='Iskaldpmax:BAAALAAECggIEwAAAA==.Isopaahto:BAAALAAECgcIBwAAAA==.',It='Iterax:BAAALAAECgQICgAAAA==.',Iv='Ivanja:BAAALAAECgEIAQAAAA==.',Ja='Jaegern:BAAALAADCgEIAQAAAA==.Jamikettu:BAABLAAECoEfAAIGAAgIkxldBAB2AgAGAAgIkxldBAB2AgAAAA==.',Je='Jeef:BAAALAADCgcIBwAAAA==.Jel:BAAALAAECggICwABLAAFFAYIEgAJAM0cAA==.Jelo:BAACLAAFFIESAAIJAAYIzRyLAwBJAgAJAAYIzRyLAwBJAgAsAAQKgSUAAwkACAjVJXYHAEsDAAkACAjVJXYHAEsDAAgABAgxILVCADwBAAAA.Jemeni:BAAALAADCgYIBgAAAA==.',Jo='Joep:BAABLAAECoEUAAMIAAYI1gyOOgBeAQAIAAYIUwyOOgBeAQAJAAMI1An7sACaAAAAAA==.Jompatorman:BAAALAADCgcIDQAAAA==.Joél:BAABLAAECoEdAAMgAAgIthieJwBMAgAgAAgIthieJwBMAgAQAAUIJRZckgAVAQAAAA==.',Ju='Juken:BAAALAADCgQIBAAAAA==.Justmeld:BAAALAAECgUICQAAAA==.Justtryme:BAAALAAECgYIDgAAAA==.Juuei:BAAALAADCgYIBgAAAA==.',Ka='Kadabri:BAAALAAECgMIAwAAAA==.Kafolul:BAACLAAFFIEIAAMcAAII/QuzFACRAAAcAAII/QuzFACRAAAUAAIIWQcFNwCNAAAsAAQKgSwABBwACAgUFqsWACkCABwACAgUFqsWACkCABQACAgeFpVaAAICABgAAQgcCvBeACcAAAAA.Kaidor:BAABLAAECoEYAAMhAAcINhbeIwDWAQAhAAcINhbeIwDWAQAZAAEIQwCrOwADAAABLAADCgcIDQANAAAAAA==.Kaikanori:BAAALAAECgIIAQAAAA==.Kalcadal:BAACLAAFFIEHAAIaAAMIwxE/EAD2AAAaAAMIwxE/EAD2AAAsAAQKgSoAAhoACAj6H38UAOkCABoACAj6H38UAOkCAAAA.Kassei:BAAALAADCgcIBwAAAA==.Kaura:BAABLAAECoEoAAIMAAgIJSF/GgC/AgAMAAgIJSF/GgC/AgAAAA==.',Ke='Kepabbi:BAAALAAECgcIBwAAAA==.Kessn:BAAALAADCgYICAAAAA==.Kevlilc:BAAALAAECggICgAAAA==.',Ki='Kibablood:BAAALAADCgcIBwAAAA==.Kisuucco:BAAALAAECgcIBwAAAA==.Kives:BAAALAAECgcIDQABLAAECggIJgABANAgAA==.',Kl='Kladdah:BAAALAAECggIAgABLAAFFAUICwAIAIwdAA==.Kladdiz:BAACLAAFFIELAAMIAAUIjB0tAQAyAQAIAAMIbh0tAQAyAQAJAAIIuR0LHQDBAAAsAAQKgS4AAwgACAhiJo4AAIMDAAgACAhiJo4AAIMDAAkAAggFEmm5AH0AAAAA.',Kn='Kneli:BAAALAADCggICAAAAA==.',Ko='Kodie:BAAALAADCggICAAAAA==.Korvvex:BAABLAAECoEoAAIVAAgI7R6mFACUAgAVAAgI7R6mFACUAgAAAA==.',Ku='Kullivelho:BAABLAAECoEmAAIRAAgIChbmPwAmAgARAAgIChbmPwAmAgAAAA==.Kulutusmaito:BAAALAADCggIEAAAAA==.Kumi:BAAALAAECgUICAAAAA==.Kuskokvint:BAAALAAECgcIDAAAAA==.',Ky='Kyinth:BAAALAAECgYICQABLAAECgYIFgAPAEgiAA==.Kylar:BAABLAAECoEhAAIXAAgILBtDKQCPAgAXAAgILBtDKQCPAgAAAA==.',['Ká']='Káminari:BAAALAAECgcIDwAAAA==.',La='Laawry:BAAALAAECgUIBQAAAA==.Laishetkhez:BAAALAAECggICAAAAA==.Larslilholt:BAAALAADCgIIAQAAAA==.Latvalaho:BAAALAADCgIIAgAAAA==.',Le='Ledeux:BAAALAAECgYIBgABLAAECggIJAARAAEjAA==.Leetopissa:BAABLAAECoEUAAIOAAgIJwuCIgBZAQAOAAgIJwuCIgBZAQAAAA==.Legbone:BAAALAAECgYIBQAAAA==.Legowish:BAABLAAECoEcAAIUAAgI1hxlMQB+AgAUAAgI1hxlMQB+AgAAAA==.Lehuit:BAABLAAECoEkAAIRAAgIASPWEAAMAwARAAgIASPWEAAMAwAAAA==.Leoenjoyer:BAAALAADCgYIBgAAAA==.',Li='Libster:BAABLAAECoEVAAIMAAgIAhaKPgAaAgAMAAgIAhaKPgAaAgAAAA==.Lindxd:BAAALAAECggIDwAAAA==.Lirac:BAAALAADCggICAAAAA==.Liraell:BAAALAAECgUIBwAAAA==.Liraith:BAAALAADCgYIBgABLAAECggICgANAAAAAA==.',Ll='Llaneria:BAAALAAECgcIDgAAAA==.Lliira:BAAALAADCgcICgAAAA==.',Lo='Loganglaives:BAAALAADCgcIAgAAAA==.Lohilo:BAAALAAECgQIBAAAAA==.Lohis:BAAALAAECgcIBwAAAA==.Lookz:BAABLAAFFIEGAAIDAAIIQR0WJgCvAAADAAIIQR0WJgCvAAAAAA==.Lothe:BAAALAADCggICAAAAA==.Louis:BAAALAADCgEIAQAAAA==.Lovefist:BAAALAADCgYIBgAAAA==.Lowping:BAAALAADCggICAAAAA==.',Lu='Lunah:BAAALAADCgUIBQABLAAFFAIIBQAdAH0YAA==.',Ly='Lydriel:BAAALAADCgIIAgAAAA==.',Ma='Maffers:BAABLAAECoEYAAMVAAcIEyC3GQBiAgAVAAcIEyC3GQBiAgAeAAQIPRapcQD3AAAAAA==.Maffershunt:BAAALAADCggICAAAAA==.Mafférs:BAAALAADCgUIBQAAAA==.Maivi:BAAALAADCgUIBgABLAAECggICgANAAAAAA==.Maksamakkara:BAAALAADCgcIDAAAAA==.Malefîcent:BAAALAAECgYIAwAAAA==.Mangoiröven:BAAALAAECgUICQABLAAFFAEIAQANAAAAAA==.Mangoprinse:BAAALAAECgUICgAAAA==.',Mb='Mborelia:BAAALAADCgQIBAAAAA==.',Me='Meadbrew:BAAALAADCgcIDAAAAA==.Mega:BAAALAAECgYIBgAAAA==.Mesterjuan:BAAALAADCgYIBgAAAA==.Metalslug:BAABLAAECoEUAAIaAAYIzQxoegBAAQAaAAYIzQxoegBAAQAAAA==.',Mf='Mfahrenheit:BAAALAADCgIIAgAAAA==.',Mg='Mgn:BAAALAAECggIEgAAAA==.',Mi='Miagi:BAAALAADCgcIBwAAAA==.Mightyteus:BAAALAAECggIEgAAAA==.Miimi:BAABLAAECoEhAAIWAAgIXROrHAAJAgAWAAgIXROrHAAJAgAAAA==.Mikah:BAABLAAECoEeAAIQAAcIcyOxFACuAgAQAAcIcyOxFACuAgAAAA==.Millae:BAAALAAECgYIBgAAAA==.Milmadia:BAAALAADCgUIBgAAAA==.Mindflay:BAAALAADCggICAAAAA==.Minsela:BAAALAAECgQIBQAAAA==.Miralibaen:BAAALAADCggIDgAAAA==.Missasstress:BAABLAAECoElAAIMAAgIGhgFSQD5AQAMAAgIGhgFSQD5AQAAAA==.',Mo='Moccamaster:BAAALAAECgMIBQAAAA==.Mocha:BAABLAAECoEbAAIiAAgIKRCjBQAEAgAiAAgIKRCjBQAEAgAAAA==.Mograine:BAAALAADCgcIBwAAAA==.Moh:BAAALAADCggIHAAAAA==.Moizt:BAAALAAECgYICwAAAA==.Moltitude:BAAALAAECgQIBgAAAA==.Monka:BAAALAADCgIIAgAAAA==.Monogamija:BAAALAADCgcIBwAAAA==.Moontu:BAABLAAECoEYAAIaAAYINB8XNAAqAgAaAAYINB8XNAAqAgAAAA==.Morso:BAAALAADCggICAAAAA==.Motueka:BAAALAAECgcIBwAAAA==.',Mu='Muimoridin:BAAALAAECgYIDgAAAA==.Munkeren:BAABLAAECoEYAAMPAAgIoRNNHwDQAQAPAAgIkQ9NHwDQAQAjAAYIUxPdIABPAQAAAA==.',My='Mykrä:BAAALAADCggIEAAAAA==.Myrahk:BAAALAADCggIDAAAAA==.',['Mí']='Mínzy:BAAALAAECggIBwAAAA==.',['Mö']='Mölli:BAABLAAECoEkAAIJAAgIECOsCgAyAwAJAAgIECOsCgAyAwAAAA==.',Na='Nahasiel:BAAALAADCggIGAAAAA==.Nanao:BAAALAAECgYIBgAAAA==.Nangus:BAABLAAECoEUAAMQAAcIJwuAmwACAQAQAAcIJwuAmwACAQAgAAMIsAJwnQBTAAAAAA==.Naughtynurse:BAAALAAECgEIAQAAAA==.',Ne='Neethor:BAABLAAECoEcAAIkAAgI4R7rCQCcAgAkAAgI4R7rCQCcAgAAAA==.Neitor:BAACLAAFFIEGAAIHAAIIoguiHwB9AAAHAAIIoguiHwB9AAAsAAQKgRQAAgcABggEG6cyANcBAAcABggEG6cyANcBAAAA.Nemio:BAAALAADCggICAAAAA==.Nesthor:BAAALAAECgIIAgABLAAFFAIIBgAHAKILAA==.',Nh='Nhil:BAABLAAECoEkAAMIAAgItgy4LwCLAQAIAAcIzQq4LwCLAQAJAAMIPw1WtQCLAAAAAA==.',Ni='Nienkê:BAAALAADCgcIEAAAAA==.Ninjagaiden:BAAALAAECgcIBwAAAA==.',No='Nocturnal:BAAALAAECgYIEgAAAA==.Nofco:BAABLAAECoEeAAIXAAgIBSL/IQCzAgAXAAgIBSL/IQCzAgAAAA==.Noobtube:BAAALAADCgUIBQAAAA==.Nordbol:BAAALAAECggICQAAAA==.Novelle:BAAALAADCgcIEAAAAA==.Noxxslaya:BAAALAAECgYIBgAAAA==.',Nu='Nugah:BAAALAADCggICAAAAA==.',Ny='Nyella:BAAALAADCggICAAAAA==.Nyssara:BAAALAAECgYIDwAAAA==.',['Nì']='Nìaz:BAAALAAECgYIEgAAAA==.',Oh='Ohrapirtelö:BAAALAADCgcIBwAAAA==.',Oi='Oiskipoiski:BAAALAAECgUIBQAAAA==.',Oj='Ojas:BAABLAAECoEeAAIRAAgIWhaEPwAoAgARAAgIWhaEPwAoAgAAAA==.',On='Onixia:BAACLAAFFIEFAAIdAAIIfRiaGgCgAAAdAAIIfRiaGgCgAAAsAAQKgSoAAh0ACAjcIZMIABUDAB0ACAjcIZMIABUDAAAA.Ontiro:BAAALAADCggICAABLAAECgYIFgAPAEgiAA==.',Oo='Oofie:BAAALAADCggICQABLAAFFAIIBgAdAFwGAA==.',Pa='Paddydk:BAAALAAECgEIAQABLAAFFAIIBgAHAKILAA==.Paleleo:BAAALAADCgcICQAAAA==.Pansersmølf:BAAALAAECgQIBAABLAAECggIJgADAIYlAA==.Parx:BAAALAAECgcIDgAAAA==.Pattepala:BAABLAAECoEVAAMUAAgIEyNMDAA7AwAUAAgIsiJMDAA7AwAYAAUIvBhwKQBqAQAAAA==.Pawmorph:BAAALAAECgYIBgAAAA==.Pawnpusher:BAAALAAECgQIBQAAAA==.Pawpatine:BAAALAAECgUICQAAAA==.Pawweaver:BAABLAAECoEeAAIOAAgIVB3FCgCRAgAOAAgIVB3FCgCRAgAAAA==.',Pe='Pekonisoturi:BAAALAAECgMIBAAAAA==.Pencil:BAAALAAFFAIIBAAAAA==.Pestoration:BAAALAAECgcIBwAAAA==.',Ph='Philwap:BAAALAADCgIIAgABLAAECgEIAQANAAAAAA==.',Pi='Pieters:BAAALAAECgYIBgAAAA==.Pii:BAABLAAECoEcAAIdAAgI/SBnDQDmAgAdAAgI/SBnDQDmAgAAAA==.Pikkuhukka:BAABLAAECoEbAAIFAAgIkhggFwBKAgAFAAgIkhggFwBKAgAAAA==.Pippipil:BAAALAAECgYICwAAAA==.Pippirull:BAAALAAECgIIBAAAAA==.Pirikaisa:BAAALAAECgYICgABLAAECggIIwAMANseAA==.Pirilissu:BAAALAAECgMIAwABLAAECggIIwAMANseAA==.Piripipsa:BAABLAAECoEjAAMMAAgI2x67HQCrAgAMAAgIuxy7HQCrAgAHAAgIpRRwLwDpAQAAAA==.Piritapsa:BAAALAADCgcICwABLAAECggIIwAMANseAA==.Pirituula:BAAALAAECgcIEQABLAAECggIIwAMANseAA==.',Pj='Pjaske:BAAALAAECgcIDwAAAA==.',Po='Pollylock:BAAALAAECgYIBQAAAA==.Possumunkki:BAAALAAECgcIEwAAAA==.Poxkajka:BAAALAAFFAEIAQAAAA==.',Pr='Prognosis:BAAALAAECgEIAQAAAA==.',Ps='Psyblade:BAAALAAECgYIDAAAAA==.Psykomayn:BAAALAADCgcIBwAAAA==.',['Pö']='Pörssisähkö:BAAALAAECgcIEAAAAA==.',Qo='Qonkeygong:BAABLAAECoEhAAIfAAgIZhlnDABVAgAfAAgIZhlnDABVAgAAAA==.',Qu='Quicknut:BAAALAADCgYIBgAAAA==.',Ra='Rauk:BAABLAAFFIEHAAIDAAIIRRqhLgCgAAADAAIIRRqhLgCgAAAAAA==.',Re='Redassain:BAAALAADCgYIBgAAAA==.Reketråla:BAAALAADCgYIBgAAAA==.Reloca:BAAALAAECgIIAgAAAA==.Rendiros:BAABLAAECoElAAILAAgI3iK8AQA1AwALAAgI3iK8AQA1AwAAAA==.Rethkerianna:BAAALAADCgMIAwABLAAECgYIEwANAAAAAA==.',Rh='Rhalaz:BAAALAADCggIKwAAAA==.Rhinoo:BAAALAAECgEIAQAAAA==.',Ro='Roarikzo:BAAALAADCgUIBQAAAA==.Robsmash:BAABLAAECoEdAAIaAAcIUx+1IACVAgAaAAcIUx+1IACVAgAAAA==.Rocknroll:BAAALAAECgYICAAAAA==.Roctar:BAAALAADCggIAwAAAA==.Roxinrajh:BAAALAAECgYIBgAAAA==.',Ru='Ruby:BAAALAAECggIDwAAAA==.Rundagar:BAAALAAECgYIBgAAAA==.',['Rö']='Rödamördarn:BAAALAADCgYIBgAAAA==.',Sa='Saela:BAAALAAECgYIBgABLAAECggIDwANAAAAAA==.Samdi:BAAALAAECgQIBAAAAA==.Satsudd:BAABLAAECoEhAAMJAAgIiRSwNwAmAgAJAAgIiRSwNwAmAgAbAAYIoQq3FQBFAQAAAA==.Sauedum:BAAALAAECgYIEgAAAA==.Savia:BAABLAAECoEgAAMDAAgIAAthjACjAQADAAgIAAthjACjAQAkAAYIgwOjNQD5AAAAAA==.Saxi:BAACLAAFFIEIAAIeAAMIZxQOCwDjAAAeAAMIZxQOCwDjAAAsAAQKgR8AAx4ACAgoHaAZAGYCAB4ACAgoHaAZAGYCABUABghyCq9ZAAoBAAAA.',Se='Senyn:BAAALAAECgYICwABLAAFFAMIBwADAHQSAA==.',Sh='Shakenator:BAAALAAECgYIBgAAAA==.Shakez:BAACLAAFFIEQAAIMAAYIexZMBADSAQAMAAYIexZMBADSAQAsAAQKgSwAAgwACAgUJucDAGEDAAwACAgUJucDAGEDAAAA.Shamuss:BAAALAAECgUICgAAAA==.Shapeshiftz:BAAALAAECgcIDwAAAA==.Sharapriest:BAAALAAFFAIIBAAAAA==.Sharawalker:BAACLAAFFIEHAAMMAAMICQneMAB/AAAMAAIItQzeMAB/AAAHAAIICAQcJwBhAAAsAAQKgRcAAwcACAiCHuUWAJMCAAcACAgTG+UWAJMCAAwACAiaHJ8oAHICAAAA.Sharawalkers:BAAALAAFFAIIAgAAAA==.Sheezwy:BAAALAAECgUIBgABLAAECgYIEgANAAAAAA==.Sheivaaja:BAABLAAECoElAAIDAAgIBh0HRABFAgADAAgIBh0HRABFAgAAAA==.Shirel:BAAALAAECggICAAAAA==.Shooker:BAAALAADCggIHQAAAA==.Shàbbìs:BAAALAADCgcIBwAAAA==.Shíela:BAAALAADCgUIBgABLAAECgcIGAASADIeAA==.',Si='Sinko:BAAALAAECgYIBgAAAA==.Siseras:BAAALAAECgYIBgABLAAECgcIDQANAAAAAA==.Sistersage:BAAALAADCggICAAAAA==.',Sk='Skibahm:BAAALAAECgYIBwABLAAECggIJAARAAEjAA==.Skravkransen:BAAALAAECggICgAAAA==.Skullsplitt:BAAALAAECgcIEAAAAA==.',Sl='Slinger:BAAALAADCgYIBgAAAA==.',So='Soeyy:BAABLAAECoEfAAMgAAgIyxHuNgD6AQAgAAgIyxHuNgD6AQAQAAMIhQMP8QBXAAAAAA==.Sofor:BAAALAAECgEIAQAAAA==.Sofô:BAAALAAFFAEIAQAAAA==.Soyun:BAAALAADCgMIAwAAAA==.',Sp='Spegodin:BAABLAAECoEUAAIcAAcIuwziMwBeAQAcAAcIuwziMwBeAQAAAA==.Sprutpump:BAAALAAECgcIBwAAAA==.',St='Stargeezer:BAAALAAECgUICAAAAA==.Starvild:BAAALAAECgMIAwAAAA==.Stepbro:BAAALAAECgYIBgAAAA==.Stickyvicky:BAAALAADCgcICAABLAAFFAIIBgAHAKILAA==.Stúbborn:BAAALAADCggICAAAAA==.',Su='Sushihukka:BAAALAAECgcIBwAAAA==.',Sv='Svettlana:BAAALAAECggICAABLAAECgYIDQANAAAAAA==.Svinfejja:BAACLAAFFIEKAAIeAAMIGBwOCQACAQAeAAMIGBwOCQACAQAsAAQKgSUAAx4ACAgTJfMCAEkDAB4ACAgTJfMCAEkDABUABQheDHJdAPcAAAAA.',Sy='Syanna:BAABLAAECoEcAAMIAAgIPSDVCAC5AgAIAAgIPSDVCAC5AgAJAAMIARAzqwCvAAAAAA==.Syrah:BAAALAAECgQIBAAAAA==.',Ta='Taankie:BAAALAAECgMIAwAAAA==.Tallgrogu:BAAALAADCgcIDQAAAA==.Tamac:BAAALAAECgYIBgAAAA==.Tameera:BAAALAAECgYICQAAAA==.Tamonten:BAABLAAECoEcAAIaAAgIlw+FSQDUAQAaAAgIlw+FSQDUAQAAAA==.Tamryssa:BAAALAAECggIDgAAAA==.Tamtheone:BAAALAADCgYIBwAAAA==.Tamyo:BAAALAAECgQIBAAAAA==.Tardi:BAABLAAECoEXAAIXAAgI9yGuEwAGAwAXAAgI9yGuEwAGAwABLAAECggIFQAOAFMfAA==.',Te='Tear:BAAALAAECgIIAwAAAA==.Teeus:BAAALAADCggICAAAAA==.Ten:BAAALAADCggIEAAAAA==.',Th='Thaelstrasz:BAABLAAECoEcAAMZAAgI8RbhDAAtAgAZAAgI8RbhDAAtAgAhAAEIrAryVwA+AAAAAA==.Thaeras:BAAALAAECgEIAQAAAA==.Thehandyman:BAAALAADCgUIBQAAAA==.Theuseless:BAAALAADCggIEAAAAA==.Thémistocles:BAAALAAECgcICAAAAA==.',Ti='Tides:BAACLAAFFIEOAAIQAAUI4CFPAgD1AQAQAAUI4CFPAgD1AQAsAAQKgS4AAhAACAhQI2wIAAoDABAACAhQI2wIAAoDAAAA.',To='Tohubohu:BAAALAADCgUIBQAAAA==.Toolbar:BAAALAADCgcIBwAAAA==.Torham:BAAALAAECgcIDQAAAA==.Torlanz:BAAALAAECgIIAwAAAA==.Tormenting:BAABLAAECoEYAAMEAAgIlxKcEgDmAQAEAAgIVxKcEgDmAQAGAAYIOxLrDABvAQAAAA==.Torosanto:BAAALAADCgUIBQAAAA==.Totempåle:BAAALAAECgQIBwAAAA==.',Tr='Trash:BAAALAAECgYICAAAAA==.Treicy:BAAALAADCggICAABLAAFFAIIBgAJADUSAA==.Trelli:BAABLAAECoEjAAIaAAgIKgpXaAB1AQAaAAgIKgpXaAB1AQAAAA==.Troz:BAABLAAECoEXAAIMAAgIbiEIFwDUAgAMAAgIbiEIFwDUAgAAAA==.Truk:BAAALAADCggICAAAAA==.',Ts='Tsuneo:BAAALAAECgYIBgAAAA==.',Tu='Tuhtinatar:BAAALAAECggIDwAAAA==.Tulloa:BAAALAAECgcIEgAAAA==.Turgön:BAABLAAECoEnAAIQAAgIEyRABQArAwAQAAgIEyRABQArAwAAAA==.',Tw='Twopi:BAAALAADCgUIBQABLAAECggIIwAhADMjAA==.',Tz='Tzameh:BAAALAAECggICAAAAA==.',['Tä']='Tärätänkö:BAABLAAECoEpAAMdAAgI+x29EgC1AgAdAAgIfh29EgC1AgAlAAcICRpQBwAWAgAAAA==.',['Té']='Téuslols:BAAALAADCggIBQAAAA==.',Ul='Ultear:BAAALAAECgYIDgAAAA==.',Um='Umduhrnahr:BAAALAAECgEIAQAAAA==.',Ur='Ursula:BAAALAAECgYIDgABLAAECgcIHgAQAHMjAA==.',Ut='Utop:BAAALAAECggICAAAAA==.',Va='Vadårårå:BAAALAAECgYIDAAAAA==.Vajdh:BAAALAAECgUIBQABLAAFFAYIEQARAGIdAA==.Valhalla:BAAALAAECgYIDgAAAA==.Vandal:BAAALAAECggICAAAAA==.Vanilje:BAABLAAECoEzAAIWAAgIpRreEAB4AgAWAAgIpRreEAB4AgAAAA==.Varuz:BAAALAAECgUIBwAAAA==.',Ve='Velanthia:BAAALAADCggIBAAAAA==.Velhomo:BAAALAADCggIEAAAAA==.Velithra:BAAALAAECgYIBgAAAA==.Verdugo:BAAALAAECgYICQAAAA==.',Vi='Vildasst:BAAALAADCggICAABLAAECgMIAwANAAAAAA==.Vildast:BAAALAADCgEIAQABLAAECgMIAwANAAAAAA==.Vixoniac:BAAALAADCgMIAwAAAA==.',Vl='Vliegendekoe:BAAALAADCggIEAAAAA==.',Vo='Voidbunny:BAAALAADCgcIDAAAAA==.Voiddaddie:BAAALAADCggIFwABLAAECgYIEwANAAAAAA==.',Vr='Vroma:BAAALAADCgIIAgABLAAECggIIwAaACoKAA==.Vruk:BAAALAADCgUIBQAAAA==.',Wa='Wagyubeef:BAAALAAECgYIDgAAAA==.Wargira:BAAALAAECgcIEwAAAA==.Warsire:BAAALAAECgQIBQAAAA==.',We='Weierstrasza:BAABLAAECoEjAAIhAAgIMyNSBAA/AwAhAAgIMyNSBAA/AwAAAA==.',Wi='Wingflaps:BAABLAAECoEfAAIZAAgIpiANBADvAgAZAAgIpiANBADvAgAAAA==.Wirin:BAAALAAECgYIDwAAAA==.',Wo='Wokeahontas:BAABLAAECoEVAAIeAAYINCU8FwB3AgAeAAYINCU8FwB3AgAAAA==.Workh:BAAALAAECgYIBgAAAA==.Woxan:BAAALAADCggICAABLAAECgcIGAASADIeAA==.',Wr='Wret:BAABLAAECoEYAAIUAAcIXgkAqwBjAQAUAAcIXgkAqwBjAQAAAA==.',Wu='Wuman:BAAALAADCgcICgAAAA==.',Xa='Xagen:BAAALAAECgYIDgABLAAFFAIICgAXANEaAA==.Xagorr:BAACLAAFFIEKAAIXAAII0RrEHQCqAAAXAAII0RrEHQCqAAAsAAQKgSEAAxcABwgfIrYkAKUCABcABwgfIrYkAKUCAAEAAwgpEdlGAHMAAAAA.Xauman:BAAALAADCgEIAQAAAA==.',Xh='Xhady:BAAALAAECgEIAQAAAA==.',Xi='Xiili:BAAALAADCgYIBgAAAA==.Xizylol:BAABLAAECoEhAAIRAAgI/B7IGADdAgARAAgI/B7IGADdAgAAAA==.',Xm='Xmasster:BAAALAADCgQIBAAAAA==.',Xo='Xorezp:BAAALAAECgUIBQAAAA==.',['Xé']='Xéz:BAABLAAECoEYAAISAAgIMRr5FwA6AgASAAgIMRr5FwA6AgAAAA==.',Ya='Yawgmoth:BAABLAAECoEjAAIJAAgI6BKuRADwAQAJAAgI6BKuRADwAQAAAA==.',Ye='Yenya:BAAALAADCgUIBgABLAAECgcIHgAQAHMjAA==.',Za='Zalbezal:BAABLAAECoEiAAIgAAgIbhx3HwB/AgAgAAgIbhx3HwB/AgAAAA==.Zanazal:BAAALAAECgMIAwAAAA==.Zargox:BAAALAADCgcIBwAAAA==.Zaruuna:BAAALAAECgMIAwAAAA==.Zaungoth:BAAALAADCgcIBwAAAA==.Zaunia:BAAALAADCgIIAgAAAA==.Zaïnt:BAAALAAECgYICAABLAAECggIHAAHABgZAA==.',Ze='Zealia:BAAALAAECgcIDgABLAAECgYIFgAPAEgiAA==.Zemalat:BAAALAAECgQIBwAAAA==.Zenzei:BAAALAADCggICAAAAA==.Zeronurish:BAAALAAECgcIDQAAAA==.Zetaprime:BAABLAAECoEUAAIUAAYIhBGXpgBqAQAUAAYIhBGXpgBqAQAAAA==.',Zi='Zinil:BAABLAAECoEYAAIJAAgIVQ8oTgDNAQAJAAgIVQ8oTgDNAQAAAA==.Zinkö:BAABLAAECoEiAAIaAAgIKBjELQBJAgAaAAgIKBjELQBJAgAAAA==.Zinstict:BAABLAAECoEYAAMUAAgI4xozMgB7AgAUAAgIVRozMgB7AgAYAAIIShUGTQB5AAAAAA==.',Zu='Zucchini:BAAALAAECgYIBgAAAA==.',Zv='Zvezda:BAACLAAFFIEHAAImAAMIbBMXAQD3AAAmAAMIbBMXAQD3AAAsAAQKgSkAAiYACAiBIz0BADIDACYACAiBIz0BADIDAAAA.',['Âg']='Âgreë:BAABLAAECoEVAAIUAAcIvRZmZgDnAQAUAAcIvRZmZgDnAQAAAA==.',['Âm']='Âmeth:BAACLAAFFIEHAAMDAAMIdBKbGQDaAAADAAMIRQubGQDaAAAfAAIImxk1CQCUAAAsAAQKgSMAAx8ACAhIGqQMAFECAB8ACAjuGaQMAFECAAMABgjJFSfcABgBAAAA.',['Ân']='Ânanas:BAABLAAECoEmAAIBAAgI0CBpBgDeAgABAAgI0CBpBgDeAgAAAA==.',['Äg']='Äggmil:BAAALAAECgYIDAAAAA==.',['Æm']='Æmûn:BAAALAAECggIDgAAAA==.',['Én']='Éner:BAAALAAECgMIAwAAAA==.',['Ða']='Ðaze:BAAALAADCgQIBAAAAA==.',['ße']='ßeelzebub:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end