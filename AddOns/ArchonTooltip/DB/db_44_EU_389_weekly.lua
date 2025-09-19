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
 local lookup = {'Unknown-Unknown','Shaman-Enhancement','Mage-Arcane','DeathKnight-Unholy','Hunter-Survival','DemonHunter-Havoc','Monk-Mistweaver','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Druid-Feral','Rogue-Assassination','Warrior-Fury','Warrior-Arms','Rogue-Outlaw','Druid-Restoration','DeathKnight-Frost','Priest-Holy','Mage-Frost','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Priest-Shadow','Monk-Windwalker','Druid-Balance','DemonHunter-Vengeance','Priest-Discipline','Monk-Brewmaster','Druid-Guardian',}; local provider = {region='EU',realm='Uldaman',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abp:BAAALAAECgMIBgAAAA==.Abytïel:BAAALAADCggIDwAAAA==.',Ad='Adyonis:BAAALAAECgMIBgAAAA==.',Ae='Aeternia:BAAALAAECgIIAgAAAA==.',Ag='Aghanim:BAAALAAECgcIDgAAAA==.',Ak='Akaziiel:BAAALAADCggIDgAAAA==.Akema:BAAALAADCgcIDQABLAAECgQIBQABAAAAAA==.Aknot:BAAALAAECgYIDwAAAA==.',Al='Alariell:BAAALAADCgcIBwAAAA==.Alcyrogue:BAAALAAECgUIBwAAAA==.Alexcremant:BAAALAADCgMIAwAAAA==.Alfà:BAABLAAECoEWAAICAAgIgCHiAgCiAgACAAgIgCHiAgCiAgAAAA==.Algildel:BAAALAAECgQIBQAAAA==.Algorythme:BAAALAAECgEIAgAAAA==.Alibaba:BAAALAADCggIEAAAAA==.Alinae:BAAALAADCgYIAQAAAA==.Alithea:BAABLAAECoEVAAIDAAcIIBNkLADTAQADAAcIIBNkLADTAQAAAA==.Alkanaar:BAAALAADCgIIAgAAAA==.Alkêrïss:BAAALAAECgIIAwAAAA==.Alkêrøn:BAAALAAECgMIBgAAAA==.Allmet:BAAALAADCgIIAwAAAA==.Almerik:BAAALAAECgMIAwAAAA==.Altamam:BAAALAADCggICQAAAA==.Altfquatr:BAAALAADCgcIBwAAAA==.Alyan:BAAALAAECgUICAAAAA==.Alyrka:BAAALAAECgEIAQAAAA==.',Am='Amaltor:BAAALAAECgYIDwAAAA==.Ambres:BAAALAAECgQIBgAAAA==.Amidamari:BAAALAADCggIEAAAAA==.Amynii:BAACLAAFFIEFAAIDAAMIGRWzBAAKAQADAAMIGRWzBAAKAQAsAAQKgRgAAgMACAjuIJEJAPMCAAMACAjuIJEJAPMCAAAA.Amyxì:BAAALAAECgcIDAAAAA==.',An='Angela:BAAALAAECgEIAgAAAA==.Angelnight:BAAALAAECgEIAQAAAA==.Angrystorm:BAAALAAECgQIBQAAAA==.Anniah:BAAALAADCgcIBwAAAA==.Anomalus:BAAALAADCgYIBgAAAA==.Anonymôus:BAAALAAECgQIBQAAAA==.Antalion:BAAALAADCggIBwAAAA==.Anørg:BAAALAAECggIDAAAAA==.',Ao='Aodus:BAAALAADCggIDgAAAA==.',Ap='Apophyse:BAAALAAECgYICQAAAA==.Appelflap:BAAALAADCgcIEAAAAA==.',Ar='Arak:BAAALAAECgMIBQAAAA==.Argahn:BAAALAAECgUIBQAAAA==.Ariinui:BAAALAADCggIDAAAAA==.Arkytos:BAABLAAECoEUAAIEAAgINw9iDQDZAQAEAAgINw9iDQDZAQAAAA==.Arlax:BAAALAAECgcIDgAAAA==.Arnialys:BAAALAAFFAIIAgAAAA==.Arrowsoir:BAABLAAECoEVAAIFAAgI9Rz/AADbAgAFAAgI9Rz/AADbAgAAAA==.Artemane:BAAALAADCggIFQAAAA==.Arvaan:BAAALAAECgMIBgAAAA==.',At='Ateesa:BAAALAADCggICAAAAA==.',Au='Auliya:BAAALAAECgQIBQAAAA==.',Av='Avici:BAAALAAECgQIBAAAAA==.',Ax='Axenn:BAAALAAECgEIAQAAAA==.',Az='Azelas:BAAALAAECgEIAQAAAA==.Azurïs:BAAALAADCggIDgAAAA==.Azög:BAAALAADCggIDgABLAAECggIFQAGAB4cAA==.',['Aí']='Aífé:BAAALAADCggICAABLAAECgUICgABAAAAAA==.',Ba='Badbreathz:BAAALAADCgQIBAABLAAECggICwABAAAAAA==.Bahamuth:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Balafrey:BAAALAADCgYIBgAAAA==.Barbarutt:BAAALAADCggICAAAAA==.Basalsena:BAAALAAECgEIAQAAAA==.',Be='Beber:BAAALAAECgUICgAAAA==.Becca:BAAALAAECgEIAQAAAA==.Beneto:BAAALAAECgQIBQAAAA==.Bevelle:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.',Bg='Bgz:BAAALAAECgIIAgABLAAECggICwABAAAAAA==.',Bi='Bibifox:BAAALAADCgcIDgAAAA==.Bidet:BAAALAADCgYIBgAAAA==.Biff:BAAALAADCggIDgAAAA==.Biflon:BAAALAADCgQIBAAAAA==.Bignaingui:BAAALAAECggIDwAAAA==.Bigted:BAAALAADCgMIAwAAAA==.Billyburger:BAAALAAECggICQAAAA==.Binøuzz:BAAALAADCgcICQAAAA==.Bièrobeurre:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.',Bl='Blackrøckk:BAAALAAECgcIDQAAAA==.Blastery:BAAALAADCgcIDQAAAA==.Blindhunter:BAAALAAECgMIBgAAAA==.Bluë:BAAALAADCgcIDQAAAA==.',Bo='Bobbly:BAAALAAECgYIDAAAAA==.Borcha:BAAALAAECgYICQAAAA==.Bostau:BAAALAAFFAIIAwAAAA==.',Br='Brakadk:BAAALAAECgYIBgABLAAECggICAABAAAAAA==.Brakamage:BAAALAAECggICAAAAA==.Brakamonkey:BAACLAAFFIEFAAIHAAMI1A2QAgDqAAAHAAMI1A2QAgDqAAAsAAQKgRgAAgcACAjaHTMEALoCAAcACAjaHTMEALoCAAAA.Bret:BAAALAAECgIIAgAAAA==.Briquait:BAAALAADCgYIDAAAAA==.Brunito:BAAALAAECgYIBgAAAA==.Brøcknroll:BAAALAAECgYIBwAAAA==.',Bu='Bulex:BAAALAAECgYIBgABLAAECgcIFAAIAOsfAA==.Buush:BAAALAADCggIDQAAAA==.',By='Byakü:BAAALAAECgMIBgAAAA==.',['Bà']='Bàz:BAAALAAECgYICAAAAA==.',['Bé']='Bélartémis:BAAALAAECgMIBAAAAA==.Bén:BAAALAAECgUICgAAAA==.',Ca='Cadarik:BAAALAAECgYIBwAAAA==.Cadoubi:BAAALAAECgcIDwAAAA==.Caiusson:BAAALAAECgIIBgAAAA==.Calidya:BAAALAAECgYICwAAAA==.Calinouha:BAAALAAECgEIAQAAAA==.Callipso:BAAALAADCgcIBwAAAA==.Candérous:BAAALAADCgcIDQAAAA==.Cariquick:BAABLAAECoEYAAMJAAgIZCM4AABOAwAJAAgIZCM4AABOAwAKAAcIvRdvFgC7AQAAAA==.Cat:BAAALAAECggIEgAAAA==.',Ce='Cellul:BAAALAADCgYIBgAAAA==.',Ch='Chamchamm:BAAALAAECgIIAgAAAA==.Chamingtatum:BAAALAAECgYICQAAAA==.Chamork:BAAALAAECggICAAAAA==.Chappintz:BAAALAAECgMIAwAAAA==.Chatonn:BAAALAAECgEIAQAAAA==.Chavalala:BAAALAADCggIEgAAAA==.Chavamalt:BAAALAADCggIEQABLAADCggIEgABAAAAAA==.Chavi:BAAALAADCggICAAAAA==.Cheldriar:BAAALAADCgMIBQAAAA==.Chewbelle:BAAALAAECgYICgAAAA==.Chewbette:BAAALAADCggIFAABLAAECgYICgABAAAAAA==.Chezyx:BAAALAAECgYIDwAAAA==.Chickxb:BAAALAAECgYIDwAAAA==.Chnewb:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.Chucknourïsh:BAAALAADCggIEAAAAA==.Chârly:BAAALAADCgUIBQABLAAECgUIBgABAAAAAA==.Chépité:BAAALAAECgUICgAAAA==.Chøcozob:BAAALAADCgYICgAAAA==.Chøn:BAAALAAECgMIAwABLAAECgYICAABAAAAAA==.Chøuette:BAAALAADCgcIBwAAAA==.',Ci='Cingrall:BAAALAAECgMIBQAAAA==.Ciremyá:BAABLAAECoEUAAIIAAcI6x+gEQBtAgAIAAcI6x+gEQBtAgAAAA==.',Cl='Clarizy:BAAALAAECgcIDwAAAA==.Clîx:BAAALAAECgQIBAAAAA==.',Co='Codie:BAACLAAFFIEFAAILAAMIXx24AQANAQALAAMIXx24AQANAQAsAAQKgRgAAgsACAh6ImYDAPQCAAsACAh6ImYDAPQCAAAA.Coffëetime:BAAALAAECgcIDQAAAA==.Compresse:BAAALAADCgcIBwAAAA==.',Cr='Crottihunt:BAAALAADCgcIDgAAAA==.Crottounette:BAAALAADCggICAAAAA==.',Cu='Cubalibre:BAAALAADCgMIAwAAAA==.',['Cé']='Cépasmoi:BAAALAAECgEIAQAAAA==.',['Cë']='Cëda:BAAALAADCgcIDwAAAA==.',['Cø']='Cømonk:BAAALAAECggICQAAAA==.Cøpal:BAAALAAECggIDgAAAA==.Cørgash:BAAALAAECgYIEQAAAA==.Cøwar:BAAALAAECggIDgAAAA==.',Da='Daemoira:BAAALAAECgIIBAAAAA==.Dagø:BAAALAADCgEIAQAAAA==.Daiya:BAAALAAECgMIAwAAAA==.Dala:BAAALAADCgYIBgAAAA==.Danaris:BAAALAAECgYICwAAAA==.Darakrein:BAAALAADCggICwAAAA==.Darklessx:BAAALAAECgMIAwAAAA==.Darman:BAAALAAECgYIDgAAAA==.Darmelos:BAAALAAECgYIBgAAAA==.Darragh:BAAALAADCgcIBwAAAA==.Dawrn:BAAALAAECgMIBgAAAA==.Dayonîs:BAABLAAECoEUAAMLAAcIeB74CwBrAgALAAcIeB74CwBrAgAMAAcISSDbEQBJAgAAAA==.Daï:BAAALAADCgYIBgAAAA==.Daïmoon:BAAALAAECgYICgAAAA==.',De='Dealen:BAAALAAECgMIBAAAAA==.Defcø:BAAALAAECgQIBQAAAA==.Delnàss:BAAALAAECgEIAQAAAA==.Desmotsnyste:BAAALAAECgEIAQAAAA==.',Di='Diamanss:BAAALAAECgcIDwAAAA==.Dihann:BAAALAADCggICAAAAA==.Dilili:BAAALAADCgIIAgAAAA==.Dispela:BAAALAADCggICAABLAAECgUIBQABAAAAAA==.Disturbiä:BAAALAAECgEIAQAAAA==.',Dj='Djivs:BAAALAAECgYIDQAAAA==.Djïnh:BAABLAAECoEYAAIDAAgIbB9iDwC0AgADAAgIbB9iDwC0AgAAAA==.',Dk='Dkarou:BAAALAAECgcIDgAAAA==.Dknoir:BAAALAADCgcIDgAAAA==.Dkth:BAAALAAECggICAABLAAECggIDQABAAAAAA==.Dkuchi:BAAALAAECgYICwAAAA==.',Dm='Dmunky:BAAALAAECgIIAgAAAA==.',Do='Dolithiel:BAAALAAECggIEwAAAA==.Domini:BAAALAAECgMIBgAAAA==.Doragon:BAAALAADCggICAABLAAECgcIFAANAC0fAA==.',Dr='Dracouille:BAAALAAECgMICAAAAA==.Dragobert:BAAALAAECgYIEgAAAA==.Dragrout:BAAALAADCgcIBwAAAA==.Drakaï:BAAALAADCgcIBwAAAA==.Draker:BAAALAADCgcIBwAAAA==.Drakhunt:BAAALAAECgMIAwAAAA==.Dramounet:BAAALAAFFAIIAgAAAA==.Drazzhar:BAAALAADCgYIBgAAAA==.Dreadlayz:BAAALAADCggIFwAAAA==.Dreadsthyl:BAABLAAECoEVAAIGAAgIHhy3DwCsAgAGAAgIHhy3DwCsAgAAAA==.Druidehealer:BAAALAADCggICwAAAA==.Druidife:BAAALAADCggICAAAAA==.Druidland:BAAALAAECgMIAwABLAAECgUIBQABAAAAAA==.Dràma:BAAALAADCgcIBwAAAA==.Drëalyna:BAAALAADCgcICwAAAA==.',Du='Durzzark:BAAALAAFFAMIAwAAAA==.Durzârk:BAAALAAFFAIIAgAAAA==.',['Dà']='Dàxter:BAAALAAECgUICQAAAA==.',['Dâ']='Dârmân:BAAALAADCggICAAAAA==.',['Dé']='Déspe:BAAALAAECgUIBQAAAA==.',['Dë']='Dëspe:BAAALAADCgcIBwABLAAECgUIBQABAAAAAA==.',['Dï']='Dïä:BAAALAADCggICAAAAA==.',['Dö']='Dömyos:BAAALAAECgQIBQAAAA==.',['Dü']='Düvel:BAAALAADCgUIBQABLAAECgUIBgABAAAAAA==.',Ea='Eauminerale:BAAALAAECgMIBQAAAA==.',Ec='Eckaz:BAAALAADCggICQAAAA==.',Ei='Eisha:BAAALAADCgcICAAAAA==.',El='Elaydja:BAAALAAECgYIBgAAAA==.Eldaar:BAAALAADCgMIAwAAAA==.Eldk:BAAALAAECgUIBQAAAA==.Eledria:BAAALAAECgMIBgAAAA==.Elenem:BAAALAAECgYIBgAAAA==.Elestren:BAAALAADCggIBwAAAA==.Elfyra:BAAALAAECgQIBQAAAA==.Elhayym:BAAALAAECgQIBQAAAA==.Elpis:BAAALAAECgcICQAAAA==.Elsyoid:BAAALAAECgQIBwAAAA==.Elthagon:BAAALAAECgMIAwAAAA==.Elthanos:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Eluney:BAAALAAECgYIBgAAAA==.',Em='Emerea:BAAALAAECgEIAgAAAA==.Emilyanne:BAAALAAECgMIAwAAAA==.Emmawatson:BAACLAAFFIEFAAIOAAMIaRzzAABEAQAOAAMIaRzzAABEAQAsAAQKgRgAAg4ACAjCIlYCADIDAA4ACAjCIlYCADIDAAAA.Emmawatsøn:BAAALAAECgYIBgAAAA==.',Eo='Eohmol:BAAALAAECgIIAgAAAA==.',Ep='Ephaistosii:BAAALAAECgYIDAAAAA==.',Er='Eracknwar:BAABLAAECoEUAAMPAAcIrxvXEQBgAgAPAAcIiRvXEQBgAgAQAAIIPxyrEQCLAAAAAA==.Erackñ:BAAALAADCggICAABLAAECgcIFAAPAK8bAA==.Erinnarra:BAAALAAECgcIDwAAAA==.Erisis:BAAALAADCggIDQAAAA==.Ermie:BAAALAAECgYICgAAAA==.',Es='Eseldaar:BAAALAAECgMIBQAAAA==.Esho:BAAALAADCggIFQAAAA==.Eska:BAAALAAECgEIAQAAAA==.Esmæra:BAAALAADCgcICwAAAA==.',Et='Ethernîty:BAAALAADCggIBwAAAA==.',Ev='Evangelîne:BAAALAAECgYIBgAAAA==.Everstyle:BAAALAAECgYICAAAAA==.',Ex='Exar:BAAALAAECgYIDAAAAA==.Exulpe:BAAALAAECgIIAgAAAA==.',Fa='Fahgus:BAAALAAECgIIAgAAAA==.Fairen:BAAALAADCggIEQAAAA==.Fandjoz:BAAALAAECgEIAQAAAA==.',Fe='Feita:BAAALAAECgQIBQAAAA==.',Fi='Fiburngrim:BAAALAAECgIIAgAAAA==.Fiery:BAAALAADCggIEAAAAA==.Fistoeuse:BAAALAAECgYIBwAAAA==.',Fl='Flaviø:BAAALAADCggIDgABLAAFFAMIBQAKAOIbAA==.Flechebrisé:BAAALAADCgYIBgAAAA==.Fleurdoré:BAAALAAECgQIBgAAAA==.Flippy:BAAALAAECgQIBQAAAA==.Florenciana:BAAALAADCgcICQAAAA==.Fluwin:BAAALAADCggICgAAAA==.Flöflo:BAAALAADCgEIAQAAAA==.Fløkii:BAAALAAECgMIBAAAAA==.Flÿ:BAAALAADCgcIAwAAAA==.',Fo='Fomar:BAAALAAECgcIDgAAAA==.Foudeguerre:BAAALAAECgQIBAAAAA==.',Fr='Franjpane:BAAALAAECgcICQAAAA==.',Fu='Fupô:BAAALAAECgQIBwAAAA==.Furilaax:BAAALAADCgcIDAAAAA==.Furryo:BAAALAADCggIDwAAAA==.Fuëgø:BAAALAAECgQIBQAAAA==.',Fy='Fyro:BAAALAADCgYICgAAAA==.',['Fø']='Føudguerre:BAAALAAECgYIBgAAAA==.',['Fü']='Fümika:BAAALAADCgIIAgAAAA==.',Ga='Gafine:BAAALAADCggIFAAAAA==.Gagagouu:BAAALAADCgcIBwAAAA==.Galewen:BAAALAADCggICAAAAA==.Galila:BAAALAADCgYIBgAAAA==.Gantua:BAAALAADCgYIBgAAAA==.Gashôu:BAAALAAECgcIBwAAAA==.',Ge='Ged:BAAALAAFFAIIAgAAAA==.Gedref:BAAALAAECgUICgAAAA==.Geiseicaille:BAAALAADCgcIDQAAAA==.Genjji:BAAALAADCgEIAQABLAAECgMICAABAAAAAA==.',Gh='Ghibly:BAAALAAECgIIAgAAAA==.',Gl='Glandhalf:BAAALAADCggICAAAAA==.Glawar:BAAALAADCggICAAAAA==.Glouglou:BAAALAAECgcICgAAAA==.',Gn='Gnuteg:BAABLAAECoEUAAIRAAgILSOIAAArAwARAAgILSOIAAArAwAAAA==.',Go='Goltc:BAACLAAFFIEKAAISAAUIkxDKAABUAQASAAUIkxDKAABUAQAsAAQKgRgAAhIACAgOH8wGAJkCABIACAgOH8wGAJkCAAAA.Gorkta:BAABLAAECoEXAAIQAAgIXRkwAgB/AgAQAAgIXRkwAgB/AgAAAA==.',Gr='Grenchyrench:BAAALAAECgEIAQAAAA==.Greymalkïn:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.Grobidon:BAAALAADCgMIAwAAAA==.Gromeur:BAAALAAECgcIDgAAAA==.Groojin:BAAALAADCggIDwABLAAECggIFQAGAB4cAA==.Grosbilly:BAAALAAECgUIBQAAAA==.Groscalin:BAAALAAECgMIBgAAAA==.',Gu='Guikusu:BAAALAAECgYICwAAAA==.',['Gé']='Gépetto:BAAALAADCgcIDgABLAAECgIIBAABAAAAAA==.',['Gø']='Gøupilførest:BAAALAAECgMIBAAAAA==.',Ha='Harrog:BAAALAADCgYIAwAAAA==.',He='Healator:BAAALAADCgcIBwAAAA==.Hebï:BAAALAAECgMIBgAAAA==.Heighn:BAAALAAECgMIBQAAAA==.Heløïse:BAAALAAECgUIBwAAAA==.Hestiahunt:BAAALAAECgMIBQAAAA==.',Hi='Hikkari:BAAALAADCggIDQAAAA==.Hiolo:BAAALAAECgQICAAAAA==.Hioolo:BAAALAAECgYICwAAAA==.Hirumiha:BAAALAAECgQIBwAAAA==.',Ho='Hokanu:BAAALAAECgIIAgABLAAECgQIBQABAAAAAA==.Holyx:BAAALAAECgYIEgAAAA==.Housenka:BAABLAAECoEUAAINAAcILR+UBACFAgANAAcILR+UBACFAgAAAA==.',Hr='Hrak:BAAALAAECgMIBgAAAA==.',Hu='Hunteurre:BAAALAAECgQICQAAAA==.Huntreß:BAAALAADCgEIAQAAAA==.',Hw='Hwii:BAAALAAECgMIBQAAAA==.',Hy='Hydroxÿle:BAAALAADCgQICAABLAAECgQIBAABAAAAAA==.Hyra:BAAALAADCggIDgAAAA==.',['Hî']='Hîroki:BAABLAAECoEcAAIPAAgI4RwlDACzAgAPAAgI4RwlDACzAgAAAA==.Hîryne:BAAALAADCggIDwAAAA==.',['Hø']='Høly:BAAALAADCgIIAgAAAA==.',Ic='Ichigor:BAAALAAECgEIAgAAAA==.',Il='Iluvathar:BAAALAADCgEIAQAAAA==.Ilydara:BAAALAADCgYIBgAAAA==.Iléyïa:BAAALAAECgcIDwAAAA==.',In='Inara:BAAALAAECgcIDgAAAA==.Ingénieur:BAAALAADCgcICgAAAA==.Inoy:BAABLAAECoEWAAIDAAgIkiEMCQD5AgADAAgIkiEMCQD5AgAAAA==.Insensity:BAAALAADCgcIBwAAAA==.Intozelïght:BAAALAAECgEIAQAAAA==.Intozewild:BAAALAADCgcIBwAAAA==.Inumi:BAAALAAECgYICgAAAA==.',Ir='Iraldin:BAAALAAECgEIAQAAAA==.Ironvax:BAAALAAECgYIBwAAAA==.Irrysa:BAAALAADCgIIAgAAAA==.Irïs:BAAALAADCggIDQAAAA==.',Is='Isalene:BAABLAAECoEVAAIOAAgI6iBOAwAaAwAOAAgI6iBOAwAaAwAAAA==.Iss:BAABLAAECoEUAAISAAcIixU1GwCwAQASAAcIixU1GwCwAQAAAA==.',Ja='Jabbe:BAAALAAECgMIAwAAAA==.Jabbyi:BAAALAAECgEIAQAAAA==.Jadziadax:BAAALAAECgYICwAAAA==.Jankrila:BAAALAAECgIIAgAAAA==.',Jc='Jchbobinette:BAAALAAECgYIDwAAAA==.',Je='Jecht:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Jeiden:BAAALAAECggICAAAAA==.Jelia:BAAALAAECgMIAwAAAA==.Jessam:BAAALAAECgUICgAAAA==.Jetestelejeu:BAAALAADCgYICwAAAA==.',Jh='Jhony:BAAALAAECgMIBQAAAA==.',Jo='Jorkine:BAAALAAECgYICgAAAA==.',Jq='Jqsh:BAAALAADCggIDAAAAA==.',Ju='Juchass:BAAALAADCgQIBAABLAAECgMIBwABAAAAAA==.Juduku:BAAALAAECgUICgAAAA==.Jupala:BAAALAAECgMIBwAAAA==.',['Jê']='Jêyjêy:BAAALAADCggICAAAAA==.',['Jö']='Jöhnweak:BAAALAAECgYIBgAAAA==.',['Jø']='Jølyne:BAABLAAECoEUAAITAAcIRiGWEQCRAgATAAcIRiGWEQCRAgAAAA==.',Ka='Kaahli:BAAALAADCggICQAAAA==.Kaalimshar:BAAALAADCggIDgAAAA==.Kaelyss:BAAALAADCggIDwABLAAECggIFQAGAB4cAA==.Kafue:BAAALAAECgYICgAAAA==.Kalliope:BAAALAAECgYIDwAAAA==.Kaly:BAAALAAECgEIAQAAAA==.Kalygräal:BAAALAAECgQIBgAAAA==.Kantan:BAAALAADCgcIBwAAAA==.Kaptain:BAAALAAECgMIAwAAAA==.Karoupali:BAAALAAECgMIBQAAAA==.Kaszama:BAAALAADCgQIBAAAAA==.Kayh:BAAALAAECgQIBQAAAA==.Kaîne:BAAALAAECgYICgAAAA==.Kaïdéliste:BAACLAAFFIEFAAIUAAMI2RI/AwAHAQAUAAMI2RI/AwAHAQAsAAQKgRgAAhQACAjbGnMPAFUCABQACAjbGnMPAFUCAAAA.',Kh='Khaali:BAAALAADCgYIBgAAAA==.Khaaly:BAAALAADCggIDwAAAA==.Khagdar:BAABLAAECoEVAAMVAAgIoRX3DAAOAgAVAAgIoRX3DAAOAgADAAcIWwivOwCDAQAAAA==.Khalgaroth:BAAALAAECgYIDAAAAA==.Khaseelena:BAAALAAECgIIAgAAAA==.Khazran:BAAALAAECgMIBQAAAA==.Khepri:BAAALAAECgYIDwAAAA==.Khold:BAAALAAECgMIBQAAAA==.Khumiguh:BAABLAAECoEXAAISAAgIeBELGADMAQASAAgIeBELGADMAQAAAA==.Khyrae:BAAALAADCgcIDQAAAA==.',Ki='Kimahry:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.Kisska:BAAALAAECgMIBgAAAA==.Kitchiarû:BAAALAAFFAIIAgAAAA==.',Kl='Klëms:BAAALAAECgMICAABLAAECgUIBQABAAAAAA==.',Ko='Kodosinistre:BAAALAADCgcIBwAAAA==.Koljin:BAAALAAECgEIAQAAAA==.Konnix:BAAALAAECgcIEAAAAA==.Koopak:BAAALAAECgEIAQAAAA==.Kooyoku:BAAALAAECgcIEAAAAA==.Koriàlstrasz:BAAALAADCgYIBgAAAA==.Kouzmin:BAAALAADCgYIBwAAAA==.',Kr='Krazilk:BAABLAAECoEWAAQWAAcIdxRgHADsAQAWAAcIdxRgHADsAQAXAAII5g0FSQB0AAAYAAEIBAGLMwAXAAAAAA==.Krazimage:BAABLAAECoEUAAIDAAcIASIGEACuAgADAAcIASIGEACuAgABLAAECgcIFgAWAHcUAA==.Krazip:BAAALAADCgcICQABLAAECgcIFgAWAHcUAA==.Krazisham:BAAALAADCgMIAwABLAAECgcIFgAWAHcUAA==.Krirl:BAAALAAECgYIBgAAAA==.',Ku='Kuchîkukan:BAAALAADCggICwAAAA==.',Ky='Kylanos:BAAALAAECgMIBAAAAA==.Kytana:BAAALAAECgEIAQAAAA==.',['Kâ']='Kâali:BAAALAADCgcIBwAAAA==.Kârlyne:BAAALAADCggICAAAAA==.Kâvalan:BAAALAAECgEIAQAAAA==.',['Kä']='Kärlyne:BAAALAADCgcIBwAAAA==.Käräh:BAAALAADCggICAAAAA==.Kääli:BAAALAADCggIDQAAAA==.',['Kå']='Kåïø:BAAALAAECgUIBQAAAA==.',['Kô']='Kônji:BAAALAAECgYICAAAAA==.Kôsâkïnlÿâ:BAAALAAECgMIBQAAAA==.',['Kö']='Köinzhel:BAAALAADCgcICgAAAA==.',La='Labellemia:BAAALAAECgUIBgAAAA==.Lalielle:BAAALAAECgMIBQAAAA==.Langenøir:BAAALAAECgYIBgAAAA==.Langla:BAAALAADCgYIBgAAAA==.Larcherfou:BAAALAAECggICwAAAA==.Larniahatal:BAAALAADCgMIBAABLAAECgEIAgABAAAAAA==.',Le='Lechad:BAAALAADCggICAAAAA==.Letuere:BAAALAADCggICAAAAA==.Leyanå:BAAALAADCgEIAQAAAA==.',Lh='Lhyndreïs:BAAALAAECggIEgABLAAECggIFQAFAPUcAA==.',Li='Lianastrasza:BAAALAAECgEIAQAAAA==.Licra:BAAALAAECggICQAAAA==.Lihaell:BAAALAAECgIIAgAAAA==.Lilubelle:BAAALAAECgMIAwAAAA==.Lilyscot:BAAALAADCgYICAAAAA==.Limei:BAAALAADCggICAAAAA==.Limyè:BAAALAAECgYIDQAAAA==.Linshea:BAAALAAECgQIBgAAAA==.Lisztaar:BAAALAADCggIDAAAAA==.Littleakema:BAAALAAECgQIBQAAAA==.Liwad:BAAALAADCgUIBQAAAA==.',Lo='Lodirmur:BAAALAAECgUICgAAAA==.Logalas:BAAALAADCggIFAAAAA==.Lolaî:BAAALAAECgQIBQAAAA==.Lovaliê:BAAALAAECgYICwAAAA==.',Lu='Luberios:BAAALAADCgUIBwAAAA==.Lucyann:BAAALAADCgEIAQAAAA==.Lucàss:BAAALAADCgcICQAAAA==.Ludsoo:BAAALAADCgYIBwAAAA==.Lumiør:BAAALAADCgcICwAAAA==.Lunetale:BAAALAADCggIDgAAAA==.',Ly='Lyliakid:BAAALAAECgUICAAAAA==.Lynuan:BAAALAAECgIIAgAAAA==.',['Lâ']='Lâmarae:BAAALAAECgYICQAAAA==.',['Lä']='Läîyna:BAAALAAECgUICAAAAA==.',['Lè']='Lèffe:BAAALAAECgUIBgAAAA==.',['Lé']='Léonas:BAAALAADCgQIBAAAAA==.',['Lø']='Løuise:BAAALAAECgYICgAAAA==.',Ma='Macrobot:BAAALAADCggICAAAAA==.Madarä:BAAALAADCgcIDQAAAA==.Magineke:BAAALAAECgMICAAAAA==.Makdrood:BAAALAAECgIIAgAAAA==.Makta:BAAALAAECgcICAAAAA==.Malfusios:BAAALAADCggICwAAAA==.Manelfoski:BAAALAADCggIDQAAAA==.Maqélébelle:BAAALAAECgEIAQAAAA==.Mathra:BAAALAADCgQIBAAAAA==.Matrand:BAAALAADCgcIBwAAAA==.Mawi:BAAALAAECgIIAgAAAA==.',Mc='Mckenzie:BAAALAAECgEIAgAAAA==.',Me='Mecanoshade:BAAALAADCggIDAAAAA==.Meeps:BAAALAAECgMIAwAAAA==.Mellusyne:BAAALAAECgQIBQAAAA==.Melvérin:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Mercuronite:BAAALAAECgMIBQAAAA==.Meretryn:BAAALAAECgcICAAAAA==.',Mi='Miguelitoo:BAAALAAECgYICwAAAA==.Milianna:BAAALAAECgEIAQAAAA==.Miltotem:BAAALAADCggIDQAAAA==.Miminøus:BAAALAAECgYICAAAAA==.Minakouso:BAAALAADCgEIAQAAAA==.Mirajayne:BAAALAAECgEIAgAAAA==.Missterloup:BAAALAAECgYIBgAAAA==.Mithotem:BAAALAADCgQIBAAAAA==.Mityle:BAAALAADCgQIBAAAAA==.',Mo='Mok:BAAALAAECgYICQAAAA==.Mond:BAAALAAECgYICQAAAA==.Monkdoteck:BAAALAAECggIDgAAAA==.Morfos:BAAALAAECgYIBwAAAA==.Moskvä:BAAALAADCgEIAgAAAA==.',Mu='Muna:BAAALAADCgcICwAAAA==.Munshi:BAAALAAECgMIBAAAAA==.Murmel:BAAALAAECgQIBwAAAA==.Mustanggt:BAAALAADCgYICAAAAA==.',Mw='Mwulazan:BAAALAADCgIIAgAAAA==.',My='Mya:BAAALAADCgMIAwAAAA==.Myin:BAAALAADCgQIBAAAAA==.Mynésïe:BAAALAAECgIIAgAAAA==.',['Mà']='Màko:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.',['Mé']='Méloria:BAABLAAECoEUAAILAAcIbA9EMwBnAQALAAcIbA9EMwBnAQAAAA==.',['Mò']='Mòlto:BAAALAADCggIEQAAAA==.',['Mø']='Møkø:BAAALAAECgEIAgAAAA==.Møundee:BAAALAAECgYIBgAAAA==.Møustik:BAAALAADCgIIAQABLAAECgMICAABAAAAAA==.Møøn:BAAALAAECgMIBgAAAA==.',['Mû']='Mûranna:BAAALAADCgQIAQAAAA==.',Na='Nabulphine:BAAALAAECgYICQAAAA==.Nainfernal:BAAALAADCggIDAAAAA==.Nainfomaniac:BAAALAAECgEIAQAAAA==.Nanapastifo:BAAALAADCgMIAwAAAA==.Narlia:BAAALAAECgIIAgAAAA==.Natrÿ:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.Natshsram:BAAALAAECgMIBQAAAA==.Nawaks:BAAALAAECgQIBQAAAA==.',Nb='Nbtwo:BAABLAAECoETAAIKAAcIKh4wCwBuAgAKAAcIKh4wCwBuAgAAAA==.',Ne='Nefelin:BAAALAADCgYIBgAAAA==.Nehfø:BAAALAAECgYIBwAAAA==.Neit:BAAALAADCgYIBgAAAA==.Nepheline:BAAALAADCgYICAAAAA==.Neskos:BAAALAADCggICAAAAA==.Nestÿ:BAAALAAECgMIBQAAAA==.',Nh='Nhaemas:BAAALAADCgcIBwAAAA==.',Ni='Niarkkrain:BAAALAAECgUICAAAAA==.Nihal:BAAALAAECgYIDgAAAA==.Nikaia:BAAALAADCggIEgABLAAECgYICgABAAAAAA==.Nikita:BAAALAADCggICAABLAAECgMIBwABAAAAAA==.Nilamê:BAAALAAECgEIAQAAAA==.Nithrarith:BAABLAAECoEUAAIPAAcI7CBWDQCgAgAPAAcI7CBWDQCgAgAAAA==.',No='Notimetodie:BAAALAADCggIDwABLAAECgUICgABAAAAAQ==.Nouchko:BAAALAADCgYIBwAAAA==.Noux:BAAALAADCggICAAAAA==.Novaxio:BAAALAADCgYIBgAAAA==.Noxic:BAAALAAECgYIDwAAAA==.Noxicocham:BAAALAADCgUIBQAAAA==.',Ny='Nyrelith:BAAALAAECgcIDwAAAA==.',['Né']='Néfrann:BAAALAAECgcIDAAAAA==.Néostakhan:BAAALAADCgcIBwAAAA==.',['Në']='Nëphary:BAAALAADCggICAAAAA==.',['Nø']='Nønøw:BAAALAAECgMIAwAAAA==.Nønøww:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Nøurs:BAAALAAECggIEgAAAA==.',Oc='Ocfed:BAAALAADCgYIEAAAAA==.',Oe='Oeildeloup:BAAALAAECgQIBQAAAA==.',Ok='Okaï:BAAALAAECgMIBAAAAA==.',Ol='Olyna:BAAALAADCgcIDQAAAA==.',On='Onesime:BAACLAAFFIEHAAISAAQIjR6NAQAZAQASAAQIjR6NAQAZAQAsAAQKgSAAAhIACAimJYEAAGMDABIACAimJYEAAGMDAAAA.Onesimonk:BAAALAAFFAEIAgABLAAFFAQIBwASAI0eAA==.',Or='Ordus:BAAALAADCgcIBwAAAA==.Oreca:BAAALAAECgUIBQAAAA==.Orihimée:BAAALAAECgcIEAAAAA==.',Ou='Ouzou:BAAALAAECgYIBgAAAA==.',Pa='Paladan:BAAALAAECgUIBQAAAA==.Palagrind:BAAALAAECgIIAgAAAA==.Palath:BAAALAAECggIDQAAAA==.Pamhalpert:BAAALAADCgcIDwAAAA==.Pandoru:BAABLAAECoEUAAMZAAcIoB8AEgCLAgAZAAcIoB8AEgCLAgAaAAIIiw4IKQBKAAAAAA==.Panoramîss:BAAALAAECgMIAwAAAA==.Parcevaux:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.Pathrocle:BAAALAADCgUIBQAAAA==.',Pe='Peko:BAAALAADCggICAAAAA==.Pekø:BAAALAAECgMIAwAAAA==.',Pi='Pilaf:BAAALAAECgcIDgAAAA==.Piloufä:BAAALAAECgcIDgAAAA==.Pipolipop:BAAALAAECgIIAgAAAA==.Pit:BAAALAAECgQIBAAAAA==.Pithy:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Pithyre:BAAALAAECgYIBwAAAA==.',Pl='Planky:BAAALAADCgQIBAABLAADCggIEAABAAAAAA==.',Po='Poiskaille:BAAALAADCgUIBQAAAA==.Polochon:BAAALAADCgUIBQAAAA==.',Pr='Prakha:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.Prayførme:BAAALAAECgYICwAAAA==.Prepusienne:BAAALAAECgMIBAAAAA==.Prev:BAAALAADCggICAABLAAECggIFQAFAPUcAA==.Previously:BAAALAAECgMIAwABLAAECggIFQAFAPUcAA==.Prêtra:BAAALAADCgIIAgAAAA==.Prïth:BAAALAAECgYIDwAAAA==.',Pu='Pulco:BAAALAADCggIEAAAAA==.',Pw='Pwic:BAAALAAECgEIAQAAAA==.',Py='Pyko:BAAALAAECgYICAAAAA==.Pyradk:BAAALAAECggIDQAAAA==.Pyrealaum:BAAALAAECgEIAQAAAA==.Pyritium:BAAALAAECgcIDAAAAA==.Pytire:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',['Pä']='Pändoro:BAAALAADCggIDgAAAA==.',['Pé']='Péondelamort:BAABLAAECoEVAAIbAAgIeR40AwDKAgAbAAgIeR40AwDKAgAAAA==.Pérelachaise:BAAALAAECgQICQAAAA==.',Ra='Rabaraï:BAAALAAECgEIAQAAAA==.Rachmaninaar:BAAALAADCggIDwAAAA==.Ragekub:BAAALAADCgcIBwAAAA==.Ramassmiette:BAAALAADCggIEgAAAA==.Rava:BAAALAAECgMIBQABLAAECgYIEgABAAAAAA==.Ravênz:BAAALAAECgQIBQAAAA==.',Re='Redblar:BAABLAAECoEXAAIcAAgIpiStAQBhAwAcAAgIpiStAQBhAwAAAA==.Renawj:BAAALAADCgcIBwAAAA==.Retuu:BAAALAAFFAIIAgAAAA==.Revølutiøn:BAAALAAECgYICQAAAA==.',Rh='Rhaenerys:BAAALAADCgcIBwAAAA==.',Ri='Rigoloss:BAAALAAECgQIBwAAAA==.Rikhu:BAAALAAECgMIBQAAAA==.Ripcry:BAAALAAECgMIBQAAAA==.Riujin:BAAALAAECgUIBgAAAA==.',Ro='Roon:BAABLAAECoEXAAIdAAgIUCO/AQA7AwAdAAgIUCO/AQA7AwAAAA==.Rotkäppchen:BAAALAADCgcIDAAAAA==.Routmoute:BAAALAAECgQIBQAAAA==.',Ru='Rubÿ:BAAALAADCggIDwAAAA==.Ruzio:BAAALAADCggIFgAAAA==.',Ry='Ryce:BAAALAADCgcIBwAAAA==.Ryjin:BAAALAAECgEIAQAAAA==.Ryller:BAAALAADCggIEAAAAA==.',['Ré']='Résolute:BAAALAADCgEIAQAAAA==.',['Rø']='Røbïndesbøïs:BAAALAADCggICAAAAA==.',['Rû']='Rûfüs:BAAALAAECgYICwAAAA==.',['Rÿ']='Rÿuga:BAAALAAECgcICAAAAA==.Rÿzen:BAAALAAECgcIEgAAAA==.',Sa='Safyrraa:BAAALAADCggIEAAAAA==.Salià:BAAALAAECgQIBwAAAA==.Samaels:BAAALAADCgEIAQABLAAECgIIAgABAAAAAA==.Sanubia:BAAALAADCgMIAwABLAAECgMIBQABAAAAAA==.Sanyia:BAAALAAECgYICwAAAA==.Saorhiel:BAAALAADCgUIBgAAAA==.Saossî:BAABLAAECoEUAAIeAAcIwh3ZDABoAgAeAAcIwh3ZDABoAgAAAA==.Sapâra:BAAALAADCgIIAgABLAAECgYIBwABAAAAAA==.Sapära:BAAALAAECgYIBwAAAA==.Sarkage:BAAALAAECgYIDwAAAA==.Saræ:BAAALAAECgYICgAAAA==.Sarælï:BAAALAAECgMIAwAAAA==.Sathanass:BAAALAADCggIEQAAAA==.',Sc='Schweppes:BAAALAAECgQIBgAAAA==.Scrùb:BAACLAAFFIEFAAIfAAMIzw6+AADcAAAfAAMIzw6+AADcAAAsAAQKgRgAAh8ACAjgHQ4DALICAB8ACAjgHQ4DALICAAAA.',Se='Seiley:BAAALAADCgcIDQAAAA==.Selandris:BAAALAAECgcIDAAAAA==.Seska:BAAALAADCggICAAAAA==.',Sh='Shadh:BAAALAAECgYIDAABLAAFFAMIBQATAKwNAA==.Shadk:BAACLAAFFIEFAAITAAMIrA3nAwDxAAATAAMIrA3nAwDxAAAsAAQKgRgAAxMACAi3HycMAM0CABMACAiaHicMAM0CABsACAgyFiMJANgBAAAA.Shhuntor:BAAALAAECgYICwAAAA==.Shibi:BAAALAAECgYIBgAAAA==.Shiha:BAAALAADCgcIBwAAAA==.Shizune:BAAALAADCggICAABLAAECggIFQAGAB4cAA==.Shoapan:BAAALAADCgEIAQAAAA==.Shoksy:BAAALAAFFAIIAgAAAA==.Showmmer:BAAALAADCgUIBQAAAA==.Shäreg:BAAALAAECgYIDAAAAA==.',Si='Sikuy:BAAALAADCgcICgAAAA==.Silins:BAAALAAECgUIBwAAAA==.Silvercrøw:BAAALAADCgcIBwAAAA==.Silverio:BAAALAAECgEIAQAAAA==.Silvyan:BAAALAAECgUICgAAAA==.',Sk='Skötch:BAAALAAECgQIBwAAAA==.',So='Sojagoons:BAAALAAECgUICgAAAA==.Solariel:BAABLAAECoEUAAIHAAcIUxh9DQDJAQAHAAcIUxh9DQDJAQAAAA==.Soleîlla:BAAALAADCgYICwAAAA==.Songfou:BAAALAADCgUIBQAAAA==.Soohee:BAABLAAECoEXAAMgAAgIshJIAwAYAgAgAAgIshJIAwAYAgAcAAYI1A+mLABMAQAAAA==.Soubaud:BAAALAADCgMIBQAAAA==.Soupäpe:BAAALAAECgYIBgAAAA==.',Sp='Spira:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Spiritum:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.Spyronéo:BAAALAADCgcIDQAAAA==.Spïz:BAAALAADCggIDwAAAA==.Spôwny:BAAALAAECgUIBgAAAA==.',St='Staniss:BAAALAAECgIIBAAAAA==.Strycke:BAAALAADCggICAAAAA==.',Su='Sunaeki:BAAALAADCgQIBAABLAAECgcIDwABAAAAAA==.',Sy='Syvhix:BAABLAAECoEVAAIhAAgIeyQIAQBSAwAhAAgIeyQIAQBSAwAAAA==.',['Sâ']='Sâossî:BAAALAADCgYIBgAAAA==.Sâparâ:BAAALAADCgYIBgABLAAECgYIBwABAAAAAA==.Sâpä:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.',['Sð']='Sðra:BAAALAAECgcIDwAAAA==.',['Sø']='Søfly:BAAALAAECgcIDAAAAA==.',Ta='Talamaskaa:BAAALAADCgMIAwAAAA==.Tanelas:BAAALAAECgQIBgAAAA==.Tataràchelle:BAACLAAFFIEFAAMXAAMIiBHgBQClAAAWAAIIWg8/CQCtAAAXAAIIVQ/gBQClAAAsAAQKgRgABBYACAhTHx4JAM4CABYACAjQHh4JAM4CABcABQi/G0UbAIgBABgAAgg7EK8dAJkAAAAA.',Te='Tellarra:BAAALAADCgcIBwAAAA==.Tenshîn:BAAALAAECgYIDAAAAA==.',Th='Thoronys:BAAALAAECgYIDwAAAA==.Throm:BAAALAADCggIDwAAAA==.Thunddss:BAAALAADCggICwAAAA==.Thunderdoom:BAAALAAECggICAAAAA==.Thãloula:BAAALAAECgMIBgAAAA==.Thémistocle:BAAALAADCggIDwAAAA==.',Ti='Tigus:BAAALAAECgcIDwAAAA==.Timerunzed:BAAALAAECggICwAAAA==.Timetodemon:BAAALAADCgIIAgAAAA==.Tiralyon:BAAALAAECgMIBAAAAA==.',To='Toci:BAAALAAECgQIBQAAAA==.Tohil:BAAALAAECgIIAwAAAA==.Tollyy:BAAALAAECggICAAAAA==.Tomohé:BAABLAAECoEXAAIIAAgIeCC7CADiAgAIAAgIeCC7CADiAgAAAA==.Toothless:BAAALAAECgUIBQAAAA==.Tordrago:BAAALAADCggICAAAAA==.Torgrïm:BAAALAADCgcICwAAAA==.Totemic:BAAALAAECgcIDgAAAA==.Toufiksolide:BAAALAADCggICAAAAA==.',Tr='Traham:BAAALAADCgEIAQAAAA==.Tressange:BAAALAAECgMIBAAAAQ==.Trizgal:BAAALAADCgcIDQAAAA==.Tronjoly:BAAALAAECgIIAgAAAA==.Tréssàaa:BAAALAADCgcICAAAAA==.',Tu='Turakam:BAAALAADCgcIEAAAAA==.Tutti:BAAALAADCggIFwAAAA==.',Ty='Tysonaar:BAAALAADCgcIBwAAAA==.',Ue='Uesugi:BAAALAAECgQIBAAAAA==.',Uu='Uurcz:BAAALAADCgcIBwAAAA==.',Va='Vakarïan:BAAALAAECggIEwAAAA==.Valefore:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Vallae:BAAALAADCggIEQAAAA==.Varyon:BAAALAAECgIIBAAAAA==.Varzhak:BAAALAAECgUICgAAAA==.Vaughnaar:BAAALAADCggIEAAAAA==.',Ve='Vedric:BAABLAAECoEUAAIiAAcICiW+AAD3AgAiAAcICiW+AAD3AgAAAA==.Velkarnis:BAAALAADCgEIAQAAAA==.Velshàroon:BAAALAAECgYIBwAAAA==.Venaira:BAAALAADCggIDgAAAA==.Vespasien:BAAALAADCgYIBgAAAA==.',Vh='Vhagar:BAAALAAECgEIAQAAAA==.',Vi='Viøla:BAABLAAECoEVAAMXAAgIDR8+CgAoAgAXAAYIfiA+CgAoAgAWAAYIaxi2IwCxAQAAAA==.',Vl='Vlaad:BAAALAAECgYIEAAAAA==.Vladoux:BAAALAADCgQIBAAAAA==.',Vo='Voltefesse:BAAALAAECgIIBAAAAA==.',['Vä']='Vähiné:BAAALAADCggICAABLAADCggIDQABAAAAAA==.Välorian:BAAALAADCgMIAwAAAA==.',['Vé']='Végë:BAAALAAECgYICQAAAA==.',['Vî']='Vînce:BAAALAAECgQIBAAAAA==.',Wa='Warth:BAAALAAECggICQABLAAECggIDQABAAAAAA==.',We='Weedwàlker:BAAALAAECgMIAwAAAA==.Weralyon:BAAALAADCgcIDQAAAA==.Wesker:BAACLAAFFIEFAAIKAAMI4httAgARAQAKAAMI4httAgARAQAsAAQKgRgAAgoACAhkH9sGAM0CAAoACAhkH9sGAM0CAAAA.',Wo='Wolfuryo:BAAALAAECgMIBQAAAA==.Wolok:BAAALAAECgYICwAAAA==.Woodenne:BAAALAAECgUICgAAAA==.Worbak:BAAALAAECgYICAAAAA==.Wowsapik:BAAALAADCgcIBgAAAA==.',Wr='Wraithlock:BAABLAAECoEUAAMXAAcI9RW5EwDAAQAXAAYITBe5EwDAAQAWAAEI6g0XaQA6AAAAAA==.Wraken:BAAALAADCgcIDgAAAA==.',['Wï']='Wïnka:BAAALAAECgEIAgAAAA==.',Xa='Xaman:BAAALAAECgIIBAAAAA==.Xaso:BAAALAADCgcICwAAAA==.Xavno:BAAALAADCgIIAgAAAA==.Xaï:BAAALAADCggIDgAAAA==.',Xe='Xehanort:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.',Xn='Xnezuko:BAAALAAECgMIBQAAAA==.',Xo='Xonï:BAAALAADCggIDQAAAA==.Xorkãlle:BAABLAAECoEUAAILAAYIZCDVFAAeAgALAAYIZCDVFAAeAgAAAA==.',['Xé']='Xélénia:BAAALAADCgEIAQABLAAECgUIBQABAAAAAA==.',Ya='Yagï:BAAALAAECgYIBgAAAA==.Yamata:BAAALAADCggIDAAAAA==.Yami:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.',Ye='Yed:BAAALAAECgEIAQAAAA==.',Yn='Ynalïa:BAAALAADCggICAAAAA==.',Yt='Yto:BAAALAAECgIIBAAAAA==.Ytoh:BAAALAADCgEIAQAAAA==.',Yu='Yunah:BAAALAADCggIEQABLAAECgMIBQABAAAAAA==.Yunïe:BAAALAAECgIIAgAAAA==.Yuthãne:BAAALAAECgIIAgAAAA==.Yuzur:BAAALAADCggIGAAAAA==.',Za='Zanarkand:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Zaraskill:BAAALAAECgUICgAAAQ==.Zaryndruid:BAABLAAECoEXAAIeAAgIHiHYBQD3AgAeAAgIHiHYBQD3AgAAAA==.',Ze='Zekosgringos:BAAALAADCggICAAAAA==.Zenokal:BAAALAADCggICAAAAA==.Zephira:BAAALAAECgMIBgAAAA==.Zeta:BAAALAADCgcIBwAAAA==.',Zl='Zlathan:BAAALAAECgUICgAAAA==.',Zo='Zobye:BAAALAADCgQIBAAAAA==.Zodzog:BAAALAADCgcIBwAAAA==.Zoelie:BAAALAADCggICQAAAA==.Zozoe:BAAALAADCggICAAAAA==.Zozoteuze:BAAALAAECgcIDgAAAA==.',Zu='Zulrohk:BAAALAADCggIFgABLAAECggIFQAGAB4cAA==.',['Zô']='Zôulette:BAAALAADCggIBwAAAA==.',['Ão']='Ãodus:BAAALAADCgcIBwAAAA==.',['Æy']='Æyø:BAAALAAECgcICQAAAA==.',['Èr']='Èrysham:BAABLAAECoEXAAIMAAgI5x/HBgAAAwAMAAgI5x/HBgAAAwAAAA==.',['Én']='Énéä:BAAALAAECgcIEQAAAA==.',['Êt']='Êther:BAAALAADCggIEQAAAA==.',['Ïl']='Ïldianä:BAAALAAECgYICwAAAA==.',['Ða']='Ðantesk:BAAALAAECgYIBwAAAA==.',['Ôr']='Ôrrorin:BAAALAAFFAIIAgAAAA==.',['Ør']='Øruraundø:BAAALAADCgMIAwAAAA==.',['ßr']='ßrennos:BAAALAADCggIDgAAAA==.',['ßw']='ßwondimanche:BAAALAADCgcIDQABLAADCggICQABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end