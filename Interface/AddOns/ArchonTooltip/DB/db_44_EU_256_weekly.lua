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
 local lookup = {'DemonHunter-Havoc','Druid-Balance','DeathKnight-Unholy','Hunter-Marksmanship','Shaman-Restoration','Paladin-Holy','Priest-Holy','Priest-Shadow','Priest-Discipline','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Unknown-Unknown','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Frost','Warlock-Demonology','Druid-Feral','Shaman-Elemental','Rogue-Outlaw','Monk-Brewmaster','DemonHunter-Vengeance','Evoker-Devastation','Warrior-Arms','Warrior-Fury','Warrior-Protection','Shaman-Enhancement','Druid-Guardian','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Hunter-Survival','Mage-Frost','Mage-Fire','Evoker-Preservation','Evoker-Augmentation',}; local provider = {region='EU',realm='Aszune',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abhora:BAAALAADCgYIBgABLAAECggIIAABAHAQAA==.Abshifter:BAABLAAECoEiAAICAAgI8B9oDQDkAgACAAgI8B9oDQDkAgAAAA==.Abwilliams:BAAALAAECgcIDwAAAA==.Abwilliamu:BAAALAAECgEIAQAAAA==.',Ac='Acirel:BAAALAAECggIAgAAAA==.',Ad='Adromeq:BAABLAAECoEbAAIDAAcI6Q0sHgCtAQADAAcI6Q0sHgCtAQAAAA==.',Af='Afirmacja:BAAALAAECgYIDwAAAA==.',Ag='Agility:BAABLAAECoEYAAIEAAYIQx/6KQAJAgAEAAYIQx/6KQAJAgAAAA==.',Ah='Ahotnjiks:BAAALAADCgcIBwAAAA==.',Ak='Akizs:BAABLAAECoEXAAIFAAgIDRanPAD7AQAFAAgIDRanPAD7AQAAAA==.',Al='Alatheal:BAAALAADCgcIBwAAAA==.Aldorex:BAAALAAECgYICAAAAA==.Alfenster:BAABLAAECoEcAAIGAAcIQhhfHAD6AQAGAAcIQhhfHAD6AQAAAA==.Alkometrs:BAABLAAECoEcAAICAAgITh1yEgCsAgACAAgITh1yEgCsAgAAAA==.Alocacoc:BAAALAADCgcIBwAAAA==.Aluidariis:BAAALAADCggIDQAAAA==.Aluidaris:BAAALAADCgQIBAAAAA==.Alyssar:BAAALAAFFAIIAgAAAA==.',Am='Ambriosa:BAAALAAECgYIEQAAAA==.Ammonium:BAAALAADCgcIBwAAAA==.',An='Anatastarte:BAABLAAECoEgAAQHAAgIrw8TQACtAQAHAAgIrw8TQACtAQAIAAcIkghcTABaAQAJAAEIwQTXOAAZAAAAAA==.Angtoria:BAAALAADCgYIBgAAAA==.Aniko:BAAALAAECgYIDQAAAA==.Anisconjurer:BAABLAAECoEkAAIKAAgIPBzHIwCkAgAKAAgIPBzHIwCkAgAAAA==.Anisprot:BAAALAAECgcICgABLAAECggIJAAKADwcAA==.Anisvore:BAABLAAECoEZAAIFAAcIVBS/aAB4AQAFAAcIVBS/aAB4AQABLAAECggIJAAKADwcAA==.Anthonysala:BAAALAADCgcIEQAAAA==.',Ar='Arantir:BAABLAAECoEbAAICAAcIlh+IGABtAgACAAcIlh+IGABtAgAAAA==.Arda:BAAALAADCggIGgABLAAECggIKQALAB4kAA==.Arisen:BAAALAADCgYIBgAAAA==.Aristah:BAACLAAFFIEFAAIFAAII2w9LMAB5AAAFAAII2w9LMAB5AAAsAAQKgSgAAgUACAjEF0U4AAoCAAUACAjEF0U4AAoCAAAA.Arîel:BAAALAAECgMIAgAAAA==.',As='Asdertis:BAABLAAECoEgAAMMAAgI1x4mLQCQAgAMAAgI1x4mLQCQAgANAAEIfRmRVQBMAAAAAA==.Asdertpala:BAAALAADCggICAAAAA==.Asibia:BAAALAAECgcIBwABLAAECggIJAAHAKYcAA==.Assy:BAAALAAECgUIDAAAAA==.Astoord:BAAALAAFFAIIBAAAAA==.Astrid:BAAALAADCgIIBAAAAA==.',At='Ati:BAAALAAECgQIBQAAAA==.Atom:BAAALAAECgQIBAAAAA==.',Az='Azarrack:BAABLAAECoEgAAIOAAgIySDZEwDoAgAOAAgIySDZEwDoAgAAAA==.Azeisha:BAAALAAECgIIAwABLAAFFAIIAgAPAAAAAA==.Azzania:BAABLAAECoEUAAIQAAYItyJzIwAqAgAQAAYItyJzIwAqAgAAAA==.',Ba='Baarrd:BAAALAADCggIDQABLAAECgIIAgAPAAAAAA==.Babaad:BAAALAAECgUICQAAAA==.Babad:BAAALAADCggICAAAAA==.',Be='Bearwalker:BAAALAADCggIEwAAAA==.Beatemgood:BAAALAAECgYIDwAAAA==.Bekon:BAACLAAFFIEIAAMRAAIIjBijCgChAAARAAIIjBijCgChAAASAAEI1RCWGgBTAAAsAAQKgRsAAxEABwh5HawSAOYBABEABgi4G6wSAOYBABIABQjcG0stAKUBAAAA.Bekons:BAABLAAFFIEIAAITAAIIsyRkGgDWAAATAAIIsyRkGgDWAAAAAA==.Bekonz:BAAALAAECgUICQAAAA==.Belzebubben:BAAALAADCggICAAAAA==.Benédíct:BAAALAADCgUIBQAAAA==.',Bh='Bhutas:BAABLAAECoEoAAIUAAgI2BJOFwAdAgAUAAgI2BJOFwAdAgAAAA==.',Bi='Biezoknis:BAABLAAECoEoAAINAAgIuSFfBQAMAwANAAgIuSFfBQAMAwAAAA==.',Bl='Blastah:BAAALAADCgMIAwAAAA==.Blastygosa:BAAALAADCggICAAAAA==.Bloom:BAAALAAECgIIBAAAAA==.Blyatovski:BAAALAADCggIDgAAAA==.',Bo='Bobawolf:BAAALAAECgEIAQAAAA==.Boh:BAAALAAECgYICAAAAA==.Bohémian:BAABLAAECoEeAAIVAAgI+RqVDABbAgAVAAgI+RqVDABbAgAAAA==.Borgmester:BAAALAADCgIIAgAAAA==.Bosh:BAAALAADCgcIFAAAAA==.Bottlebee:BAABLAAECoEnAAMWAAgIQBACOQDwAQAWAAgIQBACOQDwAQAFAAgI1Q5sZwB8AQAAAA==.',Br='Brickabrac:BAAALAADCgcIDQAAAA==.',Bu='Bumbin:BAACLAAFFIEFAAIMAAIIcQ46LQCcAAAMAAIIcQ46LQCcAAAsAAQKgSEAAgwACAgQHqMjALsCAAwACAgQHqMjALsCAAAA.Bumbuls:BAAALAAECgIIAgAAAA==.',Bx='Bx:BAAALAAECgcICAAAAA==.',['Bá']='Báthory:BAAALAAECggIDwAAAA==.',Ca='Caliban:BAAALAADCggICAAAAA==.Calid:BAABLAAECoEnAAIIAAgIaSP4BwAsAwAIAAgIaSP4BwAsAwAAAA==.Canas:BAAALAADCggIDwAAAA==.Carñal:BAACLAAFFIEGAAIKAAMIxhPVGADwAAAKAAMIxhPVGADwAAAsAAQKgTQAAgoACAh+IqATAPsCAAoACAh+IqATAPsCAAAA.',Ce='Celeb:BAAALAADCgMIAwABLAAECggIEgAPAAAAAA==.Cellagon:BAABLAAECoEbAAQJAAcIPBrgCgDKAQAJAAYInRngCgDKAQAHAAMIOxUXegDYAAAIAAEIugTSiAAxAAAAAA==.Ceryn:BAABLAAECoEgAAIBAAgIcBDdXADeAQABAAgIcBDdXADeAQAAAA==.',Ch='Charala:BAABLAAECoEkAAIBAAgIJBrVLgB1AgABAAgIJBrVLgB1AgAAAA==.Chareala:BAAALAAECgYICAABLAAECggIJAABACQaAA==.Chavilina:BAAALAADCgIIAgABLAAECggIJAABACQaAA==.Chiddi:BAAALAAECgYIBgAAAA==.Chinoiserie:BAAALAAECgcIEgAAAA==.Choronzon:BAAALAAECgQIBwAAAA==.Chumule:BAAALAAECgUIBwAAAA==.Chuprest:BAAALAAECgUIBwAAAA==.Churgie:BAAALAAECgYIDQAAAA==.',Ci='Cidonijs:BAAALAAECgUIBgABLAAFFAIIBAAPAAAAAA==.',Cl='Clear:BAAALAAECgMIAwAAAA==.',Co='Cooljustice:BAAALAAECgYIDgAAAA==.Corrupted:BAAALAAECgMIAwAAAA==.',Cr='Creepyspy:BAABLAAECoEZAAIXAAgI0R5wAgDhAgAXAAgI0R5wAgDhAgAAAA==.Cromwell:BAAALAAECgIIAgAAAA==.Crystylol:BAAALAAECgYIBgAAAA==.',Cu='Curar:BAAALAAECgYIDAABLAAECggIKQALAB4kAA==.Cuthalion:BAABLAAECoEUAAICAAgISBglIAAtAgACAAgISBglIAAtAgAAAA==.',['Cá']='Cárnal:BAAALAAECgIIAgABLAAFFAMIBgAKAMYTAA==.',['Có']='Cóffeebeanz:BAABLAAECoEcAAIGAAcIoRmsGwAAAgAGAAcIoRmsGwAAAgAAAA==.',Da='Daemoni:BAAALAAECgEIAQABLAAFFAMIBgAWAKYIAA==.Dagren:BAAALAADCggIHgAAAA==.Damnson:BAABLAAECoEoAAIYAAgIlhQ7EwD2AQAYAAgIlhQ7EwD2AQAAAA==.Dangerguy:BAABLAAECoEYAAIZAAcI3hNdHwB7AQAZAAcI3hNdHwB7AQAAAA==.Danni:BAAALAAECgMICAAAAA==.Danwell:BAAALAADCggICAAAAA==.Darit:BAACLAAFFIEFAAIVAAIIlBElCQCdAAAVAAIIlBElCQCdAAAsAAQKgSMAAhUACAj8GoAKAIQCABUACAj8GoAKAIQCAAAA.Darkdindon:BAAALAADCgMIAwAAAA==.Darkhearth:BAAALAAECgYICwAAAA==.Daswagisreal:BAAALAAECggIBAAAAA==.',De='Deadbeast:BAAALAAECgUIBQABLAAFFAIIBQAXAK4WAA==.Deafknight:BAABLAAECoEdAAITAAcIXh8fMwB8AgATAAcIXh8fMwB8AgAAAA==.Deathecus:BAAALAAECgYIDAABLAAECgcIGAAPAAAAAQ==.Deathglare:BAABLAAECoEUAAIBAAgIMA3IcwCoAQABAAgIMA3IcwCoAQAAAA==.Deixares:BAABLAAECoEVAAIOAAYIByHoQAASAgAOAAYIByHoQAASAgAAAA==.Demonslide:BAABLAAECoEkAAMBAAgICBmAOQBJAgABAAgImhiAOQBJAgAZAAEIMh0dTgBQAAAAAA==.Demontrigger:BAAALAAFFAIIAgAAAA==.Deusmedical:BAAALAAECggIBgAAAA==.Dezi:BAABLAAECoEeAAIBAAgIhhzMJwCWAgABAAgIhhzMJwCWAgAAAA==.',Di='Dinzedde:BAAALAAECgEIAQAAAA==.',Dj='Djbobo:BAAALAADCggIEAAAAA==.',Dk='Dkruz:BAAALAAECgEIAQAAAA==.Dktäx:BAABLAAECoEdAAMTAAcI8ghQtwBaAQATAAcI8ghQtwBaAQADAAMIogL/RwBtAAAAAA==.Dkz:BAAALAAECgMIAwAAAA==.',Do='Doogiex:BAAALAADCgEIAQAAAA==.',Dr='Draenei:BAAALAAECggIEAABLAAFFAQICwAaAJ4TAA==.Drulleboy:BAAALAAECgQIBAAAAA==.Dryftwood:BAAALAADCgEIAQAAAA==.',Du='Dubbz:BAAALAAECgUIDAAAAA==.Duckie:BAABLAAECoEmAAIOAAgIdRyeKAByAgAOAAgIdRyeKAByAgAAAA==.',Dy='Dynazty:BAAALAAECgEIAQAAAA==.Dystopia:BAAALAADCgcIBwAAAA==.',['Dö']='Döem:BAAALAAECgcIBwAAAA==.',Ei='Eilistraee:BAAALAADCggIDgAAAA==.Eithel:BAAALAAECgYIDAAAAA==.',El='Elandra:BAAALAAECgMIAwAAAA==.Elenate:BAAALAAECgQICAAAAA==.Elidhu:BAAALAADCggIFAAAAA==.Eline:BAAALAADCgEIAQAAAA==.Eliviotter:BAABLAAECoEmAAICAAgIIyHqDADpAgACAAgIIyHqDADpAgAAAA==.Elizaveta:BAABLAAECoEeAAMTAAgIbiM9EgATAwATAAgIbiM9EgATAwADAAMIPiN7NQD6AAAAAA==.Eluneadore:BAABLAAECoEZAAIKAAgInw2PWwDKAQAKAAgInw2PWwDKAQAAAA==.Elunera:BAAALAAECgYICwABLAAFFAUIDwAWAHUaAA==.Elusïve:BAAALAAECggIDwAAAA==.',Em='Emcix:BAAALAAECgEIAQAAAA==.',En='Enkoz:BAAALAADCggIFgABLAAFFAUIDwAWAHUaAA==.Enotrig:BAAALAAECgYIEgAAAA==.',Ex='Exceed:BAAALAAECgIIAgABLAAECggIJwAIAGkjAA==.',Fa='Faemoss:BAABLAAECoEVAAIQAAYIcxZNRACNAQAQAAYIcxZNRACNAQAAAA==.',Fe='Feanoris:BAABLAAECoEaAAIVAAcIPw4lGwCWAQAVAAcIPw4lGwCWAQAAAA==.Feysti:BAAALAADCgcICgAAAA==.',Fi='Fikkie:BAAALAAECggIEgAAAA==.Finch:BAAALAADCggIEAABLAAECggIJQAFAKMgAA==.Finchfly:BAABLAAECoEdAAIaAAYI8htkJgDCAQAaAAYI8htkJgDCAQABLAAECggIJQAFAKMgAA==.Finchpanda:BAABLAAECoElAAMFAAgIoyBYDwDSAgAFAAgIoyBYDwDSAgAWAAcIqBbEOADxAQAAAA==.Fistusèér:BAAALAAECgYIDAAAAA==.',Fl='Flarn:BAAALAAECgQIBwABLAAFFAUIDwAWAHUaAA==.',Fo='Foror:BAAALAAECgQICgAAAA==.Foxxzorr:BAABLAAECoEcAAMbAAgILxsxCQAxAgAcAAgIjhptJwBsAgAbAAcIKBsxCQAxAgAAAA==.',Fr='Fragolina:BAAALAAECgQICgAAAA==.Franzoc:BAAALAADCggICAAAAA==.Freshlegs:BAAALAADCgUIBQAAAA==.',Fu='Fugue:BAAALAAECgUIDAAAAA==.',['Fæ']='Færdæ:BAABLAAECoEkAAIdAAcIfB1hGAA2AgAdAAcIfB1hGAA2AgAAAA==.',['Fú']='Fúbárr:BAAALAAECgMIBQAAAA==.',Ga='Ganilf:BAAALAAECgYIBgABLAAFFAUIDwAWAHUaAA==.Gared:BAAALAADCggICAABLAAECggIJwAIAGkjAA==.Gargamelz:BAABLAAECoEjAAIHAAgITxKjNADjAQAHAAgITxKjNADjAQAAAA==.Garyx:BAABLAAECoEiAAMeAAgIxRXpCQAvAgAeAAgIxRXpCQAvAgAWAAIIRQkmlgBvAAAAAA==.Gatovs:BAAALAAECgIIAgAAAA==.',Ge='Georgé:BAACLAAFFIEFAAIXAAIIrhbHAgCpAAAXAAIIrhbHAgCpAAAsAAQKgSIAAhcACAgcGkMEAHwCABcACAgcGkMEAHwCAAAA.Gerppo:BAACLAAFFIEGAAIWAAMIpgj6EwC8AAAWAAMIpgj6EwC8AAAsAAQKgSQAAhYACAijHagaAKICABYACAijHagaAKICAAAA.',Gi='Giirtoone:BAABLAAECoEVAAITAAYIAx5eXgABAgATAAYIAx5eXgABAgAAAA==.Giovanna:BAAALAADCggICAAAAA==.Girtonnen:BAABLAAECoEUAAMCAAcInRq6NgCpAQACAAYIkRy6NgCpAQAQAAIIHyOnggDGAAAAAA==.',Gl='Glox:BAACLAAFFIEGAAIfAAIIOQtzBQBpAAAfAAIIOQtzBQBpAAAsAAQKgSMAAh8ACAisFccKAPcBAB8ACAisFccKAPcBAAAA.',Go='Gojos:BAAALAADCgcIBwAAAA==.Gokû:BAAALAADCgEIAQAAAA==.Golimir:BAAALAADCggIDwAAAA==.',Gr='Gregorb:BAABLAAECoEYAAIMAAcIYw8ShwClAQAMAAcIYw8ShwClAQAAAA==.',Gu='Guf:BAAALAADCggICAAAAA==.Gulldan:BAAALAAECgIIAgAAAA==.Guojing:BAAALAAECgQIBgAAAA==.',Gz='Gzus:BAAALAAECgMIBwAAAA==.',['Gó']='Gódivá:BAABLAAECoEYAAIBAAcI8wY8qQA8AQABAAcI8wY8qQA8AQAAAA==.',['Gö']='Gömmiboll:BAAALAADCgMIAwAAAA==.Göät:BAAALAADCgcIBwABLAAECgcIHwAVABYiAA==.',Ha='Haaleon:BAABLAAECoEhAAMFAAgI/xGqUQC4AQAFAAgI/xGqUQC4AQAWAAcItQfAXwBdAQAAAA==.Halston:BAABLAAECoEdAAIcAAgIyxt/JgBxAgAcAAgIyxt/JgBxAgAAAA==.Harkal:BAAALAADCggICAABLAAECggIKQALAB4kAA==.Harmony:BAAALAADCggICAAAAA==.Harveyprice:BAAALAAECgMIAwAAAA==.Hasa:BAAALAADCgYIBgAAAA==.',He='Helkaz:BAAALAAECgcIDQAAAA==.Hellrakuen:BAAALAADCggICAAAAA==.Helsong:BAAALAAECgMIBwAAAA==.Hey:BAAALAAECgEIAwAAAA==.',Hi='Hinkreborn:BAABLAAECoEhAAITAAgI/BaDTAAtAgATAAgI/BaDTAAtAgAAAA==.Hiva:BAABLAAECoEmAAIaAAgI5yMCBQAzAwAaAAgI5yMCBQAzAwAAAA==.',Ho='Holyfinch:BAAALAAECgYICwABLAAECggIJQAFAKMgAA==.Holygyatt:BAAALAADCggICAAAAA==.Hotter:BAAALAAECgUIBQAAAA==.',Hu='Hufflegruff:BAABLAAECoEeAAMLAAcI1RVSHwDQAQALAAcI1RVSHwDQAQAgAAYIPRlwGwCiAQABLAAECggIHQAHAPEeAA==.Humaneftw:BAAALAAECgYIBgAAAA==.Hundell:BAABLAAECoEbAAIOAAgI6RwuKgBqAgAOAAgI6RwuKgBqAgAAAA==.',Id='Idhexdat:BAAALAADCggIDgAAAA==.',Il='Ileya:BAAALAAECgUIDAAAAA==.Ilior:BAAALAAECggICAAAAA==.Illior:BAABLAAECoEuAAMGAAgIpxOaHAD5AQAGAAgIpxOaHAD5AQAMAAcIAhRfegC9AQAAAA==.',In='Influenza:BAAALAAECgUIDAAAAA==.Inori:BAAALAAECgUIDAAAAA==.',Is='Iskandarr:BAAALAAECgUICAAAAA==.',Ja='Jaaniits:BAABLAAECoEWAAIhAAYIUQ26dgBVAQAhAAYIUQ26dgBVAQAAAA==.Janorin:BAAALAADCggIDgAAAA==.Jayare:BAAALAADCggICAABLAAECggIEQAPAAAAAA==.',Je='Jeyer:BAAALAAECggIEQAAAA==.Jeyeri:BAAALAAECgIIAgABLAAECggIEQAPAAAAAA==.Jeyers:BAAALAAECgcIDQABLAAECggIEQAPAAAAAA==.',Ji='Jimthecheat:BAAALAAECgYIDQABLAAECggIKAAKAOogAA==.Jingshen:BAACLAAFFIEFAAIgAAII2wy6DQCQAAAgAAII2wy6DQCQAAAsAAQKgSEAAiAACAhQGr0OAE8CACAACAhQGr0OAE8CAAAA.Jinra:BAAALAAECgEIAQABLAAFFAIIBgABAKkkAA==.',Jn='Jnsorange:BAABLAAECoEmAAMhAAgIEA0+TwDJAQAhAAgIEA0+TwDJAQAiAAQIKgP+JgCSAAAAAA==.',Jo='Joukahainen:BAABLAAECoEbAAIFAAcIxBN2XQCYAQAFAAcIxBN2XQCYAQAAAA==.',Ju='Jusa:BAAALAAECgUICgABLAAFFAQICwAaAJ4TAA==.Justífied:BAAALAAECgEIAQABLAAFFAIIBQAXAK4WAA==.Juzandlis:BAABLAAECoEmAAMOAAgIEiJ9FQDdAgAOAAgI0yF9FQDdAgAjAAYIrRioDQCYAQAAAA==.',['Jé']='Jéppe:BAABLAAECoEcAAMHAAcIoRf9NQDdAQAHAAcIoRf9NQDdAQAIAAMIGwLyfQBVAAAAAA==.',Ka='Kalgoth:BAAALAAECgMIAwAAAA==.Kartupelis:BAAALAAECgYICQABLAAFFAIIBAAPAAAAAA==.Kasja:BAAALAAECgYICwAAAA==.Kay:BAABLAAECoEmAAIZAAgI1CY8AACPAwAZAAgI1CY8AACPAwAAAA==.Kaytress:BAAALAAECgIIAgAAAA==.',Ke='Kefir:BAAALAADCggICAABLAAECggIJgAOABIiAA==.Kekissx:BAAALAAECggICAAAAA==.Kentang:BAAALAAECgYICQABLAAECggIHQATAEwiAA==.Kentong:BAABLAAECoEdAAITAAgITCJ5DgAoAwATAAgITCJ5DgAoAwAAAA==.Keoss:BAAALAADCggICAAAAA==.Kerazael:BAAALAAECgMIAgAAAA==.Keyæra:BAAALAAECgUIBQABLAAECgcIJAAdAHwdAA==.',Kh='Kharazim:BAAALAAECgYICAAAAA==.',Ki='Kickdbucket:BAABLAAECoEfAAIUAAcI/hnPFQApAgAUAAcI/hnPFQApAgAAAA==.Kilzz:BAAALAADCggIFQAAAA==.Kiral:BAAALAAECgMIAwAAAA==.Kiruce:BAAALAADCggICAABLAAECgMIAwAPAAAAAA==.Kitty:BAACLAAFFIEYAAIgAAYIdBdRAQATAgAgAAYIdBdRAQATAgAsAAQKgS8AAiAACAicI4MDAB4DACAACAicI4MDAB4DAAAA.Kittypowder:BAAALAADCgMIAwAAAA==.',Ko='Korgoroth:BAAALAAECgcIGAAAAQ==.',Kr='Krovn:BAAALAAFFAIIBAAAAA==.Krovndh:BAAALAAECgYIBgABLAAFFAIIBAAPAAAAAA==.Krovnpala:BAAALAAECgUIBwABLAAFFAIIBAAPAAAAAA==.',Ku='Kubii:BAAALAAECgYIDAABLAAECgcIGgAaANEeAA==.Kuubbii:BAABLAAECoEaAAIaAAcI0R72EwBvAgAaAAcI0R72EwBvAgAAAA==.',Ky='Kywol:BAABLAAECoEZAAMGAAgI/QrmLACHAQAGAAgI/QrmLACHAQAMAAQIfhiUxwAsAQAAAA==.',['Kê']='Kênpachi:BAABLAAECoEVAAMDAAgIXSCdBwDJAgADAAgIXSCdBwDJAgATAAMIPg1oEAGbAAAAAA==.',La='Labero:BAAALAAECgUICgAAAA==.Laulund:BAAALAAECgUICQAAAA==.Lavigne:BAAALAADCgcIBwABLAAECgYIDAAPAAAAAA==.Laylith:BAAALAADCgEIAQAAAA==.',Le='Leafy:BAAALAAECgMIAwAAAA==.Leetzorz:BAABLAAECoEmAAIdAAgI2BtGFABeAgAdAAgI2BtGFABeAgAAAA==.Leocore:BAAALAAECgYIEQAAAA==.',Li='Lidonna:BAAALAAECgQIBAAAAA==.Liessa:BAAALAADCggICAAAAA==.Lightsunai:BAAALAADCggIDwAAAA==.Lisica:BAAALAADCggIIAAAAA==.Litterbox:BAABLAAECoEfAAIVAAcIFiJMCACwAgAVAAcIFiJMCACwAgAAAA==.',Lj='Ljutause:BAAALAAECgcIEwABLAAFFAIIBgAKABMZAA==.',Lo='Locas:BAAALAAECgMIAwAAAA==.Lothoal:BAAALAADCgUIBQABLAAFFAUIDwAWAHUaAA==.',Lu='Luckyman:BAAALAAECgQICwAAAA==.Lumia:BAAALAAECgYIEAAAAA==.Lutzé:BAABLAAECoEbAAMgAAcIshE6HgCDAQAgAAcIshE6HgCDAQALAAMICgm+SACIAAABLAAECggIHgAVAPkaAA==.Luzonica:BAAALAADCggICAAAAA==.',Ly='Lyijypulkka:BAAALAAECgYIBgABLAAFFAQICwAaAJ4TAA==.Lyndis:BAAALAADCggIFgAAAA==.',Ma='Madfub:BAAALAAECggIDwABLAAECggIGAAKAD4bAA==.Madnezs:BAAALAAECgIIAgAAAA==.Magicfinch:BAAALAAECggICQABLAAECggIJQAFAKMgAA==.Magicfub:BAABLAAECoEYAAIKAAgIPhsLNABXAgAKAAgIPhsLNABXAgAAAA==.Magicwizzle:BAACLAAFFIEFAAIkAAIIEglAEACBAAAkAAIIEglAEACBAAAsAAQKgSgAAiQACAjtH9oIAOsCACQACAjtH9oIAOsCAAAA.Mattaki:BAABLAAECoEoAAMKAAgI6iDjFwDiAgAKAAgI6iDjFwDiAgAlAAEIewYeIQAgAAAAAA==.Mayaa:BAABLAAECoEmAAIjAAgIYwxhCQDuAQAjAAgIYwxhCQDuAQAAAA==.',Mc='Mctart:BAAALAADCggICAAAAA==.',Md='Mdzei:BAAALAAECgUIBQAAAA==.',Me='Meg:BAABLAAECoEiAAIIAAgIbgqMOwCpAQAIAAgIbgqMOwCpAQAAAA==.Mehito:BAABLAAECoEeAAIkAAcI6gylMgCBAQAkAAcI6gylMgCBAQAAAA==.Melhoot:BAAALAAECgUIBwABLAAECggIKQALAB4kAA==.Mellane:BAABLAAECoEpAAMLAAgIHiTjAgBUAwALAAgIHiTjAgBUAwAgAAUIdhiaIwBPAQAAAA==.Melocutes:BAAALAAECgcIDQAAAA==.Melphas:BAAALAAECgQIBAAAAA==.Melshoots:BAAALAAECgUIBQAAAA==.',Mh='Mhow:BAAALAADCgcICAAAAA==.',Mi='Mimmy:BAAALAADCggICAAAAA==.Minervia:BAAALAADCgYIBgAAAA==.Minka:BAAALAADCggIEAAAAA==.Miraculous:BAAALAAECgQIBQAAAA==.Mirona:BAAALAADCgYIBwAAAA==.Mithrala:BAABLAAECoEgAAIQAAcIACUlCwDiAgAQAAcIACUlCwDiAgAAAA==.',Mo='Mogrin:BAAALAADCggICAAAAA==.Monkalicious:BAABLAAECoEWAAMgAAgIyxACHQCQAQAgAAgIyxACHQCQAQALAAgI0QivNAAvAQAAAA==.Monkerinoo:BAAALAAECgYICQABLAAFFAIIBgAKABMZAA==.Monkosh:BAABLAAECoEZAAIgAAcIwxyQDwBBAgAgAAcIwxyQDwBBAgAAAA==.Moondew:BAAALAADCgYIBgAAAA==.Moonlok:BAAALAADCgYIDAAAAA==.Moonmaide:BAAALAADCgMIAwAAAA==.Moonraine:BAAALAADCgYIBgAAAA==.Moretotems:BAAALAADCgcIBwABLAAECggIFQADAF0gAA==.',Mu='Murksontagh:BAAALAAECgEIAQAAAA==.Murkyshadow:BAAALAAECgUICQAAAA==.',My='Myohmy:BAAALAAECgYICgAAAA==.',['Mí']='Míca:BAABLAAECoEoAAIGAAgIISKQBAAGAwAGAAgIISKQBAAGAwAAAA==.',['Mî']='Mîsts:BAABLAAECoEWAAIgAAcItyM8CADAAgAgAAcItyM8CADAAgAAAA==.',Na='Nacho:BAAALAADCggIEQAAAA==.Narcis:BAAALAAECgcIEQAAAA==.Narcisdh:BAABLAAECoEoAAIBAAgIwheZOABMAgABAAgIwheZOABMAgAAAA==.Narcisdk:BAAALAAECgYIDgAAAA==.Narciskungfu:BAAALAAECgYIBgAAAA==.Narciswarr:BAAALAAECgYIDQAAAA==.Naszgull:BAAALAAECgQIBAAAAA==.Nate:BAAALAADCgYIBgAAAA==.Naílah:BAAALAADCgcIDQAAAA==.',Ne='Nekoneredzu:BAAALAAECgUIBQAAAA==.Nelfdruid:BAAALAAECgEIAQABLAAECggIHQAUADoUAA==.Neona:BAAALAADCgYIBgAAAA==.Nerobasta:BAAALAAECgYICgAAAA==.Neroli:BAAALAAECgYIBgAAAA==.Nethergray:BAABLAAECoEXAAINAAgIUx+RCwCOAgANAAgIUx+RCwCOAgAAAA==.Netiirais:BAACLAAFFIEGAAIIAAIIAhaUFQCWAAAIAAIIAhaUFQCWAAAsAAQKgRsAAggABwjkII4eAFoCAAgABwjkII4eAFoCAAAA.',Ni='Nightlily:BAAALAAECgUIDAAAAA==.Nikita:BAAALAAECgYIEgAAAA==.Nirale:BAAALAADCgUIBQAAAA==.Nitrø:BAAALAADCggIDgAAAA==.Niue:BAAALAAECgIIAgAAAA==.',Nj='Njapri:BAAALAAECggICAAAAA==.',No='Nogruni:BAAALAADCggICAAAAA==.Nonea:BAAALAAECgYIDgAAAA==.Nonlv:BAACLAAFFIEGAAIKAAIIExkWKQCjAAAKAAIIExkWKQCjAAAsAAQKgRsAAgoABgjyIC84AEQCAAoABgjyIC84AEQCAAAA.Nordmoon:BAAALAAECgQIBgAAAA==.',Nu='Nugar:BAAALAAECgEIAQAAAA==.',Ny='Nyxira:BAABLAAECoEdAAIHAAcIHAsJVwBSAQAHAAcIHAsJVwBSAQAAAA==.Nyzza:BAAALAAECggIBwAAAA==.',['Ná']='Náaved:BAABLAAECoEbAAMOAAgIERXxXADCAQAOAAgIERXxXADCAQAjAAEIZQVbIQATAAAAAA==.',Ok='Okwhofarted:BAAALAADCgcICQAAAA==.',Ol='Oldways:BAAALAADCgcIBwAAAA==.',Ot='Oty:BAAALAAECggICAAAAA==.',Pa='Palalinda:BAAALAAECgMIBwAAAA==.Palefang:BAABLAAECoEdAAIHAAgI8R44EQDDAgAHAAgI8R44EQDDAgAAAA==.Palownator:BAAALAAECgYIEAAAAA==.Pandaps:BAAALAADCgcIBwABLAADCggIDgAPAAAAAA==.Pargen:BAAALAAECgUIBQABLAAECggIKQALAB4kAA==.Pawsofflight:BAABLAAECoEWAAMmAAYIGhQMGQB2AQAmAAYIGhQMGQB2AQAaAAEIdQkDXQAmAAABLAAECggIGwAhAJsRAA==.Pawstruction:BAABLAAECoEbAAMhAAgImxFJQAABAgAhAAgImxFJQAABAgAUAAEI7QPbiAAwAAAAAA==.',Pe='Pedomednieks:BAABLAAECoEXAAIBAAcI6hwyQwAnAgABAAcI6hwyQwAnAgAAAA==.Pekainitis:BAABLAAECoEfAAIVAAgIGxy6CACnAgAVAAgIGxy6CACnAgABLAAECggIGQAHAHUeAA==.Pennyback:BAAALAAECgYIDAAAAA==.',Ph='Phyroox:BAAALAADCggIDwAAAA==.Phíl:BAABLAAECoEdAAMaAAgINRNDIgDjAQAaAAgIhxJDIgDjAQAnAAEIOhbDFABEAAAAAA==.',Pi='Piepie:BAAALAADCgcIDAAAAA==.Piromane:BAAALAADCggIBgAAAA==.Piruids:BAAALAAECgYIBgAAAA==.Pix:BAAALAAECgIIBgAAAA==.',Pl='Plogen:BAAALAAECgIIAgAAAA==.Ploogen:BAAALAADCgcIBwAAAA==.Plufs:BAAALAADCggIEAABLAAFFAUIDwAWAHUaAA==.',Po='Poppylisciou:BAAALAAECgcICgABLAAECggIJAABACQaAA==.Potat:BAABLAAECoEcAAMmAAcIhxzHCwBCAgAmAAcIhxzHCwBCAgAaAAEIqRXyVgBEAAABLAAECggIKAAKAOogAA==.',Ps='Psygore:BAAALAAECgYICwAAAA==.Psylef:BAAALAAECgMIBAABLAAECgYICwAPAAAAAA==.Psyzerker:BAAALAAECgEIAQABLAAECgYICwAPAAAAAA==.',Pu='Punishers:BAAALAAECgYIBgAAAA==.Pusygourmet:BAAALAAECgQIBAAAAA==.',Py='Pyo:BAAALAAECgUIDAAAAA==.',Qw='Qwaanh:BAABLAAECoEbAAIeAAcIPxB/EACvAQAeAAcIPxB/EACvAQAAAA==.',Ra='Ragemen:BAAALAAECgMIBgAAAA==.Rakhish:BAAALAADCggICAAAAA==.Rastlyn:BAABLAAECoEjAAIWAAgI8gtyRAC+AQAWAAgI8gtyRAC+AQAAAA==.Raventalon:BAABLAAECoEXAAIYAAgI8A19HgBpAQAYAAgI8A19HgBpAQAAAA==.Ravenwind:BAAALAAECgYIBgAAAA==.Raziél:BAAALAADCggICAAAAA==.Raýa:BAAALAADCgIIAgAAAA==.',Re='Reanimacija:BAABLAAECoEZAAIHAAgIdR4lEgC6AgAHAAgIdR4lEgC6AgAAAA==.Repena:BAAALAAECgcIDwAAAA==.Resnaaberta:BAAALAADCgcICQABLAAFFAIIBgAKABMZAA==.Rettoz:BAAALAADCggIDgAAAA==.Rexdraconis:BAAALAAECgYIDwAAAA==.',Rh='Rhannos:BAAALAAECgUICQAAAA==.',Ri='Riáz:BAAALAADCggIHQAAAA==.',Ro='Robotnic:BAAALAADCggIDwABLAAFFAUIDwAWAHUaAA==.Roller:BAABLAAECoEbAAMXAAgIjSCOAwCeAgAXAAcItSGOAwCeAgARAAgI8xdnDABEAgAAAA==.',Ru='Runeforge:BAAALAADCgIIAgAAAA==.',Rw='Rwaawr:BAABLAAECoEdAAIMAAgIoyQkCQBPAwAMAAgIoyQkCQBPAwAAAA==.',Sa='Saintslime:BAAALAAECgYICQABLAAECggIJwAWAEAQAA==.Sakaro:BAAALAADCgMIAwAAAA==.Samwyse:BAAALAADCggICAABLAAECggIBgAPAAAAAA==.',Sc='Scadi:BAAALAADCgYIBgAAAA==.Scalene:BAAALAADCggIDgABLAAECggIKQALAB4kAA==.Schrödy:BAAALAAECgYICgAAAA==.',Se='Seffir:BAAALAAECgcIEQAAAA==.Sekerpare:BAAALAADCgcIEQAAAA==.Selûne:BAAALAAECgEIAQAAAA==.Sennahoj:BAAALAADCggIDAABLAAFFAQICwAaAJ4TAA==.Senzubean:BAABLAAECoEWAAIEAAcI0h9HHABnAgAEAAcI0h9HHABnAgAAAA==.',Sh='Shaandra:BAAALAAECgUIDAAAAA==.Shabydh:BAABLAAECoEVAAIBAAgIcR1TIgCyAgABAAgIcR1TIgCyAgAAAA==.Shadowazz:BAAALAADCggICAABLAAECgYIFAAQALciAA==.Shagrat:BAAALAAECggICwAAAA==.Shalltear:BAABLAAECoEbAAMRAAgIeRTAEwDZAQASAAcI2RMHIwDoAQARAAgIkRHAEwDZAQAAAA==.Shambolic:BAAALAAECgUIBQAAAA==.Shellshócked:BAAALAADCgcIBwAAAA==.Shinki:BAAALAADCggIDwAAAA==.Shiuraz:BAAALAAECgYICQABLAAFFAIIAgAPAAAAAA==.Shuush:BAAALAADCggICAAAAA==.Shálatar:BAABLAAECoEeAAQUAAgIpCM/CQCyAgAUAAcI9CI/CQCyAgAhAAYIZRzPSwDVAQAiAAMI5iR7GQAWAQAAAA==.Shálysra:BAAALAAECgQIBAAAAA==.',Si='Siderte:BAAALAAECgMIBQAAAA==.Sieru:BAABLAAECoEoAAMUAAgILCVLAQBnAwAUAAgIGiVLAQBnAwAhAAgIoiBFGQDOAgAAAA==.Sif:BAAALAAECgYICwAAAA==.Siipivihta:BAACLAAFFIELAAIaAAQInhOQBwBCAQAaAAQInhOQBwBCAQAsAAQKgSoAAxoACAjoHiUMAM8CABoACAjoHiUMAM8CACYAAwipAtkwAGkAAAAA.Silex:BAAALAAECgYICwAAAA==.Singularity:BAAALAADCgcIBwAAAA==.Sipmark:BAAALAAECgYICAAAAA==.',Sk='Skyforgie:BAAALAADCgMIAwABLAAECgcIGgAaANEeAA==.',Sl='Slarva:BAAALAADCgUIBQAAAA==.Sliméiy:BAAALAAECgcIBwABLAAECggIJwAWAEAQAA==.',Sn='Sneeze:BAAALAAECgMICAAAAA==.Snowfairy:BAAALAAECgUIDAAAAA==.',So='Sodapop:BAAALAADCgcICAAAAA==.Solin:BAAALAADCgcIDAAAAA==.Solnight:BAAALAADCgMIAwAAAA==.Solonielle:BAAALAADCggICAAAAA==.Soulsun:BAAALAAECgcICgAAAA==.',Sp='Spirittfox:BAAALAADCggIFQAAAA==.Spook:BAAALAAECggICAAAAA==.Spring:BAAALAAECgYIDAAAAA==.',Sr='Sraaz:BAABLAAECoEcAAIdAAcItSLfDAC1AgAdAAcItSLfDAC1AgAAAA==.',St='Stabhion:BAABLAAECoEXAAMRAAcIpxlmEAAEAgARAAcIpxlmEAAEAgASAAIIoxWAWAB6AAAAAA==.Staminamc:BAAALAADCgUIBQAAAA==.Standruid:BAAALAAECgMIBgAAAA==.Stanpaladin:BAAALAAECgUIDAAAAA==.Stephan:BAAALAAECgUIBQABLAAECgYICQAPAAAAAA==.Stinkßomb:BAAALAADCggICAAAAA==.Storgut:BAAALAAECgEIAQAAAA==.Stro:BAAALAAECgUIDAAAAA==.',Su='Summertoe:BAAALAAECgcIBwABLAAECggIGwAhAJsRAA==.Sundrove:BAABLAAECoEfAAIcAAgIHCBLEgD6AgAcAAgIHCBLEgD6AgAAAA==.Susitar:BAAALAAECgYICAAAAA==.',Sy='Syllen:BAABLAAECoEeAAIFAAcI/Bu7MAAlAgAFAAcI/Bu7MAAlAgAAAA==.Synnila:BAAALAADCggICQAAAA==.',Ta='Tatyhanna:BAAALAAECgQIBwAAAA==.',Te='Teetuks:BAAALAADCggICAAAAA==.Telerion:BAAALAAECgYIBgAAAA==.Tenok:BAAALAAECgYICAAAAA==.Teronar:BAAALAADCgYICQAAAA==.',Th='Thatdragon:BAABLAAECoEjAAIaAAgIaBoHEwB7AgAaAAgIaBoHEwB7AgAAAA==.Thatdwarf:BAAALAAECgUIBQABLAAECggIIwAaAGgaAA==.Thatworgen:BAAALAADCgMIAwABLAAECggIIwAaAGgaAA==.',Tm='Tmy:BAAALAAECggICAAAAA==.',To='Tororo:BAABLAAECoEXAAIQAAgInxkvGwBcAgAQAAgInxkvGwBcAgAAAA==.Toshy:BAAALAADCgQIBAABLAAECggIHgAFAAcdAA==.',Tr='Trakulismonk:BAABLAAECoEgAAILAAgICB2BDACsAgALAAgICB2BDACsAgAAAA==.Traya:BAAALAAECgMIBQAAAA==.Tregioba:BAAALAAECgMICQAAAA==.Treisijs:BAACLAAFFIEIAAMhAAIIGSAMIQCqAAAhAAIIyx0MIQCqAAAUAAEIiyIoGQBiAAAsAAQKgSAABCEACAgoIRMWAOMCACEACAi7IBMWAOMCABQAAwgFH0JQAAABACIAAQjHICcxAFcAAAAA.Treysijs:BAABLAAFFIEGAAMhAAIINRJHKACaAAAhAAIINRJHKACaAAAUAAEIlAy+IQBNAAABLAAFFAIICAAhABkgAA==.Triger:BAAALAADCgYIBgABLAAECggIEQAPAAAAAA==.Trustyrusty:BAACLAAFFIEFAAIdAAII4h6LCwC1AAAdAAII4h6LCwC1AAAsAAQKgSMAAh0ACAi+JLwCAFkDAB0ACAi+JLwCAFkDAAAA.',Ts='Tsunarashi:BAAALAADCgYIBgAAAA==.',Tu='Tunchi:BAAALAADCggIDwAAAA==.Tuoni:BAAALAAECgUIBQAAAA==.',Tw='Twiddler:BAAALAADCgIIAwAAAA==.Twista:BAAALAADCgUIBQAAAA==.',Ty='Typhön:BAAALAADCggICgAAAA==.Tyraela:BAAALAADCggICAAAAA==.',['Té']='Térokk:BAAALAADCggICwAAAA==.',Ub='Ubiquinol:BAAALAAECggIBwAAAA==.',Ud='Udenslidejs:BAAALAAECgYIBgAAAA==.',Un='Unreflected:BAAALAAECgEIAQAAAA==.',Va='Vaash:BAAALAAECggIEgAAAA==.Valdeko:BAAALAAECgYICQAAAA==.Valkýrie:BAAALAAECgIIAgAAAA==.Vanguard:BAABLAAECoEXAAIMAAgI0xAuZQDqAQAMAAgI0xAuZQDqAQAAAA==.Vanida:BAABLAAECoEfAAIHAAcIORLKQQClAQAHAAcIORLKQQClAQAAAA==.Varaz:BAABLAAECoEUAAIFAAYIqSRnHwBwAgAFAAYIqSRnHwBwAgABLAAFFAIIAgAPAAAAAA==.Varetna:BAAALAADCggIDgAAAA==.Varnoris:BAAALAADCgcIBwAAAA==.',Vb='Vbj:BAAALAAECgUIDAAAAA==.',Ve='Velcro:BAAALAAFFAIIAgAAAA==.Venfica:BAAALAADCggIDgABLAAFFAUIDwAWAHUaAA==.Vengerr:BAAALAADCgQIBAAAAA==.',Vi='Vidzemnieks:BAAALAADCggIEAAAAA==.Vigilante:BAAALAADCggICAAAAA==.Vilath:BAAALAADCgQIBQAAAA==.Vilkme:BAAALAADCggICAAAAA==.',Vm='Vmnbgh:BAAALAADCgEIAQAAAA==.',Vo='Vojd:BAAALAADCggIDgABLAAFFAUIDwAWAHUaAA==.Voltenc:BAABLAAECoEkAAIYAAgIliFwBgDoAgAYAAgIliFwBgDoAgAAAA==.Vorador:BAACLAAFFIEGAAIhAAII7QtuLQCSAAAhAAII7QtuLQCSAAAsAAQKgRoAAiEACAjqFAY2AC4CACEACAjqFAY2AC4CAAAA.',Vu='Vuurvliegje:BAAALAADCgQIBAABLAAECgYICwAPAAAAAA==.',Vy='Vythera:BAAALAAFFAIIAgABLAAFFAIIAgAPAAAAAA==.',Wa='Wale:BAABLAAECoEbAAMkAAcI2BolIgDiAQAkAAYI7hwlIgDiAQAKAAcIjxANWwDMAQAAAA==.Warwickdavis:BAAALAAECgYIBwAAAA==.',We='Weywood:BAABLAAECoEZAAICAAgIEh/5FgB7AgACAAgIEh/5FgB7AgAAAA==.',Wh='Whisper:BAAALAAECgcIDQAAAA==.',Wi='Wienerbrød:BAAALAAECggICQAAAA==.Wily:BAAALAAECgcIBwAAAA==.Wisdomness:BAABLAAECoEdAAQUAAgIOhR/JADGAQAUAAcIrBJ/JADGAQAhAAcIbxIaUQDDAQAiAAEI2go4PQAzAAAAAA==.',Wo='Wochi:BAABLAAECoEfAAIWAAcIBhFURAC/AQAWAAcIBhFURAC/AQAAAA==.Worglock:BAAALAAECgIIAgAAAA==.',Wr='Wraarw:BAAALAAECgYIBgAAAA==.',Wy='Wynteria:BAAALAAECgcIDgAAAA==.',Xe='Xere:BAAALAADCgcIDAAAAA==.',Xi='Xianga:BAAALAAECgEIAQAAAA==.',Xo='Xona:BAAALAADCgcIBwABLAAECgcIHAAGAKEZAA==.',Yr='Yrisius:BAABLAAECoEeAAIHAAgIXQuUSQCGAQAHAAgIXQuUSQCGAQAAAA==.',Za='Zann:BAABLAAECoEWAAIWAAYINwKFiACrAAAWAAYINwKFiACrAAAAAA==.Zarvájh:BAAALAAECgYIDgAAAA==.Zaryx:BAABLAAECoEjAAIOAAcI5h2uOAAwAgAOAAcI5h2uOAAwAgAAAA==.Zatama:BAABLAAECoEdAAIMAAcIORlCUQAaAgAMAAcIORlCUQAaAgAAAA==.',Ze='Zende:BAABLAAECoEcAAINAAcI/yDaCgCZAgANAAcI/yDaCgCZAgAAAA==.Zenelie:BAAALAAFFAIIAgAAAA==.Zetharel:BAABLAAECoEcAAIBAAYIcxUvggCKAQABAAYIcxUvggCKAQABLAAECgcIIwAOAOYdAA==.',Zi='Zivjuzupa:BAAALAAECgYIDwAAAA==.',Zn='Znixxen:BAAALAAECgYICAAAAA==.',Zo='Zosma:BAAALAADCgYIBgAAAA==.',Zy='Zynthos:BAAALAAECgQIBAAAAA==.Zyrina:BAAALAAECgYIBgABLAAECgcIIwAOAOYdAA==.',['Zâ']='Zârvâjh:BAAALAAECgIIAgAAAA==.',['Òw']='Òwó:BAAALAAECggIEgABLAAECggIHgATAG4jAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end