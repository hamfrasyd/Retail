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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','DeathKnight-Frost','Hunter-BeastMastery','Monk-Mistweaver','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction',}; local provider = {region='EU',realm='Krasus',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abyna:BAAALAADCgEIAQAAAA==.',Ad='Adael:BAAALAAECgEIAQAAAA==.Adaonna:BAAALAAECgYIDAAAAA==.',Ae='Aeglos:BAAALAAECgcIDwAAAA==.Aenonis:BAAALAADCggICAAAAA==.Aeriis:BAAALAADCgYIBgAAAA==.Aerris:BAAALAADCggICAAAAA==.',Ag='Agoryax:BAAALAADCgYIBgAAAA==.',Ai='Aidermoi:BAAALAAECgcIDwAAAA==.',Ak='Akina:BAAALAAECgIIAwAAAA==.',Al='Alliçia:BAAALAADCgYIBgAAAA==.Alérion:BAAALAADCggICAAAAA==.',Am='Amogus:BAAALAAECgcIDwAAAA==.',Ap='Apik:BAAALAADCggIEQAAAA==.',Ar='Arakné:BAAALAAECgYICAAAAA==.Argès:BAAALAADCgIIAgAAAA==.Ariel:BAAALAAECgIIAwABLAAECgQIBAABAAAAAA==.Arkane:BAAALAADCgYICAAAAA==.Arwen:BAAALAAECgMIAwAAAA==.',As='Ashketchum:BAAALAADCggIDQAAAA==.Askarit:BAAALAADCgcIBwAAAA==.Asmodéa:BAAALAADCgcICgAAAA==.Astrelia:BAAALAAECgMIBgAAAA==.Astärøth:BAAALAAECgYICAAAAA==.',['Aê']='Aêdex:BAAALAADCgcIBwAAAA==.',Ba='Balmora:BAAALAAECgMIAwAAAA==.Banshée:BAAALAADCgcIBwAAAA==.',Bo='Boblerenard:BAAALAAECgMIBQAAAA==.Bordelic:BAAALAAECgIIAwAAAA==.',Bu='Buumbastik:BAAALAAECgEIAQAAAA==.',['Bä']='Bähälmung:BAAALAAECgIIAwAAAA==.',Ca='Capïah:BAAALAAECgMIBAAAAA==.',Ce='Centaur:BAAALAADCggICAAAAA==.Ceriwena:BAAALAADCgMIAwAAAA==.Cesandraa:BAAALAADCggIAwAAAA==.',Ch='Chagraal:BAAALAADCgcICQAAAA==.Chamanoxx:BAABLAAECoEWAAICAAgIOyFcBADgAgACAAgIOyFcBADgAgAAAA==.Chamys:BAAALAAECgEIAQAAAA==.Chiana:BAAALAAECgUICAAAAA==.Chyro:BAAALAADCggIDwAAAA==.Chå:BAAALAAECgIIAgAAAA==.',Co='Coloboss:BAAALAADCggIBwAAAA==.',Cq='Cqs:BAAALAAECgQIBAAAAA==.',Cy='Cydriel:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.',Da='Darkdryms:BAAALAADCggICAAAAA==.Das:BAAALAAECgYICgAAAA==.',De='Deathofmen:BAABLAAECoEUAAIDAAgI7x4NCwDbAgADAAgI7x4NCwDbAgAAAA==.Defny:BAAALAAECgYIDAAAAA==.Demox:BAAALAADCgcIBwAAAA==.Deuteros:BAAALAAFFAIIAgAAAA==.Devildrak:BAAALAADCgcIFAAAAA==.',Do='Docdrood:BAAALAADCggICAAAAA==.',Dr='Dragounet:BAAALAAECgYIBgAAAA==.Dranae:BAAALAAECgMIBAAAAA==.Drucillâ:BAAALAAECgUIBgAAAA==.Dräh:BAAALAAECgMIAwAAAA==.Drömédya:BAAALAAECgEIAQAAAA==.Drüzilla:BAAALAAECgUICAAAAA==.',['Dè']='Dèmonesstia:BAAALAADCgcIBwABLAAECgIIAgABAAAAAA==.',Ee='Eelvegan:BAAALAAECgEIAQAAAA==.',Ek='Ekyria:BAAALAADCgMIAwAAAA==.',El='Elfìà:BAAALAAECgEIAQAAAA==.',Em='Emmarie:BAAALAAECgEIAgAAAA==.Emule:BAAALAAECgYICgAAAA==.',Er='Erilea:BAAALAADCgYIBgABLAADCggIDgABAAAAAA==.Eroaht:BAAALAADCgcICwABLAAECgcIDwABAAAAAA==.Erop:BAAALAAECgYIBwAAAA==.Erwann:BAAALAADCggICwAAAA==.Erydän:BAAALAADCgEIAQAAAA==.',Eu='Euphoria:BAAALAAECgUIBgAAAA==.',Ev='Evokina:BAAALAAECgYIEQABLAAECgIIAwABAAAAAA==.',Ew='Ewïlän:BAAALAADCgUIBQAAAA==.',Ex='Expløsion:BAAALAADCgcICAAAAA==.',Fa='Falvineus:BAAALAAECgMIBgAAAA==.',Fe='Feelïng:BAAALAAECgMIAwAAAA==.Feelïngs:BAAALAAECgIIAgAAAA==.Ferendall:BAAALAADCgcIDQAAAA==.',Fl='Flamie:BAAALAAECgMIBAAAAA==.',Fr='Frainen:BAAALAADCgYIBgAAAA==.Fredazura:BAAALAAECgEIAQAAAA==.',Fu='Fufuman:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.',Ga='Galadrieil:BAAALAAECgEIAQAAAA==.Gallizzenae:BAAALAADCgYIBgAAAA==.Gazdrek:BAAALAAECgYIDAAAAA==.',Ge='Genpal:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.Genryu:BAAALAAECgQIBgAAAA==.',Go='Gokerz:BAAALAADCggICQAAAA==.Gormash:BAAALAAECgMIAwAAAA==.Gouda:BAAALAAECgMIAwAAAA==.',Gr='Grortidimmir:BAAALAADCgYIBgABLAAECgMIBQABAAAAAA==.Growny:BAAALAADCggIDgAAAA==.',Ha='Hanakupichan:BAAALAAECgYIDgAAAA==.Harta:BAAALAAECgYIDAAAAA==.',He='Helow:BAAALAAECgYIDgAAAA==.',Ho='Holygraille:BAAALAAECgMIBQAAAA==.Homage:BAAALAAECgQIBQAAAA==.Homonxa:BAAALAADCggICQAAAA==.Horchac:BAAALAAECgcIDgAAAA==.',Hu='Huhanaa:BAAALAAECgcIDwAAAA==.',Hy='Hyørinmarù:BAAALAAECgYIDgAAAA==.',['Hâ']='Hâyä:BAAALAAECgMIBAAAAA==.',['Hä']='Häyhä:BAAALAAECgcIDAAAAA==.',['Hæ']='Hæla:BAAALAAECgUIBgAAAA==.',['Hè']='Hècate:BAAALAADCggICAAAAA==.',['Hô']='Hôpisgone:BAAALAADCggIBwAAAA==.',Id='Idrael:BAAALAAECgIIAgAAAA==.',Io='Iordillidan:BAAALAAECgEIAQAAAA==.',Iw='Iwop:BAAALAAECgMIBgABLAAECgYIBwABAAAAAA==.',Ja='Jasna:BAAALAAECgYIDAAAAA==.',Je='Jeckwecker:BAAALAADCggIDwAAAA==.',Jo='Jocla:BAAALAAECgYICgAAAA==.Johnnash:BAAALAAECgEIAQAAAA==.Jolynna:BAAALAAECgMIAwAAAA==.Jolâin:BAAALAAECgMIAwAAAA==.',['Jö']='Jörmungand:BAAALAAECgEIAQABLAAECgMIBQABAAAAAA==.',Ka='Kasos:BAAALAADCggICAAAAA==.Kassiah:BAAALAAECgYICgAAAA==.Katihunt:BAABLAAECoEVAAIEAAgI2iPWAgBHAwAEAAgI2iPWAgBHAwAAAA==.',Ke='Kelts:BAAALAADCggIDwAAAA==.',Kh='Khaotik:BAAALAAECgYIDAAAAA==.',Ki='Kimiwaro:BAAALAADCgIIAgAAAA==.',Kl='Kleriøsse:BAAALAAECgcIBwAAAA==.',Ko='Kohane:BAAALAAECgMIBAAAAA==.',Kr='Krazhul:BAAALAADCgUIBQAAAA==.',Ku='Kurlly:BAAALAAECgYIDwAAAA==.Kurlsham:BAAALAADCgIIAgAAAA==.',La='Lamortu:BAAALAADCggICAAAAA==.Laëticia:BAAALAADCggIDQAAAA==.',Le='Lebang:BAAALAADCgcIBwAAAA==.Lektus:BAAALAADCgEIAQAAAA==.',Li='Lichkiing:BAAALAADCggICAAAAA==.',Lo='Louâne:BAAALAAECgUICQAAAA==.',Ly='Lynëa:BAAALAAECgMIBAAAAA==.Lyopa:BAAALAAECgQICQAAAA==.Lyow:BAAALAAECgMIAwABLAAECgQICQABAAAAAA==.Lyrrä:BAAALAADCgUIAgAAAA==.',['Lä']='Läuräne:BAAALAAECgUICgAAAA==.',['Lö']='Lödëa:BAAALAADCgcIBwAAAA==.',Ma='Magikchami:BAAALAAECgEIAQAAAA==.Mamiebaker:BAAALAAECgYICgAAAA==.Marwo:BAAALAADCgQIBAAAAA==.Marylène:BAAALAADCgcIDQAAAA==.Matchaa:BAAALAAECgMIAwABLAAECgcIDAABAAAAAA==.Mattmdevoker:BAAALAADCgcICQAAAA==.Mattmdkr:BAAALAAECgYIDgAAAA==.Mayuu:BAAALAAFFAIIAgAAAA==.Mazamune:BAAALAADCggIEAAAAA==.',Md='Mdfury:BAAALAADCgUIAgAAAA==.',Me='Metalhead:BAAALAAECgMIBQAAAA==.',Mi='Midrashim:BAAALAAECgYIDQAAAA==.Mikado:BAAALAADCgQIBAAAAA==.Misska:BAAALAAECgIIAwAAAA==.Missliadrin:BAAALAADCggIEAAAAA==.Mitterrand:BAAALAAECgcIDgAAAA==.',Mo='Mongrototem:BAAALAAECgMIBAAAAA==.',['Mä']='Mäxøu:BAABLAAECoEUAAIFAAgIKhlgBgBzAgAFAAgIKhlgBgBzAgAAAA==.',['Mî']='Mîmîc:BAAALAAECgYIDAAAAA==.',['Mô']='Môb:BAAALAADCgYIBgAAAA==.',Na='Naael:BAABLAAECoEVAAMGAAgIWyCPAwAUAwAGAAgIWyCPAwAUAwAHAAEIAgaDHQAuAAAAAA==.Naincappable:BAAALAAECgUICQABLAAECggIFgAIAP8dAA==.Nainpausepas:BAAALAAECgYICQAAAA==.Nascraf:BAAALAAECgUICQAAAA==.',Ne='Neferupitø:BAAALAADCggICgAAAA==.',Ni='Niroel:BAAALAAECgYIDQAAAA==.',No='Normux:BAAALAAECgQICAAAAA==.',Ny='Nyzzra:BAAALAADCggIFwAAAA==.',Oc='Océanika:BAAALAADCggIEQAAAA==.',Og='Ogïon:BAAALAAECgEIAQAAAA==.',Ok='Okaya:BAAALAADCgIIAgAAAA==.',Op='Opaal:BAAALAAECgcIDAAAAA==.',Pa='Paki:BAAALAAECgIIAgAAAA==.Paladoxis:BAAALAADCggIDQAAAA==.Palapagou:BAAALAAECgQIBAAAAA==.Palofou:BAAALAADCgQIBAAAAA==.Pandöra:BAAALAAECgUICAAAAA==.',Pe='Pewpewpewpew:BAAALAAECgYIDwAAAA==.',Pi='Pied:BAAALAAECgcIDQAAAA==.Pitu:BAAALAAECgEIAQAAAA==.',Pl='Plubobo:BAAALAAECgcIDwAAAA==.',Po='Poppi:BAAALAAECgYIBgAAAA==.',['Pà']='Pàblo:BAAALAAECgMIAwAAAA==.',['På']='Påf:BAAALAAECgEIAQAAAA==.',Ra='Rakarash:BAAALAAECgYIDQAAAA==.Razorgate:BAAALAAECgEIAQAAAA==.',Rh='Rhinoféroce:BAAALAAECgMIBQAAAA==.',Ri='Rivella:BAAALAAECgUIBQAAAA==.',Ru='Rusty:BAAALAADCggIDgAAAA==.',Sa='Saaka:BAAALAADCgcIDgAAAA==.Saille:BAAALAAECgQIBAAAAA==.Saiseï:BAABLAAECoEWAAIFAAgIPBZkCQAkAgAFAAgIPBZkCQAkAgAAAA==.Saku:BAAALAAECgIIAgAAAA==.Satîna:BAAALAADCggICAAAAA==.',Se='Sergisergio:BAABLAAECoEWAAMIAAgI/x3hCgB1AgAIAAcIXx/hCgB1AgAJAAUIDBewDQBRAQAAAA==.Severine:BAAALAADCgUIBQAAAA==.',Sh='Shiiro:BAAALAAECgUICAAAAA==.Shoob:BAAALAADCgUIBQAAAA==.Shoryuken:BAAALAADCgEIAQAAAA==.Shãlliã:BAAALAADCgIIAgAAAA==.',Sk='Skiunk:BAAALAADCgUIBAAAAA==.Skäldÿ:BAAALAAECgcIDAAAAA==.',Sl='Slðw:BAAALAAECgcIDgAAAA==.',St='Stargane:BAAALAAECgUICAAAAA==.Stil:BAAALAADCgYIBgAAAA==.Stéllà:BAAALAADCgcICgAAAA==.Størmss:BAAALAADCgEIAQAAAA==.',Su='Sunrise:BAAALAADCgcICwAAAA==.Surprise:BAAALAADCgcIBwAAAA==.Survie:BAAALAAECgcICQAAAA==.',Sy='Symbâd:BAAALAADCggIFwAAAA==.',['Sø']='Søùltrâp:BAAALAAECgYICwABLAAFFAMIBQAKADUSAA==.Søùlträp:BAACLAAFFIEFAAIKAAMINRJMBAAIAQAKAAMINRJMBAAIAQAsAAQKgR0AAgoACAjQIN4FAAYDAAoACAjQIN4FAAYDAAAA.Søültrâp:BAAALAAECgYIDQABLAAFFAMIBQAKADUSAA==.',Tg='Tgpied:BAAALAAECgcICQAAAA==.',Th='Thania:BAAALAADCggIEAABLAAECgMIBQABAAAAAA==.Thaoreghil:BAAALAAECgcIDwAAAA==.Theopoil:BAAALAADCggIDgAAAA==.Thémesta:BAAALAADCgMIAwAAAA==.',Ti='Timalf:BAAALAAECgEIAQAAAA==.',To='Tonko:BAAALAADCgcIDQAAAA==.Torchon:BAAALAAECgcIDwAAAA==.Torgale:BAAALAAECgMIAwAAAA==.Tototeman:BAAALAAECgQIBwAAAA==.Toudindecou:BAAALAAFFAIIAgAAAA==.Towi:BAAALAAECgcIDwAAAA==.Towny:BAAALAAECgUICgAAAA==.',Tr='Trollhiwood:BAAALAAECgMIAwAAAA==.',Tu='Tungsten:BAAALAADCggICwAAAA==.Tunkashilla:BAAALAAECgEIAQAAAA==.',Ty='Tyrandis:BAAALAAECgMIBQAAAA==.Tyshzdk:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Tyshzlock:BAAALAAECgYIDAAAAA==.',['Tø']='Tøshirø:BAAALAAECgYIDAABLAAECgYIDgABAAAAAA==.',Ul='Ulvik:BAAALAAECgEIAQAAAA==.',Us='Usée:BAAALAAECgMIAwAAAA==.',Va='Valery:BAAALAADCgcIBwAAAA==.Valye:BAAALAADCggIFAAAAA==.Valythir:BAAALAAECgQIBwAAAA==.Vany:BAAALAAECgYIDAAAAA==.Varko:BAAALAAECgUICgAAAA==.',Vi='Vitolino:BAAALAAECgMIBQAAAA==.',Vn='Vnl:BAAALAADCgcIFAAAAA==.Vnlpal:BAAALAADCgcIEQAAAA==.',Vo='Vorka:BAAALAADCgcIDQABLAAECgUICgABAAAAAA==.',Wa='Wartaff:BAAALAAECgQIBgAAAA==.Waryana:BAAALAAECgIIAgAAAA==.Watibonk:BAAALAAECgcIDwAAAA==.Watijtgoume:BAAALAADCgMIAwAAAA==.',We='Wendass:BAAALAADCgcIBwAAAA==.',Wh='Whitekilleur:BAAALAAECgIIAwAAAA==.',Wo='Wolferine:BAAALAAECgIIAgAAAA==.',['Wø']='Wølf:BAAALAAECgUICwAAAA==.',Ya='Yamajii:BAAALAADCgcICgAAAA==.Yasmina:BAAALAAECgMIAwAAAA==.Yaundel:BAAALAADCgQIBAAAAA==.',Yo='Yotsuba:BAAALAAECgQIBAAAAA==.',Yu='Yujinn:BAAALAADCgcIBwABLAAECgUIBgABAAAAAA==.Yulam:BAAALAADCggICQAAAA==.',['Yö']='Yöuffy:BAAALAADCggIEQAAAA==.',['Yø']='Yøupi:BAAALAADCggIFgAAAA==.',Za='Zarakí:BAAALAAECgYICAAAAA==.',Ze='Zenethor:BAAALAAECgYICwAAAA==.Zephyrïa:BAAALAAECgIIAgAAAA==.',Zr='Zréya:BAAALAADCgQIBAAAAA==.',Zu='Zunn:BAAALAADCgcIDQAAAA==.Zunnh:BAAALAAECgQIBAAAAA==.',['Äb']='Äbbydh:BAAALAAECgQIBgAAAA==.',['Æz']='Æzertyx:BAAALAADCgcIBwAAAA==.',['Él']='Élmére:BAAALAAECggIAgAAAA==.',['Ïq']='Ïquero:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end