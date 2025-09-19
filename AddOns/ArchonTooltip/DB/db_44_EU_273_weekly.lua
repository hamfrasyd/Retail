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
 local lookup = {'Priest-Shadow','Priest-Discipline','Warrior-Protection','Unknown-Unknown','Druid-Balance','Rogue-Outlaw','Warrior-Fury','DeathKnight-Frost','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','DemonHunter-Havoc','Priest-Holy',}; local provider = {region='EU',realm='Chromaggus',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aarschmade:BAAALAAECggIDwAAAA==.',Ai='Aine:BAAALAADCggIFwAAAA==.',Al='Alugrim:BAAALAADCggIDwAAAA==.Alutard:BAAALAAECgcIDQAAAA==.',An='Angryhippo:BAAALAAECggIEAAAAA==.Annanaran:BAAALAADCgYIBgAAAA==.Antidote:BAAALAADCggIDwABLAAECggIHAABAJoeAA==.Antidøte:BAABLAAECoEcAAMBAAgImh6TCwDQAgABAAgImh6TCwDQAgACAAEIbRChIgA1AAAAAA==.',Ar='Aran:BAAALAADCgcIBwAAAA==.Argo:BAAALAADCgMIAwAAAA==.Arkin:BAAALAADCggIDwAAAA==.',['Añ']='Añtidøte:BAAALAADCgcIBwABLAAECggIHAABAJoeAA==.',Ba='Badwizard:BAAALAADCggIGQAAAA==.',Be='Beefwall:BAABLAAECoEaAAIDAAgIOhxRDABPAgADAAgIOhxRDABPAgAAAA==.Berit:BAAALAAECgYICQAAAA==.',Bi='Birduti:BAAALAADCggICAABLAAECgMICgAEAAAAAA==.',Br='Brhamen:BAAALAADCggIEgAAAA==.Brian:BAAALAAECgcIEAAAAA==.Bruileri:BAAALAADCgYIBgAAAA==.',['Bì']='Bìrdutì:BAAALAADCgIIAgABLAAECgMICgAEAAAAAA==.',['Bî']='Bîrdy:BAAALAAECgMICgAAAA==.',Ca='Cavanagh:BAAALAADCgUIBQAAAA==.',Ch='Chonky:BAAALAADCggIEAAAAA==.',Cl='Clef:BAAALAAECgUIBwAAAA==.',Da='Dabaan:BAAALAAECgcIDQAAAA==.',Dr='Drifted:BAAALAAFFAIIAgAAAA==.Druiden:BAAALAADCgUIBgAAAA==.Druidmeup:BAAALAADCggICAAAAA==.',Du='Dudu:BAAALAAECgYICAABLAAECggIGgADADocAA==.',Ef='Effus:BAAALAADCggICwAAAA==.',Ez='Ez:BAAALAAFFAIIAgAAAA==.',Fi='Fiury:BAAALAADCgcIBwAAAA==.',Fl='Flootskaft:BAAALAADCggIDwAAAA==.',Fr='Freezeed:BAAALAAECgYIDgAAAA==.',Ga='Galaxís:BAAALAAECgUIBQAAAA==.Garr:BAAALAAECgcIEQAAAA==.',Gr='Grizzla:BAAALAADCggIDwAAAA==.Grunk:BAAALAAECgcIDQAAAA==.',Ha='Halinalle:BAAALAADCggICAAAAA==.',Hi='Hibari:BAAALAAECgMIAwAAAA==.',Ho='Holycrapx:BAAALAADCgcIDgAAAA==.Holyfans:BAAALAADCggIFQAAAA==.',Hr='Hreth:BAAALAAECgYIDAAAAA==.',Ir='Irillyth:BAAALAAECgEIAgAAAA==.',Ja='Jacksy:BAABLAAECoEfAAIFAAgIAyOxBgAMAwAFAAgIAyOxBgAMAwAAAA==.',Ka='Kagerou:BAABLAAECoETAAIGAAgIOhZVAwBcAgAGAAgIOhZVAwBcAgAAAA==.',Ke='Keled:BAAALAAECgYIEwAAAA==.Kelpa:BAAALAADCggICAAAAA==.',Ki='Killzcritter:BAAALAADCggIGAABLAAECgMICgAEAAAAAA==.',Kn='Knäckis:BAAALAADCgUIBQAAAA==.',Ku='Kungbrew:BAAALAAECgYIEQAAAA==.',['Kó']='Kónna:BAAALAAECgUICQAAAA==.',La='Lanire:BAAALAAECgUIBQAAAA==.',Le='Lechie:BAAALAADCggIEAAAAA==.',Li='Lickmethin:BAAALAADCgcICAAAAA==.',Ma='Maggús:BAAALAADCgMIAgAAAA==.Maran:BAAALAADCgcIBwAAAA==.',Me='Medunka:BAAALAAECgUIBAAAAA==.Meozhi:BAAALAAECgcIBwAAAA==.',Mi='Mintietus:BAAALAAECgIIAgAAAA==.',Mo='Morthred:BAAALAAECgYIDAAAAA==.Motax:BAAALAADCgYICAAAAA==.',Mu='Mundel:BAAALAAECgYIBgAAAA==.Mundela:BAAALAAECgcIDQAAAA==.',Ny='Nymae:BAAALAADCgYIBgAAAA==.Nyxa:BAAALAADCggICAAAAA==.Nyétheel:BAAALAADCggICAAAAA==.',Ol='Olipain:BAABLAAECoEVAAIHAAgIUBY0GABbAgAHAAgIUBY0GABbAgAAAA==.',Pa='Pahis:BAAALAAECggIDgAAAA==.',Pi='Pigcatcher:BAAALAADCgcIBwAAAA==.',Pr='Primeval:BAAALAAECgMIAwAAAA==.',Py='Pyraethis:BAAALAADCggICAAAAA==.',Rh='Rhaenyra:BAABLAAECoEcAAIIAAgIWx8tDwDiAgAIAAgIWx8tDwDiAgAAAA==.',Ri='Rieha:BAAALAADCgYIBQAAAA==.',Sc='Scarab:BAABLAAECoEcAAMJAAcIihURHADcAQAJAAcIbhMRHADcAQAKAAYI+Q3TEgBSAQAAAA==.Scrbyy:BAAALAAECgcIDwAAAA==.Scrubbybub:BAAALAADCgcIBwABLAAECgcIDwAEAAAAAA==.',Sh='Shadowdodo:BAABLAAECoEUAAMLAAYI5RflKADvAAAIAAQI+BSvhQD7AAALAAMIEBrlKADvAAAAAA==.Shadowravenn:BAAALAADCggICAAAAA==.Shakmas:BAAALAAECgcIEQAAAA==.Sherry:BAABLAAECoEYAAIMAAgIZh7TEADdAgAMAAgIZh7TEADdAgAAAA==.Shrewberry:BAAALAAECgEIAQABLAAECgcIDwAEAAAAAA==.',Si='Simon:BAAALAADCgcIDgAAAA==.',So='Soggz:BAAALAAECgEIAQAAAA==.',Sp='Spanker:BAAALAADCgEIAQAAAA==.',St='Stormkeeper:BAAALAAECgcIDQAAAA==.',Su='Suyu:BAAALAAECgYICwAAAA==.',Sw='Sweatyshaft:BAAALAADCgIIAgAAAA==.',Te='Tep:BAAALAAECggICAAAAA==.',Ti='Timjanlove:BAAALAADCgYIBgAAAA==.',Vi='Viczapz:BAAALAADCgEIAQAAAA==.Viggeviral:BAAALAADCgYICAAAAA==.Vildvittra:BAAALAADCgcICAAAAA==.',Wi='Windpaw:BAAALAAECggIEwAAAA==.',Xe='Xelina:BAAALAADCgcIBwAAAA==.Xenir:BAAALAAECgIIAgAAAA==.',Xr='Xristodoulas:BAABLAAECoEbAAINAAgIDx8eCwC7AgANAAgIDx8eCwC7AgAAAA==.',Yf='Yfy:BAAALAADCgEIAQAAAA==.',Za='Zaffiron:BAAALAAECgcIDwAAAA==.Zaytona:BAAALAAECgYIDQAAAA==.',Ze='Zeminéon:BAAALAAECgMIAwABLAAECggIEwAEAAAAAA==.',Zh='Zhamor:BAAALAAECggIDwABLAAECggIEwAEAAAAAA==.',Zu='Zuljazin:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end