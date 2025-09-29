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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Unholy','Warrior-Fury','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Hunter-Marksmanship','Druid-Guardian','Rogue-Outlaw','Druid-Feral','Priest-Holy','Mage-Frost','Paladin-Retribution','DeathKnight-Frost','Warlock-Destruction','Hunter-Survival','Paladin-Protection','Hunter-BeastMastery','Shaman-Elemental','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','DeathKnight-Blood','Shaman-Restoration','Mage-Arcane','Evoker-Devastation','Monk-Mistweaver','Shaman-Enhancement','Monk-Windwalker',}; local provider = {region='EU',realm='Bloodhoof',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aapipiron:BAAALAADCggIDgAAAA==.',Ad='Addriana:BAAALAAECgIIAgABLAAECgIIAgABAAAAAA==.',Ae='Aeagris:BAAALAADCggICAAAAA==.Aevelaine:BAAALAAECgYIDgAAAA==.',Ag='Agnés:BAAALAADCgIIAgAAAA==.',Ah='Ahad:BAACLAAFFIEFAAICAAII+hSrIQChAAACAAII+hSrIQChAAAsAAQKgRkAAwIACAh6IG4jAKwCAAIACAh6IG4jAKwCAAMAAQiPG1hSAD8AAAAA.Ahadbear:BAAALAADCgIIAgABLAAFFAIIBQACAPoUAA==.Ahadfotm:BAAALAAECgcICwABLAAFFAIIBQACAPoUAA==.Ahadsham:BAAALAAECgYIDgABLAAFFAIIBQACAPoUAA==.Ahadwar:BAABLAAECoEfAAIEAAcIViN1DAC7AgAEAAcIViN1DAC7AgABLAAFFAIIBQACAPoUAA==.',Ai='Aineas:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.',Ak='Akazy:BAAALAAECgMIAwAAAA==.',Al='Allicia:BAAALAADCgIIAgAAAA==.Alrexx:BAAALAADCgcIEAAAAA==.Alunara:BAAALAAECgMIBQAAAA==.Alvura:BAAALAADCgcIDwAAAA==.',An='Angstyflaps:BAAALAAECgYIBgAAAA==.Annushka:BAAALAAECgcIDQAAAA==.Anqet:BAAALAAECgEIAQAAAA==.Anzhu:BAABLAAECoEbAAIFAAgIshx2CAC5AgAFAAgIshx2CAC5AgAAAA==.',Ap='Apocz:BAAALAADCgcIBwAAAA==.Appelboom:BAAALAADCgMIAwABLAADCgcIBwABAAAAAA==.',Ar='Aratir:BAAALAAECgIIAgABLAAECggIDgABAAAAAA==.Argorn:BAAALAADCgUICQAAAA==.Arwin:BAAALAAECggICQAAAA==.Arwinn:BAABLAAECoEgAAIGAAgISAGzygAzAAAGAAgISAGzygAzAAAAAA==.Arwinx:BAAALAAECggIDAAAAA==.',At='Ateer:BAAALAAECgIIAwAAAA==.Atom:BAABLAAECoElAAIHAAgIqx8YCQC/AgAHAAgIqx8YCQC/AgAAAA==.Attikus:BAAALAAECgYICQAAAA==.',Au='Audigy:BAAALAAECgQICQAAAA==.',Az='Azin:BAAALAADCgEIAQAAAA==.',Ba='Backjauer:BAABLAAECoEdAAMIAAgILg/rGgACAgAIAAgILg/rGgACAgAJAAYIPgwvFABaAQAAAA==.Bari:BAAALAADCggIEAABLAAECggICAABAAAAAA==.',Be='Beerbaron:BAAALAAECggIBwAAAA==.Belaris:BAAALAAECgEIAQAAAA==.Benjamano:BAAALAAECgMIBAAAAA==.',Bi='Bigbossy:BAABLAAECoEhAAIKAAgIIhvPGABqAgAKAAgIIhvPGABqAgAAAA==.Biggingerrob:BAAALAAECgYIBgAAAA==.Bigtasty:BAAALAADCgMIAwAAAA==.Binouze:BAAALAAECgQIBAAAAA==.Bisomnio:BAAALAAECgYICgAAAA==.',Bl='Blindmoo:BAAALAAECgEIAQAAAA==.Blurinho:BAABLAAECoEfAAILAAgIZh6lEgC5AgALAAgIZh6lEgC5AgAAAA==.',Bo='Bobandy:BAABLAAECoEbAAIMAAgIXSRgAQBIAwAMAAgIXSRgAQBIAwAAAA==.Bonez:BAABLAAECoEaAAINAAgIcxQ7BgAoAgANAAgIcxQ7BgAoAgAAAA==.Borcan:BAAALAAECgYIDQAAAA==.Borr:BAAALAADCggICAABLAAECggICAABAAAAAA==.Boruvka:BAAALAAECgQICQAAAA==.Bosshogg:BAAALAAECggIEgAAAA==.Bouchard:BAAALAAECgUICAAAAA==.',Br='Braney:BAAALAAECgYIDgAAAA==.Brightest:BAAALAAECgMIAwAAAA==.Brilhasti:BAAALAADCgQIBAAAAA==.Broceliande:BAAALAAECgQIBAAAAA==.Brom:BAAALAAECgQIBQAAAA==.Bryson:BAAALAAECgQIBwAAAA==.',Bu='Burin:BAAALAAECggICAAAAA==.Bushmaster:BAAALAAECggIEAABLAAFFAEIAQABAAAAAA==.',By='Bynky:BAABLAAECoEdAAIOAAcI+hgOEQATAgAOAAcI+hgOEQATAgAAAA==.',['Bå']='Bågberit:BAAALAADCgEIAQAAAA==.',Ca='Calyx:BAAALAADCgcIHQAAAA==.Calándra:BAABLAAECoEhAAIPAAgIJBz7FACjAgAPAAgIJBz7FACjAgAAAA==.Capaletti:BAAALAAECgIIBAAAAA==.',Ce='Celedar:BAAALAAECgQIBQAAAA==.Cesr:BAAALAADCggIEAAAAA==.',Ch='Chilliam:BAAALAADCgEIAQAAAA==.Chiminglee:BAAALAADCggIDgAAAA==.Choppara:BAAALAAECgcICQAAAA==.Chrchlik:BAAALAADCggIIQAAAA==.',Ci='Cij:BAAALAADCggIGwAAAA==.Cil:BAAALAADCgcIDAAAAA==.',Co='Coldkilla:BAAALAADCgcIFAAAAA==.',Cr='Crank:BAAALAADCggICAAAAA==.Cras:BAAALAAECgQIBAAAAA==.Crittmarie:BAAALAADCgEIAQAAAA==.Crypthshade:BAAALAADCgMIAwAAAA==.Cróuch:BAAALAADCgcIBwAAAA==.',Cy='Cyberpriest:BAAALAADCgYIBgAAAA==.',['Cí']='Cítywok:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.',Da='Dalieta:BAAALAADCggICAAAAA==.Dalton:BAABLAAECoEVAAIQAAcINgZ5RQAsAQAQAAcINgZ5RQAsAQAAAA==.Danaval:BAABLAAECoEUAAIDAAYIBBQ3JgBBAQADAAYIBBQ3JgBBAQAAAA==.Darcevoker:BAAALAAECgQIBgABLAAECggIKAARAJ4eAA==.Darkelftank:BAAALAAECgQIBwAAAA==.Darkheals:BAAALAAECgUICAAAAA==.Darkironhunt:BAAALAADCggICAAAAA==.Darksoulz:BAAALAADCgYIBgAAAA==.Darryxx:BAAALAAECgUIBQAAAA==.',De='Dekra:BAAALAADCggIDwAAAA==.Delanos:BAAALAADCgEIAQABLAAECgQICgABAAAAAA==.Demetra:BAAALAAECgQIBAAAAA==.Demonetize:BAAALAAECgYICwABLAAECggIFwASAOISAA==.Demonieino:BAAALAADCgcICAABLAADCggICAABAAAAAA==.Denim:BAABLAAECoEWAAICAAcIlBQoYADVAQACAAcIlBQoYADVAQAAAA==.Denovox:BAAALAAECggIDgAAAA==.Dezie:BAAALAAECgIIAgAAAA==.',Di='Digestibull:BAAALAADCggICAAAAA==.Direnews:BAAALAAECgIIAgAAAA==.',Dj='Djerunish:BAAALAAECgMIBgAAAA==.',Dm='Dmaar:BAAALAAECgYIDQAAAA==.',Do='Dogthe:BAAALAADCggIFwABLAAECgcIJQATANoIAA==.Domagoj:BAABLAAECoEhAAIRAAgIkyECFgADAwARAAgIkyECFgADAwAAAA==.Donalddrumpf:BAAALAADCggICAABLAAECggIFAAUAIscAA==.Dontroll:BAAALAAECgEIAgAAAA==.Doshkaa:BAAALAADCgcIBwAAAA==.',Dr='Draccarys:BAAALAAECggIEAAAAA==.Drbuzzard:BAAALAAECgMICQAAAA==.Droddy:BAAALAADCggICAAAAA==.Drushift:BAAALAADCgQIAwAAAA==.',['Dá']='Dárc:BAABLAAECoEoAAQRAAgInh6QKACkAgARAAgInh6QKACkAgAHAAQI5A2PTQDHAAAVAAEIEA4vXQAtAAAAAA==.Dárcdruid:BAAALAAECgcIDgABLAAECggIKAARAJ4eAA==.Dárin:BAAALAADCgcIBwAAAA==.',['Dé']='Déstróyer:BAAALAAECgMIBwAAAA==.',['Dë']='Dëmonica:BAAALAAECgYIBgAAAA==.',Ed='Edneiy:BAAALAAECgQIBAAAAA==.',El='Elfidor:BAAALAAECgIIAgAAAA==.Elindra:BAAALAAECgMIAwABLAAECgcIDwABAAAAAA==.Ellanic:BAAALAADCgcIBwAAAA==.Elwe:BAAALAADCgcICgAAAA==.Elyssra:BAAALAAECgMIAwAAAA==.',Em='Emì:BAAALAAECgQICAABLAAECggIIQAKACIbAA==.',En='Enchant:BAAALAAECgYIAQAAAA==.Enrage:BAAALAAECgYIBwAAAA==.',Ep='Epivitorina:BAABLAAECoEZAAILAAcIPRisLQD0AQALAAcIPRisLQD0AQAAAA==.',Et='Etcid:BAABLAAECoEVAAIKAAcICw7vQgBtAQAKAAcICw7vQgBtAQAAAA==.Ethaslayer:BAAALAAECgYIDAAAAA==.',Ev='Evasor:BAAALAAECgMIBAAAAA==.Evoh:BAAALAADCgcIBwAAAA==.',Fa='Falicia:BAAALAADCgYIBgAAAA==.',Fe='Fensi:BAAALAAECgQICQAAAA==.',Fi='Fingerz:BAAALAAECgEIAgABLAAECgQIBQABAAAAAA==.',Fl='Flaga:BAAALAADCggIEAAAAA==.Florensa:BAAALAAECgIIAgAAAA==.',Fr='Frank:BAABLAAECoEfAAISAAgIFx84JQC1AgASAAgIFx84JQC1AgAAAA==.Freefellatio:BAABLAAECoEVAAISAAgIfQs3kgCZAQASAAgIfQs3kgCZAQAAAA==.Frisbeez:BAABLAAECoEZAAIWAAYInQ/AkQBNAQAWAAYInQ/AkQBNAQAAAA==.Friskstraza:BAAALAAECgYICAAAAA==.Frostgump:BAAALAAECgIIAgAAAA==.Frozenedge:BAAALAADCggICQAAAA==.',Fu='Fuder:BAAALAAECgMIAwAAAA==.Funder:BAAALAAECgEIAQAAAA==.Furydemon:BAAALAADCgYIBgAAAA==.',Ga='Gabbriel:BAAALAAECgMIAwAAAA==.Gabriell:BAABLAAECoEZAAIRAAgIDRz+LACRAgARAAgIDRz+LACRAgAAAA==.',Ge='Ge:BAAALAAECgYIEgABLAAFFAMICQALAAcdAA==.',Gi='Gihn:BAAALAAECgYIBgAAAA==.Ging:BAABLAAECoEdAAIKAAcIyR12HQBCAgAKAAcIyR12HQBCAgAAAA==.Gix:BAAALAADCgcIBwAAAA==.',Gl='Gloriez:BAAALAADCgQIBAAAAA==.',Gn='Gnomo:BAAALAADCgYIDAAAAA==.',Go='Goarsh:BAABLAAECoEkAAQJAAgIWA+QCgDyAQAJAAgIrQyQCgDyAQATAAYIVQ5edQBZAQAIAAQIggGfcQBxAAAAAA==.Goldiefuzz:BAABLAAECoEcAAITAAcIUwjYdQBXAQATAAcIUwjYdQBXAQAAAA==.Gordana:BAAALAAECgcIBwABLAAECggICAABAAAAAA==.Gorgots:BAABLAAECoEWAAIXAAgIaxyGGwCcAgAXAAgIaxyGGwCcAgAAAA==.',Gr='Greetmyfeet:BAAALAAECgIIAgAAAA==.Grimshank:BAAALAADCgIIAgAAAA==.Grimwall:BAAALAAECgQIBAAAAA==.Groawn:BAAALAAECgYICQABLAAECggIFQAXAAwXAA==.Grynhild:BAAALAAECgMIAwABLAAECgcIKwAYAGIdAA==.',Gu='Gullibull:BAABLAAECoEUAAQUAAgIixzEAwChAgAUAAgIwhvEAwChAgAWAAMIyR9urAAVAQALAAII8RNllQBkAAAAAA==.Gurkeren:BAAALAAECgMIBwABLAAECggIHwACABMiAA==.',['Gá']='Gárok:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.',He='Heda:BAABLAAECoEfAAMKAAgItgwvPACNAQAKAAgItgwvPACNAQAZAAEIcgV3vAAhAAAAAA==.Heihach:BAAALAAECgYICAABLAAECggIFQAaAH8YAA==.Hellscyte:BAABLAAECoEUAAISAAYIERVvkgCYAQASAAYIERVvkgCYAQAAAA==.Hellthrass:BAAALAADCgYIBgAAAA==.Herbaliser:BAAALAAECggICwAAAA==.',Hi='Hiccupotomas:BAAALAAECgIIAgABLAAECggIFAAUAIscAA==.Hiccupotomoo:BAAALAADCggICAABLAAECggIFAAUAIscAA==.Hiccupotomos:BAAALAAECggIAgABLAAECggIFAAUAIscAA==.Hiccupotomus:BAAALAAECggIDAABLAAECggIFAAUAIscAA==.',Ho='Holyfans:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Holyhaste:BAAALAADCgYIBgABLAAECgcIHAAbADUgAA==.Horible:BAABLAAECoEfAAMPAAgIixxTFACoAgAPAAgIixxTFACoAgAcAAEIsxbNLgA+AAAAAA==.',Hv='Hvítálfar:BAAALAADCgcIBwAAAA==.',Hy='Hyorel:BAAALAAECgMIAwAAAA==.Hyrqath:BAAALAADCgcIBwAAAA==.',['Hó']='Hóoxy:BAAALAAECgIIAgAAAA==.',Il='Ilcka:BAAALAADCggIJgAAAA==.Ilkdrakkar:BAAALAADCgIIAgAAAA==.',In='Infestados:BAABLAAECoEfAAIdAAgIyRHEFADHAQAdAAgIyRHEFADHAQAAAA==.',Is='Isabelleke:BAAALAAECgMIAwAAAA==.',It='Itismik:BAACLAAFFIEFAAMLAAIIWB7sEgCrAAALAAIIcB3sEgCrAAAWAAIIIRUMJQCRAAAsAAQKgR8AAwsACAiLIT0OAOICAAsACAgHIT0OAOICABYABgixHyxHAP4BAAAA.',Ja='Jahbinks:BAACLAAFFIEFAAIXAAII+R+JFAC2AAAXAAII+R+JFAC2AAAsAAQKgSAAAhcACAgLIJoPAPwCABcACAgLIJoPAPwCAAAA.Jawj:BAABLAAECoEfAAIeAAgIOA9lYgCKAQAeAAgIOA9lYgCKAQAAAA==.Jaxxz:BAABLAAECoEYAAMeAAcIFRZ1TQDEAQAeAAcIFRZ1TQDEAQAXAAYI5wTXeAD7AAAAAA==.',Je='Jellik:BAAALAAECgQIBgAAAA==.',Jo='Johnno:BAAALAAECgYIEwAAAA==.Josin:BAABLAAECoEbAAIMAAgIuhcoCgAEAgAMAAgIuhcoCgAEAgAAAA==.',Jr='Jró:BAAALAAECgcICQAAAA==.',Ju='Juiralen:BAAALAAECgIIAgABLAAECgcIDwABAAAAAA==.Junbo:BAACLAAFFIEFAAIfAAIIrR63IQC5AAAfAAIIrR63IQC5AAAsAAQKgSIAAh8ACAgjJGYNACEDAB8ACAgjJGYNACEDAAAA.Juntabara:BAAALAADCgcIBwAAAA==.',['Jö']='Jörmúngandr:BAAALAAECggICAABLAAECggIDQABAAAAAA==.',Ka='Kaeabaen:BAAALAAECgYIBwAAAA==.Karon:BAABLAAECoEhAAIGAAgI5QkdXgCTAQAGAAgI5QkdXgCTAQAAAA==.Katykat:BAAALAAECgMIAwAAAA==.',Ke='Keata:BAAALAAECgQICgAAAA==.Keddien:BAAALAAECgMIAwAAAA==.Kera:BAAALAAECgIIAgAAAA==.',Kh='Khadalia:BAAALAAECggIEwAAAA==.Khazadom:BAABLAAECoEfAAIRAAcIGBL/fQC2AQARAAcIGBL/fQC2AQAAAA==.',Ki='Killerbeat:BAAALAADCgIIAgAAAA==.Kitune:BAAALAADCgYICAAAAA==.',Kk='Kkenneth:BAAALAADCgMIAwAAAA==.',Kl='Kleopatra:BAAALAADCggIGwABLAAECgIIAgABAAAAAA==.',Kn='Knetter:BAAALAADCggICQAAAA==.',Ko='Korïna:BAABLAAECoEUAAISAAYIJCBXVgAUAgASAAYIJCBXVgAUAgAAAA==.',Ku='Kuzadrion:BAABLAAECoEgAAIgAAcIFB3hGAA8AgAgAAcIFB3hGAA8AgAAAA==.',Ky='Kyanu:BAAALAADCggICAABLAAECggIHQAfALMeAA==.Kylossus:BAAALAADCgcIBwAAAA==.',La='Laesis:BAAALAADCgUIBQAAAA==.Lanks:BAAALAADCggIFQAAAA==.Lavoe:BAABLAAECoEfAAIPAAgI6iPQBAA/AwAPAAgI6iPQBAA/AwAAAA==.Layria:BAAALAAECgQIBAAAAA==.',Le='Leatherkjax:BAAALAAECgYIDwAAAA==.Lebrann:BAAALAAECgYIBgABLAAFFAIIBQACAPoUAA==.Lecramm:BAABLAAECoEeAAIRAAgIEyR6CQBNAwARAAgIEyR6CQBNAwAAAA==.Legendhero:BAAALAAECgQIBgAAAA==.Legendheroic:BAAALAAECgIIAgAAAA==.Legendmonk:BAAALAADCggIFwAAAA==.Legendshade:BAAALAADCgcIBwAAAA==.Legendslash:BAAALAADCggIDQAAAA==.Leviath:BAAALAAECgMIBgAAAA==.',Li='Liaserock:BAAALAAECgIIAgAAAA==.Lightswrath:BAAALAADCgUIBQAAAA==.Lilianna:BAABLAAECoEVAAICAAcI5xUuZwDEAQACAAcI5xUuZwDEAQAAAA==.Lillemor:BAAALAAECgQICgAAAA==.Livranca:BAAALAADCgMIAwAAAA==.Lize:BAAALAAECggICAAAAA==.',Lu='Luk:BAAALAADCgcIAwAAAA==.Luxerry:BAABLAAECoEXAAMQAAgIXBBQMwB+AQAQAAYImxNQMwB+AQAfAAYIxgakmgATAQAAAA==.',Ly='Lylïana:BAAALAADCggICAAAAA==.',['Lá']='Lágertha:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.',Ma='Madlounw:BAAALAAECgQIBwAAAA==.Maladi:BAABLAAECoErAAMYAAcIYh2wIQBCAgAYAAcIYh2wIQBCAgAPAAEICBCSoAAxAAAAAA==.Malkus:BAABLAAECoEXAAITAAYIrwc0iwAeAQATAAYIrwc0iwAeAQAAAA==.Malmi:BAAALAAECgcIDQAAAA==.Mamboo:BAACLAAFFIEFAAILAAIINhq0FAChAAALAAIINhq0FAChAAAsAAQKgScAAgsACAjDIeALAPcCAAsACAjDIeALAPcCAAAA.Mattex:BAAALAAECgUIBQAAAA==.Maximusmax:BAAALAAECgIIAwAAAA==.Mazradon:BAAALAADCggIDQAAAA==.',Me='Megnito:BAAALAAECgMIAwAAAA==.Melbo:BAAALAAECgYICQAAAA==.Melindya:BAABLAAECoEkAAIQAAgIvRqSEgBlAgAQAAgIvRqSEgBlAgAAAA==.Metamarv:BAAALAAECgQIBwAAAA==.Mevrouw:BAAALAADCgcIBwAAAA==.',Mi='Miirinato:BAAALAAECggICAAAAA==.Mikkiim:BAAALAAECgEIAQABLAAFFAIIBQALAFgeAA==.Misbah:BAABLAAECoEeAAILAAgIDh4BFQClAgALAAgIDh4BFQClAgAAAA==.Mizzlillý:BAAALAADCggICwAAAA==.',Mo='Monkd:BAAALAAECgIIBAABLAAECggIFwAbADMeAA==.Moonscream:BAAALAAECgEIAQAAAA==.Morrigu:BAAALAAECgQICgAAAA==.',My='Mygon:BAAALAADCggICwAAAA==.',['Mï']='Mïke:BAAALAADCgcICgAAAA==.',Na='Naamverloren:BAAALAADCgIIAgABLAAECgcIEQABAAAAAA==.Narasimha:BAAALAAECgQIBAAAAA==.',Ne='Neflin:BAAALAADCggIDwAAAA==.Neoptolemos:BAAALAADCgEIAQAAAA==.Neth:BAABLAAECoEYAAICAAgIdCHXEgALAwACAAgIdCHXEgALAwAAAA==.Nevoa:BAAALAADCgcIBwAAAA==.',Ni='Nialla:BAAALAAECgEIAQAAAA==.',No='Noobgonedk:BAAALAAECgEIAQAAAA==.Noreino:BAAALAADCggICAAAAA==.',Nu='Nunnebille:BAAALAAECgEIAQAAAA==.Nutann:BAAALAAECgIIAgAAAA==.',['Nâ']='Nâko:BAAALAAECgQIBAAAAA==.',Om='Omun:BAAALAAECgQICgAAAA==.',Op='Ophiuchus:BAAALAADCgEIAQAAAA==.Opicman:BAAALAAECgQICQAAAA==.',Or='Oromé:BAAALAADCggIEAAAAA==.Orpheas:BAAALAAECgIIAgAAAA==.Orphide:BAAALAAECgQIBAAAAA==.',Os='Osiriss:BAAALAADCggIDwAAAA==.',Pa='Paaldanser:BAAALAAECgcIEQAAAA==.Pallypoise:BAAALAAECggIDgAAAA==.Palmi:BAAALAAECgMICQAAAA==.Papauwtje:BAAALAADCggILAAAAA==.Paradôx:BAAALAAECgMICwAAAA==.Paígey:BAAALAAECgYICAAAAA==.',Pe='Peakyy:BAAALAADCggICAAAAA==.Peetehegseth:BAAALAADCggICAAAAA==.Pepeke:BAAALAADCggIFAAAAA==.Perkamentus:BAACLAAFFIEFAAMTAAII9gXVNACAAAATAAII9gXVNACAAAAIAAEI2QGIJgA+AAAsAAQKgR4AAwgACAjZFugUADECAAgACAjZFugUADECABMABgjcDXh/AD8BAAAA.Pezetairakos:BAAALAAECggICAAAAA==.',Ph='Phanthom:BAAALAAECgQIBAAAAA==.',Pl='Plakbaart:BAAALAAECgYICQAAAA==.',Po='Potlach:BAAALAAECggIDQAAAA==.Powerplay:BAAALAADCgEIAQAAAA==.Powerwordpeg:BAAALAADCggICAAAAA==.',Pr='Prodigy:BAAALAAECgQIBQAAAA==.',Pu='Pujaa:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Purpledrag:BAAALAAECgMIAQAAAA==.Puumala:BAAALAAECgQICQAAAA==.',['Pâ']='Pâpauw:BAAALAAECgMIBwAAAA==.',Ra='Rackiechan:BAABLAAECoEeAAIhAAgI/AQoKwALAQAhAAgI/AQoKwALAQAAAA==.Raelyn:BAAALAAECgYIAgAAAA==.',Re='Reckonian:BAAALAAECggICAAAAA==.',Rh='Rhyliana:BAAALAADCgYIBgAAAA==.',Ri='Rimanda:BAAALAAECggICgAAAA==.Riwen:BAAALAADCgIIAgAAAA==.Rizumu:BAAALAADCgEIAQAAAA==.',Ro='Roawn:BAABLAAECoEVAAIXAAgIDBcjKABJAgAXAAgIDBcjKABJAgAAAA==.Robopants:BAAALAADCggIEAAAAA==.Robowarrior:BAAALAADCgcIDAAAAA==.Rohirrim:BAAALAADCggIEwAAAA==.Rolander:BAAALAAECgMIBgAAAA==.',Ry='Ryder:BAAALAADCgUIBQAAAA==.',Sa='Saafia:BAAALAAECgIIAgAAAA==.Sanctalupa:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.Sarûman:BAAALAAECgEIAQAAAA==.',Sc='Scoobbs:BAABLAAECoEhAAIMAAgI+BW5CAAlAgAMAAgI+BW5CAAlAgAAAA==.Scrobo:BAAALAAECgcIDQAAAA==.Scrótotem:BAAALAADCggIEAABLAAECggIEAABAAAAAA==.',Se='Selfmade:BAAALAADCgYIBgAAAA==.Servall:BAAALAADCgYICgAAAA==.Seylani:BAAALAAECgYIBgAAAA==.',Sh='Shamdru:BAAALAAECgQICgAAAA==.Shamlis:BAAALAADCggIDQAAAA==.Shandrys:BAAALAADCgIIAwAAAA==.Shelloqnatar:BAAALAAECgIIAgABLAAECggIIQAWAH0gAA==.Shelloqnator:BAABLAAECoEhAAIWAAgIfSCTFwDRAgAWAAgIfSCTFwDRAgAAAA==.Shiftmypants:BAAALAADCgQIBAABLAAECggICAABAAAAAA==.Shinimegami:BAAALAAECgYICQABLAAECggIEwABAAAAAA==.Shockingblue:BAAALAAECgYIEwAAAA==.Shorbi:BAABLAAECoElAAIXAAgIIAUuZgBHAQAXAAgIIAUuZgBHAQAAAA==.Shurivie:BAAALAAECgcIDwAAAA==.',Sk='Skjold:BAAALAAECgYIDAABLAAECggIDQABAAAAAA==.Skárin:BAABLAAECoEmAAIYAAgInRnUGwBwAgAYAAgInRnUGwBwAgAAAA==.',Sn='Snifflebron:BAACLAAFFIESAAIXAAcIzyCkAAC2AgAXAAcIzyCkAAC2AgAsAAQKgTAAAxcACAi7JrYAAJUDABcACAi7JrYAAJUDACIAAggnIe0cAL0AAAAA.Snuppa:BAAALAAECgEIAQAAAA==.Snów:BAAALAADCgYIBgAAAA==.',So='Sockpuppet:BAAALAAECgYIEwAAAA==.Solyne:BAAALAADCggICgAAAA==.Soulstripper:BAAALAAECgEIAQAAAA==.',Sp='Spawny:BAABLAAECoEdAAMQAAgI3w8gIgDiAQAQAAgI3w8gIgDiAQAfAAEImARj4QAlAAAAAA==.Spírìt:BAAALAAECgYIBwAAAA==.',St='Staatsvijand:BAAALAADCggIJAAAAA==.Starbugone:BAAALAADCgQIBQAAAA==.Steffenmanna:BAAALAADCgMIAwAAAA==.Stinkel:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Stormen:BAAALAAECgYICAAAAA==.Stormkin:BAABLAAECoEWAAIKAAcI5QlQSQBQAQAKAAcI5QlQSQBQAQAAAA==.',Su='Sunforged:BAAALAAECgQIBwAAAA==.',['Sá']='Sámán:BAAALAADCggIFgAAAA==.',['Sé']='Séntox:BAABLAAECoEVAAIYAAcIixjcLgDuAQAYAAcIixjcLgDuAQAAAA==.',Ta='Taagey:BAAALAAECgUICgAAAA==.Tailung:BAABLAAECoEVAAMaAAgIfxiICwBUAgAaAAgIfxiICwBUAgAbAAEIhQZ3ZQAvAAAAAA==.Takto:BAAALAADCggICAAAAA==.Taschu:BAAALAADCgcICQAAAA==.Tawaress:BAAALAAECgQIBAAAAA==.',Te='Tehaanu:BAABLAAECoEfAAIgAAgIkBpcEwB3AgAgAAgIkBpcEwB3AgAAAA==.Teslata:BAAALAADCgYICwAAAA==.',Th='Thedarkening:BAAALAADCgcIBwAAAA==.Theras:BAABLAAECoEgAAMCAAcItBrnRAAhAgACAAcItBrnRAAhAgADAAEIQRMBVAA3AAAAAA==.Thirikzal:BAAALAADCgcIDAAAAA==.Thomas:BAABLAAECoEhAAMTAAgI0xysIgCTAgATAAgIRBysIgCTAgAIAAQIUR5fRAA2AQAAAA==.Thunderfox:BAAALAADCgcICwAAAA==.Thunderholy:BAAALAADCgYIDwAAAA==.Thunderhunt:BAAALAADCgUIBgAAAA==.Thyrania:BAAALAAECgYICgABLAAECgcIDwABAAAAAA==.',Ti='Tijnio:BAAALAADCgUIBQAAAA==.Tikla:BAABLAAECoEXAAMCAAcIEBbKagC8AQACAAcIABPKagC8AQADAAQIqhSYMQDyAAAAAA==.Tiksia:BAABLAAECoEcAAIWAAcIVRgCUgDfAQAWAAcIVRgCUgDfAQAAAA==.Tiza:BAACLAAFFIEFAAIPAAMIOQcxFADGAAAPAAMIOQcxFADGAAAsAAQKgR8AAg8ACAjrGrAXAJACAA8ACAjrGrAXAJACAAAA.',Tj='Tjockesmock:BAAALAADCggIDwAAAA==.',Tm='Tmy:BAACLAAFFIEGAAIOAAYIAhd/AAAsAgAOAAYIAhd/AAAsAgAsAAQKgRYAAw4ACAhWGHQLAHICAA4ACAhWGHQLAHICABkAAwguASm4ACkAAAAA.',To='Tolkys:BAABLAAECoEfAAIEAAgITRRwIwDbAQAEAAgITRRwIwDbAQAAAA==.Tone:BAAALAADCgYICwAAAA==.Tonedeaf:BAABLAAECoEgAAIjAAgITA5PIgC2AQAjAAgITA5PIgC2AQAAAA==.Toomer:BAABLAAECoEUAAIeAAYIZiBANgARAgAeAAYIZiBANgARAgAAAA==.Tormageddon:BAABLAAECoEfAAIGAAgIDRg/KgBaAgAGAAgIDRg/KgBaAgAAAA==.Tormented:BAAALAAECgIIAgABLAAECggIDQABAAAAAA==.',Tr='Trappedwind:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.Treekloss:BAAALAADCgEIAQAAAA==.Trimbal:BAABLAAECoEWAAIEAAgIwwCtfQASAAAEAAgIwwCtfQASAAAAAA==.Trolbo:BAAALAAECgYIBgAAAA==.Trughis:BAAALAADCggICAAAAA==.',Tw='Twilex:BAAALAADCggICAAAAA==.Twinkel:BAAALAAECgIIAQAAAA==.',Ty='Tyriia:BAAALAADCgQIBQAAAA==.Tyrin:BAAALAADCggIEAABLAAECgcIGgAEAL8gAA==.',['Tï']='Tïch:BAAALAAECgQIBQAAAA==.',Ui='Uinen:BAABLAAECoEcAAIZAAcIFxPTQgCTAQAZAAcIFxPTQgCTAQAAAA==.',Un='Undarath:BAABLAAECoEfAAIIAAgIiA/9GgABAgAIAAgIiA/9GgABAgAAAA==.',Va='Valgil:BAAALAAECgQIBAAAAA==.Valkyrio:BAAALAAECgYIDAAAAA==.Vanfelswing:BAAALAAECgIIAgAAAA==.Varda:BAAALAAECgEIAQAAAA==.',Ve='Veritasi:BAAALAAECgYIDwAAAA==.',Vi='Villblomst:BAAALAAECgEIAQAAAA==.',Wa='Waiteyak:BAAALAADCgMIAwABLAAECgQIBAABAAAAAA==.Wall:BAAALAADCggIDgABLAAECggIDQABAAAAAA==.Wallié:BAAALAADCgEIAQAAAA==.',We='Wendie:BAAALAADCgUICAAAAA==.',Wh='Whatlock:BAABLAAECoElAAMTAAcI2gjDeQBOAQATAAcI2gjDeQBOAQAIAAEIlwWujAAgAAAAAA==.',Wi='Wiiroy:BAABLAAECoEfAAIHAAgIyxAtJADAAQAHAAgIyxAtJADAAQAAAA==.Winchesteruk:BAAALAAECgYIEgAAAA==.Windspearr:BAAALAAECgYIBgAAAA==.',Wo='Woc:BAAALAAECgEIAQAAAA==.Woudloper:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.',Wt='Wtbhaste:BAABLAAECoEcAAIbAAcINSCYEQCCAgAbAAcINSCYEQCCAgAAAA==.',Xa='Xazual:BAAALAAECggIBQABLAAECgUICAABAAAAAA==.',Xi='Xiz:BAAALAADCggICAAAAA==.',Xt='Xtál:BAAALAADCggIDwAAAA==.',Ye='Yemy:BAAALAAECgQIBAAAAA==.',Yp='Ypér:BAAALAAECggICAAAAA==.',Yu='Yulevoker:BAAALAADCggICAAAAA==.Yuto:BAAALAAECgMIBwAAAA==.',['Yö']='Yönritari:BAABLAAECoEUAAMFAAgIWBnKDwA/AgAFAAgIWBnKDwA/AgASAAQI0A//7wDrAAAAAA==.',Za='Zakizaurus:BAABLAAECoEcAAIXAAcI1g9zSACvAQAXAAcI1g9zSACvAQAAAA==.Zanekun:BAAALAAECggIEAAAAA==.Zanithia:BAAALAADCgYIBgAAAA==.',Ze='Zelxuis:BAAALAADCgUIBQAAAA==.Zerveres:BAAALAADCggIEAAAAA==.',Zu='Zubeia:BAAALAADCggICAAAAA==.Zucks:BAAALAADCgcIBwAAAA==.',Zy='Zytor:BAABLAAECoEVAAIGAAYIow5BcABeAQAGAAYIow5BcABeAQAAAA==.',['Zá']='Zánkou:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end