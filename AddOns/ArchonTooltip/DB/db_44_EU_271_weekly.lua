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
 local lookup = {'Mage-Frost','Mage-Arcane','Paladin-Retribution','Druid-Guardian','Druid-Feral','Warrior-Fury','Rogue-Subtlety','DemonHunter-Havoc','Druid-Balance','DeathKnight-Frost','Hunter-Marksmanship','Evoker-Augmentation','Monk-Mistweaver','Unknown-Unknown','Hunter-BeastMastery','Warlock-Destruction','Paladin-Holy','Warlock-Demonology','Priest-Holy','Monk-Brewmaster','Shaman-Elemental','Paladin-Protection','Priest-Shadow',}; local provider = {region='EU',realm='BurningSteppes',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Ace:BAAALAAECgYIDAAAAA==.',Ae='Aeolis:BAABLAAECoEUAAIBAAgIqw9eIwDaAQABAAgIqw9eIwDaAQAAAA==.',Am='Amansoroniel:BAABLAAECoEdAAIBAAgIkhKFHQADAgABAAgIkhKFHQADAgAAAA==.',Ar='Arcameplease:BAABLAAECoEaAAIBAAcIzhfGGgAYAgABAAcIzhfGGgAYAgAAAA==.Ardros:BAABLAAECoEdAAMBAAYI4xu5LwCSAQACAAYIIxafbgCTAQABAAYIYBe5LwCSAQAAAA==.',Ba='Babysham:BAAALAADCgEIAQAAAA==.Bartlina:BAAALAAECgYIDAAAAA==.',Be='Beastsmack:BAAALAADCgcIBwAAAA==.Behemoth:BAABLAAECoEYAAIDAAgI+x7MHgDTAgADAAgI+x7MHgDTAgAAAA==.',Bi='Bigdude:BAAALAAECggICAAAAA==.',Br='Brodetjetski:BAABLAAECoElAAMEAAgIwCBCBAC0AgAEAAgIRx1CBAC0AgAFAAgITx5BCACwAgAAAA==.Bru:BAAALAADCgcIDwAAAA==.',Bw='Bweatysollix:BAABLAAECoEbAAIGAAgIPhzqHwCaAgAGAAgIPhzqHwCaAgAAAA==.',Ca='Cailun:BAAALAADCggICwAAAA==.',Co='Coffee:BAAALAADCggICgAAAA==.Coraline:BAAALAAFFAIIAgAAAA==.Cornudo:BAAALAAFFAIIBAABLAAFFAYIFQAHACIeAA==.',Cu='Cursedone:BAAALAAECgEIAQAAAA==.',Da='Dadbod:BAAALAADCgMIAwAAAA==.',De='Deadsmack:BAAALAAECgEIAQAAAA==.Deathjinx:BAABLAAECoEaAAIIAAcIcBXvXgDZAQAIAAcIcBXvXgDZAQAAAA==.Defclock:BAAALAADCggIDwAAAA==.',Di='Dimeziak:BAAALAAECgYIDAAAAA==.Disomus:BAABLAAECoEYAAIJAAYIIh8yKAD4AQAJAAYIIh8yKAD4AQAAAA==.Dispair:BAAALAAECgcIBwAAAA==.',Dk='Dkarthas:BAAALAAFFAMIBQAAAQ==.',Dr='Dramacius:BAABLAAECoEnAAICAAgIXhN+QgAcAgACAAgIXhN+QgAcAgAAAA==.',Dt='Dtomi:BAAALAAECgMIBAAAAA==.',Du='Dumgrol:BAAALAADCgYIBgAAAA==.',['Dí']='Dímmuburger:BAACLAAFFIEUAAIJAAYI9SHCAABeAgAJAAYI9SHCAABeAgAsAAQKgSoAAgkACAiZJmkBAH0DAAkACAiZJmkBAH0DAAAA.',Ea='Earthenfurry:BAAALAAECgYIBgAAAA==.',Er='Ertvak:BAAALAAECgQIBgAAAA==.',Ev='Eveliina:BAAALAADCggICAAAAA==.',Ex='Extinct:BAAALAAECgQIBAAAAA==.',Fa='Fab:BAAALAAECgcICAABLAAFFAMIBwAKAGsNAA==.Fangthyr:BAAALAADCggICAAAAA==.',Fe='Felitha:BAAALAADCgEIAQAAAA==.',Fi='Firelord:BAAALAADCgUIBQAAAA==.',Fr='Fryjj:BAABLAAECoEdAAILAAgIXxxZFwCPAgALAAgIXxxZFwCPAgAAAA==.Frÿj:BAAALAAECgQIBAAAAA==.',Fx='Fxdh:BAABLAAECoEcAAIIAAgICBbIOwBBAgAIAAgICBbIOwBBAgAAAA==.',Gn='Gnomagio:BAAALAAECgQIBAAAAA==.',Gr='Grabber:BAAALAAECgYIEwAAAA==.Grib:BAACLAAFFIEKAAIJAAMIRyKJBwAfAQAJAAMIRyKJBwAfAQAsAAQKgRkAAgkACAiBJE0NAOUCAAkACAiBJE0NAOUCAAAA.',Ha='Habuerit:BAAALAAECgIIAgAAAA==.Hadronox:BAAALAADCgUIBwAAAA==.Hanna:BAAALAAECgYIDwAAAA==.Hanshestepik:BAAALAAFFAEIAQAAAA==.Haribo:BAAALAAECgYIBgAAAA==.',He='Hellzberg:BAAALAADCgIIAgAAAA==.Hevone:BAABLAAECoEUAAICAAcI7x4kOgA9AgACAAcI7x4kOgA9AgABLAAFFAYIFAAJAPUhAA==.',['Hò']='Hòudini:BAAALAAECgEIAQAAAA==.',Ik='Iknowmagic:BAABLAAECoEXAAMCAAgIBiM3IgCsAgACAAgIBiM3IgCsAgABAAIIbCKeZgCAAAAAAA==.',Ja='Jadestorm:BAAALAADCggICAAAAA==.Jake:BAAALAAECggIEAAAAA==.',Jo='Jorgramdr:BAAALAADCggIDAAAAA==.',Ka='Kabab:BAAALAADCgEIAQAAAA==.',Ki='Killshot:BAAALAAECggIAQAAAA==.Kimjungheal:BAAALAADCgIIAgAAAA==.Kishikaisei:BAAALAAECgYIEwAAAA==.Kitsera:BAABLAAECoEWAAIMAAgIoySjAgC1AgAMAAgIoySjAgC1AgABLAAECggIHwANAM0fAA==.',Ko='Komskom:BAAALAAECgYICAAAAA==.Korallina:BAAALAADCgMIAwAAAA==.',Kr='Kryn:BAAALAADCgIIAgABLAAECgUICQAOAAAAAA==.',Ku='Kunga:BAACLAAFFIEKAAILAAMI/x41CQAQAQALAAMI/x41CQAQAQAsAAQKgSsAAgsACAjsIZsKAAMDAAsACAjsIZsKAAMDAAAA.',La='Laa:BAAALAAECgYICgAAAA==.Lalnadh:BAAALAADCgYIBgABLAAECgcIBwAOAAAAAA==.Lalnadin:BAAALAADCgYIBgABLAAECgcIBwAOAAAAAA==.Lalnadruid:BAAALAAECgcIBwAAAA==.',Lo='Lo:BAAALAAECgcIDAAAAA==.Lonika:BAAALAAFFAIIAgABLAAFFAYIFAAJAPUhAA==.Lonikadh:BAAALAADCgYIBgAAAA==.',Ma='Marcash:BAABLAAECoEnAAMPAAgIHyA1IACdAgAPAAgIHyA1IACdAgALAAIIwBk5iQCJAAAAAA==.Markus:BAABLAAECoEcAAICAAgItQ+EUADtAQACAAgItQ+EUADtAQAAAA==.',Me='Merion:BAABLAAECoEgAAMJAAgIoBrUHABHAgAJAAgIKRnUHABHAgAFAAQIVRAFKgD4AAAAAA==.Merionter:BAAALAADCggICAABLAAECggIIAAJAKAaAA==.Meviuz:BAABLAAECoEhAAIQAAgIvw/sSADgAQAQAAgIvw/sSADgAQAAAA==.',Mi='Minxx:BAAALAADCggIFgAAAA==.',Mo='Mooselee:BAAALAAECgYIEgAAAA==.',Mu='Mula:BAAALAADCgYIEQAAAA==.',Na='Najgor:BAAALAAECggIEAAAAA==.Napiyon:BAAALAADCgcIBwAAAA==.Nariell:BAAALAADCgMIAwAAAA==.Nazaroth:BAAALAADCggIFQAAAA==.',Ni='Niko:BAAALAAECggIDgAAAA==.',No='Nobeardnonp:BAAALAAECgYICgAAAA==.',Or='Orchid:BAAALAAECgYIDwAAAA==.',Pa='Paladunos:BAACLAAFFIEKAAIRAAMIYBJQCQDrAAARAAMIYBJQCQDrAAAsAAQKgRoAAhEACAi/GoQSAFICABEACAi/GoQSAFICAAAA.Pallu:BAAALAAECgYIDgAAAA==.Pavullon:BAAALAADCggIFgABLAAECggIJQAGAEAdAA==.Pawullock:BAAALAADCgQIBAABLAAECggIJQAGAEAdAA==.Pawullon:BAABLAAECoElAAIGAAgIQB0VHgCnAgAGAAgIQB0VHgCnAgAAAA==.',Pe='Perpetua:BAABLAAECoESAAMSAAcIWwzZKwCfAQASAAcIWwzZKwCfAQAQAAEIHwyE1QAzAAAAAA==.',Po='Pondo:BAAALAAECggIDgAAAA==.',Ra='Raffsham:BAAALAAECgEIAQAAAA==.Raizza:BAACLAAFFIEGAAITAAIIqRVkHACcAAATAAIIqRVkHACcAAAsAAQKgSUAAhMACAhJHX4UAKcCABMACAhJHX4UAKcCAAAA.Ratnum:BAABLAAECoEWAAIPAAgIHRcCOgAqAgAPAAgIHRcCOgAqAgAAAA==.Ravana:BAAALAAECgYIEAAAAA==.',Re='Revênge:BAAALAADCgMIAwAAAA==.',Ro='Roëk:BAAALAADCgEIAQABLAAFFAYIHAAUAIkjAA==.',Ru='Ruth:BAAALAADCgUIBQAAAA==.',Ry='Ryuu:BAAALAAECgEIAQAAAA==.',Sa='Santtu:BAAALAAECgYIEQAAAA==.Sashin:BAACLAAFFIEGAAIDAAIIByElFADJAAADAAIIByElFADJAAAsAAQKgSIAAgMACAglIQkYAPcCAAMACAglIQkYAPcCAAAA.',Sc='Schavi:BAABLAAECoEXAAIVAAcIHhU1OwDmAQAVAAcIHhU1OwDmAQAAAA==.',Se='Seancon:BAAALAADCggICQAAAA==.Serah:BAABLAAECoEfAAINAAgIzR8kBwDWAgANAAgIzR8kBwDWAgAAAA==.Seraph:BAAALAAECgUIBQAAAA==.',Sh='Shajbus:BAAALAAECgYIDgAAAA==.Shazoom:BAAALAAECgIIAwAAAA==.Shockdaddy:BAAALAAECgUICQAAAA==.',Sj='Sjeffer:BAAALAADCgQIBAAAAA==.',Sk='Skull:BAAALAADCgQIBAAAAA==.',Sm='Smutt:BAABLAAECoEfAAMDAAgIthlIOwBaAgADAAgIthlIOwBaAgAWAAYI5At+NwAKAQAAAA==.',So='Sooncoldaxe:BAAALAAECgIIAgAAAA==.',St='Stuart:BAAALAADCggICAABLAAFFAMICgALAP8eAA==.',Sy='Sylvanemrys:BAAALAADCggIEAAAAA==.',['Sé']='Sérgenda:BAAALAADCgYIBgABLAAFFAMIBQAOAAAAAQ==.',Ta='Talasyn:BAAALAADCggICAABLAAECgcIEgASAFsMAA==.Taunteth:BAAALAAECgYIBgABLAAFFAYIHAAUAIkjAA==.',Th='Thiccism:BAAALAADCgcIDwAAAA==.Thieu:BAAALAAFFAIIAgABLAAFFAMIBQAOAAAAAQ==.',Ti='Tia:BAAALAAECgIIBAAAAA==.',To='Tonke:BAACLAAFFIEcAAIUAAYIiSOwAAB7AgAUAAYIiSOwAAB7AgAsAAQKgTAAAhQACAjLJj4AAJEDABQACAjLJj4AAJEDAAAA.',Va='Vali:BAAALAAECgIIAgABLAAECggIHwAVAAgfAA==.Validush:BAAALAAECgYIBgAAAA==.Valiënne:BAABLAAECoEfAAIVAAgICB++EgDiAgAVAAgICB++EgDiAgAAAA==.',Vo='Vood:BAABLAAECoEXAAIDAAYIExoNbwDUAQADAAYIExoNbwDUAQAAAA==.',Wa='Wanaja:BAAALAAECgcICQAAAA==.Wariorusan:BAAALAAECggIDgAAAA==.',Wh='Whailor:BAAALAAECgYIBwAAAA==.',Xa='Xaeth:BAABLAAECoEiAAIEAAgIViZyAACCAwAEAAgIViZyAACCAwAAAA==.Xapo:BAAALAAECgYIEgABLAAFFAUIEwAIAO4fAA==.',Xi='Xilra:BAABLAAECoEgAAMTAAgIfQ86QQCoAQATAAgIfQ86QQCoAQAXAAgIogXRTQBUAQAAAA==.',Yo='Yorgos:BAAALAADCgcICAAAAA==.',Yu='Yuki:BAAALAAECgQIBAAAAA==.',['Yö']='Yönlutka:BAABLAAECoElAAIXAAgIIiJHCAApAwAXAAgIIiJHCAApAwABLAAFFAYIFAAJAPUhAA==.',['Øl']='Øl:BAABLAAECoEYAAICAAgIAxNxSgAAAgACAAgIAxNxSgAAAgAAAA==.',['Üb']='Übershep:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end