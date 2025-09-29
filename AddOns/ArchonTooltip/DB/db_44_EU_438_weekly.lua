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
 local lookup = {'Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Hunter-BeastMastery','Paladin-Retribution','Druid-Restoration','DemonHunter-Vengeance','Warlock-Demonology','Priest-Holy','Mage-Frost','Paladin-Holy','Paladin-Protection','Monk-Mistweaver','Priest-Shadow','Warrior-Protection','DeathKnight-Blood','Hunter-Marksmanship','Druid-Guardian','Mage-Arcane','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Evoker-Devastation','Warlock-Destruction','Warlock-Affliction','DemonHunter-Havoc','Druid-Balance','Druid-Feral','Mage-Fire','Hunter-Survival','Monk-Brewmaster','Evoker-Augmentation','Evoker-Preservation','Shaman-Enhancement','Rogue-Assassination','Monk-Windwalker','Rogue-Subtlety',}; local provider = {region='EU',realm="Khaz'goroth",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Achandria:BAAALAADCgcIBwAAAA==.',Ag='Agaran:BAABLAAECoEbAAIBAAcIcQxyEwB+AQABAAcIcQxyEwB+AQAAAA==.Agareni:BAAALAADCggICAAAAA==.Agatlan:BAAALAADCggICAAAAA==.',Ai='Aiyana:BAAALAAECgIIAgAAAA==.',Ak='Akkorn:BAABLAAECoEmAAMCAAgInBauPgD7AQACAAgInBauPgD7AQADAAcIJxz0dgAVAQAAAA==.Akoko:BAABLAAECoEaAAIEAAcI/BhuWgDUAQAEAAcI/BhuWgDUAQAAAA==.Akrasa:BAAALAAECgYIBgAAAA==.Akusua:BAAALAAECgMIAwAAAA==.Akyô:BAABLAAECoEZAAIFAAYIwhAYtQBZAQAFAAYIwhAYtQBZAQAAAA==.',Al='Albedo:BAAALAAECgUIBwAAAA==.Aldous:BAAALAAECggICAAAAA==.Alelia:BAAALAAECgYIBQAAAA==.Algonkin:BAABLAAECoEcAAICAAcIvByQLwAwAgACAAcIvByQLwAwAgAAAA==.Alusru:BAAALAADCgcIDgAAAA==.Alyveth:BAAALAADCggICAAAAA==.',Am='Amazonprime:BAAALAADCgYIBgAAAA==.Amydala:BAABLAAECoEVAAIGAAYIOxXsSwB6AQAGAAYIOxXsSwB6AQAAAA==.',An='Ananassaft:BAAALAADCgcIBwABLAAECggIHAAHAJ0QAA==.Andylatte:BAABLAAECoEZAAIIAAcIdB7lDwBmAgAIAAcIdB7lDwBmAgAAAA==.Anelá:BAAALAAECggIEAAAAA==.Anilem:BAAALAADCggIFgAAAA==.Ankka:BAABLAAECoEcAAIJAAcIIg8WWABTAQAJAAcIIg8WWABTAQAAAA==.Anragoth:BAAALAADCgIIAwAAAA==.Anshy:BAAALAADCgYIDAAAAA==.',Ar='Aranthiron:BAAALAAFFAIIAgAAAA==.Arashi:BAACLAAFFIEIAAIKAAIIBBWACwCWAAAKAAIIBBWACwCWAAAsAAQKgTAAAgoACAiOIbYHAAMDAAoACAiOIbYHAAMDAAAA.Arghis:BAAALAADCgcIBwAAAA==.Arketh:BAAALAAECgEIAQAAAA==.Arquilia:BAAALAAECgMIAwAAAA==.Aryju:BAAALAAECgIIBAAAAA==.',As='Asroma:BAABLAAECoEaAAQFAAcInhAujwCdAQAFAAcInhAujwCdAQALAAMIowWfWQCDAAAMAAMIagf/UgBoAAAAAA==.Astá:BAAALAADCgYIBgAAAA==.',Ay='Ayken:BAAALAAECgIIAgAAAA==.Aylene:BAAALAAECgYIEgAAAA==.Ayoveda:BAAALAADCggIDwAAAA==.',Ba='Baaél:BAAALAADCgMIAwAAAA==.Balingar:BAABLAAECoEhAAINAAcIsB4aDgBeAgANAAcIsB4aDgBeAgABLAAFFAMICQAOAGkZAA==.Balthos:BAAALAADCggIDwAAAA==.Bargor:BAABLAAECoEWAAMBAAcIHhSkEgCLAQABAAYIFRakEgCLAQAPAAcIAgwTPwA/AQAAAA==.Bargsh:BAAALAAECgYIEAAAAA==.Barrakuhda:BAABLAAECoEXAAIQAAcILh6aDABaAgAQAAcILh6aDABaAgAAAA==.Bastet:BAAALAADCggIFwAAAA==.',Be='Beef:BAAALAADCggICAAAAA==.Belnik:BAAALAADCgEIAQAAAA==.Belshirasch:BAABLAAECoEtAAMEAAgIqSFHIACmAgAEAAgIqSFHIACmAgARAAMILA9cjACIAAAAAA==.Beratol:BAAALAAECgIIAgAAAA==.Bernhard:BAAALAADCggICAAAAA==.Bertolli:BAAALAAECgQIBgAAAA==.',Bi='Bibiana:BAAALAAECgMIAwAAAA==.Biffbaff:BAABLAAECoEZAAIEAAgIrBnqPwAhAgAEAAgIrBnqPwAhAgABLAAFFAUIDQAQAEsKAA==.Binford:BAABLAAECoEVAAIGAAcIvBwmIQA/AgAGAAcIvBwmIQA/AgAAAA==.Bitanus:BAAALAADCggIDAAAAA==.Bitcooin:BAAALAAECggICwAAAA==.',Bl='Blandeur:BAAALAADCgcIBwAAAA==.Blinck:BAABLAAECoEhAAISAAgIiBdPCgALAgASAAgIiBdPCgALAgAAAA==.Bloodboss:BAAALAADCggIGAAAAA==.Bloodrave:BAAALAAECgMIBAAAAA==.',Bo='Bobjr:BAAALAADCggIGgAAAA==.Boilíes:BAAALAAECgYIDwAAAA==.',Br='Brazorak:BAAALAADCgUIBQAAAA==.Brezelfrau:BAABLAAECoEXAAMKAAcIxhDPLQCiAQAKAAcIxhDPLQCiAQATAAIIEAeR1QBNAAAAAA==.Brigannitus:BAAALAADCgcIBwAAAA==.Brille:BAABLAAECoEVAAMBAAgIPghuGAA8AQABAAcIuAhuGAA8AQAUAAIIoQX5zgA6AAAAAA==.Bron:BAAALAAECgQIBAAAAA==.Brothax:BAABLAAECoEaAAIIAAcIERqaGQAOAgAIAAcIERqaGQAOAgAAAA==.Brutalon:BAABLAAECoEVAAIUAAcIOwzFZQCJAQAUAAcIOwzFZQCJAQAAAA==.Bröcker:BAAALAADCggICAAAAA==.',Bu='Budi:BAAALAADCgcIBgAAAA==.Butterblume:BAAALAADCgcICgAAAA==.',['Bá']='Báileý:BAAALAAECggIEAAAAA==.',['Bí']='Bíbì:BAABLAAECoEWAAMVAAcIcRMSgADBAQAVAAcIWhMSgADBAQAWAAMIUAvCQQCeAAAAAA==.',Ca='Caesar:BAABLAAECoEXAAIDAAgIXxFtOQD3AQADAAgIXxFtOQD3AQAAAA==.Caevyia:BAAALAADCgYIBgABLAAECgcICwAXAAAAAA==.Calarí:BAAALAADCggIEAAAAA==.Caleri:BAAALAADCggICAAAAA==.',Ce='Cersei:BAAALAAECgQIBgAAAA==.Cerya:BAABLAAECoEUAAIVAAgITREffwDDAQAVAAgITREffwDDAQAAAA==.',Ch='Chaneira:BAAALAADCgYIBgAAAA==.Chojî:BAAALAAECggICgAAAA==.Chopal:BAAALAAECgcIDgAAAA==.Christophêr:BAAALAADCgEIAQAAAA==.',Ci='Cicutaviros:BAAALAADCggIGgAAAA==.Ciphoria:BAAALAADCgIIAgAAAA==.',Co='Cool:BAAALAAECgQICgAAAA==.Cordo:BAAALAADCgcIBgABLAADCggIIwAXAAAAAA==.',Cr='Cresnik:BAAALAADCgYIBgAAAA==.Crownclown:BAAALAAECgMIAwAAAA==.Cruelbrew:BAAALAAECgEIAQABLAAECggIGAACAO4iAA==.Crusadé:BAABLAAECoEWAAIFAAYIURfdigCmAQAFAAYIURfdigCmAQAAAA==.',Cu='Curry:BAAALAADCggICQAAAA==.',Da='Daaria:BAAALAADCgYIDgAAAA==.Darasis:BAAALAAECgcICgAAAA==.Dariaa:BAAALAADCgYIBwAAAA==.Darkdracon:BAAALAAECggICAAAAA==.Darkivoker:BAABLAAECoEbAAIYAAgI1BIRIAD9AQAYAAgI1BIRIAD9AQAAAA==.Darkmask:BAABLAAECoEkAAIVAAgIUSByHgDYAgAVAAgIUSByHgDYAgAAAA==.Darkvaderior:BAAALAAECgEIAQAAAA==.',De='Deracty:BAAALAAECgUIDQAAAA==.Dergraue:BAAALAAECgEIAQAAAA==.Desmodiaa:BAAALAAECggICAAAAA==.Destiný:BAAALAAECggICgAAAA==.Deuzen:BAAALAADCggIEQAAAA==.Deximo:BAAALAAECgMIBwAAAA==.',Dj='Djánady:BAAALAAECgYIDwAAAA==.',Do='Dogath:BAABLAAECoEvAAMZAAgIRyE6FADzAgAZAAgIRyE6FADzAgAIAAEIywM/iQA0AAAAAA==.Doktorin:BAAALAADCgcIBwAAAA==.Dolros:BAAALAADCggIDwAAAA==.Domihl:BAACLAAFFIEKAAIUAAUIOh63BAACAgAUAAUIOh63BAACAgAsAAQKgScAAhQACAiVJv8BAIIDABQACAiVJv8BAIIDAAAA.Donzar:BAABLAAECoEhAAIRAAgI7x6XDwDZAgARAAgI7x6XDwDZAgAAAA==.Dotterpepper:BAACLAAFFIEKAAIZAAUIFhkuCgDOAQAZAAUIFhkuCgDOAQAsAAQKgRkABBkACAiNI2kRAAUDABkACAjnIWkRAAUDABoABAhXDxodAO0AAAgAAgjIGlNoAJ0AAAAA.',Du='Duretta:BAAALAAECgEIAQAAAA==.',Dw='Dwahe:BAAALAADCggIGAAAAA==.',['Dä']='Dämonjägerin:BAABLAAECoEbAAIbAAcIzAzmlgBrAQAbAAcIzAzmlgBrAQAAAA==.Däumeling:BAAALAAECgQICwAAAA==.',Ec='Eclipsae:BAAALAADCggICAAAAA==.Eclipsaedk:BAAALAADCggICAAAAA==.',Eg='Eggssqueezer:BAAALAAECgYICgAAAA==.Egor:BAABLAAECoEdAAIcAAcI/R4NHgBFAgAcAAcI/R4NHgBFAgAAAA==.',El='Elarwyn:BAAALAADCggICAAAAA==.Eliaflo:BAAALAAECgEIAQAAAA==.Elizy:BAAALAADCggICAAAAA==.Eloe:BAAALAAECgIIBAAAAA==.Eluflo:BAAALAADCggICAAAAA==.Elundir:BAAALAAECgEIAQAAAA==.',Em='Empty:BAAALAADCgcIEAAAAA==.',Es='Esariel:BAAALAADCggICAAAAA==.Estirella:BAABLAAECoEfAAIEAAcIlx/rLwBcAgAEAAcIlx/rLwBcAgAAAA==.',Ex='Exor:BAAALAADCggICQAAAA==.',Fa='Faelis:BAAALAAFFAEIAQAAAA==.Farah:BAAALAAECgQICgAAAA==.',Fe='Feedy:BAAALAAECggIEQAAAQ==.Feedyshaman:BAAALAAECgYIBwABLAAECggIEQAXAAAAAQ==.Feigndeath:BAABLAAECoEfAAMRAAcILx85HgBdAgARAAcIGB85HgBdAgAEAAEIYyGOEAE7AAAAAA==.Fellpfötchen:BAAALAAECgYIEAAAAA==.Feuergeil:BAAALAAECgYICQAAAA==.Feysan:BAAALAAECgEIAQAAAA==.',Fi='Firesmither:BAAALAADCgcICAABLAAECggIHAAHAJ0QAA==.',Fj='Fjölnir:BAAALAADCggIDwABLAAFFAUIDQAQAEsKAA==.',Fl='Flitzablitza:BAAALAAECgYIBgAAAA==.Floryel:BAAALAAECgcIDQAAAA==.',Fo='Fosja:BAABLAAECoEnAAIHAAgIIQ6QIAB5AQAHAAgIIQ6QIAB5AQAAAA==.',Fr='Freakazoid:BAAALAADCggICAABLAAECgYIDQAXAAAAAA==.Frieren:BAABLAAECoEaAAIKAAgI6h6DDAC5AgAKAAgI6h6DDAC5AgAAAA==.',Fu='Fubas:BAAALAADCggICAAAAA==.',Fy='Fyneman:BAAALAADCgQICAABLAAECggIJwAEAJUfAA==.',['Fû']='Fûßel:BAAALAADCggIDwAAAA==.',Ga='Gazoz:BAAALAADCgYIDAAAAA==.',Ge='Geîßlêr:BAAALAAECgYIBgAAAA==.',Gh='Ghorinchai:BAABLAAECoEaAAIPAAcI9gnRQgAtAQAPAAcI9gnRQgAtAQAAAA==.Ghostlord:BAAALAADCgIIAgAAAA==.',Gl='Glazed:BAAALAAECgEIAQAAAA==.',Go='Gorgonax:BAABLAAECoEjAAITAAgIXBo5MwBhAgATAAgIXBo5MwBhAgAAAA==.',Gr='Grandel:BAABLAAECoEYAAIFAAcIDxdGfADBAQAFAAcIDxdGfADBAQAAAA==.Grantel:BAACLAAFFIEJAAITAAMI/hjZFwAEAQATAAMI/hjZFwAEAQAsAAQKgTMAAhMACAgFI1ETAAEDABMACAgFI1ETAAEDAAAA.Greenhornetx:BAAALAAECgIIAgAAAA==.Greyfox:BAAALAAECgUIBwAAAA==.Griimmjow:BAAALAADCgQIBQAAAA==.Grondarn:BAAALAAECgUIBwAAAA==.Grüneflo:BAAALAADCggICAAAAA==.',Gu='Guccidruid:BAAALAADCggICwAAAA==.Guillaume:BAAALAAECgcIEQAAAA==.Gumble:BAAALAADCgcIBwAAAA==.Gutemine:BAAALAADCggICAAAAA==.',Gw='Gweñ:BAAALAAECgIIAgAAAA==.Gwynny:BAABLAAECoEVAAIOAAgIQxKoLAABAgAOAAgIQxKoLAABAgAAAA==.',Ha='Halprion:BAAALAAECgMIAwABLAAECgUIBQAXAAAAAA==.Halríon:BAAALAAECgUIBQAAAA==.Hanse:BAABLAAECoEhAAICAAcIKhkGWwCnAQACAAcIKhkGWwCnAQAAAA==.Harope:BAABLAAECoEaAAIEAAcIUR/AMwBNAgAEAAcIUR/AMwBNAgAAAA==.',He='Heal:BAAALAAECgIIAgAAAA==.Heilixblechl:BAACLAAFFIEIAAIFAAUIOw7NBgCeAQAFAAUIOw7NBgCeAQAsAAQKgRYAAgUACAhSHt8kALoCAAUACAhSHt8kALoCAAAA.Heinzstoff:BAAALAAECgMIAwAAAA==.Hexana:BAAALAAECgYIEgAAAA==.',Hi='Hitatshi:BAAALAAECgIIAgAAAA==.',Ho='Hobb:BAABLAAECoEpAAIdAAgIGR/YCQCUAgAdAAgIGR/YCQCUAgAAAA==.Horat:BAABLAAECoEcAAIIAAcIBh9uDQCBAgAIAAcIBh9uDQCBAgAAAA==.Horstili:BAAALAADCgIIAQAAAA==.',Hu='Huntax:BAAALAAECgEIAQAAAA==.',Ia='Iacta:BAAALAAECgMIAwAAAA==.',Ig='Igñaz:BAAALAADCgcIBwABLAAECggIJwAEAJUfAA==.',Im='Imreg:BAACLAAFFIEJAAMOAAMIaRnDDAD4AAAOAAMIaRnDDAD4AAAJAAIIPgxuLwB3AAAsAAQKgSkAAw4ACAjcI4IJAB8DAA4ACAjcI4IJAB8DAAkAAQizIseXAGEAAAAA.',In='Ingobräu:BAAALAAECgMIBgAAAA==.Ingvâr:BAABLAAECoFHAAIUAAgIpBXePAAQAgAUAAgIpBXePAAQAgAAAA==.Intara:BAAALAADCggICAAAAA==.Inâste:BAAALAADCgMIAwAAAA==.',Io='Iolan:BAABLAAECoEsAAQTAAgI9h34PgAxAgATAAgIbRf4PgAxAgAKAAcIZBgtNwBxAQAeAAEIIwNfIQAmAAAAAA==.',Ir='Ireth:BAABLAAECoEiAAIFAAgI/R9HIgDHAgAFAAgI/R9HIgDHAgAAAA==.',Iv='Ivanâ:BAAALAAECgcIDAAAAA==.',Ja='Jabao:BAAALAADCggIEAAAAA==.Jaheirá:BAAALAADCggICAAAAA==.Jannisan:BAAALAADCgcICwAAAA==.Januschandra:BAAALAAECgYICQAAAA==.Jazeerah:BAABLAAECoEaAAMfAAcIpxUcCQD7AQAfAAcIpxUcCQD7AQAEAAIIcQo/BgFRAAAAAA==.',Je='Jedsia:BAAALAAECgYIDgAAAA==.Jegor:BAAALAADCggIEAAAAA==.Jenolix:BAAALAADCggICAAAAA==.',Jo='Jolindchen:BAAALAADCgcIEwAAAA==.Jonny:BAAALAAECgEIAQAAAA==.Jormund:BAAALAAECgYIEQAAAA==.Josch:BAAALAADCgcIBwAAAA==.',Ju='Juppy:BAAALAAECgQICwAAAA==.',['Jä']='Jägermeistär:BAAALAADCgUIBQAAAA==.Jägno:BAAALAAECgQIBAAAAA==.',Ka='Kal:BAAALAADCgQIAQAAAA==.Kalakaman:BAAALAAECgYIDQAAAA==.Kalandris:BAABLAAECoEbAAMGAAgIjhwcFACWAgAGAAgIjhwcFACWAgAcAAUIRwmfZADiAAAAAA==.Kalimora:BAAALAADCgYIBgAAAA==.Kalma:BAAALAAECgcIDwAAAA==.Karashi:BAAALAAECgMIAwAAAA==.Katryn:BAABLAAECoEbAAIJAAcILiQqFACuAgAJAAcILiQqFACuAgAAAA==.',Ke='Kemadrell:BAAALAADCgIIAgAAAA==.Ketarii:BAAALAAECgIIAgAAAA==.',Kh='Khalessi:BAAALAAECgMIBgAAAA==.Khazrak:BAABLAAECoEqAAIQAAgI+hY3EgD4AQAQAAgI+hY3EgD4AQAAAA==.',Ki='Killbienchen:BAAALAADCgYIEAAAAA==.Killja:BAAALAAECgYIEQAAAA==.',Kl='Kleineflo:BAABLAAECoEcAAIMAAgIlRZwFgAUAgAMAAgIlRZwFgAUAgAAAA==.Klinura:BAABLAAECoEkAAIOAAgIpCPABgA7AwAOAAgIpCPABgA7AwAAAA==.',Ko='Kohl:BAAALAAECgUIBwABLAAFFAUIDQAgANEQAA==.Konfuzia:BAAALAAECgcIBwAAAA==.Konschita:BAAALAADCggIDgAAAA==.',Ku='Kudelmudel:BAAALAADCgcIDAAAAA==.',Kv='Kvothé:BAAALAAECgcIEAAAAA==.',Ky='Kynia:BAAALAAECgIIAgAAAA==.Kyora:BAAALAADCgYIBgAAAA==.Kyriana:BAAALAAECgMIAwAAAA==.Kyriè:BAACLAAFFIESAAIFAAUIFh5eBgCrAQAFAAUIFh5eBgCrAQAsAAQKgSwAAgUACAggJloDAHoDAAUACAggJloDAHoDAAAA.',['Kí']='Kílly:BAAALAADCggICQAAAA==.',['Kî']='Kîmba:BAAALAAECgUIEQAAAA==.',['Kö']='Königin:BAAALAADCgEIAQAAAA==.',['Kÿ']='Kÿra:BAABLAAECoEgAAQhAAcItQ8MCwB2AQAhAAcIxg4MCwB2AQAiAAYIsQ9cHgBBAQAYAAMIGQi3VwBOAAAAAA==.',La='Lakotamoon:BAABLAAECoEaAAIGAAcI8iD4GABxAgAGAAcI8iD4GABxAgAAAA==.Laksarshaman:BAAALAADCggICAABLAAECggIFwAGAJIQAA==.Lamagra:BAAALAAECgYIBgAAAA==.Lambda:BAABLAAECoEcAAMCAAcI3R4iLgA1AgACAAcI3R4iLgA1AgADAAMInxEPiQC9AAAAAA==.Lanaa:BAAALAAECgYIBwAAAA==.Laudat:BAAALAAECgYIDgAAAA==.',Le='Lerino:BAAALAAECgMIAwAAAA==.Levara:BAAALAAECgIIBAAAAA==.',Li='Lillibeth:BAAALAAECgQICgAAAA==.Lillyeth:BAAALAADCgUIBQAAAA==.Liteira:BAAALAADCggICAABLAAECggIGwAOAFgfAA==.Lithzua:BAAALAADCgEIAQAAAA==.',Lo='Lowny:BAAALAAFFAEIAQAAAA==.',Lu='Luflo:BAAALAADCggICAAAAA==.Lumananti:BAABLAAECoEjAAIDAAgIMRH4OwDrAQADAAgIMRH4OwDrAQAAAA==.Luzilla:BAAALAADCgYICwAAAA==.',Ly='Lynn:BAAALAAECgMIAwAAAA==.',['Lò']='Lòdor:BAABLAAECoEiAAIRAAgIwRxiGgB8AgARAAgIwRxiGgB8AgAAAA==.',Ma='Maddrock:BAAALAAECgYIDgAAAA==.Maeya:BAAALAADCggIDgAAAA==.Maggye:BAAALAAECgUIDgAAAA==.Magya:BAAALAADCgQIBAAAAA==.Mahoney:BAAALAAECgQIBAAAAA==.Maiko:BAACLAAFFIEHAAMEAAUIqBsSCACVAQAEAAUIqBsSCACVAQARAAEIQRbmKwBFAAAsAAQKgScAAwQACAi8I9gPAAYDAAQACAi8I9gPAAYDABEABQi7HEFFAIgBAAAA.Makirito:BAABLAAECoEeAAIjAAgIohGIDAAAAgAjAAgIohGIDAAAAgAAAA==.Maleniia:BAABLAAECoEdAAIkAAcIHxC0KgC6AQAkAAcIHxC0KgC6AQAAAA==.Malfina:BAAALAADCgYIBgAAAA==.Manin:BAAALAADCgcIBwAAAA==.Mankie:BAAALAAECggIEgAAAA==.Mapku:BAAALAADCgcIBwAAAA==.Marinat:BAAALAAECgcIDgAAAA==.Marvîn:BAAALAAECgEIAQAAAA==.Matala:BAAALAADCggICAAAAA==.Mazekeen:BAAALAADCggICAAAAA==.Mazorga:BAAALAADCggIBwAAAA==.',Mc='Mckaiver:BAAALAADCgcIDgAAAA==.',Me='Meidrolyn:BAAALAAECgMIAwAAAA==.Mekhet:BAABLAAECoEZAAIEAAcImwodmQBMAQAEAAcImwodmQBMAQAAAA==.Meliodas:BAABLAAECoEkAAIbAAgInxvoKwCKAgAbAAgInxvoKwCKAgAAAA==.Melokima:BAACLAAFFIELAAITAAQIFw8REwA4AQATAAQIFw8REwA4AQAsAAQKgSQAAhMACAgiICsmAJ4CABMACAgiICsmAJ4CAAAA.Melokipa:BAAALAADCgcIAQABLAAFFAQICwATABcPAA==.Merimmac:BAAALAAECgMIBAAAAA==.',Mi='Midea:BAAALAADCgYIEgAAAA==.Miiezi:BAAALAAECgUICwAAAA==.Miiggel:BAAALAAECgcIEgAAAA==.Miiquella:BAAALAADCgYIBgAAAA==.Mimíru:BAABLAAECoEdAAIUAAcIDiWhFQDoAgAUAAcIDiWhFQDoAgAAAA==.Minschi:BAAALAAECgIIBAAAAA==.Miracolie:BAAALAADCgQIBQAAAA==.Miyama:BAAALAAECgEIAwAAAA==.',Mj='Mjöd:BAAALAADCggICQAAAA==.Mjöll:BAACLAAFFIENAAIQAAUISwolBABSAQAQAAUISwolBABSAQAsAAQKgSkAAxAACAg8HpMIAK8CABAACAg8HpMIAK8CABUAAghKBeY2AWAAAAAA.',Mo='Mokkadin:BAAALAADCgcICAAAAA==.Momli:BAAALAAECgIIAgAAAA==.Moonpiie:BAAALAADCgYIBgAAAA==.',Mu='Muted:BAABLAAECoEYAAIVAAgIriSHCgA/AwAVAAgIriSHCgA/AwAAAA==.',['Mì']='Mìssery:BAAALAADCgcICAAAAA==.',['Mí']='Mízumeh:BAACLAAFFIEKAAICAAUIOA5HCABXAQACAAUIOA5HCABXAQAsAAQKgScAAgIACAggHbgbAIkCAAIACAggHbgbAIkCAAAA.',['Mî']='Mîâ:BAAALAAECgIIAgAAAA==.',Na='Naid:BAAALAAECgEIAQAAAA==.Namdrahil:BAAALAAECggIEwAAAA==.Nanoc:BAABLAAECoEcAAIkAAcI6ANKRAAeAQAkAAcI6ANKRAAeAQAAAA==.Nargula:BAAALAAECgMIAgAAAA==.Narnos:BAACLAAFFIENAAIgAAUI0RDXBAB0AQAgAAUI0RDXBAB0AQAsAAQKgSUAAiAACAjUH80JAJ8CACAACAjUH80JAJ8CAAAA.Narthafelaer:BAAALAAECgQIBgAAAA==.',Ne='Nekrimah:BAAALAADCgcICwABLAAECggIGgAEALkQAA==.Nelija:BAABLAAECoEsAAIlAAgIpBvaEQBpAgAlAAgIpBvaEQBpAgAAAA==.Neliâ:BAAALAADCgcIDgAAAA==.Nerdanel:BAAALAAECgYIBgAAAA==.',Ng='Ngmui:BAAALAAECgIIAgAAAA==.',Ni='Niva:BAAALAAECgMIBwABLAAECggIIgASAFAYAA==.',No='Nodien:BAAALAADCgYIBgAAAA==.Norah:BAAALAADCggICAABLAAECggIGgAKAOoeAA==.Norbu:BAAALAADCggICAAAAA==.Nortem:BAAALAADCgYIBgAAAA==.Notopmodel:BAAALAADCgcIBwAAAA==.Nowiel:BAAALAAECgQICgAAAA==.Noémí:BAAALAAECgMIAQAAAA==.',Ny='Nycky:BAAALAAECgIIBgAAAA==.Nyxiana:BAAALAAECgIIAgAAAA==.',['Nâ']='Nârmôrâ:BAAALAAECgIIAgAAAA==.',['Nó']='Nórdig:BAAALAAECgMICAAAAA==.',Ok='Okaninas:BAABLAAECoEVAAIcAAYIVw4YUAA9AQAcAAYIVw4YUAA9AQAAAA==.Okiidokii:BAAALAADCggICAAAAA==.',Ol='Oldenburger:BAAALAAECgUIBQAAAA==.',On='Onibi:BAAALAADCggIEgAAAA==.',Op='Opiliones:BAABLAAECoEWAAIJAAcIsQuGVwBWAQAJAAcIsQuGVwBWAQAAAA==.',Ot='Ottoman:BAAALAAECgIIAwAAAA==.',Pa='Paladimo:BAABLAAECoEeAAIFAAcIzB82NAB6AgAFAAcIzB82NAB6AgAAAA==.Palahon:BAAALAADCggIDgAAAA==.Paldragon:BAACLAAFFIEMAAIYAAQItCQ/BQCnAQAYAAQItCQ/BQCnAQAsAAQKgR0AAhgACAiqJYUCAF8DABgACAiqJYUCAF8DAAAA.Palmonk:BAABLAAECoEaAAIgAAcIphzaDgBBAgAgAAcIphzaDgBBAgABLAAFFAQIDAAYALQkAA==.Palrob:BAAALAAECgUICwAAAA==.Paly:BAAALAAECgMIBQAAAA==.Panchoo:BAAALAADCgEIAQAAAA==.Papitar:BAAALAADCggIKgAAAA==.Pawny:BAACLAAFFIEKAAIGAAUI6gsOBgBhAQAGAAUI6gsOBgBhAQAsAAQKgR8AAgYACAhzFlAxAOwBAAYACAhzFlAxAOwBAAAA.Paymaster:BAAALAADCgcICQAAAA==.',Pe='Perigrim:BAAALAAECggIBQAAAA==.',Ph='Phéo:BAAALAADCggICAAAAA==.',Po='Poi:BAAALAADCgYIBAABLAAECgcIFAAXAAAAAQ==.Pokus:BAABLAAECoEaAAIKAAcISRzmFQBMAgAKAAcISRzmFQBMAgAAAA==.',Pr='Princartar:BAAALAAECgQIBAAAAA==.Princartur:BAAALAAECgcICAAAAA==.',Pu='Pups:BAAALAAECgYICAAAAA==.Puzzi:BAAALAAECgQICgAAAA==.',Qh='Qhuinnta:BAAALAAECgQIBQAAAA==.',Qu='Quaigón:BAAALAAECgUIBQABLAAECggIIwADADERAA==.Quirin:BAABLAAECoEaAAIEAAgIuRBzaACyAQAEAAgIuRBzaACyAQAAAA==.Qumaira:BAAALAAECgcIEgAAAA==.',Ra='Rafinia:BAABLAAECoEgAAIRAAcIsRL5QwCNAQARAAcIsRL5QwCNAQAAAA==.Rahgam:BAABLAAECoEYAAIEAAcIRA0/jgBhAQAEAAcIRA0/jgBhAQAAAA==.Rantazía:BAAALAAECgYIEQAAAA==.Ravanna:BAAALAAECgQIBAAAAA==.Raxano:BAAALAAECggIEgAAAA==.',Re='Reckless:BAAALAADCggIHQAAAA==.Reehal:BAAALAADCggICAAAAA==.Reez:BAAALAAECgIIBAAAAA==.Rekkthal:BAAALAAECggICAAAAA==.Rekzi:BAAALAAECggIEAAAAQ==.Renermo:BAAALAADCgYIBwAAAA==.Repecx:BAAALAAECgcIEwAAAA==.',Rh='Rhin:BAAALAADCggICAAAAA==.',Ri='Riecka:BAAALAADCgcIDQAAAA==.Rigosmage:BAAALAAECggICAAAAA==.Rimá:BAABLAAECoEUAAIGAAYIZAc8fQDiAAAGAAYIZAc8fQDiAAAAAA==.Rishu:BAAALAAECgIIAQAAAA==.Rivendare:BAABLAAECoEYAAMWAAYIOxdGIQCZAQAWAAYIVRZGIQCZAQAVAAUIHBHa2QApAQAAAA==.',Ro='Robìn:BAAALAADCgQIBAAAAA==.Rogart:BAABLAAECoEnAAIEAAgIlR//HwCnAgAEAAgIlR//HwCnAgAAAA==.Roidheinz:BAAALAAECgcICQAAAA==.Romuluss:BAAALAADCggICAAAAA==.Rotàr:BAAALAADCggICAABLAAECggIJwAEAJUfAA==.Roódhooft:BAAALAADCgYICQAAAA==.',Ru='Rufega:BAAALAADCggIEwAAAA==.',Ry='Ryft:BAACLAAFFIEIAAMRAAMISxe6DADkAAARAAMISxe6DADkAAAEAAII1BXFLACOAAAsAAQKgSMAAxEACAi8JaMIABkDABEACAhjJKMIABkDAAQACAiBHTYkAJECAAAA.Ryftdh:BAAALAADCgYIBgABLAAFFAMICAARAEsXAA==.Ryftdk:BAAALAADCggICAABLAAFFAMICAARAEsXAA==.Ryouta:BAAALAADCggIHAAAAA==.Ryzz:BAAALAAECgIIDwAAAA==.',Sa='Saalem:BAABLAAECoEjAAMaAAgI6RvZAwCuAgAaAAgI6RvZAwCuAgAIAAEIHBa+fwBFAAAAAA==.Salenya:BAAALAAECgEIAQAAAA==.Saliva:BAABLAAECoEcAAImAAgIPBHnEgDqAQAmAAgIPBHnEgDqAQAAAA==.Salvatôre:BAAALAADCgcIEAAAAA==.Samarédariò:BAABLAAECoEsAAMLAAgI0B67CwCgAgALAAcI8CK7CwCgAgAFAAgIgAbhwABEAQABLAADCggICAAXAAAAAA==.Sarkhan:BAAALAAECgMICAAAAA==.Saturno:BAAALAAECgEIAQAAAA==.',Sc='Schlafmütze:BAABLAAECoE2AAINAAgIvB0PDwBQAgANAAgIvB0PDwBQAgAAAA==.Schmobbit:BAAALAAECgYIEwAAAA==.Schnullerfee:BAAALAADCgYIBgAAAA==.Schoko:BAAALAAECggIDwAAAA==.',Se='Sealseven:BAAALAAECgYICwAAAA==.Seasyntix:BAAALAAECgcIBwAAAA==.Sensî:BAAALAAECgYIBgAAAA==.Sentenza:BAAALAADCgcIBwAAAA==.Seraphiná:BAABLAAECoEbAAIMAAcI+gzmMgA2AQAMAAcI+gzmMgA2AQAAAA==.',Sh='Shadow:BAABLAAECoEYAAIOAAgIAQ+GWgAhAQAOAAgIAQ+GWgAhAQAAAA==.Shaminski:BAABLAAECoEbAAICAAgI3BYdOgAKAgACAAgI3BYdOgAKAgAAAA==.Shaminás:BAAALAADCgQIBAAAAA==.Shamús:BAAALAAECgEIAgAAAA==.Sharold:BAAALAAECgQIBwAAAA==.Shayvin:BAAALAAECgcICwAAAA==.Sheng:BAAALAAECgcIFAAAAQ==.Shermond:BAAALAAECgUICAABLAAECggIRwAUAKQVAA==.',Si='Silivren:BAABLAAECoEcAAIFAAgIvxnwPgBUAgAFAAgIvxnwPgBUAgAAAA==.Sinavornul:BAAALAAECgMIBAAAAA==.',Sk='Skahr:BAAALAAECgcIEgAAAA==.Skillidan:BAABLAAECoEmAAIbAAgIhCR3CABOAwAbAAgIhCR3CABOAwAAAA==.',Sl='Sleimer:BAABLAAECoEXAAIUAAYIkhfvVAC6AQAUAAYIkhfvVAC6AQAAAA==.Slemmingen:BAAALAAECgIIBAAAAA==.',Sm='Smoke:BAABLAAECoEaAAIFAAgItBc4PgBWAgAFAAgItBc4PgBWAgAAAA==.',Sn='Snabbräv:BAAALAADCggIGQAAAA==.',So='Sodiac:BAABLAAECoEWAAIDAAcIchn1MgAVAgADAAcIchn1MgAVAgAAAA==.Sonnaxt:BAAALAAECgQICAAAAA==.Soular:BAAALAADCggIDwAAAA==.',Sp='Spear:BAAALAADCgUIBQAAAA==.Spiritmoon:BAABLAAECoEXAAIcAAgIIg5IRABxAQAcAAgIIg5IRABxAQAAAA==.',St='Strubpel:BAABLAAECoEcAAMZAAgIthpMLgBbAgAZAAgI1BlMLgBbAgAaAAYIlBRWDwCfAQABLAAECggIJgACAJwWAA==.Struppel:BAAALAAECgEIAQABLAAECggIJgACAJwWAA==.Struppeldrac:BAAALAAECgYIBgABLAAECggIJgACAJwWAA==.Struppelmage:BAAALAAECgYIBgAAAA==.Stryze:BAAALAAECgYIDQAAAA==.Strîpe:BAAALAAECggIEAAAAA==.Stôrm:BAAALAAECggIDAAAAA==.',Sy='Synoumdk:BAAALAADCgQIBAAAAA==.',['Sà']='Sàly:BAAALAAECgMIBgAAAA==.',['Sâ']='Sâlyria:BAABLAAECoEhAAIHAAcIwBzEEAAtAgAHAAcIwBzEEAAtAgAAAA==.Sângân:BAAALAAECgEIAQAAAA==.',['Sè']='Sèrafima:BAAALAADCggICAAAAA==.',['Sí']='Síllvy:BAAALAAECgYIBgAAAA==.Sína:BAAALAADCgcIBwAAAA==.',['Sî']='Sîndy:BAABLAAECoEhAAIKAAcInxS9KgCzAQAKAAcInxS9KgCzAQAAAA==.',Ta='Tamós:BAAALAAECgQIDwAAAA==.Tareya:BAABLAAECoEwAAIHAAgIYB/nCACqAgAHAAgIYB/nCACqAgAAAA==.Tarian:BAAALAAECgYIBgAAAA==.Tarija:BAAALAADCgcIBwAAAA==.Tatsu:BAAALAAECgYIDQAAAA==.Tayumi:BAAALAADCggIEAABLAAECgcIHwAHAFsbAA==.',Te='Temeraire:BAAALAAECgEIAQAAAA==.Terranof:BAAALAADCggIEQAAAA==.Teteia:BAABLAAECoEfAAIHAAcIWxs1EQAnAgAHAAcIWxs1EQAnAgAAAA==.',Th='Thurs:BAAALAAECgYIBgAAAA==.Thôros:BAAALAADCggIFwAAAA==.',Ti='Tianyi:BAAALAAECggICAAAAA==.',Tj='Tjalf:BAAALAADCggICgAAAA==.Tjone:BAABLAAECoEeAAIGAAcI7ht/IgA3AgAGAAcI7ht/IgA3AgAAAA==.',To='Tobdari:BAAALAAECgQIBAAAAA==.Todespfote:BAAALAAECgMIAwABLAAECgYIEAAXAAAAAA==.Toffifee:BAAALAAECgYICgAAAA==.Toxicslayer:BAAALAADCggICAAAAA==.',Tr='Tratoss:BAAALAAECgUIBQAAAA==.Tratôss:BAAALAADCggICAAAAA==.Trazyn:BAAALAAECgMIAwAAAA==.Tristesse:BAAALAAECgEIAQAAAA==.Trolleck:BAAALAAECggICAAAAA==.Tràtoss:BAAALAAECggIBgAAAA==.',Ty='Tyrøck:BAAALAAECgYICgAAAA==.',Tz='Tzana:BAABLAAECoEXAAINAAYIBRLzJQBBAQANAAYIBRLzJQBBAQAAAA==.',Ur='Urtnuk:BAAALAADCgUIBQAAAA==.',Ve='Velari:BAAALAAECgYIDAAAAA==.Venómi:BAAALAAECgQICAAAAA==.Veylor:BAAALAAECggICAAAAA==.',Vi='Vitalivoid:BAAALAAECgIIAwAAAA==.Vitalux:BAAALAADCgEIAQAAAA==.Viviane:BAAALAADCgUIBQAAAA==.',Vo='Voidstabberx:BAAALAAECgIIAgAAAA==.Vorlord:BAAALAAECgYICQAAAA==.Vorrac:BAABLAAECoEZAAIRAAcIzQn2cgDkAAARAAcIzQn2cgDkAAAAAA==.',Vu='Vuridan:BAABLAAECoEnAAIbAAgIWyMYEwANAwAbAAgIWyMYEwANAwAAAA==.',Vy='Vykos:BAABLAAECoEjAAIQAAgIkxa4EQAAAgAQAAgIkxa4EQAAAgAAAA==.Vyna:BAAALAAECgMIAwABLAAFFAUICwAkABAeAA==.',['Vä']='Västeräs:BAAALAAECgIIBAAAAA==.',Wa='Wadenbeiser:BAAALAAECggICAABLAAFFAUICgADAJEPAA==.Walero:BAAALAADCgcIBwAAAA==.Walkingend:BAAALAADCgIIAgAAAA==.Walpri:BAABLAAECoEqAAIJAAgICh3bFwCTAgAJAAgICh3bFwCTAgAAAA==.',We='Weezy:BAAALAAECgYICwAAAA==.Wern:BAAALAAECgQIBAAAAA==.',Wi='Wizzker:BAAALAAECggIEQAAAA==.Wizzum:BAAALAAECggICAABLAAECggIEQAXAAAAAA==.Wizzârdman:BAAALAAECggIDwAAAA==.',Wo='Wolfj:BAAALAADCgcIBwAAAA==.',Xa='Xanty:BAAALAADCgQIBAAAAA==.Xarfei:BAABLAAECoEVAAIQAAYI5RjqHABoAQAQAAYI5RjqHABoAQABLAAECggILQAEAKkhAA==.',Xe='Xerxes:BAAALAADCggIDgAAAA==.',Xi='Xidira:BAAALAAECgYICAAAAA==.Ximerâ:BAAALAAECgEIAQAAAA==.',Xy='Xya:BAACLAAFFIELAAMkAAUIEB4BAQACAgAkAAUIEB4BAQACAgAmAAEISgmWFwBAAAAsAAQKgS8AAyQACAiCJBgDAEMDACQACAiCJBgDAEMDACYABAgPHBgkAEQBAAAA.',['Xá']='Xálius:BAABLAAECoEYAAIcAAgI+R/fEQC4AgAcAAgI+R/fEQC4AgAAAA==.',Ya='Yalendriel:BAAALAAECggIEAAAAA==.Yanê:BAAALAADCgcIBwAAAA==.',Yi='Yingyâng:BAAALAADCgcIBwABLAAECggIJwAEAJUfAA==.',Yo='Yokai:BAAALAAECgQICwAAAA==.Yokozuna:BAAALAADCgcICAAAAA==.',Yu='Yui:BAAALAADCgIIAgAAAA==.',Yv='Yvionstraza:BAAALAAECgMIBQAAAA==.',Za='Zaladríel:BAAALAADCgQIBAAAAA==.Zally:BAAALAADCgIIAgAAAA==.Zana:BAAALAAECgIIBAABLAAECgYIFwANAAUSAA==.Zanla:BAAALAAECgQICAABLAAECgYIFwANAAUSAA==.Zarøn:BAAALAAECgEIAQAAAA==.Zauberfló:BAAALAADCggICAAAAA==.',Ze='Zephirah:BAAALAAECgYIBwAAAA==.Zerano:BAAALAADCggIDgAAAA==.',Zi='Zibbi:BAAALAADCgMIAwAAAA==.',Zo='Zod:BAABLAAECoEaAAIkAAcIMw/qKwCyAQAkAAcIMw/qKwCyAQAAAA==.Zokrym:BAABLAAECoEcAAIPAAcIICKzDQCwAgAPAAcIICKzDQCwAgAAAA==.Zorahnus:BAABLAAECoEcAAMaAAcI8SI9AwDJAgAaAAcI8SI9AwDJAgAZAAMI6wtttQCeAAAAAA==.',Zy='Zyô:BAABLAAECoEfAAIVAAgIIB1uKgCiAgAVAAgIIB1uKgCiAgAAAA==.',['Æl']='Ælonis:BAABLAAECoEWAAMOAAcIyBMxQgCQAQAOAAYIHRQxQgCQAQAJAAYIWwsHaAAeAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end