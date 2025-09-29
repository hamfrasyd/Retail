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
 local lookup = {'Shaman-Elemental','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Frost','Hunter-BeastMastery','Mage-Frost','Druid-Feral','Paladin-Holy','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Unknown-Unknown','Warrior-Fury','DemonHunter-Vengeance','Monk-Windwalker','Evoker-Augmentation','Druid-Restoration','Rogue-Assassination','Shaman-Restoration','Paladin-Protection','Warlock-Demonology','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Druid-Balance','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','Priest-Discipline','Priest-Holy','Warrior-Arms','DeathKnight-Unholy','Rogue-Subtlety','Hunter-Survival','DeathKnight-Blood',}; local provider = {region='EU',realm='Shattrath',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aaragom:BAAALAAECgYIEgAAAA==.',Ab='Abígs:BAABLAAECoEkAAIBAAgIZg16QQDUAQABAAgIZg16QQDUAQAAAA==.',Ac='Acid:BAAALAAECgQIBAAAAA==.',Ad='Adaira:BAAALAADCgMIAwAAAA==.Adhemar:BAAALAADCggICAAAAA==.Adhiambo:BAAALAADCgIIAgAAAA==.',Ai='Aimedlol:BAACLAAFFIEIAAICAAII4CLEFQChAAACAAII4CLEFQChAAAsAAQKgRgAAgIABggHJV8bAHQCAAIABggHJV8bAHQCAAAA.Airwoker:BAAALAAECgYIDgAAAA==.Aiwia:BAAALAAECggIEAAAAA==.',Ak='Akariy:BAAALAADCgcIBwAAAA==.Akitara:BAAALAADCgIIAgAAAA==.Akkani:BAAALAADCggIEAAAAA==.Akyra:BAAALAADCgYIBwAAAA==.',Al='Alangor:BAAALAADCggIEAAAAA==.Alatáriël:BAABLAAECoEkAAIDAAgIjCQqCgBDAwADAAgIjCQqCgBDAwAAAA==.Alená:BAAALAADCggIFQAAAA==.Alexios:BAAALAADCgYIDAAAAA==.Alleni:BAAALAADCggICAAAAA==.Alphorn:BAAALAADCgcICgAAAA==.Alpollo:BAAALAAECggIEAAAAA==.Altefluse:BAAALAADCggICgAAAA==.Alukâ:BAAALAADCggICAAAAA==.Alyria:BAAALAAECgQICAAAAA==.',Am='Amariel:BAAALAAECgYIEQAAAA==.Ambos:BAAALAADCgMIAwAAAA==.Ambossfaust:BAAALAADCgcIBwAAAA==.Amdusias:BAAALAADCgYIDgAAAA==.',An='Andrui:BAAALAADCgYIBgABLAAFFAUICQAEABgSAA==.Angzair:BAAALAADCggICgAAAA==.Anhiara:BAABLAAECoEhAAIFAAgIfSXQDAAyAwAFAAgIfSXQDAAyAwAAAA==.Annea:BAABLAAECoEUAAIDAAYI0QiotwApAQADAAYI0QiotwApAQAAAA==.Anomália:BAAALAAECgcIEQAAAA==.Anon:BAAALAAECggIEAAAAA==.Antropíen:BAAALAADCgcICQAAAA==.',Ap='Apokk:BAAALAAECgYICgAAAA==.',Ar='Arashir:BAAALAAECgYIBgABLAAECggIIgAGAH0kAA==.Arayana:BAAALAADCggICAAAAA==.Armadur:BAAALAAECgYIBgAAAA==.Arodel:BAABLAAECoEiAAMGAAgIfSRnCAA9AwAGAAgIfSRnCAA9AwACAAQIeR5rUABaAQAAAA==.Arthernal:BAAALAADCgMIAwAAAA==.Arwi:BAACLAAFFIEIAAIHAAMIexbxCQCeAAAHAAMIexbxCQCeAAAsAAQKgSkAAgcACAghJFEHAAkDAAcACAghJFEHAAkDAAAA.Arèsz:BAAALAAECgcICgAAAA==.',As='Ascalin:BAAALAADCggICgABLAAECggIJAAIALweAA==.Ascalon:BAAALAAECgIIAgAAAA==.Ashandra:BAAALAAECgYIEgAAAA==.Ashline:BAAALAADCggICAAAAA==.Ashlon:BAAALAAECgMIBQAAAA==.Ashítaka:BAAALAADCggIHgAAAA==.Askardia:BAAALAADCggIEAAAAA==.Aspîrin:BAAALAADCgYIBgAAAA==.',At='Atorus:BAABLAAECoEVAAIJAAYIpQ3KOQBEAQAJAAYIpQ3KOQBEAQAAAA==.Atrêus:BAAALAADCgcICAAAAA==.Attacka:BAAALAADCgYIBgAAAA==.',Av='Avri:BAAALAADCgUICAAAAA==.',Aw='Awebo:BAABLAAECoEdAAIDAAcIsA96dwCpAQADAAcIsA96dwCpAQAAAA==.Awyn:BAABLAAECoEhAAIKAAgI7SVkAABtAwAKAAgI7SVkAABtAwAAAA==.',Ay='Ayané:BAAALAADCggICAAAAA==.Ayida:BAAALAAECggIEgAAAA==.',Az='Azeyra:BAAALAAECgQIBAAAAA==.Azimah:BAAALAAECgMIBgAAAA==.Azk:BAABLAAECoEWAAMLAAcIihOCHwDSAAAMAAUI+xBoiAAxAQALAAMI2BWCHwDSAAAAAA==.Azmôdan:BAAALAADCgcICwAAAA==.Azsuna:BAACLAAFFIEHAAIEAAIIrwpINgCVAAAEAAIIrwpINgCVAAAsAAQKgR0AAgQABwirHKFSABwCAAQABwirHKFSABwCAAAA.Azzula:BAAALAADCgcICgABLAAECgYICgANAAAAAA==.',Ba='Backpfeife:BAAALAAECgYIDAAAAA==.Baekthor:BAAALAAECgQIBgAAAA==.Balín:BAAALAAECgIIBgAAAA==.Baranov:BAAALAAECgYIEQABLAAECggICAANAAAAAA==.Barrexx:BAAALAAECgYIDwAAAA==.Barushdak:BAAALAAECgIIAgAAAA==.Batschdrake:BAAALAAECgMIAwAAAA==.Bayo:BAAALAADCgYIBgAAAA==.',Be='Bearforce:BAAALAAECgMIAwAAAA==.Beliala:BAAALAADCggICQAAAA==.Belzorash:BAAALAAECgEIAQAAAA==.Bernde:BAAALAADCggICAAAAA==.Beschamel:BAAALAAECgYIBgAAAA==.',Bi='Biborius:BAAALAADCggICAAAAA==.Bierwulfgard:BAAALAAECgYIBgAAAA==.Bira:BAAALAAECgUIDQAAAA==.Biscaya:BAAALAADCgcICQAAAA==.',Bl='Blackdragon:BAAALAADCggIIgAAAA==.Blackheaven:BAAALAAFFAIIBAAAAQ==.Blackpaladin:BAAALAAECggICQAAAA==.Blackpearl:BAAALAADCgQIBAAAAA==.Blackphoenix:BAAALAADCggIDwAAAA==.Blackpriest:BAAALAADCggICAABLAAFFAIIBAANAAAAAQ==.Blathier:BAAALAAECggICAAAAA==.',Bo='Bolas:BAAALAADCgYIBgAAAA==.Borium:BAAALAADCggIDgAAAA==.',Br='Bragush:BAABLAAECoEjAAIOAAgIvx8AFQDsAgAOAAgIvx8AFQDsAgAAAA==.Branza:BAAALAAECgYIEgAAAA==.Braurox:BAAALAAECgYIBwAAAA==.Breathless:BAAALAADCgYIBgAAAA==.Breâky:BAAALAAECgcIDQAAAA==.Brickedup:BAAALAADCggICAABLAAFFAUICgAPAKEhAA==.Bronza:BAAALAAECgMIAwABLAAECgYIEgANAAAAAA==.',Bu='Bulldøzer:BAAALAADCggICAAAAA==.Bumbummaster:BAAALAADCgcIBwAAAA==.',['Bä']='Bärnd:BAAALAADCgcIDAAAAA==.',['Bó']='Bóbrkrieger:BAAALAADCgUIAQAAAA==.Bóbrschurke:BAAALAAECggIEwAAAA==.',['Bü']='Bürsti:BAAALAADCgYIDgAAAA==.',Ca='Caerwynn:BAABLAAECoEUAAIQAAcIiwfLNQAwAQAQAAcIiwfLNQAwAQAAAA==.Calyxo:BAAALAADCgYIBgAAAA==.Caraliná:BAAALAAECgIIBgAAAA==.Carazahn:BAAALAAECgUIBQAAAA==.Cathyen:BAAALAAECggICwAAAA==.',Ce='Celaenna:BAAALAADCggIFAAAAA==.',Ch='Champar:BAAALAADCggICAAAAA==.Cheesedh:BAAALAAECgUICAAAAA==.Cheysuli:BAAALAAECgYICwAAAA==.Chiro:BAAALAADCggIDwAAAA==.Chocolate:BAAALAAECgMIAwAAAA==.Chrisseline:BAAALAAECggICAAAAA==.Chupapi:BAAALAAECgQIBAAAAA==.',Ci='Cintara:BAAALAAECgIIBAAAAA==.',Co='Contagio:BAAALAADCgYIBgAAAA==.Coyot:BAAALAAECgYIEQAAAA==.',Cr='Cryús:BAAALAADCgMIAwAAAA==.Cránè:BAAALAAECgMIBQAAAA==.',Cy='Cyberflame:BAABLAAECoEkAAIBAAgI5hpiHwCHAgABAAgI5hpiHwCHAgAAAA==.Cyna:BAAALAADCgcIBgAAAA==.Cyrion:BAAALAAECgYIEwAAAA==.',['Cø']='Cøbs:BAAALAAECggICAAAAA==.',Da='Daan:BAAALAADCgMIAwAAAA==.Dando:BAAALAAECgYIBgABLAAFFAUICgARAO8cAA==.Daneben:BAAALAADCggIFgAAAA==.Darcan:BAAALAADCgcIDAAAAA==.Daredevìl:BAAALAADCggIGAAAAA==.Darkdaemont:BAAALAADCggICAAAAA==.Darkota:BAAALAADCgcIBwAAAA==.Darksakura:BAAALAADCgMIAwAAAA==.',De='Deathgore:BAAALAAECgcIDQAAAA==.Deathgrim:BAAALAADCgcIDAAAAA==.Dendranix:BAAALAADCgcIBwAAAA==.Deni:BAABLAAECoEaAAISAAcIIiEPEwCfAgASAAcIIiEPEwCfAgAAAA==.Derni:BAAALAAECgYIDwAAAA==.Deviltor:BAABLAAECoEZAAIMAAYIEQo2hQA6AQAMAAYIEQo2hQA6AQAAAA==.',Di='Dienerderêlf:BAAALAADCgYIBgAAAA==.Digler:BAAALAAECggICAAAAA==.Dimsung:BAAALAADCgMIBAABLAAECggIJAAIALweAA==.Dingsdâ:BAAALAADCgcICQAAAA==.Dirand:BAABLAAECoEcAAIGAAgIfR83JwCBAgAGAAgIfR83JwCBAgAAAA==.Dirtyluigi:BAAALAADCggICAAAAA==.Dispair:BAAALAAECgEIAQAAAA==.',Dk='Dkproxy:BAAALAAECggIBgAAAA==.',Do='Doccore:BAAALAAECgYIDQAAAA==.Donky:BAAALAADCggICAABLAAECggIFgAOAOUcAA==.Doppelaxt:BAAALAADCgQIBAAAAA==.Doshy:BAAALAADCgYIEQAAAA==.Dostro:BAAALAAFFAEIAQAAAA==.Dothma:BAAALAAECgYIDQAAAA==.',Dr='Dracor:BAAALAADCggICAAAAA==.Drageron:BAAALAADCgUIBQAAAA==.Drakangel:BAAALAADCgIIBAAAAA==.Dramain:BAAALAADCgUIBQAAAA==.Drazukí:BAAALAAECgcIBwABLAAECggIKgACAKMfAA==.Dreadîa:BAAALAAECgYICwAAAA==.Dreshhammer:BAAALAAECgYIDwAAAA==.Drfùssél:BAAALAADCgUIBQAAAA==.Droxy:BAAALAADCgUIBgAAAA==.',Du='Dudeldi:BAAALAAECgYIDAAAAA==.Duduseech:BAAALAAECgIIAgABLAAFFAEIAQANAAAAAA==.',['Dâ']='Dâénérys:BAAALAAECgYIDgAAAA==.',['Dä']='Dämolieren:BAAALAAECgYIDwAAAA==.',Eb='Ebensa:BAAALAAECgYICQAAAA==.',Ed='Eddiee:BAAALAADCgEIAQAAAA==.Edia:BAAALAAECgYIEAAAAA==.Edudu:BAAALAAECgYICgAAAA==.',Ee='Eevil:BAAALAADCggIEgABLAAECgYIHQAGABMXAA==.',Eh='Ehecatl:BAAALAAECgQIBwABLAAECgYICgANAAAAAA==.',Ei='Eiler:BAAALAAECggIEAAAAA==.',Ej='Ejonavonsaba:BAAALAAECgIIAgAAAA==.',El='Eldirina:BAAALAAECgMIBAAAAA==.Eldurado:BAABLAAECoEWAAIEAAYI1yGbQABPAgAEAAYI1yGbQABPAgAAAA==.Elementkater:BAAALAADCgcIBwAAAA==.Elfynjana:BAAALAADCggICAAAAA==.Elisara:BAAALAADCgQIBgABLAAECggIGQATABYTAA==.Elli:BAAALAAECggICAAAAA==.Eluthalanar:BAABLAAECoEcAAIDAAgIcR4kHQDUAgADAAgIcR4kHQDUAgAAAA==.Elwlad:BAAALAAECgYIBQAAAA==.Elârâ:BAACLAAFFIEJAAIUAAMIaBT6DwDjAAAUAAMIaBT6DwDjAAAsAAQKgRcAAhQACAjBCrOHADYBABQACAjBCrOHADYBAAAA.Elênia:BAAALAADCgcIFgAAAA==.Elîasar:BAAALAADCggICAABLAAECggICAANAAAAAA==.',Em='Emerallyr:BAAALAAECgQIBAAAAA==.',En='Envyre:BAAALAAECgEIAQAAAA==.',Er='Erill:BAAALAADCggIEgAAAA==.',Es='Estora:BAAALAADCggIEwAAAA==.',Et='Ette:BAACLAAFFIEFAAIVAAII9hR7DACNAAAVAAII9hR7DACNAAAsAAQKgSIAAhUACAg/Gw4WABgCABUACAg/Gw4WABgCAAAA.',Ev='Evelyn:BAAALAAECgIIAgAAAA==.',Ey='Eyvua:BAAALAADCgcIFQAAAA==.',Fa='Fairplexu:BAAALAADCgQIBAAAAA==.Faladee:BAAALAAECgIIAwAAAA==.',Fe='Felariel:BAAALAADCgcIBwAAAA==.Felixjaegar:BAAALAAECgYIEAAAAA==.Fellbabe:BAAALAAECgMIBgAAAA==.Feluriân:BAACLAAFFIEIAAMMAAUIRRzoCQDSAQAMAAUIRRzoCQDSAQAWAAEIURXlHwBSAAAsAAQKgRgAAwwACAgPJD4HAE8DAAwACAgPJD4HAE8DABYAAwiLAYGFADsAAAAA.Fenel:BAABLAAECoEVAAIXAAgI9x70HgDCAgAXAAgI9x70HgDCAgAAAA==.Fenny:BAAALAADCggIDwABLAAECggIHgAEAP0hAA==.Fenrith:BAAALAADCggIEAAAAA==.Feuerpranke:BAAALAAECggIEAAAAA==.',Fi='Fiadh:BAABLAAECoEeAAIHAAgIqw3kJwDDAQAHAAgIqw3kJwDDAQAAAA==.Finnic:BAAALAAECgMIAwAAAA==.Finnik:BAAALAADCgcICwAAAA==.',Fl='Fleck:BAAALAAECgIIAgAAAA==.Flydechse:BAACLAAFFIEKAAMRAAUI7xxVAQDNAQARAAUI7xxVAQDNAQAYAAEI6RdPGwBPAAAsAAQKgSUABBEACAhnJKoAAFEDABEACAhnJKoAAFEDABgACAiwFkciAOoBABkAAQjCArg6ACYAAAAA.Flyless:BAABLAAECoEmAAISAAgIaRNUMwDhAQASAAgIaRNUMwDhAQAAAA==.',Fo='Foiamaan:BAAALAAECgIIBAAAAA==.',Fu='Fuchsteufel:BAABLAAECoEeAAMaAAcIuw0JRAByAQAaAAcIpw0JRAByAQAIAAEIowb0QAAwAAAAAA==.Fujihime:BAAALAADCgcICAAAAA==.',Ga='Gamana:BAAALAADCggICgAAAA==.Garibaldi:BAAALAADCgQIBAAAAA==.Garul:BAAALAAECgEIAQAAAA==.Garuuf:BAAALAAECgMIBAAAAA==.',Ge='Genessis:BAABLAAECoEUAAQQAAgIWhM0KwB4AQAQAAgIvwo0KwB4AQAbAAcINw5jIwBYAQAcAAQIVB8AAAAAAAABLAAFFAUICgARAO8cAA==.Genetíx:BAAALAAECgEIAQAAAA==.Geonomos:BAAALAADCggIDAAAAA==.Geschredder:BAAALAAECgYIDwAAAA==.Geschreddér:BAAALAAECgYICQAAAA==.',Gh='Ghotmog:BAAALAAECgQIBAAAAA==.Ghàíst:BAAALAADCggIHgAAAA==.',Gl='Glaran:BAAALAADCggICQAAAA==.',Gn='Gnoxnox:BAAALAADCggIDQAAAA==.',Go='Gorgat:BAAALAAECggICAAAAA==.Gorig:BAABLAAECoEUAAIEAAYI+wSt+gDEAAAEAAYI+wSt+gDEAAAAAA==.',Gr='Grannyhunter:BAAALAAECgMIAwAAAA==.Granthoudini:BAAALAAECgYICwAAAA==.Gravijnho:BAAALAAECgYICgAAAA==.Gremiumdh:BAAALAADCgQIBgAAAA==.Grinzer:BAAALAAECggIEQAAAA==.Gromir:BAAALAADCgYIBgAAAA==.Grummelchen:BAAALAAECgUICgAAAA==.Grètel:BAAALAADCgYICQAAAA==.',Gu='Guccpriest:BAABLAAECoElAAQdAAcIhBjWKQASAgAdAAcIhBjWKQASAgAeAAEIMAfZMwAvAAAfAAEIewFcqwAiAAAAAA==.',['Gö']='Görtrud:BAAALAADCgYIBgAAAA==.',Ha='Hanfi:BAABLAAECoEaAAICAAgIKBu+IQBEAgACAAgIKBu+IQBEAgAAAA==.Harriet:BAAALAADCggIEgAAAA==.Hatred:BAAALAADCgcIBgAAAA==.Hazoc:BAAALAADCggICAAAAA==.',He='Heffernan:BAABLAAECoEgAAMgAAgIOB50BADCAgAgAAgIOB50BADCAgAOAAUIRgodmgDqAAAAAA==.Heidelbeeré:BAAALAAECgYIEQAAAA==.Heks:BAAALAAECgEIAQAAAA==.Hellgate:BAABLAAECoEbAAIOAAcIBSAOKAByAgAOAAcIBSAOKAByAgAAAA==.Helà:BAAALAADCgQIBgAAAA==.Herakless:BAAALAADCgUIBQAAAA==.Hexii:BAAALAADCgQIBAAAAA==.Hexrider:BAABLAAECoEWAAMMAAgIeCCGJwB+AgAMAAgIbiCGJwB+AgALAAQIEBZLGwADAQAAAA==.',Hi='Highonholy:BAAALAAECgEIAgAAAA==.',Ho='Holdemaid:BAAALAAECgUICQAAAA==.Holdmybeer:BAAALAAECgUIBgAAAA==.Holybull:BAAALAADCgcIDAABLAAECggIFgAOAOUcAA==.Hon:BAAALAADCggIBQAAAA==.Horsthunt:BAAALAAECggIDAAAAA==.',Hu='Hubî:BAAALAADCgYIBgABLAAECggIIgAGAH0kAA==.Hujax:BAAALAAECgYICQAAAA==.Huppy:BAAALAADCggIFwAAAA==.Hurzlpurzl:BAAALAADCggIEAAAAA==.',Hy='Hyas:BAAALAADCggICAAAAA==.Hyrulê:BAAALAADCgYIBgAAAA==.',['Hâ']='Hânfii:BAAALAAECgYIBwABLAAECggIGgACACgbAA==.Hânfí:BAAALAAECgUIBQABLAAECggIGgACACgbAA==.',['Hö']='Hörnchen:BAAALAADCgYIBgAAAA==.',Il='Illanthya:BAAALAAECgYIBgAAAA==.Ilva:BAABLAAECoEYAAIdAAgIFRZZJwAhAgAdAAgIFRZZJwAhAgAAAA==.',Im='Imbapriesti:BAAALAADCggIEAAAAA==.',In='Ineedademon:BAAALAAECgcIDwAAAA==.Inestri:BAAALAAECgYIEgAAAA==.Insulina:BAACLAAFFIEGAAIfAAIIYh0pGACzAAAfAAIIYh0pGACzAAAsAAQKgRYAAx8ABggrIT8rABoCAB8ABghYID8rABoCAB4AAQgYIg0pAGMAAAAA.',Ja='Jaenná:BAAALAADCggIGgAAAA==.Jagron:BAAALAAECgUIBgAAAQ==.',Je='Jedeimaster:BAAALAAECgYIDAAAAA==.Jennylegoman:BAAALAADCggICAABLAAFFAUICgAPAKEhAA==.Jennynorman:BAACLAAFFIEKAAMPAAUIoSHYAADIAQAPAAQI+iXYAADIAQADAAIIwwq5MACTAAAsAAQKgSsAAw8ACAjMJlUAAIsDAA8ACAjMJlUAAIsDAAMAAQhDFpUTAUEAAAAA.Jensen:BAAALAAECgQIBAAAAA==.',Jo='Joster:BAAALAADCgYIDgAAAA==.',Ju='Justus:BAAALAADCgIIAgAAAA==.',['Jä']='Jägermaxi:BAAALAADCgUIBQAAAA==.',['Jî']='Jîren:BAAALAADCggICAAAAA==.',Ka='Kajetan:BAAALAAECgIIAwAAAA==.Kalaj:BAAALAADCgUIBQAAAA==.Kalibos:BAAALAAECgQICAABLAAFFAIIAwAXAAgRAA==.Kamino:BAAALAAECgYIDAAAAA==.Kampfkater:BAAALAAECgIIAgAAAA==.Karador:BAAALAAECgQICgAAAA==.Karli:BAAALAAECgYIDAABLAAECggIHQABAGMgAA==.Karltoffel:BAAALAAECgcIEAAAAA==.Karrlar:BAAALAADCgYIBgAAAA==.Katan:BAAALAADCgIIAgAAAA==.Kathînka:BAAALAADCggIFwAAAA==.Kautzos:BAABLAAECoEYAAITAAcIFgw2OgBgAQATAAcIFgw2OgBgAQAAAA==.Kayus:BAAALAAECggIBwAAAA==.Kazun:BAAALAAECgcIEQAAAA==.',Ke='Keashaa:BAABLAAECoEcAAMUAAcIrxjGVwCvAQAUAAcIrxjGVwCvAQABAAIIzwrVnABoAAAAAA==.Kertack:BAAALAADCgcIBwAAAA==.Kettenblitz:BAABLAAECoEdAAMBAAgIYyC+EAD3AgABAAgIYyC+EAD3AgAUAAMI1A365QB9AAAAAA==.Kezuko:BAACLAAFFIEIAAIOAAQIHRoWCgBrAQAOAAQIHRoWCgBrAQAsAAQKgSsAAg4ACAgbIy0QAA8DAA4ACAgbIy0QAA8DAAAA.',Ki='Kibert:BAAALAADCgYIBgABLAAFFAIIBQAVAPYUAA==.Kiri:BAAALAAECgYICQAAAA==.Kishyra:BAABLAAECoEcAAIfAAgIiBRUMQD6AQAfAAgIiBRUMQD6AQAAAA==.Kitharion:BAABLAAECoEjAAIDAAgIpB+AHwDHAgADAAgIpB+AHwDHAgAAAA==.',Kl='Klaang:BAAALAAECgQIBwAAAA==.Klepto:BAAALAADCgQIBAAAAA==.Kløpper:BAAALAAECgYICwAAAA==.',Kn='Knubbeline:BAAALAADCggIDgAAAA==.',Ko='Kobsi:BAAALAAECgYICgAAAA==.Kochi:BAAALAADCggIFQAAAA==.Kochom:BAAALAAECgMICAAAAA==.Kochomsan:BAAALAADCgcIBwAAAA==.Kokw:BAAALAAECgcIEQAAAA==.Korra:BAAALAAECgYIBgAAAA==.Korris:BAABLAAECoEVAAIDAAgIdyB3FwD0AgADAAgIdyB3FwD0AgAAAA==.',Kr='Kriegskater:BAAALAADCgcICAAAAA==.Krish:BAAALAAECgYIBgAAAA==.Krsharh:BAAALAAECgYIDwAAAA==.',Ku='Kurome:BAAALAAECggICAAAAA==.Kuroneko:BAABLAAECoEVAAIVAAYIwhdkJACcAQAVAAYIwhdkJACcAQAAAA==.',['Kà']='Kàli:BAAALAAECggICAAAAA==.',['Ká']='Kánté:BAAALAAECggICAAAAA==.',['Kí']='Kíngsíléncé:BAAALAAECgcIEgAAAA==.',La='Lagorash:BAAALAAECgUIBQAAAA==.Lahen:BAABLAAECoEjAAIPAAcIfCCrCgCJAgAPAAcIfCCrCgCJAgAAAA==.Laloca:BAAALAAECgIIBgAAAA==.Lanaria:BAABLAAECoEdAAISAAcICyTFDADXAgASAAcICyTFDADXAgAAAA==.',Le='Leandris:BAAALAADCggICAAAAA==.Lethis:BAAALAAECgIIBAAAAA==.Lethô:BAAALAAECgYIEQAAAA==.Lexoa:BAAALAADCgYIBgAAAA==.Lexoas:BAAALAADCgYIBgAAAA==.',Li='Lidlrogue:BAAALAAECgcIDQAAAA==.Lightbabe:BAAALAADCgIIAgAAAA==.Lightfrost:BAAALAAECgEIAQAAAA==.Lightmage:BAAALAADCggIGwAAAA==.Linvanmer:BAAALAADCgcIEwAAAA==.',Lo='Lootgenius:BAAALAADCgcIBwAAAA==.Lootlock:BAAALAADCgcIDwAAAA==.Lorthian:BAABLAAECoEUAAIPAAYIsBrVGADLAQAPAAYIsBrVGADLAQAAAA==.Lossplintos:BAAALAAECgUICgAAAA==.Lossplîntos:BAAALAADCgIIAgAAAA==.',Lu='Lucina:BAAALAAECgcIBwAAAA==.Luih:BAAALAAECgYIEgAAAA==.Lumerathil:BAAALAADCgcIDgAAAA==.Lumineè:BAAALAAECgYIEQAAAA==.Lunastra:BAACLAAFFIEOAAIYAAUIaRX3BQCSAQAYAAUIaRX3BQCSAQAsAAQKgTgAAhgACAhzJGwFAC8DABgACAhzJGwFAC8DAAAA.Lustling:BAAALAAECggICQAAAA==.Luxetumbra:BAAALAAECgYIEAABLAAFFAIIBQAVAPYUAA==.',Ly='Lynnya:BAAALAAECgIIAgAAAA==.Lyseria:BAAALAADCgcIBwAAAA==.Lyzz:BAAALAAECgYICwAAAA==.',['Lê']='Lêviathari:BAABLAAECoEUAAIYAAYIbwc8QAAaAQAYAAYIbwc8QAAaAQABLAAECggIFAAMAGYGAA==.',['Lí']='Lína:BAAALAADCgYIBgAAAA==.',Ma='Maad:BAAALAAFFAEIAQAAAA==.Maddoxx:BAABLAAECoEkAAIHAAgI1h8CCgDgAgAHAAgI1h8CCgDgAgAAAA==.Madga:BAAALAADCggIFwAAAA==.Magierding:BAAALAAECggICAAAAA==.Mailina:BAAALAADCggICAAAAA==.Makurah:BAAALAAECgMIAwABLAAECgYICgANAAAAAA==.Malaga:BAAALAADCgYIBgAAAA==.Malish:BAAALAAECgYIBgABLAAECggIJAAIALweAA==.Malok:BAAALAADCgcIEwABLAAECggIJAAIALweAA==.Malosh:BAABLAAECoEkAAMIAAgIvB79BgDRAgAIAAgIvB79BgDRAgASAAYI+RgIQgCgAQAAAA==.Mangoboller:BAAALAAECggICgAAAA==.Manisso:BAAALAADCgcIEAAAAA==.Manri:BAAALAADCggIJwAAAA==.Mantier:BAAALAADCgcIEQAAAA==.Mantor:BAAALAADCgcICwAAAA==.Marrow:BAAALAAECgcIDgABLAAECggIFgAOAOUcAA==.',Mc='Mcslippyfist:BAAALAADCgcIBwAAAA==.',Me='Meanas:BAACLAAFFIEGAAIMAAUIDRFUDgCHAQAMAAUIDRFUDgCHAQAsAAQKgSsABAwACAjBIhkMACoDAAwACAjBIhkMACoDAAsAAwjkDPckAKMAABYAAQiqIcl8AE4AAAAA.Medôc:BAABLAAECoEXAAMdAAcIZweTUgBGAQAdAAcIZweTUgBGAQAfAAQIKwQRigCaAAAAAA==.Megumin:BAABLAAECoEVAAIfAAYI2xFwVwBWAQAfAAYI2xFwVwBWAQAAAA==.Meira:BAAALAAECggIEAAAAA==.Meldora:BAAALAADCgYICQAAAA==.Melora:BAABLAAECoEWAAIMAAYIYQkMiQAwAQAMAAYIYQkMiQAwAQAAAA==.Menelaz:BAAALAAECgcIDQAAAA==.Merila:BAAALAAECgYIDwAAAA==.Merl:BAAALAAECgEIAQAAAA==.Mestophilies:BAABLAAECoEYAAIDAAgIfgIl7wCVAAADAAgIfgIl7wCVAAAAAA==.Meyrá:BAAALAADCgMIAwAAAA==.',Mi='Miaolina:BAAALAAECgYIEQAAAA==.Micaria:BAAALAAECgYIEQAAAA==.Miflox:BAAALAAECgIIAgAAAA==.Milyandra:BAABLAAECoEUAAIMAAYIZgaHlQALAQAMAAYIZgaHlQALAQAAAA==.Milycia:BAAALAADCgYIDAAAAA==.Mimirín:BAAALAAECgcIDwAAAA==.Mindblast:BAABLAAECoEoAAIUAAgIMhILdgBfAQAUAAgIMhILdgBfAQAAAA==.Mirkster:BAACLAAFFIEKAAIEAAMI1BW6JgCmAAAEAAMI1BW6JgCmAAAsAAQKgSkAAgQACAjvILMtAJQCAAQACAjvILMtAJQCAAAA.Mistbehavin:BAAALAAECgIIAgABLAAFFAUICgAPAKEhAA==.Misáko:BAAALAADCgUIBQAAAA==.Miyuki:BAAALAAECgYIDgAAAA==.',Mj='Mjolnir:BAAALAADCgYIBgAAAA==.',Mo='Mondsüchtig:BAAALAAECgEIAQAAAA==.Moodh:BAAALAAECgcIEgAAAA==.Mooschu:BAABLAAECoEfAAMCAAcIlSP+EQDEAgACAAcIAiP+EQDEAgAGAAUIfh49mABOAQAAAA==.Mordea:BAAALAADCggICAAAAA==.Mordock:BAAALAAECgIIAgAAAA==.Morgrim:BAAALAADCggICwAAAA==.Morlak:BAAALAADCgcIBwAAAA==.Morrorwizz:BAAALAADCgcIBwAAAA==.',Mu='Muhchan:BAABLAAECoEeAAIQAAcIeBteKgB+AQAQAAcIeBteKgB+AQAAAA==.Muhrette:BAABLAAECoEcAAMUAAgIDh9PFgCpAgAUAAgIDh9PFgCpAgABAAQI0BQcfQD6AAABLAAFFAUICgAPAKEhAA==.Muryna:BAEALAAECgYIBgABLAAECggIEgANAAAAAA==.Muskatnuzz:BAABLAAECoExAAIQAAgIdiPeAwBDAwAQAAgIdiPeAwBDAwAAAA==.',My='Mylo:BAAALAAECggIDgAAAA==.Myzuuba:BAABLAAECoEUAAISAAgI3AfgaQAYAQASAAgI3AfgaQAYAQAAAA==.',['Má']='Máki:BAAALAAECgYICwAAAA==.',['Mì']='Mìnerva:BAAALAADCgcIBwAAAA==.',['Mî']='Mînîwinnî:BAAALAADCggICgABLAAECggIFgATAK0LAA==.Mîryya:BAAALAADCggICAAAAA==.',['Mö']='Mölon:BAAALAAECgQIBgAAAA==.',Na='Nachtbräu:BAABLAAECoEpAAIcAAgIBR0yCgCWAgAcAAgIBR0yCgCWAgAAAA==.Nachteule:BAAALAAECggIEgAAAA==.Nakazin:BAAALAADCgQIBAAAAA==.Naregs:BAAALAAECgMIBAAAAA==.Narratt:BAABLAAECoEZAAIUAAgIRB8MEwC+AgAUAAgIRB8MEwC+AgAAAA==.Naruse:BAAALAAECgYIDQAAAA==.Nasaku:BAABLAAECoEbAAIUAAgICxkXKABOAgAUAAgICxkXKABOAgAAAA==.Natalía:BAABLAAECoEZAAMBAAcIRBuoLQAxAgABAAcIRBuoLQAxAgAUAAEITBDCDQExAAAAAA==.Nayru:BAAALAAECggICAAAAA==.',Ne='Necroidyo:BAABLAAECoEZAAIgAAcIhBN4DgDMAQAgAAcIhBN4DgDMAQAAAA==.Nefariti:BAABLAAECoEjAAMIAAgI2h02BwDNAgAIAAgI2h02BwDNAgASAAgIMhjhIgA0AgAAAA==.Negmobart:BAAALAADCggIDgAAAA==.Neliél:BAAALAAECgMIBQAAAA==.Nelphi:BAAALAADCgEIAQAAAA==.Nemania:BAAALAAECgMIAwAAAA==.Nenerie:BAAALAAECgMIAwAAAA==.Neontiger:BAABLAAECoEmAAIIAAgIEBObEQAQAgAIAAgIEBObEQAQAgAAAA==.Neosensive:BAAALAADCgUICgAAAA==.Nephthy:BAAALAAECgQIBwABLAAECgcIEgANAAAAAA==.Nerandes:BAABLAAECoEeAAIhAAgIUyNPAwAqAwAhAAgIUyNPAwAqAwAAAA==.Nevira:BAAALAAECggIDwABLAAECggIIwADAKQfAA==.Neytirii:BAAALAADCgcIEQAAAA==.Neytîri:BAAALAAECgIIAgAAAA==.',Ni='Nightblink:BAAALAADCgIIAgAAAA==.Nightfang:BAAALAADCggIFQABLAADCggIFwANAAAAAA==.Nimevyn:BAAALAAECgYICwABLAAECggIIQAKAO0lAA==.Niromi:BAABLAAECoEaAAIUAAcIOBo0PQAAAgAUAAcIOBo0PQAAAgAAAA==.',No='Nobetaforyou:BAAALAAECggICAAAAA==.Noctyra:BAAALAAECgYICwAAAA==.Noice:BAAALAAECgIIAgAAAA==.Noraya:BAABLAAECoEaAAIfAAgI4AE5cQABAQAfAAgI4AE5cQABAQAAAA==.Norlon:BAAALAADCgMIAwAAAA==.Novola:BAAALAADCggIHQAAAA==.',Nr='Nraged:BAAALAADCggIFAAAAA==.',Nu='Nuteller:BAAALAADCggICAAAAA==.',Od='Odinsgeistt:BAAALAADCggICAAAAA==.',Ok='Okara:BAAALAAECgcIEgAAAA==.',Ol='Oldcrow:BAAALAADCgYIBwAAAA==.Oldmcdruid:BAAALAADCggIFgAAAA==.Oldmchexer:BAAALAADCggICAAAAA==.',Om='Ombre:BAAALAADCgcIBwABLAAECgUIBgANAAAAAQ==.',On='Onkelherbert:BAAALAAECggICAAAAA==.',Oo='Oolok:BAABLAAECoEdAAIGAAYIExe0cwCXAQAGAAYIExe0cwCXAQAAAA==.',Or='Orlana:BAAALAADCggIEAAAAA==.',Ox='Oxycôdôn:BAAALAAECggIDwAAAA==.',Pa='Paartunax:BAAALAADCggICAAAAA==.Paladiina:BAAALAADCgEIAQAAAA==.Paladon:BAAALAAECgcIDQAAAA==.Paladrino:BAAALAAECgYIBwAAAA==.Paladöse:BAAALAADCggIHgAAAA==.Palasan:BAAALAADCggIFAAAAA==.Palawin:BAAALAAECgYICAAAAA==.Parallax:BAAALAAECgYIBgABLAAFFAIIAwAXAAgRAA==.Pastoré:BAAALAADCggIEgAAAA==.Pathologe:BAAALAAECgEIAQAAAA==.',Pe='Perry:BAAALAADCgQIAgAAAA==.Person:BAAALAAECgEIAQAAAA==.',Ph='Physjcx:BAABLAAECoEXAAITAAYIlhL2MgCIAQATAAYIlhL2MgCIAQAAAA==.',Pi='Pitter:BAAALAAECggICAAAAA==.Pixelwarri:BAAALAADCgYIBgABLAAECgYIDwANAAAAAA==.',Pl='Plumpshuhn:BAAALAADCggICAAAAA==.',Po='Poernchen:BAAALAAECgIIAgABLAAFFAMICwAMAA4iAA==.Pongratz:BAAALAADCggIEAABLAAECgEIAQANAAAAAA==.Poseides:BAAALAADCggIFAAAAA==.Potator:BAAALAADCgYIBgAAAA==.Powerboyy:BAABLAAECoEWAAIFAAgI2BswMQCIAgAFAAgI2BswMQCIAgABLAAFFAUICQAEABgSAA==.',Pr='Prajah:BAAALAADCgYICQAAAA==.Primeshock:BAAALAADCggICAABLAAECggIJAABAOYaAA==.Prismaadh:BAABLAAECoEWAAIPAAgIPBw2DABuAgAPAAgIPBw2DABuAgAAAA==.Prismamonk:BAABLAAECoEUAAIcAAYI6xi4GQCpAQAcAAYI6xi4GQCpAQAAAA==.Prismawarri:BAAALAAECgUIBQABLAAECgYIFAAcAOsYAA==.Précil:BAAALAAECgYICwAAAA==.',Pu='Pummelchen:BAAALAADCgQIBAAAAA==.Purpleraini:BAAALAADCgQIBAAAAA==.',Py='Pythiâ:BAAALAAECgUIBQAAAA==.',['Pê']='Pêei:BAAALAAECgcIEQAAAA==.',['Pû']='Pûppchén:BAAALAADCgYIBgAAAA==.',Qi='Qio:BAAALAADCgQIBAAAAA==.',Qu='Quaty:BAAALAADCgQIBAAAAA==.',Ra='Radumar:BAABLAAECoEiAAIFAAgI3hLKZgD0AQAFAAgI3hLKZgD0AQAAAA==.Rafur:BAAALAADCggIEwAAAA==.Ragnarög:BAAALAADCggIDwAAAA==.Rahia:BAAALAAECgYIDgAAAA==.Raisina:BAAALAAECgIIAwAAAA==.Raistlinia:BAAALAAECgEIAQAAAA==.Rash:BAACLAAFFIEJAAIEAAUIGBIPBgCzAQAEAAUIGBIPBgCzAQAsAAQKgSsAAgQACAh2JREIAFgDAAQACAh2JREIAFgDAAAA.Rashnal:BAAALAAECgYICQAAAA==.Ratchet:BAAALAADCgEIAQAAAA==.Ravnir:BAAALAADCgIIAwAAAA==.Razorback:BAAALAAECgYIBgAAAA==.',Re='Reacher:BAAALAAECgEIAQAAAA==.Reeo:BAAALAAECgYICwAAAA==.Renadiel:BAAALAADCggIDwAAAA==.Reonattel:BAAALAAECgYIBgAAAA==.Rexxlock:BAAALAADCggIEAABLAAFFAMIDgANAAAAAA==.',Rh='Rhumya:BAAALAAECgIIBgAAAA==.',Ri='Rimold:BAAALAADCggICAAAAA==.',Ru='Ruphus:BAAALAADCggIBwAAAA==.',Ry='Rykard:BAAALAADCggIFAAAAA==.',['Rá']='Rágnâr:BAAALAADCggIDQAAAA==.',['Rä']='Räubernase:BAAALAADCgYIBgAAAA==.',['Ré']='Rétro:BAABLAAECoEhAAMGAAcIqB/FRAARAgAGAAcIfh/FRAARAgACAAYI/xnYPQCmAQAAAA==.',['Rì']='Rìo:BAAALAADCggIEwAAAA==.',['Rú']='Rúin:BAAALAADCgMIAwAAAA==.',Sa='Saevitia:BAAALAAECgYIDAAAAA==.Saginta:BAAALAAECgEIAgAAAA==.Sajra:BAAALAAECgIIBAAAAA==.Sallie:BAAALAADCggIFQAAAA==.Sanemi:BAAALAAECgEIAQAAAA==.Sansabinu:BAABLAAECoEYAAIJAAgIHB31CgCrAgAJAAgIHB31CgCrAgAAAA==.Sansibinu:BAAALAADCggIEAAAAA==.Saraxia:BAAALAADCggIFAAAAA==.Sarnur:BAAALAADCgYICAAAAA==.Saítex:BAABLAAECoEqAAMCAAgIox8qHABuAgACAAcIrR4qHABuAgAGAAgIZBqvPQApAgAAAA==.',Sc='Schamíhaar:BAAALAAECgYIBgABLAAECggIIgAGAH0kAA==.Schandfleck:BAAALAAECggIBgAAAA==.Schigu:BAAALAAECgMIBQAAAA==.Schlafbaer:BAAALAAECgcIEAAAAA==.Schneiper:BAAALAADCgcIAgAAAA==.Schwarzmond:BAAALAADCggIDgAAAA==.Schweinefuß:BAABLAAECoEZAAIFAAcIkhugYAABAgAFAAcIkhugYAABAgAAAA==.',Se='Sebastiann:BAAALAADCgcIBwAAAA==.Secijanah:BAAALAADCggIEAAAAA==.Seech:BAAALAAFFAEIAQAAAA==.',Sh='Shaley:BAAALAAECgIIAwAAAA==.Shamone:BAAALAAECgYICwAAAA==.Shamski:BAAALAAECgUIBQAAAA==.Shayv:BAAALAADCgYIBgAAAA==.Shedena:BAAALAAECgYIDQAAAA==.Sheparrd:BAAALAADCgQIBAABLAAECgIICAANAAAAAA==.Shicha:BAAALAADCggIDgAAAA==.Shimus:BAEALAAECggIEgAAAA==.Shiruhige:BAAALAADCgcIDQAAAA==.Shoa:BAAALAADCgcIBwAAAA==.Showtek:BAAALAADCgcICwAAAA==.Shyrien:BAAALAAECgEIAQAAAA==.Shèldon:BAAALAADCgEIAQAAAA==.',Si='Sibsib:BAAALAAECgQIBAAAAA==.Siggí:BAAALAAECgcICQABLAAECggIFQADAHcgAA==.Sigrîd:BAABLAAECoEVAAIGAAYI/Ak8tAAXAQAGAAYI/Ak8tAAXAQAAAA==.Sillïa:BAABLAAECoEjAAIfAAcIiAM8bwAHAQAfAAcIiAM8bwAHAQAAAA==.',Sl='Slopari:BAABLAAECoEXAAIEAAgIug1FlwCPAQAEAAgIug1FlwCPAQAAAA==.Sloxy:BAAALAAECgYICwAAAA==.',Sn='Snassin:BAAALAADCggIIQAAAA==.Snitzelo:BAAALAADCggICAAAAA==.Snoueagle:BAABLAAECoEVAAIHAAYIighfSwAYAQAHAAYIighfSwAYAQAAAA==.',So='Solsi:BAAALAAECgQIBgAAAA==.Sorvis:BAABLAAECoEZAAMTAAgIFhMaIQD6AQATAAgIFhMaIQD6AQAiAAMIgQxqNQCfAAAAAA==.',Sp='Specialwomen:BAABLAAECoEeAAISAAcItRFgYAAzAQASAAcItRFgYAAzAQAAAA==.Spellbabe:BAAALAADCggIFAAAAA==.Spâcé:BAABLAAECoEeAAIEAAgIPRaITQArAgAEAAgIPRaITQArAgAAAA==.',Sr='Srap:BAAALAADCgYIEQAAAA==.',St='Strixvaria:BAABLAAECoEmAAIaAAgI2SB1DADzAgAaAAgI2SB1DADzAgAAAA==.',Su='Suicid:BAAALAAECgIIAgAAAA==.Sukkuba:BAAALAAECggICAAAAA==.Supersweet:BAAALAADCgQIBAABLAAFFAUIDgAGAIYiAA==.Surzun:BAAALAAECgYIDgAAAA==.Sussi:BAAALAAECgMIBAAAAA==.Sutario:BAAALAAECgcIEwAAAA==.Suzumi:BAAALAAECggICAAAAA==.',Sw='Swiss:BAABLAAECoEUAAIaAAcI6hptIgAlAgAaAAcI6hptIgAlAgAAAA==.',Sy='Syløna:BAAALAAECgUIBQAAAA==.Synæsthesia:BAABLAAECoEbAAIXAAYInxTtcACUAQAXAAYInxTtcACUAQABLAAECggIKQAPACIWAA==.Syrentia:BAAALAAECggICAAAAA==.',['Sá']='Sáliná:BAAALAADCgUIBgAAAA==.',['Sâ']='Sâitô:BAAALAADCgYIBgAAAA==.',['Sê']='Sêraphim:BAABLAAECoEUAAIVAAYI0RVQJgCOAQAVAAYI0RVQJgCOAQAAAA==.',['Sô']='Sôphie:BAAALAADCgQIBAAAAA==.',['Sû']='Sûkku:BAAALAADCgcIBwAAAA==.',Ta='Tabin:BAAALAADCggIEAAAAA==.Tahres:BAAALAADCgQIBAAAAA==.Taithleach:BAAALAAECgYIEgAAAA==.Taladon:BAAALAADCggICAAAAA==.Talaros:BAAALAADCggIDwAAAA==.Talina:BAAALAAECgIIBAAAAA==.Talovdh:BAAALAADCgcIEgABLAAECgIICAANAAAAAA==.Talovhex:BAAALAADCgYIBgAAAA==.Talovpriest:BAAALAAECgIICAAAAA==.Talovstraza:BAAALAADCgIIAgAAAA==.Tamisia:BAAALAAECggIEAAAAA==.Tamîra:BAAALAAECgIIBAAAAA==.Taurinia:BAAALAAECgYIDwAAAA==.Tayosu:BAAALAADCgEIAQAAAA==.',Te='Telanaria:BAAALAAECgYIBgABLAAECggIHAAGAH0fAA==.Telundas:BAAALAAECgMIBAAAAA==.Tendos:BAABLAAECoEiAAIEAAgIliDsGgDsAgAEAAgIliDsGgDsAgAAAA==.Terlo:BAAALAAECgEIAQAAAA==.Terrok:BAAALAADCgQIBAAAAA==.Tevent:BAABLAAECoEXAAMMAAcItQz2ZgCIAQAMAAcItQz2ZgCIAQALAAMIPAHbOQA+AAAAAA==.',Th='Thalodias:BAAALAAECgcICwAAAA==.Tharanel:BAACLAAFFIEOAAMGAAUIhiJZBADmAQAGAAUIhiJZBADmAQACAAEIzRFXLABEAAAsAAQKgSoABAYACAiUJXATAPACAAYACAiUJXATAPACAAIABAjSHs9ZADgBACMAAghtHqYZAJwAAAAA.Tharius:BAABLAAECoEUAAICAAYIWxc8QACcAQACAAYIWxc8QACcAQAAAA==.Thinael:BAAALAAECgYICgABLAAECggIJAADAIwkAA==.Thorvin:BAAALAAECgYICAABLAAFFAUIDgAGAIYiAA==.Thristessa:BAAALAAECgMIAwAAAA==.Thronos:BAAALAAECgYICAAAAA==.Thygrå:BAABLAAECoEeAAIaAAgIKR0UFwCDAgAaAAgIKR0UFwCDAgABLAAFFAUIBgAMAA0RAA==.Thédeaa:BAAALAAECgQIDAAAAA==.',Ti='Tigerlover:BAAALAAECgcIEQAAAA==.',To='Tobsch:BAAALAADCgcIBwAAAA==.Todesseele:BAAALAAECgcIEQAAAA==.Todpandaa:BAAALAADCgQIBAABLAAFFAUICgAPAKEhAA==.Tooper:BAAALAAECggICgAAAA==.Torabora:BAAALAADCgQIBAAAAA==.Tore:BAAALAAECggIBAAAAA==.Toril:BAAALAAECgcIDwAAAA==.',Tr='Trag:BAAALAADCgIIAgAAAA==.Trapmeplz:BAAALAAECggICAABLAAECggICAANAAAAAA==.Trastero:BAAALAAECggICAAAAA==.Trazyn:BAAALAADCgQIBAAAAA==.Trolgar:BAAALAADCggICAABLAAECggIGQATABYTAA==.Troxes:BAAALAADCgYIBwAAAA==.Truxxes:BAAALAADCgcIBwAAAA==.Trèska:BAAALAADCggICAAAAA==.Trøllørd:BAAALAADCgYIBgAAAA==.',Ts='Tschitschi:BAAALAADCggIFwABLAAECggIDgANAAAAAA==.',Tu='Tungusa:BAAALAADCgQIBwAAAA==.',Tw='Twizle:BAAALAAECgYICQAAAA==.',Ty='Tyrella:BAABLAAECoEUAAIOAAYIzh54OwAVAgAOAAYIzh54OwAVAgABLAAECggIJAADAIwkAA==.',['Tá']='Tátí:BAAALAADCgMIBAAAAA==.',['Tì']='Tìxxn:BAAALAAECgYIBgAAAA==.',Ud='Udinson:BAAALAAECgYIDAAAAA==.',Ul='Ultimaratiox:BAAALAAECgYIBgAAAA==.',Un='Unhøøly:BAAALAAECgYIDgAAAA==.Unnei:BAAALAADCgQIBAABLAAECgcIEgANAAAAAA==.',Ur='Uruká:BAAALAADCggICAAAAA==.',Uz='Uzgrim:BAAALAADCggICAAAAA==.',Va='Vadi:BAAALAADCgEIAQABLAADCgYIBgANAAAAAA==.Valaria:BAABLAAECoEaAAICAAcIAh0OOgC4AQACAAcIAh0OOgC4AQAAAA==.Varandis:BAACLAAFFIEDAAIXAAIICBGPMwCZAAAXAAIICBGPMwCZAAAsAAQKgSgAAxcACAjEHO0pAIwCABcACAjEHO0pAIwCAAoAAQhBDskdADkAAAAA.Varmir:BAAALAADCggIDQABLAAECggIHAAGAH0fAA==.',Ve='Vector:BAAALAAECgQIBAAAAA==.Vekthor:BAAALAAECgMIBAAAAA==.Veldora:BAAALAAECgYIEAAAAA==.Velveowar:BAAALAAECggIDgAAAA==.Vendal:BAAALAADCgIIAgAAAA==.Venelor:BAAALAADCgcICwAAAA==.Veneria:BAAALAADCgQIBAAAAA==.Venti:BAAALAAECgEIAQAAAA==.Vernorya:BAAALAAECggICAAAAA==.Verothar:BAAALAAECgUIBQAAAA==.',Vh='Vhorash:BAABLAAECoEVAAMkAAgIgyLmAwAlAwAkAAgIgyLmAwAlAwAhAAUI6Qv3NQD+AAABLAAFFAUICgAPAKEhAA==.',Vi='Vittoria:BAAALAADCgYIBgAAAA==.Vivid:BAABLAAECoEpAAIUAAgI+x6JFgCoAgAUAAgI+x6JFgCoAgAAAA==.',Vo='Voltboy:BAEBLAAECoEUAAMaAAYIDRlcNgCzAQAaAAYIDRlcNgCzAQAIAAEIXQuQPwA3AAABLAAECggIEgANAAAAAA==.',Vu='Vualatan:BAAALAAECgYIDwAAAA==.',Vy='Vyanter:BAAALAADCggIGAAAAA==.',Wa='Waidbauer:BAABLAAECoEWAAIDAAYIByDbVAD7AQADAAYIByDbVAD7AQAAAA==.Walkan:BAAALAAECgYIDwAAAA==.Walldrin:BAAALAAECggIEwABLAAFFAUICAAMAEUcAA==.Warthøg:BAAALAAECggICAAAAA==.',Wh='Whaazlysnipz:BAAALAAECgYIBgAAAA==.',Wi='Wildesding:BAAALAAECgIIAgAAAA==.Wisdom:BAAALAAECgUIAwAAAA==.',Wl='Wlad:BAABLAAECoEaAAIIAAcIPB+SDgA+AgAIAAcIPB+SDgA+AgAAAA==.',['Wé']='Wétwet:BAAALAAECgUIBQABLAAECggICAANAAAAAA==.',Xa='Xanderan:BAAALAAECgYIDgAAAA==.Xaríh:BAAALAAFFAIIAgAAAA==.Xazzar:BAAALAADCggIDgAAAA==.',Xe='Xellus:BAAALAAECgIIAgAAAA==.Xentria:BAAALAADCgYIBgAAAA==.Xerxeß:BAAALAADCgEIAQAAAA==.',Xh='Xhou:BAAALAAECgYICwAAAA==.Xhulbarak:BAAALAAECgYICgABLAAFFAUICgARAO8cAA==.',Xt='Xterra:BAAALAAECgQIBAABLAAFFAIIBgABAMISAA==.',Xy='Xymar:BAABLAAECoEdAAIMAAcIeAshcABwAQAMAAcIeAshcABwAQAAAA==.Xynna:BAAALAADCgYIBgAAAA==.Xyxis:BAAALAADCggIFwAAAA==.',['Xî']='Xîmena:BAAALAAECgIIAwAAAA==.',Ya='Yaavi:BAAALAADCggIDwAAAA==.Yahel:BAAALAAECgUICgAAAA==.Yarw:BAAALAADCgMIAwAAAA==.',Yi='Yilvilna:BAAALAAECgYIDwAAAA==.',Yn='Yngvar:BAABLAAECoEdAAIBAAcIyRU0OwDvAQABAAcIyRU0OwDvAQAAAA==.',Yo='Yondou:BAAALAADCgYICQAAAA==.',Ys='Ysane:BAAALAADCgEIAQAAAA==.',Yu='Yukari:BAAALAAECgYIEgAAAA==.Yumilein:BAAALAAECgcICQAAAA==.',['Yô']='Yôen:BAABLAAECoEfAAMUAAcIuSAyHgB8AgAUAAcIuSAyHgB8AgABAAYIHQnTcQAqAQAAAA==.',Za='Zahìrí:BAABLAAECoEUAAIIAAYIfBMxIQBeAQAIAAYIfBMxIQBeAQAAAA==.Zamael:BAAALAAECgYIDQAAAA==.Zarados:BAAALAADCggIDwAAAA==.Zartas:BAAALAAECgYIBgAAAA==.',Ze='Zenpai:BAAALAAECgYIEQAAAA==.Zentauren:BAAALAADCgcIDgAAAA==.Zeppo:BAAALAADCgQIBAABLAAFFAUICQAEABgSAA==.Zerberius:BAAALAAECgcIDgABLAAFFAIIBQAVAPYUAA==.',Zo='Zombinar:BAAALAADCgUICAAAAA==.Zoopreme:BAAALAADCggICAABLAAECgYIFwATAJYSAA==.Zoppo:BAAALAAECgYIEgAAAA==.Zoshy:BAAALAAECgYIEgAAAA==.',Zu='Zuggy:BAAALAADCgEIAQAAAA==.Zugs:BAABLAAECoEWAAIOAAgI5RzeFwDZAgAOAAgI5RzeFwDZAgAAAA==.Zunara:BAABLAAECoEVAAIGAAYIdxcYeACOAQAGAAYIdxcYeACOAQAAAA==.',Zw='Zwergpresso:BAABLAAECoEUAAIEAAYIoBD+pQB0AQAEAAYIoBD+pQB0AQAAAA==.Zwinklzwonkl:BAAALAAECgcIDQAAAA==.',Zy='Zyralion:BAAALAAECgYIEQAAAA==.',['Zô']='Zôrâc:BAABLAAECoEUAAIOAAgIQyCEEwD3AgAOAAgIQyCEEwD3AgAAAA==.',['Zû']='Zûnade:BAAALAADCgcICQAAAA==.',['Àr']='Àragorn:BAAALAAECgcIEAAAAA==.',['Ár']='Árthur:BAAALAADCgQIBAAAAA==.',['Ân']='Ânimâl:BAAALAAECgYIBgAAAA==.',['Æs']='Æscanor:BAAALAADCggIDgAAAA==.',['Ív']='Ívý:BAAALAADCggIDAAAAA==.',['Ðe']='Ðeadpool:BAAALAADCgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end