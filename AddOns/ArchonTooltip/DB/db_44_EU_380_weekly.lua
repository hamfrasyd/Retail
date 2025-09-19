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
 local lookup = {'Warrior-Arms','Warrior-Fury','Unknown-Unknown','DeathKnight-Frost','Druid-Balance','DeathKnight-Unholy','DeathKnight-Blood','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Shaman-Elemental','Warlock-Affliction','Warrior-Protection','Paladin-Holy','Mage-Arcane','Mage-Fire',}; local provider = {region='EU',realm='Medivh',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abalonne:BAAALAAECgQICAAAAA==.',Ac='Ach:BAAALAADCggIDwAAAA==.',Ad='Addey:BAAALAAECgMIBAAAAA==.',Ae='Aerhos:BAAALAAECgYIBgAAAA==.',Ak='Akcunda:BAAALAADCggIBwAAAA==.',Al='Aldétao:BAAALAAECgIIAgAAAA==.Aloulou:BAAALAAECgYIEgAAAA==.Aloulouia:BAAALAAECgYICgAAAA==.Alphabruts:BAAALAADCgcIDgAAAA==.Alrakazbam:BAAALAADCggIFwAAAA==.',An='Angell:BAAALAADCgcIDgAAAA==.Anhydrrax:BAAALAADCgEIAQAAAA==.Annahé:BAAALAAECgUIBwAAAA==.',Ap='Apodecâ:BAAALAADCggIEAAAAA==.',Ar='Arkaziel:BAABLAAECoEUAAMBAAcIfCOiAQCyAgABAAcIfCOiAQCyAgACAAMIeQ4BRQCpAAAAAA==.Armaeris:BAAALAADCggIDwABLAADCggIDwADAAAAAA==.Artaas:BAAALAAECgYICwAAAA==.Arÿ:BAAALAAECgcIDQAAAA==.',As='Askell:BAAALAADCgUIBQAAAA==.Aspeak:BAAALAADCgYIBgAAAA==.',At='Atlantya:BAAALAADCggIDQAAAA==.',['Aï']='Aïkô:BAAALAAECgEIAQAAAA==.',Ba='Babykaizer:BAAALAAECgMIBgAAAA==.Bachibouzook:BAEALAADCgcICwABLAAECgUICQADAAAAAA==.Ballrogue:BAAALAADCggIDQAAAA==.Barbarella:BAAALAADCggICAAAAA==.',Bi='Birgittbarjo:BAAALAADCgUIBQAAAA==.',Bl='Blacksan:BAAALAADCggICAAAAA==.Blekz:BAAALAAECgEIAQAAAA==.Bligzdemone:BAAALAADCgYIBgAAAA==.',Bo='Boinboin:BAAALAAECgIIAgAAAA==.Boldar:BAAALAAECgQICAAAAA==.Bouledepoual:BAAALAADCgcIBwAAAA==.',Br='Brocéfilénia:BAAALAAFFAEIAQAAAA==.Brocéliandre:BAAALAADCggICAAAAA==.',Bu='Bubulle:BAAALAADCgYICwAAAA==.Bulladin:BAAALAADCgcIBwAAAA==.Butchër:BAAALAADCgEIAQAAAA==.',['Bö']='Böduog:BAAALAAECgQICAAAAA==.',Ce='Celeborn:BAAALAADCggICAAAAA==.Celtus:BAAALAADCgcIBwAAAA==.',Ch='Chaney:BAAALAADCgcICAAAAA==.Charckan:BAAALAAECgcIDwAAAA==.Chriz:BAAALAADCgMIAwAAAA==.Chymay:BAAALAADCggICAAAAA==.Chymene:BAAALAADCggIDwAAAA==.Châmânos:BAAALAADCgIIAgAAAA==.',Cl='Clayman:BAAALAADCggIDwAAAA==.Clutu:BAAALAADCggICAAAAA==.',Co='Codrus:BAAALAAECgEIAQAAAA==.Confidence:BAAALAADCgcIBwAAAA==.',Cr='Crevur:BAAALAAECgYIBgAAAA==.Croukol:BAAALAADCgQIBAAAAA==.',['Cé']='Céellex:BAAALAAECgQICAAAAA==.',['Cø']='Cørey:BAAALAAECgIIAgAAAA==.',Da='Damaran:BAAALAADCggICgAAAA==.Danka:BAAALAADCgcIDgAAAA==.',De='Demonyack:BAAALAADCgYICAABLAADCggIDgADAAAAAA==.Deriiox:BAAALAADCggICAAAAA==.Destriacion:BAAALAADCggIDQAAAA==.',Di='Diamønds:BAAALAADCgYIBgAAAA==.Dispel:BAEALAAECgUICQAAAA==.',Do='Doomibis:BAAALAADCgYICgAAAA==.Doominette:BAAALAADCgUIBwAAAA==.Douceure:BAAALAADCggICAAAAA==.',Dr='Dracodoom:BAAALAADCgMIAwAAAA==.',['Dâ']='Dârktek:BAAALAAECgcIEAAAAA==.',El='Ellmago:BAAALAADCgcIBwAAAA==.Ellÿnna:BAAALAAECgMIAwAAAA==.Elrubis:BAAALAAECgIIAgAAAA==.',Em='Eminda:BAAALAADCgcIDAAAAA==.',Er='Erikabergen:BAAALAAECgcICgAAAA==.Erindal:BAAALAAECgYICgAAAA==.Erykä:BAAALAAECgMIAwAAAA==.',Ex='Exxodus:BAAALAADCgcICAAAAA==.',Ez='Ezactement:BAAALAADCgcIBwABLAADCggICAADAAAAAA==.',Fa='Fabÿ:BAAALAADCggIDwAAAA==.Fangpi:BAAALAAECgcIDwAAAA==.Farlock:BAAALAAECgYIDgAAAA==.Faust:BAAALAADCgYICAAAAA==.',Fi='Finëss:BAAALAAECgQIBgAAAA==.',Fj='Fjordicus:BAAALAADCggIEwAAAA==.',Fl='Flobarjo:BAAALAAECgcICgAAAA==.',Fo='Folkeÿnn:BAAALAAECgQIBAAAAA==.Forever:BAAALAAECgQIBwAAAA==.',Fr='Frostdeath:BAAALAADCggIEAAAAA==.',Ft='Ftmeinar:BAAALAAECggIBgAAAA==.Ftmjail:BAAALAAECggIBgAAAA==.Ftmleesin:BAAALAAECggIBgAAAA==.',Fu='Fubosselet:BAABLAAECoEVAAIEAAgIFiLJBwAEAwAEAAgIFiLJBwAEAwAAAA==.',['Fî']='Fîrnia:BAAALAAECgYIBgABLAAECgYIBgADAAAAAA==.',Ga='Gatol:BAAALAAECgQICAAAAA==.Gatrebile:BAAALAADCggICAAAAA==.',Ge='Gery:BAABLAAECoEYAAIFAAgI1COgAgBBAwAFAAgI1COgAgBBAwAAAA==.',Gi='Gigondas:BAAALAADCgIIAgAAAA==.',Go='Gounâ:BAAALAAECgMIBgAAAA==.',Gr='Grimes:BAAALAAFFAIIAgAAAA==.',Gu='Guerrixe:BAAALAAECgUIBgAAAA==.',Gz='Gzena:BAAALAADCgYIBgAAAA==.',Ha='Hadrïan:BAAALAAFFAEIAQAAAA==.Hannahé:BAAALAADCgUIBQABLAAECgUIBwADAAAAAA==.Harmonix:BAAALAAECgMIBQAAAA==.',He='Helloimtoxic:BAAALAADCgMIAwAAAA==.',Hi='Hibiki:BAAALAADCggIDwAAAA==.',Ho='Honjani:BAAALAAECgQICAAAAA==.',Hu='Huntinet:BAAALAADCgYIBgAAAA==.',['Hö']='Höor:BAAALAAECgYIDAAAAA==.',['Hø']='Hønixya:BAAALAADCgYIBgAAAA==.',Il='Illidone:BAAALAADCgEIAQAAAA==.Illÿria:BAAALAADCggICQAAAA==.',In='Injectîon:BAAALAADCgcIDgAAAA==.',Ja='Jackerer:BAAALAAECgUICwAAAA==.',Ka='Kalyysta:BAAALAAECgcIEAAAAA==.Karolün:BAAALAAECgIIAgAAAA==.Katastrofe:BAAALAADCggIDwAAAA==.Kayané:BAAALAADCgQIBAAAAA==.Kaënaa:BAAALAAECgQIBgAAAA==.',Ke='Kentinûs:BAAALAADCggICAAAAA==.',Kh='Kharan:BAAALAADCgMIAwAAAA==.Kharmé:BAABLAAECoEUAAMGAAcILyEQBQCIAgAGAAcILyEQBQCIAgAHAAMIFw6OGACVAAAAAA==.',Ki='Kiltara:BAABLAAECoEZAAMIAAcIixIqIwBzAQAIAAcIixIqIwBzAQAFAAEIJQJ0VAAlAAAAAA==.Kirikau:BAAALAAECgQICAAAAA==.',Kl='Klamehydias:BAAALAADCgcIBwAAAA==.Klobürste:BAAALAADCgMIAwAAAA==.Kléia:BAAALAADCggIDQAAAA==.',Kn='Knakky:BAAALAAECgQICAAAAA==.',Kr='Kromatix:BAAALAADCgcIDQAAAA==.',Ku='Kurdrbrew:BAAALAAECgYIBgAAAA==.Kurdrpprot:BAAALAAFFAIIAgAAAA==.Kurdrvdh:BAACLAAFFIEHAAIJAAMIwh5MAAAjAQAJAAMIwh5MAAAjAQAsAAQKgRYAAwkACAiJJZQAAGIDAAkACAiJJZQAAGIDAAoABghNDRhEAGYBAAAA.Kurdrwprot:BAAALAAECgcIBAAAAA==.',['Kä']='Kälÿ:BAAALAAECgYIBgAAAA==.',['Kø']='Køjirø:BAAALAADCggIDQAAAA==.',La='Lafae:BAAALAADCgcICAAAAA==.Lalle:BAAALAAECgcIBwAAAA==.Landï:BAAALAADCggIDgAAAA==.Lawthrall:BAABLAAECoEUAAILAAcIZBkbFQAiAgALAAcIZBkbFQAiAgAAAA==.Lawyna:BAAALAAECgIIAgAAAA==.',Le='Lecameleon:BAAALAADCggICAAAAA==.Ledarklord:BAAALAAECgYIBwAAAA==.Leducatrice:BAAALAADCgYIBgAAAA==.Lexane:BAAALAADCgcICQAAAA==.',Li='Littlewàr:BAAALAADCgIIAgAAAA==.',Lo='Lodae:BAAALAAECgIIAgAAAA==.',Lu='Lucilia:BAAALAADCgcIDQAAAA==.',['Lé']='Léahwar:BAAALAAECgYIBgAAAA==.',Ma='Maglor:BAAALAADCgcIEwAAAA==.Makiri:BAAALAADCgcIDgAAAA==.Malgarath:BAAALAAECgMIBAAAAA==.Maëstriaa:BAAALAADCgcIBwAAAA==.',Mi='Miaoying:BAAALAADCggIDwAAAA==.Minachan:BAAALAADCgMIAwAAAA==.Miniflash:BAAALAAECggIDwAAAA==.Miokama:BAAALAADCgcIBwAAAA==.',Mo='Monsterkills:BAAALAADCgYIBgABLAAECgQICAADAAAAAA==.Morthus:BAAALAADCgYIBwAAAA==.',My='Mystralle:BAAALAAECgUICQAAAA==.Mystíc:BAAALAAFFAIIAgAAAA==.',Na='Nagatip:BAAALAAECgYICgAAAA==.Nainguibus:BAAALAAECgIIAgAAAA==.Nakou:BAAALAAECgUIBgAAAA==.Narcisska:BAAALAADCgUIBQAAAA==.Navré:BAAALAAECgYIDAAAAA==.',Ne='Needhell:BAAALAADCggIEAAAAA==.Nerfi:BAAALAADCgcICAAAAA==.',No='Nouilleske:BAAALAAECgQIBQAAAA==.',['Nä']='Nälah:BAAALAAECgYICAAAAA==.',['Né']='Nébuleuse:BAAALAAECgIIAgAAAA==.Néfertarï:BAAALAADCgcIDQAAAA==.',['Nö']='Nöa:BAAALAADCgcIBwAAAA==.Nöly:BAAALAADCggICAAAAA==.',Ob='Obade:BAAALAADCggIDwAAAA==.',Or='Orcky:BAAALAAECgIIAgAAAA==.',Ou='Ourobouros:BAAALAAECgQICAAAAA==.',Ov='Overman:BAAALAADCggIFwAAAA==.',Pi='Pikpus:BAAALAADCgcIBwAAAA==.',Po='Portepeste:BAABLAAECoEUAAIMAAcIDxcNBQAtAgAMAAcIDxcNBQAtAgAAAA==.',Pr='Prêtro:BAAALAADCggICwAAAA==.',Ra='Ralgamaziel:BAAALAAECgEIAgAAAA==.Ranza:BAAALAADCggIDgAAAA==.',Ro='Roxis:BAAALAAECgcIEwAAAA==.',['Rø']='Røudarde:BAAALAAECgEIAQAAAA==.',Sa='Saguira:BAAALAADCgIIAgAAAA==.Sandokai:BAAALAAECgYIDAAAAA==.Sanpaz:BAAALAADCgYIBgAAAA==.Sarevok:BAAALAAECgQIBAAAAA==.',Sc='Scorpilia:BAAALAAECgEIAQAAAA==.Scorpinnia:BAAALAADCgcICQAAAA==.',Se='Selyna:BAAALAADCggIDgAAAA==.Sephylol:BAABLAAECoEUAAINAAcIwx3nCAA4AgANAAcIwx3nCAA4AgAAAA==.Septantecinq:BAAALAADCgYIDAAAAA==.Septienna:BAABLAAECoEUAAIOAAcIfx+GBgB0AgAOAAcIfx+GBgB0AgAAAA==.',Sh='Shamanar:BAAALAAECgMIAwAAAA==.Sheguéy:BAAALAADCgMIAwAAAA==.Shokicks:BAACLAAFFIEFAAMPAAMIthAMBgD0AAAPAAMIpRAMBgD0AAAQAAEItxBUAgBYAAAsAAQKgRcAAw8ACAh7ISYIAAUDAA8ACAh7ISYIAAUDABAAAghfH5wHALgAAAAA.Shyvana:BAAALAADCgEIAQAAAA==.Shâvow:BAAALAADCgcIDQAAAA==.Shéguey:BAAALAADCgYIDwAAAA==.Shéguèy:BAAALAADCgUIBQAAAA==.Shéguéy:BAAALAADCgYIBgAAAA==.',Si='Siammolow:BAAALAADCgYIBgAAAA==.Sifon:BAAALAADCgMIAwAAAA==.Silthys:BAAALAADCgYIEgAAAA==.',Sn='Snooplol:BAAALAADCgEIAQAAAA==.',So='Sokhar:BAAALAADCggIDAAAAA==.Sonum:BAAALAAECgMIBgAAAA==.Sosweet:BAAALAADCggICAAAAA==.',St='Staydead:BAAALAAECgMIBwAAAA==.Stayfocus:BAAALAADCgIIAgAAAA==.Stayføcus:BAAALAADCggICQAAAA==.Stayrosser:BAAALAADCggICQAAAA==.Staýfocus:BAAALAADCggICAAAAA==.Stepmommy:BAAALAAECgYIDgAAAA==.Stepson:BAAALAAECgYICAAAAA==.',Su='Subttle:BAAALAAECgQIBQAAAA==.Suzette:BAAALAADCggICAABLAAECgUIBwADAAAAAA==.',Sy='Sykae:BAAALAADCgcIDQAAAA==.',Ta='Takenudrood:BAAALAAECgIIAgAAAA==.Taoquan:BAAALAAECgYICQAAAA==.',Th='Theana:BAAALAADCgUIBQAAAA==.Thechassou:BAAALAADCgcIDAAAAA==.Thelaruuk:BAAALAADCggICgAAAA==.Thesys:BAAALAAECgMIAwAAAA==.Thetita:BAAALAADCggICAAAAA==.Theyoos:BAAALAADCgMIBQAAAA==.Thi:BAAALAADCggICAAAAA==.Thumbelina:BAAALAADCgIIAgAAAA==.Thélos:BAAALAADCgcIBwAAAA==.',Ti='Tileas:BAAALAADCgQIBAAAAA==.',To='Tombombadil:BAAALAADCggIEgAAAA==.Tonouille:BAAALAAECgYICwAAAA==.Totaïm:BAAALAAECgYIDgAAAA==.Tovah:BAAALAAECgcIFAAAAQ==.Toxiquorc:BAAALAAECgQICAAAAA==.',['Tü']='Tück:BAAALAADCgcIEQAAAA==.',Vi='Vilanna:BAAALAAECgQIBgAAAA==.Vincente:BAAALAADCggIEwAAAA==.Vitalia:BAAALAADCggICAAAAA==.',Vo='Volcâne:BAAALAADCggIFAAAAA==.Voxstar:BAAALAADCgUIBQAAAA==.',Vr='Vrtd:BAAALAADCgUIBQAAAA==.',['Vé']='Vésuve:BAEALAADCggIEwABLAAECgUICQADAAAAAA==.',Wi='Witargu:BAAALAADCgYIBgAAAA==.',Wo='Worëy:BAAALAAECgQIBgAAAA==.',Xo='Xorel:BAAALAADCggICAAAAA==.',Xz='Xzyllaly:BAAALAAECgIIAgAAAA==.',Yb='Ybor:BAAALAADCgUIBwAAAA==.',Za='Zacclamation:BAAALAADCggICAAAAA==.Zalcoolique:BAAALAADCgMIAwABLAADCggICAADAAAAAA==.',Ze='Zexceed:BAAALAADCggICAAAAA==.',Zg='Zgbell:BAAALAADCggIFwAAAA==.',Zu='Zultox:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end