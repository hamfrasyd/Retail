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
 local lookup = {'Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Shaman-Restoration','Mage-Arcane','Druid-Feral','Warlock-Demonology','Druid-Restoration','Unknown-Unknown','Warrior-Fury','Hunter-BeastMastery','Shaman-Elemental','Monk-Brewmaster','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Priest-Shadow','Paladin-Retribution','DeathKnight-Blood','Hunter-Marksmanship','Mage-Frost','Mage-Fire','Warlock-Affliction','Monk-Windwalker','Rogue-Assassination','Paladin-Protection','Monk-Mistweaver','Druid-Balance','Druid-Guardian','Shaman-Enhancement','Warrior-Arms','Paladin-Holy','DeathKnight-Unholy','DeathKnight-Frost',}; local provider = {region='EU',realm='Malorne',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarax:BAAALAAECggICgABLAAECggIHwABAIEOAA==.',Ab='Abtropfdecke:BAABLAAECoEYAAMCAAYIWRQMlQBuAQACAAYIVxMMlQBuAQADAAQI5xSSMwDvAAAAAA==.',Ac='Acidmäuschen:BAAALAADCggIFAAAAA==.',Ad='Adania:BAAALAAECgIIAgABLAAECggIQgAEABUiAA==.Adrialla:BAAALAAECgYIEgAAAA==.',Ae='Aelianus:BAAALAADCgMIAwAAAA==.Aeowyn:BAABLAAECoEZAAIFAAYISgMZsQDNAAAFAAYISgMZsQDNAAAAAA==.',Ah='Ahlol:BAAALAADCgMIAwABLAAECgYIGAACAFkUAA==.',Ak='Aktronum:BAAALAADCgcICQAAAA==.',Al='Alef:BAAALAAECgYIEAAAAA==.Alesandra:BAAALAADCggIDQAAAA==.Alias:BAAALAAECgQIBQABLAAECgYIGAACAFkUAA==.Alpstatcher:BAACLAAFFIEIAAIGAAMIURrnBgCxAAAGAAMIURrnBgCxAAAsAAQKgSoAAgYACAi5I18GAN8CAAYACAi5I18GAN8CAAAA.Althèa:BAAALAAECgEIAQAAAA==.',An='Angespüllt:BAAALAADCgEIAQAAAA==.Ankyro:BAAALAADCgUIBQAAAA==.Anomander:BAAALAAECgYIBgAAAA==.Anthik:BAAALAAECgYIDgAAAA==.Anûk:BAAALAAECgUIDAAAAA==.',Ap='Apeiron:BAAALAAECgEIAgAAAA==.Aposata:BAAALAADCgMIAwAAAA==.Appleblossom:BAAALAADCggICwAAAA==.',Ar='Arcus:BAAALAAECgEIAgAAAA==.Argamos:BAAALAADCggICAAAAA==.Arms:BAAALAAECgEIAQAAAA==.Arnantel:BAABLAAECoEVAAMBAAcImRvDNQA3AgABAAcImRvDNQA3AgAHAAMIBw6bZgClAAAAAA==.Arugos:BAAALAAECgYIEgAAAA==.',As='Asagiri:BAAALAADCggICAABLAAECggIJwAIAMoVAA==.Ashterian:BAAALAADCgUIBQAAAA==.',At='Athenaris:BAAALAAECgUIDwAAAA==.',Au='Auroraindica:BAAALAAECgMIAwAAAA==.',Aw='Awhorn:BAABLAAECoElAAIIAAgIuRtkFQCMAgAIAAgIuRtkFQCMAgAAAA==.',Ax='Axtuz:BAAALAAECgcIEAAAAA==.',Az='Azinthar:BAAALAAECgYICwAAAA==.',Ba='Badadan:BAAALAADCgQIBAAAAA==.Baldúr:BAAALAAECgYICAAAAA==.Bargurion:BAAALAAECgYIBgABLAAECgYIDwAJAAAAAA==.Bassboxx:BAAALAAECgMIBAABLAAECggIIAAKAJoNAA==.Bazzburst:BAAALAADCggICAAAAA==.Bazzshot:BAAALAADCggICAAAAA==.',Be='Beatricx:BAAALAADCggIGAAAAA==.Bevla:BAAALAAECgEIAQAAAA==.',Bi='Bibergirl:BAAALAAECgYICgAAAA==.Bigblackwolf:BAAALAADCgcIDQAAAA==.Bigman:BAAALAAECggICQAAAA==.',Bl='Bloubs:BAAALAADCggIGwAAAA==.Bluebunny:BAAALAADCgYIBgAAAA==.Bluwar:BAAALAADCgEIAQABLAAECgQIBAAJAAAAAA==.',Bo='Borgar:BAABLAAECoEaAAILAAYImRnnZwCzAQALAAYImRnnZwCzAQAAAA==.Borís:BAAALAADCggICwABLAAECggIKgAMAHMVAA==.',Br='Brewfox:BAAALAAECgYIEwAAAA==.Brewslee:BAABLAAECoEnAAINAAgIQBq/DQBTAgANAAgIQBq/DQBTAgAAAA==.Bronzos:BAAALAAECggIDwAAAA==.Bruni:BAAALAAECgIIAgAAAA==.',Bu='Buffdaddy:BAAALAADCgUIBQAAAA==.Bullety:BAAALAAECgEIAQAAAA==.Burakdabörek:BAAALAADCgcIBwABLAAECgcIDwAJAAAAAA==.',['Bá']='Bádbøy:BAAALAADCgYIBgABLAAECggICAAJAAAAAA==.',['Bü']='Bülizette:BAAALAADCgcICQAAAA==.',Ca='Cadira:BAAALAAECgUIDAAAAA==.Caedyl:BAAALAAECgMIAwABLAAECggICAAJAAAAAA==.Caelesdris:BAAALAADCggIFwAAAA==.Calligola:BAAALAAECgMIBAAAAA==.Carcaras:BAAALAAECgEIAQAAAA==.',Ce='Celci:BAAALAAECgcIDAAAAA==.',Ch='Chelseá:BAAALAAECgcIEwAAAA==.Chishi:BAABLAAECoElAAILAAgIUyWhBwBDAwALAAgIUyWhBwBDAwAAAA==.Chordeva:BAABLAAECoEYAAIOAAgIAhJYOQDRAQAOAAgIAhJYOQDRAQAAAA==.Chrille:BAAALAAECgUIDAAAAA==.',Co='Codil:BAAALAAECgEIAQAAAA==.Collete:BAAALAAECgYIDgAAAA==.Colora:BAAALAADCggIDQAAAA==.',Cr='Crîtical:BAABLAAECoEwAAIPAAgIXRXWGwAlAgAPAAgIXRXWGwAlAgAAAA==.',Da='Daman:BAABLAAECoEwAAIMAAgIcByKIAB+AgAMAAgIcByKIAB+AgAAAA==.Damiiel:BAAALAADCgYIBgAAAA==.Daredèvil:BAAALAADCgcIDAABLAAECgYIBgAJAAAAAA==.Davo:BAAALAAECgQIBAAAAA==.',De='Deamonpuffi:BAACLAAFFIEGAAICAAIIAwPkQAB3AAACAAIIAwPkQAB3AAAsAAQKgSMAAgIACAhSEBpiANkBAAIACAhSEBpiANkBAAAA.Deathbrecher:BAAALAAECgYIDwAAAA==.Deathroad:BAAALAADCggICAABLAAECgYIEgAJAAAAAA==.Deeghoota:BAAALAADCggICAAAAA==.Demonkuaa:BAAALAAECggIEAAAAA==.Demonrace:BAAALAAECgEIAQAAAA==.Deracos:BAABLAAECoEkAAMPAAgIJB9KCgDsAgAPAAgIJB9KCgDsAgAQAAEIPQcTGAAgAAAAAA==.Destroxa:BAAALAAECggICAAAAA==.Dezorac:BAAALAADCgMIAwABLAADCgcIEQAJAAAAAA==.',Di='Discobella:BAAALAADCgIIAQAAAA==.Divus:BAAALAAECgYIDQAAAA==.',Dk='Dk:BAAALAAFFAIIBAAAAA==.',Do='Dolchdoris:BAAALAAECgYIBgABLAAECgYIGAACAFkUAA==.Dolrak:BAEALAAECggICwABLAAECggIHQARAMoYAA==.Domba:BAAALAAECgEIAQAAAA==.Dominica:BAAALAAECgMIAwAAAA==.Doofus:BAABLAAECoEbAAIBAAYIAxaOXgChAQABAAYIAxaOXgChAQAAAA==.',Dr='Dracalyss:BAAALAAECgEIAQAAAA==.Dracwar:BAAALAAECgIIAgAAAA==.Dredorius:BAAALAAECggICwAAAA==.Drmidnight:BAAALAAECgYICAAAAA==.Droetker:BAAALAADCgQIBAAAAA==.Drottning:BAAALAADCgcICQAAAA==.Drâgonheart:BAAALAAECggIDwAAAA==.',Dy='Dyndi:BAAALAAECgIIAgABLAAFFAIICgASAPgkAA==.',['Dé']='Dée:BAAALAAECgMIAwAAAA==.',['Dö']='Dödlich:BAAALAAECgYIEgAAAA==.',El='Eladros:BAABLAAECoEdAAIDAAcI1B36FgDgAQADAAcI1B36FgDgAQABLAAECggIDgAJAAAAAA==.Eleeven:BAAALAAECgYIDgAAAA==.Elenor:BAAALAAECgYIEAABLAAECgcIEwAJAAAAAA==.Elvendra:BAABLAAECoEiAAIOAAgI9wuVSACOAQAOAAgI9wuVSACOAQAAAA==.',Em='Emilyprocter:BAAALAADCgQIBAABLAAECgYIGAACAFkUAA==.',En='Endivié:BAAALAADCgYIBQABLAADCggICAAJAAAAAA==.Endû:BAABLAAECoEbAAINAAgIKxn2DQBPAgANAAgIKxn2DQBPAgAAAA==.',Ev='Everytimetii:BAABLAAECoEgAAITAAgITx0vDQBPAgATAAgITx0vDQBPAgAAAA==.',Fa='Fael:BAAALAADCgQIBAAAAA==.Farios:BAAALAADCggIEwAAAA==.Farásha:BAAALAADCgcIBAAAAA==.',Fe='Feelsdhman:BAAALAAECggIDQAAAA==.Felenien:BAAALAAECgUIBwAAAA==.Feuergirl:BAABLAAECoEcAAICAAcIiwXB4wC1AAACAAcIiwXB4wC1AAAAAA==.',Fi='Fighti:BAAALAADCgUIBgAAAA==.Finn:BAAALAAECgEIAQAAAA==.',Fl='Flidhais:BAAALAADCgcIBwAAAA==.Fludra:BAAALAADCgcIDAAAAA==.Flumbri:BAAALAADCggICAAAAA==.',Fr='Fremenzorn:BAABLAAECoEYAAILAAgIYhH6ZQC4AQALAAgIYhH6ZQC4AQAAAA==.Fridda:BAAALAADCggICAAAAA==.Friedlich:BAAALAADCgcIBwAAAA==.Friendlyfire:BAABLAAECoEVAAIUAAYIBwgReADSAAAUAAYIBwgReADSAAAAAA==.Fronsac:BAAALAAECgIIAgAAAA==.',['Fâ']='Fâmosi:BAAALAADCgcIBwAAAA==.',Ga='Gaman:BAAALAAECgIIAwAAAA==.Garurumon:BAABLAAECoEVAAIGAAgImxx7CwB1AgAGAAgImxx7CwB1AgAAAA==.Gawlan:BAAALAAECgUIBQAAAA==.',Ge='Geller:BAABLAAECoEcAAIVAAYImCC1GgAgAgAVAAYImCC1GgAgAgAAAA==.Gerrost:BAAALAAECgEIAQABLAAECgYIDwAJAAAAAA==.',Gi='Gieladin:BAAALAAECgEIAQAAAA==.',Go='Gordi:BAAALAADCggIEwAAAA==.Gordislan:BAAALAADCggIEwAAAA==.',Gr='Grambo:BAABLAAECoEcAAISAAcI/hebhgCtAQASAAcI/hebhgCtAQAAAA==.Gramdi:BAAALAAECgMIAwAAAA==.Grimmig:BAAALAADCgcIBwAAAA==.Grnrrw:BAAALAADCggICQAAAA==.Groktan:BAAALAADCggIDgAAAA==.',Gu='Gunsound:BAACLAAFFIEJAAIUAAMIuh1+CgAHAQAUAAMIuh1+CgAHAQAsAAQKgSIAAhQACAg6IFgQANICABQACAg6IFgQANICAAAA.',Ha='Hailý:BAAALAAECggICAAAAA==.Hammerfall:BAAALAADCggICAAAAA==.Hanuta:BAAALAAECggICAAAAA==.Harbrad:BAAALAAECgYIDwAAAA==.Harmony:BAAALAAECgUICgAAAA==.',He='Healsexapeal:BAAALAAECggICAAAAA==.Hexidor:BAAALAAECggICgAAAA==.Hexxy:BAAALAAECgEIAQAAAA==.',Hj='Hjoldor:BAAALAAECgUIBQABLAAFFAUIEgAPAG8dAA==.',Hl='Hlavacek:BAAALAAECgMIAwAAAA==.',Ho='Holymolyy:BAABLAAECoEcAAIEAAcIcSBFIAByAgAEAAcIcSBFIAByAgAAAA==.Hornpranke:BAAALAADCgcIBQAAAA==.',Hr='Hrevilondo:BAAALAAECgYIBgAAAA==.',Hu='Huntereye:BAAALAADCgYIBgAAAA==.Huntermaster:BAABLAAECoElAAILAAgI3AyVnwBAAQALAAgI3AyVnwBAAQAAAA==.Huntermastér:BAAALAAECgEIAQAAAA==.',Hy='Hyperio:BAAALAADCgUIBQAAAA==.',['Hâ']='Hâyle:BAEBLAAECoEdAAIRAAcIyhj6LQD6AQARAAcIyhj6LQD6AQAAAA==.',['Hé']='Hélios:BAAALAAECggICQAAAA==.',['Hö']='Hörmeline:BAAALAAECgYICQAAAA==.',['Hû']='Hûntermaster:BAAALAADCgQIBAAAAA==.',Ig='Ignitethesky:BAABLAAECoEZAAMFAAYIzCJcNQBYAgAFAAYIzCJcNQBYAgAWAAEIdhTvGgBCAAABLAAECggIDQAJAAAAAA==.',Il='Illinoi:BAAALAAECgIIAgAAAA==.',Im='Imerius:BAAALAAECgYICwAAAA==.',In='Inlord:BAAALAAFFAIIBAAAAA==.Inéèdmoney:BAAALAADCgQIBAAAAA==.',Ir='Iraniasa:BAAALAAECgEIAQAAAA==.Irodana:BAAALAAECggICAAAAA==.',Jo='Joeyjoey:BAAALAAECgEIAQAAAA==.',['Jû']='Jûstêr:BAAALAAECgYIEgAAAA==.',Ka='Kajiva:BAACLAAFFIEKAAMXAAMIqBIrAgCuAAAXAAIICxgrAgCuAAABAAEI4QcAAAAAAAAsAAQKgTEAAhcACAhiIzoBAD8DABcACAhiIzoBAD8DAAAA.Kajsha:BAAALAAECgMIAwAAAA==.Kampfeis:BAAALAADCgMIAgABLAAECgcIDwAJAAAAAA==.',Kh='Khagan:BAAALAADCgUIBwABLAAECgYICAAJAAAAAA==.',Ki='Kittel:BAAALAAECgEIAwAAAA==.',Kn='Knox:BAAALAAECgIIAgAAAA==.',Ko='Kopii:BAAALAADCgcICQAAAA==.',Kr='Kreepy:BAAALAAECgQIBgAAAA==.Kryptoli:BAAALAAECggICwAAAA==.',Ky='Kyudo:BAAALAADCggIGwAAAA==.',La='Lagoper:BAACLAAFFIEGAAIDAAII6RsUBwCjAAADAAII6RsUBwCjAAAsAAQKgS0AAwMACAj+ICYGAOsCAAMACAj+ICYGAOsCAAIAAQilBaApARcAAAAA.Largann:BAABLAAECoEkAAIMAAgIrgzhTQCkAQAMAAgIrgzhTQCkAQAAAA==.',Le='Leccram:BAAALAAECgcIEAAAAA==.Leyarah:BAAALAAECgYIDwAAAA==.',Lf='Lfarenamate:BAAALAAECgYIEgABLAAFFAMICQAUALodAA==.',Li='Linora:BAAALAAECgYIDwAAAA==.Liroxf:BAAALAADCgcIDgAAAA==.Livana:BAAALAAECgMIAwAAAA==.',Lo='Lockomotion:BAAALAADCggIDwAAAA==.Lockomotîve:BAAALAADCggICAAAAA==.Loucia:BAAALAADCggIDwABLAAECggIKgAIANQUAA==.',Lu='Lunaraa:BAABLAAECoEgAAIOAAcIHxuJKAAoAgAOAAcIHxuJKAAoAgAAAA==.',Ly='Lynissel:BAABLAAECoEWAAIYAAYIxBsCJwCWAQAYAAYIxBsCJwCWAQAAAA==.',['Lè']='Lèlè:BAAALAAECgEIAQABLAAECgYIBgAJAAAAAA==.',['Lü']='Lügeamk:BAAALAADCggICAABLAAECggIDQAJAAAAAA==.',Ma='Madxus:BAAALAADCgEIAQAAAA==.Maeiv:BAAALAADCgYIBgAAAA==.Magicmarvin:BAACLAAFFIELAAIVAAMIDRRKBADkAAAVAAMIDRRKBADkAAAsAAQKgTEAAhUACAg5IVkKANoCABUACAg5IVkKANoCAAAA.Magietron:BAAALAAECgIIAgAAAA==.Maldorn:BAABLAAECoEVAAIIAAYIagiffADjAAAIAAYIagiffADjAAAAAA==.Manadead:BAAALAAECgEIAQAAAA==.Managrab:BAAALAADCgcICAAAAA==.Maraxa:BAAALAAECgMIAwAAAA==.Marîne:BAABLAAECoElAAIVAAgIjA/ZJgDJAQAVAAgIjA/ZJgDJAQAAAA==.Matthiasb:BAAALAAECgYIEgAAAA==.Mayruna:BAAALAADCgYIBgAAAA==.',Mc='Mcroguehd:BAAALAADCggIDQAAAA==.',Me='Meraku:BAAALAAECggIEAAAAA==.',Mi='Michaella:BAAALAAECggICAAAAA==.Millicence:BAAALAAECgUIBQAAAA==.Mirigolia:BAAALAAECgYIEwAAAA==.Misskittèn:BAAALAAECgIIAgAAAA==.',Mo='Moniker:BAAALAAECgcIDQABLAAFFAMICQAUALodAA==.Moondust:BAABLAAECoEbAAITAAcICRFOHQBkAQATAAcICRFOHQBkAQAAAA==.Movistar:BAAALAADCggICwABLAAECggICAAJAAAAAA==.',Mu='Mullky:BAAALAAECgYIDAAAAA==.Murlocmaster:BAAALAAECggIBgAAAA==.Mutare:BAAALAAECgYIEwAAAA==.',My='Myell:BAAALAADCggICAAAAA==.',['Mè']='Mèowjò:BAAALAADCgUIBQABLAAECggICAAJAAAAAA==.Mèphala:BAAALAAECgMIAwAAAA==.',['Mø']='Møøn:BAAALAADCggIDQABLAAECgcIGwATAAkRAA==.',Na='Nalie:BAAALAADCgYIBgAAAA==.Naman:BAAALAADCggICAAAAA==.',Ne='Nemli:BAAALAAECggIDgAAAA==.Neraluna:BAAALAAECgYIEAABLAAECggIJwAIAMoVAA==.',Ni='Niene:BAAALAAECgMIAwAAAA==.Nightingâlê:BAAALAADCggICAAAAA==.Nightlord:BAAALAADCgcIDQAAAA==.Ningaloo:BAAALAADCggIEgAAAA==.Niyu:BAAALAAECgYIBgAAAA==.',No='Noita:BAABLAAECoEfAAIBAAgIgQ6vagB/AQABAAgIgQ6vagB/AQAAAA==.Noxin:BAABLAAECoEYAAIZAAgIaAQBSQD4AAAZAAgIaAQBSQD4AAAAAA==.',Ny='Nym:BAABLAAECoEVAAILAAcIwAmpnQBEAQALAAcIwAmpnQBEAQAAAA==.Nymzweisoft:BAAALAAECgYIEgAAAA==.Nyrul:BAAALAADCggICgAAAA==.Nyx:BAAALAADCgYICgAAAA==.',['Nâ']='Nâhíshôk:BAAALAADCgYIBwAAAA==.',Ob='Obivan:BAABLAAECoEVAAIKAAgIig4PWgCqAQAKAAgIig4PWgCqAQAAAA==.',Od='Odiark:BAAALAADCgcIBQAAAA==.',Ol='Oldjasper:BAAALAADCgYIBgAAAA==.',Or='Orctopus:BAAALAADCgcIBwAAAA==.',Pa='Pakuna:BAAALAADCgYIBgABLAAECgYIDwAJAAAAAA==.Palamaus:BAAALAADCgYICgAAAA==.Palami:BAAALAAECggIDwAAAA==.Palduin:BAAALAADCgUIBQAAAA==.Panzér:BAAALAAECgQIBAAAAA==.',Ph='Phaedra:BAABLAAECoEgAAIaAAcIRRU3JwCHAQAaAAcIRRU3JwCHAQAAAA==.Phidok:BAAALAADCggICAAAAA==.Phóeníx:BAAALAADCgIIAgAAAA==.',Pl='Plutel:BAAALAADCggICAAAAA==.Plyb:BAAALAAECgcICgAAAA==.',Po='Poong:BAAALAAECggICQAAAA==.Popstar:BAAALAADCgEIAQAAAA==.Powerzero:BAAALAAECgYICwAAAA==.',Pr='Promethèus:BAAALAAECggIEwAAAA==.Proximus:BAAALAAECggICAAAAA==.',Pu='Pullekorn:BAAALAAECgcIDQAAAA==.',Qu='Quintessa:BAAALAADCggIFgAAAA==.Quorraa:BAAALAADCggIDwAAAA==.',Qy='Qyron:BAAALAAECgEIAQAAAA==.',Ra='Raiga:BAAALAAECgEIAQAAAA==.Ramui:BAABLAAECoEpAAIIAAgIqRSpLwDzAQAIAAgIqRSpLwDzAQAAAA==.Raschia:BAAALAADCgQIBAAAAA==.Rayri:BAAALAADCgcIGQAAAA==.Razanox:BAAALAADCggIFQAAAA==.',Re='Reaven:BAAALAADCgYICAAAAA==.Reload:BAAALAAECgQIBwABLAAECgYIEgAJAAAAAA==.Reláxx:BAAALAADCggIDwAAAA==.Remâ:BAAALAAECgYIDwAAAA==.Rerollinc:BAAALAADCgcIDAAAAA==.Revilondo:BAACLAAFFIEGAAIUAAIIcR+fEwCtAAAUAAIIcR+fEwCtAAAsAAQKgS0AAxQACAhGJAEHACkDABQACAhGJAEHACkDAAsABwgNEWt1AJQBAAAA.',Ri='Rindeastwood:BAAALAADCgUIBQAAAA==.Rizzi:BAABLAAECoEUAAIMAAYIpQQVgQDlAAAMAAYIpQQVgQDlAAAAAA==.',Ro='Roccan:BAACLAAFFIEFAAIMAAMI9QUHFADLAAAMAAMI9QUHFADLAAAsAAQKgSUAAgwACAhGHSIfAIgCAAwACAhGHSIfAIgCAAAA.Roguekuaa:BAAALAAECgYIDwAAAA==.',Ru='Rubine:BAAALAADCggICAAAAA==.',['Rí']='Ríchel:BAAALAADCgYIBwAAAA==.',['Rö']='Röstie:BAABLAAECoEcAAIbAAcIzgotLgD7AAAbAAcIzgotLgD7AAAAAA==.',Sa='Sabrichu:BAABLAAECoEcAAIKAAgIOxRVOQAdAgAKAAgIOxRVOQAdAgAAAA==.Samaria:BAAALAADCggIDwABLAAECgYIDwAJAAAAAA==.Sanii:BAAALAAECgUIDwAAAA==.Santacruz:BAAALAAECgMIAwABLAAECgMIAwAJAAAAAA==.',Sc='Schamanicur:BAAALAADCgYIBgAAAA==.Schestag:BAAALAAECgEIAQAAAA==.Schmocktan:BAAALAADCgUIBQAAAA==.Schnufflchen:BAAALAADCgYIBQAAAA==.Schnulle:BAAALAAECgUICwAAAA==.Schpock:BAAALAADCgMIAwAAAA==.Schôrlé:BAABLAAECoEXAAIYAAcIMx6yEwBQAgAYAAcIMx6yEwBQAgABLAAECggIDQAJAAAAAA==.',Se='Senzuu:BAAALAAECggICAAAAA==.Seríous:BAABLAAECoEjAAMLAAgIiw24kwBWAQALAAgIiw24kwBWAQAUAAEIagQDtgAoAAAAAA==.',Sh='Shamyyamammy:BAAALAADCgcIBwABLAAFFAIIBAAJAAAAAA==.Shikarilock:BAABLAAECoEgAAMBAAcIpx8zMQBMAgABAAcIuR0zMQBMAgAXAAMIXB05GwAEAQAAAA==.Shokxs:BAAALAAECgYIDQAAAA==.Shubi:BAAALAADCggICAABLAAECggIFQAcAKoVAA==.Shuna:BAAALAADCgEIAQAAAA==.Shuyet:BAAALAADCgcICAAAAA==.Shyrlonay:BAACLAAFFIESAAIPAAUIbx2rBQCaAQAPAAUIbx2rBQCaAQAsAAQKgRoAAw8ACAh9HuURAI0CAA8ACAhyG+URAI0CABAAAQguIzsUAGAAAAAA.Shìkarì:BAAALAADCgcIBwABLAAECgcIIAABAKcfAA==.Shùkà:BAAALAADCggIEwAAAA==.',Si='Silaya:BAAALAAECgYIDAAAAA==.Silvercastle:BAAALAADCggIFgAAAA==.Sindarin:BAABLAAECoEWAAMEAAcI0hWJVAC4AQAEAAcI0hWJVAC4AQAMAAQIBgtUhQDQAAAAAA==.',Sk='Skoja:BAAALAAECgYICQAAAA==.Skybrother:BAAALAADCggICwAAAA==.Skyró:BAAALAAECgYIEgAAAA==.Skýróh:BAAALAADCgIIAgAAAA==.',Sn='Snipèz:BAABLAAECoEgAAICAAcIex+JMQBxAgACAAcIex+JMQBxAgAAAA==.',Sp='Spînky:BAAALAAECgcIDQAAAA==.',St='Stibitzkus:BAAALAADCgcIBwAAAA==.Stonks:BAAALAAECggIEAAAAA==.Stormtropper:BAAALAAECgMIBQAAAA==.Strangè:BAAALAADCgYIEwABLAAECgYIBgAJAAAAAA==.Strikeboy:BAAALAAECgYIDwAAAA==.',Su='Surianna:BAAALAAECgUIBgAAAA==.',['Sâ']='Sâbrînâ:BAABLAAECoEZAAMGAAYI8g2TIgBRAQAGAAYI8g2TIgBRAQAdAAMI3gF2KgBIAAAAAA==.Sâitô:BAABLAAECoEfAAMEAAcIZx7eTADOAQAEAAYIOh3eTADOAQAMAAYIdw0OZQBXAQAAAA==.Sânera:BAEALAAECggIEAABLAAECggIHQARAMoYAA==.',Ta='Tangó:BAAALAADCggICAABLAAECggIFwADAPgfAA==.Tayras:BAABLAAECoFCAAIEAAgIFSJVBwAYAwAEAAgIFSJVBwAYAwAAAA==.',Te='Teufelchen:BAAALAADCgIIAgAAAA==.',Th='Thamoran:BAAALAAECgYIEQAAAA==.Tharenwel:BAAALAADCgUIBQABLAAECggIIAAKABojAA==.Thewitcher:BAAALAADCgcIBwAAAA==.Theødwyn:BAABLAAECoEUAAIIAAYIegx1cQACAQAIAAYIegx1cQACAQAAAA==.Thiccel:BAAALAADCggIGwAAAA==.Thorgrom:BAABLAAECoEVAAMMAAYITBJnYgBfAQAMAAYIhw9nYgBfAQAeAAYIuBAgFgBeAQAAAA==.Thorudor:BAAALAAECgYIBgAAAA==.Thungild:BAAALAAECgMIAwAAAA==.',Ti='Tiondra:BAAALAAECgYIBgABLAAECggIIgAOAPcLAA==.',To='Tomaso:BAAALAAECgUIDAAAAA==.',Tr='Travosh:BAAALAADCgcIEAAAAA==.Trolljawoll:BAABLAAECoElAAIVAAgIqR8mCgDeAgAVAAgIqR8mCgDeAgAAAA==.Tríckshòt:BAAALAADCgMIAwAAAA==.Trûlly:BAAALAAECgEIAQAAAA==.',Ts='Tschackeline:BAAALAAECgIIAgAAAA==.',Tu='Tube:BAABLAAECoEUAAISAAcIXg+ZkACbAQASAAcIXg+ZkACbAQAAAA==.Tuxan:BAAALAADCgcICAAAAA==.',Tw='Tweetnonie:BAAALAADCggICAABLAAECggICAAJAAAAAA==.',Ty='Tysal:BAAALAAECgUICQAAAA==.',['Tá']='Tángo:BAABLAAECoEXAAMDAAgI+B8OKwAoAQACAAgI+B/pmABnAQADAAYIpBQOKwAoAQAAAA==.Tángó:BAAALAAECgYIEAABLAAECggIFwADAPgfAA==.',['Tä']='Tängo:BAAALAADCgIIAgAAAA==.',['Tö']='Tödlich:BAABLAAECoEnAAIDAAgITSG/BQD1AgADAAgITSG/BQD1AgAAAA==.',Ur='Uraco:BAAALAADCggIDwAAAA==.',Va='Valc:BAABLAAECoEUAAMfAAYIKQuQHQD5AAAKAAYIBQs3fgBEAQAfAAYIegaQHQD5AAAAAA==.Vanimeril:BAAALAADCgcICwAAAA==.',Ve='Vendariel:BAAALAAECggICAAAAA==.Veranka:BAAALAADCggIDwAAAA==.Verflucht:BAAALAAECggICAAAAA==.Veridisquo:BAAALAAECgYIBgAAAA==.Veteris:BAAALAAECgMIBAABLAAECgYIEwAJAAAAAA==.',Vi='Vitili:BAABLAAECoEqAAIMAAgIcxXAOgDxAQAMAAgIcxXAOgDxAQAAAA==.',Vo='Vogelfrei:BAABLAAECoElAAIcAAgIFBwWFwCDAgAcAAgIFBwWFwCDAgAAAA==.',Vr='Vrisea:BAABLAAECoEbAAIRAAcIJR/JGwB2AgARAAcIJR/JGwB2AgAAAA==.',['Vá']='Válería:BAAALAAECggIAgAAAA==.',['Vâ']='Vânhell:BAAALAAECggICAAAAA==.',Wa='Walküre:BAAALAAECggIEwAAAA==.Warcheeze:BAAALAAECgYIDAAAAA==.Warkuaa:BAAALAAECgIIAgAAAA==.',We='Wengaif:BAABLAAECoEbAAMgAAYIbA+TOgBAAQAgAAYIbA+TOgBAAQAaAAEIoAObZgAaAAAAAA==.',Wh='Whyana:BAAALAAECggICAAAAA==.',Wo='Wollów:BAAALAADCgcIAQAAAA==.Wostone:BAAALAADCgUICAAAAA==.',Wy='Wyonna:BAAALAAECggIEAAAAA==.',['Wû']='Wûrres:BAAALAAECgMIAwAAAA==.',Xa='Xarthos:BAAALAAECgQIBAAAAA==.Xavyo:BAABLAAECoEXAAIBAAYIdxG1bwBxAQABAAYIdxG1bwBxAQABLAAFFAYIFQAbAIUcAA==.',Xo='Xorthas:BAAALAADCgcIBwAAAA==.',Xp='Xperia:BAAALAADCgYIBgABLAAECgYIFQAcAC8ZAA==.',Xy='Xyntias:BAAALAAECgYICQAAAA==.',Yi='Yilaza:BAAALAAECgYIDwAAAA==.',Yo='Yoshimia:BAAALAADCgMIAwAAAA==.Yoshíko:BAAALAAECgcIEAAAAA==.',Za='Zamuel:BAAALAAECgcIDgAAAA==.Zarog:BAAALAADCgIIAgAAAA==.',Ze='Zergling:BAAALAADCgcIBwABLAAECgcIDwAJAAAAAA==.Zexus:BAAALAAECgYIDAABLAAFFAYIFQAbAIUcAA==.',Zi='Zimidir:BAABLAAECoEZAAIIAAgIbQihXgA5AQAIAAgIbQihXgA5AQAAAA==.Ziska:BAAALAAECggICAAAAA==.',Zl='Zlappo:BAAALAADCggIDwABLAAECgYICQAJAAAAAA==.',Zz='Zzornröschen:BAAALAADCgYIBQAAAA==.',['Zâ']='Zâhl:BAAALAADCgYIBgAAAA==.',['Zé']='Zéyróx:BAAALAADCgUIBQAAAA==.',['Âf']='Âffemitwaffe:BAABLAAECoEqAAILAAgILRe3TAD5AQALAAgILRe3TAD5AQAAAA==.',['Æx']='Æxilol:BAAALAADCggICAAAAA==.',['Æz']='Æzrael:BAABLAAECoEbAAMhAAgIWQ0PIgCSAQAhAAgIWQ0PIgCSAQAiAAII4AgAAAAAAAAAAA==.',['Éd']='Éd:BAAALAADCgcIDwAAAA==.',['Él']='Élrond:BAAALAAECggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end