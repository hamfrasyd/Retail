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
 local lookup = {'Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Demonology','Monk-Mistweaver','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Priest-Shadow','DeathKnight-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Restoration','Warlock-Destruction','DeathKnight-Unholy','Warrior-Fury','Warlock-Affliction','Mage-Arcane','Mage-Frost','Warrior-Protection','Shaman-Elemental','Rogue-Outlaw','Mage-Fire',}; local provider = {region='EU',realm='Kazzak',name='EU',type='subscribers',zone=44,date='2025-09-06',data={Ac='Achillguy:BAEALAAFFAIIAgABLAAFFAYIEwABAOYlAA==.',Al='Alyberry:BAECLAAFFIEIAAMCAAMIHSADAgBAAQM5DAAAAwBZADsMAAACADoAOgwAAAMAYgACAAMIHSADAgBAAQM5DAAAAwBZADsMAAACADoAOgwAAAIAYgADAAEI2R+SBwBgAAE6DAAAAQBRACwABAqBIAADAgAICPskBgUACAMAAgAICOwhBgUACAMAAwAGCAwkNAUAeQIAAAA=.',An='Anshè:BAEALAAECgMICAAAAA==.',Ap='Apalamaybe:BAEALAAECgYICgABLAAECgcIEQAEAAAAAA==.',As='Asherbear:BAEALAAECgQIBAAAAA==.Asherwarbear:BAEALAADCggICAABLAAECgQIBAAEAAAAAA==.',Az='Azortharion:BAEBLAAFFIETAAMBAAYI5iURAACgAgY5DAAABABjADsMAAADAGMAOgwAAAQAYwA8DAAAAwBfADIMAAACAF8APQwAAAMAXAABAAYIsyURAACgAgY5DAAABABjADsMAAADAGMAOgwAAAQAYwA8DAAAAQBcADIMAAACAF8APQwAAAMAXAAFAAEIeSXWEQBsAAE8DAAAAgBfAAAA.Azreth:BAEALAAFFAIIAgABLAAFFAYIEwAGAGMhAA==.',Ba='Barakäbbel:BAEALAADCggICAABLAAECggIHQAHACYjAA==.Barnytrix:BAEALAADCggIFAABLAAECggIHgAIACoaAA==.',Be='Benshammy:BAEALAAECggICAABLAAFFAUIDgAJABAXAA==.Benspala:BAEALAADCggICAABLAAFFAUIDgAJABAXAA==.Benspriest:BAEALAAECggICAABLAAFFAUIDgAJABAXAA==.Bensvoker:BAECLAAFFIEOAAQJAAUIEBeZAQBZAQU5DAAAAQAhADsMAAAEAFoAOgwAAAQAQAAyDAAAAgAiAD0MAAADAEcACQAECP0TmQEAWQEEOQwAAAEAIQA6DAAABABAADIMAAACACIAPQwAAAIARwAKAAIIgRxBAQDMAAI7DAAAAwBfAD0MAAABADIACwABCE4ApREAIgABOwwAAAEAAAAsAAQKgRgABAoACAgDJiQAAHwDAAoACAgDJiQAAHwDAAsABwhFF1ccALwBAAkAAQh8ELkiAEIAAAAA.',Bl='Blaez:BAECLAAFFIETAAIGAAYIYyEWAACDAgY5DAAABABeADsMAAADAGMAOgwAAAQAYAA8DAAAAwBGADIMAAACAEMAPQwAAAMAVAAGAAYIYyEWAACDAgY5DAAABABeADsMAAADAGMAOgwAAAQAYAA8DAAAAwBGADIMAAACAEMAPQwAAAMAVAAsAAQKgRUAAgYACAh7JVQBAFYDAAYACAh7JVQBAFYDAAAA.Blebbin:BAECLAAFFIERAAIMAAYIQxtwAAAeAgY5DAAAAwAyADsMAAADAEUAOgwAAAIAVgA8DAAAAwA9ADIMAAADAEsAPQwAAAMATAAMAAYIQxtwAAAeAgY5DAAAAwAyADsMAAADAEUAOgwAAAIAVgA8DAAAAwA9ADIMAAADAEsAPQwAAAMATAAsAAQKgRkAAgwACAhAHkYFAOcCAAwACAhAHkYFAOcCAAAA.',Ca='Caleanadhs:BAEALAAECgIIAgABLAAECggIBgAEAAAAAA==.',Ch='Chamoli:BAEALAAECggIEwABLAAFFAYIDwAJAJQcAA==.Chaosleana:BAEALAAECggIBgAAAA==.',Cy='Cyanray:BAEALAAECgcICwAAAA==.',De='Deamed:BAEALAAFFAIIAgABLAAFFAYIEQAEAAAAAQ==.Deameh:BAEALAAFFAIIBAABLAAFFAYIEQAEAAAAAQ==.Deamm:BAEALAAFFAYIEQAAAQ==.Deloop:BAEALAAECggIEAABLAAFFAYIEwANALkgAA==.',Ee='Eelize:BAEALAADCgcIBwAAAA==.',El='Ellasham:BAEALAAECgYICQABLAAECggIHgAIACoaAA==.Ellatrikz:BAEBLAAECoEeAAIIAAgIKhqxCABqAgg5DAAABABEADsMAAAEAEwAOgwAAAQATgA8DAAABAA/ADIMAAAEAFAAPQwAAAQARgA+DAAAAwA9AD8MAAADACMACAAICCoasQgAagIIOQwAAAQARAA7DAAABABMADoMAAAEAE4APAwAAAQAPwAyDAAABABQAD0MAAAEAEYAPgwAAAMAPQA/DAAAAwAjAAAA.Ellatrix:BAEALAAECgYICgABLAAECggIHgAIACoaAA==.Ellatrixx:BAEALAAECgIIAgABLAAECggIHgAIACoaAA==.Elragar:BAECLAAFFIELAAIOAAQI1SOsAQC0AQQ5DAAABABgADoMAAADAGEAPAwAAAMAXwA9DAAAAQBOAA4ABAjVI6wBALQBBDkMAAAEAGAAOgwAAAMAYQA8DAAAAwBfAD0MAAABAE4ALAAECoEbAAIOAAgI9yXtAgBcAwAOAAgI9yXtAgBcAwAAAA==.Elrowl:BAEALAAECgUICQABLAAFFAQICwAOANUjAA==.',En='Enslaving:BAEALAADCgQIBAABLAADCgcIBwAEAAAAAA==.',Ev='Everdello:BAEBLAAECoEkAAMPAAgIYhukCABGAgg5DAAABgBSADsMAAAFAFkAOgwAAAUATQA8DAAABQBRADIMAAAGAFQAPQwAAAYAUwA+DAAAAgA+AD8MAAABAAEADwAHCD0fpAgARgIHOQwAAAYAUgA7DAAABQBZADoMAAAFAE0APAwAAAUAUQAyDAAABgBUAD0MAAAGAFMAPgwAAAEAPgAQAAIIqQADvAASAAI+DAAAAQACAD8MAAABAAEAAAA=.',Fe='Felmonarch:BAEALAADCgUIBQAAAA==.',Fl='Fluffyskawn:BAEALAAFFAMIBQABLAAFFAYIEQAEAAAAAQ==.Flxzd:BAEALAAECgMIBQABLAAECggICAAEAAAAAA==.Flxzdh:BAEALAAECggICAAAAA==.',Fr='Fratren:BAEALAAECgEIAQABLAAECgcIFwARADwYAA==.Freakbust:BAEALAAECgQIBAABLAAFFAYIAQAEAAAAAA==.Freakchurch:BAEALAAECgMIAwABLAAFFAYIAQAEAAAAAA==.Freakscythe:BAEALAAFFAIIBAABLAAFFAYIAQAEAAAAAA==.Freaksh:BAEALAAFFAIIAgABLAAFFAYIAQAEAAAAAA==.Freakxz:BAEALAAFFAYIAQAAAA==.',Gu='Guldone:BAEBLAAECoEdAAMHAAgIJiPQAQAkAwg5DAAABQBjADsMAAAEAGAAOgwAAAMAXQA8DAAABABPADIMAAAEAFkAPQwAAAQAXAA+DAAAAwBdAD8MAAACAEwABwAICCYj0AEAJAMIOQwAAAQAYwA7DAAABABgADoMAAADAF0APAwAAAQATwAyDAAAAgBZAD0MAAADAFwAPgwAAAMAXQA/DAAAAQBMABIABAgEGR5VABsBBDkMAAABAEkAMgwAAAIAQwA9DAAAAQBFAD8MAAABAC0AAAA=.',Ho='Hotasfk:BAEALAAECggIEgABLAAECggIEAAEAAAAAA==.',Hy='Hydrögèn:BAEALAAECgMIBQAAAA==.',Iv='Ivab:BAEALAAECggIAQAAAA==.',Je='Jessìcasky:BAEALAADCgEIAQAAAA==.',Ka='Kantaren:BAEBLAAECoEeAAIIAAgIGyX/AABRAwg5DAAABQBjADsMAAAEAGMAOgwAAAQAYgA8DAAAAwBiADIMAAAEAGAAPQwAAAQAXwA+DAAAAgBKAD8MAAAEAGIACAAICBsl/wAAUQMIOQwAAAUAYwA7DAAABABjADoMAAAEAGIAPAwAAAMAYgAyDAAABABgAD0MAAAEAF8APgwAAAIASgA/DAAABABiAAAA.',Kj='Kjordbigmac:BAEALAAECgcICgABLAAECgcIDgAEAAAAAA==.Kjordkorthia:BAEALAAECgMIAwABLAAECgcIDgAEAAAAAA==.Kjordstealth:BAEALAADCgcIBwABLAAECgcIDgAEAAAAAA==.Kjordwar:BAEALAADCggIDwABLAAECgcIDgAEAAAAAA==.Kjordwings:BAEALAAECgcIDgAAAA==.',La='Laffedh:BAEALAADCggIEAABLAAFFAYIEAAOAFQiAA==.Laffedk:BAECLAAFFIEQAAMOAAYIVCIkAgCMAQY5DAAABABcADsMAAACAFgAOgwAAAQAXgA8DAAAAwBhADIMAAACAF8APQwAAAEAOwAOAAQIkRwkAgCMAQQ5DAAAAQAFADoMAAAEAF4APAwAAAMAYQAyDAAAAgBfABMAAwhWH+MAAD0BAzkMAAADAFwAOwwAAAIAWAA9DAAAAQA7ACwABAqBGgADDgAICIkmGBgAngIADgAHCKcjGBgAngIAEwADCJ0mTh4AWAEAAAA=.Lafferogue:BAECLAAFFIEGAAMDAAMIoh4/AQAwAQM5DAAAAgAwADsMAAACAF8AOgwAAAIAWgADAAMIoh4/AQAwAQM5DAAAAQAwADsMAAABAF8AOgwAAAIAWgACAAIIiw1MCQCxAAI5DAAAAQAUADsMAAABADAALAAECoEWAAMDAAgIbhxrBQByAgADAAgIbhxrBQByAgACAAIIYBzyQgCeAAABLAAFFAYIEAAOAFQiAA==.',Le='Lepyorc:BAECLAAFFIEIAAIUAAMIXxlmBAAjAQM5DAAAAwBVADsMAAACABEAOgwAAAMAWwAUAAMIXxlmBAAjAQM5DAAAAwBVADsMAAACABEAOgwAAAMAWwAsAAQKgRwAAhQACAifH1MLAO4CABQACAifH1MLAO4CAAAA.',Lu='Lunarl:BAEALAADCgQIBAABLAADCgcIBwAEAAAAAA==.',Ly='Lynarae:BAEALAAECgcIEAABLAAECggIHgAIACoaAA==.',Mi='Minikantom:BAECLAAFFIEQAAIMAAYIOx9DAAA6AgY5DAAAAgBTADsMAAACAFUAOgwAAAQAUwA8DAAAAwBhADIMAAACAFEAPQwAAAMALgAMAAYIOx9DAAA6AgY5DAAAAgBTADsMAAACAFUAOgwAAAQAUwA8DAAAAwBhADIMAAACAFEAPQwAAAMALgAsAAQKgR8AAgwACAiiJkoAAH8DAAwACAiiJkoAAH8DAAAA.Minikantwo:BAEALAAFFAIIAgABLAAFFAYIEAAMADsfAA==.',Mo='Monkadot:BAECLAAFFIEPAAMSAAUIgRPCAgDLAQU5DAAABABeADsMAAADAE8AOgwAAAQAPAA8DAAAAgAGAD0MAAACAAgAEgAFCFgRwgIAywEFOQwAAAMAXgA7DAAAAwBPADoMAAACACAAPAwAAAIABgA9DAAAAgAIAAcAAggxHTUFALQAAjkMAAABAFkAOgwAAAIAPAAsAAQKgRYABBIACAjMIkcNANcCABIACAgyH0cNANcCAAcABghZIRAUAPEBABUAAQgfJZknAGYAAAAA.Monkasham:BAEALAAFFAIIAgABLAAFFAUIDwASAIETAA==.Mosskok:BAECLAAFFIEPAAMSAAYIGSNxAAB/AgY5DAAAAwBhADsMAAADAFoAOgwAAAMAVgA8DAAAAgBgADIMAAACAF0APQwAAAIASgASAAYI9iJxAAB/AgY5DAAAAgBhADsMAAADAFoAOgwAAAIAVAA8DAAAAgBgADIMAAACAF0APQwAAAIASgAHAAIIZBVABQCzAAI5DAAAAQAXADoMAAABAFYALAAECoEeAAQSAAgIYibnAQBsAwASAAgIYibnAQBsAwAHAAQIIh/CLwBBAQAVAAEIsyV0JwBnAAAAAA==.Mossochism:BAEALAAECgYIDAABLAAFFAYIDwASABkjAA==.',Ni='Nicksimp:BAEBLAAECoEWAAMWAAcIhAjbXgA/AQc5DAAABAAqADsMAAAEAB4AOgwAAAQADwA8DAAAAwAMADIMAAADABcAPQwAAAMAGwA+DAAAAQAAABYABgjvCdteAD8BBjkMAAACACoAOwwAAAIAHgA6DAAAAgAPADwMAAACAAwAMgwAAAIAFwA9DAAAAgAbABcABwgOAAAAAAAABzkMAAACAAAAOwwAAAIAAAA6DAAAAgAAADwMAAABAAAAMgwAAAEAAAA9DAAAAQABAD4MAAABAAAAASwABAoICAgABAAAAAA=.Nidoroar:BAECLAAFFIEPAAIYAAUIMxkAAQDIAQU5DAAABABCADsMAAADAEQAOgwAAAQAWgA8DAAAAgA9AD0MAAACACQAGAAFCDMZAAEAyAEFOQwAAAQAQgA7DAAAAwBEADoMAAAEAFoAPAwAAAIAPQA9DAAAAgAkACwABAqBGgACGAAICC8g5QUA1gIAGAAICC8g5QUA1gIAAAA=.Ninefive:BAEBLAAFFIEIAAIZAAMIBySHAwA+AQM5DAAAAwBhADsMAAACAFkAOgwAAAMAWQAZAAMIBySHAwA+AQM5DAAAAwBhADsMAAACAFkAOgwAAAMAWQAAAA==.Ninefivex:BAEALAAFFAIIAgABLAAFFAMICAAZAAckAA==.',No='Noloop:BAECLAAFFIETAAINAAYIuSBYAAB/AgY5DAAABABgADsMAAAEAGMAOgwAAAMAWgA8DAAAAwA8ADIMAAACADsAPQwAAAMAXwANAAYIuSBYAAB/AgY5DAAABABgADsMAAAEAGMAOgwAAAMAWgA8DAAAAwA8ADIMAAACADsAPQwAAAMAXwAsAAQKgRgAAg0ACAi2JPoDAEIDAA0ACAi2JPoDAEIDAAAA.',Nx='Nxgrug:BAEALAAFFAIIAgABLAAFFAYIDgAZAAUgAA==.',['Ní']='Nízzi:BAECLAAFFIEJAAMCAAQIPBh4AQB5AQQ5DAAAAwBSADsMAAACAFYAOgwAAAMANQA8DAAAAQAZAAIABAg8GHgBAHkBBDkMAAADAFIAOwwAAAIAVgA6DAAAAgA1ADwMAAABABkAAwABCN0BZQwAOAABOgwAAAEABAAsAAQKgRQAAwIACAjkHmAIAM4CAAIACAhYHWAIAM4CAAMAAgiyDF0mAEgAAAAA.',Op='Opbear:BAEALAAECggIEAAAAA==.',Or='Oromisdh:BAEBLAAECoEWAAMQAAgIsCWmAQB6Awg5DAAABABgADsMAAAEAGEAOgwAAAQAYAA8DAAAAgBgADIMAAACAF4APQwAAAIAYQA+DAAAAgBhAD8MAAACAF8AEAAICLAlpgEAegMIOQwAAAQAYAA7DAAABABhADoMAAAEAGAAPAwAAAIAYAAyDAAAAgBeAD0MAAACAGEAPgwAAAIAYQA/DAAAAQBfAA8AAQj9Cxc7ACwAAT8MAAABAB4AAAA=.',Pe='Penkekhtwo:BAEALAAFFAIIAgAAAA==.',Pr='Promitilt:BAEALAADCgEIAQABLAAECggICAAEAAAAAA==.',Ra='Rastikd:BAEALAAECggIBwABLAAECggIGAACADwlAA==.Rastikwr:BAEALAAECgYIBgABLAAECggIGAACADwlAA==.Rastíkx:BAEBLAAECoEYAAQCAAgIPCVICgCvAgg5DAAAAwBjADsMAAADAGMAOgwAAAMAVQA8DAAAAwBcADIMAAADAGMAPQwAAAMAXwA+DAAAAwBhAD8MAAADAFwAAgAHCAAkSAoArwIHOQwAAAIAYwA7DAAAAgBhADoMAAACAFMAMgwAAAEAUwA9DAAAAQBfAD4MAAACAF0APwwAAAIAXAAaAAMIGSSoCwALAQM8DAAAAQBcADIMAAACAGMAPQwAAAEAVQADAAcIlCOmJABaAAc5DAAAAQBiADsMAAABAGMAOgwAAAEAVQA8DAAAAgBaAD0MAAABAFIAPgwAAAEAYQA/DAAAAQBTAAAA.',Ro='Robystrasza:BAECLAAFFIEPAAIJAAYIlBxXAAA7AgY5DAAABABcADsMAAACAEkAOgwAAAMARwA8DAAAAgA6ADIMAAACAEEAPQwAAAIATQAJAAYIlBxXAAA7AgY5DAAABABcADsMAAACAEkAOgwAAAMARwA8DAAAAgA6ADIMAAACAEEAPQwAAAIATQAsAAQKgR8AAgkACAgXHZ8EAJYCAAkACAgXHZ8EAJYCAAAA.Rosahåret:BAEALAAECgEIAQABLAAECgcIFwARADwYAA==.',Sa='Satâñ:BAEALAAECggICAABLAAECggIEAAEAAAAAA==.',Sh='Shammÿ:BAEALAAECggICwABLAAECggIEAAEAAAAAA==.Shollee:BAECLAAFFIEIAAIRAAMIGSH+AgAiAQM5DAAAAwBaADsMAAACAFEAOgwAAAMAUgARAAMIGSH+AgAiAQM5DAAAAwBaADsMAAACAFEAOgwAAAMAUgAsAAQKgSAAAxEACAhEJXUBAEYDABEACAhEJXUBAEYDABkAAQg+IQ9qAE8AAAAA.Shookedlol:BAEALAAECgcIBwABLAAECggIGAAFAJglAA==.',Sk='Skawner:BAEALAAFFAYIEQAAAQ==.',Sn='Snowley:BAEALAAFFAIIAgAAAA==.Snowp:BAEALAAECggIDgABLAAFFAIIAgAEAAAAAA==.',Sp='Sparkgonebad:BAEALAAFFAIIBAAAAA==.Spencie:BAECLAAFFIEGAAIXAAMIuCDlAAAaAQM5DAAAAQBXADsMAAACAFEAOgwAAAMAUwAXAAMIuCDlAAAaAQM5DAAAAQBXADsMAAACAFEAOgwAAAMAUwAsAAQKgR8AAxcACAgNJtQAAHcDABcACAgNJtQAAHcDABsAAQhNIKsOAF8AAAAA.',St='Steffvun:BAEBLAAECoEWAAIQAAgIeCDsEQDTAgg5DAAAAwBbADsMAAADAFQAOgwAAAMATAA8DAAAAwBPADIMAAADAFcAPQwAAAMAVQA+DAAAAgBRAD8MAAACAE4AEAAICHgg7BEA0wIIOQwAAAMAWwA7DAAAAwBUADoMAAADAEwAPAwAAAMATwAyDAAAAwBXAD0MAAADAFUAPgwAAAIAUQA/DAAAAgBOAAAA.',To='Totahat:BAECLAAFFIEGAAMOAAMI+hl7DgC1AAM5DAAAAwBPADsMAAABACoAOgwAAAIATAAOAAIIWhd7DgC1AAI7DAAAAQAqADoMAAACAEwAEwABCDsfcwoAXgABOQwAAAMATwAsAAQKgR4AAxMACAjdIO8HAHkCABMABwhTHO8HAHkCAA4ACAj1F84pADQCAAAA.',Tr='Tridis:BAECLAAFFIEIAAICAAMIkCPdAQBIAQM5DAAAAwBhADsMAAADAEwAOgwAAAIAYwACAAMIkCPdAQBIAQM5DAAAAwBhADsMAAADAEwAOgwAAAIAYwAsAAQKgSEAAgIACAiOJZsAAHQDAAIACAiOJZsAAHQDAAAA.',Tu='Turtlebolt:BAEALAAFFAIIAgABLAAFFAMIBwABADolAA==.Turtlehunt:BAEBLAAFFIEHAAMBAAMIOiWhAgBKAQM5DAAAAwBcADsMAAABAF0AOgwAAAMAYwABAAMIOiWhAgBKAQM5DAAAAgBcADsMAAABAF0AOgwAAAIAYwAFAAII/wkwEACKAAI5DAAAAQArADoMAAABAAcAAAA=.Turtlehuntt:BAEALAAFFAIIAwABLAAFFAMIBwABADolAA==.',Ve='Velichicken:BAEALAADCggIDAABLAAECggIGAAFAJglAA==.Velikan:BAEBLAAECoEYAAIFAAgImCVoAQBxAwg5DAAAAwBiADsMAAADAGEAOgwAAAQAYwA8DAAAAwBhADIMAAADAGMAPQwAAAMAYwA+DAAAAwBTAD8MAAACAF0ABQAICJglaAEAcQMIOQwAAAMAYgA7DAAAAwBhADoMAAAEAGMAPAwAAAMAYQAyDAAAAwBjAD0MAAADAGMAPgwAAAMAUwA/DAAAAgBdAAAA.',Vi='Viviray:BAEALAAECgYIBgABLAAECgcICwAEAAAAAA==.',Vo='Vollmerto:BAECLAAFFIEGAAQLAAIIKh4OCQCrAAI5DAAAAwBUADoMAAADAEYACwACCBEZDgkAqwACOQwAAAIAOgA6DAAAAgBGAAoAAQjcIOMCAEoAATkMAAABAFQACQABCEkHMQoARAABOgwAAAEAEgAsAAQKgRoAAwsACAgWJTMDADgDAAsACAj1JDMDADgDAAoACAiRIRcBAOYCAAAA.',Wo='Wokebot:BAEALAAECgIIAgABLAAFFAIIAgAEAAAAAA==.',Xa='Xacty:BAEALAAECgMIAwABLAAFFAUICAACAAYaAA==.Xactyr:BAEBLAAFFIEIAAMCAAUIBhpzAgAvAQU5DAAAAgBcADsMAAACAFIAOgwAAAEAUwA8DAAAAgA7AD0MAAABAA8AAgADCMsYcwIALwEDOQwAAAIAXAA7DAAAAgBSAD0MAAABAA8AAwACCN8bMwMAvQACOgwAAAEAUwA8DAAAAgA7AAAA.',['Xé']='Xéth:BAEALAAECgcIEQAAAA==.',Ya='Yarnag:BAEBLAAECoEXAAMRAAcIPBh7LgDHAQc5DAAAAwBfADsMAAAEAFIAOgwAAAIATgA8DAAABAA0ADIMAAAEAD0APQwAAAQAIQA+DAAAAgAeABEABwg8GHsuAMcBBzkMAAADAF8AOwwAAAMAUgA6DAAAAgBOADwMAAADADQAMgwAAAMAPQA9DAAAAgAhAD4MAAACAB4AGQAECK0K91EA4gAEOwwAAAEAEwA8DAAAAQAcADIMAAABAB4APQwAAAIAHwAAAA==.',Yt='Ytätäjä:BAEALAADCgUIBQABLAAFFAMICAAIACQZAA==.',['Zò']='Zòi:BAEALAAFFAIIBAABLAAFFAIIBAAEAAAAAA==.Zòí:BAEALAAFFAIIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end