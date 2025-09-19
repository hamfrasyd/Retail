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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','Druid-Restoration','Druid-Balance','Mage-Frost','Paladin-Protection','Paladin-Retribution','DeathKnight-Blood','DeathKnight-Frost',}; local provider = {region='EU',realm="C'Thun",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abraxass:BAAALAAECgcIDwABLAAECggIDgABAAAAAA==.',Ac='Acu:BAAALAADCggICAAAAA==.',Ae='Aegnis:BAAALAADCggICgABLAAECgUICQABAAAAAA==.Aeseaix:BAAALAAECgIIAgAAAA==.',Ag='Agera:BAAALAADCggICAAAAA==.',Ah='Ah:BAAALAAECgYIDAAAAA==.Ahrikel:BAAALAAECgMIAwAAAA==.',Ai='Airike:BAAALAADCgIIAQAAAA==.',Ak='Akelmatonll:BAAALAADCgIIAgAAAA==.Akihima:BAAALAAECgMIAwAAAA==.Akora:BAAALAADCggICQAAAA==.',Al='Alcair:BAAALAADCgQIBQAAAA==.Aldarks:BAAALAAECgUICQAAAA==.Aldraneth:BAAALAADCgcIBwAAAA==.Aldred:BAAALAADCgYIDAABLAADCggICAABAAAAAA==.Alecsandru:BAAALAAECgYIDAAAAA==.Aleindra:BAAALAAECgYIDAAAAA==.Aliennax:BAAALAADCgMIAwAAAA==.Althaix:BAAALAAECgYIDQAAAA==.Altrius:BAAALAAECgYIDwAAAA==.',Am='Amaranthae:BAAALAAECgMIBQAAAA==.Amaya:BAAALAAECgEIAgAAAA==.',An='Anfítrite:BAAALAAECgYIDAAAAA==.Anggra:BAAALAAECgYIDAAAAA==.Anira:BAAALAAECgMIBQAAAA==.Anraweth:BAAALAADCggICAAAAA==.Anthol:BAAALAADCggIDgAAAA==.',Ap='Apañao:BAAALAADCgYIBgAAAA==.Aphyx:BAAALAAECggICwAAAA==.Apolö:BAAALAADCgYICgAAAA==.',Ar='Aragør:BAAALAAECgMIBgAAAA==.Aranoth:BAAALAAECgUIBwAAAA==.Ark:BAAALAADCgIIAwAAAA==.Arkanïa:BAAALAADCgEIAQAAAA==.Artios:BAAALAAECgEIAQAAAA==.Artisia:BAAALAAECgYICQAAAA==.',As='Asabear:BAAALAADCggIDAAAAA==.Assist:BAAALAAECgcIEwAAAA==.Astenos:BAAALAAECgQIBgAAAA==.Astherod:BAAALAADCgEIAQAAAA==.Astrack:BAAALAAFFAEIAQAAAA==.Astrelios:BAAALAAECgcIEAAAAA==.',At='Atracaviejas:BAAALAAECgIIAgAAAA==.Atrancao:BAAALAAECgQIBwAAAA==.',Au='Aughustor:BAAALAADCgcICgAAAA==.',Av='Avice:BAAALAAECgMIAwAAAA==.',Aw='Awowa:BAAALAADCgcIDQAAAA==.',Ay='Aymicuqui:BAAALAADCgEIAQAAAA==.',Ba='Badguial:BAAALAADCgYIBgAAAA==.Bagzhul:BAAALAADCggICAAAAA==.Bakaret:BAAALAAECgYIBgAAAA==.Batusais:BAAALAADCgcICgAAAA==.',Be='Beastwhisper:BAAALAAECgYIDgAAAA==.Bedesemé:BAAALAAECgMIAwAAAA==.Berciano:BAAALAAECggIBAAAAA==.Betrayër:BAAALAAECgEIAQAAAA==.',Bi='Biøzahar:BAAALAADCgYICQAAAA==.',Bl='Blighträwler:BAAALAAECgMIAwAAAA==.Blxuuff:BAAALAAECgcICgAAAA==.Blöodhorn:BAAALAADCgQIBAABLAADCggICAABAAAAAA==.',Bo='Bolaschami:BAAALAADCgMIAwAAAA==.Boromirip:BAAALAADCggIGAABLAAECgYICgABAAAAAA==.',Br='Bridion:BAAALAADCgcIDQAAAA==.Brightbull:BAAALAAECgYIDwAAAA==.Bromon:BAAALAADCgEIAQAAAA==.Broto:BAAALAAECgYIDAABLAAECgYIDAABAAAAAA==.Bròx:BAAALAADCggICAAAAA==.',Bu='Buini:BAAALAADCggIEAAAAA==.Bulti:BAAALAAECgYICgAAAA==.',By='By:BAAALAADCggIFQAAAA==.',['Bá']='Bárdáck:BAAALAADCggIEAAAAA==.',['Bë']='Bëlzër:BAAALAAECgcIDwAAAA==.',['Bô']='Bôu:BAAALAAECgYIBwAAAA==.',Ca='Cal:BAAALAADCggIDQAAAA==.Caminantë:BAAALAADCgcIBwAAAA==.Cazadiablas:BAAALAADCgcIBwAAAA==.Caëlynn:BAAALAAECgUIBQAAAA==.',Ce='Cegorach:BAAALAAECggIDAAAAA==.',Ch='Chaalswar:BAAALAADCggIDAAAAA==.Chamankito:BAAALAAECgcIEwAAAA==.Chantajista:BAAALAADCggICgAAAA==.Chesmú:BAAALAAECgEIAQAAAA==.Chiban:BAABLAAECoEWAAICAAgInhNiCwDzAQACAAgInhNiCwDzAQAAAA==.Chloe:BAAALAADCgEIAQAAAA==.Chofa:BAAALAADCggIDQAAAA==.Chogronios:BAAALAAECggIBgAAAA==.Christinne:BAAALAADCgcIAgAAAA==.Chulinorris:BAAALAAECgYIBgAAAA==.',Cl='Claric:BAAALAADCgcICgAAAA==.',Co='Cornelyus:BAAALAADCggICAAAAA==.Correita:BAAALAADCgEIAQAAAA==.',Cr='Crahal:BAAALAAECgYIDAAAAA==.Croquet:BAAALAADCgQIBAAAAA==.Croquetank:BAAALAAECgMIBQAAAA==.Croquetero:BAAALAADCggICAAAAA==.Crowgreen:BAAALAAECgIIAwAAAA==.',Cy='Cyperz:BAAALAAECgIIAgAAAA==.',Da='Daeme:BAAALAAECgIIAgAAAA==.Dagörlad:BAAALAADCgcIBwAAAA==.Damya:BAAALAADCgcIBwAAAA==.Daremy:BAAALAADCggIDgAAAA==.Darkanglical:BAAALAADCgcIBwABLAAECgIIBAABAAAAAA==.Darkdelius:BAAALAADCgcIDAAAAA==.Darkest:BAABLAAECoEWAAMDAAgIICFZBQC2AgADAAgIICFZBQC2AgAEAAEIVxNSSwBFAAAAAA==.Darkkest:BAAALAAECgYICwAAAA==.Daveria:BAAALAAECgUICAAAAA==.Davithorn:BAAALAAECgYIEAAAAA==.Dayhun:BAAALAAECgMIAwAAAA==.',De='Deadpapu:BAAALAADCgcIBwAAAA==.Deedlyt:BAAALAADCgMIAwAAAA==.Dehache:BAAALAADCgcIDQAAAA==.Demonblack:BAAALAAECgMIBAAAAA==.Demongronios:BAAALAAECgIIAgABLAAECggIBgABAAAAAA==.Demonrekt:BAAALAAECgYIDgAAAA==.Denthe:BAAALAADCgcIBwAAAA==.',Dh='Dhuke:BAAALAAECgUIBQAAAA==.',Di='Dikon:BAAALAAECgcIDgAAAA==.Direlia:BAAALAADCggICQAAAA==.Dirial:BAAALAAECgUICAAAAA==.Disc:BAAALAADCggICwAAAA==.Diyö:BAAALAADCgYIBgAAAA==.',Dk='Dktronico:BAAALAADCgUIBQAAAA==.',Do='Dornoan:BAAALAADCgQIBAAAAA==.Dosgran:BAAALAAECgEIAQAAAA==.',Dr='Dracojones:BAAALAAECgYIDAAAAA==.Draebel:BAAALAAECgIIAgAAAA==.Drajl:BAAALAAECgMIAwAAAA==.Drakës:BAAALAAECgMIBAAAAA==.Dratum:BAAALAADCgMIAwAAAA==.',Ds='Dsiefus:BAAALAAECgYIDgAAAA==.',Du='Dustin:BAAALAAECgYICQAAAA==.',['Dà']='Dànte:BAAALAAECgMIBAABLAAECgYIDAABAAAAAA==.',['Dä']='Dämonenjäger:BAAALAAECgYIBgAAAA==.',['Dü']='Dürck:BAAALAAECgIIAgAAAA==.',Ea='Ealzar:BAAALAAECgMIBAAAAA==.Earieal:BAAALAAECgUICAAAAA==.',Ek='Ekilibrio:BAAALAADCgQIBAABLAAECggIDgABAAAAAA==.Ekilibrïo:BAAALAAECggIDgAAAA==.Eko:BAAALAAECgIIBAAAAA==.',El='Eldorodwën:BAAALAAECgIIAgAAAA==.Elegía:BAAALAADCgcIEAAAAA==.Elektrá:BAAALAADCgYIEgAAAA==.Elledor:BAAALAAECgYIDwAAAA==.Elrot:BAAALAADCgcIBwAAAA==.Elyeti:BAAALAADCgQIBAAAAA==.',En='Enjoyme:BAAALAAECgYIEQAAAA==.',Eo='Eodín:BAAALAAECggIDAAAAA==.',Er='Erdun:BAAALAADCgcIBwAAAA==.Erpàla:BAAALAADCgYIBgAAAA==.',Es='Eskeletör:BAAALAAECgIIAgAAAA==.',Ev='Everdreaming:BAAALAADCgQIBAAAAA==.Evolëth:BAAALAAECgIIAgAAAA==.',Ey='Eywen:BAAALAAECgMIBwAAAA==.',Ez='Eziamxz:BAAALAAECgcIDQAAAA==.Eziaxx:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.Ezil:BAAALAADCggICgAAAA==.',['Eí']='Eíko:BAAALAAECgMIBgAAAA==.',Fa='Fautis:BAAALAAECgYICwAAAA==.',Fh='Fhenriel:BAAALAAECgMIBQAAAA==.',Fi='Fierainfame:BAAALAAECgMIBQAAAA==.',Fl='Flappas:BAAALAADCgIIAgAAAA==.Flexas:BAAALAADCggICAAAAA==.',Fo='Forota:BAAALAAECgIIAgAAAA==.Forzudo:BAAALAAECgIIAgAAAA==.',Fr='Frattus:BAAALAAECgUIBgAAAA==.Frizhy:BAAALAADCgcICQAAAA==.Frostboy:BAAALAAECgIIBAAAAA==.Fryan:BAAALAAECgYIBwAAAA==.',Fu='Fumanxi:BAAALAADCgcIBwAAAA==.',Ga='Gambiterô:BAAALAADCgMIAwAAAA==.Gangurojack:BAAALAAECgcIDAAAAA==.Gathïta:BAAALAADCgcIBwAAAA==.',Ge='Geølul:BAAALAAECgIIAgAAAA==.',Gh='Ghorck:BAAALAADCgcIBwAAAA==.',Gi='Gilberto:BAAALAAECgYICAAAAA==.Giuly:BAAALAAECgYICQAAAA==.',Go='Gogueta:BAAALAADCggICAAAAA==.Goldenfast:BAAALAAECgYICgAAAA==.Gordepon:BAAALAAECgMIAwAAAA==.Goudy:BAAALAADCggIDwAAAA==.',Gr='Grengal:BAAALAADCgcIBwAAAA==.Grisalvo:BAAALAAECgIIAgAAAA==.Gromthul:BAAALAADCggIEgAAAA==.Groniboosted:BAAALAAECgIIAgABLAAECggIBgABAAAAAA==.Groniosh:BAAALAAECgIIAgABLAAECggIBgABAAAAAA==.',Gu='Gumnuts:BAAALAADCgYIBwAAAA==.',['Gä']='Gänjahgirl:BAAALAADCggICAAAAA==.',Ha='Hamletstoner:BAAALAAECgYIBQAAAA==.Harlok:BAAALAADCgYIAwAAAA==.',He='Healdebaño:BAAALAAECgIIAgAAAA==.Helssipanki:BAAALAADCgQIBAAAAA==.',Hi='Higueron:BAAALAAECgYICAAAAA==.Hilfhëim:BAAALAAECgIIAQAAAA==.Hitoribocchi:BAAALAAECgIIAwAAAA==.',Ho='Hoverangied:BAAALAADCggICAAAAA==.',Hu='Hurnar:BAAALAADCgEIAQAAAA==.',Hy='Hyoudouissei:BAAALAADCggICQAAAA==.',['Hï']='Hïncapie:BAAALAADCgYIBgAAAA==.',Ia='Ianto:BAAALAAECgYIDAAAAA==.Iaän:BAAALAADCggIDAAAAA==.',Ic='Ichiban:BAAALAAECgYIBwAAAA==.Ichigokuros:BAAALAAECgMIBgAAAA==.',Id='Idral:BAAALAAECgEIAQAAAA==.',Il='Illidaen:BAAALAADCgUIBQAAAA==.Illucia:BAAALAADCggICAABLAAECgIIBAABAAAAAA==.',In='Inerias:BAAALAAECgQIBAAAAA==.Inserin:BAAALAAECgMIBAAAAA==.Invokados:BAAALAAECggIEAAAAA==.',Is='Ishla:BAAALAAECgIIAgAAAA==.',Iv='Ivanuno:BAAALAAECgcIBwAAAA==.',Iz='Izabella:BAAALAAECgEIAQAAAA==.',Ja='Jamonero:BAAALAAECgYICwAAAA==.Jarthur:BAAALAADCgYIBwAAAA==.',Jb='Jbelix:BAAALAAECgIIAgAAAA==.',Jh='Jhaina:BAAALAAECgMIAwAAAA==.',Ji='Jimmyjazz:BAAALAAECgYICQAAAA==.Jinu:BAAALAADCgQIBAAAAA==.',Jo='Joramun:BAAALAAECgIIAgAAAA==.Josefer:BAAALAAECgIIAgAAAA==.Joselitolito:BAAALAADCggICAAAAA==.',Ju='Juliá:BAAALAADCggIDwABLAAECgYICQABAAAAAA==.Junetemple:BAAALAADCgIIAgAAAA==.',Ka='Kabnier:BAAALAAECgMIBgAAAA==.Kaekkuga:BAAALAADCgIIAgAAAA==.Kaeltzin:BAAALAAECgYIDQAAAA==.Kaensoy:BAAALAAECgYIAQAAAA==.Kaori:BAAALAADCgUIBQABLAAECgUICQABAAAAAA==.Kaveleira:BAAALAAECgYICwAAAA==.Kazito:BAAALAAECgYIDwAAAA==.',Kd='Kdott:BAAALAADCgcIBwAAAA==.',Ke='Kefeu:BAAALAAECgYICQAAAA==.Kelfôr:BAABLAAECoEVAAIFAAgIDhljCQBMAgAFAAgIDhljCQBMAgAAAA==.',Kh='Khari:BAAALAADCgMIAwAAAA==.Khatmul:BAAALAADCgYIBgAAAA==.Khido:BAAALAAECgYIEQAAAA==.',Ki='Kikiko:BAAALAADCgcICAABLAAECgMIAwABAAAAAA==.Kimpow:BAAALAAECgIIAwAAAA==.Kirutasu:BAAALAAECgYIDwAAAA==.',Ko='Kopernikoo:BAAALAADCgIIAgAAAA==.Kouga:BAAALAAECgUICgAAAA==.',Kr='Kraelight:BAAALAAECgYICAAAAA==.Krumell:BAAALAAECgYIDQAAAA==.Kràms:BAAALAAFFAEIAQABLAAFFAIIBAABAAAAAA==.Kráms:BAAALAAECgYIDAABLAAFFAIIBAABAAAAAA==.Krýstal:BAAALAADCgEIAQAAAA==.',Ku='Kurohigexz:BAAALAAECgYICAABLAAECgcIEwABAAAAAA==.',Ky='Kyai:BAAALAAECgEIAQAAAA==.',['Ká']='Kálem:BAAALAADCgcIBwAAAA==.',['Kä']='Kästiel:BAAALAAECgYIEAAAAA==.',La='Lahar:BAAALAADCgYIBgAAAA==.Larosalïa:BAABLAAECoEWAAIFAAcIRRXEDQADAgAFAAcIRRXEDQADAgAAAA==.Laurademomio:BAAALAADCggICAAAAA==.Laurilla:BAAALAADCgUIBQAAAA==.',Le='Lexxâ:BAAALAAECgEIAQAAAA==.Leyvaman:BAAALAAECgYIBgAAAA==.Leyvarthas:BAAALAAECgcIEQAAAA==.',Li='Liadren:BAAALAAECgcIDAAAAA==.',Ll='Llagas:BAAALAAECgIIBAAAAA==.Llarth:BAAALAADCgMIAwAAAA==.',Lo='Lodh:BAAALAAECgIIAgABLAAECgMIBgABAAAAAA==.Louisse:BAAALAAECgUICgAAAA==.',Lu='Luckyluckk:BAAALAAECgUICQAAAA==.Lulianna:BAAALAADCggICAAAAA==.',Ly='Lysh:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.Lyshh:BAAALAAECgcIDQAAAA==.',['Lâ']='Lâiâ:BAAALAAECgYIDAAAAA==.',Ma='Macri:BAAALAADCggICAAAAA==.Malrek:BAAALAADCggIGAAAAA==.Mamporrazos:BAAALAAECgcIEAAAAA==.Mankramszony:BAAALAAFFAIIBAAAAA==.Marianh:BAAALAAECgYIDwAAAA==.Matajonkies:BAAALAAECgEIAQAAAA==.Matariel:BAAALAAECgIIAgAAAA==.Matildi:BAAALAADCgcIBwAAAA==.Mavys:BAAALAAECgMIBAAAAA==.',Me='Meeherah:BAAALAADCgEIAQAAAA==.Meganeo:BAAALAADCgUIBQAAAA==.Melkör:BAAALAADCgcIFQAAAA==.Merantau:BAAALAAECgUICAAAAA==.Metaldeleter:BAAALAADCgIIAgAAAA==.',Mi='Miitzukoth:BAAALAADCgcICAAAAA==.Milkà:BAAALAADCggICgAAAA==.Minipesca:BAAALAAECgYICAAAAA==.Miri:BAAALAADCgEIAQAAAA==.Miurax:BAAALAAECgIIAgAAAA==.',Mo='Morrigaan:BAAALAADCgcICgAAAA==.Mortismira:BAAALAAECgYIDwAAAA==.Mortivus:BAAALAAECgIIAgAAAA==.',Mu='Mugles:BAAALAADCgYIBgAAAA==.Muèrté:BAAALAAECgEIAQAAAA==.',['Mä']='Märä:BAAALAADCgcIDAAAAA==.',['Mê']='Mêlê:BAAALAADCggIFwAAAA==.',['Më']='Mëläk:BAAALAADCgIIAgAAAA==.',['Mï']='Mïnerva:BAAALAADCgYIDQAAAA==.',['Mò']='Mòrgul:BAAALAAECgYICAAAAA==.',['Mö']='Möt:BAAALAADCggICAAAAA==.',Na='Nalgotica:BAAALAADCgcIDAAAAA==.Nalgänis:BAAALAADCggIDQAAAA==.Namy:BAAALAAECgEIAQAAAA==.',Ne='Neega:BAAALAADCggIDwAAAA==.Nekawa:BAAALAADCggIDAAAAA==.Nelts:BAAALAADCgYICAAAAA==.Nemsi:BAAALAAECgYICwAAAA==.Neoranga:BAAALAAECggIEQAAAA==.Netas:BAAALAAECgMICQAAAA==.Netphîs:BAAALAADCggIDwAAAA==.',Nh='Nhaedor:BAAALAADCggIDgAAAA==.Nhk:BAAALAADCgUIBQAAAA==.',Ni='Nirlun:BAAALAAECgUIBgAAAA==.Niðhoggr:BAAALAAECgMIBgAAAA==.',No='Nonexistence:BAAALAADCggIDgAAAA==.',Nu='Nunare:BAAALAADCgIIAgAAAA==.',Ny='Nyarlathofer:BAAALAADCggICAAAAA==.Nythara:BAAALAADCggICAAAAA==.',Oi='Oihandar:BAAALAADCgIIAgAAAA==.',Ol='Olayafgon:BAAALAADCggIFwAAAA==.',Or='Orianna:BAAALAADCgUIBQAAAA==.Orik:BAAALAADCggIDAAAAA==.Orimai:BAAALAADCgcICQAAAA==.Orkhul:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Orogron:BAAALAAECgUICQAAAA==.Orënne:BAAALAADCgIIAgAAAA==.',Ov='Overwrite:BAAALAAECgEIAQAAAA==.',Oz='Oztiaquecalo:BAAALAADCgYIBgAAAA==.',Pa='Paanza:BAAALAAECgYIBgAAAA==.Pachangueo:BAAALAAECgYICgAAAA==.Palan:BAAALAAECgMIBAAAAA==.Pandasordos:BAAALAADCggICwAAAA==.Panyqueso:BAAALAADCgUIBQAAAA==.Papala:BAAALAADCggIDwAAAA==.Papinejo:BAAALAADCgYIBgAAAA==.Patteador:BAAALAAECgMIBgAAAA==.',Pe='Pelagøs:BAAALAADCgcIBwAAAA==.Pentakill:BAAALAAECgYIBwAAAA==.Perfectdark:BAAALAADCgQIBgAAAA==.Perkzladin:BAAALAAECgYIBgAAAA==.Perséfone:BAAALAAECgYIDwAAAA==.',Ph='Phenrîl:BAAALAAECgEIAQAAAA==.',Pi='Picfloid:BAAALAAECgYIBgAAAA==.Piit:BAAALAAECgMIAwAAAA==.Pimgtpamtoma:BAAALAADCgEIAQAAAA==.',Pl='Pludyn:BAAALAAECgMIAwAAAA==.',Po='Poka:BAEALAAECggICgAAAA==.Polloinglés:BAAALAADCgMIAwAAAA==.Portuaria:BAAALAADCgYIBgAAAA==.Poyopopeye:BAAALAADCggICAAAAA==.',Pr='Prayforme:BAAALAAECgYIBgAAAA==.Protscape:BAAALAADCgcICQAAAA==.',Pu='Pudoreta:BAAALAAECgIIBAAAAA==.',Py='Pyroblast:BAAALAADCgcICwAAAA==.',['Pê']='Pêstilence:BAAALAAECgYIDgAAAA==.',['Pú']='Púsa:BAAALAAECgEIAQAAAA==.',Qu='Quelthoridas:BAAALAAECgIIBAAAAA==.Quiker:BAAALAAECgYIDgAAAA==.Quilad:BAAALAADCgcICwAAAA==.Quintus:BAAALAAECgEIAQAAAA==.',Ra='Racnex:BAAALAADCgYIBgAAAA==.Ragnas:BAAALAAECgQICAABLAAECggIFwAFAKgZAA==.Ragnâr:BAAALAADCgMIAwABLAAECgUICAABAAAAAA==.Raoru:BAAALAAECgYICAAAAA==.Rauk:BAAALAADCgEIAQAAAA==.Razul:BAAALAADCgcIBwAAAA==.',Re='Reese:BAAALAAECgUICQAAAA==.',Ri='Rimuru:BAAALAAECgYIDAAAAA==.Rinnard:BAAALAADCgcIDQAAAA==.Riukichi:BAAALAADCggICAABLAAECgYIDwABAAAAAA==.',Ro='Robles:BAAALAADCggICAAAAA==.Ronle:BAAALAADCggIDQAAAA==.Rottenn:BAAALAADCgQIBAAAAA==.',Ru='Ruikas:BAAALAAECgIIAgAAAA==.Rukthar:BAAALAAECgcICAAAAA==.',Ry='Rydickk:BAAALAADCggIDAAAAA==.',['Ró']='Róham:BAAALAAECgUICAAAAA==.',Sa='Sabuno:BAAALAAECgYICQAAAA==.Sahaquiel:BAAALAAECgEIAQAAAA==.',Se='Sementerio:BAAALAADCggICAAAAA==.Serault:BAAALAAECgMIBAAAAA==.Severuspajot:BAAALAADCgcIBwAAAA==.',Sh='Shabank:BAAALAAECgMIBgAAAA==.Shadowdead:BAAALAAECgIIAgAAAA==.Shadowflash:BAAALAADCgcICQAAAA==.Shaellar:BAAALAADCgQIBAAAAA==.Sherya:BAAALAAECgEIAQAAAA==.Shiaru:BAAALAAECgIIAgAAAA==.Shäkä:BAAALAAECgYIDAAAAA==.',Si='Sicaia:BAAALAAECgYIDAAAAA==.Sifu:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.Sifú:BAAALAAECgYIDAAAAA==.Sigillum:BAAALAAECgIIAwAAAA==.',Sk='Skurby:BAAALAAECgQICQAAAA==.',So='Sonohara:BAAALAADCggIFAAAAA==.Soulhuntër:BAAALAADCgcICwAAAA==.Soyrepre:BAAALAAECgYIBgAAAA==.',Sp='Spikedgold:BAAALAADCggIDgAAAA==.',Sr='Srleyva:BAAALAADCgYIBgAAAA==.Sroxas:BAAALAADCggICwAAAA==.',St='Stilla:BAAALAADCgYICAAAAA==.Stonemusa:BAAALAADCggICAAAAA==.Stormfist:BAAALAADCggICAAAAA==.Storyboriis:BAAALAADCggICAAAAA==.Strat:BAAALAADCggICAAAAA==.',Su='Superheig:BAABLAAECoEXAAIFAAgIqBnUBgCCAgAFAAgIqBnUBgCCAgAAAA==.Supremus:BAAALAAECgIIBAAAAA==.',Sw='Sweetiefox:BAAALAAECgcIDwAAAA==.',Sy='Sylvanth:BAAALAAECgIIAgAAAA==.Sylvanz:BAAALAADCgQIBAAAAA==.Syrient:BAAALAAECgcIDwAAAA==.Syòn:BAAALAADCggIEgAAAA==.',['Sä']='Säzirä:BAAALAADCgcIBwAAAA==.',['Sô']='Sôwen:BAAALAADCgMIBAAAAA==.',['Sö']='Söngohan:BAAALAAECgEIAgAAAA==.',Ta='Tajonkies:BAAALAAECgUICAAAAA==.Taldazar:BAAALAADCgUICQAAAA==.Tarko:BAAALAADCggICAAAAA==.Taste:BAAALAAECgEIAQAAAA==.',Te='Tech:BAAALAADCggICAAAAA==.Tefity:BAAALAADCggIEAAAAA==.',Th='Thaelwynn:BAAALAADCgcIDgAAAA==.Thaelza:BAAALAADCgEIAQAAAA==.Thalita:BAAALAADCgcIAwAAAA==.Thekkal:BAAALAADCgYIBgAAAA==.Thelaine:BAAALAADCggIEQAAAA==.Theodyn:BAAALAADCggICAABLAAECggIBgABAAAAAA==.Thiesus:BAAALAADCgMIAwAAAA==.Thunderli:BAAALAAECgQIBgAAAA==.',Ti='Tiraoslady:BAAALAADCgMIBAAAAA==.',To='Toriibio:BAAALAADCgIIAgAAAA==.Totillos:BAAALAAECgYIDwAAAA==.',Tr='Trapchaøz:BAAALAAECgQIBQAAAA==.Trolabella:BAAALAADCgUIBQAAAA==.',Ts='Tsubaheal:BAABLAAECoEVAAICAAgIDBpFCAA/AgACAAgIDBpFCAA/AgAAAA==.',Tu='Tumamamemima:BAAALAADCgYICgAAAA==.Tunelvi:BAAALAADCgcIBwAAAA==.',Ty='Tyeci:BAAALAADCgUIBQAAAA==.Tyrfang:BAAALAADCgYICgAAAA==.',Un='Unnlucky:BAABLAAECoEUAAMGAAcIhxraCQDyAQAGAAcIhxraCQDyAQAHAAII3QRujwBLAAAAAA==.Unternehmer:BAAALAAECgYICQAAAA==.',Ut='Utanky:BAAALAADCggIEgAAAA==.',Va='Vaam:BAABLAAECoEYAAIIAAgIMx5kAwC/AgAIAAgIMx5kAwC/AgAAAA==.Vacder:BAAALAAECgYIDgAAAA==.Vandël:BAAALAAECgIIAgAAAA==.Vathriel:BAAALAAECgYIDwAAAA==.',Vi='Villurexico:BAAALAAECgIIAgAAAA==.Vioctormfp:BAAALAADCgIIAgAAAA==.',Vl='Vlyzek:BAAALAAFFAIIBAAAAA==.',Vo='Voldemort:BAAALAADCgQIBAAAAA==.Voles:BAAALAADCgYICwAAAA==.',Vu='Vulscreek:BAAALAADCggICAAAAA==.',Wa='Wacrel:BAAALAADCggIDAAAAA==.Wadacöw:BAAALAAECgYICAAAAA==.Wapuli:BAAALAADCggICAAAAA==.Warlark:BAAALAAECgQIBQAAAA==.Warx:BAAALAAECgIIAgAAAA==.Waticonteia:BAAALAAECgQIBAAAAA==.',We='Weers:BAAALAAECgMIBAAAAA==.Wetul:BAAALAAECgIIBAAAAA==.',Wh='Whyman:BAAALAADCgIIAgAAAA==.',Wi='Windfury:BAAALAADCggIDwAAAA==.Windvoid:BAAALAADCgQIBAABLAAECgMIBgABAAAAAA==.',Wo='Wolfganger:BAAALAAECgcIDgAAAA==.Wordenheal:BAAALAADCgMIAwAAAA==.',Wu='Wuombat:BAAALAAECgYICAAAAA==.Wuruh:BAAALAAECgYICgAAAA==.',Xh='Xhamansito:BAAALAADCgEIAQAAAA==.Xhanya:BAAALAAECgIIAgAAAA==.',Xl='Xluminita:BAABLAAECoEUAAIJAAgInBHqJwDzAQAJAAgInBHqJwDzAQAAAA==.',Xq='Xqyolovalgo:BAAALAAECgIIBAAAAA==.',Xu='Xusojezu:BAAALAADCgUIBQAAAA==.',Xy='Xyglar:BAAALAAECgUIBgAAAA==.',Ya='Yareythx:BAAALAADCgYICQAAAA==.',Yi='Yinda:BAAALAADCggICAAAAA==.',Yl='Yl:BAAALAADCggICAAAAA==.Yllathana:BAAALAAECgIIAgAAAA==.',Yo='Yodaíme:BAAALAADCgcIBwAAAA==.Yosoitupadre:BAAALAADCggICAAAAA==.',Za='Zahhak:BAAALAAECgIIBAAAAA==.Zaldibar:BAAALAADCgYIBgAAAA==.Zandalord:BAAALAADCgcIBwAAAA==.Zaryel:BAAALAADCggIDQABLAAECgMIAwABAAAAAA==.Zaväla:BAAALAADCgIIAgAAAA==.',Ze='Zekrush:BAAALAADCgIIAgAAAA==.Zelestus:BAAALAADCgcICQAAAA==.Zenpa:BAAALAAECgQIBAAAAA==.Zetta:BAAALAADCgcIBwAAAA==.Zexi:BAAALAADCgMIAwAAAA==.',Zh='Zhakrin:BAAALAADCgcIBwAAAA==.Zhaoyun:BAAALAADCgIIAgAAAA==.',Zi='Ziggy:BAAALAADCgEIAQAAAA==.',Zk='Zkitsune:BAAALAADCgcIDAAAAA==.',Zo='Zominus:BAAALAADCggICAAAAA==.Zorripondio:BAAALAADCggIDAAAAA==.',Zu='Zulencio:BAAALAAECgUICQAAAA==.',['Zâ']='Zâtura:BAAALAAECgcICgAAAA==.',['Ás']='Ástracö:BAAALAADCgEIAQAAAA==.',['Äl']='Älioli:BAAALAADCgcIDAAAAA==.',['Är']='Ärcus:BAAALAAECgEIAQAAAA==.',['Òn']='Òné:BAAALAAECgYICQAAAA==.',['Ün']='Üncurëd:BAAALAADCgMIAwAAAA==.',['ßa']='ßateria:BAAALAAECgUICQABLAAECggIDgABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end