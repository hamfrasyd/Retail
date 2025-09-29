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
 local lookup = {'Monk-Mistweaver','Shaman-Restoration','Unknown-Unknown','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','DemonHunter-Havoc','Warrior-Fury','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','Warlock-Destruction','Monk-Windwalker','Priest-Holy','Priest-Discipline','Druid-Feral','Evoker-Devastation','Mage-Arcane','DemonHunter-Vengeance','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Druid-Balance','Rogue-Outlaw','Hunter-Survival','Warlock-Affliction','Mage-Fire','Mage-Frost','DeathKnight-Frost','Paladin-Holy','Priest-Shadow','Shaman-Elemental','Evoker-Augmentation','Monk-Brewmaster','Rogue-Assassination','Rogue-Subtlety','Shaman-Enhancement',}; local provider = {region='EU',realm='Ghostlands',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abeny:BAAALAADCgQIBAAAAA==.',Ac='Acabrew:BAABLAAECoEaAAIBAAgIthLlGgCpAQABAAgIthLlGgCpAQAAAA==.Achtung:BAAALAAECgQIBAAAAA==.',Ad='Adderalandy:BAAALAADCgUIBQAAAA==.',Ae='Aeuna:BAAALAAECgYICAAAAA==.',Ai='Aikomoon:BAAALAAECgMIAwAAAA==.Aiyale:BAAALAAECgMIAQAAAA==.',Al='Alakazoome:BAAALAAECgcICgAAAA==.Alucardv:BAAALAADCgYIBgAAAA==.',Am='Amabloodsong:BAAALAADCgcIBwAAAA==.Amanitta:BAABLAAECoEXAAICAAYI1giErQDdAAACAAYI1giErQDdAAAAAA==.',An='Anaxímander:BAAALAADCgYIEAAAAA==.Andarcy:BAAALAAECgIIAgABLAAECggICgADAAAAAA==.Andriu:BAAALAADCgcIBwAAAA==.Anexen:BAACLAAFFIEGAAIEAAMI0RsqJwCiAAAEAAMI0RsqJwCiAAAsAAQKgScAAwQACAiAJIsKAEYDAAQACAiAJIsKAEYDAAUABwgnFcYpAGgBAAAA.Angelolight:BAAALAADCggICAAAAA==.Ankou:BAAALAAFFAEIAQAAAA==.Antvi:BAAALAAECgIIAgAAAA==.',Ap='Apox:BAAALAAECgcIDQAAAA==.Apoxology:BAAALAAECgcIDAAAAA==.',Aq='Aquaeructo:BAAALAAECgYICwAAAA==.',Ar='Araghuul:BAAALAADCgYIBgAAAA==.Arguultal:BAAALAAECggICAAAAA==.Arinnaya:BAAALAAECgIIAwAAAA==.Arthory:BAABLAAECoEVAAIGAAcI2B9OCgCBAgAGAAcI2B9OCgCBAgAAAA==.',As='Ashee:BAAALAADCggICAAAAA==.Assultturkey:BAAALAADCgcIBwAAAA==.',At='Atlass:BAAALAADCggICwAAAA==.',Av='Available:BAABLAAECoEbAAIFAAcIax8dDQB4AgAFAAcIax8dDQB4AgAAAA==.',Ax='Axeedge:BAAALAAECgQICAAAAA==.',Az='Azkadelia:BAAALAAECgYICQAAAA==.Azraq:BAAALAADCggIFgAAAA==.Azyter:BAAALAADCgIIAgAAAA==.',Ba='Babynate:BAABLAAECoEUAAIHAAgIPhYaTAALAgAHAAgIPhYaTAALAgAAAA==.Badussy:BAAALAAECgYICwAAAA==.Baghdaddy:BAAALAAECgQIBAAAAA==.Ballbuster:BAAALAAECggIEwAAAA==.Bambueater:BAAALAAECgYICwABLAAECggICAADAAAAAA==.Barricade:BAAALAADCgcICwAAAA==.Bassie:BAAALAADCggIGQAAAA==.Battlebruh:BAAALAAECggIDQAAAA==.Baullo:BAAALAADCgYIBgAAAA==.',Be='Beeffalo:BAAALAAECgIIAgAAAA==.Bertie:BAAALAADCgcIDgAAAA==.',Bi='Bigbúsh:BAAALAAECgIIAgAAAA==.Bithken:BAAALAADCgEIAQAAAA==.Bittersweet:BAAALAAECgEIAQAAAA==.',Bj='Bjurustus:BAAALAADCgQIBAAAAA==.Bjutus:BAAALAAECgYIEAAAAA==.',Bl='Bloodfiury:BAABLAAECoEcAAIIAAcIERgoQAD4AQAIAAcIERgoQAD4AQAAAA==.Bluediamond:BAAALAAECgMIBQAAAA==.Bluerage:BAABLAAECoEaAAMJAAgI8ghMXgAjAQAJAAcIwQhMXgAjAQAKAAUIQAXizADAAAAAAA==.',Bo='Boer:BAACLAAFFIEHAAILAAMIgA/4DQDQAAALAAMIgA/4DQDQAAAsAAQKgSgAAgsACAjeHZsQAK0CAAsACAjeHZsQAK0CAAAA.Boet:BAAALAAECgYIBgABLAAECgcIGAAMAIQZAA==.Boombathias:BAACLAAFFIEGAAMKAAIIySLuFADKAAAKAAIIySLuFADKAAAJAAIIOQs7IQB5AAAsAAQKgR4AAwoACAhGJXQFAFIDAAoACAhGJXQFAFIDAAkABwgMG3cqAAYCAAAA.Boscolo:BAACLAAFFIEOAAIJAAUIESSgAQARAgAJAAUIESSgAQARAgAsAAQKgSMAAwkACAiUJcYDAEsDAAkACAiDJcYDAEsDAAoAAwjMJfGQAE4BAAAA.',Br='Brandsons:BAAALAAECggICAAAAA==.Bryce:BAABLAAECoEZAAILAAcIvB2hHABTAgALAAcIvB2hHABTAgAAAA==.',Bu='Bulgaras:BAAALAAECgYIDgAAAA==.Bumcank:BAABLAAECoEWAAINAAcIixeQHgDWAQANAAcIixeQHgDWAQABLAAECggIHwABAGYeAA==.',Ca='Cassíe:BAACLAAFFIEGAAIBAAII4BcXCwCiAAABAAII4BcXCwCiAAAsAAQKgS4AAgEACAilHf8JAJ8CAAEACAilHf8JAJ8CAAAA.Catchway:BAAALAADCgYIBgAAAA==.Cath:BAAALAAECgMICAAAAA==.',Ce='Cerevrus:BAAALAADCgUIBQAAAA==.',Ch='Chalmershand:BAAALAAECgQIBQAAAA==.Chatanka:BAAALAADCgEIAQABLAAECgcIEgADAAAAAA==.Chopstíx:BAAALAAECgcIDQAAAA==.',Ci='Cirii:BAABLAAECoEUAAMOAAgIDA8zSQCHAQAOAAgIDA8zSQCHAQAPAAEIbgQxNQAoAAAAAA==.Civiys:BAAALAAECgcIBwAAAA==.',Cl='Clem:BAABLAAECoEUAAIQAAgI4BCAGACzAQAQAAgI4BCAGACzAQAAAA==.',Co='Cobbles:BAAALAAECgMIAwAAAA==.Corvínus:BAAALAAECgIIBQAAAA==.',Cr='Crimba:BAAALAADCggICAAAAA==.Cronnax:BAAALAAECggICAAAAA==.Cryptowings:BAAALAADCgMIAwAAAA==.',Cs='Cs:BAAALAADCgUIBQAAAA==.',Da='Daddyphatass:BAAALAAECgMIAwABLAAECgcIDgADAAAAAA==.Daidaros:BAAALAADCgcIBwAAAA==.Daikan:BAAALAAECgYICQABLAAECggIJgAOACUeAA==.Dairymagic:BAAALAAECgEIAQAAAA==.Darkhard:BAAALAADCgYIBgAAAA==.Darudy:BAAALAADCggIEAAAAA==.',Dd='Ddraig:BAABLAAECoEYAAIRAAcIHAi6NQBXAQARAAcIHAi6NQBXAQAAAA==.',De='Deadog:BAAALAAECgIIAgABLAAECggIIgASAEQZAA==.Decayedsnack:BAAALAAECgMIAwABLAAECggIIgATANoiAA==.Deliciouss:BAAALAADCgYIBgAAAA==.Demanding:BAAALAAECgcIEQABLAAECggIGgALAE8ZAA==.Demilious:BAAALAADCgQIBQAAAA==.Demonmarre:BAAALAADCgcIDgAAAA==.Demonmilker:BAABLAAECoEYAAIUAAgIYxJiFwAdAgAUAAgIYxJiFwAdAgAAAA==.Dench:BAAALAADCgEIAQAAAA==.Dewb:BAAALAAECgYIDgAAAA==.',Dh='Dhaimon:BAAALAAECgYICAAAAA==.',Di='Digbick:BAAALAAECgYIBgAAAA==.Dinglingming:BAAALAAECgYIDQAAAA==.Dirty:BAAALAAECgIIAgAAAA==.',Do='Doeda:BAAALAAECgcIDgAAAA==.Downside:BAAALAADCgcIDgAAAA==.Doxi:BAAALAADCgQIBAAAAA==.',Dr='Dractherydon:BAAALAADCgQIBAAAAA==.Dragongril:BAAALAADCgcIBwAAAA==.Dreamynice:BAAALAAECgcIEgAAAA==.Driust:BAAALAAECggICAAAAA==.Driustt:BAABLAAECoEgAAIEAAgIxx2yIgC/AgAEAAgIxx2yIgC/AgAAAA==.Dromma:BAABLAAECoEdAAILAAgImBdyKAAPAgALAAgImBdyKAAPAgAAAA==.Droogon:BAAALAAECgYIDwAAAA==.Drtipsy:BAEALAADCgYIBgABLAAFFAUIEAAIAGoTAA==.Druidmist:BAAALAADCggICAAAAA==.Druidtime:BAAALAAECgMIAQAAAA==.Drushan:BAAALAADCggICAAAAA==.Drzugzug:BAECLAAFFIEQAAMIAAUIahMtBwC3AQAIAAUIahMtBwC3AQAVAAMIJgiYDACrAAAsAAQKgS8ABAgACAhMIdMWANoCAAgACAgJIdMWANoCABUACAinEzUuAJMBABYAAQjwH7crAFwAAAAA.',Du='Durinn:BAAALAAECgYIEQAAAA==.',Dz='Dzwig:BAABLAAECoEWAAMJAAYITQxmbQDxAAAJAAYI5AlmbQDxAAAKAAQIjArFzgC7AAAAAA==.',['Dé']='Démonic:BAAALAADCgcIDgABLAAECgMIAwADAAAAAA==.',['Dø']='Dødknægt:BAAALAADCgcIAgAAAA==.',Ea='Earthenhunt:BAAALAAECgUIBwAAAA==.',Ed='Edraeth:BAAALAAECgYIDAAAAA==.',El='Elanadior:BAAALAADCgQIBAAAAA==.Elcorazon:BAAALAAECgQIBAAAAA==.Eledith:BAAALAAECgYIEQAAAA==.Elentari:BAAALAADCgYIBgAAAA==.Elerethe:BAABLAAECoEaAAILAAgITxkmHgBKAgALAAgITxkmHgBKAgAAAA==.Eliarien:BAAALAADCggICAABLAAECggIJAAOAKYcAA==.Elikin:BAAALAADCgcICQAAAA==.Eloize:BAAALAAECgcIDAAAAA==.Elrohirn:BAAALAAECgYIDQAAAA==.Elunä:BAABLAAECoEUAAMLAAcIpCBgKwAAAgALAAcIpCBgKwAAAgAXAAUIaQ9jXQD3AAAAAA==.Elyziann:BAAALAADCgMIAwAAAA==.',Em='Emailed:BAAALAAECggIDAAAAA==.',Eo='Eoelisa:BAAALAADCgYICgAAAA==.Eoeslite:BAAALAADCggICAAAAA==.',Er='Eriden:BAAALAADCgEIAQAAAA==.Eronia:BAAALAAECgMIAQAAAA==.Erwan:BAABLAAECoEUAAIYAAgIVhMOCQDRAQAYAAgIVhMOCQDRAQAAAA==.',Eu='Eureko:BAABLAAECoElAAIZAAgIoAzXCAD6AQAZAAgIoAzXCAD6AQAAAA==.',Ew='Ewokonfire:BAAALAADCgYIBgAAAA==.',Ex='Excuzemylag:BAAALAAECgIIAgAAAA==.',Ey='Eylla:BAABLAAECoEmAAIOAAgI2CK6CAATAwAOAAgI2CK6CAATAwAAAA==.',Ez='Ezekyle:BAAALAADCgQIBAAAAA==.Ezuei:BAAALAAECgMIBAAAAA==.',Fa='Falendrin:BAAALAAECgYIBgAAAA==.Fallout:BAAALAADCgUIBQAAAA==.Fathererick:BAAALAAECgEIAQAAAA==.',Fe='Feed:BAAALAADCgMIAwABLAAECgMIBAADAAAAAA==.Feltey:BAAALAADCgYIBgAAAA==.',Fl='Floof:BAAALAAECgEIAQAAAA==.',Fo='Fontcest:BAAALAAECgQIBgAAAA==.',Fr='Frank:BAAALAADCggIJAAAAA==.Freakzo:BAABLAAECoEiAAISAAgIRBlqMQBiAgASAAgIRBlqMQBiAgAAAA==.Frostiez:BAAALAAECgYIDAAAAA==.',Fu='Fumi:BAAALAADCgMIAwAAAA==.Fuselage:BAAALAAECgIIAgAAAA==.',Ga='Gashbell:BAAALAAECgQIBQAAAA==.',Ge='Gearleaf:BAABLAAECoEhAAMMAAgIBBgTKwBkAgAMAAgIBBgTKwBkAgAaAAMIZwSlJgCUAAAAAA==.',Gi='Giacamo:BAAALAADCggIFAAAAA==.',Gl='Gladstone:BAAALAAECgMIAwABLAAECggIJQARANsgAA==.',Go='Goldiediaz:BAAALAADCgYIBgAAAA==.Goodmonson:BAAALAADCgcIBwAAAA==.Gorinth:BAAALAAECgIIAgAAAA==.Gozok:BAAALAADCgEIAQAAAA==.',Gr='Grc:BAACLAAFFIEGAAIJAAIIeRMiGwCIAAAJAAIIeRMiGwCIAAAsAAQKgScAAgkACAjdIEcNAOsCAAkACAjdIEcNAOsCAAAA.Greatteatree:BAAALAAECgIIAgAAAA==.Gregzor:BAAALAAECgUIBgAAAA==.Grim:BAAALAADCggIEwAAAA==.Grimzsie:BAAALAAECgMIBgAAAA==.',Gu='Guurm:BAAALAADCgEIAQAAAA==.',Gw='Gwenida:BAAALAAECggICAAAAA==.Gwindar:BAAALAAFFAIIAgAAAA==.',Ha='Hawktuah:BAAALAADCggICAAAAA==.',He='Heat:BAACLAAFFIENAAISAAQI8BsCDQCOAQASAAQI8BsCDQCOAQAsAAQKgSQABBIACAjhJFUSAAMDABIACAg2JFUSAAMDABsABwhwIZUDAGgCABwAAQj9B6iDACIAAAAA.Heavymetal:BAAALAADCgcICAAAAA==.Helafix:BAAALAAECggICQAAAA==.',Hi='Highonlight:BAAALAAECggICAABLAAECggIIAAKAHoaAA==.Hiiya:BAAALAADCggICwAAAA==.Hinterz:BAABLAAECoEgAAIJAAgIFCKnCAAXAwAJAAgIFCKnCAAXAwAAAA==.',Ho='Hocuspocus:BAAALAAECgYIBwAAAA==.Holygrapei:BAABLAAECoEdAAIEAAcIKB1cOQBgAgAEAAcIKB1cOQBgAgAAAA==.Holyhand:BAAALAAECggICAABLAAECggIIAAKAHoaAA==.Horridon:BAAALAADCgMIAwAAAA==.',Hu='Hucamo:BAABLAAECoElAAIRAAgI2yBBCQD2AgARAAgI2yBBCQD2AgAAAA==.',Hv='Hvalmon:BAAALAADCggIIQAAAA==.',Hy='Hyneth:BAAALAAECgcIDQAAAA==.Hyperarrows:BAABLAAECoEgAAIKAAgIehrJLQBbAgAKAAgIehrJLQBbAgAAAA==.Hyperwall:BAAALAAECggICAABLAAECggIIAAKAHoaAA==.',['Hé']='Hécate:BAABLAAECoEVAAIcAAYIax9iHQAEAgAcAAYIax9iHQAEAgAAAA==.',Ia='Iamded:BAABLAAECoEcAAMGAAgIrCJpAwAuAwAGAAgIrCJpAwAuAwAdAAUICQ0+6QD7AAAAAA==.Ianoyahs:BAAALAAECgcIEgAAAA==.',Ib='Iback:BAAALAADCgcIDQABLAAECggIIgATANoiAA==.',Ie='Ieronimus:BAAALAADCggIDAAAAA==.',Im='Impcubus:BAAALAAECgYIBgAAAA==.',Is='Isnack:BAAALAAECgYIBgABLAAECggIIgATANoiAA==.Istrine:BAAALAADCgUIBQAAAA==.',Je='Jeongukkie:BAAALAAECgMICAAAAA==.Jessepri:BAAALAAECgMIBQAAAA==.Jevren:BAAALAAECgEIAQAAAA==.',Ji='Jinx:BAAALAADCgcIDAAAAA==.',Jo='Jonace:BAAALAADCggIFwAAAA==.',Ju='Jud:BAAALAAECggICAAAAA==.Jusbrut:BAAALAAECgEIAQAAAA==.',['Jä']='Jäme:BAAALAAECgEIAQAAAA==.',['Jî']='Jînx:BAAALAADCgQIBAAAAA==.',Ka='Kalgar:BAABLAAECoEYAAIIAAcIKxSKTQDGAQAIAAcIKxSKTQDGAQAAAA==.Kapow:BAAALAADCgcIBwAAAA==.',Ke='Kebab:BAAALAAECgIIAgABLAAECgcIBwADAAAAAA==.Kendrik:BAAALAADCggICAABLAAFFAMIBwAOAOgFAA==.Kermie:BAAALAAECgQICQAAAA==.',Kh='Khashmir:BAAALAAECgUIDQAAAA==.Khell:BAAALAAECgcIBwAAAA==.',Ki='Kidhuntress:BAAALAAECgYICAAAAA==.Kidsauce:BAABLAAECoEiAAMTAAgI2iIyBwDJAgATAAcItyMyBwDJAgAHAAgIHx8OLgB4AgAAAA==.Kijin:BAAALAADCgQIBAAAAA==.',Kr='Krenkerlaif:BAAALAAECgMICAAAAA==.',Ks='Ksanax:BAAALAAECgYIDAAAAA==.',['Kí']='Kítchenguard:BAAALAADCggICwAAAA==.',La='Lawzard:BAAALAAECgMIAwAAAA==.',Le='Leanda:BAAALAAECgEIAQAAAA==.Leilã:BAAALAAECgEIAQAAAA==.Leoniëra:BAABLAAECoEZAAISAAcIMgx8bQCWAQASAAcIMgx8bQCWAQAAAA==.Leylia:BAABLAAECoEnAAIPAAgIQiI3AQAcAwAPAAgIQiI3AQAcAwAAAA==.',Li='Lightgirll:BAAALAADCggIDwAAAA==.Lightware:BAAALAADCggICAAAAA==.Likaria:BAAALAAECgYIBgAAAA==.',Lo='Loa:BAAALAADCgcIBwAAAA==.Locarys:BAAALAADCgcICQABLAAFFAIIBgABAOAXAA==.Lorgar:BAAALAAECgQICAAAAA==.Lovacisthis:BAABLAAECoEeAAIMAAgIBh98FwDaAgAMAAgIBh98FwDaAgABLAAFFAIIBgAMAFYgAA==.Loverboi:BAAALAAECgMIBwAAAA==.',Lu='Luciferost:BAAALAAECgMIAwAAAA==.Luthais:BAAALAADCgQIBQAAAA==.',Ly='Lyrath:BAAALAAECgYICQAAAA==.',Ma='Magestic:BAAALAADCgYIBgAAAA==.Magio:BAABLAAECoEXAAISAAcIMAjfgABiAQASAAcIMAjfgABiAQABLAAECgcIGwABADoPAA==.Magmar:BAAALAAECgEIAQAAAA==.Mahhamancer:BAABLAAFFIEGAAIMAAIIjRj9IwCiAAAMAAIIjRj9IwCiAAABLAAFFAIIBgAKAMkiAA==.Mahkay:BAAALAAECggICAAAAA==.Mahstra:BAAALAADCggIDwAAAA==.Manlizard:BAAALAADCggIIwABLAAECggIIgASAEQZAA==.Manthra:BAAALAAECgQICAAAAA==.Marlena:BAAALAADCgcIBwAAAA==.Marmites:BAAALAAECggICAAAAA==.Marsyas:BAAALAAECggIEwABLAAECggIIAAJABQiAA==.Massivebaps:BAAALAAECggICAAAAA==.Mataza:BAAALAADCgQIBQAAAA==.Mavlena:BAAALAADCggIDwAAAA==.Maybe:BAAALAAECggICAAAAA==.',Mb='Mbr:BAAALAADCggIDAAAAA==.',Mc='Mcfallen:BAAALAAECgYIEAAAAA==.',Me='Meincke:BAAALAAECgcIDgAAAA==.Meithrill:BAAALAADCgUIBQAAAA==.Mesury:BAABLAAECoEWAAIeAAcInRN5JQC3AQAeAAcInRN5JQC3AQAAAA==.',Mi='Mianaa:BAAALAAECgMIAwAAAA==.Microw:BAAALAAECgYIBgAAAA==.Midgetghoula:BAABLAAECoEgAAMMAAcIfA6ZXgCZAQAMAAcIfA6ZXgCZAQAaAAMIHQrSJQCaAAAAAA==.Miky:BAAALAAECggICAAAAA==.Milor:BAAALAADCggICAAAAA==.Milord:BAABLAAECoEbAAIEAAgI+x2/JwCoAgAEAAgI+x2/JwCoAgAAAA==.Milordy:BAAALAADCggIEAAAAA==.Milore:BAAALAADCggICAAAAA==.Milorhun:BAAALAADCggICAAAAA==.Milorth:BAAALAADCggICAAAAA==.Mingeak:BAAALAADCgIIAgAAAA==.Minibombo:BAAALAAECgYIBgAAAA==.Minnii:BAAALAAECgQIBAAAAA==.Mirrage:BAAALAADCgEIAQABLAAECggICAADAAAAAA==.',Mo='Moertz:BAAALAADCggICAABLAAECggIIgASAEQZAA==.Moffy:BAAALAADCgUIAgAAAA==.Morganthe:BAABLAAECoEmAAMOAAgIJR6xFQCeAgAOAAgIJR6xFQCeAgAfAAEIRhdkgABKAAAAAA==.Morliustax:BAAALAADCggIDAAAAA==.Mortemm:BAAALAADCggICAAAAA==.',Mu='Muln:BAAALAAECgcIBwAAAA==.Multifrugt:BAAALAADCgcIAgAAAA==.Munlo:BAABLAAECoEbAAIdAAcITgU0zgAyAQAdAAcITgU0zgAyAQAAAA==.Mustangshamy:BAAALAAECgQIBAAAAA==.',Na='Naid:BAAALAAECgcIBwAAAA==.Nalathekille:BAAALAAECgMIAwAAAA==.Natrium:BAAALAADCgcIAgABLAAFFAIIBgAKAMkiAA==.',Ne='Neera:BAABLAAECoEcAAIcAAgIMyQVAwBSAwAcAAgIMyQVAwBSAwABLAAECggIIAAJABQiAA==.',Ni='Nivixo:BAAALAAECggIEwAAAA==.',No='Norahx:BAAALAAFFAIIAgAAAA==.Normanddruid:BAAALAAECgIIAgAAAA==.Normandine:BAABLAAECoEbAAIEAAgIOxCgaADiAQAEAAgIOxCgaADiAQAAAA==.',Nw='Nwktt:BAAALAADCgYIDAAAAA==.',Ny='Nyeck:BAAALAADCggICAABLAAECgQICQADAAAAAA==.',['Ní']='Níxíe:BAACLAAFFIEIAAIHAAMIjwelFQDVAAAHAAMIjwelFQDVAAAsAAQKgSYAAwcACAgYGZM4AEwCAAcACAgYGZM4AEwCABMAAgjfEGhLAFwAAAAA.',Od='Odessea:BAAALAADCggICAAAAA==.',On='Onenotsotank:BAAALAADCggIBQABLAAECggIHAAGAKwiAA==.',Os='Osbin:BAAALAAECgYICQAAAA==.Osheana:BAAALAAECgYICAAAAA==.',Ou='Outtimer:BAAALAADCgUIBgAAAA==.',Ow='Ownaris:BAAALAAECggICgAAAA==.Ownas:BAAALAAECggIBgABLAAECggICgADAAAAAA==.',Pa='Paldoon:BAAALAAECgEIAQAAAA==.Parasiteeve:BAAALAAECgQIBQAAAA==.Pathia:BAAALAAECgYIBgAAAA==.',Pl='Plib:BAABLAAECoEbAAIFAAgIGB2qDAB+AgAFAAgIGB2qDAB+AgAAAA==.',Po='Pockethunter:BAAALAAECgMIBgAAAA==.Pocky:BAAALAAECgcIEQAAAA==.Poddes:BAAALAADCgcIAgAAAA==.Pollun:BAABLAAECoEcAAIKAAcI3x0KLQBeAgAKAAcI3x0KLQBeAgAAAA==.Potan:BAAALAAECggIDAAAAA==.',Pr='Prettyinpink:BAAALAAECgcIDQAAAA==.Prussano:BAAALAADCgQIBAAAAA==.',Ps='Psychowarrio:BAAALAAECgEIAQAAAA==.',Pw='Pwnografic:BAAALAAECgIIAgAAAA==.',Qo='Qonspiq:BAAALAADCgYIBgAAAA==.',Qu='Quipumann:BAAALAAECggIDwAAAA==.Quseak:BAAALAADCggIEAABLAAECggIDwADAAAAAA==.',Ra='Radenska:BAAALAAECggICgAAAA==.Rafum:BAAALAADCgcIBwABLAAECgcIDQADAAAAAA==.Ragashal:BAAALAADCgYIBgAAAA==.Ragnarson:BAAALAAECggICAAAAA==.Rainey:BAAALAADCgcIBwAAAA==.Raminass:BAAALAAECggIAQAAAA==.',Re='Reddol:BAAALAADCggIHQAAAA==.Rennox:BAAALAAECggIBAAAAA==.Retz:BAAALAAECgQIBgAAAA==.',Rh='Rhaknir:BAAALAADCgIIAQABLAAFFAIIBgABAOAXAA==.Rhianna:BAAALAADCgYIBgAAAA==.Rhogal:BAAALAAECgEIAgAAAA==.',Ri='Rikimar:BAAALAADCggIHQAAAA==.Rilian:BAAALAADCgMIAwAAAA==.Rillana:BAAALAADCgcIDQAAAA==.Risia:BAAALAAECgYIBgABLAAFFAYIGQAgAI8gAA==.',Ro='Robaa:BAAALAAECggIEgAAAA==.',Ru='Rubenkaos:BAAALAAECgYIBgABLAAECgcIEgADAAAAAA==.Rubmychi:BAABLAAECoEfAAIBAAgIZh7fBwDIAgABAAgIZh7fBwDIAgAAAA==.Runei:BAAALAAECgYIEgAAAA==.Rutran:BAAALAAECgYIDgAAAA==.',Ry='Ryzidk:BAAALAAECgMIAwAAAA==.',Sa='Safarifentz:BAAALAADCggICAAAAA==.Salraris:BAABLAAECoElAAIEAAgIuRzLKQCfAgAEAAgIuRzLKQCfAgAAAA==.Samiyah:BAAALAADCgYICAAAAA==.Santanax:BAAALAADCgIIAgAAAA==.Sariana:BAAALAADCgYIDQAAAA==.Sarìa:BAAALAADCggIDwAAAA==.Sathrosash:BAAALAADCggIDwABLAAECggIJgAOACUeAA==.Savoire:BAAALAAECgYIDgAAAA==.',Se='Selsiecain:BAAALAAECgMIAwAAAA==.Seradoragon:BAACLAAFFIENAAIhAAUIvSDnAAD5AQAhAAUIvSDnAAD5AQAsAAQKgSsAAyEACAjIJUAAAHYDACEACAjIJUAAAHYDABEACAjHHrkOAK8CAAAA.Serasei:BAAALAADCggIDQABLAAFFAUIDQAhAL0gAA==.Serasepth:BAAALAADCggIDAABLAAFFAUIDQAhAL0gAA==.Seraser:BAAALAAECgYICQABLAAFFAUIDQAhAL0gAA==.Serios:BAABLAAECoEcAAIaAAcIMBQ7CgD4AQAaAAcIMBQ7CgD4AQAAAA==.',Sh='Shaheal:BAABLAAECoEdAAICAAYIXxq/UQC4AQACAAYIXxq/UQC4AQABLAAECggIDwAUADUUAA==.Shaku:BAAALAADCggICAAAAA==.Shamako:BAABLAAECoEZAAICAAgI2RopKwA7AgACAAgI2RopKwA7AgAAAA==.Shamey:BAAALAADCgMIAwAAAA==.Shamydavisjr:BAAALAAECgMIBAAAAA==.Shaormonk:BAACLAAFFIEGAAQNAAIIexXCCgChAAANAAIIexXCCgChAAAiAAIIwwb5EQBlAAABAAEI2AnNEgBGAAAsAAQKgSkABA0ACAhjHrgNAJkCAA0ACAhFHbgNAJkCACIACAgJFyoTAPcBAAEAAwifGR42ALQAAAAA.Shazime:BAAALAAECgQIBwAAAA==.Shilo:BAABLAAECoEbAAIGAAcIIQWsJwDwAAAGAAcIIQWsJwDwAAAAAA==.Shimptik:BAABLAAECoEVAAIOAAYIaBDsWABLAQAOAAYIaBDsWABLAQAAAA==.Shinnok:BAAALAADCgcICgAAAA==.Shionchan:BAAALAAECgQIBAAAAA==.Shiralo:BAAALAAECgMIBgAAAA==.Shylasae:BAAALAADCggIDAABLAAECgcIGgAKADYNAA==.Shádow:BAAALAADCgEIAQAAAA==.',Si='Sillat:BAAALAADCgMIAwAAAA==.Sillith:BAAALAADCgUIBQAAAA==.Silvannas:BAAALAAECgIIAgAAAA==.Sins:BAAALAADCggIFQABLAAFFAQIDQASAPAbAA==.Sinwii:BAAALAAECgEIAQAAAA==.',Sl='Slowrunner:BAAALAAECgIIAgAAAA==.Slugga:BAAALAAECgYICwAAAA==.',Sn='Snazzles:BAAALAAFFAEIAQABLAAFFAMIBgAEANEbAA==.',So='Sodexho:BAABLAAECoEZAAIjAAcIjxINJwDNAQAjAAcIjxINJwDNAQAAAA==.Softpanda:BAAALAAECggICAABLAAECggIIAAKAHoaAA==.Sojoez:BAABLAAECoEbAAIEAAcIBBerWAAHAgAEAAcIBBerWAAHAgAAAA==.Sokerimunkki:BAAALAADCggIFAAAAA==.Sonji:BAABLAAECoEYAAIMAAgIkxqKJwB2AgAMAAgIkxqKJwB2AgAAAA==.Sonofglóin:BAAALAAECggIDAAAAA==.',Sp='Spicynoodle:BAAALAAECgQIBAABLAAFFAIIBgAKAMkiAA==.Sprudle:BAAALAAECggICAAAAA==.',Sq='Square:BAAALAAECgMIAgABLAAECggIGAAMAJMaAA==.',St='Stealtht:BAAALAADCggICAAAAA==.Stenbuk:BAAALAAECgYIEQAAAA==.Stirling:BAABLAAECoEmAAIRAAgI8Rq+EgB9AgARAAgI8Rq+EgB9AgAAAA==.Stirlingo:BAAALAADCggICwAAAA==.Stofzak:BAAALAADCgIIAgAAAA==.Stonestorm:BAAALAADCgEIAQAAAA==.',Su='Sumner:BAAALAADCgQIBAAAAA==.Sunday:BAAALAAECgMIAwAAAA==.',Sy='Sylusx:BAAALAADCgQIBAAAAA==.',['Sí']='Sínweé:BAABLAAECoEWAAMhAAgIkQs+CQCdAQAhAAgIkQs+CQCdAQARAAIIlgZrVABZAAAAAA==.',['Só']='Sóulfly:BAAALAAECgMIBgAAAA==.',Ta='Taavy:BAABLAAECoEVAAILAAcIDSEAEgChAgALAAcIDSEAEgChAgAAAA==.Taint:BAAALAADCgYIBgABLAAECggIHwABAGYeAA==.Talena:BAAALAADCgMIAwAAAA==.Taliah:BAAALAADCgIIAgABLAAECggIJgAOACUeAA==.Tallis:BAAALAAECgEIAQAAAA==.Talstad:BAAALAADCggIEAAAAA==.',Te='Tedybaer:BAAALAADCgEIAQAAAA==.Teelong:BAAALAAECgUIDwAAAA==.Tefton:BAAALAAECgMIBAAAAA==.Temmari:BAAALAADCggIDgAAAA==.Teylock:BAAALAADCggICAAAAA==.Teypo:BAAALAADCggICAAAAA==.Teyren:BAAALAAECgYIEQAAAA==.',Th='Thekan:BAAALAAECggICAAAAA==.Thelittleguy:BAAALAAECggICAAAAA==.Theritter:BAAALAADCggICAABLAAFFAIIAgADAAAAAA==.Thorsoami:BAABLAAECoEcAAIEAAcIthOUdQDHAQAEAAcIthOUdQDHAQAAAA==.Throrin:BAAALAADCggIDgAAAA==.Thunderbeep:BAABLAAECoEbAAMYAAgIlBfNBABhAgAYAAgIlBfNBABhAgAkAAEI0A7ePwA/AAAAAA==.Thunderclabz:BAAALAADCgcICgAAAA==.Thyllas:BAABLAAECoEbAAIBAAcIOg+1IgBXAQABAAcIOg+1IgBXAQAAAA==.Thündercloud:BAAALAADCggIDwAAAA==.',Ti='Tinytemper:BAAALAAECggICAAAAA==.Titan:BAABLAAECoEgAAIVAAgIPRlQFwBAAgAVAAgIPRlQFwBAAgAAAA==.',To='Toastmaker:BAAALAAECgEIAQAAAA==.Toureq:BAAALAAECgcICgAAAA==.Towanda:BAAALAAECgQICgAAAA==.',Tr='Trollaltdel:BAAALAAECgYICgAAAA==.',Ts='Tshad:BAABLAAECoEdAAIOAAgIlh03EQDDAgAOAAgIlh03EQDDAgABLAAECggIIgATANoiAA==.',Tu='Tucke:BAAALAAECgQIBQAAAA==.Turtlez:BAAALAAECgcIDQAAAA==.',Tz='Tzunwan:BAABLAAECoEkAAIlAAgIAgtCDwDFAQAlAAgIAgtCDwDFAQAAAA==.',['Tá']='Tánvir:BAAALAADCgcIDgAAAA==.',Ud='Udehr:BAAALAAECggIDwAAAA==.',Ul='Ultramar:BAAALAADCgYIBwAAAA==.',Un='Unamithil:BAABLAAECoEkAAIOAAgIphzaFwCOAgAOAAgIphzaFwCOAgAAAA==.Undeadtaker:BAAALAAECgYIBgAAAA==.Unhealable:BAAALAAECgYIEgAAAA==.',Ur='Urethritis:BAAALAADCgcIDwAAAA==.Urghat:BAABLAAECoEbAAICAAgIvRe7NwAMAgACAAgIvRe7NwAMAgAAAA==.',Va='Valkhan:BAABLAAECoEWAAIgAAgIQhyoHgCEAgAgAAgIQhyoHgCEAgAAAA==.',Ve='Veldan:BAABLAAECoEVAAIOAAcIlwa/YgAqAQAOAAcIlwa/YgAqAQAAAA==.Vellen:BAAALAAECgMIBwAAAA==.Vevien:BAABLAAECoEWAAIJAAgIrBWAKgAGAgAJAAgIrBWAKgAGAgAAAA==.',Vi='Virindra:BAABLAAECoEbAAIRAAcIQA4pLACYAQARAAcIQA4pLACYAQAAAA==.',Vo='Voidberg:BAAALAADCgIIAgAAAA==.Vokera:BAAALAADCgIIAgAAAA==.Volkaal:BAAALAAECgYICgAAAA==.Voshkap:BAAALAAECgUICQAAAA==.',Wa='Warfare:BAAALAADCgcICAABLAAECgEIAQADAAAAAA==.Waroflocks:BAAALAADCggICAAAAA==.',We='Weemanz:BAAALAADCgMIAwAAAA==.Weetonk:BAAALAADCggICAAAAA==.Wesleysnypes:BAAALAADCgMIAwABLAAECgMIBAADAAAAAA==.',Wi='Willard:BAAALAAECgYIDwABLAAECgcIBwADAAAAAA==.Willdcat:BAAALAAECgQICQAAAA==.Wizzpop:BAAALAAECgIIAgAAAA==.',Wy='Wyl:BAAALAAECgYIBwAAAA==.',['Wó']='Wólverin:BAAALAADCggIDwAAAA==.',Xe='Xenophia:BAAALAAECggIBwAAAA==.',Xp='Xper:BAACLAAFFIELAAMWAAMIfhrFAAAOAQAWAAMIfhrFAAAOAQAVAAMIYAbBDACpAAAsAAQKgS4ABBYACAh5I7IBADUDABYACAh5I7IBADUDABUACAhvFJIdAAgCAAgAAgh7E+StAIYAAAAA.',Yo='Yohanna:BAACLAAFFIEGAAIdAAMIKxMWFwDpAAAdAAMIKxMWFwDpAAAsAAQKgS0AAh0ACAj7IbERABYDAB0ACAj7IbERABYDAAAA.Yomna:BAAALAAECggICAAAAA==.Youngfather:BAABLAAECoEWAAIbAAcISAOeDgDqAAAbAAcISAOeDgDqAAAAAA==.',Yu='Yuriel:BAACLAAFFIENAAIXAAUI9g2qBQBuAQAXAAUI9g2qBQBuAQAsAAQKgScAAhcACAilH+gNAN4CABcACAilH+gNAN4CAAAA.',Za='Zalorin:BAABLAAECoEXAAIIAAcIWQ3XYgCFAQAIAAcIWQ3XYgCFAQAAAA==.Zaolin:BAAALAADCgEIAQAAAA==.Zavara:BAAALAADCggICAAAAA==.',Ze='Zelina:BAABLAAECoEaAAIKAAcINg1ghgBkAQAKAAcINg1ghgBkAQAAAA==.Zeraora:BAAALAAECgEIAQAAAA==.Zerfall:BAAALAADCggICAAAAA==.Zestari:BAAALAADCgUIBQAAAA==.',Zh='Zhion:BAAALAAECggIEwAAAA==.',Zi='Ziggy:BAABLAAECoEbAAIOAAcINiHDFwCPAgAOAAcINiHDFwCPAgAAAA==.Zigrim:BAAALAADCgcIBwAAAA==.Zinest:BAACLAAFFIEHAAIOAAMI6AXJJwCGAAAOAAMI6AXJJwCGAAAsAAQKgSoAAg4ACAi8GIQeAGACAA4ACAi8GIQeAGACAAAA.',Zk='Zkyblast:BAAALAAECgYICgAAAA==.Zkyfel:BAAALAAECgYIBwAAAA==.Zkypyro:BAAALAADCgcIEwAAAA==.Zkyte:BAAALAAECgYIDwAAAA==.Zkytem:BAAALAAECgYIDwAAAA==.Zkytie:BAAALAAECgUIDAAAAA==.',Zm='Zmajcek:BAAALAAECgYICAAAAA==.',Zs='Zskin:BAAALAAECgIIAwAAAA==.',Zu='Zunimaister:BAAALAADCgMIAwABLAAECgQICQADAAAAAA==.Zunistrasz:BAAALAADCgQIBAAAAA==.Zunithedruid:BAAALAADCggICAABLAAECgQICQADAAAAAA==.Zunithewitch:BAAALAAECgQICQAAAA==.',['Är']='Ärï:BAABLAAECoEXAAQjAAgIsRtAEwBxAgAjAAcIux1AEwBxAgAYAAMIbA1eFgB3AAAkAAIICxDWOAB1AAAAAA==.',['Øn']='Ønsker:BAAALAAECgYIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end