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
 local lookup = {'Warlock-Destruction','DemonHunter-Vengeance','Monk-Brewmaster','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','DeathKnight-Frost','Druid-Balance','DemonHunter-Havoc','Warrior-Fury','Warrior-Protection','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Demonology','Warlock-Affliction','Unknown-Unknown','Evoker-Devastation','Mage-Frost','Mage-Arcane','Druid-Feral','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Hunter-Marksmanship','Paladin-Retribution','Rogue-Assassination','Paladin-Protection','Druid-Restoration','Hunter-Survival','Paladin-Holy','Druid-Guardian','Priest-Shadow','Mage-Fire','Rogue-Subtlety',}; local provider = {region='EU',realm='SteamwheedleCartel',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ad='Adaephonn:BAAALAAECgcIEgAAAA==.',Ae='Aelea:BAAALAAECgYIDgAAAA==.Aethelflaed:BAABLAAECoEYAAIBAAgItQWkgAA8AQABAAgItQWkgAA8AQAAAA==.',Af='Afrah:BAAALAAECgYICwABLAAECggIJAACAPoWAA==.',Ai='Aidune:BAAALAAECggICgAAAA==.Aigon:BAABLAAECoEkAAIDAAgIwBfKEAAbAgADAAgIwBfKEAAbAgAAAA==.Aiyana:BAAALAAECgMIBAAAAA==.',Al='Algelon:BAAALAAECgQIBgAAAA==.Alzoie:BAAALAAECgYIBgAAAA==.',An='Anilerda:BAAALAADCggIEQAAAA==.',Ar='Arashicage:BAACLAAFFIEHAAIEAAMI8hXnAAABAQAEAAMI8hXnAAABAQAsAAQKgSAAAgQACAimIZYCAAwDAAQACAimIZYCAAwDAAAA.Arckadius:BAAALAAECgcIDwAAAA==.Ardend:BAABLAAECoEdAAMFAAcIxiIcGACYAgAFAAcIxiIcGACYAgAGAAEI6An0pgA1AAAAAA==.Arrengel:BAABLAAECoEXAAIHAAYIJA/dmQA9AQAHAAYIJA/dmQA9AQAAAA==.',As='Ashadon:BAABLAAECoEVAAIIAAgIdQaDvQBPAQAIAAgIdQaDvQBPAQAAAA==.Ashamy:BAAALAADCggIBAAAAA==.Ashenne:BAABLAAECoEhAAIJAAgI3wyIOQCZAQAJAAgI3wyIOQCZAQAAAA==.Asterian:BAABLAAECoEeAAMGAAgI1BP3MgANAgAGAAgI1BP3MgANAgAFAAcIxhT1VgCqAQAAAA==.Asterionela:BAABLAAECoEgAAIHAAgIcRLGUwDaAQAHAAgIcRLGUwDaAQAAAA==.Astonhunt:BAABLAAECoEdAAIHAAcI9QxXgwBqAQAHAAcI9QxXgwBqAQAAAA==.Astonlock:BAAALAADCggIHAAAAA==.',Au='Aubade:BAAALAAECgEIAQAAAA==.Aulinel:BAAALAADCgIIAgAAAA==.',Av='Avasarala:BAABLAAECoEgAAIKAAgIEB0ZLwBzAgAKAAgIEB0ZLwBzAgAAAA==.Avengerx:BAAALAAECgUIBgAAAA==.',Aw='Awoo:BAABLAAECoEdAAIHAAcIwBpVRAAHAgAHAAcIwBpVRAAHAgAAAA==.',Ba='Basphomet:BAAALAADCggICAABLAAECggIIAACAPIkAA==.',Be='Beardaddy:BAAALAAECggICAABLAAFFAQIDgAHAGkcAA==.Beerbelly:BAAALAAECgcIDgAAAA==.Before:BAAALAADCgcIDAABLAAECggIIAACAPIkAA==.Bekkey:BAABLAAECoEZAAMLAAcIzgrbbABoAQALAAcIzgrbbABoAQAMAAcIIgcgSQAFAQAAAA==.Bellethanos:BAACLAAFFIERAAQIAAYIzRqYBgDVAQANAAYITxc/AQAbAgAIAAUITxqYBgDVAQAOAAIIvxlTDACjAAAsAAQKgRgAAw0ACAgsILoLAGQCAA0ACAh4HroLAGQCAA4ACAjrGioUAAsCAAEsAAUUCAgVAAgAiCQA.Berdache:BAABLAAECoEaAAIJAAgIlBrEGQBhAgAJAAgIlBrEGQBhAgAAAA==.Bertrand:BAAALAAECgUICQAAAA==.Betrayer:BAAALAAFFAMIAwABLAAFFAYICgALAEYdAA==.',Bl='Blightcall:BAABLAAECoEhAAQPAAgI+x2REgBHAgAPAAcInx2REgBHAgAQAAIIxRlMJwCQAAABAAEI/h77xQBYAAAAAA==.Blightmoore:BAAALAADCggICAAAAA==.Blinkhorn:BAABLAAECoEcAAIEAAcISBZ3DADrAQAEAAcISBZ3DADrAQAAAA==.Blokella:BAAALAADCgQIBAAAAA==.Bloods:BAAALAADCgUICQAAAA==.',Bo='Bossdemon:BAAALAADCgUIBQABLAAECgYIBgARAAAAAA==.Bossdragon:BAACLAAFFIEJAAISAAQICh+OBgBpAQASAAQICh+OBgBpAQAsAAQKgS4AAhIACAh/IwgFADMDABIACAh/IwgFADMDAAAA.Bosspriest:BAAALAAECgYIBgAAAA==.',Br='Broly:BAABLAAFFIEGAAMTAAII3yPuBADPAAATAAII3yPuBADPAAAUAAIIAxYpKgChAAABLAAFFAYIFgATAFYdAA==.',['Bö']='Börjebula:BAAALAADCgcIBwAAAA==.',Ca='Cannibalize:BAACLAAFFIEGAAIIAAMIMAc6HADNAAAIAAMIMAc6HADNAAAsAAQKgS4AAwgACAjpHDkzAHwCAAgACAjpHDkzAHwCAA4ABAgRB+k/AKQAAAAA.',Ch='Chaseline:BAAALAADCgQIBAAAAA==.Chewbarka:BAACLAAFFIEJAAIVAAMIZCAaAwAqAQAVAAMIZCAaAwAqAQAsAAQKgS8AAhUACAgfJl8AAIYDABUACAgfJl8AAIYDAAAA.Chibaron:BAABLAAECoEdAAMWAAgIVxgZKAAmAgAWAAgISxcZKAAmAgAXAAMIHhZbHQC/AAAAAA==.',Ci='Cier:BAAALAAECgIIAgAAAA==.Ciri:BAABLAAECoEfAAIKAAgInx/WGgDbAgAKAAgInx/WGgDbAgAAAA==.',Cl='Clemency:BAAALAAECgQICgAAAA==.',Co='Corix:BAAALAADCggIDwAAAA==.Corlaa:BAACLAAFFIEGAAIGAAIIUwdrIwCEAAAGAAIIUwdrIwCEAAAsAAQKgScAAwYACAjEFcosAC4CAAYACAjEFcosAC4CAAUABwgICJCcAAABAAAA.',Cr='Cratus:BAAALAAECgYIEQAAAA==.Croghailin:BAAALAAECgQICgAAAA==.',Da='Dappledtree:BAAALAADCggIFAAAAA==.Darkhallow:BAAALAAECgQIBAABLAAFFAMIBwAEAPIVAA==.Darkhunter:BAACLAAFFIEJAAIHAAQI7RasCwAnAQAHAAQI7RasCwAnAQAsAAQKgSsAAgcACAiEIDYYAM0CAAcACAiEIDYYAM0CAAAA.Dawnflower:BAABLAAECoEYAAIYAAgIPAueIgBYAQAYAAgIPAueIgBYAQAAAA==.',De='Deathmike:BAABLAAECoEWAAMOAAYIVSNeEQAsAgAOAAYIVSNeEQAsAgAIAAIIaiDRDwGdAAAAAA==.Demodan:BAACLAAFFIEIAAIPAAMIQRgzAgAKAQAPAAMIQRgzAgAKAQAsAAQKgTEAAg8ACAjXIdAEAAQDAA8ACAjXIdAEAAQDAAAA.Dendria:BAAALAADCggICAAAAA==.',Di='Dihmon:BAABLAAECoEkAAICAAgI+hZHFAD3AQACAAgI+hZHFAD3AQAAAA==.',Dk='Dkvirgin:BAAALAADCggICAABLAAECgQICAARAAAAAA==.',Do='Dole:BAAALAADCgUIBQAAAA==.',Dr='Dracon:BAAALAADCgMIAwAAAA==.Drakbert:BAABLAAECoEeAAIZAAgIJSErDgDjAgAZAAgIJSErDgDjAgAAAA==.Draxiah:BAAALAAECgcIEgAAAA==.Drazkon:BAAALAADCggIDwAAAA==.Dreaxan:BAAALAADCggICAAAAA==.Druidstrider:BAAALAADCgIIAgABLAAECggIFgAaAKUYAA==.Druidvirgin:BAAALAAECgMIBAABLAAECgQICAARAAAAAA==.Drusanda:BAAALAADCggIDwAAAA==.',Eb='Eblise:BAACLAAFFIEHAAIbAAMIbhUOCgD3AAAbAAMIbhUOCgD3AAAsAAQKgSoAAhsACAgjHlwJAOUCABsACAgjHlwJAOUCAAAA.',Ec='Ecco:BAAALAAECgQIBgAAAA==.',Ed='Edofix:BAAALAADCggIGgAAAA==.',Ei='Eiran:BAACLAAFFIELAAMGAAQIbBFVCgBBAQAGAAQIbBFVCgBBAQAFAAIICAsBNwBxAAAsAAQKgS4AAwYACAjfIV0NABADAAYACAjfIV0NABADAAUABAizChXNAKIAAAAA.',El='Elenore:BAAALAAECgUICQAAAA==.Elowynn:BAAALAAECgYICQAAAA==.',Ev='Evans:BAABLAAECoEdAAIaAAcIlxyYSQAwAgAaAAcIlxyYSQAwAgAAAA==.',Fe='Felmoe:BAAALAADCggICAABLAAFFAQIDgAHAGkcAA==.',Fi='Fister:BAAALAADCgMIAwAAAA==.',Fl='Flaypenguin:BAABLAAFFIEGAAMcAAQIqgSCBQDZAAAcAAQIgQSCBQDZAAAaAAIIGgQcOwCBAAABLAAFFAgIEAAaAIYcAA==.Flo:BAAALAAECgQIBQABLAAECgYIEgARAAAAAA==.',Fr='Frekko:BAAALAAECgcIBwAAAA==.',Ga='Gamlap:BAAALAADCggICgAAAA==.Gangbo:BAAALAAECggIEgAAAA==.Gazrul:BAAALAAFFAIIAwAAAA==.',Ge='Getsugatensh:BAAALAAECgcIDAAAAA==.',Gh='Gharretth:BAAALAAECgIIAgABLAAECgYICwARAAAAAA==.',Gi='Gingerbread:BAAALAAECgYIBgAAAA==.',Gj='Gjulnir:BAAALAADCggIDgAAAA==.',Gn='Gnarly:BAAALAAECgYIDAAAAA==.',Go='Goatface:BAABLAAFFIEIAAMEAAIIqxlHAgCuAAAEAAIIqxlHAgCuAAALAAEIkA6FMwBJAAAAAA==.Goonst:BAAALAAECgEIAgAAAA==.Goromajimá:BAAALAAECgMIAwAAAA==.',Gr='Grevoline:BAAALAAECgcIDAAAAA==.Gromgnok:BAAALAAECgIIAgAAAA==.',Gu='Gunvarr:BAAALAAECgMIAwAAAA==.Guthrik:BAABLAAECoEcAAIBAAcIBgV+iQAiAQABAAcIBgV+iQAiAQAAAA==.',Ha='Hafthor:BAAALAAECgcIDgAAAA==.Hallowed:BAABLAAECoEgAAICAAgI8iQEAgBSAwACAAgI8iQEAgBSAwAAAA==.Hamdergert:BAABLAAECoETAAMBAAgIUBQ4QQD+AQABAAgITxI4QQD+AQAPAAYIQBPqLwCKAQABLAAFFAUICgAJAJ4WAA==.Hasslêhoof:BAAALAAECgYIEAAAAA==.',He='Hek:BAABLAAECoEUAAIVAAYIOhwtFgDOAQAVAAYIOhwtFgDOAQABLAAECgcIBwARAAAAAA==.Hektlar:BAAALAAECgcIBwAAAA==.Hereboy:BAAALAAECgQICwAAAA==.Hexanna:BAAALAAECgEIAQAAAA==.',Hi='Hickory:BAABLAAECoEgAAMdAAgINhOEOgC3AQAdAAgINhOEOgC3AQAJAAEIcwU4jgAtAAAAAA==.Hirani:BAABLAAECoEUAAIGAAcI+w+LSQCrAQAGAAcI+w+LSQCrAQAAAA==.',Ho='Hobow:BAABLAAECoEbAAIHAAYIhA2blwBBAQAHAAYIhA2blwBBAQAAAA==.',Hu='Hugorune:BAAALAAECgEIAQAAAA==.Huli:BAAALAAECgQICwAAAA==.Huntstrider:BAAALAAECgYICQABLAAECggIFgAaAKUYAA==.',['Hå']='Hårddreng:BAAALAAECgMIBAAAAA==.',['Hó']='Hótalot:BAABLAAECoEaAAIdAAgIyyPDBAAtAwAdAAgIyyPDBAAtAwAAAA==.',Ic='Iceflower:BAAALAAECggIDgAAAA==.',Ig='Igneo:BAABLAAECoEdAAIeAAcInh5LBACLAgAeAAcInh5LBACLAgAAAA==.',Il='Ilaria:BAACLAAFFIEFAAIfAAIIIg14FACSAAAfAAIIIg14FACSAAAsAAQKgSQAAh8ACAjYHgQJAMACAB8ACAjYHgQJAMACAAAA.Illuren:BAABLAAECoEXAAIfAAgIvhezEwBGAgAfAAgIvhezEwBGAgAAAA==.Ilphas:BAAALAADCgMIAgAAAA==.',Io='Ioni:BAAALAADCggIFwAAAA==.',Iv='Ivella:BAAALAADCggIFAAAAA==.',Ja='Jaena:BAAALAADCggIHwAAAA==.Jayni:BAAALAAECgQICAAAAA==.',Je='Jerzy:BAAALAADCggICwAAAA==.',Ji='Jiemierix:BAAALAAECgYICwAAAA==.Jizy:BAAALAADCgcIEAAAAA==.Jizzly:BAABLAAECoEdAAIdAAcIZB+jFgB8AgAdAAcIZB+jFgB8AgAAAA==.',Jo='Jod:BAACLAAFFIEHAAIOAAIImgh5DwCUAAAOAAIImgh5DwCUAAAsAAQKgS0AAw4ACAibGeELAHoCAA4ACAibGeELAHoCAAgABgjLBqzxAOcAAAAA.Jodders:BAAALAAECgQICwAAAA==.',Ju='Jumanjí:BAAALAAECgcIDgAAAA==.',Ka='Kaasuten:BAAALAADCgcIBwAAAA==.Kafi:BAABLAAECoEbAAIHAAYIcRulYAC4AQAHAAYIcRulYAC4AQABLAAECgcIHgAKAHUZAA==.Kafál:BAABLAAECoEeAAIKAAcIdRkPQwAnAgAKAAcIdRkPQwAnAgAAAA==.Karmael:BAACLAAFFIEIAAIfAAMIZxXgCADxAAAfAAMIZxXgCADxAAAsAAQKgSkAAh8ACAjLGpYPAHECAB8ACAjLGpYPAHECAAAA.',Ke='Kenatsa:BAAALAAECgYICQABLAAECgcIFAAGAPsPAA==.',Kh='Khalfurion:BAACLAAFFIEHAAIJAAMIwhIxCwDbAAAJAAMIwhIxCwDbAAAsAAQKgScAAgkACAiUIJQMAO0CAAkACAiUIJQMAO0CAAAA.Khay:BAAALAADCgYIBgABLAAECggIJAACAPoWAA==.Khialune:BAABLAAECoEcAAIgAAcIdByHBwBGAgAgAAcIdByHBwBGAgAAAA==.',Ki='Kirayoshi:BAAALAAECgcIBwAAAA==.Kirsebeate:BAAALAAECgYIDAABLAAFFAUICgAJAJ4WAA==.',Kl='Kledius:BAAALAADCggICwABLAAECgYIBgARAAAAAA==.',Ko='Kodaan:BAAALAADCgcICAAAAA==.Kolkmonk:BAAALAADCggIDwAAAA==.Kozah:BAAALAAFFAIIAgAAAA==.',Kr='Kronomer:BAAALAADCgcICAAAAA==.',['Ká']='Káng:BAAALAADCgMIAwABLAAECggIGAALABQYAA==.',La='Laochramóra:BAAALAAECgMIBAAAAA==.Laphicet:BAABLAAECoEcAAIWAAcI/glYWQBJAQAWAAcI/glYWQBJAQAAAA==.',Le='Lessandre:BAAALAADCggIEAAAAA==.Letum:BAAALAAECgUIDAAAAA==.Levimon:BAACLAAFFIEFAAMJAAIILAwsGACDAAAJAAIILAwsGACDAAAdAAIIEgSzLABtAAAsAAQKgR8AAwkACAh9IMgNAN8CAAkACAh9IMgNAN8CAB0ACAi7BiVjACIBAAAA.Lexii:BAABLAAECoEhAAIBAAcInQ9vYACTAQABAAcInQ9vYACTAQAAAA==.',Lh='Lhiip:BAAALAAECgcIEAAAAA==.',Li='Lightweight:BAAALAAECgQIBgAAAA==.',Lo='Lockstrider:BAAALAADCgYIBgABLAAECggIFgAaAKUYAA==.Lodash:BAAALAADCgUIBQABLAAECgIIAwARAAAAAA==.',Ma='Maelstromike:BAAALAAECgYIBgABLAAECgYIFgAOAFUjAA==.Maeriko:BAACLAAFFIEMAAIYAAQIjQOPBgD4AAAYAAQIjQOPBgD4AAAsAAQKgS4AAhgACAhPGqsMAG4CABgACAhPGqsMAG4CAAAA.Maewynn:BAAALAAECgYIBgAAAA==.Magickmike:BAAALAAECgQIBAABLAAECgYIFgAOAFUjAA==.Magnetica:BAAALAAECgcIEQAAAA==.Mak:BAAALAAECgcIEwAAAA==.Maksüno:BAAALAADCggICwABLAAECggIGAALABQYAA==.Malinae:BAAALAADCggICAAAAA==.Maniax:BAAALAADCggICAAAAA==.Markahunt:BAAALAADCgcICAAAAA==.Maxlir:BAABLAAECoElAAQLAAgIKRuFJQB3AgALAAgI5BmFJQB3AgAMAAMIcxfpVwC2AAAEAAEI7g3TMwAwAAAAAA==.Mazoga:BAABLAAECoEZAAMaAAgIUR66IQDEAgAaAAgIUR66IQDEAgAcAAIIpwXHWAA+AAAAAA==.',Me='Melephant:BAAALAADCgUIBQAAAA==.Mephi:BAAALAADCgMIAwAAAA==.',Mi='Miema:BAAALAADCgcIDAAAAA==.Miku:BAAALAADCgcIBgABLAAECgYIEgARAAAAAA==.Milogor:BAAALAAECgMIBQAAAA==.Mirabeau:BAAALAADCgcICAAAAA==.Misrule:BAAALAADCggIHAAAAA==.',Mn='Mnee:BAAALAAECgYIEQAAAA==.Mnyo:BAAALAAECgYIBgAAAA==.Mnåå:BAAALAAECgQIBAAAAA==.',Mo='Moonshadow:BAAALAAECgYICAAAAA==.Morkvarg:BAACLAAFFIEKAAIQAAQIzBOAAABjAQAQAAQIzBOAAABjAQAsAAQKgS4AAhAACAjqIoABACwDABAACAjqIoABACwDAAAA.',Mu='Musong:BAABLAAECoEWAAIDAAcIbh6pDQBMAgADAAcIbh6pDQBMAgAAAA==.',Na='Nakedsnake:BAAALAAECgEIAQABLAAECgYIFgAOAFUjAA==.Natrey:BAABLAAECoEhAAIgAAgIzhhECAAxAgAgAAgIzhhECAAxAgAAAA==.Nazgrin:BAAALAADCgMIAwAAAA==.',Ne='Necalli:BAAALAADCggIDAAAAA==.Nemezis:BAAALAAECgcIEwAAAA==.',Ni='Nidhhogg:BAABLAAECoEeAAINAAgIMiEWBgDnAgANAAgIMiEWBgDnAgAAAA==.Nieve:BAAALAAECgYIBgAAAA==.Niquil:BAAALAAECgEIAQAAAA==.Nivráthá:BAABLAAECoEoAAMPAAgIJRsOEABfAgAPAAgIcRoOEABfAgABAAgIMBW5NAAzAgAAAA==.Nixxar:BAACLAAFFIEJAAIaAAMIbhzMCwAMAQAaAAMIbhzMCwAMAQAsAAQKgS0AAhoACAj4JTYDAHsDABoACAj4JTYDAHsDAAAA.',Ny='Nymdemon:BAAALAAECgYIEwAAAA==.Nyrelle:BAABLAAECoERAAIHAAYIwBlcbQCaAQAHAAYIwBlcbQCaAQAAAA==.',Ob='Obefix:BAAALAAECgEIAQAAAA==.',Od='Oddity:BAAALAADCgIIAgAAAA==.',Ol='Olyesse:BAAALAADCgEIAQAAAA==.',Or='Ormandons:BAABLAAECoEYAAILAAgIFBhSMwAtAgALAAgIFBhSMwAtAgAAAA==.',Pa='Pakulia:BAAALAAECgcIEwAAAA==.Palastrider:BAABLAAECoEWAAMaAAcIpRjGUQAYAgAaAAcIsRfGUQAYAgAcAAYIFhcuJQCLAQAAAA==.Pandem:BAAALAAECgYICwAAAA==.',Ph='Phos:BAAALAAECgUIBgABLAADCggIHwARAAAAAA==.',Pl='Plutonium:BAAALAADCgYIBgAAAA==.',Pr='Pretorius:BAABLAAECoEmAAMMAAgIVhIpJgDJAQAMAAgIlBEpJgDJAQALAAcIgAz3YwCCAQAAAA==.Prevoker:BAACLAAFFIEMAAISAAQI/Q8GCAAzAQASAAQI/Q8GCAAzAQAsAAQKgSsAAhIACAg4HXUOALICABIACAg4HXUOALICAAAA.',Qu='Queffa:BAABLAAECoEmAAIFAAgIPhO4TwC+AQAFAAgIPhO4TwC+AQAAAA==.Queffitch:BAAALAADCgYIBgAAAA==.Queftard:BAAALAAECgYIBwAAAA==.Quellia:BAABLAAECoEYAAIaAAgIlRjLRwA1AgAaAAgIlRjLRwA1AgAAAA==.Questionmark:BAAALAAECgYIBgAAAA==.',Ra='Radahn:BAABLAAECoEYAAILAAcIzB51JwBsAgALAAcIzB51JwBsAgAAAA==.Ralgon:BAAALAAECgQICAAAAA==.',Re='Reave:BAAALAAECgYIBgABLAAECggIGgAJAJQaAA==.Rexicorum:BAABLAAECoEXAAIKAAYIFyLUNgBTAgAKAAYIFyLUNgBTAgAAAA==.',Rh='Rhenna:BAABLAAECoEcAAMXAAcI+Az0EQBMAQAXAAcI+Az0EQBMAQAhAAIIhguLeABsAAAAAA==.',Ro='Ronshamson:BAAALAADCgYICAAAAA==.Roythelan:BAACLAAFFIEHAAIiAAII/gpuBACWAAAiAAII/gpuBACWAAAsAAQKgSwAAiIACAh0FrcEAC0CACIACAh0FrcEAC0CAAAA.',Ru='Runeblight:BAAALAAECgIIAgAAAA==.',Ry='Ryéhill:BAABLAAECoEcAAIaAAcIcw4tkACTAQAaAAcIcw4tkACTAQAAAA==.',Sa='Sanaivai:BAACLAAFFIEOAAIHAAQIaRwOCQBcAQAHAAQIaRwOCQBcAQAsAAQKgSIAAgcACAiLHTwoAHMCAAcACAiLHTwoAHMCAAAA.Saneot:BAABLAAECoEcAAIaAAcIHB4ZOgBeAgAaAAcIHB4ZOgBeAgAAAA==.Sanguines:BAAALAAECgQICgAAAA==.Sanrien:BAAALAAECgcIBwAAAA==.Saressa:BAAALAAECgcIEAAAAA==.Saucysauce:BAAALAAECgYICgAAAA==.',Sc='Scorchbane:BAAALAAECgcIDQAAAA==.',Se='Seeren:BAABLAAECoEgAAIWAAgIryMLDwDXAgAWAAgIryMLDwDXAgAAAA==.Sereh:BAAALAAECgIIAgAAAA==.',Sh='Shadowdemon:BAAALAADCgcICwAAAA==.Shadowlily:BAABLAAECoEVAAIdAAYIAheTRQCJAQAdAAYIAheTRQCJAQAAAA==.Shakarri:BAAALAAECgYICAAAAA==.Shamsanda:BAABLAAECoEeAAIFAAgIvRimMQAiAgAFAAgIvRimMQAiAgAAAA==.Shamystrider:BAABLAAECoEUAAMFAAcI/w/scABiAQAFAAcI/w/scABiAQAGAAMIogAJlwBsAAABLAAECggIFgAaAKUYAA==.Shant:BAAALAADCggICAAAAA==.',Si='Sidenia:BAAALAADCggIFQAAAA==.Silverbranch:BAABLAAECoEWAAIgAAgIQBeeCQARAgAgAAgIQBeeCQARAgAAAA==.Simosaki:BAAALAADCggIDwAAAA==.Sixseven:BAAALAAECgYIEgAAAA==.',Sk='Skribbles:BAAALAADCgYIBgABLAADCggIHwARAAAAAA==.Skyfall:BAABLAAECoEiAAQBAAgIPR3QIACdAgABAAgINhzQIACdAgAQAAIIbBZvJQCdAAAPAAIIChgUZwCbAAAAAA==.Skyhope:BAAALAADCgYIBgAAAA==.',Sl='Sledgehammer:BAABLAAECoEUAAIaAAYIzQL9/wCiAAAaAAYIzQL9/wCiAAAAAA==.Sleipner:BAACLAAFFIEFAAMNAAMI0w+9CQCOAAANAAIIpRa9CQCOAAAIAAEIMAJEZABFAAAsAAQKgSkAAw0ACAg7JMkDACQDAA0ACAg7JMkDACQDAAgABgjhECu3AFoBAAAA.Slím:BAABLAAECoEZAAILAAcIDBzJMAA5AgALAAcIDBzJMAA5AgAAAA==.',Sm='Smíle:BAAALAADCgUICAAAAA==.',Sn='Sneb:BAAALAAECggICAAAAA==.',So='Solastra:BAABLAAECoEWAAISAAgIZhmaFwBIAgASAAgIZhmaFwBIAgAAAA==.Souljamon:BAAALAADCgYICAAAAA==.',Sp='Spacejám:BAACLAAFFIEGAAIhAAMINA82DwDPAAAhAAMINA82DwDPAAAsAAQKgS4AAyEACAhbHU0ZAIYCACEABwh3H00ZAIYCABYABAg3BmCDAKwAAAAA.Spunkmeyer:BAAALAADCgYIBgAAAA==.',St='Staggmatt:BAAALAAECgQICwAAAA==.Stormrise:BAAALAADCgcIBwAAAA==.',Sy='Syhla:BAABLAAECoEdAAIPAAcI7h6YDQB7AgAPAAcI7h6YDQB7AgAAAA==.',Ta='Talana:BAAALAAECgQIBAABLAAFFAMIBwAEAPIVAA==.Talneas:BAABLAAECoEYAAICAAYIQyGuDwAzAgACAAYIQyGuDwAzAgAAAA==.Tamaki:BAACLAAFFIEHAAIKAAQIExloCgBbAQAKAAQIExloCgBbAQAsAAQKgSYAAgoACAhoI+sMAC4DAAoACAhoI+sMAC4DAAAA.Tashrog:BAAALAADCggICAAAAA==.Taurances:BAABLAAECoEfAAIVAAcItCKUCACqAgAVAAcItCKUCACqAgAAAA==.',Te='Teremoo:BAAALAAECgQICQAAAA==.',Th='Thoriata:BAABLAAECoEcAAIFAAcIGxXNVQCtAQAFAAcIGxXNVQCtAQAAAA==.Thoronska:BAAALAADCgIIAgAAAA==.',Ti='Tiiwaz:BAAALAADCggIFwAAAA==.Tinkerlight:BAAALAAECgQICwAAAA==.Tinkytank:BAAALAADCggICAAAAA==.Tinystark:BAAALAADCgEIAQAAAA==.',Tr='Trixzie:BAAALAAECgMIBAAAAA==.',Ua='Uabhar:BAAALAAECgQIBwAAAA==.',Un='Underzero:BAAALAAECgYIBAABLAAFFAMIBQAbADAbAA==.',Va='Vagner:BAAALAADCggIFwAAAA==.Varunex:BAACLAAFFIEIAAIIAAIIMRykKACqAAAIAAIIMRykKACqAAAsAAQKgRUAAggABwggIC8/AFQCAAgABwggIC8/AFQCAAAA.',Ve='Veklinash:BAABLAAECoEYAAIKAAcIpwuViQB8AQAKAAcIpwuViQB8AQAAAA==.Versility:BAAALAAECgUICwAAAA==.',Vo='Voidpete:BAABLAAECoEUAAMjAAgIdAw0FwCxAQAjAAgIdAw0FwCxAQAbAAYIYARRSgDlAAAAAA==.Volgint:BAAALAADCgcIBwABLAAECgcIFAAGAPsPAA==.',Vy='Vyí:BAAALAADCgcICwAAAA==.',Wa='Wandi:BAAALAADCggIDgAAAA==.Warlocvirgin:BAAALAAECgQICAAAAA==.',We='Wexii:BAAALAADCggICAAAAA==.',Wh='Whó:BAAALAADCgcIDAAAAA==.',Wi='Wittle:BAAALAAECgQICQAAAA==.',Wo='Wolace:BAABLAAECoEdAAIeAAgINRGYBwAWAgAeAAgINRGYBwAWAgAAAA==.Woobies:BAAALAADCggICAAAAA==.Woobs:BAACLAAFFIEKAAIJAAUInhbnBACUAQAJAAUInhbnBACUAQAsAAQKgR4AAgkACAiFIu4QALwCAAkACAiFIu4QALwCAAAA.Worze:BAAALAAECgEIAQABLAAECgMIAwARAAAAAA==.',Xa='Xav:BAAALAAECgMIBgAAAA==.',Ya='Yaria:BAAALAAECgEIAQAAAA==.Yas:BAAALAADCgcIBwAAAA==.',Yl='Yleera:BAAALAADCggIDAAAAA==.',Za='Zalaryndos:BAAALAADCggIFgABLAAECgcIIAAGANIbAA==.Zandjil:BAABLAAECoEqAAMHAAgIzhFZWwDGAQAHAAgIzhFZWwDGAQAZAAcIIARKdADXAAAAAA==.Zargon:BAAALAADCgcIBwABLAAECggIIQAdACkSAA==.',Ze='Zekeyeager:BAAALAADCgYIDAAAAA==.Zellida:BAACLAAFFIEMAAICAAQIiyAeAQCQAQACAAQIiyAeAQCQAQAsAAQKgS4AAgIACAh4JZIBAGMDAAIACAh4JZIBAGMDAAAA.',Zo='Zork:BAAALAAECgMIBQAAAA==.',['Äl']='Älia:BAAALAADCgEIAQAAAA==.',['Ép']='Épíc:BAAALAAECggICAAAAA==.',['Ûl']='Ûltra:BAABLAAECoEaAAMjAAcIlh1vCwBWAgAjAAcIlh1vCwBWAgAbAAQI+RYhRgAIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end