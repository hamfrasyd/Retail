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
 local lookup = {'Priest-Holy','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Hunter-BeastMastery','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','Shaman-Elemental','Druid-Restoration','DeathKnight-Frost','Paladin-Holy','Mage-Arcane','DemonHunter-Havoc','Unknown-Unknown','DeathKnight-Blood','Druid-Balance','Warlock-Affliction','Shaman-Restoration','Druid-Guardian','Rogue-Subtlety','Paladin-Retribution','Warlock-Destruction','Warlock-Demonology','Druid-Feral','Warrior-Protection','Mage-Frost',}; local provider = {region='EU',realm="Nera'thor",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abbrechen:BAAALAAECgQIBAAAAA==.',Ae='Aelyn:BAABLAAECoEcAAIBAAgIMASFXgA9AQABAAgIMASFXgA9AQABLAAFFAIIBQACAAATAA==.',Al='Alere:BAAALAAECgcIDQAAAA==.Alfrad:BAAALAADCgYIBgAAAA==.Alraik:BAAALAADCggIFQAAAA==.Alukat:BAABLAAECoEUAAIDAAYI1hODEwCHAQADAAYI1hODEwCHAQAAAA==.',Am='Amarea:BAAALAAECggICAAAAA==.',An='Annette:BAAALAADCgMIAwAAAA==.Annibanani:BAAALAAECgUIBQAAAA==.Antenne:BAAALAAECgYIEgAAAA==.Anyla:BAACLAAFFIEGAAIBAAIIuxZzGgCnAAABAAIIuxZzGgCnAAAsAAQKgSUAAgEACAg6HBUZAIsCAAEACAg6HBUZAIsCAAAA.',Ap='Apøkalypse:BAAALAAECgYIBgAAAA==.',Ar='Arrios:BAAALAAECgEIAQAAAA==.Aríena:BAAALAAECgIIBAAAAA==.',As='Asklepion:BAAALAAFFAMIAwAAAA==.Astrid:BAAALAAECggIDgAAAA==.Astá:BAAALAADCgYIBwAAAA==.Asuki:BAAALAAECgUIBQAAAA==.',Ba='Babaiga:BAAALAADCggIGAAAAA==.Bantu:BAABLAAECoEWAAIEAAgIZxeBMgA7AgAEAAgIZxeBMgA7AgAAAA==.',Be='Behindokles:BAAALAAECgYICAAAAA==.Beláh:BAABLAAECoEVAAIFAAcIMRpvUQDsAQAFAAcIMRpvUQDsAQAAAA==.Benjie:BAAALAAECgYIEQAAAA==.Benshi:BAAALAAECgIIAgAAAA==.Beschwöre:BAAALAADCgYIBgAAAA==.',Bl='Blackovero:BAABLAAECoEaAAIFAAcI1QctqAAvAQAFAAcI1QctqAAvAQAAAA==.',Br='Brewmi:BAABLAAECoEdAAQGAAgI/xffOAAaAQAGAAgI/xffOAAaAQAHAAYIvwyfKgAWAQAIAAUI6QbKMgCzAAAAAA==.',Ca='Caliim:BAAALAAECgYIBgAAAA==.Catwalk:BAAALAADCggIFQAAAA==.',Ce='Cecilia:BAAALAAECgYIDQAAAA==.',Ch='Chox:BAAALAAECgUIBQAAAA==.',Co='Coljin:BAAALAAECgYIBwAAAA==.',Cr='Crypticsham:BAABLAAECoEcAAIJAAgIFBijKwA8AgAJAAgIFBijKwA8AgAAAA==.',Cu='Cuja:BAABLAAECoEXAAIKAAYIiQ3FZAAmAQAKAAYIiQ3FZAAmAQAAAA==.',Da='Dampfwalze:BAABLAAECoEpAAILAAgIVhtpMACKAgALAAgIVhtpMACKAgAAAA==.Darethas:BAAALAAECgYIEgAAAA==.',De='Destt:BAAALAAECgYIBwAAAA==.',Di='Diekronenox:BAAALAADCggICAAAAA==.Direnia:BAABLAAECoEWAAIMAAcIYB+NDwB2AgAMAAcIYB+NDwB2AgAAAA==.',Dr='Drachenfeuer:BAAALAAECgEIAQAAAA==.Dracomorph:BAAALAAECgYICQAAAA==.Drixxi:BAAALAADCgEIAQAAAA==.',Du='Durchbrechen:BAAALAAECgYIBgAAAA==.',['Dê']='Dêâthwêâpôn:BAAALAAECgYIDwAAAA==.',['Dó']='Dórin:BAAALAAECgYIEgAAAA==.',El='Elaidien:BAAALAAECgYIDwAAAA==.Elarathien:BAAALAAECgIIAgAAAA==.Eldor:BAAALAADCggICAAAAA==.Elli:BAAALAAECgMIBQAAAA==.',Er='Erikohu:BAABLAAECoEeAAMCAAcIliHLIwA2AgACAAcIkxzLIwA2AgAFAAcIxB1pQAAfAgAAAA==.Erischami:BAAALAAECgIIAgAAAA==.',Ex='Excidium:BAAALAADCgcIBwAAAA==.',['Eî']='Eîswürfêl:BAAALAADCgcICwAAAA==.',Fl='Fluffi:BAAALAADCgEIAQAAAA==.',Gh='Ghart:BAAALAAECgYIBwAAAA==.',Gr='Greenarrow:BAABLAAECoEXAAICAAcIIxcxMgDfAQACAAcIIxcxMgDfAQAAAA==.Gronkash:BAABLAAECoEWAAICAAgIySHuCwD5AgACAAgIySHuCwD5AgAAAA==.',Gu='Gundrabur:BAAALAAECgYIBgABLAAFFAYIEgAJAJ4WAA==.',Gw='Gwenselah:BAAALAAECgYIDgAAAA==.',Ha='Hasu:BAABLAAECoEiAAIDAAgI2h33BAC/AgADAAgI2h33BAC/AgAAAA==.',He='Heavyweigth:BAABLAAECoEeAAINAAYIdhPacQCSAQANAAYIdhPacQCSAQAAAA==.Hecarîm:BAAALAAECgUIBQAAAA==.Heiliheili:BAAALAADCggICAAAAA==.Helfgar:BAAALAAECgYIEAAAAA==.Hellfirex:BAAALAADCggICAAAAA==.Hellokritty:BAAALAADCgEIAQAAAA==.Hexenmensch:BAAALAAECgYIDgAAAA==.',Hj='Hjörthrimul:BAAALAAECgUIAQAAAA==.',Ho='Holyców:BAAALAAECgMIAwAAAA==.Hoopi:BAAALAAECgYIEgAAAA==.Houdiny:BAAALAADCgMIAwAAAA==.',['Hô']='Hôlyshitt:BAAALAADCgEIAQAAAA==.',Ig='Igna:BAABLAAECoEUAAIOAAcIfQiUnwBaAQAOAAcIfQiUnwBaAQAAAA==.',Il='Ilari:BAAALAADCggIDwABLAAECgYIBwAPAAAAAA==.Iluvgrisslyz:BAAALAADCgcIBwAAAA==.',In='Insomnia:BAAALAAECggICAAAAA==.Intervention:BAAALAAECgYIDAAAAA==.',Ja='Javano:BAAALAADCgEIAQAAAA==.',Jo='Johnnyblink:BAAALAAECgYIBgAAAA==.',Ju='Junkzresz:BAAALAAECgMIAwAAAA==.',['Jé']='Jénara:BAAALAADCgMIBAAAAA==.',Ka='Kahrandor:BAABLAAECoEWAAIQAAcInhfjEwDbAQAQAAcInhfjEwDbAQAAAA==.Kaldêa:BAAALAAECgIIAgAAAA==.Karakil:BAAALAADCggIDgAAAA==.Katrol:BAAALAAECgEIAQAAAA==.',Ke='Kerodoro:BAABLAAECoEbAAIRAAcI3xCUOwCZAQARAAcI3xCUOwCZAQAAAA==.Kessina:BAAALAADCggIDQAAAA==.Kessinâ:BAAALAADCggIFQAAAA==.Keughor:BAAALAAECgcICwAAAA==.',Ki='Kilerion:BAAALAAECgMIBQAAAA==.Kimmuriell:BAABLAAECoEWAAISAAcIkxtVCAAfAgASAAcIkxtVCAAfAgAAAA==.',Kl='Klasmo:BAAALAAECgQIBgAAAA==.',Kn='Knoladin:BAAALAAECggICAAAAA==.',Kr='Krazuul:BAAALAADCgYICQAAAA==.Krâghor:BAAALAADCggICQAAAA==.Krôll:BAAALAADCgQIBAAAAA==.',Ku='Kuliser:BAAALAADCgcIBwAAAA==.',La='Lanayaa:BAACLAAFFIEFAAMCAAIIABO+GwCKAAACAAIIRBG+GwCKAAAFAAEIkAgAAAAAAAAsAAQKgRoAAwIACAhlFfQzANYBAAIACAjDEvQzANYBAAUABgg1EvaqACoBAAAA.Lariaa:BAAALAADCgcIBwABLAAECggIDwAPAAAAAA==.Layá:BAAALAAECgYICQABLAAECggIDwAPAAAAAA==.',Le='Legit:BAACLAAFFIELAAITAAUIiSBCAgAIAgATAAUIiSBCAgAIAgAsAAQKgSwAAxMACAjbJj0AAIUDABMACAjbJj0AAIUDAAkABQh2EWBxACsBAAAA.Legnilk:BAAALAAECgcIEgAAAA==.Lemurica:BAAALAAECgUIBwAAAA==.',Li='Lisha:BAAALAADCggICAAAAA==.Lizeth:BAAALAAECggICQAAAA==.',Lo='Lorakus:BAAALAAECggIDwAAAA==.Lothenón:BAAALAADCgcIBwAAAA==.',Ly='Lyndi:BAAALAADCgUICwAAAA==.',Ma='Maddor:BAABLAAECoEjAAINAAgIbhhRNQBYAgANAAgIbhhRNQBYAgAAAA==.Marcellã:BAAALAADCggIHwAAAA==.Marox:BAAALAADCggICAABLAAECggIDwAPAAAAAA==.Maxheal:BAAALAADCgEIAQABLAADCggICAAPAAAAAA==.',Me='Merut:BAAALAADCggIFAAAAA==.',Mi='Micanopy:BAAALAADCggIDwAAAA==.Milkywáy:BAAALAAECgUIBQAAAA==.Mixcoatl:BAAALAAECgYIEgAAAA==.',Mo='Moonpox:BAAALAAECgYICQAAAA==.Moonpoxdk:BAAALAAECgcIDwAAAA==.Morfeus:BAAALAAECgYICwAAAA==.Moroge:BAACLAAFFIEIAAICAAIIBiXeDwDFAAACAAIIBiXeDwDFAAAsAAQKgUAAAgIACAjnJWECAGADAAIACAjnJWECAGADAAAA.Mouses:BAAALAADCggICAAAAA==.Moê:BAAALAAECgYIEQAAAA==.',Mu='Mulljiin:BAAALAADCgYICwABLAAECgcIHQABAJMaAA==.',['Má']='Máddox:BAAALAADCggICAAAAA==.',['Mâ']='Mângâlângâ:BAAALAAECgMIBAABLAAECggICAAPAAAAAA==.',Na='Nahara:BAABLAAECoEiAAIUAAgIOSXzAABnAwAUAAgIOSXzAABnAwAAAA==.Naicon:BAAALAAECgYIBgABLAAECggIGwAVAI4WAA==.Nanaki:BAAALAADCggICAAAAA==.Nayria:BAAALAADCgYIBAABLAAECggIDwAPAAAAAA==.',Ne='Nebuchar:BAAALAAECgUIAQAAAA==.Neekan:BAAALAAECgQIBAAAAA==.Nephrokid:BAAALAAECgQIBAAAAA==.',Ni='Nightysra:BAAALAADCgUIBQAAAA==.Nineoneone:BAAALAAECgcIDwAAAA==.',No='Nockchan:BAAALAAECgcIEwAAAA==.Nokivaris:BAAALAAECgIIAgAAAA==.',Od='Odetta:BAAALAAECgEIAQAAAA==.',Os='Ossî:BAAALAAECgYIEgAAAA==.',Pi='Pizdation:BAAALAAECggICAAAAA==.',Pr='Priwardina:BAAALAAFFAIIAgAAAA==.',Pv='Pvphealsham:BAABLAAECoEqAAITAAgIyhVYQQDyAQATAAgIyhVYQQDyAQABLAAFFAYIEgAJAJ4WAA==.',Qd='Qdww:BAAALAAECggIDgAAAA==.',Qu='Quixxi:BAAALAAECgMIBAAAAA==.',Ra='Raisana:BAAALAADCgIIAgAAAA==.Raltar:BAAALAADCgcIBwABLAADCggICAAPAAAAAA==.Ralunara:BAAALAADCgEIAQAAAA==.Razuye:BAAALAAECggIDgAAAA==.Razuyé:BAAALAAECggICAAAAA==.',Re='Ready:BAABLAAECoEaAAIWAAYIIBRenwCAAQAWAAYIIBRenwCAAQAAAA==.Reifn:BAAALAAECgYICwAAAA==.Respektive:BAAALAAECgMIAwAAAA==.',Ri='Rikolo:BAABLAAECoEWAAMXAAcIARoEPwAPAgAXAAcIARoEPwAPAgAYAAEIdx3cgABDAAABLAAECggIHQAGAP8XAA==.',Ro='Rotok:BAAALAADCgUIBQAAAA==.',Ru='Rumî:BAAALAAECgYIDAAAAA==.',['Râ']='Râfiki:BAAALAAECgYIBwABLAAFFAYIEgAJAJ4WAA==.',Sc='Sceltury:BAABLAAECoEZAAITAAcInw+poAACAQATAAcInw+poAACAQAAAA==.Schlemil:BAAALAADCgcIBwAAAA==.Schnauze:BAAALAADCggIEgAAAA==.',Se='Selif:BAAALAADCgYIBgAAAA==.Seriously:BAAALAADCggIDgAAAA==.Serphiron:BAAALAADCgcIBwAAAA==.Seröga:BAABLAAECoEWAAIRAAcIchrjJgAIAgARAAcIchrjJgAIAgAAAA==.',Sh='Shali:BAAALAADCggIHQAAAA==.Sharokin:BAABLAAECoEWAAIJAAcIKCNdFQDRAgAJAAcIKCNdFQDRAgAAAA==.Shaukai:BAAALAAECgYIEgAAAA==.Shenya:BAAALAAECgMICAAAAA==.Sherrena:BAAALAAECgYIBwAAAA==.Sháy:BAAALAAECgYIEQAAAA==.',Si='Sikari:BAAALAADCgUIBQABLAAECggICQAPAAAAAA==.Simboon:BAABLAAECoEUAAIFAAcIih5cNQBGAgAFAAcIih5cNQBGAgAAAA==.Sinla:BAABLAAFFIEGAAIJAAIIlAgcJQCFAAAJAAIIlAgcJQCFAAAAAA==.',Sn='Snowx:BAAALAADCggIHwAAAA==.',So='Sombara:BAABLAAECoEVAAIXAAYIHAhFjAAmAQAXAAYIHAhFjAAmAQAAAA==.Soneâ:BAAALAAECgYIDAAAAA==.Soulkiss:BAAALAAECgYIBwAAAA==.',Sp='Spritti:BAAALAAECgcIEgAAAA==.',St='Stãndgebläse:BAAALAADCgYICQAAAA==.',Sy='Syrùss:BAAALAADCgcIBwABLAAECggIFwATAEAPAA==.',['Sá']='Sálith:BAAALAADCgcIBgAAAA==.',['Sâ']='Sâsûke:BAAALAAECggIEwAAAA==.',Ta='Taric:BAAALAAECgUIBgAAAA==.',Te='Teflon:BAABLAAECoEcAAIOAAgImhkdMwBqAgAOAAgImhkdMwBqAgAAAA==.Tentacuru:BAAALAADCgEIAQAAAA==.Teranodon:BAAALAAECgcIDQAAAA==.Tessã:BAAALAAECggICgAAAA==.',Th='Thrain:BAAALAADCgMIAwAAAA==.',To='Tohuwabohu:BAAALAAFFAIIBAAAAA==.Tolen:BAAALAADCggICAAAAA==.Torontos:BAAALAADCggICAAAAA==.',Tr='Triage:BAABLAAECoErAAIZAAgIVh2iBwDCAgAZAAgIVh2iBwDCAgAAAA==.',Ty='Tyronny:BAAALAAECgYIDQAAAA==.',Ul='Ultraradikal:BAAALAAECgEIAQAAAA==.',Ur='Uriel:BAAALAAECgEIAQAAAA==.',Uw='Uwe:BAABLAAECoEbAAIaAAgIEA9xMACPAQAaAAgIEA9xMACPAQAAAA==.',Va='Vahyna:BAAALAAECgYIBwAAAA==.Vargrym:BAAALAADCgcIBgAAAA==.',Ve='Veni:BAAALAADCggIDwAAAA==.Veyron:BAAALAADCggICAAAAA==.',Vi='Vieja:BAAALAADCgYIBgAAAA==.Vingthor:BAABLAAECoEVAAIDAAYIgw0mGAA4AQADAAYIgw0mGAA4AQAAAA==.',Wa='Waitandbleed:BAAALAAECgYIEQAAAA==.Waxer:BAABLAAECoEeAAIXAAYIGRpJTQDYAQAXAAYIGRpJTQDYAQAAAA==.',Wi='Wickedy:BAAALAAECgYIEgAAAA==.',Wu='Wukkuschukku:BAACLAAFFIESAAIJAAYInhY5BAAHAgAJAAYInhY5BAAHAgAsAAQKgTAAAwkACAjSJN4EAGADAAkACAjSJN4EAGADABMAAQitBYQVASIAAAAA.',['Wî']='Wîkkîschîkkî:BAACLAAFFIELAAIbAAMIfhmxAwD6AAAbAAMIfhmxAwD6AAAsAAQKgRgAAhsACAgeIXsKANkCABsACAgeIXsKANkCAAAA.',['Wú']='Wúkkú:BAACLAAFFIEGAAIFAAIIlBMWLACPAAAFAAIIlBMWLACPAAAsAAQKgRoAAgUACAhgI40SAPYCAAUACAhgI40SAPYCAAAA.Wúkkúschúkkú:BAAALAAFFAEIAQAAAA==.',['Wû']='Wûkkû:BAAALAADCgEIAQABLAAFFAYIEgAJAJ4WAA==.Wûkkûschûkkû:BAACLAAFFIEGAAIFAAIIPBZfIwCcAAAFAAIIPBZfIwCcAAAsAAQKgRkAAgUABwhzIPosAGgCAAUABwhzIPosAGgCAAEsAAUUBggSAAkAnhYA.',Yu='Yubel:BAAALAAECggICwAAAA==.',Ze='Zephiris:BAAALAADCgQIBgAAAA==.',Zi='Ziplos:BAACLAAFFIESAAIIAAUIDSLqAgDaAQAIAAUIDSLqAgDaAQAsAAQKgRYAAwgACAigJG4EABwDAAgACAigJG4EABwDAAYABgg9C6E/AOkAAAAA.',['Àu']='Àurøra:BAAALAADCgcICQAAAA==.',['Ár']='Árýá:BAAALAAECgYIBgABLAAECggIDwAPAAAAAA==.',['Êl']='Êlune:BAAALAADCgIIAgAAAA==.',['Êm']='Êmmely:BAAALAADCggIGwAAAA==.',['Ën']='Ënurfala:BAAALAADCgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end