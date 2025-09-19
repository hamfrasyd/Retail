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
 local lookup = {'Unknown-Unknown','Priest-Shadow','Paladin-Retribution','DemonHunter-Havoc','Mage-Arcane','Warrior-Fury','Hunter-Marksmanship','Warlock-Destruction','Paladin-Protection','Warlock-Demonology','Warlock-Affliction','Warrior-Protection','Priest-Holy','DemonHunter-Vengeance','Shaman-Elemental','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Blood','Rogue-Outlaw','Paladin-Holy','Evoker-Devastation','Evoker-Preservation','Hunter-BeastMastery','Druid-Balance','DeathKnight-Unholy','Monk-Mistweaver','Rogue-Assassination','Druid-Restoration','Priest-Discipline','Mage-Frost','Hunter-Survival',}; local provider = {region='EU',realm='Frostwhisper',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aaphexx:BAAALAAECgYIDAAAAA==.',Ab='Abnormal:BAAALAADCgcIDQAAAA==.',Ac='Acesulfam:BAAALAAECggIAwAAAA==.',Ae='Aeilhunt:BAAALAADCgcICQAAAA==.',Ai='Airolite:BAAALAAECgQIBAAAAA==.',Al='Alakasama:BAAALAADCgYIBgAAAA==.',Am='Amaha:BAAALAAECgYIDAAAAA==.Ameth:BAAALAADCgQIBwABLAAFFAIIAgABAAAAAA==.Amethuil:BAAALAADCgcIBwABLAAFFAIIAgABAAAAAA==.',An='Anchev:BAAALAADCgYIBgAAAA==.Ancientthor:BAAALAAECgUIAwAAAA==.Anomic:BAAALAAECgYIDAAAAA==.Ansaaja:BAAALAAECgIIAgAAAA==.',Ap='Apricus:BAAALAAECgcIDgAAAA==.',Ar='Arcanon:BAAALAAECgEIAQAAAA==.Armben:BAAALAAECgQIBgAAAA==.',As='Aseeton:BAAALAADCgcIFAAAAA==.',At='Athral:BAAALAADCgUIBQAAAA==.Atroux:BAAALAAECgcIEgAAAA==.',Av='Avengingzero:BAAALAAECgMIAwAAAA==.',Ay='Ayami:BAAALAAECgYICAAAAA==.',Ba='Baconnaise:BAAALAADCggICAAAAA==.Badox:BAAALAAECgMIBAAAAA==.Barnold:BAAALAADCggICAAAAA==.',Be='Beater:BAAALAAECgMIAwAAAA==.',Bi='Bighuntz:BAAALAAECgYIEQAAAA==.',Bj='Bjarnedragen:BAAALAADCggICAAAAA==.',Bl='Blondjanoll:BAAALAAECgYICQAAAA==.Bluedabedee:BAAALAADCggICAAAAA==.',Bo='Boltz:BAAALAAECgMIAwAAAA==.Boopsboops:BAAALAAECgcIDgAAAA==.',Br='Brbcs:BAAALAAECgQIBgAAAA==.Brotato:BAAALAAECggICAAAAA==.Bräw:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.',Bu='Budbundy:BAAALAADCgYIBQAAAA==.Bull:BAAALAAECgYIDwAAAA==.Bullcheat:BAAALAADCggICAAAAA==.Bumblebèé:BAAALAADCgcICQAAAA==.',['Bé']='Bébbí:BAABLAAECoEUAAICAAYINR/qHwD3AQACAAYINR/qHwD3AQAAAA==.',Ca='Caprian:BAAALAAECgYIBwAAAA==.',Ce='Cevion:BAABLAAECoEZAAIDAAgIgRnrHAB8AgADAAgIgRnrHAB8AgAAAA==.',Ch='Chiea:BAAALAAECgMIAwAAAA==.Chronoa:BAAALAAECgMIBwAAAA==.',Ci='Cindy:BAAALAADCgYIBgAAAA==.',Cl='Cleavesteve:BAAALAADCggICQAAAA==.',Co='Coldveins:BAAALAADCgcICAAAAA==.Conaann:BAAALAAECggIAgAAAA==.Coolikeafool:BAAALAAECgIIAgAAAA==.Copper:BAAALAADCggICAAAAA==.Corpotaurus:BAAALAADCgcIBwAAAA==.Cowbrisket:BAAALAAECgUIBQAAAA==.',Cr='Cranpyz:BAAALAAECgYICwAAAA==.Cryllez:BAAALAADCgEIAQAAAA==.',['Cá']='Cáryoxz:BAABLAAECoEXAAIEAAcIbxBpRgCsAQAEAAcIbxBpRgCsAQAAAA==.',Da='Dannus:BAAALAADCgYIBgAAAA==.',De='Deathlight:BAAALAADCggIEwAAAA==.Decilla:BAAALAAECgcIDAAAAA==.Deefer:BAAALAADCgMIAwAAAA==.Deltagoodrem:BAAALAAECgIIAgAAAA==.Demonclave:BAAALAADCgUIBQAAAA==.Desaanix:BAAALAADCggICAAAAA==.Deviil:BAAALAAECgUIBwAAAA==.Devour:BAAALAAECgYIDAAAAA==.',Dg='Dgb:BAAALAADCgEIAQAAAA==.',Dh='Dhturka:BAAALAAECgYIBwAAAA==.',Di='Didres:BAAALAADCgYIBwAAAA==.Digpics:BAAALAADCgQIBAAAAA==.Diklorvos:BAAALAADCgcIBwAAAA==.Dilweed:BAAALAAECggICAAAAA==.Dispare:BAAALAAECgMIBwAAAA==.',Do='Dolfildor:BAAALAAECgQICAAAAA==.Doodoomies:BAABLAAECoEYAAIFAAgICxgjIABmAgAFAAgICxgjIABmAgAAAA==.Dorror:BAAALAAECgMIBwAAAA==.Dotctor:BAAALAAECgcICwAAAA==.',Dr='Draald:BAAALAAECgMIBwAAAA==.Drakela:BAAALAAECgQIBAABLAAECgcIDwABAAAAAA==.Drakoulaki:BAAALAADCggICAABLAAECggIFgAGAA4FAA==.Drimen:BAABLAAECoEYAAIGAAgIKh8zCgD+AgAGAAgIKh8zCgD+AgAAAA==.Drunkenmasta:BAAALAADCggIDwAAAA==.',Du='Dumbasshuntz:BAABLAAECoEXAAIHAAcIBRaVJQC5AQAHAAcIBRaVJQC5AQAAAA==.',Dw='Dwarfkingg:BAAALAADCggIDgAAAA==.',['Dó']='Dóris:BAAALAAECgYIDwAAAA==.',['Dö']='Dödsmåns:BAAALAAECgQIBAAAAA==.',['Dø']='Dødballe:BAAALAAECgcIBwAAAA==.',Eb='Ebolowa:BAAALAAECgIIAQAAAA==.',Ee='Eek:BAAALAAECggICAAAAA==.',Ef='Efedrea:BAAALAAECgMIBAAAAA==.',Eg='Egotastic:BAABLAAECoEXAAIIAAgIqxUHIAAuAgAIAAgIqxUHIAAuAgAAAA==.',El='Elighost:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.',Em='Emorager:BAABLAAECoEUAAIJAAcIYxo5DQADAgAJAAcIYxo5DQADAgAAAA==.',En='Enforcerer:BAABLAAECoEZAAQIAAgIERSiJQAFAgAIAAgIERSiJQAFAgAKAAYImQqsKwBYAQALAAEI4gWDNQAyAAAAAA==.Envy:BAAALAAECggICAAAAA==.',Ep='Epicmeal:BAAALAADCgYIBgAAAA==.',Er='Erue:BAAALAAECgYIBgAAAA==.',Ex='Exhusband:BAAALAADCgUIBQAAAA==.',Ey='Eyesoree:BAAALAAECggICQABLAAECgYIDQABAAAAAA==.',Fa='Faceblock:BAAALAAECgEIAQAAAA==.Faizan:BAAALAAECgcIEAAAAA==.',Fd='Fdszirius:BAABLAAECoEYAAIMAAgI9RVKEwDmAQAMAAgI9RVKEwDmAQAAAA==.',Fe='Felangel:BAAALAAECggIEAAAAA==.Felene:BAAALAAECgMIBwAAAA==.Felevalin:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Felissa:BAAALAAECgYICQAAAA==.Felocity:BAAALAADCgUIBQAAAA==.Femmern:BAAALAADCggICgAAAA==.Fendalla:BAAALAADCgMIAwABLAAECggIGgANACUeAA==.Fera:BAABLAAECoEcAAIDAAgIXiGWDQD8AgADAAgIXiGWDQD8AgAAAA==.Feraldruíd:BAAALAAECgYIBwAAAA==.',Fi='Fiddlesworth:BAAALAAECgYIDwAAAA==.Filo:BAAALAAECgYIDwAAAA==.Firebrand:BAABLAAECoEWAAMEAAgI9SCRDAACAwAEAAgI9SCRDAACAwAOAAcIcBLxFABwAQAAAA==.',Fl='Flaggermus:BAABLAAECoEXAAMPAAgITh0BDgDHAgAPAAgITh0BDgDHAgAQAAMIgwgUkwBsAAAAAA==.',Fr='Frackson:BAAALAAECgQIBgAAAA==.Freakzie:BAAALAAECgUIDQAAAA==.Fregar:BAAALAADCgIIAgAAAA==.Frickintusks:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Frostching:BAAALAAECgcIEgAAAA==.Frëyä:BAAALAADCgIIAgAAAA==.',Fu='Futhark:BAAALAAECgcIEAAAAA==.',Ga='Gagic:BAAALAADCgYICgAAAA==.Galder:BAAALAAECgQIBAAAAA==.Ganeshá:BAAALAADCgQIBAAAAA==.Ganmcdaddy:BAAALAADCgYIBgAAAA==.',Gi='Gilal:BAAALAADCgcIBwAAAA==.',Gn='Gnd:BAAALAAECgcIBwAAAA==.Gnetp:BAAALAAECgYIBgAAAA==.',Go='Gotrek:BAAALAAECgYIDwAAAA==.',Gr='Gralf:BAAALAADCggICAAAAA==.Groge:BAABLAAECoEUAAICAAcILRVnIgDiAQACAAcILRVnIgDiAQAAAA==.',Gu='Guts:BAAALAAECgYIBgAAAA==.',Ha='Haqua:BAAALAADCggICAAAAA==.Haya:BAAALAADCggICAAAAA==.',He='Heisman:BAAALAADCgIIAgAAAA==.Heligagudrun:BAAALAAECgQIBgAAAA==.',Hi='Hilyna:BAAALAADCggIFQABLAAFFAIIAgABAAAAAA==.',Hj='Hjørdiss:BAABLAAECoEXAAQKAAcICBKLIQCRAQAKAAYI8BGLIQCRAQAIAAUIhxDVUgAlAQALAAMIgAsZHgCrAAAAAA==.',Ho='Hork:BAABLAAECoEXAAIRAAcI0RzTMAATAgARAAcI0RzTMAATAgAAAA==.Hornette:BAAALAADCggIFwABLAAECgYIDwABAAAAAA==.Houdin:BAAALAADCggICAAAAA==.',Hu='Hunterbadger:BAAALAAECgEIAQAAAA==.',['Hà']='Hàmstern:BAACLAAFFIEFAAISAAMIGRRWAgDsAAASAAMIGRRWAgDsAAAsAAQKgR4AAhIACAhAICQEANkCABIACAhAICQEANkCAAAA.',['Hâ']='Hâmstern:BAAALAADCggICAAAAA==.',['Hä']='Härkäpapu:BAABLAAECoEVAAMPAAcI3g16LgC2AQAPAAcI3g16LgC2AQAQAAYIXBXqQQBzAQAAAA==.',Ig='Ig:BAAALAAECgMIBQAAAA==.Igumeemi:BAAALAAECgMIAwAAAA==.',Ih='Ihananirstas:BAABLAAECoEYAAIQAAYIpBmZOACaAQAQAAYIpBmZOACaAQAAAA==.',Ik='Ikbenmarc:BAAALAADCgEIAQAAAA==.',In='Iniqa:BAAALAADCgcIBwAAAA==.',Ip='Ipokestuff:BAABLAAECoEXAAIMAAcIqRzjDABFAgAMAAcIqRzjDABFAgAAAA==.',Ir='Ira:BAABLAAECoEXAAISAAcI8BilCwDrAQASAAcI8BilCwDrAQAAAA==.Irlin:BAAALAADCggICAAAAA==.',Is='Iskaldpmax:BAAALAAECggIDAAAAA==.',It='Iterax:BAAALAAECgQICgAAAA==.',Ja='Jaegern:BAAALAADCgEIAQAAAA==.Jamikettu:BAABLAAECoEVAAITAAcIAxnuAwA2AgATAAcIAxnuAwA2AgAAAA==.',Je='Jel:BAAALAAECgMIAwABLAAFFAMIBQAIAK0jAA==.Jelo:BAACLAAFFIEFAAIIAAMIrSNTBQA1AQAIAAMIrSNTBQA1AQAsAAQKgR0AAwgACAjVJUACAGUDAAgACAjVJUACAGUDAAoABAgxIIssAFMBAAAA.Jemeni:BAAALAADCgYIBgAAAA==.',Jo='Joep:BAAALAAECgUICAAAAA==.Jompatorman:BAAALAADCgcIDQAAAA==.Joél:BAAALAAECgcIDQAAAA==.',Ju='Juken:BAAALAADCgQIBAAAAA==.Justtryme:BAAALAAECgIIAgAAAA==.',Ka='Kadabri:BAAALAAECgMIAwAAAA==.Kafolul:BAABLAAECoEeAAQUAAgIIhJEEgD6AQAUAAgIIhJEEgD6AQADAAcIMhbdRwC6AQAJAAEIHAqgOgApAAAAAA==.Kaidor:BAABLAAECoEYAAMVAAcINhauFgD6AQAVAAcINhauFgD6AQAWAAEIQwBPJwADAAABLAADCgcIDQABAAAAAA==.Kaikanori:BAAALAAECgIIAQAAAA==.Kalcadal:BAABLAAECoEcAAIGAAgI3RzcDwC4AgAGAAgI3RzcDwC4AgAAAA==.Kassei:BAAALAADCgcIBwAAAA==.Kaura:BAABLAAECoEYAAIXAAgIDCB6CgDyAgAXAAgIDCB6CgDyAgAAAA==.',Ke='Kepabbi:BAAALAADCgcIBwAAAA==.Kevlilc:BAAALAAECgMIAgAAAA==.',Ki='Kives:BAAALAADCgcIBwABLAAECgcIFQAOALEeAA==.',Kl='Kladdiz:BAABLAAECoEeAAMKAAgISCZQAACFAwAKAAgISCZQAACFAwAIAAEInwPhkQAjAAAAAA==.',Kn='Kneli:BAAALAADCggICAAAAA==.',Ko='Kodie:BAAALAADCggICAAAAA==.Korvvex:BAABLAAECoEXAAIYAAcIXh73EwBIAgAYAAcIXh73EwBIAgAAAA==.',Ku='Kullivelho:BAABLAAECoEXAAIFAAcIVxI9RwCeAQAFAAcIVxI9RwCeAQAAAA==.Kulutusmaito:BAAALAADCgIIAgAAAA==.Kuskokvint:BAAALAAECgcIDAAAAA==.',Ky='Kyinth:BAAALAAECgMIAwAAAA==.Kylar:BAAALAAECgcICQAAAA==.',La='Laawry:BAAALAAECgUIBQAAAA==.Laishetkhez:BAAALAADCgcICwAAAA==.Larslilholt:BAAALAADCgIIAQAAAA==.',Le='Ledeux:BAAALAADCggIDQABLAAECgcIFAAFALohAA==.Leetopissa:BAAALAAECgcIDwAAAA==.Legowish:BAAALAAECgcIDQAAAA==.Lehuit:BAABLAAECoEUAAIFAAcIuiErHQB6AgAFAAcIuiErHQB6AgAAAA==.',Li='Libster:BAAALAAECgcIBwAAAA==.',Ll='Llaneria:BAAALAAECgcIDgAAAA==.Lliira:BAAALAADCgcIBwAAAA==.',Lo='Loganglaives:BAAALAADCgcIAgAAAA==.Lohilo:BAAALAADCgYIBgAAAA==.Lookz:BAAALAAECggIDAAAAA==.Lothe:BAAALAADCggICAAAAA==.Louis:BAAALAADCgEIAQAAAA==.Lovefist:BAAALAADCgYIBgAAAA==.Lowping:BAAALAADCggICAAAAA==.',Ma='Maffers:BAAALAAECgYIDwAAAA==.Mafférs:BAAALAADCgUIBQAAAA==.Maivi:BAAALAADCgIIAgABLAAECggICAABAAAAAA==.Maksamakkara:BAAALAADCgcIDAAAAA==.Mangoiröven:BAAALAAECgQIBAABLAAECgYICQABAAAAAA==.Mangoprinse:BAAALAAECgQIBQAAAA==.',Me='Meadbrew:BAAALAADCgcIDAAAAA==.Mega:BAAALAAECgYIBgAAAA==.Metalslug:BAAALAAECgYIDgAAAA==.',Mf='Mfahrenheit:BAAALAADCgIIAgAAAA==.',Mg='Mgn:BAAALAAECgEIAgAAAA==.',Mi='Mightyteus:BAAALAAECggICwAAAA==.Miimi:BAAALAAECgcIDAAAAA==.Mikah:BAAALAAECgcIDwAAAA==.Milmadia:BAAALAADCgIIAgAAAA==.Mindflay:BAAALAADCggICAAAAA==.Minsela:BAAALAAECgEIAQAAAA==.Missasstress:BAABLAAECoEUAAIXAAcI5xiYJQAKAgAXAAcI5xiYJQAKAgAAAA==.',Mo='Moccamaster:BAAALAAECgMIAwAAAA==.Mocha:BAAALAAECgcIEwAAAA==.Moh:BAAALAADCggIEAAAAA==.Moltitude:BAAALAAECgMIAwAAAA==.Monka:BAAALAADCgIIAgAAAA==.Moontu:BAAALAAECgYIDAAAAA==.Morso:BAAALAADCggICAAAAA==.Motueka:BAAALAADCggICAAAAA==.',Mu='Munkeren:BAAALAAECgUIBQAAAA==.',My='Myrahk:BAAALAADCggIDAAAAA==.',['Mö']='Mölli:BAAALAAECgcIEwAAAA==.',Na='Nahasiel:BAAALAADCggIDQAAAA==.Nanao:BAAALAAECgYIBgAAAA==.Nangus:BAAALAAECgMIBAAAAA==.',Ne='Neethor:BAABLAAECoEaAAIZAAcIkx8LCAB2AgAZAAcIkx8LCAB2AgAAAA==.Neitor:BAAALAAECgQIBgAAAA==.',Nh='Nhil:BAABLAAECoEXAAMKAAcIlgVHKABqAQAKAAcIlgVHKABqAQAIAAIIHQQdiwA1AAAAAA==.',Ni='Nienkê:BAAALAADCgcIBwAAAA==.Ninjagaiden:BAAALAADCggIDAAAAA==.',No='Nocturnal:BAAALAAECgYICgAAAA==.Nofco:BAABLAAECoEeAAIEAAgIBSLXDgDuAgAEAAgIBSLXDgDuAgAAAA==.Nordbol:BAAALAADCggIEAAAAA==.Novelle:BAAALAADCgMIAwAAAA==.Noxxslaya:BAAALAADCggIEAAAAA==.',Nu='Nugah:BAAALAADCggICAAAAA==.',Ny='Nyella:BAAALAADCggICAAAAA==.Nyssara:BAAALAAECgYICQAAAA==.',['Nì']='Nìaz:BAAALAAECgYIEgAAAA==.',Oh='Ohrapirtelö:BAAALAADCgcIBwAAAA==.',Oj='Ojas:BAABLAAECoEWAAIFAAcIvxZ4NADyAQAFAAcIvxZ4NADyAQAAAA==.',On='Onixia:BAABLAAECoEaAAINAAgIJR6fCwC0AgANAAgIJR6fCwC0AgAAAA==.',Oo='Oofie:BAAALAADCggICQABLAAECggIGAANABsMAA==.',Pa='Paddydk:BAAALAADCgYIBgABLAAECgQIBgABAAAAAA==.Parx:BAAALAAECgcIDgAAAA==.Pattepala:BAAALAADCggIDwAAAA==.Pawnpusher:BAAALAAECgQIBQAAAA==.Pawpatine:BAAALAAECgUIBQAAAA==.Pawweaver:BAABLAAECoEXAAIaAAcIwBz+CQBNAgAaAAcIwBz+CQBNAgAAAA==.',Pe='Pekonisoturi:BAAALAAECgMIBAAAAA==.Pencil:BAAALAAECggICAAAAA==.Pestoration:BAAALAADCggIDwAAAA==.',Pi='Pii:BAAALAAECgcIEwAAAA==.Pikkuhukka:BAABLAAECoEYAAIbAAgIBRgODwBsAgAbAAgIBRgODwBsAgAAAA==.Pippipil:BAAALAADCgcIBwAAAA==.Pirikaisa:BAAALAADCgIIAgABLAAECgYIEwABAAAAAA==.Pirilissu:BAAALAAECgMIAwABLAAECgYIEwABAAAAAA==.Piripipsa:BAAALAAECgYIEwAAAA==.Piritapsa:BAAALAADCgcICwABLAAECgYIEwABAAAAAA==.Pirituula:BAAALAADCggICgABLAAECgYIEwABAAAAAA==.',Pj='Pjaske:BAAALAAECgIIAgAAAA==.',Po='Pollylock:BAAALAAECgMIAQAAAA==.Possumunkki:BAAALAADCgIIAgAAAA==.Poxkajka:BAAALAADCggICAABLAAECgYICQABAAAAAA==.',Pr='Prognosis:BAAALAAECgEIAQAAAA==.',Ps='Psyblade:BAAALAAECgMIBgAAAA==.Psykomayn:BAAALAADCgcIBwAAAA==.',['Pö']='Pörssisähkö:BAAALAAECgMIAwAAAA==.',Qo='Qonkeygong:BAAALAAECgcICQAAAA==.',Qu='Quicknut:BAAALAADCgYIBgAAAA==.',Ra='Rauk:BAAALAAFFAIIBAAAAA==.',Re='Redassain:BAAALAADCgYIBgAAAA==.Reketråla:BAAALAADCgYIBgAAAA==.Reloca:BAAALAADCggIEgAAAA==.Rendiros:BAAALAAECgcIDQAAAA==.',Rh='Rhalaz:BAAALAADCggIGAAAAA==.Rhinoo:BAAALAAECgEIAQAAAA==.',Ro='Roarikzo:BAAALAADCgUIBQAAAA==.Robsmash:BAAALAAECgcIEQAAAA==.Rocknroll:BAAALAADCggIDwAAAA==.Roctar:BAAALAADCggIAwAAAA==.Roxinrajh:BAAALAADCgYIBgAAAA==.',Ru='Ruby:BAAALAAECgUIBAAAAA==.',['Rö']='Rödamördarn:BAAALAADCgYIBgAAAA==.',Sa='Samdi:BAAALAADCggIDwAAAA==.Satsudd:BAAALAAECgcICQAAAA==.Sauedum:BAAALAAECgYIBgAAAA==.Savia:BAAALAAECgcIEQAAAA==.Saxi:BAABLAAECoEXAAIcAAcIQB0pFQAqAgAcAAcIQB0pFQAqAgAAAA==.',Se='Senyn:BAAALAAECgUIBQABLAAFFAIIAgABAAAAAA==.',Sh='Shakenator:BAAALAAECgYIBgAAAA==.Shakez:BAABLAAECoEWAAIXAAgIBSEZCgD2AgAXAAgIBSEZCgD2AgAAAA==.Shamuss:BAAALAAECgEIAQAAAA==.Shapeshiftz:BAAALAAECgIIAgAAAA==.Sharapriest:BAAALAAFFAIIAwAAAA==.Sharawalker:BAAALAAECgYIBgAAAA==.Sharawalkers:BAAALAAFFAIIAgAAAA==.Sheivaaja:BAABLAAECoEWAAIRAAcIJRyUNQD/AQARAAcIJRyUNQD/AQAAAA==.Shirel:BAAALAADCggICAAAAA==.Shooker:BAAALAADCggIHQAAAA==.Shàbbìs:BAAALAADCgcIBwAAAA==.Shíela:BAAALAADCgUIBQABLAAECgYIDwABAAAAAA==.',Si='Siseras:BAAALAAECgYIBgABLAAECgYIBgABAAAAAA==.Sistersage:BAAALAADCggICAAAAA==.',Sk='Skullsplitt:BAAALAAECgYICwAAAA==.',So='Soeyy:BAAALAAECgYIEAAAAA==.Sofô:BAAALAAFFAEIAQAAAA==.',Sp='Spegodin:BAAALAADCggICgAAAA==.',St='Stargeezer:BAAALAADCgIIAgAAAA==.Starvild:BAAALAAECgMIAwAAAA==.',Su='Sushihukka:BAAALAADCggIDwAAAA==.',Sv='Svinfejja:BAABLAAECoEdAAMcAAgIJCRgAgAnAwAcAAgIJCRgAgAnAwAYAAUIXgwGPAAbAQAAAA==.',Sy='Syanna:BAABLAAECoEaAAMKAAcILiGXBgCZAgAKAAcILiGXBgCZAgAIAAII3A4OegBsAAAAAA==.',Ta='Tallgrogu:BAAALAADCgcIDQAAAA==.Tamac:BAAALAAECgYIBgAAAA==.Tameera:BAAALAAECgYICQAAAA==.Tamonten:BAABLAAECoEaAAIGAAcIPxANLQC/AQAGAAcIPxANLQC/AQAAAA==.Tamryssa:BAAALAAECgMIAwAAAA==.Tamtheone:BAAALAADCgYIBwAAAA==.Tardi:BAAALAAFFAIIAgABLAAECgcIDgABAAAAAA==.',Te='Tear:BAAALAAECgIIAwAAAA==.Teeus:BAAALAADCggICAAAAA==.Ten:BAAALAADCggIEAAAAA==.',Th='Thaelstrasz:BAABLAAECoEXAAIWAAcIExgjCgD3AQAWAAcIExgjCgD3AQAAAA==.Thaeras:BAAALAAECgEIAQAAAA==.Thehandyman:BAAALAADCgUIBQAAAA==.Thémistocles:BAAALAAECgEIAQAAAA==.',Ti='Tides:BAACLAAFFIEFAAIQAAMIqxxSAwAYAQAQAAMIqxxSAwAYAQAsAAQKgR4AAhAACAg5IwgDAB4DABAACAg5IwgDAB4DAAAA.',To='Tohubohu:BAAALAADCgUIBQAAAA==.Toolbar:BAAALAADCgcIBwAAAA==.Torham:BAAALAAECgYIBgAAAA==.Tormenting:BAAALAAECgcIEAAAAA==.',Tr='Treicy:BAAALAADCggICAAAAA==.Trelli:BAABLAAECoEWAAIGAAgIDgV+SgAQAQAGAAgIDgV+SgAQAQAAAA==.Troz:BAAALAAECgYIBgAAAA==.Truk:BAAALAADCggICAAAAA==.',Tu='Tuhtinatar:BAAALAADCgcICQAAAA==.Tulloa:BAAALAAECgYIDgAAAA==.Turgön:BAAALAAECgcIDwAAAA==.',Tz='Tzameh:BAAALAADCggICAAAAA==.',['Tä']='Tärätänkö:BAABLAAECoEZAAMdAAgIFBsRBAAtAgANAAgIZRYUGAA7AgAdAAcICRoRBAAtAgAAAA==.',Ul='Ultear:BAAALAAECgYICAAAAA==.',Ur='Ursula:BAAALAAECgYIBQABLAAECgcIDwABAAAAAA==.',Ut='Utop:BAAALAAECggICAAAAA==.',Va='Vadårårå:BAAALAAECgYIBgAAAA==.Vajdh:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Valhalla:BAAALAAECgIIAgAAAA==.Vanilje:BAABLAAECoEUAAIeAAcIlBUmFwDfAQAeAAcIlBUmFwDfAQAAAA==.Varuz:BAAALAADCgUIBwAAAA==.',Ve='Velhomo:BAAALAADCggIEAAAAA==.',Vi='Vildasst:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Vildast:BAAALAADCgEIAQABLAAECgMIAwABAAAAAA==.Vixoniac:BAAALAADCgMIAwAAAA==.',Vl='Vliegendekoe:BAAALAADCggICAAAAA==.',Vo='Voidbunny:BAAALAADCgcIDAAAAA==.Voiddaddie:BAAALAADCgcICwAAAA==.',Vr='Vroma:BAAALAADCgIIAgABLAAECggIFgAGAA4FAA==.Vruk:BAAALAADCgUIBQAAAA==.',Wa='Wagyubeef:BAAALAAECgIIAgAAAA==.Wargira:BAAALAAECgUICwAAAA==.Warsire:BAAALAAECgQIBQAAAA==.',We='Weierstrasza:BAAALAAECgcIDQAAAA==.',Wi='Wingflaps:BAAALAAECgcIBwAAAA==.Wirin:BAAALAAECgQIBAAAAA==.',Wo='Wokeahontas:BAAALAAECgMIBwAAAA==.Workh:BAAALAAECgEIAQAAAA==.',Wr='Wret:BAAALAAECgYIDwAAAA==.',Wu='Wuman:BAAALAADCgcICgAAAA==.',Xa='Xagen:BAAALAAECgYICgABLAAFFAIIBAABAAAAAA==.Xagorr:BAAALAAFFAIIBAAAAA==.Xauman:BAAALAADCgEIAQAAAA==.',Xi='Xiili:BAAALAADCgYIBgAAAA==.Xizylol:BAAALAAECgcICQAAAA==.',Xm='Xmasster:BAAALAADCgQIBAAAAA==.',Xo='Xorezp:BAAALAAECgUIBQAAAA==.',['Xé']='Xéz:BAAALAAECgYIDAAAAA==.',Ya='Yawgmoth:BAABLAAECoEUAAIIAAYIahGPRQBdAQAIAAYIahGPRQBdAQAAAA==.',Za='Zalbezal:BAABLAAECoEXAAIPAAcIvhz8GABLAgAPAAcIvhz8GABLAgAAAA==.Zaruuna:BAAALAAECgMIAwAAAA==.Zaungoth:BAAALAADCgcIBwAAAA==.Zaïnt:BAAALAAECgYICAAAAA==.',Ze='Zealia:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.Zenzei:BAAALAADCggICAAAAA==.Zetaprime:BAAALAAECgMIBwAAAA==.',Zi='Zinil:BAABLAAECoEXAAIIAAcIbBBUNQCoAQAIAAcIbBBUNQCoAQAAAA==.Zinkö:BAABLAAECoEYAAIGAAgITRbMGABWAgAGAAgITRbMGABWAgAAAA==.Zinstict:BAAALAAECgYICgAAAA==.',Zu='Zucchini:BAAALAAECgYIBgAAAA==.',Zv='Zvezda:BAABLAAECoEbAAIfAAgIFSLLAAAvAwAfAAgIFSLLAAAvAwAAAA==.',['Âg']='Âgreë:BAAALAAECgMIBwAAAA==.',['Âm']='Âmeth:BAAALAAFFAIIAgAAAA==.',['Ân']='Ânanas:BAABLAAECoEVAAIOAAcIsR5QBwBnAgAOAAcIsR5QBwBnAgAAAA==.',['Äg']='Äggmil:BAAALAADCggICAAAAA==.',['Æm']='Æmûn:BAAALAAECgcIDQAAAA==.',['Én']='Éner:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end