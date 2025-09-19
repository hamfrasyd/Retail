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
 local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Outlaw',}; local provider = {region='EU',realm='Area52',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abbigail:BAAALAADCggICAAAAA==.',Al='Alphazerø:BAAALAAECggIBgAAAA==.',An='Angeldeath:BAAALAADCgYIBwAAAA==.Angelo:BAAALAADCggIEgAAAA==.',Ap='Apokalyptiko:BAAALAADCggIEAAAAA==.',Ar='Aragny:BAAALAADCgcIBwAAAA==.Aratot:BAAALAADCgYIBgAAAA==.Ardela:BAAALAADCggIGwAAAA==.Arriba:BAAALAAFFAIIAgABLAAFFAIIAgABAAAAAA==.Artemispan:BAAALAAECgMIAwAAAA==.Arthamas:BAAALAAECgEIAgAAAA==.Artura:BAAALAADCgcICwAAAA==.',As='Asela:BAAALAAECgMIBgAAAA==.Ashbrínger:BAAALAADCggIFAAAAA==.',Av='Avandarra:BAAALAAECgMIBQAAAA==.',Ay='Ayjumi:BAAALAADCggICAAAAA==.',Ba='Baleríon:BAAALAADCgIIAgAAAA==.',Be='Belegòr:BAAALAADCgYIBgABLAAECgMIBgABAAAAAA==.Belethel:BAAALAAECgMIAwAAAA==.Belga:BAAALAAECgUIBwAAAA==.Bergamont:BAAALAAECgYIEQAAAA==.',Bl='Bloodbath:BAAALAAECggIBwABLAAECggIDAABAAAAAA==.Bloodsaw:BAAALAADCgIIAgAAAA==.Bluuh:BAAALAADCgYIBgAAAA==.',Bo='Bokenroder:BAAALAADCggIDwAAAA==.',Br='Braruk:BAAALAAECgYICgAAAA==.Braveheart:BAAALAAECgMIAwAAAA==.Brendra:BAAALAAECgIIBAAAAA==.Bruzagg:BAAALAADCggIDQAAAA==.',Bu='Bulltrok:BAAALAADCgYIBgAAAA==.',Ca='Caedos:BAAALAAECgYICQAAAA==.Calico:BAAALAADCgcIDgAAAA==.Carmody:BAAALAADCggIEwAAAA==.Castìel:BAAALAADCgYIBQABLAAECgYICgABAAAAAA==.',Ce='Cellestin:BAAALAAECgYIBgAAAA==.',Ch='Chantîcô:BAAALAADCggICAAAAA==.Chay:BAAALAADCggICAAAAA==.Chicoree:BAAALAAECgMIBQAAAA==.Chih:BAAALAADCgcICAAAAA==.Chiropax:BAAALAAECgEIAQAAAA==.Chiy:BAAALAAECgYICwAAAA==.',Cy='Cyberhood:BAAALAAECgcIDQAAAA==.',['Cé']='Cémál:BAAALAADCggICAAAAA==.',Da='Dacary:BAAALAADCgYIBgAAAA==.Dadiloo:BAAALAAECgcIDAAAAA==.Daewae:BAAALAADCgIIAgAAAA==.Dalavar:BAAALAAECgMIBgAAAA==.',De='Deathmakesh:BAAALAAECgYIDgAAAA==.Debiddo:BAAALAAECgcICAAAAA==.Deepcrystal:BAAALAAECgUICwAAAA==.',Dh='Dhdd:BAAALAADCgIIAgAAAA==.',Dk='Dktanko:BAAALAADCgIIAgAAAA==.',Dr='Dragonstorm:BAAALAADCgcIDgAAAA==.Dralikor:BAAALAAECgYIDAAAAA==.Drexi:BAAALAADCggIDwABLAAECgYIBgABAAAAAA==.',['Dâ']='Dârkbeauty:BAAALAADCggIHAABLAAECgcIDAABAAAAAA==.',Ed='Edgelord:BAAALAADCgYIBwAAAA==.',Ei='Eisenwolf:BAAALAADCgcIBwAAAA==.',Er='Eretria:BAAALAADCggIGwAAAA==.',Ey='Eyfalja:BAAALAADCggICwAAAA==.',Ez='Ezkonopie:BAAALAAECggIDQAAAA==.',Fa='Fanfan:BAAALAAECgIIAgAAAA==.Faya:BAAALAADCgMIAwAAAA==.',Fe='Festnetz:BAAALAAECgcIDQAAAA==.',Fk='Fk:BAAALAAECgYIBQABLAAECgcIEAABAAAAAA==.',Fl='Fly:BAAALAAECgYICgAAAA==.',Ft='Ftmsouthgate:BAAALAAECggIBgAAAA==.',Fu='Fuegos:BAAALAAFFAIIAgAAAA==.Fuying:BAAALAADCgEIAQAAAA==.',Ga='Gabriela:BAAALAAECgYICgAAAA==.Gambeero:BAAALAAECgMIBQAAAA==.Gatzi:BAAALAAECgYICAAAAA==.',Gi='Gigagott:BAAALAADCggICAAAAA==.Gimlis:BAAALAADCgEIAQAAAA==.',Gl='Glindo:BAAALAAECgMIBgAAAA==.',Gn='Gnack:BAAALAAECggICAAAAA==.',Go='Gokuu:BAAALAAECgcIDwAAAA==.Goldenelf:BAAALAADCgcIBwAAAA==.Goldrausch:BAAALAADCggIEAAAAA==.Gollumsche:BAAALAADCgcIEAAAAA==.Gondrabur:BAAALAAECgMIBgAAAA==.Gonsi:BAAALAADCgcIBwAAAA==.Gosip:BAAALAADCgcIEwAAAA==.',Gr='Granokk:BAAALAADCggICAAAAA==.Grimmlie:BAAALAADCgcIBgABLAAECgMIAwABAAAAAA==.Grázzi:BAAALAADCgUIBQAAAA==.',Ha='Hannsemann:BAAALAAECgYICgAAAA==.Hantli:BAAALAAECgYIDgAAAA==.',He='Heidewizka:BAAALAAECgMIAwAAAA==.Hellandfire:BAAALAADCggICAAAAA==.Hellbanger:BAAALAADCggIDwAAAA==.Hellraiser:BAAALAAECggIBQABLAAECggIDAABAAAAAA==.Hephaisto:BAAALAADCggICgAAAA==.Hexelillyfee:BAAALAAECgIIAgAAAA==.',Hi='Higuruma:BAAALAADCgIIAgAAAA==.',Ho='Hoppelbob:BAAALAAECgIIAgAAAA==.',Hy='Hyacinthe:BAAALAADCgQIBwAAAA==.Hygija:BAAALAAECgMIAwAAAA==.Hyorion:BAAALAADCgcIBwAAAA==.',['Hè']='Hèlly:BAAALAAECgYIBgAAAA==.',['Hé']='Hélios:BAAALAAECgEIAQAAAA==.',['Hê']='Hêkate:BAAALAADCggICAAAAA==.',['Hî']='Hîmli:BAAALAADCgcIJwAAAA==.',Ic='Ichigø:BAAALAAECgQIBAAAAA==.',Ir='Irezzfortips:BAAALAADCgMIAwAAAA==.',Is='Ishnuala:BAAALAADCgEIAQABLAAECgYIDAABAAAAAA==.',It='Itsablw:BAAALAADCgIIAgAAAA==.Itsas:BAAALAAECgYIEAAAAA==.',Ja='Jagomo:BAAALAAECggICAAAAA==.Jamato:BAAALAAECgMIAwAAAA==.',Ju='Jupi:BAAALAADCggIFAAAAA==.Juvelian:BAAALAAECggIAQAAAA==.',['Já']='Jácob:BAAALAADCgcIDgAAAA==.',['Jé']='Jéwéls:BAAALAADCggICAAAAA==.',['Jû']='Jûhû:BAAALAADCggICAAAAA==.',Ka='Kahldrogo:BAAALAADCgUIBQAAAA==.Kamaro:BAAALAAECgEIAQABLAAECgYIDQABAAAAAQ==.Kapern:BAAALAAECgMIBQAAAA==.Karasia:BAAALAADCgYIBgAAAA==.',Ke='Kekeygenkai:BAAALAADCggICAAAAA==.',Ki='Kiliria:BAAALAAECgcIEAAAAA==.Kimjongssio:BAAALAADCgUIBAAAAA==.',Ko='Kodulf:BAAALAADCggIEgAAAA==.Kokytos:BAAALAADCgcIBwAAAA==.',Kr='Kritzlfitzl:BAAALAAECgMIBgAAAA==.',Ky='Kyrelia:BAAALAAECgMIBQAAAA==.',['Kí']='Kímberly:BAAALAADCgcIBwAAAA==.',La='Labamm:BAAALAAECggICAAAAA==.Laneus:BAAALAAECgMIAwAAAA==.Laxobèral:BAAALAADCggIFwAAAA==.',Le='Leiiniix:BAAALAADCggIDwAAAA==.Leishmaniose:BAAALAADCggIDwAAAA==.Levi:BAAALAADCgcIDwAAAA==.',Li='Lifdrasil:BAAALAADCggIDwAAAA==.Lilliana:BAAALAAECgYIDAAAAA==.Lilly:BAAALAADCgcIBwAAAA==.',Ll='Llilliee:BAAALAAECgcIDwAAAA==.Lloyd:BAAALAADCgYIBgAAAA==.',Lo='Lornashore:BAAALAAECggICAABLAAECggIDAABAAAAAA==.Lostbert:BAAALAAECgYIBgAAAA==.Lourdes:BAAALAAECgMIBgAAAA==.',Lu='Lumi:BAAALAADCgcIBwAAAA==.',Ly='Lynnsay:BAAALAADCggIGAAAAA==.',['Lá']='Lárthos:BAAALAADCgcIBwAAAA==.',['Lê']='Lêylêy:BAAALAAECgEIAQAAAA==.',['Lí']='Líâra:BAAALAADCgcIBwAAAA==.',['Lî']='Lîlalay:BAAALAADCgUIBQAAAA==.',['Lú']='Lúcý:BAAALAAECgYICQAAAA==.',Ma='Machtnixx:BAAALAADCgYIBgAAAA==.Magroth:BAAALAADCgEIAQAAAA==.Magtheriton:BAAALAADCggIFAAAAA==.Mallory:BAAALAADCgcIBwAAAA==.Marenes:BAAALAAECgYIBgAAAA==.Marina:BAAALAAECgYIDwAAAA==.Maseltov:BAAALAAECgYICwAAAA==.',Me='Meina:BAAALAADCggICwAAAA==.Meisterwilli:BAAALAADCggIFAAAAA==.',Mi='Mileyshirin:BAAALAAECgEIAQAAAA==.Miyaky:BAAALAADCggICAAAAA==.',Mo='Montyr:BAAALAAECgMIAwAAAA==.Moonwalker:BAAALAAECgMIBgAAAA==.Morgonia:BAAALAADCgEIAQAAAA==.Moriá:BAAALAADCgYICQAAAA==.',Mu='Muckel:BAAALAADCggICAAAAA==.Muluga:BAAALAAECgMIAwAAAA==.',My='Myrrine:BAAALAAECgMIAwAAAA==.',['Má']='Mároc:BAAALAADCggIDwAAAA==.',['Mé']='Méldá:BAAALAAECgYIBgAAAA==.',Na='Nafnif:BAAALAAECgIIAwAAAA==.Narmaris:BAAALAADCggICwAAAA==.',Ne='Nemonic:BAAALAAECgMIAwAAAA==.Nemrasil:BAAALAAECgIIAgAAAA==.Nephelia:BAAALAAECgYICgAAAA==.Nepice:BAAALAADCgIIAgAAAA==.',Ni='Nibelus:BAAALAAECgEIAQAAAA==.Nifnif:BAAALAAECgcIDQAAAA==.Nighet:BAAALAADCgcICgAAAA==.Nikkita:BAAALAAECggIDAAAAA==.Nile:BAAALAADCggICAABLAAECggIDAABAAAAAA==.Nimueh:BAAALAAECgEIAQAAAA==.',No='Nogalf:BAAALAADCgMIAwAAAA==.',Ny='Nyssa:BAAALAADCgYIBQAAAA==.',['Nî']='Nîaza:BAAALAAECgMIAwAAAA==.',Og='Ogni:BAAALAAECgcIDwAAAA==.',Ok='Ok:BAAALAAECggIEAAAAA==.',Ol='Ollen:BAAALAADCgQIBAAAAA==.',Or='Orcshaman:BAAALAAECgcICQAAAA==.',Os='Oskar:BAAALAADCgcIBwAAAA==.',Ot='Otternase:BAAALAAECgUIBQAAAA==.',Oz='Ozzy:BAAALAADCggIDgAAAA==.',Pa='Padee:BAAALAAECggICAAAAA==.Painskill:BAAALAADCgcIBwAAAA==.Pandalia:BAAALAAECgEIAQAAAA==.Patze:BAAALAAECgMICAAAAA==.',Pi='Piotess:BAAALAADCggIGAAAAA==.',Pl='Plinko:BAAALAADCgUIBAAAAA==.',Po='Pochette:BAAALAADCgcIBwAAAA==.Pointe:BAAALAADCggIEgAAAA==.Pounamu:BAAALAADCgcIBwAAAA==.',Pr='Priestio:BAAALAADCgcIDgAAAA==.',Py='Pynea:BAAALAAECgYIBwAAAA==.',['Pâ']='Pâhalin:BAAALAADCggIEAABLAAECgMIAwABAAAAAA==.',Qo='Qog:BAAALAADCggICQAAAA==.',Qt='Qtkappa:BAAALAAECgcIEgAAAA==.',Ra='Ragenor:BAAALAAECgMICAAAAA==.Rainny:BAAALAAECgMIAwAAAA==.',Re='Relaila:BAAALAAECgMIBgAAAA==.',Ro='Rockior:BAAALAADCgcICQABLAAECgIIBAABAAAAAA==.',Ru='Rubinaholz:BAAALAAECgEIAQABLAAECgcIDAABAAAAAA==.',['Rö']='Röstipommes:BAAALAADCggICAAAAA==.',Sa='Saltorc:BAAALAAECgMIBgAAAA==.Sandman:BAAALAAECgcIDwAAAA==.Sandorr:BAAALAAECgUIBwAAAA==.Sanifas:BAAALAADCgYIBgAAAA==.Sarya:BAAALAAECgYIDQAAAA==.Satiya:BAAALAAECgMIBQAAAA==.Satsujinpala:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.',Sc='Schenkwart:BAAALAAECgYICQAAAA==.Schämray:BAAALAAECgMIAwAAAA==.',Se='Seasmoke:BAAALAAECgYICQAAAA==.Seleén:BAAALAAECgYICAAAAA==.Sendora:BAAALAADCggIDgAAAA==.Septemí:BAAALAAECggICAAAAA==.Sethrali:BAAALAADCgIIAgAAAA==.',Sh='Shiroon:BAAALAADCggICAAAAA==.Shivalinga:BAAALAAECgEIAQAAAA==.',Si='Sinko:BAAALAADCgcIBwAAAA==.',Sk='Skibidirizz:BAAALAAECgUIAwAAAA==.Skreeny:BAAALAADCggICwAAAA==.Skye:BAAALAAECgUIBgAAAA==.',Sl='Slayn:BAAALAADCggIFgAAAA==.',Sm='Smirre:BAAALAADCggIDgAAAA==.',So='Soilwork:BAAALAADCggICAABLAAECggIDAABAAAAAA==.Soraja:BAAALAAECgMIBgAAAA==.Sorcixa:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Soulbladez:BAAALAADCgcICAAAAA==.South:BAAALAAECgMIBQAAAA==.',St='Steinhammer:BAAALAAECgMIBQAAAA==.',Su='Suleiká:BAAALAAECgEIAQAAAA==.',Sv='Svanja:BAAALAAECgEIAQAAAA==.',Sy='Syrénne:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.',Sz='Szull:BAAALAAECgYIBwAAAA==.',['Sá']='Sáhirá:BAAALAADCggIFgAAAA==.Sáphira:BAAALAADCggIDwAAAA==.',['Só']='Sómbra:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',['Sô']='Sôphy:BAAALAADCggIFgAAAA==.',Ta='Tajaa:BAAALAAECggICAAAAA==.Tanaîel:BAAALAAECgcIDwAAAA==.Tarkos:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Tayrinerrá:BAAALAADCgcIBwAAAA==.',Te='Technomickel:BAAALAADCgEIAQAAAA==.Teschewe:BAAALAADCggIEwAAAA==.Tessup:BAAALAAECgcIDwAAAA==.',Th='Thamína:BAAALAAECgMIAwAAAA==.Thibbeldorf:BAAALAADCggIEgAAAA==.Thilde:BAAALAADCgcIDgAAAA==.Thraxon:BAAALAADCgYIDQAAAA==.',Ti='Tilamera:BAAALAADCgcIBwAAAA==.Tison:BAAALAAECgMIBgAAAA==.',To='Toji:BAAALAADCgMIAwAAAA==.',Tr='Traillies:BAAALAADCgEIAQAAAA==.Trizzl:BAAALAAECgYICQAAAA==.Troublemaker:BAAALAADCggICwAAAA==.',Tu='Tullamoor:BAAALAADCgIIAgAAAA==.Tuvilock:BAAALAADCggIDgABLAAECgYIDAABAAAAAA==.Tuvimage:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Tuvipriest:BAAALAAECgYIDAAAAA==.Tuviwar:BAAALAADCggIEAABLAAECgYIDAABAAAAAA==.',Tw='Twik:BAAALAAECgIIAgAAAA==.',Ty='Tyræl:BAAALAADCggIEgAAAA==.',['Té']='Ténhjo:BAAALAADCgQIBAAAAA==.',['Tí']='Tíger:BAAALAADCgUIBgAAAA==.',Un='Uniusr:BAABLAAECoEWAAMCAAcIihYNBwDAAQACAAYIPBoNBwDAAQADAAYIlgUACAA7AQABLAADCggICAABAAAAAA==.',Va='Vaeragosa:BAAALAADCggIDwAAAA==.Vaylha:BAAALAADCggICAAAAA==.Vaélin:BAAALAAECgMIBgAAAA==.',Ve='Veiðikona:BAAALAADCggICAAAAA==.',Vo='Vonotah:BAAALAAECgMIAwAAAA==.',Vu='Vulnaria:BAAALAADCgUICAAAAA==.',Vy='Vyse:BAAALAAECgEIAgAAAA==.',We='Wesson:BAAALAAECgIIAgAAAA==.',Wh='Whitelady:BAAALAADCggICAAAAA==.',Wo='Woofi:BAAALAAECgcICQAAAA==.',Xa='Xavalon:BAAALAADCggIGwAAAA==.',Xe='Xearo:BAAALAAECgMIAwAAAA==.Xentô:BAAALAADCgUIAwAAAA==.Xeras:BAAALAAECgEIAQAAAQ==.Xerxi:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.Xerxidud:BAAALAAECgYIBgAAAA==.Xerximist:BAAALAADCgMIAwABLAAECgYIBgABAAAAAA==.Xerxisham:BAAALAAECgMIBAABLAAECgYIBgABAAAAAA==.Xerxí:BAAALAAECgEIAQABLAAECgYIBgABAAAAAA==.',Xo='Xokuk:BAAALAADCgQIBAAAAA==.',Ya='Yangci:BAAALAADCggICAAAAA==.',Yb='Ybera:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',Yl='Ylara:BAAALAADCgQIBAAAAA==.',Yu='Yulissa:BAAALAADCgQIBgAAAA==.Yumz:BAAALAAECgEIAQAAAA==.',['Yê']='Yês:BAAALAADCggICAAAAA==.',Za='Zaphod:BAAALAADCggIEAAAAA==.',Zb='Zbo:BAAALAAECgMIAwAAAA==.',Ze='Zelador:BAAALAAECgMIAwAAAA==.Zeldas:BAAALAADCggIDQAAAA==.Zephyr:BAAALAADCggIFAAAAA==.Zephyrios:BAAALAAECgMIAwAAAA==.Zesty:BAAALAAECgYICwAAAA==.',Zi='Zitrone:BAAALAADCggICgAAAA==.',Zo='Zoulou:BAAALAADCgcIBwAAAA==.Zozoria:BAAALAAECgIIAgAAAA==.',Zy='Zyldjian:BAAALAADCggIFAAAAA==.Zylium:BAAALAAECgcIBwAAAA==.',['Zý']='Zýal:BAAALAAECgcIEAAAAA==.',['Äl']='Älain:BAAALAADCgIIAgAAAA==.',['Äo']='Äonen:BAAALAADCggIDgAAAA==.',['Îô']='Îônîâ:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end