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
 local lookup = {'Mage-Arcane','Shaman-Restoration','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Havoc','DeathKnight-Blood','Monk-Windwalker','Warrior-Protection','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Hunter-BeastMastery','Priest-Holy','Priest-Discipline','Druid-Guardian',}; local provider = {region='EU',realm='Jaedenar',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ai='Aidana:BAAALAAECgYIDwAAAA==.',Al='Algra:BAAALAAECgcIBwAAAA==.',Ap='Appelmoes:BAAALAADCgcICAAAAA==.',Aq='Aquenthe:BAAALAAECgYIEAAAAA==.',Ar='Armena:BAAALAAECgUIBQAAAA==.Artus:BAAALAAECggICAAAAA==.Arwæn:BAABLAAECoEYAAIBAAYINx/7VADeAQABAAYINx/7VADeAQAAAA==.',As='Ascetka:BAAALAAECgMIBwAAAA==.Ashtoret:BAAALAAECgYIBgAAAA==.',Ba='Bambooze:BAAALAAECgYICAAAAA==.Bandum:BAABLAAECoEkAAICAAgIrBiRMQAiAgACAAgIrBiRMQAiAgAAAA==.',Bi='Billis:BAAALAAECgYIDAAAAA==.',Bl='Blademasteer:BAABLAAECoEYAAIDAAcIlxomZADsAQADAAcIlxomZADsAQAAAA==.Blankvault:BAABLAAECoEZAAIEAAcImBaLHgDBAQAEAAcImBaLHgDBAQAAAA==.',Ch='Charizard:BAAALAAECggIBwAAAA==.',Ci='Cichociemna:BAAALAADCgcIBwABLAAECgYICAAFAAAAAA==.',Cl='Clarisse:BAAALAADCggICAAAAA==.',Da='Danath:BAAALAAECgYIEAAAAA==.Darkmizuzer:BAABLAAECoEcAAIGAAgIQBjiHQBfAgAGAAgIQBjiHQBfAgAAAA==.',De='Deadlysword:BAAALAADCgYIBwAAAA==.Deanmartin:BAAALAADCggIFgAAAA==.Demonbeast:BAAALAAECgYIEQAAAA==.Destron:BAAALAAECgYIDAAAAA==.',Dr='Droolz:BAAALAADCggICAABLAAECggIJAACAKwYAA==.',Du='Dutiablo:BAAALAAECgcIDgAAAA==.',Ei='Eirene:BAAALAADCggIFgAAAA==.Eitelszymek:BAABLAAECoEVAAIHAAYIaSODVwARAgAHAAYIaSODVwARAgAAAA==.',['Eê']='Eêck:BAABLAAECoEWAAIIAAgIpwuOQgDGAQAIAAgIpwuOQgDGAQAAAA==.',Fa='Factory:BAAALAAECggIDgAAAA==.Fajniz:BAABLAAECoEVAAIJAAcIux56HABmAgAJAAcIux56HABmAgABLAAECgYIGAABADcfAA==.Fatty:BAAALAAECgcIBwAAAA==.',Fu='Fuegodesol:BAAALAADCgcIBwAAAA==.Furk:BAAALAAECgYICAAAAA==.',Gh='Ghostzero:BAAALAADCggIDwAAAA==.',Gr='Grason:BAAALAAECgEIAQAAAA==.',Ha='Hadess:BAABLAAECoEaAAIKAAYIuRUkfwCRAQAKAAYIuRUkfwCRAQAAAA==.',He='Healíum:BAAALAAECgYIDAAAAA==.Heligost:BAAALAAECgEIAQAAAA==.Henklord:BAAALAADCgYIBgAAAA==.Henklordz:BAAALAAECgQIBAAAAA==.Henkme:BAAALAADCgYIBgABLAAECgQIBAAFAAAAAA==.Hevi:BAAALAADCgMIAwAAAA==.',Ho='Hope:BAAALAAECgYIBgAAAA==.',['Hå']='Håkisbråkis:BAAALAAECgMIAwAAAA==.',Is='Isaacmooton:BAABLAAECoEeAAILAAgIqRpjDABWAgALAAgIqRpjDABWAgAAAA==.',Ja='Jabelea:BAAALAADCggIKQAAAA==.',Jl='Jlow:BAAALAAECgcIDwAAAA==.',Ju='Jurassic:BAAALAAECggIAQAAAA==.',Ka='Karrla:BAAALAAECgMIAwAAAA==.',Ke='Kebabrulle:BAAALAAECgYIBgAAAA==.',Le='Lebronjames:BAAALAADCgYIDAABLAADCggIDAAFAAAAAA==.Leifloket:BAAALAAECgUIBQAAAA==.',Li='Lightfoot:BAABLAAECoEYAAIMAAgI4hCkJQCaAQAMAAgI4hCkJQCaAQAAAA==.Lightswarden:BAAALAAECggICwAAAA==.Lilaria:BAAALAAECgcIDAAAAA==.Lillana:BAAALAAFFAEIAQAAAA==.',Lo='Loríana:BAAALAAFFAIIAgAAAA==.',Lu='Lurp:BAAALAAECgMIAwABLAAECgQIBAAFAAAAAA==.',['Lì']='Lìara:BAAALAADCggIGQAAAA==.',Me='Meatball:BAAALAAFFAIIAgAAAQ==.Mensotor:BAAALAADCgYIBgAAAA==.',Mi='Midanas:BAAALAADCgcIBwAAAA==.',Mo='Mootilator:BAABLAAECoEfAAMNAAcIPSSkCgDWAgANAAcIPSSkCgDWAgAOAAMI6g6HpgChAAAAAA==.Mordigian:BAAALAADCggIDgAAAA==.Morgan:BAAALAAECgEIAQAAAA==.Mothma:BAAALAADCggICAAAAA==.',Na='Naneunsanai:BAABLAAECoEWAAICAAYI6RyeRQDcAQACAAYI6RyeRQDcAQAAAA==.Natureless:BAAALAAECggICwAAAA==.',Ni='Ninjabossa:BAAALAAECgUIBwAAAA==.',['Nê']='Nêvêrcharge:BAAALAADCgQIBAABLAAECggIFgAIAKcLAA==.Nêvêrshot:BAAALAAECgQIBAABLAAECggIFgAIAKcLAA==.',Od='Oddy:BAABLAAECoEeAAICAAcIhyElGQCSAgACAAcIhyElGQCSAgAAAA==.Oddymonk:BAAALAAECgYIEAAAAA==.',Os='Os:BAAALAADCgYIBgAAAA==.',Pa='Paddypriest:BAAALAADCggIFwAAAA==.',Pi='Piesi:BAABLAAECoEYAAIDAAcIsQtKmQCCAQADAAcIsQtKmQCCAQAAAA==.',Pl='Plus:BAAALAAECgYIBgAAAA==.',Py='Pyrrhus:BAAALAAECgYIDwAAAA==.',Ra='Rafou:BAAALAAECgMIAwAAAA==.',Re='Reaperr:BAAALAADCgYIBgAAAA==.Redname:BAACLAAFFIELAAICAAMIrRw7DAD+AAACAAMIrRw7DAD+AAAsAAQKgR4AAgIACAjeGOMrADgCAAIACAjeGOMrADgCAAAA.',Rh='Rhante:BAAALAAECggIEgAAAA==.Rhantemage:BAAALAADCggICAAAAA==.Rhantepriest:BAAALAADCggICAAAAA==.Rhæ:BAAALAAECgMIBAABLAAECgcIEAAFAAAAAA==.',Ro='Roadhouse:BAAALAAFFAEIAQAAAA==.Rottnroll:BAAALAADCggICAABLAAECggIEAAFAAAAAA==.',Ru='Ruwie:BAAALAAECgYIDwAAAA==.',Sa='Saexi:BAAALAAECgYIEQAAAA==.Satanik:BAAALAAECggICAAAAA==.',Sh='Shamanmr:BAAALAAECgYICAAAAA==.Shamuu:BAABLAAECoEmAAICAAcIWBtSNQAUAgACAAcIWBtSNQAUAgAAAA==.Shining:BAAALAAECgYIDwAAAA==.Shárkie:BAABLAAECoEdAAIOAAgItxxKHgCmAgAOAAgItxxKHgCmAgAAAA==.',Si='Sikorsky:BAAALAAECggICQAAAA==.',Sk='Skaiplei:BAAALAADCgcICAAAAA==.Skairipa:BAAALAADCgYIBgAAAA==.Skycall:BAAALAAECgYIDQAAAA==.',Sn='Snizzlemynis:BAAALAAECgMIBgAAAA==.',Sp='Sparklightxx:BAABLAAECoEbAAIBAAgI6xslMABoAgABAAgI6xslMABoAgAAAA==.',Ss='Ss:BAABLAAECoEUAAMPAAcIABZ8HQDwAQAPAAcIABZ8HQDwAQAQAAEI6wjm1QAyAAABLAAFFAIICAARAFUcAA==.',St='Stigjuan:BAABLAAECoEkAAIHAAgICR0XJgCxAgAHAAgICR0XJgCxAgAAAA==.Stuartg:BAAALAAECggIEAAAAA==.',Sw='Sweetpain:BAAALAAECgUIBgABLAAECggIGAADAJcaAA==.',['Sé']='Sérenity:BAAALAADCggICAAAAA==.',Ti='Tiokommatvå:BAAALAAECgYIDQAAAA==.',Tr='Trollolol:BAAALAADCggIEAABLAAECgcIHwANAD0kAA==.Tropicielka:BAAALAAECgYICAAAAA==.',Um='Umbriel:BAAALAADCgcIBwAAAA==.',Va='Vaeren:BAAALAADCggIFQAAAA==.Varanis:BAAALAAECgYICAABLAAFFAIIBgAJAMAhAA==.',Ve='Versephone:BAAALAADCgUIBQAAAA==.',Vo='Vodka:BAAALAADCgUIBQAAAA==.Voidweaver:BAABLAAECoEUAAQSAAcI6xKuQwCdAQASAAcI6xKuQwCdAQAGAAQIrBTPaADEAAATAAEIEgIdOgAMAAAAAA==.',Vy='Vyshaan:BAAALAADCggICAAAAA==.',Wa='Watdfoxsay:BAAALAADCgcIBwABLAAECgcIHwANAD0kAA==.',We='Weeds:BAAALAADCgYICAAAAA==.',Wo='Workshop:BAAALAAECggICAAAAA==.',Xa='Xapia:BAAALAAECgYICQAAAA==.',Xe='Xerth:BAAALAADCggICwAAAA==.',Zo='Zolas:BAABLAAECoEUAAIUAAcIbyWoAgD/AgAUAAcIbyWoAgD/AgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end