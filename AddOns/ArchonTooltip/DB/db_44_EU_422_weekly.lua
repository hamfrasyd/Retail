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
 local lookup = {'Warrior-Protection','Warrior-Fury','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','Evoker-Preservation','DemonHunter-Havoc','Rogue-Subtlety','Shaman-Enhancement','DeathKnight-Blood','Priest-Shadow','Priest-Discipline','DemonHunter-Vengeance','Monk-Brewmaster','Evoker-Devastation','Mage-Frost','Shaman-Elemental','Paladin-Holy','Rogue-Assassination','Rogue-Outlaw','Druid-Restoration','DeathKnight-Frost','Mage-Fire','Mage-Arcane',}; local provider = {region='EU',realm='DieTodeskrallen',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ae='Aedhal:BAABLAAECoEiAAMBAAcIKBhIKgC1AQABAAcIKBhIKgC1AQACAAYIdgfumADuAAAAAA==.',Ai='Aithusa:BAAALAADCgcIDAABLAAECgYIBwADAAAAAA==.',Al='Allianz:BAAALAAECgcIBwAAAA==.',An='Andara:BAAALAAECgQIBgAAAA==.Annluca:BAAALAAECgYIEAAAAA==.',As='Asdrubeal:BAAALAAECgQIBQAAAA==.Ashleyowlzen:BAAALAAECggICQAAAA==.',Av='Avistrasza:BAAALAAECggIEwAAAA==.',Ay='Ayvah:BAAALAADCggICAAAAA==.',['Aú']='Aúron:BAAALAADCgUIBQAAAA==.',Be='Beebo:BAAALAAECgYIDQAAAA==.',Bh='Bheldir:BAAALAADCggICAAAAA==.',Bi='Billidan:BAAALAADCgYIBgAAAA==.Bingchilling:BAAALAAECgYICQAAAA==.',Bo='Bogenbert:BAACLAAFFIEJAAIEAAYIwhiaAgAWAgAEAAYIwhiaAgAWAgAsAAQKgRcAAgUABwi2HiEfAFYCAAUABwi2HiEfAFYCAAEsAAUUBwggAAQAKx8A.Bosheit:BAABLAAECoEmAAIGAAgI4RRIQQAFAgAGAAgI4RRIQQAFAgAAAA==.',Br='Bragnos:BAABLAAECoEbAAIHAAcI7hiiRwDeAQAHAAcI7hiiRwDeAQAAAA==.Brynjar:BAAALAADCgcIBwABLAAECgcIEgADAAAAAA==.Brynlock:BAAALAAECgUIBgABLAAECgcIEgADAAAAAA==.Brösel:BAAALAADCgYIBgAAAA==.',Ca='Caith:BAAALAADCggIBwAAAA==.Calvyin:BAAALAAECgMIAwAAAA==.Carlila:BAAALAAECgMIBAAAAA==.',Ch='Chengsung:BAAALAADCgUIBQAAAA==.',Ci='Ciranda:BAAALAADCgMIAwABLAAECgMIBAADAAAAAA==.Citrus:BAACLAAFFIEMAAIGAAUIdxI3DQCcAQAGAAUIdxI3DQCcAQAsAAQKgSIABAYACAiTH68pAHICAAYACAiTH68pAHICAAgABAiGFLtcAM4AAAkAAggVFIcpAIUAAAAA.',Co='Corbeo:BAAALAAECgYIBwABLAAECgcIGwAHAO4YAA==.',Cr='Crowley:BAABLAAECoEeAAQIAAcI9htLEgBNAgAIAAcI9htLEgBNAgAGAAcI8A2DaACEAQAJAAIIGArILwBiAAAAAA==.Cruxxy:BAABLAAECoEgAAIGAAcIBwfNggBAAQAGAAcIBwfNggBAAQAAAA==.',['Cá']='Cásandrá:BAAALAADCggIEAABLAAECgYIEAADAAAAAA==.',Da='Daoniyella:BAAALAAECgMIBAAAAA==.',De='Demonpavio:BAAALAADCgUIBQAAAA==.Deni:BAAALAAECgYIEgAAAA==.',Dk='Dkay:BAAALAAECgQIBAAAAA==.',Do='Dogofan:BAAALAAECgYICAABLAAECgcIGQAKAMAdAA==.Domas:BAABLAAECoEYAAILAAcIXhUeIAC+AQALAAcIXhUeIAC+AQAAAA==.',Dr='Drachenlord:BAACLAAFFIERAAIMAAUIIheqAwCnAQAMAAUIIheqAwCnAQAsAAQKgSwAAgwACAh/IcMEAOACAAwACAh/IcMEAOACAAAA.Droktar:BAAALAADCggICAAAAA==.Druijin:BAAALAADCgcIBwAAAA==.',Du='Dubbje:BAAALAADCggICAAAAA==.Durandall:BAAALAADCgcIBwAAAA==.',El='Elarith:BAAALAADCgIIAgAAAA==.Electrá:BAAALAAECggIEAAAAA==.',Ep='Epona:BAAALAAECgMIBAAAAA==.',Er='Erdbeermilch:BAAALAAECgEIAQAAAA==.',Ev='Evilious:BAAALAADCggIGwAAAA==.',Fa='Faith:BAAALAAECgUICAAAAA==.Faramis:BAAALAADCgUIBQABLAAECgYICQADAAAAAA==.',Fe='Fenixs:BAAALAAECgYIBgABLAAFFAUIDAAGAHcSAA==.',Fr='Fred:BAAALAADCggIEAAAAA==.',Fy='Fyrákk:BAAALAAECgIIAgABLAAECggIFAANAGoOAA==.',Ga='Gadranosch:BAAALAAECgYIBgAAAA==.Garandil:BAAALAAECgMIBgAAAA==.',Gu='Gumbold:BAABLAAECoEaAAIEAAYIwA/4wwD1AAAEAAYIwA/4wwD1AAAAAA==.',He='Her:BAAALAADCgcIDgABLAAFFAYIFgAOABUeAA==.',Ho='Horacyo:BAAALAADCggIHAAAAA==.',Hu='Huberta:BAAALAAECgIIAwAAAA==.',Il='Illidumm:BAAALAADCgQIAwAAAA==.',Is='Isipi:BAAALAAECgIIAwAAAA==.',Ja='Jamara:BAAALAADCgcIBwAAAA==.',Ju='Juma:BAABLAAECoEVAAIHAAcIUSMuFgCqAgAHAAcIUSMuFgCqAgABLAAECgcIGwAEADQgAA==.',Ka='Kaarjardosh:BAABLAAECoEbAAIPAAcIyBSwDgDYAQAPAAcIyBSwDgDYAQAAAA==.Katyparry:BAAALAAECggICAAAAA==.',Ke='Keragos:BAAALAADCgcIDQAAAA==.',Kh='Khartos:BAAALAADCggICAABLAAECgYIGQAQAHkeAA==.',Ko='Korihnas:BAABLAAECoEYAAIFAAcI9ROFOgC2AQAFAAcI9ROFOgC2AQAAAA==.Korwana:BAAALAAECgYIDAAAAA==.',Kr='Kratzuk:BAAALAADCggIEgAAAA==.Krautstampfa:BAAALAADCgYICgAAAA==.Krimal:BAAALAADCggICAAAAA==.Kriokan:BAAALAADCgcIGgAAAA==.',Ky='Kyaa:BAAALAAECgcIEwAAAA==.',La='Lantesh:BAAALAAECgEIAQAAAA==.',Le='Lealey:BAAALAAECgMIBAAAAA==.Leany:BAAALAAECgIIAgAAAA==.Leliel:BAAALAADCgYIEAAAAA==.Lennear:BAAALAAECgYIDwAAAA==.Lepina:BAAALAAECgcICwAAAA==.Leshia:BAAALAAFFAEIAQAAAA==.Letaro:BAAALAAECgMIBAAAAA==.Lethe:BAABLAAECoEVAAMRAAYIpRd+OAC/AQARAAYIpRd+OAC/AQASAAIIywwOKgBcAAAAAA==.',Li='Lianthor:BAAALAAECgYIBwAAAA==.Lilleskadi:BAAALAAECgIIAwAAAA==.',Lo='Lougrel:BAAALAADCgQIBAAAAA==.',Lu='Luphor:BAAALAADCggIDgAAAA==.Lusiella:BAABLAAECoEaAAISAAcIFSDiAwCGAgASAAcIFSDiAwCGAgAAAA==.',Ma='Malekki:BAABLAAECoEUAAIKAAcIdBG9ggC0AQAKAAcIdBG9ggC0AQAAAA==.Maliana:BAAALAAECgYIEAAAAA==.Malmuira:BAAALAAECgIIAgAAAA==.',Me='Melandorn:BAABLAAECoEnAAIBAAgIoxxdEACPAgABAAgIoxxdEACPAgAAAA==.Meothera:BAAALAADCggIHAAAAA==.',My='Mynamechris:BAAALAADCgUIDgAAAA==.',Na='Nantarion:BAABLAAECoEcAAITAAYIICJgEAAyAgATAAYIICJgEAAyAgAAAA==.',Ne='Neykplague:BAAALAAECggICAABLAAFFAYIDAAEAGcjAA==.',Ni='Nimloth:BAAALAAECgIIBAAAAA==.',Ny='Nycodhemus:BAAALAADCggIEAAAAA==.',Pe='Perothar:BAABLAAECoEZAAIUAAcIdxfOFADoAQAUAAcIdxfOFADoAQAAAA==.',Ph='Pharsa:BAAALAAECgUICQABLAAECgYICQADAAAAAA==.Phineya:BAAALAAECgIIAgAAAA==.',Pi='Pitaya:BAABLAAECoEbAAIVAAcIZSFrEACfAgAVAAcIZSFrEACfAgAAAA==.',Pu='Punchadin:BAAALAAECggICgAAAA==.',Pz='Pziko:BAAALAAECgQIBAAAAA==.',['Pú']='Púg:BAAALAAECgYICgAAAA==.',Re='Recktrex:BAAALAADCgUICgAAAA==.Reissohrab:BAAALAADCggICAAAAA==.Retrogun:BAAALAAECgEIAQAAAA==.Rextrex:BAAALAADCgUICQABLAAECgcIGwAHAO4YAA==.',Sc='Schmeckbert:BAAALAADCggICAAAAA==.',Se='Sephirón:BAAALAADCgEIAQAAAA==.Seryas:BAABLAAECoEpAAIRAAgI2B3aEwC6AgARAAgI2B3aEwC6AgAAAA==.Sesalia:BAAALAADCgcICwABLAAECgcIGwAHAO4YAA==.',Sh='Shroom:BAAALAAECgYIBgABLAAECggIHwAKANYPAA==.Shîkora:BAABLAAECoEaAAIWAAcIOxaDIwDfAQAWAAcIOxaDIwDfAQAAAA==.Shîzu:BAAALAADCgUIAgAAAA==.',Si='Simha:BAABLAAECoEhAAMHAAgIexn8LQA2AgAHAAgIexn8LQA2AgAXAAcIhAw8UgCVAQAAAA==.',Sl='Slytherìn:BAAALAAECgIIAgAAAA==.',Sp='Spectre:BAAALAAECggICAAAAA==.',Su='Sun:BAAALAAECggIAwAAAA==.Sundra:BAAALAAECgMIBAAAAA==.',Sy='Sythia:BAAALAAECgMIBAAAAA==.',Ta='Tael:BAAALAAECgUIDQAAAA==.Takamuh:BAABLAAECoEbAAIEAAcINCBvLwBeAgAEAAcINCBvLwBeAgAAAA==.Talir:BAAALAAECgIIAgAAAA==.Taro:BAAALAAECgUIBwAAAA==.Tayah:BAABLAAECoEaAAITAAcIxA7GJQBNAQATAAcIxA7GJQBNAQAAAA==.',Th='Thourngrel:BAAALAAECggICgAAAA==.Thràká:BAAALAAECgYIBAAAAA==.',Ti='Tihna:BAAALAADCgUIBQAAAA==.Tin:BAABLAAECoEfAAMKAAgI1g9UkQCZAQAKAAcIoA1UkQCZAQAYAAgI0wr/LwB9AQAAAA==.Tix:BAAALAADCgcIBwAAAA==.',To='Toroloco:BAAALAAECgUIBQAAAA==.',Tr='Trash:BAAALAAECgcIBwAAAA==.Trassari:BAAALAAECgIIAgAAAA==.Trauerweide:BAAALAADCgQIBAAAAA==.Trebizat:BAAALAAECgIIAQAAAA==.Trff:BAABLAAECoEbAAQOAAcIUBxcDQA5AgAOAAcI6xtcDQA5AgAZAAQIoBUbRAAfAQAaAAMIShK3EwDAAAAAAA==.Triformis:BAAALAADCggIGQAAAA==.',Ty='Tychus:BAAALAADCggICAABLAAFFAUIDAAGAHcSAA==.Tyksp:BAAALAADCggICQAAAA==.',['Tó']='Tólik:BAABLAAECoEbAAIKAAcIfA6sjgCeAQAKAAcIfA6sjgCeAQAAAA==.',Va='Vaenya:BAAALAAECgYICgAAAA==.',Ve='Vensallia:BAABLAAECoEdAAIbAAYIiBebTAB3AQAbAAYIiBebTAB3AQAAAA==.',Wi='Willfreed:BAAALAADCgQIBAAAAA==.',Wr='Wrenn:BAAALAADCgYIBgAAAA==.',Xa='Xarkon:BAABLAAECoEYAAIBAAgIchL7LgCXAQABAAgIchL7LgCXAQAAAA==.',Xe='Xeraii:BAAALAAECgEIAQABLAAECgIIAgADAAAAAA==.',Xi='Xilliana:BAAALAAECgMIBAAAAA==.',['Xé']='Xéron:BAABLAAFFIEFAAIcAAIIixfQOgCZAAAcAAIIixfQOgCZAAAAAA==.',Ya='Yarea:BAAALAADCgYIBgABLAAECgcIEwADAAAAAA==.',Ye='Yeferguson:BAABLAAECoEaAAIPAAgIcBCODwDIAQAPAAgIcBCODwDIAQAAAA==.',Yi='Yingisa:BAAALAADCgYIBgAAAA==.',Yo='Yo:BAABLAAECoEZAAMdAAcIGh9cBABHAgAdAAcI6hxcBABHAgAeAAYI+RpZXADPAQABLAAECggICgADAAAAAA==.',Yv='Yve:BAAALAAECgcICwAAAA==.',Zi='Zirconium:BAABLAAECoEpAAMIAAgIPCW6AQBaAwAIAAgIPCW6AQBaAwAGAAIIsh6IrgC1AAAAAA==.',Zl='Zlayton:BAAALAADCggICAAAAA==.',Zo='Zooka:BAAALAAECgIIAgABLAAECgcIGwAHAO4YAA==.',Zu='Zuala:BAAALAAECgcIEgAAAA==.',Zy='Zynos:BAAALAADCggIDgABLAAECgcIGwAHAO4YAA==.',['Zá']='Zára:BAAALAADCgIIAgAAAA==.',['Ás']='Ásúna:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end