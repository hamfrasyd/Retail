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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Paladin-Holy','Priest-Holy','Paladin-Retribution','Monk-Brewmaster','Priest-Shadow','Monk-Windwalker','Warrior-Arms','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warlock-Destruction','DeathKnight-Blood','DeathKnight-Frost',}; local provider = {region='EU',realm='Garrosh',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abgrundhexer:BAAALAADCgcIBwAAAA==.Absol:BAAALAADCgMIAwAAAA==.Abýz:BAAALAAFFAIIAgAAAA==.',Ac='Acidera:BAAALAADCgUIBQABLAAECgMIAwABAAAAAA==.',Ad='Adéén:BAAALAAECgMIAwABLAAECggIGAACAMskAA==.',Al='Alariah:BAAALAAECgYICwAAAA==.Alexader:BAAALAADCgUIAQAAAA==.Alun:BAAALAADCgIIAgAAAA==.',Am='Amallia:BAAALAADCgcIDAAAAA==.Amh:BAAALAAECgYICQAAAA==.',An='Annaa:BAABLAAECoEXAAIDAAgI5BwnBACtAgADAAgI5BwnBACtAgAAAA==.Annsarah:BAAALAADCgUIBQAAAA==.Anonymous:BAAALAADCgQIBQAAAA==.Anthenius:BAAALAADCggIFAAAAA==.Anticron:BAAALAADCggICAAAAA==.',Ar='Aragir:BAAALAADCgcIBwAAAA==.Armadie:BAAALAADCgcIBwAAAA==.Armadíe:BAAALAAECgQIBQAAAA==.Armorgeddon:BAAALAAECgEIAQAAAA==.Arístokrat:BAAALAADCgcICwAAAA==.',As='Ashamane:BAAALAAECgQIBgAAAA==.Astralixia:BAAALAAECgQIBAAAAA==.',At='Athail:BAAALAAECgYIDAABLAAECggIFwADAOQcAA==.Atzatharg:BAAALAAECgcIAwAAAA==.',Aw='Awesomelulz:BAAALAADCggIEAABLAAECgYIDAABAAAAAA==.',Ax='Axolotlupi:BAAALAADCgUIBQAAAA==.',Ba='Baarandur:BAAALAADCgMIAwAAAA==.Balze:BAAALAADCgMIAQABLAAECggICAABAAAAAA==.Bamo:BAAALAADCggIDwAAAA==.Bargan:BAAALAADCgcIBwAAAA==.Batmán:BAAALAADCggIFgABLAAECgcIEAABAAAAAA==.Bayura:BAAALAAECgUIBgAAAQ==.',Be='Beefex:BAAALAADCgcIBwAAAA==.Beefzy:BAAALAAECgYIDAAAAA==.Begu:BAAALAADCgYIBgAAAA==.',Bl='Blackdoom:BAAALAAECgIIAgAAAA==.Blobfîsh:BAAALAAECgcIDgAAAA==.Blockie:BAAALAAECgQIBwAAAA==.Bloodyhex:BAAALAADCgYICQAAAA==.Bloodymäry:BAAALAADCgcIBwAAAA==.',Bo='Bobderbär:BAEALAAECggIEgAAAA==.Boggy:BAAALAADCgYICAAAAA==.Bonecrusher:BAAALAADCgUIBgAAAA==.Bonnechance:BAAALAADCgUIBQAAAA==.',Br='Brainingbad:BAAALAAECgcIDwAAAA==.Brokentusk:BAAALAAECgMIBQAAAA==.Bryismad:BAAALAAECgYICgAAAA==.',Bu='Bumbumweg:BAAALAAECgUIBQAAAA==.',['Bâ']='Bâêrnig:BAAALAAECggICAAAAA==.',['Bí']='Bíerwanz:BAAALAADCggICAAAAA==.Bíllow:BAAALAAECgEIAQABLAAECgcIEAABAAAAAQ==.',Ca='Cade:BAAALAAFFAIIAgAAAA==.Cadidh:BAAALAAECgQIBQAAAA==.Cake:BAAALAADCggIFgAAAA==.Calturion:BAAALAAECgIIAgAAAA==.Carlomc:BAAALAAECgIIAgAAAA==.Carnitin:BAAALAADCgYIBgAAAA==.Casual:BAAALAAECgcIEAAAAA==.Cañuma:BAAALAADCggIFwAAAA==.',Ce='Celestriá:BAAALAAECgMIAwAAAA==.',Ch='Chaosgaia:BAAALAADCgcIBwAAAA==.Chaoslight:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.Chaosshadow:BAAALAAECgcIEQAAAA==.Chelay:BAAALAADCgYICwAAAA==.Chimaron:BAAALAADCggICwAAAA==.Chrowok:BAAALAAECgIIAwAAAA==.',Co='Coimbra:BAAALAAECgIIAgAAAA==.Coll:BAAALAADCgYICgAAAA==.Coraliné:BAAALAAECgQIBAABLAAECggIFwAEAO8GAA==.Covén:BAAALAADCgQIBAAAAA==.',Cr='Critalya:BAAALAAECgcIBwAAAA==.Crybaby:BAAALAAECgIIBAABLAAECgcIDwABAAAAAA==.',Cu='Culprit:BAAALAAECgQIBwAAAA==.',Cy='Cynoga:BAAALAADCggIDwAAAA==.Cyreen:BAAALAADCgMIBAAAAA==.',Da='Dadreki:BAAALAAECgEIAQAAAA==.Dafóx:BAAALAAECgIIBAAAAA==.Dagobertha:BAAALAADCgQIBAAAAA==.Dajimmy:BAAALAADCgcIBwAAAA==.Dakazu:BAAALAADCggIFQAAAA==.Dalans:BAAALAADCgUICAAAAA==.Dalrima:BAAALAAECgcICwAAAA==.Danielá:BAAALAAECgMIAwAAAA==.Darkbow:BAAALAAECgIIAgAAAA==.Darksmarargd:BAAALAADCgQIBAAAAA==.Darthmuh:BAAALAAECgQIBAAAAA==.',De='Deltâ:BAAALAADCggICAAAAA==.Delørix:BAAALAADCgcIDQAAAA==.Derzerp:BAAALAADCgMIAwAAAA==.Derzerpa:BAAALAADCgcIDQAAAA==.Dexymage:BAAALAADCgYICQAAAA==.',Di='Dianty:BAAALAAECgYIDgAAAA==.',Do='Docgobby:BAAALAAECgIIAgAAAA==.Doktore:BAAALAADCgEIAQAAAA==.Donnerschlag:BAAALAADCggIEAAAAA==.Doragan:BAAALAADCggICAAAAA==.Dorino:BAAALAADCgcIBwAAAA==.Dorkifan:BAAALAADCgcIDQAAAA==.',Dr='Draggrozwerk:BAAALAAECgYICQAAAA==.Drakzon:BAAALAAECgYIEgAAAA==.Drawâ:BAAALAADCgMIAwAAAA==.Drogul:BAAALAAECgYIBQAAAA==.Drâggrô:BAAALAADCggICAAAAA==.',Du='Duplina:BAABLAAECoEWAAIFAAgIKCBDCQD6AgAFAAgIKCBDCQD6AgAAAA==.Durbomir:BAAALAADCgcIBwAAAA==.',['Dä']='Dämonenfluse:BAAALAADCgcIBwAAAA==.Dämonenhérz:BAAALAADCgcIBwAAAA==.',['Dé']='Désteny:BAAALAADCggIFgAAAA==.',['Dó']='Dón:BAAALAAECgQICgAAAA==.',['Dö']='Dödliknödli:BAAALAAECgYIBgAAAA==.',['Dü']='Düsendrieb:BAAALAADCgEIAQAAAA==.',Ef='Efey:BAAALAAECgYIBwABLAAECggIFgAFACggAA==.',Ei='Eikinskjaldi:BAAALAADCggIDwAAAA==.Einszweidrei:BAAALAADCggICAAAAA==.',El='Eleanorá:BAAALAADCgYIBgAAAA==.Eleonoré:BAAALAADCggICQAAAA==.Elfríedé:BAAALAADCgYIBgAAAA==.',Eq='Eqedqe:BAAALAAECgcIEAAAAA==.Equitis:BAAALAADCggICAAAAA==.',Er='Erytheia:BAAALAADCggIDQAAAA==.Erza:BAAALAADCgYIBgAAAA==.',Es='Escalîa:BAAALAAECgMIBgAAAA==.Espresso:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Estrîâ:BAAALAAECgYIBgAAAA==.',Eu='Euterlyptus:BAAALAADCgcIFAAAAA==.',Ev='Evingolis:BAAALAADCggICAAAAA==.',Ey='Eycha:BAAALAAECgcIDwAAAA==.Eysangel:BAAALAADCgcIBwAAAA==.',Fa='Fadril:BAAALAADCgcIBwAAAA==.Fandaerin:BAAALAADCggIEAAAAA==.Fanji:BAAALAAECgQIBAAAAA==.Faronea:BAAALAAECgEIAQAAAA==.Fayence:BAAALAAECgYICQAAAA==.',Fe='Feyz:BAAALAAECggICAAAAA==.',Fi='Finaliin:BAAALAAECgQIBwAAAA==.Finstermann:BAAALAAECggIDQAAAA==.Fizzlegrim:BAAALAADCggICAAAAA==.',Fl='Flatcko:BAAALAAECgMIAwAAAA==.Fleischie:BAAALAAECgYIBwAAAA==.Flirá:BAAALAAECgIIAgAAAA==.',Fr='Freudidh:BAAALAAECgQIBAAAAA==.Fréúdii:BAAALAADCggIFgABLAAECgQIBAABAAAAAA==.',Fu='Fuchsgeist:BAAALAAECgUIBAAAAA==.Fuchslein:BAAALAAECggICAAAAA==.',Ga='Gandarwa:BAAALAADCggIEgAAAA==.Gargamelh:BAAALAADCgcIBwAAAA==.Gasbo:BAAALAADCggICAAAAA==.',Ge='Gezmo:BAAALAADCgYIBAABLAADCgcIAQABAAAAAA==.',Gi='Giggety:BAAALAAECggICAAAAA==.Gingayce:BAAALAADCgEIAQAAAA==.',Go='Golgary:BAAALAAECgYIDAAAAA==.Golgoth:BAAALAAECgEIAQAAAA==.Gondalf:BAAALAAECgMIBgAAAA==.',Gr='Grauschimmer:BAAALAAECgYIDAAAAA==.Greenarrów:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.Gripinho:BAAALAAECgQIAgABLAAECggIFgAGAAokAA==.Großváter:BAAALAADCgcICgAAAA==.Grönerotto:BAAALAADCggIDgAAAA==.',Gu='Gustavogusto:BAAALAADCggICAAAAA==.',Gw='Gwiltor:BAAALAAECgIIAwAAAA==.Gwismo:BAAALAADCgcIAQAAAA==.',['Gâ']='Gâladriel:BAAALAAECgIIAgAAAA==.',['Gö']='Gönrgy:BAAALAAECgMIBgAAAA==.',['Gø']='Gøangár:BAAALAADCgcIBwAAAA==.',Ha='Hado:BAAALAADCggICAAAAA==.Haifer:BAAALAADCggIDQAAAA==.Hakuk:BAAALAADCgEIAQAAAA==.',He='Healduin:BAAALAAECgQIBAABLAAECgYIDgABAAAAAA==.Hearth:BAAALAAECgQIBgAAAA==.Heyimdirk:BAAALAADCgcIBwAAAA==.',Ho='Holdagur:BAAALAADCggIDgAAAA==.Holyhollow:BAAALAADCgYIBgAAAA==.Holythunder:BAAALAADCggIDgAAAA==.Holzkern:BAAALAAECgIIAgAAAA==.Horith:BAAALAADCggICAAAAA==.Horstbert:BAAALAADCgUIBQAAAA==.',Hu='Hugin:BAAALAADCgcIDgAAAA==.',Hy='Hyperaktiv:BAAALAADCgQIBAAAAA==.',['Hí']='Híghlandèr:BAAALAAECgEIAQAAAA==.',Il='Ilaser:BAAALAAECgQIBwAAAA==.',In='Incôrrectx:BAAALAADCgUIBQABLAAFFAIIAgABAAAAAA==.Infamous:BAAALAADCggIFQAAAA==.Ingomage:BAAALAAECgUICQAAAA==.Inrï:BAAALAAECgQICAAAAA==.Inura:BAAALAADCggIFwAAAA==.',Is='Isigard:BAAALAADCgYICAAAAA==.Isummer:BAABLAAECoEWAAIHAAgIbxlODACRAgAHAAgIbxlODACRAgAAAA==.',Ja='Jahar:BAAALAAECgEIAQAAAA==.Jaluni:BAAALAAECgMIBQAAAA==.Jaquénto:BAAALAAECgYIBgAAAA==.Jatayu:BAAALAADCgQIBAAAAA==.Jazmín:BAAALAADCggICAABLAADCggIEAABAAAAAA==.',Je='Jenni:BAAALAAECgcIDQAAAA==.',Jh='Jhinn:BAAALAAECgYIBgAAAA==.',Jo='Jogia:BAAALAADCgcICQABLAADCgcIDwABAAAAAA==.Joglyce:BAAALAADCggIEgAAAA==.Joki:BAAALAADCgcIDwAAAA==.Jollo:BAAALAADCgcIBwAAAA==.',Ju='Judo:BAAALAAECggIEAAAAA==.Junji:BAAALAADCggICQAAAA==.Juwie:BAAALAADCgYIBgABLAADCggICwABAAAAAA==.',Ka='Kaeldrisia:BAAALAADCgYIBgAAAA==.Kaeyghi:BAAALAADCgcIBwAAAA==.Kampfeuter:BAAALAAECgIIAgAAAA==.Kangul:BAAALAAECgMIAwAAAA==.Kantha:BAAALAADCgYIBgAAAA==.Karamelli:BAABLAAECoEWAAMGAAYIviEZBwAyAgAGAAYIuCEZBwAyAgAIAAYImR5pCgAoAgAAAA==.Karnak:BAAALAADCgcIBwAAAA==.Katerine:BAAALAADCgMIAwAAAA==.',Ke='Keldashdalan:BAAALAAECgUICAAAAA==.',Ki='Kill:BAABLAAECoEWAAIJAAgIDRzeAQCaAgAJAAgIDRzeAQCaAgAAAA==.Killerkaio:BAAALAAECgIIBAAAAA==.Killerkaió:BAAALAADCggICAABLAAECgIIBAABAAAAAA==.Kinderbueno:BAAALAAECgUICQABLAAECggIGAACABomAA==.Kiralia:BAAALAADCgcIBwAAAA==.Kissme:BAAALAAECgYIDAAAAA==.',Kl='Klay:BAAALAAECgMIBAAAAA==.',Kn='Knochenluda:BAAALAADCgQIBAAAAA==.Knödlidödli:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.',Ko='Kowaki:BAAALAAECgYIBgAAAA==.',Kr='Kraxion:BAAALAADCggICAAAAA==.Kruppe:BAAALAADCgQIBAAAAA==.',Ks='Ksderbozz:BAAALAADCggIFQAAAA==.',Ku='Kuhmuckl:BAAALAADCggIEAAAAA==.Kurschd:BAAALAAECgQICgAAAA==.Kuschelbräu:BAAALAADCgUIBQAAAA==.Kuzii:BAAALAAECggIEAAAAA==.',Ky='Kyreya:BAAALAADCgUIAwABLAAECgMIBQABAAAAAA==.Kyriae:BAAALAAECgMIBQAAAA==.',['Ká']='Kálim:BAAALAAECgEIAQAAAA==.',La='Lacyina:BAAALAADCgUIBQAAAA==.Larry:BAAALAAECgUICAAAAA==.Laysana:BAAALAADCggICAAAAA==.',Le='Learra:BAAALAADCgEIAQAAAA==.Lehana:BAAALAADCgMIAQAAAA==.Leilla:BAAALAADCgcIBwAAAA==.Lelani:BAAALAAECgUICAAAAA==.',Li='Linna:BAAALAADCgQIBAAAAA==.Linstren:BAAALAAECggICAAAAA==.Littelbird:BAAALAAECgUIBwAAAA==.',Lo='Loa:BAAALAADCgIIAQAAAA==.Loonix:BAAALAADCgUIBQAAAA==.Loordurion:BAAALAADCgcIFQAAAA==.Louiscypher:BAAALAAECgMIBAAAAA==.',Lu='Lucalappen:BAAALAADCgcIBwAAAA==.Luciyana:BAAALAAECgYIBwAAAA==.Lucyari:BAAALAADCgYIBgAAAA==.Lukrezîa:BAAALAAECgYICgAAAA==.',Ma='Macpower:BAAALAAECgcIBwAAAA==.Maggow:BAAALAAECgcIEAAAAQ==.Magicnursê:BAAALAADCggICAAAAA==.Makima:BAAALAAECgIIAgAAAA==.Maldiria:BAAALAAECgEIAQAAAA==.Mandoliene:BAAALAADCgQIBAAAAA==.Maníss:BAAALAADCgYIBgAAAA==.Maphi:BAAALAADCgYIBgAAAA==.Marciey:BAAALAAECgEIAQAAAA==.Mariton:BAAALAAECgYIDQAAAA==.Masataka:BAAALAAECgcIDwAAAA==.Massá:BAAALAAECgUICAAAAA==.Mausefalle:BAAALAAFFAMIAwAAAA==.',Me='Meixiu:BAAALAAECgUIBwAAAA==.Meryn:BAAALAAECgcIDQAAAA==.Metrexa:BAAALAAECgYICQAAAA==.Metze:BAAALAADCgcIBwAAAA==.Meuchelmichi:BAAALAAECgMIAwAAAA==.',Mi='Miimic:BAAALAADCgcIBwAAAA==.',Mo='Mohlturm:BAAALAAECgMIAwAAAA==.Monkinho:BAABLAAECoEWAAIGAAgICiQ7AQBCAwAGAAgICiQ7AQBCAwAAAA==.Monokumá:BAAALAADCgcIBwABLAADCggIFQABAAAAAA==.Monuria:BAAALAADCggICAABLAADCggIEAABAAAAAA==.Mortality:BAAALAAECgIIAQAAAA==.Mostreta:BAAALAAECggICAAAAA==.',Mu='Muhffelig:BAAALAAECgIIAwAAAA==.Musclemán:BAAALAADCgQIBAAAAA==.',My='Mysticelfe:BAAALAAECgMIAwAAAA==.',['Mà']='Màldiria:BAAALAADCgcIDwAAAA==.Màylin:BAAALAADCgcIBwAAAA==.',['Má']='Máríéé:BAAALAAECgEIAQAAAA==.',Na='Nafia:BAAALAAECgMIBAAAAA==.Nailo:BAAALAAECgIIAgAAAA==.Nayama:BAAALAADCggIDQAAAA==.',Ne='Near:BAABLAAECoEWAAQKAAgIIRpECQCWAgAKAAgIIRpECQCWAgALAAMIpRJbBgCjAAAMAAEIZgvqGwA8AAAAAA==.Neklishe:BAAALAADCgIIAgABLAAECggICAABAAAAAA==.Nepharox:BAAALAAECgYICAAAAA==.Neroonia:BAAALAADCgcIBwABLAADCggICwABAAAAAA==.Nerup:BAAALAADCgYIBAAAAA==.Nerò:BAAALAADCgcIBwAAAA==.Nerôôîâ:BAAALAADCggICwAAAA==.Nexgenaddy:BAAALAAECgYICwAAAA==.',Ni='Nichtdiemama:BAAALAADCgcIBwAAAA==.Niemánd:BAABLAAECoEXAAIEAAgI7wZCKAB/AQAEAAgI7wZCKAB/AQAAAA==.Nightshamen:BAAALAAECgcIEAAAAA==.Nindel:BAAALAADCgcIBwAAAA==.',Nu='Nutzlos:BAAALAAECgcIDQAAAA==.',Ny='Nynthara:BAAALAADCggIDwAAAA==.',['Nê']='Nêbrà:BAAALAADCgMIAwABLAAECgQIBAABAAAAAA==.',Oh='Ohnoi:BAAALAAECgQIBgAAAA==.',Ol='Olirasa:BAAALAAECgcICgAAAA==.',Or='Orkania:BAAALAADCgcIBwAAAA==.Orlin:BAAALAADCgIIAQAAAA==.',Pa='Pandaduda:BAAALAADCgYIBgABLAAECggIEQANAN0hAA==.Panem:BAAALAAECgQIDQAAAA==.Pani:BAAALAADCgcIBwAAAA==.Panker:BAAALAADCggICAAAAA==.Pantalaimon:BAAALAAECgYICQAAAA==.Paruc:BAAALAADCggICgAAAA==.Paruuk:BAAALAAECgIIBAAAAA==.',Pe='Pentra:BAAALAADCgYIBgABLAADCgcIEwABAAAAAA==.Pepperdyne:BAAALAAECgcIEAAAAA==.',Pl='Planiox:BAAALAAECgEIAQAAAA==.',Pr='Pre:BAAALAAECgUICgAAAA==.',Pz='Pzudemlanlos:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Qu='Quely:BAAALAADCggIDQAAAA==.Quendo:BAAALAAECgMIBAAAAA==.',Ra='Raeny:BAAALAADCgcICwAAAA==.Raenyres:BAAALAAECgcIEAAAAA==.Rahkua:BAAALAADCgcIBwAAAA==.Rakhalár:BAAALAADCggIFQAAAA==.Ranish:BAAALAAECgYIBgAAAA==.Rastinaa:BAAALAADCgcICAAAAA==.Ratos:BAAALAADCggIDwAAAA==.Ravaan:BAAALAAECggIDQAAAA==.Ravé:BAAALAADCggICAAAAA==.Raysham:BAAALAAECgYIDQAAAA==.Raysome:BAAALAADCgcIBwAAAA==.Razkul:BAAALAAECgUIBwAAAA==.Razorxy:BAAALAAECgMIBQAAAA==.',Re='Reavz:BAAALAADCgQIBAAAAA==.Reddraenei:BAAALAADCgQIBwABLAADCggICwABAAAAAA==.Reigam:BAAALAADCgMIAwAAAA==.Reshala:BAAALAAECggICgAAAA==.Respire:BAAALAAECggIEwAAAA==.',Ri='Riddler:BAAALAADCgEIAQABLAAECgcIEAABAAAAAA==.Ringix:BAAALAADCggIEgAAAA==.Rishka:BAAALAADCgYIBwAAAA==.Rixda:BAAALAADCgcICAAAAA==.',Ro='Rocknock:BAAALAADCgcIDQAAAA==.Rosenritter:BAAALAAECgMIAwAAAA==.',Ru='Runes:BAAALAADCgcIDgAAAA==.',['Rì']='Rìck:BAAALAAECgMIBgAAAA==.',['Rí']='Rípeyes:BAABLAAECoERAAINAAcI3SE8DACeAgANAAcI3SE8DACeAgAAAA==.Rípeyesmama:BAAALAADCgcICwAAAA==.',Sa='Saamari:BAAALAAECgYIDAAAAA==.Sackbeisser:BAAALAADCggIFwAAAA==.Sahrrama:BAAALAAECgYIBwAAAA==.Samclap:BAAALAAECgYIBgABLAAECgYIDAABAAAAAA==.Samántha:BAAALAADCggIFgAAAA==.Sanrylar:BAAALAAECgMIBAAAAA==.Sansebastian:BAAALAAECgIIBAAAAA==.Saphixe:BAAALAAECggICgAAAA==.Sashinho:BAAALAAECgYICQABLAAECggIFgAGAAokAA==.Savada:BAAALAADCgUIBQAAAA==.Saydie:BAAALAAECgMIAwAAAA==.',Sc='Schattenriss:BAAALAADCggIFwAAAA==.Schaumkrone:BAAALAAECgMIAwAAAA==.Schmug:BAAALAADCgUIBQAAAA==.Schnakkami:BAAALAADCgMIAwAAAA==.Schokocrossi:BAAALAADCgcICQAAAA==.Schrotkäppch:BAAALAADCggIEwAAAA==.',Se='Sebine:BAAALAAECgIIAwAAAA==.Seelass:BAAALAAECgMIAwAAAA==.Senista:BAAALAADCgIIAgAAAA==.Sepsia:BAAALAADCgcIBwAAAA==.Serafíen:BAAALAADCgYIBgAAAA==.Seranava:BAAALAAECgMIBgAAAA==.Sergra:BAAALAAECgMIBwAAAA==.',Sh='Shamu:BAAALAADCgMIAwAAAA==.Shanlana:BAAALAADCgcIEwAAAA==.Sheele:BAAALAADCgQIBAAAAA==.Shâdôw:BAAALAAECgQIBgAAAA==.Shírana:BAAALAAECgcICwAAAA==.',Si='Sierah:BAAALAADCgcIBwAAAA==.Silverharley:BAAALAAECgIIAwAAAA==.Simaliá:BAAALAAECgIIAgAAAA==.Sitandra:BAAALAAECgIIAgAAAA==.',Sk='Skeeb:BAAALAAECgcIBwAAAA==.Skidiwidi:BAAALAAECgYICQABLAAECgcIBwABAAAAAA==.Skylara:BAAALAADCggIEAAAAA==.Skywálker:BAAALAADCggIFgABLAAECgcIEAABAAAAAA==.',Sl='Slark:BAAALAADCggICAAAAA==.',Sm='Smixy:BAAALAAECgEIAQAAAA==.Smoxox:BAAALAADCgIIAgABLAAECgEIAQABAAAAAA==.',So='Solunaria:BAAALAADCggIEAAAAA==.Sorichronos:BAAALAAECgIIAgAAAA==.',Sp='Spekulatius:BAABLAAECoEYAAICAAgIGibGAAB6AwACAAgIGibGAAB6AwAAAA==.',St='Stjpafist:BAACLAAFFIEFAAMIAAMINB7QAAAsAQAIAAMINB7QAAAsAQAGAAIIZgTsBQBrAAAsAAQKgRcAAggACAjjJZYAAG4DAAgACAjjJZYAAG4DAAAA.Stockbrot:BAAALAADCgMIAwAAAA==.Stopschíld:BAAALAAECgUIBgAAAA==.',Su='Surely:BAAALAADCgcIBwABLAAECgQIBgABAAAAAA==.Suzz:BAAALAADCggICAAAAA==.',Sy='Sykran:BAAALAADCgUIBQAAAA==.Synoxi:BAAALAADCgQIBAAAAA==.',['Sâ']='Sâlvâtore:BAAALAADCgMIAwAAAA==.',['Sæ']='Sæmí:BAAALAAECgMIBgAAAA==.',['Sê']='Sêcrêts:BAAALAAECgYICgABLAAFFAIIAgABAAAAAA==.',['Sî']='Sînclair:BAAALAAECgYICgAAAA==.',Ta='Taicuno:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.Taiyô:BAAALAADCggIDQABLAAECgMIBQABAAAAAA==.Takkan:BAAALAAECgYIAgAAAA==.Talagar:BAAALAAECgIIAwAAAA==.Talande:BAAALAAECgEIAQAAAA==.Talasha:BAAALAAECgQIBwAAAA==.Talgat:BAAALAADCgYIBwAAAA==.Tarkatov:BAAALAAECgcIEAAAAA==.Tarokk:BAAALAAECgcIDQAAAA==.Taxx:BAACLAAFFIEFAAIOAAMI2hzcAAAhAQAOAAMI2hzcAAAhAQAsAAQKgRcAAw4ACAinItUBACADAA4ACAinItUBACADAA8AAQg5AYejAA8AAAAA.',Te='Telazura:BAAALAADCgQIBAABLAAECgUIBgABAAAAAA==.Tepaartos:BAAALAAECgQICAAAAA==.Teril:BAAALAAECgEIAQAAAA==.Teys:BAAALAADCgYICwABLAAECgcICwABAAAAAA==.',Th='Thalanjo:BAAALAADCgIIAgAAAA==.Tholag:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Thorhammer:BAAALAAECgQIBQAAAA==.Thorînu:BAAALAADCggICAAAAA==.Thrahl:BAAALAAECgUIBQAAAA==.Thunderforce:BAAALAAECgMIBQAAAA==.Thunderine:BAAALAAECgYIBgAAAA==.Thyrianá:BAAALAADCgcICwAAAA==.Thôrîn:BAAALAAECgIIBAAAAA==.',Ti='Tingelchan:BAAALAADCggICAAAAA==.',To='Tohrulos:BAAALAAECgYICgAAAA==.Tomtod:BAAALAADCgcIBwAAAA==.Tongaro:BAAALAAECgUICgAAAA==.Tosaz:BAAALAAECgIIBAAAAA==.',Tr='Treibs:BAAALAADCgYIEAAAAA==.Trelliva:BAAALAADCggIEwAAAA==.Triffhuf:BAAALAADCgcIBwAAAA==.',Tu='Tutníx:BAAALAADCgYIBgAAAA==.',Ty='Tyrândê:BAAALAAECgMIAwAAAA==.',Tz='Tz:BAAALAAECgYIBgABLAAFFAIIAgABAAAAAA==.',Un='Unah:BAAALAAECgYIBgAAAA==.',Up='Upsipupsi:BAAALAAECgEIAQAAAA==.',Ur='Urleyn:BAAALAAECgQIBQAAAA==.Urukhei:BAAALAADCggICAAAAA==.',Va='Vanhennig:BAAALAADCgUIBQAAAA==.Vantur:BAAALAADCgYIBgAAAA==.',Ve='Velva:BAAALAAECgQIBgAAAA==.Verurteilt:BAAALAAECgYIBgAAAA==.',Vi='Vitalies:BAAALAADCgcICAAAAA==.',Vo='Vorheez:BAAALAADCgcIBwAAAA==.',['Vô']='Vôlji:BAAALAADCgQIBAAAAA==.',Wa='Walky:BAAALAAECgQIBgAAAA==.Warsic:BAAALAAECgYIDQAAAA==.',We='Welerik:BAAALAAECgMIAwABLAAECggIFgAFACggAA==.',Wo='Worgenblitz:BAAALAADCggIEAAAAA==.Worgina:BAAALAAECgEIAQAAAA==.',Wy='Wyver:BAAALAADCgcIBwAAAA==.',['Wá']='Wáchterin:BAAALAADCggIFAAAAA==.',['Wí']='Wítchkíng:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.',Xa='Xalatoph:BAAALAADCggICAAAAA==.Xalatroth:BAAALAAECgIIAwAAAA==.Xarínah:BAAALAADCggICAAAAA==.',['Xà']='Xàrdàs:BAAALAADCgcIEAAAAA==.',['Xá']='Xárion:BAAALAAECgYICQAAAA==.',Ya='Yamazaka:BAAALAADCggICAAAAA==.',Ye='Yerek:BAAALAADCgIIAgABLAAECgMIBQABAAAAAA==.',Yg='Yggirana:BAAALAAECgcIEAAAAA==.',Yi='Yiesera:BAAALAAECgIIAgABLAAECgcIDwABAAAAAA==.',Yo='Yokk:BAAALAADCgYIBgAAAA==.',Za='Zangil:BAAALAADCgcIBwAAAA==.Zanza:BAAALAAECgYIDQAAAA==.',Ze='Zedy:BAAALAAECgcIDwAAAA==.Zenober:BAAALAADCgQIBwAAAA==.Zerobit:BAAALAAECgMIBQAAAA==.Zeronas:BAAALAADCgIIAgAAAA==.Zethy:BAAALAAECgYICgAAAA==.',Zo='Zoes:BAAALAAECgYICQAAAA==.Zoraca:BAAALAADCgcIBwAAAA==.',Zu='Zuckermaus:BAAALAADCggIDwAAAA==.Zugzugorc:BAAALAADCgcIBwAAAA==.',Zy='Zylor:BAAALAAECgYIEQAAAA==.',['Àd']='Àdeen:BAABLAAECoEYAAICAAgIyyRVBAA4AwACAAgIyyRVBAA4AwAAAA==.',['În']='Înaste:BAAALAAECgQICgAAAA==.',['Õk']='Õkami:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end