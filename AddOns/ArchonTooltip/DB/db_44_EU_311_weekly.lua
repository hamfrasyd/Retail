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
 local lookup = {'Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Paladin-Retribution','Warlock-Destruction','Priest-Holy','Druid-Balance','Druid-Restoration','DeathKnight-Frost','Monk-Brewmaster','Warrior-Protection','Warrior-Fury','Paladin-Holy','Shaman-Elemental','Warlock-Demonology','Evoker-Devastation','Warlock-Affliction','DeathKnight-Unholy','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Rogue-Assassination','Mage-Arcane',}; local provider = {region='EU',realm="Lightning'sBlade",name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adelyna:BAAALAADCgUIBQAAAA==.Adramahlihk:BAAALAADCggICAAAAA==.',Ae='Aethelea:BAAALAADCgcIDAAAAA==.',Ag='Agulka:BAAALAADCgQIBAAAAA==.',Al='Alltingpå:BAAALAAECgIIAgAAAA==.Aloneye:BAAALAADCgcIBwAAAA==.Alsu:BAAALAAECggICgAAAA==.Alvrina:BAAALAADCgEIAQAAAA==.',An='Anduin:BAAALAADCggIEQAAAA==.',Ar='Armenbobo:BAAALAAECggICAAAAA==.Aryce:BAAALAAECgYICwAAAA==.',As='Astaeer:BAABLAAECoEaAAIBAAgIJCVJAgBfAwABAAgIJCVJAgBfAwAAAA==.',Au='Auryon:BAAALAADCggICAAAAA==.',Ba='Baconmannén:BAAALAADCggICAAAAA==.Barank:BAAALAADCgcIEQAAAA==.',Bb='Bbkaya:BAAALAADCgUIBQAAAA==.',Bi='Bideven:BAABLAAECoEUAAMCAAgIvBrABwBcAgACAAgIvBrABwBcAgADAAII4wHkpgBQAAAAAA==.Bigbone:BAAALAADCggIDwAAAA==.',Bo='Bounias:BAAALAAECgIIAgABLAAECggIEQAEAAAAAA==.',Br='Brynni:BAAALAADCggIEAAAAA==.',Bu='Bullxit:BAABLAAECoEXAAIFAAcI9yIaEwDLAgAFAAcI9yIaEwDLAgAAAA==.Bussdownap:BAABLAAECoEXAAIGAAgIRxciGwBVAgAGAAgIRxciGwBVAgAAAA==.',By='Byram:BAAALAAECgIIAgABLAAECgYICQAEAAAAAA==.',Ce='Cendre:BAAALAAECggICAAAAA==.',Ch='Checkmate:BAAALAADCgcIBwAAAA==.Chlochlo:BAAALAADCggICwAAAA==.',Ci='Cioranes:BAAALAAECgUIBgAAAA==.',Cr='Cresento:BAAALAADCgEIAQAAAA==.',Da='Damien:BAAALAAECgMIBgAAAA==.Darkichien:BAAALAAECggIDgAAAA==.Datfatjr:BAABLAAECoEVAAIHAAgI/xnZEwBgAgAHAAgI/xnZEwBgAgAAAA==.Dawne:BAAALAAECgIIAgAAAA==.',De='Deerhunter:BAAALAAECgYIBgAAAA==.Dendo:BAAALAADCggIHAAAAA==.Despana:BAAALAADCggICAAAAA==.Deyja:BAAALAADCggICAAAAA==.',Di='Disti:BAAALAAECgcIBwAAAA==.',Dr='Drdrood:BAABLAAECoEXAAMIAAcIVBZOGwD+AQAIAAcIVBZOGwD+AQAJAAcIjBC5MABsAQAAAA==.Druidex:BAAALAADCgYIBgAAAA==.',El='Elethrion:BAABLAAECoEUAAIKAAgIExqxKgAwAgAKAAgIExqxKgAwAgAAAA==.Elieda:BAAALAADCgYIBgAAAA==.',En='Ennoris:BAAALAADCggIDwAAAA==.',Et='Eterni:BAAALAAECgYIEQAAAA==.',Fa='Facepaint:BAAALAADCggICAAAAA==.Fattony:BAAALAADCggICAAAAA==.',Fe='Felinfoel:BAABLAAECoEVAAILAAcIjxObEQCcAQALAAcIjxObEQCcAQAAAA==.Fenriz:BAAALAAECgcIDQAAAA==.',Fl='Florinel:BAABLAAECoEfAAMMAAgIdxjEGQCaAQAMAAgIdxjEGQCaAQANAAEIlgepbwA4AAAAAA==.',Ge='Geraltrivia:BAAALAADCgcIDgAAAA==.',Gi='Giaour:BAAALAADCggICAABLAAECgcIFwAFAPciAA==.',Gl='Glockgechar:BAAALAAECgYIBAAAAA==.Gloxinia:BAAALAAECgYICAAAAA==.',Go='Gondy:BAAALAADCggIEAAAAA==.Goodevil:BAAALAADCggICQAAAA==.',Gr='Graveling:BAAALAAECgcIEgAAAA==.Groxigar:BAAALAAECgUICQAAAA==.',Gw='Gwendir:BAAALAAECgcIDQAAAA==.',Ha='Hayleigh:BAAALAADCgcIDwAAAA==.',Ho='Holybuns:BAAALAADCggIDwAAAA==.Holylion:BAAALAADCgcIDAAAAA==.Holysam:BAABLAAECoEaAAMFAAgIfCBpDAAIAwAFAAgIfCBpDAAIAwAOAAEIeRTnQQBEAAAAAA==.Hopé:BAAALAAECgEIAQAAAA==.Horhuset:BAAALAAECggIBwAAAA==.Horsus:BAABLAAECoEXAAIJAAcItiAzCwCOAgAJAAcItiAzCwCOAgAAAA==.',Hu='Hughmungus:BAAALAAECgIIAgAAAA==.Humanmage:BAAALAADCgIIAgAAAA==.Hunterkilla:BAAALAAECggIEwAAAA==.',Ib='Ibrahealovic:BAAALAAECgcIEgAAAA==.',Il='Ilogorn:BAAALAAECgcIEAAAAA==.',In='Ink:BAAALAADCgYIBgAAAQ==.',Ir='Irau:BAAALAADCgcIBwAAAA==.',Ja='Janus:BAAALAADCggICAAAAA==.',Ju='Junju:BAAALAADCggIDgAAAA==.Junus:BAAALAADCggICAAAAA==.Justdemon:BAAALAADCgUIBQAAAA==.',Ka='Kanti:BAABLAAECoEWAAIPAAcIVBLaJwDcAQAPAAcIVBLaJwDcAQAAAA==.Karaxiah:BAABLAAECoEbAAICAAgIDxuMCQAxAgACAAgIDxuMCQAxAgAAAA==.',Ke='Kelli:BAAALAADCggIDAAAAA==.',Ki='Kindroth:BAAALAAECggIDwAAAA==.',Kr='Kree:BAAALAADCggIEwAAAA==.',Ky='Kyusungx:BAAALAAECgYICwAAAA==.',La='Langilock:BAABLAAECoEXAAMGAAcI6xUdKwDjAQAGAAcI6xUdKwDjAQAQAAEISQB5bgALAAAAAA==.',Le='Lethalp:BAAALAAFFAEIAQAAAA==.Leviathán:BAAALAADCggIHgAAAA==.',Li='Lilíth:BAAALAAECggICAAAAA==.Lisana:BAAALAADCggICAAAAA==.Littlemäfk:BAABLAAECoEaAAINAAgINR+pDADeAgANAAgINR+pDADeAgAAAA==.Littosayshi:BAAALAAECgYICgAAAA==.Lizanardo:BAABLAAECoEcAAIRAAgIPSGABQAKAwARAAgIPSGABQAKAwAAAA==.',Lo='Loafalkman:BAAALAADCgQIAwAAAA==.',Lu='Lustkukka:BAAALAAECgMIAwAAAA==.Lutkilligal:BAABLAAECoEVAAIDAAcICRsnKQAqAgADAAcICRsnKQAqAgAAAA==.Lutkukka:BAAALAADCggICAAAAA==.',Ly='Lyana:BAABLAAECoEcAAIDAAgIASJKCQAjAwADAAgIASJKCQAjAwAAAA==.',Ma='Mahgra:BAAALAADCggICAAAAA==.Mangodjeri:BAAALAADCgUIBQAAAA==.Maryhadapet:BAAALAAECgYIDgAAAA==.',Me='Meatbeat:BAAALAADCgYIBgAAAA==.Megalock:BAABLAAECoEYAAMGAAgIJB24EgCgAgAGAAgIlBy4EgCgAgASAAUI+he4DgB5AQAAAA==.Meneerdewit:BAAALAAECgYICQAAAA==.Mesalie:BAAALAADCggIEAAAAA==.',Mi='Miguel:BAAALAAECgUIBwAAAA==.Mirra:BAAALAAECgEIAQAAAA==.',Mo='Mooncat:BAAALAADCgYIBgAAAA==.Morganlefey:BAAALAAECggICAAAAA==.',Mu='Murgundon:BAABLAAFFIEGAAITAAIIoQmkBwCaAAATAAIIoQmkBwCaAAAAAA==.',Na='Nakhi:BAAALAAECgMIAwAAAA==.Namaste:BAAALAADCggICAAAAA==.Nasev:BAAALAADCgIIAgAAAA==.Nazgul:BAAALAADCgYIBgABLAAECggIEQAEAAAAAA==.',Ne='Necrolust:BAACLAAFFIEGAAQGAAMIAxGBEQCnAAAGAAIIxhGBEQCnAAAQAAEIfg9SEwBRAAASAAEIpgnkAgBOAAAsAAQKgR8ABAYACAhRIp8HABgDAAYACAjWIZ8HABgDABIABwiZF2QEAFwCABAABQgrHyQYANABAAAA.Nelislock:BAAALAAECgYICQAAAA==.',Ni='Nibbit:BAAALAADCggIFwAAAA==.',No='Notorium:BAAALAADCggICAAAAA==.',Ny='Nyaleth:BAAALAAECgUIDAAAAA==.Nyunii:BAAALAAECgMIBAAAAA==.',On='Onearrow:BAAALAADCgcICAAAAA==.',Oo='Oo:BAAALAAECgYICwAAAA==.',Or='Orkimedes:BAAALAAECgMIAwAAAA==.',Ot='Ottermage:BAAALAADCgUIBQAAAA==.',Ov='Overclockêd:BAAALAAECgYIDgAAAA==.',Pa='Paddington:BAAALAADCgcIDQAAAA==.Paggån:BAABLAAECoEVAAIUAAcIixE7FQCKAQAUAAcIixE7FQCKAQAAAA==.Palaizeny:BAAALAAECgYICQAAAQ==.Papipinto:BAAALAAFFAIIAwAAAA==.',Pe='Pepperonikka:BAAALAADCgYIBgAAAA==.',Pu='Purenergy:BAAALAAECggIDgAAAA==.',Ra='Raflnatorr:BAAALAADCggICAAAAA==.Raikiri:BAAALAAECgcIEQAAAA==.',Re='Redrage:BAAALAAECgEIAQAAAA==.Rejuvenator:BAAALAADCgYIBgAAAA==.Rellen:BAAALAADCggIBwAAAA==.Resana:BAAALAAECgYICAAAAA==.',Rh='Rhuarc:BAAALAAECggIDwAAAA==.',Ri='Richmon:BAAALAADCggIFAAAAA==.Rigormortis:BAAALAAECgYICwABLAAECgcIEQAQAKwlAA==.',Ro='Roxy:BAAALAAECgEIAgAAAA==.',Sa='Sabrïna:BAAALAADCggIFwAAAA==.Samblinks:BAAALAAECgYIBgAAAA==.Samlock:BAAALAADCggIFgAAAA==.Sandern:BAAALAAECgYICAAAAA==.Saradomir:BAAALAAECgUICgAAAA==.Saraphina:BAAALAADCgQIBgAAAA==.Sash:BAAALAADCggICAAAAA==.',Sc='Scheebo:BAAALAADCggIGAAAAA==.',Se='Sekushi:BAAALAAECgYICQAAAA==.Seven:BAAALAADCgIIAgAAAA==.',Sh='Shakegirl:BAAALAADCggICAAAAA==.Shakira:BAAALAADCgUIBQAAAA==.Shampli:BAAALAAECggICQAAAA==.Shattered:BAAALAADCgQIBAAAAA==.Shimei:BAAALAAECgYICwAAAA==.',Si='Sihiran:BAAALAAECgcIEQAAAA==.',Sj='Sjarlan:BAAALAADCggIFQAAAA==.',Sk='Skatt:BAABLAAECoEWAAIVAAgI6BIaEgDyAQAVAAgI6BIaEgDyAQAAAA==.Skp:BAAALAAECgMIAwAAAA==.',Sl='Slapymage:BAAALAAECgQIBAAAAA==.Slasher:BAABLAAECoEaAAIBAAgIqiQzAgBgAwABAAgIqiQzAgBgAwAAAA==.Slugesh:BAAALAAECgMIAwAAAA==.',So='Soulpone:BAAALAAFFAUIAgAAAA==.Sousmatras:BAAALAADCgcIDgAAAA==.',Sv='Svenne:BAAALAAECgYIBgAAAA==.',Ta='Tangobreath:BAABLAAECoEVAAIRAAgIERzNCQC9AgARAAgIERzNCQC9AgAAAA==.Taxapingu:BAAALAAECgQICQAAAA==.',Th='Thalassian:BAAALAADCggICAAAAA==.',Ti='Tia:BAAALAADCgcICgAAAA==.',Tj='Tjin:BAAALAADCgIIAgAAAA==.',To='Toxicdagger:BAAALAAECgcIDgABLAAECggIEQAEAAAAAA==.',Tr='Tripleshoot:BAAALAAECgcIDQAAAA==.Trivia:BAAALAAECgIIAgAAAA==.',Tw='Twiztidmind:BAAALAAECgYICQAAAA==.',Ul='Ulfire:BAAALAADCgcIAgAAAA==.',Un='Uncorrupted:BAAALAADCgUIBQAAAA==.Unholyboomer:BAAALAAECggIBgAAAA==.',Ur='Urukhai:BAAALAAECggIEQAAAA==.',Va='Valerya:BAAALAADCgYIBgAAAA==.Valkyriel:BAAALAADCgcIBgAAAA==.',Ve='Veganhandler:BAAALAADCggIFQAAAA==.Vestaperrion:BAAALAADCgYIAQAAAA==.',Vi='Viidakko:BAAALAAECggIDgABLAAECggIGQAFABUiAA==.Viilisdruid:BAAALAAECgcIBwABLAAECggIGQAFABUiAA==.Viilispala:BAABLAAECoEZAAIFAAgIFSLxEADdAgAFAAgIFSLxEADdAgAAAA==.Vippy:BAAALAADCgQIBAAAAA==.',Wh='Whipmaballs:BAAALAADCggIDwABLAADCggIFwAEAAAAAA==.',Wi='Winter:BAAALAAECgMIBwAAAA==.',Wy='Wynand:BAAALAAFFAIIAgAAAA==.Wyuu:BAAALAAECgYICQAAAA==.',Xa='Xarl:BAAALAAECgEIAQAAAA==.',Xr='Xrap:BAABLAAECoEXAAMWAAcI9iH5BgA7AgAWAAYIWCD5BgA7AgAXAAUI+RxIIgCoAQAAAA==.',Ya='Yalexa:BAAALAAECgMIBAAAAA==.',Ze='Zenbeard:BAAALAAECgYIDgAAAA==.Zephirothgr:BAAALAADCgcIBwAAAA==.',Zh='Zhroxx:BAAALAADCgQIAQAAAA==.Zhruxx:BAAALAAECgYIBgAAAA==.',Zi='Zizou:BAABLAAECoEXAAIYAAcIfB8ZIABnAgAYAAcIfB8ZIABnAgAAAA==.',Zl='Zlein:BAABLAAECoERAAMQAAcIrCVKCAB5AgAQAAYIGSRKCAB5AgASAAQIKCAuDgCBAQAAAA==.',['Ðr']='Ðrake:BAAALAAECggICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end