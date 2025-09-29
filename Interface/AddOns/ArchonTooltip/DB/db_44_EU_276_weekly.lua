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
 local lookup = {'Druid-Balance','Monk-Brewmaster','Shaman-Restoration','Unknown-Unknown','Hunter-Survival','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Enhancement','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Retribution','Priest-Shadow','Warrior-Protection','Shaman-Elemental','Paladin-Protection','Mage-Arcane','Paladin-Holy','Mage-Frost','Priest-Discipline','Evoker-Devastation','Priest-Holy','Druid-Feral','Druid-Guardian','Monk-Windwalker','Rogue-Outlaw','Warrior-Arms','Evoker-Augmentation','Mage-Fire',}; local provider = {region='EU',realm='DarkmoonFaire',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaronm:BAAALAAECgEIAQAAAA==.',Ab='Absents:BAAALAADCgcIDAAAAA==.Abyssion:BAAALAAECgUICAAAAA==.Abzap:BAAALAADCgUIBQAAAA==.',Ad='Addzy:BAAALAADCggICAAAAA==.',Ag='Agammer:BAAALAAECgcIEgAAAA==.',Al='Alaania:BAAALAAECgMIBAAAAA==.Aleaxia:BAAALAAECgMIBQAAAA==.Alfr:BAABLAAECoEbAAIBAAgIgR4SEgCwAgABAAgIgR4SEgCwAgAAAA==.Alkyholix:BAABLAAECoEZAAICAAcIJhyvDwAsAgACAAcIJhyvDwAsAgAAAA==.Altais:BAABLAAECoEmAAIDAAgIhBI6UQC5AQADAAgIhBI6UQC5AQAAAA==.',Am='Amaryth:BAAALAAECggICAAAAA==.',An='Anevay:BAAALAADCggICAAAAA==.Antares:BAAALAAECgEIAQABLAAECgIIAgAEAAAAAA==.',Ao='Aorli:BAAALAAECgIIAgAAAA==.',Ar='Aragor:BAAALAADCgQIBAAAAA==.Argyros:BAABLAAECoEXAAIFAAcIOwzbDgCFAQAFAAcIOwzbDgCFAQAAAA==.Artas:BAAALAAECgUIBQAAAA==.',As='Asdfqwerty:BAAALAADCgUIDAAAAA==.Ashauna:BAABLAAECoEcAAIGAAgIcgsCWACtAQAGAAgIcgsCWACtAQAAAA==.Askja:BAAALAADCgYIBgAAAA==.Asteryn:BAAALAAECgYICgAAAA==.Astraia:BAABLAAECoEmAAMHAAgIByRTBwDTAgAHAAcI8CNTBwDTAgAIAAYI0Rt9CQAFAgAAAA==.',At='Athai:BAAALAADCgYIBgABLAAECggIJgAHAAckAA==.',Au='Auralia:BAAALAAECgYIEwAAAA==.Autem:BAAALAAECggICAAAAA==.',Av='Avoidelf:BAAALAAECgYICQAAAA==.',Az='Azarria:BAAALAADCggICAAAAA==.Azeranka:BAABLAAECoEVAAIJAAcIQg9+jwCeAQAJAAcIQg9+jwCeAQAAAA==.',Ba='Baldfatugly:BAAALAADCggICAAAAA==.',Be='Bella:BAAALAADCgcICgAAAA==.Bellecarlsen:BAACLAAFFIEKAAQJAAII7R+3JQCwAAAJAAII7R+3JQCwAAAKAAIIVR4FCACnAAALAAEIvRmVFQBWAAAsAAQKgSYAAwoACAgsIlUFAPsCAAoACAinIVUFAPsCAAkACAjUHqMkALgCAAEsAAUUCAgVAAkAiCQA.Berna:BAAALAAECgYICAAAAA==.Beshamel:BAABLAAECoEfAAIMAAgIpiHHAwDfAgAMAAgIpiHHAwDfAgABLAAECggIHwANAHQgAA==.',Bi='Bigwild:BAABLAAECoEaAAMOAAgIthxfKgBpAgAOAAgI1BtfKgBpAgAPAAcIPhA2SwBpAQAAAA==.',Bl='Bloodymarry:BAAALAAECgYICAAAAA==.',Bm='Bmo:BAAALAADCggICAAAAA==.',Bo='Boann:BAAALAAECgQIBQAAAA==.Bombard:BAAALAAECgcICQABLAAECgcIFgAGAGAcAA==.',Br='Brambull:BAAALAAECgQIBAABLAAECgcIGQACACYcAA==.Brocken:BAAALAAECgYICQAAAA==.Brynnd:BAAALAADCggIDgABLAAECgEIAQAEAAAAAA==.Bréalan:BAAALAAECgEIAQABLAAECgYICwAEAAAAAA==.',['Bæ']='Bæl:BAABLAAECoEkAAIDAAgI6BwsHgB2AgADAAgI6BwsHgB2AgAAAA==.',Ca='Candyfloss:BAAALAADCgcIHAAAAA==.Caílleach:BAAALAADCgcIBwAAAA==.',Ce='Celestiné:BAAALAAECgYIDAAAAA==.Celticdemhun:BAAALAAECgYIBgABLAAECgcIGAAQABoJAA==.Cenai:BAAALAAECggICAAAAA==.',Ch='Chalima:BAAALAAECgUIBwAAAA==.Chinde:BAABLAAECoEeAAIRAAgIqCBhBQDfAgARAAgIqCBhBQDfAgAAAA==.Chindera:BAAALAADCggICAABLAAECggIHgARAKggAA==.',Cl='Clotsby:BAAALAADCgcIEAAAAA==.',Co='Coothburt:BAAALAADCgYIBgAAAA==.Cortius:BAAALAAECgYIBgAAAA==.Cosmos:BAAALAAECgYICQAAAA==.',Cr='Crimsonlich:BAAALAADCgQIBgAAAA==.Crimsonrider:BAAALAADCgcIBwAAAA==.',Cu='Cupquake:BAAALAADCggIIAAAAA==.',Da='Daeish:BAAALAADCgYIBgABLAADCggIEAAEAAAAAA==.Daerauko:BAAALAADCggIEAAAAA==.Dakeyras:BAABLAAECoEnAAISAAgIkCB6CQDkAgASAAgIkCB6CQDkAgAAAA==.Danthorius:BAAALAAECgQICQAAAA==.Darksiner:BAAALAAECggIAQAAAA==.Darthchaos:BAABLAAECoEkAAILAAcIHhwUDgBXAgALAAcIHhwUDgBXAgAAAA==.Datsun:BAABLAAECoEnAAITAAgIBg5HHgCDAQATAAgIBg5HHgCDAQAAAA==.Daé:BAAALAADCgYIDAABLAADCggIEAAEAAAAAA==.',De='Deadlykiller:BAABLAAECoEkAAMUAAcInyXUFQD5AgAUAAcInyXUFQD5AgAVAAEIPhrxTwBIAAAAAA==.Deadlyplague:BAAALAADCggICAABLAAECgcIJAAUAJ8lAA==.Deadlyrage:BAAALAADCggICAABLAAECgcIJAAUAJ8lAA==.Deathsmane:BAABLAAECoEYAAMJAAgI2SChKQChAgAJAAgI6R+hKQChAgAKAAYISR9TFwCkAQAAAA==.Deirius:BAAALAAECggICQAAAA==.Delena:BAAALAAECgYICQAAAA==.Delygoon:BAAALAAECggIEgABLAAFFAMICAAWACMdAA==.Delynel:BAAALAAECgEIAQABLAAFFAMICAAWACMdAA==.Demonspear:BAAALAADCggIEAAAAA==.Derelicta:BAABLAAECoEnAAIKAAgI6RWGEQD4AQAKAAgI6RWGEQD4AQAAAA==.',Di='Diablø:BAAALAAECggIBgAAAA==.Diananomimec:BAAALAAECgQICAAAAA==.Dilo:BAAALAADCggICAAAAA==.Dink:BAAALAAECggICQAAAA==.Divinewill:BAAALAADCgUIDgAAAA==.',Dj='Djentlidan:BAAALAADCgMIAwAAAA==.',Do='Dorp:BAAALAAECgQICQAAAA==.',Dr='Draconic:BAAALAAECgIIAgABLAAECgcIFgAGAGAcAA==.Dragonbreat:BAAALAADCgQIAgAAAA==.Draktharr:BAAALAAECgcIDQAAAA==.Drangon:BAAALAADCggIDwAAAA==.Dreamm:BAAALAADCggIDgAAAA==.Druidsmaid:BAAALAADCggICAAAAA==.Dréxzi:BAAALAAECgQIBwAAAA==.',Dw='Dwabz:BAAALAAECgYICQAAAA==.Dwarein:BAAALAADCgcIGwABLAADCggIFAAEAAAAAA==.',['Dá']='Dágón:BAAALAAECgIIAgAAAA==.',['Dë']='Dëmönböï:BAABLAAECoEdAAIUAAgIwxUPUgD6AQAUAAgIwxUPUgD6AQAAAA==.',Ed='Eddyscritch:BAABLAAECoEjAAIBAAgIniLmCgAAAwABAAgIniLmCgAAAwAAAA==.',Ei='Eiveth:BAABLAAECoEdAAIDAAcIkhRvYACQAQADAAcIkhRvYACQAQAAAA==.',El='Elleí:BAAALAADCggIDgAAAA==.',Em='Emer:BAAALAADCgcIBwAAAA==.',Er='Eriksen:BAAALAAECgQICQAAAA==.',Es='Esuvius:BAAALAAECgEIAQAAAA==.',Ew='Ewavy:BAAALAAECgMIBgAAAA==.',Ex='Exavu:BAAALAAECgcIBwABLAAECggIGwABAIEeAA==.',Fa='Falanyr:BAABLAAECoEWAAIXAAgIxheBJQAmAgAXAAgIxheBJQAmAgAAAA==.Falkrathin:BAAALAAECgQIBAAAAA==.Fanetrotil:BAABLAAFFIEFAAIYAAMItgi2CwCzAAAYAAMItgi2CwCzAAAAAA==.Fanumtax:BAAALAAECgEIAQAAAA==.',Fe='Feigenbaum:BAABLAAECoEUAAMJAAYIbx/tcgDVAQAJAAYIHRvtcgDVAQALAAMIUh8XMwAPAQAAAA==.Felwînd:BAAALAADCgcIBwAAAA==.Fenrir:BAAALAAECgMIAwAAAA==.Fesh:BAAALAAECgcICgAAAA==.',Fi='Fitze:BAABLAAECoEdAAIUAAcI5iAAKQCQAgAUAAcI5iAAKQCQAgAAAA==.',Fl='Flexbluger:BAAALAADCgcIBwAAAA==.Flisc:BAAALAADCggIGAAAAA==.Flokis:BAAALAAECggICAAAAA==.Flowdiebow:BAABLAAECoEhAAMZAAgIUhEsNgD+AQAZAAgIUhEsNgD+AQADAAcIGAVHsgDUAAAAAA==.Fluor:BAAALAAECgQIBAAAAA==.Flóp:BAABLAAECoEZAAIaAAcI0RNDJgCCAQAaAAcI0RNDJgCCAQAAAA==.Flópsox:BAAALAADCggICAABLAAECgcIGQAaANETAA==.Flýnn:BAAALAAECgEIAQAAAA==.',Fr='Freezia:BAAALAAECgIIAgAAAA==.Frixion:BAAALAAECgUICwAAAA==.Frékor:BAAALAAECgEIAQAAAA==.',Fu='Fungral:BAAALAADCgcIBwAAAA==.Furila:BAAALAADCgEIAQAAAA==.Furstrike:BAABLAAECoEsAAIbAAgIOx6uKgCCAgAbAAgIOx6uKgCCAgAAAA==.',Ga='Gawain:BAABLAAECoEnAAIWAAgIUBvsNgBpAgAWAAgIUBvsNgBpAgAAAA==.',Ge='Geniisis:BAABLAAECoEUAAMJAAYIXQaB4wAIAQAJAAYITwaB4wAIAQALAAIILQPASgBcAAAAAA==.Georgy:BAAALAADCggICwAAAA==.',Gi='Gizzmir:BAAALAADCgYIBgAAAA==.',Gl='Gliggy:BAAALAADCggICAAAAA==.',Gr='Grandalph:BAAALAADCgYIBgAAAA==.Greystork:BAAALAAECgYICAAAAA==.',Gt='Gtfo:BAAALAADCggIDQAAAA==.',Ha='Hajashi:BAAALAAECgYIEgAAAA==.Hamura:BAAALAADCgEIAQAAAA==.Haverok:BAAALAAECgQIAwAAAA==.Hawkers:BAABLAAECoEfAAIWAAcIXQ3ujwCUAQAWAAcIXQ3ujwCUAQAAAA==.',He='Hessonite:BAAALAAECgYIDwAAAA==.',Ho='Holycritzs:BAABLAAECoElAAIcAAgI9BcQFgAuAgAcAAgI9BcQFgAuAgAAAA==.Holydjent:BAAALAADCgcICAAAAA==.Holygóat:BAAALAAECggICAABLAAECggIJgAdAKMTAA==.Holynell:BAACLAAFFIEIAAIWAAMIIx3RCwAMAQAWAAMIIx3RCwAMAQAsAAQKgR0AAhYACAjgJBcQACQDABYACAjgJBcQACQDAAAA.',['Há']='Hágríd:BAABLAAECoEYAAMeAAcIVhKGDQCVAQAeAAcIVhKGDQCVAQAXAAQI0wpSawC0AAAAAA==.',['Hé']='Héla:BAAALAADCgEIAQABLAAECggIIwAfADUfAA==.',Id='Idis:BAABLAAECoEdAAIOAAcIqxBYcACTAQAOAAcIqxBYcACTAQAAAA==.',In='Incense:BAAALAADCgYIBgABLAAECggIEAAEAAAAAA==.Invi:BAAALAAECgYIDgAAAA==.',Io='Ionns:BAAALAAECgIIAgAAAA==.',It='Ithryllian:BAAALAAECgEIAQAAAA==.Ito:BAAALAADCgcICgAAAA==.',Ja='Jacobriley:BAAALAAECgIIAQAAAA==.Jarza:BAAALAAECgcIBwAAAA==.Jass:BAAALAADCgQIBAABLAAFFAIIAgAEAAAAAA==.Jaye:BAABLAAECoEbAAIUAAgIVyQhBwBVAwAUAAgIVyQhBwBVAwAAAA==.Jayee:BAACLAAFFIEaAAIGAAUICB24BgD/AQAGAAUICB24BgD/AQAsAAQKgVIAAwYACAhnJm0CAHsDAAYACAhnJm0CAHsDAAgABgi5C48TAGIBAAAA.Jaygue:BAAALAAECgYIEAABLAAECggIGwAUAFckAA==.Jaz:BAAALAAFFAIIAgAAAA==.Jazzasaurus:BAAALAAECgEIAQABLAAFFAIIAgAEAAAAAA==.Jazzii:BAAALAAECgEIAQABLAAECgIIAQAEAAAAAA==.Jazzy:BAABLAAECoEgAAIOAAgIzBH5YgCzAQAOAAgIzBH5YgCzAQABLAAFFAIIAgAEAAAAAA==.',Je='Jesmyn:BAABLAAECoEeAAIPAAgIPSETCwD/AgAPAAgIPSETCwD/AgAAAA==.Jessi:BAAALAADCgcIBwAAAA==.Jessia:BAAALAAECggICAAAAA==.Jezebel:BAAALAAECggICAAAAA==.',Jo='Jokeski:BAABLAAECoEbAAIGAAgIMR0TIACiAgAGAAgIMR0TIACiAgAAAA==.Jomoo:BAAALAADCgYIBgAAAA==.',Ju='Judgejez:BAAALAADCgcIBwABLAAECgIIAQAEAAAAAA==.Jujucat:BAAALAAECggIDQAAAA==.Jujushin:BAAALAADCggICAAAAA==.',Jv='Jvz:BAACLAAFFIEHAAIdAAMIsA9kBADbAAAdAAMIsA9kBADbAAAsAAQKgSAAAh0ACAgwHX0OAJUCAB0ACAgwHX0OAJUCAAAA.',Jx='Jxshy:BAAALAAECgYIBgABLAAECggIHAAGAKwfAA==.',Jy='Jylani:BAAALAAECgMIBQABLAAFFAMIBwAdALAPAA==.',Ka='Kaasuidpow:BAAALAADCgcIDQAAAA==.Kah:BAAALAADCggIDQAAAA==.Kairos:BAAALAAECgIIAgAAAA==.Kaizhan:BAAALAAECggIDwAAAA==.Kalasgösta:BAAALAADCggICAAAAA==.Kalaskillen:BAABLAAECoEdAAMPAAcIEx9NGgB3AgAPAAcIEx9NGgB3AgAOAAQIWxP2ugDzAAAAAA==.Kambui:BAACLAAFFIERAAIbAAYI/RtOAgBOAgAbAAYI/RtOAgBOAgAsAAQKgTUAAhsACAhgJjsDAG0DABsACAhgJjsDAG0DAAAA.Karfhudd:BAABLAAECoEfAAINAAgIdCAJFADtAgANAAgIdCAJFADtAgAAAA==.Karsaorlong:BAAALAAECggIDAAAAA==.Karsus:BAABLAAECoEhAAIXAAgI0ghDRQB6AQAXAAgI0ghDRQB6AQAAAA==.Kazage:BAAALAAECggICAAAAA==.Kazima:BAAALAADCgYIBgABLAAECggICAAEAAAAAA==.',Kc='Kcsino:BAAALAAECgEIAQAAAA==.',Ki='Kienna:BAAALAADCggICAAAAA==.Kiroutus:BAAALAADCgQIBAABLAADCgYIBgAEAAAAAA==.',Ko='Kogan:BAAALAAECgUICAAAAA==.',Kr='Krotas:BAAALAADCggICAABLAAECgcICQAEAAAAAA==.',Ku='Kurama:BAAALAADCgEIAQAAAA==.',['Ká']='Kárathas:BAAALAADCgEIAQAAAA==.',La='Laíka:BAAALAAECgQICQAAAA==.',Le='Letmelive:BAABLAAECoEWAAMgAAgIIxUyMwDqAQAgAAgIIxUyMwDqAQAeAAEIKw4+MQAyAAAAAA==.Letmepray:BAAALAAECgcIDAAAAA==.',Li='Liara:BAABLAAECoEfAAIPAAgINiMfBgAyAwAPAAgINiMfBgAyAwAAAA==.Lielee:BAAALAAECgEIAgAAAA==.Lien:BAAALAAECgMIBwAAAA==.Lighte:BAAALAADCggIDwAAAA==.Lilidria:BAAALAADCgcIBwAAAA==.Lindome:BAAALAAECgYIBgAAAA==.',Lj='Ljosdottir:BAAALAADCggIDgABLAADCggIEAAEAAAAAA==.',Lo='Lockadina:BAAALAAECgIIAgAAAA==.Lorali:BAAALAADCggICgAAAA==.Lorkas:BAAALAADCgEIAQAAAA==.Louriele:BAAALAAECgIIAQAAAA==.',Lu='Lucianmoon:BAABLAAECoEnAAIcAAgIBhytDACQAgAcAAgIBhytDACQAgAAAA==.Lucinder:BAAALAAFFAIIAgAAAA==.Luella:BAAALAAECgQIBAAAAA==.Lufen:BAAALAADCgYIBgABLAAECgYIBgAEAAAAAA==.Lufien:BAAALAAECgYIBgAAAA==.Luobinghe:BAABLAAECoEUAAMIAAYIFQnIHgDVAAAGAAUI+AbEmgDrAAAIAAQIEgnIHgDVAAAAAA==.Lupei:BAAALAAECgcIDgAAAA==.',Ly='Lyaena:BAAALAAECgYIDwAAAA==.Lykopas:BAAALAAECgIIAgAAAA==.Lyrilla:BAAALAAECgMIAwAAAA==.',Ma='Madworgen:BAAALAAECgYIBwAAAA==.Magnetar:BAAALAADCggICAAAAA==.Makavalian:BAAALAAECgYICQAAAA==.Makoto:BAAALAADCgcICwAAAA==.Malekíth:BAAALAAECgIIAgAAAA==.Malilock:BAABLAAECoElAAQGAAgIOyGtFQDlAgAGAAgIrh+tFQDlAgAIAAcIBRlrBwA0AgAHAAIIwR3rZACkAAAAAA==.Malimoo:BAAALAADCgQIBAABLAAECggIJQAGADshAA==.Manlike:BAAALAADCggICAAAAA==.Marna:BAAALAADCggICAAAAA==.Marthen:BAAALAADCggIEAABLAAECgMIBAAEAAAAAA==.Maudie:BAAALAAECgUIBwAAAA==.Mawser:BAAALAADCgcIBQAAAA==.Maxikatí:BAAALAAECgIIAgAAAA==.Mazikéén:BAAALAAECgIIAgAAAA==.Mazzeltoff:BAAALAAECgYIBgAAAA==.',Mb='Mbabu:BAAALAADCgUIBgAAAA==.',Me='Mealiegrace:BAAALAADCggICAAAAA==.Meow:BAABLAAECoEYAAIhAAgIiSJnAwAoAwAhAAgIiSJnAwAoAwAAAA==.Meriel:BAABLAAECoEXAAINAAcI2RkgOgAQAgANAAcI2RkgOgAQAgAAAA==.',Mi='Milkygoth:BAAALAAECgQIBwAAAA==.Milkytbh:BAABLAAECoEgAAIaAAgIAh/4BwDVAgAaAAgIAh/4BwDVAgAAAA==.Mindgames:BAACLAAFFIEHAAIXAAMIkx68CgAPAQAXAAMIkx68CgAPAQAsAAQKgTgAAxcACAgnJSsDAGUDABcACAgnJSsDAGUDACAAAQhUDvyeADYAAAAA.Minibrew:BAABLAAECoEUAAICAAYIMSOiDABfAgACAAYIMSOiDABfAgAAAA==.Mirel:BAAALAAECgMIAwAAAA==.Mirthiora:BAAALAADCggICAAAAA==.Misquamacus:BAAALAADCgYIBgAAAA==.Mitars:BAABLAAECoEiAAIDAAgIjw/sZQCAAQADAAgIjw/sZQCAAQAAAA==.',Mo='Moochad:BAAALAADCggICAAAAA==.Moonfan:BAAALAAECgIIAgAAAA==.Moonwatcher:BAAALAADCgcICgAAAA==.',My='Mystalina:BAAALAADCgcIDQAAAA==.',['Mó']='Mógui:BAABLAAECoEjAAIJAAgIuxD4bQDfAQAJAAgIuxD4bQDfAQAAAA==.',Na='Naff:BAAALAAECggIEAAAAA==.Natháhnos:BAAALAAECgYIEAAAAA==.Naturègrasp:BAAALAADCgQIBgAAAA==.Naustyy:BAAALAAECggICAAAAA==.',Ne='Neim:BAAALAAECggIEAAAAA==.Nekochan:BAAALAAECggIEAAAAA==.',Ni='Nidur:BAAALAAECgYICAAAAA==.Niff:BAAALAAFFAIIAgAAAA==.Nigel:BAACLAAFFIEHAAILAAMIGR5oAwAjAQALAAMIGR5oAwAjAQAsAAQKgTEAAwsACAgyJd0BAEsDAAsACAh+JN0BAEsDAAoABwjTIzMIALICAAAA.Nimoria:BAAALAADCgEIAQAAAA==.Nimp:BAAALAAECgQIBAAAAA==.',No='Nof:BAAALAAECgEIAQAAAA==.Noff:BAAALAADCgEIAQAAAA==.Normanbatés:BAAALAADCgcIDgAAAA==.Noshards:BAAALAAECgcIEQAAAA==.Nová:BAAALAADCgcIBwABLAAECgQIBgAEAAAAAA==.',Nu='Nutmeg:BAAALAAECgQIBAAAAA==.',Ny='Nyarlock:BAAALAADCggICAAAAA==.Nymh:BAAALAAECgQICQAAAA==.Nyárla:BAABLAAECoEmAAIdAAgIoxN0GgAbAgAdAAgIoxN0GgAbAgAAAA==.',['Nè']='Nèlliel:BAAALAAECgYIEQABLAAECggIEAAEAAAAAA==.',['Nò']='Nòva:BAAALAADCgUIBQABLAAECgQIBgAEAAAAAA==.',['Nø']='Nøh:BAAALAAECgEIAQAAAA==.',Ol='Ollka:BAAALAAECgQIBAAAAA==.',Om='Omnirole:BAABLAAECoEYAAIQAAcIGgmtZgAXAQAQAAcIGgmtZgAXAQAAAA==.',Op='Ophy:BAAALAAECgcIEQAAAA==.',Or='Orumi:BAAALAAECggIIQAAAQ==.',Ow='Owlgebra:BAABLAAECoEfAAIiAAcIeyKbBAClAgAiAAcIeyKbBAClAgAAAA==.',Pa='Pallypriest:BAABLAAECoEaAAIgAAcIBQyZUwBeAQAgAAcIBQyZUwBeAQAAAA==.Parafix:BAABLAAECoEZAAIjAAcIzwwgKwByAQAjAAcIzwwgKwByAQAAAA==.Paustian:BAAALAADCggIFAAAAA==.',Pe='Peghead:BAAALAADCgYIBgAAAA==.Percival:BAAALAAECgEIAQAAAA==.Peridot:BAAALAAECggIDAAAAA==.',Ph='Phasanity:BAABLAAECoEoAAIWAAgIYCH7HgDSAgAWAAgIYCH7HgDSAgAAAA==.Phillidan:BAAALAAECgcICwAAAA==.',Pi='Piccolina:BAAALAADCggIBwABLAAECggIJwAcAAYcAA==.Pingu:BAAALAAFFAEIAQAAAA==.',Pr='Pretty:BAAALAADCggICAABLAAFFAYIGAATAHQXAA==.Priya:BAAALAADCggIBgAAAA==.',Ps='Psychotical:BAABLAAECoEaAAIkAAgI1B2TAgDYAgAkAAgI1B2TAgDYAgAAAA==.',['På']='Pågsson:BAACLAAFFIEHAAIJAAMIQxojEwAFAQAJAAMIQxojEwAFAQAsAAQKgR0AAgkACAhVJHccAN4CAAkACAhVJHccAN4CAAAA.Pålsson:BAAALAAECgYIBgAAAA==.',Qu='Quij:BAAALAADCggIKAAAAA==.Quirei:BAAALAAECgYICwAAAA==.',Ra='Rabíd:BAAALAAECggIEQAAAA==.Rafaelxes:BAABLAAECoEhAAMdAAgIjhHnHwDxAQAdAAgIjhHnHwDxAQAbAAEI2gk52wAyAAAAAA==.Rahl:BAAALAAECgQIBgAAAA==.Rainshammy:BAAALAADCggICAAAAA==.Raisy:BAAALAADCgcIBwAAAA==.Rashul:BAAALAAECgYIBwAAAA==.Rastacow:BAAALAAECgQICwABLAAFFAMIBwAXAJMeAA==.',Re='Redbol:BAAALAAECgMIAwAAAA==.Redear:BAABLAAECoEiAAIOAAgIvQ9wZACvAQAOAAgIvQ9wZACvAQAAAA==.Resus:BAAALAAECgEIAQAAAA==.Rethen:BAAALAADCggIDAAAAA==.',Rh='Rhysandt:BAAALAADCgQICQAAAA==.',Ri='Ritualofmoon:BAAALAAECgIIAgAAAA==.Ritualrogue:BAABLAAECoEbAAMSAAcI9hVcKQC+AQASAAYIYhZcKQC+AQARAAIIpAruOgBkAAAAAA==.',Ry='Ryii:BAAALAAECgYIDAAAAA==.',Sa='Saepheyr:BAAALAAECgcICQABLAAECgcIGgAcAP8VAA==.Saephrynex:BAAALAADCgYIBgABLAAECgcIGgAcAP8VAA==.Saephynea:BAAALAADCggICAABLAAECgcIGgAcAP8VAA==.Saephyra:BAAALAAECgYIDAABLAAECgcIGgAcAP8VAA==.Saephyrea:BAABLAAECoEaAAIcAAcI/xUwIADbAQAcAAcI/xUwIADbAQAAAA==.Saphoura:BAAALAAECgYIBgABLAAECggIDgAEAAAAAA==.Save:BAABLAAECoEXAAMeAAYI0xw9DACrAQAeAAYIsxc9DACrAQAgAAYI+BU2SQCHAQAAAA==.',Sc='Schierke:BAABLAAECoEdAAIbAAcIURPtVgDYAQAbAAcIURPtVgDYAQAAAA==.Scôr:BAABLAAECoEZAAINAAgI0hzgJQB1AgANAAgI0hzgJQB1AgAAAA==.',Se='Seamstress:BAAALAADCgIIAgAAAA==.Semora:BAAALAAECgcIEgAAAA==.Sendy:BAABLAAECoEdAAMFAAgIrA/VBwASAgAFAAgIrA/VBwASAgAOAAIICAM9BgE2AAAAAA==.',Sg='Sgtwolf:BAAALAADCggICAAAAA==.',Sh='Shachris:BAAALAAECgUIDgAAAA==.Shamatano:BAAALAAECgcIBwAAAA==.Shamfesh:BAAALAADCgQIBAAAAA==.Shandora:BAAALAAECgUICAABLAAECgYIBgAEAAAAAA==.Shivox:BAAALAAECgcICQAAAA==.Shortnsmitey:BAAALAADCgYIBgAAAA==.Shougon:BAAALAADCgMIAwAAAA==.',Si='Silverain:BAAALAAECgMIBQAAAA==.Sinrathus:BAABLAAECoEdAAMXAAcIBhnxJQAjAgAXAAcIBhnxJQAjAgAeAAEIog+kMQAwAAAAAA==.Sixteen:BAABLAAECoEZAAIlAAcI3g4EEQCfAQAlAAcI3g4EEQCfAQAAAA==.',Sk='Skinni:BAAALAAECgEIAQAAAA==.Skyseeker:BAAALAAFFAIIAgAAAA==.',Sm='Smallarms:BAAALAADCggIEAAAAA==.Smazdh:BAAALAAECgIIAgAAAA==.Smazz:BAAALAADCgYIBgAAAA==.',Sn='Sneakyman:BAABLAAECoEUAAMSAAYIPApDPQBIAQASAAYIPApDPQBIAQARAAQIZwI5OQByAAAAAA==.Snowcat:BAAALAADCggICAAAAA==.',So='Soffrok:BAAALAAECgYIEAAAAA==.Sopadepedra:BAAALAAECgcIBwAAAA==.',St='Starlaka:BAAALAADCggICAAAAA==.Starlie:BAAALAADCgcICgAAAA==.Steelfusion:BAAALAADCggICAAAAA==.Stezzil:BAAALAAECgYICAAAAA==.Stormbro:BAAALAADCgYICAAAAA==.Stormgrash:BAAALAADCggICgAAAA==.Stormtrooper:BAAALAAECgIIAgAAAA==.',Su='Succubeach:BAAALAAECgIIAgAAAA==.Sudosu:BAAALAADCgYICAAAAA==.Sunweaver:BAACLAAFFIEGAAIWAAIIdRmHHwCrAAAWAAIIdRmHHwCrAAAsAAQKgSMAAhYACAgzHhciAMMCABYACAgzHhciAMMCAAAA.Superspeed:BAAALAAECggIBwAAAA==.',Sy='Sylvestere:BAABLAAECoEVAAMYAAYIThdFMACHAQAYAAYIThdFMACHAQAlAAMIRAa/KgBjAAAAAA==.',['Sí']='Sírwinston:BAABLAAECoEZAAIWAAcIzB5bOQBgAgAWAAcIzB5bOQBgAgAAAA==.',Ta='Tag:BAAALAADCgQIBAABLAAECggIHAAmAPsjAA==.Tagnaros:BAAALAAECgYIDgAAAA==.Tangleroots:BAAALAADCggIDgAAAA==.',Te='Teagirl:BAAALAADCggICAAAAA==.Terrorrblade:BAABLAAECoEfAAIUAAgI5wZvqwA3AQAUAAgI5wZvqwA3AQAAAA==.Tesspiezzo:BAAALAADCggIFAAAAA==.',Th='Thornquist:BAAALAAECgYICwAAAA==.Thurin:BAAALAADCgYIBgAAAA==.',Ti='Tigerkink:BAAALAAECgYIEgAAAA==.Timbaeth:BAABLAAECoEZAAIBAAcIOCUsDADxAgABAAcIOCUsDADxAgAAAA==.Tixo:BAAALAADCggICAAAAA==.',To='Tobediah:BAAALAADCgUIBQAAAA==.Tobías:BAAALAAECgcIBAAAAA==.Toriko:BAAALAADCggICgAAAA==.Tortureall:BAAALAAECgYICQAAAA==.Toxícdótz:BAAALAADCggICAAAAA==.',Tr='Traight:BAABLAAECoEpAAIPAAgISxRZLwDpAQAPAAgISxRZLwDpAQAAAA==.Trephination:BAABLAAECoEhAAIZAAgIUwQ1bAAxAQAZAAgIUwQ1bAAxAQAAAA==.Trevorella:BAABLAAECoEcAAIHAAcIlAuHLQCXAQAHAAcIlAuHLQCXAQAAAA==.Trollmorph:BAAALAAECgcIEQAAAA==.Trombley:BAAALAAECgQIBwAAAA==.Trustyulf:BAAALAAECgcIEgAAAA==.',Tz='Tzeénthc:BAAALAAECgYIDAAAAA==.',Ud='Udurun:BAAALAADCggIDgAAAA==.',Un='Undjent:BAAALAAECgMIAwAAAA==.Unthuru:BAAALAADCgMIAwABLAADCggIFAAEAAAAAA==.',Ut='Uthredblack:BAAALAAECgYICQAAAA==.',Ve='Veey:BAAALAADCgUIBQAAAA==.Velcheria:BAAALAAECgYIDAAAAA==.Velen:BAAALAAECgMICgAAAA==.Velsæ:BAABLAAECoEhAAMDAAgIsiExDQDjAgADAAgIsiExDQDjAgAZAAEI7wJGtAAKAAAAAA==.Venandí:BAACLAAFFIEQAAIVAAYICCMkAABfAgAVAAYICCMkAABfAgAsAAQKgRwAAhUACAjcJsAAAHoDABUACAjcJsAAAHoDAAAA.Venmori:BAACLAAFFIEKAAIKAAYI+hsyAgDQAQAKAAYI+hsyAgDQAQAsAAQKgRUAAgoACAgVJCcCAFIDAAoACAgVJCcCAFIDAAEsAAUUBggQABUACCMA.Verracious:BAABLAAECoEUAAIBAAYI6QcRWQAMAQABAAYI6QcRWQAMAQAAAA==.Verrnarr:BAAALAAECgEIAQAAAA==.',Vi='Victoria:BAACLAAFFIEMAAIbAAYITRdOBQADAgAbAAYITRdOBQADAgAsAAQKgR0AAxsACAjPIwsVAPMCABsACAjPIwsVAPMCACcAAQg1C2odADcAAAAA.Viltrumite:BAAALAAECgQIBAAAAA==.Viora:BAABLAAECoEVAAIDAAYIExlMXQCYAQADAAYIExlMXQCYAQABLAADCggICAAEAAAAAA==.',Vo='Vogroth:BAAALAADCgcIDgAAAA==.Voidbro:BAAALAADCgcICgAAAA==.Voidragon:BAAALAADCgMIAwAAAA==.Voyl:BAAALAAECgMIAwAAAA==.',Vu='Vulkran:BAAALAADCgMIBAAAAA==.',We='Wehe:BAABLAAECoEdAAIcAAcIeRLfJgCtAQAcAAcIeRLfJgCtAQAAAA==.Wenz:BAAALAADCggICAABLAADCggICAAEAAAAAA==.',Wi='Wiccaa:BAAALAAECgUIBAAAAA==.Wildelife:BAAALAAECgQIBwAAAA==.Wilohmsford:BAAALAADCgMIBAAAAA==.Witherwing:BAAALAADCgUIBQAAAA==.',Wo='Wojak:BAAALAAECgYICQAAAA==.',Wr='Wraith:BAABLAAECoEWAAMGAAcIYBxaRQDuAQAGAAcI+xZaRQDuAQAIAAMIeyB8GgAKAQAAAA==.Wrayth:BAACLAAFFIEHAAIOAAMI7hDtEgDXAAAOAAMI7hDtEgDXAAAsAAQKgSQAAw4ACAgOHLs+ABoCAA4ACAgOHLs+ABoCAA8AAgidC/CfAEoAAAAA.',Wu='Wulfsine:BAAALAAECgMIAwAAAA==.Wurstwasser:BAAALAAECggIBwAAAA==.',['Wá']='Wárlôrd:BAABLAAECoEnAAINAAgITyFpFADqAgANAAgITyFpFADqAgAAAA==.',Xa='Xavios:BAABLAAECoEgAAIOAAgInReGOwAlAgAOAAgInReGOwAlAgAAAA==.Xavrius:BAAALAADCgUIBQAAAA==.',Xh='Xhali:BAAALAADCgcIBwAAAA==.Xhalia:BAAALAADCggIAgAAAA==.',Yi='Yinhen:BAABLAAECoEWAAIDAAcIYRb0TwC9AQADAAcIYRb0TwC9AQAAAA==.',Yo='Yolosswagg:BAAALAAFFAIIAgABLAAFFAMIBgAWAJ0SAA==.',Za='Zacre:BAAALAAECgIIAgAAAA==.Zahi:BAAALAADCgQIBAAAAA==.Zandramos:BAAALAADCggICAAAAA==.Zarakrond:BAAALAADCgUIAwAAAA==.Zaytan:BAABLAAECoEkAAIJAAgIfxnMOABoAgAJAAgIfxnMOABoAgAAAA==.',Zh='Zherai:BAAALAAECgEIAQAAAA==.Zhonraja:BAAALAAECgIIAgAAAA==.',Zi='Ziggo:BAAALAAECgcICwAAAA==.',Zr='Zrx:BAAALAADCggIEwAAAA==.',Zu='Zur:BAAALAAECggICAAAAA==.',['Ás']='Ásvaldr:BAABLAAECoEiAAIlAAgI4CKMAQA9AwAlAAgI4CKMAQA9AwAAAA==.',['Ðe']='Ðevlin:BAAALAAECgUICwABLAAECgcICQAEAAAAAA==.',['Ós']='Ósiris:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end