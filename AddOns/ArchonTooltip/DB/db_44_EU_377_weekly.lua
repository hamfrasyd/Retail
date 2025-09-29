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
 local lookup = {'DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Warrior-Fury','Priest-Holy','Mage-Arcane','Priest-Shadow','DemonHunter-Vengeance','Unknown-Unknown','Druid-Balance','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Mage-Frost','Rogue-Outlaw','Shaman-Enhancement','Paladin-Retribution','DeathKnight-Blood','Druid-Restoration','Paladin-Holy','Hunter-Marksmanship','Rogue-Subtlety','Druid-Feral','DeathKnight-Frost','Druid-Guardian','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Paladin-Protection','Monk-Windwalker','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','DeathKnight-Unholy','Warrior-Protection',}; local provider = {region='EU',realm='LesClairvoyants',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abbanhon:BAAALAADCgcIGwAAAA==.Abd:BAABLAAECoEXAAIBAAgIJh8ULgB/AgABAAgIJh8ULgB/AgAAAA==.',Ad='Ada:BAABLAAECoE0AAMCAAgIBBqxFwBOAgACAAgIBBqxFwBOAgADAAcIJw0AAAAAAAAAAA==.',Ae='Aeka:BAAALAADCgMIAwAAAA==.Aelthas:BAAALAADCgIIAgAAAA==.',Ag='Agraou:BAABLAAECoEUAAIEAAcI9hK/CAC9AQAEAAcI9hK/CAC9AQAAAA==.',Ah='Ahésior:BAAALAAECgYIDAAAAA==.',Ai='Aigis:BAABLAAECoElAAIFAAgIchb6OwATAgAFAAgIchb6OwATAgAAAA==.',Al='Alarinà:BAAALAADCggICwAAAA==.Alcy:BAAALAADCgUIBQAAAA==.Aleidra:BAAALAAECgYICwAAAA==.Alenice:BAACLAAFFIEIAAIGAAIIUB5dGACyAAAGAAIIUB5dGACyAAAsAAQKgR4AAgYACAjMInIHACMDAAYACAjMInIHACMDAAAA.Alssahir:BAAALAAECgMIAgAAAA==.Alsyndrïel:BAAALAADCgEIAQAAAA==.Alturiel:BAAALAADCgcICwAAAA==.',An='Anasterïan:BAAALAADCgUIBQAAAA==.Aneriana:BAAALAAECgMIAwAAAA==.Another:BAABLAAECoEnAAIHAAgIvh/cIAC4AgAHAAgIvh/cIAC4AgAAAA==.Anthénia:BAAALAADCgIIAwAAAA==.',Ar='Aragoon:BAAALAADCgYICAAAAA==.Aragornn:BAAALAAECgcICQAAAA==.Arcaneï:BAAALAADCgcIBwAAAA==.Ardaths:BAAALAADCgUIBQAAAA==.Arkanges:BAAALAAECgYIDAABLAAFFAMIBwAIAFghAA==.Arkangë:BAAALAAECgEIAQABLAAFFAMIBwAIAFghAA==.Arkànges:BAACLAAFFIEHAAIIAAMIWCGEDAD7AAAIAAMIWCGEDAD7AAAsAAQKgSYAAwgACAi4I30IACgDAAgACAi4I30IACgDAAYACAhdE005ANIBAAAA.Arlyn:BAABLAAECoEUAAIJAAYILBeQHwCCAQAJAAYILBeQHwCCAQAAAA==.Arlynis:BAAALAAECgcIEwAAAA==.Artachaman:BAAALAADCggICgABLAAECgYICQAKAAAAAA==.Artachasseur:BAAALAAECgYICQAAAA==.Arwynn:BAAALAAECggIEAAAAA==.',As='Ashford:BAAALAADCggICAABLAAECggICAAKAAAAAA==.Ashu:BAABLAAECoEhAAILAAcIjBYvMwDBAQALAAcIjBYvMwDBAQAAAA==.Asmodehus:BAAALAAECgYIEgAAAA==.Aspen:BAABLAAECoEXAAIMAAYI5yInBQBVAgAMAAYI5yInBQBVAgAAAA==.Astra:BAAALAAECgYIDAAAAA==.',At='Athanas:BAAALAADCgYIBgAAAA==.Atsusa:BAAALAADCgMIAwABLAAECgcIHAANALcbAA==.',Au='Aurassgar:BAAALAAECgQICgAAAA==.Auroreane:BAABLAAECoEUAAIOAAYIXQdOvgACAQAOAAYIXQdOvgACAQAAAA==.',Av='Avalarion:BAABLAAECoEVAAIPAAYIuRrrJgDJAQAPAAYIuRrrJgDJAQAAAA==.Avochdar:BAAALAADCgcIBwAAAA==.',Ay='Ayasha:BAAALAAECgYIEQAAAA==.',Az='Azakiel:BAAALAADCggICAAAAA==.',Ba='Baalrog:BAAALAAECgQIDAAAAA==.Baalthazar:BAAALAAECgYIDgAAAA==.Babzdead:BAAALAADCgIIAgAAAA==.Babzet:BAAALAAECgIIAwAAAA==.Barah:BAAALAADCggICAABLAAECggIJwAQALggAA==.Barakdoum:BAACLAAFFIEHAAIRAAMIkw7lAgDoAAARAAMIkw7lAgDoAAAsAAQKgT4AAhEACAiTI9sBAC8DABEACAiTI9sBAC8DAAAA.Bartesounet:BAAALAAECgYIDQAAAA==.Battosai:BAAALAAECgQICwAAAA==.',Be='Belelf:BAAALAADCgYIBgAAAA==.Belphéggorh:BAAALAAECgYIDAAAAA==.Bendo:BAAALAADCgUIBgAAAA==.Berylia:BAAALAADCggIHgABLAAECggILwASACkZAA==.Bestgïrl:BAAALAADCgcIBwABLAAECggIIAATAIEaAA==.Beylphé:BAAALAADCggIDwABLAAECgYIDAAKAAAAAA==.',Bi='Bigbløødy:BAAALAADCgcIDgAAAA==.Biscoth:BAAALAADCggIEAABLAAECgYICQAKAAAAAQ==.Bisøunours:BAAALAADCgcICAAAAA==.Bièrenado:BAAALAADCgEIAQAAAA==.',Bl='Blacklîght:BAAALAAECgYIEgAAAA==.Bluenight:BAAALAAECgcIBwAAAA==.',Bo='Bobo:BAAALAADCgcIBwAAAA==.Bombur:BAAALAADCgcIGQAAAA==.Boombotte:BAAALAADCgcICAAAAA==.Boomerpal:BAAALAADCgUIBQAAAA==.',Br='Brennuss:BAAALAADCgMIAwABLAADCgcIDQAKAAAAAA==.Brosselee:BAAALAAECgEIAQAAAA==.Bruto:BAAALAAECggICgAAAA==.',Bu='Bulli:BAAALAAECgQIBgAAAA==.',['Bé']='Bézivin:BAAALAAECggIBgAAAA==.',['Bî']='Bîsmârck:BAAALAADCgEIAQAAAA==.',Ca='Calécia:BAAALAAECgEIAQAAAA==.Carmila:BAAALAADCggICQAAAA==.Carnage:BAAALAADCggICAAAAA==.Catala:BAABLAAECoEfAAIUAAcItBvTKAAVAgAUAAcItBvTKAAVAgAAAA==.',Ce='Celebryss:BAABLAAECoEjAAIOAAcIihKSgwB2AQAOAAcIihKSgwB2AQAAAA==.Celestice:BAAALAADCggIEAAAAA==.',Ch='Chainlee:BAAALAAECgUIBgABLAAECgYIEAAKAAAAAA==.Chevalistet:BAABLAAECoEeAAITAAcI2hq5EQAAAgATAAcI2hq5EQAAAgAAAA==.Chimio:BAAALAADCgcIDQAAAA==.Chässeömbre:BAABLAAECoElAAIVAAcIZyYABQABAwAVAAcIZyYABQABAwAAAA==.',Cl='Clairvoyante:BAABLAAECoEcAAILAAcIaho/MgDHAQALAAcIaho/MgDHAQAAAA==.Claris:BAABLAAECoEaAAISAAYI3xxjewDDAQASAAYI3xxjewDDAQABLAAFFAMICwAWAFgZAA==.Clarâ:BAAALAADCgQIBAAAAA==.Clautildae:BAAALAAECgYICwAAAA==.Clymène:BAAALAADCgUIBQAAAA==.',Co='Coeurdamour:BAAALAAECgYIDwAAAA==.Corthar:BAAALAADCggICAAAAA==.',Cr='Cracoth:BAAALAAECgYICQAAAQ==.Cramïch:BAAALAAECgQIBAAAAA==.Croam:BAAALAAECgEIAQAAAA==.Crusté:BAABLAAECoEUAAIXAAgI7wVvLQDuAAAXAAgI7wVvLQDuAAAAAA==.Crépuscule:BAAALAAECggIEwAAAA==.',Cy='Cyanith:BAAALAADCgEIAQAAAA==.',Da='Daalina:BAAALAADCgEIAQAAAA==.Dabururuma:BAAALAAECggIEAAAAA==.Daezana:BAAALAAECgIIAgAAAA==.Damaladinn:BAAALAAECgMIAwAAAA==.Darkstorms:BAABLAAECoEcAAINAAcIyiA4HgB8AgANAAcIyiA4HgB8AgAAAA==.Darshao:BAAALAAECgYIDgABLAAFFAMICwAWAFgZAA==.',De='Delysium:BAABLAAECoEYAAMMAAgI7w+tDwB6AQAMAAYI9BStDwB6AQAIAAgI3ADMgwBHAAAAAA==.Demoneldamar:BAAALAAECgcIEgAAAA==.Devilfazie:BAAALAAECgYIDQAAAA==.Devrim:BAAALAAECggICAAAAA==.',Di='Diivinaa:BAAALAAECgUICAAAAA==.Dimsûm:BAAALAAECgMIBQAAAA==.',Dj='Djeskia:BAAALAADCgYIBgAAAA==.',Dk='Dkerth:BAAALAAECggICAAAAA==.',Dr='Dractiizma:BAABLAAECoEfAAIDAAgI6xpXDQAuAgADAAgI6xpXDQAuAgABLAAFFAMICQAUAE4WAA==.Draelon:BAAALAADCgYICgAAAA==.Dragonnier:BAAALAAECgYIBgAAAA==.Dreamofme:BAAALAAECgUICAABLAAFFAIICAAYAB0SAA==.Drizzizt:BAAALAADCgIIAgAAAA==.Druidiizma:BAACLAAFFIEJAAIUAAMIThZrCwDqAAAUAAMIThZrCwDqAAAsAAQKgSwAAhQACAgeIs8FACIDABQACAgeIs8FACIDAAAA.',Du='Durendael:BAAALAADCgYIEQAAAA==.Durion:BAAALAADCgYICgAAAA==.',Dy='Dyvimtvar:BAAALAADCgIIAgAAAA==.',['Dä']='Därklunä:BAAALAAECgcIDAAAAA==.',['Dê']='Dêxter:BAAALAAECgYIBgAAAA==.',Ee='Eenaya:BAAALAADCgcIBwAAAA==.',Ek='Ekhinoks:BAAALAADCgYIBgAAAA==.',El='Elfsane:BAAALAAECgYICgAAAA==.Elisä:BAAALAADCgYICAAAAA==.Ellénia:BAAALAAECgYIDwAAAA==.Elreda:BAAALAAFFAIIAgAAAA==.Elrinne:BAAALAADCggIDwABLAAECggIEAAKAAAAAA==.Eléogeon:BAABLAAECoEgAAMUAAgIeiJeBwAOAwAUAAgIeiJeBwAOAwALAAcI8h9dGwBcAgAAAA==.Elérenne:BAAALAAECgIIAgAAAA==.Elïna:BAAALAADCggICAAAAA==.',Em='Emrakul:BAAALAADCggICAAAAA==.',En='Enotian:BAABLAAECoEaAAILAAgIrBW8JQAPAgALAAgIrBW8JQAPAgAAAA==.Entauma:BAAALAAECgYICgAAAA==.',Eo='Eorl:BAAALAADCgcIGwAAAA==.',Er='Erazeerah:BAAALAAECgQIBAAAAA==.Erdemte:BAAALAAECgMIAwAAAA==.Eridana:BAAALAAECgQICgAAAA==.Erzá:BAAALAAECgUIBQAAAA==.',Es='Eskïz:BAAALAADCgcIBwAAAA==.Espêranza:BAAALAAECgYICwAAAA==.',Ev='Evictore:BAABLAAECoEdAAIOAAcIuw9PiQBrAQAOAAcIuw9PiQBrAQAAAA==.',Ez='Ezrille:BAAALAAECgMIAwAAAA==.',['Eà']='Eàrànël:BAABLAAECoElAAIVAAcI1BpGHAABAgAVAAcI1BpGHAABAgAAAA==.',['Eù']='Eùrydice:BAAALAADCgYICwAAAA==.',Fa='Faelthir:BAAALAAECgUIBQAAAA==.Falcora:BAABLAAECoEcAAIDAAYIABcBFwCZAQADAAYIABcBFwCZAQAAAA==.Fantomelolo:BAAALAADCggIDgAAAA==.Fatalquent:BAAALAADCggIBQAAAA==.',Fd='Fdjjingx:BAAALAADCgMIAwAAAA==.',Fh='Fheckt:BAAALAAECgYICwAAAA==.',Fi='Fiegthas:BAABLAAECoEXAAIVAAcIogtaOwA8AQAVAAcIogtaOwA8AQAAAA==.Filaenas:BAAALAADCgMIAwAAAA==.',Fl='Flaco:BAAALAAECgIIBAAAAA==.Flocki:BAAALAADCgYIBgABLAAECgcIEQAKAAAAAA==.',Fr='Fredounette:BAAALAAECgYIBgAAAA==.Frigide:BAABLAAECoEgAAIZAAgIthHObgDjAQAZAAgIthHObgDjAQAAAA==.',Ft='Ftanck:BAAALAADCgUIBQAAAA==.',Ga='Gatuor:BAAALAAECggICAAAAA==.Gaurok:BAAALAADCggICwAAAA==.',Ge='Geraldindø:BAAALAAECgYIDQAAAA==.',Gh='Ghy:BAAALAAECgIIAgAAAA==.',Gl='Gliphéas:BAAALAAECgUICQAAAA==.Glàce:BAAALAAECgQIBAAAAA==.',Gr='Grafo:BAAALAAECgMICQABLAAECgUIBgAKAAAAAA==.Grafomage:BAAALAAECgUIBgAAAA==.Grahumf:BAAALAADCgYICQAAAA==.Grasshopper:BAAALAADCggICAAAAA==.Gratöpoil:BAAALAADCgcIBwAAAA==.Graziano:BAAALAADCgIIAgAAAA==.Grimalky:BAAALAAECgMIBAAAAA==.Grimbay:BAAALAADCgcIBwAAAA==.Grimdelwol:BAAALAAECgUIDQAAAA==.Grimmbo:BAAALAADCgcICwAAAA==.Grimwald:BAAALAADCgYIBgABLAAECgcIEAAKAAAAAA==.Grokitape:BAAALAAFFAIIAwAAAQ==.Grosbaf:BAAALAAECgYIBgAAAA==.',Gu='Guildware:BAAALAADCgMIAwAAAA==.Guldrac:BAAALAADCgMIAwAAAA==.Gullbob:BAAALAADCgQIBAAAAA==.Gulress:BAAALAAECgYICAAAAA==.Gultir:BAABLAAECoEgAAIWAAcIQAdobwDxAAAWAAcIQAdobwDxAAAAAA==.',['Gæ']='Gæsby:BAAALAADCgcIBwAAAA==.',['Gö']='Gödiva:BAABLAAECoEUAAISAAgImwtZmACMAQASAAgImwtZmACMAQAAAA==.',['Gü']='Güladin:BAAALAADCggICAAAAA==.Güulran:BAAALAADCggICAAAAA==.',Ha='Hadmire:BAAALAADCggIDwAAAA==.Haliki:BAABLAAECoEwAAIGAAgIJR0OGgCEAgAGAAgIJR0OGgCEAgAAAA==.Hallucard:BAAALAADCgQIBAAAAA==.Hamadreth:BAAALAADCgYIDQAAAA==.Haragorn:BAAALAAECgYIDAAAAA==.Hardgamerz:BAAALAAECgQIBAAAAA==.',He='Heiiko:BAACLAAFFIEYAAIFAAYIriKXAQBtAgAFAAYIriKXAQBtAgAsAAQKgRwAAgUACAgWJgYSAAIDAAUACAgWJgYSAAIDAAAA.Herunúmen:BAACLAAFFIEIAAIaAAMIiSNaAgC2AAAaAAMIiSNaAgC2AAAsAAQKgSIAAhoACAhyImoCABIDABoACAhyImoCABIDAAAA.Heyrin:BAABLAAECoEXAAMYAAcIFB0AEwD9AQAYAAYIzx0AEwD9AQALAAIIoBUqdwCFAAAAAA==.',Hi='Highglandeur:BAAALAADCgIIAgAAAA==.Hildya:BAABLAAECoEUAAMWAAcI6xzdNgDHAQAWAAcIKxzdNgDHAQAOAAEIuB2kEQE5AAAAAA==.',Ho='Holycheat:BAAALAADCgQIBQAAAA==.Holystik:BAAALAAECgYIEgAAAA==.',Hu='Huntermarché:BAAALAADCgMIAwAAAA==.',Hy='Hytomì:BAAALAADCggICAAAAA==.',['Hè']='Hèra:BAAALAADCggIEQAAAA==.',['Hé']='Héphaistos:BAAALAAECgEIAQAAAA==.',['Hî']='Hîly:BAAALAADCggICAAAAA==.',['Hï']='Hïly:BAAALAAECggIEgAAAA==.',Ic='Icemaster:BAAALAADCgIIAgABLAAECgYIDAAKAAAAAA==.',Ik='Ikthul:BAAALAADCgcIGgAAAA==.',Il='Iliräge:BAAALAAECgMIAwAAAA==.Illyann:BAAALAADCgcIBwAAAA==.',In='Inaya:BAAALAAECgYIDQAAAA==.Innaris:BAAALAAECgEIAQAAAA==.Intenser:BAAALAADCgMIAwAAAA==.',Is='Isménien:BAAALAADCggIDwAAAA==.Isoka:BAAALAADCgQIBAAAAA==.',It='Ithanormu:BAAALAADCgEIAQABLAADCgcICQAKAAAAAA==.',Iw='Iwannakillu:BAAALAADCggIFQAAAA==.',Ja='Jaerri:BAAALAAECgMIAwAAAA==.',Ji='Jijøù:BAAALAAFFAMIAwAAAA==.',Jo='Jobloo:BAACLAAFFIEGAAIZAAIIOxPRQwCTAAAZAAIIOxPRQwCTAAAsAAQKgSEAAhkABwg1IuAmALICABkABwg1IuAmALICAAAA.Jorren:BAAALAAECggIEAAAAA==.',Js='Jsuismorte:BAAALAADCgMIAwAAAA==.',['Jî']='Jînx:BAAALAADCgIIAgAAAA==.',['Jø']='Jømanouche:BAAALAAECgMIBQAAAA==.',Ka='Kakuzo:BAAALAADCgYIBwAAAA==.Kaldryel:BAAALAADCgEIAQAAAA==.Kalhindra:BAAALAAECgIIAgABLAAECggIIAAZALYRAA==.Kallie:BAAALAAECgMIBgAAAA==.Kaluksamdi:BAABLAAECoEiAAMIAAgIsxpKKgAPAgAIAAcI9hhKKgAPAgAGAAIIZAwDlwBjAAAAAA==.Karaa:BAAALAADCggICAAAAA==.Karros:BAAALAADCgYICQAAAA==.Katheia:BAAALAAECgMIAgAAAA==.Kathîa:BAABLAAECoEeAAMVAAgIphmlEABqAgAVAAgIphmlEABqAgASAAYIQA6S4AAFAQAAAA==.Katnisse:BAAALAADCgUIBQAAAA==.Kattarn:BAAALAADCgMIAwAAAA==.',Ke='Kelkneurones:BAAALAADCgQIBAAAAA==.Kerronz:BAABLAAECoEbAAMbAAcIyRONQADXAQAbAAcIyRONQADXAQANAAYIgAkYtQDaAAAAAA==.Kertchup:BAABLAAECoEeAAISAAgIKR8IKgCjAgASAAgIKR8IKgCjAgAAAA==.Keya:BAAALAADCgIIAQABLAAECgYIDQAKAAAAAA==.',Kh='Khanarbreizh:BAAALAADCgYIBgAAAA==.Khanh:BAAALAADCgQIBAAAAA==.Khroslo:BAABLAAECoETAAIZAAgIghdSPgBcAgAZAAgIghdSPgBcAgAAAA==.Khykhii:BAACLAAFFIEIAAIGAAIIMRHOLQB8AAAGAAIIMRHOLQB8AAAsAAQKgS8AAwYACAhvF94kAD0CAAYACAhvF94kAD0CAAwABAgUC5gfALIAAAAA.Khâzar:BAAALAAECgYICQAAAA==.',Ki='Kikixm:BAAALAAECgIIAgAAAA==.Kils:BAABLAAECoEoAAIIAAgIiR3nEgDCAgAIAAgIiR3nEgDCAgAAAA==.Kiradessus:BAAALAAECgUIEAAAAA==.',Ko='Koghy:BAAALAADCggICAAAAA==.Koo:BAAALAADCgcIBwAAAA==.Korva:BAAALAAECgYIBwAAAA==.',Kr='Kraznar:BAAALAADCgQIBAABLAAECggIDAAKAAAAAA==.Kresnaste:BAAALAAECgMIAwAAAA==.Kreynna:BAAALAADCgcIDQAAAA==.Krivlak:BAABLAAECoElAAIDAAcITh9ADABCAgADAAcITh9ADABCAgAAAA==.Kronit:BAAALAAECgUICQABLAAECggIJwAHAL4fAA==.Krotin:BAAALAAECgQIBgABLAAECggIJwAHAL4fAA==.',Ks='Kshaic:BAAALAAECgcICgABLAADCgcIDQAKAAAAAA==.',Ku='Kurooyouma:BAAALAADCggIDAAAAA==.',Kv='Kvë:BAAALAAECgYICwAAAA==.',Ky='Kynara:BAAALAADCggIHAAAAA==.Kyubî:BAAALAADCggIEgAAAA==.',['Kà']='Kàmï:BAAALAAECgYICwAAAA==.',['Kä']='Kält:BAAALAAECgEIAQAAAA==.Kätsøü:BAABLAAECoEgAAISAAYIMSR6NgBxAgASAAYIMSR6NgBxAgAAAA==.',['Kë']='Kërronz:BAAALAAECgIIAgABLAAECgcIGwAbAMkTAA==.',['Kï']='Kïnvara:BAAALAADCgcIBwAAAA==.',La='Lameta:BAAALAAECgIIAwAAAA==.Lastresort:BAABLAAECoEUAAIcAAYIgBnxIADeAQAcAAYIgBnxIADeAQAAAA==.Lastresört:BAAALAAECgUICgAAAA==.Laurièl:BAAALAADCggICAAAAA==.Laylanaar:BAAALAADCgcICQAAAA==.Lazerman:BAAALAAECgUICAAAAA==.Laélith:BAAALAAECgIIAgAAAA==.',Le='Lebondjo:BAAALAAECgcIEQAAAA==.Lehmany:BAAALAAECggICgAAAA==.Leonia:BAAALAADCgcIGQAAAA==.Lesoucis:BAAALAADCgIIAgABLAAECggIHgAVAKYZAA==.Lewallondk:BAAALAADCgIIAgAAAA==.Lewalløn:BAABLAAECoEkAAINAAcIZxpHRgDiAQANAAcIZxpHRgDiAQAAAA==.Lexiatroll:BAAALAADCgEIAQAAAA==.',Li='Lillï:BAAALAADCgIIAgAAAA==.Liløù:BAAALAAECgYIBgABLAAECggIJgAbAE8UAA==.Linaya:BAAALAADCggICAABLAAECgYIDQAKAAAAAA==.Lip:BAABLAAECoEmAAQdAAgIMCR6DAAoAwAdAAgIMCR6DAAoAwAeAAUIahqwEwBhAQAcAAEIZRMNhQA8AAAAAA==.Lipstíck:BAAALAAECgIIAgAAAA==.Livynette:BAAALAADCgcIDQAAAA==.',Lo='Logan:BAAALAAECgYIBgAAAA==.Lolosa:BAAALAADCgMIBAAAAA==.Loulotte:BAAALAADCgcICwAAAA==.Loxodon:BAABLAAECoEeAAMSAAcIMR7WRQBAAgASAAcIMR7WRQBAAgAfAAYIuBAvNgAgAQAAAA==.Loztanka:BAAALAAECgIIAgAAAA==.',Lu='Lusir:BAABLAAECoEjAAIgAAcItAqLMQBMAQAgAAcItAqLMQBMAQAAAA==.Luthorr:BAAALAAECgMIAwAAAA==.',Ly='Lyanna:BAAALAAECgQIBAAAAA==.',['Lé']='Léabeillae:BAACLAAFFIELAAIWAAMIWBlEDADqAAAWAAMIWBlEDADqAAAsAAQKgTIAAhYACAjvIQMSAMMCABYACAjvIQMSAMMCAAAA.Léânâ:BAAALAAECgQIBgAAAA==.',['Lï']='Lïvy:BAABLAAECoEZAAIFAAYI/RmITgDPAQAFAAYI/RmITgDPAQAAAA==.',['Lô']='Lôlà:BAAALAADCggIDgAAAA==.Lôlâ:BAAALAADCggIDgAAAA==.',Ma='Maca:BAAALAAECggICAAAAA==.Macko:BAAALAAECgQIBAAAAA==.Mahri:BAABLAAECoEvAAMSAAcIKRkJUQAhAgASAAcIKRkJUQAhAgAVAAYIxBD4NQBbAQAAAA==.Mahêl:BAAALAADCgIIAgABLAAECgYIDAAKAAAAAA==.Malco:BAAALAADCgEIAQAAAA==.Malyra:BAAALAADCggICAAAAA==.Malzabar:BAAALAAECggIEgAAAA==.Matory:BAABLAAECoEfAAIPAAcI5QmIOQBmAQAPAAcI5QmIOQBmAQAAAA==.Matsuda:BAAALAADCggIEgAAAA==.',Me='Melraan:BAAALAAECgEIAQAAAA==.Melzeth:BAAALAADCgIIAgAAAA==.Mercurocrøme:BAAALAADCgcIBwABLAAECgIIAgAKAAAAAA==.Metrozen:BAABLAAECoEXAAIhAAcIChy5DgBDAgAhAAcIChy5DgBDAgAAAA==.Meuhlterribl:BAAALAAECgYIDwAAAA==.',Mi='Mictita:BAAALAADCggIHgAAAA==.Midorin:BAABLAAECoEZAAIiAAgIWCD+AwCcAgAiAAgIWCD+AwCcAgAAAA==.Minaka:BAABLAAECoEiAAIjAAcIjB1ZFwBMAgAjAAcIjB1ZFwBMAgAAAA==.Mirandah:BAAALAADCgcIBwAAAA==.Mirinda:BAAALAADCggIFwAAAA==.Mirlina:BAAALAAECgIIAgAAAA==.Mithrilak:BAAALAADCgQIBAAAAA==.',Mo='Mo:BAAALAADCggICAAAAA==.Moji:BAAALAAECgUICAAAAA==.Molette:BAAALAADCgYICQAAAA==.Mordrim:BAABLAAECoEnAAIHAAgIhhwhKACVAgAHAAgIhhwhKACVAgAAAA==.Morwëen:BAAALAADCgcICwAAAA==.Moufett:BAAALAAECgIIAgABLAAFFAUIEAAhANwdAA==.',My='Mylial:BAAALAADCgMIAwAAAA==.Mystilia:BAAALAAECgQIDQAAAA==.',['Mä']='Mäbelrode:BAAALAADCgcIFAAAAA==.Mäëlis:BAAALAADCgIIAgAAAA==.',['Mé']='Méprèske:BAABLAAECoEWAAISAAYILgly1gAaAQASAAYILgly1gAaAQAAAA==.Mézal:BAAALAADCgUIBQAAAA==.',Na='Naddia:BAAALAADCggIDgAAAA==.Naky:BAAALAAECgQIBAAAAA==.Nalkas:BAAALAADCgcIDwAAAA==.Nariah:BAABLAAECoEqAAMdAAgIVSN1DAAoAwAdAAgIVSN1DAAoAwAcAAEIwxjmggBAAAAAAA==.Natch:BAAALAAECgYIDAAAAA==.Natsú:BAAALAADCgQIBwAAAA==.',Ne='Nealsynn:BAAALAADCgcIGQAAAA==.Nephalem:BAAALAADCggICAAAAA==.Neuvillette:BAAALAADCgMIAwAAAA==.Nevos:BAAALAAECgQIDAAAAA==.New:BAAALAADCggIKQAAAA==.Newtonun:BAAALAADCggIHwAAAA==.Nezkrose:BAAALAADCggIFgAAAA==.Neíth:BAAALAAECgMIBAABLAAECgcIBwAKAAAAAQ==.',Ni='Nidhögg:BAAALAAECgUIDwAAAA==.Nilania:BAAALAAECgIIAgAAAA==.',No='Noffs:BAABLAAECoEfAAMVAAcITCJ2CQC/AgAVAAcITCJ2CQC/AgAfAAYIXRHINAAqAQAAAA==.Nondidiou:BAAALAADCgYIBgAAAA==.',Ny='Nyll:BAABLAAECoEgAAMNAAgIEx5zGACcAgANAAgIEx5zGACcAgAbAAQISBD7fAD7AAAAAA==.',['Né']='Nélidreth:BAAALAAECgYIDwAAAA==.Néphys:BAAALAADCgEIAQAAAA==.',['Nò']='Nòxy:BAAALAADCgYIBgAAAA==.',['Nü']='Nünquam:BAAALAAECgIIAgABLAAECgcIBwAKAAAAAQ==.',Oh='Ohryà:BAACLAAFFIEJAAIfAAIIDQmVEwBrAAAfAAIIDQmVEwBrAAAsAAQKgSwAAh8ACAiWFHYhALQBAB8ACAiWFHYhALQBAAAA.',On='Onardoclya:BAABLAAECoEXAAIZAAcIwQbLywBCAQAZAAcIwQbLywBCAQAAAA==.Onastra:BAAALAADCgcIDQAAAA==.Onirine:BAAALAADCgcICwAAAA==.Onoza:BAAALAAECgYIDgAAAA==.',Or='Orran:BAAALAADCggIEQAAAA==.Orthank:BAAALAAECgEIAQAAAA==.Orélindë:BAAALAADCggIHAAAAA==.',Os='Osteox:BAACLAAFFIEQAAIhAAUI3B3oAgDbAQAhAAUI3B3oAgDbAQAsAAQKgTUAAiEACAjgJHUCAEsDACEACAjgJHUCAEsDAAAA.',Pa='Pakhao:BAAALAADCggICAAAAA==.Palatinaa:BAAALAADCgQIBAAAAA==.Paldiuss:BAAALAAECgMIBgAAAA==.Palloudia:BAAALAADCgEIAQAAAA==.Paléas:BAAALAADCgcIBwAAAA==.',Pe='Peautter:BAAALAAECgMIAwABLAAECgcIHAAdAIMbAA==.Petitana:BAABLAAECoEfAAISAAgIyAfgswBbAQASAAgIyAfgswBbAQAAAA==.Petitanagar:BAAALAADCggIJAAAAA==.',Ph='Phoenixyl:BAAALAADCggICQAAAA==.Physis:BAAALAAECgQIBwAAAA==.',Po='Pomtank:BAABLAAECoEVAAIJAAgIDRnpEAAqAgAJAAgIDRnpEAAqAgAAAA==.',Pr='Prethayla:BAAALAADCgcIEwAAAA==.Prinnceps:BAAALAAECgMIAwAAAA==.Prométhèe:BAAALAADCgYIDwAAAA==.Proüt:BAAALAADCgYIDwAAAA==.',Ps='Psalmonde:BAAALAADCgUIBQAAAA==.Psyche:BAAALAADCgMIBAAAAA==.',Pu='Pumpkinhead:BAAALAAECgYICQAAAA==.Putrifixe:BAAALAADCgUIBQAAAA==.',['Pä']='Pätatör:BAAALAADCgcIBwAAAA==.',Qu='Quickøx:BAAALAADCgEIAQAAAA==.',Ra='Ralariaa:BAABLAAECoEWAAMbAAgIRAqMXgBrAQAbAAgIRAqMXgBrAQANAAYIAwelvgDIAAAAAA==.Rayhiryn:BAAALAAECgYIDgAAAA==.Razadur:BAABLAAECoEVAAIRAAcI+AegFgBWAQARAAcI+AegFgBWAQAAAA==.Razeera:BAAALAAECgQIBAAAAA==.',Re='Renzyra:BAAALAAECggIDwABLAAECggIGgAGAAAdAA==.Reîyza:BAAALAAECgYICQAAAA==.',Rh='Rhaënya:BAAALAADCgYIBgAAAA==.Rhyse:BAAALAADCggICgAAAA==.',Ri='Rimah:BAAALAAECgcICgAAAA==.',Ro='Ronchon:BAAALAADCgYICQAAAA==.',Ru='Rukkìa:BAAALAADCggIDwAAAA==.',Sa='Saeryn:BAAALAAECgMIBAAAAA==.Saintebière:BAAALAADCgUIBQAAAA==.Salvâk:BAAALAAECgYIBgAAAA==.Samerlipupet:BAAALAAECgYIBgAAAA==.Samsaara:BAAALAAECgEIAQAAAA==.Samàel:BAAALAAECgYIDAAAAA==.Sanctaidd:BAABLAAECoEZAAISAAcIGRJQgwC0AQASAAcIGRJQgwC0AQAAAA==.Santiago:BAAALAADCgYIBgAAAA==.Saru:BAAALAAECgMIAwABLAAECgYIEgAKAAAAAA==.Saulquipeut:BAAALAAECgYIDAAAAA==.Savatte:BAACLAAFFIEMAAMkAAMIZRcQBQAJAQAkAAMIZRcQBQAJAQAZAAEITwUAAAAAAAAsAAQKgRoAAxkACAhjHOVcAAoCABkACAgNGuVcAAoCACQABgj/G74YAN8BAAAA.Savvattefufu:BAAALAAECgMIAwAAAA==.',Sc='Scatpal:BAAALAADCgMIAwABLAADCgYIDwAKAAAAAA==.Schlapükik:BAABLAAECoEUAAMOAAYILxoyeQCMAQAOAAYILxoyeQCMAQAWAAEIMQhNugAiAAAAAA==.Schnerfy:BAAALAAECgUICwAAAA==.Screudot:BAABLAAECoEVAAILAAgIfhLNLQDfAQALAAgIfhLNLQDfAQAAAA==.',Se='Sento:BAAALAADCggICAAAAA==.Seregril:BAAALAAECgMIAwAAAA==.Severüs:BAAALAAECgQIDgAAAA==.Sevy:BAAALAAECggICAAAAA==.',Sh='Shallyaa:BAABLAAECoEXAAIfAAcIjRxFEwA2AgAfAAcIjRxFEwA2AgAAAA==.Shameno:BAAALAAECggICAAAAA==.Shannel:BAAALAADCgYIBgAAAA==.Shaîtan:BAAALAAECgcICgAAAA==.Shela:BAAALAADCgIIAgAAAA==.Shellock:BAAALAAECggICAAAAA==.Shelra:BAABLAAECoEXAAIdAAcIwwvqcQBrAQAdAAcIwwvqcQBrAQAAAA==.Shenka:BAAALAADCgYIBgAAAA==.Shivaan:BAABLAAECoEXAAMCAAcI6A4vMgB1AQACAAcI6A4vMgB1AQADAAEIsQGVPAAWAAAAAA==.Shivanesca:BAABLAAECoEWAAIPAAcISh01FABcAgAPAAcISh01FABcAgAAAA==.Shnerfouille:BAAALAADCggIDQABLAAECgUICwAKAAAAAA==.Showker:BAAALAADCggIDQAAAA==.Shrëcky:BAAALAAECgUIBQABLAAECggIGwASAMUaAA==.Shuttlance:BAAALAAECgcIBwABLAAECggIJwAQALggAA==.Shyn:BAAALAAECgYIBgAAAA==.Shynwar:BAAALAAECgUIBQABLAAECgYIBgAKAAAAAA==.Shëli:BAABLAAECoEVAAIgAAYI/BkhIwC1AQAgAAYI/BkhIwC1AQABLAAECggICAAKAAAAAA==.',Si='Sigmunt:BAAALAADCgcIGgAAAA==.Silendil:BAABLAAECoEqAAIJAAgIpg+gIQBvAQAJAAgIpg+gIQBvAQAAAA==.Sithra:BAAALAAECgYIEAAAAA==.',Sk='Skarrleth:BAAALAAECgcIBwAAAQ==.',Sl='Slavinas:BAAALAAECgQIBQAAAA==.Släsher:BAABLAAECoEVAAIBAAgIuxRGaADKAQABAAgIuxRGaADKAQAAAA==.',Sn='Snack:BAAALAADCgUIBQAAAA==.',So='Soeurrow:BAAALAADCgIIAgAAAA==.Sofiyaah:BAAALAAECgYIDAAAAA==.Soléra:BAAALAAECgYIEwAAAA==.Sombraura:BAAALAAECgYIBgAAAA==.',Sp='Spartacus:BAAALAAECgYIBgAAAA==.',Sq='Squeechy:BAAALAADCgQIBwAAAA==.',St='Sthelios:BAABLAAECoEiAAIZAAgIwxytNAB7AgAZAAgIwxytNAB7AgAAAA==.Stiil:BAAALAADCggICAAAAA==.Stoness:BAAALAADCgcIBwAAAA==.Stormers:BAAALAAECgYICgAAAA==.',Su='Sulyah:BAAALAADCgIIAgAAAA==.Supremekaii:BAAALAADCgUIBQAAAA==.',Sy='Syll:BAAALAADCgcICQAAAA==.Sywan:BAAALAAECgYIBgAAAA==.',['Sä']='Sämaêl:BAABLAAECoElAAIOAAcIHiARUADwAQAOAAcIHiARUADwAQAAAA==.',['Sø']='Søsuk:BAAALAADCggICAAAAA==.',Ta='Tacocat:BAABLAAECoEnAAIQAAgIuCAtAgDyAgAQAAgIuCAtAgDyAgAAAA==.Taillon:BAAALAAECgMIAwAAAA==.Targes:BAAALAADCggICAABLAAECgIIAgAKAAAAAA==.Tartotémique:BAAALAADCggICAAAAA==.Tatayouyou:BAAALAADCggICAAAAA==.Taymas:BAAALAADCgcIBwABLAAECgMIAwAKAAAAAA==.',Te='Teega:BAABLAAECoEWAAMkAAgIhR3vDABvAgAkAAgIfxvvDABvAgAZAAMIqxcAAAAAAAAAAA==.',Th='Thalindra:BAAALAAECgYIBgAAAA==.Thaola:BAAALAADCgYIBgAAAA==.Thariantos:BAAALAADCggIJgAAAA==.Thasar:BAAALAAECgYIDgAAAA==.Thelarius:BAAALAADCggIDAAAAA==.Thorîn:BAAALAAECgIIAgAAAA==.Thrallgaze:BAAALAADCgcIBwAAAA==.Thranotyr:BAABLAAECoEXAAIGAAcIdhiQOQDQAQAGAAcIdhiQOQDQAQAAAA==.Thrän:BAAALAADCgcIBwAAAA==.Thylani:BAAALAAECgEIAQAAAA==.',Ti='Tinà:BAAALAADCgEIAQAAAA==.Tiphoria:BAAALAAECgIIAgAAAA==.Tirganac:BAAALAADCgcIBwAAAA==.Tirik:BAAALAADCggICwAAAA==.Tisiphone:BAAALAADCggICAABLAAECgYIDwAKAAAAAA==.',Tl='Tlachtgä:BAAALAADCggIFQAAAA==.',To='Toisondor:BAAALAAECgEIAQAAAA==.Tokyö:BAAALAAECgUIBQABLAAFFAMICQADALABAA==.Torgnoll:BAAALAADCgIIAgAAAA==.Tourmantal:BAABLAAECoEjAAQeAAcI+xO7FABTAQAdAAcI0RB0YwCTAQAeAAUIYRW7FABTAQAcAAMIrAfiawCOAAAAAA==.Toxixm:BAAALAAECgIIAwAAAA==.',Tr='Trafalgarlaw:BAACLAAFFIEIAAIjAAMI3RRYCQAFAQAjAAMI3RRYCQAFAQAsAAQKgSsAAiMACAi6IpwEACkDACMACAi6IpwEACkDAAAA.Traféïs:BAAALAADCgMIAwAAAA==.Triboule:BAACLAAFFIEOAAIFAAUIlx5VBQDzAQAFAAUIlx5VBQDzAQAsAAQKgS8AAgUACAheJqsDAG8DAAUACAheJqsDAG8DAAAA.Trikos:BAAALAADCgcIBwAAAA==.Trogo:BAAALAADCggIEgAAAA==.Tromagnon:BAABLAAECoEYAAIWAAYI5wwQZgAPAQAWAAYI5wwQZgAPAQAAAA==.',Ts='Tsumah:BAAALAAECgIIAgAAAA==.',Ty='Tyro:BAAALAADCgQIBAAAAA==.',['Tö']='Tökyo:BAACLAAFFIEJAAMDAAMIsAFYDACcAAADAAMIsAFYDACcAAACAAIIEQY3GQB0AAAsAAQKgSQAAwIACAg6FlUaADQCAAIACAg6FlUaADQCAAMABggZCJgkAAABAAAA.',Uj='Ujitsuna:BAAALAADCggICAAAAA==.',Ul='Ulgriruth:BAAALAAECgYICAAAAA==.',Um='Umami:BAAALAADCgYIBgAAAA==.Umbarto:BAAALAADCggIBgAAAA==.',Un='Unicorny:BAABLAAECoEUAAILAAYIJBR8RwBiAQALAAYIJBR8RwBiAQAAAA==.Unillusion:BAABLAAECoEWAAIHAAcILh9qOQBGAgAHAAcILh9qOQBGAgAAAA==.Unosdotes:BAAALAADCgYIBwABLAAECggIKQAgADUhAA==.',Ur='Urazon:BAAALAADCgcIBwAAAA==.Urën:BAAALAADCgQIBQAAAA==.',Va='Varana:BAAALAAECgMIAwAAAA==.',Ve='Venize:BAAALAAECgQICgAAAA==.',Vi='Visaj:BAABLAAECoEaAAIGAAgIAB3CGQCGAgAGAAgIAB3CGQCGAgAAAA==.Vitely:BAAALAADCgYIBgAAAA==.',Wa='Warorcs:BAABLAAECoEUAAIFAAYIeQ4hgAA/AQAFAAYIeQ4hgAA/AQAAAA==.',We='Wednesdayfan:BAAALAAECgEIAQAAAA==.',Wi='Wizzærd:BAABLAAECoEbAAMDAAgIzg3DHABTAQADAAcIuA/DHABTAQACAAgIvQf0QQANAQAAAA==.',Wo='Wofol:BAABLAAECoEYAAIUAAcIgQ5hZwAfAQAUAAcIgQ5hZwAfAQAAAA==.Worgdany:BAAALAAECgUICAAAAA==.Woriten:BAABLAAECoEoAAMFAAgI2hLZQAAAAgAFAAgI2hLZQAAAAgAlAAUI+wq6XQCqAAAAAA==.',Wy='Wyl:BAAALAAECgQIBAAAAA==.',Xa='Xambla:BAABLAAECoEXAAISAAcIlBO7kQCZAQASAAcIlBO7kQCZAQAAAA==.',Xc='Xcå:BAAALAAECgIIAgAAAA==.',Xe='Xerosiis:BAAALAAECgcIDgABLAAFFAYIGAAFAK4iAA==.',Xo='Xobic:BAAALAADCgMIAwAAAA==.',['Xà']='Xànthane:BAABLAAECoEmAAIhAAgIVw28HwBmAQAhAAgIVw28HwBmAQAAAA==.',Yu='Yugarten:BAAALAADCggIEAAAAA==.Yuhgito:BAAALAADCggICgAAAA==.Yuske:BAAALAAECgcIEQAAAA==.Yutsi:BAAALAADCgcIBwAAAA==.',['Yù']='Yùhé:BAAALAAECggIAwAAAA==.',Za='Zango:BAABLAAECoEZAAIWAAcI9xBgRwB/AQAWAAcI9xBgRwB/AQAAAA==.',Ze='Zelmo:BAAALAAECggICgAAAA==.Zen:BAAALAAECgYIEQAAAA==.',Zo='Zoradia:BAABLAAECoEUAAMIAAcIVxbIQQCSAQAIAAYIHxXIQQCSAQAGAAYIWAmubQAMAQAAAA==.',Zu='Zulko:BAAALAADCggICAAAAA==.Zullixia:BAAALAAECgIIAgAAAA==.Zullwu:BAABLAAECoEbAAIgAAcIsg5tKQCFAQAgAAcIsg5tKQCFAQAAAA==.',Zy='Zyhn:BAAALAADCgEIAQAAAA==.',['Àl']='Àlex:BAAALAADCgQIBQAAAA==.',['Äm']='Ämära:BAAALAAECgQICAAAAA==.',['Är']='Ärkänge:BAAALAADCgcIBwABLAAFFAMIBwAIAFghAA==.',['Äz']='Äzael:BAAALAADCgYIBgAAAA==.',['Ær']='Ærzá:BAAALAADCggICAAAAA==.Ærzã:BAAALAADCgYIBgAAAA==.',['Æy']='Æyzä:BAAALAADCgYIBgAAAA==.',['Ér']='Éri:BAAALAADCgYICgAAAA==.Érydis:BAAALAADCggIEAAAAA==.Érèbos:BAAALAADCggIEwAAAA==.',['Ðe']='Ðemøn:BAAALAAECggICAAAAA==.',['Ðé']='Ðéysa:BAAALAADCgIIAgAAAA==.',['Øl']='Øllàø:BAAALAADCgYICwAAAA==.',['Ør']='Ørîon:BAAALAADCgYIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end