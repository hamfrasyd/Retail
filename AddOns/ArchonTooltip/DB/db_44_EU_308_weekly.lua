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
 local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Druid-Restoration','Warrior-Protection','DeathKnight-Blood','Hunter-Marksmanship','Warlock-Destruction','Hunter-BeastMastery','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Shaman-Restoration','Shaman-Elemental','DeathKnight-Frost','Paladin-Retribution','Warrior-Fury','Priest-Holy','DemonHunter-Vengeance','Mage-Frost','Druid-Guardian','Monk-Windwalker','Paladin-Protection','Warrior-Arms','Warlock-Demonology','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Druid-Feral','Paladin-Holy','Priest-Shadow',}; local provider = {region='EU',realm='KulTiras',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aarwen:BAAALAADCggIDgABLAAECgYIGwABAB8jAA==.',Ac='Achilleas:BAAALAAECgMIBAAAAA==.',Af='Afrodita:BAAALAAECgcIDgABLAAECggIEAACAAAAAA==.',Ag='Agrelle:BAABLAAECoEdAAIDAAgIQRGLPgCmAQADAAgIQRGLPgCmAQAAAA==.',Ai='Aizu:BAAALAAECgYIEAAAAA==.',Ak='Akile:BAABLAAFFIEXAAIEAAcIBSFEAADSAgAEAAcIBSFEAADSAgABLAAFFAYICQAFAF4hAA==.Akivasha:BAAALAAECgQICQAAAA==.',Al='Alabara:BAABLAAECoEUAAIGAAYIbRZKPwCbAQAGAAYIbRZKPwCbAQAAAA==.Alexandrina:BAAALAAECgYIEgAAAA==.Alexandruid:BAAALAADCgYIBgAAAA==.',Am='Amaraa:BAABLAAECoEaAAIHAAcIlBLKTgDLAQAHAAcIlBLKTgDLAQAAAA==.Amedeu:BAAALAADCgcIBwAAAA==.Amidofen:BAAALAAECggIEAAAAA==.Amzil:BAAALAAECgYIBgAAAA==.',An='Anevay:BAAALAADCgUIBQAAAA==.Annsin:BAABLAAECoEYAAIIAAcIuh47PAAiAgAIAAcIuh47PAAiAgAAAA==.',Ap='Apokaliio:BAAALAADCggIGAAAAA==.Apokkalio:BAAALAADCgMIAwABLAADCggIGAACAAAAAA==.Apureborn:BAAALAAECgYIBgAAAA==.',Aq='Aquilinus:BAAALAADCgcIDQAAAA==.',Ar='Arenith:BAACLAAFFIELAAIJAAUI9R4fAwDqAQAJAAUI9R4fAwDqAQAsAAQKgSwABAkACAizJTAEAEEDAAkACAizJTAEAEEDAAoAAwgiI2IfACwBAAsAAwi1G4oQALYAAAAA.Aridian:BAAALAADCgIIAgAAAA==.Arothas:BAAALAAECggICgAAAA==.Artaios:BAAALAADCgcIDQAAAA==.',Au='Auris:BAABLAAECoEaAAIGAAcIyBRIOAC7AQAGAAcIyBRIOAC7AQAAAA==.',Ay='Aydris:BAAALAAECgUIDAAAAA==.',Az='Azina:BAACLAAFFIEJAAIMAAMIohnYCgARAQAMAAMIohnYCgARAQAsAAQKgRwAAwwABwhTJJ4SALwCAAwABwhTJJ4SALwCAA0AAghtIU2FALsAAAAA.',Ba='Baltrou:BAAALAADCgYIBgABLAAFFAUIEwAOAJEiAA==.Bankerdeg:BAAALAADCggIEAAAAA==.',Be='Benzigaz:BAAALAADCggIDAAAAA==.Berserkr:BAAALAAECgIIAgAAAA==.Bexy:BAAALAAECgIIAgAAAA==.',Bi='Biscuittea:BAAALAADCgMIBAAAAA==.',Bk='Bkcd:BAAALAAECgYIEwAAAA==.',Bo='Boinkki:BAAALAAECgIIAgAAAA==.Borvo:BAAALAAECgYIEwAAAA==.',Br='Brenrik:BAAALAADCgYICgAAAA==.Bronzemane:BAAALAADCgYIBgAAAA==.Bruhbble:BAAALAADCggICAAAAA==.Brumir:BAAALAADCggIEAAAAA==.',Ca='Cacodemon:BAABLAAECoEcAAIPAAgI8QS/zgAdAQAPAAgI8QS/zgAdAQAAAA==.Casrot:BAAALAAECgEIAQAAAA==.Castan:BAACLAAFFIEMAAMQAAUIeRxhBgDMAQAQAAUIeRxhBgDMAQAEAAIIIBPaEgCCAAAsAAQKgRcAAxAACAhIJR4QAAsDABAACAhIJR4QAAsDAAQAAgg0Hx9dAJoAAAAA.Castiana:BAECLAAFFIEKAAIRAAQIyxYVCABKAQARAAQIyxYVCABKAQAsAAQKgRcAAhEACAh9Gx4gAFYCABEACAh9Gx4gAFYCAAAA.Cay:BAABLAAECoEXAAISAAYIwA5uLAAUAQASAAYIwA5uLAAUAQAAAA==.',Ch='Charmelina:BAAALAADCggICAAAAA==.Chrysalis:BAABLAAECoEpAAIBAAcI3iGzJAClAgABAAcI3iGzJAClAgAAAA==.',Ci='Cindradeath:BAAALAAECgQIBgAAAA==.Cindraholy:BAAALAADCggICAAAAA==.Cindralock:BAABLAAECoEaAAIHAAgITxhoMABIAgAHAAgITxhoMABIAgAAAA==.',Cl='Clageddin:BAABLAAECoEdAAIRAAgIHhnoIQBKAgARAAgIHhnoIQBKAgAAAA==.Claim:BAAALAAECgEIAQAAAA==.Cleed:BAAALAADCgUIBgAAAA==.',Da='Danji:BAAALAADCgcIDQAAAA==.Darkhaus:BAAALAADCgYIBgAAAA==.Darksoul:BAAALAAECgEIAQAAAA==.Dazage:BAAALAAECgcIEAAAAA==.',De='Deackard:BAAALAAECgYIBgAAAA==.Deathpelt:BAAALAAECgIIAgABLAAECggIHAATALAdAQ==.Deathwisherr:BAAALAAECggICAAAAA==.Dedz:BAAALAADCggIDgAAAA==.Demohan:BAAALAADCgYIDAAAAA==.Denovox:BAACLAAFFIEKAAIUAAMI0CK4AAA5AQAUAAMI0CK4AAA5AQAsAAQKgRsAAhQACAihJbQAAHMDABQACAihJbQAAHMDAAAA.',Di='Dijango:BAAALAAECggICAAAAA==.',Dk='Dklady:BAAALAADCgQIBgABLAAECggIEAACAAAAAA==.',Do='Dontcarebear:BAAALAAECgcIBwABLAAFFAUIDAAVAD8PAA==.Down:BAABLAAECoEXAAIWAAcIiRPiIgCcAQAWAAcIiRPiIgCcAQAAAA==.',Dp='Dp:BAAALAAECggICAAAAA==.',Dr='Dragonloc:BAAALAAECgYIEAAAAA==.Druda:BAABLAAECoEZAAIDAAYIgSOBGgBgAgADAAYIgSOBGgBgAgAAAA==.',Du='Dudududududu:BAABLAAECoEZAAIPAAgIqx92HADgAgAPAAgIqx92HADgAgAAAA==.Dumplings:BAAALAAECggICAABLAAECggIHAATALAdAQ==.Duskstrider:BAAALAAECgYIEAAAAA==.',Dv='Dv:BAAALAADCggICAABLAAECggIFQACAAAAAQ==.',['Dà']='Dàrren:BAAALAAECgUICwAAAA==.',['Dâ']='Dârklight:BAAALAADCgcIBwAAAA==.',['Dò']='Dòx:BAAALAADCggIHAABLAAECgYIFQAVAHMZAA==.',El='Elvenelder:BAAALAADCggIGAAAAA==.',En='Encheladus:BAAALAAECgcIEAAAAA==.',Eo='Eoline:BAAALAAECgYIEAAAAA==.',Er='Eryndor:BAABLAAECoEWAAMXAAYI+hIJGgAhAQAQAAYI+hIzawBtAQAXAAYIqwkJGgAhAQAAAA==.',Ex='Expiator:BAAALAAECgYIEwAAAA==.',Fi='Fiorano:BAAALAAECgcIDgAAAA==.Fishslap:BAACLAAFFIEMAAIVAAUIPw8hAwCYAQAVAAUIPw8hAwCYAQAsAAQKgR0AAhUACAjZHNYQAHACABUACAjZHNYQAHACAAAA.',Fl='Flaminis:BAAALAAECgYIBwAAAA==.Flaskekork:BAABLAAECoEkAAIIAAgIeyFqFgDYAgAIAAgIeyFqFgDYAgAAAA==.',Fo='Folkenor:BAAALAAECgYIEAAAAA==.Fordealyn:BAACLAAFFIEJAAMHAAUI7RlOCQDOAQAHAAUIoBhOCQDOAQAYAAEIiBUBGgBdAAAsAAQKgRUAAxgACAh/IwYKAKcCAAcABwjRImgYANQCABgACAjFHgYKAKcCAAAA.Foxford:BAABLAAECoEWAAIHAAgIshp9IwCNAgAHAAgIshp9IwCNAgABLAAECggIHAATALAdAA==.Foxrogerbeer:BAABLAAECoEcAAIBAAcIDQz6hQCDAQABAAcIDQz6hQCDAQAAAA==.',Fr='Freya:BAAALAAECgYIBgAAAA==.',Ft='Ftw:BAAALAAECgQIBAAAAA==.',Fu='Funtimes:BAAALAAECgcIDAAAAA==.Fuzzybrows:BAAALAADCgQIBAAAAA==.',Ga='Gars:BAAALAADCggICAAAAA==.',Gi='Gilarás:BAAALAADCgcIBwAAAA==.',Go='Goldenlay:BAAALAAECgIIAgABLAAECggIHAATALAdAQ==.',Ha='Haelix:BAABLAAECoEYAAIZAAgIZRmZIgAcAgAZAAgIZRmZIgAcAgAAAA==.Halonn:BAAALAAECggICAAAAA==.Happy:BAAALAADCggIHwAAAA==.',He='Helvar:BAAALAAECggIEwAAAA==.',Ho='Holmqvist:BAAALAAECgYIBgAAAA==.Holyjosh:BAAALAAECgEIAQAAAA==.',Hu='Hunttn:BAAALAADCggICAAAAA==.',Id='Idle:BAAALAAECgYIEgAAAA==.',In='Incarnum:BAABLAAECoEXAAIUAAcI/A3tEwBMAQAUAAcI/A3tEwBMAQAAAA==.Ink:BAAALAADCgUIBQAAAA==.',Ir='Ira:BAAALAAECgYIDAAAAA==.',Ja='Jadee:BAAALAADCgIIAgAAAA==.Jagura:BAAALAAECgYICAAAAA==.January:BAAALAAECgYIDQAAAA==.',Je='Jever:BAABLAAECoEVAAIVAAYIcxkUIQDAAQAVAAYIcxkUIQDAAQAAAA==.',Ji='Jihto:BAAALAADCggICAAAAA==.',Ju='Julienne:BAAALAADCgQIBAAAAA==.',['Já']='Jámíe:BAABLAAECoEcAAIPAAgIFx1uJwCpAgAPAAgIFx1uJwCpAgAAAA==.',Ka='Kaelna:BAAALAADCgcIDwAAAA==.Kamino:BAAALAADCggICAAAAA==.Kazibo:BAABLAAECoEoAAMWAAgImhvBDwBUAgAWAAgImhvBDwBUAgAPAAMIPBgg8gDGAAAAAA==.',Ke='Kelsara:BAABLAAECoEXAAIRAAcIVB0MIwBDAgARAAcIVB0MIwBDAgAAAA==.',Ki='Kirsin:BAAALAAECgYIBgAAAA==.',Kl='Kleivyn:BAABLAAECoEXAAIPAAcIPxyJQABKAgAPAAcIPxyJQABKAgAAAA==.Kloabo:BAAALAAECgEIAQAAAA==.',Kn='Knabby:BAABLAAECoEUAAIRAAYI9hrkNwDTAQARAAYI9hrkNwDTAQAAAA==.',Ko='Koiot:BAAALAADCggICgABLAAECggIEAACAAAAAA==.',Kr='Krier:BAAALAAECgYIBgABLAAFFAMIBgAOAC8UAA==.',La='Lannisham:BAEALAAECggICQABLAAECggIEQACAAAAAA==.Lath:BAACLAAFFIEWAAIDAAYI3xodAQAyAgADAAYI3xodAQAyAgAsAAQKgTEAAgMACAjJJSoBAGwDAAMACAjJJSoBAGwDAAAA.',Le='Leannan:BAAALAADCggICAAAAA==.',Li='Liamneeson:BAAALAAFFAIIAgAAAA==.Linkez:BAAALAAECgYIEAAAAA==.',Lo='Lonehuntress:BAAALAADCgcICwAAAA==.Lorienne:BAAALAAECgQIBAAAAA==.',Lu='Lulläby:BAAALAADCgMIAwABLAAECgYIGwABAB8jAA==.Lunaasa:BAAALAADCggICAAAAA==.',Ly='Lyoria:BAAALAADCggIDwAAAA==.',Ma='Macy:BAAALAADCgMIBAAAAA==.Maeliven:BAAALAAECgEIAQAAAA==.Malucifer:BAABLAAECoEYAAIBAAcIvxNKZwDEAQABAAcIvxNKZwDEAQAAAA==.Mamsebumsen:BAAALAAECgMIAwAAAA==.Maximus:BAAALAADCggIEwAAAA==.',Mi='Micara:BAAALAADCggIDQAAAA==.Milk:BAAALAAECgcIEwAAAA==.Milou:BAAALAAECgYICgAAAA==.Minuva:BAAALAAFFAIIBAABLAAFFAUICQAHAO0ZAA==.Miramizz:BAAALAADCgYICQAAAA==.',Mo='Morrisons:BAABLAAECoEWAAMaAAcIuSWyBgAKAwAaAAcIuSWyBgAKAwAbAAEIjQuORAArAAAAAA==.Moshimosh:BAAALAAECgYICQAAAA==.',Ms='Msd:BAAALAAECgcICAAAAA==.',['Mî']='Mîhr:BAAALAADCggICAAAAA==.',Na='Nadgob:BAAALAADCgYICwAAAA==.Nanski:BAABLAAECoEcAAIcAAgIoApFGgCgAQAcAAgIoApFGgCgAQAAAA==.Narim:BAAALAAECgcIEgAAAA==.',Ne='Nemi:BAAALAADCgcIBwAAAA==.Nerflord:BAAALAAECgYICwAAAA==.Nexeath:BAAALAADCggIEAAAAA==.',No='Nomelk:BAAALAADCgIIAgAAAA==.Nozdormi:BAAALAAECggICAABLAAECggIHAATALAdAA==.',Nz='Nzk:BAABLAAECoEiAAIQAAcIOx89KQBhAgAQAAcIOx89KQBhAgAAAA==.',Op='Opaque:BAAALAADCgQIBAABLAAECgcIKQABAN4hAA==.',Or='Orobas:BAAALAADCggIEgAAAA==.',Os='Osias:BAAALAAECgcICgAAAA==.',Pa='Paci:BAAALAAECgUIBQAAAA==.Paladinpain:BAAALAAECgYIDQAAAA==.Pawter:BAEALAAECggIDgABLAAFFAQICgARAMsWAA==.',Pe='Pesha:BAAALAAECgYIEgAAAA==.',Ph='Ph:BAAALAAECggIFQAAAQ==.Phlare:BAAALAAECgYIBgAAAA==.',Po='Polimeriq:BAABLAAECoEXAAIWAAcImhOGIwCXAQAWAAcImhOGIwCXAQAAAA==.Ponydin:BAAALAAECgcIDwABLAAECggICwACAAAAAQ==.Ponysmash:BAAALAAECgYIBwABLAAECggICwACAAAAAA==.Portalkeeper:BAAALAADCgYIBgAAAA==.',Pr='Prottector:BAAALAADCggICAAAAA==.',Pu='Puss:BAAALAAECgMIAwAAAA==.',Qu='Quarrel:BAAALAAECggIDAAAAA==.',Ra='Raiten:BAAALAAECgYIEAAAAA==.Raveleijn:BAABLAAECoEbAAIPAAgIFhjhRQA6AgAPAAgIFhjhRQA6AgAAAA==.Rawrbaby:BAAALAAECgYIEAAAAA==.',Re='Redlegend:BAAALAADCgUIBQAAAA==.Redsonja:BAAALAADCggICAAAAA==.Rekesalat:BAAALAADCggICAAAAA==.',Ri='Riftwalker:BAAALAAECgYIEwAAAA==.',Ro='Roger:BAABLAAECoEjAAIZAAgIByJoCwD6AgAZAAgIByJoCwD6AgAAAA==.Rosenkrauz:BAAALAAECgYIBwAAAA==.Rosibebe:BAAALAADCggICgABLAAECggIEAACAAAAAA==.',Ru='Rudedude:BAAALAAECgEIAQAAAA==.',Sa='Saintpeter:BAABLAAECoEUAAMdAAgIJCC1DACQAgAdAAcIsh+1DACQAgAPAAEIEhudIwFSAAAAAA==.Saman:BAAALAAECggIDQAAAA==.Samedi:BAAALAADCgYIBgAAAA==.Sandalf:BAABLAAECoEcAAITAAgIsB0jDAC2AgATAAgIsB0jDAC2AgAAAA==.',Se='Seppe:BAAALAAECgMIBgAAAA==.Serlina:BAABLAAECoEZAAIPAAcI1BoLVgANAgAPAAcI1BoLVgANAgAAAA==.Sethario:BAAALAADCgYICQAAAA==.',Sh='Shadowfury:BAAALAADCggIEwAAAA==.Shavora:BAAALAAECgYICQAAAA==.Shinyman:BAABLAAECoEdAAIPAAgIshv4KgCaAgAPAAgIshv4KgCaAgAAAA==.Shrewd:BAAALAAECgEIAgAAAA==.',So='Soban:BAAALAAECgIIAgABLAAECggIGAAZAGUZAA==.',Sp='Spggl:BAAALAADCggIFgAAAA==.',St='Stabster:BAAALAADCgYIBwAAAA==.Stanx:BAAALAADCgYIBgAAAA==.Stéfan:BAAALAADCggIFwAAAA==.Störmcaller:BAAALAADCgcIBwAAAA==.',Su='Suey:BAABLAAECoEaAAIaAAgIDhfmFgBNAgAaAAgIDhfmFgBNAgAAAA==.Summachos:BAAALAAECggICwAAAA==.Suny:BAAALAAECgYIEwAAAA==.Suzannah:BAAALAAECgYICQAAAA==.',Sy='Sylv:BAAALAAECgUICwAAAA==.',Ta='Takeshi:BAAALAAECgQICAAAAA==.Tarkuss:BAAALAADCgMIAwAAAA==.Taros:BAAALAAECgIIAgAAAA==.',Te='Tempest:BAAALAAECggICAAAAQ==.',Th='Thorolf:BAAALAAECgIIAgAAAA==.',Ti='Tienus:BAABLAAECoEnAAIWAAgIkR8xCgClAgAWAAgIkR8xCgClAgAAAA==.',Tr='Triest:BAAALAADCgMIAwAAAA==.',Tu='Tunkashy:BAAALAAECgIIAgAAAA==.Turboligma:BAAALAADCggIDAAAAA==.',Tw='Tworkm:BAAALAAECgQICwABLAAECgYIDwACAAAAAA==.',Ty='Tyshia:BAAALAADCgMIAwAAAA==.',Va='Vali:BAABLAAECoEcAAIIAAgIZh65HwCfAgAIAAgIZh65HwCfAgAAAA==.Vanthir:BAAALAAECgcIEgAAAA==.',Ve='Venrak:BAAALAADCgIIAgAAAA==.Vermax:BAAALAADCgQIBAABLAAECggIKgAeADYhAA==.',Vu='Vulaang:BAAALAAECgYIBgABLAAECggIHAATALAdAQ==.Vulgoku:BAAALAAECggICgABLAAECggIHAATALAdAA==.Vulpie:BAAALAAECgYIBgABLAAECggIHAATALAdAA==.',Wa='Wampy:BAAALAAECgYIEAAAAA==.Warmacca:BAAALAAECgIIAgAAAA==.',Wh='Whelp:BAAALAAECgcIDQAAAA==.Whizzie:BAAALAADCgMIAwAAAA==.',Ya='Yasha:BAAALAAECgYIDAAAAA==.',Ye='Yeshbre:BAAALAAECgMIAwAAAA==.',Yo='Yondaimekun:BAAALAADCgcICAAAAA==.',Yw='Yw:BAAALAADCgYIBgAAAA==.',Za='Zanisia:BAAALAAECgYIEgAAAA==.Zanixis:BAAALAAECgYIBgAAAA==.',Ze='Zeng:BAAALAADCggICgAAAA==.',['Ðo']='Ðora:BAAALAAECggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end