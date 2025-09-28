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
 local lookup = {'Rogue-Subtlety','Rogue-Assassination','Druid-Balance','Druid-Feral','Unknown-Unknown','Priest-Shadow','DeathKnight-Blood','DemonHunter-Vengeance','Warlock-Destruction','Mage-Arcane','Paladin-Retribution','Warrior-Fury','Priest-Holy','Shaman-Enhancement','Shaman-Elemental','Paladin-Protection','Shaman-Restoration','DemonHunter-Havoc','Evoker-Devastation','Evoker-Preservation','Warrior-Protection','DeathKnight-Frost','DeathKnight-Unholy','Druid-Restoration','Hunter-BeastMastery','Warrior-Arms','Mage-Frost','Priest-Discipline','Monk-Brewmaster','Paladin-Holy','Druid-Guardian','Hunter-Marksmanship','Warlock-Demonology','Warlock-Affliction','Monk-Mistweaver',}; local provider = {region='EU',realm='Gorgonnash',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Actròn:BAAALAADCggICgAAAA==.',Ad='Adalacuir:BAAALAAECgIIAgAAAA==.',Ae='Aeliria:BAABLAAECoEXAAMBAAcIiBlPEQD/AQABAAcIiBlPEQD/AQACAAEIrAdhZwAsAAAAAA==.',Ag='Agradar:BAAALAAECgIIAgAAAA==.',Ah='Ahouúúuuúuuú:BAAALAADCgcIBwAAAA==.',Aj='Ajesh:BAABLAAECoEbAAMDAAYItiFTIAA0AgADAAYItiFTIAA0AgAEAAQI0BKwLADoAAAAAA==.',Al='Aldabautz:BAAALAAECgMIAwAAAA==.Alenja:BAAALAADCggIGQAAAA==.',Am='Amrek:BAAALAADCgYIBgAAAA==.',An='Anaturielle:BAAALAAECgIIBAAAAA==.Anrâeth:BAAALAAECggICAAAAA==.Antarés:BAAALAADCgYIBgAAAA==.',Ar='Araes:BAAALAAECgYIDgABLAAECgYIDwAFAAAAAA==.Arconia:BAABLAAECoEaAAIGAAgIdBEFMADuAQAGAAgIdBEFMADuAQAAAA==.Artêmîs:BAAALAADCgYIBgAAAA==.Arïadne:BAABLAAECoEfAAIHAAgI/h9eBgDlAgAHAAgI/h9eBgDlAgAAAA==.',As='Asak:BAAALAADCggICAAAAA==.Asilda:BAAALAAECggIBQAAAA==.Aske:BAAALAAECgUICAAAAA==.',Au='Aufzieheule:BAAALAAFFAIIBAAAAA==.',Az='Azmodeus:BAAALAAECgIIAgAAAA==.Azulâ:BAAALAADCggIEwAAAA==.Azzar:BAABLAAECoEVAAIIAAYIch8+EgAZAgAIAAYIch8+EgAZAgAAAA==.',Ba='Baldor:BAAALAADCggIDQAAAA==.Banged:BAAALAAECgUIBgABLAAECgYIFAAIAPEVAA==.',Be='Bebo:BAAALAADCggICAAAAA==.Beckie:BAAALAADCgIIAgAAAA==.Benedikt:BAAALAADCggICAAAAA==.',Bi='Bibabutzi:BAABLAAECoEUAAIJAAYIugdpkQAYAQAJAAYIugdpkQAYAQAAAA==.Bigdino:BAAALAADCgYICQAAAA==.',Bj='Bjun:BAABLAAECoEVAAIKAAYI3R8PPgA0AgAKAAYI3R8PPgA0AgABLAAECggIBgAFAAAAAA==.',Bl='Bljat:BAAALAAECgQIBAABLAAECggIIwALAJUlAA==.Bloodshivâ:BAAALAAECgEIAQABLAAECgcIGgAGAKkSAA==.Bloody:BAACLAAFFIEJAAIMAAMIKxtKDwAIAQAMAAMIKxtKDwAIAQAsAAQKgS8AAgwACAjzI+MLAC8DAAwACAjzI+MLAC8DAAAA.Blowboi:BAAALAADCgYIDAAAAA==.',Bo='Boblox:BAAALAADCggIDwAAAA==.',Br='Brahless:BAABLAAECoEZAAMCAAgIwQg0MACYAQACAAgIwQg0MACYAQABAAcINQBKSgAFAAABLAAFFAMIBAAFAAAAAA==.Bratak:BAAALAAECgIIAwAAAA==.Breeze:BAAALAAECgYIBgAAAA==.Brewswayne:BAAALAADCgMIAgAAAA==.Brèwslee:BAAALAAECgEIAQABLAAECgYIDgAFAAAAAA==.',Bu='Bufar:BAAALAADCggIEAAAAA==.Burzum:BAABLAAECoEVAAIJAAYIFREIbgB1AQAJAAYIFREIbgB1AQAAAA==.Butch:BAAALAADCggIEAAAAA==.Butchor:BAAALAAECggICQAAAA==.',Ca='Caco:BAAALAADCgYIDAAAAA==.Calos:BAAALAAECgEIAQAAAA==.Calwen:BAAALAAECgYIBgAAAA==.Camayne:BAAALAADCgEIAQAAAA==.Carbonicum:BAAALAAECggICgAAAA==.Carsath:BAAALAAECggIEgAAAA==.Caty:BAABLAAECoEmAAINAAgILBTSOADUAQANAAgILBTSOADUAQAAAA==.Cazador:BAAALAAECgYIDwAAAA==.',Cb='Cbrah:BAAALAAECgYIEAAAAA==.',Ce='Celes:BAAALAAECgYIBgAAAA==.Celestha:BAAALAADCgcIBwAAAA==.Celso:BAABLAAECoEUAAMOAAgIpg86DwDOAQAOAAgIpg86DwDOAQAPAAYIZgBNsgApAAAAAA==.',Ch='Charlierunkl:BAAALAAECgYIEwAAAA==.Cheripala:BAABLAAECoEZAAMLAAgIqBI7cADZAQALAAgIUw87cADZAQAQAAcIchJSKQB3AQAAAA==.',Cl='Clancy:BAAALAAECggICAAAAA==.',Co='Coffeeshock:BAACLAAFFIEGAAIRAAIIkgYiQgBpAAARAAIIkgYiQgBpAAAsAAQKgSUAAhEACAh7ECJmAIkBABEACAh7ECJmAIkBAAAA.Cowabunga:BAAALAAECgYIBgAAAA==.',Cr='Crivid:BAAALAADCgYICAAAAA==.',Da='Dakulana:BAAALAADCgQIBAAAAA==.Daregas:BAAALAAECgMIBQAAAA==.Daror:BAAALAAECgYICAAAAA==.Darula:BAAALAADCgcIBwAAAA==.Dashael:BAABLAAECoEkAAISAAcI1RzhTgALAgASAAcI1RzhTgALAgAAAA==.',De='Deathstroyer:BAAALAAECgIIAgAAAA==.Deathvoker:BAABLAAECoElAAMTAAgIihP6IgDkAQATAAcIKhX6IgDkAQAUAAEIBQOdPAAVAAAAAA==.Derain:BAAALAAECggIDgABLAAECggIFAAVAL8HAA==.Derarzt:BAAALAADCgMIAwAAAA==.Derknortz:BAAALAAECggIEAAAAA==.Devrill:BAAALAADCgMIAgAAAA==.',Dh='Dhuun:BAAALAADCggIFgAAAA==.',Di='Dinermoe:BAACLAAFFIESAAIMAAYI7x9UAQB6AgAMAAYI7x9UAQB6AgAsAAQKgTIAAgwACAjEJjECAIADAAwACAjEJjECAIADAAAA.',Do='Domar:BAAALAADCggICAABLAAFFAMICQAMAJYRAA==.Dontknow:BAAALAAECgcIEgAAAA==.Dovarâ:BAAALAAFFAMICgAAAQ==.',Dr='Dreadnought:BAAALAAECgIIAgAAAA==.Drfaust:BAAALAAECgMIBgAAAA==.Drui:BAAALAADCgcIBwAAAA==.Druidmom:BAAALAADCgYIBgAAAA==.Drurain:BAAALAAECggICAABLAAECggIFAAVAL8HAA==.',Ds='Dschängo:BAABLAAECoEUAAIMAAcIOhKRUADIAQAMAAcIOhKRUADIAQAAAA==.',Du='Ducacell:BAAALAADCggIGQAAAA==.Dungarus:BAAALAAECggICAAAAA==.Dunkelmut:BAAALAAECgEIAQAAAA==.Durain:BAAALAAECggIEAABLAAECggIFAAVAL8HAA==.',Ea='Eardiincrit:BAAALAADCggICAABLAAECgMIAwAFAAAAAA==.Eardin:BAAALAAECgMIAwAAAA==.',Ed='Edgewalker:BAABLAAECoEbAAMWAAYIjR87YgD+AQAWAAYIjR87YgD+AQAXAAYIUReIJQB2AQAAAA==.',El='Elairys:BAAALAAECgYIEQABLAAECggIGAANADUaAA==.Elfenlîed:BAAALAADCgQIBAAAAA==.Elfilein:BAABLAAECoElAAINAAgIihWeLAATAgANAAgIihWeLAATAgAAAA==.',En='Enju:BAAALAADCggIGAAAAA==.',Eo='Eowewia:BAAALAADCgUIBQAAAA==.',Er='Eri:BAAALAAECgYIEQAAAA==.',Ev='Evodra:BAAALAAECgIIAgAAAA==.',Ew='Ewolet:BAAALAAECgcIEgAAAA==.',Fa='Fahne:BAAALAAECgcIEwAAAA==.',Fi='Filia:BAABLAAECoEaAAIYAAcI0BkVLgD7AQAYAAcI0BkVLgD7AQAAAA==.',Fl='Flamjorosaja:BAAALAAECggIBAAAAA==.',Fo='Forukos:BAABLAAECoEXAAIDAAgIiCI6DQDrAgADAAgIiCI6DQDrAgABLAAECggIFQAKAEwLAA==.Fotem:BAABLAAECoEjAAILAAgIlSX1BQBmAwALAAgIlSX1BQBmAwAAAA==.',Fr='Friedali:BAAALAAECggICAABLAAECggILwAZAHsiAA==.Frêiundwild:BAAALAADCggIFQAAAA==.',Ge='Gefrierkombi:BAAALAADCggICAABLAAFFAYIEgAMAO8fAA==.Geralynde:BAAALAAECgQIBAABLAAECggIBQAFAAAAAA==.Germag:BAAALAADCgcIBwABLAAECgMIBQAFAAAAAA==.',Gl='Gleam:BAAALAADCgEIAQAAAA==.',Gn='Gnarku:BAACLAAFFIEZAAMMAAcI2yQrAAD/AgAMAAcI2yQrAAD/AgAaAAQIjhxcAACOAQAsAAQKgSMAAwwACAjWJjMDAHUDAAwACAjMJjMDAHUDABoABgg+JmUFAKACAAAA.',Go='Gosa:BAAALAAECgQIBgAAAA==.',Gr='Greenfrog:BAAALAAECgEIAQAAAA==.Greldo:BAAALAADCggICgAAAA==.Grodak:BAAALAAECgYICQAAAA==.Groldak:BAAALAAECgIIAgAAAA==.Groldan:BAAALAAECggIBgAAAA==.Gromrak:BAAALAAECgMIBAAAAA==.',Gu='Gumse:BAABLAAECoEWAAILAAcInxwSewDDAQALAAcInxwSewDDAQAAAA==.',Ha='Hachtel:BAAALAAECggIEAAAAA==.Hachtelei:BAABLAAECoEaAAILAAgInQcwyAA2AQALAAgInQcwyAA2AQAAAA==.Halexorn:BAAALAADCgcIBwAAAA==.Harzor:BAAALAADCgIIAgAAAA==.Hawai:BAAALAADCgcIBwAAAA==.',He='Headshock:BAACLAAFFIEJAAIPAAMIGRwbDgAJAQAPAAMIGRwbDgAJAQAsAAQKgR4AAg8ACAi2JGsJADYDAA8ACAi2JGsJADYDAAAA.Hederia:BAAALAADCgcIBwAAAA==.Herbe:BAAALAAECgEIAQAAAA==.Heschdinitäg:BAAALAAECgYICwAAAA==.Hexerion:BAABLAAECoEXAAIJAAcIAAsfcQBtAQAJAAcIAAsfcQBtAQAAAA==.',Ho='Hodgepodge:BAAALAADCgcIBwABLAAECgYICwAFAAAAAA==.Hokey:BAAALAADCgUIBQABLAAECggIHQAbAAIgAA==.',['Hö']='Hörä:BAABLAAECoEcAAMCAAcIQRroMgCIAQACAAUIZBroMgCIAQABAAQIeRbNKgAJAQAAAA==.',Ia='Iamdone:BAAALAADCgcIBwABLAAECgEIAQAFAAAAAA==.',Ic='Icykaty:BAAALAAECggIEQAAAA==.',Id='Idy:BAABLAAECoEeAAMcAAgIqSC+AQD1AgAcAAgIqSC+AQD1AgANAAQIXhEqewDdAAAAAA==.',Il='Illil:BAABLAAECoEUAAMIAAYI8RUSKQA2AQAIAAYI8RUSKQA2AQASAAQIaAnV4AC9AAAAAA==.',In='Infernîa:BAABLAAECoEdAAIJAAcIEhUhVwC3AQAJAAcIEhUhVwC3AQAAAA==.Ingrain:BAABLAAECoEUAAIVAAgIvwe/TAAAAQAVAAgIvwe/TAAAAQAAAA==.',Ja='Jacktronghop:BAAALAADCgYIBgAAAA==.Jadarc:BAAALAADCgcICAAAAA==.Jahi:BAAALAADCggICAAAAA==.',Je='Jelia:BAAALAAECgIIAgAAAA==.Jeroquee:BAAALAAECgMIAwAAAA==.',Ka='Kalmar:BAAALAAECgYIEwAAAA==.Kamuii:BAAALAAECggICAAAAA==.Kanaruto:BAAALAAECgQICAAAAA==.',Kn='Knoppers:BAAALAADCggIDwAAAA==.',Ko='Kokoro:BAAALAAECgMIAwAAAA==.Kommandognom:BAAALAADCgEIAQAAAA==.',Kr='Kredlock:BAAALAAECgEIAQABLAAECggIBQAFAAAAAA==.Krisu:BAAALAAECgcIDAAAAA==.Kroot:BAAALAAECgYIDQABLAAECgcIEgAFAAAAAA==.',Ku='Kurage:BAAALAADCgYICAAAAA==.',['Kü']='Kürbiskante:BAAALAAECgYIDwAAAA==.',La='Layla:BAAALAAECgYIEgAAAA==.',Le='Lehonk:BAAALAADCgcIDQABLAAECgYIDwAFAAAAAA==.Leonie:BAAALAADCggICwABLAAECggIJQATAIoTAA==.',Li='Liná:BAAALAAECgUIBwAAAA==.Lipovka:BAAALAADCggIEAAAAA==.',Lo='Lovealotbear:BAABLAAECoEmAAIdAAgIfxOKFADtAQAdAAgIfxOKFADtAQAAAA==.',Lu='Luaná:BAAALAAECgcIBwAAAA==.Lummelinchen:BAABLAAECoEXAAMeAAgIKiAgBwDfAgAeAAgIKiAgBwDfAgALAAEIqwLgTQEbAAAAAA==.Lustlurch:BAAALAADCggICAAAAA==.',Ly='Lyraja:BAAALAAECggIEQAAAA==.',Ma='Maelisandre:BAAALAADCgIIAgAAAA==.Maetzlor:BAAALAAECgcIDwABLAAFFAIIBQALAOoaAA==.Magecore:BAABLAAECoEUAAIKAAgIqxr3OgBAAgAKAAgIqxr3OgBAAgABLAAFFAUIDgALADMcAA==.Mahoni:BAAALAAECgMIAwAAAA==.Makuta:BAAALAADCgMIAwAAAA==.Mandus:BAAALAADCggIFAABLAAFFAIIBQALAOoaAA==.Mannus:BAAALAADCggICAAAAA==.Matunos:BAABLAAECoEUAAIfAAYI2xfPEACNAQAfAAYI2xfPEACNAQAAAA==.',Mc='Mcgyver:BAAALAAFFAIIAwAAAA==.',Me='Mentos:BAAALAADCggICAAAAA==.',Mi='Milandiz:BAAALAADCggIHAAAAA==.Milanny:BAABLAAECoEuAAIBAAgIKRrhCwBSAgABAAgIKRrhCwBSAgAAAA==.Miltankk:BAACLAAFFIEIAAIWAAIIiR2LJwCzAAAWAAIIiR2LJwCzAAAsAAQKgSIAAhYACAiUI+gbAOMCABYACAiUI+gbAOMCAAAA.Mindsoul:BAAALAAECgIIAgAAAA==.Minervá:BAABLAAECoEfAAIQAAcIIhGvKAB8AQAQAAcIIhGvKAB8AQAAAA==.Miø:BAAALAADCggIDgAAAA==.',Mo='Molari:BAABLAAECoEUAAIDAAYI5RRvPACVAQADAAYI5RRvPACVAQAAAA==.Moozy:BAAALAADCggICAAAAA==.Moro:BAAALAAECgEIAQAAAA==.Morvenna:BAABLAAECoEeAAIMAAcIKRi5PQAMAgAMAAcIKRi5PQAMAgAAAA==.Motion:BAAALAAECgYIDQAAAA==.',Mu='Muggle:BAABLAAECoEWAAIKAAYIdBj+XgDHAQAKAAYIdBj+XgDHAQAAAA==.Mugshot:BAAALAADCggICQAAAA==.Muho:BAAALAAECgYIEwAAAA==.',My='Myrafae:BAABLAAFFIEHAAIWAAII0x8gKACyAAAWAAII0x8gKACyAAAAAA==.',Na='Nalind:BAAALAADCggIDAAAAA==.',Ne='Nelyn:BAAALAAECgUICQABLAAECgcIEgAFAAAAAA==.Nerzan:BAAALAAECgYIDAAAAA==.',Ni='Niemand:BAAALAAECgEIAQABLAAECgMIBQAFAAAAAA==.Nightbowler:BAAALAADCggICwAAAA==.Nightshoot:BAAALAAECgIIAgABLAAECgYIDgAFAAAAAA==.Niralta:BAAALAADCgEIAQAAAA==.',No='Noobhunter:BAAALAAECgYICwAAAA==.Nordo:BAABLAAECoEgAAIWAAgImxvwQQBRAgAWAAgImxvwQQBRAgAAAA==.Noxh:BAAALAAECgMIAwAAAA==.Noxit:BAAALAAECgYICQABLAAFFAYIDgATAFMeAA==.Noxll:BAABLAAECoEdAAIgAAcIZhfbMQDhAQAgAAcIZhfbMQDhAQAAAA==.',Nu='Nuvielle:BAAALAAECggICgAAAA==.',Ny='Nymora:BAAALAAECgcICgAAAA==.',Ob='Obipriest:BAAALAAECgYIBgAAAA==.',Oh='Ohnezahn:BAABLAAECoEgAAMUAAgIdhFiEwDKAQAUAAgIdhFiEwDKAQATAAcIPhKBLQCVAQAAAA==.',Or='Orthos:BAAALAAECgMIAwAAAA==.',Pa='Pallyboi:BAAALAADCggICAAAAA==.',Pe='Perfect:BAAALAAECgYIDAAAAA==.',Ph='Philirose:BAABLAAECoEUAAIZAAcInwkmmwBIAQAZAAcInwkmmwBIAQAAAA==.',Po='Pogress:BAAALAADCggICAAAAA==.',Pp='Ppati:BAABLAAECoEdAAIbAAcINxRsKADAAQAbAAcINxRsKADAAQABLAAECggIJwADAFYdAA==.',Pr='Proddy:BAAALAAECgMIAwAAAA==.',Ps='Psychosalami:BAAALAADCggICAABLAAFFAUIEAASAHcUAA==.',Pu='Pullover:BAAALAADCgcICQAAAA==.Punkdaft:BAAALAAECgEIAQAAAA==.Puppal:BAAALAADCgIIAgAAAA==.',['Pà']='Pàti:BAABLAAECoEnAAIDAAgIVh21EgCvAgADAAgIVh21EgCvAgAAAA==.',Qi='Qisma:BAAALAAECgYIEwAAAA==.',Qu='Quap:BAAALAADCgYIBgAAAA==.Qumi:BAAALAAECgcIEQAAAA==.',Ra='Ra:BAABLAAECoEgAAIZAAcIURL/cACdAQAZAAcIURL/cACdAQAAAA==.Rachun:BAABLAAECoEaAAMOAAYIyxhgEAC6AQAOAAYIyxhgEAC6AQARAAEIWwEOIAERAAABLAAFFAUIDgALADMcAA==.Rahmalla:BAAALAAECggIEAAAAA==.Rasaged:BAAALAADCgYIBgAAAA==.Ravyn:BAAALAAECgcICgAAAA==.Rayne:BAAALAAECgYICwAAAA==.',Re='Reiju:BAAALAADCgcIBwAAAA==.',Rh='Rhaegalion:BAAALAAECgEIAQAAAA==.',Ri='Rillu:BAAALAAECgMIAwAAAA==.Ripmeta:BAAALAAECgIIAgABLAAFFAMICQAZAHQcAA==.Riyria:BAAALAAECgMICQAAAA==.',Ro='Rodríguez:BAABLAAECoEZAAIWAAgIgh+NKACqAgAWAAgIgh+NKACqAgAAAA==.Rogni:BAAALAAECgYIBwAAAA==.Rompo:BAABLAAECoEdAAIZAAgICBwgJQCMAgAZAAgICBwgJQCMAgABLAAFFAMICQAMAJYRAA==.',Ru='Runeston:BAAALAAECgYIBgAAAA==.',Ry='Ryson:BAABLAAECoEkAAMLAAgIuxtvQQBNAgALAAgI+RhvQQBNAgAQAAYIDR0SQQDbAAAAAA==.',['Rô']='Rôwdypiper:BAABLAAECoEXAAMMAAYIihTmXgCcAQAMAAYIihTmXgCcAQAVAAII9Am7cwBGAAAAAA==.',['Rü']='Rüdiggar:BAAALAAECgYIBgAAAA==.',Sa='Samtpfote:BAAALAADCgUIBgAAAA==.Saphira:BAAALAAECgUIBwAAAA==.',Sc='Schmirgol:BAAALAAECgYIDwAAAA==.Scylla:BAAALAADCgcIBwAAAA==.',Se='Searx:BAAALAADCgcIFAABLAAECggIKAASACQlAA==.Securisdei:BAAALAAECgcIDwAAAA==.Selan:BAAALAAECgYIEwAAAA==.Seleneira:BAAALAAECgMICAAAAA==.Sella:BAAALAADCggIGwAAAA==.Semilock:BAAALAAECgMIBQAAAA==.Serdeath:BAABLAAECoEYAAIWAAYIMh5XYQD/AQAWAAYIMh5XYQD/AQAAAA==.Seàrx:BAAALAADCgcIBwAAAA==.Seára:BAABLAAECoEoAAISAAgIJCWTCQBHAwASAAgIJCWTCQBHAwAAAA==.',Sg='Sgtlarry:BAAALAAECgYIDAAAAA==.',Sh='Shacó:BAAALAADCgcIDQAAAA==.Shakuna:BAABLAAECoEZAAIGAAcIqhL9OQC4AQAGAAcIqhL9OQC4AQAAAA==.Shanní:BAAALAADCgYIBgAAAA==.Shi:BAAALAAECgQIBAAAAA==.Shockwave:BAABLAAECoEVAAQYAAYInhAGWABOAQAYAAYInhAGWABOAQADAAUICA8nXAAKAQAEAAEIAQNwQwAlAAAAAA==.Shoxxy:BAABLAAECoEaAAIPAAcIoht+KgBDAgAPAAcIoht+KgBDAgAAAA==.Shuná:BAAALAAECgQICAAAAA==.Shynore:BAABLAAECoEgAAMSAAgIaB/eHADVAgASAAgIaB/eHADVAgAIAAIIzwfKUgBGAAAAAA==.Shùna:BAAALAADCgcIBwAAAA==.',Si='Sieglinde:BAAALAAECggICAAAAA==.Silan:BAAALAADCgcIBwABLAAECgYIEgAFAAAAAA==.Silenos:BAAALAADCggICAABLAAECgcIHAACAEEaAA==.',Sl='Slayerz:BAAALAADCggICQAAAA==.',Sn='Snâkee:BAABLAAECoEZAAIPAAYIAxnQTQCkAQAPAAYIAxnQTQCkAQAAAA==.',So='Solarus:BAAALAAECggIDwAAAA==.Solumon:BAAALAAECgYIBgAAAA==.Soulsmog:BAAALAAECgYICgAAAA==.',St='Studii:BAAALAAECgIIAwAAAA==.',Sw='Swítsch:BAAALAAECgYIBwAAAA==.',Sy='Syriale:BAABLAAECoEYAAINAAgINRp7HwBfAgANAAgINRp7HwBfAgAAAA==.',['Sê']='Sêraphia:BAAALAADCgcIBwAAAA==.',Ta='Taloná:BAAALAAECgYIDgAAAA==.Tameme:BAAALAAECgYICwAAAA==.Tankwärtin:BAAALAAECgEIAQABLAAECgMIBQAFAAAAAA==.Taolinn:BAABLAAECoEkAAIRAAcICx1zRgDiAQARAAcICx1zRgDiAQAAAA==.Tarinûs:BAAALAAECgYIBgAAAA==.Tark:BAACLAAFFIEFAAILAAII6hpwIQCsAAALAAII6hpwIQCsAAAsAAQKgTAAAgsACAiHJl4BAI4DAAsACAiHJl4BAI4DAAAA.Tarkan:BAAALAAECgIIAgAAAA==.',Th='Thalindriel:BAAALAAECgMIBQAAAA==.Therealdurin:BAAALAAECggICAAAAA==.Thesêus:BAAALAADCggICAAAAA==.',Ti='Timaja:BAAALAADCgcIFgAAAA==.Tinks:BAAALAADCgYIBgAAAA==.',To='Todian:BAAALAAECggIAQAAAA==.Toneh:BAABLAAECoEZAAILAAgIoRwCMACLAgALAAgIoRwCMACLAgAAAA==.Torgaddonn:BAABLAAECoEUAAMaAAgIdhuGDADwAQAaAAYIkhqGDADwAQAMAAYIaRANiQAkAQAAAA==.Torro:BAAALAAECggIEgAAAA==.Totemboi:BAACLAAFFIEJAAIRAAQIRhi9DwDlAAARAAQIRhi9DwDlAAAsAAQKgR4AAhEACAjtIWcLAPUCABEACAjtIWcLAPUCAAAA.Totemdwarf:BAAALAAFFAIIBAAAAA==.Toâdy:BAAALAADCggICAAAAA==.',Tr='Tragast:BAAALAADCggIIgAAAA==.Trixs:BAAALAAECgYIBgAAAA==.Trommler:BAACLAAFFIEGAAMZAAIIvSDFHgCqAAAZAAIIvSDFHgCqAAAgAAEIZgABMgATAAAsAAQKgTEAAhkACAiUIIcUAOkCABkACAiUIIcUAOkCAAAA.',Ts='Tsatoggua:BAAALAADCgcIDAAAAA==.',Tu='Turkeyhunter:BAAALAAECgYICgAAAA==.',Tw='Twîztêr:BAAALAAECgYIDgAAAA==.',Ty='Tyhra:BAAALAAECgYIEgAAAA==.Typeng:BAAALAAECgQIBAAAAA==.Tyune:BAABLAAECoEiAAIGAAgITxxLFQCtAgAGAAgITxxLFQCtAgAAAA==.',['Tò']='Tòasty:BAAALAAFFAIIBAAAAA==.',['Tó']='Tóady:BAACLAAFFIELAAIDAAQIhB7FCQD+AAADAAQIhB7FCQD+AAAsAAQKgS0AAgMACAi6JMUEAFADAAMACAi6JMUEAFADAAAA.',Un='Unholyfluff:BAAALAADCggICAABLAAFFAYIEgAMAO8fAA==.Unlight:BAACLAAFFIEJAAMJAAMIphB1GgDqAAAJAAMIphB1GgDqAAAhAAEIBgdMJQBJAAAsAAQKgSoABAkACAj3H8QaAMoCAAkACAgZH8QaAMoCACIABghwEm4OAK4BACEAAgheFhdsAI0AAAAA.Unrest:BAACLAAFFIEJAAIMAAMIlhH3EQDwAAAMAAMIlhH3EQDwAAAsAAQKgS0AAgwACAgmI+8LAC4DAAwACAgmI+8LAC4DAAAA.',Va='Vader:BAAALAAECgIIAgAAAA==.Vaestra:BAAALAADCggICAAAAA==.',Ve='Vexahlia:BAAALAADCgMIAwAAAA==.',Vi='Vi:BAAALAAECgMIAwAAAA==.',Vo='Voki:BAAALAAECgYICwABLAAECgYIFAAIAPEVAA==.',['Vù']='Vùlgrim:BAAALAADCggIFAAAAA==.',Wa='Walburgah:BAAALAAECgMIBQAAAA==.Waldschratt:BAABLAAECoEUAAIZAAYIwgy9tAAWAQAZAAYIwgy9tAAWAQAAAA==.Wawoker:BAAALAAECgYICgABLAAFFAMICQAIAJ8bAA==.Wawumbör:BAAALAAECgYIBgABLAAFFAMICQAIAJ8bAA==.',Wh='Whiskeyjoe:BAABLAAECoEfAAIMAAcIUhIiVAC9AQAMAAcIUhIiVAC9AQAAAA==.Whispy:BAABLAAECoEUAAIjAAcIgQptKAAqAQAjAAcIgQptKAAqAQAAAA==.',Wi='Wilmastreit:BAABLAAECoElAAIGAAgI6gkbQgCQAQAGAAgI6gkbQgCQAQAAAA==.',Wo='Wodkalilly:BAACLAAFFIEOAAILAAUIMxxCBADhAQALAAUIMxxCBADhAQAsAAQKgTAAAgsACAizJnQAAJ0DAAsACAizJnQAAJ0DAAAA.Wodkastacy:BAAALAADCggICAABLAAFFAUIDgALADMcAA==.Wookieknight:BAAALAAECgYIEwAAAA==.',Wu='Wumbillidan:BAACLAAFFIEJAAMIAAMInxsdAwD7AAAIAAMIZxgdAwD7AAASAAIIeBtbHgCvAAAsAAQKgS0AAxIACAiOJE0LADwDABIACAiOJE0LADwDAAgACAiUHtkHAMECAAAA.',Xa='Xaphian:BAABLAAECoEnAAILAAgI9x3AKACpAgALAAgI9x3AKACpAgAAAA==.Xardras:BAABLAAECoEVAAMPAAYIiBAKXgBtAQAPAAYIiBAKXgBtAQARAAUIZwl5xgC6AAAAAA==.',Xy='Xy:BAAALAAECgYIDwAAAA==.',Ya='Yavanna:BAAALAAECgYIEQAAAA==.',Yu='Yurach:BAAALAAECgUIDQAAAA==.',Ze='Zehnkv:BAABLAAECoEcAAIRAAcInxUJXgCfAQARAAcInxUJXgCfAQAAAA==.Zerai:BAAALAAECgMIAwAAAA==.Zerberon:BAABLAAECoEUAAIMAAgIBSUFBwBTAwAMAAgIBSUFBwBTAwABLAAFFAMICQAKAMkLAA==.Zerbini:BAACLAAFFIEJAAIKAAMIyQt7HgDaAAAKAAMIyQt7HgDaAAAsAAQKgS0AAgoACAizIiUSAAgDAAoACAizIiUSAAgDAAAA.Zercon:BAAALAAECggIEAAAAA==.Zerkí:BAAALAAECgMIAwAAAA==.Zermonk:BAAALAADCggICAAAAA==.Zest:BAAALAAECgYIBAAAAA==.',Zo='Zodarg:BAAALAADCggICwAAAA==.Zodiacus:BAAALAAECgEIAQAAAA==.Zol:BAAALAAECgYIDQAAAA==.Zoltanus:BAAALAAECgUIBQAAAA==.',Zw='Zwariso:BAAALAAECgIIBAAAAA==.Zwergolas:BAAALAADCgYICwAAAA==.',['Ák']='Ákara:BAAALAADCgYIBgABLAAFFAUIDgALADMcAA==.',['În']='Înstantbam:BAAALAADCggICAAAAA==.',['Ðe']='Ðemira:BAAALAADCggIHwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end