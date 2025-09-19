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
 local lookup = {'Unknown-Unknown','Warrior-Fury','Paladin-Protection','Paladin-Retribution','DeathKnight-Frost',}; local provider = {region='EU',realm='Chantséternels',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abdelkrimm:BAAALAAECgMIAwABLAAFFAIIAwABAAAAAA==.',Ac='Ackiliane:BAAALAAECgIIBAAAAA==.Acryllia:BAAALAAECgYICQAAAA==.Acteøn:BAAALAADCgQIBAAAAA==.',Ad='Adélaïde:BAAALAADCggICAAAAA==.',Ag='Ageware:BAAALAADCgYIBgAAAA==.Aghorah:BAAALAAECgMICAAAAA==.Agode:BAAALAAECgYIDgAAAA==.',Ak='Akanë:BAAALAAECgMIBQAAAA==.Akeros:BAAALAAECgQIBAABLAAECgYICgABAAAAAA==.Akumeå:BAAALAAECgQICQAAAA==.',Al='Albibiphoque:BAAALAAECgYIDAAAAA==.Alcham:BAAALAAECggIEwAAAA==.Aldrys:BAAALAAECgYIDAAAAA==.Aleadractas:BAAALAAECgYICgAAAA==.Aloouf:BAAALAAECgYICAAAAA==.Alvíss:BAAALAAECgYICgAAAA==.',Am='Amaymmon:BAAALAADCgUICgAAAA==.Aménor:BAAALAADCgcICwAAAA==.',An='Andúril:BAAALAADCgcIBwAAAA==.Anoquim:BAAALAADCgQIBAABLAADCgcIDgABAAAAAA==.Anourette:BAAALAAECgQIBAAAAA==.Anänké:BAAALAADCgcIBwAAAA==.',Ar='Arcaniox:BAAALAADCgcIBwAAAA==.Arcanis:BAAALAADCggICAAAAA==.Archévo:BAAALAAECgYIDAAAAA==.Arimane:BAAALAAECgIIAgAAAA==.Arka:BAAALAADCggIDAAAAA==.Arkhalys:BAAALAAECgYIDgAAAA==.Arklay:BAAALAAECgMIBQAAAA==.Arrosh:BAAALAADCggIEAAAAA==.',As='Asrieladrien:BAAALAADCggICAAAAA==.Astridormi:BAAALAAECgYIDwAAAA==.',Au='Auguras:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.',Ax='Axedark:BAAALAADCggIEAAAAA==.Axtrix:BAAALAADCgcIDQAAAA==.',Az='Azaell:BAAALAADCgIIAgAAAA==.Azdrielle:BAAALAADCgUIBQAAAA==.Azé:BAAALAADCggIFAABLAADCggIFwABAAAAAA==.Azémage:BAAALAADCggIFwAAAA==.',['Aÿ']='Aÿala:BAAALAADCgcIDAAAAA==.',Ba='Badwulf:BAAALAADCgcIDwAAAA==.Barbapioche:BAAALAADCggICAAAAA==.',Be='Belpère:BAAALAADCgIIAgAAAA==.Belïal:BAAALAADCggIBQAAAA==.Betys:BAAALAAECgMIAwAAAA==.',Bh='Bhrom:BAAALAAECgQIBwAAAA==.',Bi='Biskhot:BAAALAAECgMIBQAAAA==.',Bl='Blackdark:BAAALAAECgYICwAAAA==.Bladion:BAAALAADCgMIAwAAAA==.Blaive:BAAALAADCggIDQAAAA==.',Bo='Bogard:BAAALAAECgcIDAAAAA==.Boriss:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.Boréalia:BAAALAADCgUIBgAAAA==.',Br='Bressigris:BAAALAADCggIDgAAAA==.Brizä:BAAALAAECgYIBwAAAA==.Brunicendre:BAAALAADCgcIBwAAAA==.',Bu='Bunchi:BAAALAAECgMIBgAAAA==.',['Bã']='Bãbz:BAAALAAECgMIBQAAAA==.',Ca='Carlo:BAAALAAECgIIAgAAAA==.',Ce='Cent:BAAALAADCgEIAQABLAAECgUICAABAAAAAA==.',Ch='Chamelya:BAAALAAECggICQAAAA==.Chamoinemomo:BAAALAAECgEIAQAAAA==.Chassoukati:BAAALAADCgcIBwAAAA==.Childerick:BAAALAADCgUIBQAAAA==.Chitzen:BAAALAAECggICgAAAA==.',Ci='Cityhunter:BAAALAADCgMIAwAAAA==.',Cl='Cleyent:BAAALAADCgcIBwAAAA==.',Co='Cordon:BAAALAAECgQIBAAAAA==.',Cy='Cyndraz:BAAALAADCggICgABLAAECggIEwABAAAAAA==.',Da='Daktary:BAAALAAECgMIBQAAAA==.Darkøsta:BAAALAADCggICAAAAA==.',De='Decarth:BAAALAAECgQIBQABLAAECgQIBQABAAAAAA==.Deepér:BAAALAAECgQICQAAAA==.Demaxis:BAAALAAECgMIBQAAAA==.Dered:BAAALAAECgYIDwAAAA==.Devlyne:BAAALAAECgIIAgAAAA==.',Dh='Dhealx:BAAALAAECgQIAwAAAA==.',Di='Dialfus:BAAALAAECgYIDwAAAA==.Dimanche:BAAALAADCgcIBwAAAA==.',Do='Dovahlastraz:BAAALAADCggIEAAAAA==.',Dr='Drackaelia:BAAALAADCgcIDgABLAADCgcIFAABAAAAAA==.Dranose:BAAALAAECgQIBAAAAA==.Drenna:BAAALAAECggICAAAAA==.',Du='Dustinshadow:BAAALAADCgcIDgAAAA==.',Dy='Dyman:BAAALAADCgIIAgAAAA==.',['Dé']='Démaunio:BAAALAADCggIEAAAAA==.',['Dë']='Dëlios:BAAALAAECgYIDAAAAA==.',['Dü']='Dürrin:BAAALAAECgMICQAAAA==.',Ed='Edalix:BAAALAADCgMIAwABLAAECgEIAQABAAAAAA==.Edalya:BAAALAAECgEIAQAAAA==.Edracyr:BAAALAADCgcIAQAAAA==.Edrinldy:BAAALAAECgEIAQAAAA==.Eduarem:BAABLAAECoEVAAICAAgIkSCmBgAGAwACAAgIkSCmBgAGAwAAAA==.',Ef='Efra:BAAALAADCggIEAAAAA==.',El='Elamin:BAAALAAECgQIBAAAAA==.Eldoros:BAAALAADCgcIDAAAAA==.Elkarh:BAAALAADCggIFwAAAA==.Elucidator:BAAALAAECgMIBQAAAA==.Elwÿn:BAAALAADCgUICgAAAA==.Elysea:BAAALAADCgcIBwAAAA==.',En='Enalora:BAAALAAECgcIDQABLAAECggIFQADAN4aAA==.Enmi:BAAALAADCggIEAAAAA==.',Eo='Eowïnà:BAAALAADCggICwAAAA==.',Ep='Ephraïm:BAAALAAECgYIBwABLAAECgYICAABAAAAAA==.',Er='Erahdak:BAAALAADCgcIDAAAAA==.Erethia:BAAALAADCgUIBQAAAA==.Erudimend:BAAALAAECgMIBQAAAA==.Erwÿn:BAAALAADCggIDgAAAA==.',Es='Esmeralda:BAAALAADCgUIBQAAAA==.',Et='Etis:BAAALAADCgMIBAAAAA==.',Ew='Ewalock:BAAALAAFFAEIAQAAAA==.',['Eö']='Eöl:BAAALAADCgQIBgABLAADCgcIDAABAAAAAA==.',Fa='Falsh:BAAALAADCggIBgAAAA==.Fantasïa:BAAALAAECgMIBQAAAA==.',Fe='Fen:BAAALAAECgMIBgAAAA==.',Fi='Filisia:BAAALAADCggICAAAAA==.',Fl='Flapok:BAAALAAECggIDgAAAA==.Flintounette:BAAALAADCgcIBwAAAA==.Fléxo:BAAALAADCgIIAgABLAAECgYICgABAAAAAA==.',Fo='Foxminator:BAAALAAECgMIBgAAAA==.',Fr='Frellon:BAAALAAECgMICAAAAA==.',Fu='Fufuspwan:BAAALAADCgcIDQAAAA==.Funmore:BAAALAADCgcIDAAAAA==.Future:BAAALAADCggICAAAAA==.',['Fé']='Fétidø:BAAALAADCggIDwAAAA==.',['Fü']='Füshï:BAAALAAECgYICwAAAA==.',Ga='Gakorikus:BAAALAAECgMIBQAAAA==.Gardener:BAAALAAECgIIAgAAAA==.',Gi='Gimlisan:BAAALAAECgYICwAAAA==.',Gn='Gnomegazél:BAAALAADCggIBgAAAA==.',Go='Gobeau:BAAALAADCgUIBQAAAA==.Golth:BAAALAAECgYICgAAAA==.Gonvalskyy:BAAALAAFFAIIAwAAAA==.Goroumu:BAAALAAECgYICQAAAA==.Gortikas:BAAALAADCgcIEgAAAA==.Goudale:BAABLAAECoEaAAMDAAcIsBweBwAuAgADAAcIsBweBwAuAgAEAAII1AppggBcAAAAAA==.',Gr='Grenat:BAAALAADCggIDQAAAA==.Gribouille:BAAALAAECgUICAAAAA==.',['Gä']='Gägou:BAAALAADCgYIBgAAAA==.',['Gü']='Günter:BAAALAAECgYIDgAAAA==.',Ha='Haelas:BAAALAAECgEIAQAAAA==.Hareyaka:BAAALAAECgQIBwAAAA==.Harlèy:BAAALAADCggIDQAAAA==.Hartus:BAAALAAECgYIDgAAAA==.Hayllay:BAAALAAECgYIBgAAAA==.',He='Healianna:BAAALAAECgQIBAAAAA==.Hellvyra:BAAALAAECgIIAgAAAA==.Henodine:BAAALAADCgcIFAAAAA==.',Hi='Hirock:BAAALAADCgUIBQAAAA==.Hirrho:BAAALAAECgMIAwAAAA==.Hizallinna:BAAALAADCggIFgAAAA==.',Hy='Hybrisya:BAAALAADCggIDwAAAA==.',['Hä']='Hällay:BAAALAAECgYIDAAAAA==.',['Hæ']='Hæstia:BAAALAAECgIIAgAAAA==.',['Hè']='Hèllwen:BAAALAAECgIIAgAAAA==.',['Hé']='Hélgie:BAAALAADCggICAAAAA==.Héølÿs:BAAALAADCgIIAgAAAA==.',['Hë']='Hëavy:BAAALAAECgQIBwAAAA==.',['Hî']='Hîsoka:BAAALAAECgYICwAAAA==.',Id='Idel:BAAALAAECgUIBQAAAA==.',Io='Ionia:BAAALAAECgYIDAAAAA==.',Is='Isadora:BAAALAAECgMIBQAAAA==.Isagarran:BAAALAADCgcICgAAAA==.',Ja='Jaimelabiere:BAAALAADCgMIAwAAAA==.',Je='Jeremchaçeur:BAAALAAECgIIAgAAAA==.',Ji='Jilkaniz:BAAALAAECgYIBgAAAA==.',Jr='Jrams:BAAALAAECgYIDQAAAA==.',Ju='Jujudk:BAAALAAECgYIBwAAAA==.Junnahlaas:BAAALAADCgEIAQAAAA==.',['Jô']='Jônathan:BAAALAAECgYICQAAAA==.',Ka='Kaeldorei:BAAALAAECgQIBAAAAA==.Kaiøshin:BAAALAADCgQIBAAAAA==.Kakelmon:BAAALAADCgcIBwAAAA==.Kalipsa:BAAALAAECgMIBQAAAA==.Kalm:BAAALAADCgIIAgAAAA==.Kamaa:BAAALAAECgMIBQAAAA==.Kame:BAAALAADCggICAAAAA==.Kamélià:BAAALAAECgYIBgABLAAECgYIDgABAAAAAA==.Kananne:BAAALAAECgUIBwAAAA==.Karadraz:BAAALAAECgYIDQAAAA==.Kaulendil:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Kayne:BAAALAAECgMIAwAAAA==.',Ke='Keneldrik:BAAALAADCggIFAAAAA==.',Kh='Khaldoran:BAAALAADCggIDAAAAA==.',Kk='Kkanane:BAAALAAECgMIAwAAAA==.',Kl='Klainn:BAAALAAECgYIDgAAAA==.',Ko='Kouloup:BAAALAADCgEIAQAAAA==.Kovac:BAAALAADCgcIBwAAAA==.Koval:BAAALAADCgcIDQAAAA==.Kovalchuck:BAAALAAECgQIBAAAAA==.',Kr='Krâkeur:BAAALAAECgMIBgAAAA==.',Ky='Kyranah:BAAALAAECgYICgAAAA==.Kyuby:BAAALAADCgcIEwAAAA==.',['Kâ']='Kâthllyn:BAAALAAECgMIAwAAAA==.',['Kä']='Kägrïm:BAAALAADCgEIAQAAAA==.',['Kæ']='Kænã:BAAALAAECgYIDwAAAA==.',['Kô']='Kôva:BAAALAADCgcIBwAAAA==.',La='Lakri:BAAALAAECggIDwAAAA==.',Le='Lensorceleze:BAAALAADCgcIEAAAAA==.Lexya:BAAALAADCgIIAgAAAA==.',Lh='Lhunhah:BAAALAADCgEIAQAAAA==.',Li='Lihz:BAAALAADCggICAAAAA==.',Lo='Lolippop:BAAALAAECgYIDgAAAA==.Lollipøps:BAAALAADCggIFwAAAA==.Loupkìus:BAAALAAECgQICQAAAA==.Louragan:BAAALAAECgYIDgAAAA==.',Lu='Luhnae:BAAALAADCgMIAwAAAA==.Lukaélys:BAABLAAECoEVAAIFAAgI7RkdFABtAgAFAAgI7RkdFABtAgAAAA==.Lulabi:BAAALAADCgQIBAAAAA==.Lunnah:BAAALAADCgcIBwAAAA==.Luther:BAAALAADCggIEAAAAA==.Luzim:BAAALAAECgMIBAAAAA==.',['Lé']='Lénastrasza:BAAALAAECgMIBQAAAA==.',['Lï']='Lïcht:BAAALAAECgYIDAAAAA==.',['Lö']='Lööne:BAAALAAECgYICQAAAA==.',['Lø']='Løgosh:BAAALAADCgcIDQAAAA==.Løther:BAAALAAECgQIBQAAAA==.',Ma='Maena:BAAALAADCgcIBwAAAA==.Magehuskull:BAAALAAECgQICgABLAAECgcIDAABAAAAAA==.Mara:BAAALAAECggIEwAAAA==.Marakta:BAAALAAECgUIBQAAAA==.Marius:BAAALAAECgMIAwAAAA==.Marmonäe:BAAALAADCgMIAwAAAA==.Maryløue:BAAALAADCgIIAgAAAA==.',Me='Medene:BAAALAADCgMIAwAAAA==.Meilya:BAAALAADCggICwAAAA==.Melyyna:BAAALAAECgQICQAAAA==.Merwën:BAAALAADCggICAAAAA==.',Mi='Mijokii:BAAALAADCgcICAAAAA==.Minl:BAABLAAECoEWAAIFAAgI2B/+DgCjAgAFAAgI2B/+DgCjAgAAAA==.',Mo='Monalisa:BAAALAAECgMIBQAAAA==.Moonfurie:BAAALAAECgMIBAAAAA==.Mopsmash:BAAALAAECgUICAAAAA==.Motillium:BAAALAAECgQICQAAAA==.',My='Myralaza:BAAALAAECggIEwAAAA==.',['Mï']='Mïtia:BAAALAADCgIIAgAAAA==.',Na='Nagashi:BAAALAAECgUIBgAAAA==.Nanïbi:BAAALAADCggICAAAAA==.Nashyrra:BAAALAADCgMIAwAAAA==.',Ne='Neazl:BAAALAADCggICAAAAA==.Necrodragon:BAAALAAECgQIBwAAAA==.Nehøsky:BAAALAADCgEIAQAAAA==.Neosto:BAAALAADCgcIFAAAAA==.Neven:BAAALAAECgEIAQAAAA==.',Ni='Nicki:BAAALAAECgYICQAAAA==.Nimasus:BAAALAADCgcIBwAAAA==.Nimuae:BAAALAADCgYICQAAAA==.Nishimiya:BAAALAAECgQICgAAAA==.Nivélion:BAAALAAECgMIBgAAAA==.',No='Noflowers:BAAALAADCgcIBwAAAA==.Northstar:BAAALAAECgMIAwAAAA==.',Nu='Nuhara:BAAALAAECgcICgAAAA==.',Ny='Nycø:BAAALAADCgcIDAAAAA==.',['Né']='Néni:BAAALAADCgYIBgABLAADCggICwABAAAAAA==.Néphénie:BAAALAAECgYICAAAAA==.',Ob='Obëlïx:BAABLAAECoEXAAICAAYIEh9sFAAzAgACAAYIEh9sFAAzAgAAAA==.',Om='Omnissiah:BAAALAAECgEIAQAAAA==.',Op='Ophedemo:BAAALAADCggIDwAAAA==.Ophegaelle:BAAALAADCgYIBgAAAA==.',Or='Orokke:BAAALAAECgYIBgAAAA==.Orrion:BAAALAADCgcIEAABLAADCgcIFAABAAAAAA==.',Ow='Oweglacier:BAAALAAECgIIAgAAAA==.',Ox='Oxias:BAAALAAECgIIAgAAAA==.',Pa='Palafoune:BAAALAAECgIIAgAAAA==.Palaghøst:BAAALAADCggIDwAAAA==.Pancarte:BAAALAADCggICAAAAA==.Pandragor:BAAALAADCgUIBQAAAA==.Panoramixx:BAAALAADCggIFQAAAA==.Paÿnn:BAAALAAECgMIBQAAAA==.',Pe='Perfoura:BAAALAADCgIIAgAAAA==.Perihan:BAAALAAECgIIAgAAAA==.Persépöils:BAAALAADCgQIBAAAAA==.',Pi='Pitkonk:BAAALAADCgUIBQAAAA==.',Po='Poney:BAAALAADCgYIBwAAAA==.',Pu='Pulsion:BAAALAAECgEIAQABLAAECgYIDAABAAAAAA==.',Py='Pyrocham:BAAALAAECgEIAQAAAA==.Pyrøblast:BAAALAADCgcICwAAAA==.',Ra='Radoje:BAAALAAECgYICgAAAA==.',Re='Rezme:BAAALAADCgcIBwAAAA==.',Ri='Riiddick:BAAALAADCgcIDgAAAA==.',Ro='Rokinou:BAAALAAECgQIBwAAAA==.Roufous:BAAALAAECgYICgAAAA==.',Ry='Rydick:BAAALAAECgYICQAAAA==.Ryuji:BAAALAADCgIIAgAAAA==.',['Rô']='Rôxxer:BAAALAAECgQICQAAAA==.',Sa='Saadidda:BAAALAADCggIDgAAAA==.Safirä:BAAALAAECgMIAwAAAA==.Sanølya:BAAALAADCgcIEwAAAA==.Satsat:BAAALAAECgUICgAAAA==.Sawa:BAAALAAECgcIDAAAAA==.',Sc='Scalliebaby:BAAALAAECgYICAAAAA==.Scarmiglione:BAAALAAECgEIAQAAAA==.',Se='Sephi:BAAALAAECgYICgAAAA==.',Sh='Shadraneth:BAAALAAECgUIBQABLAAECgYICgABAAAAAA==.Shaldoreï:BAAALAAECgYIDgAAAA==.Shali:BAAALAAECgQIBgAAAA==.Shalteaa:BAAALAADCgMIAwAAAA==.Shayastrasha:BAAALAAECgQICQAAAA==.Shelannath:BAAALAADCgMIBAABLAAECgMIBQABAAAAAA==.Shindeiwa:BAAALAAECgQICQAAAA==.Shocan:BAAALAADCggIFwAAAA==.Shomen:BAAALAADCgMIAwAAAA==.Shyra:BAAALAAECgMIAwAAAA==.',Si='Sinahindo:BAAALAAECgcICwAAAA==.',Sk='Sky:BAAALAAECgIIAgAAAA==.',Sl='Slma:BAAALAADCggICAABLAAFFAIIAwABAAAAAA==.',So='Somøney:BAAALAADCggIEwAAAA==.Sornet:BAAALAAECgMIBQAAAA==.Sortha:BAAALAAECgEIAQAAAA==.',Sp='Spadiell:BAAALAAECgQIBwAAAA==.Sparta:BAAALAAECgYICQAAAA==.',Su='Suguru:BAAALAADCggIDAAAAA==.Superdps:BAAALAAFFAIIBAAAAA==.',['Sö']='Söja:BAAALAAECgYIDwAAAA==.',['Sø']='Søulwørld:BAAALAADCgYIBQAAAA==.',['Sý']='Sýhl:BAAALAAECgcIDgAAAA==.',['Sÿ']='Sÿhl:BAAALAAECgYICwABLAAECgcIDgABAAAAAA==.',Ta='Taraën:BAAALAADCgUIBQAAAA==.Tarteaufruit:BAAALAAECgYIBgAAAA==.',Te='Temperanceb:BAAALAADCggIDgAAAA==.',Th='Thalorin:BAAALAADCgIIAgAAAA==.Thebodjack:BAAALAAECgMIAwAAAA==.Theguy:BAAALAAECgYIDAAAAA==.Thorggyr:BAAALAAECgYIBgAAAA==.Thylte:BAAALAAECgMIAwAAAA==.',Ti='Tiwen:BAAALAADCggICAAAAA==.',To='Togurô:BAAALAADCgcIAgAAAA==.Torkîl:BAAALAAECgYIBgAAAA==.',Tr='Trolaklass:BAAALAADCgcIDQAAAA==.Trunk:BAAALAAECgEIAgAAAA==.Trégorr:BAAALAAECgMIBQAAAA==.',Ts='Tsukiken:BAAALAAECgMIAwAAAA==.',Tw='Twyd:BAAALAAECgYICQAAAA==.',['Tï']='Tïtanïa:BAAALAADCgIIAgAAAA==.',Va='Valyna:BAAALAADCgcIBwAAAA==.',Ve='Velmeya:BAABLAAECoEcAAICAAgIQCGaBQAaAwACAAgIQCGaBQAaAwAAAA==.Ventor:BAAALAADCggICAAAAA==.Vermithor:BAAALAADCgcIFAAAAA==.',Vi='Viggnette:BAAALAAECgQICAAAAA==.Virus:BAAALAAFFAIIBAABLAAFFAIIBAABAAAAAA==.Visaraa:BAAALAAECgIIAgAAAA==.',Vr='Vritra:BAAALAAECgQICQAAAA==.',['Vö']='Vögue:BAAALAAECgMIBAAAAA==.',['Vø']='Vømito:BAAALAAECgEIAQAAAA==.',Wa='Wahalali:BAAALAADCgcIBwAAAA==.',Wh='Whatamidoing:BAAALAADCggIGAABLAAECgYICgABAAAAAA==.',Wo='Worgdelamort:BAAALAAECgMIAwAAAA==.',['Wà']='Wàzabï:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.',Xa='Xaliatath:BAAALAAECgcIEAAAAA==.Xaraac:BAAALAADCgUIDAAAAA==.Xarya:BAAALAAFFAEIAQAAAA==.',Xi='Xinchao:BAAALAADCgcIDQAAAA==.',Ya='Yamichto:BAAALAAECgEIAQAAAA==.Yarubo:BAAALAADCgUICQAAAA==.',Ye='Yelgi:BAAALAADCgQIBAAAAA==.Yeus:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.',Yo='Yopimarus:BAAALAAECgYIEQAAAA==.Yorri:BAAALAADCggIEQAAAA==.',Yr='Yrnos:BAAALAAECgUICgAAAA==.Yrzatz:BAAALAAECgYICQAAAA==.',['Yà']='Yàms:BAAALAAECgYICwAAAA==.',['Yû']='Yûreî:BAAALAAECgQICQAAAA==.',Za='Zabuzas:BAAALAADCgIIAgAAAA==.Zaggara:BAAALAADCgIIAgAAAA==.Zaktan:BAAALAADCgcIDQAAAA==.Zandou:BAAALAADCgUIBQABLAAECgYIBgABAAAAAA==.',Ze='Zelkar:BAAALAADCgEIAQAAAA==.Zenogs:BAAALAADCgIIAgAAAA==.Zetharis:BAAALAADCggIFgAAAA==.',Zi='Zinàcien:BAAALAAECgUICAAAAA==.',Zo='Zorykø:BAAALAAECgMIAwAAAA==.Zoukely:BAAALAADCgQIBAAAAA==.',Zu='Zulgorom:BAAALAADCggICAAAAA==.',Zy='Zyrix:BAAALAAECgIIAwAAAA==.',['Zå']='Zåk:BAAALAADCgYIBgAAAA==.',['Ân']='Ângélina:BAAALAADCgIIAgAAAA==.',['Él']='Élîe:BAABLAAECoEVAAMDAAgI3hpEBgBJAgADAAgIcxlEBgBJAgAEAAcIcxpIKQDaAQAAAA==.',['Ér']='Érèbe:BAAALAAECgEIAQAAAA==.',['Ïg']='Ïgøre:BAAALAADCgIIAgAAAA==.',['Øm']='Ømfæ:BAAALAAECgYICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end