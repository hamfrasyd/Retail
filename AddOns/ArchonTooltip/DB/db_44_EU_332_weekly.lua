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
 local lookup = {'DeathKnight-Blood','Priest-Holy','Monk-Windwalker','Priest-Shadow','Hunter-BeastMastery','Druid-Balance','Paladin-Retribution','Paladin-Protection','Mage-Fire','DemonHunter-Havoc','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Mage-Arcane','Paladin-Holy','Warrior-Protection','Warlock-Destruction','Shaman-Restoration','Warrior-Arms','Hunter-Marksmanship','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Warlock-Demonology','Monk-Brewmaster','Hunter-Survival','Evoker-Preservation','Warrior-Fury',}; local provider = {region='EU',realm='Sporeggar',name='EU',type='weekly',zone=44,date='2025-09-22',data={Af='Afton:BAAALAADCgYIBgABLAAECgYIFgABAO0UAA==.',Al='Alechs:BAAALAAECgYIDAAAAA==.',Am='Amaelamen:BAAALAADCgcIBwAAAA==.Amenadial:BAAALAADCgcIBwAAAA==.',An='Aneurin:BAAALAAECgUIAQAAAA==.Anuka:BAAALAADCgcIBwABLAAECggIHgACAMkaAA==.',Ar='Archennon:BAAALAAECgYIBgABLAAECggIHwADAH4eAA==.Armaphyst:BAAALAAFFAIIBAABLAAFFAIICgAEAPYfAA==.Armarouge:BAAALAAFFAIIBAABLAAFFAIICgAEAPYfAA==.',Au='Aulea:BAAALAAECgMIBQAAAA==.Austra:BAACLAAFFIEOAAIFAAQINBwQCQBcAQAFAAQINBwQCQBcAQAsAAQKgSMAAgUACAjgIpcSAO8CAAUACAjgIpcSAO8CAAAA.',Az='Azazil:BAAALAAECgYIDAAAAA==.',Ba='Bankcy:BAAALAADCgIIAgAAAA==.',Be='Beba:BAABLAAECoEbAAIFAAgIRhsRLgBaAgAFAAgIRhsRLgBaAgAAAA==.Behul:BAAALAADCggIEAAAAA==.',Bh='Bhil:BAAALAADCgQIBAAAAA==.',Bi='Biftek:BAABLAAECoEZAAIGAAgImw+UPgCBAQAGAAgImw+UPgCBAQAAAA==.Biltemabenny:BAABLAAECoEXAAMHAAgIVhkWQQBIAgAHAAgIpBgWQQBIAgAIAAYISBNILQBPAQAAAA==.Biltemajenny:BAAALAAECgYIDAAAAA==.',Bo='Bodytypeone:BAAALAAECgYICQAAAA==.',Br='Braindamage:BAAALAAECgQIBAABLAAECggIIgAJAEglAA==.Brightsong:BAABLAAECoEaAAMIAAcIKx42FQAYAgAIAAYI8CA2FQAYAgAHAAEIjQ3wMAE8AAAAAA==.Brinjiolf:BAAALAADCgYIBgABLAAECgcIGgAIACseAA==.',Bu='Bucket:BAABLAAECoEUAAIBAAcImRhiFADLAQABAAcImRhiFADLAQAAAA==.',Ca='Cady:BAAALAAECgYIBgABLAAECggIHwAKAJ8fAA==.Catknight:BAAALAADCgQIBAAAAA==.Cazi:BAAALAADCgcIDgAAAA==.',Ce='Celestial:BAAALAAECgYIBgABLAAECggIIgAJAEglAA==.Cerynn:BAAALAAECgUIBQABLAAECggIIgAJAEglAA==.',Ch='Chanden:BAABLAAECoEVAAMGAAcI2BqcOwCQAQAGAAYI8RecOwCQAQALAAYIgBkbHQCBAQAAAA==.Chandrizard:BAABLAAECoEVAAMMAAcI8xR1LwCBAQAMAAYICBd1LwCBAQANAAEIcggrFQA9AAAAAA==.Chaosdemon:BAAALAAECgYIBgAAAA==.Chaoticus:BAAALAAECgYICAAAAA==.',Cl='Claribel:BAAALAAECgYIDQAAAA==.',Co='Cobbo:BAAALAADCggICQAAAA==.',Cr='Créèd:BAAALAAECgUIBQABLAAECgYIBgAOAAAAAA==.',Cu='Cucalian:BAAALAADCggICAAAAA==.',Da='Daggy:BAAALAADCggIEAABLAADCggIEAAOAAAAAA==.Darkshadow:BAAALAAECgcIEgAAAA==.Darmac:BAAALAADCggIEAAAAA==.Daskeladden:BAAALAADCggICgABLAAECggIIQAPAH0ZAA==.',Di='Diabla:BAAALAAECgYIBgABLAAECgcIGgAIACseAA==.Dignite:BAAALAAECgYICwABLAAECggIIgAJAEglAA==.',Dr='Dragonflight:BAAALAAECgcIBwAAAA==.Draugred:BAABLAAECoEWAAIBAAYI7RRwHwBBAQABAAYI7RRwHwBBAQAAAA==.Druidosz:BAABLAAECoEWAAIGAAcIYBypKQDvAQAGAAcIYBypKQDvAQAAAA==.Drukash:BAAALAAECgYIDAAAAA==.',Ea='Earis:BAABLAAECoEcAAILAAgIEiOeAgA9AwALAAgIEiOeAgA9AwAAAA==.',Er='Erevus:BAAALAADCggICAAAAA==.',Fa='Fay:BAAALAADCgYIBgAAAA==.',Fe='Felforit:BAAALAAECgcIDQAAAA==.Ferinir:BAAALAADCggIDQABLAAECggIHAALABIjAA==.Feshamby:BAAALAADCgcIDgAAAA==.',Ga='Gail:BAABLAAECoEXAAIQAAcIhAqDVACDAQAQAAcIhAqDVACDAQAAAA==.',Gi='Giger:BAAALAADCggIIwAAAA==.Gingerjoe:BAABLAAECoEbAAIRAAcIhxl2QwAZAgARAAcIhxl2QwAZAgABLAAECgcIFgAGAGAcAA==.Ginti:BAAALAAECggICAAAAA==.',Gr='Grizzlepaw:BAAALAADCggIDwAAAA==.',Gv='Gvastrion:BAABLAAECoEjAAMIAAgIGx1MCwCSAgAIAAgIGx1MCwCSAgAHAAEI2wflOAExAAAAAA==.',Ha='Hazzlebarth:BAAALAADCggIHgABLAAECgcIJAASAIMSAA==.',Hi='Hidden:BAAALAAECgYICgAAAA==.',Ho='Hotgothpanda:BAAALAADCggICwAAAA==.',Ia='Iarchas:BAAALAADCgUIBQAAAA==.',Ig='Ignite:BAABLAAECoEiAAIJAAgISCVmAABoAwAJAAgISCVmAABoAwAAAA==.',Ik='Iknow:BAABLAAECoEhAAIFAAgIfSAPEwDtAgAFAAgIfSAPEwDtAgAAAA==.',In='Inuki:BAAALAAECgYICgAAAA==.Inzomnia:BAAALAAECggIEQAAAA==.',Ir='Irath:BAAALAADCggICAABLAAECgYIFgABAO0UAA==.Ironhand:BAAALAADCggIDgABLAAECgcIHQATAAAYAA==.Ironxwar:BAABLAAECoEdAAITAAcIABh2JQDNAQATAAcIABh2JQDNAQAAAA==.',Ja='Jayee:BAACLAAFFIENAAIUAAUI9htVCADfAQAUAAUI9htVCADfAQAsAAQKgR8AAhQACAjTJZMDAHADABQACAjTJZMDAHADAAAA.',Je='Jenkens:BAAALAAECgYIDQAAAA==.Jenna:BAAALAADCggICAABLAAECggIJwAVALwlAA==.Jeratsle:BAAALAADCgQIBAAAAA==.',Jm='Jmy:BAAALAADCggICAAAAA==.',Jo='Joeyphatpwn:BAABLAAECoEVAAIWAAgIfAzrEQCQAQAWAAgIfAzrEQCQAQAAAA==.Joy:BAAALAADCggICAAAAA==.',Ju='Jumju:BAAALAADCgEIAQAAAA==.',Ka='Kamimoo:BAAALAADCgcIBwABLAAECggIHAALABIjAA==.Kavanos:BAAALAAECgYIDAAAAA==.Kazuun:BAABLAAECoEcAAIVAAcIjQk7lgANAQAVAAcIjQk7lgANAQAAAA==.',Ko='Kodya:BAAALAADCggICAAAAA==.',Kr='Kraves:BAAALAAECgcIDAAAAA==.Kresty:BAAALAADCgMIAwAAAA==.',Ky='Kychahh:BAAALAAECgcIDQAAAA==.',La='Laress:BAAALAAFFAIIAgAAAA==.Laureen:BAABLAAECoEnAAMCAAgIQyFYCwD4AgACAAgIQyFYCwD4AgAEAAgIURCuMgDYAQAAAA==.',Le='Lento:BAAALAADCgcIBwAAAA==.',Li='Liavia:BAAALAAECggIEAABLAAFFAYIDQAUAJoaAA==.Lienchao:BAAALAADCggICAAAAA==.Lighthammer:BAAALAADCgcIEgAAAA==.',Lu='Lumen:BAABLAAECoEYAAISAAcIxgcfPQApAQASAAcIxgcfPQApAQAAAA==.',Ly='Lyss:BAAALAADCgIIAgABLAAFFAMICAARAAMZAA==.',Ma='Magzy:BAAALAAECgcIEwAAAA==.Marundo:BAABLAAECoEXAAIQAAYIvQkqagA5AQAQAAYIvQkqagA5AQAAAA==.',Mu='Mumble:BAAALAADCgcIBgAAAA==.',My='Mythic:BAAALAAECgIIAgAAAA==.',['Mí']='Mínuo:BAAALAAECgMIAwAAAA==.',No='Nora:BAAALAADCgcIBwABLAAECggIJwAVALwlAA==.Notegrus:BAAALAADCggICAABLAAECggIIQAPAH0ZAA==.Nov:BAAALAAECgMIAwAAAA==.',Ny='Nyahu:BAABLAAECoEpAAIXAAgIQSB3DgDgAgAXAAgIQSB3DgDgAgAAAA==.Nyandehu:BAAALAAECgMIAwAAAA==.Nyandra:BAAALAADCggICAAAAA==.Nyuu:BAAALAAECgUIBwABLAAECggIHAALABIjAA==.',Od='Oddsocks:BAACLAAFFIEFAAMPAAMIMyANAgAxAQAPAAMIMyANAgAxAQARAAEIBwROTABCAAAsAAQKgRsAAw8ACAixJMAGAA8DAA8ABwjrJcAGAA8DABEABwgKHUM7ADgCAAAA.',Om='Omelette:BAAALAAECgUIBQAAAA==.',Pa='Palacalz:BAAALAAECggIEAAAAA==.Pandamonium:BAAALAAECgEIAQAAAA==.',Pe='Percival:BAAALAADCggICQAAAA==.',Pi='Piston:BAAALAADCgYIBgAAAA==.',Po='Pog:BAAALAADCgIIAgAAAA==.',Pr='Prokeptor:BAABLAAECoEaAAMYAAcIVB6sDQBRAgAYAAcIVB6sDQBRAgAKAAYIqhhNdQClAQAAAA==.',Qu='Queldaran:BAAALAADCggICQAAAA==.',Ra='Rae:BAAALAAECgEIAQAAAA==.Ramy:BAABLAAECoEeAAMCAAgIyRqDHwBaAgACAAgIyRqDHwBaAgAEAAYIKAq0VgArAQAAAA==.Raval:BAAALAAECgYIBgAAAA==.',Ri='Rimandir:BAAALAAECgQIBQAAAA==.Riversong:BAAALAAECgYIDwAAAA==.',Ro='Romeo:BAAALAAECgMIAwAAAA==.',Sa='Salvation:BAAALAAECgIIAgAAAA==.',Sc='Scuffed:BAAALAAECgYIBgAAAA==.',Si='Siuksa:BAAALAAECgUIBQAAAA==.',Sk='Sk:BAAALAAECgYIDQABLAAFFAMIBQAPADMgAA==.',Sl='Slink:BAABLAAECoEsAAMZAAcI3CInEACUAgAZAAcIfyInEACUAgAaAAQIThuwJwAeAQABLAAFFAMIBQAPADMgAA==.',Sm='Smashstabber:BAAALAAFFAIIAgAAAA==.Smoku:BAAALAAECgYIBgABLAAECggIIAAUAFweAA==.Smokuqt:BAABLAAECoEgAAQUAAgIXB4MHgCvAgAUAAgIkh0MHgCvAgAbAAUI1BkREwBoAQAcAAMI5xCSXwC6AAAAAA==.Smokû:BAAALAADCgUIBQABLAAECggIIAAUAFweAA==.Smóku:BAABLAAECoEcAAIGAAgIdCOsCwD3AgAGAAgIdCOsCwD3AgABLAAECggIIAAUAFweAA==.',Sn='Snowtalon:BAAALAADCgYIBgAAAA==.',Sp='Sphyco:BAABLAAECoEZAAITAAcI8QYQSgAAAQATAAcI8QYQSgAAAQAAAA==.',St='Stonehoof:BAAALAADCggICAAAAA==.',Su='Superidol:BAAALAADCgIIAQAAAA==.',Sv='Svanchi:BAAALAAECgcIDAAAAA==.',Sy='Sylphie:BAAALAAECggICAAAAA==.Sylvie:BAABLAAECoEWAAIRAAgIDh6wGgDTAgARAAgIDh6wGgDTAgAAAA==.',Ta='Tarriell:BAAALAAECgIIAgAAAA==.',Ti='Tigres:BAABLAAECoEbAAIdAAcIjB0uDQBVAgAdAAcIjB0uDQBVAgAAAA==.',To='Tourcuic:BAACLAAFFIEKAAIEAAII9h9MEAC8AAAEAAII9h9MEAC8AAAsAAQKgR0AAgQABwhCIvcXAJECAAQABwhCIvcXAJECAAAA.',Tr='Trolld:BAAALAAECgcIEQAAAA==.Trull:BAABLAAECoEcAAIdAAgI4xmyDQBLAgAdAAgI4xmyDQBLAgAAAA==.Trulle:BAAALAADCgIIAgAAAA==.',Tu='Turbosaus:BAABLAAECoEYAAIeAAgIzw/rCgDMAQAeAAgIzw/rCgDMAQAAAA==.',Ty='Tyto:BAABLAAECoEWAAIfAAYIKRStGQBuAQAfAAYIKRStGQBuAQAAAA==.',Ve='Vermeil:BAAALAADCgIIAgAAAA==.Vesien:BAAALAADCggICAAAAA==.Vexifur:BAAALAAECgYIBgAAAA==.',Vo='Voixx:BAAALAAECgQIBAAAAA==.',Wa='Warlie:BAEALAADCggICAABLAAFFAUIEQAdAKsLAA==.',Wi='Wia:BAAALAAECgEIAQAAAA==.Willitblend:BAABLAAECoEjAAIgAAcIjR7IJAB8AgAgAAcIjR7IJAB8AgAAAA==.',Wo='Wolvespirit:BAAALAAECgIIAgAAAA==.',Xa='Xalder:BAAALAADCgIIAgAAAA==.Xanthippe:BAABLAAECoEfAAIEAAcIJx0UHgBeAgAEAAcIJx0UHgBeAgAAAA==.',Ye='Yerachmiel:BAABLAAECoEfAAICAAgIBQstSACLAQACAAgIBQstSACLAQAAAA==.',Ys='Yserae:BAAALAAECgUICAAAAA==.Yserra:BAAALAADCgcIBwAAAA==.',Yu='Yuanshi:BAABLAAECoEfAAIDAAgIfh7OCwC2AgADAAgIfh7OCwC2AgAAAA==.',Za='Zaot:BAAALAADCggIDwAAAA==.',Ze='Zekkhan:BAABLAAECoEYAAIQAAgIPCK0CgAoAwAQAAgIPCK0CgAoAwAAAA==.Zepla:BAAALAAECgQIBQAAAA==.Zervar:BAAALAADCggICQAAAA==.Zeurvival:BAABLAAECoEYAAIeAAgI0hBbCQDuAQAeAAgI0hBbCQDuAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end