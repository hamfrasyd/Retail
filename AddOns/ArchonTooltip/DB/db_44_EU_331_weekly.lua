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
 local lookup = {'DeathKnight-Frost','Monk-Brewmaster','Evoker-Devastation','Paladin-Retribution','Hunter-BeastMastery','Hunter-Survival','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Havoc','Rogue-Assassination','Priest-Shadow','Priest-Holy','Priest-Discipline','Unknown-Unknown','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Unholy','Rogue-Subtlety','Druid-Balance','Warrior-Arms',}; local provider = {region='EU',realm='Spinebreaker',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ag='Agonyost:BAAALAADCgcIBwAAAA==.',Al='Aliveman:BAAALAAECgMICAAAAA==.',An='Antideath:BAABLAAECoEmAAIBAAgIjRP/YAD7AQABAAgIjRP/YAD7AQAAAA==.',Ar='Aragos:BAAALAAECgYICwAAAA==.Archilion:BAAALAAECgYIBgAAAA==.Arvesse:BAAALAADCgUIBQABLAAECgcIFgACANAkAA==.',As='Ashers:BAAALAADCggIKAAAAA==.Askkick:BAAALAADCgQIAwAAAA==.Asterius:BAAALAAECgIIAgAAAA==.Astrayus:BAAALAAECgMIBgAAAA==.',Au='Aurelion:BAABLAAECoEgAAIDAAgIJBGeIgDhAQADAAgIJBGeIgDhAQAAAA==.',Az='Azzy:BAAALAAECgcIEwAAAA==.',Ba='Baldemort:BAAALAAECgcIDgAAAA==.',Bi='Bigsnake:BAAALAADCgQIBAAAAA==.',Bl='Bleahz:BAABLAAECoEcAAIEAAYIPBkUdwDEAQAEAAYIPBkUdwDEAQAAAA==.',Br='Bragdrag:BAABLAAECoE5AAIDAAgINyCfCAD+AgADAAgINyCfCAD+AgAAAA==.Bragrag:BAAALAAECgMIAwABLAAECggIOQADADcgAA==.',['Bê']='Bêêtlêjuîcee:BAABLAAECoEWAAMFAAgI1xQGVADZAQAFAAgI1xQGVADZAQAGAAMIXBT3FgDMAAAAAA==.',Ca='Calculated:BAAALAAECggIBwAAAA==.Calsidious:BAACLAAFFIEFAAIHAAIIPQUVFQCJAAAHAAIIPQUVFQCJAAAsAAQKgSkAAgcACAjpEu4XABgCAAcACAjpEu4XABgCAAAA.Caltrop:BAAALAAECgMIAwAAAA==.Capriestsun:BAAALAADCgcIBwAAAA==.Catnp:BAAALAADCggIEQABLAAECgcIFgACANAkAA==.',Ch='Chinazes:BAAALAAECggIEQAAAA==.Chuckira:BAAALAAECgYIBgABLAAFFAUIDwAIAFMZAA==.Ché:BAAALAAECggIAgAAAA==.',Co='Colthas:BAABLAAECoEcAAMBAAYIKhk/cQDYAQABAAYIKhk/cQDYAQAJAAQINQ6VKwDGAAAAAA==.',Cw='Cwis:BAAALAAECgUICgAAAA==.',Da='Darkmist:BAAALAADCgUIBQAAAA==.Darlandm:BAAALAADCgIIAgAAAA==.',De='Deathwísh:BAAALAAECggICAAAAA==.Deceiver:BAABLAAECoEWAAIKAAYIpSN1MwBhAgAKAAYIpSN1MwBhAgAAAA==.Delaqua:BAAALAADCggICQAAAA==.Despar:BAAALAAECgMICAAAAA==.Deus:BAAALAAECgMIAwAAAA==.',Do='Doljin:BAAALAAECgYIEAABLAAECggILAALANIhAA==.',Dr='Dracalis:BAABLAAECoEcAAIDAAgI9w25JADQAQADAAgI9w25JADQAQAAAA==.',['Dä']='Därk:BAAALAAECgYICAAAAA==.',El='Eljonson:BAABLAAECoEaAAIEAAYIPSOkPgBQAgAEAAYIPSOkPgBQAgAAAA==.',Ev='Evi:BAAALAAECggICAAAAA==.',Ey='Eyfra:BAABLAAECoEgAAQMAAgIdxoqHQBmAgAMAAgIdxoqHQBmAgANAAUItRcFUQBpAQAOAAEIOROPLwA6AAAAAA==.',Fa='Faldaith:BAAALAADCgcICQAAAA==.',Fe='Feetsniffa:BAAALAAECgYIDAAAAA==.Feldior:BAAALAAECgIIBAAAAA==.Felminia:BAAALAAECgEIAQAAAA==.Femmefatale:BAAALAAECgYIBgAAAA==.',Fi='Fizzlebutt:BAAALAADCggICAABLAAECggIEgAPAAAAAA==.',Fj='Fjuttjarn:BAAALAAECgYIDgAAAA==.',Fl='Flamegrilled:BAAALAADCggIFAAAAA==.Flera:BAAALAAECgYIEAABLAAECggILAALANIhAA==.Fluba:BAAALAADCgQIBAAAAA==.Flyba:BAAALAADCggIDgAAAA==.',Fo='Foxuta:BAABLAAECoEUAAIQAAcIkAcbPgBMAQAQAAcIkAcbPgBMAQAAAA==.',Fr='Fridge:BAAALAAECgYIEAAAAA==.Frostpaw:BAAALAADCggIGQAAAA==.',Ga='Gar:BAAALAADCggIGAABLAAECgcIFgACANAkAA==.',Gn='Gnotker:BAAALAAECgYIBgAAAA==.',Go='Golddie:BAAALAADCgUICwAAAA==.Goyda:BAABLAAECoEmAAIRAAgIYBZ7NQBQAgARAAgIYBZ7NQBQAgAAAA==.',Gr='Grush:BAAALAAECgIIAgAAAA==.',Ha='Haemodecay:BAAALAADCgQIBgAAAA==.Haemoelement:BAAALAAECggICAAAAA==.Haemorhage:BAAALAAECgIIAgAAAA==.Haemozen:BAABLAAECoEYAAMSAAgIwhvEDQBdAgASAAgIwhvEDQBdAgATAAEIYQPSXAAcAAAAAA==.Haereticus:BAAALAADCggICAAAAA==.Hamomaki:BAAALAAECgIIAgAAAA==.Havòc:BAAALAADCggICAABLAAFFAMICQARALYJAA==.',He='Healyoself:BAAALAADCgcIBwAAAA==.',Ho='Hoardor:BAAALAAECgUIBgAAAA==.Honeyloops:BAAALAAECgQIBAAAAA==.Howly:BAAALAAECgIIAgABLAAECggIJgABAI0TAA==.',Hr='Hro:BAAALAAECgcIBwAAAA==.',Hu='Huntelar:BAAALAAECgYIBgAAAA==.',In='Indicavus:BAABLAAECoEUAAIHAAYINx4xGAAWAgAHAAYINx4xGAAWAgAAAA==.',Is='Isukie:BAABLAAECoEmAAMKAAgI8hvPLwBwAgAKAAgI8hvPLwBwAgAUAAMIuxQTRACDAAAAAA==.Isukio:BAAALAAECgIIAgABLAAECggIJgAKAPIbAA==.',Ja='Jaks:BAAALAADCgQIBAAAAA==.Jarzarn:BAAALAADCgcIDgAAAA==.',Ka='Kaidou:BAAALAADCgUIBQABLAAECgYIFgAKAKUjAA==.',Ki='Kihzame:BAABLAAECoElAAIVAAgIoSD8DgDVAgAVAAgIoSD8DgDVAgAAAA==.Kilineiram:BAAALAADCggICAABLAAECgMIAwAPAAAAAA==.Kirotricepsa:BAAALAADCgEIAQAAAA==.',Ko='Kotn:BAAALAAECgQIBQAAAA==.',Ku='Kurotora:BAAALAAECggIDgAAAA==.',La='Lail:BAABLAAECoEUAAIRAAgIKxusMgBdAgARAAgIKxusMgBdAgAAAA==.Lasoia:BAAALAAECgYIDAABLAAECgYIHAABACoZAA==.',Li='Lich:BAABLAAECoEkAAIHAAgI9CIUAwAwAwAHAAgI9CIUAwAwAwAAAA==.',Lo='Lockzz:BAAALAADCgcIBwAAAA==.Longnuts:BAAALAADCgQIBQAAAA==.Lothbrock:BAABLAAECoERAAMBAAYItRQ3jACkAQABAAYItRQ3jACkAQAWAAIIogvXSABoAAAAAA==.',Ma='Maidenbreak:BAAALAAECgEIAQAAAA==.Mandy:BAAALAADCgcICwAAAA==.Mantaleni:BAAALAAECgYICwAAAA==.Marcuss:BAAALAAECgYIBgAAAA==.Marimtroll:BAABLAAECoEXAAIXAAgIqhNVEQD3AQAXAAgIqhNVEQD3AQAAAA==.Matt:BAAALAAECggIEgAAAA==.Maximus:BAAALAADCgUIBQAAAA==.',Me='Mezaroth:BAABLAAECoEoAAIKAAgIFxprNwBRAgAKAAgIFxprNwBRAgAAAA==.',Mi='Mittomonk:BAAALAAECgYIBwAAAA==.Mizuko:BAAALAADCggIEAABLAAECgcIEwAPAAAAAA==.',Mo='Moohamed:BAAALAADCgQIBwABLAAECgUICgAPAAAAAA==.',My='Myrkul:BAAALAAECgYIBgAAAA==.',Na='Namira:BAAALAADCgcIBwAAAA==.',Ne='Nerfplease:BAAALAAECggIDwAAAA==.Neyzann:BAAALAADCggIEwABLAAECgcIFgACANAkAA==.',Ni='Niceshot:BAAALAAECggICAAAAA==.',No='Nocturnal:BAAALAADCggICAAAAA==.Nomercy:BAAALAAECgYICwAAAA==.Noméne:BAAALAADCggIDwAAAA==.Noxim:BAAALAAECggIEgAAAA==.',Np='Np:BAAALAAECgYIBgAAAA==.',Nu='Nutella:BAAALAAECgUIBQAAAA==.',['Né']='Nékrós:BAAALAAECgEIAQABLAAECggIAgAPAAAAAA==.',Od='Odyssos:BAAALAAECgYIDgAAAA==.',On='Onlyfunzz:BAAALAAECgYIDAAAAA==.',Os='Osmosis:BAAALAAECggIEgAAAA==.',Oz='Ozria:BAAALAAECgcIBwAAAA==.',Pa='Paladinse:BAAALAADCggICAABLAAECggIHwAYAI0bAA==.Palandiox:BAAALAAECgcIDAABLAAECggIIgAZAMYlAA==.',Pe='Pepsiicola:BAAALAAECgIIAgAAAA==.',Pi='Pirgendoff:BAAALAADCgIIAgAAAA==.',Po='Pokemonk:BAABLAAECoEXAAITAAgI2R5VCgDPAgATAAgI2R5VCgDPAgAAAA==.Potkermeta:BAAALAADCggIDgAAAA==.Potkner:BAAALAAECgYICAAAAA==.',Pr='Prkl:BAAALAAECgIIAgAAAA==.',Pu='Pumperpowell:BAAALAADCggIDwAAAA==.',Qu='Quote:BAAALAADCgcIBwAAAA==.',Rh='Rhaegal:BAAALAADCgYICAAAAA==.',Ru='Ruanna:BAAALAAECgMICAAAAA==.Rubberdubbie:BAAALAADCgcIBwAAAA==.Ruska:BAAALAAECgIIAgABLAAECggIJgAMAL4JAA==.',Ry='Ryssu:BAAALAAECgMICAAAAA==.',Sa='Saincte:BAAALAADCggICgABLAAECgcIFgACANAkAA==.Samuei:BAABLAAECoEWAAICAAcI0CSICAC4AgACAAcI0CSICAC4AgAAAA==.Saxos:BAAALAAECgIIAgAAAA==.',Se='Sevverslut:BAAALAADCgIIAgAAAA==.',Si='Silya:BAAALAADCgYIBgAAAA==.Sinthya:BAAALAAECgQIBQAAAA==.Sivicarobni:BAAALAADCgIIAwABLAAECggIFwAXAKoTAA==.',Sm='Smokedx:BAAALAADCgMIAwABLAAECgYIEwAPAAAAAA==.Smokei:BAAALAAECgYIEwAAAA==.Smokes:BAAALAAECgYICgABLAAECgYIEwAPAAAAAA==.',Sn='Snowmistx:BAAALAADCggICwABLAAECgYIEwAPAAAAAA==.Snowpala:BAAALAADCggICAABLAAECgYIEwAPAAAAAA==.',So='Soihtu:BAABLAAECoEmAAIMAAgIvgkqPQChAQAMAAgIvgkqPQChAQAAAA==.',Sp='Sparksprock:BAAALAADCgcIBwAAAA==.',St='Stoan:BAAALAADCgcIBwAAAA==.Stonewind:BAAALAAECgYICAABLAAECggILAALANIhAA==.',Sy='Sytas:BAAALAAECgYICQAAAA==.',Ta='Tango:BAAALAAECggICAAAAA==.Tangsan:BAABLAAECoEaAAIEAAcI+BapYgDwAQAEAAcI+BapYgDwAQAAAA==.Tarawatem:BAAALAAECgYICgAAAA==.',Th='Thayweave:BAABLAAECoElAAIRAAgISR4MIQCyAgARAAgISR4MIQCyAgAAAA==.',Ti='Tim:BAAALAADCgYIDwAAAA==.Tipzy:BAAALAADCggIFQAAAA==.',To='Toriel:BAAALAAECgMIAwAAAA==.Torlon:BAABLAAECoEhAAIJAAgIgBnODQA6AgAJAAgIgBnODQA6AgAAAA==.',Ty='Tyrios:BAAALAAECgYIBgABLAAECggIEgAPAAAAAA==.',['Tó']='Tóka:BAAALAAECgYIBgABLAAECggIHQAIAJgYAA==.',Um='Umerchik:BAAALAAECgEIAQAAAA==.',Un='Unhallowed:BAABLAAECoEaAAIBAAgIRB6oIgDAAgABAAgIRB6oIgDAAgAAAA==.',Va='Vareth:BAAALAAECggICAAAAA==.',Ve='Vexor:BAAALAAECgYIEwAAAA==.',Vi='Vilxs:BAAALAADCggIGAAAAA==.',Vo='Voleth:BAAALAADCggIJQABLAAECggIEAAPAAAAAA==.',Wa='Wargrin:BAABLAAECoEiAAIZAAgIxiWWAABzAwAZAAgIxiWWAABzAwAAAA==.',Xi='Xinthos:BAABLAAECoEfAAIFAAgIPx2FIQCVAgAFAAgIPx2FIQCVAgAAAA==.',Ya='Yajirobe:BAABLAAECoEWAAITAAgIPRxFDACwAgATAAgIPRxFDACwAgABLAAECgYIFgAKAKUjAA==.',Zi='Zig:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end