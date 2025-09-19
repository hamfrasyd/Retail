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
 local lookup = {'Monk-Windwalker','Mage-Arcane','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Warlock-Demonology','Warlock-Destruction','Monk-Brewmaster','Monk-Mistweaver','DemonHunter-Havoc','Hunter-Survival','Mage-Frost','Rogue-Assassination','Rogue-Outlaw','Evoker-Preservation',}; local provider = {region='EU',realm='Balnazzar',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abilio:BAAALAAECgQIDAAAAA==.',Ac='Actionspeax:BAAALAAECgYIBwAAAA==.',Al='Alexdk:BAAALAADCggICAAAAA==.Alexmonk:BAAALAAECgcICQAAAA==.Alustia:BAAALAAECgUIBgAAAA==.Alyzina:BAAALAADCgcIBwABLAAECgcIFAABAPcjAA==.',Am='Amalia:BAABLAAECoEUAAICAAcItxx6JgA+AgACAAcItxx6JgA+AgAAAA==.Amyncloud:BAAALAAECgMIBQAAAA==.',An='Animall:BAAALAADCggICAABLAADCggICQADAAAAAA==.',Ar='Arakiel:BAAALAAECgYICQAAAA==.',As='Asteria:BAAALAAECgYICgAAAA==.',Av='Avicus:BAAALAAECgMIBQAAAA==.',Be='Beolon:BAAALAADCgYIBgAAAA==.',Bi='Bill:BAAALAADCggICAAAAA==.Biola:BAAALAADCgcIBwAAAA==.',Bo='Borntrue:BAAALAAECgEIAQAAAA==.',Br='Brunost:BAAALAAECgYIDAAAAA==.',Ca='Castrol:BAAALAAECgQIBAAAAA==.',Ch='Chayen:BAAALAAECgYIDgAAAA==.',Co='Coonan:BAAALAAECgMIBAAAAA==.',Cr='Crofyz:BAABLAAECoEVAAIEAAcIhxP8IwDWAQAEAAcIhxP8IwDWAQAAAA==.',Da='Damsugare:BAAALAAECgIIAgAAAA==.Darkblade:BAAALAADCggICAAAAA==.',De='Deano:BAAALAADCgYIBgAAAA==.Demonizer:BAAALAADCgQIAQAAAA==.Demonnuggie:BAAALAAECgcIEwABLAAECgcIFAABAPcjAA==.Demontriox:BAAALAADCgcIDQAAAA==.',Dr='Dracaris:BAAALAADCgcIBwAAAA==.Drizzydk:BAAALAAECgMIAwAAAA==.',Du='Dumsomensten:BAAALAADCggICQAAAA==.',Dw='Dwarftusken:BAAALAADCggICAAAAA==.',Ee='Eetwatti:BAAALAAECgYIEgAAAA==.',El='Eldris:BAAALAADCgYIBQAAAA==.',Eu='Euraia:BAAALAAECgIIAgAAAA==.',Ez='Ezioc:BAAALAADCggICAAAAA==.',Fe='Fen:BAAALAAECgYIDwAAAA==.',Fi='Filletheone:BAAALAADCggICAAAAA==.',Fl='Flowdk:BAAALAADCgYIBgAAAA==.',Fr='Frostmoon:BAABLAAECoEbAAIFAAgI3R8LGACfAgAFAAgI3R8LGACfAgAAAA==.',Ga='Garalos:BAAALAAECgYIEgAAAA==.',Gi='Gilford:BAAALAAECgYIDwAAAA==.',Gl='Gloriana:BAAALAAECgMIBQAAAA==.',Gr='Greybeard:BAABLAAECoEZAAMGAAgIuSEeAwDyAgAGAAgIuSEeAwDyAgAHAAcI9h/4gQBMAAAAAA==.Gruldrak:BAAALAADCgcIBwAAAA==.',Ha='Haadés:BAAALAADCgcIBgAAAA==.Halyn:BAAALAADCgYIBgAAAA==.Hate:BAAALAADCggIBwABLAAECgYICwADAAAAAA==.',He='Hethym:BAAALAAECgQIBQAAAA==.',Hu='Hutao:BAABLAAECoEeAAMBAAgIDiTOAgA1AwABAAgIDiTOAgA1AwAIAAEIxxEAAAAAAAAAAA==.',Hy='Hyrsretwo:BAAALAADCgUIBQAAAA==.',['Hé']='Héllwhisper:BAABLAAECoEUAAIBAAcI9yNrBgDSAgABAAcI9yNrBgDSAgAAAA==.',Ji='Jingim:BAAALAADCgcIBwAAAA==.',Jo='Jox:BAABLAAECoEXAAMJAAcIFRuwCwAsAgAJAAcIFRuwCwAsAgABAAEIlAGPQQAKAAAAAA==.',Ka='Kaladin:BAAALAAECgQIBQAAAA==.Kawamury:BAAALAADCgEIAQAAAA==.',Ke='Kepster:BAAALAADCgcICwAAAA==.',Kh='Khalley:BAAALAAECgYIEAAAAA==.Khalltusken:BAAALAADCggICAAAAA==.',Kl='Klæssesnabb:BAAALAAECgcICgAAAA==.',Kn='Knas:BAAALAAECgYICwAAAA==.',Ko='Koase:BAAALAAECggIDAAAAA==.',Kr='Kratos:BAAALAAECgQIBQAAAA==.',Ku='Kukbe:BAAALAAECgYIDAAAAA==.',La='Larra:BAAALAAECgYIBgAAAA==.',Li='Lilanka:BAAALAADCgYIBgAAAA==.Lissa:BAACLAAFFIEFAAIKAAQIrQR/BQAUAQAKAAQIrQR/BQAUAQAsAAQKgRsAAgoACAiOICIQAOMCAAoACAiOICIQAOMCAAAA.',Lu='Luppious:BAAALAADCgUIBQAAAA==.',Me='Mentally:BAAALAAECgMIAwAAAA==.Metsämies:BAAALAADCgcIBwAAAA==.',Mi='Midnight:BAAALAADCggICAAAAA==.Milva:BAAALAADCggICQAAAA==.Mirannda:BAAALAADCgcIBwAAAA==.Misshyper:BAAALAAECgMIBgAAAA==.',Mo='Monkyman:BAAALAADCgQIBgAAAA==.Moreeca:BAAALAAECgcIDAAAAA==.Mosees:BAAALAADCgcIBwAAAA==.',Ms='Msi:BAAALAAECgMIBQAAAA==.',Mu='Murhamies:BAAALAADCgcIDQAAAA==.',['Mö']='Mörkö:BAACLAAFFIEHAAILAAQITiESAACgAQALAAQITiESAACgAQAsAAQKgRwAAgsACAgMJwEAALYDAAsACAgMJwEAALYDAAAA.',Na='Nalindax:BAAALAADCggICAAAAA==.Narrak:BAAALAADCggICwAAAA==.',Ne='Nevedora:BAAALAADCgUICAAAAA==.',No='Nolli:BAAALAADCgMIAwAAAA==.',Nw='Nw:BAAALAADCggIFgAAAA==.',Ny='Nymeria:BAAALAAECgYIDQAAAA==.',On='Onyx:BAAALAADCggIDwAAAA==.',Op='Opie:BAAALAAECgcIEgAAAA==.',Oz='Ozzy:BAAALAADCgMIAwAAAA==.',['Oê']='Oêll:BAAALAAECgMIBQAAAA==.',Pa='Patriarkka:BAAALAADCgQIBQAAAA==.',Pe='Pestilence:BAAALAADCgcIBwAAAA==.',Pu='Punk:BAAALAADCggICAAAAA==.Punkdafunk:BAABLAAECoEfAAIKAAgI2Bt2FQCzAgAKAAgI2Bt2FQCzAgAAAA==.',Qu='Queldorai:BAAALAAECgYIEAABLAAECggIGwAFAN0fAA==.Quias:BAAALAADCggIDwAAAA==.',Ra='Rasko:BAAALAADCggICAAAAA==.',Re='Renwell:BAAALAADCgEIAQAAAA==.',Sa='Saleyn:BAAALAADCgIIAgABLAAECggIEwADAAAAAA==.Samistar:BAAALAADCgYIBgAAAA==.Sassy:BAAALAAECgYICAAAAA==.Sayajin:BAAALAADCgcIBwABLAAECggIGwAFAN0fAA==.',Sd='Sdg:BAAALAAECgYIEgAAAA==.',Sh='Shirael:BAAALAAECggIEwAAAA==.',Si='Sinon:BAABLAAECoEWAAIMAAcI/BpzDgA+AgAMAAcI/BpzDgA+AgAAAA==.',Sk='Skelmage:BAAALAAECgEIAQABLAAECgYIFAANAFEaAA==.Skelmon:BAAALAADCggICAABLAAECgYIFAANAFEaAA==.Skeltor:BAABLAAECoEUAAMNAAYIURptHgDHAQANAAYIURptHgDHAQAOAAEIfwTMEwArAAAAAA==.Skoff:BAAALAADCggIEQAAAA==.',Sl='Slopp:BAAALAAECgcIEwAAAA==.Slæggetryne:BAAALAADCgIIAgAAAA==.',Sn='Snerkz:BAAALAAECgYIEwAAAA==.',Sp='Spaztíc:BAAALAAECggIDwAAAA==.',St='Standardat:BAAALAAECgcIEQAAAA==.',Sy='Sypha:BAAALAAECgYICQAAAA==.',Ta='Tandefelt:BAABLAAECoEaAAIPAAgIPyP/AAA1AwAPAAgIPyP/AAA1AwAAAA==.Tanith:BAAALAAECgMIAwAAAA==.',Te='Telenara:BAAALAAECgMIBgAAAA==.Tera:BAAALAAECgcIEAAAAA==.',To='Tommy:BAAALAAECgUICQAAAA==.',Us='Useable:BAAALAAECgIIAQAAAA==.',Va='Vampirekiss:BAAALAADCggIDgAAAA==.Vanerion:BAAALAADCgcICQAAAA==.',Vi='Vicaria:BAAALAAECgMIBQAAAA==.Vinerion:BAAALAADCgcIBwAAAA==.',Vp='Vphunter:BAAALAADCgEIAQAAAA==.',Za='Zagan:BAAALAAECgMIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end