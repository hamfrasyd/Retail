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
 local lookup = {'Paladin-Retribution','Paladin-Protection','Druid-Restoration','Hunter-Marksmanship','Monk-Windwalker','Unknown-Unknown','Monk-Mistweaver','DemonHunter-Havoc','Warrior-Fury','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Survival','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Mage-Fire','Mage-Arcane','Mage-Frost','DemonHunter-Vengeance','Priest-Discipline','Evoker-Augmentation','Shaman-Restoration','Monk-Brewmaster','Shaman-Enhancement','DeathKnight-Frost','Druid-Balance',}; local provider = {region='EU',realm='Ghostlands',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abeny:BAAALAADCgQIBAAAAA==.',Ac='Acabrew:BAAALAAECgQIBwAAAA==.Achtung:BAAALAADCggICAAAAA==.',Ad='Adderalandy:BAAALAADCgUIBQAAAA==.',Ai='Aikomoon:BAAALAAECgMIAwAAAA==.Aiyale:BAAALAAECgEIAQAAAA==.',Al='Alakazoome:BAAALAAECgYIBgAAAA==.Alucardv:BAAALAADCgYIBgAAAA==.',Am='Amabloodsong:BAAALAADCgcIBwAAAA==.Amanitta:BAAALAAECgUIDAAAAA==.',An='Anaxímander:BAAALAADCgYICgAAAA==.Anexen:BAABLAAECoEaAAMBAAgICCJzCQAlAwABAAgICCJzCQAlAwACAAcIJxVfFACUAQAAAA==.Angelolight:BAAALAADCggICAAAAA==.',Ap='Apoxology:BAAALAAECgYICQAAAA==.',Aq='Aquaeructo:BAAALAAECgEIAgAAAA==.',Ar='Arinnaya:BAAALAADCggICAAAAA==.Arthory:BAAALAAECgUICAAAAA==.',As='Assultturkey:BAAALAADCgcIBwAAAA==.',At='Atlass:BAAALAADCgMIAwAAAA==.',Av='Available:BAAALAAECgYICwAAAA==.',Ax='Axeedge:BAAALAADCggICwAAAA==.',Az='Azkadelia:BAAALAAECgIIAgAAAA==.Azraq:BAAALAADCggIFgAAAA==.',Ba='Babynate:BAAALAAECggICAAAAA==.Badussy:BAAALAAECgYICwAAAA==.Baghdaddy:BAAALAADCggIEAAAAA==.Ballbuster:BAAALAAECggIDgAAAA==.Barricade:BAAALAADCgcICwAAAA==.Bassie:BAAALAADCggIEQAAAA==.Baullo:BAAALAADCgYIBgAAAA==.',Be='Bertie:BAAALAADCgcIDgAAAA==.',Bi='Bithken:BAAALAADCgEIAQAAAA==.Bittersweet:BAAALAAECgEIAQAAAA==.',Bj='Bjutus:BAAALAAECgYIDwAAAA==.',Bl='Bloodfiury:BAAALAAECgYIDwAAAA==.Bluediamond:BAAALAAECgMIBQAAAA==.Bluerage:BAAALAAECgYICgAAAA==.',Bo='Boer:BAABLAAECoEgAAIDAAgIaRu0CgCVAgADAAgIaRu0CgCVAgAAAA==.Boombathias:BAAALAAECgcIDgAAAA==.Boscolo:BAABLAAECoEXAAIEAAgIJyVQAgBJAwAEAAgIJyVQAgBJAwAAAA==.',Br='Bryce:BAAALAAECgYIDAAAAA==.',Bu='Bulgaras:BAAALAAECgMIBAAAAA==.Bumcank:BAABLAAECoEWAAIFAAcIixf/EAADAgAFAAcIixf/EAADAgABLAAECggICAAGAAAAAA==.',Ca='Cassíe:BAABLAAECoEeAAIHAAgIHB0fBgCqAgAHAAgIHB0fBgCqAgAAAA==.Catchway:BAAALAADCgYIBgAAAA==.Cath:BAAALAAECgEIAQAAAA==.',Ch='Chalmershand:BAAALAAECgEIAQAAAA==.Chatanka:BAEALAADCgEIAQABLAAECgcIEgAGAAAAAA==.Chopstíx:BAAALAAECgcIDQAAAA==.',Ci='Cirii:BAAALAAECgcIDQAAAA==.',Cl='Clem:BAAALAAECgUICgAAAA==.',Co='Cobbles:BAAALAAECgIIAgAAAA==.Corvínus:BAAALAAECgIIAgAAAA==.',Cr='Crimba:BAAALAADCggICAAAAA==.Cryptowings:BAAALAADCgMIAwAAAA==.',Da='Daddyphatass:BAAALAAECgMIAwABLAAECgcIDgAGAAAAAA==.Daidaros:BAAALAADCgcIBwAAAA==.Dairymagic:BAAALAAECgEIAQAAAA==.',Dd='Ddraig:BAAALAAECgYICwAAAA==.',De='Decayedsnack:BAAALAAECgMIAwABLAAECggIFwAIAAoeAA==.Decima:BAAALAADCgMIAwAAAA==.Demanding:BAAALAAECgYIBgABLAAECggIFwADAGoYAA==.Demilious:BAAALAADCgQIBQAAAA==.Demonmarre:BAAALAADCgcIDgAAAA==.Demonmilker:BAAALAAECgcIBwAAAA==.Dench:BAAALAADCgEIAQAAAA==.Dewb:BAAALAAECgEIAQAAAA==.',Di='Digbick:BAAALAADCgYIBgAAAA==.Dinglingming:BAAALAAECgQIBAAAAA==.',Do='Doeda:BAAALAADCggICAAAAA==.Downside:BAAALAADCgcIBwAAAA==.Doxi:BAAALAADCgQIBAAAAA==.',Dr='Dractherydon:BAAALAADCgQIBAAAAA==.Dragongril:BAAALAADCgcIBwAAAA==.Dreamynice:BAAALAAECgcIEgAAAA==.Driust:BAAALAADCggIDwAAAA==.Driustt:BAAALAAECggIEQAAAA==.Dromma:BAAALAAECgYIDwAAAA==.Droogon:BAAALAAECgYIDwAAAA==.Droxes:BAAALAADCgYIBgAAAA==.Drtipsy:BAEALAADCgYIBgABLAAFFAMIBgAJADAOAA==.Druidtime:BAAALAAECgMIAQAAAA==.Drushan:BAAALAADCggICAAAAA==.Drzugzug:BAECLAAFFIEGAAMJAAMIMA5VBwD1AAAJAAMIMA5VBwD1AAAKAAIIawqiCgB3AAAsAAQKgSQABAkACAhkIGQLAO0CAAkACAghIGQLAO0CAAoACAinEzsXALYBAAsAAQjwH8odAF0AAAAA.',Du='Durinn:BAAALAAECgYICgAAAA==.',Dz='Dzwig:BAAALAAECggIDAAAAA==.',['Dé']='Démonic:BAAALAADCgcIDgAAAA==.',['Dø']='Dødknægt:BAAALAADCgcIAgAAAA==.',Ea='Earthenhunt:BAAALAAECgIIAgAAAA==.',El='Elcorazon:BAAALAADCggIDgAAAA==.Eledith:BAAALAAECgMIAwAAAA==.Elentari:BAAALAADCgYIBgAAAA==.Elerethe:BAABLAAECoEXAAIDAAgIahjLEABSAgADAAgIahjLEABSAgAAAA==.Eliarien:BAAALAADCggICAABLAAECggIGwAMAJ4YAA==.Eloize:BAAALAAECgUIBwAAAA==.Elrohirn:BAAALAAECgQIBwAAAA==.Elunä:BAAALAAECgUICAAAAA==.',Em='Emailed:BAAALAAECggIDAAAAA==.',Eo='Eoelisa:BAAALAADCgYICgAAAA==.Eoeslite:BAAALAADCggICAAAAA==.',Er='Eriden:BAAALAADCgEIAQAAAA==.Eronia:BAAALAAECgEIAQAAAA==.Erwan:BAAALAAECgYICgAAAA==.',Eu='Eureko:BAABLAAECoEVAAINAAcI8QgHCACiAQANAAcI8QgHCACiAQAAAA==.',Ew='Ewokonfire:BAAALAADCgYIBgAAAA==.',Ex='Excuzemylag:BAAALAAECgIIAgAAAA==.',Ey='Eylla:BAABLAAECoEbAAIMAAgIfyI7BAAfAwAMAAgIfyI7BAAfAwAAAA==.',Ez='Ezuei:BAAALAAECgMIAwAAAA==.',Fa='Falendrin:BAAALAAECgIIAgAAAA==.Fallout:BAAALAADCgUIBQAAAA==.Fathererick:BAAALAAECgEIAQAAAA==.',Fe='Feed:BAAALAADCgMIAwABLAAECgMIBAAGAAAAAA==.',Fl='Floof:BAAALAAECgEIAQAAAA==.',Fo='Fontcest:BAAALAADCggICAAAAA==.',Fr='Frank:BAAALAADCggIFQAAAA==.Freakzo:BAAALAAECgcIEwAAAA==.Frostiez:BAAALAAECgYIDAAAAA==.',Fu='Fumi:BAAALAADCgMIAwAAAA==.',Ge='Gearleaf:BAABLAAECoEZAAMOAAgIExWIIQAiAgAOAAgIExWIIQAiAgAPAAMIZwQ8HwCiAAAAAA==.',Gi='Giacamo:BAAALAADCggIFAAAAA==.',Gl='Gladstone:BAAALAADCgcICwABLAAECgcIFQAQAKQdAA==.',Go='Goodmonson:BAAALAADCgcIBwAAAA==.Gorinth:BAAALAADCgcIBwAAAA==.Gozok:BAAALAADCgEIAQAAAA==.',Gr='Grc:BAABLAAECoEXAAIEAAgIzB3+DACoAgAEAAgIzB3+DACoAgAAAA==.Greatteatree:BAAALAAECgIIAgAAAA==.Gregzor:BAAALAAECgUIBgAAAA==.Grim:BAAALAADCggIEwAAAA==.Grimzsie:BAAALAAECgEIAQAAAA==.',Gu='Guurm:BAAALAADCgEIAQAAAA==.',Gw='Gwindar:BAAALAAECgYIEAAAAA==.',He='Heartstrings:BAAALAAECgYIDAAAAA==.Heat:BAABLAAECoEcAAQRAAgIkyOpAQCaAgASAAgI4yEKDwDpAgARAAcIcCGpAQCaAgATAAEI/QfcXwAkAAAAAA==.Heavymetal:BAAALAADCgcICAAAAA==.Helafix:BAAALAAECggICAAAAA==.',Hi='Hiiya:BAAALAADCggICwAAAA==.Hinterz:BAAALAAECgcIEQAAAA==.',Ho='Hocuspocus:BAAALAADCggIEwAAAA==.Holygrapei:BAAALAAECgYIDwAAAA==.Horridon:BAAALAADCgMIAwAAAA==.',Hu='Hucamo:BAABLAAECoEVAAIQAAcIpB0xEQBIAgAQAAcIpB0xEQBIAgAAAA==.',Hv='Hvalmon:BAAALAADCggIGwAAAA==.',Hy='Hyperarrows:BAAALAAECgcIEgAAAA==.',['Hé']='Hécate:BAABLAAECoEVAAITAAYIax+TEAAlAgATAAYIax+TEAAlAgAAAA==.',Ia='Iamded:BAAALAAECgcICwAAAA==.Ianoyahs:BAEALAAECgcIEgAAAA==.',Ib='Iback:BAAALAADCgcIDQABLAAECggIFwAIAAoeAA==.',Je='Jeongukkie:BAAALAAECgEIAQAAAA==.Jessepri:BAAALAAECgMIBQAAAA==.Jevren:BAAALAAECgEIAQAAAA==.',Ji='Jinx:BAAALAADCgQIBAAAAA==.',Jo='Jonace:BAAALAADCgcIBwAAAA==.',Ju='Jusbrut:BAAALAADCgMIBAAAAA==.',['Jä']='Jäme:BAAALAADCggIEwAAAA==.',['Jî']='Jînx:BAAALAADCgQIBAAAAA==.',Ka='Kalgar:BAAALAAECgYIEQAAAA==.',Ke='Kendrik:BAAALAADCggICAABLAAECggIGgAMAP8HAA==.Kermie:BAAALAAECgQIBwAAAA==.',Kh='Khashmir:BAAALAAECgUICAAAAA==.Khell:BAAALAAECgcIBwAAAA==.',Ki='Kidsauce:BAABLAAECoEXAAMIAAgICh7bGQCOAgAIAAgICh7bGQCOAgAUAAIIjRvrKgCWAAAAAA==.Kijin:BAAALAADCgQIBAAAAA==.',Kr='Krenkerlaif:BAAALAAECgEIAQAAAA==.',Ks='Ksanax:BAAALAAECgEIAQAAAA==.',['Kí']='Kítchenguard:BAAALAADCggICwAAAA==.',La='Lawzard:BAAALAAECgMIAwAAAA==.',Le='Leanda:BAAALAAECgEIAQAAAA==.Leoniëra:BAAALAAECgYIDAAAAA==.Leylia:BAABLAAECoEXAAIVAAcI1x8fAgCSAgAVAAcI1x8fAgCSAgAAAA==.',Li='Likaria:BAAALAAECgYIBgAAAA==.',Lo='Loa:BAAALAADCgcIBwAAAA==.Locarys:BAAALAADCgcICQABLAAECggIHgAHABwdAA==.Lorgar:BAAALAAECgMIBAAAAA==.Lovacisthis:BAAALAAFFAEIAQABLAAECggIGgAOANEiAA==.Loverboi:BAAALAAECgMIBwAAAA==.',Lu='Luciferost:BAAALAAECgMIAwAAAA==.Luthais:BAAALAADCgQIBQAAAA==.',Ly='Lyrath:BAAALAAECgYICQAAAA==.',Ma='Magio:BAAALAAECgYICgABLAAECgYIDAAGAAAAAA==.Magmar:BAAALAAECgEIAQAAAA==.Mahhamancer:BAAALAAECgYIBgABLAAECgcIDgAGAAAAAA==.Mahkay:BAAALAAECggICAAAAA==.Manlizard:BAAALAADCggIEwABLAAECgcIEwAGAAAAAA==.Manthra:BAAALAAECgMIBQAAAA==.Marlena:BAAALAADCgcIBwAAAA==.Marsyas:BAAALAAECgcICwABLAAECgcIEQAGAAAAAA==.Maybe:BAAALAAECggICAAAAA==.',Mb='Mbr:BAAALAADCgQIBAAAAA==.',Mc='Mcfallen:BAAALAAECgYIEAAAAA==.',Me='Meincke:BAAALAAECgcIDgAAAA==.Mesury:BAAALAAECgUICQAAAA==.',Mi='Mianaa:BAAALAAECgMIAwAAAA==.Microw:BAAALAADCggICAAAAA==.Midgetghoula:BAAALAAECgYIEwAAAA==.Milor:BAAALAADCggICAAAAA==.Milord:BAABLAAECoEVAAIBAAgIvRuPHgBxAgABAAgIvRuPHgBxAgAAAA==.Milordy:BAAALAADCggIEAAAAA==.Milore:BAAALAADCggICAAAAA==.Milorhun:BAAALAADCggICAAAAA==.Milorth:BAAALAADCggICAAAAA==.Mingeak:BAAALAADCgIIAgAAAA==.Mirrage:BAAALAADCgEIAQAAAA==.',Mo='Moertz:BAAALAADCggICAABLAAECgcIEwAGAAAAAA==.Moffy:BAAALAADCgUIAgAAAA==.Morganthe:BAABLAAECoEVAAIMAAcImh2nGAA3AgAMAAcImh2nGAA3AgAAAA==.Morliustax:BAAALAADCggIDAAAAA==.',Mu='Multifrugt:BAAALAADCgcIAgAAAA==.Munlo:BAAALAAECgYIDQAAAA==.Mustangshamy:BAAALAAECgEIAQAAAA==.',Na='Nalathekille:BAAALAAECgMIAwAAAA==.Natrium:BAAALAADCgcIAgABLAAECgcIDgAGAAAAAA==.',Ne='Neera:BAAALAAECgYIDQABLAAECgcIEQAGAAAAAA==.',Ni='Nivixo:BAAALAAECgcICwAAAA==.',No='Norahx:BAAALAAFFAIIAgAAAA==.Normanddruid:BAAALAADCgcIBAAAAA==.Normandine:BAAALAAECgcICwAAAA==.',Nw='Nwktt:BAAALAADCgYIDAAAAA==.',Ny='Nyeck:BAAALAADCggICAABLAAECgMIBQAGAAAAAA==.',['Ní']='Níxíe:BAABLAAECoEWAAMIAAcI/RT1OQDcAQAIAAcI1hT1OQDcAQAUAAII3xDwMABoAAAAAA==.',On='Onenotsotank:BAAALAADCggIBQABLAAECgcICwAGAAAAAA==.',Os='Osbin:BAAALAAECgIIAgAAAA==.Osheana:BAAALAAECgUIBwAAAA==.',Ou='Outtimer:BAAALAADCgUIBgAAAA==.',Ow='Ownaris:BAAALAAECggICgAAAA==.Ownas:BAAALAAECggIBgABLAAECggICgAGAAAAAA==.',Pa='Paldoon:BAAALAAECgEIAQAAAA==.Parasiteeve:BAAALAAECgQIBQAAAA==.',Pl='Plib:BAAALAAECgcICwAAAA==.',Po='Pockethunter:BAAALAAECgEIAQAAAA==.Pocky:BAAALAAECgMIAwAAAA==.Poddes:BAAALAADCgcIAgAAAA==.Pollun:BAAALAAECgYICAAAAA==.Potan:BAAALAAECgcIBwAAAA==.',Pr='Prussano:BAAALAADCgQIBAAAAA==.',Ps='Psychowarrio:BAAALAAECgEIAQAAAA==.',Qo='Qonspiq:BAAALAADCgYIBgAAAA==.',Qu='Quipumann:BAAALAAECgUIBQAAAA==.',Ra='Radenska:BAAALAAECgIIAwAAAA==.Ragashal:BAAALAADCgYIBgAAAA==.',Re='Reddol:BAAALAADCgcIDQAAAA==.Rennox:BAAALAADCgcIEAAAAA==.Retz:BAAALAAECgMIBAAAAA==.',Rh='Rhaknir:BAAALAADCgIIAQABLAAECggIHgAHABwdAA==.Rhianna:BAAALAADCgYIBgAAAA==.Rhogal:BAAALAAECgEIAgAAAA==.',Ri='Rikimar:BAAALAADCggIHQAAAA==.Rilian:BAAALAADCgMIAwAAAA==.Rillana:BAAALAADCgcIDQAAAA==.Risia:BAAALAADCgcIBwAAAA==.',Ro='Robaa:BAAALAAECgIIAgAAAA==.',Ru='Rubenkaos:BAAALAADCgYICwAAAA==.Rubmychi:BAAALAAECggICAAAAA==.Runei:BAAALAAECgMIBAAAAA==.Rutran:BAAALAAECgMIBgAAAA==.',Ry='Ryzidk:BAAALAAECgMIAwAAAA==.',Sa='Salraris:BAABLAAECoEUAAIBAAgIJxXpLQAdAgABAAgIJxXpLQAdAgAAAA==.Samiyah:BAAALAADCgYIBgAAAA==.Sariana:BAAALAADCgYICwAAAA==.Sarìa:BAAALAADCgcIBwAAAA==.Savoire:BAAALAAECgEIAgAAAA==.',Se='Selsiecain:BAAALAAECgMIAwAAAA==.Seradoragon:BAABLAAECoEfAAMWAAgIPSFfAQDKAgAQAAgIxx5sBwDmAgAWAAgIYSBfAQDKAgAAAA==.Serasepth:BAAALAADCggIDAABLAAECggIHwAWAD0hAA==.Serios:BAAALAAECgYICAAAAA==.',Sh='Shaheal:BAAALAAECgYIEQAAAA==.Shamako:BAABLAAECoEZAAIXAAgI2RpNFgBOAgAXAAgI2RpNFgBOAgAAAA==.Shamydavisjr:BAAALAADCgcICgAAAA==.Shaormonk:BAABLAAECoEZAAQFAAgIqRv2CACTAgAFAAgIqRv2CACTAgAYAAcIMxXNEACqAQAHAAMInxkrJgC+AAAAAA==.Shilo:BAAALAAECgYIDgAAAA==.Shimptik:BAAALAAECgYICQAAAA==.Shiralo:BAAALAAECgMIAwAAAA==.Shylasae:BAAALAADCgQIBAABLAAECgYIDQAGAAAAAA==.',Si='Sins:BAAALAADCggIFQABLAAECggIHAARAJMjAA==.Sinwii:BAAALAAECgEIAQAAAA==.',Sl='Slugga:BAAALAAECgUICgAAAA==.',Sn='Snazzles:BAAALAAECgEIAQABLAAECggIGgABAAgiAA==.',So='Sodexho:BAAALAAECgYIDQAAAA==.Sojoez:BAAALAAECgYIDgAAAA==.Sokerimunkki:BAAALAADCggIFAAAAA==.Sonji:BAABLAAECoEUAAIOAAcIcBvjIAAnAgAOAAcIcBvjIAAnAgAAAA==.Sonofglóin:BAAALAAECggICAAAAA==.',Sq='Square:BAAALAADCggIDQABLAAECgcIFAAOAHAbAA==.',St='Stealtht:BAAALAADCggICAAAAA==.Stenbuk:BAAALAAECgYIEQAAAA==.Stirling:BAABLAAECoEVAAIQAAcIqBezFgD6AQAQAAcIqBezFgD6AQAAAA==.Stirlingo:BAAALAADCggICwAAAA==.Stofzak:BAAALAADCgIIAgAAAA==.Stonestorm:BAAALAADCgEIAQAAAA==.',Su='Sumner:BAAALAADCgQIBAAAAA==.Sunday:BAAALAADCggIBwAAAA==.',Sy='Sylusx:BAAALAADCgQIBAAAAA==.',['Sí']='Sínweé:BAABLAAECoEUAAMWAAYILgx9BgBKAQAWAAYILgx9BgBKAQAQAAIIlgaNPgBfAAAAAA==.',['Só']='Sóulfly:BAAALAAECgMIBgAAAA==.',Ta='Taavy:BAAALAAECgcICwAAAA==.Taint:BAAALAADCgYIBgABLAAECggICAAGAAAAAA==.Talena:BAAALAADCgMIAwAAAA==.Taliah:BAAALAADCgIIAgABLAAECgcIFQAMAJodAA==.Tallis:BAAALAAECgEIAQAAAA==.',Te='Teelong:BAAALAAECgUIBQAAAA==.Tefton:BAAALAAECgMIBAAAAA==.Temmari:BAAALAADCggICAAAAA==.Teylock:BAAALAADCggICAAAAA==.Teyren:BAAALAAECgIIAwAAAA==.',Th='Thelittleguy:BAAALAAECggICAAAAA==.Thorsoami:BAAALAAECgYIDgAAAA==.Thunderbeep:BAAALAAECgcICwAAAA==.Thunderclabz:BAAALAADCgUIBQAAAA==.Thyllas:BAAALAAECgYIDAAAAA==.',Ti='Titan:BAAALAAECgcIEAAAAA==.',To='Toastmaker:BAAALAADCggICAAAAA==.Toureq:BAAALAAECgMIAwAAAA==.Towanda:BAAALAAECgIIAwAAAA==.',Tr='Trollaltdel:BAAALAAECgYICgAAAA==.',Ts='Tshad:BAAALAAECgYICwABLAAECggIFwAIAAoeAA==.',Tu='Tucke:BAAALAAECgQIBQAAAA==.',Tz='Tzunwan:BAABLAAECoEXAAIZAAcI9gi8DQCFAQAZAAcI9gi8DQCFAQAAAA==.',['Tá']='Tánvir:BAAALAADCgcIDgAAAA==.',Ul='Ultramar:BAAALAADCgYIBwAAAA==.',Un='Unamithil:BAABLAAECoEbAAIMAAgInhgNFABeAgAMAAgInhgNFABeAgAAAA==.',Ur='Urethritis:BAAALAADCgcIDwAAAA==.Urghat:BAAALAAECgYICwAAAA==.',Va='Valkhan:BAAALAAECggICgAAAA==.',Ve='Veldan:BAAALAAECgYICwAAAA==.Vellen:BAAALAAECgEIAQAAAA==.Vevien:BAAALAAECgcIDgAAAA==.',Vi='Virindra:BAAALAAECgYIDgAAAA==.',Vo='Volkaal:BAAALAAECgYICgAAAA==.Voshkap:BAAALAAECgMIBAAAAA==.',Wa='Warfare:BAAALAADCgcICAABLAAECgEIAQAGAAAAAA==.',We='Weemanz:BAAALAADCgMIAwAAAA==.Wesleysnypes:BAAALAADCgMIAwABLAADCgcICgAGAAAAAA==.',Wi='Willard:BAAALAAECgIIAwAAAA==.Willdcat:BAAALAAECgMIBAAAAA==.',Wy='Wyl:BAAALAAECgYIBwAAAA==.',['Wó']='Wólverin:BAAALAADCggIDwAAAA==.',Xe='Xenophia:BAAALAAECggIAwAAAA==.',Xp='Xper:BAABLAAECoEeAAILAAgIvyLoAAA3AwALAAgIvyLoAAA3AwAAAA==.',Yo='Yohanna:BAABLAAECoEdAAIaAAgInxjCIQBhAgAaAAgInxjCIQBhAgAAAA==.Youngfather:BAAALAAECgUICQAAAA==.',Yu='Yuriel:BAACLAAFFIEIAAIbAAMIxwXuBQDGAAAbAAMIxwXuBQDGAAAsAAQKgR4AAhsACAhcGTURAGgCABsACAhcGTURAGgCAAAA.',Za='Zalorin:BAABLAAECoEXAAIJAAcIWQ3TMACoAQAJAAcIWQ3TMACoAQAAAA==.Zaolin:BAAALAADCgEIAQAAAA==.Zavara:BAAALAADCggICAAAAA==.',Ze='Zelina:BAAALAAECgYIDQAAAA==.Zeraora:BAAALAAECgEIAQAAAA==.Zerfall:BAAALAADCggICAAAAA==.',Zh='Zhion:BAAALAAECgcICwAAAA==.',Zi='Ziggy:BAAALAAECgYIDgAAAA==.Zigrim:BAAALAADCgcIBwAAAA==.Zinest:BAABLAAECoEaAAIMAAgI/wf1NQB6AQAMAAgI/wf1NQB6AQAAAA==.',Zk='Zkyblast:BAAALAADCgMIAwAAAA==.Zkyfel:BAAALAADCgYIBwAAAA==.Zkypyro:BAAALAADCgIIAgAAAA==.Zkyte:BAAALAAECgEIAQAAAA==.Zkytem:BAAALAAECgYIBgAAAA==.Zkytie:BAAALAAECgUIBQAAAA==.',Zm='Zmajcek:BAAALAAECgIIAwAAAA==.',Zu='Zunimaister:BAAALAADCgMIAwABLAAECgMIBQAGAAAAAA==.Zunithewitch:BAAALAAECgMIBQAAAA==.',['Är']='Ärï:BAAALAAECgUIBQAAAA==.',['Øn']='Ønsker:BAAALAAECgUIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end