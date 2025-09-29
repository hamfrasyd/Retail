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
 local lookup = {'Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Retribution','Druid-Restoration','Warrior-Fury','DeathKnight-Blood','Unknown-Unknown','Monk-Brewmaster','Warrior-Protection','Warrior-Arms','DeathKnight-Unholy','Shaman-Restoration','Shaman-Elemental','Mage-Arcane','Paladin-Holy','DemonHunter-Vengeance','DeathKnight-Frost','Druid-Balance','Druid-Guardian','Monk-Windwalker','Hunter-BeastMastery',}; local provider = {region='EU',realm='Antonidas',name='EU',type='subscribers',zone=44,date='2025-09-25',data={Ak='Akumizuki:BAEBLAAECoEfAAMBAAgIMReoEwDnAQg5DAAABQA/ADsMAAAFAFAAOgwAAAUAQgA8DAAABQA4ADIMAAAEADQAPQwAAAQAQQA+DAAAAgA1AD8MAAABACUAAQAHCPAWqBMA5wEHOQwAAAQAPwA7DAAABABQADoMAAAEADEAPAwAAAMALgAyDAAABAA0AD0MAAAEAEEAPgwAAAIANQACAAUIDxTCQAA7AQU5DAAAAQA4ADsMAAABACkAOgwAAAEAQgA8DAAAAgA4AD8MAAABACUAAAA=.',Br='Brewidwen:BAEALAAECgcIBwABLAAFFAcIIAADADwcAA==.',Bu='Bubblidwen:BAECLAAFFIEgAAIDAAcIPBwvAACaAgc5DAAABgBdADsMAAAFAFkAOgwAAAYAXgA8DAAABQAiADIMAAAEADsAPQwAAAQAVAA+DAAAAgAxAAMABwg8HC8AAJoCBzkMAAAGAF0AOwwAAAUAWQA6DAAABgBeADwMAAAFACIAMgwAAAQAOwA9DAAABABUAD4MAAACADEALAAECoEbAAIDAAgIJSW+BAAjAwADAAgIJSW+BAAjAwAAAA==.',Ci='Cinderace:BAEBLAAECoEZAAIEAAcIZht3KAAbAgc5DAAABQBHADsMAAAEAFIAOgwAAAUAQAA8DAAABABEADIMAAADAD4APQwAAAMASQA+DAAAAQBDAAQABwhmG3coABsCBzkMAAAFAEcAOwwAAAQAUgA6DAAABQBAADwMAAAEAEQAMgwAAAMAPgA9DAAAAwBJAD4MAAABAEMAASwABRQGCBkABQBZFgA=.',Cl='Clubberpala:BAEALAAECgcIEQAAAA==.',Cy='Cylíria:BAEALAAECggIBgAAAA==.',Da='Daddymoo:BAEBLAAECoEiAAIGAAgIyBtdLwCTAgg5DAAABgBWADsMAAAGAE0AOgwAAAUAUwA8DAAABABEADIMAAAEAFUAPQwAAAQANwA+DAAAAwA7AD8MAAACADQABgAICMgbXS8AkwIIOQwAAAYAVgA7DAAABgBNADoMAAAFAFMAPAwAAAQARAAyDAAABABVAD0MAAAEADcAPgwAAAMAOwA/DAAAAgA0AAAA.',De='Delarià:BAEALAAECgUIDgAAAA==.',El='Elluneve:BAEALAAECgcICwABLAAFFAUIDgAHABERAQ==.',En='Enby:BAEBLAAECoEqAAIIAAgIwiQ6CQBEAwg5DAAACABiADsMAAAGAGAAOgwAAAUAYQA8DAAABwBhADIMAAAHAGEAPQwAAAQAUwA+DAAAAgBbAD8MAAADAFkACAAICMIkOgkARAMIOQwAAAgAYgA7DAAABgBgADoMAAAFAGEAPAwAAAcAYQAyDAAABwBhAD0MAAAEAFMAPgwAAAIAWwA/DAAAAwBZAAAA.Enekoro:BAECLAAFFIEZAAIFAAYIWRbNCQCoAQY5DAAABgBgADsMAAAFADcAOgwAAAYAXAA8DAAABAAiADIMAAABAA8APQwAAAMAMAAFAAYIWRbNCQCoAQY5DAAABgBgADsMAAAFADcAOgwAAAYAXAA8DAAABAAiADIMAAABAA8APQwAAAMAMAAsAAQKgTgAAgUACAhnJPQGAFoDAAUACAhnJPQGAFoDAAAA.',Fl='Floppydekay:BAEBLAAECoEeAAIJAAgIAyNjBAAbAwg5DAAABQBhADsMAAAFAGEAOgwAAAQAYgA8DAAAAwBbADIMAAAEAF0APQwAAAUAYAA+DAAAAgBJAD8MAAACAEQACQAICAMjYwQAGwMIOQwAAAUAYQA7DAAABQBhADoMAAAEAGIAPAwAAAMAWwAyDAAABABdAD0MAAAFAGAAPgwAAAIASQA/DAAAAgBEAAEsAAQKBggGAAoAAAAA.Floppymonk:BAECLAAFFIEWAAILAAYIRRz+AQAcAgY5DAAABQBYADsMAAAEAE8AOgwAAAUAVgA8DAAABAAvADIMAAABAEcAPQwAAAMAOwALAAYIRRz+AQAcAgY5DAAABQBYADsMAAAEAE8AOgwAAAUAVgA8DAAABAAvADIMAAABAEcAPQwAAAMAOwAsAAQKgSUAAgsACAgRJKMEABgDAAsACAgRJKMEABgDAAEsAAQKBggGAAoAAAAA.Floppypal:BAEALAAECgYIBgAAAA==.Floppywarri:BAEBLAAECoEbAAIMAAgI/RnQEgB4Agg5DAAABABMADsMAAAEAFoAOgwAAAQAVQA8DAAABABRADIMAAAEAEwAPQwAAAUASQA+DAAAAQAMAD8MAAABACQADAAICP0Z0BIAeAIIOQwAAAQATAA7DAAABABaADoMAAAEAFUAPAwAAAQAUQAyDAAABABMAD0MAAAFAEkAPgwAAAEADAA/DAAAAQAkAAEsAAQKBggGAAoAAAAA.Fluffers:BAEALAAECggICAABLAAECggICAAKAAAAAA==.',Gr='Gripidwen:BAECLAAFFIEJAAIJAAYIRhhwAQAdAgY5DAAAAgBeADsMAAACAD0AOgwAAAIAVwA8DAAAAQAyADIMAAABADoAPQwAAAEAFAAJAAYIRhhwAQAdAgY5DAAAAgBeADsMAAACAD0AOgwAAAIAVwA8DAAAAQAyADIMAAABADoAPQwAAAEAFAAsAAQKgRkAAgkACAi1IywEACADAAkACAi1IywEACADAAEsAAUUBwggAAMAPBwA.',Ha='Haumichdh:BAEALAAECggICQABLAAECggIMwAMANkiAA==.Haumichwarri:BAEBLAAECoEzAAMMAAgI2SLiBQAlAwg5DAAACQBcADsMAAAIAFgAOgwAAAgAXAA8DAAABwBbADIMAAAHAFYAPQwAAAYAWgA+DAAABABUAD8MAAACAFUADAAICLQi4gUAJQMIOQwAAAcAXAA7DAAABgBVADoMAAAGAFwAPAwAAAYAWwAyDAAABwBWAD0MAAAFAFoAPgwAAAQAVAA/DAAAAgBVAA0ABQhHFsgZAC8BBTkMAAACAFAAOwwAAAIAWAA6DAAAAgBJADwMAAABACkAPQwAAAEAAQAAAA==.Haumimonk:BAEALAAECggICQABLAAECggIMwAMANkiAA==.Haumishaman:BAEALAADCggIEAABLAAECggIMwAMANkiAA==.',He='Heralia:BAEBLAAECoEiAAMOAAcICiHPCwCEAgc5DAAABwBeADsMAAAHAFMAOgwAAAYAYAA8DAAABABMADIMAAAEAEIAPQwAAAQAWwA+DAAAAgBTAA4ABwgKIc8LAIQCBzkMAAAHAF4AOwwAAAcAUwA6DAAABgBgADwMAAAEAEwAMgwAAAMAQgA9DAAAAwBbAD4MAAACAFMACQACCFEPTzgAYwACMgwAAAEAMQA9DAAAAQAcAAAA.Herâlia:BAEALAAECgMIBAABLAAECgcIIgAOAAohAA==.',Ho='Hottymoo:BAEALAAECgIIAgABLAAECggIIgAGAMgbAA==.',Iy='Iyásu:BAECLAAFFIEOAAIPAAMIPhFdHAC1AAM5DAAABgAxADsMAAADACAAOgwAAAUAMgAPAAMIPhFdHAC1AAM5DAAABgAxADsMAAADACAAOgwAAAUAMgAsAAQKgTgAAw8ACAjfG7ovADQCAA8ACAjfG7ovADQCABAACAj4FQ0wACkCAAAA.',Jf='Jfawk:BAECLAAFFIEOAAIRAAYIeBVuCADsAQY5DAAAAwAwADsMAAADAFQAOgwAAAMASwA8DAAAAgAqADIMAAABADYAPQwAAAIAFwARAAYIeBVuCADsAQY5DAAAAwAwADsMAAADAFQAOgwAAAMASwA8DAAAAgAqADIMAAABADYAPQwAAAIAFwAsAAQKgTEAAhEACAiaJokCAHYDABEACAiaJokCAHYDAAAA.',Jo='Jowl:BAECLAAFFIEVAAISAAcIxByPAACMAgc5DAAAAwA6ADsMAAAEAFAAOgwAAAQAWQA8DAAABABfADIMAAACACIAPQwAAAMAUwA+DAAAAQBJABIABwjEHI8AAIwCBzkMAAADADoAOwwAAAQAUAA6DAAABABZADwMAAAEAF8AMgwAAAIAIgA9DAAAAwBTAD4MAAABAEkALAAECoEoAAMSAAgImyW4AABmAwASAAgImyW4AABmAwAGAAUILBf0tQBgAQAAAA==.',Kr='Kranoi:BAEALAADCggICAAAAA==.Kranth:BAEALAAECgYIBgABLAAFFAMICwAGAKUlAA==.',La='Larolan:BAEALAAFFAIIBAABLAAFFAIIBgAGAF8XAA==.Layondeez:BAECLAAFFIELAAIGAAMIpSXGCgA0AQM5DAAABABgADsMAAADAF8AOgwAAAQAYAAGAAMIpSXGCgA0AQM5DAAABABgADsMAAADAF8AOgwAAAQAYAAsAAQKgUsAAgYACAi9JpMAAJsDAAYACAi9JpMAAJsDAAAA.',Le='Leeting:BAEBLAAECoEVAAITAAcI7h/5CgCKAgc5DAAABQBUADsMAAAEAFoAOgwAAAMAUQA8DAAAAwBMADIMAAADAEwAPQwAAAIAVgA+DAAAAQBLABMABwjuH/kKAIoCBzkMAAAFAFQAOwwAAAQAWgA6DAAAAwBRADwMAAADAEwAMgwAAAMATAA9DAAAAgBWAD4MAAABAEsAAAA=.',Lo='Lockyfloppy:BAEALAAECggIEwABLAAECgYIBgAKAAAAAA==.',Lu='Luciddk:BAECLAAFFIEIAAIUAAUIHxWfCgCoAQU5DAAAAgBNADsMAAACAGIAOgwAAAIASgA8DAAAAQAKAD0MAAABAAkAFAAFCB8VnwoAqAEFOQwAAAIATQA7DAAAAgBiADoMAAACAEoAPAwAAAEACgA9DAAAAQAJACwABAqBFQACFAAICC4kKQYAXAMAFAAICC4kKQYAXAMAASwABRQDCAsABgClJQA=.Lunore:BAEBLAAECoEbAAMVAAcI0yJZEgC4Agc5DAAAAwBeADsMAAAFAF0AOgwAAAMAYAA8DAAABQBXADIMAAAEAEoAPQwAAAUAWQA+DAAAAgBYABUABwjTIlkSALgCBzkMAAACAF4AOwwAAAUAXQA6DAAAAwBgADwMAAAFAFcAMgwAAAQASgA9DAAABQBZAD4MAAABAFgAFgACCKMJcioAUQACOQwAAAEAFgA+DAAAAQAaAAAA.',Mi='Mirady:BAECLAAFFIEOAAIFAAQI2SC9CgCOAQQ5DAAABgBhADsMAAAEAFIAOgwAAAMAWAA8DAAAAQBDAAUABAjZIL0KAI4BBDkMAAAGAGEAOwwAAAQAUgA6DAAAAwBYADwMAAABAEMALAAECoEnAAIFAAgIOCXrCQBGAwAFAAgIOCXrCQBGAwAAAA==.',Na='Namaá:BAEALAADCgYIBgABLAAECgcIHgADACAgAA==.Nasenbohrer:BAEBLAAECoEdAAMLAAgIyh1oCgCWAgg5DAAABQBhADsMAAAEAFYAOgwAAAQAWAA8DAAABABPADIMAAAFAE4APQwAAAMAWwA+DAAAAwBUAD8MAAABAAIACwAICModaAoAlgIIOQwAAAUAYQA7DAAABABWADoMAAAEAFgAPAwAAAQATwAyDAAABABOAD0MAAADAFsAPgwAAAMAVAA/DAAAAQACABcAAQjhDRRbADQAATIMAAABACMAASwABAoICBgADACQJAA=.',Sc='Schockolade:BAEALAAECgIIAgABLAAECggIIgAGAMgbAA==.',Sh='Shatricê:BAEBLAAECoEnAAIRAAgIIxoLPgA3Agg5DAAABgBUADsMAAAGAE0AOgwAAAYAUQA8DAAABQA7ADIMAAAGAD8APQwAAAYASQA+DAAAAwBCAD8MAAABAB0AEQAICCMaCz4ANwIIOQwAAAYAVAA7DAAABgBNADoMAAAGAFEAPAwAAAUAOwAyDAAABgA/AD0MAAAGAEkAPgwAAAMAQgA/DAAAAQAdAAAA.Shinba:BAEBLAAECoEYAAIMAAgIkCRzAwBOAwg5DAAAAwBgADsMAAADAF8AOgwAAAMAYQA8DAAAAwBbADIMAAAEAF4APQwAAAMAYAA+DAAAAwBhAD8MAAACAFAADAAICJAkcwMATgMIOQwAAAMAYAA7DAAAAwBfADoMAAADAGEAPAwAAAMAWwAyDAAABABeAD0MAAADAGAAPgwAAAMAYQA/DAAAAgBQAAAA.',Si='Sitaliss:BAEALAAECggIEAABLAAFFAIIBgAGAF8XAA==.',Sl='Slâanesh:BAEALAAECgcIBwABLAAECgYIBwAKAAAAAA==.',Sp='Spiritdur:BAEALAAECgQIBAABLAAFFAcIEAAPACcJAA==.',St='Stîcy:BAEBLAAECoElAAIYAAcI4iXTEgD3Agc5DAAABgBhADsMAAAGAGAAOgwAAAYAYgA8DAAABQBjADIMAAAFAF8APQwAAAUAXQA+DAAABABhABgABwjiJdMSAPcCBzkMAAAGAGEAOwwAAAYAYAA6DAAABgBiADwMAAAFAGMAMgwAAAUAXwA9DAAABQBdAD4MAAAEAGEAAAA=.',['Sô']='Sôlar:BAEALAAECgYIBwAAAA==.',Te='Tealon:BAEALAADCggICAABLAAFFAIIBgAGAF8XAA==.',Tr='Trauergrimm:BAEBLAAECoEgAAIDAAcIhRI1KwBzAQc5DAAABgA/ADsMAAAGADsAOgwAAAUANQA8DAAABQAqADIMAAAEABYAPQwAAAQALwA+DAAAAgAqAAMABwiFEjUrAHMBBzkMAAAGAD8AOwwAAAYAOwA6DAAABQA1ADwMAAAFACoAMgwAAAQAFgA9DAAABAAvAD4MAAACACoAAAA=.Trivigos:BAECLAAFFIEGAAMGAAIIXxcLKQClAAI5DAAABABVADoMAAACACIABgACCF8XCykApQACOQwAAAMAVQA6DAAAAQAiAAMAAggxBYQVAGIAAjkMAAABAAwAOgwAAAEADgAsAAQKgR8AAgYACAjbJU4JAFIDAAYACAjbJU4JAFIDAAAA.',Ve='Vegigo:BAEALAADCgcIBwABLAAECggIBgAKAAAAAA==.',['Vê']='Vêno:BAEALAAECgYIBgAAAA==.',Wa='Waidur:BAECLAAFFIEQAAIPAAcIJwl+AwDkAQc5DAAABAAXADsMAAACAAIAOgwAAAQATQA8DAAAAQANADIMAAACAAoAPQwAAAIAFQA+DAAAAQAPAA8ABwgnCX4DAOQBBzkMAAAEABcAOwwAAAIAAgA6DAAABABNADwMAAABAA0AMgwAAAIACgA9DAAAAgAVAD4MAAABAA8ALAAECoE6AAMPAAgI7BvQIAB0AgAPAAgI7BvQIAB0AgAQAAcIHxfdOQD7AQAAAA==.',Wi='Widori:BAEALAAECggICAAAAA==.',Yu='Yursoir:BAEALAADCggIEAAAAA==.',['Yé']='Yélp:BAEALAAECgYIEwABLAAFFAcIFQASAMQcAA==.',['Âr']='Ârisha:BAECLAAFFIEOAAIPAAQItgYsEADoAAQ5DAAABQARADsMAAADAA4AOgwAAAUAIAA9DAAAAQAEAA8ABAi2BiwQAOgABDkMAAAFABEAOwwAAAMADgA6DAAABQAgAD0MAAABAAQALAAECoEhAAIPAAgI8xfIPAAGAgAPAAgI8xfIPAAGAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end