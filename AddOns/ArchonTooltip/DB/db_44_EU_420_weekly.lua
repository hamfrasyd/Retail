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
 local lookup = {'Monk-Windwalker','Shaman-Restoration','Unknown-Unknown','DemonHunter-Vengeance','Priest-Holy',}; local provider = {region='EU',realm='DieNachtwache',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aerope:BAAALAADCgYICwAAAA==.',Ai='Ainê:BAAALAADCgYICAAAAA==.Aiolli:BAABLAAECoEVAAIBAAgIwB0GBADlAgABAAgIwB0GBADlAgAAAA==.',Al='Alekstrazsa:BAAALAAECgMIAwAAAA==.Alfredó:BAAALAAECgUICwAAAA==.Aliiza:BAAALAAECgIIAgAAAA==.Allanah:BAAALAAECgMIBQAAAA==.Altivo:BAAALAADCggIEAAAAA==.Alyciya:BAAALAAECgMIBgAAAA==.',Am='Amarice:BAAALAADCggIFwAAAA==.Amelton:BAAALAADCgcIBwAAAA==.',An='Anivia:BAABLAAECoEUAAICAAgIQBT2HgDYAQACAAgIQBT2HgDYAQAAAA==.Ankhano:BAAALAAECgMIBgAAAA==.Anluryn:BAAALAAECgYICgAAAA==.Antony:BAAALAAECgEIAQAAAA==.Anubis:BAAALAAECgcIDwAAAA==.Anyanka:BAAALAADCggIFwAAAA==.Anä:BAAALAADCgcIBwAAAA==.',Ar='Aranys:BAAALAAECgMIAwAAAA==.Ariati:BAAALAADCggICAAAAA==.Arjan:BAAALAAECgYICAAAAA==.Arkitoss:BAAALAADCggIFQAAAA==.Artaíos:BAAALAAECgYICwAAAA==.',As='Asená:BAAALAAECgIIAgAAAA==.Ashantria:BAAALAAECgUICQAAAA==.Asmodal:BAAALAAECgcIEAAAAA==.Assandri:BAAALAAECgMIBAAAAA==.Astenay:BAAALAADCgYIBgAAAA==.',At='Ateka:BAAALAAECgIIAgAAAA==.Athels:BAAALAADCgcIBgAAAA==.Athène:BAAALAAECgEIAgAAAA==.',Av='Averli:BAAALAADCgcICAAAAA==.',Aw='Awaken:BAAALAADCggIDwAAAA==.',Ax='Axolòtl:BAAALAAECgEIAQAAAA==.',Az='Azgeda:BAAALAAECgIIAQAAAA==.Azzumii:BAAALAAECgMIBQAAAA==.',Ba='Bacardiweiss:BAAALAAECgEIAQAAAA==.Baeldin:BAAALAAECgIIAgAAAA==.Balvenie:BAAALAADCggICAAAAA==.Barusu:BAAALAADCggIEAAAAA==.Barven:BAAALAAECgQIBwABLAAECggIFQABAMAdAA==.',Be='Benito:BAAALAADCggICAAAAA==.Bertraut:BAAALAADCggIFQAAAA==.Bestatterin:BAAALAAECgIIAgAAAA==.',Bi='Bilbop:BAAALAADCggIEgABLAAECgYICQADAAAAAA==.',Bl='Bloodface:BAAALAADCgcIBwAAAA==.Bloodmagicx:BAAALAADCgEIAQAAAA==.Bloodyhunta:BAAALAAECggIEQAAAA==.',Bo='Boddie:BAAALAAECgYICwAAAA==.Bodin:BAAALAAECgIIAgAAAA==.',['Bá']='Bánhellsing:BAAALAAECgMIBgAAAA==.',Ca='Cadêra:BAAALAADCggIFQABLAADCggIFgADAAAAAA==.Carmondai:BAAALAAECgIIAgAAAA==.',Ce='Celestiné:BAAALAAECgUIBgAAAA==.',Ch='Chalice:BAAALAAECggICAAAAA==.Chromaggus:BAAALAADCggIFAAAAA==.',Ci='Cipactli:BAAALAADCgMIAwAAAA==.',Co='Collesii:BAAALAAECgEIAQAAAA==.Combustion:BAAALAADCgcIBwAAAA==.Cosmóó:BAAALAAFFAIIBAAAAA==.',Cr='Crazynoc:BAAALAADCggICAAAAA==.Crizo:BAAALAAECgMIAwAAAA==.Crów:BAAALAADCggIFAAAAA==.',Cy='Cymbel:BAAALAAECgIIAgAAAA==.',['Cô']='Côsmò:BAAALAAECgIIAwABLAAFFAIIBAADAAAAAA==.Côsmòó:BAAALAADCggIDgABLAAFFAIIBAADAAAAAA==.',Da='Darkhell:BAAALAADCgMIBQABLAADCggIEAADAAAAAA==.Darkluná:BAAALAADCgMIAwABLAADCggIEAADAAAAAA==.Darktammy:BAAALAAECgYIBwAAAA==.Dartz:BAAALAADCgcIBwAAAA==.Datisdaelan:BAAALAAECgMIAwAAAA==.',De='Deckerdruid:BAAALAAECgQICAAAAA==.Dekyi:BAAALAAECgYICwAAAA==.Demenz:BAAALAADCggICAABLAAECggIBQADAAAAAA==.Deneria:BAAALAADCggIDgAAAA==.Destraya:BAAALAAECgYIDQAAAA==.Devilemii:BAAALAAECgMIAwAAAA==.Devilscircle:BAAALAAECgIIAgAAAA==.',Dh='Dhara:BAAALAAECgYIDgAAAA==.Dhearan:BAAALAADCggIDgAAAA==.Dhörte:BAAALAADCgcIDAAAAA==.',Dr='Dragonknîght:BAAALAADCgIIAgABLAADCgcIBwADAAAAAA==.Dralin:BAAALAADCgcIBwAAAA==.Dregorath:BAAALAAECgMIAwAAAA==.Drogea:BAAALAAECgEIAQAAAA==.',['Dà']='Dàrzz:BAAALAADCgcIDQAAAA==.',Ec='Ecolicin:BAAALAADCgcICQAAAA==.Ecrofy:BAAALAAECgIIAgAAAA==.',Ed='Edola:BAAALAAECgMIAwAAAA==.',Eg='Egó:BAAALAADCgcIDgAAAA==.',Ei='Eisenpranke:BAAALAADCgUIBQAAAA==.',El='Elanar:BAAALAADCggIFwAAAA==.Elisia:BAAALAADCgcIDAAAAA==.',En='Endzeít:BAAALAAECgYIDwAAAA==.Enion:BAAALAAECgEIAQAAAA==.',Er='Eriôn:BAAALAAECgMIBgAAAA==.',Es='Esil:BAAALAAECgEIAQAAAA==.Espinas:BAAALAADCgEIAQAAAA==.',Ex='Executioner:BAAALAAECgMIBgAAAA==.',Fa='Faleera:BAAALAAECgYIDgAAAA==.Faveyo:BAAALAAECgEIAQAAAA==.',Fi='Fixdas:BAAALAAECgYICAABLAAECggIFQABAMAdAA==.',Fl='Flamir:BAAALAADCggIEAAAAA==.Flatulencias:BAAALAADCgIIAgAAAA==.Flinrax:BAAALAADCgcIEQABLAAECgIIAgADAAAAAA==.',Fr='Freakaziod:BAAALAAECgYICAAAAA==.',Fu='Fulgidus:BAAALAADCgcIDAAAAA==.Fusselraupe:BAAALAAECgIIAgAAAA==.',Ga='Gadran:BAAALAADCggIFwAAAA==.Garax:BAAALAAFFAIIAgAAAA==.',Ge='Gealach:BAAALAADCgcIDQAAAA==.',Gi='Gingerly:BAAALAADCgEIAQAAAA==.',Gl='Gloigur:BAAALAAECgQICAAAAA==.',Gn='Gnomá:BAAALAAECggICAAAAA==.',Go='Goa:BAAALAAECgIIAgAAAA==.Gorma:BAAALAADCgMIAwAAAA==.',Gr='Gragagas:BAAALAAECgYIDwAAAA==.Grammlo:BAAALAADCggIFgAAAA==.Grimhold:BAAALAAECgEIAgAAAA==.Grlzilla:BAAALAADCgUIBQAAAA==.Grünbart:BAAALAADCggIDwAAAA==.',['Gâ']='Gâbríel:BAAALAAECgcIBgAAAA==.',Ha='Haldefuchs:BAAALAAECgMIBQAAAA==.Haraldegon:BAAALAAECggIDQAAAA==.',He='Hedrot:BAAALAAECgMIAwAAAA==.Heiligergorn:BAAALAADCggIDwAAAA==.Hexogon:BAAALAAECgYICgAAAA==.',Ho='Holyangel:BAAALAAECgUICQAAAA==.',['Hó']='Hóllýcróx:BAAALAAECgYIDAAAAA==.',Ic='Icéy:BAAALAAECgQIBgAAAA==.',Il='Ilfi:BAAALAAECgcIDwAAAA==.',In='Inasha:BAAALAADCgYICwABLAAECgYIDwADAAAAAA==.',Ir='Iresá:BAAALAAECgIIAgAAAA==.Irisy:BAAALAADCggIGAAAAA==.',It='Itsoktocry:BAAALAAECgMIAwAAAA==.',Iu='Ius:BAAALAADCgUIBgAAAA==.',Ja='Jacesa:BAAALAAECgMIAQAAAA==.Jaspira:BAAALAADCgYIBgAAAA==.',Je='Jenifa:BAAALAADCggIDAAAAA==.',Ju='June:BAAALAAECgcIEAAAAA==.Juniarius:BAAALAADCggICAAAAA==.',['Jø']='Jøøy:BAABLAAECoEkAAIEAAcIuCJEAwCnAgAEAAcIuCJEAwCnAgAAAA==.',Ka='Karademon:BAAALAAECgYIBwAAAA==.Karafoxxí:BAAALAAECgcICgAAAA==.Kararius:BAAALAADCgYIBgAAAA==.',Ke='Kerit:BAAALAADCgcICgAAAA==.',Kh='Khloe:BAAALAADCgEIAQABLAAECgYIDgADAAAAAA==.Khranosh:BAAALAADCggIDwAAAA==.',Ki='Kirié:BAAALAADCggIEAAAAA==.Kishou:BAAALAAECgYIDwAAAA==.Kitten:BAAALAADCggIGAAAAA==.',Kn='Kneder:BAAALAAECgMIAwAAAA==.',Kr='Krally:BAAALAADCggIBgAAAA==.Kroxas:BAAALAADCgYIBgAAAA==.',Ku='Kultian:BAAALAADCgcICAAAAA==.Kupece:BAAALAADCgcICgAAAA==.',['Ký']='Kýros:BAAALAADCgcIDAAAAA==.',La='Lachdana:BAAALAADCgEIAQAAAA==.Laodi:BAEALAAECgcIDAAAAA==.Laody:BAEALAADCggIDwABLAAECgcIDAADAAAAAA==.',Le='Lebenshilfe:BAAALAADCgcIFQAAAA==.Leodan:BAAALAAECggIDwAAAA==.',Li='Lightbreaker:BAAALAADCggICAAAAA==.Lighttank:BAAALAADCgIIAgAAAA==.Lilithel:BAAALAAECgIIAgAAAA==.',Lj='Ljóshjarta:BAAALAAECggIEQAAAA==.',Ll='Lluna:BAAALAADCggIEAAAAA==.',Lo='Lomk:BAAALAAECgMIAwAAAA==.Lorry:BAAALAAECgMIBgAAAA==.Lorwath:BAAALAADCggIEQABLAAFFAEIAQADAAAAAA==.Lotok:BAAALAADCggICAABLAAECggIBQADAAAAAA==.',Lu='Lucy:BAAALAAECgMIBgAAAA==.Lusí:BAAALAADCgYIBgAAAA==.',Ly='Lybärror:BAAALAAECgcIDwAAAA==.Lyron:BAAALAADCggIEAAAAA==.Lyrror:BAAALAAECgIIAgAAAA==.',['Lâ']='Lâkâstriâ:BAEALAAECgIIAgABLAAECgMIAwADAAAAAA==.',['Ló']='Lórellin:BAAALAADCggICAAAAA==.',['Lú']='Lúrtz:BAAALAADCggICAAAAA==.',['Lý']='Lýella:BAAALAAECgcIEQAAAA==.',Ma='Magicstrikz:BAAALAADCggICAABLAADCggIDwADAAAAAA==.Magnifik:BAAALAAECgMIBgAAAA==.Mahja:BAAALAADCgcIFQAAAA==.Malenia:BAAALAADCgcIEAAAAA==.Maliwhen:BAAALAAECgMIBgAAAA==.Malradon:BAAALAAECgcIDwAAAA==.Malunari:BAAALAAECgQIBAABLAAECgYICwADAAAAAA==.Malve:BAAALAADCgYIBgAAAA==.Mariéchen:BAAALAAECgYICgAAAA==.Marvelius:BAAALAADCgYICgAAAA==.Marx:BAAALAADCggIAgABLAADCggIBgADAAAAAA==.Masassi:BAAALAADCggIEwAAAA==.',Mi='Midi:BAAALAAFFAEIAQAAAA==.Mijá:BAAALAAECgcIDwAAAA==.Milamberevoz:BAAALAADCggICAAAAA==.Mitsûri:BAAALAADCgYIBgAAAA==.',Mu='Mullemauss:BAAALAADCggIEAAAAA==.',Na='Nachtarâ:BAAALAAECggIDAAAAA==.Nadeko:BAAALAADCggIFwABLAAECgMIAwADAAAAAA==.Naemii:BAAALAAECgYIBwABLAAECgMIAwADAAAAAA==.Nafine:BAAALAADCggIEQAAAA==.Naluzhul:BAAALAADCggIDgABLAADCggIDwADAAAAAA==.Narud:BAAALAADCggIDAAAAA==.Nayl:BAAALAADCggIFQAAAA==.',Ne='Neirenn:BAAALAAECgMIAwAAAA==.',Ni='Nimaly:BAAALAADCgcIEAAAAA==.',No='Noellesilva:BAAALAADCgUIBQAAAA==.Nostoros:BAAALAADCggICAAAAA==.',Nu='Numek:BAAALAADCgcIFQAAAA==.Nurgos:BAAALAADCgcIBwAAAA==.Nutriscore:BAAALAAECgMIAwAAAA==.',Ny='Nydara:BAAALAADCggIEAAAAA==.',['Né']='Nédriel:BAAALAADCggICQAAAA==.',Ob='Obvaylon:BAAALAAECgYICgAAAA==.',Oc='Occulco:BAAALAADCgYICAAAAA==.',Pa='Paldrian:BAAALAADCgcIBwAAAA==.',Pe='Pestilenz:BAAALAADCgcIBwAAAA==.',Pi='Piadora:BAAALAAECgYIDQAAAA==.Pitahaya:BAAALAAECgMIBgAAAA==.Pitelf:BAAALAADCggICQAAAA==.',Pu='Pudge:BAAALAADCggIDgABLAAECgYICAADAAAAAA==.Pumpbear:BAAALAADCgQIBAABLAADCggICAADAAAAAA==.Purplebtch:BAAALAADCggICAAAAA==.',['Pâ']='Pâllâx:BAAALAAECgcIDgAAAA==.',Qi='Qixidasleben:BAAALAADCggIDwAAAA==.',Qu='Quemen:BAAALAADCgUIBQAAAA==.Quirin:BAAALAADCggICgAAAA==.',Ra='Rahamut:BAAALAADCggICAAAAA==.Raidin:BAAALAAECgQIBAAAAA==.Raphna:BAAALAADCggIEAABLAAECgUICQADAAAAAA==.Rashkaja:BAAALAAECgcIDwAAAA==.Raziêl:BAAALAADCgcIFQAAAA==.Raìn:BAAALAAECggIBgAAAA==.',Re='Reanimatril:BAAALAADCgQIBQAAAA==.Remdk:BAAALAADCgYIBQABLAADCggIEAADAAAAAA==.Rendan:BAAALAAECgQICAAAAA==.',Rh='Rhoan:BAAALAAECgMIBgAAAA==.',Ri='Rivkâh:BAAALAAECgMIBAAAAA==.',Ro='Rongo:BAAALAADCgQIBAABLAAECgIIAgADAAAAAA==.',Ru='Rustý:BAAALAADCggIFQAAAA==.',['Rá']='Ráyven:BAAALAADCggIDgAAAA==.',['Râ']='Râgnàr:BAAALAADCggICAAAAA==.',['Rí']='Rían:BAAALAADCggIEAAAAA==.',Sa='Sagittâ:BAAALAADCgEIAQAAAA==.Saja:BAAALAAECgMIAwAAAA==.Salome:BAAALAAECgMIBAAAAA==.Sarlessa:BAAALAAECgIIAgAAAA==.Sayunarí:BAAALAAECgIIAgAAAA==.',Sc='Schmerzabt:BAAALAAECgMIBAAAAA==.Scöfi:BAAALAADCgUIBQAAAA==.Scööfii:BAAALAADCgYIBgAAAA==.',Se='Seal:BAAALAADCggICAAAAA==.Selistra:BAAALAADCgEIAQAAAA==.Selor:BAAALAADCgcIEQAAAA==.Senthi:BAAALAAECgMIAwAAAA==.Seràphina:BAAALAAECgIIAgAAAA==.',Sh='Shamsn:BAAALAAFFAIIAwAAAA==.Shavedbolts:BAAALAADCgYIBgAAAA==.Shelby:BAAALAAECgMIAwAAAA==.Shelldorina:BAAALAAECgIIAgAAAA==.Shianá:BAAALAADCggIDwAAAA==.Shinary:BAAALAADCgIIAgABLAADCgcIDQADAAAAAA==.Shinyqtxt:BAAALAADCgEIAQABLAAECgcIEAADAAAAAA==.Shynani:BAAALAADCggIDgAAAA==.',Sk='Skadh:BAAALAAECgcIEAAAAA==.Skavampir:BAAALAADCgcIBwABLAAECgcIEAADAAAAAA==.',Sl='Slinknar:BAAALAADCggICAAAAA==.Slyfôx:BAAALAAECgMIBAAAAA==.',So='Sohyon:BAAALAADCggICAAAAA==.Sombras:BAAALAADCgYIBgAAAA==.',St='Stormhammer:BAAALAADCgcIBwAAAA==.Stîcks:BAAALAADCggIEAAAAA==.',Sy='Sylamira:BAAALAADCgcIEAAAAA==.Sylvàna:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâturdây:BAAALAADCggIDwAAAA==.',['Sé']='Sénthi:BAAALAAECgIIAgAAAA==.',['Sê']='Sêgomo:BAAALAADCgYIBgAAAA==.',['Sí']='Sísra:BAAALAAECgMIBwAAAA==.',Ta='Talsanir:BAAALAADCggICAABLAAECggIBQADAAAAAA==.Tazo:BAAALAAECgYIDAAAAA==.',Te='Teremas:BAAALAAECgcIBwAAAA==.Teufelsbrut:BAAALAAECgMIAwAAAA==.',Th='Thadus:BAAALAAECgMIBgAAAA==.Thalrax:BAAALAADCgYIBgAAAA==.Theldain:BAAALAADCgEIAQABLAAECgYIDwADAAAAAA==.Theodor:BAAALAADCgUIAwAAAA==.Theoscha:BAAALAADCgEIAQAAAA==.Thytsai:BAAALAADCgIIAQABLAADCggIFwADAAAAAA==.',Ti='Tibbers:BAAALAADCgIIAgAAAA==.',Tk='Tkhühnchen:BAAALAAECgYIDQAAAA==.',To='Torîan:BAAALAADCggIFgAAAA==.Touka:BAAALAADCggIEAABLAAECgMIAwADAAAAAA==.',Tr='Tronnos:BAAALAADCgcIDAAAAA==.Trucky:BAAALAAECgYICQAAAA==.Tráinaider:BAAALAADCggICAAAAA==.',Ts='Tschabalala:BAAALAADCgYIBgAAAA==.Tsuki:BAAALAAECgIIAgAAAA==.',Ul='Ulfbërht:BAAALAADCgMIAgAAAA==.',Va='Valhalla:BAAALAAECgUIDgAAAA==.Vanbilbo:BAAALAAECgYICQAAAA==.Vaynak:BAAALAAECgYICgAAAA==.Vazruk:BAAALAADCggICAABLAADCggIDwADAAAAAA==.',Ve='Veldras:BAAALAADCggIEAAAAA==.Velindâs:BAAALAADCgYIBgABLAADCggIEAADAAAAAA==.Velocity:BAAALAAECgIIAgAAAA==.Verpflanzt:BAAALAAECgYIBwAAAA==.Verstohlen:BAAALAADCgMIAwABLAAECgYIBwADAAAAAA==.',Vi='Vilya:BAABLAAECoEXAAIFAAgILRyQCQChAgAFAAgILRyQCQChAgAAAA==.',Vo='Voy:BAAALAADCggICAAAAA==.',Vy='Vykas:BAAALAADCggIDwAAAA==.',['Và']='Vàla:BAAALAADCggIBgAAAA==.',Wa='Waldbändíger:BAAALAADCgYIBgAAAA==.Warlove:BAAALAADCgcIBwAAAA==.',We='Werfer:BAAALAADCgYIBQAAAA==.',Wh='Whisna:BAAALAADCgUIBQAAAA==.',Wi='Wienermädl:BAAALAADCgcIDQAAAA==.Witya:BAAALAAECgcICgAAAA==.',Wo='Worps:BAAALAAECgEIAQAAAA==.',['Wá']='Wándáá:BAAALAAECgQIBQAAAA==.',['Xé']='Xérxís:BAAALAADCgEIAQAAAA==.',Ya='Yasika:BAAALAADCgMIAwAAAA==.',Ye='Yennen:BAAALAAECgYICAAAAA==.Yetapeng:BAAALAADCgcIDQAAAA==.',Ze='Zellaris:BAAALAAECgEIAQAAAA==.Zelrin:BAAALAADCggICAAAAA==.Zeretha:BAAALAADCgcIBwAAAA==.Zesan:BAAALAAECgcICgAAAA==.',Zi='Zinnbart:BAAALAAECgMIAwABLAAECgUIBQADAAAAAA==.',Zo='Zoemii:BAAALAADCgYIBgAAAA==.',Zr='Zrotic:BAAALAAECgcIDwAAAA==.',Zu='Zualles:BAAALAAECgcIEAAAAA==.Zuckerpuppe:BAAALAAECgUIDQAAAA==.Zuia:BAAALAAECgcIDwAAAA==.',Zy='Zyasara:BAAALAAECgUIDQAAAA==.',['Zâ']='Zâth:BAAALAAECgIIAgAAAA==.',['Àn']='Ànubìs:BAAALAADCgcIDgABLAAECgcIDwADAAAAAA==.',['Âl']='Âlâstor:BAAALAADCgYICAAAAA==.',['Ân']='Ânubìs:BAAALAADCggICAABLAAECgcIDwADAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end