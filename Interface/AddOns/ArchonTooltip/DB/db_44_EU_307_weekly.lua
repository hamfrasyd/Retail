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
 local lookup = {'Paladin-Retribution','Paladin-Protection','Warlock-Destruction','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Shaman-Enhancement','DeathKnight-Unholy','Druid-Balance','Evoker-Augmentation','Priest-Shadow','Warrior-Arms','Unknown-Unknown','Monk-Mistweaver','Paladin-Holy','DeathKnight-Frost','Druid-Restoration','DeathKnight-Blood','Hunter-BeastMastery','Monk-Windwalker','DemonHunter-Havoc','Warlock-Demonology','Monk-Brewmaster','Evoker-Preservation','Shaman-Restoration','Priest-Holy','Mage-Arcane','Warlock-Affliction','Druid-Feral','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','Rogue-Subtlety','Mage-Frost',}; local provider = {region='EU',realm="Kor'gall",name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abukhalil:BAAALAADCggIAwAAAA==.',Ae='Aen:BAAALAADCgcIDAAAAA==.',Ag='Agocalmin:BAAALAAECgQIBAABLAAECgcIGwABAKAfAA==.Agrave:BAAALAAECgcIEgAAAA==.',Al='Alexina:BAABLAAECoEYAAICAAcIHxImIwCaAQACAAcIHxImIwCaAQABLAAFFAYIDQADAAkWAA==.Alleriaa:BAABLAAECoEXAAIEAAcIwBafMwDRAQAEAAcIwBafMwDRAQAAAA==.',Am='Amenethil:BAABLAAECoEiAAMFAAgIVBqOLgBEAgAFAAcIbBuOLgBEAgAGAAgIpBUMJgDJAQABLAAFFAIIBQAHANUdAA==.',An='Angren:BAABLAAECoEZAAIBAAgIaxvsLACRAgABAAgIaxvsLACRAgAAAA==.Anointedhunt:BAAALAAFFAIIAgABLAAFFAYIEwAIAHkPAA==.Anointedlock:BAAALAAFFAIIAgABLAAFFAYIEwAIAHkPAA==.',Ao='Aon:BAAALAADCgEIAQAAAA==.',Ar='Arrowshooter:BAAALAADCgcIBwAAAA==.',As='Assmysterion:BAAALAAECgEIAQAAAA==.',Az='Azura:BAAALAAECgYIDwAAAA==.',Ba='Balanced:BAACLAAFFIESAAIJAAYIRSHrAABPAgAJAAYIRSHrAABPAgAsAAQKgRkAAgkACAgiJl4MAPACAAkACAgiJl4MAPACAAAA.Bandit:BAAALAADCgMIAwAAAA==.',Be='Beasthuntard:BAAALAADCggIDwAAAA==.Bendu:BAAALAAECggIEAAAAA==.Bentína:BAAALAAECgQIBAAAAA==.Beëf:BAAALAAECgYIDgAAAA==.',Bo='Borg:BAAALAAECgYIDAAAAA==.',Bu='Bunnyhunter:BAAALAAECggICAAAAA==.',Ca='Carmilla:BAABLAAECoEeAAIDAAgI/wtTWgCmAQADAAgI/wtTWgCmAQAAAA==.Cataract:BAAALAAECgYIBgABLAAFFAMIBQAKAJkCAA==.',Ch='Chikie:BAAALAAECggIDgAAAA==.Chrundle:BAAALAAECgcIBwAAAA==.',Co='Copulla:BAAALAAECggIBAAAAA==.',Cr='Cradilyb:BAAALAAECgIIAgABLAAECgYIFAALAKAcAA==.Crazymagory:BAAALAAECggIBgAAAA==.',Cz='Cz:BAAALAADCgYIBgAAAA==.',Da='Danii:BAACLAAFFIESAAMFAAYI5hjJBQDYAQAFAAUIGR3JBQDYAQAMAAEI6wP3BQBUAAAsAAQKgRwAAgUACAhcIzAcALQCAAUACAhcIzAcALQCAAAA.',De='Deadeye:BAAALAADCgcICgAAAA==.Decayé:BAAALAADCgQIBAAAAA==.Democh:BAAALAAECgEIAQABLAAECggIEAANAAAAAA==.Demon:BAAALAADCgQIBAAAAA==.Denego:BAAALAAECgEIAQAAAA==.Depletzen:BAAALAADCgEIAQABLAAFFAYIFAAOAAAUAA==.Devilmercy:BAAALAADCgMIAwAAAA==.',Di='Dimnjak:BAABLAAECoEWAAIPAAcI2RhIHQDzAQAPAAcI2RhIHQDzAQAAAA==.',Dk='Dkracula:BAACLAAFFIENAAMQAAYIAhqhBgDUAQAQAAUIuhihBgDUAQAIAAIIBCOYBgDPAAAsAAQKgScAAxAACAgnJq0BAIMDABAACAglJq0BAIMDAAgAAwh2JkQrAEcBAAAA.',Dr='Draconii:BAAALAADCgcIDQAAAA==.Dragmage:BAAALAADCgYIBgAAAA==.Dragonkinght:BAAALAAECgcIEAAAAA==.Drezz:BAAALAADCggICAAAAA==.',El='Elatrasa:BAAALAAECgYIEAAAAA==.Elexis:BAAALAAECgYIBwAAAA==.',En='Enkelbijter:BAAALAAECgUIBQAAAA==.Env:BAAALAAECgcICgABLAAFFAMIBQAKAJkCAA==.',Ep='Epz:BAAALAADCgcICAAAAA==.',Ez='Ezomic:BAACLAAFFIEFAAIHAAII1R2iAwCyAAAHAAII1R2iAwCyAAAsAAQKgTQAAgcACAiTIaACAA0DAAcACAiTIaACAA0DAAAA.',Fa='Fazzbloom:BAACLAAFFIEQAAIRAAYInRYpAgD1AQARAAYInRYpAgD1AQAsAAQKgRsAAxEACAjnH/oOALsCABEACAjnH/oOALsCAAkAAwhmA8d3AHQAAAAA.Fazzlink:BAAALAAECgUIBQABLAAFFAYIEAARAJ0WAA==.Fazzmend:BAAALAAECgYIBgABLAAFFAYIEAARAJ0WAA==.Fazzscale:BAAALAAECgYIAwABLAAFFAYIEAARAJ0WAA==.',Fe='Fedkat:BAAALAAECgUIBQAAAA==.',Fi='Fishwah:BAAALAAECgYIEgAAAA==.',Fo='Folkewest:BAAALAADCggICAABLAAECggIIQAQAHsdAA==.',Fr='Fredgrim:BAAALAADCggIDAAAAA==.',Fu='Furious:BAAALAAECgYIBwAAAA==.Fuskfanboy:BAAALAADCggICgAAAA==.',Ga='Gallivos:BAACLAAFFIEcAAISAAYI3iCaAABhAgASAAYI3iCaAABhAgAsAAQKgTAAAhIACAgNJr4AAHwDABIACAgNJr4AAHwDAAAA.',Ge='Gedamak:BAAALAADCgMIAwAAAA==.',Gi='Girlfriend:BAACLAAFFIEUAAIOAAYIABSaAQABAgAOAAYIABSaAQABAgAsAAQKgS4AAg4ACAjpI8QCADEDAA4ACAjpI8QCADEDAAAA.Girlypop:BAAALAADCgEIAQABLAAFFAYIFAAOAAAUAA==.',Gl='Glow:BAAALAAFFAIIAgABLAAFFAYIEgAJAEUhAA==.',Go='Goal:BAABLAAECoEXAAITAAYI6BeQZwCnAQATAAYI6BeQZwCnAQAAAA==.Gorgol:BAAALAAECgYICQAAAA==.Govnaz:BAAALAAECgUIBgAAAA==.',Gr='Grimshot:BAAALAAECggICQAAAA==.Groma:BAAALAAECgYIEgAAAA==.',Gu='Gurdora:BAACLAAFFIEcAAIOAAYIKBPaAQDyAQAOAAYIKBPaAQDyAQAsAAQKgS4AAw4ACAi/GywOAFgCAA4ACAi/GywOAFgCABQABghABos8APQAAAAA.',Ha='Hairybeauty:BAAALAADCgYIBgAAAA==.Hammerdin:BAABLAAECoEXAAIBAAcINxDSjQCYAQABAAcINxDSjQCYAQAAAA==.',He='Hellgate:BAAALAADCgcIBwAAAA==.',Hi='Hippiecow:BAABLAAECoEcAAIRAAgILhTLMADlAQARAAgILhTLMADlAQAAAA==.',['Hó']='Hóli:BAABLAAECoEkAAIBAAgIARfCRAA9AgABAAgIARfCRAA9AgAAAA==.',Ic='Icetea:BAAALAAECgEIAQABLAAECgYICAANAAAAAA==.Icyteens:BAAALAAECgcIEAAAAA==.',In='Indgoa:BAABLAAECoEVAAIVAAgIiCGREQATAwAVAAgIiCGREQATAwAAAA==.',Is='Ispankmysuc:BAACLAAFFIEIAAMDAAMIwxPSFgD3AAADAAMIwxPSFgD3AAAWAAIIAg/eEQCXAAAsAAQKgR0AAwMACAitIJAeAKwCAAMACAi2HpAeAKwCABYAAwhKIZ9aANAAAAAA.',Ja='Jaythree:BAAALAAECgYIDwABLAAFFAYICwAXAAgZAA==.',Ju='Jutipumppu:BAABLAAECoEhAAQQAAcIex3iPwBRAgAQAAcIex3iPwBRAgASAAYImgmhKQDcAAAIAAIIfxgBRQCBAAAAAA==.',Ka='Kajo:BAAALAADCggIDQAAAA==.Kanketo:BAAALAAECgYIBwAAAA==.',Ke='Kells:BAAALAAECgQIBQAAAA==.',Kp='Kpop:BAAALAAECgQIBAAAAA==.',Kr='Kratosgow:BAAALAAFFAIIBAABLAAFFAQIBgAYAGkGAA==.Kriizz:BAABLAAECoEgAAIZAAgI/hkVJQBVAgAZAAgI/hkVJQBVAgAAAA==.Kryll:BAAALAAECgcIEwAAAA==.',Ku='Kurgøn:BAAALAAFFAIIBAAAAA==.',La='Larandir:BAAALAAECgYIDgAAAA==.Lazzam:BAAALAAECgMICAAAAA==.',Le='Lesbotukka:BAABLAAECoEXAAIaAAgI9x2FFQCfAgAaAAgI9x2FFQCfAgAAAA==.',Ly='Lycanster:BAAALAADCggICQAAAA==.',Ma='Maakari:BAABLAAECoEiAAIbAAgIYhLkRQAQAgAbAAgIYhLkRQAQAgAAAA==.Magepala:BAAALAADCggIHAAAAA==.Magicmario:BAAALAADCggICAAAAA==.Magistríx:BAAALAAECgYICQAAAA==.Magners:BAAALAAECgYIBgAAAA==.Mallecc:BAAALAADCgMIAwAAAA==.Mambor:BAACLAAFFIEUAAIbAAYIMR7bAgA7AgAbAAYIMR7bAgA7AgAsAAQKgT8AAhsACAhPJiQCAHkDABsACAhPJiQCAHkDAAAA.Marzipan:BAAALAAFFAIIBAABLAAFFAYIFAAOAAAUAA==.Matdudu:BAAALAADCggIDAABLAAFFAYICwADAK0JAA==.Matpandemic:BAABLAAECoEoAAILAAgIsiDEFQCkAgALAAgIsiDEFQCkAgABLAAFFAYICwADAK0JAA==.Maxiie:BAAALAADCgcIBwAAAA==.',Mc='Mcpersreikä:BAAALAAECggICAABLAAECggIIQAQAHsdAA==.',Me='Mentalrob:BAABLAAECoEXAAMTAAcIdw0giQBeAQATAAcIWw0giQBeAQAEAAUI7wg/dQDTAAAAAA==.',Mo='Moelock:BAACLAAFFIESAAMDAAYIlxanBgAAAgADAAYIlxanBgAAAgAWAAII3AJuFwBvAAAsAAQKgSYABAMACAgQJAEKADcDAAMACAgQJAEKADcDABYABgj6GrcpAKoBABwABgiIDtoQAIcBAAAA.Mojomonsta:BAABLAAECoEWAAIRAAcIBSSCDADUAgARAAcIBSSCDADUAgAAAA==.Mommabeast:BAAALAADCggICAAAAA==.Monon:BAAALAAECgYIDQAAAA==.Morpheuus:BAACLAAFFIENAAIDAAYICRZqBgAGAgADAAYICRZqBgAGAgAsAAQKgSIAAgMACAjYI7UTAPMCAAMACAjYI7UTAPMCAAAA.',My='Mybad:BAAALAAECgQIBQAAAA==.',Na='Naamis:BAAALAADCggICAAAAA==.',Nd='Nd:BAABLAAECoEcAAMRAAcIXB2bIAA6AgARAAcIXB2bIAA6AgAdAAMIywQYOQBXAAABLAAFFAUIDQANAAAAAA==.',Ne='Neotreehug:BAAALAADCggICAAAAA==.',Ni='Nidaime:BAAALAADCgYIBgABLAAECggIGQABAGsbAA==.Nighthawkdk:BAAALAAECgMIAwAAAA==.',No='Noah:BAABLAAECoEjAAMJAAgIIBz5GQBgAgAJAAgIIBz5GQBgAgARAAQIXhngYwAgAQAAAA==.',On='Onlykisses:BAAALAADCggICAAAAA==.',Ox='Oxytocine:BAAALAAECgMIAwAAAA==.',Pa='Pachénko:BAAALAADCggICwAAAA==.Pappismies:BAAALAAECggICAABLAAECggICgANAAAAAA==.',Pi='Pizlo:BAAALAADCggICAAAAA==.',Pl='Plosbone:BAAALAADCgYIBgAAAA==.',Po='Poladin:BAAALAAECggICAABLAAFFAUIDQANAAAAAQ==.Poppis:BAACLAAFFIEHAAIeAAIIrBrvBgCfAAAeAAIIrBrvBgCfAAAsAAQKgRQAAh4ACAgBIJgIAKgCAB4ACAgBIJgIAKgCAAAA.',['Pá']='Pá:BAACLAAFFIEHAAIBAAMIbg+hDwDtAAABAAMIbg+hDwDtAAAsAAQKgSQAAgEACAj2IVwUAAwDAAEACAj2IVwUAAwDAAAA.',Ra='Rakoro:BAABLAAECoElAAIfAAgIgQ12QADPAQAfAAgIgQ12QADPAQAAAA==.Rakoza:BAAALAADCgYIBgAAAA==.',Re='Rekoh:BAAALAAECggIDwAAAA==.',Ro='Rookster:BAAALAADCggICAAAAA==.',['Rå']='Rågiryggen:BAABLAAECoEfAAMgAAgIvBO4HQAQAgAgAAgI2BK4HQAQAgAhAAcIuwyfGwCGAQAAAA==.',Sa='Salamilehmä:BAAALAAECggICgAAAA==.Sanin:BAAALAAECgEIAQAAAA==.Sappls:BAAALAADCgYIBgAAAA==.Saul:BAAALAADCggICAAAAA==.',Se='Seteth:BAACLAAFFIEZAAIZAAYIBhfNAgDhAQAZAAYIBhfNAgDhAQAsAAQKgS0AAxkACAgaIvQNAN0CABkACAgaIvQNAN0CAB8ABwjDEj9CAMcBAAAA.',Sh='Shadowfly:BAAALAAECgcIBwAAAA==.Shampi:BAAALAADCggICAAAAA==.Sheìk:BAAALAAECgMIBAAAAA==.Shiivar:BAAALAAECgYIEQAAAA==.Shiivva:BAAALAADCgMIAwAAAA==.',Si='Siner:BAAALAAECggIEAAAAA==.',Sk='Skellyshelly:BAABLAAECoEYAAIOAAgI7gcSKAAlAQAOAAgI7gcSKAAlAQAAAA==.Skrømt:BAAALAAECgMIAwAAAA==.',Sl='Slag:BAABLAAECoEcAAIIAAgIChw0DQBkAgAIAAgIChw0DQBkAgAAAA==.',Sm='Smalltown:BAAALAAECggIDgAAAA==.',So='Sonofalìch:BAAALAADCggIEgAAAA==.',Su='Sulij:BAAALAADCggIDQAAAA==.Sunny:BAAALAAECggICAAAAA==.Sunný:BAAALAAFFAIIAwAAAA==.',Sy='Syerae:BAAALAADCgcIBwAAAA==.Sylvanna:BAAALAADCgEIAQAAAA==.',Ta='Tanketsu:BAAALAAECgYIDAAAAA==.',Te='Tenebralis:BAAALAAECgIIAgAAAA==.',Th='Theo:BAAALAADCgQIAwAAAA==.',Ti='Tigran:BAAALAADCgUIBQAAAA==.Tigranh:BAAALAADCgcICAAAAA==.Tinytony:BAABLAAECoEZAAIiAAcIXyAZEQB1AgAiAAcIXyAZEQB1AgAAAA==.',To='Toastie:BAAALAADCggICAAAAA==.Tos:BAAALAADCgUIBQAAAA==.Touhutippa:BAAALAAECgUIBQABLAAECggIIQAQAHsdAA==.',Tr='Trul:BAAALAAECgMIAwAAAA==.Trythedk:BAAALAADCggIKgAAAA==.Tråll:BAAALAADCgIIAgAAAA==.',Tu='Tundra:BAAALAAECgQIBAAAAA==.',['Tõ']='Tõne:BAAALAAECggIBwABLAAECggICgANAAAAAA==.',Va='Vallerie:BAABLAAECoEeAAIaAAgIawyMRQCVAQAaAAgIawyMRQCVAQABLAAFFAYIDQADAAkWAA==.',Ve='Velifalafeli:BAAALAAECggICwAAAA==.',Vi='Vicvinegar:BAABLAAECoEcAAIXAAgIxB9tBgDoAgAXAAgIxB9tBgDoAgAAAA==.',Wa='Warthog:BAAALAADCggICAAAAA==.',We='Weesammy:BAAALAADCgUIBQAAAA==.Well:BAAALAAFFAIIAgABLAAFFAYIEgAJAEUhAA==.',Wh='Whym:BAAALAADCggICAAAAA==.',Yu='Yubel:BAAALAADCgEIAQAAAA==.',Ze='Zeebraaka:BAABLAAFFIEGAAIYAAQIaQZLBgAOAQAYAAQIaQZLBgAOAQAAAA==.',Zh='Zhe:BAACLAAFFIESAAIIAAUICBilAADZAQAIAAUICBilAADZAQAsAAQKgSoAAggACAj5JGsBAFgDAAgACAj5JGsBAFgDAAAA.',Zo='Zoniya:BAAALAADCgIIAgAAAA==.',['Äs']='Ästärtes:BAAALAAECgYIEQAAAA==.',['Òh']='Òhmsen:BAAALAAECgUICAABLAAFFAIIAgANAAAAAA==.',['Öö']='Ööh:BAAALAAECgcIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end