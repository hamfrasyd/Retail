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
 local lookup = {'Mage-Frost','Paladin-Holy','Unknown-Unknown','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Evoker-Preservation','Warrior-Fury','Priest-Shadow','Rogue-Assassination','Mage-Fire','DemonHunter-Vengeance','Paladin-Protection','Rogue-Subtlety','Paladin-Retribution','Priest-Holy','DemonHunter-Havoc','Druid-Balance','Warlock-Demonology','Evoker-Augmentation','Monk-Mistweaver','Hunter-Marksmanship','Druid-Restoration','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Protection','Hunter-BeastMastery','Evoker-Devastation','Druid-Guardian','Warrior-Arms','Monk-Windwalker',}; local provider = {region='EU',realm='Hellfire',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abréezer:BAAALAADCgYIBgAAAA==.',Ac='Acced:BAAALAAECgcIEwAAAA==.Acrylics:BAAALAAECgMIAQAAAA==.Act:BAAALAADCgUIBQAAAA==.',Ad='Adelayia:BAAALAADCggIEAABLAAECggIHgABAAggAA==.Adivoroneanu:BAAALAAECgYIBgAAAA==.',Ae='Aeden:BAAALAAECgcIEwAAAA==.',Ag='Ageman:BAAALAAECgIIAgAAAA==.',Ah='Ahmedkiing:BAAALAADCgIIAgAAAA==.',Ai='Ailoo:BAAALAAECggIBgAAAA==.Ainsooalgown:BAABLAAECoEiAAICAAgIbxUADwAhAgACAAgIbxUADwAhAgAAAA==.',Ak='Akl:BAAALAAECgEIAQAAAA==.',Al='Alfrédo:BAAALAADCggICAABLAADCggIGAADAAAAAA==.All:BAAALAAECgEIAQAAAA==.Allcoria:BAAALAADCggIEgAAAA==.Alphaeus:BAAALAADCggICAAAAA==.Alphà:BAAALAADCgcIBwAAAA==.Altheron:BAABLAAECoESAAIEAAYITRKbTACJAQAEAAYITRKbTACJAQAAAA==.Aluneth:BAAALAAECgYIBgAAAA==.',Am='Ambêrlee:BAAALAAECgIIAgAAAA==.Ameliá:BAAALAAECgYIBgAAAA==.',An='Angrathar:BAABLAAECoEUAAMFAAYItyWnBwB/AgAFAAYIIiWnBwB/AgAGAAMICyWjhQD7AAAAAA==.',As='Asmodai:BAAALAAECgMIAwAAAA==.Astallan:BAAALAAECgQIBgAAAA==.',At='Athane:BAAALAAECgYIDAAAAA==.',Au='Auch:BAAALAADCggIDwABLAADCggIEgADAAAAAA==.Aurigae:BAAALAAECgcICgABLAAECggIDwAHAOUZAA==.',Av='Avani:BAAALAAECgIIAgAAAA==.Avem:BAAALAADCggICAAAAA==.Avemcoade:BAAALAAECgMIBQAAAA==.',Az='Azarina:BAAALAADCgUIBQAAAA==.Azureion:BAAALAAECgMIBQAAAA==.Azureon:BAABLAAECoEbAAIIAAgIACDQAgDbAgAIAAgIACDQAgDbAgAAAA==.Azzy:BAAALAADCgEIAQAAAA==.',Ba='Babinéni:BAAALAADCgIIAgAAAA==.Babypriest:BAAALAAECgYIDgAAAA==.Bahamuth:BAABLAAECoEVAAIHAAcIWRdeKwDhAQAHAAcIWRdeKwDhAQAAAA==.Baki:BAAALAAECgEIAQAAAA==.Banktanten:BAAALAAECgMIAwAAAA==.Bavers:BAAALAAECgMIBAAAAA==.',Be='Bebbaa:BAAALAADCggICQAAAA==.Belagar:BAAALAADCggICAAAAA==.Belemena:BAAALAADCgMIAwABLAAECgcIEAADAAAAAA==.Bellyslammer:BAAALAADCgIIAgAAAA==.Berrybear:BAAALAAECgQICAAAAA==.Bessy:BAAALAAECgcIEAAAAA==.Bettymartin:BAAALAAECgMIBAABLAAECgQIBAADAAAAAA==.',Bh='Bhogdim:BAABLAAECoEZAAIJAAcItBTuJwDfAQAJAAcItBTuJwDfAQAAAA==.',Bi='Bigboo:BAAALAADCgcIBwAAAA==.Bigchain:BAAALAADCgIIAgAAAA==.Bigdjonhnson:BAAALAAECgUICgAAAA==.Bildros:BAAALAADCgcIDQAAAA==.Birdsnest:BAAALAAECgEIAQAAAA==.Bitbitbobs:BAAALAADCggICAAAAA==.',Bj='Björnn:BAAALAADCggIGAAAAA==.',Bl='Blackligcht:BAAALAAECgYICwAAAA==.Blickn:BAAALAADCgUIBQAAAA==.Blobbis:BAAALAADCggICAAAAA==.Bloodbarra:BAAALAAECgUICQAAAA==.Bloodcomet:BAAALAAECgYIEAAAAA==.Bloodmonk:BAAALAADCgIIAgAAAA==.Bloodteeth:BAAALAAECgEIAQABLAAECgUICAADAAAAAA==.Blue:BAAALAADCggICAAAAA==.',Bo='Borhard:BAAALAADCgMIBAAAAA==.Bowltoastie:BAABLAAECoEXAAIKAAgIZhN5HQALAgAKAAgIZhN5HQALAgAAAA==.Bowner:BAAALAAECgIIAgAAAA==.',Br='Brewtality:BAAALAADCggICAAAAA==.Brutalmind:BAAALAADCgcIDAAAAA==.Bryony:BAAALAAECgYIDQAAAA==.Brícia:BAAALAADCgUIBQAAAA==.',Bu='Busker:BAAALAAECgIIAgAAAA==.Butterface:BAAALAAECgMIBQAAAA==.',By='Bylochka:BAAALAAECgIIAgAAAA==.',Ca='Cal:BAAALAAECgYIBgABLAAFFAMICAALAGYYAA==.Caldren:BAABLAAECoEbAAMEAAgI6R7YGwCEAgAEAAgISR7YGwCEAgAMAAQIexrSBwAyAQAAAA==.Caloomsa:BAAALAAECgYIDwAAAA==.Carrottop:BAAALAAECgYICAAAAA==.Casielle:BAAALAAECgcIDgAAAA==.Castillian:BAAALAAECggIBgAAAA==.',Ce='Ceasr:BAAALAAECggICAAAAA==.Cedarra:BAAALAADCgcIEQAAAA==.Cereza:BAAALAADCggIDwAAAA==.',Ch='Chamabe:BAAALAADCgcICwAAAA==.Chizy:BAAALAADCgYIBgAAAA==.',Ci='Cicaro:BAAALAADCggIEgAAAA==.Cilly:BAAALAADCgYIBgAAAA==.',Cl='Clapmedaddy:BAAALAADCggICAABLAAECgYIDgADAAAAAA==.Claraklump:BAAALAAECgYIDQAAAA==.Clough:BAAALAAECgEIAQAAAA==.',Co='Cocacolafyns:BAAALAADCgcIBwAAAA==.Colossiux:BAAALAADCgUIBQABLAAECgUICwADAAAAAA==.Commie:BAAALAAECgYIEwAAAQ==.Companion:BAAALAAECgQIBwAAAA==.',Cr='Crazie:BAABLAAECoEgAAINAAgI5yYJAACmAwANAAgI5yYJAACmAwAAAA==.Croiman:BAABLAAECoEWAAIOAAcIoxxBCgA8AgAOAAcIoxxBCgA8AgAAAA==.Croishammy:BAAALAADCgUIBQAAAA==.Crywolf:BAAALAAECgYIDwAAAA==.',Cu='Cula:BAAALAADCgcIBwAAAA==.',Cx='Cxlder:BAACLAAFFIEIAAMLAAMIZhg+BAAPAQALAAMIfhM+BAAPAQAPAAEI7BYcCQBPAAAsAAQKgRkAAgsACAjfHrwHANcCAAsACAjfHrwHANcCAAAA.',Da='Dadhunter:BAAALAADCggICAABLAAECgMIAQADAAAAAA==.Daesu:BAABLAAECoEVAAIQAAgIUhonHgB0AgAQAAgIUhonHgB0AgAAAA==.Daizekekw:BAAALAAECgIIAgAAAA==.Dankic:BAABLAAECoEeAAIRAAgIgx8MCADkAgARAAgIgx8MCADkAgAAAA==.Darkrash:BAAALAADCggIFgABLAAECggIGwAEAOkeAA==.Dawnwielder:BAAALAAECggICwAAAA==.',De='Deadlocks:BAAALAAECggIDAAAAA==.Deadqt:BAAALAAECgYIDQAAAA==.Deathseeker:BAAALAAECgcIEQAAAA==.Deceiver:BAAALAAECgYICwAAAA==.Defiler:BAAALAADCgQIBAABLAAECgUICQADAAAAAA==.Delorean:BAAALAAECgQIBgAAAA==.Demize:BAAALAAECgUIBQAAAA==.Demonmage:BAAALAAECgYIDwAAAA==.Demonmeat:BAAALAADCgQIBAABLAAECggIGAAQAAkjAA==.Demonswithin:BAAALAAECgIIAgABLAAECggIGAAQAAkjAA==.Demtuskstho:BAAALAADCgcIEwAAAA==.Depcio:BAAALAADCggICwAAAA==.Dev:BAAALAAECgYIDwAAAA==.',Di='Diffmagus:BAABLAAECoEVAAMEAAcIqBcQMgD+AQAEAAcIqBcQMgD+AQAMAAEIvgL0FQAoAAAAAA==.Difs:BAAALAAECgUICgABLAAECgcIFQAEAKgXAA==.Disney:BAAALAADCggICAAAAA==.',Dk='Dkgreen:BAAALAADCggICQAAAA==.',Do='Dottmefunny:BAAALAAECgIIAwAAAA==.',Dr='Dracice:BAAALAAECgYIDwAAAA==.Draculaz:BAAALAAECgYICwAAAA==.Dragolkia:BAAALAADCgEIAQAAAA==.Drakemar:BAAALAAECgUIBQAAAA==.Dreadit:BAABLAAECoEcAAISAAgI8BykFAC7AgASAAgI8BykFAC7AgAAAA==.Dreptate:BAAALAAECgEIAQAAAA==.Drsnafruity:BAAALAAECgIIAgAAAA==.Druidkings:BAABLAAECoEaAAITAAgItiVKAQB1AwATAAgItiVKAQB1AwAAAA==.Drunkdog:BAAALAADCgYIBgAAAA==.Drusyk:BAAALAAECgYICwAAAA==.Dréam:BAAALAADCgEIAQAAAA==.',Dt='Dthundur:BAAALAADCgYIBgAAAA==.',Dw='Dwendor:BAAALAADCgcIBwAAAA==.',['Dø']='Dødskriger:BAAALAADCgUIBQAAAA==.',Ed='Eddà:BAABLAAECoEPAAIHAAgI5RmCGABsAgAHAAgI5RmCGABsAgAAAA==.Edixa:BAAALAADCggICQAAAA==.',Ei='Eidheann:BAABLAAECoEUAAIRAAYIiCV5DgCVAgARAAYIiCV5DgCVAgAAAA==.',El='Elwôndô:BAAALAADCgcICAAAAA==.',Er='Eriana:BAAALAAECgYIBgABLAAECgYIDQADAAAAAA==.Ericon:BAAALAADCggIFAAAAA==.Erinyès:BAAALAAECggIEwAAAA==.Eritor:BAAALAAECgUICQAAAA==.Erysipelas:BAAALAADCggICAAAAA==.',Es='Esllidan:BAAALAADCggICAAAAA==.',Et='Ethrya:BAACLAAFFIENAAIEAAUIKxvpAQDsAQAEAAUIKxvpAQDsAQAsAAQKgRgAAgQACAjAIYYaAI4CAAQACAjAIYYaAI4CAAAA.',Ev='Evelinia:BAAALAAECgYIDwAAAA==.',Ex='Excan:BAAALAAECgYIBgAAAA==.',Ey='Eyres:BAABLAAECoEaAAISAAgI2SNaBQBMAwASAAgI2SNaBQBMAwAAAA==.Eyresdk:BAAALAAECgYIBgAAAA==.',['Eî']='Eîr:BAAALAAFFAIIAgAAAA==.',Fa='Faithful:BAAALAADCgQIBAAAAA==.Farkasvadász:BAAALAAECgUIBwABLAAECgYIDAADAAAAAA==.',Fe='Feck:BAAALAAECgEIAQAAAA==.Fengari:BAAALAAECgcIDQAAAA==.Fenrè:BAAALAADCggIFQAAAA==.',Fi='Fishdip:BAAALAADCgYIBgAAAA==.',Fj='Fjandadóttir:BAABLAAECoEZAAILAAgIsR6BBwDaAgALAAgIsR6BBwDaAgAAAA==.',Fo='Forte:BAAALAADCgcIEQAAAA==.Fortolock:BAAALAAFFAIIAwAAAA==.Foxybull:BAAALAAECgMIAwAAAA==.',Fr='Frogholler:BAAALAADCgIIAgAAAA==.Frosh:BAAALAADCggIFwAAAA==.Frostbrand:BAAALAAECgMIAwAAAA==.',Fu='Fuyukaze:BAAALAAECgYIDgAAAA==.Fuzzyduck:BAABLAAECoEZAAIJAAgIURk3FgBvAgAJAAgIURk3FgBvAgAAAA==.',['Fé']='Félíx:BAAALAADCggICQABLAAECgYIFAARAIglAA==.',['Fï']='Fïnwë:BAAALAAECgYICAAAAA==.',Ga='Gaga:BAAALAAECgYICwAAAA==.Gandalarian:BAAALAADCggICAAAAA==.',Ge='Gekkonia:BAAALAAECgYIDwAAAA==.Gelle:BAACLAAFFIEIAAINAAMIjyGNAAAsAQANAAMIjyGNAAAsAQAsAAQKgRoAAg0ACAgvJUQBAE4DAA0ACAgvJUQBAE4DAAAA.Gentiana:BAAALAAECgYIDgAAAA==.Georgyana:BAAALAADCgcIEgAAAA==.',Gf='Gfn:BAABLAAECoEaAAIRAAgIIxuJEQB1AgARAAgIIxuJEQB1AgAAAA==.',Gh='Ghettosmølf:BAAALAAECggIEAAAAA==.',Gi='Giantbear:BAAALAAECgYIEQAAAA==.Gimbley:BAAALAAECggIDwAAAA==.Gipsyh:BAABLAAECoEUAAIJAAcIsw8JKwDMAQAJAAcIsw8JKwDMAQAAAA==.Gipsyy:BAAALAAECgYIDgAAAA==.',Gl='Glorywhole:BAAALAADCgcIBwAAAA==.',Gn='Gnalurg:BAAALAAECgIIAgAAAA==.',Go='Goma:BAABLAAECoEbAAISAAgIJhp4GwCCAgASAAgIJhp4GwCCAgAAAA==.Gortek:BAAALAADCgUIBQAAAA==.',Gr='Gronel:BAAALAADCggICAAAAA==.Grumpyaf:BAAALAADCgQIBAAAAA==.Grándpá:BAAALAAECggIEQAAAA==.',Gu='Guccimama:BAAALAADCggICAAAAA==.Gutten:BAAALAAECgUIBQABLAAECgcIGQAHAPUiAA==.Guttentag:BAABLAAECoEZAAMHAAcI9SKVHABJAgAHAAYIPSKVHABJAgAUAAIIUiNIRQDEAAAAAA==.',Gw='Gwinaver:BAAALAADCgQIBAAAAA==.',Ha='Halekk:BAAALAADCggICQAAAA==.Haloferret:BAAALAAECgcIBwAAAA==.Hammertimes:BAAALAADCgcIBwAAAA==.Hasufel:BAEALAAECgcIBwAAAA==.',He='Healiux:BAAALAAECgUICwAAAA==.Hellangél:BAAALAADCgcICwAAAA==.Hestiya:BAABLAAECoEZAAIVAAgIvA+VAwD8AQAVAAgIvA+VAwD8AQAAAA==.',Hi='Hihunter:BAAALAADCggIDgAAAA==.Hiyóri:BAAALAAECgYIEwAAAA==.',Ho='Holyghoat:BAAALAADCgYIBgAAAA==.Holytic:BAAALAAECgcIBgAAAA==.Hookgrip:BAAALAADCggICAAAAA==.Hork:BAAALAAECgUIBQAAAA==.Hotoman:BAAALAAECgYIBgAAAA==.Hovezina:BAAALAAECgYIDwAAAA==.',Hu='Huntacced:BAAALAADCgcIDQABLAAECgcIEwADAAAAAA==.Hunttheduck:BAAALAADCggIEAABLAAECggIGQAJAFEZAA==.',Hy='Hyperlight:BAAALAADCgcIBwAAAA==.',Id='Idonodamage:BAAALAAECgMIBgAAAA==.',Ig='Igethit:BAAALAAECgcIEwAAAA==.',Ih='Ihaterbgs:BAAALAADCgcIBwABLAAFFAMIBgASAOYdAA==.',Il='Illdarius:BAAALAADCgYIBgAAAA==.Illidaddy:BAAALAADCgMIAwABLAAECgYIDgADAAAAAA==.Illidor:BAAALAAECgYIBgAAAA==.',In='Integro:BAABLAAECoEcAAIJAAgIOhzTEgCVAgAJAAgIOhzTEgCVAgAAAA==.',Ir='Irishlock:BAAALAAFFAIIAgABLAAFFAIIBAADAAAAAA==.Irishsmile:BAAALAAECgcIBwABLAAFFAIIBAADAAAAAA==.Irishsmiley:BAAALAAFFAIIAgABLAAFFAIIBAADAAAAAA==.',Iv='Ivyskye:BAAALAADCgQIBAABLAAECgYIFAARAIglAA==.',Ja='Jadranka:BAAALAADCggICAAAAA==.Jaygarrick:BAAALAADCggICAAAAA==.Jaypally:BAABLAAECoEYAAIQAAgICSOmDQD8AgAQAAgICSOmDQD8AgAAAA==.Jayspaladin:BAAALAAECgEIAQAAAA==.',Je='Jer:BAAALAAECgIIAgAAAA==.Jett:BAAALAADCggICQABLAAECggIDwAHAOUZAA==.Jex:BAAALAAECgQIBgAAAA==.',Ji='Jinxion:BAAALAADCggICQAAAA==.',Jo='Jondo:BAAALAAECgIIAgAAAA==.Jondô:BAABLAAECoEbAAIWAAgIshDtEADLAQAWAAgIshDtEADLAQAAAA==.',Jt='Jtpal:BAAALAADCggICgAAAA==.',Ju='Judicator:BAAALAAECgQIBQAAAA==.Jurrgen:BAABLAAECoEUAAMEAAYIMSNPLQAXAgAEAAYIMSNPLQAXAgAMAAEINA/ZEgBAAAAAAA==.Juuste:BAAALAADCgcIBwAAAA==.',['Já']='Jákk:BAAALAAECggICAAAAA==.',['Jö']='Jöndö:BAAALAAECgYIBwAAAA==.',Ka='Kalestraz:BAAALAAECgYIDAAAAA==.Kamaro:BAAALAADCgcIFwAAAA==.Kamirios:BAAALAAECggIBwAAAA==.Karanthir:BAABLAAECoEWAAIXAAcIZAQxRwDzAAAXAAcIZAQxRwDzAAAAAA==.Karatelight:BAAALAAECgQIBAAAAA==.Kasummi:BAAALAADCgcIBwAAAA==.',Ke='Keelar:BAAALAAECggIEgAAAA==.Kelrian:BAAALAADCgYICAAAAA==.Kendyyd:BAAALAADCggIFwAAAA==.Ketoshu:BAAALAAECgcIDAAAAA==.',Kf='Kfcemployee:BAAALAADCgUIBQABLAAFFAMIBgASAOYdAA==.',Kh='Kharora:BAABLAAECoEYAAIYAAgIBiIRCgCdAgAYAAgIBiIRCgCdAgAAAA==.',Ki='Kigganator:BAAALAADCgcIBgAAAA==.Kilgor:BAAALAAECgcIEgAAAA==.Killant:BAAALAADCgEIAQAAAA==.',Ko='Korta:BAAALAAECgEIAgAAAA==.',Kr='Kratoc:BAAALAAECgcIDAAAAA==.Kriwan:BAAALAADCggICAAAAA==.Krokofanten:BAAALAAECgcICgAAAA==.Krámpus:BAABLAAECoEaAAISAAgITCDXEADdAgASAAgITCDXEADdAgAAAA==.',Ku='Kulcs:BAAALAAECgcIDwAAAA==.',['Kí']='Kíckazz:BAAALAADCgYIBgAAAA==.',La='Laawgiik:BAAALAAECgUICgABLAAECgYICQADAAAAAA==.Labyrinthx:BAAALAAECgYICwAAAA==.Lacodk:BAAALAADCgYIBgAAAA==.Lalisa:BAAALAADCgQIBAAAAA==.Lann:BAAALAADCggICAABLAAFFAIIAgADAAAAAA==.Lareste:BAABLAAECoEcAAIZAAgIhBUbBgBHAgAZAAgIhBUbBgBHAgAAAA==.Latexdrood:BAAALAADCgYIDAABLAAECgYIDgADAAAAAA==.Laurapalmer:BAAALAADCgcIBwAAAA==.Lawgeek:BAAALAAECgYICQAAAA==.',Le='Lebronzejamz:BAAALAADCgIIAgAAAA==.Lemiwinks:BAAALAADCggICAABLAAECgYIDwADAAAAAA==.Lerpi:BAAALAAECggIDAAAAA==.',Li='Liability:BAABLAAECoEWAAMSAAcIFiNhEgDPAgASAAcICSNhEgDPAgANAAEIGSZAMABtAAAAAA==.Liana:BAAALAADCgcIBwAAAA==.Lightbrin:BAAALAADCggIDQAAAA==.Lightsdemon:BAAALAADCgcIBwAAAA==.Lightsmash:BAAALAAECgcICAAAAA==.Lila:BAACLAAFFIEFAAIYAAMI1RtbAwAKAQAYAAMI1RtbAwAKAQAsAAQKgRcAAhgACAhtH0YMAIECABgACAhtH0YMAIECAAAA.Lilhuntress:BAAALAADCgEIAQABLAAECgYIEgADAAAAAA==.Lilleguf:BAAALAAECgIIAgABLAAFFAMICAANAI8hAA==.Lilrogie:BAAALAAECgYIEgAAAA==.Lilsadnes:BAAALAADCggIEgABLAAECgYIEgADAAAAAA==.Lilsha:BAAALAAECgYIEgAAAA==.Lilshammy:BAAALAADCggIEQABLAAECgYIEgADAAAAAA==.Lintalad:BAAALAAECgQIBgAAAA==.Liweth:BAAALAAECgYIBgAAAA==.',Ll='Llewiachawr:BAAALAADCgcIBwAAAA==.',Lo='Lockpro:BAAALAAECgMIBQAAAA==.Lollíe:BAABLAAECoEbAAIIAAgIUR/kAgDZAgAIAAgIUR/kAgDZAgAAAA==.Loomcast:BAAALAAECgIIAgABLAAECgMIAwADAAAAAA==.Loomflow:BAAALAAECgMIAwAAAA==.Lorfinas:BAAALAAECgQICAAAAA==.Loxias:BAAALAADCgYIBgAAAA==.',Lu='Lucyfur:BAAALAADCgQIBAAAAA==.Lunadin:BAAALAADCgcIDQAAAA==.Lunadina:BAAALAADCggIBwAAAA==.',Ly='Lylander:BAAALAAECggIEQAAAA==.',['Lí']='Líndor:BAAALAAECgYIDwAAAA==.',['Lù']='Lùcifér:BAAALAADCggICAAAAA==.Lùcîfer:BAACLAAFFIEGAAISAAMItRJ6BwD8AAASAAMItRJ6BwD8AAAsAAQKgR4AAhIACAiqIawPAOYCABIACAiqIawPAOYCAAAA.',Ma='Magehuh:BAAALAAECggICAAAAA==.Magicrap:BAAALAADCggICAAAAA==.Malcine:BAAALAAECgYIDAAAAA==.Malore:BAEALAADCggIEAABLAAFFAMIBgAKAMcRAQ==.Manife:BAAALAADCggIGQAAAA==.Mantinel:BAAALAAECgYIDwAAAA==.Matik:BAAALAAECggICAAAAA==.Matiks:BAAALAAECggIEAAAAA==.Maximous:BAAALAAECgYICgAAAA==.',Mc='Mcdzynek:BAAALAADCggIFQAAAA==.Mcpointy:BAAALAAECgYIDAAAAA==.',Me='Mealone:BAAALAAECgMIBAAAAA==.Meatbone:BAAALAAECgMIBgAAAA==.Meateor:BAAALAAECgUIBgABLAAECggIGAAQAAkjAA==.Meatyy:BAAALAAECgYIDAAAAA==.Melarissa:BAAALAAECgEIAQAAAA==.Memphistoo:BAAALAADCgcIBwAAAA==.Mentosbreath:BAAALAADCgEIAQAAAA==.Merah:BAAALAADCggIDwAAAA==.Mercbeste:BAABLAAFFIEGAAIaAAMI3gQ/CwCxAAAaAAMI3gQ/CwCxAAAAAA==.Meritus:BAAALAADCgYIBgAAAA==.Methuselah:BAAALAAECgIIAgAAAA==.Meírelth:BAABLAAECoEWAAIbAAcIahENEACOAQAbAAcIahENEACOAQAAAA==.',Mi='Michaël:BAAALAADCggICAAAAA==.Mickeyolsen:BAAALAADCgcIBwAAAA==.Midge:BAAALAADCggICQAAAA==.Milkybarboom:BAAALAADCgcIBwAAAA==.Milkybardrac:BAAALAAECgMIAwAAAA==.Milkybarsham:BAAALAAECgQIBAAAAA==.Mimyy:BAAALAADCggIDgAAAA==.Mind:BAAALAAECggIDAAAAA==.Mindachuwu:BAAALAAECgYIEAAAAA==.Mirador:BAAALAAECgMIBgAAAA==.',Mj='Mjstcmedusa:BAAALAAECgEIAQAAAA==.',Mo='Moderna:BAAALAAECggICAAAAA==.Moerath:BAAALAAECgMIAwAAAA==.Monarchlay:BAAALAAECgYICwAAAA==.Monsoto:BAAALAADCgUIBQABLAAFFAMICQARALkTAA==.Monti:BAAALAAECgYIEQAAAA==.Mooviestar:BAAALAAECgYIBwAAAA==.Morene:BAAALAAECgYIEgAAAA==.Morgaroth:BAAALAADCgUIBAABLAAECgYICwADAAAAAA==.Morsee:BAAALAADCggICQAAAA==.Morsey:BAABLAAECoEcAAIcAAgIQBzyCQB6AgAcAAgIQBzyCQB6AgAAAA==.',Mu='Mumm:BAAALAADCgcIEQAAAA==.Musicar:BAAALAADCggICAABLAAECgYIDwADAAAAAA==.Muzzleflash:BAAALAAECgEIAQAAAA==.',Mz='Mzerohero:BAAALAAECgYIDgAAAA==.',['Má']='Máe:BAAALAADCggIEAABLAAECgYICgADAAAAAA==.Mágni:BAAALAAECggICAAAAA==.',Na='Naif:BAABLAAECoEUAAIXAAgITxgvFQBHAgAXAAgITxgvFQBHAgAAAA==.Najo:BAAALAAECgQIBwAAAA==.Nalewar:BAAALAAECgcIEQAAAA==.Naranna:BAAALAAECgMIBQAAAA==.Narutó:BAAALAADCggICAAAAA==.Nastel:BAAALAAECgUIBwAAAA==.Nastie:BAABLAAECoEeAAQBAAgICCC6DQBIAgABAAcIwx+6DQBIAgAEAAYIoh12MwD3AQAMAAIInxAYDQB2AAAAAA==.Nattyhunt:BAAALAADCgQIBAABLAAECgQIBQADAAAAAA==.Nattyprot:BAAALAAECgQIBQAAAA==.Nauti:BAAALAADCggICAAAAA==.Nautis:BAAALAAECgYIEAAAAA==.',Ne='Necrotixx:BAAALAADCggICAABLAAECggIGQAVALwPAA==.Nelagoma:BAABLAAECoEWAAIKAAcIExpNGQAxAgAKAAcIExpNGQAxAgAAAA==.Nerif:BAAALAADCgYIAwAAAA==.Neuega:BAAALAADCgMIAwAAAA==.Neueqa:BAABLAAECoEZAAIGAAgIsx6IEwDAAgAGAAgIsx6IEwDAAgAAAA==.Nevergonnagi:BAAALAAECgIIAgAAAA==.Newjeans:BAAALAADCgMIAwAAAA==.',Ni='Niniver:BAAALAAECgYIEAAAAA==.Nivie:BAAALAADCggICAAAAA==.',Nj='Njb:BAAALAADCgEIAQAAAA==.',No='Noaidi:BAAALAAECgYIDwAAAA==.Norah:BAAALAAFFAMIAwABLAAFFAMIBQAYANUbAA==.Noskill:BAAALAADCgEIAQAAAA==.Notvulpera:BAAALAAECgUIBwAAAA==.Novafire:BAAALAADCgcIBwAAAA==.',Nt='Ntmonkey:BAAALAADCggICgAAAA==.',Nu='Nullrop:BAAALAADCgcIBwABLAAECgUICQADAAAAAA==.',Ny='Nyil:BAAALAAECgYIEAAAAA==.Nykona:BAAALAAECgEIAQAAAA==.Nykonapala:BAAALAADCggICAAAAA==.Nyme:BAAALAAECgQIBAAAAA==.Nymerios:BAAALAADCgYIDAAAAA==.Nypheliá:BAAALAADCgcICAAAAA==.Nyxxara:BAAALAADCgEIAQAAAA==.',['Ní']='Nícole:BAAALAADCgQIBAABLAAECgYIFAARAIglAA==.',['Nø']='Nøxus:BAAALAAECgYICgAAAA==.',Ob='Obfuscate:BAAALAADCgcIDgAAAA==.',Oc='Ochala:BAAALAADCgYIBgAAAA==.',Oh='Ohholysmeck:BAAALAADCgcIEQAAAA==.',Op='Oplight:BAAALAADCgUICQAAAA==.',Pa='Palajan:BAAALAADCgQIBAAAAA==.Pandaspally:BAABLAAECoEbAAICAAcIURyiCwBLAgACAAcIURyiCwBLAgAAAA==.Patrickstar:BAAALAAECgcIDQAAAA==.Patt:BAAALAAECgUIBwAAAA==.',Pe='Pepelepew:BAAALAADCgUIBQAAAA==.Perszephoné:BAAALAADCgIIAgAAAA==.Pestilencë:BAAALAAECgYICwAAAA==.Peter:BAABLAAECoEVAAIQAAcISyBqIABlAgAQAAcISyBqIABlAgAAAA==.',Ph='Phage:BAAALAADCgEIAQAAAA==.Phelicia:BAAALAAECgQIBAABLAAECgYIDQADAAAAAA==.Phestus:BAAALAADCggICAAAAA==.Phrall:BAAALAADCgYICAAAAA==.Phyinxx:BAAALAADCgEIAQABLAADCggICAADAAAAAA==.Phynx:BAAALAADCgUIBQABLAADCggICAADAAAAAA==.Phynxx:BAAALAADCggICAAAAA==.',Pi='Pigidiwone:BAAALAAECgIIAgAAAA==.Pinkpepper:BAAALAADCggICgAAAA==.Piri:BAAALAAECgMIBQAAAA==.',Pl='Plex:BAAALAAECgYICgAAAA==.',Po='Pohroma:BAAALAAECgYIDwAAAA==.Poisoned:BAAALAAECgQIBAAAAA==.Polistarte:BAAALAAECgYIBgAAAA==.Potvora:BAAALAAECgYIDgAAAA==.',Pr='Predar:BAAALAAECgMIAwAAAA==.Pretani:BAAALAAECgEIAQAAAA==.Priestiitute:BAAALAADCggICAABLAAECgcIDwADAAAAAA==.Procers:BAAALAAECgUIBQAAAA==.Proudlee:BAAALAAECgYIDAAAAA==.Proér:BAAALAADCggICAABLAAECgUICQADAAAAAA==.',Pu='Pufariga:BAAALAADCggICAAAAA==.Puthealzhere:BAAALAAECgYIEAAAAA==.',Py='Pytka:BAAALAADCgYIEAAAAA==.',Qu='Quirons:BAAALAAECgYIDwAAAA==.',Qy='Qyra:BAAALAADCggICAAAAA==.',Ra='Ralif:BAAALAAECgUIBQAAAA==.Rayme:BAAALAAECgYIDQAAAA==.',Re='Realhot:BAAALAAECggIBgAAAA==.Realorc:BAABLAAECoEfAAIJAAgI8iKfBQA2AwAJAAgI8iKfBQA2AwAAAA==.Reinknight:BAAALAAECgYIEwAAAA==.Rejepi:BAAALAAECgYIDQAAAA==.Rerolling:BAAALAAECgMIAwAAAA==.Retox:BAAALAAECgMIAwAAAA==.Rezemaw:BAAALAAECgYIDQAAAA==.',Rh='Rháenys:BAAALAAECgYIBgAAAA==.',Ri='Riador:BAAALAADCgYIBgAAAA==.Riekteran:BAAALAADCgEIAQAAAA==.Ringmuncher:BAAALAADCgcIBwAAAA==.Rirjage:BAAALAAECgUICAAAAA==.',Ro='Rosedewh:BAAALAADCggIEAAAAA==.Roveine:BAAALAADCgYIBgAAAA==.',Ru='Rule:BAAALAAECgcIDAAAAA==.Rundulf:BAAALAAECgQICAAAAA==.Ruuhpriest:BAAALAAECgcIDAAAAA==.',Ry='Ryba:BAAALAADCgcIBwAAAA==.',['Rí']='Rízy:BAAALAADCggICAAAAA==.',Sa='Saburex:BAAALAAECgYIEwAAAA==.Saelwan:BAAALAADCggIDAAAAA==.Saffié:BAAALAADCggICAAAAA==.Sagemblack:BAABLAAECoEVAAIQAAcIXCQ1DwDtAgAQAAcIXCQ1DwDtAgAAAA==.Salora:BAECLAAFFIEGAAIKAAMIxxFNBgDwAAAKAAMIxxFNBgDwAAAsAAQKgR8AAwoACAhYIKAJAOwCAAoACAhYIKAJAOwCABEAAQj2FsFwAEMAAAAA.Saranac:BAAALAAECggICwAAAA==.Sark:BAAALAADCgcICgAAAA==.Sarry:BAAALAADCggICAAAAA==.',Se='Sebdude:BAAALAAECgcIDQAAAA==.Seline:BAAALAAECgYIEgAAAA==.Selyanna:BAAALAADCgcIBwAAAA==.Serleia:BAAALAADCgQIBAAAAA==.Serpine:BAAALAAECgQIBgAAAA==.',Sh='Shadeness:BAAALAAECgcIDgAAAA==.Shadowglaive:BAAALAAECgYIBgAAAA==.Shadowplays:BAAALAAECgYIEwAAAA==.Shamelee:BAAALAAECgEIAQABLAAECgYIDAADAAAAAA==.Shendao:BAAALAAECgUICAAAAA==.',Si='Siennè:BAAALAADCggIFwABLAAECgcIEAADAAAAAA==.Sinistra:BAAALAADCgcIBwAAAA==.Siuu:BAAALAADCggICAAAAA==.',Sk='Skaype:BAAALAAECgQIBAAAAA==.Skivesnulle:BAACLAAFFIEGAAISAAMI5h23BQAQAQASAAMI5h23BQAQAQAsAAQKgR0AAhIACAiFJhcBAIQDABIACAiFJhcBAIQDAAAA.',Sl='Slimjimmy:BAAALAAECgYICgAAAA==.',Sm='Smileyirish:BAAALAAFFAIIBAAAAA==.',Sn='Snoópdogg:BAAALAADCgEIAQAAAA==.Snusdog:BAAALAAFFAIIAgAAAA==.',So='Somberlane:BAACLAAFFIEGAAIRAAII3RhgDQCzAAARAAII3RhgDQCzAAAsAAQKgR0AAhEACAjhIMQIANoCABEACAjhIMQIANoCAAAA.Sompaladin:BAAALAAECgYIDwAAAA==.Sophine:BAAALAAECgMIAwAAAA==.Soulsdk:BAAALAADCggICAAAAA==.Soulslotty:BAAALAAECgcIDAAAAA==.',Sp='Spankymcgee:BAAALAAECgYICQAAAA==.Sparky:BAAALAAECgYIDgAAAA==.Spazdh:BAAALAAECgYIDQAAAA==.Spinalhunter:BAAALAADCggICAAAAA==.Sploosh:BAAALAAFFAIIAgAAAA==.Spongebobman:BAAALAAECgcIBwAAAA==.Spuffy:BAAALAAECgEIAgAAAA==.',Sr='Srymisotired:BAAALAADCggIDgAAAA==.',St='Staniel:BAAALAAECgYIBgAAAA==.Steku:BAAALAADCggICAAAAA==.Stinglikebee:BAAALAADCggICAAAAA==.Storolf:BAAALAADCgQIBAAAAA==.Streimbol:BAAALAADCgYIBgAAAA==.Striixxzzy:BAAALAADCgYIBgAAAA==.Stáry:BAAALAAECgQIBQAAAA==.Stãry:BAAALAADCggICAAAAA==.',Su='Subz:BAAALAAECgYIEwAAAA==.Sunstreakér:BAABLAAECoEaAAIdAAgIWR+iDADZAgAdAAgIWR+iDADZAgAAAA==.Survivor:BAAALAADCggIGAABLAAECggIIgAYAHcdAA==.Suunto:BAAALAAECgEIAQABLAAECgcIEwADAAAAAA==.',Sw='Sweedydk:BAAALAAECgYIDwAAAA==.Sween:BAAALAADCgUIBQAAAA==.Switchdk:BAAALAADCgcIBwABLAAECggIHQAQADImAA==.Switchl:BAABLAAECoEdAAIQAAgIMiZhAQCDAwAQAAgIMiZhAQCDAwAAAA==.',Sy='Syhrfel:BAAALAADCgcIEQAAAA==.Sylher:BAAALAAECgIIBgAAAA==.Sylonis:BAAALAADCgIIAgAAAA==.Sylpha:BAAALAADCgQIBAAAAA==.Syléha:BAAALAAECgQIBwAAAA==.',Sz='Szattyán:BAAALAAECgcIEwAAAA==.Szikla:BAAALAAECgYIBgAAAA==.',Ta='Tadgheals:BAAALAAECgYICQAAAA==.Tagrenam:BAAALAADCgIIAgAAAA==.Taktotak:BAABLAAECoEaAAILAAgIuiLtAgAwAwALAAgIuiLtAgAwAwAAAA==.Tarenis:BAAALAAECgcIEQAAAA==.Tarmac:BAAALAADCggICgAAAA==.Tartascon:BAAALAADCgYIBgAAAA==.',Tb='Tbee:BAAALAAECgMIAwAAAA==.',Te='Teaflower:BAAALAADCgcIEwAAAA==.Terrorblyat:BAAALAADCgUIBQAAAA==.',Th='Thassarian:BAAALAAECgcIEwAAAA==.Thebear:BAAALAAECgYIDgAAAA==.Thediejee:BAABLAAECoEeAAIeAAgIER+IDQB/AgAeAAgIER+IDQB/AgAAAA==.Themuffinman:BAAALAADCgcIBwAAAA==.Thewretched:BAAALAADCggICAAAAA==.',Ti='Timmeh:BAAALAADCggICAAAAA==.Tinytwototem:BAAALAAECgcICgAAAA==.',To='Tonykal:BAAALAADCgIIAgAAAA==.Toperr:BAAALAAECgYIBwAAAA==.Topraider:BAAALAAECgMIAwABLAAECgUICQADAAAAAA==.Tortus:BAAALAADCggICAABLAAECgYIDAADAAAAAA==.',Tr='Tralion:BAAALAADCgcIBwAAAA==.Tre:BAAALAADCgcICwAAAA==.Tritan:BAAALAADCgcIBwAAAA==.Trotylmix:BAAALAADCgcIBwAAAA==.',Tw='Twobae:BAAALAADCggIDQAAAA==.',Ty='Tyrannic:BAAALAADCggIDQAAAA==.',['Tø']='Tøs:BAAALAADCggIEAABLAAECgYIDgADAAAAAA==.',Un='Undskyldmig:BAAALAADCgcIBwAAAA==.Unibobus:BAAALAAECgcIEQAAAA==.',Us='User:BAAALAADCgcIBwAAAA==.',Va='Vall:BAAALAADCggIBQAAAA==.Vampiremommy:BAAALAAECgMIAwAAAA==.Varanus:BAABLAAECoEdAAIFAAgI7CTLAABjAwAFAAgI7CTLAABjAwAAAA==.Variva:BAABLAAECoEWAAILAAcIiCMqCADRAgALAAcIiCMqCADRAgAAAA==.Vascy:BAABLAAECoEiAAQYAAgIdx11DAB/AgAYAAgIdx11DAB/AgATAAUIRQRARgDHAAAfAAIIagiIGQBGAAAAAA==.Vaun:BAAALAADCgcIBwAAAA==.Vazez:BAAALAAECgYIEgAAAA==.',Ve='Velannara:BAABLAAECoEWAAIBAAgIrxEuFwDfAQABAAgIrxEuFwDfAQAAAA==.Velawyn:BAAALAAECgMIAwABLAAFFAMIBQAYANUbAA==.Velrias:BAAALAAECgYICwAAAA==.Venelat:BAAALAAECgIIAgAAAA==.Venous:BAAALAAECgMIAwAAAA==.Ventriss:BAAALAAECgMIAwABLAAECgcIDwADAAAAAA==.Verendus:BAAALAAECgEIAQABLAAECgYIEwADAAAAAQ==.Veriduca:BAAALAADCgQIAgAAAA==.Vertz:BAAALAAECgYIDAAAAA==.Vertzz:BAAALAADCggIAwAAAA==.',Vi='Vilderolf:BAAALAADCgcIBwAAAA==.Vinart:BAAALAADCggICQAAAA==.',Vl='Vladavid:BAAALAADCgQIBAAAAA==.',Wa='Warfog:BAAALAAECgYIDwAAAA==.Warlochita:BAAALAADCgYIBgAAAA==.Warrjan:BAABLAAECoEVAAIgAAcISyQaAgDaAgAgAAcISyQaAgDaAgAAAA==.Warwini:BAAALAADCgcIDAAAAA==.',We='Weissmüller:BAAALAAECgYICgAAAA==.Weoweo:BAAALAAECgYIDAAAAA==.Werex:BAAALAAECgYICgAAAA==.',Wi='Wickfish:BAAALAAECgYIDAAAAA==.Wimani:BAAALAAECggIDAAAAA==.Wizlól:BAAALAAECgYIDAAAAA==.',Wl='Wlind:BAAALAAECgYIDgAAAA==.',Wy='Wyndorf:BAABLAAECoEUAAIdAAcI+B34GQBaAgAdAAcI+B34GQBaAgAAAA==.Wynshock:BAAALAADCggIDAAAAA==.Wynwarr:BAAALAADCggICAAAAA==.',Xa='Xalandori:BAAALAAECgEIAQAAAA==.Xaldar:BAAALAAECgUIDwAAAA==.Xanas:BAAALAAECgYIDQAAAA==.Xandori:BAAALAAECgYIDwAAAA==.Xariv:BAAALAAECgYICAAAAA==.Xarro:BAACLAAFFIEJAAIRAAMIuRPdBgD8AAARAAMIuRPdBgD8AAAsAAQKgSAAAhEACAi0HJ0QAH4CABEACAi0HJ0QAH4CAAAA.',Xe='Xevir:BAAALAAECgYIBgAAAA==.',Xo='Xoor:BAAALAADCgcIDAAAAA==.',Xy='Xykhors:BAAALAADCgEIAQAAAA==.',Ya='Yama:BAAALAADCgMIAgAAAA==.Yayaker:BAAALAAECgYIAwAAAA==.',Ye='Yewneh:BAAALAAECgYIDwAAAA==.',Yn='Ynkm:BAAALAADCggIBAAAAA==.',Yo='Yodaa:BAABLAAECoEbAAIhAAgITiHuAwAUAwAhAAgITiHuAwAUAwAAAA==.',Za='Zarui:BAAALAADCgcIBwAAAA==.',Ze='Zeals:BAAALAAECgMIBAAAAA==.Zecele:BAAALAADCgYIBgABLAAECgUICQADAAAAAA==.Zerkar:BAAALAAECgYIEAAAAA==.',Zi='Ziek:BAAALAADCgQIBAAAAA==.Zienne:BAAALAAECgcIEAAAAA==.',Zo='Zorake:BAAALAADCgQIBAAAAA==.',['Ár']='Áranea:BAAALAADCgYICQAAAA==.',['Æt']='Æthelwulf:BAAALAAECgUIBQAAAA==.',['Ée']='Éeviill:BAABLAAECoEXAAIeAAcIdyEiDACWAgAeAAcIdyEiDACWAgAAAA==.',['Ír']='Íronhíde:BAAALAADCgEIAQABLAAECgYICgADAAAAAA==.',['Ïc']='Ïcyhot:BAAALAADCggIFwAAAA==.',['Ðj']='Ðjall:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end