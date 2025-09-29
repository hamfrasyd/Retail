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
 local lookup = {'Warlock-Destruction','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','Mage-Arcane','Warlock-Demonology','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','Priest-Discipline','Hunter-Survival',}; local provider = {region='EU',realm='Haomarush',name='EU',type='weekly',zone=44,date='2025-09-22',data={Am='Amberleaf:BAAALAAECgcIDQABLAAECgcIHwABAJgcAA==.',An='Anshe:BAAALAADCgUIBQAAAA==.',Au='Aubin:BAAALAAECgUIDQABLAAECgcIHwABAJgcAA==.',Ba='Bambus:BAAALAAECgQIBgABLAAFFAIIBQACAJwNAA==.Bassem:BAAALAADCgcICAAAAA==.',Be='Bellátrix:BAABLAAECoEiAAMDAAcIAiDnJwB1AgADAAcI3R/nJwB1AgAEAAcIPhhGMwDTAQAAAA==.',Bi='Bishie:BAAALAADCgYIBwAAAA==.',Bl='Bloodthirsty:BAABLAAECoEgAAIFAAgI3CSiBgBTAwAFAAgI3CSiBgBTAwAAAA==.',Bo='Bolatorsk:BAAALAAECgYIBgAAAA==.Boombulance:BAAALAADCggIHwAAAA==.Bowbeforeme:BAABLAAECoEXAAIGAAcIjw4dlACMAQAGAAcIjw4dlACMAQAAAA==.',Bu='Bulgarche:BAAALAAECgYIDQABLAAECgcIHgAGAGAaAA==.Burly:BAAALAADCgYIBgAAAA==.',Ca='Camilla:BAAALAAECgMIBwABLAAECggIIQAHAAAAAQ==.',Ce='Cersei:BAAALAAECgMIAwAAAA==.',Ch='Changeez:BAAALAADCgEIAQAAAA==.Churcmaster:BAAALAAECgcIEQAAAA==.',Co='Commodus:BAAALAAECgMIBAABLAAECgcIFQAIAGUZAA==.',Da='Daddyx:BAAALAAECgYIDQAAAA==.Dazdingo:BAAALAAECggIDgAAAA==.',Di='Diablolich:BAAALAADCggIDgAAAA==.',Do='Dolo:BAAALAAECgIIAgAAAA==.Doloress:BAABLAAECoEVAAIIAAcIZRnaBwAqAgAIAAcIZRnaBwAqAgAAAA==.',Dr='Drfox:BAAALAAECgMIBgAAAA==.Drjung:BAAALAADCggICAAAAA==.Drogona:BAAALAAECgYIEwABLAAECgcIHwABAJgcAA==.Drud:BAAALAADCggIDwAAAA==.Druitara:BAAALAAECgQIBQAAAA==.',Eb='Ebonic:BAAALAAECgYIDgAAAA==.',Em='Em:BAAALAAECgEIAQAAAA==.Emy:BAAALAAECgMIAwAAAA==.',Ex='Exodia:BAAALAAECgEIAQABLAAECggIJQAJAD4cAA==.',Fr='Freaknique:BAAALAADCggIFAAAAA==.Fredrik:BAAALAAECgYIBgAAAA==.',['Fä']='Fäbojäntan:BAAALAADCggICAAAAA==.',Ha='Harleyx:BAAALAAECggICAAAAA==.Harleyy:BAAALAAECggIEAAAAA==.Havas:BAAALAADCgcICwAAAA==.Hazkim:BAAALAAECgYIDgABLAAECgcIHwABAJgcAA==.',Ho='Hobbitvanda:BAAALAADCggIDgAAAA==.Hoothor:BAAALAADCggICAAAAA==.',Id='Idune:BAAALAADCggIEwAAAA==.',Il='Illidüne:BAAALAADCgcIDwAAAA==.',Ir='Irenésnusk:BAAALAADCggICQAAAA==.',Jo='Jolo:BAAALAAECgMIAwAAAA==.Jolobob:BAAALAAECgIIAgABLAAECgMIAwAHAAAAAA==.',Ka='Kaunis:BAAALAAECgMIBAABLAAECggIIQAHAAAAAQ==.',Kr='Kranium:BAAALAADCggICAABLAAECgYIDgAHAAAAAA==.Krexen:BAAALAADCgIIAgAAAA==.',Ku='Kungfumoocow:BAAALAAFFAEIAQAAAA==.',La='Larch:BAAALAADCggIFAAAAA==.Lasaruz:BAAALAAECgMIAwAAAA==.',Le='Leifgw:BAAALAADCggIBgAAAA==.',Lo='Locksix:BAABLAAECoEfAAMBAAcImBwrNgAtAgABAAcI0hsrNgAtAgAKAAYImhR3MgCAAQAAAA==.Loladin:BAAALAAECgMIAwAAAA==.',Ma='Maivin:BAAALAAECgYIEgAAAA==.Makaveliz:BAAALAADCgcIBwAAAA==.Makavelli:BAAALAAECgYIEwAAAA==.Marianka:BAABLAAECoEfAAICAAcI2xmZKQAdAgACAAcI2xmZKQAdAgAAAA==.',Mi='Mialei:BAABLAAECoEVAAIGAAYIERjAkQCQAQAGAAYIERjAkQCQAQAAAA==.',Mo='Mogwai:BAAALAADCggICAAAAA==.',Ne='Nen:BAABLAAECoEfAAMLAAcIlRN2agC9AQALAAcIlRN2agC9AQAMAAEIaAjEWQAkAAAAAA==.',Ni='Nightingale:BAAALAAECgUIBwAAAA==.',Nn='Nnyco:BAABLAAECoEjAAINAAcIYiMwBwDKAgANAAcIYiMwBwDKAgAAAA==.',Oo='Oombulance:BAAALAADCggIHwAAAA==.',Pa='Pangu:BAAALAADCgYICQAAAA==.',Po='Pontikitsa:BAABLAAECoEaAAMOAAcIJyFRFABAAgAOAAYIQCNRFABAAgAGAAcIpRC/hwCjAQAAAA==.',Pr='Procne:BAABLAAECoEWAAIPAAgIyBn7LQDzAQAPAAgIyBn7LQDzAQAAAA==.',Qa='Qatesh:BAAALAAECgYIDQAAAA==.',Ra='Ragnaz:BAAALAAECgYICgAAAA==.Rashomon:BAAALAAECgYIDQAAAA==.',Re='Remoh:BAAALAAECgMIAwAAAA==.',Ro='Rottenskull:BAAALAAECgYIDgAAAA==.',Sa='Saaconis:BAAALAAECgEIAQAAAA==.Salac:BAABLAAECoEjAAMQAAcI1xw4JwBOAgAQAAcI1xw4JwBOAgARAAQIcBjaowDxAAAAAA==.',Sh='Shalyir:BAACLAAFFIEFAAISAAII9xt/DgCwAAASAAII9xt/DgCwAAAsAAQKgRcAAhIACAj3G64PAJkCABIACAj3G64PAJkCAAAA.Shivalry:BAABLAAECoEgAAMTAAcIjxrYEQDwAQATAAcIhhfYEQDwAQASAAYIkhleLwCZAQAAAA==.Showtime:BAAALAADCggICAAAAA==.',Si='Sickomode:BAAALAAECgcIEgAAAA==.Silly:BAACLAAFFIEHAAICAAMIuhX8DQDwAAACAAMIuhX8DQDwAAAsAAQKgScAAwIACAgqIHsPANMCAAIACAgqIHsPANMCABQAAgj4FhQkAIAAAAEsAAQKCAgVABUADiMA.Sinistru:BAABLAAECoEaAAISAAcIghAqKADGAQASAAcIghAqKADGAQAAAA==.',Ta='Tali:BAAALAAECgYIBgAAAA==.',Te='Tessuwan:BAACLAAFFIEIAAIQAAIILiB0EwDDAAAQAAIILiB0EwDDAAAsAAQKgRoAAhAACAh9GwIXAL8CABAACAh9GwIXAL8CAAAA.',Th='Thilandras:BAAALAADCggIEAAAAA==.Thorn:BAAALAAECggICAAAAA==.',To='Totes:BAABLAAECoEcAAMQAAcIDQgnYwBRAQAQAAcIDQgnYwBRAQARAAYIfwW4xwCtAAAAAA==.',Tr='Tru:BAAALAAECgYIBgABLAAFFAMIBwARACYTAA==.',Tu='Tufnica:BAAALAADCggICAAAAA==.',Us='Useless:BAABLAAECoEWAAIRAAcI9hrCMgAeAgARAAcI9hrCMgAeAgAAAA==.',Vo='Voleth:BAAALAAECgUIBQABLAAECggIEAAHAAAAAA==.',Vy='Vyraleon:BAAALAADCgYIBgAAAA==.',We='Wespid:BAAALAAECgYIDwAAAA==.',Xi='Xibet:BAAALAAECgMIAwAAAA==.',Za='Zagaan:BAAALAAECgYIEwABLAAECgcIHwABAJgcAA==.Zalamn:BAAALAAECgYIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end