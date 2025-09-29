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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Priest-Holy','Paladin-Retribution','DemonHunter-Vengeance','DemonHunter-Havoc','Rogue-Subtlety','Warlock-Destruction','Monk-Mistweaver','Hunter-BeastMastery','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Monk-Brewmaster','Monk-Windwalker','Mage-Arcane','Warrior-Protection','Warrior-Fury','Paladin-Holy','Hunter-Marksmanship','Shaman-Elemental','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','DeathKnight-Unholy','Hunter-Survival','Rogue-Assassination','Shaman-Restoration','Shaman-Enhancement','DeathKnight-Blood',}; local provider = {region='EU',realm="Lightning'sBlade",name='EU',type='weekly',zone=44,date='2025-09-22',data={Ad='Adelyna:BAAALAADCgUIBQAAAA==.Adramahlihk:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Ae='Aethelea:BAAALAADCgcIEQAAAA==.',Ag='Agulka:BAAALAADCggIDAAAAA==.',Al='Alltingpå:BAAALAAECgIIAgAAAA==.Alluka:BAAALAAECggIDgAAAA==.Aloneye:BAAALAADCgcIBwAAAA==.Alsu:BAACLAAFFIEGAAMCAAIINQIOHwBgAAACAAIINQIOHwBgAAADAAEIXwAeNQAtAAAsAAQKgRUAAgIACAj1Cw87AKwBAAIACAj1Cw87AKwBAAAA.Alvrina:BAAALAADCgEIAQAAAA==.',An='Anduin:BAABLAAFFIEFAAIEAAIICw/YLACcAAAEAAIICw/YLACcAAAAAA==.',Ar='Archaiix:BAAALAAECgUIBQAAAA==.Armenbobo:BAAALAAECggIEwAAAA==.Artemis:BAAALAAECgYICwAAAA==.Aryce:BAAALAAECgcIEwAAAA==.',As='Ashbringer:BAAALAAECgMIAQAAAA==.Astaeer:BAACLAAFFIELAAICAAQI/h/tBgCHAQACAAQI/h/tBgCHAQAsAAQKgSYAAgIACAiuJf0CAGcDAAIACAiuJf0CAGcDAAAA.Asuramaru:BAAALAAECggIEAAAAA==.',Ay='Aysegul:BAAALAADCgYIBwAAAA==.',Ba='Baconmannén:BAAALAADCggICAAAAA==.Barank:BAAALAADCgcIEQAAAA==.Barx:BAAALAAECggICAAAAA==.',Bb='Bbkaya:BAAALAADCggIEAAAAA==.',Bi='Bideven:BAABLAAECoEZAAMFAAgILBxNDABmAgAFAAgILBxNDABmAgAGAAII4wGGBQFMAAAAAA==.Bigbone:BAAALAADCggIDwAAAA==.',Bo='Bounias:BAAALAAECggIEgABLAAECggIGgAHAE4gAA==.',Br='Brynni:BAAALAADCggIGAAAAA==.',Bu='Bullxit:BAABLAAECoEdAAIEAAgIhiKMFAALAwAEAAgIhiKMFAALAwAAAA==.Bussdownap:BAABLAAECoEnAAIIAAgInRtQJACJAgAIAAgInRtQJACJAgAAAA==.',By='Byram:BAAALAAECgMIAwABLAAECgcIEgABAAAAAA==.',Ce='Cendre:BAAALAAECggIDgAAAA==.',Ch='Checkmate:BAAALAADCgcIBwAAAA==.Chlochlo:BAAALAADCggICwAAAA==.',Ci='Cinnamoon:BAAALAADCggIDQAAAA==.Cioranes:BAAALAAECgUIBgAAAA==.',Co='Complishady:BAAALAAECggICAAAAA==.',Cr='Cresento:BAAALAADCgEIAQAAAA==.',Da='Damien:BAAALAAECgMIBgAAAA==.Darkichien:BAAALAAECggIEAAAAA==.Datfatjr:BAACLAAFFIEGAAIDAAIIYiOUEgDSAAADAAIIYiOUEgDSAAAsAAQKgSUAAgMACAjHHgQSALsCAAMACAjHHgQSALsCAAAA.',De='Deerhunter:BAAALAAECgYICwAAAA==.Dendo:BAAALAADCggIIgABLAAECgYIFwAJAKsXAA==.Despana:BAAALAADCggICAAAAA==.Deyja:BAAALAADCggICAAAAA==.',Di='Disti:BAAALAAECgcIEgAAAA==.',Dj='Djrazy:BAAALAAECggICAAAAA==.',Dr='Drakani:BAAALAADCggICAABLAAECggIFQAKAIcYAA==.Drdrood:BAABLAAECoEaAAMLAAgI5RU7KAD3AQALAAgI5RU7KAD3AQAMAAcIjBC7UQBaAQAAAA==.Druidex:BAAALAADCgYIBgAAAA==.',El='Elethrion:BAABLAAECoEeAAINAAgIUBoMRgA/AgANAAgIUBoMRgA/AgAAAA==.Elieda:BAAALAADCgYICgAAAA==.',En='Ennoris:BAAALAAECgcICwAAAA==.Enrienna:BAAALAAECgcIEQAAAA==.',Et='Eterni:BAABLAAECoEdAAMLAAYI9h7bLQDXAQALAAYI9h7bLQDXAQAMAAYI4xKpUwBTAQAAAA==.',Fa='Facepaint:BAAALAADCggICAAAAA==.Fatfingers:BAAALAAECgQIBgABLAAECgYIBwABAAAAAA==.Fattony:BAAALAAECgYIBgAAAA==.',Fe='Felinfoel:BAABLAAECoEeAAMOAAgIGhRnFwC8AQAOAAcIEhVnFwC8AQAPAAEIUA2AVAA+AAAAAA==.Fenriz:BAABLAAECoEaAAIQAAgIlyB8FgDrAgAQAAgIlyB8FgDrAgAAAA==.',Fl='Florentino:BAAALAADCgYIBQABLAAECggICAABAAAAAA==.Florinel:BAABLAAECoEsAAMRAAgIMxsAEwBrAgARAAgIMxsAEwBrAgASAAEIlgeGyQA1AAAAAA==.',Ge='Geraltrivia:BAAALAADCgcIDgAAAA==.',Gi='Giaour:BAAALAAECgYIBgABLAAECggIHQAEAIYiAA==.',Gl='Glockgechar:BAAALAAFFAIIAwAAAA==.Gloxinia:BAAALAAECgYIBwAAAA==.',Go='Gondy:BAAALAADCggIEAAAAA==.Goodevil:BAAALAAECggIDgAAAA==.',Gr='Graveling:BAAALAAECggIEwAAAA==.Grezvi:BAAALAADCggIEQAAAA==.Groxigar:BAAALAAECgUICQAAAA==.',Gw='Gwendir:BAABLAAECoEbAAIEAAgIrhjKPABVAgAEAAgIrhjKPABVAgAAAA==.',Ha='Hadys:BAAALAADCgMIAwAAAA==.Hayleigh:BAAALAADCgcIDwAAAA==.',Hi='Hi:BAAALAAECgIIAgAAAA==.',Ho='Holybuns:BAAALAADCggIDwAAAA==.Holylion:BAAALAADCggIEgAAAA==.Holysam:BAACLAAFFIEHAAMTAAMIABeADQC2AAATAAII/huADQC2AAAEAAMITREsJAClAAAsAAQKgSoAAwQACAiZI3wSABYDAAQACAiZI3wSABYDABMACAhkH9QGAOACAAAA.Hopé:BAAALAAECgMICAAAAA==.Horhuset:BAAALAAECggIDQAAAA==.Horsus:BAABLAAECoEfAAIMAAgIqSBACwDhAgAMAAgIqSBACwDhAgAAAA==.',Hu='Hugebeard:BAAALAAECgcICwAAAA==.Hughmungus:BAAALAAECgIIAgAAAA==.Humanmage:BAAALAADCgIIAgAAAA==.Hunterkilla:BAABLAAECoEjAAIUAAgIiyDqDQDlAgAUAAgIiyDqDQDlAgAAAA==.Huuga:BAAALAAECgcIDQAAAA==.',Ib='Ibrahealovic:BAAALAAECgcIEgAAAA==.',Il='Ilogorn:BAAALAAFFAIIAgAAAA==.',In='Ink:BAAALAADCgYIBgAAAQ==.',Ir='Irau:BAAALAADCgcIBwAAAA==.',Ja='Janus:BAAALAADCggICAAAAA==.',Ju='Junju:BAAALAAECgUIBQAAAA==.Junus:BAAALAADCggICAAAAA==.Justdemon:BAAALAADCgUIBQAAAA==.',Ka='Kanti:BAABLAAECoEiAAIVAAgI0BHDNQAAAgAVAAgI0BHDNQAAAgAAAA==.Karaxiah:BAACLAAFFIEGAAIFAAIIYw/MCwBuAAAFAAIIYw/MCwBuAAAsAAQKgSsAAgUACAgPG/cSAAcCAAUACAgPG/cSAAcCAAAA.',Ke='Kelli:BAAALAADCggIDAAAAA==.Kendrath:BAAALAAECgYIBgABLAAECgcICwABAAAAAA==.',Ki='Kindroth:BAABLAAECoEZAAMUAAgIwRBCRACGAQAUAAgI0Q1CRACGAQAKAAQISw+cxADYAAAAAA==.',Kr='Krallman:BAAALAAECgYIBgAAAA==.Kree:BAAALAADCggIEwAAAA==.',Ky='Kyusungx:BAAALAAECgYICwAAAA==.',La='Langilock:BAABLAAECoEfAAMIAAgIaRchNgAtAgAIAAgIaRchNgAtAgAWAAEISQAxjwALAAAAAA==.Layrjr:BAAALAAECgcICwAAAA==.',Le='Lethalp:BAACLAAFFIEHAAITAAMIIiAuBwAdAQATAAMIIiAuBwAdAQAsAAQKgRoAAhMACAh7IPoHAM4CABMACAh7IPoHAM4CAAAA.Leviathán:BAAALAADCggIHgAAAA==.',Li='Lilíth:BAAALAAECggICAAAAA==.Linadra:BAAALAAECgIIAgAAAA==.Lisana:BAAALAADCggICAAAAA==.Littlemäfk:BAACLAAFFIEJAAISAAMIIRz7CwAfAQASAAMIIRz7CwAfAQAsAAQKgSgAAhIACAjHJFcGAFYDABIACAjHJFcGAFYDAAAA.Littosayshi:BAABLAAECoEWAAIUAAYIuCETIABKAgAUAAYIuCETIABKAgAAAA==.Lizanardo:BAACLAAFFIEJAAIXAAMIUBTlCgDtAAAXAAMIUBTlCgDtAAAsAAQKgSQAAhcACAjhI+YEADUDABcACAjhI+YEADUDAAAA.',Lo='Loafalkman:BAAALAAECgIIBAAAAA==.',Lu='Lustkukka:BAAALAAECgMIAwAAAA==.Lutkilligal:BAABLAAECoElAAIGAAgIJR2ZJwCXAgAGAAgIJR2ZJwCXAgAAAA==.Lutkukka:BAAALAADCggICAAAAA==.',Ly='Lyana:BAACLAAFFIEGAAIGAAIIQx44HgCpAAAGAAIIQx44HgCpAAAsAAQKgSkAAgYACAjLIokPAB4DAAYACAjLIokPAB4DAAAA.',Ma='Mahgra:BAAALAADCggICAAAAA==.Mandiant:BAAALAADCggIEAAAAA==.Mangodjeri:BAAALAADCgUIBgAAAA==.Maryhadapet:BAABLAAECoEbAAIKAAcI5g+QdwCDAQAKAAcI5g+QdwCDAQAAAA==.',Me='Meatbeat:BAAALAADCgYIBgAAAA==.Megalock:BAABLAAECoEYAAMIAAgIJB04KABzAgAIAAgIlBw4KABzAgAYAAUI+heJEwBiAQAAAA==.Meneerdewit:BAAALAAECgcICgAAAA==.Mesalie:BAAALAADCggIGAAAAA==.',Mi='Miguel:BAAALAAECgcIDgAAAA==.Mirra:BAAALAAECgcIDgAAAA==.',Mo='Monstrul:BAAALAADCgEIAQAAAA==.Mooncat:BAAALAAECgYICAAAAA==.Morganlefey:BAAALAAECggIEAAAAA==.',Mu='Murgundon:BAABLAAFFIEIAAIZAAIIoQl1DwCUAAAZAAIIoQl1DwCUAAAAAA==.',Na='Nakhi:BAAALAAECgQICgAAAA==.Namaste:BAAALAADCggICAAAAA==.Nasev:BAAALAAECgEIAQAAAA==.Nazgul:BAAALAADCggICgABLAAECggIGgAHAE4gAA==.',Ne='Necrolust:BAACLAAFFIEQAAQIAAUIlBQnCwCtAQAIAAUIlBQnCwCtAQAWAAEIfg/zIABPAAAYAAEIpgkyBgBFAAAsAAQKgTIABAgACAhDJAkMACgDAAgACAjBIwkMACgDABgABwihF0AHADgCABYABQgrHzUoALIBAAAA.Nelislock:BAAALAAECgcIDQAAAA==.',Ni='Nibbit:BAAALAADCggIFwAAAA==.Nikwana:BAAALAADCgMIAwAAAA==.',No='Notorium:BAAALAADCggICAAAAA==.',Ny='Nyaleth:BAAALAAECgUIDQABLAAFFAMIBgAWAF0OAA==.Nyunii:BAABLAAECoEVAAIDAAcI4A/hTAB4AQADAAcI4A/hTAB4AQAAAA==.',Om='Omléttin:BAAALAADCgEIAQAAAA==.',On='Onearrow:BAAALAADCgcICAAAAA==.',Oo='Oo:BAABLAAECoEZAAMaAAYIOCNtBQBZAgAaAAYIkyJtBQBZAgAKAAYIOh2CQgANAgAAAA==.',Or='Orkimedes:BAAALAAECgcIEAAAAA==.',Ot='Ottermage:BAAALAAECgMIBQAAAA==.',Ov='Overclockêd:BAABLAAECoEbAAINAAcInxs+UgAeAgANAAcInxs+UgAeAgAAAA==.',Ox='Oxdeath:BAAALAAECgQIBQAAAA==.',Pa='Paddington:BAAALAAECgUIBgAAAA==.Paggån:BAABLAAECoEnAAIJAAgIFRmQDQBgAgAJAAgIFRmQDQBgAgAAAA==.Palaizeny:BAAALAAECgYIGQAAAQ==.Papipinto:BAABLAAFFIEHAAISAAIIrxpTFgC1AAASAAIIrxpTFgC1AAAAAA==.Pasaricapk:BAAALAAECgIIAgAAAA==.',Pe='Pedrao:BAAALAADCggICAAAAA==.Pepperonikka:BAAALAADCgYIBgAAAA==.',Pi='Pionaur:BAAALAAECggIBgAAAA==.Pisione:BAAALAAECgYIBgAAAA==.',Po='Popcdnoskill:BAAALAAECgYICgAAAA==.',Pu='Purenergy:BAABLAAECoEZAAIbAAgIzh6cCwDIAgAbAAgIzh6cCwDIAgAAAA==.',Ra='Raflnatorr:BAAALAAECgcIBwAAAA==.Raikiri:BAABLAAECoEfAAIVAAgI5hJhMgAQAgAVAAgI5hJhMgAQAgAAAA==.Rakanath:BAAALAAECggIAgAAAA==.',Re='Redrage:BAAALAAECgQIBgAAAA==.Rejuvenator:BAAALAAECgYIDAAAAA==.Rellen:BAAALAADCggIBwAAAA==.Resana:BAAALAAECgYICAAAAA==.',Rh='Rhuarc:BAABLAAECoEVAAIKAAgIhxguPwAYAgAKAAgIhxguPwAYAgAAAA==.',Ri='Richmon:BAAALAADCggIFAAAAA==.Rigormortis:BAABLAAECoEYAAIQAAcI4SEnIwCnAgAQAAcI4SEnIwCnAgAAAA==.',Ro='Roseheart:BAAALAADCggICQAAAA==.Roxy:BAAALAAECgEIAgAAAA==.',Sa='Sabrïna:BAAALAAECggICAAAAA==.Samblinks:BAAALAAECgYIBgAAAA==.Samlock:BAAALAAECgYIDgAAAA==.Sandern:BAAALAAECgYICAAAAA==.Saradomir:BAAALAAECgcIEwAAAA==.Saraphina:BAAALAADCggIEwABLAAECggIFgADAHojAA==.Sash:BAAALAADCggICAAAAA==.',Sc='Scheebo:BAAALAADCggIHQAAAA==.',Se='Sekushi:BAAALAAECgcIEgAAAA==.Seven:BAAALAADCgIIAgAAAA==.',Sh='Shakegirl:BAAALAAECgcIBwAAAA==.Shakira:BAAALAADCgUIBQAAAA==.Shamaizeno:BAAALAAECgYIBgABLAAECgYIGQABAAAAAA==.Shampli:BAAALAAECggIEQAAAA==.Shattered:BAAALAAECgYIBgABLAAFFAUIEAAIAJQUAA==.Shimei:BAABLAAECoEcAAMcAAcI6B6iJgBOAgAcAAcI6B6iJgBOAgAdAAcIrBPUDQDfAQAAAA==.',Si='Sihiran:BAABLAAECoEfAAIDAAgI4h9LDgDdAgADAAgI4h9LDgDdAgAAAA==.',Sj='Sjarlan:BAAALAADCggIFQAAAA==.',Sk='Skatt:BAABLAAECoEeAAIPAAgIYBVtGgD+AQAPAAgIYBVtGgD+AQAAAA==.Skp:BAAALAAECgMIAwAAAA==.',Sl='Slapymage:BAAALAAECgQIBAAAAA==.Slasher:BAACLAAFFIEJAAICAAMIRiDTDgDVAAACAAMIRiDTDgDVAAAsAAQKgSgAAgIACAjDJXUBAIADAAIACAjDJXUBAIADAAAA.Slugesh:BAAALAAECgMIAwAAAA==.',Sm='Smokewheat:BAAALAAECgYIBwAAAA==.',Sn='Snugg:BAAALAAECggIBgAAAA==.',So='Soulpone:BAAALAAFFAcIAgAAAA==.Sousmatras:BAAALAADCgcIDgAAAA==.',Sv='Svenne:BAABLAAECoEYAAICAAYI1h4VJwAcAgACAAYI1h4VJwAcAgAAAA==.',Ta='Tangobreath:BAABLAAECoEVAAIXAAgIERxTEgCDAgAXAAgIERxTEgCDAgAAAA==.Taxapingu:BAAALAAECggIEwAAAA==.',Th='Thalassian:BAAALAADCggICAAAAA==.Thendbringer:BAAALAAECgYICwAAAA==.',Ti='Tia:BAAALAADCgcIDAAAAA==.',Tj='Tjin:BAAALAADCggIEQAAAA==.',To='Toxicdagger:BAABLAAECoEaAAMHAAgITiApBQDmAgAHAAgITiApBQDmAgAbAAMIyRjETADRAAAAAA==.',Tr='Tripleshoot:BAABLAAECoEWAAIKAAgI6R2BJwB3AgAKAAgI6R2BJwB3AgAAAA==.Trivia:BAAALAAECgYIEQAAAA==.',Tw='Twiztidmind:BAABLAAECoEWAAIIAAcIhgwmYwCLAQAIAAcIhgwmYwCLAQAAAA==.',Ul='Ulfire:BAAALAADCgcICQAAAA==.',Un='Uncorrupted:BAAALAADCgUIBQAAAA==.Unholyboomer:BAAALAAECggIDAAAAA==.',Ur='Urukhai:BAABLAAECoEXAAINAAgIsx6MNgBwAgANAAgIsx6MNgBwAgABLAAECggIGgAHAE4gAA==.',Us='Ushuru:BAAALAADCggICAABLAAECgcIGwANAJ8bAA==.',Va='Valerya:BAAALAADCgYIBgAAAA==.Valkyriel:BAAALAADCgcIBgAAAA==.Vamper:BAAALAAECggICgABLAAECggIHgANAFAaAA==.',Ve='Veganhandler:BAAALAADCggIFQAAAA==.Vestaperrion:BAAALAADCgYIAQAAAA==.',Vi='Viidakko:BAAALAAECggIDgABLAAECggIIQAEAN4iAA==.Viilisdruid:BAAALAAECgcIBwABLAAECggIIQAEAN4iAA==.Viilispala:BAABLAAECoEhAAIEAAgI3iJzGwDmAgAEAAgI3iJzGwDmAgAAAA==.Vippy:BAAALAADCgQIBAAAAA==.',Vu='Vugdush:BAAALAAECgYIBgAAAA==.',Wh='Whipmaballs:BAAALAADCggIDwABLAAECggICAABAAAAAA==.',Wi='Winter:BAAALAAECgMIBwABLAAECgYICgABAAAAAA==.Wishblades:BAAALAADCggIDwAAAA==.Wishdom:BAAALAAECgYIBgAAAA==.',Wo='Worgenixa:BAAALAAECgYIBgAAAA==.',Wy='Wynand:BAACLAAFFIEIAAIeAAIIdwp2DAB1AAAeAAIIdwp2DAB1AAAsAAQKgRoAAw0ABwiXDx6zAGEBAA0ABwhbDR6zAGEBAB4ABgj2DVkjABkBAAAA.Wyuu:BAAALAAECgYICQAAAA==.',Xa='Xarl:BAAALAAECgEIAQAAAA==.',Xr='Xrap:BAABLAAECoEXAAMHAAcI9iE5DwAWAgAHAAYIWCA5DwAWAgAbAAUI+RwVMACVAQABLAAECggICAABAAAAAA==.',Ya='Yalexa:BAAALAAECgMIBAAAAA==.',Yv='Yvy:BAAALAADCgcIDQAAAA==.',Ze='Zenbeard:BAABLAAECoEcAAMPAAcIAAzHOQAKAQAPAAYICQjHOQAKAQAJAAYI5gr1LAD8AAAAAA==.Zephirothgr:BAAALAADCgcIBwAAAA==.',Zh='Zhraxx:BAAALAAECgYIBgAAAA==.Zhroxx:BAAALAADCgQIAQAAAA==.Zhruxx:BAAALAAECgcIDQAAAA==.',Zi='Zizou:BAABLAAECoEYAAIQAAgIpB05LwBsAgAQAAgIpB05LwBsAgAAAA==.',Zl='Zlein:BAABLAAECoEiAAQWAAgI2yXiDQB4AgAWAAYIoSTiDQB4AgAYAAUIlCG2CgDuAQAIAAEIkiKQwQBlAAABLAAECgcIGAAQAOEhAA==.',['Æt']='Æther:BAAALAAECgUIAwAAAA==.',['Ëm']='Ëms:BAAALAAECgUICwAAAA==.',['Ðr']='Ðrake:BAAALAAECggICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end