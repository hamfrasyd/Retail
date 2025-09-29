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
 local lookup = {'DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Retribution','Shaman-Elemental','Shaman-Enhancement','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Warlock-Affliction','Evoker-Devastation','Monk-Windwalker','Unknown-Unknown','Shaman-Restoration','Warrior-Protection','Mage-Arcane','Mage-Frost','Hunter-BeastMastery','Monk-Mistweaver','Priest-Shadow','Warrior-Fury','Rogue-Outlaw','Druid-Balance','Priest-Holy','Priest-Discipline','Paladin-Protection','Druid-Guardian','Warlock-Destruction','Evoker-Augmentation','Warlock-Demonology',}; local provider = {region='EU',realm='DieArguswacht',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adarna:BAAALAAECgMIBQAAAA==.',Ak='Akkumulator:BAAALAADCgEIAQAAAA==.',Al='Alienn:BAAALAAECgYIDAAAAA==.Alîscha:BAAALAAECgcIBwAAAA==.',An='Antheva:BAAALAAECgIIAgAAAA==.',Ar='Aradîna:BAAALAAECgIIAgAAAA==.Aragnas:BAAALAAECggIBwAAAA==.',At='Atharion:BAAALAADCggICAAAAA==.',Ax='Axarados:BAAALAADCggICAAAAA==.',Ba='Badhunt:BAAALAADCgcIBwAAAA==.Balagora:BAAALAADCggICAAAAA==.Barababo:BAACLAAFFIEPAAIBAAYIMQ/kBQD0AQABAAYIMQ/kBQD0AQAsAAQKgSgAAgEACAhQI4EQABwDAAEACAhQI4EQABwDAAAA.',Be='Beachyjiiva:BAAALAAECgUIBQAAAA==.Berte:BAAALAAECgMIBAAAAA==.Beverly:BAAALAAECgcIBwAAAA==.',Bi='Bif:BAAALAAECgMIBgAAAA==.',Bl='Bloodymary:BAABLAAECoEqAAMCAAgIciW+AQBQAwACAAgIQyW+AQBQAwADAAIInB3SQgFIAAAAAA==.',Bo='Bormia:BAABLAAECoEXAAIEAAgIIBesRgA9AgAEAAgIIBesRgA9AgAAAA==.',Br='Broxigara:BAAALAADCgcIBwAAAA==.Brunnea:BAAALAADCgEIAQAAAA==.',['Bü']='Büffelsteak:BAABLAAECoEdAAMFAAcIsiC3HACaAgAFAAcIsiC3HACaAgAGAAEIJwgZJAA8AAAAAA==.',Ca='Cargath:BAAALAAECgMIBwAAAA==.',Ch='Chillcollins:BAAALAAECgYIBgAAAA==.',Ci='Ciathie:BAAALAADCgcIBwABLAAECgcIHwACABYbAA==.',Da='Darkstar:BAAALAAECgMIBwAAAA==.',De='Dentarius:BAABLAAECoEXAAMHAAcIxR98GwAoAgAHAAYI0x98GwAoAgAIAAYICREEHwBuAQAAAA==.',Dh='Dhskull:BAABLAAECoEXAAIJAAcIOw0XKQA2AQAJAAcIOw0XKQA2AQAAAA==.',Di='Dietinge:BAABLAAECoEVAAIKAAYIDA/IEwBgAQAKAAYIDA/IEwBgAQAAAA==.Dioxes:BAABLAAECoEXAAILAAcI1g/hKwCgAQALAAcI1g/hKwCgAQAAAA==.',Do='Docstrange:BAAALAADCgcIBgAAAA==.',Dr='Draemog:BAABLAAECoEZAAIMAAcIwBdaHADwAQAMAAcIwBdaHADwAQAAAA==.Dridi:BAAALAAECgEIAQAAAA==.Drmedrasen:BAAALAADCgcIDAAAAA==.',Dy='Dysan:BAAALAAECgcIEgAAAA==.',El='Ellanora:BAAALAAECgIIAwAAAA==.Elypsa:BAAALAADCggICgAAAA==.',En='Enkayjey:BAAALAAECggICAAAAA==.',Fe='Feralá:BAAALAAECgcIEgAAAA==.',Fi='Fiery:BAAALAAECggIDwAAAA==.Fiffipi:BAAALAAECgMIAwABLAAECgYIBgANAAAAAA==.',Fl='Flaxta:BAAALAAECgYICQAAAA==.',Fr='Frin:BAAALAADCggICAAAAA==.',['Fî']='Fîffi:BAAALAAECgYIBgAAAA==.',Ga='Garronar:BAAALAAECgYIBwAAAA==.',Ge='Gewaltig:BAAALAAECgcICwABLAAECggIHwALANYcAA==.',Gl='Glut:BAAALAADCggICgAAAA==.',Go='Gokan:BAAALAAECgYIBgABLAAFFAMIDAAOAPsUAA==.Goldberg:BAABLAAECoEVAAIPAAgItAAIggAVAAAPAAgItAAIggAVAAAAAA==.',Gr='Grieverus:BAABLAAECoEYAAMQAAcIuA+EcwCNAQAQAAcI8guEcwCNAQARAAMIwhesXAC9AAAAAA==.Grotos:BAAALAADCggICAAAAA==.Gruamcarraig:BAAALAAECgIIAwAAAA==.Grünspan:BAAALAAECgMIBAAAAA==.',Ha='Hanta:BAABLAAECoEeAAISAAcIyw0VjwBgAQASAAcIyw0VjwBgAQAAAA==.',He='Helpmeheal:BAABLAAECoEvAAIOAAgI5CJYCwD2AgAOAAgI5CJYCwD2AgAAAA==.Hetti:BAAALAAECggIEgAAAA==.',Ho='Hollymôlly:BAAALAAECgYIBgABLAAFFAMIDAAOAPsUAA==.',['Hô']='Hôllymolly:BAAALAAECgUIBQABLAAFFAMIDAAOAPsUAA==.Hôllymôlly:BAAALAAECgQIBAABLAAFFAMIDAAOAPsUAA==.',In='Ingor:BAAALAAECggICAAAAA==.',Is='Isabela:BAAALAADCgcIBwAAAA==.Isilion:BAAALAADCggICAAAAA==.',Iz='Izze:BAAALAAECggIDAAAAA==.',Ja='Jade:BAABLAAECoEeAAITAAcIzhVSGADPAQATAAcIzhVSGADPAQAAAA==.Jashadda:BAAALAADCggICAAAAA==.',Je='Jetleeh:BAABLAAECoEgAAIMAAgI0iB+CQDiAgAMAAgI0iB+CQDiAgAAAA==.',Jh='Jhoda:BAAALAAECgQIBgAAAA==.',Ji='Jirakaya:BAABLAAECoEXAAIUAAcIwBhWKgAPAgAUAAcIwBhWKgAPAgAAAA==.',Ju='Jujinxx:BAAALAADCgUIBQAAAA==.',['Jâ']='Jânedôe:BAAALAAECgUIBQAAAA==.',Ka='Kamelin:BAAALAADCgQIBAAAAA==.',Ke='Kenobi:BAAALAADCgQIBAAAAA==.',Kn='Knuffel:BAAALAAECgEIAQABLAAECgYIFgADALYFAA==.',Ko='Konan:BAAALAAECggIEAAAAA==.Konos:BAAALAAECgYIDAAAAA==.',Ky='Kyr:BAACLAAFFIEMAAIVAAUIFxS3BwDBAQAVAAUIFxS3BwDBAQAsAAQKgSIAAhUACAhdI/ULAC4DABUACAhdI/ULAC4DAAAA.',La='Lakota:BAAALAAECgMIBwAAAA==.',Le='Lechi:BAAALAAECgYIDgAAAA==.Letheköle:BAABLAAECoEUAAIWAAcIzxW0CADhAQAWAAcIzxW0CADhAQAAAA==.Leyno:BAAALAADCgEIAQAAAA==.',Li='Lisyrah:BAAALAAECgYIEAAAAA==.',Lo='Lockunrage:BAAALAAECgMIBAABLAAECggIIQACAFsiAA==.Lorallenn:BAAALAAECggIEwAAAA==.Lorien:BAAALAADCgcIBgAAAA==.',Lu='Lunelia:BAAALAAECgQIBAAAAA==.Luperix:BAABLAAECoEXAAIXAAYIZxiEOwCZAQAXAAYIZxiEOwCZAQAAAA==.Luura:BAAALAADCggICAABLAAECggIEAANAAAAAA==.',Ly='Lydamer:BAABLAAECoEgAAMYAAgI6hRgMAD/AQAYAAgI6hRgMAD/AQAZAAMIUQRtKABnAAAAAA==.Lynerah:BAAALAAECgYIDwAAAA==.',['Lé']='Léss:BAAALAADCggIEAAAAA==.',['Lí']='Lío:BAAALAAECgUIDAAAAA==.',['Lö']='Löffelics:BAAALAADCggICAABLAAECgYIDgANAAAAAA==.',Ma='Magicpreach:BAAALAADCggIDgAAAA==.Matteospyro:BAAALAAECggIBgABLAAECggIFwAQACQmAA==.',Me='Mefii:BAAALAADCggIDQAAAA==.Melindrah:BAABLAAECoErAAIYAAcIXRnFNgDeAQAYAAcIXRnFNgDeAQAAAA==.Mewtoo:BAAALAAECgMIAwAAAA==.',Mi='Misfire:BAAALAADCgQIBAAAAA==.Mittylock:BAAALAADCggICAABLAAECgcIHgAaANEbAA==.Mittypal:BAABLAAECoEeAAIaAAcI0RvgFAAkAgAaAAcI0RvgFAAkAgAAAA==.',Mo='Molyre:BAAALAADCgUICQAAAA==.Morugg:BAAALAADCgUIBQAAAA==.Moxer:BAAALAAECggIEAAAAA==.Mozambi:BAAALAAECgYICAAAAA==.Mozo:BAAALAAECggICAAAAA==.',My='Myridon:BAAALAAECgYIEgAAAA==.Myriel:BAAALAAECggICAAAAA==.',['Mà']='Màskulin:BAAALAAECgYIBgAAAA==.',Na='Nadekoi:BAAALAAECggIDwAAAA==.Naiana:BAAALAADCgEIAQAAAA==.Namielle:BAAALAAECgYIDAAAAA==.Natros:BAAALAAECgcIEQAAAA==.',Ne='Necrón:BAAALAAECgMIBQAAAA==.Ned:BAAALAAECggIEAAAAA==.Nefertim:BAAALAAECgMIBAAAAA==.',Ni='Nimes:BAABLAAECoEVAAIbAAcIwBRJDwCnAQAbAAcIwBRJDwCnAQAAAA==.Niqu:BAAALAAECgMIAwAAAA==.',No='Noire:BAAALAADCgcIBwAAAA==.',Nu='Nukkii:BAAALAAECggICAAAAA==.',Ny='Nymphadora:BAAALAAECgMIBAAAAA==.',['Nî']='Nîcole:BAAALAAECgcIBwAAAA==.',Pa='Palabüchse:BAAALAAECgMIBAAAAA==.',Pi='Pitsch:BAAALAADCgQIBQAAAA==.',Pr='Prisla:BAAALAAECggIEAAAAA==.',Re='Redul:BAAALAAECgYIBgAAAA==.',Sa='Sankro:BAAALAAECgYICgAAAA==.Sankroo:BAAALAADCggIFgABLAAECgYICgANAAAAAA==.',Sc='Schnelly:BAAALAADCgIIAgABLAAFFAMIDAAOAPsUAA==.Schomodormu:BAABLAAECoEfAAILAAgI1hxiDwCsAgALAAgI1hxiDwCsAgAAAA==.',Sh='Shaiya:BAABLAAECoEXAAIPAAcICg9NOQBdAQAPAAcICg9NOQBdAQAAAA==.Shironda:BAAALAAECgIIAgAAAA==.Shirone:BAABLAAECoEYAAIcAAYIzwgajQAkAQAcAAYIzwgajQAkAQAAAA==.Shugh:BAAALAAECggICgAAAA==.Shunaka:BAAALAAECgcIEQAAAA==.Shînola:BAAALAADCggIEQAAAA==.',Si='Sinayda:BAAALAADCggIKwAAAA==.Sinchi:BAAALAADCggICAAAAA==.Sixus:BAAALAAECgQIBgAAAA==.',Sk='Skadrö:BAAALAAECgIIAwAAAA==.Skiadrum:BAAALAADCgcIBwABLAAECggIIAAdANIWAA==.',So='Sodeta:BAAALAAECgIIAgAAAA==.Sorayaá:BAAALAADCggIEAAAAA==.',St='Stahlhuf:BAABLAAECoEfAAIEAAgIYBxkKACqAgAEAAgIYBxkKACqAgAAAA==.Sthórmy:BAAALAADCggIFQAAAA==.Stoli:BAAALAAECgYIBgABLAAFFAMIDAAOAPsUAA==.',Ta='Tailtinn:BAABLAAECoEUAAICAAcIwBd9FgD1AQACAAcIwBd9FgD1AQAAAA==.Tamori:BAAALAAECgMIAwABLAAECggIEAANAAAAAA==.Tankdeckel:BAAALAAECgUIBAAAAA==.Tayaninian:BAAALAAECgMIAwAAAA==.',Te='Telperion:BAAALAAECgMIBwAAAA==.Tempra:BAAALAAECgYIDgAAAA==.',Th='Thaena:BAAALAAECgIIAgAAAA==.Thebrain:BAAALAAECgQIBAAAAA==.Thorgrim:BAAALAAECggICAAAAA==.',Ti='Tinyhealz:BAAALAAECggICAAAAA==.',To='Torya:BAAALAADCggICgAAAA==.Toryv:BAAALAADCggIHwAAAA==.Toryy:BAAALAAECgIIAgAAAA==.Tossadar:BAABLAAECoEpAAISAAcIIyLFLQBlAgASAAcIIyLFLQBlAgAAAA==.Tossadur:BAAALAAECgUIBQAAAA==.Tossalock:BAAALAADCggICQABLAAECgcIKQASACMiAA==.Totekuh:BAAALAADCggICAAAAA==.',Tr='Trys:BAAALAAECgYIEAAAAA==.',Tu='Tuborg:BAAALAAECggIDQAAAA==.',['Tâ']='Tâpion:BAABLAAECoEYAAIPAAcI4g9vNwBoAQAPAAcI4g9vNwBoAQAAAA==.Tâwa:BAAALAAECgQIBgAAAA==.',Up='Upfackovic:BAAALAAECgYIEQAAAA==.',Va='Vahalla:BAAALAAECggICAAAAA==.',Ve='Ventli:BAABLAAECoEXAAMcAAcIPRwLMwBDAgAcAAcIPRwLMwBDAgAeAAEIpATcjQAnAAAAAA==.',Vi='Violancer:BAAALAAECgUIBQAAAA==.',Vo='Vorlon:BAAALAADCgQIBAAAAA==.',Vq='Vqueeni:BAAALAADCggICAAAAA==.',We='Werhaingwen:BAAALAADCgQIBAAAAA==.',Wu='Wuff:BAACLAAFFIEQAAIFAAUI2R6zBQDhAQAFAAUI2R6zBQDhAQAsAAQKgSsAAgUACAgTJmkEAGYDAAUACAgTJmkEAGYDAAAA.',['Wä']='Wähdritsch:BAAALAADCggICAAAAA==.Wäädritsch:BAAALAAECggIBQAAAA==.',Xe='Xenomorph:BAABLAAECoEgAAMdAAgI0hacBwDdAQALAAgI1BN9HgAMAgAdAAcI+xWcBwDdAQAAAA==.',Xi='Xiu:BAABLAAFFIELAAITAAMIeRUxBwDyAAATAAMIeRUxBwDyAAABLAAFFAUIEAAFANkeAA==.Xiuhtecutli:BAAALAAECgEIAQAAAA==.',Ya='Yanir:BAAALAAECgEIAQAAAA==.',Ye='Yeshe:BAABLAAECoEiAAITAAgI0RnSDwBFAgATAAgI0RnSDwBFAgAAAA==.',Za='Zapfanlage:BAACLAAFFIEFAAIMAAIIfh+9CQCrAAAMAAIIfh+9CQCrAAAsAAQKgSQAAgwACAgRID0JAOYCAAwACAgRID0JAOYCAAAA.',Ze='Zerstoerer:BAAALAAECgcIEgAAAA==.',Zh='Zhuzudergwen:BAAALAAECgUIBwAAAA==.',Zy='Zydônia:BAAALAAECgYIBgAAAA==.',['Zé']='Zédrik:BAABLAAECoEYAAISAAcIPBLicgCZAQASAAcIPBLicgCZAQAAAA==.',['Àn']='Ànuro:BAAALAAECgYIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end