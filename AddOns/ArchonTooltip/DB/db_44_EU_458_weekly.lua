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
 local lookup = {'Unknown-Unknown','Rogue-Assassination','Druid-Balance','Evoker-Preservation',}; local provider = {region='EU',realm='Onyxia',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adiline:BAAALAADCgcIBwAAAA==.',Af='Afflíction:BAAALAADCggICAAAAA==.',Ai='Aiassit:BAAALAAECgMIAQAAAA==.',Ak='Ako:BAAALAADCggICAAAAA==.',Al='Aliciakeys:BAAALAAECgIIAgAAAA==.',Am='Amanatîdis:BAAALAAECgMIBQAAAA==.Amphdruid:BAAALAADCgQIBAAAAA==.Amunet:BAAALAADCgcIDgAAAA==.',Aq='Aquickmoa:BAAALAADCggIDgAAAA==.',Ar='Archiatrà:BAAALAADCggIEgAAAA==.Ariun:BAAALAADCgUIBgABLAAECgYIBgABAAAAAA==.Arivey:BAAALAAECgQIBAAAAA==.Arrotec:BAAALAAECgMIAwAAAA==.Artharia:BAAALAADCggICAAAAA==.Arumad:BAAALAAECgMIAgAAAA==.Aráco:BAAALAAECgMIAwAAAA==.',As='Asphyxie:BAAALAAECgIIAgAAAA==.',Av='Avíana:BAAALAAECgQIBwAAAA==.',Ay='Ayazato:BAAALAADCggICwAAAA==.',Az='Azoh:BAAALAAECgMIAwAAAA==.Azurweib:BAAALAAECgYIDAAAAA==.Azurîon:BAAALAAECgIIAgAAAA==.',Ba='Balph:BAAALAADCgcIBwAAAA==.Baltoch:BAAALAAECgIIAQAAAA==.Barbâra:BAAALAAECgMIAwAAAA==.',Be='Belfort:BAAALAADCggICgAAAA==.',Bl='Blackstâr:BAAALAADCggIEwABLAAECgEIAQABAAAAAA==.Bloodydh:BAAALAADCgEIAQAAAA==.Bltchimacow:BAAALAADCgcIBwAAAA==.Blàckstâr:BAAALAAECgEIAQAAAA==.',Bo='Boeppo:BAAALAADCggICwAAAA==.Bonifabius:BAAALAAECgEIAQAAAA==.',Br='Braunbaer:BAAALAADCgcICwAAAA==.Brixz:BAAALAADCgEIAgAAAA==.Brîght:BAAALAADCggICgAAAA==.',Bw='Bwonsamdin:BAAALAAECgUICAAAAA==.',['Bä']='Bämaggrodown:BAAALAAECgYIBgAAAA==.',['Bó']='Bóppo:BAAALAADCgcIDgAAAA==.',['Bû']='Bûlletproof:BAAALAAECgIIAwAAAA==.',Ca='Caesurae:BAACLAAFFIEHAAICAAMI6xYLAgAfAQACAAMI6xYLAgAfAQAsAAQKgRwAAgIACAhdJQsBAFoDAAIACAhdJQsBAFoDAAAA.Calico:BAAALAADCggICAAAAA==.Califo:BAAALAAECgEIAgAAAA==.Canim:BAAALAADCgIIBAAAAA==.Capitanenter:BAAALAADCgcIBwAAAA==.Carnáge:BAAALAAECgMIAwAAAA==.',Ce='Celestra:BAAALAADCgcIDAAAAA==.Cemtleman:BAAALAAECgIIAgAAAA==.Cerberon:BAAALAAECgYIDgAAAA==.',Ch='Chaosnight:BAAALAAECgYICgAAAA==.Cheguevarri:BAAALAADCgcICgAAAA==.Chuggernautz:BAAALAADCgcIEgAAAA==.',Co='Corez:BAAALAAECgYICQAAAA==.Corpor:BAAALAAECgIIAwAAAA==.Cosé:BAAALAADCgYIBgAAAA==.',Cy='Cyberchief:BAAALAAECgQICwAAAA==.Cynrix:BAAALAADCgYIBgAAAA==.Cyreen:BAAALAADCggICAAAAA==.',['Câ']='Câmú:BAAALAADCggIDgAAAA==.',['Cí']='Cíbo:BAAALAADCggICgAAAA==.',['Cî']='Cîke:BAAALAADCggIEwAAAA==.',['Cô']='Côse:BAAALAADCgcIBwAAAA==.',Da='Dabi:BAAALAAECgcIDQAAAA==.Dachlâtte:BAAALAADCgcIDQAAAA==.Daggi:BAAALAADCgcIBwAAAA==.Darkthúnder:BAAALAADCgYIBgAAAA==.',De='De:BAAALAAECgcIDgAAAA==.Deadscream:BAAALAAECgQICwAAAA==.Deathdoor:BAAALAADCgUIBwAAAA==.Dertank:BAAALAAECgIIAgAAAA==.Desølated:BAAALAADCggIFQAAAA==.',Di='Dietzsche:BAAALAAECgIIAwAAAA==.',Do='Domirex:BAAALAADCggIFgAAAA==.Doomedhunter:BAAALAADCgMIAwABLAAECgQIBwABAAAAAA==.Doremir:BAAALAADCgcIBwAAAA==.',Dr='Dracwulf:BAAALAAECgMIAwAAAA==.Dronéx:BAAALAADCgUIBgAAAA==.',Du='Dunkelheít:BAAALAAECgYICQAAAA==.',['Dä']='Dämolocke:BAAALAADCgcICwAAAA==.Dämonion:BAAALAAECgMIBQAAAA==.',Ea='Earilalith:BAAALAAECgMIBAAAAA==.',Eg='Egirl:BAAALAAECgQIBAAAAA==.Egirlremix:BAAALAAECgMIAwAAAA==.',El='Ellmo:BAAALAAECgEIAgAAAA==.Eléctrâ:BAAALAAECgIIBAAAAA==.',Em='Emeraldâ:BAAALAADCgUIBQAAAA==.',En='Enkon:BAAALAADCgYICgAAAA==.',Er='Erlotril:BAAALAAECgIIBAAAAA==.Eráfin:BAAALAAECgIIBAAAAA==.',Et='Etho:BAAALAAECgIIAQAAAA==.',Fa='Fanshuli:BAAALAAECgEIAQAAAA==.Fartseer:BAAALAADCgYICwAAAA==.',Fl='Flexd:BAAALAADCgcIBwAAAA==.',Fr='Freezie:BAAALAADCgUIBQAAAA==.Fródò:BAAALAADCgYIBgABLAAECgcIFAADABkVAA==.',['Fâ']='Fârewell:BAAALAADCggIBgAAAA==.',Ga='Gabbadin:BAAALAAECgYIBgABLAAECgcIFAADABkVAA==.Gahine:BAAALAADCgUIBAAAAA==.',Ge='Gehirntod:BAAALAAECgQICgAAAA==.Gelo:BAAALAADCgIIAgAAAA==.',Gi='Ginaro:BAAALAADCggICAAAAA==.Gipsylord:BAAALAADCggICAAAAA==.',Gl='Glaphanji:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Go='Goldochse:BAAALAAECgIIAgAAAA==.Gorle:BAAALAADCggIDwAAAA==.Gorlucy:BAAALAAECgMIAwAAAA==.Gorly:BAAALAADCggIEwAAAA==.',Gr='Gral:BAAALAADCggICQABLAAECgIIAQABAAAAAA==.Grimmtor:BAAALAADCgcIEwAAAA==.Großerorc:BAAALAAECgMIAQAAAA==.Grumlii:BAAALAADCgMIAwAAAA==.Gráishak:BAAALAAECgMIBAAAAA==.',Gu='Gumbo:BAAALAADCgcIBwAAAA==.Gustav:BAAALAADCggIFQAAAA==.',['Gé']='Gérhard:BAAALAADCggICAAAAA==.',['Gí']='Gímly:BAAALAAECgEIAQAAAA==.',['Gö']='Göttergleich:BAAALAADCgcICwAAAA==.',Ha='Haborym:BAAALAADCgUIBQAAAA==.Hanura:BAAALAADCggIFQAAAA==.',Hd='Hdl:BAAALAADCgYIBgAAAA==.',He='Heangh:BAAALAADCgYICAAAAA==.Hexelulu:BAAALAADCggICAAAAA==.',Ho='Hoshpack:BAAALAADCgYICAAAAA==.',Hp='Hpbaxxter:BAAALAAECgYICwABLAAECgYIDAABAAAAAA==.',Hu='Huntess:BAAALAAECgUICQAAAA==.',['Hö']='Höllgrrosh:BAAALAADCgEIAQAAAA==.',['Hù']='Hùmmel:BAAALAAECgcIDQAAAA==.Hùntsmèn:BAAALAAECgMICAAAAA==.',Ic='Ichígó:BAAALAADCggIDQABLAAECggIAgABAAAAAA==.',Il='Ilidian:BAAALAAECgMIAwAAAA==.',Im='Imhotepsis:BAAALAADCggIFwAAAA==.',In='Invíctùs:BAAALAAECggIDQAAAA==.',Ir='Iryut:BAAALAAECgQIBgAAAA==.',Is='Isehnix:BAAALAAECgIIBAAAAA==.',It='Itsatraap:BAAALAADCgcIBQAAAA==.',Ja='Jahnna:BAAALAADCggIDgAAAA==.Javae:BAAALAAECgMIAwAAAA==.Jaýdí:BAAALAADCggIDgAAAA==.',Je='Jeeckyll:BAAALAADCggIEAAAAA==.Jeffbenzos:BAAALAAECgQIBQAAAA==.Jetztknallts:BAAALAADCgcIBwAAAA==.',Ji='Jinzznope:BAAALAAECgYICwAAAA==.',Ju='Juicylucy:BAAALAAECgMIAwAAAA==.Justpassion:BAAALAAECgIIBAAAAA==.',Ka='Kaestel:BAAALAAECgYICgAAAA==.Kaiman:BAAALAAECgMIAwAAAA==.Kalih:BAAALAAECgUIEAAAAA==.Kalisie:BAAALAAECgEIAQAAAA==.Kampfpanda:BAAALAADCgUIBQAAAA==.Karah:BAAALAADCggICAAAAA==.Karola:BAAALAAECgIIAgAAAA==.Kashen:BAAALAAECgIIAgAAAA==.',Ke='Keeia:BAAALAADCggICAAAAA==.Keso:BAAALAAECgIIBAAAAA==.Kesora:BAAALAADCggICAAAAA==.',Kh='Khane:BAAALAADCggIDwABLAAECgQIBAABAAAAAA==.Kharesia:BAAALAAECgQIBAAAAA==.Khun:BAAALAADCgYIDAABLAAECgMIBQABAAAAAA==.',Ki='Kiaris:BAAALAAECgYIBgAAAA==.Kibô:BAAALAAECggIAgAAAA==.Kiwiz:BAAALAADCgUIBQAAAA==.',Ko='Kodishot:BAAALAAECgIIAgAAAA==.',Ku='Kudou:BAAALAAECggIDwAAAA==.Kuksi:BAAALAAECgYIDAAAAA==.Kulane:BAAALAADCgcIBwAAAA==.',Ky='Kyrlill:BAAALAADCggICAAAAA==.',['Kà']='Kàkashi:BAAALAAECgUIBwAAAA==.',La='Law:BAAALAAECgIIAgAAAA==.',Le='Leonidas:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Leyras:BAAALAADCggIEAAAAA==.',Li='Liantriss:BAAALAAECgEIAQAAAA==.Liqquor:BAAALAADCgEIAQAAAA==.Lisànna:BAAALAADCggICAAAAA==.',Lo='Lokras:BAAALAADCgcICAAAAA==.Loreal:BAAALAAECgIIBAAAAA==.Loryl:BAAALAADCgcIDQABLAAECgQIBAABAAAAAA==.',Lu='Luckos:BAAALAADCgcIBwAAAA==.Luhmy:BAAALAAECgMIAwAAAA==.',Ly='Lysianne:BAAALAAECgIIAwAAAA==.',['Lê']='Lêvâná:BAAALAAECgcIEQAAAA==.',['Ló']='Lótus:BAAALAADCgcIEQAAAA==.',['Lô']='Lôcý:BAAALAADCgcICgABLAAECgMIBQABAAAAAA==.',['Lû']='Lûsringa:BAAALAADCgcIDAABLAAECgMIBQABAAAAAA==.',Ma='Mabelâ:BAAALAAECgIIBQAAAA==.Machtvoll:BAAALAADCgcIBwAAAA==.Magedrop:BAAALAAECgMIAwAAAA==.Magnador:BAAALAADCggICwAAAA==.Mahakam:BAAALAADCggICAAAAA==.Manajunkie:BAAALAADCggICAAAAA==.Maxximage:BAAALAADCgQIBAAAAA==.Maxximus:BAAALAADCgYIBgAAAA==.Maxxirogue:BAAALAADCggICAAAAA==.',Me='Meadlife:BAAALAADCgUIBQAAAA==.Meistereder:BAAALAADCgYIBgABLAADCgcIEQABAAAAAA==.',Mi='Milamber:BAAALAADCgcICQABLAAECgIIAgABAAAAAA==.Milamberdudu:BAAALAADCggIEAABLAAECgIIAgABAAAAAA==.Milamberevo:BAAALAAECgIIAgAAAA==.Milambersham:BAAALAADCgcIDAABLAAECgIIAgABAAAAAA==.Mimsyy:BAAALAADCggICwAAAA==.Mirâculíx:BAAALAADCgYIBgAAAA==.',Mo='Mokador:BAAALAAECgEIAQAAAA==.Mops:BAAALAADCggIEAAAAA==.Mordion:BAAALAAECgEIAQAAAA==.Morgulf:BAAALAAECgMIBgAAAA==.',Mu='Muggabadschr:BAAALAAECgYICQAAAA==.Mukju:BAAALAAECgYIDAAAAA==.',['Mô']='Mônte:BAAALAAECgMIAwAAAA==.Môritz:BAAALAAECgMIAwAAAA==.',Na='Nacho:BAABLAAECoEUAAIDAAcIGRVSFwDhAQADAAcIGRVSFwDhAQAAAA==.Naguru:BAAALAAECgYIBwAAAA==.Naigul:BAAALAADCggICQAAAA==.Nakarox:BAAALAAECggIEAAAAA==.',Ne='Neroni:BAAALAAECgIIAwAAAA==.',Ni='Nicklasli:BAAALAAECgMIAwAAAA==.Nijeeh:BAAALAADCggICwABLAAECgcIDQABAAAAAA==.Niênna:BAAALAAECgYICQAAAA==.',No='Nohonor:BAAALAADCggICAAAAA==.',Nu='Nurysha:BAAALAAECgYIBgAAAA==.Nuxly:BAAALAAECgQIBAAAAA==.',Ny='Nykaria:BAAALAADCgcIBwAAAA==.Nyraâ:BAAALAAECgEIAQAAAA==.',['Ní']='Nícki:BAAALAAECgMIBQAAAA==.',Ol='Oliver:BAAALAAECgMIBwAAAA==.',On='Onikage:BAAALAAECgIIAgAAAA==.',Os='Osladi:BAAALAAECgYIDgABLAAECgcIDQABAAAAAA==.',Pa='Pajun:BAAALAAECgQICwAAAA==.Panteon:BAAALAAECgIIAgAAAA==.Papaschatten:BAAALAADCgcIDAAAAA==.Paroodin:BAAALAADCgMIAwAAAA==.',Pe='Pepede:BAAALAADCgcIBwAAAA==.',Ph='Pheno:BAAALAAECgYIBQAAAA==.Phenonom:BAAALAADCgQIBAAAAA==.',Pi='Pisanarias:BAAALAADCgcIBwAAAA==.',Pr='Prigak:BAAALAAECgYICQAAAA==.Prilaria:BAAALAADCgcIBgAAAA==.Prisma:BAAALAADCgQIBAAAAA==.',Pw='Pwnyah:BAAALAADCgUIBAAAAA==.',Py='Pyronius:BAAALAADCgcIBwAAAA==.',['Pü']='Püzcraft:BAAALAAECgcIEAAAAA==.',Re='Recane:BAAALAAECgEIAQAAAA==.Reenju:BAAALAADCgMIAwAAAA==.Regala:BAAALAAECgEIAQAAAA==.Renate:BAAALAAECgUIBQAAAA==.Rewiyel:BAAALAADCggIDgAAAA==.',Ri='Riquas:BAAALAAECgYICgAAAA==.',Ro='Ronzarok:BAAALAAECgMIBgAAAA==.',Ru='Ruppî:BAAALAAECgIIAgAAAA==.',Ry='Ryomage:BAAALAAECggIEgAAAA==.Ryomdh:BAAALAADCgYIBgAAAA==.Ryompi:BAAALAADCggICAABLAAECggIEgABAAAAAA==.',['Rá']='Rágée:BAAALAADCgcIDQABLAAECgMIBQABAAAAAA==.',['Râ']='Râsh:BAAALAAECgcIDwAAAA==.',Sa='Saibot:BAAALAAECgYICgAAAA==.Saifu:BAAALAAECgMIBgAAAA==.Saito:BAAALAAECggICAAAAA==.Sajà:BAAALAADCgMIAwAAAA==.Sakushî:BAAALAADCgcIBwABLAAECgcIFAADABkVAA==.Salamisticks:BAAALAADCggIEAAAAA==.Santacruz:BAAALAAECgMIBQAAAA==.Sarada:BAAALAADCgIIAgAAAA==.Sareliana:BAAALAADCgYICQAAAA==.',Sc='Scharrak:BAAALAADCggIDwAAAA==.Schmeck:BAAALAADCgcICgAAAA==.Schwupibank:BAAALAAECgMIAwAAAA==.Scyrathia:BAAALAADCgYIBwAAAA==.',Se='Segas:BAAALAADCgQIBQAAAA==.Semyaza:BAAALAADCgEIAQAAAA==.Senegram:BAAALAADCgEIAQAAAA==.Seraphinâ:BAAALAAECgQIBgAAAA==.Seusi:BAAALAAECgYIDAAAAA==.Sev:BAAALAAECgYIDAAAAA==.Sevcon:BAAALAADCggICgAAAA==.',Sh='Shadowbxrn:BAAALAADCggICAAAAA==.Shameful:BAAALAADCgYIBAAAAA==.Shanjin:BAAALAADCggIDAAAAA==.Shanmo:BAAALAADCgcIBwAAAA==.Shaolique:BAAALAADCgIIAgAAAA==.Shibbedu:BAAALAAECgYIBgAAAA==.Shockbear:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Shockomel:BAAALAAECgQICgAAAA==.Shurul:BAAALAAECgMIAwAAAA==.Shytoos:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Si='Silikara:BAAALAAECgQIBAAAAA==.',Sk='Skâdî:BAAALAADCgcIBwAAAA==.Skândal:BAAALAAECgYICwAAAA==.',So='Soarqt:BAAALAAECgYIDwAAAA==.',Sp='Spacewizard:BAAALAAECgMIBQAAAA==.',St='Steinbeißer:BAAALAADCgMIAwABLAADCgcICwABAAAAAA==.Stinkguror:BAAALAAECgIIAgAAAA==.Stoorm:BAAALAADCggIIwABLAAECgMIBQABAAAAAA==.Stürmsche:BAAALAAECgMIBQAAAA==.',Su='Suffgurgl:BAAALAADCgIIAgAAAA==.',Sy='Syd:BAAALAADCggIFQAAAA==.',['Sî']='Sîlverlîne:BAAALAAECgEIAQAAAA==.',['Sû']='Sûnnschînê:BAAALAADCgUIBQAAAA==.',Ta='Taddie:BAAALAAECgMIBgAAAA==.Tajil:BAAALAADCgYIBgAAAA==.Takanan:BAAALAAECgEIAQAAAA==.Talinara:BAAALAADCgYIBgAAAA==.Taniara:BAAALAAECgMIBgAAAA==.Tariel:BAAALAADCggICAAAAA==.',Te='Telaría:BAAALAADCggIEAAAAA==.Tennyo:BAAALAADCggICAAAAA==.Testos:BAAALAAECgcIDQAAAA==.Tetty:BAAALAADCgcIBwAAAA==.',Th='Thermir:BAAALAADCggIFgAAAA==.Theston:BAAALAAECggIEQAAAA==.Thorina:BAAALAAECgUIDAAAAA==.Thorvid:BAAALAADCggICAAAAA==.',Ti='Tilasha:BAAALAAECgYIDAAAAA==.Tipsy:BAAALAAECgQICwAAAA==.Titanbull:BAAALAAECgMIBQAAAA==.',To='Tohui:BAAALAAECgYICAAAAA==.Tordon:BAAALAAECgYICAAAAA==.',Tr='Trixter:BAAALAADCgIIAgAAAA==.Trophys:BAAALAADCggIFQAAAA==.',Ty='Tyraurque:BAAALAAECggIDQAAAA==.Tyrralon:BAAALAAECgEIAQAAAA==.Tyrs:BAAALAAECgMIAwAAAA==.',Tz='Tzwonk:BAAALAAECgcIDwAAAA==.',['Té']='Térrorjunky:BAAALAADCggIDgAAAA==.',['Tí']='Tífì:BAAALAAECgcIAwAAAA==.',Ul='Ulrick:BAAALAAECgYIBgAAAA==.',Un='Unwriten:BAAALAADCggIEAAAAA==.',Ur='Uriell:BAAALAADCgcIBwAAAA==.',Us='Uskarr:BAAALAAECgUIBQAAAA==.',Va='Valkyrie:BAACLAAFFIEIAAIEAAMI3iTsAABHAQAEAAMI3iTsAABHAQAsAAQKgRcAAgQACAj7HjcCAMcCAAQACAj7HjcCAMcCAAAA.Vandiur:BAAALAADCggICAAAAA==.Vanîc:BAAALAAECgEIAQAAAA==.',Ve='Veethó:BAAALAAECgMIBgAAAA==.Veltinshorde:BAAALAAECgYIDgAAAA==.',Vi='Vienta:BAAALAADCgEIAQAAAA==.Vilatriz:BAAALAAECgEIAQAAAA==.Vivianné:BAAALAADCggICAAAAA==.',Vo='Vorgos:BAAALAAECgEIAQAAAA==.',Vu='Vunikat:BAAALAAECgMIBAAAAA==.Vuton:BAAALAAECgYICQAAAA==.',Wa='Waldpups:BAAALAADCgYIBgAAAA==.',We='Weideglück:BAAALAADCggICAAAAA==.Weißbrot:BAAALAAECgYICAAAAA==.',Wi='Wizlo:BAAALAAECgYICQAAAA==.',Wo='Woollahara:BAAALAADCgEIAQAAAA==.',['Wâ']='Wârlòrd:BAAALAAECgMIAwAAAA==.',['Wí']='Wíschmopp:BAAALAADCgYICgAAAA==.',Xa='Xavj:BAAALAAECgUICAAAAA==.',Xe='Xentos:BAAALAAECgQICwAAAA==.',Xo='Xoseria:BAAALAAECgMIAwAAAA==.',Xq='Xqlusiv:BAAALAAECgYIBwAAAA==.',['Xî']='Xîêê:BAAALAADCggICAAAAA==.',Ya='Yadana:BAAALAADCggICQAAAA==.Yadira:BAAALAADCggIDgAAAA==.Yaxxentra:BAAALAADCgYIBwAAAA==.',Yo='Yolofant:BAAALAADCgcIEgAAAA==.Yortu:BAAALAAECgcICwAAAA==.',Yr='Yrelia:BAAALAADCgYIBgAAAA==.',Yu='Yunâlesca:BAAALAADCggIFgAAAA==.Yuzuki:BAAALAADCgcIBwAAAA==.',Za='Zaljian:BAAALAAECgMIAwABLAAECggIAgABAAAAAA==.Zandaladin:BAAALAAECgMIAwAAAA==.Zappsarap:BAAALAADCgIIAgAAAA==.Zarakí:BAAALAAECgMIAgABLAAECggIAgABAAAAAA==.Zasias:BAAALAADCggICAAAAA==.',Zh='Zhâran:BAAALAADCggIFwAAAA==.',Zi='Zirconis:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Zo='Zoeki:BAAALAAECgUIBQAAAA==.Zorades:BAAALAADCgcICAAAAA==.Zottelknecht:BAAALAAECgYICQAAAA==.',['Âi']='Âion:BAAALAADCgcIBwAAAA==.',['Âr']='Ârion:BAAALAAECgYIDAAAAA==.Ârvên:BAAALAADCgcIBwAAAA==.',['Èm']='Èmily:BAAALAADCgcIDwAAAA==.',['Øc']='Øcelot:BAAALAADCggICAAAAA==.',['Ún']='Únique:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end