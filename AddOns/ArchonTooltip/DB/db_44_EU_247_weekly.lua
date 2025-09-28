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
 local lookup = {'Shaman-Restoration','Unknown-Unknown','Paladin-Holy','Druid-Restoration','Druid-Feral','Hunter-BeastMastery','Paladin-Retribution','Druid-Balance','Shaman-Elemental','Hunter-Marksmanship','Priest-Shadow','DeathKnight-Frost','Mage-Arcane','Warrior-Fury','Warrior-Protection','DemonHunter-Havoc','Mage-Frost','Paladin-Protection','DeathKnight-Blood','DeathKnight-Unholy','Druid-Guardian','Warlock-Demonology','Monk-Brewmaster','DemonHunter-Vengeance','Warlock-Destruction','Hunter-Survival','Rogue-Assassination','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Warlock-Affliction','Rogue-Outlaw','Priest-Discipline','Rogue-Subtlety','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation',}; local provider = {region='EU',realm='AeriePeak',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abit:BAABLAAECoEjAAIBAAgIuB4LHwByAgABAAgIuB4LHwByAgAAAA==.',Ad='Adelae:BAAALAADCgMIAwAAAA==.Adnior:BAABLAAECoEfAAIBAAcIcAkiogD0AAABAAcIcAkiogD0AAAAAA==.Advo:BAAALAADCggICAAAAA==.Advocatas:BAAALAAECggICgAAAA==.Advocatus:BAAALAADCgYIBgAAAA==.Adysor:BAAALAAECgQIBAABLAAECgQIBwACAAAAAA==.',Ae='Aeden:BAABLAAECoEYAAIDAAcIpxqGFgArAgADAAcIpxqGFgArAgAAAA==.Aelistrea:BAAALAADCgMIBAAAAA==.Aewin:BAABLAAECoEgAAMEAAgIkBr/GABrAgAEAAgIkBr/GABrAgAFAAMIKA9UMQCgAAAAAA==.',Ai='Aimeh:BAABLAAECoEcAAIGAAYI2hqhYQC2AQAGAAYI2hqhYQC2AQAAAA==.',Ak='Akpallus:BAABLAAECoEWAAIHAAgIlRKuYwDtAQAHAAgIlRKuYwDtAQAAAA==.Akïra:BAAALAADCgQIBAAAAA==.',Al='Alexantrias:BAAALAAECgYIBgAAAA==.Alinush:BAAALAAECgEIAQABLAAECgQIBwACAAAAAA==.Alià:BAABLAAECoEZAAIIAAgIzhCTLQDYAQAIAAgIzhCTLQDYAQAAAA==.Alshai:BAAALAADCgcIBwAAAA==.Altruic:BAABLAAECoEZAAMBAAgIexerNQATAgABAAgIexerNQATAgAJAAYIRAhabwAlAQAAAA==.Alyssaria:BAAALAADCgQIBAAAAA==.Alythae:BAAALAADCggIEAAAAA==.',Am='Amelya:BAAALAADCggIIwAAAA==.Ametza:BAAALAAECggICAAAAA==.',An='Andie:BAAALAADCgYIBgAAAA==.Andkattdwarf:BAAALAAECgIIAwAAAA==.Andrei:BAAALAAECgYIBgAAAA==.Anduriel:BAABLAAECoEXAAMKAAcIDiVGEgC9AgAKAAcIoyRGEgC9AgAGAAEILSNG9gBWAAAAAA==.Angeluna:BAAALAAECggIDQAAAA==.Angie:BAABLAAECoEcAAMDAAgIGhFBIADbAQADAAgIGhFBIADbAQAHAAQIPAbb+gCvAAAAAA==.Angryeler:BAABLAAECoEYAAIJAAcI6g6UTwCVAQAJAAcI6g6UTwCVAQAAAA==.Annara:BAAALAAECgUICwAAAA==.Antor:BAAALAADCgYIBgAAAA==.',Ar='Aramathaya:BAAALAAECgQIBwAAAA==.Araya:BAAALAADCgcICQAAAA==.Arcadias:BAABLAAECoEmAAILAAgIcAq9PQCfAQALAAgIcAq9PQCfAQAAAA==.Arcangle:BAAALAAECgUIBQAAAA==.Arcanimagus:BAAALAAECgMIAwAAAA==.Arenthel:BAAALAADCgUIBQABLAAFFAMIBQAMAGsLAA==.Armadi:BAAALAADCgYIEQAAAA==.Arminor:BAAALAADCgcIBwAAAA==.Arodius:BAAALAADCgcIDgAAAA==.Arthok:BAAALAAECgYIDgAAAA==.Arthurdayne:BAAALAAECgMIBAABLAAECggIJQANANgaAA==.Arxontas:BAAALAADCggICAAAAA==.',As='Ashhgaming:BAAALAADCggICwAAAA==.Aspenleaf:BAAALAAECgYICgABLAAECgcIGwAGACsXAA==.',At='Atnub:BAAALAAECgYICAAAAA==.Atorias:BAAALAADCggICAAAAA==.Atriohm:BAAALAADCgcIBwAAAA==.',Au='Audey:BAAALAADCgMIAwAAAA==.Aureliae:BAAALAAECgQIBAAAAA==.Auridel:BAAALAAECggICAAAAA==.',Av='Avaan:BAAALAADCggICAABLAAECggIJgALAHAKAA==.',Az='Azrift:BAAALAADCgcIBwAAAA==.Azunath:BAAALAAECgMIBQAAAA==.',Ba='Bababooie:BAABLAAECoEnAAIOAAgIpRxjHwCeAgAOAAgIpRxjHwCeAgAAAA==.Badpala:BAAALAAECgMIAwAAAA==.Badpriester:BAAALAAECgYICgAAAA==.Baldrax:BAAALAADCggICAAAAA==.Balmdur:BAAALAAECggICQAAAA==.Baltic:BAAALAADCggIGgAAAA==.',Be='Bearace:BAACLAAFFIENAAIIAAQIuRYyBgBTAQAIAAQIuRYyBgBTAQAsAAQKgS4AAggACAi2JSYDAGUDAAgACAi2JSYDAGUDAAAA.Beardiweirdi:BAAALAAECgEIAQAAAA==.Befreiung:BAAALAADCgcIBwAAAA==.Bereket:BAABLAAECoEgAAIPAAgI+xcaGAA5AgAPAAgI+xcaGAA5AgAAAA==.Beyfu:BAAALAAECgUIBwAAAA==.Beyrol:BAAALAAECgIIAgAAAA==.',Bi='Bigbadbull:BAAALAADCgEIAQABLAAFFAMICgAPALEMAA==.Billidan:BAAALAADCggIFwAAAA==.Bipsié:BAACLAAFFIEHAAIQAAMImRCNEQD0AAAQAAMImRCNEQD0AAAsAAQKgSwAAhAACAhWI4EPAB4DABAACAhWI4EPAB4DAAAA.',Bl='Blackadder:BAAALAAECgYIDAAAAA==.Blasterm:BAAALAAECgYICQAAAA==.Blinks:BAAALAADCggICAAAAA==.Bloodmagik:BAAALAADCgEIAQAAAA==.',Bo='Bodziu:BAABLAAECoEcAAMRAAcIAA9oOABlAQANAAcIXwjDfwBlAQARAAYI2xBoOABlAQAAAA==.Bottimus:BAAALAADCggICAAAAA==.Bouhunter:BAABLAAECoEoAAIGAAgIOBcKQgAOAgAGAAgIOBcKQgAOAgAAAA==.',Br='Brickchewer:BAABLAAECoEgAAIMAAgIwhfCQgBIAgAMAAgIwhfCQgBIAgAAAA==.Broony:BAAALAADCggIFAABLAADCggIGgACAAAAAA==.',Bu='Buckybckbtch:BAAALAADCggIDwAAAA==.Buddala:BAABLAAECoEhAAMHAAgILBPBdgDFAQAHAAgIVBLBdgDFAQASAAYI+Q6IMgAqAQAAAA==.Bullstomper:BAAALAAECgEIAQAAAA==.',['Bó']='Bóz:BAABLAAECoEdAAIOAAgIER9yGADPAgAOAAgIER9yGADPAgAAAA==.',Ca='Cailin:BAAALAAECgIIAgAAAA==.Calaelen:BAAALAAECgUICgAAAA==.Callistra:BAAALAADCgcIBwAAAA==.Carcossa:BAAALAADCgcIBwABLAAFFAMICAABAAIlAA==.',Ce='Ceder:BAAALAAECgYIBgAAAA==.Celestaine:BAAALAADCggICwAAAA==.Celestiin:BAAALAAECgYIDAAAAA==.Cellesta:BAAALAAECgIIBAAAAA==.Cereberos:BAAALAADCgYIBgAAAA==.',Ch='Chaostotem:BAAALAADCggIEQABLAAECgUICgACAAAAAA==.Chazar:BAABLAAECoEVAAIOAAcIxRKcTgDDAQAOAAcIxRKcTgDDAQAAAA==.Chilis:BAAALAADCgYIBgAAAA==.Chillbill:BAAALAAECgMIAwAAAA==.Chomikoski:BAAALAADCgQIBAAAAA==.',Ci='Cirilla:BAAALAADCggIBgAAAA==.',Cj='Cjonas:BAABLAAECoEUAAIFAAYITCRVCwB0AgAFAAYITCRVCwB0AgAAAA==.',Cl='Clam:BAABLAAECoE1AAIIAAgIexK/KAD0AQAIAAgIexK/KAD0AQAAAA==.',Co='Cordisater:BAABLAAECoEjAAIHAAgIzyCpFgD/AgAHAAgIzyCpFgD/AgAAAA==.Corn:BAAALAADCggICQAAAA==.Corraan:BAAALAADCggICAAAAA==.Costae:BAAALAAECgMIBgAAAA==.',Cr='Crayoneater:BAABLAAECoEiAAIOAAcI6h8aIwCGAgAOAAcI6h8aIwCGAgAAAA==.Creedence:BAAALAADCgYIBgAAAA==.Cronoth:BAAALAAECgYIEgAAAA==.Crowidan:BAABLAAECoEZAAIQAAcINgaDrAA1AQAQAAcINgaDrAA1AQAAAA==.',['Cé']='Cénice:BAAALAADCgUIBQAAAA==.',['Có']='Cómpactdísc:BAAALAAECggIDAABLAAECggIFgAIADQOAA==.',Da='Daath:BAABLAAECoEiAAITAAcIUyLmCACiAgATAAcIUyLmCACiAgAAAA==.Dagoat:BAACLAAFFIEGAAIQAAMIrReNEAD8AAAQAAMIrReNEAD8AAAsAAQKgS0AAhAACAh1IsQPAB0DABAACAh1IsQPAB0DAAAA.Darkine:BAAALAADCgIIAgAAAA==.Darkmeld:BAAALAADCggIFgAAAA==.Darkneph:BAAALAAECgUIBQABLAAECgcIEQACAAAAAA==.Darkróse:BAAALAAECgYIDAAAAA==.Darkscarlet:BAAALAAECgYIEAAAAA==.',De='Deamo:BAAALAADCgUIBQAAAA==.Deamonthinut:BAAALAAECggIDQAAAA==.Deathchef:BAABLAAECoEgAAIMAAgInxYeRQBCAgAMAAgInxYeRQBCAgAAAA==.Deathdissent:BAAALAADCgcICAAAAA==.Deathzoef:BAAALAADCggICAABLAAECggIJgAGADYfAA==.Debos:BAAALAADCgMIAwAAAA==.Delfin:BAAALAAECgEIAQAAAA==.Desolate:BAABLAAECoEVAAMUAAcIuR/KCwB8AgAUAAcIuR/KCwB8AgAMAAMIdRc69ADhAAAAAA==.',Di='Diealot:BAAALAAECgQIBAAAAA==.Dionfortune:BAAALAADCgcIAwAAAA==.Dismyr:BAAALAADCgcIEAAAAA==.Dixierect:BAAALAAECgIIAwABLAAECggIKwAKABYlAA==.',Do='Dorchadas:BAAALAADCggIBwAAAA==.',Dr='Draegos:BAAALAAECgIIAgAAAA==.Draendei:BAAALAAECgMIAwAAAA==.Dragula:BAAALAAECggIAwAAAA==.Dreaddemon:BAAALAAECgIIAwAAAA==.Drezlakk:BAAALAAECgUIBQAAAA==.Drimturm:BAABLAAECoEbAAMVAAgI1htsBQCGAgAVAAgI1htsBQCGAgAIAAMIPBYIbwCcAAAAAA==.Drmanháttan:BAAALAADCggIDgAAAA==.Drogrin:BAAALAADCgcIBwAAAA==.Droseros:BAAALAADCgcIBwAAAA==.Drurmargur:BAABLAAECoEgAAMBAAgIrxjlNQASAgABAAgIrxjlNQASAgAJAAcIJgxSUQCOAQAAAA==.',Du='Durildruki:BAAALAADCgIIAgAAAA==.',Dy='Dysphoria:BAAALAAECgYICwAAAA==.',Ed='Edannu:BAAALAADCggIFgAAAA==.Edgarz:BAAALAAECggICAAAAA==.',Eg='Eggshen:BAAALAAECgUICAAAAA==.',El='Elea:BAAALAAECgQIBAAAAA==.Elektrorose:BAAALAAECggIDQAAAA==.Eleonora:BAAALAADCgcICwAAAA==.Elerment:BAABLAAECoEgAAIJAAgIlxccLQAsAgAJAAgIlxccLQAsAgAAAA==.Eliara:BAAALAADCggICAAAAA==.Elria:BAAALAAECgMIAwAAAA==.Elrygos:BAAALAADCggIHwAAAA==.',Em='Emeraldgosa:BAAALAAECgIIAgAAAA==.Emry:BAAALAAECggIEwAAAA==.',Es='Esmeraldi:BAAALAADCggICAAAAA==.',Eu='Euphiee:BAAALAAECgUIBgAAAA==.',Fa='Faralda:BAAALAADCggIEQAAAA==.Faralt:BAAALAADCggICAAAAA==.',Fe='Felon:BAAALAAECgUIBwAAAA==.Felshan:BAAALAADCgIIAgABLAAECggIKQAMAAgkAA==.Ferrin:BAAALAADCggIBwAAAA==.Feyrê:BAAALAADCggIFQABLAAECgcIHwAEADYhAA==.',Fi='Fiction:BAAALAAECgYIDQAAAA==.Fireminth:BAABLAAECoElAAIWAAcIPR/BDACEAgAWAAcIPR/BDACEAgAAAA==.Firescream:BAABLAAECoElAAMNAAgI2BqvLwBqAgANAAgI2BqvLwBqAgARAAMIvQ2taAB2AAAAAA==.',Fl='Floridaman:BAAALAADCggIEAAAAA==.Florinel:BAAALAAECgQIBwAAAA==.',Fo='Forzakenone:BAABLAAECoEYAAMMAAgI7hqWQwBGAgAMAAgIVBmWQwBGAgAUAAcItBTWHAC4AQAAAA==.',Fr='Fraybentos:BAAALAADCggIDgAAAA==.Freeninety:BAAALAAECgYICQAAAA==.Frizlok:BAAALAAECgYICwAAAA==.Frostitutee:BAAALAAECggIDwAAAA==.',Fu='Fudgex:BAAALAADCgMIAwAAAA==.',['Fê']='Fêyre:BAABLAAECoEfAAIEAAcINiGsEQCkAgAEAAcINiGsEQCkAgAAAA==.',Ga='Gabran:BAABLAAECoEYAAIMAAgIHxp3OABpAgAMAAgIHxp3OABpAgAAAA==.Galbatros:BAABLAAECoErAAIBAAgImRvHHAB+AgABAAgImRvHHAB+AgAAAA==.Gamblers:BAAALAAECgUIAwAAAA==.Garbagedrood:BAAALAAECgMIBQAAAA==.Garre:BAABLAAECoEWAAMEAAcIFw5fVQBNAQAEAAcIFw5fVQBNAQAFAAYIWAXFKgDwAAAAAA==.Gascoigne:BAAALAAECgYIBgAAAA==.Gazdalf:BAAALAADCggIBQABLAADCggIGgACAAAAAA==.',Ge='Genghiszan:BAAALAAECgMIAwAAAA==.Gettafixx:BAAALAAECggIEAAAAA==.',Gh='Ghostspectre:BAAALAAECgEIAQAAAA==.',Gl='Glowner:BAAALAADCgcIBwABLAAECggIGAAIALAMAA==.',Go='Gondolock:BAABLAAECoEcAAIWAAgIJhErHQDyAQAWAAgIJhErHQDyAQAAAA==.Gorefriend:BAABLAAECoEdAAIMAAgIriTNEgAQAwAMAAgIriTNEgAQAwAAAA==.Gorlem:BAAALAAECggICwAAAA==.Gospell:BAAALAADCgYICgAAAA==.Gothgirlcliq:BAAALAAECgUIBgAAAA==.',Gr='Grandmagus:BAAALAAECgQIBAAAAA==.Grimmage:BAAALAADCggIEQABLAAECgEIAQACAAAAAA==.Grimmly:BAABLAAECoEYAAIEAAcIpAvkWwA4AQAEAAcIpAvkWwA4AQAAAA==.Grundi:BAAALAADCgYIBgAAAA==.Gruthar:BAAALAAECgYIEgAAAA==.',['Gâ']='Gârgamel:BAAALAAECgMIAwAAAA==.',['Gä']='Gäri:BAAALAAECgcIDAAAAA==.',Ha='Hanako:BAAALAADCggIEAABLAAECggIKgACAAAAAA==.Hardwon:BAAALAAECgIIAgAAAA==.Harikrishna:BAAALAAECgcIDQAAAA==.Hasadiga:BAAALAADCggIEAAAAA==.',He='Healstrasza:BAAALAAECgIIAgAAAA==.Hellshan:BAABLAAECoEpAAMMAAgICCSQDgAnAwAMAAgICCSQDgAnAwATAAII9BHQMwBxAAAAAA==.Hellsplitter:BAAALAADCgYIBgAAAA==.Herculies:BAAALAAECgEIAQAAAA==.Hextoothless:BAAALAADCggIDAAAAA==.',Hi='Hiliduin:BAAALAADCggICgABLAAECggIGQAXAKMcAA==.Hilioama:BAAALAADCgQIBAABLAAECggIGQAXAKMcAA==.Hillee:BAABLAAECoEZAAIXAAgIoxxeCQCiAgAXAAgIoxxeCQCiAgAAAA==.Hirotaka:BAAALAADCgIIAgAAAA==.',Ho='Hornstars:BAAALAAECgcIEAAAAA==.',Hu='Hugorune:BAAALAADCggIBgAAAA==.Hunterm:BAAALAAECgYIDAAAAA==.Huntina:BAABLAAECoEbAAIGAAcIahheWADOAQAGAAcIahheWADOAQAAAA==.Huntressrose:BAAALAAECgQIBAAAAA==.Huntvine:BAAALAADCggIEQAAAA==.Huxsmash:BAAALAADCggICAAAAA==.Huxstormzy:BAAALAAECgYIBgAAAA==.',['Hü']='Hüri:BAABLAAECoEaAAIPAAgIQwNzUgDVAAAPAAgIQwNzUgDVAAAAAA==.',Ia='Iamcurved:BAAALAAECggIEwAAAA==.Iamninja:BAAALAADCggIFAAAAA==.',If='Ifiklis:BAABLAAECoEbAAIHAAcITA76jACZAQAHAAcITA76jACZAQAAAA==.',Il='Ilikecurves:BAABLAAECoEiAAIYAAgIiB+2BgDWAgAYAAgIiB+2BgDWAgAAAA==.Illyiah:BAAALAAECgYIDgAAAA==.',Im='Immortallife:BAAALAAECggIDwAAAA==.Imprasarrial:BAABLAAECoEXAAMBAAgIYR3SGACUAgABAAgIYR3SGACUAgAJAAYI7gsLagA5AQAAAA==.Impravoker:BAAALAAECgYIBgAAAA==.',In='Infekted:BAABLAAECoEiAAMZAAcIlxZcSQDeAQAZAAcI5BVcSQDeAQAWAAYIoROmMwB7AQAAAA==.',Ja='Jackechan:BAAALAADCggICAAAAA==.Jackson:BAAALAAECgYICwAAAA==.Jadá:BAACLAAFFIEJAAIaAAQIvBXKAAAgAQAaAAQIvBXKAAAgAQAsAAQKgSUAAxoACAheJQ4BAEIDABoACAiUJA4BAEIDAAoAAwgzHbB1ANIAAAAA.Jakksy:BAAALAAECgQIBAAAAA==.Jandara:BAAALAADCgYIBgAAAA==.Jayygeh:BAAALAADCgMIAwAAAA==.',Je='Jennefer:BAAALAADCggIBwAAAA==.Jeremykylé:BAABLAAECoEdAAIHAAcIGyKwJAC2AgAHAAcIGyKwJAC2AgAAAA==.Jetlee:BAAALAADCgIIAgABLAAECggIDgACAAAAAA==.',Ji='Jinjuu:BAABLAAECoEpAAIRAAgIYRYQHAAOAgARAAgIYRYQHAAOAgAAAA==.',Jo='Jobje:BAAALAAECggIEAAAAA==.Joony:BAAALAADCgcICwABLAAECgQIBwACAAAAAA==.',Ju='Juddge:BAABLAAECoErAAIVAAgIzAajFwAXAQAVAAgIzAajFwAXAQAAAA==.Juffzh:BAAALAAECgcICgAAAA==.Juipe:BAAALAAECgIIAgAAAA==.',Ka='Kaboose:BAAALAAECgMIAwAAAA==.Kaidasen:BAAALAAECgIIAgABLAAFFAQIDAABAO8JAA==.Kaidazen:BAACLAAFFIEMAAIBAAQI7wn6DAD0AAABAAQI7wn6DAD0AAAsAAQKgSsAAgEACAgXFmZFAN0BAAEACAgXFmZFAN0BAAAA.Kapsokolis:BAAALAADCggICQAAAA==.',Ke='Kealsith:BAAALAADCgQIBAAAAA==.Kelain:BAAALAAECgYIBgABLAAECggIJQANANgaAA==.Keldris:BAAALAADCggICAAAAA==.Keun:BAAALAAECgcIEAAAAA==.',Kh='Kharox:BAABLAAECoEbAAIOAAcIqRHoVQCrAQAOAAcIqRHoVQCrAQAAAA==.Kházrak:BAABLAAECoEYAAIPAAgIRRtzEACIAgAPAAgIRRtzEACIAgAAAA==.',Ki='Killshot:BAAALAAECgcIEQAAAA==.Kiðlingur:BAABLAAECoEUAAMEAAgI5xttJQAeAgAEAAcIWRttJQAeAgAIAAcIzBWeLwDMAQAAAA==.',Ko='Kompakt:BAABLAAECoEVAAIbAAcIGhCmKgC1AQAbAAcIGhCmKgC1AQAAAA==.',Kr='Kraven:BAAALAAECgQIDAAAAA==.',Ku='Kuniku:BAABLAAECoEWAAIcAAgIWwo/TAB7AQAcAAgIWwo/TAB7AQAAAA==.',['Kâ']='Kâunokainen:BAAALAADCggIFwAAAA==.',['Kü']='Kücümen:BAABLAAECoEXAAINAAgIGwEqzwBQAAANAAgIGwEqzwBQAAAAAA==.',Le='Levìathan:BAAALAAECgYIBgAAAA==.',Li='Liekkiö:BAACLAAFFIEHAAIdAAMI4gk1DQDLAAAdAAMI4gk1DQDLAAAsAAQKgSoAAx0ACAhsGpEXAEkCAB0ACAgUGpEXAEkCAB4ABghrFA0JAKQBAAAA.Lightsaxe:BAAALAAECgEIAQABLAAECgUICgACAAAAAA==.Lika:BAAALAADCgcICgAAAA==.Lion:BAAALAADCggICwABLAAECggIHQAHAFghAA==.',Ll='Llensi:BAAALAAECgYICgAAAA==.Llowkey:BAAALAADCgcIDAABLAAECgIIAgACAAAAAA==.Llowwkey:BAAALAAECgYIEwAAAA==.',Lo='Loganmccrae:BAABLAAECoEcAAIGAAYIcBHbiQBdAQAGAAYIcBHbiQBdAQAAAA==.Lolow:BAAALAAECggIEAAAAA==.Looper:BAACLAAFFIELAAIGAAUIZhbbBwB9AQAGAAUIZhbbBwB9AQAsAAQKgTAAAgYACAgYJJQSAO8CAAYACAgYJJQSAO8CAAAA.Loreleyannet:BAAALAAECgcIEAAAAA==.Lowkeyloki:BAAALAAECgIIAgAAAA==.',Lt='Ltpd:BAAALAAECgQIBAAAAA==.',Lu='Luppin:BAAALAAECgYIDAABLAAFFAUICwAGAGYWAA==.Luthiean:BAAALAAECgYIBgAAAA==.',['Lí']='Lílith:BAAALAADCgcIBwAAAA==.',Ma='Magealot:BAAALAAECgUICgAAAA==.Mageu:BAAALAAECgYIDAAAAA==.Mairo:BAAALAADCgcIBwAAAA==.Majro:BAAALAADCggIFgAAAA==.Mamercus:BAAALAADCgcIEAAAAA==.Manscattan:BAAALAADCggICAABLAAFFAMIBgANAD8ZAA==.Mardell:BAAALAAECgUICQAAAA==.Marowit:BAABLAAECoEUAAILAAcIeAp5SABrAQALAAcIeAp5SABrAQAAAA==.Masic:BAABLAAECoEgAAINAAgIKhgJMABoAgANAAgIKhgJMABoAgAAAA==.Maximusver:BAAALAAECgMIBwAAAA==.Mazikeenn:BAAALAAECgYICQAAAA==.',Mc='Mcstabberz:BAAALAADCgcIBwAAAA==.',Md='Mdx:BAAALAAECgYIBgAAAA==.',Me='Mencius:BAAALAADCgcIDQAAAA==.Mephine:BAAALAAECgEIAQAAAA==.Merliina:BAAALAADCggIAQAAAA==.Methuselah:BAABLAAECoEWAAMZAAgI5RYrNQAxAgAZAAgI5RYrNQAxAgAfAAEIpAFcQAAlAAABLAAFFAMICAABAAIlAA==.Mezumiiru:BAABLAAECoEXAAMJAAcItxBuRwCzAQAJAAcItxBuRwCzAQABAAUIFQlgxwCtAAAAAA==.',Mi='Micks:BAAALAAECgYIBgAAAA==.Mictian:BAAALAADCggICQAAAA==.Minaskra:BAAALAAECgcIBwAAAA==.Minnakra:BAABLAAECoEaAAIJAAgIAxV2LwAfAgAJAAgIAxV2LwAfAgAAAA==.Mirili:BAAALAAECgMIAwAAAA==.Mirthy:BAAALAAECggIEAAAAA==.Missinnaeye:BAAALAAECggICAAAAA==.Mistrzu:BAAALAADCggIFQAAAA==.',Mj='Mjedër:BAABLAAECoEiAAIGAAcI1h0fOwAmAgAGAAcI1h0fOwAmAgAAAA==.',Mo='Moeko:BAAALAAECgYICwAAAA==.Moostang:BAAALAADCgcIBwAAAA==.Morbis:BAABLAAECoEjAAIMAAcIrhR3dwDMAQAMAAcIrhR3dwDMAQAAAA==.Morphero:BAAALAAECgcIDQAAAA==.Mortarian:BAAALAAECgUICQAAAA==.',Mu='Mudlock:BAAALAAECgIIAgAAAA==.Mudpal:BAAALAADCggIEAAAAA==.Munja:BAAALAAECgcIDAAAAA==.',My='Myoldlady:BAAALAADCgcIBwAAAA==.',['Mó']='Mónthé:BAABLAAECoEfAAIVAAgINR+xAwDPAgAVAAgINR+xAwDPAgAAAA==.',Na='Naiva:BAAALAAECgYIBgABLAAECggIDgACAAAAAA==.Narooma:BAAALAADCggICAABLAADCggIGgACAAAAAA==.Narun:BAAALAAECgYIEAAAAA==.Nasián:BAABLAAECoEgAAIBAAgIUhazNAAWAgABAAgIUhazNAAWAgAAAA==.Naveanna:BAAALAADCgMIAwABLAAECgYIEgACAAAAAA==.',Ne='Nemeziziz:BAAALAADCgYIBwAAAA==.Neph:BAAALAAECgYICgABLAAECgcIEQACAAAAAA==.Nepherias:BAAALAAECgIIAgABLAAECgcIEQACAAAAAA==.Nesso:BAAALAAECgQIBAABLAAECggIDwACAAAAAA==.',Ni='Nightshades:BAAALAADCggIDAAAAA==.Niguratum:BAAALAAECggICAAAAA==.Nipper:BAAALAADCgYIBgAAAA==.Nitre:BAEBLAAECoEhAAIgAAgIPRmJBABuAgAgAAgIPRmJBABuAgABLAAFFAEIAQACAAAAAA==.',Nu='Nuncio:BAABLAAECoEZAAMhAAcI8BJsDgCGAQAhAAYI/BRsDgCGAQALAAcIzwiQTgBQAQAAAA==.Nuradin:BAAALAADCgQICQAAAA==.',Ny='Nymoen:BAAALAAECggIAwAAAA==.Nyujin:BAABLAAECoEXAAIKAAgItQFengBNAAAKAAgItQFengBNAAAAAA==.',Oa='Oakleaf:BAABLAAECoEbAAIGAAcIKxcHXQDCAQAGAAcIKxcHXQDCAQAAAA==.',Og='Ogpog:BAAALAADCgcIFQAAAA==.',Om='Omm:BAAALAADCgcIBwAAAA==.',On='Onepunsh:BAABLAAECoEkAAIBAAcI7yCuHQB5AgABAAcI7yCuHQB5AgAAAA==.Oneshot:BAAALAADCggIEQAAAA==.Oneyedwilly:BAAALAADCgYIBAAAAA==.',Oo='Oomtrix:BAACLAAFFIENAAINAAQIMR/gDACSAQANAAQIMR/gDACSAQAsAAQKgS4AAg0ACAiVIgAPABcDAA0ACAiVIgAPABcDAAEsAAQKBAgMAAIAAAAA.',Op='Opala:BAAALAAECgYIEwABLAAECggIJwAGAGcWAA==.',Or='Orihan:BAAALAADCggIDQAAAA==.Oruhe:BAAALAADCgcIDQAAAA==.',Pa='Palasia:BAAALAADCgMIAwAAAA==.Palko:BAAALAADCggICQAAAA==.Pandarin:BAAALAADCgIIAgAAAA==.Papibear:BAAALAAECgYIEAAAAA==.Paulthealien:BAAALAAFFAIIAgAAAA==.Paxili:BAAALAADCggICwAAAA==.',Pb='Pbs:BAABLAAECoEbAAISAAcI8yB4DQB0AgASAAcI8yB4DQB0AgAAAA==.',Pe='Petrisor:BAAALAADCgUIBQABLAAECgQIBwACAAAAAA==.Petru:BAAALAADCgcIDQABLAAECgQIBwACAAAAAA==.',Ph='Phéoníx:BAAALAAECgcIEwAAAA==.',Pi='Picollovac:BAAALAADCgcIBwAAAA==.Pinguïn:BAAALAAECgYIDQAAAA==.Pintea:BAAALAADCggIDgABLAAECgQIBwACAAAAAA==.Pipsqueak:BAAALAAECgUIBQABLAAECgYIEgACAAAAAA==.Piroel:BAABLAAECoEmAAMHAAgIOCNzEAAiAwAHAAgIOCNzEAAiAwASAAYINh0zGgDoAQAAAA==.',Pl='Plan:BAABLAAECoEUAAMbAAgIrhYgGgAvAgAbAAgIuxQgGgAvAgAiAAQI2wwOMQC8AAAAAA==.Plantje:BAAALAADCggICAAAAA==.Plops:BAAALAADCggIDwAAAA==.',Po='Polymorph:BAABLAAECoEdAAINAAgIBxVoQgAdAgANAAgIBxVoQgAdAgAAAA==.Ponyfiddler:BAAALAAECgcIDgAAAA==.Popesith:BAABLAAECoEVAAMIAAcIqh0/GgBdAgAIAAcIqh0/GgBdAgAEAAEIJAaZuwAjAAAAAA==.Powerbttm:BAABLAAECoEfAAQcAAcILRq6JQAyAgAcAAcIuRm6JQAyAgALAAUI/ws9XgADAQAhAAMIWhuOGgDeAAAAAA==.',Pp='Ppanda:BAAALAAECgQIBwAAAA==.',Pr='Prada:BAABLAAECoEVAAMRAAgI1wc5SAAfAQARAAgIwgc5SAAfAQANAAgIbQF2wwB2AAAAAA==.Preatorion:BAAALAADCgcIBwAAAA==.Priestouchme:BAAALAADCgYIBgAAAA==.Priestzoef:BAAALAADCggICAABLAAECggIJgAGADYfAA==.',['Pá']='Pádfoot:BAAALAAECggIEwAAAA==.',Ra='Rabbidpikey:BAABLAAECoEWAAMIAAgINA4pOgCXAQAIAAgI4g0pOgCXAQAFAAYIJwTsLADWAAAAAA==.Raemal:BAABLAAECoEUAAIVAAYI3CRhBQCIAgAVAAYI3CRhBQCIAgAAAA==.Rageelf:BAACLAAFFIEIAAMLAAMIgA1bDgDcAAALAAMIgA1bDgDcAAAcAAMItAL9FgCxAAAsAAQKgS4ABAsACAiXH44OAOkCAAsACAiXH44OAOkCABwACAjdBz1PAG8BACEAAwg+DHciAI4AAAAA.Ravena:BAABLAAECoEcAAIBAAcIdwsEiwAlAQABAAcIdwsEiwAlAQAAAA==.',Re='Redspark:BAAALAAECggICAAAAA==.Renji:BAAALAAECggICAAAAA==.Revorius:BAAALAADCggIEAABLAAECgcIFgAEABcOAA==.',Ri='Riccochet:BAAALAADCgUIBAAAAA==.Ritsen:BAABLAAECoEjAAIGAAgIXSHpFwDPAgAGAAgIXSHpFwDPAgAAAA==.Rizzaa:BAAALAAECgQIBgABLAAECggIJgALAHAKAA==.',Rk='Rkshana:BAAALAADCggICAAAAA==.',Ro='Rokiva:BAAALAADCgMIAwAAAA==.Ronalf:BAAALAAECgEIAQAAAA==.Roseblade:BAABLAAECoEfAAMDAAcIjxg5HAD7AQADAAcIjxg5HAD7AQAHAAMIegc7BAGXAAAAAA==.Rotandroll:BAAALAAECgIIBAAAAA==.Rotath:BAAALAAECgUICAABLAAECgQIDAACAAAAAA==.Rothganon:BAAALAAECggICAAAAA==.',Ru='Rubmytotèm:BAABLAAECoEVAAIJAAYIPCLrIwBhAgAJAAYIPCLrIwBhAgAAAA==.Rudolph:BAAALAADCgUIBQAAAA==.',Sa='Sabe:BAAALAADCggIFAAAAA==.Sachrem:BAAALAAECgYIBgAAAA==.Saifu:BAACLAAFFIENAAIjAAQIdgsxBQAoAQAjAAQIdgsxBQAoAQAsAAQKgSgAAiMACAhJHnMIALwCACMACAhJHnMIALwCAAAA.Sammie:BAABLAAECoEXAAIBAAgIYgragAA8AQABAAgIYgragAA8AQAAAA==.Samson:BAAALAADCggIDQAAAA==.Sanjin:BAAALAADCggIKAAAAA==.Saron:BAACLAAFFIEIAAIBAAMIAiUwCABBAQABAAMIAiUwCABBAQAsAAQKgSYAAwEACAh8ItcHAA8DAAEACAh8ItcHAA8DAAkABAhdHXJqADgBAAAA.',Sc='Scattach:BAACLAAFFIEGAAINAAMIPxmtFAAMAQANAAMIPxmtFAAMAQAsAAQKgSkAAg0ACAg8JQ4FAFwDAA0ACAg8JQ4FAFwDAAAA.Schukon:BAAALAAECggICAAAAA==.Scroob:BAAALAADCggICAAAAA==.',Se='Seamanstains:BAAALAADCggIEQAAAA==.Seffron:BAAALAAECgIIAwAAAA==.Seffrone:BAAALAADCgEIAQAAAA==.Selafira:BAAALAADCgcIBwAAAA==.Selora:BAABLAAECoEjAAIQAAgI3SK3DQApAwAQAAgI3SK3DQApAwAAAA==.Seramoon:BAAALAAECgYICgAAAA==.Seyko:BAABLAAECoEbAAIIAAgIIiGGDADuAgAIAAgIIiGGDADuAgAAAA==.',Sf='Sfantu:BAAALAAECgEIAQABLAAECgQIBwACAAAAAA==.',Sh='Shadedlady:BAAALAADCgcICwAAAA==.Shadowmelder:BAABLAAECoEiAAIGAAcIwB6iNwA0AgAGAAcIwB6iNwA0AgAAAA==.Shadowstrike:BAAALAADCgIIAwAAAA==.Shahiri:BAAALAAECgUIBQABLAAFFAMIBgANAD8ZAA==.Shamanuellsn:BAAALAADCggICwAAAA==.Shamanzoef:BAABLAAECoEYAAIBAAgIggzJcgBeAQABAAgIggzJcgBeAQABLAAECggIJgAGADYfAA==.Sharashim:BAABLAAFFIEHAAIEAAMIFw+7DgDLAAAEAAMIFw+7DgDLAAAAAA==.Shazaulk:BAAALAADCgcIBwAAAA==.Shellaa:BAAALAADCggIFAAAAA==.Sheyne:BAAALAADCggICgAAAA==.Shiftimblind:BAAALAADCgcIBwABLAAECggIKwAEAGAiAA==.Shimme:BAAALAAECgIIAwAAAA==.Shinomiya:BAAALAADCggIFwAAAA==.Shivwa:BAAALAAECgMIAwAAAA==.',Si='Siirí:BAAALAAECggICgAAAA==.Silina:BAAALAADCgYIAwABLAADCggIIwACAAAAAA==.Simpsonheale:BAAALAAECgcIEwAAAA==.Sizzlekitten:BAAALAADCgEIAQAAAA==.',Sj='Sjenka:BAABLAAECoEfAAILAAcIyxrCIgA7AgALAAcIyxrCIgA7AgAAAA==.',Sk='Skargoth:BAAALAADCggIFgABLAAECgEIAQACAAAAAA==.Skeleton:BAABLAAECoEkAAITAAgIChZPEgDrAQATAAgIChZPEgDrAQAAAA==.',Sl='Slasherm:BAAALAAECgUICQAAAA==.Slaughterkil:BAAALAAECgYIBwAAAA==.Slaughterwel:BAABLAAECoEWAAIfAAcIORQICQAOAgAfAAcIORQICQAOAgAAAA==.Sleep:BAAALAADCgYIBgAAAA==.',Sn='Snapdruidx:BAAALAADCggICAAAAA==.',So='Sometingwong:BAAALAADCgcIBwAAAA==.Soulpandaa:BAAALAAECgYICwAAAA==.',Sp='Speckles:BAAALAAECgcIDAAAAA==.Speedtomten:BAAALAADCggICAABLAAFFAMICAALAIANAA==.Spellwright:BAAALAADCgYIBgAAAA==.Spideycat:BAAALAADCgMIAwAAAA==.Spink:BAAALAADCggIEwAAAA==.Spiritius:BAAALAAECgYICAABLAAFFAMIBwAdAOIJAA==.Spirtuel:BAAALAADCgYIAQAAAA==.',St='Staura:BAAALAADCggICAAAAA==.Steelfayth:BAAALAADCggICAABLAAECggIFwAXAAsdAA==.Steelzyy:BAAALAAECgEIAQAAAA==.Stormlord:BAAALAAECgQIBgAAAA==.Stormwytch:BAAALAAECgYIDgAAAA==.Stormypetrel:BAAALAADCgcIAwAAAA==.',Su='Sunnie:BAAALAAECgYIEgAAAA==.Sunrinlin:BAAALAAECgUICQAAAA==.Supay:BAAALAAECgIIAgAAAA==.Supimage:BAAALAAECgIIAgAAAA==.Suvitza:BAAALAADCgcIBwABLAAECgQIBwACAAAAAA==.',Sw='Swiftie:BAAALAADCgYIBgAAAA==.Swoleshan:BAAALAAECgIIAgABLAAECggIKQAMAAgkAA==.',Sy='Sylren:BAABLAAECoEfAAIHAAgIAA04kACTAQAHAAgIAA04kACTAQAAAA==.Symeris:BAAALAADCggICAAAAA==.Syndrexia:BAAALAADCggIEQAAAA==.',Ta='Tanade:BAAALAADCgEIAQAAAA==.Tankistaa:BAAALAAECgcICQAAAA==.Taro:BAAALAAECggICAAAAA==.',Tc='Tccb:BAABLAAECoEgAAMOAAgIDh3ZGwC2AgAOAAgIDh3ZGwC2AgAPAAYIixVFNwBeAQAAAA==.',Te='Tehbinka:BAAALAADCggICAAAAA==.Temerial:BAEALAAFFAIIAgABLAAFFAEIAQACAAAAAA==.Tenen:BAABLAAECoEiAAIGAAcImRjSUADiAQAGAAcImRjSUADiAQAAAA==.Tephraxis:BAABLAAECoEfAAIdAAcIrxAkKgCmAQAdAAcIrxAkKgCmAQAAAA==.Terrax:BAAALAAECgEIAQAAAA==.Terö:BAAALAAECgYIDgAAAA==.',Th='Thaddeus:BAABLAAECoEhAAIWAAgIrhphDACIAgAWAAgIrhphDACIAgAAAA==.Theshifter:BAABLAAECoErAAQEAAgIYCKlCQDxAgAEAAgIYCKlCQDxAgAFAAgI+xzyBwC2AgAIAAgIzh0mFQCOAgAAAA==.Thramlocks:BAAALAAECgcIDQAAAA==.Thunderleaf:BAACLAAFFIESAAIXAAUIdw9vBABqAQAXAAUIdw9vBABqAQAsAAQKgSYAAhcACAjlHvsIAKsCABcACAjlHvsIAKsCAAAA.',Ti='Ticklemytess:BAABLAAECoErAAIKAAgIFiWxAgBaAwAKAAgIFiWxAgBaAwAAAA==.Tileana:BAAALAAECgYIDAAAAA==.Tinylynne:BAAALAADCgcIAwAAAA==.',Tj='Tjaman:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.',To='Toombs:BAAALAADCgYIBgAAAA==.Torche:BAABLAAECoEcAAIIAAgIGBPsKwDhAQAIAAgIGBPsKwDhAQAAAA==.Tozar:BAAALAADCggICQAAAA==.',Tr='Tretta:BAAALAAECggICAAAAA==.Truestorm:BAAALAADCgcIGAABLAAECgEIAQACAAAAAA==.',Tu='Tudum:BAAALAAECgIIAwAAAA==.Turnatrick:BAAALAADCgIIAgAAAA==.Turnip:BAAALAAECgYIBgAAAA==.Tutator:BAABLAAECoEYAAIXAAgIOgEsNgB9AAAXAAgIOgEsNgB9AAAAAA==.Tutlek:BAAALAAECgEIAQAAAA==.',Tw='Twinklés:BAABLAAECoEZAAIXAAYIvhWfHQByAQAXAAYIvhWfHQByAQAAAA==.',Ty='Tyronath:BAAALAAECgYIAQAAAA==.',['Tô']='Tôza:BAAALAADCggICAAAAA==.',Ue='Ueksan:BAAALAADCgQIBAAAAA==.',Ul='Ulfgangur:BAAALAAECgMIBgAAAA==.Ulithorn:BAAALAADCgcIBwAAAA==.',Un='Un:BAAALAADCggICAABLAAECggIHQAHAFghAA==.Uniken:BAAALAADCgcIBwAAAA==.',Va='Vadér:BAAALAADCgUICAAAAA==.Valgodorras:BAAALAAECgIIAwAAAA==.Valkahn:BAABLAAECoEoAAIIAAgIkwznOgCTAQAIAAgIkwznOgCTAQAAAA==.Vantrex:BAAALAAECgMIBQAAAA==.Varealf:BAAALAAECgcIEQAAAA==.Vareesha:BAAALAAECgEIAQAAAA==.Vasur:BAAALAADCgQIBAAAAA==.',Ve='Venkel:BAAALAAECgcIEwAAAA==.Venthues:BAAALAAECgMIAwAAAA==.Venús:BAAALAAECggICgAAAA==.Verifonix:BAABLAAECoEWAAIBAAgIoQyceQBNAQABAAgIoQyceQBNAQAAAA==.',Vi='Vilebaard:BAABLAAECoEfAAIUAAcIYhXcFQD2AQAUAAcIYhXcFQD2AQAAAA==.Virane:BAABLAAECoEUAAIJAAgIDwhGUQCOAQAJAAgIDwhGUQCOAQAAAA==.Virmortalis:BAAALAAECgEIAQAAAA==.',Vo='Voiddeath:BAAALAADCgQIBAAAAA==.',Vu='Vukodlak:BAABLAAECoEaAAMbAAcIvBkbHwAEAgAbAAcIvBkbHwAEAgAiAAQIqQzbMAC9AAAAAA==.',['Vá']='Vánhelsing:BAAALAADCggIDAAAAA==.',['Vé']='Vérónní:BAAALAADCgIIAgAAAA==.',Wa='Warcox:BAAALAAFFAIIAgAAAA==.Warrzoef:BAAALAAECgUIBQABLAAECggIJgAGADYfAA==.',We='Wetshya:BAAALAADCggIDAAAAA==.',Wh='Whitelighter:BAAALAAECggIDgAAAA==.',Wi='Windtorn:BAABLAAECoEdAAIHAAcIMArZpwBoAQAHAAcIMArZpwBoAQAAAA==.',Wo='Woknroll:BAEALAAFFAEIAQAAAA==.Wonderbread:BAAALAAECgcIEwAAAA==.',['Wá']='Wárden:BAAALAADCggICAAAAA==.',Xi='Xiaomimi:BAABLAAECoEVAAIDAAcIOQ1lNQBVAQADAAcIOQ1lNQBVAQAAAA==.',Xu='Xulu:BAAALAAECgcIDgABLAAECggIKAAcAA4kAA==.',Xx='Xxkole:BAABLAAECoEoAAIQAAgIDSVECQBGAwAQAAgIDSVECQBGAwAAAA==.',Xy='Xytron:BAAALAAECgcIBwAAAA==.',Ya='Yalldor:BAAALAADCggIEQABLAAECgEIAQACAAAAAA==.Yalysea:BAAALAADCgEIAQAAAA==.',Ye='Yemanya:BAAALAADCgEIAQAAAA==.Yevaud:BAAALAAECgEIAQAAAA==.',Yl='Ylva:BAAALAADCggICAAAAA==.',Yo='Yodà:BAABLAAECoEfAAILAAcIHBOYNgDCAQALAAcIHBOYNgDCAQAAAA==.Yoshirogue:BAAALAADCggIEQAAAA==.',Yu='Yugo:BAAALAADCgQIBAAAAA==.Yungai:BAABLAAECoEcAAIBAAcINA68fgBBAQABAAcINA68fgBBAQAAAA==.',Za='Zandwitch:BAAALAADCgUIBQAAAA==.',Ze='Zecturne:BAABLAAECoEVAAIbAAgIwhZjFwBIAgAbAAgIwhZjFwBIAgAAAA==.Zeelord:BAABLAAECoEeAAIcAAgIDiQwBwAjAwAcAAgIDiQwBwAjAwAAAA==.Zenindraz:BAAALAAECgcIEgABLAAFFAMIBwAdAOIJAA==.Zenindreas:BAAALAAFFAIIAgABLAAFFAMIBwAdAOIJAA==.Zenintra:BAAALAAECgYIEAABLAAFFAMIBwAdAOIJAA==.Zeroy:BAABLAAECoEmAAIkAAgIdCVDAgBiAwAkAAgIdCVDAgBiAwAAAA==.Zetheros:BAAALAAECggIBAAAAA==.',Zi='Zireaél:BAAALAADCgcIBwAAAA==.',Zm='Zmij:BAAALAADCgMIAwABLAAFFAMICAABAAIlAA==.Zmíj:BAAALAAECgQIBAABLAAFFAMICAABAAIlAA==.Zmííj:BAABLAAECoEYAAIlAAgIFR0FBwCjAgAlAAgIFR0FBwCjAgABLAAFFAMICAABAAIlAA==.',Zo='Zoef:BAABLAAECoEmAAIGAAgINh+NHgCmAgAGAAgINh+NHgCmAgAAAA==.',Zr='Zroy:BAAALAAECgIIAgAAAA==.',Zu='Zukov:BAAALAADCggICAABLAAECggIDgACAAAAAA==.Zuluhead:BAAALAADCgcIAwAAAA==.',Zw='Zwerewolfz:BAAALAAECgIIAwAAAA==.',Zy='Zyrrith:BAAALAADCgMIAwAAAA==.',['Àr']='Àres:BAAALAADCggIFgAAAA==.',['Èm']='Èmrys:BAAALAAECgYIDAAAAA==.',['Õk']='Õk:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end