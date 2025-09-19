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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Frost','Mage-Frost','Mage-Arcane','Evoker-Devastation','Hunter-Survival','Shaman-Elemental','Evoker-Augmentation','Paladin-Retribution','Shaman-Restoration','Warrior-Fury','Warrior-Protection',}; local provider = {region='EU',realm='Wrathbringer',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aerion:BAAALAADCggIDgAAAA==.',Al='Alakaja:BAAALAAECgMIBwAAAA==.Alyrià:BAAALAAECgYICwAAAA==.Alyrus:BAAALAAECgYICwAAAA==.Alysrêa:BAAALAAECgMIBQAAAA==.',Am='Amaterasû:BAAALAAECgQIBgAAAA==.',An='Anaco:BAAALAADCgEIAQAAAA==.',Ar='Arathak:BAAALAAECgYICQAAAA==.',As='Aspekt:BAAALAAECgQIBAABLAAECgUIBwABAAAAAA==.Astrâ:BAAALAADCggICAAAAA==.',Av='Avalia:BAAALAADCgcICAAAAA==.Avarie:BAAALAAECgMIAwAAAA==.',Ay='Ayamy:BAAALAAECgcIDQAAAA==.',Az='Azlag:BAAALAADCgIIAgAAAA==.',['Aß']='Aßindia:BAAALAAECgYIBgAAAA==.',Ba='Babutcha:BAAALAAECgYICAAAAA==.Barfuß:BAAALAADCggICAAAAA==.Barryy:BAAALAAECggIBgAAAA==.',Be='Beradox:BAABLAAECoEaAAMCAAgIyh6eDABeAgACAAcI9B6eDABeAgADAAEIoR1IcQBXAAAAAA==.',Bi='Bibalicious:BAAALAADCggICQAAAA==.',Bl='Blootgeil:BAAALAAECgYIBwAAAA==.Blutvente:BAAALAADCgQIBAAAAA==.Blóodbée:BAAALAAECgMIBwAAAA==.',Bo='Bondagé:BAAALAADCgcICAAAAA==.',Br='Brokah:BAAALAAECgYIBgAAAA==.Brotbüchse:BAAALAAECggIAgAAAA==.',Bu='Buffme:BAAALAADCgYIBgABLAAECgcICgABAAAAAA==.Bullentussy:BAAALAAECgEIAQAAAA==.',['Bø']='Bødhî:BAAALAADCggIDwAAAA==.',Ch='Chêrry:BAAALAAECgIIAgAAAA==.Chô:BAAALAADCgYIBgAAAA==.',Ci='Cijandri:BAAALAAECgMIAwAAAA==.',Cl='Cleylock:BAAALAAECgMICAAAAA==.',Cu='Cutyu:BAAALAADCggIEQAAAA==.',Da='Darona:BAAALAAECgYIDAAAAA==.Darthreaper:BAABLAAECoEXAAMEAAgIhyGyCQATAgAEAAUIFySyCQATAgAFAAYI6BmANAC2AQAAAA==.Darthvicious:BAAALAAECgMIAwAAAA==.Daydoron:BAAALAAECgIIAgAAAA==.Daydreamer:BAAALAADCggIDQAAAA==.',De='Demonmuh:BAAALAAECgQIBAAAAA==.Devilgoth:BAAALAADCggICAAAAA==.',Di='Dirune:BAAALAAECgYICgAAAA==.',Dj='Djandoxd:BAAALAAECgYICQAAAA==.',Do='Dornenblumé:BAAALAAECgcIDQAAAA==.',Dr='Dreamfyre:BAAALAADCggICAAAAA==.',Dz='Dzibrill:BAAALAADCgMIAwAAAA==.',Ek='Ekolten:BAAALAAECgUIBQAAAA==.',Em='Emdru:BAAALAADCggIEAAAAA==.',En='Ente:BAAALAADCgcIBwAAAA==.',Eo='Eotrin:BAAALAAECgYICAAAAA==.',Er='Erandur:BAAALAADCggIDAAAAA==.Erea:BAAALAADCggIDQAAAA==.',Ex='Exardin:BAAALAAECgIIAgAAAA==.',Fe='Feazz:BAABLAAECoEQAAMGAAYIwRxJEgDJAQAGAAYIuBtJEgDJAQAHAAUI6BYqQgBjAQAAAA==.Feddora:BAAALAAECgQIBQAAAA==.',Fl='Flames:BAAALAADCgQIBAABLAAECgYIDwABAAAAAA==.Flippie:BAABLAAECoEWAAIIAAgIyhz2BwC1AgAIAAgIyhz2BwC1AgAAAA==.',Fr='Fraumerkel:BAAALAADCgMIAwAAAA==.Fritzelbritz:BAAALAADCgMIAwAAAA==.Frêyá:BAAALAADCgEIAQAAAA==.',Fu='Fumor:BAAALAAECgcIEAAAAA==.',Ga='Galore:BAAALAAECgIIBAAAAA==.',Ge='Gelidá:BAAALAADCggICgAAAA==.Gelin:BAAALAADCggICAAAAA==.',Gh='Ghoststalk:BAAALAAECgEIAQAAAA==.',Go='Goodfellass:BAAALAAECgEIAQAAAA==.',Gr='Grimwald:BAAALAAECgYIDwAAAA==.Grusélla:BAAALAAECgIIAgAAAA==.',['Gà']='Gàruda:BAAALAAECgcIDQAAAA==.',Ha='Hagebuddne:BAAALAAECgMIBAAAAA==.Hanah:BAAALAAECgYIBgAAAA==.Hannya:BAAALAAECgMIBQAAAA==.',He='Hegamurl:BAAALAAECgUIBwAAAA==.Heisor:BAAALAAECgQIBwAAAA==.Hellothere:BAAALAAFFAIIAwAAAA==.',Hj='Hjacker:BAAALAAECgYIBgAAAA==.',Hu='Huntjinn:BAABLAAECoEUAAQJAAgI/B76AADdAgAJAAgIqB36AADdAgACAAgIJxZNEwD9AQADAAIIFRkgZQCFAAAAAA==.',Ic='Icomeinpeace:BAAALAAECgIIAgAAAA==.',In='Innidovil:BAAALAAECggICAAAAA==.',Iv='Iveri:BAAALAADCgcIDAAAAA==.Iviry:BAAALAADCgcIDQABLAAECgYIDAABAAAAAA==.',Iw='Iwire:BAAALAAECgYIDAAAAA==.',Ja='Jackburst:BAAALAAECgYIDAAAAA==.',Ju='Jukpew:BAAALAAECgMIBAABLAAECgYIBgABAAAAAA==.',['Jü']='Jükü:BAAALAAECgYIBgAAAA==.',Ka='Kaeæs:BAAALAADCggICAAAAA==.Kalita:BAAALAAECgYICAAAAA==.Kazuko:BAAALAAECgUIBwAAAA==.',Ke='Keinhorn:BAAALAAECgUIBQAAAA==.Kesuke:BAAALAADCgcIBwAAAA==.',Kh='Khorash:BAAALAAECgcIEwAAAA==.',Ki='Kiomá:BAAALAADCgYIBgAAAA==.',Kl='Klatschmuh:BAAALAADCgcIEgAAAA==.',Ko='Koedoron:BAAALAADCggICAAAAA==.',Kr='Kraftbrühe:BAAALAAECggICwAAAA==.',Ky='Kyira:BAAALAAECgcIEAAAAA==.',La='Lahmus:BAAALAAECgEIAQAAAA==.Lazarussign:BAAALAADCgUIBQAAAA==.',Le='Leanois:BAAALAADCggICwAAAA==.Legit:BAAALAADCgcIBwAAAA==.Levia:BAAALAAECgMIAwAAAA==.',Lh='Lhihunter:BAAALAADCgUIBgAAAA==.',Li='Liyaa:BAAALAAECggIEwAAAA==.',Lo='Lolô:BAAALAAECgYIBgAAAA==.Lorox:BAAALAAECgIIAgAAAA==.',Lu='Lunéx:BAAALAAECgcIEAAAAA==.',Ma='Madwac:BAAALAAECgYIDAAAAA==.',Me='Meistêr:BAAALAAECgEIAQAAAA==.',Mi='Mike:BAAALAAECggICAAAAA==.Mish:BAAALAAECgYICwAAAA==.',Mo='Moiki:BAABLAAECoEaAAIKAAgIFBtSDQCMAgAKAAgIFBtSDQCMAgAAAA==.Moikidan:BAAALAAECgMIAwABLAAECggIGgAKABQbAA==.Moikii:BAAALAAECgEIAQABLAAECggIGgAKABQbAA==.Mokinus:BAAALAADCggIDwAAAA==.Mokki:BAAALAADCgQIBAAAAA==.Mondpriest:BAAALAAECgIIAgAAAA==.Mood:BAAALAAECgMIBQAAAA==.Moy:BAAALAADCgcIBwAAAA==.',Mu='Muhskelkater:BAAALAADCggIFwAAAA==.',Na='Naelgnuy:BAAALAADCgQIBAAAAA==.Nagrim:BAAALAADCggIDgAAAA==.Nali:BAAALAADCgYIBgAAAA==.Nartasha:BAAALAAECgYICQAAAA==.',Ne='Nexari:BAAALAAECgQIBQAAAA==.',No='Nookye:BAAALAAECgMIAwAAAA==.',Ny='Nyll:BAAALAADCggICgAAAA==.',Ob='Oboss:BAAALAADCgYICgAAAA==.',Oh='Ohnono:BAAALAADCgQIBAAAAA==.Ohurâ:BAAALAADCgEIAQABLAADCgEIAQABAAAAAA==.',Oo='Oomami:BAAALAADCgUIBQAAAA==.',Op='Optimo:BAABLAAECoEXAAMIAAgITxlBCwBtAgAIAAgInhdBCwBtAgALAAYImBhIAwCoAQAAAA==.',Ow='Owir:BAAALAAECgMIAwAAAA==.',Pa='Pain:BAABLAAECoEXAAIEAAgIhSLkAgDaAgAEAAgIhSLkAgDaAgAAAA==.Palatin:BAABLAAECoEXAAIMAAgIfyP8BgAbAwAMAAgIfyP8BgAbAwAAAA==.Parbo:BAAALAADCgEIAQAAAA==.',Pf='Pfosten:BAAALAAECgYICwAAAA==.',Pi='Piepsi:BAAALAADCggIFgAAAA==.',Pr='Prestoc:BAAALAAECgMIBAAAAA==.Propheteggxi:BAAALAADCggIFwAAAA==.',Qu='Quixxor:BAAALAAECgcIEgAAAA==.',Ra='Racaf:BAAALAADCggIDwAAAA==.Rattopher:BAAALAADCggIEgAAAA==.Razador:BAAALAAECgIIAgAAAA==.Razó:BAAALAADCggIFAAAAA==.',Ri='Rin:BAAALAAECgYICAAAAA==.',Ro='Robmaster:BAAALAAECgEIAQAAAA==.Rogsha:BAAALAADCgcIDQAAAA==.',Ru='Ruvena:BAAALAADCggIBgAAAA==.',Ry='Ryndiira:BAAALAADCggICAAAAA==.',['Rä']='Rämsr:BAAALAADCggICgAAAA==.',Sa='Sanyex:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.Saorla:BAAALAADCgYIBgAAAA==.Saree:BAAALAAECgMIAwAAAA==.',Se='Seirina:BAAALAADCgEIAQAAAA==.',Sh='Shakti:BAAALAAECgYIBgAAAA==.Shimarah:BAAALAAECgMIAwAAAA==.Shirá:BAAALAAECgEIAQAAAA==.Shorash:BAAALAADCggICwAAAA==.',Sn='Snowflaké:BAAALAADCggIDgAAAA==.',So='Sopala:BAAALAAECgIIBAAAAA==.Sorata:BAAALAAECgcIEAAAAA==.Sorayja:BAAALAAECgIIBAAAAA==.',St='Steinbeißer:BAAALAAECgcICgAAAA==.Stoopsr:BAAALAAECgMIAwAAAA==.Stronker:BAAALAAECgYICgAAAA==.',Su='Sunic:BAAALAADCggICAAAAA==.Sunji:BAAALAAECgYIBgAAAA==.',Sy='Syhm:BAAALAAECgcIBwABLAAECggIFAAJAPweAA==.Syn:BAAALAAECgIIBAABLAAECgcIEAABAAAAAA==.',['Sî']='Sîlas:BAAALAAECgUIBQAAAA==.',['Sú']='Súvá:BAAALAAECgYICQAAAA==.',Ta='Tallynus:BAAALAADCgcIBwAAAA==.Taloxx:BAAALAADCggICAAAAA==.Talys:BAAALAAECgIIAgAAAA==.Tanís:BAAALAAECgYIDwAAAA==.Tavaros:BAAALAAECgIIAgAAAA==.Taz:BAAALAADCggIDwAAAA==.',Te='Tedia:BAAALAADCgcIDgAAAA==.',Th='Thcil:BAAALAADCggICAAAAA==.Theôderich:BAAALAADCggICAAAAA==.Thjasse:BAABLAAECoEaAAINAAgIXiEbAwD8AgANAAgIXiEbAwD8AgAAAA==.Thorbine:BAAALAAECgYICgAAAA==.Thêoderich:BAAALAADCgQIBQAAAA==.',To='Tomea:BAAALAADCggICAAAAA==.Totemtimo:BAAALAADCgcICQAAAA==.',Tr='Tranq:BAAALAAECgYIDwAAAA==.Tranquila:BAAALAADCggIEAAAAA==.Trekor:BAAALAAECgUIBwAAAA==.Trishka:BAAALAAECgEIAQAAAA==.',Ts='Tschiffra:BAAALAAECgIIAwAAAA==.',Tu='Turbo:BAABLAAECoEWAAIOAAgI9BwlEgBbAgAOAAgI9BwlEgBbAgAAAA==.',Ty='Tyrodal:BAAALAAECggICQAAAA==.',['Tá']='Tálînà:BAAALAADCgYIBgAAAA==.',Uk='Ukanu:BAAALAAECgYIBQAAAA==.',Ul='Ulkhor:BAAALAAECgYICgAAAA==.',Un='Unclebarry:BAAALAADCggICAAAAA==.',Ur='Urshâg:BAAALAADCgIIAgAAAA==.',Uw='Uwudan:BAEALAAECgEIAQABLAAECggIFgAHAN0cAA==.Uwumage:BAEBLAAECoEWAAIHAAgI3RzDFAB/AgAHAAgI3RzDFAB/AgAAAA==.',Va='Vagra:BAAALAAECgIIAgAAAA==.Valesia:BAAALAAECgMIAwAAAA==.Vaphex:BAAALAAECgYICQAAAA==.Vasu:BAAALAAECgcICwAAAA==.Vazu:BAAALAAECgUIBQABLAAECgcICwABAAAAAA==.',Ve='Vezz:BAAALAAECgcIEAAAAA==.',Vi='Victôry:BAAALAAECgQIBAAAAA==.Violaine:BAAALAADCgMIAwAAAA==.',Vu='Vulturas:BAAALAAECgcICgAAAA==.Vuvigdrood:BAAALAADCgcIEAAAAA==.',Xa='Xaeros:BAAALAADCggICAABLAAECgcICgABAAAAAA==.Xaki:BAAALAAECgYICAAAAA==.Xao:BAAALAAECgYIBgAAAA==.',Xe='Xeana:BAAALAADCggIDgAAAA==.Xelodie:BAAALAADCgMIAwABLAAECgcICgABAAAAAA==.Xentronius:BAAALAAECgcIEwAAAA==.',Xh='Xhalta:BAAALAADCggICAAAAA==.',Xi='Xilas:BAAALAADCggICAAAAA==.',Xu='Xull:BAAALAADCgcIDQAAAA==.',['Xî']='Xîrr:BAAALAADCgYICAAAAA==.',Ya='Yarelna:BAAALAAECgYICwAAAA==.',Ys='Ysegrim:BAAALAAECgMIBAAAAA==.',Yv='Yve:BAAALAAECgMIAwAAAA==.',Za='Zackding:BAAALAAECgMIAwAAAA==.Zappyboy:BAAALAAECgEIAgAAAA==.',Ze='Zechnet:BAAALAADCgMIAwAAAA==.Zeppelin:BAAALAAECgIIBQAAAA==.',Zi='Zilas:BAAALAAECggICwAAAA==.Zipacna:BAAALAAECggIDAAAAA==.Zischpeng:BAAALAADCgIIAgAAAA==.',['Æl']='Ælumø:BAAALAADCgUIBgABLAADCggICAABAAAAAA==.',['Æm']='Æmalia:BAAALAADCggICAABLAAECggIFwAPAC0mAA==.',['Æo']='Æoreth:BAABLAAECoEXAAIPAAgILSZMAACIAwAPAAgILSZMAACIAwAAAA==.',['Æw']='Æwyen:BAAALAADCggICgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end