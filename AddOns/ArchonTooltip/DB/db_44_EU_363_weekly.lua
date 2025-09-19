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
 local lookup = {'Shaman-Elemental','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Rogue-Assassination','Mage-Arcane','Mage-Fire','Mage-Frost','Paladin-Protection','Paladin-Retribution','Priest-Discipline','Shaman-Restoration','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Feral',}; local provider = {region='EU',realm='CultedelaRivenoire',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abaddøn:BAAALAAECgEIAQAAAA==.',Ad='Adalyne:BAAALAADCgYIBgAAAA==.Adrastée:BAAALAADCggICAAAAA==.',Ai='Airyn:BAAALAADCgEIAQAAAA==.',Al='Alenzanar:BAAALAADCggIEgAAAA==.',Am='Amystra:BAAALAAECgcIEAAAAA==.',An='Angarrøs:BAAALAAFFAIIAgAAAA==.Anthrias:BAAALAAECgIIBAAAAA==.',Ap='Apocalypse:BAAALAAECggIDgAAAA==.',Ar='Archyna:BAAALAAECgMIBQAAAA==.Archéoptérix:BAAALAAECgQIBwAAAA==.Argaliade:BAAALAADCgcICAAAAA==.Arihotter:BAAALAAECgYICAAAAA==.Arinix:BAAALAAECgYIDwAAAA==.Arì:BAAALAADCgYIBwAAAA==.',As='Ashkä:BAAALAAECgIIAwAAAA==.Asrai:BAAALAAECgIIAgAAAA==.Astador:BAABLAAECoEXAAIBAAgITSVQAQBtAwABAAgITSVQAQBtAwAAAA==.',At='Athanael:BAAALAAECgYIBwAAAA==.Athinia:BAAALAADCgYICQAAAA==.',Au='Aurthelëa:BAAALAADCgMIBAAAAA==.',Aw='Awaiken:BAAALAADCggICAAAAA==.',Ba='Bahadoraan:BAAALAADCggICAAAAA==.Bahru:BAAALAAECgIIAgAAAA==.Baldurn:BAAALAAECgMIAwAAAA==.',Be='Beanbag:BAAALAADCgUIBQABLAAECgQICgACAAAAAA==.Behelit:BAAALAADCggICAABLAAECgQIBAACAAAAAA==.Belfynae:BAAALAADCggICAAAAA==.',Bi='Bilow:BAAALAADCgYIDAAAAA==.Biniouche:BAAALAAECgQICgAAAA==.',Bj='Björnden:BAAALAADCgIIAgAAAA==.',Bl='Blamethemonk:BAAALAADCgcIDgABLAADCgcIDwACAAAAAA==.',Bo='Boolvezoon:BAAALAADCggIDQAAAA==.Boubours:BAAALAADCgMIAwAAAA==.',Br='Brook:BAAALAADCgEIAQAAAA==.',['Bë']='Bëlk:BAAALAADCgcICgAAAA==.',Ca='Cayn:BAAALAADCgEIAQABLAADCgIIAgACAAAAAA==.',Ch='Chamalgame:BAAALAADCgMIBgABLAAECgMIBQACAAAAAA==.Chassemax:BAAALAADCgMIAwAAAA==.Chaøstheøry:BAAALAAECgEIAQAAAA==.Chenoas:BAAALAADCggICAAAAA==.Chouaky:BAAALAADCgcICwAAAA==.',Ck='Ckrom:BAAALAADCgYIBwAAAA==.Ckromn:BAAALAADCgcIDAAAAA==.',Cl='Clerica:BAAALAADCgcIBwAAAA==.Cloro:BAAALAADCgMIBQAAAA==.Cléô:BAAALAAECgIIBAAAAA==.',Cr='Crodh:BAAALAADCggIDwAAAA==.Cronass:BAABLAAECoEYAAQDAAgI4yStAQBeAwADAAgI4yStAQBeAwAEAAMIExzwEwD6AAAFAAEI/BmDTwBHAAAAAA==.',Cy='Cyrosee:BAAALAAECgYIDwAAAA==.',['Cé']='Célestinette:BAAALAAECgIIAwAAAA==.',Da='Dalbafer:BAAALAAECgcICgAAAA==.Dalinar:BAAALAADCgcIDwAAAA==.',De='Deathkermy:BAAALAAECgIIAwAAAA==.Dess:BAAALAAECgYIDwAAAA==.',Dh='Dhanvatari:BAAALAADCggICAABLAAECgYICQACAAAAAA==.Dhanvatarî:BAAALAAECgQIBgABLAAECgYICQACAAAAAA==.Dharnam:BAABLAAECoEYAAIGAAgIsCCnBQDmAgAGAAgIsCCnBQDmAgAAAA==.Dhänvatari:BAAALAAECgYICQAAAA==.',Di='Diazépam:BAAALAADCggICAAAAA==.Divy:BAAALAADCggIDwAAAA==.Dixvy:BAAALAADCgcICAABLAADCggIDwACAAAAAA==.',Dk='Dköre:BAAALAAECggIDQAAAA==.',Do='Dorka:BAAALAAECgYIDwAAAA==.Dothunderr:BAAALAADCgQIBAAAAA==.',Dr='Dreystïe:BAAALAAECgMIBAAAAA==.Drosera:BAAALAADCgIIAgAAAA==.Drøody:BAAALAAECgMIBQAAAA==.',Du='Durandal:BAAALAAECgIIAgAAAA==.',Ef='Efique:BAAALAAECgQIBwAAAA==.',El='Eldrytch:BAAALAADCgIIAgAAAA==.Elunael:BAAALAAECggIEQAAAA==.Elzen:BAAALAAECgIIAgAAAA==.',En='Eniryphen:BAAALAADCgcICAAAAA==.',Er='Eracta:BAAALAAECgYICwAAAA==.Ergolias:BAAALAAECgIIAwAAAA==.',Et='Etrinnøxe:BAAALAADCgIIAgAAAA==.',Ev='Evermoon:BAAALAADCggICQAAAA==.',Fa='Fanttom:BAAALAADCgcIEgAAAA==.Faricha:BAAALAAECgIIAgAAAA==.',Fr='Friketta:BAAALAAECgYIDQAAAA==.Frostnova:BAAALAAECgYIBgAAAA==.',Fy='Fyrefoux:BAAALAAECgEIAgABLAAECggIEAACAAAAAA==.',Ga='Galoragran:BAAALAADCgcIBwABLAAECgYIDwACAAAAAA==.Gaëlle:BAAALAADCgEIAQAAAA==.',Gh='Ghjuventu:BAAALAAECgMIAQAAAA==.',Go='Goug:BAAALAAECgQIBgAAAA==.',Gr='Gragdish:BAAALAAECgMIAwAAAA==.Groshâa:BAAALAADCggICAAAAA==.',Ha='Haeli:BAAALAAECgIIBAAAAA==.',He='Herrison:BAAALAADCgYIBgAAAA==.',Hi='Higeki:BAAALAADCggIFQAAAA==.Hioku:BAAALAADCgIIAgAAAA==.',Ho='Hollymarie:BAAALAADCgYIBgAAAA==.Hollymolly:BAAALAADCgIIAgAAAA==.Houdizi:BAAALAAECgIIAgAAAA==.',['Hü']='Hümer:BAAALAADCgcIAgAAAA==.',Ic='Icetomeetyou:BAAALAADCggIEAAAAA==.',Il='Ilrys:BAAALAADCgcIBwAAAA==.',Im='Imodium:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.Impietoyable:BAAALAADCgcIBwAAAA==.',Ja='Jannelle:BAAALAADCggIEAAAAA==.',Je='Jeaneudes:BAAALAAECgYICwAAAA==.',['Jø']='Jøÿce:BAAALAAECgMIBQAAAA==.',['Jù']='Jùstùs:BAAALAAECgQIAwAAAA==.',Ka='Kabo:BAAALAADCgcICQAAAA==.Kadath:BAAALAAECgMIAwAAAA==.Kalhas:BAABLAAECoEVAAIGAAgIpyF5AwATAwAGAAgIpyF5AwATAwAAAA==.Kamose:BAAALAADCgEIAQAAAA==.Kaonashi:BAAALAADCgEIAQAAAA==.',Ke='Kermyd:BAAALAADCgYIBgAAAA==.Kermymelio:BAAALAAECgYIDAAAAA==.Kernel:BAAALAADCggIDAAAAA==.',Ki='Kido:BAAALAADCgUIBQAAAA==.Kiridormu:BAAALAAECgEIAQAAAA==.Kistahr:BAAALAADCgYIBgAAAA==.',Kl='Klasher:BAAALAADCggICAAAAA==.Kléalaine:BAAALAADCgIIAwAAAA==.Kléamolette:BAAALAADCggICAAAAA==.',Ko='Koubiak:BAAALAADCgcIEAAAAA==.',Ky='Kyliane:BAAALAADCgMIBQAAAA==.Kyokô:BAAALAAECgYICAAAAA==.Kyôko:BAABLAAFFIEHAAMDAAQIFxD+AQBcAQADAAQITQ/+AQBcAQAFAAEIFAeFDABNAAAAAA==.',['Kæ']='Kælím:BAAALAADCgIIAgAAAA==.',['Kî']='Kîyoko:BAAALAAECgMIAwAAAA==.',La='Lam:BAAALAAECgUIBgAAAA==.Lamphader:BAAALAADCgcIAgAAAA==.Lapouttre:BAAALAAECggIBgAAAA==.Larsnic:BAAALAAECgYICgAAAA==.Latueuse:BAAALAADCgcIFAAAAA==.Law:BAAALAAECgMIAwAAAA==.',Le='Leolulu:BAAALAAECgQIBAAAAA==.Letsuro:BAAALAAFFAIIAgAAAA==.Lexi:BAAALAADCgYICgAAAA==.Leïkias:BAAALAADCgEIAQAAAA==.Leöla:BAAALAAFFAIIAgAAAA==.',Li='Liadrin:BAAALAADCgUIBAAAAA==.Lilim:BAAALAAECgcIEQAAAA==.Lilitth:BAAALAADCgMIAwAAAA==.Liloodana:BAAALAAECgIIAgAAAA==.Lisindra:BAAALAADCgMIAwAAAA==.Lithìum:BAAALAAECgcIDAAAAA==.',Lo='Lohkï:BAAALAAECgIIBAAAAA==.Lohlâh:BAAALAAECgQIBQAAAA==.Loonette:BAAALAADCggICAAAAA==.Loupmiere:BAAALAADCgIIAgAAAA==.',Lu='Luxvincit:BAAALAAECgEIAQAAAA==.',Ly='Lyanà:BAAALAAECggICAAAAA==.',['Lâ']='Lâgoa:BAAALAAECggICAAAAA==.',['Lø']='Løweell:BAAALAADCgEIAQAAAA==.',['Lù']='Lùnà:BAAALAADCgcIDQAAAA==.',['Lÿ']='Lÿnñ:BAABLAAECoEVAAQHAAgITh5iDgC6AgAHAAgITh5iDgC6AgAIAAEIhgziDQA9AAAJAAEIRgeuSgApAAAAAA==.',Ma='Mahlat:BAAALAADCggIDQAAAA==.Mahìro:BAABLAAECoEVAAIFAAgIlx+WAQD/AgAFAAgIlx+WAQD/AgAAAA==.Maistespalà:BAAALAAFFAIIAgAAAA==.Malgora:BAAALAAECgcICgAAAA==.Marhuul:BAAALAADCgIIAgAAAA==.Marianagetth:BAAALAAECgMIBgAAAA==.',Me='Meawhz:BAAALAAECgYICQAAAA==.Melenix:BAAALAAECgMIAwAAAA==.Menellia:BAAALAADCgcIEQAAAA==.Mernal:BAAALAAECgMIBAAAAA==.Mezrial:BAAALAAECgMIBQAAAA==.',Mo='Moomoone:BAAALAADCgcIFAAAAA==.Mourohi:BAAALAAECggICAAAAA==.Moÿa:BAAALAADCgUIBQAAAA==.',My='Myzedion:BAAALAADCggICAAAAA==.',['Mà']='Màw:BAAALAADCgUIBQAAAA==.',['Mâ']='Mâdalas:BAAALAADCgcICAAAAA==.',['Mã']='Mãnu:BAAALAAECgUIBgAAAA==.',['Më']='Mënëlle:BAAALAADCgMIAwAAAA==.',Na='Naelwë:BAAALAADCgcIBwAAAA==.Nahilaga:BAAALAADCgcIDwAAAA==.Naikina:BAAALAADCggICAAAAA==.Nam:BAABLAAFFIEJAAIKAAQIlxxUAABuAQAKAAQIlxxUAABuAQAAAA==.Nanili:BAAALAADCggIEAAAAA==.Narcée:BAAALAAECgMIAwAAAA==.',Ne='Nerako:BAAALAADCgcIDAAAAA==.',Ni='Niriya:BAAALAAECgYIDQAAAA==.',No='Noctürne:BAAALAADCgIIAwAAAA==.Notsitham:BAAALAAECgYIBgAAAA==.',Nu='Nulhdbriqa:BAAALAAECgIIAwAAAA==.Nulhiedbriks:BAAALAADCggICAAAAA==.',Ny='Nyhra:BAABLAAECoEVAAILAAgIQRfuHQAdAgALAAgIQRfuHQAdAgAAAA==.Nyoko:BAAALAADCgQIAwAAAA==.Nystrala:BAAALAAECgEIAQAAAA==.',['Nâ']='Nâpälhm:BAAALAAECgMIBQAAAA==.',Ok='Okaboto:BAAALAAECgMIBAABLAAECgYIDwACAAAAAA==.',Ol='Olórine:BAAALAADCgMIAwAAAA==.',Ot='Otelavie:BAAALAADCggICAAAAA==.',Pa='Painaulait:BAAALAAECgcIDQAAAA==.Paladinouse:BAAALAADCgIIAgAAAA==.Pandöre:BAAALAADCgQIBAABLAAECgcIEAACAAAAAA==.Papï:BAAALAAECgYIDAAAAA==.',Pe='Pelviss:BAAALAAECgYIDAAAAA==.',Pi='Piconorval:BAAALAAECgYICwAAAA==.Pirlø:BAAALAAECgEIAQAAAA==.',Po='Poètepouette:BAAALAAFFAIIAgAAAA==.',Pr='Priem:BAAALAADCggIFgAAAA==.',Qn='Qnx:BAAALAAECgMIAwAAAA==.',Ra='Radokahn:BAAALAAECgEIAQAAAA==.Raehnyria:BAAALAAECggIEQAAAA==.Rafallan:BAAALAAECgQIBgAAAA==.Raffiq:BAAALAAECgUICAAAAA==.Razbitum:BAAALAAECgcICgAAAA==.Razfrost:BAAALAAECgYIDgAAAA==.Raziell:BAAALAAECgYIDwAAAA==.',Re='Republïc:BAAALAADCggIDgAAAA==.Rev:BAAALAADCggIDwAAAA==.Revilock:BAABLAAECoEXAAQFAAgINyYtAACKAwAFAAgIMyYtAACKAwAEAAcIeh9TAgCUAgADAAEIAx7iXABKAAAAAA==.Reynath:BAAALAADCgcIBwAAAA==.',Ro='Roykard:BAAALAADCgIIAgAAAA==.',Rv='Rvii:BAAALAAECgYIDQABLAAECggIFwAFADcmAA==.',['Rã']='Rãyla:BAAALAAECgYIBgABLAAECggIGAAMABUXAA==.',['Ré']='Révi:BAAALAAECgYIDQABLAAECggIFwAFADcmAA==.',Sa='Sakreth:BAAALAADCggIFgAAAA==.Saïyan:BAAALAADCgcIDgAAAA==.Saûl:BAAALAADCgYIBgAAAA==.',Sc='Schokette:BAAALAADCgMIAwAAAA==.Schtrøumpf:BAAALAAECgcIDAAAAA==.',Se='Senjiî:BAABLAAECoEVAAINAAgI+R0CCACTAgANAAgI+R0CCACTAgAAAA==.',Sh='Shinora:BAAALAAECgEIAQAAAA==.Shiraak:BAAALAAECgYIDQAAAA==.Shyue:BAAALAAECgQICQAAAA==.',Sk='Skipy:BAAALAAECgEIAgAAAA==.Skynokk:BAAALAAECggIEAAAAA==.Skyppi:BAAALAADCgcICAAAAA==.',St='Stropo:BAAALAADCgcIDQAAAA==.',Su='Suréya:BAAALAADCgcICAAAAA==.Susfice:BAAALAAECgIIAgAAAA==.',Sy='Syre:BAABLAAECoEYAAMMAAgIFRfoAQBhAgAMAAgIFRfoAQBhAgAOAAgI8gQAKgBlAQAAAA==.',['Sä']='Sätos:BAAALAAECgYIBwAAAA==.',['Sé']='Séphira:BAAALAAECgYIDwAAAA==.',['Sø']='Søllek:BAAALAAECgQIBAAAAA==.',Ta='Tahk:BAAALAAECgcICAAAAA==.Takouchka:BAAALAAECgIIAgAAAA==.Tankmänia:BAAALAAECgYIDAAAAA==.Tayanah:BAAALAADCgcICwAAAA==.Taÿxa:BAAALAAECgUIBgAAAA==.',Tc='Tchointchoïn:BAAALAAECgEIAQAAAA==.',Th='Thæærølf:BAAALAADCgcIBwAAAA==.',Ti='Tibabia:BAAALAADCgcIBwAAAA==.Tinkera:BAAALAADCgMIAwAAAA==.',To='Tohoka:BAAALAADCgMIAwAAAA==.Torentule:BAAALAAECgMIBAAAAA==.',Tr='Tryxe:BAAALAAECgMIAwAAAA==.',['Tø']='Tøreno:BAAALAADCgEIAQAAAA==.Tørïko:BAAALAAECgIIAgAAAA==.',Va='Valak:BAAALAADCgcIDgAAAA==.Valeme:BAAALAAECgMIBQAAAA==.Valtme:BAAALAADCgIIAgAAAA==.Varkas:BAAALAAECgIIAgAAAA==.',Ve='Vengeresse:BAAALAAECggIBwAAAA==.Venthress:BAAALAADCgcIBwAAAA==.',Vi='Vide:BAAALAADCgMIAwAAAA==.Vitta:BAAALAAECgcIEAAAAA==.',Vo='Volg:BAAALAAECggICwABLAAECggIFwABAE0lAA==.Volkiro:BAAALAADCggIFgAAAA==.Volthâs:BAAALAADCggICAAAAA==.',['Vü']='Vülcain:BAAALAADCgcIBwAAAA==.',Wi='Wismeryl:BAAALAAECgYICQAAAA==.',['Wé']='Wérra:BAABLAAECoEUAAMPAAgIbRQ7FQDZAQAPAAgIMhQ7FQDZAQAQAAIIDg+vZAB2AAAAAA==.',['Wî']='Wîkï:BAAALAAECgEIAgABLAAECgMIBAACAAAAAA==.',['Wï']='Wïkî:BAAALAAECgMIBAAAAA==.',Xe='Xenophon:BAABLAAECoEUAAIRAAcI+x+ZBAB8AgARAAcI+x+ZBAB8AgAAAA==.Xeï:BAAALAADCgcIDAABLAAECgcIFAARAPsfAA==.Xeïna:BAAALAADCggICwABLAAECgcIFAARAPsfAA==.',Xi='Xióng:BAAALAADCgcIAgAAAA==.',Ya='Yako:BAAALAAECgIIAwAAAA==.',Yl='Ylanâa:BAAALAAECggICAAAAA==.',Yo='Yokozuna:BAAALAADCgEIAQAAAA==.Yoshîmura:BAAALAAECgIIAgAAAA==.',Za='Zalès:BAAALAADCggIEQAAAA==.',Ze='Zerothen:BAAALAAECgQIBwAAAA==.',Zi='Zinøtrïx:BAAALAADCgUICAAAAA==.',Zk='Zkèz:BAAALAAECgEIAQAAAA==.',Zu='Zuldân:BAAALAAECgYICAAAAA==.',Zz='Zzccmxtp:BAAALAADCgcIDQAAAA==.',['Àr']='Ària:BAAALAADCggIDAAAAA==.',['Æl']='Ælith:BAAALAAECgQIBAAAAA==.',['Ðe']='Ðeathnote:BAAALAAECgYICwAAAA==.',['Ør']='Ørikan:BAAALAAECgMIBQAAAA==.',['Øs']='Øsabi:BAAALAAECgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end