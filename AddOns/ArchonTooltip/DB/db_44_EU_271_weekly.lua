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
 local lookup = {'Mage-Frost','Mage-Arcane','Druid-Feral','Druid-Guardian','Rogue-Subtlety','Druid-Balance','DemonHunter-Havoc','Evoker-Augmentation','Hunter-Marksmanship','Unknown-Unknown','Hunter-BeastMastery','Paladin-Holy','Warrior-Fury','Priest-Holy','Monk-Brewmaster','Priest-Shadow',}; local provider = {region='EU',realm='BurningSteppes',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Ace:BAAALAAECgYIDAAAAA==.',Ae='Aeolis:BAAALAAECgYICQAAAA==.',Am='Amansoroniel:BAAALAAECgcIDgAAAA==.',Ar='Arcameplease:BAAALAAECgYIBgAAAA==.Ardros:BAABLAAECoEVAAMBAAYIMBbcHgCcAQABAAYIMBbcHgCcAQACAAYIRAkSZwAaAQAAAA==.',Ba='Babysham:BAAALAADCgEIAQAAAA==.',Be='Beastsmack:BAAALAADCgcIBwAAAA==.Behemoth:BAAALAAECgYIEAAAAA==.',Br='Brodetjetski:BAABLAAECoEVAAMDAAgIdRnYCABHAgADAAgIrBbYCABHAgAEAAQI+BjjDAAfAQAAAA==.Bru:BAAALAADCgcIBwAAAA==.',Bw='Bweatysollix:BAAALAAECgYICQAAAA==.',Ca='Cailun:BAAALAADCggICwAAAA==.',Co='Coffee:BAAALAADCgIIAgAAAA==.Coraline:BAAALAADCggICAAAAA==.Cornudo:BAAALAAFFAIIBAABLAAFFAUICwAFABscAA==.',Cu='Cursedone:BAAALAAECgEIAQAAAA==.',Da='Dadbod:BAAALAADCgMIAwAAAA==.',De='Deadsmack:BAAALAAECgEIAQAAAA==.Deathjinx:BAAALAAECgcIDAAAAA==.Defclock:BAAALAADCggIDwAAAA==.',Di='Dimeziak:BAAALAADCgMIAwAAAA==.Disomus:BAAALAAECgYIEgAAAA==.',Dk='Dkarthas:BAAALAAFFAMIAwAAAQ==.',Dr='Dramacius:BAABLAAECoEYAAICAAgIYA88NQDvAQACAAgIYA88NQDvAQAAAA==.',Dt='Dtomi:BAAALAADCgcIBwAAAA==.',Du='Dumgrol:BAAALAADCgYIBgAAAA==.',['Dí']='Dímmuburger:BAACLAAFFIEJAAIGAAQI2yAlAQCbAQAGAAQI2yAlAQCbAQAsAAQKgSAAAgYACAhtJVgBAHMDAAYACAhtJVgBAHMDAAAA.',Er='Ertvak:BAAALAAECgQIBgAAAA==.',Ex='Extinct:BAAALAAECgQIBAAAAA==.',Fa='Fangthyr:BAAALAADCggICAAAAA==.',Fe='Felitha:BAAALAADCgEIAQAAAA==.',Fr='Fryjj:BAAALAAECggIEQAAAA==.Frÿj:BAAALAADCgIIAgAAAA==.',Fx='Fxdh:BAABLAAECoEUAAIHAAcICA73SACkAQAHAAcICA73SACkAQAAAA==.',Gr='Grabber:BAAALAAECgQIBwAAAA==.Grib:BAACLAAFFIEFAAIGAAMIKBzXAgAZAQAGAAMIKBzXAgAZAQAsAAQKgRkAAgYACAiBJB4EAD0DAAYACAiBJB4EAD0DAAAA.',Ha='Habuerit:BAAALAAECgIIAgAAAA==.Hadronox:BAAALAADCgUIBwAAAA==.Hanna:BAAALAAECgYICQAAAA==.Hanshestepik:BAAALAAECgUICQAAAA==.',He='Hevone:BAAALAAFFAIIAgABLAAFFAQICQAGANsgAA==.',['Hò']='Hòudini:BAAALAAECgEIAQAAAA==.',Ik='Iknowmagic:BAABLAAECoEXAAMCAAgIBiOyDgDrAgACAAgIBiOyDgDrAgABAAIIbCLtRQCNAAAAAA==.',Ja='Jadestorm:BAAALAADCggICAAAAA==.',Jo='Jorgramdr:BAAALAADCggIDAAAAA==.',Ki='Kimjungheal:BAAALAADCgIIAgAAAA==.Kishikaisei:BAAALAAECgYIDQAAAA==.Kitsera:BAABLAAECoEWAAIIAAgIoyTfAAACAwAIAAgIoyTfAAACAwAAAA==.',Ko='Komskom:BAAALAAECgYICAAAAA==.Korallina:BAAALAADCgMIAwAAAA==.',Kr='Kryn:BAAALAADCgIIAgAAAA==.',Ku='Kunga:BAABLAAECoEbAAIJAAgI6yDzCADiAgAJAAgI6yDzCADiAgAAAA==.',La='Laa:BAAALAADCggIFAAAAA==.Lalnadh:BAAALAADCgYIBgABLAAECgcIBwAKAAAAAA==.Lalnadin:BAAALAADCgYIBgABLAAECgcIBwAKAAAAAA==.Lalnadruid:BAAALAAECgcIBwAAAA==.',Lo='Lo:BAAALAAECgcIDAAAAA==.Lonika:BAAALAAECgUIBQABLAAFFAQICQAGANsgAA==.',Ma='Marcash:BAABLAAECoEXAAMLAAcIKCDvFACFAgALAAcIKCDvFACFAgAJAAIIwBm0VwCVAAAAAA==.Markus:BAAALAAECggIDgAAAA==.',Me='Merion:BAABLAAECoEYAAMGAAgIuxiSFQA2AgAGAAgIRBeSFQA2AgADAAMIexHoHQDQAAAAAA==.Meviuz:BAAALAAECgYICQAAAA==.',Mi='Minxx:BAAALAADCggIFgAAAA==.',Mo='Mooselee:BAAALAAECgYIBgAAAA==.',Mu='Mula:BAAALAADCgYIEQAAAA==.',Na='Najgor:BAAALAAECggIDQAAAA==.Nariell:BAAALAADCgMIAwAAAA==.Nazaroth:BAAALAADCggIFQAAAA==.',Ni='Niko:BAAALAAECgcIBwAAAA==.',No='Nobeardnonp:BAAALAAECgYICAAAAA==.',Or='Orchid:BAAALAAECgYICwAAAA==.',Pa='Paladunos:BAACLAAFFIEFAAIMAAMIJQZ9BQDZAAAMAAMIJQZ9BQDZAAAsAAQKgRoAAgwACAi/GkkKAF0CAAwACAi/GkkKAF0CAAAA.Pallu:BAAALAAECgMIBAAAAA==.Pavullon:BAAALAADCggIEAABLAAECggIFwANABcWAA==.Pawullon:BAABLAAECoEXAAINAAgIFxZsGQBQAgANAAgIFxZsGQBQAgAAAA==.',Pe='Perpetua:BAAALAAECgcICQAAAA==.',Ra='Raizza:BAABLAAECoEUAAIOAAgIfRmuEQB0AgAOAAgIfRmuEQB0AgAAAA==.Ratnum:BAAALAADCgYIBwAAAA==.Ravana:BAAALAAECgYICgAAAA==.',Re='Revênge:BAAALAADCgMIAwAAAA==.',Ro='Roëk:BAAALAADCgEIAQABLAAFFAUIDwAPAG4hAA==.',Ru='Ruth:BAAALAADCgUIBQAAAA==.',Ry='Ryuu:BAAALAADCggIDQAAAA==.',Sa='Santtu:BAAALAADCggIHAAAAA==.Sashin:BAAALAAFFAIIAgAAAA==.',Sc='Schavi:BAAALAAECgYICQAAAA==.',Se='Seancon:BAAALAADCggICQAAAA==.Serah:BAAALAAECgYICQABLAAECggIFgAIAKMkAA==.Seraph:BAAALAADCgMIAwAAAA==.',Sh='Shajbus:BAAALAAECgEIAQAAAA==.Shazoom:BAAALAAECgIIAwAAAA==.Shockdaddy:BAAALAADCgcIBwAAAA==.',Sj='Sjeffer:BAAALAADCgQIBAAAAA==.',Sk='Skull:BAAALAADCgQIBAAAAA==.',Sm='Smutt:BAAALAAECgYICQAAAA==.',So='Sooncoldaxe:BAAALAAECgIIAgAAAA==.',Sy='Sylvanemrys:BAAALAADCggIEAAAAA==.',['Sé']='Sérgenda:BAAALAADCgYIBgABLAAFFAMIAwAKAAAAAQ==.',Ta='Taunteth:BAAALAAECgMIAwABLAAFFAUIDwAPAG4hAA==.',Th='Thiccism:BAAALAADCgcIDwAAAA==.Thieu:BAAALAAFFAIIAgABLAAFFAMIAwAKAAAAAQ==.',Ti='Tia:BAAALAAECgIIBAAAAA==.',To='Tonke:BAACLAAFFIEPAAIPAAUIbiHSAAD4AQAPAAUIbiHSAAD4AQAsAAQKgSAAAg8ACAiZJiwAAJMDAA8ACAiZJiwAAJMDAAAA.',Va='Vali:BAAALAAECgIIAgABLAAECgYICQAKAAAAAA==.Validush:BAAALAAECgEIAQAAAA==.Valiënne:BAAALAAECgYICQAAAA==.',Vo='Vood:BAAALAAECgUICwAAAA==.',Wa='Wanaja:BAAALAAECgYIBQAAAA==.',Wh='Whailor:BAAALAAECgMIAwAAAA==.',Xa='Xaeth:BAAALAAECgYIDAAAAA==.Xapo:BAAALAAECgYIBgAAAA==.',Xi='Xilra:BAABLAAECoEbAAMOAAgIXw18LQCoAQAOAAgIXw18LQCoAQAQAAgIogVpNABjAQAAAA==.',Yu='Yuki:BAAALAADCggIAgAAAA==.',['Yö']='Yönlutka:BAABLAAECoEVAAIQAAcIix5oEwBwAgAQAAcIix5oEwBwAgABLAAFFAQICQAGANsgAA==.',['Øl']='Øl:BAAALAAECgYICgAAAA==.',['Üb']='Übershep:BAAALAAECgQIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end