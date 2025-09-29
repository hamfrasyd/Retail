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
 local lookup = {'Shaman-Restoration','Shaman-Elemental','Warrior-Arms','Unknown-Unknown','Warlock-Affliction','Evoker-Devastation','Druid-Restoration','Priest-Shadow','Druid-Guardian','Hunter-BeastMastery','Warrior-Fury','Druid-Balance','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Havoc','Paladin-Retribution','Monk-Brewmaster',}; local provider = {region='EU',realm="Un'Goro",name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarren:BAAALAADCggIHAAAAA==.',Ab='Abluren:BAAALAADCggIHAAAAA==.',Ad='Adio:BAAALAADCgcICQAAAA==.Adiô:BAAALAADCggICwAAAA==.Adiø:BAAALAADCggIDAAAAA==.',Ai='Aidranisa:BAACLAAFFIEKAAIBAAII9ia0DwDlAAABAAII9ia0DwDlAAAsAAQKgTUAAgEACAjMJmIAAIADAAEACAjMJmIAAIADAAAA.',Al='Altérnis:BAAALAAECgYIDwAAAA==.',Ar='Aravis:BAAALAAECgMICQAAAA==.Arestios:BAAALAADCggICAAAAA==.',As='Ashnagz:BAAALAAECgIIAgAAAA==.Asuká:BAAALAADCggICAAAAA==.',Au='Aurex:BAABLAAECoEUAAMBAAYInR2pVwCwAQABAAYInR2pVwCwAQACAAYIPw2EYwBcAQAAAA==.',Ba='Bafragor:BAAALAADCggIDQAAAA==.',Be='Belanaer:BAAALAADCgYIBgABLAAECgcIHgADACAbAA==.Bepo:BAAALAADCggIGgAAAA==.',Bi='Bimmler:BAABLAAECoEYAAIDAAgIYhzNDADqAQADAAgIYhzNDADqAQAAAA==.Bingobob:BAAALAAECgMICAAAAA==.',Bl='Blackdevilxx:BAAALAADCgIIAgAAAA==.Blackrippche:BAAALAADCggICQAAAA==.Blizzòrd:BAAALAAECgMIAwABLAAECgMICAAEAAAAAA==.Blutkönîg:BAAALAAECggICAAAAA==.Bláckbart:BAAALAAECgcIEwAAAA==.',Bo='Bodaway:BAAALAAFFAIIAgABLAAFFAUICgACAJEPAA==.Borban:BAAALAADCgUIBQAAAA==.',Br='Bracer:BAAALAADCgQIBAABLAAECggIGAAFAM8gAA==.',Ca='Casualbard:BAAALAADCggIEwAAAA==.Casuallock:BAAALAAECgYIDAAAAA==.Casualwarri:BAAALAADCggIEAAAAA==.Cathy:BAAALAADCgMIAwAAAA==.Catwithin:BAAALAADCgUICQABLAAECgQIBAAEAAAAAA==.',Ch='Chibrandy:BAAALAADCggICAABLAAECggIBAAEAAAAAA==.Chronobrandy:BAABLAAECoEaAAIGAAgIvBd2GwApAgAGAAgIvBd2GwApAgAAAA==.',Ci='Cinemoon:BAAALAADCgMIBAAAAA==.',Cl='Cloudson:BAAALAADCgcIBwAAAA==.',Da='Dadael:BAAALAAECgUICwAAAA==.Dalesia:BAAALAAECgcIEQAAAA==.',De='Demonalisa:BAAALAADCgcIBwAAAA==.Denoria:BAAALAAECgcIEwAAAA==.Devilina:BAAALAADCggICAAAAA==.Devilskeeper:BAAALAAECgIIAgAAAA==.',Dr='Dragobert:BAAALAADCgUIBQAAAA==.Dragoon:BAAALAADCgcICgAAAA==.',Ed='Edelgonn:BAAALAAECgYIBgAAAA==.',El='Elúnya:BAABLAAECoEcAAIHAAYIgA95bwAHAQAHAAYIgA95bwAHAQAAAA==.',Em='Emiya:BAAALAAECgUIBQAAAA==.',Ex='Exava:BAABLAAECoErAAIIAAgIkBxHGQCLAgAIAAgIkBxHGQCLAgAAAA==.',Fa='Fauler:BAAALAAECgUIBQAAAA==.',Fe='Fenric:BAAALAAECgYICgAAAA==.',Fi='Firewithin:BAAALAADCgcIFAABLAAECgQIBAAEAAAAAA==.',Fl='Flegmon:BAAALAAECgcICgABLAAECgcIFAAJAEEUAA==.Floh:BAAALAAECgYIDAAAAA==.',Fr='Frostgubbl:BAAALAADCggIHQAAAA==.',Ga='Garu:BAABLAAECoEkAAIBAAgI6xO8SwDSAQABAAgI6xO8SwDSAQAAAA==.',Go='Goldina:BAAALAADCggIEwAAAA==.Golgi:BAAALAAECgYIDwAAAA==.Golka:BAAALAAECgYIBgABLAAECgcIHQAHAE8jAA==.',Gr='Gralos:BAAALAADCgYIBgAAAA==.',Gu='Gunnar:BAAALAAECgIIAgAAAA==.',Ha='Hairyhotter:BAAALAAECgYIDAAAAA==.Hammergünter:BAAALAADCgEIAQABLAAECgcIHAAKAK8iAA==.',He='Healstraszas:BAAALAADCggIDwAAAA==.Herio:BAAALAAECgYIEQAAAA==.',Hi='Hildür:BAAALAAECgIIAwAAAA==.',Ho='Holyteck:BAAALAADCgcIEAAAAA==.',['Há']='Hálk:BAAALAAECggIEwAAAA==.',['Hâ']='Hâldir:BAAALAAECggICAAAAA==.',['Hê']='Hêxî:BAAALAAECgcIDgAAAA==.',Id='Idefix:BAAALAADCgQIBAAAAA==.Idrâcab:BAAALAAECgYIDAAAAA==.',Il='Iladan:BAAALAADCgYIBgABLAAECgQIBAAEAAAAAA==.',Im='Imiraculix:BAAALAAECgIIBAAAAA==.',Ir='Irongobbie:BAABLAAECoEUAAILAAcIXwrvcQBnAQALAAcIXwrvcQBnAQAAAA==.',Ix='Ixathal:BAAALAAECgYICQAAAA==.',Ja='Jackline:BAAALAADCggIGwAAAA==.',Ka='Kaldesch:BAAALAADCgQIBAAAAA==.',Ke='Kenshan:BAAALAAECgIIAgABLAAECgQIBAAEAAAAAA==.Kesher:BAAALAAECggIDQAAAA==.',Kh='Kharzak:BAABLAAECoEeAAMDAAcIIBtZCABMAgADAAcIIBtZCABMAgALAAEITwiY1gArAAAAAA==.',Kn='Knallkopp:BAAALAAECgEIAQAAAA==.',Ko='Koch:BAAALAAECgYIDwAAAA==.Kohaku:BAABLAAECoEaAAMBAAgIwRMFfQBPAQABAAgIwRMFfQBPAQACAAMI+AiIkQCWAAAAAA==.',Kr='Kravchenko:BAAALAADCgcIBwAAAA==.',Ky='Kyrilla:BAAALAADCgQIBAAAAA==.',La='Lacrimà:BAAALAAECgMIBgAAAA==.',Le='Lesmana:BAAALAAECgYICgAAAA==.',Li='Linduxu:BAAALAAECgQIBgAAAA==.',Lo='Loli:BAAALAADCgYIBgAAAA==.',['Lî']='Lîlíth:BAAALAADCggICAAAAA==.',['Lú']='Lúcillé:BAAALAAECgUICAAAAA==.',['Lý']='Lýnní:BAAALAADCgIIAgAAAA==.',Ma='Malkuth:BAABLAAECoEcAAIHAAcIJiVfCwDlAgAHAAcIJiVfCwDlAgAAAA==.Marlû:BAAALAADCgYIBgAAAA==.Mary:BAAALAAECgIIAwABLAAECgYIHAAHAIAPAA==.',Me='Mebanker:BAAALAAECgYIBgAAAA==.Merystraza:BAAALAADCggICAAAAA==.',Mi='Minus:BAAALAADCggIDAAAAA==.',Mo='Mogun:BAAALAADCgIIAgAAAA==.Morguhl:BAAALAADCgYIBgABLAAECgcIHgADACAbAA==.',My='Mysteria:BAAALAAECgQIBQABLAAECgYIDAAEAAAAAA==.',['Mà']='Mànari:BAAALAAECgMICAAAAA==.',['Mü']='Müxo:BAAALAAECgcICgAAAA==.',Na='Nakhla:BAAALAADCggICAAAAA==.Naneka:BAAALAAECgYIBgAAAA==.Naxara:BAAALAAECgYIBgAAAA==.',Ne='Nexusi:BAAALAAECgEIAQAAAA==.',No='Nofearian:BAAALAADCgcIDAABLAAECgQIBAAEAAAAAA==.Norus:BAABLAAECoEcAAIKAAcIryLCIgCZAgAKAAcIryLCIgCZAgAAAA==.',Ob='Obelaxy:BAAALAADCgcIBwAAAA==.',Os='Osiradk:BAAALAADCggIBgAAAA==.',Ow='Ownkin:BAABLAAECoEZAAIMAAYIZSGrJAAWAgAMAAYIZSGrJAAWAgAAAA==.',Pa='Pasemesani:BAAALAAECgYICgAAAA==.',Pe='Peinkilleron:BAABLAAECoEbAAIKAAYIIRuRbgCjAQAKAAYIIRuRbgCjAQAAAA==.',Pf='Pflegeputze:BAAALAADCgcICwAAAA==.',Pi='Pichu:BAAALAADCggIEgABLAAECggIJAAKAMkVAA==.Pille:BAAALAAECgYICAAAAA==.Pimbi:BAAALAAECgYIDQAAAA==.',Ra='Ragin:BAABLAAECoEcAAIGAAYIzhZtLACcAQAGAAYIzhZtLACcAQAAAA==.Ranten:BAAALAAECgMIAwAAAA==.Ranton:BAABLAAECoEdAAINAAgIpBiaKwAFAgANAAgIpBiaKwAFAgAAAA==.',Ru='Ruderas:BAAALAAECggIDgAAAA==.',Sc='Schamoc:BAABLAAECoEcAAIBAAYI9xpsVQC1AQABAAYI9xpsVQC1AQAAAA==.',Se='Seele:BAAALAAECgIIAwABLAAECgYIHAAGAM4WAA==.Seralí:BAAALAAECgYIBgAAAA==.Serana:BAAALAADCggIDwAAAA==.',Sh='Shagura:BAAALAAECggIBAAAAA==.Shumbultala:BAAALAADCggICAAAAA==.Shâdów:BAAALAADCggIEgAAAA==.',Sk='Skalli:BAABLAAECoEcAAIOAAcI+BL4CQDoAQAOAAcI+BL4CQDoAQAAAA==.Skàr:BAAALAADCgQIBgAAAA==.',So='Soy:BAAALAAECgYICwAAAA==.',Sp='Speedshot:BAAALAADCgIIAgAAAA==.Speedtator:BAAALAAECgQIBAAAAA==.Speedverossa:BAAALAAECgcIBwAAAA==.',St='Stepjab:BAAALAADCgYICQAAAA==.Stôlen:BAAALAAECgIIBAAAAA==.',Sy='Syreena:BAAALAADCggICAABLAAECgYIHAAHAIAPAA==.',Ta='Taktlôss:BAABLAAECoEZAAIBAAcIGh7SKwA/AgABAAcIGh7SKwA/AgAAAA==.',Te='Tetrapåck:BAAALAAECgYIBgAAAA==.',Ti='Titaniari:BAAALAADCgYIBgAAAA==.',To='Tohrgrim:BAAALAADCggICAABLAAECgYIDAAEAAAAAA==.Toram:BAAALAADCgYIBgABLAAECgcIHgADACAbAA==.Tormentar:BAAALAADCggICQAAAA==.',Tu='Turøk:BAACLAAFFIEIAAIKAAMI2hzxDwAFAQAKAAMI2hzxDwAFAQAsAAQKgS4AAgoACAhLJLQLACMDAAoACAhLJLQLACMDAAAA.',Ty='Tyvarr:BAAALAAECgYIDwAAAA==.Tyvârr:BAAALAAECgUICAAAAA==.',Ur='Uran:BAAALAAECgcIDQAAAA==.',Va='Valaroth:BAABLAAECoEVAAIPAAcI5RDzcgCyAQAPAAcI5RDzcgCyAQAAAA==.',Vi='Viperina:BAAALAAECgIIAgAAAA==.',Vo='Volan:BAAALAADCggICgABLAAECgcIHgADACAbAA==.',Vu='Vulpra:BAAALAADCggICAAAAA==.',Wh='Whynot:BAAALAADCgcIDAABLAAECgIIAgAEAAAAAA==.',Xa='Xandoria:BAAALAADCgcIBwAAAA==.',Xi='Xixes:BAAALAADCggIEAAAAA==.',Yo='Yoke:BAAALAADCgcICgAAAA==.',Yu='Yukari:BAAALAAECgYICgAAAA==.Yukira:BAAALAADCgMIAwABLAAECgYIHAAHAIAPAA==.',Ze='Zeuzeu:BAAALAADCgEIAQABLAAECgMICAAEAAAAAA==.',Zi='Zilo:BAAALAADCgYICwAAAA==.',Zo='Zoeba:BAAALAAECgYIDAAAAA==.',Zy='Zyrok:BAAALAAECgMIBQAAAA==.',['Âl']='Âltêrnis:BAAALAAECgQIBgAAAA==.',['Äl']='Älexso:BAAALAADCgEIAQAAAA==.',['Æp']='Æpio:BAABLAAECoEbAAIQAAcIpw7lkACaAQAQAAcIpw7lkACaAQAAAA==.',['Êl']='Êlaine:BAABLAAECoEWAAIRAAYIuBfPHwBlAQARAAYIuBfPHwBlAQAAAA==.',['Êu']='Êule:BAAALAADCggIEAAAAA==.',['Ða']='Ðania:BAABLAAECoEZAAIKAAcIugv9jwBeAQAKAAcIugv9jwBeAQAAAA==.',['Øs']='Øsiramage:BAAALAAECgQIBAAAAA==.Øsîra:BAAALAAECggIAwAAAA==.',['Ýû']='Ýûmi:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end