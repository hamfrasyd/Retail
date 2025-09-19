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
 local lookup = {'Rogue-Assassination','Warlock-Destruction','Warlock-Affliction','Unknown-Unknown','Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','Monk-Mistweaver','Evoker-Devastation','Druid-Restoration','Druid-Guardian','Druid-Balance','DemonHunter-Havoc','Mage-Arcane','Hunter-BeastMastery','Warlock-Demonology','Druid-Feral','DemonHunter-Vengeance','Shaman-Elemental','Mage-Frost','Shaman-Restoration','Priest-Shadow','Paladin-Protection','DeathKnight-Frost','Warrior-Protection','Hunter-Marksmanship','Monk-Windwalker',}; local provider = {region='EU',realm='EarthenRing',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aawia:BAABLAAECoEXAAIBAAcIHA8TIQCxAQABAAcIHA8TIQCxAQAAAA==.',Ab='Abidi:BAAALAAECgcIEAAAAA==.Abracadavra:BAAALAAECggIBAAAAA==.',Ad='Addinio:BAAALAAECgcIEQAAAA==.',Ae='Aerdris:BAAALAADCgQIBAAAAA==.Aevathar:BAAALAADCgMIAwAAAA==.',Al='Alcyone:BAAALAAECgMICAAAAA==.Alithyra:BAAALAADCgYIBgAAAA==.',Am='Amarula:BAAALAADCggICAAAAA==.',An='Androva:BAAALAADCggICAAAAA==.Anirei:BAAALAAECgYIEAAAAA==.Anorwen:BAAALAAECgYIBgAAAA==.Anya:BAABLAAECoEVAAMCAAgInhT7IQAfAgACAAgInhT7IQAfAgADAAIIPxBKJAB+AAAAAA==.',Ar='Arkam:BAAALAAECgQIBgAAAA==.Arthulaz:BAAALAADCgUIBQAAAA==.Arthulius:BAAALAADCgEIAQABLAADCgUIBQAEAAAAAA==.Arthyronyx:BAAALAAECgcIDwAAAA==.',As='Ashrethar:BAAALAAECgYICgAAAA==.Askhim:BAAALAADCgYIBgAAAA==.',Av='Avengeline:BAAALAADCggICQAAAA==.',Ba='Baelo:BAAALAADCgcIBwAAAA==.Baxigo:BAAALAADCggICAAAAA==.',Be='Belladonná:BAAALAADCgIIAgAAAA==.Bescea:BAAALAAECgUIBwAAAA==.Beástmaster:BAAALAADCgcIBwAAAA==.',Bh='Bhalnur:BAAALAAECgcIEQAAAA==.',Bl='Blair:BAAALAAECgIIAgAAAA==.',Bo='Bobopala:BAABLAAECoEaAAIFAAgI2yFEDAAJAwAFAAgI2yFEDAAJAwAAAA==.Bomidoff:BAAALAADCgcICQAAAA==.Bomimeow:BAAALAADCgYIBgABLAADCgcICQAEAAAAAA==.Bonksik:BAACLAAFFIEHAAIGAAMIDBsUBAApAQAGAAMIDBsUBAApAQAsAAQKgRwAAgYACAiNJOsEAEADAAYACAiNJOsEAEADAAAA.Bowmistress:BAAALAAECgMIBQAAAA==.',Br='Bratla:BAAALAADCgcIBwAAAA==.Bratsal:BAAALAAECgIIAgAAAA==.Brimlor:BAAALAAECgIIAgAAAA==.Briuk:BAAALAADCgMIAwAAAA==.Bromeo:BAAALAADCgMIAgABLAADCgcIBwAEAAAAAA==.Bruna:BAABLAAECoEYAAIHAAcIVRwaCQBGAgAHAAcIVRwaCQBGAgAAAA==.',Ca='Calamita:BAAALAADCgcIBwAAAA==.Cathbadh:BAAALAAECgYICAAAAA==.',Ce='Cessalls:BAAALAADCggICAAAAA==.',Cl='Clerik:BAAALAADCggICQABLAAECggIFQAIAOYhAA==.',Co='Cocowater:BAAALAAECgEIAQAAAA==.Cogwire:BAAALAAECggIBgAAAA==.',Cy='Cyndrel:BAAALAADCgcIDAAAAA==.Cyrann:BAAALAAECgMIBwAAAA==.',Da='Darkblaze:BAAALAAECgQIBAAAAA==.Darkstyle:BAAALAADCggICAABLAAECgYICQAEAAAAAA==.Darkwank:BAAALAAECgYICQAAAA==.Daylana:BAAALAAECgYIDAAAAA==.Daysie:BAAALAADCgcIBwAAAA==.',De='Deekadin:BAABLAAECoEUAAIFAAgInBDCNQD8AQAFAAgInBDCNQD8AQAAAA==.Demicha:BAAALAADCggICQAAAA==.Demonessia:BAAALAADCggICAAAAA==.',Di='Diamon:BAAALAAECgMIAwAAAA==.Dioni:BAAALAADCgcIBwAAAA==.Dizzy:BAAALAADCgcIBwAAAA==.',Do='Donutwarrior:BAAALAAECgQIBgAAAA==.',Dr='Dracurion:BAAALAADCggICAAAAA==.Dragosis:BAABLAAECoEVAAIJAAcIlhp5EwAmAgAJAAcIlhp5EwAmAgAAAA==.Drakkaroth:BAAALAADCggICAABLAAECgcIGAAHAFUcAA==.Draughen:BAAALAADCggIFgAAAA==.Draxari:BAAALAADCggICAAAAA==.Drekarth:BAAALAADCgYICwAAAA==.Drudu:BAABLAAECoEYAAQKAAgIxQxlLwB0AQAKAAgIxQxlLwB0AQALAAYInggiDwD0AAAMAAEITQaZYAA4AAAAAA==.Drunkenfeet:BAAALAADCgcIBwAAAA==.',Du='Dutchgeneral:BAAALAAECgYIBgAAAA==.',['Dö']='Dödgrävarn:BAAALAAECgUIBwAAAA==.',Ea='Eamene:BAAALAADCgYIBgAAAA==.Eartenio:BAAALAADCgUIBQAAAA==.Earwigg:BAAALAADCggICQAAAA==.',Ei='Eiria:BAAALAADCgIIAgAAAA==.',El='Elrathir:BAABLAAECoEVAAIFAAcIuRekPADhAQAFAAcIuRekPADhAQAAAA==.Elsà:BAAALAADCgcIBwAAAA==.',Em='Emerick:BAABLAAECoEYAAIFAAgIyyLoCQAhAwAFAAgIyyLoCQAhAwAAAA==.',En='Enilea:BAAALAADCgYIBgAAAA==.',Er='Eranaar:BAAALAADCgcIBwAAAA==.',Fa='Faclya:BAAALAAECgEIAQAAAA==.Fantast:BAAALAAECgYIBgAAAA==.Fantazja:BAAALAADCgUIBQAAAA==.Favoxh:BAAALAAECgMIAwAAAA==.',Fe='Felkite:BAABLAAECoEVAAINAAcIWSGTFgCqAgANAAcIWSGTFgCqAgAAAA==.Feylari:BAAALAAECgEIAQAAAA==.Feythion:BAAALAAECgcIDwAAAA==.',Fi='Finnmag:BAABLAAECoEVAAIOAAcIIxPPPADLAQAOAAcIIxPPPADLAQAAAA==.Fistrik:BAABLAAECoEVAAIIAAgI5iHWAwDsAgAIAAgI5iHWAwDsAgAAAA==.',Fr='Framan:BAAALAADCggICAABLAAECgcIFQADABsfAA==.Frankii:BAAALAAECgUIBgAAAA==.Frela:BAAALAAECgYIBgAAAA==.Frima:BAABLAAECoEVAAIPAAcIdSGSEwCSAgAPAAcIdSGSEwCSAgAAAA==.Frunk:BAABLAAECoEVAAMDAAcIGx8rBABjAgADAAYIZiIrBABjAgAQAAcIxRM0FgDgAQAAAA==.',Ft='Ftgbztmr:BAAALAAFFAIIAgAAAA==.',Ga='Gabbryx:BAAALAADCgYIBgAAAA==.',Gi='Giinjou:BAAALAAECgMIBAAAAA==.Gingernutter:BAAALAADCggIDwAAAA==.Gizzy:BAAALAAECgEIAQAAAA==.',Gl='Gloriette:BAAALAAECgcIEAAAAA==.',Go='Gobbox:BAAALAADCgMIBAAAAA==.',Gr='Greenpork:BAAALAAECgEIAQAAAA==.',Ha='Hacon:BAAALAAECgYICQAAAA==.Halgir:BAABLAAECoEVAAIFAAgITx2/FQC0AgAFAAgITx2/FQC0AgAAAA==.Hammertime:BAAALAADCggICAAAAA==.Hardtek:BAAALAAFFAIIBAAAAA==.',He='Heathér:BAAALAADCggIDgAAAA==.',Hi='Hi:BAAALAADCgYIBgAAAA==.Hidedruid:BAABLAAECoEWAAIRAAgIuyPJAgAKAwARAAgIuyPJAgAKAwAAAA==.Hideevoker:BAAALAAECggICAABLAAECggIFgARALsjAA==.Hidemonk:BAAALAADCggICAABLAAECggIFgARALsjAA==.Hiyori:BAAALAADCgYIBwAAAA==.',Ho='Hoaqino:BAAALAADCggICQAAAA==.',Hu='Huai:BAAALAAECgYIDgAAAA==.Hueblo:BAAALAAECgcIDwAAAA==.Huntcore:BAAALAAECggIDAAAAA==.Huntess:BAAALAAECgYIBwAAAA==.Hurjarja:BAAALAAECgEIAQAAAA==.Huror:BAAALAAECgYICQAAAA==.',Hy='Hydaelyn:BAAALAAECgIIAgAAAA==.',['Hö']='Höder:BAAALAADCggIGAAAAA==.',If='Ifalna:BAAALAAECgcIEQAAAA==.',Il='Ilireth:BAABLAAECoEVAAISAAcIVCD+BQCKAgASAAcIVCD+BQCKAgAAAA==.Illadius:BAAALAAECgcIEQAAAA==.',In='Ingà:BAAALAADCgIIAgAAAA==.',Is='Isabel:BAAALAAECgYICgAAAA==.',Ji='Jinnia:BAAALAAECgMIBAAAAA==.Jizog:BAABLAAECoEYAAISAAgI5xnNBwBbAgASAAgI5xnNBwBbAgAAAA==.',Jo='Jon:BAAALAADCgMIAwAAAA==.Jou:BAAALAAECgEIAQAAAA==.',Ka='Kalimba:BAAALAAECgIIAgAAAA==.Kalquan:BAAALAADCgcIEQAAAA==.Katten:BAAALAAECgMIBgAAAA==.',Ke='Kerchak:BAAALAADCggICAAAAA==.',Kh='Khaya:BAAALAADCgYIBgAAAA==.',Ki='Kiora:BAAALAADCggIFgABLAAECgcIGAAHAFUcAA==.Kirameow:BAAALAADCgcIBwAAAA==.',Ko='Korenwolf:BAAALAADCgcICQAAAA==.Kostroma:BAAALAAECgYICgAAAA==.',Kr='Kranosh:BAABLAAECoEUAAITAAcI5xRbJwDfAQATAAcI5xRbJwDfAQAAAA==.Krast:BAAALAADCggIEAABLAAECgYIBAAEAAAAAA==.',Ky='Kyrena:BAAALAAECgMIBwAAAA==.Kyriea:BAAALAAECgMIAgAAAA==.',La='Ladidruid:BAEALAADCggICAAAAA==.Laerbrithyre:BAAALAAECgYICAAAAA==.Lampedoo:BAABLAAECoEVAAMOAAcI2BlnMAAHAgAOAAcIsBZnMAAHAgAUAAYIcxbNJQBrAQAAAA==.Lampris:BAAALAADCggIEAAAAA==.Lanenaar:BAAALAADCggICgAAAA==.Laoganma:BAAALAADCgYIBgAAAA==.Lascap:BAAALAAECgYICwAAAA==.Last:BAAALAADCgYIDwAAAA==.Latta:BAAALAAECggIDQAAAA==.',Le='Leikila:BAABLAAECoEXAAIVAAgIcROfLQDLAQAVAAgIcROfLQDLAQAAAA==.',Li='Lightdealer:BAAALAADCggIDwAAAA==.Lightshope:BAAALAAECgYICQAAAA==.Lithi:BAAALAADCgYIBgAAAA==.Liung:BAAALAADCggIEAAAAA==.',Ll='Lloyyd:BAAALAAECgIIAgAAAA==.',Lo='Lockaio:BAAALAADCggICgAAAA==.Looma:BAAALAADCggICAAAAA==.',Lu='Luxo:BAABLAAECoEWAAIVAAcIxRQvNgClAQAVAAcIxRQvNgClAQAAAA==.',['Là']='Làn:BAAALAADCggICQABLAAECgUIBQAEAAAAAA==.Lànn:BAAALAAECgEIAQAAAA==.',['Lá']='Lán:BAAALAAECgUIBQAAAA==.',['Læ']='Læknirinn:BAAALAAECgYIDQAAAA==.',Ma='Mattma:BAAALAADCgYIBgAAAA==.Maximilian:BAAALAADCggICAAAAA==.',Me='Meara:BAAALAAECgEIAQAAAA==.Megastab:BAABLAAECoEbAAIBAAgIgBhfDgB2AgABAAgIgBhfDgB2AgAAAA==.Memebeam:BAEALAADCggICAAAAA==.Meodi:BAEALAADCgYIBgABLAADCggICAAEAAAAAA==.Merkula:BAAALAAECgYIEwAAAA==.',Mi='Micarta:BAAALAAECgIIAgAAAA==.Mileeria:BAACLAAFFIEGAAIWAAMIGhMGBgD1AAAWAAMIGhMGBgD1AAAsAAQKgSAAAhYACAgRI38GABoDABYACAgRI38GABoDAAAA.Minorkinhah:BAAALAAECgYIBgAAAA==.Mirdad:BAAALAADCgQIBAAAAA==.',Mo='Mokraw:BAAALAADCggICAAAAA==.Morc:BAAALAAECggIBgAAAA==.Mortiné:BAAALAADCggIDgAAAA==.Moxxira:BAAALAAECgcIEQAAAA==.',Mu='Mumraa:BAAALAAECgIIAgAAAA==.',My='Mymer:BAAALAAECgYIBAAAAA==.',Na='Nadriel:BAAALAADCgYIBgAAAA==.Naksam:BAAALAADCggICwAAAA==.Nalá:BAAALAADCggICAAAAA==.Nava:BAAALAADCgUIBQAAAA==.',Ne='Nemiria:BAAALAADCgEIAQAAAA==.Neomimad:BAAALAAECgMIBAAAAA==.Nevagosa:BAAALAAECgcICgAAAA==.',Ni='Nikkori:BAAALAADCggICAAAAA==.Niriya:BAAALAAECgUIBwAAAA==.Nitro:BAABLAAECoEWAAIXAAcImhzUCgAvAgAXAAcImhzUCgAvAgAAAA==.',No='Noselingwa:BAAALAADCgMIBgAAAA==.Novakk:BAAALAAECgcIBwAAAA==.',Nu='Nuubxie:BAABLAAECoEdAAIGAAcIcCV3CgD6AgAGAAcIcCV3CgD6AgAAAA==.',Ny='Nyarlathotep:BAAALAADCgIIAgAAAA==.Nyvi:BAAALAADCggIBgAAAA==.',Nz='Nzk:BAAALAAECgEIAgAAAA==.',Od='Oditts:BAAALAADCgcIDQAAAA==.',Ok='Okkie:BAAALAAECgMIAwAAAA==.',Oo='Oosterveld:BAAALAAECgIIAgABLAAECgcIDwAEAAAAAA==.',Or='Orenem:BAAALAADCggIFwAAAA==.',Ou='Outie:BAAALAADCgIIAgAAAA==.Outlander:BAAALAAECgYIBgAAAA==.',Pd='Pdwebslinger:BAABLAAECoEaAAMFAAgIoQq/VQCOAQAFAAgIjwm/VQCOAQAXAAYIZgd/KACwAAAAAA==.',Pe='Peggster:BAAALAAECgUIBQAAAA==.Perkele:BAAALAAECgcIEQAAAA==.',Ph='Phoebè:BAAALAADCgYIBgAAAA==.',Pi='Pickerin:BAAALAAECgcIDwAAAA==.',Pl='Pleochroic:BAAALAADCgEIAQAAAA==.',Po='Poet:BAAALAADCggIDwAAAA==.Potatofamer:BAAALAADCggIDAAAAA==.Potatoshamer:BAAALAADCgcIBwAAAA==.',Pr='Preeppe:BAAALAADCgUIBQAAAA==.Prðteus:BAAALAADCgYIBgAAAA==.',Pu='Puckaio:BAAALAADCggICAAAAA==.',Qy='Qyo:BAAALAADCgcIBwAAAA==.',Ra='Rakarath:BAAALAAECgYIBgAAAA==.Razatt:BAAALAAECgcIDwAAAA==.',Re='Redflower:BAAALAADCggICAAAAA==.Redkiygost:BAAALAAECgEIAgAAAA==.',Ri='Rigamitis:BAAALAAECgEIAQAAAA==.',Ro='Roasties:BAAALAADCgcIDAAAAA==.Roxanne:BAAALAAECgIIBAAAAA==.Roxywolf:BAAALAADCgUIBQAAAA==.',Ry='Ryaio:BAAALAAECgMIAwAAAA==.',Sa='Sanniya:BAAALAAECgYICQAAAA==.Saturos:BAAALAADCgEIAQAAAA==.',Sc='Scalerik:BAAALAAECgMIAwABLAAECggIFQAIAOYhAA==.Schnoofas:BAAALAADCgEIAQAAAA==.',Se='Seagaard:BAAALAAECgYIEQAAAA==.Seril:BAAALAAECgYIDAAAAA==.Sevensad:BAAALAADCgYIBgAAAA==.',Sh='Shadowweaver:BAAALAADCgYIBgAAAA==.Shaikki:BAAALAAECgcIEQAAAA==.Shanden:BAAALAAECgYIDQAAAA==.Shonin:BAAALAAECgcIEQAAAA==.',Si='Silveatia:BAAALAADCgQIBAABLAAECgYIBgAEAAAAAA==.',Sl='Slakt:BAAALAAECgcIEQAAAA==.',Sn='Snuffey:BAAALAADCgIIAgAAAA==.',So='Soriel:BAAALAAECgYIEAAAAA==.Sorrell:BAAALAADCgMIAwAAAA==.',Sp='Spiridragon:BAABLAAECoEfAAIJAAgIIRxcDACRAgAJAAgIIRxcDACRAgAAAA==.Spiridymonk:BAAALAADCggICAABLAAECggIHwAJACEcAA==.',Su='Sudaki:BAAALAAECgYIDwAAAA==.Sunglassdog:BAAALAADCgcIBwAAAA==.',Sv='Svinpäls:BAAALAAECggICQAAAA==.',Sy='Syri:BAAALAAECgMIAwAAAA==.',['Sé']='Séphíróth:BAAALAAECgQICQAAAA==.',Ta='Tahiri:BAAALAAECgYICgAAAA==.Tauler:BAAALAADCgcIBgAAAA==.Taurenus:BAAALAADCgIIAgAAAA==.',Te='Teýla:BAAALAADCggICAAAAA==.',Th='Thechewerz:BAABLAAECoEYAAIYAAgICRs/JABTAgAYAAgICRs/JABTAgAAAA==.Thermidor:BAABLAAECoEWAAIZAAcIwB07DABRAgAZAAcIwB07DABRAgAAAA==.Thoomrah:BAAALAAECgYIBgAAAA==.Thurid:BAAALAAECgYIEAAAAA==.',Ti='Tiindra:BAAALAAECgUIBQAAAA==.Tiurri:BAAALAAECgcICgAAAA==.',To='Toasties:BAAALAAECgMIAwAAAA==.Toffeetapper:BAAALAADCgQIBgAAAA==.Tonant:BAAALAADCgYICQAAAA==.Torgar:BAAALAAECgcICwAAAA==.Tourar:BAABLAAECoEVAAIaAAcIUh84EACBAgAaAAcIUh84EACBAgAAAA==.',Tr='Treguard:BAAALAAECgcIDQAAAA==.Trinkets:BAAALAAECggIDwAAAA==.Trubulox:BAAALAAECgcICQAAAA==.Trä:BAAALAAECgYICAAAAA==.',Tu='Tuhmamuumuu:BAAALAAECgIIAgAAAA==.Turboslug:BAAALAADCgEIAQABLAADCgcIDQAEAAAAAA==.',Ul='Uliade:BAAALAAECgMIBgAAAA==.',Ur='Ursla:BAAALAADCggIEAAAAA==.',Va='Valarie:BAAALAAECgcIDgAAAA==.Valouri:BAABLAAECoEVAAMIAAgIIBsACAB8AgAIAAgIIBsACAB8AgAbAAMI3wf5MwByAAAAAA==.',Ve='Velorna:BAAALAADCggICwAAAA==.Verard:BAAALAADCgcIBwAAAA==.Vesicular:BAAALAAECgcIDwAAAA==.',Vh='Vhazhreal:BAAALAADCgEIAQAAAA==.',Vi='Viktor:BAAALAADCgYIBgAAAA==.Vince:BAABLAAECoEXAAMaAAgI6BYZHQD6AQAaAAcIdhcZHQD6AQAPAAQIFgmSaQDVAAAAAA==.',Vo='Voiddancer:BAAALAADCgQIBAAAAA==.Voodude:BAAALAAECgEIAQAAAA==.Vordar:BAAALAADCgcIAQAAAA==.',['Væ']='Væv:BAAALAADCgUIBQAAAA==.',Wa='Waggoner:BAAALAAFFAIIAwAAAA==.',We='Webslingerz:BAAALAAECgMIAwABLAAECggIGgAFAKEKAA==.',Wi='Wildboi:BAAALAAECgYIEAAAAA==.Wildghosts:BAAALAADCgUIBQAAAA==.',Wo='Wor:BAAALAADCgUIAwAAAA==.',Wr='Wrighty:BAAALAAECgMIBgAAAA==.',Wu='Wundo:BAAALAAECgIIBAAAAA==.',Xa='Xari:BAAALAAECgcIDgAAAA==.',Xe='Xenrie:BAAALAAECgMIBwAAAA==.Xerxes:BAAALAADCgEIAQAAAA==.',Xi='Xinzy:BAAALAAECgMICgAAAA==.Xiuwei:BAAALAAECgMIBQAAAA==.',Xr='Xreinak:BAAALAADCgcIAQAAAA==.',Yu='Yumo:BAAALAAECgYIDwAAAA==.',Za='Zaithrizeth:BAAALAADCgEIAQAAAA==.Zalazan:BAAALAAECgMIBQAAAA==.Zaté:BAAALAADCgcIBwABLAAECgcIDwAEAAAAAA==.',Ze='Zenee:BAAALAAECgcIEgAAAA==.',Zo='Zorgrom:BAAALAAECgcIEQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end