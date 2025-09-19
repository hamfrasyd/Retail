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
 local lookup = {'Unknown-Unknown','Monk-Brewmaster','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Evoker-Devastation','Rogue-Subtlety','Rogue-Assassination','Priest-Shadow','Priest-Holy','Warrior-Protection','Hunter-BeastMastery','Druid-Restoration','Druid-Balance','Paladin-Retribution','Mage-Arcane',}; local provider = {region='EU',realm='KultderVerdammten',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adradia:BAAALAADCggIEAAAAA==.Adratea:BAAALAADCgcICwAAAA==.',Af='Afk:BAAALAADCggIEwAAAA==.',Ag='Agathon:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ak='Akariel:BAAALAADCgcIDgAAAA==.Akári:BAAALAADCgYIBgAAAA==.',Al='Alaraa:BAAALAADCgEIAQAAAA==.Alexantria:BAAALAAECgcIDQAAAA==.Alfrothul:BAAALAADCgcIEwAAAA==.Allenor:BAAALAADCgEIAQAAAA==.Almî:BAAALAAECgMIBAAAAA==.',Am='Amduscias:BAAALAADCgUICQAAAA==.',An='Andoki:BAAALAAECgYICgAAAA==.Anilari:BAAALAAECgMIAwAAAA==.Anjanath:BAAALAAECgIIAgAAAA==.Anjàly:BAAALAAECgEIAQAAAA==.Anthar:BAAALAADCgQIBAAAAA==.',Aq='Aquacyrex:BAAALAAECgIIAwAAAA==.',Ar='Archowa:BAAALAADCgcICwAAAA==.Aristophat:BAAALAADCgcIDAAAAA==.',As='Ashtaka:BAAALAAECgYIEQAAAA==.Aswelden:BAAALAAECgcICgAAAA==.Asøk:BAAALAADCgIIAgAAAA==.',At='Athrian:BAABLAAECoEVAAICAAgIbyHRAgDoAgACAAgIbyHRAgDoAgAAAA==.',Au='Aurin:BAAALAADCgcIBwAAAA==.',Ay='Ayà:BAAALAAECgcIEAAAAA==.',Az='Azoc:BAAALAAECgMIAwAAAA==.',Ba='Backlit:BAAALAADCgcIBwAAAA==.Baelari:BAAALAAECgYICgAAAA==.Baella:BAAALAAECgYIBgAAAA==.Bahamuht:BAAALAAECgMIBAAAAA==.Baratoss:BAAALAADCgcIBwAAAA==.Barlogo:BAAALAAECgMIBAAAAA==.',Be='Bendagar:BAAALAADCgcIDQAAAA==.Benjihunt:BAAALAAECgYICwABLAAECggIFQADAKIcAA==.Benjiwarri:BAABLAAECoEVAAIDAAgIohxRDgCRAgADAAgIohxRDgCRAgAAAA==.',Bl='Blutsturm:BAAALAAECgMIAwAAAA==.',Bo='Boindîl:BAAALAADCggIBwAAAA==.Borold:BAAALAAECgcIDwAAAA==.Bountzi:BAAALAADCggICAABLAAECggICAABAAAAAA==.',Ca='Camîlla:BAAALAAECgMIAwAAAA==.Carel:BAABLAAECoEOAAIEAAgIHhpeBgBqAgAEAAgIHhpeBgBqAgAAAA==.Cascal:BAAALAADCgMIAwAAAA==.',Ce='Ceeroma:BAAALAADCgYICgAAAA==.Celaira:BAAALAAECgUIBQAAAA==.',Ch='Chacarron:BAAALAADCgcIBwABLAAECgYIDgABAAAAAA==.Chipendale:BAAALAADCggIDgAAAA==.Chippiee:BAAALAAECgMIBgAAAA==.',Cl='Cleoras:BAAALAAECgYIDgAAAA==.',Co='Corvex:BAAALAADCgcIBwAAAA==.',Cr='Crxzydk:BAAALAAECgYICAAAAA==.',['Có']='Cóker:BAAALAAECggIEQAAAA==.',Da='Dabidoo:BAAALAAECgMIAwAAAA==.Dalrak:BAAALAADCgYICwAAAA==.Danuris:BAAALAADCgYIBgAAAA==.Darliko:BAAALAADCgIIAgAAAA==.Daronil:BAABLAAECoEVAAMEAAgIlhUqDwDtAQAEAAgIUxQqDwDtAQAFAAcIug8AAAAAAAAAAA==.Darragh:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',De='Deliyah:BAAALAAECgEIAQAAAA==.Demala:BAAALAAECgQIBAAAAA==.Demistraza:BAAALAAECgQIBQAAAA==.Demonsadi:BAAALAAECgMIBQAAAA==.Demonyo:BAAALAAECgcIBwAAAA==.Denji:BAAALAADCgMIAwAAAA==.Dersonne:BAAALAADCggIDAAAAA==.Deucalion:BAAALAADCgcIBwAAAA==.Devilon:BAAALAAECgYIDAAAAA==.Devius:BAAALAAECgMIBAAAAA==.',Di='Dilari:BAAALAAECgMIAwABLAAECgYIBwABAAAAAA==.Dilaro:BAAALAAECgYIBwAAAA==.',Do='Dorgrin:BAAALAADCggIEgAAAA==.',Dr='Dracthyra:BAAALAADCgUICgAAAA==.Draggow:BAABLAAECoEXAAIGAAgIPCadAAB3AwAGAAgIPCadAAB3AwABLAAFFAIIAgABAAAAAA==.Druideheinz:BAAALAADCgcIBwAAAA==.Drôll:BAAALAAECgMIBAAAAA==.',Du='Dunter:BAAALAADCgcIBwAAAA==.',Ed='Edichán:BAAALAAECgMIAwAAAA==.',Eh='Ehmi:BAABLAAECoEXAAMHAAgIfBleBAAqAgAIAAcIWBsuEAAyAgAHAAgIBxNeBAAqAgAAAA==.',El='Elixiu:BAAALAAECgIIAwAAAA==.Elkje:BAAALAADCggIEwABLAADCggICAABAAAAAA==.Eltharon:BAAALAAECgMIBAAAAA==.Elunasil:BAAALAADCgEIAQABLAADCgcIEAABAAAAAA==.',Em='Emol:BAAALAAECgEIAQAAAA==.',En='Enno:BAAALAAECgcIEAAAAA==.Envi:BAAALAAFFAIIAgAAAA==.',Er='Erinnya:BAAALAADCggIDAAAAA==.',Fe='Feez:BAAALAAECgUIBgAAAA==.Felicea:BAAALAAECgEIAQAAAA==.Fenja:BAAALAAECgEIAQAAAA==.Feuil:BAABLAAECoEXAAMJAAgIlySuAwAxAwAJAAgIlySuAwAxAwAKAAcIgx4MEQBDAgAAAA==.',Fh='Fhel:BAAALAADCggICAAAAA==.',Fi='Fighjo:BAAALAAECgYICgAAAA==.Filix:BAAALAAECgMIAwAAAA==.Fishbonez:BAAALAADCggICQAAAA==.',Fl='Florin:BAABLAAECoEWAAIKAAgInxlEDwBYAgAKAAgInxlEDwBYAgAAAA==.',Fr='Frànbubble:BAAALAAECgYICgAAAA==.Frêssh:BAAALAAECgYICQAAAA==.',Fu='Funfool:BAAALAAECgYICgAAAA==.Furion:BAAALAADCgQIBwAAAA==.',Ga='Ganzo:BAAALAAECgYICgAAAA==.Garguraz:BAAALAADCgcICwAAAA==.Garune:BAAALAADCgcIDQABLAAECgIIAgABAAAAAA==.',Ge='Gelimer:BAAALAADCgcIBwAAAA==.',Gl='Glàdíus:BAAALAADCggIEAAAAA==.',Go='Goldenswoord:BAAALAADCgUICAAAAA==.',Gr='Grecosa:BAAALAAECgIIAwAAAA==.Grimfang:BAAALAADCgcIDwAAAA==.Grizzlysin:BAAALAADCgcIDQAAAA==.Gromz:BAAALAAECgYIDAAAAA==.',Gu='Gufte:BAAALAAECggICQAAAA==.Guidan:BAAALAADCggICAAAAA==.',['Gô']='Gôr:BAAALAAECgIIAgAAAA==.',['Gö']='Göndula:BAAALAADCggICQAAAA==.',Ha='Hagitakamich:BAAALAADCgcIEAAAAA==.',He='Headlock:BAAALAADCgEIAQAAAA==.Helgå:BAAALAAECgEIAQAAAA==.',Hi='Hiloria:BAAALAADCgcIBwAAAA==.',Ho='Hornochs:BAAALAADCgYIBgAAAA==.',Hu='Hu:BAAALAAECgYIDgAAAA==.Hufenjunge:BAABLAAECoEWAAILAAgIzh7gAwDVAgALAAgIzh7gAwDVAgAAAA==.',Il='Ilanah:BAAALAADCgYIBgAAAA==.Illandore:BAAALAAECgYICgAAAA==.',In='Inoúla:BAAALAADCgcIBwAAAA==.Inuk:BAAALAAECgIIAgAAAA==.',Iz='Izomoncherie:BAAALAADCgcIBwAAAA==.',Ja='Jazabella:BAAALAAECgcIDwAAAA==.',Jo='Jolo:BAABLAAECoEUAAIMAAYI8x9BFgA/AgAMAAYI8x9BFgA/AgAAAA==.Jolreal:BAAALAAECgYIDgAAAA==.Joññy:BAAALAAECgMIBAAAAA==.',Ju='Juros:BAAALAADCgYIBgAAAA==.',Ka='Kagall:BAAALAAECgYICQAAAA==.Kaitoo:BAAALAADCggICAAAAA==.Kaleidos:BAAALAAECgMIBAAAAA==.Karaschie:BAAALAAECgcIEQAAAA==.Karimor:BAAALAADCgYIBgAAAA==.Kathlynna:BAAALAAECgMIAwAAAA==.Kazdul:BAAALAADCgcIBgABLAAECgYIDgABAAAAAA==.',Ke='Keald:BAAALAADCgUIBQAAAA==.Kejadyr:BAAALAAECgMIBAAAAA==.Keksmistress:BAAALAAECgEIAQAAAA==.Keori:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.',Ki='Killder:BAAALAADCgUIBQAAAA==.Kirell:BAAALAADCggICAAAAA==.Kirigo:BAABLAAECoEXAAINAAgIKxqYCgBgAgANAAgIKxqYCgBgAgAAAA==.',Kn='Knani:BAAALAAECgMIAwAAAA==.',Ko='Kobedin:BAAALAADCgYIBgAAAA==.Kolarak:BAAALAAECgYICgAAAA==.Koli:BAAALAAECgYIBgAAAA==.',Kr='Krônos:BAAALAAECgEIAQAAAA==.',Ku='Kuraj:BAAALAADCggIDwAAAA==.Kurokuma:BAAALAAECgMIAwAAAA==.',Ky='Kyressa:BAAALAADCgYIBgAAAA==.',['Kí']='Kírá:BAAALAAECgIIAgAAAA==.',['Kî']='Kîmbaley:BAAALAADCgQIAwAAAA==.',La='Lanthas:BAAALAADCgMIAwAAAA==.Laschy:BAAALAAECgMIAwAAAA==.Laurana:BAAALAADCggIEgAAAA==.Laureen:BAAALAAECgYIDgAAAA==.',Le='Lefarion:BAAALAADCgUICgAAAA==.Legosch:BAAALAADCgYIBgAAAA==.',Li='Licay:BAAALAADCgYIBgAAAA==.Lightson:BAAALAAECgEIAQAAAA==.Linaera:BAAALAAFFAIIBAAAAA==.Lionedda:BAAALAAECgYICQAAAA==.',Lo='Loliksdeh:BAAALAAECgYIDgAAAA==.Lorelaya:BAAALAAECgMIAwAAAA==.Lorleen:BAAALAAECgMIBAAAAA==.',Lu='Luvilyen:BAAALAADCggIEwAAAA==.Luxa:BAAALAAECgEIAQAAAA==.',['Lú']='Lúna:BAAALAADCgIIAgAAAA==.',Ma='Machmantis:BAAALAAECgEIAQABLAAECggIFwAHAHwZAA==.Madwarr:BAAALAAECgcIEQAAAA==.Magia:BAAALAAECgYICgAAAA==.Majak:BAAALAADCggIEwAAAA==.Malicia:BAAALAAECgMIAwAAAA==.Manadis:BAAALAADCgcIEwAAAA==.Mandalich:BAAALAADCgYIBgAAAA==.Mandelmane:BAAALAADCgEIAQAAAA==.Mandrake:BAAALAADCgcIEAAAAA==.Massanie:BAAALAAECgMIBwAAAA==.Mayurî:BAAALAAECggIDgAAAA==.',Me='Meijra:BAAALAADCggIGAAAAA==.Melwumonk:BAAALAAECgQIBgAAAA==.Mettîgel:BAAALAADCgcIBgAAAA==.Meuchex:BAAALAAECgMIAwAAAA==.',Mi='Miiá:BAAALAADCgYIBgAAAA==.Minicharles:BAAALAADCggICAABLAAECgcICgABAAAAAA==.Miraculiixx:BAAALAADCggICQAAAA==.',Mo='Mondprinzess:BAAALAADCgcIEAAAAA==.Monáchá:BAAALAADCggICAAAAA==.Moxxly:BAAALAADCgMIAwAAAA==.',Mu='Muhkulo:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Muhtig:BAAALAAECgUIBwAAAA==.',['Mä']='Märtyria:BAAALAAECgIIAgAAAA==.',['Mó']='Móón:BAAALAAECgYIDgAAAA==.',Na='Nahida:BAAALAAECgYICgAAAA==.Nanamií:BAAALAAECgEIAQAAAA==.Narikela:BAAALAAECgYICgAAAA==.Narrow:BAAALAAFFAIIAgAAAA==.',Ne='Nealla:BAAALAADCgcICQAAAA==.Necrosia:BAAALAAECgcICgAAAA==.Nekoyasei:BAABLAAFFIEFAAMNAAMI/xRFAgD6AAANAAMI/xRFAgD6AAAOAAEIggHECgA0AAAAAA==.Nerîell:BAAALAAECgEIAQAAAA==.Nevertrap:BAAALAADCggICAAAAA==.Neyrdok:BAAALAADCgYIBgABLAAECgcIEQABAAAAAA==.',Ni='Niffty:BAAALAADCgYIBgAAAA==.Nilsa:BAAALAADCgcIDAAAAA==.',Nn='Nnoitra:BAAALAAECgEIAQAAAA==.',No='Nohand:BAAALAADCgcIBwAAAA==.Noshok:BAAALAAECgQIBgAAAA==.Nostii:BAAALAADCggIDgAAAA==.Notaq:BAABLAAECoEXAAIPAAgIVCbWAACFAwAPAAgIVCbWAACFAwAAAA==.',['Nê']='Nêas:BAAALAAECgYICAAAAA==.',Oc='Ociussosus:BAAALAADCgMIAwAAAA==.',Od='Odrando:BAAALAADCgYIDAABLAADCggIEAABAAAAAA==.',Oh='Oh:BAAALAAECgIIBAAAAA==.',On='Ongrin:BAAALAADCgcIEwAAAA==.Onugh:BAAALAADCgYIBgAAAA==.',Or='Orkzäpfchen:BAAALAADCgcIBwAAAA==.Orphileindos:BAAALAADCgQIBAAAAA==.',Ov='Overdozer:BAAALAADCggICgAAAA==.',Pa='Pandemor:BAAALAAECgIIAgAAAA==.Paran:BAAALAADCggIFQAAAA==.Paruktul:BAAALAAECgEIAQAAAA==.',Pi='Pixone:BAAALAAECgYIBgAAAA==.',Pl='Plampel:BAAALAADCgUIBQAAAA==.',Po='Polyphemus:BAAALAADCggICAAAAA==.',Pr='Prexqq:BAAALAADCggICwAAAA==.Prulig:BAAALAAECgYIDgAAAA==.',['Pé']='Pénthesilea:BAAALAAECgYIBgAAAA==.',Qa='Qaigon:BAAALAADCgIIAgAAAA==.',Qw='Qwelsi:BAAALAAECgUIBQAAAA==.',Ra='Raldrak:BAAALAAECgEIAgAAAA==.Rapuun:BAAALAAECgIIAwAAAA==.Raychel:BAAALAAECgUICAAAAA==.',Re='Reekha:BAAALAAECgEIAQAAAA==.Renlarian:BAAALAADCggICAAAAA==.Reínerzufall:BAAALAAECgIIAgAAAA==.',Ri='Riya:BAAALAAECgYICgAAAA==.',Ro='Rokdan:BAAALAAECgMIAwAAAA==.Rondâ:BAAALAAECgMIAwAAAA==.',Ru='Russel:BAAALAAECgcIDgAAAA==.Ruvik:BAAALAAECgMIBgAAAA==.',Ry='Ryokaji:BAAALAADCgcICAAAAA==.',Sa='Sahri:BAAALAADCgYIBgAAAA==.Sanadriel:BAAALAADCgMIAwAAAA==.Sanraku:BAAALAAECggIDAAAAA==.Sathivae:BAAALAADCggIEwAAAA==.',Sc='Schlîtzohr:BAAALAAECgIIAgAAAA==.Schuäänzmän:BAAALAADCgEIAQAAAA==.Scrajak:BAAALAAECgEIAQAAAA==.',Se='Seuchenwind:BAAALAAECgQIBgAAAA==.Seyqt:BAAALAADCgQIBAAAAA==.',Sh='Shaah:BAAALAADCggICAAAAA==.Shaylaah:BAAALAADCgcICwAAAA==.Shenlo:BAAALAADCgEIAQAAAA==.Shenlong:BAAALAADCggICAAAAA==.Shiasa:BAAALAADCggIDAAAAA==.Shyrianâ:BAAALAAECgEIAQAAAA==.',Si='Sichelhammer:BAAALAAECgMIAwAAAA==.Sickshots:BAAALAAECgUIBQAAAA==.Silare:BAAALAAECgEIAQAAAA==.Simâr:BAAALAAECgcIDwAAAA==.Sintheras:BAAALAADCgYIDAAAAA==.',Sk='Skizzl:BAAALAAECgEIAQAAAA==.',Sl='Slater:BAAALAADCgEIAQAAAA==.Slaxxstarsha:BAAALAADCgEIAQAAAA==.Slaxxstarwar:BAAALAADCgYIBgAAAA==.Slickdaddy:BAAALAAECgMIBQAAAA==.',Sn='Snaxace:BAAALAAECgMIAwAAAA==.',So='Sokeni:BAAALAADCgcIBwAAAA==.Solu:BAAALAADCggICAAAAA==.Sorenta:BAAALAADCgMIBAAAAA==.',Sq='Squäbble:BAAALAAECgYIDwAAAA==.',Sy='Syre:BAAALAAECgIIAgAAAA==.',['Sâ']='Sâmolia:BAAALAAECgMIAwAAAA==.',['Sé']='Séraphéná:BAAALAAECgMIBQAAAA==.',Ta='Tabanddot:BAAALAAECgEIAQAAAA==.Tahlis:BAAALAAECgMIBAAAAA==.Tainois:BAAALAAECgEIAQAAAA==.Tanlia:BAAALAAECgYICgAAAA==.Tantela:BAAALAADCggIFAAAAA==.',Tc='Tchilar:BAAALAADCgcIEwAAAA==.',Te='Terônas:BAAALAAECgMIBAAAAA==.',Th='Thrun:BAAALAAECgIIAgAAAA==.',Ti='Timox:BAAALAADCgQIBAAAAA==.Tintax:BAAALAAECgYICwAAAA==.',To='Togur:BAAALAAECgYIDQAAAA==.Tombkiller:BAAALAAECgYICQAAAA==.',Tr='Truntio:BAAALAADCgQIBAAAAA==.',Ts='Tsheyari:BAABLAAECoEXAAIQAAgI7h+YDwCyAgAQAAgI7h+YDwCyAgAAAA==.',Tu='Tur:BAAALAADCggIDwAAAA==.',Ty='Tyriane:BAAALAAECgIIBAAAAA==.',['Tì']='Tìbbìt:BAAALAAECgEIAQAAAA==.',Ul='Ultraloard:BAAALAADCgcIBwAAAA==.',Un='Uniquex:BAAALAAECgMIBAAAAA==.',Va='Valeri:BAAALAAECgMIBgAAAA==.Valkyrja:BAAALAAECgQIBAAAAA==.',Ve='Vertiko:BAAALAAECggIDwAAAA==.',Vi='Vierkanter:BAAALAAECgQIBAAAAA==.Vimzo:BAAALAADCggICAAAAA==.Vine:BAAALAAECgcICAAAAA==.Violaalexiel:BAAALAADCggICwAAAA==.',Vl='Vlubbax:BAAALAAECgYIDQAAAA==.',Vo='Vortac:BAAALAAECgYICgAAAA==.',Vu='Vuldurdeath:BAAALAAECgYIDAAAAA==.Vulkanius:BAAALAADCgMIAwAAAA==.',['Vó']='Vóie:BAAALAAECgMIBQAAAA==.',Wa='Waltraudt:BAAALAAECgYIDQAAAA==.',We='Weroth:BAAALAADCgEIAQAAAA==.',Wi='Wispal:BAAALAAECgYICgAAAA==.',Wo='Wohgan:BAAALAAECgMIBAAAAA==.Worloc:BAAALAADCgcIBwAAAA==.',Xe='Xelestin:BAAALAADCgYIBgAAAA==.Xena:BAAALAAECggIEgAAAA==.Xeremiozar:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',Xy='Xyris:BAAALAAECgIIAwAAAA==.',Ys='Ysondré:BAAALAAECgEIAQAAAA==.',Yu='Yunxu:BAAALAAECgIIAgAAAA==.',Yv='Yvainè:BAAALAAECgMIBAAAAA==.',['Yâ']='Yâri:BAAALAAECgEIAQABLAAECggIFwAQAO4fAA==.',Za='Zaphir:BAAALAADCgcIBwAAAA==.Zarantor:BAAALAADCggIEAAAAA==.Zaubberer:BAAALAAECgYIDgAAAA==.',Ze='Zedora:BAAALAADCgUIBQAAAA==.Zeizt:BAAALAAECgQIBgAAAA==.',Zu='Zuan:BAAALAADCgIIAgAAAA==.Zuria:BAAALAAECgIIAwAAAA==.',Zw='Zwonki:BAAALAAECgYIDgAAAA==.',['Zì']='Zìm:BAAALAAECgMIBQAAAA==.',['Zò']='Zòrn:BAAALAAECgMIBAAAAA==.',['Âm']='Âmlîn:BAAALAAECgIIAgAAAA==.',['Æz']='Æz:BAAALAAECgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end