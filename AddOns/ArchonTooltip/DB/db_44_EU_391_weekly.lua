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
 local lookup = {'DeathKnight-Frost','DemonHunter-Havoc','Monk-Brewmaster','Hunter-BeastMastery','Warrior-Fury','Unknown-Unknown','Warlock-Demonology','Hunter-Marksmanship','Paladin-Protection','Druid-Balance','Shaman-Elemental','Rogue-Assassination','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','DemonHunter-Vengeance','Monk-Windwalker','Paladin-Retribution','Priest-Holy','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Mage-Frost','Druid-Feral','Warrior-Protection','DeathKnight-Unholy','Shaman-Enhancement','Mage-Arcane','Warlock-Destruction','Monk-Mistweaver','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warlock-Affliction','Warrior-Arms',}; local provider = {region='EU',realm="Vol'jin",name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aamook:BAAALAAECgIIAgAAAA==.',Ad='Adrakîn:BAABLAAECoEXAAIBAAYIbxkajQCpAQABAAYIbxkajQCpAQAAAA==.',Ae='Aegön:BAAALAAECgMIBAAAAA==.Aelthys:BAABLAAECoEeAAICAAcI3R/INwBXAgACAAcI3R/INwBXAgAAAA==.Aeri:BAAALAADCgMIAwAAAA==.Aesily:BAAALAAECggICgAAAA==.',Af='Affix:BAAALAADCggICAAAAA==.',Ai='Aindreas:BAAALAADCgIIAQAAAA==.Aino:BAABLAAECoEcAAIDAAcIrR4dDgBNAgADAAcIrR4dDgBNAgAAAA==.',Ak='Akîrä:BAAALAAECgYICgAAAA==.',Al='Alakajir:BAABLAAECoEdAAIEAAgIRhyDLwBeAgAEAAgIRhyDLwBeAgAAAA==.Alandilas:BAABLAAECoEgAAIFAAgIexx3IwCMAgAFAAgIexx3IwCMAgAAAA==.Aldéha:BAAALAAECgcIDgAAAA==.Alfirk:BAAALAADCggICAABLAAECgMIBAAGAAAAAA==.Allirâsa:BAAALAADCgYIBgAAAA==.',An='Angbanddetyr:BAAALAAECgEIAQAAAA==.Angelic:BAABLAAECoEVAAIHAAYIARD8NAB4AQAHAAYIARD8NAB4AQAAAA==.Angron:BAAALAADCgEIAQAAAA==.Anthowarlike:BAAALAADCggIJwAAAA==.Antiles:BAAALAADCgcIDwAAAA==.Anwyn:BAABLAAECoEgAAICAAgISSDvJQCmAgACAAgISSDvJQCmAgAAAA==.',Ar='Aramos:BAABLAAECoEZAAIEAAcIyhGQdgCRAQAEAAcIyhGQdgCRAQAAAA==.Arckhos:BAAALAADCggICAAAAA==.Ariekor:BAAALAAECgcIEQAAAA==.Artessia:BAABLAAECoEnAAIIAAgIniL8DADwAgAIAAgIniL8DADwAgAAAA==.',As='Ashpal:BAAALAAECgYIDAAAAA==.Aslhan:BAAALAADCggICgAAAA==.Asmodus:BAAALAAECgYIBgAAAA==.Asthya:BAABLAAECoEUAAIJAAcI1Bf8IAC4AQAJAAcI1Bf8IAC4AQAAAA==.Astrania:BAAALAAECgIIAgAAAA==.Astrâ:BAAALAAECggICAAAAA==.Asuia:BAAALAAECgIIAwAAAA==.Asunä:BAAALAADCggIJQABLAAECgYICwAGAAAAAA==.',At='Ataez:BAAALAADCgYIBgAAAA==.',Au='Aurinko:BAAALAAECgMIBAAAAA==.',Av='Aveldro:BAAALAAECgMIAQAAAA==.',Az='Azhur:BAAALAADCgYIBgAAAA==.Azmu:BAAALAADCggIDwAAAA==.Azn:BAAALAAECgcIDQAAAA==.',Ba='Balthazarius:BAAALAADCggICAAAAA==.Balzac:BAAALAADCgYICAAAAA==.Barrique:BAAALAADCgQIBAAAAA==.Base:BAAALAAECggIAQABLAAECggIEgAGAAAAAA==.Bayard:BAAALAADCgYIBwAAAA==.',Be='Bellabeca:BAAALAAECgcIDQABLAAECggIJAAKAOIQAA==.',Bi='Biddibulle:BAAALAADCgYIBgAAAA==.Bigelcham:BAABLAAECoEXAAILAAcIoBT1PQDiAQALAAcIoBT1PQDiAQAAAA==.Bikop:BAAALAAECgYIBgAAAA==.Bili:BAABLAAECoEhAAIMAAcImRS2LACtAQAMAAcImRS2LACtAQAAAA==.',Bl='Blackblues:BAAALAAECgYIDQAAAA==.Blackmamer:BAABLAAECoEiAAINAAgIHB3ACQCWAgANAAgIHB3ACQCWAgAAAA==.Blïnnkk:BAAALAAECgYIDgAAAA==.',Bo='Bodard:BAAALAAFFAIIAwAAAA==.Bodjjackk:BAAALAAECgEIAgAAAA==.Bonchamps:BAAALAAECgUIDQAAAA==.Borch:BAAALAAECgMIBQAAAA==.Boreale:BAABLAAECoEbAAIIAAYIohAnZwAMAQAIAAYIohAnZwAMAQAAAA==.Bouliaug:BAAALAADCgEIAQAAAA==.Boykäh:BAAALAADCgEIAQABLAADCgcIDQAGAAAAAA==.',Br='Breakiss:BAAALAAECgYICgAAAA==.Brisac:BAABLAAECoEhAAIEAAgIogp/gQB7AQAEAAgIogp/gQB7AQAAAA==.Briviac:BAAALAAECgIIAgAAAA==.Brîgitte:BAAALAADCgcICQAAAA==.Brøm:BAAALAAECgYIBgABLAAECggIJgAOAKYdAA==.',['Bâ']='Bâlder:BAAALAAECgEIAQAAAA==.',Ca='Cactuar:BAAALAAECgUICwAAAA==.Cakoli:BAAALAADCggIBwAAAA==.Caliawën:BAAALAAECgEIAQAAAA==.Callum:BAABLAAECoEZAAIHAAcILgyNMQCGAQAHAAcILgyNMQCGAQAAAA==.Calypsø:BAAALAAECgIIAgAAAA==.Carloman:BAAALAADCgYIBgAAAA==.Carryme:BAABLAAFFIEGAAIPAAII0yGEEADHAAAPAAII0yGEEADHAAAAAA==.Cathelyn:BAABLAAECoEXAAIQAAYIYxd0EwBhAQAQAAYIYxd0EwBhAQAAAA==.Catsan:BAAALAAECgYIBgABLAAECggIJAAKAOIQAA==.Catsays:BAAALAADCgMIAwAAAA==.',Ce='Celange:BAAALAADCggIDgABLAAECggIJAAKAOIQAA==.Celeas:BAAALAAECgIIAgAAAA==.Celsius:BAAALAAECgcIDAAAAA==.Cerf:BAAALAADCgcIGAAAAA==.',Ch='Chagun:BAABLAAECoEhAAMEAAgIuSBkHwCrAgAEAAgIuSBkHwCrAgAIAAII0RS/nABZAAAAAA==.Chamanflex:BAAALAAECgYIBgABLAAECggIIwARAMwUAA==.Chamanne:BAAALAADCgMIAwAAAA==.Chamdark:BAAALAADCgEIAQAAAA==.Chassounico:BAAALAADCgcIEAAAAA==.Chaussette:BAAALAAECgcIEQAAAA==.Chenfen:BAABLAAECoEkAAISAAgI8RhnGQAOAgASAAgI8RhnGQAOAgAAAA==.Chicken:BAAALAADCggIGAABLAAECgMIAwAGAAAAAA==.Chiplune:BAAALAADCgIIAgAAAA==.Chouubi:BAAALAAECgYICwAAAA==.Choüpi:BAAALAAECgUIBwAAAA==.Chrismad:BAABLAAECoEaAAITAAcItAbg5gD2AAATAAcItAbg5gD2AAAAAA==.Chémi:BAAALAADCggICAAAAA==.',Ci='Cinquante:BAAALAAECgEIAQABLAAECggINgAPAMcNAA==.',Cl='Clementina:BAAALAADCggIFAAAAA==.Clâff:BAABLAAECoEhAAQUAAcInBwzLAAVAgAUAAcInBwzLAAVAgAVAAYIYw68WgAhAQAWAAII7QfyLABPAAAAAA==.Clédetreize:BAAALAAECgIIAgAAAA==.',Co='Cobax:BAAALAAECgEIAQAAAA==.Cobrablanc:BAAALAAECgEIAgAAAA==.Codo:BAAALAADCggIFgAAAA==.',Cr='Cradock:BAAALAADCgYIBgAAAA==.Crakoo:BAAALAADCggICAAAAA==.',Cu='Cunikael:BAAALAADCggIFwAAAA==.',Cy='Cydia:BAABLAAECoEdAAIXAAcIYw2GhgA5AQAXAAcIYw2GhgA5AQAAAA==.Cyndy:BAAALAAECgYIBgABLAAECggIJAAKAOIQAA==.',['Cé']='Céliane:BAAALAADCgcIDgAAAA==.',Da='Dagahra:BAAALAADCgcIBwAAAA==.Dai:BAAALAAECgcIBwABLAAECggIFgAYACUfAA==.Daranor:BAAALAADCggIEQAAAA==.Darkelectra:BAAALAADCgQIBAAAAA==.Darkfox:BAAALAADCgYIDAAAAA==.Darklola:BAAALAAECgIIAgAAAA==.Darkujä:BAAALAADCgMIAwAAAA==.Darkxof:BAAALAADCggIHgABLAAECggIIAAPAGQdAA==.',De='Deadhuntter:BAABLAAECoEpAAIIAAgIdxeBKQASAgAIAAgIdxeBKQASAgAAAA==.Deepinside:BAAALAAECggIDgAAAA==.Dekaatlon:BAAALAAECgcIEQAAAA==.Delawyn:BAABLAAECoEUAAIZAAcIog0iIABpAQAZAAcIog0iIABpAQAAAA==.Demelza:BAAALAAECgYICQAAAA==.Denverstraza:BAAALAAECgQIBQAAAA==.Desideria:BAAALAAECgUIBQAAAA==.Devam:BAAALAAECgQIBAABLAAFFAIIBwALAN4dAA==.Dexcalibur:BAAALAAECgEIAQAAAA==.Dexide:BAABLAAECoEbAAIVAAgIjh9qFAC2AgAVAAgIjh9qFAC2AgAAAA==.',Di='Dimra:BAABLAAECoEkAAMXAAgIqhtUHwB2AgAXAAgIqhtUHwB2AgALAAQIyRBcfwDvAAAAAA==.Dinadi:BAAALAAECgYICgAAAA==.',Dj='Djedje:BAACLAAFFIEJAAIEAAQIESFXCQB6AQAEAAQIESFXCQB6AQAsAAQKgScAAwQACAgpJb0FAFIDAAQACAggJb0FAFIDAAgABwjJH7YoABYCAAAA.Djogo:BAAALAAFFAIIBAABLAAFFAQICwADAOQiAA==.Djuskarow:BAAALAAFFAIIBAABLAAFFAQICwADAOQiAA==.Djuskho:BAAALAAECgQIBAABLAAFFAQICwADAOQiAA==.Djusko:BAACLAAFFIELAAIDAAQI5CIMBACeAQADAAQI5CIMBACeAQAsAAQKgScAAwMACAijJqMAAIIDAAMACAijJqMAAIIDABIAAQiBFJ5WAEAAAAAA.',Do='Dondaflexx:BAABLAAECoEjAAIRAAgIzBSzFQDuAQARAAgIzBSzFQDuAQAAAA==.Donddaflexx:BAAALAAECgYICAABLAAECggIIwARAMwUAA==.Dougi:BAAALAAECgIIAgAAAA==.',Dr='Draugur:BAAALAAECgYIEAAAAA==.Drogur:BAAALAAECgYIDwAAAA==.Druiok:BAAALAADCggICAAAAA==.Drôgur:BAAALAAECgQIBAAAAA==.',Dw='Dwarderon:BAAALAADCggICAAAAA==.',['Dà']='Dànte:BAAALAAECgEIAQAAAA==.',['Dï']='Dïnadrion:BAABLAAECoEcAAIUAAgI7RkBHAB3AgAUAAgI7RkBHAB3AgAAAA==.',Ea='Eadric:BAAALAAECgEIAQAAAA==.',Ed='Eddiedh:BAAALAAECgYIEwAAAA==.',Ee='Eeva:BAAALAADCgcIBwAAAA==.',Ef='Eferalgant:BAAALAADCggIDQAAAA==.Efilie:BAAALAAECgIIAgAAAA==.',El='Elfeblanca:BAAALAADCgcIBwAAAA==.Eloon:BAAALAAECgYICQAAAA==.Elunya:BAAALAADCgEIAQABLAAECgIIAgAGAAAAAA==.Elylia:BAABLAAECoEbAAIVAAcIlxFIOwCxAQAVAAcIlxFIOwCxAQAAAA==.Elzbietta:BAAALAADCgYIBgAAAA==.',En='Enahpets:BAAALAAECgEIAQAAAA==.Enrobb:BAAALAAECgIIAgABLAAECgYIEgAGAAAAAA==.Entité:BAABLAAECoEiAAIPAAgIVyG8CQD1AgAPAAgIVyG8CQD1AgAAAA==.',Eo='Eowend:BAAALAAECgEIAQAAAA==.',Er='Erénäly:BAAALAADCggICAABLAAFFAIIBgACAMsgAA==.',Et='Etèrnèl:BAAALAADCggICAAAAA==.',Ex='Exu:BAAALAAECgYIDwAAAA==.',Ey='Eykira:BAAALAAECgYIDAAAAA==.',Ez='Ezekia:BAAALAAECgYIEwAAAA==.',Fa='Faenor:BAAALAADCgIIAgAAAA==.',Fe='Feijoa:BAABLAAECoEgAAMEAAgIHBAvaQCwAQAEAAgIHBAvaQCwAQAIAAUIcQilfADBAAAAAA==.Feitan:BAAALAADCggICgAAAA==.Fendlabrise:BAAALAAECgcIDAABLAAECggIJAAKAOIQAA==.',Fi='Filledenyx:BAAALAADCggIFAAAAA==.Filypesto:BAAALAAECgcICwAAAA==.',Fo='Formapal:BAAALAADCggICQAAAA==.',Fr='Fraziel:BAABLAAECoEaAAIIAAcIYhjoRQCFAQAIAAcIYhjoRQCFAQAAAA==.Fresh:BAAALAAECgYIDAAAAA==.Frickyd:BAACLAAFFIEIAAIaAAMI9RS+CgDGAAAaAAMI9RS+CgDGAAAsAAQKgR8AAhoACAiHHBUSAHwCABoACAiHHBUSAHwCAAAA.Frickyx:BAABLAAECoEcAAIQAAgIFx5hBAC5AgAQAAgIFx5hBAC5AgABLAAFFAMICAAaAPUUAA==.Frigouille:BAAALAAFFAIIAwABLAAFFAQICQAEABEhAQ==.Fryka:BAAALAADCgcICQAAAA==.',Fy='Fyraa:BAAALAADCggIEAABLAAFFAIIBgACAMsgAA==.',['Fê']='Fêlicîa:BAAALAAECgQICQAAAA==.',['Fë']='Fëlicia:BAACLAAFFIEJAAIbAAQIaBJJAgBNAQAbAAQIaBJJAgBNAQAsAAQKgRsAAhsACAghIrIHAM0CABsACAghIrIHAM0CAAAA.',Ga='Gaby:BAAALAAECgMIBQAAAA==.Gainor:BAAALAADCggICAAAAA==.Gandall:BAAALAAECggICAAAAA==.Garrlax:BAAALAAECgUIBQAAAA==.',Ge='Gerbeux:BAAALAAECgEIAQAAAA==.',Gi='Givräa:BAAALAAECgYIDAABLAAFFAIIBgACAMsgAA==.',Go='Goldie:BAAALAAFFAIIBAAAAA==.Goodold:BAAALAADCggIKwAAAA==.',Gr='Graben:BAAALAAECggIEAAAAA==.Grazax:BAAALAAECgYIBwAAAA==.Griguef:BAAALAAECgYIDAAAAA==.Grimmjow:BAAALAADCgIIAgAAAA==.',Gu='Guyle:BAAALAADCgUIBgAAAA==.',Gw='Gwennyn:BAAALAAECgcIBwAAAA==.',Ha='Haldis:BAAALAADCgEIAQAAAA==.Haldiss:BAAALAADCgcIDQAAAA==.Haldistress:BAAALAADCgIIAgAAAA==.Hambre:BAAALAADCgMIBQABLAAECgYIEAAGAAAAAA==.Hatchi:BAAALAADCgYIBgAAAA==.Hattorï:BAABLAAECoEXAAIEAAgIxAaMqgArAQAEAAgIxAaMqgArAQAAAA==.Hayashi:BAAALAADCgYIBgAAAA==.Hayasuky:BAAALAADCgcIEAAAAA==.',He='Healéryâ:BAAALAADCgcIBwAAAA==.Hemoroïdoz:BAAALAADCggIDgAAAA==.Henzu:BAAALAADCgYIBgAAAA==.Herion:BAAALAAECggIDwABLAAFFAIIBwALAN4dAA==.Herkala:BAAALAADCgIIAgAAAA==.Hexumed:BAAALAAECgYIBgABLAAECgYIDwAGAAAAAA==.',Hi='Hidemaker:BAABLAAECoEWAAQKAAYIQQxlYQDxAAAKAAUIHQxlYQDxAAAPAAQI5xJzfADkAAAZAAYIvAf3NQCAAAAAAA==.Hikoroma:BAABLAAECoEWAAIcAAYIzhDhFABxAQAcAAYIzhDhFABxAQABLAAFFAIICAAdAAofAA==.Hirocham:BAAALAAECgQIBgAAAA==.Hizalina:BAABLAAECoEaAAIUAAgIjRnmMwDtAQAUAAgIjRnmMwDtAQABLAAFFAMIBQAHAFEQAA==.',Ho='Hokdk:BAAALAAECgQIBQAAAA==.',Hy='Hypak:BAAALAAECgEIAQAAAA==.',['Hé']='Hélène:BAAALAADCggIJAAAAA==.',['Hï']='Hïsoka:BAAALAADCggIDgAAAA==.',['Hø']='Hødle:BAAALAADCggIBwAAAA==.Høtcho:BAAALAAECgMIAwAAAA==.',['Hü']='Hüxley:BAACLAAFFIEFAAMHAAMIURBIFwB7AAAHAAIIQAVIFwB7AAAeAAMIURAAAAAAAAAsAAQKgR8AAx4ACAgnG6cmAIMCAB4ACAjdGKcmAIMCAAcABgjpF1spALABAAAA.',Ia='Ianoush:BAAALAADCgcIBwAAAA==.',Ib='Ibuprofen:BAAALAAECggIEwAAAA==.',Ic='Icemen:BAAALAADCggIHAAAAA==.',Id='Ideum:BAABLAAECoEcAAIMAAcI7Rp6GQA5AgAMAAcI7Rp6GQA5AgAAAA==.Idkhowtogrip:BAAALAAECgYIBgABLAAFFAMICAACAOoiAA==.Idrila:BAAALAAECgYICwAAAA==.',Il='Illiciaa:BAAALAAECgUICgAAAA==.Illiciae:BAAALAADCggIEwAAAA==.Illidash:BAAALAAECgEIAQAAAA==.Illuminatus:BAAALAAECgEIAQAAAA==.Ilmoi:BAAALAAECgEIAQAAAA==.Ilokime:BAABLAAECoElAAIPAAgI5BsjHgBRAgAPAAgI5BsjHgBRAgAAAA==.Ilythe:BAAALAAECgcIDQABLAAFFAIIBwALAN4dAA==.',In='Ingwiel:BAABLAAECoEtAAIHAAgI9A7vJgC7AQAHAAgI9A7vJgC7AQAAAA==.',Is='Ishijo:BAAALAADCgYIBgAAAA==.Ishikix:BAAALAADCgMIBQAAAA==.Isyan:BAACLAAFFIEFAAIUAAIIWSHzFgC7AAAUAAIIWSHzFgC7AAAsAAQKgR4AAhQACAjcHb8PANQCABQACAjcHb8PANQCAAEsAAQKCAggABAA2yMA.',Iz='Iz:BAAALAADCggIEAAAAA==.Izronod:BAAALAAECgYIBgAAAA==.',['Iä']='Iäe:BAAALAAECgQICQAAAA==.',Ja='Jahouaka:BAAALAAECgEIAQAAAA==.Jakekill:BAABLAAECoElAAIMAAgIKhMkGwArAgAMAAgIKhMkGwArAgAAAA==.Jamenia:BAAALAADCggICAAAAA==.Jaugrain:BAAALAADCgcIFgAAAA==.Jaypatousheo:BAABLAAECoEWAAIYAAgIJR9vCwDIAgAYAAgIJR9vCwDIAgAAAA==.Jaï:BAABLAAECoEeAAILAAgIhx7XFQDOAgALAAgIhx7XFQDOAgAAAA==.',Jo='Johnmacbobby:BAABLAAECoEfAAMTAAcIWxPwwQBCAQATAAcIWxPwwQBCAQAOAAYIjgflRAAIAQAAAA==.Jorgen:BAAALAADCgYIBwAAAA==.',Ju='Juska:BAAALAAECgYICgAAAA==.Jusklock:BAAALAAECgIIAgAAAA==.',Ka='Kaelden:BAACLAAFFIEIAAMRAAMIthsJAwABAQARAAMIthsJAwABAQACAAII/wpFOQCJAAAsAAQKgSoAAwIACAg+ITAYAPACAAIACAgpITAYAPACABEAAQjMIm9LAGQAAAAA.Kagemitsu:BAAALAAECgMIBAAAAA==.Kagrenac:BAAALAAECgUIBQAAAA==.Kainblade:BAAALAADCggICAAAAA==.Kalab:BAABLAAECoEkAAIXAAgI8R29GACbAgAXAAgI8R29GACbAgAAAA==.Kapteyn:BAAALAAECgUICAAAAA==.Kardyss:BAAALAAECgcICwAAAA==.Karole:BAAALAAECgIIAwAAAA==.Kathmandu:BAABLAAECoEkAAIKAAgI4hBUNAC8AQAKAAgI4hBUNAC8AQAAAA==.Kaÿn:BAAALAAECggICgAAAA==.',Ke='Kenavö:BAAALAADCggIHAAAAA==.Kenryo:BAABLAAECoEaAAICAAcICh93OABUAgACAAcICh93OABUAgAAAA==.Keyalerhouse:BAAALAADCgcIDQAAAA==.Keïzho:BAAALAADCgMIAwAAAA==.',Kh='Khaleesî:BAAALAAECggIBwABLAAECggIJAAKAOIQAA==.Kheallerbaal:BAAALAAECgYIDAABLAAECgYIGAAeADgaAA==.Khensi:BAAALAADCgYIBgAAAA==.Khiliãna:BAAALAAECgUIBQAAAA==.Khione:BAAALAADCgQIBQAAAA==.Khocayine:BAAALAADCgcIBwAAAA==.Khourouk:BAAALAADCgIIAgAAAA==.Khoursk:BAAALAADCgYIBQAAAA==.Khrystall:BAAALAADCgcIDQAAAA==.Khrÿstall:BAAALAAECgcIEwAAAA==.',Ki='Kialys:BAAALAAECgYIBgAAAA==.Killerbaal:BAABLAAECoEYAAIeAAYIOBqlTgDTAQAeAAYIOBqlTgDTAQAAAA==.Killerbhaahl:BAAALAAECgYICgABLAAECgYIGAAeADgaAA==.Killerblood:BAAALAAECgYIEgABLAAECgYIGAAeADgaAA==.Kilowog:BAAALAAECgQICQAAAA==.Kirozan:BAAALAAECgIIBAAAAA==.',Ko='Koban:BAABLAAECoEhAAICAAcILCW8HgDLAgACAAcILCW8HgDLAgAAAA==.Kobsinette:BAABLAAECoEWAAMVAAcIhREfPACtAQAVAAcIhREfPACtAQAUAAMIwwpbjgCIAAAAAA==.Kohva:BAAALAAECgYICAAAAA==.Kongzi:BAAALAADCgYIBgABLAAECggIJAAKAOIQAA==.Korkhan:BAAALAAECgYICwAAAA==.',Kr='Krakoo:BAABLAAECoEkAAMYAAcI/Rq7IgDlAQAYAAcI/Rq7IgDlAQAdAAEIvQHr6gAYAAAAAA==.Krakou:BAAALAADCgcICQAAAA==.',Ku='Kumano:BAABLAAECoEgAAIVAAgILgdzRgB7AQAVAAgILgdzRgB7AQAAAA==.Kurzen:BAAALAADCgEIAQAAAA==.Kurzu:BAAALAAECggIBgAAAA==.',Kw='Kwäk:BAAALAAECgEIAQABLAAECgcIJgAJAA4hAA==.',Ky='Kyel:BAAALAAECggIEgAAAA==.Kylianã:BAABLAAECoEbAAICAAYI2xhViQCFAQACAAYI2xhViQCFAQAAAA==.Kyliøna:BAAALAADCgcICQAAAA==.Kylrïss:BAAALAAECgYIEAAAAA==.Kynalïa:BAAALAADCgEIAQAAAA==.Kysendra:BAAALAADCgYICAAAAA==.',Kz='Kzey:BAACLAAFFIEIAAICAAMI6iJaDwATAQACAAMI6iJaDwATAQAsAAQKgRgAAgIACAjMJZQKAEADAAIACAjMJZQKAEADAAAA.',['Kâ']='Kâli:BAAALAADCgEIAQAAAA==.',['Ké']='Kétta:BAAALAADCggICAAAAA==.',['Kø']='Kørbustiøn:BAAALAADCgEIAQAAAA==.',La='Labomba:BAAALAADCggIDwAAAA==.Lagoulue:BAAALAADCgYIBgAAAA==.Laidlyworm:BAAALAADCgcIDQAAAA==.Lavalaisanne:BAAALAAECgYICAAAAA==.Laverde:BAABLAAECoEoAAIeAAYIcAj7jQAhAQAeAAYIcAj7jQAhAQABLAAECggINgAPAMcNAA==.',Le='Legandel:BAAALAAECggIEgAAAA==.Legeek:BAAALAADCgYICQAAAA==.Legelindd:BAAALAAECgQIBAAAAA==.Lenwe:BAAALAAECggIEQAAAA==.Lepere:BAAALAADCgcIBwAAAA==.Letmekissyou:BAAALAADCgcIFwAAAA==.',Li='Lioubia:BAAALAADCgQIBAAAAA==.Lisacendress:BAAALAAECgUIBgAAAA==.Littlegwëndo:BAAALAADCgcICQAAAA==.',Ll='Llauroncius:BAAALAAECgQIBAABLAAECggIIAACAEkgAA==.',Lo='Lopin:BAABLAAECoEcAAIfAAcIJhMbGwCtAQAfAAcIJhMbGwCtAQAAAA==.Loubleue:BAABLAAECoEkAAIaAAgIJB0DDwCgAgAaAAgIJB0DDwCgAgAAAA==.Loumas:BAAALAADCgYIBgAAAA==.',Lu='Ludeka:BAAALAADCgcIBwAAAA==.Luluxy:BAAALAAECgIIAgAAAA==.Lunah:BAAALAADCgEIAQAAAA==.Lunathiel:BAAALAADCggICAAAAA==.Lunatikos:BAAALAAECgYIEQAAAA==.Lunelya:BAAALAADCgMIAwAAAA==.',Ly='Lydwïn:BAAALAAECgUIBQAAAA==.Lyraël:BAAALAADCggIDgAAAA==.Lysandra:BAAALAADCggICQAAAA==.',Ma='Macflight:BAAALAAECgYIDAAAAA==.Magodepo:BAAALAADCgUIBQAAAA==.Mahiru:BAAALAAECgYIBgAAAA==.Maiia:BAABLAAECoEmAAIEAAgIwRymNQBFAgAEAAgIwRymNQBFAgAAAA==.Malaryäa:BAACLAAFFIEGAAICAAIIyyAfGwC6AAACAAIIyyAfGwC6AAAsAAQKgScAAgIACAheJA0KAEMDAAIACAheJA0KAEMDAAAA.Malbarrée:BAEBLAAECoEaAAITAAcIGyBCXQACAgATAAcIGyBCXQACAgABLAAECggIGQAZAIUXAA==.Malice:BAAALAADCgQIBAAAAA==.Mallunée:BAEBLAAECoEZAAIZAAgIhRc7DgBFAgAZAAgIhRc7DgBFAgAAAA==.Malocanine:BAAALAAECgUICQAAAA==.Malé:BAABLAAECoEbAAIHAAYI4x0gIwDRAQAHAAYI4x0gIwDRAQAAAA==.Manðør:BAAALAAECgYIDAABLAAECgcIEwAGAAAAAA==.Mathania:BAAALAAECgYIBgAAAA==.Maxbosse:BAAALAAECgQIBAABLAAECgYIHQAEAIUfAA==.',Me='Medav:BAAALAAECgYIEAAAAA==.Medavv:BAAALAADCgUIBQABLAAECgYIEAAGAAAAAA==.Medjin:BAAALAADCggIDgAAAA==.Meduse:BAAALAAECgYIEAABLAAECggIJAAKAOIQAA==.Medzer:BAACLAAFFIEIAAIdAAMIJAy4HgDYAAAdAAMIJAy4HgDYAAAsAAQKgR0AAh0ACAjjFsBEABsCAB0ACAjjFsBEABsCAAAA.Megazombie:BAAALAAECgYIDAAAAA==.Mell:BAAALAADCgcIBwAAAA==.',Mi='Micrognøme:BAAALAAECgQIBgAAAA==.Microlax:BAAALAAECgYIDwAAAA==.Mihtzen:BAAALAAECgYIDwAAAA==.Mimelone:BAAALAADCgcICwAAAA==.',Mo='Moideux:BAAALAADCgEIAQAAAA==.Moinouille:BAAALAAECgYICQAAAA==.Moonkiss:BAAALAADCggIFQAAAA==.Morphéis:BAAALAADCgcICgABLAAECggIJwAIAJ4iAA==.Moî:BAAALAADCgcIDgAAAA==.',Mu='Multani:BAABLAAECoEcAAIIAAYIFCLNLwDtAQAIAAYIFCLNLwDtAQAAAA==.',My='Myù:BAAALAAECgIIBAAAAA==.',['Mà']='Màrika:BAAALAAECgYIDgAAAA==.',['Må']='Månå:BAAALAADCgYIBgAAAA==.',['Mé']='Mévlock:BAABLAAECoEeAAIHAAgIPBNQGgAJAgAHAAgIPBNQGgAJAgAAAA==.',['Më']='Mëth:BAAALAADCggIIAABLAAECgcIJAAQAA4kAA==.Mëthan:BAABLAAECoEkAAIQAAcIDiSiAwDZAgAQAAcIDiSiAwDZAgAAAA==.',['Mî']='Mîssouf:BAAALAADCggIEAABLAAECggIJAAKAOIQAA==.',['Mô']='Môi:BAAALAAECgcIBwAAAA==.',['Mø']='Mørfine:BAABLAAECoEcAAIPAAgIlx26EwCaAgAPAAgIlx26EwCaAgAAAA==.',Na='Nabøu:BAABLAAECoEhAAMXAAgIMRUjRADpAQAXAAgIMRUjRADpAQALAAMIfA1aigC3AAAAAA==.Nagios:BAAALAAECgYICgAAAA==.Nagrosh:BAABLAAECoEZAAIFAAcIbCLVHwCkAgAFAAcIbCLVHwCkAgAAAA==.Namixie:BAABLAAECoEXAAIgAAcImwdkIgAWAQAgAAcImwdkIgAWAQAAAA==.Nanöu:BAAALAAECgcIDgAAAA==.Narsiss:BAAALAAECgEIAQAAAA==.Nassiim:BAAALAAECgYICgAAAA==.Nasuada:BAAALAADCggICAABLAAECgcIEwAGAAAAAA==.Naysa:BAAALAADCggIDgAAAA==.',Ne='Nearkhos:BAAALAADCgYIBgAAAA==.Necrodrake:BAACLAAFFIEJAAMgAAMIqgcpCgDCAAAgAAMIqgcpCgDCAAAhAAIIIwuDFgCIAAAsAAQKgSsAAyIACAjeHmMDAJICACIACAjiGmMDAJICACEACAgUG9YVAGECAAAA.Necromonger:BAAALAAECgYIDAABLAAFFAMICQAgAKoHAA==.Nehta:BAAALAADCgcIBwABLAADCggICAAGAAAAAA==.Nehtar:BAAALAADCggICAAAAA==.Nekfà:BAAALAAECgMIBQABLAAFFAQIEAAVADQiAA==.Nekfâ:BAACLAAFFIEQAAMVAAQINCLIBwCEAQAVAAQINCLIBwCEAQAUAAMIfhzxDAAJAQAsAAQKgUMAAxUACAjyJdgEAFIDABUACAjyJdgEAFIDABQACAg9I+MGACgDAAAA.Neshndras:BAAALAAECggICgAAAA==.Nesliors:BAABLAAECoEVAAIBAAcIlhtfVgAZAgABAAcIlhtfVgAZAgAAAA==.Nessahoney:BAAALAADCgEIAQAAAA==.Nessypew:BAAALAADCgEIAQAAAA==.',Ni='Nieur:BAAALAAECgIIAwAAAA==.Nightelfeman:BAAALAADCgcIBwAAAA==.Nikie:BAAALAAECgQIBAAAAA==.Niniapaspeur:BAAALAADCgYIBgAAAA==.Ninodrood:BAAALAADCggIFgAAAA==.Niro:BAACLAAFFIEHAAILAAII3h1wHACbAAALAAII3h1wHACbAAAsAAQKgSAAAgsACAi5HFIdAJUCAAsACAi5HFIdAJUCAAAA.Nirvanna:BAAALAADCggIBQAAAA==.',No='Normà:BAAALAADCgEIAQAAAA==.Norâh:BAAALAAECgMIAwAAAA==.Notharius:BAAALAADCggIDAAAAA==.Noyz:BAAALAAECgcIBwAAAA==.',Np='Npsaarrive:BAABLAAECoEgAAMLAAgIHBLZNQAHAgALAAgIHBLZNQAHAgAXAAYI8AI40QCnAAAAAA==.',Nu='Nualan:BAAALAADCggIDQAAAA==.',Ny='Nyffa:BAAALAAECgEIAQAAAA==.',['Nï']='Nïell:BAAALAAECgEIAQAAAA==.',Od='Odrix:BAACLAAFFIEIAAIdAAIICh8lKQCoAAAdAAIICh8lKQCoAAAsAAQKgSQAAh0ACAj1IB0YAOYCAB0ACAj1IB0YAOYCAAAA.',Oh='Ohkvir:BAAALAADCggIIgAAAA==.',Oi='Oijnazd:BAAALAADCgMIAwAAAA==.',Ok='Okam:BAAALAADCgIIAgAAAA==.Okbar:BAAALAAECgYIEQAAAA==.',Op='Opax:BAAALAAECgEIAQAAAA==.Opàx:BAABLAAECoEXAAITAAYIzg+XqQBuAQATAAYIzg+XqQBuAQAAAA==.',Or='Orgruk:BAAALAAECgcIDgAAAA==.',Os='Oshova:BAABLAAECoEkAAITAAcIKhstUAAjAgATAAcIKhstUAAjAgAAAA==.',Ot='Otochout:BAAALAADCggIDQABLAAECggIEQAGAAAAAA==.',Oz='Ozztralie:BAABLAAECoEaAAIdAAgIDxevQgAjAgAdAAgIDxevQgAjAgAAAA==.',Pa='Pakaaru:BAAALAAECgEIAQAAAA==.Palafox:BAAALAAECgYICwAAAA==.Paliakov:BAAALAAECgYIDgAAAA==.Pample:BAAALAADCgQIBAAAAA==.Pandøøræ:BAAALAAECgYIBgAAAA==.Paristgernin:BAAALAADCgcICAABLAAECgYIEAAGAAAAAA==.Pastilina:BAAALAAECgEIAQAAAA==.Patateheu:BAABLAAECoEcAAMOAAgI0BkZHQD7AQAOAAcIVBgZHQD7AQATAAcINQxMlgCQAQAAAA==.Pattobeurre:BAABLAAECoEgAAIQAAgI2yPRAQA0AwAQAAgI2yPRAQA0AwAAAA==.Pattoketchup:BAAALAAECgQIBAABLAAECggIIAAQANsjAA==.Pattopesto:BAAALAADCgUIBQABLAAECggIIAAQANsjAA==.',Pe='Pellopée:BAABLAAECoEZAAIVAAYI2B7cNgDIAQAVAAYI2B7cNgDIAQABLAAFFAIICAAdAAofAA==.Petya:BAAALAAECggIEgAAAA==.',Ph='Phoenicis:BAAALAAECgMIBAAAAA==.',Pi='Pizzu:BAAALAAECgYIDAAAAA==.',Pl='Plassébo:BAAALAAECgYIBwAAAA==.',Po='Poirewilliam:BAAALAADCgcICAAAAA==.',Pr='Process:BAAALAAECgEIAQAAAA==.Propa:BAAALAADCgcIBwAAAA==.',['Pî']='Pîtch:BAAALAADCgcIBwAAAA==.',Ra='Raazgul:BAAALAADCgYIDAAAAA==.Raimana:BAAALAAECgYICAAAAA==.Rajab:BAAALAAECgcIDQAAAA==.Raskarkapak:BAAALAADCgMIAwABLAAECgcIHAAXAIoeAA==.',Re='Recyprøk:BAAALAAECgcIEwAAAA==.Redmasteur:BAAALAAECgYICgAAAA==.Reza:BAABLAAECoEVAAIOAAcI4RkdGAAjAgAOAAcI4RkdGAAjAgAAAA==.Reïgna:BAABLAAECoEhAAIRAAcIixdDGgC7AQARAAcIixdDGgC7AQAAAA==.',Rh='Rhâa:BAAALAAECggIDQAAAA==.Rhânnax:BAAALAADCggICQAAAA==.',Ri='Ricco:BAAALAAECgEIAQAAAA==.Richelieu:BAAALAADCgYIBgAAAA==.Rienderien:BAAALAAECggICAABLAAECggIEAAGAAAAAA==.Rinata:BAAALAADCggIJAAAAA==.Riswell:BAAALAAECgEIAQAAAA==.',Rm='Rmillia:BAABLAAECoEeAAIHAAgIJxLBFwAdAgAHAAgIJxLBFwAdAgAAAA==.',Ro='Robinhood:BAAALAAECggIEAAAAA==.Robinhook:BAAALAADCggICAABLAAECggIEAAGAAAAAA==.Romasst:BAAALAADCgYIDAABLAAECgcIJAAEAJcaAA==.Romast:BAABLAAECoEkAAIEAAcIlxp/TwDxAQAEAAcIlxp/TwDxAQAAAA==.Ronax:BAAALAAECgYIBgAAAA==.',Ru='Rushty:BAAALAADCgcICgAAAA==.',['Rê']='Rêvy:BAAALAAECgYIEwAAAA==.',['Rø']='Røbb:BAAALAAECgYIEgAAAA==.',Sa='Sacerdoce:BAAALAADCgUIBQAAAA==.Sacerdos:BAABLAAECoEjAAIBAAcInR82TwAsAgABAAcInR82TwAsAgAAAA==.Samaelis:BAAALAAECgUIBwAAAA==.Sapphyre:BAABLAAECoEVAAIIAAYIUw0RaQAGAQAIAAYIUw0RaQAGAQAAAA==.Sardion:BAABLAAECoEmAAICAAcItyA6OABWAgACAAcItyA6OABWAgAAAA==.Sasûké:BAAALAAECgYIAgABLAAECggICAAGAAAAAA==.Satsu:BAABLAAECoEVAAISAAYIMhBhOAAeAQASAAYIMhBhOAAeAQAAAA==.Satsujinpala:BAAALAADCggIEAABLAAFFAIIAgAGAAAAAA==.Saween:BAAALAAECgYIEgAAAA==.',Sb='Sbariou:BAAALAAECgUICQAAAA==.',Sc='Scratt:BAAALAAECgYIEgAAAA==.Scärlettë:BAAALAADCggIDwAAAA==.',Se='Segaroth:BAABLAAECoEiAAQVAAgIHCPRCAAmAwAVAAgIHCPRCAAmAwAUAAII5xw5iACjAAAWAAIIzBCrKABlAAAAAA==.Selahani:BAABLAAECoEeAAIPAAcIUx2xJAAqAgAPAAcIUx2xJAAqAgAAAA==.Seleriion:BAABLAAECoEeAAMYAAcIsBNQNgB0AQAdAAcIYxKGbQCeAQAYAAYInxNQNgB0AQAAAA==.Sellundra:BAAALAAECgYIEQAAAA==.',Sh='Shadrys:BAAALAADCggIFwAAAA==.Shalumo:BAAALAAECgYICQABLAAECggIFgAYACUfAA==.Shampooze:BAAALAAECgMIAwAAAA==.Shams:BAAALAAECgEIAQAAAA==.Shaëllia:BAAALAAECgYIBgABLAAECgcIGwAGAAAAAQ==.Sherloch:BAAALAADCgcIEQAAAA==.Sheya:BAABLAAECoEaAAICAAgIciIxEgATAwACAAgIciIxEgATAwAAAA==.Shyroxx:BAAALAADCgcIBwAAAA==.',Si='Siegward:BAAALAADCgcIBwABLAAECgcIEQAGAAAAAA==.Siférion:BAAALAADCggICAAAAA==.Sillys:BAAALAADCggIJwAAAA==.Sinkarley:BAAALAAECgUICAAAAA==.',Sl='Slagger:BAAALAAECgQIBAAAAA==.Släy:BAABLAAECoEeAAIhAAgIdhHIHwAAAgAhAAgIdhHIHwAAAgAAAA==.',So='Sombreeclat:BAAALAAECgcIDwAAAA==.Soranaar:BAACLAAFFIEIAAICAAIIWSEGGwC6AAACAAIIWSEGGwC6AAAsAAQKgSAAAgIACAhdI50RABYDAAIACAhdI50RABYDAAAA.',Sp='Spartê:BAAALAADCgcIBwAAAA==.',Ss='Ssaso:BAAALAADCggIFQAAAA==.',St='Strakk:BAABLAAECoEVAAIEAAYIFBY6fQCDAQAEAAYIFBY6fQCDAQAAAA==.Strukkmonk:BAAALAADCgcIBwAAAA==.Strukky:BAAALAAECgUIBQAAAA==.Støblük:BAAALAAECgYICAAAAA==.',Su='Subotai:BAAALAAECgUIBQABLAAECggIIgARABUWAA==.Sunken:BAAALAAECgcIDAAAAA==.',Sy='Sygalko:BAAALAAECgcIBwABLAAECggIFgAYACUfAA==.',Sz='Szeptàha:BAAALAAECgcIDQAAAA==.',['Sà']='Sàbrina:BAAALAAECgYIEQAAAA==.',['Sâ']='Sââlikhorn:BAAALAAECgYIDwAAAA==.',['Sé']='Ségnolia:BAAALAADCgcIFwAAAA==.Sérénithy:BAAALAAECggIDgAAAA==.',['Sï']='Sïlâs:BAAALAAECgEIAQAAAA==.',Ta='Taedrun:BAABLAAECoEYAAQgAAYI/RRSHwA3AQAgAAYI/RRSHwA3AQAhAAMIdAbyUAB+AAAiAAEI3AXiFwAkAAAAAA==.Tazrek:BAABLAAECoEkAAMeAAgIWBbbRAD4AQAeAAgIABTbRAD4AQAjAAIIuB2+JAClAAAAAA==.',Tc='Tchoupii:BAAALAADCgEIAQAAAA==.',Te='Telinedra:BAAALAAECgMIAwABLAAECggILwAVABMaAA==.Tepes:BAAALAADCgYICwAAAA==.Terryx:BAAALAADCgIIAgAAAA==.',Th='Thelegende:BAAALAAECgEIAQABLAAFFAMICQAgAKoHAA==.Thenewbiche:BAAALAAECgIIBAAAAA==.Thesuspect:BAAALAADCgYIBwAAAA==.Thewallou:BAAALAADCggICAAAAA==.Thewillou:BAABLAAECoEiAAIRAAgISyWsAQBhAwARAAgISyWsAQBhAwAAAA==.Thyrofix:BAAALAAECgQIBAAAAA==.Thémîs:BAAALAAECgEIAQAAAA==.Thöragrim:BAAALAAECgYICwAAAA==.',Ti='Tindh:BAAALAAECgMIAwAAAA==.',To='Tomawok:BAABLAAECoEUAAMXAAYITgnPrgDmAAAXAAYITgnPrgDmAAALAAEIDgOBtgAdAAAAAA==.Torakka:BAAALAAECgIIAwABLAAECgcIHAADAK0eAA==.Tossiborg:BAAALAADCgIIAgAAAA==.',Tr='Traceymartel:BAAALAAFFAIIAgAAAA==.Trestycia:BAAALAAECgcIGwAAAQ==.Trynket:BAAALAAECgUICQAAAA==.',Tu='Tue:BAABLAAECoEiAAMRAAgIzxscFQD2AQARAAgIzxscFQD2AQACAAIIlAnKAgFnAAAAAA==.',Tw='Tweetycar:BAAALAADCggIFgAAAA==.',Ty='Tyene:BAAALAAECgYIEAAAAA==.Typale:BAAALAAECggIDAAAAA==.Tyrhenias:BAAALAADCggIJQAAAA==.',Ul='Ulther:BAAALAADCgEIAQAAAA==.Ultrafin:BAABLAAECoE2AAIPAAgIxw3/TwBqAQAPAAgIxw3/TwBqAQAAAA==.',Ut='Uturbe:BAAALAADCgcIBwABLAAECggIIAAQANsjAA==.',Va='Valamir:BAAALAADCgIIAgAAAA==.Valduin:BAAALAAECgMIAwAAAA==.Valyrian:BAAALAADCgIIAgAAAA==.Vanbowl:BAABLAAECoEZAAIFAAcIXhIuVAC9AQAFAAcIXhIuVAC9AQAAAA==.',Ve='Velhari:BAABLAAECoEYAAIPAAgIbxHIOgC/AQAPAAgIbxHIOgC/AQAAAA==.Velleda:BAAALAAECgIIAgAAAA==.Velmira:BAAALAADCggICAABLAAECgcIHgACAN0fAQ==.Venîvicï:BAABLAAECoEWAAITAAcIjgbTxgA5AQATAAcIjgbTxgA5AQAAAA==.Veridiana:BAAALAADCggIFgAAAA==.Vespéra:BAAALAADCggIDgAAAA==.',Vi='Viortus:BAAALAAECgQIBAAAAA==.Virusdark:BAAALAADCgMIAwAAAA==.Visalic:BAAALAADCgUIBQAAAA==.',Vo='Volkhrun:BAACLAAFFIEGAAINAAIIxAmwDQBxAAANAAIIxAmwDQBxAAAsAAQKgRcAAwEACAi0EzGTAJ8BAAEABwjODzGTAJ8BAA0ACAgAETRDACEAAAEsAAUUBwgaAAUAjSIA.Vortiguën:BAAALAAECgEIAQAAAA==.',['Và']='Vàmpà:BAABLAAECoEkAAMkAAcIXiAJBgCNAgAkAAcIXiAJBgCNAgAaAAEInx0ebwBXAAAAAA==.',['Vî']='Vîsk:BAAALAADCgYICgAAAA==.',Wa='Warbowl:BAAALAADCgIIAgAAAA==.Warhogar:BAABLAAECoEeAAIFAAcIPhTnTQDRAQAFAAcIPhTnTQDRAQAAAA==.Warsher:BAAALAADCgcIBwAAAA==.',We='Wentworth:BAAALAAECgYIDAAAAA==.Wenuss:BAAALAADCgUIBQAAAA==.',Wo='Worssinferno:BAAALAAECgcIDQAAAA==.',Xa='Xagolt:BAAALAADCggIDwAAAA==.',Xe='Xerpî:BAABLAAECoEZAAMeAAcIwQsdgwA/AQAeAAYI6godgwA/AQAHAAMIFAnHcAB6AAAAAA==.',Xy='Xyang:BAAALAADCggIFwAAAA==.',['Xé']='Xéfi:BAAALAADCgcIBwABLAAECgcIIwAUAFQcAA==.',Ya='Yaelden:BAAALAAECgIIAgAAAA==.Yakari:BAAALAADCgEIAQABLAAECgcIEQAGAAAAAA==.Yanoushka:BAAALAAECgYIDwAAAA==.',Ye='Yeahll:BAAALAADCggICAAAAA==.Yenlo:BAAALAAECgYIEgABLAAECggIJAAKAOIQAA==.',Yg='Ygaril:BAAALAAECgEIAQAAAA==.',Yl='Ylhäälta:BAAALAAECgUIBQAAAA==.',Yo='Yol:BAAALAADCgcIBwAAAA==.Yorgl:BAABLAAECoEjAAINAAcICiOoCACtAgANAAcICiOoCACtAgAAAA==.Yoshiman:BAAALAADCggICAAAAA==.You:BAAALAADCgUIBQAAAA==.',Yu='Yudima:BAAALAADCgcICwAAAA==.Yuja:BAABLAAECoEcAAIMAAcIkRS4IwDoAQAMAAcIkRS4IwDoAQAAAA==.Yuri:BAABLAAECoEWAAITAAcIlgzRmwCGAQATAAcIlgzRmwCGAQAAAA==.Yuuki:BAAALAADCgQIBAAAAA==.',Za='Zaiilyo:BAAALAADCggIEAAAAA==.Zalurine:BAAALAAECgEIAgAAAA==.Zazahunter:BAAALAADCgcIBwAAAA==.',Ze='Zelgadys:BAAALAADCggIEAABLAAECggIIgAVABwjAA==.',Zi='Zibargor:BAACLAAFFIEFAAIcAAMIZRSVAgD5AAAcAAMIZRSVAgD5AAAsAAQKgRwAAhwACAjyIJgDAOsCABwACAjyIJgDAOsCAAAA.Zibojin:BAAALAAECggIDQABLAAFFAMIBQAcAGUUAA==.Zimtstern:BAAALAAECgIIAwAAAA==.Zipp:BAABLAAECoEVAAIdAAYI4gTIpAD9AAAdAAYI4gTIpAD9AAAAAA==.',Zo='Zoüz:BAAALAAECgYIDAABLAAFFAMICAAVADUKAA==.',Zu='Zukï:BAAALAADCgcIBwAAAA==.Zurken:BAABLAAECoEfAAIeAAcIRhKkXQCkAQAeAAcIRhKkXQCkAQAAAA==.Zury:BAAALAADCggIDwAAAA==.',['Zè']='Zèllh:BAAALAADCgUIBQAAAA==.',['Zë']='Zëpèq:BAAALAADCggIDwABLAAECgMIAwAGAAAAAA==.',['Zü']='Züuki:BAAALAAECgcIDQAAAA==.Züwa:BAABLAAECoEiAAILAAgIuCH8DAAWAwALAAgIuCH8DAAWAwAAAA==.',['Ãm']='Ãmethyste:BAABLAAECoEUAAIYAAcIAQkWVQDlAAAYAAcIAQkWVQDlAAAAAA==.',['Äm']='Ämørkë:BAAALAADCgEIAQAAAA==.',['Æp']='Æppø:BAAALAAECgcIDwAAAA==.',['Ép']='Épicure:BAAALAADCgYIEwAAAA==.',['Ív']='Ívý:BAAALAADCggICgAAAA==.',['Ïa']='Ïae:BAABLAAECoEjAAMDAAgI3yADBwDiAgADAAcIOyUDBwDiAgASAAIIuwJ4XAArAAAAAA==.',['Ðy']='Ðylem:BAAALAAECgcIBwAAAA==.',['Õp']='Õpti:BAAALAAECgYIBwAAAA==.',['Øw']='Øwødd:BAABLAAECoEaAAIKAAYIShytNwCsAQAKAAYIShytNwCsAQAAAA==.',['ßa']='ßabayaga:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end