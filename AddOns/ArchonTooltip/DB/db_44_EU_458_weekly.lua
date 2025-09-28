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
 local lookup = {'Unknown-Unknown','Mage-Frost','DeathKnight-Frost','DemonHunter-Havoc','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Hunter-BeastMastery','Paladin-Retribution','Warrior-Fury','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Blood','DeathKnight-Unholy','Druid-Restoration','Paladin-Holy','Warlock-Destruction','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','Druid-Balance','Warlock-Demonology','Hunter-Survival','Priest-Shadow','Hunter-Marksmanship','Evoker-Devastation','Druid-Guardian','Druid-Feral','Priest-Holy','Mage-Arcane','Priest-Discipline','Mage-Fire','Shaman-Enhancement','Rogue-Outlaw','Monk-Mistweaver','Monk-Brewmaster',}; local provider = {region='EU',realm='Onyxia',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abschwaten:BAAALAAECgYIEQAAAA==.',Ad='Adiline:BAAALAADCgcIBwAAAA==.',Ae='Aenas:BAAALAAECggIAgABLAAECggIAwABAAAAAA==.',Af='Afflíction:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Ak='Ako:BAAALAADCggICAABLAAFFAIIBgACAIAlAA==.Akáshià:BAAALAAECgIIAgAAAA==.',Al='Aliciakeys:BAAALAAECgIIAgABLAAFFAIICAADAKIiAA==.Alliandy:BAAALAAECgYIBgAAAA==.',Am='Amanatîdis:BAAALAAECgMIBQAAAA==.Amphdruid:BAAALAADCgQIBAAAAA==.Amunet:BAAALAAECgIIAgAAAA==.',An='Anker:BAAALAADCggICAAAAA==.Antonius:BAAALAADCgcIBwAAAA==.',Aq='Aquickmoa:BAAALAADCggIDgAAAA==.',Ar='Aratrim:BAAALAADCggIBwAAAA==.Archiatrà:BAAALAAECggIDwAAAA==.Ariun:BAAALAADCgUIBgABLAAECgYIDAABAAAAAA==.Arivey:BAABLAAECoEVAAMEAAYI1RweZQDSAQAEAAYI2hseZQDSAQAFAAIIdxmkRgB+AAAAAA==.Arrotec:BAAALAAECgMIBQAAAA==.Artharia:BAAALAAECggICAAAAA==.Arumad:BAAALAAECgMIBQABLAAECgcIGAAEAFcOAA==.Aráco:BAABLAAECoEUAAMGAAYIzQ6gCwBlAQAGAAYIzQ6gCwBlAQAHAAUIEQJTMQB1AAAAAA==.Arîanna:BAAALAADCggICAAAAA==.',As='Aselath:BAAALAAECgIIAgAAAA==.Asphyxie:BAAALAAECgIIAgAAAA==.',At='Atrêyu:BAAALAADCgcIDQAAAA==.',Av='Avíana:BAABLAAECoEVAAIIAAgILR5/DgBuAgAIAAgILR5/DgBuAgAAAA==.',Aw='Awan:BAAALAADCgcIBwAAAA==.',Ay='Ayatou:BAAALAAECgYIDQAAAA==.Ayazato:BAAALAADCggICwAAAA==.',Az='Azoh:BAAALAAECgMIAwAAAA==.Azurweib:BAABLAAECoEWAAIJAAcI3BjgVADjAQAJAAcI3BjgVADjAQAAAA==.Azurîon:BAAALAAECgYICAAAAA==.',Ba='Balph:BAAALAADCgcICAAAAA==.Baltoch:BAAALAAECgMIBQAAAA==.Barbâra:BAABLAAECoEYAAIIAAcIhBnuFwAFAgAIAAcIhBnuFwAFAgAAAA==.',Be='Belfort:BAAALAADCggICgAAAA==.Berok:BAAALAAECggICAAAAA==.Beôwulf:BAAALAADCgIIAgAAAA==.',Bl='Blackstar:BAAALAADCgEIAQABLAAECgYIEwABAAAAAA==.Blackstâr:BAAALAAECgYICwABLAAECgYIEwABAAAAAA==.Bloodlock:BAAALAADCggICAAAAA==.Bloodydh:BAAALAADCgEIAQAAAA==.Bltchimacow:BAAALAADCgcIBwAAAA==.Blutbulweii:BAAALAADCgcIBwAAAA==.Blyze:BAAALAADCggIDwAAAA==.Blàckstâr:BAAALAAECgYIEwAAAA==.',Bo='Boeppo:BAAALAADCggIEgAAAA==.Boneshanks:BAAALAADCggICAABLAAECggIDgABAAAAAA==.Bonifabius:BAAALAAECgIIAgAAAA==.',Br='Braunbaer:BAAALAAECgEIAQAAAA==.Brixz:BAAALAADCgEIAgAAAA==.Brîght:BAAALAADCggIEgAAAA==.',Bu='Bulweii:BAAALAAECggICAAAAA==.',Bw='Bwonsamdin:BAABLAAECoEYAAIKAAYI8h1SWgAJAgAKAAYI8h1SWgAJAgAAAA==.',['Bá']='Báhámut:BAAALAADCggIDwAAAA==.',['Bä']='Bämaggrodown:BAABLAAECoEXAAILAAcIfRluVwCyAQALAAcIfRluVwCyAQAAAA==.',['Bó']='Bóppo:BAAALAADCgcIDgAAAA==.',['Bø']='Bøyka:BAAALAADCgcIBwAAAA==.',['Bû']='Bûlletproof:BAAALAAECgYIDwAAAA==.',Ca='Caesurae:BAACLAAFFIEYAAMMAAYIkB6VAQDdAQAMAAUIoh6VAQDdAQANAAUIHh7oAgC1AQAsAAQKgTQAAwwACAi0JeEEACUDAAwACAiJJeEEACUDAA0ABghhJDwLAGECAAAA.Cailyt:BAAALAAECgYIBgAAAA==.Calico:BAAALAAECgYIBAAAAA==.Califo:BAAALAAECgEIAgAAAA==.Canim:BAAALAADCgIIBAAAAA==.Capitanenter:BAAALAADCggIFQAAAA==.Carnáge:BAABLAAECoEUAAQOAAcIvyALEAAZAgAOAAYIFSALEAAZAgADAAYIlBoEggC+AQAPAAEILSYhSQBtAAAAAA==.Castsalot:BAAALAAECgYIBgAAAA==.',Ce='Celestra:BAAALAAECgMIAgAAAA==.Cemtleman:BAAALAAECgIIAgABLAAFFAIICAAQAGsgAA==.Cerbero:BAAALAADCgYIBgAAAA==.Cerberon:BAABLAAECoEeAAMKAAgIORMIXQADAgAKAAgIORMIXQADAgARAAgIwREHIgDVAQAAAA==.',Ch='Chacii:BAAALAAECgIIAgAAAA==.Chaosnight:BAABLAAECoEaAAISAAgILxoPNwAxAgASAAgILxoPNwAxAgAAAA==.Cheguevarri:BAAALAAECgMIAwAAAA==.Chenso:BAAALAADCggICAAAAA==.Cherrycake:BAAALAAECgMIAwAAAA==.Chico:BAAALAADCggIDwAAAA==.Chuggernautz:BAAALAADCgcIEgAAAA==.',Ci='Ciu:BAAALAAECgYIBgAAAA==.',Cl='Clydebarrow:BAAALAADCggICAABLAAECgcIGAAIAIQZAA==.',Co='Corez:BAAALAAECggIEAAAAA==.Corpor:BAAALAAECgMIBAAAAA==.Cosé:BAAALAADCgYIBgAAAA==.',Cr='Crisintar:BAAALAADCggIIAAAAA==.Crystaleyé:BAAALAADCggICAAAAA==.',Cy='Cyberchief:BAABLAAECoEiAAITAAcIfR1wKABOAgATAAcIfR1wKABOAgAAAA==.Cynrix:BAAALAADCgYIBgAAAA==.Cyreen:BAAALAADCggICAAAAA==.',['Câ']='Câmú:BAABLAAECoEUAAIEAAgIfRGccwCxAQAEAAgIfRGccwCxAQAAAA==.',['Cæ']='Cædes:BAAALAAECggICAABLAAECggICAABAAAAAA==.',['Cí']='Cíbo:BAAALAAECgYIBgAAAA==.',['Cî']='Cîke:BAAALAADCggIEwAAAA==.',['Cô']='Côse:BAAALAADCgcIBwAAAA==.',['Cø']='Cøzn:BAAALAADCgMIAwAAAA==.',Da='Dabi:BAACLAAFFIENAAIDAAQIIx5OCwCLAQADAAQIIx5OCwCLAQAsAAQKgSEAAgMACAghI3kSABQDAAMACAghI3kSABQDAAAA.Dachlâtte:BAAALAADCgcIDQAAAA==.Daggi:BAAALAADCgcIBwAAAA==.Darkrainbow:BAAALAAECggICQAAAA==.Darksilent:BAAALAAECgYIDAAAAA==.Darkthúnder:BAAALAADCgYIBgAAAA==.',De='De:BAABLAAECoEfAAIKAAgI7x1RLQCWAgAKAAgI7x1RLQCWAgAAAA==.Deadinsîde:BAAALAAECgMIAwAAAA==.Deadscream:BAACLAAFFIEGAAIUAAIIYRvTIACiAAAUAAIIYRvTIACiAAAsAAQKgSYAAhQACAiNJbkIAAsDABQACAiNJbkIAAsDAAAA.Deathdoor:BAAALAADCgUIBwAAAA==.Dertank:BAABLAAECoEXAAIVAAcIRg5FKgB/AQAVAAcIRg5FKgB/AQAAAA==.Destrroo:BAAALAADCgcIDgAAAA==.Desølated:BAAALAAECgcIDQAAAA==.',Di='Dietzsche:BAAALAAECgMIBgAAAA==.Direxpala:BAAALAADCgcIBwAAAA==.',Do='Domirex:BAAALAAECgUICAAAAA==.Doomedhunter:BAAALAAECgEIAQABLAAECggIFQAIAC0eAA==.Doremir:BAAALAADCgcIDAAAAA==.',Dr='Dracwulf:BAAALAAECgYIDAAAAA==.Drakura:BAAALAAECgYIBQAAAA==.Driud:BAAALAADCggIBwAAAA==.Dronéx:BAAALAAECgYICQAAAA==.',Du='Duduwurst:BAAALAADCggICAAAAA==.Dunkelheít:BAAALAAECgcIEAAAAA==.',['Dä']='Dämolocke:BAAALAADCggIGQAAAA==.Dämonion:BAAALAAECgMIBQAAAA==.',['Dé']='Déadscream:BAAALAADCgUIBQAAAA==.',['Dü']='Düdü:BAAALAAECgIIAgAAAA==.',Ea='Earilalith:BAAALAAECgMIBAAAAA==.',Ed='Edeszeuge:BAAALAADCgIIAgAAAA==.',Eg='Egirl:BAAALAAECgcICAAAAA==.Egirlremix:BAAALAAECgcIDAAAAA==.',Ei='Eidz:BAAALAAECgQIBAAAAA==.',El='Ellmo:BAAALAAECggIEAAAAA==.Elnara:BAABLAAECoEYAAMEAAcIVw5OfwCZAQAEAAcIVw5OfwCZAQAFAAMIdwf/SgBnAAAAAA==.Elume:BAAALAADCgcICQAAAA==.Eléctrâ:BAAALAAECgcIEwAAAA==.',Em='Emeraldâ:BAAALAAECgYIBgAAAA==.',En='Enkon:BAAALAAECgMIAwAAAA==.Enshi:BAAALAAECgMIAwAAAA==.',Er='Eragô:BAAALAADCggICAAAAA==.Erbi:BAAALAADCggICAAAAA==.Eriado:BAAALAAECgUIBQAAAA==.Erlotril:BAABLAAECoEZAAIMAAcI9SEUDwCjAgAMAAcI9SEUDwCjAgAAAA==.Eráfin:BAAALAAECgcIEgAAAA==.',Et='Etho:BAAALAAECgYIDAABLAAECggIFwADAIohAA==.',Fa='Fanshuli:BAAALAAECgEIAgAAAA==.Fartseer:BAAALAADCgYICwAAAA==.',Fe='Fernis:BAAALAAECgYIBgAAAA==.Fescale:BAAALAADCgcIBwAAAA==.',Fl='Flexd:BAAALAADCggIFAABLAAECgYICQABAAAAAA==.',Fo='Forfoxsake:BAAALAADCggICAAAAA==.',Fr='Freezie:BAAALAADCggIDQAAAA==.Froth:BAABLAAECoEXAAIDAAgIiiH+FgD8AgADAAgIiiH+FgD8AgAAAA==.Fródò:BAAALAADCgYIBgABLAAECggIKwAWAJIdAA==.',Fu='Fumon:BAAALAADCgcICwAAAA==.Fumá:BAAALAAECggICAAAAA==.Furiós:BAAALAAECgQIBAAAAA==.',['Fâ']='Fârewell:BAAALAADCggIBgAAAA==.',Ga='Gabbadin:BAABLAAECoEYAAIUAAYI9gqirADqAAAUAAYI9gqirADqAAABLAAECggIKwAWAJIdAA==.Gahine:BAAALAADCgUIBAAAAA==.Garimto:BAAALAAECgIIAQAAAA==.',Ge='Gehirntod:BAABLAAECoEcAAILAAgIBRN9TgDPAQALAAgIBRN9TgDPAQAAAA==.Gelo:BAAALAADCgIIAgAAAA==.Getonmylevel:BAAALAAECgYIBgABLAAECgYIBgABAAAAAA==.Gewalt:BAAALAAECgIIAgAAAA==.',Gi='Ginaro:BAAALAADCggICAAAAA==.Gipsylord:BAABLAAECoEcAAMPAAgIhQz+IACbAQAPAAgIQAz+IACbAQADAAUIhQbw+wDiAAAAAA==.',Gl='Glaphanji:BAAALAADCggIGAABLAAECggIIAAKAHAeAA==.',Go='Goldkenzer:BAAALAAECgYIDgAAAA==.Goldochse:BAAALAAECgYIBgAAAA==.Golkosh:BAAALAADCgQIBAAAAA==.Gorle:BAAALAAECgYICgAAAA==.Gorluc:BAAALAAECgUIBgAAAA==.Gorlucy:BAAALAAECggICwAAAA==.Gorly:BAAALAADCggIEwAAAA==.Goruc:BAABLAAECoEWAAILAAcIZRPhUQDDAQALAAcIZRPhUQDDAQAAAA==.',Gr='Gral:BAAALAADCggICQABLAAECggIFwADAIohAA==.Grimmtor:BAAALAAECgMIAwAAAA==.Grondak:BAAALAAECgIIAgAAAA==.Großerorc:BAABLAAECoEcAAITAAgIbh1fJABnAgATAAgIbh1fJABnAgAAAA==.Grubênfrêd:BAAALAAECgcIEAAAAA==.Grumlii:BAAALAADCgMIAwAAAA==.Gráishak:BAABLAAECoEVAAILAAcIUwpCbwBuAQALAAcIUwpCbwBuAQAAAA==.Grómy:BAAALAAFFAIIAgAAAA==.',Gu='Gumbo:BAAALAADCgcIBwAAAA==.Gumpaa:BAAALAAECgcIEwAAAA==.Gustav:BAAALAADCggIHQAAAA==.',['Gé']='Gérhard:BAAALAADCggIDwAAAA==.',['Gí']='Gímly:BAAALAAECgQIBQAAAA==.',['Gö']='Göttergleich:BAAALAADCgcICwAAAA==.',Ha='Haborym:BAAALAADCgUIBQAAAA==.Hamfidampfi:BAAALAAECggIEgAAAA==.Hanura:BAAALAADCggIKAAAAA==.Harleen:BAAALAADCggICAABLAAECgYIFQACABoeAA==.',Hd='Hdl:BAAALAADCgYIBgAAAA==.',He='Hecke:BAAALAADCgcIBwAAAA==.Hexelulu:BAAALAAECgcIBgAAAA==.',Hi='Himyko:BAAALAAECgYIBgAAAA==.',Ho='Hoda:BAAALAAECgYICQAAAA==.Hoshpack:BAAALAADCggIEQAAAA==.Hotfreak:BAABLAAFFIEIAAIQAAIIayCPEQDCAAAQAAIIayCPEQDCAAAAAA==.',Hp='Hpbaxxter:BAABLAAECoEZAAIXAAcIyhrsFwAcAgAXAAcIyhrsFwAcAgABLAAECggIIAAKAHAeAA==.',Hu='Huntess:BAABLAAECoEcAAMJAAcIwx2nOgAzAgAJAAcIwx2nOgAzAgAYAAEIhhVxHgBHAAAAAA==.',Hy='Hypnokröte:BAAALAADCgcICgAAAA==.',['Hö']='Höllgrrosh:BAAALAADCgEIAQAAAA==.',['Hù']='Hùmmel:BAABLAAECoEoAAIZAAgIZx2SGgCBAgAZAAgIZx2SGgCBAgAAAA==.Hùntsmèn:BAABLAAECoEWAAMaAAcISgpaWwAzAQAaAAcISgpaWwAzAQAJAAIIYQl1AAFcAAAAAA==.',Ic='Ichígó:BAAALAADCggIEQABLAAECggIDgABAAAAAA==.',Id='Idéle:BAAALAADCggICAAAAA==.',Il='Ilidian:BAABLAAECoEdAAIKAAgIshGUfQC+AQAKAAgIshGUfQC+AQAAAA==.Ilska:BAAALAAECggIEwAAAA==.',Im='Imhotepsis:BAAALAAECgYICgAAAA==.Impirial:BAAALAAECggIBgAAAA==.',In='Invíctùs:BAABLAAECoEhAAIEAAgIwRjLQwAtAgAEAAgIwRjLQwAtAgAAAA==.',Ir='Iryut:BAAALAAECgcIEQAAAA==.',Is='Isehnix:BAABLAAECoEfAAIFAAcIgCWqBQD3AgAFAAcIgCWqBQD3AgAAAA==.',It='Itsatraap:BAAALAADCgcIBQAAAA==.',Ja='Jagdwoscht:BAABLAAECoEUAAMJAAgIrRT1rgAiAQAJAAYIFhv1rgAiAQAaAAgI/wD9swArAAAAAA==.Jahnna:BAAALAADCggIDgAAAA==.Jaruga:BAAALAAECgEIAQABLAAFFAUIEAAJAJUiAA==.Javae:BAAALAAECgMIAwAAAA==.Jaýdí:BAAALAAECgEIAQAAAA==.',Je='Jeeckyll:BAAALAAECgYICQAAAA==.Jeffbenzos:BAAALAAECgcICgAAAA==.Jetztknallts:BAAALAADCgcIBwAAAA==.',Jf='Jf:BAAALAADCgIIAgAAAA==.',Ji='Jinzzar:BAABLAAECoEeAAMGAAgITCBxAgDGAgAGAAgITCBxAgDGAgAbAAUIXA3IRQDsAAAAAA==.Jinzznope:BAAALAAECgYICwABLAAECggIHgAGAEwgAA==.',Ju='Juicylucy:BAAALAAECgMIAwAAAA==.Jule:BAAALAADCgQIBAABLAAECgYIEgABAAAAAA==.Jureesa:BAAALAAECgYIBgAAAA==.Juslez:BAAALAADCggIEAAAAA==.Justpassion:BAABLAAECoEfAAICAAcIUwv9OABpAQACAAcIUwv9OABpAQAAAA==.',Ka='Kaestel:BAABLAAECoEXAAIcAAgIAhQJDADlAQAcAAgIAhQJDADlAQAAAA==.Kaiman:BAAALAAECgYIBgAAAA==.Kalih:BAACLAAFFIEIAAIdAAIIBww1CwCQAAAdAAIIBww1CwCQAAAsAAQKgSMAAh0ACAgpF50OAD0CAB0ACAgpF50OAD0CAAAA.Kampfpanda:BAAALAADCgUIBQAAAA==.Karah:BAAALAADCggICAAAAA==.Karola:BAAALAAECgIIAgAAAA==.Kashen:BAAALAAECggIDwAAAA==.',Ke='Keeia:BAAALAADCggICAAAAA==.Keldarun:BAAALAAECggIAgAAAA==.Kelira:BAAALAAECgIIAgAAAA==.Keso:BAABLAAECoEfAAIUAAcIYSRvFgCpAgAUAAcIYSRvFgCpAgAAAA==.Kesora:BAAALAADCggIHQAAAA==.',Kh='Khane:BAAALAAECgIIAgABLAAECgYIFQAEANUcAA==.Kharesia:BAAALAAECggIEgAAAA==.Khun:BAAALAADCgYIDgABLAAECgcIGgAeAIIWAA==.',Ki='Kiaris:BAAALAAECgcIDQAAAA==.Kibô:BAAALAAECggIDgAAAA==.Kiwiz:BAAALAADCgUIBQAAAA==.',Kn='Knuzn:BAAALAADCggIDgAAAA==.',Ko='Kodishot:BAAALAAECgIIAgAAAA==.Korack:BAAALAAECgIIAgAAAA==.',Kr='Krautwurm:BAAALAAECggIEAAAAA==.Krosos:BAAALAADCgQIBAAAAA==.',Ku='Kudou:BAABLAAECoEcAAIQAAgIdB1aFwB9AgAQAAgIdB1aFwB9AgAAAA==.Kukipriest:BAAALAADCggICAAAAA==.Kuksi:BAABLAAECoEgAAIKAAgIcB7uHwDSAgAKAAgIcB7uHwDSAgAAAA==.Kulane:BAAALAADCgcIBwAAAA==.',Ky='Kyrlill:BAAALAADCggICAAAAA==.',['Kà']='Kàkashi:BAAALAAECgUIDAAAAA==.',La='Laeroo:BAAALAADCgUIBQAAAA==.Laladîn:BAAALAAECgEIAQAAAA==.Law:BAABLAAECoEbAAILAAcI0RjQOAAgAgALAAcI0RjQOAAgAgAAAA==.',Le='Leci:BAAALAADCgcIBwAAAA==.Leonidas:BAAALAADCgcIBwABLAAECgcIGgAeAIIWAA==.Leylana:BAAALAADCgEIAgAAAA==.Leyras:BAABLAAECoEVAAISAAcITQp5igArAQASAAcITQp5igArAQAAAA==.',Li='Liantriss:BAABLAAECoEWAAIKAAcIexNddADRAQAKAAcIexNddADRAQAAAA==.Liqquor:BAAALAADCgEIAQAAAA==.Lisànna:BAACLAAFFIEKAAIfAAQIRRXsEQBLAQAfAAQIRRXsEQBLAQAsAAQKgRcAAh8ACAjpGIozAF8CAB8ACAjpGIozAF8CAAAA.Littos:BAAALAADCgYIBgAAAA==.',Lo='Lokras:BAAALAADCgcIEQAAAA==.Loreal:BAAALAAECggIEQAAAA==.Loryl:BAAALAAECgYICgABLAAECgYIFQAEANUcAA==.',Lu='Luaxx:BAAALAADCgYIBgAAAA==.Luckos:BAAALAADCgcIBwAAAA==.Luhmy:BAABLAAECoEXAAIeAAcI9SLIEADLAgAeAAcI9SLIEADLAgAAAA==.Luzaria:BAAALAADCggICAAAAA==.',Ly='Lyneria:BAAALAAECgYIEQAAAA==.Lysianne:BAABLAAECoEVAAICAAYIGh4CHgAFAgACAAYIGh4CHgAFAgAAAA==.',['Lê']='Lêvâná:BAAALAAECgcIEQAAAA==.',['Ló']='Lótus:BAAALAADCgcIEQAAAA==.',['Lô']='Lôcý:BAAALAADCgcICgABLAAECgcIGgAeAIIWAA==.',['Lû']='Lûsringa:BAAALAADCggIFAABLAAECgcIGgAeAIIWAA==.',Ma='Mabelâ:BAABLAAECoEbAAQZAAcIwBSbNADUAQAZAAcIwBSbNADUAQAeAAYIWxgzRACgAQAgAAEI/B7pKwBUAAAAAA==.Machtvoll:BAAALAAECgMIAwAAAA==.Maelina:BAAALAADCgYIBgAAAA==.Magedrop:BAAALAAECgQICwAAAA==.Magnador:BAAALAAECgYIEgAAAA==.Mahabel:BAAALAADCgQIBAABLAADCggIDwABAAAAAA==.Mahakam:BAAALAADCggICAABLAAFFAUIEAAJAJUiAA==.Massafakka:BAAALAADCggICAAAAA==.Mavi:BAAALAADCgcIDgAAAA==.Maxximage:BAAALAADCgQIBAAAAA==.Maxximus:BAAALAADCgYIBgAAAA==.Maxxirogue:BAAALAADCggICAAAAA==.',Me='Meadlife:BAAALAADCggIDQAAAA==.Meistereder:BAAALAADCgYIBgABLAADCgcIEQABAAAAAA==.',Mi='Milamber:BAAALAADCgcICQABLAAECgcIEgABAAAAAA==.Milamberdudu:BAAALAADCggIEwABLAAECgcIEgABAAAAAA==.Milamberevo:BAAALAAECgcIEgAAAA==.Milambersham:BAAALAAECgYIDQABLAAECgcIEgABAAAAAA==.Mimsyy:BAAALAADCggIDAAAAA==.Mirâculíx:BAAALAADCgYIBgAAAA==.',Mo='Moira:BAAALAADCgUIBgAAAA==.Mokador:BAAALAAECgYIBQAAAA==.Moneè:BAAALAAECggICQAAAA==.Mops:BAAALAADCggIEAAAAA==.Mordion:BAAALAAECgYIDQAAAA==.Morgulf:BAAALAAECgUIDQAAAA==.Moroo:BAAALAADCggICAAAAA==.',Mu='Muggabadschr:BAABLAAECoEWAAIDAAYIyBWYkQCiAQADAAYIyBWYkQCiAQAAAA==.Mukju:BAABLAAECoEaAAIJAAgIURoDPgAoAgAJAAgIURoDPgAoAgAAAA==.',['Mé']='Méyl:BAAALAAECgIIAgAAAA==.',['Mô']='Mônte:BAAALAAECgMIAwAAAA==.Môritz:BAAALAAECgYIDQAAAA==.Môsh:BAAALAAECgUIBQAAAA==.',Na='Nacho:BAABLAAECoErAAIWAAgIkh0yFQCWAgAWAAgIkh0yFQCWAgAAAA==.Naguru:BAAALAAECgYIDQAAAA==.Naigul:BAAALAADCggICQAAAA==.Naihika:BAAALAADCgYICAAAAA==.Nakarox:BAACLAAFFIEHAAIcAAIIlSPLAQDPAAAcAAIIlSPLAQDPAAAsAAQKgRwAAhwACAgbIjoCAB8DABwACAgbIjoCAB8DAAAA.Nakoa:BAAALAAECgUIBQAAAA==.Namìna:BAAALAAECgEIAQAAAA==.Narathyr:BAAALAADCgEIAQAAAA==.Nashara:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.Nathra:BAAALAAECgYICQAAAA==.Naxatras:BAAALAAECgYIDAAAAA==.',Ne='Neefertiti:BAAALAAECgIIBAAAAA==.Nephôs:BAAALAAECgcIBQAAAA==.Neroni:BAAALAAECgIIBwAAAA==.Nersaya:BAAALAADCgcIBwAAAA==.',Ni='Nicklasli:BAAALAAECgMIAwAAAA==.Niilon:BAAALAADCgIIAgAAAA==.Nijeeh:BAAALAAECgYIDAABLAAECggIKAAZAGcdAA==.Nirva:BAABLAAECoEUAAIJAAYIJRstiQBrAQAJAAYIJRstiQBrAQAAAA==.Niveline:BAAALAADCgMIAwAAAA==.Niênna:BAABLAAECoEdAAMDAAgIGxpfUwAgAgADAAgI2BdfUwAgAgAPAAYIzhiFHwCmAQAAAA==.',No='Nohonor:BAAALAADCggICAAAAA==.',Nu='Nurisha:BAAALAADCggICAAAAA==.Nurysha:BAAALAAECgYIBgAAAA==.Nuxly:BAAALAAECgYIEAAAAA==.',Ny='Nykaria:BAAALAADCgcIBwABLAAECgcIEwABAAAAAA==.Nyraâ:BAAALAAECgEIAQAAAA==.',['Né']='Némèsis:BAAALAADCgcIBwAAAA==.',['Ní']='Nícki:BAAALAAECgMIBQAAAA==.',Oa='Oachkatzerl:BAAALAADCgEIAQAAAA==.',Oi='Oimusha:BAAALAADCggICAAAAA==.',Ol='Oliver:BAAALAAECgQICAAAAA==.',On='Onikage:BAAALAAECgIIAgAAAA==.',Os='Osladi:BAABLAAECoEiAAISAAcIORSUTQDXAQASAAcIORSUTQDXAQABLAAECggIKAAZAGcdAA==.',Pa='Pajun:BAABLAAECoEdAAMaAAgIxh67HgBZAgAaAAgIxh67HgBZAgAJAAEIWR8FAwFXAAAAAA==.Paladîs:BAAALAAECgIIAgAAAA==.Panteon:BAABLAAECoEWAAISAAcI1AuNaQCCAQASAAcI1AuNaQCCAQAAAA==.Papaschatten:BAAALAAECgYICgAAAA==.Paroodin:BAAALAAECgYIDQAAAA==.',Pe='Pepede:BAAALAADCgcICwAAAA==.Pepucina:BAAALAADCggICAAAAA==.',Ph='Phenex:BAAALAADCgMIAwAAAA==.Pheno:BAABLAAECoEWAAIEAAgI6xs7KgCRAgAEAAgI6xs7KgCRAgAAAA==.Phenonom:BAAALAAECgcICwAAAA==.',Pi='Piicolo:BAAALAADCgMIAwAAAA==.Pisanarias:BAAALAADCgcIBwAAAA==.Pitzpatz:BAAALAAECgIIAgAAAA==.',Pr='Prigak:BAABLAAECoEYAAIJAAgIBxjlTQD2AQAJAAgIBxjlTQD2AQAAAA==.Prilaria:BAAALAADCgcIBgABLAAECggIEgABAAAAAA==.Prisma:BAAALAADCgQIBAAAAA==.',Pu='Pucina:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Pw='Pwnyah:BAAALAADCgUIBAAAAA==.',Py='Pyronius:BAAALAADCgcIBwAAAA==.',['Pé']='Péy:BAABLAAECoEUAAIQAAgIwhO8MwDfAQAQAAgIwhO8MwDfAQAAAA==.',['Pü']='Püzcraft:BAABLAAECoEoAAIdAAgIKSS4BAAHAwAdAAgIKSS4BAAHAwAAAA==.',Qu='Quicksand:BAAALAAECgUIBQAAAA==.',Ra='Ravemanz:BAAALAAECgcIBwAAAA==.',Re='Recane:BAAALAAECggICwAAAA==.Reenju:BAAALAADCgMIAwAAAA==.Regala:BAAALAAECgYIDQAAAA==.Renate:BAAALAAECgcIEgAAAA==.Rewiyel:BAAALAADCggIDgAAAA==.',Ri='Riquas:BAABLAAECoEZAAITAAgIQR6gGQCxAgATAAgIQR6gGQCxAgAAAA==.',Ro='Ronzarok:BAABLAAECoEUAAMfAAcIaw60cwCMAQAfAAcIaw60cwCMAQAhAAEInwT8IQAgAAAAAA==.Rowñ:BAAALAAECgIIAgABLAAECggIFQAIAC0eAA==.',Ru='Ruppî:BAAALAAECgYICgAAAA==.',Ry='Ryomage:BAABLAAECoEZAAMfAAgIXCCIMQBpAgAfAAgIXCCIMQBpAgAhAAEILRB8HQA6AAAAAA==.Ryomdh:BAAALAADCgYIBgAAAA==.Ryompi:BAAALAADCggICAABLAAECggIGQAfAFwgAA==.',['Rá']='Rágée:BAAALAADCgcIDQABLAAECgcIGgAeAIIWAA==.',['Râ']='Râsh:BAACLAAFFIEHAAIEAAMIMRkrHwCtAAAEAAMIMRkrHwCtAAAsAAQKgSQAAgQACAjvIAEXAPcCAAQACAjvIAEXAPcCAAAA.',Sa='Saibot:BAABLAAECoEVAAIbAAgIdBvJIgDmAQAbAAgIdBvJIgDmAQAAAA==.Saifu:BAABLAAECoEbAAISAAcIagW2jQAiAQASAAcIagW2jQAiAQAAAA==.Saito:BAAALAAECggICAAAAA==.Sajuno:BAAALAADCggICAAAAA==.Sajà:BAAALAAECgEIAQAAAA==.Sakushî:BAAALAAECgcIBwABLAAECggIKwAWAJIdAA==.Salamisticks:BAAALAADCggIEAAAAA==.Santacruz:BAABLAAECoEUAAMTAAcI3RHLRADGAQATAAcI3RHLRADGAQAiAAMIQwUlIQBwAAAAAA==.Sarada:BAAALAAECgQIBgAAAA==.Sareliana:BAAALAADCgYICQABLAADCgcIBwABAAAAAA==.',Sc='Scharrak:BAAALAADCggIHwAAAA==.Schmeck:BAAALAAFFAIIAgAAAA==.Schnoppbub:BAAALAAECggIDAAAAA==.Schokella:BAAALAAECggICAAAAA==.Schwupibank:BAAALAAECgYIEgAAAA==.Scyrathia:BAAALAADCgYIBwABLAADCggICAABAAAAAA==.',Se='Segas:BAAALAADCgQIBQAAAA==.Segáfredó:BAAALAAECggICAAAAA==.Semyaza:BAAALAAECggIDwAAAA==.Senegram:BAAALAADCgEIAQAAAA==.Seraphinâ:BAAALAAECgQIBwAAAA==.Seusi:BAABLAAECoEjAAMCAAgIYxwfGgAlAgACAAgIAhwfGgAlAgAfAAcIAhYlXADQAQAAAA==.Sev:BAABLAAECoEnAAIUAAcIKCCEJQBaAgAUAAcIKCCEJQBaAgAAAA==.Sevcon:BAAALAAECgYIEAAAAA==.Sevonic:BAABLAAECoEaAAMjAAgIjRf0BgAWAgAjAAcI6Bj0BgAWAgANAAYIeRAAAAAAAAAAAA==.',Sh='Shadowbxrn:BAAALAADCggICAAAAA==.Shameful:BAAALAADCgYIBAAAAA==.Shamlo:BAAALAAECgUIBQAAAA==.Shanjin:BAAALAAECgIIAgAAAA==.Shanmo:BAAALAADCgcIBwAAAA==.Shaolai:BAAALAAECggICwAAAA==.Shaolique:BAAALAAECgYIBgAAAA==.Shibbedu:BAABLAAECoEWAAIEAAYI/BHskgBzAQAEAAYI/BHskgBzAQAAAA==.Shiveria:BAAALAADCggICAAAAA==.Shockbear:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.Shockomel:BAAALAAECgcIEQAAAA==.Shurul:BAABLAAECoEbAAIYAAgIphe4CAAEAgAYAAgIphe4CAAEAgAAAA==.Shytoos:BAAALAADCggICAAAAA==.',Si='Sikkens:BAAALAAECgYIDAABLAAECggICwABAAAAAA==.Silikara:BAAALAAECgQIBAAAAA==.Sinf:BAAALAADCgIIAgAAAA==.Sittentau:BAAALAAECgEIAQAAAA==.',Sk='Skâdî:BAAALAADCgcIBwAAAA==.Skândal:BAAALAAECgYIEQAAAA==.',Sl='Slickz:BAAALAAECggIAwAAAA==.',Sm='Smoký:BAAALAADCgIIAgAAAA==.',Sn='Snirat:BAAALAAECgYIBgAAAA==.',So='Soarqt:BAABLAAECoEmAAIMAAgI7hvGDQCxAgAMAAgI7hvGDQCxAgAAAA==.',Sp='Spacewizard:BAAALAAECgUICwAAAA==.Splätter:BAAALAAECggIEAAAAA==.',St='Steinbeißer:BAAALAADCgMIAwABLAADCggIGQABAAAAAA==.Stellalina:BAAALAADCggICAAAAA==.Stepsqt:BAAALAAECgYIBgAAAA==.Stinkguror:BAAALAAECgMIBAABLAAECgYICwABAAAAAA==.Stoorm:BAAALAADCggIMwABLAAECgcIGgAeAIIWAA==.Straciatella:BAAALAADCggICAAAAA==.Stürmsche:BAABLAAECoEaAAIeAAcIghaENADpAQAeAAcIghaENADpAQAAAA==.',Su='Suffgurgl:BAAALAADCgIIAgAAAA==.Sunzr:BAAALAADCgIIAgAAAA==.',Sy='Syd:BAAALAADCggIHQAAAA==.Syldarion:BAAALAAECgYIBgABLAAECgYIFQAEANUcAA==.Syntera:BAAALAADCgcIBwAAAA==.Syraxis:BAAALAAECgYIBgAAAA==.',['Sî']='Sîlverlîne:BAAALAAECgUICQAAAA==.',['Sû']='Sûnnschînê:BAAALAADCgUIBQAAAA==.',Ta='Taddie:BAABLAAECoEbAAIWAAcIIxV2MADQAQAWAAcIIxV2MADQAQAAAA==.Tajil:BAAALAADCgYIBgAAAA==.Takanan:BAAALAAECgEIAQAAAA==.Takimizu:BAAALAADCggICgABLAAECgYIFQACABoeAA==.Talinara:BAAALAADCggIDwAAAA==.Tandîr:BAAALAAECgYIDAABLAAFFAMIBwAEADEZAA==.Taniara:BAABLAAECoEbAAIDAAcIyRWzfADIAQADAAcIyRWzfADIAQAAAA==.Tariel:BAAALAADCggICAAAAA==.Tatatasahur:BAAALAADCggICAAAAA==.',Te='Telaría:BAAALAAECgYICAABLAAECggIEgABAAAAAA==.Tennyo:BAAALAAECgUIBQAAAA==.Testos:BAAALAAECgcIDQAAAA==.Tetty:BAAALAADCgcIBwAAAA==.',Th='Thalasereg:BAAALAADCgIIAgAAAA==.Thermir:BAAALAADCggIFgAAAA==.Theston:BAABLAAECoEXAAILAAgIdSGpGgDHAgALAAgIdSGpGgDHAgAAAA==.Thorina:BAACLAAFFIEIAAIFAAII7AXuEABZAAAFAAII7AXuEABZAAAsAAQKgSsAAwUACAjaDuwpADABAAUACAjaDuwpADABAAQAAQisBk4gAS0AAAAA.Thorvid:BAAALAAECgYIEgAAAA==.',Ti='Tilasha:BAABLAAECoEgAAIQAAgIGRsTGQBxAgAQAAgIGRsTGQBxAgAAAA==.Timori:BAAALAAECgcIEwAAAA==.Tipsy:BAABLAAECoEjAAIhAAgIzxwDBQAqAgAhAAgIzxwDBQAqAgAAAA==.Titanbull:BAAALAAECgYIEwAAAA==.',To='Tobsucht:BAAALAAECgIIAgAAAA==.Tohui:BAABLAAECoEnAAIkAAgIIRKWGADLAQAkAAgIIRKWGADLAQAAAA==.Tooróp:BAAALAAECgYIBgAAAA==.Tordon:BAABLAAECoEVAAIIAAcIFxAQKQB5AQAIAAcIFxAQKQB5AQABLAAFFAIIAgABAAAAAA==.Torolf:BAAALAAECgUIBQAAAA==.Towélié:BAAALAAECgYIBgAAAA==.',Tr='Trixter:BAAALAADCgIIAgAAAA==.Trophys:BAAALAAECggIDgABLAAFFAMIBwAEADEZAA==.',Ty='Tyraurque:BAACLAAFFIEGAAIOAAMIMRj9BQDpAAAOAAMIMRj9BQDpAAAsAAQKgSUAAg4ACAiNI0gDADUDAA4ACAiNI0gDADUDAAAA.Tyrralon:BAAALAAECgEIAQAAAA==.Tyrs:BAAALAAECggIAwAAAA==.',Tz='Tzwonk:BAABLAAECoEaAAMlAAgIpxjAEAAjAgAlAAgIpxjAEAAjAgAVAAcINweDOQAWAQAAAA==.',['Té']='Térrorjunky:BAAALAAECgEIAQAAAA==.',['Tí']='Tífì:BAAALAAECggIEAAAAA==.',Ul='Ulrick:BAAALAAECgYIDAAAAA==.',Um='Umbrauschi:BAAALAAECgYICgABLAAECggIHAATAG4dAA==.',Un='Unwriten:BAAALAAECgUICgAAAA==.',Ur='Uriell:BAAALAADCgcIBwAAAA==.',Us='Uskarr:BAABLAAECoEZAAILAAcIexLTUwC+AQALAAcIexLTUwC+AQAAAA==.',Va='Valkyrie:BAACLAAFFIEXAAIHAAcIwB1vAACZAgAHAAcIwB1vAACZAgAsAAQKgSYAAwcACAg4H6kFAMoCAAcACAg4H6kFAMoCABsABQgIHo8nAMABAAAA.Vandiur:BAAALAADCggICAAAAA==.Vanîc:BAAALAAECgEIAQAAAA==.',Ve='Veethó:BAAALAAECgcIEAAAAA==.Veltinshorde:BAABLAAECoEkAAIUAAYIGyDROQALAgAUAAYIGyDROQALAgAAAA==.',Vi='Vienta:BAAALAADCgEIAQAAAA==.Vilatriz:BAAALAAECgYIDQAAAA==.Vivianné:BAAALAADCggICAAAAA==.',Vo='Vorgos:BAAALAAECgIIAQABLAAECgYIBgABAAAAAA==.',Vu='Vunikat:BAAALAAECgcIEgAAAA==.Vuton:BAABLAAECoEZAAICAAcIVSBTEgBvAgACAAcIVSBTEgBvAgAAAA==.',Wa='Waldpups:BAAALAADCggIFgAAAA==.Wartork:BAAALAADCgMIAwAAAA==.',We='Weideglück:BAAALAADCggICAAAAA==.Weißbrot:BAABLAAECoEVAAMeAAYIHg2bYQAyAQAeAAYIHg2bYQAyAQAgAAEIIQQdOgAcAAAAAA==.',Wh='Whitemaydo:BAAALAAECgIIAgAAAA==.',Wi='Wizlo:BAABLAAECoEUAAMfAAgIERvcLgB1AgAfAAgIERvcLgB1AgAhAAEI2wxsHgA2AAAAAA==.',Wo='Woollahara:BAAALAAECgMIAwAAAA==.',['Wâ']='Wârlòrd:BAAALAAECgMIBAAAAA==.',['Wí']='Wíschmopp:BAAALAADCggIEgAAAA==.',Xa='Xardos:BAAALAADCgYIBgAAAA==.Xavj:BAAALAAECgcIDwAAAA==.',Xe='Xentos:BAABLAAECoEjAAMXAAgIph6nDQB+AgAXAAcI6iCnDQB+AgASAAII9hCu1wA5AAAAAA==.Xeri:BAAALAADCgEIAQAAAA==.',Xi='Xinestra:BAAALAADCggIEwAAAA==.',Xo='Xoloth:BAABLAAECoEeAAMTAAgImgYQdwAVAQATAAYIcwcQdwAVAQAUAAgI1wO+sgDeAAAAAA==.Xoseria:BAAALAAECgMIAwAAAA==.',Xq='Xqlusiv:BAABLAAECoEaAAIIAAcI0CCjCwCVAgAIAAcI0CCjCwCVAgAAAA==.',['Xî']='Xîêê:BAAALAAECggIEAAAAA==.',Ya='Yadana:BAAALAADCggICQAAAA==.Yadira:BAAALAADCggIFQAAAA==.Yaxxentra:BAAALAADCgYIBwAAAA==.',Yo='Yolofant:BAAALAAECggIEwAAAA==.Yortu:BAABLAAECoEhAAIYAAgIFBn0BAB2AgAYAAgIFBn0BAB2AgAAAA==.',Yr='Yrelia:BAAALAADCgcIDQAAAA==.',Yu='Yukiiko:BAAALAADCgIIAgAAAA==.Yungsnickers:BAAALAAECggIBAAAAA==.Yunâlesca:BAAALAAECggICwAAAA==.Yuzuki:BAAALAADCgcIDgABLAAECgcIEAABAAAAAA==.',Za='Zaljian:BAAALAAECgMIAwABLAAECggIDgABAAAAAA==.Zandaladin:BAABLAAECoEYAAIRAAcIShw6FQA9AgARAAcIShw6FQA9AgAAAA==.Zappsarap:BAAALAADCgcICAAAAA==.Zarakí:BAABLAAECoEZAAIEAAcIIBomWgDtAQAEAAcIIBomWgDtAQABLAAECggIDgABAAAAAA==.Zasias:BAAALAAECgIIAQAAAA==.Zatoras:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Ze='Zerødýme:BAAALAAECgIIAgAAAA==.Zewarolle:BAAALAAECgIIAgAAAA==.',Zh='Zhâran:BAAALAAECgcICgAAAA==.',Zi='Zirconis:BAAALAADCgYIBgABLAAECgYIFgADAMgVAA==.Zivara:BAAALAADCggICAAAAA==.',Zo='Zoeki:BAAALAAECgUIBQABLAAFFAIIBQAeABAPAA==.Zora:BAAALAAECgEIAQAAAA==.Zorades:BAAALAADCgcICAAAAA==.Zoralth:BAAALAAECgIIBAABLAAECggIDgABAAAAAA==.Zottelknecht:BAABLAAECoEkAAIUAAcIZyDsHACDAgAUAAcIZyDsHACDAgAAAA==.Zoyâ:BAAALAAECggICAAAAA==.',['Âi']='Âion:BAAALAADCgcIBwAAAA==.',['Âr']='Ârion:BAABLAAECoEkAAMUAAgIlRdYLwAxAgAUAAgIlRdYLwAxAgATAAYIbQW6ewABAQAAAA==.Ârvên:BAAALAADCgcIBwAAAA==.',['Èm']='Èmily:BAAALAADCgcIDwAAAA==.',['Øc']='Øcelot:BAAALAADCggICAAAAA==.',['Ún']='Únique:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end