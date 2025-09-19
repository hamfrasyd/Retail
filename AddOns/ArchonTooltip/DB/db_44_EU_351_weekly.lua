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
 local lookup = {'Warrior-Fury','Unknown-Unknown','Evoker-Devastation','Paladin-Retribution','Hunter-Marksmanship','DeathKnight-Blood','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','Shaman-Enhancement','Shaman-Elemental','Hunter-Survival','Priest-Holy','Priest-Discipline','Druid-Balance','Mage-Arcane',}; local provider = {region='EU',realm='Vashj',name='EU',type='weekly',zone=44,date='2025-08-30',data={Aa='Aaravos:BAAALAAFFAIIBAABLAAFFAYIDQABAP8eAA==.',Ae='Aegor:BAAALAADCggICAAAAA==.',Af='Affena:BAAALAAECgIIAgAAAA==.',Ai='Ai:BAAALAADCggIEAAAAA==.',Ak='Aknana:BAAALAADCgEIAQAAAA==.',Al='Aldrakith:BAAALAADCgMIBgAAAA==.',An='Andarr:BAAALAAECgYICwAAAA==.',Ap='Apocaliptus:BAAALAAECgYIDgAAAA==.',Ar='Arr:BAAALAADCgIIAgABLAAECgUICAACAAAAAA==.',As='Ashpri:BAAALAAECgUIBQAAAA==.',At='Atonement:BAAALAAECgcICgAAAA==.',Ba='Baaphomet:BAAALAAECgYIDAAAAA==.',Bo='Bosso:BAAALAAECgYIDAAAAA==.Bossodh:BAAALAAECgcICQAAAA==.Bossoe:BAACLAAFFIEJAAIDAAUITh+ZAADxAQADAAUITh+ZAADxAQAsAAQKgRYAAgMACAjrJhQAAJ8DAAMACAjrJhQAAJ8DAAAA.Bossom:BAAALAAECgYIBgAAAA==.',Br='Broderplupp:BAAALAAECgYIBgAAAA==.Brutanaz:BAAALAAECgcIDwAAAA==.',Bu='Budmaash:BAAALAADCgcIBwAAAA==.',Ch='Charliegreen:BAAALAADCgIIAgAAAA==.',Cr='Crypthia:BAAALAAECggICgAAAA==.',De='Deathiscomin:BAAALAADCgcIDAAAAA==.Demonfarter:BAAALAADCgYICAAAAA==.Depressed:BAAALAADCggICAABLAAECgYIBgACAAAAAA==.',Do='Dorrak:BAAALAADCgQIBAAAAA==.',Du='Dumrak:BAAALAADCgcIBwAAAA==.',Ek='Ekriz:BAAALAAECgYIDgAAAA==.',El='Elarune:BAAALAADCgcIBwAAAA==.Elashia:BAAALAAECgYIEgAAAA==.Eloth:BAAALAADCgcIBwABLAAECgYIDgACAAAAAQ==.Elwind:BAAALAAECgcIEQAAAA==.',Er='Ere:BAAALAAECgEIAQAAAA==.Eredin:BAABLAAECoEWAAIEAAgIcB8ADADNAgAEAAgIcB8ADADNAgAAAA==.Erise:BAAALAADCggICAAAAA==.',Fe='Felran:BAAALAAECgYIDAABLAAFFAUICwAFAG0jAA==.Fenar:BAAALAAECgcIBwAAAA==.',Fl='Floorpov:BAAALAADCggICAAAAA==.',Fr='Fraile:BAAALAADCgMIBgAAAA==.',Fs='Fsj:BAACLAAFFIELAAIGAAUIQhk9AADjAQAGAAUIQhk9AADjAQAsAAQKgRgAAgYACAj6JAMBAFADAAYACAj6JAMBAFADAAAA.',Ga='Gallox:BAAALAADCggIEAAAAA==.',Go='Gothgf:BAAALAADCggIDwABLAAECgYIBgACAAAAAA==.',Gr='Grzegorz:BAAALAAECgMIBQAAAA==.',Gu='Gurumage:BAAALAAECgMIBQAAAA==.Guruwl:BAAALAAECgMIBAAAAA==.',He='Hedan:BAAALAAECgEIAQAAAA==.',In='Intix:BAAALAADCggICAAAAA==.',Js='Jsf:BAAALAAECgYIDAAAAA==.',Ju='Julmajoni:BAAALAAFFAIIAgAAAA==.',Ka='Kaidron:BAAALAAECggIFwAAAQ==.Karsta:BAACLAAFFIEGAAIHAAMI7B5XAQAgAQAHAAMI7B5XAQAgAQAsAAQKgRgAAgcACAh0IzQBAC8DAAcACAh0IzQBAC8DAAAA.Kate:BAAALAAECgYICwAAAA==.',Ki='Kitkatt:BAAALAAECgYIDAAAAA==.',Kr='Kratos:BAABLAAFFIENAAIBAAYI/x4DAACQAgABAAYI/x4DAACQAgAAAA==.Krukesh:BAAALAAECgcIBwAAAA==.',Ku='Kuparipilli:BAAALAADCgcIBwAAAA==.',Kw='Kwaaiseun:BAAALAAECgYIAwAAAA==.',Le='Lemmudin:BAAALAAECgEIAQAAAA==.Leqa:BAAALAAFFAIIAgAAAA==.',Li='Lightphoenix:BAAALAAECgcICgAAAA==.Liny:BAACLAAFFIELAAIIAAUIYhwoAADpAQAIAAUIYhwoAADpAQAsAAQKgRgAAggACAhgJjcAAI4DAAgACAhgJjcAAI4DAAAA.',Lo='Lost:BAAALAAECgYIBgAAAA==.',Ly='Lynna:BAAALAADCgcIBwAAAA==.',Ma='Madcan:BAAALAADCgcIBwAAAA==.Magekko:BAAALAAECggICAAAAA==.Malfurion:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.Malkeenian:BAAALAADCggICAAAAA==.Malzahar:BAAALAADCgYIBgAAAA==.Mansicki:BAAALAADCgYIBgAAAA==.Marcicia:BAAALAADCgcIBwAAAA==.',Mi='Mimtan:BAAALAAECgcIBwAAAA==.Misfire:BAAALAAECgYIDgAAAQ==.Mithrina:BAAALAAECgYIDgAAAA==.',Mo='Monkstronk:BAAALAAECgUICAAAAA==.Morena:BAAALAAECgcIBwAAAA==.',Mu='Muikkukukko:BAAALAADCggICAAAAA==.Murduck:BAAALAAECgMIBQAAAA==.',Na='Nanu:BAAALAADCgUIBQAAAA==.',Ne='Nesai:BAAALAADCggICAAAAA==.',No='Noodle:BAACLAAFFIEFAAMJAAMIChKYBQCyAAAJAAIIQxOYBQCyAAAKAAEImA9VAQBfAAAsAAQKgRQAAgkACAi1GgAJAKICAAkACAi1GgAJAKICAAAA.',Ny='Nyhm:BAAALAADCgYIBgAAAA==.',['Nô']='Nôstradamus:BAAALAAECgcIDgAAAA==.',Od='Oddislajos:BAACLAAFFIEHAAIJAAMIzB1+AQAqAQAJAAMIzB1+AQAqAQAsAAQKgRgAAgkACAhSJOsAAF4DAAkACAhSJOsAAF4DAAAA.',Oh='Ohalvaro:BAAALAADCgYIBgAAAA==.',Om='Omageo:BAAALAADCggIDwAAAA==.Omgifoundyou:BAAALAADCgcIBwAAAA==.',Pa='Panja:BAAALAAECgYIDgAAAA==.Parrupaavali:BAAALAAECgYIDgAAAA==.',Pe='Penny:BAAALAAECgYICwAAAA==.',Ph='Pho:BAAALAADCggICAAAAA==.',Pi='Picklock:BAAALAAECgMICAAAAA==.',Po='Poker:BAAALAADCggIDwAAAA==.',Pr='Prestigé:BAAALAAECgYIDAAAAA==.Prixy:BAAALAADCggIDwAAAA==.Proxante:BAAALAAECgEIAQAAAA==.Proxus:BAAALAADCggICgAAAA==.Prutq:BAAALAAECggICAAAAA==.',Qa='Qaeril:BAAALAAECgYIBgABLAAFFAUICwAFAG0jAA==.',Ra='Ranfel:BAACLAAFFIELAAIFAAUIbSMyAAAHAgAFAAUIbSMyAAAHAgAsAAQKgRgAAgUACAh3JdsBADkDAAUACAh3JdsBADkDAAAA.',Ro='Rontti:BAAALAADCggICQAAAA==.',Sa='Sacrae:BAAALAADCgcIDAAAAA==.Saftsusme:BAAALAAECgYIDAAAAA==.Sanniti:BAAALAAECgYIBgAAAA==.Santalokki:BAAALAAECgYICQAAAA==.Saskia:BAABLAAECoEXAAMLAAgIbSBiAQAFAwALAAgIbSBiAQAFAwAMAAMIBBEUQQCqAAAAAA==.',Sh='Shinjo:BAAALAAECgMIBAAAAA==.Shynee:BAAALAADCggICAABLAAECgYIBgACAAAAAA==.',Si='Sillis:BAAALAAECgUICAAAAA==.',Sk='Skorm:BAABLAAFFIEGAAINAAIIgBJ9AAC6AAANAAIIgBJ9AAC6AAABLAAFFAYIDQABAP8eAA==.',Sl='Sleepy:BAAALAAECgYIBgAAAA==.Slerbad:BAAALAAECgYIBgAAAA==.Slerbaevoker:BAAALAAECgcICQAAAA==.Slerbamonk:BAAALAAFFAEIAQAAAA==.Slerbapriest:BAACLAAFFIEHAAIOAAQInAsHAQBQAQAOAAQInAsHAQBQAQAsAAQKgRYAAw4ACAhHFswQADwCAA4ACAhHFswQADwCAA8AAQjsASEeAB0AAAAA.',So='Solaro:BAAALAADCgYIBgABLAAECgEIAQACAAAAAA==.Souw:BAAALAAECgcIDwAAAA==.',St='Stommz:BAACLAAFFIEGAAIQAAQI/Bx1AACUAQAQAAQI/Bx1AACUAQAsAAQKgRgAAhAACAhlJosAAIADABAACAhlJosAAIADAAAA.',Te='Tear:BAAALAAECggIDAAAAA==.Terranostra:BAAALAAECgYICwAAAA==.',To='Toolzhaman:BAAALAAECgYICAAAAA==.Toolzy:BAAALAADCgcIBwABLAAECgYICAACAAAAAA==.Torsház:BAAALAADCgQIBAAAAA==.',['Tö']='Törsky:BAAALAAECggICAAAAA==.',Ve='Vengance:BAAALAAECgYIDAAAAA==.',Vi='Vixxen:BAAALAADCgMIBgAAAA==.',Vr='Vryndar:BAAALAAECgYIDAAAAA==.',Xe='Xewe:BAAALAAECgcIEAAAAA==.',Xi='Xirev:BAABLAAECoEkAAIRAAgIjSahAAB/AwARAAgIjSahAAB/AwAAAA==.',Xy='Xydru:BAAALAAECgMIAwABLAAECgYIDgACAAAAAA==.',Za='Zanza:BAAALAADCgcIBwABLAAFFAYIDQABAP8eAA==.Zatinth:BAAALAAECgEIAQAAAA==.',Zu='Zugchoochoo:BAAALAAECgcIBwAAAA==.',['Öö']='Ööke:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end