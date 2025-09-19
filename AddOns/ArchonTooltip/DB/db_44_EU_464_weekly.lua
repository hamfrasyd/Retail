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
 local lookup = {'Unknown-Unknown','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warlock-Destruction','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','Warrior-Fury','Warlock-Demonology','Monk-Windwalker','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival',}; local provider = {region='EU',realm='Shattrath',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aaragom:BAAALAAECgEIAQAAAA==.',Ab='Abígs:BAAALAAECgYIDQAAAA==.',Ad='Adaira:BAAALAADCgMIAwAAAA==.Adhemar:BAAALAADCggICAAAAA==.Adhiambo:BAAALAADCgIIAgAAAA==.',Ai='Airwoker:BAAALAAECgMIAwAAAA==.Aiwia:BAAALAAECgYICAAAAA==.',Ak='Akitara:BAAALAADCgIIAgAAAA==.Akkani:BAAALAADCggIEAAAAA==.',Al='Alangor:BAAALAADCggIEAAAAA==.Alatáriël:BAAALAAECgUICwAAAA==.Alená:BAAALAADCgcIDgAAAA==.Alleni:BAAALAADCggICAAAAA==.Alphorn:BAAALAADCgcICgAAAA==.Alpollo:BAAALAAECggIEAAAAA==.Altefluse:BAAALAADCgcIBwAAAA==.Alyria:BAAALAAECgQIBgAAAA==.',Am='Amariel:BAAALAAECgUIBwAAAA==.Ambos:BAAALAADCgMIAwAAAA==.Amdusias:BAAALAADCgQIBAAAAA==.',An='Angzair:BAAALAADCggICAAAAA==.Anhiara:BAAALAAECgcIEQAAAA==.Annea:BAAALAAECgQIBQAAAA==.Anomália:BAAALAAECgYICgAAAA==.Antropíen:BAAALAADCgcICQAAAA==.',Ar='Arodel:BAAALAAECgYICwAAAA==.Arwi:BAAALAAFFAEIAQAAAA==.Arèsz:BAAALAAECgIIAgAAAA==.',As='Ascalin:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Ashandra:BAAALAAECgEIAQAAAA==.Ashline:BAAALAADCggICAAAAA==.Ashlon:BAAALAAECgEIAQAAAA==.Ashítaka:BAAALAADCgcICwAAAA==.',At='Atorus:BAAALAAECgMIBAAAAA==.Atrêus:BAAALAADCgcIBwAAAA==.Attacka:BAAALAADCgYIBgAAAA==.',Av='Avri:BAAALAADCgUIBQAAAA==.',Aw='Awebo:BAAALAADCggIFAAAAA==.Awyn:BAAALAAECgYICQAAAA==.',Ay='Ayida:BAAALAAECgYICQAAAA==.',Az='Azeyra:BAAALAAECgQIBAAAAA==.Azk:BAAALAAECgMIBQAAAA==.Azsuna:BAAALAAECgYIDAAAAA==.Azzula:BAAALAADCgcICgABLAAECgMIAwABAAAAAA==.',Ba='Balín:BAAALAADCggIFAAAAA==.Baranov:BAAALAADCggIDAAAAA==.Barrexx:BAAALAAECgQIBQAAAA==.Batschdrake:BAAALAAECgMIAwAAAA==.',Be='Bearforce:BAAALAADCgEIAQAAAA==.Belzorash:BAAALAADCggICAAAAA==.Beschamel:BAAALAADCgcICwAAAA==.',Bi='Bira:BAAALAAECgQIBwAAAA==.Biscaya:BAAALAADCgcIBwAAAA==.',Bl='Blackdragon:BAAALAADCggIEQAAAA==.Blackheaven:BAAALAAECgcIEAAAAQ==.Blackphoenix:BAAALAADCggICAAAAA==.',Bo='Borium:BAAALAADCggIDQAAAA==.',Br='Bragush:BAAALAAECgUICQAAAA==.Braurox:BAAALAAECgEIAgAAAA==.',['Bä']='Bärnd:BAAALAADCgcICwAAAA==.',['Bó']='Bóbrschurke:BAAALAADCgcIBwAAAA==.',['Bü']='Bürsti:BAAALAADCgYIDgAAAA==.',Ca='Caerwynn:BAAALAAECgQIBwAAAA==.Calyxo:BAAALAADCgYIBgAAAA==.Caraliná:BAAALAADCggIFgAAAA==.Carazahn:BAAALAADCgcIBwAAAA==.',Ch='Cheesedh:BAAALAAECgUIBwAAAA==.Cheysuli:BAAALAAECgEIAQAAAA==.Chiro:BAAALAADCgMIBwAAAA==.Chocolate:BAAALAADCgcIDgAAAA==.Chupapi:BAAALAADCgIIAgAAAA==.',Ci='Cintara:BAAALAAECgIIBAAAAA==.',Co='Coyot:BAAALAAECgMIBAAAAA==.',Cy='Cyberflame:BAAALAAECgYIDQAAAA==.Cyrion:BAAALAAECgMIBAAAAA==.',Da='Daan:BAAALAADCgMIAwAAAA==.Dando:BAAALAAECgYIBgABLAAECggIFwACAFwYAA==.Daneben:BAAALAADCgcIBwAAAA==.Darcan:BAAALAADCgcIDAAAAA==.Darksakura:BAAALAADCgMIAwAAAA==.',De='Deathgrim:BAAALAADCgcIDAAAAA==.Deni:BAAALAAECgQICQAAAA==.Derni:BAAALAADCggIGAAAAA==.Deviltor:BAAALAAECgQIBwAAAA==.',Di='Dienerderêlf:BAAALAADCgYIBgAAAA==.Dimsung:BAAALAADCgIIAgABLAAECgYIDQABAAAAAA==.Dingsdâ:BAAALAADCgcICQAAAA==.Dirand:BAAALAAECgYIDAAAAA==.Dirtyluigi:BAAALAADCggICAAAAA==.',Do='Doccore:BAAALAADCgMIAwAAAA==.Doshy:BAAALAADCgQIBAAAAA==.Dostro:BAAALAAECgIIAgAAAA==.Dothma:BAAALAAECgMIBAAAAA==.',Dr='Drakangel:BAAALAADCgIIAgAAAA==.Drazukí:BAAALAADCggIDgABLAAECggIEgABAAAAAA==.Dreadîa:BAAALAAECgMIAwAAAA==.Dreshhammer:BAAALAADCggIGAAAAA==.Drfùssél:BAAALAADCgUIBQAAAA==.Droxy:BAAALAADCgUIBgAAAA==.',Du='Dudeldi:BAAALAAECgEIAQAAAA==.',['Dâ']='Dâénérys:BAAALAADCgcIBwAAAA==.',['Dä']='Dämolieren:BAAALAAECgIIAgAAAA==.',Eb='Ebensa:BAAALAAECgIIAwAAAA==.',Ed='Eddiee:BAAALAADCgEIAQAAAA==.Edia:BAAALAAECgQIBAAAAA==.Edudu:BAAALAAECgEIAQAAAA==.',Eh='Ehecatl:BAAALAAECgIIAwABLAAECgMIAwABAAAAAA==.',Ei='Eiler:BAAALAAECgYICwAAAA==.',Ej='Ejonavonsaba:BAAALAADCggIDwAAAA==.',El='Eldirina:BAAALAADCggIDAAAAA==.Eldurado:BAAALAAECgYIBgAAAA==.Elementkater:BAAALAADCgcIBwAAAA==.Eluthalanar:BAAALAAECggIBgAAAA==.Elênia:BAAALAADCgcIDwAAAA==.',Er='Erill:BAAALAADCgcICgAAAA==.',Et='Ette:BAAALAAFFAEIAQAAAA==.',Ey='Eyvua:BAAALAADCgcIDgAAAA==.',Fa='Faladee:BAAALAADCggIFgAAAA==.',Fe='Felariel:BAAALAADCgcIBwAAAA==.Felixjaegar:BAAALAAECgEIAQAAAA==.Fellbabe:BAAALAAECgMIBgAAAA==.Feluriân:BAAALAAECgMIBgAAAA==.Fenel:BAAALAAECggICAAAAA==.Fenny:BAAALAADCgcIBwABLAAECgMIBQABAAAAAA==.Feuerpranke:BAAALAAECggIEAAAAA==.',Fi='Fiadh:BAAALAAECgYIDwAAAA==.Finnic:BAAALAADCggIDQAAAA==.Finnik:BAAALAADCgYIAwAAAA==.',Fl='Fleck:BAAALAAECgIIAgAAAA==.Flydechse:BAABLAAECoEXAAQCAAgIXBgHAgArAgACAAcIphcHAgArAgADAAgI/xX+DgAoAgAEAAEIwgIbHgApAAAAAA==.Flyless:BAAALAAECgcIDwAAAA==.',Fo='Foiamaan:BAAALAADCggIDgAAAA==.',Fu='Fuchsteufel:BAAALAAECgYICQAAAA==.',Ga='Garul:BAAALAAECgEIAQAAAA==.',Ge='Geschredder:BAAALAAECgYIBwAAAA==.',Gh='Ghotmog:BAAALAADCggIDgAAAA==.Ghàíst:BAAALAADCggIFgAAAA==.',Gn='Gnoxnox:BAAALAADCggIDQAAAA==.',Gr='Grannyhunter:BAAALAADCgcIBwAAAA==.Granthoudini:BAAALAAECgYICwAAAA==.Gravijnho:BAAALAAECgEIAQAAAA==.Grinzer:BAAALAAECgEIAQAAAA==.Gromir:BAAALAADCgYIBgAAAA==.Grummelchen:BAAALAADCgcIBwAAAA==.Grètel:BAAALAADCgQIBwAAAA==.',Gu='Guccpriest:BAAALAAECgYIBwAAAA==.',Ha='Hanfi:BAAALAAECgcIDQAAAA==.Harriet:BAAALAADCgcICgAAAA==.Hazoc:BAAALAADCggICAAAAA==.',He='Heffernan:BAAALAAECgcIEAAAAA==.Heidelbeeré:BAAALAAECgIIAwAAAA==.Hellgate:BAAALAAECgMIBQAAAA==.Helà:BAAALAADCgIIAgAAAA==.Herakless:BAAALAADCgUIBQAAAA==.Hexii:BAAALAADCgQIBAAAAA==.Hexrider:BAABLAAECoEWAAMFAAgIeCDJCADUAgAFAAgIbiDJCADUAgAGAAQIEBbQEQAiAQAAAA==.',Hi='Highonholy:BAAALAAECgEIAgAAAA==.',Ho='Holdemaid:BAAALAAECgQIBQAAAA==.Holybull:BAAALAADCgUIBQABLAAECgIIAgABAAAAAA==.Hon:BAAALAADCggIBQAAAA==.',Hu='Huppy:BAAALAADCggIFwAAAA==.Hurzlpurzl:BAAALAADCggIEAAAAA==.',Hy='Hyas:BAAALAADCggICAAAAA==.Hyrulê:BAAALAADCgYIBgAAAA==.',['Hâ']='Hânfii:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.Hânfí:BAAALAADCgcIBwABLAAECgcIDQABAAAAAA==.',Il='Illanthya:BAAALAAECgYIBgAAAA==.Ilva:BAAALAAECgcIEAAAAA==.',In='Ineedademon:BAAALAAECgMIAwAAAA==.Inestri:BAAALAAECgIIAgAAAA==.Insulina:BAAALAAECgYIDgAAAA==.',Ir='Iraf:BAAALAADCggIEAAAAA==.',Ja='Jaenná:BAAALAADCgcICgAAAA==.Jagron:BAAALAAECgUIBgAAAQ==.',Je='Jedeimaster:BAAALAADCgYIBwAAAA==.Jennynorman:BAABLAAECoEXAAMHAAgIcSYkAACQAwAHAAgIcSYkAACQAwAIAAEIGhbGgABLAAAAAA==.Jensen:BAAALAADCgQIBAAAAA==.',Ka='Kamino:BAAALAADCggIDgAAAA==.Kampfkater:BAAALAADCgYIBgAAAA==.Karador:BAAALAADCggIGAAAAA==.Karli:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Karltoffel:BAAALAAECgYICQAAAA==.Kathînka:BAAALAADCgcIBwAAAA==.Kautzos:BAAALAAECgIIBAAAAA==.Kazun:BAAALAADCgcIBwAAAA==.',Ke='Keashaa:BAAALAAECgMIBAAAAA==.Kertack:BAAALAADCgcIBwAAAA==.Kettenblitz:BAAALAAECgYIDQAAAA==.Kezuko:BAABLAAECoEXAAIJAAgI6x/3BwD2AgAJAAgI6x/3BwD2AgAAAA==.',Ki='Kiri:BAAALAAECgEIAQAAAA==.Kishyra:BAAALAAECgcIDwAAAA==.Kitharion:BAAALAAECggIEwAAAA==.',Kl='Klaang:BAAALAADCggIFQAAAA==.Klepto:BAAALAADCgQIBAAAAA==.Kløpper:BAAALAADCgUIBgAAAA==.',Ko='Kobsi:BAAALAAECgMIBAAAAA==.Kochi:BAAALAADCggICAAAAA==.Kochom:BAAALAAECgMIBQAAAA==.Kochomsan:BAAALAADCgcIBwAAAA==.Kokw:BAAALAAECgcICwAAAA==.Korra:BAAALAADCggIDQAAAA==.',Kr='Krish:BAAALAADCggICAAAAA==.Krsharh:BAAALAAECgMIAwAAAA==.',Ku='Kurome:BAAALAADCgQIBAAAAA==.Kuroneko:BAAALAAECgMIAwAAAA==.',['Kí']='Kíngsíléncé:BAAALAAECgMIAwAAAA==.',La='Lagorash:BAAALAADCggIEAAAAA==.Lahen:BAAALAAECgQICgAAAA==.Lanaria:BAAALAAECgUICQAAAA==.',Le='Leehla:BAAALAADCgQIBAAAAA==.Lethis:BAAALAADCggIDwAAAA==.',Li='Lidlrogue:BAAALAAECgYIBgAAAA==.Lightbabe:BAAALAADCgEIAQAAAA==.Lightfrost:BAAALAAECgEIAQAAAA==.Lightmage:BAAALAADCgcIBwAAAA==.Linvanmer:BAAALAADCgcIBwAAAA==.',Lo='Lootgenius:BAAALAADCgcIBwAAAA==.Lootlock:BAAALAADCgcIDwAAAA==.Lorthian:BAAALAAECgQIBQAAAA==.Lossplintos:BAAALAADCggICQAAAA==.Lossplîntos:BAAALAADCgIIAgAAAA==.',Lu='Luih:BAAALAAECgEIAQAAAA==.Lumerathil:BAAALAADCgEIAQAAAA==.Lumineè:BAAALAADCggIEAAAAA==.Lunastra:BAABLAAECoEXAAIDAAgI8R4vCACuAgADAAgI8R4vCACuAgAAAA==.Lustling:BAAALAAECggICQAAAA==.Luxetumbra:BAAALAADCggIFQABLAAFFAEIAQABAAAAAA==.',Ly='Lynnya:BAAALAAECgIIAgAAAA==.Lyseria:BAAALAADCgcIBwAAAA==.',['Lê']='Lêviathari:BAAALAADCggIEgABLAAECgMIBgABAAAAAA==.',Ma='Maad:BAAALAAECgYICQAAAA==.Maddoxx:BAAALAAECgYIDQAAAA==.Madga:BAAALAADCggIFwAAAA==.Makurah:BAAALAAECgMIAwAAAA==.Malish:BAAALAADCgcIEAABLAAECgYIDQABAAAAAA==.Malosh:BAAALAAECgYIDQAAAA==.Manisso:BAAALAADCgcICQAAAA==.Manri:BAAALAADCgUIBQAAAA==.Mantier:BAAALAADCgYIBgAAAA==.Mantor:BAAALAADCgcIBwAAAA==.',Mc='Mcslippyfist:BAAALAADCgcIBwAAAA==.',Me='Meanas:BAABLAAECoEWAAQFAAgIgBv/CwCiAgAFAAgIgBv/CwCiAgAGAAMI5AzfGQC3AAAKAAEIqiFxTQBcAAAAAA==.Medôc:BAAALAAECgMIBAAAAA==.Megumin:BAAALAAECgMIAwAAAA==.Meldora:BAAALAADCgYICQAAAA==.Melora:BAAALAAECgMIBAAAAA==.Merila:BAAALAADCgcIBwAAAA==.Merl:BAAALAADCgcIEAAAAA==.',Mi='Miaolina:BAAALAADCggIDAAAAA==.Micaria:BAAALAAECgUIBwAAAA==.Miflox:BAAALAADCgYIBgAAAA==.Milyandra:BAAALAAECgMIBgAAAA==.Mimirín:BAAALAAECgcIDwAAAA==.Mindblast:BAAALAAECgUICwAAAA==.Mirkster:BAAALAAFFAEIAQAAAA==.Mistbehavin:BAAALAADCggICAAAAA==.Miyuki:BAAALAAECgMIAwAAAA==.',Mj='Mjolnir:BAAALAADCgYIBgAAAA==.',Mo='Moodh:BAAALAAECgcICwAAAA==.Mooschu:BAAALAAECgUICQAAAA==.Morgrim:BAAALAADCggICwAAAA==.Morlak:BAAALAADCgcIBwAAAA==.',Mu='Muhchan:BAAALAAECgcIEAAAAA==.Muhrette:BAAALAAECgYICQABLAAECggIFwAHAHEmAA==.Muryna:BAEALAAECgYIBgAAAA==.Muskatnuzz:BAABLAAECoEWAAILAAgI1RUpCQBEAgALAAgI1RUpCQBEAgAAAA==.',My='Mylo:BAAALAADCgYIBgAAAA==.Myzuuba:BAAALAAECgEIAQAAAA==.',['Má']='Máki:BAAALAADCggIEwAAAA==.',['Mî']='Mînîwinnî:BAAALAADCggICAAAAA==.',['Mö']='Mölon:BAAALAADCggICQAAAA==.',Na='Nachtbräu:BAAALAAECgcIEwAAAA==.Nachteule:BAAALAAECgIIAgAAAA==.Narratt:BAAALAAECgMIBQAAAA==.Naruse:BAAALAADCgcIBwAAAA==.Nasaku:BAAALAAECggIDAAAAA==.Natalía:BAAALAAECgMIBQAAAA==.Nayru:BAAALAAECgYICAAAAA==.',Ne='Necroidyo:BAAALAAECgQIBgAAAA==.Nefariti:BAAALAAECgYICgAAAA==.Negmobart:BAAALAADCggIDgAAAA==.Neliél:BAAALAAECgEIAQAAAA==.Nelphi:BAAALAADCgEIAQAAAA==.Nenerie:BAAALAAECgEIAQAAAA==.Neontiger:BAAALAAECgcIDwAAAA==.Neosensive:BAAALAADCgUICgAAAA==.Nephthy:BAAALAADCggIFQABLAAECgMIAwABAAAAAA==.Nerandes:BAAALAAECgcIDwAAAA==.Nevira:BAAALAADCggIEwABLAAECggIEwABAAAAAA==.Neytirii:BAAALAADCgYIBgAAAA==.',Ni='Nightfang:BAAALAADCggICAABLAADCggIFwABAAAAAA==.Niromi:BAAALAAECgQIBwAAAA==.',No='Noraya:BAAALAAECgYICwAAAA==.Novola:BAAALAADCgcIDgAAAA==.',Nr='Nraged:BAAALAADCggIDQAAAA==.',Od='Odinsgeistt:BAAALAADCggICAAAAA==.',Ok='Okara:BAAALAAECgMIAwAAAA==.',Ol='Oldcrow:BAAALAADCgYIBwAAAA==.Oldmcdruid:BAAALAADCgQIBwAAAA==.',Om='Ombre:BAAALAADCgcIBwABLAAECgUIBgABAAAAAQ==.',Oo='Oolok:BAAALAAECgIIAgAAAA==.',Pa='Paladiina:BAAALAADCgEIAQAAAA==.Paladrino:BAAALAADCgcICQAAAA==.Paladöse:BAAALAADCgYIDAAAAA==.Palawin:BAAALAAECgYIBgAAAA==.Pastoré:BAAALAADCggIDgAAAA==.',Pe='Perry:BAAALAADCgQIAgAAAA==.Person:BAAALAAECgEIAQAAAA==.',Ph='Physjcx:BAAALAAECgYIDAAAAA==.',Pl='Plumpshuhn:BAAALAADCggICAAAAA==.',Po='Pongratz:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Potator:BAAALAADCgYIBgAAAA==.',Pr='Prajah:BAAALAADCgIIAgAAAA==.Primeshock:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.Prismaadh:BAAALAAECgQIBAAAAA==.Prismamonk:BAAALAADCggIDwAAAA==.',Pu='Purpleraini:BAAALAADCgQIBAAAAA==.',Py='Pythiâ:BAAALAADCgEIAQAAAA==.',['Pê']='Pêei:BAAALAAECgQICAAAAA==.',Ra='Radumar:BAAALAAECgcIDQAAAA==.Rafur:BAAALAADCggIDgAAAA==.Ragnarög:BAAALAADCggIDwAAAA==.Rahia:BAAALAADCggIDAAAAA==.Raisina:BAAALAADCggIEwAAAA==.Raistlinia:BAAALAADCggICAAAAA==.Rash:BAABLAAECoEXAAIMAAgITCD9CAD9AgAMAAgITCD9CAD9AgAAAA==.Rashnal:BAAALAAECgMIAwAAAA==.Ravnir:BAAALAADCgEIAQAAAA==.Razorback:BAAALAAECgMIBgAAAA==.',Re='Reeo:BAAALAADCggIDgAAAA==.Renadiel:BAAALAADCgcIBwAAAA==.Reonattel:BAAALAADCggIDQAAAA==.Rexxlock:BAAALAADCggICAABLAAFFAIIAgABAAAAAA==.',Rh='Rhumya:BAAALAADCggIFgAAAA==.',Ry='Rykard:BAAALAADCggIDgAAAA==.',['Rá']='Rágnâr:BAAALAADCggIDQAAAA==.',['Rä']='Räubernase:BAAALAADCgYIBgAAAA==.',['Ré']='Rétro:BAAALAAECgYIBwAAAA==.',['Rì']='Rìo:BAAALAADCggICwAAAA==.',['Rú']='Rúin:BAAALAADCgMIAwAAAA==.',Sa='Saevitia:BAAALAAECgMIAwAAAA==.Sajra:BAAALAADCggIFQAAAA==.Sansabinu:BAAALAAECgYIDAAAAA==.Sansibinu:BAAALAADCggICAAAAA==.Sarnur:BAAALAADCgYICAAAAA==.Saítex:BAAALAAECggIEgAAAA==.',Sc='Schandfleck:BAAALAAECggIBgAAAA==.Schigu:BAAALAADCggIDwAAAA==.Schlafbaer:BAAALAAECgIIAgAAAA==.Schwarzmond:BAAALAADCgYIBgAAAA==.Schweinefuß:BAAALAAECgQICgAAAA==.',Se='Sebastiann:BAAALAADCgcIBwAAAA==.',Sh='Shaley:BAAALAADCgcICgAAAA==.Shamone:BAAALAAECgYICwAAAA==.Shedena:BAAALAADCgYICwAAAA==.Shicha:BAAALAADCggIDgAAAA==.Shirei:BAAALAAECgMIAwAAAA==.Shiruhige:BAAALAADCgYIBgAAAA==.Showtek:BAAALAADCgcICwAAAA==.Shyrien:BAAALAAECgEIAQAAAA==.',Si='Siggí:BAAALAAECgcICQAAAA==.Sigrîd:BAAALAAECgMIBAAAAA==.Sillïa:BAAALAAECgQIBwAAAA==.',Sl='Slopari:BAAALAAECggICAAAAA==.Sloxy:BAAALAAECgIIBAAAAA==.',Sn='Snassin:BAAALAADCggIFAAAAA==.Snoueagle:BAAALAAECgMIBgAAAA==.',So='Solsi:BAAALAADCggIEAAAAA==.Sorvis:BAAALAAECggICAAAAA==.',Sp='Specialwomen:BAAALAAECgIIBAAAAA==.Spâcé:BAAALAAECgYICQAAAA==.',Sr='Srap:BAAALAADCgQIBAAAAA==.',St='Strixvaria:BAAALAAECggIDgAAAA==.',Su='Surzun:BAAALAAECgQIBAAAAA==.Sussi:BAAALAADCggIEQAAAA==.Sutario:BAAALAADCggICQAAAA==.',Sw='Swiss:BAAALAAECgMIAwAAAA==.',Sy='Synæsthesia:BAAALAAECgYICAAAAA==.',['Sê']='Sêraphim:BAAALAAECgQIBQAAAA==.',['Sû']='Sûkku:BAAALAADCgcIBwAAAA==.',Ta='Tabin:BAAALAADCgYIBgAAAA==.Tahres:BAAALAADCgQIBAAAAA==.Taithleach:BAAALAADCggIGAAAAA==.Talaros:BAAALAADCgQIBwAAAA==.Talina:BAAALAADCggIFQAAAA==.Talovdh:BAAALAADCgcIDgABLAAECgIIAgABAAAAAA==.Talovpriest:BAAALAAECgIIAgAAAA==.Tamisia:BAAALAADCggICAAAAA==.Taurinia:BAAALAAECgEIAQAAAA==.',Te='Telundas:BAAALAAECgEIAQAAAA==.Tendos:BAAALAAECgcIDAAAAA==.Terrok:BAAALAADCgQIBAAAAA==.Tevent:BAAALAAECgMIAwAAAA==.',Th='Thalodias:BAAALAADCggICAAAAA==.Tharanel:BAABLAAECoEXAAQNAAgIGSWxAwA5AwANAAgIGSWxAwA5AwAOAAQI0h4LIwBnAQAPAAIIbR4CCgC7AAAAAA==.Tharius:BAAALAAECgQIBQAAAA==.Thristessa:BAAALAAECgMIAwAAAA==.Thronos:BAAALAAECgYICAAAAA==.Thygrå:BAAALAADCggICAABLAAECggIFgAFAIAbAA==.Thédeaa:BAAALAADCggIFAAAAA==.',Ti='Tigerlover:BAAALAAECgUICgAAAA==.',To='Tobsch:BAAALAADCgcIBwAAAA==.Todesseele:BAAALAAECgIIAgAAAA==.Tore:BAAALAAECggIBAAAAA==.Toril:BAAALAAECgIIAwAAAA==.',Tr='Trapmeplz:BAAALAADCggIEAAAAA==.Troxes:BAAALAADCgYIBwAAAA==.Truxxes:BAAALAADCgcIBwAAAA==.',Ts='Tschitschi:BAAALAADCggIFwAAAA==.',Tu='Tungusa:BAAALAADCgQIBwAAAA==.',Ty='Tyrella:BAAALAAECgMIAwABLAAECgUICwABAAAAAA==.',['Tá']='Tátí:BAAALAADCgEIAQAAAA==.',['Tì']='Tìxxn:BAAALAADCgcIBwAAAA==.',Ud='Udinson:BAAALAADCggIFwAAAA==.',Ul='Ultimaratiox:BAAALAADCgEIAQAAAA==.',Un='Unnei:BAAALAADCgQIBAAAAA==.',Uz='Uzgrim:BAAALAADCggICAAAAA==.',Va='Valaria:BAAALAADCggIDwAAAA==.Varandis:BAAALAAECgcIEAAAAA==.Varmir:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.',Ve='Vekthor:BAAALAADCggIDgAAAA==.Veldora:BAAALAADCggIDwAAAA==.Venelor:BAAALAADCgQIBAAAAA==.',Vh='Vhorash:BAAALAAECgYIBQABLAAECggIFwAHAHEmAA==.',Vi='Vivid:BAAALAAECgcIEgAAAA==.',Vo='Voltboy:BAEALAAECgQIBQABLAAECgYIBgABAAAAAA==.',Vu='Vualatan:BAAALAADCggICAAAAA==.',Vy='Vyanter:BAAALAADCggICAAAAA==.',Wa='Waidbauer:BAAALAAECggIBQAAAA==.',Wl='Wlad:BAAALAAECgcIEwAAAA==.',['Wé']='Wétwet:BAAALAADCgcIEwAAAA==.',Xa='Xanderan:BAAALAAECgMIBAAAAA==.',Xh='Xhou:BAAALAADCggICQAAAA==.Xhulbarak:BAAALAADCggICAABLAAECggIFwACAFwYAA==.',Xy='Xymar:BAAALAAECgUIBgAAAA==.Xyxis:BAAALAADCggIDwAAAA==.',['Xî']='Xîmena:BAAALAADCgcICgAAAA==.',Ya='Yarw:BAAALAADCgMIAwAAAA==.',Yi='Yilvilna:BAAALAAECgIIAgAAAA==.',Yn='Yngvar:BAAALAAECgQICgAAAA==.',Yu='Yukari:BAAALAADCggIGAAAAA==.Yumilein:BAAALAAECgIIAgAAAA==.',['Yô']='Yôen:BAAALAAECgQICgAAAA==.',Za='Zahìrí:BAAALAAECgIIAgAAAA==.Zamael:BAAALAAECgYIDQAAAA==.Zartas:BAAALAAECgIIAgAAAA==.',Ze='Zenpai:BAAALAAECgMIAwAAAA==.Zentauren:BAAALAADCgcICAAAAA==.Zeppo:BAAALAADCgQIBAABLAAECggIFwAMAEwgAA==.Zerberius:BAAALAADCggIFQABLAAFFAEIAQABAAAAAA==.',Zo='Zombinar:BAAALAADCgUIBQAAAA==.Zoopreme:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Zoppo:BAAALAADCggIGAAAAA==.Zoshy:BAAALAADCggIGAAAAA==.',Zu='Zuggy:BAAALAADCgEIAQAAAA==.Zugs:BAAALAAECgIIAgAAAA==.Zunara:BAAALAAECgMIBAAAAA==.',Zw='Zwergpresso:BAAALAADCggIDwAAAA==.',Zy='Zyralion:BAAALAAECgIIAwAAAA==.',['Zû']='Zûnade:BAAALAADCgIIAgAAAA==.',['Àr']='Àragorn:BAAALAAECgMIBAAAAA==.',['Ár']='Árthur:BAAALAADCgQIBAAAAA==.',['Ân']='Ânimâl:BAAALAADCgEIAQAAAA==.',['Æs']='Æscanor:BAAALAADCggIDgAAAA==.',['Ív']='Ívý:BAAALAADCgIIAgAAAA==.',['Ðe']='Ðeadpool:BAAALAADCgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end