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
 local lookup = {'Monk-Mistweaver','Paladin-Retribution','Hunter-BeastMastery','Mage-Arcane','Unknown-Unknown','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Warlock-Destruction','Mage-Fire','Monk-Brewmaster','Rogue-Assassination','Monk-Windwalker','Druid-Restoration','Druid-Balance','Mage-Frost','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Evoker-Augmentation','Warrior-Protection','Druid-Guardian','Paladin-Protection','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','Priest-Holy','Druid-Feral','Priest-Shadow','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','DeathKnight-Blood',}; local provider = {region='EU',realm='Madmortem',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abbot:BAABLAAECoEYAAIBAAgIwgBZQgBVAAABAAgIwgBZQgBVAAAAAA==.Abra:BAAALAADCggIGgAAAA==.Abydos:BAAALAAECgYICgABLAAECggIIgACAN8VAA==.',Ac='Achaion:BAAALAADCggIEwAAAA==.Acki:BAAALAAECgQICQAAAA==.',Ad='Adyria:BAAALAAECgcIDwAAAA==.',Aj='Ajeni:BAAALAADCggIFgAAAA==.',Al='Altimor:BAABLAAECoEYAAIDAAYIcCICPQArAgADAAYIcCICPQArAgAAAA==.Alvára:BAABLAAECoEeAAIEAAcIyBFMYQDAAQAEAAcIyBFMYQDAAQAAAA==.Alêxá:BAAALAAECgMIAwAAAA==.',Am='Amberlee:BAABLAAECoEpAAIDAAgIzBWLXQDMAQADAAgIzBWLXQDMAQAAAA==.Amilea:BAABLAAECoEXAAICAAgIViBLGgDvAgACAAgIViBLGgDvAgAAAA==.Ammâzonin:BAAALAAECgYIDAAAAA==.Amuun:BAAALAADCgIIAgAAAA==.Amína:BAAALAAECgYIBgAAAA==.',An='Anatomie:BAABLAAECoEbAAIEAAgI/RD5aACqAQAEAAgI/RD5aACqAQAAAA==.Andokî:BAAALAADCggICQAAAA==.Angelface:BAAALAADCgcIEQABLAAECgQIBwAFAAAAAA==.Anniky:BAAALAAECgUIBQAAAA==.Anníky:BAAALAADCggICwABLAAECgUIBQAFAAAAAA==.',Ao='Aoe:BAAALAADCgUIBQABLAAECggICAAFAAAAAA==.',Ap='Apanatschí:BAAALAADCggICgAAAA==.',Ar='Aramat:BAAALAAECgMIBgAAAA==.Aranthil:BAAALAAECgYIDgAAAA==.Arenthil:BAABLAAECoEWAAIDAAcIdSG0JwB/AgADAAcIdSG0JwB/AgAAAA==.Ariljar:BAABLAAECoEjAAIGAAgIXRhzCwBQAgAGAAgIXRhzCwBQAgAAAA==.Arkaik:BAAALAADCgcIDQAAAA==.Artegalantus:BAAALAAECgcIBwAAAA==.',As='Asgatron:BAAALAADCgQIBAAAAA==.Ashara:BAAALAADCgMIAwAAAA==.Asheràh:BAAALAAECgYIEQAAAA==.Asterwix:BAAALAAECgEIAQAAAA==.',At='Athayna:BAAALAAECgIIAgAAAA==.Athil:BAABLAAECoEbAAIDAAYI9xQxjgBhAQADAAYI9xQxjgBhAQAAAA==.Aturana:BAABLAAECoEqAAMHAAgINiABEADTAgAHAAgINiABEADTAgAIAAgIIh7mIwBpAgAAAA==.',Au='Auralis:BAABLAAECoEbAAIDAAYIdQ3LqAAuAQADAAYIdQ3LqAAuAQAAAA==.Aurara:BAAALAAECgYIEgAAAA==.Aurel:BAAALAAECgEIAQAAAA==.Aurelien:BAAALAADCgcIFAAAAA==.Aurius:BAABLAAECoEhAAICAAgIKgdupAB3AQACAAgIKgdupAB3AQAAAA==.',Av='Avène:BAAALAAECgYIDQAAAA==.',Ay='Aylyssae:BAAALAAECggIDwAAAA==.Ayoris:BAAALAAECgUIBQAAAA==.',Az='Azizah:BAAALAAECgUICwAAAA==.Azòg:BAACLAAFFIEFAAICAAIIuQ9kLwCdAAACAAIIuQ9kLwCdAAAsAAQKgSYAAgIABwjaISIvAI8CAAIABwjaISIvAI8CAAAA.',Ba='Baalroschox:BAAALAAECgQICAAAAA==.Bambur:BAABLAAECoEZAAIJAAcI+QqANwBSAQAJAAcI+QqANwBSAQAAAA==.Bapsi:BAAALAAECgMIBAABLAAECgQIBAAFAAAAAA==.',Be='Bearlee:BAAALAAECgYIBwAAAA==.Beckhasel:BAAALAAECgYICgAAAA==.Bellatrix:BAAALAADCggIEwAAAA==.Benjayboi:BAAALAADCgUIBQAAAA==.Beppò:BAAALAAECgMIAwAAAA==.Berstes:BAAALAADCggIDQAAAA==.Bertel:BAAALAADCgEIAgAAAA==.Bes:BAAALAAECgEIAQABLAAECggIHwAIALEXAA==.Bevola:BAAALAAECgEIAQAAAA==.',Bi='Biangka:BAAALAAECggIDgAAAA==.',Bl='Blackcycle:BAAALAADCgcIBgAAAA==.Blauwal:BAAALAADCggICAABLAADCggICAAFAAAAAA==.Blitzbirne:BAABLAAECoEVAAIIAAYIixqGPQDkAQAIAAYIixqGPQDkAQAAAA==.Bloodyminos:BAAALAAECgMIBgAAAA==.Blutdrache:BAAALAAECgYIDQAAAA==.',Bo='Boomfluffy:BAAALAAECgYIEwAAAA==.Borgash:BAAALAAECgQIBQAAAA==.',Br='Breitstreich:BAAALAADCgcIDQAAAA==.Brumbos:BAAALAADCggICwAAAA==.',Bu='Bummelz:BAABLAAECoEvAAIKAAcIZiPZJgCBAgAKAAcIZiPZJgCBAgAAAA==.Burroughs:BAAALAAECgYIDwAAAA==.',Ca='Candystôrm:BAAALAADCgYIBwAAAA==.Caraxas:BAAALAADCggILgABLAAFFAIIBQALAFoHAA==.Carerie:BAAALAADCgQIBAABLAAECgcIGwAMAEEYAA==.Catalaná:BAABLAAECoEZAAINAAYI+RNCMACYAQANAAYI+RNCMACYAQAAAA==.',Ce='Ceeyzo:BAAALAADCgYIBgAAAA==.Cerialkiller:BAAALAAECgMIBAAAAA==.',Ch='Chaoling:BAABLAAECoEmAAIOAAgI1xTNHADrAQAOAAgI1xTNHADrAQAAAA==.Chippzzií:BAABLAAECoEXAAIPAAcIVxy+KQAQAgAPAAcIVxy+KQAQAgAAAA==.Chocalock:BAAALAAECgYIDAAAAA==.Chorknai:BAABLAAECoEbAAIQAAcIZxd/MADQAQAQAAcIZxd/MADQAQAAAA==.Chrisa:BAABLAAECoEeAAIQAAcIiAt3RwBiAQAQAAcIiAt3RwBiAQAAAA==.',Cl='Clisan:BAAALAAECgYIDwAAAA==.',Co='Colinferal:BAABLAAECoEWAAMQAAYIKBxZLgDcAQAQAAYIKBxZLgDcAQAPAAMI+QtWowBuAAAAAA==.Corazón:BAABLAAECoEbAAIRAAcIYxQwLgCgAQARAAcIYxQwLgCgAQAAAA==.',Cr='Cryt:BAAALAAECgYICAAAAA==.Cryîngwolf:BAAALAAFFAIIBAAAAA==.',Da='Daeana:BAAALAADCggIBgAAAA==.Dako:BAAALAADCgMIAwAAAA==.Dalora:BAABLAAECoEWAAMNAAgItQQZPwBCAQANAAgItQQZPwBCAQASAAEIVwKMHQAaAAAAAA==.Dameon:BAAALAAECgYICAAAAA==.Dandukrah:BAAALAAECggICgAAAA==.Dara:BAABLAAECoEnAAINAAgIlCPDAwA5AwANAAgIlCPDAwA5AwAAAA==.Darkcaster:BAAALAADCgMIAgAAAA==.Darkdaka:BAACLAAFFIEGAAIPAAMI/RanCgD2AAAPAAMI/RanCgD2AAAsAAQKgSQAAw8ACAiIFuotAPwBAA8ACAiIFuotAPwBABAACAgyCqZFAGsBAAAA.Darkdk:BAAALAAECgMIBQABLAAFFAMIBgAPAP0WAA==.Darkface:BAAALAAECgEIAQAAAA==.Darkpriest:BAAALAADCgIIAgAAAA==.Darksniper:BAAALAAECgEIAQABLAAFFAMIBgAPAP0WAA==.Darkvoker:BAAALAAECgYICAAAAA==.Darthdrago:BAAALAADCgcIBwAAAA==.Darthsoul:BAABLAAECoEYAAMTAAgIKRhWZgD1AQATAAgIKRhWZgD1AQAUAAEImyJwTgBPAAAAAA==.Dasilva:BAAALAADCggIJAAAAA==.',De='Deadeyê:BAAALAAECgYIDQAAAA==.Deltonia:BAAALAAECgYICwAAAA==.',Di='Dignug:BAAALAAFFAEIAQAAAA==.Dilonia:BAABLAAECoEhAAICAAcIpQqipwBxAQACAAcIpQqipwBxAQAAAA==.Dimiter:BAAALAAECgYIDwAAAA==.Dirbase:BAAALAAECgYIBgAAAA==.Dirce:BAAALAADCgEIAQAAAA==.Dirtyd:BAAALAAECgIIAwAAAA==.Disaster:BAAALAAECgEIAQABLAAECgMIBgAFAAAAAA==.',Do='Dorbina:BAAALAADCggIEAAAAA==.',Dr='Draccas:BAAALAADCggILAAAAA==.Draketa:BAABLAAECoEWAAMVAAgIwhsOFgDqAQAWAAcI4xp4TQAPAgAVAAYIOh0OFgDqAQAAAA==.Drip:BAAALAADCggIEAAAAA==.Drâgoon:BAAALAAECgYIEwAAAA==.',Du='Duellant:BAABLAAECoEdAAIXAAgIexO8RQDtAQAXAAgIexO8RQDtAQAAAA==.Dufinchen:BAAALAADCggIAwAAAA==.Durran:BAAALAAECgYICgAAAA==.Duschberater:BAAALAAECgcIEQAAAA==.Dusk:BAAALAADCgcIBwABLAAECgcIDQAFAAAAAA==.Duuns:BAAALAADCggIFgAAAA==.',Dy='Dyane:BAAALAAECgcIDQAAAA==.',['Dâ']='Dârka:BAAALAAECgMIBwAAAA==.Dâywâlker:BAAALAADCggICwAAAA==.',['Dä']='Dämonâ:BAAALAAECgYIDAAAAA==.',['Dê']='Dêspotar:BAAALAAECgYIBQAAAA==.',Ea='Earb:BAABLAAECoEeAAMJAAcInRQEIgDVAQAJAAcInRQEIgDVAQACAAcIdQ+shwCsAQAAAA==.Earthtongue:BAAALAAECgMIAwAAAA==.',Eb='Ebbakush:BAAALAAECgYIDQAAAA==.',Ek='Ekzykes:BAABLAAECoEWAAIYAAcIDg+NCQCjAQAYAAcIDg+NCQCjAQAAAA==.Ekáro:BAAALAAECgYIDQAAAA==.',El='Elchak:BAABLAAECoEjAAIZAAgIPBDHLQCeAQAZAAgIPBDHLQCeAQAAAA==.Elenè:BAABLAAECoEUAAIPAAcIPCAyGAB3AgAPAAcIPCAyGAB3AgAAAA==.Elené:BAAALAAFFAIIBAAAAA==.Ellariana:BAAALAADCggIEAAAAA==.Elundris:BAAALAAECgUIBQAAAA==.',Er='Erandas:BAAALAADCgYIBgAAAA==.Erathan:BAABLAAECoEVAAIaAAcI8xV1DQDIAQAaAAcI8xV1DQDIAQABLAAFFAIICAAXAIgaAA==.Erdenfeuer:BAAALAADCgEIAQAAAA==.Ericsa:BAABLAAECoEiAAICAAcI3xVLhQCwAQACAAcI3xVLhQCwAQAAAA==.Ersatzspiel:BAABLAAECoEgAAMbAAcIWx/8DgBnAgAbAAcIWx/8DgBnAgACAAIIew50JQFhAAAAAA==.',Es='Essence:BAABLAAECoEdAAIcAAcIfCVYCgDrAgAcAAcIfCVYCgDrAgAAAA==.',Ev='Evides:BAAALAAECgUIBQAAAA==.Evithra:BAAALAAECggICwAAAA==.',Ex='Existenz:BAABLAAECoEfAAIZAAcIsyL4DQCtAgAZAAcIsyL4DQCtAgAAAA==.',Ey='Eywer:BAAALAADCgUIBQAAAA==.',Fa='Fandelyria:BAAALAAECgYIEAAAAA==.Farasyn:BAAALAAECgEIAQAAAA==.',Fe='Felgibson:BAABLAAECoEdAAIKAAgI4BXnOQAlAgAKAAgI4BXnOQAlAgAAAA==.Felinova:BAABLAAECoEcAAIDAAgI5xJ7XADPAQADAAgI5xJ7XADPAQAAAA==.Fero:BAABLAAECoEeAAIPAAgI9B25FACRAgAPAAgI9B25FACRAgAAAA==.',Fl='Flared:BAAALAAECgQIBgAAAA==.Fluorid:BAABLAAECoEdAAIZAAcIWRUtLQCiAQAZAAcIWRUtLQCiAQAAAA==.',Fo='Foxly:BAAALAADCggICAAAAA==.',Fr='Freesia:BAAALAAECgUIBgAAAA==.From:BAABLAAECoEdAAINAAgIfBfkHQATAgANAAgIfBfkHQATAgAAAA==.',Fy='Fynni:BAABLAAECoEWAAIZAAgIgBhkGwAjAgAZAAgIgBhkGwAjAgAAAA==.',Ga='Galgarix:BAAALAAECgEIAQAAAA==.Garaa:BAABLAAECoEZAAIDAAYIIxnCdQCTAQADAAYIIxnCdQCTAQAAAA==.Garagrim:BAAALAADCggICAAAAA==.',Gh='Ghandí:BAABLAAECoEkAAIOAAcI0w0ELQBrAQAOAAcI0w0ELQBrAQAAAA==.',Gi='Giemly:BAAALAAECgQIBgAAAA==.Ginnpala:BAABLAAECoErAAICAAgI2h8OHwDXAgACAAgI2h8OHwDXAgAAAA==.',Gn='Gnomferatu:BAAALAAECgMIBgAAAA==.',Go='Golgothan:BAAALAAECgEIAQAAAA==.Gomper:BAAALAADCgcIEQAAAA==.Goswin:BAAALAADCggICAAAAA==.',Gr='Greeny:BAABLAAECoEZAAIDAAgIqRD3iABrAQADAAgIqRD3iABrAQAAAA==.Grisu:BAAALAAECgQICQAAAA==.Grisù:BAAALAADCgYIBgABLAAECgIIAwAFAAAAAA==.Grizzli:BAAALAAECgIIAgABLAAECggIHQAKAOAVAA==.Gromar:BAAALAAFFAIIAgAAAA==.Gronnhard:BAAALAADCgcIEgAAAA==.',Gu='Guenevert:BAAALAADCgcIBgAAAA==.Guldanos:BAABLAAECoEbAAIdAAcIkR+XDACLAgAdAAcIkR+XDACLAgAAAA==.Gurkengustel:BAAALAAECgYIDQAAAA==.',Gw='Gwendoleen:BAABLAAECoEaAAIRAAYIaROkNAB9AQARAAYIaROkNAB9AQAAAA==.',['Gò']='Gòlle:BAABLAAFFIEGAAIXAAIIEgpmLQCKAAAXAAIIEgpmLQCKAAAAAA==.',['Gö']='Gövb:BAAALAADCgQICQAAAA==.',['Gú']='Gúnnârsòn:BAABLAAECoEeAAIZAAcI4BhxIgDsAQAZAAcI4BhxIgDsAQAAAA==.',Ha='Halvor:BAABLAAECoEgAAIXAAgI9BxmIgCTAgAXAAgI9BxmIgCTAgAAAA==.Hanibal:BAAALAAECgMIAwAAAA==.Hastir:BAAALAAECgMIAwAAAA==.',He='Hekaria:BAAALAADCgEIAQAAAA==.Hellráiser:BAAALAAECgYIDQAAAA==.Heralon:BAAALAADCgcIDQAAAA==.Heribert:BAAALAAECgMIBwAAAA==.Herzbann:BAABLAAECoEfAAMWAAcIAhgRXQDlAQAWAAcIAhgRXQDlAQAVAAYIKQ2DNADpAAAAAA==.Hestaby:BAABLAAECoEjAAIPAAgIRxFhOwC8AQAPAAgIRxFhOwC8AQAAAA==.Hexerchen:BAABLAAECoEXAAIeAAcI3iBcBACaAgAeAAcI3iBcBACaAgABLAAFFAIICAAXAIgaAA==.Hexorp:BAAALAAECgEIAQAAAA==.',Hi='Hiiaka:BAAALAAECgYIDAAAAA==.Hirona:BAAALAAECgMIBQAAAA==.',Ho='Holypumpgun:BAAALAAECgIIAgAAAA==.Homusubi:BAAALAADCggIGQAAAA==.Hoohoo:BAAALAAECgYICAAAAA==.Hornîdemon:BAABLAAECoEbAAIWAAcIbBKdmwBhAQAWAAcIbBKdmwBhAQAAAA==.Hoshiguma:BAAALAAECgYICQAAAA==.',Hr='Hrøthgarr:BAAALAAECgUIBQAAAA==.',['Hé']='Héllslayer:BAAALAAECgUIDAABLAAECgYIDQAFAAAAAA==.',['Hí']='Híkarí:BAAALAAECgcICwAAAA==.',Ig='Igcorn:BAAALAAECgQICQAAAA==.',Il='Illidarm:BAABLAAECoElAAMWAAgIQCG4HADWAgAWAAgIViC4HADWAgAVAAIICSSWOADRAAAAAA==.',Im='Imhotêp:BAABLAAECoEbAAIfAAYIbQ2DagAWAQAfAAYIbQ2DagAWAQAAAA==.',In='Ino:BAABLAAECoEmAAMTAAgISBMfawDrAQATAAgI6RAfawDrAQAUAAEI6yE7SgBnAAAAAA==.Inso:BAAALAADCggIDwAAAA==.',Is='Isnipeyou:BAABLAAECoEWAAIDAAgIVgwuhAB1AQADAAgIVgwuhAB1AQAAAA==.Isâra:BAAALAAECgYIDQABLAAECggIIQACAGkjAA==.',It='Itakespeed:BAAALAAECgYIEwAAAA==.',Iw='Iwazaro:BAABLAAECoEcAAIbAAgIFSCuBwDiAgAbAAgIFSCuBwDiAgAAAA==.',Ja='Jalendrya:BAABLAAECoEZAAIbAAYIGgqSPQDzAAAbAAYIGgqSPQDzAAAAAA==.',Je='Jeneca:BAABLAAECoEhAAIbAAcIXgytMQA9AQAbAAcIXgytMQA9AQAAAA==.Jerrica:BAABLAAECoEnAAIPAAgIyBOuOQDEAQAPAAgIyBOuOQDEAQAAAA==.Jeryssa:BAAALAAECgYIDgAAAA==.Jesaija:BAAALAADCgEIAQAAAA==.',Ji='Jingu:BAAALAADCggIIAAAAA==.',Ju='Jukens:BAAALAADCggICAAAAA==.Juker:BAABLAAECoEaAAIJAAcI+ySYBgDnAgAJAAcI+ySYBgDnAgAAAA==.Jularis:BAABLAAECoEUAAIRAAYI/Q5bQwA8AQARAAYI/Q5bQwA8AQAAAA==.Junimond:BAAALAADCgcIBgAAAA==.Justizia:BAAALAADCgcICwAAAA==.',['Jä']='Jäm:BAAALAADCgcIBwAAAA==.',['Jî']='Jînx:BAAALAAECggIEgABLAAECggILQARAHohAA==.',Ka='Kaajiin:BAAALAADCgcIDAAAAA==.Kagari:BAAALAADCggICAAAAA==.Kagûra:BAABLAAECoEUAAIDAAgI2w/XbQClAQADAAgI2w/XbQClAQAAAA==.Kaissy:BAABLAAECoEbAAIMAAYIWBa2HwBmAQAMAAYIWBa2HwBmAQAAAA==.Kaiulani:BAAALAADCgcIBwAAAA==.Kakashie:BAABLAAECoEaAAIXAAcIzBysLwBJAgAXAAcIzBysLwBJAgAAAA==.Kalany:BAAALAAECgMIBwAAAA==.Kaliphera:BAAALAAECgYIBwAAAA==.Kallistos:BAAALAADCgcIBwABLAAECgcIHgAQAOUbAA==.Karuzo:BAAALAAFFAIIAwAAAA==.Karya:BAABLAAECoETAAIgAAYI0RkgGAC9AQAgAAYI0RkgGAC9AQAAAA==.Kathreena:BAAALAAECgcIDwAAAA==.Kazzia:BAAALAAECggIEQAAAA==.',Ke='Kergrimm:BAAALAAECgQICQAAAA==.Kerola:BAAALAAECgMIBgAAAQ==.Keshara:BAABLAAECoEdAAIHAAcIRyKfGgCPAgAHAAcIRyKfGgCPAgAAAA==.',Kh='Khia:BAAALAAECgEIAQAAAA==.',Ki='Kimiko:BAAALAADCggIFAAAAA==.Kiralowa:BAAALAADCggIEAAAAA==.',Kl='Klotzkopf:BAAALAADCgMIBAAAAA==.',Km='Kmörderin:BAAALAADCgcIDgAAAA==.',Ko='Koothrappali:BAAALAAECgYIDQAAAA==.',Kr='Kraska:BAAALAADCgYICAAAAA==.Krautstrudel:BAAALAADCggIDwAAAA==.Krellis:BAAALAAECgMIBAAAAA==.Krenon:BAAALAAECgYIDQAAAA==.',['Kä']='Käsi:BAAALAAECgYICQAAAA==.',['Kí']='Kíllbill:BAAALAAECggICAAAAA==.Kíllerspeed:BAAALAADCgYIBgAAAA==.Kírytô:BAAALAADCgIIAgAAAA==.',La='Larisha:BAABLAAECoEjAAIWAAcINRhCUgACAgAWAAcINRhCUgACAgAAAA==.Latexia:BAAALAADCggILAAAAA==.Lautasmir:BAAALAADCggIHwAAAA==.Lavonas:BAABLAAECoEcAAICAAcIVBL1egDEAQACAAcIVBL1egDEAQAAAA==.Laylana:BAABLAAECoEUAAIaAAcIohW/DQDCAQAaAAcIohW/DQDCAQAAAA==.',Le='Lebensquelle:BAAALAADCggIDAAAAA==.Lenija:BAABLAAECoEdAAIIAAcIxyCkIAB+AgAIAAcIxyCkIAB+AgAAAA==.Leodor:BAABLAAECoErAAMaAAgIpBsdBwBbAgAaAAgIpBsdBwBbAgAgAAcIeQy2HQCBAQAAAA==.Leskaia:BAAALAADCggICAAAAA==.Leslie:BAAALAADCggICAAAAA==.Lessien:BAABLAAECoEgAAIhAAcI8RjCLwDwAQAhAAcI8RjCLwDwAQAAAA==.Lexus:BAAALAAECgQIBwAAAA==.Leyona:BAAALAADCggIDwAAAA==.',Lh='Lhoreta:BAAALAADCggIDgAAAA==.',Li='Libertas:BAAALAAECgUICAAAAA==.Lightyear:BAAALAADCgcIBwAAAA==.Lilth:BAAALAADCgYIBgAAAA==.Lingfu:BAAALAAECgIIBAAAAA==.Live:BAAALAADCggIDQABLAAECggIJwAiAK4jAA==.Livefour:BAABLAAECoEnAAIiAAgIriOnCQAPAwAiAAgIriOnCQAPAwAAAA==.Liwana:BAAALAAECgYIEAABLAAECggIKwAaAKQbAA==.',Lo='Londran:BAACLAAFFIEFAAILAAIIWgcjBQCJAAALAAIIWgcjBQCJAAAsAAQKgSAAAgsACAg4E/AEACwCAAsACAg4E/AEACwCAAAA.Loorii:BAAALAAECgIIAgAAAA==.Lorisaniea:BAAALAADCggICAABLAAFFAIIAgAFAAAAAA==.',Lu='Lubog:BAAALAAECgUIBQABLAAFFAIIBQAfAPkRAA==.Lucif:BAAALAAECgYICAAAAA==.Lucifér:BAAALAADCgcICgABLAAECgQIBwAFAAAAAA==.Luthia:BAAALAADCggIEAAAAA==.',Ly='Lynesca:BAABLAAECoEiAAIWAAYI5xe+hgCKAQAWAAYI5xe+hgCKAQAAAA==.Lyo:BAABLAAECoEUAAIIAAYIRB+mMQAbAgAIAAYIRB+mMQAbAgAAAA==.Lysalis:BAAALAAECgIIAgAAAA==.Lysandar:BAABLAAECoEUAAIiAAgIBB89EwC4AgAiAAgIBB89EwC4AgAAAA==.',['Lú']='Lúaxa:BAAALAADCggICAAAAA==.',['Lü']='Lübä:BAACLAAFFIEKAAIJAAQI6hZGBgBSAQAJAAQI6hZGBgBSAQAsAAQKgSMAAwkACAjpIDEJAMICAAkACAjpIDEJAMICABsAAwhQId83ABcBAAAA.',Ma='Maditartor:BAAALAAECgYICgAAAA==.Magamas:BAABLAAECoEYAAIEAAgITg7NVQDjAQAEAAgITg7NVQDjAQAAAA==.Magimax:BAAALAADCgcIBgABLAADCggILAAFAAAAAA==.Mainator:BAAALAAECgMIAwAAAA==.Malissa:BAABLAAECoEeAAMCAAcIsA/QhgCtAQACAAcIsA/QhgCtAQAbAAII4wJbXgA2AAAAAA==.Maowy:BAABLAAECoEZAAMbAAYIfgwXOQAPAQAbAAYIfgwXOQAPAQACAAEIZQKnTwEVAAAAAA==.Marab:BAABLAAECoEYAAINAAcIWxLlKQC/AQANAAcIWxLlKQC/AQAAAA==.Margonja:BAAALAAECgUICgAAAA==.Maribelle:BAAALAAECgYIBgABLAAECggIFwACAFYgAA==.Maschorox:BAAALAAECgIICQAAAA==.',Me='Medon:BAAALAAECgQICQAAAA==.Meilíx:BAAALAADCggICAAAAA==.Meistercycle:BAAALAADCggIFAAAAA==.Melfara:BAAALAADCggIEQABLAAECggIIwACADAZAA==.Meliaa:BAAALAADCggIHwABLAAECgcIGwAdAJEfAA==.Melvin:BAABLAAECoEdAAIRAAcI9A7wLwCWAQARAAcI9A7wLwCWAQAAAA==.Memna:BAAALAADCgUIBQABLAAECgYIBwAFAAAAAA==.Meresin:BAAALAAECggICAAAAA==.Merãluñã:BAAALAAECgYIBQAAAA==.',Mi='Milim:BAABLAAECoEbAAIIAAYIdxNmWQB8AQAIAAYIdxNmWQB8AQAAAA==.Mimikyu:BAAALAAECgYIDAABLAAECgcIGwAMAEEYAA==.Mithara:BAAALAADCgEIAQABLAAECgcIHgACALAPAA==.Miyade:BAAALAADCggILgABLAAECgcIHgACALAPAA==.',Mo='Mobsi:BAAALAADCggICAAAAA==.Mondschwinge:BAABLAAECoEnAAIfAAgITwbeZQAkAQAfAAgITwbeZQAkAQAAAA==.Monomania:BAABLAAECoEjAAIDAAgIxR7KIwCUAgADAAgIxR7KIwCUAgAAAA==.Monschischi:BAAALAAECgUICwAAAA==.Moofiepoh:BAABLAAECoErAAIBAAgI0B/YCAC7AgABAAgI0B/YCAC7AgAAAA==.Mooncrush:BAABLAAECoEeAAIQAAcIMh5zGgBkAgAQAAcIMh5zGgBkAgAAAA==.Moosy:BAAALAAECgUIBgAAAA==.Morowyn:BAABLAAECoEmAAIgAAgIGA8yGQCwAQAgAAgIGA8yGQCwAQAAAA==.',Mu='Muhdy:BAAALAAECgYIBgAAAA==.Muhnagosa:BAAALAAECggIDAAAAA==.Munel:BAABLAAECoEjAAMfAAgINhSVMwDuAQAfAAgINhSVMwDuAQAhAAIIQAaYgQBRAAAAAA==.Muradjin:BAAALAADCgYIBgAAAA==.',My='Myami:BAAALAAECggICAAAAA==.Mystiklion:BAAALAADCggIGwAAAA==.Mystra:BAAALAAECgYIBgAAAA==.',['Mâ']='Mâverick:BAABLAAECoEhAAICAAgIaSN/GAD5AgACAAgIaSN/GAD5AgAAAA==.',['Mè']='Mèlix:BAAALAAECgYIDQAAAA==.',Na='Naliana:BAAALAADCgcICAABLAAECggIKgAHADYgAA==.Nandul:BAAALAAECgYICQAAAA==.Napfkuchen:BAABLAAECoEbAAIfAAcIlhkMLwAGAgAfAAcIlhkMLwAGAgAAAA==.Napo:BAAALAAECgYIEwAAAA==.Nathalel:BAAALAAECgYIEgAAAA==.',Ne='Neavane:BAAALAAECgcIDAABLAAFFAIIBAAFAAAAAA==.Necha:BAAALAAECgEIAQAAAA==.Nedari:BAAALAAECgYICwAAAA==.Neiren:BAABLAAECoEjAAIfAAgIkw72QACuAQAfAAgIkw72QACuAQAAAA==.Neosha:BAAALAADCggICAABLAAFFAIIAgAFAAAAAA==.Nerdanel:BAABLAAECoEXAAIRAAcIAhqKGgAhAgARAAcIAhqKGgAhAgAAAA==.Nerylla:BAABLAAECoEaAAIDAAYIrQzFqwAoAQADAAYIrQzFqwAoAQAAAA==.Nethrok:BAAALAADCgYIBgAAAA==.',Nh='Nhamrael:BAAALAAECggICgAAAA==.',Ni='Niahani:BAAALAADCggICAAAAA==.Nicon:BAABLAAECoEfAAIIAAgIsRenKABNAgAIAAgIsRenKABNAgAAAA==.Nightmoo:BAAALAADCgcICgABLAAECgYICgAFAAAAAA==.Nightskull:BAABLAAECoEWAAIWAAgISxK3YADdAQAWAAgISxK3YADdAQAAAA==.Niluna:BAAALAAECgQICQAAAA==.Niralania:BAAALAAECgIIAgAAAA==.Nishera:BAAALAAECgcIEwAAAA==.',No='Noleen:BAAALAAECgIIAgAAAA==.Nordanier:BAAALAAECgMIAwABLAAECggIJwAiAK4jAA==.Noxaris:BAAALAAECggIEAABLAAFFAIIBAAFAAAAAQ==.',['Nì']='Nìghtwolf:BAAALAADCgYIBgAAAA==.',Ol='Olfrad:BAAALAAECgUICgAAAA==.',On='Oniginn:BAAALAADCggIEgABLAAECggIKwACANofAA==.Onklhorscht:BAABLAAECoEYAAIDAAcIWBC5ggB4AQADAAcIWBC5ggB4AQAAAA==.',Op='Ophira:BAAALAAECgYIBgAAAA==.',Or='Ordoban:BAAALAADCggILgAAAA==.Orikano:BAAALAAECgMIBQAAAA==.Orpex:BAABLAAECoEXAAIWAAgIqwhAwgARAQAWAAgIqwhAwgARAQAAAA==.',Os='Osbourne:BAAALAAECggIEAAAAA==.',Ot='Otzum:BAAALAAECgUIDwAAAA==.',Pa='Palandrius:BAAALAADCgYIBgAAAA==.Pavo:BAAALAADCgIIAgAAAA==.',Pe='Pepegodx:BAAALAAECgYIBgAAAA==.Petrani:BAAALAADCggIIgAAAA==.',Ph='Phyintias:BAAALAAECgYICwAAAA==.',Pi='Piiepmatz:BAAALAAECgIIAgAAAA==.Pillosis:BAAALAAECgQIBgAAAA==.Pinpin:BAAALAAECggIAQAAAA==.',Pl='Plebon:BAAALAAECgYICQABLAAECgYIFgAEAJoWAA==.',Po='Poepina:BAAALAAECgMICAAAAA==.Porschegünni:BAABLAAECoEWAAIEAAgIDgEB0QBcAAAEAAgIDgEB0QBcAAAAAA==.Porthub:BAAALAAECgYIBgABLAAECggIHQAKAOAVAA==.',Pr='Pretorianner:BAABLAAECoEWAAITAAYILhGqxQBLAQATAAYILhGqxQBLAQAAAA==.Priesterle:BAAALAAFFAIIBAABLAAFFAIICAAXAIgaAA==.Pränkii:BAAALAAECgcIEAAAAA==.',Ps='Psychoonfire:BAAALAADCggICAAAAA==.',Pu='Puda:BAAALAAECgUICQAAAA==.Punanidh:BAAALAAECggICwABLAAFFAIIBQAXAOMUAA==.Punaniwarri:BAACLAAFFIEFAAIXAAII4xQlHgClAAAXAAII4xQlHgClAAAsAAQKgScAAhcACAibHvYZAMwCABcACAibHvYZAMwCAAAA.Puredarkness:BAABLAAECoEUAAIgAAcIpQq8HwBsAQAgAAcIpQq8HwBsAQAAAA==.',['Pü']='Püppi:BAAALAADCggICAAAAA==.',Qu='Quool:BAAALAAECgEIAQAAAA==.',Ra='Raraku:BAAALAADCgIIAgABLAAECgYIBwAFAAAAAA==.',Re='Redbullseye:BAAALAADCgcIBwAAAA==.Rehiri:BAABLAAECoEmAAIHAAgIJB3XHACDAgAHAAgIJB3XHACDAgAAAA==.Rekan:BAABLAAECoEWAAIDAAYIKhkxbwCiAQADAAYIKhkxbwCiAQAAAA==.Rentnerdd:BAAALAAECgYIEAABLAAECgYIFgAQACgcAA==.',Ro='Robina:BAAALAAECgYIBwAAAA==.Roblock:BAABLAAECoEiAAQeAAgInhWdEQB8AQAKAAcIjBfdWwCpAQAeAAcIxQedEQB8AQAdAAUIbQdoVwDnAAAAAA==.Robro:BAAALAAECgYIBgABLAAECggIJwADAO0gAA==.Robson:BAABLAAECoEnAAIDAAgI7SDSIACjAgADAAgI7SDSIACjAgAAAA==.Robsón:BAAALAADCgYIBgABLAAECggIJwADAO0gAA==.Rogan:BAAALAAECgYIDAAAAA==.Rokkboxx:BAAALAADCggIJgAAAA==.Roxsas:BAAALAADCggIDAABLAAECggIFwAcAPkhAA==.Royanna:BAAALAADCgIIAgABLAAECgcIHgACALAPAA==.',['Rá']='Rásputin:BAABLAAECoEnAAIjAAgI7QNIHwC1AAAjAAgI7QNIHwC1AAAAAA==.',Sa='Sairaspöllö:BAAALAAECggICAAAAA==.Saizou:BAAALAAECgYIDwAAAA==.Salz:BAAALAADCgcIBwAAAA==.Samiel:BAAALAADCggICAAAAA==.Santäter:BAAALAADCgcIBwABLAAECgMIAwAFAAAAAA==.Sargatanas:BAAALAADCgcIDwAAAA==.Sayu:BAABLAAECoEgAAIIAAgItiKnCgAqAwAIAAgItiKnCgAqAwAAAA==.',Sc='Schitan:BAACLAAFFIEFAAIfAAII+RGsJACQAAAfAAII+RGsJACQAAAsAAQKgRYAAh8ABwjhGncoACkCAB8ABwjhGncoACkCAAAA.Schmani:BAAALAAECgUIBQAAAA==.Schmuwu:BAAALAADCgMIAwAAAA==.Schwerg:BAAALAADCggICAABLAAECgMIAwAFAAAAAA==.Scãrlinã:BAAALAAECgQIBAAAAA==.',Se='Secira:BAABLAAECoEcAAITAAcIzyCUMQCGAgATAAcIzyCUMQCGAgAAAA==.Seduka:BAAALAAECgcIDgAAAA==.Seelenfriede:BAABLAAECoEtAAIEAAgIfR7CLwBxAgAEAAgIfR7CLwBxAgAAAA==.Segerazz:BAABLAAECoEVAAICAAYI3RP+nwB/AQACAAYI3RP+nwB/AQAAAA==.Serila:BAABLAAECoEiAAIWAAgIYCBxHwDHAgAWAAgIYCBxHwDHAgAAAA==.Sethmorag:BAAALAADCgMIAwAAAA==.Sevaum:BAAALAAECgcIEAAAAA==.Seyco:BAAALAAECggICAAAAA==.',Sh='Shacks:BAAALAAFFAIIBAAAAQ==.Shadowuwu:BAABLAAECoEbAAIEAAgIYB07JwCZAgAEAAgIYB07JwCZAgAAAA==.Shaduwu:BAAALAADCgEIAQAAAA==.Shalímar:BAABLAAECoExAAILAAgImQZOCwBTAQALAAgImQZOCwBTAQAAAA==.Sheenaya:BAAALAADCgQIBAAAAA==.Shekfang:BAAALAADCgUIBQABLAAECgUICAAFAAAAAA==.Shenphen:BAAALAAECgYICQABLAAFFAIICAAXAIgaAA==.Shirka:BAAALAAECgYIEAAAAA==.Shix:BAAALAAECggIDAABLAAFFAIIBAAFAAAAAQ==.Shiyzuka:BAABLAAECoEYAAIWAAcIHiFPKACaAgAWAAcIHiFPKACaAgAAAA==.',Si='Siegertyp:BAAALAAECgMIAwAAAA==.Sihirbaz:BAAALAAECgcIEQAAAA==.Silverlit:BAAALAADCggICAAAAA==.Sinner:BAAALAADCgIIAgABLAAECgQICQAFAAAAAA==.Sinon:BAABLAAECoEeAAIQAAcI5Rs9IQAtAgAQAAcI5Rs9IQAtAgAAAA==.Sireena:BAAALAAECgUIDgAAAA==.Sirtom:BAABLAAECoEjAAICAAgILw/AgQC2AQACAAgILw/AgQC2AQAAAA==.',Sl='Slace:BAAALAADCgUIBQAAAA==.Slacé:BAAALAADCggIDwAAAA==.Slany:BAAALAADCgcIDQAAAA==.Sláce:BAAALAAECgMIAwAAAA==.',Sn='Snes:BAABLAAECoEoAAICAAgIWibwGAD3AgACAAgIWibwGAD3AgAAAA==.',So='Sodal:BAABLAAECoEbAAIRAAYIPAufRAA3AQARAAYIPAufRAA3AQAAAA==.',St='Sternbräu:BAAALAADCggIEAAAAA==.Sternschauer:BAAALAAECggICAAAAA==.',Su='Sukie:BAAALAAECgUIBQAAAA==.Surbradl:BAAALAAECgYIEgAAAA==.Susannah:BAAALAADCgcIBwAAAA==.Susiohnebot:BAAALAAECgUICAAAAA==.',Sw='Sworduschi:BAAALAADCggIAwAAAA==.',Sy='Syndragos:BAAALAAECgYICQAAAA==.Sypho:BAAALAAECggIAQAAAA==.',['Sâ']='Sâlâmânderîa:BAAALAAECgIIAgAAAA==.',['Sä']='Säbellicht:BAAALAADCgIIAgAAAA==.',['Sé']='Séeéd:BAAALAAECgQICQAAAA==.',['Sê']='Sêrina:BAABLAAECoEjAAIhAAgIpBr2GQCGAgAhAAgIpBr2GQCGAgAAAA==.',Ta='Tadrin:BAAALAAECgEIAQAAAA==.Talrashar:BAAALAADCggICwAAAA==.Taqvia:BAAALAADCggIHwAAAA==.Taryel:BAAALAADCggIEAAAAA==.Tavalian:BAAALAAECggIDgAAAA==.',Te='Teláris:BAAALAADCgIIAgAAAA==.Teraaganeia:BAAALAADCgcICAAAAA==.Teraf:BAAALAADCgcIBwAAAA==.Teriyaki:BAAALAADCggICAAAAA==.',Th='Thalina:BAAALAAECggICAAAAA==.Tharisa:BAABLAAECoEUAAMhAAYIhBEASgBsAQAhAAYIhBEASgBsAQAfAAMIFwkojQCMAAAAAA==.Thariux:BAAALAAECgQIBAABLAAECgYIFAAhAIQRAA==.Thaílanah:BAABLAAECoEaAAIDAAYIexNsjQBjAQADAAYIexNsjQBjAQAAAA==.Theundil:BAABLAAECoEhAAMCAAgI/CN6DwArAwACAAgI/CN6DwArAwAJAAEI7AWKaAAtAAAAAA==.Thondir:BAABLAAECoEjAAIZAAgIiCKrBwAIAwAZAAgIiCKrBwAIAwAAAA==.Thorja:BAABLAAECoEUAAICAAcIqhEkiQCpAQACAAcIqhEkiQCpAQAAAA==.Thundara:BAABLAAECoEdAAMCAAcIlxICggC2AQACAAcIFhACggC2AQAbAAcIMBBLKwBpAQAAAA==.Thuok:BAAALAADCgcIBwAAAA==.',Ti='Tigoro:BAAALAADCggIEQABLAAECgYIBgAFAAAAAA==.Tinman:BAAALAADCgcIBwAAAA==.Tintus:BAAALAAECggIAQAAAA==.Tirifa:BAAALAAECgEIAgABLAAECggIJwAiAK4jAA==.Tirsulfid:BAAALAAECgQIBwAAAA==.',To='Tobeycore:BAAALAAECgIIAgAAAA==.Tobrâx:BAAALAAECggIEwAAAA==.Toka:BAAALAAECgMIAwAAAA==.Torda:BAAALAAECgEIAQAAAA==.Torvî:BAAALAAECgEIAQAAAA==.Totemtobi:BAAALAAECgYIDwAAAA==.',Tr='Trakath:BAABLAAECoEdAAIkAAcInxiFDAAAAgAkAAcInxiFDAAAAgAAAA==.Trevian:BAAALAAECgUIBgABLAAECgcIEwAFAAAAAA==.Trinkverbot:BAABLAAECoEWAAIeAAYIXB9FCQAKAgAeAAYIXB9FCQAKAgABLAAECgYIFgAQACgcAA==.Trusty:BAAALAAECggIAQAAAA==.',Tu='Turtledemo:BAAALAADCggIEQAAAA==.',Tw='Twondil:BAAALAADCggIDgAAAA==.',Ty='Tyrannus:BAAALAAECgcIEgAAAA==.',['Tá']='Tásty:BAAALAAECgMIAwAAAA==.',Un='Unaya:BAABLAAECoEZAAIDAAcImApClwBQAQADAAcImApClwBQAQAAAA==.',Ur='Urathan:BAACLAAFFIEIAAIXAAIIiBqNGQCvAAAXAAIIiBqNGQCvAAAsAAQKgR4AAhcACAhmHeIeAKoCABcACAhmHeIeAKoCAAAA.',Va='Vaenish:BAAALAADCggICAABLAAECgQIBAAFAAAAAA==.Varoz:BAAALAAECgYICAAAAA==.',Ve='Veltar:BAABLAAECoEaAAIZAAcI4R3nFABfAgAZAAcI4R3nFABfAgAAAA==.Ventus:BAAALAADCggICAABLAAECggIFwAcAPkhAA==.Verania:BAAALAAECgYIDQAAAA==.',Vi='Vinoc:BAAALAADCgIIAgAAAA==.Violetnike:BAAALAADCggICAAAAA==.Virga:BAAALAAECgUIDAAAAA==.Visenna:BAAALAADCgMIAwAAAA==.Vivî:BAAALAAECgQIBAABLAAECgcIGgAfACEaAA==.',Vo='Voician:BAAALAAECggIDgAAAA==.Vokar:BAAALAAECgYIDQAAAA==.',Vu='Vulder:BAAALAADCgUIBQAAAA==.',Wa='Wayendran:BAAALAAECgUIDAAAAA==.',We='Weedsthyr:BAAALAAECgEIAQAAAA==.Weltnee:BAABLAAECoEeAAMXAAcIohrMOAAgAgAXAAcIdhrMOAAgAgAZAAcIMRSvfAAoAAABLAAECgcIDAAFAAAAAA==.Weltnoo:BAAALAAECgcIDAAAAA==.Wennofer:BAAALAAECgQIBAAAAA==.',Wh='Whitenike:BAAALAADCgYIBgAAAA==.',Wi='Wiaschtlsira:BAAALAAECgcIDQAAAQ==.Wildstyles:BAAALAAECgcIDQAAAA==.',Wo='Wolfblood:BAAALAADCgUIBQAAAA==.Woodford:BAAALAADCgcIEAAAAA==.',Wu='Wuying:BAAALAADCggICAAAAA==.',Wy='Wyscor:BAAALAADCgcIBwAAAA==.',Xa='Xaloris:BAABLAAECoEgAAIlAAcIkhoCEAAZAgAlAAcIkhoCEAAZAgAAAA==.Xalìtas:BAAALAADCgQIBAAAAA==.Xamesh:BAAALAAECgcIBwAAAA==.Xantharî:BAAALAAECgYICwAAAA==.Xanthya:BAABLAAECoEgAAMBAAcIdhDKHwB7AQABAAcIdhDKHwB7AQAOAAII0gs8TwBrAAAAAA==.',Xe='Xeller:BAAALAADCggIFAAAAA==.Xelsia:BAABLAAECoEgAAIWAAcI1RcmZADUAQAWAAcI1RcmZADUAQAAAA==.',Xh='Xheela:BAAALAAECgMIAwABLAAECgcIDQAFAAAAAA==.',['Xâ']='Xânt:BAAALAADCggILAAAAA==.',['Xä']='Xäres:BAAALAADCggIFAAAAA==.',Ya='Yalani:BAABLAAECoEUAAQfAAgILBPbVQBcAQAfAAUIYBfbVQBcAQAhAAgIFgjwVQA3AQAjAAIIZRZkJQCAAAAAAA==.Yappo:BAABLAAECoEfAAIWAAcISxd6WwDpAQAWAAcISxd6WwDpAQAAAA==.Yazemin:BAAALAADCgUIBQABLAAECgcIHgACALAPAA==.',Yi='Yingau:BAABLAAECoEcAAIOAAcIUgwVLQBqAQAOAAcIUgwVLQBqAQAAAA==.',Yp='Ypsiløn:BAAALAAECgMIAwAAAA==.',Yu='Yukk:BAAALAADCgMIAwAAAA==.Yuliveê:BAABLAAECoEaAAIfAAcIIRpKPgC6AQAfAAcIIRpKPgC6AQAAAA==.',Za='Zarali:BAABLAAECoEhAAIWAAgIfAz+cQC1AQAWAAgIfAz+cQC1AQAAAA==.Zaralija:BAAALAADCgMIAwAAAA==.Zatôx:BAAALAADCggIGAAAAA==.',Zi='Zin:BAAALAADCggIDwAAAA==.Zitroo:BAAALAAECgYIDQABLAAECggIIwAPADIeAA==.',Zu='Zucker:BAABLAAECoEbAAIMAAcIQRjWFQDZAQAMAAcIQRjWFQDZAQAAAA==.Zulumi:BAABLAAECoEbAAIHAAYIuh6GUQDAAQAHAAYIuh6GUQDAAQAAAA==.Zuraal:BAAALAAECgYICgAAAA==.Zurgon:BAAALAADCggIDAAAAA==.',Zy='Zymbal:BAAALAAECgIIAwAAAA==.',['Áe']='Áegwynn:BAABLAAECoEWAAMWAAcI9BWrfgCaAQAWAAcI9BWrfgCaAQAVAAEIAhdCVABAAAABLAAFFAUIEgAOAKsZAA==.Áelora:BAABLAAECoEdAAIRAAcIBRXPJADXAQARAAcIBRXPJADXAQAAAA==.',['Äp']='Äpril:BAABLAAECoEeAAIHAAgIvxieMQAoAgAHAAgIvxieMQAoAgABLAAECggILgAWAK8YAA==.',['Är']='Ärathan:BAAALAAFFAIIAgABLAAFFAIICAAXAIgaAA==.',['Çh']='Çhandra:BAABLAAECoEtAAIRAAgIeiEXCQDtAgARAAgIeiEXCQDtAgAAAA==.',['Ñe']='Ñeferu:BAAALAAECgYIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end