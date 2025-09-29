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
 local lookup = {'Hunter-BeastMastery','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','DemonHunter-Vengeance','Shaman-Enhancement','Rogue-Outlaw','Priest-Holy','Priest-Shadow','Warrior-Fury','DeathKnight-Frost','Priest-Discipline','Unknown-Unknown','Shaman-Elemental','Druid-Guardian','DeathKnight-Unholy','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Hunter-Marksmanship','Druid-Balance','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Evoker-Augmentation','Warrior-Protection','Druid-Feral','DeathKnight-Blood',}; local provider = {region='EU',realm='Gilneas',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Achilleus:BAAALAADCgUICQAAAA==.',Ad='Adamantina:BAABLAAECoEyAAIBAAgIyiP2EgDzAgABAAgIyiP2EgDzAgAAAA==.Adelmute:BAAALAAFFAEIAQAAAA==.Adorabel:BAAALAADCgcIBwABLAAECggIJwACAKcmAA==.Adrazil:BAABLAAECoEmAAIDAAcI9BFhKwCvAQADAAcI9BFhKwCvAQABLAAECggIHwAEAC4PAA==.Adriella:BAABLAAECoEXAAIFAAYIph+AEwAIAgAFAAYIph+AEwAIAgAAAA==.',Ae='Aelena:BAAALAAECgUIBQAAAA==.',Ak='Akanê:BAAALAADCgEIAQAAAA==.Akui:BAAALAAECgcICAAAAA==.',Al='Alaric:BAAALAAECggICQAAAA==.Alexandrà:BAAALAADCgYIBgAAAA==.Alukarl:BAAALAAFFAIIAgAAAA==.',Am='Amaly:BAABLAAECoEaAAIGAAcIhxuACgArAgAGAAcIhxuACgArAgAAAA==.Amando:BAAALAAECggICAAAAA==.Amanvâh:BAAALAADCggICAAAAA==.Amathalarus:BAAALAAECgYIDwAAAA==.Amokio:BAAALAAECgQICAAAAA==.',An='Anco:BAAALAAECgcIBwAAAA==.Andiray:BAAALAADCgcIBwAAAA==.Angaráto:BAAALAAECgcIEQABLAAFFAIIDQAHACgiAA==.Ankor:BAAALAAECgMIAgAAAA==.Annageddon:BAAALAAECgYIEgAAAA==.Anubilia:BAAALAAECgcIDQAAAA==.Anubit:BAABLAAECoEYAAMIAAcIihqpJgAyAgAIAAcIihqpJgAyAgAJAAMI+ATlhABEAAAAAA==.Anuky:BAAALAAECgYIDgAAAA==.',Ap='Apfelmusmann:BAABLAAECoEdAAIKAAcIMBt1NgAqAgAKAAcIMBt1NgAqAgAAAA==.',Ar='Archeôn:BAAALAAECggIEAAAAA==.Artemîs:BAAALAAECgIIAgAAAA==.Arthaz:BAABLAAECoEgAAIFAAgIiRq8EgASAgAFAAgIiRq8EgASAgAAAA==.Artikon:BAABLAAECoEoAAILAAcIthdHZgD1AQALAAcIthdHZgD1AQAAAA==.',As='Asmavaeth:BAAALAAECggIAgAAAA==.Astmatiker:BAAALAADCggICgAAAA==.',At='Atomfrieda:BAAALAADCggIDgAAAA==.Atreyana:BAAALAADCggICAABLAAECggIGQAMAMchAA==.Atreyû:BAAALAAECgYICgAAAA==.Attilla:BAAALAAECggICwAAAA==.Atum:BAAALAADCgUIBQABLAAECgIIAgANAAAAAA==.',Au='Audrid:BAAALAADCgQIBAAAAA==.Aureliá:BAAALAAECgYIDwAAAA==.',Av='Avaloniâ:BAAALAAECgYICwAAAA==.Aveeny:BAABLAAECoEnAAICAAgIKRprKABNAgACAAgIKRprKABNAgAAAA==.Avri:BAAALAAECgEIAQABLAAECggICAANAAAAAA==.',Aw='Awanatá:BAABLAAECoEVAAIBAAYIehGeogA6AQABAAYIehGeogA6AQABLAAECgYIFQAOAGANAA==.',Ay='Aylea:BAAALAAECgcICwAAAA==.',Ba='Babrika:BAAALAAECgYIDAAAAA==.Backferry:BAAALAADCgcIBwABLAADCggICAANAAAAAA==.Bahâmuth:BAAALAADCgMIAwAAAA==.Bakui:BAAALAAECgUIBQAAAA==.Ban:BAAALAAECgYIBgAAAA==.Bandits:BAAALAADCgEIAQAAAA==.Bartkor:BAAALAAECgcIEwAAAA==.Bazer:BAAALAADCgYIBgABLAAECggIJwAFAOYfAA==.',Be='Bearforzeone:BAABLAAECoEXAAIPAAcIdBc+DADhAQAPAAcIdBc+DADhAQAAAA==.Beastman:BAAALAAECgMIBAAAAA==.Belofar:BAABLAAECoEVAAMJAAcIkAl2TQBdAQAJAAcIkAl2TQBdAQAIAAUItg4KcgD/AAABLAAECggIKQAQADkbAA==.Benjolo:BAAALAAECgYIDAABLAAECggIJwARAJ4ZAA==.Betsy:BAAALAAECgEIAQAAAA==.',Bi='Bigbass:BAAALAADCgUIBgAAAA==.Birma:BAAALAAECgUIBQAAAA==.Birta:BAABLAAECoEnAAICAAgIpyZcAQBmAwACAAgIpyZcAQBmAwAAAA==.',Bl='Blackdone:BAAALAAECggIEAAAAA==.Blackpitch:BAAALAADCgIIAgAAAA==.Bloodycruel:BAAALAADCggIEAAAAA==.Bluughhunt:BAACLAAFFIEJAAIBAAMIqxMLEwDlAAABAAMIqxMLEwDlAAAsAAQKgS0AAgEACAgPIgYTAPMCAAEACAgPIgYTAPMCAAAA.Bløødbath:BAAALAADCggIDwAAAA==.',Bo='Boese:BAAALAAECgIIAgAAAA==.Borenzo:BAAALAADCgYICQAAAA==.Bottrom:BAABLAAECoEdAAMSAAcIHAwjMwCHAQASAAcIcAsjMwCHAQATAAcIAwiWIwBIAQAAAA==.',Br='Broxas:BAAALAAECggICwAAAA==.Brók:BAABLAAECoEXAAIUAAYIxhKNMABFAQAUAAYIxhKNMABFAQAAAA==.',Bu='Bubbletogo:BAAALAAECgMIAwAAAA==.Buberella:BAAALAAECgYICAAAAA==.Bunnyhop:BAAALAAECgUIDQAAAA==.Bunnymädchen:BAAALAADCggIFAAAAA==.Burnhard:BAAALAADCgcIBwAAAA==.Burtor:BAAALAADCggICAABLAAECgcIJQARAD4fAA==.',By='By:BAAALAADCgYIBwAAAA==.',Ca='Cartly:BAAALAADCgUIBQABLAAECggIHQAJANAYAA==.Cascada:BAACLAAFFIEFAAIIAAMInRJoEADnAAAIAAMInRJoEADnAAAsAAQKgSUAAggACAgBIz4JABEDAAgACAgBIz4JABEDAAAA.Casnar:BAAALAADCggICAAAAA==.Castellock:BAACLAAFFIELAAMVAAUIugjTFQAKAQAVAAQImgbTFQAKAQAWAAEIPBFCIwBNAAAsAAQKgS0ABBUACAjlIFofAK0CABUACAjQIFofAK0CABYABQioGxgzAIABABcAAQg/D2k4AEEAAAAA.',Ce='Ceelia:BAABLAAECoEnAAMVAAgIfiBRLQBgAgAVAAgIfiBRLQBgAgAWAAUIdxMcRgAzAQAAAA==.Cellypatch:BAAALAAECgIIAgABLAAECgUIBgANAAAAAA==.Ceyla:BAAALAAECggICAAAAA==.Ceylandra:BAAALAAECgIIAgAAAA==.',Ch='Changes:BAAALAADCgcIFAAAAA==.Channella:BAAALAADCggICwAAAA==.Chaosben:BAAALAADCggICAABLAAFFAIIAgANAAAAAA==.Cheri:BAAALAAECgMIBwAAAA==.Cheveyo:BAAALAAECgYICQAAAA==.Chewi:BAAALAADCgcIDQAAAA==.Chízú:BAAALAAECgQIBQAAAA==.',Ci='Ciarra:BAABLAAECoEVAAIYAAcIMhmXRwARAgAYAAcIMhmXRwARAgAAAA==.',Cl='Clangedin:BAAALAAECgMICAAAAA==.Clira:BAAALAAECgEIAQAAAA==.',Co='Controlled:BAABLAAECoEgAAICAAgIDx+4IgBnAgACAAgIDx+4IgBnAgAAAA==.Coyama:BAAALAAECggICAAAAA==.Coínflip:BAAALAADCggICAAAAA==.',Cr='Cricx:BAABLAAECoEaAAIJAAcIzQxAQwCLAQAJAAcIzQxAQwCLAQAAAA==.',Cy='Cyowen:BAAALAAECgQIBgAAAA==.',['Câ']='Cârl:BAABLAAECoEUAAMBAAYIChrjeQCKAQABAAYIahjjeQCKAQAZAAYIexOMUABaAQAAAA==.',Da='Dakarion:BAABLAAECoElAAMRAAcIPh+2QgCeAQARAAUIfRy2QgCeAQAaAAcIihRNSgBVAQAAAA==.Danielo:BAAALAAECgYICgAAAA==.Darelien:BAABLAAECoEnAAIYAAgIBiCRNwBPAgAYAAgIBiCRNwBPAgAAAA==.Dariarona:BAAALAAECgQIBAAAAA==.Darksel:BAAALAADCggIDwAAAA==.Darkskystorm:BAAALAADCgEIAQAAAA==.Darktwerc:BAAALAADCggICAAAAA==.Dasha:BAAALAADCgcIBwAAAA==.',De='Deisý:BAAALAADCgcIEAABLAAFFAMIBQAbAKIUAA==.',Dh='Dhazeria:BAABLAAECoEnAAIFAAgI5h+kCwB3AgAFAAgI5h+kCwB3AgAAAA==.Dhukai:BAABLAAECoEYAAIOAAYIXRg7SwCuAQAOAAYIXRg7SwCuAQAAAA==.',Di='Dineth:BAAALAAECgQIBAAAAA==.Disasterpice:BAAALAADCggIEAAAAA==.',Dj='Djarin:BAAALAAECggIEQAAAA==.',Do='Donkaybong:BAAALAAECgEIAgAAAA==.',Dr='Dracthyrian:BAABLAAECoEYAAIcAAgIWAP0RwDXAAAcAAgIWAP0RwDXAAAAAA==.Dracyris:BAAALAAECggICAAAAA==.Dragunøv:BAAALAADCggICAAAAA==.Drakania:BAABLAAECoEZAAMcAAgItBZZGgA0AgAcAAgItBZZGgA0AgAdAAIIRwzVMwBbAAAAAA==.Drakui:BAAALAADCgUIBQAAAA==.Dranhey:BAAALAADCgcIDgAAAA==.Dreist:BAAALAADCgYIBgAAAA==.Dreyken:BAAALAADCggIDwAAAA==.Driz:BAABLAAECoEnAAIYAAgIcRxpOQBGAgAYAAgIcRxpOQBGAgAAAA==.Drracona:BAAALAAECgQICAAAAA==.',Ds='Dschaffar:BAABLAAECoEvAAIDAAgIjCJ+BwAGAwADAAgIjCJ+BwAGAwAAAA==.',['Dê']='Dêrg:BAAALAAECgYIDQAAAA==.',Ea='Eamane:BAAALAADCggIHAAAAA==.',Ec='Ecural:BAABLAAECoEWAAIQAAgIgSHcCAC2AgAQAAgIgSHcCAC2AgAAAA==.',El='Eldaroth:BAAALAADCgYIBgABLAAECggIDwANAAAAAA==.Element:BAAALAADCgUIBQAAAA==.Eljafin:BAAALAAECgMIAwAAAA==.',Er='Eroica:BAABLAAECoEZAAIdAAgI/wiJHwA1AQAdAAgI/wiJHwA1AQAAAA==.',Ev='Evángelos:BAAALAADCggIHAAAAA==.',Ex='Exoduz:BAAALAAECggIDwABLAAFFAMICQABAKsTAA==.Exoma:BAAALAAECgYIDQAAAA==.Exomos:BAAALAADCggIEAAAAA==.Exotic:BAAALAADCggICAAAAA==.',Ez='Ezrì:BAAALAAECgQIBAABLAAECggILwAeAA8lAA==.',Fa='Faelas:BAABLAAECoEpAAIfAAgIvBa7WgAIAgAfAAgIvBa7WgAIAgAAAA==.Falinstrasz:BAAALAADCgIIAgABLAAECgIIAwANAAAAAA==.Famulá:BAAALAADCggIDwABLAAECgYIFQAOAGANAA==.',Fe='Feadale:BAAALAAECgQICQAAAA==.Feanør:BAAALAADCgcIBwAAAA==.Felôra:BAAALAADCggICAAAAA==.Fenris:BAAALAADCgcIBwAAAA==.Fenriz:BAAALAAECgUIDQAAAA==.Feuerdráche:BAAALAADCggIFwAAAA==.Feurouge:BAAALAAECgQICQAAAA==.',Fi='Fiareth:BAAALAADCgQIBAABLAAECggIHwAEAC4PAA==.Firetropi:BAAALAADCgMIAwAAAA==.Firion:BAAALAADCggIFAAAAA==.Fistr:BAABLAAECoEWAAIEAAcIAyGbEAA6AgAEAAcIAyGbEAA6AgAAAA==.',Fl='Flachmann:BAAALAADCggIEAAAAA==.Flauschtatze:BAAALAADCgMIAwAAAA==.Floresthan:BAABLAAECoEUAAIgAAcInAlBKAAUAQAgAAcInAlBKAAUAQAAAA==.',Fo='Fourcheese:BAAALAADCgcIDgAAAA==.',Fr='Fraali:BAAALAADCgcIBwAAAA==.Freyaar:BAAALAADCgcIBwABLAAECggIJwAFAOYfAA==.',Fu='Fullin:BAAALAADCggICQABLAAECggIJQAWADoeAA==.Furiosia:BAAALAADCgQIAwAAAA==.',Fy='Fyona:BAAALAAECgYICAAAAA==.',Ga='Galerius:BAAALAADCggIEAAAAA==.Galfa:BAAALAAECgYICgABLAAFFAIIDQAHACgiAA==.Galvani:BAAALAAECgQIBQAAAA==.Gamarona:BAAALAAECgcIBwAAAA==.Gandoro:BAAALAAECgUICgAAAA==.Garwald:BAAALAADCggIEAAAAA==.',Ge='Gearboltless:BAAALAAECgIIAgAAAA==.Gebrittnicke:BAAALAADCgYIBgAAAA==.Geist:BAAALAAECgMIBQAAAA==.Geri:BAAALAADCggICAAAAA==.',Gh='Ghazkull:BAABLAAECoEUAAIfAAYItBvlegDEAQAfAAYItBvlegDEAQAAAA==.',Gi='Ginora:BAAALAAECgUIBQAAAA==.',Gl='Glemgor:BAABLAAECoEZAAIIAAcIBR2JIgBMAgAIAAcIBR2JIgBMAgAAAA==.',Gn='Gnexmex:BAAALAAECgUIDQAAAA==.',Go='Goggon:BAAALAAECggIAgAAAA==.Golddorn:BAAALAAECgYIDAAAAA==.Gondolin:BAAALAAECgUICAAAAA==.Goroth:BAAALAADCgEIAQAAAA==.Gown:BAAALAADCggIEAABLAAECggIGQAYAMMUAA==.',Gr='Graendel:BAAALAADCgUIBQAAAA==.Greenerina:BAAALAAECgMIAwAAAA==.Greenhorn:BAAALAAECgQICwABLAAECgYICAANAAAAAA==.Gremgar:BAAALAAECgQIDQAAAA==.Grischnax:BAAALAADCgUIBQAAAA==.Growal:BAAALAADCgQIBAAAAA==.',Gu='Gulthar:BAAALAAECgYICAAAAA==.Gundaar:BAAALAAECgUIDQAAAA==.',['Gü']='Güldenstar:BAAALAAECgcIEAAAAA==.',Ha='Hanar:BAAALAAECgYIEgAAAA==.Hanfpalme:BAABLAAECoEYAAIhAAgI/QPtQADdAAAhAAgI/QPtQADdAAAAAA==.Hanfpflanze:BAAALAAECggICAAAAA==.Hannelori:BAAALAAECggICAAAAA==.Hanniah:BAAALAADCggICAABLAAECgMIBQANAAAAAA==.Hardès:BAABLAAECoEcAAIKAAcI4Rh0QgD5AQAKAAcI4Rh0QgD5AQAAAA==.Harpyie:BAAALAADCgYIBgAAAA==.',He='Hellebron:BAABLAAECoEYAAIVAAgI/AOLkwARAQAVAAgI/AOLkwARAQAAAA==.Heraa:BAAALAADCggICAAAAA==.',Ho='Honkymonkey:BAABLAAECoEVAAIhAAcI9AX1PgDuAAAhAAcI9AX1PgDuAAAAAA==.Honêybunny:BAAALAADCggICQAAAA==.',Hu='Huntinghexer:BAAALAAECgYIBgAAAA==.Huntingwarr:BAACLAAFFIETAAIKAAYIYxiYAwAhAgAKAAYIYxiYAwAhAgAsAAQKgRgAAgoACAjRI1MMACwDAAoACAjRI1MMACwDAAAA.',Hy='Hymai:BAABLAAECoEVAAIZAAcIhAugWAA9AQAZAAcIhAugWAA9AQAAAA==.',Id='Idarel:BAAALAADCggIFwABLAAECgcIJQARAD4fAA==.',Ik='Iketa:BAAALAAECgQIBAAAAA==.Iknow:BAAALAADCggIFQABLAAECgYICAANAAAAAA==.',Il='Iliedan:BAAALAAECggIBgAAAA==.',Im='Imbalanced:BAAALAAECgEIAQABLAAECggIAgANAAAAAA==.Imgral:BAAALAADCggICAAAAA==.Imgrîmmsch:BAAALAAECgUIDQAAAA==.',In='Inosan:BAABLAAECoEWAAMIAAcILiRtEgC8AgAIAAcILiRtEgC8AgAJAAYINRICSAB0AQAAAA==.',Is='Isabo:BAAALAADCgcIBwAAAA==.Iskeria:BAAALAAECgcIDwAAAA==.',It='Itzwarlock:BAABLAAECoElAAMWAAgImhwlFQA0AgAWAAgImhwlFQA0AgAVAAEISwIAAAAAAAAAAA==.',Ja='Jaromìr:BAAALAADCgUIBQAAAA==.',Je='Jeryla:BAAALAADCgUIBQAAAA==.',Ji='Jinora:BAABLAAECoEmAAIIAAgIgxSOMgD0AQAIAAgIgxSOMgD0AQAAAA==.Jinoryn:BAAALAAECgYIBgAAAA==.',Jl='Jllida:BAAALAADCgYIBgAAAA==.',Jo='Jordahn:BAAALAADCgcIBwAAAA==.Joý:BAAALAADCgYIBgABLAAFFAMIBQAbAKIUAA==.',Ju='Juren:BAABLAAECoEWAAIBAAcIIRIQdQCVAQABAAcIIRIQdQCVAQAAAA==.Juripa:BAAALAADCggICwAAAA==.',['Já']='Jáde:BAAALAAECgQICAAAAA==.',['Jó']='Jóline:BAAALAADCgcIBwABLAAFFAMIBQAbAKIUAA==.',Ka='Kaav:BAAALAADCggICQAAAA==.Kadaj:BAAALAAECgEIAQAAAA==.Kahono:BAAALAAECgUIBQAAAA==.Kailyna:BAABLAAECoEYAAQXAAYIiBZXHAD3AAAVAAYIbBMEaACGAQAXAAQIwRBXHAD3AAAWAAEI3Bd3fwBGAAABLAAECggIKQAQADkbAA==.Kaisâ:BAAALAAECgYIDAAAAA==.Kalego:BAAALAAECggICAAAAA==.Kaltilover:BAAALAAECgIIAwAAAA==.Kampfkecks:BAAALAADCggIEQAAAA==.Kampfzicke:BAAALAADCgcIBwAAAA==.Kartoffelsak:BAAALAADCggIFgAAAA==.Kaschira:BAAALAAECgcIEAAAAA==.Kaseopeia:BAAALAADCggICAAAAA==.Kateperry:BAAALAAECgYIBgAAAA==.Kazonk:BAAALAAECgIIAgAAAA==.Kaztay:BAABLAAECoEYAAIYAAcIMAsWdQCJAQAYAAcIMAsWdQCJAQAAAA==.',Ke='Kenzo:BAAALAAECgEIAQAAAA==.Kesara:BAAALAADCgEIAQAAAA==.Kessaya:BAAALAADCgcIBwAAAA==.',Kh='Khélgrar:BAAALAADCgIIAgAAAA==.',Ki='Kiaransalee:BAAALAADCgEIAQAAAA==.Kickingwicky:BAAALAAECgIIAgAAAA==.Kijan:BAAALAAECgQICQAAAA==.Killertaps:BAAALAAECgQIDAAAAA==.Killoster:BAAALAAECgYICAAAAA==.Killyou:BAAALAAECgYICQAAAA==.Killyoufast:BAABLAAECoEjAAIfAAcIHhX7bQDeAQAfAAcIHhX7bQDeAQAAAA==.Kiná:BAAALAADCggIAQABLAAECgQIDAANAAAAAA==.Kisankanna:BAAALAADCggICAAAAA==.Kishra:BAAALAADCgYIBgABLAAECgEIAQANAAAAAA==.Kitkat:BAAALAAECgYICAABLAAECggIKQAfANUeAA==.',Kl='Klaustrophob:BAAALAADCggICAABLAAECgIIAgANAAAAAA==.Kleener:BAAALAAECgMIAwAAAA==.Klopriest:BAAALAADCgYIBgABLAAECgYICAANAAAAAA==.Kloshift:BAAALAAECgIIAgAAAA==.',Kr='Kregan:BAABLAAECoEeAAICAAcIaCIoFwCkAgACAAcIaCIoFwCkAgAAAA==.Kriad:BAAALAAECgYIFwAAAQ==.',Ku='Kukie:BAAALAADCggIGgAAAA==.Kumaneko:BAAALAAECgYIBgAAAA==.Kurzvorelf:BAAALAAECggIEAAAAA==.Kushiel:BAABLAAECoEnAAMJAAgIRhnYQgCMAQAJAAYIyBbYQgCMAQAIAAgIcAgDXQBCAQAAAA==.',Ky='Kyrion:BAAALAAECggIAwAAAA==.',['Ké']='Kélath:BAABLAAECoEeAAMUAAcIXhUuLwBOAQAfAAYInA+otgBWAQAUAAcIXRIuLwBOAQAAAA==.',['Kî']='Kîrî:BAAALAAECgUIBAAAAA==.',['Kú']='Kú:BAAALAAECgYIDgABLAAFFAIIBgAVAMoQAA==.',La='Lagerthå:BAABLAAECoEaAAMFAAgINyFCCAC3AgAFAAcIASRCCAC3AgAbAAgIsA0AAAAAAAAAAA==.',Le='Leeju:BAAALAAECggIEwAAAA==.Leevia:BAAALAADCggICAAAAA==.Legaia:BAAALAADCggICQAAAA==.Leichenlilli:BAAALAAECgYIBgAAAA==.Leva:BAAALAAECgYICQAAAA==.',Li='Liath:BAABLAAECoEaAAIIAAcIvgy7UwBkAQAIAAcIvgy7UwBkAQAAAA==.Lilithak:BAAALAADCggICAAAAA==.Lillyar:BAAALAAECgQIBwAAAA==.Littleham:BAAALAAECggIEwAAAA==.Littlekira:BAAALAADCgMIAwABLAAFFAMIBQAbAKIUAA==.Littlesanny:BAAALAADCggIBgAAAA==.Livor:BAAALAAECgYIDQAAAA==.',Ll='Llondor:BAAALAAECgMIBwAAAA==.Lloth:BAABLAAECoEVAAMSAAcIlhjpHQATAgASAAcIlhjpHQATAgATAAEIKgaERwAlAAAAAA==.Llunafey:BAAALAAECgQIBQAAAA==.',Lo='Logaris:BAAALAADCggIFgAAAA==.Lophera:BAAALAAECgQIDAAAAA==.',Lu='Lunicavolpe:BAAALAADCgUIBQAAAA==.Lunià:BAAALAAECgMIAwAAAA==.',Ly='Lyssia:BAABLAAECoEeAAIFAAcIbBn1EwADAgAFAAcIbBn1EwADAgAAAA==.Lyxi:BAAALAAECgYIBgAAAA==.Lyxiana:BAABLAAECoEUAAIFAAYIoh38FQDrAQAFAAYIoh38FQDrAQAAAA==.',['Lý']='Lýs:BAABLAAECoEYAAIdAAgIZiAIDwARAgAdAAgIZiAIDwARAgAAAA==.',Ma='Madclaw:BAAALAADCggIDwABLAADCggIHAANAAAAAA==.Magdablair:BAAALAAECggICAAAAA==.Makeo:BAAALAAECggIEwAAAA==.Maki:BAAALAAECgMIBAAAAA==.Maloj:BAAALAAECgYIDgAAAA==.Marius:BAACLAAFFIEOAAILAAMIBhouGQDsAAALAAMIBhouGQDsAAAsAAQKgSIAAgsACAisJJIOACkDAAsACAisJJIOACkDAAAA.Mathi:BAAALAAECgYIEgAAAA==.',Me='Meliodas:BAAALAADCgQIBAAAAA==.Mellificent:BAAALAAECgYICQAAAA==.Menion:BAAALAAECgIIBAAAAA==.Meowjkmiau:BAAALAAECgQIBAAAAA==.Meradan:BAAALAAECgYIDQAAAA==.Merlot:BAABLAAECoEWAAMRAAgIWgxMWQBKAQARAAgIWgxMWQBKAQAPAAYIfgbAHQDcAAAAAA==.Metaro:BAAALAADCgUIBQABLAAECgcIHgACAGgiAA==.',Mi='Minariah:BAAALAADCgYIBgAAAA==.Mirianna:BAAALAADCgcIBwAAAA==.Mirineos:BAAALAADCgcIBwAAAA==.',Mo='Monkni:BAAALAADCgUIBQAAAA==.Monuky:BAAALAAECgUIBQAAAA==.Mopso:BAAALAADCgcIBwAAAA==.Mordak:BAABLAAECoEnAAISAAgIXhOjGwAnAgASAAgIXhOjGwAnAgAAAA==.Moriliath:BAABLAAECoEiAAILAAgIUBvVYgD8AQALAAgIUBvVYgD8AQAAAA==.',Mu='Muckslix:BAABLAAECoEcAAIVAAcIRAvHawB8AQAVAAcIRAvHawB8AQAAAA==.Muhlinex:BAAALAADCgQIBAAAAA==.Murkyy:BAAALAAECgMIBgAAAA==.Murmalinator:BAAALAAECgMIBQAAAA==.Musaschi:BAAALAAECgQICQABLAAECgYIBgANAAAAAA==.',My='Myrîel:BAAALAAECggICAAAAA==.',['Mâ']='Mâmâ:BAABLAAECoEdAAIJAAgI0BgCIABVAgAJAAgI0BgCIABVAgAAAA==.Mâu:BAAALAAECgMIBgABLAAECgUICAANAAAAAA==.Mâzaky:BAAALAAECgQIDgAAAA==.',Na='Nabucco:BAABLAAECoEbAAMXAAgIjArSEQB6AQAXAAgIjArSEQB6AQAWAAEIXADYkQALAAAAAA==.Naera:BAAALAADCggICAABLAAECgYIDAANAAAAAA==.Namirja:BAAALAAECgMIBgAAAA==.Namorâ:BAAALAADCgEIAQAAAA==.Narlim:BAAALAAECgUIBwAAAA==.Narrenferal:BAAALAAECgYICQABLAAFFAMIBwARAD0VAA==.Narrenpala:BAAALAAECgYIDAABLAAFFAMIBwARAD0VAA==.Naryah:BAAALAAECgYICQAAAA==.Nasgor:BAAALAADCgYIBgAAAA==.Navily:BAAALAADCgMIAwABLAAECggIGAAVAEoGAA==.',Ne='Neffelum:BAABLAAECoEVAAIGAAcInhsgCQBLAgAGAAcInhsgCQBLAgAAAA==.Neleneue:BAAALAADCgcICgAAAA==.Nelia:BAAALAAECgcIDAAAAA==.Nerg:BAAALAADCgYIBgAAAA==.Nerimee:BAAALAADCgQIBAABLAAECgQIDAANAAAAAA==.',Ni='Niaolong:BAAALAADCgcIBwAAAA==.Niemert:BAAALAAECgMIBQAAAA==.Nilrai:BAAALAADCggICgAAAA==.Nirn:BAAALAAECgMIAwAAAA==.',No='Noríco:BAAALAADCgYIBgAAAA==.',Nu='Nu:BAAALAADCgcIBwAAAA==.',Ny='Nybalde:BAAALAAECgYICgAAAA==.Nysos:BAAALAADCggICAAAAA==.Nyxh:BAAALAADCgQIBAAAAA==.',Od='Odin:BAABLAAECoEgAAIfAAgIPhoROABrAgAfAAgIPhoROABrAgAAAA==.',Og='Ogtar:BAAALAAECgQICAAAAA==.',Ok='Oktaviaklaud:BAAALAADCgMIAwAAAA==.',Ou='Outdunit:BAAALAAECgYICAAAAA==.',Pa='Painrezepte:BAAALAADCgQIBgAAAA==.Palagoh:BAABLAAECoEaAAIfAAcIDgfrwwA+AQAfAAcIDgfrwwA+AQAAAA==.Paldette:BAAALAAECgcIDgAAAA==.Pallando:BAAALAAECgIIBAAAAA==.Pallydine:BAAALAAECgEIAQAAAA==.Pangea:BAAALAAECgYIDgAAAA==.Pauley:BAAALAADCgcIBwAAAA==.',Pe='Peymakalir:BAAALAAECggICAAAAA==.',Ph='Phenom:BAAALAADCggIFAABLAADCggIHAANAAAAAA==.Phynadrea:BAABLAAECoElAAIOAAgIFBoqIgB0AgAOAAgIFBoqIgB0AgAAAA==.Phönìx:BAAALAAECgYIDQAAAA==.',Pi='Pieps:BAAALAAECgQIBQABLAAECggILwARAG4lAA==.',Po='Pocket:BAAALAAECgUIDgAAAA==.',Pr='Pronos:BAAALAAECgMIBQAAAA==.',Ps='Psycholaus:BAABLAAECoEVAAIJAAgIXg+NOgC1AQAJAAgIXg+NOgC1AQAAAA==.',Pu='Puddles:BAAALAADCggICQABLAAECggIFAAKAPoTAA==.Puk:BAAALAADCgYIBgAAAA==.Puschyevoker:BAABLAAECoErAAIcAAgILiC4CgDmAgAcAAgILiC4CgDmAgABLAAFFAUIDAALABYSAA==.Puschymonk:BAABLAAECoEvAAIgAAgIYBlAFADxAQAgAAgIYBlAFADxAQABLAAFFAUIDAALABYSAA==.Puschypríest:BAAALAAECgEIAQABLAAFFAUIDAALABYSAA==.',Py='Pythonissam:BAAALAAECgMIBQAAAA==.',['Pé']='Péach:BAAALAAECgYICQAAAA==.',Qu='Quantice:BAAALAAECgMIAgABLAAECgYIDQANAAAAAA==.Quinter:BAAALAAECgYIDAABLAAECggIFgAQAIEhAA==.',Ra='Ragnos:BAAALAAECgMIAwAAAA==.Raguhl:BAAALAADCggICAABLAAECgUIDgANAAAAAA==.Ramura:BAAALAADCgcIBwAAAA==.Ramuthra:BAAALAADCggIBgABLAADCggIEAANAAAAAA==.Randîr:BAAALAAECgYIDwAAAA==.Rapidô:BAAALAADCggICAAAAA==.Raziel:BAAALAADCggICAAAAA==.Razzha:BAABLAAECoEWAAQdAAcIMhaDFwCRAQAdAAYI9BWDFwCRAQAcAAQIjhVoQwACAQAiAAEISBFkFQBIAAAAAA==.',Re='Reginaris:BAAALAADCggIDwAAAA==.Regtoz:BAAALAAECggIDAAAAA==.Reksai:BAAALAAECgEIAQAAAA==.Rexonia:BAAALAADCggICQAAAA==.',Rh='Rhônôn:BAAALAAECgYIBgAAAA==.',Ri='Ridieck:BAAALAAECgMICQAAAA==.Rilmeya:BAAALAAECgMICgAAAA==.',Ro='Roidmuncher:BAABLAAECoEYAAQIAAYI9RrwZAAoAQAIAAYI9RrwZAAoAQAMAAEIEhSuMAA8AAAJAAEIFgNjjwApAAAAAA==.Rosi:BAAALAAECgYIEQAAAA==.',Ry='Ryzaari:BAAALAADCggICAABLAAECggIJwAFAOYfAA==.',['Ré']='Rééd:BAAALAADCgEIAQAAAA==.',['Rî']='Rînø:BAAALAAECgIIAgAAAA==.',Sa='Sahif:BAACLAAFFIEFAAIbAAMIkA4NFQDlAAAbAAMIkA4NFQDlAAAsAAQKgSwAAhsACAgrG6gxAHACABsACAgrG6gxAHACAAAA.Sainnith:BAAALAADCgcIBwABLAADCggICQANAAAAAA==.Saintlucifer:BAAALAADCggICwAAAA==.Sakajo:BAAALAAECgIIAgAAAA==.Sakirya:BAABLAAECoEZAAIMAAgIxyFuAQAOAwAMAAgIxyFuAQAOAwAAAA==.Salemon:BAAALAAECggICAAAAA==.Salinâ:BAABLAAECoEWAAIbAAcI0QdSrQA+AQAbAAcI0QdSrQA+AQAAAA==.Salud:BAAALAADCgUICAAAAA==.Sam:BAAALAAECgYICAAAAA==.Sanaru:BAAALAAECgIIAgABLAAECggIHwAEAC4PAA==.Sanchez:BAABLAAECoEYAAIfAAYIbhg4fwC7AQAfAAYIbhg4fwC7AQABLAAECggIGwAKAFkXAA==.Sanjisan:BAAALAAECgQIAgAAAA==.Sannyboy:BAAALAAECggIDwAAAA==.Sarjna:BAAALAAECgMIBQAAAA==.Sarumara:BAAALAADCggICAAAAA==.Sayacia:BAAALAAECgUICQAAAA==.',Sc='Schledi:BAAALAADCgMIAwAAAA==.Schlossoline:BAAALAADCggICQAAAA==.Schnikschnak:BAAALAAECgMIBAAAAA==.',Se='Selinari:BAAALAADCgcICwAAAA==.Seni:BAABLAAECoEcAAIJAAcIFB5/GwB5AgAJAAcIFB5/GwB5AgAAAA==.Senitrin:BAAALAAECggICAABLAAECggIHAAJABQeAA==.Serit:BAAALAAECgYIBgAAAA==.Seviya:BAAALAAECgYIEgAAAA==.',Sh='Shadowbear:BAAALAAECgUIDQAAAA==.Shadowhawk:BAAALAADCggICAAAAA==.Shakui:BAAALAAECgMIBwAAAA==.Shamanlenin:BAABLAAECoEbAAICAAgInhXNQAD0AQACAAgInhXNQAD0AQAAAA==.Shame:BAAALAAECgYIDwAAAA==.Shavion:BAAALAADCggICgABLAADCggIHAANAAAAAA==.Sheltera:BAABLAAECoEZAAIYAAgIwxTkPwAtAgAYAAgIwxTkPwAtAgAAAA==.Shenlao:BAAALAAECggIDwAAAA==.Shenyo:BAAALAAECgMIBQAAAA==.Sheryfa:BAAALAAECgIIAgAAAA==.Shiokekw:BAACLAAFFIEGAAIbAAIIsCSlFgDYAAAbAAIIsCSlFgDYAAAsAAQKgRQAAhsABwgDJQ0eAM4CABsABwgDJQ0eAM4CAAEsAAUUBQgKAAsA9hsA.Shizzy:BAAALAADCggIFAABLAAECggIJwAYAHEcAA==.Shoriah:BAAALAADCgYIDgAAAA==.Shìo:BAACLAAFFIEKAAILAAUI9htsBwDZAQALAAUI9htsBwDZAQAsAAQKgSkAAgsACAi4JbwEAGYDAAsACAi4JbwEAGYDAAAA.',Si='Sid:BAAALAAECgQICAAAAA==.Simsalaknall:BAAALAADCgUIAwAAAA==.Sindorei:BAAALAAECgQIBAAAAA==.Sindrì:BAAALAAECgYICAAAAA==.Sinestra:BAABLAAECoEfAAIEAAgILg8CHACjAQAEAAgILg8CHACjAQAAAA==.Sinta:BAAALAAECgcIDgAAAA==.Sister:BAAALAADCgUIBQAAAA==.Sisterone:BAAALAADCgIIAgAAAA==.Sixdrtydix:BAABLAAECoEgAAIOAAcIkxHjRgC+AQAOAAcIkxHjRgC+AQAAAA==.Sixvaadoo:BAABLAAECoEqAAIOAAgI9RBePQDlAQAOAAgI9RBePQDlAQAAAA==.',Sk='Skie:BAABLAAECoEnAAQaAAgI7RYeKAAAAgAaAAcI3hgeKAAAAgARAAgIexG3aAAbAQAPAAYIpAlvHADrAAAAAA==.Skîndred:BAABLAAECoEVAAIbAAgITSAUHgDOAgAbAAgITSAUHgDOAgAAAA==.',Sl='Slomo:BAAALAADCgUIBQABLAAECgYIFgAbALQjAA==.Slomodemon:BAABLAAECoEWAAIbAAYItCMxRAAsAgAbAAYItCMxRAAsAgAAAA==.Slomokitty:BAAALAAECgEIAQABLAAECgYIFgAbALQjAA==.Slomophob:BAAALAADCggICAABLAAECgYIFgAbALQjAA==.Slomototem:BAAALAAECgUIBgABLAAECgYIFgAbALQjAA==.Sluagh:BAAALAAECggIDAAAAA==.Slîce:BAAALAADCgcIBwAAAA==.',Sm='Smashii:BAAALAAECgUIBgAAAA==.',Sn='Snuden:BAAALAAECgYIBwABLAAECgYIFgAbALQjAA==.',So='Softmage:BAAALAAECgQIBAAAAA==.Soirella:BAAALAADCggIGgAAAA==.Solandra:BAAALAAECgEIAQAAAA==.Solomun:BAAALAADCgYIBgABLAAECgcICAANAAAAAA==.Somira:BAABLAAECoEYAAIRAAgIbhufHwBIAgARAAgIbhufHwBIAgAAAA==.Sonambulo:BAAALAADCgYIBgAAAA==.Soni:BAAALAAECgQICwAAAA==.Sooli:BAAALAAECgMICQAAAA==.Sorn:BAAALAADCgQIBAAAAA==.Sorren:BAAALAAECgMIBQAAAA==.Sowen:BAABLAAECoEYAAQWAAcIvQjCMgCBAQAWAAcIvQjCMgCBAQAVAAcIFwSpmAACAQAXAAIImgPiNwBCAAAAAA==.',St='Stahlfeder:BAAALAADCgEIAQAAAA==.Stealthbraid:BAAALAAECgMIAwAAAA==.Steve:BAABLAAECoEvAAIKAAgIBxqXLABYAgAKAAgIBxqXLABYAgAAAA==.Storolfsson:BAABLAAECoEmAAIBAAgIMyARGgDJAgABAAgIMyARGgDJAgAAAA==.Stuppz:BAABLAAECoEUAAMKAAgI+hOVYACYAQAKAAgIuBGVYACYAQAjAAIIdyTIVgDOAAAAAA==.Styles:BAAALAAECgcIEwABLAAECggIGQAMAMchAA==.',Su='Surayaalisha:BAAALAAECggIEAAAAA==.Surstrômming:BAAALAADCgEIAQAAAA==.',Sy='Syrakus:BAAALAADCggIDwABLAAECgYIBgANAAAAAA==.',['Sâ']='Sânsibar:BAAALAAECggIDgAAAA==.Sârphina:BAAALAAECgYIEgAAAA==.',['Sí']='Sílina:BAAALAAECgQICAAAAA==.Sírinasi:BAAALAADCggICAAAAA==.',Ta='Tahark:BAAALAADCgYIBgAAAA==.Taire:BAAALAADCggICAAAAA==.Taja:BAAALAAECgUIDQAAAA==.Taliesín:BAAALAAECgIIBQAAAA==.Tamaki:BAAALAAECgUICAABLAAECggIGQAMAMchAA==.Tankerella:BAABLAAECoEbAAIjAAYIIyAgGgAuAgAjAAYIIyAgGgAuAgAAAA==.Tarijin:BAAALAAECgcIDgAAAA==.Taurusrex:BAAALAADCgYIBgABLAAECgYIDAANAAAAAA==.',Te='Telchar:BAAALAAFFAMIAwAAAA==.Terrence:BAAALAAECgUIDgAAAA==.',Th='Thalandil:BAAALAADCgcIDgAAAA==.Thalliana:BAAALAAECggICAAAAA==.Thalron:BAAALAADCggIDwAAAA==.Tharom:BAAALAAECgUICAAAAA==.Thheerryy:BAABLAAECoEZAAIWAAcIQRiLGAAXAgAWAAcIQRiLGAAXAgAAAA==.Thimorias:BAAALAAECgIIBAAAAA==.Thorôs:BAAALAADCggIEAAAAA==.Thékron:BAABLAAECoEcAAIaAAcI7RWTMgDFAQAaAAcI7RWTMgDFAQAAAA==.',Ti='Tierlieb:BAABLAAECoEvAAMaAAgI3CBDDAD1AgAaAAgI3CBDDAD1AgAPAAgIURG7DQDCAQAAAA==.Tintaa:BAAALAADCgUIBQAAAA==.Tipsey:BAAALAADCggICAAAAA==.',To='Tobin:BAABLAAECoEvAAMeAAgIDyUKAQBYAwAeAAgIDyUKAQBYAwAKAAMIcg6zuwBxAAAAAA==.Totemine:BAAALAAECgcIEQAAAA==.Totemtom:BAAALAAECgIIAgABLAAECgcIDQANAAAAAA==.',Tr='Trashly:BAABLAAECoEYAAIVAAgISgbQhAA7AQAVAAgISgbQhAA7AQAAAA==.Treamon:BAABLAAECoEeAAIbAAgIBBnPZADTAQAbAAgIBBnPZADTAQAAAA==.Trenbolonus:BAAALAADCggICAAAAA==.Trishâ:BAAALAAECgYIBgAAAA==.Trkzn:BAABLAAECoEWAAQTAAYIHBNxJABBAQATAAUIRhNxJABBAQASAAMIohAYTgDPAAAHAAEITQWgHAAoAAAAAA==.',Tu='Tulana:BAAALAAECgQIDAABLAAECggIBwANAAAAAA==.Turosto:BAABLAAECoEeAAIfAAcI2RspUAAjAgAfAAcI2RspUAAjAgAAAA==.',Ty='Tyramon:BAAALAAECgUICwAAAA==.Tyranion:BAABLAAECoEvAAIRAAgIbiVmBgAaAwARAAgIbiVmBgAaAwAAAA==.',['Tá']='Táya:BAAALAAECgQIDAAAAA==.',['Tú']='Túva:BAAALAAECggIBwAAAA==.',Un='Ungeimpft:BAAALAADCggIIAAAAA==.',Ur='Uraraka:BAAALAADCgcIBwAAAA==.',Va='Vadaría:BAAALAAECgQICAAAAA==.Valeriá:BAAALAAECgYIBgAAAA==.Valkanta:BAAALAAECggICAAAAA==.Vanathel:BAAALAAECggICAAAAA==.Vandania:BAABLAAECoEXAAIBAAYInhzxYADEAQABAAYInhzxYADEAQAAAA==.Vanhagen:BAABLAAECoEoAAMFAAgIQRnlGADKAQAFAAcIuhflGADKAQAbAAcItxPZfACeAQABLAAECggIKQAQADkbAA==.Vanhelsingii:BAAALAADCgEIAQAAAA==.',Vc='Vchronic:BAAALAAECgUIBQAAAA==.',Ve='Velarias:BAAALAADCgEIAQAAAA==.Velox:BAAALAADCgcIDQABLAAECggIJwAYAHEcAA==.Venatri:BAAALAAECgEIAQAAAA==.Vengahl:BAABLAAECoEXAAIOAAgIoxTrNQAHAgAOAAgIoxTrNQAHAgAAAA==.',Vi='Viore:BAAALAAECgUICQABLAAECggIHwAEAC4PAA==.',Vo='Vonda:BAAALAADCgcIBwAAAA==.',Vu='Vuh:BAACLAAFFIEFAAICAAMIDw3nGQC5AAACAAMIDw3nGQC5AAAsAAQKgR4AAgIACAhaGyIpAEoCAAIACAhaGyIpAEoCAAAA.',Wa='Waldhexe:BAABLAAECoElAAQRAAcIPRwqIgA5AgARAAcIPRwqIgA5AgAkAAQI1AYyMgCnAAAaAAYI8A4AAAAAAAAAAA==.Warax:BAAALAADCgYIBgAAAA==.Waytheah:BAABLAAECoEVAAIOAAYIYA2FYwBcAQAOAAYIYA2FYwBcAQAAAA==.',We='Weewoo:BAAALAADCgcIDQABLAAECggIGQAMAMchAA==.Werner:BAAALAAECggICAAAAA==.',Wi='Willibald:BAAALAAECgYIDgAAAA==.',Wo='Woist:BAAALAADCgcIBwAAAA==.Wolfschwanz:BAAALAADCgcIBwABLAAECggIGQAMAMchAA==.Worgtamer:BAABLAAECoEgAAIaAAgI0hxRKgDzAQAaAAgI0hxRKgDzAQAAAA==.',Wr='Wryn:BAAALAAECgYIDAAAAA==.',Wu='Wuschelstern:BAAALAADCgcIEgAAAA==.',Xa='Xaraxi:BAAALAAFFAIIAgABLAAFFAIICgABAAUiAA==.Xayo:BAAALAAECgYICgAAAA==.Xayó:BAAALAADCgYIBgAAAA==.',Xo='Xorath:BAAALAAECgQIBAAAAA==.',Xy='Xylone:BAAALAAECgMIBgAAAA==.',['Xé']='Xéró:BAAALAAECgIIBAAAAA==.',Ye='Yedrin:BAAALAADCggICAABLAAECggILwAeAA8lAA==.',Yh='Yharana:BAAALAADCgMIAwAAAA==.',Yi='Yithra:BAACLAAFFIENAAMHAAIIKCIIAgDKAAAHAAIIKCIIAgDKAAATAAEIQgwhFwBCAAAsAAQKgS4AAwcACAhaJVwAAHcDAAcACAhaJVwAAHcDABMABwhyGNUTAN8BAAAA.',Yo='Youaredead:BAABLAAECoEYAAIVAAcIVRatRQD1AQAVAAcIVRatRQD1AQAAAA==.Yowda:BAAALAAECgQIBAAAAA==.',Yu='Yukimaru:BAAALAADCggICAAAAA==.',['Yó']='Yómie:BAAALAADCgcICwAAAA==.',Za='Zahar:BAAALAADCgcIBwAAAA==.Zahrah:BAAALAAECgYIEAAAAA==.Zakkusu:BAABLAAECoEpAAQQAAgIORsqDQBrAgAQAAgIMBcqDQBrAgALAAgI0hLVmACVAQAlAAcISgsbIgAwAQAAAA==.Zandahli:BAAALAADCgEIAQABLAAECgcIHgAUAF4VAA==.Zarimchen:BAAALAAECgQIBAAAAA==.Zaríma:BAAALAAECgUIBwAAAA==.Zass:BAAALAAECgQICAABLAAECggIJQAWADoeAA==.',Ze='Zeha:BAAALAAECggIDQAAAA==.Zepharus:BAAALAAECgYIEwAAAA==.Zeratule:BAAALAAECgUIBQAAAA==.Zerdales:BAAALAADCgYIBgAAAA==.',Zo='Zorr:BAABLAAECoElAAQWAAgIOh6ECgCkAgAWAAgIOh6ECgCkAgAVAAcIMhaHuwCJAAAXAAEIxAyyNwBDAAAAAA==.',Zu='Zuchiku:BAAALAAECgYIEwAAAA==.Zundhöuzli:BAAALAADCggIDAAAAA==.',['Zê']='Zêna:BAAALAADCgYIBgAAAA==.',['Àr']='Àrios:BAAALAAECgMIBwAAAA==.',['Òd']='Òdi:BAAALAAECgcIFgAAAQ==.Òdì:BAAALAAECgMIAwABLAAECgcIFgANAAAAAQ==.Òdín:BAAALAAECgYIDAABLAAECgcIHAAKAOEYAA==.',['Ôs']='Ôsíris:BAAALAADCgUIBQABLAAECgYIBgANAAAAAA==.',['Õk']='Õk:BAAALAAECgYICAAAAA==.',['Õn']='Õn:BAAALAADCgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end