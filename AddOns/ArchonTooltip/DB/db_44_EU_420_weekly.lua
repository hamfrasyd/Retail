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
 local lookup = {'Monk-Windwalker','Unknown-Unknown','Priest-Shadow','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Retribution','DeathKnight-Frost','Warlock-Destruction','Rogue-Subtlety','Rogue-Assassination','Hunter-Survival','Evoker-Devastation','Druid-Balance','Warrior-Arms','DemonHunter-Havoc','Warrior-Fury','Mage-Frost','Mage-Arcane','Mage-Fire','Monk-Mistweaver','Warlock-Demonology','Paladin-Holy','Priest-Holy','Druid-Feral','Druid-Restoration','Warlock-Affliction','Paladin-Protection','DemonHunter-Vengeance','Rogue-Outlaw','Shaman-Enhancement','Druid-Guardian','Evoker-Preservation','DeathKnight-Blood','Priest-Discipline','Evoker-Augmentation','DeathKnight-Unholy',}; local provider = {region='EU',realm='DieNachtwache',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ae='Aerope:BAAALAADCgYICwAAAA==.',Ai='Ainê:BAAALAADCgYIGQAAAA==.Aiolli:BAACLAAFFIEKAAIBAAQIhh/TAwB0AQABAAQIhh/TAwB0AQAsAAQKgRsAAgEACAh8HjMLAMYCAAEACAh8HjMLAMYCAAAA.',Al='Aldaril:BAAALAADCggICAAAAA==.Alekstrazsa:BAAALAAECgMIAwABLAAECggICAACAAAAAA==.Alfredó:BAAALAAECgUIDwAAAA==.Alienya:BAAALAADCggICAAAAA==.Aliiza:BAAALAAECgYIDAAAAA==.Allanah:BAABLAAECoEXAAIDAAcIMAipVAA9AQADAAcIMAipVAA9AQAAAA==.Altivo:BAAALAAECgYIDgAAAA==.Alyciya:BAABLAAECoEYAAIEAAYIuBIsTgBjAQAEAAYIuBIsTgBjAQAAAA==.',Am='Amarice:BAAALAAECgEIAQAAAA==.Amelton:BAAALAADCggIEQAAAA==.',An='Anivia:BAABLAAECoEUAAIFAAgIQBTjTwDFAQAFAAgIQBTjTwDFAQAAAA==.Ankhano:BAABLAAECoEZAAMGAAcIZhfvNgACAgAGAAcIZhfvNgACAgAFAAEIowNjGgEdAAAAAA==.Anluryn:BAABLAAECoEfAAMHAAgIsAk6iQBrAQAHAAgIsAk6iQBrAQAEAAMIyQNxowBKAAAAAA==.Antholf:BAAALAAECgMIAwAAAA==.Antony:BAAALAAECgYICAAAAA==.Anubis:BAABLAAECoEnAAMBAAgIqh0RDQCoAgABAAgIqh0RDQCoAgAIAAEIghrvPQBHAAAAAA==.Anyanka:BAAALAAECgMIBAAAAA==.Anä:BAAALAAECgMIBQAAAA==.Anùbìs:BAAALAAECgIIAgABLAAECggIJwABAKodAA==.',Ar='Aranys:BAAALAAECgcIDQAAAA==.Ardelvon:BAAALAAECggIBQAAAA==.Ariati:BAAALAADCggICAAAAA==.Arjan:BAABLAAECoEkAAIJAAgIziPXLgCQAgAJAAgIziPXLgCQAgAAAA==.Arkanos:BAAALAADCgEIAQAAAA==.Arkitoss:BAAALAAECgQICAAAAA==.Artaíos:BAABLAAECoEdAAIKAAYIAh1AbgDkAQAKAAYIAh1AbgDkAQAAAA==.',As='Asená:BAAALAAECgQIBgAAAA==.Ashantria:BAABLAAECoEYAAILAAcImxAZXwCgAQALAAcImxAZXwCgAQAAAA==.Ashaya:BAAALAAECggICAAAAA==.Asmodal:BAABLAAECoEbAAMMAAcI5hInHQB+AQAMAAYI2hUnHQB+AQANAAcIBQX9QAA2AQAAAA==.Asmoroth:BAAALAADCgEIAgAAAA==.Assandri:BAAALAAECgUIDQAAAA==.Astenay:BAAALAAECgYIBwAAAA==.',At='Ateka:BAAALAAECgcIDAAAAA==.Athels:BAAALAAECgYIDQAAAA==.Athène:BAAALAAECgYIEQAAAA==.',Aw='Awaken:BAAALAAECgMIAwAAAA==.',Ax='Axolòtl:BAAALAAECgMIBAAAAA==.',Az='Azgeda:BAAALAAECgUICAABLAAECggIKgAOANMhAA==.Azzumii:BAAALAAECgYIEwAAAA==.',Ba='Bacardiweiss:BAAALAAECgYIEAAAAA==.Baeldin:BAAALAAECgcIEgAAAA==.Balvenie:BAAALAADCggICAAAAA==.Barusu:BAAALAADCggIEAAAAA==.Barven:BAABLAAECoEYAAIPAAYIZx/mGgAvAgAPAAYIZx/mGgAvAgABLAAFFAQICgABAIYfAA==.',Be='Beldran:BAAALAAECgIIAwABLAAFFAIIBQAQALwPAA==.Beltaron:BAAALAAECggIBQAAAA==.Benito:BAAALAADCggIDQAAAA==.Bertraut:BAAALAAECgYIDgAAAA==.Bestatterin:BAABLAAECoEVAAIJAAYIygeT2gASAQAJAAYIygeT2gASAQAAAA==.',Bi='Bilbop:BAAALAADCggIEgABLAAECggIGwARAMIgAA==.',Bl='Blackydem:BAAALAAECgcICAABLAAECggIKgAOANMhAA==.Bloodface:BAAALAADCgcIBwAAAA==.Bloodmagicx:BAAALAADCgYIBwAAAA==.Bloodshéep:BAAALAADCggIEAAAAA==.Bloodyhunta:BAABLAAECoEYAAISAAgIuhdARgAlAgASAAgIuhdARgAlAgAAAA==.Blutmondluna:BAAALAADCgQIBgABLAADCggIEAACAAAAAA==.Blutî:BAAALAAECgIIAgAAAA==.',Bo='Boddie:BAABLAAECoEdAAIKAAgILSPCGQDuAgAKAAgILSPCGQDuAgAAAA==.Bodin:BAAALAAECgIIAgAAAA==.',Bu='Butwhy:BAAALAAECgEIAQAAAA==.',['Bá']='Bánhellsing:BAABLAAECoEZAAIFAAcI9Rv4MQAnAgAFAAcI9Rv4MQAnAgAAAA==.',['Bé']='Béllá:BAAALAADCgEIAQAAAA==.',Ca='Cadêra:BAAALAAECgMIBgABLAAECgUIBQACAAAAAA==.Carmondai:BAAALAAECgcIEgAAAA==.',Ce='Celestiné:BAABLAAECoEbAAIJAAgIqA12igCmAQAJAAgIqA12igCmAQAAAA==.',Ch='Chalice:BAAALAAECggICgAAAA==.Chazzye:BAAALAAECggICAAAAA==.Chromaggus:BAAALAAECgcIDgAAAA==.Chûchû:BAAALAAECggIDgAAAA==.',Ci='Cipactli:BAAALAADCgMIAwAAAA==.',Co='Collesii:BAABLAAECoEcAAITAAYIxiGlNgApAgATAAYIxiGlNgApAgAAAA==.Combustion:BAAALAAECgMIAwAAAA==.Cosmóó:BAACLAAFFIEMAAMUAAII5SE8BgDAAAAUAAII5SE8BgDAAAAVAAII5AthQQCIAAAsAAQKgSQABBQACAjrImUUAFsCABQABgiqJGUUAFsCABUACAhcH4VAACsCABYAAQh5BuQfADAAAAAA.',Cr='Crazynoc:BAAALAAECgEIAQAAAA==.Crizo:BAAALAAECgYICQAAAA==.Crów:BAAALAAECgQICQAAAA==.',Cy='Cymbel:BAAALAAECgYIEQAAAA==.',['Cô']='Côsmò:BAAALAAECggIDQABLAAFFAIIDAAUAOUhAA==.Côsmòó:BAAALAADCggIDgABLAAFFAIIDAAUAOUhAA==.',Da='Dahaka:BAAALAAECgcICwAAAA==.Darkhell:BAAALAADCgMIBQABLAADCggIEAACAAAAAA==.Darkluná:BAAALAADCgMIAwABLAADCggIEAACAAAAAA==.Darkside:BAAALAAECgIIAgAAAA==.Darktammy:BAAALAAECgYIDQAAAA==.Dartz:BAAALAADCgcIBwAAAA==.Datisdaelan:BAAALAAECggIEgAAAA==.Daze:BAAALAAECgIIAgABLAAECgMIAwACAAAAAA==.',De='Deathknîfe:BAAALAADCgEIAQAAAA==.Deckerdruid:BAABLAAECoEYAAIQAAcIXBr3IgAhAgAQAAcIXBr3IgAhAgAAAA==.Dekyi:BAABLAAECoEaAAIXAAgIpB80BwDaAgAXAAgIpB80BwDaAgAAAA==.Demenz:BAAALAADCggICAABLAAECggIBQACAAAAAA==.Demerzel:BAAALAAECgMIAQAAAA==.Deneria:BAAALAAECgIIAgAAAA==.Destraya:BAABLAAECoEdAAMYAAgI4hfsGwD9AQAYAAcIoBfsGwD9AQALAAcIcQuffwBHAQAAAA==.Destìny:BAAALAADCggIFAAAAA==.Devilemii:BAABLAAECoEVAAISAAYIOxPNjAB+AQASAAYIOxPNjAB+AQAAAA==.Devilscircle:BAAALAAECgMIAwAAAA==.',Dh='Dhara:BAABLAAECoEkAAIVAAgISxRHQgAkAgAVAAgISxRHQgAkAgAAAA==.Dhearan:BAAALAAECgYICwAAAA==.Dhörte:BAAALAADCggIGwAAAA==.',Di='Dicanio:BAAALAAECgQIBwAAAA==.Dispérutio:BAAALAADCgYIDgAAAA==.',Do='Domenia:BAAALAADCggICAAAAA==.',Dr='Dragonknîght:BAAALAAECgMIAwAAAA==.Dralin:BAAALAADCgcIBwAAAA==.Dreama:BAAALAAECgEIAQAAAA==.Dregorath:BAAALAAECgMIAwAAAA==.Droc:BAAALAADCggICwABLAAFFAIICAATAJcTAA==.Drogea:BAAALAAECgYIEAAAAA==.',Ds='Dshadir:BAAALAADCggIHgAAAA==.',['Dà']='Dàrzz:BAAALAADCgcIDQABLAADCggIDgACAAAAAA==.',['Dá']='Dáron:BAAALAAECgQIBAAAAA==.',['Dí']='Díca:BAAALAAECgYIBgAAAA==.',Ec='Ecolicin:BAAALAADCgcICgAAAA==.Ecrofy:BAABLAAECoEbAAIYAAYIqhzTIgDTAQAYAAYIqhzTIgDTAQAAAA==.',Ed='Edola:BAAALAAECgMICAAAAA==.',Eg='Egó:BAAALAAECgEIAQAAAA==.',Ei='Eisenpranke:BAAALAADCggIIQAAAA==.',El='Elanar:BAABLAAECoEXAAIDAAYIJwocWAAtAQADAAYIJwocWAAtAQAAAA==.Elisia:BAAALAADCgcIEwAAAA==.',En='Endzeít:BAACLAAFFIEFAAIPAAIIUAcSGAB/AAAPAAIIUAcSGAB/AAAsAAQKgR4AAg8ACAiyFIcoALgBAA8ACAiyFIcoALgBAAAA.Enion:BAAALAAECgEIAQAAAA==.',Er='Eriôn:BAAALAAECgYICgAAAA==.',Es='Esil:BAABLAAECoEUAAIHAAgIhRmNNwA/AgAHAAgIhRmNNwA/AgAAAA==.Espinass:BAAALAAECgcIBwAAAA==.',Ev='Evade:BAAALAAECggICAAAAA==.',Ex='Executioner:BAAALAAECgYIEwAAAA==.',Fa='Faimien:BAAALAAECgEIAQAAAA==.Falcón:BAAALAADCgYIBgAAAA==.Faleera:BAABLAAECoEUAAIFAAYIYh7xRQDjAQAFAAYIYh7xRQDjAQABLAAECggIHgAZACkZAA==.Faveyo:BAAALAAECgYIBwAAAA==.',Fe='Fediel:BAAALAAECggICAAAAA==.',Fi='Fireball:BAAALAADCgMIAwAAAA==.Fixdas:BAABLAAECoEVAAIZAAcI2CBHDQCOAgAZAAcI2CBHDQCOAgABLAAFFAQICgABAIYfAA==.',Fl='Flamir:BAAALAADCggIEAAAAA==.Flatulencias:BAAALAADCgIIAgAAAA==.Flinrax:BAAALAAECgQIBQABLAAECgYIGwAYAKocAA==.Fluxian:BAABLAAECoEXAAIaAAYI0yCcJwAtAgAaAAYI0yCcJwAtAgAAAA==.',Fr='Freakaziod:BAABLAAECoEfAAIRAAYIACAiCwALAgARAAYIACAiCwALAgAAAA==.Frozeneagle:BAAALAADCggICAABLAAECgEIAQACAAAAAA==.',Fu='Fulgidus:BAAALAADCggIGAAAAA==.Fusselraupe:BAAALAAECgIIAgAAAA==.',['Fî']='Fîetz:BAAALAADCggICAAAAA==.',Ga='Gadran:BAAALAAECgYIEgAAAA==.Galith:BAAALAAECgYIEQAAAA==.Galjun:BAAALAADCggICAABLAAFFAIIBQAbADYVAA==.Galmanis:BAABLAAECoEUAAIEAAgINhx/FwCTAgAEAAgINhx/FwCTAgABLAAFFAQICgABAIYfAA==.Garax:BAABLAAECoEqAAIOAAgI0yGOAQAgAwAOAAgI0yGOAQAgAwAAAA==.',Ge='Gealach:BAAALAAECgYIBwAAAA==.Gelin:BAAALAADCggICAAAAA==.Gerolds:BAAALAADCgQIBAAAAA==.',Gi='Gilara:BAAALAADCgYIDQABLAAECggIFwAHAB4XAA==.Gingerly:BAAALAADCgUIBQAAAA==.',Gl='Glangal:BAAALAAECggIBQAAAA==.Gloigur:BAAALAAECgcICwAAAA==.',Gn='Gnomá:BAAALAAECggICQAAAA==.',Go='Goa:BAAALAAECgIIAgAAAA==.Gondalor:BAAALAAECgIIAgAAAA==.Gorma:BAAALAADCgcIBwAAAA==.Gornim:BAAALAAECgcIBQAAAA==.',Gr='Gragagas:BAABLAAECoEjAAMMAAcIwSEKDABQAgANAAcIKR+BEwByAgAMAAcINxwKDABQAgAAAA==.Grammlo:BAAALAAECgQIDgAAAA==.Greatkix:BAAALAADCgUIBQAAAA==.Grenngweyja:BAAALAADCggIDAAAAA==.Grimhold:BAAALAAECgQIBQAAAA==.Grimmlit:BAAALAADCggICAAAAA==.Grlzilla:BAAALAAECgcIDgAAAA==.Grünbart:BAAALAAECgYIDAAAAA==.',['Gâ']='Gâbríel:BAABLAAECoEmAAIJAAgIMiMhFgAGAwAJAAgIMiMhFgAGAwAAAA==.',Ha='Haldefuchs:BAAALAAECgMIBQAAAA==.Haraldegon:BAABLAAECoEiAAMcAAgI6wlSYAA0AQAcAAgI6wlSYAA0AQAQAAcIrgSQYAD1AAAAAA==.Hatch:BAAALAAECggIBQAAAA==.',He='Headgear:BAAALAAECgYIAQAAAA==.Hedrot:BAAALAAECgYICQAAAA==.Heiligergorn:BAAALAAECgYICAAAAA==.Hexogon:BAABLAAECoEiAAMYAAgIhx8dDQCEAgAYAAcImR8dDQCEAgAdAAEICB/5MQBWAAAAAA==.',Hj='Hjelgrim:BAAALAAECggIEAAAAA==.',Ho='Holyangel:BAABLAAECoEfAAMJAAcICSGWMACIAgAJAAcICSGWMACIAgAeAAIIQAvNVwBRAAAAAA==.',Hy='Hyah:BAAALAADCggIEAABLAAECgcIFAAKAIURAA==.',['Hó']='Hóllýcróx:BAABLAAECoEjAAILAAgIQg76UwDCAQALAAgIQg76UwDCAQAAAA==.',Ic='Iceymage:BAAALAADCggIEAAAAA==.Icéy:BAABLAAECoEUAAIFAAYI0hcCZQCMAQAFAAYI0hcCZQCMAQAAAA==.',Il='Ilfi:BAABLAAECoEnAAISAAgIfSFYFgD7AgASAAgIfSFYFgD7AgAAAA==.',In='Inasha:BAAALAADCgYICwABLAAFFAIIBQAQALwPAA==.Iniyari:BAAALAAECggIBQAAAA==.',Ir='Iresá:BAAALAAECgcIEwAAAA==.Irisy:BAAALAADCggIGAAAAA==.',It='Itsoktocry:BAAALAAECgYIDQAAAA==.',Iu='Ius:BAAALAADCgYIDgAAAA==.',Iz='Izabella:BAAALAADCggICAAAAA==.',Ja='Jacesa:BAAALAAECgMIAQAAAA==.Jaspira:BAAALAADCgcIBgAAAA==.Jasse:BAAALAAECggIBgAAAA==.',Je='Jenifa:BAAALAADCggIDAAAAA==.',Jo='Jonnyrm:BAAALAAECggIEgAAAA==.',Ju='June:BAABLAAECoEwAAIGAAgIJCM+DAAcAwAGAAgIJCM+DAAcAwAAAA==.Juniarius:BAAALAAECggICAAAAA==.Justdk:BAAALAAECgcIBgAAAA==.',['Jâ']='Jâsmínê:BAAALAADCgUIBQAAAA==.',['Jì']='Jìnxí:BAAALAAECgYIBgAAAA==.',['Jø']='Jøøy:BAABLAAECoEkAAIfAAcIuCIJDQBjAgAfAAcIuCIJDQBjAgABLAAFFAIICAAIAD4jAA==.',Ka='Kadlin:BAAALAADCgYIBgAAAA==.Kaldoras:BAAALAADCgMIAwABLAAFFAIICQAgAB8TAA==.Karademon:BAABLAAECoEaAAISAAcIFCAFKQCXAgASAAcIFCAFKQCXAgAAAA==.Karafoxxí:BAABLAAECoEiAAIhAAcIOyAKBwCDAgAhAAcIOyAKBwCDAgAAAA==.Kararius:BAAALAADCgYIBgAAAA==.',Ke='Kerit:BAAALAAECggICwAAAA==.Keyterrorist:BAAALAADCgYIBgABLAAFFAYIGQAaADUeAA==.',Kh='Khloe:BAABLAAECoEeAAMZAAgIKRlCIwDNAQAZAAgIKRlCIwDNAQAJAAMIOQeyEgGJAAAAAA==.Khorâd:BAAALAADCgcIBwAAAA==.Khranosh:BAAALAADCggIDwABLAAECggIAwACAAAAAA==.Khungix:BAAALAADCgQIBAAAAA==.',Ki='Kirié:BAAALAAECgYIEAAAAA==.Kishou:BAACLAAFFIEFAAIQAAIIvA+qFwCLAAAQAAIIvA+qFwCLAAAsAAQKgSoAAhAACAj9GyggADUCABAACAj9GyggADUCAAAA.Kitten:BAAALAAECggIEAABLAAECggIGAAbANskAA==.',Kl='Klocki:BAAALAADCgMIAwAAAA==.',Kn='Kneder:BAAALAAECgYICwAAAA==.Knülle:BAAALAADCgQIBgAAAA==.',Kr='Krally:BAAALAADCggIBgABLAADCggIBwACAAAAAA==.Kroxas:BAAALAADCgYIBgAAAA==.',Ku='Kultian:BAAALAAECgIIAgAAAA==.Kupece:BAAALAAECgIIAgAAAA==.',['Ký']='Kýros:BAAALAAECgYIBgAAAA==.',La='Lachdana:BAAALAADCgEIAQAAAA==.Laodi:BAEBLAAECoEkAAIUAAgI6B8jCQDsAgAUAAgI6B8jCQDsAgAAAA==.Laody:BAEALAAECgYICQABLAAECggIJAAUAOgfAA==.Larela:BAAALAAECggICAAAAA==.Larinar:BAAALAAECggICAABLAAECggIFwAHAB4XAA==.Latrana:BAAALAADCgYIBgAAAA==.',Le='Lebenshilfe:BAAALAAECgIIAgAAAA==.Leodan:BAACLAAFFIEGAAISAAIIoBlvIwCiAAASAAIIoBlvIwCiAAAsAAQKgScAAhIACAiZIF8ZAOgCABIACAiZIF8ZAOgCAAAA.Lerenija:BAAALAAECgcIBwAAAA==.Leôna:BAAALAAECgYIBgAAAA==.',Li='Lightbreaker:BAAALAAECggICAAAAA==.Lighttank:BAAALAADCgIIAgAAAA==.Lilithel:BAABLAAECoEXAAILAAcIRgjBeQBWAQALAAcIRgjBeQBWAQAAAA==.Linfu:BAAALAADCgQIBAAAAA==.',Lj='Ljóshjarta:BAABLAAECoEnAAIKAAgIvRq/OwBkAgAKAAgIvRq/OwBkAgAAAA==.',Ll='Lluna:BAAALAADCggIEAAAAA==.',Lo='Lomk:BAAALAAECggICAAAAA==.Lorellia:BAAALAAECgIIAwAAAA==.Lorry:BAAALAAECgYIEwAAAA==.Lorwath:BAAALAAECgQIBAABLAAFFAIICQAgAB8TAA==.Lotok:BAAALAADCggICAABLAAECggIBQACAAAAAA==.',Lu='Lucy:BAABLAAECoEaAAMDAAcI+w1gQACZAQADAAcI+w1gQACZAQAaAAYI9xG/UwBkAQAAAA==.Lusí:BAAALAAECgMIBAAAAA==.',Ly='Lybärror:BAABLAAECoEfAAIIAAgI5CNEBAAhAwAIAAgI5CNEBAAhAwAAAA==.Lyron:BAAALAAECgYIEQAAAA==.Lyrror:BAAALAAECgYIDQAAAA==.',['Lâ']='Lâkâstriâ:BAEALAAECgcIEAABLAAECgUIBgACAAAAAA==.',['Ló']='Lórellin:BAABLAAFFIEHAAIcAAIIjhCeJwCAAAAcAAIIjhCeJwCAAAAAAA==.',['Lú']='Lúnavëa:BAAALAADCgcIDAAAAA==.Lúrtz:BAAALAAECggICwAAAA==.',['Lý']='Lýella:BAACLAAFFIEGAAIZAAIIMhI8FACXAAAZAAIIMhI8FACXAAAsAAQKgSIAAhkACAgCG80dAPYBABkACAgCG80dAPYBAAAA.',Ma='Magicstrikz:BAAALAADCggICAABLAAECgYIDAACAAAAAA==.Magnifik:BAABLAAECoEZAAIeAAcIrQ0EMQBCAQAeAAcIrQ0EMQBCAQAAAA==.Magí:BAAALAADCgUIBQAAAA==.Mahfouz:BAAALAAECgMIAwAAAA==.Mahja:BAAALAAECgMIAwAAAA==.Malenia:BAAALAAECgUIBgAAAA==.Maliwhen:BAABLAAECoEXAAIfAAcIlBmwFAD6AQAfAAcIlBmwFAD6AQAAAA==.Malradon:BAABLAAECoEnAAQQAAgI3x4JFACiAgAQAAgI+h0JFACiAgAiAAgIuxesCAAwAgAcAAMIvhROlQCaAAAAAA==.Malunari:BAAALAAECgQIBAABLAAECggIGgAXAKQfAA==.Malve:BAAALAADCgYIBgAAAA==.Mannixe:BAAALAAECgUIBwAAAA==.Marily:BAAALAADCgYIBgAAAA==.Mariéchen:BAABLAAECoEiAAIJAAcInQznogB6AQAJAAcInQznogB6AQAAAA==.Marvelius:BAAALAAECggICQAAAA==.Marx:BAAALAADCggIBwAAAA==.Masassi:BAAALAAFFAEIAQAAAA==.',Me='Mentras:BAABLAAECoEXAAIFAAgIlgWYsgDfAAAFAAgIlgWYsgDfAAAAAA==.Meren:BAAALAAECgEIAQAAAA==.Merogh:BAAALAAECgIIAgAAAA==.',Mi='Midi:BAACLAAFFIEJAAIgAAIIHxPtAwCWAAAgAAIIHxPtAwCWAAAsAAQKgSIAAiAACAgCH3MDAKcCACAACAgCH3MDAKcCAAAA.Mijá:BAABLAAECoEmAAIJAAgINh2FNAB4AgAJAAgINh2FNAB4AgAAAA==.Milamberevoz:BAAALAAECgQIBAAAAA==.Miri:BAAALAAECggIBQAAAA==.Misune:BAAALAAECggIEgABLAAECggIFwAHAB4XAA==.Mitsûri:BAAALAADCgcICwAAAA==.',Mk='Mkmon:BAACLAAFFIEIAAIIAAIIPiPlCADNAAAIAAIIPiPlCADNAAAsAAQKgRoAAggACAj8IpAEABkDAAgACAj8IpAEABkDAAAA.',Mu='Mullemauss:BAAALAAECgYIDAAAAA==.',Na='Nachtarâ:BAABLAAECoEXAAMHAAYIHhceiQBrAQAHAAYI1RYeiQBrAQAEAAYIiQoEaQAGAQAAAA==.Nadeko:BAAALAADCggIJgABLAAECgMIBgACAAAAAA==.Naemii:BAABLAAECoEgAAIFAAcIkCFsGACcAgAFAAcIkCFsGACcAgABLAAECgYIFQASADsTAA==.Nafine:BAAALAADCggIEQAAAA==.Naluzhul:BAAALAADCggIDgABLAAECggIAwACAAAAAA==.Nanó:BAAALAAECgYIDQAAAA==.Narud:BAAALAADCggIDAAAAA==.Nayl:BAAALAAECgYIDgAAAA==.',Ne='Neirenn:BAAALAAECgMIBgAAAA==.',Ni='Nimaly:BAAALAAECgIIAwAAAA==.Niòbe:BAAALAADCgcIDwAAAA==.',No='Noeken:BAAALAADCgcIBwABLAAECggIJQAHAP8ZAA==.Noellesilva:BAAALAADCgUIBQAAAA==.Nostoros:BAAALAADCggIEAABLAAECgIIAgACAAAAAA==.Notcola:BAAALAADCggIGgABLAAECgMIBgACAAAAAA==.',Nu='Numek:BAAALAAECgQIBQAAAA==.Nurgos:BAAALAADCgcICAAAAA==.Nutriscore:BAAALAAECgMIAwABLAAFFAIIBgAYAJkLAA==.',Ny='Nydara:BAAALAADCggIEAAAAA==.Nymue:BAAALAADCgcICQAAAA==.',['Né']='Nédriel:BAAALAADCggICQAAAA==.',Ob='Obvaylon:BAABLAAECoEaAAIGAAgIuxRgLwAoAgAGAAgIuxRgLwAoAgAAAA==.',Oc='Occulco:BAAALAADCgYIFgAAAA==.',Od='Odens:BAAALAADCggICAAAAA==.',Or='Oricalkos:BAAALAADCgMIAwAAAA==.',Ot='Otis:BAAALAAECgIIAgAAAA==.',Pa='Paldrian:BAAALAADCgcIBwAAAA==.Palohunter:BAAALAAECggIDgABLAAFFAMICQAJAHUXAA==.',Pe='Pestilenz:BAAALAADCggIDwAAAA==.',Ph='Philisa:BAAALAAECgEIAwAAAA==.',Pi='Piadora:BAABLAAECoEfAAQcAAYIzxxyOgDAAQAcAAYIzxxyOgDAAQAbAAIIYAiZOgBYAAAQAAIIxwQfhgBOAAAAAA==.Pitahaya:BAABLAAECoEXAAMjAAcIxRc7GACIAQAjAAYI2xU7GACIAQAPAAEIDwiSWgA6AAAAAA==.Pitelf:BAAALAAECgEIAQAAAA==.',Pu='Pudge:BAAALAADCggIEAABLAAECgcIDwACAAAAAA==.Pumpbear:BAAALAADCggIDgAAAA==.Purplebtch:BAAALAADCggICAABLAADCggIDgACAAAAAA==.',['Pâ']='Pâllâx:BAABLAAECoEoAAIJAAgIhR6WLwCNAgAJAAgIhR6WLwCNAgAAAA==.',Qi='Qixidasleben:BAAALAAECgYICAAAAA==.',Qu='Quemen:BAAALAADCggIDQAAAA==.Quirin:BAAALAADCggICgAAAA==.',Ra='Rahamut:BAAALAADCggIFAAAAA==.Raidin:BAABLAAECoEfAAITAAcI6yJsHgCtAgATAAcI6yJsHgCtAgAAAA==.Ralloon:BAAALAADCggICAAAAA==.Randolf:BAAALAAECgMIAwAAAA==.Raphna:BAAALAAECgYICgABLAAECgcIGAALAJsQAA==.Rashkaja:BAABLAAECoEnAAIFAAgIICFlDwDXAgAFAAgIICFlDwDXAgAAAA==.Raziêl:BAAALAAECgQIBQAAAA==.',Re='Reanimatril:BAAALAADCgYICgAAAA==.Remdk:BAAALAAECgEIAQABLAAECgcIDgACAAAAAA==.Rendan:BAABLAAECoEnAAIeAAgIMCQjAwBGAwAeAAgIMCQjAwBGAwAAAA==.',Rh='Rhoan:BAABLAAECoEaAAIiAAcIZA1CFABTAQAiAAcIZA1CFABTAQAAAA==.',Ri='Rivkâh:BAAALAAECgMIBAAAAA==.',Ro='Rongo:BAAALAADCgQIBAABLAAECgYIGwAYAKocAA==.Rosalina:BAAALAADCgQIBAAAAA==.',Ru='Rustý:BAAALAAECgYIDQAAAA==.',['Rá']='Ráyven:BAAALAADCggIDgAAAA==.',['Râ']='Râgnàr:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.',['Rí']='Rían:BAAALAAECgUIEAAAAA==.',['Ró']='Róssweisse:BAAALAAECgcIDwAAAA==.',Sa='Sacima:BAAALAAECggICAAAAA==.Sagittâ:BAAALAADCgEIAQAAAA==.Sahira:BAAALAADCgcIBwAAAA==.Saja:BAAALAAECgYICQAAAA==.Sajá:BAAALAADCgcIBwAAAA==.Salome:BAABLAAECoEkAAIVAAgIrhg9QAAsAgAVAAgIrhg9QAAsAgAAAA==.Sarlessa:BAAALAAECgYICAAAAA==.Sayunarí:BAABLAAECoEYAAITAAgI4wssVwCzAQATAAgI4wssVwCzAQAAAA==.',Sc='Schmerzabt:BAAALAAECgMIBAAAAA==.Schwibbelkj:BAAALAAECgEIAQAAAA==.Scöfi:BAAALAADCggIEwAAAA==.Scööfii:BAAALAADCgcIDQAAAA==.',Se='Seal:BAAALAAECgYIBgAAAA==.Selor:BAAALAADCggIIAAAAA==.Senthi:BAAALAAECgMIAwAAAA==.Seràphina:BAAALAAECgMIBQAAAA==.Seráya:BAAALAADCggICAAAAA==.',Sh='Shamsn:BAACLAAFFIEHAAIFAAQIPBXICQA2AQAFAAQIPBXICQA2AQAsAAQKgRcAAgUACAjaHrxHAN4BAAUACAjaHrxHAN4BAAAA.Shavedbolts:BAAALAADCgYIBgAAAA==.Shelby:BAABLAAECoEWAAIFAAcISRaglgAWAQAFAAcISRaglgAWAQAAAA==.Shelldorina:BAABLAAECoEbAAIfAAYI4QaWOgDGAAAfAAYI4QaWOgDGAAAAAA==.Shianá:BAAALAAECgYIDAAAAA==.Shinary:BAAALAADCgIIAgABLAADCggIDgACAAAAAA==.Shinyqtxt:BAAALAADCgEIAQABLAAECggIFgATAHkYAA==.Shynani:BAAALAAECgEIAQAAAA==.',Sk='Skadh:BAABLAAECoEwAAMfAAgIMBr7DwA3AgAfAAgIFRr7DwA3AgASAAgIARQoWQDvAQAAAA==.Skatorflak:BAAALAADCgIIAgAAAA==.Skavampir:BAAALAAECgUIBQABLAAECggIMAAfADAaAA==.',Sl='Slinknar:BAAALAADCggICAAAAA==.Slyfôx:BAABLAAECoEVAAISAAYI5g7AowBSAQASAAYI5g7AowBSAQAAAA==.Slàól:BAAALAAECgYICgAAAA==.',So='Sohyon:BAAALAADCggICAAAAA==.Solmyr:BAAALAADCgYIBgABLAAECgMIAwACAAAAAA==.Sombras:BAAALAADCgYIBgAAAA==.Soreana:BAAALAAECggIBwAAAA==.Sorti:BAAALAADCgQIBAAAAA==.',St='Stormhammer:BAAALAAECgYICwAAAA==.Stîcks:BAAALAAECgYIDAAAAA==.',Sy='Sylamira:BAAALAAECgYIDAAAAA==.Sylvanaro:BAAALAADCgYIBgAAAA==.Sylvàna:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâturdây:BAAALAAECgEIAgAAAA==.',['Sé']='Sénthi:BAAALAAECgIIAgAAAA==.',['Sê']='Sêgomo:BAAALAADCgYIBgAAAA==.',['Sí']='Sísra:BAACLAAFFIEGAAIHAAII5wpZNgCBAAAHAAII5wpZNgCBAAAsAAQKgSMAAgcACAjWHGEpAHgCAAcACAjWHGEpAHgCAAAA.',Ta='Talsanir:BAAALAADCggICAABLAAECggIBQACAAAAAA==.Tazo:BAABLAAECoEjAAIDAAcIRA5gPwCeAQADAAcIRA5gPwCeAQAAAA==.',Te='Teremas:BAABLAAECoEXAAMKAAgIXAAlYQEQAAAKAAcIWgAlYQEQAAAkAAcIHgC4RQAHAAAAAA==.Teufelsbrut:BAABLAAECoEVAAIQAAcIBxL9TwA9AQAQAAcIBxL9TwA9AQAAAA==.',Th='Thadus:BAABLAAECoEZAAMJAAcIeRfkXQABAgAJAAcIeRfkXQABAgAeAAMIZwvqUQBuAAAAAA==.Thalrax:BAAALAAECggIDgABLAAFFAIIBQAQALwPAA==.Thaori:BAAALAAECggICAAAAA==.Theldain:BAAALAADCgEIAQABLAAFFAIIBQAQALwPAA==.Theodor:BAAALAAECggICAAAAA==.Thytsai:BAAALAADCgIIAQABLAAECgEIAQACAAAAAA==.',Ti='Tibbers:BAAALAADCgIIAgAAAA==.',Tk='Tkhühnchen:BAABLAAECoEjAAISAAcI8B9GLQCDAgASAAcI8B9GLQCDAgAAAA==.',To='Tortur:BAAALAAECggICAAAAA==.Torîan:BAAALAAECgUIBQAAAA==.Touka:BAAALAADCggIKAABLAAECgMIBgACAAAAAA==.Toxicos:BAAALAADCgUIBQAAAA==.Toxuz:BAACLAAFFIEGAAMOAAQI9RDKAQC+AAAOAAII+h/KAQC+AAAEAAQI7AUAAAAAAAAsAAQKgRgAAw4ACAi1IMABABYDAA4ACAi1IMABABYDAAcACAgQDoR9AIMBAAAA.',Tr='Tronnos:BAAALAAECgEIAQAAAA==.Troublemaker:BAAALAAECgIIAgAAAA==.Trucky:BAAALAAECgYICQAAAA==.Tráinaider:BAAALAADCggICAAAAA==.Trâshhuntér:BAAALAAECggIBAAAAA==.Trôax:BAAALAADCgQIBAABLAADCgYIBgACAAAAAA==.',Ts='Tschabalala:BAAALAAECggICAAAAA==.Tsuki:BAAALAAECgIIAgAAAA==.',Ty='Tyleet:BAAALAAECgEIAQAAAA==.Tyradem:BAAALAAECgcIBwAAAA==.',Ul='Ulfbërht:BAAALAADCgMIAgAAAA==.',Un='Ungläubige:BAAALAADCgcIAgAAAA==.',Uu='Uurs:BAAALAAECgYICwAAAA==.',Va='Valhalla:BAAALAAECgUIDgABLAAECggIKgAOANMhAA==.Valkoríon:BAAALAAECggICAAAAA==.Vanbilbo:BAABLAAECoEbAAMRAAgIwiC1AgALAwARAAgIBCC1AgALAwATAAcIOR9sKABwAgAAAA==.Varhic:BAAALAADCggICwAAAA==.Vaynak:BAAALAAECgYIEAAAAA==.',Ve='Veldras:BAAALAAECgYIEAAAAA==.Velindas:BAAALAADCgIIAgABLAADCggIEAACAAAAAA==.Velindâs:BAAALAADCgYIBgABLAADCggIEAACAAAAAA==.Velocity:BAAALAAECgIIAgAAAA==.Verpflanzt:BAABLAAECoEVAAMcAAYIzhZsTgBwAQAcAAYIzhZsTgBwAQAQAAYINQ7bVgAiAQAAAA==.Verschwörer:BAAALAADCggICAAAAA==.Verstohlen:BAAALAADCgMIAwABLAAECgYIFQAcAM4WAA==.',Vi='Vilya:BAACLAAFFIEVAAIaAAUI6RFfBwCCAQAaAAUI6RFfBwCCAQAsAAQKgS8AAxoACAgtIhYNAOwCABoACAjRIBYNAOwCACUABgg3IZQFAEcCAAAA.Violencifer:BAAALAADCgQIBAAAAA==.',Vo='Voy:BAAALAADCggICAAAAA==.',Vy='Vykas:BAAALAAECgcIEAAAAA==.',['Và']='Vàla:BAAALAAECgEIAQAAAA==.',Wa='Waffles:BAAALAAECggIBQAAAA==.Waldbändíger:BAAALAADCgYIBgAAAA==.Waltus:BAAALAAECgEIAQAAAA==.Warlove:BAAALAADCgcIDAAAAA==.Warpudgé:BAAALAADCgYIBgABLAAECgcIDwACAAAAAA==.',We='Werfer:BAAALAAECgEIAQAAAA==.',Wh='Whisna:BAAALAADCgUIBQAAAA==.',Wi='Wienermädl:BAAALAAECgEIAgAAAA==.Wildblossom:BAAALAAECgMIAwAAAA==.Witya:BAABLAAECoEiAAQPAAgI9xauIgDnAQAPAAcIgxWuIgDnAQAjAAgIKxJtEgDYAQAmAAYIfRQYCgCUAQAAAA==.',Wo='Worps:BAAALAAECgYICwAAAA==.',['Wá']='Wándáá:BAAALAAECgUIBgAAAA==.',['Xé']='Xérxís:BAAALAADCgEIAQAAAA==.',Ya='Yarimari:BAAALAAECggICAAAAA==.Yasika:BAAALAAECgYIBgAAAA==.',Ye='Yennen:BAAALAAECgcIDwAAAA==.Yetapeng:BAAALAAECgQIBQAAAA==.',Ze='Zellaris:BAAALAAECgEIAQAAAA==.Zelrin:BAAALAADCggICAAAAA==.Zenedarius:BAAALAAECgYIBgABLAAECggIIgAXALcUAA==.Zeretha:BAAALAAECgIIAgAAAA==.Zesan:BAABLAAECoEiAAIXAAgItxQ+FQD4AQAXAAgItxQ+FQD4AQAAAA==.',Zi='Zinnbart:BAAALAAECgYICQABLAAECggIIgAOAEcRAA==.',Zo='Zoemii:BAAALAADCgYIBgAAAA==.Zoti:BAAALAADCgYIBgAAAA==.',Zr='Zrotic:BAABLAAECoExAAMkAAgIdiMMBAAiAwAkAAgIdiMMBAAiAwAnAAYIJxZFHgCwAQAAAA==.',Zu='Zualles:BAABLAAECoEWAAITAAgIeRi3MABEAgATAAgIeRi3MABEAgAAAA==.Zuckerpuppe:BAABLAAECoElAAIHAAgI/xmTVwDbAQAHAAgI/xmTVwDbAQAAAA==.Zuia:BAABLAAECoEqAAMHAAgImR6THgCvAgAHAAgImR6THgCvAgAEAAYIBRIfYQAgAQAAAA==.',Zy='Zyasara:BAABLAAECoEhAAMaAAcIUhJnRwCTAQAaAAcIUhJnRwCTAQADAAYIWgRUZgDhAAAAAA==.Zyk:BAAALAAECgEIAQAAAA==.',['Zâ']='Zâth:BAAALAAECgYIDAAAAA==.',['Àn']='Ànubìs:BAAALAAECgcIDQABLAAECggIJwABAKodAA==.',['Âl']='Âlâstor:BAAALAAECgYIBwAAAA==.',['Ân']='Ânubìs:BAAALAADCggICAABLAAECggIJwABAKodAA==.',['Æp']='Æpoo:BAABLAAECoEVAAIFAAYIrBQOcwBnAQAFAAYIrBQOcwBnAQAAAA==.',['Êl']='Êla:BAABLAAECoEbAAIJAAcIwBOumgCIAQAJAAcIwBOumgCIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end