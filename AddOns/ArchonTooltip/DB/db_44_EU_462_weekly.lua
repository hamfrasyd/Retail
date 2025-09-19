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
 local lookup = {'DeathKnight-Frost','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Warlock-Affliction','Shaman-Enhancement','Warrior-Fury','Monk-Brewmaster','Evoker-Devastation','Mage-Arcane','Shaman-Restoration',}; local provider = {region='EU',realm='Rexxar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Acaelus:BAAALAADCgQIBAAAAA==.',Ad='Adenela:BAAALAAECggIDAAAAA==.Adin:BAAALAAECgEIAQAAAA==.',Ag='Agravain:BAAALAAECgYIDwAAAA==.',Ai='Aii:BAAALAAECgMIAwAAAA==.Aikidos:BAAALAAECgIIAwAAAA==.',Ak='Akalii:BAAALAAECgYICgAAAA==.Akthar:BAAALAAECgIIAgAAAA==.',Al='Alayra:BAAALAADCgYIBgAAAA==.Alcina:BAAALAAECgYICwAAAA==.Alcudía:BAAALAAECgMIAwAAAA==.Alexzaub:BAAALAADCgcICwAAAA==.Allihexe:BAAALAADCgUIBgAAAA==.Altariel:BAAALAAECgEIAQAAAA==.Alura:BAAALAADCggICwAAAA==.',Am='Amaia:BAAALAADCgcIDQAAAA==.Amalurax:BAAALAAECgEIAQAAAA==.Amaryas:BAAALAAECgYICAAAAA==.Amui:BAAALAAECgYICQAAAA==.',An='Anisa:BAAALAADCgcIBwAAAA==.Annalise:BAAALAAECgEIAgAAAA==.Annihilator:BAAALAADCgcIBwAAAA==.Anàrchy:BAABLAAECoEXAAIBAAgIEyZ2AACHAwABAAgIEyZ2AACHAwAAAA==.',Ap='Apfeldite:BAAALAADCggIDgABLAAECgcICgACAAAAAA==.',Ar='Arghoul:BAAALAAECgQIBAAAAA==.Arkangel:BAAALAAECggIEAAAAA==.Arrkin:BAAALAAECgYIDgAAAA==.Aruzohra:BAAALAADCgMIAwABLAAECggIDAACAAAAAA==.Arwid:BAAALAADCgIIAgABLAADCgUIBQACAAAAAA==.',As='Asag:BAAALAADCggICAAAAA==.Asariia:BAAALAADCgcIDQAAAA==.Aschimonde:BAAALAADCgIIAgAAAA==.Asortix:BAAALAAECgQICQAAAA==.Asrock:BAAALAADCgcIFAAAAA==.Asznee:BAAALAAECggIDAAAAA==.',At='Athanax:BAAALAADCgMIAwAAAA==.Atrian:BAAALAADCggICAAAAA==.',Au='Aulíná:BAAALAAECgYICQAAAA==.',Av='Avîana:BAAALAADCgMIAwAAAA==.',Az='Azraelo:BAAALAAFFAIIAgAAAA==.',Ba='Badtotems:BAAALAAECgYICgAAAA==.Balboa:BAAALAADCgMIAwAAAA==.Ballabumbum:BAAALAADCggIEQAAAA==.Bartholder:BAAALAADCgcIBwAAAA==.Basim:BAAALAAECgIIAgAAAA==.Bastí:BAAALAADCgYIBwAAAA==.Batuu:BAAALAAECgYIDwAAAA==.',Be='Beklit:BAAALAAECgcIDgAAAA==.Belion:BAAALAADCgcICAAAAA==.Belisar:BAAALAAECgYICAAAAA==.Betonfinger:BAAALAAECgYICwAAAA==.',Bi='Bierbube:BAAALAADCggICAAAAA==.Bierspritzer:BAAALAAECggICAAAAA==.Billy:BAAALAADCgYIBgAAAA==.',Bl='Blazed:BAAALAAECgcIEgAAAA==.Blitzbirne:BAAALAAECgcIEAAAAA==.Bloodydevil:BAAALAADCggICAAAAA==.Blæckhawk:BAAALAAECgcIEAAAAA==.Blóodymary:BAAALAADCggICQAAAA==.',Bo='Bobbery:BAAALAAECgcIEgAAAA==.Borismagus:BAAALAADCggICQAAAA==.Boynextdoor:BAAALAAECgYIDQAAAA==.',Br='Brachox:BAAALAADCgcIFAAAAA==.Brambart:BAAALAADCggICAABLAAECgcIEgACAAAAAA==.Brancopala:BAAALAADCgYIBgAAAA==.Branjolina:BAAALAADCggICwAAAA==.Brudajakob:BAAALAAECgIIBQAAAA==.Brugo:BAAALAAECgMIBAAAAA==.',Ca='Cailean:BAAALAADCggICAAAAA==.Caldur:BAAALAADCgcIBwAAAA==.Camelot:BAAALAAECgMIBAAAAA==.Cani:BAAALAAECgcIBwAAAA==.Cardrak:BAAALAAECgYICwAAAA==.Cavalanzas:BAAALAAECgMIAwAAAA==.',Ce='Cellox:BAAALAAECgYIBgAAAA==.Celyla:BAAALAAECgUIBgABLAAECgcIDQACAAAAAA==.Cessy:BAAALAAECggICQAAAA==.',Ch='Changeforms:BAAALAADCggICAABLAAECgcIDwACAAAAAA==.Chary:BAAALAADCggIDgAAAA==.Chaszkahmiya:BAAALAAECgQIBwAAAA==.Cheeppi:BAAALAADCggIBgAAAA==.Chibikairi:BAAALAADCggIEQAAAA==.Chimpacta:BAAALAADCgUIBQABLAAECgYIDQACAAAAAA==.Chivoltaic:BAAALAADCgcIBwABLAAECgUIBAACAAAAAA==.Chiwut:BAAALAAECgUIBAAAAA==.Chèrry:BAAALAAECgUIBwAAAA==.',Ci='Cidy:BAAALAAECgcIEgAAAA==.Cipherdragon:BAAALAADCggICAAAAA==.Citra:BAAALAADCggICAABLAAECgYICgACAAAAAA==.',Cl='Clemmdruid:BAAALAAECgMIAwAAAA==.Clivedk:BAAALAADCgUIBQAAAA==.Clivia:BAAALAADCgcIDQAAAA==.Clusters:BAAALAADCgYIBgAAAA==.',Co='Consânesco:BAAALAADCgYIDAABLAAECgcICgACAAAAAA==.Corryvreckan:BAAALAAECgYIBgAAAA==.Cortessá:BAAALAAECgYICgAAAA==.Corth:BAAALAADCggIEAAAAA==.',Cr='Cromo:BAAALAAECgIIAgAAAA==.Crooxx:BAAALAAECgIIAgAAAA==.Crossi:BAAALAAECgQIBAAAAA==.Crossí:BAAALAADCggICAAAAA==.Crôssi:BAAALAAECgcIDwAAAA==.',Cu='Curilock:BAAALAADCggIDgAAAA==.Curipera:BAAALAAECggIEwAAAA==.Curumbir:BAAALAAECgEIAQAAAA==.',Cy='Cyberjâck:BAAALAADCgcIBwAAAA==.Cylezz:BAAALAADCgcIAgAAAA==.',Cz='Czerwo:BAAALAAECgIIAgAAAA==.',['Cá']='Cárà:BAAALAAECgYICAAAAA==.',['Câ']='Cârà:BAAALAADCgcIDQAAAA==.Câtwêâzlê:BAAALAADCgcIBwAAAA==.',Da='Daerin:BAAALAADCgIIAgAAAA==.Darcura:BAAALAADCgcICQABLAADCggICAACAAAAAA==.Darkmouse:BAAALAAECgMIBQAAAA==.Darkside:BAAALAADCgcIDQAAAA==.Dasha:BAAALAAECgQIBwAAAA==.',De='Delanier:BAAALAAECgYIDAAAAA==.Demaulwurfn:BAAALAAECgIIBQAAAA==.Deshboard:BAAALAAECggIEwAAAA==.Destina:BAAALAADCgYIBgAAAA==.Detarexium:BAAALAADCgcIBwAAAA==.Devøn:BAAALAAECgMIBgAAAA==.',Dh='Dhaulagiri:BAAALAADCgcIDwAAAA==.',Di='Diroh:BAAALAAECggICAAAAA==.',Dk='Dkôôn:BAAALAADCgcIBwABLAAECggIDAACAAAAAA==.',Do='Dobutsu:BAAALAAECgcIDQAAAA==.Donjuancho:BAAALAAECgYICAAAAA==.',Dr='Drackthul:BAAALAAECgcIDQAAAA==.Dragonblue:BAAALAADCggIGAAAAA==.Draktoria:BAAALAADCgUIBQAAAA==.Drdupstep:BAAALAAECgIIAgAAAA==.Drifia:BAAALAAECgYICQAAAA==.Dripdropice:BAAALAADCgUIBQAAAA==.Drynai:BAAALAAECgIIBQAAAA==.',Du='Duffjunkie:BAAALAAECgYICQAAAA==.Duriella:BAAALAADCggICgAAAA==.',Dy='Dylee:BAAALAADCgcIDQAAAA==.',['Dé']='Déímos:BAAALAADCggIDgAAAA==.',Ef='Efii:BAAALAAECgYICAAAAA==.',Ei='Einârr:BAAALAADCgcIBwAAAA==.',El='Elaía:BAAALAAECgYICgAAAA==.Eldorin:BAAALAAECgMIAwAAAA==.Eldämon:BAAALAAECgYIDQAAAA==.Elfeba:BAAALAAECgcIEgAAAA==.Elfiechaos:BAAALAADCggIFAAAAA==.Elladan:BAAALAAECgUIBQAAAA==.Elone:BAAALAADCggIEAAAAA==.Elonmo:BAAALAAECgcIEAAAAA==.',Em='Empîre:BAAALAADCggIDwAAAA==.',En='Enginé:BAAALAAECgYIBgAAAA==.',Er='Erza:BAAALAAECgcIEgAAAA==.',Es='Escalante:BAAALAAECgcIDwAAAA==.',Et='Etsu:BAAALAADCggIBAAAAA==.',Ev='Evious:BAAALAADCgcIBwAAAA==.Evoxd:BAAALAAECgcIDgAAAA==.',Ex='Extermina:BAAALAADCggIEAAAAA==.',Fa='Faciem:BAAALAAECgYICgAAAA==.Fahise:BAAALAAECggICQAAAA==.Fairozwei:BAAALAAECgYICgAAAA==.Faladi:BAAALAAECgcIEQAAAA==.Fanaris:BAAALAAECgYIBgAAAA==.',Fe='Fearit:BAAALAAECgMIBQAAAA==.Fearx:BAAALAAECgEIAQAAAA==.Febí:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Fentron:BAAALAAECgYIDAAAAA==.Fepper:BAAALAADCggIDAAAAA==.Feraaya:BAAALAAECgYICgAAAA==.Feranus:BAAALAADCgYICwAAAA==.Feremias:BAAALAAECgYICgAAAA==.',Fi='Filliz:BAAALAADCggICAAAAA==.Fireefly:BAAALAADCgMIAwABLAADCggICAACAAAAAA==.',Fl='Flacherdler:BAAALAADCggIFQAAAA==.Flitzfritz:BAAALAAECgEIAQAAAA==.',Fo='Foonkel:BAAALAAECgUIDAABLAAECgYIDAACAAAAAA==.',Fr='Frauöhrchen:BAAALAADCgcIDQAAAA==.Frex:BAAALAAECggICAAAAA==.',Fu='Fujina:BAAALAADCgYIBgAAAA==.Furorblut:BAAALAADCggIDwAAAA==.Furoricum:BAAALAADCggIDQAAAA==.',Fy='Fydonural:BAAALAADCgQIBAAAAA==.',['Fé']='Féarswin:BAAALAAECgcIEAAAAA==.',['Fí']='Fírimar:BAAALAADCggICAAAAA==.',Ga='Gaddøø:BAAALAADCggICAAAAA==.Galal:BAAALAAECgEIAQAAAA==.Gallidan:BAAALAAECgYICQAAAA==.Gandine:BAAALAAECgEIAQAAAA==.Garuin:BAAALAADCgYIBgAAAA==.',Ge='Gemini:BAAALAAECggIAQAAAA==.',Gi='Giftzwergerl:BAAALAAECgIIBAAAAA==.Gildenmaster:BAAALAADCgcIBwAAAA==.Ginorius:BAAALAADCggIDAAAAA==.',Gl='Glaiveguy:BAAALAADCggIDQAAAA==.',Gr='Granitjäger:BAAALAADCgMIAwAAAA==.Greislich:BAAALAADCgYICAAAAA==.Greyback:BAAALAADCggIEwAAAA==.Grobienchen:BAAALAAECgYIDAAAAA==.Grobiene:BAAALAAECgQIBgABLAAECgYIDAACAAAAAA==.Gromgash:BAAALAAECggICAAAAA==.Grêg:BAAALAADCgMIAwAAAA==.Grômm:BAAALAAECgcIEAAAAA==.',Gu='Guglhupf:BAAALAADCggICAAAAA==.Guhl:BAAALAAECggIAQAAAA==.Guillotine:BAAALAAECgMIAwAAAA==.Guldatrix:BAAALAADCgMIAwAAAA==.Gundeberga:BAAALAAECgUIBwAAAA==.',Gw='Gwennifer:BAAALAAECgEIAQAAAA==.',Gy='Gyio:BAAALAAECggICAAAAA==.',['Gó']='Górgoroth:BAAALAAECgcIDAAAAA==.',Ha='Hackepeter:BAAALAADCgEIAQAAAA==.Haldrophîa:BAAALAAECgMIAwABLAAECgcIDgACAAAAAA==.Hamelun:BAAALAAECgYIDQAAAA==.Hanco:BAAALAAECggICQAAAA==.Harlêên:BAAALAAECggICAAAAA==.Hasixii:BAAALAAECgIIAgAAAA==.Hasley:BAAALAADCggICAAAAA==.Hatari:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.Hawcha:BAAALAADCgcIDQAAAA==.',He='Healmyface:BAAALAAECgIIAgAAAA==.Heisterruléz:BAABLAAECoEiAAIDAAgIoiAOBwD8AgADAAgIoiAOBwD8AgAAAA==.Helusha:BAAALAAECgcIDQAAAA==.Hergard:BAAALAADCgYIBgAAAA==.',Hi='Hi:BAAALAADCgMIAQAAAA==.Hirak:BAAALAAECgcIDQABLAAFFAEIAQACAAAAAA==.Hisedi:BAAALAADCggICQAAAA==.',Ho='Holmalbier:BAAALAAECgIIAgAAAA==.Holytroll:BAAALAAECgEIAQAAAA==.',Hu='Hunterowski:BAAALAAECgIIAgAAAA==.Hunthontas:BAAALAADCggICAAAAA==.Huângson:BAAALAAECgcIBwAAAA==.',Hy='Hyara:BAAALAAECggIEgAAAA==.Hyprusên:BAAALAAECgIIAgAAAA==.',Ic='Icedblood:BAAALAADCgYIBgAAAA==.Iceflex:BAAALAAECggIEwAAAA==.',Il='Ilativ:BAAALAAECgYIBgAAAA==.',In='Ingithas:BAAALAAECgMIAwAAAA==.Insyhunt:BAAALAADCggIDwAAAA==.Insymaid:BAAALAAECgcIEAAAAA==.Insync:BAAALAAECgIIAgAAAA==.Intime:BAAALAAECgMIBQAAAA==.Invìctus:BAAALAAECgYICwAAAA==.',Ir='Irelaana:BAAALAAECgYICQAAAA==.Iristus:BAAALAADCgQIBAAAAA==.',Is='Isko:BAACLAAFFIEFAAIEAAMIRRhtAgD0AAAEAAMIRRhtAgD0AAAsAAQKgRcAAgQACAjSJJ4BAFoDAAQACAjSJJ4BAFoDAAAA.Iskodh:BAAALAAECgEIAQABLAAFFAMIBQAEAEUYAA==.Isodrink:BAAALAADCggIFgABLAAECgcICgACAAAAAA==.',Iz='Izunaa:BAAALAAECgMICgAAAA==.',Ja='Jalia:BAAALAADCgcICQAAAA==.Janamate:BAAALAAECgcICgAAAA==.Javaco:BAAALAADCggIDwAAAA==.',Ji='Jinqx:BAAALAADCgYIBgAAAA==.Jinwoo:BAAALAADCgUIBQAAAA==.Jinzak:BAAALAADCgcIDQAAAA==.',Jo='Jorre:BAAALAAECgIIAwAAAA==.',['Jí']='Jí:BAAALAAECggIEAAAAA==.',Ka='Kaali:BAAALAAECgYIDwAAAA==.Kabíra:BAAALAAECgYICQAAAA==.Kail:BAAALAADCgEIAQAAAA==.Kaleha:BAAALAADCggICAAAAA==.Karita:BAAALAAECgcIEgAAAA==.Karmageddon:BAAALAADCggIDwAAAA==.Kashukii:BAAALAAECgcIBwAAAA==.Katanatoá:BAAALAADCgcIFQAAAA==.Katânja:BAAALAADCgQIBAAAAA==.Kazury:BAAALAAECgYIBgAAAA==.',Ke='Keap:BAAALAADCggICAAAAA==.Kenshîn:BAAALAAECgYIDQAAAA==.Kerala:BAAALAAECgcIDQAAAA==.Keyman:BAAALAADCgcIDQABLAADCggICAACAAAAAA==.Keys:BAAALAADCggICAAAAA==.',Kh='Khala:BAAALAAECgUIBQAAAA==.Kharzon:BAAALAAECgYICAAAAA==.Khazar:BAAALAADCggIDAABLAAECgUICQACAAAAAA==.',Ki='Kijara:BAAALAAECgIIAgABLAAECggICQACAAAAAA==.Killerbabe:BAABLAAECoEUAAIFAAcIXSQbAQDyAgAFAAcIXSQbAQDyAgAAAA==.Kitàná:BAAALAADCggIDwAAAA==.',Kl='Klenekle:BAAALAAECgMIBQAAAA==.Klunka:BAAALAAECgUIBQAAAA==.',Kn='Knockknock:BAAALAAFFAIIAgAAAA==.Knoval:BAAALAAECgcIEQAAAA==.',Ko='Kodâ:BAAALAADCgYIBgAAAA==.',Kr='Kreltor:BAAALAAECgYIDwAAAA==.',Ku='Kuhlius:BAAALAADCgIIAgAAAA==.',Kv='Kvothee:BAAALAAECgYICQAAAA==.',Ky='Kynari:BAAALAAECgYICgAAAA==.',La='Lacrim:BAAALAADCggIGAAAAA==.Lastkiss:BAAALAAECgMIAwAAAA==.Lauranâ:BAAALAADCgcIDQAAAA==.Lazerchicken:BAAALAAECgMIAwAAAA==.',Le='Leafmealone:BAAALAAECgIIAgAAAA==.',Li='Liahon:BAAALAADCggICAAAAA==.Lianesse:BAAALAADCggICAAAAA==.Lidian:BAAALAAECgEIAQABLAAECgcIEgACAAAAAA==.Lift:BAAALAADCggIEAAAAA==.Lilkittyuwu:BAAALAADCgQIBgAAAA==.Lindan:BAAALAADCggICAABLAAECgcICgACAAAAAA==.Lisett:BAAALAAECgIIAgAAAA==.Listart:BAAALAADCgcIDAAAAA==.',Lo='Lobotomya:BAAALAADCgMIBAAAAA==.Lokj:BAAALAAECgIIAwAAAA==.Loore:BAAALAADCgcIDgAAAA==.Lorayla:BAAALAAECgQIBAAAAA==.Lorento:BAAALAADCgMIBQAAAA==.Lostystorm:BAAALAAECgEIAQAAAA==.Louli:BAAALAADCggICAABLAAECgcICAACAAAAAA==.',Lu='Lucifersama:BAAALAAECgMIAwABLAAECggIFwABABMmAA==.Lunanya:BAAALAADCggICAAAAA==.Luthienne:BAAALAADCggIFQAAAA==.Luxur:BAAALAADCggIEgAAAA==.',Ly='Lyka:BAAALAAECgEIAQAAAA==.Lyori:BAAALAADCgcIBwAAAA==.Lyys:BAAALAAFFAIIAgAAAA==.',['Lì']='Lìdìan:BAAALAAECgcIEgAAAA==.',['Lü']='Lümmelmor:BAAALAAECgcICgAAAA==.',Ma='Maegar:BAAALAAECgIIAwAAAA==.Magisko:BAAALAAECgYIBwABLAAFFAMIBQAEAEUYAA==.Magmatamer:BAAALAAECgYICgAAAA==.Mahiru:BAAALAADCggICAAAAA==.Malakai:BAAALAAECgcICgAAAA==.Mararith:BAAALAAECggIDgAAAA==.Marcy:BAAALAAECgMIAwAAAA==.Mardoth:BAAALAAECgUIBgAAAA==.Marksman:BAAALAADCgcIBwAAAA==.Marscheall:BAAALAADCgUIBQAAAA==.Mashor:BAAALAADCggIFgAAAA==.Mashrabeya:BAAALAADCggIDwAAAA==.Maskagato:BAAALAADCgcIEgABLAAECgMIAwACAAAAAA==.',Me='Meditroll:BAAALAAECgEIAQAAAA==.Medullah:BAAALAAECgYIDwAAAA==.Megæra:BAAALAAECgIIAgABLAAECgYIDAACAAAAAA==.Melan:BAAALAAECgIIAgAAAA==.Melomancer:BAAALAAECgYIDQAAAA==.Meloron:BAAALAAECgMIAwAAAA==.Merce:BAAALAADCgUIBQAAAA==.Merlote:BAAALAADCgUIBwAAAA==.',Mi='Mightynature:BAAALAADCgcICQAAAA==.Miralora:BAAALAAECgcIEAAAAA==.Mirotos:BAAALAADCgYIBgAAAA==.Mirqun:BAAALAADCgcIFQAAAA==.',Ml='Mliodasx:BAAALAAECgcIDwAAAA==.',Mo='Mogna:BAAALAAECgMIBQAAAA==.Mondlüge:BAAALAADCgcIDQAAAA==.Moolara:BAAALAADCgIIAgABLAAECggIIgADAKIgAA==.Morgulis:BAAALAAECggICwAAAA==.',Mu='Muckmuck:BAAALAAECgEIAgAAAA==.Muffý:BAAALAADCgcICgAAAA==.Muriala:BAAALAAECgcIBwAAAA==.',['Mâ']='Mâjestix:BAAALAAECgMIBgAAAA==.Mâte:BAAALAAECgcIEAAAAA==.',['Mä']='Mäxim:BAAALAAECgcIEAAAAA==.',['Mé']='Mérida:BAAALAADCgcIBwAAAA==.',['Mí']='Míraculix:BAAALAAECgIIAQAAAA==.Mízel:BAAALAAECgYIBgAAAA==.',['Mû']='Mûnkâ:BAABLAAECoEWAAIGAAcITh/cAwBpAgAGAAcITh/cAwBpAgAAAA==.',Na='Naisha:BAAALAADCggICAAAAA==.Nalou:BAAALAADCgcICgAAAA==.Naomí:BAAALAADCggICAAAAA==.Narqrogue:BAAALAADCggICAABLAAECgIIAgACAAAAAA==.Narqune:BAAALAAECgIIAgAAAA==.Narugadan:BAAALAAECgYIDwAAAA==.Narwynn:BAAALAADCgcIDQAAAA==.Narø:BAAALAAECgYIDAAAAA==.',Ne='Nedorian:BAAALAAECgcIBwABLAAECgcICAACAAAAAA==.Neferpitou:BAAALAAECggIEAAAAA==.Nemea:BAAALAADCggICAABLAAECgcICAACAAAAAA==.Nenya:BAAALAAECgcIDwAAAA==.Neoran:BAAALAAECgcIEgAAAA==.Nephalêm:BAAALAADCgcIBwAAAA==.Nerdii:BAAALAAECgcICwAAAA==.Nerdikay:BAAALAAECgcIDQAAAA==.Nerdragon:BAAALAADCggIEAAAAA==.Neverdeplete:BAAALAADCgQIBAAAAA==.',Ni='Nibo:BAAALAADCgYIBgAAAA==.Nichtstewie:BAAALAADCgYIBgAAAA==.Nidavellir:BAAALAADCgcICAAAAA==.Niemand:BAAALAAECgcIDgAAAA==.Nihalem:BAAALAAECgIIAgABLAAECgMIBAACAAAAAA==.Nijana:BAAALAAECgIIAgAAAA==.Ninggu:BAAALAAECgYIBgAAAA==.Niola:BAAALAADCgcIBwAAAA==.Nizo:BAAALAADCggICQAAAA==.',No='Noahewi:BAAALAADCgQIBAAAAA==.Noize:BAAALAADCggIFwAAAA==.',Ny='Nyxalara:BAAALAADCggICAAAAA==.',['Næ']='Nærgaruga:BAAALAAECgYIDwAAAA==.',['Nó']='Nóroelle:BAAALAADCgcIDgAAAA==.',Oa='Oarschi:BAAALAAECggIEQAAAA==.',Ok='Oklahomaa:BAABLAAECoEVAAIHAAgIsRs8DACyAgAHAAgIsRs8DACyAgAAAA==.',Ol='Olpa:BAAALAADCggIEQAAAA==.Olwe:BAAALAAECgMIAwAAAA==.',Om='Omnia:BAAALAADCgcIFQAAAA==.Omnivalent:BAACLAAFFIEGAAIIAAMI6BmjAQD6AAAIAAMI6BmjAQD6AAAsAAQKgRgAAggACAgSIeICAOQCAAgACAgSIeICAOQCAAAA.',On='Onionjack:BAAALAADCgcIBwAAAA==.',Op='Optima:BAAALAAECgcIBwAAAA==.',Os='Oshara:BAAALAADCggICAABLAAECggICQACAAAAAA==.Osora:BAAALAAECggICQAAAA==.',Pa='Palizskijvah:BAAALAADCgQIBAAAAA==.Paralyzed:BAAALAAECgEIAQAAAA==.Paretó:BAAALAADCgYIBwAAAA==.Parona:BAAALAADCgYIBgAAAA==.Passîona:BAAALAAECgYIDwAAAA==.Patpatsan:BAAALAADCggICAAAAA==.Patzia:BAAALAADCgMIAwAAAA==.',Pe='Peanût:BAAALAAECgcIEAAAAA==.Peekaboo:BAAALAAECgIIAgAAAA==.Peniheal:BAAALAADCggICwAAAA==.Pennyweis:BAAALAADCgYIBgAAAA==.',Ph='Phaldriel:BAAALAADCggICAAAAA==.Phantomox:BAAALAAECgEIAQAAAA==.Phieb:BAAALAAECgMIBQAAAA==.Phêa:BAAALAADCggIFgAAAA==.Phîlomena:BAAALAAECgIIAgAAAA==.',Pi='Piara:BAAALAAECgEIAQAAAA==.Piefke:BAAALAAECgMIBAAAAA==.',Po='Poccahunters:BAAALAAECgcIEgAAAA==.',Pr='Priesterie:BAAALAADCggIDwAAAA==.Pristerchen:BAAALAAFFAEIAQAAAA==.',Pu='Purplewitch:BAAALAAECgYICwAAAA==.',['Pá']='Páblo:BAAALAADCggIEwAAAA==.',['Pü']='Püppii:BAAALAAECgYIBgAAAA==.',Qu='Quent:BAAALAADCgUIBQAAAA==.Quillan:BAAALAAECgcIDQAAAA==.Qurte:BAAALAAECgIIBgAAAA==.Qurtydirty:BAAALAADCgcIBwAAAA==.',Ra='Rachelle:BAAALAAECgQIBwAAAA==.Radrox:BAAALAAECgYIDwAAAA==.Raemsi:BAAALAADCgYIEgAAAA==.Raguel:BAAALAADCggICwAAAA==.Raleehá:BAAALAADCggIGwAAAA==.Ranginui:BAAALAAECgcIEAAAAA==.Raxxla:BAAALAADCgQIBAAAAA==.Raydeath:BAAALAAECggIBwAAAA==.Razshak:BAAALAADCgYIBgAAAA==.',Re='Reckless:BAAALAAECgMIBQAAAA==.Reculex:BAAALAADCggICAAAAA==.Regan:BAAALAAECgUIBwAAAA==.Reisui:BAAALAAECgYICgAAAA==.Rengal:BAAALAAECgcIEgAAAA==.Reuberzwei:BAAALAAECggIEwAAAA==.Revagor:BAAALAADCgcIDAAAAA==.Reze:BAAALAAECggIEAAAAA==.Rezora:BAAALAADCgYIBgAAAA==.',Ri='Riikku:BAAALAAECgcICwAAAA==.Riikkuqt:BAAALAAECgEIAQAAAA==.Rikkumaus:BAAALAAECgYICQAAAA==.',Ro='Robspala:BAAALAAECgMIAwAAAA==.Rockblue:BAAALAAECgIIAwAAAA==.Ronnié:BAAALAADCgYIBgAAAA==.Rostigernagl:BAAALAAECgEIAQAAAA==.',Ry='Rytha:BAAALAADCggIDwABLAAECggICQACAAAAAA==.Rythâ:BAAALAADCggIDwABLAAECggICQACAAAAAA==.',['Rä']='Räuberr:BAAALAAECgMIBQAAAA==.',['Rê']='Rêy:BAAALAAECgIIAgAAAA==.',['Rì']='Rìyoku:BAAALAADCggIFQAAAA==.',['Rú']='Rúllio:BAAALAAECggICgAAAA==.',Sa='Sadcatwave:BAAALAAECggICAAAAA==.Sadrax:BAAALAAECgcICwAAAA==.Sahrina:BAAALAAECgIIAgABLAAECgMIBQACAAAAAA==.Salini:BAAALAADCgYIBgAAAA==.Sappho:BAAALAADCggIDQAAAA==.Sarandos:BAAALAAECgYICAAAAA==.Sardasil:BAAALAAECgIIAgAAAA==.Saxy:BAAALAADCggICAAAAA==.',Sc='Schalala:BAAALAAECgcIDwAAAA==.Schamanjess:BAAALAADCgYIBgAAAA==.Scherox:BAAALAAECgcICAAAAA==.Schmaggi:BAAALAAECgEIAQAAAA==.',Se='Sebull:BAAALAAECgQICQAAAA==.Sensory:BAAALAAECgcIEgAAAA==.Serendipity:BAAALAADCgcIBwAAAA==.',Sh='Shaadar:BAAALAAECgcIEgAAAA==.Shaan:BAAALAAECgIIAgAAAA==.Shala:BAAALAADCgUIBQAAAA==.Shanoru:BAAALAAECggICAAAAA==.Sheidalin:BAAALAAECgYICgAAAA==.Sheronà:BAAALAADCggIDgAAAA==.Shivarina:BAAALAAECgEIAQAAAA==.Shjami:BAAALAAECggIDAAAAA==.Shrék:BAAALAADCgMIBAAAAA==.Shuno:BAAALAADCggIDwAAAA==.Shâwny:BAAALAAECgEIAQAAAA==.Shéy:BAAALAADCggIDQAAAA==.Shîno:BAAALAAECgYICQAAAA==.Shînyumbreon:BAAALAAECgQIBAABLAAECggICQACAAAAAA==.Shòx:BAAALAAECgUIDAAAAA==.',Si='Sidien:BAAALAAECgMIBwAAAA==.Sizzledk:BAAALAADCgcIBwAAAA==.',Sk='Skeder:BAAALAADCggIBwAAAA==.Skedèr:BAAALAAECgYIBgAAAA==.Skillknight:BAAALAAECgYIEgAAAA==.',Sl='Sleepingsun:BAAALAAECgYIDwAAAA==.',Sm='Smoken:BAAALAAECgYICwAAAA==.',Sn='Snowflakê:BAAALAAECgMIAwAAAA==.Snoxhy:BAAALAADCgYIBgAAAA==.',Sp='Sparrow:BAAALAADCgYIAwAAAA==.Spellnix:BAAALAADCggIFAAAAA==.',St='Stardust:BAAALAADCgcIBwABLAAECgYICgACAAAAAA==.Strassi:BAAALAADCgcIEgAAAA==.Strike:BAAALAADCgMIAwABLAAECgcICgACAAAAAA==.Stroy:BAAALAAECgcIEwAAAA==.',Sw='Swailes:BAAALAAECgEIAQAAAA==.Swift:BAAALAADCgUIBQAAAA==.',Sy='Sylinth:BAAALAADCgYIBgAAAA==.Syluna:BAAALAADCgEIAgAAAA==.Synaxia:BAAALAAECgIIAgAAAA==.',['Sá']='Sáibot:BAAALAADCgQIBAAAAA==.',['Sé']='Sémiel:BAAALAADCggICAAAAA==.Séèla:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.',['Sê']='Sêlene:BAAALAAECgUICQAAAA==.',['Sö']='Sözen:BAAALAADCgcIBwAAAA==.',['Sü']='Süchtel:BAAALAAECgMIAwAAAA==.Süßes:BAAALAAECgQIBAAAAA==.',Ta='Talanoa:BAAALAAECgcIEwAAAA==.Talora:BAAALAADCggIEAAAAA==.Tamzin:BAAALAAECgMIBQAAAA==.Taradòr:BAAALAADCggICAAAAA==.Taren:BAAALAAECgUICQAAAA==.Tarok:BAAALAADCggIDwAAAA==.Tatjanná:BAAALAADCgcIBwABLAAFFAQIBgAJAFwhAA==.Tautätzchen:BAAALAAECgQICQAAAA==.Tavrosh:BAAALAAECgIIAgAAAA==.Tazara:BAAALAADCgcIDQAAAA==.',Te='Teckerli:BAAALAAECggIBQAAAQ==.Teckerlinus:BAAALAAECgcIEwABLAAECggIBQACAAAAAQ==.Tekakage:BAAALAADCgcICQAAAA==.Tensuten:BAAALAADCgcICgAAAA==.Teufeline:BAAALAADCgcIBwAAAA==.',Th='Thallistro:BAAALAADCgcIBwAAAA==.Therealgeek:BAAALAADCgIIAgAAAA==.Therealme:BAABLAAECoEWAAIKAAgIViU6DADVAgAKAAgIViU6DADVAgAAAA==.Thronerbe:BAAALAAECgcIEQAAAA==.',Ti='Tiffany:BAAALAAECgQIBAAAAA==.Tiffikeks:BAAALAAECgYICgAAAA==.Tiia:BAAALAAECgcIDgAAAA==.Timmeey:BAAALAAECgEIAQAAAA==.Tirjin:BAAALAAECgMIAwAAAA==.',Tj='Tjanu:BAAALAADCgYIBgAAAA==.',Tk='Tkey:BAAALAADCgMIAwAAAA==.Tkêy:BAAALAADCgUIBQAAAA==.',To='Todesleelee:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Tokark:BAAALAADCggICAAAAA==.Tombrady:BAAALAAECggIBgAAAA==.Tonglu:BAAALAAECgcIEgAAAA==.Tornadotonya:BAAALAAECgcICgAAAA==.',Tr='Tracxo:BAAALAADCgYICAAAAA==.Trazym:BAAALAADCgcIBwAAAA==.Trifactá:BAAALAAECgEIAQAAAA==.Trollfestwiz:BAAALAAECgYIDAAAAA==.Troody:BAAALAADCgcIDgAAAA==.Truldon:BAAALAADCggIDQAAAA==.Trustî:BAAALAAECggIEgAAAA==.',Ts='Tsuyosa:BAAALAADCgQIBQAAAA==.',Ty='Tyanne:BAAALAAECgcIDwAAAA==.',['Tü']='Tütütü:BAAALAAECgIIAgAAAA==.',Um='Umbrella:BAAALAAECggIDgAAAA==.',Un='Unangenehm:BAAALAADCgcIBwAAAA==.Underscore:BAAALAAECgcIEgAAAA==.Uniusshaman:BAACLAAFFIEGAAILAAMI4AhgBADLAAALAAMI4AhgBADLAAAsAAQKgRgAAgsACAgOEf8gAMsBAAsACAgOEf8gAMsBAAEsAAMKCAgIAAIAAAAA.',Ur='Urd:BAAALAADCggICAAAAA==.Ursa:BAAALAAECgcIEAAAAA==.',Us='Ushara:BAAALAAECgYIBgAAAA==.',Va='Vahldor:BAAALAAECgEIAQAAAA==.Vantis:BAAALAAECgcIDgAAAA==.Varandriel:BAAALAADCggIEQAAAA==.Varlafel:BAAALAAECgcIDgAAAA==.',Ve='Veos:BAAALAAECgMIBQAAAA==.Veparis:BAAALAAECgMIBAAAAA==.Vexor:BAAALAAECgQIBwAAAA==.',Vi='Vitaldemon:BAAALAADCgUICgAAAA==.Vitalitas:BAAALAADCggIEgAAAA==.Vitalmage:BAAALAADCggIDwAAAA==.Vitalshaman:BAAALAADCggIDwAAAA==.Vivin:BAAALAAECgcIEQAAAA==.',Vo='Volredaar:BAAALAAECgIIAgAAAA==.Volstros:BAAALAAECgQIBQAAAA==.Voyde:BAAALAADCgYIBgAAAA==.',Vy='Vyscerah:BAAALAAECgUIDAAAAA==.',['Vø']='Vøllmilch:BAAALAAECgMIBAAAAA==.',Wa='Waidmanns:BAAALAAECgEIAQAAAA==.Wau:BAAALAADCggIBAAAAA==.',We='Welcorn:BAAALAAECgcICQAAAA==.',Wo='Wowee:BAAALAADCggIFQABLAAECgYICQACAAAAAA==.',Wu='Wugo:BAAALAADCgcIDQABLAADCggIBAACAAAAAA==.',['Wø']='Wølfzklaue:BAAALAADCgcIDQAAAA==.',Xa='Xaji:BAAALAAECggIEAAAAA==.Xathaa:BAAALAAECgcIBwAAAA==.',Xe='Xenophilia:BAAALAAECgcICAAAAA==.',Xo='Xolldog:BAAALAADCgcIBwAAAA==.',Xy='Xyliano:BAAALAAECgYIBgABLAAECgcICgACAAAAAA==.Xyóng:BAAALAAECgEIAQAAAA==.',['Xê']='Xêrxus:BAAALAAECgIIAgAAAA==.',Ya='Yaemiko:BAAALAADCgMIAwABLAADCggICAACAAAAAA==.Yalfyr:BAAALAAECgMIBgAAAA==.Yaranie:BAAALAADCggICAAAAA==.Yartdos:BAAALAAECgMIAwAAAA==.Yasera:BAAALAADCgEIAQAAAA==.',Yo='Yoshino:BAAALAADCggICAAAAA==.',Yu='Yunseo:BAAALAADCgcIBwAAAA==.',Za='Zaelara:BAAALAADCgYIBgAAAA==.Zauberträne:BAAALAADCgcIBwAAAA==.Zaxirus:BAAALAADCgYIBgAAAA==.',Ze='Zenitsu:BAAALAAECgQIBAAAAA==.Zevorox:BAAALAAECggICQAAAA==.',Zu='Zubo:BAAALAAECgcIEAAAAA==.Zugou:BAAALAAECgEIAQAAAA==.Zulthalor:BAAALAADCgYIBQAAAA==.',Zy='Zyanic:BAAALAAECgEIAQAAAA==.',Zz='Zzok:BAAALAAECgEIAQAAAA==.',['Zä']='Zänker:BAAALAAECgEIAQAAAA==.',['Zé']='Zévorox:BAAALAADCgMIAwAAAA==.',['Zô']='Zôdîác:BAAALAAECgMIBAAAAA==.Zôron:BAAALAADCgcIEQAAAA==.',['Àe']='Àeôwyn:BAAALAAECgIIAgAAAA==.',['Àf']='Àflexx:BAAALAAECgIIBQAAAA==.',['Àn']='Àndre:BAABLAAFFIEGAAIJAAIIXCG5BADCAAAJAAIIXCG5BADCAAAAAA==.',['Àr']='Àrahano:BAAALAAECgcIEAAAAA==.',['Áa']='Áang:BAAALAADCgEIAQAAAA==.',['Ár']='Árahano:BAAALAADCggIDwABLAAECgcIEAACAAAAAA==.',['Áz']='Ázael:BAAALAADCgMIAwAAAA==.',['Âr']='Âragorn:BAAALAADCgcIEwAAAA==.',['Ór']='Órózín:BAAALAADCggIDwAAAA==.',['Ýa']='Ýasuo:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end