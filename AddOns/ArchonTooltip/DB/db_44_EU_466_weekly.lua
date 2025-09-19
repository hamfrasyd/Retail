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
 local lookup = {'Unknown-Unknown','Druid-Guardian','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','Evoker-Devastation','Monk-Mistweaver','Priest-Shadow','Monk-Windwalker',}; local provider = {region='EU',realm='Teldrassil',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adalaz:BAAALAADCgYICQAAAA==.',Ag='Agapala:BAAALAAECgMIAwAAAA==.Agrippanus:BAAALAAECgQICQAAAA==.',Ak='Akhzell:BAAALAAECgMICAAAAA==.Akimbo:BAAALAAECgEIAQAAAA==.',Al='Alexandrix:BAAALAADCgEIAQAAAA==.Aliasandre:BAAALAAECgQICAAAAA==.',Am='Amazon:BAAALAAECgUICQAAAA==.',An='Angelkrissy:BAAALAADCgcIBwAAAA==.Animia:BAAALAADCggIDQAAAA==.Ankordia:BAAALAADCggIDgAAAA==.',Ar='Arael:BAAALAADCggICAAAAA==.Arannis:BAAALAAECgUICgAAAA==.Archimidas:BAAALAAECgYIDwAAAA==.Arkany:BAAALAADCgYICAAAAA==.Arminu:BAAALAAECgYIDQAAAA==.Arrmageddon:BAAALAAECgMIBQABLAAECgMIBQABAAAAAA==.Aryjana:BAAALAAECgMIAwAAAA==.',As='Asen:BAAALAADCggIDQAAAA==.Asimâ:BAAALAAECgMIBQAAAA==.Askandra:BAAALAADCgUIBQAAAA==.Assúnga:BAAALAAECgYIBgAAAA==.Astheria:BAAALAADCgcIBwAAAA==.Astics:BAAALAAECgYIBgAAAA==.',At='Atom:BAAALAAECgYICQAAAA==.',Au='Audacity:BAAALAAECgIIAwAAAA==.',Av='Avoca:BAAALAADCggIBwAAAA==.',Az='Azad:BAAALAADCggICAAAAA==.Azguhl:BAAALAAECgcIEAAAAA==.',Ba='Balôm:BAAALAADCgUIBgAAAA==.Barragegaga:BAAALAAECgUIBwAAAA==.Bartholde:BAAALAAECgUIDQAAAA==.Basarâ:BAAALAADCgYIBgAAAA==.',Be='Belládona:BAAALAAECgMIAwAAAA==.Beogar:BAAALAADCgIIAgAAAA==.',Bi='Bigwhitecow:BAAALAADCgcIBwAAAA==.',Bl='Blitzy:BAAALAADCggIEAAAAA==.',Bo='Bowdh:BAAALAAECgYIBgAAAA==.',Br='Brogtar:BAAALAAECgcICQAAAA==.Brosyoshiret:BAAALAAECgcIDgAAAA==.Brummbaer:BAAALAADCgcIDAAAAA==.Brunhîld:BAAALAAECgcIEAAAAA==.',Bu='Buginswahili:BAAALAAECgMIAwAAAA==.Burni:BAAALAADCgcIBwAAAA==.Bursa:BAAALAADCggIEAAAAA==.',['Bä']='Bärsy:BAAALAADCgcIBwAAAA==.',Ca='Camtolorprst:BAAALAAECgEIAQAAAA==.Camtolorwar:BAAALAAECgEIAQABLAAECgEIAQABAAAAAA==.Carstnstahl:BAAALAAECgcIDwAAAA==.Cassiusdio:BAAALAADCgQIBgAAAA==.Cavus:BAAALAAECgMIBAAAAA==.',Ce='Celebi:BAAALAADCgYIBgAAAA==.Celîna:BAAALAADCggICAAAAA==.Cerenia:BAAALAAECgMIBQAAAA==.',Ch='Chalysa:BAAALAADCgIIAgAAAA==.Chaoslicht:BAAALAAECgYICQAAAA==.Chapchap:BAAALAADCggIDQAAAA==.Charizard:BAAALAAECggIEgAAAA==.Cheralie:BAAALAAECgYICgAAAA==.Cherrydu:BAAALAAECgMIAwAAAA==.Chéos:BAAALAADCgcICAAAAA==.',Ci='Cinnamonroll:BAAALAAECgQIBQAAAA==.Cirano:BAAALAADCgYIBgAAAA==.',Co='Coldres:BAAALAAECgIIAgAAAA==.Content:BAAALAADCggIDgAAAA==.Corneria:BAAALAADCgcIDgAAAA==.Cornil:BAAALAADCggIDgAAAA==.',Cr='Crêpes:BAAALAAECgMIAwAAAA==.',Cu='Curran:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',Da='Dalarok:BAAALAADCgYIBwAAAA==.Dalibor:BAAALAADCgcIBwAAAA==.Daphnee:BAAALAADCgEIAQAAAA==.Dayli:BAAALAADCgQIBAAAAA==.',De='Deathelester:BAAALAADCggICQAAAA==.Demondock:BAAALAAECgQIBAABLAAECggIFQACADAdAA==.Denschaaren:BAAALAADCgIIAgAAAA==.Dergehörtmir:BAAALAADCgcICAABLAAECgcIDwABAAAAAA==.Derketzer:BAAALAAECgcIEAAAAA==.Desalmado:BAAALAAECggIEAAAAA==.Devildragon:BAAALAAECgEIAQAAAA==.',Di='Dixii:BAAALAADCgQIBAAAAA==.',Dk='Dkquéén:BAAALAADCgEIAQABLAADCggICQABAAAAAA==.',Do='Dommaker:BAAALAADCggIEAAAAA==.Dommune:BAAALAADCggIFwAAAA==.Donalexandro:BAAALAAECgEIAgAAAA==.Donarwulf:BAACLAAFFIEFAAIDAAMI7hncAQAGAQADAAMI7hncAQAGAQAsAAQKgRYAAgMACAhkJOoAAEQDAAMACAhkJOoAAEQDAAAA.Donluis:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.Doodleez:BAAALAAECgcIDgAAAA==.Doppelpeter:BAAALAAECgQIBwAAAA==.',Dr='Draconídas:BAAALAADCgYIBgABLAADCggICQABAAAAAA==.Dragonar:BAABLAAECoEVAAIDAAgINxNnLACJAQADAAgINxNnLACJAQAAAA==.Dreistin:BAAALAADCggIFgAAAA==.',Du='Duvessa:BAAALAAECgcICAAAAA==.',['Dä']='Dämonibar:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',['Dö']='Dönos:BAAALAAECgYIDQAAAA==.Dönvoker:BAAALAADCggICQABLAAECgYIDQABAAAAAA==.',Eb='Ebonmage:BAABLAAECoEWAAIEAAgIkxPCHQAzAgAEAAgIkxPCHQAzAgAAAA==.',Ed='Edgyreggie:BAAALAADCggICAAAAA==.Edwinvansieg:BAAALAADCggICAAAAA==.',Ee='Eelowynn:BAAALAADCggIBQAAAA==.',Ei='Eis:BAAALAAECggIDgAAAA==.Eismar:BAAALAAECgEIAQAAAA==.',El='Elenôre:BAAALAAECggIDQAAAA==.Elle:BAAALAADCgcIBwAAAA==.Elsurioth:BAAALAADCgEIAQAAAA==.Elsé:BAAALAAECgIIAgAAAA==.Eluneu:BAAALAADCgYIBgABLAADCggIEAABAAAAAA==.Eluria:BAAALAADCgYIBAAAAA==.Elwin:BAAALAADCgcICAABLAAECgYIBgABAAAAAA==.Elêktra:BAAALAADCggIFgABLAAECgcICAABAAAAAA==.',Em='Emmà:BAAALAAECgMIBQAAAA==.',En='Endorì:BAAALAAECgQIBAAAAA==.Enthal:BAAALAAECgYIDAAAAA==.',Es='Escannor:BAAALAAECgYICAAAAA==.',Et='Ettersberg:BAAALAAECggIDgAAAA==.',Eu='Eulenfeder:BAAALAADCggIGAAAAA==.',Ev='Everlasting:BAAALAAECgMIBwAAAA==.',Ex='Exesor:BAAALAAECgIIBAAAAA==.Exodal:BAAALAADCggIFgAAAA==.',Fa='Fandrissa:BAAALAAECgMIBQAAAA==.Faver:BAAALAAECgYIDAAAAA==.',Fe='Feno:BAAALAAFFAIIAgAAAA==.',Fi='Fiandala:BAAALAADCgQIBAAAAA==.Finla:BAAALAADCgMIAwAAAA==.',Fl='Flathead:BAAALAAECgcIBwAAAA==.Flednanders:BAAALAADCgcICAAAAA==.Floxus:BAAALAAECggICQABLAAECggIFQAFAFsjAA==.Fluu:BAAALAAECgMIAwAAAA==.Flying:BAAALAADCggIDwAAAA==.',Fo='Fogerogue:BAAALAAECgUIBQAAAA==.Forte:BAAALAADCgcIFQAAAA==.Foxîe:BAAALAADCgcIBwAAAA==.',Fr='Friuda:BAAALAADCgcICQAAAA==.Fruxilia:BAAALAAECgQIBgAAAA==.Fränzis:BAAALAADCggICAAAAA==.',['Fì']='Fìeldy:BAAALAADCgYIDAAAAA==.',['Fô']='Fôo:BAAALAADCggICgAAAA==.',Ga='Garoar:BAAALAADCggIDgAAAA==.Gaster:BAAALAAECgEIAQAAAA==.Gavril:BAAALAADCgcIDgAAAA==.',Ge='Gena:BAAALAAECgYIBgAAAA==.Geonidas:BAAALAAECgEIAQAAAA==.',Gl='Glee:BAAALAADCgcIBwAAAA==.Glücksfee:BAAALAADCggIFQAAAA==.',Go='Gorak:BAAALAADCggIDwAAAA==.Gotfrit:BAAALAADCgcIBwAAAA==.',Gr='Grandeeney:BAAALAADCggIFgAAAA==.Grangorian:BAAALAAECgMIBQAAAA==.Grantler:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.Grimbolin:BAAALAADCggIDwABLAADCggIDwABAAAAAA==.Grimnirsson:BAAALAAECgYICgAAAA==.Grîmmjow:BAAALAADCggICQAAAA==.',['Gô']='Gôttesbote:BAAALAADCgcICwAAAA==.',Ha='Hammabamma:BAAALAAECgYICAAAAA==.Hastur:BAAALAADCgUIBQAAAA==.Hausmeister:BAAALAADCgQIBAAAAA==.',He='Heerah:BAAALAADCggIFAAAAA==.Heilkraft:BAAALAAECgMIAwAAAA==.Hekto:BAAALAADCgYIBgAAAA==.Herberthahn:BAAALAADCgYIBgAAAA==.Hextul:BAAALAAECgYIBgAAAA==.Hexzul:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Hi='Hitorder:BAAALAAECgEIAQAAAA==.',Ho='Hochofen:BAAALAADCgcIBwAAAA==.Hopp:BAAALAAECgMIAwAAAA==.Horace:BAAALAAECgEIAQAAAA==.Horik:BAAALAADCgEIAQAAAA==.Hossa:BAAALAADCgcIBwAAAA==.',Hu='Hunox:BAAALAAECgEIAQAAAA==.Hunterhunter:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.',['Hà']='Hàmmberge:BAAALAAECgMIBAAAAA==.',['Hî']='Hînatá:BAAALAAECgYICgAAAA==.',['Hò']='Hòórny:BAAALAAECgIIAgAAAA==.',Ic='Ichsehnichts:BAAALAADCggIDQAAAA==.',Ii='Iida:BAAALAAECgMIBQABLAAECgMIBQABAAAAAA==.',Im='Imhøtep:BAAALAADCgEIAQAAAA==.',In='Inola:BAAALAADCggIEwAAAA==.Inori:BAAALAADCggIEAAAAA==.',Ir='Iranazal:BAAALAAECgYIDwAAAA==.Irilitha:BAAALAADCgcIBgAAAA==.',Is='Isirany:BAAALAAECgMIAwAAAA==.',Ja='Jaebum:BAAALAADCggIAwABLAADCggIEAABAAAAAA==.Jallyna:BAAALAADCggIEQABLAAECgYIDQABAAAAAA==.Jardyna:BAAALAADCgUIBQABLAAECgYIDQABAAAAAA==.',Je='Jerîcho:BAAALAADCgcIBwAAAA==.Jessyschami:BAAALAAECgYIDwAAAA==.',Ji='Jimcuningham:BAAALAADCggIDwAAAA==.Jimmieo:BAAALAADCggIFAAAAA==.Jinjie:BAAALAAECgUICQAAAA==.Jinxed:BAAALAAECgMIBQAAAA==.',Ju='Julès:BAAALAADCggIFAAAAA==.',Ka='Kaelen:BAAALAADCgcIBwAAAA==.Karateka:BAAALAAECgcIDwAAAA==.Karry:BAAALAADCggICAAAAA==.Kasei:BAAALAAECgYICQAAAA==.Kawausoness:BAAALAADCgEIAQAAAA==.',Ke='Keylie:BAAALAAECgEIAQAAAA==.',Ki='Kianaa:BAABLAAECoEWAAIGAAgIxSTNAgAuAwAGAAgIxSTNAgAuAwAAAA==.Kiddycát:BAAALAADCggIFAAAAA==.Kiddycât:BAAALAAECgEIAQAAAA==.Killkit:BAAALAADCggIEAAAAA==.Kiritô:BAAALAADCgcIBwAAAA==.',Kn='Knoppers:BAAALAAECgMIAwAAAA==.',Ko='Kohi:BAAALAADCggICAABLAAECgYIEQABAAAAAA==.Kortus:BAAALAADCgcIBwAAAA==.',Kr='Krifi:BAAALAADCgcIBwABLAAECgYIBAABAAAAAA==.Kristina:BAAALAADCgMIAgAAAA==.Kroosi:BAAALAADCgUIBQABLAAECgYIBgABAAAAAA==.Kryfi:BAAALAAECgYIBAAAAA==.',Ky='Kyarà:BAAALAAECgEIAQAAAA==.',['Kô']='Kônzuela:BAAALAAECgMIAwAAAA==.',La='Laufwienix:BAAALAADCggICAAAAA==.Laurelin:BAAALAAECgUIBwAAAA==.',Le='Lemora:BAAALAAECgcIEAAAAA==.Lessaria:BAABLAAECoEVAAIFAAgIWyOcBAAyAwAFAAgIWyOcBAAyAwAAAA==.Letonic:BAAALAADCgYIBwAAAA==.Letî:BAAALAAECgEIAQAAAA==.Levitar:BAAALAAECgMIBgAAAA==.Levitas:BAAALAADCgIIAgAAAA==.',Li='Lichtkiller:BAACLAAFFIEFAAIFAAMI5B+2BQDDAAAFAAMI5B+2BQDDAAAsAAQKgRcAAgUACAj1I1EGABgDAAUACAj1I1EGABgDAAAA.Limpy:BAAALAADCgcIDgABLAADCggIBQABAAAAAA==.Liposa:BAAALAAECggIEwAAAA==.Liriel:BAAALAAECgIIAgAAAA==.Livitana:BAAALAADCggICgAAAA==.',Lo='Lockgob:BAAALAADCggIDgAAAA==.Looth:BAAALAADCgQIBAAAAA==.',Lu='Luntilette:BAAALAADCgEIAQAAAA==.',['Lî']='Lîsanna:BAAALAAECgMIAwABLAAECggIEAABAAAAAA==.',['Lù']='Lùcký:BAAALAAECgEIAQAAAA==.',Ma='Mafi:BAAALAAECgEIAQAAAA==.Mageblast:BAAALAAECgQIBwAAAA==.Magequit:BAAALAADCggIEAAAAA==.Malinaperle:BAAALAADCgEIAQAAAA==.Mapleskiller:BAAALAADCggICAAAAQ==.Maradus:BAAALAAECgMIAwAAAA==.Margistrat:BAAALAADCggIDgAAAA==.Maríka:BAAALAAECgYIBgABLAAECggIFQAFAFsjAA==.Maylana:BAAALAAECgUICAAAAA==.',Me='Medizinbräu:BAABLAAECoEWAAIHAAgIpxNaDQDLAQAHAAgIpxNaDQDLAQAAAA==.Merilyn:BAAALAAECgMIBQAAAA==.Merryfinger:BAAALAADCggIDwAAAA==.',Mi='Milca:BAAALAADCggICAAAAA==.Minin:BAAALAAECggIEAAAAA==.Mirí:BAAALAADCgcIDAAAAA==.Misselestra:BAAALAAECgMIAwAAAA==.Misá:BAAALAADCgYICAAAAA==.Mity:BAAALAADCgUIBQAAAA==.',Mo='Moadib:BAAALAAECgQIBAAAAA==.Monkihonk:BAAALAADCgUIBQAAAA==.Moonangelina:BAAALAAECgMIBAABLAAECgcIEAABAAAAAA==.',Mu='Munin:BAAALAAECgIIAwAAAA==.',['Mà']='Màl:BAAALAAECgIIBAAAAA==.',['Má']='Márs:BAAALAAECgcIBwAAAA==.',['Mö']='Mönchichì:BAAALAAECgMIAwAAAA==.Mörenmonarch:BAAALAADCggIDAAAAA==.',['Mû']='Mûrdock:BAABLAAECoEVAAICAAgIMB1+AwD4AQACAAgIMB1+AwD4AQAAAA==.',Na='Naldric:BAAALAADCggICAAAAA==.Nassm:BAAALAAECgYICgAAAA==.Natürlích:BAAALAADCgUIBgAAAA==.Naytiri:BAAALAADCgYIBgAAAA==.',Ne='Nebelteiler:BAAALAAECgcIEAAAAA==.Nemeria:BAAALAADCgEIAQAAAA==.',Nh='Nhym:BAAALAAECgYICgAAAA==.',Ni='Nightmâre:BAAALAADCgUIBQAAAA==.Niliá:BAAALAADCgYIBwABLAADCgYIBwABAAAAAA==.',Nr='Nrazul:BAAALAADCggICAAAAA==.',Nu='Nullnullsix:BAAALAAECgMIBAAAAA==.Nurtok:BAAALAADCgUIBQAAAA==.',Ny='Nyhmz:BAAALAADCggICAAAAA==.',Ok='Okessa:BAAALAADCggICAABLAAECggIFAAIAOUbAA==.',Ol='Oldbear:BAAALAADCgcIBwAAAA==.Ollibar:BAAALAAECgYIBgAAAA==.',Or='Orimonk:BAAALAAECgMIBAAAAA==.Oripriest:BAAALAADCgYIBgAAAA==.Orphelié:BAAALAADCggICAAAAA==.',Os='Osîrîs:BAAALAADCgcIBwAAAA==.',Ot='Otis:BAAALAADCgcIBwAAAA==.',Pa='Pacoline:BAAALAAECgEIAQAAAA==.Padèé:BAAALAADCggICAAAAA==.Paulix:BAAALAAECgEIAQAAAA==.Paxo:BAAALAAECgcICgAAAA==.',Pe='Peppajam:BAAALAADCggIDgAAAA==.',Ph='Phan:BAAALAAECgIIAwAAAA==.Pheby:BAAALAAECgMIBQAAAA==.',Pr='Prunax:BAAALAAECgYIBgABLAAECgYICQABAAAAAA==.',Py='Pyrdacor:BAAALAADCgcIDAAAAA==.',['Pé']='Péradon:BAAALAAECgIIAgAAAA==.',['Pö']='Pöbelknirps:BAAALAADCggICQABLAAFFAIIAgABAAAAAA==.',['Pü']='Pübschen:BAAALAAECgMIBQAAAA==.',Qu='Quixxan:BAAALAADCggIEgAAAA==.',Ra='Raffos:BAAALAADCggIEwAAAA==.Rall:BAAALAADCggICAAAAA==.Raran:BAAALAADCgYIBgAAAA==.Raris:BAAALAADCgYIDAAAAA==.Raseth:BAAALAADCgUIBQAAAA==.',Re='Rexôna:BAAALAADCggICAAAAA==.',Rh='Rhogarr:BAAALAAECgIIAgAAAA==.',Ri='Rilex:BAAALAADCgMIAwAAAA==.Riora:BAAALAADCggICQAAAA==.Riva:BAAALAADCggIDQAAAA==.',Ro='Rodira:BAAALAADCgIIAgAAAA==.Roxxani:BAAALAADCgYIBgAAAA==.Roxxanía:BAAALAADCgYIBgAAAA==.',Ru='Rudolph:BAAALAADCgYIBgAAAA==.Rugar:BAAALAADCggIDwAAAA==.',Sa='Saffira:BAAALAADCgMIAwAAAA==.Sagittarius:BAAALAAECgMIAwAAAA==.Sagittaríus:BAAALAADCgIIAgAAAA==.Sahnetörtle:BAAALAAECgYIDAAAAA==.Saj:BAAALAADCggIEAAAAA==.Sakurâ:BAAALAADCgcIDgAAAA==.Salomil:BAAALAADCgcIBwAAAA==.Salvadore:BAAALAADCgcIBwAAAA==.Samentorana:BAAALAADCgcIBwAAAA==.Sandtieger:BAAALAAECgEIAQAAAA==.Santáfee:BAAALAADCgEIAQAAAA==.',Sc='Schort:BAAALAADCgQIBAAAAA==.',Se='Sephirothx:BAAALAAECgMICAAAAA==.Sequana:BAAALAAECgMIBQAAAA==.Seraxinus:BAAALAADCggICAAAAA==.Serayah:BAAALAAECgQIBAAAAA==.Sereana:BAAALAADCgQIBAAAAA==.',Sh='Shadewitch:BAAALAADCggIDwAAAA==.Shalai:BAAALAADCgQIBAABLAAFFAIIAgABAAAAAA==.Sherry:BAAALAAECgUIBgAAAA==.Shirogane:BAAALAAECgEIAQAAAA==.Shiruan:BAAALAAECgQIBAAAAA==.Shizury:BAAALAAECgIIAgAAAA==.',Si='Silliana:BAAALAAECgUIBwAAAA==.Silverj:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.Silvermuh:BAAALAAECgMIBQAAAA==.Sindrilian:BAAALAADCgcIBwAAAA==.',Sk='Skarin:BAAALAADCgEIAQABLAAECgcIDwABAAAAAA==.Skarla:BAAALAADCgYIBgAAAA==.',Sl='Sleepymage:BAAALAADCggIFQAAAA==.Sleepypriest:BAAALAADCggIEAAAAA==.Sleika:BAAALAADCgMIAwAAAA==.Sleiker:BAAALAAECgYIDQAAAA==.Sloth:BAAALAADCgcIBwAAAA==.',Sm='Smãugs:BAAALAADCgEIAQAAAA==.',Sn='Sniky:BAAALAADCggIDwAAAA==.',So='Soku:BAAALAAECgYIDAAAAA==.Sorax:BAAALAADCgcIDAAAAA==.',Sp='Spezî:BAAALAADCgIIAgAAAA==.Spriti:BAAALAAECgcIEAAAAA==.',St='Starbac:BAAALAADCggIDwAAAA==.Stealtha:BAAALAADCgcIBwABLAADCggICQABAAAAAA==.Stegi:BAAALAADCgcIDgAAAA==.Sternfeuer:BAAALAAECgMICAAAAA==.Støny:BAAALAADCgcIBwAAAA==.',Su='Suedtirol:BAAALAAECgMIBwAAAA==.Sulrig:BAAALAAECgMIBQAAAQ==.Suranaja:BAAALAAECgYICwABLAAECgYIDwABAAAAAA==.Surijan:BAAALAAECgMIBAAAAA==.',Sw='Swordmän:BAAALAADCgcIDAAAAA==.Swêety:BAAALAAECgQIBwABLAAECgcIEAABAAAAAA==.Swìffer:BAAALAAECgQIBAAAAA==.',Sy='Sylar:BAAALAADCggIFQAAAA==.Syltarius:BAAALAADCggICQAAAA==.Syluri:BAAALAADCggIDQABLAAECgYIBAABAAAAAA==.Syrahna:BAAALAAECgMIAwABLAAECgcICgABAAAAAA==.Syvarris:BAAALAADCggIDQAAAA==.',['Sá']='Sálázar:BAAALAAECgYICQAAAA==.Sálêîkô:BAAALAADCgYICgAAAA==.',Ta='Taka:BAAALAADCgIIAgAAAA==.Tandri:BAAALAADCgYIBgAAAA==.Tapsî:BAAALAAECgcIEAAAAA==.Tarantoga:BAAALAADCggIEwAAAA==.Tardurin:BAAALAADCggIDQAAAA==.Tarragona:BAAALAADCgcIDAAAAA==.Tatsuya:BAAALAADCggIFgAAAA==.Taøshi:BAAALAADCgMIAwAAAA==.',Te='Teddybärchen:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Teebaum:BAAALAADCgcIBwAAAA==.Teheros:BAAALAAECggIDAAAAA==.Telannie:BAAALAAECgYICgAAAA==.Teras:BAAALAADCgcIDgAAAA==.Terenci:BAAALAAECgMIBQAAAA==.',Th='Thabathaia:BAAALAAECgMIAwAAAA==.Thabtalian:BAAALAAECgMIAwAAAA==.Thainach:BAAALAADCggIDwAAAA==.Tharuel:BAAALAAECgQIBAAAAA==.Thcatze:BAAALAAECgEIAgAAAA==.Thorik:BAAALAADCgcIDgAAAA==.Thuramandill:BAABLAAECoEUAAIIAAgI5Ru+CgCsAgAIAAgI5Ru+CgCsAgAAAA==.',Ti='Ticta:BAAALAAECgMIBQAAAA==.Tiibbers:BAAALAADCgcIBwAAAA==.Tiluna:BAAALAAECgIIAgAAAA==.Tindra:BAAALAADCggICAAAAA==.Tiqz:BAAALAAECgcIDgAAAA==.Tix:BAAALAAECgMIBAAAAA==.',To='Tommî:BAAALAAECgcICAAAAA==.Toralor:BAAALAADCggIDwAAAA==.',Tr='Trackstaar:BAAALAAECgYIDAAAAA==.Triggerhappy:BAAALAAECgEIAQAAAA==.',Tw='Twochar:BAAALAAECgEIAgAAAA==.Twotime:BAAALAAECgcIDQAAAA==.',['Tá']='Táy:BAAALAAECgUIBwAAAA==.',['Tê']='Têmuchin:BAAALAADCgEIAQAAAA==.',['Tô']='Tômmi:BAAALAAECgEIAgABLAAECgcICAABAAAAAA==.',['Tö']='Törtle:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.',Ud='Udagaz:BAAALAADCgcIBwAAAA==.',Ul='Ulf:BAAALAAECgMIBAAAAA==.',Us='Usranos:BAAALAAECgMIAwAAAA==.',Va='Valgarv:BAAALAAECgQIBAAAAA==.Valistra:BAAALAAECgMIAwAAAA==.Vambraél:BAAALAADCgYIBwAAAA==.',Ve='Venomzug:BAABLAAECoEYAAIFAAgIQCKMDgCyAgAFAAgIQCKMDgCyAgAAAA==.Venthor:BAAALAADCgcIBwABLAADCggIEAABAAAAAA==.Venïtarï:BAAALAAECggIDwAAAA==.',Vi='Viin:BAAALAAECgEIAQAAAA==.Violence:BAAALAADCgIIAgAAAA==.',Vo='Voidhexer:BAAALAADCgQIBAAAAA==.Voldidk:BAABLAAECoEVAAIFAAgIByEDIwAOAgAFAAgIByEDIwAOAgAAAA==.Voldisha:BAAALAAECgQIBAABLAAECggIFQAFAAchAA==.',Vu='Vulvarna:BAAALAADCggIFgAAAA==.',['Vø']='Vøxzia:BAAALAADCgIIAgAAAA==.',Wa='Wallee:BAAALAADCggIDQAAAA==.Wallwerk:BAAALAADCgcIBwAAAA==.',We='Weizen:BAAALAADCgEIAQABLAAECgMIBwABAAAAAA==.Welcon:BAAALAAECgYICAAAAA==.',Wi='Wiwowa:BAAALAADCggIEwAAAA==.',Wo='Wolvis:BAAALAAECgMIAwAAAA==.Woorff:BAAALAADCggIDwAAAA==.Woschj:BAAALAAECgUIBwAAAA==.Wovl:BAAALAAECgcIDwAAAA==.',Xe='Xerus:BAAALAADCgcIBwAAAA==.',Xl='Xload:BAABLAAECoEWAAIJAAgInRI2CwAXAgAJAAgInRI2CwAXAgAAAA==.',Ye='Yeni:BAAALAAECgMIAwAAAA==.Yenn:BAAALAAECgcIDwAAAA==.',Yo='Yokto:BAAALAADCgIIAgAAAA==.Yoshí:BAAALAAECgYIDAAAAA==.Yotta:BAAALAADCgcIEAAAAA==.',Yr='Yrmell:BAAALAADCgYIBgAAAA==.',Za='Zaarol:BAAALAAECgcIEAAAAA==.',Ze='Zepto:BAAALAAECgMIBAAAAA==.Zetta:BAAALAADCggIFQAAAA==.',Zh='Zhuh:BAAALAADCggIEAAAAA==.',Zi='Ziiani:BAAALAAECgQIBgAAAA==.Zimity:BAAALAADCgcIDgAAAA==.Zimsaye:BAAALAADCgUIBQAAAA==.',Zo='Zoh:BAAALAAECgMIBgAAAA==.Zoldreth:BAAALAADCggICAAAAA==.Zornax:BAAALAAFFAIIAgAAAA==.',Zu='Zumit:BAAALAADCggIDwABLAAECggIEwABAAAAAA==.Zuzannah:BAAALAADCggIDwAAAA==.',['Zê']='Zêkê:BAAALAAECggIEAAAAA==.',['Án']='Ángerfist:BAAALAADCgYIBgAAAA==.',['Ãr']='Ãrtus:BAAALAADCgEIAQAAAA==.Ãrwen:BAAALAADCgEIAQAAAA==.',['Ån']='Ångström:BAAALAADCgUIBQABLAADCgcIDgABAAAAAA==.',['Él']='Élisé:BAAALAAECgIIBAAAAA==.Éléandrielle:BAAALAAECgMIAwAAAA==.',['Éo']='Éomer:BAAALAADCggICAAAAA==.',['Ðe']='Ðeathly:BAAALAAECgYICQAAAA==.',['Øl']='Ølson:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end