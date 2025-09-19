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
 local lookup = {'Shaman-Restoration','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','DeathKnight-Blood','DeathKnight-Unholy','Unknown-Unknown','Rogue-Assassination','Monk-Mistweaver','DemonHunter-Havoc','Paladin-Retribution','Druid-Balance','Mage-Arcane','Paladin-Holy','Mage-Frost','Warlock-Destruction','Hunter-BeastMastery','Priest-Shadow','Warrior-Fury','Hunter-Marksmanship','DemonHunter-Vengeance','Mage-Fire',}; local provider = {region='EU',realm='DarkmoonFaire',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aaronm:BAAALAAECgEIAQAAAA==.',Ab='Absents:BAAALAADCgcIDAAAAA==.Abyssion:BAAALAAECgMIBAAAAA==.Abzap:BAAALAADCgUIBQAAAA==.',Ad='Addzy:BAAALAADCggICAAAAA==.',Ag='Agammer:BAAALAAECgYIEQAAAA==.',Al='Alaania:BAAALAAECgMIBAAAAA==.Aleaxia:BAAALAAECgMIAwAAAA==.Alfr:BAAALAAECgYIEQAAAA==.Alkyholix:BAAALAAECgYIDwAAAA==.Altais:BAABLAAECoEWAAIBAAcIHggxaADzAAABAAcIHggxaADzAAAAAA==.',An='Antares:BAAALAAECgEIAQAAAA==.',Ao='Aorli:BAAALAAECgIIAgAAAA==.',Ar='Aragor:BAAALAADCgQIBAAAAA==.Argyros:BAAALAAECgYIEAAAAA==.',As='Asdfqwerty:BAAALAADCgUIBwAAAA==.Ashauna:BAAALAAECgcIEwAAAA==.Askja:BAAALAADCgYIBgAAAA==.Asteryn:BAAALAAECgYICgAAAA==.Astraia:BAABLAAECoEVAAMCAAcIRyKxCgBWAgACAAYIBCKxCgBWAgADAAMIDxwkFgAFAQAAAA==.',Au='Auralia:BAAALAAECgIIBQAAAA==.',Av='Avoidelf:BAAALAAECgMIAwAAAA==.',Az='Azeranka:BAAALAAECgYIDgAAAA==.',Be='Bella:BAAALAADCgcICgAAAA==.Bellecarlsen:BAABLAAFFIEGAAQEAAIIWx2GDgC1AAAEAAIIWx2GDgC1AAAFAAIIxgakBgB1AAAGAAEIvRmSCwBZAAAAAA==.Berna:BAAALAAECgEIAQAAAA==.Beshamel:BAAALAAECggIEwAAAA==.',Bi='Bigwild:BAAALAAECggICwAAAA==.',Bo='Bombard:BAAALAADCgYIDAABLAAECgYIDwAHAAAAAA==.',Br='Brambull:BAAALAADCggIDAABLAAECgYIDwAHAAAAAA==.Brocken:BAAALAAECgIIAgAAAA==.Brynnd:BAAALAADCggIDgABLAAECgEIAQAHAAAAAA==.Bréalan:BAAALAAECgEIAQAAAA==.',['Bæ']='Bæl:BAABLAAECoEVAAIBAAcIFxy4GwAsAgABAAcIFxy4GwAsAgAAAA==.',Ca='Candyfloss:BAAALAADCgcIFwAAAA==.Caílleach:BAAALAADCgcIBwAAAA==.',Ch='Chalima:BAAALAAECgIIAgAAAA==.Chinde:BAAALAAECgYIEQAAAA==.',Cl='Clotsby:BAAALAADCgcIEAAAAA==.',Co='Constar:BAAALAADCgcIAwAAAA==.Cortius:BAAALAADCgMIAwAAAA==.Cosmos:BAAALAAECgIIAgAAAA==.',Cr='Crimsonlich:BAAALAADCgQIBgAAAA==.Crimsonrider:BAAALAADCgcIBwAAAA==.',Cu='Cupquake:BAAALAADCggIGwAAAA==.',Da='Daerauko:BAAALAADCggIEAAAAA==.Dakeyras:BAABLAAECoEVAAIIAAcIbyCxDQB/AgAIAAcIbyCxDQB/AgAAAA==.Danthorius:BAAALAAECgIIAgAAAA==.Darthchaos:BAABLAAECoEVAAIGAAYI9hbLFQCtAQAGAAYI9hbLFQCtAQAAAA==.Datsun:BAABLAAECoEVAAIJAAcI3QhdHAAuAQAJAAcI3QhdHAAuAQAAAA==.Daé:BAAALAADCgYIDAABLAADCggIEAAHAAAAAA==.',De='Deadlykiller:BAABLAAECoEVAAIKAAYIISXJGgCHAgAKAAYIISXJGgCHAgAAAA==.Deadlyrage:BAAALAADCggICAABLAAECgYIFQAKACElAA==.Deathsmane:BAABLAAECoEVAAMEAAcInB8lHQB+AgAEAAcIiR4lHQB+AgAFAAYISR8XDADgAQAAAA==.Deirius:BAAALAADCggICAAAAA==.Delena:BAAALAAECgIIAgAAAA==.Delynel:BAAALAAECgEIAQABLAAECggIHQALAOAkAA==.Demonspear:BAAALAADCggIEAAAAA==.Derelicta:BAABLAAECoEWAAIFAAcIixKbEACFAQAFAAcIixKbEACFAQAAAA==.',Di='Diananomimec:BAAALAAECgMIBgAAAA==.Divinewill:BAAALAADCgUICQAAAA==.',Do='Dorp:BAAALAAECgIIAgAAAA==.',Dr='Dragonbreat:BAAALAADCgQIAgAAAA==.Draktharr:BAAALAAECgMIAwAAAA==.Drangon:BAAALAADCggIDwAAAA==.Druidsmaid:BAAALAADCggICAAAAA==.Dréxzi:BAAALAADCgcIEgAAAA==.',Dw='Dwabz:BAAALAAECgIIAgAAAA==.Dwarein:BAAALAADCgcIEQAAAA==.',['Dë']='Dëmönböï:BAABLAAECoEWAAIKAAcIERdhMgD9AQAKAAcIERdhMgD9AQAAAA==.',Ed='Eddyscritch:BAABLAAECoEYAAIMAAgIGiI6BgAVAwAMAAgIGiI6BgAVAwAAAA==.',Ei='Eiveth:BAAALAAECgYIDwAAAA==.',El='Elleí:BAAALAADCggIDgAAAA==.',Er='Eriksen:BAAALAAECgIIAgAAAA==.',Es='Esuvius:BAAALAAECgEIAQAAAA==.',Ew='Ewavy:BAAALAAECgMIBgAAAA==.',Fa='Falanyr:BAAALAAECgcIDgAAAA==.Falkrathin:BAAALAADCgcIEwAAAA==.Fanetrotil:BAAALAAFFAIIAgAAAA==.Fanumtax:BAAALAAECgEIAQAAAA==.',Fe='Feigenbaum:BAAALAAECgMIBgAAAA==.Fenrir:BAAALAAECgIIAgAAAA==.Fesh:BAAALAAECgMIAwAAAA==.',Fi='Fitze:BAAALAAECgYIDwAAAA==.',Fl='Flexbluger:BAAALAADCgcIBwAAAA==.Flisc:BAAALAADCggICAAAAA==.Flowdiebow:BAAALAAECggIEgAAAA==.Flóp:BAAALAAECgYICwAAAA==.Flópsox:BAAALAADCggICAABLAAECgYICwAHAAAAAA==.Flýnn:BAAALAAECgEIAQAAAA==.',Fr='Frixion:BAAALAAECgUICwAAAA==.Frékor:BAAALAAECgEIAQAAAA==.',Fu='Furila:BAAALAADCgEIAQAAAA==.Furstrike:BAABLAAECoEdAAINAAgIyxwRGwCKAgANAAgIyxwRGwCKAgAAAA==.',Ga='Gawain:BAABLAAECoEYAAILAAgIOxg+JQBIAgALAAgIOxg+JQBIAgAAAA==.',Ge='Geniisis:BAAALAAECgMICAAAAA==.Georgy:BAAALAADCgYICQAAAA==.',Gi='Gizzmir:BAAALAADCgYIBgAAAA==.',Gl='Gliggy:BAAALAADCggICAAAAA==.',Gr='Greystork:BAAALAAECgEIAQAAAA==.',Ha='Hajashi:BAAALAAECgMIBgAAAA==.Haverok:BAAALAAECgEIAQAAAA==.Hawkers:BAAALAAECgcIEQAAAA==.',He='Hessonite:BAAALAAECgMIAwAAAA==.',Ho='Holycritzs:BAABLAAECoEdAAIOAAgI1xc+DQA1AgAOAAgI1xc+DQA1AgAAAA==.Holydjent:BAAALAADCgcICAAAAA==.Holygóat:BAAALAADCgcIBwABLAAECgYIFAAPABwQAA==.Holynell:BAABLAAECoEdAAILAAgI4CQ8BQBRAwALAAgI4CQ8BQBRAwAAAA==.',['Há']='Hágríd:BAAALAAECgcIEQAAAA==.',['Hé']='Héla:BAAALAADCgEIAQAAAA==.',Id='Idis:BAAALAAECgYIDwAAAA==.',In='Invi:BAAALAAECgMIBAAAAA==.',Io='Ionns:BAAALAAECgIIAgAAAA==.',It='Ithryllian:BAAALAAECgEIAQAAAA==.Ito:BAAALAADCgcICgAAAA==.',Ja='Jacobriley:BAAALAAECgIIAQAAAA==.Jaye:BAAALAAECgcIEQAAAA==.Jayee:BAACLAAFFIEHAAIQAAMIRR34CgDXAAAQAAMIRR34CgDXAAAsAAQKgSoAAxAACAiiG6gWAHsCABAACAiiG6gWAHsCAAMABgi5CyIOAIIBAAAA.Jaygue:BAAALAAECgYIBgABLAAECgcIEQAHAAAAAA==.Jaz:BAAALAAECgYIBwABLAAECggIGAARANIPAA==.Jazzii:BAAALAAECgEIAQABLAAECgIIAQAHAAAAAA==.Jazzy:BAABLAAECoEYAAIRAAgI0g/ZKgDsAQARAAgI0g/ZKgDsAQAAAA==.',Je='Jesmyn:BAAALAAECgcIDwAAAA==.Jessia:BAAALAAECggICAAAAA==.',Jo='Jokeski:BAAALAAECgcIEwAAAA==.Jomoo:BAAALAADCgYIBgAAAA==.',Ju='Judgejez:BAAALAADCgcIBwABLAAECgIIAQAHAAAAAA==.Jujucat:BAAALAAECggICAAAAA==.Jujushin:BAAALAADCggICAAAAA==.',Jv='Jvz:BAAALAAFFAIIAgAAAA==.',Jx='Jxshy:BAAALAADCgYIBgAAAA==.',Jy='Jylani:BAAALAAECgMIAwABLAAFFAIIAgAHAAAAAA==.',Ka='Kaasuidpow:BAAALAADCgcIDQAAAA==.Kah:BAAALAADCggIDQAAAA==.Kairos:BAAALAAECgIIAgAAAA==.Kaizhan:BAAALAAECggICAAAAA==.Kalasgösta:BAAALAADCggICAAAAA==.Kalaskillen:BAAALAAECgYIDwAAAA==.Kambui:BAACLAAFFIEFAAINAAMIshiWCAAKAQANAAMIshiWCAAKAQAsAAQKgSUAAg0ACAjYJPoDAEwDAA0ACAjYJPoDAEwDAAAA.Karfhudd:BAAALAAECggIDwABLAAECggIEwAHAAAAAA==.Karsaorlong:BAAALAADCgEIAQAAAA==.Karsus:BAAALAAECgYIEgAAAA==.Kazage:BAAALAAECgMIAwAAAA==.',Kc='Kcsino:BAAALAADCgYICgAAAA==.',Ki='Kienna:BAAALAADCggICAAAAA==.',Ko='Kogan:BAAALAAECgUICAAAAA==.',Ku='Kurama:BAAALAADCgEIAQAAAA==.',['Ká']='Kárathas:BAAALAADCgEIAQAAAA==.',La='Laíka:BAAALAAECgIIAgAAAA==.',Le='Letmelive:BAAALAAECgYIEQAAAA==.Letmepray:BAAALAADCgcIBwAAAA==.',Li='Liara:BAAALAAECggIDwAAAA==.Lielee:BAAALAAECgEIAgAAAA==.Lien:BAAALAAECgEIAQAAAA==.Lighte:BAAALAADCggIDwAAAA==.',Lj='Ljosdottir:BAAALAADCgYIBgABLAADCggIEAAHAAAAAA==.',Lo='Lorali:BAAALAADCggICgAAAA==.Lorkas:BAAALAADCgEIAQAAAA==.Louriele:BAAALAAECgIIAQAAAA==.',Lu='Lucianmoon:BAABLAAECoEVAAIOAAcIHxwCDQA4AgAOAAcIHxwCDQA4AgAAAA==.Luella:BAAALAAECgQIBAAAAA==.Lufen:BAAALAADCgYIBgAAAA==.Luobinghe:BAAALAAECgMIBgAAAA==.Lupei:BAAALAAECgMIBgAAAA==.',Ly='Lyaena:BAAALAAECgMIBwAAAA==.Lykopas:BAAALAADCgcIEAABLAAECgEIAQAHAAAAAA==.Lyrilla:BAAALAAECgMIAwAAAA==.',Ma='Magnetar:BAAALAADCggICAAAAA==.Makavalian:BAAALAAECgIIAgAAAA==.Makoto:BAAALAADCgcICwAAAA==.Malilock:BAABLAAECoEWAAQDAAgIph/sBwD8AQADAAYIfhjsBwD8AQAQAAYIxBTBNwCcAQACAAIIwR1mSQCwAAAAAA==.Manlike:BAAALAADCggICAAAAA==.Marthen:BAAALAADCggIEAAAAA==.Mawser:BAAALAADCgcIBQAAAA==.Maxikatí:BAAALAAECgIIAgAAAA==.Mazzeltoff:BAAALAAECgYIBgAAAA==.',Me='Meow:BAAALAAECggICAAAAA==.Meriel:BAAALAAECgQICgAAAA==.',Mi='Milkytbh:BAAALAAECgcIEQAAAA==.Mindgames:BAABLAAECoEjAAISAAgIJiNNBQAsAwASAAgIJiNNBQAsAwAAAA==.Minibrew:BAAALAAECgMIBgAAAA==.Mirel:BAAALAADCgcIBwAAAA==.Mirthiora:BAAALAADCggICAAAAA==.Misquamacus:BAAALAADCgYIBgAAAA==.Mitars:BAAALAAECgYIEQAAAA==.',Mo='Moochad:BAAALAADCggICAAAAA==.Moonfan:BAAALAADCggIEAAAAA==.',My='Mystalina:BAAALAADCgcIDQAAAA==.',['Mó']='Mógui:BAABLAAECoEVAAIEAAcI2g9jUQCaAQAEAAcI2g9jUQCaAQAAAA==.',Na='Naff:BAAALAAECgcIBwAAAA==.Natháhnos:BAAALAAECgMIBAAAAA==.Naturègrasp:BAAALAADCgQIBgAAAA==.Naustyy:BAAALAAECggICAAAAA==.',Ne='Nekochan:BAAALAAECggICAAAAA==.',Ni='Nidur:BAAALAAECgEIAQAAAA==.Niff:BAAALAAECggICAAAAA==.Nigel:BAABLAAECoEWAAMGAAgIbyPzAQAuAwAGAAgIbyPzAQAuAwAFAAEINiHDJABWAAAAAA==.Nimoria:BAAALAADCgEIAQAAAA==.Nimp:BAAALAADCgcICQAAAA==.',No='Nof:BAAALAAECgEIAQAAAA==.Noff:BAAALAADCgEIAQAAAA==.Normanbatés:BAAALAADCgcIDgAAAA==.Noshards:BAAALAAECgQIBAAAAA==.Nová:BAAALAADCgcIBwABLAAECgIIAgAHAAAAAA==.',Ny='Nyarlock:BAAALAADCggICAAAAA==.Nymh:BAAALAAECgIIAgAAAA==.Nyárla:BAABLAAECoEUAAIPAAYIHBCTJABzAQAPAAYIHBCTJABzAQAAAA==.',['Nè']='Nèlliel:BAAALAAECgMIBgABLAAECggICAAHAAAAAA==.',['Nò']='Nòva:BAAALAADCgUIBQABLAAECgIIAgAHAAAAAA==.',['Nø']='Nøh:BAAALAAECgEIAQAAAA==.',Om='Omnirole:BAAALAAECgUICgAAAA==.',Op='Ophy:BAAALAAECgMIAgAAAA==.',Or='Orumi:BAAALAAECgcIEQAAAQ==.',Ow='Owlgebra:BAAALAAECgYIDAAAAA==.',Pa='Pallypriest:BAAALAAECgYIDAAAAA==.Parafix:BAAALAAECgYIDQAAAA==.Paustian:BAAALAADCggIDwAAAA==.',Pe='Percival:BAAALAADCgcIBwAAAA==.',Ph='Phasanity:BAABLAAECoEWAAILAAcILSBiHACAAgALAAcILSBiHACAAgAAAA==.Phillidan:BAAALAAECgMIBQAAAA==.',Pr='Pretty:BAAALAADCggICAAAAA==.Priya:BAAALAADCggIBgAAAA==.',['På']='Pågsson:BAABLAAECoEZAAIEAAgIVSTbBwAmAwAEAAgIVSTbBwAmAwAAAA==.Pålsson:BAAALAADCgcIBwAAAA==.',Qu='Quij:BAAALAADCggIGAAAAA==.Quirei:BAAALAAECgYIBgAAAA==.',Ra='Rabíd:BAAALAADCgcICgAAAA==.Rafaelxes:BAAALAAECgcIEgAAAA==.Rahl:BAAALAAECgIIAgAAAA==.Rainshammy:BAAALAADCggICAAAAA==.Rashul:BAAALAAECgIIAwAAAA==.Rastacow:BAAALAAECgQICAABLAAECggIIwASACYjAA==.',Re='Redbol:BAAALAAECgMIAwAAAA==.Redear:BAAALAAECgYIEQAAAA==.Resus:BAAALAAECgEIAQAAAA==.Rethen:BAAALAADCgQIBAAAAA==.',Rh='Rhysandt:BAAALAADCgQIBQAAAA==.',Ri='Ritualofmoon:BAAALAAECgIIAgAAAA==.Ritualrogue:BAAALAAECgYIDAAAAA==.',Sa='Saephrynex:BAAALAADCgYIBgABLAAECgYIBgAHAAAAAA==.Saephynea:BAAALAADCggICAABLAAECgYIBgAHAAAAAA==.Saephyra:BAAALAAECgYIBgAAAA==.Saephyrea:BAAALAAECgMICgABLAAECgYIBgAHAAAAAA==.Saphoura:BAAALAAECgYIBgAAAA==.Save:BAAALAAECgYIDQAAAA==.',Sc='Schierke:BAAALAAECgYIDwAAAA==.Scôr:BAABLAAECoEUAAITAAcIOB3OGwA7AgATAAcIOB3OGwA7AgAAAA==.',Se='Seamstress:BAAALAADCgIIAgAAAA==.Semora:BAAALAAECgYICgAAAA==.Sendy:BAAALAAECgYIEQAAAA==.',Sh='Shachris:BAAALAAECgUIDAAAAA==.Shandora:BAAALAAECgUICAAAAA==.Shivox:BAAALAAECgIIAgABLAAECgUICwAHAAAAAA==.Shortnsmitey:BAAALAADCgYIBgAAAA==.',Si='Silverain:BAAALAAECgIIAgAAAA==.Sinrathus:BAAALAAECgYIDwAAAA==.Sixteen:BAAALAAECgUICwAAAA==.',Sk='Skyseeker:BAAALAAECgcIEAAAAA==.',Sm='Smallarms:BAAALAADCggIEAAAAA==.Smazdh:BAAALAAECgIIAgAAAA==.Smazz:BAAALAADCgYIBgAAAA==.',Sn='Sneakyman:BAAALAAECgQIBwAAAA==.Snowcat:BAAALAADCggICAAAAA==.',So='Soffrok:BAAALAAECgMICAAAAA==.Sopadepedra:BAAALAAECgcIBwAAAA==.',St='Starlaka:BAAALAADCggICAAAAA==.Starlie:BAAALAADCgMIAwAAAA==.Stezzil:BAAALAAECgIIAgAAAA==.Stormgrash:BAAALAADCggICgAAAA==.',Su='Succubeach:BAAALAADCgcIEAAAAA==.Sudosu:BAAALAADCgYICAAAAA==.Sunweaver:BAAALAAECggIDAAAAA==.',Sy='Sylvestere:BAAALAAECgcIDAAAAA==.',['Sí']='Sírwinston:BAAALAAECgYICwAAAA==.',Ta='Tag:BAAALAADCgQIBAABLAAECgYIDAAHAAAAAA==.Tagnaros:BAAALAAECgMIBgAAAA==.Tangleroots:BAAALAADCggIDgAAAA==.',Te='Terrorrblade:BAAALAAECgYIEAAAAA==.',Th='Thornquist:BAAALAAECgYICgAAAA==.Thurin:BAAALAADCgYIBgAAAA==.',Ti='Tigerkink:BAAALAAECgMIBgAAAA==.Timbaeth:BAAALAAECgYIDAAAAA==.',To='Toriko:BAAALAADCgEIAQAAAA==.Tortureall:BAAALAAECgIIAgAAAA==.',Tr='Traight:BAABLAAECoEVAAIUAAcIxRO8JwCpAQAUAAcIxRO8JwCpAQAAAA==.Trephination:BAAALAAECgYIEQAAAA==.Trevorella:BAAALAAECgYICQAAAA==.Trollmorph:BAAALAAECgYICQAAAA==.Trombley:BAAALAADCgcIEwAAAA==.Trustyulf:BAAALAAECgUIBQAAAA==.',Tz='Tzeénthc:BAAALAAECgMIAwAAAA==.',Ud='Udurun:BAAALAADCggIDgAAAA==.',Ut='Uthredblack:BAAALAAECgIIAgAAAA==.',Ve='Velcheria:BAAALAAECgYIDAAAAA==.Velen:BAAALAAECgMIBQAAAA==.Velsæ:BAAALAAECgcIEQAAAA==.Venandí:BAACLAAFFIENAAIVAAUIkCQLAAAoAgAVAAUIkCQLAAAoAgAsAAQKgRwAAhUACAjcJj8AAIsDABUACAjcJj8AAIsDAAAA.Venmori:BAAALAAECgQIBAAAAA==.Verracious:BAAALAAECgMIBgAAAA==.Verrnarr:BAAALAAECgEIAQAAAA==.',Vi='Victoria:BAACLAAFFIEFAAINAAQI4xPABABWAQANAAQI4xPABABWAQAsAAQKgR0AAw0ACAjPI8wIAB4DAA0ACAjPI8wIAB4DABYAAQg1C3ATAD0AAAAA.Viora:BAAALAAECgUICQABLAADCggICAAHAAAAAA==.',Vo='Vogroth:BAAALAADCgcIDgAAAA==.Voidragon:BAAALAADCgMIAwAAAA==.',Vu='Vulkran:BAAALAADCgMIBAAAAA==.',We='Wehe:BAAALAAECgYIDwAAAA==.Wenz:BAAALAADCggICAABLAADCggICAAHAAAAAA==.',Wi='Wiccaa:BAAALAAECgEIAQAAAA==.Wildelife:BAAALAAECgQIBQAAAA==.Wilohmsford:BAAALAADCgMIBAAAAA==.Witherwing:BAAALAADCgUIBQAAAA==.',Wo='Wojak:BAAALAAECgMIAwAAAA==.',Wr='Wraith:BAAALAAECgYIDwAAAA==.Wrayth:BAABLAAECoEYAAMRAAgIBxrwGABiAgARAAgIBxrwGABiAgAUAAIInQvGaABPAAAAAA==.',Wu='Wulfsine:BAAALAAECgIIAgAAAA==.Wurstwasser:BAAALAAECggIBAAAAA==.',['Wá']='Wárlôrd:BAABLAAECoEWAAITAAcIDCAfFQB7AgATAAcIDCAfFQB7AgAAAA==.',Xa='Xavios:BAAALAAECgcIEQAAAA==.',Xh='Xhali:BAAALAADCgcIBwAAAA==.',Yi='Yinhen:BAAALAAECggICQAAAA==.',Yo='Yolosswagg:BAAALAAECgMIAwAAAA==.',Za='Zacre:BAAALAAECgEIAQAAAA==.Zandramos:BAAALAADCggICAAAAA==.Zarakrond:BAAALAADCgUIAwAAAA==.Zaytan:BAAALAAECgcIDwAAAA==.',Zh='Zherai:BAAALAAECgEIAQAAAA==.Zhonraja:BAAALAADCgcIDwAAAA==.',Zi='Ziggo:BAAALAADCggICAAAAA==.',['Ás']='Ásvaldr:BAAALAAECgYIEQAAAA==.',['Ðe']='Ðevlin:BAAALAAECgUICwAAAA==.',['Ós']='Ósiris:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end