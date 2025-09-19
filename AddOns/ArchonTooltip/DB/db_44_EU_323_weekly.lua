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
 local lookup = {'Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Evoker-Devastation','Priest-Shadow','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Monk-Mistweaver','Warrior-Protection','Priest-Holy','Shaman-Elemental','Mage-Fire','Priest-Discipline','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Restoration','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','DeathKnight-Blood',}; local provider = {region='EU',realm='Runetotem',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Achlyss:BAAALAAECggICQAAAA==.Acornius:BAAALAADCgUIBQAAAA==.',Ad='Adrastos:BAAALAADCgQIBAAAAA==.',Ae='Aerandir:BAAALAADCgYIBgAAAA==.',Aj='Ajira:BAAALAADCggIFQAAAA==.',Al='Aladruid:BAAALAAECgMIAwAAAA==.Aledra:BAAALAADCgcIBwAAAA==.Alfdis:BAAALAADCggIBwAAAA==.Allidár:BAAALAAECgQIBAAAAA==.Alrock:BAAALAADCgQIBAAAAA==.',Am='Amanily:BAABLAAECoEcAAMBAAgIchkVFgBxAgABAAgIchkVFgBxAgACAAII6xERHABwAAAAAA==.Amis:BAABLAAECoEZAAIDAAgIuh2cEwDDAgADAAgIuh2cEwDDAgAAAA==.',An='Anisha:BAAALAADCgQIAQABLAAECggIDwAEAAAAAA==.Anumet:BAAALAADCggIGgAAAA==.',Ar='Arcanál:BAAALAAECgMIAwAAAA==.Aro:BAAALAAECgYIEgAAAA==.',As='Asurian:BAAALAAECgYIBgAAAA==.',Au='Audentia:BAAALAADCgcIBwAAAA==.',Av='Avocadoo:BAAALAADCgYIBgAAAA==.',Ay='Ayori:BAAALAADCgcIBwAAAA==.Ayy:BAACLAAFFIEIAAMFAAMIkiZvBQDnAAAFAAIIlCZvBQDnAAAGAAEIjCb2BgBzAAAsAAQKgR8AAwYACAidJhAAAJMDAAYACAhhJhAAAJMDAAUACAh3Jf8BAEUDAAAA.',Az='Azbogah:BAAALAADCggIEAABLAAECgYIDAAEAAAAAA==.Azun:BAAALAADCgcICQAAAA==.',Ba='Baani:BAAALAADCggIHAAAAA==.Babski:BAAALAADCgYIBgAAAA==.Bacovia:BAAALAAECgEIAQAAAA==.Bananabread:BAAALAADCgcIBwAAAA==.Baniin:BAAALAADCgQIBgAAAA==.Barnetv:BAAALAAECggICAAAAA==.',Be='Bearly:BAAALAAECgcIDQAAAA==.Benafflic:BAAALAADCggIBwAAAA==.Bendover:BAAALAADCggIDAAAAA==.Bergur:BAABLAAECoEUAAIHAAcInh4EIQBiAgAHAAcInh4EIQBiAgAAAA==.Berhar:BAAALAADCgMIAwAAAA==.',Bi='Bifor:BAAALAADCgMIAwAAAA==.Bigibono:BAAALAAECggICwAAAA==.Biz:BAAALAAECgEIAQAAAA==.',Bl='Blackweaver:BAAALAADCgUICAAAAA==.Blazko:BAAALAAECgQIBgAAAA==.Blinkyflaps:BAAALAAECgcIDQAAAA==.',Bo='Bobrockss:BAAALAAECgYIBwAAAA==.Boints:BAAALAADCggICAAAAA==.Boogíe:BAAALAADCgUIBQAAAA==.Booly:BAAALAADCggIEAABLAAECgcIDQAEAAAAAQ==.',Br='Branch:BAAALAADCgcIBwAAAA==.Brauer:BAEALAAECgYIEQAAAA==.Brewsle:BAAALAAECgYIBwAAAA==.Brewzea:BAAALAAECgUICgAAAA==.',Bz='Bzerk:BAAALAAECggICgABLAAECgUICgAEAAAAAA==.',['Bé']='Béndover:BAAALAADCgUIBQAAAA==.',Ca='Calisea:BAAALAADCggICAAAAA==.Carmine:BAAALAADCgMIAwAAAA==.Caviar:BAAALAAECgUIBQAAAA==.',Ce='Ceret:BAAALAAECgYICwAAAA==.',Ch='Chetu:BAAALAADCgYIBgAAAA==.Chianna:BAAALAADCggIFgAAAA==.Chisdk:BAAALAADCgcIDgAAAA==.Chocolate:BAAALAAECgcIDgAAAA==.Chrissassin:BAAALAAECgQICQAAAA==.Chunckgt:BAAALAAECgUICwAAAA==.',Ci='Cindergore:BAAALAAECgYIBgAAAA==.Ciresika:BAAALAADCgYIBgAAAA==.',Co='Coldstuff:BAAALAAECgYIEgAAAA==.Comar:BAAALAAECgYIEgAAAA==.Coolbreezer:BAEALAADCgcIBwABLAAECgYIEQAEAAAAAA==.',Cr='Croon:BAAALAAECgIIAgAAAA==.',Cy='Cyn:BAAALAADCgUICAAAAA==.Cyphor:BAAALAADCgcIHwAAAA==.Cyrasil:BAAALAADCggICwABLAAECgIIAwAEAAAAAA==.',Da='Dallerion:BAAALAADCgYIBgAAAA==.Danisha:BAAALAAECgMIBgAAAA==.Darkryu:BAAALAAECgEIAQAAAA==.',De='Delimina:BAAALAAECgIIAgAAAA==.Demonhunter:BAAALAAECgMIAQAAAA==.Demoninside:BAABLAAECoEbAAQIAAgIHBuiFACOAgAIAAgIHBuiFACOAgAJAAQIDhZVPAD3AAAKAAEIqxMgLQBMAAAAAA==.Demonoctris:BAAALAADCgUIBQAAAA==.Dentydh:BAAALAADCgIIAgABLAAECggIAgAEAAAAAA==.Deusbelli:BAAALAADCggICAAAAA==.',Di='Diblo:BAAALAADCggICwAAAA==.',Dj='Djasper:BAAALAADCgcIEwABLAAECgcIGAALACwbAA==.',Do='Donius:BAAALAAECgcIEQAAAA==.Dontexist:BAAALAAECgMIAwAAAA==.',Dr='Drav:BAABLAAECoEVAAQIAAgIhyKICwDrAgAIAAgICCKICwDrAgAKAAUIYiN6CQDaAQAJAAEI2x4GXABWAAAAAA==.Drgndeeznuts:BAABLAAECoEcAAIMAAgI3iS7AQBcAwAMAAgI3iS7AQBcAwAAAA==.Drogkala:BAAALAADCgcIDQAAAA==.Drélmordah:BAAALAAECgcIBwAAAA==.',Du='Duckmuncher:BAAALAADCggICAAAAA==.Dutchiedemon:BAABLAAECoEVAAIDAAgIRxHaMAAEAgADAAgIRxHaMAAEAgAAAA==.',Ea='Earlhero:BAAALAAECgYICAAAAA==.',Eb='Ebani:BAAALAADCgYIBgAAAA==.',Ed='Edgy:BAAALAADCggICAAAAA==.',El='Eleanorah:BAAALAADCggIDwAAAA==.Electroboy:BAAALAAECgYICwAAAA==.',Em='Emistrasza:BAAALAADCggICAAAAA==.Emmitatress:BAAALAADCgYIBgABLAAECgYIDQAEAAAAAA==.Emmophilist:BAAALAADCggIHwAAAA==.Emméline:BAAALAAECgYIDQAAAA==.Emphasis:BAAALAADCgUICgAAAA==.',En='Enrie:BAAALAADCgIIAgAAAA==.Entillani:BAAALAADCgcIBwAAAA==.',Eo='Eomer:BAAALAAECgYIEgAAAA==.',Et='Ethelfleda:BAAALAADCgQIBAAAAA==.',Ex='Excathedra:BAAALAAECgMIBAAAAA==.Exodarious:BAAALAAECggIBgAAAA==.',Fa='Falli:BAAALAADCggICAAAAA==.Farty:BAAALAAECgMIAwAAAA==.',Fe='Felmiracle:BAACLAAFFIEIAAIDAAMI9xquBAAhAQADAAMI9xquBAAhAQAsAAQKgR8AAgMACAgsJcUCAGoDAAMACAgsJcUCAGoDAAAA.Felscourge:BAABLAAECoEbAAIDAAgIVxg1IABgAgADAAgIVxg1IABgAgAAAA==.',Fl='Flett:BAAALAAECgYICQAAAA==.',Fu='Fumanchu:BAAALAADCgQIBAAAAA==.',Ge='Gefeltafish:BAABLAAECoEVAAINAAgIJRgPGwAgAgANAAgIJRgPGwAgAgAAAA==.',Gi='Giezer:BAAALAAECggICQAAAA==.',Go='Golbríng:BAAALAAECgUIBgAAAA==.Gordzgrey:BAAALAAECgYIDAAAAA==.Goshunt:BAABLAAECoEXAAIOAAcILBs3GQAeAgAOAAcILBs3GQAeAgAAAA==.',Gr='Granithe:BAAALAADCgYIAQAAAA==.Grasgon:BAAALAAECgYIEgAAAA==.Greensausage:BAAALAAECgcIEwAAAA==.Grotz:BAAALAAECgYICQAAAA==.',Gu='Gulkaren:BAAALAAECgYICwAAAA==.',Ha='Hamdomri:BAAALAADCgMIAwAAAA==.',He='Heavenhealer:BAAALAADCgYIBgAAAA==.Hexual:BAAALAAECgYICQAAAA==.',Hi='Hiela:BAAALAAECgQIBgAAAA==.Hilmoon:BAAALAADCgcIBwAAAA==.',Hu='Huginnmuninn:BAAALAAECgMICwAAAA==.Hunkilii:BAAALAADCgIIAgAAAA==.Hunterboots:BAAALAAECgUICQAAAA==.Hutta:BAAALAAECgYIDgAAAA==.',Hy='Hyacinth:BAABLAAECoEdAAMPAAgIKCPhAgAyAwAPAAgIKCPhAgAyAwAQAAEISAP5mQAyAAAAAA==.',Ic='Icewind:BAAALAAECgUIBwAAAA==.',Il='Ildiko:BAAALAAECgYICgAAAA==.',In='Innz:BAAALAADCgQIBAAAAA==.Inubis:BAAALAAECgYIBgAAAA==.',Ja='Jacobroed:BAAALAAECgYIBwAAAA==.',Je='Jemmox:BAAALAADCggICAAAAA==.',Jj='Jjholy:BAAALAAECgYIBAAAAA==.',Jo='Joeexotic:BAAALAAECgQIBgAAAA==.Johana:BAAALAADCgUIBQAAAA==.Johnnerzul:BAAALAADCggICAAAAA==.',Ju='Judgerinder:BAAALAADCgYIBgABLAAECgQIBgAEAAAAAA==.Jullice:BAABLAAECoEWAAIRAAcIeQzEGQBNAQARAAcIeQzEGQBNAQAAAA==.Justicemercy:BAAALAADCgcIEQAAAA==.',Jw='Jwéel:BAAALAAECgMIAwAAAA==.',Ka='Kackobacko:BAAALAADCggIEgAAAA==.Kadath:BAAALAAECgYIDwAAAA==.Karakun:BAAALAADCggIFgABLAAECgYIDAAEAAAAAA==.Karamb:BAAALAADCgQIAgAAAA==.Karanda:BAAALAADCgIIAgAAAA==.Karenblixen:BAAALAADCgYICAAAAA==.Karn:BAAALAADCgcICgAAAA==.Kaytam:BAAALAADCgQIBAAAAA==.',Ki='Kinkyrasta:BAAALAAECggICAAAAA==.Kitlord:BAAALAADCgcIBwAAAA==.',Kl='Klooas:BAABLAAFFIEIAAISAAMI6hnGAgABAQASAAMI6hnGAgABAQAAAA==.',Kn='Kneel:BAAALAAECgMIAwAAAA==.Knuppel:BAAALAAECgYIBgAAAA==.Knuppelster:BAAALAAECgQIBgABLAAECgYIBgAEAAAAAA==.Knurf:BAAALAADCgQIBAAAAA==.',Kr='Krissz:BAAALAAECggIAgAAAA==.Kroellboell:BAAALAADCgYICwAAAA==.Kråka:BAAALAADCggIFwAAAA==.',La='Lahn:BAAALAAECgYIDwAAAA==.Lat:BAABLAAECoEYAAILAAcILBuiKQA1AgALAAcILBuiKQA1AgAAAA==.',Le='Lehuge:BAAALAADCgUIBQAAAA==.Lemonparty:BAAALAADCgIIAgABLAADCgUICgAEAAAAAA==.Lemuria:BAAALAAECgYICQAAAA==.',Li='Liandrah:BAABLAAECoEWAAMQAAcI+BFPPgDEAQAQAAcI+BFPPgDEAQAPAAMI2QS4RwCCAAAAAA==.Linflas:BAAALAADCggIEgAAAA==.Litzi:BAABLAAECoEdAAITAAgIbBfMFwA+AgATAAgIbBfMFwA+AgAAAA==.',Lo='Lockias:BAAALAADCgQIBAAAAA==.Lorran:BAAALAAECgcICAAAAA==.',Lu='Luffy:BAAALAAECgMIBwAAAA==.Luvi:BAAALAADCgcIBwAAAA==.',Lv='Lvs:BAAALAAECgYICwAAAA==.',Ly='Lyns:BAABLAAECoEUAAIUAAYIRSDFGwAzAgAUAAYIRSDFGwAzAgAAAA==.',Ma='Macallan:BAAALAAECgYIAgAAAA==.Maddock:BAAALAADCggICAAAAA==.Madeleine:BAAALAAECgUIBQAAAA==.Madkard:BAAALAADCgYIBgAAAA==.Madlokk:BAAALAADCggIEgAAAA==.Madmardigan:BAAALAADCgcIBwAAAA==.Magickaren:BAACLAAFFIEGAAMVAAMI8xxYAAAyAQAVAAMI8xxYAAAyAQAQAAIIqw0VFwCjAAAsAAQKgRsAAxUACAg4IX8AADEDABUACAg4IX8AADEDABAABghDFnZWAGEBAAAA.Mark:BAAALAADCgUICQAAAA==.Maulers:BAAALAAECgUICAAAAA==.Maz:BAAALAAFFAIIAgABLAAFFAMIBwAUAJglAA==.',Me='Method:BAAALAADCggIEAAAAA==.Metot:BAAALAAECgYICgAAAA==.',Mi='Milochan:BAAALAADCgUIBQAAAA==.',Mo='Moia:BAAALAADCgcIDAAAAA==.Mommy:BAAALAADCgcICAAAAA==.Monkarina:BAAALAAECgYICQAAAA==.Monsterenerg:BAAALAADCgIIAgABLAAECggIGwADAFcYAA==.Moogul:BAAALAAECgEIAQAAAA==.Moonpearl:BAAALAADCgQIBAAAAA==.Mortine:BAAALAADCggIDQAAAA==.',Mu='Mua:BAAALAADCgQIBAAAAA==.Mufi:BAABLAAECoEWAAMPAAcIqRhZIACQAQAPAAYI0hVZIACQAQAQAAYIBRSYTwB9AQAAAA==.',My='Myzorth:BAAALAAECgYIBgAAAA==.',Na='Nachsas:BAAALAADCggICAAAAA==.Nariane:BAAALAADCgYIBwAAAA==.Navaros:BAAALAADCgUIBQAAAA==.',Nh='Nhala:BAAALAAECgYIDwAAAA==.Nhs:BAABLAAECoEnAAMNAAgIFyJKBwAOAwANAAgIFyJKBwAOAwAWAAIIdSDhEwC+AAAAAA==.',Ni='Nielaa:BAAALAADCgcIBwAAAA==.Nikephoros:BAAALAAECggICAAAAA==.',No='Noaddon:BAAALAADCgEIAQAAAA==.Nogoodtank:BAAALAADCgEIAQAAAA==.',Nu='Nualinn:BAAALAADCgYIAQAAAA==.Nuriel:BAAALAADCgcIBwABLAAECgYIDAAEAAAAAA==.',['Né']='Néana:BAAALAAECgQIBgAAAA==.',Od='Odeseiron:BAAALAAECggIDwAAAA==.',Og='Oggsie:BAAALAAECgIIAQAAAA==.',Oh='Ohnaur:BAAALAAECgYICwAAAA==.',On='Oneshöt:BAAALAAECgUIBQAAAA==.Ongelukkige:BAAALAAECgEIAQAAAA==.',Or='Ordys:BAAALAADCgcIBwAAAA==.',Os='Ossia:BAAALAAECgYICQAAAA==.',Pa='Palanary:BAAALAAFFAEIAQAAAA==.Panzonfist:BAAALAAECgcIDwAAAA==.Pavelow:BAAALAADCggICgAAAA==.',Pe='Percepeus:BAAALAADCgIIAgAAAA==.Perceus:BAAALAADCgYIBwAAAA==.Percival:BAAALAADCgYIBwAAAA==.',Ph='Phantaleon:BAAALAADCggICAAAAA==.',Pi='Piimp:BAABLAAECoE0AAQIAAgILBy0EwCXAgAIAAgIvRu0EwCXAgAKAAMIRhC7GQDWAAAJAAIIWxPiUgCBAAAAAA==.Pinkhelmet:BAAALAADCgcIAgAAAA==.',Pj='Pjuskelusken:BAAALAADCgMIAwAAAA==.',Po='Polymilf:BAAALAADCgYIBgABLAAECggINAAIACwcAA==.',Ps='Psychogamer:BAAALAAECgMIAwAAAA==.',['Pâ']='Pânico:BAABLAAECoEjAAMBAAgIRyVmBgAsAwABAAgIviRmBgAsAwACAAEI+SZ7GwB2AAAAAA==.',Qu='Qualudes:BAAALAAECgMICQAAAA==.Quazzar:BAAALAAECgMIBgAAAA==.',Ra='Rakhsham:BAAALAAECgYIDAAAAA==.Rambok:BAAALAAECgcIEwAAAA==.Ranzog:BAAALAADCgcIBwAAAA==.Rapciune:BAAALAADCgYIBgAAAA==.Raupthasar:BAAALAAECggIDAAAAA==.',Re='Reivax:BAAALAAECgMIAwABLAAECggINAAIACwcAA==.Relani:BAAALAAECgMIAwABLAAECggIDwAEAAAAAA==.Revokes:BAABLAAECoEXAAMXAAYIxCL9BwBWAgAXAAYIxCL9BwBWAgADAAYI0RXxXgBZAQAAAA==.',Ri='Rimari:BAAALAAECgQIBgAAAA==.Rio:BAABLAAECoEmAAMVAAgIViG0AAATAwAVAAgIViG0AAATAwAQAAUIuBpwVABqAQAAAA==.Ripix:BAAALAAECgMIBQAAAA==.',Ru='Rullepølsen:BAABLAAECoEWAAIYAAcIex32CwBXAgAYAAcIex32CwBXAgAAAA==.Rumner:BAABLAAECoEaAAIZAAgIVRQqKADmAQAZAAgIVRQqKADmAQAAAA==.',Ry='Rysz:BAAALAADCggICQAAAA==.Ryuken:BAAALAADCgYIBgAAAA==.',['Ró']='Róshia:BAABLAAECoEbAAMaAAgISgwtJgCpAQAaAAgISgwtJgCpAQAbAAcIJgQYSgDzAAAAAA==.',Sa='Sauron:BAAALAAECgYICQAAAA==.',Se='Semenmachine:BAAALAADCgUIBQAAAA==.Semenmachiné:BAAALAADCgYIBgAAAA==.',Sh='Shadowfury:BAAALAADCggICAAAAA==.Shamdak:BAAALAAECgEIAQAAAA==.Shamren:BAACLAAFFIEIAAIZAAMINyA2AwAbAQAZAAMINyA2AwAbAQAsAAQKgR8AAhkACAjuHEYNAJQCABkACAjuHEYNAJQCAAAA.Shapke:BAAALAAECgIIAQAAAA==.Shattercleft:BAAALAAECgUIDQAAAA==.Shazaar:BAAALAAECgYIDAAAAA==.Shazman:BAAALAADCgYIBgAAAA==.Sheroni:BAAALAADCggIDwAAAA==.Shjarn:BAAALAAECgYIEQAAAA==.Shroomshaman:BAAALAAECgcIEwAAAA==.Sháqel:BAAALAADCgYIBgAAAA==.',Si='Sigmundrr:BAAALAADCgcIBwABLAAECggIDwAEAAAAAA==.',Sk='Skjerabagera:BAAALAAECggIDgAAAA==.Skjip:BAAALAAECgcIBwAAAA==.',Sl='Slowbzz:BAAALAAECgcIDgAAAA==.',Sm='Smorc:BAABLAAECoEZAAILAAgIYyTEBQA8AwALAAgIYyTEBQA8AwABLAAECggIHAAMAN4kAA==.',So='Sonel:BAAALAAECgYICAAAAA==.Sonje:BAAALAADCgYIBgAAAA==.',Sp='Spicyandcoke:BAAALAAECgEIAQAAAA==.Spiffi:BAAALAAECggICwAAAA==.Spiritclaws:BAAALAAECgIIAgABLAAECgYIDAAEAAAAAA==.Spúddy:BAABLAAECoEXAAIcAAcIIB9bGgBXAgAcAAcIIB9bGgBXAgAAAA==.',St='Stelf:BAAALAADCgEIAQAAAA==.Stigma:BAAALAAECggIDwAAAA==.',Sw='Sweetlaugh:BAAALAADCgQIBAAAAA==.',['Sá']='Sáhal:BAABLAAECoEZAAIdAAgIPxO+CwDoAQAdAAgIPxO+CwDoAQAAAA==.',['Sè']='Sèlèct:BAACLAAFFIEGAAIIAAMI8xELCQD9AAAIAAMI8xELCQD9AAAsAAQKgR8ABAgACAg9IK8KAPQCAAgACAg9IK8KAPQCAAoABwgIEOUIAOUBAAkAAghUGr5QAIsAAAAA.',Ta='Tamatori:BAAALAADCggIEAAAAA==.Tandora:BAAALAAECggICAAAAA==.Tangustan:BAAALAAECgIIAgAAAA==.Taranus:BAAALAAECgYIDAAAAA==.Tarnauk:BAAALAAECgEIAQAAAA==.Tauria:BAAALAAECgYICgAAAA==.',Te='Tempestade:BAAALAAECgEIAQAAAA==.Teneen:BAAALAADCggICAAAAA==.',Th='Theonekalle:BAAALAADCgMIAwAAAA==.Thordön:BAAALAAECgYICQAAAA==.Thorkild:BAAALAADCgMIAwAAAA==.Thundergrave:BAAALAAECgMIBQAAAA==.Thuradin:BAAALAAECgQICQAAAA==.Thórin:BAAALAADCgcIBwAAAA==.',Ti='Tinka:BAAALAADCgcIDQAAAA==.Tinkerrella:BAAALAADCgcIAgAAAA==.Tinyy:BAAALAAECggICwAAAA==.',To='Torine:BAAALAAECgYIBgAAAA==.Totemfutt:BAAALAADCggIDwAAAA==.',Tr='Traditor:BAAALAADCgMIAwAAAA==.Trolletotem:BAAALAAECgMIBAAAAA==.Tryn:BAAALAAECgYIDAAAAA==.',Tu='Tummi:BAAALAADCggIFwAAAA==.',Ty='Tyronus:BAAALAAECgcIBwAAAA==.Tyry:BAAALAAECgYIBgAAAA==.',['Tà']='Tàvore:BAAALAADCggICAAAAA==.',Um='Umar:BAAALAADCgcIDAAAAA==.Umber:BAAALAADCgcIAwAAAA==.',Un='Undeadmoomoo:BAAALAAECgQIBAAAAA==.',Ur='Ureass:BAAALAADCgcIBwAAAA==.',Uz='Uzzi:BAAALAADCgcIBwAAAA==.',Va='Vaelthion:BAAALAADCggIEAAAAA==.Valamagi:BAAALAADCgcIDwABLAAECgYIEgAEAAAAAA==.Valanor:BAAALAAECgYIEgAAAA==.Valkria:BAAALAAECgIIAgAAAA==.Vallmar:BAABLAAECoEZAAMOAAgIsRq4DwCHAgAOAAgIsRq4DwCHAgAcAAIIJBKyggBwAAAAAA==.',Vi='Vildvittra:BAAALAAECgYIDAAAAA==.',Vo='Voliwood:BAAALAADCgcIDgAAAA==.Voltarwulf:BAAALAADCgcIBwAAAA==.Voodoobob:BAAALAADCgcIBwAAAA==.',We='Wenbrandt:BAAALAADCgcIBwAAAA==.Wetlettuce:BAAALAAECgYIEwAAAA==.',Wh='Whiteweaver:BAAALAAECgEIAQAAAA==.',Wi='Wildar:BAAALAADCgIIAgAAAA==.Wimdu:BAAALAAECggICQAAAA==.Wimsp:BAAALAAECggICAAAAA==.Wisnix:BAAALAAECgcIEQAAAA==.',Yn='Ynk:BAAALAADCggICgAAAA==.Ynks:BAAALAADCggICgAAAA==.',Ys='Yseraa:BAAALAADCggICAAAAA==.',Za='Zadicz:BAAALAAECgIIAgAAAA==.Zardu:BAAALAAECgIIAwAAAA==.Zayvon:BAAALAADCgcIBwAAAA==.Zaza:BAAALAADCgQIBAAAAA==.',Ze='Zeborg:BAAALAAECgEIAQAAAA==.Zerobyte:BAAALAADCggICAAAAA==.',Zi='Ziru:BAAALAAECggICAAAAA==.',Zo='Zorinn:BAAALAADCggIBwAAAA==.Zorua:BAAALAAECgEIAQABLAAECgcIFwAcACAfAA==.',['Üw']='Üwü:BAAALAADCgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end