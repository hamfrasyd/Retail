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
 local lookup = {'Druid-Restoration','Evoker-Augmentation','Paladin-Protection','Druid-Feral','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Mage-Fire','Mage-Frost','Warrior-Fury','Priest-Holy','Unknown-Unknown','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','Evoker-Devastation','DemonHunter-Havoc','Paladin-Retribution','Mage-Arcane','Warlock-Demonology','Warlock-Destruction','Monk-Mistweaver','Priest-Shadow','Priest-Discipline','Shaman-Enhancement','Evoker-Preservation','Warrior-Protection','Rogue-Assassination','Hunter-Marksmanship','Warrior-Arms','Rogue-Outlaw','Rogue-Subtlety','Paladin-Holy',}; local provider = {region='EU',realm='Bladefist',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abomination:BAAALAADCgcICQAAAA==.',Ae='Aelinx:BAAALAAECgQIBwAAAA==.',Al='Alania:BAAALAAECgIIAgAAAA==.Alfdruidor:BAAALAAFFAIIAgAAAA==.Alisaie:BAAALAAECgMIAwABLAAECggIGQABAC0WAA==.',Am='Amari:BAABLAAECoEbAAICAAcIhhCkCACyAQACAAcIhhCkCACyAQAAAA==.',An='Anomindara:BAABLAAECoEjAAIDAAgIzSG8BQAEAwADAAgIzSG8BQAEAwAAAA==.',Ap='Apollocanon:BAAALAADCggIEQAAAA==.Apple:BAABLAAECoEzAAIEAAgIbSFaBAANAwAEAAgIbSFaBAANAwAAAA==.',Ar='Arathiël:BAAALAAECgYIBwAAAA==.Argorash:BAAALAAECgUIBQAAAA==.Arilone:BAAALAAECggICwAAAA==.',As='Asunà:BAAALAADCgMIAwAAAA==.',At='Atheistheist:BAAALAADCgYIBgAAAA==.',Av='Averance:BAACLAAFFIEJAAIFAAUIIAp0CQBRAQAFAAUIIAp0CQBRAQAsAAQKgSYAAgUACAjPH3chAJUCAAUACAjPH3chAJUCAAAA.',Az='Azhag:BAAALAAECggICAAAAA==.Azvrael:BAABLAAECoEnAAMGAAgIdxzkCgCKAgAGAAgIdxzkCgCKAgAHAAUI7Qyh3gASAQAAAA==.',Ba='Balerionas:BAAALAADCgUICAAAAA==.Bam:BAAALAAECggICAAAAA==.Bannyfatter:BAACLAAFFIEIAAIBAAIIcBc/GQCVAAABAAIIcBc/GQCVAAAsAAQKgSMAAwEACAgeG74eAEYCAAEACAgeG74eAEYCAAgABwhEFoUqAOoBAAAA.',Be='Belisama:BAAALAADCggIDQAAAA==.Bellzzar:BAAALAAECgIIBAAAAA==.',Bh='Bhok:BAAALAADCggICQAAAA==.',Bl='Blinkaway:BAABLAAECoEgAAMJAAgIMCFKAwB3AgAJAAgISxlKAwB3AgAKAAYIEiQ6GgAdAgAAAA==.',Bo='Bob:BAABLAAECoEhAAILAAgIiyBiFADqAgALAAgIiyBiFADqAgAAAA==.Bonegore:BAAALAADCggICAABLAAECggIHAAMAEAGAA==.',Br='Bradley:BAAALAADCgYIBgAAAA==.Brenda:BAAALAAECgMIAwABLAAECggIDQANAAAAAA==.',Bu='Bucky:BAAALAAECgEIAQAAAA==.Burser:BAABLAAECoEXAAIBAAgI/BZUJQAfAgABAAgI/BZUJQAfAgAAAA==.Burudlock:BAAALAAECgYIEwAAAA==.',['Bó']='Bólt:BAABLAAECoEVAAMOAAgICgw1RAC/AQAOAAgICgw1RAC/AQAPAAUIMgrAvgC9AAAAAA==.',Ca='Carolus:BAAALAADCgYIBgABLAAECgYIBgANAAAAAA==.Catfishone:BAABLAAECoEXAAIQAAcIfA4GEwBaAQAQAAcIfA4GEwBaAQAAAA==.',Ce='Celethal:BAABLAAECoEnAAMRAAgIpBe2FwBHAgARAAgIpBe2FwBHAgACAAIIXA8zFABOAAAAAA==.Celythriël:BAABLAAECoEVAAISAAgITxwHOgBHAgASAAgITxwHOgBHAgAAAA==.',Ch='Chæl:BAAALAAECggICwAAAA==.',Ci='Ciniá:BAECLAAFFIEGAAITAAII/hAELgCbAAATAAII/hAELgCbAAAsAAQKgS4AAhMACAjwJIwKAEYDABMACAjwJIwKAEYDAAAA.',Co='Coollikeafol:BAAALAADCgQIBQAAAA==.Cooltrain:BAAALAAECgYIEwAAAA==.Coruscuz:BAABLAAECoEbAAIUAAgIQhUuPgAtAgAUAAgIQhUuPgAtAgAAAA==.',Cr='Crag:BAAALAADCgQIBAAAAA==.Crazypower:BAACLAAFFIEGAAIPAAMIoiDYCQAgAQAPAAMIoiDYCQAgAQAsAAQKgSkAAw8ACAjAInQKAPgCAA8ACAjAInQKAPgCAA4AAQhbCpSmADYAAAAA.',Da='Daedelus:BAAALAADCgQIBAAAAA==.Darkcoke:BAAALAAECgUIBgAAAA==.Darknstormy:BAAALAAECgIIAgAAAA==.',De='Deathcomes:BAAALAAECgUICAAAAA==.',Di='Dignitas:BAABLAAECoEbAAIFAAgIHQ8vbwCWAQAFAAgIHQ8vbwCWAQAAAA==.',Dk='Dksucks:BAAALAAECgQIBAAAAA==.',Do='Doddie:BAAALAADCgcIDAAAAA==.Donkstonk:BAAALAAECgEIAQAAAA==.',Dr='Drexcia:BAAALAADCgMIAwAAAA==.Drákk:BAAALAADCggICAAAAA==.',['Dë']='Dëfiance:BAABLAAECoEmAAMVAAgIcRgyEABdAgAVAAgIcRgyEABdAgAWAAIIvBdltACOAAAAAA==.',Ec='Ectooplasm:BAAALAADCggIEAAAAA==.',Ee='Eevi:BAAALAADCggICAAAAA==.',El='Elenna:BAAALAADCggIFwAAAA==.Elir:BAAALAADCgcICwAAAA==.Elkimon:BAAALAADCgYIBgAAAA==.Ellia:BAAALAADCgYIBgAAAA==.Elrand:BAAALAAECgEIAQAAAA==.Eluray:BAAALAAECgYICAAAAA==.',En='Enano:BAAALAAECgcIBgAAAA==.',Ep='Epicboomboom:BAAALAADCggICAABLAAECggIGQABAC0WAA==.',Ev='Evilzodiax:BAABLAAECoEeAAIUAAcIpQgwfQBsAQAUAAcIpQgwfQBsAQAAAA==.',Ey='Eyybruh:BAAALAAECgUICQAAAA==.',Fa='Faithlezz:BAAALAADCggIDAAAAA==.',Fe='Femtina:BAAALAADCgMIAwAAAA==.',Fi='Fishstickboi:BAAALAADCgcIBwAAAA==.',Fl='Flandre:BAAALAADCggICAAAAA==.',Fr='Frames:BAAALAAECggICgAAAA==.Frysepinne:BAAALAAECggICwAAAA==.',Fu='Fumli:BAAALAAECgQIBgAAAA==.',Gh='Ghettogospel:BAABLAAECoEUAAIRAAYIdR6pHgADAgARAAYIdR6pHgADAgAAAA==.',Gi='Ginochjuice:BAAALAAECgIIAgAAAA==.',Gl='Glarial:BAAALAADCgQIBAAAAA==.Glitchmoon:BAAALAADCgUIBQABLAAECggIHAAVAD0gAA==.Glorin:BAAALAAECgQIBAAAAA==.',Gr='Grokedeus:BAABLAAECoEWAAITAAYIKBHdpQBsAQATAAYIKBHdpQBsAQAAAA==.',Gu='Guland:BAAALAAECgYICwAAAA==.Gunbot:BAABLAAECoEVAAIFAAYInCQsMgBJAgAFAAYInCQsMgBJAgAAAA==.',Ha='Havardr:BAAALAAECggIEgAAAA==.',He='Healslet:BAABLAAECoEcAAIDAAgI1xdmGAD3AQADAAgI1xdmGAD3AQAAAA==.Henkselman:BAABLAAECoEaAAITAAcIhhkVUAAdAgATAAcIhhkVUAAdAgAAAA==.',Hy='Hyperblaster:BAAALAAECgYIBgAAAA==.',Ia='Iamablueorc:BAAALAADCggIDAAAAA==.Ianna:BAAALAAECgYIBgAAAA==.',Im='Immowar:BAAALAADCgYIBgAAAA==.',In='Invisio:BAAALAADCggIGAAAAA==.',Is='Isoo:BAAALAADCggICAAAAA==.',Iz='Izame:BAAALAADCgcIBwAAAA==.',Ja='Jazulia:BAAALAADCgYIAgAAAA==.',Je='Jeegon:BAAALAADCgcIBwAAAA==.Jeskewee:BAABLAAECoEcAAIXAAgIShplDwBFAgAXAAgIShplDwBFAgAAAA==.',Jo='Johnkanon:BAAALAADCggIEAABLAAECggIHAAXAEoaAA==.Johnwcraft:BAAALAAECgYIDwAAAA==.Joode:BAAALAADCgMIBAAAAA==.',Ju='Juey:BAAALAAECgMIAwAAAA==.',Ka='Kadba:BAAALAAECgYIBgAAAA==.Kalashkalas:BAAALAADCgQIBAAAAA==.Kamikyo:BAAALAADCggICAABLAAECggIGQABAC0WAA==.Kaufmann:BAABLAAECoEdAAILAAcIVhgNPQAEAgALAAcIVhgNPQAEAgAAAA==.Kazav:BAABLAAECoEZAAIDAAgICCIZBgD8AgADAAgICCIZBgD8AgAAAA==.',Kh='Khamul:BAAALAAECgYIBgAAAA==.',Ki='Kiroudemon:BAAALAADCggIGAABLAAECggIHAAMAEAGAA==.Kiroudruid:BAAALAADCgQIBAABLAAECggIHAAMAEAGAA==.Kiroufury:BAAALAADCggICAABLAAECggIHAAMAEAGAA==.Kirouhealz:BAABLAAECoEcAAQMAAgIQAbRVgBTAQAMAAgIJAbRVgBTAQAYAAQIWQohawC1AAAZAAQIvwRpIwCGAAAAAA==.Kiroupala:BAAALAADCgIIAgABLAAECggIHAAMAEAGAA==.',Kl='Klaato:BAABLAAECoEXAAIQAAcIdBzFBwA+AgAQAAcIdBzFBwA+AgAAAA==.Klammppe:BAAALAAECgEIAQAAAA==.',Kr='Krelath:BAAALAAECgIIAgAAAA==.Krush:BAAALAAECgEIAQAAAA==.',Ku='Kuttamaräng:BAABLAAECoEfAAIQAAgI4RryBQB3AgAQAAgI4RryBQB3AgAAAA==.',Ky='Kyrii:BAAALAADCgIIAgAAAA==.',La='Lanarhodes:BAAALAAECggICAAAAA==.Laserback:BAABLAAECoEkAAIaAAgI5R6LBQCnAgAaAAgI5R6LBQCnAgAAAA==.Latterlig:BAAALAAECgYIBwAAAA==.',Le='Levily:BAACLAAFFIEHAAIbAAMIwR+vBQAnAQAbAAMIwR+vBQAnAQAsAAQKgRcAAhsACAjaIc4CABQDABsACAjaIc4CABQDAAAA.',Li='Lifecross:BAAALAAECgUIDQAAAA==.Lightcoke:BAAALAAECgYIBgAAAA==.Lightiron:BAAALAADCgcIBwAAAA==.Lispel:BAAALAAECgMIBQABLAAECgcIHAAcADAbAA==.Livewire:BAAALAAECgYIBgAAAA==.',Lu='Lul:BAAALAAECgcIEgAAAA==.',Ma='Macus:BAAALAADCgYICQAAAA==.Magikarp:BAAALAAECgIIAwAAAA==.Magischesok:BAABLAAECoEcAAIKAAgIaRkIFQBNAgAKAAgIaRkIFQBNAgAAAA==.Majkol:BAAALAAECgYIEgAAAA==.Mammal:BAAALAAECgMIAwABLAAFFAUIEQAdAJEbAA==.Manatrice:BAAALAADCgYIBgAAAA==.Maresha:BAAALAAECgYICQAAAA==.Mattdamon:BAAALAADCgYICQAAAA==.',Me='Meizin:BAAALAADCggICAAAAA==.',Mi='Mikeson:BAAALAADCggIDwAAAA==.',Mo='Mohg:BAAALAADCgIIAgABLAAECgcIHAAcADAbAA==.Moomeow:BAAALAAECgYICQAAAA==.Morain:BAAALAAECgIIAgAAAA==.Morrmegil:BAAALAAECgYICQAAAA==.',['Mü']='Müffinman:BAAALAADCgQIBwAAAA==.',Na='Nafti:BAAALAAECgYIDwAAAA==.Namulax:BAABLAAECoEZAAIBAAgILRZZLAD7AQABAAgILRZZLAD7AQAAAA==.Nazgûl:BAAALAADCggICAABLAADCggIDwANAAAAAA==.',Ne='Nelidia:BAAALAAECgYIDAAAAA==.Nesrivalo:BAABLAAECoEeAAITAAgIeR/5GgDoAgATAAgIeR/5GgDoAgAAAA==.',Om='Omegalulz:BAAALAADCggICAABLAAECgcIEgANAAAAAA==.',On='Onoskelis:BAABLAAECoEXAAMVAAgIPhoiHgDsAQAWAAgI4RF2QgD5AQAVAAYI7BwiHgDsAQAAAA==.',Pa='Paholainen:BAAALAAECgMIAgAAAA==.Paphat:BAAALAAECgQIBAABLAAECggIGAAeABQZAA==.Paphelgen:BAAALAAECgIIAgAAAA==.Paphoontress:BAABLAAECoEYAAIeAAcIFBnkKQAKAgAeAAcIFBnkKQAKAgAAAA==.',Pe='Peenisha:BAAALAAECgUIBQAAAA==.',Pi='Pico:BAAALAADCggICAAAAA==.Pinksky:BAABLAAECoEfAAIFAAgI0A8wZgCrAQAFAAgI0A8wZgCrAQAAAA==.Pisslowxoxo:BAAALAAECgMIBAAAAA==.Pisslowxx:BAAALAAECgYIBgAAAA==.',Po='Podlock:BAABLAAECoEjAAMWAAgI3x+zFgDfAgAWAAgI3x+zFgDfAgAVAAEIKyLMeQBRAAAAAA==.Podrouge:BAAALAAECgUICAAAAA==.Pogu:BAAALAAECggIHwAAAQ==.Polunicya:BAAALAADCggICAAAAA==.Pom:BAABLAAECoEcAAIcAAgIXR2TEACHAgAcAAgIXR2TEACHAgAAAA==.Pomonk:BAAALAAECgYIBgAAAA==.Pooli:BAABLAAECoEWAAITAAgILRN1aQDgAQATAAgILRN1aQDgAQAAAA==.Postcookiee:BAAALAADCgcIDwAAAA==.Powaah:BAAALAADCgcICwAAAA==.Powpow:BAAALAADCgQIBQAAAA==.',Pr='Prevoker:BAAALAADCgMIAwAAAA==.',Pu='Pudiox:BAAALAADCgcICwAAAA==.',Ra='Rage:BAABLAAECoEeAAITAAgIaCCzHADfAgATAAgIaCCzHADfAgAAAA==.Raggamuffin:BAABLAAECoElAAIfAAgIkyAdAwD0AgAfAAgIkyAdAwD0AgAAAA==.Ramuuli:BAAALAAECggIDgAAAA==.Rastashot:BAAALAAECgYICAABLAAECggIFQAOAAoMAA==.',Re='Rei:BAACLAAFFIEGAAIRAAMIpRGzCwDiAAARAAMIpRGzCwDiAAAsAAQKgR8AAhEACAjZIjcFADADABEACAjZIjcFADADAAAA.Retli:BAAALAAECgUIBgAAAA==.',Ro='Rohnan:BAABLAAECoEcAAIcAAcIMBv/IwDXAQAcAAcIMBv/IwDXAQAAAA==.',Sa='Sagblad:BAAALAADCgYIBwAAAA==.Saveme:BAAALAAECgcICQAAAA==.',Sc='Scheerjeweg:BAAALAADCggICgAAAA==.Schoulst:BAAALAADCggICAAAAA==.Scrubgaming:BAAALAAECgIIAgAAAA==.Scurtz:BAAALAAECgYIBgAAAA==.',Sh='Shadowgrip:BAABLAAECoEhAAIdAAgIdBZuGAA/AgAdAAgIdBZuGAA/AgAAAA==.Shiningginge:BAAALAADCgUIBQAAAA==.',Sk='Skadoesh:BAAALAADCgMIAwAAAA==.',Sm='Smiguhontas:BAAALAADCgUIBQAAAA==.Smiguman:BAAALAADCgYIDAAAAA==.Smigust:BAAALAAECggIBgAAAA==.Smígu:BAACLAAFFIEHAAISAAMIIw99EwDnAAASAAMIIw99EwDnAAAsAAQKgSoAAhIACAiaIIUXAO4CABIACAiaIIUXAO4CAAAA.',So='Sorscha:BAABLAAECoEbAAITAAYIDAjqyQAoAQATAAYIDAjqyQAoAQAAAA==.',Sp='Spoondehunt:BAAALAADCggICAABLAAECggIHAAaAJUcAA==.Spoondruid:BAAALAADCgMIAwABLAAECggIHAAaAJUcAA==.Spoonhaman:BAABLAAECoEcAAIaAAgIlRzMBwBlAgAaAAgIlRzMBwBlAgAAAA==.Spoonpala:BAAALAADCggICAABLAAECggIHAAaAJUcAA==.',St='Strykerblue:BAAALAAECgEIAQAAAA==.Stén:BAAALAADCgMIAwAAAA==.',Su='Subsy:BAABLAAECoEjAAQQAAcItSDtBACYAgAQAAcItSDtBACYAgAEAAIIcgsWOQBXAAAIAAIIHQ39gABUAAAAAA==.Succubie:BAAALAAECgYIBgAAAA==.Sudana:BAAALAADCggIDwAAAA==.Sup:BAAALAAECgYIEgABLAAECgcICwANAAAAAA==.Superman:BAAALAADCggIDQAAAA==.Sushiwúshi:BAAALAAECgcICQAAAA==.',Ta='Tails:BAABLAAECoEoAAMgAAgIbSMNAQA7AwAgAAgIbSMNAQA7AwAhAAUIPBjcJAA4AQAAAA==.Tainttickler:BAAALAADCggIDQAAAA==.Tamadotchi:BAAALAADCgMIAwAAAA==.Tanadzil:BAAALAAECgYIBgAAAA==.',Te='Telesmurfken:BAAALAADCgcIBwABLAAECggIHAAaAJUcAA==.',Th='Thingsgoboom:BAAALAAECgYIDAAAAA==.Thondin:BAAALAAECgEIAQAAAA==.Thordenstore:BAAALAAECgMIAwAAAA==.Thraximundar:BAAALAADCgcICAAAAA==.',To='Tokatci:BAAALAAECgYIDQAAAA==.',Tr='Trollmann:BAAALAAECgYIDQAAAA==.Trons:BAABLAAECoEUAAQiAAUICBjtMQBpAQAiAAUICBjtMQBpAQATAAIIRRfZBwGPAAADAAEIiCKjUABkAAABLAAECgYIBgANAAAAAA==.',Un='Underslicer:BAAALAADCgYIBgAAAA==.',Ux='Uxxia:BAAALAADCggICAABLAAECggIHAAVAD0gAA==.',Va='Vaahnzy:BAAALAADCgcIBwAAAA==.Valsvik:BAAALAADCggICAAAAA==.Vassaya:BAAALAADCggIDwAAAA==.',Ve='Ven:BAAALAAECgcIEwAAAA==.Venn:BAAALAAECgEIAQAAAA==.',Vi='Viidapew:BAAALAADCgcIBwAAAA==.',Vo='Voidslayer:BAAALAADCgcIDAABLAAECggIHAAXAEoaAA==.Voize:BAAALAADCgcIAgAAAA==.Vooze:BAAALAAECgEIAQABLAAECgYIBgANAAAAAA==.Vowed:BAAALAAFFAEIAQAAAA==.',Vr='Vramer:BAAALAAECggICAAAAA==.',Wa='Walpurga:BAAALAAECgcICgABLAAECggIHgAUAGgdAA==.',We='Westquest:BAAALAAECgcIEwAAAA==.',Wi='Wildrake:BAAALAAECgEIAQAAAA==.Wildy:BAAALAAECgYICQAAAA==.Wingtardium:BAAALAAECgYIBgAAAA==.',Xa='Xarbarian:BAAALAADCggICAAAAA==.',Xu='Xunter:BAAALAADCggIDgAAAA==.',Ya='Yamazakí:BAABLAAECoEXAAMKAAcIUgpKNwBqAQAKAAcIUgpKNwBqAQAUAAYISQMHqwDTAAAAAA==.',Yi='Yikess:BAAALAAECgYICAAAAA==.',Yx='Yxus:BAAALAADCggICAAAAA==.',Za='Zabuzar:BAAALAADCgYIBgAAAA==.Zachariasz:BAAALAAECgcIDAABLAAECggIHgAUAGgdAA==.Zameleon:BAAALAADCgYIBgAAAA==.Zander:BAAALAAECgYIDQAAAA==.',Ze='Zeitgeist:BAAALAAECgEIAQAAAA==.',Zu='Zurin:BAABLAAECoEYAAIUAAgIIhVwQQAgAgAUAAgIIhVwQQAgAgAAAA==.',['Éi']='Éire:BAAALAADCgcICQAAAA==.',['ßa']='ßattycrease:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end