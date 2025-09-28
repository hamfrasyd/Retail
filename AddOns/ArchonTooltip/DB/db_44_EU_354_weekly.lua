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
 local lookup = {'DeathKnight-Unholy','Shaman-Restoration','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Shaman-Elemental','Unknown-Unknown','Evoker-Augmentation','Warrior-Protection','Paladin-Retribution','DeathKnight-Frost','Priest-Holy','Evoker-Devastation','Druid-Feral','Warlock-Destruction','Paladin-Protection','Druid-Restoration','Shaman-Enhancement','DemonHunter-Vengeance','Priest-Discipline','Paladin-Holy','Warrior-Fury','Warlock-Demonology','Mage-Arcane','Warlock-Affliction','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Mage-Fire',}; local provider = {region='EU',realm='Xavius',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abdallahlol:BAAALAADCggICAAAAA==.',Ad='Adi:BAAALAAECgYIBwAAAA==.',An='Anton:BAAALAAECgIIAQAAAA==.',Ar='Arovs:BAAALAAECgYIDwAAAA==.Artoria:BAAALAADCggICAAAAA==.',Au='Augustus:BAACLAAFFIEFAAIBAAIIhhcICwCrAAABAAIIhhcICwCrAAAsAAQKgR0AAgEACAhmIyEDAC0DAAEACAhmIyEDAC0DAAAA.',Aw='Awarrior:BAAALAAFFAIIAgAAAA==.',Ax='Aximusprime:BAAALAADCggICAAAAA==.Axio:BAAALAAECgQIBgAAAA==.',Ay='Ayizan:BAABLAAECoEYAAICAAgIFRBkcABoAQACAAgIFRBkcABoAQAAAA==.',Ba='Bacalao:BAAALAAECgYIAgABLAAECggIGQADAEogAA==.Barabím:BAAALAAECggICQAAAA==.Baradins:BAAALAAECgIIBQAAAA==.',Be='Beastmeister:BAABLAAECoEXAAMEAAgIXCApDgDlAgAEAAgIXCApDgDlAgAFAAEIGA2+DQE1AAAAAA==.Beatpriest:BAAALAADCggICAAAAA==.Beermaster:BAAALAADCggICAAAAA==.Beliar:BAAALAADCggIDgAAAA==.Betrayèr:BAABLAAECoEfAAIDAAgIWhLMbwC0AQADAAgIWhLMbwC0AQAAAA==.Bettyswollok:BAABLAAECoEXAAIGAAgIhhd0JgBVAgAGAAgIhhd0JgBVAgAAAA==.',Bl='Bloodborne:BAAALAAECggIEwAAAA==.Bloodgrimm:BAAALAADCgUIBQABLAAECgYIEAAHAAAAAA==.Bloodyrosa:BAAALAADCgcIBwAAAA==.',Bo='Bobbybrunkuk:BAAALAADCgEIAQABLAAECgYIGQADABYjAA==.Bobthepriest:BAAALAADCgQIBAAAAA==.Bobthetank:BAAALAADCgcICAAAAA==.Bolark:BAAALAADCgcIBwABLAAECggIDwAHAAAAAA==.Bombarda:BAAALAADCgcIBwAAAA==.Bonebearer:BAAALAADCgcIBwAAAA==.',Br='Brokenrubber:BAAALAAECgYICwAAAA==.Bror:BAAALAAECgEIAgAAAA==.Brunkuken:BAABLAAECoEZAAIDAAYIFiOVOABQAgADAAYIFiOVOABQAgAAAA==.',Bu='Bunnyfufu:BAAALAAECgQIBwAAAA==.',['Bå']='Bålkugler:BAAALAAECgIIAgABLAAECggIEwAHAAAAAA==.',Ca='Cactuss:BAAALAADCgYIDAAAAA==.Candymán:BAAALAAECgMICgAAAA==.',Ce='Cephandrius:BAAALAADCggICAAAAA==.',Cr='Craw:BAAALAAECgEIAQAAAA==.',Da='Dagoat:BAAALAAECggIEwAAAA==.Dalinar:BAABLAAECoEVAAICAAYIaBzgRADiAQACAAYIaBzgRADiAQAAAA==.',De='Deablio:BAAALAAECgYIBgAAAA==.Deathpowa:BAAALAAECgYICwAAAA==.Deathshade:BAAALAAECggICAAAAA==.Deathview:BAAALAAECggIEAAAAA==.Decimus:BAAALAADCgcIBwAAAA==.Demantic:BAAALAADCgYIBgAAAA==.Dexii:BAAALAAECgEIAQAAAA==.',Di='Diaga:BAAALAADCggIAQAAAA==.',Dj='Djtwo:BAAALAAECgYIDwABLAAFFAYIHAAIAEIWAA==.',Do='Dotdotdie:BAAALAAECgMIAwAAAA==.',Dr='Dracoelfa:BAAALAADCgEIAQAAAA==.Draconero:BAAALAADCgIIAgAAAA==.Drudru:BAAALAADCgEIAQAAAA==.',Du='Dure:BAAALAADCgIIAgABLAAECgcIHwAGABggAA==.',['Då']='Dårehunter:BAAALAADCggICAAAAA==.',Ef='Effect:BAAALAADCggICAAAAA==.',El='Elganrod:BAAALAADCgYIBgAAAA==.',Ex='Exort:BAACLAAFFIEYAAIJAAYIqCSOAACTAgAJAAYIqCSOAACTAgAsAAQKgTEAAgkACAisJUkDAE8DAAkACAisJUkDAE8DAAAA.',Fa='Fantasygirl:BAAALAAECgMIAwAAAA==.Fantasykid:BAAALAADCgYIBgAAAA==.',Fe='Felwinter:BAAALAADCgIIAgAAAA==.',Fi='Fidoodle:BAAALAAECggICAAAAA==.',Fl='Flannel:BAABLAAECoEZAAIDAAcI1BuaOABQAgADAAcI1BuaOABQAgAAAA==.Florx:BAAALAAECgYIEwAAAA==.',Fo='Foxy:BAAALAAECgIIAgAAAA==.',Fr='François:BAAALAADCggICAAAAA==.Frenchie:BAABLAAECoEfAAIKAAgIYiWxBABuAwAKAAgIYiWxBABuAwAAAA==.Frolic:BAAALAADCgYIBgABLAAECgcIHwAGABggAA==.Frosteyes:BAABLAAECoEhAAILAAgIlh6IJAC6AgALAAgIlh6IJAC6AgAAAA==.Frostmore:BAAALAADCgcIBwAAAA==.',Fu='Fuksdeluks:BAABLAAECoEfAAMEAAgI5hjPIgA6AgAEAAgIIxfPIgA6AgAFAAYI8BooZQCzAQAAAA==.Furrygang:BAAALAADCgcIBwAAAA==.',Ga='Gatito:BAAALAAECgEIAQAAAA==.Gaya:BAAALAAECgYIBwAAAA==.',Gh='Ghila:BAAALAADCggICAAAAA==.',Gi='Gimbrumdwal:BAAALAADCggICAAAAA==.',Gl='Glacialmaw:BAAALAADCgcIBwAAAA==.Glare:BAABLAAECoEcAAIMAAgIUCOyBwAfAwAMAAgIUCOyBwAfAwAAAA==.',Go='Gobliman:BAAALAADCggICAAAAA==.',Gu='Gurns:BAAALAADCggIDwAAAA==.',Gx='Gxy:BAAALAADCgUIBQAAAA==.',Gy='Gyatsu:BAAALAAECgEIAQAAAA==.',Ha='Hardcøre:BAAALAAFFAIIBAAAAA==.Hazmo:BAAALAADCggIEQAAAA==.',He='Heltsinnes:BAABLAAFFIEKAAICAAMItx7qCwAMAQACAAMItx7qCwAMAQAAAA==.Helya:BAAALAADCgcICgAAAA==.',Hi='Hiereas:BAAALAADCgYIEQAAAA==.',Hu='Hunterelo:BAAALAAECgYICQAAAA==.',Hy='Hyoríon:BAAALAADCggIEwAAAA==.',Im='Imoogi:BAACLAAFFIEHAAINAAMIrxdnCgD5AAANAAMIrxdnCgD5AAAsAAQKgRcAAg0ABwjbIm8OALQCAA0ABwjbIm8OALQCAAEsAAUUBQgKAA4AnhQA.',In='Inwhile:BAAALAADCggIDgAAAA==.',Io='Iol:BAAALAADCggIFQABLAAECgUIDgAHAAAAAA==.',Iv='Ivchony:BAAALAAECgEIAQAAAA==.',Ja='Jayal:BAAALAAECgYICwAAAA==.',Je='Jepari:BAAALAADCggICAAAAA==.',Jo='Joelyn:BAAALAADCgMIAwAAAA==.',Ju='Juls:BAAALAAFFAIIAgAAAA==.',['Jó']='Jóhnny:BAAALAAECgYIBwAAAA==.',Ka='Karlie:BAAALAAECggIBgAAAA==.Kat:BAAALAAECgIIAgAAAA==.',Ke='Kendarick:BAAALAADCgcICQAAAA==.Kenthegreat:BAAALAADCgEIAQAAAA==.',Kh='Khandhar:BAAALAADCgYIBgAAAA==.',Kl='Klokkeblomst:BAABLAAECoEWAAIPAAcISw58YQCUAQAPAAcISw58YQCUAQAAAA==.Klum:BAAALAAECgEIAQAAAA==.',Ko='Kolamola:BAAALAADCgcIBwAAAA==.',Kr='Kriptis:BAAALAAECgYIBgAAAA==.',Kv='Kvoten:BAAALAAFFAIIAgAAAA==.',La='Laddenx:BAAALAADCgYICwAAAA==.Laminia:BAAALAAECgYIEAAAAA==.Lastöfus:BAAALAAECgYICQAAAA==.Lawlith:BAAALAAECgMIAwAAAA==.',Le='Letheriel:BAAALAAECgIIAwAAAA==.Levia:BAAALAADCgEIAQABLAAECggIFgAKACEOAA==.Leviachan:BAABLAAECoEWAAIKAAYIIQ5VuQBNAQAKAAYIIQ5VuQBNAQAAAA==.',Li='Lichtfut:BAAALAAECggICwAAAA==.Lilbullx:BAAALAAECgYICgAAAA==.Liska:BAAALAADCggICAAAAA==.',Lo='Lowekr:BAAALAADCgUIBQAAAA==.',Lu='Luciefear:BAAALAAECgYIBgABLAAECggIGgAQAIARAA==.Lufoo:BAAALAAECgUICQAAAA==.Luicfer:BAAALAAECgMIAwAAAA==.',Ly='Lyra:BAAALAAECgUIAQAAAA==.Lyrà:BAAALAADCggICgABLAAECgUIAQAHAAAAAA==.',Ma='Mageny:BAAALAADCgcIBwAAAA==.Malaedan:BAAALAAECgYIBgAAAA==.Malathar:BAAALAADCgIIAgAAAA==.Markon:BAABLAAECoEZAAIRAAYI0CGGHwBEAgARAAYI0CGGHwBEAgAAAA==.',Me='Meeb:BAABLAAECoEZAAIDAAgISiBpHADUAgADAAgISiBpHADUAgAAAA==.Megabyzusx:BAAALAADCgcIBwAAAA==.Mentee:BAAALAADCgIIAgAAAA==.Mentemonk:BAAALAADCgUIBQAAAA==.Merulion:BAAALAADCggICAAAAA==.Messenjaah:BAABLAAECoEdAAISAAgI5xzLBQCiAgASAAgI5xzLBQCiAgAAAA==.Metahelah:BAABLAAECoEfAAIGAAcIGCDCHACVAgAGAAcIGCDCHACVAgAAAA==.',Mo='Mogiie:BAAALAAECgQIBwAAAA==.Moj:BAACLAAFFIEGAAIRAAII3SWTDADcAAARAAII3SWTDADcAAAsAAQKgR4AAhEABgifI9UZAGgCABEABgifI9UZAGgCAAAA.Mondo:BAAALAAECgQIBgAAAA==.',Mw='Mwi:BAAALAAECgMICgAAAA==.',My='Mylonian:BAAALAAECgcIDwAAAA==.Myrdraal:BAABLAAECoEUAAITAAgItRKqGQC+AQATAAgItRKqGQC+AQAAAA==.Myrna:BAABLAAECoEaAAMUAAgInBwjBAB0AgAUAAYISiQjBAB0AgAMAAgILAu4SQCIAQABLAAECggIKgAVAHIeAA==.Myrongaines:BAABLAAECoEiAAIWAAgIrRSHPAALAgAWAAgIrRSHPAALAgAAAA==.',Na='Nairdan:BAAALAADCgQIBAAAAA==.',Ni='Nisse:BAAALAAECgUIBQAAAA==.Niyo:BAAALAADCgUIBwAAAA==.',No='Notaste:BAAALAADCggIEAAAAA==.',Of='Ofrisk:BAABLAAECoEXAAIDAAgIDhsYQQAxAgADAAgIDhsYQQAxAgABLAAFFAMIBQAXADkQAA==.',Or='Oranoss:BAAALAAECgcIEgAAAA==.Orviusprime:BAAALAAECgYIBgAAAA==.',Ot='Ott:BAAALAAECggIDwAAAA==.',Ow='Owo:BAAALAADCgIIAQAAAA==.',Pe='Pellegrino:BAAALAADCgcIBwAAAA==.',Ph='Phalynx:BAAALAADCgYIDAAAAA==.Phax:BAABLAAECoEZAAMGAAgI+BFMRADDAQAGAAcImRJMRADDAQACAAMIygty3ACKAAAAAA==.Phaxh:BAAALAADCgMIAwAAAA==.Phaxos:BAAALAADCgQIBAAAAA==.Phenome:BAAALAAECgQIBQAAAA==.',Pi='Picikukkpapa:BAAALAAECgEIAQAAAA==.Pilavpowa:BAAALAAECgIIAgAAAA==.Pivnoenechto:BAAALAADCgQIBwAAAA==.',Po='Pontiff:BAABLAAECoEUAAIMAAgIvB2yEADKAgAMAAgIvB2yEADKAgABLAAFFAIIDAAFANEkAA==.',['Pä']='Päddy:BAAALAAECgUICgAAAA==.',Ra='Rachellaa:BAAALAADCggICAAAAA==.Ragnap:BAAALAADCggIDwAAAA==.Raoden:BAAALAADCgcICAAAAA==.',Re='Rectifier:BAACLAAFFIEKAAIYAAMIXxtXFwAAAQAYAAMIXxtXFwAAAQAsAAQKgTgAAhgACAiqJHkKADMDABgACAiqJHkKADMDAAAA.Redcloud:BAAALAAECgYIDgAAAA==.Redmamba:BAAALAADCgIIAgAAAA==.Revilo:BAAALAADCggIEwABLAAECggIEwAHAAAAAA==.',Ri='Riams:BAAALAAECggIEgAAAA==.Riesenriemen:BAAALAADCgYIBgAAAA==.',Ru='Ruf:BAAALAAECgIIAgAAAA==.',Ry='Ryuk:BAABLAAECoEfAAIFAAYIICIiOwArAgAFAAYIICIiOwArAgAAAA==.Ryuurei:BAAALAAECggIEgAAAA==.Ryvarín:BAAALAADCggIDwAAAA==.',['Rø']='Røvmås:BAAALAADCgYIBgAAAA==.',Sa='Saeva:BAAALAADCggICAAAAA==.Saiborgwar:BAAALAADCgIIAgAAAA==.Sakuraknight:BAAALAAECgEIAQAAAA==.Sam:BAACLAAFFIEOAAIPAAUI0wohDgB/AQAPAAUI0wohDgB/AQAsAAQKgS0AAw8ACAjeH38WAOICAA8ACAjeH38WAOICABkAAQhwE480AEoAAAAA.Sassy:BAABLAAECoEiAAIPAAgIqA3AUADIAQAPAAgIqA3AUADIAQAAAA==.Satudarah:BAABLAAECoEZAAMWAAgIVh+BIwCHAgAWAAgIDx6BIwCHAgAaAAII3xf3JACZAAAAAA==.',Sc='Scourgespree:BAABLAAECoEoAAIBAAgICSazAAB5AwABAAgICSazAAB5AwAAAA==.Scralett:BAAALAAECgIIAgAAAA==.',Se='Sendrea:BAAALAAECgUIBQAAAA==.Serniczek:BAABLAAECoEgAAMFAAcIsiHvNwA3AgAFAAcIjh/vNwA3AgAEAAYImRs5OAC+AQAAAA==.',Sh='Shamly:BAAALAAECggIBgAAAA==.Shatterhoof:BAAALAADCggIDAAAAA==.Shinazugawa:BAAALAAECgYIBgAAAA==.Shivanizy:BAAALAAECgcIEgAAAA==.Shâdowspiké:BAAALAAECggICAAAAA==.',Si='Sigmund:BAAALAADCgcICAAAAA==.Simmeb:BAAALAAECggICAAAAA==.Sinic:BAAALAADCgcIBwAAAA==.Sino:BAAALAAFFAIIAgAAAA==.Siz:BAAALAAECgYICwABLAAECgcIFgACAEATAA==.',Sk='Skyra:BAAALAAECgUIBQAAAA==.Skíttles:BAAALAADCgcIBwAAAA==.',Sl='Slaayer:BAAALAAECgcICQAAAA==.',Sn='Sneerfrost:BAAALAADCgcIDQABLAAECgcIGgABAL4UAA==.',So='Solfryd:BAABLAAECoEfAAIRAAcImCZPBgAZAwARAAcImCZPBgAZAwAAAA==.Sollin:BAAALAADCggICAAAAA==.Solutionq:BAAALAADCggICwABLAAECgYICAAHAAAAAA==.Solutions:BAAALAADCggIFwABLAAECgYICAAHAAAAAA==.Solutionx:BAAALAAECgYICAAAAA==.Sonicaz:BAABLAAECoEXAAMbAAYIfwkPJwAoAQAbAAYIswgPJwAoAQAcAAYIdQXuRAAUAQAAAA==.',Sp='Spaenk:BAAALAADCggICQAAAA==.Spendi:BAAALAADCgcICQAAAA==.Spiritarrow:BAAALAADCgYIBgABLAAFFAYIFgAEAHMmAA==.',St='Stinkbreath:BAAALAAECggIAgAAAA==.',Sx='Sxxthgoat:BAAALAAECgYIDAAAAA==.',Ta='Tabu:BAAALAADCggICAAAAA==.',Tc='Tct:BAAALAAECgUIBgAAAA==.',Te='Teslatrassel:BAAALAAECgcIDgAAAA==.',Th='Thalendris:BAAALAADCgcIBwAAAA==.',Ti='Tissyndeia:BAAALAAECgYICAAAAA==.',Tm='Tmt:BAAALAAECgYIEAAAAA==.',Tn='Tnt:BAAALAAECgYIBwAAAA==.',To='Tobleon:BAAALAAFFAIIAgAAAA==.Tooezy:BAABLAAFFIEFAAMXAAMIORDACwCoAAAXAAIIXhfACwCoAAAPAAIIsAeaMgCKAAAAAA==.Tossler:BAACLAAFFIEJAAICAAMIgAmAHgCmAAACAAMIgAmAHgCmAAAsAAQKgS0AAwIACAiWGMYqAEACAAIACAiWGMYqAEACAAYAAwioAZ+bAGMAAAAA.Tovah:BAAALAADCggICQAAAA==.Tovaro:BAAALAADCgYICwABLAADCggICQAHAAAAAA==.',Tu='Tutankamon:BAAALAAECgIIAgAAAA==.Tutankamoon:BAABLAAECoEaAAQUAAcI0hijCgDTAQAUAAYIshqjCgDTAQAdAAUItQoJXgAJAQAMAAIIqQnWlwBZAAAAAA==.Tuvis:BAAALAAECgYICgAAAA==.',Ty='Tyríon:BAAALAADCggIJgAAAA==.',Uk='Ukrotitelj:BAACLAAFFIEGAAIEAAII2hxLFQCiAAAEAAII2hxLFQCiAAAsAAQKgSgAAgQACAhMIZ0LAPsCAAQACAhMIZ0LAPsCAAAA.',Un='Untitledone:BAAALAAECgUICwAAAA==.',Va='Vafan:BAAALAADCggICAAAAA==.Valefor:BAAALAADCggIGQAAAA==.Valusha:BAAALAAECggICAAAAA==.Vanilor:BAAALAAECgYICgAAAA==.Vankisa:BAAALAAECggIDQAAAA==.Vasher:BAAALAADCgcIEQAAAA==.',Ve='Velrathis:BAAALAADCgUICAAAAA==.Verbati:BAABLAAECoEWAAICAAcIQBMiaQB8AQACAAcIQBMiaQB8AQAAAA==.Veresaa:BAAALAAECgEIAQAAAA==.',Vi='Vidov:BAAALAADCgMIAwAAAA==.',Vl='Vladimiry:BAABLAAECoEYAAIPAAcIhBK4VQC4AQAPAAcIhBK4VQC4AQAAAA==.',Vo='Voop:BAAALAAECgYIBgAAAA==.',Vy='Vynvalin:BAAALAADCggIDwAAAA==.',['Vå']='Vådascott:BAAALAADCgMIAwAAAA==.Vårlök:BAAALAAECgUIBQAAAA==.',Wa='Wardedman:BAAALAADCggICgAAAA==.Waxillium:BAAALAAECgYIDwAAAA==.Waxnwane:BAAALAAECgEIAQABLAAECggIFAATALUSAA==.Wayne:BAAALAAECgQIBwAAAA==.',We='Welehu:BAABLAAECoEaAAIeAAgI+BdcAwB0AgAeAAgI+BdcAwB0AgAAAA==.',Wi='Wingedhavoc:BAAALAAECggICgAAAA==.',Wo='Wolfixia:BAAALAADCgQIBAAAAA==.',Xo='Xoduz:BAABLAAFFIEFAAIDAAIIHB9TGwC2AAADAAIIHB9TGwC2AAAAAA==.',Ya='Yamomoto:BAAALAADCggIEAAAAA==.',['Yú']='Yúri:BAAALAADCgcIBwAAAA==.',Za='Zalisrcemoje:BAAALAADCggICAAAAA==.',Zb='Zbr:BAAALAADCgMIAwAAAA==.Zbyszek:BAAALAAECgYICAABLAAECgYIDwAHAAAAAA==.',Zh='Zhaenya:BAAALAADCgcIBwAAAA==.',Zo='Zoraide:BAAALAADCgYIBgAAAA==.',['Öd']='Ödet:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end