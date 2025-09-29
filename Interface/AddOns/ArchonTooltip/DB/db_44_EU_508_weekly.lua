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
 local lookup = {'Mage-Arcane','Evoker-Devastation','Paladin-Holy','Hunter-BeastMastery','Warrior-Fury','Druid-Balance','Unknown-Unknown','Warlock-Destruction','Priest-Shadow','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','Warrior-Arms','Monk-Windwalker','Shaman-Restoration','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Druid-Feral','DeathKnight-Blood','Monk-Mistweaver','Priest-Holy','Druid-Guardian','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Mage-Frost','Evoker-Preservation',}; local provider = {region='EU',realm='Minahonda',name='EU',type='weekly',zone=44,date='2025-09-25',data={Aa='Aagamer:BAAALAADCgMIAgAAAA==.',Ab='Abigor:BAAALAADCggIFAAAAA==.',Ac='Acehood:BAAALAADCggIGAAAAA==.',Ad='Adrarc:BAAALAAECgEIAQAAAA==.Adrianlegaz:BAAALAAECgYIEAAAAA==.',Ae='Aediel:BAAALAAECgYICwABLAAECgcIGQABAOkZAA==.Aelryndel:BAAALAADCgcIBwAAAA==.Aetha:BAAALAADCggIEgAAAA==.',Af='Afigi:BAAALAAECgYICwAAAA==.Aftereffects:BAAALAADCgcIBwAAAA==.',Al='Alakazim:BAAALAAECgMIBQAAAA==.Alcatraz:BAAALAADCgIIAgAAAA==.Alexor:BAABLAAECoEXAAICAAYIBwV4RwDcAAACAAYIBwV4RwDcAAAAAA==.Alextrasz:BAABLAAECoEVAAIDAAYI/xGJNQBeAQADAAYI/xGJNQBeAQAAAA==.Altkia:BAAALAADCggIDgAAAA==.Alucar:BAAALAAECgYIEgAAAA==.',Am='Amulg:BAAALAADCgcIFQAAAA==.',Ap='Apechusques:BAAALAADCgYICgAAAA==.',Ar='Arcanita:BAAALAAECgEIAQAAAA==.Arcenfren:BAABLAAECoEqAAIEAAgIThZXVQDiAQAEAAgIThZXVQDiAQAAAA==.Armostrazon:BAAALAAECgcIDAAAAA==.Arrowgirl:BAAALAADCgMIAwAAAA==.Arthalgor:BAAALAAECgYICwAAAA==.',As='Ascenom:BAAALAAECgQICAAAAA==.Aspirinas:BAAALAAECgYICQABLAAECggILQAFAAocAA==.Asturiana:BAAALAADCgUIBAAAAA==.',At='Athael:BAAALAADCgcIDgAAAA==.',Au='Aura:BAAALAADCgcIBwAAAA==.',Av='Avernus:BAABLAAECoEiAAIGAAgItRo8HwA8AgAGAAgItRo8HwA8AgAAAA==.',Ba='Badbunni:BAAALAADCgcIEAAAAA==.Bafur:BAAALAAECgYICwAAAA==.Bajheera:BAAALAAECgUIBQAAAA==.Barrilete:BAAALAADCgEIAQAAAA==.Barán:BAAALAADCggICAAAAA==.Bashara:BAAALAADCggICAAAAA==.',Be='Belphegor:BAAALAAECgIIBAAAAA==.Bernkastel:BAAALAADCggIDwABLAAECgEIAgAHAAAAAA==.',Bl='Blinja:BAAALAADCggIHwABLAAECgYIDgAHAAAAAA==.',Br='Brokenpeenus:BAAALAAECgYIBwAAAA==.Brujïtä:BAABLAAECoEXAAIIAAYIlgfSjgAfAQAIAAYIlgfSjgAfAQAAAA==.Brulee:BAAALAAECgEIAgAAAA==.Brunitzz:BAAALAAECgcICgAAAA==.',['Bá']='Báby:BAAALAADCggICAAAAA==.',['Bê']='Bêjar:BAAALAAECgEIAQAAAA==.',['Bú']='Búdspencer:BAAALAADCggIDwAAAA==.Búrbuja:BAAALAAECgYIDAAAAA==.',Ca='Calpizar:BAAALAAECgEIAQAAAA==.Caminallum:BAAALAAECgYIBgAAAA==.Carnatum:BAAALAAECgcIEgAAAA==.',Ch='Chamitoo:BAAALAADCgYIBgAAAA==.Cherath:BAAALAADCgMIAwAAAA==.Cherroky:BAAALAAECgUICQAAAA==.Cheshiirex:BAAALAAECggIEQAAAA==.Chesterwin:BAAALAAECgYIDgAAAA==.Chimbiri:BAABLAAECoEXAAIJAAcI5RiJKQAUAgAJAAcI5RiJKQAUAgAAAA==.Chueyuan:BAAALAADCgIIAgAAAA==.Chüsina:BAAALAADCggIKQAAAA==.',Ci='Cinthia:BAAALAADCgMIAwAAAA==.',Cl='Clair:BAAALAADCgcIBwABLAAECgEIAgAHAAAAAA==.Claudiomvp:BAAALAADCggICAAAAA==.Cluck:BAABLAAECoEWAAIKAAcIWxOrTAB3AQAKAAcIWxOrTAB3AQAAAA==.',Cr='Croner:BAAALAAECgEIAQAAAA==.Croww:BAAALAADCgIIAgABLAADCgUIBQAHAAAAAA==.Crujiento:BAAALAAECgMICAAAAA==.',['Cä']='Cäl:BAAALAADCggIFAAAAA==.',Da='Daddymilker:BAAALAAECgYIDAAAAA==.Dairine:BAAALAAECgQIAwAAAA==.Damamuerte:BAAALAAECgMICAAAAA==.Damaoscuraa:BAAALAAECgMIBAAAAA==.Danasgul:BAAALAADCgcICwAAAA==.Darkdwarf:BAAALAAECgUIDwAAAA==.Darkdwarfx:BAAALAADCgQIBAAAAA==.Darkphoenix:BAABLAAECoEnAAIJAAgIRhKQMADsAQAJAAgIRhKQMADsAQAAAA==.Darktora:BAAALAADCggICwAAAA==.',De='Deathmasc:BAAALAADCggICAAAAA==.Demonyalo:BAABLAAECoEaAAMLAAcIBBuoEwAGAgALAAcIBBuoEwAGAgAMAAMI2AUJ8wCLAAAAAA==.Denunsiat:BAAALAAECgYICwAAAA==.Deore:BAAALAAECgYIBgAAAA==.Devorarocas:BAAALAADCggICAAAAA==.',Dg='Dguts:BAAALAAECgQICAAAAA==.',Dh='Dharkhonn:BAAALAADCggICQAAAA==.',Di='Diosktw:BAAALAAECgIIAgAAAA==.Diriom:BAABLAAECoEaAAIMAAYI7g62pABQAQAMAAYI7g62pABQAQAAAA==.',Dk='Dkhuerso:BAAALAAECgYIBAAAAA==.',Do='Doheemlogo:BAAALAADCgEIAQABLAAECgcIDAAHAAAAAA==.',Dr='Dracarhys:BAABLAAECoExAAIBAAgIdRyKLQB7AgABAAgIdRyKLQB7AgAAAA==.Draconath:BAAALAAECggIEQAAAA==.Dragon:BAABLAAECoEiAAINAAgImhiaRABEAgANAAgImhiaRABEAgAAAA==.Drakariel:BAABLAAECoEaAAIOAAYIORbiKgBrAQAOAAYIORbiKgBrAQAAAA==.Drawnir:BAAALAAECgYIEgAAAA==.Drákenden:BAABLAAECoEkAAMFAAcIKx8xMgA9AgAFAAcIBx8xMgA9AgAPAAQIuBr6GgAcAQAAAA==.Dränna:BAAALAADCgcIBwAAAA==.Drîzt:BAAALAAECgMIAQAAAA==.',Du='Dukira:BAAALAADCgQIBAAAAA==.Duquesi:BAAALAADCgIIBgAAAA==.',Ea='Earnen:BAAALAAECgIIAgAAAA==.Earther:BAAALAADCgQIBQAAAA==.',Ed='Edros:BAAALAADCgIIAgAAAA==.',Ei='Eiguer:BAAALAAECgYIDAAAAA==.',El='Elderon:BAACLAAFFIEFAAIQAAII9hEJDwCKAAAQAAII9hEJDwCKAAAsAAQKgRoAAhAABgiiG/0dAOABABAABgiiG/0dAOABAAAA.Eldiego:BAAALAAECgEIAQAAAA==.Eldtara:BAAALAAECgcIDwAAAA==.Electrø:BAAALAADCgcIBwAAAA==.Elisacutberg:BAABLAAECoEXAAIDAAcIZSDyDwByAgADAAcIZSDyDwByAgAAAA==.Elkazemo:BAAALAAECgcIBwABLAAFFAIIBgALAEUcAA==.Elladan:BAAALAAECgYICwAAAA==.Elroy:BAABLAAECoEVAAIRAAYIyhxuRwDfAQARAAYIyhxuRwDfAQAAAA==.',En='Enghèl:BAAALAAECgEIAQAAAA==.Enoc:BAABLAAECoEXAAQSAAgI1Q+KDADOAQASAAcIWhCKDADOAQAIAAYIxwngiQAtAQATAAMIzgcbbACNAAAAAA==.',Es='Esquizo:BAAALAADCgcIBwABLAAECgcIIQAUAA8OAA==.Estronko:BAAALAADCgYIBgABLAAFFAIIBgAVABIfAA==.',Et='Etreumut:BAAALAAECgEIAQAAAA==.',Eu='Eustodia:BAAALAADCggIEAAAAA==.',Ev='Everglide:BAAALAADCgcICAAAAA==.',Ex='Exoodos:BAAALAADCgEIAQAAAA==.',['Eô']='Eôwïn:BAAALAAECgEIAQAAAA==.',Fa='Falkkor:BAABLAAECoENAAIBAAYIqwuAiwBMAQABAAYIqwuAiwBMAQAAAA==.Faloscuro:BAAALAAECgIIAgAAAA==.Falufractum:BAAALAAECgIIAgAAAA==.',Fe='Feldragos:BAAALAADCggICAAAAA==.',Fi='Filpos:BAAALAADCgYIDAAAAA==.',Fl='Flakita:BAAALAADCggICAAAAA==.Flamongo:BAAALAAECgQIBwAAAA==.',Fo='Fonti:BAAALAAECgIIAgAAAA==.',Fr='Frisky:BAAALAADCggIBwAAAA==.Frônt:BAAALAADCggICAAAAA==.',Fu='Furabolos:BAAALAADCgEIAQAAAA==.',Ga='Gadrael:BAAALAADCggICAAAAA==.Galactus:BAAALAADCgUIBQAAAA==.Galafa:BAABLAAECoEbAAIDAAcIvx5vFQA6AgADAAcIvx5vFQA6AgAAAA==.Galaherbo:BAAALAAECgYIDwABLAAECgcIGwADAL8eAA==.Galimb:BAAALAAECggICQAAAA==.Garzon:BAAALAAECgcIDAAAAA==.',Ge='Genesi:BAAALAAECgcIEQAAAA==.Geokgre:BAAALAAECgMIAwAAAA==.Gesserit:BAAALAAECgYIDgAAAA==.',Gh='Ghuleh:BAAALAADCggIDwABLAAECgEIAgAHAAAAAA==.',Gi='Gilvard:BAABLAAECoEYAAMPAAYIpR9rCwAFAgAPAAYIpR9rCwAFAgAFAAII7w5PvgBpAAAAAA==.Gipsydavy:BAAALAAECgYICgAAAA==.Gipsydávid:BAAALAAECgIIAgAAAA==.Gipsyemma:BAABLAAECoEYAAIEAAcI9Qs8kQBbAQAEAAcI9Qs8kQBbAQAAAA==.Gisselle:BAAALAADCgQIAwAAAA==.',Gl='Glandel:BAAALAADCgUIBQAAAA==.Glavin:BAAALAADCgMIAwAAAA==.',Gn='Gnaru:BAABLAAECoEaAAIIAAcIgx9RNAA9AgAIAAcIgx9RNAA9AgAAAA==.',Go='Gokupatatil:BAAALAADCgIIAgAAAA==.Gondan:BAAALAADCggICAAAAA==.Gorkcroth:BAAALAADCgYIBwAAAA==.Gotga:BAABLAAECoEhAAIUAAcIDw7wUgCSAQAUAAcIDw7wUgCSAQAAAA==.',Gr='Grelos:BAAALAAECgYIEgAAAA==.Gremmori:BAAALAAECggIAQAAAA==.Griffithxiv:BAAALAADCgEIAQAAAA==.Gromgar:BAAALAAECgcIDAAAAA==.',Gu='Guyular:BAAALAAECgMIAwAAAA==.',Gw='Gwenella:BAAALAADCggIEAAAAA==.',['Gö']='Gödzila:BAAALAADCggIGwAAAA==.',Ha='Hagën:BAAALAAECgIIAgAAAA==.Hakethemeto:BAABLAAECoEpAAIWAAgIbRw3CwB3AgAWAAgIbRw3CwB3AgAAAA==.Haketheskivo:BAAALAADCgYIBgAAAA==.Haradrenven:BAAALAADCgEIAQAAAA==.Hawtorn:BAAALAADCgcIBwAAAA==.Hayaax:BAAALAADCgcICwAAAA==.Hayaxz:BAAALAADCggIDwAAAA==.',He='Hechi:BAAALAADCggIDAAAAA==.Hectorlkm:BAAALAADCgQIBAAAAA==.Helenitsette:BAAALAAECggIBgABLAAFFAgIAgAHAAAAAA==.Hexyl:BAAALAADCgcIBwAAAA==.',Ho='Hockney:BAAALAADCggILQAAAA==.',Hy='Hydropaw:BAAALAAECgMIBgAAAA==.',['Hë']='Hëllýà:BAABLAAECoEUAAIKAAcI6xR0PQC0AQAKAAcI6xR0PQC0AQAAAA==.',Ic='Icefrost:BAAALAADCggIEgAAAA==.',Il='Ilididan:BAAALAAECgEIAQAAAA==.Ilmatics:BAAALAAECgMICAAAAA==.',In='Infeliz:BAAALAADCgUIBgAAAA==.',Ir='Irenë:BAAALAADCggICAABLAAFFAIIBQAVAOwNAA==.Iriäl:BAABLAAECoEVAAIRAAcINRIPbAB5AQARAAcINRIPbAB5AQABLAAECggIKAAXAAUbAA==.',Ix='Ixchelia:BAABLAAECoEVAAIYAAcItggMXgA+AQAYAAcItggMXgA+AQAAAA==.',Ja='Jadon:BAACLAAFFIEKAAIKAAIIqxzgGQCZAAAKAAIIqxzgGQCZAAAsAAQKgSIAAwoACAjNILcNAM4CAAoACAjNILcNAM4CABkAAwjaGBIeANgAAAAA.',Jo='Joseleitor:BAAALAAECgEIAgAAAA==.',Ju='Juanchope:BAAALAADCgUIBQAAAA==.Juank:BAAALAAECgYIDgAAAA==.Juegoyo:BAAALAAECgMIAwAAAA==.Julyet:BAAALAAECgYIEAAAAA==.',['Jü']='Jülk:BAAALAADCgYIBwAAAA==.',Ka='Kaedelolz:BAAALAADCgMIAwAAAA==.Kaissa:BAAALAAECgMIAwAAAA==.Kameko:BAAALAADCgYIBgAAAA==.Kana:BAAALAADCgUIBgAAAA==.Karionat:BAAALAAECgUIAwABLAAECgYICwAHAAAAAA==.Kasumi:BAAALAADCgQIBAAAAA==.Kazbo:BAAALAADCgUIBQAAAA==.',Ke='Keikø:BAAALAAECgYIEQAAAA==.Kerveroos:BAAALAADCgYICgABLAADCggIDQAHAAAAAA==.Kesser:BAAALAAECgMIAwAAAA==.',Kh='Khadozor:BAAALAADCgMIAwAAAA==.Kharmä:BAAALAAECgYIEQAAAA==.Khasstier:BAAALAAECgEIAQAAAA==.Khevin:BAAALAAECgYIBAAAAA==.Khiana:BAABLAAECoEUAAIKAAcIaAmaZQAkAQAKAAcIaAmaZQAkAQAAAA==.Khorner:BAAALAADCggIEAAAAA==.',Ki='Kiilldemon:BAAALAAECgYICAAAAA==.Kimära:BAABLAAECoEoAAIXAAgIBRv/EgAXAgAXAAgIBRv/EgAXAgAAAA==.',Kn='Kn:BAAALAADCgIIAgAAAA==.',Ko='Konamy:BAABLAAECoElAAIEAAcI3xdabgCkAQAEAAcI3xdabgCkAQAAAA==.Konnita:BAAALAADCggIDQAAAA==.',Kr='Kragtar:BAAALAAECgEIAQAAAA==.Krampus:BAAALAADCgEIAQAAAA==.Kreiguer:BAAALAADCgcIBwAAAA==.Kremlar:BAAALAADCgcICAAAAA==.Krystalina:BAAALAADCggICgAAAA==.',Ky='Kyriean:BAAALAAECgIIAwAAAA==.',['Kí']='Kírsi:BAAALAAECgMIAwAAAA==.',La='Lacurona:BAAALAADCgYIBgAAAA==.Lagartîja:BAAALAADCgQIBAAAAA==.Laurye:BAAALAAECgMIBgAAAA==.Layloft:BAAALAAECgEIAQAAAA==.',Le='Lechucico:BAAALAADCggIEQAAAA==.Legaedon:BAABLAAECoEkAAIEAAgIDh2zMwBNAgAEAAgIDh2zMwBNAgAAAA==.Legnator:BAAALAADCggICAAAAA==.Leidyjasmin:BAAALAAECgMICAAAAA==.Leinara:BAAALAADCggIDgAAAA==.Leuwone:BAAALAAECgcIEAAAAA==.Levyatan:BAAALAADCggIDgAAAA==.',Li='Liatris:BAABLAAECoEUAAIKAAYIEB2jMADuAQAKAAYIEB2jMADuAQAAAA==.Lilparka:BAAALAADCgYICgAAAA==.Limboch:BAAALAAECgEIAQAAAA==.Limongordo:BAABLAAECoEZAAIIAAYImBZJYQCZAQAIAAYImBZJYQCZAQAAAA==.Limonobeso:BAAALAADCgEIAQABLAAECgYIGQAIAJgWAA==.Litrix:BAABLAAECoEYAAIEAAcIcRiCawCrAQAEAAcIcRiCawCrAQAAAA==.Liædrï:BAAALAAECgEIAQABLAAECggIHAALADIjAA==.',Ll='Lluvîa:BAAALAADCggICwAAAA==.',Lm='Lmans:BAAALAADCgIIAgAAAA==.',Lu='Luffamer:BAABLAAECoEdAAIEAAgIjxjgRQAOAgAEAAgIjxjgRQAOAgAAAA==.Lugami:BAAALAADCgcICwAAAA==.Lulisha:BAAALAADCgcIBwABLAAECgYIFgANALUeAA==.Lunsi:BAAALAAECgIIAgAAAA==.Lunsy:BAAALAAECgMIBAAAAA==.Luppo:BAAALAADCggIEAAAAA==.Luxuri:BAAALAAECgIIAgAAAA==.',Lx='Lxk:BAAALAAECgMICAAAAA==.',Ly='Lysanis:BAAALAAECgEIAQAAAA==.',Ma='Maataas:BAAALAAECgUICwAAAA==.Maclovio:BAAALAADCggIEAAAAA==.Macondo:BAAALAAECgUICAAAAA==.Madamers:BAAALAAECgUICgAAAA==.Madock:BAAALAADCggICgAAAA==.Maekary:BAAALAADCgQIBAAAAA==.Magelf:BAAALAADCgEIAQAAAA==.Magickash:BAAALAADCgMIAwAAAA==.Maikwazousky:BAAALAAECgYIBgAAAA==.Maitrol:BAAALAADCggICAAAAA==.Maius:BAAALAAECgMIBgAAAA==.Malborö:BAAALAADCgYIAwAAAA==.Mapahalcon:BAAALAAECgEIAQAAAA==.Martica:BAAALAAECgYIBwAAAA==.Maxdeadlord:BAAALAAECgUICgAAAA==.Maxpatter:BAAALAADCgQIBAAAAA==.',Me='Mechabello:BAAALAAECgYICQAAAA==.Melisandrë:BAAALAAECgcIEwAAAA==.Melme:BAAALAAECggICAAAAA==.Melmet:BAAALAAECggICAAAAA==.Meloncio:BAAALAADCggIEAABLAAECgcIJAAFACsfAA==.Memlaks:BAABLAAECoEhAAINAAgI4RFuaQDoAQANAAgI4RFuaQDoAQAAAA==.Mennón:BAABLAAECoEZAAIUAAYISRpjQgDPAQAUAAYISRpjQgDPAQAAAA==.Merbyn:BAAALAAECgEIAQAAAA==.Meshoj:BAABLAAECoEhAAIaAAgIABf5KQAPAgAaAAgIABf5KQAPAgAAAA==.',Mi='Mimiko:BAAALAAECgYIEAAAAA==.Miniexánime:BAAALAAECgEIAQABLAAECgcIGgALAAQbAA==.Minifalo:BAAALAAECgYIEQAAAA==.Mirandre:BAAALAADCgMIAwABLAADCgQIAQAHAAAAAA==.Mistik:BAAALAADCggICAAAAA==.Mithas:BAAALAADCgYIDAAAAA==.Miyuna:BAAALAADCgYIBgAAAA==.',Mo='Mochi:BAAALAADCgcIBwAAAA==.Mogaro:BAAALAADCgUIBQAAAA==.Moogur:BAAALAAECgYICgAAAA==.Morganagalz:BAAALAAECgMIAQAAAA==.Morgans:BAABLAAECoEjAAMNAAcI4B6nUQAfAgANAAcI4B6nUQAfAgADAAYI9xtOIgDTAQAAAA==.Morthgull:BAAALAADCggICAAAAA==.Mortimër:BAAALAADCgcIBgAAAA==.Mowglí:BAAALAAECgMIBQAAAA==.',Mu='Munn:BAAALAAECgYICQAAAA==.',['Mä']='Mäxdeadlord:BAAALAAECgEIAQAAAA==.',Na='Naomicampbel:BAAALAADCggICwAAAA==.Naral:BAAALAADCggIEAAAAA==.',Ne='Nefiire:BAAALAADCgYIDAAAAA==.Nekosan:BAAALAAECgMIAwAAAA==.Nely:BAAALAAECgEIAQAAAA==.Nessalia:BAAALAADCgQIBAAAAA==.Newydd:BAAALAAECgIIAgAAAA==.',Ni='Nigrodian:BAAALAAECgYICgAAAA==.Nilea:BAABLAAECoEdAAMbAAYIvRo/GQCjAQAbAAYIuRc/GQCjAQAcAAYIzBYAAAAAAAAAAA==.Ninfaev:BAAALAADCggIEAAAAA==.Niue:BAABLAAECoEWAAINAAYItR67WwAGAgANAAYItR67WwAGAgAAAA==.',No='Nochebuena:BAAALAADCgYIBgAAAA==.Noraah:BAAALAADCgcIDQAAAA==.Noå:BAAALAADCgcIBwAAAA==.',Nu='Nuke:BAAALAAECgEIAQAAAA==.',Ob='Obscurïo:BAAALAADCgUIBQAAAA==.',Oh='Ohmycát:BAAALAAECgEIAQAAAA==.',Ol='Oloragitano:BAAALAADCgYIBgAAAA==.',On='Onawha:BAAALAADCgEIAQABLAAECgYIGQAIAJgWAA==.',Or='Orav:BAAALAAECgEIAQAAAA==.',Ot='Otarix:BAAALAADCgYIBgAAAA==.',Pa='Pacodin:BAABLAAECoEVAAIOAAUISw3VPgDqAAAOAAUISw3VPgDqAAAAAA==.Paladió:BAAALAAECgIIAgAAAA==.Papawelo:BAAALAAECgEIAQAAAA==.Pavolliu:BAAALAADCgUIBQAAAA==.',Pe='Pecu:BAAALAAECgQIBwAAAA==.Pedromt:BAAALAADCgEIAQAAAA==.Pelonchita:BAAALAAECgMIAwAAAA==.Pepemoncho:BAAALAADCggIHQAAAA==.Pepinilloo:BAAALAAECgMIAwAAAA==.',Ph='Phalillo:BAAALAADCgEIAQAAAA==.',Pk='Pkearcher:BAABLAAECoEtAAMaAAgIjBlBOADBAQAaAAcIdhpBOADBAQAEAAgIDBTPYwC9AQAAAA==.Pkepala:BAAALAAECgUICQAAAA==.',Po='Polcar:BAAALAAECgcIDAAAAA==.',Pp='Ppïm:BAAALAADCgUIBQAAAA==.',Pu='Puzzle:BAAALAADCggIBwAAAA==.',['Pâ']='Pâgana:BAAALAADCgUIBQAAAA==.',Qi='Qiare:BAAALAADCgcIBwAAAA==.',Qn='Qnwanheda:BAAALAAECgYIDQABLAAECggIIQAXAPoWAA==.',Qu='Quin:BAACLAAFFIEGAAIQAAII7xV3CgCkAAAQAAII7xV3CgCkAAAsAAQKgTIAAhAACAh6Ig4IAPsCABAACAh6Ig4IAPsCAAAA.Quindh:BAAALAAECgMIAgAAAA==.',Qw='Qweeck:BAACLAAFFIEFAAIKAAMI3wvxEADFAAAKAAMI3wvxEADFAAAsAAQKgRkAAgoABgg2Hw0pABQCAAoABgg2Hw0pABQCAAEsAAUUBQgOAAgAKB8A.',Ra='Raaeghal:BAAALAAECgYIEQAAAA==.Radahn:BAAALAADCggIDwAAAA==.Raikuh:BAAALAAECgMICAAAAA==.Raistlìn:BAABLAAECoESAAIBAAcInxboRwAQAgABAAcInxboRwAQAgAAAA==.Raitlinn:BAAALAADCgQIAQAAAA==.Ramala:BAAALAADCggICgAAAA==.Randirla:BAAALAADCgIIAQAAAA==.Raphtalia:BAAALAAECgIIAgAAAA==.Rarnarg:BAAALAAECgEIAQAAAA==.',Re='Redflag:BAABLAAECoEXAAIYAAcIWyGOFwCVAgAYAAcIWyGOFwCVAgAAAA==.Reinhart:BAAALAAECgUIBQAAAA==.Retraa:BAAALAAECggICAAAAA==.Revientalmas:BAAALAADCgUICAAAAA==.',Rh='Rhelar:BAABLAAECoEmAAILAAgItB16CQCeAgALAAgItB16CQCeAgAAAA==.Rhukah:BAAALAADCggICAAAAA==.',Ri='Rickard:BAAALAAECgMIAwABLAAECggIDwAHAAAAAA==.Riglôs:BAAALAAECgMIAwAAAA==.Rique:BAAALAAECgEIAQAAAA==.',Ro='Roim:BAAALAADCgQIBAAAAA==.Rontal:BAAALAAECgIIAgABLAAECggIIAAWAIEaAA==.Roostrife:BAAALAAECgMIBAAAAA==.Rosae:BAAALAAECgEIAQAAAA==.Roucomei:BAAALAADCgYIBgAAAA==.Rous:BAAALAAECgcIDQAAAA==.',Ru='Runas:BAABLAAECoEgAAMUAAcICBFrWgB4AQAUAAcICBFrWgB4AQARAAYI6AmLrwDkAAAAAA==.',Ry='Ryø:BAAALAAECgYICgAAAA==.',['Râ']='Râtchet:BAAALAADCgIIAgAAAA==.',['Rí']='Ríp:BAAALAAECgUICQAAAA==.',['Rô']='Rôxy:BAAALAAECgEIAQAAAA==.',Sa='Saauron:BAAALAAECgIIAgAAAA==.Sadoom:BAABLAAECoEYAAMaAAYILAr4cADrAAAaAAYILAr4cADrAAAEAAMINAal9wBuAAAAAA==.Sanctús:BAAALAADCgYIBwAAAA==.Sarâh:BAAALAADCgYICQAAAA==.',Se='Seijuro:BAAALAAECgYICQAAAA==.Seiuro:BAAALAAECgYICAAAAA==.Sekki:BAAALAAECgYIDAAAAA==.Seldoria:BAAALAAECggIEQAAAA==.Selenebreath:BAAALAADCgEIAQAAAA==.Sercomart:BAAALAAECgMIBAAAAA==.Serenix:BAAALAAECgMIAwAAAA==.Serify:BAAALAADCgYIDwAAAA==.Severuxx:BAAALAAECgUICwAAAA==.Seycan:BAABLAAECoEaAAIIAAgILhEIbQB4AQAIAAgILhEIbQB4AQAAAA==.Seznax:BAAALAADCgcIDQAAAA==.',Sh='Shadowstar:BAACLAAFFIELAAMIAAMI9RxaGAD3AAAIAAMItxhaGAD3AAATAAII/xzQIABRAAAsAAQKgSMABAgACAi4HzMgAKgCAAgACAjtHjMgAKgCABIAAwh1IWkYACQBABMAAggcFTVrAJAAAAAA.Shads:BAAALAAECggIEgAAAA==.Shamael:BAAALAADCgQIBAAAAA==.Shamalia:BAAALAAECgYIEgAAAA==.Shanndo:BAAALAADCgUIBQAAAA==.Shapiva:BAAALAAECgIIAgAAAA==.Shawla:BAAALAAECgEIAQABLAAECgYICQAHAAAAAA==.Shinon:BAABLAAECoE0AAINAAgIyRpNMwB+AgANAAgIyRpNMwB+AgAAAA==.Shogunneko:BAAALAAFFAIIAgAAAA==.Shánks:BAAALAADCgYIBgAAAA==.',Si='Silwex:BAABLAAECoEaAAIBAAcItQ+4bACgAQABAAcItQ+4bACgAQAAAA==.',Sj='Sjena:BAAALAADCgUIBQAAAA==.',Sk='Skartus:BAACLAAFFIEGAAIdAAII2hDlRwCQAAAdAAII2hDlRwCQAAAsAAQKgSMAAx0ACAhGIL0iAMQCAB0ACAhGIL0iAMQCAB4AAQiQFFlUADcAAAAA.',Sn='Snim:BAAALAADCgcIBwABLAAECgcIDAAHAAAAAA==.Snowblack:BAAALAADCggIDQAAAA==.',So='Socerdotta:BAABLAAECoEUAAMJAAgIdxbaNADTAQAJAAcIExfaNADTAQAYAAEIeQ0AAAAAAAAAAA==.Sonn:BAAALAADCgcIDAAAAA==.Sonne:BAAALAAECgUICAAAAA==.Sorzas:BAAALAADCgcIBgAAAA==.',Sp='Spt:BAAALAADCgUIBQAAAA==.',Sr='Srmustacho:BAAALAADCgcIBwAAAA==.',St='Steingeitin:BAAALAADCggIDQAAAA==.',Su='Suguuru:BAAALAAECgYIDwAAAA==.Sunder:BAACLAAFFIEKAAIMAAII/w2qNQCOAAAMAAII/w2qNQCOAAAsAAQKgRkAAgwABgiXHTpdAOUBAAwABgiXHTpdAOUBAAAA.Surelya:BAAALAADCgcIBwAAAA==.',Sv='Svicelny:BAAALAADCgYIBgAAAA==.',Sy='Sylvänas:BAAALAADCgYIBgABLAAFFAIIBgABANQOAA==.Syraax:BAAALAAECgQIBQAAAA==.',['Sâ']='Sâcmis:BAAALAAECgIIAgAAAA==.',Ta='Tadín:BAAALAAECgcIEAAAAA==.Tamahome:BAAALAAECggICQAAAA==.Tanthalas:BAAALAADCgUIBQAAAA==.Tarkoth:BAAALAAECgYIEAAAAA==.Taupaipala:BAAALAAECgEIAQAAAA==.',Te='Tejeleo:BAAALAAECgQIBwAAAA==.Terapia:BAAALAAECgcIDAAAAA==.Teska:BAAALAAECgQIBgAAAA==.Teskachami:BAAALAAECgYIDAAAAA==.Teskarayo:BAAALAAECgYIBgAAAA==.Teskarolo:BAAALAADCggIDQAAAA==.',Th='Thejosema:BAAALAAECgYIDQAAAA==.Thelriza:BAABLAAECoEaAAITAAgIniESBQADAwATAAgIniESBQADAwAAAA==.Thorien:BAAALAAECgIIAgAAAA==.Thunderhunt:BAAALAADCggICAAAAA==.Théodred:BAABLAAECoEZAAINAAYIIBxLZwDsAQANAAYIIBxLZwDsAQAAAA==.',Ti='Tiodelamaza:BAABLAAECoEXAAIYAAYIOgWqdwDqAAAYAAYIOgWqdwDqAAAAAA==.Titovitx:BAAALAAECgUIDQAAAA==.',To='Torpedò:BAAALAADCgQIBAAAAA==.Tottenwolf:BAAALAADCgcIBwAAAA==.',Tr='Trembotesto:BAAALAADCgMIBAAAAA==.Treïzak:BAAALAADCgcIDAAAAA==.Trinnyty:BAAALAAECgMIAwAAAA==.Tráckfol:BAABLAAECoEZAAIfAAYIDRFdPQBVAQAfAAYIDRFdPQBVAQAAAA==.Träncas:BAAALAADCgYICgAAAA==.',Tu='Turmi:BAAALAADCggIEgAAAA==.',Ty='Tyrondalia:BAAALAAECgcIEQAAAA==.',Tz='Tzarkos:BAAALAADCgYICQAAAA==.',Ul='Ultimatrix:BAAALAAECgIIAgAAAA==.',Ur='Urthas:BAAALAAECgQICQAAAA==.',Us='Ushiø:BAAALAAECgYIDAABLAAECgcIEwAHAAAAAA==.',Va='Vaiu:BAABLAAECoEaAAMCAAcISAiKPAAzAQACAAcISAiKPAAzAQAgAAEIhAKHOwAiAAAAAA==.Valirah:BAAALAADCgYIBgAAAA==.Vanadio:BAAALAADCgUIBQAAAA==.Vandüsh:BAAALAAECgIIAgAAAA==.',Ve='Vello:BAAALAAECgQICAAAAA==.Verysa:BAAALAAECggIDwAAAA==.',Vh='Vhaldemar:BAAALAADCgcIDgAAAA==.Vhenom:BAAALAADCggIIQAAAA==.',Vi='Vice:BAAALAAECgEIAQAAAA==.Vikram:BAAALAAECgUIBQAAAA==.Villanaa:BAAALAADCgYIBgAAAA==.',Vm='Vml:BAAALAADCgQIBAAAAA==.',Wa='Wache:BAAALAADCggIDgAAAA==.Walamonio:BAAALAAECgcIDAAAAA==.',We='Webofrito:BAAALAADCgEIAQAAAA==.Weizer:BAAALAAECgYIEAAAAA==.Welfi:BAAALAADCgcIEwAAAA==.Welolock:BAAALAAECgMIBwAAAA==.Welvor:BAAALAADCggIEQAAAA==.',Wh='Whatsername:BAAALAAECgEIAQAAAA==.Whiteligth:BAAALAADCggICAAAAA==.Whiterose:BAAALAADCgcIDAAAAA==.Whololook:BAAALAAECgUICgAAAA==.',Wi='Winola:BAABLAAECoEkAAINAAcIpAa22gARAQANAAcIpAa22gARAQAAAA==.',Wo='Wolfkrieg:BAAALAAECgEIAQAAAA==.',Wt='Wthrgeralt:BAAALAAECgEIAQAAAA==.',Xh='Xhilaxh:BAAALAAECgIIAgAAAA==.',Xi='Xiaoyu:BAABLAAECoEcAAMRAAcI6hUXYgCUAQARAAcI6hUXYgCUAQAUAAIITgHqswAlAAAAAA==.Ximixurry:BAABLAAECoEbAAIbAAgI2hJbEQD/AQAbAAgI2hJbEQD/AQAAAA==.Xireth:BAAALAAECgUICgAAAA==.',Xm='Xmatapayos:BAAALAAECgEIAQAAAA==.',Xu='Xuteboy:BAAALAADCgQIBAAAAA==.',Ya='Yaffar:BAAALAAECggIDgAAAA==.Yalamagic:BAAALAADCgYICAABLAAECgcIGgALAAQbAA==.Yalohm:BAABLAAECoEYAAIUAAgIzhX+KQBGAgAUAAgIzhX+KQBGAgABLAAECgcIGgALAAQbAA==.Yarrik:BAAALAADCgEIAQAAAA==.',Ye='Yeruki:BAAALAAECgUIAgAAAA==.Yesika:BAAALAADCgQIBAAAAA==.',Yi='Yiazmat:BAABLAAECoEXAAINAAYI7BubaADpAQANAAYI7BubaADpAQAAAA==.',Yk='Ykâr:BAAALAADCggICAAAAA==.',Yo='Yohdise:BAABLAAECoEcAAIKAAcImBoSNQDZAQAKAAcImBoSNQDZAQAAAA==.',Yr='Yrona:BAAALAADCgYIBgAAAA==.',Yu='Yuiznita:BAAALAAECgIIAgAAAA==.Yunaka:BAAALAAECgQIBwAAAA==.',Za='Zaishei:BAAALAAECgQIBAABLAAECggIKAAXAAUbAA==.Zakaria:BAAALAADCgcIBwAAAA==.Zakwd:BAAALAAECgIIAgAAAA==.Zalek:BAAALAAECgYIDQAAAA==.Zapétrel:BAAALAADCgMIAwAAAA==.Zarfia:BAAALAADCggICAAAAA==.Zarguk:BAAALAAECgYIDAAAAA==.',Ze='Zelune:BAAALAAECgEIAQAAAA==.Zerea:BAAALAADCggICAAAAA==.',Zi='Zif:BAAALAADCggICAAAAA==.',Zo='Zoltrix:BAAALAADCggIDQAAAA==.',Zu='Zulkraa:BAAALAADCgYICwAAAA==.Zum:BAAALAAECgYIEQAAAA==.',['Ál']='Álicai:BAAALAAECgIIAgAAAA==.',['Áz']='Ázazél:BAAALAADCgcIBwAAAA==.',['Æñ']='Æñ:BAACLAAFFIEFAAIVAAII7A3gCwCLAAAVAAII7A3gCwCLAAAsAAQKgRkAAhUABwjLHGAOAEICABUABwjLHGAOAEICAAAA.',['Ðe']='Ðersuuzala:BAABLAAECoErAAIEAAgIYSFlHgCwAgAEAAgIYSFlHgCwAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end