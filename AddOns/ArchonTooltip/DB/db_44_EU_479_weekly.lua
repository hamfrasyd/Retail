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
 local lookup = {'Paladin-Retribution','Hunter-Marksmanship','Unknown-Unknown','Mage-Arcane','Mage-Frost','Evoker-Devastation','Warrior-Fury','Druid-Balance','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Enhancement','Shaman-Restoration','Rogue-Assassination','Druid-Guardian','Paladin-Holy','Shaman-Elemental','DemonHunter-Havoc','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Priest-Holy','Priest-Shadow','Paladin-Protection','Monk-Brewmaster','Warlock-Demonology','Monk-Mistweaver','Monk-Windwalker',}; local provider = {region='EU',realm='Zuluhed',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adina:BAAALAADCgcIBwAAAA==.',Ae='Aereôn:BAAALAAECgYICwAAAA==.',Ah='Ahvana:BAAALAADCgYIBwAAAA==.',Ai='Aita:BAAALAAECgMIAwAAAA==.',Aj='Ajani:BAABLAAECoEaAAIBAAcIXxv/SQA0AgABAAcIXxv/SQA0AgAAAA==.',Ak='Akatzuki:BAAALAAECggICAAAAA==.Akazan:BAABLAAECoEeAAICAAgIvRDITABpAQACAAgIvRDITABpAQAAAA==.Akses:BAAALAADCggIDwAAAA==.',Al='Alcará:BAAALAAECgIIAQABLAAECgIIAgADAAAAAA==.',An='Anaarai:BAAALAADCgUIBQAAAA==.Andrastê:BAAALAAECgYIBwAAAA==.Andrej:BAAALAAECgYIBgAAAA==.Annatara:BAAALAADCgcICwAAAA==.',Ar='Aranthul:BAAALAADCgcIBwAAAA==.Arkannia:BAABLAAECoEUAAMEAAcI6Qb2iwBLAQAEAAcI6Qb2iwBLAQAFAAIIegaWeQBCAAAAAA==.',As='Asusa:BAAALAAECgYIDAAAAA==.',At='Athenê:BAAALAAECgYIBgAAAA==.',Au='Auriel:BAAALAADCgcICAAAAA==.',Aw='Awôn:BAAALAAECgUICAAAAA==.',Ax='Axxero:BAAALAADCggIDwAAAA==.',Ay='Aydoabay:BAAALAADCgUICQAAAA==.',Ba='Balenciaga:BAAALAAECggICAAAAA==.Bambusbirne:BAAALAADCgMIAwAAAA==.Barosa:BAAALAADCgEIAQAAAA==.Barân:BAAALAAECgcIEAAAAA==.',Be='Benaro:BAAALAADCgYIBgABLAAFFAMIBQAGANIGAA==.',Bi='Biigdaddy:BAABLAAECoEXAAIHAAYIbRrzUwC9AQAHAAYIbRrzUwC9AQAAAA==.',Bl='Blackbewiju:BAABLAAECoEbAAMFAAcIPhfQLACnAQAFAAcIPhfQLACnAQAEAAMIVQQWzgBlAAAAAA==.Blutshock:BAAALAAECggIEAAAAA==.',Bu='Bubblebell:BAAALAADCggICAAAAA==.Buffalo:BAABLAAECoElAAMIAAcIZxqkIgAjAgAIAAcIZxqkIgAjAgAJAAMICwYmqwBXAAAAAA==.Buggy:BAAALAADCgcIBwAAAA==.Buttergolem:BAAALAAECggIEwAAAA==.',Ca='Caha:BAAALAAECgcIBwAAAA==.Calythra:BAAALAAECgEIAQAAAA==.Camorá:BAAALAAECgcIDgAAAA==.Cassia:BAAALAADCggIFwABLAAFFAIICAAJANUMAA==.',Ch='Chandrika:BAAALAAECgIIAgAAAA==.Chunky:BAAALAAECgYIBgABLAAECggIDgADAAAAAA==.',Cl='Claustrophob:BAAALAADCgcIBwAAAA==.',Co='Colin:BAAALAADCgUIBQAAAA==.Conarconarik:BAAALAAECgUIDAAAAA==.',Cr='Cranox:BAAALAADCgYIDgAAAA==.Cremolis:BAAALAAECgMIAwAAAA==.Crockdu:BAAALAAECggICAAAAA==.Crocker:BAAALAAECggICAABLAAECggIFAAKAEMVAA==.',Cx='Cxde:BAAALAADCgQIBAAAAA==.',Cy='Cyler:BAAALAADCggICAAAAA==.',Da='Damaco:BAAALAADCgcIBwABLAAECgcIHgABAFYYAA==.Danix:BAAALAADCggICQABLAAECggIEwADAAAAAA==.Darkshi:BAAALAAECggIBgAAAA==.',De='Deekah:BAAALAADCggICgAAAA==.Demondog:BAAALAADCgcIBwAAAA==.',Di='Dinkelbörg:BAABLAAECoEUAAIKAAgIQxX1EwDaAQAKAAgIQxX1EwDaAQAAAA==.',Do='Docproof:BAABLAAECoEkAAIBAAgIcBVQVgATAgABAAgIcBVQVgATAgAAAA==.Dotzie:BAAALAAECgcICgAAAA==.',Dr='Dracona:BAACLAAFFIEEAAILAAIIViSSHQDTAAALAAIIViSSHQDTAAAsAAQKgSgAAgsACAgvJlwDAHEDAAsACAgvJlwDAHEDAAAA.Drakoná:BAAALAAECgUIBwAAAA==.Drbizzare:BAABLAAECoEeAAIBAAcIVhi4YQD4AQABAAcIVhi4YQD4AQAAAA==.Dregin:BAABLAAECoEeAAIMAAcI/BlSZgC3AQAMAAcI/BlSZgC3AQAAAA==.',Du='Dumbum:BAAALAADCggICAAAAA==.Durbe:BAAALAAECgMIAwAAAA==.',['Dú']='Dúdúýá:BAAALAADCgcIGgAAAA==.',['Dû']='Dûrendâl:BAABLAAECoEZAAIBAAcIARaRbwDaAQABAAcIARaRbwDaAQAAAA==.',Eg='Egrim:BAABLAAECoEjAAMNAAcI+yHJBgCLAgANAAcI+yHJBgCLAgAOAAEI3AEAAAAAAAAAAA==.',El='Eleitron:BAAALAADCgcIEQAAAA==.Elytron:BAAALAAECgYIDQAAAA==.',En='Enkidû:BAAALAAECggICwAAAA==.',Er='Erecá:BAAALAADCgcIBwAAAA==.Erl:BAAALAADCgQIBAAAAA==.Erîk:BAAALAAECgYIBwAAAA==.',Es='Escala:BAAALAADCggICAAAAA==.',Et='Etegosch:BAABLAAECoEXAAIPAAcIWAn0NAB9AQAPAAcIWAn0NAB9AQAAAA==.',Eu='Eulenklause:BAAALAAECgYIBgAAAA==.',Fe='Feelgood:BAAALAAECgIIAgAAAA==.Fehú:BAAALAADCggICAAAAA==.',Fl='Flyer:BAAALAADCggICAAAAA==.',Fo='Foop:BAAALAAECgcIBQABLAAECggIFAAKAEMVAA==.Foyan:BAAALAADCgYICAAAAA==.',Fr='Freezey:BAABLAAECoEYAAILAAgIzQfL1AAyAQALAAgIzQfL1AAyAQAAAA==.Freydis:BAAALAAECgYICgAAAA==.Froline:BAAALAAECgMIBgAAAA==.Frozina:BAAALAADCgYIBgAAAA==.',Fy='Fyè:BAABLAAECoElAAIQAAcIER+EBwBOAgAQAAcIER+EBwBOAgAAAA==.',['Fé']='Féhù:BAAALAAECggIDgAAAA==.',Ge='Gerlinde:BAAALAADCggICAAAAA==.',Gi='Gimlon:BAAALAADCgMIAwAAAA==.',Gl='Glubtrox:BAAALAADCggICAAAAA==.',Go='Goreon:BAAALAADCgYIBgABLAAECgYICwADAAAAAA==.Gork:BAAALAADCgEIAQAAAA==.Goryas:BAAALAAECgYIBgABLAAFFAYIDgACAH4aAA==.Gottespatron:BAABLAAECoEZAAIIAAcICB4hIAA1AgAIAAcICB4hIAA1AgAAAA==.Gottloser:BAAALAADCgcIFQAAAA==.',Gr='Graverobber:BAAALAAECgYIEAAAAA==.Greenárrow:BAABLAAECoEdAAICAAgI6ReeIwA3AgACAAgI6ReeIwA3AgAAAA==.Grimmzul:BAAALAADCggICAAAAA==.Grona:BAAALAAECgYICgAAAA==.Gròot:BAAALAADCgYICwAAAA==.Grünerteufel:BAAALAADCgIIAgAAAA==.',Gu='Guts:BAAALAAECgYIDAAAAA==.',['Gö']='Göttliche:BAAALAADCggICwAAAA==.Göttlicher:BAAALAADCgMIAgAAAA==.',Ha='Hackse:BAABLAAECoEZAAMBAAcIoB9APQBZAgABAAYIBSNAPQBZAgARAAQI8g0MTQDaAAABLAAECgYIGAASAG0fAA==.Haiwee:BAAALAAECgYICAAAAA==.Harlecann:BAAALAAECgYIDwAAAA==.Haxxe:BAAALAADCgYIBgABLAAECgYIGAASAG0fAA==.Haxxen:BAABLAAECoEYAAQSAAYIbR9KMAAiAgASAAYIbR9KMAAiAgANAAEIhhZtIwBDAAAOAAEIbhL9CwE1AAAAAA==.Haxxenone:BAAALAAECgYIEgABLAAECgYIGAASAG0fAA==.Haxxn:BAACLAAFFIEFAAIEAAIILB8BIwC9AAAEAAIILB8BIwC9AAAsAAQKgSkAAgQACAiPIusNACADAAQACAiPIusNACADAAEsAAQKBggYABIAbR8A.',He='Heißenberg:BAAALAAECgYIBgAAAA==.Henja:BAAALAAECgMIBgAAAA==.Herbie:BAABLAAECoEfAAIIAAgIdBSYKwDsAQAIAAgIdBSYKwDsAQAAAA==.Herrmanndo:BAAALAADCgQIBAAAAA==.',Hi='Hirschku:BAAALAAECgIIAgAAAA==.',Hu='Huntil:BAAALAADCgcIEAAAAA==.',Hy='Hyroz:BAAALAADCgcIDQAAAA==.',['Hê']='Hêalomat:BAAALAADCggICAAAAA==.',Id='Idra:BAAALAAECgIIAgAAAA==.',Im='Imi:BAAALAAECggICAAAAA==.',Io='Iosirenia:BAAALAAECgMIAwAAAA==.',Iv='Ivarr:BAAALAAECgYIBgAAAA==.',Jb='Jbanez:BAAALAAECgIIAgAAAA==.',Ji='Jimmer:BAAALAADCgYIBgAAAA==.',Jo='Jorwa:BAAALAAECgIIAwABLAAECgYICwADAAAAAA==.',Ju='Jurâ:BAAALAAECgcIDAAAAA==.Jutter:BAAALAADCgIIAgAAAA==.',['Jí']='Jínx:BAAALAAECgIIAwAAAA==.',['Jø']='Jøker:BAABLAAECoEkAAITAAgIBRnGQgAxAgATAAgIBRnGQgAxAgAAAA==.',Ka='Kaldini:BAAALAAECggIBwAAAA==.',Ke='Kelith:BAABLAAECoEeAAIBAAcIPRyxSAA3AgABAAcIPRyxSAA3AgAAAA==.Keyll:BAAALAADCggICAAAAA==.',Kh='Khaosdruid:BAAALAADCgcIBwAAAA==.Khara:BAAALAAECgUIAwAAAA==.Khmerta:BAAALAAECgIIAgAAAA==.Khäosdemon:BAABLAAECoEXAAMUAAcIuxRjTADbAQAUAAcIuxRjTADbAQAVAAQIggyhHgDbAAAAAA==.',Ki='Kiltura:BAAALAAECgYIDwAAAA==.',Kj='Kjartan:BAAALAAECgYIEwAAAA==.',Kn='Knut:BAABLAAECoEXAAIOAAcIFBB1fgBLAQAOAAcIFBB1fgBLAQAAAA==.',Ko='Kombât:BAAALAADCggICAAAAA==.Kosh:BAAALAAECgYICgAAAA==.',['Kí']='Kírá:BAAALAAECggICgABLAAECggIEwADAAAAAA==.',['Kö']='Köpek:BAAALAADCggICAAAAA==.',La='Laredo:BAAALAAECgcICQAAAA==.',Le='Leetmachine:BAAALAAECgYIDgAAAA==.Lethalie:BAAALAAECgIIAgAAAA==.',Li='Liandris:BAAALAADCggICAAAAA==.Lillalol:BAAALAAECgYIBgAAAA==.Lillà:BAABLAAECoEnAAQWAAgI7RlfCQDuAQAXAAgItxUkMAAAAgAWAAgIUxNfCQDuAQAYAAUIcxG4VgA0AQAAAA==.Lilyboa:BAAALAADCgcIBwAAAA==.Littelperson:BAAALAAECgQIBAAAAA==.',Lo='Lokahn:BAAALAAECgcIEwAAAA==.',Lu='Luthyâ:BAAALAAECgYIBgAAAA==.Luy:BAAALAAECgUIBwAAAA==.',Ly='Lyandria:BAAALAADCggICAAAAA==.',['Lá']='Láw:BAAALAAECgMIBgAAAA==.',Ma='Magann:BAAALAAECgYIBgAAAA==.Malteschrek:BAABLAAECoEgAAIZAAYIKg9KNgAgAQAZAAYIKg9KNgAgAQAAAA==.Malve:BAAALAAECgEIAgAAAA==.Mario:BAABLAAECoEeAAIUAAgI9hv8MABNAgAUAAgI9hv8MABNAgAAAA==.Martosch:BAAALAAECgYIDAAAAA==.Marukh:BAAALAADCggICAAAAA==.Matrixprocs:BAAALAADCgYIBwABLAAECgMIAwADAAAAAA==.Mayesty:BAAALAAECgUIBQAAAA==.Mayutami:BAAALAADCggICQABLAAECgMIAwADAAAAAA==.',Mc='Mc:BAAALAAECgcIDQAAAA==.Mcfrostshock:BAAALAADCgYIBgAAAA==.Mcschleck:BAAALAADCggICAAAAA==.',Me='Menthuras:BAABLAAECoEeAAIaAAcI+xBIHgB1AQAaAAcI+xBIHgB1AQAAAA==.Merivara:BAABLAAECoEVAAIFAAgIQCTkBAA1AwAFAAgIQCTkBAA1AwAAAA==.',Mi='Miarr:BAABLAAECoEYAAIHAAgItALjrQCgAAAHAAgItALjrQCgAAAAAA==.',Mo='Moegraine:BAAALAAECggIDAAAAA==.Morbinus:BAAALAADCggICAAAAA==.Morgâná:BAAALAAECgYICAAAAA==.Mortaschna:BAAALAAECggIDQAAAA==.',['Mô']='Môrtalis:BAACLAAFFIESAAMUAAYIHh3ZCwC0AQAUAAYIHh3ZCwC0AQAbAAIIEQv4EwCSAAAsAAQKgS0ABBQACAj+I2QKADcDABQACAjuI2QKADcDABUABwheGaYGAEsCABsABQhHHFwvAJEBAAAA.',Na='Nahhay:BAABLAAECoEeAAIZAAcIFAvKMgA2AQAZAAcIFAvKMgA2AQAAAA==.Naimi:BAABLAAECoEkAAIMAAgI3SX0AwBjAwAMAAgI3SX0AwBjAwAAAA==.',Ne='Nelkuk:BAAALAADCgcIFAAAAA==.Nelliary:BAAALAAECgIIAgAAAA==.Nervews:BAAALAADCggIDwAAAA==.Neré:BAABLAAECoEWAAMJAAcI2BWIOQDEAQAJAAcI2BWIOQDEAQAIAAEISgJVlgAlAAAAAA==.Newtster:BAAALAAFFAIIAgAAAA==.Neytiri:BAABLAAECoEWAAIIAAgI/A/YMADOAQAIAAgI/A/YMADOAQAAAA==.',Ni='Niara:BAAALAADCgYIBgAAAA==.Niarus:BAAALAADCgYIBgAAAA==.Niffty:BAABLAAECoEjAAMcAAgI8BYsEgAkAgAcAAgI8BYsEgAkAgAdAAYIZQsZNgAuAQAAAA==.Nilana:BAAALAAECgYIDAAAAA==.Ninjantiz:BAAALAAECgYIBwAAAA==.',No='Nodemon:BAAALAADCgcIBwABLAADCgcIBwADAAAAAA==.Noobkin:BAABLAAECoEWAAIIAAgIaSJlCQAVAwAIAAgIaSJlCQAVAwABLAAFFAIIAgADAAAAAA==.Noxxius:BAAALAADCgMIAwAAAA==.',Ny='Nyxilon:BAAALAAECggICAAAAA==.',Ob='Obsia:BAAALAAECggIDAAAAA==.',Oc='Ochunga:BAAALAADCggICAAAAA==.',On='Onecube:BAABLAAECoEWAAIIAAgIyxc3HwA8AgAIAAgIyxc3HwA8AgAAAA==.',Pa='Pabloone:BAAALAADCgcICAAAAA==.Palamanu:BAABLAAECoEiAAIBAAYIZyOCQQBNAgABAAYIZyOCQQBNAgAAAA==.',Pr='Proctus:BAAALAAECgYICwAAAA==.Profdrake:BAAALAAECgMIAwAAAA==.',Pu='Puronimo:BAABLAAECoEUAAIYAAYIqxEmRgB9AQAYAAYIqxEmRgB9AQAAAA==.',['Pà']='Pàndôra:BAABLAAECoEdAAIXAAcI6QmCWwBHAQAXAAcI6QmCWwBHAQAAAA==.',Ql='Ql:BAAALAAFFAIIBgABLAAFFAIICgACAG8mAQ==.',Ra='Raalia:BAAALAAECgQIBwAAAA==.Raskull:BAABLAAECoEaAAIMAAcIEh5MPAAuAgAMAAcIEh5MPAAuAgAAAA==.',Re='Recá:BAAALAADCgEIAQAAAA==.Regenbringer:BAAALAADCgcIBwAAAA==.Reih:BAAALAAECgcICAAAAA==.Relaxin:BAAALAAECgIIAgAAAA==.Reyven:BAAALAAECgcIBwABLAAECgcIHgAZABQLAA==.',Ro='Roadyhog:BAAALAAECgEIAQABLAAECgIIAgADAAAAAA==.',Ru='Run:BAAALAADCgcIBwAAAA==.Runeia:BAABLAAECoEfAAILAAcIbxcQdQDXAQALAAcIbxcQdQDXAQAAAA==.',Sa='Samsemilia:BAAALAAECggIDQAAAA==.Sansnom:BAAALAADCggIEAABLAAECggIDgADAAAAAA==.Satura:BAAALAAECgcIDgABLAAFFAIICAAJANUMAA==.',Sc='Schrumpél:BAAALAAECgYIBwAAAA==.Scribe:BAAALAAECgIIAgAAAA==.',Se='Serâx:BAAALAADCgIIAgAAAA==.',Sh='Shuix:BAAALAAECgYICgABLAAECgYICwADAAAAAA==.',Si='Silverhexer:BAABLAAECoEbAAIUAAcI4wgbdQBjAQAUAAcI4wgbdQBjAQAAAA==.Siola:BAAALAAECgcIDgABLAAFFAIICAAJANUMAA==.Sivra:BAAALAADCgYICAAAAA==.',Sn='Snok:BAAALAAECgYIBgABLAADCgMIAwADAAAAAA==.Snokshaman:BAAALAADCgMIAwAAAA==.Snuky:BAAALAADCgUIBQABLAAECgcIHgABAFYYAA==.',So='Some:BAABLAAECoEfAAIOAAgITBiZPwD4AQAOAAgITBiZPwD4AQAAAA==.',Sq='Squalldudu:BAAALAADCggIDAAAAA==.Squisius:BAAALAAECgMIAwAAAA==.',Su='Suwltan:BAABLAAECoEZAAMIAAYIwRfANwCsAQAIAAYIwRfANwCsAQAJAAYIRQ6NYgAtAQAAAA==.',Sy='Synfonia:BAAALAAECgQIBAAAAA==.Syni:BAAALAADCgcIBwAAAA==.Syntexo:BAAALAADCgcIDAAAAA==.',['Sâ']='Sâmuel:BAAALAAECgUICgAAAA==.',Ta='Taron:BAAALAAECgcIBwAAAA==.',Te='Teufelsherd:BAAALAAECgYICAAAAA==.',Th='Theldas:BAAALAAECgYICwAAAA==.Themountain:BAACLAAFFIEGAAIBAAIIXBZPJwClAAABAAIIXBZPJwClAAAsAAQKgSMAAgEABwiJIQUxAIYCAAEABwiJIQUxAIYCAAAA.Thures:BAAALAAECgQIEAAAAA==.',Ti='Tigu:BAABLAAECoEXAAIHAAgIpg0fVwCzAQAHAAgIpg0fVwCzAQABLAAFFAMICQAIAOsUAA==.Tiramísu:BAAALAAECgYICgAAAA==.',To='Todeshaxxen:BAAALAAECgYIBgABLAAECgYIGAASAG0fAA==.',Tr='Trasil:BAAALAADCggICAAAAA==.Tríní:BAAALAAECgYIDwAAAA==.',Tu='Turner:BAAALAAECgcIEQABLAAECggIFAAKAEMVAA==.',Un='Unari:BAABLAAECoEUAAMYAAcIyBd1KwAIAgAYAAcIyBd1KwAIAgAXAAYIexVtSgCHAQAAAA==.Unbrained:BAABLAAECoEaAAICAAcIWBI0RACMAQACAAcIWBI0RACMAQAAAA==.',Va='Vaenz:BAAALAAECggIDgAAAA==.Valkyrion:BAAALAAECggICwAAAA==.Variana:BAAALAADCgIIAgAAAA==.',Ve='Veb:BAABLAAECoElAAIXAAcI6hvAKAAnAgAXAAcI6hvAKAAnAgAAAA==.Verrottling:BAAALAAECgcIEwAAAA==.',Vh='Vhallas:BAABLAAECoEWAAIFAAcI1BP8JgDJAQAFAAcI1BP8JgDJAQAAAA==.',Vi='Viebi:BAAALAAECgEIAQAAAA==.Visyna:BAAALAAECgIIBAAAAA==.Vithar:BAABLAAECoEUAAILAAYIHw7r0gA1AQALAAYIHw7r0gA1AQAAAA==.',Vl='Vlad:BAAALAAECgcIDgAAAA==.',Vo='Volki:BAAALAAECgYIBwAAAA==.',Vy='Vyrala:BAABLAAECoEVAAIYAAcIHA38RgB5AQAYAAcIHA38RgB5AQAAAA==.Vyrany:BAAALAADCgQIBAABLAAECgcIFQAYABwNAA==.',['Vá']='Váléríá:BAAALAAECgMIAwAAAA==.',Wi='Wildbreath:BAABLAAECoEqAAIGAAgIZSKMBQAsAwAGAAgIZSKMBQAsAwAAAA==.',Wo='Woodstar:BAAALAAECggIEwAAAA==.',Xa='Xaturas:BAAALAAECgYIBgAAAA==.',Xe='Xeek:BAAALAAECggICAAAAA==.',Xi='Xiou:BAAALAADCgEIAQAAAA==.',Yi='Yikesm:BAAALAADCgYIBgAAAA==.Yikess:BAABLAAECoEWAAISAAcIrRtvLAA4AgASAAcIrRtvLAA4AgAAAA==.',Za='Zackzack:BAAALAAECgYIBwAAAA==.Zampuijin:BAAALAAECgIIAgAAAA==.',Zu='Zuxlan:BAAALAAECggIEQAAAA==.',['Áu']='Áuraya:BAABLAAECoEkAAIRAAgIpBj4EwBIAgARAAgIpBj4EwBIAgAAAA==.',['Âm']='Âmanda:BAABLAAECoEUAAIOAAYIsxD5jAArAQAOAAYIsxD5jAArAQAAAA==.',['Æl']='Ælimós:BAAALAAECgYIBwAAAA==.',['Êl']='Êlyn:BAABLAAECoEdAAIUAAYITg1cfQBNAQAUAAYITg1cfQBNAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end