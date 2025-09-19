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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Druid-Balance','Rogue-Assassination','Rogue-Subtlety','Hunter-Marksmanship','Druid-Restoration','Mage-Frost','DeathKnight-Frost','Mage-Arcane','Priest-Holy','Priest-Shadow','Shaman-Restoration','Warrior-Fury','DeathKnight-Blood','DemonHunter-Havoc','Paladin-Retribution','Monk-Brewmaster',}; local provider = {region='EU',realm='Perenolde',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abgelaufen:BAAALAAECgYIDQAAAA==.Abstrakt:BAAALAAECgMIBAAAAA==.',Ac='Acdc:BAAALAADCggIFgAAAA==.',Ag='Aggroluna:BAAALAADCgUIBQAAAA==.',Al='Aldieb:BAAALAAECgYICAAAAA==.Alextrasa:BAAALAADCggICAAAAA==.Allegretta:BAAALAAECgQIBAAAAA==.Alpaniad:BAAALAAECgEIAQAAAA==.Alpha:BAAALAADCgcIDgAAAA==.',Am='Amicalunae:BAAALAADCgIIAgAAAA==.Amügdala:BAAALAADCgIIAgAAAA==.',An='Andoriá:BAAALAADCgEIAQAAAA==.Angelhawk:BAAALAAECgEIAQAAAA==.Ankelar:BAAALAADCgcIDAAAAA==.Anklimus:BAAALAADCgcIBwAAAA==.Antarus:BAAALAAECgQIBQAAAA==.Anthuria:BAAALAADCggIEwAAAA==.',Ao='Aonas:BAAALAAECgYICwAAAA==.',Ar='Arnulf:BAAALAADCggIFgAAAA==.Aroxi:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Aroxs:BAAALAADCgcIEgAAAA==.Arthalis:BAAALAADCggIBwAAAA==.Arýa:BAAALAAECgQIBAABLAAECggIFQACAC8dAA==.',As='Asgerd:BAAALAADCgQIBAAAAA==.Ashlay:BAAALAADCgYIDwAAAA==.Asmodân:BAAALAAECgYIDQAAAA==.Asteron:BAAALAADCggIDwAAAA==.Astoriá:BAAALAADCgcIDAAAAA==.',Au='Autohitwarri:BAAALAAECgMIAwAAAA==.',Ay='Ayebeambeast:BAAALAAECgIIAgABLAAECgUIBQABAAAAAA==.',Az='Azenth:BAAALAAECgIIAgAAAA==.Azhu:BAAALAAECgcICwAAAA==.',Ba='Balgaroth:BAAALAADCggIFgAAAA==.Bathasar:BAAALAAECgMIBAAAAA==.Baumäffchen:BAAALAAECgYICwAAAA==.',Be='Beak:BAAALAAECgYICQAAAA==.Beefbolts:BAAALAAECgUICwAAAA==.Beleron:BAAALAADCggIFgAAAA==.Bellinah:BAAALAADCggIEQAAAA==.',Bi='Biby:BAAALAAFFAIIAgAAAA==.Bigschuz:BAAALAAECggIEwAAAA==.',Bl='Blackhorn:BAAALAADCggIDwAAAA==.Blackmask:BAAALAADCgcIDgAAAA==.Blindfolded:BAAALAAECgMICAAAAA==.Bloodpath:BAAALAADCgUIBQABLAADCggIDwABAAAAAA==.',Bo='Bobbyroxx:BAAALAAECgIIAgAAAA==.Bollek:BAAALAAECgMIAwAAAA==.Bonecrusher:BAAALAADCgEIAQAAAA==.Borbarad:BAAALAAECgMICAAAAA==.Borgramm:BAAALAADCggICAAAAA==.',Br='Bravier:BAAALAADCgcIBwAAAA==.Britneyfearz:BAAALAADCggICAABLAAECggIFgADAGwiAA==.',Bu='Bubblegummi:BAAALAADCgcIBwAAAA==.Buddelbernd:BAAALAADCggICAAAAA==.Bullfîre:BAAALAAECgIIAgAAAA==.Bullroot:BAAALAAECgYICQAAAQ==.',['Bä']='Bärenstark:BAAALAADCgcIDgAAAA==.',['Bè']='Bèyz:BAAALAAECgYIDgAAAA==.',Ca='Cachou:BAAALAADCggIFgAAAA==.Cadmasch:BAAALAAECgEIAgAAAA==.Caradhras:BAABLAAECoEVAAICAAgILx2HHgDKAQACAAgILx2HHgDKAQAAAA==.Caramîra:BAAALAAECgYIBgAAAA==.Castello:BAAALAAECgYIDQAAAA==.',Ce='Celil:BAAALAAECgMIAwAAAA==.Celinda:BAAALAADCggIFgAAAA==.Centorea:BAAALAADCgcICQAAAA==.Cerusela:BAAALAADCgIIAgAAAA==.',Ch='Chargebiene:BAAALAAECgIIBAAAAA==.Churki:BAABLAAECoEXAAMEAAgIrCByBgDaAgAEAAgIrCByBgDaAgAFAAEIZxktGQBLAAAAAA==.Churkilol:BAAALAAECgUIBQAAAA==.',Co='Cobrew:BAAALAADCggICAAAAA==.Coibrew:BAAALAADCggICAAAAA==.Conrep:BAAALAAECgQIBAAAAA==.Corann:BAAALAAECgUIDAAAAA==.',Cr='Cribl:BAAALAAECgEIAQAAAA==.Crich:BAAALAAECggIAQAAAA==.Critpala:BAAALAAECgUIBQAAAA==.Cronii:BAAALAAECgYICQAAAA==.Cruiser:BAAALAADCggIEAAAAA==.',Cu='Cutterrina:BAAALAADCgQIBQAAAA==.',Da='Dalarios:BAAALAADCgMIBwAAAA==.Darkknuffel:BAAALAADCgIIAgAAAA==.Darkyoda:BAAALAADCgMIAwAAAA==.Daywalkerdh:BAAALAAECgYICAAAAA==.',De='Delareyna:BAAALAAECgYIDQAAAA==.Deluge:BAAALAADCggICAABLAADCgMIAwABAAAAAA==.Denegar:BAAALAAECgYIDAAAAA==.Deschein:BAAALAAECgQIBQAAAA==.Destard:BAAALAADCgYICQAAAA==.',Di='Diamagiclein:BAAALAADCgQIBwAAAA==.Diggah:BAAALAAECgEIAQAAAA==.',Dr='Drachenhauch:BAAALAADCggICAAAAA==.Dragonmcm:BAAALAADCggICgAAAA==.Drakaries:BAAALAAECgYIDwAAAA==.Drakoth:BAAALAADCgYIBgAAAA==.',Du='Dugesia:BAAALAAECgIIBAAAAA==.Dummpfbacke:BAAALAADCggIEQAAAA==.',['Dø']='Døgne:BAAALAAECgcIDQAAAA==.',Ea='Eagleuno:BAAALAAECgYIBgAAAA==.Eatviol:BAAALAAECgcIBwAAAA==.',Ee='Eelessa:BAAALAAECgMIAwAAAA==.',Ei='Eilleen:BAAALAADCggIFgAAAA==.',El='Eladria:BAABLAAECoEUAAIGAAcIYhrDGQC4AQAGAAcIYhrDGQC4AQAAAA==.Eldrado:BAAALAADCggICAAAAA==.Elliè:BAAALAAECgMIBAAAAA==.Elynea:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.',Er='Erdwip:BAAALAADCgYIBgAAAA==.Erina:BAAALAAECgYIDAAAAA==.',Es='Ession:BAAALAAECgMICAAAAA==.',Eu='Euphory:BAAALAADCggICAAAAA==.',Fa='Fancynancy:BAAALAADCgYIBgAAAA==.',Fe='Felhound:BAAALAAECgMIAwAAAA==.Felshade:BAAALAAECgcIEQAAAA==.Fener:BAAALAAECgUICQAAAA==.Fettesschaf:BAAALAADCggIFQABLAAECgYICQABAAAAAA==.',Fi='Filicytas:BAAALAADCggIFQAAAA==.Finiz:BAAALAADCgUIBQAAAA==.Fiochi:BAAALAAECgEIAQAAAA==.Firunnqt:BAAALAADCggICgABLAAECgYIBgABAAAAAA==.Fizzle:BAAALAADCggICAABLAAECggIFgADAGwiAA==.',Fl='Flakest:BAAALAADCggICAAAAA==.',Fo='Foha:BAAALAADCggIDwAAAA==.',Fr='Frigobald:BAAALAADCggICQAAAA==.',Fu='Furorean:BAAALAAECgYICwAAAA==.',Fy='Fyrena:BAAALAADCggICAAAAA==.',Ga='Gamagos:BAAALAAECgYIDwAAAA==.Gannicus:BAAALAADCgcIBwAAAA==.',Ge='Geertje:BAAALAADCggICAAAAA==.Gegenverkehr:BAAALAADCggICAAAAA==.Gercrusher:BAAALAAECgQIBwAAAA==.',Gi='Gienga:BAAALAAECgIIBAAAAA==.Gilondil:BAAALAAECgYICQABLAAECggIFgADAGwiAA==.',Gl='Glaphan:BAAALAAECgYIDAABLAAECgYIDQABAAAAAA==.Glauron:BAAALAADCgcIFAAAAA==.',Go='Goldwing:BAAALAAECgMIBgAAAA==.Golgatha:BAAALAADCgcIDQAAAA==.Goslaktrote:BAAALAAECgYIEAAAAA==.',Gr='Gragàs:BAAALAADCgcIBwAAAA==.Grêg:BAAALAAECgIIAwAAAA==.',Gu='Gulsin:BAAALAAECgQIBgAAAA==.',['Gû']='Gûndabur:BAAALAAECgYIDAAAAA==.',Ha='Habibi:BAAALAADCgcIBwAAAA==.Haffí:BAAALAAECgYICQAAAA==.Hagazusa:BAAALAADCgMIAwAAAA==.Halkhar:BAAALAAECgYIDAAAAA==.Halldor:BAAALAADCggIDQAAAA==.Hanako:BAAALAADCggICgAAAA==.',He='Hedu:BAAALAAECgQIBwAAAA==.Helaskreem:BAAALAADCgcIBwAAAA==.Hexeanita:BAAALAAECgYIDwAAAA==.Hexiexi:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Hi='Hippo:BAAALAAECgQIBAABLAAECggIDwABAAAAAA==.Hippofive:BAAALAAECgQIBAAAAA==.Hippofour:BAAALAADCgYIBgABLAAECggIDwABAAAAAA==.Hipposix:BAAALAADCgYIBgABLAAECggIDwABAAAAAA==.Hippothree:BAAALAADCgYIBgABLAAECggIDwABAAAAAA==.Hippotwo:BAAALAAECggIDwAAAA==.',Ho='Holyfists:BAAALAAECgEIAQAAAA==.Horda:BAAALAAECgEIAQAAAA==.',Hu='Hullatrulla:BAAALAADCgYIBgAAAA==.Huntertank:BAAALAADCggIDQABLAAECgcICgABAAAAAA==.',Hy='Hypeset:BAAALAAECgQIBAAAAA==.',['Hê']='Hêl:BAAALAAECgMIAgAAAA==.',['Hô']='Hôlly:BAAALAADCggICAAAAA==.',Id='Idrien:BAAALAADCgcIBAAAAA==.',Ii='Iibu:BAAALAAECgMIAwAAAA==.',Il='Illumina:BAAALAAECgcIEQAAAA==.',In='Inania:BAAALAAECgEIAQAAAA==.Indirà:BAAALAAECgQIBQAAAA==.Inkipinki:BAAALAADCgIIAgAAAA==.',Ir='Ironstan:BAAALAADCgMIAwAAAA==.Irrii:BAAALAAECgUICQAAAA==.',Iz='Izanagi:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.',Ja='Jalani:BAAALAADCgcIBwAAAA==.',Je='Jeânne:BAAALAADCggICAAAAA==.',Jh='Jhove:BAAALAAECgEIAQAAAA==.',Ji='Jirokhan:BAAALAAECgUIBQAAAA==.',Jo='Jokerr:BAAALAAECggIDwAAAA==.',Ju='Jupiter:BAAALAAECgIIAgABLAAECgcIDQABAAAAAA==.Jurá:BAAALAAECgYIDQAAAA==.',['Jø']='Jøke:BAAALAADCgUIBQABLAAECggIDwABAAAAAA==.',Ka='Kaahanu:BAABLAAECoEVAAIHAAgILA2mKABMAQAHAAgILA2mKABMAQAAAA==.Kagenomiko:BAAALAAECgMIAwABLAAECgcICgABAAAAAA==.Kamiragi:BAAALAADCggIDwAAAA==.Kardanar:BAAALAADCggICAAAAA==.Karila:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Ke='Keana:BAAALAAECgEIAQAAAA==.Kermanudâs:BAAALAAECgYIDwAAAA==.',Ki='Killmachine:BAAALAAECgMICAAAAA==.Kimono:BAAALAADCggIEwAAAA==.Kiânâ:BAAALAAECgYIBgAAAA==.',Kl='Klaatu:BAAALAADCggICAAAAA==.Klingsohr:BAAALAAECggICAAAAA==.Klópfaer:BAAALAAECgQIBAAAAA==.',Ko='Kodoschänder:BAAALAAECggIDQABLAAECgYIDQABAAAAAA==.Kodumatu:BAAALAADCggIFAAAAA==.Korkran:BAAALAADCgQIBAAAAA==.',Kr='Kriegnieheal:BAAALAADCggIEAAAAA==.Kruber:BAAALAADCgYICQAAAA==.',Ku='Kurdran:BAAALAAECgQICAAAAA==.Kurushimu:BAAALAADCgcIBwAAAA==.',Ky='Kydia:BAAALAAECgIIAgAAAA==.',['Ká']='Káli:BAAALAAECgEIAQAAAA==.',['Kí']='Kíra:BAAALAADCgEIAQAAAA==.',La='Lasouris:BAAALAADCgQIBAAAAA==.',Le='Lemia:BAAALAADCgcIBwAAAA==.Lenarî:BAAALAAECgQIBAAAAA==.',Li='Lictor:BAAALAAECgIIBAAAAA==.Lilya:BAABLAAECoEVAAIIAAgI+Rn7EgDCAQAIAAgI+Rn7EgDCAQAAAA==.Limbozot:BAAALAADCgcIDQAAAA==.Liânâ:BAAALAAECgIIAgAAAA==.',Lo='Loqx:BAAALAADCggICAAAAA==.Lorian:BAAALAADCggIFgAAAA==.Lotgar:BAAALAADCgUIBQAAAA==.',Lu='Luminexa:BAAALAADCgUIBQAAAA==.Luniar:BAAALAADCggICAAAAA==.Lunábird:BAAALAAECgYICwAAAA==.Luro:BAAALAADCggIDAAAAA==.Luzifara:BAAALAAECgMIBQAAAA==.',Ly='Lydi:BAAALAAECgEIAQAAAA==.Lyranne:BAAALAAECgYICQAAAA==.Lyrissa:BAAALAAECgYIBgAAAA==.',['Lâ']='Lânessâ:BAAALAADCggICAAAAA==.',['Lé']='Léyá:BAAALAADCgYIBgAAAA==.',['Lî']='Lîyana:BAACLAAFFIEIAAIJAAIINxQ6CgCqAAAJAAIINxQ6CgCqAAAsAAQKgSEAAgkACAguIoQFACQDAAkACAguIoQFACQDAAAA.',Ma='Mado:BAAALAADCggICAAAAA==.Maio:BAAALAADCgcIEQAAAA==.Malirog:BAAALAADCggICAAAAA==.Maluforion:BAAALAADCggIFAAAAA==.Manscreeda:BAABLAAECoEVAAMKAAgI2SJbJQD+AQAKAAgIjCJbJQD+AQAIAAQIDx62JQATAQAAAA==.Manuellsen:BAAALAAECgYICgAAAA==.Maultäschle:BAAALAAECgYICQAAAA==.Mayva:BAAALAADCggIEwAAAA==.Mazzerules:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.',Mc='Mcgee:BAAALAADCggICAAAAA==.Mcwastey:BAAALAAECgMIAwAAAA==.',Me='Mehran:BAABLAAECoEWAAIDAAgIbCKrAwAoAwADAAgIbCKrAwAoAwAAAA==.',Mi='Mickey:BAAALAAECgMICAAAAA==.Miniarthas:BAAALAAECgYICAAAAA==.Mirakulix:BAAALAAECgcIEAAAAA==.',Mo='Monkeykøng:BAAALAADCggICAAAAA==.Monkomg:BAAALAADCggIDwAAAA==.Mononoke:BAAALAADCggIDQAAAA==.Moonnights:BAAALAADCggIFgAAAA==.Morgainea:BAAALAADCgUIBQAAAA==.Morodeth:BAAALAAECgYIEAAAAA==.',My='Mybabe:BAAALAAECgQIBAABLAAECgYIDQABAAAAAA==.Mykera:BAAALAADCgMIBwAAAA==.Myrelia:BAAALAADCgcIEQAAAA==.',['Má']='Májor:BAAALAAECgMIBgAAAA==.',['Mä']='Mäggi:BAAALAADCgYIDAAAAA==.',['Mì']='Mìkasa:BAAALAAECgcIDwAAAA==.',['Mí']='Míraculix:BAAALAADCgUIAgABLAADCgMIAwABAAAAAA==.',Na='Nabu:BAAALAAECgIIAwAAAA==.Nane:BAAALAADCggICAAAAA==.Naraani:BAAALAAECgYIBwAAAA==.Nathiniel:BAAALAADCggIGAAAAA==.Naíra:BAAALAAECgYIEAAAAA==.',Ne='Neadana:BAAALAADCgUIBQAAAA==.Nebbia:BAAALAADCgcIBwAAAA==.Necrox:BAAALAAECgEIAQAAAA==.Needamedic:BAAALAAECggIAQAAAA==.Nefflo:BAAALAADCggIFgAAAA==.Neolon:BAAALAADCggIFQAAAA==.Neptune:BAAALAADCgcICwABLAAECgcIDQABAAAAAA==.Nergrim:BAAALAAECgIIAgAAAA==.Nezukø:BAAALAADCgQIBAAAAA==.Neÿtiri:BAAALAADCggIDwABLAAECgMIBQABAAAAAA==.',Ni='Nia:BAABLAAECoEVAAMLAAgIuxb2GQDsAQALAAgIuxb2GQDsAQAMAAcIZBwAAAAAAAAAAA==.Nidhog:BAAALAADCgcIBwAAAA==.Nimiel:BAAALAAECgYIEAAAAA==.Ninwe:BAAALAAECggIEAAAAA==.Nirî:BAAALAADCggIEAAAAA==.',No='Nordfee:BAAALAADCggIDgAAAA==.Nose:BAAALAADCggIDwAAAA==.Noura:BAAALAAECgMIAwABLAAECggIFgADAGwiAA==.Novania:BAAALAADCggIFAAAAA==.',['Né']='Néelo:BAAALAAECgUICQAAAA==.Nééla:BAAALAADCggICAAAAA==.',['Ní']='Nímué:BAAALAADCgUIBQAAAA==.',Oa='Oahin:BAAALAAECgQIBwAAAA==.',Oc='Ocinsperle:BAAALAADCgcIFQAAAA==.',Ok='Oktayo:BAAALAAECgYIEAAAAA==.',Ol='Olleg:BAAALAADCggICAAAAA==.',On='Onlybuffing:BAAALAAECgcICgAAAA==.',Or='Orklord:BAAALAAECgIIAgAAAA==.',Oy='Oya:BAAALAAECgEIAQAAAA==.',Pa='Pahtfinder:BAAALAAECgYIDgAAAA==.Panicpriest:BAAALAADCggIFAAAAA==.',Pe='Perccival:BAAALAADCgcIDgAAAA==.',Ph='Phirunn:BAAALAAECgYIBgAAAA==.Phoinix:BAAALAAECgYICAAAAA==.',Pi='Piandao:BAAALAADCggICgAAAA==.',Pl='Plattenrind:BAAALAAECgIIAwAAAA==.Pluizig:BAAALAADCggICwAAAA==.Pluto:BAAALAAECgcIDQAAAA==.',Po='Polyphemus:BAAALAADCggICAAAAA==.',Pr='Priestar:BAAALAADCgMIAwAAAA==.Priestomat:BAAALAAECgMIAwAAAA==.Protóss:BAAALAAECgYIBwAAAA==.',Pu='Pulsarine:BAAALAADCgcIBwAAAA==.',['Pí']='Píwo:BAAALAADCgcIBwAAAA==.',['Pû']='Pûrple:BAAALAADCggIFgAAAA==.',Ra='Rado:BAAALAAECgMIBAAAAA==.Raftalia:BAAALAAECgYICwAAAA==.Rainjuná:BAAALAADCgYIBgAAAA==.Raldor:BAAALAADCgcIBwAAAA==.Ranctar:BAAALAAECgEIAQAAAA==.Randalegabi:BAAALAADCggIDwAAAA==.',Re='Reaktorkalle:BAAALAADCgUIBQAAAA==.Redban:BAAALAAECgEIAQAAAA==.',Rh='Rhoninn:BAAALAADCggIFgAAAA==.',Ri='Riragu:BAAALAADCggICAAAAA==.',Ro='Roniñ:BAAALAADCgcIBwAAAA==.Rowyn:BAAALAADCgcICAAAAA==.',Ru='Rubbeldekatz:BAAALAAECgMIAwAAAA==.Runar:BAAALAADCggIDQAAAA==.',Ry='Ryllira:BAAALAAECgcIEAAAAA==.',['Rì']='Rìger:BAAALAADCggIDgAAAA==.',['Rý']='Rýu:BAAALAAECggIDwAAAA==.',Sa='Sahlex:BAAALAAECgIIAgAAAA==.Sameth:BAAALAAECgEIAQAAAA==.Sanitas:BAAALAADCgcIBwAAAA==.Sanitöterin:BAAALAADCgcIBwAAAA==.Saïx:BAAALAADCgcIBwAAAA==.',Sc='Schnensch:BAAALAADCggIDQAAAA==.',Se='Seraphini:BAAALAADCgYIBgAAAA==.Seresa:BAAALAAECgMICAAAAA==.Serino:BAAALAADCgYIBgABLAAECgYIDAABAAAAAA==.Serion:BAAALAADCgcIDgAAAA==.',Sh='Shamystyles:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.Sharíva:BAAALAAECgYICwAAAA==.Shenlian:BAAALAADCgEIAQAAAA==.Shivà:BAAALAADCgcIBwAAAA==.Shonyy:BAAALAAECgYICgAAAA==.Shruikán:BAAALAAECgYIDQAAAA==.',Si='Sicklikemanu:BAAALAAECgQIBAABLAAECggIDwABAAAAAA==.Sinder:BAAALAADCgYICQAAAA==.',Sk='Skruggur:BAAALAAECgEIAgAAAA==.',Sn='Snakebíte:BAAALAAECgIIBAABLAADCgMIAwABAAAAAA==.',So='Soláris:BAAALAADCggIDwAAAA==.',Sp='Speik:BAAALAADCggICAAAAA==.',St='Starshine:BAAALAAECgYIDQAAAA==.',Su='Sugarswini:BAAALAAECgIICAAAAA==.Sumíre:BAABLAAECoEWAAINAAgI4SFCBADiAgANAAgI4SFCBADiAgAAAA==.',Sw='Swagbanana:BAAALAAECgYIEgAAAA==.Swiffer:BAABLAAECoEVAAIOAAgI7RdsGwD4AQAOAAgI7RdsGwD4AQAAAA==.Swordart:BAAALAAECgQIBQAAAA==.',Sy='Syndra:BAAALAADCgQIBAAAAA==.',['Só']='Sóláris:BAAALAAECggIBQAAAA==.',Ta='Tadashi:BAAALAADCggICAAAAA==.Talej:BAAALAADCgcICgAAAA==.Tarabo:BAAALAADCgEIAQAAAA==.Taramira:BAABLAAECoEUAAIPAAgIah6lAwCxAgAPAAgIah6lAwCxAgAAAA==.Tayulia:BAABLAAECoEWAAIQAAgI6SMMBwAcAwAQAAgI6SMMBwAcAwAAAA==.',Tb='Tbone:BAAALAAECgIIAgAAAA==.',Te='Telura:BAAALAAECgUIAgAAAA==.Telvor:BAAALAADCgUIBgAAAA==.',Th='Thargoll:BAAALAAECgIIAwABLAAECggIFAARAOQkAA==.Thetamarie:BAAALAADCggIFgAAAA==.Thoreas:BAAALAAECgMIBQAAAA==.Thulazea:BAAALAAECgYIDwAAAA==.Thuzad:BAABLAAECoEWAAIJAAgIUh9BDADMAgAJAAgIUh9BDADMAgAAAA==.',Ti='Tiggy:BAAALAAECgIIAgAAAA==.',Tj='Tjojo:BAAALAADCgYIBgAAAA==.',To='Torglosch:BAAALAADCgcICQAAAA==.',Tr='Trivia:BAAALAADCgEIAQAAAA==.Trokdur:BAAALAADCgYIBgAAAA==.Trucy:BAAALAAECgYICgAAAA==.Trînîty:BAAALAAECgMIBwAAAA==.',Ty='Tyrael:BAAALAADCgMIAwAAAA==.Tyraja:BAAALAADCgcIBgAAAA==.',Ul='Ulfgrim:BAAALAADCggIBwAAAA==.Ulthane:BAAALAADCggIFgAAAA==.Ultrajoker:BAAALAADCgcICgAAAA==.',Un='Unmenschlich:BAAALAADCgYIBgAAAA==.',Ur='Uranus:BAAALAAECgMIBQABLAAECgcIDQABAAAAAA==.',Va='Valunia:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.Varojin:BAAALAADCggIDQAAAA==.',Ve='Vectus:BAAALAADCggIFgAAAA==.Vegacraftdk:BAAALAAECgQIBAAAAA==.Vegadudu:BAAALAADCgIIAgAAAA==.Venatrixx:BAAALAAECgEIAQAAAA==.Veroniká:BAAALAADCgcIBwAAAA==.',Vo='Vokalmatadór:BAAALAAECgMIBQAAAA==.',Wa='Waldfèe:BAABLAAECoEWAAIMAAgIAwvUIQCfAQAMAAgIAwvUIQCfAQAAAA==.Warnichtda:BAAALAADCgcIDwAAAA==.',Wi='Wizzie:BAAALAAECgEIAQAAAA==.',Wu='Wutzz:BAAALAADCggIEAAAAA==.',['Wü']='Wünschelrute:BAAALAADCgcIDgAAAA==.',Xa='Xaren:BAAALAAECgQIBAABLAAFFAIIAgABAAAAAA==.',Xe='Xemnas:BAAALAADCgcIDAAAAA==.',Xi='Xiakan:BAACLAAFFIEFAAISAAMIrh1ZAQARAQASAAMIrh1ZAQARAQAsAAQKgRcAAhIACAgjJCoBAEgDABIACAgjJCoBAEgDAAAA.',Xo='Xonay:BAAALAAECgcIDwAAAA==.Xorean:BAAALAADCgYIBgAAAA==.',Xy='Xyriel:BAAALAADCgcICwAAAA==.',['Xà']='Xàvador:BAAALAAECgMIAwAAAA==.',Ya='Yasuo:BAAALAAECgUIDAAAAA==.Yaya:BAAALAADCggIEAAAAA==.',Yo='Yooda:BAAALAAECgEIAQAAAA==.Yoshino:BAAALAAECgYIBgAAAA==.Youri:BAAALAADCgcIBwAAAA==.',Yu='Yukino:BAAALAADCgcIBwAAAA==.',Za='Zadora:BAAALAADCgcIDgAAAA==.Zahard:BAAALAADCgYIBgAAAA==.Zalagos:BAAALAADCggIFAAAAA==.Zarakez:BAAALAADCgcIDQAAAA==.',Ze='Zeeus:BAAALAADCgcIBwAAAA==.',Zi='Zirash:BAAALAAECgMIAwAAAA==.',Zu='Zurako:BAAALAADCgUIBQAAAA==.',Zw='Zwergblase:BAAALAADCggIDwAAAA==.',['Âl']='Âlessia:BAAALAADCggIDwAAAA==.',['Ân']='Ânastasiâ:BAAALAAECgYICQAAAA==.',['Ât']='Âtârî:BAAALAADCggIFQAAAA==.',['År']='Årtemis:BAAALAADCgcIDQAAAA==.',['Æs']='Æsyr:BAAALAADCgcIFAAAAA==.',['Én']='Éndure:BAAALAADCggIDwAAAA==.',['Ðe']='Ðementeus:BAAALAAECgYIDAAAAA==.',['Ði']='Ðingsdá:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end