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
 local lookup = {'Warrior-Arms','Warrior-Fury','Unknown-Unknown','Priest-Holy','Priest-Shadow','Druid-Balance','Druid-Restoration','Monk-Mistweaver','Hunter-BeastMastery','Mage-Frost','Druid-Guardian','Paladin-Retribution','Monk-Windwalker','DemonHunter-Havoc','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Shaman-Restoration','Hunter-Marksmanship','Shaman-Elemental','Evoker-Devastation','DeathKnight-Frost','Warlock-Affliction','Rogue-Subtlety','Druid-Feral','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Protection','Paladin-Protection','Mage-Arcane','Evoker-Augmentation','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw',}; local provider = {region='EU',realm='Lothar',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abstergo:BAAALAAECgQIBAAAAA==.',Ad='Adamas:BAABLAAECoEYAAMBAAcI/iKBBgB+AgABAAYIUCSBBgB+AgACAAEIFBuaxQBRAAAAAA==.',Ak='Akeemi:BAAALAADCgYICgAAAA==.',Al='Alari:BAAALAAFFAUIDAAAAQ==.Alaribrew:BAAALAAECggIDwABLAAFFAUIDAADAAAAAQ==.Alarî:BAAALAAECgcIEwAAAA==.Alishiana:BAAALAADCggICAAAAA==.Alterfelîx:BAAALAADCgcIDQAAAA==.Alzreateria:BAABLAAECoEVAAMEAAcI9gGsfADYAAAEAAcI9gGsfADYAAAFAAcIBgMAAAAAAAAAAA==.',Am='Ameckitos:BAABLAAECoEbAAMGAAYIFAbdYQDvAAAGAAYIFAbdYQDvAAAHAAEI4QGYxAAdAAAAAA==.Ameria:BAAALAAECgYIDwAAAA==.Amilly:BAAALAADCggIDwAAAA==.Ammaranth:BAABLAAECoEiAAIHAAgIlwoFWgBIAQAHAAgIlwoFWgBIAQAAAA==.Amous:BAAALAAECgIIAgAAAA==.Amunét:BAABLAAECoEhAAIIAAcIlxcgHwCCAQAIAAcIlxcgHwCCAQAAAA==.',An='Andro:BAAALAAECgYIBgAAAA==.Anitta:BAAALAADCggICAAAAA==.Ansel:BAAALAADCggIFgAAAA==.',Aq='Aquena:BAABLAAECoEXAAIJAAYIqSDDUwDmAQAJAAYIqSDDUwDmAQABLAAFFAMIBwAKAAsMAA==.',Ar='Araelien:BAABLAAECoEjAAILAAgIuRoBBwBdAgALAAgIuRoBBwBdAgAAAA==.Arakas:BAAALAADCggIGgAAAA==.Arath:BAAALAADCgcIBwAAAA==.Archiimedees:BAAALAADCgIIBAAAAA==.Arono:BAAALAAECgYIEwAAAA==.Arýa:BAABLAAECoEYAAIMAAYIUxYQmwCHAQAMAAYIUxYQmwCHAQAAAA==.',As='Asarina:BAAALAAECgMIAwAAAA==.Ashdaleah:BAABLAAECoEdAAINAAgI8x1rCwDCAgANAAgI8x1rCwDCAgAAAA==.Ashînî:BAAALAAECgYIDAAAAA==.Asja:BAAALAADCgcICgAAAA==.Askari:BAABLAAECoEWAAIOAAYI8R4nTQAQAgAOAAYI8R4nTQAQAgAAAA==.Astora:BAAALAAECggIDQAAAA==.',Av='Avrelle:BAABLAAECoEgAAIJAAgIAwuGfACFAQAJAAgIAwuGfACFAQAAAA==.',Ay='Ayrah:BAAALAADCggIGgAAAA==.',Az='Azathoth:BAABLAAECoEYAAMPAAcI8QexPABYAQAPAAcIoAaxPABYAQAQAAIICQt+yABiAAAAAA==.Azuráh:BAAALAAECgEIAQAAAA==.',Ba='Baall:BAAALAADCgEIAQAAAA==.Ballrogg:BAAALAAECgMIBAAAAA==.Bankdude:BAAALAADCggICAAAAA==.Bankgirli:BAAALAADCggICAAAAA==.Barthalos:BAABLAAECoEVAAIMAAYI0x4RdwDLAQAMAAYI0x4RdwDLAQAAAA==.',Bi='Binski:BAAALAAECgcIBwABLAAECggICAADAAAAAA==.',Bl='Blutbodo:BAAALAAECgcICgAAAA==.',Bo='Boleron:BAACLAAFFIEHAAIRAAMILRc9BAAZAQARAAMILRc9BAAZAQAsAAQKgSkAAhEACAh/IpADACQDABEACAh/IpADACQDAAAA.Bossdudu:BAAALAADCgcIBwAAAA==.Bowbeforyogo:BAAALAAECgMIAwAAAA==.',Br='Brightlight:BAAALAAECgUIBQAAAA==.Brotus:BAAALAAECggIEAAAAA==.',['Bä']='Bärenliebe:BAAALAAECgYIDAAAAA==.',['Bê']='Bêâ:BAABLAAECoEYAAISAAcIZhpCPgD8AQASAAcIZhpCPgD8AQAAAA==.',['Bö']='Bömsch:BAAALAADCggICAABLAAECgYICgADAAAAAA==.',['Bù']='Bùnný:BAACLAAFFIEHAAIJAAMIOhNMFADcAAAJAAMIOhNMFADcAAAsAAQKgSkAAwkACAgvIVIhAKACAAkACAgvIVIhAKACABMAAQjrDvOqADgAAAAA.',Ca='Caimu:BAAALAADCggIHAAAAA==.Calder:BAAALAAECgYIBgABLAAECggIKwAOANUZAA==.Caldius:BAAALAADCgYIBgABLAAECggIKwAOANUZAA==.Caldán:BAABLAAECoErAAIOAAgI1RkvTQAQAgAOAAgI1RkvTQAQAgAAAA==.Caliya:BAAALAADCgYIBgAAAA==.Callmeshock:BAABLAAECoEdAAIUAAcIsxQSUQCZAQAUAAcIsxQSUQCZAQAAAA==.Calyx:BAAALAAECgcIEwAAAA==.Carela:BAABLAAECoEkAAIJAAgIMBBRaACyAQAJAAgIMBBRaACyAQAAAA==.Cassie:BAAALAAECggICAAAAA==.',Ce='Ceallach:BAABLAAECoEUAAIMAAcIbRSgggC1AQAMAAcIbRSgggC1AQABLAAECggIGgAVAIwWAA==.',Ch='Chalis:BAAALAAECgUIDAAAAA==.Cherti:BAABLAAECoEbAAIJAAcIwxTUgwB2AQAJAAcIwxTUgwB2AQAAAA==.Chifraig:BAAALAADCgYICQABLAAECgcIFgAWAHIjAA==.Chlorocresol:BAAALAAECgQIBAAAAA==.Chúnú:BAAALAADCgcIDQAAAA==.',Cl='Clia:BAAALAAECggICAAAAA==.',Co='Conell:BAACLAAFFIEKAAIWAAIIDB9oLQCoAAAWAAIIDB9oLQCoAAAsAAQKgTgAAhYACAhwIvwcAN4CABYACAhwIvwcAN4CAAAA.Coonie:BAAALAADCggIGgAAAA==.Corristo:BAAALAAECggICAAAAA==.Corristî:BAAALAAECggICAAAAA==.',Cr='Cranberry:BAAALAAECggICAAAAA==.Crasher:BAAALAAECggIEwAAAA==.',Cu='Curia:BAABLAAECoEVAAMFAAgI7hTDJQAsAgAFAAgI7hTDJQAsAgAEAAEI/QkmqAAqAAAAAA==.Cuêrly:BAAALAAECggICQAAAA==.',Cy='Cynthîanâ:BAAALAAECggICAAAAA==.',['Cá']='Cátinka:BAAALAADCgQIBgAAAA==.',Da='Daeva:BAAALAADCgQIBAAAAA==.Dahren:BAAALAAECggICQAAAA==.Danidragon:BAABLAAECoEUAAIXAAYIvhgrDQDDAQAXAAYIvhgrDQDDAQAAAA==.Dapî:BAABLAAECoEVAAIYAAgI4RiBEAALAgAYAAgI4RiBEAALAgAAAA==.Darkdeamon:BAAALAADCgQIBQAAAA==.Dashennes:BAACLAAFFIEHAAIZAAMIHx1XAwAoAQAZAAMIHx1XAwAoAQAsAAQKgSkAAhkACAiLJd0AAHADABkACAiLJd0AAHADAAAA.Dasjäger:BAAALAAECgYIBgABLAAFFAQICQANAKMMAA==.',De='Deathamb:BAAALAAECggICAAAAA==.Deathfraig:BAABLAAECoEWAAIWAAcIciOOKACqAgAWAAcIciOOKACqAgAAAA==.Deathknight:BAABLAAECoEkAAIWAAgIfhsmOgBoAgAWAAgIfhsmOgBoAgAAAA==.Deathpointer:BAAALAADCgEIAQABLAADCgMIAwADAAAAAA==.Deep:BAAALAAECggICAAAAA==.Denetrus:BAAALAADCggIEQAAAA==.',Dh='Dhahaha:BAAALAADCgUIBQAAAA==.Dhannanis:BAAALAADCgcIDAAAAA==.',Di='Didit:BAAALAADCgUIBQAAAA==.Dirury:BAAALAADCggIFQABLAAECgcIFgAWAHIjAA==.Discbraten:BAAALAAECgQICAAAAA==.',Dj='Djago:BAAALAAECgcIDwABLAAECggIBQADAAAAAA==.',Dm='Dmgdieter:BAABLAAECoEaAAIKAAgI9x3QFABWAgAKAAgI9x3QFABWAgAAAA==.',Do='Dokeni:BAABLAAECoEdAAMaAAcIhRoUGgC9AQAaAAYIsRoUGgC9AQAOAAcIIBYadACwAQAAAA==.Dondar:BAAALAAECgYIBgAAAA==.Dondavito:BAAALAADCgEIAQAAAA==.Donnella:BAAALAADCggIFQAAAA==.Dorone:BAAALAAECgYIEwAAAA==.',Dr='Dragana:BAAALAAECggIBQAAAA==.Dragongîrl:BAABLAAECoEgAAIMAAgI2hAOZgDuAQAMAAgI2hAOZgDuAQAAAA==.Drakthar:BAABLAAECoEUAAIMAAYIBg4lwwA/AQAMAAYIBg4lwwA/AQAAAA==.Dravco:BAAALAAECgIIAgAAAA==.Drudor:BAAALAAECgcICAAAAA==.Druïd:BAAALAAECggICAAAAA==.',Du='Dunamee:BAAALAADCgQIBgAAAA==.Duuri:BAAALAAECgEIAQAAAA==.',['Dä']='Dämo:BAAALAADCggIFAAAAA==.Dämofraig:BAAALAADCggIDgAAAA==.Dämoní:BAAALAADCgcIBwAAAA==.',Ea='Earthlight:BAACLAAFFIEKAAISAAUIARIGBwB4AQASAAUIARIGBwB4AQAsAAQKgSkAAhIACAjnH4IRAMgCABIACAjnH4IRAMgCAAAA.',Ed='Edánà:BAAALAADCgIIAgAAAA==.',Ei='Eiko:BAAALAADCggICAABLAAECggIJAAOAIwkAA==.Eiszwerg:BAAALAAECgYIDwAAAA==.',El='Elarew:BAAALAADCgYIBwAAAA==.Elburrìto:BAAALAAECgYIDQAAAA==.Elburrìtò:BAAALAAECgYIBwAAAA==.Elburrítò:BAAALAADCgMIAwAAAA==.Ellburrito:BAAALAADCgQIBAAAAA==.Elvaters:BAAALAADCggIGwAAAA==.Elèmént:BAABLAAECoEkAAIbAAgI5CCnAgAOAwAbAAgI5CCnAgAOAwAAAA==.',Em='Embrace:BAAALAAECgYIDQABLAAECggIRAAJAJMlAA==.Emorius:BAABLAAECoEdAAQPAAgIqyCADQCAAgAPAAcI8SCADQCAAgAQAAUIexWMgQBDAQAXAAEI0xKzOwA5AAAAAA==.Empress:BAAALAADCggICgAAAA==.',En='Engelbeard:BAAALAADCgYIDAAAAA==.Engelfli:BAAALAAECgUICwAAAA==.Engelfly:BAAALAADCgYIBgAAAA==.Enõy:BAAALAADCgcIEQAAAA==.',Es='Esrâ:BAAALAADCggICAAAAA==.Esçanor:BAABLAAECoEkAAIcAAgI9SNnBAA8AwAcAAgI9SNnBAA8AwAAAA==.',Eu='Eureka:BAAALAAECgYIBgAAAA==.',Ev='Evilsonic:BAAALAAECgMIBwAAAA==.',Ex='Exodiâ:BAAALAAECggICAAAAA==.',Fa='Factor:BAAALAAECggIEQAAAA==.Fatz:BAAALAAECgYIEQAAAA==.Faulius:BAAALAADCggICAAAAA==.Faulus:BAAALAAECgEIAQAAAA==.Faura:BAAALAADCggIGwAAAA==.',Fe='Feather:BAACLAAFFIEGAAIUAAIIUxn3GACkAAAUAAIIUxn3GACkAAAsAAQKgSkAAxQACAj0H4cVANACABQACAj0H4cVANACABIAAQgECRERASoAAAAA.Felidâe:BAABLAAECoEeAAMHAAcIyB6SHgBPAgAHAAcIyB6SHgBPAgAGAAEIHwkLjgA1AAAAAA==.Feloria:BAAALAADCggICAAAAA==.Feralfraig:BAAALAADCggIAwABLAAECgcIFgAWAHIjAA==.Feyiel:BAAALAADCgYIBgAAAA==.',Fl='Flauschebär:BAAALAAECgYIDAABLAAECgYIDwADAAAAAA==.Flavion:BAAALAADCgcIDAAAAA==.Fleshtearer:BAAALAADCggICAAAAA==.Flogge:BAAALAAECgEIAQAAAA==.Florenda:BAACLAAFFIEHAAIHAAMIjBFwDgDTAAAHAAMIjBFwDgDTAAAsAAQKgSkAAgcACAgDH2sRAK0CAAcACAgDH2sRAK0CAAAA.Flunkor:BAABLAAECoEgAAIHAAgIQB74FgCAAgAHAAgIQB74FgCAAgAAAA==.',Fo='Fong:BAABLAAECoEXAAINAAcIASMXDQCoAgANAAcIASMXDQCoAgAAAA==.Foox:BAAALAAECgEIAQAAAA==.',Fr='Fraigadin:BAAALAADCgYIBgABLAAECgcIFgAWAHIjAA==.Fraigx:BAAALAADCgYIBgABLAAECgcIFgAWAHIjAA==.Fraiig:BAAALAADCgYICgABLAAECgcIFgAWAHIjAA==.Frantzl:BAAALAAECgYIBgAAAA==.Freakbyme:BAAALAAECggIDAAAAA==.Frêêzer:BAAALAAECgMIBgAAAA==.',Ga='Gabbertje:BAABLAAECoEUAAIOAAcIfwZh3wDBAAAOAAcIfwZh3wDBAAAAAA==.Galdrim:BAAALAADCggICAABLAAECgcIGAAZAGggAA==.Galáxius:BAAALAAECggICAAAAA==.Gamblex:BAABLAAECoEYAAICAAgISxDeYgCRAQACAAgISxDeYgCRAQAAAA==.Gania:BAAALAADCggIHgABLAAECgYIFQAMAP4VAA==.Garthyrail:BAAALAADCggIIAAAAA==.',Ge='Genjar:BAAALAAECgQIBgAAAA==.Genshi:BAAALAAECgIIAwAAAA==.Gestrenge:BAAALAAECgYIEQAAAA==.',Gh='Ghuly:BAAALAAECgcIEQAAAA==.',Gl='Glimmrock:BAAALAADCgcIDQAAAA==.',Go='Gojira:BAABLAAECoEYAAMCAAgIRwOUowDFAAACAAgIKQOUowDFAAAcAAMItAHaeQAwAAAAAA==.Goodnìght:BAAALAAECgYIEQABLAAFFAMIBwAKAAsMAA==.',Gr='Grimbart:BAAALAAECgMIBQAAAA==.',Gu='Guldanramsey:BAAALAADCgcICgAAAA==.Gungnir:BAAALAADCgEIAQAAAA==.',Gw='Gweny:BAAALAAECggICAAAAA==.',['Gá']='Gándógáhr:BAAALAAECgIIAgAAAA==.',['Gâ']='Gârwain:BAAALAADCgcIIgAAAA==.',Ha='Hackepeter:BAAALAADCgMIAwAAAA==.Hakula:BAABLAAECoEVAAIMAAYI/hVfqQBuAQAMAAYI/hVfqQBuAQAAAA==.Hanabi:BAABLAAECoEXAAINAAgIyhNDHADxAQANAAgIyhNDHADxAQAAAA==.Hanka:BAAALAADCggICAAAAA==.Hardmood:BAAALAADCgcIBwAAAA==.Haudazû:BAAALAADCggIEAAAAA==.Hauzu:BAAALAAECgIIAwAAAA==.Hawke:BAAALAAECgYIEwAAAA==.',He='Healdeeguard:BAAALAAECgYIBwAAAA==.Hedkrakka:BAAALAADCgIIAgAAAA==.Heidí:BAABLAAECoEVAAIMAAgIExqIbgDdAQAMAAgIExqIbgDdAQAAAA==.Heiligsmadl:BAABLAAECoEuAAIdAAgIGAmuMwAxAQAdAAgIGAmuMwAxAQAAAA==.Heróicorá:BAAALAAECgQIBAAAAA==.Heuljamit:BAAALAADCggIDQAAAA==.Heulnichrum:BAAALAAECggICQAAAA==.Hexfila:BAABLAAECoEdAAIQAAgIlAmxYACbAQAQAAgIlAmxYACbAQAAAA==.',Ho='Hogar:BAAALAAECgEIAQAAAA==.Holyhelga:BAAALAADCgQIBAAAAA==.Honnee:BAABLAAECoEYAAIJAAgIpwqbhQByAQAJAAgIpwqbhQByAQAAAA==.Hordo:BAAALAAECgMIBgAAAA==.',['Hî']='Hîty:BAAALAADCggIFQAAAA==.',['Hö']='Hörtauchzu:BAAALAADCgcIBwAAAA==.Hörtniezu:BAAALAADCggIDwAAAA==.',Ic='Icéangel:BAAALAAECgEIAQAAAA==.',Ig='Igris:BAAALAAECgIIAgAAAA==.',In='Inextremi:BAABLAAECoEeAAISAAgIVxtnKgBGAgASAAgIVxtnKgBGAgAAAA==.Inki:BAABLAAECoEcAAIeAAcIpho4RwASAgAeAAcIpho4RwASAgAAAA==.Inraelis:BAAALAAECgYIBAABLAAECggIJAAcAPUjAA==.Insomniac:BAAALAAECgEIAQAAAA==.Inu:BAABLAAECoEkAAQQAAgIcxaZNwAuAgAQAAgIDhaZNwAuAgAPAAQIYhgJUQAEAQAXAAEIxgJVQgAYAAAAAA==.',Is='Isnaa:BAAALAAECgYIDQAAAA==.',It='Ithlínne:BAAALAADCgcIIgAAAA==.',Ix='Ixis:BAAALAAECgIIAgAAAA==.',Ja='Jaheuldoch:BAAALAAECgEIAQAAAA==.Janedoo:BAAALAADCgcICAAAAA==.Jaîme:BAAALAAECgIIAgAAAA==.',Je='Jeverman:BAABLAAECoEcAAIJAAcIfxPwbwCgAQAJAAcIfxPwbwCgAQAAAA==.',Ji='Jicky:BAABLAAECoEVAAIeAAcIJgpQegB7AQAeAAcIJgpQegB7AQAAAA==.Jinjá:BAAALAADCgEIAQAAAA==.',Jo='Joergimausi:BAAALAAECgIIAgAAAA==.',Ju='Jujube:BAABLAAECoEZAAIfAAcI2BQsCADMAQAfAAcI2BQsCADMAQAAAA==.Juscharo:BAAALAADCggICAAAAA==.',['Jê']='Jêga:BAAALAAECgYICgAAAA==.',Ka='Kaffeebohne:BAAALAAECgIIAgAAAA==.Kalathor:BAABLAAECoEYAAITAAcISx2yIABLAgATAAcISx2yIABLAgAAAA==.Kalîna:BAAALAAECgYIDwAAAA==.Kandâtsu:BAAALAADCgcIBwAAAA==.Kanü:BAAALAADCgcIDQAAAA==.Karilux:BAABLAAECoEbAAIcAAYIvhlMMACQAQAcAAYIvhlMMACQAQAAAA==.Kavax:BAABLAAECoEYAAISAAgI4xh3MQApAgASAAgI4xh3MQApAgAAAA==.',Ke='Kedi:BAAALAAECgYIDAAAAA==.Kelea:BAAALAAECggIEAABLAAECggIBgADAAAAAA==.Kentauro:BAAALAADCggIEgABLAAECggIJgAHACclAA==.',Kh='Khrimm:BAAALAAECgMICgAAAA==.Khuno:BAABLAAECoEZAAIgAAgIGR9SCADOAgAgAAgIGR9SCADOAgAAAA==.',Ki='Killertomate:BAABLAAECoEdAAISAAcIAQbmswDcAAASAAcIAQbmswDcAAAAAA==.Kiniti:BAABLAAECoEUAAIXAAYIkgzYFABSAQAXAAYIkgzYFABSAQAAAA==.Kirkkomaa:BAAALAADCgQIBQAAAA==.Kiyona:BAAALAADCggICAAAAA==.',Kl='Klorelia:BAAALAADCgcIBwAAAA==.',Kn='Knochenknut:BAABLAAECoEVAAIWAAgIPQ/4rgBwAQAWAAgIPQ/4rgBwAQAAAA==.',Ko='Koinheal:BAAALAADCgcIDAAAAA==.Komatös:BAAALAAECgUIBwAAAA==.Koraki:BAABLAAECoEiAAIKAAcI9xLfMgCHAQAKAAcI9xLfMgCHAQAAAA==.Koyeto:BAAALAAECgMIBAAAAA==.',Ku='Kuiil:BAAALAADCggIGAAAAA==.',Ky='Kyvanú:BAABLAAECoEpAAIGAAgIoB3hFACZAgAGAAgIoB3hFACZAgAAAA==.Kyvanúscham:BAABLAAECoEWAAIUAAgIOxvHHACZAgAUAAgIOxvHHACZAgAAAA==.',['Ké']='Kéhleyr:BAABLAAECoEUAAIaAAYI0xdcHgCOAQAaAAYI0xdcHgCOAQAAAA==.',La='Lacigale:BAAALAAECgMIAwAAAA==.Larentía:BAAALAADCggICAAAAA==.Lariza:BAAALAADCggICAAAAA==.Laylia:BAACLAAFFIEFAAIGAAMImRmgCgDwAAAGAAMImRmgCgDwAAAsAAQKgSEAAgYACAinJHcIACADAAYACAinJHcIACADAAAA.',Le='Leighla:BAAALAADCgIIAgAAAA==.Letiifer:BAAALAADCgEIAQAAAA==.Leyylaani:BAAALAADCggICAAAAA==.',Li='Lichbraten:BAAALAADCgUIBQABLAAECgQICAADAAAAAA==.Lilja:BAABLAAECoEXAAIMAAgIegXj0gAiAQAMAAgIegXj0gAiAQAAAA==.Lill:BAAALAADCggIEAAAAA==.Lillet:BAAALAAECgYIEgAAAA==.Linaraa:BAAALAADCggICAABLAAECggIIwALALkaAA==.Lionila:BAAALAAECgYIBgABLAAECgcICAADAAAAAA==.Lizzard:BAAALAADCgUIBQAAAA==.',Lo='Logarésh:BAABLAAECoEWAAIOAAYIrhQ0jgB8AQAOAAYIrhQ0jgB8AQAAAA==.Lolika:BAACLAAFFIEGAAIbAAMIagw6AwDQAAAbAAMIagw6AwDQAAAsAAQKgSMAAhsACAhZH2gEANACABsACAhZH2gEANACAAAA.Lonik:BAAALAADCgMIAwABLAAECgYIHAAbANsfAA==.Lorena:BAAALAAECgUIBgAAAA==.Lorgar:BAAALAADCggICAAAAA==.Lorim:BAABLAAECoEcAAIbAAYI2x/uCwANAgAbAAYI2x/uCwANAgAAAA==.Lorina:BAABLAAECoEaAAIOAAgI3hdPRgAlAgAOAAgI3hdPRgAlAgAAAA==.Lorissa:BAABLAAECoEaAAIQAAYIdwepmQD/AAAQAAYIdwepmQD/AAAAAA==.',Lu='Lubert:BAAALAADCgMIAwAAAA==.Ludo:BAABLAAECoEbAAIUAAYIrg7sYQBhAQAUAAYIrg7sYQBhAQAAAA==.Lullátsch:BAAALAAECgEIAQAAAA==.Lumbartus:BAAALAADCggIIAAAAA==.Lumihoothoot:BAACLAAFFIEOAAIGAAUIthd4BAC9AQAGAAUIthd4BAC9AQAsAAQKgSUAAgYACAiYJBkLAAIDAAYACAiYJBkLAAIDAAAA.Lumî:BAAALAAECgYIDQABLAAFFAUIDgAGALYXAA==.Lumîxy:BAAALAAECgYICwABLAAFFAUIDgAGALYXAA==.',Ly='Lycàner:BAAALAAECgMIAwAAAA==.Lynelle:BAAALAADCggIEAAAAA==.Lynvala:BAABLAAECoEbAAIOAAcI8R5jOQBRAgAOAAcI8R5jOQBRAgAAAA==.Lyxe:BAAALAAECgIIAQAAAA==.',['Lí']='Lílanara:BAAALAAECgQICgAAAA==.Líllîth:BAABLAAECoEcAAIOAAgIdB1kIwCzAgAOAAgIdB1kIwCzAgAAAA==.',Ma='Maajala:BAAALAADCgYIBwAAAA==.Macgoon:BAAALAAECgUIDgAAAA==.Machunt:BAABLAAECoEYAAIhAAYIVBn0CQDoAQAhAAYIVBn0CQDoAQAAAA==.Madinez:BAAALAAECgIIAgAAAA==.Malih:BAABLAAECoEkAAIJAAgILxoGPAAvAgAJAAgILxoGPAAvAgAAAA==.Mandarîne:BAABLAAECoEWAAIHAAYI1Bb8RwCIAQAHAAYI1Bb8RwCIAQAAAA==.Mariel:BAABLAAECoEkAAIEAAgI0wNyYgAvAQAEAAgI0wNyYgAvAQAAAA==.Marlen:BAABLAAECoEXAAIeAAcIZyBdLACBAgAeAAcIZyBdLACBAgAAAA==.Martego:BAAALAAECgUIAwAAAA==.Mashiro:BAABLAAECoEhAAIJAAgISx9iGwDBAgAJAAgISx9iGwDBAgAAAA==.Matayus:BAAALAAECgYIBAAAAA==.Maxim:BAAALAAECgMIBwAAAA==.',Me='Mechabumm:BAAALAAECggICAABLAAECggIJAABAFAcAA==.Melaisa:BAABLAAECoEdAAIPAAcIow0BKgCsAQAPAAcIow0BKgCsAQAAAA==.Meranda:BAABLAAECoEkAAIeAAgI8hVTTgD6AQAeAAgI8hVTTgD6AQAAAA==.Meshock:BAAALAAECgUIDgAAAA==.',Mh='Mhez:BAAALAAECgYIBgAAAA==.',Mi='Midera:BAAALAAECgcIDwAAAA==.Migina:BAAALAADCgMIAwAAAA==.Milthred:BAABLAAECoEUAAIFAAYI1xxXMwDbAQAFAAYI1xxXMwDbAQAAAA==.Minona:BAABLAAECoEdAAISAAgIkx/LFgCmAgASAAgIkx/LFgCmAgAAAA==.Minotorro:BAAALAADCgYIBgAAAA==.Minulock:BAAALAAECgYIBwAAAA==.Mizukí:BAABLAAECoEbAAIJAAcICBsLUADwAQAJAAcICBsLUADwAQAAAA==.',Mo='Mondbâr:BAAALAAECggIEgAAAA==.Monkchéri:BAAALAAECgQIBAAAAA==.Montie:BAAALAAECggIBQAAAA==.Moonday:BAABLAAECoEWAAIHAAcIwxoZKgAPAgAHAAcIwxoZKgAPAgAAAA==.Moone:BAAALAAECggIDgAAAA==.Moonozond:BAABLAAECoEaAAIVAAgIjBZDGgA1AgAVAAgIjBZDGgA1AgAAAA==.Mor:BAAALAADCgcIBwAAAA==.',Mu='Muhladín:BAABLAAECoEYAAIMAAYIgRn0fgC7AQAMAAYIgRn0fgC7AQAAAA==.Muhyagi:BAAALAADCgYICQAAAA==.Muldar:BAAALAAECgYICAABLAAFFAIIAgADAAAAAA==.',My='Mythica:BAAALAADCggICAAAAA==.',['Má']='Mávis:BAABLAAECoEVAAIGAAYIeBNUSQBaAQAGAAYIeBNUSQBaAQAAAA==.',['Mä']='Mäggie:BAAALAAECgYIDQAAAA==.',['Mê']='Mêgo:BAACLAAFFIEIAAIiAAMI4hNnCADZAAAiAAMI4hNnCADZAAAsAAQKgSkAAiIACAgwITAHAN4CACIACAgwITAHAN4CAAAA.',Na='Nackensteak:BAAALAAECgEIAgABLAAECgIIAQADAAAAAA==.Nadea:BAACLAAFFIEHAAIKAAMICww0BwC0AAAKAAMICww0BwC0AAAsAAQKgSMAAgoACAjRJLADAEoDAAoACAjRJLADAEoDAAAA.Nahiko:BAABLAAECoEjAAIFAAgIXRxZFgCkAgAFAAgIXRxZFgCkAgAAAA==.Nalie:BAABLAAECoEYAAIjAAcI5B3gBABeAgAjAAcI5B3gBABeAgAAAA==.Namaste:BAACLAAFFIEHAAISAAIIRx0SHgCrAAASAAIIRx0SHgCrAAAsAAQKgSUAAhIACAhuHtsUALICABIACAhuHtsUALICAAAA.Namiel:BAAALAAECgIIAgAAAA==.Naves:BAABLAAECoEUAAISAAYIaRYAgQBFAQASAAYIaRYAgQBFAQAAAA==.Naxxi:BAAALAAECggIEAAAAA==.',Ne='Nebelmond:BAAALAADCgEIAQAAAA==.Nementhiel:BAABLAAECoEYAAICAAcI4SAjIQCbAgACAAcI4SAjIQCbAgAAAA==.Nemyt:BAAALAADCggICAABLAAECggIEAADAAAAAA==.Nerakson:BAAALAADCgcIBwABLAAECgMIBAADAAAAAA==.Neramis:BAAALAADCgUIBQAAAA==.Nevgond:BAABLAAECoEYAAIZAAcIaCBlCgCIAgAZAAcIaCBlCgCIAgAAAA==.Nexyrîa:BAAALAAECgYIEAABLAAECggIJAAGANYQAA==.Neî:BAAALAAECgYIDQAAAA==.Neô:BAAALAAECgYIEgAAAA==.',Ni='Nibelien:BAABLAAECoEaAAIMAAYIZhLJpwBxAQAMAAYIZhLJpwBxAQAAAA==.Nique:BAAALAAECgEIAgAAAA==.Niuo:BAAALAAECgQIBgAAAA==.',Nk='Nks:BAAALAAECgEIAQAAAA==.',No='Nobi:BAAALAAECgcIDgAAAA==.Noshama:BAAALAAECgYIEAAAAA==.Nouri:BAAALAADCggICAAAAA==.',Ny='Nyphera:BAAALAADCggIDwAAAA==.',['Né']='Néragodx:BAAALAADCgcIDwABLAAECggINAACAG8dAA==.Nérasan:BAABLAAECoE0AAMCAAgIbx2BKgBjAgACAAgIBByBKgBjAgAcAAcI8xuVJADbAQAAAA==.',['Nì']='Nìghtmare:BAAALAADCgYICgAAAA==.',Od='Odaiba:BAAALAAECgQIBAAAAA==.Odryn:BAABLAAECoEWAAICAAgIdhJ9PQANAgACAAgIdhJ9PQANAgABLAAECggIGAASAOMYAA==.',Og='Ogórek:BAABLAAECoEsAAIHAAgIABhJIQA+AgAHAAgIABhJIQA+AgAAAA==.',Op='Optìmus:BAAALAAECgMIBQAAAA==.',Or='Orccro:BAAALAADCgYIBgAAAA==.Orcmon:BAABLAAECoEnAAISAAgIbQzHfgBLAQASAAgIbQzHfgBLAQAAAA==.Orthar:BAABLAAECoEjAAMRAAgIJR1PCgCbAgARAAgIJR1PCgCbAgAWAAMIKwkQHgGRAAAAAA==.',Os='Ossipuma:BAABLAAECoEYAAMkAAcIZggcOwBaAQAkAAcILAgcOwBaAQAYAAMIlQYfOwBuAAAAAA==.',Ou='Ouragan:BAAALAADCggIFAAAAA==.',Pa='Pakei:BAAALAADCgcICgAAAA==.Palamon:BAABLAAECoEmAAIMAAcI4xRsjQChAQAMAAcI4xRsjQChAQABLAAECggIJwASAG0MAA==.Pandomax:BAACLAAFFIEIAAIEAAMIOiJ8CgAxAQAEAAMIOiJ8CgAxAQAsAAQKgSkAAwQACAgcI4wMAPECAAQACAgcI4wMAPECAAUABAgkFfhfAAYBAAAA.Parmesan:BAAALAAECgIIAgABLAAECgYIHAAbANsfAA==.Patill:BAAALAAECgEIAQAAAA==.',Pe='Penkingx:BAAALAADCgYIBgAAAA==.',Pf='Pfafnir:BAAALAADCgcIBwABLAAECgYIDAADAAAAAA==.',Ph='Phillepalle:BAAALAADCgEIAQABLAAECgIIAgADAAAAAA==.Phærôn:BAAALAADCgcIBwAAAA==.',Pi='Piinyin:BAAALAADCgIIAgAAAA==.',Pl='Plazdrood:BAAALAAECggIDgAAAA==.Plexx:BAAALAADCgEIAQAAAA==.',Pu='Pumagirl:BAAALAADCgIIAgAAAA==.Pumeluff:BAAALAADCgMIAwAAAA==.',Qu='Quixos:BAAALAADCggICAAAAA==.',Ra='Racyareth:BAAALAAECgYIDQAAAA==.Rai:BAAALAAECgYIBgABLAAECggIGgAVAIwWAA==.Ralin:BAAALAAECgMIBQAAAA==.Rambotan:BAAALAAECgYIBgAAAA==.Raspbêrry:BAAALAADCggIEAAAAA==.Ravius:BAABLAAECoEoAAIVAAgIKh0VGgA2AgAVAAgIKh0VGgA2AgAAAA==.Rayzz:BAAALAADCgEIAQABLAAECggIJwAiAMUYAA==.',Re='Reachfight:BAACLAAFFIEIAAIOAAIIQx9XIgCkAAAOAAIIQx9XIgCkAAAsAAQKgSMAAg4ACAgqIaAVAP8CAA4ACAgqIaAVAP8CAAAA.Reanko:BAAALAADCgYIBwAAAA==.Reinholz:BAABLAAECoEkAAIGAAgI1hDSMADOAQAGAAgI1hDSMADOAQAAAA==.Reiyuki:BAAALAADCgYIBgAAAA==.Returned:BAAALAAECgcIDQAAAA==.Rewonina:BAAALAAECgUICgAAAA==.',Rh='Rhoc:BAAALAADCgcIDgAAAA==.',Ri='Riac:BAAALAAFFAIIBAAAAQ==.',Ro='Rotor:BAAALAADCgcIBwAAAA==.',Ru='Rubley:BAABLAAECoEXAAIlAAcIKhwDBgA3AgAlAAcIKhwDBgA3AgAAAA==.',Ry='Ryuu:BAAALAAECgMIAwAAAA==.',['Rú']='Rúbydacherry:BAAALAADCgEIAQAAAA==.',Sa='Saafira:BAAALAADCggIGgAAAA==.Safila:BAAALAAECgMIAwABLAAECggIHQAQAJQJAA==.Saiga:BAAALAADCggICAAAAA==.Salarya:BAAALAAECgcICwAAAA==.Samilius:BAAALAADCggICAAAAA==.Sanara:BAAALAAECgQIBwAAAA==.Sanoxy:BAAALAAECgYIDQAAAA==.Santolina:BAAALAADCgIIAgAAAA==.Saphye:BAAALAAECgYICgAAAA==.Satellite:BAAALAAECgMIAwAAAA==.Sathria:BAABLAAECoEnAAMMAAgIsiSmEwATAwAMAAgIsiSmEwATAwAgAAUISQljSwDkAAAAAA==.',Sc='Schamani:BAAALAADCggIGAAAAA==.Schamasch:BAAALAADCggIHAAAAA==.Schischong:BAABLAAECoEnAAIiAAgIxRhxEwD8AQAiAAgIxRhxEwD8AQAAAA==.Schmooving:BAAALAADCggIDQAAAA==.',Se='Semidea:BAAALAAECgYICAAAAA==.Semperito:BAAALAADCggIEQAAAA==.Senshoux:BAACLAAFFIEHAAMgAAMIxRE2CgDoAAAgAAMIxRE2CgDoAAAMAAEIoh0iRABVAAAsAAQKgSkAAwwACAh8IB4mALQCAAwABwixIx4mALQCACAACAi/GrkUAEECAAAA.Sephi:BAAALAAECgUIDQAAAA==.Series:BAAALAADCgcIBwAAAA==.Sethra:BAACLAAFFIEFAAIJAAIIYxE8LACPAAAJAAIIYxE8LACPAAAsAAQKgSgAAgkACAi0H0snAIECAAkACAi0H0snAIECAAAA.Sevîka:BAAALAADCggICAAAAA==.',Sh='Shael:BAAALAADCgIIAgAAAA==.Shalluna:BAAALAAECgcIDwAAAA==.Shallunâ:BAAALAAECgEIAQABLAAECgcIDwADAAAAAA==.Sharia:BAAALAADCgcIDAAAAA==.Shawtiex:BAAALAAECgIIAgAAAA==.Shikka:BAABLAAECoEfAAICAAcICB2vPAAQAgACAAcICB2vPAAQAgAAAA==.Shinlu:BAAALAADCggIDgABLAAFFAIIBgABAMkbAA==.Shinoriah:BAABLAAECoEkAAIYAAgITiNVAwAcAwAYAAgITiNVAwAcAwAAAA==.Shiresse:BAABLAAECoEYAAIMAAYI6AyGwgBBAQAMAAYI6AyGwgBBAQAAAA==.Shivaluna:BAAALAAECgcIEAAAAA==.Shivo:BAAALAADCgcIBwAAAA==.Shodashi:BAAALAAECgYIEQAAAA==.Shokz:BAAALAADCggIDgAAAA==.Shokzn:BAAALAAECgcIDAAAAA==.Shoqqz:BAAALAADCgQIBAAAAA==.Shoyo:BAAALAAECgYIEQAAAA==.Shysan:BAACLAAFFIEGAAITAAMIPxhxDADnAAATAAMIPxhxDADnAAAsAAQKgSkAAhMACAgiJT4EAEgDABMACAgiJT4EAEgDAAAA.',Si='Sideways:BAAALAADCggICAABLAAECgYIDAADAAAAAA==.Sindira:BAAALAAECgYIDQAAAA==.Sirlancelot:BAAALAAECggICAAAAA==.',Sl='Slev:BAAALAADCggIEAAAAA==.Slevìn:BAAALAADCgMIAwAAAA==.',So='Sorraja:BAAALAADCggIDwAAAA==.',Sp='Spef:BAAALAADCgYIBwAAAA==.Spleen:BAABLAAECoEYAAIKAAgIAA5INQB6AQAKAAgIAA5INQB6AQAAAA==.Spookynooky:BAAALAADCgYIBgAAAA==.',St='Stormhalt:BAAALAAECgIIAgABLAAECggIIQARAFsiAA==.',Su='Suladria:BAAALAAECgIIBAAAAA==.Sulfuria:BAAALAADCggIDQAAAA==.Supergai:BAAALAADCgcIBwAAAA==.Superschami:BAAALAAECgIIAgAAAA==.Suè:BAAALAADCggICAAAAA==.',Sy='Sylivrien:BAAALAAECggIIQAAAQ==.',Ta='Tabbe:BAAALAAECggICAAAAA==.Tamro:BAAALAAECgUIBwAAAA==.Tandoki:BAACLAAFFIENAAQkAAUI0h1HBwAdAQAkAAMIjRlHBwAdAQAYAAIIEh/8CAC+AAAlAAEIGQ1iBQBPAAAsAAQKgRcABCUACAjDG5wHAAICACQACAgTFU8eAA8CACUABwhbGJwHAAICABgABAhCGwclADwBAAAA.Tarmo:BAAALAADCgQIBAAAAA==.Taurjan:BAAALAADCgUIBQAAAA==.',Te='Teahupoo:BAAALAAECgMIAwAAAA==.Teldrag:BAAALAAECgEIAQAAAA==.Tellassa:BAAALAADCgUICgAAAA==.Tevv:BAAALAADCggICAAAAA==.Texa:BAAALAAECgQIDAAAAA==.',Th='Thalar:BAAALAAECgYIEQAAAA==.Tharisan:BAAALAADCgUIBQAAAA==.Theros:BAABLAAECoEkAAIeAAgIcRlBMABuAgAeAAgIcRlBMABuAgAAAA==.Thundergrave:BAAALAAECgIIAgAAAA==.',Ti='Timberly:BAAALAADCggIHwAAAA==.Timii:BAAALAAECgcIEwAAAA==.Tiseis:BAABLAAECoEVAAIPAAcI+BJEJADKAQAPAAcI+BJEJADKAQAAAA==.',To='Toastii:BAAALAAECgYIEAAAAA==.Togerass:BAAALAADCggIBwAAAA==.Tohsaka:BAACLAAFFIEGAAIBAAIIyRszAgCzAAABAAIIyRszAgCzAAAsAAQKgSkAAgEACAi/I2EBAEYDAAEACAi/I2EBAEYDAAAA.Tooruu:BAAALAAECgYIBgAAAA==.Topher:BAABLAAECoEnAAMSAAgIvBPkTwDFAQASAAgIvBPkTwDFAQAUAAQIfSFYkQCWAAAAAA==.Torkal:BAABLAAECoEkAAQBAAgIUBx/BgB/AgABAAgIJBp/BgB/AgACAAgI1BqSKgBjAgAcAAEIOw40egAvAAAAAA==.',Tr='Trommelfell:BAAALAADCggICAABLAAECgcIFQAVAA4RAA==.Trueleader:BAABLAAECoEmAAMEAAgIIh6SFwCVAgAEAAgIIh6SFwCVAgAFAAUIJhX9TwBRAQAAAA==.',Ts='Tsa:BAAALAAECgYICQAAAA==.',Tt='Tton:BAAALAAECgEIAQAAAA==.',Ud='Udim:BAABLAAECoEVAAIQAAYIHwu+gwA9AQAQAAYIHwu+gwA9AQAAAA==.',Uk='Ukuwa:BAABLAAECoEiAAITAAgIPBvAGQCBAgATAAgIPBvAGQCBAgAAAA==.',Ul='Ulther:BAAALAAECgUIDgAAAA==.',Un='Unholyfraig:BAAALAADCggICgABLAAECgcIFgAWAHIjAA==.Unkown:BAAALAAECgYICwAAAA==.',Us='Usaca:BAABLAAECoEXAAIiAAcIESGwCQChAgAiAAcIESGwCQChAgAAAA==.',Ut='Uthassa:BAAALAADCggICAAAAA==.',Ux='Uxmal:BAAALAAECgYIBAAAAA==.',Va='Valerina:BAAALAAECgUICAAAAA==.Valnessa:BAAALAAECgUIDAAAAA==.Valraven:BAABLAAECoEmAAIHAAgIJyUpAwBIAwAHAAgIJyUpAwBIAwAAAA==.Valstadt:BAAALAADCggIEAABLAAECggIJAABAFAcAA==.Varelldk:BAAALAAFFAIIBAAAAA==.Vayah:BAAALAAECggIBgAAAA==.',Ve='Vela:BAABLAAECoEVAAIWAAYI2BW0oQCGAQAWAAYI2BW0oQCGAQAAAA==.Velencia:BAAALAAECgEIAgAAAA==.Velmoras:BAAALAADCgEIAQAAAA==.Versacé:BAAALAADCggICAAAAA==.',Vi='Violith:BAAALAAECggICAAAAA==.Viridatrux:BAABLAAECoEVAAIVAAcIDhFWKwCjAQAVAAcIDhFWKwCjAQAAAA==.Vivy:BAAALAAECgYICQABLAAECgYIDAADAAAAAA==.Vix:BAAALAADCggICAAAAA==.',Vo='Voldan:BAAALAAFFAEIAQAAAA==.',Vu='Vulshok:BAAALAAECgMIBwAAAA==.',Wa='Warfraig:BAAALAADCgYIBgABLAAECgcIFgAWAHIjAA==.Warixus:BAAALAADCgcIEAAAAA==.',We='Wetherby:BAAALAADCggICAAAAA==.',Wh='Whâtson:BAAALAAECggICAAAAA==.',Wi='Wilburga:BAAALAADCgcICgAAAA==.Wildblood:BAAALAAECggICAAAAA==.Winki:BAAALAAECgYICwABLAAECgcIHAAeAKYaAA==.',Wo='Wolfsfang:BAAALAAECgcIBwAAAA==.',Xa='Xali:BAAALAAECgcICAABLAAECggIEAADAAAAAA==.Xande:BAAALAADCgcICwAAAA==.Xaroth:BAAALAADCgUIBQAAAA==.',Xc='Xcallica:BAAALAAECggIEwAAAA==.',Xe='Xerina:BAABLAAECoEXAAIPAAgIKhsYDACQAgAPAAgIKhsYDACQAgAAAA==.',Xy='Xyth:BAAALAAECgYIEAAAAA==.',Ya='Yaleira:BAABLAAECoEnAAIQAAgIWBuOLgBaAgAQAAgIWBuOLgBaAgAAAA==.',Ye='Yedia:BAABLAAECoEgAAIUAAcIpA7bTwCdAQAUAAcIpA7bTwCdAQAAAA==.',Yo='Yonsho:BAAALAAECgMIAwAAAA==.',Yu='Yuelin:BAAALAAECgYIEQAAAA==.',Za='Zalah:BAAALAADCggICAAAAA==.Zamber:BAACLAAFFIEIAAICAAMIUh+8CwA4AQACAAMIUh+8CwA4AQAsAAQKgSkAAgIACAg9JuICAHcDAAIACAg9JuICAHcDAAAA.Zarubi:BAAALAAECgMIBgAAAA==.Zat:BAAALAAECggIIgAAAQ==.',Ze='Zeedan:BAAALAAECgYIEgAAAA==.Zehn:BAAALAAECgMIBwAAAA==.Zeth:BAAALAADCgQIBAAAAA==.',Zw='Zwörgnase:BAAALAADCgIIAgAAAA==.',Zy='Zyrinia:BAAALAAECgMIBwAAAA==.',['Àn']='Ànruna:BAAALAAFFAEIAQAAAA==.',['Às']='Àshe:BAAALAADCgYIBgAAAA==.',['Ás']='Áseriá:BAAALAADCgIIAgAAAA==.',['Ål']='Ålistar:BAAALAAECgEIAQAAAA==.',['Ìk']='Ìká:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end