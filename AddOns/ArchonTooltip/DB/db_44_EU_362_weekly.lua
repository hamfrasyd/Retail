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
 local lookup = {'Rogue-Subtlety','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Priest-Shadow','Priest-Holy','Shaman-Restoration','Monk-Brewmaster','DemonHunter-Havoc','Paladin-Retribution','Warrior-Protection','Paladin-Holy','Warlock-Affliction','Warlock-Destruction',}; local provider = {region='EU',realm='ConseildesOmbres',name='EU',type='weekly',zone=44,date='2025-08-30',data={Aa='Aalba:BAAALAAECgEIAQAAAA==.',Ab='Abd:BAAALAAECgcIEgAAAA==.Abdaroth:BAACLAAFFIEFAAIBAAMI8hefAAAWAQABAAMI8hefAAAWAQAsAAQKgRcAAgEACAjSJE4AAGMDAAEACAjSJE4AAGMDAAAA.Abdoul:BAAALAADCgYIBgAAAA==.',Ad='Adiard:BAAALAAECgQIBwAAAA==.',Ae='Aerïth:BAAALAAECgMIBwAAAA==.Aeternia:BAAALAAECgIIAgAAAA==.',Al='Alistar:BAAALAADCgcIDQABLAAECgQIBQACAAAAAA==.Almiraj:BAAALAADCgEIAQAAAA==.Alucar:BAAALAAECgQIBwAAAA==.',Am='Amnesià:BAAALAAECgQIBgAAAA==.',An='Anarkia:BAAALAADCgcIDgAAAA==.Anoeth:BAAALAADCgQIBAABLAAECgEIAgACAAAAAA==.Anosapin:BAAALAAECgQIBwAAAA==.',Ao='Aoqin:BAAALAAECgUICQAAAA==.',Ap='Apnwx:BAAALAADCggIEwAAAA==.',Ar='Aralÿs:BAAALAAECgYICQAAAA==.Arnek:BAAALAAECgMIAQAAAA==.Artirro:BAAALAADCgcIBwAAAA==.Arüka:BAAALAADCgIIAgAAAA==.',As='Ascaroth:BAAALAADCgMIBAAAAA==.Ashäa:BAAALAAECgcIDQAAAA==.Aspectdukiki:BAAALAAECgMIAwAAAA==.Aspergian:BAAALAAECgYICwAAAA==.Aspy:BAAALAAECgcIDwAAAA==.Astarius:BAAALAADCgcICgAAAA==.Astranar:BAAALAADCgcIBwAAAA==.',At='Atagloire:BAAALAADCggICwAAAA==.Athäe:BAAALAAECgYIDgAAAA==.',Au='Authority:BAAALAAECgQIBwAAAA==.',Av='Average:BAAALAADCgcIBwAAAA==.',Aw='Awhkì:BAAALAADCgQICAABLAAECgYIEgACAAAAAQ==.',Ay='Aygon:BAAALAADCggICwAAAA==.',Az='Azaran:BAAALAAECgQICAAAAA==.Azaërus:BAAALAAECgcIEAAAAA==.Azhure:BAAALAAECgUIBwAAAA==.',['Aé']='Aélys:BAAALAAECgMIBQAAAA==.',Ba='Baguetta:BAAALAAECgUICwAAAA==.Balycouli:BAAALAADCggICAAAAA==.Barador:BAAALAADCggIEQAAAA==.',Be='Behemaute:BAAALAADCgUIBQAAAA==.Belém:BAAALAADCgUIBQAAAA==.',Bi='Bigmoine:BAAALAADCgcIBwAAAA==.Bignoobars:BAAALAADCgEIAQAAAA==.Bigwyrm:BAAALAADCgUIBQAAAA==.Bisoûnours:BAAALAADCgcIAgAAAA==.',Bo='Bobketchup:BAAALAAECgYIDgAAAA==.',Br='Brotheur:BAAALAADCgcIDgAAAA==.',['Bä']='Bärlok:BAAALAADCgcIBwAAAA==.',['Bè']='Bèást:BAABLAAECoEbAAMDAAgIKCCJAQC3AgADAAcIfSGJAQC3AgAEAAcIuRb3FgAWAgAAAA==.',Ca='Camyne:BAAALAADCggICAAAAA==.Candra:BAAALAAECgcIEwAAAA==.Carmila:BAAALAAECgMIBAAAAA==.Carnage:BAAALAAECgMIAwAAAA==.',Ce='Ceriize:BAAALAADCggICAAAAA==.',Ch='Chamanheal:BAAALAADCgQIAQAAAA==.Chibroly:BAAALAAECgMIBgAAAA==.Chienpo:BAAALAADCggICAABLAAECgcIEwACAAAAAA==.Châcal:BAAALAADCggIDgAAAA==.Châtiment:BAAALAADCgcIBwAAAA==.',Co='Cordelys:BAAALAAECgIIAgAAAA==.',Cr='Creamy:BAAALAADCgIIAgAAAA==.',['Cé']='Cézanne:BAAALAAECgYIDAAAAA==.',Da='Daléora:BAAALAAECgYIDwAAAA==.Damuuth:BAAALAAECgMIBAAAAA==.',De='Deathdemon:BAAALAAECgcIDwAAAA==.Deepshii:BAAALAAECgYIEAAAAA==.Deloise:BAAALAAECgcIEAAAAA==.Delyna:BAAALAADCgcIBwABLAAECgUICQACAAAAAA==.Desdez:BAAALAADCgEIAQABLAAECgYICwACAAAAAA==.Devak:BAAALAAECgYIBgAAAA==.Devilskîng:BAAALAADCgcIDAAAAA==.',Di='Diplopie:BAAALAAECgcICwAAAA==.',Dk='Dkthlon:BAAALAAECgMIBAAAAA==.',Dr='Dracqween:BAAALAAECgIIAgAAAA==.Dragorkk:BAAALAAECgYIDAAAAA==.Drathen:BAAALAAECgIIAgAAAA==.Droogo:BAAALAAECgIIAwAAAA==.Droom:BAAALAADCgYIBgAAAA==.Drpolaton:BAAALAAECgUIBgABLAAFFAQICQAFAKoUAA==.Druidee:BAAALAADCgcIDAAAAA==.',Du='Dumbe:BAAALAAECgMIBwAAAA==.',Ea='Eauskøur:BAAALAAECgEIAQABLAAECgcIDgACAAAAAA==.',Eg='Egeanine:BAAALAAECgIIAgAAAA==.',Ek='Ekzayxd:BAAALAAECggIDgAAAA==.',El='Elendél:BAAALAADCgcIEAAAAA==.Elhatno:BAAALAAECgEIAgAAAA==.Elnïa:BAAALAAECgcICwAAAA==.Elsariel:BAAALAADCggIEwAAAA==.Elsheitan:BAAALAADCggIDgAAAA==.Eltak:BAAALAADCgEIAQAAAA==.Elzbieta:BAAALAAECgQICAAAAA==.',Em='Emeuha:BAAALAAECgMIBgAAAA==.Emmy:BAAALAAECgIIAgAAAA==.',En='Eneïde:BAAALAAECgQICAAAAA==.',Eo='Eolias:BAAALAAECgQIBwAAAA==.',Ev='Evengel:BAAALAADCgEIAQAAAA==.',Fi='Fildentaire:BAAALAAECgMIAwAAAA==.Filzareis:BAAALAADCggIDwAAAA==.',Fo='Foncedslemur:BAAALAAECgMIBQAAAA==.',Fr='Frastrixs:BAAALAADCgcIBwAAAA==.',Ga='Gadwina:BAAALAADCggICAAAAA==.Gaianne:BAAALAAECgQICAAAAA==.Galateia:BAAALAAECgYICwAAAA==.Garbotank:BAAALAAECgQIBQAAAA==.',Gn='Gnominay:BAAALAADCggICgABLAADCggIEwACAAAAAA==.',Gr='Grogmar:BAAALAAECgQICAAAAA==.Groms:BAAALAADCgcICAAAAA==.Grossemite:BAAALAAECgQIBQAAAA==.Gríef:BAAALAADCggIBQAAAA==.Grîbouille:BAAALAAECgcICQAAAA==.Grøldan:BAAALAADCgcIBwAAAA==.',Gw='Gwedaen:BAAALAADCgIIAwAAAA==.Gwoklibre:BAAALAAECgIIAgAAAA==.',Ha='Haersvelg:BAAALAADCggICgAAAA==.Happymheal:BAAALAADCggIDgAAAA==.Harricovert:BAAALAADCgcIDQAAAA==.Hautdesaine:BAAALAAECgUIBgAAAA==.Haxas:BAAALAAECgIIAgAAAA==.',He='Helldarion:BAAALAAECgEIAQAAAA==.Hexi:BAAALAAECgQIBAAAAA==.',Ho='Holyra:BAAALAADCgUIBgAAAA==.Hortense:BAAALAADCgEIAQAAAA==.',Hy='Hyuna:BAAALAAECgEIAQABLAAECgMIBQACAAAAAA==.',Ib='Ibexphénix:BAABLAAFFIEJAAIFAAQIqhQ8AQBqAQAFAAQIqhQ8AQBqAQAAAA==.',Ic='Icandre:BAAALAADCggIEwAAAA==.',In='Inatîa:BAAALAADCgQIBAAAAA==.Indika:BAAALAADCggICAAAAA==.',Is='Ishä:BAAALAADCggICAAAAA==.',Ja='Javine:BAAALAADCgcIBwABLAAECgQIBwACAAAAAA==.',Ji='Jinizz:BAAALAAECgcIEgAAAA==.',Jo='Jolyana:BAAALAADCgQIBAAAAA==.',Ju='Justunetaf:BAAALAAECgIIAgAAAA==.Juuki:BAAALAAECgIIAgAAAA==.',['Jï']='Jïzo:BAAALAAECgMIAQAAAA==.',['Jü']='Jürgen:BAAALAAECgQIBAAAAA==.',Ka='Kahd:BAAALAAECgQIBwAAAA==.Kaldiria:BAABLAAFFIEJAAMGAAQIuyDvAACdAQAGAAQIuyDvAACdAQAHAAEI2QMsDgBOAAAAAA==.Kameokami:BAABLAAECoEYAAIIAAgIgh6NBgCrAgAIAAgIgh6NBgCrAgAAAA==.Kamoulox:BAAALAAECgQIBgAAAA==.Karädras:BAAALAAECgIIAgAAAA==.Katerina:BAAALAAECgMIBAAAAA==.Kaôô:BAAALAADCgMIAwAAAA==.',Ke='Kern:BAAALAAECgUIBQAAAA==.Kerodruid:BAAALAADCggIDgABLAAECgQIBwACAAAAAA==.',Kh='Khazgrol:BAAALAAECgIIAgAAAA==.Khiera:BAAALAAECgMIBgAAAA==.Khrak:BAAALAAECgcIDQAAAA==.Khéliana:BAAALAADCggIFQAAAA==.',Ki='Kin:BAAALAADCgcIBwAAAA==.Kissyfrôtte:BAAALAADCgUIBQAAAA==.',Kl='Klifft:BAAALAAECgUICwAAAA==.Klyesh:BAAALAADCgcICgAAAA==.',Kn='Knozibul:BAAALAAECgcIDwAAAA==.',Ko='Konveex:BAAALAAECgMIBAAAAA==.Korasek:BAAALAAECgMIBQAAAA==.',Kr='Kreaze:BAAALAAFFAIIAgAAAA==.Krilldur:BAAALAADCggIEAAAAA==.',Ku='Kura:BAAALAAECgMIBAAAAA==.',['Kä']='Kälipsow:BAAALAAECgEIAQAAAA==.',['Kè']='Kèrö:BAAALAADCggIDwABLAAECgQIBwACAAAAAA==.Kèrø:BAAALAAECgQIBwAAAA==.',['Kî']='Kîra:BAAALAAECgEIAQABLAAECgUICQACAAAAAA==.',La='Lapinôu:BAAALAADCgcIBwAAAA==.Lauviah:BAAALAAECgIIAgABLAAECgcICwACAAAAAA==.',Le='Ledragon:BAAALAADCggIGAABLAAECgYICgACAAAAAA==.Leexa:BAAALAADCgcIBwAAAA==.',Li='Libowsky:BAAALAAECgIIBAAAAA==.Ligesol:BAAALAADCgcICgAAAA==.',Lo='Loushinglar:BAAALAADCgcICgAAAA==.Loûrs:BAAALAADCgQIBAAAAA==.',Lu='Lumarmacil:BAAALAAECgIIAgAAAA==.',Ly='Lysandre:BAAALAADCgYIBgAAAA==.',['Lö']='Löurs:BAAALAAECgcICgAAAA==.',Ma='Madamedark:BAAALAAECgYIBgABLAAECggIFQAJAE0eAA==.Madsu:BAAALAAECgYICAAAAA==.Makaveli:BAAALAADCggICAAAAA==.Maldraxx:BAAALAAECgEIAQAAAA==.Mardrim:BAAALAAECgcIEAAAAA==.Massax:BAAALAAECgMIAwAAAA==.Masstodont:BAAALAAECgYIBAAAAA==.Mataji:BAAALAADCgcIBwAAAA==.Mathematix:BAABLAAECoEVAAIKAAgIcyKOBgAdAwAKAAgIcyKOBgAdAwAAAA==.Matusin:BAAALAADCgUIBQABLAAECgEIAgACAAAAAA==.Maïsse:BAAALAADCgcIEgAAAA==.',Me='Melkorlock:BAAALAAECgMIAwAAAA==.Meriah:BAAALAAECgIIAgABLAAECgcIDQACAAAAAA==.',Mi='Miami:BAAALAADCgYICgABLAAECgYIEAACAAAAAA==.Mifali:BAAALAAECgUICwAAAA==.',Mk='Mkvennair:BAAALAADCggIEAAAAA==.',Mo='Momygoodmage:BAAALAAECgEIAQAAAA==.Montalieu:BAAALAADCgQIBAAAAA==.Mortice:BAAALAAECgcICwAAAA==.Mortlalune:BAAALAAECgYICAAAAA==.',My='Myleäs:BAAALAAECgIIAwAAAA==.',['Mé']='Mériah:BAAALAAECgcIDQAAAA==.',Na='Naatah:BAAALAADCgcICAAAAA==.Naili:BAAALAADCgcICAAAAA==.Nanøm:BAAALAAECgQIBQAAAA==.Narisson:BAAALAAECgQIBwAAAA==.Narotia:BAAALAAECgEIAQAAAA==.Nasteria:BAAALAAECgMIBgAAAA==.Nazghull:BAAALAAECgIIAgAAAA==.Nazorkros:BAAALAADCgcIDwAAAA==.',Ne='Nephty:BAAALAAECgEIAQAAAA==.Nessadiou:BAAALAAECgMIAgAAAA==.Nesta:BAAALAAECgcIEwAAAA==.Netsune:BAAALAAECgIICQAAAA==.',Ni='Nicklauss:BAAALAAECgYICAAAAA==.Nightmahr:BAAALAAECgIIAgAAAA==.Nixma:BAAALAADCgcIBAAAAA==.',No='Noishpa:BAAALAADCgcICgABLAAECgcIDQACAAAAAA==.Noldor:BAAALAADCgIIAgAAAA==.',Nu='Nuÿ:BAAALAADCggICAAAAA==.',Ny='Nyarae:BAAALAAECgYIDAAAAA==.Nyù:BAAALAAECgMIAwAAAA==.',['Nø']='Nøøkie:BAAALAADCgMIAwAAAA==.',Or='Orena:BAAALAADCggIDwAAAA==.Orfelia:BAAALAAECgMIBgAAAA==.Orphay:BAAALAAECgYIEgAAAQ==.',Os='Osti:BAAALAADCgMIBAAAAA==.Oswÿn:BAAALAADCggIDwAAAA==.',Ou='Oupsie:BAAALAADCgUIBQABLAAECgYIEAACAAAAAA==.',Oz='Ozwyn:BAAALAADCgYIBgAAAA==.',Pa='Palagaule:BAAALAADCggIFQAAAA==.Palaslayer:BAAALAADCggICAAAAA==.Palatinaë:BAAALAAECgQICAAAAA==.Parbuffle:BAAALAAECgMIBQAAAA==.',Pe='Pegidouze:BAAALAAECgcIDwAAAA==.Perlette:BAAALAADCgEIAQAAAA==.Petoplow:BAAALAAECgUICgABLAAECgYIEAACAAAAAA==.',Pi='Pitchounoute:BAAALAADCgUIBQAAAA==.',Po='Pooöôh:BAAALAADCgQIBAAAAA==.',Pr='Protmalone:BAACLAAFFIEKAAILAAUILBouAADzAQALAAUILBouAADzAQAsAAQKgRgAAgsACAhPI6MFACwDAAsACAhPI6MFACwDAAAA.Prøxima:BAAALAAECgMIBAAAAA==.',Ra='Raknathõr:BAAALAAECgQIBQAAAA==.Raksharan:BAAALAAECgYIBgAAAA==.Rastofire:BAAALAADCgUIBQAAAA==.Razzmatazz:BAAALAAECgMIBgAAAA==.',Rc='Rcdrink:BAAALAADCgYIBgAAAA==.',Re='Redlïght:BAAALAADCggICAAAAA==.Rei:BAAALAAECgEIAQAAAA==.Replicant:BAAALAAECgEIAQAAAA==.',Ri='Rinzï:BAAALAADCgcIDwAAAA==.',Ro='Roubidou:BAAALAADCggICAAAAA==.',Rq='Rqch:BAABLAAECoEUAAMMAAgI5RW0EACUAQAEAAcIvhGAGwDpAQAMAAcIvRW0EACUAQAAAA==.',Ru='Russell:BAAALAADCgcIBwAAAA==.',Ry='Ryuk:BAAALAADCgUIBgAAAA==.',['Rö']='Rödyy:BAAALAADCggICAABLAAECgMIBAACAAAAAA==.',['Rø']='Røxäne:BAAALAADCggIEwAAAA==.',Sa='Safian:BAAALAAECgIIAwAAAA==.Sajï:BAAALAADCgUICgAAAA==.Satoru:BAAALAAECgYICAAAAA==.Sayphix:BAAALAAECgQIBQAAAA==.',Sc='Scary:BAAALAADCgUIBQAAAA==.Scores:BAAALAAFFAIIBAAAAQ==.',Se='Seido:BAAALAADCgYICwAAAA==.Seldara:BAABLAAECoEVAAIHAAYIih+gIwCVAQAHAAYIih+gIwCVAQABLAAFFAMIBQANAOEfAA==.Serpillère:BAAALAAECgcIDgAAAA==.',Sh='Shadowphra:BAAALAAECgYIBgABLAAECgYIEAACAAAAAA==.Shaerazad:BAAALAADCggICwAAAA==.Shakyz:BAAALAADCgcIDgAAAA==.Shamless:BAAALAAECgYICgAAAA==.Sheratan:BAAALAADCgcICgAAAA==.Shorey:BAAALAADCgcICgAAAA==.Shushen:BAAALAAECgYIBgAAAA==.Shyn:BAAALAAECgUICgAAAA==.Shànnøn:BAAALAADCgcIDQAAAA==.Shämo:BAAALAAECgUIBgAAAA==.',Si='Siltheas:BAAALAADCgMIAwAAAA==.',Sm='Smith:BAAALAADCggICAAAAA==.',So='Sof:BAAALAADCgIIAwAAAA==.',St='Stainless:BAAALAADCgIIAgAAAA==.Stalkyz:BAAALAAECgQICAAAAA==.Starloose:BAAALAAECgMIBgABLAAECgcICwACAAAAAA==.Staticx:BAAALAAECgcIDwAAAA==.Stinkiwinki:BAAALAADCgIIAQAAAA==.',Su='Sulenya:BAAALAADCgMIAwAAAA==.Sunfire:BAAALAAECgYIDQABLAAECgcIEwACAAAAAA==.Sunkyuu:BAAALAAECgcIEwAAAA==.',Sy='Sydarta:BAAALAADCgcICwAAAA==.Syleams:BAAALAADCgQIBAAAAA==.Sylvannanas:BAAALAADCgYIBgABLAAECgcICwACAAAAAA==.Syniel:BAAALAAECgcIDwAAAA==.Synrael:BAAALAADCgcIEAAAAA==.Synécham:BAAALAAECgMIAwAAAA==.',['Sé']='Sétèsh:BAAALAAECgMIBAAAAA==.',['Sï']='Sïnypscø:BAAALAAFFAIIAgAAAA==.',['Sô']='Sôlstice:BAAALAADCgYICgAAAA==.',['Sù']='Sùnzen:BAAALAADCgYICAABLAAECgcIEwACAAAAAA==.',Ta='Tai:BAAALAAECgcIDwAAAA==.Tawen:BAABLAAECoEVAAMOAAgIaRa/BgD4AQAPAAgIZBNfFgAXAgAOAAcI7xC/BgD4AQAAAA==.',Te='Tehlarissa:BAAALAAECggICAAAAA==.Terr:BAAALAAECgEIAQAAAA==.',Th='Thebam:BAAALAAECgMIAwAAAA==.Thera:BAAALAADCggICAAAAA==.Thunderbolts:BAAALAAECgEIAQAAAA==.',Ti='Tidus:BAAALAADCggICQAAAA==.Tiladia:BAAALAADCggICAABLAAECgMIBgACAAAAAA==.Titoxy:BAAALAADCgcICQAAAA==.',To='Torgrom:BAAALAADCgcIBwAAAA==.Totemrun:BAAALAAECgUIBQAAAA==.',Ts='Tsunade:BAAALAADCgYIBgABLAAECgEIAQACAAAAAA==.',Ty='Tyrkusia:BAAALAADCgcICgAAAA==.',Tz='Tzanta:BAAALAADCgMIAwAAAA==.',['Tä']='Täaz:BAAALAAECgIIAgAAAA==.',Ut='Uthar:BAAALAADCgMIAwAAAA==.',Uz='Uzo:BAAALAAECgYIEAAAAA==.',Va='Valmir:BAAALAAECgMIAwAAAA==.Vanivel:BAAALAAECgIIAwAAAA==.',Ve='Velarian:BAAALAAECgYIBgAAAA==.Venusa:BAAALAAECgYIBgAAAA==.Vereva:BAACLAAFFIEFAAINAAMI4R88AQAxAQANAAMI4R88AQAxAQAsAAQKgRgAAg0ACAgoI9IBAPcCAA0ACAgoI9IBAPcCAAAA.',Vi='Viego:BAAALAAECgIIAwAAAA==.Visorak:BAAALAADCggICAAAAA==.',Vl='Vladï:BAAALAAECgMIAwAAAA==.',['Vô']='Vôletavie:BAAALAADCgcICgAAAA==.',Wa='Walrot:BAAALAADCggICAAAAA==.',Wh='Whatapal:BAAALAAECgYICwAAAA==.Whitewolf:BAAALAAECgYIBgAAAA==.Whity:BAAALAAECgMIBgAAAA==.',Wi='Wiish:BAAALAAECgYICQAAAA==.Windstormind:BAAALAAECgYICQABLAAECggIGwADACggAA==.Wingosho:BAAALAAECgQIBwAAAA==.',['Wÿ']='Wÿzën:BAAALAAECgQICAAAAA==.',Ya='Yaminiga:BAAALAADCggICAAAAA==.',Ye='Yeezys:BAAALAAECgEIAQAAAA==.',Yi='Yikiolth:BAAALAADCggIDgAAAA==.Yikthu:BAAALAADCgYIBgAAAA==.',Yr='Yrélia:BAAALAADCggIEwAAAA==.',Yu='Yukïe:BAAALAADCgEIAQAAAA==.Yunormi:BAAALAAECgYIDwAAAA==.',Za='Zantekutsia:BAAALAAECgMIBgAAAA==.Zargoths:BAAALAADCgcIBgAAAA==.',Ze='Zertare:BAAALAADCgEIAQAAAA==.Zevil:BAAALAAECgYICwAAAA==.Zevilus:BAAALAADCgcICwABLAAECgYICwACAAAAAA==.',Zh='Zhedd:BAAALAAECgcIEgAAAA==.',Zk='Zkarbon:BAAALAADCgIIAgAAAA==.',Zn='Zni:BAAALAAECgYIDgAAAA==.',Zo='Zochalbak:BAAALAAECgIIBQAAAA==.Zorodémo:BAAALAAECgQIBwAAAA==.',['Âr']='Ârtarus:BAAALAAECggIAQAAAA==.',['Ât']='Âthenna:BAAALAADCgYICwAAAA==.',['Är']='Ärwwen:BAAALAAECgMIAwAAAA==.',['Éd']='Édoras:BAAALAAECgMIAwAAAA==.',['Él']='Éliriane:BAAALAAECgMIBAAAAA==.',['Ða']='Ðarkmønk:BAABLAAECoEVAAIJAAgITR6JAwC3AgAJAAgITR6JAwC3AgAAAA==.',['Ðr']='Ðraemir:BAAALAAECgMIBAAAAA==.',['Öb']='Öbaâl:BAAALAADCgcICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end