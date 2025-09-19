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
 local lookup = {'DeathKnight-Frost','Monk-Brewmaster','Evoker-Devastation','Warlock-Demonology','Unknown-Unknown','Mage-Arcane','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Priest-Shadow','Warrior-Arms',}; local provider = {region='EU',realm='Spinebreaker',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ag='Agonyost:BAAALAADCgcIBwAAAA==.',Al='Aliveman:BAAALAAECgIIAgAAAA==.',An='Antideath:BAABLAAECoEWAAIBAAcIgRHTSwCsAQABAAcIgRHTSwCsAQAAAA==.',Ar='Aragos:BAAALAAECgYICwAAAA==.Arvesse:BAAALAADCgUIBQABLAAECgcIFgACANAkAA==.',As='Ashers:BAAALAADCggIGQAAAA==.Askkick:BAAALAADCgQIAwAAAA==.Astrayus:BAAALAADCggIFwAAAA==.',Au='Aurelion:BAABLAAECoEUAAIDAAcIgRGRHAC5AQADAAcIgRGRHAC5AQAAAA==.',Az='Azzy:BAAALAAECgYIBgAAAA==.',Ba='Baldemort:BAAALAAECgYIBwAAAA==.',Bl='Bleahz:BAAALAAECgYIEQAAAA==.',Br='Bragdrag:BAABLAAECoErAAIDAAgI1BsODgB2AgADAAgI1BsODgB2AgAAAA==.Bragrag:BAAALAAECgMIAwABLAAECggIKwADANQbAA==.',['Bê']='Bêêtlêjuîcee:BAAALAAECgYIDAAAAA==.',Ca='Calsidious:BAABLAAECoEZAAIEAAgIfBEEDwAgAgAEAAgIfBEEDwAgAgAAAA==.Capriestsun:BAAALAADCgcIBwAAAA==.Catnp:BAAALAADCggIEQABLAAECgcIFgACANAkAA==.',Ch='Chinazes:BAAALAAECgcICAAAAA==.Ché:BAAALAAECggIAgAAAA==.',Co='Colthas:BAAALAAECgYIEAAAAA==.',Cw='Cwis:BAAALAAECgUICgAAAA==.',Da='Darkmist:BAAALAADCgUIBQAAAA==.',De='Deathwísh:BAAALAAECggICAAAAA==.Deceiver:BAAALAAECgUICwAAAA==.Despar:BAAALAAECgIIAgAAAA==.Deus:BAAALAADCggIEAAAAA==.',Do='Doljin:BAAALAADCggICAABLAAECgYICgAFAAAAAA==.',Dr='Dracalis:BAAALAAECgYIEgAAAA==.',El='Eljonson:BAAALAAECgYICAAAAA==.',Ey='Eyfra:BAAALAAECgcIEgAAAA==.',Fa='Faldaith:BAAALAADCgcICQAAAA==.',Fe='Feetsniffa:BAAALAAECgYIBgAAAA==.Feldior:BAAALAAECgIIAgAAAA==.Felminia:BAAALAADCggIFwAAAA==.Femmefatale:BAAALAADCgYIBwAAAA==.',Fi='Fizzlebutt:BAAALAADCggICAABLAAECggICAAFAAAAAA==.',Fj='Fjuttjarn:BAAALAAECgYICAAAAA==.',Fl='Flamegrilled:BAAALAADCggIDQAAAA==.Flera:BAAALAAECgYICgAAAA==.Fluba:BAAALAADCgQIBAAAAA==.Flyba:BAAALAADCggIDgAAAA==.',Fo='Foxuta:BAAALAAECgMIBgAAAA==.',Fr='Fridge:BAAALAAECgYICAAAAA==.Frostpaw:BAAALAADCggIDwAAAA==.',Ga='Gar:BAAALAADCggIGAABLAAECgcIFgACANAkAA==.',Gn='Gnotker:BAAALAADCggICQAAAA==.',Go='Golddie:BAAALAADCgUICwAAAA==.Goyda:BAABLAAECoETAAIGAAgIVxLSKwAfAgAGAAgIVxLSKwAfAgAAAA==.',Ha='Haemozen:BAABLAAECoEWAAMHAAcIehyWCwAuAgAHAAcIehyWCwAuAgAIAAEIYQM+QAAeAAAAAA==.Hamomaki:BAAALAAECgIIAgAAAA==.',He='Healyoself:BAAALAADCgcIBwAAAA==.',Ho='Hoardor:BAAALAADCggIHQAAAA==.Honeyloops:BAAALAAECgQIBAAAAA==.',Hr='Hro:BAAALAAECgcIBwAAAA==.',In='Indicavus:BAAALAAECgQIBgAAAA==.',Is='Isukie:BAABLAAECoEWAAMJAAcIFBswKAAvAgAJAAcIFBswKAAvAgAKAAMIuxTaKwCOAAAAAA==.',Ja='Jarzarn:BAAALAADCgcIDgAAAA==.',Ki='Kihzame:BAABLAAECoEZAAILAAgIpR+PCADKAgALAAgIpR+PCADKAgAAAA==.',Ko='Kotn:BAAALAAECgQIBQAAAA==.',Ku='Kurotora:BAAALAAECgcIDAAAAA==.',La='Lail:BAABLAAECoEOAAIGAAcIlhuEJQBDAgAGAAcIlhuEJQBDAgAAAA==.',Li='Lich:BAABLAAECoEUAAIEAAcIiiDNBgCUAgAEAAcIiiDNBgCUAgAAAA==.',Lo='Longnuts:BAAALAADCgQIBQAAAA==.Lothbrock:BAAALAAECgQIBgAAAA==.',Ma='Mandy:BAAALAADCgcICwAAAA==.Mantaleni:BAAALAADCggIDwAAAA==.Marimtroll:BAAALAAECgMIAwAAAA==.Matt:BAAALAAECggICAAAAA==.Maximus:BAAALAADCgUIBQAAAA==.',Me='Mezaroth:BAABLAAECoEWAAIJAAcIyhl1KwAdAgAJAAcIyhl1KwAdAgAAAA==.',Mi='Mittomonk:BAAALAAECgYIBwAAAA==.',Mo='Moohamed:BAAALAADCgQIBAABLAAECgUICgAFAAAAAA==.',Na='Namira:BAAALAADCgcIBwAAAA==.',Ne='Neyzann:BAAALAADCggIEwABLAAECgcIFgACANAkAA==.',No='Nomercy:BAAALAAECgEIAQAAAA==.Noxim:BAAALAAECggIEgAAAA==.',On='Onlyfunzz:BAAALAAECgYICgAAAA==.',Os='Osmosis:BAAALAAECggIBAAAAA==.',Oz='Ozria:BAAALAAECgcIBwAAAA==.',Pa='Palandiox:BAAALAADCgcIBgAAAA==.',Pe='Pepsiicola:BAAALAADCggICgAAAA==.',Pi='Pirgendoff:BAAALAADCgIIAgAAAA==.',Po='Pokemonk:BAAALAAECgMIAwAAAA==.Potkermeta:BAAALAADCggIDgAAAA==.Potkner:BAAALAAECgYICAAAAA==.',Pu='Pumperpowell:BAAALAADCggIDwAAAA==.',Qu='Quote:BAAALAADCgcIBwAAAA==.',Ru='Ruanna:BAAALAAECgIIAgAAAA==.Rultan:BAAALAADCgEIAQAAAA==.',Ry='Ryssu:BAAALAAECgIIAgAAAA==.',Sa='Saincte:BAAALAADCggICgABLAAECgcIFgACANAkAA==.Samuei:BAABLAAECoEWAAICAAcI0CRTBADeAgACAAcI0CRTBADeAgAAAA==.Saxos:BAAALAAECgIIAgAAAA==.',Se='Sevverslut:BAAALAADCgIIAgAAAA==.',Si='Sinthya:BAAALAAECgQIBQAAAA==.Sivicarobni:BAAALAADCgIIAwABLAAECgMIAwAFAAAAAA==.',Sm='Smokedx:BAAALAADCgMIAwABLAAECgEIAgAFAAAAAA==.Smokei:BAAALAAECgEIAgAAAA==.Smokes:BAAALAADCgcIDwABLAAECgEIAgAFAAAAAA==.',Sn='Snowmistx:BAAALAADCggICwABLAAECgEIAgAFAAAAAA==.',So='Soihtu:BAABLAAECoEWAAIMAAcI3gbMNwBPAQAMAAcI3gbMNwBPAQAAAA==.',St='Stonewind:BAAALAAECgIIAgABLAAECgYICgAFAAAAAA==.',Sy='Sytas:BAAALAAECgIIAgAAAA==.',Ta='Tangsan:BAAALAAECgcIDAAAAA==.Tarawatem:BAAALAAECgYICAAAAA==.',Th='Thayweave:BAABLAAECoEWAAIGAAcIMx49IQBfAgAGAAcIMx49IQBfAgAAAA==.',Ti='Tim:BAAALAADCgYICQAAAA==.Tipzy:BAAALAADCggIFQAAAA==.',To='Torlon:BAAALAAECgYIEQAAAA==.',Un='Unhallowed:BAAALAAECgYICgAAAA==.',Va='Vareth:BAAALAAECggICAAAAA==.',Ve='Vexor:BAAALAAECgYICAAAAA==.',Vi='Vilxs:BAAALAADCggICQAAAA==.',Vo='Voleth:BAAALAADCggIGwAAAA==.',Wa='Wargrin:BAABLAAECoEZAAINAAgIFyTRAAA+AwANAAgIFyTRAAA+AwAAAA==.',Xi='Xinthos:BAAALAAECgYIEAAAAA==.',Ya='Yajirobe:BAAALAAECgYICgABLAAECgUICwAFAAAAAA==.',Zi='Zig:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end