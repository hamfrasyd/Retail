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
 local lookup = {'Paladin-Protection','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Monk-Windwalker','Hunter-Marksmanship','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Hunter-BeastMastery','Druid-Feral','Druid-Balance','Mage-Arcane','Mage-Fire','DemonHunter-Havoc','DeathKnight-Frost','Priest-Holy','Druid-Restoration','Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Blood','Rogue-Assassination','Warrior-Fury','Mage-Frost','Rogue-Subtlety','Shaman-Enhancement','Druid-Guardian','Evoker-Preservation','Warrior-Protection','Warrior-Arms','Rogue-Outlaw','Monk-Brewmaster','Shaman-Restoration',}; local provider = {region='EU',realm="Gul'dan",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Acro:BAAALAAECgEIAQAAAA==.',Ad='Adania:BAACLAAFFIEbAAIBAAcI1hhlAABcAgABAAcI1hhlAABcAgAsAAQKgSgAAgEACAhKJukAAIEDAAEACAhKJukAAIEDAAAA.Adenea:BAABLAAECoEdAAICAAgIoSKyBQD3AgACAAgIoSKyBQD3AgABLAAFFAcIGwABANYYAA==.',Ae='Aereon:BAABLAAECoEWAAMDAAcIjhxZIgDTAQADAAYIlRtZIgDTAQAEAAMI5xbdAAG0AAAAAA==.',Ai='Aishoka:BAABLAAECoElAAIFAAcI/x3wDwCAAgAFAAcI/x3wDwCAAgAAAA==.',Ak='Akanon:BAAALAADCgcIBAAAAA==.',Al='Alexes:BAAALAAECggIEAAAAA==.Aliagos:BAAALAAECggICAAAAA==.Alkantara:BAABLAAECoEaAAIDAAcIJx6+IADeAQADAAcIJx6+IADeAQAAAA==.',Am='Ambino:BAAALAAECgYIEAAAAA==.Amelie:BAAALAAECgYICwAAAA==.Amylea:BAABLAAECoEUAAIGAAgIMhmUJAAwAgAGAAgIMhmUJAAwAgAAAA==.',Ap='Apolon:BAAALAAECgIIAgAAAA==.',Ar='Arendexx:BAAALAAECgYIBgAAAA==.Ariell:BAAALAAECgEIAQAAAA==.',Au='Aureeon:BAAALAAECgEIAQAAAA==.',Av='Avalun:BAAALAADCgQIBgAAAA==.',Az='Azrâel:BAAALAAECgYIDQAAAA==.',Ba='Balzak:BAAALAAECgIIAgAAAA==.Bamboozler:BAAALAAECgcIBwAAAA==.Bananenbrot:BAABLAAECoEoAAIHAAgI8xVXJgAnAgAHAAgI8xVXJgAnAgAAAA==.Barbepew:BAAALAAECggICQAAAA==.',Bl='Blackfoxx:BAAALAAECggICAABLAAECggIKgACACQaAA==.Blindar:BAAALAADCggIDQAAAA==.Blooddorem:BAAALAADCggIEAAAAA==.Bloodfox:BAAALAADCggIDwAAAA==.Bloodhôof:BAAALAAECgEIAQAAAA==.',Br='Braxl:BAAALAAECgEIAQAAAA==.Brosekko:BAAALAAECgMIAwAAAA==.Browe:BAABLAAECoEVAAQIAAYIWwogjAAnAQAIAAYILwogjAAnAQAJAAMILgaeKQCEAAAKAAIIhgZDeQBcAAAAAA==.',Bu='Buffor:BAABLAAECoEfAAILAAcI8ySRIACkAgALAAcI8ySRIACkAgAAAA==.',['Bî']='Bîerkules:BAAALAAECgcIDQAAAA==.',Ca='Cassio:BAAALAAECgQIBAAAAA==.Catnado:BAABLAAECoEiAAMMAAcIdh2iDgA9AgAMAAcIdh2iDgA9AgANAAII6gaHggBaAAAAAA==.',Ch='Chakaron:BAACLAAFFIEZAAMOAAcITyGkAQB0AgAOAAYI7CKkAQB0AgAPAAEInxdqBwBVAAAsAAQKgSEAAg4ACAhSJhYJAD4DAA4ACAhSJhYJAD4DAAAA.Chakaronfotm:BAABLAAECoEaAAILAAgIwSNtHQC2AgALAAgIwSNtHQC2AgAAAA==.Chaosgaxx:BAAALAADCgUIBQAAAA==.Chemdog:BAAALAAECggICAAAAA==.Chîllôzz:BAAALAAECgcIBwAAAA==.',Cl='Cleavpala:BAABLAAECoEVAAIEAAgIlBhtWAAOAgAEAAgIlBhtWAAOAgABLAAFFAcIEQAQAKMZAA==.Clockworkelf:BAAALAAECgcIDQABLAAECggIJwARAM4lAA==.',Co='Coloris:BAAALAAECgEIAQAAAA==.Corvaz:BAACLAAFFIEbAAMIAAcIix4uAQCqAgAIAAcIix4uAQCqAgAKAAIIMBKREQCZAAAsAAQKgTAABAgACAjOJqoBAIYDAAgACAjOJqoBAIYDAAkAAwjCHA4dAO0AAAoAAgggHFBuAIMAAAAA.Corvazjr:BAABLAAECoEVAAMJAAgIDxinDQC8AQAIAAgItRQoSgDkAQAJAAYINBqnDQC8AQAAAA==.Cowderwelsh:BAAALAAECggICgAAAA==.',Cy='Cyclops:BAAALAAECgYICQAAAA==.',['Cò']='Còlós:BAAALAADCgYIBgAAAA==.',Da='Daichan:BAABLAAECoEnAAIRAAgIziVKFwD7AgARAAgIziVKFwD7AgAAAA==.Dantalus:BAAALAAECggICAAAAA==.Darasch:BAAALAADCggICAAAAA==.Darkwife:BAABLAAECoEeAAISAAcI7xBlRQCbAQASAAcI7xBlRQCbAQAAAA==.',De='Deadman:BAABLAAECoEyAAIOAAgIMhmZOQBGAgAOAAgIMhmZOQBGAgAAAA==.Deathnite:BAAALAADCggICQAAAA==.Deekju:BAAALAAECgYIDAAAAA==.Deera:BAAALAADCgcIBwAAAA==.Deezhots:BAACLAAFFIELAAITAAMI1CWkCwDoAAATAAMI1CWkCwDoAAAsAAQKgR8AAxMACAi/JFwDAEUDABMACAi/JFwDAEUDAAwAAwjUDAAAAAAAAAAA.Defty:BAAALAADCggICAAAAA==.Deicide:BAABLAAECoEiAAIDAAgIKh29CgCuAgADAAgIKh29CgCuAgAAAA==.Demoholic:BAABLAAECoEdAAMJAAgIXxQcBwA+AgAJAAgIQxQcBwA+AgAIAAIINwPU1gA7AAAAAA==.Demoniya:BAAALAAECgYICgAAAA==.',Di='Dieqo:BAAALAAECgYIBgAAAA==.',Do='Doloria:BAAALAADCggICAAAAA==.Doom:BAAALAAECgYIDwAAAA==.Doombot:BAAALAADCggICAAAAA==.Doomrel:BAAALAADCggIDgAAAA==.Dorien:BAAALAADCggIDwAAAA==.Doé:BAAALAADCgEIAQABLAADCgEIAQAUAAAAAA==.',Dr='Dragostrasza:BAABLAAECoEZAAMVAAgIGRFrJgDIAQAVAAgIGRFrJgDIAQAWAAMIvQjVEgCGAAAAAA==.',['Dé']='Désperados:BAAALAAECgYICQAAAA==.',['Dü']='Düsterkeit:BAAALAADCgUIBQABLAAECggIFgAXAKsQAA==.',El='Electrocutie:BAAALAAFFAMIAwABLAAFFAcIGQAOAD4lAA==.Elementauro:BAACLAAFFIEHAAIYAAMITSOQCwA7AQAYAAMITSOQCwA7AQAsAAQKgR8AAhgACAgGJdIIADwDABgACAgGJdIIADwDAAAA.',En='Endris:BAAALAADCgcIBwAAAA==.Enkidu:BAAALAAECgYIDAAAAA==.',Er='Erzuriel:BAAALAADCgQIBAAAAA==.',Ex='Excezzdk:BAABLAAECoEpAAMRAAgIlx6nKwCdAgARAAgIYB6nKwCdAgAZAAYI8BgAAAAAAAAAAA==.Exquisa:BAABLAAECoEeAAIRAAgIfSL9EwAMAwARAAgIfSL9EwAMAwAAAA==.Exxa:BAAALAADCggICAAAAA==.',Fe='Ferenginar:BAABLAAECoEZAAIaAAgI/Rw9DgCsAgAaAAgI/Rw9DgCsAgAAAA==.',Fi='Finhy:BAAALAAFFAMIAwABLAAFFAUIDAAEAGsaAA==.Finshii:BAACLAAFFIEMAAIEAAUIaxpuBADdAQAEAAUIaxpuBADdAQAsAAQKgRgAAgQACAi+JtoDAHYDAAQACAi+JtoDAHYDAAAA.Fiola:BAAALAAECggIDgAAAA==.',Fo='Fockz:BAACLAAFFIELAAIYAAMIdCBGDAApAQAYAAMIdCBGDAApAQAsAAQKgTQAAhgACAhmJjkEAGgDABgACAhmJjkEAGgDAAAA.',Fr='Franck:BAAALAADCggIDwAAAA==.Freeze:BAAALAADCgEIAQAAAA==.Frostshocks:BAAALAADCggICAAAAA==.',Fu='Futta:BAAALAAECgYIEgAAAA==.',Fy='Fyralath:BAAALAADCggICAAAAA==.',Ga='Gaella:BAAALAAECgMIAwAAAA==.Galaxyhunter:BAACLAAFFIELAAIBAAMIbCASBAAVAQABAAMIbCASBAAVAQAsAAQKgSAAAwEACAhyJngBAHEDAAEACAhyJngBAHEDAAQAAQilHvorAVQAAAAA.Galenn:BAAALAAECggICAAAAA==.Galimonde:BAAALAAECgIIAgAAAA==.',Ge='Georgeruney:BAABLAAECoEmAAMRAAgICCOJFgD+AgARAAgICCOJFgD+AgAZAAYI0AiqKADxAAAAAA==.',Go='Gogeta:BAABLAAECoEVAAIEAAcIAxyZSAA4AgAEAAcIAxyZSAA4AgABLAAECggIKgAbALUgAA==.Gon:BAABLAAECoEYAAMGAAcIZROkPACsAQAGAAcIZROkPACsAQALAAYI6A2brQAkAQAAAA==.',Gr='Grandulf:BAAALAAECgYICQAAAA==.Grantorino:BAAALAADCggICAAAAA==.Graveclaw:BAAALAAECgIIAgAAAA==.Greay:BAABLAAECoEXAAIIAAcI4QUljQAjAQAIAAcI4QUljQAjAQAAAA==.Griphook:BAAALAAECggICAABLAAECggIKQAcAPIfAA==.Grumpyy:BAAALAAECgYIDAAAAA==.',Gu='Gummibärchen:BAAALAAECgQIBAAAAA==.',Ha='Haelis:BAAALAAECgEIAQABLAAECggIGQAVABkRAA==.Hakéta:BAAALAADCgMIBAAAAA==.',He='Headshot:BAAALAAECgMIBAAAAA==.Herminé:BAAALAADCggICAAAAA==.Hexadezimal:BAAALAAECggICgABLAAECggIGQAVABkRAA==.Hexelin:BAAALAADCgMIAwAAAA==.Heîlnîx:BAAALAAFFAIIAgABLAAFFAMICwABAGwgAA==.',Ho='Hoddot:BAAALAADCggICgAAAA==.Hodix:BAAALAAECgYIDAAAAA==.Holyfluffy:BAAALAAECgcICwAAAA==.',Hy='Hyta:BAACLAAFFIEOAAISAAUIMhbRBQCsAQASAAUIMhbRBQCsAQAsAAQKgRcAAhIACAiMGzooACoCABIACAiMGzooACoCAAAA.Hyy:BAABLAAECoEVAAIDAAgINhl7EQBhAgADAAgINhl7EQBhAgAAAA==.',['Há']='Háudràuf:BAAALAADCgYIBgAAAA==.',['Hö']='Hösler:BAABLAAECoEcAAMOAAcInxUbXADQAQAOAAcImBQbXADQAQAcAAEILxsAAAAAAAAAAA==.',Ig='Igotyou:BAAALAADCgIIAgAAAA==.',Il='Iladora:BAAALAADCggICAAAAA==.Iloveit:BAAALAAECggICAAAAA==.Ilovesara:BAACLAAFFIENAAMOAAYIChNaDQCnAQAOAAUIQRZaDQCnAQAPAAEI9gJuCgBEAAAsAAQKgS8AAw4ACAiaJDoIAEUDAA4ACAiaJDoIAEUDAA8AAQitDrkcAD0AAAAA.',Im='Immanuel:BAAALAADCggIEQAAAA==.Impergator:BAAALAAFFAMICwAAAQ==.',In='Inosygosa:BAACLAAFFIEbAAMWAAcItyUWAAAGAwAWAAcItyUWAAAGAwAVAAUISCIqBADMAQAsAAQKgSkAAxUACAjlJmcAAJIDABUACAjjJmcAAJIDABYACAjOJVUAAHEDAAAA.Inthedark:BAACLAAFFIEVAAMdAAcIyhwmAQBCAgAdAAYIix4mAQBCAgAaAAUIkhkZAgDDAQAsAAQKgSAAAx0ACAi8JuYAAGoDAB0ACAgKJuYAAGoDABoACAisJUgFAB8DAAAA.',Io='Ioreth:BAABLAAECoEXAAILAAcIZA15hwBuAQALAAcIZA15hwBuAQAAAA==.',Ir='Irondruid:BAACLAAFFIETAAITAAYIhBUhAwDYAQATAAYIhBUhAwDYAQAsAAQKgTgAAhMACAjKH5kSAKQCABMACAjKH5kSAKQCAAAA.Ironstrike:BAAALAADCggICAAAAA==.',Ix='Ixaty:BAAALAAECgYIEgAAAA==.',Ja='Jailoss:BAAALAADCgYIBgAAAA==.Jandi:BAAALAAECggICAAAAA==.',Ji='Jiaxin:BAAALAADCgYIBgAAAA==.Jimeji:BAABLAAECoEcAAIMAAgImR+/FQDaAQAMAAgImR+/FQDaAQABLAAFFAYICwAVAC8WAA==.',Jo='Joblob:BAAALAADCgcIAQAAAA==.Joliehoney:BAAALAAECgYICgAAAA==.',Ka='Karaton:BAAALAAECgEIAQAAAA==.Kasan:BAAALAAECgYIEwAAAA==.Katyparry:BAAALAAFFAIIAgAAAA==.Kazmojo:BAABLAAECoErAAIeAAgIySJLAgAdAwAeAAgIySJLAgAdAwAAAA==.Kazumi:BAAALAADCggIEAAAAA==.',Ke='Kenpachy:BAAALAAECgEIAQAAAA==.Kesh:BAAALAADCggICAAAAA==.',Ki='Kiara:BAAALAAECgYIBQAAAA==.Kitohunt:BAAALAAECgMIAwAAAA==.Kitopal:BAAALAADCgIIAgAAAA==.',Kl='Klatschi:BAAALAADCgIIAgAAAA==.',Ko='Kona:BAAALAADCggICAAAAA==.Koplawu:BAAALAAECgIIAgAAAA==.Koranova:BAAALAADCggICAAAAA==.Korridan:BAAALAAECgQIBAABLAAFFAYIEgARACwTAA==.',Kr='Krankenwagen:BAAALAADCggIDgABLAAECgYICgAUAAAAAA==.',Ku='Kumâ:BAAALAAECgMIAwAAAA==.Kungfused:BAAALAADCggICAAAAA==.Kuróok:BAAALAAECgQIBQABLAAFFAIIAgAUAAAAAA==.Kushzz:BAAALAADCggICAAAAA==.',Kv='Kvelertak:BAAALAAECggICQAAAA==.',['Kî']='Kîto:BAAALAAECgUIBQAAAA==.',La='Lathgertha:BAABLAAECoEaAAIEAAcIWRwCQgBLAgAEAAcIWRwCQgBLAgAAAA==.',Le='Lenti:BAABLAAECoEZAAIQAAcILBQHYgDaAQAQAAcILBQHYgDaAQAAAA==.',Li='Liandor:BAAALAADCggIGAAAAA==.Likkiste:BAEBLAAECoEVAAMRAAgIjxj8qgB2AQARAAcIHBf8qgB2AQAZAAgIeRQAAAAAAAABLAAFFAMIAwAUAAAAAA==.Lirinny:BAAALAAECggICAAAAA==.Littledark:BAABLAAECoEaAAIfAAcIuRdGEACWAQAfAAcIuRdGEACWAQAAAA==.',Lo='Lodotomy:BAAALAAECgYIDAAAAA==.Lonlenin:BAAALAAECgUIBgAAAA==.',Lu='Lumínár:BAAALAADCgIIAgAAAA==.Lumøs:BAAALAAECgMIBgAAAA==.Lunira:BAAALAADCggICAAAAA==.',Ly='Lyana:BAAALAADCgEIAQABLAADCggICAAUAAAAAA==.Lycanstrasz:BAABLAAECoEpAAIgAAgIBST7AQAzAwAgAAgIBST7AQAzAwAAAA==.Lycanthrope:BAACLAAFFIEXAAITAAcIyxxWAACaAgATAAcIyxxWAACaAgAsAAQKgSgAAhMACAjYJFYHAA8DABMACAjYJFYHAA8DAAAA.',['Lî']='Lîghthoof:BAAALAADCgMIAwAAAA==.',['Lú']='Lúkado:BAAALAADCgUIBQAAAA==.',['Lü']='Lügenbaron:BAAALAADCgcIDAABLAADCggIHQAUAAAAAA==.',Ma='Malenia:BAAALAAECgYIBgAAAA==.Mallee:BAAALAADCgMIAwAAAA==.Marani:BAAALAADCgUIBQAAAA==.Marillé:BAAALAAECgQIBAAAAA==.Matekstrasza:BAAALAAECgUICAAAAA==.',Me='Medusa:BAAALAADCgcIBwAAAA==.',Mi='Miami:BAAALAADCgYIAwAAAA==.Miesmuschel:BAABLAAECoErAAILAAgIbxxSRQAQAgALAAgIbxxSRQAQAgAAAA==.Mikoya:BAAALAADCgYIBgAAAA==.Minjei:BAAALAAECggIDgABLAAFFAYICwAVAC8WAA==.Mink:BAABLAAECoEpAAIbAAgIPRoILQBWAgAbAAgIPRoILQBWAgAAAA==.Mirtazapin:BAAALAADCggICAAAAA==.Misaky:BAAALAAECgMIBAAAAA==.Mistwerfer:BAAALAAECgYIBgAAAA==.Mitra:BAAALAADCgcIDAAAAA==.',Mo='Mobie:BAACLAAFFIEFAAIhAAMIcx+JBgAdAQAhAAMIcx+JBgAdAQAsAAQKgSgABCIACAhBJVEEAMYCACIACAisHlEEAMYCACEACAj9JLQVAFcCABsABQhZHRZRAMYBAAAA.Mogar:BAAALAADCgcIAQAAAA==.Monstertruck:BAAALAADCggICAABLAAECggIJwARAM4lAA==.Monty:BAAALAADCgcIDwAAAA==.Moqz:BAAALAAFFAIIAgAAAA==.',Mu='Muhuh:BAAALAAECggICAAAAA==.Murtagh:BAAALAADCggIEAAAAA==.',My='Mykor:BAABLAAECoEXAAILAAYIEhpdbgCkAQALAAYIEhpdbgCkAQAAAA==.Myn:BAACLAAFFIEQAAIeAAUIeSVDAAAqAgAeAAUIeSVDAAAqAgAsAAQKgSEAAh4ACAhvJooAAGsDAB4ACAhvJooAAGsDAAAA.',['Mí']='Mílá:BAAALAAECgIIAgAAAA==.',['Mï']='Mïku:BAAALAAECgMIBAAAAA==.',['Mø']='Mørgana:BAAALAADCggIEAAAAA==.',Na='Nahan:BAAALAAECgIIAwAAAA==.Nalan:BAAALAADCggICAAAAA==.Naleri:BAAALAAECgYIDQAAAA==.Nastyshot:BAAALAADCggIEQAAAA==.Nays:BAAALAADCggIIAAAAA==.',Ne='Neero:BAAALAAECgYICwAAAA==.Neptun:BAAALAAECgYIDAAAAA==.',Ni='Nika:BAAALAADCggICAAAAA==.Nikos:BAAALAAECgYIEQAAAA==.Nimeji:BAACLAAFFIELAAIVAAYILxZhAwDsAQAVAAYILxZhAwDsAQAsAAQKgRQAAhUACAiKI2YJAPcCABUACAiKI2YJAPcCAAAA.Nindo:BAACLAAFFIEXAAMLAAcI9CU4AQBTAgALAAYIQiU4AQBTAgAGAAUI1yKQAgD0AQAsAAQKgSsAAwsACAjvJmsAAJQDAAsACAjeJmsAAJQDAAYACAh/Jo0BAG8DAAAA.Nindoboomer:BAAALAAECggICAABLAAFFAcIFwALAPQlAA==.Nindotwo:BAACLAAFFIEFAAMLAAMICCOMDgAWAQALAAMIxBqMDgAWAQAGAAIIDCBrEwCuAAAsAAQKgRUAAwYACAjaIyMVAKgCAAYACAjDIyMVAKgCAAsAAQjCJl7+AGAAAAEsAAUUBwgXAAsA9CUA.Nindow:BAAALAAECggIBwAAAA==.Nindowo:BAAALAAFFAIIAgABLAAFFAcIFwALAPQlAA==.Niìno:BAAALAADCgcIBwAAAA==.',Ny='Nymphadøra:BAAALAAECgYIDAAAAA==.Nyxos:BAABLAAECoEWAAIQAAgIWxdmQwAvAgAQAAgIWxdmQwAvAgAAAA==.',['Nâ']='Nânó:BAAALAAECgEIAQAAAA==.',['Nì']='Nìshi:BAAALAADCgQIBAAAAA==.',Oc='Octavius:BAAALAADCggIGQAAAA==.',Og='Ogkush:BAAALAADCgUIBQAAAA==.',Ok='Okoye:BAAALAADCgYIBgAAAA==.',Pa='Pacolitodk:BAAALAAECgUIBQABLAAECgYIDAAUAAAAAA==.Palandrios:BAACLAAFFIELAAIEAAQIbRe9CABVAQAEAAQIbRe9CABVAQAsAAQKgRwAAgQACAjMJZUEAHADAAQACAjMJZUEAHADAAEsAAUUBwgWABAA9BgA.Paper:BAAALAAFFAIIAgAAAA==.Paperwingz:BAAALAAECgcIBwAAAA==.Parishealton:BAABLAAECoEeAAIHAAgIUR5aGwB6AgAHAAgIUR5aGwB6AgAAAA==.',Pe='Pellasos:BAAALAADCgYICgAAAA==.',Ph='Philit:BAABLAAECoEZAAIjAAgI+Q8UCADzAQAjAAgI+Q8UCADzAQAAAA==.Phônix:BAAALAAECgYIDwAAAA==.',Pi='Pilsator:BAAALAAECgYIBgAAAA==.Pinacolada:BAAALAADCgYIBgAAAA==.Piscina:BAACLAAFFIEFAAIEAAIINBeMIACtAAAEAAIINBeMIACtAAAsAAQKgSgAAgQACAgqJO8PACcDAAQACAgqJO8PACcDAAAA.Piuu:BAAALAADCgcIBwABLAAFFAUICwAdANMZAA==.Pixie:BAABLAAECoEdAAMiAAgImiJaAgAcAwAiAAgImiJaAgAcAwAhAAgIPRWtIAD4AQAAAA==.',Po='Poggers:BAAALAAECgYIDAAAAA==.Pommespommes:BAAALAADCggIEAABLAAECggIJwARAM4lAA==.',Pr='Praystation:BAACLAAFFIEIAAIDAAIIriSACwDaAAADAAIIriSACwDaAAAsAAQKgSMAAwMACAgZIVoFAPsCAAMACAgZIVoFAPsCAAQABAjYC4TsAOgAAAEsAAUUAwgLABMA1CUA.Propaganda:BAAALAAECggIEAAAAA==.Prîme:BAAALAADCgYIBgAAAA==.',Pu='Purrzy:BAACLAAFFIEZAAMOAAcIPiVGAAACAwAOAAcIPiVGAAACAwAPAAEI0iG8BgBZAAAsAAQKgRoAAg4ACAivJtMIAEEDAA4ACAivJtMIAEEDAAAA.Purrzydk:BAAALAAFFAIIAgABLAAFFAcIGQAOAD4lAA==.Purrzyelf:BAAALAAECgYIBgABLAAFFAcIGQAOAD4lAA==.',['Pù']='Pùkka:BAAALAADCggIDgABLAAECgcIJgAEALQbAA==.',['Pú']='Púkka:BAABLAAECoEmAAIEAAcItBvhSgAyAgAEAAcItBvhSgAyAgAAAA==.',['Pû']='Pûkkâ:BAAALAADCgYIBgABLAAECgcIJgAEALQbAA==.',['Qú']='Qúayn:BAAALAADCgcIBwAAAA==.',Ra='Ralaa:BAACLAAFFIENAAITAAUI+RbZCQAEAQATAAUI+RbZCQAEAQAsAAQKgRsAAhMACAg0H/AZAGsCABMACAg0H/AZAGsCAAAA.Randire:BAACLAAFFIEZAAMGAAcIPyXeAABKAgAGAAYIqSPeAABKAgALAAIIaSNrGQDAAAAsAAQKgTAAAwYACAjqJt8EAEADAAYACAh0Jt8EAEADAAsABwjnJkENABkDAAAA.Ranshao:BAABLAAECoEeAAMNAAcIGyOdEwCmAgANAAcIGyOdEwCmAgATAAIIkA9GqABfAAAAAA==.',Re='Rebus:BAAALAADCggICAAAAA==.Regnia:BAACLAAFFIELAAIOAAMI+A/mHgDXAAAOAAMI+A/mHgDXAAAsAAQKgScAAw4ACAh+HO0tAHkCAA4ACAh+HO0tAHkCAA8AAggBCGIZAEoAAAAA.Reign:BAABLAAECoEbAAISAAYIkB3MXgA8AQASAAYIkB3MXgA8AQAAAA==.Rellix:BAAALAADCggICAAAAA==.',Ri='Rikuhla:BAABLAAECoEqAAIbAAgItSDFEwD1AgAbAAgItSDFEwD1AgAAAA==.',Ro='Roandra:BAACLAAFFIEEAAIIAAIIZwbWNwCCAAAIAAIIZwbWNwCCAAAsAAQKgSkAAggACAgVFB49ABYCAAgACAgVFB49ABYCAAAA.Robberdeniro:BAAALAADCgcIBwAAAA==.Rolfzukowzky:BAAALAAECgYIDAAAAA==.',Ru='Ruumi:BAEALAAFFAMIAwAAAA==.',Ry='Rymir:BAACLAAFFIEXAAMLAAYItSTzAgAKAgALAAUIXiXzAgAKAgAGAAUIlB2UBACxAQAsAAQKgTgAAwYACAjOJsADAE0DAAYACAhtJcADAE0DAAsABwjhJsINABUDAAAA.',['Râ']='Râre:BAACLAAFFIEQAAMdAAYIqg43AgDkAQAdAAYIqg43AgDkAQAaAAEI7gbPHQBHAAAsAAQKgUAAAx0ACAh8I0EDAB4DAB0ACAg7I0EDAB4DABoACAi8GWgZADoCAAAA.',['Ró']='Rócksóul:BAAALAADCggICAAAAA==.',Sa='Sakíma:BAAALAADCgEIAQAAAA==.Sanyarin:BAAALAADCgYIEAAAAA==.',Sc='Scancheck:BAAALAADCggICAAAAA==.Schuiba:BAAALAAECgcIDgAAAA==.Schutzgold:BAAALAAECgUICgABLAABCgQIAwAUAAAAAA==.Schwarmwelpe:BAAALAAECgMIBQAAAA==.Scàvenger:BAABLAAECoEaAAIHAAYIuRGCRwB2AQAHAAYIuRGCRwB2AQAAAA==.',Se='Selfishmonk:BAACLAAFFIEbAAIkAAcIBiYiAAATAwAkAAcIBiYiAAATAwAsAAQKgR8AAiQACAjvJjQAAJUDACQACAjvJjQAAJUDAAAA.Selfishw:BAABLAAECoEbAAIhAAgI7yIlBwAQAwAhAAgI7yIlBwAQAwAAAA==.Semmesane:BAABLAAECoEkAAIOAAgIqBTeRgATAgAOAAgIqBTeRgATAgAAAA==.',Sh='Shambibi:BAAALAAECggIEAAAAA==.Shanaráh:BAABLAAECoEYAAITAAcISwrWYwApAQATAAcISwrWYwApAQAAAA==.Shayajin:BAAALAAECgYICQAAAA==.',Si='Simon:BAAALAAECgMIAwABLAAECggILAATAPUiAA==.Sirunterberg:BAAALAAECgcIEgAAAA==.',Sl='Slagi:BAAALAAECggIEwAAAA==.',So='Sokrates:BAAALAAECgYIBgAAAA==.Soulbrew:BAACLAAFFIEKAAIFAAIILx2hCgCjAAAFAAIILx2hCgCjAAAsAAQKgUIAAgUACAjeIlIFACkDAAUACAjeIlIFACkDAAAA.',Sp='Spaetzle:BAAALAAECgYICwAAAA==.Spâcê:BAABLAAECoEbAAIlAAgImR/HFQCsAgAlAAgImR/HFQCsAgAAAA==.',St='Stôrmtank:BAAALAADCggIEAAAAA==.',Su='Sudowoodo:BAABLAAECoEVAAINAAgIEwqLSQBZAQANAAgIEwqLSQBZAQABLAAFFAMICwAUAAAAAA==.Sunnie:BAAALAAECgcIDwAAAA==.',Sv='Svapoo:BAAALAAECggICAAAAA==.',Ta='Talarakan:BAAALAAECgYIBgABLAAFFAcIGQAOAD4lAA==.Tarhal:BAAALAAECgMIBgAAAA==.',Te='Teci:BAAALAAECggICQAAAA==.',Th='Thanato:BAAALAADCgcICAAAAA==.Thefear:BAAALAADCggICAABLAAFFAMICwABAGwgAA==.Theos:BAAALAAECggIEAAAAA==.Thorbar:BAABLAAECoEaAAIlAAcI8hr+NAAcAgAlAAcI8hr+NAAcAgAAAA==.Thrice:BAABLAAECoEZAAISAAcIkR/xHwBcAgASAAcIkR/xHwBcAgAAAA==.',Ti='Tica:BAAALAAECggICAAAAA==.',To='Tollername:BAAALAAECgYICgAAAA==.Tonraq:BAAALAADCgEIAQAAAA==.Topf:BAAALAADCggICgAAAA==.',Tr='Triodh:BAAALAADCggICAABLAAFFAcIHAAIAMAcAA==.Triodruid:BAACLAAFFIEFAAINAAMIGxxKCQAIAQANAAMIGxxKCQAIAQAsAAQKgSYAAw0ACAjnIyQIACUDAA0ACAjnIyQIACUDABMAAQhiDAK8AC0AAAEsAAUUBwgcAAgAwBwA.Triohunt:BAABLAAECoEWAAMLAAgIqR5lSwD9AQALAAcIdR9lSwD9AQAGAAIIVh3thgCbAAABLAAFFAcIHAAIAMAcAA==.Triolock:BAACLAAFFIEcAAMIAAcIwBxGAQCjAgAIAAcIwBxGAQCjAgAKAAIIuB+kCQCuAAAsAAQKgSMAAwgACAgOJkMQAA4DAAgABwg0JkMQAA4DAAoABwgXJKwMAIkCAAAA.Triomage:BAAALAADCggIEAABLAAFFAcIHAAIAMAcAA==.Trübsal:BAABLAAECoEWAAIXAAgIqxDuGwCkAQAXAAgIqxDuGwCkAQAAAA==.',Tu='Tumbletail:BAABLAAECoEUAAIYAAcIaBJtTgCiAQAYAAcIaBJtTgCiAQABLAAECggIJQAFAP8dAA==.',Ul='Ulla:BAAALAAECgYICwAAAA==.',Ur='Ursarus:BAACLAAFFIEQAAINAAYIeCKVAAB7AgANAAYIeCKVAAB7AgAsAAQKgSIAAg0ACAi1JksAAJsDAA0ACAi1JksAAJsDAAAA.',Va='Vankara:BAABLAAECoEdAAIJAAcIkhwBBgBfAgAJAAcIkhwBBgBfAgAAAA==.',Ve='Vesta:BAAALAAECgYIDwAAAA==.Vexxz:BAABLAAECoEmAAMKAAYIyB4OJADMAQAKAAYIyB4OJADMAQAIAAYIQBexZACPAQAAAA==.',Vi='Vic:BAAALAAFFAYIGwAAAQ==.',We='Wehrmaus:BAAALAADCggICAAAAA==.',Wu='Wulle:BAABLAAECoEsAAITAAgI9SLMBwAKAwATAAgI9SLMBwAKAwAAAA==.',Xa='Xardars:BAACLAAFFIEJAAINAAQI+RNnBwA+AQANAAQI+RNnBwA+AQAsAAQKgTAAAg0ACAjjIlYLAP8CAA0ACAjjIlYLAP8CAAAA.',Xl='Xlenqt:BAAALAAECgQIBwAAAA==.',Xu='Xurian:BAABLAAECoEeAAIhAAgI3RoxGQA3AgAhAAgI3RoxGQA3AgAAAA==.',Ya='Yael:BAAALAAECgMIBAAAAA==.',Ys='Yssenia:BAAALAAECgYIBwAAAA==.',Yu='Yunademon:BAACLAAFFIEOAAIQAAUIoRz3BQDyAQAQAAUIoRz3BQDyAQAsAAQKgSYAAhAACAhWJfcFAGADABAACAhWJfcFAGADAAEsAAUUBwgWABAA9BgA.Yunalesska:BAAALAAFFAIIBAAAAA==.',Za='Zadoc:BAAALAADCgcIDQAAAA==.Zalandotroll:BAAALAADCggICAABLAAECggIJwARAM4lAA==.',Ze='Zejinn:BAAALAAECgEIAgAAAA==.Zejn:BAAALAAECgMIAwAAAA==.',Zn='Zneykh:BAAALAAECgMIBQABLAAFFAIICAASAAwIAA==.',Zt='Ztex:BAABLAAECoEoAAMZAAgIUyLwBgDWAgAZAAgIUyLwBgDWAgARAAEIhBAVSQE+AAAAAA==.',Zu='Zubaljin:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end