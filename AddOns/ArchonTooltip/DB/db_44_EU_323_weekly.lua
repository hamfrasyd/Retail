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
 local lookup = {'Warrior-Fury','Warrior-Protection','Warrior-Arms','DemonHunter-Havoc','Unknown-Unknown','Rogue-Outlaw','Mage-Frost','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Druid-Restoration','Paladin-Retribution','Evoker-Preservation','Mage-Arcane','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Hunter-BeastMastery','Monk-Brewmaster','Paladin-Protection','Hunter-Marksmanship','Evoker-Augmentation','Shaman-Elemental','Mage-Fire','Druid-Feral','Monk-Windwalker','Monk-Mistweaver','Priest-Holy','Priest-Discipline','DemonHunter-Vengeance','Druid-Balance','DeathKnight-Blood','Shaman-Enhancement','Paladin-Holy',}; local provider = {region='EU',realm='Runetotem',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abraxis:BAAALAAECggICAAAAA==.',Ac='Achlyss:BAAALAAECggICQAAAA==.Acornius:BAAALAADCgUIBQAAAA==.',Ad='Adrastos:BAAALAADCgcICwAAAA==.',Ae='Aearthonn:BAAALAADCgcIDgAAAA==.Aelyra:BAAALAAECgYIBgAAAA==.Aerandir:BAAALAADCggIFgAAAA==.',Aj='Ajira:BAAALAAECgYIBQAAAA==.',Al='Aladruid:BAAALAAECgcIDwAAAA==.Aledra:BAAALAADCgcIBwAAAA==.Alfdis:BAAALAADCggIBwAAAA==.Allidár:BAAALAAECgUICAAAAA==.Alrock:BAAALAADCgcICwAAAA==.Alsfury:BAAALAADCgcIBwAAAA==.',Am='Amanily:BAACLAAFFIEHAAIBAAMI+hNTDwD/AAABAAMI+hNTDwD/AAAsAAQKgSUABAEACAg0IAgnAG4CAAEACAjSGwgnAG4CAAIABghuG8QhAOgBAAMAAgjrEVgoAHYAAAAA.Amis:BAACLAAFFIEGAAIEAAIIdxImKQCYAAAEAAIIdxImKQCYAAAsAAQKgSkAAgQACAgsIHcYAOkCAAQACAgsIHcYAOkCAAAA.',An='Anisha:BAAALAADCgQIAQABLAAECggIGQAFAAAAAA==.Anumet:BAAALAADCggIKQAAAA==.Anyie:BAAALAADCgcICgAAAA==.',Ar='Arcanál:BAAALAAECggICQAAAA==.Aro:BAABLAAECoEgAAIGAAcIUyRTAgDnAgAGAAcIUyRTAgDnAgAAAA==.',As='Asurian:BAAALAAECgYIBgAAAA==.',Au='Audentia:BAAALAADCgcIBwAAAA==.',Av='Avocadoo:BAAALAAECggICAAAAA==.',Ay='Ayori:BAAALAADCgcIBwAAAA==.Ayosa:BAAALAAECgYIBgABLAAFFAMICQAHAOEdAA==.Ayy:BAACLAAFFIESAAMIAAUI9SVJAQAjAgAIAAUITSRJAQAjAgAJAAMI3SVVBQA+AQAsAAQKgSYAAwgACAi6JksAAIcDAAgACAiWJksAAIcDAAkACAh3JTAFACADAAAA.',Az='Azun:BAAALAADCggIDQAAAA==.',Ba='Baani:BAAALAADCggILAAAAA==.Babski:BAAALAADCgYIBgAAAA==.Babyhunter:BAAALAAECgMIAwAAAA==.Bacovia:BAAALAAECgYICAAAAA==.Bananabread:BAAALAADCgcIBwAAAA==.Baniin:BAAALAADCgQIBgAAAA==.Barnetv:BAABLAAECoEXAAIKAAgI1gOvwwC0AAAKAAgI1gOvwwC0AAABLAAECggIIwALAMwUAA==.',Be='Bearly:BAAALAAECgcIDQAAAA==.Beary:BAAALAADCgcICgABLAAECgQIBgAFAAAAAA==.Benafflic:BAAALAAECgYIBgAAAA==.Bendover:BAAALAADCggIDAAAAA==.Bergur:BAACLAAFFIEFAAIMAAIIFCBbFwC+AAAMAAIIFCBbFwC+AAAsAAQKgRsAAgwABwg5IFxXAAoCAAwABwg5IFxXAAoCAAAA.Berhar:BAAALAADCgMIAwAAAA==.',Bi='Bifor:BAAALAADCgMIAwAAAA==.Bigibono:BAACLAAFFIEGAAIKAAIIUxRoKwCAAAAKAAIIUxRoKwCAAAAsAAQKgRkAAgoACAh2E7hMAMcBAAoACAh2E7hMAMcBAAAA.Biz:BAAALAAECgYIBwAAAA==.',Bl='Blackweaver:BAAALAAECgMICQAAAA==.Blazko:BAABLAAECoEZAAINAAcI3ST6AwDxAgANAAcI3ST6AwDxAgAAAA==.Blazkov:BAAALAADCgEIAQAAAA==.Blinkyflaps:BAABLAAECoEUAAIOAAcIjB0LPQAxAgAOAAcIjB0LPQAxAgAAAA==.',Bo='Bobrockss:BAABLAAECoEUAAIBAAcI4x+uIQCOAgABAAcI4x+uIQCOAgAAAA==.Bobsidian:BAAALAAECgYIDgAAAA==.Boints:BAAALAADCggICAAAAA==.Boogíe:BAAALAADCgYIBgAAAA==.Booly:BAAALAAECgYIBwABLAAECgcIDQAFAAAAAQ==.Bottoms:BAAALAADCggIDQAAAA==.',Br='Branch:BAAALAADCgcIBwAAAA==.Brauer:BAEALAAFFAIIAgAAAA==.Brewsle:BAAALAAECgYIBwAAAA==.Brewzea:BAAALAAECgUIDwAAAA==.',Bu='Bulbasaur:BAAALAAECgQIBAAAAA==.',Bz='Bzerk:BAABLAAECoEYAAIBAAgIxRvxKgBXAgABAAgIxRvxKgBXAgABLAAECgUICwAFAAAAAA==.',['Bé']='Béndover:BAAALAADCgUIBQAAAA==.',Ca='Calisea:BAAALAADCggICAAAAA==.Carmine:BAAALAADCgMIAwAAAA==.Caviar:BAAALAAECgUIBgAAAA==.',Ce='Celenia:BAAALAADCgcIBwAAAA==.Ceret:BAAALAAECggIEwAAAA==.',Ch='Chetu:BAAALAADCgYIBgAAAA==.Chianna:BAAALAAECgIIAgAAAA==.Chisdk:BAAALAADCgcIDgAAAA==.Chocolate:BAABLAAECoEVAAIPAAcIwhgJKwADAgAPAAcIwhgJKwADAgAAAA==.Chrissassin:BAAALAAECgQICQABLAAECgcIEgAFAAAAAA==.Chunckgt:BAAALAAECgcIEgAAAA==.',Ci='Cindergore:BAAALAAECgYIDAAAAA==.Ciresika:BAAALAADCgcIDQAAAA==.',Co='Coldstuff:BAABLAAECoEZAAIOAAcIfRtSRgAPAgAOAAcIfRtSRgAPAgAAAA==.Comar:BAABLAAECoEeAAMQAAcIPxCnHAC6AQAQAAcIPxCnHAC6AQARAAQIogLOIAF4AAAAAA==.Coolbreezer:BAEALAADCgcIBwABLAAFFAIIAgAFAAAAAA==.',Cr='Creeps:BAAALAADCgMIAwAAAA==.Croon:BAAALAAECggICwAAAA==.',Cy='Cyn:BAAALAADCgUICAAAAA==.Cyphor:BAAALAAECgEIAQAAAA==.Cyrasil:BAAALAAECgUICgABLAAECgYICgAFAAAAAA==.',Da='Dallerion:BAAALAAECgEIAQAAAA==.Danisha:BAAALAAECgcIEwAAAA==.Darkryu:BAAALAAECggIDQAAAA==.',De='Delimar:BAAALAADCggIEAAAAA==.Delimina:BAAALAAECgYICgAAAA==.Demonhunter:BAAALAAECgMIAwAAAA==.Demoninside:BAACLAAFFIEIAAMSAAMIJRJ7GADsAAASAAMIJRJ7GADsAAATAAIIWQNkFwBvAAAsAAQKgSEABBIACAjdG88hAJgCABIACAjdG88hAJgCABMABAgOFh1VAOoAABQAAQirE/Q1AEYAAAAA.Demonoctris:BAAALAADCgUIBQAAAA==.Dentydh:BAAALAADCggICgABLAAECggIEwAFAAAAAA==.Deusbelli:BAAALAADCggICAABLAAECgYIEAAFAAAAAA==.',Di='Diblo:BAAALAADCggICwAAAA==.',Dj='Djasper:BAAALAADCgcIEwABLAAECggIKAARAH4dAA==.',Do='Donius:BAABLAAECoEgAAILAAgIEyNDBQAmAwALAAgIEyNDBQAmAwAAAA==.Dontexist:BAAALAAECgYICQAAAA==.',Dr='Drav:BAACLAAFFIEJAAISAAUIWRnFCADYAQASAAUIWRnFCADYAQAsAAQKgSUABBIACAiEJC4HAE4DABIACAgEJC4HAE4DABQABQhiI/0NALQBABMAAQiUJnVxAHEAAAAA.Drgndeeznuts:BAACLAAFFIEKAAIVAAMI0h+nCAAeAQAVAAMI0h+nCAAeAQAsAAQKgSgAAhUACAjWJQ4BAHsDABUACAjWJQ4BAHsDAAAA.Drogkala:BAAALAAECgYICwAAAA==.Drélmordah:BAAALAAECgcIDgAAAA==.',Du='Duckmuncher:BAAALAAECgYIDgAAAA==.Dutchiedemon:BAABLAAECoEVAAIEAAgIRxGjXQDcAQAEAAgIRxGjXQDcAQAAAA==.',Ea='Earlhero:BAABLAAECoEaAAIDAAcIkhQPDQDhAQADAAcIkhQPDQDhAQAAAA==.',Eb='Ebani:BAAALAADCggIDgAAAA==.',Ed='Edgy:BAAALAADCggICAAAAA==.',El='Eleanorah:BAAALAADCggIDwAAAA==.Electroboy:BAAALAAECgYICwAAAA==.Ellarose:BAAALAADCgcIBwAAAA==.',Em='Emistrasza:BAAALAAECgQIBgAAAA==.Emlin:BAAALAADCgIIAgABLAAECgQIBgAFAAAAAA==.Emmitatress:BAAALAADCgYIBgABLAAECggIFQALAIoNAA==.Emmophilist:BAAALAADCggIHwAAAA==.Emmorously:BAAALAADCgcIBwAAAA==.Emméline:BAABLAAECoEVAAILAAgIig3dSgB0AQALAAgIig3dSgB0AQAAAA==.Emphasis:BAAALAADCgUICgAAAA==.',En='Enrie:BAAALAADCgIIAgAAAA==.Entillani:BAAALAADCgcIBwAAAA==.',Eo='Eomer:BAABLAAECoEZAAIWAAYI/iEnTADwAQAWAAYI/iEnTADwAQAAAA==.',Er='Eros:BAAALAADCggICAAAAA==.',Et='Ethelfleda:BAAALAADCgQIBAAAAA==.',Ex='Excathedra:BAAALAAECgYICgAAAA==.Exodarious:BAAALAAECggICwAAAA==.',Fa='Faeblade:BAAALAADCggICAAAAA==.Falli:BAAALAADCggICAAAAA==.Farty:BAAALAAECgYICgAAAA==.',Fe='Felmiracle:BAACLAAFFIEVAAIEAAYIZRmwAgBGAgAEAAYIZRmwAgBGAgAsAAQKgS8AAgQACAiVJZ4FAGEDAAQACAiVJZ4FAGEDAAAA.Felscourge:BAACLAAFFIEGAAIEAAIIvxFDKwCWAAAEAAIIvxFDKwCWAAAsAAQKgSsAAgQACAjfHjUjAK0CAAQACAjfHjUjAK0CAAAA.',Fl='Flett:BAABLAAECoEXAAIUAAcIjwfNEwBfAQAUAAcIjwfNEwBfAQAAAA==.',Fu='Fulgrim:BAAALAADCggICAAAAA==.Fumanchu:BAAALAADCgQIBAAAAA==.',['Fð']='Fðrgë:BAAALAAECgIIAgAAAA==.',Ga='Garlicc:BAAALAAECggICQAAAA==.',Ge='Gefeltafish:BAABLAAECoEYAAIPAAgIgxjHJgAeAgAPAAgIgxjHJgAeAgAAAA==.',Gh='Ghouloncé:BAAALAAECgYIDQAAAA==.',Gi='Giezer:BAABLAAECoEVAAIXAAYI1hLZIABQAQAXAAYI1hLZIABQAQAAAA==.',Go='Golbríng:BAAALAAECgUIBgAAAA==.Gordzgrey:BAABLAAECoEaAAIYAAcIRBQgIwCaAQAYAAcIRBQgIwCaAQAAAA==.Goshunt:BAACLAAFFIEHAAMWAAMIiiRvCgA9AQAWAAMIiiRvCgA9AQAZAAIICQlaIwBzAAAsAAQKgSUAAxYABwgaJZwSAO8CABYABwgaJZwSAO8CABkABwikG4coABICAAAA.',Gr='Granithe:BAAALAADCgYIAQAAAA==.Grasgon:BAABLAAECoEgAAMaAAcIhxk9BgAAAgAaAAcIehc9BgAAAgAVAAYI/xcKLACZAQAAAA==.Greatshaman:BAAALAAECgUIDQAAAA==.Greensausage:BAABLAAECoEjAAIbAAgIqRIbNQADAgAbAAgIqRIbNQADAgAAAA==.Grimjaw:BAAALAADCggICAAAAA==.Grotz:BAABLAAECoEVAAISAAYIxhwHQgD7AQASAAYIxhwHQgD7AQAAAA==.',Gu='Gudmund:BAAALAADCggIDgAAAA==.Gudulf:BAAALAADCgcIBwAAAA==.Gulkaren:BAAALAAECgYIEQAAAA==.Gulldan:BAAALAADCgYIBgAAAA==.',Ha='Hamdomri:BAAALAADCgMIAwAAAA==.Harú:BAAALAADCgYICAAAAA==.Haunt:BAAALAADCgIIAgABLAAECgEIAQAFAAAAAA==.',He='Heavenhealer:BAAALAADCgYIBgAAAA==.Heladøkinder:BAAALAAECgEIAQAAAA==.Helliek:BAAALAADCggICAAAAA==.Hexual:BAAALAAECggIDgAAAA==.',Hi='Hiela:BAABLAAECoEZAAIcAAcILAcYCwBPAQAcAAcILAcYCwBPAQAAAA==.Hiightopp:BAAALAADCgMIAwAAAA==.Hilmoon:BAAALAAECgYIBgAAAA==.',Hu='Huginnmuninn:BAABLAAECoEbAAIEAAYIFAJO8gB5AAAEAAYIFAJO8gB5AAAAAA==.Hunkilii:BAAALAADCgIIAgAAAA==.Hunterboots:BAAALAAECgYIEgAAAA==.Hutta:BAABLAAECoEfAAMWAAcIPBx8NQA8AgAWAAcIPBx8NQA8AgAZAAYIMw+NWwAsAQAAAA==.',Hy='Hyacinth:BAACLAAFFIEJAAIHAAMI4R24AgARAQAHAAMI4R24AgARAQAsAAQKgSsAAwcACAjJI94EADEDAAcACAjJI94EADEDAA4AAQhIA8rdAC0AAAAA.Hydros:BAAALAADCgEIAQAAAA==.',Ic='Icewind:BAAALAAECgYIEwAAAA==.Icewindius:BAAALAADCggICAAAAA==.Icyhunter:BAAALAADCgcIBwAAAA==.',Ik='Ikheetmouse:BAAALAADCgUIBgAAAA==.',Il='Ildiko:BAABLAAECoEWAAIKAAYIbBWQaQB2AQAKAAYIbBWQaQB2AQAAAA==.Ilium:BAAALAADCggIDQABLAAECgYIDgAFAAAAAA==.',Im='Impatience:BAAALAADCggICAABLAAECgYICQAFAAAAAA==.',In='Innz:BAAALAADCgQIBAAAAA==.Inubis:BAAALAAECgYIBgAAAA==.',Ja='Jacobroed:BAAALAAECggIDQAAAA==.',Je='Jemmox:BAAALAADCggICAAAAA==.',Jj='Jjholy:BAAALAAECggIDQAAAA==.',Jo='Joeexotic:BAABLAAECoEZAAIdAAcIHRt6DgA6AgAdAAcIHRt6DgA6AgAAAA==.Johana:BAAALAADCgUIBQAAAA==.Johnnerzul:BAAALAADCggICAAAAA==.',Ju='Jullice:BAABLAAECoElAAMeAAgIrwrgLABlAQAeAAgIrwrgLABlAQAfAAcIDw6/IgBXAQAAAA==.Justicemercy:BAAALAADCgcIEQAAAA==.Jutem:BAAALAADCggICAAAAA==.',Jw='Jwéel:BAAALAAECgUICAAAAA==.',['Jø']='Jøe:BAAALAADCgcIDQAAAA==.',Ka='Kackobacko:BAAALAAECggICAAAAA==.Kadath:BAABLAAECoEcAAIgAAcIxhs/JQA1AgAgAAcIxhs/JQA1AgAAAA==.Karakun:BAAALAADCggIFgABLAAECggIHQAbAPgUAA==.Karamb:BAAALAADCgQICAAAAA==.Karanda:BAAALAADCgIIAgAAAA==.Karenblixen:BAAALAADCgYICAAAAA==.Karn:BAAALAADCgcICgAAAA==.Karrav:BAAALAAECgYIDAAAAA==.Kawaiitiran:BAAALAADCgcIBwABLAAECgYIDgAFAAAAAA==.Kaytam:BAAALAADCgQIBAAAAA==.',Kh='Khalraz:BAAALAAECggICAAAAA==.',Ki='Kianie:BAAALAAECggICAAAAA==.Kinkyrasta:BAAALAAECggICAAAAA==.Kitlord:BAAALAADCgcIBwAAAA==.',Kl='Klooas:BAACLAAFFIERAAICAAUIrxgGAwDAAQACAAUIrxgGAwDAAQAsAAQKgSEAAgIACAhIJeEBAGsDAAIACAhIJeEBAGsDAAAA.',Kn='Kneel:BAAALAAECgMIAwAAAA==.Knuppel:BAABLAAECoEVAAIbAAgIBxhvJABeAgAbAAgIBxhvJABeAgAAAA==.Knuppelster:BAAALAAECgQIBgABLAAECggIFQAbAAcYAA==.Knurf:BAAALAADCgQIBAAAAA==.',Kr='Krissz:BAAALAAECggIEwAAAA==.Kroellboell:BAAALAAECgIIAgAAAA==.Kråka:BAAALAAECgEIAQAAAA==.',La='Lahn:BAABLAAECoEcAAIWAAcI8CM3HQCuAgAWAAcI8CM3HQCuAgAAAA==.Lat:BAABLAAECoEoAAIRAAgIfh1RLgCOAgARAAgIfh1RLgCOAgAAAA==.Lavadude:BAAALAADCggICAAAAA==.',Le='Lecolas:BAAALAADCggICAAAAA==.Lehuge:BAAALAADCgUIBQAAAA==.Lemonparty:BAAALAADCgIIAgABLAADCgUICgAFAAAAAA==.Lemuria:BAAALAAECgYICQAAAA==.',Li='Liandrah:BAABLAAECoEkAAMOAAcI4BWaUwDjAQAOAAcI4BWaUwDjAQAHAAMI2QQUaAB5AAAAAA==.Linflas:BAAALAAECgEIAQAAAA==.Litzi:BAACLAAFFIEJAAIgAAMIrQ2oEADfAAAgAAMIrQ2oEADfAAAsAAQKgSsAAiAACAhdGesgAFACACAACAhdGesgAFACAAAA.Lizzii:BAAALAAECgYIBgABLAAFFAMICQAgAK0NAA==.',Lo='Lockias:BAAALAADCgQIBAAAAA==.Lorran:BAAALAAECggICwAAAA==.',Lu='Luffy:BAAALAAECgUICgAAAA==.Luther:BAAALAADCggICAAAAA==.Luvi:BAAALAAECgQIBAABLAAECgYIBgAFAAAAAA==.',Lv='Lvs:BAABLAAECoEZAAIbAAcIrQJVgADUAAAbAAcIrQJVgADUAAAAAA==.',Ly='Lyns:BAABLAAECoEkAAIbAAgIKiL9DAATAwAbAAgIKiL9DAATAwAAAA==.',Ma='Macallan:BAAALAAECgYICAAAAA==.Maddock:BAAALAADCggIEAAAAA==.Madeleine:BAAALAAECgYICwAAAA==.Madkard:BAAALAADCggIDQAAAA==.Madlokk:BAAALAADCggIEgAAAA==.Madmardigan:BAAALAADCggIDwAAAA==.Madziz:BAAALAADCgUIBQABLAADCggICAAFAAAAAA==.Magickaren:BAACLAAFFIENAAMOAAYIHRM5BwDmAQAOAAYIrw45BwDmAQAcAAMI8xxQAQATAQAsAAQKgSUAAxwACAgvI0UBAAwDABwACAh8IUUBAAwDAA4ACAivIKsSAAEDAAAA.Mark:BAAALAAECgYIBgAAAA==.Markuslol:BAAALAADCgcIBwABLAAECggIFAARAMYbAA==.Maulers:BAAALAAECgcIDAAAAA==.Maz:BAAALAAFFAIIAgABLAAFFAYIFAAbALIfAA==.',Me='Meepmeep:BAAALAADCgYIBgABLAAFFAMIBwABAPoTAA==.Method:BAAALAADCggIGwAAAA==.Metot:BAAALAAECgYICgAAAA==.',Mi='Mightythor:BAAALAADCgcIDgAAAA==.Milochan:BAAALAADCgUIBQAAAA==.',Mo='Moccamaster:BAAALAAECggICAAAAA==.Moia:BAAALAAECgYIBgAAAA==.Mommy:BAAALAADCgcICAAAAA==.Monkarina:BAAALAAECgYICQAAAA==.Monsterenerg:BAAALAADCgIIAgABLAAFFAIIBgAEAL8RAA==.Moogul:BAAALAAECgIIAwAAAA==.Moonmilk:BAAALAAECgYIBgAAAA==.Moonpearl:BAAALAADCgQIBAAAAA==.Mortine:BAAALAADCggIEAAAAA==.',Mu='Mua:BAAALAADCgQIBAAAAA==.Mufi:BAABLAAECoElAAQOAAgImhswNwBJAgAOAAgIGhgwNwBJAgAHAAYIXxY6MgCDAQAcAAEIRgtiHQA3AAAAAA==.Mukkerr:BAAALAADCgMIAwAAAA==.',My='Myzorth:BAAALAAECggIDgAAAA==.',Na='Nachsas:BAAALAADCggICAAAAA==.Nariane:BAAALAADCggIDQAAAA==.Navaros:BAAALAADCgUIBQAAAA==.Naãri:BAAALAAECgcIBwABLAAFFAIICAASAMoTAA==.',Nh='Nhala:BAABLAAECoEXAAIBAAgIUgjsaABzAQABAAgIUgjsaABzAQAAAA==.Nhs:BAACLAAFFIEGAAIPAAII5iJZDwDMAAAPAAII5iJZDwDMAAAsAAQKgTwAAw8ACAguJmMBAIEDAA8ACAguJmMBAIEDACEAAgh1IGYeALMAAAAA.',Ni='Nielaa:BAAALAADCgcIBwAAAA==.Nightbreezer:BAEALAADCggIEAABLAAFFAIIAgAFAAAAAA==.Nikephoros:BAAALAAECggICAAAAA==.Nipha:BAAALAAECgYICwAAAA==.',No='Noaddon:BAAALAADCgEIAQAAAA==.Nogoodtank:BAAALAADCgEIAQAAAA==.',Nu='Nualinn:BAAALAADCgYIAQAAAA==.Nuriel:BAAALAADCgcIDgABLAAECggIHQAbAPgUAA==.',['Né']='Néana:BAABLAAECoEZAAIBAAcIDhSrSQDUAQABAAcIDhSrSQDUAQAAAA==.',Od='Odeseiron:BAABLAAECoEcAAIgAAgIthxaEwCwAgAgAAgIthxaEwCwAgAAAA==.',Og='Oggsie:BAAALAAECgIIAQAAAA==.',Oh='Ohnaur:BAABLAAECoEUAAIJAAgIlxThGwAhAgAJAAgIlxThGwAhAgAAAA==.',On='Oneshöt:BAAALAAECgUIBQAAAA==.Ongelukkige:BAAALAAECgEIAQAAAA==.',Op='Oprãwindfury:BAAALAADCgcIBwABLAAFFAIICAASAMoTAA==.',Or='Ordys:BAAALAADCgcIBwAAAA==.',Os='Oscars:BAAALAADCgYIBwAAAA==.Osirian:BAAALAADCgEIAQAAAA==.Ossia:BAAALAAECgYIDwAAAA==.',Pa='Palanary:BAABLAAECoEYAAMMAAgI1CGoFAAKAwAMAAgI1CGoFAAKAwAYAAUITBAdOgD5AAAAAA==.Panzonfist:BAABLAAECoEfAAIeAAgI5xmTEQBmAgAeAAgI5xmTEQBmAgAAAA==.Pappason:BAAALAADCggIAgABLAADCggIBwAFAAAAAA==.Pavelow:BAAALAAECgIIAgAAAA==.',Pe='Percepeus:BAAALAADCgIIAgAAAA==.Perceus:BAAALAADCgYIBwAAAA==.Percival:BAAALAADCgYIDAAAAA==.Persy:BAAALAAECgMIAwAAAA==.Pewspews:BAAALAAECgMIAwAAAA==.',Ph='Phantaleon:BAAALAAECgIIAgAAAA==.',Pi='Piimp:BAACLAAFFIEIAAISAAIIyhPmJgCdAAASAAIIyhPmJgCdAAAsAAQKgUEABBIACAj3HdEdALECABIACAiJHdEdALECABQAAwhGEKQgAMQAABMAAwguE85fALkAAAAA.Pinkhelmet:BAAALAADCgcIAgAAAA==.',Pj='Pjuskelusken:BAAALAADCgMIAwAAAA==.',Po='Polymilf:BAAALAADCggIDAABLAAFFAIICAASAMoTAA==.Posuna:BAAALAADCggICAAAAA==.',Pr='Pra:BAAALAAECgEIAQAAAA==.',Ps='Psychogamer:BAAALAAECgMIAwAAAA==.',Pu='Pultsari:BAAALAADCggICQABLAAECggIHgALAAQXAA==.',['Pâ']='Pânico:BAACLAAFFIEMAAIBAAUIYBp7BAD1AQABAAUIYBp7BAD1AQAsAAQKgTIAAwEACAh2JncBAIcDAAEACAhsJncBAIcDAAMAAQj5JrEoAHMAAAAA.',Qu='Qualudes:BAAALAAECgYIDwAAAA==.Quazzar:BAAALAAECgcIDQAAAA==.',Ra='Raevn:BAAALAAECgcIDgAAAA==.Ragnaror:BAAALAAECgUIBQAAAA==.Rakhsham:BAABLAAECoEaAAMbAAcIxBXdOADxAQAbAAcIxBXdOADxAQAKAAQINhbppQDtAAAAAA==.Rambok:BAABLAAECoEVAAMOAAcI/xwNTwDxAQAOAAcI/xwNTwDxAQAcAAEIvSHpFgBZAAAAAA==.Ranzog:BAAALAADCggICgAAAA==.Rapciune:BAAALAADCgYIBgAAAA==.Rash:BAAALAAECgcICAAAAA==.Raupthasar:BAAALAAECggIDAAAAA==.Raziyya:BAAALAADCggICAAAAA==.',Re='Reivax:BAAALAAECgcIDAABLAAFFAIICAASAMoTAA==.Relani:BAAALAAECgMIAwABLAAECggIFAACAGoiAA==.Revokes:BAABLAAECoElAAMiAAcIqiNvBwDDAgAiAAcIqiNvBwDDAgAEAAYI0RX0pABEAQAAAA==.',Ri='Rimari:BAAALAAECgYIDAAAAA==.Rio:BAABLAAECoEsAAMcAAgIZyGnAQDtAgAcAAgIZyGnAQDtAgAOAAUIuBr0hgBQAQAAAA==.Ripix:BAABLAAECoEXAAIWAAYIYSCtPQAdAgAWAAYIYSCtPQAdAgAAAA==.',Ro='Roshía:BAAALAAFFAIIAgAAAA==.Rowën:BAAALAAECgYIBgABLAAFFAIICAALALkjAA==.',Ru='Rullepølsen:BAACLAAFFIEFAAIeAAII8w8QDQCTAAAeAAII8w8QDQCTAAAsAAQKgSUAAh4ACAj2INsKAMYCAB4ACAj2INsKAMYCAAAA.Rumner:BAABLAAECoEwAAIKAAgIxhajPwDwAQAKAAgIxhajPwDwAQAAAA==.',Ry='Rysz:BAAALAADCggICQAAAA==.Ryuken:BAAALAAECgEIAQAAAA==.',['Ró']='Róshia:BAABLAAECoEjAAMjAAgIcBZqJAAQAgAjAAgIcBZqJAAQAgALAAcIJgTpeADjAAABLAAFFAIIAgAFAAAAAA==.',Sa='Sammyshamm:BAAALAADCgYIBgAAAA==.Sauron:BAAALAAECgYIEAAAAA==.',Se='Selidon:BAAALAAECgcICwAAAA==.Semenmachine:BAAALAADCgUIBQAAAA==.Semenmachiné:BAAALAADCgYIBgAAAA==.',Sh='Shadowfury:BAAALAADCggICAABLAAECgQICQAFAAAAAA==.Shamdak:BAAALAAECgYIBwAAAA==.Shamren:BAACLAAFFIEKAAIKAAUIhBobBACzAQAKAAUIhBobBACzAQAsAAQKgR8AAgoACAjuHJYcAH8CAAoACAjuHJYcAH8CAAAA.Shapke:BAAALAAECgYIBwAAAA==.Shaquonda:BAAALAAECggIEwABLAAFFAYIDQAOAB0TAA==.Shattercleft:BAABLAAECoEcAAMRAAcIFgiktABeAQARAAcIFgiktABeAQAQAAUIdAJDPgCwAAAAAA==.Shazaar:BAAALAAECgcIEwAAAA==.Shazman:BAAALAADCgYIBgAAAA==.Sheroni:BAAALAAECgQIAgAAAA==.Shivh:BAAALAAECgYIEQABLAAFFAYICQASAFkZAA==.Shjarn:BAABLAAECoEfAAIHAAcIQx/NEAB4AgAHAAcIQx/NEAB4AgAAAA==.Shroomshaman:BAABLAAECoEiAAIbAAgIbhxBGgCmAgAbAAgIbhxBGgCmAgAAAA==.Sháqel:BAAALAAECgYICAAAAA==.',Si='Sigmundrr:BAAALAADCgcIEgABLAAECggIHAAgALYcAA==.',Sk='Skjerabagera:BAAALAAECggIEAAAAA==.Skjip:BAABLAAECoEUAAIEAAgIwBcCNwBSAgAEAAgIwBcCNwBSAgAAAA==.Skrul:BAAALAAECgEIAQAAAA==.',Sl='Slowbzz:BAABLAAECoEUAAIRAAcINhjwdgDNAQARAAcINhjwdgDNAQAAAA==.',Sm='Smorc:BAABLAAECoEpAAIRAAgIKCWeDQAtAwARAAgIKCWeDQAtAwABLAAFFAMICgAVANIfAA==.',So='Sonel:BAAALAAECgYICAAAAA==.Sonje:BAAALAADCgYIBgAAAA==.',Sp='Spicyandcoke:BAAALAAECgMIBQAAAA==.Spiffi:BAABLAAECoEgAAIGAAgIegUwEAAeAQAGAAgIegUwEAAeAQAAAA==.Spiritclaws:BAAALAAECgUIBQABLAAECggIHQAbAPgUAA==.Spúddy:BAABLAAECoEoAAIWAAgIpCJrEAD+AgAWAAgIpCJrEAD+AgAAAA==.',St='Stelf:BAAALAADCgcIDQAAAA==.Stigma:BAABLAAECoEUAAICAAgIaiKtCwDFAgACAAgIaiKtCwDFAgAAAA==.Støckholm:BAAALAAECgMIAwAAAA==.',Su='Subzey:BAAALAADCgQIBAAAAA==.',Sw='Swag:BAABLAAECoEUAAIBAAgICh/6FgDZAgABAAgICh/6FgDZAgAAAA==.Sweetlaugh:BAAALAAECgIIAgAAAA==.',Sz='Sztuk:BAAALAAECggICQAAAA==.',['Sá']='Sáhal:BAACLAAFFIEFAAIkAAMILgsiBwC9AAAkAAMILgsiBwC9AAAsAAQKgSEAAiQACAhSFcQTANQBACQACAhSFcQTANQBAAAA.',['Sè']='Sèlèct:BAACLAAFFIETAAISAAYIZA6ECADcAQASAAYIZA6ECADcAQAsAAQKgS8ABBIACAi8IVMPABEDABIACAi8IVMPABEDABQABwgIEGQNAL8BABMAAghUGh9sAIUAAAAA.',Ta='Tamatori:BAAALAAECgYIBgAAAA==.Tandora:BAAALAAECggICAAAAA==.Tangustan:BAAALAAECgIIAgAAAA==.Taranus:BAABLAAECoEdAAMbAAgI+BSmMQAUAgAbAAgI9hKmMQAUAgAlAAYIIBJ5EwB+AQAAAA==.Tarnauk:BAAALAAECgYICAAAAA==.Tauria:BAABLAAECoEYAAIPAAcInRLRMgDXAQAPAAcInRLRMgDXAQAAAA==.',Te='Tempestade:BAAALAAECgIIAwAAAA==.Teneen:BAAALAADCggICAAAAA==.',Th='Theonekalle:BAAALAADCgMIAwAAAA==.Thordun:BAAALAADCggICAAAAA==.Thordön:BAABLAAECoEVAAICAAcIAQ9vNABuAQACAAcIAQ9vNABuAQAAAA==.Thorkild:BAAALAADCgMIAwAAAA==.Thundergrave:BAAALAAECgYIEQAAAA==.Thuradin:BAAALAAECgQIDgAAAA==.Thórin:BAAALAADCgcIBwAAAA==.',Ti='Tinka:BAAALAAECgEIAQAAAA==.Tinkerbox:BAAALAAECgYIBgAAAA==.Tinkerrella:BAAALAADCggICgAAAA==.Tinyy:BAAALAAECggIEQAAAA==.',To='Torine:BAAALAAECgcICAAAAA==.Totemfutt:BAAALAADCggIDwAAAA==.',Tr='Traditor:BAAALAADCgMIAwABLAAECgQIBAAFAAAAAA==.Trolletotem:BAAALAAECgMIBAABLAAECggIHgAmAEEeAA==.Tryn:BAABLAAECoEaAAILAAcIAQ/IUgBXAQALAAcIAQ/IUgBXAQAAAA==.Träsket:BAAALAADCgcIDAAAAA==.',Tu='Tummi:BAAALAADCggIHQAAAA==.',Ty='Tyronus:BAAALAAECgcIBwAAAA==.Tyry:BAABLAAECoEXAAIhAAcI5BpkBgArAgAhAAcI5BpkBgArAgAAAA==.',['Tà']='Tàvore:BAAALAAECgIIAgAAAA==.',Um='Umar:BAAALAADCgcIDAAAAA==.Umber:BAAALAADCgcIAwAAAA==.',Un='Undeadmoomoo:BAAALAAECgYIEAAAAA==.',Ur='Ureass:BAAALAADCggIBwAAAA==.Ursoll:BAAALAADCgYIBgAAAA==.',Uz='Uzzi:BAAALAADCgcIDgAAAA==.',Va='Vacä:BAAALAADCgMIAwAAAA==.Vaelthion:BAAALAADCggIEAAAAA==.Valamagi:BAAALAADCgcIDwABLAAECgcIIAAEACkkAA==.Valanor:BAABLAAECoEgAAIEAAcIKSSdGwDWAgAEAAcIKSSdGwDWAgAAAA==.Valkria:BAAALAAECgcIEQAAAA==.Vallmar:BAABLAAECoEpAAMZAAgIux0/FQCiAgAZAAgIux0/FQCiAgAWAAIIJBJA8QBhAAAAAA==.Vanitas:BAAALAADCgcIBwAAAA==.',Ve='Venali:BAAALAADCgYICgABLAAECgYICAAFAAAAAA==.',Vh='Vhaidra:BAAALAAECgYIBgAAAA==.',Vi='Vildvittra:BAAALAAECgYIDAAAAA==.Vipsen:BAAALAADCgcIBwAAAA==.',Vo='Voliwood:BAAALAAECgIIAgAAAA==.Voltarwulf:BAAALAADCggIDgAAAA==.Voodoobob:BAAALAADCgcIBwAAAA==.',Wa='Walockgirl:BAAALAAECgYIDQAAAA==.',We='Wenbrandt:BAAALAAECgEIAQAAAA==.Wetlettuce:BAABLAAECoEbAAIbAAcIiyHFGgCiAgAbAAcIiyHFGgCiAgAAAA==.',Wh='Whiteweaver:BAAALAAECgMIAgAAAA==.',Wi='Wildar:BAAALAADCgYIBgAAAA==.Wimdu:BAAALAAECggICgAAAA==.Wimsp:BAAALAAECggICAAAAA==.Wisnix:BAAALAAECgcIEQAAAA==.',Xr='Xróth:BAAALAADCgcIBwAAAA==.',Ye='Yelaara:BAAALAADCggICQAAAA==.',Yn='Ynk:BAAALAAECggIBwAAAA==.Ynks:BAAALAADCggICgAAAA==.',Ys='Yseraa:BAAALAADCggICAAAAA==.',Za='Zadicz:BAAALAAECgIIAgAAAA==.Zagarna:BAAALAAECgMIAwABLAAECggIHgAUAPQbAA==.Zalwina:BAAALAAECgYIBgAAAA==.Zardu:BAAALAAECgYICgAAAA==.Zayvon:BAAALAADCgcIBwAAAA==.Zaza:BAAALAADCgcIEgAAAA==.',Ze='Zeborg:BAAALAAECgcICgAAAA==.Zerobyte:BAAALAADCggICAAAAA==.Zesummoner:BAAALAAECgEIAQAAAA==.',Zi='Ziru:BAAALAAECggIEAAAAA==.',Zo='Zorinn:BAAALAAECgYIDwAAAA==.Zorua:BAAALAAECgcIBwABLAAECggIKAAWAKQiAA==.',Zr='Zrgje:BAAALAAECggICAAAAA==.',['Üw']='Üwü:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end