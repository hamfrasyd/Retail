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
 local lookup = {'Mage-Frost','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','DeathKnight-Blood','Unknown-Unknown','Mage-Arcane','Paladin-Retribution','Shaman-Elemental','Shaman-Restoration','Monk-Brewmaster','Evoker-Devastation','Druid-Restoration','Monk-Mistweaver','Rogue-Assassination',}; local provider = {region='EU',realm="Khaz'goroth",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ag='Agaran:BAAALAAECgQIBgAAAA==.Agatlan:BAAALAADCggICAAAAA==.',Ak='Akkorn:BAAALAAECgYIDwAAAA==.Akoko:BAAALAAECgUIBwAAAA==.Akyô:BAAALAAECgMIBQAAAA==.',Al='Albedo:BAAALAAECgEIAQAAAA==.Alelia:BAAALAAECgMIBAAAAA==.Algonkin:BAAALAAECgYICAAAAA==.Alusru:BAAALAADCgMIAwAAAA==.Alyveth:BAAALAADCggICAAAAA==.',Am='Amazonprime:BAAALAADCgYIBgAAAA==.Amydala:BAAALAAECgMIAwAAAA==.',An='Andylatte:BAAALAAECgYICQAAAA==.Anilem:BAAALAADCggIFgAAAA==.Ankka:BAAALAAECgIIAgAAAA==.Anshy:BAAALAADCgUIBgAAAA==.',Ar='Arashi:BAABLAAECoEWAAIBAAcIgCAQBgCWAgABAAcIgCAQBgCWAgAAAA==.Arquilia:BAAALAADCggIFgAAAA==.Aryju:BAAALAADCgYIBgAAAA==.',As='Asroma:BAAALAAECgUIBwAAAA==.',At='Atariel:BAAALAADCggICAAAAA==.',Ay='Ayken:BAAALAAECgIIAgAAAA==.Aylene:BAAALAADCggIFwAAAA==.Ayoveda:BAAALAADCgcIBwAAAA==.',Ba='Balingar:BAAALAAECgQICAABLAAECgcIGAACAGwhAA==.Balthos:BAAALAADCggICAAAAA==.Bargor:BAAALAAECgMIBQAAAA==.Bargsh:BAAALAAECgMIBAAAAA==.Barrakuhda:BAAALAAECgUIBwAAAA==.',Be='Belshirasch:BAABLAAECoEUAAMDAAgIOx+wEgBjAgADAAgIOx+wEgBjAgAEAAMILA90PgCeAAAAAA==.Beratol:BAAALAADCgEIAQAAAA==.Bernhard:BAAALAADCggICAAAAA==.Bertolli:BAAALAAECgMIAwAAAA==.',Bi='Bibiana:BAAALAADCgcIDgAAAA==.Biffbaff:BAAALAAECgMIBQAAAA==.Binford:BAAALAAECgIIAgAAAA==.Bitanus:BAAALAADCggICQAAAA==.Bitcooin:BAAALAAECgIIAgAAAA==.',Bl='Blinck:BAAALAAECgYIDAAAAA==.Bloodboss:BAAALAADCgcIBwAAAA==.Bloodrave:BAAALAAECgMIBAAAAA==.',Bo='Bobjr:BAAALAADCgcIBgAAAA==.Boilíes:BAAALAAECgYIBgAAAA==.',Br='Brezelfrau:BAAALAAECgYICgAAAA==.Brille:BAAALAAECgcIDAAAAA==.Bron:BAAALAAECgMIAwAAAA==.Brothax:BAAALAAECgUIBwAAAA==.Brutalon:BAAALAAECggICAAAAA==.',Bu='Butterblume:BAAALAADCgYIBgAAAA==.',['Bí']='Bíbì:BAAALAAECgMIAwAAAA==.',Ca='Caesar:BAAALAAECgMIAwAAAA==.Caevyia:BAAALAADCgYIBgAAAA==.Calarí:BAAALAADCggIEAAAAA==.',Ce='Cersei:BAAALAAECgIIAgAAAA==.Cerya:BAAALAAECgcIDAAAAA==.',Ch='Chojî:BAAALAAECggICAAAAA==.',Ci='Cicutaviros:BAAALAADCgUIBQAAAA==.Ciphoria:BAAALAADCgIIAgAAAA==.',Co='Cool:BAAALAADCggIFgAAAA==.',Cr='Cresnik:BAAALAADCgYIBgAAAA==.Crownclown:BAAALAADCgMIAwAAAA==.Cruelbrew:BAAALAADCggIDwAAAA==.Crusadé:BAAALAAECgUIBwAAAA==.',Da='Daaria:BAAALAADCgYIBgAAAA==.Darasis:BAAALAAECgMIAwAAAA==.Darkivoker:BAAALAAECgYIDAAAAA==.Darkmask:BAAALAAECgYIDQAAAA==.',De='Deracty:BAAALAAECgMIBAAAAA==.Dergraue:BAAALAAECgEIAQAAAA==.Desmodiaa:BAAALAADCggIEAAAAA==.Deximo:BAAALAADCggIEwAAAA==.',Dj='Djánady:BAAALAAECgMIAwAAAA==.',Do='Dogath:BAAALAAECgcIEAAAAA==.Domihl:BAABLAAECoEXAAIFAAgItyUlAQB0AwAFAAgItyUlAQB0AwAAAA==.Donzar:BAAALAAECgYIDAAAAA==.Dotterpepper:BAAALAAFFAIIAgAAAA==.',Dw='Dwahe:BAAALAADCggIDwAAAA==.',['Dä']='Dämonjägerin:BAAALAAECgMIBQAAAA==.Däumeling:BAAALAADCggIFgAAAA==.',Ec='Eclipsae:BAAALAADCggICAAAAA==.',Eg='Eggssqueezer:BAAALAADCggIFwAAAA==.Egor:BAAALAAECgIIAwAAAA==.',El='Elarwyn:BAAALAADCggICAAAAA==.Eliaflo:BAAALAADCggICAAAAA==.Eloe:BAAALAADCgYIBgAAAA==.Elundir:BAAALAAECgEIAQAAAA==.',Em='Empty:BAAALAADCgcIEAAAAA==.',Es='Esariel:BAAALAADCggICAAAAA==.Estirella:BAAALAAECgQICAAAAA==.',Fa='Faelis:BAAALAADCgEIAQAAAA==.Farah:BAAALAADCggIDwAAAA==.',Fe='Feedy:BAAALAAECgMIBAAAAQ==.Feigndeath:BAAALAAECgYIDgAAAA==.Fellpfötchen:BAAALAAECgEIAQAAAA==.',Fi='Firesmither:BAAALAADCgEIAQAAAA==.',Fj='Fjölnir:BAAALAADCggICAABLAAECggIFwAGAEkYAA==.',Fl='Flitzablitza:BAAALAADCggIEAAAAA==.Floryel:BAAALAAECgYIBgAAAA==.Fluffeline:BAAALAAECgEIAQAAAA==.',Fo='Fosja:BAAALAAECgcIEAAAAA==.',Fr='Frieren:BAAALAAECgYICwAAAA==.',Fy='Fyneman:BAAALAADCgQICAABLAAECgcIEAAHAAAAAA==.',['Fû']='Fûßel:BAAALAADCgcIBwAAAA==.',Ga='Gazoz:BAAALAADCgYIDAAAAA==.',Ge='Geîßlêr:BAAALAADCgYIBgAAAA==.',Gh='Ghorinchai:BAAALAAECgUIBwAAAA==.Ghostlord:BAAALAADCgEIAQAAAA==.',Gl='Glazed:BAAALAADCgYIBgAAAA==.',Go='Gorgonax:BAAALAAECgYICwAAAA==.',Gr='Grandel:BAAALAAECgYIDgAAAA==.Grantel:BAABLAAECoEZAAIIAAcI3R0xHwApAgAIAAcI3R0xHwApAgAAAA==.Greenhornetx:BAAALAADCggICAAAAA==.Greyfox:BAAALAAECgIIAgAAAA==.Griimmjow:BAAALAADCgEIAQAAAA==.Grondarn:BAAALAADCggIFgAAAA==.',Gu='Guccidruid:BAAALAADCggICwAAAA==.Guillaume:BAAALAAECgQIBgAAAA==.Gumble:BAAALAADCgcIBwAAAA==.',Gw='Gwynny:BAAALAAECgYIBgAAAA==.',Ha='Halríon:BAAALAADCgcIBwAAAA==.Hanse:BAAALAAECgMIBwAAAA==.Harope:BAAALAAECgUIBwAAAA==.',He='Heilixblechl:BAAALAAECggICwAAAA==.Heinzstoff:BAAALAAECgMIAwAAAA==.Hexana:BAAALAAECgIIBAAAAA==.',Hi='Hitatshi:BAAALAAECgIIAgAAAA==.',Ho='Hobb:BAAALAAECgYICwAAAA==.Horat:BAAALAAECgYICAAAAA==.',Ig='Igñaz:BAAALAADCgcIBwABLAAECgcIEAAHAAAAAA==.',Im='Imreg:BAABLAAECoEYAAICAAcIbCG9CwCbAgACAAcIbCG9CwCbAgAAAA==.',In='Ingobräu:BAAALAADCggIGAAAAA==.',Io='Iolan:BAAALAAECgcIDwAAAA==.',Ir='Ireth:BAAALAAECgYIDAAAAA==.',Iv='Ivanâ:BAAALAADCggIFQAAAA==.',Ja='Jabao:BAAALAADCggIEAAAAA==.Januschandra:BAAALAADCggICAAAAA==.Jazeerah:BAAALAAECgQIBgAAAA==.',Je='Jedsia:BAAALAAECgMIBQAAAA==.Jegor:BAAALAADCggICAAAAA==.Jenolix:BAAALAADCggICAAAAA==.',Jo='Jonny:BAAALAADCgcIBwAAAA==.Jormund:BAAALAAECgIIAgAAAA==.Josch:BAAALAADCgcIBwAAAA==.',Ju='Juppy:BAAALAADCggIFgAAAA==.',['Jä']='Jägno:BAAALAADCgcIEwAAAA==.',Ka='Kalakaman:BAAALAAECgUIBwAAAA==.Kalandris:BAAALAAECgYIDAAAAA==.Kalma:BAAALAADCgYICgAAAA==.Katryn:BAAALAAECgIIAgAAAA==.',Kh='Khalessi:BAAALAAECgMIBgAAAA==.Khazrak:BAAALAAECgcIEQAAAA==.',Ki='Killbienchen:BAAALAADCgYICgAAAA==.Killja:BAAALAAECgIIAgAAAA==.',Kl='Kleineflo:BAAALAAECgMIBQAAAA==.Klinura:BAAALAAECgcIDQAAAA==.',Ku='Kudelmudel:BAAALAADCgQIBQAAAA==.',Kv='Kvothé:BAAALAAECgYICQAAAA==.',Ky='Kynia:BAAALAADCgYIBgAAAA==.Kyora:BAAALAADCgYIBgAAAA==.Kyriè:BAACLAAFFIEFAAIJAAMItBEYCQChAAAJAAMItBEYCQChAAAsAAQKgRQAAgkACAjfIsUFAC4DAAkACAjfIsUFAC4DAAAA.',['Kî']='Kîmba:BAAALAAECgEIAQAAAA==.',['Kÿ']='Kÿra:BAAALAAECgMIBgAAAA==.',La='Lakotamoon:BAAALAAECgUIBwAAAA==.Lambda:BAAALAAECgIIAgAAAA==.Lanaa:BAAALAADCggIDgAAAA==.Laudat:BAAALAAECgMIBQAAAA==.',Le='Lerino:BAAALAADCgcIDAAAAA==.Levara:BAAALAADCgYIBgAAAA==.',Li='Lillibeth:BAAALAADCggIFgAAAA==.Lithzua:BAAALAADCgEIAQAAAA==.',Lu='Lumananti:BAABLAAECoEYAAIKAAgIIhBMGAAAAgAKAAgIIhBMGAAAAgAAAA==.Luzilla:BAAALAADCgYIBwAAAA==.',['Lò']='Lòdor:BAAALAAECgYICgAAAA==.',Ma='Maddrock:BAAALAAECgIIAgAAAA==.Maeya:BAAALAADCggIDgAAAA==.Maggye:BAAALAADCggIJAAAAA==.Mahoney:BAAALAAECgQIBAAAAA==.Maiko:BAABLAAECoEXAAMDAAgIJSEYBwD7AgADAAgIYyAYBwD7AgAEAAUIuxySGQC6AQAAAA==.Makirito:BAAALAAECgYICwAAAA==.Maleniia:BAAALAAECgYICQAAAA==.Marinat:BAAALAADCgcIDAAAAA==.Marvîn:BAAALAAECgEIAQAAAA==.',Mc='Mckaiver:BAAALAADCgcIDgAAAA==.',Me='Mekhet:BAAALAAECgEIAQAAAA==.Meliodas:BAAALAAECgYIDQAAAA==.Melokima:BAABLAAECoEUAAIIAAgIoB1bEACrAgAIAAgIoB1bEACrAgAAAA==.Merimmac:BAAALAADCggIDwAAAA==.',Mi='Midea:BAAALAADCgUIBQAAAA==.Miiezi:BAAALAAECgIIAgAAAA==.Miiggel:BAAALAAECgYICgAAAA==.Miiquella:BAAALAADCgYIBgAAAA==.Mimíru:BAAALAAECgQICAAAAA==.Minschi:BAAALAADCgYIBgAAAA==.Miracolie:BAAALAADCgQIBQAAAA==.Miyama:BAAALAAECgEIAQAAAA==.',Mj='Mjöll:BAABLAAECoEXAAIGAAgISRi4BQBLAgAGAAgISRi4BQBLAgAAAA==.',Mo='Mokkadin:BAAALAADCgQIBAAAAA==.',['Mì']='Mìssery:BAAALAADCgcICAAAAA==.',['Mí']='Mízumeh:BAABLAAECoEXAAILAAgICRV3HADoAQALAAgICRV3HADoAQAAAA==.',Na='Naid:BAAALAADCggIDAAAAA==.Namdrahil:BAAALAADCggICgAAAA==.Nanoc:BAAALAAECgYICAAAAA==.Narnos:BAABLAAECoEaAAIMAAgIKx7FAwC2AgAMAAgIKx7FAwC2AgAAAA==.Narthafelaer:BAAALAAECgQIBgAAAA==.',Ne='Nelija:BAAALAAECgcIDQAAAA==.Neliâ:BAAALAADCgcIBwAAAA==.Nerdanel:BAAALAAECgYIBgAAAA==.',Ng='Ngmui:BAAALAADCggIDwAAAA==.',Ni='Niva:BAAALAAECgMIBAAAAA==.',No='Notopmodel:BAAALAADCgcIBwAAAA==.Nowiel:BAAALAADCggIDwAAAA==.',Ny='Nycky:BAAALAADCggIFgAAAA==.',['Nâ']='Nârmôrâ:BAAALAAECgIIAgAAAA==.',['Nó']='Nórdig:BAAALAAECgIIAgAAAA==.',Ok='Okaninas:BAAALAAECgMIAwAAAA==.',Ol='Oldenburger:BAAALAADCgcICQAAAA==.',Op='Opiliones:BAAALAAECgMIAwAAAA==.',Pa='Paladimo:BAAALAAECgYICgAAAA==.Paldragon:BAABLAAECoEVAAINAAgIXySeAQBPAwANAAgIXySeAQBPAwAAAA==.Palmonk:BAAALAAECgYICgAAAA==.Palrob:BAAALAAECgIIAgAAAA==.Paly:BAAALAAECgEIAQAAAA==.Papitar:BAAALAADCgcIEwAAAA==.Pawny:BAABLAAECoEXAAIOAAgIxxP7EwDzAQAOAAgIxxP7EwDzAQAAAA==.Paymaster:BAAALAADCgcIBwAAAA==.',Po='Pokus:BAAALAAECgYIBwAAAA==.',Pr='Princartar:BAAALAAECgQIBAAAAA==.',Pu='Pups:BAAALAAECgYICAAAAA==.Puzzi:BAAALAADCggIFgAAAA==.',Qh='Qhuinnta:BAAALAADCggIDwAAAA==.',Qu='Quaigón:BAAALAADCgMIAwABLAAECggIGAAKACIQAA==.Quirin:BAAALAAECgYIDAAAAA==.Qumaira:BAAALAAECgEIAQAAAA==.',Ra='Rafinia:BAAALAAECgUICgAAAA==.Rahgam:BAAALAAECgUIBQAAAA==.Rantazía:BAAALAAECgMIBAAAAA==.Raxano:BAAALAAECggIBwAAAA==.',Re='Reckless:BAAALAADCggIDgAAAA==.Reez:BAAALAADCgYIBgAAAA==.Rekzi:BAAALAAECggICAAAAQ==.Renermo:BAAALAADCgUIBQAAAA==.',Ri='Riecka:BAAALAADCgcIDQAAAA==.Rigosmage:BAAALAAECggICAAAAA==.Rimá:BAAALAAECgMIBQAAAA==.Rishu:BAAALAADCggICAAAAA==.Rivendare:BAAALAAECgQICAAAAA==.',Ro='Robìn:BAAALAADCgQIBAAAAA==.Rogart:BAAALAAECgcIEAAAAA==.Roidheinz:BAAALAAECgYIBwAAAA==.Romuluss:BAAALAADCggICAAAAA==.Rotàr:BAAALAADCggICAABLAAECgcIEAAHAAAAAA==.Roódhooft:BAAALAADCgYICQAAAA==.',Ru='Rufega:BAAALAADCggIBwAAAA==.',Ry='Ryft:BAABLAAECoEVAAMEAAgIYyQJAQBTAwAEAAgIYyQJAQBTAwADAAII2iEvXQCmAAAAAA==.Ryftdh:BAAALAADCgYIBgABLAAECggIFQAEAGMkAA==.Ryftdk:BAAALAADCggICAABLAAECggIFQAEAGMkAA==.Ryouta:BAAALAADCgcIDAAAAA==.Ryzz:BAAALAAECgIIBgAAAA==.',Sa='Saalem:BAAALAAECgcIDQAAAA==.Salenya:BAAALAADCggIFAAAAA==.Saliva:BAAALAAECgMIBQAAAA==.Salvatôre:BAAALAADCgYICQAAAA==.Samarédariò:BAAALAAECggIEgABLAADCggICAAHAAAAAA==.',Sc='Schlafmütze:BAABLAAECoEWAAIPAAgIoxcuCQApAgAPAAgIoxcuCQApAgAAAA==.Schmobbit:BAAALAAECgYICAAAAA==.',Se='Sensî:BAAALAAECgYIBgAAAA==.Sentenza:BAAALAADCgcIBwAAAA==.Seraphiná:BAAALAAECgMIBQAAAA==.',Sh='Shadow:BAAALAAECggICgAAAA==.Shaminski:BAAALAAECgYICgAAAA==.Shamús:BAAALAADCgcIDQAAAA==.Sharold:BAAALAAECgMIBAAAAA==.Shayvin:BAAALAADCgIIAgABLAADCgYIBgAHAAAAAA==.Sheng:BAAALAAECgYIBgAAAQ==.',Si='Silivren:BAAALAAECgcIDQAAAA==.Sinavornul:BAAALAAECgMIBAAAAA==.Sinlila:BAAALAAECgYIBgAAAA==.',Sk='Skahr:BAAALAAECgUIBQAAAA==.Skillidan:BAAALAAECgcIDwAAAA==.',Sl='Sleimer:BAAALAAECgUIBwAAAA==.Slemmingen:BAAALAADCgYIBgAAAA==.',Sm='Smoke:BAAALAAECgYIBgAAAA==.',Sn='Snabbräv:BAAALAADCgcICAAAAA==.',So='Sodiac:BAAALAAECgMIBQAAAA==.Sonnaxt:BAAALAADCggIFgAAAA==.Soular:BAAALAADCggIDwAAAA==.',Sp='Spear:BAAALAADCgUIBQAAAA==.Spiritmoon:BAAALAAECgIIAgAAAA==.',St='Strubpel:BAAALAAECgYIDwABLAAECgYIDwAHAAAAAA==.Struppel:BAAALAADCggIEQABLAAECgYIDwAHAAAAAA==.Struppelmage:BAAALAADCggIFQAAAA==.Stryze:BAAALAAECgQIBAAAAA==.Stôrm:BAAALAADCgEIAQAAAA==.',Sy='Synoumdk:BAAALAADCgQIBAAAAA==.',['Sà']='Sàly:BAAALAADCggIGAAAAA==.',['Sâ']='Sâlyria:BAAALAAECgMIBwAAAA==.Sângân:BAAALAADCgQIBAAAAA==.',['Sî']='Sîndy:BAAALAAECgMIBwAAAA==.',Ta='Tamós:BAAALAAECgIIAQAAAA==.Tareya:BAAALAAECgcIEAAAAA==.Tatsu:BAAALAAECgUIBwAAAA==.',Te='Temeraire:BAAALAAECgEIAQAAAA==.Terranof:BAAALAADCgEIAQAAAA==.Teteia:BAAALAAECgQICAAAAA==.',Th='Thurs:BAAALAAECgYIBgAAAA==.Thôros:BAAALAADCgMIAwAAAA==.',Tj='Tjalf:BAAALAADCggICAAAAA==.Tjone:BAAALAAECgMIBAAAAA==.',To='Toxicslayer:BAAALAADCggICAAAAA==.',Tr='Tratôss:BAAALAADCggICAAAAA==.Trazyn:BAAALAAECgMIAwAAAA==.Tristesse:BAAALAAECgEIAQAAAA==.',Ty='Tyrøck:BAAALAAECgYICAAAAA==.',Tz='Tzana:BAAALAAECgIIBAAAAA==.',Ve='Velari:BAAALAAECgEIAQAAAA==.Venómi:BAAALAADCggIDwAAAA==.Veylor:BAAALAAECggICAAAAA==.',Vi='Vitalivoid:BAAALAADCggIFQAAAA==.',Vo='Voidstabberx:BAAALAADCggIFgAAAA==.Vorlord:BAAALAADCgQIBAAAAA==.',Vu='Vuridan:BAAALAAECgYICwAAAA==.',Vy='Vykos:BAAALAAECgcIEAAAAA==.Vyna:BAAALAADCgcIDAABLAAECggIFwAQANwiAA==.',['Vä']='Västeräs:BAAALAADCgYIBgAAAA==.',Wa='Walkingend:BAAALAADCgIIAgAAAA==.Walpri:BAAALAAECgUICAAAAA==.',We='Weezy:BAAALAAECgMIBAAAAA==.Wern:BAAALAADCgMIAwAAAA==.',Xa='Xanty:BAAALAADCgQIBAAAAA==.Xarfei:BAAALAADCggIFAABLAAECggIFAADADsfAA==.',Xi='Ximerâ:BAAALAAECgEIAQAAAA==.',Xy='Xya:BAABLAAECoEXAAIQAAgI3CJGAgA0AwAQAAgI3CJGAgA0AwAAAA==.',['Xá']='Xálius:BAAALAAECgUICQAAAA==.',Ya='Yanê:BAAALAADCgcIBwAAAA==.',Yi='Yingyâng:BAAALAADCgcIBwABLAAECgcIEAAHAAAAAA==.',Yo='Yokai:BAAALAADCggIEQAAAA==.Yokozuna:BAAALAADCgcIAwAAAA==.',Yu='Yui:BAAALAADCgIIAgAAAA==.',Yv='Yvionstraza:BAAALAAECgIIAwAAAA==.',Za='Zaladríel:BAAALAADCgQIBAAAAA==.Zana:BAAALAADCgYIBgABLAAECgIIBAAHAAAAAA==.Zanla:BAAALAADCggIFgABLAAECgIIBAAHAAAAAA==.Zarøn:BAAALAAECgEIAQAAAA==.',Zi='Zibbi:BAAALAADCgMIAwAAAA==.',Zo='Zod:BAAALAAECgUIBwAAAA==.Zokrym:BAAALAAECgYICAAAAA==.Zorahnus:BAAALAAECgYICAAAAA==.',Zy='Zyô:BAAALAAECgYICQAAAA==.',['Æl']='Ælonis:BAAALAAECgMIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end