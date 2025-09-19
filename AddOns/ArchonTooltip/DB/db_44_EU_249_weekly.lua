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
 local lookup = {'Warlock-Destruction','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Unknown-Unknown','Evoker-Devastation','Priest-Shadow','Warrior-Protection','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Druid-Restoration','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Paladin-Retribution','Mage-Arcane','Mage-Frost','Mage-Fire','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Holy','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Warrior-Arms','Priest-Holy','DeathKnight-Unholy','Hunter-Survival','Priest-Discipline','Rogue-Subtlety',}; local provider = {region='EU',realm='Aggramar',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Achlex:BAABLAAECoEcAAIBAAgIIx4HFACTAgABAAgIIx4HFACTAgAAAA==.',Ad='Adarin:BAAALAADCggIDAAAAA==.',Ag='Agramore:BAAALAADCgUIBQAAAA==.',Ai='Ainai:BAAALAAECgMIBgAAAA==.Aiqu:BAAALAAECgYIBgAAAA==.',Ak='Akathan:BAAALAAECggIAgAAAA==.',Al='Alaki:BAAALAAECgIIBAAAAA==.Alamin:BAAALAAECgQIBAAAAA==.Albe:BAAALAAECgMIAwAAAA==.Aldanil:BAAALAADCgUIBQAAAA==.Alibert:BAAALAADCggICAAAAA==.Alizya:BAAALAAECgMIBAAAAA==.Altarian:BAAALAADCgEIAQAAAA==.Alumbrada:BAAALAAECgUICgAAAA==.',Am='Amberleígh:BAABLAAECoEXAAICAAcIqAz2PQCSAQACAAcIqAz2PQCSAQAAAA==.',An='Angelreeper:BAABLAAECoEeAAMCAAgI9x1WFACLAgACAAgIsBxWFACLAgADAAgICRcSFQBIAgAAAA==.Angoea:BAAALAADCggIDAAAAA==.Antisocial:BAAALAAFFAIIBAAAAA==.',Ar='Aramirloth:BAAALAAECgYICgAAAA==.Ariå:BAABLAAECoEeAAIEAAgIyhElEwCnAQAEAAgIyhElEwCnAQAAAA==.Arloge:BAAALAAECgMIBwAAAA==.',As='Asperia:BAAALAAECgEIAQAAAA==.',At='Atholon:BAAALAADCggIEAAAAA==.Atreide:BAAALAAECgMIAwAAAA==.Atreleto:BAAALAADCgYIBgAAAA==.Atuad:BAAALAADCggICAABLAAECgYIEQAFAAAAAA==.',Au='Auralia:BAAALAAECgIIAgAAAA==.Auramaystery:BAAALAADCgcIBwABLAAECgQIAwAFAAAAAA==.Aurelià:BAAALAADCggIDAAAAA==.',Av='Aviicii:BAAALAADCgcICgAAAA==.',Aw='Awoo:BAAALAAFFAIIAgAAAA==.',Az='Azaela:BAAALAAECgMIAwAAAA==.Azmah:BAAALAADCgYICgAAAA==.Azovan:BAAALAAECgQIBAABLAAECggIHgAGADogAA==.',Ba='Babyray:BAAALAAECgMIBgAAAA==.Baelphegor:BAAALAAECgMIBgAAAA==.Bair:BAAALAADCggIEAABLAAECggIHgAHAJsiAA==.Bairoth:BAABLAAECoEeAAIHAAgImyIABgAiAwAHAAgImyIABgAiAwAAAA==.Baison:BAAALAADCggIDAAAAA==.Bamipangang:BAAALAADCgYIBgAAAA==.Baradiel:BAAALAAECggICAAAAA==.Baratan:BAACLAAFFIEIAAMIAAMI6x3zAgD6AAAJAAMIRRqWBQASAQAIAAMIShXzAgD6AAAsAAQKgR8AAgkACAhyJecBAG0DAAkACAhyJecBAG0DAAAA.',Be='Beastyagood:BAAALAADCggIEAAAAA==.Beckinsalex:BAAALAAFFAIIAgAAAQ==.Beejoux:BAAALAAECgMICAAAAA==.Bellatrixl:BAAALAADCgMIAwAAAA==.Benjanator:BAAALAAECggIDQAAAA==.Beton:BAAALAAECgQICAAAAA==.',Bi='Biclops:BAAALAADCgQIAQAAAA==.Bigyin:BAAALAAECgMIAwAAAA==.',Bl='Blacknight:BAAALAADCggICAAAAA==.Blackwidow:BAAALAADCggIEwAAAA==.Blazerent:BAAALAAECggICAAAAA==.Blindlight:BAAALAAFFAIIAgAAAA==.Bloodezyx:BAAALAAECgIIAgAAAA==.Bloodsepsis:BAAALAAECggIBgAAAA==.',Bo='Boozie:BAABLAAECoEZAAIJAAgI0Rj4FwBeAgAJAAgI0Rj4FwBeAgAAAA==.Bowkiller:BAAALAADCgYIBgAAAA==.',Br='Braincursed:BAACLAAFFIEIAAMBAAMIciCeBQAsAQABAAMI8R6eBQAsAQAKAAEIKSWJDQBsAAAsAAQKgR8ABAEACAgsJjgBAHgDAAEACAjrJTgBAHgDAAsABQh3JXAHAAgCAAoAAghBJk1CANMAAAAA.',Bu='Bulldozern:BAAALAAECgMIAwAAAA==.Bulz:BAABLAAECoEXAAIMAAcIxRXqIwC6AQAMAAcIxRXqIwC6AQAAAA==.Burox:BAAALAADCgMIAwAAAA==.Burston:BAAALAAECgMIAwAAAA==.',Ca='Cahlista:BAAALAADCggICAAAAA==.Caileán:BAAALAADCggICgAAAA==.Cala:BAAALAADCggICAAAAA==.Camulus:BAAALAAECgYICgAAAA==.Canix:BAAALAAECgYICgAAAA==.Cantamucca:BAAALAAECgYIDQAAAA==.Captrix:BAAALAAECgUIAwAAAA==.Carar:BAACLAAFFIEFAAINAAMIYhg8AgDyAAANAAMIYhg8AgDyAAAsAAQKgR8AAg0ACAgKI+UCABMDAA0ACAgKI+UCABMDAAAA.Carre:BAAALAAECgcIDQAAAA==.Castle:BAAALAAECgIIBAAAAA==.',Ce='Celesté:BAAALAADCggIFwAAAA==.Celinae:BAAALAAECgYIBgABLAAECgYICwAFAAAAAA==.Cellene:BAAALAADCgIIAgAAAA==.Cerebellum:BAABLAAECoEXAAMOAAcImxnNHgAZAgAOAAcImxnNHgAZAgAPAAYIRAxbEABHAQAAAA==.',Ch='Chairten:BAAALAAECgIIAgAAAA==.Cheetan:BAACLAAFFIEIAAIQAAMI3SAjAwAlAQAQAAMI3SAjAwAlAQAsAAQKgR8AAhAACAhJJUEDAGcDABAACAhJJUEDAGcDAAAA.Chejhaci:BAAALAAECgYICwAAAA==.Chiangel:BAAALAADCgUIBQAAAA==.Chriista:BAAALAAECgMIBAAAAA==.',Cl='Clarkéy:BAAALAAECggIAQAAAA==.Claus:BAABLAAECoEiAAQRAAgISCUfDwDoAgARAAgI8iMfDwDoAgASAAUIPiakEAAkAgATAAEIgwtXEwA9AAAAAA==.Clivacuss:BAAALAAECgEIAQAAAA==.',Co='Coconutpete:BAAALAADCgcICwAAAA==.Comeflywmay:BAAALAAECgMIBAABLAAECgQIAwAFAAAAAA==.',Cr='Criodor:BAAALAAECggICAAAAA==.Critcat:BAAALAAECgMICQAAAA==.Cronyx:BAAALAAECgUIAwAAAA==.',Cu='Cullie:BAAALAAECgQIBwAAAA==.Cush:BAAALAAECgMIAwAAAA==.',['Có']='Cóólio:BAAALAAECgEIAQAAAA==.',Da='Daaryki:BAAALAADCggICAAAAA==.Daely:BAAALAAECgYIDAAAAA==.Dakul:BAAALAAECgYIDQAAAA==.Damarrus:BAAALAAECgMIAwAAAA==.Darkepic:BAAALAAECgMIBgAAAA==.Darrina:BAAALAADCggIEQABLAAECgMICQAFAAAAAA==.Dasgot:BAAALAADCggICgAAAA==.Dawnwalkér:BAAALAAECgIIAgAAAA==.',De='Ded:BAAALAADCggICAAAAA==.Dedfupanda:BAAALAADCggICAAAAA==.Dedholy:BAAALAADCggIEAAAAA==.Deepimpact:BAABLAAECoEYAAIRAAgIhBBUNADzAQARAAgIhBBUNADzAQAAAA==.Delraxian:BAAALAAECgYICwAAAA==.Demonvamp:BAAALAAECgMICQAAAA==.Demonveiko:BAAALAADCggIDgAAAA==.Dentge:BAAALAAFFAUIAgAAAA==.Desirous:BAAALAADCggIGQAAAA==.Dethromas:BAABLAAECoEWAAIUAAcI8Bx7JgBHAgAUAAcI8Bx7JgBHAgAAAA==.Develia:BAAALAADCggICAAAAA==.Devilbyday:BAABLAAECoEXAAIVAAcIQQwyGwAmAQAVAAcIQQwyGwAmAQAAAA==.Devillion:BAAALAAECggIEAAAAA==.',Di='Die:BAAALAAECgUIAwAAAA==.Digiman:BAAALAAECgcIDwAAAA==.Ditgit:BAAALAAECgEIAgAAAA==.Ditobuco:BAAALAAECgIIAgAAAA==.',Dj='Djfmastermix:BAAALAADCgEIAQAAAA==.',Do='Dokteranders:BAAALAAECgYIDAAAAA==.Domhruun:BAAALAADCgcIBwAAAA==.Donaldpump:BAAALAAECgQIBQAAAA==.',Dr='Dragolich:BAAALAAECgUIAwAAAA==.Dragorad:BAAALAAECgcICgAAAA==.Drahugonis:BAAALAAECgEIAQAAAA==.Drakial:BAAALAAECggICAAAAA==.Drupa:BAAALAADCggICAABLAAECgIIAgAFAAAAAA==.Dryalla:BAAALAAECgMIAwAAAA==.Drüids:BAAALAADCgIIAgAAAA==.',Du='Dumbelldoor:BAAALAADCgcIEgAAAA==.Durrantarna:BAAALAADCgYICAAAAA==.Duskmoon:BAAALAAECgYICAAAAA==.',Dw='Dwalik:BAAALAADCgQIBAAAAA==.',Ea='Ealak:BAAALAAECgYICAAAAA==.Easytiger:BAAALAAECgMICAAAAA==.',Eb='Ebonmaw:BAAALAAECgMIBAAAAA==.',Ef='Effina:BAAALAAECgYICAAAAA==.',El='Elclapo:BAABLAAECoEYAAIIAAgIaSU1AQBpAwAIAAgIaSU1AQBpAwAAAA==.Elderbeast:BAAALAADCggIDgAAAA==.Elders:BAAALAAECgMIBQAAAA==.Eldunari:BAAALAAECgMIAwAAAA==.Elki:BAAALAADCggICAAAAA==.Ellie:BAABLAAECoEWAAMCAAgIWh49EgCfAgACAAgIWh49EgCfAgADAAYIMghGSQDnAAAAAA==.Eluthia:BAAALAAECgMIAwAAAA==.Elyesia:BAABLAAECoEXAAIEAAcIVx6cCgA0AgAEAAcIVx6cCgA0AgAAAA==.Elyshan:BAAALAAECgUICwAAAA==.',Em='Emdoom:BAAALAADCggIAwAAAA==.Eminentia:BAAALAAECgEIAQAAAA==.Emsickle:BAAALAADCgcIBwAAAA==.Emster:BAAALAADCggIHAAAAA==.',Er='Ervar:BAAALAAECgMIBAAAAA==.Erwind:BAAALAAECgMIBgAAAA==.',Et='Ett:BAAALAAECgYIBwAAAA==.',Ev='Evilblep:BAAALAAECgcIDwAAAA==.Evyat:BAAALAAECgUICwAAAA==.',Ex='Exigè:BAAALAAECgYICQAAAA==.Exille:BAAALAAECgMIAwAAAA==.',Ey='Eyebims:BAAALAAECgQIBQAAAA==.',Ez='Ezran:BAAALAAECgEIAQAAAA==.',Fa='Facebeated:BAAALAADCgcIBwAAAA==.Faylen:BAABLAAECoEUAAMCAAcIqB9uFwBvAgACAAcIqB9uFwBvAgADAAQI0Rl8OQA6AQAAAA==.',Fe='Felfire:BAABLAAECoEUAAIWAAcIfhkaMgD+AQAWAAcIfhkaMgD+AQAAAA==.Fellover:BAABLAAECoEeAAIWAAgISyIOCwARAwAWAAgISyIOCwARAwAAAA==.Felmilk:BAAALAAECgYIBgAAAA==.Fera:BAAALAAECgMICAAAAA==.',Ff='Fflam:BAAALAAECgYIDQAAAA==.',Fi='Figroll:BAAALAAECgYIDwAAAA==.Fika:BAAALAAECgYICAAAAA==.Firestormed:BAAALAAECgMICAAAAA==.',Fl='Flaskepant:BAAALAAECgcICAAAAA==.Flickit:BAAALAADCgEIAQAAAA==.Flipper:BAAALAAECgIIAwAAAA==.Floppydog:BAAALAAECgYIDAAAAA==.',Fo='Forg:BAAALAADCgcIBgAAAA==.Forloveren:BAAALAAECgQIBAABLAAECgcICwAFAAAAAA==.Foxie:BAAALAAECgMIAwAAAA==.Foxyy:BAAALAADCggICAAAAA==.',Fr='Frozonè:BAAALAADCgcICQAAAA==.',Fu='Fulgur:BAAALAAECgMIBQAAAA==.Fuyrae:BAAALAAECgYICgAAAA==.',Ga='Gaaladriell:BAAALAAECgEIAQAAAA==.Gabiis:BAAALAAECgYIDQAAAA==.Gabis:BAAALAAECgYICgAAAA==.Gabiss:BAABLAAECoEfAAQBAAgIZx6IEQCrAgABAAgIZx6IEQCrAgALAAQIPhNSFQARAQAKAAMISBO2QgDRAAAAAA==.',Ge='Gebis:BAAALAAECgYIEwAAAA==.Gekkofisk:BAAALAADCgUIBQABLAAECgcICwAFAAAAAA==.Geo:BAAALAADCggICAABLAAECggIGAARAB0gAA==.',Gn='Gnugget:BAAALAAECgMIAwAAAA==.',Go='Goatfan:BAAALAAECgUIAwAAAA==.Gondaft:BAAALAAECgMICAAAAA==.',Gr='Grave:BAAALAAECgUIBQAAAA==.Gremwick:BAAALAAECgYIDQAAAA==.Greyowl:BAAALAADCggIBwAAAA==.Grigari:BAAALAADCgUIBQAAAA==.Griim:BAAALAADCggICAAAAA==.Grunni:BAAALAADCgMIAwAAAA==.Gryfsara:BAAALAADCggIEwAAAA==.',Gu='Gueles:BAAALAAECgMIBAAAAA==.Guldshammy:BAAALAADCgEIAQAAAA==.Guthrie:BAAALAAECggIDAAAAA==.',['Gá']='Gárnet:BAAALAAECgMICAAAAA==.',Ha='Habibii:BAABLAAECoEYAAIQAAgIYCO1BwA3AwAQAAgIYCO1BwA3AwAAAA==.Hagrasuwu:BAABLAAECoEeAAIMAAgIwSQgAQBTAwAMAAgIwSQgAQBTAwAAAA==.Haifriends:BAAALAAECgQICAAAAA==.Hairypal:BAAALAADCggICwAAAA==.Hairytotems:BAAALAAECgcIDQAAAA==.Hallådär:BAAALAAECgMIBAAAAA==.Hated:BAAALAADCggIEAAAAA==.Hawlao:BAAALAAECgYICAAAAA==.',He='Hearthshield:BAAALAAECgQIBQAAAA==.Hecate:BAAALAAECgcIEQAAAA==.Heet:BAAALAAECggIEgAAAA==.Hexem:BAAALAAECgUICAAAAA==.',Hi='Hitandrun:BAAALAADCgYIBgAAAA==.',Ho='Holywilleh:BAAALAADCgcICAAAAA==.Hoy:BAABLAAECoEXAAIQAAgInB4hEwDLAgAQAAgInB4hEwDLAgAAAA==.',Hu='Huffandpuff:BAAALAAECgMIBAAAAA==.Huglover:BAAALAADCggICAAAAA==.Hunney:BAABLAAECoEXAAIQAAcIphZnQADUAQAQAAcIphZnQADUAQAAAA==.',Hw='Hwitebear:BAAALAAECgYIBgAAAA==.',['Hæ']='Hælded:BAAALAADCgcICwAAAA==.',Ic='Icenia:BAAALAADCgIIAQAAAA==.Ickarus:BAABLAAECoEeAAIGAAgIOiCEBgD2AgAGAAgIOiCEBgD2AgAAAA==.Icylath:BAAALAAECgUIAwAAAA==.',Ie='Ieronumos:BAAALAAFFAIIAgAAAA==.',Im='Imogén:BAAALAADCgYIBgAAAA==.',In='Inamorata:BAAALAAECgMICAAAAA==.Ingarr:BAAALAAECgYIEQAAAA==.Invinciblep:BAAALAADCgcIBwAAAA==.',Ja='Jackness:BAAALAAECgEIAQAAAA==.James:BAAALAADCggICAAAAA==.Jamjam:BAAALAADCggICAAAAA==.Jamma:BAAALAAECgMIAwAAAA==.Jammyjam:BAAALAAECgMIAwAAAA==.',Je='Jeff:BAAALAAECgMIAwAAAA==.Jegerligeher:BAACLAAFFIEHAAISAAMI+RkXAQAPAQASAAMI+RkXAQAPAQAsAAQKgRYAAxIACAgII8MEAPsCABIACAgII8MEAPsCABEAAQgGENWTAEIAAAAA.Jeloby:BAABLAAECoEYAAIEAAgIqRqvCwAeAgAEAAgIqRqvCwAeAgAAAA==.',Ji='Jigsaw:BAAALAAECgMIBQAAAA==.Jinjer:BAABLAAECoEVAAIRAAcIjRdKLgASAgARAAcIjRdKLgASAgABLAAECgEIAQAFAAAAAA==.',Jo='Jocelynn:BAACLAAFFIEGAAISAAIISh7KAgC8AAASAAIISh7KAgC8AAAsAAQKgRwAAhIACAgWJLsBAFUDABIACAgWJLsBAFUDAAAA.Joegue:BAAALAAECgMIAwAAAA==.Jollyrancher:BAAALAAECgcIEQAAAA==.Joéy:BAAALAAECggICAAAAA==.',Js='Jskdh:BAAALAAECgYIDAAAAA==.Jstarr:BAAALAADCggIEAAAAA==.',Ju='Jugram:BAAALAADCgMIAwAAAA==.Juliett:BAAALAAECgYIEAAAAA==.Justbarry:BAAALAAECgQIBgAAAA==.',Jx='Jxke:BAAALAAECgQIBAABLAAECgYIDAAFAAAAAA==.',['Jí']='Jímmy:BAAALAAECgYICwAAAA==.Jínja:BAAALAADCgIIAgAAAA==.',Ka='Kaaryki:BAAALAAECgMICAAAAA==.Kaasko:BAAALAAECgMIBQAAAA==.Kaheera:BAAALAAECgIIAwAAAA==.Kaldordraigo:BAAALAAECgMIAwAAAA==.Kalevandaal:BAAALAAECgQIBQABLAAECggIGgALAMMYAA==.Kalman:BAAALAAECgYIDQAAAA==.Kasadyaa:BAAALAAECgIIAgAAAA==.Katniss:BAAALAADCggIEAAAAA==.Katraouras:BAAALAAECgYIBgAAAA==.Kayn:BAAALAAECgMIAwABLAAFFAMICAAWAGAhAA==.',Ke='Kenko:BAABLAAECoEeAAMXAAgIXxnsCgBUAgAXAAgIXxnsCgBUAgAQAAcI3xKTVACRAQAAAA==.',Ki='Kirris:BAAALAADCgcIDgAAAA==.',Kl='Klamandar:BAAALAAECgMIBwAAAA==.Klamdk:BAAALAADCgcIDgABLAAECgMIBwAFAAAAAA==.Klatte:BAAALAAECgMIBAAAAA==.Klinkin:BAAALAAECgcIDQAAAA==.Klinko:BAAALAADCggICAAAAA==.',Kn='Knakwörst:BAAALAADCggIGwAAAA==.Kneehow:BAAALAADCggICAABLAADCggICAAFAAAAAA==.',Ko='Korrigan:BAAALAAECgMIBwAAAA==.Korun:BAAALAAECgYICgAAAA==.',Kr='Kronii:BAAALAADCggIDQAAAA==.',Ku='Kug:BAAALAAECgYICwAAAA==.',Kw='Kwizzbang:BAAALAAECgIIAgAAAA==.',['Kí']='Kítsune:BAAALAAECgQIBAAAAA==.',La='Lajcsi:BAABLAAECoEfAAIYAAgIKBlGCQBBAgAYAAgIKBlGCQBBAgAAAA==.Larwick:BAAALAADCggIEgAAAA==.Laveloos:BAAALAAECgEIAQAAAA==.Layniar:BAAALAADCgYIBgABLAAECgIIBAAFAAAAAA==.Laynier:BAAALAAECgIIBAAAAA==.',Le='Leadfoot:BAAALAAECgMIAwAAAA==.Legato:BAABLAAECoEeAAIJAAgI4iLRBQA0AwAJAAgI4iLRBQA0AwAAAA==.Leoioi:BAAALAAECgYICwAAAA==.Lespadal:BAAALAAECgYIBgAAAA==.Lexus:BAAALAAECgMICAAAAA==.Leyton:BAAALAAECgMIBwAAAA==.',Li='Liam:BAAALAADCggIEAAAAA==.Lilhani:BAAALAADCgIIAgAAAA==.Lilitü:BAAALAAECgUICgAAAA==.',Lo='Lockonimp:BAABLAAECoEaAAILAAgIwxioAgCpAgALAAgIwxioAgCpAgAAAA==.Loghorn:BAAALAAECgYIDwAAAA==.Lok:BAAALAAECgUICAAAAA==.Lonêy:BAAALAAECgUIAwAAAA==.Lorielus:BAAALAADCggICAAAAA==.Loríelus:BAAALAADCgYIBQAAAA==.Losstriss:BAAALAAECgUICAAAAA==.Lovemydruid:BAAALAAECggICwAAAA==.Lozzielock:BAAALAAECgYIEgAAAA==.',Lu='Lucianov:BAAALAADCggIDQAAAA==.Luddeg:BAABLAAECoEdAAIOAAgImCC0CwDmAgAOAAgImCC0CwDmAgAAAA==.Lumas:BAAALAAECgQIBgAAAA==.Lunar:BAAALAADCgYIBgAAAA==.',Ly='Lycria:BAAALAAECgUIAwAAAA==.',['Lá']='Láyníar:BAAALAADCgMIAwABLAAECgIIBAAFAAAAAA==.',['Lé']='Léetum:BAAALAAECgMIBQAAAA==.',Ma='Maalekith:BAAALAAECgIIAgAAAA==.Magedukenl:BAAALAAECgcIEQAAAA==.Magiamannen:BAAALAAECgcIDgAAAA==.Magicpiggy:BAAALAAECgEIAgABLAAFFAMICAABAHIgAA==.Magwi:BAABLAAECoEeAAICAAgIwCPCBAA6AwACAAgIwCPCBAA6AwAAAA==.Malazot:BAAALAAECgUICwAAAA==.Malneria:BAAALAADCgEIAQAAAA==.Manizen:BAAALAAECgYICgAAAA==.Marchessa:BAAALAADCgQIBAAAAA==.Mastabear:BAAALAADCggIEAAAAA==.Matthias:BAAALAAECgMICAAAAA==.Mayfoo:BAABLAAECoEeAAQZAAgIGRwhCAB4AgAZAAgIGRwhCAB4AgAaAAYInxnLFADOAQAYAAIIXg5LJwBkAAAAAA==.Maymay:BAAALAAECgQIAwAAAA==.',Me='Mectra:BAABLAAECoEdAAIQAAgIgR8DEADlAgAQAAgIgR8DEADlAgAAAA==.Mehwa:BAAALAAECgQIBgAAAA==.Melandroso:BAAALAAECgEIAQAAAA==.Melpal:BAAALAAECggICwAAAA==.Messycalabas:BAAALAADCgYIBgAAAA==.',Mi='Micrototem:BAAALAAECgYICAAAAA==.Millecollin:BAABLAAECoEfAAIbAAgITx2nAgC8AgAbAAgITx2nAgC8AgAAAA==.Miragen:BAAALAAECgEIAQAAAA==.Mirages:BAAALAADCggICAAAAA==.Miriva:BAAALAADCggIJAAAAA==.Mitsi:BAAALAAECgMIBwAAAA==.Miyuri:BAABLAAECoEVAAIJAAcINBbvJgDnAQAJAAcINBbvJgDnAQAAAA==.',Mo='Monkovich:BAAALAAECgMICAAAAA==.Moodydroody:BAABLAAECoEZAAIMAAgIDiHXBADwAgAMAAgIDiHXBADwAgAAAA==.Moonjuice:BAAALAAECgEIAgAAAA==.Mootty:BAAALAADCggIDwAAAA==.Mowinckel:BAAALAAECgcICwAAAA==.Moxxy:BAAALAAECgUICwAAAA==.Moísty:BAAALAAECgUIDwAAAA==.',Mu='Mucca:BAAALAAECgUICQAAAA==.Muniu:BAAALAAECgQIBAAAAA==.Musha:BAAALAAECgYIDQAAAA==.',My='Mymage:BAAALAAECgQIBQAAAA==.Mynamisjef:BAAALAAECgQIBAABLAAECgIIAwAFAAAAAA==.Myozikeen:BAAALAADCgQIBAAAAA==.Mystia:BAAALAAECgIIAQAAAA==.Myztia:BAAALAADCgcIEgAAAA==.',['Mà']='Màthìás:BAAALAAECgcIDwAAAA==.',['Mí']='Mímo:BAAALAADCgcICwAAAA==.',Na='Naatpuupke:BAAALAADCgIIAgAAAA==.Nadytaur:BAAALAAECgMIBwAAAA==.Naga:BAAALAAECgQIBAAAAA==.Namah:BAAALAAECgYICAAAAA==.Namedilema:BAAALAADCggICAAAAA==.Naruyrelhar:BAAALAADCggIEAAAAA==.',Ne='Necrofile:BAABLAAECoEUAAMBAAcI8RZnJwD5AQABAAcI8RZnJwD5AQAKAAUIjw7YMgAvAQAAAA==.Nemesishunt:BAAALAAECgIIAgAAAA==.Nerdbane:BAAALAADCgcIBwAAAA==.Neres:BAAALAAECgMICAAAAA==.Nesidruid:BAAALAAECgUICwAAAA==.Neverluckyxd:BAAALAADCgcIBwAAAA==.',Ni='Nimea:BAAALAAECgYIBgAAAA==.Niquisra:BAAALAADCggIFwAAAA==.Nivod:BAAALAAECggICQABLAAECggIFwAQAJweAA==.',No='Nostramu:BAAALAAECgIIAgAAAA==.Novíe:BAAALAAECgQIBQAAAA==.',Nq='Nqdies:BAAALAAECgMICQAAAA==.',Ny='Nybris:BAAALAAECgYICwAAAA==.',['Nì']='Nìjá:BAAALAAECgYIBwAAAA==.',['Nî']='Nîckfury:BAAALAADCggICAABLAAECgMICAAFAAAAAA==.',Oc='Ocukace:BAAALAADCgEIAQAAAA==.',Og='Oggle:BAAALAAECgQIBQABLAAFFAMICAAWAPQWAA==.Oggles:BAACLAAFFIEIAAIWAAMI9Bb8BgABAQAWAAMI9Bb8BgABAQAsAAQKgR8AAhYACAhFJeEDAFwDABYACAhFJeEDAFwDAAAA.',Oh='Ohhillidan:BAAALAAECgYIBgAAAA==.',Op='Opticon:BAAALAAECgYIEAABLAAECggIHgAcAD4kAA==.Optidrood:BAAALAAECgYIBQABLAAECggIHgAcAD4kAA==.Optilass:BAAALAAECgMIBAABLAAECggIHgAcAD4kAA==.Optipriest:BAABLAAECoEeAAIcAAgIPiQZAgBMAwAcAAgIPiQZAgBMAwAAAA==.',Or='Orvos:BAAALAADCgQIBAABLAADCggIDQAFAAAAAA==.',Ov='Overkeko:BAAALAAECgYIDAAAAA==.Overogue:BAAALAAECgIIAgAAAA==.Overshameo:BAAALAAECgYIBgAAAA==.Overyap:BAAALAAECgYIBgAAAA==.',Pa='Pandarama:BAAALAAECgMIAwAAAA==.',Pe='Peakeiz:BAAALAAECgMIAwAAAA==.Pearle:BAAALAAECgYICAAAAA==.Pendulum:BAABLAAECoEgAAQdAAgIExumBwB/AgAdAAgI2BqmBwB/AgANAAYIqBYsDwCfAQAUAAYI1g55dQAvAQAAAA==.Perago:BAAALAADCggICAAAAA==.Pestofwest:BAAALAADCgUIBQAAAA==.Petrakulika:BAAALAADCggICgAAAA==.Pewnage:BAAALAAECgYICgAAAA==.',Ph='Pharven:BAAALAADCggICQAAAA==.',Po='Polinczki:BAAALAADCggIHAAAAA==.Polinczkimoo:BAAALAADCggICgAAAA==.Polinczkiy:BAAALAADCggIEQAAAA==.',Pr='Preservation:BAAALAADCggIEQAAAA==.Proflora:BAAALAAECgUICAAAAA==.',Pu='Puddle:BAAALAAECgMIAwAAAA==.Pulsarp:BAAALAAECgQIBwAAAA==.Purdey:BAAALAAECgMIBgAAAA==.',Py='Pyrofrost:BAAALAAECgMIAwAAAA==.',['Pâ']='Pân:BAAALAADCgQIBAAAAA==.',['Pò']='Pòptart:BAAALAADCggIDAAAAA==.',Qu='Quelaania:BAABLAAECoEZAAIeAAgIxx5zAQDkAgAeAAgIxx5zAQDkAgAAAA==.Quelana:BAAALAAECgYIBgABLAAECggIGQAeAMceAA==.Quélth:BAABLAAECoEXAAIcAAcI2RQqKADJAQAcAAcI2RQqKADJAQAAAA==.Quótästic:BAAALAAECgIIBAAAAA==.',Ra='Rainaris:BAAALAAECgcIEwAAAA==.Rautha:BAAALAADCgQICAAAAA==.Ravenbuft:BAAALAAECgMIBQAAAA==.Raymundoo:BAAALAADCggICAAAAA==.Razika:BAAALAADCggIDQABLAAECgcICwAFAAAAAA==.',Re='Reava:BAAALAAECgQIBAAAAA==.Reddanni:BAAALAADCgQIBAAAAA==.Reenberg:BAAALAAECgcIDAAAAA==.Reinah:BAAALAAECgcIEgAAAA==.Relaw:BAAALAADCggIDwABLAAECgYIDAAFAAAAAA==.Relawen:BAAALAAECgEIAQABLAAECgYIDAAFAAAAAA==.Renatô:BAEALAAECgQIBQABLAAFFAIIBAAFAAAAAA==.Renatö:BAEALAAFFAIIBAAAAA==.Repulse:BAABLAAECoEWAAIfAAgI1BriAQCmAgAfAAgI1BriAQCmAgAAAA==.',Rh='Rhuanna:BAAALAADCggICAAAAA==.',Ri='Rietje:BAAALAAECgUICQAAAA==.Rigorra:BAAALAAECgQIBAAAAA==.Rinku:BAAALAAECgIIAgAAAA==.Rivern:BAAALAADCgcIEgAAAA==.',Ro='Rockenbeer:BAAALAADCgYIAgAAAA==.Roided:BAAALAAECggIBgAAAA==.Rosca:BAABLAAECoEYAAIRAAgIHSDnEADZAgARAAgIHSDnEADZAgAAAA==.Rosedew:BAAALAADCgcIDgAAAA==.Rowren:BAAALAAECgcIDwAAAA==.Roïsin:BAABLAAECoEdAAIUAAgIYxS0MAAUAgAUAAgIYxS0MAAUAgAAAA==.',Ru='Ruffy:BAAALAAECgYICgAAAA==.',Ry='Ryalia:BAAALAADCggICwAAAA==.Ryuukurai:BAAALAADCggIEAAAAA==.Ryzz:BAAALAAFFAIIAwAAAA==.',['Rì']='Rìp:BAAALAADCgEIAQAAAA==.',Sa='Sabitsuki:BAAALAAECgYICAAAAA==.Sacreboeuf:BAAALAAECgQIBQAAAA==.Saiho:BAAALAAECgYICAAAAA==.Sailak:BAAALAADCggIFwAAAA==.Sailakd:BAAALAADCggICAAAAA==.Salera:BAABLAAECoEWAAQBAAgIpBxRIgAdAgABAAgIXhhRIgAdAgAKAAIIQRyvSwCkAAALAAIIaQy4JQBzAAAAAA==.Sammael:BAAALAADCgMIAwAAAA==.Sangor:BAABLAAECoEeAAIBAAgIFhtvFQCGAgABAAgIFhtvFQCGAgAAAA==.',Sc='Scottywarr:BAABLAAECoEVAAIJAAgIwByWEACwAgAJAAgIwByWEACwAgAAAA==.Scrímpton:BAAALAAECgUICAAAAA==.',Se='Secret:BAAALAAECgMIAwAAAA==.Seinaru:BAAALAAECgMIBgAAAA==.Selesny:BAAALAADCgYIDAAAAA==.Selis:BAAALAAECgUIAwAAAA==.',Sf='Sfaxtis:BAAALAAECgIIAgAAAA==.',Sh='Shamalozzie:BAAALAAECggICAAAAA==.Shamanigans:BAAALAAECgUICAAAAA==.Shamdamonium:BAAALAAECgIIAwAAAA==.Showtoes:BAAALAAECggIBgAAAA==.Shroomies:BAAALAAECgYICgAAAA==.',Si='Siana:BAAALAAECgMIBAAAAA==.Silverheart:BAAALAADCggIAwAAAA==.Simien:BAAALAAECgMIBAAAAA==.Simpleton:BAAALAAECgQIBAAAAA==.Simplosion:BAABLAAECoEeAAQLAAgI1CUqAACKAwALAAgIwiUqAACKAwAKAAMIOSN6MgAxAQABAAEIvyH/fQBdAAAAAA==.Siérra:BAAALAAECgIIAgABLAAECgcIFAACAKgfAA==.',Sj='Självfallet:BAABLAAECoEdAAIcAAgIqhGmIwDlAQAcAAgIqhGmIwDlAQAAAA==.',Sk='Skarnur:BAACLAAFFIEIAAIXAAMIggzHBADtAAAXAAMIggzHBADtAAAsAAQKgR8AAhcACAjXFpIMAD4CABcACAjXFpIMAD4CAAAA.Skautik:BAAALAAECgMICQAAAA==.Skillgoore:BAABLAAECoEeAAIgAAgITCHDAQAZAwAgAAgITCHDAQAZAwAAAA==.Skorio:BAAALAAECgMIBwAAAA==.Skylarius:BAAALAADCggIDQAAAA==.',Sl='Slanetz:BAAALAAECgUIAwAAAA==.Slashikpala:BAAALAAECgMICQAAAA==.Sleepy:BAAALAAECggIEAAAAA==.Slubby:BAAALAADCggIBwAAAA==.',Sm='Smikkel:BAABLAAECoEUAAIQAAcIsQ8kUgCZAQAQAAcIsQ8kUgCZAQAAAA==.Smörj:BAAALAAECgMIAwAAAA==.',Sn='Snipertal:BAAALAAECgMIAwAAAA==.',So='Soisondn:BAAALAAECgYIBwAAAA==.Soteira:BAAALAAECgMIBQAAAA==.',Sp='Spartaazz:BAAALAAECgEIAQAAAA==.Spartaz:BAAALAADCggIEgAAAA==.Spartazz:BAAALAAECgYICQAAAA==.Spiritlash:BAAALAADCggICAAAAA==.Splithex:BAAALAADCggICAAAAA==.Splitotem:BAAALAAECgQIBQAAAA==.Spookums:BAAALAADCgcIFwAAAA==.',St='Stardawn:BAAALAAECgYICgAAAA==.Steampe:BAAALAAECggICAAAAA==.Stefano:BAAALAAFFAIIAgAAAA==.Stefanos:BAAALAAECgQIBQABLAAFFAIIAgAFAAAAAA==.Stefy:BAAALAAECgEIAQAAAA==.Stezzlock:BAAALAADCgcIDQAAAA==.Stobbart:BAAALAAECgYICgAAAA==.Stonesmasher:BAAALAAECgMIAwAAAA==.Stormbeard:BAAALAAECgMIAwAAAA==.Stormbinder:BAAALAAECgQIBQAAAA==.',Su='Sub:BAAALAADCgYIBgAAAA==.Sultress:BAAALAADCggIDwAAAA==.',Sy='Syntaks:BAAALAADCggIFwAAAA==.Syñtax:BAAALAAECgcIBwAAAA==.',Sz='Szelong:BAAALAADCggIGwAAAA==.Szuzsika:BAAALAAECgYICwAAAA==.',Ta='Talent:BAAALAADCggICAAAAA==.Tankuru:BAAALAADCgcIFQAAAA==.',Te='Teabág:BAAALAADCgcICwAAAA==.Teddiursa:BAAALAAECgQIBQABLAAECggIHgACAMAjAA==.',Th='Thaismile:BAAALAAECgUICAAAAA==.Thandril:BAAALAAECgMIAwAAAA==.Thebringer:BAAALAAECgMICQAAAA==.Thecoolsham:BAAALAAECgYICgAAAA==.Thellanah:BAAALAAECgMICAAAAA==.Thespanker:BAAALAAECgQIBAAAAA==.Thiralia:BAAALAAECgYIDAAAAA==.Thomarz:BAAALAAECgUIBQAAAA==.Thomselspall:BAAALAADCggIDgAAAA==.Thraldox:BAAALAAECgQIBAAAAA==.Thralnox:BAAALAADCggIDwABLAAECgQIBAAFAAAAAA==.Thurgos:BAAALAAECgYICwAAAA==.Thuya:BAAALAAECgMIBQAAAA==.',Ti='Tiberium:BAAALAAECgcIDQAAAA==.Tinydragon:BAAALAADCgMIAwAAAA==.',To='Tobimonk:BAACLAAFFIEGAAIZAAMIuhHFAwD2AAAZAAMIuhHFAwD2AAAsAAQKgR4AAhkACAhDH4sEANcCABkACAhDH4sEANcCAAAA.Torien:BAAALAADCgEIAQAAAA==.Totemsniffer:BAAALAADCggICQABLAAECggIGgALAMMYAA==.',Tr='Trathor:BAAALAAECgQIBAAAAA==.Trawn:BAAALAAECgMIBgAAAA==.Tryy:BAAALAADCggIEwAAAA==.Tríckd:BAAALAAECgQIBQAAAA==.',Ty='Tykhoved:BAAALAAECgQIBAAAAA==.Tyronar:BAAALAADCggIEwAAAA==.',Un='Undeadknight:BAAALAADCgcIDwAAAA==.',Ur='Urgol:BAAALAADCggICAABLAAECgYIEQAFAAAAAA==.',Va='Vaelith:BAAALAAECgYIEQAAAA==.Vallath:BAAALAAECgYIBwAAAA==.Vampiregirly:BAAALAAECgIIBAAAAA==.Vattel:BAABLAAECoEXAAIQAAcIcxatPADhAQAQAAcIcxatPADhAQAAAA==.',Ve='Veiko:BAAALAADCgcIDAAAAA==.Venarys:BAAALAAECgMIAwAAAA==.',Vi='Vigíl:BAAALAAECggICgAAAA==.Visdomstand:BAAALAADCgUIBQAAAA==.Vixean:BAAALAADCgYIBgAAAA==.Vizilium:BAAALAADCgYIBgAAAA==.',Vo='Voidz:BAAALAADCgcIDgAAAA==.Voodoolord:BAAALAAECgMIAwAAAA==.',Wa='Waifuhunter:BAACLAAFFIEGAAIVAAMIGCGXAAAnAQAVAAMIGCGXAAAnAQAsAAQKgRcAAhUACAjrJeAAAGQDABUACAjrJeAAAGQDAAAA.Wartrol:BAAALAADCgQIAwAAAA==.Washte:BAAALAAECgYIEQAAAA==.',We='Weebbsteer:BAAALAAECgcIDAAAAA==.',Wh='Whitepearl:BAAALAAECgYIDgAAAA==.Whitewizzard:BAAALAAECgIIBAAAAA==.',Wi='Wieland:BAAALAAECggIAwAAAA==.Wilikhanom:BAAALAAECgYIBgAAAA==.Willehwarloc:BAAALAADCgcICwABLAADCggIEgAFAAAAAA==.Willythepooh:BAAALAADCggIDwAAAA==.Wily:BAAALAADCggICAABLAADCggIEgAFAAAAAA==.Wingmage:BAAALAAECgEIAQAAAA==.',Wr='Wrongclue:BAAALAADCgEIAQAAAA==.',Wy='Wynnona:BAAALAADCgcIBwAAAA==.',Xa='Xanzi:BAAALAADCgUIBQAAAA==.',Ya='Yakku:BAAALAADCgcIBwAAAA==.',Ye='Yeah:BAAALAADCggICAAAAA==.Yenthel:BAAALAAECggIDwAAAA==.',Ze='Zendezith:BAAALAAECgYICgAAAA==.Zengi:BAAALAAECgMIBAAAAA==.Zentoro:BAAALAAECgcICgAAAA==.Zeny:BAAALAAECgMIAwAAAA==.',Zi='Zilda:BAAALAADCgIIAgAAAA==.Zirith:BAAALAADCggIEwAAAA==.',Zk='Zkdiablo:BAAALAADCggIDgAAAA==.',Zo='Zomburriito:BAAALAAECgEIAQAAAA==.',['Ás']='Ásgarðr:BAAALAADCggICAABLAAECgMIBgAFAAAAAA==.',['Åz']='Åzarn:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end