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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Priest-Shadow','Warrior-Fury','Mage-Frost','Hunter-Marksmanship','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Priest-Holy',}; local provider = {region='EU',realm='Illidan',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Ackö:BAAALAAECgMIBAAAAA==.',Ad='Adoloes:BAAALAAECgMIBwAAAA==.',Ae='Aerielle:BAAALAADCgIIAgAAAA==.',Ak='Akantis:BAAALAAECgIIAgABLAAECgYIDgABAAAAAA==.',Al='Allhin:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Alluna:BAABLAAECoEYAAICAAcIZiJyDQC+AgACAAcIZiJyDQC+AgAAAA==.Aloneth:BAAALAADCgMIAwAAAA==.',Am='Amarih:BAAALAADCggIDwAAAA==.',An='Antifascista:BAAALAAECgIIAgAAAA==.',As='Ashenshugar:BAAALAAECgYIBgAAAA==.Asumix:BAAALAAECgIIAgAAAA==.',Au='Aurahn:BAAALAADCggIDAAAAA==.',Ax='Axo:BAAALAADCgMIAwAAAA==.',Ay='Ayshare:BAAALAADCggICgAAAA==.',Az='Azalìe:BAAALAADCgYIBgAAAA==.',Ba='Badnos:BAAALAAECgYIDAAAAA==.',Be='Beepp:BAAALAAECgUICAAAAA==.Berym:BAAALAADCgcIBwAAAA==.',Bo='Bongabin:BAAALAAECgMIBwAAAA==.Boontar:BAAALAAECggIDAAAAA==.Boukàry:BAAALAAECgIIAgAAAA==.',Br='Bratkick:BAAALAADCgcIBwAAAA==.Bromuldir:BAAALAAECgMIAwAAAA==.Brutizy:BAAALAADCggIDwAAAA==.',Bu='Buissøn:BAAALAAECgMIBQAAAA==.Buritos:BAAALAAECggICgAAAA==.',Bz='Bzhcoco:BAABLAAECoEYAAIDAAgIDRwKGwA9AgADAAgIDRwKGwA9AgAAAA==.',['Bê']='Bêëtle:BAAALAAECgYIDAAAAA==.',Ch='Chamajah:BAAALAADCgcIBwAAAA==.Chanla:BAAALAADCggICAAAAA==.Chatdique:BAAALAADCgcICgAAAA==.Choumami:BAAALAAECgcIEgAAAA==.Chromimie:BAAALAADCggICAAAAA==.',Cl='Cleveland:BAAALAAECgMIBQAAAA==.Clôchêtte:BAABLAAECoEXAAIEAAgIQhOpIQDoAQAEAAgIQhOpIQDoAQAAAA==.',Co='Corana:BAAALAADCgUIBgABLAAECgIIAgABAAAAAA==.Cornedbeef:BAAALAAECgEIAQAAAA==.',Cr='Crùsaders:BAAALAAECgMIAwAAAA==.',['Cï']='Cïrion:BAAALAAECgEIAQAAAA==.',['Cø']='Cøcø:BAABLAAECoEVAAMFAAgI1Ba2EwD3AQAFAAgI1Ba2EwD3AQAGAAcIuQ4SHgCgAQAAAA==.',Da='Dardan:BAAALAAECgYICwAAAA==.',De='Deidarra:BAAALAAECgIIAgAAAA==.Deviljäh:BAAALAADCgcIBwABLAAECgYICQABAAAAAA==.Deviltchad:BAAALAAECgYICQAAAA==.',Dk='Dklamite:BAABLAAECoEbAAMCAAgISCUXEwCCAgACAAYIoCQXEwCCAgAHAAUIVCXqCgCjAQAAAA==.',Dm='Dmü:BAAALAADCgcIDQAAAA==.',Do='Dorak:BAAALAAECgUIBgAAAA==.',Dr='Draguanos:BAAALAAECgUICAAAAA==.Dreinisse:BAABLAAECoEVAAMIAAgIUxkGGQD/AQAIAAgIUxkGGQD/AQAJAAcI/wvmJwCKAQAAAA==.Drägny:BAAALAAECgIIAgAAAA==.',Du='Dumblol:BAAALAAECgMIAwAAAA==.',['Dâ']='Dânestan:BAAALAADCgcIBwAAAA==.',['Dï']='Dïxîkry:BAAALAAECgYIBgAAAA==.',Ea='Easier:BAAALAAFFAIIAgAAAA==.',El='Elaidja:BAABLAAECoEVAAMKAAYIJB65CwDJAQAKAAYIEx65CwDJAQALAAMI9RSFawDAAAAAAA==.Elf:BAAALAAECgIIAgAAAA==.Ellenae:BAAALAAECgcICgAAAA==.Elunara:BAAALAAECgYICAAAAA==.Elyz:BAAALAAECgIIAgAAAA==.Eléria:BAAALAAECgcIDQAAAA==.',En='Enõla:BAAALAADCgcICQAAAA==.',Er='Erathole:BAAALAADCggICAAAAA==.',Ew='Ewilon:BAAALAAECgEIAQAAAA==.',Fa='Falcor:BAAALAAECgMIBQAAAA==.Faux:BAAALAADCggICAAAAA==.Favelinha:BAAALAADCgcIDQAAAA==.',Fe='Fearfearfear:BAAALAAECgMIAwAAAA==.Fenwell:BAABLAAECoEUAAIMAAgI1h//AQDdAgAMAAgI1h//AQDdAgAAAA==.',Fi='Ficelle:BAAALAAECgcIEAAAAA==.Filly:BAAALAAECgUICAAAAA==.Firefisher:BAAALAAECgMIAQAAAA==.',Fo='Fouet:BAAALAADCggICgAAAA==.',Fu='Fufuti:BAAALAAECgUIBQABLAAECgYIBgABAAAAAA==.',['Fâ']='Fâvêlinhâ:BAAALAADCgcICwAAAA==.',Ga='Gastmort:BAAALAAECgUICAAAAA==.',Ge='Geb:BAAALAAECgYIBwAAAA==.',Gh='Ghostuns:BAAALAAECgYICQAAAA==.',Gl='Globok:BAAALAADCggIFQAAAA==.',Gr='Grimmjôww:BAAALAAECgYIDwAAAA==.Grlm:BAAALAAECgUIBgAAAA==.Grunbeld:BAAALAADCgQIBAAAAA==.',Gu='Guljaeden:BAAALAAECgMIAwAAAA==.Guuldaan:BAAALAAECgQIBAAAAA==.',['Gü']='Gürdan:BAAALAAECgQIBwAAAA==.',He='Heldios:BAAALAADCggICAABLAAECgcIDQABAAAAAA==.Heyrazmo:BAAALAAECgYIDgAAAA==.',Ho='Hoprytal:BAAALAAECgYICwAAAA==.',Hu='Humanisse:BAAALAADCgQIBAABLAAECggIFQAIAFMZAA==.',Hy='Hyosube:BAAALAADCgcIBwAAAA==.',['Hä']='Häussen:BAAALAAECgcIEAAAAA==.',['Hù']='Hùtch:BAAALAADCggIHAAAAA==.',['Hü']='Hünk:BAAALAADCggIFgAAAA==.',Ic='Ichïmaru:BAAALAADCgcIDgAAAA==.',Il='Ilithya:BAAALAADCggIEwAAAA==.Ilwyna:BAAALAADCgcICAAAAA==.',Im='Immuane:BAAALAAECgYIBgAAAA==.',Is='Istos:BAAALAADCgYIBgAAAA==.',Iy='Iyonas:BAAALAADCgcIBwAAAA==.',Ja='Jackpote:BAAALAADCgIIAgAAAA==.',['Jä']='Jäckz:BAAALAAECggICAAAAA==.Järjär:BAAALAADCggIFgAAAA==.',['Jö']='Jöthun:BAAALAAECgYIDAAAAA==.',Ka='Kadlaxyr:BAAALAAECggIDQAAAA==.Kakkette:BAAALAAECgYIBgAAAA==.Karden:BAAALAAECgUICAAAAA==.',Ke='Keelea:BAABLAAECoEXAAINAAgIBhw4DACTAgANAAgIBhw4DACTAgAAAA==.Keyn:BAAALAAECgEIAQAAAA==.Keïlà:BAAALAADCgYICQAAAA==.',Kh='Khaya:BAAALAAECgYICwAAAA==.Kheph:BAAALAAECgYIDQAAAA==.',Kn='Knuh:BAAALAADCgEIAQAAAA==.',Ko='Korak:BAAALAADCgcICAAAAA==.',Kr='Krapock:BAAALAAECgMIAwAAAA==.Kraven:BAAALAAECgYICgAAAA==.Krolox:BAAALAADCggIEAAAAA==.',Ky='Kylana:BAAALAADCgcIDAAAAA==.',['Kâ']='Kâlaye:BAAALAAECgEIAQAAAA==.',['Kä']='Kämikazy:BAAALAAECgQIBAAAAA==.',La='Laucéane:BAAALAADCggICAAAAA==.Laël:BAAALAAECgEIAQAAAA==.',Le='Leemyungbak:BAABLAAECoEWAAIOAAgIzB1BCwDBAgAOAAgIzB1BCwDBAgAAAA==.Leffedral:BAAALAADCggIFQAAAA==.Leyvina:BAAALAADCggIDgAAAA==.',Li='Lighthammer:BAAALAADCggICAAAAA==.',Lo='Loraën:BAAALAAECgEIAQAAAA==.Loreleïla:BAAALAADCgYIBgAAAA==.',Lu='Lubellion:BAAALAAECgUIBgAAAA==.',['Lê']='Lêd:BAAALAAECgMIAwAAAA==.',['Lì']='Lìnk:BAAALAADCgUIBQAAAA==.',Ma='Maelwyn:BAAALAADCgYIBwABLAAECgcIDQABAAAAAA==.Mahito:BAAALAADCgIIAgAAAA==.Marheaven:BAAALAAECgMIAwAAAA==.Maxinaz:BAAALAADCgcIBwAAAA==.',Mc='Mckay:BAAALAADCggIGAAAAA==.',Me='Medipac:BAAALAAECgIIAgAAAA==.Meldan:BAAALAAECgYIEQAAAA==.Meljânz:BAAALAAECgIIAgAAAA==.Mentalyill:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Meraxes:BAAALAAECgcICgAAAA==.',Mi='Miketysôn:BAAALAADCgEIAQAAAA==.',Mo='Monahlisa:BAAALAAECgMIAwAAAA==.Monbazillac:BAAALAAECgMIBAAAAA==.Monsu:BAAALAAECgMIAwAAAA==.Montoya:BAAALAADCggIFAAAAA==.Mouchoustyle:BAAALAADCggIEAAAAA==.Moönz:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',['Mï']='Mïnuït:BAAALAAECgQICAAAAA==.',Na='Nadyie:BAAALAAECgYICQAAAA==.Nayma:BAAALAADCggICAAAAA==.',Ne='Necrogodx:BAAALAADCggIDwAAAA==.Nectarinee:BAAALAAECgcIEQAAAA==.',No='Nonverbal:BAAALAAFFAIIAgAAAA==.Notsgar:BAAALAADCgcIBwAAAA==.',['Nà']='Nàm:BAAALAAECgMIAwAAAA==.',['Né']='Nécroh:BAAALAADCggIFQAAAA==.',Oi='Oil:BAAALAAECgIIAgAAAA==.',Om='Omerdalors:BAAALAAECgMIAwAAAA==.',Ou='Ouique:BAAALAAECgYIBgAAAA==.',Ov='Overlords:BAAALAADCgcIBwAAAA==.',Ox='Oxmolol:BAAALAAECgIIAgAAAA==.',Pa='Palapin:BAAALAAECgMIAwAAAA==.Panorhamix:BAAALAADCgcICgAAAA==.Papis:BAAALAADCgcIBwAAAA==.Parisnovotel:BAAALAADCgUIBQAAAA==.Patoune:BAAALAAECgcICAAAAA==.',Ph='Phasma:BAAALAAECgYIBwABLAAECggIGwACAEglAA==.Phasmålia:BAAALAADCgcICwABLAAECggIGwACAEglAA==.Phâsma:BAAALAADCgcIBwABLAAECggIGwACAEglAA==.',Pi='Piflya:BAAALAADCggICAAAAA==.',Pl='Plopute:BAABLAAECoESAAIPAAgI+Rp8CgA5AgAPAAgI+Rp8CgA5AgAAAA==.Ploumi:BAAALAADCgQIBQAAAA==.',Po='Poeleaheal:BAAALAAECgcICwAAAA==.Popotin:BAAALAAECgIIAgAAAA==.',Ra='Rambi:BAAALAADCggICAABLAAECggIGQAQAD4YAA==.Randeng:BAAALAAECgYICQAAAA==.',Re='Redbreath:BAABLAAECoEWAAQRAAgI0R+6AwDLAgARAAgI0R+6AwDLAgASAAUIIhCMGwAlAQATAAEI2gz5IQA+AAAAAA==.Redvokers:BAAALAAECgYIBgABLAAECggIFgARANEfAA==.Rehgård:BAAALAADCggICAAAAA==.Reiser:BAAALAADCggIEgABLAAECgcIDQABAAAAAA==.Reyden:BAAALAAECgIIAgAAAA==.',Ro='Rooffe:BAAALAAECgYIBgAAAA==.',Ru='Rubilax:BAAALAAECgYICwAAAA==.',Ry='Ryze:BAAALAADCgcIDgABLAAECgYICwABAAAAAA==.',['Rî']='Rîgald:BAAALAADCggIGAAAAA==.',Sa='Sabri:BAAALAADCgYIBgAAAA==.Sadouque:BAAALAAECgMIBwAAAA==.Salzburg:BAAALAAECgYIBgAAAA==.',Se='Seekffu:BAAALAAECgEIAQAAAA==.',Sh='Shakano:BAAALAAECgEIAQAAAA==.Shingen:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.',Si='Siffride:BAAALAAECgMIAwAAAA==.',Sk='Skeptgalileo:BAAALAAECgIIAgABLAAECggIGwALALMkAA==.Skirner:BAABLAAECoEVAAICAAgInBVjHwAkAgACAAgInBVjHwAkAgAAAA==.Sky:BAAALAADCgMIAwAAAA==.',So='Soeurâltà:BAAALAADCgMIAwAAAA==.',St='Stormax:BAAALAAECgQICQAAAA==.',Su='Subzerocool:BAAALAAECgMICAAAAA==.',['Sê']='Sêifer:BAAALAADCgUIBgAAAA==.Sêênsî:BAAALAAECgIIAgAAAA==.',['Sø']='Søà:BAAALAAECggICQAAAA==.',Ta='Taboune:BAAALAAECgMICwAAAA==.Talesse:BAAALAADCgEIAQAAAA==.Tarakzul:BAAALAADCgEIAQAAAA==.Tarkalian:BAAALAAECgIIAgAAAA==.',Te='Telilenn:BAAALAADCgIIAgAAAA==.Tempeste:BAAALAADCgUIBQAAAA==.',Th='Thyraël:BAAALAADCggIDgAAAA==.',Ti='Tidjani:BAAALAAECgQIBAAAAA==.Titleist:BAAALAADCggICAAAAA==.',To='Tokinooki:BAAALAADCggIDwAAAA==.Touklakos:BAAALAAECgUICAAAAA==.',Ty='Tyraniss:BAAALAAECgUICAAAAA==.',['Tä']='Tärentio:BAAALAAECgIIAgAAAA==.',Um='Umbrös:BAAALAAECgUICQAAAA==.',Ur='Urrax:BAAALAADCggICAABLAAECgcICgABAAAAAA==.',Us='Usurpater:BAABLAAECoEbAAILAAgIsyTzDADIAgALAAgIsyTzDADIAgAAAA==.',Va='Valunistar:BAABLAAECoEVAAIUAAgIEgmbJQCTAQAUAAgIEgmbJQCTAQAAAA==.Vanadis:BAACLAAFFIEFAAIDAAMIMxR5CgCsAAADAAMIMxR5CgCsAAAsAAQKgRgAAgMACAjqHocOALwCAAMACAjqHocOALwCAAAA.',Ve='Vengeance:BAAALAADCgEIAQAAAA==.',Vi='Victim:BAAALAADCgcICQAAAA==.Vikkos:BAAALAAECgYICgAAAA==.',['Vî']='Vîdâlôcâ:BAAALAADCggIDwAAAA==.Vîgald:BAAALAADCggIFwAAAA==.',Wa='Wakkam:BAAALAAECgYIBwAAAA==.Wakkaï:BAAALAADCgYIBQAAAA==.Wapz:BAAALAADCggICAAAAA==.',Wh='Whispaa:BAAALAAECggIEAAAAA==.',Wi='Wiloo:BAAALAAECgIIAgAAAA==.',Wo='Woodland:BAABLAAECoEZAAIQAAgIPhjjFQDgAQAQAAgIPhjjFQDgAQAAAA==.',Xe='Xernes:BAAALAAECgcIDQAAAA==.',Ya='Yannoubass:BAAALAADCgQIBAAAAA==.',Ym='Ymïr:BAAALAAECgEIAQAAAA==.',Yo='Yoirgl:BAAALAAECgMIBgAAAA==.Yoirglë:BAAALAADCggICAAAAA==.',Za='Zaacksx:BAAALAADCggICgAAAA==.Zayos:BAAALAADCgcIBwAAAA==.',Zk='Zkittlez:BAAALAADCgMIAwAAAA==.',Zo='Zogi:BAAALAADCggICAAAAA==.',Zu='Zumajiji:BAAALAAECgYICQAAAA==.',['Zâ']='Zâcâpâ:BAAALAAECgEIAQAAAA==.',['Zé']='Zéloth:BAAALAADCgQIBAAAAA==.',['Zø']='Zøkar:BAAALAAECgIIAgAAAA==.',['Ãl']='Ãlphã:BAAALAADCggICAAAAA==.',['År']='Årchimède:BAAALAADCgYIBgAAAA==.',['În']='Înorie:BAAALAAECgUIBwAAAA==.',['Ðe']='Ðeinos:BAAALAAECgEIAQAAAA==.',['Øb']='Øbëlïx:BAAALAADCgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end