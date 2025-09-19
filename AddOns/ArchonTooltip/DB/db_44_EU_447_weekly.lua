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
 local lookup = {'Unknown-Unknown','Druid-Feral','Evoker-Devastation','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Frost','Hunter-Marksmanship',}; local provider = {region='EU',realm='Malorne',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abtropfdecke:BAAALAAECgIIAgAAAA==.',Ac='Acidmäuschen:BAAALAADCgYIBgAAAA==.',Ad='Adania:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Adrialla:BAAALAAECgEIAQAAAA==.',Ae='Aeowyn:BAAALAAECggIDQAAAA==.',Ah='Ahlol:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.',Ak='Aktronum:BAAALAADCgcICQAAAA==.',Al='Alef:BAAALAAECgQICQAAAA==.Alesandra:BAAALAADCgYIBgAAAA==.Alpstatcher:BAABLAAECoEVAAICAAgInB6LBQBfAgACAAgInB6LBQBfAgAAAA==.Althèa:BAAALAADCggICwAAAA==.',An='Angespüllt:BAAALAADCgEIAQAAAA==.Anomander:BAAALAADCgcIBwAAAA==.Anthik:BAAALAADCggIDAAAAA==.Anûk:BAAALAADCgcIEAAAAA==.',Ap='Apeiron:BAAALAADCggIDwAAAA==.Aphrothite:BAAALAADCgYIDQAAAA==.Appleblossom:BAAALAADCgEIAQAAAA==.',Ar='Arcus:BAAALAADCggIDwAAAA==.Arms:BAAALAAECgEIAQAAAA==.Arnantel:BAAALAAECgYIBgAAAA==.Arugos:BAAALAADCggICAAAAA==.',As='Asagiri:BAAALAADCggICAAAAA==.Ashterian:BAAALAADCgUIBQAAAA==.',At='Athenaris:BAAALAAECgUIBQAAAA==.',Aw='Awhorn:BAAALAAECgcIEAAAAA==.',Ax='Axtuz:BAAALAAECgQIBQAAAA==.',Ba='Badadan:BAAALAADCgQIBAAAAA==.',Be='Beatricx:BAAALAADCggIEAAAAA==.Bevla:BAAALAADCggIAQAAAA==.',Bi='Bigblackwolf:BAAALAADCgcIDQAAAA==.Bigman:BAAALAADCgcICQAAAA==.',Bl='Bloubs:BAAALAADCggIEAAAAA==.Bluwar:BAAALAADCgEIAQAAAA==.',Bo='Borgar:BAAALAAECgMIBgAAAA==.',Br='Brewfox:BAAALAAECgYIBgAAAA==.Brewslee:BAAALAAECggIEAAAAA==.Bronzos:BAAALAAECgEIAQAAAA==.',Bu='Buffdaddy:BAAALAADCgUIBQAAAA==.',['Bü']='Büli:BAAALAADCggIDwAAAA==.Bülizette:BAAALAADCgcIBwAAAA==.',Ca='Cadira:BAAALAADCgcIEAAAAA==.Caelesdris:BAAALAADCggIFwAAAA==.Calligola:BAAALAADCggIGwAAAA==.Carcaras:BAAALAADCgYIDQAAAA==.',Ch='Chishi:BAAALAAFFAIIAgAAAA==.Chordeva:BAAALAAECgcIDQAAAA==.Chrille:BAAALAADCgcIEAAAAA==.',Co='Codil:BAAALAAECgEIAQAAAA==.Collete:BAAALAAECgMIAwAAAA==.',Cr='Crîtical:BAABLAAECoEUAAIDAAgImgoDHAB4AQADAAgImgoDHAB4AQAAAA==.',Da='Daman:BAAALAAECgcIEAAAAA==.Daredèvil:BAAALAADCgYIBgABLAADCgYIDwABAAAAAA==.Davo:BAAALAADCggICAAAAA==.',De='Deamonpuffi:BAAALAAECgYIDAAAAA==.Deathbrecher:BAAALAAECgYICQAAAA==.Deracos:BAAALAAECgYIDgAAAA==.',Di='Divus:BAAALAAECgEIAQAAAA==.',Do='Domba:BAAALAADCggICQAAAA==.Doofus:BAAALAAECgQIBgAAAA==.',Dr='Dracalyss:BAAALAAECgEIAQAAAA==.Drmidnight:BAAALAAECgEIAgAAAA==.Droetker:BAAALAADCgQIBAAAAA==.Drâgonheart:BAAALAADCggICwAAAA==.',['Dé']='Dée:BAAALAADCgIIAgAAAA==.',['Dö']='Dödlich:BAAALAAECgYIDAAAAA==.',El='Eladros:BAAALAAECgMIBAABLAAECgQIBgABAAAAAA==.Eleeven:BAAALAAECgEIAQAAAA==.Elenor:BAAALAAECgMIBAAAAA==.Elvendra:BAAALAAECgcIDAAAAA==.',Em='Emilyprocter:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',En='Endivié:BAAALAADCgYIBQAAAA==.Endû:BAAALAAECgUIBQAAAA==.',Ev='Everytimetii:BAAALAAECggIEQAAAA==.',Fa='Fael:BAAALAADCgQIBAAAAA==.Farios:BAAALAADCgYIBgAAAA==.',Fe='Feuergirl:BAAALAAECgMIAwAAAA==.',Fi='Finn:BAAALAADCggIDwAAAA==.',Fl='Fludra:BAAALAADCgcICgAAAA==.Flumbri:BAAALAADCggICAAAAA==.',Fr='Fremenzorn:BAAALAAECggICAAAAA==.Friendlyfire:BAAALAAECgEIAgAAAA==.',Ga='Gaman:BAAALAADCggICAAAAA==.Garurumon:BAAALAAECgcIEAAAAA==.',Ge='Geller:BAAALAAECgEIAgAAAA==.Gerrost:BAAALAADCgYIBgAAAA==.',Go='Gordi:BAAALAADCgcIDAAAAA==.Gordislan:BAAALAADCggICwAAAA==.',Gr='Grambo:BAAALAAECgMIAwAAAA==.Grimmig:BAAALAADCgcIBwAAAA==.Groktan:BAAALAADCgcIBwAAAA==.',Gu='Gunsound:BAAALAAECggIEQAAAA==.',Ha='Harbrad:BAAALAAECgMIAwAAAA==.Harmony:BAAALAAECgIIBAAAAA==.',He='Hexidor:BAAALAAECggICgAAAA==.Hexxy:BAAALAAECgEIAQAAAA==.',Hj='Hjoldor:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.',Hl='Hlavacek:BAAALAAECgMIAwAAAA==.',Ho='Holymolyy:BAAALAAFFAIIAgAAAA==.Hornpranke:BAAALAADCgUIBQAAAA==.',Hu='Huntermaster:BAAALAAECgcIEAAAAA==.Huntermastér:BAAALAADCgcICgAAAA==.',Hy='Hyperio:BAAALAADCgUIBQAAAA==.',['Hâ']='Hâyle:BAEALAAECggIEAAAAA==.',['Hé']='Hélios:BAAALAAECgEIAQAAAA==.',['Hö']='Hörmeline:BAAALAAECgEIAQAAAA==.',Ig='Ignitethesky:BAAALAAECgYIBgABLAAECgYIEAABAAAAAA==.',Il='Illinoi:BAAALAAECgIIAgAAAA==.',Im='Imerius:BAAALAAECgYIBgAAAA==.',In='Inlord:BAAALAADCggICgAAAA==.Inéèdmoney:BAAALAADCgQIBAAAAA==.',Ir='Iraniasa:BAAALAADCgcIDAAAAA==.Irodana:BAAALAADCggICQAAAA==.',Jo='Joeyjoey:BAAALAADCgcIEwAAAA==.',['Jû']='Jûstêr:BAAALAAECgIIAgAAAA==.',Ka='Kajiva:BAABLAAECoEVAAIEAAgIBB+YAgCKAgAEAAgIBB+YAgCKAgAAAA==.Kajsha:BAAALAAECgMIAwAAAA==.Kampfeis:BAAALAADCgMIAgAAAA==.',Kh='Khagan:BAAALAADCgUIBwAAAA==.',Ki='Kittel:BAAALAADCgcIEwAAAA==.',Kn='Knox:BAAALAADCgcIEQAAAA==.',Ko='Kopii:BAAALAADCgcICQAAAA==.',Kr='Kreepy:BAAALAADCggICwAAAA==.Kryptoli:BAAALAADCgQIBgAAAA==.',Ky='Kyudo:BAAALAADCggIDQAAAA==.',La='Lagoper:BAABLAAECoEXAAMFAAgIHRHpDACUAQAFAAcIwBLpDACUAQAGAAEIpQWLkAAaAAAAAA==.Largann:BAAALAAECgYICwAAAA==.',Le='Leccram:BAAALAAECgEIAQAAAA==.Leyarah:BAAALAAECgMIAwAAAA==.',Lf='Lfarenamate:BAAALAAECgYIDAABLAAECggIEQABAAAAAA==.',Li='Linora:BAAALAAECgMIAwAAAA==.Liroxf:BAAALAADCgcIDgAAAA==.Livana:BAAALAAECgMIAwAAAA==.',Lo='Lockomotion:BAAALAADCggICAAAAA==.Lockomotîve:BAAALAADCggICAAAAA==.',Lu='Lunaraa:BAAALAAECgYIDAAAAA==.',Ly='Lynissel:BAAALAAECgIIAwAAAA==.',['Lè']='Lèlè:BAAALAAECgEIAQAAAA==.',Ma='Magicmarvin:BAABLAAECoEVAAIHAAgIExsmCwAtAgAHAAgIExsmCwAtAgAAAA==.Magietron:BAAALAADCggICAAAAA==.Maldorn:BAAALAAECgUICwAAAA==.Manadead:BAAALAADCgIIAgAAAA==.Marîne:BAAALAAECgcIEAAAAA==.Matthiasb:BAAALAAECgMIAwAAAA==.',Mc='Mcroguehd:BAAALAADCggIDQAAAA==.',Mi='Millicence:BAAALAAECgQIBAAAAA==.Mirigolia:BAAALAAECgEIAgAAAA==.',Mo='Moondust:BAAALAAECgYIDAAAAA==.Movistar:BAAALAADCgIIAwABLAADCgUIBQABAAAAAA==.',Mu='Mullky:BAAALAAECgQIBwAAAA==.Murlocmaster:BAAALAADCggICAAAAA==.Mutare:BAAALAAECgEIAgAAAA==.',['Mè']='Mèowjò:BAAALAADCgUIBQAAAA==.Mèphala:BAAALAAECgEIAQAAAA==.',['Mø']='Møøn:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Na='Naman:BAAALAADCggICAAAAA==.',Ne='Nemli:BAAALAAECgQIBgAAAA==.',Ni='Niene:BAAALAADCgIIAgAAAA==.Nightlord:BAAALAADCgcICwAAAA==.Ningaloo:BAAALAADCggIEgAAAA==.Niyu:BAAALAAECgYIBgAAAA==.',No='Noita:BAAALAAECgUIBAAAAA==.',Ny='Nym:BAAALAAECgYIDgAAAA==.Nymzweisoft:BAAALAAECgYIDAAAAA==.Nyrul:BAAALAADCggICgAAAA==.',['Nâ']='Nâhíshôk:BAAALAADCgYIBwAAAA==.',Ob='Obivan:BAAALAAECgMIAwAAAA==.',Od='Odiark:BAAALAADCgcIBQAAAA==.',Ol='Oldjasper:BAAALAADCgYIBgAAAA==.',Or='Orctopus:BAAALAADCgcIBwAAAA==.',Pa='Pakuna:BAAALAADCgYIBgAAAA==.Palami:BAAALAADCggIEgAAAA==.Palduin:BAAALAADCgUIBQAAAA==.Panzér:BAAALAAECgQIBAAAAA==.',Ph='Phaedra:BAAALAAECgYIDAAAAA==.',Pl='Plankuaa:BAAALAADCgIIAgAAAA==.Plyb:BAAALAAECgcICgAAAA==.',Po='Poong:BAAALAAECggIBgAAAA==.Powerzero:BAAALAADCggIDwAAAA==.',Pr='Promethèus:BAAALAAECggICAAAAA==.',Pu='Pullekorn:BAAALAAECgYIDAAAAA==.',Qu='Quintessa:BAAALAADCgcIBwAAAA==.Quorraa:BAAALAADCggICAAAAA==.',Qy='Qyron:BAAALAAECgEIAQAAAA==.',Ra='Raiga:BAAALAADCggICAAAAA==.Ramui:BAAALAAECggIDQAAAA==.Rayri:BAAALAADCgQICQAAAA==.',Re='Reaven:BAAALAADCgYIBgAAAA==.Reload:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.Reláxx:BAAALAADCggICAAAAA==.Remâ:BAAALAADCgYIBQAAAA==.Rerollinc:BAAALAADCgcIDAAAAA==.Revilondo:BAABLAAECoEVAAIIAAgIASElBAAEAwAIAAgIASElBAAEAwAAAA==.',Ri='Rindeastwood:BAAALAADCgUIBQAAAA==.Rizzi:BAAALAAECgIIAwAAAA==.',Ro='Roccan:BAAALAAFFAEIAQAAAA==.Roguekuaa:BAAALAAECgYIDQAAAA==.',['Rö']='Röstie:BAAALAAECgMIAwAAAA==.',Sa='Sabrichu:BAAALAAECgYIBgAAAA==.Sanii:BAAALAADCggIDgAAAA==.Santacruz:BAAALAAECgMIAwAAAA==.',Sc='Schestag:BAAALAADCgUIBQAAAA==.Schmocktan:BAAALAADCgUIBQAAAA==.Schnufflchen:BAAALAADCgYIBQAAAA==.Schnulle:BAAALAADCgYIBgAAAA==.Schpock:BAAALAADCgMIAwAAAA==.Schôrlé:BAAALAAECgYIEAAAAA==.',Se='Senzuu:BAAALAAECggIBAAAAA==.Seríous:BAAALAAECggICgAAAA==.',Sh='Shikarilock:BAAALAAECgYIDAAAAA==.Shokxs:BAAALAAECgYIDAAAAA==.Shubi:BAAALAADCggICAAAAA==.Shuyet:BAAALAADCgYIBgAAAA==.Shyrlonay:BAAALAAFFAIIAgAAAA==.Shìkarì:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Shùkà:BAAALAADCggIDAAAAA==.',Si='Silaya:BAAALAAECgMIAwAAAA==.Silvercastle:BAAALAADCgcIBwAAAA==.Sindarin:BAAALAAECgMIAwAAAA==.',Sk='Skoja:BAAALAAECgYIBgAAAA==.Skybrother:BAAALAADCggICAAAAA==.Skyró:BAAALAAECgYIBgAAAA==.',Sn='Snipèz:BAAALAAECgYICwAAAA==.',St='Strangè:BAAALAADCgYIDwAAAA==.Strikeboy:BAAALAAECgIIAwAAAA==.',Su='Surianna:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâbrînâ:BAAALAAECgYICQAAAA==.Sâitô:BAAALAAECgYICwAAAA==.Sânera:BAEALAAECggICAABLAAECggIEAABAAAAAA==.',Ta='Tangó:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Tayras:BAAALAAECgYIDAAAAA==.',Te='Teufelchen:BAAALAADCgIIAgAAAA==.',Th='Thamoran:BAAALAAECgMIAwAAAA==.Theødwyn:BAAALAAECgMIAwAAAA==.Thiccel:BAAALAADCgcIEwAAAA==.Thungild:BAAALAADCgcIBwAAAA==.',Ti='Tiondra:BAAALAADCgcIBwABLAAECgcIDAABAAAAAA==.',To='Tomaso:BAAALAADCgcIEAAAAA==.',Tr='Trolljawoll:BAAALAAECgcIEAAAAA==.Tríckshòt:BAAALAADCgMIAwAAAA==.Trûlly:BAAALAADCggIDwAAAA==.',Ts='Tschackeline:BAAALAADCgcIFQAAAA==.',Tu='Tube:BAAALAAECgYIBgAAAA==.Tuxan:BAAALAADCgYIBgAAAA==.',Tw='Tweetnonie:BAAALAADCggICAAAAA==.',Ty='Tysal:BAAALAADCgcIDgAAAA==.',['Tá']='Tángo:BAAALAAECgYIBwAAAA==.Tángó:BAAALAAECgYIBwABLAAECgYIBwABAAAAAA==.',['Tö']='Tödlich:BAAALAAECgcIEAAAAA==.',Ur='Uraco:BAAALAADCgUIBQAAAA==.',Va='Vanimeril:BAAALAADCgcIBgAAAA==.',Ve='Verflucht:BAAALAADCgQIBAABLAADCgUIBQABAAAAAA==.Veridisquo:BAAALAAECgYIBgAAAA==.Veteris:BAAALAADCggIGwABLAAECgEIAgABAAAAAA==.',Vi='Vitili:BAAALAAECgYIDgAAAA==.',Vo='Vogelfrei:BAAALAAECgcIEAAAAA==.',Vr='Vrisea:BAAALAAECgYIDQAAAA==.',['Vá']='Válería:BAAALAAECggIAgAAAA==.',['Vâ']='Vânhell:BAAALAADCgQIBAAAAA==.',Wa='Warcheeze:BAAALAADCgcIBwAAAA==.',We='Wengaif:BAAALAAECgYICQAAAA==.',Wo='Wollów:BAAALAADCgcIAQAAAA==.',Wy='Wyonna:BAAALAADCggICAAAAA==.',['Wû']='Wûrres:BAAALAADCgcIBwAAAA==.',Xa='Xarthos:BAAALAAECgMIAwAAAA==.',Xo='Xorthas:BAAALAADCgcIBwAAAA==.',Yi='Yilaza:BAAALAAECgMIAwAAAA==.',Yo='Yoshíko:BAAALAAECgcIEAAAAA==.',Za='Zamuel:BAAALAADCgYIDQAAAA==.',Zi='Zimidir:BAAALAAECgYICgAAAA==.',Zz='Zzornröschen:BAAALAADCgEIAQAAAA==.',['Zâ']='Zâhl:BAAALAADCgYIBgAAAA==.',['Zé']='Zéyróx:BAAALAADCgUIBQAAAA==.',['Âf']='Âffemitwaffe:BAAALAAECgYIDgAAAA==.',['Æz']='Æzrael:BAAALAAECgcICQAAAA==.',['Éd']='Éd:BAAALAADCgUIBQAAAA==.',['Él']='Élrond:BAAALAADCggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end