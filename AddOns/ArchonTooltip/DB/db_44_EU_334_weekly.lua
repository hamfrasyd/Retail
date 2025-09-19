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
 local lookup = {'Unknown-Unknown','DemonHunter-Vengeance','Druid-Guardian','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Havoc','Monk-Windwalker','Warrior-Fury','Paladin-Retribution','Shaman-Restoration','Paladin-Protection','Priest-Holy','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Druid-Restoration','DeathKnight-Frost','Paladin-Holy','Priest-Shadow','Evoker-Preservation','Evoker-Augmentation','Shaman-Elemental','Mage-Arcane','Mage-Fire','Warrior-Protection','Warlock-Affliction','Druid-Balance','Mage-Frost','Hunter-Survival','DeathKnight-Blood','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Unholy','Warrior-Arms','Monk-Mistweaver','Shaman-Enhancement',}; local provider = {region='EU',realm='Stormrage',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Aboleo:BAAALAADCgUIBQABLAABCgQIAwABAAAAAA==.',Ad='Adidasolio:BAAALAADCggICAAAAA==.Adrowyh:BAAALAADCgUIBQAAAA==.',Ae='Aerios:BAAALAADCgcIDgAAAA==.Aethodas:BAAALAAECgUIBQAAAQ==.',Ai='Airish:BAABLAAECoEbAAICAAcIzSB6BQCaAgACAAcIzSB6BQCaAgAAAA==.Aishah:BAAALAAECgYIDQAAAA==.',Aj='Ajfloorpov:BAAALAAECgcICwAAAA==.',Ak='Akilios:BAABLAAECoEUAAIDAAcIVwWKDwDtAAADAAcIVwWKDwDtAAAAAA==.',Al='Alarizen:BAABLAAECoEcAAIEAAgIECK3AQAzAwAEAAgIECK3AQAzAwAAAA==.Aldaeron:BAAALAADCggIFwAAAA==.Allareth:BAAALAADCggICAAAAA==.Almirsamael:BAAALAADCggICQAAAA==.Althrenn:BAAALAAECgcIDAAAAA==.Althrinn:BAABLAAECoEeAAMFAAgImyIgBwAbAwAFAAgImyIgBwAbAwAGAAIIfw5GZgBXAAAAAA==.Alucârd:BAACLAAFFIEFAAIHAAMI5gvpCADpAAAHAAMI5gvpCADpAAAsAAQKgRYAAgcACAh4Go8iAFACAAcACAh4Go8iAFACAAAA.Alveyura:BAABLAAECoEgAAIIAAgI4COfBAADAwAIAAgI4COfBAADAwAAAA==.Alxander:BAABLAAECoEUAAIJAAcIfiDVFAB/AgAJAAcIfiDVFAB/AgAAAA==.',Am='Amahgad:BAAALAADCggIDwABLAAECgcIFwAFAPkgAA==.Amberfrost:BAAALAAECgcIEwAAAA==.Amberstorm:BAAALAADCggIDwAAAA==.Amestor:BAAALAADCgIIAgAAAA==.',An='Angelawhite:BAAALAAECgYIDAAAAA==.Anthem:BAAALAAECgEIAQAAAA==.Anxine:BAABLAAECoEXAAIKAAgIyCKmCAAuAwAKAAgIyCKmCAAuAwAAAA==.',Ap='Apolake:BAABLAAECoEeAAILAAgI6yLgAgAhAwALAAgI6yLgAgAhAwAAAA==.',Ar='Argo:BAAALAAECgUICQAAAA==.Arjent:BAABLAAECoEUAAMMAAgIAgziGgBBAQAMAAgIAgziGgBBAQAKAAEIZAYszQAqAAAAAA==.Arther:BAAALAADCgQIBAAAAA==.Arádior:BAAALAADCggICAAAAA==.',As='Ashlye:BAAALAAECgIIAgAAAA==.Ashyra:BAAALAAECgUICAAAAA==.Astarroth:BAAALAADCgcIBAAAAA==.',At='Atein:BAACLAAFFIEJAAMNAAQIgxfpAQBxAQANAAQI0BXpAQBxAQAOAAIIARqoAACuAAAsAAQKgSAAAw4ACAiGJJIAADEDAA4ACAhmIpIAADEDAA0ACAj/HsAGAPgCAAAA.Ateni:BAAALAAECgYIBgABLAAFFAQICQANAIMXAA==.Atiro:BAAALAAECgEIAQAAAA==.',Au='Augboi:BAAALAAECgEIAQAAAA==.',Av='Averyel:BAAALAAECgcIDAAAAA==.',Az='Azaelan:BAAALAADCggICAABLAAECggIFQAKACEYAA==.Azaelia:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Azmoodan:BAAALAADCggICAAAAA==.Azriel:BAABLAAECoEoAAINAAgIFCR9AgBCAwANAAgIFCR9AgBCAwAAAA==.Azron:BAAALAAECgcIDwAAAA==.',Ba='Ballim:BAAALAAECgMIBAAAAA==.Baltasar:BAAALAADCggICAAAAA==.Bamba:BAABLAAECoEWAAIFAAgIux9NDgDHAgAFAAgIux9NDgDHAgAAAA==.Banacheq:BAAALAADCgQIBAAAAA==.Barach:BAAALAADCgcIEAAAAA==.Basescuu:BAAALAADCggICAAAAA==.Batinix:BAACLAAFFIEIAAIKAAQIPCJHAQCaAQAKAAQIPCJHAQCaAQAsAAQKgR8AAgoACAiVJkUAAJwDAAoACAiVJkUAAJwDAAAA.',Be='Beatrix:BAAALAAECgYIDQAAAA==.Beelzepeach:BAAALAAECgYIDQAAAA==.Beetlegeuse:BAABLAAECoEeAAMPAAgITyKHAQAwAwAPAAgITyKHAQAwAwAQAAEI8g2GjwAqAAAAAA==.Beorn:BAAALAADCgIIAgAAAA==.',Bi='Bidnnbuy:BAAALAAECgcICAAAAA==.Bigmonkw:BAAALAADCggIDgAAAA==.',Bl='Blight:BAAALAADCggICAAAAA==.Blueberri:BAAALAADCgcIFgAAAA==.Blygläppen:BAAALAADCgMIAwAAAA==.',Bo='Bobtastic:BAAALAAECgEIAQAAAA==.Boomslang:BAABLAAECoEYAAIFAAgIbiChCwDlAgAFAAgIbiChCwDlAgAAAA==.',Br='Brìcktop:BAAALAAECgYICQABLAAECggIFgARAK8dAA==.',Bu='Bubbleskillz:BAAALAAECgYICwABLAAECggIGQASAOkdAA==.Bubblé:BAAALAADCgUIBQAAAA==.Bullzéye:BAACLAAFFIEHAAMFAAMITBTtBwC7AAAFAAIIUhntBwC7AAAGAAII/w/uDwCGAAAsAAQKgRYAAwYACAj6IbAMAK0CAAYACAj6IbAMAK0CAAUABAh4FV5hAP8AAAAA.',['Bá']='Báge:BAABLAAECoEcAAIFAAgIPB7dFACGAgAFAAgIPB7dFACGAgAAAA==.',Ca='Cainwyn:BAACLAAFFIEIAAILAAMIpRLJBgDXAAALAAMIpRLJBgDXAAAsAAQKgRUAAgsACAiHCnlKAFMBAAsACAiHCnlKAFMBAAAA.Calq:BAAALAAECgEIAQAAAA==.Cazamataz:BAAALAADCggICAAAAA==.',Ce='Cebara:BAABLAAECoEWAAILAAcIjRl4IwD+AQALAAcIjRl4IwD+AQABLAABCgQIAwABAAAAAA==.Ceiad:BAAALAADCggIEAAAAA==.Cel:BAACLAAFFIEFAAITAAMIpA2xBADvAAATAAMIpA2xBADvAAAsAAQKgR0AAxMACAgRHkYGAJ8CABMACAgRHkYGAJ8CAAoAAwijGemHAO8AAAAA.Cenedra:BAAALAAECgYIDQAAAA==.',Ch='Chaynal:BAAALAADCgUIBgAAAA==.Chillblaster:BAAALAADCgUIBQAAAA==.',Cl='Clap:BAAALAAECgYIBgAAAA==.',Co='Cocobelle:BAAALAAECgUICQAAAA==.Codexx:BAAALAADCgYIBgAAAA==.Coraax:BAAALAAECgYIDQAAAA==.Corallna:BAAALAAECgcIBwABLAAECggIGwAUAK8TAA==.Coratana:BAAALAADCggIGAAAAA==.Corhate:BAAALAADCggIEAAAAA==.Coriolanus:BAAALAADCggIDwAAAA==.Cosimá:BAAALAADCggICAABLAAECgcIFwAEAFEZAA==.',Cp='Cptswallows:BAAALAADCgcICAAAAA==.',Cr='Crunkler:BAACLAAFFIEKAAIUAAQIARmGAgBhAQAUAAQIARmGAgBhAQAsAAQKgR8AAhQACAieJSEBAHcDABQACAieJSEBAHcDAAAA.',Cu='Cucumber:BAACLAAFFIEFAAIVAAQImwgbAgAtAQAVAAQImwgbAgAtAQAsAAQKgRgAAxYACAjFGCEDABoCABYABwh7GSEDABoCABUACAhXEvUKAOABAAAA.Curcuma:BAAALAAECgYIDgAAAA==.Curryman:BAABLAAECoEeAAMKAAgI6R/SDwDnAgAKAAgI6R/SDwDnAgAMAAMIvAn4LwBsAAAAAA==.',Cy='Cytherios:BAAALAAECggICAAAAA==.',['Cé']='Céll:BAAALAADCggICAAAAA==.',Da='Daeey:BAAALAAECgYIEQAAAA==.Daemonian:BAAALAADCggICAABLAAECggIFQAKACEYAA==.Daeston:BAAALAAECgYICAAAAA==.Danarious:BAAALAAECgYIDQAAAA==.Dancé:BAABLAAECoEUAAIXAAcI0BfgIAAKAgAXAAcI0BfgIAAKAgAAAA==.Darki:BAAALAADCggIDwAAAA==.Dawnaw:BAAALAAFFAEIAQAAAA==.Daxiok:BAAALAAECgYICgAAAA==.',De='Deadkai:BAAALAADCggIDQAAAA==.Deadnam:BAAALAADCgYIBgAAAA==.Deadperson:BAAALAAECgYICAAAAA==.Deland:BAAALAAECgYIBgAAAA==.Demonwife:BAAALAAECgIIAgAAAA==.',Dh='Dhebs:BAAALAADCgcIBwAAAA==.',Di='Dilyy:BAACLAAFFIEJAAIGAAQIEBuVAgBNAQAGAAQIEBuVAgBNAQAsAAQKgSAAAgYACAhtJBcDADsDAAYACAhtJBcDADsDAAAA.',Dj='Djungelkorv:BAAALAADCgYICgAAAA==.',Dm='Dmcx:BAACLAAFFIEJAAIYAAQIzxs9BABuAQAYAAQIzxs9BABuAQAsAAQKgRkAAxgACAgSJRAKABIDABgACAgSJRAKABIDABkAAQjpHxMPAFoAAAAA.',Do='Dogsection:BAAALAAECgYICwAAAA==.Dolozplash:BAAALAAECgUICAAAAA==.Dolzök:BAABLAAECoEYAAIFAAgILhllFgB4AgAFAAgILhllFgB4AgAAAA==.Donny:BAABLAAECoEYAAIaAAgIQxWREgDwAQAaAAgIQxWREgDwAQAAAA==.Doomdot:BAABLAAECoEeAAIbAAgIbSHdAAAxAwAbAAgIbSHdAAAxAwAAAA==.Dotgain:BAAALAAECgMIAwAAAA==.',Dr='Drafic:BAAALAAECgYIDQAAAA==.Dratma:BAAALAAECgEIAQAAAA==.Draxl:BAAALAADCgcIBwAAAA==.Dreythani:BAAALAADCggICAAAAA==.Drogerok:BAAALAADCgcICgAAAA==.Drow:BAAALAADCgcIBwAAAA==.',Du='Durst:BAAALAAECgYIDQAAAA==.',Dy='Dynafit:BAAALAAECgUICQAAAA==.',['Dâ']='Dâhl:BAAALAADCgEIAQAAAA==.',['Dì']='Dìem:BAAALAADCgEIAQAAAA==.',Ed='Edgar:BAAALAAECgMIAwAAAA==.Ediwen:BAAALAAECgYICQAAAA==.',El='Elashor:BAAALAAECgIIAgABLAAECgUICQABAAAAAA==.Electraz:BAAALAAECggIAwABLAAECggIEAABAAAAAA==.Elemen:BAAALAADCgQIBAABLAAECgYICQABAAAAAA==.Elenise:BAAALAADCggICAAAAA==.Elirya:BAAALAADCgcIBwAAAA==.Elthariaza:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Em='Emunis:BAAALAADCgYIBgAAAA==.',En='Eneath:BAAALAAECgcIBwAAAA==.',Ep='Epaxiel:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.',Er='Erisalia:BAEBLAAFFIEFAAIaAAMI1BZLAwDqAAAaAAMI1BZLAwDqAAAAAA==.Erny:BAAALAAECgcIEQAAAA==.',Es='Eshi:BAABLAAECoEYAAITAAgILRK+FADfAQATAAgILRK+FADfAQAAAA==.',Ev='Evildaveh:BAAALAAECgYIDQAAAA==.',Ex='Exodite:BAAALAAECgYICQAAAA==.Expresslån:BAAALAADCgUIBQAAAA==.',Ey='Eyebeam:BAAALAAECgYIBgAAAA==.',Fa='Fabbawabba:BAAALAAFFAMIBAAAAA==.Failsmite:BAAALAADCggICAAAAA==.Fathoof:BAAALAAECgYIDAAAAA==.Faxee:BAAALAAECgQIBwAAAA==.',Fe='Feardkt:BAAALAADCggICAAAAA==.Felgalok:BAAALAADCggIDQAAAA==.Fellacage:BAAALAAECgYIDQAAAA==.',Fj='Fjone:BAAALAADCgcIBwAAAA==.',Fl='Flonk:BAAALAADCgYIBgAAAA==.Flyingdin:BAACLAAFFIEIAAIKAAQIGRi9AQBqAQAKAAQIGRi9AQBqAQAsAAQKgSAAAwoACAgbJHcFAE8DAAoACAgbJHcFAE8DABMABAiCBWA2AKQAAAAA.',Fo='Forestboi:BAACLAAFFIEGAAIcAAMItiMrAgA0AQAcAAMItiMrAgA0AQAsAAQKgRgAAhwACAgRJrwEADADABwACAgRJrwEADADAAAA.',Fr='Freddymage:BAABLAAECoEWAAIYAAcIeBtiLQAXAgAYAAcIeBtiLQAXAgAAAA==.Fredsbrödet:BAABLAAECoEYAAITAAcIjR76CABxAgATAAcIjR76CABxAgAAAA==.Freyas:BAAALAAECgUIBQAAAA==.Friendmoney:BAAALAAECgYIDgAAAA==.Frikándel:BAAALAAECgYIDgAAAA==.Frogpizza:BAAALAAECggIEQAAAA==.Frøsty:BAACLAAFFIEIAAIJAAQIRhPVAgBrAQAJAAQIRhPVAgBrAQAsAAQKgRgAAgkACAjwI20LAO0CAAkACAjwI20LAO0CAAAA.',Fu='Futhorc:BAAALAADCgYIBgAAAA==.',['Fá']='Fáxe:BAAALAADCggIEAAAAA==.',['Få']='Fåxe:BAAALAADCgEIAQAAAA==.',Ga='Galonià:BAAALAADCgcICAAAAA==.',Ge='Gembella:BAAALAAECgQIBAAAAA==.Gertrude:BAABLAAECoEVAAIRAAcIDCBGDQB2AgARAAcIDCBGDQB2AgAAAA==.Geyllroth:BAAALAAECgMIAwAAAA==.',Gh='Gharph:BAAALAADCgYIBgAAAA==.Ghazkull:BAAALAADCgQIBAAAAA==.Ghoum:BAAALAAECgMIBAAAAA==.',Gl='Glis:BAAALAAECgIIAgAAAA==.Glís:BAAALAADCggICQABLAAECgIIAgABAAAAAA==.',Gn='Gnoimev:BAABLAAECoEXAAIUAAcIkxsdFgBSAgAUAAcIkxsdFgBSAgAAAA==.',Gr='Grimtoll:BAAALAADCgUIBQABLAAECgYICQABAAAAAA==.Grómph:BAAALAAECggIAwAAAA==.',Gu='Gudgeon:BAAALAAECgUIBwAAAA==.Gundefar:BAAALAAECgMIBQAAAA==.Guttermouth:BAAALAAECgYIDgAAAA==.',Ha='Haarg:BAAALAAECgcIEgAAAA==.Haeggis:BAAALAADCgcIEQAAAA==.Hairysocks:BAAALAADCgYIBQAAAA==.Hammjo:BAAALAAECgEIAQAAAA==.Haramis:BAAALAAECgUICQAAAA==.',He='Herflick:BAAALAAECgYIDgAAAA==.',Hi='Himura:BAAALAAECgMIBgAAAA==.',Ho='Holiemolly:BAAALAAECgMIAwAAAA==.Holyduck:BAAALAAECgYIBgAAAA==.',Hu='Hulkshrek:BAAALAADCgYICgAAAA==.Huntdeeznuts:BAAALAAECgcICAAAAA==.Huntolf:BAAALAAECgQIBAAAAA==.',Hy='Hytos:BAAALAAECgYIEgAAAA==.',['Há']='Hármony:BAAALAAECgYIDQAAAA==.',['Hê']='Hêns:BAAALAAECgMIBwAAAA==.',Ik='Ikati:BAAALAADCgcIBwAAAA==.',Il='Illidariana:BAAALAAECgYICQAAAA==.Ilysa:BAAALAADCggICAAAAA==.',Im='Imdademon:BAAALAAECgUIBQABLAAFFAYIDQAZALkiAA==.',In='Intranet:BAEBLAAECoEqAAIcAAgIhRJzGgAGAgAcAAgIhRJzGgAGAgAAAA==.',Ir='Ironpalms:BAAALAADCgMIAwAAAA==.',Is='Ishae:BAAALAADCgIIAgABLAADCgcIBwABAAAAAA==.Ismenia:BAAALAAECgIIBQAAAA==.',Iu='Iustinus:BAABLAAECoEdAAIdAAgIdySvAQBXAwAdAAgIdySvAQBXAwAAAA==.',Iz='Izabel:BAAALAADCgIIAgAAAA==.',Ja='Jaegra:BAACLAAFFIEIAAIHAAMIMSGTBAAjAQAHAAMIMSGTBAAjAQAsAAQKgRgAAgcACAilJbQEAFMDAAcACAilJbQEAFMDAAAA.Jaemes:BAAALAADCggICQAAAA==.Jahya:BAAALAADCggIDwAAAA==.Jamaine:BAAALAAECgMIAwAAAA==.Jarnex:BAAALAADCgYIBgAAAA==.Jarnexa:BAABLAAECoEYAAIeAAgI6xzdAQDDAgAeAAgI6xzdAQDDAgAAAA==.Jayzin:BAAALAADCgQIBQABLAAECgYIBgABAAAAAA==.',Je='Jeffknight:BAAALAAECgYIDQAAAA==.Jeorn:BAAALAAECgUICQAAAA==.',Jo='Johnro:BAABLAAECoEYAAIKAAgIIiQRBQBTAwAKAAgIIiQRBQBTAwAAAA==.',Ju='Juicewrld:BAAALAADCgIIAgAAAA==.',['Jö']='Jörmungadrow:BAAALAAECgYIDQAAAA==.',Ka='Kaelios:BAAALAAECgcIEAAAAA==.Kaerhus:BAAALAAECgQIAgAAAA==.Kalida:BAAALAAECgYIDgAAAA==.Kalihi:BAAALAAECgUIBwAAAA==.Kalums:BAAALAAFFAMIAwAAAA==.Kargosh:BAAALAAECgYIEAAAAA==.Katnisz:BAAALAADCgcIBwAAAA==.',Kb='Kbillhunter:BAAALAAECgcIDQAAAA==.',Ke='Kelgorn:BAAALAAECgMIAwAAAA==.Kelrina:BAAALAADCggICAAAAA==.',Kh='Khnemu:BAAALAAECgQIBAABLAAECggIHgALAOsiAA==.',Ki='Kipaa:BAACLAAFFIELAAIHAAQI8hFQAwBQAQAHAAQI8hFQAwBQAQAsAAQKgRgAAwIACAiPJMYBADMDAAIACAiDI8YBADMDAAcACAjLIVUXAKQCAAAA.Kippaa:BAAALAAECggICwABLAAFFAQICwAHAPIRAA==.Kirrá:BAAALAAECgIIAgAAAA==.',Kl='Klock:BAAALAAECgUICQAAAA==.',Kn='Kniightelff:BAAALAADCgQIBAABLAAECggIEAABAAAAAA==.',Ko='Kormash:BAACLAAFFIELAAIfAAQIpBsAAQBsAQAfAAQIpBsAAQBsAQAsAAQKgSAAAh8ACAhMJIQBAE0DAB8ACAhMJIQBAE0DAAAA.',Ku='Kumihoz:BAABLAAECoEYAAIHAAgI4xRvJwA0AgAHAAgI4xRvJwA0AgAAAA==.Kurikael:BAAALAADCgcICQAAAA==.',Kx='Kxeviv:BAAALAAECgMIAwAAAA==.',['Ká']='Kárra:BAAALAAECgQIBAAAAA==.',La='Laeneus:BAAALAAECgEIAQAAAA==.Laiva:BAAALAAECgYIBgAAAA==.Lauriem:BAABLAAECoEWAAILAAgIpgxnRABqAQALAAgIpgxnRABqAQAAAA==.Lazypeon:BAAALAAECgIIAgAAAA==.Lazyshadow:BAAALAADCgEIAQAAAA==.',Le='Leifbilly:BAAALAADCggIDwAAAA==.Leosoul:BAAALAAECggIEwAAAA==.',Li='Lilscarlet:BAAALAAECgYIDgAAAA==.Limelock:BAAALAAECgYICgABLAAECgcIGAATAI0eAA==.Linton:BAAALAADCggICAAAAA==.Lirra:BAAALAAECgYIDQAAAA==.Lisondra:BAAALAAECgMIBAAAAA==.Littlekitty:BAAALAAECggICwAAAA==.',Ll='Lledari:BAAALAAECggIEAAAAA==.',Lo='Lockus:BAAALAADCggICAAAAA==.Lourioz:BAACLAAFFIEHAAIYAAMIKhHvCgD1AAAYAAMIKhHvCgD1AAAsAAQKgRcAAxgACAgCIIAXAKQCABgACAgCIIAXAKQCABkAAwjTFmELAKEAAAAA.Lowmac:BAAALAAECggIAQAAAA==.',Lu='Lucidhex:BAABLAAECoEdAAIXAAgI5CF4CAAQAwAXAAgI5CF4CAAQAwAAAA==.Luckycat:BAAALAADCgcIBwABLAAECgcIFQALAOMRAA==.Luckywolf:BAABLAAECoEVAAILAAcI4xGcOQCWAQALAAcI4xGcOQCWAQAAAA==.Lucyan:BAAALAADCgcICgAAAA==.Lucyheartfil:BAAALAADCgUIBgAAAA==.Luderso:BAAALAADCggIBwAAAA==.Lukrethia:BAAALAADCgcIEAAAAA==.Lumike:BAAALAADCggIFgAAAA==.Luthiee:BAAALAADCgcIEQAAAA==.',['Lî']='Lîlîth:BAAALAADCggICAABLAAECggIFQALABwPAA==.',['Lù']='Lùcky:BAAALAAECgYIDgAAAA==.',['Lü']='Lücky:BAAALAADCggICAABLAAECgcIFQALAOMRAA==.Lündin:BAAALAAECgcIEQAAAA==.',Ma='Mackan:BAABLAAECoEYAAMgAAgILRNJCwDMAQAgAAgIYBJJCwDMAQAhAAcI5AhYKwBnAQAAAA==.Magicfizz:BAAALAADCgcICgAAAA==.Magicsnar:BAAALAAECgcIDgAAAA==.Malandrino:BAAALAADCgIIBAAAAA==.Malfdrago:BAABLAAECoEVAAIiAAcIcRh4FwDyAQAiAAcIcRh4FwDyAQAAAA==.Malfpalka:BAAALAADCggIDQABLAAECgcIFQAiAHEYAA==.Malhern:BAAALAADCggICAAAAA==.Mangojuulpod:BAAALAADCggICgABLAAECgcICwABAAAAAA==.Marks:BAACLAAFFIEIAAIGAAQIJRSqAgBIAQAGAAQIJRSqAgBIAQAsAAQKgR4AAgYACAjeIHsHAPcCAAYACAjeIHsHAPcCAAAA.Markza:BAAALAAECgQIBQAAAA==.Mateki:BAAALAAECgYIDgAAAA==.Maximuss:BAAALAADCgYIBgAAAA==.Maymar:BAAALAAECggIDgAAAA==.',Mc='Mcplant:BAACLAAFFIEIAAIcAAMIkBytAgAgAQAcAAMIkBytAgAgAQAsAAQKgRgAAhwACAi6H3AKAMwCABwACAi6H3AKAMwCAAAA.',Me='Meh:BAAALAAECgEIAQAAAA==.Meldrew:BAAALAADCgcIEQAAAA==.Melisara:BAAALAADCgcIBwAAAA==.Metalkeg:BAABLAAECoEUAAIjAAgIQA0xGAAxAQAjAAgIQA0xGAAxAQAAAA==.',Mi='Milityr:BAAALAADCgcIDQABLAADCggICwABAAAAAA==.Milutin:BAAALAADCgUIBQAAAA==.Mirnà:BAAALAADCggIDwAAAA==.Misdemeanour:BAAALAAECgEIAQAAAA==.Misery:BAAALAADCggICAAAAA==.Mistydraconi:BAAALAAECgQIBQAAAA==.',Mn='Mnck:BAABLAAECoEWAAMSAAgIJyVjBABKAwASAAgIzyRjBABKAwAkAAUItyObEwDGAQAAAA==.',Mo='Moffegrevên:BAAALAAECgcIBwAAAA==.Mokha:BAAALAAECgMIAwAAAA==.Moneyfriend:BAAALAAECgYIDgAAAA==.Monkbam:BAAALAAECggIDQAAAA==.Moominette:BAAALAADCgcIEQAAAA==.Mooms:BAAALAAECgUICQAAAA==.Moosey:BAAALAAECgcIEwAAAA==.',Mu='Mumu:BAAALAADCggICAABLAAECgcIFgAHAAwhAA==.',My='Myfic:BAAALAAECggIDAAAAA==.Myficc:BAAALAAECggIEQAAAA==.Mysea:BAAALAADCgcIBwAAAA==.Mystiblood:BAAALAADCgcIBwAAAA==.',['Má']='Mánny:BAAALAADCgEIAQABLAAECgYIDQABAAAAAA==.',['Mé']='Méleys:BAAALAADCgcICgAAAA==.',['Mó']='Mórgana:BAAALAAECgQIBAAAAA==.',Na='Naffes:BAAALAADCgYIBgAAAA==.Nahida:BAAALAAECgYICgAAAA==.Naturehealer:BAABLAAECoEdAAIUAAgIZRiqFQBXAgAUAAgIZRiqFQBXAgAAAA==.',Ne='Neoxlock:BAAALAADCggICAABLAAECgcIFAAXANAXAA==.Neteroo:BAAALAADCgcIFAAAAA==.Newdruid:BAAALAAECgIIAgAAAA==.',Ni='Niceerjeg:BAAALAAECgYIDgAAAA==.Nightkung:BAAALAAECgQIBAAAAA==.',No='Noevryn:BAACLAAFFIEJAAIYAAQIVA4aBQBEAQAYAAQIVA4aBQBEAQAsAAQKgSAAAhgACAhoI/cFADgDABgACAhoI/cFADgDAAAA.Noks:BAAALAADCgcIBwAAAA==.Nomadius:BAABLAAECoEXAAIaAAcISxytDwAbAgAaAAcISxytDwAbAgAAAA==.Nonagon:BAAALAAECgUICAAAAA==.Nopes:BAAALAADCggIEAABLAAECggIFgARAK8dAA==.Noxium:BAAALAAECgcIDQAAAA==.',Ny='Nyakay:BAAALAAECgEIAgAAAA==.Nyand:BAAALAAECgUICQAAAA==.Nyxee:BAABLAAECoEWAAINAAcI6g54MQCTAQANAAcI6g54MQCTAQAAAA==.',['Nó']='Nóvá:BAAALAAECgQIBQAAAA==.',Oa='Oak:BAAALAADCgcIDQAAAA==.',Ob='Obliteration:BAAALAAECgIIAgAAAA==.',Od='Odanobunaga:BAAALAAECgUIDAABLAAECggIGAAHAOMUAA==.',Ok='Okej:BAAALAAECgYIDQAAAA==.',Ol='Olfinator:BAAALAAECggIDwAAAA==.',On='Onkelpung:BAAALAAECgYIDwAAAA==.',Op='Oppressor:BAAALAADCgYIBwAAAA==.',Or='Orgrimash:BAACLAAFFIEGAAIJAAII3hz5CQC5AAAJAAII3hz5CQC5AAAsAAQKgRcAAgkACAgfIlcKAPwCAAkACAgfIlcKAPwCAAAA.Orthik:BAABLAAECoEgAAMHAAgIsh8RFQC3AgAHAAgIsh8RFQC3AgACAAEIIxNhOQA3AAAAAA==.',Ou='Ouíja:BAAALAAECgEIAQAAAA==.',Ov='Overhaul:BAAALAAECgMIAwAAAA==.',Ox='Oxed:BAAALAAECgcIBwAAAA==.',Pa='Paatz:BAAALAADCgcICwAAAA==.Pajoodk:BAABLAAECoEcAAIkAAgI3h/uAgAJAwAkAAgI3h/uAgAJAwAAAA==.Pamike:BAAALAADCgcIEgAAAA==.Panduin:BAACLAAFFIEIAAIfAAMI9SCTAQAjAQAfAAMI9SCTAQAjAQAsAAQKgRgAAh8ACAhqJB8CADYDAB8ACAhqJB8CADYDAAAA.Pascal:BAABLAAECoEdAAMJAAgI2SSBBABEAwAJAAgIDySBBABEAwAlAAQI5iEyCwCZAQAAAA==.Pats:BAAALAAECgYIDQAAAA==.',Pe='Pebblestream:BAABLAAECoEbAAILAAgIRBsYFwBJAgALAAgIRBsYFwBJAgAAAA==.',Ph='Philip:BAAALAAECgYICQAAAA==.Phlick:BAAALAAECgYIBwAAAA==.Phong:BAABLAAECoEUAAImAAcIhhBxFgB4AQAmAAcIhhBxFgB4AQAAAA==.Phoopi:BAAALAAECgIIAwAAAA==.Phosphorus:BAAALAADCgUIBQAAAA==.',Pi='Pietroassa:BAAALAADCggICAABLAAECgcIBwABAAAAAA==.Pinap:BAAALAAECgIIAgAAAA==.',Pn='Pnemmz:BAAALAADCggIFQAAAA==.',Po='Potato:BAABLAAECoEbAAIUAAgIrxMAGgAqAgAUAAgIrxMAGgAqAgAAAA==.Poxiok:BAAALAADCggICAAAAA==.',Pr='Prosperine:BAABLAAECoEZAAMMAAcI7SRYBgCZAgAMAAcI7SRYBgCZAgAKAAYIrxUMXAB7AQAAAA==.Prälle:BAAALAADCgcIEQAAAA==.',Pt='Ptørg:BAAALAADCgIIAgABLAAECgcIFgAYAHgbAA==.',Pw='Pwent:BAAALAAECgIIAgAAAA==.',Qu='Quampir:BAAALAAECgcIDwAAAA==.Quickben:BAAALAAECgYIDgAAAA==.Quis:BAAALAADCgIIAgAAAA==.',Qw='Qwe:BAAALAADCggICAABLAAECggIFgAGAPsfAA==.',Ra='Radasex:BAABLAAECoEUAAMLAAgI4A8sPwB+AQALAAcIsBEsPwB+AQAnAAEIOwK4HAAMAAAAAA==.Raichi:BAABLAAECoEVAAILAAgIHA/pQAB3AQALAAgIHA/pQAB3AQAAAA==.Rally:BAAALAAECgQIBAAAAA==.Rashie:BAABLAAECoEUAAMPAAgIfxiZCgBXAgAPAAgIfxiZCgBXAgAQAAEI7BzLgABRAAAAAA==.Rashiee:BAAALAAECgIIAgABLAAECggIFAAPAH8YAA==.Ravenheart:BAAALAAECgcIDwAAAA==.Raxmark:BAAALAADCgYIBgAAAA==.Raxto:BAAALAADCgcIBwAAAA==.Raxzo:BAAALAADCgEIAQAAAA==.',Re='Reeven:BAAALAADCggICAABLAAECgYICQABAAAAAA==.Rejesh:BAAALAAECggICAAAAA==.Rekar:BAAALAADCgQIBAAAAA==.Rennyo:BAAALAAECgQICQAAAA==.Rezesurvival:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.Rezoi:BAAALAAECgYIBgAAAA==.',Ri='Rimz:BAAALAAECgcIEAAAAA==.Rishåår:BAAALAADCgQIBAAAAA==.Rivarì:BAAALAADCgUIBwAAAA==.',Ro='Robinstr:BAAALAAECgUICQAAAA==.Rofusmedlem:BAAALAAECgIIAgAAAA==.',Ru='Rudyp:BAAALAAECggIDAAAAA==.Rugged:BAAALAAECgQIBgAAAA==.',['Rì']='Rìshaar:BAAALAADCgEIAQAAAA==.',Sa='Salendra:BAAALAADCgcIDwAAAA==.Saleos:BAAALAADCggICAAAAA==.Salinda:BAAALAADCgMIAwAAAA==.Saliqua:BAACLAAFFIEIAAImAAMIMhqmAgATAQAmAAMIMhqmAgATAQAsAAQKgRgAAiYACAjgHuoGAJYCACYACAjgHuoGAJYCAAAA.Sammyann:BAAALAAECgMIAgAAAA==.Sanatina:BAAALAAECggIDwAAAA==.Saramé:BAAALAAECgYIDAAAAA==.',Sc='Schopie:BAAALAAECgcIEAAAAA==.',Se='Seed:BAAALAADCggICAAAAA==.Selket:BAABLAAECoEYAAINAAgIsSJ7BQALAwANAAgIsSJ7BQALAwAAAA==.Senapsburk:BAACLAAFFIEJAAIIAAQIuxI7AQBTAQAIAAQIuxI7AQBTAQAsAAQKgSAAAggACAj+I/kBAE4DAAgACAj+I/kBAE4DAAAA.',Sh='Shaddy:BAAALAADCggICAAAAA==.Shadoll:BAAALAADCgMIBgAAAA==.Shadowpizza:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.Shalena:BAAALAAECgYICAABLAAECggIHAAEABAiAA==.Shamatíc:BAAALAAECgYICQAAAA==.Shamesom:BAAALAADCgcIBwAAAA==.Shedu:BAEBLAAFFIEKAAIXAAQIFRzGAgB1AQAXAAQIFRzGAgB1AQAAAA==.Sheilds:BAAALAADCgcIBwAAAA==.Shibata:BAAALAAECgYICgABLAAFFAMIBQAdAF8OAA==.Shinnok:BAAALAAECgYIDAAAAA==.Showlie:BAABLAAECoEXAAIEAAcIURlSCgAjAgAEAAcIURlSCgAjAgAAAA==.Shyanaa:BAAALAAECgYIEAAAAA==.',Si='Sigismund:BAABLAAECoEWAAMHAAcIDCGBGACaAgAHAAcIYSCBGACaAgACAAMIwSD0HgACAQAAAA==.Silverflow:BAAALAAECgQIAgAAAA==.',Sk='Skaraa:BAAALAADCggICAABLAAECgcIFgANAOoOAA==.Skillsnapper:BAABLAAECoEZAAISAAgI6R0wFwClAgASAAgI6R0wFwClAgAAAA==.Skourge:BAAALAAECgEIAgAAAA==.Skywalkerr:BAAALAADCgcIBwAAAA==.',Sl='Slimpickings:BAAALAADCgcIBwAAAA==.Slynm:BAAALAAECgYIDQAAAA==.',Sm='Smashin:BAAALAADCggICQAAAA==.Smølfine:BAAALAADCgcIDAAAAA==.',Sn='Sneakyboi:BAAALAAECgIIAgAAAA==.Sneakybubble:BAAALAAECgYIBgAAAA==.Snowlily:BAACLAAFFIEIAAINAAMI2CI0AwA1AQANAAMI2CI0AwA1AQAsAAQKgRgAAg0ACAiAIZYHAOsCAA0ACAiAIZYHAOsCAAAA.',So='Solarus:BAABLAAECoEXAAIEAAgIKhqYBgCGAgAEAAgIKhqYBgCGAgAAAA==.',Sp='Speedfire:BAAALAAECgIIBAAAAA==.Spiritbloom:BAAALAAECgcIEAAAAA==.Spititout:BAAALAAECgIIAgAAAA==.Spookee:BAAALAADCggIEgAAAA==.Spooks:BAABLAAECoEWAAMRAAgIrx02DACCAgARAAgIrx02DACCAgAcAAEI1AWRZgAnAAAAAA==.',St='Stanmoore:BAAALAADCggIDwAAAA==.Starfall:BAAALAAECgMIAwABLAAECggIKAANABQkAA==.Starfigther:BAAALAAECgIIAgABLAAECgcICwABAAAAAA==.Staxie:BAAALAAFFAIIAgAAAA==.',Su='Suffragette:BAAALAAECgUICQAAAA==.Sushidk:BAAALAADCgYICwAAAA==.',Sv='Svartskallig:BAAALAADCggIDwAAAA==.Svoll:BAABLAAECoEWAAIGAAgI+x95CQDbAgAGAAgI+x95CQDbAgAAAA==.',Sw='Swiftshock:BAAALAAECgUICQAAAA==.',Sz='Szamike:BAAALAADCgcIDAAAAA==.Szuriel:BAAALAADCgUIBQABLAADCgYIBgABAAAAAA==.',Ta='Taara:BAAALAAECgQIBAAAAA==.Talais:BAAALAADCgcIBwAAAA==.Talonrickman:BAAALAADCgYICAAAAA==.Tarja:BAAALAAECgYIBgABLAAFFAQIBgAPAGYXAA==.Tayana:BAAALAAECgQICQAAAA==.Tayenon:BAABLAAECoEXAAIKAAcIwx9PGwCJAgAKAAcIwx9PGwCJAgAAAA==.',Te='Teishóu:BAAALAADCgcIBwAAAA==.',Th='Tharium:BAAALAADCgcIFwAAAA==.Thirouc:BAABLAAECoEYAAIRAAgI4SPoAQA3AwARAAgI4SPoAQA3AwAAAA==.Thrashér:BAAALAADCgMIAwAAAA==.',To='Toe:BAAALAAECgYIDQAAAA==.Tofdiz:BAAALAADCggICAABLAAFFAQICQAcAPcYAA==.Tofdoom:BAAALAADCggIDgABLAAFFAQICQAcAPcYAA==.Tofdy:BAACLAAFFIEJAAIcAAQI9xiCAQB1AQAcAAQI9xiCAQB1AQAsAAQKgSAAAhwACAiMJG0DAEkDABwACAiMJG0DAEkDAAAA.Toph:BAAALAAECgYIDgAAAA==.Totemiss:BAAALAAECgEIAQAAAA==.Touya:BAAALAADCgcICQAAAA==.',Tr='Trikistab:BAABLAAECoESAAIhAAgIbiHDBwDWAgAhAAgIbiHDBwDWAgAAAA==.Trixed:BAAALAAECgUIBQAAAA==.Trojanhorse:BAAALAADCggICAAAAA==.Trueomega:BAAALAAECggIBwAAAA==.Tràgédy:BAABLAAECoEXAAINAAcIGB6KGAA4AgANAAcIGB6KGAA4AgAAAA==.Træto:BAABLAAECoEXAAISAAcIvh8yJQBOAgASAAcIvh8yJQBOAgAAAA==.',Tu='Tukka:BAAALAAECgYIDAAAAA==.Tulegit:BAABLAAECoEYAAMUAAgIcx7gCQDnAgAUAAgIcx7gCQDnAgANAAcIRxdoIgDuAQAAAA==.',Tw='Twixype:BAAALAADCgcIFgAAAA==.',Ty='Tykling:BAAALAAECgMIAwAAAA==.',Un='Undeadovy:BAAALAADCggIDgAAAA==.',Ut='Utami:BAACLAAFFIEFAAIdAAMIXw66AQDmAAAdAAMIXw66AQDmAAAsAAQKgRgAAh0ACAggItoEAPgCAB0ACAggItoEAPgCAAAA.',Va='Valchi:BAAALAAECgYIBgABLAAECgcIBwABAAAAAA==.Valdura:BAACLAAFFIEIAAITAAMInheXAwAHAQATAAMInheXAwAHAQAsAAQKgRgAAhMACAjzFcIPABcCABMACAjzFcIPABcCAAAA.Valkyrian:BAAALAADCgcIBAABLAAECgcIGAAiAKggAA==.Valrenia:BAAALAAECgcIBwAAAA==.Varnak:BAAALAADCgcIEQAAAA==.Varðlokkur:BAAALAAECgcIBwAAAA==.Vashastrasz:BAAALAAECgcICAAAAA==.',Ve='Vecraz:BAABLAAECoEYAAQPAAgIjhbuFwDSAQAPAAYIMBfuFwDSAQAQAAMIgxKIZQDGAAAbAAEIjg+gLQBLAAAAAA==.Vegapunk:BAAALAADCggIDwAAAA==.Verrain:BAAALAAECgMIBQAAAA==.Vesria:BAAALAAECgQIBwAAAA==.Vetnippel:BAAALAADCgIIAwAAAA==.',Vh='Vhayle:BAAALAAECgYIDQAAAA==.',Vi='Viletta:BAAALAAECgYICwAAAA==.Vindicaith:BAABLAAECoEVAAIKAAgIIRgjMQAPAgAKAAgIIRgjMQAPAgAAAA==.Vindra:BAAALAAECgYICgAAAA==.Vinsa:BAAALAAECggIEwAAAA==.Visemya:BAAALAAECgYICwAAAA==.',Vo='Voodoonker:BAAALAADCggICAAAAA==.Vorpalis:BAACLAAFFIEGAAISAAMIDRAbBwADAQASAAMIDRAbBwADAQAsAAQKgRgAAhIACAjoHGIeAHUCABIACAjoHGIeAHUCAAAA.Vorzan:BAAALAADCgcIDQAAAA==.',Vy='Vyg:BAAALAAECgYIBgAAAA==.',['Vì']='Vìvii:BAAALAAECgMIBwAAAA==.',['Ví']='Vísíonn:BAACLAAFFIEHAAIFAAMIdhsUAwAYAQAFAAMIdhsUAwAYAQAsAAQKgRUAAgUACAhQHpURAKUCAAUACAhQHpURAKUCAAAA.',Wa='Waldove:BAAALAADCgUIBQAAAA==.Wallhunter:BAAALAADCggIFgAAAA==.',We='Welfir:BAACLAAFFIEGAAIJAAMIAhNJBgAKAQAJAAMIAhNJBgAKAQAsAAQKgRcAAgkACAi8GzUWAG8CAAkACAi8GzUWAG8CAAAA.',Wo='Wook:BAAALAADCgIIAgAAAA==.',Wr='Wrosh:BAAALAADCggICAABLAAECggIHgAFABckAA==.Wroshe:BAABLAAECoEeAAIFAAgIFyTlAwBHAwAFAAgIFyTlAwBHAwAAAA==.',Xa='Xaqla:BAACLAAFFIEGAAMPAAQIZhcmBAC5AAAPAAIIBRwmBAC5AAAQAAIIxxJSDQC5AAAsAAQKgRoABBAACAhjImsLAOwCABAACAjMIGsLAOwCAA8ABgj6I08LAE0CABsAAwiTHPYUABcBAAAA.',Xy='Xyden:BAACLAAFFIEIAAIUAAMIliAiBAAYAQAUAAMIliAiBAAYAQAsAAQKgRgAAxQACAj4G8QRAIUCABQACAj4G8QRAIUCAA0ACAgzEWQoAMcBAAAA.Xyraxia:BAAALAADCggIDwAAAA==.',Ya='Yabbz:BAAALAAECgcIEAAAAA==.',Yd='Ydelos:BAAALAAECgUIBwAAAA==.',Yu='Yuehai:BAAALAADCggICAABLAAECggIIAAIAOAjAA==.Yuki:BAAALAADCgYIBgAAAA==.',['Yó']='Yódagill:BAAALAADCgcIBwAAAA==.',['Yú']='Yúnyun:BAABLAAECoEXAAIFAAgIgB8eCwDrAgAFAAgIgB8eCwDrAgAAAA==.',Za='Zaepheo:BAAALAAECgYIDQAAAA==.Zagdin:BAAALAAECgYICwAAAA==.Zalfac:BAAALAADCggICAAAAA==.Zandasaurus:BAABLAAECoEVAAIDAAgIoyOVAQDeAgADAAgIoyOVAQDeAgAAAA==.Zanghi:BAACLAAFFIEHAAIXAAMI3RGdBgD5AAAXAAMI3RGdBgD5AAAsAAQKgRgAAxcACAhJHusPAK8CABcACAhJHusPAK8CACcAAQjQA9waADYAAAAA.Zappityzap:BAAALAADCggICQAAAA==.Zarine:BAAALAADCgQIAQAAAA==.',Ze='Zem:BAAALAAECgcIEgAAAA==.Zephria:BAACLAAFFIEKAAMiAAQIuhxCAgB+AQAiAAQIuhxCAgB+AQAWAAEI8hcFAwBEAAAsAAQKgSAAAyIACAjrInoDADQDACIACAjrInoDADQDABYABQgbFR0HACcBAAAA.Zeryni:BAAALAADCgcIBwAAAA==.Zeyk:BAAALAADCggICAAAAA==.Zeylira:BAAALAAECgYIEQAAAA==.',Zi='Ziibow:BAABLAAECoEbAAIFAAgIJCSlAwBLAwAFAAgIJCSlAwBLAwAAAA==.Zinsa:BAAALAADCggIFAAAAA==.',Zn='Zni:BAAALAAECgMIAwAAAA==.',Zo='Zondalary:BAAALAAECggIEAAAAA==.',Zy='Zylan:BAAALAADCggICAAAAA==.Zymira:BAABLAAECoEYAAMiAAcIqCBwDQCAAgAiAAcIqCBwDQCAAgAVAAMIgBgAGQDaAAAAAA==.Zyrimx:BAAALAADCgcIEQAAAA==.',['Zé']='Zéro:BAABLAAECoEXAAIkAAcIzSC0BQCwAgAkAAcIzSC0BQCwAgAAAA==.',['Án']='Ángeleyes:BAAALAADCggIEAAAAA==.',['Áp']='Ápachi:BAAALAADCgcIBwAAAA==.',['Él']='Éllie:BAAALAAECgMIAwAAAA==.',['Êr']='Êrmagad:BAABLAAECoEXAAMFAAcI+SBhEgCdAgAFAAcI+SBhEgCdAgAGAAIIwhaYXQB6AAAAAA==.',['În']='Îndîch:BAAALAADCgcIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end