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
 local lookup = {'Unknown-Unknown','Monk-Brewmaster','Priest-Shadow','Warrior-Fury','Druid-Balance','Druid-Restoration','Priest-Holy',}; local provider = {region='EU',realm='Durotan',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aarona:BAAALAAECgMIBQAAAA==.',Ad='Adelindar:BAAALAADCgYIBwAAAA==.',Ai='Aida:BAAALAADCggIDwAAAA==.',Al='Alicìa:BAAALAADCgYIBgAAAA==.Alkzaba:BAAALAAECgYICQAAAA==.Almeya:BAAALAADCgMIAwAAAA==.Alorien:BAAALAADCggIEAAAAA==.Altekuh:BAAALAADCgEIAQAAAA==.',An='Andelton:BAAALAADCgQIBAAAAA==.Angelforyou:BAAALAAECgMIBgAAAA==.',As='Aschenstølle:BAAALAADCggIEgAAAA==.Ashenbeârd:BAAALAADCggICAAAAA==.',At='Attilem:BAAALAADCgYIBgAAAA==.',Au='Aurøra:BAAALAAECgEIAQAAAA==.',Az='Azzinoth:BAAALAADCgcIBwAAAA==.',Ba='Babypowder:BAAALAADCgcIFAAAAA==.Bakida:BAAALAAECgUIBQAAAA==.Balver:BAAALAAECgcICgAAAA==.Barcodé:BAAALAADCgcIDgABLAAECgEIAQABAAAAAA==.Bathrum:BAAALAADCgMIAwAAAA==.',Be='Beatya:BAAALAAECgEIAgAAAA==.Beefkeeper:BAAALAADCgcIDgAAAA==.Befibe:BAAALAADCgcIDgAAAA==.',Bi='Bibabub:BAAALAAECgMIAwAAAA==.Bigs:BAAALAADCgYIBgAAAA==.',Bl='Bloodhunter:BAAALAADCggICAAAAA==.Bluelux:BAAALAAECgQIBwAAAA==.',Br='Brachhus:BAAALAADCgcIDgAAAA==.Brubi:BAAALAADCgcIDAAAAA==.Brutitis:BAAALAADCgcIBwAAAA==.',Bu='Bubblepot:BAAALAAECgEIAQAAAA==.Bubblerunner:BAAALAADCgIIAgAAAA==.',['Bæ']='Bætý:BAAALAADCgQIBAABLAAECgEIAgABAAAAAA==.',Ca='Candrima:BAAALAADCgcIDgAAAA==.Capernián:BAAALAADCggIFwAAAA==.Casjiopaja:BAAALAADCggICAAAAA==.',Ce='Celibrew:BAAALAADCgMIAwAAAA==.',Ch='Chrishh:BAAALAAECgMIAwAAAA==.Chàntál:BAAALAAECgYICAABLAAECgYIEAABAAAAAA==.',Cl='Claîr:BAAALAADCgYIBgAAAA==.',Co='Cocó:BAAALAADCgYICQAAAA==.Columbu:BAAALAAECgEIAQAAAA==.Cong:BAAALAADCgIIAgAAAA==.Conqueror:BAAALAAECgEIAQAAAA==.',Da='Dady:BAAALAADCgcIBwAAAA==.Daisycutter:BAAALAAECggIBwAAAA==.Damanda:BAAALAADCgYIBgAAAA==.Darklakai:BAAALAAECgMIAwAAAA==.Datios:BAAALAADCgcIBwAAAA==.',De='Deadlef:BAAALAADCgcIBwABLAABCgYIDwABAAAAAA==.Deandrâ:BAAALAADCgcICwAAAA==.Demetos:BAAALAADCgYIBwAAAA==.Deo:BAAALAADCggICAAAAA==.Desolater:BAAALAADCggIDgAAAA==.Detania:BAAALAAECgIIAgAAAA==.Devilpeace:BAAALAAECgYIDwAAAA==.',Di='Dinarya:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Dirando:BAAALAADCgcIEgAAAA==.',Do='Dobs:BAAALAAECgIIBAAAAA==.Domibärt:BAAALAAECgEIAQAAAA==.Doneran:BAAALAADCgIIAgAAAA==.',Dr='Drakaris:BAAALAAECgQIBQAAAA==.Drenâ:BAAALAAECgcIEQAAAA==.Druitrox:BAAALAAECgcIEAAAAA==.',['Dê']='Dêxo:BAAALAAECgIIAgAAAA==.',Ea='Earthfighter:BAAALAADCgEIAQAAAA==.Easymilow:BAAALAAECggIDwAAAA==.',El='Elcombo:BAAALAADCgcICgAAAA==.Elenoar:BAAALAADCgYIBgAAAA==.Elorien:BAAALAADCgcICAAAAA==.Elyos:BAAALAAECgYIDwAAAA==.',En='Enchantrezz:BAAALAADCgcIBwAAAA==.Ent:BAAALAADCggIEAAAAA==.',Er='Eredin:BAAALAAECgcIEAAAAA==.Erleuchter:BAAALAAECgQIBQAAAA==.',Eu='Euka:BAAALAADCgcIDgAAAA==.',Ex='Exqz:BAAALAADCggICAAAAA==.',Fa='Fataldeath:BAAALAADCgMIAwAAAA==.Fatality:BAAALAADCgcICgAAAA==.Fattîxx:BAAALAAECgQICQAAAA==.',Fe='Febbo:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Feen:BAAALAAECgYICAAAAA==.Feger:BAAALAADCgcIBwAAAA==.Fenneco:BAAALAADCgcIDQAAAA==.',Fi='Fingolfin:BAAALAAECgMIAwAAAA==.',Ga='Gaku:BAAALAADCgUIBQAAAA==.Gamba:BAAALAADCgEIAQAAAA==.Garuk:BAAALAAECgIIAgAAAA==.',Ge='Geekschnabel:BAAALAADCgYIBgAAAA==.',Go='Goldhasepal:BAAALAADCggIDQAAAA==.',['Gá']='Gándalf:BAAALAADCggIEAAAAA==.',['Gä']='Gänsehose:BAAALAADCgIIAgAAAA==.',Ha='Habschhumpen:BAABLAAECoEVAAICAAcIqg8nDgB3AQACAAcIqg8nDgB3AQAAAA==.Halsey:BAAALAADCgUIBQABLAAECgcIFQADAGkiAA==.Hasinator:BAAALAAECgcIEAAAAA==.',He='Healflame:BAAALAADCgYIBgAAAA==.Hephâistos:BAAALAAECgIIAgAAAA==.Hessi:BAAALAADCgcIBwAAAA==.',Ho='Hobbert:BAAALAAECgYIBgAAAA==.Holyscchiet:BAAALAAECgEIAQAAAA==.Hotwife:BAAALAADCgcICAAAAA==.',Ib='Ibirarwen:BAAALAAECgcIDwAAAA==.',Id='Ideria:BAABLAAECoEVAAIDAAcIaSLKCgCrAgADAAcIaSLKCgCrAgAAAA==.',In='Inez:BAAALAADCggIFAAAAA==.Inferion:BAAALAADCgYICQAAAA==.',Iv='Ivalina:BAAALAAECgEIAQAAAA==.Iváná:BAAALAADCgYIBwABLAAECgQICQABAAAAAA==.',Iz='Izir:BAAALAADCggIDwAAAA==.',Ja='Jarûn:BAAALAAECgYICgAAAA==.',Je='Jebolaren:BAAALAAECgYIBgAAAA==.Jenna:BAAALAAECgYICAAAAA==.',Ju='Julimond:BAAALAAECgIIAwABLAAECgYICwABAAAAAA==.',['Jè']='Jèssy:BAAALAADCgQIAwAAAA==.',Ka='Kaine:BAAALAADCgUIBQAAAA==.Kalinga:BAAALAADCgcIBwAAAA==.Kaltkaltauau:BAAALAAECgEIAQAAAA==.Karanda:BAAALAAECgYICQAAAA==.Kartoffelaim:BAAALAADCgYICQAAAA==.',Ke='Kekz:BAAALAAECgYICQAAAA==.Keratos:BAAALAAECgIIBAAAAA==.',Ki='Kiyoshi:BAAALAADCgYIBwAAAA==.',Ku='Kuranami:BAAALAAECgMIAwAAAA==.Kuromi:BAAALAAECgQIBgAAAA==.',Ky='Kyuubii:BAAALAAECgIIBAAAAA==.',['Kò']='Kòrrá:BAAALAAECgYICAABLAAECgYIEAABAAAAAA==.',La='Laban:BAAALAADCgMIAwAAAA==.Lachrìzì:BAAALAAECgcIEAAAAA==.Lamalover:BAAALAAECgMIAwAAAA==.Lanistas:BAAALAAECgMIBQAAAA==.Laroras:BAAALAADCggICAAAAA==.',Le='Leenïe:BAAALAADCggIDgAAAA==.Lelanie:BAAALAAECgYIBgAAAA==.Lengadanger:BAAALAAECgYIAgAAAA==.Letsshame:BAAALAAECgYIBQAAAA==.',Lh='Lhykis:BAAALAADCgMIAwAAAA==.',Li='Lightlucifer:BAAALAAECgMIAwAAAA==.Lightwings:BAAALAADCgcIBwAAAA==.Likra:BAAALAAECgEIAQAAAA==.Liszy:BAAALAADCgUIBQAAAA==.Livenia:BAAALAAECgMIAwAAAA==.',Lo='Loardi:BAAALAAECgEIAQAAAA==.Lockone:BAAALAADCgYIBgAAAA==.Lomo:BAAALAADCgUIBQAAAA==.Lomyta:BAAALAAECgYICQAAAA==.Lorêa:BAAALAADCgUIBQAAAA==.',Lu='Lugga:BAAALAAECgEIAQAAAA==.',Ly='Lyrenda:BAAALAAECgQIBAAAAA==.Lyzzi:BAAALAADCgIIAgAAAA==.',Ma='Maguma:BAAALAADCgcICwAAAA==.Maniaib:BAAALAAECgIIAwAAAA==.Maruuhn:BAAALAAECgEIAQAAAA==.Marxos:BAAALAADCgYIBgAAAA==.Maskeraith:BAAALAADCggIDwAAAA==.Maurîce:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',Mc='Mckay:BAAALAADCggICAAAAA==.',Me='Medikus:BAAALAADCggIDgABLAAECgEIAgABAAAAAA==.Mellicat:BAAALAADCgIIAgAAAA==.Mevamber:BAAALAADCgYIBgAAAA==.Meyonix:BAAALAADCgQIBAAAAA==.',Mi='Miib:BAAALAAECgMIBQAAAA==.Milyna:BAAALAADCgcIBwAAAA==.Minzchen:BAAALAADCggICgAAAA==.Mirakuru:BAAALAADCgYIBgAAAA==.',Mo='Moametal:BAAALAAECgYICwAAAQ==.Moar:BAAALAADCgYIBgAAAA==.Modock:BAACLAAFFIEFAAIEAAMIqgtfCACoAAAEAAMIqgtfCACoAAAsAAQKgRcAAgQACAhTIjUEADUDAAQACAhTIjUEADUDAAAA.Moncler:BAAALAADCggIFAAAAA==.Moonchéri:BAAALAADCgcIDgABLAAECgEIAQABAAAAAA==.',My='Myitare:BAAALAAECgEIAgAAAA==.Mythra:BAAALAAECgYICgAAAA==.',['Mä']='Mäxii:BAAALAAECgMIBQAAAA==.',Na='Naitras:BAAALAADCgcIDQAAAA==.Naljia:BAAALAAECgEIAQAAAA==.Namysan:BAAALAADCggIDwAAAA==.Namìleìn:BAAALAADCgYIBgAAAA==.',Ne='Nemedi:BAAALAADCgYIBwAAAA==.',Ni='Nightbann:BAAALAADCgMIBQAAAA==.Nimoëh:BAAALAAECgYIBgAAAA==.',No='Noducor:BAAALAADCgUICQAAAA==.Notmounty:BAAALAADCggIBwAAAA==.Notthehealer:BAAALAAECgEIAQAAAA==.',Nu='Nudelführer:BAAALAAECggICgAAAA==.',Ny='Nyrokrouge:BAAALAAECgcIDQAAAA==.Nyu:BAAALAAECgUIBQAAAA==.Nyzit:BAAALAAECgcIEAAAAA==.',Od='Oddos:BAAALAAECgEIAQAAAA==.',Og='Ogartar:BAAALAADCgYICgAAAA==.Oggsor:BAAALAAECgcICgAAAA==.Oggtus:BAAALAADCggICAABLAAECgcICgABAAAAAA==.',Oh='Ohaa:BAAALAADCgYIBwAAAA==.',Or='Orms:BAAALAADCgcICAAAAA==.Orogtar:BAAALAAECgYICQAAAA==.',Os='Oshkosh:BAAALAAECgYICAAAAA==.',Ot='Otis:BAAALAAECggIDAAAAA==.Ottilli:BAAALAAECgMIAwAAAA==.',Pa='Paladirne:BAAALAADCgcIBwABLAAECgcIFQACAKoPAA==.Pande:BAAALAADCgMIAwAAAA==.',Pe='Peacebreaker:BAAALAADCgIIAgAAAA==.Pedin:BAAALAADCgQIBQAAAA==.',Pr='Proxa:BAAALAADCgcIDgAAAA==.',Ra='Rakuls:BAAALAADCggIFAAAAA==.Rasika:BAAALAAECgcIEAAAAA==.Raspyrrha:BAAALAADCggIDwAAAA==.',Re='Reginald:BAAALAAECgIIAwAAAA==.',Ri='Rilanía:BAAALAAECggIAwAAAA==.',Ro='Rocksor:BAAALAADCggICAAAAA==.',Ru='Rumcas:BAAALAADCgcIEgAAAA==.Rumper:BAAALAADCgcIBwAAAA==.',Ry='Ryazit:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.',['Ré']='Rémì:BAAALAAECgYICgAAAA==.',Sa='Saio:BAABLAAECoEWAAMFAAgIaAg+IgB7AQAFAAgIaAg+IgB7AQAGAAgIDAgdJgBdAQAAAA==.Samæl:BAAALAADCgcIDgAAAA==.Saronas:BAAALAADCgcICgAAAA==.',Sc='Schnabio:BAAALAAECgYIDwAAAA==.',Se='Seick:BAAALAAECgMIAwAAAA==.Seidenpfote:BAAALAAECgcIEQAAAA==.Selènia:BAAALAAECgcICQAAAA==.',Sh='Shadowmina:BAAALAADCgcIDAAAAA==.Shaileen:BAAALAAECgYICQAAAA==.Shalan:BAAALAAECgEIAQAAAA==.Shamasutra:BAAALAADCgUIBQABLAAECgcIFQACAKoPAA==.Shamir:BAAALAADCgYICQABLAAECgIIAgABAAAAAA==.Shedou:BAAALAADCgcIEgAAAA==.Shizuyona:BAAALAAECgYIDAAAAA==.Shogun:BAAALAAECgUIAwAAAA==.',Si='Silivra:BAAALAAECgIIAwAAAA==.Sinria:BAAALAADCggIEAAAAA==.',Sl='Slowmarri:BAAALAADCgYIBgAAAA==.',Sn='Snowbâll:BAAALAAECgEIAQAAAA==.Snówwhite:BAAALAAECgYICQAAAA==.',Sp='Spooner:BAAALAADCgcIFAAAAA==.',St='Stellanocte:BAAALAADCgcIBwAAAA==.',Su='Subscriber:BAAALAADCgcIDgAAAA==.Sucara:BAAALAADCgMIBAAAAA==.',Sz='Szedu:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâsûke:BAAALAAECgIIAwAAAA==.',Ta='Taeas:BAAALAADCgYIDAAAAA==.Tagol:BAAALAADCggICAAAAA==.Talysra:BAAALAADCgcIBwAAAA==.Tatà:BAAALAAECgIIAgAAAA==.',Te='Teelia:BAAALAAECgMIBgAAAA==.Tekôda:BAAALAADCggIDwAAAA==.Testoot:BAAALAADCgUIBQAAAA==.',Th='Thalknight:BAAALAAECgMIAQAAAA==.Thalocki:BAAALAADCggICAAAAA==.Thyrisa:BAAALAAECgIIAgAAAA==.',Ty='Tyny:BAAALAADCggICAAAAA==.',Un='Unithral:BAAALAAECgMIAwAAAA==.',Va='Variel:BAAALAADCggICAAAAA==.',Ve='Venuro:BAAALAAECgYIDwAAAA==.',Vo='Vorletzter:BAAALAADCgcIDQAAAA==.',['Vé']='Vérion:BAAALAADCgcIBwAAAA==.',Wa='Walisdudu:BAAALAAECgYIBgABLAAFFAMIBQAHAPIIAA==.Walisschami:BAAALAAECgcIBwABLAAFFAMIBQAHAPIIAA==.Walíss:BAACLAAFFIEFAAIHAAMI8gjmCgChAAAHAAMI8gjmCgChAAAsAAQKgRcAAwcACAigF38PAFUCAAcACAigF38PAFUCAAMAAQhiAypUADQAAAAA.Watc:BAAALAADCgcIDQAAAA==.',Wr='Wroglen:BAAALAADCggICQAAAA==.',Yi='Yingtao:BAAALAAECggIDQAAAA==.',Yu='Yuimetal:BAAALAADCgYIBgABLAAECgYICwABAAAAAQ==.Yukishiro:BAAALAAECgYICgAAAA==.Yuula:BAAALAADCggICAAAAA==.',['Yé']='Yénnefer:BAAALAAECgYIDAAAAA==.',Za='Zablo:BAAALAAECgMIBgAAAA==.Zaccharia:BAAALAADCggIFgAAAA==.Zando:BAAALAADCgIIAgAAAA==.Zaraya:BAAALAADCggIGQAAAA==.',Ze='Zerrox:BAAALAADCgUIBQAAAA==.',Zu='Zuckerstange:BAAALAADCgYIBgAAAA==.',['Âk']='Âkina:BAAALAADCgcIDgAAAA==.',['Ér']='Ériu:BAAALAAECgUIBQAAAA==.',['Ðr']='Ðragon:BAAALAAECgEIAQAAAA==.',['Øz']='Øzzem:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end