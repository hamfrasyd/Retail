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
 local lookup = {'DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Priest-Holy','Shaman-Elemental','Shaman-Enhancement','Warrior-Fury','Warrior-Arms','Warrior-Protection','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Mage-Frost','Unknown-Unknown','Shaman-Restoration','Monk-Mistweaver','Paladin-Holy','Paladin-Protection','Priest-Shadow','Mage-Arcane','Priest-Discipline','Mage-Fire','Druid-Feral','Evoker-Devastation','Paladin-Retribution',}; local provider = {region='EU',realm='Suramar',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aara:BAAALAAECgYICgAAAA==.',Ab='Absolüm:BAAALAAECgEIAQAAAA==.',Ae='Aekoo:BAAALAAECgQIBgAAAA==.Aeros:BAAALAAECgUIDAAAAA==.',Ag='Agatha:BAAALAADCgUICAAAAA==.',Ak='Akhisha:BAAALAADCgcIDQAAAA==.',Al='Aladach:BAAALAAECgYIDQAAAA==.Aleandria:BAAALAAECgMIAwAAAA==.Alestia:BAACLAAFFIEHAAIBAAIIrhwyIwCjAAABAAIIrhwyIwCjAAAsAAQKgSkAAgEACAhqJT8EAG0DAAEACAhqJT8EAG0DAAAA.Almaghar:BAAALAAECgEIAQAAAA==.Alurdel:BAAALAAECgUIBgAAAA==.Alween:BAAALAAECgYIBwAAAA==.',Am='Amadass:BAABLAAECoEXAAMCAAgIGA8qTgDVAQACAAgIGA8qTgDVAQADAAEIDQe7OgA7AAAAAA==.Amergin:BAAALAADCgcIBwAAAA==.Ametyste:BAAALAAECgEIAQAAAA==.',An='Anarazel:BAAALAAECgYICAABLAAECggIGQAEAAchAA==.Anenix:BAAALAAECgUICAAAAA==.',Ao='Aoshin:BAAALAAECgcIEQAAAA==.',Ap='Appletree:BAABLAAECoEXAAMFAAYI8xGLXABAAQAFAAYI8xGLXABAAQAGAAQI8xDeZADgAAAAAA==.',Ar='Arael:BAAALAADCggIEAAAAA==.Arakval:BAAALAAECggICgAAAA==.Aranwel:BAAALAAECgYIEwAAAA==.Arglen:BAAALAADCggICAAAAA==.Argoultek:BAAALAAECgYIBgAAAA==.Arkharn:BAAALAADCgUIBQAAAA==.Arkø:BAAALAAECggICAAAAA==.Arratar:BAABLAAECoEsAAIHAAgI2RHmEwAUAgAHAAgI2RHmEwAUAgAAAA==.Arthaes:BAAALAADCgIIAgAAAA==.',As='Asiriel:BAABLAAECoEnAAIIAAgIoRm0HgBlAgAIAAgIoRm0HgBlAgAAAA==.Astra:BAABLAAECoEVAAMJAAgIzB4TKgBFAgAJAAgIzB4TKgBFAgAKAAEIpwwuJAA7AAAAAA==.Astralat:BAAALAADCggIDgAAAA==.',Ay='Ayzan:BAAALAADCgIIAwAAAA==.',['Aé']='Aégidius:BAAALAAECgYIDwAAAA==.',['Aø']='Aødhan:BAABLAAECoEmAAMLAAgIzCL9EgD7AgALAAgIVyL9EgD7AgAMAAYIyyQYBgCLAgAAAA==.',Ba='Badday:BAAALAADCgUIBQAAAA==.Bahamut:BAACLAAFFIEGAAINAAIIKwu7HABoAAANAAIIKwu7HABoAAAsAAQKgRYAAg0ABwgME38uAJoBAA0ABwgME38uAJoBAAEsAAUUAggGAA4ASCMA.Bakthor:BAAALAADCggIEAAAAA==.Bamboudiné:BAAALAAECgEIAQAAAA==.Bamyl:BAAALAAECgQIBQAAAA==.',Be='Beatrixe:BAAALAADCggICAAAAA==.',Bl='Blackpriest:BAAALAAECgYIEAABLAAECggIFwABAEgbAA==.Blancbarbu:BAABLAAECoEwAAIPAAgIoCSkCwAkAwAPAAgIoCSkCwAkAwAAAA==.Blancpally:BAAALAAECgIIAgAAAA==.Blobecarlate:BAAALAAECgQIBAABLAAFFAIIBgAOAMYPAA==.Blobindigo:BAABLAAECoEdAAIJAAgI4yHmIAB8AgAJAAgI4yHmIAB8AgAAAA==.Blobjeanma:BAABLAAECoEfAAIQAAgIsBDknwCJAQAQAAgIsBDknwCJAQAAAA==.Blobsidienne:BAAALAADCgYICwABLAAFFAIIBgAOAMYPAA==.Blobéon:BAABLAAECoElAAICAAgIXx8nHADBAgACAAgIXx8nHADBAgAAAA==.Blueskyy:BAABLAAECoEcAAIOAAYIlR2oRACKAQAOAAYIlR2oRACKAQAAAA==.',Bm='Bmahfarmer:BAAALAADCggICAAAAA==.',Bo='Bouhdepier:BAAALAADCggICAAAAA==.Boykka:BAAALAADCgcIBwAAAA==.',Br='Braoret:BAAALAADCgYICwAAAA==.Brel:BAACLAAFFIEHAAILAAMInBn/DQAWAQALAAMInBn/DQAWAQAsAAQKgSUAAgsACAj1JCEGAFoDAAsACAj1JCEGAFoDAAAA.Brouwnies:BAAALAADCgcICgAAAA==.Bryseys:BAAALAADCgMIAwAAAA==.',By='Byakknini:BAAALAAFFAEIAQABLAAFFAMICAANAGslAA==.Byakktina:BAACLAAFFIEIAAINAAMIayVhBQBNAQANAAMIayVhBQBNAQAsAAQKgR4AAg0ACAj0JOoCAFgDAA0ACAj0JOoCAFgDAAAA.',['Bà']='Bàohù:BAABLAAECoEgAAIRAAgIbyPOBAAUAwARAAgIbyPOBAAUAwAAAA==.',Ca='Caepra:BAAALAAECgMIAwAAAA==.Camoes:BAAALAAECgcIDgAAAA==.Cartarme:BAABLAAECoEhAAIQAAcIaCJ8KgCiAgAQAAcIaCJ8KgCiAgAAAA==.',Ce='Celyanar:BAAALAAECgYIBgAAAA==.Ceridwen:BAAALAADCgIIAgAAAA==.',Ch='Chamanni:BAAALAAECgcIDQAAAA==.Chaminati:BAAALAAECgQIBAAAAA==.Chevaliøur:BAAALAAECgIIAgAAAA==.Chicots:BAAALAAECgYIEgAAAA==.Christallys:BAAALAADCggICAAAAA==.Chérie:BAAALAAECgEIAQAAAA==.',Ci='Cirdec:BAAALAADCgUIBQAAAA==.',Cs='Csisala:BAAALAADCgcIEAAAAA==.',Cu='Curcuma:BAAALAAECgUICQAAAA==.',Cy='Cylla:BAAALAAECgcIEgAAAA==.',['Cô']='Côôlmâ:BAAALAADCggIGQAAAA==.',['Cø']='Cøcøtte:BAAALAADCggILgAAAA==.',Da='Daemont:BAAALAAECgcIDgAAAA==.Daffydock:BAAALAAECgYIEgAAAA==.Darkane:BAAALAAECgYIBwAAAA==.Darkfûry:BAAALAADCgYICAAAAA==.Darkgirl:BAAALAADCgYICAAAAA==.Darktauren:BAAALAAECgEIAQAAAA==.Daëmonika:BAAALAADCgUIBQAAAA==.',De='Deadlight:BAAALAADCgcIBwAAAA==.Deathjadou:BAAALAAECgUIBQAAAA==.Delandris:BAAALAADCggICAAAAA==.Demofish:BAAALAAECgUIBgAAAA==.Derea:BAAALAADCgQIBAAAAA==.Derideath:BAAALAADCgMIAwAAAA==.',Dh='Dhik:BAAALAADCgQIBAAAAA==.',Dk='Dkmal:BAABLAAECoEoAAISAAgIySOMBAAWAwASAAgIySOMBAAWAwAAAA==.',Do='Donmakaveli:BAAALAADCgUIBQAAAA==.',Dr='Dragonico:BAACLAAFFIEGAAIOAAIIxg/kHwCAAAAOAAIIxg/kHwCAAAAsAAQKgSoAAg4ACAjlG8keAFgCAA4ACAjlG8keAFgCAAAA.Drahssal:BAAALAAECgEIAQAAAA==.Drakenshyk:BAAALAAECgEIAgAAAA==.Druidamix:BAAALAAECgYIDgABLAAECgcIHgATAKwTAA==.',['Dé']='Décapfour:BAAALAAECgYIDwAAAA==.Décimal:BAABLAAECoEeAAIFAAcIfBgFLwD3AQAFAAcIfBgFLwD3AQAAAA==.Décimalus:BAAALAADCgQIBAAAAA==.Déri:BAAALAAECgUICAAAAA==.',Ea='Eaubenite:BAAALAADCgMIAwAAAA==.Eaudreyve:BAAALAAECgYIEQAAAA==.',El='Elara:BAABLAAECoETAAIOAAYIlRfWQwCOAQAOAAYIlRfWQwCOAQABLAAECgcIFgARAJohAA==.Elbartodrood:BAAALAAECgYIBgAAAA==.Elfie:BAAALAADCgcIBwABLAAECgYIDwAUAAAAAA==.Elémentar:BAABLAAECoEiAAIVAAgIsw9ZYQCWAQAVAAgIsw9ZYQCWAQAAAA==.',Er='Erhétrya:BAACLAAFFIEIAAIVAAIIyRlCJACYAAAVAAIIyRlCJACYAAAsAAQKgScAAhUACAgIIccPANQCABUACAgIIccPANQCAAAA.',Ev='Evilwulf:BAABLAAECoEZAAIEAAcIByG1CwCVAgAEAAcIByG1CwCVAgAAAA==.',Ex='Exalutor:BAAALAAECggIEgAAAA==.',Ey='Eyesonme:BAAALAADCgEIAQAAAA==.',Fa='Failcast:BAAALAADCgcIDAAAAA==.Falkor:BAAALAAECgYICwABLAAECggIGQAEAAchAA==.Farléane:BAAALAAECgMIBQAAAA==.',Fe='Fefist:BAABLAAFFIEJAAIWAAMI+hW1BgD+AAAWAAMI+hW1BgD+AAAAAA==.Fellean:BAAALAAECgYIEQAAAA==.',Fo='Fougêrre:BAAALAADCggIGQAAAA==.',Fr='Frostheim:BAAALAAECgEIAQAAAA==.',['Fà']='Fàfnir:BAAALAAECgYIBgAAAA==.',['Fé']='Félinne:BAAALAADCggIFQABLAAFFAIIBgASAPwjAA==.',Ga='Gallaw:BAAALAADCgUIBQAAAA==.',Gi='Gilrohel:BAABLAAECoEwAAIPAAgIQxOhXADOAQAPAAgIQxOhXADOAQAAAA==.',Gl='Glossy:BAAALAAECgMIBAAAAA==.',Go='Gounä:BAAALAADCgEIAQAAAA==.',Gr='Groscaillou:BAABLAAECoEWAAIRAAcImiHGCwB2AgARAAcImiHGCwB2AgAAAA==.',Gu='Guïmauve:BAAALAADCgMIAwAAAA==.',['Gø']='Gørøsh:BAAALAADCggIEAAAAA==.',Ha='Hakushu:BAAALAADCgcIBwAAAA==.Hanoumân:BAAALAAECgcIBwAAAA==.Hathanael:BAAALAAECgMIBgABLAAECggIJwAIAKEZAA==.',He='Heldas:BAAALAADCggICAAAAA==.Helincia:BAAALAAECgcIEAAAAA==.Heraa:BAAALAAECgEIAQAAAA==.',Ho='Hogma:BAABLAAECoEeAAIFAAcI3Rw5IQA+AgAFAAcI3Rw5IQA+AgAAAA==.Hogmad:BAAALAADCgcIBwAAAA==.',Hu='Hunä:BAABLAAECoEoAAIXAAgIqxr0DgB8AgAXAAgIqxr0DgB8AgAAAA==.',['Hé']='Héresia:BAABLAAECoEWAAIEAAcICx21EABcAgAEAAcICx21EABcAgAAAA==.',Ic='Iceforge:BAAALAADCgIIAgAAAA==.',Ig='Iggins:BAABLAAECoEXAAIYAAYIbgcfQQDbAAAYAAYIbgcfQQDbAAAAAA==.',Ik='Ikshar:BAAALAADCgMIAwAAAA==.',Il='Ilgadh:BAAALAAECggICwABLAAECggILgAZAG8aAA==.Ilgapal:BAAALAADCggIEAABLAAECggILgAZAG8aAA==.Ilgarna:BAABLAAECoEuAAIZAAgIbxr6IABOAgAZAAgIbxr6IABOAgAAAA==.Ilidune:BAABLAAECoEXAAIBAAYISButUgABAgABAAYISButUgABAgAAAA==.Ill:BAABLAAECoEZAAIKAAgIWhxnBgCVAgAKAAgIWhxnBgCVAgAAAA==.Ilyasse:BAABLAAECoEdAAILAAgIPhdQUADJAQALAAgIPhdQUADJAQABLAAFFAYIAwAUAAAAAA==.',Is='Istarei:BAABLAAECoEgAAIaAAgIYRx6LQB7AgAaAAgIYRx6LQB7AgAAAA==.',Iz='Izikia:BAAALAADCggICAABLAAECggIEgAUAAAAAA==.',Ja='Jacke:BAAALAAECgUIBQAAAA==.Jadounet:BAABLAAECoEcAAIbAAcISCLZAgCyAgAbAAcISCLZAgCyAgAAAA==.Jafad:BAABLAAECoEWAAIVAAcI/xWVVwCwAQAVAAcI/xWVVwCwAQAAAA==.',Jh='Jhabilou:BAAALAADCggICwAAAA==.',Ji='Jilsoul:BAAALAADCgUIBQAAAA==.',Jo='Jollyna:BAAALAAECgEIAgAAAA==.Joya:BAAALAADCgMIAwAAAA==.',Ka='Kaeldan:BAAALAADCgEIAQAAAA==.Kaervek:BAAALAADCggIDwAAAA==.Kame:BAABLAAECoEUAAMLAAcI8xd6PQANAgALAAcI8xd6PQANAgAMAAQICxIdIADXAAAAAA==.Kaséo:BAAALAADCgMIAQAAAA==.',Ke='Keitho:BAAALAAECgcIEQAAAA==.Keljinss:BAAALAADCggICAAAAA==.Kemosabe:BAAALAAECgYIDgAAAA==.Keramal:BAAALAADCgcIBwAAAA==.',Kh='Khendan:BAAALAAECgEIAQAAAA==.',Ki='Kira:BAAALAAECgMIAwABLAAECggIMAAcANggAA==.Kirito:BAAALAAECgIIBQAAAA==.',Kl='Kleà:BAAALAAECgcIEwAAAA==.',Ko='Koane:BAABLAAECoEWAAICAAgIlhydIACmAgACAAgIlhydIACmAgAAAA==.Kobalt:BAAALAADCgcICgAAAA==.Kornich:BAAALAADCgYIDQAAAA==.',Ku='Kuronawaah:BAAALAAECggIDAABLAAECggIGQAZAAklAA==.Kurowaah:BAABLAAECoEZAAIZAAgICSVVBABYAwAZAAgICSVVBABYAwAAAA==.',Ky='Kyjo:BAAALAADCgQIBAAAAA==.Kyssa:BAABLAAECoEwAAIJAAgIwBcjKQBKAgAJAAgIwBcjKQBKAgAAAA==.',['Kÿ']='Kÿnoa:BAAALAADCgMIAwAAAA==.Kÿrâ:BAAALAADCggICAAAAA==.',La='Ladinâ:BAAALAADCgcIBwAAAA==.',Le='Lelard:BAAALAADCgQIBAAAAA==.Lemagicien:BAABLAAECoEwAAMcAAgI2CCuAQDtAgAcAAgI1CCuAQDtAgAaAAQIHxlvoQAJAQAAAA==.Leoh:BAAALAAECgQIBQAAAA==.Leroyn:BAAALAADCggICwAAAA==.Levdrood:BAACLAAFFIEKAAIdAAQIYx2KAgB7AQAdAAQIYx2KAgB7AQAsAAQKgTIAAx0ACAiXJLkCAD0DAB0ACAiXJLkCAD0DAAUABwh4ENRcAD8BAAAA.',Li='Lidalice:BAACLAAFFIEGAAISAAII/CPhBgDPAAASAAII/CPhBgDPAAAsAAQKgSoAAhIACAjTIk8FAAIDABIACAjTIk8FAAIDAAAA.Lisneuh:BAACLAAFFIEGAAIKAAIIew2KBQCYAAAKAAIIew2KBQCYAAAsAAQKgSsAAwoACAjTGoEIAFsCAAoACAjTGoEIAFsCABUAAQiCAWYcARoAAAAA.',Lo='Lodie:BAAALAADCgQIBAAAAA==.Loludu:BAAALAADCggICAABLAAECggIIAAeAGIaAA==.Loroyse:BAACLAAFFIEGAAIOAAIISCMNDwDMAAAOAAIISCMNDwDMAAAsAAQKgSwAAg4ACAjrITIJABMDAA4ACAjrITIJABMDAAAA.Lostris:BAAALAAECgYIDAAAAA==.Loturos:BAABLAAECoEfAAMXAAgIrh1TDACZAgAXAAgIrh1TDACZAgAfAAEIPwqyOQE9AAAAAA==.Lousdé:BAAALAADCgQIBAAAAA==.',Lu='Lumineau:BAAALAAECgQIBQAAAA==.',Ly='Lykaon:BAAALAADCgcIEwAAAA==.',['Lé']='Léovis:BAAALAAECgUIBwAAAA==.',Ma='Magikbana:BAAALAADCgQIAwAAAA==.Magikbanani:BAAALAADCgUIBQAAAA==.Magikkbanani:BAACLAAFFIEEAAMEAAMIFgtKAwDkAAAEAAMIFgtKAwDkAAADAAEIvATbBgA9AAAsAAQKgSsABAQACAg2HLwQAFwCAAQACAjgGrwQAFwCAAMAAwiOESskAKkAAAIAAwiBHHq6AI0AAAAA.Magistrall:BAABLAAECoEeAAMTAAcIrBN9MACUAQATAAYIVhV9MACUAQAaAAQIvQ3zpwDyAAAAAA==.Maldonn:BAAALAAECgMIAwAAAA==.Malerath:BAAALAAECgYIEAAAAA==.Manla:BAAALAAECgMIBgAAAA==.',Me='Metrae:BAAALAAECgEIAgAAAA==.',Mi='Midonä:BAAALAAECgMIBwAAAA==.Mikaw:BAAALAADCgYICQAAAA==.Milenia:BAAALAAECgcIEAAAAA==.Milëa:BAAALAAECgYICwAAAA==.Minichouette:BAAALAAECgMIAwAAAA==.Minicovid:BAAALAADCgUIBQAAAA==.Miniprêtress:BAABLAAECoEwAAIIAAgIGxpaIQBTAgAIAAgIGxpaIQBTAgAAAA==.Minora:BAAALAADCggICAAAAA==.Miranà:BAAALAAECgIIAgAAAA==.Missisipia:BAABLAAECoEZAAIPAAgInRj4QgAXAgAPAAgInRj4QgAXAgAAAA==.Missmix:BAAALAAECgYICQABLAAECgcIDAAUAAAAAA==.',Mo='Moinephuc:BAAALAAECgYICwAAAA==.Monibou:BAAALAADCgYIBgABLAADCggIDwAUAAAAAA==.Monysera:BAAALAADCggIDwAAAA==.Morgomir:BAABLAAECoEhAAIQAAcIaR6SQgBPAgAQAAcIaR6SQgBPAgAAAA==.Mouçe:BAAALAAECgMIAwAAAA==.',Mu='Muldrak:BAAALAADCgcIEwAAAA==.Murlcat:BAAALAADCgUIBQABLAADCgcIEAAUAAAAAA==.',My='Myrianne:BAAALAADCgEIAQAAAA==.Mystas:BAAALAAECgYICAABLAAECggIFwABAAEjAA==.',['Mâ']='Mâjoris:BAAALAADCgUIBQAAAA==.Mânïra:BAAALAAECgMIAwAAAA==.',['Mä']='Mägnûm:BAABLAAECoEdAAIPAAgIUxykOAA7AgAPAAgIUxykOAA7AgAAAA==.',Na='Nahry:BAAALAADCggIEwAAAA==.Nanashi:BAAALAAECgcIEwAAAA==.',Ne='Nefertami:BAAALAAECgYIBgAAAA==.Nerioo:BAABLAAECoEiAAIfAAgITBknPwBUAgAfAAgITBknPwBUAgAAAA==.Nerthüs:BAAALAADCggIDAAAAA==.',Ni='Niabey:BAABLAAECoEfAAIaAAcIUwyKhQBdAQAaAAcIUwyKhQBdAQAAAA==.Nightrage:BAAALAADCgQIBAAAAA==.Nirinäh:BAAALAAECgcIDwAAAA==.',Nn='Nnaal:BAAALAADCgQIBQAAAA==.',No='Noukkie:BAAALAADCgcIEAAAAA==.',['Né']='Néferia:BAAALAAECgcIEwAAAA==.',Or='Orksovage:BAAALAAECgMIBAAAAA==.Orphélie:BAABLAAECoEXAAIVAAgIbA8PaQCBAQAVAAgIbA8PaQCBAQAAAA==.',Os='Osteolis:BAAALAAECgcIDAAAAA==.',Pa='Palafortune:BAAALAAECgEIAQABLAAECgYIBgAUAAAAAA==.Pandaran:BAAALAAECgYIBgABLAAECggIGQAEAAchAA==.Panomanixme:BAAALAAECgYIDgABLAAFFAIICAAVAMkZAA==.Papybellu:BAABLAAECoEVAAITAAcI0B7NEQB0AgATAAcI0B7NEQB0AgAAAA==.Pasgrand:BAAALAAECgcIBwAAAA==.Paxarius:BAAALAADCgcIBwAAAA==.',Pi='Pignedepin:BAAALAADCgYIAwAAAA==.',Po='Pomee:BAAALAADCggIDgABLAAECgUIBgAUAAAAAA==.Pompei:BAAALAADCgMIBAAAAA==.Popkornne:BAAALAAECgUIEwAAAA==.',Pr='Priestzle:BAAALAADCgcIDQAAAA==.Protonidze:BAAALAADCgcIDQAAAA==.',['Pä']='Pärø:BAAALAADCgcIBwABLAAECgcIIQATACoRAA==.',['Pé']='Pélagie:BAAALAAECgQIBAAAAA==.',['Pï']='Pïstachë:BAAALAAECgMICgAAAA==.',Qu='Quantumedge:BAAALAADCgIIAgAAAA==.',Ra='Ragnaro:BAAALAADCgcIDQAAAA==.Raknarok:BAABLAAECoEaAAIBAAgIoR1jMwBpAgABAAgIoR1jMwBpAgAAAA==.',Re='Renardo:BAABLAAECoEYAAIQAAgI3BcgQgBQAgAQAAgI3BcgQgBQAgAAAA==.Restyaka:BAAALAADCggIFAAAAA==.Reythanabis:BAAALAAECgUIAwAAAA==.',Ro='Rockks:BAAALAADCgUIBQAAAA==.Rodrac:BAAALAAECgYIDgAAAA==.',['Râ']='Râknâ:BAAALAAECgcIDQAAAA==.',Sa='Saakhar:BAAALAAECgIIAgAAAA==.Saekoh:BAABLAAECoEhAAIQAAcIEiQ4KQCoAgAQAAcIEiQ4KQCoAgAAAA==.Sakredbonk:BAAALAAECgYIBwAAAA==.Sakürà:BAAALAADCggIFQAAAA==.Sarïka:BAAALAAECgYICAAAAA==.Satsujinken:BAAALAAECgEIAQAAAA==.',Sh='Shamansexi:BAAALAAECgYIBgAAAA==.Shaÿa:BAAALAAECgEIAQAAAA==.Sheiyne:BAAALAAECgYIAQAAAA==.Sheryne:BAAALAADCgYIBgAAAA==.',Si='Sillia:BAAALAADCgYIBgAAAA==.Silverpalhea:BAAALAADCgMIBAAAAA==.Siondrus:BAAALAAECgEIAQAAAA==.Sissur:BAAALAADCggICAAAAA==.',Sm='Smartmini:BAAALAADCgUIBQAAAA==.Smò:BAAALAADCgcICgAAAA==.Smõ:BAAALAAECgIIAgAAAA==.',Sn='Snòòtsh:BAAALAADCgcIBwABLAAECgcIGAAQAHkeAA==.',So='Solido:BAAALAADCgMIAwAAAA==.Soltrae:BAAALAADCggIDAAAAA==.Soonyangel:BAAALAAECgcIBwAAAA==.Sorön:BAAALAADCgcIBwAAAA==.Soøny:BAAALAADCggICAAAAA==.',Sp='Sprinkle:BAAALAAECgYIDwAAAA==.Spyrodormu:BAAALAAECgIIAgAAAA==.',Sq='Squishina:BAAALAAECgMIBgAAAA==.',St='Stbnn:BAAALAADCgcIBwABLAAECgcIDwAUAAAAAA==.Stcnn:BAAALAAECgYICQABLAAECgcIDwAUAAAAAA==.',Sy='Syltrae:BAAALAAECgcICAAAAA==.',['Sî']='Sîrmerlin:BAACLAAFFIEGAAIIAAIISxRuJwCLAAAIAAIISxRuJwCLAAAsAAQKgSIAAggACAgLHVQZAIkCAAgACAgLHVQZAIkCAAAA.',['Sø']='Søoný:BAABLAAECoEwAAIdAAgItB4oBwDOAgAdAAgItB4oBwDOAgAAAA==.',Ta='Tactacdh:BAABLAAECoEgAAIPAAgIBBWHZAC7AQAPAAgIBBWHZAC7AQAAAA==.Taellia:BAABLAAECoEXAAIfAAcI7BJMjQChAQAfAAcI7BJMjQChAQAAAA==.Tahmil:BAAALAADCggIEAABLAAECggIMAAcANggAA==.Taoor:BAABLAAECoEfAAIFAAgIRRrBGgBmAgAFAAgIRRrBGgBmAgAAAA==.Taralith:BAAALAADCgcICQAAAA==.Tarâ:BAAALAAECgEIAQAAAA==.Tatemontotem:BAAALAAECgMIAwAAAA==.Tatoobabe:BAAALAAECgMIAwAAAA==.Taöse:BAAALAAECgcIDgAAAA==.',Te='Tenestra:BAAALAAECgEIAQAAAA==.',Th='Tharawaah:BAAALAAECggIEgAAAA==.Theroshan:BAABLAAECoEjAAIGAAgIvQ77RwBgAQAGAAgIvQ77RwBgAQAAAA==.Thienthien:BAABLAAECoEUAAIHAAgIYxMaFQAGAgAHAAgIYxMaFQAGAgAAAA==.Thàllion:BAACLAAFFIEYAAILAAYIvhybAgBGAgALAAYIvhybAgBGAgAsAAQKgSoAAgsACAjxJUsFAGEDAAsACAjxJUsFAGEDAAAA.Théoochoux:BAAALAADCgUIBQAAAA==.',Tl='Tlaartos:BAAALAAECgQIBAABLAAECggIFwABAEgbAA==.',To='Tontonjeanma:BAAALAADCgYIBgAAAA==.Tov:BAAALAAECgYIBgAAAA==.',Tu='Turim:BAAALAAECgYIEgAAAA==.',['Tî']='Tîtepuce:BAAALAADCgUIBQABLAAECggIGQAEAAchAA==.',['Tø']='Tømyun:BAABLAAECoEqAAQKAAgInh4XBADbAgAKAAgInh4XBADbAgAJAAQIrxdLcQAsAQAVAAYIBAxZqwDtAAAAAA==.',Uc='Ucatsone:BAAALAADCgcIEAAAAA==.',Un='Univeria:BAAALAAECgYIDgAAAA==.',Va='Vaelthas:BAAALAADCgcIBwAAAA==.Valøø:BAAALAAFFAIIBAAAAA==.Vanhouten:BAAALAADCgcIFgABLAADCggICwAUAAAAAA==.Vanthyr:BAAALAAFFAYIAwAAAA==.',Ve='Veleera:BAAALAAECggICAABLAAFFAIIBAAUAAAAAA==.Veréna:BAAALAADCgQIBAAAAA==.',Vi='Visariuss:BAABLAAECoEsAAMLAAcI+xDEbgBwAQALAAcIwhDEbgBwAQAMAAEImhH/MABCAAAAAA==.',['Vê']='Vêlkan:BAAALAADCggICAAAAA==.',Wa='Walkinglunge:BAAALAAECgcICgAAAA==.Warwîck:BAAALAADCgEIAQAAAA==.',Wi='Winnie:BAAALAAECgMIAwAAAA==.',Wr='Wrÿnn:BAAALAADCgIIAQAAAA==.',['Wé']='Wési:BAAALAAECggIEQAAAA==.',Xa='Xalatat:BAAALAADCgYIBgAAAA==.',Ya='Yabadabadoo:BAAALAAECgIIAgABLAAFFAIIBgASAPwjAA==.',Yl='Yllixta:BAAALAAECgYIDQAAAA==.',Yr='Yronos:BAAALAAECggICAAAAA==.Yrüama:BAAALAADCgIIAgAAAA==.',Yu='Yugure:BAABLAAECoEaAAIWAAcIMBjrGQC7AQAWAAcIMBjrGQC7AQABLAAFFAIIBgAOAEgjAA==.Yummu:BAABLAAECoEWAAMJAAcIvBlXSQC1AQAJAAUImhxXSQC1AQAVAAQIcCN8awB7AQAAAA==.Yumu:BAABLAAECoEZAAQCAAgInCDLKQByAgACAAcIaiDLKQByAgAEAAQIIyDzNgBwAQADAAQIDBcCGQAeAQAAAA==.',Za='Zavryk:BAAALAAECgYIDwAAAA==.',Ze='Zeshiro:BAAALAADCggICwAAAA==.',Zi='Ziapaladin:BAABLAAECoEbAAIfAAYIjgzE0QAkAQAfAAYIjgzE0QAkAQAAAA==.Ziapin:BAAALAADCgcIDQABLAAECgYIGwAfAI4MAA==.Zionhigh:BAAALAAECgUIBQAAAA==.Ziraël:BAAALAAECggICAAAAA==.',Zo='Zoumio:BAAALAADCgcIBwAAAA==.',['Äb']='Äbaddon:BAAALAAECgIIAgAAAA==.',['Æw']='Æwêÿn:BAAALAAECggIEQABLAAECggIJgALAMwiAA==.',['Ìs']='Ìshä:BAAALAADCgYIBgAAAA==.',['Øm']='Ømegâ:BAABLAAECoEhAAMTAAcIKhGKLQCkAQATAAcI5xCKLQCkAQAaAAYICAhdmwAdAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end