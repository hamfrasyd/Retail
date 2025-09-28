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
 local lookup = {'Evoker-Devastation','DeathKnight-Frost','Warlock-Destruction','Mage-Arcane','Hunter-Survival','DemonHunter-Havoc','Unknown-Unknown','Warlock-Demonology','Monk-Brewmaster','Warrior-Fury','Mage-Frost','Hunter-BeastMastery','Monk-Mistweaver','Mage-Fire','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Monk-Windwalker','Priest-Shadow','Priest-Discipline','Druid-Balance','Paladin-Protection','Warrior-Protection','Warlock-Affliction','Paladin-Retribution','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Vengeance','Druid-Feral','Shaman-Enhancement','Priest-Holy','Warrior-Arms','Druid-Restoration','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Druid-Guardian','Hunter-Marksmanship','DeathKnight-Blood',}; local provider = {region='EU',realm='Ravenholdt',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ae='Aeonthe:BAABLAAECoEgAAIBAAgIXRUmHgAIAgABAAgIXRUmHgAIAgAAAA==.Aetheria:BAAALAADCgYIBgAAAA==.',Ai='Aizen:BAAALAADCgEIAQABLAAECggIGwACAKQVAA==.Aizendk:BAABLAAECoEbAAICAAgIpBXzXgAAAgACAAgIpBXzXgAAAgAAAA==.Aizenstab:BAAALAADCgcIBwABLAAECggIGwACAKQVAA==.',Al='Alrisaera:BAABLAAECoEgAAIDAAgINRU2OwAWAgADAAgINRU2OwAWAgAAAA==.Alwaysborne:BAAALAADCgYIBgAAAA==.Alyssá:BAACLAAFFIEIAAIEAAMIAxkzFwD5AAAEAAMIAxkzFwD5AAAsAAQKgSUAAgQACAh5ItcSAP8CAAQACAh5ItcSAP8CAAAA.Alzu:BAABLAAECoEWAAIFAAcIYh/zBABsAgAFAAcIYh/zBABsAgAAAA==.',Am='Ambrotor:BAABLAAECoEbAAIGAAgI0hCGYADUAQAGAAgI0hCGYADUAQAAAA==.',An='Animo:BAAALAADCggICAABLAAECgYIBgAHAAAAAA==.Annabéth:BAAALAAECgMIBAAAAA==.Anubarrak:BAABLAAECoEbAAMIAAgIrRGJLgCRAQAIAAYI7RGJLgCRAQADAAQI2Q8FngDfAAAAAA==.',Ar='Arasme:BAAALAAECgIIBAAAAA==.Arleigh:BAEALAAECggIDgABLAAFFAUIEQAJAKsLAA==.Artemás:BAABLAAECoEZAAICAAgIBAowogB9AQACAAgIBAowogB9AQAAAA==.Arthrasz:BAAALAAECgYIEgABLAAFFAQICQAKACEXAA==.Aruál:BAACLAAFFIERAAMLAAQIXhUQBADiAAAEAAQI3g9eEABFAQALAAMIJxUQBADiAAAsAAQKgT0AAwsACAjDI9AHAPwCAAQACAgaIY0RAAgDAAsACAhfI9AHAPwCAAAA.Aruáll:BAACLAAFFIEIAAMEAAIIkRvtIwCwAAAEAAIIkRvtIwCwAAALAAIIMQtdDwCGAAAsAAQKgSMAAwQACAhuIskMACQDAAQACAgvIskMACQDAAsABghTHeAgAOsBAAEsAAUUBAgRAAsAXhUA.',As='Ashe:BAABLAAECoEfAAIMAAgIxCEWGADOAgAMAAgIxCEWGADOAgAAAA==.Ashynn:BAAALAADCggICAAAAA==.',At='Atadeekay:BAAALAAECgEIAgAAAA==.Atahu:BAAALAAECgEIAgABLAAECgEIAgAHAAAAAA==.',Au='Aube:BAAALAADCgYIBgAAAA==.Auragen:BAABLAAECoEeAAIEAAgIfx6VJQCbAgAEAAgIfx6VJQCbAgAAAA==.Aurah:BAAALAADCggIEAABLAAECggIHwAMAMQhAA==.',Av='Avelîna:BAAALAAECgYICwAAAA==.',Az='Azalen:BAAALAADCggIFwABLAAECgYIFQANAMQNAA==.Azone:BAABLAAECoEgAAIKAAgIUyMTCgA4AwAKAAgIUyMTCgA4AwAAAA==.',['Aû']='Aûtumn:BAAALAAECgIIAgAAAA==.',Ba='Baladans:BAAALAADCgcIBwAAAA==.Balgara:BAAALAADCggICAAAAA==.Balgho:BAAALAAECgcICQAAAA==.Balgorok:BAAALAADCgUIBQAAAA==.Barry:BAAALAAECgUIBAAAAA==.',Be='Beelzeebub:BAAALAAECgIIAgAAAA==.Beleth:BAAALAAECgYIBgABLAAECggIGgAMALEcAA==.',Bi='Bighunterman:BAAALAAECggICAABLAAFFAYIGwAKAPkcAA==.Bigpow:BAAALAADCggIDwAAAA==.Billydoll:BAAALAAECgcIEAAAAA==.Bishop:BAAALAAECgEIAgABLAAECgEIAgAHAAAAAA==.',Bl='Bladyos:BAABLAAECoEoAAIOAAgIqhoNAwCGAgAOAAgIqhoNAwCGAgAAAA==.Blm:BAAALAAECgcIBwAAAA==.',Bo='Bodgers:BAAALAAECgQIBQAAAA==.Bonkers:BAAALAAECggIBwAAAA==.Bothadis:BAABLAAECoEbAAICAAcImyGNQABPAgACAAcImyGNQABPAgAAAA==.',Bu='Bumbulerini:BAAALAAECgMIBQAAAA==.Bumbulio:BAABLAAECoEXAAMPAAgIdxMaQQDMAQAPAAcIwRIaQQDMAQAQAAUISg4jpADwAAAAAA==.Bumbulis:BAACLAAFFIEWAAIRAAYIOR11AQAnAgARAAYIOR11AQAnAgAsAAQKgTAAAhEACAheIu4DABIDABEACAheIu4DABIDAAAA.Burdoc:BAABLAAECoEUAAMNAAcIDgUFLwDtAAANAAcIDgUFLwDtAAASAAYIHwUzPgDmAAAAAA==.',Bw='Bwarrior:BAAALAAECgMIAwAAAA==.',Ca='Caelen:BAAALAADCggICAAAAA==.Caeven:BAACLAAFFIEbAAITAAYIGyEeAQBzAgATAAYIGyEeAQBzAgAsAAQKgTAAAxMACAiFJu4AAIoDABMACAiFJu4AAIoDABQAAQi9C4MwADUAAAAA.Cazati:BAAALAADCggICAAAAA==.',Ce='Cephi:BAAALAAECggICgAAAA==.',Ch='Chloè:BAAALAAECgMIBAAAAA==.Chonkylee:BAABLAAECoEnAAISAAgIYxtbEAB2AgASAAgIYxtbEAB2AgAAAA==.Chrissi:BAAALAADCggIGAAAAA==.',Ci='Cibriks:BAAALAAECgQIBgABLAAFFAYIGwAKAPkcAA==.Cinderhood:BAABLAAECoEfAAIVAAcIKwlDSwBIAQAVAAcIKwlDSwBIAQAAAA==.',Cl='Cloudie:BAAALAAECgYIBgAAAA==.',Co='Connelia:BAAALAAECgYIDAAAAA==.Coom:BAAALAAECgMIAwAAAA==.Cooney:BAAALAAFFAIIAgAAAA==.Cozystrasza:BAABLAAECoEkAAIBAAgIjB77CwDRAgABAAgIjB77CwDRAgAAAA==.',Cr='Creedzable:BAACLAAFFIETAAIKAAUIMSaNAgA5AgAKAAUIMSaNAgA5AgAsAAQKgRcAAgoACAgBJi8SAPsCAAoACAgBJi8SAPsCAAAA.',Cy='Cybershock:BAAALAAECgMIBgAAAA==.Cyne:BAACLAAFFIERAAIWAAYInR61AAAnAgAWAAYInR61AAAnAgAsAAQKgRgAAhYACAhNJRwDAEQDABYACAhNJRwDAEQDAAAA.Cyrano:BAAALAAECggIEAABLAAFFAYIEQAWAJ0eAA==.',['Cé']='Céris:BAAALAAECgQIBgAAAA==.',Da='Dajaf:BAABLAAFFIEOAAIXAAYI8SD+AABcAgAXAAYI8SD+AABcAgABLAAFFAYIBwAJAOskAA==.Dalrell:BAAALAADCgYIBgABLAAECgcIFAAYABcXAA==.Dammerflinn:BAABLAAECoEfAAMRAAgIZg9MJQC4AQARAAgIZg9MJQC4AQAZAAQIZwpG8gDGAAAAAA==.Danariël:BAAALAAECgIIAgAAAA==.Darknes:BAABLAAECoEXAAIUAAgIghVeCAD7AQAUAAgIghVeCAD7AQAAAA==.Darwin:BAAALAAECgUIBQABLAAFFAYIFAAHAAAAAQ==.Daríon:BAAALAADCggIFAAAAA==.',De='Deadtibbs:BAACLAAFFIEIAAICAAMI7Rd+GQDbAAACAAMI7Rd+GQDbAAAsAAQKgRsAAgIACAg2ILEZAOoCAAIACAg2ILEZAOoCAAAA.Deathwalksxd:BAAALAADCgUIBAAAAA==.Demonlove:BAAALAAECggIEwAAAA==.Demonrise:BAAALAADCgMIAgAAAA==.Demontard:BAAALAAECggIDwABLAAFFAYIGwAKAPkcAA==.Demontay:BAAALAAECgEIAQABLAAECgcIDQAHAAAAAA==.Desica:BAAALAADCgcIDQAAAA==.Destructiv:BAABLAAECoEfAAICAAgIrguvjgCfAQACAAgIrguvjgCfAQAAAA==.',Di='Dirahlia:BAAALAADCggICAAAAA==.Diviniste:BAAALAADCgUIBQAAAA==.',Do='Dotzilla:BAABLAAECoEYAAMDAAYIiBhaVQC1AQADAAYIiBhaVQC1AQAIAAIIoBGobwB3AAAAAA==.Doxxadruid:BAAALAAECggIEAAAAA==.Doxxapapa:BAAALAAECgcIBgAAAA==.',Dr='Dracdeeznuts:BAAALAADCgcIBwAAAA==.Dracthel:BAAALAAECgIIAgAAAA==.',['Dë']='Dëvo:BAAALAAECgMIAwAAAA==.',['Dø']='Dødstrolden:BAAALAAECggIDwAAAA==.',El='Electron:BAAALAAECgIIAQAAAA==.Elemefayoh:BAAALAAECgYIBgAAAA==.Eliaskw:BAABLAAECoEUAAIEAAgIxRpVLgBwAgAEAAgIxRpVLgBwAgAAAA==.Elmoboom:BAAALAAECgcIDgAAAA==.Elnea:BAABLAAECoEZAAIMAAgItg+2ZwCnAQAMAAgItg+2ZwCnAQAAAA==.Elp:BAAALAAECggIDAABLAAFFAYIGAAEABgiAA==.Elulin:BAAALAAECgIIAgABLAAFFAYIGwATABshAA==.',En='Enzou:BAABLAAECoEfAAQBAAgI7B+yDgCvAgABAAgIwR6yDgCvAgAaAAcIKB0/BABfAgAbAAIINBcKLwB9AAAAAA==.',Ep='Epinon:BAABLAAECoEnAAITAAgIhxtyGACNAgATAAgIhxtyGACNAgAAAA==.Epÿon:BAAALAAFFAMIAwAAAA==.',Er='Erok:BAAALAADCggICAAAAA==.',Ev='Eversonn:BAAALAAECggIBQAAAA==.Evië:BAAALAADCgQIBAAAAA==.',Ez='Ezerak:BAAALAAECgYIDgAAAA==.',Fa='Faelu:BAAALAADCggICAAAAA==.',Fe='Ferlain:BAAALAADCggIFQAAAA==.',Fi='Fikisulik:BAAALAAECgYIDAAAAA==.',Fl='Flap:BAABLAAECoEXAAIcAAcIzSEyDABnAgAcAAcIzSEyDABnAgAAAA==.',Fo='Follie:BAACLAAFFIEWAAIdAAYImx1RAABZAgAdAAYImx1RAABZAgAsAAQKgTAAAh0ACAihJggAAKADAB0ACAihJggAAKADAAAA.Foxife:BAAALAADCgcIBwAAAA==.',Fu='Fulakazam:BAABLAAECoEcAAIEAAgIvBgxNgBNAgAEAAgIvBgxNgBNAgAAAA==.Fulburst:BAAALAAFFAEIAQAAAA==.Furii:BAABLAAECoEcAAIeAAgIohmpBgCHAgAeAAgIohmpBgCHAgAAAA==.',['Fí']='Fíré:BAAALAADCgcICAAAAA==.',Ga='Gadren:BAABLAAECoEZAAMfAAgIzxrMHABsAgAfAAgIzxrMHABsAgATAAMI6A3+bACpAAAAAA==.Galona:BAAALAADCggIEAAAAA==.Gandélf:BAAALAAECgEIAgABLAAECgIIAgAHAAAAAA==.Gangsta:BAAALAAECgUIBQAAAA==.',Ge='Geklock:BAAALAADCgYIDAAAAA==.',Gh='Ghorbash:BAAALAAECggICgAAAA==.Ghostrabbit:BAABLAAECoEUAAICAAcIvAxmnACHAQACAAcIvAxmnACHAQAAAA==.Ghostrâbbît:BAAALAADCgYIBgAAAA==.',Gi='Gintama:BAAALAAECgMIBwAAAA==.',Gn='Gnomie:BAACLAAFFIEHAAIJAAUI6yR/AQAsAgAJAAUI6yR/AQAsAgAsAAQKgSQAAgkACAg7JoAAAIYDAAkACAg7JoAAAIYDAAAA.Gnomielash:BAAALAAECggIEgABLAAFFAYIBwAJAOskAA==.Gnomiemagus:BAAALAADCgcIBwABLAAFFAYIBwAJAOskAA==.Gnomiepal:BAABLAAFFIEIAAIWAAUIYBJhAgBwAQAWAAUIYBJhAgBwAQABLAAFFAYIBwAJAOskAA==.Gnomietwo:BAABLAAFFIEJAAIJAAQIJxP2BQAaAQAJAAQIJxP2BQAaAQABLAAFFAYIBwAJAOskAA==.',Go='Gobstoppers:BAABLAAECoEUAAIMAAcI2hUWVQDXAQAMAAcI2hUWVQDXAQAAAA==.Goonette:BAAALAAECgIIAgAAAA==.Gordían:BAAALAAFFAIIAgAAAA==.',Gr='Gramm:BAABLAAECoEYAAIKAAcImQwSYQCKAQAKAAcImQwSYQCKAQAAAA==.Grimblade:BAAALAAECgYIBgAAAA==.Gristonius:BAABLAAECoEcAAQDAAgICSAEFADwAgADAAgICSAEFADwAgAIAAEIzRH0fABGAAAYAAEIEgr+PAA0AAAAAA==.Gromthrek:BAAALAAECgMIAwABLAAECgYIBwAHAAAAAA==.',Gu='Guinan:BAABLAAECoEdAAIfAAcIfhJtTQB2AQAfAAcIfhJtTQB2AQAAAA==.Gumma:BAAALAADCgYIAwAAAA==.Guyy:BAACLAAFFIEbAAQKAAYI+RxhAgBCAgAKAAYI5xxhAgBCAgAXAAUIzBOyAwCbAQAgAAEI9B9yBQBgAAAsAAQKgTAABAoACAjlJYEGAFQDAAoACAjlJIEGAFQDABcACAhoImcFACgDACAABQiJJAMLAAgCAAAA.',Ha='Haeger:BAAALAAECggICAAAAA==.Hamsterxd:BAAALAAECgYIBgAAAA==.Hamsterxp:BAAALAAECgYIAQAAAA==.Harkenaegis:BAAALAAECgYIBgAAAA==.Harlot:BAAALAAECgMIAwAAAA==.',He='Healsbadman:BAAALAAECgYICAAAAA==.Helline:BAAALAADCggIDAAAAA==.',Ho='Holyhéll:BAAALAAECgMIBgAAAA==.Hoolyz:BAAALAAECggIEQAAAA==.Hotwings:BAAALAADCggIDQABLAAFFAIIBgAhAMwaAA==.Houdoe:BAAALAADCggIEAAAAA==.Hounde:BAAALAADCgQIBAAAAA==.',Hu='Hunttrix:BAAALAAECgEIAgAAAA==.',Hy='Hydrate:BAAALAADCgcIBgABLAAECggIFwACAOISAA==.',Ic='Icarus:BAAALAAECggIDwAAAA==.',Ik='Ikachu:BAACLAAFFIEHAAIJAAIIYRYrDQCHAAAJAAIIYRYrDQCHAAAsAAQKgRgAAgkACAiaHekMAFoCAAkACAiaHekMAFoCAAAA.',Im='Imtheflash:BAAALAAECgMIBgAAAA==.',In='Indigo:BAACLAAFFIEFAAIRAAMInwajCwDOAAARAAMInwajCwDOAAAsAAQKgR0AAhEACAhfHjMIAMsCABEACAhfHjMIAMsCAAAA.Indris:BAABLAAECoEeAAIZAAcIPiUXGgDtAgAZAAcIPiUXGgDtAgAAAA==.Insaneshamz:BAAALAAECgYIDAAAAA==.',Ir='Iridaxys:BAAALAADCggICAAAAA==.Ironsight:BAABLAAECoEnAAIMAAgIqBzfKwBjAgAMAAgIqBzfKwBjAgAAAA==.',Is='Isleen:BAACLAAFFIEJAAIhAAQIpg87BwAjAQAhAAQIpg87BwAjAQAsAAQKgSAAAiEACAigFjQqAAYCACEACAigFjQqAAYCAAAA.',It='Ittygritty:BAAALAADCgIIAgAAAA==.',Ja='Jack:BAABLAAECoEpAAMiAAgIix0+BwCvAgAiAAgIix0+BwCvAgAjAAcIVxXaCADWAQAAAA==.Jaola:BAAALAADCggICAAAAA==.Jayee:BAACLAAFFIEXAAIDAAYIwiHnAgBaAgADAAYIwiHnAgBaAgAsAAQKgRsABAMACAjTIUkQAAkDAAMACAguIUkQAAkDAAgABQiGJSonALcBABgAAggyIPAiALAAAAAA.',Je='Jeffdk:BAAALAAECggIDwAAAA==.',Jo='Joemomma:BAAALAAECgcIDQABLAAECggIFgAFAGIfAA==.Joheltro:BAAALAADCggIFwAAAA==.',Ju='Jumlip:BAAALAAECggICAAAAA==.Jumpy:BAAALAAECggIDgAAAA==.',Jw='Jweddy:BAABLAAECoEkAAMVAAgIaCDjDgDUAgAVAAgIaCDjDgDUAgAdAAIIsgiNOABbAAAAAA==.',['Jé']='Jéddy:BAAALAADCggICAAAAA==.',Ka='Kakirage:BAABLAAECoEUAAIKAAcIVhKOTwDAAQAKAAcIVhKOTwDAAQAAAA==.Kaktperekdk:BAAALAAECgQIBwAAAA==.Kallrell:BAAALAADCggICAABLAAECgcIFAAYABcXAA==.Kalrell:BAAALAAECgYIDgABLAAECgcIFAAYABcXAA==.Kann:BAACLAAFFIEKAAIZAAQIlQy/CAA7AQAZAAQIlQy/CAA7AQAsAAQKgTIAAhkACAiUIKYdANkCABkACAiUIKYdANkCAAAA.Kannada:BAABLAAECoEfAAIVAAgIrxekHwAwAgAVAAgIrxekHwAwAgABLAAFFAQICgAZAJUMAA==.Karatiewater:BAAALAAECgYICQABLAAECggIJwAMAKgcAA==.Karlakh:BAAALAAECgQIBAAAAA==.Kasida:BAABLAAECoEbAAITAAgIFAp+PgCbAQATAAgIFAp+PgCbAQAAAA==.Katsùki:BAAALAAECgcIDgABLAAECggIGQAGAD4gAA==.Katsúki:BAABLAAECoEZAAIGAAgIPiBnFwDvAgAGAAgIPiBnFwDvAgAAAA==.',Ke='Keiron:BAACLAAFFIEYAAIEAAYIGCLAAQBjAgAEAAYIGCLAAQBjAgAsAAQKgTAAAgQACAh0JLAHAEcDAAQACAh0JLAHAEcDAAAA.Kelanai:BAAALAADCggIEAAAAA==.Kelhben:BAABLAAECoEWAAIIAAgIERnTEABXAgAIAAgIERnTEABXAgAAAA==.Kelrel:BAAALAADCggICgABLAAECgcIFAAYABcXAA==.Kenoo:BAAALAAECgYICQAAAA==.',Ki='Kijo:BAAALAAECgYIBgAAAA==.Kirschsaft:BAAALAADCgcIBwAAAA==.',Kn='Knit:BAAALAAECgYIDQAAAA==.',Ko='Kotlin:BAACLAAFFIEGAAIhAAIIzBo7FACrAAAhAAIIzBo7FACrAAAsAAQKgSMAAyEACAgiHZ0iAC4CACEACAgiHZ0iAC4CABUABgjfGlYwAMkBAAAA.Kovú:BAAALAAECgMIAwAAAA==.',Kr='Kreppy:BAABLAAECoEkAAIhAAgIrB7PDgC9AgAhAAgIrB7PDgC9AgAAAA==.Krieger:BAAALAAECggIBQABLAAECggIEwAHAAAAAA==.Krimmyr:BAABLAAECoEnAAIBAAgICCRTAwBPAwABAAgICCRTAwBPAwAAAA==.Krimotar:BAAALAADCgcIBwAAAA==.Krippi:BAABLAAECoElAAINAAgIOhlrDgBUAgANAAgIOhlrDgBUAgAAAA==.Krippy:BAAALAADCgcIBwABLAAECggIJQANADoZAA==.',Ku='Kullervo:BAABLAAECoEbAAIkAAcIkRfZHAAYAgAkAAcIkRfZHAAYAgAAAA==.Kux:BAACLAAFFIEaAAMfAAYIchp1AQArAgAfAAYIchp1AQArAgATAAEIVQnWIABLAAAsAAQKgTAAAh8ACAgvIZ0LAPYCAB8ACAgvIZ0LAPYCAAAA.',La='Laerin:BAAALAADCgcIBwABLAAECggIDgAHAAAAAA==.Lakshmi:BAAALAAECgYIEAAAAA==.Lanaska:BAAALAAECgEIAQABLAAECgIIAgAHAAAAAA==.Larenta:BAAALAADCggICAAAAA==.Lari:BAAALAAECgIIAwAAAA==.Lavabursted:BAAALAAECgIIAgAAAA==.Lavinna:BAAALAADCgcIBwAAAA==.',Le='Leaba:BAAALAAECgYIDgAAAA==.Leblanc:BAAALAAECggICgAAAA==.Lexania:BAAALAAECgQICgAAAA==.',Li='Lightbrand:BAABLAAFFIEGAAIWAAMI6g3OBgDBAAAWAAMI6g3OBgDBAAAAAA==.Lightisun:BAABLAAECoEXAAIVAAYIshgaOgCXAQAVAAYIshgaOgCXAQAAAA==.Lightmane:BAABLAAECoEpAAIZAAgIOyHXGQDuAgAZAAgIOyHXGQDuAgAAAA==.Lilacree:BAAALAADCgcIBwAAAA==.',Lo='Lohke:BAAALAAECggIDgAAAA==.Lornâ:BAAALAADCgYIAgAAAA==.Lostglaive:BAABLAAECoEUAAMcAAgImBm5FQDmAQAcAAYI7Bu5FQDmAQAGAAgIzRQ3XQDdAQAAAA==.',Lu='Lucarion:BAAALAAECgYICwAAAA==.Luftem:BAAALAAECgMIAwAAAA==.',Ma='Madbones:BAABLAAECoEUAAIZAAgI4QLH7ADVAAAZAAgI4QLH7ADVAAAAAA==.Magexd:BAAALAAECgYICwAAAA==.Magrin:BAAALAAECgYIDgAAAA==.Maldom:BAAALAAECgYIDwAAAA==.Manglorious:BAABLAAECoEmAAMkAAgIyx+jCgDVAgAkAAgIyx+jCgDVAgAiAAQIwxhdJgAqAQAAAA==.Marissa:BAAALAAECgYICwAAAA==.Mará:BAABLAAECoEjAAUdAAgIdxOnEQALAgAdAAgIHhOnEQALAgAhAAYIOBWwVQBMAQAlAAcIjQ2AFABDAQAVAAEIAxHnhgA+AAAAAA==.Masterchef:BAACLAAFFIEIAAMmAAMIIhSFDQDRAAAmAAMIIhSFDQDRAAAMAAEILgxCQABAAAAsAAQKgTEAAyYACAgtIwsRAMgCACYACAhPIgsRAMgCAAwABQgXHzJqAKEBAAAA.Maxdisc:BAAALAAECggIBgAAAA==.Maxi:BAAALAAECggICAAAAA==.',Me='Meta:BAAALAAECgYIBgAAAA==.',Mi='Mihdo:BAABLAAECoEaAAMMAAgIsRyUMwBDAgAMAAcINh2UMwBDAgAmAAQIvhJVcQDiAAAAAA==.Mindkiller:BAAALAAECgYICAAAAA==.Mithos:BAAALAADCggICAABLAAECggIIQAXAOYXAA==.',Mo='Molka:BAABLAAECoEZAAIQAAcIvhugLgAtAgAQAAcIvhugLgAtAgAAAA==.Monte:BAAALAAECgcIDwAAAA==.Morrígu:BAAALAADCgIIAgAAAA==.',Mu='Muffadin:BAAALAAECgUICwAAAA==.Murtagh:BAAALAADCggIDwAAAA==.',['Mí']='Míshka:BAABLAAECoEfAAIfAAgIrBHbNwDTAQAfAAgIrBHbNwDTAQAAAA==.',Na='Nadeko:BAAALAADCgMIBwAAAA==.Nairod:BAAALAADCgcIBwAAAA==.Naiya:BAABLAAECoEnAAIQAAgIvCUUAgBXAwAQAAgIvCUUAgBXAwAAAA==.Nasrudan:BAAALAAECggIEwAAAA==.Navissa:BAAALAAECgYICAAAAA==.',Ne='Nealson:BAABLAAECoEiAAICAAgIjBvLKgCcAgACAAgIjBvLKgCcAgAAAA==.Necri:BAABLAAECoEnAAIGAAgI9iPdCwA1AwAGAAgI9iPdCwA1AwAAAA==.Nemophila:BAABLAAECoEVAAIMAAYIwwrHogAqAQAMAAYIwwrHogAqAQABLAAECggIJgAhAKYhAA==.',Ni='Niesna:BAAALAAECgMIAwAAAA==.Nikkans:BAACLAAFFIESAAIZAAYIZR1YAQA7AgAZAAYIZR1YAQA7AgAsAAQKgSkAAhkACAg9JskFAGUDABkACAg9JskFAGUDAAAA.Nikki:BAAALAADCggICAAAAA==.Nina:BAAALAAECgIIAQAAAA==.Ninnoc:BAAALAAECgQIBgAAAA==.',No='Nobume:BAAALAAECgMIBAAAAA==.Nogearnofear:BAAALAADCgYIBwAAAA==.Norbi:BAABLAAECoEeAAIKAAgIDBlvJwBsAgAKAAgIDBlvJwBsAgAAAA==.',Nu='Nuit:BAAALAAECgEIAQAAAA==.',['Nö']='Nöx:BAABLAAECoEUAAIIAAYIKxs4IADgAQAIAAYIKxs4IADgAQAAAA==.',Oh='Ohyfs:BAAALAADCggICAAAAA==.',Op='Opalus:BAAALAADCgcICgAAAA==.',Or='Orothaine:BAAALAADCggICgAAAA==.',Os='Osiria:BAABLAAECoEmAAIhAAgIpiH8BwACAwAhAAgIpiH8BwACAwAAAA==.Oswynn:BAABLAAECoEgAAIdAAgIOyBeBgDcAgAdAAgIOyBeBgDcAgAAAA==.Osyluth:BAAALAADCgQIBAAAAA==.',Ou='Ouchie:BAABLAAECoEYAAIJAAgIXx0yDQBUAgAJAAgIXx0yDQBUAgAAAA==.',Pa='Pawl:BAAALAADCggICAAAAA==.',Pe='Peepars:BAABLAAECoEYAAMlAAcIqB+zBQB+AgAlAAcIqB+zBQB+AgAdAAIIHwohOgBOAAABLAAFFAMICAAdAEscAA==.Peepers:BAACLAAFFIEIAAIdAAMISxxSAwAeAQAdAAMISxxSAwAeAQAsAAQKgSYAAh0ACAihJJsBAFkDAB0ACAihJJsBAFkDAAAA.Person:BAAALAAECgIIAgAAAA==.',Ph='Phoeñix:BAAALAAECgUIAwAAAA==.',Po='Pocketpicka:BAAALAADCgcIDwAAAA==.',Pr='Prokletija:BAABLAAECoEVAAIDAAcIPB4jLwBPAgADAAcIPB4jLwBPAgAAAA==.',Py='Pyromaniac:BAACLAAFFIEIAAIOAAIIJBgxAwCqAAAOAAIIJBgxAwCqAAAsAAQKgTAAAg4ACAj6IRUBACUDAA4ACAj6IRUBACUDAAEsAAUUBggbABMAGyEA.',Qq='Qq:BAAALAADCgEIAQABLAAECggIGQAMANQmAA==.',Qu='Quellandra:BAAALAADCgMIAwAAAA==.Quilith:BAAALAADCggIEAABLAAECggIHwAMAMQhAA==.',Ra='Rafael:BAAALAAECgMIBAAAAA==.Raitou:BAABLAAECoEUAAMZAAYIRA20rwBZAQAZAAYIRA20rwBZAQARAAUISwz3RAD+AAABLAAECggIJQANADoZAA==.Raphius:BAAALAADCggICAAAAA==.Rastafman:BAAALAADCggIDgAAAA==.Ratut:BAACLAAFFIEHAAIBAAMIdBvVCAAXAQABAAMIdBvVCAAXAQAsAAQKgTAAAgEACAi8ImgFAC0DAAEACAi8ImgFAC0DAAAA.',Re='Reikärauta:BAABLAAECoEdAAIZAAcIuAak1gAMAQAZAAcIuAak1gAMAQAAAA==.Reliance:BAABLAAECoEoAAMTAAgIrBoRGwB2AgATAAgIrBoRGwB2AgAfAAUIigmDdgDmAAAAAA==.Renminnda:BAACLAAFFIEFAAMTAAMILxtoEQCvAAATAAIIcBloEQCvAAAfAAIIrgWeKACEAAAsAAQKgS8AAxMACAgIIKoOAOgCABMACAgIIKoOAOgCAB8ABwidGUEqABoCAAAA.Retier:BAACLAAFFIEMAAIiAAYI8SDTAABVAgAiAAYI8SDTAABVAgAsAAQKgTAAAyIACAiJJLQBAE0DACIACAiJJLQBAE0DACQAAQjAB4ZkADMAAAAA.Revybrew:BAACLAAFFIELAAMNAAMIqB3LBQAPAQANAAMIqB3LBQAPAQAJAAEI4hRPFQAzAAAsAAQKgRoAAg0ABwghJjEHANUCAA0ABwghJjEHANUCAAAA.Revyti:BAAALAAECgMIAwAAAA==.',Rh='Rhydan:BAAALAADCggIEAAAAA==.',Ri='Riftr:BAAALAAECggICAAAAA==.Rigonda:BAACLAAFFIEZAAIGAAYIiR9EAQCCAgAGAAYIiR9EAQCCAgAsAAQKgSwAAgYACAhzJiACAIEDAAYACAhzJiACAIEDAAAA.Riverwalker:BAAALAAECgIIAgABLAAECggIFQAkAHodAA==.',Rk='Rkyuub:BAAALAADCgcIBwAAAA==.',Ro='Rodati:BAACLAAFFIEGAAMPAAIIAyTFEQDZAAAPAAIIAyTFEQDZAAAQAAIILgbJQQBjAAAsAAQKgSUAAg8ACAj1JJQEAGIDAA8ACAj1JJQEAGIDAAAA.Rooflolly:BAAALAADCgEIAQAAAA==.Rosebútt:BAAALAAECgcIDQABLAAECggIJgAhAKYhAA==.',Ru='Ru:BAAALAAECgMIAwAAAA==.Rulan:BAABLAAECoEVAAITAAgIEBBiMwDUAQATAAgIEBBiMwDUAQAAAA==.Rustybubbles:BAABLAAECoEYAAMZAAcI/hb3ZgDmAQAZAAcI/hb3ZgDmAQARAAEIQBF+YwA0AAAAAA==.',['Rí']='Ríljrákk:BAAALAAFFAIIAgAAAA==.',Sa='Sabelliana:BAAALAAECgMIAwABLAAFFAIIBgAhAMwaAA==.Sael:BAABLAAECoEcAAIYAAcILCStAgDkAgAYAAcILCStAgDkAgAAAA==.Saephynea:BAAALAAECgcIDAAAAA==.Sahtiämpäri:BAAALAADCgYICgAAAA==.Saka:BAABLAAECoEaAAMCAAgI0B1uLACWAgACAAgI0B1uLACWAgAnAAQIBxe2JQADAQAAAA==.Sappyboi:BAAALAAECggIBgABLAAFFAYIGwAKAPkcAA==.Sarethas:BAAALAAECgEIAQAAAA==.',Sc='Scala:BAAALAADCgEIAQAAAA==.Scrin:BAABLAAECoEgAAMXAAgIrRthFABdAgAXAAgIrRthFABdAgAKAAEILQ2YxQA8AAAAAA==.',Se='Secondnoob:BAAALAADCgYIBgAAAA==.Seldarine:BAAALAADCggICAAAAA==.Seyrin:BAAALAAECgYICAABLAAECggIDgAHAAAAAA==.',Sh='Shamiina:BAAALAADCggICAAAAA==.Shirokiba:BAAALAADCggIDAAAAA==.Shrinkeypal:BAAALAAECgcICwAAAA==.Shrinkeysham:BAACLAAFFIENAAIPAAYIQxtKAwAaAgAPAAYIQxtKAwAaAgAsAAQKgSEAAg8ACAhrJEgNABEDAA8ACAhrJEgNABEDAAAA.',Si='Sipwel:BAAALAAECgYIDQAAAA==.',Sk='Skadi:BAAALAAECgcIEAAAAA==.Skumplast:BAAALAADCgMIAwAAAA==.Skærverg:BAAALAADCggIDgABLAAECgcIDQAHAAAAAA==.',Sl='Slamse:BAAALAADCggICAAAAA==.',Sm='Smirkymonk:BAAALAADCgcIBwAAAA==.Smurref:BAAALAADCggIGAAAAA==.',Sn='Sniffa:BAAALAAECggIDgABLAAFFAYIBwAJAOskAA==.',So='Soapnrope:BAAALAAECggIEAABLAAFFAYIGwAKAPkcAA==.Solastro:BAAALAAFFAMIBAAAAA==.',Sq='Squashee:BAAALAAFFAIIAgAAAA==.Squashiclysm:BAACLAAFFIEGAAIEAAIIAg+5OQCOAAAEAAIIAg+5OQCOAAAsAAQKgSAAAgQACAi0IYcPABQDAAQACAi0IYcPABQDAAAA.',St='Stoorm:BAAALAAFFAIIAgAAAA==.Stormvalor:BAABLAAECoEWAAIZAAcIuhJWgQCwAQAZAAcIuhJWgQCwAQAAAA==.',Su='Supercell:BAAALAAECgcIEAAAAA==.',Sy='Sylveon:BAAALAAECgcIEAABLAAECggIGAAJAF8dAA==.',Ta='Taay:BAAALAAECgcIDQAAAA==.Talowz:BAAALAADCggICAAAAA==.Tamurkhan:BAAALAAECgIIAgAAAA==.Tarskaden:BAAALAADCgQIBAAAAA==.Tauler:BAABLAAECoEZAAIhAAYIshiYPACvAQAhAAYIshiYPACvAQABLAAFFAIIAgAHAAAAAA==.',Te='Tedrass:BAAALAAECgYIBwAAAA==.Terendrýn:BAABLAAECoEgAAISAAgIhxogEAB5AgASAAgIhxogEAB5AgAAAA==.',Th='Thalario:BAAALAAECgIIAgAAAA==.Thalaron:BAABLAAECoEYAAIZAAgIURdSRwA2AgAZAAgIURdSRwA2AgAAAA==.Thebigpow:BAAALAAECgUIBQAAAA==.Thedukenine:BAAALAAECgQIBAABLAAECgcIIAACAGoPAA==.Thoradius:BAAALAADCgcIDAAAAA==.',Ti='Tibbor:BAACLAAFFIEJAAMKAAQIIRcoDgAIAQAKAAMIpxooDgAIAQAXAAEIjgzXHQBWAAAsAAQKgS0AAwoACAi7JDwXANcCAAoACAi7JDwXANcCABcACAgWGagUAFoCAAAA.Tiktik:BAABLAAECoEjAAIZAAgIvB7RHwDOAgAZAAgIvB7RHwDOAgAAAA==.Tinre:BAACLAAFFIEGAAMfAAIIwCSbEgDSAAAfAAIIwCSbEgDSAAATAAIIOQXvHQBwAAAsAAQKgRwABB8ACAg4IfwOANcCAB8ACAgYIfwOANcCABMABQjbFLNWACsBABQAAQj4I5QnAGQAAAAA.',To='Today:BAAALAAECgYICQAAAA==.Tolanaar:BAAALAAECgIIAgAAAA==.Topdkey:BAABLAAECoEUAAICAAgInxlbNQB0AgACAAgInxlbNQB0AgABLAAFFAYIGwAKAPkcAA==.Totemjävel:BAAALAADCgEIAQABLAADCgMIAwAHAAAAAA==.Totemkin:BAABLAAECoEUAAIQAAYIfRaKZACEAQAQAAYIfRaKZACEAQAAAA==.',Tr='Tritonus:BAAALAAECggICAAAAA==.Triumoh:BAAALAADCgcIBwAAAA==.Truesittkens:BAAALAADCgMIAwAAAA==.',Ts='Tsukuyo:BAAALAAECgEIAQAAAA==.',Ty='Tyraea:BAAALAAECgEIAQABLAAECgcIHgAZAD4lAA==.',Ug='Uglygrill:BAAALAAECgUIBgAAAA==.',Un='Unaimed:BAAALAADCggICAAAAA==.',Ut='Utsa:BAAALAAECgIIAgAAAA==.',Va='Vallrell:BAAALAAECgYICwABLAAECgcIFAAYABcXAA==.Valrell:BAABLAAECoEUAAQYAAcIFxelGQAUAQADAAYIlhalZACHAQAIAAUIMA6USQAeAQAYAAQIBRClGQAUAQAAAA==.Vanillacroco:BAAALAADCggIFwAAAA==.',Ve='Veloskm:BAAALAAECgMIAwAAAA==.Ventriss:BAAALAAECgMIAwAAAA==.Verdell:BAAALAADCgUIBQAAAA==.Vestigium:BAACLAAFFIEbAAInAAYIRCRqAAB9AgAnAAYIRCRqAAB9AgAsAAQKgTAAAicACAjbJTQBAGwDACcACAjbJTQBAGwDAAAA.',Vi='Vileplume:BAAALAAECgYIBgAAAA==.',Vo='Votka:BAAALAADCgcIBwAAAA==.Voïd:BAAALAADCggICAAAAA==.',Wa='Wac:BAAALAAECgMIAwABLAAFFAUIDQATAAsdAA==.Wachunter:BAAALAAECggIDwABLAAFFAUIDQATAAsdAA==.Wacmage:BAAALAAECgcICwABLAAFFAUIDQATAAsdAA==.Wanhéda:BAAALAAECgUIDAAAAA==.',Wh='Wheelchair:BAABLAAECoEYAAIRAAgIvBIUHgDsAQARAAgIvBIUHgDsAQAAAA==.Wheelchrchef:BAAALAADCgEIAQABLAAFFAMICAAmACIUAA==.',Wi='Willjum:BAAALAADCgQIBAAAAA==.Wit:BAAALAAECgQIBwAAAA==.',Wo='Wombats:BAACLAAFFIEZAAMMAAYI6SGJAQAxAgAMAAYIwyCJAQAxAgAmAAMIDhzhCgDzAAAsAAQKgTAAAwwACAhgJkkCAHMDAAwACAhgJkkCAHMDACYACAj+HxUQANECAAAA.Wonkie:BAAALAAECgIIAgAAAA==.Wonton:BAAALAAECgMIBAAAAA==.',Wr='Wren:BAAALAAECgYIEQAAAA==.',Wu='Wuxci:BAAALAADCggICAAAAA==.',['Wà']='Wàc:BAAALAADCgYIBgABLAAFFAUIDQATAAsdAA==.',['Wá']='Wác:BAACLAAFFIENAAITAAUICx0lBQDAAQATAAUICx0lBQDAAQAsAAQKgSEAAxMACAjxJSEGAEADABMACAjxJSEGAEADAB8AAgg/C8qQAG4AAAAA.',Xi='Xinzy:BAAALAAECggICAAAAA==.',Xo='Xo:BAABLAAECoEjAAIhAAgIMCENCgDtAgAhAAgIMCENCgDtAgAAAA==.Xor:BAACLAAFFIEQAAMIAAUIXiEnAwDgAAADAAQIah8JDACXAQAIAAIIYCUnAwDgAAAsAAQKgTAABAgACAihJqcJAKwCAAgABgiSJqcJAKwCABgABQjiJt0GAEMCAAMAAwjaJIWCADYBAAAA.',Ya='Yadé:BAACLAAFFIELAAIGAAUIUBBiCACkAQAGAAUIUBBiCACkAQAsAAQKgRkAAgYACAgNIUUUAAIDAAYACAgNIUUUAAIDAAAA.Yathl:BAAALAAECgYIBgABLAAFFAIIBgAhAMwaAA==.Yathrien:BAAALAADCgYIBgABLAAFFAIIBgAhAMwaAA==.Yawnie:BAAALAADCggIIAABLAAECggIHwABAOwfAA==.',Ye='Yenterey:BAAALAAFFAIIAgABLAAFFAYIGwAKAPkcAA==.Yevar:BAAALAAECgUICgABLAAECgcIEQAHAAAAAA==.',Yo='Yokeshi:BAAALAADCgEIAQAAAA==.',Za='Zaidbama:BAAALAAECgMIAwAAAA==.Zain:BAAALAAECgIIAgAAAA==.Zam:BAAALAAECgYIEQABLAAFFAMIDgAPAHYQAA==.',Ze='Zeegoddess:BAAALAAECgQIBAAAAA==.Zetsupt:BAAALAAECgYIEgAAAA==.',Zi='Zindara:BAAALAAECgMIAQAAAA==.',Zo='Zoogi:BAAALAAECgIIAgAAAA==.Zookerella:BAAALAAECgMIAwAAAA==.Zookette:BAAALAADCgQIBAAAAA==.Zookiana:BAAALAADCggICAAAAA==.Zorokao:BAAALAADCggIGAAAAA==.',Zu='Zubye:BAACLAAFFIENAAIEAAUIXwuUDQCBAQAEAAUIXwuUDQCBAQAsAAQKgSIAAgQACAi3HmQjAKYCAAQACAi3HmQjAKYCAAAA.Zuse:BAAALAADCgQIBAAAAA==.',Zz='Zzigo:BAAALAAECgMIAwAAAA==.',['Öt']='Öttiäinen:BAABLAAECoEXAAICAAcI7wmk0AAuAQACAAcI7wmk0AAuAQAAAA==.',['Üb']='Übeåvieel:BAAALAADCggIHAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end