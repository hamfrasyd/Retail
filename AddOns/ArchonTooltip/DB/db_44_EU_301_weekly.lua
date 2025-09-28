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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Monk-Windwalker','Hunter-BeastMastery','Evoker-Preservation','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Blood','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Priest-Shadow','Paladin-Holy','Warrior-Protection','Warrior-Fury','Druid-Balance','Paladin-Protection','Monk-Brewmaster','Shaman-Enhancement','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Affliction','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Priest-Holy','Hunter-Survival','Rogue-Outlaw','Mage-Arcane','Priest-Discipline','Druid-Feral','Mage-Frost','Warrior-Arms','Evoker-Devastation','Evoker-Augmentation',}; local provider = {region='EU',realm='Hellscream',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ad='Adara:BAAALAAECgcIBwABLAADCgQIBAABAAAAAA==.Adeline:BAABLAAECoEUAAICAAYIwxTzZACGAQACAAYIwxTzZACGAQAAAA==.',Ae='Aei:BAAALAAECgcICAAAAA==.',Af='Afk:BAAALAAECgYICAAAAA==.',Ag='Agrajag:BAAALAADCgcIBwAAAA==.',Ai='Aib:BAAALAAECggICAAAAA==.Aibelf:BAACLAAFFIETAAIDAAYIVx2qAQDvAQADAAYIVx2qAQDvAQAsAAQKgS8AAgMACAh2JoEAAIsDAAMACAh2JoEAAIsDAAAA.Aile:BAAALAADCggICAAAAA==.',Al='Algisham:BAABLAAECoEhAAICAAgIhxZ+MABHAgACAAgIhxZ+MABHAgAAAA==.Alitakos:BAAALAAECgYIDAAAAA==.Alive:BAAALAAECgcIBwAAAA==.Allwin:BAABLAAECoEXAAIEAAYINRGujgBTAQAEAAYINRGujgBTAQAAAA==.Alonedragon:BAAALAADCgIIAgAAAA==.Altran:BAAALAADCggICAAAAA==.Alzarinet:BAABLAAECoEhAAIFAAgIpR1zBgCwAgAFAAgIpR1zBgCwAgAAAA==.',Am='Amathera:BAAALAADCgYICQAAAA==.Amberlea:BAAALAAECgcICwAAAA==.',An='Anglaran:BAAALAAECgYIDgAAAA==.Anthet:BAAALAAECgcIBwAAAA==.Anvar:BAAALAAECgIIAwAAAA==.Anyadelgado:BAAALAAECgYIBgABLAAECgYIHgAEAJAbAA==.',Ar='Aragan:BAAALAADCgUICAAAAA==.Arbalest:BAACLAAFFIEQAAIGAAYIMRTBBADBAQAGAAYIMRTBBADBAQAsAAQKgS8AAgYACAh7JTwIAFUDAAYACAh7JTwIAFUDAAAA.Arcyan:BAAALAADCgcIFwAAAA==.Ardor:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Argoz:BAAALAAECgMIAwAAAA==.Arnfinnson:BAAALAADCggICAAAAA==.Arssling:BAAALAAECgYIEgAAAA==.Arywal:BAABLAAFFIEKAAMHAAII8gzaSgCJAAAHAAIIFAvaSgCJAAAIAAII2QhODQBsAAAAAA==.',As='Asir:BAACLAAFFIENAAIEAAUInRkzCAB0AQAEAAUInRkzCAB0AQAsAAQKgSYAAwQACAjuJHkEAFsDAAQACAjuJHkEAFsDAAkAAwihDzSNAH0AAAAA.Asirdam:BAACLAAFFIEKAAMKAAUITxyGCAA6AQAKAAQI2SGGCAA6AQALAAMISQpNEADoAAAsAAQKgSUAAwsACAhyHbMVAMoCAAsACAhyHbMVAMoCAAoABgjaJmAYAJYCAAAA.Asiru:BAAALAAFFAIIBAABLAAFFAUIDQAEAJ0ZAA==.',Au='Aurae:BAABLAAECoEYAAIMAAcICx78GACJAgAMAAcICx78GACJAgAAAA==.',Av='Avirondeloco:BAAALAAECgYIDwABLAAECgcIBwABAAAAAA==.',Az='Azhe:BAABLAAECoEdAAINAAcIeyF3CwCgAgANAAcIeyF3CwCgAgAAAA==.Azoog:BAAALAADCgYIBgAAAA==.',Ba='Badbox:BAAALAADCggICAAAAA==.Baldúr:BAAALAAECgYICwAAAA==.Bankebiff:BAABLAAECoEZAAMOAAcIHSRKCwDMAgAOAAcIHSRKCwDMAgAPAAYIRh6xTQDGAQAAAA==.Basíl:BAAALAADCgIIAgABLAADCgQIBAABAAAAAA==.Batholith:BAABLAAECoEoAAIHAAgIpSWtBABmAwAHAAgIpSWtBABmAwAAAA==.Battlehenk:BAAALAADCgcIBwAAAA==.',Be='Beana:BAAALAADCggICAAAAA==.Bearlyready:BAAALAAECgQIBAABLAAECggIJgAEALEbAA==.Beermonster:BAABLAAECoEXAAIGAAYIEQ25swBSAQAGAAYIEQ25swBSAQAAAA==.Bellavonn:BAAALAADCggICAAAAA==.Belverinia:BAAALAAECgEIAgAAAA==.Berryblast:BAAALAAECgQIBAAAAA==.',Bi='Bigerrzor:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.Bini:BAACLAAFFIETAAIQAAYIWiS9AwDCAQAQAAYIWiS9AwDCAQAsAAQKgS8AAhAACAjwJisAAJ8DABAACAjwJisAAJ8DAAAA.Binidh:BAAALAAECgYIBgABLAAFFAYIEwAQAFokAA==.Binifromage:BAAALAAECgYICgABLAAFFAYIEwAQAFokAA==.',Bl='Blackdk:BAAALAAECgIIAgAAAA==.Blindslice:BAAALAADCggIGAAAAA==.Bloodaxe:BAAALAAECgUIBQAAAA==.Bluwind:BAAALAAECgUIDwAAAA==.',Bo='Bobby:BAAALAADCggIDwAAAA==.Bobleif:BAAALAADCgQIBAAAAA==.Boldragon:BAABLAAECoEYAAIRAAcI6iKKCADIAgARAAcI6iKKCADIAgAAAA==.Bolinha:BAAALAAECggIEwAAAA==.Bonlo:BAABLAAECoEhAAISAAgIdBw6DABnAgASAAgIdBw6DABnAgAAAA==.Boxie:BAAALAAECggIEwAAAA==.Boótybandit:BAAALAADCgMIAwAAAA==.',Br='Brawen:BAAALAADCgUIBgAAAA==.Brawler:BAAALAADCggICwAAAA==.Bromm:BAAALAAECgIIBAAAAA==.Brutobjonsk:BAABLAAECoEXAAITAAYIEhynDAD0AQATAAYIEhynDAD0AQAAAA==.',Bu='Bubbleguts:BAAALAAECgEIAQAAAA==.Bubblun:BAAALAAECgUICAAAAA==.Bugs:BAAALAADCggIDwAAAA==.Bunji:BAAALAAECgQIBgAAAA==.Buyukaltay:BAAALAAECgYIEwABLAAECgYIHgAEAJAbAA==.',['Bà']='Bàbaluba:BAAALAADCgcIDAAAAA==.',['Bá']='Bálor:BAAALAADCggICwAAAA==.',['Bé']='Béany:BAAALAAECgIIAgABLAAECgYIEAABAAAAAA==.',['Bë']='Bërserk:BAAALAAECggIDgAAAA==.',Ca='Camonk:BAACLAAFFIELAAIUAAMIax1gBgD8AAAUAAMIax1gBgD8AAAsAAQKgS4AAxQACAisHCwKAJwCABQACAisHCwKAJwCAAMABghpFmsoAIYBAAAA.',Cc='Ccreuss:BAAALAAECgQIBAAAAA==.',Ce='Ceralix:BAAALAAECgUIDwAAAA==.',Ch='Changa:BAAALAADCggICwAAAA==.Cherry:BAAALAAECggICAAAAA==.Chrovo:BAAALAADCgYIAgAAAA==.Chumaka:BAAALAAECgIIAwAAAA==.',Ci='Cindarella:BAAALAADCgcIBwAAAA==.',Co='Comet:BAAALAADCggICAAAAA==.',Cr='Crab:BAAALAADCggIDwAAAA==.Craggle:BAAALAAECgMIAwAAAA==.',Cy='Cyclo:BAAALAAECggICQAAAA==.Cyrogen:BAABLAAECoEaAAMLAAcImCBXHwB/AgALAAcImCBXHwB/AgAKAAIIUxn53gB9AAAAAA==.',Da='Daniael:BAAALAAECgMIAwAAAA==.Darclu:BAAALAADCgcIBwAAAA==.Darkjuri:BAAALAADCgQIBAAAAA==.Darladin:BAAALAAECgYIDAAAAA==.Darthraxxion:BAABLAAECoEiAAMVAAgI7yJYDwAfAwAVAAgI7yJYDwAfAwAWAAEI5Bi2VgAsAAAAAA==.Daruude:BAAALAAECgYIBgAAAA==.',De='Deadméat:BAAALAAECgYIBgAAAA==.Deadnoodle:BAAALAAECgEIAQAAAA==.Deathleif:BAAALAAECgYIBgAAAA==.Deathlyblade:BAAALAAECgYIDgAAAA==.Deathpulse:BAAALAAECgcIDQAAAA==.Deathtankz:BAAALAADCggIDwAAAA==.Decailin:BAAALAAECgYICgAAAA==.Definitely:BAAALAADCggIBwABLAAECgcIGQAKADgeAA==.Demeetriks:BAAALAAECgYIBgAAAA==.Demonzac:BAAALAAECggICgAAAA==.Dezrath:BAAALAAECgYIEQAAAA==.',Di='Diedtrying:BAAALAAECgEIAQAAAA==.Dimz:BAABLAAECoEVAAIPAAYIDhcsUAC+AQAPAAYIDhcsUAC+AQAAAA==.',Dm='Dmoc:BAABLAAECoElAAQCAAgIRiAVMgBAAgACAAcIJB0VMgBAAgAXAAQIDyInLwCOAQAYAAEIKiO3LQBpAAAAAA==.',Do='Domienator:BAAALAAECggIEAAAAA==.Dottingkalle:BAAALAADCggIDwAAAA==.',Dr='Dragleif:BAAALAAECgUIBQAAAA==.Draigor:BAABLAAECoEXAAMRAAYI7RTjLABSAQARAAYI7RTjLABSAQAGAAMI3giMFwFsAAAAAA==.Drakkrim:BAAALAAECgYIBgAAAA==.Draksir:BAAALAAFFAMIAwABLAAFFAUIDQAEAJ0ZAA==.Dralro:BAACLAAFFIETAAMZAAUIcxSGBAAvAQAZAAUI2g6GBAAvAQAaAAMIEg77CAAGAQAsAAQKgS8AAxkACAhxH30FAN0CABkACAgAH30FAN0CABoABwgMFsEqALQBAAAA.Draupnir:BAAALAAECgMIAwAAAA==.Draven:BAAALAADCggIDgAAAA==.Draxal:BAAALAADCggIEwAAAA==.Drayden:BAAALAAECgYIDAAAAA==.Dreamstraza:BAAALAAECgQIBAAAAA==.Drincredible:BAAALAADCgcIBwAAAA==.Drippingfang:BAABLAAECoEcAAMLAAgIDA6TQADOAQALAAgIDA6TQADOAQAKAAcIjgaBqwDhAAAAAA==.Drusturbate:BAAALAAECggICQAAAA==.',Du='Dudupirate:BAAALAAECggICwAAAA==.',['Dæ']='Dæmonpasta:BAAALAADCgUIBQAAAA==.',Ei='Eidolon:BAAALAADCgcICAAAAA==.',El='Eldanhar:BAAALAAECgUIDwAAAA==.Elemintt:BAAALAAECgcIBwAAAA==.Elennia:BAAALAADCggICAAAAA==.Elimion:BAAALAAECgIIAgAAAA==.Ellytrimix:BAABLAAECoEbAAIEAAcIzRBYfQB2AQAEAAcIzRBYfQB2AQAAAA==.Eluizu:BAAALAADCggIDAAAAA==.Elydor:BAAALAAECgMIBAAAAA==.',En='Enpriest:BAAALAADCgYIBgAAAA==.',Er='Erigor:BAAALAAFFAIIBAAAAA==.Erinael:BAAALAADCgcIEQAAAA==.Erinel:BAAALAAECgQIAwAAAA==.Ernest:BAAALAADCgMIAwAAAA==.',Es='Esrefpasali:BAAALAAECgMIBAABLAAECgYIHgAEAJAbAA==.',Et='Ethredus:BAAALAAECgUIBwAAAA==.Etwin:BAAALAAECgYIDAAAAA==.',Ev='Eveagora:BAAALAAECgIIAgAAAA==.Eviljake:BAAALAAECgIIAgAAAA==.',Fa='Fandasia:BAAALAAECgcICwABLAAECggIGgAXACUeAA==.Fantasyzz:BAAALAAECgIIAgAAAA==.Favoured:BAAALAADCggIDAAAAA==.Faythe:BAAALAADCgYIBgAAAA==.',Fi='Fiskerenfisk:BAABLAAECoEUAAIGAAcIkiSFJAC3AgAGAAcIkiSFJAC3AgABLAAFFAIIAgABAAAAAA==.Fisky:BAAALAAFFAIIAgAAAA==.',Fl='Flakeypastry:BAAALAAECgYIBgABLAAECggIKAAHAKUlAA==.Flamborambo:BAAALAADCgIIAgAAAA==.Flou:BAAALAAECgIIAgAAAA==.',Fo='Forsakenthor:BAAALAAECgMIAwAAAA==.',Fr='Frakdorf:BAAALAADCggIFgAAAA==.Frésh:BAAALAADCgYIBgAAAA==.',Ga='Galbraithh:BAAALAADCgQIBAAAAA==.Gamonius:BAAALAADCgUIBQAAAA==.',Ge='Gecko:BAAALAADCgMIAwABLAAECgYIDAABAAAAAA==.Genohacker:BAABLAAECoEZAAIPAAcI6Q1RbgBkAQAPAAcI6Q1RbgBkAQAAAA==.',Gh='Ghaross:BAAALAAECgYIBgAAAA==.',Gl='Gleam:BAABLAAECoEoAAIbAAgIVBm1HABSAgAbAAgIVBm1HABSAgAAAA==.Glulir:BAABLAAECoEfAAIRAAcI7BV0IgCgAQARAAcI7BV0IgCgAQAAAA==.',Go='Gooya:BAAALAAECgYIBgAAAA==.',Gw='Gwen:BAAALAADCggIIwAAAA==.Gwendolinee:BAABLAAECoEXAAIKAAYIqA1nmwACAQAKAAYIqA1nmwACAQAAAA==.Gwendydd:BAAALAADCggIDQAAAA==.Gweniver:BAAALAADCggIIwAAAA==.',Ha='Hashira:BAAALAADCgUIBQAAAA==.',He='Helko:BAAALAAECgcIBwAAAA==.Helrezza:BAACLAAFFIEIAAIbAAMIlxYYCgDwAAAbAAMIlxYYCgDwAAAsAAQKgSwAAxAACAj5HsgPAMkCABAACAj5HsgPAMkCABsACAgRHvsPALICAAAA.Hexer:BAAALAADCggIDAAAAA==.',Hi='Hináta:BAAALAADCgYIBgAAAA==.Hivix:BAACLAAFFIEKAAIEAAYIBRjMCABjAQAEAAYIBRjMCABjAQAsAAQKgRcAAgQABgj9IzIvAFUCAAQABgj9IzIvAFUCAAAA.',Ho='Hoffyshammy:BAAALAADCgcIBwABLAAECggIGwAGAIoSAA==.Hoofski:BAABLAAECoEZAAMKAAcIOB5nPAD7AQAKAAcIOB5nPAD7AQALAAQItgwnfgDfAAAAAA==.Hoperock:BAABLAAECoEmAAMcAAgIcQ4bQACtAQAcAAgIcQ4bQACtAQAMAAEIGAOBjwAdAAAAAA==.Hordeleader:BAAALAADCgcIBwAAAA==.Hotz:BAAALAAECgYIEwAAAA==.',['Hé']='Héx:BAAALAAECgYIEAAAAA==.',Ic='Icefox:BAAALAAECgYIDgAAAA==.Icegoblin:BAABLAAECoEbAAICAAcI9wnybQBtAQACAAcI9wnybQBtAQAAAA==.Icesaffa:BAAALAADCggICAAAAA==.',Ii='Iingvaar:BAAALAADCggICAAAAA==.',Il='Ilovemycat:BAAALAAFFAIIAgAAAA==.Ilran:BAAALAADCgYIEgAAAA==.',Im='Imptias:BAAALAADCgIIAgAAAA==.',In='Innovision:BAAALAADCggICQABLAAECgYIDAABAAAAAA==.',Ir='Iriacynthe:BAAALAAECgYIDgAAAA==.Irishbolt:BAAALAADCgYIBgAAAA==.Irishpi:BAAALAADCggICAABLAADCggIDAABAAAAAA==.Irnbru:BAABLAAECoEaAAIDAAcImQ6oKACEAQADAAcImQ6oKACEAQAAAA==.Irnbruxtra:BAAALAAECgIIAgAAAA==.',Is='Isiatrasil:BAAALAAECgUICQAAAA==.Isithralith:BAAALAADCgcIDwAAAA==.',Iz='Izalith:BAAALAAECgcIBwAAAA==.',Ja='Jakozzle:BAACLAAFFIEFAAIdAAIIVx/IAQC8AAAdAAIIVx/IAQC8AAAsAAQKgSIAAh0ACAgwI0gBAC0DAB0ACAgwI0gBAC0DAAAA.Jarrupala:BAABLAAECoEdAAIGAAcIPQ3bjgCWAQAGAAcIPQ3bjgCWAQAAAA==.',Je='Jeia:BAAALAADCgcIBwAAAA==.',Ji='Jiegerbomb:BAABLAAECoEfAAIGAAcIfwsJngB6AQAGAAcIfwsJngB6AQAAAA==.Jinot:BAABLAAECoEYAAIeAAgI4wDLHAAaAAAeAAgI4wDLHAAaAAAAAA==.Jinzo:BAAALAAECgYIBgAAAA==.',Jo='Johanneke:BAAALAAECgYIEwAAAA==.Josefu:BAAALAAECgMIAwAAAA==.',Ju='Judsea:BAAALAADCgYICgAAAA==.Jui:BAAALAADCggICAAAAA==.',Ka='Kaelyn:BAAALAAECgYIDAAAAA==.Kailiyah:BAAALAAECgYICQAAAA==.Kalimdora:BAAALAAECgYIDAAAAA==.Kaliopy:BAAALAADCggIJgAAAA==.Kaliopybg:BAABLAAECoEVAAIPAAcIkw45XACZAQAPAAcIkw45XACZAQAAAA==.Kaliopydk:BAAALAAECgMIAQAAAA==.Kalokua:BAAALAAECgYICwAAAA==.Kayrra:BAAALAAECgYICwAAAA==.Kazama:BAAALAAECgMIBAABLAAECgYICwABAAAAAA==.',Ke='Keeli:BAAALAADCgcIDQABLAAECgcIGAAEAEMkAA==.Kennytheger:BAAALAADCggICAAAAA==.',Ki='Killerdemon:BAABLAAECoEXAAIWAAcIgCNBBwDHAgAWAAcIgCNBBwDHAgAAAA==.',Kn='Knóx:BAABLAAECoEWAAIaAAgI1xhJFgBSAgAaAAgI1xhJFgBSAgAAAA==.Knôx:BAAALAADCgQIBAAAAA==.',Kr='Krazat:BAAALAAECgYIDgAAAA==.Krezra:BAAALAAECgcIBwAAAA==.Krier:BAAALAADCggICAAAAA==.Kronin:BAAALAAECgEIAQAAAA==.',Ku='Kusynlig:BAAALAADCgcIBwABLAAECgcIGQAOAB0kAA==.',Ky='Kyng:BAABLAAECoEmAAIEAAgIsRuRMgBHAgAEAAgIsRuRMgBHAgAAAA==.Kyubiistraza:BAAALAAECgcIEAAAAA==.',La='Lattios:BAABLAAECoEdAAMXAAcIeCKKCQCtAgAXAAcIeCKKCQCtAgACAAQI2xc1jQAYAQABLAADCgQIBAABAAAAAA==.',Le='Lebellel:BAABLAAECoEZAAIVAAgIRBk+NABeAgAVAAgIRBk+NABeAgAAAA==.Lehrel:BAAALAAECgEIAQAAAA==.Leopal:BAAALAAECgQICAABLAAECgcIGQAfADIMAA==.Leousan:BAAALAAECgUIBQAAAA==.Lethalbacon:BAAALAADCgYIBgAAAA==.',Lh='Lhydia:BAAALAAECgYICwAAAA==.',Li='Lilit:BAACLAAFFIEKAAICAAUIWBJ/CwClAQACAAUIWBJ/CwClAQAsAAQKgSwAAgIACAhkIncNAB4DAAIACAhkIncNAB4DAAAA.Linked:BAAALAAECgYIDAAAAA==.Liontarakis:BAABLAAECoEaAAMXAAgIJR6RCAC9AgAXAAgIJR6RCAC9AgACAAMIDxXHpwC6AAAAAA==.Litllestar:BAAALAADCggICAAAAA==.Littleholy:BAAALAADCgYICAAAAA==.',Lo='Lockleif:BAAALAADCggICAAAAA==.Locohunter:BAAALAAECggIDQAAAA==.Loftus:BAABLAAECoEjAAMEAAgI9hx+LABgAgAEAAgI9hx+LABgAgAJAAUIWBAtagD8AAAAAA==.Longeria:BAABLAAECoEWAAIQAAYIrQTWYgDbAAAQAAYIrQTWYgDbAAAAAA==.Lozz:BAAALAAECgQIBAAAAA==.Lozzarino:BAAALAAECgUICgAAAA==.',Lu='Lunjun:BAAALAADCgcIBwAAAA==.Lux:BAAALAADCgcIBwAAAA==.',Ly='Lyrianna:BAAALAAECgYIDwAAAA==.Lysara:BAABLAAECoEYAAIPAAcILgkXbwBhAQAPAAcILgkXbwBhAQAAAA==.Lyxea:BAABLAAECoEWAAQZAAgIdhatDQAuAgAZAAgIqRStDQAuAgAaAAUIORdLOQBgAQAeAAIIRhCOFgByAAAAAA==.',['Lé']='Lémon:BAABLAAECoEiAAIGAAgIkhrQMgB5AgAGAAgIkhrQMgB5AgAAAA==.',Ma='Madaline:BAAALAAECgUIDwAAAA==.Madrisa:BAAALAAECgYICQABLAAFFAUIDQAEAJ0ZAA==.Madrísa:BAAALAAECggIDwABLAAFFAUIDQAEAJ0ZAA==.Madwell:BAABLAAECoEYAAIEAAcIoxFIcwCMAQAEAAcIoxFIcwCMAQAAAA==.Maffi:BAAALAADCggICAABLAAFFAcIEwALAHoXAA==.Magelena:BAEALAADCggICAAAAA==.Magí:BAAALAAECgUICwAAAA==.Marjolein:BAABLAAECoEcAAIGAAgIlRbfRQA6AgAGAAgIlRbfRQA6AgAAAA==.Masashi:BAAALAAECgYIBwAAAA==.Mastércastér:BAAALAAECgMIBAAAAA==.Maxariun:BAAALAAECgYIDgAAAA==.Maxímus:BAABLAAECoEVAAIPAAYIbyD6MAA5AgAPAAYIbyD6MAA5AgAAAA==.',Mc='Mcgrumpy:BAAALAAECgYIEQAAAA==.Mcivy:BAABLAAECoEYAAIKAAgIkgFszwCeAAAKAAgIkgFszwCeAAAAAA==.Mcpie:BAABLAAECoEhAAQMAAgIISBxEQDNAgAMAAgIISBxEQDNAgAgAAIIcxAYJgBvAAAcAAEIRAognwA1AAAAAA==.',Me='Melt:BAAALAADCgUIBQAAAA==.Methe:BAAALAAECgcIBwAAAA==.',Mh='Mhdk:BAAALAAECggICAAAAA==.Mhordok:BAAALAADCggICAAAAA==.',Mi='Mikusiek:BAAALAAECgMIAwAAAA==.Milim:BAABLAAECoEVAAIFAAYIsSWSBwCYAgAFAAYIsSWSBwCYAgAAAA==.Miso:BAAALAAECgcIBgAAAA==.Misteá:BAABLAAECoEoAAMUAAgI+BukCgCTAgAUAAgI+BukCgCTAgADAAEIORatUwBCAAAAAA==.',Mo='Moltres:BAAALAADCggIGgAAAA==.Mooniania:BAACLAAFFIEFAAIUAAIIJhnfCgClAAAUAAIIJhnfCgClAAAsAAQKgSAAAhQACAgrHl8JAKoCABQACAgrHl8JAKoCAAEsAAUUBggUABsAjiIA.Morphmage:BAAALAAECgQIBAABLAAECggIKAAHAKUlAA==.Morwenys:BAAALAADCggIDQAAAA==.Mothra:BAAALAADCggICAAAAA==.Motto:BAACLAAFFIESAAMgAAYIYA9SAAAwAQAgAAUI5w9SAAAwAQAMAAEIPAgAIQBKAAAsAAQKgScAAiAACAjjH+IBAOkCACAACAjjH+IBAOkCAAAA.',['Má']='Márshmallow:BAAALAAECgQIBAABLAAECgUIDwABAAAAAA==.',['Mé']='Méatshield:BAAALAADCggIEAABLAAECgUICwABAAAAAA==.',['Mí']='Míthrax:BAAALAADCgMIAwAAAA==.',['Mø']='Møhammad:BAAALAAECgEIAQABLAAECgcIGQAOAB0kAA==.',Na='Naleya:BAAALAAECgIIAgAAAA==.Natvera:BAAALAAECgcICgAAAA==.',Ne='Neptun:BAAALAAECggIDwAAAA==.Nerabus:BAAALAADCgQIBAAAAA==.Neriana:BAABLAAECoEdAAIVAAcIZiVLFgD2AgAVAAcIZiVLFgD2AgAAAA==.Nerök:BAAALAADCgcIBwAAAA==.Nesyrre:BAAALAADCgYIBgAAAA==.Nethertank:BAAALAAECgMIBgAAAA==.',Ni='Niccii:BAAALAADCgQICAAAAA==.Nightmoon:BAACLAAFFIEUAAIbAAYIjiJ6AQAYAgAbAAYIjiJ6AQAYAgAsAAQKgS8AAxsACAgVJQgEADgDABsACAgVJQgEADgDACEACAjoIacDACADAAAA.Nightsorrow:BAAALAAECggIEgAAAA==.Ninaxx:BAAALAAECgcIEAAAAA==.Nineoneone:BAAALAAECgYIDAAAAA==.Ninjitstu:BAAALAADCgcIBwABLAAECggIEwABAAAAAA==.Nivix:BAACLAAFFIEKAAIiAAUIQQmEAQBkAQAiAAUIQQmEAQBkAQAsAAQKgTMAAyIACAgWJFEFACkDACIACAgWJFEFACkDAB8AAggbFg/AAIEAAAEsAAUUBggKAAQABRgA.',No='Norgus:BAAALAAECgUIBwAAAA==.Nothinghood:BAAALAAECggICgAAAA==.Notto:BAAALAAFFAIIAgABLAAFFAYIEgAgAGAPAA==.',Nu='Nurkal:BAAALAADCgcICAAAAA==.',Ny='Nyria:BAAALAADCgcIBQAAAA==.',['Nè']='Nèd:BAABLAAECoEYAAIGAAgIGBYZRgA5AgAGAAgIGBYZRgA5AgAAAA==.',['Né']='Néédmanas:BAAALAADCggICwAAAA==.',['Në']='Nëverlucky:BAAALAADCgQIBAAAAA==.',['Nÿ']='Nÿsa:BAABLAAECoEeAAIEAAYIkBunUwDaAQAEAAYIkBunUwDaAQAAAA==.',Od='Oddbal:BAAALAAECgYICQAAAA==.',Ol='Olivianne:BAAALAADCggIBgAAAA==.Olodos:BAAALAAECgYICgAAAA==.',Om='Ompw:BAAALAADCggIEAAAAA==.',On='One:BAABLAAECoEVAAILAAgIGBjTJABbAgALAAgIGBjTJABbAgAAAA==.Onyxo:BAAALAAECgcIBwAAAA==.',Oo='Ooga:BAAALAADCggICAAAAA==.',Op='Opsie:BAABLAAECoEXAAIKAAcIZxcpSADUAQAKAAcIZxcpSADUAQAAAA==.',Ot='Otaval:BAAALAAECgEIAQAAAA==.',Ou='Outcome:BAABLAAECoEXAAMbAAgIARCITwBjAQAbAAgIARCITwBjAQAQAAEIiwpgiQA3AAAAAA==.',Ov='Ovock:BAABLAAECoEdAAILAAgIJhGpNwD3AQALAAgIJhGpNwD3AQAAAA==.',Pa='Padonk:BAABLAAECoEZAAMDAAcIxBFTNAAxAQADAAYIRhRTNAAxAQASAAYIJgdDLQDdAAAAAA==.Paimei:BAAALAADCgEIAQABLAAECggIDgABAAAAAA==.Palavizor:BAAALAAECgIIAgAAAA==.Pauldirac:BAAALAADCggIGgAAAA==.',Pe='Permabanned:BAAALAAECggICAAAAA==.',Ph='Phoneman:BAAALAAECgYICgAAAA==.',Pi='Piki:BAAALAADCgMIAwAAAA==.Pinkfury:BAAALAAECggIEwAAAA==.Piraten:BAAALAAECgcIBwAAAA==.Pirrow:BAAALAADCgIIAgAAAA==.Pithikos:BAAALAADCgEIAQAAAA==.Pittepatt:BAAALAADCgcIBwAAAA==.',Pl='Pleather:BAAALAAECgUICAAAAA==.',Po='Pointillism:BAAALAAECgQIBAAAAA==.',Pp='Ppowah:BAAALAADCgIIAgABLAAECgYIFQAbAPYfAA==.Ppower:BAAALAAECgQIBAABLAAECgYIFQAbAPYfAA==.',Pr='Praxithea:BAAALAAECgUIDQAAAA==.Prique:BAAALAADCgUIBQAAAA==.',Ps='Psyla:BAAALAADCgYICgAAAA==.Psyló:BAAALAAECgQIBAAAAA==.',Pu='Puffy:BAABLAAECoEfAAIQAAcIcRskIAAtAgAQAAcIcRskIAAtAgAAAA==.Purgi:BAAALAADCggIDwAAAA==.',['Pí']='Pírat:BAABLAAECoEaAAIEAAgIqxs2PgAbAgAEAAgIqxs2PgAbAgAAAA==.',Qu='Quezalacotol:BAAALAADCgcIFgAAAA==.',Ra='Rarion:BAAALAAECgYIDwAAAA==.Rasberry:BAAALAAECgcIDgAAAA==.Rasillon:BAABLAAECoEhAAIfAAgIlQr1YwCyAQAfAAgIlQr1YwCyAQAAAA==.Rastyu:BAABLAAECoEXAAMOAAYI+BubIwDaAQAOAAYI+BubIwDaAQAjAAYI9RYlEQCdAQAAAA==.Rautakilpi:BAAALAADCgcIBwAAAA==.Ravanaa:BAABLAAECoEcAAIVAAgIghBTXADfAQAVAAgIghBTXADfAQAAAA==.Ravoy:BAAALAAECggICgAAAA==.Ravven:BAAALAAECgIIAgAAAA==.Rayneko:BAABLAAECoElAAIIAAgI+hUqEQD/AQAIAAgI+hUqEQD/AQAAAA==.',Re='Reformed:BAAALAAECggICgAAAA==.Regla:BAAALAADCgcIBwAAAA==.Relent:BAAALAADCgcIBwAAAA==.Renewlock:BAABLAAECoEoAAICAAgIrR7BGwC9AgACAAgIrR7BGwC9AgAAAA==.Renji:BAAALAAECggICgAAAA==.Rexes:BAAALAAECgYIEAAAAA==.',Ro='Rockdoctor:BAABLAAECoEXAAMLAAYI5AlJaQA8AQALAAYI5AlJaQA8AQAKAAYIYQwpowDyAAAAAA==.Rolicia:BAAALAAECgYIDQAAAA==.Rorsach:BAAALAADCgUIBQAAAA==.Rosie:BAAALAAECgYIDQAAAA==.Rothric:BAAALAAECgIIAgAAAA==.',Ru='Rumendh:BAAALAADCggIFAAAAA==.Rumleskaft:BAAALAAECgQIBAABLAAECggIDgABAAAAAA==.',Sa='Sabatonv:BAAALAADCgcICgAAAA==.Sadelra:BAAALAAECgEIAQAAAA==.Saeko:BAAALAAECgYIEwAAAA==.Sagar:BAABLAAECoEUAAIGAAcIkghnqgBkAQAGAAcIkghnqgBkAQAAAA==.Sajapie:BAAALAAECgcIBwAAAA==.Sakai:BAAALAAECgMIBQAAAA==.Salamander:BAAALAADCggICwABLAAECgUIDwABAAAAAA==.Salvaron:BAABLAAECoEfAAIbAAcIvRblNgDIAQAbAAcIvRblNgDIAQAAAA==.Saphiya:BAAALAAECgQICAAAAA==.Saphíra:BAAALAADCgYIBgAAAA==.Sas:BAAALAAECgcIDQAAAA==.Sasi:BAAALAADCgcIBwAAAA==.',Se='Selavy:BAAALAADCgIIAgAAAA==.Sensi:BAAALAADCgMIAwAAAA==.Sensibeam:BAAALAAECgUIBQABLAAFFAIIBAABAAAAAA==.Sensiclap:BAAALAAFFAIIBAAAAA==.Sensipony:BAAALAAECgYIBgABLAAFFAIIBAABAAAAAA==.Sensiuwu:BAACLAAFFIEUAAIMAAYI9iEqAwAJAgAMAAYI9iEqAwAJAgAsAAQKgTAAAgwACAiIJuAAAIsDAAwACAiIJuAAAIsDAAAA.Serrá:BAAALAAECgQIAwAAAA==.Sertoi:BAAALAAECgQIBwAAAA==.',Sh='Shalashovka:BAAALAAECgMIAwAAAA==.Shamandurex:BAAALAADCgcIBwAAAA==.Shambollic:BAAALAAECgYIEQAAAA==.Shammyberry:BAACLAAFFIEQAAMLAAYIBgYuCQBoAQALAAYIBgYuCQBoAQAKAAEIkgEJTgApAAAsAAQKgSAAAwsACAj/HrQfAH0CAAsACAj/HrQfAH0CAAoAAQg4CKcJASgAAAAA.Sheeshdormu:BAAALAAECgIIAgAAAA==.Sheshock:BAABLAAECoEVAAILAAYIhQ9yWwBrAQALAAYIhQ9yWwBrAQAAAA==.Shinkz:BAABLAAECoEaAAMEAAgIhxlmOAAxAgAEAAgIhxlmOAAxAgAJAAEI1wthswAnAAAAAA==.Shook:BAAALAAECgYIDAAAAA==.Shronky:BAAALAADCggIHgABLAAECgcIGQAKADgeAA==.',Si='Sigmamyballs:BAAALAAECgYIBgAAAA==.Sinimonk:BAAALAADCggIDwAAAA==.Sisnoir:BAAALAADCgQIBAAAAA==.',Sj='Sjokkomelk:BAAALAAECgYIBgAAAA==.',Sk='Skildpadde:BAAALAAECgYIBgAAAA==.Skullsmasha:BAAALAADCgQICAAAAA==.Skyggetyren:BAAALAADCggICAAAAA==.',Sl='Slappyhands:BAAALAADCgQIBAABLAAECgUICwABAAAAAA==.Slarr:BAAALAAECgYIBgAAAA==.Slubby:BAAALAAECggIDQAAAA==.',Sm='Smäsh:BAAALAAECgUIBQAAAA==.',So='Solaire:BAAALAADCgEIAQAAAA==.Sonjad:BAAALAADCgYIFwAAAA==.Sosarian:BAAALAAECgYICwAAAA==.Sotsji:BAAALAAECgUIDgABLAAECgYIEwABAAAAAA==.Souru:BAABLAAECoEfAAIHAAgIHSPIFgD6AgAHAAgIHSPIFgD6AgAAAA==.Soá:BAAALAADCggIDQAAAA==.',Sp='Spartarion:BAABLAAECoEcAAIEAAcIEAoOkwBKAQAEAAcIEAoOkwBKAQAAAA==.Spicytofu:BAABLAAECoEbAAIWAAgIyyVNAgBJAwAWAAgIyyVNAgBJAwAAAA==.Spiokra:BAABLAAECoEWAAIPAAgIYRmuKABkAgAPAAgIYRmuKABkAgAAAA==.',St='Stars:BAABLAAECoEVAAIbAAYI9h96JQAeAgAbAAYI9h96JQAeAgAAAA==.Stjernekrem:BAAALAADCgcIBwAAAA==.Storbums:BAAALAADCgUIBQAAAA==.Stormfang:BAAALAAECgMIAwAAAA==.Stormfury:BAAALAADCgIIAgAAAA==.Stormspirit:BAAALAAECgMIAwAAAA==.Strel:BAAALAADCggICAAAAA==.Stu:BAAALAADCgMIAwABLAAECggIEwABAAAAAA==.Studiophile:BAAALAAECggICgAAAA==.Studru:BAAALAAECggIEgABLAAECggIEwABAAAAAA==.Stuehstrasza:BAAALAADCggICAABLAAECggIEwABAAAAAA==.Stuéh:BAAALAAECggIEwAAAA==.',Sw='Swagowner:BAAALAAFFAIIAgAAAA==.',Sy='Syphix:BAAALAAECgYICwAAAA==.',Sz='Szuzsika:BAAALAAECgcIEwABLAAECggICAABAAAAAA==.',Ta='Takala:BAAALAAECgUIDQAAAA==.Talis:BAAALAAECgYICwAAAA==.Tarantoyla:BAAALAADCgEIAQAAAA==.Tatalorcoie:BAAALAAFFAIIBAAAAA==.Taxus:BAABLAAECoEWAAIHAAcIUwYjzAA2AQAHAAcIUwYjzAA2AQAAAA==.',Te='Tenzin:BAAALAAECgcIBQAAAA==.Teodora:BAAALAAECgEIAQAAAA==.Terrormaker:BAAALAADCgQIBAAAAA==.',Th='Thoka:BAAALAAECgcIDQAAAA==.Threats:BAAALAAECgQIBAAAAA==.Throngayle:BAAALAAECgcIDwAAAA==.',Ti='Tikal:BAAALAAECgYICwAAAA==.Titanis:BAAALAAECgQIBAAAAA==.',To='Toothless:BAABLAAECoEWAAIcAAcIARZjNADkAQAcAAcIARZjNADkAQAAAA==.Totemherm:BAAALAAECgYIBgAAAA==.',Tr='Trapsilence:BAAALAAECgMIBQAAAA==.Treehuggre:BAABLAAECoEdAAIbAAcIGBUOOgC6AQAbAAcIGBUOOgC6AQAAAA==.Trelamenos:BAAALAADCgIIAgAAAA==.',Ts='Tsulos:BAAALAADCggICAAAAA==.',Tu='Turidemon:BAAALAADCgcICwAAAA==.Tuskka:BAAALAADCgYIFQAAAA==.',Tw='Twibble:BAAALAADCgYIBgAAAA==.',Uc='Ucharik:BAABLAAECoEXAAIHAAcI/RmTTQAqAgAHAAcI/RmTTQAqAgAAAA==.',Ug='Ugliebuglie:BAAALAAECgYIDgABLAAECgYIEwABAAAAAA==.',Uk='Ukumbe:BAAALAADCggIDwAAAA==.',Ul='Ulthar:BAAALAADCggIEgAAAA==.',Un='Unfulfilled:BAAALAAECgcICgAAAA==.Unskilledkek:BAAALAAECgMIBQAAAA==.',Ur='Uradrel:BAABLAAECoEaAAIPAAcIJR0WLwBCAgAPAAcIJR0WLwBCAgAAAA==.Uranus:BAAALAAECgcIBwAAAA==.Urð:BAAALAAECgUIBwABLAAECggIGgAVAIUdAA==.',Va='Valix:BAAALAADCggICAABLAAFFAIIBQAdAFcfAA==.Vallis:BAAALAAECggIEAAAAA==.Vany:BAAALAAECgQICAAAAA==.',Ve='Vectamxd:BAAALAAECgUIBQAAAA==.Velinha:BAAALAADCggICAABLAAECggIEwABAAAAAA==.Veszély:BAAALAADCgUIBQAAAA==.',Vi='Vibedk:BAAALAAECgMIAwAAAA==.Vind:BAAALAAECgYICQAAAA==.Violeti:BAAALAADCggIDwAAAA==.Violety:BAAALAAECgMIBwAAAA==.Violetï:BAAALAADCggICAAAAA==.Viridia:BAABLAAECoEZAAMCAAgI5AdvcwBeAQACAAgIYQdvcwBeAQAXAAMIMAjjbACBAAAAAA==.Visions:BAAALAADCgUIBQABLAAECgIIBAABAAAAAA==.Vitamin:BAAALAAECgcIBwAAAA==.',Vk='Vkyra:BAAALAAECgMIBgAAAA==.',Vo='Vollmilch:BAAALAAECgcIBwAAAA==.Vorkath:BAACLAAFFIEUAAMkAAYIdx9IBAC9AQAkAAUIhRtIBAC9AQAlAAYITx6SAQCkAQAsAAQKgS8AAyUACAi4JikAAIQDACUACAjGJSkAAIQDACQACAguJZwDAEoDAAAA.Voxarria:BAAALAAECgYIDgABLAAECggIFgAPAGEZAA==.',Vu='Vulpan:BAAALAAECgUIDwAAAA==.',Wa='Waendor:BAAALAADCggIDAAAAA==.Wannebe:BAAALAAECgMIBQAAAA==.Warior:BAAALAAECgIIAgABLAAFFAMICAACAM4bAA==.Warlead:BAAALAAECgcIDQAAAA==.Wasa:BAAALAADCgcIBwAAAA==.',Wh='Whyrm:BAAALAADCgYIBgAAAA==.',Wo='Wonderpray:BAAALAAECgcIEAAAAA==.Woph:BAAALAADCggIEQABLAAECgcIFwAKAGcXAA==.Wops:BAAALAADCgYIBgABLAAECgcIFwAKAGcXAA==.',Wr='Wrynn:BAAALAAECgUIDwAAAA==.',Wy='Wyran:BAAALAADCgQIBAAAAA==.Wyriaz:BAAALAAECgMIBAAAAA==.',Xe='Xelmettria:BAABLAAECoEmAAINAAgIXRgtFABBAgANAAgIXRgtFABBAgAAAA==.Xethvallia:BAAALAAECgQIBAAAAA==.',Xi='Xiaara:BAABLAAECoEZAAIfAAgIphDTSgD/AQAfAAgIphDTSgD/AQAAAA==.Xiaolongbao:BAAALAAECgIIBQAAAA==.Xiora:BAABLAAECoEUAAIHAAgICBX5aQDnAQAHAAgICBX5aQDnAQAAAA==.',Xl='Xlight:BAAALAAECgUIDwAAAA==.',['Xã']='Xãlatath:BAAALAADCgcIBwAAAA==.',Ya='Yagodkin:BAAALAADCgcIBwAAAA==.Yakara:BAAALAAECgYIBgAAAA==.',Yo='Yonhaelen:BAAALAAFFAIIAgABLAAFFAUIEgAHAIAmAA==.Yonhealen:BAACLAAFFIESAAIHAAUIgCaSAgA/AgAHAAUIgCaSAgA/AgAsAAQKgS8AAgcACAj2JigAAKIDAAcACAj2JigAAKIDAAAA.',Ys='Ysrana:BAAALAADCgEIAQAAAA==.',Yu='Yuzral:BAABLAAECoEnAAIGAAgIoRxoKgCcAgAGAAgIoRxoKgCcAgAAAA==.',Yv='Yva:BAABLAAECoEXAAIGAAYIGQ0wtQBPAQAGAAYIGQ0wtQBPAQAAAA==.',Za='Zanisn:BAABLAAECoEbAAIHAAcIjhbZdADRAQAHAAcIjhbZdADRAQAAAA==.Zarquon:BAAALAADCgcIBwAAAA==.',Ze='Zenig:BAAALAAECgcIBwAAAA==.Zeusbeast:BAAALAADCggIDAAAAA==.',Zg='Zgykke:BAAALAAECgEIAQAAAA==.',Zi='Zigge:BAAALAADCgcIBwAAAA==.Zinwei:BAABLAAECoEUAAIPAAYICgyrdgBLAQAPAAYICgyrdgBLAQAAAA==.',Zo='Zoilo:BAAALAAECgcIDAAAAA==.',Zu='Zubunk:BAABLAAECoEdAAIDAAcIwxKfIwCrAQADAAcIwxKfIwCrAQAAAA==.Zuldark:BAAALAADCgcICAAAAA==.Zulkas:BAAALAAECgUICwAAAA==.',['Æn']='Ænerox:BAAALAAECgEIAQAAAA==.',['Íl']='Íllithane:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end