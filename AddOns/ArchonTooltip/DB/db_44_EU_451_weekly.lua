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
 local lookup = {'DeathKnight-Frost','Priest-Shadow','DemonHunter-Havoc','Druid-Balance','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Vengeance','Warrior-Fury','Rogue-Assassination',}; local provider = {region='EU',realm='Nathrezim',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ai='Airesh:BAAALAADCgYIBgAAAA==.',Aj='Ajuko:BAAALAADCggICwAAAA==.',Ak='Akenias:BAABLAAECoEVAAIBAAgIaSZ8AACHAwABAAgIaSZ8AACHAwABLAAFFAYIDgACAJMkAA==.',Al='Alecia:BAAALAAECgUIBwAAAA==.Aliranas:BAAALAAECgYIDAAAAA==.',Am='Amandus:BAAALAADCggICAAAAA==.Ampicillin:BAAALAAECgMIAwAAAA==.',Ar='Aristana:BAAALAAECgMIAwAAAA==.Arkail:BAAALAAECgIIAgAAAA==.Arsamandi:BAAALAAECgQICgAAAA==.',Au='Auxi:BAAALAAECgIIAgAAAA==.Auxii:BAAALAADCggIDwAAAA==.',Ay='Ayumii:BAAALAAECgMIBQAAAA==.',Az='Azazul:BAAALAAECgEIAQAAAA==.',Ba='Bacardíto:BAAALAADCgcICgAAAA==.Baldêr:BAAALAAECgYICQAAAA==.Barrin:BAAALAAECgMIBgAAAA==.',Bi='Bigscar:BAAALAAECgMIBQAAAA==.Bigyiatch:BAACLAAFFIEKAAIDAAUIsxD3AADFAQADAAUIsxD3AADFAQAsAAQKgRgAAgMACAiVJRoBAH8DAAMACAiVJRoBAH8DAAAA.',Bl='Blogran:BAAALAAECgMIBQAAAA==.',Bo='Boozedh:BAAALAADCgYIBwAAAA==.',Br='Brandor:BAAALAADCgYIDAAAAA==.Brangbok:BAAALAADCggICQAAAA==.Bratkartoffl:BAAALAAECgMIBAAAAA==.Brolax:BAAALAADCgcIDQAAAA==.',Bu='Bulldog:BAAALAADCgQIBAAAAA==.Burtock:BAAALAADCgUIBQAAAA==.',['Bô']='Bôoze:BAABLAAECoEYAAIEAAgIJyN+AwAtAwAEAAgIJyN+AwAtAwAAAA==.',Ca='Cactus:BAAALAADCgcIDgAAAA==.Caregiver:BAAALAADCgQIBwAAAA==.',Ch='Charlz:BAAALAAECgYIBwAAAA==.Chillerrufer:BAAALAAECgYIBgAAAA==.',Da='Damaaruhn:BAACLAAFFIEFAAMFAAMIXR00AQDJAAAFAAII0Bw0AQDJAAAGAAEIdx4AAAAAAAAsAAQKgRcABAUACAjdJC8EAJ4CAAUABgiDJS8EAJ4CAAcAAgiDHc8YAMIAAAYAAQisH1JeAF4AAAAA.Darasha:BAAALAAECgIIAwAAAA==.Darkshamen:BAAALAAECggICAAAAA==.Darksim:BAAALAAECgEIAQAAAA==.',De='Deathranger:BAAALAAECgIIBQAAAA==.Decon:BAAALAADCggICAAAAA==.Deepvibes:BAAALAADCggIBwAAAA==.Dellana:BAABLAAECoEUAAIIAAgIBBniDgBcAgAIAAgIBBniDgBcAgAAAA==.Demage:BAAALAAECgMIBQAAAQ==.Demonerich:BAAALAADCgEIAQAAAA==.Derfeige:BAAALAADCggICAAAAA==.Devii:BAAALAADCgMIAwAAAA==.',Di='Diabolus:BAAALAAECgYIBgAAAA==.Dinora:BAAALAADCgQIBAABLAAECgIIBAAJAAAAAA==.',Do='Donnerbüchse:BAAALAADCggICwAAAA==.',Dr='Drem:BAAALAADCgQIBAAAAA==.',Du='Dubbie:BAAALAADCggICwABLAADCggIEAAJAAAAAA==.Dunao:BAAALAADCggIDgAAAA==.',['Dé']='Démonhunter:BAAALAADCgQIAwAAAA==.',Ea='Easydeath:BAAALAAECgMIAwAAAA==.',Ei='Eisenschwein:BAAALAAECgIIAwAAAA==.',El='Elsaruman:BAAALAADCgcIDQAAAA==.',En='Enton:BAABLAAECoEWAAMKAAgIcSD1BQDbAgAKAAgIcSD1BQDbAgALAAEILRcOcwBPAAAAAA==.',Fa='Faeyn:BAAALAAECgIIAgAAAA==.Fancel:BAAALAAECgQIBwAAAA==.',Fi='Fidulaa:BAAALAADCgEIAQAAAQ==.Fizli:BAAALAADCggIEAAAAA==.',Fr='Freya:BAAALAAECgIIAgAAAA==.Frostzwerg:BAAALAADCgcIBwAAAA==.',['Fê']='Fêârdôtcôm:BAAALAADCgIIAwAAAA==.',Ga='Gandolf:BAAALAADCggIDgABLAAECggIFgAKAHEgAA==.Ganschar:BAAALAAECgIIAgAAAA==.',Ge='Gewitter:BAAALAADCgcIDQAAAA==.',Gr='Grandseiko:BAAALAAECgcICQAAAA==.Gromalo:BAAALAAECgcIEQAAAA==.',Ha='Happý:BAAALAADCggIDwAAAA==.',He='Hebdieschere:BAAALAAECggICAAAAA==.',Ib='Ibraham:BAAALAADCgQIBAAAAA==.',If='Ifelia:BAABLAAECoEUAAIMAAcImR0XBQBdAgAMAAcImR0XBQBdAgAAAA==.',Im='Imbaness:BAAALAADCggIDgABLAAECgcIEAAJAAAAAA==.Imperiales:BAAALAADCgcICQAAAA==.',In='Intankos:BAAALAAECgYIEAAAAA==.',Is='Ishaar:BAAALAADCgMIAwAAAA==.Iskîerka:BAAALAADCggICQAAAA==.',Iz='Izeron:BAAALAADCgUIAQAAAA==.',Ja='Jadranko:BAAALAAECgIIAgAAAA==.',Je='Jeathor:BAAALAAECgYIBwAAAA==.',Jo='Jockâ:BAABLAAECoEWAAINAAgIbQK8PwDMAAANAAgIbQK8PwDMAAAAAA==.',['Jê']='Jênovâ:BAAALAADCgUIBQAAAA==.',Ka='Karizma:BAAALAADCgcIAQAAAA==.Karrian:BAAALAADCggIEAAAAA==.Kayrizzma:BAAALAAECgIIAgAAAA==.',Ke='Kegth:BAAALAAECgQIBwAAAA==.Keni:BAAALAAECgMIAwAAAA==.',Kh='Khida:BAAALAAECgMIAwAAAA==.',Ki='Killerorx:BAAALAADCgYIBAAAAA==.',Kr='Krathor:BAAALAAECgYIBwAAAA==.',Ku='Kuhmosapiens:BAAALAADCggIFgAAAA==.',La='Layo:BAAALAAECgMIBAAAAA==.',Le='Lehtera:BAAALAADCgYIBgAAAA==.Lemonly:BAABLAAECoEVAAIOAAgIwxdyCwB7AgAOAAgIwxdyCwB7AgABLAAFFAUICgADALMQAA==.Leome:BAAALAAECgMIBgAAAA==.',Li='Liamos:BAAALAAECgMIAwAAAA==.Liinara:BAAALAADCgIIAgAAAA==.',Lo='Lorewalker:BAAALAAECgMIBQAAAA==.',Lu='Lugbúrz:BAAALAAECgcIEQAAAA==.',Ly='Lycaramba:BAAALAADCggICAAAAA==.',Ma='Mahakali:BAAALAAECgMIBQAAAA==.Maki:BAAALAADCggICAABLAAFFAUICgADALMQAA==.Maronai:BAAALAAECgcICAAAAA==.Marshadow:BAAALAADCgYIBgAAAA==.Maul:BAAALAAECgcIEAAAAA==.',Me='Melèk:BAAALAADCggICAAAAA==.',Mi='Michelangelu:BAAALAAECgYICAAAAA==.Milsana:BAAALAAECgMIAwAAAA==.Minami:BAAALAAECgYICAAAAA==.Minthal:BAAALAADCgYIDAABLAADCggIDQAJAAAAAA==.',Mo='Mordrain:BAAALAADCgYIBgAAAA==.Mortìscha:BAAALAADCgcIBwAAAA==.Mourne:BAAALAADCgQIBAAAAA==.',Mu='Mufasá:BAAALAAECgYIBgAAAA==.Muhz:BAAALAAECgEIAQAAAA==.Muuhli:BAAALAAECgIIAgAAAA==.',My='Mysery:BAAALAADCgcICwAAAA==.Mysos:BAAALAADCggIDQAAAA==.',['Mà']='Màgistrix:BAAALAADCggIDgABLAAECgEIAQAJAAAAAA==.',['Mâ']='Mâusî:BAAALAAECgEIAgAAAA==.',['Mí']='Míyou:BAAALAADCgQIBQAAAA==.',Na='Narashi:BAAALAADCggICwAAAA==.Naràke:BAAALAAECgcIDAAAAA==.',Ne='Neofelis:BAAALAADCggIFwAAAA==.',Ni='Nicolasrage:BAAALAADCgYIBgAAAA==.Nightbreaker:BAAALAADCgcIBgAAAA==.Nimueh:BAAALAAECgIIBAAAAA==.Nishoola:BAAALAAECgIIAwAAAA==.Niuz:BAAALAADCgcIBwAAAA==.',Om='Omi:BAAALAAECgEIAQAAAA==.Omir:BAAALAADCgcIEAAAAA==.',Ou='Outrage:BAAALAAECgYICQAAAA==.Outráge:BAAALAAECgIIAgAAAA==.',Pa='Pange:BAAALAAECgIIAgAAAA==.',Pe='Peccatum:BAAALAAECgIIAgAAAA==.Perot:BAAALAADCggIDwAAAA==.',Ra='Rae:BAAALAADCggIDgAAAA==.Ragosa:BAAALAAECgEIAQAAAA==.Rajindo:BAAALAADCgcICQABLAAECgUIBwAJAAAAAA==.',Re='Reileigh:BAAALAAECgEIAQAAAA==.',Rn='Rngesus:BAAALAADCgYIBwAAAA==.',Ro='Roqu:BAAALAAECggIDwAAAA==.Rosckarnar:BAAALAADCgUIBQAAAA==.',Sc='Scrappy:BAAALAADCgYIBgAAAA==.',Sh='Shadowseeker:BAAALAAECgcIEAAAAA==.Shanadee:BAAALAADCgIIAgAAAA==.Shantari:BAAALAAECgIIBAAAAA==.Shîndral:BAAALAADCgUIBQAAAA==.',Si='Signum:BAAALAADCgUIBQABLAAECgMIBQAJAAAAAA==.Sintharia:BAAALAADCgcIBwAAAA==.',Sm='Smokys:BAAALAADCgcIBwAAAA==.Smokysthane:BAAALAADCgcIDQAAAA==.',So='Sora:BAAALAADCggICQAAAA==.',Sp='Speermarkus:BAAALAADCggICAAAAA==.',St='Stiftix:BAAALAADCgcIAgAAAA==.',Su='Sukkubus:BAAALAAECgEIAgAAAA==.',Sy='Syráx:BAAALAAECgIIAgABLAAECgIIBAAJAAAAAA==.',['Sû']='Sûramienne:BAAALAADCggICAAAAA==.',Ta='Talaaron:BAAALAADCgcIBwAAAA==.Tashina:BAAALAADCggIBwAAAA==.',Te='Teldina:BAAALAADCggICwABLAAECgcIEwAJAAAAAA==.Teldumage:BAAALAAECgcIEwAAAA==.Teldurîn:BAAALAADCggICAABLAAECgcIEwAJAAAAAA==.Telia:BAAALAADCggIEAABLAAECgcIFAAMAJkdAA==.Terrix:BAAALAAECgYIDwAAAA==.',Ti='Tinkerbella:BAAALAAECgcIBwAAAA==.Tisar:BAAALAAECgcIEAAAAA==.',To='Todesringo:BAAALAAECgEIAQABLAAECgIIBQAJAAAAAA==.Totalschaden:BAAALAADCgcICwAAAA==.',Tr='Trashadin:BAAALAADCggIDQAAAA==.Trashdiva:BAAALAADCggICAAAAA==.Treyce:BAACLAAFFIEOAAMCAAYIkyRVAAA+AgACAAUI1iZVAAA+AgAIAAIIcCIcBQDVAAAsAAQKgRgAAgIACAjxJgcAAKsDAAIACAjxJgcAAKsDAAAA.Tryxie:BAAALAADCggIEAABLAAECgcIFAAMAJkdAA==.',['Tô']='Tômkâr:BAAALAAECgEIAQAAAA==.',Un='Unhailbar:BAAALAADCgMIAwABLAADCgcIDQAJAAAAAA==.',Va='Vaburdine:BAAALAADCgYIBwAAAA==.Vadamosky:BAAALAADCgEIAQAAAA==.Valana:BAAALAADCggICAAAAA==.',Ve='Veyo:BAAALAAECgMIBgAAAA==.',Vi='Vitocorleone:BAAALAAECgIIAgAAAA==.',Vo='Vollaufsmaul:BAAALAADCggICQAAAA==.Volltroll:BAAALAAECgUIBQAAAA==.Voluntas:BAAALAADCggICAAAAA==.',Wa='Wandor:BAAALAADCgUIBQAAAA==.Warfare:BAAALAAECgYIDwAAAA==.',Wo='Wolfdragon:BAAALAADCggIDgAAAA==.',Wy='Wynardtages:BAAALAAECggIEQAAAA==.',['Wù']='Wùmpscut:BAAALAADCggIEAAAAA==.',Xa='Xan:BAAALAAECgMIAwAAAA==.Xarona:BAAALAADCggICQAAAA==.Xawora:BAAALAADCggICAAAAA==.Xaworu:BAAALAADCggIEAAAAA==.',Xe='Xenn:BAAALAADCgcICQAAAA==.',Ya='Yanck:BAAALAAECgYIBgAAAA==.',Za='Zalana:BAAALAADCgQIBAAAAA==.',Ze='Zentila:BAAALAAECgYIDAABLAAECgcIFAAMAJkdAA==.Zernichtung:BAAALAAECggICAAAAA==.Zerspaltung:BAAALAADCgQIBgABLAAECggICAAJAAAAAA==.',['Êx']='Êxó:BAAALAAECgcIDQAAAA==.',['Ðo']='Ðorfmofa:BAAALAADCggICAAAAA==.',['Ño']='Ñova:BAAALAAECggIDAAAAA==.',['Ñø']='Ñøva:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end