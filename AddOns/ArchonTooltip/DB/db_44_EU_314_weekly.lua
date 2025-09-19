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
 local lookup = {'Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Shaman-Elemental','Druid-Restoration','Warrior-Protection','Warrior-Fury','Paladin-Retribution','Druid-Balance','Mage-Frost','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Warrior-Arms','Mage-Fire','Druid-Feral','DemonHunter-Havoc','Hunter-BeastMastery','Druid-Guardian','Mage-Arcane','Warlock-Destruction','Shaman-Enhancement','DeathKnight-Frost','Monk-Brewmaster','Paladin-Holy','DeathKnight-Unholy',}; local provider = {region='EU',realm='Moonglade',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Achelois:BAAALAAECgIIAwAAAA==.',Ae='Aegeus:BAAALAAECgMIBQAAAA==.',Ah='Ahildan:BAAALAADCgEIAQAAAA==.',Ai='Airima:BAAALAADCggICAAAAA==.',Ak='Akamë:BAAALAAECgMIAwAAAA==.',Al='Alarid:BAAALAAECgMIBQAAAA==.Alarïc:BAAALAAECgYICAAAAA==.Albane:BAABLAAECoEdAAMBAAgIIx7GCQDtAQABAAcIuRPGCQDtAQACAAQIiSFQJwCDAQAAAA==.Alexandèr:BAAALAAECgYIDQAAAA==.Aloele:BAAALAADCggICAABLAADCggIIAADAAAAAA==.Altum:BAAALAADCgEIAQAAAA==.',Am='Ambulance:BAAALAADCggIEAAAAA==.Ammathrel:BAAALAAECggICAAAAA==.',An='Anavael:BAAALAADCggIFQAAAA==.Andrijavas:BAAALAAECgQIBAAAAA==.Andriukas:BAAALAAECgMIBQAAAA==.Antosh:BAAALAAECgcIBwAAAA==.',Ar='Arandor:BAAALAADCggIEQAAAA==.Araysh:BAABLAAECoEVAAMEAAcIzxgrJQDaAQAEAAYIlRorJQDaAQAFAAcIqBY6JADUAQAAAA==.Arloth:BAAALAAECgIIAgAAAA==.',As='Ashadori:BAAALAAECgYIDAAAAA==.Ashami:BAACLAAFFIEFAAIEAAMIwBrEBAAVAQAEAAMIwBrEBAAVAQAsAAQKgR4AAwQACAjYI9cEABUDAAQACAjYI9cEABUDAAUABQjLHVwoALUBAAAA.',At='Atarishe:BAAALAADCggICAAAAA==.Athel:BAABLAAECoEeAAIGAAgIrB15DACwAgAGAAgIrB15DACwAgAAAA==.',Az='Azurea:BAAALAAECgYICwAAAA==.Azuriana:BAAALAAECgYIEQAAAA==.',Ba='Baklengsbæsj:BAAALAAECggICAAAAA==.Baroi:BAAALAADCgEIAQAAAA==.',Bi='Bigpurple:BAAALAAECgMIBQAAAA==.',Bl='Blackarm:BAAALAAECgcIEwAAAA==.Blowmie:BAAALAAECggIAwAAAA==.',Bo='Boffeloff:BAAALAAECgQIBwAAAA==.Bonezee:BAAALAADCgcIBwAAAA==.Bopan:BAAALAADCgcIDQAAAA==.Boug:BAAALAADCggIBwAAAA==.',Br='Bradyn:BAAALAADCgcIBwAAAA==.Braol:BAAALAAECgMIBQAAAA==.Brenna:BAAALAADCggICAAAAA==.Briyar:BAAALAADCgcIBwAAAA==.',Ca='Caelenne:BAAALAAECgYICwABLAAECgYICwADAAAAAA==.Caliras:BAAALAADCggIDAAAAA==.Cane:BAAALAAECgEIAQAAAA==.Casturbation:BAAALAADCggICAAAAA==.Catease:BAAALAAECgQIDAAAAA==.',Ce='Celata:BAAALAAECgMIBQAAAA==.Celestiné:BAAALAADCgQIBAAAAA==.Celinette:BAAALAADCgcICwAAAA==.',Ch='Charnvan:BAAALAAECgYICQABLAAECgcIFwAHAHEiAA==.Chichi:BAAALAAECgYICQAAAA==.Chiepa:BAAALAADCgcIDAAAAA==.Chooby:BAAALAADCgYIBgAAAA==.Choppá:BAAALAAECgIIAgAAAA==.Chulun:BAAALAADCggIGAAAAA==.',Co='Colonthree:BAAALAAECgYIDgABLAAECgYIFQAIAFQjAA==.Cordyceps:BAAALAAECgYIEAAAAA==.Corintz:BAAALAADCggICAABLAAECggIGAAJAIYXAA==.',['Có']='Córa:BAAALAADCggICAAAAA==.',Da='Daemin:BAAALAADCggIEAAAAA==.Dakcota:BAAALAAECgMIBQABLAAECggIHgAKAKQeAA==.Dakcotaa:BAABLAAECoEeAAIKAAgIpB7nDADbAgAKAAgIpB7nDADbAgAAAA==.Dantel:BAAALAAECgYIDAAAAA==.Darforth:BAAALAAECgYIDwAAAA==.Darkdash:BAAALAADCgUIBQAAAA==.Darravin:BAAALAADCggIDwAAAA==.',De='Deathrow:BAAALAAECgYICwAAAA==.Deathwhis:BAAALAADCggIDwAAAA==.Denoreth:BAAALAADCgYIBgAAAA==.',Di='Dibidyus:BAAALAADCgUIBQAAAA==.Dippingsauce:BAAALAADCgEIAQAAAA==.Dizsiee:BAAALAAECgIIAgAAAA==.Diás:BAABLAAECoEXAAILAAcIDB4KIgBbAgALAAcIDB4KIgBbAgAAAA==.',Dj='Djenga:BAAALAADCgYIBgAAAA==.',Do='Doofybot:BAAALAAECgcIEQAAAA==.Doric:BAAALAAECgYIEwAAAA==.',Dr='Dragonmaster:BAAALAADCgUIBQAAAA==.Drbrainfriez:BAAALAAECgMIBQAAAA==.Drgoodheals:BAAALAADCggICAAAAA==.Drulasera:BAABLAAECoEVAAMIAAcI7RRDIwC/AQAIAAcI7RRDIwC/AQAMAAIIGgiAVQBqAAAAAA==.Drunkster:BAAALAAECgMIBQAAAA==.',Du='Dutara:BAAALAADCggIDgAAAA==.',Ee='Eerion:BAABLAAECoEeAAINAAgIoiNJAgBFAwANAAgIoiNJAgBFAwAAAA==.',El='Elariía:BAAALAADCgQIBAAAAA==.Electro:BAAALAAECgMIAwAAAA==.Ellin:BAAALAAECgQIBAAAAA==.Ellisd:BAAALAAECgYICAAAAA==.Eltoa:BAAALAAECgYICAAAAA==.Eléazar:BAAALAAECgIIAgAAAA==.',Em='Embodruid:BAAALAADCggICAABLAAECgYICwADAAAAAA==.Emboholy:BAAALAAECgYICwAAAA==.',En='Enyani:BAAALAAECgMIBQAAAA==.',Er='Erfwyll:BAAALAAECgMIBQAAAA==.Erthus:BAAALAAECgMIBQAAAA==.',Es='Eshaldadh:BAAALAAECggIEAAAAA==.Espírito:BAAALAAECgYIDgAAAA==.Essari:BAAALAADCggICAAAAA==.',Ev='Evokslay:BAABLAAECoEdAAMOAAgI3Bm8BgBSAgAOAAgI3Bm8BgBSAgAPAAcIERt6EQBEAgAAAA==.',Ex='Exceed:BAAALAAECgYIEgAAAA==.',Fa='Faldran:BAABLAAECoEaAAIJAAgI7CR8AQBgAwAJAAgI7CR8AQBgAwAAAA==.',Fe='Feisar:BAAALAADCggICAAAAA==.',Fl='Flasher:BAABLAAECoEXAAILAAgIdhl6IABlAgALAAgIdhl6IABlAgAAAA==.Flíbz:BAAALAAECgIIAgAAAA==.',Fo='Forsythra:BAAALAADCgYIBgABLAAECgYIEQADAAAAAA==.Forsythria:BAAALAAECgYIEQAAAA==.Fortissimus:BAAALAADCgQIBAAAAA==.',Fr='Fredryn:BAAALAAECgMIBQAAAA==.Freesya:BAAALAAECgMIBQAAAA==.Frozello:BAAALAAECgYIDAAAAA==.',Fu='Futiko:BAAALAAECggIDgAAAA==.',Fy='Fyria:BAABLAAECoEYAAIJAAgIhheuDwAbAgAJAAgIhheuDwAbAgAAAA==.',Ga='Galmorag:BAAALAAECgYIDwAAAA==.Garretth:BAAALAAECgMIAwAAAA==.Gastly:BAAALAAECgQIBwAAAA==.',Ge='Gentoo:BAAALAADCgcIBwAAAQ==.Gentras:BAAALAADCggIEAABLAAECgQIBgADAAAAAA==.',Gh='Ghaith:BAAALAADCgQIBAABLAAECgYIFQAIAFQjAA==.',Gi='Gimlijrd:BAAALAAECgYIEAAAAA==.',Gl='Glóinzhifu:BAAALAADCggICAAAAA==.',Go='Goukí:BAABLAAECoEVAAIQAAcIzRcbKwDYAQAQAAcIzRcbKwDYAQAAAA==.',Gr='Grail:BAABLAAECoEeAAMKAAgImxmnFgBqAgAKAAgImxmnFgBqAgARAAIIDxdrGQCQAAAAAA==.Gratjak:BAAALAAECgIIAgAAAA==.Growth:BAAALAAECgQIBgAAAA==.',Gu='Gurm:BAAALAAECgcIEQAAAA==.',He='Heftan:BAAALAAECgYIDgAAAA==.Helekõre:BAABLAAECoEVAAISAAcIiw6rBADEAQASAAcIiw6rBADEAQAAAA==.Herrá:BAABLAAECoEYAAIQAAgIIBT4KQDdAQAQAAgIIBT4KQDdAQAAAA==.',['Hé']='Héimdall:BAAALAADCggIEAAAAA==.',Ic='Icelord:BAAALAAECgMIBQAAAA==.Icetails:BAAALAADCgIIAgABLAAECggIFgALAD4cAA==.',Il='Ilanara:BAABLAAECoEWAAILAAcIBxhlNgD5AQALAAcIBxhlNgD5AQAAAA==.',In='Inala:BAAALAADCgMIAwAAAA==.Incisor:BAAALAAECgIIAgABLAAECggICAADAAAAAA==.',It='Ittygritty:BAAALAADCgQIBAAAAA==.',Iz='Izemayn:BAAALAAECgcIBQAAAA==.',Ja='Jamonshamon:BAACLAAFFIEFAAIHAAMIaxOIBgD6AAAHAAMIaxOIBgD6AAAsAAQKgRcAAgcACAhCHwUOAMcCAAcACAhCHwUOAMcCAAAA.Jarondar:BAAALAAECgEIAQAAAA==.',Ju='Juksmonk:BAAALAAECggIBwAAAA==.Jull:BAAALAAECgEIAQABLAAECgYIDwADAAAAAA==.',['Jæ']='Jægeren:BAAALAADCggICAAAAA==.',['Jö']='Jönssi:BAAALAADCggICAAAAA==.',Ka='Kaedhunt:BAAALAADCggICAAAAA==.Kaedshadow:BAAALAADCggICAAAAA==.Kaelthir:BAAALAADCgQIBAAAAA==.Kanters:BAAALAAECgYIDAAAAA==.Kasamuthardi:BAAALAAECggIDQAAAA==.Kasuml:BAAALAADCggIEAAAAA==.Kattalia:BAABLAAECoEUAAMTAAcITRFlDgDTAQATAAcITRFlDgDTAQAIAAEI7QL1fQAiAAAAAA==.Kazeshíní:BAAALAAECgYIDAAAAA==.',Ke='Kerae:BAAALAADCgcIBgAAAA==.Kery:BAAALAADCggIEwAAAA==.',Kh='Kharandriel:BAAALAAECgQIBAAAAA==.Khazradin:BAAALAAECgEIAQAAAA==.Khels:BAABLAAECoEYAAIUAAgIoR9bEQDYAgAUAAgIoR9bEQDYAgAAAA==.Khelss:BAAALAADCggICAABLAAECggIGAAUAKEfAA==.',Ki='Killerwomen:BAABLAAECoEXAAMTAAgIhhr8CgAVAgATAAcIdhn8CgAVAgAIAAEIoxB4dAA7AAAAAA==.Killted:BAAALAAECggICgABLAAECggIJQAKAOMcAA==.',Kl='Kligz:BAAALAAECgYIEQAAAA==.',Kn='Kneecaps:BAAALAAECgcIEwAAAA==.',Ko='Kobra:BAAALAADCggICAAAAA==.Koekmonster:BAAALAAECgYICgAAAA==.Koxypie:BAAALAADCgUICAAAAA==.',La='Lachdanan:BAAALAAECgMIBQAAAA==.Lankey:BAABLAAECoEeAAIVAAgI8CF5CAAJAwAVAAgI8CF5CAAJAwAAAA==.',Le='Lekuna:BAAALAAECgYIBgAAAA==.Lennaya:BAAALAAECgYICwAAAA==.Lexikon:BAAALAAECgMIAwAAAA==.',Li='Liathin:BAABLAAECoEVAAQIAAYIVCNwKQCXAQAIAAYIVCNwKQCXAQAWAAMIVBFeEwCjAAAMAAIIiwxEVgBnAAAAAA==.Lightblossom:BAAALAAECgQICAAAAA==.Lilipéd:BAAALAAECgEIAgAAAA==.Lilitawa:BAAALAADCgcIBwAAAA==.Lillorigga:BAABLAAECoEeAAIHAAgI9iJeBQA7AwAHAAgI9iJeBQA7AwAAAA==.',Ll='Llayla:BAAALAAECgYIDAAAAA==.',Lo='Loktagar:BAAALAADCggIDwAAAA==.Lonelytotem:BAAALAAECgEIAQAAAA==.Lorgo:BAAALAAECgYICwAAAA==.Loriqey:BAAALAAECgYIEwAAAA==.',Ly='Lyzara:BAACLAAFFIEFAAIIAAMI4x0OAwATAQAIAAMI4x0OAwATAQAsAAQKgR4AAggACAiqIzQCAC0DAAgACAiqIzQCAC0DAAAA.',Ma='Maeven:BAAALAADCggICAAAAA==.Magicbowl:BAAALAAECgUIDAAAAA==.Maire:BAAALAAECggIEQAAAA==.Makorr:BAAALAADCggIDAAAAA==.Malavai:BAAALAAECgcIEQAAAA==.Mannchu:BAAALAADCgUIBgAAAA==.Marvyn:BAAALAAECgYIBQAAAA==.',Me='Meowforheals:BAAALAADCggIFgABLAAECgYIDQADAAAAAA==.Meowmeow:BAAALAAECgMIAwAAAA==.Meridian:BAAALAADCggICAAAAA==.Metalpala:BAAALAAECgYICwAAAA==.Metalpriest:BAAALAADCggICAAAAA==.',Mi='Mifurey:BAAALAAECgMIBQAAAA==.Mikiyaki:BAAALAADCgEIAQAAAA==.Minudh:BAAALAADCggIEAAAAA==.Mirandanas:BAAALAAECgYIBwAAAA==.',Mo='Monkslay:BAAALAADCgYIBgABLAAECggIHQAOANwZAA==.Moondancêr:BAAALAADCggIDAAAAA==.Morpheus:BAAALAAECgYIDAAAAA==.',Ms='Msrgrundie:BAAALAAECgMIBwAAAA==.',Mu='Mudhide:BAAALAAECgYIEQAAAA==.Musgrus:BAABLAAECoEUAAIUAAcI7RkgMQADAgAUAAcI7RkgMQADAgAAAA==.',Na='Nadjai:BAABLAAECoEeAAMXAAgIYR43FQC1AgAXAAgIYR43FQC1AgASAAEI0wALFwAJAAAAAA==.Naffaviel:BAAALAADCgYIBgABLAADCgcIBwADAAAAAA==.Namnam:BAAALAAECgcICQAAAA==.Naota:BAAALAAECgQIBQAAAA==.Natf:BAAALAADCgcIBwAAAA==.Nazus:BAAALAADCggIEAAAAA==.',Nb='Nbg:BAAALAADCgcIBwAAAA==.',Ne='Nephos:BAAALAADCgEIAQAAAA==.Nes:BAAALAAECgYICQAAAA==.',Ni='Nilvek:BAAALAAECgMIAwAAAA==.Niriana:BAAALAAECgcIEQAAAA==.Nixage:BAABLAAECoEVAAIXAAcITBRjNgDpAQAXAAcITBRjNgDpAQAAAA==.',No='Novo:BAAALAAECgYIDwAAAA==.',Nu='Nurrien:BAAALAAECgcIDAAAAA==.',Nw='Nw:BAAALAADCgcIBwAAAA==.',Ny='Nythiera:BAABLAAECoEaAAIPAAgItRtaDwBjAgAPAAgItRtaDwBjAgAAAA==.Nyxithra:BAAALAAECgYIDAAAAA==.',Op='Opheliá:BAAALAAECgQIBwAAAA==.',Pa='Palawilkie:BAAALAADCggICwAAAA==.Palea:BAAALAADCgcIEgAAAA==.Pathra:BAAALAADCgEIAQAAAA==.Patróklos:BAAALAADCgEIAQAAAA==.',Pe='Petrichi:BAAALAAECgQICQAAAA==.',Po='Pogothy:BAAALAADCggICAAAAA==.',Ps='Ps:BAAALAADCgYIBgAAAA==.',Pu='Puddles:BAAALAADCggICAAAAA==.',['Pé']='Pétri:BAAALAADCgcIEgAAAA==.',Qe='Qerthal:BAABLAAECoEXAAIYAAcIyhrsIAAnAgAYAAcIyhrsIAAnAgAAAA==.',Qu='Quizan:BAAALAAECgYICwAAAA==.',Ra='Rathollo:BAAALAADCggIHgAAAA==.Rauelduke:BAAALAAECgUIAQAAAA==.Rawdy:BAAALAADCgcICAAAAA==.',Re='Reidens:BAAALAADCgYIBwAAAA==.Remi:BAAALAADCggIEAAAAA==.Rendalar:BAAALAADCggIDwAAAA==.Resynsham:BAAALAADCggICAAAAA==.Retrimootion:BAAALAAECgIIAwAAAA==.Rezet:BAABLAAECoEWAAIZAAcIsxZUCAAAAgAZAAcIsxZUCAAAAgAAAA==.',Ro='Rogueckle:BAAALAAECgIIAgAAAA==.Rootin:BAAALAADCggIBgABLAAECgMIBQADAAAAAA==.Rova:BAAALAADCgYIBAAAAA==.',Ru='Ruunal:BAAALAADCgcIBwAAAA==.',Sa='Safarax:BAAALAAECgIIAgAAAA==.Sangrielle:BAAALAAECgMIAwAAAA==.Sarafan:BAAALAAECgEIAQAAAA==.',Sc='Schwerrie:BAAALAADCggIEAABLAAECgQIBgADAAAAAA==.',Se='Senketsu:BAAALAADCggICAAAAA==.',Sh='Shabu:BAAALAAECgIIAgAAAA==.Shamone:BAABLAAECoEXAAIHAAcIgBmvHgAaAgAHAAcIgBmvHgAaAgAAAA==.Shamoss:BAAALAADCgcIBwAAAA==.Sheiken:BAAALAAECggICAAAAA==.Shershagin:BAAALAADCggIDgAAAA==.Shiemba:BAAALAADCgYIBgAAAA==.Shongtar:BAAALAAECgYIBgAAAA==.Shuvi:BAACLAAFFIEFAAIXAAIInAVdIgB1AAAXAAIInAVdIgB1AAAsAAQKgR8AAhcACAgSHmUUALwCABcACAgSHmUUALwCAAAA.',Si='Silentfist:BAAALAADCgYIBgAAAA==.Sinew:BAAALAAECgQIBwAAAA==.',Sk='Skullyboi:BAAALAAECgIIAgAAAA==.Skurkagurken:BAAALAADCgYIBgAAAA==.',Sn='Snoot:BAAALAAECgMIBQAAAA==.Snugglez:BAAALAADCgQIBAAAAA==.',So='Sofì:BAAALAAECgYICgAAAA==.Solaría:BAAALAAECgMIAwAAAA==.Soukar:BAAALAAECgIIAgABLAAFFAMIBQAEAMAaAA==.',Sp='Spicykebabs:BAAALAAECgYICQAAAA==.Splobotnik:BAABLAAECoEZAAIJAAgIYiL7AgApAwAJAAgIYiL7AgApAwABLAAECgYICQADAAAAAA==.Sprockettrap:BAAALAAECgYICwAAAA==.Spudfyre:BAAALAAECgYIEQAAAA==.',St='Stepbro:BAAALAAECgUIBwAAAA==.Stereotype:BAAALAADCgEIAQAAAA==.Stormrow:BAAALAAECgcIEQAAAA==.',Sy='Sylawyn:BAAALAAECgMIBQAAAA==.Synth:BAABLAAECoEdAAIKAAgIExhgFwBjAgAKAAgIExhgFwBjAgAAAA==.Syrax:BAAALAADCggIEAAAAA==.',Ta='Taijie:BAAALAAECgQIBwAAAA==.Talandareth:BAAALAADCgYIBgAAAA==.Targaryen:BAAALAAECgYIDAAAAA==.',Tb='Tbh:BAAALAAECgYIDQAAAA==.',Te='Telkhuzad:BAAALAADCggIEAAAAA==.',Ti='Tiaana:BAAALAAECgUIBQABLAAECgcIFAAPAJ4cAA==.Tiaanstrasza:BAABLAAECoEUAAIPAAcInhyNEQBCAgAPAAcInhyNEQBCAgAAAA==.Tinodith:BAAALAADCggIEAAAAA==.',To='Toivodk:BAAALAADCggIEQAAAA==.Tokajin:BAAALAAECgcIDgABLAAECgcIDgADAAAAAA==.Tokashot:BAAALAAECgcIDgAAAA==.Tolson:BAAALAADCgcICwAAAA==.Tozie:BAABLAAECoElAAIaAAgIpxlTJwBBAgAaAAgIpxlTJwBBAgAAAA==.',Tr='Treasach:BAACLAAFFIEFAAIbAAMIvxnPAgABAQAbAAMIvxnPAgABAQAsAAQKgR4AAhsACAiXIuoCABMDABsACAiXIuoCABMDAAAA.Tricksa:BAAALAADCggIDgAAAA==.Troopp:BAAALAAECgYIDAAAAA==.',Ul='Ulthwé:BAAALAADCggIFgAAAA==.',Un='Unkillted:BAABLAAECoElAAMKAAgI4xxuEACxAgAKAAgI4xxuEACxAgARAAgIagtODACBAQAAAA==.Unnholyone:BAAALAADCggICAAAAA==.',Ur='Uria:BAABLAAECoEUAAMEAAcICxdJIwDoAQAEAAcICxdJIwDoAQAFAAEICRLQXwBKAAAAAA==.Ursaluna:BAAALAADCgIIAgAAAA==.',Va='Vados:BAAALAADCgIIAgAAAA==.Valefyr:BAAALAADCgMIAwAAAA==.Valerios:BAAALAADCgUIBQAAAA==.Vallik:BAAALAADCggIEwAAAA==.Vampella:BAAALAAECgYIEAAAAA==.Varella:BAAALAADCgEIAQAAAA==.Varila:BAAALAAECgYIBgABLAAECggIFgALAD4cAA==.',Ve='Velinas:BAAALAADCggICAAAAA==.Vers:BAAALAADCgYIBgAAAA==.',Vo='Volteer:BAAALAAECgMIBAAAAA==.Voodooist:BAAALAAECgYIEAAAAA==.',['Ví']='Ví:BAABLAAECoEUAAIUAAgISh60EgDMAgAUAAgISh60EgDMAgAAAA==.',Wa='Wackle:BAAALAAECgEIAQAAAA==.',Wy='Wy:BAAALAADCggICAAAAA==.Wynie:BAAALAAECgYICwAAAA==.',Xo='Xora:BAECLAAFFIENAAIWAAUIcyUJAABIAgAWAAUIcyUJAABIAgAsAAQKgSAAAhYACAjxJgcAAKgDABYACAjxJgcAAKgDAAAA.',Xy='Xyri:BAAALAADCgcIBwAAAA==.',Ya='Yanshi:BAACLAAFFIEFAAIcAAMIIx+SAgApAQAcAAMIIx+SAgApAQAsAAQKgR4AAhwACAiXJT4AAGwDABwACAiXJT4AAGwDAAAA.Yarble:BAAALAAECgYIDwAAAA==.',Ye='Yemy:BAABLAAECoEWAAILAAgIPhw1HACBAgALAAgIPhw1HACBAgAAAA==.Yesmer:BAAALAAECgYICgAAAA==.',Ys='Ys:BAAALAADCggIEwAAAA==.Ysra:BAAALAAECgYIDwAAAA==.',Yu='Yunara:BAAALAADCggIDgAAAA==.Yunsi:BAAALAAECggIDwAAAA==.',Zc='Zc:BAAALAAECgIIAgAAAA==.',Ze='Zeronara:BAAALAAECgMIBgAAAA==.',Zh='Zhourei:BAAALAAECgYIDgAAAA==.',Zi='Zizzlefizzle:BAAALAADCgcIDgAAAA==.',Zo='Zotroz:BAAALAADCgcICAAAAA==.',Zu='Zulrot:BAABLAAECoEWAAMaAAcI/BcYQwDLAQAaAAcI/BcYQwDLAQAdAAUIwA3HIgAyAQAAAA==.',['Äm']='Ämadeus:BAAALAAECgMIBQAAAA==.',['Él']='Élune:BAAALAADCgcIBwAAAA==.',['Êu']='Êuclid:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end