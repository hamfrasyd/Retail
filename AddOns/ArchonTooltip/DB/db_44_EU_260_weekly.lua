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
 local lookup = {'Mage-Arcane','Monk-Windwalker','Priest-Holy','Hunter-Marksmanship','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','Hunter-BeastMastery','Evoker-Devastation','Rogue-Assassination','DeathKnight-Frost','Paladin-Holy','Paladin-Retribution','Unknown-Unknown','Warlock-Demonology','Monk-Brewmaster','Monk-Mistweaver','Paladin-Protection','DeathKnight-Blood','DemonHunter-Havoc','Hunter-Survival','Mage-Frost','Rogue-Subtlety','Rogue-Outlaw','DeathKnight-Unholy','Warrior-Protection','Druid-Restoration','Shaman-Enhancement','Evoker-Preservation','Warrior-Fury',}; local provider = {region='EU',realm='Balnazzar',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abilio:BAAALAAECgQIDwAAAA==.',Ac='Actionspeax:BAAALAAECgYIDgAAAA==.',Al='Alexdk:BAAALAADCggICAAAAA==.Alexmonk:BAAALAAECgcICQAAAA==.Alustia:BAAALAAECgUIBgAAAA==.Alxen:BAAALAAECgYICgABLAAFFAMICAABAIIXAA==.Alyzina:BAAALAAECgYICwABLAAECggIHQACAGwjAA==.',Am='Amalia:BAABLAAECoEcAAIBAAgIKxsVLwBtAgABAAgIKxsVLwBtAgAAAA==.Amyncloud:BAAALAAECgMIBQAAAA==.',An='Animall:BAAALAADCggICgAAAA==.',Ar='Arakiel:BAABLAAECoEbAAIDAAgIyyYjAACdAwADAAgIyyYjAACdAwABLAAECggIGwADAN0mAA==.',As='Asteria:BAABLAAECoETAAIEAAgI8BCnOgCwAQAEAAgI8BCnOgCwAQAAAA==.',Av='Avicus:BAAALAAECgMIBQAAAA==.',Az='Azhila:BAAALAADCgUIAQAAAA==.',Be='Beolon:BAAALAADCggIFgAAAA==.',Bi='Bill:BAAALAADCggICAAAAA==.Biola:BAAALAADCgcIEwAAAA==.',Bl='Blinktonight:BAAALAAECggICAAAAA==.',Bo='Borntrue:BAAALAAECgQIBAAAAA==.Bors:BAAALAADCggICAAAAA==.',Br='Brunost:BAAALAAECgYIEgAAAA==.',Ca='Castrol:BAAALAAECgQIBAAAAA==.',Ch='Chao:BAAALAAECgcICgAAAA==.Chayen:BAABLAAECoEeAAIDAAgIdRcxIwBCAgADAAgIdRcxIwBCAgAAAA==.',Co='Coonan:BAAALAAECgQICgAAAA==.',Cr='Crofyz:BAABLAAECoEhAAIFAAcI5hY0KwACAgAFAAcI5hY0KwACAgAAAA==.Cruul:BAAALAADCgYIBgAAAA==.',Da='Damnazor:BAAALAADCgcIBwAAAA==.Damsugare:BAAALAAECgIIAgAAAA==.Darkblade:BAAALAADCggICAAAAA==.',De='Deano:BAAALAADCgYIBgAAAA==.Demoman:BAAALAAECgIIAgAAAA==.Demonizer:BAAALAADCgQIAQAAAA==.Demonnuggie:BAABLAAECoEYAAMGAAcIjSGwBwAuAgAHAAcIMR/ULABbAgAGAAYIoyGwBwAuAgABLAAECggIHQACAGwjAA==.Demontriox:BAAALAADCgcIEwAAAA==.Devos:BAABLAAFFIEFAAMIAAMI1R1bDgABAQAIAAMI1R1bDgABAQAEAAIIQhbeGQCLAAAAAA==.',Di='Dinodeano:BAAALAADCgEIAQAAAA==.',Dr='Dracaris:BAAALAADCgcIBwAAAA==.Drizzydk:BAAALAAECgMIAwAAAA==.',Du='Dubarare:BAAALAADCggIDQAAAA==.Dumsomensten:BAAALAADCggICQAAAA==.Dunka:BAAALAAECgYIBgAAAA==.',Dw='Dwarftusken:BAAALAADCggICAAAAA==.',Ee='Eetwatti:BAABLAAECoEiAAIJAAgIYxaWGwAhAgAJAAgIYxaWGwAhAgAAAA==.',El='Eldris:BAAALAADCgYIBQAAAA==.',Er='Erioc:BAAALAAECgEIAQABLAAECggIJAAKAP8YAA==.',Eu='Euraia:BAAALAAECgIIAgAAAA==.',Ez='Ezioc:BAAALAADCggIDgAAAA==.',Fa='Fanix:BAAALAAECgQIBAAAAA==.',Fe='Fen:BAABLAAECoEgAAIIAAgI6hpiKwBlAgAIAAgI6hpiKwBlAgAAAA==.',Fi='Fielorna:BAAALAADCgcIDAAAAA==.Filletheone:BAAALAAECggICAAAAA==.Firenda:BAAALAADCgcICAAAAA==.',Fl='Flowdk:BAAALAAECgEIAgAAAA==.',Fr='Frostmoon:BAACLAAFFIEHAAILAAMIDBqHEwACAQALAAMIDBqHEwACAQAsAAQKgSQAAgsACAgPIRktAJMCAAsACAgPIRktAJMCAAAA.',Ga='Garalos:BAABLAAECoEVAAIFAAYI3CB9KQANAgAFAAYI3CB9KQANAgAAAA==.',Gi='Gilford:BAABLAAECoEgAAMMAAgI7AwZKQCfAQAMAAgI7AwZKQCfAQANAAIIdAacHAFhAAAAAA==.',Gl='Gloriana:BAAALAAECgMIBQAAAA==.',Go='Gowther:BAAALAADCgcIDAABLAADCggIEAAOAAAAAA==.',Gr='Greybeard:BAACLAAFFIEIAAMPAAUIXhsoAADyAQAPAAUIXhsoAADyAQAHAAEILAeQOwBTAAAsAAQKgR4AAw8ACAibIgYHANgCAA8ACAh/IgYHANgCAAcABwgTINElAH8CAAAA.Gruldrak:BAAALAADCgcIBwAAAA==.',Ha='Haadés:BAAALAADCgcIBgAAAA==.Halyn:BAAALAADCgYIDAAAAA==.Hate:BAAALAADCggIBwABLAAECgcIEQAOAAAAAA==.',He='Hethym:BAAALAAECgcIDwAAAA==.',Hi='Himouto:BAAALAADCggICAAAAA==.',Hu='Hutao:BAABLAAECoEeAAMCAAgIDCSABgATAwACAAgIDCSABgATAwAQAAEIzxHuPQA7AAABLAAFFAYIDAAGAJwOAA==.',Hy='Hyrsretwo:BAAALAAECgYICQAAAA==.',['Hé']='Héllwhisper:BAABLAAECoEdAAICAAgIbCM0BQAqAwACAAgIbCM0BQAqAwAAAA==.',Il='Illiflow:BAAALAADCgEIAQAAAA==.',Is='Isarith:BAAALAAECgIIAgABLAAECggIHgADAHUXAA==.',Ji='Jingim:BAAALAADCgcIBwAAAA==.',Jo='Jox:BAABLAAECoEeAAMRAAgIrRnRDgBNAgARAAgIrRnRDgBNAgACAAEIlAH+XgAKAAAAAA==.',Ka='Kaladin:BAAALAAECgUICgABLAAFFAMICQASAFIfAA==.',Ke='Kepster:BAAALAADCgcICwAAAA==.Kexan:BAAALAADCggICAAAAA==.',Kh='Khalley:BAABLAAECoEUAAITAAgISAsuHQBbAQATAAgISAsuHQBbAQAAAA==.Khalltusken:BAAALAAECgYIDAAAAA==.',Kl='Klæssesnabb:BAACLAAFFIEGAAILAAIIxxnmPQCTAAALAAIIxxnmPQCTAAAsAAQKgRQAAgsACAjAF6xLAC8CAAsACAjAF6xLAC8CAAAA.',Kn='Knas:BAAALAAECgcIEQAAAA==.',Ko='Koase:BAAALAAFFAIIBAAAAA==.',Kr='Kratos:BAAALAAECgYIDQABLAAECgcICgAOAAAAAA==.',Ku='Kukbe:BAABLAAECoEbAAIUAAgIwAabmwBXAQAUAAgIwAabmwBXAQAAAA==.',La='Larentina:BAAALAADCgYIBAABLAAECgcIEQAOAAAAAA==.Larra:BAABLAAECoEVAAIDAAgISRewIQBMAgADAAgISRewIQBMAgAAAA==.Lazernugget:BAAALAAFFAIIAgAAAA==.',Li='Lilanka:BAAALAADCgYIBgAAAA==.',Lu='Luppious:BAAALAADCgUIBQAAAA==.',Me='Mentally:BAAALAAECgMIAwAAAA==.Metsämies:BAAALAADCgcIDQAAAA==.',Mi='Midnight:BAAALAADCggICAAAAA==.Milva:BAAALAADCggICQABLAADCggICgAOAAAAAA==.Mirannda:BAAALAADCgcIBwAAAA==.Misshyper:BAAALAAECgQICgAAAA==.',Mo='Monkyman:BAAALAADCgQIBgAAAA==.Moreeca:BAAALAAECgcIDAAAAA==.Mosees:BAAALAADCgcIBwAAAA==.',Ms='Msi:BAAALAAECgMIBQAAAA==.',Mu='Murhamies:BAAALAADCgcIDQAAAA==.',['Mö']='Mörkö:BAACLAAFFIEMAAIVAAYIeCAMAABsAgAVAAYIeCAMAABsAgAsAAQKgSoAAxUACAgMJwYAAKoDABUACAgMJwYAAKoDAAgACAhgJYUCAHADAAAA.',Na='Nalindax:BAAALAADCggICAAAAA==.Narrak:BAAALAAECgMIAwAAAA==.',Ne='Nereya:BAAALAADCgEIAQABLAAECggIHwANANcjAA==.Nevedora:BAAALAAECgIIAgAAAA==.',No='Nolli:BAAALAADCgMIAwAAAA==.',Nw='Nw:BAAALAAECgMIAwAAAA==.',Ny='Nymeria:BAABLAAECoEdAAIFAAYIQhD/SQBlAQAFAAYIQhD/SQBlAQAAAA==.',Nz='Nzl:BAAALAADCggICAAAAA==.',On='Onyx:BAAALAADCggIDwAAAA==.',Op='Opadeeku:BAAALAADCgEIAQAAAA==.Opie:BAABLAAECoEhAAIVAAgIdxFNBwAfAgAVAAgIdxFNBwAfAgAAAA==.',Oz='Ozzy:BAAALAADCgMIAwAAAA==.',['Oê']='Oêll:BAAALAAECgMIBQAAAA==.',Pa='Pansurge:BAAALAAECgcICQAAAA==.Patriarkka:BAAALAADCgQIBQAAAA==.',Pe='Pestilence:BAAALAADCgcICQAAAA==.',Po='Pox:BAAALAADCggICAAAAA==.',Pu='Punk:BAAALAADCggICAAAAA==.Punkdafunk:BAACLAAFFIEFAAIUAAMIOh2dDwAFAQAUAAMIOh2dDwAFAQAsAAQKgSoAAhQACAirIW0UAAEDABQACAirIW0UAAEDAAAA.',Qu='Queldorai:BAABLAAECoEYAAIHAAgItBN4PgAJAgAHAAgItBN4PgAJAgABLAAFFAMIBwALAAwaAA==.Quias:BAAALAADCggIDwAAAA==.',Ra='Rasko:BAAALAADCggICAAAAA==.',Re='Renwell:BAAALAADCgEIAQAAAA==.',Rn='Rngesus:BAAALAADCgcICQAAAA==.',Ro='Rouxn:BAAALAAECgIIAgAAAA==.',Sa='Saleyn:BAAALAADCgIIAgABLAAECggIHwANANcjAA==.Samistar:BAAALAAFFAIIBAAAAA==.Sanphlet:BAAALAAECggICwAAAA==.Sassy:BAABLAAECoEcAAIEAAcIABSKOQC1AQAEAAcIABSKOQC1AQAAAA==.Sayajin:BAAALAADCgcIBwABLAAFFAMIBwALAAwaAA==.',Sd='Sdg:BAABLAAECoEbAAMNAAgIrAY2sQBXAQANAAgIrAY2sQBXAQAMAAIIoQCjaQAZAAAAAA==.',Se='Setharas:BAAALAADCggICAABLAAECggIJAAKAP8YAA==.',Sh='Shirael:BAABLAAECoEfAAINAAgI1yMKDgAwAwANAAgI1yMKDgAwAwAAAA==.Shush:BAAALAAECgUIAgAAAA==.',Si='Sinon:BAACLAAFFIEGAAIWAAMI2wUKBgC9AAAWAAMI2wUKBgC9AAAsAAQKgSYAAhYACAhhGjUSAGkCABYACAhhGjUSAGkCAAAA.',Sk='Skelmage:BAAALAAECgYIBwABLAAECggIJAAKAP8YAA==.Skelmon:BAAALAAECgMIAwABLAAECggIJAAKAP8YAA==.Skeltor:BAABLAAECoEkAAQKAAgI/xglFgBTAgAKAAgI/xglFgBTAgAXAAEIVBDiPwA/AAAYAAEIfwTrGwAoAAAAAA==.Skoff:BAAALAADCggIEQAAAA==.',Sl='Slopp:BAABLAAECoEjAAMZAAgIyhkYDAB2AgAZAAgIyhkYDAB2AgALAAQIxhJn/ADNAAAAAA==.Slurva:BAAALAADCggIEAAAAA==.Slæggetryne:BAAALAADCgIIAgAAAA==.',Sn='Snerkz:BAABLAAECoEXAAIaAAYItCLSFwA7AgAaAAYItCLSFwA7AgAAAA==.',Sp='Spaztíc:BAABLAAECoEXAAIbAAgIHhgjIQA3AgAbAAgIHhgjIQA3AgAAAA==.',St='Standardat:BAABLAAECoEYAAIcAAcIAyCwBwBoAgAcAAcIAyCwBwBoAgAAAA==.',Su='Superkenneth:BAAALAAECgMIAwAAAA==.Surilian:BAAALAADCggIDQAAAA==.',Sy='Sypha:BAABLAAECoEWAAMdAAcI5QT5IwD7AAAdAAcI5QT5IwD7AAAJAAMI9gD8WwArAAAAAA==.',Ta='Tancaru:BAAALAADCgYICwAAAA==.Tandefelt:BAACLAAFFIEHAAIdAAMIIhjJBgD+AAAdAAMIIhjJBgD+AAAsAAQKgSIAAh0ACAg/I0gCACYDAB0ACAg/I0gCACYDAAAA.Tanith:BAAALAAECgMIAwAAAA==.Tarduck:BAAALAADCggIEgAAAA==.',Te='Telenara:BAAALAAECgMIBgAAAA==.Tera:BAABLAAECoEgAAIbAAgICCEsCgDrAgAbAAgICCEsCgDrAgAAAA==.Terassi:BAAALAAECggIEQAAAA==.',Ti='Tizona:BAAALAADCgIIAgAAAA==.',To='Tommy:BAAALAAFFAEIAQAAAA==.',Uk='Ukkonen:BAAALAADCgQIBAAAAA==.',Us='Useable:BAAALAAECgIIAQAAAA==.',Va='Vampirekiss:BAAALAADCggIFgABLAAECggIFgAeAJYbAA==.Vanerion:BAAALAADCgcICQAAAA==.',Vi='Vicaria:BAAALAAECgMIBQAAAA==.Vinerion:BAAALAADCgcIBwAAAA==.',Vp='Vphunter:BAAALAADCgEIAQAAAA==.',['Vä']='Vägglusen:BAAALAADCggICAAAAA==.',Ya='Yavinek:BAAALAADCgMIAwAAAA==.',Ye='Yeadaddy:BAAALAADCggICAAAAA==.',Yu='Yudex:BAAALAADCgcIBQAAAA==.',Za='Zagan:BAABLAAECoEUAAIBAAcICwtlcgCJAQABAAcICwtlcgCJAQAAAA==.',Zb='Zbyszek:BAAALAADCggICAABLAAECgYIDwAOAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end