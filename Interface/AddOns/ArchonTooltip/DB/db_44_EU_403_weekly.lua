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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Protection','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Priest-Holy','Druid-Restoration','Shaman-Elemental','Hunter-BeastMastery','Warrior-Protection','Evoker-Devastation','Druid-Feral','Warlock-Demonology','Warrior-Fury','Mage-Frost','Hunter-Marksmanship','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','Mage-Fire','DeathKnight-Blood','Warrior-Arms','Monk-Windwalker','Monk-Mistweaver','Paladin-Holy','Shaman-Enhancement','Evoker-Preservation','Druid-Balance','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Druid-Guardian','Priest-Shadow','DemonHunter-Vengeance','Rogue-Assassination',}; local provider = {region='EU',realm='Arygos',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adhs:BAAALAADCggICAABLAAECgQIDwABAAAAAA==.',Ae='Aelor:BAABLAAECoEVAAMCAAgIAyB1HgDbAgACAAgIAyB1HgDbAgADAAEIbxbjYQAqAAAAAA==.',Ag='Aganubon:BAAALAAECgUIBwAAAA==.Aguares:BAAALAAECggICAAAAA==.',Ai='Ainarios:BAAALAADCgYIBwABLAAECgYIDwABAAAAAA==.',Ak='Aka:BAACLAAFFIENAAMEAAUIZhU7BAAZAQAEAAMI0Bc7BAAZAQAFAAMIrBB7GQDqAAAsAAQKgScAAwQACAieI8cWAPIBAAQABQj5I8cWAPIBAAUABwgBFyZ3ANMBAAAA.Akø:BAAALAADCggICAAAAA==.',Al='Alafia:BAAALAAECgUIBQAAAA==.Alaskatraz:BAAALAAECgYIDgAAAA==.Albêdo:BAAALAADCgMIAwABLAAECgcIHAAGAOYZAA==.Aleke:BAAALAAECgYICwAAAA==.Aliaa:BAABLAAECoEbAAIHAAcICQthVwBWAQAHAAcICQthVwBWAQAAAA==.Almerias:BAAALAAECgMIAwAAAA==.Alpa:BAAALAAECgQIBAAAAA==.Alric:BAABLAAECoEVAAIIAAYIRxKDVgBTAQAIAAYIRxKDVgBTAQAAAA==.Althyn:BAAALAADCggICAAAAA==.Aluna:BAAALAAECgMIAwAAAA==.Alvari:BAAALAAECgQIBwAAAA==.',Am='Amalaswintha:BAABLAAECoEXAAIJAAcIpxYSOwDvAQAJAAcIpxYSOwDvAQAAAA==.Amaree:BAAALAADCgEIAQAAAA==.Amayai:BAAALAAECgYIDQABLAAECggIIwAKAIggAA==.',An='Anesturia:BAAALAAECgYICwAAAA==.Angmida:BAAALAADCgQIBAAAAA==.Anoxa:BAAALAADCgcICwABLAAFFAIIAgABAAAAAA==.',Ao='Aority:BAAALAADCgEIAQAAAA==.',Ar='Aribêth:BAAALAAECgYIDwAAAA==.Artimes:BAAALAAECgcIBwAAAA==.',As='Ascendra:BAAALAADCgEIAQABLAAECgcIHgALAC4eAA==.Astraanar:BAAALAAECgYIEQAAAA==.',Au='Autnoob:BAAALAAECggICAAAAA==.Auwehmeinzeh:BAAALAADCggICAABLAADCggICAABAAAAAA==.Auxo:BAAALAADCgYIDwAAAA==.',Av='Avelie:BAAALAAECgMICgAAAA==.',Az='Azel:BAAALAAECggICAAAAA==.Azzinóth:BAAALAAECgYIDgABLAAECggIOwAMAGkhAA==.Azzuro:BAAALAADCggIHQAAAA==.',['Aä']='Aäfk:BAAALAADCgMIAwAAAA==.',Ba='Badbones:BAAALAADCgYIBgABLAAECgcIKQANAMUcAA==.Baela:BAAALAADCggICAAAAA==.Balîndys:BAAALAAECgYIEQAAAA==.Bambî:BAAALAAECggICAAAAA==.Bansenvonnod:BAAALAADCggICQAAAA==.Baphuon:BAABLAAECoEkAAIOAAgIoRzzCQCtAgAOAAgIoRzzCQCtAgAAAA==.Bartakus:BAABLAAECoEVAAMPAAYIpQxZeQBSAQAPAAYIhQxZeQBSAQALAAEI3hIHeAA2AAAAAA==.',Be='Beaux:BAABLAAECoEUAAIMAAYI9QMfSADVAAAMAAYI9QMfSADVAAAAAA==.Beernator:BAAALAADCggIEQAAAA==.Bellamía:BAAALAAECggICAAAAA==.Bellasopie:BAAALAAECgQIBgAAAA==.',Bi='Biiduubiiduu:BAAALAADCgEIAQABLAAECgYIEgAOAAIZAA==.Biorach:BAAALAADCgcICwAAAA==.',Bl='Blackzora:BAABLAAECoEcAAIKAAcInB2ANQBGAgAKAAcInB2ANQBGAgAAAA==.Blitzknubbel:BAAALAAECggIBAAAAA==.Blueray:BAABLAAECoEVAAINAAYIPA0VIwBMAQANAAYIPA0VIwBMAQAAAA==.Blóom:BAACLAAFFIEIAAIQAAQIygVRAwAIAQAQAAQIygVRAwAIAQAsAAQKgRgAAxAACAhOGxkRAHwCABAACAhOGxkRAHwCAAYAAghUCOTUAE4AAAAA.',Bo='Boomiie:BAAALAAECggIDAAAAA==.Bosspeter:BAAALAAECggICAAAAA==.',Br='Brautt:BAAALAADCggICAAAAA==.Browíllis:BAAALAAECggICAAAAA==.',Bu='Bualie:BAABLAAECoEfAAIRAAYIDCHjLAD+AQARAAYIDCHjLAD+AQAAAA==.Buggtide:BAAALAADCgYIBgAAAA==.Bullwalker:BAAALAAECgEIAQAAAA==.Bunbo:BAAALAADCgUIBQAAAA==.Butterbart:BAAALAAECgYIEgAAAA==.',Bz='Bzztbzzt:BAABLAAECoEnAAIJAAgI1xZ5LAA4AgAJAAgI1xZ5LAA4AgAAAA==.',['Bä']='Bärchénn:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',['Bå']='Bådlock:BAAALAAECgEIAQAAAA==.',['Bè']='Bènder:BAAALAAECgQIBgAAAA==.',['Bí']='Bísam:BAABLAAECoEoAAMSAAgIIxtXBQB0AgASAAgIIxtXBQB0AgATAAEI2gb14AApAAAAAA==.',['Bù']='Bùfù:BAAALAADCggICAAAAA==.',Ca='Cagliosttro:BAAALAAECgYIDgABLAAECggIFgARALMXAA==.Caidana:BAAALAAECgYIBgABLAAECggIHQAOAKMaAA==.Calísra:BAAALAAECggICAAAAA==.Cardrill:BAAALAAECgQIBgAAAA==.Cartharra:BAAALAAECgYIEgAAAA==.Casjopaya:BAAALAADCgcIEwAAAA==.Catori:BAACLAAFFIEIAAIUAAIIACClGwCyAAAUAAIIACClGwCyAAAsAAQKgRQAAhQABghPJG8sAD0CABQABghPJG8sAD0CAAAA.Catthebest:BAAALAADCgQIBAAAAA==.Catweesel:BAAALAADCggIFQAAAA==.',Ce='Celiah:BAABLAAECoEYAAMOAAcIRiD/LwCOAQAOAAcIRiD/LwCOAQATAAIIZA8JwAB6AAAAAA==.',Ch='Chaotik:BAAALAADCgYICAAAAA==.Charell:BAAALAAECggICAAAAA==.Charina:BAAALAAECgIIAgAAAA==.Charlu:BAAALAAECgQIBQAAAA==.Cheynestoke:BAAALAAECgYIEQAAAA==.Chiv:BAAALAAECgYICQAAAA==.Choor:BAAALAADCggICAAAAA==.Chucky:BAAALAADCgQIBAAAAA==.',Ci='Cinderrella:BAABLAAECoEdAAIVAAgI6xn8AgCPAgAVAAgI6xn8AgCPAgAAAA==.',Co='Codon:BAAALAAECgQIBAAAAA==.Conina:BAAALAAECgQICwAAAA==.Console:BAAALAAECggIEAAAAA==.Coriona:BAABLAAECoEkAAIHAAgIeAn9TgB2AQAHAAgIeAn9TgB2AQAAAA==.Corristo:BAAALAAECgYIEAAAAA==.',Cu='Curlos:BAAALAAFFAIIAgAAAA==.',Cy='Cyría:BAAALAADCgQIBAAAAA==.',['Câ']='Câtaléya:BAAALAADCggICAAAAA==.',['Cé']='Cénaríus:BAAALAADCggICAAAAA==.',['Cí']='Círí:BAABLAAECoEVAAIUAAYIAhu6TQDMAQAUAAYIAhu6TQDMAQAAAA==.',Da='Dabumms:BAAALAAFFAIIAgABLAAFFAMICAAHAFMhAA==.Dagolad:BAAALAADCgcIBwAAAA==.Daktos:BAAALAADCggICwABLAAECgIIAgABAAAAAA==.Daméé:BAAALAAECgUIBgAAAA==.Darkdamien:BAAALAAECgIIAgAAAA==.Darkmarko:BAAALAAECgEIAQAAAA==.',De='Deathiras:BAAALAAECgYIDQAAAA==.Deathrocky:BAAALAADCgQIBAAAAA==.Delicious:BAAALAAECggIBgAAAA==.Delphino:BAAALAADCgcIEwAAAA==.Detor:BAAALAAECgQIDAAAAA==.Devokerz:BAAALAAECgcIBwAAAA==.',Di='Dibster:BAAALAADCgQIBAABLAAECgcIHgALAC4eAA==.Dirk:BAAALAAECgQIBwAAAA==.Dirtybash:BAABLAAECoEXAAMKAAYIwRtdYADFAQAKAAYIbRtdYADFAQARAAMIFxaLfgC5AAAAAA==.Dishia:BAAALAADCgMIAwAAAA==.',Dk='Dk:BAABLAAECoEeAAMFAAcI4SD3LgCQAgAFAAcI4SD3LgCQAgAWAAYIJRzbKQDlAAAAAA==.',Do='Dokarion:BAABLAAECoEiAAIIAAgI9RzOFwB6AgAIAAgI9RzOFwB6AgAAAA==.',Dr='Drachenzorn:BAAALAADCgEIAQAAAA==.Dragonator:BAAALAAECgEIAQAAAA==.Dragonbane:BAAALAADCggIEwAAAA==.Dreamfyre:BAAALAAECgYIDgAAAA==.Dreddy:BAAALAAECgYIBgABLAAFFAUICgATABYZAA==.Dreek:BAAALAADCggIEwABLAAECgEIAQABAAAAAA==.Dreihandaxt:BAACLAAFFIEKAAICAAUI5hImBgCxAQACAAUI5hImBgCxAQAsAAQKgScAAgIACAjXJGYOADEDAAIACAjXJGYOADEDAAAA.Drias:BAABLAAECoEVAAIQAAcI+hLcKgCyAQAQAAcI+hLcKgCyAQAAAA==.Drinknblink:BAAALAADCgEIAQAAAA==.Drugsbunny:BAAALAAECgEIAQAAAA==.Drááver:BAAALAAECgcIAwABLAAECggICAABAAAAAA==.',Du='Duduelf:BAAALAAECgYIBgAAAA==.Dudujazz:BAAALAADCgcIFAAAAA==.Dumbledormu:BAAALAAECggIDwAAAA==.',Dw='Dwarusch:BAABLAAECoEfAAIXAAcI/hfCEACnAQAXAAcI/hfCEACnAQAAAA==.',['Dá']='Dádá:BAAALAAECgcIEgAAAA==.',['Dä']='Dämoni:BAAALAAECggIEgAAAA==.',Eb='Eberrippchen:BAABLAAECoEjAAIEAAgIMR8YCwCMAgAEAAgIMR8YCwCMAgAAAA==.',Ec='Echsenecki:BAAALAAECggIEAABLAAFFAUICgAJAJEPAA==.Echsenmann:BAAALAAECgMIAwAAAA==.',Ef='Efeel:BAAALAAECgYIEQAAAA==.',Eg='Egaleddi:BAAALAAECggIEAAAAA==.',El='Elaisa:BAACLAAFFIEIAAIIAAIIhRM5HgCPAAAIAAIIhRM5HgCPAAAsAAQKgSoAAggACAiWG3QaAGgCAAgACAiWG3QaAGgCAAAA.Elisina:BAAALAADCggIDwAAAA==.Ellie:BAAALAAECgQIBgAAAA==.Eltika:BAAALAAECgMIBQAAAA==.Elymas:BAABLAAECoEcAAMOAAYI/xyOHAD5AQAOAAYI/xyOHAD5AQATAAEIkhSj0ABJAAAAAA==.',Em='Emix:BAAALAAECggIEwAAAA==.Emmea:BAAALAAECgMIBgAAAA==.',En='Endgame:BAAALAAECgYIDwAAAA==.Energon:BAAALAADCgYIDQAAAA==.Ennox:BAABLAAECoEXAAIPAAYIcQzieABTAQAPAAYIcQzieABTAQAAAA==.Enyâ:BAABLAAECoEoAAILAAgIPRG5NgBsAQALAAgIPRG5NgBsAQAAAA==.',Er='Erleuchtung:BAABLAAECoEVAAMCAAcI8B3jTAAsAgACAAcInRzjTAAsAgADAAYIixUdKACAAQAAAA==.Erâdyâs:BAAALAADCgcIFgABLAAECgYICwABAAAAAA==.Erêk:BAAALAADCggICAAAAA==.',Es='Essy:BAAALAADCggICAAAAA==.',Eu='Eutrasusrex:BAAALAADCgcIDgAAAA==.',Ev='Evángéliné:BAAALAAECgEIAQAAAA==.',Ex='Excile:BAAALAADCggICAAAAA==.',Ez='Ezakimak:BAABLAAECoEWAAITAAcI8w3iZgCJAQATAAcI8w3iZgCJAQAAAA==.Eziioo:BAABLAAECoEYAAIEAAcI0BZ0GgDRAQAEAAcI0BZ0GgDRAQAAAA==.',Fa='Fafnis:BAABLAAECoEcAAIGAAcI5hnhRwAQAgAGAAcI5hnhRwAQAgAAAA==.Falada:BAAALAAECgIIAgABLAAECgUIDgABAAAAAA==.Farmnix:BAAALAADCggICAAAAA==.Fayaris:BAAALAAECgUIDgAAAA==.Fayrin:BAAALAADCgcIBwABLAAECgUIDgABAAAAAA==.',Fe='Feight:BAABLAAECoEUAAIHAAYI6BipPwC0AQAHAAYI6BipPwC0AQAAAA==.Felgrim:BAABLAAECoEeAAMTAAcI8BmlPgAQAgATAAcI8BmlPgAQAgAOAAIIUwtfeABfAAAAAA==.Feltality:BAAALAAECggIEAAAAA==.Felun:BAABLAAECoEaAAIYAAgIaRl9FABGAgAYAAgIaRl9FABGAgAAAA==.Felín:BAABLAAECoEVAAIZAAgIexRFFQD4AQAZAAgIexRFFQD4AQABLAAECggIGgAYAGkZAA==.Femorka:BAAALAAECgYIEgAAAA==.Feuerkachel:BAAALAAECgYICwAAAA==.',Fi='Filrakuna:BAAALAADCgYIBgAAAA==.Finduz:BAABLAAECoEWAAIMAAgI6iDUFQBhAgAMAAgI6iDUFQBhAgAAAA==.Fireflint:BAABLAAECoEYAAMCAAcIkSA0MQCFAgACAAcIkSA0MQCFAgAaAAIIrxkKVwCUAAAAAA==.Firefly:BAAALAAECgEIAQAAAA==.',Fl='Fluffyna:BAAALAAECggIBgAAAA==.Flòwérpòwér:BAAALAADCgYIBgAAAA==.',Fr='Friedjín:BAABLAAECoEYAAIbAAgIWh9bBADTAgAbAAgIWh9bBADTAgAAAA==.Frubart:BAAALAADCgQIBAABLAAECgYICwABAAAAAA==.Fructi:BAAALAAECgYIEQAAAA==.',Fu='Fummlerin:BAAALAADCgcIDAAAAA==.Furorion:BAABLAAECoE7AAMMAAgIaSFfCQD4AgAMAAgIaSFfCQD4AgAcAAUIEg82IwAOAQAAAA==.Fururion:BAAALAADCggIJAAAAA==.Fushigi:BAAALAAECgEIAQAAAA==.Fuyugá:BAABLAAECoEiAAIbAAgI3RvyBwBqAgAbAAgI3RvyBwBqAgAAAA==.',['Fî']='Fîa:BAAALAADCggIDgABLAAECggICQABAAAAAA==.',Ga='Gafludi:BAAALAAECgYIDQAAAA==.Gartogg:BAAALAAECgYIEgAAAA==.Garviel:BAAALAADCggICwAAAA==.Gazebolein:BAAALAAECggICAAAAA==.',Ge='Gehhem:BAAALAAECgEIAQAAAA==.Gerard:BAAALAADCggICAAAAA==.',Gl='Glandahl:BAAALAAECgQIDQAAAA==.Globorg:BAABLAAECoEeAAIPAAcIHxG4WACuAQAPAAcIHxG4WACuAQAAAA==.Glühbirne:BAAALAAECgYIEgAAAA==.',Go='Goibniu:BAAALAADCggICAAAAA==.Goju:BAAALAAECgIIAgAAAA==.Goldfielder:BAAALAADCgcICwAAAA==.Goldíe:BAAALAAECgIIAgAAAA==.Goliat:BAAALAADCggICAAAAA==.Goralax:BAAALAAECgQIBAABLAAECgYICwABAAAAAA==.',Gr='Grotzog:BAAALAADCgIIAgAAAA==.Growler:BAAALAADCggICAAAAA==.Grubel:BAAALAAECggICAAAAA==.Grómbârt:BAAALAAECgYICAAAAA==.',['Gô']='Gôrlôsch:BAAALAADCgIIAgABLAAECgYICwABAAAAAA==.',['Gö']='Gönndalf:BAAALAADCgQIBAAAAA==.Göpe:BAACLAAFFIEJAAIdAAQI+R5ZBgBvAQAdAAQI+R5ZBgBvAQAsAAQKgSYAAh0ACAiwJVgGADwDAB0ACAiwJVgGADwDAAAA.',['Gú']='Gúltiriá:BAAALAAECgYIBgABLAAECgYICwABAAAAAA==.',Ha='Hamptidamti:BAAALAADCgcIEAAAAA==.Handmixer:BAABLAAECoEWAAMYAAgIyxKzIwCxAQAYAAcIHhOzIwCxAQAeAAMIZg7nNACcAAAAAA==.Hanei:BAABLAAECoEjAAIKAAgIiCC0FADoAgAKAAgIiCC0FADoAgAAAA==.Hardthor:BAAALAAECggICwAAAA==.Harryhoff:BAABLAAECoEfAAIKAAgIVx/KOQA3AgAKAAgIVx/KOQA3AgAAAA==.Haunei:BAAALAADCggIEAAAAA==.Haybow:BAAALAAECgQIBgAAAA==.Hazesa:BAAALAADCgcIDgAAAA==.Hazè:BAAALAAECgIIAgAAAA==.',He='Healbilly:BAAALAADCggIEAAAAA==.Helgê:BAAALAAECgMIBAAAAA==.Hellgrazer:BAAALAADCgMIAwAAAA==.Herminator:BAAALAADCgcIEwAAAA==.Heslo:BAAALAADCgcICQAAAA==.',Ho='Holyshlt:BAAALAADCggIDQAAAA==.Honeyhoff:BAABLAAECoEqAAIOAAgI7yRPBQD9AgAOAAgI7yRPBQD9AgAAAA==.Horgata:BAAALAADCgcIEwAAAA==.',Hu='Huntinghero:BAAALAADCgQIBwAAAA==.Huurga:BAAALAADCggIKgAAAA==.',['Há']='Hálfar:BAABLAAECoEeAAMCAAgItSFVMQCFAgACAAgItSFVMQCFAgADAAIIFRa1WQBJAAAAAA==.',['Hè']='Hèllsbèlls:BAAALAADCgYIBgAAAA==.',['Hô']='Hôrstt:BAAALAADCgcIBwAAAA==.',Ic='Ichmagblumen:BAAALAADCgQIAwABLAAECggIGgACAD0hAA==.',Ig='Igerus:BAAALAAECgcIDQAAAA==.',Il='Illumzar:BAAALAADCgcIDQAAAA==.',Im='Imigran:BAAALAAECgMICAAAAA==.',In='Inadequate:BAABLAAECoEdAAICAAYI5RS4pQB1AQACAAYI5RS4pQB1AQAAAA==.Inaira:BAAALAAECgYIDgABLAAFFAUICwATAJQPAA==.Ingbar:BAAALAAECgYIEgAAAA==.Injuria:BAACLAAFFIEKAAIJAAUI3hHQCACaAQAJAAUI3hHQCACaAQAsAAQKgR8AAgkACAjwHgQbAKYCAAkACAjwHgQbAKYCAAAA.Inzendia:BAAALAAECggICAAAAA==.Início:BAAALAADCggICAAAAA==.',Ir='Ironhite:BAAALAADCgcIDgAAAA==.',Iv='Ivraviel:BAACLAAFFIEKAAIUAAMISSOyCQA4AQAUAAMISSOyCQA4AQAsAAQKgSUAAhQACAg5G44hAGwCABQACAg5G44hAGwCAAAA.Ivóny:BAAALAAECggIDQAAAA==.',Iz='Izzaria:BAAALAAECgEIAQABLAAFFAUICwATAJQPAA==.',Ja='Jacat:BAAALAAECgQIDwAAAA==.Jagana:BAAALAAECgYIDgAAAA==.',Je='Jenolix:BAAALAADCgcIBwAAAA==.Jess:BAAALAADCgQIBAAAAA==.',Ji='Jiani:BAAALAAECgMICgAAAA==.',Jo='Johta:BAAALAAECgIIAgAAAA==.Jokerbabe:BAAALAADCggIDwAAAA==.Jomaro:BAAALAAECgUIBwAAAA==.',Jr='Jrpepa:BAAALAADCggICAAAAA==.',Ju='Juster:BAAALAAECgMIAwAAAA==.',['Jä']='Jägernus:BAAALAADCgQIBAAAAA==.',['Jú']='Júsy:BAAALAAECgIIAgAAAA==.',['Jû']='Jûdasprîest:BAAALAADCgUIBQABLAAECgYIHAAOAP8cAA==.Jûster:BAAALAADCgUIBQAAAA==.',Ka='Kaatschauu:BAAALAADCgUIBQAAAA==.Kajusha:BAABLAAECoEUAAIGAAcIHAlahABhAQAGAAcIHAlahABhAQAAAA==.Kammí:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Kasat:BAAALAAECgEIAQAAAA==.Kassiphone:BAAALAADCggIIgAAAA==.Kasuto:BAAALAAECggIBAAAAA==.Katargo:BAAALAADCggIDwAAAA==.Katsaa:BAAALAAFFAIIAgABLAAFFAUIEQATAH8WAA==.Kay:BAABLAAECoEpAAMTAAgIZyCKGgDMAgATAAgIZyCKGgDMAgASAAEI7xXTNgBFAAAAAA==.Kayorus:BAAALAAECgYIEQAAAA==.',Ke='Keenreevs:BAABLAAECoEiAAIfAAgIUx5ZNgBdAgAfAAgIUx5ZNgBdAgAAAA==.Keksschmiedê:BAAALAADCgUICwAAAA==.Kelnarzul:BAACLAAFFIELAAITAAUIlA+ODQCVAQATAAUIlA+ODQCVAQAsAAQKgScAAhMACAhIIe4XANwCABMACAhIIe4XANwCAAAA.Kezo:BAABLAAECoExAAIDAAgIHRw2EQBLAgADAAgIHRw2EQBLAgAAAA==.',Kh='Kheldren:BAAALAAECggICAAAAA==.Khýrá:BAAALAAECggIEAAAAA==.',Ki='Kitinog:BAAALAADCgUIBQAAAA==.',Kl='Kleiniwi:BAAALAAECggICAAAAA==.Klophania:BAAALAAECgMIAwAAAA==.Klâkier:BAAALAAECgYIBwAAAA==.',Kn='Knopp:BAAALAADCggIEwAAAA==.Knüppeldrauf:BAAALAADCgcIEwABLAADCggICAABAAAAAA==.',Ko='Kohaku:BAAALAAECgQIDQAAAA==.',Kr='Krallamari:BAABLAAECoEWAAIKAAcIPiKdHQC0AgAKAAcIPiKdHQC0AgAAAA==.Krasota:BAAALAADCgYICwAAAA==.Krystalia:BAAALAAECgIIAgAAAA==.Krüppling:BAABLAAECoEZAAITAAcIjA+zawB8AQATAAcIjA+zawB8AQABLAAECggIJwAJANcWAA==.',Ku='Kuhbickmeter:BAAALAADCggICgAAAA==.Kuhgelblitz:BAACLAAFFIEKAAIJAAUIkQ8FCQCTAQAJAAUIkQ8FCQCTAQAsAAQKgSUAAwkACAgoIzgLACUDAAkACAgoIzgLACUDABQAAQhtBegTASQAAAAA.',Kv='Kvothiras:BAABLAAECoEvAAISAAgIayWXAABoAwASAAgIayWXAABoAwAAAA==.',Ky='Kyda:BAABLAAECoEVAAIUAAgI8xj1YACXAQAUAAgI8xj1YACXAQAAAA==.Kydd:BAAALAADCggIDwAAAA==.Kynez:BAAALAADCgcICQAAAA==.Kyø:BAACLAAFFIEKAAIGAAIIlRMsOgCSAAAGAAIIlRMsOgCSAAAsAAQKgSYAAgYACAgIH0AnAJkCAAYACAgIH0AnAJkCAAAA.',['Ká']='Káraso:BAAALAAECggICAAAAA==.',['Kâ']='Kâmikazèn:BAAALAADCggICQABLAAECgYIFAAPADEaAA==.',['Ké']='Kéndór:BAAALAADCggIBAABLAAECggIOwAMAGkhAA==.',['Kê']='Kêule:BAAALAADCgUIBQAAAA==.',['Kì']='Kìsumà:BAAALAADCgcIBwAAAA==.',La='Lagoran:BAAALAAECgEIAQAAAA==.Lanfêar:BAAALAAECgEIAQAAAA==.Laylas:BAABLAAECoEYAAICAAYI3yHjSAA3AgACAAYI3yHjSAA3AgAAAA==.',Le='Lenori:BAAALAAECgYICwAAAA==.Leoardrry:BAAALAAECgMIBQAAAA==.',Lh='Lhilia:BAAALAAECgcICAAAAA==.',Li='Liabell:BAAALAAECgYICgAAAA==.Liay:BAAALAAECgEIAQAAAA==.Lichti:BAAALAADCggICAAAAA==.Liikex:BAAALAAECgcIEgAAAA==.Lilars:BAAALAADCgcIBwAAAA==.Lillith:BAAALAAECgYICQAAAA==.Limoncella:BAAALAADCggIJgAAAA==.Lirius:BAAALAADCgcICwAAAA==.',Lo='Lockda:BAABLAAECoEeAAIIAAgIpiFrCwDlAgAIAAgIpiFrCwDlAgAAAA==.Locktide:BAAALAAECgEIAQABLAAECggIHgAIAKYhAA==.Lokna:BAAALAADCggIFQAAAA==.Loparia:BAAALAAECgQIBwAAAA==.Lorat:BAABLAAECoEbAAMLAAcIyBIQLwCXAQALAAcIyBIQLwCXAQAPAAcIzgtrbAB2AQAAAA==.Loraven:BAAALAAECggIDwAAAA==.',Lu='Lukou:BAAALAAECgYIDAAAAA==.Lunostrion:BAAALAADCgcIEQABLAAECggIIgAWAG8MAA==.',Ly='Lysandria:BAAALAAECggICAAAAA==.',['Lê']='Lêâ:BAAALAAFFAMIAgAAAA==.',['Lô']='Lôckchen:BAAALAAECgUIBQABLAAECgcIHAAdADkUAA==.',['Lû']='Lûcius:BAAALAADCgUIDQAAAA==.',Ma='Magonia:BAAALAAECgMIAwAAAA==.Majenda:BAAALAAECgQICAAAAA==.Maktorr:BAABLAAECoEcAAIFAAYIqhc5lwCYAQAFAAYIqhc5lwCYAQAAAA==.Malatus:BAAALAAECgYICAAAAA==.Malesteria:BAAALAAECgEIAQABLAAECggIJAAHAHgJAA==.Malgrimace:BAAALAAECgMIBQAAAA==.Malizz:BAAALAADCgIIAgAAAA==.Marasi:BAAALAADCgUIBQAAAA==.Maribela:BAAALAADCggIDQAAAA==.Marlôth:BAAALAADCgEIAQAAAA==.Martinika:BAAALAAECgYIEgAAAA==.',Mc='Mcdemon:BAAALAAECgIIAgAAAA==.',Me='Medon:BAAALAAECggIEwAAAA==.Megalon:BAAALAAECgQIBAAAAA==.Melapala:BAAALAADCgcIDQAAAA==.Melasculâ:BAABLAAECoEmAAQTAAgIkSOJIgCaAgATAAcIbSKJIgCaAgASAAMI4x4UGwAGAQAOAAIIySLBggBAAAAAAA==.Memphes:BAAALAAECgEIAQAAAA==.Mendrin:BAAALAAECggIDgAAAA==.Mendrion:BAAALAAECggICgAAAA==.Meranbir:BAAALAAECgIIAwAAAA==.Merile:BAAALAADCggIDAAAAA==.Merrlin:BAAALAAECgIIAgAAAA==.',Mi='Midorii:BAABLAAECoErAAIQAAgIpxoaEQB8AgAQAAgIpxoaEQB8AgAAAA==.Mieraculix:BAAALAAECgQIBAAAAA==.Mikael:BAAALAAECgYICgAAAA==.Millhaus:BAAALAADCgIIAgAAAA==.Minette:BAAALAAECgUICQAAAA==.Missbanshee:BAAALAADCgcIBwAAAA==.Missnadira:BAAALAAECggICAAAAA==.Misumi:BAAALAADCggIGAAAAA==.Miyoko:BAAALAADCggICAAAAA==.',Mo='Moonwitch:BAAALAADCgcIBwAAAA==.Mops:BAAALAADCgcIBwAAAA==.Mordsith:BAAALAAECgYICAAAAA==.Moriyama:BAAALAADCggIGAAAAA==.Morrak:BAAALAADCggIFgAAAA==.Moth:BAAALAAECggIEQAAAA==.',Mu='Muerte:BAABLAAECoEVAAICAAgIxxztKACoAgACAAgIxxztKACoAgAAAA==.Mumanz:BAAALAAECgIIBAAAAA==.Muramatsu:BAAALAADCggICgAAAA==.Murcks:BAAALAAECgYIBgAAAA==.Muzan:BAAALAAECgYIBgAAAA==.',Mx='Mxpaladin:BAABLAAECoEYAAQDAAgI8wBYZAAiAAADAAgIqwBYZAAiAAAaAAMIkACPbQAKAAACAAcIBAEAAAAAAAAAAA==.Mxpriester:BAABLAAECoEfAAMgAAgIqAGzLwBBAAAgAAgIpQGzLwBBAAAHAAgIMQC+qQAmAAAAAA==.',My='Myrrha:BAAALAADCgYIBgAAAA==.Mystikmage:BAABLAAECoEVAAIQAAgItg76JADWAQAQAAgItg76JADWAQAAAA==.Myynach:BAAALAAECgYIDgAAAA==.',['Mê']='Mêlanes:BAAALAADCggICAAAAA==.',['Mî']='Mîu:BAABLAAECoEpAAIKAAgIYCHBHwCpAgAKAAgIYCHBHwCpAgAAAA==.',Na='Nakavoker:BAAALAAECgQIBgAAAA==.Naschi:BAAALAADCggIFQAAAA==.Nationalelfe:BAAALAADCggICAABLAAECgcIHgALAC4eAA==.Naturesprime:BAAALAAECgYIEQAAAA==.Naturhuf:BAAALAAECgMIAwAAAA==.Nayuta:BAAALAAECggICAAAAA==.',Ne='Needforspeed:BAAALAADCgQIBAAAAA==.Neldai:BAABLAAECoEUAAIhAAYI9iNlBgBvAgAhAAYI9iNlBgBvAgAAAA==.Neltarion:BAAALAADCggIHQAAAA==.Nemaide:BAABLAAECoEcAAIKAAcIxxDXhQBxAQAKAAcIxxDXhQBxAQAAAA==.Neoblomný:BAAALAAECgQICwAAAA==.Neoxt:BAAALAAECgYIEgAAAA==.',Ni='Nidavelier:BAAALAAECgQIBAAAAA==.Nightblade:BAAALAAECgIIAwAAAA==.Nimativ:BAAALAAECgYIEQAAAA==.',No='Noala:BAAALAAECgYIEAAAAA==.Nocx:BAABLAAECoErAAIIAAgIYB8ZGwBkAgAIAAgIYB8ZGwBkAgAAAA==.Nojoy:BAACLAAFFIELAAIdAAUIXB5HAwDlAQAdAAUIXB5HAwDlAQAsAAQKgTAAAh0ACAhpJI4HACwDAB0ACAhpJI4HACwDAAAA.Nolity:BAABLAAECoEjAAMCAAgINxfMawDiAQACAAgINxfMawDiAQAaAAUITQq3SwDiAAAAAA==.Nomie:BAEALAAECggIEQABLAAECggIGwAEAJ0gAA==.Nomié:BAEBLAAECoEVAAIYAAgIshhcFQA8AgAYAAgIshhcFQA8AgABLAAECggIGwAEAJ0gAA==.Nomíé:BAEALAADCgQIBAABLAAECggIGwAEAJ0gAA==.Norak:BAAALAADCgcIBwAAAA==.Notärztin:BAAALAAECgYIAwAAAA==.Novionia:BAAALAADCgQIBAAAAA==.',Nu='Nuy:BAABLAAECoErAAIKAAgIoiUaBgBPAwAKAAgIoiUaBgBPAwAAAA==.',Ny='Nymea:BAAALAAECgcIEgAAAA==.Nymerià:BAAALAAECgMIAwAAAA==.Nyrel:BAAALAAECgYIDQAAAA==.Nyxira:BAAALAAECgYICQAAAA==.',['Nà']='Nàsty:BAAALAADCggICAAAAA==.',['Nâ']='Nânamii:BAAALAAECggIDgABLAAFFAMICQAiAIYaAA==.',['Nê']='Nêssaja:BAAALAAECgYIBgAAAA==.',['Nì']='Nìka:BAAALAADCggIEgAAAA==.',['Nî']='Nîcý:BAAALAAECggIEAAAAA==.',['Nó']='Nómie:BAEALAAECgYICwABLAAECggIGwAEAJ0gAA==.Nómíé:BAEALAAECggIEAABLAAECggIGwAEAJ0gAA==.',['Nô']='Nômie:BAEBLAAECoEbAAIEAAgInSBWBQD5AgAEAAgInSBWBQD5AgAAAA==.',['Nû']='Nûdelhunter:BAACLAAFFIEFAAMfAAIIrxtNIQCnAAAfAAIIrxtNIQCnAAAjAAEI0hgVEwBHAAAsAAQKgSYAAx8ACAgEH0gfAMgCAB8ACAgEH0gfAMgCACMAAwhGD/lFAIIAAAAA.',Oa='Oaschkazel:BAAALAADCgcICAAAAA==.',Oc='Ochsford:BAAALAAECgMIBwAAAA==.',Og='Ogra:BAAALAADCggIHQAAAA==.',Ol='Oldener:BAAALAAECgIIAgAAAA==.Olio:BAAALAADCggICAAAAA==.',On='Onkela:BAABLAAECoEWAAIGAAgIlQfRkgA3AQAGAAgIlQfRkgA3AQAAAA==.Onlein:BAAALAAECgUIDwAAAA==.',Or='Orangebud:BAAALAADCgcIDAAAAA==.Oreane:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Ormes:BAAALAADCggIDgAAAA==.Oryx:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Orzowei:BAAALAADCggICAAAAA==.',Os='Osana:BAAALAADCgcIEwAAAA==.',Ou='Outzider:BAAALAAECgYIEgAAAA==.',Pa='Padma:BAABLAAECoEhAAMeAAgIQh1DCgCVAgAeAAgIQh1DCgCVAgAYAAYIigqbOwAIAQAAAA==.Painbow:BAABLAAECoEaAAIiAAcIehDRPACqAQAiAAcIehDRPACqAQAAAA==.Palacetamol:BAACLAAFFIELAAIaAAUIwxVFBACzAQAaAAUIwxVFBACzAQAsAAQKgRsAAhoACAjlH8QFAPQCABoACAjlH8QFAPQCAAAA.Palanorris:BAAALAADCgcIBwAAAA==.Palaver:BAAALAAECgYICwAAAA==.Palinaí:BAAALAADCggICAAAAA==.Palì:BAAALAADCgYIAQAAAA==.Pantastisch:BAAALAAECggICAABLAAECggIGgAYAGkZAA==.Papadudu:BAAALAAECgMIAwAAAA==.Parlo:BAAALAADCgYIBgAAAA==.París:BAABLAAECoEYAAICAAcIXhUxagDmAQACAAcIXhUxagDmAQAAAA==.Patzeclap:BAAALAAECggIEQAAAA==.Patzedh:BAAALAAECgcIEQABLAAECggIEQABAAAAAA==.Pava:BAAALAAECggICQAAAA==.',Pe='Pelaios:BAAALAADCggICAABLAADCggICAABAAAAAA==.Pendash:BAAALAAECgYIDAAAAA==.Pengfeng:BAAALAAECgYIBwAAAA==.Pennerbombe:BAABLAAECoEeAAISAAgIqRkRCgD7AQASAAgIqRkRCgD7AQAAAA==.Penthy:BAAALAAECgYIDQAAAA==.Pepperidge:BAAALAAECggICAABLAAFFAUICgATABYZAA==.Perditaamo:BAAALAAECgYICAAAAA==.Petzibär:BAAALAAECggIEAAAAA==.',Ph='Pherisus:BAAALAAECgcIDgAAAA==.Phex:BAAALAAECgIIAgAAAA==.Phix:BAAALAAECggICAAAAA==.Phèx:BAACLAAFFIEMAAIfAAUIMR91BQD/AQAfAAUIMR91BQD/AQAsAAQKgScAAh8ACAjdJVMGAF0DAB8ACAjdJVMGAF0DAAAA.',Pl='Plelf:BAAALAAECgYIEgAAAA==.Ploedeq:BAAALAADCggICAAAAA==.',Po='Pogchamp:BAAALAAECgcIBwAAAA==.Powerbogen:BAAALAAECgQICQAAAA==.',Pr='Priesterella:BAAALAAECggIBwAAAA==.Problemkuh:BAAALAADCggICAAAAA==.Profdrmed:BAACLAAFFIEIAAIHAAMIUyGMCwAfAQAHAAMIUyGMCwAfAQAsAAQKgR8AAwcACAiIIWsOAOACAAcACAiIIWsOAOACACAAAQjICXM0AC0AAAAA.',Pu='Puuhlee:BAAALAAECgcIDgABLAAECgYIDwABAAAAAA==.',['Pá']='Pálamu:BAAALAAECgUIBQAAAA==.Pálínai:BAAALAAECgcIEQAAAA==.',['Pâ']='Pâlínai:BAAALAADCggICAAAAA==.',['Pí']='Píng:BAAALAADCggIDwAAAA==.',Qi='Qiin:BAACLAAFFIEHAAIUAAUIVA0/CABYAQAUAAUIVA0/CABYAQAsAAQKgRUAAhQACAgwG/MfAHMCABQACAgwG/MfAHMCAAAA.',Ql='Qlöde:BAAALAAFFAIIAgAAAA==.',Ra='Raaku:BAAALAAECgYICgAAAA==.Ragnarogg:BAAALAAECgIIAgABLAAECgYIEgAOAAIZAA==.Rainmakerex:BAAALAADCgMIAwAAAA==.Ramondis:BAAALAAECgEIAQAAAA==.Rasc:BAAALAADCggIDAAAAA==.Rasorae:BAAALAAECgYICAAAAA==.Rayka:BAAALAADCggICAABLAAECgYIGgAHAEkjAA==.Razørs:BAAALAAECggIEwAAAA==.Raý:BAAALAAECgQIBwAAAA==.',Re='Redstone:BAAALAADCgQIBAABLAAECgcIHgALAC4eAA==.Reev:BAAALAAECggIDwAAAA==.Rengahr:BAAALAAECgYIDAAAAA==.Resilience:BAAALAAECgIIAgABLAAECgYIFgAOAJ8fAA==.',Rh='Rhox:BAAALAAECgEIAQAAAA==.',Ri='Ridik:BAAALAADCgcIDgAAAA==.Rimarà:BAAALAADCgcIBwAAAA==.Rischi:BAAALAAECgYIEAAAAA==.Ritzos:BAABLAAECoEpAAINAAcIxRx2DABjAgANAAcIxRx2DABjAgAAAA==.',Ro='Rockylein:BAAALAAECgEIAQAAAA==.Rogar:BAAALAADCggIGQAAAA==.Roguecilia:BAAALAAECgQIBAAAAA==.Rokhar:BAAALAADCgcICQAAAA==.',Ry='Ryco:BAABLAAECoEXAAIkAAYIWQ4nNwBwAQAkAAYIWQ4nNwBwAQAAAA==.',['Rî']='Rîkku:BAAALAAECggICAAAAA==.',['Rü']='Rüdnarök:BAAALAADCggICAAAAA==.',Sa='Sacrífíce:BAAALAAECgQIBAAAAA==.Salacia:BAAALAADCggICAAAAA==.Salazzar:BAAALAAECgEIAQAAAA==.Saloc:BAABLAAECoEcAAIdAAcIORQeLwDXAQAdAAcIORQeLwDXAQAAAA==.Sanitoeter:BAAALAAECgUICAAAAA==.Santi:BAAALAAECggICQAAAA==.Sanusi:BAAALAADCgYIBgABLAAECgcIHgALAC4eAA==.Saphurion:BAAALAADCggIEgAAAA==.Sardaî:BAAALAADCggICAAAAA==.Savême:BAAALAADCgYIBwAAAA==.Sawkicker:BAAALAAECgYIEAAAAA==.Sayjuki:BAAALAADCgUIBQAAAA==.Sayla:BAAALAAECgUIBQAAAA==.',Sc='Sceptrez:BAAALAAECggIEAAAAA==.Schamili:BAAALAAECgUICQAAAA==.Schams:BAABLAAECoEcAAIUAAYI8RVfeABaAQAUAAYI8RVfeABaAQAAAA==.Schila:BAAALAADCgUIBQAAAA==.Schnubsii:BAAALAADCgYIBgAAAA==.Schnuffelie:BAAALAADCgcICQAAAA==.Schuppî:BAAALAADCgUICAABLAAECggIBwABAAAAAA==.Schwarzwald:BAAALAAECgIIAgAAAA==.',Se='Seccu:BAAALAADCggIDwABLAAECgYIFQAPAKUMAA==.Semaphine:BAABLAAECoEUAAIDAAYICSQjDgByAgADAAYICSQjDgByAgAAAA==.Senpai:BAAALAAECgQIBAAAAA==.Senpái:BAAALAAECgYICwAAAA==.Senra:BAAALAAECgQIBwAAAA==.Senzzoe:BAAALAAECggICAAAAA==.Sephir:BAAALAADCggIEAAAAA==.Serà:BAABLAAECoEfAAQQAAgIXyXoAQBtAwAQAAgIXyXoAQBtAwAGAAEI2B9D0QBbAAAVAAEIfhhIGQBLAAAAAA==.',Sh='Shabhazza:BAABLAAECoEYAAIdAAgIhQYnYgDuAAAdAAgIhQYnYgDuAAAAAA==.Shadowmane:BAAALAAECgIIAgAAAA==.Shadur:BAAALAADCggICAABLAAECgcIHgALAC4eAA==.Shaiýa:BAAALAAECgQIBgAAAA==.Shanressar:BAABLAAECoElAAIfAAgIKBoNQAA6AgAfAAgIKBoNQAA6AgAAAA==.Sheenah:BAABLAAECoEcAAIUAAYIUBLfkQAgAQAUAAYIUBLfkQAgAQAAAA==.Shenjar:BAABLAAECoEeAAMLAAcILh43FgBTAgALAAcILh43FgBTAgAPAAEIcQLj3QARAAAAAA==.Shinkawa:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Shinrà:BAAALAADCggIEAAAAA==.Shodh:BAAALAADCgcIBwABLAAECggIEwAGANEiAA==.Shuichi:BAAALAAECgUICAAAAA==.Shunt:BAAALAADCggIDAAAAA==.Shàné:BAAALAADCgQIBAAAAA==.Sháné:BAAALAAECgIIAgAAAA==.Shøøtemup:BAAALAAECggICgAAAA==.',Si='Sibul:BAAALAAECgUICwAAAA==.Siju:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.Silesta:BAABLAAECoEkAAIgAAgIzSOSAABRAwAgAAgIzSOSAABRAwABLAAECggIJgAIAFsiAA==.Sindra:BAAALAAECgIIAgAAAA==.Sinuvil:BAAALAAECggIDQABLAAECggIJAALAFMkAA==.Sixkiller:BAAALAADCgcIBwAAAA==.',Sk='Skinnypuppy:BAAALAADCggIDwAAAA==.Skol:BAAALAADCgcIEwAAAA==.Skydk:BAAALAADCggICAAAAA==.Skymonki:BAABLAAECoEfAAIeAAcIMBE/HgB1AQAeAAcIMBE/HgB1AQABLAADCggICAABAAAAAA==.',So='Sorbya:BAAALAAECgUIBwAAAA==.',Sp='Spacêe:BAAALAAECgUIBQABLAAFFAYIEgAkABkjAA==.Spinnbert:BAAALAADCggICAABLAAFFAUIBwAUAFQNAA==.Spirittx:BAAALAADCgcICwABLAAECgYIDwABAAAAAA==.',Sr='Srîka:BAAALAADCgQIBAAAAA==.',St='Stahl:BAAALAAECgMIAwAAAA==.Stahlrock:BAAALAADCggICAAAAA==.Strohhut:BAAALAAECgMIBwAAAA==.Stylewalker:BAAALAAECgYIEAAAAA==.Stâhlrock:BAABLAAECoEXAAMUAAgI4w91agB9AQAUAAgI4w91agB9AQAJAAEIEgonrAA2AAAAAA==.Stérnenkind:BAABLAAECoEUAAIKAAYIeRCdmABNAQAKAAYIeRCdmABNAQAAAA==.',Sy='Syladean:BAAALAADCggICAAAAA==.Syrialis:BAAALAAECgQICgAAAA==.',['Sí']='Sínuviel:BAABLAAECoEkAAILAAgIUySPBAA5AwALAAgIUySPBAA5AwAAAA==.',['Só']='Sóphie:BAAALAADCggICQAAAA==.Sóra:BAAALAAECggIDAAAAA==.',['Sø']='Søckenbügler:BAAALAAECggIDgABLAAFFAIICAAIAIUTAA==.',Ta='Takako:BAAALAADCggICAAAAA==.Takeomasaki:BAAALAAECgYICwAAAA==.Talantor:BAAALAAECgYIEwAAAA==.Tassdrago:BAABLAAECoEZAAIcAAcI1xrJDQAlAgAcAAcI1xrJDQAlAgAAAA==.Tassilo:BAAALAADCggICAAAAA==.Taunix:BAAALAADCggIGgAAAA==.',Te='Technogikus:BAAALAAECgUIBQAAAA==.Tekvora:BAAALAADCgYIBgAAAA==.Teval:BAAALAADCggIEgAAAA==.',Th='Thaloren:BAAALAADCggICAAAAA==.Theressa:BAABLAAECoEiAAIDAAgIuBh9FQAeAgADAAgIuBh9FQAeAgAAAA==.Thorneblood:BAAALAAECgEIAQAAAA==.Threeinch:BAAALAADCgcIBwAAAA==.Thálya:BAAALAAECgMIBQAAAA==.',Ti='Tibbi:BAAALAAECgUIBgAAAA==.Tinares:BAAALAAECgIIAgAAAA==.Tio:BAAALAADCggICAAAAA==.Tivara:BAAALAAECgcIBwAAAA==.',To='Todyys:BAAALAADCgIIBAAAAA==.Tomcruisader:BAAALAADCggIFQABLAAECgEIAQABAAAAAA==.Totemmeister:BAAALAADCgYIBgAAAA==.',Tr='Treffníx:BAAALAAECgYICQAAAA==.Trex:BAAALAADCgYIBgAAAA==.Trueide:BAAALAADCgIIAgAAAA==.',Tu='Tutzel:BAAALAAECgEIAgAAAA==.',Ty='Tygerlilly:BAABLAAECoEWAAIKAAgIHhLoZwCzAQAKAAgIHhLoZwCzAQABLAAECggIJwAJANcWAA==.Tynaria:BAAALAAFFAEIAQAAAA==.Tysen:BAAALAAECgMIAwABLAAECggIHgACALUhAA==.',Tz='Tziki:BAABLAAECoEnAAIHAAgIfR3wEQDBAgAHAAgIfR3wEQDBAgAAAA==.',Ue='Uelidehealer:BAABLAAECoEVAAMIAAgIBwyaXgA5AQAIAAgIBwyaXgA5AQAdAAUIhwuJYAD2AAAAAA==.',Uh='Uhps:BAAALAADCgEIAQAAAA==.',Ul='Ulltron:BAAALAAECgIIAgAAAA==.Ulrichstein:BAAALAADCgEIAQAAAA==.',Um='Umut:BAAALAADCggICAAAAA==.',Ur='Uriél:BAAALAADCggICAAAAA==.',Va='Vahltas:BAAALAAECgMIBwAAAA==.Vaila:BAAALAAECgYICgAAAA==.Valkye:BAAALAADCggICwAAAA==.Valygosa:BAAALAAECgUICQAAAA==.Vargrin:BAAALAADCggIEAAAAA==.Varithra:BAAALAAECgYIDgAAAA==.Vascó:BAAALAADCggIHQAAAA==.Vashara:BAAALAAECgMIAwAAAA==.',Ve='Vedalia:BAAALAAECgIIAgAAAA==.Veijari:BAAALAAECgMIBAAAAA==.Velaryn:BAAALAAFFAIIAgABLAAFFAIIAgABAAAAAA==.Velerius:BAAALAADCgcIBwABLAAECgQIDQABAAAAAA==.Ventipala:BAABLAAECoEeAAICAAgIOhhHUgAdAgACAAgIOhhHUgAdAgAAAA==.Vermeíl:BAAALAAECgEIAQAAAA==.',Vi='Vicany:BAABLAAECoEgAAIHAAgI1haOJgAyAgAHAAgI1haOJgAyAgAAAA==.',Vo='Voolverine:BAAALAADCgYIAQAAAA==.Vortrak:BAAALAADCggIIgAAAA==.Vortrek:BAAALAADCggIHQAAAA==.Vortrik:BAAALAADCggIGgAAAA==.',Vu='Vuppi:BAAALAADCgcIFQAAAA==.',Vy='Vyrez:BAAALAADCgEIAQAAAA==.',['Vä']='Vännish:BAAALAAFFAMIAwAAAA==.',Wa='Waffeleisen:BAABLAAFFIEHAAIUAAIIFw4RNgB2AAAUAAIIFw4RNgB2AAAAAA==.Waifu:BAABLAAECoEgAAIJAAgIZSCtGAC3AgAJAAgIZSCtGAC3AgAAAA==.Warristyles:BAAALAAECgEIAQAAAA==.',Wh='Whityxd:BAAALAADCgEIAQAAAA==.Whynnê:BAAALAADCggICAAAAA==.',Wi='Wiczi:BAAALAAECggIEAAAAA==.',Wo='Woodknife:BAAALAAECgYIBgAAAA==.',['Wà']='Wàrheàrt:BAAALAADCgcIBwAAAA==.',['Wì']='Wìsh:BAAALAADCgcIDQABLAAECgYIFwAKAMEbAA==.',['Wó']='Wódan:BAAALAAECgQIDQAAAA==.',Xa='Xaitra:BAAALAADCggICAAAAA==.Xalindare:BAAALAADCgMIAwAAAA==.Xarthul:BAABLAAECoESAAIOAAYIAhn4IwDMAQAOAAYIAhn4IwDMAQAAAA==.',Xe='Xemnás:BAAALAADCgcIDgAAAA==.',Xo='Xosad:BAAALAAECgIIAgAAAA==.',Xr='Xrparmy:BAAALAAECggIEAAAAA==.',Xs='Xsen:BAAALAAECgIIAgAAAA==.',Ya='Yanê:BAAALAADCgcIBwAAAA==.',Yo='Yoruíchí:BAAALAAECgEIAQAAAA==.Yoshino:BAAALAAECgcIEAAAAA==.',Yu='Yumeko:BAAALAADCgcIBwAAAA==.Yunalescá:BAAALAADCggIDgAAAA==.',['Yû']='Yûkí:BAAALAAECgQIBAAAAA==.',Za='Zab:BAAALAAECgEIAQAAAA==.Zackipriest:BAAALAAECgYIBwAAAA==.Zackthyr:BAAALAAECgEIAQABLAAECgYIBwABAAAAAA==.Zagzagelia:BAAALAAECgMIBgABLAAECggILQAdAP0QAA==.Zal:BAAALAAECggICgAAAA==.',Ze='Zelaous:BAAALAAECgEIAQAAAA==.Zenchou:BAAALAAECgYIBgABLAAECggIGgAYAGkZAA==.Zerberos:BAAALAAECgIIAgAAAA==.Zerebro:BAAALAADCgEIAQAAAA==.Zerozerotwo:BAAALAADCggICAABLAAECgcIGAACAJEgAA==.Zeyrox:BAAALAADCgcIAQAAAA==.',Zi='Zihua:BAAALAAECgcIEgAAAA==.Zilana:BAABLAAECoEmAAMIAAgIWyK9JAAqAgAIAAgIWyK9JAAqAgAdAAQIdxnEawC7AAAAAA==.Zilverblade:BAAALAAECgYIDAAAAA==.',Zo='Zoniya:BAABLAAECoEVAAIKAAYIHA4NowA5AQAKAAYIHA4NowA5AQAAAA==.',Zu='Zumor:BAAALAADCggIEAAAAA==.',['Zö']='Zöschi:BAABLAAECoEWAAIQAAgIKSJdEACFAgAQAAgIKSJdEACFAgAAAA==.',['Ån']='Åndrox:BAAALAAECgcIEQAAAA==.',['În']='Înostrion:BAABLAAECoEiAAIWAAgIbwzbGwB2AQAWAAgIbwzbGwB2AQAAAA==.',['Ðî']='Ðîrk:BAABLAAECoEaAAIfAAgIsxHoWwDoAQAfAAgIsxHoWwDoAQAAAA==.',['Óf']='Óf:BAAALAAECgIIAgAAAA==.',['Ör']='Örchên:BAAALAAECgQICAAAAA==.',['Ør']='Øreøz:BAAALAADCggICAAAAA==.',['Ýu']='Ýuuki:BAAALAAECgMICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end