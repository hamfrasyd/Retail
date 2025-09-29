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
 local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Druid-Restoration','Monk-Windwalker','Mage-Arcane','Paladin-Retribution','Druid-Guardian','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Druid-Balance','Warrior-Protection','Druid-Feral','Warrior-Fury','Priest-Holy','Rogue-Subtlety','Hunter-BeastMastery','Shaman-Restoration','Warlock-Demonology','Shaman-Enhancement','Warlock-Destruction','Shaman-Elemental','Warlock-Affliction','Rogue-Assassination','Evoker-Devastation','Evoker-Augmentation','Monk-Brewmaster','Evoker-Preservation','Priest-Discipline','Priest-Shadow','Rogue-Outlaw','Paladin-Protection',}; local provider = {region='EU',realm='Area52',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abbigail:BAAALAADCggICAAAAA==.',Ag='Agrona:BAAALAADCggICwAAAA==.',Ak='Akudh:BAAALAADCgMIAwAAAA==.',Al='Albedô:BAABLAAECoEVAAMBAAgICiHQGQDmAgABAAgICiHQGQDmAgACAAUIfRiLJgBHAQAAAA==.Alphazerø:BAAALAAECggIBgAAAA==.',An='Angeldeath:BAAALAADCggIDgAAAA==.Angelo:BAAALAAECgQICQAAAA==.',Ap='Apokalyptiko:BAAALAAECggIEwAAAA==.Apple:BAAALAAECggIBAAAAA==.',Ar='Aragny:BAAALAADCgcIBwAAAA==.Aratot:BAABLAAECoEWAAIDAAcIURDnLACnAQADAAcIURDnLACnAQAAAA==.Ardela:BAAALAAECgEIAQAAAA==.Arogant:BAAALAADCgUIBQAAAA==.Arokh:BAAALAADCggIDwABLAADCggICAAEAAAAAA==.Arriba:BAACLAAFFIEKAAIFAAII2Qu3IQB8AAAFAAII2Qu3IQB8AAAsAAQKgR8AAgUACAgiFdIuAPMBAAUACAgiFdIuAPMBAAAA.Artemispan:BAAALAAECgUIEgAAAA==.Arthamas:BAAALAAECgYIDAAAAA==.Artura:BAAALAADCgcICwAAAA==.Arygb:BAAALAAECgIIAgAAAA==.',As='Asela:BAABLAAECoEUAAIGAAYIIxhURwCLAQAGAAYIIxhURwCLAQAAAA==.Ashbrínger:BAAALAAECgIIBAAAAA==.',Av='Avandarra:BAAALAAECgYIEQAAAA==.',Ay='Ayjumi:BAAALAADCggICAAAAA==.',Ba='Baerson:BAAALAADCggIDQAAAA==.Baleríon:BAAALAADCgIIAgAAAA==.Batardeaux:BAAALAADCggICAAAAA==.Baumknutsche:BAAALAAECgIIAgAAAA==.',Be='Belegòr:BAAALAADCgYIBgABLAAECgcIHAAHAPMXAA==.Belethel:BAAALAAECgcICgAAAA==.Belga:BAABLAAECoEWAAMIAAgI5xlUNQBYAgAIAAgIxBlUNQBYAgADAAIIaQpWdwBJAAAAAA==.Bergamont:BAABLAAECoEZAAIJAAcITh1JXQACAgAJAAcITh1JXQACAgAAAA==.Betor:BAAALAADCgYIAwAAAA==.',Bi='Bindera:BAAALAADCgQIBAAAAA==.',Bl='Bloodbath:BAAALAAECggIBwABLAAECggIEgAEAAAAAA==.Bloodsaw:BAAALAADCggIEAABLAAECggIMAADAOEXAA==.Bluuh:BAAALAADCgcIDQAAAA==.',Bo='Bokenroder:BAAALAAECgMICQAAAA==.Botulist:BAAALAADCggICgAAAA==.Boíndil:BAAALAADCggICAAAAA==.',Br='Braruk:BAAALAAECgYIEAAAAA==.Braveheart:BAABLAAECoEUAAIJAAcIYxfJbwDaAQAJAAcIYxfJbwDaAQAAAA==.Brendra:BAAALAAECgUIDAAAAA==.Bruzagg:BAAALAADCggIDQAAAA==.',Bu='Bulltrok:BAAALAAECgIIAgAAAA==.Bummelz:BAAALAAECgQIBAABLAAECgcIFAAKAEEUAA==.',Ca='Caedos:BAABLAAECoEVAAIBAAYIyBL2kgBzAQABAAYIyBL2kgBzAQAAAA==.Calico:BAAALAADCgcIDgAAAA==.Carmody:BAAALAAECgYIBgAAAA==.Castìel:BAAALAADCgYIBQABLAAECgYIEAAEAAAAAA==.',Ce='Cellestin:BAAALAAECgcIEwABLAAECggICAAEAAAAAA==.',Ch='Chantîcô:BAAALAADCggICAAAAA==.Chay:BAAALAADCggICAAAAA==.Chicoree:BAAALAAECgYIDQAAAA==.Chih:BAAALAAECgMICQAAAA==.Chiropax:BAAALAAECgMIBAAAAA==.Chiy:BAABLAAECoEhAAIBAAgIpRZ5YgDZAQABAAgIpRZ5YgDZAQAAAA==.',Cl='Claw:BAAALAAECgEIAQAAAA==.',Co='Cocoyoyo:BAAALAADCgYICAAAAA==.Copbot:BAAALAAECgYIBgAAAA==.Cornelius:BAAALAADCgQIBAAAAA==.',Cr='Crushy:BAABLAAECoEYAAMLAAgIxyCPCAC8AgALAAgIxyCPCAC8AgAMAAIIpxL8JAGDAAAAAA==.',Cy='Cyberhood:BAAALAAECgcIDQAAAA==.Cyrô:BAAALAAECgYICAAAAA==.',['Cé']='Cémál:BAAALAADCggICAAAAA==.',Da='Dacary:BAAALAAECgYIDwAAAA==.Dadiloo:BAAALAAECggIDgAAAA==.Daena:BAAALAAECgIIAgAAAA==.Daewae:BAAALAADCgQIBQAAAA==.Dalavar:BAABLAAECoEcAAINAAcIHiXbBQDyAgANAAcIHiXbBQDyAgAAAA==.Darmî:BAAALAADCgYIBgAAAA==.Daróck:BAAALAADCgYIBgAAAA==.',De='Deathmakesh:BAABLAAECoEqAAILAAgIwwz3HQCzAQALAAgIwwz3HQCzAQAAAA==.Debiddo:BAAALAAECgcICAAAAA==.Deepcrystal:BAABLAAECoEsAAINAAgIPBshCwB4AgANAAgIPBshCwB4AgAAAA==.',Dh='Dhdd:BAAALAADCgIIAgAAAA==.',Di='Dielusche:BAAALAADCgcIBwAAAA==.',Dk='Dkdrain:BAAALAADCgcIDQAAAA==.Dktanko:BAAALAADCgIIAgAAAA==.',Dr='Dragonstorm:BAAALAAECgQICQAAAA==.Dralikor:BAABLAAECoEhAAIMAAcI7hU/cQDeAQAMAAcI7hU/cQDeAQAAAA==.Drexi:BAAALAADCggIFwABLAAECgYIBwAEAAAAAA==.Drádán:BAAALAADCgQIBAAAAA==.',['Dâ']='Dârkbeauty:BAAALAAECgMIBAABLAAECggIDgAEAAAAAA==.',Ed='Edgelord:BAAALAADCgcICgAAAA==.',Ei='Eisenwolf:BAAALAAECgYICAAAAA==.',El='Elsch:BAAALAADCggICAAAAA==.',En='Enomines:BAAALAADCggIFwAAAA==.',Er='Eretria:BAAALAAECgMIBAAAAA==.',Es='Estraza:BAAALAADCgYIBgAAAA==.',Ey='Eyfalja:BAAALAADCggIFgAAAA==.',Ez='Ezkonopie:BAACLAAFFIEHAAIGAAMIqRIMDQDcAAAGAAMIqRIMDQDcAAAsAAQKgSIAAwYACAg+GwMYAHkCAAYACAg+GwMYAHkCAA4ABQhCHkY1ALgBAAAA.',Fa='Fanfan:BAAALAAECgQIBwAAAA==.Faya:BAAALAADCggIEQAAAA==.',Fe='Festnetz:BAAALAAECgcIDQAAAA==.Feuerteufeln:BAAALAAECgEIAQAAAA==.',Fk='Fk:BAAALAAECgYIBQABLAAECggILwAPAEEmAA==.',Fl='Fly:BAABLAAECoEqAAIBAAgIAB0kKwCNAgABAAgIAB0kKwCNAgAAAA==.',Fo='Fourevoker:BAAALAADCggIDwAAAA==.',Fr='Freeinfinity:BAAALAAECgYIBgAAAA==.',Ft='Ftmsouthgate:BAAALAAECggIBgAAAA==.',Fu='Fuegos:BAACLAAFFIEJAAIDAAIIcRDLDgCMAAADAAIIcRDLDgCMAAAsAAQKgRgAAgMACAipHBgQAIgCAAMACAipHBgQAIgCAAEsAAUUAggKAAUA2QsA.Fuying:BAAALAADCgMIAwAAAA==.',Ga='Gabriela:BAAALAAECgYICgAAAA==.Gambeero:BAABLAAECoEbAAMKAAgIHB5sCAA1AgAKAAgIHB5sCAA1AgAQAAMIRgzPNgB4AAAAAA==.Gams:BAAALAAECggICAAAAA==.Gatzi:BAABLAAECoEoAAIOAAgI+CJQCgAKAwAOAAgI+CJQCgAKAwAAAA==.',Ge='Gevostigma:BAAALAAECgUIDwAAAA==.',Gi='Gigagott:BAAALAADCggICAAAAA==.Gigakahl:BAAALAADCgMIAwAAAA==.Gimlis:BAAALAADCgEIAQABLAAECggIEAAEAAAAAA==.',Gl='Glindo:BAABLAAECoEYAAIKAAYI5RkwDgC7AQAKAAYI5RkwDgC7AQAAAA==.',Gn='Gnack:BAAALAAECggICAAAAA==.',Go='Gokuu:BAABLAAECoElAAIRAAgIXCNKDQAkAwARAAgIXCNKDQAkAwAAAA==.Goldenelf:BAAALAADCggILQAAAA==.Goldrausch:BAAALAAECgYICQAAAA==.Gollumsche:BAAALAAECgMIBgAAAA==.Gondrabur:BAABLAAECoEcAAIPAAcILxZ2JgDOAQAPAAcILxZ2JgDOAQAAAA==.Gonsi:BAAALAAECgYIDwAAAA==.Gosip:BAAALAADCggIIQAAAA==.Gottri:BAAALAAECggIDAAAAA==.',Gr='Granokk:BAAALAAECgYIBgAAAA==.Grimmlie:BAAALAAECgcIDwABLAADCggICAAEAAAAAA==.Grázzi:BAAALAADCgUIBQAAAA==.',Ha='Halibel:BAAALAAECggIEAABLAAECggIEgAEAAAAAA==.Halox:BAAALAADCgIIAgAAAA==.Hannsemann:BAABLAAECoEqAAIMAAgIpBeCUAAoAgAMAAgIpBeCUAAoAgAAAA==.Hantli:BAABLAAECoEXAAIIAAYIlCN7PAA6AgAIAAYIlCN7PAA6AgAAAA==.Hantlizwei:BAAALAADCgYIBgAAAA==.',He='Heidewizka:BAABLAAECoEXAAIOAAYINgYWYwDqAAAOAAYINgYWYwDqAAAAAA==.Hellandfire:BAAALAADCggICAAAAA==.Hellbanger:BAAALAAECggIBwAAAA==.Hellbone:BAAALAAECggICAAAAA==.Helloverheel:BAAALAAECggICgAAAA==.Hellraiser:BAAALAAECggIBQABLAAECggIEgAEAAAAAA==.Hellshami:BAAALAADCggICAAAAA==.Hephaisto:BAAALAADCggIEQAAAA==.Herci:BAAALAAECgMIAwAAAA==.Hexelillyfee:BAAALAAECgYICwAAAA==.',Hi='Higuruma:BAAALAADCgIIAgAAAA==.',Ho='Hohenhaym:BAAALAAECgUIBwAAAA==.Hohlfuss:BAAALAADCggIDQAAAA==.Hoppelbob:BAAALAAECgIIAgAAAA==.',Hy='Hyacinthe:BAAALAAECgYIBgAAAA==.Hygija:BAAALAAECgUIDgAAAA==.Hyogos:BAAALAADCggIDwAAAA==.Hyorion:BAAALAADCgcIBwAAAA==.',['Hè']='Hèlly:BAAALAAECgcIEwAAAA==.',['Hé']='Hélios:BAAALAAECgQIBQAAAA==.',['Hê']='Hêkate:BAAALAADCggICAAAAA==.',['Hî']='Hîmli:BAAALAAECgMIBAAAAA==.',['Hü']='Hürremsultan:BAAALAADCgcIBgAAAA==.',Ic='Icetea:BAAALAADCgYIBgAAAA==.Ichigø:BAAALAAECgQIBAAAAA==.',Im='Imperator:BAAALAAECggIEAAAAA==.',In='Inlitrhyl:BAAALAAECgYICQABLAAECggIBwAEAAAAAA==.',Ir='Irezzfortips:BAAALAADCgMIAwAAAA==.',Is='Ishnuala:BAAALAADCgEIAQABLAAECggILgASALQeAA==.',It='Itsablw:BAAALAADCgIIAgAAAA==.Itsaknife:BAAALAADCgUIBQAAAA==.Itsas:BAABLAAECoEbAAITAAYIaRp1GQCgAQATAAYIaRp1GQCgAQAAAA==.',Iz='Izabella:BAAALAAECgcIBwAAAA==.',Ja='Jagomo:BAAALAAECggICAAAAA==.Jamato:BAAALAAECgUIEgAAAA==.',Ji='Jindojum:BAAALAAECggICAAAAA==.',Jo='Jonura:BAAALAAECgMICAAAAA==.',Ju='Juicedragon:BAAALAADCggICAAAAA==.Jupi:BAAALAAECgYIDwAAAA==.Juvelian:BAAALAAECggIAQAAAA==.',['Já']='Jácob:BAAALAAECgQIBQAAAA==.',['Jé']='Jéwéls:BAAALAAECgMIAwAAAA==.',Ka='Kahldrogo:BAAALAADCgUIBQAAAA==.Kamaro:BAAALAAECgUIBQABLAAECgcIKgAEAAAAAQ==.Kapern:BAAALAAECgMIBQAAAA==.Karasia:BAAALAADCgYIBgAAAA==.',Ke='Kekeygenkai:BAAALAADCggICAAAAA==.',Ki='Kiffwunder:BAAALAAECggIEQAAAA==.Kiliria:BAACLAAFFIEGAAIOAAIIdR4GEwCbAAAOAAIIdR4GEwCbAAAsAAQKgSMAAw4ACAjLJIYJABQDAA4ACAjLJIYJABQDABAAAwhbFestANkAAAAA.Kimjongssio:BAAALAADCgUIBAAAAA==.Kindred:BAAALAADCgUIBQAAAA==.',Ko='Kodulf:BAAALAAECgQIAgAAAA==.Kokytos:BAAALAADCgcIBwAAAA==.Kortexandriu:BAAALAADCgQIBAABLAADCggICAAEAAAAAA==.',Kr='Kritzlfitzl:BAABLAAECoEXAAIUAAcIkAYzswAZAQAUAAcIkAYzswAZAQAAAA==.',Ky='Kyrelia:BAABLAAECoEhAAIUAAcIYhAshwBvAQAUAAcIYhAshwBvAQAAAA==.',['Kí']='Kímberly:BAAALAAECgYIBgAAAA==.',La='Labamm:BAAALAAECggICAAAAA==.Laneus:BAAALAAECgUIEgAAAA==.Laxobèral:BAAALAAECgUIDwAAAA==.',Le='Leberwurstel:BAAALAADCgcIEgAAAA==.Leiiniix:BAAALAAECgcIDwAAAA==.Leishmaniose:BAAALAADCggIHwAAAA==.Levi:BAAALAADCgcIEAAAAA==.',Li='Lifdrasil:BAAALAAECgMICgAAAA==.Lilliana:BAAALAAECgYIDAAAAA==.Lilly:BAAALAAECgYIDgAAAA==.',Ll='Llilliee:BAABLAAECoEuAAIIAAgIIQpZcgCQAQAIAAgIIQpZcgCQAQAAAA==.Lloyd:BAAALAADCgYIBgAAAA==.',Lo='Lornashore:BAAALAAECggICAABLAAECggIEgAEAAAAAA==.Lostbert:BAABLAAECoEZAAIVAAYI4BcLYACZAQAVAAYI4BcLYACZAQAAAA==.Lourdes:BAABLAAECoEbAAIWAAgI0Bl7GwABAgAWAAgI0Bl7GwABAgAAAA==.',Lu='Luculus:BAAALAADCggICAAAAA==.Lumi:BAAALAADCggIDwAAAA==.Lurchí:BAAALAADCggIEAAAAA==.',['Lá']='Lárthos:BAAALAAECgMIBAAAAA==.',['Lê']='Lêylêy:BAAALAAECggIDgAAAA==.',['Lí']='Líâra:BAAALAADCgcIBwAAAA==.',['Lî']='Lîlalay:BAAALAAECgIIAgAAAA==.',['Lú']='Lúcý:BAAALAAECgYICQAAAA==.',Ma='Machtnixx:BAAALAADCgYIBgAAAA==.Magroth:BAAALAADCgEIAQAAAA==.Magtheriton:BAAALAAECgYIDwAAAA==.Mallory:BAAALAADCgcIBwAAAA==.Manolina:BAAALAADCggICAABLAAECgYIFwAOADYGAA==.Marenes:BAAALAAECggIEAAAAA==.Marina:BAABLAAECoEfAAIBAAgInCKmEwAKAwABAAgInCKmEwAKAwAAAA==.Maróck:BAAALAADCgYIBgAAAA==.Maseltov:BAABLAAECoEnAAMXAAgIBhQ5DwDOAQAXAAcI8hM5DwDOAQAVAAgINBYEnAALAQAAAA==.Mausy:BAAALAAECgMIBAAAAA==.Mavis:BAAALAADCgYIBgAAAA==.',Me='Meina:BAAALAAECgQIBQAAAA==.Meisterwilli:BAAALAAECgYIDwAAAA==.Mementus:BAAALAADCgYIBwAAAA==.Mervo:BAAALAAECgUIBQAAAA==.',Mi='Mileyshirin:BAAALAAECgcICAAAAA==.Mint:BAAALAAECgIIAQAAAA==.Miyaky:BAAALAADCggICAABLAAECgYIEgAEAAAAAA==.',Mo='Molni:BAAALAAECggICwAAAA==.Montyr:BAAALAAECgUIDwAAAA==.Moonwalker:BAABLAAECoEUAAMWAAYIeyRWDwBsAgAWAAYIeyRWDwBsAgAYAAEIDCGDywBZAAAAAA==.Morgonia:BAAALAADCgcIBwAAAA==.Moriá:BAAALAADCggIEQAAAA==.Mottanio:BAAALAAECgYIDAAAAA==.',Mu='Muckel:BAAALAADCggICAAAAA==.Muluga:BAAALAAECgUIEgAAAA==.',My='Myrrine:BAABLAAECoEUAAMUAAYISAuxqwAoAQAUAAYISAuxqwAoAQAFAAEIAAXsvAAeAAAAAA==.',['Má']='Mároc:BAAALAAECgYIEAAAAA==.',['Mé']='Méldá:BAAALAAECgcIDQAAAA==.',['Mî']='Mîtsurî:BAAALAAECgIIAgAAAA==.',Na='Nafnif:BAAALAAECgYICgAAAA==.Narmaris:BAAALAADCggIEwAAAA==.',Ne='Nebula:BAAALAADCgQIBQAAAA==.Neiilaa:BAAALAAECgUIBQAAAA==.Nemonic:BAAALAAECgUIEgAAAA==.Nemrasil:BAAALAAECgUICQABLAAECggICwAEAAAAAA==.Nenaya:BAAALAADCggICAAAAA==.Nephelia:BAAALAAECgYIEAAAAA==.Nepice:BAAALAADCgIIAgAAAA==.',Ni='Nibelus:BAAALAAECgEIAQAAAA==.Nifnif:BAABLAAECoEjAAIHAAgIixYcGAAdAgAHAAgIixYcGAAdAgAAAA==.Nighet:BAAALAADCgcICgAAAA==.Nikkita:BAAALAAECggIEgAAAA==.Nile:BAAALAAECggICAABLAAECggIEgAEAAAAAA==.Nimueh:BAAALAAECgEIAQAAAA==.',No='Nogalf:BAABLAAECoEfAAIDAAgIUxYvHAATAgADAAgIUxYvHAATAgAAAA==.',Ny='Nyss:BAAALAADCggICAAAAA==.Nyssa:BAAALAADCgYIBQAAAA==.',['Nî']='Nîaza:BAAALAAECgYIEAAAAA==.',Ob='Oblivíana:BAAALAAECggIBAAAAA==.',Og='Ogni:BAABLAAECoEtAAIZAAgIchSCMwASAgAZAAgIchSCMwASAgAAAA==.',Ok='Ok:BAAALAAECggIEAAAAA==.',Ol='Ollen:BAAALAADCgQIBAAAAA==.Ollivänder:BAAALAADCgYICQAAAA==.',Or='Orcshaman:BAAALAAECggIDQAAAA==.Orthega:BAAALAAECgIIAQAAAA==.',Os='Oskar:BAAALAADCgcIBwAAAA==.',Ot='Otternase:BAAALAAECgYICAAAAA==.',Oz='Ozzy:BAAALAAECggIBwAAAA==.',Pa='Padee:BAABLAAECoElAAIMAAgIDBTKZAD4AQAMAAgIDBTKZAD4AQAAAA==.Painskill:BAAALAADCggIFwAAAA==.Pakara:BAAALAADCggICAAAAA==.Pandalia:BAAALAAECgYIDgAAAA==.Pandapolo:BAAALAADCgcIBwAAAA==.Patze:BAAALAAECgMICAAAAA==.',Pe='Pevíl:BAAALAAECgUICQAAAA==.',Pi='Piotess:BAAALAAECggIEwAAAA==.',Pl='Plinko:BAAALAADCgYICgAAAA==.',Po='Pochette:BAAALAAECgIIBAAAAA==.Pointe:BAAALAAECgQICQAAAA==.Pounamu:BAAALAADCgcIBwAAAA==.',Pr='Prami:BAAALAAECgMIAwAAAA==.Priestio:BAAALAADCggIHgAAAA==.Prêtra:BAAALAAECgYIBgABLAAECgcIEwAEAAAAAA==.',Py='Pynea:BAABLAAECoEeAAIaAAgI4xv/AwCnAgAaAAgI4xv/AwCnAgAAAA==.',['Pâ']='Pâhalin:BAAALAAECgcIEwAAAA==.',Qt='Qtkappa:BAABLAAECoEiAAMbAAcIeR4bFwBOAgAbAAcIeR4bFwBOAgATAAMInQ0xNQCgAAAAAA==.',Ra='Ragenor:BAAALAAECgYIDgAAAA==.Rainny:BAABLAAECoEdAAIOAAYIZhwxMADSAQAOAAYIZhwxMADSAQAAAA==.Raktes:BAAALAAECgIIAQAAAA==.',Re='Relaila:BAABLAAECoEcAAIGAAcIFxS7QgCeAQAGAAcIFxS7QgCeAQAAAA==.',Rh='Rhados:BAAALAAECgEIAQAAAA==.',Ro='Rockior:BAAALAADCgcICQABLAAECgIIBAAEAAAAAA==.',Ru='Rubinaholz:BAAALAAECgEIAQABLAAECggIDgAEAAAAAA==.',['Ró']='Róck:BAAALAADCgcIDQAAAA==.',Sa='Saltorc:BAABLAAECoEdAAIYAAYInQbBlQALAQAYAAYInQbBlQALAQAAAA==.Sandin:BAAALAADCggIDQAAAA==.Sandman:BAABLAAECoEuAAIWAAgI5yGOBQD4AgAWAAgI5yGOBQD4AgAAAA==.Sandorr:BAABLAAECoEUAAIJAAYIpwg10wAhAQAJAAYIpwg10wAhAQAAAA==.Sanifas:BAAALAADCgcICgAAAA==.Sarya:BAAALAAECgYIDQAAAA==.Satiya:BAABLAAECoEbAAMcAAcIuw4fLQCYAQAcAAcIOA4fLQCYAQAdAAEI+BILFgA9AAAAAA==.Satsujinpala:BAAALAADCggICAABLAAFFAIIAgAEAAAAAA==.',Sc='Schamanqt:BAAALAAECgIIAgAAAA==.Schenkwart:BAABLAAECoEpAAIeAAgIdSSMBAAZAwAeAAgIdSSMBAAZAwAAAA==.Schmeterlîng:BAAALAAECggICAAAAA==.Schämray:BAAALAAECgYICQABLAAECgcIEwAEAAAAAA==.',Se='Seasmoke:BAABLAAECoEpAAQdAAgIsB/qAgCtAgAdAAgIFB/qAgCtAgAcAAgIQRu0FgBYAgAfAAQISRCRKADWAAAAAA==.Seipe:BAAALAAECgIIAgAAAA==.Seleén:BAABLAAECoEgAAIUAAgI/R0hRQAQAgAUAAgI/R0hRQAQAgAAAA==.Sendora:BAAALAAECgQICQAAAA==.Septemí:BAAALAAECggICAAAAA==.Sethrali:BAAALAAECgIIAgAAAA==.',Sh='Shirob:BAAALAAECgUIBQAAAA==.Shiroon:BAAALAADCggIGAAAAA==.Shivalinga:BAABLAAECoEXAAIYAAcI2ApPbgB1AQAYAAcI2ApPbgB1AQAAAA==.Shizius:BAAALAADCgcIBwAAAA==.Shorio:BAAALAADCggICAAAAA==.',Si='Sihanutee:BAAALAADCgMIAwAAAA==.Simantis:BAAALAADCggICAAAAA==.Sinko:BAAALAADCgcIBwAAAA==.',Sk='Skibidirizz:BAABLAAECoEYAAIIAAgIgA7OVADmAQAIAAgIgA7OVADmAQAAAA==.Skye:BAAALAAECgcIEgAAAA==.',Sl='Slayn:BAAALAAECgYIEQAAAA==.',Sm='Smirre:BAAALAAECgMIBgAAAA==.',So='Soilwork:BAAALAADCggICAABLAAECggIEgAEAAAAAA==.Soonshaiicc:BAAALAAECgYIBgAAAA==.Soraja:BAABLAAECoEcAAIgAAcIZRPkDACnAQAgAAcIZRPkDACnAQAAAA==.Sorcixa:BAAALAADCggICAABLAAECggIBwAEAAAAAA==.Soulbladez:BAAALAAECgUICwAAAA==.South:BAAALAAECgYIEwAAAA==.',Sp='Spargit:BAAALAAECgEIAQABLAAECggIDgAEAAAAAA==.Spliffwunder:BAAALAAECggICAAAAA==.',St='Steinhammer:BAABLAAECoEYAAIJAAcIGA9VkACbAQAJAAcIGA9VkACbAQAAAA==.Stonye:BAAALAAECgYIBgABLAAECggILgARADMmAA==.',Su='Suguru:BAAALAAECgYIBwAAAA==.Suleiká:BAAALAAECgEIAQAAAA==.',Sv='Svanja:BAAALAAECggICQAAAA==.',Sy='Syrénne:BAAALAAECgYIEgAAAA==.',Sz='Szull:BAAALAAECggIBwAAAA==.',['Sá']='Sáhirá:BAAALAAECgQICwAAAA==.Sáphira:BAAALAADCggIDwAAAA==.',['Só']='Sómbra:BAAALAAECgMIAwABLAAECggICwAEAAAAAA==.',['Sô']='Sôphy:BAAALAAECgMIBAAAAA==.',Ta='Tajaa:BAAALAAECggICAAAAA==.Tanaîel:BAABLAAECoEuAAIRAAgIMyZfBABpAwARAAgIMyZfBABpAwAAAA==.Tarkos:BAAALAAECgEIAQABLAADCggICAAEAAAAAA==.Taurii:BAAALAAECggIDQAAAA==.Tayrinerrá:BAAALAADCggIDwAAAA==.',Te='Technomickel:BAAALAADCgEIAQAAAA==.Teemonk:BAAALAADCgEIAQAAAA==.Teschewe:BAAALAAECgYIDwAAAA==.Tesslla:BAAALAAECgYIEQAAAA==.Tessup:BAABLAAECoEWAAMZAAcIbR06LQA0AgAZAAcIbR06LQA0AgAVAAEIKgYNFgEiAAABLAAECggIGAALAMcgAA==.',Th='Thamína:BAAALAAECgUIEgAAAA==.Thibbeldorf:BAAALAAECgYICwAAAA==.Thilde:BAAALAADCggIFgAAAA==.Thraxon:BAAALAAECgQICQAAAA==.',Ti='Tilamera:BAAALAADCgcIBwAAAA==.Tison:BAABLAAECoEVAAMhAAUInB0bOQC9AQAhAAUInB0bOQC9AQASAAMIYhs4ewDdAAAAAA==.',To='Toji:BAAALAADCgMIAwAAAA==.Totemlady:BAAALAADCggICAABLAAECggIDgAEAAAAAA==.',Tr='Traillies:BAAALAADCgEIAQAAAA==.Trizzl:BAABLAAECoEZAAIGAAgImCUUAQBxAwAGAAgImCUUAQBxAwAAAA==.Troublemaker:BAAALAAECgEIAQAAAA==.',Tu='Tullamoor:BAAALAADCgIIAgAAAA==.Tuvilock:BAAALAAECgcIBwABLAAECggILgASALQeAA==.Tuvimage:BAAALAADCggICAABLAAECggILgASALQeAA==.Tuvipriest:BAABLAAECoEuAAMSAAgItB73FQCgAgASAAgItB73FQCgAgAhAAIICx57cQCeAAAAAA==.Tuviwar:BAAALAADCggIEAABLAAECggILgASALQeAA==.',Tw='Twik:BAAALAAECgYIDwAAAA==.',Ty='Tyricon:BAAALAAECggIEgAAAA==.Tyræl:BAAALAAECgMIAwAAAA==.',['Té']='Ténhjo:BAAALAAECgMIBQAAAA==.',['Tí']='Tíger:BAAALAADCgUIBgAAAA==.',Un='Uniusr:BAABLAAECoEfAAMTAAcI3RgqEwDnAQATAAYI8hwqEwDnAQAiAAYIlgX8DwAsAQABLAADCggICAAEAAAAAA==.',Va='Vaeragosa:BAAALAAECgYIEAAAAA==.Vaylha:BAAALAADCggICAAAAA==.Vaélin:BAABLAAECoEcAAIHAAcI8xeMGwD4AQAHAAcI8xeMGwD4AQAAAA==.',Ve='Veiðikona:BAAALAADCggICAAAAA==.Vermíthor:BAAALAADCgEIAQAAAA==.',Vi='Visandre:BAAALAAECgEIAwAAAA==.Vitaljus:BAAALAAECgEIAQAAAA==.',Vo='Vonotah:BAAALAAECgUIBQAAAA==.',Vu='Vulnaria:BAAALAADCgUICAAAAA==.',Vy='Vyse:BAAALAAECgEIAgAAAA==.',['Vô']='Vôldemort:BAAALAADCgcIBwABLAAECgYIDgAEAAAAAA==.',We='Weihbär:BAAALAADCgYIBgAAAA==.Wesson:BAAALAAECgUIEQAAAA==.',Wh='Whitelady:BAAALAADCggIDwAAAA==.',Wo='Woofi:BAABLAAECoEoAAIFAAgImx73EwCyAgAFAAgImx73EwCyAgAAAA==.Woolee:BAAALAADCgUIBQABLAAECgMIBAAEAAAAAA==.',Xa='Xantus:BAAALAADCggICAAAAA==.Xavalon:BAAALAAECgMIBAAAAA==.',Xe='Xearo:BAAALAAECggIEgABLAADCggICAAEAAAAAA==.Xentô:BAAALAADCgcIEQAAAA==.Xeras:BAAALAAECgEIAQAAAQ==.Xerxi:BAAALAADCggICgABLAAECgYIBwAEAAAAAA==.Xerxibm:BAAALAADCggICAABLAAECgYIBwAEAAAAAA==.Xerxidud:BAAALAAECgYIBgABLAAECgYIBwAEAAAAAA==.Xerximist:BAAALAADCgMIAwABLAAECgYIBwAEAAAAAA==.Xerxisham:BAAALAAECgMIBAABLAAECgYIBwAEAAAAAA==.Xerxí:BAAALAAECgYIBwAAAA==.',Xo='Xokuk:BAAALAADCgQIBAAAAA==.',Ya='Yangci:BAAALAADCggICAAAAA==.',Yb='Ybera:BAAALAAECgMIBQABLAAECggIHgAaAOMbAA==.',Yl='Ylara:BAAALAADCgQIBgAAAA==.',Yo='Yongsun:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.',Yu='Yulissa:BAAALAADCgYIDwAAAA==.Yumz:BAAALAAECgEIAQAAAA==.',['Yê']='Yês:BAAALAADCggICAAAAA==.',Za='Zaknefain:BAAALAADCgUIBQAAAA==.',Zb='Zbo:BAAALAAECgMIAwAAAA==.',Ze='Zelador:BAABLAAECoEVAAIJAAYITxzqbADgAQAJAAYITxzqbADgAQAAAA==.Zeldas:BAAALAAECgYICwAAAA==.Zephyr:BAAALAAECgYIDgAAAA==.Zephyrios:BAABLAAECoEXAAIRAAYI8xiMUwC/AQARAAYI8xiMUwC/AQAAAA==.Zesty:BAABLAAECoErAAMjAAgIhiOuBAAiAwAjAAgIhiOuBAAiAwAJAAEIyCEAAAAAAAAAAA==.Zeyphir:BAAALAADCggICAABLAAECgYIFAAUAEgLAA==.',Zh='Zhuge:BAAALAADCggIDwABLAAFFAIIAgAEAAAAAA==.',Zi='Zitrone:BAAALAADCggICgAAAA==.',Zo='Zoulou:BAAALAADCgcIBwAAAA==.Zozoria:BAAALAAECgYIDAAAAA==.',Zy='Zyldjian:BAAALAADCggIIAAAAA==.Zylium:BAAALAAECggIEAAAAA==.',['Zý']='Zýal:BAABLAAECoEvAAIPAAgIQSY8AQB5AwAPAAgIQSY8AQB5AwAAAA==.',['Äl']='Älain:BAAALAADCgcIDwAAAA==.',['Äo']='Äonen:BAAALAAECgUIBwAAAA==.',['Îô']='Îônîâ:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end