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
 local lookup = {'Unknown-Unknown','Shaman-Enhancement','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Arcane','Priest-Shadow','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','Evoker-Devastation','Warrior-Arms','Priest-Holy','Mage-Frost','Warrior-Fury','DeathKnight-Frost',}; local provider = {region='EU',realm="Drek'Thar",name='EU',type='weekly',zone=44,date='2025-08-30',data={Ad='Adriou:BAAALAADCgUIBQABLAADCggIEgABAAAAAA==.',Ae='Aech:BAAALAAECgIIAgAAAA==.Aechmort:BAAALAAECgIIAwAAAA==.Aelinth:BAAALAADCggIEAAAAA==.',Ak='Akie:BAAALAADCggIFQAAAA==.Akätsükï:BAAALAAECgMIBQAAAA==.',Al='Albaphiqua:BAAALAAECgEIAQAAAA==.Alduine:BAAALAAECgMIBwAAAA==.Aliella:BAAALAAECgQIBwAAAA==.Allerya:BAAALAADCgEIAQAAAA==.Alopus:BAAALAAECgYICgAAAA==.Althéa:BAAALAAECgcIDQAAAA==.',Am='Amatøx:BAABLAAECoEWAAMCAAYIxhnzCQCLAQACAAYIxhnzCQCLAQADAAYIOw2lSQD3AAAAAA==.',An='Anarkya:BAAALAAECgMIAwAAAA==.Angelito:BAAALAADCgcIEAAAAA==.',Ar='Aradil:BAAALAADCggICAAAAA==.Aragore:BAAALAAECgIIBAAAAA==.Arch:BAABLAAECoEYAAMEAAgI4CNKBQAVAwAEAAgImiNKBQAVAwAFAAcIdiAUCACmAgAAAA==.Archanologie:BAAALAAECgIIAgABLAAECggIGAAEAOAjAA==.Arinn:BAAALAADCgcIDAAAAA==.Armogos:BAAALAAECgYIEQAAAA==.Arthlas:BAAALAADCggIDwAAAA==.Artory:BAABLAAECoEUAAQGAAcItx+vHQDXAQAGAAYIcxmvHQDXAQAHAAMI1SDQJwAmAQAIAAIIvxHDHwCHAAAAAA==.',As='Astroo:BAAALAAECgEIAQAAAA==.Asyliaa:BAAALAADCgcIBwAAAA==.',Au='Aunix:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.',Av='Avacrown:BAAALAAECggICAAAAA==.',Ay='Ayakan:BAAALAAECgEIAQAAAA==.',Az='Azraëlle:BAAALAAECgUIBQAAAA==.Azürÿa:BAAALAADCgcIDgAAAA==.',Ba='Bailla:BAAALAADCgYIBgAAAA==.Balybalo:BAAALAAECgYICAAAAA==.',Be='Beleti:BAAALAADCggICAAAAA==.Belgafon:BAAALAAECgYICwAAAA==.',Bi='Bibinounette:BAAALAADCgIIAgAAAA==.Bistouris:BAAALAADCgYICQAAAA==.',Bl='Blackfast:BAAALAAECgQIBwAAAA==.',Bo='Bonnepinte:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Borussia:BAAALAAECgIIAgAAAA==.Boukitoos:BAAALAAECgQIBAABLAAECgYIEAABAAAAAA==.',Bu='Bubss:BAAALAADCggIEAAAAA==.',['Bø']='Børatgirl:BAAALAAECgEIAQAAAA==.',Ca='Carenath:BAAALAAECgQIBAAAAA==.Catalleyaa:BAAALAAECgYIDQAAAA==.Cattalleya:BAAALAAECgMIBAABLAAECgYIDQABAAAAAA==.Catäclysme:BAAALAAECgMIAwAAAA==.',Ch='Chamezouls:BAAALAAECgMIAwAAAA==.Chamøu:BAAALAAECgEIAQAAAA==.Chandail:BAAALAAECgUICgAAAA==.Chlo:BAAALAAECgEIAQAAAA==.Chtibidi:BAAALAAECgIIBAAAAA==.Chucknorriz:BAABLAAECoEYAAIJAAgIqxaJFwBfAgAJAAgIqxaJFwBfAgAAAA==.Chuupiih:BAAALAAECgcIDgAAAA==.',Ci='Cibella:BAAALAADCgUICAAAAA==.Cide:BAAALAAECgIIAgAAAA==.',Cr='Crackitos:BAAALAAECgYICwABLAAECgYIEAABAAAAAA==.Cranemp:BAAALAADCgQIBAABLAADCggIEgABAAAAAA==.',['Cå']='Cållisto:BAAALAADCgcIBwAAAA==.',Da='Daliâ:BAAALAAECgIIAgABLAAECgUICAABAAAAAA==.Damvache:BAAALAAECgMICAAAAA==.Daria:BAAALAAECgYICwAAAA==.',De='Demoniakie:BAAALAAECgYIBgAAAA==.Demora:BAAALAADCggICAABLAAECgQIBwABAAAAAA==.Destring:BAAALAADCggIDQAAAA==.',Dh='Dhibride:BAAALAAECgYICAAAAA==.',Di='Diukez:BAAALAAECgcIDQAAAA==.',Dr='Dracobuzz:BAAALAADCggICAAAAA==.Droganz:BAABLAAECoEYAAIKAAgIMhc2DwBcAgAKAAgIMhc2DwBcAgAAAA==.Droopi:BAAALAAECgYIBgAAAA==.',Dw='Dwala:BAAALAADCgcIDgAAAA==.',['Dä']='Dätcham:BAAALAAECgMIBQAAAA==.',['Dé']='Démézia:BAAALAAECgMIBgAAAA==.',Ef='Efinwel:BAAALAAECgcIEwAAAA==.',El='Eldenmer:BAAALAADCgYIBgAAAA==.Elfanaa:BAAALAAECgYIBwAAAA==.Ellenya:BAAALAAECgcIDAAAAA==.Ellîath:BAAALAADCggICAAAAA==.Elundril:BAAALAAFFAIIAgAAAA==.',Em='Emeental:BAAALAADCggIDwAAAA==.',En='Enaeco:BAAALAADCggIDgAAAA==.',Er='Erandil:BAAALAAECgEIAQAAAA==.',Ev='Evengelion:BAAALAAECgIIBAAAAA==.',Ex='Exonar:BAAALAAECggICwAAAA==.',Fe='Feig:BAAALAAECgQIBAAAAA==.Felicita:BAAALAADCgYIBgAAAA==.Felistìria:BAABLAAECoEUAAILAAcI/Bu+DgAhAgALAAcI/Bu+DgAhAgAAAA==.',Fg='Fgez:BAAALAAECgIIAQABLAAECgYICgABAAAAAA==.',Fl='Flemethe:BAAALAAECgMIAwAAAA==.Floribella:BAAALAAECgIIAgAAAA==.',Fr='Francislalam:BAAALAAECgQIBwAAAA==.Frostal:BAABLAAECoEVAAMMAAgIpRfiDABbAgAMAAgICBfiDABbAgANAAcIaxOKBQDkAQAAAA==.Frst:BAAALAADCgcIDgAAAA==.Frøøsty:BAAALAAECgMIAwAAAA==.',Fu='Furyh:BAAALAAECgMIAwAAAA==.',['Fä']='Fäuust:BAAALAAECgYIBgAAAA==.',Ga='Galounaïaa:BAAALAADCgQIBAAAAA==.Gargöl:BAAALAADCggIFgAAAA==.',Ge='Gemna:BAAALAADCggIDAABLAAECgMIBQABAAAAAA==.',Gl='Glenn:BAAALAADCggICAAAAA==.',Gn='Gnömînette:BAAALAADCgQIBAAAAA==.',Go='Gougueulkar:BAAALAAECgYICgAAAA==.Gozz:BAAALAADCgcIBwAAAA==.',Gr='Granork:BAAALAADCggIEAAAAA==.',['Gä']='Gällaad:BAAALAADCgYIBgAAAA==.',['Gë']='Gënocee:BAAALAAECgMIAwAAAA==.',Ha='Haldises:BAAALAADCggICAAAAA==.Haldra:BAAALAADCgcIBwABLAAECggIFgAOAGUlAA==.Hanax:BAABLAAECoEUAAIPAAcInSR+AQC6AgAPAAcInSR+AQC6AgAAAA==.Hansaplastus:BAAALAAECgcIBwAAAA==.Hastérion:BAAALAADCgcIBwAAAA==.',He='Hesseth:BAAALAAECgQIBQAAAA==.',Hi='Hillidanl:BAAALAADCgcIBwAAAA==.Hixae:BAAALAAECgQIBwAAAA==.',Hj='Hjell:BAAALAADCgYIBgAAAA==.',Hu='Hugnir:BAAALAAECgQIBwAAAA==.Hulktar:BAAALAADCggICAAAAA==.Hulkutir:BAAALAAECgEIAQAAAA==.Huma:BAAALAAECgcICwAAAA==.Hunthera:BAAALAADCgcIFAAAAA==.',If='Ifagwe:BAAALAAECgcIDwAAAA==.Ifni:BAAALAAECgMIBAAAAA==.',Ir='Irzak:BAAALAADCgEIAQABLAAECgMIBQABAAAAAA==.',Is='Isille:BAAALAADCgcIBwAAAA==.Ismir:BAAALAADCgMIAwABLAADCggIEgABAAAAAA==.',Ja='Jackychäm:BAAALAAECgcIDgAAAA==.Jaladin:BAAALAADCgcIBwAAAA==.Janopetrus:BAAALAAECgEIAgABLAAECgYICAABAAAAAA==.',Je='Jessica:BAAALAADCgcIBwAAAA==.Jesterdead:BAAALAADCgcIDAAAAA==.',Ji='Jiltz:BAAALAAECgMIBgAAAA==.Jimangel:BAAALAAECgMICAAAAA==.Jimillin:BAAALAAECgQICQAAAA==.',Ju='Junip:BAAALAADCggIDAAAAA==.',Ka='Kapitch:BAAALAAECgYICgAAAA==.Karaël:BAAALAADCgYICQAAAA==.Kattarakte:BAAALAADCggIDAABLAADCggIDwABAAAAAA==.Kayanhi:BAAALAADCggIDQAAAA==.',Ke='Kelra:BAAALAADCgYICgAAAA==.Kelrà:BAAALAADCgYIBgABLAADCgYICgABAAAAAA==.Keridan:BAAALAAECgMIBQAAAA==.Kerrigan:BAAALAADCggICAAAAA==.Ketamïne:BAAALAAECgEIAgAAAA==.Kewaux:BAAALAAECggIDgAAAA==.',Kh='Khaliks:BAAALAAECgMIAwAAAA==.',Kl='Klaplouf:BAAALAADCgMIAwABLAADCggIDwABAAAAAA==.',Kr='Kraoseur:BAAALAADCgMIAwAAAA==.Krimy:BAAALAADCgMIAwAAAA==.',['Kí']='Kíwí:BAAALAADCgEIAQAAAA==.Kíwï:BAAALAADCgYIBgAAAA==.',['Kî']='Kîlâ:BAAALAADCgQIAQAAAA==.',La='Lacamarde:BAAALAADCggIDwAAAA==.Laênae:BAAALAADCgcIBwAAAA==.',Li='Lidius:BAAALAADCgIIAgAAAA==.Liloü:BAAALAADCgQIAwAAAA==.Lincce:BAAALAAECgEIAQAAAA==.Litvhi:BAAALAAECgIIAgAAAA==.',Lo='Lovst:BAAALAAECgIIAgAAAA==.',Ly='Lydhïa:BAAALAADCgcIBwAAAA==.Lystys:BAABLAAECoEUAAIQAAcIEQddLQBOAQAQAAcIEQddLQBOAQAAAA==.',['Là']='Làilah:BAAALAADCggIDwAAAA==.',['Lé']='Léoline:BAAALAAECgMIBQAAAA==.',['Lë']='Lëön:BAAALAAECgMIBQAAAA==.',Ma='Malauxyeux:BAAALAAECgMIBQAAAA==.Mamayet:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Mayween:BAAALAAECgQIBwAAAA==.',Me='Meilleur:BAAALAAECggIDgAAAA==.Meta:BAAALAAECgYIDgAAAA==.',Mi='Mibz:BAAALAAECgEIAQAAAA==.Mikael:BAAALAADCgMIBgAAAA==.Mikkadoo:BAAALAADCggICAAAAA==.Milune:BAAALAAECgMIAwAAAA==.Minifigue:BAAALAADCgIIAgAAAA==.',Mo='Morbax:BAAALAADCgcIBwAAAA==.Mordore:BAAALAAECgMIBQAAAA==.',Mu='Mucus:BAAALAADCggIFAAAAA==.Muradroud:BAAALAAECgIICAAAAA==.Muroorgamd:BAAALAAECgYIBwAAAA==.Musôtensei:BAAALAAECgMIAwAAAA==.',['Mà']='Mààt:BAAALAAECgYICgAAAA==.',['Má']='Málycia:BAAALAAECgYIBgAAAA==.',['Më']='Mërlin:BAAALAAECgYIBgAAAA==.',Na='Naamu:BAAALAAECgYICQAAAA==.Nanko:BAABLAAECoEWAAIOAAgIZSXGAABuAwAOAAgIZSXGAABuAwAAAA==.Narwel:BAAALAAECgQIBgAAAA==.Nausicää:BAAALAADCgQIBAAAAA==.',Ne='Necronomecan:BAAALAAECgQIBwAAAA==.',Ni='Nightfly:BAAALAADCggICAAAAA==.Ninial:BAAALAAECgUICAAAAA==.Nitø:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.',No='Noadk:BAAALAAECgUICAAAAA==.Normal:BAAALAAECgYIDAAAAA==.Nourgortan:BAAALAAECgQIAwAAAA==.',Nu='Nunderran:BAAALAAECgcIDAAAAA==.',Ob='Oblione:BAAALAAECgEIAQAAAA==.',Oe='Oeildeglace:BAAALAADCggIDgAAAA==.',Ol='Olÿmpe:BAAALAADCgUIBQAAAA==.',Or='Orkaya:BAAALAAECgYIBgAAAA==.',Ox='Oxfuz:BAAALAAECgYIDQAAAA==.',Pa='Palacoco:BAAALAADCgYIBgAAAA==.Paladania:BAAALAADCgIIAgAAAA==.Paladina:BAAALAADCgcIBwAAAA==.Palaric:BAABLAAECoEWAAIRAAgIcSRrAQBDAwARAAgIcSRrAQBDAwAAAA==.Palibis:BAAALAADCgYIBgAAAA==.Paltauren:BAAALAADCgYIBgAAAA==.Papayet:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.Papillimp:BAAALAAECgMIAwAAAA==.',Pe='Peachounette:BAAALAADCggIDwAAAA==.',Pi='Pibo:BAAALAADCggIEgAAAA==.',Po='Pomillo:BAABLAAECoEUAAISAAgIxCNqAwA/AwASAAgIxCNqAwA/AwAAAA==.Poylder:BAAALAAECgUICAAAAA==.',Pr='Pretous:BAAALAAECgYIBgAAAA==.',Qu='Quake:BAAALAADCgQIAwAAAA==.',Ra='Ragasoniic:BAAALAADCggIGAAAAA==.Raglar:BAAALAADCggIEAAAAA==.Rannèk:BAAALAAECgIIAwAAAA==.Ratchet:BAAALAAECgMIBAAAAA==.',Ro='Rocks:BAAALAADCggICAAAAA==.Rodølfus:BAAALAAECggICwAAAA==.Rominoo:BAAALAAECgYICgAAAA==.',Rr='Rromanne:BAAALAAECgYICwAAAA==.',['Ré']='Réjène:BAAALAAECgcIDwAAAA==.',Sa='Sazoulsia:BAAALAADCgYIBgAAAA==.',Se='Seipth:BAAALAAECgQIBwAAAA==.Sephreina:BAAALAAECgYIDwAAAA==.',Sh='Shadka:BAAALAADCggIDwAAAA==.Shadowzoulls:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Shank:BAAALAADCgQIBAAAAA==.Shemira:BAABLAAECoEUAAITAAcI6hhUIgAFAgATAAcI6hhUIgAFAgAAAA==.Sheìtan:BAAALAADCgcIEQAAAA==.Shoeiliche:BAAALAAECgQIBAAAAA==.',Si='Silverâzz:BAAALAADCggIEAAAAA==.Simbiotik:BAAALAAECgcIDgAAAA==.Sindira:BAAALAAECgYIDAAAAA==.Sinergi:BAAALAAECgYICAAAAA==.',Sk='Skildoux:BAAALAAECgMIAwAAAA==.',Sn='Snoww:BAAALAADCgcIBwAAAA==.',So='Sobad:BAAALAAECgIIAwAAAA==.Sohryø:BAAALAADCggIDwAAAA==.Soomeoone:BAAALAAECgYIEAAAAA==.',St='Strïke:BAAALAADCgEIAQAAAA==.',Sy='Sylyas:BAAALAADCgUIBQAAAA==.Synapse:BAAALAAECggIBgAAAA==.Syska:BAAALAAECgMIAwAAAA==.',['Sé']='Sémiramis:BAAALAADCgcIBwAAAA==.',['Sê']='Sêven:BAAALAAECgYIDQAAAA==.',Ta='Taehlx:BAAALAAECgcIDgAAAA==.Takalove:BAAALAADCggIDwAAAA==.Talianna:BAAALAADCgYIBgAAAA==.Talulah:BAABLAAECoEWAAIFAAYIYhQ6LgD9AAAFAAYIYhQ6LgD9AAAAAA==.Taralor:BAAALAAECgIIAgAAAA==.Tarsillia:BAAALAADCggIFQAAAA==.',Te='Teraa:BAAALAAFFAIIAgAAAA==.Tetra:BAAALAADCgcIBwABLAADCggIDAABAAAAAA==.',Th='Thalira:BAAALAAECggICgAAAA==.Thanarion:BAAALAAECgQIBwAAAA==.Thaïfaros:BAAALAADCgUIBQABLAAECgMIBgABAAAAAA==.Thorpath:BAAALAADCggIHgAAAA==.Thorpem:BAAALAADCgcIBwAAAA==.',Ti='Timey:BAAALAADCgcIBwAAAA==.Tiss:BAAALAAECgMIAwAAAA==.',Tr='Trakcost:BAAALAAECgMIBQAAAA==.Troolli:BAAALAADCgcIBwAAAA==.',['Tø']='Tørmentsnøw:BAAALAADCgEIAQAAAA==.',Ul='Ulticre:BAAALAADCggIDAAAAA==.',Uz='Uzukolyo:BAAALAADCggIFQAAAA==.',Va='Vaampa:BAAALAAECgcIEQAAAA==.Valtéria:BAAALAADCgIIAwAAAA==.Varay:BAAALAAECgQICgAAAA==.',Ve='Versyngetori:BAAALAADCggIEgAAAA==.',Vh='Vhal:BAAALAADCgcIBwAAAA==.',Vi='Vieillepoo:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Vin:BAAALAADCggIEAAAAA==.',Vl='Vlaad:BAAALAADCgcIBwAAAA==.',Vo='Volôloîn:BAAALAADCgQIBQAAAA==.',Vy='Vyraik:BAAALAAECgMIBQAAAA==.Vyvy:BAAALAAECgMIAwABLAAECgMIBQABAAAAAA==.',['Và']='Vàldismonk:BAAALAADCggICQAAAA==.',['Vî']='Vîncus:BAAALAAECgUICAAAAA==.',Wa='Wayreth:BAABLAAECoEUAAIJAAcImhpRHAA5AgAJAAcImhpRHAA5AgAAAA==.',We='Wespe:BAAALAAECgcIDgAAAA==.',Wu='Wurta:BAAALAADCggIDgAAAA==.',Wy='Wyksaelle:BAAALAAECgcIDgAAAA==.',['Wä']='Wäyätt:BAAALAADCgcIDQAAAA==.',Xa='Xare:BAAALAADCgIIAgAAAA==.',Ya='Yapa:BAAALAAECgMIAwAAAA==.',Yg='Yggdräsïl:BAAALAAECgEIAQAAAA==.',Yo='Yoxi:BAAALAAECgYICwAAAA==.',Yu='Yuurei:BAAALAAECgQIBwAAAA==.',Zi='Ziboud:BAAALAAECgMIBgAAAA==.',['Zä']='Zängarrä:BAAALAADCggICwAAAA==.',['Äl']='Äldaron:BAAALAADCggIEAAAAA==.',['Är']='Ärch:BAAALAAECgUIBwABLAAECggIGAAEAOAjAA==.',['Él']='Élium:BAAALAAECggIEQAAAA==.',['Ïw']='Ïwïi:BAAALAAECggIAQAAAA==.',['Øm']='Ømbré:BAAALAAECgMIBQAAAA==.',['ßo']='ßoukitos:BAAALAAECgYIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end