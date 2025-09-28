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
 local lookup = {'DemonHunter-Havoc','Unknown-Unknown','Druid-Feral','Druid-Guardian','Paladin-Holy','Shaman-Restoration','Warlock-Destruction','Rogue-Melee','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','Mage-Frost','DeathKnight-Frost','DeathKnight-Blood','Mage-Arcane','Rogue-Outlaw','Warrior-Fury','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Protection','Paladin-Retribution','Evoker-Devastation','Warrior-Protection','Evoker-Augmentation',}; local provider = {region='EU',realm="Kil'jaeden",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abrakadabrá:BAAALAADCgIIAgAAAA==.',Ac='Act:BAABLAAECoElAAIBAAcIrxjEXADmAQABAAcIrxjEXADmAQAAAA==.Acth:BAAALAAECggIEgAAAA==.',Ae='Aedaira:BAAALAAECgIIAwAAAA==.Aelya:BAAALAAECgYICgAAAA==.',Ai='Aiphatonos:BAAALAAECgcICgAAAA==.',Al='Alanìa:BAAALAAECgYIDgABLAAECggIDgACAAAAAA==.Alf:BAAALAADCggICwAAAA==.Allegro:BAAALAAECggICAAAAA==.',An='Androgeus:BAABLAAECoEiAAMDAAcIuh9iCgCJAgADAAcIuh9iCgCJAgAEAAEIIQ8QLgAtAAAAAA==.Anfaenger:BAAALAAECgYIEgABLAAECgcIFgAFADkYAA==.Ankär:BAABLAAECoEfAAIGAAgIiiMmBQAwAwAGAAgIiiMmBQAwAwAAAA==.Antarus:BAABLAAECoEpAAIHAAgIdxc5NQA5AgAHAAgIdxc5NQA5AgAAAA==.Anubís:BAAALAADCgcIDgAAAA==.Anuri:BAAALAAECgcICQAAAA==.',Ao='Aoì:BAAALAAECgIIAgABLAAFFAQIAQAIAA0TAA==.',Aq='Aqua:BAABLAAECoEkAAIJAAgIvhdnJABBAgAJAAgIvhdnJABBAgAAAA==.',Ar='Archandaria:BAAALAADCgcIBwAAAA==.Aristelle:BAABLAAECoEaAAIKAAcISRGoDgCLAQAKAAcISRGoDgCLAQAAAA==.Arkania:BAAALAAECggIDgAAAA==.Arlik:BAABLAAECoEoAAIEAAgItSOdAQA+AwAEAAgItSOdAQA+AwAAAA==.Armageddon:BAAALAADCgcIBwAAAA==.Arzëth:BAAALAAECgYIBwAAAA==.',As='Asklepia:BAAALAAECgMIAwAAAA==.',At='Atali:BAAALAADCggIEAAAAA==.Atheon:BAAALAAECgQIBwAAAA==.Atroxmonk:BAAALAAECgYIBwABLAAECggIHwABAJkRAA==.',Ay='Ayvi:BAABLAAECoEiAAILAAcIthLtfgCAAQALAAcIthLtfgCAAQAAAA==.',['Aà']='Aàskereia:BAAALAADCgEIAQABLAAECgIIAwACAAAAAA==.',Ba='Baerserker:BAAALAAECgMIAwAAAA==.Baschilla:BAAALAAECgMIAwAAAA==.',Be='Becki:BAAALAAECgcIEwAAAA==.',Bi='Bigpapa:BAAALAADCgcIFAAAAA==.',Bl='Blackjohn:BAAALAADCggICAAAAA==.Blâckbêard:BAABLAAECoEmAAMGAAgI2RJIUwC7AQAGAAgI2RJIUwC7AQAMAAMILgEkqgA6AAAAAA==.',Bo='Bonham:BAAALAAECgQICQAAAA==.',Br='Bright:BAAALAADCggIDwAAAA==.Brônkô:BAAALAAECgYICgABLAAECggIKwAMAOoZAA==.',Bu='Bulltin:BAAALAADCgIIAgAAAA==.',['Bä']='Bängor:BAAALAAECgcICAAAAA==.',Ca='Cadacadea:BAAALAADCggIBQAAAA==.Cadá:BAAALAADCgUIAQAAAA==.Califa:BAAALAAECgQIBQAAAA==.Candy:BAAALAAECgYIDQAAAA==.Cap:BAABLAAECoEhAAMNAAcISRbbGQC8AQANAAcISRbbGQC8AQAOAAEIyw9PWwAuAAABLAAECggIDgACAAAAAA==.',Ce='Celilinda:BAAALAAECgEIAQAAAA==.',Ch='Charra:BAAALAADCggIBwAAAA==.Cheltear:BAAALAADCggIDwAAAA==.Chengying:BAAALAADCgcIBwAAAA==.',Ci='Cinan:BAAALAADCgcICgAAAA==.',Cl='Cláymore:BAAALAADCggICAAAAA==.',Co='Coraíja:BAAALAAFFAIIBAAAAA==.',Cr='Crom:BAAALAADCgUIBgAAAA==.Crota:BAAALAADCgQIBAAAAA==.',Da='Darkeflam:BAABLAAECoEiAAIFAAgIjhdoFABEAgAFAAgIjhdoFABEAgAAAA==.Darriss:BAAALAAECgMIBgAAAA==.',De='Deadshadow:BAAALAAECgYIDQAAAA==.',Do='Donna:BAAALAAECgYIEAAAAA==.',Dr='Drave:BAAALAAECgYIBgABLAAECgcIBwACAAAAAA==.Drunkiechan:BAAALAAECgYICwAAAA==.',Dy='Dysnomia:BAABLAAECoEfAAIPAAcIThphGADQAQAPAAcIThphGADQAQAAAA==.',['Dà']='Dàrà:BAAALAADCgEIAQAAAA==.',El='Eleni:BAAALAADCggIDwAAAA==.',Er='Ernstaugust:BAAALAAECgcIEwAAAA==.',Eu='Eulenbär:BAAALAAECgcICAAAAA==.',Ex='Extrém:BAAALAADCgYIBgAAAA==.',Fe='Felizia:BAAALAAECgYIBgAAAA==.Fernandô:BAAALAADCgcIDgABLAAECggICgACAAAAAA==.',Fi='Fizzle:BAAALAADCggIDAAAAA==.',Fu='Furzzilla:BAAALAAECgYICQAAAA==.',Ga='Gammaray:BAAALAAECgYICgAAAA==.',Ge='Gewitterval:BAAALAADCgcIDgAAAA==.',Gl='Glamien:BAAALAADCgcIBwAAAA==.Glóin:BAABLAAECoEdAAILAAgI9hRVWgDUAQALAAgI9hRVWgDUAQAAAA==.',Go='Gorek:BAAALAADCggICwAAAA==.',['Gô']='Gôdîs:BAAALAADCgUIBQAAAA==.',He='Healzero:BAAALAAECgYICAAAAA==.Heilmich:BAAALAADCgcIBwAAAA==.Hellrazór:BAAALAAECgMIAwAAAA==.Hellsong:BAAALAAECgYICwAAAA==.',Ho='Hoppelkadse:BAAALAADCggICAAAAA==.Horgaar:BAAALAADCggICwAAAA==.',Hu='Hufflepuf:BAABLAAECoEpAAIQAAgI8h+FCgDYAgAQAAgI8h+FCgDYAgAAAA==.Hulkmoor:BAAALAAECggIDQAAAA==.',['Hô']='Hôkûspôkus:BAAALAADCgMIAwAAAA==.',Ig='Igorr:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.',Ii='Iisi:BAAALAAECgMIAwAAAA==.',Il='Ilyana:BAAALAADCggICgAAAA==.',Im='Imperatorin:BAAALAADCgMIAwABLAAECgcIIAAJAL4cAA==.',In='Inflâmes:BAAALAAECggICQAAAA==.',Is='Isabellaa:BAAALAAECggIDwAAAA==.',It='Itari:BAAALAAECgEIAQABLAAECgIIAwACAAAAAA==.',Je='Jee:BAAALAADCggIMwAAAA==.Jendoo:BAAALAAECgYIDwAAAA==.',Ji='Jiika:BAABLAAECoEWAAIFAAcIORgsHAACAgAFAAcIORgsHAACAgAAAA==.',['Jû']='Jûxx:BAAALAADCgQIBAAAAA==.',Ka='Kagrosh:BAAALAADCgcIBwAAAA==.Kaledrial:BAABLAAECoEVAAIRAAcIvgPR9wDsAAARAAcIvgPR9wDsAAAAAA==.Karlach:BAAALAAECgYICQAAAA==.Kaìdo:BAAALAADCggICAAAAA==.Kaýa:BAAALAADCggICAAAAA==.',Ke='Kelridan:BAABLAAECoEhAAISAAgIUh60CQCXAgASAAgIUh60CQCXAgAAAA==.',Ki='Kiarai:BAAALAADCggIFwAAAA==.Kip:BAAALAADCggIFAABLAADCggIFwACAAAAAA==.',Kr='Krampf:BAAALAAECggIAQAAAA==.Krýss:BAAALAAECgUICQABLAAECggIGQAJAKMaAA==.',La='Lanna:BAAALAAECggIEwAAAA==.',Le='Lecia:BAAALAADCgUIBQAAAA==.Lecitania:BAAALAAECggIBwAAAA==.',Li='Lichto:BAAALAADCggICgAAAA==.Ligon:BAAALAAECgEIAQAAAA==.',Lo='Loipy:BAABLAAECoEaAAIMAAcINxuwKQBHAgAMAAcINxuwKQBHAgAAAA==.Los:BAAALAADCgcIBwABLAAFFAMIDgAGAMQZAA==.Lossy:BAACLAAFFIEOAAIGAAMIxBlpDwDnAAAGAAMIxBlpDwDnAAAsAAQKgTQAAwYACAj4IW4PANcCAAYACAj4IW4PANcCAAwABwhjGwYvACkCAAAA.',Lu='Lunario:BAAALAAECgYIBgAAAA==.',Ly='Lyandris:BAABLAAECoEoAAITAAgIgBwFJgCfAgATAAgIgBwFJgCfAgAAAA==.Lyra:BAAALAADCgcIEQAAAA==.',['Lû']='Lûxx:BAABLAAECoEbAAIUAAcIuiFkAwCpAgAUAAcIuiFkAwCpAgAAAA==.',Ma='Maidemonboi:BAAALAAECgMIBQABLAAFFAUIDAAVAIsQAA==.Maiself:BAACLAAFFIEMAAIVAAUIixCqCACmAQAVAAUIixCqCACmAQAsAAQKgTYAAhUACAjzIloSAAADABUACAjzIloSAAADAAAA.Mankarul:BAAALAADCgcIEAAAAA==.Marahi:BAAALAAECgIIAgABLAAECgcIBwACAAAAAA==.Marinchen:BAAALAADCggIKAAAAA==.',Me='Merain:BAAALAAECgIIAgAAAA==.',Mi='Miaupy:BAAALAADCggICAAAAA==.Miazaan:BAABLAAECoEkAAMJAAcIWA4TUwBmAQAJAAcIWA4TUwBmAQAKAAEIiQdxNwAnAAAAAA==.Micaleya:BAABLAAECoEZAAIWAAYINh1wNQDOAQAWAAYINh1wNQDOAQAAAA==.Miisha:BAAALAADCgYIBgABLAAECggIDgACAAAAAA==.Milek:BAABLAAECoEUAAIXAAYInhGRJQB2AQAXAAYInhGRJQB2AQAAAA==.Mili:BAAALAADCggICAAAAA==.Mimmimimimii:BAAALAAECgIIBQAAAA==.Mirato:BAACLAAFFIEGAAMPAAIIGhG0DABuAAABAAIIBg3cNACPAAAPAAIImw+0DABuAAAsAAQKgSMAAgEACAgUH94bANoCAAEACAgUH94bANoCAAAA.Misha:BAAALAADCgcIEAAAAA==.',Mo='Mokuyoubi:BAABLAAECoEtAAMYAAgIrB3fDwBaAgAYAAgIrB3fDwBaAgAZAAYIkguz1wAYAQAAAA==.Monk:BAAALAAFFAIIAgABLAAFFAUIAgACAAAAAA==.Morbol:BAAALAADCgQIBAAAAA==.Moyo:BAAALAAECgMIBAAAAA==.',Mu='Muckmúck:BAABLAAECoEZAAIEAAcIQRTGDgCwAQAEAAcIQRTGDgCwAQABLAAECggIKAAaALQRAA==.Muhnk:BAAALAAECgcIBwAAAA==.',My='Myrte:BAAALAAECggICAAAAA==.',['Mæ']='Mæsticor:BAABLAAECoEgAAMbAAcIFhiJJwDIAQAbAAcI2BeJJwDIAQAVAAUIxRM0hQAwAQAAAA==.',['Mí']='Mía:BAAALAAECgYIDwAAAA==.',['Mî']='Mîsâ:BAAALAAECgUIAwAAAA==.',Na='Nachtara:BAAALAADCgUIBQAAAA==.Nahimana:BAAALAADCgcIBwAAAA==.Nahin:BAABLAAECoEYAAIDAAcINhyhFgDPAQADAAcINhyhFgDPAQAAAA==.',Ne='Nefertiabet:BAAALAAECgYICQAAAA==.',Ni='Nightshade:BAABLAAECoEaAAIWAAgIdCQ/BABHAwAWAAgIdCQ/BABHAwAAAA==.',No='Novak:BAAALAADCggICAAAAA==.',['Nâ']='Nârthasdûm:BAAALAAECgEIAQAAAA==.',['Né']='Nécray:BAAALAAECgMIBQAAAA==.',Ol='Olê:BAAALAADCggICAAAAA==.',On='Onah:BAAALAAECgEIAQAAAA==.',Op='Opia:BAAALAADCggIGAAAAA==.',Or='Oraios:BAAALAADCggICAAAAA==.Orm:BAAALAAECgYICAABLAAECgcIBwACAAAAAA==.Orodrun:BAAALAADCggIFwAAAA==.',Os='Osiriss:BAAALAADCgcIBwABLAAECggIHgAFAJIKAA==.',Ot='Otto:BAAALAAECgcIBwAAAA==.',Pa='Pandirio:BAACLAAFFIEEAAIRAAIIIRSbMQChAAARAAIIIRSbMQChAAAsAAQKgScAAhEACAgDJtkFAF0DABEACAgDJtkFAF0DAAAA.Pauluß:BAAALAAECgcIEgAAAA==.',Pe='Peterzwegyat:BAAALAAECgcIDgAAAA==.Peusie:BAAALAADCggIEQAAAA==.',Ph='Phenya:BAAALAADCgYIBgABLAAECgcICQACAAAAAA==.',Pl='Plazer:BAAALAADCggICQAAAA==.',Ra='Ragoo:BAABLAAECoEgAAILAAcIuB3iSAAEAgALAAcIuB3iSAAEAgAAAA==.Railaa:BAAALAADCggIDwAAAA==.Raschafarie:BAAALAADCggIEAAAAA==.Rawley:BAAALAADCgcIBwAAAA==.',Re='Redpala:BAAALAAECgYIBwAAAA==.Reed:BAAALAAECgcIAwABLAAECggIDgACAAAAAA==.',Ri='Ridcully:BAAALAAECgYIEgAAAA==.',Ro='Robsn:BAABLAAECoElAAIZAAgIdRfiPgBUAgAZAAgIdRfiPgBUAgAAAA==.Ronin:BAAALAADCgIIAgAAAA==.',Ru='Rufi:BAAALAADCgEIAQAAAA==.Rush:BAAALAADCgYIEAAAAA==.',Ry='Rykki:BAAALAADCgYIBgAAAA==.',Sa='Sadry:BAAALAADCgcIBwAAAA==.Sazia:BAAALAAECgYIDwABLAAECgcIFgAFADkYAA==.Sazpal:BAAALAAECgIIAgAAAA==.',Sc='Schneeschatz:BAAALAAECgMIBAAAAA==.Schorliele:BAAALAADCggIIgAAAA==.',Se='Seecrow:BAABLAAECoEnAAINAAgIHBv1CwCBAgANAAgIHBv1CwCBAgABLAAECgcIFgAFADkYAA==.',Sh='Shadî:BAAALAAECgEIAQAAAA==.Shammy:BAAALAADCgUIBQAAAA==.Shaymin:BAABLAAECoEfAAIMAAgI2RqOHACbAgAMAAgI2RqOHACbAgAAAA==.Shredd:BAAALAAECgIIAgAAAA==.Shándro:BAAALAAECgQIBwAAAA==.Shíla:BAABLAAECoEoAAMaAAgItBGeJgDHAQAaAAgIvgyeJgDHAQAcAAcItxDKCQCbAQAAAA==.Shínko:BAAALAADCggICAABLAAECggIKAAaALQRAA==.',Si='Sichelweib:BAAALAAECgMIAwAAAA==.',Sk='Skangra:BAABLAAECoEpAAIMAAgIrhlwIwBsAgAMAAgIrhlwIwBsAgAAAA==.Skizzler:BAAALAAECgIIAgAAAA==.',Sn='Sneat:BAAALAAECgcIBwAAAA==.',St='Steckmann:BAAALAAECgIIAgAAAA==.',Sy='Syna:BAAALAAECgcICQAAAA==.',['Sè']='Sèlie:BAAALAADCggIDAAAAA==.',['Sê']='Sêlka:BAAALAAECgMIAwAAAA==.',['Sî']='Sîvéry:BAAALAAECgIIAgAAAA==.',Ta='Taolun:BAAALAAECggICgAAAA==.Tara:BAAALAAECgQIBQAAAA==.Tarvek:BAAALAAECgYIBgAAAA==.',Te='Tejá:BAAALAAECgYIBQAAAA==.',Th='Thanatôs:BAABLAAECoEZAAIJAAgIoxrSIQBQAgAJAAgIoxrSIQBQAgAAAA==.Thandolin:BAAALAADCgMIAwAAAA==.',Ti='Tina:BAAALAADCgEIAQABLAAECgcIIgAaAPEbAA==.Tinerala:BAAALAADCgYIBgAAAA==.',To='Totemiker:BAAALAADCgYIBgAAAA==.',['Tä']='Tänkgirl:BAAALAADCggIEAAAAA==.',['Tó']='Tómmy:BAAALAAECggIDgAAAA==.',['Tô']='Tôbî:BAAALAAECgYIDAAAAA==.',Ud='Udarist:BAAALAAECgUIBwAAAA==.',Ve='Velanìa:BAAALAAECgYIBgABLAAECggIDgACAAAAAA==.Velly:BAAALAAECgEIAQAAAA==.Veromoth:BAAALAADCggIGwAAAA==.',Vo='Voìd:BAAALAADCggIBQAAAA==.',['Vè']='Vègètà:BAABLAAECoEXAAIBAAgI5gt4kQB2AQABAAgI5gt4kQB2AQAAAA==.',We='Weissi:BAAALAAECgYIDAABLAAECgcIFgAFADkYAA==.Wendigo:BAAALAADCgMIAwAAAA==.',Wo='Wolfhunter:BAAALAAECgEIAQAAAA==.Woop:BAAALAADCgcIEQAAAA==.',['Wâ']='Wârt:BAABLAAECoEfAAIMAAcIQCFQHQCVAgAMAAcIQCFQHQCVAgAAAA==.',Ya='Yamatô:BAABLAAECoEiAAIaAAcI8RsaGwAtAgAaAAcI8RsaGwAtAgAAAA==.Yannik:BAAALAAECggIEgAAAA==.',Yl='Ylida:BAAALAADCgcIGgAAAA==.',Yu='Yugoschmugo:BAABLAAECoEpAAIWAAgIpBwgFwCXAgAWAAgIpBwgFwCXAgAAAA==.Yukìi:BAAALAADCgcIDAAAAA==.',['Yû']='Yûna:BAAALAADCgcICAAAAA==.',Zh='Zhalia:BAAALAAECgEIAQAAAA==.',Zu='Zues:BAAALAAECgcIFAAAAQ==.Zufall:BAAALAADCggILwAAAA==.Zuthugaurk:BAABLAAECoEeAAILAAcIZRMLcgCbAQALAAcIZRMLcgCbAQAAAA==.',Zy='Zyklo:BAAALAADCggIHAAAAA==.',['Át']='Átrox:BAABLAAECoEfAAMBAAgImRGFZgDOAQABAAgIaBGFZgDOAQAPAAEIGR0vTwBUAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end