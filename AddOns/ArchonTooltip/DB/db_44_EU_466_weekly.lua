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
 local lookup = {'Shaman-Restoration','Paladin-Retribution','Unknown-Unknown','Warrior-Fury','Priest-Shadow','Priest-Discipline','Druid-Balance','Mage-Frost','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Druid-Feral','Warlock-Affliction','DemonHunter-Havoc','Priest-Holy','Warrior-Protection','Monk-Windwalker','Paladin-Holy','Mage-Arcane','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Elemental','DeathKnight-Unholy','Monk-Mistweaver','Evoker-Devastation','Warrior-Arms','Druid-Restoration','Mage-Fire','Hunter-Survival','Paladin-Protection',}; local provider = {region='EU',realm='Teldrassil',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abilalla:BAAALAAECgYIDAAAAA==.Absolutnrk:BAAALAADCgQIBAAAAA==.',Ac='Acra:BAAALAADCggICAABLAAECgcIFgABAMcaAA==.Actionbutton:BAAALAAECgcIDQAAAA==.',Ad='Adalaz:BAAALAADCgYICQAAAA==.',Ae='Aeloria:BAAALAADCgcIBwAAAA==.',Ag='Agapala:BAAALAAECgYICQAAAA==.Agrippanus:BAABLAAECoEVAAICAAYIdxVCkACbAQACAAYIdxVCkACbAQAAAA==.',Ah='Ahko:BAAALAADCgIIAgABLAAECgEIAgADAAAAAA==.',Ak='Akhzell:BAABLAAECoEXAAIEAAcI6AiChwApAQAEAAcI6AiChwApAQAAAA==.Akimbo:BAAALAAECgMIBAAAAA==.Akumá:BAAALAADCgMIAgABLAAECgEIAQADAAAAAA==.',Al='Alcapwn:BAAALAAECgYIDAAAAA==.Alexandrix:BAAALAAECgEIAgAAAA==.Alexstrasz:BAAALAADCgEIAQAAAA==.Aliasandre:BAABLAAECoEZAAMFAAcISREzOgC3AQAFAAcISREzOgC3AQAGAAQINwtpHwC0AAAAAA==.Altaír:BAAALAADCgUIBQAAAA==.',Am='Amazon:BAABLAAECoEfAAIHAAgIbR+uDwDRAgAHAAgIbR+uDwDRAgAAAA==.Amiclya:BAAALAADCgcIDQAAAA==.Amunteb:BAAALAADCgEIAgAAAA==.',An='Andrina:BAAALAADCggICQAAAA==.Angelkrissy:BAAALAADCgcIBwAAAA==.Animia:BAABLAAECoEdAAIFAAcIUxPENgDJAQAFAAcIUxPENgDJAQAAAA==.Ankordia:BAABLAAECoEVAAIBAAcIRgz1oQD/AAABAAcIRgz1oQD/AAAAAA==.Anktiss:BAAALAADCggICQABLAABCgMIAwADAAAAAQ==.Anthrina:BAAALAADCggICQAAAA==.',Ar='Arael:BAAALAADCggICAAAAA==.Arannis:BAAALAAECgYIEgAAAA==.Archimidas:BAABLAAECoEXAAIIAAgIsBSeHwD6AQAIAAgIsBSeHwD6AQAAAA==.Arkany:BAAALAAECggICAAAAA==.Arminu:BAABLAAECoEkAAMJAAgIfSIOGgDtAgAJAAgIfSIOGgDtAgAKAAEIthCtPgA1AAAAAA==.Arrmageddon:BAABLAAECoEXAAMLAAYI2g0wPABaAQALAAYIXQwwPABaAQAMAAYIXQlWkgAVAQABLAAECgcIGAANACwGAA==.Aryjana:BAABLAAECoEdAAIBAAcIXhiHSADbAQABAAcIXhiHSADbAQAAAA==.',As='Ascê:BAAALAADCgYIBgAAAA==.Asimâ:BAAALAAECgYIDQAAAA==.Askandra:BAAALAAECgEIAQAAAA==.Assúnga:BAAALAAECggIEwAAAA==.Astheria:BAAALAAECgEIAgAAAA==.Astics:BAABLAAECoEVAAIGAAcIKiGEBgAtAgAGAAcIKiGEBgAtAgAAAA==.Astrid:BAAALAADCgQIBAAAAA==.',At='Atilla:BAAALAAECgIIAgAAAA==.Atom:BAABLAAECoEYAAICAAcIchgIggC2AQACAAcIchgIggC2AQAAAA==.',Au='Audacity:BAAALAAECgIIAwAAAA==.',Av='Avoca:BAAALAAECggICAAAAA==.',Ay='Ayaya:BAAALAADCggICAABLAAECggIFgAOAAEQAA==.',Az='Azguhl:BAABLAAECoEgAAIJAAgI7iIgEAAhAwAJAAgI7iIgEAAhAwAAAA==.',Ba='Balôm:BAAALAADCgUIBgAAAA==.Barragegaga:BAAALAAECgUIBwAAAA==.Bartholde:BAABLAAECoEZAAMMAAYIEQ1dfwBIAQAMAAYIEQ1dfwBIAQAPAAMI/QiPJACmAAAAAA==.Basarâ:BAAALAADCgYICAAAAA==.',Be='Bellamara:BAAALAAECgUIEAAAAA==.Belládona:BAAALAAECgMIAwAAAA==.Beogar:BAAALAADCgIIAgAAAA==.',Bi='Bigbäm:BAAALAADCggICAAAAA==.Bigwhitecow:BAAALAAECgUIBQAAAA==.',Bl='Blinx:BAAALAAECgYIDAABLAAECggIJAAJAH0iAA==.Blitzy:BAAALAAECggICAAAAA==.Bluefrost:BAAALAADCggICAAAAA==.',Bo='Bowdh:BAABLAAECoEcAAIQAAcIAB+nNgBcAgAQAAcIAB+nNgBcAgAAAA==.',Br='Bramnir:BAAALAAECgIIAgAAAA==.Brogtar:BAABLAAECoEgAAINAAgIaBynBgCOAgANAAgIaBynBgCOAgAAAA==.Brosyoshiret:BAAALAAECgcIDgAAAA==.Brudergünter:BAAALAADCggICAAAAA==.Brummbaer:BAAALAAECgEIAQAAAA==.Brummbár:BAAALAAECgEIAQAAAA==.Brunhîld:BAABLAAECoEiAAIJAAgI2xo1WQATAgAJAAgI2xo1WQATAgAAAA==.',Bu='Buginswahili:BAAALAAECgMIAwAAAA==.Bungi:BAAALAAECgYICQABLAAECggIGAAIAF4iAA==.Burni:BAAALAADCgcICAAAAA==.Bursa:BAAALAAECggIDAAAAA==.',['Bä']='Bärbauch:BAAALAADCgUIBAAAAA==.Bärsy:BAAALAAECgEIAgAAAA==.',Ca='Calliaras:BAAALAAECgUICwAAAA==.Camtolorprst:BAABLAAECoEVAAIRAAcI/R/6GQCEAgARAAcI/R/6GQCEAgAAAA==.Camtolorwar:BAABLAAECoEVAAISAAcI2iTVFQBWAgASAAcI2iTVFQBWAgABLAAECgcIFQARAP0fAA==.Carstnstahl:BAABLAAECoEmAAITAAgIKSOaBgATAwATAAgIKSOaBgATAwAAAA==.Cassiusdio:BAAALAAECgIIAgAAAA==.Cavus:BAAALAAECgYIEgAAAA==.',Ce='Celebi:BAAALAAECgYIDAAAAA==.Celîna:BAAALAAECggICAAAAA==.Cerenia:BAABLAAECoEfAAIRAAcIfh3XIQBQAgARAAcIfh3XIQBQAgAAAA==.',Ch='Chalysa:BAAALAADCggIFgAAAA==.Chaoslicht:BAABLAAECoEXAAMUAAcIXhiAIADgAQAUAAcIXhiAIADgAQACAAYI6QsAAAAAAAAAAA==.Chapchap:BAABLAAECoEWAAIHAAcIUBzyIAAvAgAHAAcIUBzyIAAvAgAAAA==.Charizard:BAABLAAECoEgAAIVAAgInCXNBwBJAwAVAAgInCXNBwBJAwAAAA==.Cheralie:BAABLAAECoEjAAIUAAgI9iFOBAANAwAUAAgI9iFOBAANAwAAAA==.Cherrydu:BAAALAAECgYIEgAAAA==.Chéos:BAAALAAECgYIEgAAAA==.',Ci='Cidrè:BAAALAAECgQICAAAAA==.Cinnamonroll:BAABLAAECoEVAAMTAAYI1hVLJwCUAQATAAYI1hVLJwCUAQAWAAEIywptRAAeAAAAAA==.Cirano:BAAALAADCgcIEAAAAA==.',Co='Coldres:BAAALAAECgUICgAAAA==.Content:BAAALAAECgYIBgAAAA==.Corneria:BAAALAAECgEIAgAAAA==.Cornil:BAAALAADCggIDgAAAA==.',Cr='Croni:BAAALAAFFAEIAQAAAA==.Crêpes:BAABLAAECoEUAAQXAAYIzxDRDQBiAQAXAAYISQ7RDQBiAQAYAAUIow1qQgAsAQAZAAEItgaCRgAqAAAAAA==.',Cu='Curran:BAAALAAECgUICAABLAAECgcIIAAMADsZAA==.',Da='Dalarok:BAAALAAECggIBgAAAA==.Dalibor:BAAALAADCgcIBwAAAA==.Dancewithme:BAAALAAECgcIBwAAAA==.Daphnee:BAAALAADCgUIBgAAAA==.Dayli:BAAALAADCgYICgAAAA==.',De='Deadlysitt:BAAALAADCgYIBgAAAA==.Deathelester:BAABLAAECoEUAAIJAAYIggdU4AAdAQAJAAYIggdU4AAdAQAAAA==.Delacrema:BAAALAADCgQIBAAAAA==.Demondock:BAABLAAECoEVAAIQAAcI1BYxXADoAQAQAAcI1BYxXADoAQABLAAFFAIIBgAaAMQdAA==.Denschaaren:BAAALAADCgcIDAAAAA==.Dergehörtmir:BAABLAAECoEWAAMbAAcI1A1wNwDYAAAbAAcI1A1wNwDYAAAQAAMI+Qae9gCCAAABLAAECgcIJQAWAFcTAA==.Derketzer:BAABLAAECoEiAAMcAAgISB2rKgByAgAcAAgISB2rKgByAgAdAAEIMwJIvwAYAAAAAA==.Desalmado:BAABLAAECoEoAAIRAAgIIhsOGwB9AgARAAgIIhsOGwB9AgAAAA==.Devildragon:BAAALAAECgEIAQAAAA==.',Di='Dixii:BAAALAADCgYICgAAAA==.',Dk='Dkquéén:BAAALAADCggIEwABLAAECgMIAwADAAAAAA==.',Do='Dommaker:BAAALAAECgYIDQAAAA==.Dommune:BAAALAADCggIIQAAAA==.Donalexandro:BAAALAAECgUIDwAAAA==.Donarwulf:BAACLAAFFIEUAAIBAAUI1CAtBADHAQABAAUI1CAtBADHAQAsAAQKgSMAAwEACAjVJFYEADkDAAEACAjVJFYEADkDAB4AAQhWEdWlAEUAAAAA.Donluis:BAAALAAECgEIAQABLAAECgIIAgADAAAAAA==.Doodleez:BAABLAAECoEWAAIYAAgILBnhFQBaAgAYAAgILBnhFQBaAgAAAA==.Doppelpeter:BAAALAAECgYIDQAAAA==.',Dr='Draconídas:BAAALAADCgYIBgABLAAECgMIAwADAAAAAA==.Dragonar:BAACLAAFFIEKAAIBAAIIMxfFKACMAAABAAIIMxfFKACMAAAsAAQKgS0AAwEACAiLFIBMAM8BAAEACAiLFIBMAM8BAB4ABwjeDntPAJ4BAAAA.Dreistin:BAAALAAECgQIBAAAAA==.',Du='Duvessa:BAAALAAECgcIEAAAAA==.',['Dâ']='Dâo:BAAALAADCgYIBQAAAA==.',['Dä']='Dämonibar:BAAALAADCgcIBwABLAAECgcIHwAVALAYAA==.',['Dö']='Dönos:BAABLAAECoEnAAMPAAgI+iECBQCBAgAMAAgIph03HgC1AgAPAAcIeR4CBQCBAgAAAA==.Dönvoker:BAAALAAECgUICQABLAAECggIJwAPAPohAA==.',Eb='Ebonmage:BAABLAAECoEWAAIVAAgIkxP8UwDoAQAVAAgIkxP8UwDoAQAAAA==.',Ed='Edgyreggie:BAAALAADCggICAABLAAECgcIHQAfAKUkAA==.Edwinvansieg:BAAALAADCggICAAAAA==.',Ee='Eelowynn:BAAALAADCggIDQABLAAECgEIAgADAAAAAA==.',Ei='Eis:BAABLAAECoEWAAMOAAgIARDdHgB1AQAOAAgIfwvdHgB1AQAaAAIIKh/QIQCpAAAAAA==.Eismar:BAAALAAECgYIDgAAAA==.',El='Elenôre:BAAALAAECggIDQAAAA==.Elle:BAAALAADCgcIBwAAAA==.Ellonidas:BAAALAAECgYICgAAAA==.Elmareo:BAAALAADCgMIAwAAAA==.Elsurioth:BAAALAADCgEIAQAAAA==.Elsé:BAAALAAECgIIAgAAAA==.Eluneu:BAAALAADCggIBgABLAAECgYIDQADAAAAAA==.Eluria:BAAALAADCggIBQAAAA==.Elwin:BAAALAADCgcICAABLAAECgcIHwAVALAYAA==.Elêktra:BAAALAADCggIHgABLAAECgcIFAAcAAATAA==.',Em='Emerie:BAAALAADCgcIBwAAAA==.Emmà:BAABLAAECoEYAAMGAAcIjxxdBwAcAgAGAAYISx9dBwAcAgARAAMI5wsujACQAAAAAA==.',En='Endorì:BAAALAAECgYIEwAAAA==.Enthal:BAAALAAECgYIDwAAAA==.',Ep='Epato:BAAALAAECgIIAgAAAA==.',Es='Escannor:BAABLAAECoEUAAMUAAYIrhJlNABkAQAUAAYIrhJlNABkAQACAAEI+QTdQAEzAAAAAA==.',Et='Ettersberg:BAABLAAECoEUAAQLAAgICRLWLwCPAQALAAgIxBHWLwCPAQAPAAEIHQUlOwA6AAAMAAIIDgEW5QAcAAAAAA==.',Eu='Eulenfeder:BAAALAAECggICAAAAA==.',Ev='Everlasting:BAABLAAECoEeAAIFAAcIShH1OAC9AQAFAAcIShH1OAC9AQAAAA==.',Ex='Exesor:BAABLAAECoEUAAICAAYI3yOINgBxAgACAAYI3yOINgBxAgAAAA==.Exodal:BAAALAADCggIFgAAAA==.',Fa='Fandrissa:BAABLAAECoEYAAIbAAcItBcIFwDfAQAbAAcItBcIFwDfAQAAAA==.Faver:BAAALAAECgYIDQAAAA==.',Fe='Feno:BAABLAAFFIEJAAIBAAIIpiHwFgDDAAABAAIIpiHwFgDDAAAAAA==.Fexxór:BAAALAAECgIIAgAAAA==.',Fi='Fiandala:BAAALAAECgEIAgAAAA==.Fibruh:BAAALAAECgcIBwAAAA==.Finla:BAAALAADCgMIAwAAAA==.',Fl='Flathead:BAABLAAECoEWAAIBAAcIxxqmNgAWAgABAAcIxxqmNgAWAgAAAA==.Flednanders:BAAALAADCgcICAAAAA==.Floxus:BAAALAAECggIEwABLAAFFAMIDQAJAG0eAA==.Fluu:BAAALAAECgcIEAAAAA==.Flying:BAAALAAECgcIBwAAAA==.',Fo='Fogerogue:BAABLAAECoEeAAIYAAgIrR66CgDWAgAYAAgIrR66CgDWAgAAAA==.Forte:BAAALAAECgIIAgAAAA==.Foxîe:BAAALAADCgcIBwAAAA==.',Fr='Franzí:BAAALAAECgMIAwABLAAECggIJwAgALwhAA==.Friuda:BAAALAAECggIEAAAAA==.Fruxilia:BAAALAAECgcIEwAAAA==.Fränzis:BAAALAADCggICAAAAA==.',Fu='Fuji:BAAALAADCgYIBgAAAA==.Funi:BAAALAADCggIEAAAAA==.',['Fì']='Fìeldy:BAAALAAECgEIAgAAAA==.',['Fí']='Fíesel:BAAALAADCggICAAAAA==.',['Fô']='Fôo:BAAALAAECgYIDQAAAA==.',Ga='Gaaraa:BAAALAAECgYICwABLAAECgYIDgADAAAAAA==.Garoar:BAAALAAECgYICwAAAA==.Gaster:BAAALAAECgUIBgAAAA==.Gavril:BAAALAADCgcIFQAAAA==.',Ge='Gena:BAABLAAECoEbAAIIAAcIfBmqGgAgAgAIAAcIfBmqGgAgAgAAAA==.Geonidas:BAAALAAECgUICQAAAA==.',Gl='Glee:BAAALAADCgcICQAAAA==.Glücksfee:BAAALAAECgYICgAAAA==.',Gn='Gnomsieg:BAAALAADCgQIBAAAAA==.',Go='Gorak:BAAALAAECgYIEQAAAA==.Gotfrit:BAAALAADCgcIBwAAAA==.',Gr='Grandeeney:BAAALAAECgIIBgAAAA==.Grangorian:BAABLAAECoEYAAIQAAcIdh/+LwB3AgAQAAcIdh/+LwB3AgAAAA==.Grantler:BAAALAAECgcIEAAAAA==.Grimbold:BAAALAAECgEIAQAAAA==.Grimbolin:BAAALAADCggIDwABLAAECgEIAgADAAAAAA==.Grimnirsson:BAAALAAECgYIEAAAAA==.Grîmmjow:BAAALAAECgUIBQAAAA==.',['Gô']='Gôttesbote:BAAALAAECgIIAgABLAAFFAQIEgAMAKMgAA==.',Ha='Habnîx:BAAALAADCgIIAgAAAA==.Hammabamma:BAABLAAECoEaAAICAAYIWyKGUwAaAgACAAYIWyKGUwAaAgAAAA==.Harzhexe:BAAALAAECggICAAAAA==.Hastur:BAAALAADCgUIBQAAAA==.Hausmeister:BAAALAADCggIEAAAAA==.',He='Heerah:BAAALAAECgYIBgAAAA==.Heheyo:BAAALAAECgIIAgAAAA==.Heilkraft:BAABLAAECoEVAAIRAAYITQUkdwDsAAARAAYITQUkdwDsAAAAAA==.Hekto:BAAALAADCgcIDAAAAA==.Helgarr:BAAALAADCgUIBQAAAA==.Herberthahn:BAAALAADCgYIBgAAAA==.Hextul:BAAALAAECgYIEQABLAAECgcIEAADAAAAAA==.Hexzul:BAAALAAECgYIBgAAAA==.',Hi='Hitorder:BAAALAAECgIIAwAAAA==.',Ho='Hochofen:BAAALAADCgcIEwAAAA==.Holysun:BAAALAADCggICgABLAADCggIEAADAAAAAA==.Honigblüte:BAAALAADCggICAAAAA==.Hopp:BAABLAAECoEUAAIQAAYIMx5PTAATAgAQAAYIMx5PTAATAgAAAA==.Horace:BAAALAAECgUIDgAAAA==.Horik:BAAALAADCgcICAAAAA==.Hossa:BAAALAADCggIFgAAAA==.',Hu='Hunox:BAAALAAECggIDgAAAA==.Hunterhunter:BAAALAAECgMIAwABLAAFFAIIBQASABwKAA==.',['Hà']='Hàmmberge:BAAALAAECggIEgAAAA==.',['Hî']='Hînatá:BAAALAAECgYIDgAAAA==.',['Hò']='Hòórny:BAAALAAECgIIAgAAAA==.',Ib='Ibberzwerch:BAAALAADCggICAABLAAECgEIAQADAAAAAA==.',Ic='Ichsehnichts:BAAALAAECgYIBgAAAA==.',Ii='Iida:BAABLAAECoEYAAISAAcIZhk/HgALAgASAAcIZhk/HgALAgABLAAECgcIHAAXALEYAA==.Iiuna:BAAALAAECgEIAgAAAA==.',Il='Illeniel:BAAALAADCgYIBgAAAA==.Ilures:BAAALAADCgUIBQAAAA==.',Im='Imhøtep:BAAALAADCgEIAwAAAA==.',In='Inola:BAAALAAECgUIDgAAAA==.Inori:BAAALAADCggIEAAAAA==.',Ir='Iranazal:BAABLAAECoEnAAIWAAgIGRf0EAAgAgAWAAgIGRf0EAAgAgAAAA==.Irilitha:BAAALAADCgcIBgAAAA==.',Is='Isirany:BAABLAAECoEUAAIRAAYIeAunZgAiAQARAAYIeAunZgAiAQAAAA==.',Ja='Jaebum:BAAALAAECgMIAwAAAA==.Jallyn:BAAALAAECgYIBgABLAAECggIJAAJAH0iAA==.Jallyna:BAAALAAECgYIDAABLAAECggIJAAJAH0iAA==.Jammie:BAAALAAECgEIAQAAAA==.Janos:BAAALAADCggICAAAAA==.Jardyna:BAAALAAECgYICAABLAAECggIJAAJAH0iAA==.',Je='Jerîcho:BAAALAADCgcIBwAAAA==.Jessaj:BAAALAAECgIIAgABLAAECggIFwARAEIFAA==.Jessdemon:BAAALAADCgcIBwAAAA==.Jessyschami:BAAALAAECgcIEQABLAAECggIFwARAEIFAA==.',Ji='Jigdral:BAAALAAECgcIBwABLAAECggIFAAhAAkWAA==.Jimcuningham:BAAALAAECgYIEQAAAA==.Jimmieo:BAAALAAECggIAQAAAA==.Jinjie:BAAALAAECgcIEgAAAA==.Jinxed:BAAALAAECgYIBQAAAA==.',Ju='Julès:BAAALAADCggIIAAAAA==.Juniór:BAAALAAECgEIAQAAAA==.',Ka='Kaelen:BAAALAADCgcIBwAAAA==.Kaiza:BAAALAADCgcICAAAAA==.Kalistara:BAAALAAECggIDQABLAAFFAMIDQAJAG0eAA==.Karateka:BAABLAAECoElAAMWAAcIVxOrHQB7AQAWAAcIVxOrHQB7AQATAAYIwQSRRAC/AAAAAA==.Karry:BAAALAADCggIEAAAAA==.Kasei:BAABLAAECoEdAAIiAAcIFRDLEACnAQAiAAcIFRDLEACnAQAAAA==.Kawausoness:BAAALAADCgEIAQAAAA==.',Ke='Keshya:BAAALAADCgUIBQAAAA==.Keylie:BAAALAAECgUIBgAAAA==.',Ki='Kianaa:BAABLAAECoEeAAIhAAgIHCWUBgAdAwAhAAgIHCWUBgAdAwAAAA==.Kiddycát:BAAALAAECgYIDwAAAA==.Kiddycât:BAAALAAECgMIBQABLAAECgYIDwADAAAAAA==.Killkit:BAAALAADCggIIAAAAA==.Killí:BAAALAADCggIEQABLAAECgMIAwADAAAAAA==.Kiritô:BAAALAADCgcIBwAAAA==.Kiví:BAAALAADCggIEAAAAA==.Kiwí:BAAALAAECgYIBwABLAAECgYIDQADAAAAAA==.',Kn='Knoppers:BAABLAAECoEdAAIMAAgIphETRAD7AQAMAAgIphETRAD7AQABLAAFFAIICQAUAB0PAA==.',Ko='Kohi:BAAALAADCggICAABLAAECggILwAjAHUeAA==.Kortus:BAAALAADCgcIBwAAAA==.',Kr='Krawet:BAAALAADCgYICAAAAA==.Kristina:BAAALAADCgMIAgAAAA==.Kroosi:BAAALAADCgUIBQABLAAECgcIEAADAAAAAA==.Kryfi:BAABLAAECoEhAAMeAAcIOxrdOQD1AQAeAAcIOxrdOQD1AQABAAQIfAF+/QBOAAAAAA==.',Ku='Kumifjiel:BAAALAAECgMIAwAAAA==.Kuqiidruid:BAAALAAECgYIBgAAAA==.',Ky='Kyarà:BAAALAAECgEIAQAAAA==.',['Kô']='Kônzuela:BAABLAAECoEWAAIBAAcI5RNjXQChAQABAAcI5RNjXQChAQAAAA==.',La='Laoshi:BAAALAAECgYIDAAAAA==.Laufwienix:BAAALAADCggIEAAAAA==.Laurelin:BAAALAAECgUIBwAAAA==.',Le='Lemora:BAABLAAECoEYAAIFAAgIohXcLgD1AQAFAAgIohXcLgD1AQAAAA==.Lessaria:BAACLAAFFIENAAIJAAMIbR6NFwD1AAAJAAMIbR6NFwD1AAAsAAQKgSMAAgkACAjGJDgQACADAAkACAjGJDgQACADAAAA.Letonic:BAAALAADCgYICQAAAA==.Letî:BAAALAAECgcIEQAAAA==.Levitar:BAAALAAECgMIBgAAAA==.Levitas:BAAALAAECgIIAgAAAA==.',Li='Lichtkiller:BAACLAAFFIEVAAIJAAYIKiMrAwA7AgAJAAYIKiMrAwA7AgAsAAQKgSEAAgkACAjpJDgVAAYDAAkACAjpJDgVAAYDAAAA.Limpy:BAAALAAECgEIAgAAAA==.Linella:BAAALAADCgUIBQAAAA==.Linorana:BAAALAADCggIBAAAAA==.Liposa:BAACLAAFFIEFAAMFAAII4BG6GACQAAAFAAII4BG6GACQAAARAAEIQgAsOAAfAAAsAAQKgSsAAgUACAiTINgNAPUCAAUACAiTINgNAPUCAAAA.Liriel:BAAALAAECgYIDwAAAA==.Livitana:BAABLAAECoEZAAIIAAYIgCDgHQAGAgAIAAYIgCDgHQAGAgAAAA==.',Lo='Lockgob:BAAALAAECgYIBgAAAA==.Looth:BAAALAADCgQICAAAAA==.',Lu='Luntilette:BAAALAADCgEIAQAAAA==.Luzyfer:BAAALAADCggICAAAAA==.',['Lå']='Lågerthå:BAAALAADCgYIBgAAAA==.',['Lî']='Lîsanna:BAAALAAECgMIAwABLAAECggIEgADAAAAAA==.',['Lù']='Lùcký:BAAALAAECgYIDQAAAA==.',Ma='Macchiato:BAAALAADCggICAAAAA==.Mafi:BAAALAAECgUICQAAAA==.Mageblast:BAABLAAECoEYAAMIAAgIXiJpDQCrAgAVAAgIOh3vHQDHAgAIAAcIMCNpDQCrAgAAAA==.Magequit:BAAALAAECgQIBAAAAA==.Malgoras:BAAALAAECgUIBwAAAA==.Malinaperle:BAAALAAECgcIDAAAAA==.Mapleskiller:BAAALAADCggICAAAAQ==.Maradus:BAABLAAECoEUAAIaAAYIIw9gFwAnAQAaAAYIIw9gFwAnAQAAAA==.Margistrat:BAAALAAECggICAAAAA==.Maríka:BAAALAAFFAIIAgABLAAFFAMIDQAJAG0eAA==.Mayan:BAAALAADCggIFQAAAA==.Maylana:BAABLAAECoEkAAIcAAcImCEjNABLAgAcAAcImCEjNABLAgAAAA==.',Me='Medizinbräu:BAABLAAECoEeAAIgAAgIpRb2EAA0AgAgAAgIpRb2EAA0AgAAAA==.Meloenchên:BAAALAAECgIIAgAAAA==.Merilyn:BAABLAAECoEYAAIIAAcIlQiuQABHAQAIAAcIlQiuQABHAQAAAA==.Merryfinger:BAAALAAECgEIAgAAAA==.',Mi='Milca:BAAALAAECgEIAQAAAA==.Minalar:BAAALAAECgQIBAAAAA==.Minin:BAAALAAECggIEgAAAA==.Minuschka:BAAALAAECggICAAAAA==.Mirí:BAAALAAECgEIAQAAAA==.Misselestra:BAABLAAECoEUAAIcAAYIPAvSqwAoAQAcAAYIPAvSqwAoAQAAAA==.Misá:BAAALAADCggIEAAAAA==.Mity:BAAALAAECgEIAQAAAA==.',Mo='Moadib:BAABLAAECoEVAAIUAAcIdAkTPAA4AQAUAAcIdAkTPAA4AQAAAA==.Monkihonk:BAAALAADCgUIBQAAAA==.Moonangelina:BAABLAAECoEcAAMHAAcI/xYCLwDYAQAHAAcI/xYCLwDYAQAjAAYIfhMxqgBaAAABLAAECggIJwAgALwhAA==.',Mu='Mummyheal:BAABLAAECoEXAAIRAAgIQgUqWwBIAQARAAgIQgUqWwBIAQAAAA==.Munin:BAAALAAECgMIBAAAAA==.',My='Mykris:BAAALAADCggICwAAAA==.',['Mà']='Màl:BAABLAAECoEWAAIgAAcI2BBnHwB/AQAgAAcI2BBnHwB/AQAAAA==.',['Má']='Márs:BAABLAAECoEcAAILAAcIFiFvCgClAgALAAcIFiFvCgClAgAAAA==.',['Më']='Mërlin:BAAALAADCgEIAQAAAA==.',['Mö']='Mönchichì:BAAALAAECgYICwAAAA==.Mörenmonarch:BAAALAADCggIDAAAAA==.',['Mû']='Mûrdock:BAACLAAFFIEGAAIaAAIIxB2XAgCuAAAaAAIIxB2XAgCuAAAsAAQKgS0AAhoACAjsH3oDAOACABoACAjsH3oDAOACAAAA.',Na='Nahîmana:BAAALAADCgcIDwAAAA==.Naldric:BAAALAADCggICAAAAA==.Nassm:BAABLAAECoEgAAIVAAgIwhlNNQBYAgAVAAgIwhlNNQBYAgAAAA==.Natürlích:BAAALAADCggIDgAAAA==.Naytiri:BAAALAAECgIIAgAAAA==.',Ne='Nebelteiler:BAABLAAECoEnAAIOAAgI7xgDDQBaAgAOAAgI7xgDDQBaAgAAAA==.Nemeria:BAAALAADCgEIAQAAAA==.Nesa:BAAALAAECgcIDgAAAA==.',Nh='Nhym:BAABLAAECoEsAAMeAAgI6RwFHwCJAgAeAAgI6RwFHwCJAgABAAcI7hSjXwCaAQAAAA==.',Ni='Nicsenpala:BAAALAAECgUIBwABLAAECgcIJQAWAFcTAA==.Nightmâre:BAAALAADCgUIBQAAAA==.Niliá:BAAALAADCgYIBwABLAAECgcICwADAAAAAA==.Nivis:BAAALAADCgcIBwAAAA==.',No='Noyako:BAAALAAECgcIBwABLAAECggIHAAFAHceAA==.',Nr='Nrazul:BAAALAADCggICAABLAAECgYIBgADAAAAAA==.',Nu='Nullnullsix:BAABLAAECoEbAAILAAcI9hhCHAD7AQALAAcI9hhCHAD7AQAAAA==.Nurtok:BAAALAADCggIDwAAAA==.',Ny='Nyhmz:BAAALAAECggIEwAAAA==.',['Nâ']='Nânina:BAAALAADCgYIBgAAAA==.',['Nì']='Nìniel:BAABLAAECoEUAAIkAAgIQQhCCgBwAQAkAAgIQQhCCgBwAQAAAA==.',Ok='Okessa:BAAALAADCggICAABLAAECggIHAAFAHceAA==.',Ol='Ol:BAAALAAECgMIAwAAAA==.Oldbear:BAABLAAECoEZAAMjAAcIWheiNwDNAQAjAAcIWheiNwDNAQAHAAQIxQ0AAAAAAAAAAA==.Ollibar:BAABLAAECoEfAAIVAAcIsBiaSwAEAgAVAAcIsBiaSwAEAgAAAA==.',On='Onioc:BAAALAAECgYIBgAAAA==.',Or='Orcnas:BAAALAAECggICAAAAA==.Origamikillè:BAAALAADCgcICQAAAA==.Orimonk:BAAALAAECgUIDQAAAA==.Oripriest:BAAALAADCgYIBgAAAA==.Orphelié:BAAALAADCggIEAAAAA==.',Os='Osîrîs:BAAALAAECgQIDAAAAA==.',Ot='Otis:BAAALAAECggICAAAAA==.',Pa='Pacoline:BAAALAAECgMIBwAAAA==.Padee:BAAALAAECggICAAAAA==.Padèé:BAAALAAECggICwAAAA==.Palarina:BAAALAAECgUIBQAAAA==.Pandawaninho:BAAALAADCgIIAgAAAA==.Panícz:BAAALAADCgMIAwAAAA==.Papawine:BAAALAAECgUIBwAAAA==.Paulix:BAAALAAECgEIAQAAAA==.Paxo:BAAALAAECggIEwABLAAFFAEIAQADAAAAAA==.',Pe='Peppajam:BAAALAADCggIFgAAAA==.',Ph='Phan:BAABLAAECoEXAAIJAAYIqyJJUgAkAgAJAAYIqyJJUgAkAgAAAA==.Phanne:BAAALAADCggICAAAAA==.Pheby:BAABLAAECoEXAAIHAAYI9wIEcgCdAAAHAAYI9wIEcgCdAAAAAA==.Phönìx:BAAALAADCggIBwABLAAECgYIDwADAAAAAA==.',Pi='Piko:BAAALAADCgUIBAAAAA==.',Pr='Prisa:BAAALAADCggICAABLAAECgUIDgADAAAAAA==.Protrian:BAAALAADCgYIBQAAAA==.Prunax:BAAALAAECgYIBgABLAAECggIFAAhAAkWAA==.',Py='Pyrdacor:BAAALAAECgEIAQAAAA==.',['Pâ']='Pâinkîller:BAAALAAECgYICAAAAA==.',['Pé']='Péradon:BAAALAAECgIIAgAAAA==.',['Pö']='Pöbelknirps:BAAALAAECgcIEQABLAAFFAIIBQASABwKAA==.Pöbelknírps:BAAALAAECgYIBwABLAAFFAIIBQASABwKAA==.',['Pü']='Pübschen:BAABLAAECoEaAAIRAAYILBthOgDNAQARAAYILBthOgDNAQAAAA==.',Qu='Quendolin:BAAALAADCgYIBQAAAA==.Quixxan:BAAALAAECgYICAAAAA==.',Ra='Raekor:BAAALAADCgYIDAAAAA==.Raffos:BAAALAAECgIIAgAAAA==.Rall:BAAALAADCggICAAAAA==.Raran:BAAALAAECgEIAgAAAA==.Raris:BAAALAADCgYIDAAAAA==.Raseth:BAAALAADCgUIBQAAAA==.',Re='Regentanz:BAAALAAECgcIDQABLAAECgcIFgABAMcaAA==.Rejizha:BAAALAADCgcIBwAAAA==.Remliel:BAABLAAECoEZAAMiAAcIhxv5CQAkAgAiAAcIPxn5CQAkAgAEAAcI1xinOQAcAgAAAA==.Renatesi:BAAALAADCggIFgAAAA==.Rexôna:BAAALAADCggIGwAAAA==.',Rh='Rhogarr:BAAALAAECggIDQAAAA==.',Ri='Riora:BAAALAADCggIFgABLAAECgMIAwADAAAAAA==.Riva:BAABLAAECoEdAAIbAAcIfhdeGQDFAQAbAAcIfhdeGQDFAQAAAA==.',Ro='Rodira:BAAALAADCgIIAgAAAA==.Rolfe:BAAALAAECgYIBgAAAA==.Rotfuchss:BAAALAADCgcIBwAAAA==.Roxxani:BAAALAADCgYIBgAAAA==.Roxxanii:BAAALAAECgMIAwAAAA==.Roxxanía:BAAALAADCgYIBgAAAA==.',Ru='Rudolph:BAAALAADCggIDgAAAA==.Rugar:BAAALAAECgMIAwAAAA==.',['Ré']='Rébôn:BAAALAADCgYIBgAAAA==.',Sa='Saffira:BAAALAADCgMIAwAAAA==.Safran:BAAALAADCggIBQAAAA==.Sagittarius:BAAALAAECgYIEQAAAA==.Sagittaríus:BAAALAADCgIIAgAAAA==.Sahnetörtle:BAAALAAFFAIIAgAAAA==.Saj:BAAALAADCggIHgABLAAECgEIAgADAAAAAA==.Sakurâ:BAAALAAECgEIAgAAAA==.Salomil:BAAALAAECgEIAgAAAA==.Salvadore:BAAALAAECgEIAQAAAA==.Samentorana:BAAALAADCggIHgAAAA==.Sandtieger:BAABLAAECoEVAAIfAAcI2gSmKgBQAQAfAAcI2gSmKgBQAQAAAA==.Santáfee:BAAALAADCgEIAQAAAA==.Sarri:BAAALAADCggIDAABLAAECgYIDQADAAAAAA==.Sarì:BAAALAAECgcICwAAAA==.',Sc='Scherkulix:BAAALAADCgcIDQAAAA==.Schnugíe:BAAALAAECgEIAQAAAA==.Schort:BAAALAADCgQIBAAAAA==.',Se='Sephirothx:BAAALAAECgYIEAAAAA==.Sequana:BAABLAAECoEYAAMNAAcILAZsFwBGAQANAAcILAZsFwBGAQABAAYIZQ6FlwAUAQAAAA==.Seraxinus:BAAALAADCggICAAAAA==.Serayah:BAABLAAECoEVAAIIAAcIKhRFIwDhAQAIAAcIKhRFIwDhAQAAAA==.Sereana:BAAALAADCgQIBAAAAA==.',Sh='Shadewitch:BAAALAADCggIDwAAAA==.Shahal:BAAALAADCgcIDQAAAA==.Shalai:BAAALAADCgQIBAABLAAFFAIICQABAKYhAA==.Shamanzone:BAAALAADCggIEAAAAA==.Shanterian:BAAALAAECgYIDQABLAAECggIKAAQANIgAA==.Sherry:BAABLAAECoEcAAIlAAgIOhVpBgBBAgAlAAgIOhVpBgBBAgAAAA==.Shirogane:BAAALAAECgcIDwAAAA==.Shiruan:BAAALAAECgYIDgAAAA==.Shizury:BAAALAAECgIIAgAAAA==.',Si='Silliana:BAABLAAECoEbAAIdAAcIng/2UQBVAQAdAAcIng/2UQBVAQAAAA==.Silverj:BAAALAADCgEIAQABLAAECgcICwADAAAAAA==.Silverlietqt:BAAALAAECggIBAAAAA==.Silvermuh:BAAALAAECgcICwAAAA==.Sindrilian:BAAALAAECgEIAgAAAA==.',Sk='Skarin:BAAALAAECgYICwABLAAECggIJgATACkjAA==.Skarla:BAAALAADCggIDgAAAA==.Skâlli:BAAALAADCgUIBQAAAA==.',Sl='Sleepydk:BAAALAAECgYIDgABLAAFFAIIBQAcACYZAA==.Sleepymage:BAAALAADCggIFQABLAAFFAIIBQAcACYZAA==.Sleepypriest:BAAALAADCggIEAABLAAFFAIIBQAcACYZAA==.Sleika:BAAALAADCgMIAwAAAA==.Sleiker:BAABLAAECoEgAAIMAAcIOxl3PwANAgAMAAcIOxl3PwANAgAAAA==.Sloth:BAAALAAECgMIBgAAAA==.',Sm='Smokymolla:BAAALAAECggICwAAAA==.Smãugs:BAAALAADCgEIAgAAAA==.',Sn='Sniky:BAAALAAECgEIAgAAAA==.',So='Soku:BAABLAAECoEkAAIdAAgIHhT5OQC5AQAdAAgIHhT5OQC5AQAAAA==.Sontina:BAAALAADCgYIBgABLAAECgYIDQADAAAAAA==.Sorax:BAAALAADCgcIDAAAAA==.',Sp='Spezî:BAAALAADCgIIAgAAAA==.Spriti:BAABLAAECoEnAAIBAAgIJxbGNwASAgABAAgIJxbGNwASAgAAAA==.',St='Starbac:BAAALAAECgEIAQAAAA==.Stealtha:BAAALAAECgMIAwAAAA==.Stegi:BAAALAAECgEIAgAAAA==.Sternfeuer:BAABLAAECoElAAIcAAcIoB6eQwAVAgAcAAcIoB6eQwAVAgAAAA==.Stormragé:BAABLAAECoEWAAIQAAgIphRDVAD8AQAQAAgIphRDVAD8AQAAAA==.Sturmhorn:BAAALAADCggICAAAAA==.Støny:BAAALAADCggIEgAAAA==.',Su='Suedtirol:BAAALAAECgYIEQAAAA==.Sulrig:BAAALAAECgcIHwAAAQ==.Sunchi:BAAALAAECgUICAAAAA==.Suranaja:BAABLAAECoEmAAMjAAcICxRPPwCsAQAjAAcICxRPPwCsAQAHAAYIKBWHXgD/AAABLAAECggIFwARAEIFAA==.Surijan:BAABLAAECoEcAAIOAAcIyhueEgACAgAOAAcIyhueEgACAgAAAA==.',Sw='Sweedypala:BAAALAAECgYIDQAAAA==.Swordmän:BAAALAAECgEIAQAAAA==.Swêety:BAAALAAECgUIDAABLAAECggIIgAJANsaAA==.Swìffer:BAAALAAECgQIBAAAAA==.',Sy='Sylar:BAAALAAECgQIBwAAAA==.Syltarius:BAAALAADCggICQAAAA==.Syluri:BAABLAAECoEdAAImAAcIvQ+kKwBnAQAmAAcIvQ+kKwBnAQABLAAECgcIIQAeADsaAA==.Synexiaa:BAAALAAECggICgAAAA==.Syrahna:BAAALAAFFAEIAQAAAA==.Syvarris:BAABLAAECoEdAAMLAAcIgybRAwAgAwALAAcIgybRAwAgAwAMAAUIMyRMQgABAgAAAA==.',['Sá']='Sálázar:BAAALAAECgYIDwABLAAECggIFAAhAAkWAA==.Sálêîkô:BAAALAADCgYICgAAAA==.',Ta='Taka:BAAALAADCgIIAgABLAADCgQIBAADAAAAAA==.Tandri:BAAALAADCgYICgAAAA==.Tapsî:BAABLAAECoEnAAIgAAgIvCF5BAANAwAgAAgIvCF5BAANAwAAAA==.Tarantoga:BAAALAAECgQIBwAAAA==.Tardurin:BAABLAAECoEdAAIjAAcIPBjWLgD3AQAjAAcIPBjWLgD3AQAAAA==.Tarragona:BAAALAADCggIFAAAAA==.Tatsuya:BAAALAAECgQICQAAAA==.Tauriél:BAAALAADCggICAAAAA==.Taøshi:BAAALAADCgMIAwAAAA==.',Te='Teddybärchen:BAAALAADCgcIBwABLAAECgEIAQADAAAAAA==.Teebaum:BAAALAAECgYIEAAAAA==.Teheros:BAABLAAECoEbAAIEAAgIuhk0KwBgAgAEAAgIuhk0KwBgAgAAAA==.Tekka:BAAALAADCgMIAwAAAA==.Telannie:BAABLAAECoEWAAINAAcIownsFABwAQANAAcIownsFABwAQAAAA==.Tenebrís:BAAALAAECgEIAQAAAA==.Teras:BAAALAADCgcIDgAAAA==.Terenci:BAAALAAECgcICwAAAA==.Testø:BAAALAADCgQIAgAAAA==.',Th='Thabathaia:BAABLAAECoEUAAIMAAYI3BGObQB3AQAMAAYI3BGObQB3AQAAAA==.Thabtalian:BAABLAAECoEUAAImAAYIzgtlPAD6AAAmAAYIzgtlPAD6AAAAAA==.Thainach:BAAALAAFFAIIBAAAAA==.Tharmus:BAAALAAECggICgAAAA==.Tharuel:BAABLAAECoEVAAMMAAcIqhqiTADbAQAMAAcIGRWiTADbAQALAAQIQyCBPABZAQAAAA==.Thcatze:BAAALAAECgYIEgAAAA==.Thorik:BAAALAADCggIJQAAAA==.Thuramandill:BAABLAAECoEcAAIFAAgIdx54FwCaAgAFAAgIdx54FwCaAgAAAA==.Thurok:BAAALAAECgUIBgAAAA==.Thümian:BAAALAAECgEIAgAAAA==.',Ti='Ticklefinger:BAAALAADCggIBgABLAAECgEIAgADAAAAAA==.Ticta:BAABLAAECoEcAAIXAAcIsRgnBwAQAgAXAAcIsRgnBwAQAgAAAA==.Tiibbers:BAAALAADCgcIBwAAAA==.Tiluna:BAAALAAECgIIAgAAAA==.Tindra:BAAALAADCggICAAAAA==.Tiqz:BAABLAAECoEeAAIRAAgIWxfaKAAnAgARAAgIWxfaKAAnAgAAAA==.Tirios:BAAALAAECgIIBQAAAA==.Titanius:BAAALAADCgcICAAAAA==.Tix:BAAALAAECgcIDQAAAA==.',To='Tommî:BAABLAAECoEUAAIcAAcIABNTeACOAQAcAAcIABNTeACOAQAAAA==.Toormund:BAAALAADCggICwAAAA==.Toralor:BAAALAADCggIIgAAAA==.',Tr='Trackstaar:BAAALAAECgYIDwAAAA==.Triggerhappy:BAAALAAECgcIDwAAAA==.Trix:BAAALAADCgYIBgAAAA==.',Tw='Twochar:BAAALAAECgUIEQAAAA==.Twotime:BAABLAAECoEiAAIEAAgIjh2LGwDBAgAEAAgIjh2LGwDBAgAAAA==.',['Tá']='Táy:BAAALAAECgYIEAAAAA==.',['Tê']='Têmuchin:BAAALAADCgEIAgAAAA==.',['Tî']='Tîberion:BAAALAADCgYIBgAAAA==.',['Tô']='Tômmi:BAAALAAECgUIEAABLAAECgcIFAAcAAATAA==.',['Tö']='Törtle:BAAALAAECgYICwABLAAFFAIIAgADAAAAAA==.',['Tø']='Tømmi:BAAALAADCgEIAQABLAAECgcIFAAcAAATAA==.',Ud='Udagaz:BAAALAADCgcIBwABLAAECggIHgALAH0eAA==.',Ul='Ulf:BAABLAAECoEVAAIJAAYIixNnowCDAQAJAAYIixNnowCDAQAAAA==.',Un='Ungenau:BAAALAADCgUIBQAAAA==.',Us='Usranos:BAABLAAECoEUAAMIAAYIRAh1TgAIAQAIAAYIRAh1TgAIAQAVAAIIjwNO4QAxAAAAAA==.',Va='Valgarv:BAABLAAECoEWAAIfAAYIVw/WJQB0AQAfAAYIVw/WJQB0AQAAAA==.Valgos:BAAALAAECgMIAwABLAAECgcIFAAcAAATAA==.Valistra:BAAALAAECgMIAwAAAA==.Vambraél:BAAALAAECgYIBgABLAAECgcICwADAAAAAA==.Vamparadice:BAAALAAECgIIAgAAAA==.',Ve='Velhô:BAAALAAECggICAAAAA==.Venomzug:BAACLAAFFIEKAAIJAAMIYhOdGQDpAAAJAAMIYhOdGQDpAAAsAAQKgSAAAgkACAgnI5chAMkCAAkACAgnI5chAMkCAAAA.Venthor:BAAALAADCggIFAABLAAECgEIAgADAAAAAA==.Venïtarï:BAACLAAFFIEGAAIjAAMI9Qk9EwC4AAAjAAMI9Qk9EwC4AAAsAAQKgRsAAiMACAg0FdE5AMMBACMACAg0FdE5AMMBAAAA.Vexille:BAAALAAECgEIAQAAAA==.',Vi='Victorix:BAAALAADCgEIAgAAAA==.Viin:BAAALAAECgYICwAAAA==.Violence:BAAALAADCgMIBAAAAA==.',Vo='Voidhexer:BAAALAADCgQIBAABLAAECgEIAQADAAAAAA==.Voldidk:BAABLAAECoEsAAIJAAgIECRjCgBAAwAJAAgIECRjCgBAAwAAAA==.Voldisha:BAAALAAECgYICgABLAAECggILAAJABAkAA==.',Vr='Vras:BAAALAAECggIDgAAAA==.',Vu='Vulvarna:BAAALAAECgIIBgAAAA==.',['Vø']='Vøxzia:BAAALAADCgIIAgAAAA==.',Wa='Wallee:BAAALAAECggIDwAAAA==.Wallwerk:BAAALAAECgIIAgAAAA==.Wasgibtsnoch:BAAALAADCgEIAQAAAA==.Wavedesti:BAAALAAECgcIDwAAAA==.',We='Weizen:BAAALAADCgEIAQABLAAECgYIEQADAAAAAA==.Welcon:BAABLAAECoEYAAIOAAYI4hYLGAC+AQAOAAYI4hYLGAC+AQAAAA==.Wellness:BAAALAAECgEIAQAAAA==.',Wi='Wildhoney:BAAALAAECgMIAwABLAAECggIGgARAN0OAA==.Wiwowa:BAAALAAECgUIDgAAAA==.',Wo='Wollowizzard:BAAALAAECgEIAQAAAA==.Wolvis:BAABLAAECoEVAAIhAAcI8x6cFwBPAgAhAAcI8x6cFwBPAgAAAA==.Woorff:BAAALAAECgIIAwAAAA==.Woschj:BAAALAAECgUIBwAAAA==.Wovl:BAABLAAECoEfAAMjAAgIcCTvAwA8AwAjAAgIcCTvAwA8AwAHAAII5xYtegB4AAAAAA==.',Xe='Xelos:BAAALAADCggICAAAAA==.Xestarossa:BAAALAAECgIIAgAAAA==.',Xl='Xload:BAABLAAECoEvAAITAAgIrRixFQA5AgATAAgIrRixFQA5AgAAAA==.',Ye='Yeni:BAAALAAECgMIAwAAAA==.Yenn:BAABLAAECoEmAAQMAAgINCOOFQDqAgAMAAgIEyKOFQDqAgALAAUI2iTlGQAMAgAPAAIIUBA7LABzAAAAAA==.Yenq:BAAALAAECgcIBwAAAA==.Yeserif:BAAALAADCgcIBgAAAA==.',Yo='Yokto:BAAALAADCgcICgAAAA==.Yoshí:BAABLAAECoElAAIHAAcI7h9qFgCJAgAHAAcI7h9qFgCJAgAAAA==.Yotta:BAAALAADCggIJwAAAA==.',Yu='Yuiî:BAAALAAECgEIAQAAAA==.',Za='Zaarol:BAABLAAECoE0AAICAAgIZgunhQCvAQACAAgIZgunhQCvAQAAAA==.',Ze='Zepto:BAAALAAECgcIEQAAAA==.Zeraphis:BAAALAADCgYIBgAAAA==.Zetta:BAAALAAECgcICwAAAA==.',Zh='Zhuh:BAAALAADCggIEAABLAAECgMIAwADAAAAAA==.',Zi='Ziiani:BAABLAAECoEaAAMQAAcILBlPVQD6AQAQAAcI6xdPVQD6AQAbAAII/R6zQAChAAAAAA==.Zimity:BAAALAAECgEIAgAAAA==.Zimsaye:BAAALAAECgEIAQAAAA==.',Zo='Zoh:BAABLAAECoEeAAIWAAgI/RTpEwD2AQAWAAgI/RTpEwD2AQAAAA==.Zoldreth:BAAALAADCggICAAAAA==.Zornax:BAACLAAFFIEFAAMSAAIIHAp8GgBwAAASAAIIkgh8GgBwAAAEAAIIWwXYNgBLAAAsAAQKgRkAAwQABwjpHyg9AA8CAAQABggfHig9AA8CABIAAgjUHpFcALAAAAAA.',Zu='Zumit:BAAALAADCggIDwABLAAFFAIIBQAFAOARAA==.Zuzannah:BAABLAAECoEUAAIjAAYIfhDbXgA4AQAjAAYIfhDbXgA4AQAAAA==.',['Zê']='Zêkê:BAAALAAECggIEAAAAA==.',['Án']='Ángerfist:BAAALAAECgIIAgAAAA==.',['Ân']='Ânkô:BAAALAAECgcIDAAAAA==.',['Ãr']='Ãrtus:BAAALAADCgEIAgAAAA==.Ãrwen:BAAALAADCgEIAgAAAA==.',['Ån']='Ångström:BAAALAAECgEIAQABLAAECgEIAgADAAAAAA==.',['Él']='Élar:BAAALAAECgYIBgAAAA==.Élisé:BAAALAAECgIIBAAAAA==.Éléandrielle:BAABLAAECoEVAAIcAAYIGQagxwDrAAAcAAYIGQagxwDrAAAAAA==.',['Éo']='Éomer:BAAALAAECgcIEAAAAA==.',['Ðe']='Ðeathly:BAABLAAECoEZAAIjAAYITBS/VQBWAQAjAAYITBS/VQBWAQAAAA==.',['Øl']='Ølson:BAAALAADCggIGQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end