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
 local lookup = {'Warlock-Demonology','Shaman-Restoration','Paladin-Protection','Paladin-Retribution','Unknown-Unknown','Shaman-Elemental','Mage-Frost','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost','Priest-Holy','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','Monk-Windwalker','Mage-Arcane','Evoker-Devastation','Druid-Restoration','Warrior-Fury','Warrior-Protection','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','DeathKnight-Unholy','Priest-Shadow','Warlock-Affliction','DemonHunter-Vengeance','Paladin-Holy','Priest-Discipline','Monk-Brewmaster','Shaman-Enhancement','Warrior-Arms',}; local provider = {region='EU',realm='Tirion',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Actionork:BAAALAADCgUIBQAAAA==.',Ah='Ahzee:BAAALAADCgIIAgAAAA==.',Ak='Akunda:BAAALAADCgQIBAAAAA==.',Al='Alestis:BAAALAADCgcICgAAAA==.Alinê:BAAALAAECgIIBQAAAA==.',Am='Amônet:BAAALAADCgcIBwAAAA==.',An='Andralas:BAABLAAECoEgAAIBAAcIOx33EABaAgABAAcIOx33EABaAgAAAA==.Anitadiq:BAABLAAECoEXAAICAAcIORgdSgDWAQACAAcIORgdSgDWAQAAAA==.Ankare:BAABLAAECoEWAAIDAAYIcRK9LwBLAQADAAYIcRK9LwBLAQAAAA==.Annastesia:BAAALAADCgcICgAAAA==.Anubis:BAABLAAECoEWAAIEAAgIVQ4nsQBhAQAEAAgIVQ4nsQBhAQAAAA==.Anysha:BAAALAADCggICAAAAA==.',Aq='Aqui:BAAALAADCgMIAwAAAA==.',Ar='Arluthien:BAAALAAECgIIBQAAAA==.Aronan:BAAALAADCggIDQAAAA==.Artischocke:BAAALAAECgcIDgAAAA==.Artun:BAAALAAECgYIDQAAAA==.',As='Aseria:BAAALAADCgcIBwAAAA==.Asira:BAAALAADCggIGgABLAAECgYIDgAFAAAAAA==.Asmanica:BAAALAADCggIEAAAAA==.',At='Atas:BAAALAAECggIEwAAAA==.Atomstrom:BAABLAAECoEWAAIGAAcI/AlUXABzAQAGAAcI/AlUXABzAQABLAAECgcIGwAGAE0NAA==.',Au='Auron:BAAALAADCggIHgAAAA==.',Ax='Axeclick:BAAALAADCggICAAAAA==.',Ay='Ayva:BAAALAAECgEIAQAAAA==.',Az='Azaroth:BAAALAADCggIBQAAAA==.Azeem:BAABLAAECoEtAAIHAAgIHQuKMgCIAQAHAAgIHQuKMgCIAQAAAA==.Azeroth:BAAALAAECggICAAAAA==.',Ba='Baiky:BAAALAADCggIFQAAAA==.Baldraz:BAAALAAECgIIAgABLAAECggICAAFAAAAAA==.Batibat:BAAALAAECgYIDgAAAA==.',Be='Beo:BAAALAADCgUIBQAAAA==.Beothor:BAAALAADCggIDwAAAA==.',Bi='Biltan:BAAALAADCgYIDQAAAA==.',Bl='Blake:BAABLAAECoEiAAIEAAgI0h9uHwDVAgAEAAgI0h9uHwDVAgAAAA==.Blinzelgnom:BAAALAADCggICAABLAAECgEIAQAFAAAAAA==.Blákê:BAAALAAECgIIAgAAAA==.Blâké:BAAALAADCgcIBgAAAA==.Blåke:BAAALAADCggICgAAAA==.',Bo='Bosov:BAAALAAECgYIDAAAAA==.',Br='Brawzyy:BAAALAAECggIBgAAAA==.',Bu='Bulthasor:BAAALAAECgYICQABLAAECgYIDQAFAAAAAA==.Bursa:BAAALAAECgMIAwABLAAECgYIDQAFAAAAAA==.',['Bá']='Bálin:BAAALAADCgYICwABLAAECgcIIAAIAIMZAA==.',Ca='Calmest:BAABLAAECoEaAAMJAAYIdBoJGAClAQAJAAYIdBoJGAClAQAKAAII0QvCNQFiAAAAAA==.Capoplaza:BAAALAAFFAEIAQAAAA==.Casarea:BAAALAAECgYIBgAAAA==.Cayenn:BAABLAAECoEoAAILAAgIgRDaPADAAQALAAgIgRDaPADAAQAAAA==.',Ci='Cirille:BAAALAADCgcIDAAAAA==.',Cr='Crazylykhan:BAAALAADCggIEAAAAA==.Crotan:BAABLAAECoEcAAIKAAYI9hhGmgCSAQAKAAYI9hhGmgCSAQAAAA==.Cryogen:BAABLAAECoEhAAIHAAcIjR7xEAB9AgAHAAcIjR7xEAB9AgAAAA==.Cryp:BAAALAAECgMIAwAAAA==.Crypt:BAAALAAECgUIBQAAAA==.',Cu='Curson:BAAALAAECggICAAAAA==.',Cy='Cykaxt:BAAALAAECgQIBAAAAA==.Cyphe:BAAALAADCgMIAwAAAA==.Cyress:BAAALAADCggICQAAAA==.',Da='Dalari:BAAALAADCgYICQAAAA==.Dandiegro:BAAALAAECgIIBQAAAA==.Darkdestiiny:BAAALAADCgcICgAAAA==.Darkgore:BAAALAAECgEIAQABLAAECgYICgAFAAAAAQ==.Darksilver:BAAALAAECgYIDgAAAA==.',De='Dego:BAABLAAECoEcAAMMAAgIzRkKDQA/AgAMAAgImBkKDQA/AgANAAYIoQ3CQgAqAQAAAA==.Dellefin:BAABLAAECoEUAAIOAAYIQh63WQDuAQAOAAYIQh63WQDuAQAAAA==.Dentenist:BAAALAAECgEIAQABLAAECgcIGwAPAPAaAA==.Deserteagle:BAAALAAECggICAAAAA==.',Di='Diemonia:BAAALAAECgMIBAAAAA==.Discobang:BAAALAAECgMIAwAAAA==.Discolight:BAAALAAECggICAAAAA==.Discopogo:BAAALAAECggIAgAAAA==.Dissonance:BAAALAADCgMIAwAAAA==.Divoka:BAAALAADCgcIDQAAAA==.',Dj='Djkorsakoff:BAAALAAECgYIDAAAAA==.',Dm='Dmagicd:BAABLAAECoEdAAIQAAgI7gLnsQDKAAAQAAgI7gLnsQDKAAAAAA==.',Do='Dopsi:BAAALAADCgQIBAAAAA==.Dotzie:BAAALAADCggIEAAAAA==.',Dr='Dracarya:BAABLAAECoEWAAIRAAYI3wzsOQBDAQARAAYI3wzsOQBDAQAAAA==.Dragobias:BAAALAADCggICAABLAAECggIHgABAO0iAA==.Draídax:BAABLAAECoEeAAISAAcILR6DHwBJAgASAAcILR6DHwBJAgAAAA==.Druisita:BAAALAADCgYIBgAAAA==.',Du='Dusty:BAAALAAECggICAAAAA==.',['Dæ']='Dænerys:BAAALAADCggIDwAAAA==.',['Dê']='Dêgô:BAAALAAECgYICwAAAA==.Dêâthknight:BAABLAAECoEXAAIKAAYIjBh0qQB5AQAKAAYIjBh0qQB5AQAAAA==.',['Dí']='Dína:BAAALAADCggIDgAAAA==.Dívestry:BAAALAADCggICAABLAAFFAUIDwATAJkgAA==.',['Dî']='Dîvestry:BAACLAAFFIEPAAITAAUImSA9BgDfAQATAAUImSA9BgDfAQAsAAQKgSwAAhMACAiWJTYFAGIDABMACAiWJTYFAGIDAAAA.',['Dô']='Dôriâ:BAAALAADCggIFgAAAA==.',Ea='Ea:BAABLAAECoEWAAILAAYIjBBsWgBLAQALAAYIjBBsWgBLAQAAAA==.',Eb='Ebrietas:BAABLAAECoEZAAIOAAcImxkzUAAIAgAOAAcImxkzUAAIAgAAAA==.',Em='Emîly:BAAALAAFFAIIAwAAAA==.',En='Endurrion:BAABLAAECoEVAAIUAAcIwRscHQAVAgAUAAcIwRscHQAVAgAAAA==.',Er='Erdcracker:BAAALAAECgMIAwABLAAECgcIDQAFAAAAAA==.Erdinger:BAAALAADCgcIBwABLAAECggIDAAFAAAAAA==.Eredrak:BAAALAAECgYIDAAAAA==.Ereminos:BAAALAADCggICAAAAA==.Eriador:BAAALAAECgEIAQAAAA==.Eriôn:BAAALAAECgIIBQAAAA==.',Ev='Evangelin:BAAALAAECgEIAQAAAA==.Evén:BAAALAAECgEIAQAAAA==.',Ex='Exôdûs:BAAALAAECggICgAAAA==.',Fa='Faern:BAAALAADCggICAABLAAECgYIFgAKAHgjAA==.',Fe='Femio:BAAALAAECgQIBgABLAAECgYIFgAKAHgjAA==.',Fi='Fiesta:BAAALAADCggIFgAAAA==.',Fr='Freaky:BAAALAADCggICgAAAA==.Friedchicken:BAAALAAECgIIAgABLAAFFAMICQAPAI0kAA==.Frozen:BAAALAADCgYIBgAAAA==.Frída:BAAALAADCgcIEAAAAA==.Frôst:BAAALAAECgUIBQAAAA==.',Fu='Fusselmuh:BAAALAAECgIIAgAAAA==.',Ga='Ganadorus:BAAALAADCggICwAAAA==.',Ge='Geküsst:BAAALAAECggICAAAAA==.Gend:BAAALAADCggIDQAAAA==.',Gh='Ghear:BAAALAAECggICAAAAA==.',Gi='Gilceleb:BAAALAAECgUICgAAAA==.',Go='Goodaim:BAABLAAECoEVAAMVAAYIjhG1qQAsAQAVAAYIjhG1qQAsAQAWAAMIWwvNkAB6AAAAAA==.Gopferdammi:BAAALAAECgQIBAAAAA==.',Gr='Gradon:BAAALAAECgMIBQAAAA==.',Gu='Guildt:BAABLAAECoEgAAMIAAcIgxmGQgAAAgAIAAcI3xiGQgAAAgABAAMICBOYXQDKAAAAAA==.Guilty:BAAALAADCgUICgABLAAECgcIIAAIAIMZAA==.',Ha='Hachimoru:BAAALAAECgYIDwAAAA==.Hampelmaan:BAABLAAECoEmAAIXAAgIdCHjDgDZAgAXAAgIdCHjDgDZAgAAAA==.Haraldos:BAAALAADCggIKgAAAA==.Haress:BAABLAAECoEWAAMKAAYIeCOBSAA+AgAKAAYILSKBSAA+AgAYAAUITyLxHAC8AQAAAA==.Haydor:BAAALAAECggIAgAAAA==.',He='Healdown:BAAALAADCgIIAgAAAA==.Heilmo:BAAALAADCgMIAwABLAAECgEIAQAFAAAAAA==.Heiphestos:BAAALAAECgQIBAAAAA==.Helius:BAAALAAECgYIBgAAAA==.',Hi='Hizzer:BAAALAAECgMIAwAAAA==.',Ho='Holymeelo:BAAALAAECgIIAgABLAAECgUIBQAFAAAAAA==.Holó:BAAALAAECgYIBQAAAA==.',Hy='Hydnose:BAABLAAECoEaAAISAAcITB3KHgBNAgASAAcITB3KHgBNAgAAAA==.Hym:BAEALAAECggICAABLAAFFAIIBQAZAB0eAA==.',['Hú']='Húbert:BAAALAADCgMIAwAAAA==.',Id='Idomos:BAAALAADCgMIAwAAAA==.Idorai:BAAALAAECgUIDAAAAA==.',Ik='Ikazuchi:BAAALAAECggICAABLAAFFAMICQAPAI0kAA==.',Il='Illidana:BAAALAADCgUIBQAAAA==.',In='Inalun:BAAALAAECgEIAQAAAA==.Inasta:BAAALAAECgMICQAAAA==.Inava:BAAALAADCgYIBgAAAA==.Intheembrace:BAAALAAECgcIDQAAAA==.',Ja='Jaress:BAAALAAECgIIAwABLAAECgYIFgAKAHgjAA==.',Ji='Jimeno:BAABLAAECoEcAAMaAAYIzx3fDADIAQAaAAYIzx3fDADIAQAIAAYIzxIDbgB1AQAAAA==.',Jo='Joanofarc:BAABLAAECoEcAAICAAYIsyOKKABMAgACAAYIsyOKKABMAgAAAA==.',Ju='Julaki:BAAALAAECgYICQAAAA==.Julézzroot:BAAALAAECgEIAQAAAA==.Junho:BAABLAAECoEhAAIGAAgIDyAIEAD8AgAGAAgIDyAIEAD8AgAAAA==.',['Jê']='Jên:BAAALAAECgYIBgAAAA==.',['Jô']='Jôlinar:BAAALAADCgMIAwABLAADCgcIBwAFAAAAAA==.',Ka='Kair:BAABLAAECoEWAAIHAAYIgAkURgAwAQAHAAYIgAkURgAwAQAAAA==.Kalda:BAAALAAECgYIAgAAAA==.Kaleo:BAAALAADCgcICgAAAA==.Karion:BAAALAAECgQICgAAAA==.',Ke='Keísha:BAAALAAECgYIEQAAAA==.',Kh='Khasa:BAAALAADCgIIAgABLAAECgYIDQAFAAAAAA==.',Ki='Kiaros:BAABLAAECoEcAAISAAYIxRnZOwC6AQASAAYIxRnZOwC6AQAAAA==.Kida:BAAALAAECgYIDQAAAA==.Killnoob:BAAALAAECgcIBwAAAA==.Kimbalin:BAAALAAECgEIAgAAAA==.Kiss:BAAALAADCggIDQAAAA==.Kiyoki:BAAALAADCgYIBgAAAA==.',Kl='Kletz:BAACLAAFFIEFAAIXAAII1AwrGACJAAAXAAII1AwrGACJAAAsAAQKgR8AAhcACAilIC0MAPYCABcACAilIC0MAPYCAAAA.Kletzmonk:BAAALAADCggICAAAAA==.',Kn='Knörrli:BAAALAADCgcIBwAAAA==.',Ko='Kommarübär:BAAALAADCggIEAAAAA==.Koronà:BAAALAAECgYICwAAAA==.Korsarius:BAAALAAECgYIBwAAAA==.',Kr='Kration:BAAALAAECgYIDAAAAA==.',['Ké']='Kéréòn:BAABLAAECoEeAAMbAAcIrhTFJgBGAQAOAAcI7w6wfgCaAQAbAAYIdhTFJgBGAQAAAA==.',['Kü']='Kürwalda:BAAALAAECgYIEAAAAA==.',La='Lacon:BAAALAADCgQIBAAAAA==.Lagastí:BAABLAAECoEVAAIEAAcI/h+tNwBtAgAEAAcI/h+tNwBtAgAAAA==.Lahrin:BAABLAAECoEhAAMcAAcIvCIVCwCpAgAcAAcIvCIVCwCpAgAEAAEIjgOvSwEiAAAAAA==.Lanaley:BAABLAAECoEbAAIdAAcIMyXEAQD1AgAdAAcIMyXEAQD1AgAAAA==.Lao:BAAALAADCggICAAAAA==.Lassknacken:BAAALAAECggIDgAAAA==.Latoýya:BAAALAADCggICAAAAA==.',Le='Leandrôs:BAABLAAECoEXAAIGAAcIUxScSwCsAQAGAAcIUxScSwCsAQAAAA==.Leijona:BAAALAADCgMIAwAAAA==.Leyti:BAAALAADCggIBQAAAA==.',Li='Lillara:BAABLAAECoEqAAILAAcInQtMWQBPAQALAAcInQtMWQBPAQAAAA==.Lillithu:BAAALAAECgEIAQAAAA==.',Lo='Lockroga:BAAALAADCggICAABLAAFFAUIDwATAJkgAA==.Lokin:BAAALAAECgIIBQAAAA==.',Lu='Lukida:BAAALAADCggIIgAAAA==.Lum:BAEBLAAECoEWAAIeAAYIGx1gFADvAQAeAAYIGx1gFADvAQABLAAFFAIIBQAZAB0eAA==.Lusamine:BAABLAAECoEwAAIVAAgI7CKqDgAOAwAVAAgI7CKqDgAOAwAAAA==.',['Lô']='Lôrdvader:BAAALAADCgcIDQAAAA==.',Ma='Magelan:BAAALAADCggIEAAAAA==.Magicmo:BAAALAAECgEIAQAAAA==.Maluna:BAAALAAECgIIAgAAAA==.Manco:BAABLAAECoErAAIXAAgIDSGWEADHAgAXAAgIDSGWEADHAgAAAA==.Maracuja:BAABLAAECoEfAAIdAAgISyGnAQD8AgAdAAgISyGnAQD8AgAAAA==.Maxdk:BAAALAADCgcIDQAAAA==.',Mc='Mctavish:BAAALAADCggIFwAAAA==.',Me='Met:BAAALAAFFAIIAwAAAA==.Mexi:BAAALAADCgcIBwAAAA==.',Mi='Michi:BAABLAAECoEYAAIVAAgIxhNoWQDWAQAVAAgIxhNoWQDWAQAAAA==.Ministry:BAAALAAECgcIDwAAAQ==.Mirkan:BAAALAAECgUIBwAAAA==.Mizagi:BAAALAAECgYIEwABLAAECgcIDgAFAAAAAA==.',Mo='Morgar:BAAALAAECgEIAQABLAAFFAUIDwATAJkgAA==.Mortarios:BAAALAADCggICAAAAA==.',Mu='Mugen:BAAALAAECgYIDAAAAA==.',Mv='Mvnko:BAAALAAECgYICwABLAAECggIKwAXAA0hAA==.',My='Myrion:BAAALAAECgEIAQAAAA==.Myrta:BAAALAAECgcIDQAAAA==.Mysteryá:BAAALAAECgQIBwAAAA==.Mythio:BAAALAAECggIDAAAAA==.',['Mí']='Míráculíx:BAABLAAECoEVAAMSAAYIlRnmPQCyAQASAAYIlRnmPQCyAQAXAAUI6wj3aADLAAAAAA==.',['Mó']='Móses:BAAALAADCgcIBwAAAA==.',Na='Narin:BAAALAADCggICAAAAA==.Narkotica:BAABLAAECoEjAAMLAAcIYRQ7QQCtAQALAAcIYRQ7QQCtAQAZAAIIfAFzkAAmAAAAAA==.',Ne='Nebelgrau:BAAALAADCgYIBgAAAA==.Neku:BAABLAAECoEcAAIVAAgI9xCGXgDJAQAVAAgI9xCGXgDJAQAAAA==.',Ni='Nightofmeelo:BAAALAAECgUIBQAAAA==.Nirritriel:BAAALAADCggIGgABLAAECgYIHAAPADAfAA==.',Ny='Nylwan:BAABLAAECoEeAAIeAAcIvBtsEAAoAgAeAAcIvBtsEAAoAgAAAA==.',['Nê']='Nêram:BAAALAADCgcIBwAAAA==.',Oc='Ocyde:BAAALAAECgYIEQAAAA==.',Ol='Oleron:BAAALAAECggICAAAAA==.',On='Onikor:BAAALAAECggIBQAAAA==.',Pa='Paerna:BAAALAADCggICwAAAA==.Painstriker:BAAALAADCggICAABLAAECggICAAFAAAAAA==.Palaisin:BAAALAADCgUIBQAAAA==.Paly:BAAALAAECgYIEwAAAA==.Pandabear:BAAALAAECgYIBgAAAA==.Paran:BAAALAADCggICAAAAA==.Parkos:BAAALAAECgYICwAAAA==.',Pe='Pelori:BAAALAADCggIFAAAAA==.Pey:BAABLAAECoEkAAICAAcIeRE7dwBdAQACAAcIeRE7dwBdAQAAAA==.Peyoteh:BAAALAAECgYIBgAAAA==.',Po='Pogmage:BAAALAAECgEIAQABLAAECgYIDgAFAAAAAA==.Poldraci:BAAALAAECgUICAAAAA==.',Ps='Psychomantis:BAAALAAECgYICwAAAA==.',['Pá']='Pándorà:BAAALAAECgQIBAABLAAECggIIgABAO8YAA==.',Qu='Quirl:BAABLAAECoEbAAIVAAYISw7TowA4AQAVAAYISw7TowA4AQAAAA==.',Ra='Raddeneintop:BAAALAAECgIIAwAAAA==.Radgást:BAAALAADCgYIBgABLAAECgcIIAAIAIMZAA==.Ralfpeterson:BAAALAAECggIDQAAAA==.Rarfunzel:BAAALAADCgYIBgAAAA==.Raze:BAAALAADCgcIDQAAAA==.',Re='Realm:BAAALAADCggICAAAAA==.Replika:BAAALAAECgMIBQAAAA==.Retardor:BAABLAAECoEcAAIPAAYIMB8PGgAIAgAPAAYIMB8PGgAIAgAAAA==.Revênger:BAABLAAECoEdAAITAAYIehwWSwDaAQATAAYIehwWSwDaAQAAAA==.',Rh='Rheja:BAAALAAECgYIEQAAAA==.',Ro='Robert:BAAALAAECgQIBAABLAAECggIHgABAO0iAA==.Rovína:BAAALAADCgYIBgABLAAECggIKwAXAA0hAA==.',Ru='Rumbleteazer:BAAALAADCggIDgAAAA==.',Ry='Ryluras:BAAALAAECgQIBAAAAA==.',Sa='Saaron:BAAALAADCgUIBgAAAA==.Saizo:BAAALAADCggIEAAAAA==.San:BAECLAAFFIEFAAIZAAIIHR60EQC1AAAZAAIIHR60EQC1AAAsAAQKgTAAAhkACAjVIQcLAA8DABkACAjVIQcLAA8DAAAA.Sansibar:BAAALAAECgMIBAAAAA==.',Sc='Schnuckid:BAAALAADCgIIAgAAAA==.Schwub:BAAALAAECggICwAAAA==.',Se='Sehun:BAAALAAECgUICAAAAA==.Selkie:BAABLAAECoEaAAITAAgIgB0BJwB4AgATAAgIgB0BJwB4AgABLAAFFAUIDQAGAOUXAA==.Serenya:BAAALAAECgYIDwAAAA==.',Sh='Shakitilar:BAABLAAECoEcAAMfAAYIphsOEAC/AQAfAAYIphsOEAC/AQACAAYI0AiStwDVAAAAAA==.Shamasu:BAAALAADCgcIBwAAAA==.Shambulance:BAAALAADCgYIDAAAAA==.Shamty:BAAALAADCgEIAQABLAADCgcIEAAFAAAAAA==.Shandoshea:BAAALAADCgYIAQAAAA==.Sheeva:BAAALAADCgcIEwAAAA==.Sheyma:BAAALAADCgYIBwAAAA==.Shâkky:BAAALAADCgMIAwAAAA==.',Si='Silentwater:BAAALAAECggICAAAAA==.Siluria:BAABLAAECoEXAAIKAAgIjAGxLgFwAAAKAAgIjAGxLgFwAAAAAA==.Silva:BAAALAAECgYIDAAAAA==.Sinaqyl:BAAALAAECgcICQABLAAFFAIIBgACAOwjAA==.',Sk='Skorsh:BAAALAAECggIEAAAAA==.Skrymir:BAABLAAECoEWAAIWAAgI/wlaZQASAQAWAAgI/wlaZQASAQAAAA==.',Sl='Sleepy:BAABLAAECoEdAAIGAAcIeR15JwBTAgAGAAcIeR15JwBTAgAAAA==.',So='Sopranos:BAAALAAECggIDgAAAA==.Sorasa:BAAALAAECgYIDAAAAA==.',Sr='Sryus:BAAALAADCggIHAAAAA==.',St='Steckdose:BAAALAAECgEIAQAAAA==.Stormlash:BAAALAAECgUICAAAAA==.Sturmtraum:BAABLAAECoEbAAIGAAcITQ38UACZAQAGAAcITQ38UACZAQAAAA==.Stôrmfighter:BAAALAAECggICAAAAA==.',Sw='Sweet:BAAALAAECgYIDgAAAA==.',Sy='Sylforia:BAAALAAECgQICAABLAAECggIDAAFAAAAAA==.Sylthara:BAAALAADCgQIBAAAAA==.',['Sê']='Sêlené:BAAALAADCggIGAAAAA==.',Ta='Tahrea:BAAALAADCgIIAgAAAA==.Talmanar:BAAALAADCggIDQAAAA==.Talvy:BAAALAADCgcIDgAAAA==.',Te='Tegxonn:BAAALAAECgUIBQAAAA==.Temeria:BAABLAAECoEbAAMVAAcISBPxggB4AQAVAAcISBPxggB4AQAWAAUIFQpCeQDNAAAAAA==.Tendroin:BAABLAAECoEVAAMgAAgIDRI7EgCRAQAgAAgIVw87EgCRAQATAAUImRN4hQAwAQAAAA==.Teran:BAAALAADCggIFAAAAA==.Terranios:BAAALAADCgcIBwAAAA==.',Th='Thaldorin:BAAALAAECgYIAQAAAA==.Themistro:BAAALAAECgcIDwAAAA==.Thila:BAAALAAECgYIDAAAAA==.Thurîn:BAAALAAECggICQAAAA==.Thynotlikeus:BAAALAADCggIDAAAAA==.Thûrin:BAAALAAECggIBgAAAA==.',Ti='Til:BAEALAAECgUIBQABLAAFFAIIBQAZAB0eAA==.Titoo:BAAALAADCgcIBwAAAA==.',To='Tobert:BAABLAAECoEeAAMBAAgI7SIqBAAXAwABAAcIFiYqBAAXAwAIAAMIGQYIyQBhAAAAAA==.Todeszwerg:BAAALAAECgQICwAAAA==.',Tr='Trayn:BAAALAADCgcIBwAAAA==.Trolljordomu:BAAALAAECggICAAAAA==.Trostrinossa:BAAALAADCgYIBgAAAA==.',Tu='Turbooma:BAAALAAECgYIBgAAAA==.Turrikan:BAABLAAECoEcAAIXAAYIhB18MgDFAQAXAAYIhB18MgDFAQAAAA==.',Tw='Twìlíght:BAAALAAECgEIAQAAAA==.',['Tâ']='Tâekwondo:BAABLAAECoEbAAIPAAcI8BpsHADwAQAPAAcI8BpsHADwAQAAAA==.',['Tå']='Tåyxzz:BAAALAADCggICAAAAA==.',['Tè']='Tèçak:BAAALAADCgUIBQAAAA==.',Va='Valeri:BAAALAAECgUIDAAAAA==.Valisera:BAAALAADCgcIBwAAAA==.Vanos:BAAALAADCgcIEAAAAA==.Vaska:BAAALAAECgUIBgAAAA==.',Ve='Verla:BAAALAAECgIIAgABLAAECgYIFgAKAHgjAA==.Verndarís:BAAALAADCgcIFAAAAA==.',Vi='Vit:BAABLAAECoEVAAIGAAcIPROXYgBfAQAGAAcIPROXYgBfAQAAAA==.',Wa='Wala:BAAALAAECgIIAwAAAA==.',We='Weskér:BAAALAADCgcIBwAAAA==.',Wh='Whiteiverson:BAAALAADCgEIAQAAAA==.',Wi='Wichtlzwick:BAAALAAECgcIDQAAAA==.Wildeyes:BAABLAAECoEhAAIOAAgI9BvSKgCOAgAOAAgI9BvSKgCOAgAAAA==.Wildman:BAAALAAECgEIAQAAAA==.Windwalker:BAAALAAECgQIBgAAAA==.',Wo='Worn:BAABLAAECoEXAAITAAgIvglPYgCTAQATAAgIvglPYgCTAQAAAA==.',['Wê']='Wêlle:BAAALAADCggIDwAAAA==.',Xa='Xanim:BAAALAAECgUICAAAAA==.Xavulpa:BAAALAAECgYIDwAAAA==.',Xe='Xenophilos:BAAALAADCgYIBgAAAA==.',Xi='Xilina:BAAALAADCgUIBQAAAA==.Xipetwo:BAAALAAECgQIBQAAAA==.',Xy='Xylaara:BAAALAADCggIEgAAAA==.',Ya='Yalor:BAAALAAECgYIEAAAAA==.Yamuna:BAAALAAECgYIBgAAAA==.Yanji:BAAALAADCggICAAAAA==.',Yu='Yuma:BAAALAAECgMIAwAAAA==.',['Yó']='Yótema:BAABLAAECoEYAAICAAgIZQ/bbAB3AQACAAgIZQ/bbAB3AQAAAA==.',['Yú']='Yúrí:BAAALAAECgQICAABLAAECgcIGAAJAH0hAA==.Yúríhású:BAABLAAECoEYAAIJAAcIfSHnCACoAgAJAAcIfSHnCACoAgAAAA==.',['Yû']='Yûlivee:BAABLAAECoEiAAIBAAgI7xhrEABgAgABAAgI7xhrEABgAgAAAA==.',Za='Zapfdos:BAAALAAECggICAAAAA==.Zayomi:BAAALAAECgYICAAAAA==.',Ze='Zehnvierzig:BAAALAAECgYIDQAAAA==.Zenos:BAABLAAECoEUAAIEAAgI9gA/NAFFAAAEAAgI9gA/NAFFAAAAAA==.Zera:BAAALAAECgMIAwAAAA==.',Zi='Zin:BAAALAADCgYIDAAAAA==.',Zo='Zoè:BAAALAADCgQIBAAAAA==.',Zu='Zudar:BAAALAAECgYICwABLAAECgYIDQAFAAAAAA==.',Zw='Zwai:BAAALAADCggICAAAAA==.',['Âl']='Âllrounder:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end