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
 local lookup = {'Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Mage-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Warlock-Destruction','Druid-Balance','Rogue-Outlaw','Rogue-Assassination','Druid-Restoration','Paladin-Protection','DeathKnight-Frost','Priest-Shadow','Warlock-Demonology','Priest-Holy','Shaman-Enhancement','DemonHunter-Havoc','Warrior-Fury','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','Shaman-Elemental','DemonHunter-Vengeance','Druid-Feral','Monk-Brewmaster','Warrior-Protection',}; local provider = {region='EU',realm='Nefarian',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ag='Agnetá:BAAALAAECgYIEAAAAA==.',Al='Alexiam:BAAALAADCgYIBgAAAA==.Alexis:BAAALAADCgcIEwAAAA==.Allandria:BAAALAADCggICAAAAA==.',An='Andôkái:BAAALAAECgcIEwAAAA==.Angelwings:BAABLAAECoEWAAMBAAYIwAx5uwBOAQABAAYIwAx5uwBOAQACAAYIKglFRAAMAQAAAA==.Antikite:BAAALAADCgYIBwAAAA==.',Ar='Arathena:BAAALAADCgQIBAABLAAECggIFwABAAYfAA==.Arcticlight:BAAALAAECgYIDQAAAA==.',As='Aslanis:BAAALAADCgUIBQAAAA==.',At='Atrium:BAAALAAECggIEgAAAA==.',Ay='Aypeax:BAAALAADCgcIBwAAAA==.',Ba='Ballinion:BAAALAAECgQIBAAAAA==.Bastosch:BAAALAAECgQIBgAAAA==.Batumi:BAABLAAECoEeAAIDAAcIhh1sKwBBAgADAAcIhh1sKwBBAgAAAA==.',Be='Beltron:BAAALAAECgQIBQAAAA==.',Bl='Blademonk:BAAALAAECgQIBAAAAA==.Bliamlekaddz:BAAALAAECgcIEgAAAA==.Blondy:BAAALAADCggICAAAAA==.Bláckwidôw:BAAALAADCggIDQABLAAECggIOgAEAHAiAA==.',Bo='Bogenbabsi:BAAALAAECgYIBwAAAA==.',Br='Brandolin:BAAALAAECgEIAQAAAA==.',Ch='Chickenwings:BAAALAADCgQIBQAAAA==.',Cm='Cmptrsayno:BAABLAAECoEXAAMFAAYIGCJsPQAqAgAFAAYIGCJsPQAqAgAGAAEI+RKYsgAtAAAAAA==.',Cr='Creativeone:BAAALAAECgYIEgAAAA==.Crosher:BAAALAADCggICAAAAA==.Cruelty:BAAALAAECgYIDAAAAA==.',Da='Daareal:BAAALAAECgYIDwAAAA==.Dagobärt:BAAALAADCgMIAwABLAAECggIDAAHAAAAAA==.Dante:BAABLAAECoEXAAIBAAgI+hwgNgBzAgABAAgI+hwgNgBzAgAAAA==.Darkwhitcher:BAAALAAECgYIDAAAAA==.',De='Deadsouls:BAABLAAECoEcAAIIAAgIoxyNHgCyAgAIAAgIoxyNHgCyAgAAAA==.Dembek:BAAALAADCgcIBwAAAA==.Dermeli:BAAALAAECgYIDAABLAAECgYIGgAFAMIeAA==.Devanas:BAAALAAECgYIEAAAAA==.',Di='Disturbed:BAABLAAECoEdAAIJAAcIKx7KHwA3AgAJAAcIKx7KHwA3AgAAAA==.',Do='Dotzilla:BAAALAADCgYIBgAAAA==.',Dr='Drezar:BAAALAAECgYIBgAAAA==.',Du='Duduworg:BAAALAADCgcICwAAAA==.',Ef='Effemvier:BAAALAADCgcICwABLAAECggIHAAIAKMcAA==.',El='Elesh:BAAALAAECggICAABLAAECggIHQABADMgAA==.Ellroy:BAABLAAECoEoAAIKAAgInRtRBQBSAgAKAAgInRtRBQBSAgAAAA==.Elonías:BAAALAAECgIIAgAAAA==.Elyndris:BAAALAADCggICAAAAA==.',En='Enelion:BAAALAADCggIFQAAAA==.',Ep='Epiphany:BAAALAADCggICAAAAA==.',Eu='Eurybia:BAAALAADCgUIBQAAAA==.',Ex='Exô:BAABLAAECoEXAAILAAgIuhZQGgAyAgALAAgIuhZQGgAyAgAAAA==.',Fa='Falard:BAAALAADCggIFAAAAA==.Faradormu:BAAALAADCgcICAAAAA==.Fastríp:BAAALAADCggICAAAAA==.Fatuu:BAAALAAECgIIAgAAAA==.',Ga='Garac:BAAALAAECgEIAQAAAA==.Gazin:BAABLAAECoEUAAMJAAgIdh/nGgBgAgAJAAcIQh/nGgBgAgAMAAgIaBJEOQDGAQABLAAECggIHAAIAKMcAA==.',Ge='Gerumos:BAAALAAECgMIBAABLAAFFAIIAgAHAAAAAA==.',Gh='Ghera:BAAALAADCgIIAgABLAAFFAIIAgAHAAAAAA==.Ghlaire:BAAALAAFFAIIAgAAAA==.',Go='Goldenweek:BAACLAAFFIEKAAINAAMI3wzKBwC7AAANAAMI3wzKBwC7AAAsAAQKgSEAAg0ACAisGu0TAC4CAA0ACAisGu0TAC4CAAAA.Gonbustion:BAAALAAECgUIEAAAAA==.Gozka:BAABLAAECoEWAAIOAAYIzRsoiQCxAQAOAAYIzRsoiQCxAQAAAA==.',Ha='Harijan:BAABLAAECoEWAAIPAAYI0gPoZwDXAAAPAAYI0gPoZwDXAAAAAA==.',He='Herrberg:BAAALAAECgMIBgAAAA==.',Hi='Himel:BAABLAAECoEUAAMQAAcI6g5+LgCVAQAQAAcIGA5+LgCVAQAIAAMIQgrRtQCcAAAAAA==.',Ho='Holydox:BAABLAAECoEWAAIRAAgIjQvqSgCFAQARAAgIjQvqSgCFAQABLAAFFAIIBQASAPUFAA==.',It='Itszero:BAABLAAECoEeAAITAAcIERaOXwDgAQATAAcIERaOXwDgAQAAAA==.',Ja='Jaki:BAAALAAECgQIBgAAAA==.',Ju='Julezz:BAACLAAFFIEGAAITAAIIpBckJQCgAAATAAIIpBckJQCgAAAsAAQKgSMAAhMACAiwIc8WAPgCABMACAiwIc8WAPgCAAAA.',Ka='Kaiyika:BAAALAADCgcICgAAAA==.Kajika:BAAALAADCggIFgAAAA==.',Ke='Kerub:BAAALAADCggICAAAAA==.Keshnoc:BAAALAAECgMIAwAAAA==.',Kh='Khorknohar:BAABLAAECoEbAAIUAAcIpxskRgDsAQAUAAcIpxskRgDsAQAAAA==.',Ki='Kimshí:BAAALAAECgMIBgAAAA==.',Kn='Knorkeborke:BAABLAAECoEbAAIMAAYIXB82KwAJAgAMAAYIXB82KwAJAgAAAA==.',Kr='Krotor:BAAALAAECgYICAABLAAECggIHAAIAKMcAA==.',Ku='Kuhlimuh:BAABLAAECoEWAAIMAAYI8A5+ZwAfAQAMAAYI8A5+ZwAfAQAAAA==.',La='Lanina:BAAALAAECgYIEgAAAA==.Lapyn:BAAALAADCggIEQAAAA==.',Le='Leonno:BAAALAAECgMIAwAAAA==.Leyda:BAAALAADCggICAAAAA==.',Lo='Lootgeier:BAAALAAECggICAAAAA==.Lormêx:BAAALAAECggIEgAAAA==.',Lu='Luthien:BAAALAAECgYIDQAAAA==.Luxina:BAAALAAECgMIAwAAAA==.',Ma='Mamoria:BAAALAAECgYIDQABLAAECggIOgAEAHAiAA==.',Me='Melif:BAABLAAECoEaAAIFAAYIwh6jTQD2AQAFAAYIwh6jTQD2AQAAAA==.Melrakki:BAAALAADCgYIBgAAAA==.',Mi='Miawallace:BAABLAAECoEWAAIGAAYInhpINgDKAQAGAAYInhpINgDKAQAAAA==.Miguéréya:BAAALAAECgMIAwAAAA==.Milchmädchen:BAAALAADCgYIBgAAAA==.Mirija:BAAALAAECgEIAQAAAA==.',Mo='Mograr:BAAALAADCgEIAQAAAA==.',Mu='Murky:BAAALAAECgYIDAAAAA==.',Na='Nairi:BAAALAAECgIIAgAAAA==.',Ni='Nightwings:BAAALAAECgMIBQAAAA==.',Ny='Nymphadora:BAABLAAECoEWAAITAAgI2RRXbgC9AQATAAgI2RRXbgC9AQAAAA==.',On='Onawa:BAABLAAECoEpAAIMAAgIBQU0fgDfAAAMAAgIBQU0fgDfAAAAAA==.Onepunchmonk:BAAALAAECgYIDAAAAA==.Ontari:BAAALAADCggICAABLAAFFAMIBQAVAFEPAA==.',Ot='Otar:BAAALAAECggICgAAAA==.',Pa='Paladoxa:BAABLAAECoExAAINAAgISBoOEQBNAgANAAgISBoOEQBNAgABLAAFFAIIBQASAPUFAA==.Palboa:BAAALAADCgcIFQAAAA==.Paradoxas:BAACLAAFFIEFAAISAAII9QU2BwBZAAASAAII9QU2BwBZAAAsAAQKgSgAAhIACAjcGAMIAGkCABIACAjcGAMIAGkCAAAA.',Py='Pyroßlow:BAACLAAFFIEKAAIWAAUI0hmkBAC7AQAWAAUI0hmkBAC7AQAsAAQKgScAAhYACAhhJacCAFwDABYACAhhJacCAFwDAAAA.',['Pé']='Pébbles:BAAALAADCggICAABLAAECggIDAAHAAAAAA==.',Ra='Raeoxx:BAAALAAECggIBwAAAA==.',Re='Reapaz:BAABLAAECoEhAAIXAAgI0h/NBQDxAgAXAAgI0h/NBQDxAgAAAA==.',Ro='Robindem:BAABLAAECoErAAITAAgI7wNR1QDeAAATAAgI7wNR1QDeAAAAAA==.Robinwar:BAAALAAECggIDgAAAA==.',Ru='Rumbi:BAAALAADCgUIBQABLAAFFAMICQALAKcaAA==.',Ry='Ryumari:BAABLAAECoEsAAIOAAgIdxxcLQCWAgAOAAgIdxxcLQCWAgAAAA==.',['Rì']='Rìmz:BAAALAADCgUIBwAAAA==.',['Rí']='Rímzi:BAAALAADCgUIBQAAAA==.',['Rô']='Rôlade:BAAALAADCggICgAAAA==.',Sa='Sadorak:BAACLAAFFIEIAAIOAAMIrxskFQAGAQAOAAMIrxskFQAGAQAsAAQKgSkAAg4ACAjnIeEbAOMCAA4ACAjnIeEbAOMCAAAA.',Sc='Scharm:BAAALAAECgYIBgABLAAECgYIDAAHAAAAAA==.',Sh='Shaarî:BAAALAAECgQICQAAAA==.Shameonu:BAABLAAECoEVAAMYAAgI4RkdTgCjAQAYAAYIphcdTgCjAQADAAQIqxRc4wCDAAAAAA==.Shamydeluxe:BAAALAAECggIEgAAAA==.Shinobu:BAAALAAECgMIAwAAAA==.Shono:BAAALAAECgYICwAAAA==.',Si='Silveraxekyo:BAAALAAECgYIBAAAAA==.',Sn='Sniadin:BAAALAADCgcIAQAAAA==.Snimies:BAAALAADCggIDwAAAA==.Sniwarri:BAAALAADCgEIAQAAAA==.Snî:BAABLAAECoEmAAIZAAgILhZIFAD/AQAZAAgILhZIFAD/AQAAAA==.',So='Solani:BAAALAAECgMIAwAAAA==.',Sy='Syrence:BAAALAAECgMIAwAAAA==.Syrenia:BAAALAADCggICAAAAA==.',Te='Teddyxbear:BAABLAAECoEaAAIaAAYI1h93EAAjAgAaAAYI1h93EAAjAgAAAA==.Teddyxdh:BAAALAAECgYICgAAAA==.Teddyxheals:BAAALAAECggIDwAAAA==.',Th='Thalmor:BAABLAAECoEdAAMBAAgIMyDiMACHAgABAAgIMyDiMACHAgACAAYIUhH2LwB9AQAAAA==.Thedark:BAAALAADCggICAAAAA==.Thorfinn:BAABLAAECoEXAAIBAAgIBh9eLgCSAgABAAgIBh9eLgCSAgAAAA==.Thunderjudge:BAAALAAECggIDwAAAA==.',Tr='Treuto:BAACLAAFFIEJAAIYAAMIuAfeFADBAAAYAAMIuAfeFADBAAAsAAQKgSMAAhgACAgaGp0pAEgCABgACAgaGp0pAEgCAAAA.Trollinlock:BAAALAADCgcIDQAAAA==.',Tx='Txskynet:BAAALAADCgcIDQAAAA==.',Ty='Tyrst:BAAALAAECgIIAgAAAA==.',Ve='Velrok:BAAALAAECggIDgAAAA==.Verydemon:BAAALAAECgUIDQAAAA==.',Vy='Vysco:BAAALAAECgEIAQAAAA==.',Wa='Warløn:BAAALAADCgYIBgAAAA==.',Wh='Whatsupdóc:BAAALAADCgcIEQAAAA==.',Wi='Willems:BAABLAAECoEWAAMIAAgIByILPQAXAgAIAAgIByILPQAXAgAQAAIIFA/XcQB3AAAAAA==.',Wu='Wuran:BAAALAAECgEIAQAAAA==.',['Wî']='Wîlma:BAAALAAECggIDAAAAA==.',Xa='Xaivo:BAABLAAECoEfAAMMAAcIyyR7CwDkAgAMAAcIyyR7CwDkAgAJAAYIEhRJSABeAQAAAA==.Xargall:BAAALAADCggIFwAAAA==.Xaron:BAAALAAECgYIEAAAAA==.',Yo='Yoruîchî:BAACLAAFFIEOAAIGAAUIVBshBAC/AQAGAAUIVBshBAC/AQAsAAQKgUgAAwYACAglItgWAJkCAAYABwgXI9gWAJkCAAUAAgi2FNPzAHYAAAAA.',['Yë']='Yën:BAABLAAECoEVAAIbAAYIhhNIIABgAQAbAAYIhhNIIABgAQAAAA==.',['Âr']='Ârrøw:BAABLAAECoEcAAMFAAcIDRR4aQCvAQAFAAcIDRR4aQCvAQAGAAEILQDRxQACAAAAAA==.',['În']='Înktra:BAACLAAFFIEFAAMUAAIIkhGPIwCcAAAUAAIIkhGPIwCcAAAcAAEIUwXDIgAyAAAsAAQKgSgAAxQACAh1HQYdALYCABQACAhcHQYdALYCABwABwhsF9ErAKsBAAAA.',['ßl']='ßlowchop:BAACLAAFFIEJAAIOAAMIGBoNFgD/AAAOAAMIGBoNFgD/AAAsAAQKgRQAAg4ABgj1JPY2AHMCAA4ABgj1JPY2AHMCAAEsAAUUBQgKABYA0hkA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end