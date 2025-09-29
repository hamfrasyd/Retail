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
 local lookup = {'Evoker-Devastation','Unknown-Unknown','Priest-Holy','Hunter-BeastMastery','DeathKnight-Frost','Monk-Windwalker','Monk-Mistweaver','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Priest-Shadow','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Paladin-Retribution','Warrior-Fury','Warrior-Arms','Druid-Feral','Druid-Guardian','Shaman-Restoration','Mage-Arcane','Hunter-Marksmanship','DemonHunter-Vengeance',}; local provider = {region='EU',realm='DasSyndikat',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abraxi:BAACLAAFFIEFAAIBAAIIyA4PFACSAAABAAIIyA4PFACSAAAsAAQKgSQAAgEACAjfHroKAOUCAAEACAjfHroKAOUCAAAA.',Ad='Adochun:BAAALAAECgEIAQAAAA==.',Ag='Agwen:BAAALAADCggICQAAAA==.',Ah='Ahe:BAAALAAECgYIFQABLAAECgYIBgACAAAAAQ==.',Al='Alenyâ:BAAALAAECggIEwAAAA==.Allistair:BAABLAAECoEcAAIDAAgIHyACDgDkAgADAAgIHyACDgDkAgAAAA==.Alyndra:BAAALAAECgQICAAAAA==.',An='Anork:BAAALAAECgYIBgAAAA==.',Ar='Arcun:BAAALAADCggICQAAAA==.Arikna:BAACLAAFFIEQAAIEAAUIXSWPAgAYAgAEAAUIXSWPAgAYAgAsAAQKgTMAAgQACAiLJjsEAGADAAQACAiLJjsEAGADAAAA.',As='Asphyxovic:BAACLAAFFIEIAAIFAAII3hsTSgCPAAAFAAII3hsTSgCPAAAsAAQKgRUAAgUABwhuH8NQACgCAAUABwhuH8NQACgCAAAA.Asylaros:BAAALAADCgcIBwAAAA==.',At='Atalânte:BAAALAADCggIJQAAAA==.Atemi:BAAALAADCggIDgAAAA==.Athorus:BAAALAAECgEIAQAAAA==.Atremis:BAAALAADCgQIBAABLAAECgYIEAACAAAAAA==.',Az='Azgorath:BAAALAAECgYIBgAAAA==.Azumzy:BAABLAAECoEpAAMGAAgI7yV8AQBvAwAGAAgI7yV8AQBvAwAHAAIIGBdFPACJAAAAAA==.Azûmy:BAAALAAECgQICwABLAAECggIKQAGAO8lAA==.',Be='Belgrath:BAACLAAFFIEGAAIDAAIIMQzCJQCOAAADAAIIMQzCJQCOAAAsAAQKgSkAAgMACAgBFsMwAP0BAAMACAgBFsMwAP0BAAAA.',Bi='Biskit:BAAALAAECgIIAgAAAA==.',Bl='Bluffy:BAAALAADCggIEAAAAA==.Bly:BAAALAAECgYIBgAAAA==.',Bo='Bolsar:BAAALAAECgIIAgAAAA==.Bowser:BAAALAADCgMIAwAAAA==.',Br='Bremsar:BAECLAAFFIEQAAMIAAUIbhhlCwC7AQAIAAUIbhhlCwC7AQAJAAEIvw/JIQBPAAAsAAQKgTMABAgACAgvJbwFAFsDAAgACAgvJbwFAFsDAAoABAjbGBUYACgBAAkAAwicFG1fAMEAAAAA.Bremshades:BAEBLAAECoEaAAILAAcI9R1oHABxAgALAAcI9R1oHABxAgABLAAFFAUIEAAIAG4YAA==.Brewbarrymor:BAAALAADCggICAABLAAECggIHAADAB8gAA==.Brezzy:BAAALAADCgMIAwAAAA==.Bromadin:BAABLAAECoEhAAMMAAgI/waWEwCGAQAMAAgI9gaWEwCGAQANAAcIXwM9fQD6AAAAAA==.Brudèrtuk:BAACLAAFFIENAAMJAAMIgx95BgC+AAAIAAMIXR7tEgAvAQAJAAMICR55BgC+AAAsAAQKgS4AAwgACAijJekEAGMDAAgACAhJJekEAGMDAAkABwizI1kMAI4CAAAA.',Ca='Caroline:BAAALAADCgYIBgAAAA==.Catarama:BAAALAAECgIIAgAAAA==.Cathnai:BAAALAADCggIFAAAAA==.',Ce='Ceralia:BAAALAAECgEIAgAAAA==.Cetoh:BAABLAAECoEoAAIIAAgIZhLdVgC4AQAIAAgIZhLdVgC4AQAAAA==.',Ch='Charleen:BAABLAAECoEZAAMLAAcIDAsBSgBsAQALAAcIDAsBSgBsAQADAAUIHAhzfgDQAAAAAA==.',Da='Daylight:BAAALAAECgYIBgAAAA==.',De='Dedrya:BAAALAAECgMIBAAAAA==.Defeero:BAAALAADCggIGgAAAA==.Demoi:BAABLAAECoEhAAIIAAgI+x0lHADBAgAIAAgI+x0lHADBAgAAAA==.',Do='Dornentot:BAAALAAECggIBgAAAA==.Dorros:BAAALAADCggICAAAAA==.',Dr='Drombadir:BAAALAAECgUICAABLAAECgYIEAACAAAAAA==.Druschii:BAAALAAECgIIAgAAAA==.',Ds='Dschinä:BAAALAADCgMIAwAAAA==.',El='Elvira:BAAALAAECgYICwAAAA==.',Er='Erania:BAACLAAFFIERAAMFAAUI8RsdCQC5AQAFAAUI8RsdCQC5AQAOAAII2RBkDAB9AAAsAAQKgTMAAwUACAi1JckLADcDAAUACAiJJckLADcDAA4AAwiMJoIfAEsBAAAA.',Fa='Falkenklaue:BAAALAAECgUIBQAAAA==.',Fe='Felizitas:BAAALAAECggIEAAAAA==.Feydra:BAABLAAECoEYAAMPAAgIYwnKZwAeAQAPAAgIYwnKZwAeAQAQAAgIpwDjgQBdAAAAAA==.',Fi='Firion:BAAALAAECgYIDQAAAA==.',Fr='Fryryna:BAAALAADCgIIAgAAAA==.Frêeky:BAAALAAECgcIDgAAAA==.',Ga='Gabâ:BAAALAADCgIIAgAAAA==.Galaron:BAAALAADCgQIBAAAAA==.',Gi='Gildur:BAAALAADCggICgAAAA==.',Gw='Gwendolíne:BAAALAAECgYIDgAAAA==.',He='Herá:BAAALAAECgUIBQAAAA==.',Ho='Holymolyy:BAAALAADCggICAAAAA==.',Hy='Hybra:BAAALAAECgYIBgAAAA==.',Is='Isokrates:BAAALAAECgYIDQAAAA==.',Ka='Kajó:BAAALAAECgQIBQAAAA==.Kaltesh:BAAALAAECgYICwABLAAECgYIEAACAAAAAA==.Karlie:BAAALAAECgEIAQABLAAECggIKAAIAGYSAA==.Katala:BAAALAAECgUIBQAAAA==.',Ke='Kelrath:BAAALAADCgcIAwAAAA==.Kerida:BAAALAAECgYIBgAAAA==.Kessaïæ:BAABLAAECoEcAAIPAAgIwyEfCAAFAwAPAAgIwyEfCAAFAwAAAA==.',Kh='Khazanvil:BAAALAAECgYIDgAAAA==.Khelden:BAAALAADCggICAAAAA==.',Ki='Kirby:BAAALAADCggIDwAAAA==.',Kn='Knöpfchen:BAAALAADCgIIAgAAAA==.',Ko='Korthas:BAAALAAECggIDgAAAA==.Kowinho:BAAALAADCggIHgAAAA==.',Kr='Kragzavica:BAABLAAECoEaAAIPAAcIywuUXgA5AQAPAAcIywuUXgA5AQAAAA==.',La='Lamyra:BAAALAADCgUIBQAAAA==.',Le='Lexin:BAAALAADCgUIBQAAAA==.',Ma='Magantus:BAAALAADCggIJQAAAA==.Magharald:BAABLAAECoEYAAIGAAYIUhtnJwCTAQAGAAYIUhtnJwCTAQAAAA==.Majestic:BAAALAAECgQIBwAAAA==.',Mu='Murgh:BAABLAAECoEhAAIRAAgIShymLQCVAgARAAgIShymLQCVAgAAAA==.Murghi:BAAALAADCgEIAQABLAAECggIIQARAEocAA==.Murgo:BAAALAAECgYIDgABLAAECggIIQARAEocAA==.Murgoh:BAAALAADCgcIDgABLAAECggIIQARAEocAA==.',Na='Narsin:BAAALAADCgIIAgAAAA==.Nayra:BAAALAAECgYIEAAAAA==.',Ni='Niquesse:BAABLAAECoEcAAIDAAgIEQ0qRAChAQADAAgIEQ0qRAChAQAAAA==.Nirala:BAAALAADCggIEwAAAA==.',No='Notration:BAAALAADCggIOAAAAA==.',['Nì']='Nìro:BAABLAAECoEkAAMSAAgIpRpIKgBkAgASAAgISRpIKgBkAgATAAEImx5xLQBXAAAAAA==.',Ol='Olsun:BAAALAADCggICwAAAA==.',Or='Ornella:BAAALAAECgEIAQAAAA==.',Os='Oscuros:BAAALAAECgUIEQAAAA==.Oscurós:BAABLAAECoEZAAQIAAcImhWmUADNAQAIAAcIYBWmUADNAQAJAAMIvRMxZACvAAAKAAEIEwG0QQAgAAAAAA==.',Pa='Palima:BAACLAAFFIEGAAILAAIIvxj1EQCyAAALAAIIvxj1EQCyAAAsAAQKgSkAAgsACAjVHjQSAMoCAAsACAjVHjQSAMoCAAAA.Paragnur:BAAALAADCgIIAgAAAA==.',Ph='Phanpy:BAAALAADCgcIBwAAAA==.',Qa='Qain:BAAALAADCggICAAAAA==.',Qu='Quitzel:BAAALAAECgIIAgAAAA==.',Sa='Salene:BAACLAAFFIEGAAIQAAII9QU/GwB8AAAQAAII9QU/GwB8AAAsAAQKgTUAAxAACAgjFIcqAPIBABAACAgjFIcqAPIBAA8AAwh+F8GEAMwAAAAA.Saléné:BAAALAADCggIHgAAAA==.Sartarius:BAAALAADCggICAAAAA==.',Sc='Schneefoxy:BAABLAAECoEmAAILAAgIEhi/KAAZAgALAAgIEhi/KAAZAgAAAA==.Schnäuzel:BAAALAAECgMIBwAAAA==.Scratch:BAABLAAECoEnAAIUAAgIayCICACuAgAUAAgIayCICACuAgAAAA==.',Se='Seriade:BAAALAADCggIFQAAAA==.Serubi:BAABLAAECoEhAAIPAAgIng2BSQCDAQAPAAgIng2BSQCDAQAAAA==.Serubî:BAABLAAECoEUAAIPAAYI+ROQSwB7AQAPAAYI+ROQSwB7AQAAAA==.',Sh='Sharpay:BAACLAAFFIEKAAIPAAII7RQjHgCPAAAPAAII7RQjHgCPAAAsAAQKgR0AAg8ABgiPII81ANcBAA8ABgiPII81ANcBAAAA.Shaylana:BAAALAADCggICAAAAA==.',Si='Sinerias:BAAALAADCgUIBQAAAA==.Sinri:BAAALAADCgcIDAAAAA==.Siph:BAAALAAECggIBwAAAA==.',So='Sorbébé:BAAALAAECggIDQAAAA==.',Sp='Specter:BAAALAADCgYIBgAAAA==.',St='Stormflash:BAAALAADCgEIAQAAAA==.',Su='Sumalon:BAAALAADCggIDQAAAA==.',Sy='Sylvaa:BAAALAADCggIDQAAAA==.',['Sê']='Sêlia:BAAALAADCgcIBwAAAA==.',Ta='Tafia:BAAALAADCgIIAgAAAA==.Tahomi:BAAALAAECgEIAQABLAAECggIHAADAB8gAA==.Tajlukhan:BAAALAADCggIDAAAAA==.',Te='Temani:BAAALAADCgIIAgAAAA==.Terillina:BAAALAADCggICQAAAA==.',Th='Thaarkasha:BAAALAADCggICAABLAAECgcIEAACAAAAAA==.',To='Toki:BAAALAADCgQIBQAAAA==.',Tr='Trijhstul:BAAALAAECgIIAgAAAA==.',Ur='Uram:BAACLAAFFIETAAIVAAUIkxh1AAC1AQAVAAUIkxh1AAC1AQAsAAQKgTMAAhUACAjHI44BAEIDABUACAjHI44BAEIDAAAA.',Va='Varanis:BAAALAADCgYIBgABLAAECggIKwARADciAA==.',Vl='Vlausheri:BAACLAAFFIEGAAMNAAIIWhtwFwCrAAANAAIIWhtwFwCrAAAWAAEIDwoMUQA2AAAsAAQKgSgAAw0ACAjTIYsMABoDAA0ACAjTIYsMABoDABYAAQhOHRH8AFEAAAAA.',Vo='Voodoopriest:BAACLAAFFIENAAILAAUI3RhMBgCxAQALAAUI3RhMBgCxAQAsAAQKgR4AAgsACAicJEAMAAQDAAsACAicJEAMAAQDAAAA.Voodooqt:BAAALAAECgcIDQABLAAFFAUIDQALAN0YAA==.Voîxîa:BAAALAAECgcICQABLAAECggIKQAGAO8lAA==.',Wi='William:BAABLAAECoErAAIRAAgINyJ+FgAEAwARAAgINyJ+FgAEAwAAAA==.',Wo='Wolfpassing:BAAALAADCggIHwAAAA==.Wolm:BAAALAAECgUIBQABLAAECggIEwACAAAAAA==.',Wr='Wrok:BAABLAAECoEXAAIXAAcIVQ1HbgCbAQAXAAcIVQ1HbgCbAQAAAA==.',Wy='Wyrdai:BAAALAAECgcIDQAAAA==.',Xa='Xaviná:BAAALAADCgIIAgAAAA==.',Xz='Xzes:BAABLAAECoEgAAISAAgIfh/cFwDZAgASAAgIfh/cFwDZAgAAAA==.',Ye='Yeralâ:BAABLAAECoETAAIYAAYImySIGQCDAgAYAAYImySIGQCDAgABLAAFFAUIEQAFAPEbAA==.',Za='Zabani:BAAALAADCggICAAAAA==.Zafani:BAAALAAECgcIBwAAAA==.Zaptix:BAAALAAECgYIBgAAAA==.',Ze='Zerimas:BAABLAAECoEjAAIZAAgIHRH7HACeAQAZAAgIHRH7HACeAQAAAA==.',Zh='Zhertlesh:BAAALAADCgYIBgAAAA==.',Zu='Zulhannaar:BAAALAADCgUIAQAAAA==.',['Ôp']='Ôpa:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end