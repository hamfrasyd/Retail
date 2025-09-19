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
 local lookup = {'Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Priest-Shadow','Warrior-Fury','DeathKnight-Frost','Mage-Frost','Shaman-Elemental','Shaman-Enhancement','Priest-Holy','DemonHunter-Havoc','Shaman-Restoration',}; local provider = {region='EU',realm='Anachronos',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Achmethax:BAAALAAECgEIAQAAAA==.Ackles:BAAALAADCgMIAwAAAA==.',Ad='Admon:BAAALAAECggICAAAAA==.',Ae='Aegyptus:BAAALAAECgYIBgAAAA==.',Ag='Aginor:BAAALAAECgIIAgAAAA==.Agnitio:BAAALAAECgYICwAAAA==.Agnuks:BAAALAAECgUICwAAAA==.',Ai='Airetta:BAAALAAECgMIBQAAAA==.Aitarel:BAAALAAECgMIBQAAAA==.',An='Andicon:BAAALAADCgcIEwAAAA==.',As='Ashbringer:BAAALAADCgcIBwAAAA==.Ashimmu:BAAALAAECgYIDwAAAA==.Asura:BAAALAAECgYIDAAAAA==.',At='Attanocorvo:BAAALAADCggICQAAAA==.',Av='Avery:BAAALAAECgcIEgAAAA==.',Ba='Baka:BAAALAAECgYICgAAAA==.Batoutofhell:BAAALAADCggIDQAAAA==.',Be='Bernch:BAAALAAECgMIBAAAAA==.',Bg='Bg:BAAALAAECgYIBgAAAA==.',Bj='Bjerg:BAAALAADCgIIAgABLAAECgYIDgABAAAAAA==.',Bo='Bones:BAAALAADCggICAAAAA==.',Br='Bradnir:BAAALAAECgYIAwAAAA==.Brightlight:BAAALAADCggICgAAAA==.Bronne:BAAALAADCgEIAQAAAA==.Broulin:BAAALAAECgYICgAAAA==.Bruk:BAAALAAECgYICwAAAA==.',Bs='Bsugarri:BAAALAADCgIIAgAAAA==.',Bu='Bugyertem:BAAALAAECgYIBgAAAA==.',Ca='Cambridgelol:BAAALAAFFAIIBAAAAA==.Carzzy:BAAALAAECgYIDgAAAA==.',Ce='Cessator:BAAALAAECgQIBAAAAA==.',Ch='Chaosprime:BAAALAADCgIIAgAAAA==.Chizx:BAAALAAECgUICQAAAA==.Chéznéy:BAAALAAECgMIBQAAAA==.',Da='Dalt:BAABLAAECoEaAAICAAcIxBx7CgBbAgACAAcIxBx7CgBbAgAAAA==.Daltanyan:BAAALAADCgYIBgAAAA==.Dalthazar:BAAALAAECgMIAwABLAAECgcIGgACAMQcAA==.Darla:BAAALAADCggICAAAAA==.',Dd='Ddraigfach:BAAALAAECgEIAQAAAA==.',De='Deadlycalm:BAAALAAECgIIAwAAAA==.Deftly:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Dev:BAAALAAECgcIDgAAAA==.',Di='Dikoos:BAAALAAECgcIEQAAAA==.',Do='Doks:BAAALAADCgIIAgAAAA==.',Dr='Drypp:BAAALAADCgUICAAAAA==.',['Dé']='Dérpington:BAAALAAECgQIBAAAAA==.',Ec='Ecarus:BAAALAAFFAIIAgAAAA==.',Ed='Edéa:BAAALAADCgcICQAAAA==.',El='Elans:BAAALAADCggIDgAAAA==.Elnuzard:BAAALAADCgMIAwAAAA==.Elogis:BAAALAAECgUICwAAAA==.Elvenmageo:BAAALAAFFAIIAgAAAA==.',Er='Ert:BAAALAADCgQIBAABLAADCgUICAABAAAAAA==.',Es='Especti:BAAALAAECgYICwAAAA==.',Fa='Fano:BAAALAAECgYIDgAAAA==.',Fe='Feck:BAAALAADCgUIBQAAAA==.',Fo='Foul:BAAALAAECgUIBQAAAA==.',Fr='Frazelbur:BAAALAADCgYIBgAAAA==.Fraztid:BAAALAADCgcIBwAAAA==.Frosthammer:BAAALAAECgUICAAAAA==.',Fu='Furìous:BAAALAAECgEIAQABLAAECggIIQADAEMlAA==.',Fx='Fxw:BAAALAAECgMIAwAAAA==.',Fy='Fyrun:BAAALAADCgIIAgAAAA==.',Ga='Gambrinus:BAAALAAECgMIBAAAAA==.',Ge='Gematría:BAAALAAECgYICwAAAA==.Gembersnor:BAAALAADCggICAAAAA==.',Gh='Ghorda:BAAALAAECgcIBwAAAA==.',Gi='Gigah:BAAALAAECggICgAAAA==.',Gj='Gjørmebrytar:BAAALAADCgMIAwABLAADCgUICAABAAAAAA==.',Gl='Glacial:BAAALAADCgEIAQABLAAECggIIQADAEMlAA==.',Go='Gorihrgrom:BAAALAADCgIIAgABLAADCgQIBAABAAAAAA==.Gourtcool:BAEALAAECggICAAAAA==.',Gr='Graninza:BAAALAADCgYICQAAAA==.Grimn:BAAALAAECgcIDgAAAA==.Grizlyadams:BAAALAAECgUICwAAAA==.',Ha='Habrok:BAAALAAECgcIEQAAAA==.Hamaya:BAAALAAECgYIDAAAAA==.Harríe:BAAALAADCggICQAAAA==.',He='Heck:BAAALAAECgYICwAAAA==.Hempuma:BAAALAAECgcICgAAAA==.Henno:BAAALAAECggICQAAAA==.',Ho='Honeywell:BAAALAAECgcICgAAAA==.',Ij='Ijin:BAAALAAECgQIBAAAAA==.',It='Itshal:BAAALAAECgMIBgAAAA==.',Ja='Jaythedruid:BAAALAAECgUICQAAAA==.',Je='Jeeralt:BAAALAAECggICgAAAA==.',Ju='Jump:BAAALAADCggICAAAAA==.',Ka='Kartara:BAAALAADCgYIBgAAAA==.',Ke='Keomo:BAAALAAECgYIDwAAAA==.Ketdrinker:BAAALAAECggIDgAAAA==.',Ki='Kierang:BAAALAAECgcIDQAAAA==.',Kn='Knotwell:BAAALAADCgUIBQAAAA==.',Kr='Krassix:BAAALAAECgMIBAAAAA==.',Ky='Kyariek:BAAALAAECgYIDQAAAA==.Kyxobype:BAAALAAECgYIBwAAAA==.',La='Lapianos:BAAALAADCgcIGAAAAA==.Lazam:BAAALAADCggIDgAAAA==.',Le='Leelu:BAAALAAECgYIBwABLAAECgcIDgABAAAAAA==.',Li='Liath:BAAALAADCggIBwAAAA==.Lilkitsune:BAAALAAECgYIDAAAAA==.Liuzhigang:BAAALAAECggIEAAAAA==.',Lu='Lutharii:BAAALAADCgcIBwAAAA==.',['Lí']='Líghtbringer:BAAALAAECgMIBAAAAA==.',Ma='Manson:BAAALAAECgYICgAAAA==.Mattdraclock:BAAALAAECgYIDAAAAA==.Mavric:BAAALAADCgcIDAAAAA==.',Me='Meggy:BAAALAAECgEIAQAAAA==.Menor:BAAALAADCggIFQAAAA==.',Mg='Mgd:BAAALAAECggICAAAAA==.',Mi='Mikra:BAAALAAECgYIDwAAAA==.Misiolkin:BAAALAAECgYICwAAAA==.Mitta:BAAALAAECgYIDAAAAA==.',Mj='Mjøll:BAAALAAECgcIDgAAAA==.',Mo='Mokum:BAAALAADCggIFQAAAA==.Monica:BAAALAAECgYIDAAAAA==.Morgenfruen:BAAALAAECgYIDQAAAA==.',Mp='Mpalanteza:BAAALAADCgUIBQAAAA==.',My='Mykernios:BAAALAADCgcIDwAAAA==.Mypetiswet:BAAALAADCgEIAQAAAA==.Mystry:BAAALAAECgUICwAAAA==.',Na='Nameless:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Napierniczak:BAAALAADCggICAAAAA==.Naravi:BAAALAADCgcICQAAAA==.Naturestar:BAAALAAECgYIDAAAAA==.',Ne='Nebring:BAAALAADCgQIBAAAAA==.',Ni='Nivd:BAAALAADCggICAAAAA==.',No='Nocent:BAAALAADCggICAAAAA==.Nocturm:BAAALAADCgMIAwAAAA==.Nohe:BAAALAADCggIDAAAAA==.Nowan:BAAALAADCgYIBgAAAA==.',Nu='Nueleth:BAAALAADCgUIBQABLAADCggIFgABAAAAAA==.',['Nè']='Nèmesis:BAAALAADCgYIDAAAAA==.',On='Onefistyboy:BAAALAADCggIEAAAAA==.',Op='Opheliah:BAAALAAECgMIBAAAAA==.',Pa='Palladan:BAABLAAECoEhAAIDAAgIQyXlAgBsAwADAAgIQyXlAgBsAwAAAA==.Pandatings:BAAALAADCggICAAAAA==.',Pl='Plush:BAAALAAECgYICgAAAA==.',Po='Porcia:BAAALAAECgMIBQAAAA==.',Pr='Príesty:BAABLAAECoEUAAIEAAYI1BO0LwCBAQAEAAYI1BO0LwCBAQAAAA==.',Ps='Psirens:BAAALAAECgYICwAAAA==.',Qy='Qysa:BAAALAAECgYICgAAAA==.',Ra='Radhoc:BAAALAADCgcICQAAAA==.Raktrak:BAAALAADCgcIBwAAAA==.Rambôô:BAAALAAECgQICwAAAA==.Ranna:BAAALAAECgYIEAAAAA==.',Re='Redbeardd:BAAALAAECgcIEAAAAA==.Reeko:BAAALAAECgYIDwAAAQ==.Renascentia:BAAALAADCgQIBAAAAA==.Rendoniss:BAAALAAECgcIDQAAAA==.',Rh='Rhoald:BAABLAAECoEfAAIFAAcINB3TGABVAgAFAAcINB3TGABVAgAAAA==.',Ro='Rothcore:BAAALAAECgcIEQAAAA==.',Ru='Ruinedk:BAABLAAECoEXAAIGAAgIVh0IEgDLAgAGAAgIVh0IEgDLAgAAAA==.Ruinersback:BAAALAAECgUICQAAAA==.Russell:BAAALAAECgcIDgAAAA==.',['Ré']='Rémus:BAAALAADCgYICgAAAA==.',Sa='Santaverde:BAAALAADCggICAAAAA==.Saphaera:BAAALAADCggIDwAAAA==.',Se='Sebej:BAAALAADCgIIAgAAAA==.Seraphena:BAAALAADCgMIAwAAAA==.Serinity:BAAALAAECgMIBAAAAA==.Serpez:BAAALAAECgMIAwAAAA==.',Sh='Shaggyrogers:BAAALAADCgUIBQAAAA==.',Sj='Sjager:BAAALAAECgYIDwAAAA==.',Sk='Skopeutis:BAAALAADCgUIBQAAAA==.',Sl='Slayersboxer:BAAALAAECgEIAQAAAA==.',Sm='Smeister:BAABLAAECoEYAAIHAAcIRyTJBgDIAgAHAAcIRyTJBgDIAgAAAA==.',Sn='Sniggles:BAABLAAECoEWAAIIAAgIHxbZGgA7AgAIAAgIHxbZGgA7AgAAAA==.Sniperspeed:BAAALAADCgcIBwAAAA==.Snuiter:BAAALAADCgYIBgAAAA==.',So='Soldshort:BAAALAADCggICAAAAA==.Soothy:BAAALAAECgYICgAAAA==.',Sp='Spartalock:BAAALAAECgYICwAAAA==.Spiritivan:BAAALAADCggICgAAAA==.',St='Stamos:BAAALAADCgcIBwAAAA==.Stevie:BAAALAAECgYICwAAAA==.',Ta='Taihuntsham:BAAALAAECgYIDAAAAA==.Targhor:BAAALAADCgMIBAAAAA==.',Th='Thalcorn:BAAALAADCggICAAAAA==.Thelsennos:BAAALAADCgMIAwAAAA==.Thorí:BAAALAADCgUIBQAAAA==.Thristy:BAAALAAECgEIAQAAAA==.Thórinal:BAAALAADCgYIBgAAAA==.',Ti='Titanmage:BAAALAADCgEIAQAAAA==.',To='Tolmyr:BAAALAADCgQIBAAAAA==.',Tr='Traci:BAAALAADCggICAAAAA==.Tru:BAAALAADCgcIDgABLAAECggIFgAJAM0QAA==.',Tu='Turowai:BAAALAAECgQICwAAAA==.',Tw='Twocancarl:BAAALAAECgcIEAAAAA==.',Ty='Tyarah:BAAALAAECgMIBAABLAAECgMIBAABAAAAAA==.',Uk='Ukitake:BAAALAAECggIAwAAAA==.',Ur='Ursur:BAAALAADCgcIBwAAAA==.',Va='Vaes:BAABLAAECoEYAAMKAAcI2h1jEwBkAgAKAAcI2h1jEwBkAgAEAAEI4QG3aAAqAAAAAA==.Vandejoa:BAAALAAECgMIAQAAAA==.Vayne:BAAALAAECgUICwAAAA==.',Ve='Velver:BAAALAADCggIEwAAAA==.Velvor:BAAALAADCggIDwAAAA==.Venakros:BAABLAAECoEaAAILAAgI4CACFwCmAgALAAgI4CACFwCmAgAAAA==.Ventaros:BAAALAAECgYICwABLAAECggIGgALAOAgAA==.',Vi='Vinnsanity:BAAALAAECgUIBQABLAAECgYIDwABAAAAAA==.Vinzen:BAAALAAECgYIBgABLAAECgYIDwABAAAAAA==.Viosback:BAAALAADCgcIBwAAAA==.Viserionn:BAABLAAECoEUAAIMAAgIDBYbIwABAgAMAAgIDBYbIwABAgAAAA==.Vitorios:BAAALAAECgUICgAAAA==.Vivian:BAAALAADCggIFgAAAA==.',Vo='Volara:BAAALAAECgYICgAAAA==.Voltaran:BAAALAAECgEIAQAAAA==.Vonji:BAAALAAECgYIDAAAAA==.',Vr='Vredna:BAAALAAECgQIBQAAAA==.',Wa='Warren:BAAALAAECgYIDAAAAA==.Warwithin:BAAALAADCggICAAAAA==.',Xe='Xenastraza:BAAALAAECgYIBgAAAA==.',Xh='Xharin:BAAALAAECgMIBgAAAA==.',Xl='Xlzm:BAAALAAECgUIDAAAAA==.',Yu='Yugbertem:BAAALAAECgMIAwAAAA==.',Ze='Zerant:BAAALAAECgMIBAAAAA==.',Zi='Ziekgast:BAAALAADCggICAAAAA==.Zilvèr:BAAALAADCggIDwAAAA==.Zim:BAAALAAECgYICAAAAA==.',['Ár']='Árthas:BAAALAAECgcICgABLAAECggIIQADAEMlAA==.',['Îs']='Îshtar:BAAALAADCggICwAAAA==.',['Ðr']='Ðrudict:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end