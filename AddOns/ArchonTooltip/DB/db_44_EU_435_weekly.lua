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
 local lookup = {'Paladin-Protection','DemonHunter-Vengeance','Mage-Arcane','Mage-Fire','Hunter-BeastMastery','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver','Paladin-Retribution','Shaman-Elemental','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination','Rogue-Subtlety','Druid-Restoration','Warrior-Fury','Shaman-Enhancement','Hunter-Marksmanship','Monk-Brewmaster','Warrior-Protection','Monk-Windwalker','Druid-Balance','DemonHunter-Havoc',}; local provider = {region='EU',realm="Gul'dan",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Acro:BAAALAAECgEIAQAAAA==.',Ad='Adania:BAACLAAFFIEOAAIBAAYIzRYQAAA3AgABAAYIzRYQAAA3AgAsAAQKgRgAAgEACAjRJYAAAHYDAAEACAjRJYAAAHYDAAAA.Adenea:BAABLAAECoEVAAICAAgIjSJIAQAiAwACAAgIjSJIAQAiAwABLAAFFAYIDgABAM0WAA==.',Ae='Aereon:BAAALAAECgQICQAAAA==.',Ai='Aishoka:BAAALAAECgcIDQAAAA==.',Al='Alkantara:BAAALAAECgIIAwAAAA==.',Am='Ambino:BAAALAADCgYIBgAAAA==.Amelie:BAAALAADCggIFQAAAA==.Amylea:BAAALAAECggIBgAAAA==.',Ar='Arendexx:BAAALAAECgYIBgAAAA==.Ariell:BAAALAADCgcIEQAAAA==.',Au='Aureeon:BAAALAAECgEIAQAAAA==.',Az='Azrâel:BAAALAAECgIIAgAAAA==.',Ba='Bamboozler:BAAALAADCgYIBgAAAA==.Bananenbrot:BAAALAAECgcIEAAAAA==.Barbepew:BAAALAADCgcIBwAAAA==.',Bl='Blindar:BAAALAADCggIDQAAAA==.Blooddorem:BAAALAADCggIEAAAAA==.Bloodfox:BAAALAADCggIDwAAAA==.Bloodhôof:BAAALAAECgEIAQAAAA==.',Br='Braxl:BAAALAAECgEIAQAAAA==.Browe:BAAALAAECgMIBAAAAA==.',Bu='Buffor:BAAALAAECgcIDQAAAA==.',Ca='Catnado:BAAALAAECgYIDQAAAA==.',Ch='Chakaron:BAACLAAFFIEMAAMDAAYIXRt4AAAHAgADAAUIGB14AAAHAgAEAAEItRL8AQBgAAAsAAQKgRgAAgMACAj7JX8AAIMDAAMACAj7JX8AAIMDAAAA.Chakaronfotm:BAABLAAECoEVAAIFAAgIwSO9AgBJAwAFAAgIwSO9AgBJAwAAAA==.Chaosgaxx:BAAALAADCgUIBQAAAA==.Chillidan:BAAALAAECgYICAAAAA==.',Cl='Cleavpala:BAAALAAECgcIEgAAAA==.Clockworkelf:BAAALAAECgcIDQABLAAFFAIIBAAGAAAAAA==.',Co='Coloris:BAAALAADCgcIDgAAAA==.Corvaz:BAACLAAFFIEOAAMHAAYIHh5CAABiAgAHAAYIHh5CAABiAgAIAAIIMBJ4BQCnAAAsAAQKgRgABAcACAiOJCECAFYDAAcACAiOJCECAFYDAAkAAwjCHE4TAAoBAAgAAgggHC1CAJQAAAAA.Corvazjr:BAABLAAECoEVAAMJAAgIDxgYBwD0AQAHAAgItBRhFwAYAgAJAAYINBoYBwD0AQAAAA==.Cowderwelsh:BAAALAADCgEIAQAAAA==.',Cy='Cyclops:BAAALAAECgEIAQAAAA==.',['Cò']='Còlós:BAAALAADCgYIBgAAAA==.',Da='Daichan:BAAALAAFFAIIBAAAAA==.Darasch:BAAALAADCggICAAAAA==.Darkwife:BAAALAAECgYICwAAAA==.',De='Deadman:BAAALAAECgcIDwAAAA==.Deathnite:BAAALAADCgEIAQAAAA==.Deekju:BAAALAAECgIIAgAAAA==.Deera:BAAALAADCgcIBwAAAA==.Deezhots:BAAALAAECgYIDAABLAAFFAIIAgAGAAAAAA==.Defty:BAAALAADCggICAAAAA==.Deicide:BAAALAAECgYIDQAAAA==.Demoholic:BAAALAAECgYIDgAAAA==.Demoniya:BAAALAAECgEIAQAAAA==.',Do='Doloria:BAAALAADCggICAAAAA==.Doom:BAAALAAECgYIBgAAAA==.Dorien:BAAALAADCgcIBwAAAA==.Doé:BAAALAADCgEIAQAAAA==.',['Dõ']='Dõt:BAAALAAECgYIBwAAAA==.',['Dü']='Düsterkeit:BAAALAADCgUIBQABLAAECggIFgAKAKoQAA==.',El='Elementauro:BAAALAAECggIDwAAAA==.',En='Enkidu:BAAALAAECgMIBQAAAA==.',Ex='Excezzdk:BAAALAAECgcIDgAAAA==.Exquisa:BAAALAAECggIEAAAAA==.Exxa:BAAALAADCggICAAAAA==.',Fe='Ferenginar:BAAALAAECgUICAAAAA==.',Fi='Finhy:BAAALAAECggIDwABLAAFFAQICgALACgWAA==.Finshii:BAACLAAFFIEKAAILAAQIKBaQAAB/AQALAAQIKBaQAAB/AQAsAAQKgRgAAgsACAi+JjoAAKADAAsACAi+JjoAAKADAAAA.Fiola:BAAALAADCgMIBAAAAA==.',Fo='Fockz:BAABLAAECoEXAAIMAAgIWiU4AQBzAwAMAAgIWiU4AQBzAwAAAA==.',Fr='Freeze:BAAALAADCgEIAQABLAADCgEIAQAGAAAAAA==.Frostshocks:BAAALAADCggICAAAAA==.',Fu='Futta:BAAALAAECgUIBgAAAA==.',Fy='Fyralath:BAAALAADCggICAAAAA==.',Ga='Gaella:BAAALAAECgMIAwAAAA==.Galaxyhunter:BAACLAAFFIEFAAIBAAMIeh62AAAgAQABAAMIeh62AAAgAQAsAAQKgRcAAgEACAg/JjUAAI0DAAEACAg/JjUAAI0DAAAA.Galimonde:BAAALAAECgIIAgAAAA==.',Ge='Georgeruney:BAAALAAECgMIBwAAAA==.',Go='Gogeta:BAAALAAECgMIAwABLAAECgcIDgAGAAAAAA==.Gon:BAAALAAECgMIBgAAAA==.',Gr='Grantorino:BAAALAADCggICAAAAA==.Greay:BAAALAAECgIIBAAAAA==.Grumpyy:BAAALAAECgIIAgAAAA==.',Ha='Haelis:BAAALAAECgEIAQABLAAECggIBAAGAAAAAA==.Hakéta:BAAALAADCgMIBAAAAA==.',He='Headshot:BAAALAAECgMIBAAAAA==.Herminé:BAAALAADCggICAAAAA==.Hexadezimal:BAAALAAECggIBAAAAA==.Hexelin:BAAALAADCgMIAwAAAA==.',Ho='Hodix:BAAALAAECgYICAAAAA==.',Hy='Hyta:BAABLAAFFIEFAAINAAMIYBEmAwAJAQANAAMIYBEmAwAJAQAAAA==.Hyy:BAAALAAECgcIDQAAAA==.',['Há']='Háudràuf:BAAALAADCgYIBgAAAA==.',['Hö']='Hösler:BAAALAAECgYIBgAAAA==.',Ig='Igotyou:BAAALAADCgIIAgAAAA==.',Il='Iladora:BAAALAADCggICAAAAA==.Iloveit:BAAALAAECggICAAAAA==.Ilovesara:BAAALAAFFAIIAgAAAA==.',Im='Impergator:BAAALAAFFAMIBQAAAQ==.',In='Inosygosa:BAACLAAFFIEOAAMOAAYIiB9vAAAXAgAOAAUISCJvAAAXAgAPAAEIxhFfAQBoAAAsAAQKgRgAAw4ACAjJJhoAAJoDAA4ACAjJJhoAAJoDAA8AAggoJccFAMkAAAAA.Inthedark:BAACLAAFFIEMAAMQAAYIBxkZAAD+AQAQAAUIkhkZAAD+AQARAAIIJhipAQCzAAAsAAQKgRgAAxEACAh/JjIAAHoDABEACAhIJTIAAHoDABAACAisJe0AAF8DAAAA.',Io='Ioreth:BAAALAAECgMIBAAAAA==.',Ir='Irondruid:BAACLAAFFIEHAAISAAMIrBcCAgADAQASAAMIrBcCAgADAQAsAAQKgRgAAhIACAjZHIgGAJ0CABIACAjZHIgGAJ0CAAAA.Ironstrike:BAAALAADCggICAAAAA==.',Ix='Ixaty:BAAALAAECgMIAwAAAA==.',Ja='Jailoss:BAAALAADCgYIBgAAAA==.',Ji='Jiaxin:BAAALAADCgYIBgAAAA==.',Jo='Joblob:BAAALAADCgcIAQAAAA==.Joliehoney:BAAALAAECgYICgAAAA==.',Ka='Karaton:BAAALAADCgcIDQAAAA==.Kasan:BAAALAADCgYIBgAAAA==.Katyparry:BAAALAAECgYIBgAAAA==.Kazmojo:BAAALAAFFAEIAQAAAA==.',Ke='Kenpachy:BAAALAADCgYIBgAAAA==.',Ki='Kitohunt:BAAALAADCgUIBQAAAA==.',Ko='Kona:BAAALAADCggICAAAAA==.Koplawu:BAAALAAECgIIAgAAAA==.',Kr='Krankenwagen:BAAALAADCggIDgABLAAECgYIBgAGAAAAAA==.',Ku='Kumâ:BAAALAAECgMIAwAAAA==.Kungfused:BAAALAADCggICAAAAA==.Kuróok:BAAALAAECgQIBQAAAA==.Kushzz:BAAALAADCggICAAAAA==.',Kv='Kvelertak:BAAALAADCggIEQAAAA==.',['Kî']='Kîto:BAAALAADCgcIBwAAAA==.',La='Lathgertha:BAAALAAECgQIBgAAAA==.',Li='Liandor:BAAALAADCggICAAAAA==.Likkiste:BAEALAAECgcIDQAAAA==.Littledark:BAAALAAECgIIAwAAAA==.',Lo='Lodotomy:BAAALAADCggIEgAAAA==.Lonlenin:BAAALAAECgIIAwAAAA==.',Lu='Lumínár:BAAALAADCgIIAgAAAA==.Lumøs:BAAALAAECgMIAwAAAA==.',Ly='Lycanstrasz:BAAALAAECggIDwAAAA==.Lycanthrope:BAACLAAFFIELAAISAAUISx9JAADzAQASAAUISx9JAADzAQAsAAQKgRgAAhIACAjVJEMBADADABIACAjVJEMBADADAAAA.',['Lú']='Lúkado:BAAALAADCgUIBQAAAA==.',Ma='Mallee:BAAALAADCgMIAwAAAA==.Matekstrasza:BAAALAAECgMIBAAAAA==.',Me='Medusa:BAAALAADCgcIBgAAAA==.',Mi='Miesmuschel:BAAALAAECgYICwAAAA==.Minjei:BAAALAAECggIDgABLAAFFAYICAAOAHESAA==.Mink:BAABLAAECoEVAAITAAgIBA+oGQAHAgATAAgIBA+oGQAHAgAAAA==.Misaky:BAAALAAECgMIBAAAAA==.Mistwerfer:BAAALAAECgYIBgAAAA==.Mitra:BAAALAADCgcIDAAAAA==.',Mo='Mobie:BAAALAAECggICAAAAA==.Mogar:BAAALAADCgcIAQAAAA==.Monstertruck:BAAALAADCggICAABLAAFFAIIBAAGAAAAAA==.Monty:BAAALAADCgcIDwAAAA==.',My='Mykor:BAAALAAECgYIDAAAAA==.Myn:BAABLAAECoEYAAIUAAgI1SU+AABpAwAUAAgI1SU+AABpAwAAAA==.',['Mï']='Mïku:BAAALAADCggICAAAAA==.',Na='Nahan:BAAALAAECgEIAQAAAA==.Nalan:BAAALAADCgcIBwAAAA==.Naleri:BAAALAAECgEIAQAAAA==.Nays:BAAALAADCggIGAAAAA==.',Ni='Nikos:BAAALAAECgEIAQAAAA==.Nimeji:BAABLAAFFIEIAAIOAAYIcRJlAAAkAgAOAAYIcRJlAAAkAgAAAA==.Nindo:BAACLAAFFIEKAAMVAAUIqx62AACDAQAVAAQI1xy2AACDAQAFAAIIKhpEBADDAAAsAAQKgRgAAhUACAh1JiYAAIwDABUACAh1JiYAAIwDAAAA.Nindotwo:BAABLAAECoEVAAMVAAgI2iOCBAD9AgAVAAgIwyOCBAD9AgAFAAEIwiYOagBzAAABLAAFFAUICgAVAKseAA==.Niìno:BAAALAADCgcIBwAAAA==.',Ny='Nyxos:BAAALAAECggIDgAAAA==.',['Nâ']='Nânó:BAAALAAECgEIAQAAAA==.',Og='Ogkush:BAAALAADCgUIBQAAAA==.',Ok='Okoye:BAAALAADCgYIBgAAAA==.',Pa='Palandrios:BAAALAAFFAIIAgAAAA==.Paper:BAAALAAECgMIBAAAAA==.Parishealton:BAAALAAECgYICgAAAA==.',Pe='Pellasos:BAAALAADCgYICgAAAA==.',Ph='Philit:BAAALAAECgQICAAAAA==.Phônix:BAAALAAECgIIAgAAAA==.',Pi='Pinacolada:BAAALAADCgYIBgAAAA==.Piscina:BAABLAAECoEYAAILAAgI1yE+CQD6AgALAAgI1yE+CQD6AgAAAA==.Piuu:BAAALAADCgcIBwAAAA==.Pixie:BAAALAAECgcIDQAAAA==.',Po='Pommespommes:BAAALAADCggIEAABLAAFFAIIBAAGAAAAAA==.',Pr='Praystation:BAAALAAFFAIIAgAAAA==.Propaganda:BAAALAAECggIEAAAAA==.Prîme:BAAALAADCgYIBgAAAA==.',Pu='Purrzy:BAACLAAFFIEMAAMDAAYI0yJTAAAWAgADAAUIBiNTAAAWAgAEAAEI0iGXAQBrAAAsAAQKgRgAAgMACAivJqMAAH4DAAMACAivJqMAAH4DAAAA.Purrzydk:BAAALAAECggIDwABLAAFFAYIDAADANMiAA==.Purrzyelf:BAAALAAECgYIBgABLAAFFAYIDAADANMiAA==.',['Pú']='Púkka:BAAALAAECgYICwAAAA==.',['Pû']='Pûkkâ:BAAALAADCgYIBgABLAAECgYICwAGAAAAAA==.',Ra='Ralaa:BAACLAAFFIEFAAISAAMIthjCAQAOAQASAAMIthjCAQAOAQAsAAQKgRcAAhIACAggHkEKAGUCABIACAggHkEKAGUCAAAA.Randire:BAACLAAFFIEMAAIVAAYI+hoTAABDAgAVAAYI+hoTAABDAgAsAAQKgRgAAhUACAhWJqwAAGIDABUACAhWJqwAAGIDAAAA.Ranshao:BAAALAAECgYICgAAAA==.',Re='Rebus:BAAALAADCggICAAAAA==.Regnia:BAAALAAFFAEIAQAAAA==.Reign:BAAALAAECgMIBAAAAA==.Rellix:BAAALAADCggICAAAAA==.',Ri='Rikuhla:BAAALAAECgcIDgAAAA==.',Ro='Roandra:BAABLAAECoEUAAIHAAcIXwv4JgCaAQAHAAcIXwv4JgCaAQAAAA==.Robberdeniro:BAAALAADCgcIBwAAAA==.Rolfzukowzky:BAAALAAECgIIAgAAAA==.',Ru='Ruumi:BAAALAAECgYIDAAAAA==.',Ry='Rymir:BAACLAAFFIEFAAIVAAMIJiGGAQAeAQAVAAMIJiGGAQAeAQAsAAQKgRgAAhUACAgwIvcCAB4DABUACAgwIvcCAB4DAAAA.',['Râ']='Râre:BAABLAAECoEgAAMRAAgI6iA6AQAEAwARAAgI5B86AQAEAwAQAAgIvBn1CgCEAgAAAA==.',['Ró']='Rócksóul:BAAALAADCggICAAAAA==.',Sa='Sakíma:BAAALAADCgEIAQAAAA==.Sanyarin:BAAALAADCgUICwAAAA==.',Sc='Schuiba:BAAALAAECgMIBwAAAA==.Schwarmwelpe:BAAALAADCggIDQAAAA==.Scàvenger:BAAALAAECgYICQAAAA==.',Se='Selfishmonk:BAACLAAFFIEOAAIWAAYIYCISAAB6AgAWAAYIYCISAAB6AgAsAAQKgRgAAhYACAjrJgQAAK0DABYACAjrJgQAAK0DAAAA.Selfishw:BAABLAAECoEVAAIXAAgI7SAABADQAgAXAAgI7SAABADQAgAAAA==.Semmesane:BAAALAAECgcIDgAAAA==.',Sh='Shambibi:BAAALAAECggICAAAAA==.Shanaráh:BAAALAAECgQIBgAAAA==.',Si='Simon:BAAALAADCgcIBwABLAAECgcIEAAGAAAAAA==.',Sl='Slagi:BAAALAAECgUIBwAAAA==.',So='Sokrates:BAAALAADCggIBgAAAA==.Soulbrew:BAABLAAECoEZAAIYAAcIwRieEAC5AQAYAAcIwRieEAC5AQAAAA==.',Sp='Spâcê:BAAALAAECgcIDwAAAA==.',Su='Sudowoodo:BAABLAAECoEVAAIZAAgIEgqBHwCTAQAZAAgIEgqBHwCTAQABLAAFFAMIBQAGAAAAAA==.Sunnie:BAAALAAECgIIAgAAAA==.',Ta='Tarhal:BAAALAAECgMIBgAAAA==.',Te='Teci:BAAALAADCggIEAAAAA==.',Th='Thanato:BAAALAADCgcICAAAAA==.Thefear:BAAALAADCggICAABLAAFFAMIBQABAHoeAA==.Thorbar:BAAALAAECgQIBgAAAA==.Thrice:BAAALAAECgYIDQAAAA==.',Ti='Tica:BAAALAADCggICAAAAA==.',To='Tollername:BAAALAAECgYIBgAAAA==.Tonraq:BAAALAADCgEIAQAAAA==.',Tr='Triodh:BAAALAADCggICAABLAAFFAQICAAIALkbAA==.Triodruid:BAABLAAECoEWAAMZAAgItCLdBQD2AgAZAAgItCLdBQD2AgASAAEIYgxrXwAyAAABLAAFFAQICAAIALkbAA==.Triohunt:BAAALAAECggIDgABLAAFFAQICAAIALkbAA==.Triolock:BAACLAAFFIEIAAMIAAQIuRvmAQDBAAAIAAIIuB/mAQDBAAAHAAIIuReiBgC/AAAsAAQKgRYAAwgACAiSI0cDALoCAAgABwh8I0cDALoCAAcABQgVIbYiALkBAAAA.Triomage:BAAALAADCggIEAABLAAFFAQICAAIALkbAA==.Trübsal:BAABLAAECoEWAAIKAAgIqhDyDADTAQAKAAgIqhDyDADTAQAAAA==.',Ur='Ursarus:BAACLAAFFIEGAAIZAAQIwSRMAADHAQAZAAQIwSRMAADHAQAsAAQKgRYAAhkACAi4JZkAAH4DABkACAi4JZkAAH4DAAAA.',Va='Vankara:BAAALAAECgUICQAAAA==.',Ve='Vesta:BAAALAADCggICgAAAA==.Vexxz:BAAALAAECgYIDgAAAA==.',Vi='Vic:BAAALAAFFAMIBwAAAQ==.',We='Wehrmaus:BAAALAADCggICAAAAA==.',Wu='Wulle:BAAALAAECgcIEAAAAA==.',Xa='Xardars:BAABLAAECoEYAAIZAAgIHxqfCQCjAgAZAAgIHxqfCQCjAgAAAA==.',Xl='Xlenqt:BAAALAAECgQIBwAAAA==.',Xu='Xurian:BAAALAAECgcIDgAAAA==.',Ya='Yael:BAAALAAECgMIBAAAAA==.',Ys='Yssenia:BAAALAAECgYIBwAAAA==.',Yu='Yunademon:BAABLAAECoEVAAIaAAgIDSDQJAD7AQAaAAgIDSDQJAD7AQABLAAFFAIIAgAGAAAAAA==.Yunalesska:BAAALAAECggIEwAAAA==.',Za='Zadoc:BAAALAADCgYIBgAAAA==.Zalandotroll:BAAALAADCggICAABLAAFFAIIBAAGAAAAAA==.',Ze='Zejn:BAAALAADCgcIBwAAAA==.',Zn='Zneykh:BAAALAAECgMIBQAAAA==.',Zt='Ztex:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end