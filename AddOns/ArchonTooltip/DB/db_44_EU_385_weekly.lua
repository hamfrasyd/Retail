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
 local lookup = {'Unknown-Unknown','Warrior-Arms','Mage-Frost','Monk-Windwalker','DeathKnight-Frost','Monk-Mistweaver','Druid-Balance','Druid-Restoration','Warlock-Destruction','Druid-Feral','DemonHunter-Havoc','Paladin-Retribution','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Priest-Holy','Priest-Discipline','Paladin-Protection','Priest-Shadow','DeathKnight-Blood',}; local provider = {region='EU',realm='Sinstralis',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aalec:BAAALAAECgYIDAAAAA==.',Ab='Abzoom:BAAALAAECggIEgAAAA==.',Ad='Adyboo:BAAALAAECgYIBgAAAA==.',Ah='Aheris:BAAALAADCgEIAQAAAA==.',Ak='Akamarü:BAAALAAECgUIBgAAAA==.Akouma:BAAALAADCggIFQAAAA==.',Al='Alvilda:BAAALAADCgcIBwAAAA==.',Am='Amagaye:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Ammazone:BAAALAADCgcIBwAAAA==.',An='Annehidalgo:BAAALAAECgcIEAABLAAECgQIBwABAAAAAA==.Anèga:BAAALAADCgcIBwAAAA==.',Ar='Arcâdïa:BAAALAADCgcIDAABLAAECgIIAgABAAAAAA==.Arkide:BAAALAAECgcIEAAAAA==.Arklock:BAAALAADCgUIBQAAAA==.',As='Asuman:BAAALAADCggIDQAAAA==.',Az='Azarelis:BAAALAADCgYICwAAAA==.',Ba='Bahaztek:BAAALAAECgYIEQAAAA==.Baladine:BAAALAAECgQIBQAAAA==.Balöo:BAAALAADCgEIAQAAAA==.Bartocck:BAAALAADCgcIDgAAAA==.Bastykk:BAABLAAECoEVAAICAAgIdh63AQCpAgACAAgIdh63AQCpAgAAAA==.',Be='Beback:BAAALAADCgEIAQAAAA==.Behe:BAAALAAECgMIBQAAAA==.',Bh='Bhrenayn:BAAALAAECgcIEQAAAA==.',Bo='Bonbon:BAAALAAECgYICgAAAA==.',['Bö']='Bömbers:BAAALAAECgYIBgAAAA==.',Ca='Caracas:BAAALAADCgIIAgAAAA==.',Ch='Chamoulox:BAAALAAECgYIDwAAAA==.Chamrök:BAAALAAECgQIBAAAAA==.Chamrøk:BAAALAADCgYIBgAAAA==.Chanteciel:BAAALAAECgYIDQAAAA==.Charlouff:BAAALAADCggIDQAAAA==.',Ci='Cimeriss:BAAALAAECgYICgAAAA==.Ciran:BAAALAADCgMIAwAAAA==.Cirelle:BAAALAAECgYIDQAAAA==.',Cr='Crakoukass:BAAALAAECgIIAgAAAA==.Crenkss:BAAALAAECggIDQAAAA==.',Cy='Cyrann:BAAALAADCggIDgAAAA==.',Da='Dakina:BAAALAADCgcIDAAAAA==.Darkilik:BAAALAAECgYIDQAAAA==.Darkshadöw:BAAALAADCgcIDAABLAAECgIIAgABAAAAAA==.',Di='Diki:BAAALAAECgcIBwAAAA==.Dingodaz:BAAALAAECgEIAQAAAA==.Distress:BAAALAAECgYIDwAAAA==.Diviciacoss:BAAALAAECgEIAQAAAA==.',Dj='Djryllz:BAABLAAECoEXAAIDAAgIow1xFwCSAQADAAgIow1xFwCSAQAAAA==.',Dr='Drakaufeu:BAAALAADCggIFQAAAA==.Drimzz:BAAALAAECgQIBAABLAAECggIDwABAAAAAA==.',Du='Dumè:BAAALAADCggICwABLAAECgcIDgABAAAAAA==.',El='Eladina:BAAALAADCggIDgAAAA==.Elfeah:BAAALAADCgYIBgAAAA==.Elione:BAAALAADCggICAAAAA==.Eliyù:BAABLAAECoEZAAIDAAgISSGiAgAQAwADAAgISSGiAgAQAwAAAA==.Elwabi:BAAALAAECgYIEAAAAA==.Elyria:BAAALAADCgIIAgABLAAECggIFwAEAAkcAA==.',Fe='Feef:BAAALAADCggICwAAAA==.Felipecha:BAAALAAECgUIBgAAAA==.',Fr='Fracafiak:BAAALAADCgMIAwAAAA==.Freetipoyo:BAAALAADCggICAAAAA==.Frostyze:BAAALAAECgcIDAAAAA==.',Ga='Gaarasand:BAAALAADCgYIBwAAAA==.Gargalalm:BAAALAAECgMIBAAAAA==.',Gi='Gipsa:BAAALAAECgMIAwABLAAECggIFQAFAKwiAA==.',Gl='Glubux:BAAALAAECgIIAgAAAA==.',Go='Goyamonk:BAAALAAECgQIBQAAAA==.',Gr='Graha:BAAALAADCggIGAAAAA==.Grievz:BAAALAADCggIFgAAAA==.Grâham:BAAALAAECgMIBAAAAA==.',Ha='Hakubo:BAAALAAECgIIAgAAAA==.Hanabi:BAAALAADCggIEQAAAA==.Harcolepal:BAAALAAECgYICQAAAA==.',He='Healkekw:BAACLAAFFIEGAAIGAAMI0A5dAgDyAAAGAAMI0A5dAgDyAAAsAAQKgRYAAgYACAgdHJkFAIoCAAYACAgdHJkFAIoCAAAA.Hemøragie:BAAALAADCgYIBgAAAA==.',Hu='Huulk:BAABLAAECoEYAAMHAAgINR2QCQCkAgAHAAgINR2QCQCkAgAIAAUIyg9VNAAHAQAAAA==.',['Hà']='Hàkntoo:BAAALAADCggICQAAAA==.',['Hä']='Hädam:BAAALAAECgYIDwAAAA==.',['Hû']='Hûz:BAAALAAECgYIBgAAAA==.',Id='Idrana:BAAALAAECgIIBAAAAA==.',Il='Ilharend:BAAALAAECgcIEAAAAA==.',Ir='Irøh:BAAALAAECgYICgAAAA==.',Is='Isyar:BAAALAAECggIBQAAAA==.',Iw='Iwantpickles:BAAALAADCggIDQAAAA==.',Je='Jeanray:BAAALAAECgcIDgAAAA==.',Ju='Jupiterre:BAAALAADCgUIBQAAAA==.',Ka='Kagenou:BAAALAADCgcIDAAAAA==.Kahu:BAAALAAECgIIAgAAAA==.Kahulyne:BAAALAAECgMIBQAAAA==.Kame:BAAALAADCggICAAAAA==.Kapheria:BAAALAADCgQIBwAAAA==.Kasspard:BAAALAAECgEIAQAAAA==.',Ke='Keltia:BAAALAAECgEIAQAAAA==.',Kh='Khargun:BAAALAAECgMIBAAAAA==.',Kr='Krask:BAAALAAECggIDwAAAA==.',La='Laurelei:BAAALAAECgYICgAAAA==.Lawen:BAABLAAECoEWAAIGAAgIihojBwBcAgAGAAgIihojBwBcAgAAAA==.',Le='Legoret:BAABLAAECoEYAAIJAAgIjB24DACYAgAJAAgIjB24DACYAgAAAA==.Leroys:BAAALAAECgcIEQAAAA==.',Li='Lindä:BAAALAAECgIIAgAAAA==.Lirhia:BAAALAAECgMIBQAAAA==.Lirhïa:BAAALAADCgYIBgAAAA==.',Lo='Lostfire:BAAALAAECgYICQAAAA==.Louky:BAAALAAECgcIEQAAAA==.',['Lé']='Léa:BAAALAAECgEIAQAAAA==.',['Lê']='Lêøne:BAAALAADCggICAAAAA==.',['Lî']='Lîma:BAAALAAECgUICgAAAA==.',['Lï']='Lïrhia:BAAALAADCgYIBgAAAA==.',Ma='Makiard:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Makithar:BAAALAAECgIIAgAAAA==.Malan:BAAALAAECgYIDAAAAA==.Malendras:BAAALAADCgQIBAABLAAECgYIDAABAAAAAA==.Marionsilver:BAAALAAECgIIAgAAAA==.Martys:BAAALAADCgcIBwAAAA==.',Me='Meuuhrtrier:BAAALAADCgMIAwAAAA==.',Mh='Mhad:BAAALAADCgcICAAAAA==.',Mi='Minxicat:BAAALAADCgcIBwAAAA==.Miralith:BAAALAADCgcIBwAAAA==.Misenbière:BAAALAADCggICAAAAA==.Miskina:BAAALAADCgcICQAAAA==.',Mo='Moonn:BAAALAADCgIIAgAAAA==.Mortys:BAAALAADCgEIAQAAAA==.',Mu='Mukasan:BAAALAAECgMIAwAAAA==.Murmandus:BAAALAAECgYICQAAAA==.',My='Mylenfarmer:BAAALAADCgYIBgAAAA==.Myoren:BAAALAADCgUIBQAAAA==.Mythrandir:BAAALAADCgUIBQAAAA==.',Na='Nalik:BAAALAADCgIIAwAAAA==.Narzuol:BAAALAADCgEIAQAAAA==.Nashu:BAAALAADCggIDgAAAA==.',Ne='Nedraah:BAAALAADCgEIAQAAAA==.Nedraood:BAAALAAECgYIDgAAAA==.Neks:BAABLAAECoEXAAIKAAgIvyObAABOAwAKAAgIvyObAABOAwAAAA==.Nepthune:BAAALAADCgYIBgAAAA==.Nexoxcho:BAAALAADCgMIAwAAAA==.',Ni='Nialeem:BAAALAADCgYIEQAAAA==.',No='Norajeuh:BAAALAAECgYIBgAAAA==.',['Nã']='Nãthãdãn:BAAALAADCgcIFQAAAA==.',Om='Ombrecoeür:BAAALAADCggICQAAAA==.',Ox='Oxygene:BAABLAAECoEVAAILAAgIFyLfBQAuAwALAAgIFyLfBQAuAwAAAA==.Oxymoon:BAAALAAECgIIAgAAAA==.',Pa='Papylord:BAABLAAECoEYAAIMAAgIoiUEAgBsAwAMAAgIoiUEAgBsAwAAAA==.Pastille:BAAALAAECgMIBQAAAA==.',Ph='Phèos:BAAALAAECgYIDwAAAA==.Phéosc:BAAALAADCgcIBwAAAA==.',Py='Pyrokaid:BAABLAAECoEXAAINAAgIZSHZAwAOAwANAAgIZSHZAwAOAwAAAA==.',['Pà']='Pàïro:BAAALAAECgIIAgAAAA==.',Qu='Quinzalin:BAAALAADCgUIBQAAAA==.',Ra='Radamänthis:BAAALAADCgMIAwAAAA==.Raimbette:BAAALAADCggIDwABLAAECggIEwABAAAAAA==.Raimbettelb:BAAALAAECgYIDAABLAAECggIEwABAAAAAA==.Raimbo:BAAALAAECggIEwAAAA==.Raimboitboit:BAAALAADCggICAABLAAECggIEwABAAAAAA==.Randh:BAAALAADCggIDgAAAA==.Rayleroux:BAAALAAECgQIBAAAAA==.',Re='Ressmage:BAAALAAECgQIBgAAAA==.Rezlock:BAAALAAECgYICAAAAA==.',Ri='Riadryn:BAAALAAECgYICgABLAAECgUIBQABAAAAAA==.',Ro='Roltux:BAAALAADCgMIAwAAAA==.Rosase:BAABLAAECoEXAAMNAAgIvB0TCAC5AgANAAgIJxsTCAC5AgAOAAII9hzfEgCrAAAAAA==.',['Rø']='Røxxmane:BAAALAADCgIIAgABLAADCggICAABAAAAAA==.',Sa='Sadia:BAAALAAECgIIAgAAAA==.Sarkän:BAAALAAECgIIAgAAAA==.Sasukedusud:BAAALAAECgUIBwAAAA==.Sathanas:BAAALAADCgYIBwAAAA==.Saucemagique:BAAALAADCgUIBQAAAA==.',Sd='Sdk:BAAALAAECgYICQAAAA==.',Sh='Shaapplight:BAAALAAECgYIBgAAAA==.Shapeless:BAAALAADCggIDgAAAA==.Shilliew:BAAALAAECggIEQAAAA==.Shöwgun:BAAALAAECgEIAQAAAA==.',Si='Sigourneypog:BAAALAAECgQIBAAAAA==.Sipapi:BAAALAADCgEIAQAAAA==.Sisiclone:BAAALAAECgYIDgAAAA==.',Sk='Sken:BAAALAAECgMIAgAAAA==.Skipnøt:BAAALAAECgYICQAAAA==.',Sl='Slaiyer:BAAALAADCggICAAAAA==.',So='Soobin:BAAALAAECgYIDQAAAA==.Soobinmonk:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Soyun:BAABLAAECoEXAAMEAAgICRxRBQC5AgAEAAgICRxRBQC5AgAGAAgIngrrEACIAQAAAA==.',Sp='Spinningman:BAABLAAECoEUAAIEAAgIlR4zBQC9AgAEAAgIlR4zBQC9AgAAAA==.',St='Stendha:BAAALAAECgQIAwAAAA==.Sthaune:BAAALAAECgEIAQAAAA==.',Su='Sucecubes:BAAALAADCgUIBQAAAA==.Sucre:BAAALAAECgEIAQAAAA==.',['Sà']='Sàrkan:BAAALAAECgMIAwAAAA==.',['Sö']='Söcar:BAAALAADCggIDwAAAA==.Söcär:BAAALAADCgcICgAAAA==.',Ta='Tanataus:BAAALAADCgcIEwAAAA==.Tanka:BAAALAAECgMIAwAAAA==.',Te='Teikashî:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Temasham:BAAALAADCgMIAwAAAA==.',Th='Thorny:BAAALAAECgcICQAAAA==.Thôrgull:BAAALAADCgEIAQABLAADCggIFwABAAAAAA==.Thörgull:BAAALAADCggIFwAAAA==.',Ti='Tiliate:BAABLAAECoEUAAMJAAYITRKWKACPAQAJAAYILhGWKACPAQAPAAUIpBIxIwBSAQAAAA==.',Tr='Trollveld:BAAALAADCgQIBAAAAA==.',Tw='Twihades:BAAALAAECggIDAAAAA==.Twipluton:BAAALAAECggICAAAAA==.',['Tî']='Tîtîbökä:BAAALAADCgcIEwAAAA==.',['Tö']='Tök:BAABLAAECoEVAAMQAAgIYBJrFwAFAgAQAAgIYBJrFwAFAgARAAQI5ASGDwC6AAAAAA==.',Ul='Ulithi:BAAALAAECgEIAQAAAA==.',Un='Unrahcsinep:BAAALAADCgcICAABLAADCggICAABAAAAAA==.',Ut='Utøpiate:BAAALAADCgEIAQAAAA==.',Va='Valaryn:BAAALAADCggICAAAAA==.Valkiør:BAAALAAECgMIAwAAAA==.',Ve='Veldou:BAABLAAECoEWAAISAAgI7x95BACcAgASAAgI7x95BACcAgAAAA==.Veldzor:BAAALAADCgUIAwAAAA==.Verhana:BAAALAADCgYIBwAAAA==.Vermithor:BAAALAAECgYICQAAAA==.',Xe='Xendraka:BAAALAADCgEIAQAAAA==.',Yd='Ydrisse:BAAALAAECgMIBQAAAA==.',Yi='Yinmái:BAAALAADCggICAAAAA==.',Yo='Yoggsarocrow:BAABLAAECoEVAAITAAgIwxxyCgCxAgATAAgIwxxyCgCxAgAAAA==.',Ys='Ysiia:BAAALAADCgYIBgAAAA==.Ysyh:BAAALAADCgYIBgAAAA==.',Yu='Yurraah:BAAALAADCgYIBgAAAA==.',Za='Zadarthas:BAAALAAECgIIAgAAAA==.Zadormu:BAAALAADCggICAAAAA==.Zarocrow:BAABLAAECoEVAAILAAgIKiT8BAA6AwALAAgIKiT8BAA6AwAAAA==.',Ze='Zeki:BAAALAADCgQIBAAAAA==.Zerazera:BAAALAAECgMIBQAAAA==.',Zh='Zhëf:BAAALAADCgMIAwAAAA==.',Zi='Zinphéa:BAABLAAECoEVAAMFAAgIrCLXCQDqAgAFAAgIFx/XCQDqAgAUAAYINCBGCADxAQAAAA==.Zizanie:BAAALAAECgMIAwAAAA==.',Zo='Zoomback:BAAALAADCggIEAAAAA==.Zoomevo:BAAALAAECgcIEAAAAA==.Zoomojo:BAAALAAECgcIDAAAAA==.Zorica:BAAALAAECgEIAgAAAA==.Zoømette:BAAALAADCggIEAAAAA==.',['Ân']='Ânéâ:BAAALAAECgcIDgAAAA==.',['Äd']='Ädam:BAAALAADCggICAAAAA==.',['Îr']='Îragnir:BAAALAAECgYICwAAAA==.Îragnîr:BAAALAADCggICAABLAAECgYICwABAAAAAA==.',['Õl']='Õlæya:BAAALAADCgcICgAAAA==.',['Øg']='Øgami:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end