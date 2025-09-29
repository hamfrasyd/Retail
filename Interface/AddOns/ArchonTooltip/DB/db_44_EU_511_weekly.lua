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
 local lookup = {'Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Paladin-Retribution','Priest-Holy','Priest-Shadow','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Warlock-Affliction','Hunter-Marksmanship','DemonHunter-Havoc','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','Unknown-Unknown','Paladin-Holy','Warrior-Fury','Shaman-Enhancement','Druid-Feral','Paladin-Protection','Rogue-Subtlety','Rogue-Assassination','Shaman-Elemental','Druid-Guardian','Evoker-Preservation','Evoker-Augmentation','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Frost','Mage-Frost','Evoker-Devastation','Priest-Discipline','DeathKnight-Blood',}; local provider = {region='EU',realm='Tyrande',name='EU',type='weekly',zone=44,date='2025-09-25',data={Ab='Abso:BAABLAAECoEmAAMBAAcIFiPfHABPAgABAAcIFiPfHABPAgACAAIIrRJvqwBWAAAAAA==.',Ac='Acascarlo:BAAALAADCgcIDgAAAA==.',Ad='Adelfus:BAAALAADCggIDQAAAA==.Adelram:BAAALAAECgEIAQAAAA==.',Ae='Aerlín:BAABLAAECoEZAAIDAAcIuQegqgArAQADAAcIuQegqgArAQAAAA==.',Af='Africana:BAAALAADCgcIDQAAAA==.',Ag='Agnoba:BAAALAADCgYIBgAAAA==.',Ah='Ahdala:BAAALAAECgMIAwAAAA==.',Ai='Aidil:BAAALAAECgIIAgAAAA==.',Aj='Ajnp:BAAALAAECgYIDgAAAA==.',Ak='Akhubadain:BAAALAAECgcIDQAAAA==.Akodiña:BAABLAAECoEXAAIEAAcIEQNCAAG1AAAEAAcIEQNCAAG1AAAAAA==.',Al='Alesra:BAAALAADCgcIBwAAAA==.Alesta:BAAALAADCggIFAAAAA==.Alexselygos:BAAALAADCggICAAAAA==.Algar:BAAALAADCgYIBgAAAA==.Almôsteasy:BAAALAAECgcIEgAAAA==.Alontar:BAAALAAECgEIAQAAAA==.Altamiro:BAAALAADCgEIAQAAAA==.Altema:BAAALAAECgQIBgAAAA==.Alëxandêr:BAAALAAECgYICQAAAA==.Alücard:BAAALAADCgcIBwAAAA==.',Am='Amaräntha:BAABLAAECoEZAAIFAAcIOgYnaAAdAQAFAAcIOgYnaAAdAQAAAA==.',An='Anapinmes:BAABLAAECoEaAAIDAAcI/hCjfwB/AQADAAcI/hCjfwB/AQAAAA==.Ankhansunamu:BAACLAAFFIEFAAIFAAIIzhGYIQCWAAAFAAIIzhGYIQCWAAAsAAQKgSsAAwUACAhXGwkbAH0CAAUACAhXGwkbAH0CAAYAAghWCPl8AGUAAAAA.Ansee:BAAALAADCggIEgAAAA==.Ansset:BAAALAAECgYICwAAAA==.Anuel:BAAALAAECgcIDAAAAA==.',Ar='Arachy:BAAALAAECgcIEAAAAA==.Aradoiel:BAAALAAECgMIAwAAAA==.Aranith:BAAALAADCgcIBwAAAA==.Arendelle:BAAALAADCgQIBAAAAA==.Aristhos:BAAALAADCggIFwAAAA==.Ariâlyn:BAAALAAECgQIBAAAAA==.Arkey:BAABLAAECoEkAAMCAAgI6BRKMgDmAQACAAgI6BRKMgDmAQABAAQINw1laADOAAAAAA==.Armadura:BAABLAAFFIEFAAIHAAIIeRBCFQB/AAAHAAIIeRBCFQB/AAAAAA==.Arnoll:BAAALAADCggIEAAAAA==.Artak:BAAALAAECgYIEQAAAA==.Arterocaza:BAAALAADCgYIBgAAAA==.Arterotitan:BAAALAAECgMIBQAAAA==.Artiel:BAAALAAECgYIDQAAAA==.Arzarissa:BAAALAAECggICAAAAA==.',As='Ashasoryu:BAAALAAECgYIDAAAAA==.Asptronomo:BAAALAADCggICQAAAA==.Assborr:BAAALAAECgEIAQAAAA==.Assokâ:BAAALAAECgIIBQAAAA==.Astrodruid:BAAALAAECgMIAwAAAA==.Astárte:BAAALAADCgMIAwAAAA==.Asumo:BAAALAAECgEIAQAAAA==.',At='Athom:BAAALAAECgQIBwAAAA==.Athätriel:BAABLAAECoEeAAMIAAgIXwtrYgCWAQAIAAgIXwtrYgCWAQAJAAEIDAOdkAAUAAAAAA==.Athøs:BAAALAAECgQIAwAAAA==.Atriumvestæ:BAAALAAECgEIAQAAAA==.',Au='Ausentë:BAAALAAECgEIAQAAAA==.',Ax='Axelkrog:BAAALAADCgMIAwAAAA==.',Ay='Ayashi:BAABLAAECoEYAAIKAAgIFBBOZQCMAQAKAAgIFBBOZQCMAQAAAA==.Ayperos:BAABLAAECoEWAAILAAYIORO+EACJAQALAAYIORO+EACJAQAAAA==.',Az='Azug:BAAALAAECgYICAAAAA==.',['Aè']='Aèto:BAABLAAECoEYAAMMAAYIMx4BKwAIAgAMAAYIMx4BKwAIAgADAAEI1gWAGgEuAAAAAA==.',Ba='Bakayaro:BAACLAAFFIEFAAIBAAIIgguDGACIAAABAAIIgguDGACIAAAsAAQKgSkAAgEACAiuHacUAJwCAAEACAiuHacUAJwCAAAA.Baligos:BAAALAADCgYIBgAAAA==.Baltorus:BAABLAAECoEjAAINAAcIiA63hgCKAQANAAcIiA63hgCKAQAAAA==.Banconcial:BAAALAAECgQIBAAAAA==.Basön:BAAALAADCgIIAgAAAA==.',Be='Beastcall:BAAALAADCggIDwAAAA==.Beaxela:BAAALAAECgYICQAAAA==.Bedonia:BAAALAADCgIIAgAAAA==.Beduja:BAABLAAECoEgAAIIAAYIIQVToADoAAAIAAYIIQVToADoAAAAAA==.Begimo:BAAALAAECgIIAgAAAA==.Belialuin:BAAALAAECgYIDAAAAA==.Beliel:BAAALAADCgUIAQAAAA==.Bemezor:BAAALAAECgUIAQAAAA==.Berrny:BAAALAAECgYIEgAAAA==.Berïel:BAAALAADCggIIgAAAA==.Besfala:BAAALAAECgYIEAAAAA==.Betzabel:BAAALAADCgYIBgAAAA==.',Bl='Blackpanter:BAAALAAECgEIAQAAAA==.Blackpapet:BAAALAAECgIIAgAAAA==.Blancosinmas:BAAALAAECgIIAwAAAA==.Blankosinmas:BAAALAAECggICAAAAA==.Blied:BAAALAADCgcIDQAAAA==.Blindkeeper:BAABLAAECoERAAIOAAcI7AgzDgBZAQAOAAcI7AgzDgBZAQAAAA==.Bloodgarm:BAAALAADCgUIBQAAAA==.Bloodwyn:BAAALAADCgYIBgABLAAECgcIGwADAKogAA==.',Bo='Boar:BAAALAAECgcIDgAAAA==.Boligrafo:BAAALAADCggICgAAAA==.Bombonbum:BAACLAAFFIELAAIPAAMIZhclBwDzAAAPAAMIZhclBwDzAAAsAAQKgRwAAw8ACAi5GgQMAIACAA8ACAi5GgQMAIACABAABQicFOMzAD0BAAAA.Borjacosta:BAABLAAECoEeAAMMAAcI6RpxKQASAgAMAAcI0BpxKQASAgADAAIIKxqG8wB3AAAAAA==.',Br='Brago:BAAALAAECgYIEgAAAA==.Brahum:BAAALAAECgMIAwABLAAECgMIAwARAAAAAA==.Brighteye:BAAALAADCgYIBgAAAA==.Briseïda:BAAALAAECgYIBgAAAA==.Brujoo:BAAALAADCgYIBgAAAA==.',Bu='Bubblechick:BAAALAAECgYIEAAAAA==.Buruthor:BAAALAAECggIEwAAAA==.',By='Byakkur:BAABLAAECoEeAAIQAAgI7RigEgBfAgAQAAgI7RigEgBfAgAAAA==.',['Bâ']='Bâmbelvi:BAAALAAECgIIAgAAAA==.',['Bø']='Børder:BAAALAADCggICAAAAA==.',['Bü']='Bünnyy:BAAALAADCgEIAQAAAA==.',Ca='Caelid:BAAALAADCgYIBwABLAAECggIKAASANgUAA==.Caerroil:BAABLAAECoEfAAITAAgI7w01WwCmAQATAAgI7w01WwCmAQAAAA==.Calens:BAAALAADCgUIBQAAAA==.Calîoppe:BAAALAADCgMIAwAAAA==.Canach:BAABLAAECoEpAAIDAAgILhyHNQBGAgADAAgILhyHNQBGAgAAAA==.Capirote:BAAALAADCgcIBwAAAA==.Carmandt:BAAALAAECgMICAAAAA==.Carmandtf:BAAALAAECgQIBAAAAA==.Carmannd:BAAALAADCgYIBQAAAA==.Carrerá:BAAALAAECgIIAgAAAA==.Cassioplea:BAAALAADCgUIBQAAAA==.Caylena:BAAALAADCgcICwAAAA==.Cazatotos:BAAALAADCggICAAAAA==.',Ce='Cesair:BAAALAADCgMIAwAAAA==.',Ch='Chaminita:BAAALAAECgQICwABLAAECggIIwAUAJsZAA==.Chanyboyito:BAAALAAECgYIBgAAAA==.Chariizard:BAAALAAECgEIAQABLAAECgYIEgARAAAAAA==.Chartrass:BAAALAAECgQICwAAAA==.Chekevareske:BAAALAAECgUIBQABLAAECgcIHgAMAOkaAA==.Cherrim:BAABLAAECoEtAAMVAAgIdRQEEQAZAgAVAAgIdRQEEQAZAgACAAMIVQRwqwBWAAAAAA==.Chets:BAAALAAECgMIAwAAAA==.Chorra:BAAALAAECgEIAQAAAA==.',Ci='Cires:BAAALAAECgYICQAAAA==.',Cl='Clak:BAAALAAECgYIBgABLAAECgcIGwADAKogAA==.Clarck:BAAALAADCgcIDAAAAA==.',Co='Colorwar:BAAALAAECgIIAgABLAAECggIHgAWAGIcAA==.Colthan:BAAALAAECgcIBwAAAA==.Colágenö:BAAALAAECgIIAwAAAA==.Comeniños:BAABLAAECoEdAAIBAAgIjBr6HwA2AgABAAgIjBr6HwA2AgAAAA==.',Cr='Crisfer:BAAALAAECgUICwAAAA==.Crookedarrow:BAAALAADCggIGwAAAA==.Crìím:BAAALAADCggICgAAAA==.',Da='Dablas:BAAALAAECgYICQAAAA==.Daeghun:BAAALAAECgYIDAAAAA==.Daenay:BAAALAAECggIEQAAAA==.Dahell:BAAALAADCggICAAAAA==.Dajjal:BAAALAAECgIIAwAAAA==.Damaso:BAAALAADCgQIAgAAAA==.Daphna:BAAALAADCgQIBAAAAA==.Darkand:BAAALAAECgcIDgAAAA==.Darkarius:BAAALAAECgUICAAAAA==.Darkatlantia:BAAALAAECgcIDwAAAA==.Darkmáximus:BAAALAAECgYICwAAAA==.Darksouw:BAAALAADCgUIBQAAAA==.Darthemisa:BAAALAADCggICAAAAA==.Darzakesh:BAAALAAECgYIBgABLAAECgcIKwARAAAAAA==.Dawa:BAAALAAECgcIDwAAAA==.Dayl:BAAALAADCgMIAwAAAA==.Daígotsu:BAAALAAECgUIBgAAAA==.',De='Delgui:BAAALAAECgEIAQAAAA==.Demonjake:BAAALAADCgMIAwAAAA==.Demonyxa:BAAALAAECggICAAAAA==.Dertipincha:BAABLAAECoEeAAMXAAcI7BwKDgAuAgAXAAcIXBoKDgAuAgAYAAUIARrLPABQAQAAAA==.Despair:BAAALAAECggIBgAAAA==.',Dh='Dhael:BAAALAADCgYIBAAAAA==.',Di='Diegospicy:BAABLAAECoEVAAIZAAYIHQnzbwAxAQAZAAYIHQnzbwAxAQAAAA==.Dinzi:BAAALAADCgYIBgAAAA==.Diosamadre:BAAALAADCgUIBQAAAA==.',Do='Douluc:BAAALAADCgMIAwABLAAECgIIBAARAAAAAA==.',Dr='Draeliâ:BAAALAAECgEIAQAAAA==.Dranza:BAABLAAECoEgAAIEAAcItRdBdQDPAQAEAAcItRdBdQDPAQAAAA==.Drinchita:BAAALAAECgEIAQAAAA==.Drìadas:BAAALAAECgUICwAAAA==.',Du='Durexcontrol:BAAALAADCgIIAgAAAA==.',Dw='Dwal:BAAALAAECgMIAwAAAA==.',Dy='Dyrinia:BAABLAAECoEUAAMZAAcIiQldXgBsAQAZAAcIiQldXgBsAQAKAAIIfwh/BQFAAAAAAA==.',['Dá']='Dávíd:BAAALAADCggIDwAAAA==.',['Dä']='Därckness:BAAALAAECgIIAgAAAA==.',['Dè']='Dèsko:BAAALAAECgYIDgAAAA==.',Ea='Eaden:BAAALAADCgIIAgAAAA==.Eaglesrojod:BAABLAAECoElAAMVAAcIGBWvFgDOAQAVAAcIGBWvFgDOAQAaAAMIkgeoJwBjAAAAAA==.',Ec='Ecotone:BAABLAAECoEgAAMbAAgIESLDAgAZAwAbAAgIESLDAgAZAwAcAAQIzhDCDwDtAAAAAA==.',Ei='Eiliv:BAAALAAECgYICQAAAA==.Einrrick:BAAALAAECgYIBQAAAA==.',El='Elana:BAAALAADCgcIBwAAAA==.Elfric:BAABLAAECoEbAAIDAAcIqiAEMQBYAgADAAcIqiAEMQBYAgAAAA==.Elledan:BAAALAADCgYIAwABLAAECgcIGwADAKogAA==.Elrond:BAABLAAECoEcAAIBAAYIFB9KKAD/AQABAAYIFB9KKAD/AQABLAAECgcIGwADAKogAA==.Eltiopepe:BAABLAAECoEZAAMQAAYIRRWzJwCSAQAQAAYIRRWzJwCSAQAPAAMIiAbRQABiAAAAAA==.Elumami:BAABLAAECoEVAAIdAAgIMxUAPQA4AgAdAAgIMxUAPQA4AgAAAA==.Elunelle:BAAALAAECgMIAwAAAA==.Elñocas:BAAALAAECgQIBAAAAA==.',Em='Empireon:BAAALAADCggIFgAAAA==.',Er='Ereishkigal:BAAALAAECggICAABLAAECggIGwATADshAA==.Eriba:BAAALAAECgcIDQAAAA==.Erickgos:BAAALAADCggICgAAAA==.Ermadeon:BAAALAADCgcIDgAAAA==.Erodillen:BAABLAAECoEaAAMeAAcIGxnhFwDVAQAeAAcIGxnhFwDVAQANAAMIvgw58ACSAAAAAA==.',Es='Escorbutopia:BAAALAADCgcIDQAAAA==.Esfolada:BAAALAADCgcIBwAAAA==.Estoimuiover:BAAALAAECgQICAAAAA==.',Ev='Evilzack:BAAALAADCgIIAgAAAA==.',Ez='Ezis:BAAALAADCggICAAAAA==.',['Eí']='Eír:BAABLAAECoEpAAIKAAgIgCFTDADuAgAKAAgIgCFTDADuAgAAAA==.',Fa='Faneka:BAAALAADCgUIBQABLAAECgcIDQARAAAAAA==.Farald:BAAALAADCggIFgABLAAECggIKQADAC4cAA==.',Fe='Feel:BAAALAADCgcIDgAAAA==.Feltos:BAAALAAECgUICgAAAA==.',Fi='Fiifii:BAAALAAECgYIDQABLAAECggIDwARAAAAAA==.Firesoul:BAAALAADCgcICwAAAA==.',Fl='Floria:BAAALAADCgQIBAAAAA==.Florä:BAAALAADCggICAAAAA==.',Fo='Formas:BAABLAAECoEfAAIaAAcIShlLCgALAgAaAAcIShlLCgALAgAAAA==.',Fr='Frankiless:BAAALAADCggIDwAAAA==.Fror:BAAALAAECgQIAQAAAA==.',Fu='Fullshamy:BAAALAAECgEIAQAAAA==.Fumme:BAAALAAECgMIBQAAAA==.Furfur:BAAALAADCgYIBgAAAA==.Fuzu:BAAALAAECgYIBgAAAA==.',['Fø']='Førmas:BAAALAADCggICAAAAA==.',Ga='Gabrantthh:BAAALAAECgYIEwAAAA==.Gabrieljdv:BAAALAADCggICAAAAA==.Gaijins:BAAALAAECggIEAAAAA==.Galâtëa:BAAALAADCggIGQAAAA==.Gargath:BAAALAAECgYIEAABLAAECgcIGwADAKogAA==.Gattssu:BAAALAADCgIIAgAAAA==.Gaviscon:BAAALAADCgcIBwAAAA==.',Ge='Gelote:BAAALAAECgIIAgAAAA==.Gerald:BAAALAADCgcIFgABLAADCggIDQARAAAAAA==.',Gh='Ghordocabron:BAAALAADCgYICAAAAA==.',Gi='Gino:BAAALAADCgEIAQAAAA==.',Gl='Glacsí:BAAALAADCgYICgAAAA==.',Go='Gobla:BAAALAAECgcIBQAAAA==.Gohku:BAAALAAECgMIAwABLAAECgQIBwARAAAAAA==.Gozadora:BAAALAAECgYIDAAAAA==.',Gu='Gudmund:BAAALAAECgYIDAAAAA==.Guilaila:BAAALAADCggIDwAAAA==.Guqnir:BAABLAAECoEgAAIDAAgIRR01IwCXAgADAAgIRR01IwCXAgAAAA==.',['Gú']='Gúldàn:BAAALAAECgYIEAAAAA==.',Ha='Hakalock:BAAALAADCggICAAAAA==.Hansis:BAAALAADCgUIAQAAAA==.Haukr:BAAALAADCggICAAAAA==.Haydeé:BAAALAAECgMIAwAAAA==.Hazzani:BAAALAAECgYICgAAAA==.',He='Hectordo:BAABLAAECoEmAAIfAAgI3CBnJAC9AgAfAAgI3CBnJAC9AgAAAA==.Heikono:BAAALAAECgYIBgAAAA==.Hekatormenta:BAAALAAECgcIBwAAAA==.Helzvog:BAAALAAECgYIEQAAAA==.Hengist:BAAALAADCgMIAwABLAAECgcIGwADAKogAA==.Herboristero:BAAALAADCggICAAAAA==.Hermion:BAAALAADCgYIBgAAAA==.Heëll:BAAALAADCggICwAAAA==.',Hi='Hideyoshi:BAAALAAECgUICQAAAA==.Hilgarri:BAAALAAECgUICAAAAA==.',Hl='Hleyf:BAABLAAECoEcAAIWAAcIGBFdKwBoAQAWAAcIGBFdKwBoAQAAAA==.',Ho='Hollow:BAAALAAECgYIDQAAAA==.',Hy='Hyng:BAAALAADCggIHQAAAA==.Hyperbor:BAAALAAECgMIAwABLAAECgcIIQAgAD0PAA==.Hyperspain:BAABLAAECoEhAAIgAAcIPQ/dOABpAQAgAAcIPQ/dOABpAQAAAA==.Hyrmatia:BAAALAADCggIDwAAAA==.',['Hé']='Héroder:BAAALAADCgYIBgAAAA==.',['Hô']='Hôrusin:BAAALAAECgYIEAAAAA==.',Ib='Ibisol:BAABLAAECoEdAAITAAcIhxudNgApAgATAAcIhxudNgApAgAAAA==.',Ic='Ictus:BAAALAAECgYIBgAAAA==.',Ig='Igneelya:BAAALAADCggICwABLAAECgYIBgARAAAAAA==.',Ik='Iki:BAAALAAECgIIAgAAAA==.',Il='Illiscar:BAABLAAECoEeAAMeAAcIEh30EgAQAgAeAAcIeRz0EgAQAgANAAYI5hmVYwDVAQAAAA==.Illiye:BAAALAAECgMIBAABLAAECgQIBwARAAAAAA==.Ilmatar:BAABLAAECoEbAAIMAAYIsBTpSQB0AQAMAAYIsBTpSQB0AQABLAAECggIKQAKAIAhAA==.Ilmáter:BAAALAAECgYIBgAAAA==.',In='Instanity:BAAALAADCggIEQABLAAECgcIHgAXAOwcAA==.Inyäuke:BAAALAADCgEIAQAAAA==.',Ir='Iroas:BAAALAAECgMIAQAAAA==.Irukä:BAAALAADCggIFAAAAA==.',Is='Ishialert:BAAALAADCgUIBQAAAA==.',It='Ithilien:BAAALAADCggIEgAAAA==.',Ja='Jamvius:BAAALAAECgYIBgABLAAECgYICwARAAAAAA==.Jarraypedal:BAAALAAECgIIAgAAAA==.Javitukss:BAAALAADCgUIBQAAAA==.Jazari:BAAALAADCgQIBQAAAA==.',Jm='Jmlee:BAAALAADCgMIAwAAAA==.',Jo='Joaquin:BAAALAAECgYIDQAAAA==.Johnatan:BAAALAAECgIIAgAAAA==.Joness:BAABLAAECoEZAAIEAAYIkBzgZADxAQAEAAYIkBzgZADxAQAAAA==.Joseartero:BAAALAAECgYICAAAAA==.',Ju='Juli:BAAALAADCggICAAAAA==.',['Jä']='Jäké:BAAALAAECgYIDQAAAA==.',Ka='Kaballerete:BAAALAAECggIBQAAAA==.Kaceus:BAAALAADCggIDwAAAA==.Kagetsunu:BAAALAADCggIFQAAAA==.Kalesy:BAAALAAECgcIEgAAAA==.Kallypsso:BAAALAADCgEIAQAAAA==.Kalus:BAABLAAECoElAAIFAAcI2BofKAAqAgAFAAcI2BofKAAqAgAAAA==.Kanela:BAABLAAECoEXAAIBAAgItwtyTwBAAQABAAgItwtyTwBAAQAAAA==.Karlfury:BAAALAAECgcIAQAAAA==.',Ke='Kernos:BAAALAAECgYICwAAAA==.Keroseno:BAAALAAECgMIAwAAAA==.Kethrox:BAAALAADCgIIAgAAAA==.Keyrou:BAAALAAECgYICAAAAA==.',Kh='Khalegon:BAABLAAECoEUAAIBAAgIkRLFKQD2AQABAAgIkRLFKQD2AQAAAA==.Khandrik:BAAALAAECgIIAgAAAA==.Kharrigan:BAAALAADCggICAAAAA==.Khast:BAAALAAECgIIAgABLAAECggIKAANAD0jAA==.Khinn:BAABLAAECoEoAAINAAgIPSNAFAAHAwANAAgIPSNAFAAHAwAAAA==.',Ki='Kiva:BAABLAAECoElAAIKAAgIrBVVQwDsAQAKAAgIrBVVQwDsAQAAAA==.',Ko='Koeus:BAABLAAECoEWAAIKAAYIuA+IjwAmAQAKAAYIuA+IjwAmAQAAAA==.Kogmoyed:BAABLAAECoEVAAMIAAgIuR09NQA5AgAIAAgIuhU9NQA5AgALAAQIbSA9FABZAQAAAA==.Kohäck:BAAALAADCggIFwAAAA==.Koldoabalos:BAAALAADCgMIAwAAAA==.Komodona:BAABLAAECoEcAAIhAAgIIQ8nJgDLAQAhAAgIIQ8nJgDLAQAAAA==.Kouranuruhay:BAAALAAECgYIBgAAAA==.',Kp='Kpazatio:BAAALAADCgQIBwAAAA==.',Kr='Krahtos:BAAALAAECgIIAwABLAAECgQIBwARAAAAAA==.',Ku='Kuhlturista:BAAALAAECgMIAwAAAA==.Kurudruida:BAAALAAECgIIAwAAAA==.Kusin:BAAALAAECgEIAQAAAA==.',Ky='Kysle:BAABLAAECoEoAAIEAAgI2iLpGAD3AgAEAAgI2iLpGAD3AgAAAA==.Kytäna:BAAALAAECgYICwAAAA==.',['Kí']='Kínnara:BAAALAAECgcIDQAAAA==.',['Kø']='Køtec:BAAALAAECgYIBgAAAA==.',La='Lab:BAAALAAECgYIDAAAAA==.Lademonio:BAAALAADCggIIgAAAA==.Lainobeltz:BAAALAADCgcIBwAAAA==.Lakamal:BAAALAAECgEIAQAAAA==.Lalaby:BAAALAAECgMIAwAAAA==.Lantecurios:BAAALAAECgYIEAAAAA==.Larrydc:BAABLAAECoEVAAIIAAcIzhgdPwAOAgAIAAcIzhgdPwAOAgAAAA==.Lasciel:BAAALAADCggICAAAAA==.Lasnas:BAAALAAECgEIAQAAAA==.Lawjack:BAAALAAECggICAAAAA==.Laën:BAABLAAECoEUAAIdAAYIdBpDWADcAQAdAAYIdBpDWADcAQAAAA==.',Ld='Ldark:BAAALAAECgMIAwAAAA==.',Le='Leidycruel:BAAALAADCggIEgAAAA==.Leiä:BAAALAAECgcIEAAAAA==.Lestrange:BAAALAADCgEIAQAAAA==.Leynda:BAAALAAECggIDAAAAA==.',Li='Lightwar:BAAALAADCgcIBwABLAAECggIHgAWAGIcAA==.Ligthstar:BAAALAAECgEIAQAAAA==.Lirah:BAAALAAECgMIBAAAAA==.Lish:BAAALAADCgMIAwAAAA==.',Lm='Lmeentxz:BAAALAADCgYIBgAAAA==.',Lo='Lobog:BAACLAAFFIEFAAIBAAIIzAuhGACIAAABAAIIzAuhGACIAAAsAAQKgScAAgEACAggH1oWAIoCAAEACAggH1oWAIoCAAAA.Loha:BAABLAAECoEWAAICAAYIawvocgD+AAACAAYIawvocgD+AAAAAA==.Lokemo:BAAALAADCgYIBQAAAA==.Lolawer:BAAALAAECgMIAwAAAA==.Lomonegro:BAAALAAECgYICAAAAA==.Loring:BAAALAADCggIFQAAAA==.Lorxen:BAAALAADCgIIAgAAAA==.Lostbeast:BAAALAADCgUIBwAAAA==.',Lu='Luký:BAAALAAECgUIBQABLAAECgUIDAARAAAAAA==.Lukÿ:BAAALAAECgUIDAAAAA==.Lunaia:BAAALAAECgIIAgAAAA==.Lupodeath:BAAALAADCgEIAQABLAAECgUIBgARAAAAAA==.Lurmyr:BAAALAAECgYIEAAAAA==.',Ly='Lyanta:BAAALAAECgYIBgABLAAECgcIKwARAAAAAA==.Lydriet:BAAALAADCgcIBwAAAA==.Lykensen:BAAALAADCgEIAQAAAA==.Lylaeth:BAABLAAECoEcAAIDAAcI2CCjLQBlAgADAAcI2CCjLQBlAgAAAA==.Lylhet:BAAALAADCggICwAAAA==.',['Lé']='Léfat:BAAALAAECgMIBQAAAA==.',['Lë']='Lëeloo:BAAALAADCgcIDAABLAAECgYICwARAAAAAA==.',['Lö']='Löwe:BAAALAAECgUICgAAAA==.',['Lø']='Løckprøcdøtt:BAAALAAECgYIDwAAAA==.',Ma='Macizza:BAAALAAECgYIEAAAAA==.Madalena:BAAALAADCgUIBQAAAA==.Madamecurie:BAAALAAECgMIAwAAAA==.Madness:BAAALAAECgcICAABLAAECgcIHgAXAOwcAA==.Magufo:BAAALAAECggIEQABLAAECggIGwATADshAA==.Mailoc:BAAALAADCgQIBAAAAA==.Malakøi:BAAALAADCgcIBwAAAA==.Mandrágore:BAAALAADCggIEAAAAA==.Mangarran:BAAALAAECgYICwAAAA==.Maninda:BAAALAAECgMIBAAAAA==.Maniotas:BAAALAADCggIFAAAAA==.Maokun:BAABLAAECoEoAAIQAAgIIB1pDQCkAgAQAAgIIB1pDQCkAgAAAA==.Margón:BAAALAAECggIEgAAAA==.Markez:BAAALAAECgUIAQAAAA==.Marymary:BAAALAADCggICAAAAA==.Mas:BAAALAAECgIIAQAAAA==.Matapatos:BAAALAADCggIDwAAAA==.Mawik:BAAALAADCgIIAgAAAA==.',Mc='Mcabro:BAAALAAECgYIBgABLAAECggIHgAWAGIcAA==.',Me='Mecmec:BAAALAADCgUICAAAAA==.Meleys:BAAALAAECgcIDwAAAA==.Melindá:BAAALAADCgYICAAAAA==.Melith:BAAALAAECgEIAQAAAA==.Menfís:BAAALAAECgYICAAAAA==.Methor:BAABLAAECoEjAAQiAAgIzw/mDwB2AQAFAAgIgwwCRgCZAQAiAAcIcxDmDwB2AQAGAAMIrQIIiAA7AAAAAA==.',Mi='Micosin:BAAALAAECgcIDgAAAA==.Miladymarisa:BAAALAAECgcICAAAAA==.Milock:BAABLAAECoEVAAIIAAYIngTboADmAAAIAAYIngTboADmAAAAAA==.Minze:BAABLAAECoEWAAIKAAYI7h8TNAAfAgAKAAYI7h8TNAAfAgAAAA==.Miradetras:BAAALAADCgEIAQAAAA==.Mitsumi:BAABLAAECoEZAAIgAAcIUghEPQBWAQAgAAcIUghEPQBWAQAAAA==.Miudiña:BAAALAADCgMIAgAAAA==.',Mo='Moildraf:BAAALAAECgcIEgAAAA==.Momolly:BAACLAAFFIEFAAIZAAIILCGSFADFAAAZAAIILCGSFADFAAAsAAQKgTAAAhkACAh1It0MABcDABkACAh1It0MABcDAAAA.Morcega:BAAALAAECgQIBAAAAA==.Morguis:BAAALAAECgIIAgAAAA==.Morthîs:BAAALAADCgMIAwAAAA==.Morti:BAAALAAECgcIEQAAAA==.Mottiix:BAAALAADCggICAAAAA==.',Mu='Muelita:BAABLAAFFIEFAAIDAAII+BDELgCMAAADAAII+BDELgCMAAAAAA==.Muffinz:BAAALAAECgcICgABLAAECggIGwATADshAA==.Murph:BAAALAADCgQIBAAAAA==.Mustakrakïsh:BAABLAAECoEuAAIEAAgIMg9NcwDTAQAEAAgIMg9NcwDTAQAAAA==.',My='Mylet:BAAALAADCgYIBgAAAA==.Mythbusters:BAAALAAECgcIEwAAAA==.',['Má']='Máxdark:BAAALAADCggICwAAAA==.Máxica:BAAALAAECgYIDAAAAA==.',['Mä']='Mälakøi:BAAALAAECgEIAQAAAA==.Mänbrü:BAAALAAECgMIAwAAAA==.',['Mé']='Médici:BAABLAAECoElAAIFAAcIVhNgTQB8AQAFAAcIVhNgTQB8AQAAAA==.',['Më']='Mërchan:BAAALAAECgYICwAAAA==.',['Mì']='Mìnos:BAAALAADCggIDQAAAA==.',['Mï']='Mïcha:BAAALAAECgUIDgAAAA==.',['Mü']='Mürtägh:BAAALAAECgQIBAABLAAECgYIEgARAAAAAA==.',Na='Nahuala:BAAALAADCggIEAAAAA==.Naomhy:BAABLAAECoEVAAMEAAgIswvJhACxAQAEAAgIswvJhACxAQAWAAIIRAIAAAAAAAAAAA==.Narfi:BAAALAADCggIFQAAAA==.Naskas:BAAALAAECgYIDQAAAA==.Natsull:BAABLAAECoEpAAIMAAgIUhOxNQDNAQAMAAgIUhOxNQDNAQAAAA==.',Ne='Neferpitou:BAAALAAECgEIAQAAAA==.Neolidas:BAAALAAECgYICgAAAA==.Neozed:BAAALAAECgQIAQAAAA==.Nephtyes:BAAALAAECgIIAwAAAA==.Nerisdormi:BAAALAADCggIFAAAAA==.',Ni='Nikini:BAAALAAECgUIDAABLAAECgcIEQARAAAAAA==.Ninjawarior:BAAALAADCgQIBAAAAA==.',No='Nokron:BAABLAAECoEeAAIbAAcIOw+HHABVAQAbAAcIOw+HHABVAQABLAAECggIKAASANgUAA==.Nolan:BAAALAADCgIIAgAAAA==.Noor:BAABLAAECoEfAAIFAAcI4A2KTQB7AQAFAAcI4A2KTQB7AQAAAA==.Noreline:BAAALAAECgYICAAAAA==.Norlum:BAAALAADCgQIBgAAAA==.Notdïe:BAAALAAECgEIAQAAAA==.',Nr='Nr:BAAALAAECgQIBAAAAA==.',['Nÿ']='Nÿxa:BAAALAAECgEIAgAAAA==.',Ob='Obsydian:BAAALAAECgYIEAAAAA==.',Oi='Oieminegro:BAAALAAECgUICwAAAA==.',Ok='Okotto:BAAALAADCgcIBwAAAA==.',Om='Omen:BAAALAAECgMIAwAAAA==.',Or='Oralva:BAAALAADCggIDAAAAA==.Orballa:BAAALAADCggIBQABLAADCggIFAARAAAAAA==.Orkde:BAABLAAECoEYAAIKAAgIRg1hgQBFAQAKAAgIRg1hgQBFAQAAAA==.Orshabaal:BAAALAAECgIIAwAAAA==.Orïòn:BAABLAAECoEWAAITAAYIDBR2cABrAQATAAYIDBR2cABrAQAAAA==.',Ot='Ottís:BAAALAADCgcIDgAAAA==.',Ov='Ovalar:BAAALAADCgMIAwAAAA==.',Pa='Pacussa:BAAALAADCgUIBQAAAA==.Palakín:BAAALAADCgcICgAAAA==.Palanganator:BAAALAADCgMIBwAAAA==.Pandicius:BAAALAAECgIIAgABLAAFFAIIBQADAPgQAA==.Panzapanza:BAAALAADCgEIAQAAAA==.Paralilubiti:BAAALAADCggICAABLAAECggIJgALAB4VAA==.Parckys:BAAALAAECgYIDQAAAA==.Pathra:BAAALAADCggIDwAAAA==.',Pe='Pedrosanche:BAAALAADCgQIBAAAAA==.Pelahembras:BAAALAAECgYIDgABLAAECggIGwATADshAA==.Pelotiketo:BAABLAAECoEmAAQLAAgIHhUZDwCjAQAIAAgIZBTnPwALAgALAAYIRBMZDwCjAQAJAAMIFQePagCTAAAAAA==.Pelouzana:BAABLAAECoEcAAMdAAgIdRsKLgB5AgAdAAgIdRsKLgB5AgAgAAIIZQcOeQBEAAAAAA==.Percyman:BAAALAADCgEIAQAAAA==.Peri:BAAALAADCgcIBwAAAA==.Perretes:BAAALAADCggICAAAAA==.Petróleo:BAAALAADCggICAAAAA==.Pewzu:BAAALAADCggICQAAAA==.',Ph='Philgood:BAAALAADCgEIAQAAAA==.',Pi='Pibelock:BAAALAAECgYICwAAAA==.Pibewarro:BAAALAAECgYICgABLAAECgYICwARAAAAAA==.Pikatwo:BAAALAAECgMIAwAAAA==.Pilarita:BAAALAAECgEIAQAAAA==.Pipødruid:BAAALAADCgYIBgAAAA==.Pipøevoker:BAACLAAFFIEFAAIbAAII9SAiCgDDAAAbAAII9SAiCgDDAAAsAAQKgSAAAxsACAg7G9wKAFsCABsACAg7G9wKAFsCABwABwgGHNYEAEcCAAAA.',Po='Pocopepe:BAAALAADCgcIBwAAAA==.Podroto:BAAALAAECgcIEAAAAA==.Poggers:BAAALAAECgQIBwAAAA==.Pozí:BAAALAADCgcIBwAAAA==.',Pr='Princésa:BAABLAAECoEWAAICAAYIVBZnaQAZAQACAAYIVBZnaQAZAQAAAA==.',['Pê']='Pêndragon:BAAALAADCggIDgAAAA==.',['Põ']='Põ:BAAALAADCgcICAAAAA==.',Qu='Queiroga:BAAALAAECgIIAwAAAA==.Quelthias:BAAALAADCgIIAgAAAA==.Quinos:BAAALAADCggICwAAAA==.',Ra='Raigdesol:BAAALAAECgIIAgAAAA==.Raistlìn:BAABLAAECoEXAAIdAAgIGxcLOwBAAgAdAAgIGxcLOwBAAgAAAA==.Rakuul:BAAALAAECgcIEAAAAA==.Randorf:BAAALAAECggIBgAAAA==.Raphtel:BAAALAADCgUIBQAAAA==.Raykua:BAAALAAECgUIBQAAAA==.Rayuco:BAAALAADCgMIAwAAAA==.',Rb='Rbka:BAAALAADCggIEAAAAA==.',Re='Redjunter:BAABLAAECoEWAAINAAgIMBSrWQDuAQANAAgIMBSrWQDuAQAAAA==.Reima:BAAALAAECgIIAgAAAA==.Reventh:BAAALAAECgQIBAABLAAECgQIBwARAAAAAA==.Reydruida:BAAALAADCgcIBwABLAAECggIHgAWAGIcAA==.',Rh='Rhauru:BAAALAAECgYICgABLAAFFAIIBAARAAAAAA==.Rhaymast:BAAALAADCggIDAAAAA==.Rheda:BAAALAAECgEIAwAAAA==.',Ri='Rindo:BAAALAAECgYIDgAAAA==.Rinky:BAABLAAECoEYAAIGAAcIkhzCHwBXAgAGAAcIkhzCHwBXAgAAAA==.Rivama:BAAALAAECgIIAgABLAAECgMIAwARAAAAAA==.Rivendel:BAAALAADCggICAABLAAECgcIGwADAKogAA==.',Ro='Roma:BAAALAAECgIIAgAAAA==.Romperocas:BAAALAAECgMIAwAAAA==.Rootpaul:BAAALAAECgMIAwAAAA==.',Ru='Ruamy:BAAALAAECgQIBwAAAA==.Ruancito:BAAALAADCggICAAAAA==.',Ry='Ryhal:BAAALAAECgYIDQAAAA==.Ryomonio:BAABLAAECoEkAAINAAcIexghWgDtAQANAAcIexghWgDtAQAAAA==.Ryosaeba:BAAALAAECgMIAwAAAA==.',Sa='Sacerfo:BAACLAAFFIEFAAIFAAIICB4CGAC0AAAFAAIICB4CGAC0AAAsAAQKgScAAwUACAhAHBEYAJICAAUACAhAHBEYAJICAAYAAQiyCfmIADgAAAAA.Salfu:BAABLAAECoEWAAIEAAgIpBHobgDcAQAEAAgIpBHobgDcAQAAAA==.Samanthä:BAAALAADCgcICwAAAA==.Sanare:BAAALAAECgMICwAAAA==.Sanchopanza:BAAALAAECgUIBQAAAA==.Santaklaus:BAACLAAFFIEKAAIjAAMIHSVABABHAQAjAAMIHSVABABHAQAsAAQKgSkAAiMACAjhJTMBAG4DACMACAjhJTMBAG4DAAAA.Santuaria:BAAALAADCgYICQAAAA==.Sariah:BAAALAADCgIIAgAAAA==.Satürn:BAAALAADCgEIAQAAAA==.',Se='Sebrindel:BAAALAAECgYIDAAAAA==.Secondus:BAAALAADCgIIAgAAAA==.Sencilla:BAAALAADCgQIBAAAAA==.Sepphirotth:BAAALAAECgIIAgAAAA==.Septllas:BAABLAAECoEjAAIKAAgILhoLKgBHAgAKAAgILhoLKgBHAgAAAA==.Sethtak:BAAALAAECgcIDwAAAA==.Sevy:BAAALAAECgEIAQAAAA==.',Sg='Sgàeyl:BAAALAADCgcIDgAAAA==.',Sh='Shabana:BAAALAADCggIDAAAAA==.Shadist:BAAALAAECggIDAAAAA==.Shaelara:BAAALAADCgMIAwAAAA==.Shalashin:BAABLAAECoEbAAICAAgIUR5eEQCtAgACAAgIUR5eEQCtAgAAAA==.Shamansito:BAAALAAECgYIBwAAAA==.Shenjingbing:BAABLAAECoEdAAIGAAgISBYuIwA9AgAGAAgISBYuIwA9AgAAAA==.Shevat:BAAALAAECgMIAwABLAAECggIGwACAFEeAA==.Shibba:BAAALAAECgQIBAAAAA==.Shiibba:BAAALAAECgYIBgAAAA==.Shinjy:BAAALAADCgcIDQABLAAECgcIGwADAKogAA==.Shinshampoo:BAAALAAECgcIDAAAAA==.Shintaro:BAAALAAECggIDwAAAA==.Shugos:BAAALAADCgIIAgAAAA==.Shurdh:BAAALAAECgIIAwAAAA==.Shâde:BAAALAAECgIIAwAAAA==.',Si='Sichadah:BAAALAAECgIIAwAAAA==.Silexion:BAAALAADCgIIAgAAAA==.Silmar:BAAALAAECgMIAwAAAA==.Sindra:BAABLAAECoEgAAMGAAcI7R9mNQDQAQAGAAYIYx9mNQDQAQAFAAYISxDAXgA8AQAAAA==.Sindrenei:BAAALAAECgUIAQAAAA==.Siniye:BAAALAAECgcIEwAAAA==.',Sk='Skultar:BAAALAADCgEIAQAAAA==.Skyred:BAABLAAECoEdAAIEAAcIqBPmcwDSAQAEAAcIqBPmcwDSAQAAAA==.Skäadi:BAAALAAECgYIDAAAAA==.',Sl='Slilandro:BAAALAADCgcIEAAAAA==.',Sn='Snaerith:BAAALAADCgIIAgAAAA==.',So='Solgélida:BAAALAAECgYIBwAAAA==.Sonnyc:BAABLAAECoEYAAITAAcIoxcNPgALAgATAAcIoxcNPgALAgAAAA==.Sottanas:BAAALAAECgYIEAAAAA==.',Sp='Spectër:BAAALAADCggIDQAAAA==.Spitz:BAAALAAECgMIAwAAAA==.',Sr='Srarturo:BAAALAADCgUIBQAAAA==.Srlisters:BAAALAADCgcIBwAAAA==.Srstark:BAAALAADCgcICwAAAA==.',St='Stickmaster:BAAALAAECgIIAwAAAA==.Storyboris:BAAALAAECgcIEQAAAA==.Storyborix:BAAALAADCgYIBgAAAA==.',Su='Suaak:BAAALAADCggICAAAAA==.Suariel:BAAALAAECgYICgAAAA==.Suhné:BAAALAAECgYIDgABLAAECgcIFAAdAHQaAA==.Suken:BAAALAAECggIEgABLAAFFAIIBQAFAAgeAA==.Sukki:BAAALAAECgQIBwAAAA==.Supratacos:BAAALAAECgYIEQAAAA==.',Sy='Syl:BAAALAADCgQIBAAAAA==.Sylnus:BAAALAAECgEIAQAAAA==.Sylvanito:BAAALAADCggICgAAAA==.Sylvän:BAABLAAECoEoAAISAAgI2BRCGAAhAgASAAgI2BRCGAAhAgAAAA==.',['Sá']='Sámay:BAAALAAECgQIAQAAAA==.',['Sâ']='Sâlfuman:BAAALAADCgUIBQAAAA==.',['Sî']='Sîlvér:BAAALAADCgQIBAAAAA==.',Ta='Tagliatella:BAAALAAECggIDQAAAA==.Talanjy:BAAALAAECgQIBAAAAA==.Taldoran:BAAALAADCgcIBwAAAA==.Taltaro:BAAALAADCgUIBQAAAA==.Tapucho:BAAALAAECgMIAwAAAA==.',Te='Teneumbra:BAAALAADCgEIAQAAAA==.Tenran:BAABLAAECoEWAAINAAgI4RKhbgC8AQANAAgI4RKhbgC8AQAAAA==.Terminux:BAAALAAECgYICgAAAA==.Termirulo:BAAALAAECgYICwAAAA==.Termës:BAAALAAECgMIBQAAAA==.',Th='Thairox:BAAALAADCgQIBwAAAA==.Tharmor:BAAALAAECgYIBgAAAA==.Themagician:BAAALAAECgEIAQAAAA==.Therkan:BAAALAADCgcICwABLAAECggIIwAiAM8PAA==.Thordin:BAAALAAECgYIEwAAAA==.Thumder:BAABLAAECoEaAAIKAAgILx5IGACdAgAKAAgILx5IGACdAgAAAA==.',Ti='Tichöndrius:BAAALAADCggICQAAAA==.Tiradar:BAAALAAECgIIAgAAAA==.Titania:BAAALAAECgYIBgAAAA==.',To='Toixona:BAAALAADCgMIAwAAAA==.Toixoneta:BAAALAADCgcICgAAAA==.Toukä:BAAALAAECgcIDwAAAA==.Toztada:BAAALAADCgYIBgAAAA==.',Tr='Trankishan:BAABLAAECoEpAAIPAAgItRMoGADSAQAPAAgItRMoGADSAQAAAA==.Traumatico:BAAALAAECgYIDwAAAA==.Tremory:BAAALAADCgQIBAAAAA==.Troia:BAABLAAECoEgAAIBAAcIuBVHOQClAQABAAcIuBVHOQClAQAAAA==.',Tu='Tuck:BAAALAAECgMIAgAAAA==.Tugahtïtha:BAAALAAECgEIAQAAAA==.Tula:BAAALAAFFAIIBAAAAA==.Turlertes:BAAALAAECgMIAwAAAA==.',Ul='Uluk:BAAALAAECgMIAwAAAA==.',Um='Umbrak:BAAALAAECgMIAwAAAA==.',Ur='Urfi:BAAALAADCggICAAAAA==.Urthysis:BAAALAADCggIFwAAAA==.',Uy='Uykmiedo:BAAALAAECgQIBAAAAA==.',Va='Vaaldor:BAAALAADCgcIDQAAAA==.Vaelico:BAAALAADCgIIAgAAAA==.Vajra:BAABLAAECoEpAAQIAAgIIR5eKgBvAgAIAAgIIR5eKgBvAgALAAMIZQqHJQCfAAAJAAII6w1McgB1AAAAAA==.Valerius:BAAALAAECggIBQAAAA==.Valix:BAAALAAECgYIDAAAAA==.Vallen:BAAALAADCgYICAAAAA==.Vashnar:BAAALAADCgcIBwABLAAECgcIGwADAKogAA==.',Ve='Venradis:BAAALAADCgIIAgAAAA==.Veyrath:BAAALAADCggICgAAAA==.',Vh='Vhalsee:BAACLAAFFIEFAAIZAAIImR5MFgCzAAAZAAIImR5MFgCzAAAsAAQKgTEAAhkACAivIqoLACEDABkACAivIqoLACEDAAAA.',Vi='Viejales:BAAALAADCgUIBQAAAA==.',Vo='Voldemört:BAAALAAECgYIBgAAAA==.Volthumn:BAAALAAECggIDwAAAA==.Vonderleyen:BAAALAADCgYIBQAAAA==.Vortexiña:BAAALAADCgcICQAAAA==.',Vu='Vulruth:BAAALAADCgIIAgABLAAECgcIDQARAAAAAA==.Vulture:BAAALAAECgcIBwAAAA==.',['Vô']='Vôrtex:BAAALAAECgMIBQAAAA==.',Wa='Wally:BAAALAADCgcIDgAAAA==.Warmode:BAAALAAECgMIAgABLAAECggIHgAWAGIcAA==.',We='Wex:BAABLAAECoEXAAILAAcIBSBQBQB1AgALAAcIBSBQBQB1AgAAAA==.',Wh='Whitelock:BAAALAAECgcICgAAAA==.Whitewar:BAABLAAECoEeAAIWAAgIYhz/DwBZAgAWAAgIYhz/DwBZAgAAAA==.',Wl='Wleyenda:BAAALAADCgYIBgAAAA==.',Wu='Wut:BAAALAADCggICgAAAA==.',Xa='Xaco:BAAALAADCggICAAAAA==.Xaney:BAAALAADCggICAAAAA==.Xarmy:BAAALAAECggIAwAAAA==.Xarolastriz:BAAALAADCgcIBwAAAA==.',Xd='Xd:BAABLAAECoEXAAIjAAcIJQ3TIwAfAQAjAAcIJQ3TIwAfAQABLAAECggIGwATADshAA==.',Xe='Xemnathas:BAAALAAECgYIBwAAAA==.',Xi='Xillian:BAAALAADCggIIgAAAA==.',Xq='Xq:BAAALAADCgcIBwAAAA==.',Ya='Yamette:BAAALAADCggIEQAAAA==.Yaninna:BAAALAADCgEIAQAAAA==.Yassineitor:BAAALAADCgYIBgAAAA==.Yavienna:BAAALAAECgIIAQAAAA==.',Ye='Yelldemoniac:BAAALAAECggICwAAAA==.Yensa:BAAALAAECgcIDwAAAA==.',Yo='Yodar:BAAALAADCgIIAgAAAA==.Yomatarte:BAAALAADCgcIDgAAAA==.',['Yû']='Yûri:BAAALAADCggICAABLAAECggIKAASANgUAA==.',Za='Zanesfar:BAAALAAECggIDgABLAAFFAIIBQAFAAgeAA==.Zarwik:BAAALAADCggIEAAAAA==.Zaserk:BAAALAAECgYIBgAAAA==.Zazerzote:BAAALAAECgYIEAAAAA==.',Ze='Zeroo:BAAALAADCggICgABLAAECgYICgARAAAAAA==.',Zh='Zhajun:BAAALAADCggICAAAAA==.Zhuanyun:BAAALAAECgIIAgAAAA==.',Zo='Zoaroner:BAAALAAECgIIAwAAAA==.Zombirella:BAAALAADCggIBQAAAA==.Zondp:BAABLAAECoEbAAIGAAcI7xp8JQAtAgAGAAcI7xp8JQAtAgAAAA==.Zondx:BAAALAAECgUIBAAAAA==.Zondz:BAAALAAECgIIAgAAAA==.Zont:BAAALAAECgUIBQABLAAFFAIIBQAFAAgeAA==.Zoth:BAAALAAECgIIBAAAAA==.Zothen:BAAALAADCggIDwABLAAECgcIGwADAKogAA==.',Zz='Zzull:BAAALAAECggIDgAAAA==.',['Âk']='Âkh:BAAALAAECgMIAwAAAA==.',['Äk']='Äködö:BAAALAAECgEIAgABLAAECgcIFwAEABEDAA==.',['Íñ']='Íñigomontoya:BAAALAADCggICAABLAAECgYICwARAAAAAA==.',['Ðe']='Ðemoliria:BAAALAAECgIIAgAAAA==.',['Ðu']='Ðucal:BAAALAAECgQIBAAAAA==.',['Ör']='Ördög:BAAALAAECgcICgAAAA==.',['Üm']='Ümbra:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end