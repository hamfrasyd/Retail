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
 local lookup = {'Druid-Balance','DemonHunter-Havoc','Unknown-Unknown','Druid-Guardian','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Priest-Holy','Shaman-Restoration','Shaman-Elemental','Warrior-Fury',}; local provider = {region='EU',realm='ConfrérieduThorium',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ac='Acuitédr:BAABLAAECoEUAAIBAAcIEx7kDABgAgABAAcIEx7kDABgAgAAAA==.',Ad='Addîson:BAAALAADCgQIBAAAAA==.Adhaa:BAAALAADCggICAAAAA==.',Af='Afierte:BAAALAAECggIDQAAAA==.',Ag='Agaväen:BAAALAAFFAIIAgAAAA==.Agrât:BAABLAAECoEWAAICAAgIhSEKBwAWAwACAAgIhSEKBwAWAwAAAA==.',Ai='Airénshùshi:BAAALAADCgIIAgAAAA==.',Ak='Akarui:BAAALAADCgUIBQAAAA==.Akhileusdh:BAAALAAECgEIAQAAAA==.Akiru:BAAALAAECgMIBgAAAA==.',Al='Alariel:BAAALAADCgUIBwAAAA==.Albereth:BAAALAADCgcIBwAAAA==.Allarya:BAAALAADCgYIBgABLAAECgYIBgADAAAAAA==.Allwhitte:BAAALAAECgYIBgAAAA==.Allya:BAAALAADCggICAABLAAECgYIDAADAAAAAA==.Almana:BAAALAADCgcIBwABLAADCggIEwADAAAAAA==.Aly:BAAALAADCggIFAAAAA==.',Am='Amaliaa:BAAALAAECgYICwAAAA==.Amandrà:BAAALAAECggICAAAAA==.Amphorea:BAAALAADCgQIBAAAAA==.',Ar='Arcandria:BAAALAAECgMIAwAAAA==.Ariié:BAAALAAECgMIAwAAAA==.Armadyl:BAAALAADCgcIBwAAAA==.Arrowfstørms:BAAALAAECgUICAAAAA==.Artemystel:BAAALAADCggIDwAAAA==.Arthia:BAABLAAECoEXAAIEAAgIcyNdAABHAwAEAAgIcyNdAABHAwAAAA==.Arîa:BAAALAADCggIEwAAAA==.',As='Asherah:BAAALAAECgMIBgAAAA==.Asmo:BAAALAAECgIIAgAAAA==.Astamage:BAAALAAFFAIIAwAAAA==.Astharoths:BAAALAADCggICQABLAAFFAIIAwADAAAAAA==.Astrome:BAABLAAECoEWAAIFAAgInB+dCwDSAgAFAAgInB+dCwDSAgAAAA==.',At='Athanora:BAAALAADCggIDwAAAA==.Athrelya:BAAALAADCggIFAAAAA==.Atronos:BAAALAAECgYIDQAAAA==.',Ay='Ayae:BAAALAADCgcIDgAAAA==.',Az='Azersdf:BAAALAADCgUIBQAAAA==.Azkyn:BAAALAAECgMIBQAAAA==.Azranail:BAAALAADCggICAAAAA==.',['Aê']='Aêly:BAAALAADCgcIBwAAAA==.',['Aë']='Aëlwynn:BAAALAADCgcICQAAAA==.',Ba='Balarane:BAAALAAECgYICgAAAA==.Balbî:BAAALAADCgQIBAAAAA==.Balgamor:BAAALAADCggICAAAAA==.Barth:BAAALAAECgYIDwAAAA==.Bartholomew:BAAALAADCggIDwABLAAECgYIDwADAAAAAA==.Bawlt:BAAALAAECgMIBQABLAAECgYICwADAAAAAA==.Bawltimor:BAAALAAECgYICwAAAA==.',Be='Beber:BAAALAAECgIIAgAAAA==.Becarus:BAAALAADCgcIBwAAAA==.Beelzesam:BAAALAADCgEIAQAAAA==.Beenøuz:BAAALAAECgIIBAAAAA==.Berethore:BAAALAADCgQIBQAAAA==.',Bl='Blancoau:BAAALAAECgMIBwAAAA==.Blankette:BAAALAADCgIIAgAAAA==.Blennorrhas:BAAALAADCgcIBwAAAA==.Blëssed:BAAALAAECgIIBAAAAA==.',Bo='Boralex:BAAALAAECgMIBwAAAA==.Borval:BAAALAADCgMIAwAAAA==.',Br='Brasylax:BAAALAADCggICAAAAA==.Breedühr:BAAALAADCgUIBQAAAA==.Brocélliande:BAAALAADCggICAAAAA==.Broqu:BAAALAAECgQICAAAAA==.',Bu='Bulasturu:BAAALAAECgYICgAAAA==.',Bw='Bwayan:BAAALAADCgEIAQAAAA==.',['Bé']='Bénédictiøn:BAAALAADCgMIAwAAAA==.',Ca='Calize:BAAALAADCggICwAAAA==.',Ce='Cerbére:BAAALAADCggICAAAAA==.',Ch='Chagou:BAAALAADCggIEwAAAA==.Chamilia:BAAALAADCggIDwAAAA==.Chaminny:BAAALAAECgMIBQAAAA==.Chandefleuve:BAAALAADCgcICgAAAA==.Charlîe:BAAALAAECgEIAgAAAA==.Chassequipeu:BAAALAADCgMIAwAAAA==.',Co='Cobrat:BAAALAADCgcIDQAAAA==.Colmart:BAAALAAECgEIAQAAAA==.Complaìnte:BAAALAAECgEIAgAAAA==.',Cr='Cranhanpodku:BAAALAADCgcIFAAAAA==.Craseux:BAAALAADCggIFAAAAA==.Crimewaves:BAAALAADCggIEQAAAA==.',Cy='Cyraei:BAAALAADCgcIBwAAAA==.',Da='Damexia:BAAALAAECgMIAgAAAA==.Dananshee:BAAALAADCgcICAAAAA==.',De='De:BAAALAADCgUIBQAAAA==.Deme:BAAALAAECgMIBgAAAA==.Demiecorne:BAAALAADCgcIBwAAAA==.Den:BAAALAAECgUIBQAAAA==.Deshamhar:BAAALAAECgYIBgAAAA==.Deuxdeqi:BAAALAADCgcIBwAAAA==.',Di='Difole:BAAALAAECgMIAwAAAA==.Dipio:BAAALAADCgcIDAAAAA==.Discretion:BAAALAAFFAMIAgAAAA==.Diter:BAAALAADCgcIDgAAAA==.Diurza:BAAALAADCgcIBwAAAA==.',Do='Dorsator:BAAALAAECggICwAAAA==.',Dr='Drachktar:BAAALAADCggIDwAAAA==.Drakedög:BAAALAAECgcIDgABLAAFFAQIBwAGAGgUAA==.Drazhoath:BAAALAAECgMIAwAAAA==.Droudix:BAAALAADCgYIBgAAAA==.Drunkfox:BAAALAAECgQIBwAAAA==.Dryknight:BAAALAAECgMIBgAAAA==.Drëa:BAAALAADCggICAAAAA==.Drøpsy:BAAALAAECggIEgAAAA==.',['Dø']='Dønsham:BAAALAADCgcIDAAAAA==.',Ea='Easywind:BAAALAAECgEIAQAAAA==.',Ef='Efreetul:BAAALAAECgMIBQAAAA==.',Eh='Ehma:BAAALAADCgQIBAAAAA==.',El='Elletank:BAAALAAECgIIAgAAAA==.Elone:BAAALAADCggICwAAAA==.Elpatron:BAAALAADCgMIAwAAAA==.Elysera:BAAALAAECgEIAgAAAA==.Elíae:BAAALAAECgMIBwAAAA==.',Em='Emeràld:BAAALAADCggIEgAAAA==.',En='Enëtary:BAAALAADCggICAAAAA==.',Er='Eraëldy:BAAALAAECgYIDgAAAA==.Erzza:BAAALAAECgYIDQAAAA==.',Es='Escalop:BAAALAAECgUICAAAAA==.Esthete:BAAALAAECgYICQAAAA==.',Ev='Evazur:BAAALAADCgEIAQAAAA==.Evolock:BAAALAAECgEIAQAAAA==.',['Eï']='Eïir:BAAALAAECgIIAgAAAA==.',Fa='Faràs:BAAALAAECgYIBwAAAA==.',Fe='Fendarion:BAAALAADCggICAAAAA==.',Fi='Filomene:BAAALAADCgcIDgAAAA==.Finsaë:BAAALAAECgIIBAAAAA==.',Fl='Flac:BAAALAADCgcIBwAAAA==.Flynnee:BAAALAADCgQIBQAAAA==.',Fr='Fragaria:BAAALAADCgYIBgAAAA==.Fredale:BAAALAAECgMIBAAAAA==.',Fu='Fufuloh:BAEALAAECggICAABLAAECggIDgADAAAAAA==.Fulohdh:BAEALAAECgEIAQABLAAECggIDgADAAAAAA==.Fulohunt:BAEALAAECggIDgAAAA==.',['Fâ']='Fâwn:BAAALAAECgIIAgAAAA==.Fââyyaa:BAAALAADCgUIBQAAAA==.',['Fé']='Félhun:BAAALAADCggIEAAAAA==.Féllyne:BAAALAADCggICAAAAA==.',['Fø']='Føùføù:BAAALAADCggIFwAAAA==.',Ga='Galorus:BAAALAAECgEIAQAAAA==.',Go='Goathrokk:BAAALAAECgYIBwAAAA==.Gorodrim:BAAALAADCggIDQAAAA==.',Gr='Grabtar:BAAALAAECgEIAQAAAA==.Gradzia:BAAALAADCggICAAAAA==.Grenn:BAAALAADCggIDwAAAA==.Greyson:BAAALAAECgYIBgAAAA==.Grita:BAAALAADCgQIBAAAAA==.Groaar:BAAALAADCgUIBQAAAA==.Grumir:BAAALAADCgcIBwAAAA==.',Gu='Gurzraki:BAAALAADCgYIBgAAAA==.',['Gó']='Góld:BAAALAAECgMIAwAAAA==.',['Gõ']='Gõrtke:BAAALAADCggICAAAAA==.',['Gö']='Göld:BAABLAAFFIEHAAMGAAQIaBScAABaAQAGAAQIKxOcAABaAQAHAAIIDRViBgCXAAAAAA==.',Ha='Hafthør:BAAALAAECgcIBwAAAA==.Hastings:BAAALAADCgcIBwAAAA==.',He='Hemyc:BAAALAADCggIEQAAAA==.Herah:BAAALAADCggICAAAAA==.',Hi='Hironeiden:BAAALAAECgEIAQAAAA==.',Ho='Hopale:BAAALAADCgUIBQAAAA==.Hoshiyo:BAAALAADCggICwAAAA==.',Hu='Hudren:BAAALAADCgIIAgAAAA==.',Hy='Hyles:BAAALAADCgUIBQAAAA==.',['Hø']='Hølycøw:BAAALAAECgEIAQAAAA==.Hørriblette:BAAALAADCggIHAAAAA==.',Ic='Icàriam:BAAALAAECgcIDQAAAA==.',Il='Illuminäety:BAAALAADCgcIBwAAAA==.Illïad:BAAALAAECgQIBAAAAA==.',In='Inarï:BAAALAAECgIIAgAAAA==.',Ir='Iridiensse:BAAALAAECgEIAQAAAA==.Irøq:BAAALAADCgcIBwAAAA==.',Iv='Ivalys:BAAALAADCggIDgAAAA==.',Iw='Iwasan:BAAALAADCgYIBgAAAA==.Iwashan:BAAALAADCgcIBwAAAA==.',Ji='Jinwoo:BAAALAAECgcIDgABLAAFFAYIDQAIAAAbAA==.Jinwøø:BAACLAAFFIENAAMIAAYIABtmAABMAgAIAAYIABtmAABMAgAJAAEItR0SCQBcAAAsAAQKgRQAAwgACAjKISwFAA8DAAgACAjKISwFAA8DAAoAAQiRIBckAGMAAAAA.',Ka='Kaladjin:BAAALAADCgcIBwAAAA==.Kallÿ:BAAALAADCgcIBwAAAA==.Karm:BAAALAADCgcIDgAAAA==.Karsham:BAAALAADCggIDgAAAA==.Kaîzen:BAAALAADCgcIBwAAAA==.',Ke='Ketheru:BAAALAAECgQIBQAAAA==.',Ki='Kihrin:BAAALAAECgIIAwAAAA==.Kirjava:BAAALAADCgcIBwAAAA==.Kiro:BAAALAADCgcIBwAAAA==.Kirothius:BAAALAADCgcIDAAAAA==.',Kl='Klaatu:BAAALAADCgcIDwAAAA==.Klåus:BAAALAAECgIIBAAAAA==.',Ko='Koa:BAAALAADCggICAAAAA==.Kohor:BAAALAADCgQIBAAAAA==.Koniak:BAAALAAECgEIAQAAAA==.Kormgor:BAAALAADCgUICAAAAA==.',Kr='Kreustian:BAAALAAECgYICgAAAA==.',Ku='Kudix:BAAALAADCggICQAAAA==.Kurrama:BAAALAAECgMIBAAAAA==.',Kw='Kwicky:BAAALAAECgMIBwAAAA==.',Ky='Kylana:BAAALAADCgcIBwAAAA==.Kyodh:BAAALAAECgYICAABLAAFFAYIDQAIAAAbAA==.Kysail:BAAALAADCgYIBgAAAA==.Kysoke:BAAALAAECgcIDQAAAA==.',La='Lasagna:BAAALAAECgIIAgAAAA==.',Le='Lecter:BAAALAADCgcIBwAAAA==.Letitgo:BAABLAAECoEUAAILAAgIUyQOAQBVAwALAAgIUyQOAQBVAwAAAA==.',Lh='Lhanzu:BAAALAADCgYIBgAAAA==.',Li='Lianzo:BAAALAADCgcIBwAAAA==.Liliana:BAAALAADCggIDgAAAA==.Lililarousse:BAAALAADCgcIDgAAAA==.Linoas:BAAALAADCgYICwAAAA==.Linreeya:BAAALAAECgQICAAAAA==.Linyë:BAAALAAECgMIAwAAAA==.Liriel:BAAALAADCgcIBwAAAA==.',Lo='Lolatora:BAAALAADCggIDwAAAA==.',Lu='Lucifera:BAAALAADCgUIBQAAAA==.Lunaewen:BAAALAADCggIEAAAAA==.Lunëa:BAAALAAECgEIAQAAAA==.',Ly='Lyara:BAAALAAECgIIAwAAAA==.Lysapriest:BAAALAAFFAIIAgAAAA==.',['Lé']='Léynia:BAAALAADCggICgAAAA==.',['Lë']='Lëtharion:BAAALAAECgYIBgAAAA==.',['Lí']='Línoù:BAAALAADCgcIBwAAAA==.',['Lî']='Lîlith:BAAALAAECgIIAgAAAA==.',['Lø']='Lønfor:BAAALAAECgMIAwAAAA==.',Ma='Mahbit:BAAALAAECgMIBgAAAA==.Malith:BAAALAADCgMIAwAAAA==.Maltack:BAAALAAECgMIBQAAAA==.Maléfika:BAAALAADCgQIBAAAAA==.Manabu:BAAALAAECgcIDQAAAA==.Manatiomé:BAAALAADCgcICgAAAA==.Manekalma:BAAALAAECgQICAAAAA==.Massella:BAAALAADCggICgAAAA==.Matine:BAAALAAECgYICgAAAA==.Maugraîne:BAAALAADCggIDAAAAA==.Maulie:BAAALAAECgYIBgAAAA==.Maybel:BAAALAADCggIFAAAAA==.Mayü:BAABLAAECoEXAAIMAAgIUAB6UABvAAAMAAgIUAB6UABvAAAAAA==.Maë:BAAALAADCgQIBAAAAA==.Maëz:BAAALAADCggICAAAAA==.',Me='Meoleo:BAAALAAECgMIAwAAAA==.Merewen:BAAALAAECgUICAAAAA==.Merveilles:BAAALAAECgMIAwAAAA==.Mexxa:BAAALAADCgUIBgAAAA==.',Mh='Mhorphéus:BAAALAADCggIEAAAAA==.',Mi='Mistalova:BAAALAADCggIEAABLAAFFAQIBwAGAGgUAA==.',Mo='Moiranne:BAAALAADCggIFgAAAA==.Morgonn:BAAALAADCgcICQAAAA==.Mortels:BAAALAADCgIIAgAAAA==.',Mu='Multypass:BAAALAADCgcIBwAAAA==.',['Mï']='Mïnerve:BAAALAADCgcIDQAAAA==.',['Mø']='Møkati:BAAALAADCgcIDQAAAA==.',Na='Nagenda:BAAALAADCggICAAAAA==.Naliana:BAAALAAECgEIAQAAAA==.Nalrot:BAAALAADCggIDwAAAA==.Nargrim:BAAALAADCgUIBQAAAA==.Nashala:BAAALAADCggICAAAAA==.Naveis:BAAALAAECgUICAAAAA==.Nawopal:BAAALAAECgYICgABLAAECgYIEgADAAAAAA==.Nayram:BAAALAAECgYIDwAAAA==.Naÿram:BAAALAADCggICAABLAAECgYIDwADAAAAAA==.',Ne='Neilammar:BAAALAADCgQIBAAAAA==.Neyliel:BAAALAADCggICQAAAA==.',Ni='Niamorcm:BAAALAADCgcICAAAAA==.Ninougat:BAAALAADCgcICwAAAA==.Nisskorn:BAAALAADCggICAAAAA==.',No='Noklë:BAAALAAECgYIDwAAAA==.Nonobbzh:BAAALAAECgMIBgAAAA==.',Nu='Nukâ:BAAALAADCgcIDgAAAA==.',Ny='Nykypala:BAAALAAECgcIDQAAAA==.',['Ná']='Náte:BAAALAADCgYIBgABLAAECgYIEgADAAAAAA==.Nátte:BAAALAADCggIEAABLAAECgYIEgADAAAAAA==.',['Në']='Nëphthÿs:BAAALAAECgEIAQAAAA==.',Ok='Oku:BAAALAADCgYIBgAAAA==.',Ol='Olkerdys:BAAALAADCggICAAAAA==.',Op='Oppalïa:BAAALAADCggIFAAAAA==.',Or='Oranis:BAAALAAECgIIBQAAAA==.Orenyshi:BAAALAADCgQIBAAAAA==.',Os='Oscarnak:BAAALAADCgcIDgAAAA==.',Ou='Oupsïtv:BAAALAAFFAIIAgAAAA==.',['Oï']='Oïron:BAAALAAECgQIAwAAAA==.',Pa='Padar:BAAALAADCggIFAAAAA==.Paperheal:BAAALAAECgEIAQAAAA==.Papÿ:BAAALAAECgMIBAAAAA==.Pariàh:BAAALAADCggIEAAAAA==.',Pe='Pewnáte:BAAALAAECgYIEgAAAA==.Peyo:BAAALAAECgcIDAAAAQ==.',Ph='Phoènix:BAAALAAECgUICQAAAA==.Phèdres:BAAALAAECgIIAgAAAA==.',Pi='Piwinator:BAAALAADCggICAAAAA==.',Pl='Plezal:BAAALAADCgMIAwAAAA==.',Po='Polosis:BAAALAADCgMIAwAAAA==.',Pr='Prismatica:BAAALAAECgEIAQAAAA==.',Ps='Psychô:BAAALAADCggIFwAAAA==.',Pu='Putrasse:BAAALAAECgYIBgABLAAECggIFAALAFMkAA==.Putrius:BAAALAAECgEIAQAAAA==.',['Pí']='Píwa:BAAALAADCgcIDQAAAA==.',Ra='Rallena:BAAALAAECggIDAAAAA==.Ramonetou:BAAALAADCgYICwAAAA==.Razanon:BAAALAAECgMIAwAAAA==.Razgriz:BAAALAAECgIIAwAAAA==.Razurios:BAAALAADCgcICQAAAA==.Razâkh:BAAALAADCgQIBAAAAA==.',Re='Redwh:BAAALAAECgMICAAAAA==.Rentao:BAAALAADCggIDgABLAAECgMIBQADAAAAAA==.Reînhär:BAAALAADCgEIAQAAAA==.',Ro='Robindéboite:BAAALAADCgcIFQAAAA==.',['Rä']='Rägnärok:BAAALAADCgcIDQAAAA==.',['Ré']='Rémî:BAAALAADCgEIAQAAAA==.Rémï:BAAALAAECgYIBgAAAA==.',Sa='Sabbath:BAAALAADCgYIBgAAAA==.Saious:BAEALAADCgcICQAAAA==.Sangtelle:BAAALAAECgMIBQAAAA==.Santoline:BAAALAAECgIIAgAAAA==.Sardyne:BAAALAADCgcIBwAAAA==.Sarfest:BAAALAADCgYIBgAAAA==.Saskuacht:BAAALAADCggICAAAAA==.',Se='Seditmonk:BAAALAADCgcIDgAAAA==.Segojan:BAAALAAECgIIBQAAAA==.Seir:BAAALAAECgYICgAAAA==.Serenity:BAAALAADCgYICAAAAA==.Setsunà:BAAALAAECgIIAwAAAA==.Severina:BAAALAADCgcIBwABLAAECgMIBQADAAAAAA==.Seyrarm:BAAALAADCggICAAAAA==.',Sh='Shemz:BAABLAAECoEXAAMNAAgI8xsLDABiAgANAAgI8xsLDABiAgAOAAYIzRkCHwC7AQAAAA==.Shenlee:BAAALAADCgMIAwAAAA==.Shira:BAAALAADCgcIBwAAAA==.Shungate:BAAALAAECggIEQAAAA==.Shuryo:BAAALAAECgMIBQAAAA==.Shêld:BAAALAADCgcIBwAAAA==.Shïnai:BAAALAAECgIIAgAAAA==.',Sm='Smookie:BAAALAADCgcIBwAAAA==.',So='Sorbed:BAAALAADCgIIAgAAAA==.Soufflemort:BAAALAAECgIIAgAAAA==.',Sp='Spacemiaou:BAAALAAECgIIAgAAAA==.',Ss='Ssolock:BAAALAAFFAEIAQAAAA==.',St='Staberky:BAAALAADCggIDwAAAA==.Stanhopea:BAAALAADCgIIAgAAAA==.Starski:BAAALAADCgYIBgABLAAECgUICAADAAAAAA==.Stiich:BAAALAADCgcICgAAAA==.Stress:BAAALAAECgcIEQAAAA==.',Sw='Sweetzer:BAAALAAECgYIDgAAAA==.Swöôp:BAAALAADCgMIAwAAAA==.',Sy='Sylphilia:BAAALAAECgEIAQAAAA==.Sylvranas:BAAALAADCgYIBgAAAA==.Syrnie:BAAALAAECgEIAgAAAA==.',['Sé']='Sébastien:BAAALAADCgcIDwAAAA==.Sédatîîf:BAAALAADCgcIBwAAAA==.',['Sï']='Sïndarîn:BAAALAADCgcIBwAAAA==.',['Sø']='Sølomonkane:BAAALAADCggIFQAAAA==.',Ta='Taarna:BAAALAAECgYIDQABLAAFFAMIAgADAAAAAA==.Talcö:BAAALAADCgYIBwAAAA==.Talullâh:BAAALAADCggICAAAAA==.Tampaxxe:BAAALAADCggIEAAAAA==.Tass:BAAALAADCgIIAwAAAA==.Taverniertv:BAABLAAECoEUAAIPAAcIxyC6DACfAgAPAAcIxyC6DACfAgAAAA==.',Te='Tehupoo:BAAALAAECgEIAQAAAA==.Tenval:BAAALAADCgIIAgAAAA==.Teuffa:BAAALAAECgIIAgAAAA==.Teushiba:BAAALAAECgIIBAAAAA==.Teyko:BAAALAAECgIIAgAAAA==.',Th='Thebosspekor:BAAALAADCgUIBQAAAA==.Thenoobatorr:BAAALAADCggICAAAAA==.Thhorr:BAAALAADCgYIDwAAAA==.Thuzrin:BAAALAAECgIIAgAAAA==.Thànøs:BAAALAAECgEIAgAAAA==.Thörald:BAAALAAECgcIDQAAAA==.',Ti='Tialmère:BAAALAADCggICAAAAA==.',To='Tozi:BAAALAAECgYIDAAAAA==.Toøk:BAAALAADCgMIAwAAAA==.',Tr='Trena:BAAALAAFFAMIAgAAAA==.',Ty='Tyséria:BAAALAADCggIFgAAAA==.',['Tê']='Têyla:BAAALAADCggIDgAAAA==.',Ui='Uialwen:BAAALAADCggICAAAAA==.',Um='Umbrozae:BAAALAAECgEIAgAAAA==.Umpä:BAAALAADCgQIBAAAAA==.',Va='Vaelune:BAAALAAECgEIAQAAAA==.Valanice:BAAALAAECgYICAABLAAECgYIDgADAAAAAA==.Vassily:BAAALAAECgUICAAAAA==.Vava:BAABLAAECoEYAAMOAAgIgCQoCADdAgAOAAcIZyQoCADdAgANAAEIiA+5fAA2AAAAAA==.Vavâ:BAAALAADCggICAAAAA==.',Ve='Venatorix:BAAALAADCgEIAQAAAA==.',Vo='Voldusyn:BAAALAADCgEIAQAAAA==.Volkillos:BAAALAADCgQIBAAAAA==.Voltigeurs:BAAALAADCgcIBwAAAA==.Volurgin:BAAALAAECgQIBQAAAA==.Vone:BAAALAADCggIFwAAAA==.',Vr='Vraxen:BAAALAAECgIIAgAAAA==.',Vy='Vyelnarys:BAAALAAECgUIBQAAAA==.',Wa='Wahzgul:BAAALAADCgcIBwAAAA==.Waltaras:BAAALAAECgQIBAAAAA==.Wavÿ:BAAALAADCgQIBAAAAA==.',Wh='Whiterabbit:BAAALAADCgMIAgAAAA==.',['Wó']='Wólf:BAAALAADCgcIBwABLAAFFAQIBwAGAGgUAA==.',Xa='Xaltanis:BAAALAADCgEIAQAAAA==.',Xe='Xertis:BAAALAAECgQIBAAAAA==.',Xi='Xipam:BAAALAAECgcIDgAAAA==.',Xy='Xyanaa:BAAALAAECgMIBgAAAA==.Xyle:BAAALAADCgMIAwAAAA==.',Ya='Yakjzak:BAAALAAECgMIBAAAAA==.',Yl='Ylvicî:BAAALAAFFAEIAQAAAA==.',Yn='Ynferia:BAAALAAECgYIBgAAAA==.',Yv='Yvalys:BAAALAADCgcIDwABLAADCggIDgADAAAAAA==.',Yz='Yza:BAAALAAFFAIIAgAAAA==.',['Yö']='Yöba:BAAALAAECgIIAgAAAA==.',Za='Zaely:BAAALAADCgMIBAAAAA==.Zahely:BAAALAAECgIIAgAAAA==.Zangddar:BAAALAAECgEIAQAAAA==.',Ze='Zegvor:BAAALAAECgcIEQAAAA==.Zeldala:BAAALAADCggIFgAAAA==.Zeldoris:BAAALAADCgEIAQABLAAECgEIAQADAAAAAA==.Zetick:BAAALAAECgUIBQAAAA==.Zewielle:BAAALAAECgYIBgAAAA==.',Zo='Zoe:BAAALAAECgIIBAAAAA==.',Zu='Zulgart:BAAALAAECgMIAwAAAA==.',Zz='Zzaegir:BAAALAAECgcIDwAAAA==.Zzeimdall:BAAALAAECgYIDAABLAAECgcIDwADAAAAAA==.',['Zè']='Zèll:BAAALAAECgQIBAABLAAECgUIBQADAAAAAA==.',['Zé']='Zéravas:BAAALAADCgEIAQAAAA==.',['Zë']='Zëlfk:BAAALAADCgYIBwAAAA==.',['Ân']='Ângêls:BAAALAADCggIEgAAAA==.',['Ãx']='Ãxreder:BAAALAAECgYICwAAAA==.',['Äz']='Äzell:BAAALAAECgYIDAAAAA==.',['Ða']='Ðalania:BAAALAADCgUIBQAAAA==.Ðamédia:BAAALAAECgIIAgAAAA==.',['Öl']='Öllïe:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end