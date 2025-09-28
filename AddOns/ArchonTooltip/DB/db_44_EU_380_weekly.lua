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
 local lookup = {'Warrior-Fury','Warrior-Arms','Shaman-Restoration','Priest-Holy','Paladin-Protection','Unknown-Unknown','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Druid-Feral','Warrior-Protection','Rogue-Outlaw','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Mage-Fire','DemonHunter-Havoc','Paladin-Holy','Mage-Frost','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Survival','DemonHunter-Vengeance','Mage-Arcane','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Affliction','Monk-Mistweaver',}; local provider = {region='EU',realm='Medivh',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abalonne:BAABLAAECoEeAAMBAAgIJxiKLgBOAgABAAgIJxiKLgBOAgACAAEIuBL0MgA5AAAAAA==.Abygaga:BAAALAAECgMIAwABLAAECggIMAADABwXAA==.',Ac='Ach:BAAALAADCggIDwAAAA==.',Ad='Addey:BAAALAAECgYICgAAAA==.',Ae='Aelftÿrith:BAAALAAECgUIBQAAAA==.Aerhos:BAAALAAECgYIDgAAAA==.Aeyla:BAAALAADCgUIBQAAAA==.',Ag='Agonÿ:BAAALAADCgIIAgAAAA==.',Ak='Akunda:BAAALAADCgYIBgAAAA==.',Al='Aldétao:BAAALAAECgYIEQAAAA==.Alhoa:BAAALAADCggIFQAAAA==.Aloulou:BAABLAAECoEnAAIDAAgIjxQ2SADcAQADAAgIjxQ2SADcAQAAAA==.Aloulouia:BAABLAAECoEbAAIEAAgImxqCGwB6AgAEAAgImxqCGwB6AgAAAA==.Alphabruts:BAAALAADCgcIEgAAAA==.Alrakazbam:BAAALAADCggIFwAAAA==.',Am='Amrodbergen:BAAALAAECgMIAwAAAA==.',An='Angell:BAAALAAECgEIAQAAAA==.Anhydrrax:BAAALAADCggICQAAAA==.Annahé:BAABLAAECoEhAAIFAAcIAhpzIQC0AQAFAAcIAhpzIQC0AQAAAA==.Anémy:BAAALAADCggICwAAAA==.',Ap='Apodecâ:BAAALAAECgYIDwAAAA==.',Ar='Arkaziel:BAACLAAFFIELAAMBAAMIrB5gDQAcAQABAAMIWR5gDQAcAQACAAIIDh4QAgC2AAAsAAQKgR0AAwEACAhII5QYANQCAAEACAh4H5QYANQCAAIABwh8I3cGAH8CAAAA.Armaeris:BAAALAAECgYIDwABLAAECgYIDwAGAAAAAA==.Artaas:BAABLAAECoEZAAIHAAgItBhZQgBQAgAHAAgItBhZQgBQAgAAAA==.Artheon:BAAALAADCggICAAAAA==.Arÿ:BAABLAAECoEtAAQIAAgIGRsWJgANAgAIAAcItBsWJgANAgAJAAUI3xxmRACWAQAKAAUIVw4AAAAAAAAAAA==.',As='Askell:BAAALAADCgUIBQAAAA==.Aspeak:BAAALAADCgYIBgAAAA==.',At='Atlantya:BAAALAAECgMIBgAAAA==.',Au='Aurald:BAAALAADCgYICgAAAA==.',Az='Azmaelle:BAAALAAECgMIAwAAAA==.',['Aï']='Aïkô:BAAALAAECgIIBQAAAA==.',Ba='Babykaizer:BAABLAAECoEZAAILAAgILhVNJQDWAQALAAgILhVNJQDWAQAAAA==.Bachibouzook:BAEALAADCgcIGQABLAAECggIJgAEAN8eAA==.Ballrogue:BAAALAAECggIAQAAAA==.Barbarella:BAAALAADCggICAAAAA==.',Be='Belledeloin:BAAALAADCgcICAAAAA==.',Bi='Bigblackcat:BAAALAAECggIAwAAAA==.Bigcila:BAAALAADCgcIDgAAAA==.Biggyzeb:BAAALAAECgYIBwAAAA==.Birgittbarjo:BAAALAAECgMIBQAAAA==.',Bl='Blacksan:BAAALAADCggICAAAAA==.Blekz:BAAALAAECgEIAQAAAA==.Bligzdemone:BAAALAADCggIFAAAAA==.Bligzeera:BAAALAADCgUIBQAAAA==.Blkh:BAAALAAECgYIBwAAAA==.',Bo='Boinboin:BAAALAAECgQIBAAAAA==.Boldar:BAABLAAECoEhAAIMAAgIbBINBwATAgAMAAgIbBINBwATAgAAAA==.Bonegrinder:BAAALAAECgIIAgAAAA==.Borboleta:BAAALAAECgEIAQAAAA==.Bouledepoual:BAAALAAECgYIBwAAAA==.',Br='Brocéfilénia:BAACLAAFFIELAAIDAAMIEiURCQBFAQADAAMIEiURCQBFAQAsAAQKgRwAAgMACAjlH4wVAK4CAAMACAjlH4wVAK4CAAAA.Brocéliandre:BAAALAAECgcIBwAAAA==.',Bu='Bubulle:BAAALAAECgEIAQAAAA==.Bulladin:BAAALAAECgEIAQAAAA==.Butchër:BAAALAADCgUIBQAAAA==.',['Bö']='Böduog:BAABLAAECoEiAAINAAgI1hrVHwBWAgANAAgI1hrVHwBWAgAAAA==.',Ce='Celeborn:BAAALAAECgYIBgAAAA==.Celtus:BAAALAADCggIDwAAAA==.',Ch='Chaney:BAAALAADCgcICAAAAA==.Charckan:BAACLAAFFIEGAAIOAAIICRZnKACUAAAOAAIICRZnKACUAAAsAAQKgScAAw4ACAiLHa8wAFkCAA4ACAgVHK8wAFkCAA8ACAgNGa4iAD0CAAAA.Chimani:BAAALAAECgIIAgAAAA==.Chriz:BAAALAADCgMIAwAAAA==.Chymay:BAAALAAECgcIBwAAAA==.Chymene:BAAALAAECgYIBwAAAA==.Châmânos:BAAALAADCgIIAgAAAA==.Chêfdeguerre:BAAALAADCgIIAgAAAA==.Chïkâ:BAAALAADCgMIAwAAAA==.',Ci='Ciaran:BAAALAAECgIIAgAAAA==.Ciridan:BAAALAADCgYIBgAAAA==.',Cl='Clayman:BAAALAAECgYIDQAAAA==.Clutu:BAAALAAECgcIDQAAAA==.',Co='Codrus:BAAALAAECgQIBwAAAA==.Confidence:BAAALAADCggICQAAAA==.',Cr='Crevur:BAAALAAECgYIEAAAAA==.Croukol:BAAALAADCggIDAAAAA==.',['Cé']='Céellex:BAABLAAECoEfAAIQAAgIHR7SBACpAgAQAAgIHR7SBACpAgAAAA==.',['Cô']='Côrns:BAAALAAECgIIAgAAAA==.Côôlma:BAAALAADCgUIBQAAAA==.',['Cø']='Cørey:BAAALAAECgIIAgAAAA==.',Da='Damaran:BAAALAAECgYICgAAAA==.Danka:BAAALAAECgEIAgAAAA==.Darkdawn:BAAALAAECgYICQAAAA==.Dashin:BAAALAAECgQIBAAAAA==.',De='Deadlord:BAAALAADCgcIBwAAAA==.Decafine:BAAALAAECgYICQABLAAECggIHwAQAB0eAA==.Demonolaw:BAAALAAECgcIBwAAAA==.Demonyack:BAAALAADCggIHwABLAAECgEIAQAGAAAAAA==.Deriiox:BAAALAADCggICAAAAA==.Destriacion:BAAALAAECgQIBAAAAA==.',Dh='Dhéïstrà:BAAALAADCggICAAAAA==.',Di='Diamønds:BAAALAAECgMIAwAAAA==.Dispel:BAEBLAAECoEmAAIEAAgI3x4SFACvAgAEAAgI3x4SFACvAgAAAA==.',Do='Doomibis:BAAALAADCgYIDAAAAA==.Doominette:BAAALAADCgUIBwAAAA==.Doominie:BAAALAADCgYIBgAAAA==.Douceure:BAABLAAECoEWAAIJAAYInweqjAC2AAAJAAYInweqjAC2AAAAAA==.',Dr='Dracodoom:BAAALAADCgMIAwAAAA==.Draënaa:BAAALAADCgYICAAAAA==.Drooxie:BAAALAAECgYICAAAAA==.Druidassa:BAAALAAECgYIBgABLAAECggIGgARABwjAA==.',Du='Dubaichoco:BAAALAADCggIDAABLAAECgYIDgAGAAAAAA==.',['Dâ']='Dârktek:BAABLAAECoEkAAISAAgIhiNOEwAMAwASAAgIhiNOEwAMAwAAAA==.',['Dé']='Dégoya:BAAALAAECgMIAwABLAAECggIGgARABwjAA==.',El='Elasha:BAAALAADCggIFAAAAA==.Ellmago:BAAALAADCgcIBwAAAA==.Ellÿnna:BAABLAAECoEVAAITAAYIcxQ9LwCBAQATAAYIcxQ9LwCBAQAAAA==.Elrubis:BAAALAAECgMIBwAAAA==.Elvorion:BAAALAADCgcICgAAAA==.',Em='Eminda:BAAALAAECgMIAwAAAA==.Emisia:BAAALAADCgUIBQAAAA==.',Ep='Epidémies:BAAALAAECgIIAgAAAA==.',Er='Erikabergen:BAABLAAECoEpAAIOAAgI+h5eJACQAgAOAAgI+h5eJACQAgAAAA==.Erindal:BAAALAAECggIEgAAAA==.Ermus:BAAALAAECgEIAQAAAA==.Erykä:BAABLAAECoEcAAIUAAcIJB3iEwBfAgAUAAcIJB3iEwBfAgAAAA==.',Ex='Exxodus:BAAALAAECgYICQAAAA==.',Ez='Ezactement:BAAALAADCggICgABLAAECgIIAgAGAAAAAA==.',Fa='Fabÿ:BAAALAAECgYIDwAAAA==.Fangpi:BAABLAAECoEoAAIVAAgIBCNzBQAoAwAVAAgIBCNzBQAoAwAAAA==.Farlock:BAABLAAECoEbAAMWAAcIuhWmFQDKAQAWAAcIlBWmFQDKAQAXAAYIsBH/NwBsAQAAAA==.Faust:BAAALAADCgYICwAAAA==.',Fi='Finëss:BAABLAAECoEbAAIXAAcIsR7iEgB5AgAXAAcIsR7iEgB5AgAAAA==.',Fj='Fjordicus:BAAALAAECgMIBQAAAA==.',Fl='Flobarjo:BAABLAAECoEgAAIYAAgIcR0YKQCoAgAYAAgIcR0YKQCoAgAAAA==.',Fo='Folkeÿnn:BAAALAAECgQIBAAAAA==.Forever:BAABLAAECoEdAAMZAAgIrxQ/OwAfAgAZAAgIrxQ/OwAfAgAaAAMI8wj6agCSAAAAAA==.',Fr='Fraurseg:BAABLAAECoEUAAIQAAcI4R+JBQCMAgAQAAcI4R+JBQCMAgAAAA==.Frieren:BAAALAAECgYIBgAAAA==.Fronblanc:BAAALAADCggIDgAAAA==.Frostdeath:BAAALAADCggIEAAAAA==.',Ft='Ftmeinar:BAAALAAECggIBgAAAA==.Ftmjail:BAAALAAECggIBgABLAAFFAYIBwAEAOgTAA==.',Fu='Fubosselet:BAACLAAFFIEMAAIHAAUI0yACBwDhAQAHAAUI0yACBwDhAQAsAAQKgSMAAgcACAiAJTQJAEYDAAcACAiAJTQJAEYDAAAA.',['Fî']='Fîrnia:BAAALAAECgcIEgAAAA==.',Ga='Galipya:BAAALAADCggICAAAAA==.Garof:BAAALAADCggIBwAAAA==.Gatol:BAABLAAECoEhAAMJAAgIFxYyMADxAQAJAAgIFxYyMADxAQAIAAQIcwl4bQCyAAAAAA==.Gatrebile:BAAALAADCggICAAAAA==.',Ge='Gery:BAACLAAFFIEHAAIIAAMI1h8dCQALAQAIAAMI1h8dCQALAQAsAAQKgSgAAggACAgDJdgEAE8DAAgACAgDJdgEAE8DAAAA.',Gi='Giclêtte:BAAALAADCggICAAAAA==.Gigondas:BAAALAADCgIIAgAAAA==.Giltoniel:BAAALAADCggIDwAAAA==.',Gl='Glamourrus:BAAALAAECgYIEAAAAA==.Glamourus:BAAALAAECgIIAgAAAA==.',Go='Gounâ:BAABLAAECoEaAAIbAAcI1RERRQDFAQAbAAcI1RERRQDFAQAAAA==.',Gr='Grigo:BAABLAAECoENAAIZAAcI9w+hWgCtAQAZAAcI9w+hWgCtAQAAAA==.Grimes:BAACLAAFFIEGAAIDAAIIshYHKQCMAAADAAIIshYHKQCMAAAsAAQKgSkAAgMACAg2HYccAIUCAAMACAg2HYccAIUCAAAA.',Gu='Guerrixe:BAAALAAECgUIDgAAAA==.',Gz='Gzena:BAAALAAECgYIDwAAAA==.',Ha='Hadrïan:BAACLAAFFIELAAIYAAMIfRbyDQAEAQAYAAMIfRbyDQAEAQAsAAQKgSQAAhgABwi0IZYxAIQCABgABwi0IZYxAIQCAAAA.Hannahé:BAAALAADCgUIBQABLAAECgcIIQAFAAIaAA==.Harmonix:BAAALAAECgUIBwAAAA==.',He='Healarité:BAAALAAECgYICgAAAA==.Helloimtoxic:BAAALAADCgMIAwAAAA==.',Hi='Hibiki:BAAALAAECgEIAQABLAAECgYIDwAGAAAAAA==.Hilata:BAAALAADCgcIFQAAAA==.',Ho='Honjani:BAABLAAECoEfAAICAAgIDxOPCwADAgACAAgIDxOPCwADAgAAAA==.',Hu='Huntinet:BAAALAAECggIDQAAAA==.',['Hö']='Höor:BAABLAAECoEjAAIOAAYIIRM+gwB3AQAOAAYIIRM+gwB3AQAAAA==.',['Hø']='Hønixya:BAAALAADCgYIDAAAAA==.',Il='Illidone:BAAALAADCgEIAQAAAA==.Illivoker:BAAALAAECgQIBAAAAA==.Illÿria:BAAALAADCggICQAAAA==.',In='Injectîon:BAAALAADCgcIEQAAAA==.',Ja='Jackerer:BAABLAAECoEVAAIOAAYIDBDipgAyAQAOAAYIDBDipgAyAQAAAA==.Jaïnaa:BAAALAADCgIIAgAAAA==.',Jh='Jhinwô:BAAALAADCgYIDgAAAA==.',Ji='Jinshakai:BAAALAAECgYIBgABLAAECgcIIQAVAEshAA==.Jinshi:BAAALAADCgUIBQAAAA==.',Jo='Jordanbrdela:BAAALAAECgYICwAAAA==.Jouke:BAAALAAECggICAAAAA==.',Ka='Kahté:BAAALAADCgUIBwAAAA==.Kalyysta:BAABLAAECoEwAAIDAAgIHBc9SADcAQADAAgIHBc9SADcAQAAAA==.Karoldue:BAAALAADCgIIAgABLAAECgcIMQAOAMUPAA==.Karolün:BAABLAAECoExAAIOAAcIxQ+EoAA+AQAOAAcIxQ+EoAA+AQAAAA==.Karthusirl:BAAALAAECggIAwAAAA==.Katastrofe:BAAALAAECgYIDwAAAA==.Kayané:BAAALAADCgQIBAAAAA==.Kaënaa:BAABLAAECoEbAAIEAAcIUguHWABSAQAEAAcIUguHWABSAQAAAA==.',Ke='Keloud:BAAALAADCggICAAAAA==.Kentinûs:BAAALAAECgUIBQABLAAECggIJAAYAAMjAA==.',Kh='Kharan:BAAALAADCggIFQAAAA==.Kharmé:BAACLAAFFIEHAAQcAAMIQBuoCAC9AAAdAAMI1w1FBwDFAAAcAAIIRiGoCAC9AAAHAAIIBRsAAAAAAAAsAAQKgR0AAxwACAjPILUHAMwCABwACAjPILUHAMwCAB0AAwgXDs4zAH8AAAAA.',Ki='Kiltara:BAACLAAFFIEIAAIJAAIIsAk9KgB8AAAJAAIIsAk9KgB8AAAsAAQKgS0AAwkACAg3GKwjADACAAkACAg3GKwjADACAAgAAwiOBzZ4AIEAAAAA.Kirikau:BAABLAAECoEeAAIeAAgIyhxKBACQAgAeAAgIyhxKBACQAgAAAA==.Kithara:BAAALAAECgIIAgAAAA==.',Kl='Klamehydias:BAAALAADCgcIBwAAAA==.Klobürste:BAAALAADCgMIAwAAAA==.Kléia:BAAALAAECgMIBgAAAA==.',Kn='Knakky:BAABLAAECoEiAAIYAAgIjBOCgQC3AQAYAAgIjBOCgQC3AQAAAA==.',Kr='Kromatix:BAAALAAECgEIAQAAAA==.',Ku='Kurdrbrew:BAAALAAECgcIEQAAAA==.Kurdrpprot:BAABLAAECoEkAAMFAAcImSPBCgCjAgAFAAYILibBCgCjAgAYAAEIGxQ+NAFFAAAAAA==.Kurdrvdh:BAACLAAFFIEUAAIfAAYI7xppAAAWAgAfAAYI7xppAAAWAgAsAAQKgSYAAx8ACAjyJbcBAF8DAB8ACAjyJbcBAF8DABIABghNDWmwADgBAAAA.Kurdrwprot:BAACLAAFFIEOAAILAAYIZhk9BACLAQALAAYIZhk9BACLAQAsAAQKgR4AAwsACAgIIhQIAAIDAAsACAgIIhQIAAIDAAEAAQjJDQAAAAAAAAAA.Kushymoon:BAAALAADCgYIBgAAAA==.',['Kä']='Kälÿ:BAAALAAECgYIEgABLAAECgcIEgAGAAAAAA==.',['Kø']='Køjirø:BAAALAAECgcIDAAAAA==.',La='Lafae:BAAALAADCgcICAAAAA==.Lagerthä:BAAALAADCgUIBQAAAA==.Lalle:BAAALAAECgcIBwAAAA==.Landï:BAAALAADCggIDgAAAA==.Lawthrall:BAACLAAFFIELAAIbAAMIORDVEQDmAAAbAAMIORDVEQDmAAAsAAQKgRwAAhsACAjpG7UfAIQCABsACAjpG7UfAIQCAAAA.Lawyna:BAAALAAECgYIEAAAAA==.',Le='Lecameleon:BAAALAAECgcIBwAAAA==.Ledarklord:BAABLAAECoEcAAMOAAgI2RQEWADaAQAOAAgI2RQEWADaAQAPAAMIKgZDmQBiAAAAAA==.Leducatrice:BAAALAAECgEIAQAAAA==.Leetha:BAABLAAECoEVAAIOAAYIVAXpywDgAAAOAAYIVAXpywDgAAAAAA==.Lexane:BAAALAAECgEIAQAAAA==.',Li='Littlewàr:BAAALAADCgIIAgAAAA==.',Lo='Lodae:BAABLAAECoErAAIRAAcIMxEoCgBzAQARAAcIMxEoCgBzAQAAAA==.Lorendhriel:BAAALAADCgcIBwAAAA==.Loress:BAAALAADCggIEAAAAA==.',Lu='Lucilia:BAAALAADCgcIDQABLAAFFAIIBwASAK4cAA==.Luin:BAAALAAECgYIDQAAAA==.',['Lé']='Léahwar:BAAALAAECgYIEgAAAA==.',['Lÿ']='Lÿserg:BAAALAAECgEIAQABLAAECggILQAIABkbAA==.',Ma='Maagdo:BAAALAADCggIEAAAAA==.Maglor:BAAALAAECgMIBgAAAA==.Makiri:BAAALAADCgcIFAAAAA==.Malgarath:BAABLAAECoEdAAISAAcIJw/sgQCUAQASAAcIJw/sgQCUAQAAAA==.Malkingrim:BAAALAAECgIIAgAAAA==.Maëstriaa:BAAALAADCgcIDQAAAA==.',Me='Meko:BAAALAAECgIIAgABLAAECggILQAIABkbAA==.Melïa:BAAALAADCggICAABLAAECggILQAIABkbAA==.',Mi='Miaoying:BAAALAADCggIDwAAAA==.Mimimatix:BAAALAADCggIDwABLAAECggIMAADABwXAA==.Minachan:BAAALAAECgYIBgAAAA==.Miniflash:BAABLAAECoEnAAIOAAgIFh0TNwBAAgAOAAgIFh0TNwBAAgAAAA==.Miniobade:BAAALAAECgIIAgAAAA==.Miokama:BAAALAADCgcIBwAAAA==.Mitsou:BAAALAAECgMIAwAAAA==.',Mo='Mobii:BAAALAAECgYIBgAAAQ==.Monsterkills:BAAALAADCgYIBgABLAAECggIJQAOAIcbAA==.Moohmoohstar:BAAALAADCggICAAAAA==.Moonlaw:BAAALAADCgYIBgAAAA==.Morthus:BAAALAAECgUIBgAAAA==.Moyzi:BAAALAAECgcIEQABLAAECggIGAAEACALAA==.',Mw='Mwak:BAAALAAECgIIAgABLAAECggIIAAgAJwcAA==.',My='Mystralle:BAABLAAECoEbAAMUAAgI+AiPRQAzAQAUAAcI6gaPRQAzAQAgAAYI/QiHoQAJAQAAAA==.Mystíc:BAACLAAFFIEKAAIVAAMIKxg1BgD6AAAVAAMIKxg1BgD6AAAsAAQKgRsAAhUACAj3H5ANAKICABUACAj3H5ANAKICAAAA.',['Mö']='Mölly:BAAALAADCggICAAAAA==.',Na='Nagatip:BAABLAAECoEbAAMcAAcIBSDrDABvAgAcAAcIBSDrDABvAgAHAAIIqhJuKwF3AAAAAA==.Nainguibus:BAAALAAECgYIEQAAAA==.Nakou:BAABLAAECoEVAAMDAAYIghaWZwCFAQADAAYIghaWZwCFAQAbAAYIkhDWYwBbAQAAAA==.Narcisska:BAAALAADCgUIBQAAAA==.Navré:BAABLAAECoEsAAMfAAgIuySWBAASAwAfAAgIBSSWBAASAwASAAgI0SKtEgAQAwAAAA==.Naïni:BAAALAAECgYIBgAAAA==.',Ne='Needhell:BAAALAADCggIEAAAAA==.Nelphis:BAAALAAECgYIEgAAAA==.Nerfi:BAAALAADCgcICAAAAA==.',Ni='Nikkàu:BAAALAAECgEIAQABLAAFFAMICQAKAPEYAA==.Nirouthe:BAAALAAECgIIAgAAAA==.',No='Nouilleske:BAAALAAECgQIBQAAAA==.Noá:BAAALAAECggIDgAAAA==.',Ny='Nyobë:BAAALAADCggICAAAAA==.Nyü:BAABLAAECoEbAAISAAcISwWSwQASAQASAAcISwWSwQASAQAAAA==.',['Nä']='Nälah:BAAALAAECgYIDAAAAA==.',['Né']='Nébuleuse:BAAALAAECgYIEQAAAA==.Néfertarï:BAAALAADCggIGQAAAA==.',['Nî']='Nîkkâu:BAAALAAECgcIDQABLAAFFAMICQAKAPEYAA==.',['Nó']='Nóra:BAAALAADCggICAAAAA==.',['Nö']='Nöa:BAAALAADCggIDwAAAA==.Nöly:BAAALAAECgQIDQAAAA==.',['Nø']='Nøa:BAABLAAECoETAAIgAAgI9AxTcwCNAQAgAAgI9AxTcwCNAQAAAA==.',Ob='Obade:BAABLAAECoEYAAIOAAcISA4WowA5AQAOAAcISA4WowA5AQAAAA==.',Oc='Occidet:BAAALAAECgEIAQAAAA==.',Or='Orcky:BAAALAAECgIIAgAAAA==.',Ou='Ourobouros:BAABLAAECoEkAAQhAAgInQ/5FAC0AQAhAAgInQ/5FAC0AQAiAAcI0xIiKgCsAQAjAAIIYhZfEwB1AAAAAA==.',Ov='Overman:BAAALAAECgYIDAAAAA==.',Pa='Pandachad:BAAALAADCgYIBgAAAA==.',Pi='Pikpus:BAAALAADCgcIBwAAAA==.',Po='Popotin:BAAALAADCgcIBwABLAAECggIMAADABwXAA==.Portepeste:BAACLAAFFIEJAAMZAAMINgodHgDMAAAZAAMIsAcdHgDMAAAkAAII1gwVAwCXAAAsAAQKgSMAAyQACAieHFsEAJoCACQACAieHFsEAJoCABkABAjTD1ibAPkAAAAA.Pourpre:BAAALAAECgcIBwABLAAFFAIIAgAGAAAAAQ==.',Pr='Prêtro:BAAALAADCggICwAAAA==.',Ps='Psyover:BAAALAAECgEIAQAAAA==.',Pt='Ptiløuis:BAAALAADCgcIBwAAAA==.',Ra='Ralgamaziel:BAABLAAECoEdAAIDAAgI3grrhwA2AQADAAgI3grrhwA2AQAAAA==.Ranza:BAAALAAECgQIDAAAAA==.',Ro='Robïn:BAAALAADCgcIBwABLAAECggIHQAZAK8UAA==.Rofellos:BAAALAAECgEIAQAAAA==.Rokkofea:BAAALAAECgIIAgABLAAECggIKAAVAAQjAA==.Roudarde:BAAALAADCgYIBwAAAA==.Roxis:BAABLAAECoEpAAMIAAgIsCCtDQDlAgAIAAgITiCtDQDlAgAKAAEIWBrcOwBOAAAAAA==.',['Rà']='Ràvi:BAAALAADCggICAAAAA==.',['Râ']='Râgn:BAAALAADCgMIAgAAAA==.',['Rø']='Røudarde:BAAALAAECgEIAQAAAA==.',Sa='Saguira:BAAALAADCgIIAgAAAA==.Sandokai:BAABLAAECoEsAAIOAAgIahbdSgD+AQAOAAgIahbdSgD+AQAAAA==.Sanpaz:BAAALAAECgEIAQAAAA==.Sarevok:BAAALAAECgYICgAAAA==.Saurctox:BAAALAADCgQIBAAAAA==.',Sc='Scorpilia:BAAALAAECgEIAQAAAA==.Scorpinnia:BAAALAAECgYIDwAAAA==.',Se='Selyna:BAAALAAECgEIAQAAAA==.Sephylol:BAACLAAFFIEMAAILAAMISRTVCQDRAAALAAMISRTVCQDRAAAsAAQKgSQAAwsACAh5Ha4UAGECAAsACAh5Ha4UAGECAAEABwjREilRAMYBAAAA.Septantecinq:BAAALAAECgEIAQAAAA==.Septienna:BAACLAAFFIEJAAITAAMICRQDCgDrAAATAAMICRQDCgDrAAAsAAQKgSIAAhMACAhOHxALAKkCABMACAhOHxALAKkCAAAA.',Sh='Shadowkyo:BAAALAADCgQIBAAAAA==.Shamanar:BAABLAAECoEVAAIDAAYILhvgTwDFAQADAAYILhvgTwDFAQAAAA==.Sheguéy:BAAALAADCgMIAwAAAA==.Shokicks:BAACLAAFFIEKAAMgAAQI2BfHEQBOAQAgAAQI2BfHEQBOAQARAAEItxDyCABOAAAsAAQKgS0AAyAACAiWJU8NACMDACAACAiWJU8NACMDABEAAghfH1cSAKAAAAAA.Shushu:BAAALAAECgMIAwAAAA==.Shyvana:BAAALAADCgEIAQAAAA==.Shâvow:BAAALAADCgcIDQAAAA==.Shéguey:BAAALAADCgYIFQAAAA==.Shéguèy:BAAALAADCgUIBQAAAA==.Shéguéy:BAAALAADCgYIBgAAAA==.',Si='Siammolow:BAAALAAECgMIAwAAAA==.Sifon:BAAALAAECgYIDAAAAA==.Silexes:BAAALAAECgYICQABLAAECggIHwAQAB0eAA==.Silthys:BAAALAAECgYIDwAAAA==.',Sl='Slevin:BAAALAAFFAIIAgAAAA==.',Sn='Snooplol:BAAALAADCgEIAQAAAA==.',So='Sokhar:BAAALAAECgYIEgAAAA==.Sonum:BAABLAAECoEfAAIDAAgIhw3ncgBnAQADAAgIhw3ncgBnAQAAAA==.Sosweet:BAAALAAFFAIIAgAAAA==.',St='Staydead:BAAALAAECgMIBwAAAA==.Stayfocus:BAAALAADCggICAAAAA==.Stayføcus:BAAALAADCggICQAAAA==.Staypal:BAAALAADCgQIBAAAAA==.Stayrosser:BAAALAADCggICQAAAA==.Staýfocus:BAAALAAECgIIAgAAAA==.Stepmom:BAAALAADCgUIBQAAAA==.Stepmommy:BAABLAAECoEeAAIDAAgIEiDjEwC5AgADAAgIEiDjEwC5AgAAAA==.Stepson:BAABLAAECoEWAAMXAAgIGBQjIQD6AQAXAAgIpBIjIQD6AQAWAAcIYRAjGgCaAQAAAA==.',Su='Subttle:BAABLAAECoEeAAIJAAcIwyJ+EAC1AgAJAAcIwyJ+EAC1AgAAAA==.Succube:BAAALAAECgYIEgAAAA==.Suzette:BAAALAADCggICAABLAAECgcIIQAFAAIaAA==.',Sy='Sykae:BAAALAADCgcIDQAAAA==.Sylianhã:BAAALAADCgYICwAAAA==.',Sz='Sz:BAAALAAECgcIAQAAAA==.Szsszssz:BAAALAAECgMIBgAAAA==.',Ta='Takenudrood:BAAALAAECgYIDgAAAA==.Taoquan:BAABLAAECoEZAAIlAAcIqwu3JgA5AQAlAAcIqwu3JgA5AQAAAA==.',Th='Thalÿa:BAAALAADCggICAAAAA==.Theana:BAAALAAECgMIBQAAAA==.Thechassou:BAAALAADCgcIDAAAAA==.Thelaruuk:BAAALAADCggICgAAAA==.Thesys:BAAALAAECgUICwAAAA==.Thetita:BAAALAADCggICAAAAA==.Theyos:BAAALAADCgcIBwAAAA==.Thi:BAAALAAECgYICwAAAA==.Thumbelina:BAAALAADCgIIAgAAAA==.Thélos:BAAALAADCgcIBwAAAA==.',Ti='Tileas:BAAALAADCgQIBAAAAA==.',To='Tombombadil:BAAALAAECgMIAwAAAA==.Tonouille:BAAALAAECgYIEQAAAA==.Totaïm:BAABLAAECoErAAIbAAgIDxojKgBFAgAbAAgIDxojKgBFAgAAAA==.Tovah:BAAALAAFFAIIAgAAAQ==.Toxiquorc:BAABLAAECoElAAIOAAgIhxv2NQBEAgAOAAgIhxv2NQBEAgAAAA==.',Ty='Tyrius:BAAALAADCggIEgAAAA==.',['Tü']='Tück:BAAALAADCgcIEQAAAA==.',Va='Valambre:BAAALAAECgYIBgAAAA==.',Ve='Vertîgo:BAAALAAECgMIAwABLAAECggIMAADABwXAA==.',Vi='Vieilhomm:BAAALAADCggIDgAAAA==.Vilanna:BAAALAAECgcIDQAAAA==.Vincente:BAAALAAECgYIDQAAAA==.Vitalia:BAAALAADCggICAAAAA==.',Vo='Volcâne:BAAALAAECgIIAwAAAA==.Vorazun:BAAALAAECgEIAQAAAA==.Voxstar:BAAALAADCgUIBQAAAA==.',Vr='Vrtd:BAAALAADCgUIBQAAAA==.',['Vé']='Vésuve:BAEALAAECgYIDgABLAAECggIJgAEAN8eAA==.',Wi='Wickeb:BAAALAAECgMIAwAAAA==.Winso:BAAALAADCggIEwAAAA==.Winëss:BAAALAADCggICAAAAA==.Witargu:BAAALAADCgYIBgAAAA==.',Wo='Worëy:BAABLAAECoEYAAIHAAYI2R+FXgAGAgAHAAYI2R+FXgAGAgAAAA==.',Ws='Wsa:BAAALAAECggICAABLAAECggIJAAHAIclAA==.',Wy='Wyralith:BAAALAADCgYIBgAAAA==.',['Wê']='Wêllàn:BAAALAAECgQIBAABLAAECggIGgARABwjAA==.',Xo='Xorel:BAAALAADCggICAAAAA==.',Xz='Xzyllaly:BAAALAAECgYIEQAAAA==.',Yb='Ybor:BAAALAAECgMIBAAAAA==.',Yi='Yiu:BAAALAADCggICAAAAA==.',Yr='Yrveg:BAAALAAECgIIAgAAAA==.',['Yû']='Yûnted:BAAALAADCgUIBQAAAA==.',Za='Zacclamation:BAAALAAECgIIAgAAAA==.Zalcoolique:BAAALAADCgMIAwABLAAECgIIAgAGAAAAAA==.',Ze='Zexceed:BAAALAADCggICAAAAA==.',Zg='Zgbell:BAAALAADCggILwAAAA==.',Zi='Zigzagta:BAAALAAECgIIAwAAAA==.',Zu='Zultox:BAAALAAECgQIBAAAAA==.',['Él']='Éllisa:BAAALAADCggICAAAAA==.',['Ða']='Ðaëlys:BAAALAADCggICAAAAA==.',['Ðæ']='Ðæströ:BAAALAAECggICAAAAA==.',['Ñy']='Ñyx:BAAALAADCggIGAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end