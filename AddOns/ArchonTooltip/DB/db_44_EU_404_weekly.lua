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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Monk-Windwalker','Evoker-Devastation','Warlock-Destruction','Warlock-Affliction','Warrior-Fury','Warrior-Protection','Priest-Holy','Hunter-BeastMastery','Warlock-Demonology','Monk-Mistweaver','Hunter-Marksmanship','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Shaman-Restoration','Paladin-Holy','Druid-Restoration','Priest-Shadow','Druid-Feral','Shaman-Enhancement',}; local provider = {region='EU',realm='Azshara',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abendhimmel:BAAALAAECgIIAgAAAA==.Absyrtus:BAAALAAECgYICAAAAA==.',Ac='Acascha:BAAALAADCggIEAAAAA==.',Ad='Adastra:BAAALAADCggICAAAAA==.Addibeam:BAAALAAECgMIAwAAAA==.Addiheiltnix:BAAALAADCgcIBwAAAA==.',Ag='Agness:BAAALAADCggICwAAAA==.',Ai='Ailaikgrips:BAAALAAECggIEgAAAA==.Aither:BAAALAADCgcICQABLAAECgUICQABAAAAAA==.',Ak='Akizá:BAAALAAECgQICgAAAA==.Akyu:BAAALAADCgEIAQAAAA==.',Al='Aladìn:BAAALAAECgIIAgAAAA==.Aldharion:BAAALAAECgYIDwAAAA==.Alessandriel:BAAALAADCggIDwAAAA==.Alibâba:BAAALAAECgcIDwAAAA==.Alondra:BAAALAADCgcIEgAAAA==.Alphadin:BAAALAADCgYIBgAAAA==.Alíceinwow:BAAALAADCgYIDAAAAA==.',Am='Amirt:BAAALAADCgcIEgAAAA==.Amorryn:BAAALAAFFAIIBAAAAQ==.Amoryn:BAAALAAECggIEwABLAAFFAIIBAABAAAAAQ==.Amâranth:BAAALAAFFAEIAQAAAA==.',An='Anduríel:BAAALAADCggIDwAAAA==.Angelus:BAAALAAECgMIBQAAAA==.Angrath:BAAALAADCgcICAABLAADCgcIDQABAAAAAA==.Anâya:BAAALAADCggICAABLAAFFAIIBAABAAAAAA==.',Ao='Aoi:BAAALAAECgMIBwAAAA==.',Aq='Aquilia:BAAALAAECgUIBgAAAA==.',Ar='Argondk:BAAALAAECgYICwAAAA==.Ariax:BAAALAADCgcIBwAAAA==.Arisee:BAAALAAECgMIAwAAAA==.Arkanoth:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.Aronscha:BAAALAADCgcIDgAAAA==.Artaíus:BAAALAAECgYICwAAAA==.Arthacx:BAAALAAFFAIIAgAAAA==.',As='Ascalor:BAAALAAFFAIIBAAAAA==.Ascantius:BAAALAAECgYICwAAAA==.Ashar:BAAALAAECgYIBgAAAA==.Ashera:BAABLAAECoEYAAICAAgIYSR4BABDAwACAAgIYSR4BABDAwAAAA==.Ashkandur:BAAALAAECgQIDwAAAA==.Asùná:BAAALAADCgQIBAAAAA==.',At='Atalante:BAAALAAECgcICgABLAAECggIGAACAGEkAQ==.Athenaa:BAAALAADCggIEAAAAA==.',Au='Aurayia:BAAALAADCgcIBgAAAA==.Aurelia:BAAALAAECggIEwAAAA==.',Av='Avalie:BAAALAAECgUIBQAAAA==.Aveline:BAAALAAECggIDgAAAA==.Aviáná:BAAALAADCgIIAgAAAA==.',Az='Azalia:BAAALAAECgMIAwAAAA==.Azoic:BAAALAAECgUIBwAAAA==.Azurk:BAAALAADCgYICQAAAA==.Azzaleah:BAAALAAECgUIBQAAAA==.',Ba='Badhex:BAAALAADCggICAAAAA==.Bambadabusa:BAAALAAECgQIBgAAAA==.Bangdang:BAAALAADCggIEwAAAA==.Bankfutzi:BAAALAADCggICwABLAAECgYICgABAAAAAA==.Baratros:BAAALAAECgYICwAAAA==.Bashe:BAAALAAECgMIAwAAAA==.Battank:BAAALAAECgYIDgAAAA==.',Be='Beargryll:BAAALAAECgMIAwAAAA==.Beldô:BAAALAAECgYIDAAAAA==.Bellethiel:BAAALAADCgEIAgAAAA==.Belzegor:BAAALAAECgUIBQAAAA==.',Bi='Billgoldberg:BAAALAAECgIIAgABLAAECgMIBwABAAAAAA==.',Bl='Blackhorn:BAAALAADCgcICAAAAA==.Blase:BAAALAADCgEIAQABLAAECggIFgADAMkfAA==.Blueraze:BAABLAAECoEWAAIEAAgI5CK8BADMAgAEAAgI5CK8BADMAgAAAA==.Blumenfreund:BAAALAAECgMIBwAAAA==.',Bo='Bomben:BAAALAADCggICAAAAA==.Bonestripper:BAAALAAECgYICQAAAA==.Boomlord:BAABLAAECoEXAAIDAAcIqBopJAAFAgADAAcIqBopJAAFAgAAAA==.Boregar:BAAALAAECgYIBgAAAA==.Boroc:BAAALAADCgcIBwAAAA==.Boxbunny:BAAALAAECgEIAQAAAA==.',Br='Bradykardie:BAAALAADCgcIEAABLAAECgcIEgABAAAAAA==.Brocken:BAAALAAECgIIAwAAAA==.Brozag:BAAALAADCggICAAAAA==.Brøxìgar:BAAALAAECgYICAAAAA==.',Bu='Bullzor:BAAALAADCgEIAQAAAA==.Bumblebeeh:BAAALAADCgcIBgABLAADCggICAABAAAAAA==.Bumja:BAAALAADCggICgAAAA==.Bumsmuckel:BAAALAAECgMIAwAAAA==.',['Bé']='Béelzebub:BAAALAADCggIDwAAAA==.Bérshká:BAAALAADCggIDwAAAA==.',['Bï']='Bïrds:BAAALAAECgYICgAAAA==.',Ca='Cadmium:BAABLAAECoEWAAIFAAgIKyRqAQBUAwAFAAgIKyRqAQBUAwAAAA==.Caluso:BAAALAAECgEIAQAAAA==.',Ce='Cemözdemir:BAAALAAECgYIDAAAAA==.',Ch='Chamuel:BAAALAAECgEIAQAAAA==.Chien:BAAALAADCgcIBwAAAA==.Chienii:BAAALAADCgcIBwAAAA==.Chikø:BAAALAAECgYIBgAAAA==.Chion:BAAALAADCggICgAAAA==.Chowsn:BAAALAAECgYICQABLAAECggIEAABAAAAAA==.Chowsy:BAAALAAECggIEAAAAA==.Chowzy:BAAALAADCggICAAAAA==.Chénlông:BAAALAAECgIIAgAAAA==.Chíon:BAAALAADCgcIBQAAAA==.Chîara:BAAALAAECgMIAwAAAA==.',Ci='Cildriel:BAAALAAECgEIAQAAAA==.',Cl='Clarahlol:BAAALAADCgUIBgAAAA==.Clarâh:BAAALAAECgIIAgAAAA==.Cluelezz:BAAALAAECggIEAAAAA==.',Co='Coexistence:BAAALAADCgYIBgABLAAECgQICgABAAAAAA==.Coppi:BAAALAADCggIDwAAAA==.Corbana:BAAALAADCggICAABLAADCggIDwABAAAAAA==.Corvînus:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.',Cr='Cristyne:BAAALAADCgYIBgAAAA==.Crâvên:BAAALAAECgEIAQAAAA==.',Ct='Ctöön:BAACLAAFFIEHAAMGAAMIDA65BAD9AAAGAAMIDA65BAD9AAAHAAEIwgx6AQBUAAAsAAQKgRYAAgYACAjFIHIKALkCAAYACAjFIHIKALkCAAAA.',Cy='Cyt:BAAALAAECgYIBgAAAA==.',['Câ']='Câps:BAAALAAECgIIAgAAAA==.Câstîel:BAAALAAECgEIAgAAAA==.',['Cò']='Còldi:BAAALAADCgYIBgAAAA==.',['Cø']='Cødiac:BAAALAAECgcIEgAAAA==.',Da='Dallow:BAAALAAECgEIAQAAAA==.Dalroumak:BAAALAADCggIFgAAAA==.Darkbash:BAAALAAECggICAAAAA==.Darkwalker:BAAALAADCgcIDAAAAA==.Darlith:BAACLAAFFIEHAAMIAAQIph1tAgAdAQAIAAMI0xptAgAdAQAJAAEIHiYAAAAAAAAsAAQKgRcAAggACAg1IrILALwCAAgACAg1IrILALwCAAAA.Davizard:BAABLAAECoEUAAIFAAgICxezDQA9AgAFAAgICxezDQA9AgAAAA==.',De='Decaei:BAAALAAECgEIAQABLAAFFAMIAwABAAAAAA==.Demogôrlôck:BAAALAADCgcICgABLAAFFAIIAgABAAAAAA==.Deratlium:BAAALAAECgMIBgAAAA==.Derotrix:BAAALAADCgcIBwAAAA==.',Di='Diafu:BAAALAAECgMIBgAAAA==.Dimespring:BAAALAADCgYIBgAAAA==.Diorgas:BAAALAAECgYICwAAAA==.',Do='Dolinarius:BAAALAAECggICwAAAA==.Donlexa:BAAALAAECgMIBQAAAA==.Donlysop:BAAALAAECgYIBwAAAA==.Doomboy:BAAALAAECgcIBwAAAA==.',Dr='Dracenda:BAAALAAECgcIDwAAAA==.Drakusus:BAAALAAECgYICgAAAA==.Drannina:BAAALAADCggICwABLAAECgYICgABAAAAAA==.Draçul:BAAALAADCgcICgABLAADCgcIDQABAAAAAA==.Drengpala:BAAALAAECgYICQAAAA==.Drengur:BAAALAADCggICAAAAA==.Dreyàloha:BAAALAADCggIDwAAAA==.Drruanx:BAAALAAECgYICwAAAA==.Drunkyard:BAAALAADCgcICwAAAA==.',Du='Dupy:BAAALAADCgMIAwAAAA==.Durendaî:BAAALAADCgQIBAAAAA==.',['Dé']='Détox:BAAALAAECgcIDgAAAA==.',['Dê']='Dêathlight:BAAALAAECggICwAAAA==.',['Dü']='Düdorf:BAAALAADCggICgAAAA==.',Ea='Easywl:BAAALAADCggICAAAAA==.',Ed='Edalia:BAAALAADCgcIBwAAAA==.',Eg='Egî:BAACLAAFFIEJAAIKAAQIrheDAgAUAQAKAAQIrheDAgAUAQAsAAQKgRUAAgoACAgqIqUEAPUCAAoACAgqIqUEAPUCAAAA.',Ek='Ektobus:BAAALAADCgcIBwABLAAECggICwABAAAAAA==.',El='Elefoil:BAAALAADCgcICAAAAA==.Elenaril:BAABLAAECoEXAAIDAAgIihz/EACkAgADAAgIihz/EACkAgAAAA==.Elfi:BAAALAAECgcIDAAAAA==.Ellanrii:BAACLAAFFIEGAAIJAAMIyh01AQAZAQAJAAMIyh01AQAZAQAsAAQKgRsAAgkACAhVJBIBAFoDAAkACAhVJBIBAFoDAAAA.Ellenor:BAAALAAECgYIDwAAAA==.Eloween:BAAALAADCgIIAwAAAA==.Eloweyn:BAAALAAECgYICwAAAA==.Elowên:BAAALAADCgcIBwAAAA==.Elunse:BAAALAADCggICAAAAA==.Elîneas:BAAALAAECgMIBAAAAA==.',Ep='Ephi:BAAALAAECgMIBAAAAA==.',Er='Erìx:BAAALAADCggIDgAAAA==.',Es='Escordia:BAAALAAECgYICgAAAA==.',Eu='Eulé:BAAALAADCgQIBAAAAA==.',Ev='Eveer:BAACLAAFFIEHAAILAAQI/Ba/AQAZAQALAAQI/Ba/AQAZAQAsAAQKgRYAAgsACAheIewFAA8DAAsACAheIewFAA8DAAAA.Eversham:BAAALAADCggICAAAAA==.Evoksie:BAAALAAFFAIIAgAAAA==.',Ew='Ewake:BAACLAAFFIEIAAMMAAQIHxD5AwCwAAAMAAIIihj5AwCwAAAGAAMIpQz9CACuAAAsAAQKgRUAAwYACAjTIHcZAAQCAAYABgguHncZAAQCAAwABQjUIWgVALIBAAAA.',Ex='Excibu:BAAALAAECggICAAAAA==.',Ez='Ezrah:BAAALAADCgMIAwAAAA==.',Fa='Faiyth:BAAALAAECgQIBQAAAA==.Fardibard:BAAALAADCgIIAgAAAA==.Fatebringer:BAAALAADCgMIBAABLAAECgYIBwABAAAAAA==.',Fe='Fearnone:BAAALAADCggICAAAAA==.Fetchboyslim:BAAALAADCgYIBgAAAA==.Fexh:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.',Fi='Firefoxy:BAABLAAECoEXAAINAAgIpQtmEACRAQANAAgIpQtmEACRAQAAAA==.Firenzê:BAAALAADCggICAAAAA==.Firepandy:BAAALAAECgQIBAABLAAFFAIIAgABAAAAAA==.',Fl='Flòki:BAAALAAECggICQAAAA==.',Fr='Franrott:BAAALAAECgMIBwAAAA==.Frâny:BAAALAAECgYIDwAAAA==.',Fu='Furu:BAAALAAECgYIBgABLAAECggIFgAIALElAA==.',Fx='Fxxy:BAAALAAECgcICAAAAA==.',Fy='Fynnwb:BAAALAADCgUIBgAAAA==.',['Fô']='Fôrrester:BAAALAADCggICAAAAA==.',Ga='Galath:BAABLAAECoEbAAIJAAgIphkkBwBkAgAJAAgIphkkBwBkAgAAAA==.Ganvaa:BAAALAAECgYIBwAAAA==.Garachzarck:BAABLAAECoEWAAIIAAgI5R2ICADuAgAIAAgI5R2ICADuAgAAAA==.Garnelefant:BAAALAAECgUIBgABLAAECgcIEgABAAAAAA==.Gartosch:BAAALAAECgYICQAAAA==.Gaø:BAABLAAFFIEGAAIEAAMI3BXHAwCjAAAEAAMI3BXHAwCjAAAAAA==.',Gi='Gibbim:BAAALAADCggIDgAAAA==.Gidora:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.Gigáblácé:BAAALAAECgcIDwAAAA==.Gilderon:BAAALAADCggIFwAAAA==.',Gl='Glaivebae:BAAALAAECgMIBAAAAA==.',Go='Goóse:BAAALAAECggICQAAAA==.',Gr='Grabriel:BAAALAADCggIEQAAAA==.Gramokh:BAAALAADCgUIBgAAAA==.Graum:BAAALAAECgYICQAAAA==.Grimmelfitz:BAAALAAECgMIBQAAAA==.Grimmosh:BAAALAADCgYICgAAAA==.Grink:BAAALAADCggIDwAAAA==.Gronahk:BAAALAADCgYIBQAAAA==.Grìz:BAAALAADCgIIAgAAAA==.',Gu='Guntor:BAAALAAECgQIBgAAAA==.Gurgelwurgel:BAAALAADCgYIBgAAAA==.Guzituzi:BAAALAAECgMIAwAAAA==.',Ha='Hahnu:BAAALAADCgQIBwAAAA==.Haneunji:BAAALAADCgcICgABLAAECgIIAwABAAAAAA==.Hanibalektra:BAAALAAECgYIBwAAAA==.Hannahorror:BAAALAAECgcIDgAAAA==.Hansyolo:BAAALAAECgUICgAAAA==.Hardcora:BAAALAADCgEIAQAAAA==.Hazeomatic:BAAALAAECgIIAgAAAA==.',He='Healyouself:BAAALAADCgEIAQAAAA==.Heisénberg:BAAALAADCgcICQAAAA==.Heldia:BAAALAADCggICAAAAA==.Helge:BAAALAAECgYIDwAAAA==.Herbekrass:BAAALAADCggICAABLAAECggIFwANAKULAA==.',Hi='Highgor:BAAALAADCggIDQAAAA==.Hikaro:BAAALAAECgIIBAAAAA==.Hitze:BAAALAAECggICAAAAA==.',Ho='Hoeby:BAAALAADCggICAAAAA==.Holyferkel:BAAALAAECgYICwAAAA==.Hotaru:BAAALAAECgMIBwAAAA==.Hotwing:BAAALAAECgMIBwAAAA==.Howlydragon:BAAALAAECgQIBAAAAA==.',Hu='Humaneater:BAAALAADCggIEAAAAA==.Huschii:BAAALAADCgIIAgAAAA==.',Hy='Hypocritical:BAAALAAECgcIDwAAAA==.',['Hâ']='Hâzel:BAAALAADCgIIAgABLAAECgcIEgABAAAAAA==.',['Hú']='Húmiliation:BAAALAADCggICgAAAA==.',Id='Idde:BAAALAADCggICwABLAAECgIIAgABAAAAAA==.Iddô:BAAALAAECgIIAgAAAA==.Iddüü:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',Il='Illidamo:BAAALAAECgYICgAAAA==.',In='Insane:BAAALAADCggIFwAAAA==.Inselhopf:BAAALAADCgcICwAAAA==.',Io='Ioun:BAAALAAECgUIBQAAAA==.',Iy='Iyara:BAAALAAECgUICQAAAA==.',Ja='Jacé:BAAALAADCgQIAwAAAA==.Jalankulkija:BAAALAAECgQIBAAAAA==.Janita:BAAALAADCggICAAAAA==.Jater:BAAALAADCggIDwAAAA==.',Jc='Jcy:BAAALAAECgMIBAAAAA==.',Jd='Jdiva:BAAALAADCggICAAAAA==.',Ji='Jinda:BAAALAADCggIDQAAAA==.Jintaur:BAAALAAECggICQAAAA==.',Jo='Jogos:BAAALAAECgUICQAAAA==.Jolinê:BAAALAADCgcIBwAAAA==.Jondillamand:BAAALAADCgYIDAAAAA==.Joshiimizu:BAAALAAECgMIBwAAAA==.',Ju='Justnbiever:BAAALAAECgUIBwAAAA==.',['Jà']='Jàné:BAAALAADCggIEgABLAAECgMIBQABAAAAAA==.',Ka='Kagachi:BAAALAAECgEIAQAAAA==.Kahmehameha:BAAALAADCggIDgAAAA==.Kaliya:BAAALAADCggIDwAAAA==.Kamala:BAAALAADCgcICAAAAA==.Karliah:BAAALAADCgYIBwAAAA==.Karnavora:BAAALAAECgQICgAAAA==.Kasla:BAAALAADCgcIBwAAAA==.Katnessa:BAAALAAECgMIBwAAAA==.',Ke='Keewe:BAAALAADCggIDgABLAADCggIFgABAAAAAA==.Kefla:BAAALAAECgMIBwAAAA==.Kenmo:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Kerub:BAAALAAECgMIBgAAAA==.',Kh='Khaleésí:BAAALAADCggICQAAAA==.Khalida:BAAALAAECgYIDQAAAA==.Khazevo:BAAALAAECgYIDAAAAA==.Khazmage:BAAALAADCggICAAAAA==.Khensu:BAAALAAECgIIAgAAAA==.Khirinya:BAAALAADCgYIBgABLAAECgUIBgABAAAAAA==.',Ki='Kiirou:BAAALAAECgYICwAAAA==.Kipu:BAAALAAECgYICwAAAA==.',Kl='Klingenkurt:BAAALAAECgQICQAAAA==.',Ko='Komiko:BAAALAADCggIEAABLAAECggIEwABAAAAAA==.Kopfkissen:BAAALAAECgMIAwAAAA==.',Kr='Kranul:BAAALAAECgIIAgABLAAFFAIIAgABAAAAAA==.Krimpatul:BAAALAAECgEIAQAAAA==.Krylock:BAAALAAECgYIDwAAAA==.Krîtînâ:BAAALAAECgQIBgAAAA==.Krümel:BAAALAAECgEIAQAAAA==.',Ku='Kuetschii:BAAALAAECgIIAgAAAA==.Kungfucaipe:BAAALAADCgIIAgAAAA==.Kuno:BAAALAAECgYICAAAAA==.Kurika:BAAALAAECgYIBgABLAAECgYIBwABAAAAAA==.Kurpfuscher:BAAALAAECgIIAwAAAA==.',['Ká']='Káirý:BAAALAADCgYIBgAAAA==.',La='Lakyron:BAAALAAECgMIAwAAAA==.Lalami:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Lanay:BAAALAAECgQIBAAAAA==.Lappenlock:BAAALAAECgcIEgAAAA==.Lasimera:BAAALAADCgcIBwABLAAECgYIBwABAAAAAA==.Latinò:BAAALAAECgIIAgAAAA==.Laurelîn:BAAALAAECgMIBwAAAA==.Lauslie:BAAALAAECgMIBAAAAA==.Lavr:BAAALAAECgEIAQAAAA==.',Le='Leerstunde:BAAALAADCggICAAAAA==.Leodavinci:BAAALAAECgIIAgAAAA==.Lethil:BAAALAADCgcIDgAAAA==.Lexxa:BAAALAAECgYIBgAAAA==.',Li='Liamliam:BAAALAADCgcIFAAAAA==.Lichtelf:BAAALAAECgYIBgABLAAECgYICgABAAAAAA==.Lichtrecht:BAAALAAFFAEIAQAAAA==.Lilidora:BAAALAAECgYIBQAAAA==.Lillyana:BAAALAAECgMIAwAAAA==.Linneâ:BAAALAADCgYIBgABLAADCggIEQABAAAAAA==.Lisrayah:BAAALAAECggIDgAAAA==.',Lo='Lowcow:BAAALAADCgYIBgAAAA==.Lowgor:BAAALAAECgcIEAAAAA==.Lowhealth:BAAALAAECgIIAgAAAA==.',Lu='Lumii:BAAALAADCggICwAAAA==.Lumpenjunge:BAAALAAECgIIAwAAAA==.Lunabolt:BAAALAADCggIEgABLAAECggIHwAOAJAjAA==.Lunashot:BAABLAAECoEfAAIOAAgIkCOqAwANAwAOAAgIkCOqAwANAwAAAA==.Luís:BAAALAADCggICAAAAA==.',Ly='Lyssandria:BAAALAADCggICAAAAA==.',['Lí']='Línnea:BAAALAADCggIDwABLAAECgUIBgABAAAAAA==.',['Lö']='Lörrez:BAAALAAECggICAABLAAECggIEAABAAAAAA==.',Ma='Madeva:BAAALAAECgcIEAAAAA==.Madmurdog:BAAALAAECgcIDQAAAA==.Mageinchina:BAAALAAECgMIBAAAAA==.Malinava:BAAALAAECgIIAgAAAA==.Malloryknoxx:BAAALAADCgcIBwABLAAECggIIwADAJ0fAA==.Malloryx:BAABLAAECoEjAAIDAAgInR/aFQB0AgADAAgInR/aFQB0AgAAAA==.Malloryxx:BAAALAAECgYIBgABLAAECggIIwADAJ0fAA==.Markforster:BAAALAADCgMIAwAAAA==.Marley:BAAALAAECgUIBgAAAA==.Marlleen:BAAALAAECgMIBQAAAA==.Matania:BAAALAAECgMIBwAAAA==.',Me='Meerbär:BAABLAAECoEXAAIPAAgIeyJRBAAYAwAPAAgIeyJRBAAYAwAAAA==.Mentie:BAAALAAECgIIAgAAAA==.Mesablind:BAAALAAECgYIBgAAAA==.Methindor:BAAALAADCgYIBgAAAA==.',Mi='Miau:BAAALAADCggIDgAAAA==.Mikat:BAAALAAECgEIAQAAAA==.Milked:BAAALAAECggICAAAAA==.Milkypala:BAAALAADCgcIBwAAAA==.Minz:BAAALAAECgIIAQAAAA==.Mirakura:BAAALAADCgYIBgAAAA==.Mirat:BAACLAAFFIEFAAIQAAMIWBqUCACxAAAQAAMIWBqUCACxAAAsAAQKgRgAAhAACAhCI9cGABEDABAACAhCI9cGABEDAAAA.Miroin:BAAALAAECgYICAAAAA==.Mirus:BAAALAAECgIIAgAAAA==.Misas:BAAALAAECgYIDgAAAA==.Misstück:BAAALAAECgYICgAAAA==.Mitrá:BAAALAAECgYICgAAAA==.Miulin:BAABLAAECoETAAIQAAYIEw3VWwAXAQAQAAYIEw3VWwAXAQAAAA==.Miyeon:BAAALAADCggICAAAAA==.',Mj='Mjólnír:BAAALAAECgIIAgAAAA==.',Mo='Mobbydan:BAAALAAECgYICgAAAA==.Moinsen:BAAALAAECgMICQAAAA==.Moitoi:BAAALAAECgQIBwAAAA==.Momosapien:BAAALAADCgMIAwAAAA==.Mongô:BAAALAADCggICgAAAA==.Monkyfex:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Monthy:BAAALAAECgIIAgAAAA==.Mordo:BAACLAAFFIEIAAIRAAMIyBGKAQDmAAARAAMIyBGKAQDmAAAsAAQKgRYAAhEACAj3GGEGADQCABEACAj3GGEGADQCAAAA.Morgy:BAAALAAECgQIBgABLAAECggIFwANAKULAA==.Morusa:BAAALAAECgMIBQAAAA==.',Ms='Msbrightside:BAAALAAECgYICAAAAA==.',Mu='Muhünn:BAAALAAECgYICwAAAA==.',My='Myotisa:BAAALAADCggIFgAAAA==.',['Má']='Máylee:BAAALAAFFAIIAgAAAA==.',['Mâ']='Mâdâra:BAAALAADCgEIAQAAAA==.',['Mø']='Mømmy:BAAALAAECgMIBAAAAA==.',['Mý']='Mýstíc:BAAALAADCgcICQAAAA==.',Na='Nachtwind:BAAALAAECgEIAQAAAA==.Naelthas:BAAALAAECgYIBgAAAA==.Narminoria:BAAALAAECgYIDwAAAA==.Navenya:BAABLAAECoEVAAILAAgIxSLXAwA2AwALAAgIxSLXAwA2AwAAAA==.Nayleya:BAAALAAECgYIDAAAAA==.Nayuna:BAAALAAECgEIAgAAAA==.Naîhla:BAAALAAECggIEAAAAA==.',Ne='Necromán:BAAALAADCggIDwAAAA==.Neheb:BAAALAADCgcIDQAAAA==.Neiklot:BAAALAAFFAIIAgAAAA==.Neltharian:BAAALAAECgIIAgAAAA==.Nemefist:BAAALAAECgYIBgABLAAFFAQICQASAOEhAA==.Nemethis:BAACLAAFFIEJAAMSAAQI4SEeAQA6AQASAAMILiEeAQA6AQATAAEI+SMAAAAAAAAsAAQKgRYAAhIACAgHJPMBAD0DABIACAgHJPMBAD0DAAAA.Nemèsis:BAABLAAECoESAAIUAAcIrxr/EwAvAgAUAAcIrxr/EwAvAgAAAA==.Nerajix:BAAALAAFFAIIBAAAAA==.Nethralya:BAAALAAECgQIBAAAAA==.',Ni='Niccage:BAAALAADCgcICwABLAAECggIFwADAIocAA==.Nightnare:BAAALAAECgEIAQAAAA==.Nigripes:BAAALAAECgYIBgAAAA==.',No='Noclue:BAAALAADCgQIBAAAAA==.Noctyr:BAAALAAECgYIDgAAAA==.Nonie:BAAALAADCgQIBAAAAA==.Norumoth:BAAALAADCgcIBwAAAA==.Notkhan:BAAALAAECgYIEQAAAA==.Notmobby:BAAALAADCgcIDgABLAAECgYICgABAAAAAA==.Notslapped:BAAALAADCgUIBQAAAA==.Noxfrost:BAAALAAECgUICQAAAA==.',Ns='Nsh:BAAALAADCgEIAQABLAADCgEIAQABAAAAAA==.',['Nó']='Nóvu:BAAALAAECgQIBgAAAA==.',['Nô']='Nôôkie:BAAALAAECggIBwAAAA==.',Ob='Obehix:BAAALAAECgYICwAAAA==.',Oc='Ocinred:BAAALAADCggIDQAAAA==.',Oj='Ojuscha:BAABLAAECoEUAAIVAAgIdBohDwBOAgAVAAgIdBohDwBOAgAAAA==.',Ok='Okkultist:BAAALAADCgcIFAABLAADCgcIDQABAAAAAA==.Okmahar:BAAALAADCggIFQAAAA==.',On='Ondoku:BAAALAADCgEIAQAAAA==.Oneechan:BAAALAADCgcIBgAAAA==.Oneeighty:BAAALAADCgcICQAAAA==.Onehsot:BAAALAADCggICgAAAA==.Onkeldrache:BAAALAADCgcIDgABLAAECgEIAgABAAAAAA==.Onkeleule:BAAALAAECgEIAQABLAAECgEIAgABAAAAAA==.Onkelfritte:BAAALAAECgEIAgAAAA==.',Op='Optiksoldîer:BAAALAADCgcIBwAAAA==.',Or='Orchid:BAAALAAECgYICgAAAA==.Orgathacram:BAAALAAECgMIBwAAAA==.Orleans:BAABLAAECoEVAAIWAAgIxSI1AQAYAwAWAAgIxSI1AQAYAwAAAA==.',Ow='Owlrider:BAAALAAECgEIAQAAAA==.Ownîî:BAAALAADCgQIBAAAAA==.',Oy='Oyosham:BAAALAADCggICAAAAA==.',Pa='Pablo:BAAALAADCgcIBwAAAA==.Paipe:BAABLAAECoEVAAMGAAgIiCC4BgD2AgAGAAgITCC4BgD2AgAMAAQISx44KAAwAQABLAAECggIFgADAMkfAA==.Palalina:BAAALAADCgQIBAAAAA==.Palkia:BAAALAADCggICAABLAAECggIFwANAKULAA==.Pallap:BAAALAADCggIDAAAAA==.Pandaffe:BAACLAAFFIEHAAINAAMIYQfHAgDgAAANAAMIYQfHAgDgAAAsAAQKgRYAAg0ACAhbEtsLAOkBAA0ACAhbEtsLAOkBAAAA.Pandó:BAAALAADCggICAABLAAECgcIDAABAAAAAA==.Pangania:BAAALAADCgQIBAAAAA==.Panzerfaust:BAAALAAECgUIBQABLAAECgUIBQABAAAAAA==.Papageno:BAAALAADCgcIBwAAAA==.',Pe='Peaches:BAAALAAECggIDgABLAAFFAIIAgABAAAAAA==.Pepebeam:BAAALAAECggICQABLAAECggICgABAAAAAA==.Pepeclap:BAAALAAECggICgAAAA==.Pepegrip:BAAALAAECgMIAwABLAAECggICgABAAAAAA==.Pepeshaman:BAAALAADCgYIBgABLAAECggICgABAAAAAA==.Perla:BAAALAAECgYICgAAAA==.',Ph='Phatho:BAAALAAECgYICQAAAA==.Phii:BAAALAAECgEIAQAAAA==.Phironê:BAAALAAECgMIBwAAAA==.Phlegethon:BAAALAAECgIIBAAAAA==.Phururuuhn:BAAALAADCgcIBwAAAA==.',Pl='Plastii:BAABLAAECoEWAAIDAAgIyR/GDQDGAgADAAgIyR/GDQDGAgAAAA==.',Po='Poweronoff:BAAALAADCgcIBwAAAA==.',Pr='Prie:BAAALAADCgcICgAAAA==.Pryfex:BAAALAAECgYIDQAAAA==.',Ps='Psychobanger:BAAALAADCgYIBgAAAA==.',Pu='Pumpchaser:BAAALAADCgcICwAAAA==.Pupper:BAAALAADCgQIBAAAAA==.Purp:BAAALAADCgcIBwAAAA==.',['Pí']='Píkâchu:BAAALAAECgUIBwAAAA==.',['Pü']='Pünktchen:BAAALAADCgQIBAAAAA==.',Qi='Qi:BAAALAADCgMIAwAAAA==.',Ql='Qlock:BAAALAADCggIFgAAAA==.',Qt='Qtum:BAAALAADCggICwAAAA==.',Qu='Quedegras:BAAALAADCggIEgAAAA==.Quelda:BAAALAADCgYIBgAAAA==.',Qw='Qwdru:BAAALAAECgIIAgAAAA==.',Ra='Raawwr:BAAALAADCggIBgAAAA==.Racheeule:BAAALAADCggIDQAAAA==.Raknatu:BAAALAADCggIBwAAAA==.Rakshasza:BAAALAAECgYIBgAAAA==.Ral:BAAALAADCggICAAAAA==.Raquellâ:BAAALAAECgIIAgAAAA==.Ravator:BAAALAAECgYICwAAAA==.Ravenhard:BAAALAADCggIDwAAAA==.Razaesh:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.',Re='Reborn:BAAALAAECgYICAAAAA==.Reíbach:BAAALAAECgIIAgAAAA==.',Rh='Rhuan:BAAALAADCgcIBwAAAA==.',Ri='Rikkú:BAAALAADCgQIAgAAAA==.Rimbimbim:BAAALAAECgYIBwABLAAECggIFQAXAHQWAA==.',Ro='Roberd:BAAALAADCggICQAAAA==.Rogu:BAAALAAECgIIAwAAAA==.Rollbow:BAAALAAECgYICwAAAA==.Rollostaroi:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.Ronîn:BAAALAADCggIFgABLAAECgYIBgABAAAAAA==.Rootyu:BAACLAAFFIEHAAIPAAQIjhtGAQAjAQAPAAQIjhtGAQAjAQAsAAQKgRYAAg8ACAjoJY8DACsDAA8ACAjoJY8DACsDAAAA.',Ru='Rujabin:BAAALAAECgMIAwAAAA==.Rukasu:BAAALAAECgUIBQAAAA==.',Ry='Ryômen:BAAALAAECggIAwABLAAECggIAwABAAAAAA==.',['Râ']='Râcâllâ:BAAALAADCgcICQABLAAECgYIDwABAAAAAA==.',['Ró']='Róckstár:BAAALAADCgYICQAAAA==.',['Rö']='Römsömsöms:BAABLAAECoEVAAMXAAgIdBasEwD3AQAXAAgIdBasEwD3AQAPAAYIrROJIACKAQAAAA==.',['Rø']='Røckefeller:BAAALAAECgIIAgAAAA==.',Sa='Sabanda:BAAALAAECgUIBQAAAA==.Sahgosh:BAAALAADCgIIAgABLAAECgUIBQABAAAAAA==.Saladir:BAAALAAECgIIAwAAAA==.Samila:BAAALAAECgYIBwAAAA==.Sangris:BAABLAAECoEVAAIRAAgI/w2SCgCsAQARAAgI/w2SCgCsAQAAAA==.Sartaria:BAAALAADCggICAABLAADCggIEQABAAAAAA==.',Sc='Scalista:BAAALAADCgcIDQAAAA==.Scampy:BAAALAAECgEIAgAAAA==.Schati:BAAALAADCgQIBAAAAA==.Schattenauge:BAAALAADCgcIFAAAAA==.Schattenleid:BAAALAAECgYICwAAAA==.Schulze:BAAALAADCgYICAAAAA==.Scornius:BAAALAAECgcIEAAAAA==.Scornoth:BAAALAAECgYICAAAAA==.Scrounginski:BAAALAADCgYIBwAAAA==.',Se='Senlayn:BAAALAAECgIIAgABLAAECgUIBgABAAAAAA==.Sensu:BAAALAADCggICAAAAA==.Sentaya:BAAALAAECgUIBgAAAA==.Sevenx:BAAALAAECgUICQAAAA==.',Sh='Shadowjunky:BAAALAADCggIDwAAAA==.Shadowslâyer:BAAALAADCggIFAAAAA==.Shadowvlad:BAAALAADCggICAAAAA==.Shagoos:BAAALAADCgcIBwAAAA==.Shalidud:BAAALAAECggIBwAAAA==.Shamyfex:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.Shanghrila:BAAALAAECgYICwAAAA==.Shannà:BAAALAADCggIDwAAAA==.Shayáríel:BAAALAADCggICAAAAA==.Shervan:BAAALAAECggICgAAAA==.Shinoo:BAAALAADCgcIBwABLAAECgEIAgABAAAAAA==.Shizué:BAAALAADCggIEAAAAA==.Shokeg:BAABLAAECoEVAAIEAAgI7BJMCwAWAgAEAAgI7BJMCwAWAgAAAA==.Shêrvan:BAAALAAECggIAwAAAA==.',Si='Siméx:BAAALAAECggIEAAAAA==.Sinext:BAAALAAECgQICwABLAAECgYIBgABAAAAAA==.',Sl='Slas:BAAALAAECgEIAQAAAA==.Slit:BAAALAAECgcIEgAAAA==.Slugrider:BAAALAADCggICAAAAA==.',Sm='Smiite:BAAALAAECgQIBwAAAA==.Smôkêy:BAAALAADCggIDwAAAA==.',Sn='Sneakyminaj:BAAALAADCggICAAAAA==.Sneidig:BAAALAADCgcICgAAAA==.Snipah:BAAALAAECgcIDwAAAA==.Snowmercy:BAAALAADCgQIBAAAAA==.Snude:BAAALAAECgIIAgAAAA==.',So='Sonderbonbon:BAAALAAECgYIDQAAAA==.Sondermodell:BAAALAADCgcICAAAAA==.Sonnenmeer:BAAALAADCgcICAAAAA==.Soonkyu:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.',Sp='Spacèy:BAAALAADCggIEAAAAA==.Spaiché:BAAALAADCggICgAAAA==.Spartaner:BAAALAADCggIBQAAAA==.Speederell:BAACLAAFFIEGAAIYAAMIJxeEBQC0AAAYAAMIJxeEBQC0AAAsAAQKgRYAAxgACAijJPYFAAMDABgACAijJPYFAAMDAAoAAQi4CIVeADoAAAAA.Spikes:BAAALAAECgcIBwAAAA==.',St='Starvoker:BAAALAAECgYIDAAAAA==.Stasia:BAAALAAECgYICAABLAAECggIFQAZAD8fAA==.Stasibubble:BAAALAADCggICQABLAAECggIFQAZAD8fAA==.Stasidecay:BAAALAAECgYIBgABLAAECggIFQAZAD8fAA==.Stasidroid:BAABLAAECoEVAAQZAAgIPx8bBACXAgAZAAcIEyAbBACXAgAXAAIIdQiRVABeAAAPAAEIHA/YTAA+AAAAAA==.Stasifel:BAAALAAECgMIAwABLAAECggIFQAZAD8fAA==.Stasisneak:BAAALAADCgYIBwABLAAECggIFQAZAD8fAA==.Storir:BAAALAADCggIDgAAAA==.Strikegunner:BAAALAADCgcIBwAAAA==.Stubi:BAAALAAECgYIDAAAAA==.Stuizid:BAAALAAECgMIBQAAAA==.Sturmpfote:BAAALAAECgMIBwAAAA==.Stârsky:BAAALAAECgYICwAAAA==.',Su='Sudyca:BAAALAAECgcIEgAAAA==.Sugurú:BAAALAAECggIAwAAAA==.Sunnypanda:BAAALAADCgYICwABLAADCggIDwABAAAAAA==.Surtûr:BAAALAADCgEIAQAAAA==.',Sw='Swordfish:BAEALAAECgMIBwAAAA==.',Sy='Sylpion:BAAALAADCggIDwAAAA==.Sylvâ:BAAALAAECgYIBgABLAAECggICwABAAAAAA==.Synethic:BAAALAAECgQIBAAAAA==.',['Sê']='Sêlena:BAAALAAECgYIBwAAAA==.',['Sî']='Sîgismund:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.',['Só']='Sókár:BAAALAADCgcICAAAAA==.',['Sú']='Súrtúr:BAAALAAECgYICQAAAA==.',Ta='Tabaqui:BAAALAADCggIEQAAAA==.Tacci:BAAALAADCggICwAAAA==.Tactikzz:BAAALAADCgYIBgAAAA==.Taeyeon:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Tantetilly:BAAALAAECgYICwAAAA==.Taton:BAAALAADCggICwAAAA==.Taumi:BAAALAADCggICAAAAA==.Taurs:BAAALAADCggICwAAAA==.Tavez:BAABLAAECoEWAAIIAAgIsSVuAQBrAwAIAAgIsSVuAQBrAwAAAA==.Tayuka:BAAALAAECgUIBQABLAAECgcIDwABAAAAAA==.Tazuna:BAAALAADCggIDwAAAA==.',Te='Teaone:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.Temnoc:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Tenet:BAAALAADCgcICwABLAAECggIGwANAAkZAA==.Tensi:BAAALAAECgcIDwAAAA==.Tequîla:BAAALAADCggICAAAAA==.Teregôn:BAAALAAECgYICQAAAA==.Terenyes:BAAALAAECgMIBwABLAAECgUIBgABAAAAAA==.Terpéntin:BAAALAAECgQICgAAAA==.Tess:BAAALAAFFAIIBAAAAA==.Tevtev:BAAALAAECgYIBwAAAA==.',Th='Thrakar:BAAALAAECgIIAgAAAA==.Thrallson:BAAALAAECgEIAQAAAA==.Thynaria:BAAALAADCggIDgAAAA==.',Ti='Tiros:BAAALAADCgMIAwAAAA==.',To='Tobenhorn:BAAALAAECgMIAwAAAA==.Tohunga:BAAALAADCgcIBwAAAA==.Tomcats:BAAALAADCgcIDAAAAA==.Tonitruum:BAAALAAFFAIIAgAAAA==.Topar:BAAALAADCgcICgAAAA==.',Tr='Treora:BAAALAAECgQICgAAAA==.Treyos:BAAALAADCggIAgABLAAECgUIBgABAAAAAA==.Trogadon:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.Trxl:BAAALAADCgcIAQAAAA==.',Ts='Tsunamí:BAAALAAECgQIBAAAAA==.',Ty='Tynsy:BAAALAADCgEIAQABLAADCgcIAQABAAAAAA==.',Tz='Tzutaka:BAABLAAECoEVAAIYAAgI2RicDACMAgAYAAgI2RicDACMAgAAAA==.',['Tå']='Tångø:BAAALAAECgMIBgAAAA==.',['Té']='Téras:BAAALAAECgYIDQAAAA==.',['Tí']='Tíll:BAAALAAECgUIBQABLAAECgYICwABAAAAAA==.Tísís:BAAALAAECgMIBgAAAA==.',Ub='Ubbysk:BAAALAAECgUIBQAAAA==.',Un='Unimok:BAAALAADCgQIBAABLAAECggIEwABAAAAAA==.',Us='Usain:BAAALAAECgYIEgAAAA==.',Va='Vaalhazak:BAAALAADCgEIAQAAAA==.Valrona:BAAALAAECggICAAAAA==.Vanshin:BAAALAAECgMIBgAAAA==.',Ve='Velez:BAAALAAECgYICwAAAA==.Vengotryan:BAAALAAECgUIBgAAAA==.',Vh='Vhoq:BAABLAAECoEWAAIFAAgIsx2KBgDTAgAFAAgIsx2KBgDTAgAAAA==.',Vi='Vitrasa:BAAALAAECgYICAAAAA==.',Vo='Vollbremsung:BAAALAAECgYICAAAAA==.',Vu='Vuhdo:BAAALAADCgMIAwAAAA==.',Vy='Vyver:BAAALAAECgYICwAAAA==.',['Vâ']='Vânessâ:BAAALAADCgIIAgABLAAFFAIIAgABAAAAAA==.',Wa='Waaghrior:BAAALAAECgYICQAAAA==.Watchdogman:BAAALAADCgcICQAAAA==.',Wh='Wheàtley:BAAALAAECgYIDAAAAA==.Whitej:BAAALAADCggIDwAAAA==.',Wi='Wickedßick:BAAALAAECgYICwAAAA==.Wisdomplz:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.',Xa='Xan:BAAALAADCgcIBwABLAAECgQIBQABAAAAAA==.',Xi='Xiaotore:BAAALAADCggIDwAAAA==.Xinis:BAAALAAECgYIBgAAAA==.',Xq='Xqtr:BAAALAADCgcIBwAAAA==.',Xs='Xshiro:BAAALAAECgMIAwAAAA==.',Xz='Xztrazer:BAAALAAECgYICgAAAA==.',['Xâ']='Xârion:BAAALAADCgcIDQAAAA==.',Ya='Yakari:BAAALAADCgMIAwAAAA==.',Yd='Ydraeth:BAAALAAECgIIAgABLAAFFAMIBgAJAModAA==.',Ye='Yelan:BAAALAAECgIIAwAAAA==.',Yl='Yllari:BAAALAADCggICwAAAA==.',Ys='Ysande:BAAALAAECgIIAgAAAA==.Yschara:BAAALAAECgMIAwAAAA==.Yserax:BAAALAAECgMIBAAAAA==.',Yu='Yukiina:BAAALAAECgcIDwAAAA==.Yunalesca:BAAALAADCgYIBgAAAA==.Yuzuy:BAABLAAECoEbAAMNAAgICRlUCQAmAgANAAgICRlUCQAmAgAEAAcIPAh0GABMAQAAAA==.',Za='Zansoa:BAAALAAECgQICAABLAAECgYIBgABAAAAAA==.',Ze='Zeatek:BAAALAAECgYICAAAAA==.Zedrus:BAAALAAFFAIIAgAAAA==.Zeitgeist:BAAALAADCggIDAAAAA==.Zencor:BAAALAAECgEIAQABLAAECgYIDgABAAAAAA==.Zeri:BAAALAADCgMIAwAAAA==.Zeroqxyx:BAAALAADCggICAAAAA==.Zevii:BAAALAAECgIIBAAAAA==.',Zh='Zhuul:BAAALAAECgIIAgAAAA==.',Zu='Zulrín:BAACLAAFFIEJAAIaAAQIFhpmAAAcAQAaAAQIFhpmAAAcAQAsAAQKgRYAAhoACAj+JWMAAFoDABoACAj+JWMAAFoDAAAA.Zusaki:BAAALAAECgQIAwAAAA==.',Zw='Zwarizath:BAAALAADCgEIAQAAAA==.Zwirbelbob:BAAALAAECggIEwAAAA==.',['Zé']='Zékkén:BAAALAAECgIIAgABLAAFFAMIBgAJAModAA==.',['Zø']='Zørtek:BAAALAADCgQIBAAAAA==.',['Zû']='Zûâ:BAAALAADCggIFAAAAA==.',['Âr']='Ârgôn:BAAALAADCgQIBAAAAA==.',['Âs']='Âsuná:BAAALAAECgIIAwAAAA==.',['Âu']='Âurexromeos:BAAALAADCggIEQAAAA==.',['În']='Învoker:BAAALAAECgQICgAAAA==.',['Ðr']='Ðrache:BAAALAAECgYICQAAAA==.',['Üb']='Überbreit:BAAALAADCgcIDgAAAA==.Übergriffig:BAAALAADCggIEAABLAAECgIIAwABAAAAAA==.',['ßl']='ßlades:BAAALAAECgYICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end