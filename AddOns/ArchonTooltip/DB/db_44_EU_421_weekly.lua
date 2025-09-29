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
 local lookup = {'Unknown-Unknown','Warrior-Protection','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Feral','Rogue-Assassination','Monk-Windwalker','Druid-Restoration','Hunter-BeastMastery','Paladin-Retribution','Warrior-Fury','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Paladin-Protection','DemonHunter-Havoc','Mage-Frost','Mage-Arcane','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','DemonHunter-Vengeance','Evoker-Devastation','Rogue-Outlaw','Warrior-Arms','Monk-Mistweaver','Priest-Holy','Priest-Discipline','Evoker-Preservation','Monk-Brewmaster','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Evoker-Augmentation',}; local provider = {region='EU',realm='DieSilberneHand',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abendelf:BAAALAADCgcIDAABLAAECgYIDwABAAAAAA==.Abidana:BAABLAAECoEpAAICAAcIfCHFDwCWAgACAAcIfCHFDwCWAgAAAA==.Abuduhn:BAAALAADCgcIEwAAAA==.',Af='Afra:BAAALAAECgYIEQAAAA==.',Ag='Agarwal:BAAALAADCgYIBgAAAA==.Agrotera:BAAALAAECgYIDgAAAA==.Agua:BAAALAADCgMIAwAAAA==.',Ah='Ahrline:BAAALAAECgYIEAABLAAECgcIHwADAEMSAA==.',Ai='Ainzsama:BAABLAAECoEhAAQEAAcINxA8JwC6AQAEAAcI/g88JwC6AQAFAAQISw41ogDiAAAGAAEIcQGFQQAiAAAAAA==.Aiwa:BAAALAADCgYIBgAAAA==.',Aj='Ajden:BAAALAAECgYICgAAAA==.',Al='Aldoron:BAABLAAECoEmAAIHAAgIaRLxEwDwAQAHAAgIaRLxEwDwAQAAAA==.Aleshaa:BAAALAAECggICAAAAA==.Alysria:BAABLAAECoEcAAIIAAYIWw1cOQBkAQAIAAYIWw1cOQBkAQAAAA==.',An='Andamyon:BAABLAAECoEgAAIJAAcIdQfQNgApAQAJAAcIdQfQNgApAQAAAA==.Andella:BAABLAAECoEZAAIKAAcINw4WWABOAQAKAAcINw4WWABOAQAAAA==.Anicaya:BAABLAAECoEhAAILAAgIuBwcLwBfAgALAAgIuBwcLwBfAgAAAA==.Anjaly:BAAALAADCgYIBgAAAA==.Ann:BAAALAAECgEIAQAAAA==.',Ap='Apfelmus:BAAALAAECgUICQAAAA==.',Ar='Arabesch:BAAALAADCggIHgAAAA==.Arathria:BAAALAAECggIBQAAAA==.Argôrôk:BAAALAADCgcIBwAAAA==.Arndor:BAAALAADCggIEwAAAA==.Artos:BAABLAAECoEUAAIMAAgIrhk5SQA2AgAMAAgIrhk5SQA2AgAAAA==.',As='Ashesnay:BAAALAAFFAEIAQAAAA==.Ashkatan:BAAALAAECgYIDwAAAA==.Askária:BAAALAADCgQIBAAAAA==.Asraêl:BAAALAADCggIDQABLAAFFAIICgANAMEUAA==.',At='Atomick:BAAALAAECgYIDQAAAA==.Atomreaktor:BAABLAAECoEkAAMOAAgIkhfRNgAVAgAOAAgIkhfRNgAVAgAPAAcInxW0OQD1AQAAAA==.',Au='Aurorah:BAAALAADCggIEAAAAA==.',Av='Avaani:BAAALAAECgYIBwAAAA==.Avaborg:BAABLAAECoEmAAIQAAgIxRFIJADHAQAQAAgIxRFIJADHAQAAAA==.Avany:BAAALAAECggIEAAAAA==.Avastor:BAABLAAECoEgAAINAAcIhxayTQDRAQANAAcIhxayTQDRAQAAAA==.Avathrea:BAAALAAECgUICQAAAA==.',Aw='Awacs:BAAALAADCggICAAAAA==.',Ax='Axerisa:BAAALAAECggICAAAAA==.Axoran:BAAALAADCggIEAAAAA==.',Az='Azante:BAAALAADCgEIAQAAAA==.Azôra:BAAALAAECgYIEQABLAAECgYIEgABAAAAAA==.',Ba='Baldak:BAAALAAECgcIEwAAAA==.Balder:BAAALAAECgcICQAAAA==.Banxor:BAAALAADCgYIBgAAAA==.Barø:BAAALAADCggICAAAAA==.',Be='Beasle:BAAALAADCggIDwAAAA==.Beerus:BAAALAAECggICAABLAAECggIEAABAAAAAA==.Belicia:BAAALAAECgYICgAAAA==.Beliseth:BAAALAADCgYIBgABLAAECgYIEQABAAAAAA==.Bengalosius:BAABLAAECoEWAAIRAAYIhRfOJgCKAQARAAYIhRfOJgCKAQAAAA==.',Bi='Biatesh:BAAALAADCgIIAgABLAAFFAMICwASALUiAA==.Bisca:BAAALAAECgQICAAAAA==.',Bl='Blaizé:BAABLAAECoEeAAMTAAgIhh3OFwA7AgATAAgIyhzOFwA7AgAUAAgIlhNeSAAOAgAAAA==.Bluedragon:BAAALAADCgcIBwABLAAECggIEAABAAAAAA==.',Bo='Bofur:BAAALAAECggICwABLAAECggIEQABAAAAAA==.Boghanik:BAABLAAECoEgAAILAAgIhg7bdACVAQALAAgIhg7bdACVAQAAAA==.Bokarl:BAABLAAECoEdAAIVAAYIoSKuIABLAgAVAAYIoSKuIABLAgAAAA==.Boudika:BAAALAADCgMIAwAAAA==.',Br='Brokenheart:BAAALAADCggIFgAAAA==.Brokkoli:BAAALAADCgcIBwAAAA==.Brotbart:BAABLAAECoEnAAIWAAgIciW3AQA2AwAWAAgIciW3AQA2AwAAAA==.Bruebaeck:BAABLAAECoEWAAMXAAYI3RcmPQCRAQAXAAYI3RcmPQCRAQAKAAYIdAgNfADkAAAAAA==.',['Bø']='Bøømér:BAAALAADCggICAAAAA==.',Ca='Caivena:BAAALAAECggICAAAAA==.Caliosta:BAABLAAECoEZAAITAAcISxvvGgAeAgATAAcISxvvGgAeAgAAAA==.Caltis:BAAALAADCggIHgAAAA==.Calypsó:BAAALAAECgQIDAAAAA==.Calyxor:BAAALAADCggIEQABLAADCggIIAABAAAAAA==.Caorlas:BAAALAAECgIIAwAAAA==.',Ce='Cerio:BAABLAAECoEkAAQYAAgIpBj3DABuAgAYAAgItBb3DABuAgADAAcIKRffFQDAAQAZAAYIZQYr9AD0AAAAAA==.',Ch='Chiella:BAAALAAECgMIAwAAAA==.',Cl='Cloudy:BAABLAAECoEaAAILAAcIPx9gPwAjAgALAAcIPx9gPwAjAgAAAA==.',Co='Coonie:BAAALAAECgIIAwAAAA==.Coraleen:BAABLAAECoEpAAILAAgIJyQ5CgAuAwALAAgIJyQ5CgAuAwAAAA==.',Cp='Cptmuhrica:BAABLAAECoEaAAIRAAcI+CCWDACGAgARAAcI+CCWDACGAgAAAA==.',Cr='Crud:BAAALAADCggICQAAAA==.Crìxus:BAAALAAECggIDQAAAA==.',Cy='Cylax:BAABLAAECoEXAAIKAAYIdyMrGwBjAgAKAAYIdyMrGwBjAgAAAA==.Cylith:BAAALAADCggICAAAAA==.',['Câ']='Câstle:BAAALAADCggIEwAAAA==.',Da='Daedric:BAEBLAAECoEmAAIaAAgIwhjhIABPAgAaAAgIwhjhIABPAgAAAA==.Daongel:BAAALAAECgYIEQAAAA==.Darklee:BAAALAAECgQIBAAAAA==.',De='Dean:BAAALAAECgcICgABLAAECggIEgABAAAAAA==.Delia:BAAALAAECgcIEwAAAA==.Delidiit:BAAALAAECgYIDgAAAA==.Desastro:BAAALAADCgcIBwAAAA==.Desi:BAAALAAECgYICQAAAA==.Devola:BAAALAAECgMIAwAAAA==.Devoma:BAAALAAECgYIDgAAAA==.',Dh='Dholâs:BAAALAADCgEIAQAAAA==.',Di='Dice:BAEALAADCggICAABLAAECggIJgAaAMIYAA==.',Do='Dobbs:BAAALAAECggIEAAAAA==.Doose:BAAALAAECgYIEAABLAAECggIJgAbAH8kAA==.Dorienne:BAABLAAECoEeAAIMAAgISxavUwAaAgAMAAgISxavUwAaAgAAAA==.Dormelosch:BAAALAAECgQICgAAAA==.',Dr='Dragonkai:BAAALAADCggIDgAAAA==.Drapthor:BAAALAAECgYIDgAAAA==.Drathul:BAABLAAECoEhAAMFAAgIXxpSKAB5AgAFAAgIXxpSKAB5AgAEAAII9gjPcwBwAAAAAA==.Dream:BAAALAAECgYICgAAAA==.Dryade:BAABLAAECoEeAAIXAAcIAh7lHQBHAgAXAAcIAh7lHQBHAgAAAA==.',Du='Durula:BAAALAADCgUIBwAAAA==.',Dv='Dvolin:BAAALAAECgYIBgABLAAECgcIHgAXAAIeAA==.',['Dä']='Dämonensepp:BAAALAADCgYIBgAAAA==.',['Dê']='Dêilm:BAAALAAECgYIBgAAAA==.Dêmônâ:BAAALAADCggICAAAAA==.',Ei='Eisenerwolf:BAAALAAECgYIEgAAAA==.',Ek='Ekko:BAAALAADCgYIBgAAAA==.',El='Elosion:BAAALAADCgcIBwAAAA==.Elowin:BAAALAADCgEIAQAAAA==.Elpis:BAAALAAECgIIAgAAAA==.Elysya:BAAALAADCggIGAAAAA==.',Em='Emphirian:BAAALAADCgcIBwAAAA==.',En='Enjia:BAACLAAFFIEJAAIPAAMICBZ3DgAFAQAPAAMICBZ3DgAFAQAsAAQKgSEAAg8ACAhFH64VAM8CAA8ACAhFH64VAM8CAAAA.',Eo='Eosan:BAAALAAECgYIEAAAAA==.',Er='Erilar:BAAALAADCgcIBwAAAA==.',Es='Escadâ:BAAALAAECgcIEQAAAA==.Eshira:BAAALAAECgYIBgAAAA==.',Ex='Exorr:BAABLAAECoEmAAIcAAgI8SQDAwBWAwAcAAgI8SQDAwBWAwAAAA==.Exxiil:BAAALAAECgYICAAAAA==.',Ez='Ezhno:BAAALAADCggICAAAAA==.',Fa='Fahliell:BAABLAAECoEXAAIGAAYIgBzaCwDaAQAGAAYIgBzaCwDaAQAAAA==.Fanjuur:BAABLAAECoEjAAIUAAgIug41UwDrAQAUAAgIug41UwDrAQAAAA==.Farina:BAAALAAECgEIAQAAAA==.',Fe='Fear:BAABLAAECoEUAAISAAgIQSRRGgDjAgASAAgIQSRRGgDjAgAAAA==.Feelizitaz:BAABLAAECoEqAAIOAAgIlBjQMwAgAgAOAAgIlBjQMwAgAgAAAA==.Fennecy:BAAALAAECggIEAAAAA==.Ferasina:BAAALAADCgcIFAAAAA==.Ferengar:BAABLAAECoE9AAILAAgI3CL2EwDsAgALAAgI3CL2EwDsAgAAAA==.',Fi='Fidala:BAAALAAECgYIDgAAAA==.Fintia:BAAALAADCggIFQAAAA==.Fizzeline:BAAALAAECgYIEwAAAA==.',Fl='Flodur:BAAALAADCgEIAQAAAA==.',Fr='Frathak:BAAALAAECgIIAgABLAAECgMIBgABAAAAAA==.Frostfeuer:BAEALAAECgEIAQABLAAECggIJgAaAMIYAA==.Frotheg:BAAALAADCgYIBgAAAA==.',Fu='Furyos:BAABLAAECoEgAAIWAAgIACIsAwD6AgAWAAgIACIsAwD6AgAAAA==.',['Fá']='Fálah:BAAALAADCggIFQAAAA==.',['Fæ']='Fæydra:BAAALAADCggIDQABLAAECggIJAAZALoeAA==.',Ga='Gagatchar:BAAALAAECgcIBwAAAA==.Galathiêl:BAABLAAECoEVAAILAAgISgRXyADpAAALAAgISgRXyADpAAAAAA==.Garudan:BAAALAAECgYIBgAAAA==.Gaxryn:BAAALAAECgYICwABLAAFFAMIDAAEAGceAA==.',Ge='Gemmy:BAAALAAECgQIBAAAAA==.Geryzen:BAAALAADCggICAAAAA==.',Gh='Ghostangel:BAAALAAECgYICQAAAA==.',Gi='Gimris:BAAALAAECgYICQAAAA==.Ginkou:BAAALAADCgcIBwAAAA==.',Gl='Glaïmbar:BAAALAAECgYIDgAAAA==.',Go='Goran:BAAALAADCgMIAwAAAA==.',Gr='Gravejinx:BAABLAAECoEZAAIdAAcIlA3ECwCVAQAdAAcIlA3ECwCVAQAAAA==.Grimbearon:BAABLAAECoEWAAILAAYIVAiZvQADAQALAAYIVAiZvQADAQAAAA==.Grimthul:BAAALAAECgYICAAAAA==.Grisù:BAAALAAECgYIDgAAAA==.Gromnur:BAAALAAECgYIDgAAAA==.Growler:BAAALAAECgYIEgAAAA==.Gruldan:BAAALAADCggIGAAAAA==.',Gu='Guldumeek:BAABLAAECoEeAAIHAAYIChmWFwDDAQAHAAYIChmWFwDDAQAAAA==.',Gy='Gyngyn:BAAALAAECgYIDgAAAA==.Gywania:BAAALAAECgYIEQAAAA==.',['Gá']='Gálbartorix:BAAALAAECgMIBwAAAA==.',['Gî']='Gîselle:BAAALAAECgYIEQAAAA==.',['Gü']='Gül:BAAALAADCggIFAABLAAFFAIICgANAMEUAA==.',Ha='Habeera:BAAALAAECgYIBwAAAA==.Halfar:BAAALAAECggIBgAAAA==.Hallacar:BAAALAADCgcIBwABLAADCggIIwABAAAAAA==.Hammerfaust:BAAALAAECgYIDAAAAA==.Hanali:BAABLAAECoEmAAICAAgIpRzQDwCWAgACAAgIpRzQDwCWAgAAAA==.Hargrim:BAAALAAECgQICAAAAA==.Hastati:BAABLAAECoEVAAIeAAYIPw5tFgBXAQAeAAYIPw5tFgBXAQAAAA==.',He='Held:BAAALAAECgQIDAAAAA==.Helvira:BAAALAAECgYIDAAAAA==.Hermadiaelys:BAAALAAECgUIDQAAAA==.',Ho='Honny:BAAALAADCgcIDAABLAAECggIHwAFANMUAA==.Hornschi:BAAALAAECgIIAQAAAA==.',Hu='Hukdok:BAABLAAECoEmAAMPAAgIXRK9NwD+AQAPAAgIXRK9NwD+AQAOAAYIMRBhjgAoAQAAAA==.Hunterfire:BAAALAAECgIIAgAAAA==.',Hy='Hylax:BAAALAAECgYICQAAAA==.',['Hê']='Hêcate:BAAALAAECgYIDgAAAA==.',['Hø']='Høpè:BAABLAAECoErAAIXAAgIAx/VGQBpAgAXAAgIAx/VGQBpAgAAAA==.',Ic='Icewhisper:BAAALAAECgYIBgAAAA==.Icyvenom:BAABLAAECoEcAAITAAcIXhlRKQC7AQATAAcIXhlRKQC7AQAAAA==.',Id='Ideala:BAAALAAECgQIBQAAAA==.Idoras:BAAALAADCggICAAAAA==.',Ik='Iktome:BAAALAADCggICAAAAA==.Iktôme:BAAALAAECgcICgAAAA==.',Il='Illidoo:BAABLAAECoEmAAMbAAgIfyRhAwAyAwAbAAgITSRhAwAyAwASAAYIVh3WVwDzAQAAAA==.',Im='Immôrtality:BAAALAAECggICAAAAA==.',In='Ingrimmosch:BAABLAAECoEZAAIMAAcIix+UQABPAgAMAAcIix+UQABPAgAAAA==.',Ir='Iras:BAAALAAECggICwAAAA==.Irujam:BAABLAAECoEXAAMJAAcIXQwZLwBcAQAJAAcIXQwZLwBcAQAfAAUIJg3HMQDhAAAAAA==.',Is='Iseig:BAABLAAECoEoAAMZAAcIoA33qAB6AQAZAAcILwz3qAB6AQAYAAQIcA+1NQAAAQAAAA==.',Ja='Jajoma:BAAALAAECgQIBwAAAA==.',Je='Jelani:BAAALAAECgYIBgABLAAECggIJAAYAKQYAA==.',Jh='Jhakazar:BAAALAADCgcIBwAAAA==.',Jo='Johnmandrake:BAAALAAECgIIBAAAAA==.Jonkob:BAACLAAFFIEZAAMZAAYIQCUHAQCbAgAZAAYIQCUHAQCbAgAYAAMI9B44AwAtAQAsAAQKgSIAAxkACAjyJkQEAGkDABkACAjoJkQEAGkDABgAAgjoJok5AOAAAAAA.',Ju='Juljia:BAAALAAECgYICQABLAAFFAMICQAPAAgWAA==.',['Jè']='Jèssí:BAABLAAECoEoAAIDAAgIJAohHwBPAQADAAgIJAohHwBPAQAAAA==.',['Jó']='Jódi:BAAALAAECgQICAAAAA==.',Ka='Kadlin:BAABLAAECoEoAAILAAgIZCF9FwDYAgALAAgIZCF9FwDYAgAAAA==.Kaduc:BAAALAAECgYICgAAAA==.Kalidia:BAAALAAECgEIAQAAAA==.Kaluur:BAAALAAECggIDgAAAA==.Kantholz:BAAALAAECggIEwAAAA==.Kardowén:BAAALAAECgIIAwAAAA==.Karuuzo:BAAALAADCggICgABLAAFFAMICwASALUiAA==.Katabasis:BAEALAAECgYIDQABLAAECggIJgAaAMIYAA==.Kawa:BAAALAAECgcIDgAAAA==.Kaz:BAAALAAECgMIAwABLAAFFAYIDgAVAH4aAA==.',Ke='Keebala:BAAALAAECggICAAAAA==.Kehléthor:BAACLAAFFIEGAAMZAAIIvgcjXgB6AAAZAAIIBwQjXgB6AAAYAAEIbw3UGABPAAAsAAQKgR4AAxgACAj+EjweALEBABkACAiIDK2CAL0BABgABwhNEzweALEBAAAA.Keio:BAABLAAECoEYAAINAAYISgwCegBQAQANAAYISgwCegBQAQAAAA==.Kelos:BAAALAAECggIAQABLAAECggIEQABAAAAAA==.Keltran:BAAALAAECgYIDAAAAA==.Kesiray:BAAALAAECgEIAQAAAA==.Keynani:BAABLAAECoE9AAIgAAgIvCJSCQAQAwAgAAgIvCJSCQAQAwAAAA==.',Kh='Khazragore:BAABLAAECoEXAAMOAAgIZBRETgDKAQAOAAgIZBRETgDKAQAPAAEI3BLXqAA9AAAAAA==.',Ki='Kitanidas:BAAALAAECgYIEgAAAA==.Kitty:BAAALAAECggICAAAAA==.',Ko='Konso:BAABLAAECoEfAAMYAAcI+w75HgCrAQAYAAcIxw75HgCrAQADAAYIygehKQDnAAAAAA==.Koralie:BAABLAAECoEmAAMhAAgIuyF7AQALAwAhAAgIuyF7AQALAwAgAAMIZAXRkgB1AAAAAA==.Korudash:BAAALAADCgQIBAAAAA==.',Kr='Krafter:BAAALAAECgYIEQAAAA==.Krauser:BAAALAADCgcICwAAAA==.Kreolia:BAAALAADCggIBAAAAA==.Kriegsritter:BAAALAADCgYICQAAAA==.Krolok:BAABLAAECoEZAAIEAAcINBYkHgDvAQAEAAcINBYkHgDvAQAAAA==.',['Kâ']='Kâshira:BAABLAAECoEUAAIaAAgIDgmPUQBLAQAaAAgIDgmPUQBLAQAAAA==.Kâzaam:BAAALAAECgcIDAAAAA==.',La='Laex:BAAALAADCgIIAgAAAA==.Lagolas:BAAALAAECgMIBwAAAA==.Larwain:BAAALAADCgYIBgABLAAECggIJgAHAGkSAA==.',Le='Leanox:BAAALAADCggICAAAAA==.Leanâ:BAAALAAECgYICgAAAA==.Lesarya:BAAALAAECggICAAAAA==.Leà:BAAALAADCggICAAAAA==.',Li='Libelle:BAAALAAECgQIBAAAAA==.Liesira:BAAALAADCgYIBgAAAA==.Lilas:BAAALAADCggIEQAAAA==.Limaro:BAABLAAECoEfAAIKAAgIQhjGIABBAgAKAAgIQhjGIABBAgAAAA==.Linari:BAAALAAECgQICAAAAA==.Lindragon:BAABLAAECoEfAAMcAAcIKh4BFgBfAgAcAAcIKh4BFgBfAgAiAAYIvgz9IQAaAQAAAA==.Lingshu:BAABLAAECoEVAAMTAAYIShv+IgDjAQATAAYIShv+IgDjAQAUAAEIjAzG3gA2AAAAAA==.Liubee:BAAALAAECggIEAAAAA==.Lizoka:BAAALAAECgQIBwAAAA==.Lizshuna:BAAALAADCgcIBwAAAA==.',Lo='Lonelý:BAABLAAECoEUAAMJAAcIjxrcFwAfAgAJAAcICRrcFwAfAgAjAAYIohNOHwBpAQAAAA==.Lorufinden:BAABLAAECoEoAAIFAAgIKxbpOwAcAgAFAAgIKxbpOwAcAgAAAA==.',Lu='Lucifert:BAAALAADCgEIAQAAAA==.Luli:BAAALAADCggIFQAAAA==.Luminos:BAABLAAECoEhAAILAAgIWhcbSwD+AQALAAgIWhcbSwD+AQAAAA==.Lunyá:BAAALAADCggICAAAAA==.Luáná:BAABLAAECoEaAAIXAAcItxKgNgCxAQAXAAcItxKgNgCxAQAAAA==.',Ly='Lyrilith:BAABLAAECoEdAAIgAAcIkRH/RgCUAQAgAAcIkRH/RgCUAQAAAA==.Lysterses:BAAALAAECggIAQAAAA==.',['Lî']='Lîu:BAAALAADCggICAABLAAECggIEAABAAAAAA==.',['Lò']='Lònély:BAAALAADCggICAAAAA==.',Ma='Magicguk:BAAALAADCgcIDQAAAA==.Magira:BAAALAADCgQIBAAAAA==.Magistrat:BAAALAADCgcIEQAAAA==.Magmatron:BAABLAAECoEjAAICAAgIahuFEwBsAgACAAgIahuFEwBsAgAAAA==.Maiiro:BAAALAADCgYIBgAAAA==.Mairo:BAAALAADCggIBwAAAA==.Malgor:BAAALAAECgQICAAAAA==.Malgorian:BAAALAAECgMIBQAAAA==.Malissp:BAABLAAECoEWAAISAAYIsRCpmQBlAQASAAYIsRCpmQBlAQAAAA==.Malura:BAABLAAECoEdAAQgAAcI3RMKTQB9AQAgAAcImhEKTQB9AQAhAAMIXBquGwDcAAAaAAMIGQkAAAAAAAAAAA==.Manta:BAABLAAECoEaAAIkAAgImRF6BQAWAgAkAAgImRF6BQAWAgAAAA==.Marolaz:BAAALAADCgcIBwAAAA==.Matrâs:BAAALAAECgYIBwAAAA==.Matteowo:BAABLAAECoEXAAIUAAgIJCaTBABiAwAUAAgIJCaTBABiAwAAAA==.Maureen:BAAALAAECgEIAQAAAA==.Mazorgrim:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.',Me='Mechratle:BAAALAADCggIDAAAAA==.Megares:BAABLAAECoEfAAIMAAcIPBouVwARAgAMAAcIPBouVwARAgAAAA==.Meliria:BAAALAAECggIEQAAAA==.Merakol:BAAALAADCgUIBQABLAAFFAMIDAAEAGceAA==.Merona:BAABLAAECoEiAAIfAAcIsg1SIwBZAQAfAAcIsg1SIwBZAQAAAA==.Mevi:BAAALAAECgYIBgAAAA==.',Mi='Michèle:BAAALAADCgQIBAAAAA==.Miela:BAAALAAECgQIBQAAAA==.Millinocket:BAAALAAECgYIDgAAAA==.Minuky:BAABLAAECoEaAAIMAAcIcSAwNAB6AgAMAAcIcSAwNAB6AgAAAA==.Minusa:BAAALAADCgYIBgAAAA==.Mirajane:BAAALAADCgcIBwAAAA==.Misschief:BAAALAADCggIGAAAAA==.Miyasu:BAAALAAECgYIDgAAAA==.',Mo='Mohora:BAAALAAECgYICwAAAA==.Monochrome:BAEALAADCggIGAABLAAECggIJgAaAMIYAA==.Morgenelf:BAAALAAECgYIBwABLAAECgYIDwABAAAAAA==.',Mu='Muxx:BAAALAADCgcIBgAAAA==.',My='Mycrew:BAAALAADCgIIAgAAAA==.Myracel:BAACLAAFFIEWAAIgAAUI6h4bBADbAQAgAAUI6h4bBADbAQAsAAQKgTEAAiAACAijHn4TALMCACAACAijHn4TALMCAAAA.',['Mâ']='Mâlory:BAAALAAECgYIEQAAAA==.',['Mæ']='Mæntorin:BAAALAADCggICAAAAA==.',['Mè']='Mèoéw:BAAALAAECggIEwABLAAECggIJAAZALoeAA==.',['Mé']='Méo:BAAALAADCggICAAAAA==.',['Mì']='Mìri:BAAALAAECgQICAAAAA==.',['Mö']='Möppi:BAAALAADCgYIBgABLAAECgYIFAAEAAcUAA==.',Na='Narathok:BAAALAADCggICAABLAAECgYIFAAEAAcUAA==.Naúrdin:BAAALAAECgQIDQAAAA==.',Ne='Neischi:BAAALAADCgcIBwAAAA==.Nerimee:BAAALAAFFAEIAgAAAA==.Nestario:BAABLAAECoEUAAMEAAYIBxR4LgCWAQAEAAYIBxR4LgCWAQAFAAEIoATN2wAzAAAAAA==.Netherflame:BAEALAAECggIDgABLAAECggIJgAaAMIYAA==.Neyjalon:BAAALAAECggICAAAAA==.',Ni='Niachha:BAAALAAECgMIBAAAAA==.Nidhoegg:BAAALAAECgUICQAAAA==.Nighti:BAAALAAECggICQAAAA==.Nightstalke:BAABLAAECoEgAAIMAAgIBiRtDwArAwAMAAgIBiRtDwArAwAAAA==.Nilathan:BAACLAAFFIEIAAITAAIIehr9CQCeAAATAAIIehr9CQCeAAAsAAQKgR4AAhMACAgNIvoHAP4CABMACAgNIvoHAP4CAAAA.Nioo:BAAALAAECgIIAgABLAAFFAMICwASALUiAA==.Nipani:BAACLAAFFIEGAAIfAAIINA4HDgCQAAAfAAIINA4HDgCQAAAsAAQKgSkAAh8ACAgIGSoQAEACAB8ACAgIGSoQAEACAAAA.Nirfuin:BAAALAAECggIEQAAAA==.Nissel:BAABLAAECoEWAAIaAAgIAhfIJwAeAgAaAAgIAhfIJwAeAgAAAA==.Niva:BAABLAAECoEbAAMZAAcI6CApNwByAgAZAAcI6CApNwByAgADAAYIIB8AAAAAAAAAAA==.',Nj='Njela:BAABLAAECoEZAAIKAAcIgxpJKgAOAgAKAAcIgxpJKgAOAgAAAA==.',No='Noellene:BAABLAAECoEgAAIRAAcIeyBIDQB9AgARAAcIeyBIDQB9AgAAAA==.Norcanor:BAAALAADCgUIBQAAAA==.Noric:BAABLAAECoEVAAMPAAYIohBvXQBvAQAPAAYIohBvXQBvAQAOAAIIkQQXCQE6AAAAAA==.Norrîn:BAAALAAECgYIEQAAAA==.Noxî:BAABLAAECoEdAAIXAAcIYA8sQQB/AQAXAAcIYA8sQQB/AQAAAA==.',['Nê']='Nêyláh:BAAALAAECgcIEwAAAA==.',['Nî']='Nîmue:BAAALAAECgUICQAAAA==.',['Nö']='Nörmellina:BAAALAAECgYICgAAAA==.',Ol='Olbai:BAAALAAFFAIIAgABLAAFFAMICwASALUiAA==.',Or='Oraradas:BAABLAAECoEgAAITAAcIlxL+KQC3AQATAAcIlxL+KQC3AQAAAA==.Orpelia:BAAALAAECgYIDAAAAA==.',Ov='Ovelia:BAABLAAFFIEIAAMIAAMIHCEQDQDAAAAIAAIIzSMQDQDAAAAlAAEIuhsfFABPAAABLAAFFAYIGQAZAEAlAA==.',Pa='Paladelgon:BAAALAAECgMIAwAAAA==.Pallar:BAAALAAECgIIBAAAAA==.Pandachi:BAAALAAECgMIAwAAAA==.',Pe='Peuresia:BAAALAADCgMIAwAAAA==.',Ph='Phaatom:BAAALAADCgYIBgAAAA==.Phayara:BAABLAAECoEkAAIZAAgIuh4ULQCXAgAZAAgIuh4ULQCXAgAAAA==.',Po='Pol:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.Polat:BAAALAADCggICAABLAAFFAIICgANAMEUAA==.',Pr='Priestdelgon:BAAALAAECgcIDQAAAA==.',['Pâ']='Pâtrice:BAAALAAECgYIEgAAAA==.',Qu='Quend:BAAALAAECgYIBgABLAAECgcIGQATAEsbAA==.Quentchen:BAACLAAFFIEIAAImAAMIwhvPAAAlAQAmAAMIwhvPAAAlAQAsAAQKgSAAAiYACAinIpIBAB8DACYACAinIpIBAB8DAAAA.',Ra='Raaen:BAAALAADCggICAAAAA==.Radojka:BAAALAADCggICgABLAAECgcIIwARAIgcAA==.Raellian:BAABLAAECoEiAAMgAAgIuBIGTACBAQAgAAgIuBIGTACBAQAaAAUI/BQaXAAaAQAAAA==.Ragnarôk:BAAALAAECggICAABLAAECggIEAABAAAAAA==.Rahdojka:BAAALAADCgQIBAABLAAECgcIIwARAIgcAA==.Ramondir:BAAALAAECggICAAAAA==.Rashira:BAAALAAECgUIBQABLAAECggIFAAaAA4JAA==.Raskji:BAABLAAECoEfAAIZAAcI0hJaigCvAQAZAAcI0hJaigCvAQAAAA==.',Re='Redstripe:BAAALAAECgcICgAAAA==.Reiki:BAAALAAECgYIEAAAAA==.',Rh='Rhiluna:BAAALAADCgcIBgAAAA==.',Ri='Ri:BAAALAAECgIIAgAAAA==.Riodaan:BAACLAAFFIEQAAIXAAUIah8nAwDpAQAXAAUIah8nAwDpAQAsAAQKgTUAAhcACAiVJjABAIUDABcACAiVJjABAIUDAAAA.',Ro='Roderia:BAAALAAECgYICgAAAA==.Ronara:BAABLAAECoEbAAMiAAcI0hISFgClAQAiAAcI0hISFgClAQAcAAQIABWLQgAIAQAAAA==.Rouul:BAABLAAECoEXAAIWAAcIGSHyBgCGAgAWAAcIGSHyBgCGAgAAAA==.',Ru='Rucari:BAACLAAFFIEGAAIcAAIIJQmSFgCHAAAcAAIIJQmSFgCHAAAsAAQKgR8AAycACAh6EYYIAMEBABwACAihEFYiAOkBACcACAhqDYYIAMEBAAAA.Rudig:BAAALAADCgcIBwAAAA==.Rudix:BAAALAADCgMIBAAAAA==.',Ry='Rylax:BAAALAAECgYICgAAAA==.',['Rø']='Rølvoddoskar:BAAALAAECgQIBQAAAA==.',Sa='Sabian:BAABLAAFFIEIAAMIAAIIfxmREACqAAAIAAIIfxmREACqAAAlAAEIWACrGQAnAAABLAAFFAMICwASALUiAA==.Sakuriel:BAAALAAECgUICQAAAA==.Salvira:BAAALAAECgQIBQABLAAECgQIBQABAAAAAA==.Samulay:BAAALAADCggICAAAAA==.Samáèl:BAAALAADCgEIAQAAAA==.Sanii:BAAALAAECgYICAAAAA==.Sarada:BAAALAADCggIDQAAAA==.Savinia:BAAALAAECggIDwAAAA==.Sayu:BAAALAAECgYIDwAAAA==.',Sc='Schanice:BAAALAAECggICAAAAA==.Schneestaub:BAAALAAECgMIBAAAAA==.Scyllua:BAABLAAECoEaAAIPAAgI6Q8lTgCjAQAPAAgI6Q8lTgCjAQABLAAECggIHwAFANMUAA==.',Se='Seb:BAAALAAECgYIEgAAAA==.Seeknd:BAAALAADCggICAAAAA==.Sehnetor:BAAALAAECgUIBwAAAA==.Selarion:BAAALAAECgIIAgABLAAECgcIEgABAAAAAA==.Sengaja:BAABLAAECoEgAAMLAAcI4QpUogA7AQALAAcI4QpUogA7AQAVAAIIngMcrQAzAAAAAA==.Serelia:BAAALAAECgMIBgAAAA==.',Sh='Shadowbladé:BAAALAADCgMIAwAAAA==.Shaebear:BAAALAADCggICAAAAA==.Shanaya:BAAALAAECgQIBAAAAA==.Sharandala:BAABLAAECoEdAAMHAAcI/A75GwCTAQAHAAcI/A75GwCTAQAXAAIIoATblAAoAAAAAA==.Shindori:BAAALAADCggICQAAAA==.Shisai:BAACLAAFFIELAAIgAAUIYA8fBwCJAQAgAAUIYA8fBwCJAQAsAAQKgTcAAyAACAiwH1gZAIkCACAACAiwH1gZAIkCABoACAiqDrUzANkBAAAA.Shneezn:BAABLAAECoEYAAIZAAcIqxJIiQCwAQAZAAcIqxJIiQCwAQABLAAFFAMIDAAEAGceAA==.Shylvana:BAACLAAFFIEGAAINAAIIaCKVFADNAAANAAIIaCKVFADNAAAsAAQKgSsAAw0ACAjoIRQPABcDAA0ACAi2IRQPABcDAB4ABAhUGBEaACcBAAAA.Shálly:BAAALAADCggIDAAAAA==.Shérly:BAABLAAECoEUAAIRAAcI1xH1LABeAQARAAcI1xH1LABeAQAAAA==.Shíney:BAAALAADCggIEAABLAAECggIFAARANcRAA==.Shôdân:BAAALAADCggIEAAAAA==.',Si='Sibrand:BAAALAAECggIEAABLAAECggIEQABAAAAAA==.Sii:BAAALAAECgMIAwAAAA==.Sinesterá:BAAALAAECgYIDgAAAA==.',Sn='Snowflake:BAAALAADCgYIBgAAAA==.Snuppil:BAAALAAECgEIAQAAAA==.',So='Solius:BAABLAAECoEjAAMRAAcIiBykGQD1AQARAAcIiBykGQD1AQAMAAEIsg6mNwFAAAAAAA==.Sonkor:BAACLAAFFIEJAAICAAIICxbnEQCMAAACAAIICxbnEQCMAAAsAAQKgRoAAgIACAj4EUIqALUBAAIACAj4EUIqALUBAAAA.Sonèa:BAAALAAECgIIBAAAAA==.Sophar:BAABLAAECoEmAAIIAAgIdxPAHAAeAgAIAAgIdxPAHAAeAgAAAA==.',Sp='Spätelf:BAAALAAECgYIDwAAAA==.',Sr='Sry:BAAALAAECgYIBwAAAA==.',St='Staggerop:BAAALAAECgYIBgAAAA==.',Su='Sucari:BAAALAAECgYICQAAAA==.Sugosch:BAAALAAECgMIBQABLAAECgYIFAAEAAcUAA==.Summergalé:BAABLAAFFIEKAAIaAAIIfBe7FACdAAAaAAIIfBe7FACdAAAAAA==.Sunless:BAAALAAECgYIEQAAAA==.',Sy='Sylva:BAAALAADCggIIwAAAA==.',['Sà']='Sàphira:BAAALAAECgIIAgAAAA==.',['Sá']='Sáhirá:BAAALAAECgYIEAAAAA==.Sávánt:BAAALAADCgUIBQAAAA==.',['Sî']='Sîana:BAABLAAECoEfAAIKAAgIeR8nDQDTAgAKAAgIeR8nDQDTAgAAAA==.',Ta='Tabuu:BAAALAADCgYICAAAAA==.Tabøø:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Takkar:BAAALAAECggIDwABLAAECggIEQABAAAAAA==.Talanjó:BAAALAAECgYIEAAAAA==.Talijah:BAAALAADCgIIAgAAAA==.Talitha:BAAALAAECgMIAQAAAA==.Tanshiro:BAABLAAECoEeAAILAAgINh4SJgCHAgALAAgINh4SJgCHAgAAAA==.Tapsino:BAAALAAECgIIAwAAAA==.Tareth:BAAALAAECgIIAgAAAA==.Tarexigos:BAAALAAECgYIDgAAAA==.Tatus:BAAALAADCgYIAwAAAA==.Taylara:BAAALAADCgYIBgAAAA==.',Te='Tellron:BAABLAAECoEfAAIFAAgI0xQtOAAsAgAFAAgI0xQtOAAsAgAAAA==.Tenchy:BAAALAAECggIBgAAAA==.Terrassador:BAAALAAECgYIBgAAAA==.Tessiâ:BAAALAAECgYIDAAAAA==.',Th='Thabita:BAAALAADCgMIAwAAAA==.Thaddeus:BAABLAAECoErAAIRAAgIFhzPDgBpAgARAAgIFhzPDgBpAgAAAA==.Thalyana:BAABLAAECoEaAAIgAAcIIwZ1ZQAmAQAgAAcIIwZ1ZQAmAQAAAA==.Thanae:BAAALAAECgYIEQAAAA==.Thasor:BAAALAADCggIEgAAAA==.Thorgran:BAAALAAECgcIBQAAAA==.Thormorath:BAAALAAECgYICwAAAA==.',Ti='Tibs:BAAALAAECgYIEwAAAA==.Tieker:BAABLAAECoEWAAIMAAgIjhSnZQDvAQAMAAgIjhSnZQDvAQABLAAECggIIQALALgcAA==.Tilasha:BAABLAAECoEbAAIEAAcIhgotPABaAQAEAAcIhgotPABaAQAAAA==.Tinduith:BAAALAADCgcIEwAAAA==.',To='Todesente:BAABLAAECoEaAAIYAAcIpgoMIwCLAQAYAAcIpgoMIwCLAQAAAA==.Todoo:BAAALAADCgYIBgABLAAECggIJgAbAH8kAA==.Todormu:BAAALAADCgYIBgAAAA==.Toron:BAAALAAECgYIDAAAAA==.Torque:BAAALAAECgYIDAAAAA==.',Tr='Trias:BAAALAAECgEIAQAAAA==.',Tu='Turmbauer:BAAALAAECgYICQAAAA==.',['Tî']='Tîara:BAABLAAECoEYAAIKAAcIAxLyUQBkAQAKAAcIAxLyUQBkAQAAAA==.',['Tó']='Tór:BAAALAAECgYICwAAAA==.',Uc='Ucci:BAAALAAECgIIAQAAAA==.',Uk='Ukkosa:BAABLAAECoEZAAISAAcIwiBGLwB6AgASAAcIwiBGLwB6AgAAAA==.',Ul='Ulaxia:BAAALAAECggICAAAAA==.',Um='Umath:BAAALAADCggIIwAAAA==.',Ur='Urolke:BAAALAAECgYIEQABLAAECgcIGQATAEsbAA==.',Va='Valagard:BAAALAADCggIFgAAAA==.Valishko:BAAALAAECgYIBgAAAA==.Valâr:BAAALAADCgcICQABLAAECgYIEgABAAAAAA==.Vantarias:BAAALAAECgEIAQAAAA==.Vareel:BAAALAAFFAEIAQABLAAFFAIIBgANAGgiAA==.',Ve='Vearis:BAAALAADCgQIBAAAAA==.Velgorn:BAAALAAECgYIEgAAAA==.Vette:BAAALAAECggIAgAAAA==.',Vi='Vidarr:BAAALAADCgIIAgAAAA==.Viridan:BAAALAAECgQIDAAAAA==.',Vo='Vortexis:BAAALAAECggICAAAAA==.',['Vê']='Vênture:BAABLAAECoEbAAIaAAgIfSMrEADdAgAaAAgIfSMrEADdAgABLAAFFAYIGQAZAEAlAA==.',Wa='Walkingbeef:BAAALAAECgYIEQAAAA==.Wanaka:BAABLAAECoEbAAIVAAYIlAmpbAD6AAAVAAYIlAmpbAD6AAAAAA==.',Wi='Wildoger:BAAALAADCggIDwAAAA==.',Wo='Wolke:BAACLAAFFIEGAAIKAAII5CGUEADHAAAKAAII5CGUEADHAAAsAAQKgSEAAgoACAj7HZwSAKQCAAoACAj7HZwSAKQCAAAA.',Xa='Xacxa:BAAALAADCgUIAwAAAA==.Xanthippe:BAAALAADCggIFAAAAA==.Xastra:BAABLAAECoEmAAIRAAgIJiUyAgBeAwARAAgIJiUyAgBeAwAAAA==.Xaxi:BAAALAADCgEIAQAAAA==.',Xe='Xelestine:BAAALAADCgcIBwAAAA==.Xeliera:BAAALAAECgcIEgAAAA==.Xentras:BAAALAAECgYIEQAAAA==.',Xi='Xindria:BAAALAAECgYICQAAAA==.',Ya='Yacusa:BAABLAAECoEnAAIMAAgI0RRiUgAdAgAMAAgI0RRiUgAdAgAAAA==.Yamato:BAABLAAECoEfAAIcAAcI+g0TMACEAQAcAAcI+g0TMACEAQAAAA==.Yangzingthao:BAABLAAECoEdAAMjAAcIjBlNFQDiAQAjAAcIjBlNFQDiAQAJAAMIdQizSwCDAAAAAA==.',Ye='Yenali:BAAALAAECgEIAgAAAA==.',Yo='Yo:BAAALAAECgYIBwABLAAECggICgABAAAAAA==.Yodok:BAABLAAECoEVAAMKAAcI3xFfRwCLAQAKAAcI3xFfRwCLAQAXAAEIOQBvnwABAAAAAA==.Youmu:BAAALAAECgYIEQAAAA==.',Yu='Yubaka:BAAALAADCggIIAAAAA==.Yuu:BAAALAADCggICAABLAAFFAIIBgAfADQOAA==.Yuukì:BAABLAAECoEhAAIRAAgI9yFwBwDnAgARAAgI9yFwBwDnAgABLAAFFAIIBgAfADQOAA==.',Za='Zaara:BAABLAAECoEYAAIPAAYI/gaqfAD9AAAPAAYI/gaqfAD9AAAAAA==.Zabier:BAAALAADCgEIAQAAAA==.Zamga:BAAALAAECgYIDAAAAA==.Zanzibar:BAAALAAECgIIAgAAAA==.Zati:BAAALAAECgYIBgAAAA==.Zaubernixx:BAAALAAECgMIBwAAAA==.',Ze='Zerfall:BAAALAAECgYIEAAAAA==.Zeriza:BAAALAAECgYIEgAAAA==.Zeronikor:BAABLAAECoEgAAISAAcInQxdjAB/AQASAAcInQxdjAB/AQAAAA==.Zerrox:BAAALAADCgUIBgAAAA==.',Zi='Zimti:BAAALAADCgYIBgAAAA==.',Zo='Zobrombie:BAABLAAECoEkAAIOAAgIjyUoAwBJAwAOAAgIjyUoAwBJAwAAAA==.Zojin:BAABLAAECoEYAAIaAAYIlh93JQAuAgAaAAYIlh93JQAuAgABLAAFFAMIDAAEAGceAA==.Zolgon:BAABLAAECoEfAAIPAAgI2BYJLAA6AgAPAAgI2BYJLAA6AgAAAA==.Zornschwinge:BAAALAAECggIDAAAAA==.Zoé:BAAALAAECgQIBQAAAA==.',Zu='Zulan:BAAALAAECgEIAQAAAA==.',Zw='Zweixvier:BAAALAADCgMIAwAAAA==.Zworkel:BAAALAADCggICAAAAA==.',Zy='Zyix:BAAALAAECgYIBgAAAA==.Zyliâne:BAAALAAECgYICwAAAA==.',['Án']='Ánkharesh:BAAALAAECgIIAgAAAA==.',['Áx']='Áxerisa:BAAALAAECggICAAAAA==.',['Âr']='Ârmun:BAAALAAECgEIAQAAAA==.',['Är']='Ärator:BAAALAAECgIIAwAAAA==.',['Æy']='Æyleen:BAAALAAECgMIAwAAAA==.',['Él']='Éllíe:BAAALAAECgYIDgAAAA==.',['Ím']='Ímpa:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end