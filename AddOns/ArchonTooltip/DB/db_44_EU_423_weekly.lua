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
 local lookup = {'Hunter-Marksmanship','Druid-Balance','Druid-Restoration','Unknown-Unknown','Priest-Holy','Mage-Frost','Shaman-Restoration','Warrior-Fury','Priest-Shadow','Warlock-Affliction','Paladin-Protection','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','DeathKnight-Frost','Warrior-Arms','Priest-Discipline','Rogue-Outlaw','DemonHunter-Vengeance','Hunter-BeastMastery','Paladin-Retribution','Paladin-Holy','Shaman-Elemental','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Blood','DeathKnight-Unholy','Monk-Brewmaster','Monk-Windwalker','Druid-Feral','Warrior-Protection',}; local provider = {region='EU',realm='DieewigeWacht',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abracowdabra:BAAALAADCgEIAQAAAA==.Abraxsas:BAAALAAECgUIBQABLAAECgcIFAABAAYYAA==.',Ad='Adranos:BAABLAAECoEaAAMCAAgI1xEsMQDMAQACAAcIghMsMQDMAQADAAgIdQN3eQDsAAAAAA==.',Ae='Aetheriion:BAAALAADCgQIBAAAAA==.',Ak='Akkan:BAAALAADCgUIBwABLAAECgYIEQAEAAAAAA==.',Al='Alaris:BAABLAAECoEZAAIFAAcIFxh+MwDvAQAFAAcIFxh+MwDvAQAAAA==.Alea:BAAALAAECgEIAQAAAA==.Alterbär:BAAALAAECgEIAQAAAA==.',Am='Amadea:BAAALAAECgYICwAAAA==.Amaneo:BAAALAADCgQIBAAAAA==.',An='Ancalagonn:BAAALAAECggIEAAAAA==.Anchsenamun:BAAALAADCgIIAgAAAA==.Anelia:BAAALAADCgYICwAAAA==.Anemone:BAAALAAECggICQAAAA==.Ansatsu:BAAALAAECgcICAAAAA==.Anur:BAAALAAECgYIDwAAAA==.',Aq='Aquira:BAABLAAECoEpAAIGAAgIchb9GQAnAgAGAAgIchb9GQAnAgAAAA==.',Ar='Aratack:BAAALAAECgcIBwAAAA==.Arwenis:BAAALAADCgcIBwAAAA==.',As='Asmera:BAABLAAECoEiAAIHAAgIFyBTEADQAgAHAAgIFyBTEADQAgAAAA==.',At='Atharion:BAAALAAECggICAABLAAECggIGAAIALgUAA==.Attrax:BAAALAADCggICwAAAA==.',Au='Aurôn:BAAALAAECgIIAwAAAA==.',Ay='Aymee:BAAALAADCgYIDgAAAA==.',Az='Azaba:BAAALAADCggIGQAAAA==.Azrael:BAABLAAECoEYAAIIAAgIuBRlNQAuAgAIAAgIuBRlNQAuAgAAAA==.',Ba='Baelorr:BAAALAAECgYIDQAAAA==.Bahamutt:BAAALAADCggIEQAAAA==.Baruc:BAAALAADCgcIDAAAAA==.Barucan:BAAALAADCggICAAAAA==.',Be='Betthupferl:BAAALAADCggICQAAAA==.',Bi='Bielefeld:BAAALAADCgcIBwAAAA==.',Bl='Blackstaff:BAAALAAECgMIBAAAAA==.Blutbertina:BAAALAAECgMIBgAAAA==.',Bo='Bonzo:BAAALAAECggIBQAAAA==.',Br='Brucelinchen:BAAALAADCggIEAAAAA==.',Bu='Bufferl:BAABLAAECoEXAAIJAAcIkx4IHAB0AgAJAAcIkx4IHAB0AgAAAA==.Buffy:BAABLAAECoEUAAIKAAYIaCH8BgBBAgAKAAYIaCH8BgBBAgAAAA==.Bumbelbee:BAAALAADCggIDgAAAA==.',['Bä']='Bärtigär:BAAALAAECgYIBgABLAAFFAIIBgADAG8OAA==.',Ca='Calariel:BAAALAAECgUIEQAAAA==.Caninus:BAAALAADCgYIBgAAAA==.Cattybrie:BAAALAAECgIIAgAAAA==.',Ch='Chaosdemon:BAAALAADCgEIAQAAAA==.Chinaclyra:BAAALAADCgcIBwABLAAECgcIFgALAIghAA==.Chinassa:BAABLAAECoEWAAILAAcIiCF6CgCpAgALAAcIiCF6CgCpAgAAAA==.',Cl='Classless:BAABLAAECoEWAAMMAAYI4CBITwD3AQAMAAYIaR9ITwD3AQAGAAIIiCFWXQC5AAAAAA==.Clipeatusus:BAAALAAECgEIAQAAAA==.',Co='Constantinos:BAAALAAECggICAAAAA==.Coên:BAABLAAECoEWAAMNAAcIhArQPQBTAQANAAcIhArQPQBTAQAOAAEINAfN3gAuAAAAAA==.',Cr='Crest:BAAALAAECgYIDQAAAA==.Cricou:BAAALAAECgUICgAAAA==.Cronu:BAABLAAECoEZAAIPAAcIjxkbXQDlAQAPAAcIjxkbXQDlAQAAAA==.Créatures:BAAALAAECgYIDQAAAA==.Crëst:BAAALAAECgIIAwAAAA==.',Cy='Cyrus:BAAALAADCggIEwAAAA==.',Da='Dalían:BAAALAAECgYIDgAAAA==.Darcelf:BAAALAADCggIEAAAAA==.Darknîght:BAABLAAECoEVAAIGAAgI9hjtFwA5AgAGAAgI9hjtFwA5AgAAAA==.Dathrohan:BAAALAADCggIDgAAAA==.',De='Denramonix:BAABLAAECoEbAAMDAAcIRxUEVgBVAQADAAYITRQEVgBVAQACAAII6Q62jwAyAAAAAA==.Derethor:BAABLAAECoEfAAIQAAgIxCHfFAAIAwAQAAgIxCHfFAAIAwAAAA==.Devlin:BAAALAADCgYIBgABLAAECgcIHgAIALogAA==.',Dh='Dhionas:BAAALAAECggIDAAAAA==.',Di='Dinindourden:BAAALAADCggICAAAAA==.Dispâter:BAAALAADCgYIBgAAAA==.',Do='Dokatha:BAAALAADCgEIAQABLAAECggIGAARABoGAA==.Dorothey:BAAALAAECgYIBQABLAAECgcIDwAEAAAAAA==.',Dr='Dragô:BAAALAADCgIIAwAAAA==.Drekan:BAAALAADCgUIBQAAAA==.Dronatega:BAAALAAECgEIAQAAAA==.',Du='Dugong:BAAALAADCggIDwAAAA==.',['Dá']='Dániá:BAABLAAECoEWAAQJAAYItQo1WQAoAQAJAAYItQo1WQAoAQAFAAEIwghbqAApAAASAAEI8wVrNwAnAAAAAA==.Dáx:BAAALAADCgUIAwAAAA==.Dáxx:BAAALAADCgcIDgAAAA==.',['Dâ']='Dârklîght:BAAALAAECgEIAQAAAA==.',['Dí']='Dímìtri:BAABLAAECoEgAAIOAAcIzRXMSwDeAQAOAAcIzRXMSwDeAQAAAA==.',['Dî']='Dîamond:BAABLAAECoEbAAITAAcIRhcDCgC+AQATAAcIRhcDCgC+AQAAAA==.Dîom:BAAALAADCgcIDQAAAA==.',Ek='Ekoo:BAAALAAECgMIAwABLAAFFAIIBgAUAPgMAA==.',El='Elsana:BAAALAAECgYICwAAAA==.',Em='Emmalina:BAABLAAECoEVAAIUAAYIqRUSIQB0AQAUAAYIqRUSIQB0AQABLAAECggIKgAHAJQYAA==.',En='Endora:BAAALAAECgYICQAAAA==.Enthyro:BAABLAAECoEVAAMVAAcI5SOqIQCeAgAVAAcI5SOqIQCeAgABAAII+hqwiwCLAAAAAA==.',Eo='Eos:BAAALAADCgcIDQAAAA==.',Er='Eragonia:BAAALAADCggIHQAAAA==.',Es='Eshren:BAAALAADCggICAABLAAECgcIDgAEAAAAAA==.',Fa='Falloutflo:BAAALAAECgIIAgAAAA==.Fauny:BAAALAAECgIIAgAAAA==.Fayette:BAAALAADCgcIBwAAAA==.',Fe='Fedérs:BAAALAADCgIIAgAAAA==.Felline:BAAALAAECgYIBgAAAA==.Fellus:BAAALAADCggIDAAAAA==.',Fh='Fhijondhreas:BAABLAAECoEYAAIRAAcIGgYnHgDxAAARAAcIGgYnHgDxAAAAAA==.',Fl='Flamel:BAAALAADCggIDAABLAAECgYIEQAEAAAAAA==.Flauschi:BAAALAAECgYIDAAAAA==.',Fr='Frederikus:BAABLAAECoEZAAIOAAYI3ghgjgAgAQAOAAYI3ghgjgAgAQAAAA==.',Ga='Galear:BAAALAADCgIIAgAAAA==.Garim:BAABLAAECoEZAAIWAAcILxYqcgDVAQAWAAcILxYqcgDVAQAAAA==.Garina:BAAALAAECgYICAAAAA==.',Ge='Geco:BAAALAAECgcIDQABLAAFFAMIDAAHAPsUAA==.Gekkò:BAABLAAECoEXAAIVAAcI2xUUfACGAQAVAAcI2xUUfACGAQAAAA==.',Gh='Ghedra:BAAALAADCgcIJAAAAA==.',Gn='Gnomero:BAAALAAECgYIEQAAAA==.',Gr='Grevonimo:BAAALAAECgQICQAAAA==.',Ha='Hariana:BAABLAAECoEZAAIQAAcIchLfrgBwAQAQAAcIchLfrgBwAQAAAA==.Hatschí:BAAALAADCgcIBwAAAA==.',He='Healenâ:BAABLAAECoEfAAIXAAcIIhpnGQAYAgAXAAcIIhpnGQAYAgAAAA==.Hellios:BAABLAAECoEpAAMHAAgIxwxyegBVAQAHAAgIxwxyegBVAQAYAAEIeQPysQAqAAAAAA==.Hexx:BAAALAADCggICAAAAA==.',Hi='Hiaria:BAABLAAECoEbAAMUAAcI3BQsKgAuAQAUAAcI3BQsKgAuAQAPAAIIgQsVCAFaAAAAAA==.',Ho='Hornia:BAAALAADCggIGwAAAA==.',Hu='Huyana:BAAALAADCgQIBgAAAA==.',Ia='Iang:BAAALAADCggICAABLAAECgYICQAEAAAAAA==.',Ic='Icecreamman:BAAALAAECgYICgABLAAFFAQICwAZAOUgAA==.',Ik='Ikamia:BAAALAADCgYIGAABLAAECgcIEwAEAAAAAA==.',Im='Immer:BAAALAADCgcIDAAAAA==.Impress:BAAALAADCgcIBwABLAAECgcIDwAEAAAAAA==.',In='Indu:BAABLAAECoEbAAMaAAgIjhbxDQAwAgAaAAgIjhbxDQAwAgAbAAMIywlsVwCHAAAAAA==.',Ir='Irisfacem:BAAALAAECgYIEAAAAA==.',Ja='Jasemin:BAAALAADCgcIDQAAAA==.',Jh='Jhola:BAABLAAECoEdAAICAAcIZA3ARABvAQACAAcIZA3ARABvAQAAAA==.',Jo='Jodara:BAABLAAECoEUAAIBAAcIBhiPLAAAAgABAAcIBhiPLAAAAgAAAA==.',Ju='Julês:BAABLAAECoEdAAIMAAcIfBmFVADnAQAMAAcIfBmFVADnAQAAAA==.Jumaji:BAAALAAECgcIEAAAAA==.',Ka='Kadness:BAAALAADCggICgAAAA==.Kaeda:BAAALAADCgcIDQAAAA==.Kaleeza:BAABLAAECoEbAAIJAAYIiRp2NADVAQAJAAYIiRp2NADVAQAAAA==.Kalumin:BAABLAAECoEWAAIXAAcI7g2LNABjAQAXAAcI7g2LNABjAQABLAAFFAIIAgAEAAAAAA==.Kariná:BAAALAAECgIIAgAAAA==.Katchen:BAABLAAECoEbAAIHAAYIywlbsQDhAAAHAAYIywlbsQDhAAAAAA==.Kawib:BAAALAAECgYIEwAAAA==.Kayah:BAAALAAECgUIBQAAAA==.',Kh='Khoriel:BAABLAAECoEZAAIbAAYIax1xIQD3AQAbAAYIax1xIQD3AQABLAAFFAIIAgAEAAAAAA==.',Ki='Kinobi:BAAALAADCgcICQAAAA==.',Kl='Klautomatix:BAAALAAECgIIAwAAAA==.',Ko='Kokosnuss:BAAALAAECgIIAgAAAA==.Komex:BAAALAADCggICAAAAA==.',Kr='Kratia:BAAALAADCgcICgAAAA==.Kreatör:BAABLAAECoEaAAIVAAcI4CHdOwAvAgAVAAcI4CHdOwAvAgAAAA==.Kreuner:BAAALAAECgIIAgAAAA==.Kropolis:BAAALAAECggICAAAAA==.Kryana:BAAALAADCgMIAwAAAA==.',La='Ladim:BAAALAADCggIFgAAAA==.Larouge:BAAALAADCggICAAAAA==.Lauie:BAAALAADCgMIAwAAAA==.Lavitz:BAAALAAECgQIAgAAAA==.Layra:BAAALAADCgcICgAAAA==.Layraani:BAAALAADCggIDQAAAA==.',Le='Lexinja:BAAALAADCgYIBgABLAAECgcIDwAEAAAAAA==.',Li='Liandrell:BAABLAAECoEcAAMMAAYIYhhzdwCCAQAMAAYIWxFzdwCCAQAGAAMIrRmfVgDdAAAAAA==.Lianka:BAAALAADCggIFAAAAA==.Liathia:BAAALAAECgcIDwAAAA==.Liathinu:BAAALAADCgYIBgABLAAECgcIDwAEAAAAAA==.Linkén:BAAALAADCgIIAgAAAA==.Linê:BAAALAADCggICAAAAA==.',Lo='Lodar:BAAALAAECgIIAgAAAA==.Lorule:BAAALAAECgEIAQAAAA==.Loupapagarou:BAAALAAECgYIEQAAAA==.Loxlay:BAAALAAECgIIAgAAAA==.',Lu='Lucyy:BAAALAADCgUIBQABLAAECggIHAAHAHQkAA==.Luminos:BAAALAADCgcICQAAAA==.Lunarg:BAAALAAECgUICAAAAA==.',Ly='Lynise:BAAALAAECgEIAQAAAA==.',['Lê']='Lêvînja:BAAALAADCgEIAQAAAA==.',['Lý']='Lýdan:BAAALAAECgYICgAAAA==.',Ma='Madrakor:BAAALAAECgUIBgABLAAECgcIDgAEAAAAAA==.Madymu:BAAALAADCgcIGgAAAA==.Magnix:BAABLAAECoEcAAQcAAcI/hUEIQA7AQAQAAYIbBNpqgB3AQAcAAYIXxUEIQA7AQAdAAEItwd5VQAzAAAAAA==.Mahaji:BAAALAADCgMIAwAAAA==.Maiky:BAAALAAECgYIDwAAAA==.Malyana:BAABLAAECoEeAAIVAAgI1hxeIwCWAgAVAAgI1hxeIwCWAgAAAA==.Mansan:BAAALAADCgcIBwAAAA==.Marøk:BAAALAADCgEIAgABLAAECgYICwAEAAAAAA==.Maximin:BAAALAAECgYICQAAAA==.',Mc='Mcandy:BAACLAAFFIELAAIVAAIIaCV1GADFAAAVAAIIaCV1GADFAAAsAAQKgTcAAhUACAgxJbkMABwDABUACAgxJbkMABwDAAAA.',Me='Meltdown:BAACLAAFFIEGAAMUAAII+AyaDQBpAAAPAAIIwwoDOACLAAAUAAII+AyaDQBpAAAsAAQKgSgAAxQACAi9GNgRAB8CABQACAgAF9gRAB8CAA8ACAgtFkdQAAcCAAAA.Metzopolis:BAAALAADCggIBQAAAA==.',Mi='Michaghar:BAABLAAECoEfAAMdAAgIASIvBgDpAgAdAAgI6iEvBgDpAgAQAAMI7RoU/gDdAAAAAA==.Mierro:BAABLAAECoEYAAMYAAcIRgpHdwAUAQAYAAcIRgpHdwAUAQAHAAMITwNc/gBNAAAAAA==.Miniroderia:BAAALAADCgcIBwABLAAECgYICgAEAAAAAA==.Minoria:BAAALAADCgIIAgAAAA==.Miralyn:BAABLAAECoEbAAIFAAcIoQd4bwAHAQAFAAcIoQd4bwAHAQAAAA==.Mirlan:BAAALAADCgEIAQAAAA==.Misandei:BAAALAAECgcIDgAAAA==.',Mo='Mord:BAAALAADCggIIwAAAA==.Morg:BAABLAAECoEgAAIGAAgI+iG6BgAUAwAGAAgI+iG6BgAUAwAAAA==.Morieria:BAAALAAECgMIAwABLAAECgYICwAEAAAAAA==.Motarion:BAAALAAECgIIAgAAAA==.',Mu='Munchkín:BAAALAAECgYIDAAAAA==.',['Mâ']='Mârimo:BAAALAAECgYIDQAAAA==.',['Mô']='Môônlight:BAAALAAECgYIDwAAAA==.',['Mø']='Møri:BAAALAAECgYICwAAAA==.',Na='Nachtfrost:BAAALAAECgEIAwAAAA==.Nagînî:BAAALAAECgcIEgAAAA==.Nap:BAAALAADCgcICAAAAA==.Narîko:BAACLAAFFIEGAAIOAAIICh+nIAC2AAAOAAIICh+nIAC2AAAsAAQKgSkAAg4ACAgZIngOABoDAA4ACAgZIngOABoDAAAA.Nasen:BAAALAAECgEIAQAAAA==.Natire:BAAALAAECgMIAwAAAA==.',Ne='Nemet:BAABLAAECoEUAAIXAAYIfxKcLwB/AQAXAAYIfxKcLwB/AQAAAA==.Nereus:BAACLAAFFIEGAAIVAAII6BzUOAB8AAAVAAII6BzUOAB8AAAsAAQKgSwAAhUACAhnHlwkAJACABUACAhnHlwkAJACAAAA.Neyith:BAAALAADCggICAAAAA==.',Ni='Niari:BAAALAAECgIIAgABLAAECgIIAgAEAAAAAA==.Nighttrive:BAAALAADCgcIBgAAAA==.Nimz:BAAALAADCgYIDAABLAAFFAMIDAAPAEILAA==.Nina:BAAALAAECgYIBgAAAA==.Ninoria:BAAALAADCgEIAQAAAA==.Nitche:BAAALAADCgcIBgAAAA==.',Nu='Nuovi:BAAALAADCgcICwAAAA==.Nussini:BAAALAAECgEIAQAAAA==.',['Ná']='Náomy:BAAALAADCgcIDgABLAAECgYIFgAJALUKAA==.',['Nâ']='Nâsty:BAABLAAECoEYAAMWAAcIPBaRhACxAQAWAAcI6hORhACxAQALAAEIRCC7VABgAAAAAA==.',['Ní']='Nímz:BAAALAAECgQIBAABLAAFFAMIDAAPAEILAA==.',['Nî']='Nîrlana:BAAALAADCgcIDQAAAA==.',['Nü']='Nüssli:BAABLAAECoEgAAIFAAcISBu2LAASAgAFAAcISBu2LAASAgAAAA==.',Om='Ommespommes:BAAALAADCggICAABLAAECgIIAgAEAAAAAA==.',Pa='Palibaba:BAAALAAECgYICAAAAA==.Patos:BAAALAADCgMIBAAAAA==.',Pe='Pegsch:BAAALAADCgcIBwAAAA==.',Ph='Philldloong:BAAALAAECgcIEwAAAA==.',Pp='Ppriest:BAAALAADCgcIBwAAAA==.',Pr='Protektor:BAAALAAECgMIBAAAAA==.',['Pí']='Píper:BAABLAAECoEmAAIPAAgI1CRiBQBkAwAPAAgI1CRiBQBkAwAAAA==.',Ra='Ravennia:BAAALAAECgIIAwAAAA==.Raz:BAAALAADCgIIAgAAAA==.Razka:BAAALAADCgcICAAAAA==.Raznarock:BAAALAADCgQIBwAAAA==.',Re='Reojin:BAABLAAECoEZAAIeAAcI4iPsBwDNAgAeAAcI4iPsBwDNAgAAAA==.',Rh='Rhelon:BAAALAADCgcIBwAAAA==.',Ri='Risna:BAAALAADCgYIBgAAAA==.',Ro='Rosaga:BAAALAAECgIIAwAAAA==.Roxadoxa:BAAALAAECgcIEwAAAA==.',Ru='Ruras:BAAALAAECgYIBgAAAA==.',Ry='Rynera:BAAALAAECgYIEgAAAA==.Ryuuk:BAAALAAECggIEAABLAAECggIGAAIALgUAA==.',['Rê']='Rêvên:BAAALAAECgIIAwAAAA==.',['Rì']='Rìnoa:BAAALAADCggIFwAAAA==.',Sa='Sajon:BAAALAADCgEIAQAAAA==.Saluná:BAAALAAECgYICwAAAA==.Santina:BAAALAADCgYICwAAAA==.',Sc='Schadralli:BAAALAAECgYIBgABLAAECgcIFAABAAYYAA==.Schamane:BAAALAADCgYIBgAAAA==.Schädowelff:BAABLAAECoEbAAIPAAcIegX6xwADAQAPAAcIegX6xwADAQAAAA==.Scorpion:BAAALAADCggIDQAAAA==.',Se='Secre:BAAALAADCggICAABLAAECgYIFAAfAIAcAA==.Seebär:BAAALAADCggIDwABLAADCggIFwAEAAAAAA==.Selola:BAAALAADCgEIAQAAAA==.Selolan:BAAALAADCggICAAAAA==.Senaya:BAAALAAECgYIDQAAAA==.Seranety:BAACLAAFFIEFAAIFAAIIVhArIgCUAAAFAAIIVhArIgCUAAAsAAQKgSAAAgUACAgwGqEdAGwCAAUACAgwGqEdAGwCAAAA.Serodían:BAAALAAECgMIAwAAAA==.Seytanja:BAABLAAECoEaAAIFAAcI1hLBTwByAQAFAAcI1hLBTwByAQAAAA==.',Sh='Shakotan:BAAALAADCggIHQAAAA==.Shanadorion:BAABLAAECoEcAAIHAAYIIRH1nAAJAQAHAAYIIRH1nAAJAQAAAA==.Sherì:BAAALAADCgMIAwAAAA==.Shi:BAACLAAFFIENAAMGAAQIRRFaAgAvAQAGAAQIlA9aAgAvAQAMAAMIFRAAAAAAAAAsAAQKgSYAAwYACAhEI3wFACoDAAYACAjaInwFACoDAAwACAhAHAAAAAAAAAAA.Shiro:BAABLAAECoEUAAIfAAYIgBxDKwB4AQAfAAYIgBxDKwB4AQAAAA==.Shizuko:BAABLAAECoEYAAIYAAgIER+yGAC3AgAYAAgIER+yGAC3AgAAAA==.Shoca:BAABLAAECoElAAQgAAgIZRZwEgAFAgAgAAcI9xdwEgAFAgACAAMIlA7UcACiAAADAAIIRBNtqgBZAAAAAA==.Shoci:BAAALAAECgMIBAAAAA==.Shunia:BAAALAADCgcIGwAAAA==.Shyrâna:BAAALAADCgQIBAAAAA==.',Si='Siatana:BAABLAAECoEWAAIDAAYIeRqYOADIAQADAAYIeRqYOADIAQAAAA==.Sinsemilla:BAABLAAECoEaAAIPAAcIKB1jNwBZAgAPAAcIKB1jNwBZAgAAAA==.',Sl='Slyder:BAAALAADCgcIDQAAAA==.Slyver:BAABLAAECoEVAAIBAAcIYg/NSgBxAQABAAcIYg/NSgBxAQAAAA==.',Sn='Snowwolf:BAAALAADCggICgAAAA==.',So='Sojih:BAABLAAECoElAAIFAAcI1g6GSwCDAQAFAAcI1g6GSwCDAQAAAA==.Solerian:BAAALAADCgEIAQAAAA==.',St='Stets:BAAALAADCgcIDgAAAA==.Stimpack:BAAALAAECggIEgABLAAFFAIIAgAEAAAAAA==.Stormi:BAAALAAECgYICAAAAA==.',Su='Suzaria:BAAALAAECggIDgABLAAFFAIIAgAEAAAAAA==.',['Sé']='Sénaya:BAAALAADCggIIgABLAAECgYIDQAEAAAAAA==.',Ta='Tadog:BAAALAAECgcICQAAAA==.Talinia:BAAALAADCgUIBgAAAA==.Talvì:BAAALAAECgUIBQAAAA==.Tarak:BAAALAAECggIEQAAAA==.Tarelia:BAAALAAECgIIAwAAAA==.Tawama:BAAALAADCggIFgAAAA==.',Te='Telemnar:BAAALAAECgQIAwAAAA==.',Th='Thorîn:BAAALAAECgYIEQAAAA==.Thutmosina:BAAALAAECgEIAQAAAA==.',Ti='Tibera:BAAALAADCgMIBAABLAADCggIHQAEAAAAAA==.Tilalia:BAAALAADCgIIAgAAAA==.Tiniare:BAAALAAECgQICQAAAA==.Tiranon:BAAALAAECgIIAgAAAA==.',Tj='Tjiara:BAAALAAECgYICQABLAAECgcIDwAEAAAAAA==.',Tr='Triana:BAACLAAFFIEIAAIDAAII1QxTJQCEAAADAAII1QxTJQCEAAAsAAQKgSQAAgMACAj/IEIIAAQDAAMACAj/IEIIAAQDAAAA.Tristanus:BAABLAAECoEaAAIhAAcIeg1KRQAiAQAhAAcIeg1KRQAiAQAAAA==.Trîst:BAACLAAFFIEMAAIPAAMIQgslFwDUAAAPAAMIQgslFwDUAAAsAAQKgSsAAg8ACAieH4AqAJACAA8ACAieH4AqAJACAAAA.',Ts='Tscholls:BAAALAADCggICAABLAAECggIGAARABoGAA==.Tsurára:BAAALAADCgIIAgABLAAECgYIFAAfAIAcAA==.',Un='Unkon:BAAALAADCgcIBwABLAAECgYIEQAEAAAAAA==.',Va='Valinôr:BAAALAAECgYIDgAAAA==.Vanity:BAAALAADCgUIBQABLAADCgYIDgAEAAAAAA==.',Ve='Veklar:BAABLAAECoEUAAIHAAcIZBeQWQCrAQAHAAcIZBeQWQCrAQAAAA==.Verala:BAAALAAFFAIIAgAAAA==.Verflucht:BAAALAADCgcICwAAAA==.',Vh='Vhaulor:BAAALAAECgMIAwABLAAECggIGAARABoGAA==.',Vo='Voidly:BAAALAAECggICAAAAA==.Volkani:BAAALAADCgYIBgAAAA==.Vorana:BAAALAADCgEIAQAAAA==.',Vy='Vykas:BAAALAAECgYIEQAAAA==.',['Ví']='Víola:BAAALAAECgYIDwAAAA==.',Wa='Wallkürè:BAAALAAECgUICAAAAA==.',We='Wendehals:BAAALAAECgEIAgAAAA==.',Wi='Wichteltante:BAAALAAECgEIAQAAAA==.Wild:BAAALAADCgIIAgAAAA==.',Wo='Wolke:BAAALAADCgcIBwAAAA==.Woogyo:BAACLAAFFIEHAAIJAAMIYhk7DQDzAAAJAAMIYhk7DQDzAAAsAAQKgS4AAgkACAj/IxIHADcDAAkACAj/IxIHADcDAAAA.Worcesters:BAAALAAECgMIBAAAAA==.',Xa='Xaden:BAAALAADCgYIBgAAAA==.Xalih:BAACLAAFFIEGAAIeAAIITg4NEAB5AAAeAAIITg4NEAB5AAAsAAQKgSEAAh4ACAgEG6YMAGYCAB4ACAgEG6YMAGYCAAAA.',Xi='Xixero:BAAALAADCgYIBgAAAA==.',Xo='Xolon:BAAALAADCgYIBgAAAA==.',Ya='Yawgmoth:BAAALAAECggICAAAAA==.',Ye='Yellowdragon:BAAALAADCggIJwAAAA==.',Yo='Yodaschi:BAACLAAFFIEHAAIGAAMILxbrBADYAAAGAAMILxbrBADYAAAsAAQKgR8AAgYABwgiI38PAI8CAAYABwgiI38PAI8CAAAA.Yoshimitsumg:BAABLAAECoEWAAIMAAcI3BzZOABJAgAMAAcI3BzZOABJAgAAAA==.',Yu='Yukihime:BAAALAADCggIDQABLAAECgYIFAAfAIAcAA==.',Za='Zacknefein:BAABLAAECoEeAAMIAAcIuiApKABxAgAIAAcIfiApKABxAgARAAMIkxIrIwCxAAAAAA==.Zamor:BAAALAAECgUIBQAAAA==.',Ze='Zeiron:BAAALAAECgcICgAAAA==.Zeitgeist:BAAALAADCggIGQAAAA==.Zendiwari:BAAALAAECgQIBgAAAA==.Zeroforone:BAAALAADCgcIDQAAAA==.',Zw='Zwoó:BAAALAAECgcIEQAAAA==.',Zy='Zyr:BAAALAAECggIEAABLAAECggIGAAIALgUAA==.',['Zü']='Zündhütchen:BAABLAAECoEcAAIVAAYIgRU9jABlAQAVAAYIgRU9jABlAQAAAA==.',['Êx']='Êxorr:BAAALAADCgYIBgABLAAECggIJgAZAPEkAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end