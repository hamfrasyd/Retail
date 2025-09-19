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
 local lookup = {'Unknown-Unknown','Rogue-Assassination','Mage-Arcane','Priest-Holy','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Mage-Frost','Rogue-Subtlety',}; local provider = {region='EU',realm="Vek'nilash",name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abysmöl:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.Abyssos:BAAALAADCgcIBwAAAA==.',Ae='Aertheas:BAAALAAECggIEQAAAA==.',Ag='Agitar:BAAALAADCggICAAAAA==.',Ah='Aholymoly:BAAALAAECgcIEQAAAA==.',Ai='Aiman:BAAALAAECgcIEAAAAA==.Aionir:BAAALAAECgYIDgAAAA==.',Al='Alsyana:BAAALAAECgcICAAAAA==.',An='Anathemaa:BAAALAAECgYIBgAAAA==.',Ar='Arabélla:BAAALAAECgEIAQAAAA==.Aradenox:BAAALAAECgUIAgAAAA==.Arckie:BAAALAAECgYICAABLAAECggIFQACAF0eAA==.Arrowplume:BAAALAAECgEIAQAAAA==.',As='Ashie:BAABLAAECoEUAAIDAAcITyFJEACmAgADAAcITyFJEACmAgAAAA==.Astrida:BAAALAAECgYIBgAAAA==.',Au='Audran:BAAALAAECggIEQAAAA==.',Az='Azrael:BAAALAAECgYIBgAAAA==.',Ba='Bamvandam:BAAALAADCggIDAAAAA==.',Be='Beamzz:BAAALAADCggICAABLAAECggIFQACAF0eAA==.Bedste:BAAALAADCggICAAAAA==.Belindo:BAAALAADCgUIBQAAAA==.Bennyboo:BAAALAAECgMIBAAAAA==.',Bi='Bigboned:BAAALAADCgMIAwABLAAECggIFQACAF0eAA==.',Bl='Blippi:BAAALAAECgcIDgAAAA==.',Br='Brakkar:BAAALAAECgMIBQAAAA==.Brewplum:BAAALAAECgIIAgAAAA==.',Ca='Cairneblood:BAAALAAECgYICwAAAA==.Catesi:BAAALAAECgcIEAAAAA==.',Ce='Cesiana:BAAALAAECgYICgAAAA==.',Ch='Charlamagne:BAAALAADCggICAAAAA==.Chíe:BAAALAAECgIIAgAAAA==.',Ci='Ciezar:BAAALAAECgYICwAAAA==.Ciirith:BAAALAAECgcIDwABLAAECggIFwAEACMVAA==.Cindia:BAABLAAECoEUAAIEAAcIIRXNHgC6AQAEAAcIIRXNHgC6AQAAAA==.Cirithi:BAABLAAECoEXAAIEAAgIIxWXEQAzAgAEAAgIIxWXEQAzAgAAAA==.',Cs='Cspr:BAAALAADCggIEQAAAA==.',Da='Dakamar:BAAALAAECgQIBAAAAA==.Danogoza:BAAALAAECgYIDgAAAA==.Dartha:BAAALAADCgIIAgABLAAECgcIFAAFAAUVAA==.',De='Deadbaldman:BAAALAAECgYIDAABLAAECggIFQAFALUgAA==.Deadbullz:BAAALAADCgYIBwAAAA==.Deadtroll:BAAALAAECgYIBgAAAA==.Denma:BAAALAAECgcIEAAAAA==.',Di='Diesiraee:BAAALAAECgYICwAAAA==.',Dr='Drakereaper:BAAALAADCgIIAgAAAA==.Drakor:BAAALAAECgYIBgAAAA==.Drangkor:BAAALAADCgcIEgAAAA==.Drevo:BAAALAADCgUIBQAAAA==.Druamina:BAAALAAECgYICQABLAAECggIEQABAAAAAA==.Drukhan:BAABLAAECoEXAAMGAAgIlCTkAgDCAgAGAAcI9yPkAgDCAgAHAAYIWSLuEABTAgAAAA==.Drustme:BAAALAADCggICAAAAA==.',Du='Durzoblínt:BAAALAADCgcIBwAAAA==.',El='Elementary:BAAALAAECgEIAQAAAA==.',Es='Eshonai:BAAALAAECgYICgAAAA==.Esselie:BAAALAADCgcIBwAAAA==.',Ev='Evoky:BAAALAAECgYICQAAAA==.',Ey='Eyljire:BAAALAAECgYICwAAAA==.',Fa='Faekitty:BAAALAAECgIIAgAAAA==.Faelarin:BAAALAAFFAIIAgAAAA==.Farmd:BAAALAAECgcIEgAAAA==.',Fe='Feldemon:BAAALAADCgIIAgAAAA==.',Fi='Fistrurum:BAAALAADCggICAAAAA==.',Fl='Flurry:BAAALAAECgMIAwAAAA==.',Fr='Frostfiend:BAAALAADCgcIDQAAAA==.',Fu='Fusr:BAAALAADCgcIBwAAAA==.',Ga='Galdokter:BAAALAADCgIIAgAAAA==.',Gi='Gingerclaw:BAAALAAECgcIEQAAAA==.',Go='Goracysoczek:BAAALAAFFAIIAgAAAA==.',Gr='Graardor:BAABLAAECoEVAAIFAAgItSAdBwD+AgAFAAgItSAdBwD+AgAAAA==.Grarzer:BAABLAAECoEUAAIFAAcIBRXiGgDvAQAFAAcIBRXiGgDvAQAAAA==.Grendel:BAAALAAECgIIAgAAAA==.Groktar:BAAALAAECgIIAwAAAA==.Grommdhne:BAAALAAECgEIAQAAAA==.',Ha='Haldír:BAAALAAECgYICwAAAA==.',He='Heal:BAAALAADCggIBwAAAA==.Hellsminion:BAAALAADCgYIBgAAAA==.',In='Initia:BAABLAAECoETAAIIAAcIyQokFwCHAQAIAAcIyQokFwCHAQAAAA==.',Io='Ioth:BAAALAAECgYICwAAAA==.',Ip='Ipalock:BAAALAAECgEIAQAAAA==.',Iv='Ivym:BAAALAAECgcIEgAAAA==.',Ja='Jakasi:BAAALAADCgMIAwABLAAECgYICwABAAAAAA==.',Ju='Juice:BAAALAAFFAIIAgAAAA==.',Ka='Kaleca:BAAALAAECgYIDAAAAA==.Kalii:BAAALAAECgUIAgAAAA==.',Ke='Kerppa:BAAALAADCgcIEwAAAA==.',Kh='Khirgan:BAAALAADCggICAAAAA==.',Ki='Kiwiwi:BAAALAAECgcIEQAAAA==.',Ko='Kosimazaki:BAAALAAECgYICQAAAA==.',Ky='Kyberflame:BAAALAADCgcIBwAAAA==.Kyoko:BAAALAAECgQIBgAAAA==.',Le='Leggy:BAAALAADCgcIBwABLAAECggIFQACAF0eAA==.',Li='Lid:BAAALAADCggICAAAAA==.',Lo='Lodowysoczek:BAABLAAECoEXAAIDAAgIRyOVBAAyAwADAAgIRyOVBAAyAwAAAA==.',Ma='Mageyoulook:BAAALAADCgcIBwAAAA==.Magnac:BAAALAADCgcIDgAAAA==.',Me='Meambemexd:BAAALAAECgIIAgAAAA==.Mebladey:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Medjig:BAAALAAECgcIEgAAAA==.Melthao:BAAALAADCgcIBwAAAA==.Mercc:BAAALAAECgYICwAAAA==.',Mi='Milkers:BAAALAAECgMIAwABLAAECggIFQAFALUgAA==.',Mo='Moomiin:BAAALAAECggIDgAAAA==.',Na='Nada:BAAALAADCggICAAAAA==.',Ne='Nerdié:BAAALAADCgMIAwAAAA==.',Ni='Nikkola:BAABLAAECoEXAAIFAAcIWSAEEQBeAgAFAAcIWSAEEQBeAgAAAA==.Nish:BAAALAAECgIIAgAAAA==.',No='Noveria:BAAALAAECgEIAQAAAA==.',Ol='Olgin:BAAALAADCggIFwAAAA==.',On='Ono:BAAALAADCgYICAAAAA==.',Or='Orukk:BAAALAAECgYIDAAAAA==.',Ou='Outlul:BAABLAAECoEVAAMCAAgIXR70CQCPAgACAAcIER/0CQCPAgAJAAIIihLIEgCSAAAAAA==.',Ow='Owocek:BAAALAAECgYICwAAAA==.',Pa='Pangtong:BAAALAADCgQIBAAAAA==.',Pe='Petrichor:BAAALAADCggIDwAAAA==.',Pi='Pished:BAAALAADCggICAAAAA==.',Pl='Plia:BAAALAADCgQIBgAAAA==.',Po='Polonikoo:BAAALAAECgMIAwAAAA==.Polstre:BAAALAADCgYICAAAAA==.',Ps='Psychoboo:BAAALAAECgUICQAAAA==.',Pu='Pulsár:BAAALAAECgMIBgAAAA==.Punish:BAAALAAECgYICQAAAA==.',Qu='Quillenar:BAAALAADCgMIAwABLAAECgYICQABAAAAAA==.',Re='Reuven:BAAALAAECgYIDAAAAA==.',Rh='Rhododendron:BAAALAAECgIIBAAAAA==.',Ri='Riker:BAAALAADCgcICAAAAA==.',Ru='Rustbucket:BAAALAAECgYICwAAAA==.',Ry='Rysiu:BAAALAADCggICAAAAA==.',Rz='Rza:BAAALAAECgYICgAAAA==.',Sh='Shadowbleak:BAAALAADCgcICwAAAA==.Shasseem:BAAALAAECgYICQAAAA==.',Si='Siphaman:BAAALAAECgcIEAAAAA==.Sipharrior:BAAALAAECgMIBQABLAAECgcIEAABAAAAAA==.',Sn='Snuffit:BAAALAADCgIIAgAAAA==.',Sp='Splashdaddy:BAAALAAECgIIAgAAAA==.',Su='Superhick:BAAALAADCggIFgAAAA==.',Sw='Swiftknigth:BAAALAADCggIDgAAAA==.Swiftyholy:BAAALAADCgYICQAAAA==.Swiftypala:BAAALAADCgIIAgAAAA==.Swiftyshaman:BAAALAADCgcIBwAAAA==.Swyfegosa:BAAALAADCggICAAAAA==.',Sy='Sythini:BAAALAADCggIDQAAAA==.',Ta='Talar:BAAALAAECgEIAQAAAA==.Tanzar:BAAALAAECgYICwAAAA==.',Ti='Titanhold:BAAALAAECgMIBgAAAA==.',To='Toko:BAAALAADCggICAAAAA==.Torik:BAABLAAECoEWAAIDAAgIVRoQGgBKAgADAAgIVRoQGgBKAgAAAA==.',Ty='Typo:BAAALAADCgcIBwAAAA==.',Va='Varkarra:BAAALAADCgYIBgAAAA==.Vatkap:BAAALAAECgcIDgAAAA==.',Ve='Vexáhlia:BAAALAADCgMIAwAAAA==.',Vo='Voidhammer:BAAALAADCgcIBwAAAA==.',Wa='Warlockz:BAAALAAECgQIBwAAAA==.',We='Weirdié:BAAALAADCgMIAwABLAADCgcIEwABAAAAAA==.',Wo='Wokandroll:BAAALAAECgEIAQAAAA==.',Za='Zajeczyca:BAAALAAECgMIBwAAAA==.Zapper:BAAALAADCgQIBAAAAA==.Zarmin:BAAALAAECgYIBwAAAA==.',Ze='Zenadin:BAAALAAECgQIBQAAAA==.Zenaku:BAAALAADCggICAAAAA==.Zeno:BAAALAAECgYIDAAAAA==.',Zu='Zulteraa:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Zy='Zylarx:BAAALAADCggIDgAAAA==.',['ßo']='ßoid:BAAALAAECgMIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end