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
 local lookup = {'Warrior-Protection','Unknown-Unknown','Mage-Arcane','Priest-Shadow','Priest-Holy','Druid-Restoration','DemonHunter-Havoc','Warrior-Fury','DemonHunter-Vengeance','Shaman-Elemental','Hunter-Marksmanship','Warrior-Arms','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Shaman-Restoration','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw','Priest-Discipline','Druid-Balance','Paladin-Retribution','Mage-Frost','Monk-Brewmaster','Evoker-Preservation','Druid-Feral','Evoker-Devastation','Paladin-Protection','Hunter-Survival','Rogue-Subtlety','Mage-Fire','Paladin-Holy','Evoker-Augmentation','DeathKnight-Unholy','Druid-Guardian','Shaman-Enhancement',}; local provider = {region='EU',realm='CultedelaRivenoire',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abaddøn:BAAALAAECgEIAQAAAA==.Abd:BAAALAAECgYICQAAAA==.',Ad='Adalyne:BAAALAADCgYIBgAAAA==.Adrastée:BAAALAADCggICAAAAA==.',Ah='Ahri:BAAALAADCgcIBwAAAA==.',Ai='Airyn:BAAALAAECgcIEgABLAAECggIIAABAPMcAA==.',Ak='Akanor:BAAALAAECgYIDwAAAA==.Aknu:BAAALAADCggICAAAAA==.',Al='Alcan:BAAALAAECgMIAwAAAA==.Alenzanar:BAAALAAECgYIDAAAAA==.Alindrei:BAAALAADCgYICgABLAAECgYIDAACAAAAAA==.',Am='Ambréa:BAAALAADCgIIAgAAAA==.Amystra:BAABLAAECoEdAAIDAAgIZxjAQAAlAgADAAgIZxjAQAAlAgAAAA==.',An='Angarrøs:BAACLAAFFIESAAIEAAYI5h+dAQBbAgAEAAYI5h+dAQBbAgAsAAQKgRYAAwQACAhGI4MMAP8CAAQACAhGI4MMAP8CAAUAAQipA0GnACcAAAAA.Anorah:BAAALAADCgcIBwABLAAFFAQICAAGAPgVAA==.Anthrias:BAABLAAECoEZAAIHAAcIFxs9TAAOAgAHAAcIFxs9TAAOAgAAAA==.',Ap='Apocalypse:BAACLAAFFIEIAAIHAAIIvhtjHQCvAAAHAAIIvhtjHQCvAAAsAAQKgRsAAgcACAiZIeAUAAADAAcACAiZIeAUAAADAAAA.',Ar='Archyna:BAAALAAECgYIEQAAAA==.Archéoptérix:BAABLAAECoEaAAIIAAcI2xraMQA4AgAIAAcI2xraMQA4AgAAAA==.Argaliade:BAAALAADCgcICAAAAA==.Arianator:BAAALAAECgYIDAAAAA==.Arihotter:BAABLAAECoEWAAIGAAgI7grAYQAqAQAGAAgI7grAYQAqAQAAAA==.Arinix:BAABLAAECoEVAAIEAAYIqgliVgAwAQAEAAYIqgliVgAwAQAAAA==.Ariwell:BAAALAADCggICAAAAA==.Arì:BAAALAADCggIFwAAAA==.',As='Ashkä:BAABLAAECoEaAAIJAAcIpBkNFAD9AQAJAAcIpBkNFAD9AQAAAA==.Asrai:BAAALAAECgMIAwAAAA==.Astador:BAACLAAFFIEOAAIKAAUIPh6UBQDfAQAKAAUIPh6UBQDfAQAsAAQKgSsAAgoACAilJVcEAGQDAAoACAilJVcEAGQDAAAA.',At='Athanael:BAAALAAECgYIDQAAAA==.Athinia:BAAALAADCgcIDgAAAA==.',Au='Aurthelëa:BAAALAADCgMIBAAAAA==.',Aw='Awaiken:BAAALAADCggICAAAAA==.',Ba='Baggio:BAAALAADCgcIFgAAAA==.Bahadoraan:BAAALAADCggIEAAAAA==.Bahrloup:BAAALAAECgcIDgAAAA==.Bahru:BAAALAAFFAIIAgAAAA==.Baldurn:BAAALAAECggICgAAAA==.',Be='Beanbag:BAAALAADCgUIBQABLAAECgYIEAACAAAAAA==.Behelit:BAAALAADCggICAABLAAECgcIFAALAN8fAA==.Belfynae:BAAALAADCggIEgAAAA==.Bemelial:BAAALAADCggICgAAAA==.Benjiiz:BAAALAAECgYICAAAAA==.',Bi='Bilow:BAAALAADCgcIEQAAAA==.Biniouche:BAAALAAECgYIEAAAAA==.',Bl='Blamethemonk:BAAALAAECgMIBQABLAAECgYIDAACAAAAAA==.Blamethesham:BAAALAAECgIIAgABLAAECgYIDAACAAAAAA==.',Bo='Boolvezoon:BAAALAAECgEIAQAAAA==.Boubours:BAAALAADCgMIAwAAAA==.Boulouparis:BAAALAADCgcICgAAAA==.',Br='Brook:BAAALAAECgQIBQAAAA==.',Bu='Bulamiou:BAAALAAECgUIBQABLAAECggIIQAMAO4hAA==.Bulasturu:BAAALAAECgUICAABLAAECggIIQAMAO4hAA==.Burningyou:BAAALAADCgUIBgAAAA==.Butwhysoez:BAAALAADCgcIBwABLAADCgIIAgACAAAAAA==.',['Bë']='Bëlk:BAAALAAECgYIBgAAAA==.',Ca='Canines:BAAALAADCggICgAAAA==.Cardarik:BAAALAADCggICAAAAA==.Carnagium:BAAALAAECgcIBwAAAA==.Cayn:BAAALAADCgEIAQABLAADCggIEQACAAAAAA==.',Ce='Ceerveau:BAAALAAECgcICAAAAA==.Cervida:BAAALAAFFAIIBAAAAA==.',Ch='Chamalgame:BAAALAADCgMIBgABLAAECgMIBQACAAAAAA==.Chassemax:BAAALAADCgMIAwAAAA==.Chaøstheøry:BAAALAAECgEIAQAAAA==.Chenoas:BAAALAAECgYIDAAAAA==.Chiroptera:BAAALAAECgUIBQAAAA==.Chouaky:BAAALAAECgMIBAAAAA==.',Ci='Cirgan:BAAALAADCggIDQAAAA==.',Ck='Ckrom:BAAALAAECgYIDwAAAA==.Ckromn:BAAALAAECgYICgAAAA==.',Cl='Clerica:BAAALAADCgcIDQAAAA==.Cloro:BAAALAADCggIIAAAAA==.Cléô:BAABLAAECoEXAAIGAAYIwhF7XAA7AQAGAAYIwhF7XAA7AQAAAA==.',Cr='Crodh:BAAALAAECgYIEAAAAA==.Croladin:BAAALAAECgUIBQABLAAFFAYIEgANAAgjAA==.Cronass:BAACLAAFFIESAAINAAYICCOPAgBqAgANAAYICCOPAgBqAgAsAAQKgSIABA0ACAgFJeAHAEkDAA0ACAgFJeAHAEkDAA4AAwgTHFgeAN0AAA8AAgjAHIdoAJgAAAAA.',Cy='Cyrosee:BAABLAAECoEhAAIHAAgIQA/9ZgDIAQAHAAgIQA/9ZgDIAQAAAA==.',['Cé']='Célestinette:BAABLAAECoEYAAIQAAcIgAzTkABVAQAQAAcIgAzTkABVAQAAAA==.',Da='Dalbafer:BAABLAAECoEeAAIRAAgIcRPCUAC+AQARAAgIcRPCUAC+AQAAAA==.Dalinar:BAAALAAECgYIDAAAAA==.Darklily:BAAALAADCgQIBAAAAA==.Darkäsh:BAAALAADCgIIAgAAAA==.Dawhz:BAAALAAECgUIBwAAAA==.Daxtôr:BAAALAAECgMIAwAAAA==.',De='Deathkermy:BAAALAAECgYIDgAAAA==.Dess:BAACLAAFFIEFAAISAAII5hQtOgCXAAASAAII5hQtOgCXAAAsAAQKgSMAAhIACAhlHKU0AHkCABIACAhlHKU0AHkCAAAA.',Dh='Dhanvatari:BAAALAAECgYICwABLAAFFAIIBQAFANgVAA==.Dhanvatarî:BAABLAAECoEVAAIRAAgIZBppKwA9AgARAAgIZBppKwA9AgABLAAFFAIIBQAFANgVAA==.Dharnam:BAACLAAFFIENAAITAAUIuR7TAAAMAgATAAUIuR7TAAAMAgAsAAQKgSAAAxMACAiIIRMPAKECABMACAg9IRMPAKECABQABwihHmoEAHYCAAAA.Dhänvatari:BAACLAAFFIEFAAIFAAII2BXvHACdAAAFAAII2BXvHACdAAAsAAQKgSQABAUACAj8IXUQAMwCAAUACAiLIHUQAMwCABUAAwj1JJ4UACoBAAQAAgh2Cyt6AGoAAAAA.',Di='Diazépam:BAAALAAECgEIAgAAAA==.Divy:BAAALAADCggIFwAAAA==.Divyfuki:BAAALAADCgYIBwABLAADCggIFwACAAAAAA==.Dixvy:BAAALAADCgcICQABLAADCggIFwACAAAAAA==.',Dk='Dköre:BAAALAAECggIDQAAAA==.',Do='Dorka:BAACLAAFFIEFAAISAAIIbxm/KACtAAASAAIIbxm/KACtAAAsAAQKgSAAAhIACAivIq0XAPcCABIACAivIq0XAPcCAAAA.Dothunderr:BAAALAADCgQIBAAAAA==.',Dr='Dreystïe:BAABLAAECoEbAAIFAAcIewzJUwBhAQAFAAcIewzJUwBhAQAAAA==.Drosera:BAAALAAECgYIBwAAAA==.Drøody:BAAALAAECgMIBQAAAA==.',Ds='Dsmoke:BAAALAAECgQIBQAAAA==.',Du='Durandal:BAAALAAECgUIBwAAAA==.',Ef='Efique:BAAALAAECgcIEwAAAA==.',El='Eldrytch:BAAALAADCgIIAgAAAA==.Ellana:BAAALAADCgEIAQAAAA==.Ellariell:BAAALAAECgYIBgABLAAFFAYIEwAVAI8QAA==.Elunael:BAACLAAFFIEIAAIGAAQI+BU3BgBQAQAGAAQI+BU3BgBQAQAsAAQKgSMAAwYACAjkIhoKAO8CAAYACAjkIhoKAO8CABYABgiqFSxCAHQBAAAA.Elzen:BAABLAAECoEUAAMRAAcI9xLcYACSAQARAAcI9xLcYACSAQAKAAEIagM3sgAhAAAAAA==.Elìhn:BAAALAAECgYIDQABLAAFFAIICQADAJ0fAA==.',En='Endeavor:BAAALAADCgYIBgAAAA==.Eniryphen:BAAALAAECgYICQAAAA==.Enwynn:BAAALAADCgEIAQAAAA==.',Er='Eracta:BAACLAAFFIEGAAIXAAII7BdNHACzAAAXAAII7BdNHACzAAAsAAQKgSYAAhcACAjPI6cNADQDABcACAjPI6cNADQDAAAA.Ergolias:BAAALAAECgYIDAAAAA==.',Es='Esfanar:BAAALAADCgIIAgABLAAFFAUIDgAKAD4eAA==.',Et='Etrinnøxe:BAAALAADCgUIBQAAAA==.',Eu='Euphy:BAAALAAECgIIAgAAAA==.',Ev='Evermoon:BAAALAAECgQIBwAAAA==.',Ez='Ezen:BAAALAADCggIEAABLAAECgcIFAARAPcSAA==.',Fa='Fanttom:BAAALAAECgcICAAAAA==.Faricha:BAAALAAECgIIAgAAAA==.',Fb='Fbademo:BAAALAADCgQIBQAAAA==.Fbahunt:BAAALAADCggICAAAAA==.',Fe='Feuillenoire:BAAALAADCgYICQAAAA==.',Fr='Friketta:BAAALAAECgYIEwAAAA==.Frostnova:BAABLAAECoEUAAIYAAcIlAyXNAB6AQAYAAcIlAyXNAB6AQAAAA==.',Fy='Fyrefoux:BAAALAAECgEIAgABLAAECggIKQASAIUbAA==.',['Fã']='Fãnfan:BAAALAADCgUIBQABLAAECgcICAACAAAAAA==.',Ga='Galoragran:BAAALAAECgEIAQABLAAFFAIIBQASAG8ZAA==.Ganikos:BAAALAAECgIIAgAAAA==.Gaëlle:BAAALAADCgEIAQAAAA==.',Ge='Gekkeiju:BAAALAAECgMIAwAAAA==.',Gh='Ghjuventu:BAAALAAECggICQAAAA==.',Go='Goug:BAABLAAECoEUAAMLAAYI5A4jbwDuAAAQAAUIXw0zugAAAQALAAUIXg0jbwDuAAABLAAECggICAACAAAAAA==.Goutev:BAAALAADCgUICQABLAAFFAUIDgAKAD4eAA==.',Gr='Gragdish:BAAALAAECgMIAwAAAA==.Grimliine:BAAALAAECgQIBAABLAAECgcIGQAZAOseAA==.Groshâa:BAAALAAECgYIEgAAAA==.',Ha='Haeli:BAABLAAECoEWAAIJAAgIBhvLCwBwAgAJAAgIBhvLCwBwAgAAAA==.Halfgrim:BAAALAADCgYIBgAAAA==.Hatchepsout:BAAALAADCgYIBgAAAA==.',He='Heka:BAAALAADCgYIBgAAAA==.Herrison:BAAALAADCgYIBgAAAA==.',Hi='Higeki:BAAALAAECggIEwAAAA==.Hioku:BAAALAADCgYICQAAAA==.Hirissa:BAAALAAECgIIAgABLAAECgcIGQAZAOseAA==.',Ho='Holda:BAAALAADCggICgAAAA==.Hollymarie:BAAALAADCggIEwAAAA==.Hollymolly:BAAALAADCgIIAgAAAA==.Houdizi:BAAALAAECgIIAgAAAA==.Hoxal:BAAALAAECgIIAwAAAA==.',['Hâ']='Hânaciole:BAAALAAECgQIBAAAAA==.',['Hü']='Hümer:BAAALAAECgMIAgAAAA==.',Ic='Icetomeetyou:BAAALAAECgIIAwAAAA==.',Il='Ilrys:BAAALAADCgcIBwAAAA==.',Im='Imodium:BAAALAAECgYIBwABLAAECggIJgARAFYcAA==.Impietoyable:BAAALAADCgcIBwAAAA==.',In='Indrä:BAAALAADCgcIBQAAAA==.',Is='Ishvald:BAAALAAECgYIBgAAAA==.',Iz='Izaliss:BAAALAADCgcIBwAAAA==.',Ja='Jademino:BAAALAAECgMIBAAAAA==.Jannelle:BAAALAAECgYICwAAAA==.',Je='Jeaneudes:BAAALAAECgYICwAAAA==.Jerouspette:BAAALAADCggICAAAAA==.Jesuislechat:BAAALAAECgUIBQAAAA==.',['Jø']='Jøÿce:BAABLAAECoEWAAIXAAcI7SCYLgCNAgAXAAcI7SCYLgCNAgAAAA==.',['Jù']='Jùstùs:BAAALAAECgcIEgABLAAECggICAACAAAAAA==.',Ka='Kabo:BAAALAAECgUICgAAAA==.Kadath:BAAALAAECgMIAwAAAA==.Kaharne:BAAALAAECgIIAgAAAA==.Kalhas:BAACLAAFFIEMAAITAAQIkRSpBABgAQATAAQIkRSpBABgAQAsAAQKgSsAAhMACAgUI8UGAAkDABMACAgUI8UGAAkDAAAA.Kallyst:BAAALAADCgUIBQAAAA==.Kamose:BAAALAADCgEIAQAAAA==.Kaonashi:BAAALAADCgUIBgAAAA==.Karhn:BAAALAADCggIDgABLAAECgIIAgACAAAAAA==.Kaurca:BAAALAADCgIIAgAAAA==.',Ke='Kelliana:BAAALAADCggICAAAAA==.Kermyd:BAAALAADCgYIBgAAAA==.Kermymelio:BAAALAAECgYIDAAAAA==.Kermytos:BAAALAADCgEIAQAAAA==.Kernel:BAAALAADCggIDAAAAA==.',Kh='Khorne:BAAALAADCggIDQABLAAECgIIAgACAAAAAA==.Khouri:BAAALAAECgEIAQAAAA==.',Ki='Kido:BAAALAADCgUIBQAAAA==.Kimbiel:BAAALAADCggICQAAAA==.Kiridormu:BAABLAAECoEUAAIaAAYIdguqIQAXAQAaAAYIdguqIQAXAQAAAA==.Kistahr:BAAALAADCggIDAAAAA==.',Kl='Klasher:BAAALAAECgYIBgAAAA==.Kléalaine:BAAALAAECgYIBgAAAA==.',Ko='Kondiac:BAAALAADCggIIQAAAA==.Korka:BAAALAADCgcIBgAAAA==.Koubiak:BAAALAAECgQIBgAAAA==.',Ky='Kyari:BAAALAAECgYICAABLAAFFAMICQAbAPwiAA==.Kyary:BAAALAAECgYICQAAAA==.Kyarï:BAAALAADCgUIBQABLAAFFAMICQAbAPwiAA==.Kyliane:BAABLAAECoEWAAIRAAYILBDAhwAxAQARAAYILBDAhwAxAQAAAA==.Kyokô:BAABLAAECoEaAAIKAAcIFRV1PADkAQAKAAcIFRV1PADkAQAAAA==.Kyôko:BAACLAAFFIEZAAMNAAYIxxguBQApAgANAAYIxxguBQApAgAPAAEIFAe5JABJAAAsAAQKgSYABA0ACAjuI64LACwDAA0ACAjuI64LACwDAA4ABghmBz8ZABwBAA8AAQgWGvB/AEMAAAAA.',['Kã']='Kãmi:BAAALAAECgIIAgAAAA==.',['Kæ']='Kælím:BAAALAADCgIIAgAAAA==.',['Kî']='Kîyoko:BAAALAAECgMIAwAAAA==.',La='Lam:BAAALAAECgYICQAAAA==.Lamaflo:BAAALAADCgcIBwAAAA==.Lapouttre:BAAALAAECggIBgAAAA==.Larsnic:BAABLAAECoEbAAIQAAcINiNcIgCUAgAQAAcINiNcIgCUAgAAAA==.Latueuse:BAAALAAECgYIEAAAAA==.Law:BAAALAAECgcIDQAAAA==.Lazaren:BAAALAAECggIEQAAAA==.',Le='Leolulu:BAAALAAECgcIEAABLAAECgcIFAALAN8fAA==.Letsuro:BAACLAAFFIEKAAIcAAQIFBfGBwBFAQAcAAQIFBfGBwBFAQAsAAQKgR8AAhwACAgGHqkNAL4CABwACAgGHqkNAL4CAAAA.Lexi:BAAALAAECgcIEAAAAA==.Leïkias:BAAALAADCgEIAQAAAA==.Leöla:BAACLAAFFIEIAAIXAAMILiZBCABWAQAXAAMILiZBCABWAQAsAAQKgSUAAxcACAgvJoYDAHkDABcACAgvJoYDAHkDAB0ABwiZCYg6AP0AAAAA.',Li='Liadrin:BAAALAADCgUIBAAAAA==.Lightpriest:BAAALAAECgYIBgAAAA==.Lilim:BAABLAAECoEhAAIWAAgIcRkfHABQAgAWAAgIcRkfHABQAgAAAA==.Lilitth:BAAALAADCgMIAwAAAA==.Liloodana:BAAALAAECgQIBwAAAA==.Lisindra:BAAALAADCgcIFAAAAA==.Lithìum:BAABLAAECoEkAAIeAAgIoiSZAABlAwAeAAgIoiSZAABlAwAAAA==.',Lo='Lodjay:BAEALAAECggICAAAAA==.Lohkï:BAABLAAECoEUAAITAAYIZwyPOwBUAQATAAYIZwyPOwBUAQAAAA==.Lohlâh:BAABLAAECoEbAAIfAAcIiBJdGgCVAQAfAAcIiBJdGgCVAQAAAA==.Loonette:BAAALAADCggICAAAAA==.Loreth:BAAALAAECgEIAQAAAA==.Loupmiere:BAAALAADCgIIAgAAAA==.',Lu='Luxvincit:BAAALAAECgUIBgABLAAECgYICAACAAAAAA==.',Ly='Lyanà:BAABLAAECoEYAAIQAAgIFQZXxgDgAAAQAAgIFQZXxgDgAAAAAA==.Lycandaemon:BAAALAADCggIDwAAAA==.',['Lâ']='Lâgoa:BAABLAAECoEcAAINAAgIfwx+VgC1AQANAAgIfwx+VgC1AQAAAA==.',['Lø']='Løweell:BAAALAADCgIIAwAAAA==.',['Lù']='Lùnà:BAAALAADCggIEgAAAA==.',['Lý']='Lýnñ:BAAALAAECgMIAwAAAA==.',['Lÿ']='Lÿnñ:BAACLAAFFIEFAAIDAAMIXRnAGQDxAAADAAMIXRnAGQDxAAAsAAQKgRwABAMACAhLH24kAKMCAAMACAhLH24kAKMCACAAAQiGDAIeADYAABgAAQhGBzGEACYAAAEsAAQKCAgUAAcA+hwA.Lÿñn:BAABLAAECoEUAAIHAAgI+hzxIgCxAgAHAAgI+hzxIgCxAgAAAA==.',Ma='Madjak:BAAALAADCgUIBQAAAA==.Mahlat:BAAALAADCggIDQAAAA==.Mahìro:BAACLAAFFIEHAAIPAAQI8hiWAAB0AQAPAAQI8hiWAAB0AQAsAAQKgSkAAg8ACAhEJLwCADwDAA8ACAhEJLwCADwDAAAA.Maistespalà:BAACLAAFFIEGAAIXAAQItCAVBwCAAQAXAAQItCAVBwCAAQAsAAQKgRYAAxcACAgQJskEAG4DABcACAgQJskEAG4DAB0AAwhRHuRHAKMAAAAA.Malgora:BAABLAAECoEbAAIEAAcIwhYnMQDkAQAEAAcIwhYnMQDkAQAAAA==.Marhuul:BAAALAADCgIIAgAAAA==.Marianagetth:BAABLAAECoEZAAIQAAcIqhjyWQDPAQAQAAcIqhjyWQDPAQAAAA==.Massaia:BAAALAADCggIEwAAAA==.Mattack:BAAALAADCggIDwAAAA==.',Me='Meawhz:BAACLAAFFIEHAAIWAAMILhq7CQD3AAAWAAMILhq7CQD3AAAsAAQKgSAAAxYACAgxJgACAHYDABYACAgxJgACAHYDABsAAgjgIbQvALwAAAAA.Megumi:BAAALAADCgMIAwAAAA==.Melenix:BAAALAAFFAIIAgAAAA==.Menellia:BAAALAAECgQICAAAAA==.Menøk:BAAALAAECgYIDwAAAA==.Merlline:BAAALAADCgYIBgAAAA==.Mernal:BAABLAAECoEZAAIZAAcI6x6TDQBRAgAZAAcI6x6TDQBRAgAAAA==.Merüem:BAAALAAECgUIBQAAAA==.Mezrial:BAAALAAECgUICgAAAA==.',Mi='Mikatsuki:BAAALAADCgIIAgAAAA==.Mirawen:BAAALAADCggIEgAAAA==.',Mo='Moggrash:BAAALAADCgUIBQAAAA==.Mokatini:BAAALAADCgYIBgAAAA==.Moomoone:BAAALAAECgYIDgAAAA==.Mourohi:BAAALAAECggIDAAAAA==.Moÿa:BAAALAAECgcIBwAAAA==.',My='Myrhia:BAAALAAECgIIAgAAAA==.Myzedion:BAAALAADCggICAAAAA==.',['Mà']='Màw:BAAALAADCgcICwAAAA==.',['Mâ']='Mâdalas:BAAALAAECgYIBgAAAA==.',['Mã']='Mãnu:BAABLAAECoEYAAISAAYITh1YbADlAQASAAYITh1YbADlAQAAAA==.',['Më']='Mënëlle:BAAALAADCgMIAwAAAA==.',['Mî']='Mîzû:BAAALAAECggICAAAAA==.',Na='Nabucor:BAAALAADCgYICgAAAA==.Naelwë:BAAALAADCgcIBwAAAA==.Nahilaga:BAAALAAECgUIDAAAAA==.Naikina:BAAALAADCggICAAAAA==.Nam:BAACLAAFFIEbAAIdAAYI/R2rAAAyAgAdAAYI/R2rAAAyAgAsAAQKgTAABB0ACAgMJn4BAHADAB0ACAgDJn4BAHADABcABAgPI+KNAJwBACEABAjXD2hLAN0AAAAA.Nanili:BAAALAAECgYIBgAAAA==.Narcée:BAABLAAECoEVAAITAAgIAgriKQC8AQATAAgIAgriKQC8AQAAAA==.Naïmpørtekoï:BAAALAAECggICAAAAA==.',Ne='Nemrød:BAAALAADCggICAAAAA==.Nerako:BAAALAAECgYIDgAAAA==.Neytiriri:BAAALAAECgEIAQAAAA==.',Ni='Niriya:BAAALAAECgYIEQAAAA==.',No='Noctürne:BAAALAADCgIIAwAAAA==.Notsitham:BAAALAAECgYIDAAAAA==.',Nu='Nulhdbriqa:BAAALAAECgcIEwAAAA==.Nulhiedbriks:BAAALAAECgUICAAAAA==.',Ny='Nyataìga:BAAALAADCgcIBwAAAA==.Nyhra:BAABLAAECoEsAAMXAAgIGSLBFgABAwAXAAgIGSLBFgABAwAdAAEIcQwIXQA0AAAAAA==.Nyoko:BAAALAAECgEIAQAAAA==.Nystrala:BAAALAAECgYIEAAAAA==.',['Nâ']='Nâpälhm:BAABLAAECoEWAAINAAYIGQhijgAaAQANAAYIGQhijgAaAQAAAA==.',['Né']='Nédar:BAAALAAECgIIAgAAAA==.',['Nî']='Nîshiro:BAAALAADCggIDgABLAAECgcIFAAJAMIHAA==.',Ok='Okaboto:BAAALAAECgMIBAABLAAFFAIIBQASAG8ZAA==.',Ol='Olórine:BAAALAADCgMIAwAAAA==.',Or='Orcqtf:BAAALAADCgYIBgAAAA==.Orkalithed:BAAALAADCgYIBgABLAAECgMIBAACAAAAAA==.',Ot='Otelavie:BAAALAADCggICAAAAA==.',Oz='Ozy:BAAALAAECgMIAgAAAA==.',Pa='Painaulait:BAACLAAFFIEJAAIcAAUI9w83BgCEAQAcAAUI9w83BgCEAQAsAAQKgSQAAhwACAjcIskFACcDABwACAjcIskFACcDAAAA.Paladinouse:BAAALAAECgEIAQAAAA==.Paloss:BAAALAADCgIIAgAAAA==.Pandöre:BAAALAADCgQIBAABLAAECggIHQADAGcYAA==.Papï:BAABLAAECoEdAAIQAAYIDBiFcACYAQAQAAYIDBiFcACYAQAAAA==.',Pe='Peach:BAAALAAECgYIEgABLAAFFAMIAwACAAAAAA==.Pelviss:BAABLAAECoEeAAMYAAgIMyPSBQAiAwAYAAgIMyPSBQAiAwADAAEI8wAi6wAJAAAAAA==.Petroshka:BAAALAADCgcIBwAAAA==.',Ph='Phantøm:BAABLAAECoEZAAISAAgINAbB1wAmAQASAAgINAbB1wAmAQAAAA==.Phylahisse:BAAALAAECgIIAgAAAA==.Phøenix:BAAALAAECgYIEQAAAA==.',Pi='Piconorval:BAABLAAECoEmAAIRAAgIVhwcGgCPAgARAAgIVhwcGgCPAgAAAA==.Piper:BAAALAADCgQIBQAAAA==.Pipoujean:BAAALAADCggICAAAAA==.Pirlø:BAAALAAECgYICwAAAA==.',Po='Poètepouette:BAACLAAFFIEIAAIcAAQIFxG7CAAnAQAcAAQIFxG7CAAnAQAsAAQKgSQAAxwACAiYH10MAM4CABwACAiYH10MAM4CACIAAQgiEUYVAEAAAAAA.',Pr='Priem:BAAALAAECgMIAwAAAA==.',['Pÿ']='Pÿx:BAAALAADCgIIAgABLAAECgYIDgACAAAAAA==.',Qn='Qnx:BAAALAAECgMIAwABLAAFFAIIAgACAAAAAA==.',Ra='Rabbimonga:BAAALAAECgEIAQAAAA==.Radokahn:BAABLAAECoEYAAIjAAgIohrOCgCOAgAjAAgIohrOCgCOAgAAAA==.Raehnyria:BAACLAAFFIEGAAIQAAMI4Q2WFgDIAAAQAAMI4Q2WFgDIAAAsAAQKgSYAAxAACAjhIBsbAL4CABAACAjhIBsbAL4CAAsAAggRFlaRAHQAAAAA.Rafallan:BAABLAAECoEcAAIbAAcI/hRsFQDbAQAbAAcI/hRsFQDbAQAAAA==.Raffiq:BAABLAAECoEXAAMXAAcI0ByeQgBHAgAXAAcI0ByeQgBHAgAhAAMIBwIaXQBhAAAAAA==.Rahjã:BAAALAADCgYIBgAAAA==.Raquell:BAAALAADCgMIAwAAAA==.Rayaa:BAAALAAECgIIAwAAAA==.Raylleiigh:BAAALAADCggICAAAAA==.Rayure:BAAALAADCgMIAwAAAA==.Razbitum:BAABLAAECoEhAAMNAAgIvRZINgAwAgANAAgIvRZINgAwAgAPAAgITQvFKQCsAQAAAA==.Razfrost:BAABLAAECoEaAAIYAAYI7SJMFQBNAgAYAAYI7SJMFQBNAgABLAAFFAMIAwACAAAAAA==.Razgaroth:BAAALAADCgIIAgAAAA==.Raziell:BAABLAAECoEZAAIXAAYI+iLUPQBVAgAXAAYI+iLUPQBVAgAAAA==.Razvan:BAAALAAFFAMIAwAAAA==.',Re='Republïc:BAAALAAECggIDwAAAA==.Rev:BAAALAAECggIEwAAAA==.Revilock:BAACLAAFFIEOAAMPAAUIniLmAABFAQANAAQI+SCqDQCJAQAPAAMIVSXmAABFAQAsAAQKgS8ABA8ACAijJmMAAI0DAA8ACAiTJmMAAI0DAA0ACAiPI7kMACUDAA4ABwh6H/4FAF8CAAAA.Reynath:BAAALAADCggIDwAAAA==.',Ri='Riâwesoi:BAAALAAECgEIAQABLAAECgYIJgACAAAAAQ==.',Ro='Roykard:BAAALAADCgIIAgAAAA==.Royzal:BAAALAAECgQIBAAAAA==.',Rv='Rvii:BAABLAAECoEeAAIWAAYItR9sIAAuAgAWAAYItR9sIAAuAgABLAAFFAUIDgAPAJ4iAA==.',['Rã']='Rãyla:BAAALAAFFAEIAQABLAAFFAYIEwAVAI8QAA==.',['Ré']='Révi:BAABLAAECoEZAAIIAAYIkxsjSQDaAQAIAAYIkxsjSQDaAQABLAAFFAUIDgAPAJ4iAA==.',Sa='Sakreth:BAABLAAECoEXAAISAAgI1w4TkgCcAQASAAgI1w4TkgCcAQAAAA==.Sanspapier:BAAALAADCgYIBgAAAA==.Saïa:BAAALAAECgEIAQAAAA==.Saïyan:BAAALAADCgcIDgAAAA==.Saûl:BAAALAADCgYIBgAAAA==.',Sc='Schokette:BAAALAADCgMIAwAAAA==.Schtrøumpf:BAABLAAECoEUAAIQAAcI8Re4YQC7AQAQAAcI8Re4YQC7AQAAAA==.',Se='Selkyhs:BAAALAADCgQIBAAAAA==.Senjiî:BAACLAAFFIEJAAIRAAMIeBbTDgDnAAARAAMIeBbTDgDnAAAsAAQKgSsAAhEACAjrHjUZAJQCABEACAjrHjUZAJQCAAAA.Senjïï:BAAALAAECgMIBAAAAA==.Serenis:BAAALAAECggIEwAAAA==.',Sh='Shakal:BAAALAADCggICwAAAA==.Shawn:BAABLAAECoEUAAILAAcI3x+pGACHAgALAAcI3x+pGACHAgAAAA==.Shinora:BAAALAAECgMICQAAAA==.Shiraak:BAABLAAECoEhAAMdAAcIFh77DgBiAgAdAAcIFh77DgBiAgAXAAcItAuCqQBpAQAAAA==.Shyue:BAABLAAECoEiAAIYAAgIkyPZBAAyAwAYAAgIkyPZBAAyAwAAAA==.Shàe:BAAALAADCggICAAAAA==.',Si='Sidonï:BAAALAAECgYICAAAAA==.Silaennas:BAAALAADCggIDwAAAA==.Silverhoof:BAAALAADCggICwAAAA==.',Sk='Skios:BAAALAAECgYICQABLAAECggIKQASAIUbAA==.Skipy:BAAALAAECgIIBAAAAA==.Skynokk:BAABLAAECoEpAAISAAgIhRuUOgBlAgASAAgIhRuUOgBlAgAAAA==.Skyppi:BAAALAAECgYIDAAAAA==.',Sl='Slaquovitz:BAAALAADCggIFgAAAA==.',So='Solosimpi:BAAALAAECgYIBgAAAA==.',Sq='Sqaky:BAAALAAECgYIDAABLAAECggIJgARAFYcAA==.',Sr='Srimar:BAAALAAECgEIAQAAAA==.',St='Stropo:BAAALAAECgYICAAAAA==.Størm:BAAALAAECgYIEgAAAA==.',Su='Suréya:BAAALAADCgcIDAAAAA==.Susfice:BAAALAAECgIIAgAAAA==.',Sy='Sylestheria:BAAALAADCgUICQAAAA==.Syre:BAACLAAFFIETAAIVAAYIjxAbAADsAQAVAAYIjxAbAADsAQAsAAQKgSIAAxUACAhKIjUBAB4DABUACAhKIjUBAB4DAAUACAjyBBlaAEoBAAAA.',['Sä']='Sätos:BAAALAAECgYIBwAAAA==.',['Sé']='Séphira:BAABLAAECoEmAAIhAAgINyL6BAAAAwAhAAgINyL6BAAAAwAAAA==.',['Sî']='Sîg:BAAALAAECgMIAwAAAA==.',['Sø']='Søllek:BAAALAAECgcIEwAAAA==.',Ta='Tahk:BAACLAAFFIEFAAIGAAMIgRp+CQAEAQAGAAMIgRp+CQAEAQAsAAQKgRcAAgYACAjHITYJAPgCAAYACAjHITYJAPgCAAAA.Takouchka:BAAALAAECgYICAAAAA==.Tankmänia:BAABLAAECoEZAAIBAAcI/Q9MNwBhAQABAAcI/Q9MNwBhAQAAAA==.Tarporion:BAAALAADCgIIAgAAAA==.Tatyova:BAAALAAECgIIAgAAAA==.Tayanah:BAAALAAECgQIBAAAAA==.Taÿxa:BAAALAAECgYIDAAAAA==.',Tc='Tchointchoïn:BAAALAAECgIIAgAAAA==.',Th='Tharon:BAAALAAECggICAAAAA==.Thæærølf:BAABLAAECoEWAAIXAAYIdCLqPgBRAgAXAAYIdCLqPgBRAgAAAA==.',Ti='Tibabia:BAAALAADCgcIBwAAAA==.Tinkera:BAAALAADCgMIAwAAAA==.',To='Tohoka:BAAALAADCgMIAwAAAA==.Tonkh:BAAALAAECgYICgAAAA==.Torentule:BAAALAAECgMIBAAAAA==.Torment:BAAALAADCggICAAAAA==.Totenna:BAAALAADCgUIBgAAAA==.',Tr='Trapiste:BAAALAADCggICgABLAAECgMIBQACAAAAAA==.Troudelasecu:BAAALAADCgYIBwAAAA==.Tryxe:BAAALAAECggIEAAAAA==.',Ts='Tsiganok:BAAALAADCggICAAAAA==.',Tu='Turquoise:BAAALAAECgUIBQABLAAECgcIEAACAAAAAA==.',['Tî']='Tîïk:BAAALAADCgQIBAABLAAECgIIAgACAAAAAA==.',['Tø']='Tøreno:BAAALAADCgEIAQAAAA==.Tørïko:BAAALAAECgIIAgAAAA==.',Ul='Ulltima:BAAALAAECgIIAgAAAA==.',Ut='Utrhed:BAAALAAECgYICwAAAA==.',Va='Valak:BAAALAAECgEIAQAAAA==.Valeme:BAABLAAECoEYAAIkAAcIGxVeDQDEAQAkAAcIGxVeDQDEAQAAAA==.Valtme:BAAALAADCgIIAgAAAA==.Varkas:BAAALAAECgIIAgAAAA==.',Ve='Vengeresse:BAAALAAECggIBwAAAA==.Venthress:BAAALAAECgQIBAAAAA==.',Vi='Vickky:BAAALAADCgQIBAAAAA==.Vindispel:BAAALAADCggICgAAAA==.Vitta:BAABLAAECoEgAAIlAAgI4BcdBwB9AgAlAAgI4BcdBwB9AgAAAA==.',Vo='Volg:BAABLAAECoEfAAIIAAgIeByfHAC0AgAIAAgIeByfHAC0AgABLAAFFAUIDgAKAD4eAA==.Volkiro:BAAALAAECgEIAQAAAA==.Volthâs:BAAALAAECgcIBwAAAA==.',['Vü']='Vülcain:BAAALAAECgEIAQAAAA==.',We='Weis:BAAALAADCgIIAgABLAAFFAIIBAACAAAAAA==.',Wh='Whiskers:BAAALAAECgMIAwAAAA==.',Wi='Winepress:BAAALAADCgcICQABLAAECgcICAACAAAAAA==.Wismeryl:BAAALAAECgYIEAAAAA==.',['Wé']='Wérra:BAACLAAFFIEGAAILAAMI9xKsDgDMAAALAAMI9xKsDgDMAAAsAAQKgRUAAwsACAg2FVI1AMsBAAsACAg2FVI1AMsBABAAAggOD3H4AF4AAAAA.',['Wî']='Wîkï:BAAALAAECgQIBgABLAAECggIGAAHAOkTAA==.',['Wï']='Wïkî:BAABLAAECoEYAAIHAAgI6ROeZQDLAQAHAAgI6ROeZQDLAQAAAA==.',Xa='Xaelis:BAAALAAECgYIDQAAAA==.',Xe='Xei:BAAALAADCgYIBgABLAAFFAMICQAbAPwiAA==.Xenea:BAAALAAECggICQAAAA==.Xenophon:BAACLAAFFIEJAAIbAAMI/CL/AgA8AQAbAAMI/CL/AgA8AQAsAAQKgSQAAhsACAhWJKACAD4DABsACAhWJKACAD4DAAAA.Xeï:BAAALAAECgYIEgABLAAFFAMICQAbAPwiAA==.Xeïna:BAAALAAECgYICgABLAAFFAMICQAbAPwiAA==.',Xi='Xióng:BAAALAADCgcIAgAAAA==.',Ya='Yako:BAABLAAECoEWAAIIAAcI+xVISADdAQAIAAcI+xVISADdAQAAAA==.',Yl='Ylanâa:BAABLAAECoEgAAIbAAgI4g0bGgCkAQAbAAgI4g0bGgCkAQAAAA==.',Yo='Yokozuna:BAAALAADCggICQABLAAECgcIGAABACEWAA==.Yoshîmura:BAAALAAECgIIAgAAAA==.',['Yù']='Yùrik:BAAALAADCgQIBwAAAA==.',Za='Zalès:BAAALAAECgEIAQAAAA==.',Ze='Zemné:BAAALAAECgYIBgABLAAFFAUIDgAKAD4eAA==.Zerothen:BAABLAAECoEUAAMJAAcITB7PEQAZAgAJAAYIKSHPEQAZAgAHAAMI0RY90QDfAAAAAA==.',Zi='Zinøtrïx:BAABLAAECoEVAAILAAYIiAzeYQAaAQALAAYIiAzeYQAaAQAAAA==.',Zk='Zkèz:BAAALAAECgEIAQAAAA==.',Zu='Zuldân:BAABLAAECoEZAAIPAAgIhBJTGAAXAgAPAAgIhBJTGAAXAgAAAA==.',Zz='Zzccmxtp:BAAALAAECgYIDAAAAA==.',['Âm']='Âmnésïa:BAAALAAECgYIDwAAAA==.',['Ât']='Âtilâ:BAAALAAECggIDwAAAA==.',['Äw']='Äwhz:BAAALAADCgIIAgAAAA==.',['Åt']='Åtreyu:BAAALAAECgcICwAAAA==.',['Åz']='Åzeroth:BAAALAADCgcIBwAAAA==.',['Æl']='Ælith:BAAALAAECgYICwAAAA==.',['Ìg']='Ìggy:BAAALAADCgUIBQAAAA==.',['Ðe']='Ðeathnote:BAAALAAECgYIEgAAAA==.',['Ør']='Ørikan:BAABLAAECoEeAAMEAAcILhJBOAC8AQAEAAcILhJBOAC8AQAVAAEIHxuYLABNAAAAAA==.',['Øs']='Øsabi:BAABLAAECoEUAAIJAAcIwgf3LwAAAQAJAAcIwgf3LwAAAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end