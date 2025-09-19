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
 local lookup = {'Rogue-Assassination','Rogue-Subtlety','Unknown-Unknown','Evoker-Devastation','Druid-Balance','Monk-Windwalker','Priest-Shadow','Hunter-BeastMastery','Warlock-Affliction','Priest-Holy','Hunter-Marksmanship','Druid-Restoration','Warrior-Protection','Druid-Feral','Shaman-Restoration','DemonHunter-Havoc','Druid-Guardian','Warrior-Fury','Paladin-Holy','Paladin-Retribution','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','DeathKnight-Blood','Paladin-Protection','Evoker-Preservation','Evoker-Augmentation','Shaman-Elemental','Priest-Discipline','Warrior-Arms','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Mage-Arcane',}; local provider = {region='EU',realm='Shadowsong',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adikia:BAAALAADCggIEwAAAA==.',Ae='Aelik:BAAALAADCggICQAAAA==.Aelynthi:BAACLAAFFIEJAAMBAAMIyBqMAgAsAQABAAMIyBqMAgAsAQACAAEI4QycCgBHAAAsAAQKgSAAAwEACAiNIhcGAPUCAAEACAjQIRcGAPUCAAIABAgWGgAAAAAAAAAA.Aeoneye:BAAALAAECgMIAQAAAA==.Aevorn:BAAALAAECggIEAAAAA==.Aexxo:BAAALAAECgcICQAAAA==.',Ag='Agility:BAAALAAECgYIDAAAAA==.',Ak='Akasukí:BAAALAADCgEIAQABLAAECgYIDAADAAAAAA==.Akyone:BAAALAADCgYIBgAAAA==.',Al='Aldaniti:BAAALAAECgMIBQAAAA==.Alegosa:BAABLAAECoEYAAIEAAgIDRoLDQCHAgAEAAgIDRoLDQCHAgAAAA==.Alvirae:BAABLAAECoEVAAIFAAgIAhr+EgBTAgAFAAgIAhr+EgBTAgAAAA==.Alysium:BAAALAADCgIIAgAAAA==.',Am='Amerisa:BAAALAAECgEIAQAAAA==.Amicalucina:BAAALAAECgEIAQAAAA==.Ammiana:BAAALAADCggIEAAAAQ==.',An='Angelictuna:BAAALAADCgQIBgABLAAECgYICgADAAAAAA==.Anikara:BAAALAADCgcICwAAAA==.Aniz:BAABLAAECoEXAAIGAAcI9xw0CwBmAgAGAAcI9xw0CwBmAgAAAA==.',Aq='Aquilegia:BAAALAAECgEIAQAAAA==.',Ar='Aredheal:BAAALAAECgYIDAAAAA==.Arrowmark:BAAALAAECgEIAQAAAA==.Artaelion:BAAALAAECgYICgAAAA==.Arthiel:BAAALAAECgEIAQAAAA==.Arúgál:BAAALAAECgEIAgAAAA==.',As='Astaraell:BAAALAADCggIFAABLAAECggIGAAHAMgZAA==.',At='Atomiinus:BAAALAADCggICAABLAAECgMIAwADAAAAAA==.',Au='Au:BAAALAADCgYIBgABLAAECgcIEQADAAAAAA==.Aurium:BAAALAAECgQIBAABLAAECgcIDQADAAAAAA==.',Av='Avesk:BAAALAAECgYIEQAAAA==.Aviael:BAABLAAECoEWAAIIAAcIZSEnEAC0AgAIAAcIZSEnEAC0AgAAAA==.',Aw='Awakes:BAAALAADCggIEQAAAA==.',Az='Azur:BAABLAAECoEZAAIJAAcIkyOhAQDnAgAJAAcIkyOhAQDnAgAAAA==.',['Aí']='Aíthína:BAAALAAECgYIDwAAAA==.',Ba='Badshot:BAAALAAECgEIAQAAAA==.Bagius:BAAALAADCgcIEAAAAA==.Balione:BAAALAADCggICAAAAA==.Bastalion:BAAALAADCgMIAwAAAA==.',Be='Bearie:BAAALAADCgEIAQABLAAECgYICQADAAAAAA==.Bearmittens:BAAALAAECgEIAQAAAA==.Beatnik:BAAALAADCgcIBwAAAA==.Becquin:BAAALAADCggIEwAAAA==.Beedrill:BAAALAADCggIEAAAAA==.Beefie:BAAALAADCggICAAAAA==.Beliall:BAAALAAECgcIEgAAAA==.Bellowmane:BAAALAAECgEIAQAAAA==.Bentoxvi:BAABLAAECoEXAAIKAAcIgRuWGgAnAgAKAAcIgRuWGgAnAgAAAA==.',Bi='Bigdiel:BAAALAAECgQICAAAAA==.Bigmonkworth:BAAALAAECggICAAAAA==.Bismarck:BAAALAAECgYIDAAAAA==.',Bl='Bling:BAAALAADCggICAAAAA==.',Bo='Boyar:BAABLAAECoEZAAILAAcIkB17FABOAgALAAcIkB17FABOAgAAAA==.',Br='Branchy:BAABLAAECoEYAAIMAAcIXCHECQChAgAMAAcIXCHECQChAgAAAA==.Brent:BAAALAAECgEIAQAAAA==.Brioche:BAAALAAECgcIDQAAAA==.Bronix:BAAALAADCgUIBQAAAA==.',Bu='Bubbsielocks:BAAALAADCgYIBgAAAA==.Bubitz:BAABLAAECoEZAAMLAAcI6BQeJQC8AQALAAcI5BQeJQC8AQAIAAMIDg+EdwCZAAAAAA==.Buffunholy:BAAALAAECgEIAQAAAA==.Bumlebien:BAAALAAECgMIAwAAAA==.',Ca='Calipse:BAAALAAECgcIDwAAAA==.Candifloss:BAAALAADCggICwAAAA==.Cartesia:BAAALAAECgYIAwAAAA==.Cathela:BAAALAAECgMIBQAAAA==.Caélia:BAAALAAECgIIAgAAAA==.',Ce='Centavo:BAAALAAECgUICQAAAA==.',Ch='Chayse:BAAALAADCgMIAwAAAA==.Chiaka:BAAALAADCggICAAAAA==.Christymack:BAAALAADCgQIBAAAAA==.Chulainn:BAAALAAECgQICAAAAA==.',Ci='Citrine:BAAALAAECgMIBQAAAA==.',Ck='Ckoffè:BAAALAADCgcIBwAAAA==.',Co='Coffè:BAABLAAECoEZAAIIAAcIeSEMEgChAgAIAAcIeSEMEgChAgAAAA==.Correctus:BAAALAADCgcIBwAAAA==.',Cr='Creatorr:BAABLAAECoEbAAINAAgIVRz0CQB6AgANAAgIVRz0CQB6AgAAAA==.Crona:BAAALAAECgYICQAAAA==.',Da='Daamed:BAAALAAECggICAAAAA==.Daktilo:BAAALAADCggICAAAAA==.Dalyana:BAAALAADCgUIBQAAAA==.Daranthian:BAAALAADCggICAAAAA==.Darkmender:BAAALAAECgYIDgAAAA==.Darkshard:BAAALAADCggICAAAAA==.Darksky:BAAALAAECgIIAgAAAA==.Darkys:BAAALAAECgEIAQAAAA==.Darugga:BAAALAAECgEIAQAAAA==.',De='Deathberry:BAAALAAECgYICAABLAAECgYICQADAAAAAA==.Demonella:BAAALAADCgMIAwAAAA==.Dens:BAAALAADCgIIAgAAAA==.Deobelix:BAAALAAECgEIAQAAAA==.Derkit:BAAALAAECgUIBQABLAAECgYICQADAAAAAA==.Destorm:BAAALAADCgcIBwAAAA==.',Di='Diamondheart:BAAALAAECgQICQAAAA==.Dionysia:BAAALAADCgYIBwAAAA==.',Dj='Djennaa:BAAALAAECgYICgAAAA==.',Do='Dooiekoe:BAAALAADCggIDgAAAA==.Dora:BAAALAAECgEIAQAAAA==.',Dr='Dracalid:BAAALAAECgYIDAAAAA==.Dracsussy:BAAALAADCgcIEwAAAA==.Draecariss:BAAALAADCgcIBwAAAA==.Drakot:BAAALAAECgYIEQAAAA==.Dreamàh:BAAALAAECgEIAQAAAA==.Droneth:BAAALAADCggIEwAAAA==.Drool:BAAALAADCggICwAAAA==.Drpoolittle:BAAALAAECgIIAgAAAA==.',Du='Duckula:BAAALAADCgQIBAAAAA==.',Dy='Dyarte:BAAALAAECgQIBQAAAA==.Dyendra:BAAALAADCgcIBwAAAA==.',Eb='Ebit:BAABLAAECoEUAAIOAAgI3xQRCgAqAgAOAAgI3xQRCgAqAgAAAA==.Eblino:BAAALAADCggIEwAAAA==.',Ec='Echidna:BAAALAAECgYIAgAAAA==.',Ed='Edgypriest:BAAALAAECgYIBgAAAA==.',Ee='Eef:BAAALAAFFAIIAgAAAA==.Eefoker:BAAALAAECgUICgABLAAFFAIIAgADAAAAAA==.',Ef='Efie:BAAALAAECgYIEQAAAA==.',El='Elcandy:BAAALAAECgMIBgAAAA==.Elementuss:BAAALAAECgcIDAAAAA==.Elléndruil:BAAALAAECggIDAAAAA==.Eloen:BAAALAAECgQICAAAAA==.Elément:BAAALAADCgQIBAABLAAECgcIFwALAMwdAA==.',Es='Esmeraud:BAAALAAECgIIBAAAAQ==.',Ev='Evanesce:BAAALAAECgMIBQAAAA==.Evkr:BAAALAADCggIDQAAAA==.',Ex='Exitium:BAAALAAECgIIAgAAAA==.Exonym:BAABLAAECoEXAAIPAAgIUwu0RQBlAQAPAAgIUwu0RQBlAQAAAA==.Ext:BAAALAAECgIIAgAAAA==.Exterminans:BAAALAAECgYIEAAAAA==.',Fa='Fakelock:BAAALAAECgMIBAAAAA==.Fanný:BAABLAAECoEdAAILAAgIyx04DAC0AgALAAgIyx04DAC0AgAAAA==.',Fe='Fee:BAAALAAECgMIAwABLAAFFAIIAgADAAAAAA==.Felseagal:BAAALAAECgMIAwAAAA==.Fenchurch:BAAALAAECgQICAAAAA==.',Fj='Fjas:BAAALAADCgcIBwAAAA==.',Fl='Flamé:BAAALAAECgYIBgAAAA==.Flokii:BAAALAAECgYICQAAAA==.Floorpov:BAABLAAECoEXAAIQAAcIBRurKwAcAgAQAAcIBRurKwAcAgAAAA==.',Fo='Fomeen:BAABLAAECoEYAAIRAAgISxoBAwBvAgARAAgISxoBAwBvAgAAAA==.Fomevoker:BAAALAAECgYIDwABLAAECggIGAARAEsaAA==.Formaggio:BAAALAADCgEIAQAAAA==.Foxish:BAAALAAECgIIAgAAAA==.',Fr='Frankard:BAAALAADCgYIBgABLAAECgIIBAADAAAAAQ==.Frankkie:BAAALAADCgQIBAABLAAECgIIBAADAAAAAQ==.Frozenella:BAAALAADCgcIFAAAAA==.Frugtplukker:BAAALAAECgMIAwAAAA==.Frygaa:BAAALAAECgYICQAAAA==.',Fu='Fujikawa:BAAALAADCggIEwAAAA==.',['Fú']='Fúry:BAAALAADCggIDgABLAAECgcIFwALAMwdAA==.',Ga='Gameover:BAAALAADCgEIAQAAAA==.Ganar:BAAALAADCggICAABLAAECggIFQASAOUjAA==.Gandrayda:BAABLAAECoEWAAITAAcIJhGbGwCbAQATAAcIJhGbGwCbAQAAAA==.',Ge='Gentildonna:BAAALAAECgIIAgAAAA==.Geogar:BAAALAAECgIIAgAAAA==.',Gh='Ghøstøf:BAAALAAECgYIEAAAAA==.',Gi='Girlkisser:BAAALAAECgEIAQAAAA==.',Gn='Gnomié:BAAALAAECgcICQAAAA==.',Go='Goldenlight:BAAALAADCgcIBwAAAA==.',Gr='Graume:BAAALAAECgEIAgAAAA==.Grexsa:BAAALAADCgQIBAAAAA==.Greyworg:BAAALAAECgEIAQAAAA==.Grimaldor:BAAALAADCgYIDwAAAA==.Grimdark:BAAALAADCggIEAAAAA==.Grimreapers:BAAALAAECgEIAQAAAA==.Gríndan:BAABLAAECoEXAAIUAAcILQ78UACcAQAUAAcILQ78UACcAQAAAA==.',Gw='Gwýn:BAAALAAECgYIDAAAAA==.',He='Healyourself:BAAALAAECgEIAQAAAA==.Hejtsphere:BAAALAAECgYIDwAAAA==.Henna:BAAALAAECgQICAAAAA==.',Hi='Higgz:BAAALAAECgQICAAAAA==.',Ho='Hokath:BAAALAAECgYIDgAAAA==.Holey:BAAALAADCgEIAQAAAA==.Holylíght:BAAALAAECgUIBQAAAA==.Homer:BAAALAAECgIIAgAAAA==.',Hu='Hunira:BAAALAADCgIIAgAAAA==.Hurtzogud:BAAALAADCgEIAQAAAA==.',Hy='Hymne:BAAALAAECgEIAgAAAA==.',['Hö']='Hörny:BAAALAADCgIIAgAAAA==.',Il='Ilthalas:BAAALAADCggICAAAAA==.',Im='Imsoocunning:BAAALAAFFAIIAwAAAA==.Imsooscaley:BAAALAADCggIDAAAAA==.Imsootwisted:BAAALAADCgQIBAABLAAFFAIIAwADAAAAAA==.Imtoohot:BAABLAAECoEbAAIMAAgI7COPAwAIAwAMAAgI7COPAwAIAwAAAA==.',In='Inkotron:BAAALAAECgYICgAAAA==.',Is='Isilmë:BAAALAAECgYIEQAAAA==.Islandstone:BAAALAAECgEIAQAAAA==.',It='Itea:BAAALAADCggIDgAAAA==.',Iv='Ivoxe:BAAALAADCggIFQAAAA==.',Iz='Izere:BAAALAADCggIDgAAAA==.',Ja='Jaqenn:BAAALAAECgYICQAAAA==.Jasdeepti:BAAALAAECgEIAQAAAA==.Jathbean:BAAALAAECgEIAQAAAA==.',Je='Jedhunter:BAAALAAECgIIAgAAAA==.Jenni:BAAALAADCggICgAAAA==.Jerrod:BAAALAADCggICAAAAA==.',Jj='Jjake:BAAALAAECgMIAwAAAA==.',Jo='Joyquils:BAAALAADCggIEAAAAA==.',Jt='Jtod:BAAALAADCgEIAQAAAA==.',Ka='Kaira:BAAALAAECgEIAQAAAA==.Kaistra:BAAALAADCgEIAQAAAA==.Kalnesh:BAAALAADCgUIBQAAAA==.Kamakrazee:BAAALAADCgcICQAAAA==.Karboz:BAAALAADCggICAAAAA==.Karog:BAAALAADCgcIAQAAAA==.Karza:BAAALAADCgcIBwAAAA==.Kazaria:BAAALAAECgYIEAAAAA==.Kazgaroth:BAAALAADCgYIBgAAAA==.Kazmilurshul:BAAALAAECgQICAAAAA==.',Ke='Keflá:BAAALAAECgIIAgAAAA==.Keirasky:BAAALAAECgEIAQAAAA==.Kekimir:BAAALAAECgcICAAAAA==.Kelestra:BAAALAADCgIIAgAAAA==.Kendwa:BAAALAADCgcIBwAAAA==.Ketsuri:BAAALAAECgMIAwAAAA==.',Ki='Killshot:BAAALAAECgcIDgAAAA==.Kilzzor:BAAALAAECggIEwAAAA==.',Kl='Klaster:BAAALAAECgIIAgAAAA==.Klein:BAAALAAECgYICQAAAA==.Kleinmage:BAAALAADCggICAABLAAECgYICQADAAAAAA==.',Ko='Kortväxt:BAAALAAECgYIBgAAAA==.Koshu:BAABLAAECoEYAAMFAAcIsQjOLwBrAQAFAAcIsQjOLwBrAQAMAAYI4wPhUwDFAAAAAA==.Kovelok:BAABLAAECoEXAAIHAAcI1RlzGwAdAgAHAAcI1RlzGwAdAgAAAA==.',Kr='Kraky:BAAALAAECgcICwAAAA==.Kraumdekay:BAABLAAECoEZAAMVAAcIxCIQMwAKAgAVAAYI8h4QMwAKAgAWAAMISCQMIwAvAQAAAA==.Kreetol:BAAALAAECgYIEgAAAA==.Krizulgrimm:BAABLAAECoEWAAIXAAcIABo7CgAkAgAXAAcIABo7CgAkAgABLAAECgcIFwAUAC0OAA==.Krriz:BAAALAAECgYICQABLAAECgcIFwAUAC0OAA==.Krullet:BAAALAAECgYICgAAAA==.',Ky='Kyomag:BAAALAAECgYIBQAAAA==.',La='Lantex:BAABLAAECoEZAAIYAAcIuxbeDADOAQAYAAcIuxbeDADOAQAAAA==.Lantexbrew:BAAALAADCgQIBAABLAAECgcIGQAYALsWAA==.Lawrence:BAAALAADCgMIAwAAAA==.Laz:BAABLAAECoEbAAIWAAgIdCHIAwDtAgAWAAgIdCHIAwDtAgAAAA==.',Le='Lech:BAAALAAECgYIEAAAAA==.Lethora:BAABLAAECoEZAAIZAAcI3RwfCgA/AgAZAAcI3RwfCgA/AgAAAA==.Letsbeatit:BAAALAADCgcIBwAAAA==.Leuka:BAAALAAECgYIEQAAAA==.Levantah:BAAALAADCgcICgAAAA==.Lexà:BAAALAAECgUIBgAAAA==.',Li='Lightjumper:BAAALAAECgYIDAAAAA==.Litencognac:BAAALAADCggIBgAAAA==.Littlewolf:BAAALAADCgIIAgAAAA==.',Lo='Lortto:BAAALAADCggICAAAAA==.Lotharlight:BAAALAADCgcIBwAAAA==.',Lu='Lukastrasz:BAABLAAECoEWAAQaAAcIoAn3EgBCAQAaAAcIoAn3EgBCAQAbAAEImRLMDAAvAAAEAAEIlgdzRQArAAAAAA==.Luresa:BAAALAAECgYIDAAAAA==.Lutherlight:BAAALAADCggIHgAAAA==.Luxie:BAAALAADCgcIGwAAAA==.',Ly='Lyxet:BAAALAADCggIFwAAAA==.',['Lí']='Líght:BAAALAADCggICgABLAAECgcIFwALAMwdAA==.',Ma='Magnusson:BAAALAAECgIIAgAAAA==.Maid:BAAALAAECggICAAAAA==.Makariorc:BAABLAAECoEYAAIcAAcI5BKDJwDeAQAcAAcI5BKDJwDeAQAAAA==.Makusa:BAAALAADCgcICAAAAA==.Malania:BAAALAAECggIDwAAAA==.Maldram:BAAALAAECgMIAwAAAA==.Marwell:BAAALAAECgMIAwAAAA==.Maryvonne:BAAALAAECgMIBgAAAA==.',Mc='Mcfishy:BAAALAADCggIDQAAAA==.Mctha:BAAALAAECgMIAwAAAA==.',Me='Meddyg:BAABLAAECoEUAAQHAAgIHAzEJgDAAQAHAAgIHAzEJgDAAQAdAAMIwQ+tFACzAAAKAAEIwAO8eAApAAAAAA==.Meradah:BAAALAAECgYIEQAAAA==.',Mi='Minihelland:BAABLAAECoEYAAIeAAgI1B4GAgDfAgAeAAgI1B4GAgDfAgAAAA==.Mirable:BAAALAAECgMIAgAAAA==.Mistreskarai:BAAALAAECgUIBwAAAA==.',Mo='Moirraine:BAAALAADCggICwAAAA==.Mono:BAABLAAECoEZAAIEAAcIJh/QDQB7AgAEAAcIJh/QDQB7AgAAAA==.Monsterbaby:BAAALAADCggIGAAAAA==.Moolow:BAAALAADCgIIAgAAAA==.Mormonk:BAAALAAECgEIAQAAAA==.Morphdem:BAAALAAECgYIEgAAAA==.Mozzihn:BAAALAAECgIIAgAAAA==.',Mu='Mulberry:BAABLAAECoEYAAIPAAcIXh0KIAARAgAPAAcIXh0KIAARAgAAAA==.Mulgor:BAAALAADCggIEwAAAA==.Mundis:BAAALAADCgEIAQAAAA==.Muonspeed:BAAALAADCggIDAAAAA==.',['Má']='Mánimal:BAABLAAECoEXAAILAAcIzB1hEwBbAgALAAcIzB1hEwBbAgAAAA==.',Na='Nagur:BAAALAAECgEIAQAAAA==.Nagz:BAAALAAECgEIAgAAAA==.Nahoras:BAAALAAECgYICQAAAA==.Nalona:BAAALAAECgYIEQAAAA==.Namedrop:BAABLAAECoEgAAINAAgIpSTyAQBPAwANAAgIpSTyAQBPAwAAAA==.Namedropped:BAAALAADCggIDQABLAAECggIIAANAKUkAA==.Nazkerban:BAAALAAECgEIAQAAAA==.',Ne='Nentia:BAAALAAECgYIBwAAAA==.Neosmoke:BAAALAADCgYICAAAAA==.Neshi:BAAALAAECgYICgAAAA==.Netheron:BAABLAAECoEXAAMfAAcIrBJtGwC5AQAfAAYIcBNtGwC5AQAgAAUIuQrzWAAJAQAAAA==.Nevaeh:BAAALAAECgIIAQAAAA==.',Ni='Nidriel:BAAALAAECgQICAAAAA==.Nightdark:BAAALAADCggIEgAAAA==.Nivarys:BAAALAAECgYIDQAAAA==.',No='Nokron:BAAALAADCggICAAAAA==.Nomilian:BAAALAADCggIDwAAAA==.Nommy:BAAALAADCgcIDAAAAA==.Nooneknownme:BAAALAAECgYIDAAAAA==.',Nu='Numidia:BAAALAAECgEIAQAAAA==.',Nx='Nx:BAAALAAECgcIEQAAAA==.',Ny='Nyshu:BAABLAAECoEVAAIQAAgIMCRCCAAtAwAQAAgIMCRCCAAtAwAAAA==.Nyshú:BAAALAAECgYIDgABLAAECggIFQAQADAkAA==.',['Nà']='Nàmedrop:BAAALAADCggICAABLAAECggIIAANAKUkAA==.',['Ná']='Nádja:BAAALAADCgcIBwABLAAECgQIBAADAAAAAA==.',['Nè']='Nèko:BAAALAADCggIGAAAAA==.',['Nó']='Nózomi:BAAALAADCggIFQABLAAECgYIEgADAAAAAA==.',Of='Off:BAAALAAECgYIEQAAAA==.',Oj='Ojobe:BAAALAAECgEIAQAAAA==.',Ol='Oliminus:BAAALAAECggIEQAAAA==.',Om='Omgetosnakey:BAAALAADCggIEAAAAA==.',On='Oneshock:BAAALAAECgYIDAAAAA==.Onimu:BAAALAAECgYIDwAAAA==.Onlybrews:BAAALAAECgcIEAAAAA==.',Or='Oredos:BAAALAAECgQICAAAAA==.',Pa='Palaisakern:BAAALAADCgYIBgAAAA==.Palkei:BAAALAAECgIIAgAAAA==.Pandabuffel:BAAALAAECgQIBAAAAA==.',Pe='Peloa:BAAALAADCggICAAAAA==.Perfectdark:BAAALAAECgEIAQAAAA==.',Pn='Pnepnepne:BAAALAAECgEIAQAAAA==.',Po='Portalgeist:BAAALAAECgYIDwAAAA==.',Pr='Price:BAAALAAECgcIDwAAAA==.Prillan:BAAALAADCggIFAAAAA==.',Ql='Qloosanka:BAAALAADCgEIAQAAAA==.',Qu='Quilchex:BAAALAAECgEIAgAAAA==.',Ra='Rack:BAAALAAECggIBwABLAAECggICAADAAAAAA==.Rammlied:BAAALAAECgcICwAAAA==.Raptorgodx:BAAALAAECggICAAAAA==.Rayce:BAAALAAECgYICQAAAA==.',Re='Reiyou:BAABLAAECoEYAAIHAAgIyBn6DwCYAgAHAAgIyBn6DwCYAgAAAA==.Rellia:BAAALAAECgMIAwAAAA==.Rephaim:BAAALAAECgEIAQAAAA==.Retbully:BAAALAAECgYIDwAAAA==.',Ri='Rigtze:BAABLAAECoEaAAIhAAgIvRQ+EAApAgAhAAgIvRQ+EAApAgAAAA==.Ririzuha:BAAALAAECgcIDQAAAA==.Rissmien:BAAALAADCggIHgAAAA==.',Ro='Rogueflax:BAAALAAECgYICwAAAA==.Romeomo:BAAALAADCggICgAAAA==.',Ru='Ruth:BAABLAAECoEYAAMgAAgI8xA0LwDKAQAgAAgIew00LwDKAQAfAAUI+RLrLABRAQAAAA==.Ruud:BAAALAADCgcIBwAAAA==.',Rv='Rvck:BAAALAAECgQIAwAAAA==.',['Rú']='Rúkia:BAAALAAECgYIEgAAAA==.',Sa='Sadammo:BAAALAAECgYIEQAAAA==.Saman:BAAALAAFFAEIAQAAAA==.Sarshá:BAAALAADCgMIAwAAAA==.',Se='Segath:BAAALAAECgYIDgAAAA==.Seleen:BAAALAAECgEIAQAAAA==.Setupp:BAAALAAECgEIAQAAAA==.',Sh='Shakdan:BAAALAAECgcIEgAAAA==.Shamsham:BAAALAAECgYIDgAAAA==.Shayadin:BAAALAADCgIIAgAAAA==.Sheinam:BAAALAAECgEIAgAAAA==.Shooker:BAAALAAECgQICgABLAAECgYICQADAAAAAA==.Shoorka:BAAALAADCgMIAwAAAA==.Shortcakes:BAAALAADCggICAAAAA==.Shrando:BAAALAAECgcIEAAAAA==.Shylanai:BAAALAADCgQIBAAAAA==.',Si='Siegrain:BAAALAADCgMIAwAAAA==.Sikkertlunar:BAAALAAECgYIBwAAAA==.Sikstis:BAAALAADCgcICAAAAA==.',Sj='Sjöjohan:BAAALAADCggICQAAAA==.',Sk='Skridtspark:BAAALAAECgYIEQAAAA==.Skêlar:BAAALAAECgYIEQAAAA==.',Sl='Slayallmonks:BAAALAAECgYICgAAAA==.Slayforfun:BAAALAADCggICAAAAA==.Slaythedudu:BAAALAAECgcIDgAAAA==.Slaytheshamy:BAAALAAECgYIBQAAAA==.',Sn='Snabbchaos:BAABLAAECoEaAAQfAAgIQRYuEgACAgAfAAcIrRcuEgACAgAgAAQIQgukYQDbAAAJAAIIFAIcKQBdAAAAAA==.Snabbexecute:BAABLAAECoEUAAISAAgIphhQGgBIAgASAAgIphhQGgBIAgAAAA==.Snabbjeavel:BAAALAADCggIDgAAAA==.Snaccthyr:BAAALAAECgYICQAAAA==.Sneakysnakey:BAAALAAECgYICgAAAA==.Snorlaxlover:BAAALAADCgEIAgAAAA==.',So='Soak:BAABLAAECoEXAAIiAAgItR15GQCWAgAiAAgItR15GQCWAgAAAA==.Sofera:BAAALAAECgMIBgAAAA==.Solniaz:BAAALAADCgcIDQAAAA==.Sonos:BAAALAAECgYIDgAAAA==.Sootú:BAAALAAECgYICQAAAA==.',St='Stennup:BAABLAAECoEdAAISAAgIrh2pDwC7AgASAAgIrh2pDwC7AgAAAA==.Stickytoffee:BAAALAADCggICAAAAA==.Stormchrome:BAAALAADCggICAAAAA==.Stryk:BAABLAAECoEYAAINAAgIYRoNDABUAgANAAgIYRoNDABUAgAAAA==.Stuntress:BAAALAAECgYIDwAAAA==.Stur:BAAALAADCgYIBwAAAA==.',Su='Sunzi:BAAALAAECgEIAQAAAA==.Surelîa:BAAALAADCgYIBgAAAA==.Survivor:BAAALAADCgcIBwAAAA==.Sushy:BAABLAAECoEVAAMPAAgI6SCfCgCxAgAPAAgI6SCfCgCxAgAcAAUIVhU8PQBqAQAAAA==.',Sy='Sylveria:BAAALAAECgMIBQAAAA==.Syraxx:BAAALAAECggIEgAAAA==.',Ta='Taivokershan:BAAALAAECgYIDAAAAA==.Talevane:BAAALAAECgMIAwAAAA==.Talzin:BAAALAAECgEIAQAAAA==.Tansari:BAAALAAECgQIBwAAAA==.Tawny:BAAALAAECgYIBgAAAA==.',Te='Tehmoshi:BAAALAADCggIDAAAAA==.Tellusia:BAAALAAECgIIAgAAAA==.Terribletim:BAAALAAECgYICQAAAA==.Terzal:BAAALAAECgYIEQAAAA==.',Th='Tharain:BAAALAADCgQIBgAAAA==.Theryandh:BAAALAAECgYIEQAAAA==.Theserpent:BAAALAAECgYIDAAAAA==.This:BAAALAAECgEIAQABLAAECgYIEQADAAAAAA==.Thriela:BAAALAAECgYIDwAAAA==.Thrilmi:BAAALAAECgMIAwAAAA==.Thumert:BAAALAADCgMIAwAAAA==.Thunderbonk:BAAALAAECgcIDQAAAA==.Thunk:BAEBLAAECoEZAAMSAAcIpyEAEgCeAgASAAcIcSAAEgCeAgAeAAMIDhelFADdAAAAAA==.',Ti='Tidess:BAAALAAECgQIBAAAAA==.Tidex:BAAALAADCgUIBQAAAA==.Tiffania:BAAALAADCggICAAAAA==.Timedwalker:BAAALAADCggICAAAAA==.',To='Tondar:BAAALAAECgUIBQAAAA==.Toxsin:BAAALAAFFAIIBAAAAA==.',Tr='Truenaro:BAAALAADCgQIBAAAAA==.',Tu='Tuern:BAAALAAECgEIAQAAAA==.Tulehaamer:BAAALAADCgQIBAAAAA==.Turinel:BAAALAADCgQICQAAAA==.',Tw='Twijg:BAAALAAECgEIAQAAAA==.',Us='Uski:BAAALAADCgcICAAAAA==.Usucka:BAAALAAECgUICgAAAA==.',Va='Vaelion:BAAALAADCgIIAgAAAA==.Valarrow:BAABLAAECoEbAAILAAgIvReFGgARAgALAAgIvReFGgARAgABLAAECggIFQAFAAIaAA==.Valdraugr:BAAALAADCggIEwABLAAECggIFQAFAAIaAA==.Valentijne:BAAALAAECgEIAQAAAA==.Valgus:BAAALAADCgEIAQAAAA==.Valzan:BAABLAAECoEVAAMSAAgI5SMyCgD+AgASAAgI0SMyCgD+AgAeAAIIaSTFFgC3AAAAAA==.Vanator:BAAALAADCggICAAAAA==.Vansinne:BAAALAADCgYIDAAAAA==.Variety:BAAALAADCgMIAgAAAA==.',Ve='Vegapunk:BAAALAADCgIIAgAAAA==.',Vi='Vinca:BAAALAAECgYIBgAAAA==.',Vo='Voidine:BAAALAADCggIGAABLAAECggIHQALAMsdAA==.Vonadin:BAAALAAECgcIBwAAAA==.',Wa='Waka:BAAALAAECgIIAwAAAA==.Waltz:BAAALAADCgUIBQAAAA==.Warpíg:BAAALAADCgcIBwAAAA==.Washini:BAAALAAECgIIBAAAAA==.',We='Weehaggis:BAAALAAECgcIBgABLAAECgYIBQADAAAAAA==.Weriess:BAAALAAECgIIBAAAAA==.',Wi='Wiggzz:BAABLAAECoEWAAIeAAcISw5oCwCVAQAeAAcISw5oCwCVAQAAAA==.Wizesson:BAAALAADCgcIBwAAAA==.',Wo='Wombatt:BAAALAAECgIIAgAAAA==.',Wt='Wtypestuff:BAAALAAECggIEgAAAA==.',Wy='Wyneris:BAAALAADCgUIBQAAAA==.',['Wî']='Wîccan:BAAALAADCggIDAAAAA==.',Xa='Xaivi:BAAALAADCgIIAgAAAA==.',Xe='Xenil:BAAALAADCgUIBQAAAA==.',Xi='Xibron:BAAALAADCgYIBgAAAA==.',Xy='Xyrien:BAAALAAECgYIEgAAAA==.',Ya='Yasukí:BAAALAADCggICAAAAA==.',Ye='Yeule:BAAALAAECgcIDQAAAA==.',Yi='Yilae:BAAALAADCggIDwABLAAECgcIEQADAAAAAA==.',Yl='Ylwenah:BAAALAAECgEIAQAAAA==.',Yo='Yondan:BAAALAAECgYICwAAAA==.Yorghul:BAAALAADCgcICQAAAA==.Yorù:BAAALAADCgcIDwAAAA==.',Yu='Yuelral:BAAALAADCgQIBAAAAA==.Yuka:BAAALAAECgYIDAAAAA==.',Za='Zahhak:BAAALAADCggIEAAAAA==.Zamadrax:BAAALAAFFAEIAQAAAA==.Zanarkand:BAAALAAECgYIDwAAAA==.Zanechan:BAAALAADCggICAAAAA==.Zas:BAAALAAECggIEAAAAA==.',Ze='Zehír:BAAALAADCgIIAgAAAA==.Zemel:BAAALAAECgIIAgAAAA==.Zenpiggy:BAAALAADCggICwAAAA==.Zenryo:BAAALAAECgYIEQAAAA==.Zetix:BAAALAAECgYIDgAAAA==.',Zh='Zhaneel:BAAALAAECgQICAABLAAECggIGAAEAA0aAA==.',Zu='Zuleun:BAAALAAECgcICQAAAA==.',Zv='Zvijer:BAABLAAECoEZAAISAAcIth9NGABaAgASAAcIth9NGABaAgAAAA==.',['Án']='Ánorx:BAAALAAECggICwAAAA==.',['Çy']='Çyph:BAAALAAECgYIEQAAAA==.',['Øl']='Ølglass:BAAALAAECgcIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end