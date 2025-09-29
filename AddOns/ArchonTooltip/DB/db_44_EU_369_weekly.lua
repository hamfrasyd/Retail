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
 local lookup = {'Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Warlock-Destruction','Mage-Arcane','Mage-Fire','DeathKnight-Frost','Hunter-BeastMastery','Monk-Brewmaster','DeathKnight-Blood','Paladin-Holy','Rogue-Subtlety','Druid-Feral','Druid-Balance','Rogue-Assassination','DemonHunter-Havoc','DemonHunter-Vengeance','Rogue-Outlaw','Warlock-Demonology','Unknown-Unknown','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','Druid-Restoration','Monk-Windwalker','Paladin-Protection','Warrior-Fury','Evoker-Devastation','Hunter-Marksmanship','Warlock-Affliction','Mage-Frost','Priest-Shadow','Warrior-Protection','Druid-Guardian','DeathKnight-Unholy','Hunter-Survival','Monk-Mistweaver',}; local provider = {region='EU',realm='Garona',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abryco:BAAALAADCggIFQAAAA==.',Ac='Achyll:BAAALAAECgYIDwAAAA==.',Ae='Aegøn:BAAALAAECgYIBwAAAA==.Aelwyn:BAAALAAECgEIAQAAAA==.',Af='Afynyth:BAAALAADCgIIAgAAAA==.',Ah='Ahnnya:BAAALAADCgQICAAAAA==.',Ai='Aikha:BAABLAAECoEeAAMBAAgIXRIHVAC5AQABAAgIXRIHVAC5AQACAAcI7BFVSAC4AQAAAA==.Ainix:BAAALAADCgcIBwAAAA==.',Ak='Akabane:BAAALAADCggICwAAAA==.Akabané:BAAALAADCggIEAAAAA==.Akîra:BAAALAAECgYIDwAAAA==.',Al='Aldric:BAAALAAECgIIAgAAAA==.Alfpipe:BAAALAADCggICAABLAAECggIHAADAHYaAA==.Alicecooper:BAAALAAECgQIAwAAAA==.Althar:BAAALAAECgUIBQAAAA==.Althorack:BAABLAAECoEfAAIEAAcIBAlHjAAmAQAEAAcIBAlHjAAmAQAAAA==.Alura:BAABLAAECoEXAAIFAAgI7wxdZAC3AQAFAAgI7wxdZAC3AQAAAA==.',Am='Amanó:BAAALAADCgIIAwAAAA==.Amidon:BAAALAADCggIDAAAAA==.Améris:BAABLAAECoEXAAMGAAgI5gt4DAAzAQAGAAgI0gt4DAAzAQAFAAUIlwVKtADAAAAAAA==.',An='Andrømède:BAAALAAECgcIEwAAAA==.Antek:BAAALAADCggICAAAAA==.',Ar='Arcrod:BAAALAAECgYIBgAAAA==.Arioch:BAAALAAECggIEwAAAA==.Arkhanhane:BAAALAADCgcICgAAAA==.Aräthörn:BAAALAADCggIBAAAAA==.',As='Ashproof:BAABLAAECoEYAAIHAAgIOxVsiACyAQAHAAgIOxVsiACyAQAAAA==.Asrubalde:BAABLAAECoEmAAIIAAgIsyOXEAACAwAIAAgIsyOXEAACAwAAAA==.Astolfo:BAAALAADCgUIBQAAAA==.',Az='Azarock:BAABLAAECoEVAAIJAAYI8RdxGwCTAQAJAAYI8RdxGwCTAQAAAA==.Azufame:BAAALAADCggICgAAAA==.',Ba='Babardashian:BAAALAAECgEIAQAAAA==.Bashok:BAABLAAECoEYAAMHAAcI3xorWAAVAgAHAAcI3xorWAAVAgAKAAQIQAkEMwCGAAAAAA==.',Be='Behwolf:BAAALAADCggICQAAAA==.Bernkastel:BAAALAAECgcIEgABLAAFFAMICwADAGkkAA==.',Bl='Bloodswordz:BAAALAAECgYICwAAAA==.Bläckyjäck:BAABLAAECoEfAAICAAgICyGKDgAJAwACAAgICyGKDgAJAwAAAA==.',Bo='Bobmorane:BAAALAAECggIEgAAAA==.',Br='Braduval:BAAALAAECgMIAwAAAA==.Brazael:BAAALAADCgYICQAAAA==.Breator:BAABLAAECoEVAAILAAYI0hqJLwCAAQALAAYI0hqJLwCAAQAAAA==.Bricewullus:BAAALAAECgUICAAAAA==.Brubru:BAABLAAECoEZAAMBAAgItRooJABgAgABAAcIdx4oJABgAgACAAgIZwyAUACbAQAAAA==.Brutagrip:BAAALAAECgYIDQABLAAECggIGQABALUaAA==.',Bu='Bubblegum:BAAALAADCgcIBwAAAA==.',Bz='Bzrk:BAAALAAECggIEAAAAA==.',Ca='Caera:BAAALAADCgYIBwAAAA==.Cahlanne:BAAALAAECgIIAwAAAA==.Caraxes:BAAALAAECgYIDAAAAA==.',Ce='Cemillia:BAAALAAECgUICAAAAA==.Cemina:BAAALAAECgYICwAAAA==.',Ch='Chameuuh:BAAALAADCgcICwAAAA==.Chamoulox:BAAALAAECgUICQAAAA==.Chaussonopom:BAABLAAECoEoAAIFAAgIFB3CNABbAgAFAAgIFB3CNABbAgAAAA==.Chocola:BAABLAAECoEVAAIFAAYIBAgzpwD0AAAFAAYIBAgzpwD0AAAAAA==.Choufa:BAABLAAECoEcAAIMAAgIEiDNCQB9AgAMAAgIEiDNCQB9AgAAAA==.Chronosia:BAABLAAECoEjAAIFAAgInBPJTQD8AQAFAAgInBPJTQD8AQAAAA==.Chuckloriss:BAAALAAECgUICQAAAA==.',Cl='Claquemerde:BAAALAAECgIIAgAAAA==.Clëoh:BAABLAAECoEgAAMNAAcIjxWiFgDPAQANAAcIjxWiFgDPAQAOAAEILROmjAA4AAAAAA==.',Co='Copain:BAAALAAECgMIAwABLAAFFAUIEgAPAHkhAA==.Copàïn:BAAALAAECgYIBwABLAAFFAUIEgAPAHkhAA==.Corca:BAAALAADCgEIAQAAAA==.',Cr='Crazydiamond:BAACLAAFFIELAAIDAAMIaSR8CQBEAQADAAMIaSR8CQBEAQAsAAQKgSkAAgMACAg1JkUGAGMDAAMACAg1JkUGAGMDAAAA.Critical:BAAALAAECgEIAQAAAA==.',Cu='Cuthulu:BAACLAAFFIEIAAIQAAIIvR5WHwCsAAAQAAIIvR5WHwCsAAAsAAQKgSsAAxEACAj5GYIRACMCABEACAhsGIIRACMCABAABwgIEnqgAFgBAAAA.',['Cø']='Cøpãin:BAACLAAFFIESAAQPAAUIeSFLBgAvAQAPAAMImiFLBgAvAQAMAAMIvCGDBQAaAQASAAEIzBhABQBUAAAsAAQKgTUABBIACAi6JaIAAF0DABIACAhKJaIAAF0DAAwABwgmI7QGAMECAA8AAwghJepBADABAAAA.Cørzelle:BAAALAAECgMIBAAAAA==.',Da='Daftwullie:BAAALAAECgYIDgAAAA==.Dain:BAAALAAECgYIDAAAAA==.Dakufuraito:BAAALAAECgYIDgABLAAECggILAANAJUjAA==.Darkhx:BAAALAADCggICAAAAA==.Darkløck:BAABLAAECoEUAAMTAAYIjQ8VOABrAQATAAYIjQ8VOABrAQAEAAIIMQYHygBeAAAAAA==.Darkone:BAAALAADCgcICAAAAA==.Darkshamy:BAAALAAECgEIAQAAAA==.Darktwo:BAAALAADCggICAAAAA==.Darkwood:BAABLAAECoEsAAINAAgIlSPdAgA6AwANAAgIlSPdAgA6AwAAAA==.Darkxhunt:BAAALAADCgUIBQAAAA==.Datra:BAAALAADCggICAAAAA==.Davaniella:BAAALAAECggIDwAAAA==.',De='Deadfada:BAABLAAECoEWAAIHAAcI2gswzABBAQAHAAcI2gswzABBAQAAAA==.Deadzr:BAAALAADCggIGgAAAA==.Deathmute:BAAALAADCgEIAQAAAA==.Demandrëd:BAAALAADCgYIBwAAAA==.Desh:BAAALAAECgQIBQABLAAECgUICAAUAAAAAA==.',Di='Diamantfou:BAACLAAFFIEGAAICAAIIQSH0FADAAAACAAIIQSH0FADAAAAsAAQKgSYAAgIACAjGISUPAAQDAAIACAjGISUPAAQDAAEsAAUUAwgLAAMAaSQA.Diëgo:BAAALAADCgIIAgAAAA==.',Do='Dooms:BAABLAAECoEhAAIDAAgI/x71KwCcAgADAAgI/x71KwCcAgAAAA==.Doomsevoker:BAAALAAECgYICAABLAAECggIIQADAP8eAA==.',Dr='Dracozouille:BAAALAADCgYIBgAAAA==.Drakariel:BAAALAAECgEIAQAAAA==.Drakolynette:BAABLAAECoEbAAMVAAcIWwtQCwBvAQAVAAcIWwtQCwBvAQAWAAcImgU9IwAOAQABLAAECgcIIwAXAFQcAA==.Drastark:BAABLAAECoEhAAIDAAcINB5sQwBHAgADAAcINB5sQwBHAgAAAA==.Drical:BAABLAAECoEgAAMYAAgIfw8WRACYAQAYAAgIfw8WRACYAQAOAAEIaApNkwAsAAABLAAFFAIIAgAUAAAAAA==.Dricosh:BAAALAAFFAIIAgAAAA==.Drilic:BAAALAAECgYIDAAAAA==.Drswin:BAABLAAECoEeAAIOAAgIRB7PFwB7AgAOAAgIRB7PFwB7AgAAAA==.',Dt='Dtress:BAABLAAECoEjAAITAAcI6R4yFQAzAgATAAcI6R4yFQAzAgAAAA==.',Du='Dunkie:BAAALAADCggIEgAAAA==.',['Dâ']='Dântéé:BAAALAADCgcICQAAAA==.',['Dæ']='Dædmønk:BAAALAADCggIFwAAAA==.',['Dé']='Déps:BAAALAAECgEIAQAAAA==.',['Dï']='Dïetrich:BAAALAADCgYICgAAAA==.',['Dø']='Dørmammu:BAAALAAECgIIAgAAAA==.',El='Elendariel:BAAALAAECgYIEgAAAA==.Elfihunt:BAAALAADCgUIBwAAAA==.Elfilette:BAAALAAECgcIDwAAAA==.Elnax:BAAALAADCgcIDQAAAA==.Elpololoco:BAAALAADCgYIBwAAAA==.',Em='Emperör:BAAALAAECgMIAwAAAA==.',En='Enero:BAABLAAECoEXAAIYAAYIwBpAOQDGAQAYAAYIwBpAOQDGAQAAAA==.',Eo='Eoliä:BAABLAAECoEmAAIBAAUI0SOeQwDrAQABAAUI0SOeQwDrAQAAAA==.',Ep='Epicmøuse:BAACLAAFFIEJAAIZAAMI3xIyCgCmAAAZAAMI3xIyCgCmAAAsAAQKgRQAAhkACAg/HdcQAHQCABkACAg/HdcQAHQCAAAA.',Er='Erazekiel:BAAALAADCggIGwAAAA==.Erféw:BAAALAAECggIBQAAAA==.Erienne:BAABLAAECoEgAAIDAAgIoCM6DwAsAwADAAgIoCM6DwAsAwAAAA==.',Es='Escanor:BAAALAAECggIDwAAAA==.',Et='Eternété:BAABLAAECoEZAAIRAAYIChboIQBsAQARAAYIChboIQBsAQAAAA==.',Ev='Evena:BAACLAAFFIEOAAIaAAQIhB6yAgBvAQAaAAQIhB6yAgBvAQAsAAQKgS0AAhoACAiKI9UEAB4DABoACAiKI9UEAB4DAAAA.',Ex='Exers:BAAALAAECggIDAAAAA==.',Ez='Ezøp:BAAALAAECggICwAAAA==.',Fa='Faufilé:BAABLAAECoEjAAIQAAcIsB0gQQA2AgAQAAcIsB0gQQA2AgAAAA==.',Fe='Fendral:BAAALAAECgYIDAAAAA==.',Fi='Fineblow:BAAALAAECgUICQAAAA==.Fionaax:BAAALAADCggICAAAAA==.',Fl='Flammeche:BAAALAADCgcICgAAAA==.',Fo='Foufours:BAABLAAECoEcAAIIAAcIXBJpawCrAQAIAAcIXBJpawCrAQAAAA==.',Fr='Friskette:BAAALAADCggIHAAAAA==.',Fu='Furryo:BAABLAAECoEYAAIbAAgIoRatNAAyAgAbAAgIoRatNAAyAgAAAA==.Furtifblanc:BAAALAAECgYICwABLAAFFAYIFwAcAIYiAA==.',Ga='Gaab:BAAALAADCggICAAAAA==.Gaaby:BAAALAADCgYIBgAAAA==.Gabsz:BAAALAADCgcIDQAAAA==.Gabzs:BAAALAAECgMIAwAAAA==.Gajil:BAABLAAECoElAAMEAAgIgh6wHwCrAgAEAAgIgh6wHwCrAgATAAMIvw7LZwCgAAAAAA==.Galawìn:BAABLAAECoEZAAIbAAgIYBhDMwA4AgAbAAgIYBhDMwA4AgAAAA==.Gaélon:BAABLAAECoEsAAIBAAgIhh0xMAAuAgABAAgIhh0xMAAuAgAAAA==.',Ge='Gealdounée:BAAALAAECgIIAwAAAA==.',Go='Goblena:BAAALAADCgcIBwAAAA==.Goldenx:BAAALAADCggIDAAAAA==.',Gr='Granacho:BAABLAAECoEWAAIJAAcIjwmgJgAjAQAJAAcIjwmgJgAjAQAAAA==.Grhöm:BAAALAADCgcIEgAAAA==.Grimg:BAAALAADCgcICgAAAA==.Grodhar:BAABLAAECoEUAAIbAAcI2BkQPQAPAgAbAAcI2BkQPQAPAgAAAA==.Gryrgrax:BAAALAADCgUIBwAAAA==.',Gu='Gum:BAABLAAECoEYAAMIAAYIhxr8iQBpAQAIAAYIhxr8iQBpAQAdAAIIdQemogBLAAAAAA==.',Gw='Gwenha:BAAALAADCgYIBgAAAA==.Gwo:BAABLAAECoEYAAIHAAYINhtObwDiAQAHAAYINhtObwDiAQAAAA==.',['Gü']='Günter:BAAALAAECgUIBgAAAA==.',Ha='Hadrii:BAACLAAFFIEHAAMEAAII7yLHIAC1AAAEAAIIayHHIAC1AAAeAAEIcyTKAwBuAAAsAAQKgS0AAx4ACAjkJD8BAD0DAB4ACAixIz8BAD0DAAQACAiRJIUMACcDAAAA.Hagimage:BAAALAADCgcICAAAAA==.Halebos:BAAALAAECgUIBwAAAA==.Halowa:BAAALAAECgYIBwAAAA==.Hanibhal:BAAALAAECgMIAwAAAA==.Harmonia:BAAALAADCgYIBgAAAA==.Hazgeda:BAABLAAECoEjAAQaAAcIWiAzFAAsAgAaAAcIvB0zFAAsAgADAAcIByA+VAAYAgALAAQIMBGpTQDWAAAAAA==.Hazhelios:BAAALAADCgcIBwABLAAECgcIIwAaAFogAA==.Hazlayk:BAAALAAECgYIDgABLAAECgcIIwAaAFogAA==.',He='Hellboys:BAAALAAECgIIAgAAAA==.',Hi='Hitokirü:BAABLAAECoEYAAIDAAYICBVelgCQAQADAAYICBVelgCQAQAAAA==.Hitoyama:BAAALAADCggIHwAAAA==.',Ho='Hororro:BAAALAAECgYIDQAAAA==.',Hy='Hypergentil:BAAALAAECggIEAAAAA==.Hyzaal:BAAALAAECgYIBgAAAA==.',Ir='Iridia:BAABLAAECoEfAAIBAAcIKRt7OAAQAgABAAcIKRt7OAAQAgAAAA==.',Iv='Iverhild:BAABLAAECoEdAAMfAAgIzhiKFABaAgAfAAgIzhiKFABaAgAFAAIILAZF0ABeAAAAAA==.',Ja='Jafaar:BAACLAAFFIEGAAIKAAII8h1rCACsAAAKAAII8h1rCACsAAAsAAQKgRoAAgoACAh5IuEFAPECAAoACAh5IuEFAPECAAAA.Jaiy:BAAALAADCgIIAwAAAA==.',Je='Jeddead:BAAALAADCgMIAwAAAA==.Jeskodas:BAAALAAECgcIEAAAAA==.Jezàbel:BAAALAAECgYIDgAAAA==.',Jo='Joüx:BAAALAADCggICAABLAAECgEIAQAUAAAAAA==.',['Jë']='Jërykô:BAABLAAECoEsAAIRAAgIryMgBAAeAwARAAgIryMgBAAeAwAAAA==.',Ka='Kaguâ:BAABLAAECoEUAAICAAgI2R+vHgCLAgACAAgI2R+vHgCLAgAAAA==.Kaherdin:BAAALAADCggIDwAAAA==.Kakouzz:BAACLAAFFIEGAAMcAAIIcgmPFgCHAAAcAAIIcgmPFgCHAAAWAAIIgwh2EAB+AAAsAAQKgRsABBwACAjvHJAfAAICABwABwjtG5AfAAICABUABwjMEl0JAKoBABYAAQj2BI05ACwAAAAA.Kalatas:BAAALAAECgEIAQAAAA==.Karaw:BAAALAAECgcIDwAAAA==.Karnilla:BAABLAAECoEcAAIKAAcI/wgfJgAJAQAKAAcI/wgfJgAJAQAAAA==.',Ke='Kellam:BAABLAAECoEnAAIFAAgIOCIaFwDrAgAFAAgIOCIaFwDrAgAAAA==.Kelthorya:BAAALAAECgYICAAAAA==.Kendral:BAABLAAECoEjAAICAAcI6Q/zUACZAQACAAcI6Q/zUACZAQAAAA==.Keros:BAAALAAECgIIAwAAAA==.Ketama:BAAALAAECgIIAgAAAA==.Kezyr:BAAALAADCggIDgAAAA==.',Kh='Khaha:BAAALAADCgEIAQAAAA==.',Ki='Kidhunter:BAAALAAECgcIDwAAAA==.Kilogramprod:BAAALAAECgcICAAAAA==.Kissî:BAACLAAFFIEIAAIgAAIIHiPaDwDRAAAgAAIIHiPaDwDRAAAsAAQKgS0AAiAACAi6JW0CAHIDACAACAi6JW0CAHIDAAAA.Kiz:BAAALAAECgIIAgABLAAFFAIIDAAOAE4gAA==.Kizera:BAAALAADCgcIBwABLAAFFAIIDAAOAE4gAA==.Kizerx:BAACLAAFFIEMAAIOAAIITiAlDwCxAAAOAAIITiAlDwCxAAAsAAQKgSoAAg4ACAh5JDsGAD4DAA4ACAh5JDsGAD4DAAAA.',Ko='Koalatell:BAAALAADCgYICAAAAA==.Kothe:BAAALAAECggIBgAAAA==.Koumba:BAAALAADCggIDgAAAA==.',Ku='Ku:BAAALAAECgYICAAAAA==.Kuaigonjin:BAACLAAFFIEJAAMZAAMIjRpDBgD4AAAZAAMIjRpDBgD4AAAJAAIIlQwLEQBzAAAsAAQKgSgAAwkACAhEH4IKAJACAAkACAh0HIIKAJACABkACAhWHU0UAEkCAAAA.Kurogäne:BAAALAAECgUIBQAAAA==.',Ky='Kynicham:BAABLAAECoEbAAIBAAgIQRlLMQAqAgABAAgIQRlLMQAqAgAAAA==.',La='Labellaw:BAAALAAECggICAAAAA==.Lalina:BAABLAAECoEgAAIcAAgIwBX8IgDkAQAcAAgIwBX8IgDkAQAAAA==.Layam:BAABLAAECoEUAAICAAYI7AblegAEAQACAAYI7AblegAEAQAAAA==.',Le='Legym:BAAALAAECggICAABLAAFFAIIAgAUAAAAAA==.Lei:BAAALAAECgYICAAAAA==.Lepetitedrag:BAAALAAECgEIAQABLAAFFAIIBgAEAFYgAA==.Lerodra:BAABLAAECoEdAAILAAcI5BoWGQAaAgALAAcI5BoWGQAaAgAAAA==.Leynora:BAABLAAECoEbAAISAAcIrRRmCADpAQASAAcIrRRmCADpAQABLAAECgcIIAANAI8VAA==.',Lh='Lhøälex:BAABLAAECoEtAAIHAAgIxyQvDAA1AwAHAAgIxyQvDAA1AwAAAA==.',Li='Liefer:BAAALAAECgYIBgABLAAECggIHAADAHYaAA==.Lieferte:BAABLAAECoEcAAMDAAgIdhpMYQD5AQADAAgIdhpMYQD5AQALAAYInQZ6RwD6AAAAAA==.Liliths:BAAALAAECgYIDQABLAAECgcIEAAUAAAAAA==.Littlejuice:BAAALAAECgYIEgAAAA==.Lixfem:BAAALAADCgcICgAAAA==.',Lo='Lokelaniloke:BAAALAADCgUIBQAAAA==.Loteilin:BAAALAADCgIIAgAAAA==.',Ly='Lycus:BAAALAAECgYICwAAAA==.',['Lõ']='Lõthar:BAAALAAECgcIBwABLAAECggIJgAIALMjAA==.',Ma='Maabout:BAABLAAECoEXAAIFAAgIohb2OwA8AgAFAAgIohb2OwA8AgAAAA==.Maav:BAAALAADCgEIAQAAAA==.Madfog:BAAALAAECgYIBgABLAAFFAcIGgAYAEYaAA==.Magounight:BAAALAADCgYICQAAAA==.Maidisana:BAAALAAECgYIEwAAAA==.Makmk:BAAALAADCgUIBQABLAAECgYIBgAUAAAAAA==.Makoclaque:BAAALAADCggICgAAAA==.Makötao:BAAALAAECgMIAwAAAA==.Malagnyr:BAAALAADCgQIBAAAAA==.Mantax:BAABLAAECoEUAAIOAAgImB8VDwDWAgAOAAgImB8VDwDWAgABLAAECggIGAATAIohAA==.Mara:BAAALAAECgYIBgAAAA==.Maralora:BAABLAAECoEZAAIXAAcIXR7tIwBDAgAXAAcIXR7tIwBDAgAAAA==.',Mc='Mcshadow:BAAALAADCgcICwAAAA==.',Me='Meltosse:BAAALAADCggIDgAAAA==.Meraxès:BAABLAAECoEUAAIWAAgIrhPfEADyAQAWAAgIrhPfEADyAQABLAAECggIIAAcAMAVAA==.Meteorlover:BAAALAADCggICAABLAAFFAIIAgAUAAAAAA==.',Mi='Michi:BAAALAAECgMIBAAAAA==.Miellaa:BAAALAADCgQIBAAAAA==.Mihli:BAAALAAECgYIDQABLAAECggIEgAUAAAAAA==.Miraidon:BAABLAAECoEVAAIcAAgI6ByzEQCQAgAcAAgI6ByzEQCQAgAAAA==.Misstoc:BAABLAAECoEZAAIIAAYIaQXc2QC7AAAIAAYIaQXc2QC7AAAAAA==.',Ml='Mlyn:BAAALAADCgMIAwAAAA==.',Mo='Moinearya:BAAALAADCgYIBwAAAA==.Mordrède:BAAALAADCgQIBAAAAA==.Moreplease:BAACLAAFFIEJAAIhAAIIzQkBGgBxAAAhAAIIzQkBGgBxAAAsAAQKgRcAAiEACAioD+4yAIEBACEACAioD+4yAIEBAAAA.Morganouu:BAABLAAECoEUAAIIAAgIHwPDywDhAAAIAAgIHwPDywDhAAAAAA==.Mortifere:BAABLAAECoEXAAIXAAgIVwNfaQAaAQAXAAgIVwNfaQAaAQAAAA==.',My='Myläne:BAAALAADCgYICgAAAA==.Myr:BAAALAADCgUIBQABLAAECggIHgAEADcYAA==.Myrlight:BAABLAAECoEbAAMDAAgIuhQpWQAMAgADAAgIuhQpWQAMAgALAAYIWBsJJADIAQABLAAECggIHgAEADcYAA==.Myrmana:BAAALAADCggIDgAAAA==.Myrnone:BAABLAAECoEeAAMEAAgINxjuLABiAgAEAAgINxjuLABiAgAeAAEI+AfKOwA5AAAAAA==.Mystæ:BAAALAAECggICAAAAA==.',['Mà']='Màkassh:BAAALAADCggICAAAAA==.',['Më']='Mërcurocromë:BAAALAADCgEIAQAAAA==.',['Mì']='Mìanala:BAAALAAECgYIEgAAAA==.',['Mø']='Mørphe:BAAALAADCggICgAAAA==.',['Mÿ']='Mÿlia:BAABLAAECoEhAAIiAAgIxiPaAQAyAwAiAAgIxiPaAQAyAwAAAA==.',Na='Naerlia:BAAALAADCgUIBQAAAA==.Nainbus:BAABLAAECoEWAAIBAAgIdQiisADiAAABAAgIdQiisADiAAAAAA==.Naini:BAAALAAECgYICAABLAAFFAIIBAAUAAAAAA==.Nainpo:BAAALAAECgYIEgAAAA==.Nanÿ:BAABLAAECoEZAAIhAAYImBL0TgD3AAAhAAYImBL0TgD3AAAAAA==.Narutouss:BAAALAADCgcICAAAAA==.Nashøba:BAAALAAECggIDgAAAA==.Naïnfette:BAAALAADCgIIAgAAAA==.Naïnladin:BAAALAADCgUIBwAAAA==.',Ne='Nereide:BAAALAAECgYIBgABLAAECggIGAAaAEQkAA==.Nerø:BAAALAADCggICgAAAA==.',Ni='Nicala:BAABLAAECoEXAAIYAAcIfBcDMwDjAQAYAAcIfBcDMwDjAQAAAA==.Nidéio:BAAALAAECggIHAABLAAFFAMICAAUAAAAAQ==.Nidéyoth:BAAALAAFFAMICAAAAQ==.Nikaala:BAAALAADCgYIBgAAAA==.Nikitya:BAABLAAECoEhAAIDAAgItxkoSQA2AgADAAgItxkoSQA2AgAAAA==.',No='Norlundo:BAAALAADCgcIBwAAAA==.Novea:BAABLAAECoEYAAIDAAgIXxZsSAA4AgADAAgIXxZsSAA4AgAAAA==.Noziroth:BAABLAAECoEbAAIRAAcIVR54DwA+AgARAAcIVR54DwA+AgABLAAFFAIIAgAUAAAAAA==.',Nu='Numiielia:BAABLAAECoEVAAIcAAYIqxIUMACEAQAcAAYIqxIUMACEAQAAAA==.',Ny='Nybleür:BAAALAAECgYIBgABLAAECgcIGQAgAJYZAA==.',['Nè']='Nèréïde:BAABLAAECoEYAAMaAAgIRCQ1BgAAAwAaAAgIRCQ1BgAAAwADAAUIChGi0wAgAQAAAA==.',Oc='Océannia:BAAALAAECgYIEgAAAA==.',Ok='Okalm:BAAALAAECgYIDwAAAA==.Okapirette:BAABLAAECoEbAAIDAAgI4h0yPABdAgADAAgI4h0yPABdAgAAAA==.Oktier:BAAALAADCgMIAwAAAA==.',Ol='Olgacat:BAACLAAFFIEXAAMcAAYIhiIpAwD0AQAcAAUITSMpAwD0AQAVAAIIXx0AAAAAAAAsAAQKgSkAAxwACAgKJXEEAD4DABwACAgKJXEEAD4DABUAAQj/IXgUAFsAAAAA.',Om='Omayia:BAAALAADCgYIBgAAAA==.Omeada:BAAALAAECgIIAgAAAA==.',Or='Oranika:BAAALAADCgYIDQAAAA==.Orkau:BAAALAAECgUIBwAAAA==.',Oz='Ozza:BAABLAAECoEVAAIdAAgIaBnyQACZAQAdAAgIaBnyQACZAQABLAAFFAYIEgAFAKAbAA==.',Pa='Palenvie:BAAALAAECgcICAAAAA==.Paolinha:BAAALAAECgEIAQAAAA==.Papynou:BAAALAAECgIIAgAAAA==.Pawaxe:BAAALAAECgYICwAAAA==.',Pe='Penyble:BAABLAAECoEZAAIgAAcIlhmzJwAfAgAgAAcIlhmzJwAfAgAAAA==.Pepitö:BAAALAAECgIIAgAAAA==.Pepæ:BAAALAAECgEIAQAAAA==.Perisol:BAAALAAECgYIEwAAAA==.Persifal:BAAALAADCgQIBAAAAA==.Petronille:BAAALAAECgUIBwAAAA==.',Ph='Physali:BAAALAADCgcIBwABLAAECgcIIAANAI8VAA==.',Pi='Piroste:BAABLAAECoEcAAIIAAgIJyAKGgDJAgAIAAgIJyAKGgDJAgAAAA==.',Po='Polnodianno:BAABLAAECoEWAAIHAAgIfRR1YQD/AQAHAAgIfRR1YQD/AQAAAA==.Porképix:BAAALAAECgEIAQAAAA==.Poubz:BAABLAAECoEgAAMLAAgIghDrIwDJAQALAAgIghDrIwDJAQADAAcIVA3gpgBzAQAAAA==.Poubzouk:BAAALAADCggIDAAAAA==.Pouflepalouf:BAAALAADCggIDwABLAAECggIIAAcAMAVAA==.',Pt='Ptipoicarote:BAAALAADCggICAAAAA==.Ptitgui:BAAALAAECgMIAwAAAA==.',Pu='Pushandgo:BAABLAAECoEUAAIEAAcIDQzIaACEAQAEAAcIDQzIaACEAQAAAA==.',['På']='Påpynou:BAAALAAECgYICwAAAA==.',['Pø']='Pøinte:BAAALAAECgcIBwAAAA==.',Qn='Qny:BAAALAADCgMIAwAAAA==.',Qu='Quetzâl:BAAALAAECgcIEQAAAA==.',['Qä']='Qälmünö:BAAALAADCgUIBQAAAA==.',Ra='Radamanthis:BAAALAAECgIIAgABLAAECgYIGwALAMMaAA==.Rahanu:BAAALAADCgIIAwAAAA==.Raminagrobis:BAAALAAECgcIDAAAAA==.Ranzaly:BAAALAADCgEIAQAAAA==.Rastamon:BAAALAADCgcICAAAAA==.Rawh:BAAALAADCgEIAQAAAA==.Rayfinkle:BAAALAADCgQIBAAAAA==.',Re='Rebz:BAAALAAECgIIAgAAAA==.Redeker:BAAALAAECgUIBQABLAAECgYIEwAhAHEkAA==.Revawar:BAAALAAECgMIAwAAAA==.Revhell:BAABLAAECoEZAAMHAAYIhyADbwDjAQAHAAYIhyADbwDjAQAjAAEIYxxUTwBLAAAAAA==.',Ri='Rirheal:BAAALAAECgYICwAAAA==.',Ro='Roccosipetit:BAAALAADCgUIBQAAAA==.Rosebomb:BAAALAAECgQIBAAAAA==.',Ry='Rykoh:BAAALAAECgEIAQAAAA==.Ryudø:BAABLAAECoEXAAMbAAgItx8/HAC8AgAbAAgIex4/HAC8AgAhAAQI+x7yPgBAAQAAAA==.',Rz='Rzâ:BAAALAAECgUIDQAAAA==.',['Rø']='Røcket:BAAALAADCgQIBgAAAA==.Røndubidøu:BAAALAAECgEIAQAAAA==.',['Rû']='Rûbîs:BAAALAADCgcICwAAAA==.',Sa='Saero:BAAALAADCggICAAAAA==.Sakai:BAABLAAECoEcAAIcAAgIJBgLFwBVAgAcAAgIJBgLFwBVAgAAAA==.Sangeilli:BAAALAAECgYICgAAAA==.Sartana:BAAALAADCgYIBwAAAA==.Sartørius:BAAALAAECgcIEAAAAA==.Saurcrocs:BAAALAAECgQIBAAAAA==.Saz:BAAALAADCgcIBwAAAA==.',Se='Seiykø:BAAALAAECggIEwAAAA==.Selucia:BAABLAAECoEYAAIbAAYIZwzEewBLAQAbAAYIZwzEewBLAQAAAA==.Sephis:BAAALAAECgUICAABLAAECgcIIgAKAEwYAA==.Sephix:BAABLAAECoEiAAIKAAcITBjsEgDrAQAKAAcITBjsEgDrAQAAAA==.Serianamu:BAAALAAECgUICgAAAA==.Seryn:BAABLAAECoEbAAIEAAcIRBIXVADBAQAEAAcIRBIXVADBAQAAAA==.',Sh='Shallinfisto:BAABLAAECoEXAAIZAAgINRxDEQBvAgAZAAgINRxDEQBvAgAAAA==.Shallinh:BAAALAADCgYIBgABLAAECggIFwAZADUcAA==.Shaniou:BAAALAAECgQIBAAAAA==.Shanliku:BAAALAAECgYIDAAAAA==.Shenara:BAAALAAECgIIAwABLAAECgcIGQAXAF0eAA==.Sheïyk:BAACLAAFFIEHAAIBAAMIjR1EDAAQAQABAAMIjR1EDAAQAQAsAAQKgRgAAgEACAgxInQMAO0CAAEACAgxInQMAO0CAAAA.Shrakle:BAAALAAFFAIICAAAAQ==.Shëëro:BAABLAAECoEWAAIDAAcIzBK6iACqAQADAAcIzBK6iACqAQAAAA==.Shïper:BAAALAAECgQICQAAAA==.',Si='Sierrakiloo:BAAALAAECggIEwAAAA==.Sikarna:BAAALAAECggICwAAAA==.Silnia:BAAALAADCgEIAQAAAA==.Silyar:BAABLAAECoEXAAIBAAYIyRvCTgDJAQABAAYIyRvCTgDJAQAAAA==.Sintknight:BAABLAAECoEbAAILAAYIwxqNIgDSAQALAAYIwxqNIgDSAQAAAA==.',Sk='Skibloude:BAAALAAECggIBwAAAA==.Skyblløød:BAAALAAECggIAgAAAA==.Skydeath:BAAALAAECgYIEAAAAA==.Skysmash:BAAALAAECggIDgAAAA==.Skystormm:BAAALAAECgUIBQAAAA==.',Sl='Slaxifis:BAAALAADCgUIBQABLAAFFAYIGAAIAHwlAA==.Slevin:BAACLAAFFIEJAAIbAAMIlhrgFQDAAAAbAAMIlhrgFQDAAAAsAAQKgRkAAhsACAjFIHISAP8CABsACAjFIHISAP8CAAAA.Slürm:BAABLAAECoEXAAIkAAYIcRwjCQD7AQAkAAYIcRwjCQD7AQAAAA==.',Sm='Smoz:BAAALAAECgYIDwAAAA==.',Sn='Snyck:BAABLAAECoEhAAMKAAgINiDADABXAgAKAAcICiHADABXAgAHAAgIvBR/WAAUAgAAAA==.',So='Soleîl:BAAALAAECgUIDgAAAA==.Sompa:BAAALAAECgUIBgAAAA==.',Sp='Speakeasy:BAAALAAECgYIBwABLAAECggIGAAYAGckAA==.Spyro:BAAALAADCgEIAQAAAA==.',St='Steziel:BAAALAADCggIFgAAAA==.Stéréo:BAAALAAECgYIBgAAAA==.',Su='Subutex:BAAALAADCggICQAAAA==.Sunja:BAAALAAECgMIAwAAAA==.',Sy='Synopteak:BAAALAAECgYIDgAAAA==.',['Sâ']='Sâw:BAAALAADCggICAAAAA==.',['Sÿ']='Sÿriane:BAABLAAECoEdAAIXAAgIZh6RDQDoAgAXAAgIZh6RDQDoAgAAAA==.',Ta='Taelarion:BAAALAAECgUIBQAAAA==.Taho:BAAALAAECgUIDwAAAA==.Take:BAACLAAFFIEIAAIJAAIIthxsCwClAAAJAAIIthxsCwClAAAsAAQKgSEAAgkACAgLH4AKAJACAAkACAgLH4AKAJACAAAA.Tarãsboulba:BAAALAAECgYIBgABLAAECggIJgAIALMjAA==.Tatoumonkey:BAAALAAECgUICwAAAA==.Taurantes:BAACLAAFFIEYAAMDAAYI6yLrAABsAgADAAYI6yLrAABsAgALAAMICQuzCwDXAAAsAAQKgRkAAgMACAgiIrIlALYCAAMACAgiIrIlALYCAAAA.',Te='Tehura:BAAALAADCggIDwAAAA==.Teraldors:BAAALAAECggICAAAAA==.Tess:BAAALAADCgMIAwAAAA==.',Th='Thalyra:BAAALAAECgYIBgABLAAECggIGwABAEEZAA==.Thaor:BAAALAAECggICAAAAA==.Thâor:BAAALAAECgcIEAAAAA==.',To='Tolch:BAAALAADCgYIBwAAAA==.Tolchuck:BAAALAAECgYIEwAAAA==.Torgunn:BAAALAAECgEIAQAAAA==.Totemixa:BAABLAAECoEhAAIBAAgIQQT0qwDrAAABAAgIQQT0qwDrAAAAAA==.Toufoux:BAAALAAFFAIIAgAAAA==.',Tr='Trodzia:BAABLAAECoEeAAILAAgIrBP9HwDkAQALAAgIrBP9HwDkAQAAAA==.Trèv:BAABLAAECoEiAAIXAAcIqBUmOQDTAQAXAAcIqBUmOQDTAQAAAA==.Trøllya:BAAALAAECgYIDAAAAA==.Trøy:BAAALAAECggICAAAAA==.',['Tà']='Tàlim:BAABLAAECoEbAAIHAAYItyJkXAALAgAHAAYItyJkXAALAgAAAA==.',['Tä']='Tälim:BAABLAAECoEUAAIdAAYIaR5RPwCgAQAdAAYIaR5RPwCgAQAAAA==.',['Tð']='Tðyesh:BAAALAADCgYIBwAAAA==.',['Tö']='Töøc:BAABLAAECoEWAAMjAAgIPyCMCAC8AgAjAAgIPyCMCAC8AgAHAAcI0AqpzABAAQAAAA==.',Ud='Uddymurphy:BAAALAAECgUIBQAAAA==.',Um='Umberlee:BAAALAADCggICAAAAA==.',Va='Vadh:BAAALAADCgUIBwAAAA==.Valaena:BAAALAAECgcIEwAAAA==.Valgorn:BAABLAAECoEfAAMFAAcIsBYgXADQAQAFAAcIlRMgXADQAQAfAAYIPhFRPABaAQAAAA==.Valløris:BAAALAAECgUIBQAAAA==.Vanael:BAAALAAECgcIEAAAAA==.Vandraxi:BAABLAAECoEZAAIeAAYIkhkhDQDDAQAeAAYIkhkhDQDDAQAAAA==.',Vi='Vicious:BAAALAAFFAIIAwAAAA==.Vitalitys:BAABLAAECoEUAAIOAAgIwyJ2EgCyAgAOAAgIwyJ2EgCyAgAAAA==.',Vr='Vraccas:BAAALAADCggICQAAAA==.',['Và']='Vàna:BAAALAAECgUICAAAAA==.',['Vä']='Vänder:BAAALAAECgYIDAAAAA==.',We='Weubi:BAABLAAECoESAAMjAAYI7B7lKQBVAQAjAAYI7B7lKQBVAQAHAAEIbQCDYwEIAAAAAA==.',Wh='Whitedram:BAABLAAECoEYAAIJAAYIJxmXGgCdAQAJAAYIJxmXGgCdAQABLAAECgcIFwAcAFkWAA==.',Wi='Winds:BAAALAAECgYIBgAAAA==.',Wo='Wolfrie:BAAALAADCggIGQAAAA==.Wolvgang:BAABLAAECoEaAAIIAAcITBauagCsAQAIAAcITBauagCsAQAAAA==.Woopssy:BAAALAAFFAIIAgAAAA==.Worldd:BAABLAAECoEdAAICAAgI4hjMJQBdAgACAAgI4hjMJQBdAgAAAA==.Wouahoioi:BAABLAAFFIEIAAMYAAMIDRWlHQCQAAAYAAMIDRWlHQCQAAAOAAEIPgAGIwAPAAAAAA==.',Xi='Xiandarius:BAACLAAFFIEGAAIDAAIIYw5tMQCbAAADAAIIYw5tMQCbAAAsAAQKgSUAAgMACAijFt9IADcCAAMACAijFt9IADcCAAAA.',Xo='Xonara:BAAALAAECgcICQABLAAECggIHgAEADcYAA==.',Xz='Xzensh:BAAALAADCgcIBwABLAAECggIGAAaAEQkAA==.',Ya='Yakuzas:BAAALAADCgQIBAAAAA==.Yavanna:BAAALAADCgcIBwAAAA==.',Yh='Yhwa:BAABLAAECoEYAAIFAAcIXhwHOgBEAgAFAAcIXhwHOgBEAgAAAA==.',Yu='Yumîko:BAAALAADCgYIBgAAAA==.Yuri:BAAALAAECgIIAgABLAAECgYICwAUAAAAAA==.',Yv='Yvalf:BAAALAAECgUICgAAAA==.',['Yä']='Yäku:BAABLAAECoEZAAIgAAYIVBo1PACtAQAgAAYIVBo1PACtAQAAAA==.',Za='Zaphicham:BAAALAAECgUICQAAAA==.Zargun:BAAALAAECgIICAABLAAECgcIGQAXAF0eAA==.',Ze='Zemeno:BAACLAAFFIEXAAMeAAYI6BsaAABGAgAeAAYI6BsaAABGAgAEAAIINAVnNQCIAAAsAAQKgTAAAh4ACAieJYwAAG4DAB4ACAieJYwAAG4DAAAA.Zepandawan:BAABLAAECoEeAAIlAAgIkwyYHwB9AQAlAAgIkwyYHwB9AQAAAA==.Zepheus:BAAALAADCggICAABLAADCggIFQAUAAAAAA==.Zepheüs:BAAALAADCggIFQAAAA==.Zephs:BAAALAAECgYICQAAAA==.',Zi='Zilë:BAAALAAECgcIEwAAAA==.',Zo='Zouille:BAAALAADCgYIBgAAAA==.Zoulzi:BAAALAADCgMIAwAAAA==.',['Äu']='Äusträ:BAAALAADCgEIAQAAAA==.',['Äz']='Äzazelle:BAAALAADCgcIBwAAAA==.',['Ça']='Çavadrood:BAAALAAECgMIAwABLAAECgQICQAUAAAAAA==.Çavavoker:BAAALAAECgQICQAAAA==.',['Ïn']='Ïnfer:BAAALAADCgcIBwAAAA==.',['Ðr']='Ðrøwzer:BAABLAAECoEYAAIOAAgIFw5MNgCzAQAOAAgIFw5MNgCzAQAAAA==.',['Óm']='Ómirrëa:BAABLAAECoEYAAIIAAYIsxjOggB4AQAIAAYIsxjOggB4AQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end