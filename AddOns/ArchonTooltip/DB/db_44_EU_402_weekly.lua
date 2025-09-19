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
 local lookup = {'Unknown-Unknown','Mage-Frost','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Mage-Arcane','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Druid-Balance','Priest-Holy','DemonHunter-Vengeance','Shaman-Restoration','Paladin-Protection','Warrior-Fury','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','DemonHunter-Havoc','Shaman-Enhancement','Warlock-Affliction',}; local provider = {region='EU',realm='Arthas',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abbey:BAAALAADCggIFwAAAA==.',Ac='Actaeon:BAAALAADCggICAAAAA==.',Ad='Adèron:BAAALAAECgMIBAAAAA==.',Ae='Aeis:BAAALAADCgIIAgAAAA==.Aeris:BAAALAAECgYICgAAAA==.Aeron:BAAALAADCgYIBgAAAA==.',Ai='Aim:BAAALAADCggICAAAAA==.Aimshotwayne:BAAALAAECgYIBgAAAA==.Aimé:BAAALAADCggIDQAAAA==.',Al='Albituplenna:BAAALAADCggIFgABLAAECgMIBAABAAAAAA==.Almahunt:BAAALAAECgUIDwAAAA==.Alnoctur:BAAALAAECgEIAgAAAA==.Alx:BAAALAADCggICAAAAA==.',Am='Amane:BAAALAAECgYIBgAAAA==.Amaterasù:BAAALAAECgQIBAAAAA==.Amilyn:BAAALAAECgYIDwAAAA==.',An='Andriona:BAAALAAECgMIAQAAAA==.Angharradh:BAAALAAECgMIBwAAAA==.Aniwe:BAAALAADCgcICgAAAA==.Annikkí:BAAALAADCgcIBQAAAA==.Antillia:BAAALAAECgEIAQAAAA==.',Ar='Arash:BAAALAAECgIIAwAAAA==.Aratol:BAAALAAECgcIDwAAAA==.Arboreus:BAAALAAECgMIBAAAAA==.Ardalâ:BAAALAADCgUIBQAAAA==.Aretia:BAAALAADCggICAAAAA==.Aryã:BAAALAADCggICAAAAA==.',As='Asa:BAAALAAECgcIEgAAAA==.Askannøn:BAABLAAECoESAAICAAgIqiDFBQCeAgACAAgIqiDFBQCeAgAAAA==.Asot:BAAALAADCggIFwAAAA==.Aspire:BAAALAAECgUIAgAAAA==.Astares:BAAALAADCgQIBAAAAA==.Astari:BAAALAADCggIDwAAAA==.Astarya:BAAALAAECgQIBgAAAA==.',At='Atarya:BAAALAADCgcIDgAAAA==.Atero:BAABLAAECoEVAAIDAAgI4xkoCAD1AQADAAgI4xkoCAD1AQABLAAFFAEIAQABAAAAAA==.Atheon:BAAALAADCggICAAAAA==.Atraf:BAAALAAECgYIDAAAAA==.Atricía:BAAALAAECgQIBAAAAA==.',Au='Ausgemampft:BAAALAADCgQIBAAAAA==.',Ax='Aximant:BAAALAADCgMIAwAAAA==.',Ay='Ayariel:BAAALAAECgYICwAAAA==.',Az='Azghula:BAAALAAECgQIBAAAAA==.Azhora:BAAALAADCggIFwAAAA==.',Ba='Backstabbath:BAAALAADCgYIBgAAAA==.Baltazarin:BAAALAADCggIDwAAAA==.Baraqel:BAAALAAECgMIAwAAAA==.',Be='Beatik:BAAALAAECggICAAAAA==.Bellatrìx:BAAALAAECgcIDQAAAA==.',Bi='Bibbidi:BAABLAAECoEaAAMEAAgI6yGtDQD+AQAEAAUICyOtDQD+AQAFAAQIyh1sMwBOAQAAAA==.',Bl='Blacknîghts:BAAALAAECggICAAAAA==.Bladingwayne:BAAALAADCgMIAwAAAA==.Bleed:BAAALAAECggIDQAAAA==.Bleghblade:BAAALAAECgMIAQAAAA==.Blinky:BAAALAAECggIEgAAAA==.Blueberryr:BAAALAAECgEIAQAAAA==.Bluemchen:BAAALAAECgYIDQAAAA==.',Bo='Bogenbärbel:BAAALAADCggIDwAAAA==.Boi:BAAALAADCgcIBwAAAA==.Bomaru:BAAALAAECgYICgAAAA==.Boombang:BAAALAAECgQIBgAAAA==.Boomchickawa:BAAALAAECgcICwAAAA==.',Br='Bradaswarri:BAAALAADCgMIAwAAAA==.Brasak:BAAALAAECgYICQAAAA==.Bratti:BAAALAAECgQIBAAAAA==.Bre:BAAALAADCgUIBgAAAA==.Brenntatos:BAABLAAECoEXAAMGAAgI9SEXCQD5AgAGAAgI9SEXCQD5AgACAAUIshKcIwAmAQAAAA==.Brewzzers:BAAALAADCgYIBgAAAA==.Bricktamland:BAAALAADCgcIDwAAAA==.Brightblade:BAAALAADCggICwAAAA==.Brizzlina:BAAALAAECggICAAAAA==.Brobert:BAAALAAECgEIAQAAAA==.Brumblebee:BAAALAADCgcICAAAAA==.Brôly:BAAALAADCgQIBAAAAA==.',Bu='Buenoellsen:BAAALAADCgIIAgAAAA==.Burnislav:BAAALAADCgYIBgABLAADCgYIDAABAAAAAA==.Burnix:BAAALAADCgcICQAAAA==.',['Bé']='Béatríx:BAAALAAECgYIDAAAAA==.',['Bí']='Bígmamma:BAAALAAECgEIAQAAAA==.',['Bø']='Bøømsläng:BAAALAAECgIIBAAAAA==.',Ca='Calamitas:BAAALAADCggICAAAAA==.Caru:BAAALAAECgYICQAAAA==.Casaru:BAAALAADCggICAAAAA==.Casstiel:BAAALAAECgYIDAAAAA==.Catani:BAAALAADCggIEAABLAAECgcIEQABAAAAAA==.Caydacleave:BAAALAAECgIIAgAAAA==.',Ce='Ceeaser:BAAALAADCgcIDwAAAA==.',Ch='Chali:BAAALAAECgEIAgAAAA==.Chandir:BAABLAAECoEYAAIHAAgIoR2cCwC3AgAHAAgIoR2cCwC3AgAAAA==.Chaosclown:BAAALAADCgYIBgAAAA==.Chaospeter:BAAALAAECgQIBgAAAA==.Chelzea:BAAALAADCgMIAwAAAA==.Chilling:BAAALAAECgcIDAAAAA==.Chrónos:BAAALAAECgQIBAAAAA==.Chrôno:BAAALAAECgMIBgAAAA==.',Cl='Clayrah:BAAALAADCggICAAAAA==.Clèo:BAAALAADCggIFwAAAA==.',Co='Colette:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.Corvass:BAAALAAECgIIAgAAAA==.Cownix:BAAALAAECggIDAAAAA==.',Cr='Crankone:BAABLAAECoEVAAMIAAgIlBuMFAB1AgAIAAgIkRuMFAB1AgAJAAIIPCEeJADGAAAAAA==.',Cy='Cyruss:BAAALAAECgYICgAAAA==.',['Cü']='Cüno:BAABLAAECoEWAAIKAAgI8R91BAACAwAKAAgI8R91BAACAwAAAA==.',Da='Daelayn:BAAALAADCgQIBAAAAA==.Daesha:BAAALAAECgcIDwAAAA==.Daevadruj:BAAALAADCggICAAAAA==.Daevenator:BAAALAAECgIIAQAAAA==.Daila:BAABLAAECoEVAAILAAgIaxFxEgDHAQALAAgIaxFxEgDHAQAAAA==.Daimont:BAAALAAECgYICAAAAA==.Dakosi:BAAALAADCgcIBwAAAA==.Dakuun:BAACLAAFFIEFAAIDAAMIUBK4AgCgAAADAAMIUBK4AgCgAAAsAAQKgRkAAgMACAivItABACIDAAMACAivItABACIDAAAA.Dandria:BAAALAAECgYIDwAAAA==.Darkomagnus:BAAALAAECgEIAgAAAA==.Darksouls:BAAALAAECgUIDQAAAA==.',De='Deamonshe:BAAALAAECgcIDwAAAA==.Definitiv:BAAALAADCggIFQAAAA==.Demonjosie:BAAALAADCggIEAAAAA==.Dengø:BAABLAAECoEVAAIMAAgI8BjvGQBDAgAMAAgI8BjvGQBDAgAAAA==.Derhackt:BAAALAAECgIIAgAAAA==.Derprinz:BAAALAAECgMIBgAAAA==.Destorg:BAAALAADCggICAABLAAFFAQICgANAGQeAA==.Devadana:BAAALAAECgQIBgAAAA==.Devellis:BAAALAADCggICAABLAAFFAQICgANAGQeAA==.',Di='Diabolini:BAAALAADCggICAAAAA==.Dialyara:BAAALAAECgEIAgAAAA==.Diekosi:BAAALAADCggIFwAAAA==.Dirtydan:BAAALAADCgcIBwAAAA==.Disease:BAAALAAECgYIBgAAAA==.Distortio:BAAALAAECgQIBwAAAA==.Dizilove:BAAALAAECgQIBgAAAA==.',Dj='Djângo:BAACLAAFFIEFAAIOAAMIiyM9AQAkAQAOAAMIiyM9AQAkAQAsAAQKgRUAAg4ACAi2JhoAAJgDAA4ACAi2JhoAAJgDAAAA.Djângø:BAAALAADCggICAAAAA==.',Dl='Dlakiller:BAAALAAECgcIDQAAAA==.',Do='Donmai:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.Donmöhre:BAAALAAECgQIBgAAAA==.Donvak:BAAALAAECgYICAAAAA==.',Dr='Drachentier:BAAALAAECgYIDQAAAA==.Drachimausi:BAAALAADCggICAAAAA==.Draney:BAAALAAECgYIDQAAAA==.Drow:BAAALAAECgQIBAAAAA==.Drunkenangel:BAAALAAECgUIBQAAAA==.Drusillala:BAAALAADCggIDwAAAA==.Drysift:BAAALAADCgYIBgAAAA==.Drôideka:BAAALAAECgcIEQAAAA==.',Du='Duluric:BAAALAADCggICwAAAA==.Dummdi:BAAALAADCgcIBwAAAA==.',Dw='Dwighti:BAAALAAECgMIBAAAAA==.',['Dä']='Dänku:BAAALAAECgYIDwAAAA==.',['Dê']='Dêltas:BAACLAAFFIEFAAIPAAMI8xr0CACtAAAPAAMI8xr0CACtAAAsAAQKgRkAAg8ACAiyHU4IALYCAA8ACAiyHU4IALYCAAAA.',Ea='Eashi:BAAALAAECgcIDwAAAA==.',Ed='Edkane:BAAALAAECgYICQAAAA==.',Eg='Egalolas:BAAALAAECgMIBQABLAAECgYICAABAAAAAA==.',Ei='Eierlikör:BAAALAADCggIFwAAAA==.',Ek='Ekadnude:BAAALAAECgUIBQAAAA==.',El='Elecebra:BAAALAADCgQIBAAAAA==.Elldoro:BAAALAADCgcICwAAAA==.Eloaine:BAAALAAECgUIBQAAAA==.Elpaplo:BAAALAAECgYIDAAAAA==.',En='Endemonidia:BAAALAAECgYICAAAAA==.Eniac:BAAALAAECggIEAAAAA==.',Ep='Epóna:BAAALAAECgQIBgAAAA==.',Er='Erderwärmung:BAAALAAECgIIAgAAAA==.Erdkern:BAAALAADCgYIBwAAAA==.Erina:BAAALAADCgcIBQAAAA==.Ertai:BAAALAAECgYIDQAAAA==.Erzascarlett:BAAALAAECgcIDQAAAA==.',Es='Esdragon:BAAALAAECgYIBgAAAA==.',Ev='Evelf:BAAALAAECgYICgAAAA==.Evildeath:BAAALAAECggIDwAAAA==.Evoki:BAAALAAECgEIAgAAAA==.Evoxx:BAABLAAECoEVAAIQAAcIpCOsAgDIAgAQAAcIpCOsAgDIAgAAAA==.',Ex='Executephase:BAAALAADCgIIBAAAAA==.Exy:BAAALAAECgYICwAAAA==.',Fa='Falan:BAAALAAECgcIDQAAAA==.Falandriel:BAAALAAECgcIDwAAAA==.Falandrín:BAAALAADCggICAAAAA==.Farye:BAAALAAECgUIBQABLAAECgYIDQABAAAAAA==.Fate:BAAALAADCgYIBgAAAA==.Faydee:BAAALAAECgQIAgAAAA==.',Fe='Februar:BAAALAAECgcIDgAAAA==.Feeara:BAAALAAECgQIBgAAAA==.Fenreal:BAAALAADCggIEAAAAA==.',Fi='Fieber:BAAALAAECgcIEgAAAA==.Fiesefäuste:BAAALAADCggICAAAAA==.Fieserfútzi:BAAALAADCgcICwAAAA==.Fingers:BAAALAAECgYIDQAAAA==.Fioma:BAAALAAECgYIDAAAAA==.Fioña:BAAALAAECgYIBgAAAA==.Firos:BAAALAAECgYIBwAAAA==.Fiõna:BAAALAAFFAIIAgAAAA==.',Fo='Focalor:BAAALAADCgcIBwAAAA==.Forsake:BAAALAADCgcIBwAAAA==.',Fr='Frechstück:BAAALAADCgcIDgAAAA==.Froggie:BAAALAADCgEIAgAAAA==.Frydrake:BAAALAADCggIEAAAAA==.',Ga='Galein:BAAALAAECgQIBAAAAA==.Galen:BAAALAAECgYIBgAAAA==.Ganni:BAAALAAECgMIAwAAAA==.',Ge='Gelya:BAAALAADCgYIBgAAAA==.Getup:BAAALAADCgUIBQAAAA==.',Gh='Ghosti:BAABLAAECoEZAAIGAAgIehwvEQCiAgAGAAgIehwvEQCiAgAAAA==.',Gn='Gnomagus:BAAALAADCgYIBgAAAA==.Gnomtröte:BAAALAADCggIDwAAAA==.',Go='Gorlong:BAAALAADCgcIBwAAAA==.',Gr='Grafgustav:BAAALAAECgMIAwAAAA==.Gragras:BAAALAAECgYIDgAAAA==.Gravius:BAAALAAECgYIDAAAAA==.Grei:BAAALAAECgYIDwAAAA==.Grungie:BAAALAAECgYIEgAAAA==.Gruum:BAAALAAECgYICgAAAA==.Grâutvørnix:BAAALAADCgcIDgABLAADCggICAABAAAAAA==.',Gu='Gubibu:BAAALAAECgYIDAAAAA==.Guckeniòó:BAAALAADCgQIBAAAAA==.',['Gâ']='Gânon:BAAALAADCgMIAwAAAA==.',Ha='Haebbs:BAAALAADCgYIBgAAAA==.Hakunamatatâ:BAAALAADCgEIAQAAAA==.Hakuryo:BAAALAAECgMIAwAAAA==.Hakyu:BAAALAADCgYIBgAAAA==.Haluun:BAAALAADCggICAAAAA==.Handal:BAAALAADCgcIBwAAAA==.Hanslang:BAAALAAECgQICAAAAA==.Hasselhuf:BAAALAADCggICAAAAA==.Hasspelz:BAAALAADCggICAAAAA==.Hawnspfaab:BAAALAADCgQIBAAAAA==.',He='Herrmannelig:BAAALAAECgMIAwAAAA==.Heyalde:BAAALAAECgMIAwAAAA==.',Hi='Himejima:BAAALAAECgUIBgAAAA==.Hisori:BAAALAAECgUIBwAAAA==.',Hl='Hlidaale:BAAALAAECgYIDQABLAAECgcIEAABAAAAAA==.',Ho='Hondai:BAAALAAECgEIAQAAAA==.',Hr='Hreaper:BAAALAAECgYIBgAAAA==.',Hu='Hulicea:BAAALAADCggIFAAAAA==.Humphry:BAAALAAECgIIAgAAAA==.Huntaufsherz:BAAALAADCggICQAAAA==.Huntirix:BAAALAAECgYICwAAAA==.Huntyah:BAAALAAECgYIBgAAAA==.',Hy='Hyperbruh:BAAALAAECgYIBQAAAA==.',['Hä']='Härri:BAAALAADCggICAAAAA==.',Ia='Iausig:BAAALAAECgYICQAAAA==.',Ic='Icemân:BAAALAAECgYICwAAAA==.',Ik='Ikaru:BAAALAAECgQIBAAAAA==.Ikunei:BAAALAADCgcIBwAAAA==.',Im='Immortal:BAAALAAECgMIAwAAAA==.',In='Infex:BAAALAAECgYIEAAAAA==.Inozuko:BAABLAAECoEVAAIRAAgIXRzuCgB4AgARAAgIXRzuCgB4AgAAAA==.Insànè:BAAALAAECgIIAgAAAA==.',Is='Isidion:BAAALAAECgMIBQAAAA==.Isiluu:BAAALAAECgQIBgAAAA==.',It='Iteoms:BAAALAAECgcIEQAAAA==.Itoslemma:BAAALAAECgYIEQAAAA==.Itouch:BAAALAAECgEIAQAAAA==.',Iz='Izual:BAAALAADCggIDwAAAA==.',Ja='Jackedsal:BAAALAADCggIEAAAAA==.Janisi:BAAALAAECgcIDwAAAA==.Jarnknut:BAAALAADCgcIFAAAAA==.',Jd='Jdscance:BAAALAADCggICAAAAA==.',Je='Jezariael:BAAALAADCggIEAAAAA==.',Ji='Jinxmydings:BAAALAAECgYIBAAAAA==.',Jo='Jodah:BAAALAADCggIEwAAAA==.Josiferna:BAAALAADCggICAAAAA==.',Ka='Kace:BAABLAAECoEVAAIRAAcItRgXHwDXAQARAAcItRgXHwDXAQAAAA==.Kadicea:BAAALAAECgIIBwAAAA==.Kadiko:BAAALAADCgYIBgAAAA==.Kairêx:BAAALAAECggIBgAAAA==.Kaishu:BAAALAAECgMIAwAAAA==.Kalameet:BAAALAAECgYICAAAAA==.Kallbo:BAAALAADCggICAAAAA==.Karifex:BAAALAAECgIIAwAAAA==.Kasperle:BAAALAAECgIIAwAAAA==.',Ke='Keepêr:BAAALAAECgcIDwAAAA==.Kepano:BAAALAAECgIIAgAAAA==.Kerber:BAAALAAECgQIBgAAAA==.Kernson:BAAALAAECgMIBQAAAA==.Kerzensturm:BAAALAAECgYIDQAAAA==.',Kh='Khalja:BAAALAAECgQICQAAAA==.',Ki='Ki:BAAALAADCgcIDQAAAA==.Killaer:BAAALAADCgQIBAAAAA==.',Ko='Kosella:BAAALAADCggIEAABLAADCgcIBwABAAAAAA==.',Kr='Krifex:BAAALAADCgYIBgAAAA==.Kriganus:BAAALAADCgcICAAAAA==.Krockett:BAAALAAECgYICQAAAA==.Kronoth:BAAALAAECgYIDwAAAA==.Kruschpak:BAAALAADCggICAAAAA==.',Ky='Kyami:BAAALAAECgMIAwAAAA==.Kyisira:BAAALAADCgcIBwAAAA==.',['Kü']='Kürbiis:BAAALAAECgYIDwAAAA==.',['Kÿ']='Kÿra:BAAALAAECgUICQAAAA==.',La='Larifari:BAAALAAECgEIAQAAAA==.Laughing:BAAALAAECgYIDQAAAA==.Laxara:BAAALAAECgQIBQAAAA==.',Le='Ledun:BAAALAAECgEIAgAAAA==.Lesharo:BAAALAAECgEIAQAAAA==.Lethrá:BAAALAAECggICQAAAA==.Levìna:BAAALAADCgcIBwAAAA==.',Li='Lilalime:BAAALAAECgUIDgAAAA==.Lilisofia:BAAALAAECgQIBgAAAA==.Linnëa:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.Linvala:BAAALAADCgYIBgAAAA==.Liq:BAAALAAECgEIAQAAAA==.Lisdrya:BAAALAADCggICAAAAA==.Livv:BAAALAADCggIDQAAAA==.',Lo='Locktirix:BAAALAADCgYIBgAAAA==.Lousindra:BAAALAAECgYIDwAAAA==.Loxley:BAAALAADCggIDAAAAA==.',Lu='Ludwig:BAAALAAFFAEIAQABLAAFFAMIBQASAHsPAA==.Lugy:BAAALAADCgYIDAAAAA==.Lunariia:BAAALAAECgcIEQAAAA==.Lunariá:BAAALAAECgcICgABLAAECggIFQARAF0cAA==.',Ly='Lyin:BAAALAAECgcIDQAAAA==.Lynna:BAABLAAECoEXAAITAAgINSFKBQAjAwATAAgINSFKBQAjAwAAAA==.Lyrandria:BAAALAAECgMIBQAAAA==.Lysinar:BAAALAADCggIDwAAAA==.Lyviana:BAAALAAECgYIBgABLAAECggIFQALAGsRAA==.',['Lí']='Líght:BAAALAADCgQIAwAAAA==.Línglîng:BAAALAADCgQIBAAAAA==.',['Lî']='Lîandra:BAAALAADCgcIBwAAAA==.',['Ló']='Lóup:BAAALAADCgcIFAABLAAECgYIDAABAAAAAA==.',['Lú']='Lúpâ:BAAALAAECgYICAAAAA==.',Ma='Mababy:BAAALAAECgcIEgAAAA==.Macragge:BAAALAADCggIAgAAAA==.Magikain:BAAALAADCgMIAwAAAA==.Magiknight:BAAALAAECgMIBQAAAA==.Magnorr:BAAALAADCggICAABLAAFFAEIAQABAAAAAA==.Mahtatis:BAAALAADCgEIAQAAAA==.Malacai:BAAALAADCggICAAAAA==.Maldei:BAACLAAFFIEKAAINAAQIZB74AACYAQANAAQIZB74AACYAQAsAAQKgRcAAg0ACAgnJu4AAHcDAA0ACAgnJu4AAHcDAAAA.Mampff:BAAALAADCgcICQAAAA==.Mandra:BAAALAAECgMICAABLAAECgYICAABAAAAAA==.Maninmirror:BAAALAADCgUIBQAAAA==.Mapalâ:BAAALAAECgQIBAABLAAECgcIEgABAAAAAA==.Marabou:BAAALAAECgEIAgAAAA==.Maramarie:BAAALAADCggIDwAAAA==.Maramarîe:BAAALAADCggIEAAAAA==.Maridyan:BAAALAADCgYIBgAAAA==.Mariemara:BAAALAADCggIFgAAAA==.Marthok:BAAALAAECgMIAwAAAA==.Marylittle:BAAALAAECgcIDAAAAA==.Materyaga:BAAALAADCggIDwAAAA==.Mathaaesh:BAAALAAECgIIAgABLAAECgYICQABAAAAAA==.Matirix:BAAALAAECgUIBgAAAA==.Matoffel:BAAALAAECggIBwAAAA==.Matrus:BAAALAADCgYIBgAAAA==.Maximalni:BAAALAADCgYIBgABLAADCgcICQABAAAAAA==.Mayla:BAAALAAECgcIEQAAAA==.',Mc='Mcdk:BAAALAAECgYIDwAAAA==.',Me='Mellisandre:BAAALAADCggICAABLAAECgUIBQABAAAAAA==.Meluschka:BAAALAADCgEIAQAAAA==.Menatos:BAAALAADCggIEAAAAA==.Mensor:BAAALAADCgQIBAAAAA==.Mesami:BAAALAADCgcIBwAAAA==.',Mh='Mhilo:BAAALAADCgcIAgAAAA==.',Mi='Mickdagger:BAAALAAECgEIAQAAAA==.Mickeydin:BAAALAAECggIDgAAAA==.Mighty:BAAALAAECgcICgABLAAECggICgABAAAAAA==.Migome:BAAALAADCgcIBwAAAA==.Mikarior:BAAALAAECgcIDAAAAA==.Milo:BAAALAADCgQIBAAAAA==.Minimilky:BAAALAADCgcIBwAAAA==.Minischamy:BAAALAADCggIEAAAAA==.Mirail:BAAALAADCgUIBQABLAAECgYIBwABAAAAAA==.Missduttfish:BAAALAADCggICAAAAA==.',Mo='Monshana:BAAALAAECgYICwAAAA==.Moonshîne:BAAALAADCgYIDAAAAA==.Moquí:BAAALAADCggIDAAAAA==.Mordante:BAAALAAECgEIAgAAAA==.Mortifix:BAAALAADCggICAAAAA==.Mossi:BAAALAADCggICAAAAA==.Mostacho:BAAALAAFFAEIAQAAAA==.Mostachu:BAAALAADCggICAABLAAFFAEIAQABAAAAAA==.',['Má']='Mátze:BAAALAAECgMIAwAAAA==.',['Mê']='Mêrcury:BAAALAAECgUICQAAAA==.',['Mî']='Mîssmôshalot:BAAALAAFFAIIAgAAAA==.',Na='Nachschlag:BAAALAADCggICAAAAA==.Nachtkrieger:BAAALAADCgUIBQABLAADCggIDAABAAAAAA==.Nalula:BAAALAADCgYIBgAAAA==.Namtilia:BAAALAAECgYIDQAAAA==.Napfkuchen:BAAALAADCggIDwAAAA==.Natille:BAAALAADCggIDAAAAA==.Naîltaz:BAAALAAECgUIBAAAAA==.',Ne='Nebeshima:BAAALAAECgYIDAAAAA==.Nedras:BAAALAAECggICgAAAA==.Needmuchdope:BAAALAAECgYICgAAAA==.Neftesare:BAAALAAECgQIBwAAAA==.Nelesan:BAABLAAECoEXAAIRAAgIbh9sBgC3AgARAAgIbh9sBgC3AgAAAA==.Nemm:BAAALAADCgEIAQAAAA==.Neoline:BAAALAADCgcIDAAAAA==.Nesuma:BAAALAAECgEIAQAAAA==.',Ni='Nihilo:BAAALAAECgYICgAAAA==.Nijuu:BAABLAAECoEWAAIUAAgI5Bt5DACaAgAUAAgI5Bt5DACaAgAAAA==.',No='Nogma:BAAALAADCgcIBwAAAA==.Nogmer:BAAALAAECgQIBgAAAA==.Nolicia:BAAALAAECgcIEAAAAA==.',Ny='Nyrral:BAAALAADCggICAAAAA==.Nysim:BAAALAADCggICAABLAAECgcIDwABAAAAAA==.Nyxi:BAAALAADCggIDQAAAA==.',Od='Odí:BAAALAAECgIIAgAAAA==.',Og='Ogni:BAAALAADCgcICgAAAA==.',Om='Omaru:BAAALAAECgcIDQAAAA==.',Or='Ore:BAAALAADCggICAAAAA==.Orin:BAAALAAECgQIBAAAAA==.',Ot='Otz:BAAALAADCggIEAAAAA==.',Pa='Paleandro:BAAALAADCggICQAAAA==.Pam:BAAALAADCgEIAQAAAA==.Pandacat:BAAALAADCgIIAgAAAA==.Pandax:BAAALAAECgcIEAAAAA==.',Pe='Petzibär:BAAALAAECgYICQAAAA==.',Ph='Phosphora:BAAALAAECgMIAwAAAA==.',Pi='Pillow:BAAALAAECgcIDwAAAA==.Pinkymoon:BAAALAADCgQIBAAAAA==.Pixiee:BAAALAAECggIDQAAAA==.',Pr='Praylene:BAAALAADCggICAAAAA==.Primed:BAAALAAECgcIDwAAAA==.Procco:BAAALAAECgcIEwAAAA==.',Ps='Psey:BAAALAAECggIEAAAAA==.Psiana:BAAALAAECgcIDQAAAA==.',Pu='Puc:BAAALAADCgYIBgAAAA==.Pudena:BAAALAADCggICAABLAAECggIFAALAEYWAA==.Pudu:BAABLAAECoEUAAILAAgIRhaoBwBfAgALAAgIRhaoBwBfAgAAAA==.',Py='Pyrotechnik:BAAALAAECgYIBwAAAA==.',Qj='Qjiun:BAACLAAFFIEFAAISAAMIew/JAwCCAAASAAMIew/JAwCCAAAsAAQKgRkAAhIACAgOJQ0BAFMDABIACAgOJQ0BAFMDAAAA.',Qu='Quallenfisch:BAAALAADCgUIBQAAAA==.',Ra='Raea:BAAALAADCggICAAAAA==.Raigis:BAAALAADCggIEAAAAA==.Ramok:BAAALAADCgcIEAAAAA==.Ravemaster:BAAALAADCggIDAAAAA==.Ravensei:BAAALAAECgcICQAAAA==.Rayleighd:BAAALAADCgUIBQAAAA==.Razpriest:BAABLAAECoEaAAIPAAgIPyUHAQBbAwAPAAgIPyUHAQBbAwAAAA==.Razvoker:BAAALAAECgYICgAAAA==.',Re='Readyteddy:BAAALAAECgEIAQAAAA==.Reasonable:BAAALAAECgQIBwAAAA==.Regloh:BAAALAAECgcICgAAAA==.Rekz:BAAALAAECgEIAQAAAA==.',Ri='Ric:BAAALAAECggIBAAAAA==.Rikkui:BAAALAAECgIIBAAAAA==.Rizii:BAAALAAECgEIAQAAAA==.',Ro='Rokthar:BAAALAAECgIIAgABLAAECgcIFQARALUYAA==.Ronjarövar:BAAALAADCggICAAAAA==.Rookie:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Ru='Rubi:BAAALAAECgEIAQAAAA==.',Ry='Ryûkû:BAAALAAECgUIBQAAAA==.',['Rá']='Rás:BAAALAADCgYIBgAAAA==.',['Rò']='Ròcky:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.',Sa='Sacrosanctus:BAAALAADCgcIBwAAAA==.Salicía:BAABLAAECoEVAAIVAAcIxB4YBQBJAgAVAAcIxB4YBQBJAgAAAA==.Saltymage:BAAALAAECgEIAQAAAA==.Saltypriest:BAAALAAECgYIDwAAAA==.Saltywarri:BAAALAADCgcIBwAAAA==.Saman:BAAALAADCggICwAAAA==.Sanu:BAAALAADCggICAAAAA==.Saphiresh:BAAALAAECgEIAgAAAA==.Sapientia:BAAALAADCggICAAAAA==.',Sc='Scaris:BAAALAADCgcIDgAAAA==.Schayen:BAAALAADCggICAAAAA==.Schmudd:BAAALAAECgMIBQAAAA==.Schmutzengel:BAAALAAECgEIAQAAAA==.Schwingus:BAAALAAECgMIAwAAAA==.Schwärzulesn:BAAALAADCgcIBwAAAA==.Sco:BAAALAAECgcIDQAAAA==.',Se='Selass:BAAALAAECgcIEgAAAA==.Selcutalus:BAAALAADCgcIBwAAAA==.Sennaqt:BAAALAADCgYIBgAAAA==.Serac:BAAALAAECgUIBgAAAA==.Serafinê:BAAALAADCgcIDQAAAA==.Seranya:BAAALAAECgYIBgAAAA==.Serathp:BAAALAADCgEIAQAAAA==.Seratori:BAAALAAECgMIBAAAAA==.Seyley:BAAALAAECgYIBgABLAAECggIFwARAG4fAA==.',Sh='Shamant:BAAALAAECgUIAgAAAA==.Shikonee:BAAALAAECgQIBgAAAA==.Shôyi:BAAALAAECggICAABLAAECggIFQAWAMggAA==.',Si='Silencewayne:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.Silentscream:BAAALAADCggIFgAAAA==.Silenzio:BAAALAAECgYICgAAAA==.Sinaleria:BAAALAAECgYICAAAAA==.Sinistrata:BAAALAAECgIIAgAAAA==.Sittinbull:BAAALAAECgMICAAAAA==.',Sl='Slexx:BAAALAADCggIDAAAAA==.Sljivovica:BAAALAADCgQIBAABLAADCgcICQABAAAAAA==.',Sn='Snuggí:BAAALAADCggICAAAAA==.',So='Solorioing:BAAALAAECggIEwAAAA==.',Sp='Spook:BAAALAAECgcIBwAAAA==.',Ss='Sskaliert:BAAALAADCgUIBQAAAA==.',St='Stine:BAAALAAECgIIAgAAAA==.Stonehenge:BAABLAAECoEVAAIWAAgIyCD7AgD5AgAWAAgIyCD7AgD5AgAAAA==.Stârlight:BAAALAADCgcIDQAAAA==.Stönks:BAAALAAECgcIEAAAAA==.',Su='Sukkubee:BAAALAAECggICAAAAA==.Susanó:BAAALAAECgIIAgAAAA==.',Sy='Sylvany:BAAALAADCgMIAgAAAA==.Sylvänas:BAAALAAECgIIAgAAAA==.Syrup:BAAALAAECgIIAgAAAA==.',['Sì']='Sìnthòras:BAAALAAECgYIDwAAAA==.',['Sî']='Sîrmoshalot:BAAALAAECgQIBAAAAA==.',['Só']='Sóngoku:BAAALAADCgUIBQAAAA==.',['Sô']='Sôya:BAAALAADCgcIBwAAAA==.',Ta='Taktik:BAAALAAECgYIDQAAAA==.Taldaris:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Tatsuki:BAAALAADCgQIBQAAAA==.',Te='Terrorgnomi:BAAALAAECgcIEwAAAA==.',Th='Thaicurry:BAAALAADCgYIDgAAAA==.Thanischa:BAAALAAECgUICQAAAA==.Thatch:BAAALAAECgMIAwAAAA==.Theforce:BAAALAAECgcICgAAAA==.Themô:BAAALAADCggIFwAAAA==.Thondrar:BAAALAAECgYICgAAAA==.Thorndal:BAAALAAECgIIAgAAAA==.Thorquil:BAAALAAECgIIAgAAAA==.Thunderchonk:BAAALAAECgYICgAAAA==.Thunderrambo:BAAALAAECgYIDQAAAA==.Thærion:BAAALAAECggIBgAAAA==.',Ti='Timonoi:BAABLAAECoEZAAIXAAgI0STVAgBdAwAXAAgI0STVAgBdAwAAAA==.Tingltangl:BAAALAADCgEIAQAAAA==.Tiwelé:BAAALAAECgYIDwAAAA==.',Tj='Tjorvendra:BAAALAAECgIIAgAAAA==.',To='Tolous:BAAALAADCgcIBwAAAA==.Tonkpils:BAAALAADCggIEQAAAA==.Toothless:BAAALAAECgIIBQAAAA==.',Tr='Treegirl:BAAALAADCgcIFAAAAA==.Treestyler:BAAALAAECgYIDAABLAAECggIDgABAAAAAA==.Tryin:BAAALAAECggICAAAAA==.',Tu='Tujani:BAAALAAECggICAAAAA==.',Tz='Tzn:BAAALAAECgYICgAAAA==.',['Tà']='Tàmi:BAAALAAECggIBgAAAA==.',Ub='Ubetrollin:BAAALAADCgYIAgAAAA==.',Ul='Uldastron:BAAALAAECgcIDwAAAA==.',Un='Unai:BAAALAAECgYICQAAAA==.Unholyrambo:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Uniswap:BAAALAAECgQIBgAAAA==.',Ur='Urthodar:BAAALAAECgcIDAAAAA==.Urushihara:BAAALAAECgYICgAAAA==.',Va='Vaeloria:BAAALAADCggIDwABLAAECgYIDQABAAAAAA==.Vagudk:BAAALAADCggICAAAAA==.Vagullion:BAAALAADCggICAAAAA==.Valchaya:BAAALAADCggIEgAAAA==.Valdarim:BAAALAAECgcIEQAAAA==.Valorian:BAAALAADCgYIBgAAAA==.Valyria:BAAALAAECgYICwAAAA==.Varghul:BAAALAAECgIIAgAAAA==.Vartarius:BAABLAAECoEVAAMUAAcIlRw5EQBRAgAUAAcIlRw5EQBRAgAYAAEIEgTiFgA4AAAAAA==.',Ve='Veigos:BAAALAADCgIIAgAAAA==.Velyra:BAAALAAECgIIAgAAAA==.Vereesá:BAAALAADCgcIBwAAAA==.Vermílion:BAAALAAECgMIBAABLAAECggIGgANAJQjAA==.',Vi='Via:BAAALAAECgIIAgAAAA==.Viantia:BAAALAAECgYIDwAAAA==.Victarian:BAAALAADCgYIBgAAAA==.Vielfraß:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Vindujin:BAAALAAECgMIAwAAAA==.Vinoveritass:BAAALAADCggIEAAAAA==.Violá:BAAALAADCggICAAAAA==.Visandre:BAAALAADCgcIBgAAAA==.',Vo='Voidlock:BAAALAAECgUIBgAAAA==.Voxx:BAAALAADCgcICgAAAA==.Voyze:BAAALAAFFAIIAgAAAA==.',Vu='Vulpibär:BAAALAADCggIFgAAAA==.',Vy='Vye:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.',['Vá']='Vánjariá:BAABLAAECoEVAAIFAAcI5ha2GgD6AQAFAAcI5ha2GgD6AQAAAA==.',Wa='Waaynefistu:BAAALAAFFAIIAgAAAA==.Warg:BAAALAAECgcIEwAAAA==.Warthor:BAAALAADCggICwAAAA==.Wasnwarri:BAAALAADCgYIBgAAAA==.',Wi='Wildstylez:BAAALAAECgYIDwAAAA==.Winfury:BAAALAADCgYIBwAAAA==.',Wo='Wolfidine:BAAALAAECgYIDgAAAA==.Wolverín:BAAALAAECgcICgABLAAECgcIDQABAAAAAA==.Wopk:BAAALAAECgYIBgAAAA==.',Xa='Xalaxa:BAAALAADCgIIAgAAAA==.Xantina:BAAALAAECgcIDAAAAA==.',Xe='Xelinas:BAAALAADCgcIBwAAAA==.Xeraton:BAAALAADCgYIBgAAAA==.Xerebus:BAAALAAECgMIBQAAAA==.',Xi='Xianshi:BAAALAAECgEIAQAAAA==.',Xp='Xpsy:BAAALAADCgMIAwAAAA==.',Xv='Xvii:BAAALAAECgIIAgAAAA==.',Ya='Yakirea:BAABLAAECoEVAAIZAAcIYyNNAQDjAgAZAAcIYyNNAQDjAgAAAA==.Yamáto:BAAALAAECgIIAgAAAA==.Yanthir:BAAALAAECgcIDAAAAA==.Yazu:BAAALAAECgEIAQAAAA==.',Ye='Yeri:BAAALAADCgcIBwAAAA==.',Yi='Yikes:BAAALAAECgYIDgABLAAECgcIEAABAAAAAA==.Yinjou:BAAALAADCgUIBQAAAA==.',Yo='Yo:BAAALAADCggIFgAAAA==.Yorak:BAAALAAECgEIAgAAAA==.Yorimoto:BAAALAADCggIEAAAAA==.',Yu='Yumana:BAAALAAECgMIAwAAAA==.Yunanisha:BAAALAAECgYIDwAAAA==.Yuunaa:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.',Yv='Yviene:BAAALAAECgIIAgAAAA==.',Za='Zaarô:BAAALAADCgUIAwAAAA==.Zackí:BAAALAADCgcIBwAAAA==.Zardrasch:BAAALAAECgcICQAAAA==.Zardán:BAAALAADCggICAAAAA==.Zasterdrache:BAAALAAECgMIAwAAAA==.',Ze='Zeppo:BAABLAAECoEaAAQFAAgIfBk5IgC9AQAFAAYIchc5IgC9AQAEAAUIbhPsIgBUAQAZAAEI6gYULgA/AAAAAA==.Zerberker:BAAALAADCggICgAAAA==.',Zi='Zirany:BAAALAAECgEIAQAAAA==.Zizou:BAABLAAECoEaAAINAAgIlCPVAgBEAwANAAgIlCPVAgBEAwAAAA==.',Zo='Zoarter:BAAALAAECgIIBAAAAA==.',Zr='Zránk:BAAALAAECgYIBAAAAA==.',Zu='Zuko:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.Zulan:BAAALAADCgYIBgAAAA==.Zunnizwo:BAAALAAECgcIDQAAAA==.',Zw='Zwobelix:BAAALAAECgcIDQAAAA==.',['Zò']='Zòra:BAAALAAFFAEIAQAAAA==.',['Zü']='Zückerli:BAAALAADCggIFgAAAA==.Zündstück:BAAALAADCggIEQAAAA==.',['Äl']='Älseh:BAAALAAECgIIAgAAAA==.',['Åc']='Åccursed:BAAALAAECgYIDAAAAA==.',['Ês']='Êspêrâ:BAAALAAECgMIBQAAAA==.',['Êt']='Êtê:BAAALAAECgMIBAAAAA==.',['Óm']='Ómg:BAAALAAECgQIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end