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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Warrior-Protection','Warlock-Demonology','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Monk-Mistweaver','Shaman-Elemental','Warrior-Fury','DemonHunter-Havoc','Mage-Frost','Paladin-Holy','Hunter-BeastMastery','Paladin-Retribution','Druid-Guardian','DeathKnight-Unholy','Hunter-Marksmanship','Monk-Brewmaster','Monk-Windwalker','Priest-Discipline','Evoker-Preservation','DeathKnight-Frost','Warlock-Destruction','Paladin-Protection','DeathKnight-Blood','Evoker-Ranged','Evoker-Devastation','DemonHunter-Vengeance','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Affliction','Hunter-Survival','Priest-Shadow','Druid-Feral','Warrior-Arms',}; local provider = {region='EU',realm='Forscherliga',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarmon:BAAALAADCggIGgAAAA==.',Ad='Addo:BAAALAAECgYIDAAAAA==.Adzzon:BAAALAAECggICgAAAA==.',Ae='Aesthetic:BAAALAAECgEIAQAAAA==.',Af='Affixlol:BAAALAADCgYIBgABLAAECgcICAABAAAAAA==.',Ai='Ailie:BAABLAAECoEbAAICAAYIMxjaYwCPAQACAAYIMxjaYwCPAQAAAA==.',Ak='Akarí:BAABLAAECoEgAAIDAAgI8R0oDgCqAgADAAgI8R0oDgCqAgAAAA==.Akdorban:BAABLAAECoEXAAIEAAcI+RykDwBoAgAEAAcI+RykDwBoAgAAAA==.Akrakadabra:BAAALAAECgUIBwAAAA==.Akurayamino:BAABLAAECoEmAAIDAAgIMiQHBABDAwADAAgIMiQHBABDAwAAAA==.',Al='Alaron:BAAALAAECgcIDgABLAAFFAIIAgABAAAAAA==.Aletharia:BAAALAADCgcIBwAAAA==.Aliis:BAAALAAECgUICQAAAA==.Altria:BAAALAADCgYIBgAAAA==.Alunah:BAAALAADCggIIgAAAA==.Alynia:BAAALAADCggICAAAAA==.',Am='Amelina:BAABLAAECoEgAAMFAAgIgxINKgD0AQAFAAgIgxINKgD0AQAGAAQIjQfqpABpAAAAAA==.Amellià:BAAALAAECgYIEQAAAA==.',An='Andromaky:BAABLAAECoEaAAIHAAcIVxbyBgD0AQAHAAcIVxbyBgD0AQAAAA==.Anjilu:BAAALAAECgMIBQAAAA==.Anyrienna:BAAALAADCggIFwAAAA==.Anyska:BAAALAAECgIIAgAAAA==.',Ar='Ardorion:BAAALAAECgEIAgAAAA==.Arrateri:BAABLAAECoEYAAIIAAcI0Q1AJQBHAQAIAAcI0Q1AJQBHAQAAAA==.Arthana:BAAALAADCggIDwAAAA==.',As='Ashaiya:BAABLAAECoEjAAMCAAgIJhylIQBrAgACAAgIJhylIQBrAgAJAAIIjgYAAAAAAAABLAAFFAQICwAGABMZAA==.Ashenya:BAAALAAECggIBQAAAA==.Ashram:BAABLAAECoEWAAIKAAYIziM/JwB2AgAKAAYIziM/JwB2AgAAAA==.Ashrya:BAAALAAECgYICQAAAA==.',At='Attol:BAABLAAECoEUAAIDAAcIBxVCLACoAQADAAcIBxVCLACoAQAAAA==.',Au='Aud:BAABLAAECoEqAAILAAgI1h0RJQCqAgALAAgI1h0RJQCqAgAAAA==.Aurine:BAAALAAECgIIAgAAAA==.',Av='Avania:BAAALAADCgcIFQAAAA==.Aventorian:BAABLAAECoEXAAIMAAYIFA/4PwBKAQAMAAYIFA/4PwBKAQAAAA==.',Ay='Ayaleth:BAAALAAECggICAAAAA==.Ayres:BAAALAAECgUIAgAAAA==.',Az='Azshatar:BAABLAAECoEeAAINAAgIcCJiBAAMAwANAAgIcCJiBAAMAwAAAA==.Azzazi:BAABLAAECoEVAAIJAAYIPwsHdgAZAQAJAAYIPwsHdgAZAQAAAA==.',Ba='Baceldackel:BAAALAADCggIEAAAAA==.Balu:BAAALAADCgcIBwAAAA==.Barokx:BAAALAAECgYICQAAAA==.Baschira:BAAALAADCggICAAAAA==.',Be='Begadör:BAAALAADCgEIAQAAAA==.Beviso:BAAALAAECgYIEgAAAA==.',Bl='Blackdragon:BAAALAAECggIEQAAAA==.',Bo='Borrs:BAAALAAECgQIBgAAAA==.',Br='Bravados:BAAALAAECgYIDgAAAA==.Bròók:BAAALAAECgIIAgAAAA==.',Bu='Buck:BAAALAADCggICAAAAA==.',['Bá']='Bámbám:BAAALAAECgUIBQAAAA==.',['Bä']='Bähdskull:BAABLAAECoEnAAIOAAgImBteLABrAgAOAAgImBteLABrAgAAAA==.',Ca='Caitlin:BAAALAAECgEIAgAAAA==.Calgatiar:BAAALAAECgcIDQAAAA==.Caliostro:BAAALAAECgEIAgAAAA==.Canondah:BAAALAAECgQIBgAAAA==.Castivar:BAAALAADCgcIEQABLAAECggIGgAOAJQTAA==.Cay:BAAALAADCgcICgAAAA==.',Ce='Cenedrá:BAAALAADCggICAAAAA==.',Ch='Chitose:BAAALAAECgYICgAAAA==.Chodeweiner:BAAALAADCgQIBAAAAA==.Chárly:BAAALAADCgcICgABLAADCggIDAABAAAAAA==.',Cl='Clayd:BAABLAAECoEqAAIOAAgIUyXVCgAqAwAOAAgIUyXVCgAqAwAAAA==.',Co='Connie:BAAALAAECgMIBgAAAA==.Corry:BAAALAADCgUIBQAAAA==.',Cr='Crysin:BAAALAAECgcICAAAAA==.',Cy='Cynn:BAAALAADCgYICAAAAA==.',Da='Dahka:BAAALAADCgIIAgAAAA==.Darkbird:BAAALAAECgYIEQAAAA==.Darkshello:BAAALAADCgUIBQAAAA==.Daríon:BAABLAAECoEnAAIPAAgIlR/qIwC/AgAPAAgIlR/qIwC/AgAAAA==.Davedatlay:BAACLAAFFIEIAAIQAAII+RscAwCeAAAQAAII+RscAwCeAAAsAAQKgRoAAhAACAhOHBoGAHoCABAACAhOHBoGAHoCAAAA.Dazan:BAACLAAFFIEGAAIGAAII4SDiEQDAAAAGAAII4SDiEQDAAAAsAAQKgSQAAwYACAijImgIAAIDAAYACAijImgIAAIDAAUABghgGF06AJ8BAAAA.',De='Deathlight:BAABLAAECoEkAAIRAAgIkBMaGQDcAQARAAgIkBMaGQDcAQAAAA==.Default:BAAALAAECgMIBAAAAA==.Deheilemacha:BAABLAAECoEjAAIGAAgIpyTVBQAhAwAGAAgIpyTVBQAhAwAAAA==.Dejan:BAABLAAECoEaAAIFAAcIDhxSHgBDAgAFAAcIDhxSHgBDAgAAAA==.Delanny:BAAALAAECgUIBQAAAA==.Deloyro:BAAALAADCgYIBQAAAA==.Dematos:BAAALAADCgYIBgAAAA==.Demonlink:BAABLAAECoEVAAILAAgICxKRXADnAQALAAgICxKRXADnAQAAAA==.Deranadis:BAAALAAECgMIBQAAAA==.Devillino:BAAALAADCggICAAAAA==.Deviona:BAAALAAECgEIAgAAAA==.Dexzhunt:BAAALAADCggICAAAAA==.',Di='Diwa:BAAALAAECgcIEAAAAA==.',Dk='Dkinght:BAAALAAECgYIBgAAAA==.',Dr='Dradam:BAAALAADCggICAAAAA==.Dragondeez:BAAALAAFFAIIAgABLAAFFAIIBgALAOofAA==.Dragy:BAAALAAECgcIBwAAAA==.Dralun:BAABLAAECoEYAAIOAAcIICHbKgBxAgAOAAcIICHbKgBxAgAAAA==.Drapax:BAABLAAECoEaAAISAAYIHg0VaAAJAQASAAYIHg0VaAAJAQAAAA==.Dregona:BAABLAAECoEWAAILAAcIOBX0bgC7AQALAAcIOBX0bgC7AQAAAA==.Drexx:BAAALAAECgQIDAAAAA==.Droc:BAACLAAFFIEIAAIKAAIIlxNwIQCgAAAKAAIIlxNwIQCgAAAsAAQKgR0AAgoACAj4GiIqAGUCAAoACAj4GiIqAGUCAAAA.Drowranger:BAAALAADCggIDwAAAA==.Druidkasia:BAAALAAECgYIEAAAAA==.Dróc:BAAALAAECgYIEAABLAAFFAIICAAKAJcTAA==.',Ds='Dschamp:BAAALAAECggIDgAAAA==.',Du='Duge:BAAALAAECgYICwAAAA==.',Dw='Dworg:BAAALAAECgMIAwAAAA==.',['Dæ']='Dæmon:BAAALAADCgYIBgAAAA==.',['Dø']='Døntqqme:BAAALAAECggIBAAAAA==.',['Dú']='Dúngar:BAAALAAECggIDAAAAA==.',Ed='Edgemaster:BAAALAADCgMIAwAAAA==.',Ei='Eisenhøwer:BAAALAAECgUIBwAAAA==.',El='Elcidena:BAAALAAECgYIDQABLAAECgcICAABAAAAAA==.Eldirith:BAAALAAECgYIBgAAAA==.Eliyantha:BAAALAAECgIIAgABLAAECgcICAABAAAAAA==.Elorèén:BAAALAAECgUIBwAAAA==.Elsbeth:BAAALAADCgIIBgAAAA==.Elsuteras:BAAALAAECgYIBgAAAA==.Elunde:BAAALAADCgMIAwAAAA==.',Em='Emiroc:BAABLAAECoEjAAMTAAgIjB6KCQClAgATAAgIjB6KCQClAgAUAAMIIhXGRgCrAAAAAA==.Emlyn:BAABLAAECoEjAAIVAAgIzBgeBQBXAgAVAAgIzBgeBQBXAgAAAA==.',En='Endorawen:BAAALAAECgQIBwAAAA==.Engallado:BAAALAAECgEIAQAAAA==.',Er='Eriag:BAAALAAECgUIEAAAAA==.',Ev='Evitana:BAAALAADCggIFQAAAA==.',Ex='Exto:BAAALAADCgQIBAAAAA==.',Fa='Faowyn:BAABLAAECoEgAAIGAAcIoR4yHABcAgAGAAcIoR4yHABcAgAAAA==.Fario:BAABLAAECoEZAAINAAcIGBWNLQCLAQANAAcIGBWNLQCLAQAAAA==.Farren:BAAALAAECgQIBAAAAA==.Fazil:BAAALAAECgYIEQAAAA==.',Fe='Fealinara:BAAALAAECggIEAAAAA==.Fellbuur:BAAALAAECggIBQAAAA==.Fenrus:BAABLAAECoEXAAIQAAcIcRn7CQASAgAQAAcIcRn7CQASAgAAAA==.Fenso:BAABLAAECoEnAAMOAAgIZBi4WgDTAQAOAAgIZBi4WgDTAQASAAYIdAkjbwDyAAAAAA==.Ferocita:BAAALAADCggIBwAAAA==.Ferrero:BAAALAAECgYIEQAAAA==.',Fr='Frostya:BAAALAADCgYIBgAAAA==.',Fu='Funker:BAAALAAECgYIEQAAAA==.',Fy='Fyera:BAACLAAFFIEFAAIWAAII9BMZDQCVAAAWAAII9BMZDQCVAAAsAAQKgSkAAhYACAiqFV4OABsCABYACAiqFV4OABsCAAAA.',['Fà']='Fàte:BAAALAADCgYICAAAAA==.',['Fá']='Fáelin:BAABLAAECoEUAAISAAgITRsuIQBIAgASAAgITRsuIQBIAgAAAA==.',['Fâ']='Fâromir:BAAALAADCggICAAAAA==.',['Fø']='Føgme:BAACLAAFFIELAAIUAAUItBh0AgDJAQAUAAUItBh0AgDJAQAsAAQKgRcAAhQACAg1Im0MALICABQACAg1Im0MALICAAAA.',Ga='Galateriar:BAAALAAECgEIAQAAAA==.Galdinos:BAABLAAECoEeAAIMAAgI0RVeGgAjAgAMAAgI0RVeGgAjAgAAAA==.Gannimed:BAAALAADCggIDgAAAA==.Gao:BAAALAADCggIEAAAAA==.Gardaf:BAABLAAECoEVAAIEAAYIHQwtOwBfAQAEAAYIHQwtOwBfAQAAAA==.Garrz:BAAALAAECgMIAwAAAA==.Gathor:BAAALAADCggIIQAAAA==.',Ge='Gehennas:BAAALAAECgYIBgAAAA==.Gelek:BAAALAADCgUIBQAAAA==.Gelino:BAAALAAECgYIEQAAAA==.',Gh='Ghazul:BAAALAAECgIIAgAAAA==.Ghostbloody:BAAALAAFFAIIAgAAAA==.',Gi='Giwolas:BAABLAAECoEZAAISAAcIPR4tIQBIAgASAAcIPR4tIQBIAgAAAA==.',Go='Gofri:BAACLAAFFIEIAAIXAAIIyhmlKQCuAAAXAAIIyhmlKQCuAAAsAAQKgS0AAhcACAgHHq8lALcCABcACAgHHq8lALcCAAAA.Gonduro:BAAALAADCgYIBgABLAAECgcICAABAAAAAA==.',Gr='Graell:BAAALAAECgEIAQABLAAECggIIAAUAMkdAA==.Gravitas:BAAALAADCgcIBwAAAA==.Greygella:BAAALAADCggICwAAAA==.Griegi:BAAALAAECggIDAAAAA==.Grishna:BAABLAAECoEgAAIEAAgI2QtRKgCqAQAEAAgI2QtRKgCqAQAAAA==.Grísu:BAAALAAECggIBwAAAA==.Grísû:BAAALAAECggICAAAAA==.',Gu='Gudebärbel:BAAALAAECgcICQAAAA==.Gundyr:BAAALAAECgUIBwAAAA==.Gunnhild:BAAALAAECgMIAwABLAAECgYIFgAKAM4jAA==.',['Gö']='Göttlicher:BAAALAADCggICAAAAA==.',Ha='Happyness:BAAALAAECgYIBgAAAA==.Haralt:BAAALAADCgUIBQAAAA==.',He='Hearis:BAACLAAFFIEGAAILAAII6h9gGgC+AAALAAII6h9gGgC+AAAsAAQKgSAAAgsACAgoJDQKAEMDAAsACAgoJDQKAEMDAAAA.Heartstopper:BAAALAAECggIEgAAAA==.Heilemacher:BAAALAAECgEIAQAAAA==.Heleth:BAABLAAECoEWAAIGAAcIXwW4eQDrAAAGAAcIXwW4eQDrAAAAAA==.Helior:BAAALAADCggICgABLAAECggIIAAUAMkdAA==.Heredia:BAAALAAECgEIAQAAAA==.',Ho='Hober:BAAALAAECgYIDQAAAA==.',Hu='Huaming:BAAALAADCggICAAAAA==.',['Há']='Háe:BAAALAAECgYICAABLAAECggIFAASAE0bAA==.',Ik='Ikmuss:BAABLAAECoEdAAIIAAgImBEJIQBuAQAIAAgImBEJIQBuAQAAAA==.',Il='Ilaia:BAAALAADCgUIBQAAAA==.Ilaydra:BAAALAAECgYICAAAAA==.Ilene:BAAALAAECgYIEgAAAA==.',Im='Imiòn:BAAALAADCgcICQAAAA==.Imâla:BAAALAAECgMIBQAAAA==.',In='Inaly:BAAALAADCggIFwAAAA==.Inucari:BAABLAAECoEXAAIPAAcIpho+TQArAgAPAAcIpho+TQArAgAAAA==.',Ir='Irillyth:BAABLAAECoEgAAIXAAgI4iFLIwDBAgAXAAgI4iFLIwDBAgAAAA==.',Is='Isop:BAAALAAECgYIDQAAAA==.',Iv='Ivija:BAAALAADCggIDQAAAA==.',Ix='Ixee:BAAALAAECggICAABLAAECggICAABAAAAAA==.',Iz='Izznix:BAAALAAECgEIAQAAAA==.',['Iô']='Iôn:BAABLAAECoEYAAIYAAgIOwwBWAC1AQAYAAgIOwwBWAC1AQAAAA==.',Ja='Jajîra:BAAALAAECgEIAgAAAA==.Jakru:BAAALAAECgMIAwAAAA==.Jazzuzzu:BAAALAADCgIIAgAAAA==.',Je='Jebit:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.Jeblo:BAAALAADCggICAABLAAECgQIBgABAAAAAA==.Jebrak:BAAALAAECgQIBgAAAA==.Jerah:BAAALAADCggICAAAAA==.',Jo='Joejitzu:BAAALAAECgYIEAAAAA==.Jolia:BAAALAAECgIIBAAAAA==.Jonáh:BAAALAAECgYIBgAAAA==.Jorbine:BAAALAADCggICAABLAAECggIHwAZAJcdAA==.',Ju='Ju:BAAALAADCgcIFQAAAA==.Juowha:BAAALAADCgYICQABLAAECgUIBQABAAAAAA==.',['Jè']='Jènteala:BAAALAADCgYIBgAAAA==.',Ka='Kalera:BAABLAAECoEVAAIDAAcIhxYLJgDRAQADAAcIhxYLJgDRAQAAAA==.Kalestra:BAAALAADCgUIBQAAAA==.Kaskan:BAAALAADCgYIBgAAAA==.Katran:BAACLAAFFIEPAAIJAAUIehqzBgDIAQAJAAUIehqzBgDIAQAsAAQKgSoAAgkACAgvJOMIADsDAAkACAgvJOMIADsDAAAA.Katrani:BAAALAAECgEIAQABLAAFFAYIDwAJAHoaAA==.Kazzuzzu:BAAALAAECgYIBgAAAA==.',Ke='Kennshïn:BAAALAAECgYIBgABLAAECggIIgAaACEcAA==.',Kh='Khale:BAAALAAECgYIDgAAAA==.Khrysalion:BAABLAAFFIEDAAIbAAMIOxsAAAAAAAAcAAMIOxsAAAAAAAAAAA==.Khálysta:BAABLAAECoEwAAIOAAgIRSFGFwDZAgAOAAgIRSFGFwDZAgAAAA==.Khâlé:BAAALAAECgYIDgAAAA==.',Ki='Kino:BAAALAADCgcIDQAAAA==.Kirai:BAACLAAFFIEQAAIdAAUISBkPAQCwAQAdAAUISBkPAQCwAQAsAAQKgTYAAx0ACAiwI5kEABIDAB0ACAiwI5kEABIDAAsABwhvGqdLABUCAAAA.Kizûna:BAAALAAECgcIEgAAAA==.',Kl='Kloppbot:BAAALAADCgYIBgAAAA==.Klárisá:BAAALAADCggICAAAAA==.',Kn='Knackl:BAAALAADCgEIAQAAAA==.',Ko='Korhambor:BAAALAAECgYIEgAAAA==.Koril:BAAALAAFFAIIAgAAAA==.',Kr='Krankfurt:BAAALAADCgcIBwABLAAECggIGgAeAPslAA==.Kreto:BAAALAAECgcIDgABLAAFFAYIDwAJAHoaAA==.Krôldh:BAAALAAECggICAAAAA==.Krôn:BAAALAADCggIDwAAAA==.',Ks='Kseniya:BAAALAAECgEIAQAAAA==.',Ku='Kuma:BAAALAAECgQIDAAAAA==.Kuroneko:BAAALAADCggIIAAAAA==.Kuscheltier:BAAALAADCgYIBgAAAA==.',['Kÿ']='Kÿra:BAAALAADCgcIBAAAAA==.',La='Laminia:BAAALAADCgUIBgAAAA==.Lanari:BAAALAAECgEIAQAAAA==.Lancelott:BAAALAADCgcICgAAAA==.Lanigerunum:BAAALAADCgcIDAAAAA==.Lannaei:BAAALAAECgYIDAAAAA==.Lapinkûlta:BAAALAAECgEIAQAAAA==.Larentía:BAAALAADCggIIAAAAA==.Laurabell:BAAALAADCggICAAAAA==.Lavenderhaze:BAAALAAECgYIBgAAAA==.Laxnaquen:BAAALAAECgEIAQAAAA==.Lazirus:BAABLAAECoEpAAIaAAgIXR58CgCGAgAaAAgIXR58CgCGAgAAAA==.',Le='Leergutlars:BAAALAAECggICwAAAA==.Leha:BAAALAAECgYIEQAAAA==.Lenneki:BAAALAAECgEIAgAAAA==.Leésha:BAAALAAECgYICgAAAA==.',Li='Liladulli:BAAALAAECggIAgAAAA==.Lindara:BAAALAAECgMIBQAAAA==.Liniu:BAABLAAECoEvAAIUAAgIwiQ9BQAqAwAUAAgIwiQ9BQAqAwAAAA==.Linorie:BAABLAAECoEfAAIPAAgIyg8XbADiAQAPAAgIyg8XbADiAQAAAA==.Lishadi:BAAALAAECgUIBQAAAA==.',Lo='Lokion:BAAALAADCgcIDQAAAA==.Lokuhmotive:BAAALAADCgcIBwABLAAECgYIFgAKAM4jAA==.Loradine:BAAALAAECgUIEAAAAA==.Lorelei:BAAALAAECgYICAAAAA==.Lormax:BAABLAAECoEbAAIfAAYINQ5BYQAzAQAfAAYINQ5BYQAzAQAAAA==.',Lu='Lucine:BAAALAAECggIBQAAAA==.Lucía:BAAALAAECgQIAgAAAA==.Lunastrasza:BAAALAAECgQIBAAAAA==.Lutzifer:BAAALAADCgEIAQAAAA==.',Ly='Lyanda:BAAALAADCggICAAAAA==.Lyekka:BAAALAAECgYIBgAAAA==.Lythandra:BAABLAAECoEcAAIOAAYIswcgvQAEAQAOAAYIswcgvQAEAQAAAA==.Lyândris:BAAALAADCgIIAgABLAAECggIIgAFAOkXAA==.',['Lí']='Lía:BAABLAAECoEZAAIUAAcIgAxtLABvAQAUAAcIgAxtLABvAQAAAA==.Líoba:BAAALAADCggIHwAAAA==.Líranda:BAABLAAECoEYAAIOAAcIMB8+PgAnAgAOAAcIMB8+PgAnAgAAAA==.',['Lî']='Lîrania:BAACLAAFFIEIAAIKAAMIERanDgAOAQAKAAMIERanDgAOAQAsAAQKgS4AAgoACAh5HlUeAK0CAAoACAh5HlUeAK0CAAAA.',['Lï']='Lïllïth:BAAALAAECgIIAgAAAA==.',Ma='Maevia:BAABLAAECoEbAAIMAAYIQhs9IgDoAQAMAAYIQhs9IgDoAQAAAA==.Magnaclysm:BAABLAAECoEhAAIYAAgI+xLTSADpAQAYAAgI+xLTSADpAQAAAA==.Magneria:BAABLAAECoEZAAIfAAcIVhNoQQCtAQAfAAcIVhNoQQCtAQAAAA==.Mallesein:BAAALAAECgEIAQAAAA==.Mamoulian:BAABLAAECoEcAAMcAAcIIxnZLACZAQAcAAcIIxnZLACZAQAWAAIIrQf3NQBIAAAAAA==.Marjorie:BAABLAAECoEaAAIOAAgIoiBFFwDZAgAOAAgIoiBFFwDZAgAAAA==.Maugrin:BAAALAAECgEIAgAAAA==.Mausepfote:BAAALAADCgEIAQAAAA==.',Mc='Mcmuffin:BAAALAADCgcIDQAAAA==.',Me='Megamhax:BAAALAAECgMIBAAAAA==.Megatronix:BAAALAADCggIHwAAAA==.Meiread:BAAALAAECgYIEwAAAA==.Menori:BAABLAAECoEfAAIgAAgInh4YGgDaAgAgAAgInh4YGgDaAgABLAAFFAIIAgABAAAAAA==.Mephestos:BAAALAAECgIIAgAAAA==.Merador:BAABLAAECoEaAAISAAcIphodJwAgAgASAAcIphodJwAgAgAAAA==.Merian:BAABLAAECoEiAAIOAAgICQYvswAZAQAOAAgICQYvswAZAQAAAA==.',Mi='Miriael:BAAALAAECgYIEAAAAA==.Miyani:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Mj='Mjernia:BAABLAAECoEbAAINAAYIdx46GwAIAgANAAYIdx46GwAIAgAAAA==.',Mo='Mondbärchen:BAAALAADCgYIEgAAAA==.Monklich:BAAALAADCggIDAAAAA==.Morì:BAAALAAECgUIBwABLAAECggIDQABAAAAAA==.Moríturus:BAAALAAECggIDQAAAA==.Moshu:BAAALAADCgEIAQAAAA==.',Mu='Muecke:BAAALAAECgMIAwAAAA==.Mugz:BAAALAADCggICAAAAA==.Muhevia:BAAALAADCgcIBwAAAA==.Muranox:BAAALAADCggIIgAAAA==.Murmon:BAAALAADCggIFgAAAA==.Murthayus:BAAALAADCggICAAAAA==.Murxidruid:BAAALAADCgYICwAAAA==.',My='Mycenas:BAAALAAECgMIAwAAAA==.Myhenea:BAAALAAECgIIAgAAAA==.Mythar:BAAALAAECgMIBAAAAA==.',['Mà']='Màrzael:BAAALAAECgYIBgAAAA==.',['Mê']='Mêdusa:BAABLAAECoEUAAIhAAgI1RmDDgCtAQAhAAgI1RmDDgCtAQAAAA==.',['Mí']='Míu:BAABLAAECoEYAAILAAYIQiAHRQApAgALAAYIQiAHRQApAgABLAAECggIIAADAPEdAA==.',['Mü']='Mützchen:BAAALAAECgcIDgAAAA==.',Na='Naaruda:BAAALAAECgYIEQAAAA==.Nahr:BAABLAAECoEVAAIdAAcIuATZNgDbAAAdAAcIuATZNgDbAAAAAA==.Najm:BAAALAAECgYIBgAAAA==.Nathasil:BAAALAADCgQIBgABLAAECgEIAgABAAAAAA==.Nathasìl:BAAALAAECgEIAgAAAA==.Nathasíl:BAAALAADCgEIAQABLAAECgEIAgABAAAAAA==.Navani:BAAALAAECggIAwAAAA==.',Ne='Nehmoc:BAAALAAECgMIAwAAAA==.Nenodor:BAAALAAECgIIBgAAAA==.Nerio:BAAALAAECgMIAwAAAA==.Newton:BAAALAAECgYIBgAAAA==.Neyja:BAAALAADCgYIBgAAAA==.',Ni='Niewinter:BAAALAAECgcIEgAAAA==.Nimsu:BAAALAADCgcIBwABLAADCggIIAABAAAAAA==.Nimêa:BAAALAADCgcIBwABLAAECggIIgAiAEcRAA==.Nithilam:BAAALAAECgEIAQAAAA==.',Nj='Njorthr:BAAALAADCggICAAAAA==.',No='Nocturne:BAAALAAECgcIBwAAAA==.Noktua:BAAALAAECgQIDAAAAA==.Nordschrott:BAABLAAECoEUAAIOAAcIlBeybQClAQAOAAcIlBeybQClAQAAAA==.',Nu='Numerobis:BAAALAADCggIHQAAAA==.Nuraná:BAAALAAECggIEAAAAA==.',['Nò']='Nòah:BAAALAAECgYIBgAAAA==.',['Nø']='Nøtdeadyet:BAABLAAECoEUAAIXAAYIaiGcSAA+AgAXAAYIaiGcSAA+AgAAAA==.',Ob='Oberguffel:BAAALAAECgcIEgAAAA==.Obscuriya:BAAALAADCggIDwAAAA==.',Od='Odoniel:BAABLAAECoEZAAMGAAcIJg89UwBfAQAGAAcIJg89UwBfAQAQAAYIngjMHADnAAAAAA==.',Ok='Okeanos:BAAALAAECgEIAgAAAA==.Okonawa:BAAALAAECgMIAwAAAA==.',Ol='Olivinia:BAAALAAECgYIBgABLAAECgcIGAAOADAfAA==.Olywol:BAAALAADCgcIBwAAAA==.',Or='Ormoga:BAAALAADCgMIAwAAAA==.',Pa='Pachini:BAABLAAECoEiAAIiAAgIRxGKCAAJAgAiAAgIRxGKCAAJAgAAAA==.Paldoro:BAAALAAECgMIAwAAAA==.Parva:BAAALAAECgYIEQAAAA==.Pastoria:BAAALAADCggIFwAAAA==.',Pe='Peridox:BAAALAAECgIIAgAAAA==.Peterpool:BAAALAADCgcIBwAAAA==.',Pi='Pistacia:BAAALAAECggICgAAAA==.',Pl='Plux:BAABLAAECoEVAAIJAAgI7yA4DwADAwAJAAgI7yA4DwADAwAAAA==.Pluxp:BAAALAADCggICwABLAAECggIFQAJAO8gAA==.',Pr='Preto:BAAALAADCgcICAAAAA==.Primitive:BAAALAAECgcIEwAAAA==.Prito:BAAALAAECgIIAgAAAA==.Proteus:BAAALAAECgMIBQAAAA==.',Pu='Pualani:BAAALAADCgcIEQAAAA==.',Qa='Qahonji:BAAALAAECgUIBQAAAA==.',Qi='Qishi:BAAALAAECggICAAAAA==.',Qu='Quenzah:BAAALAAECgcICgABLAAECggIJAAfAP4QAA==.Quigongin:BAAALAADCggIEQAAAA==.Quíntás:BAABLAAECoEUAAIFAAYI4ggzXwD8AAAFAAYI4ggzXwD8AAAAAA==.',Ra='Ragar:BAAALAADCggIIAAAAA==.Ravienna:BAAALAADCggIKQAAAA==.',Re='Reapêr:BAAALAAECggIDgAAAA==.Reylah:BAAALAADCgIIAgAAAA==.',Rh='Rhapsodi:BAABLAAECoElAAIOAAgI0xFdYgDAAQAOAAgI0xFdYgDAAQAAAA==.Rhænira:BAAALAAECgIIAgAAAA==.',Ri='Ricciie:BAAALAADCgQIBAAAAA==.Rikya:BAAALAAECgYIEgAAAA==.Rilion:BAAALAAECgUICAABLAAECgYICwABAAAAAA==.',Rm='Rmf:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.',Ro='Rokket:BAAALAADCgcIFwAAAA==.Rornagh:BAAALAAECgYIEAAAAA==.Rosâlia:BAAALAAECggIIAAAAQ==.Rosâlin:BAAALAADCggICAABLAAECggIIAABAAAAAQ==.Rozao:BAAALAADCggIFQAAAA==.',Ru='Runeknight:BAAALAAECgIIAwAAAA==.Ruyan:BAAALAADCggIDAABLAADCggIIAABAAAAAA==.',['Rí']='Rísha:BAAALAAECgYIEAAAAA==.',Sa='Sa:BAABLAAECoEZAAINAAgIFxGZIQDYAQANAAgIFxGZIQDYAQAAAA==.Sachíko:BAAALAADCgcIBwAAAA==.Sagarem:BAAALAAECgEIAQAAAA==.Sahloknir:BAAALAADCggICAAAAA==.Saiyanjin:BAAALAAECgYIDwAAAA==.Sanilor:BAABLAAECoEWAAIjAAYIsQKFbgCuAAAjAAYIsQKFbgCuAAAAAA==.Saninana:BAAALAAECgcIDQAAAA==.Sanjana:BAAALAADCgIIAgAAAA==.Sanjib:BAAALAADCggICAAAAA==.Santee:BAABLAAECoEYAAIJAAcItgLeggDcAAAJAAcItgLeggDcAAAAAA==.Sarania:BAAALAADCgcIBwAAAA==.Sasakurina:BAACLAAFFIESAAIkAAUIaCESAQDzAQAkAAUIaCESAQDzAQAsAAQKgSMAAiQACAg0Jc4AAHMDACQACAg0Jc4AAHMDAAAA.Sasorì:BAAALAAECgYIBgAAAA==.Sayu:BAAALAAECggICAAAAA==.',Sc='Scaath:BAAALAAECgEIAgAAAA==.Scabbs:BAAALAAECgMIBQAAAA==.Scariel:BAABLAAECoEVAAIdAAYIESDNEgASAgAdAAYIESDNEgASAgAAAA==.Schamun:BAAALAAECgQIBAABLAAECggIHQAIAJgRAA==.Schattentânz:BAABLAAECoEiAAIfAAcIzw92UQBsAQAfAAcIzw92UQBsAQAAAA==.Schnurlo:BAAALAADCgcICwAAAA==.Schoki:BAAALAAECgUIBgAAAA==.Schwupps:BAAALAAECgEIAQAAAA==.Schûrlo:BAAALAAECgEIAgAAAA==.',Se='Secalla:BAAALAAECgcIEwAAAA==.Sedei:BAAALAADCggIEAABLAAECggIEQABAAAAAA==.Seleria:BAAALAADCggIJAAAAA==.Semará:BAAALAAECggIEAAAAA==.Seraphìne:BAAALAAECggIDgAAAA==.Seredana:BAAALAADCggIDAAAAA==.Setsukô:BAAALAAECgUIBQAAAA==.',Sh='Shadowclaw:BAAALAADCgEIAQAAAA==.Shadrox:BAAALAAECggICAAAAA==.Shaita:BAAALAADCgQIBAAAAA==.Shellox:BAAALAADCgQIBAAAAA==.Sherin:BAAALAADCggICAAAAA==.Shinx:BAAALAAECgUIDwAAAA==.Shizuna:BAAALAAECgYIBgABLAAECgcIGAAOACAhAA==.Shorma:BAAALAAECgEIAQABLAAECgYIFQAEAB0MAA==.',Si='Silberhauch:BAAALAAECgQIAgAAAA==.Simsala:BAAALAAECggIEAAAAA==.',Sl='Sloptok:BAAALAAECgYIEQAAAA==.',So='Solveîg:BAAALAADCgYIBgAAAA==.Sorinera:BAAALAADCggIHwAAAA==.',Sp='Spaceradio:BAAALAAECggICAAAAA==.Sphärensturm:BAAALAAECgYIEQAAAA==.',Su='Sugrem:BAABLAAECoEbAAITAAYIgBK1JgAiAQATAAYIgBK1JgAiAQAAAA==.Sushigenesis:BAABLAAECoEgAAMJAAgIfx/BNgADAgAJAAYIfx7BNgADAgACAAQItR7TewBSAQAAAA==.',Sw='Swàfnir:BAAALAADCgcIBwAAAA==.',Sy='Sylvaran:BAAALAAECgMIAwAAAA==.Syphondaddy:BAAALAADCggICAABLAAFFAIIBgAGAOEgAA==.Syrenya:BAAALAAECgEIAQAAAA==.',['Sê']='Sêtsuko:BAABLAAECoEgAAIPAAgIlhqdOABpAgAPAAgIlhqdOABpAgAAAA==.',['Só']='Sóul:BAAALAAECgcIDwAAAA==.',Ta='Taitus:BAAALAADCgIIAgAAAA==.Talesin:BAAALAAECgYIEgAAAA==.Tamarök:BAAALAAECgIIAgAAAA==.Tanariel:BAAALAADCggIBgAAAA==.Taslyn:BAAALAAECgYIEQAAAA==.Taurantulas:BAABLAAECoEkAAIPAAcI+xDRmACMAQAPAAcI+xDRmACMAQAAAA==.Taurea:BAAALAAECgUIBwAAAA==.Tavyun:BAAALAAECgYIDQAAAA==.Tavzul:BAAALAADCgcIBwAAAA==.Taytay:BAAALAAECgYIBgAAAA==.',Te='Tegtha:BAABLAAECoEiAAQaAAgIIRz7CgB7AgAaAAgIIRz7CgB7AgAXAAQIBgipDwGyAAARAAMIpBLuQACjAAAAAA==.Tegtharossa:BAAALAAECgYIBgABLAAECggIIgAaACEcAA==.Tepra:BAABLAAECoEUAAINAAcIqBnFGwAFAgANAAcIqBnFGwAFAgAAAA==.Teruno:BAABLAAECoEyAAIMAAgIIyHzDwCKAgAMAAgIIyHzDwCKAgAAAA==.Tesalonar:BAABLAAECoEYAAILAAYI4Q6foABXAQALAAYI4Q6foABXAQAAAA==.Tesaríus:BAAALAAECgIIAgABLAAECgcIGAAOADAfAA==.',Th='Thabia:BAAALAAECgEIAgAAAA==.Thaeyoung:BAAALAAECgYIEAAAAA==.Tharukko:BAABLAAECoEcAAIiAAgIABk1BQBqAgAiAAgIABk1BQBqAgAAAA==.Thel:BAAALAADCgMIAwAAAA==.Theldar:BAAALAAECgYICwAAAA==.Thespirit:BAAALAAECgIIAgAAAA==.Thirius:BAAALAADCggIBQAAAA==.Thoknar:BAAALAAECggICwAAAA==.Throbon:BAAALAADCggICQAAAA==.Thurianx:BAAALAAECgMIBQAAAA==.',Ti='Tifferny:BAAALAADCgUIBQABLAAECgcIFgAJAKYHAA==.Tijuanah:BAAALAAECgYIBgAAAA==.Timber:BAAALAAECgEIAQAAAA==.Tirimira:BAABLAAECoEXAAIPAAcIxwe1wABEAQAPAAcIxwe1wABEAQAAAA==.',To='Tollas:BAAALAADCgUIBQAAAA==.Tolpana:BAAALAADCgcIEQAAAA==.Torwin:BAAALAADCgYIBgAAAA==.Toshan:BAABLAAECoEVAAIOAAYILxnUcQCbAQAOAAYILxnUcQCbAQAAAA==.Toxicus:BAAALAAECggICAAAAA==.',Tr='Tramaios:BAAALAADCggIJQAAAA==.Trineas:BAABLAAECoEkAAIfAAgI/hBiNwDcAQAfAAgI/hBiNwDcAQAAAA==.Truppenküche:BAABLAAECoEaAAIeAAgI+yVEAACAAwAeAAgI+yVEAACAAwAAAA==.',Tu='Tullios:BAAALAADCgcIBwAAAA==.Turgarn:BAABLAAECoEVAAIPAAgILgI9FQGDAAAPAAgILgI9FQGDAAAAAA==.',Ty='Ty:BAAALAADCggIIgAAAA==.',Tz='Tzahiko:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.',['Tí']='Tíamat:BAAALAAECggICAAAAA==.',['Tô']='Tôrvûs:BAAALAAECgYIEwAAAA==.',Ur='Urique:BAAALAAECgEIAgAAAA==.',Uz='Uzur:BAAALAADCggILwAAAA==.Uzziel:BAAALAADCgUIBQAAAA==.',Va='Vagnard:BAABLAAECoEaAAIYAAgIawuYZwCHAQAYAAgIawuYZwCHAQAAAA==.',Ve='Velrax:BAACLAAFFIELAAIIAAUIDR83AgDsAQAIAAUIDR83AgDsAQAsAAQKgSwAAwgACAjkIw8DAC0DAAgACAjkIw8DAC0DABQABwhQFWgjALMBAAAA.Venati:BAAALAAECgYIDgAAAA==.',Vh='Vhegar:BAAALAAECgYIEQAAAA==.',Vi='Viktarion:BAAALAADCgYIBgABLAAECggIHQAIAJgRAA==.Vitória:BAAALAAECgEIAQAAAA==.',Vo='Voilia:BAAALAADCgcIDgAAAA==.',Vr='Vrugnir:BAAALAADCgYIBgAAAA==.',Vu='Vul:BAAALAADCgcIDQAAAA==.',Wa='Wacholder:BAAALAAECgUIBQAAAA==.Walfaras:BAABLAAECoEcAAIlAAgIrR39BACvAgAlAAgIrR39BACvAgAAAA==.',Wi='Wimi:BAAALAADCgcIBwAAAA==.Wintersturm:BAAALAADCggICAAAAA==.Wirbelwind:BAABLAAECoEjAAMEAAcIExXUIQDYAQAEAAcIExXUIQDYAQAYAAIIWQ4AAAAAAAAAAA==.Wiwaria:BAABLAAECoEbAAMCAAcI4B8dIABzAgACAAcI4B8dIABzAgAJAAYIZh96OgDyAQAAAA==.',Wo='Wolfgáng:BAAALAADCggIDAAAAA==.',['Wì']='Wìwarux:BAAALAAECgYIBgAAAA==.',['Wí']='Wíwa:BAAALAADCgcICQAAAA==.Wíwarux:BAAALAAECgYIDAAAAA==.',Xa='Xantorakk:BAAALAAECgQIBgAAAA==.',Xc='Xcyy:BAAALAAECggICAABLAAECggIHQAXAJ4kAA==.',Xe='Xeranova:BAAALAAECggICAAAAA==.',Xh='Xhantós:BAAALAAECgYIBgAAAA==.',Xi='Xiaody:BAAALAAECgYIEAAAAA==.Xippy:BAAALAADCgcIHQAAAA==.Xishi:BAAALAADCgcIDgAAAA==.Xixie:BAAALAADCggIEAAAAA==.',Xr='Xris:BAAALAAECgEIAgAAAA==.',['Xí']='Xíaomei:BAAALAADCgYIBgAAAA==.',Ya='Yasuko:BAAALAAECgYICAAAAA==.Yasumi:BAAALAADCggIFAAAAA==.',Ye='Yelnyfy:BAABLAAECoEdAAIOAAYILQqpuQAMAQAOAAYILQqpuQAMAQAAAA==.Yeni:BAAALAADCgcIBwAAAA==.Yeserá:BAAALAADCggICQAAAA==.',Ys='Yskiera:BAAALAADCggIHgAAAA==.',Yt='Ytonia:BAAALAAECgIIAwAAAA==.',Yu='Yulson:BAAALAAECgIIAgAAAA==.Yuuji:BAABLAAECoEeAAIIAAYIOhq6GwCnAQAIAAYIOhq6GwCnAQAAAA==.',Yv='Yvessaint:BAAALAAECgEIAQAAAA==.',Yy='Yyd:BAABLAAECoEdAAMXAAYIniS9VQAbAgAXAAYIniS9VQAbAgAaAAEI6AYdQgAmAAAAAA==.',Za='Zakwen:BAABLAAECoEaAAIfAAcIzRaDNwDbAQAfAAcIzRaDNwDbAQAAAA==.Zangan:BAAALAAECgEIAgAAAA==.Zavarelia:BAAALAAECgUICAAAAA==.',Ze='Zelós:BAAALAAECgQIBAAAAA==.Zeraide:BAACLAAFFIELAAIGAAMIExkTCwDvAAAGAAMIExkTCwDvAAAsAAQKgS0AAwYACAggH2oNANECAAYACAggH2oNANECAAUABghGBcRqAMEAAAAA.',Zi='Zidane:BAABLAAECoEUAAICAAUI9h57ZgCIAQACAAUI9h57ZgCIAQAAAA==.Ziry:BAAALAADCggICAAAAA==.',Zu='Zuajh:BAAALAADCgUIBQAAAA==.Zuanoro:BAAALAAECgEIAQAAAA==.',Zy='Zyr:BAABLAAECoEUAAIfAAcIsx1fIQBTAgAfAAcIsx1fIQBTAgAAAA==.',['Zê']='Zêraphina:BAAALAADCgQIBAAAAA==.',['Àu']='Àurorá:BAABLAAECoEgAAIXAAgI0BdkUQAmAgAXAAgI0BdkUQAmAgAAAA==.',['Ár']='Árwên:BAAALAAECgIIAgAAAA==.',['Âm']='Âmanvah:BAAALAADCgIIAgAAAA==.',['Çr']='Çrispy:BAAALAAECggIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end