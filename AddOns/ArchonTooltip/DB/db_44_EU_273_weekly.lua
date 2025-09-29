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
 local lookup = {'Shaman-Restoration','Shaman-Elemental','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Shadow','Priest-Discipline','Warrior-Protection','Warrior-Fury','Warrior-Arms','Paladin-Protection','Evoker-Devastation','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Frost','Druid-Balance','Rogue-Outlaw','Druid-Feral','Druid-Restoration','Monk-Brewmaster','Unknown-Unknown','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Hunter-Survival','DeathKnight-Unholy',}; local provider = {region='EU',realm='Chromaggus',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aarschmade:BAABLAAECoEmAAMBAAgIIRyfGQCPAgABAAgIIRyfGQCPAgACAAMIqwlMiwCeAAAAAA==.',Ai='Aine:BAAALAADCggIFwAAAA==.',Al='Alugrim:BAAALAADCggIKQABLAAECggIGQADALkLAA==.Alutard:BAABLAAECoEZAAIDAAgIuQsRUABsAQADAAgIuQsRUABsAQAAAA==.',An='Angryhippo:BAABLAAECoEeAAMEAAgIxiNXCwAhAwAEAAgIxiNXCwAhAwAFAAgIkgM0eADIAAAAAA==.Annanaran:BAAALAADCggIEgAAAA==.Antidote:BAAALAAECgYIDgABLAAFFAMIBwAGAMoSAA==.Antidøte:BAACLAAFFIEHAAIGAAMIyhI3DQDqAAAGAAMIyhI3DQDqAAAsAAQKgScAAwYACAjRIWwMAP8CAAYACAjRIWwMAP8CAAcAAQhtECEwADcAAAAA.',Ar='Aran:BAAALAADCggIDwAAAA==.Argo:BAAALAADCgMIAwAAAA==.Arkin:BAAALAADCggIDwAAAA==.',['Añ']='Añtidøte:BAAALAADCgcIBwABLAAFFAMIBwAGAMoSAA==.',Ba='Babywarrior:BAAALAADCggIEwABLAAECggIJgABAFAfAA==.Badwizard:BAAALAADCggIGQAAAA==.',Be='Beefwall:BAACLAAFFIEGAAMIAAIIDRx1DQCjAAAIAAIIDRx1DQCjAAAJAAII8Ql6JwCSAAAsAAQKgSoABAoACAh2HscGAHMCAAoACAieGccGAHMCAAkACAiVFG4yADECAAgACAg6HNEZACkCAAAA.Berit:BAAALAAECgcICgAAAA==.',Bi='Birduti:BAAALAADCggICAABLAAECgcIGwALANUkAA==.',Br='Brhamen:BAAALAAECgUICAAAAA==.Brian:BAABLAAECoEeAAIMAAcIQgnZMgBqAQAMAAcIQgnZMgBqAQAAAA==.Bruileri:BAAALAADCgYIBgAAAA==.',['Bì']='Bìrdutì:BAAALAAECgIIAgABLAAECgcIGwALANUkAA==.',['Bî']='Bîrdy:BAABLAAECoEbAAILAAcI1SStBgDvAgALAAcI1SStBgDvAgAAAA==.',Ca='Caroline:BAAALAAECgQIAwAAAA==.Cavanagh:BAAALAADCgUIBQAAAA==.',Ch='Ch:BAAALAAECgcIBwAAAA==.Chonky:BAAALAAECgMIAwAAAA==.Chromgrok:BAAALAADCggICAAAAA==.',Cl='Clef:BAABLAAECoEUAAICAAYI0g3LXwBdAQACAAYI0g3LXwBdAQAAAA==.',Da='Dabaan:BAABLAAECoEcAAINAAgIHBUNOgAbAgANAAgIHBUNOgAbAgAAAA==.',Dj='Djinozvqr:BAAALAADCgYIBgAAAA==.',Dr='Drah:BAAALAAECgEIAQAAAA==.Drifted:BAABLAAECoEVAAIOAAcIrx0iPwA1AgAOAAcIrx0iPwA1AgAAAA==.Druiden:BAAALAADCgcIDQAAAA==.Druidmeup:BAAALAADCggIEAAAAA==.',Du='Dudu:BAAALAAECgcIDQABLAAFFAIIBgAIAA0cAA==.',Ef='Effus:BAAALAADCggIDwAAAA==.',En='Ennorath:BAAALAADCggICAAAAA==.',Ep='Eponine:BAAALAAECgYIBgAAAA==.',Ev='Evi:BAAALAADCgYIBgAAAA==.',Ez='Ez:BAACLAAFFIEGAAIOAAIIORouHgCpAAAOAAIIORouHgCpAAAsAAQKgSAAAg4ACAhbHYsjAKsCAA4ACAhbHYsjAKsCAAAA.',Fi='Fiury:BAAALAAECgIIAgAAAA==.',Fl='Flootskaft:BAAALAAECgUICgAAAA==.',Fr='Freezeed:BAAALAAECgYIEAAAAA==.',Ga='Galaxís:BAAALAAECgUIBQAAAA==.Garr:BAABLAAECoEgAAIPAAgIKx2cLACVAgAPAAgIKx2cLACVAgAAAA==.Garrly:BAAALAADCgUIBQAAAA==.',Ge='Getskaft:BAAALAAECgUICAAAAA==.',Gr='Grizzla:BAAALAADCggIFgAAAA==.Grunk:BAAALAAECgcIDQAAAA==.',Ha='Halinalle:BAAALAAECgYIBgABLAAFFAMIBgACAGwXAA==.',Hi='Hibari:BAAALAAECgMIBgAAAA==.',Ho='Holycrapx:BAAALAADCggIFgAAAA==.Holyfans:BAAALAAECgUICgAAAA==.',Hr='Hreth:BAABLAAECoEaAAIOAAgIiR4jIAC9AgAOAAgIiR4jIAC9AgAAAA==.',Ir='Irillyth:BAAALAAECgYIDQAAAA==.',Ja='Jacksy:BAACLAAFFIEFAAIQAAMIbhWMCQD0AAAQAAMIbhWMCQD0AAAsAAQKgSoAAhAACAgPJIIGADgDABAACAgPJIIGADgDAAAA.',Ka='Kagerou:BAABLAAECoEuAAIRAAgIRiJmAQAgAwARAAgIRiJmAQAgAwAAAA==.Katze:BAAALAADCgcIBwAAAA==.',Ke='Keled:BAABLAAECoEjAAMSAAgIGRIGEwD3AQASAAgIGRIGEwD3AQATAAcIfRnaLgDvAQAAAA==.Kelm:BAAALAADCggIEAAAAA==.Kelpa:BAAALAADCggICAAAAA==.',Kh='Khalissa:BAAALAAECgcICgABLAAFFAMIBQABAOAWAA==.',Ki='Killzcritter:BAAALAAECgYICgABLAAECgcIGwALANUkAA==.',Kn='Knäckis:BAAALAADCgUIBQAAAA==.',Kt='Ktinovatis:BAAALAADCgYIBgABLAAFFAMIBwADAOYNAA==.',Ku='Kungbrew:BAABLAAECoEhAAIUAAgImR+uBwDNAgAUAAgImR+uBwDNAgAAAA==.Kungshift:BAAALAAECgIIAgABLAAECggIIQAUAJkfAA==.',['Kó']='Kónna:BAABLAAECoEZAAIQAAYIYBFbRABnAQAQAAYIYBFbRABnAQAAAA==.',['Kú']='Kúningas:BAAALAADCgYIBgAAAA==.',La='Laiev:BAAALAADCgYIBgABLAADCgcIBwAVAAAAAA==.Lanire:BAAALAAECgYICwAAAA==.',Le='Lechie:BAAALAAECgYIBgAAAA==.',Li='Lickmethin:BAAALAADCggIFgAAAA==.',Ma='Maggús:BAAALAADCgMIAgAAAA==.Maiku:BAAALAAECggIEAAAAA==.Maran:BAAALAADCgcIDgAAAA==.',Me='Medunka:BAAALAAECgYIEAAAAA==.Meozhi:BAABLAAECoEYAAIWAAgIyRuvEAByAgAWAAgIyRuvEAByAgAAAA==.',Mi='Mintietus:BAAALAAECgYICwAAAA==.',Mo='Morthred:BAABLAAECoEZAAIPAAgIFxYVRQBCAgAPAAgIFxYVRQBCAgAAAA==.Motax:BAAALAADCgYICAAAAA==.',Mu='Muffin:BAAALAADCggIEAAAAA==.Mundel:BAAALAAECgYIBgAAAA==.Mundela:BAABLAAECoEbAAIEAAgIDxQnYwCyAQAEAAgIDxQnYwCyAQAAAA==.',Ne='Neimi:BAAALAAECgYIBgAAAA==.Neolithic:BAAALAADCgcIBwAAAA==.',Ni='Nightfall:BAAALAADCgcIBwAAAA==.',Ny='Nymae:BAAALAADCgYIBgAAAA==.Nyxa:BAAALAADCggIGwAAAA==.Nyétheel:BAAALAADCggICAAAAA==.',Ol='Olipain:BAABLAAECoEdAAIJAAgIxhmQJwBrAgAJAAgIxhmQJwBrAgABLAAFFAYIDwAEAFMcAA==.',Pa='Pahis:BAAALAAECggIDgAAAA==.',Ph='Photios:BAAALAADCggIEAAAAA==.',Pi='Pigcatcher:BAAALAADCgcIBwAAAA==.',Pr='Primeval:BAAALAAECgMIAwAAAA==.',Py='Pyraethis:BAAALAAECgcIDQAAAA==.',Rh='Rhaenyra:BAABLAAECoErAAIPAAgIcCD5GgDkAgAPAAgIcCD5GgDkAgAAAA==.',Ri='Rieha:BAAALAADCggIEQAAAA==.',Ru='Rusk:BAAALAAECgEIAQAAAA==.',Sc='Scarab:BAABLAAECoEgAAMXAAcIPhZtIwDlAQAXAAcIIhRtIwDlAQAYAAYI+Q2pJAA5AQABLAAECggILAAZAEAdAA==.Scotsdragon:BAAALAAECgIIAgAAAA==.Scrbyy:BAAALAAECgcIDwAAAA==.Scrubbybub:BAAALAADCgcIBwABLAAECgcIDwAVAAAAAA==.',Sh='Shadowdodo:BAABLAAECoEkAAMPAAgIexiKaQDoAQAPAAcIdBaKaQDoAQAaAAQIHRqMLQA4AQAAAA==.Shadowmourne:BAAALAADCgUIBQAAAA==.Shadowravenn:BAAALAADCggICAAAAA==.Shakmas:BAAALAAECgcIEQAAAA==.Sherry:BAABLAAECoEoAAIOAAgIViHRFwDsAgAOAAgIViHRFwDsAgAAAA==.Shrewberry:BAAALAAECgEIAQABLAAECgcIDwAVAAAAAA==.Shyntal:BAAALAADCgYIBgAAAA==.',Si='Simon:BAAALAAECgEIAQAAAA==.',Sk='Skeye:BAAALAADCggICAAAAA==.',So='Soggz:BAAALAAECgYICQAAAA==.',Sp='Spanker:BAAALAAECgMIAwAAAA==.',St='Stormkeeper:BAABLAAECoEbAAMCAAgIpxNPLwAgAgACAAgIpxNPLwAgAgABAAIIBgio+gBFAAAAAA==.',Su='Suyu:BAAALAAECgYICwAAAA==.',Sw='Sweatyshaft:BAAALAAECgYICwAAAA==.',Ta='Taloniuk:BAAALAADCggICAAAAA==.',Te='Tep:BAAALAAECggICAAAAA==.',Ti='Timjanlove:BAAALAADCgYIBgAAAA==.',Vi='Viczapz:BAAALAADCgEIAQAAAA==.Viggeviral:BAAALAADCgYICAAAAA==.Vildvittra:BAAALAADCggIFgAAAA==.',Wi='Windpaw:BAAALAAECggIEwAAAA==.',Xe='Xelina:BAAALAADCgcIBwAAAA==.Xenir:BAAALAAECggICAAAAA==.',Xr='Xristodoulas:BAACLAAFFIEHAAIDAAMI5g2SEADfAAADAAMI5g2SEADfAAAsAAQKgSgAAgMACAjQH/4PAM4CAAMACAjQH/4PAM4CAAAA.',Yf='Yfy:BAAALAADCgEIAQAAAA==.',Za='Zaffiron:BAAALAAECgcIDwAAAA==.Zaytona:BAABLAAECoEUAAMCAAgI8g0hPwDVAQACAAgI8g0hPwDVAQABAAIIXgL0AwE0AAAAAA==.',Ze='Zeminéon:BAAALAAECgMIAwABLAAECggIEwAVAAAAAA==.',Zh='Zhamor:BAAALAAECggIDwABLAAECggIEwAVAAAAAA==.',Zu='Zuljazin:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end