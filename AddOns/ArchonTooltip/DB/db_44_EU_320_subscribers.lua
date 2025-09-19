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
 local lookup = {'Hunter-Marksmanship','Rogue-Assassination','Rogue-Subtlety','Warlock-Destruction','Monk-Windwalker','Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','Druid-Feral','Evoker-Preservation','DeathKnight-Blood','Hunter-BeastMastery','Rogue-Outlaw','Priest-Holy','Druid-Restoration','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Warrior-Protection','Hunter-Survival','Evoker-Devastation','Evoker-Augmentation','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','Monk-Mistweaver',}; local provider = {region='EU',realm='Ragnaros',name='EU',type='subscribers',zone=44,date='2025-09-06',data={An='Ancalágon:BAEALAAECgUIBQABLAAECggIGwABAJgdAA==.Ande:BAEALAADCggICAAAAA==.',Ap='Apachi:BAEBLAAECoEZAAMCAAgIXBuPDACOAgg5DAAAAwBKADsMAAADAFIAOgwAAAQATQA8DAAABABbADIMAAADAFMAPQwAAAQANAA+DAAAAwBbAD8MAAABAAUAAgAICFwbjwwAjgIIOQwAAAMASgA7DAAAAwBSADoMAAAEAE0APAwAAAMAWwAyDAAAAgBTAD0MAAAEADQAPgwAAAMAWwA/DAAAAQAFAAMAAggxFSwhAIEAAjwMAAABAC4AMgwAAAEAPgABLAAFFAUICgACAIgcAA==.Apparatchik:BAECLAAFFIEKAAMCAAUIiBxKAQCCAQU5DAAAAgBeADsMAAACAEcAOgwAAAIATgA8DAAAAgBMAD0MAAACACsAAgAECOIWSgEAggEEOQwAAAIAXgA7DAAAAgBHADoMAAABABcAPQwAAAIAKwADAAIINx4+AwC8AAI6DAAAAQBOADwMAAACAEwALAAECoEWAAICAAgIRSEdBQAHAwACAAgIRSEdBQAHAwAAAA==.',Bl='Blxreroll:BAEALAAECgUIBgABLAAFFAQICwAEALsaAA==.',Bo='Bolldingo:BAEALAAECgcIDQABLAAFFAUIDQAFAFseAA==.Bonytta:BAEALAADCgEIAQABLAAECgcIEwAGAAAAAA==.',Ca='Capsalot:BAECLAAFFIEIAAMHAAMIzRsGAQAUAQM5DAAAAwBeADsMAAACAFAAOgwAAAMAJgAHAAMIYRYGAQAUAQM5DAAAAgBeADsMAAABACYAOgwAAAIAJgAIAAMI4RRWBgD9AAM5DAAAAQBBADsMAAABAFAAOgwAAAEADgAsAAQKgR8AAwcACAi0JM4BAAwDAAcACAiMJM4BAAwDAAgABgjGHo8gAA0CAAAA.Carpetnar:BAEALAAECgcIDwABLAAFFAUIDAAJABsbAA==.',Ch='Chimedh:BAEALAADCggICAABLAAECggIHwAHABofAA==.Chimeshaman:BAEBLAAECoEfAAMHAAgIGh85AgDyAgg5DAAABgBWADsMAAAFAF8AOgwAAAQAYgA8DAAABABWADIMAAAFAFgAPQwAAAQAXwA+DAAAAgAyAD8MAAABACMABwAICBofOQIA8gIIOQwAAAYAVgA7DAAABQBfADoMAAAEAGIAPAwAAAQAVgAyDAAABQBYAD0MAAAEAF8APgwAAAEAMgA/DAAAAQAjAAgAAQgsD3ZsAEIAAT4MAAABACYAAAA=.',Cr='Crwnn:BAEALAADCgEIAQAAAA==.',De='Denegatia:BAECLAAFFIENAAIFAAUIWx57AADuAQU5DAAAAwBIADsMAAADAFgAOgwAAAQAXQA8DAAAAgBcAD0MAAABACkABQAFCFseewAA7gEFOQwAAAMASAA7DAAAAwBYADoMAAAEAF0APAwAAAIAXAA9DAAAAQApACwABAqBGAACBQAICKcmWwAAiAMABQAICKcmWwAAiAMAAAA=.',Dr='Dragicorn:BAECLAAFFIEOAAIKAAUIMA5DAQCSAQU5DAAABABaADsMAAACAAEAOgwAAAQAVQA8DAAAAgAAAD0MAAACAAMACgAFCDAOQwEAkgEFOQwAAAQAWgA7DAAAAgABADoMAAAEAFUAPAwAAAIAAAA9DAAAAgADACwABAqBHgACCgAICJMZmAUAdgIACgAICJMZmAUAdgIAAAA=.',['Dà']='Dàrk:BAECLAAFFIEIAAILAAMIdBVGAgDvAAM5DAAAAwBCADsMAAACAC4AOgwAAAMAMwALAAMIdBVGAgDvAAM5DAAAAwBCADsMAAACAC4AOgwAAAMAMwAsAAQKgR4AAgsACAgBIs0DAOoCAAsACAgBIs0DAOoCAAAA.',['Dá']='Dárkflame:BAEALAAECgIIAgABLAAFFAIIBQABAJYLAA==.',['Dä']='Därkbeast:BAECLAAFFIEFAAIBAAIIlgsKEQCAAAI5DAAAAwAyADoMAAACAAgAAQACCJYLChEAgAACOQwAAAMAMgA6DAAAAgAIACwABAqBIwADAQAICDoiPQcA+gIAAQAICDoiPQcA+gIADAABCAgQEZQAOQAAAAA=.',El='Elejulqt:BAEALAAFFAIIAgABLAAFFAIIBAAGAAAAAA==.',En='Engrah:BAEALAAECgcIEwAAAA==.Enormesvindk:BAEALAAECgYIBgABLAAECggIGAANAAQmAA==.Enormesvinro:BAEBLAAECoEYAAINAAgIBCYpAAB6Awg5DAAAAwBjADsMAAAEAGMAOgwAAAQAYwA8DAAAAwBgADIMAAAEAGAAPQwAAAQAYgA+DAAAAQBiAD8MAAABAFsADQAICAQmKQAAegMIOQwAAAMAYwA7DAAABABjADoMAAAEAGMAPAwAAAMAYAAyDAAABABgAD0MAAAEAGIAPgwAAAEAYgA/DAAAAQBbAAAA.',Gr='Grækenland:BAEALAAECgMIBAABLAAFFAIIAgAGAAAAAA==.',Ho='Holyunicorn:BAEALAAECgcIDAABLAAFFAUIDgAKADAOAA==.Holyzmile:BAEBLAAFFIEGAAIOAAMIqw0rBwD4AAM5DAAAAgAbADsMAAACABoAOgwAAAIAMwAOAAMIqw0rBwD4AAM5DAAAAgAbADsMAAACABoAOgwAAAIAMwAAAA==.',Ic='Icyhater:BAEALAAECgcIEAAAAA==.',Il='Ildifusserne:BAEALAAFFAIIAgAAAA==.Ilyindia:BAEALAAECgcIEwAAAA==.',Jo='Joshyidh:BAEALAAECggICAABLAAFFAIIAgAGAAAAAA==.Joshyijr:BAEALAADCgUIBQABLAAFFAIIAgAGAAAAAA==.Joshyis:BAEALAAFFAIIAgAAAA==.',Kw='Kwigga:BAEALAAECggICgABLAAFFAMICQAPAFElAA==.',Le='Lenerie:BAEALAAECgYICwAAAA==.',Li='Livelørð:BAECLAAFFIELAAMEAAQIuxpHBwAQAQQ5DAAAAwBRADsMAAADADsAOgwAAAMAVwA8DAAAAgAtAAQAAwg1GEcHABABAzkMAAADAFEAOwwAAAMAOwA8DAAAAgAtABAAAQhNIjEOAGUAAToMAAADAFcALAAECoEdAAQEAAgIrCOWBQAxAwAEAAgIECOWBQAxAwARAAUIXiLuCADkAQAQAAUIJiNaFwDWAQAAAA==.',Lv='Lvlrd:BAEALAADCgcIBwABLAAFFAQICwAEALsaAA==.',Ma='Margokel:BAEALAADCggIAQABLAAECgcIEwAGAAAAAA==.',Me='Meownar:BAECLAAFFIEMAAIJAAUIGxtbAADXAQU5DAAABABcADsMAAACAC0AOgwAAAMAXAA8DAAAAgBLAD0MAAABACkACQAFCBsbWwAA1wEFOQwAAAQAXAA7DAAAAgAtADoMAAADAFwAPAwAAAIASwA9DAAAAQApACwABAqBFgACCQAICCclOAIAHgMACQAICCclOAIAHgMAAAA=.',Mo='Moó:BAEBLAAECoEbAAMBAAgImB19DgCWAgg5DAAABABVADsMAAAEAFMAOgwAAAQAPQA8DAAABABLADIMAAADAFwAPQwAAAMATAA+DAAAAwBLAD8MAAACADYAAQAICPYcfQ4AlgIIOQwAAAIAVQA7DAAAAwBTADoMAAACADEAPAwAAAIASwAyDAAAAgBcAD0MAAACAEwAPgwAAAIASwA/DAAAAgA2AAwABwjaE9g6AJ8BBzkMAAACAEQAOwwAAAEAPAA6DAAAAgA9ADwMAAACACYAMgwAAAEAKgA9DAAAAQBDAD4MAAABAA8AAAA=.',Mu='Murçisztár:BAEALAAECgYICQABLAAECgYICwAGAAAAAA==.Muskotten:BAEBLAAECoEaAAIOAAcIKh/MEAB8Agc5DAAABABRADsMAAAEAFQAOgwAAAQAXAA8DAAABAA5ADIMAAAEAFAAPQwAAAQAWwA+DAAAAgBGAA4ABwgqH8wQAHwCBzkMAAAEAFEAOwwAAAQAVAA6DAAABABcADwMAAAEADkAMgwAAAQAUAA9DAAABABbAD4MAAACAEYAAAA=.',Ne='Netherax:BAEBLAAFFIEOAAIIAAYIBSA1AACHAgY5DAAAAwBjADsMAAACAGAAOgwAAAQAZAA8DAAAAgBKADIMAAABABcAPQwAAAIAYQAIAAYIBSA1AACHAgY5DAAAAwBjADsMAAACAGAAOgwAAAQAZAA8DAAAAgBKADIMAAABABcAPQwAAAIAYQAAAA==.',No='Nomuwu:BAEALAADCggICwABLAAECgcIEwAGAAAAAA==.',Pe='Petérdh:BAEALAAECgIIAwAAAA==.',Pr='Prigga:BAEALAAECgYIBwABLAAFFAMICQAPAFElAA==.Primeazoid:BAECLAAFFIENAAIOAAUI0SRaAAAsAgU5DAAAAgBhADsMAAADAGEAOgwAAAQAYwA8DAAAAgBQAD0MAAACAGAADgAFCNEkWgAALAIFOQwAAAIAYQA7DAAAAwBhADoMAAAEAGMAPAwAAAIAUAA9DAAAAgBgACwABAqBFwACDgAICMUlYQEAXgMADgAICMUlYQEAXgMAAAA=.',Ra='Rahka:BAEALAADCggIBwABLAAECgcIEwAGAAAAAA==.',Re='Reckful:BAEALAAFFAIIAgABLAAFFAUICgASAK0YAA==.Rexwarr:BAECLAAFFIEIAAITAAMInxjvAgD6AAM5DAAAAwBMADsMAAACADsAOgwAAAMANAATAAMInxjvAgD6AAM5DAAAAwBMADsMAAACADsAOgwAAAMANAAsAAQKgR0AAhMACAi3IN4FANcCABMACAi3IN4FANcCAAAA.',Sa='Sandkassen:BAEALAAECgUIBQABLAAFFAIIAgAGAAAAAA==.',Sc='Scruffer:BAEBLAAECoEXAAMMAAcItCRwDQDQAgc5DAAABQBeADsMAAAFAF8AOgwAAAQAXAA8DAAAAwBeADIMAAACAFsAPQwAAAIAYwA+DAAAAgBaAAwABwi0JHANANACBzkMAAAEAF4AOwwAAAQAXwA6DAAAAwBcADwMAAACAF4AMgwAAAIAWwA9DAAAAgBjAD4MAAACAFoAFAAECKoQ5gwA+QAEOQwAAAEABQA7DAAAAQBMADoMAAABADMAPAwAAAEAJAAAAA==.',Se='Setilvenstre:BAEALAAFFAIIAgABLAAFFAIIAgAGAAAAAA==.',Sk='Skrai:BAECLAAFFIEFAAIVAAMI5Q/+BQDxAAM5DAAAAwAlADoMAAABAD8APAwAAAEAFAAVAAMI5Q/+BQDxAAM5DAAAAwAlADoMAAABAD8APAwAAAEAFAAsAAQKgRcAAhUACAgPIwUGAAADABUACAgPIwUGAAADAAAA.Skraitwo:BAEBLAAECoEcAAMVAAgIgyHEBgDyAgg5DAAABABfADsMAAAEAFwAOgwAAAQAXQA8DAAABABbADIMAAADAEQAPQwAAAQAWAA+DAAAAwBVAD8MAAACAEYAFQAICIMhxAYA8gIIOQwAAAQAXwA7DAAABABcADoMAAAEAF0APAwAAAQAWwAyDAAAAwBEAD0MAAAEAFgAPgwAAAIAVQA/DAAAAgBGABYAAQj7HAAAAAAAAT4MAAABAEoAASwABRQDCAUAFQDlDwA=.',Sm='Smòsh:BAEALAADCggIDwABLAAECggIGwABAJgdAA==.',Sn='Snowmaballs:BAEBLAAECoEWAAMXAAgIzyAsDQBRAgg5DAAAAgBbADsMAAADAFUAOgwAAAIAUAA8DAAAAwBWADIMAAAEAF4APQwAAAMAWwA+DAAAAwBIAD8MAAACAEYAFwAHCGcgLA0AUQIHOwwAAAEAVQA6DAAAAgBQADwMAAADAFYAMgwAAAMAXgA9DAAAAwBbAD4MAAABAEgAPwwAAAEARgAYAAUIixalVwBdAQU5DAAAAgBbADsMAAACAFEAMgwAAAEATQA+DAAAAgAVAD8MAAABABAAASwABRQFCAoAEgCtGAA=.Snowxo:BAECLAAFFIEKAAMSAAUIrRhrAgB8AQU5DAAAAwBcADsMAAACAEMAOgwAAAEAIgA8DAAAAQBXAD0MAAADACEAEgAECHAVawIAfAEEOQwAAAIAXAA6DAAAAQAiADwMAAABAFcAPQwAAAEABQAZAAMIKRW/AQAYAQM5DAAAAQA9ADsMAAACAEMAPQwAAAIAIQAsAAQKgRgAAxkACAgpJXoGAJ0CABkABwgrJHoGAJ0CABIACAhuGhMnAEMCAAAA.Snuffed:BAEALAAECgIIAgABLAAECgcIFwAMALQkAA==.Snuffer:BAEALAAECgUICgABLAAECgcIFwAMALQkAA==.',Ta='Taskaine:BAECLAAFFIEOAAIKAAYIsQ3QAADvAQY5DAAABAAvADsMAAACAC4AOgwAAAMAIQA8DAAAAgAXADIMAAACAC4APQwAAAEADAAKAAYIsQ3QAADvAQY5DAAABAAvADsMAAACAC4AOgwAAAMAIQA8DAAAAgAXADIMAAACAC4APQwAAAEADAAsAAQKgSAAAgoACAhcHJ4FAHUCAAoACAhcHJ4FAHUCAAAA.Taskainedup:BAEALAADCggICAABLAAFFAYIDgAKALENAA==.Taskainp:BAEBLAAECoEYAAIOAAgIERRVIAD9AQg5DAAAAwAnADsMAAADAFcAOgwAAAMATgA8DAAAAwAhADIMAAADADcAPQwAAAMAJgA+DAAAAwAoAD8MAAADACQADgAICBEUVSAA/QEIOQwAAAMAJwA7DAAAAwBXADoMAAADAE4APAwAAAMAIQAyDAAAAwA3AD0MAAADACYAPgwAAAMAKAA/DAAAAwAkAAEsAAUUBggOAAoAsQ0A.Taskainpala:BAEALAAFFAIIAgABLAAFFAYIDgAKALENAA==.',Ti='Tibikasza:BAEALAAECgMIAQABLAAECggIHwAHABofAA==.Titanbelly:BAECLAAFFIENAAIaAAUIVCZBAAA9AgU5DAAABABjADsMAAADAGMAOgwAAAIAZAA8DAAAAgBeAD0MAAACAGAAGgAFCFQmQQAAPQIFOQwAAAQAYwA7DAAAAwBjADoMAAACAGQAPAwAAAIAXgA9DAAAAgBgACwABAqBFQACGgAICMwmiQAAagMAGgAICMwmiQAAagMAAAA=.',Vo='Vollmer:BAEBLAAFFIETAAIVAAYIkCMcAACaAgY5DAAABABjADsMAAAEAGIAOgwAAAQAYwA8DAAAAwBZADIMAAACAGMAPQwAAAIAPAAVAAYIkCMcAACaAgY5DAAABABjADsMAAAEAGIAOgwAAAQAYwA8DAAAAwBZADIMAAACAGMAPQwAAAIAPAAAAA==.Vollmerfire:BAEALAAECgEIAQABLAAFFAYIEwAVAJAjAA==.',Xa='Xaretas:BAEALAAECgUIBgAAAA==.',Ye='Yepterw:BAEALAAECgEIAQABLAAECgIIAwAGAAAAAA==.',Zm='Zmile:BAEALAAECgYIBgABLAAFFAMIBgAOAKsNAA==.Zmiledrake:BAEALAAECggIDgABLAAFFAMIBgAOAKsNAA==.',Zz='Zzeeikw:BAEALAADCggICAABLAAFFAMICAALAHQVAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end