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
 local lookup = {'Warlock-Destruction','Shaman-Enhancement','Unknown-Unknown','Druid-Balance','Warrior-Fury','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','DeathKnight-Blood','Paladin-Retribution','Warlock-Demonology','Priest-Holy','Mage-Arcane','Priest-Shadow','Warlock-Affliction','Druid-Feral','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination','Shaman-Restoration',}; local provider = {region='EU',realm="Kor'gall",name='EU',type='weekly',zone=44,date='2025-09-06',data={Ae='Aen:BAAALAADCgcIDAAAAA==.',Ag='Agrave:BAAALAAECgQIBQAAAA==.',Al='Alexina:BAAALAAECgYICwABLAAFFAQIBQABADYOAA==.Alleriaa:BAAALAAECgYICgAAAA==.',Am='Amenethil:BAAALAAECgYIEwABLAAECggIGwACAF4aAA==.',An='Angren:BAAALAAECgcICgAAAA==.Anointedhunt:BAAALAAECggICAABLAAFFAIIAgADAAAAAA==.Anointedlock:BAAALAAFFAIIAgAAAA==.',Ao='Aon:BAAALAADCgEIAQAAAA==.',Ar='Arrowshooter:BAAALAADCgcIBwAAAA==.',As='Assmysterion:BAAALAAECgEIAQAAAA==.',Az='Azura:BAAALAAECgMIBQAAAA==.',Ba='Balanced:BAACLAAFFIEJAAIEAAUIHxrJAADUAQAEAAUIHxrJAADUAQAsAAQKgRgAAgQACAgiJgsEAD8DAAQACAgiJgsEAD8DAAAA.Bandit:BAAALAADCgMIAwAAAA==.',Be='Beasthuntard:BAAALAADCggIDwAAAA==.Bendu:BAAALAAECgcICAAAAA==.Beëf:BAAALAAECgYIDgAAAA==.',Bo='Borg:BAAALAAECgEIAQAAAA==.',Ca='Carmilla:BAABLAAECoEWAAIBAAgIwAc0PwB5AQABAAgIwAc0PwB5AQAAAA==.Cataract:BAAALAAECgYIBgABLAAECgYICQADAAAAAA==.',Ch='Chikie:BAAALAAECgQIAgAAAA==.',Co='Copulla:BAAALAAECgMIAQAAAA==.',Cr='Cradilyb:BAAALAAECgIIAgAAAA==.',Cz='Cz:BAAALAADCgYIBgAAAA==.',Da='Danii:BAACLAAFFIEIAAIFAAQI/xqAAgCAAQAFAAQI/xqAAgCAAQAsAAQKgRoAAgUACAhcI3wLAOwCAAUACAhcI3wLAOwCAAAA.',De='Deadeye:BAAALAADCgcICgAAAA==.Democh:BAAALAAECgEIAQAAAA==.Demon:BAAALAADCgQIBAAAAA==.Denego:BAAALAAECgEIAQAAAA==.Depletzen:BAAALAADCgEIAQABLAAFFAUICwAGAFESAA==.Devilmercy:BAAALAADCgMIAwAAAA==.',Di='Dimnjak:BAAALAAECgcICgAAAA==.',Dk='Dkracula:BAACLAAFFIEFAAMHAAMIDB3fAgDXAAAHAAIIziLfAgDXAAAIAAEIiBF4KQBJAAAsAAQKgRgAAwgACAgDJYkXAKMCAAgACAjBIokXAKMCAAcAAwh2JhQfAFIBAAAA.',Dr='Draconii:BAAALAADCgcIDAAAAA==.Dragmage:BAAALAADCgYIBgAAAA==.Dragonkinght:BAAALAAECgMIBQAAAA==.Drezz:BAAALAADCggICAAAAA==.',El='Elatrasa:BAAALAAECgYIDAAAAA==.',Em='Emigmatic:BAAALAADCgMIAwAAAA==.',En='Enkelbijter:BAAALAAECgQIBAAAAA==.Env:BAAALAAECgYICQAAAA==.',Ez='Ezomic:BAABLAAECoEbAAICAAgIXhpQBACNAgACAAgIXhpQBACNAgAAAA==.',Fa='Fazzbloom:BAACLAAFFIEHAAIJAAQIYRLNAQBNAQAJAAQIYRLNAQBNAQAsAAQKgRYAAwkACAh0GvQPAFsCAAkACAh0GvQPAFsCAAQAAwhmAwBRAIAAAAAA.Fazzmend:BAAALAADCgEIAQABLAAFFAQIBwAJAGESAA==.',Fe='Fedkat:BAAALAAECgUIBQAAAA==.',Fi='Fishwah:BAAALAAECgYIDAAAAA==.',Fo='Folkewest:BAAALAADCggICAABLAAECggIEgADAAAAAA==.',Fu='Furious:BAAALAADCgQIBAAAAA==.Fuskfanboy:BAAALAADCggICgAAAA==.',Ga='Gallivos:BAACLAAFFIEPAAIKAAUIgRuWAADdAQAKAAUIgRuWAADdAQAsAAQKgSAAAgoACAgkJYIBAE0DAAoACAgkJYIBAE0DAAAA.',Ge='Gedamak:BAAALAADCgMIAwAAAA==.',Gi='Girlfriend:BAACLAAFFIELAAIGAAUIURILAQCmAQAGAAUIURILAQCmAQAsAAQKgRoAAgYACAjLIZsDAPMCAAYACAjLIZsDAPMCAAAA.Girlypop:BAAALAADCgEIAQABLAAFFAUICwAGAFESAA==.',Go='Goal:BAAALAAECgYICwAAAA==.Govnaz:BAAALAAECgEIAQAAAA==.',Gr='Grimshot:BAAALAAECgMIAQAAAA==.Groma:BAAALAAECgYICAAAAA==.',Gu='Gurdora:BAACLAAFFIEPAAIGAAUIRhEVAQChAQAGAAUIRhEVAQChAQAsAAQKgSAAAgYACAjHGqsJAFQCAAYACAjHGqsJAFQCAAAA.',Ha='Hairybeauty:BAAALAADCgYIBgAAAA==.Hammerdin:BAAALAAECggIEQAAAA==.',He='Hellgate:BAAALAADCgcIBwAAAA==.',Hi='Hippiecow:BAAALAAECgYIEAAAAA==.',['Hó']='Hóli:BAABLAAECoEYAAILAAgItROHPwDXAQALAAgItROHPwDXAQAAAA==.',Ic='Icetea:BAAALAAECgEIAQAAAA==.Icyteens:BAAALAAECgcIDAAAAA==.',Il='Illamående:BAAALAADCgcIDQAAAA==.',In='Indgoa:BAAALAAECgEIAQAAAA==.',Is='Ispankmysuc:BAABLAAECoEVAAMBAAgIDR0KIgAfAgABAAgIDBgKIgAfAgAMAAMISiHRQADdAAAAAA==.',Ja='Jaythree:BAAALAAECgUIBQAAAA==.',Ju='Jutipumppu:BAAALAAECggIEgAAAA==.',Ka='Kanketo:BAAALAAECgYIBwAAAA==.',Ke='Kells:BAAALAAECgQIBQAAAA==.',Kp='Kpop:BAAALAAECgQIBAAAAA==.',Kr='Kratosgow:BAAALAADCggIEAABLAAECgcICgADAAAAAA==.Kriizz:BAAALAAECgcIEQAAAA==.Kryll:BAAALAAECgYICgAAAA==.',La='Larandir:BAAALAAECgIIAgAAAA==.Lazzam:BAAALAAECgMIAwAAAA==.',Le='Lesbotukka:BAABLAAECoEWAAINAAgIxR2nDACoAgANAAgIxR2nDACoAgAAAA==.',Ma='Maakari:BAAALAAECgcIEwAAAA==.Magepala:BAAALAADCggIFQAAAA==.Magicmario:BAAALAADCggICAAAAA==.Magners:BAAALAAECgUIBQAAAA==.Mallecc:BAAALAADCgMIAwAAAA==.Mambor:BAACLAAFFIELAAIOAAUIHR1YAQACAgAOAAUIHR1YAQACAgAsAAQKgSAAAg4ACAj6JFQDAFQDAA4ACAj6JFQDAFQDAAAA.Marzipan:BAAALAAECgQIBAABLAAFFAUICwAGAFESAA==.Matdudu:BAAALAADCggIDAABLAAECggIKAAPALIgAA==.Matpandemic:BAABLAAECoEoAAIPAAgIsiCRCwDQAgAPAAgIsiCRCwDQAgAAAA==.',Me='Mentalrob:BAAALAAECgYICgAAAA==.',Mo='Moelock:BAACLAAFFIELAAMBAAUIxxTEAgDLAQABAAUIxxTEAgDLAQAMAAII3AK5DAB4AAAsAAQKgSAABAEACAjcI+sEADoDAAEACAiiI+sEADoDAAwABgj6GicYANABABAABgiIDhkMAKUBAAAA.Mojomonsta:BAAALAAECgIIAwAAAA==.Monon:BAAALAADCgYICQAAAA==.Morpheuus:BAACLAAFFIEFAAIBAAQINg7HBABRAQABAAQINg7HBABRAQAsAAQKgSAAAgEACAjYI1QHABsDAAEACAjYI1QHABsDAAAA.',Nd='Nd:BAABLAAECoEVAAMJAAcItBpgGAAQAgAJAAcItBpgGAAQAgARAAMIywQhJQBlAAABLAAFFAMIBQADAAAAAA==.',No='Noah:BAABLAAECoEWAAMEAAgILxtnDgCOAgAEAAgILxtnDgCOAgAJAAMI7hc7UgDNAAAAAA==.',Ox='Oxytocine:BAAALAAECgMIAwAAAA==.',Pa='Pachénko:BAAALAADCgMIAwAAAA==.Pappismies:BAAALAAECggICAAAAA==.',Pi='Pizlo:BAAALAADCggICAAAAA==.',Pl='Plosbone:BAAALAADCgYIBgAAAA==.',Po='Poppis:BAABLAAECoEUAAISAAgIASAMBADOAgASAAgIASAMBADOAgAAAA==.',['Pá']='Pá:BAABLAAECoEWAAILAAgInR7YDwDnAgALAAgInR7YDwDnAgAAAA==.',Ra='Rakoro:BAABLAAECoEXAAITAAgI6ArxKQDPAQATAAgI6ArxKQDPAQAAAA==.',Re='Rekoh:BAAALAAECggIDwAAAA==.',['Rå']='Rågiryggen:BAABLAAECoEWAAIUAAcIPxJrHQDQAQAUAAcIPxJrHQDQAQAAAA==.',Sa='Sanin:BAAALAADCgUIBQAAAA==.Sappls:BAAALAADCgYIBgAAAA==.',Se='Seteth:BAACLAAFFIEOAAIVAAUIlxF8AQCAAQAVAAUIlxF8AQCAAQAsAAQKgSAAAxUACAi4ICkIAM8CABUACAi4ICkIAM8CABMABwgzEO0tALgBAAAA.',Sh='Shadowfly:BAAALAADCgcIBwAAAA==.Sheìk:BAAALAAECgMIBAAAAA==.Shiivar:BAAALAAECgYIDgAAAA==.Shiivva:BAAALAADCgMIAwAAAA==.',Si='Siner:BAAALAAECggICQAAAA==.',Sk='Skellyshelly:BAAALAAECggICAAAAA==.Skrømt:BAAALAAECgMIAwAAAA==.',Sl='Slag:BAAALAAECgcIEAAAAA==.',Sm='Smalltown:BAAALAAECggIDQAAAA==.',So='Sonofalìch:BAAALAADCggIEgAAAA==.',Su='Sulij:BAAALAADCggIDQAAAA==.Sunny:BAAALAAECggICAAAAA==.Sunný:BAAALAADCgQIBAAAAA==.',Sy='Syerae:BAAALAADCgcIBwAAAA==.Sylvanna:BAAALAADCgEIAQAAAA==.',Te='Tenebralis:BAAALAADCgcICAAAAA==.',Th='Theo:BAAALAADCgQIAwAAAA==.',Ti='Tinytony:BAAALAAECgQIBgAAAA==.',To='Touhutippa:BAAALAAECgUIBQABLAAECggIEgADAAAAAA==.',Tr='Trythedk:BAAALAADCggIGwAAAA==.Tråll:BAAALAADCgIIAgAAAA==.',['Tõ']='Tõne:BAAALAAECggIBwABLAAECggICAADAAAAAA==.',Va='Vallerie:BAAALAAECgYIDgABLAAFFAQIBQABADYOAA==.',Vi='Vicvinegar:BAAALAAECgYICQAAAA==.',We='Weesammy:BAAALAADCgUIBQAAAA==.Well:BAAALAAECgYIBwABLAAFFAUICQAEAB8aAA==.',Wh='Whoops:BAAALAAFFAMIBQAAAQ==.',Yu='Yubel:BAAALAADCgEIAQAAAA==.',Ze='Zeebraaka:BAAALAAECgcICgAAAA==.',Zh='Zhe:BAACLAAFFIEKAAIHAAUIYhYpAADcAQAHAAUIYhYpAADcAQAsAAQKgRoAAgcACAg0IwQCACsDAAcACAg0IwQCACsDAAAA.',Zo='Zoniya:BAAALAADCgIIAgAAAA==.',['Òh']='Òhmsen:BAAALAAECgUIBQAAAA==.',['Öö']='Ööh:BAAALAAECgcIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end