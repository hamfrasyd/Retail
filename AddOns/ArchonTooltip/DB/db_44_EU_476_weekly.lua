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
 local lookup = {'Paladin-Retribution','DeathKnight-Blood','Priest-Shadow','DeathKnight-Frost','Hunter-Survival','Mage-Frost','Mage-Arcane','Warlock-Demonology','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Paladin-Protection','Warrior-Arms','Druid-Restoration','Evoker-Augmentation','Warlock-Destruction','Warlock-Affliction','DeathKnight-Unholy','Evoker-Devastation','Monk-Mistweaver','Evoker-Preservation','Druid-Feral','DemonHunter-Vengeance','Priest-Holy','Monk-Windwalker','Rogue-Assassination','Druid-Balance','Warrior-Fury','Rogue-Outlaw','Mage-Fire','Warrior-Protection','Shaman-Enhancement','DemonHunter-Havoc',}; local provider = {region='EU',realm='Wrathbringer',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ae='Aerianda:BAAALAAECggICAAAAA==.Aerion:BAAALAAECgYIDQAAAA==.',Ak='Aki:BAAALAADCgMIAwAAAA==.',Al='Alakaja:BAAALAAECgcIEQAAAA==.Alyrià:BAABLAAECoEhAAIBAAgIGCBSHQDgAgABAAgIGCBSHQDgAgAAAA==.Alyrus:BAABLAAECoEiAAICAAgIjiRXAgBPAwACAAgIjiRXAgBPAwAAAA==.Alysrêa:BAABLAAECoEfAAIDAAcI4xDAOwCvAQADAAcI4xDAOwCvAQAAAA==.Alyu:BAAALAADCgIIAgAAAA==.',Am='Amaterasû:BAAALAAECgcIDgAAAA==.Amylynn:BAAALAAECgYIBgAAAA==.',An='Anaco:BAAALAADCgEIAQAAAA==.Anydia:BAAALAAECgIIAgAAAA==.',Ar='Arathak:BAABLAAECoEYAAIEAAcIphRNcgDcAQAEAAcIphRNcgDcAQAAAA==.Arrgus:BAAALAADCggIBwAAAA==.Aryasa:BAAALAAECgIIAgAAAA==.',As='Aspekt:BAAALAAECgcICwABLAAECggIFgADAAMYAA==.Astrâ:BAAALAAECgYICAAAAA==.',Av='Avalia:BAAALAAECgMIAwAAAA==.Avarie:BAABLAAECoEYAAIBAAYIGgRH8gDZAAABAAYIGgRH8gDZAAAAAA==.',Ay='Ayamy:BAABLAAECoEgAAIFAAcIyCPQBQBTAgAFAAcIyCPQBQBTAgAAAA==.',Az='Azlag:BAAALAADCgIIAgAAAA==.',['Aß']='Aßindia:BAABLAAECoEdAAMGAAgIGCBsCgDZAgAGAAgIGCBsCgDZAgAHAAEIrwzX2QBBAAAAAA==.',Ba='Babutcha:BAABLAAECoEbAAIIAAcIOQ65KQCtAQAIAAcIOQ65KQCtAQAAAA==.Barfuß:BAABLAAECoEgAAIJAAgIhgjnfAD7AAAJAAgIhgjnfAD7AAAAAA==.Barryy:BAABLAAECoEfAAIKAAgIYBbAFwAlAgAKAAgIYBbAFwAlAgAAAA==.Bayernetta:BAAALAADCgcIBwABLAAECgIIAgALAAAAAA==.',Be='Beradox:BAACLAAFFIERAAMMAAUIriJKCQB7AQAMAAQIKyNKCQB7AQANAAMI/xz4DADgAAAsAAQKgTEAAwwACAj4JaYVAOICAAwABwjUJaYVAOICAA0ACAhiIWsPANsCAAAA.Berri:BAAALAADCggICAAAAA==.',Bi='Bibalicious:BAAALAADCggICQAAAA==.Bienenstich:BAAALAAECgYIDgAAAA==.',Bl='Blootgeil:BAABLAAECoEXAAMOAAgI2Ra5NgAWAgAOAAgI2Ra5NgAWAgAJAAIIvQZRogBTAAAAAA==.Blutvente:BAAALAADCgQIBAAAAA==.Blóodbée:BAAALAAECgUIEQAAAA==.',Bo='Bondagé:BAAALAAECgMIAwAAAA==.',Br='Braragas:BAAALAAECgUICAAAAA==.Brokah:BAABLAAECoEZAAIPAAcIABK4JwCDAQAPAAcIABK4JwCDAQAAAA==.Brotbüchse:BAAALAAECggICgAAAA==.',Bu='Buffme:BAAALAADCgYIBgABLAAECggIIwAQANQjAA==.Bullentussy:BAABLAAECoEWAAIRAAYIPxexUgBhAQARAAYIPxexUgBhAQAAAA==.',['Bø']='Bødhî:BAAALAADCggIDwAAAA==.',Ce='Cenari:BAAALAADCgYIBgAAAA==.',Ch='Chêrry:BAAALAAECgIIAgAAAA==.Chô:BAAALAADCggIFgABLAAFFAUIEQASAHEPAA==.',Ci='Cijandri:BAAALAAECgQIBwAAAA==.',Cl='Cleylock:BAABLAAECoEWAAMTAAgIwxcuMwBCAgATAAgIwxcuMwBCAgAUAAIIHhEhLQBvAAAAAA==.',Cr='Crankskyline:BAAALAAECgcIBgAAAA==.Creetz:BAAALAAECgYIBgAAAA==.',Cu='Cutyu:BAAALAADCggIEQAAAA==.',Da='Darkbanshee:BAAALAADCgUIBQAAAA==.Darkgaiá:BAAALAADCggICwAAAA==.Darona:BAABLAAECoEWAAIHAAYIMAq1jwBAAQAHAAYIMAq1jwBAAQAAAA==.Darthreaper:BAACLAAFFIERAAMVAAUIJRuWAQB/AQAVAAQILB2WAQB/AQAEAAMIZRZvGgDkAAAsAAQKgS8AAxUACAjaJDoGAOkCABUACAjaJDoGAOkCAAQABwjQHABJAD0CAAAA.Darthvicious:BAAALAAECgcICgAAAA==.Daydoron:BAABLAAECoEYAAIRAAcIiR39HgBMAgARAAcIiR39HgBMAgAAAA==.Daydreamer:BAAALAADCggIHQAAAA==.',De='Deathnote:BAAALAADCggICgAAAA==.Dejoule:BAAALAADCgUIBQABLAADCgYIBgALAAAAAA==.Deka:BAAALAAECgMIAwAAAA==.Demonmuh:BAAALAAECgQIBAAAAA==.Devilgoth:BAAALAADCggIDAAAAA==.',Di='Dirune:BAABLAAECoEaAAIEAAcIZhuHXwAEAgAEAAcIZhuHXwAEAgAAAA==.Discorufer:BAAALAAECgUIBQAAAA==.',Dj='Djandoxd:BAABLAAECoEfAAIWAAgIQxsJEwCAAgAWAAgIQxsJEwCAAgAAAA==.',Do='Dontworry:BAAALAADCggICgAAAA==.Dornenblumé:BAABLAAECoEVAAIIAAcIMA80KgCrAQAIAAcIMA80KgCrAQAAAA==.',Dr='Dreamfyre:BAAALAADCggIDwAAAA==.',Dz='Dzibrill:BAAALAADCgMIAwAAAA==.',Ed='Edone:BAAALAADCggIEwAAAA==.',Ek='Ekolten:BAAALAAECgUICAAAAA==.',Em='Emdru:BAAALAADCggIIQAAAA==.',En='Ente:BAAALAADCgcIBwAAAA==.',Eo='Eotrin:BAABLAAECoEcAAIXAAcIaA3nJQBBAQAXAAcIaA3nJQBBAQAAAA==.',Er='Erandur:BAAALAADCggIFQAAAA==.Erea:BAAALAAECgEIAQAAAA==.',Et='Etherna:BAAALAAECgEIAQAAAA==.',Ex='Exardin:BAAALAAECgYIDAAAAA==.',Fe='Feazz:BAABLAAECoEhAAMGAAcIxRpDJQDVAQAHAAcIrRiQSgAHAgAGAAYIPh1DJQDVAQAAAA==.Feddora:BAAALAAECgcIEgAAAA==.',Fl='Flames:BAAALAAECgMIAwABLAAECggIJAABAA0lAA==.Flippie:BAACLAAFFIEMAAIWAAUITB/tAwDVAQAWAAUITB/tAwDVAQAsAAQKgSwAAxYACAjmJQkCAGcDABYACAjmJQkCAGcDABgABgikJOoZAHQBAAAA.',Fr='Fraumerkel:BAAALAADCggICwAAAA==.Fritzelbritz:BAAALAADCgMIAwAAAA==.Fränni:BAAALAADCggICAAAAA==.Frêyá:BAAALAADCgMICAAAAA==.',Fu='Fumor:BAABLAAECoEeAAIJAAgIYyE6EwDiAgAJAAgIYyE6EwDiAgAAAA==.Furysch:BAAALAAECggICwAAAA==.',['Fê']='Fênnek:BAAALAADCggIEgAAAA==.',Ga='Galore:BAAALAAECgcIDAAAAA==.',Ge='Gelidá:BAAALAAECgIIAgAAAA==.Gelin:BAAALAADCggIEQAAAA==.Gerudio:BAAALAAFFAEIAQAAAA==.',Gh='Ghoststalk:BAAALAAECgEIAQAAAA==.',Go='Goodfellass:BAAALAAECgYIDAAAAA==.Gorgh:BAAALAADCgIIAgAAAA==.',Gr='Grimwald:BAABLAAECoEkAAIBAAgIDSXyDQAzAwABAAgIDSXyDQAzAwAAAA==.Grusélla:BAABLAAECoEYAAMKAAcIxQckPgAtAQAKAAcIxQckPgAtAQABAAYIigNW8wDWAAAAAA==.',Gu='Guilty:BAAALAAECggIEAAAAA==.Gurkenglas:BAAALAAECgcIBwABLAAECggIFwAUAAAjAA==.',['Gà']='Gàruda:BAABLAAECoEiAAMJAAcIcBbQNgADAgAJAAcIcBbQNgADAgAOAAcIbRiKRgDhAQAAAA==.',Ha='Hagebuddne:BAAALAAECgMIBAAAAA==.Halyrius:BAAALAAECgEIAQAAAA==.Hanah:BAABLAAECoEhAAIZAAgI6SNkBAARAwAZAAgI6SNkBAARAwAAAA==.Hannya:BAABLAAECoEeAAIaAAcI3B+XGADOAQAaAAcI3B+XGADOAQAAAA==.Harrogath:BAAALAAECggIEAAAAA==.',He='Hegamurl:BAABLAAECoEWAAMDAAgIAxhSIABSAgADAAgIAxhSIABSAgAbAAEIAgzZogA2AAAAAA==.Heisor:BAAALAAECgcIEwAAAA==.Hellothere:BAACLAAFFIEKAAIRAAUILxfTBACWAQARAAUILxfTBACWAQAsAAQKgSgAAhEACAg5I7wGABYDABEACAg5I7wGABYDAAAA.Heule:BAAALAADCgYIBgAAAA==.Hexhunter:BAAALAAECgYICgAAAA==.',Hj='Hjacker:BAABLAAECoEVAAIRAAcIgxoEKAAZAgARAAcIgxoEKAAZAgAAAA==.',Ho='Hollythecow:BAAALAADCgQIBAABLAAECgcIHgAMAAUTAA==.',Hu='Huntjinn:BAABLAAECoEUAAQFAAgI/B7VBAB7AgAFAAgIqB3VBAB7AgANAAgIJxbGOQC6AQAMAAIIFRmy+QBpAAABLAAFFAMICQAKAOMLAA==.',['Hâ']='Hâppy:BAAALAADCggIBwAAAA==.',Ic='Ichabod:BAAALAADCgQIAwAAAA==.Ichthys:BAAALAAECgYIDAAAAA==.Icomeinpeace:BAAALAAECgIIAgAAAA==.',If='Iflameyou:BAAALAADCgUIBQAAAA==.',In='Innidovil:BAAALAAECggICAAAAA==.',Iv='Iveri:BAAALAADCgcIDAAAAA==.Iviry:BAAALAADCgcIDQABLAAFFAIIBgABAPwQAA==.Ivyre:BAAALAAECgYICAAAAA==.',Iw='Iwire:BAACLAAFFIEGAAIBAAII/BDcLQCfAAABAAII/BDcLQCfAAAsAAQKgRkAAgEABwivHhhTABsCAAEABwivHhhTABsCAAAA.',Ja='Jackburst:BAAALAAFFAIIAgAAAA==.Jarlaxle:BAAALAAECgIIBgAAAA==.',Je='Jenova:BAAALAADCgEIAQABLAAECggIHQAVAC8cAA==.',Ju='Jukpew:BAAALAAECgMIBAABLAAECgcIGAAMABIdAA==.',['Jü']='Jükü:BAABLAAECoEYAAIMAAcIEh3TRgALAgAMAAcIEh3TRgALAgAAAA==.',Ka='Kaeæs:BAAALAADCggICAABLAAECgUIBQALAAAAAA==.Kalita:BAABLAAECoEXAAIDAAcIBgpJSQBvAQADAAcIBgpJSQBvAQAAAA==.Kazuko:BAAALAAECgUIBwAAAA==.',Ke='Keinhorn:BAAALAAECgcIEQAAAA==.Kesuke:BAAALAADCgcIBwAAAA==.',Kf='Kfaro:BAAALAADCgUIBgAAAA==.',Kh='Khamûl:BAAALAADCgcICAAAAA==.Khorash:BAABLAAECoEcAAMOAAgIVh4jIAByAgAOAAgIVh4jIAByAgAJAAEIkgNwsgApAAAAAA==.',Ki='Kiomá:BAAALAAECgYICgAAAA==.',Kl='Klatschmuh:BAAALAAECgMIBAAAAA==.',Ko='Koedoron:BAAALAADCggICAAAAA==.',Kr='Kraftbrühe:BAAALAAECggIEwAAAA==.Kraxor:BAAALAADCgUIBQABLAAECgcIHgAMAM0hAA==.Kryptal:BAAALAAECgYIBgAAAA==.',Ky='Kyiel:BAAALAAECgIIAwAAAA==.Kyira:BAABLAAECoEwAAIBAAgIFiELHADnAgABAAgIFiELHADnAgAAAA==.',La='Lahmus:BAAALAAECgEIAQAAAA==.Lassmieranda:BAAALAAECggIDwAAAA==.Laysi:BAAALAADCggICAAAAA==.Lazarussign:BAAALAADCggICwAAAA==.',Le='Leafblower:BAAALAADCggIDQABLAAECggIFwAUAAAjAA==.Leanois:BAAALAADCggICwAAAA==.Legit:BAAALAADCgcIBwAAAA==.Levia:BAAALAAECgcICgAAAA==.',Lh='Lhihunter:BAABLAAECoEXAAIMAAcIaBHxewCGAQAMAAcIaBHxewCGAQAAAA==.',Li='Liyaa:BAABLAAECoEqAAIcAAgIBBLdHQDiAQAcAAgIBBLdHQDiAQAAAA==.Liyanne:BAABLAAECoEXAAMJAAgIvQrSYABkAQAJAAcIlgjSYABkAQAOAAQIOQS08ABmAAAAAA==.',Lo='Lolô:BAAALAAECgYIDwAAAA==.Lorox:BAABLAAECoEVAAMTAAcItAqQbwBxAQATAAcItAqQbwBxAQAIAAIIuQXMfABOAAAAAA==.',Lu='Lunéx:BAABLAAECoEgAAMXAAgIdyH2BQDwAgAXAAgIdyH2BQDwAgAcAAEICwyLVwA8AAAAAA==.Luxpacis:BAAALAAECgYICAAAAA==.',['Lí']='Líthara:BAAALAADCggIDAAAAA==.',Ma='Madly:BAAALAAECgYIBgAAAA==.Madwac:BAABLAAECoEiAAIJAAcI2RY+OgDzAQAJAAcI2RY+OgDzAQAAAA==.Maldera:BAAALAADCgYIBgABLAAECgEIAQALAAAAAA==.Marignano:BAAALAAECgIIAgAAAA==.Maxisback:BAAALAADCgYIBgAAAA==.',Mb='Mbappé:BAAALAAECgYIBgAAAA==.',Me='Meer:BAAALAAECggICAAAAA==.Meistêr:BAAALAAECgEIAgAAAA==.',Mi='Mike:BAABLAAECoEgAAIBAAgIwwgoygAzAQABAAgIwwgoygAzAQAAAA==.Mireille:BAAALAAECgIIAgAAAA==.Mish:BAABLAAECoEiAAIOAAgIbxUsRADpAQAOAAgIbxUsRADpAQAAAA==.',Mo='Moiki:BAACLAAFFIESAAMJAAUIjhK+CACbAQAJAAUIjhK+CACbAQAOAAEIYQSPTwA8AAAsAAQKgTUAAgkACAhYIKYTAN4CAAkACAhYIKYTAN4CAAAA.Moikidan:BAABLAAECoEWAAIaAAgI+hdcEAAyAgAaAAgI+hdcEAAyAgABLAAFFAUIEgAJAI4SAA==.Moikii:BAAALAAECgEIAQABLAAFFAUIEgAJAI4SAA==.Mokinus:BAAALAADCggIHAAAAA==.Mokki:BAAALAAECgYIDgAAAA==.Mondpriest:BAAALAAECgIIAgAAAA==.Mood:BAAALAAECggIDgAAAA==.Morá:BAAALAAECggICAAAAA==.Moy:BAAALAADCgcIBwAAAA==.',Mu='Muhkuhli:BAAALAADCggIEAAAAA==.Muhskelkater:BAAALAADCggIFwAAAA==.',['Mö']='Mötorhead:BAAALAADCgcIDgAAAA==.',Na='Naelgnuy:BAAALAAECggIEQAAAA==.Nagrim:BAAALAAECgQIBAAAAA==.Nali:BAAALAAECgYICwAAAA==.Nanalí:BAAALAADCggIDgAAAA==.Narimur:BAAALAADCgMIAwABLAAECgcIHgAMAM0hAA==.Nartasha:BAAALAAECgYIEwAAAA==.',Ne='Nexari:BAAALAAECgQIBQAAAA==.Nexarn:BAAALAADCggICAABLAAECggIEAALAAAAAA==.',Ni='Nicepanda:BAAALAAECgYICwAAAA==.',No='Nookye:BAAALAAECggIEwAAAA==.Novosibirsk:BAAALAADCgYIBgAAAA==.',Ny='Nyll:BAAALAADCggIEgAAAA==.',Ob='Oboss:BAAALAAECgIIAgAAAA==.Obôss:BAAALAADCgQICAAAAA==.',Oh='Ohnono:BAAALAADCgcIBwAAAA==.Ohurâ:BAAALAAECgEIAQAAAA==.',Oo='Oomami:BAAALAADCgUIBQAAAA==.',Op='Optimo:BAACLAAFFIEJAAMWAAUI0gb+CQAHAQAWAAQI/Af+CQAHAQASAAEIKQIcCABGAAAsAAQKgSAAAxYACAi3GzUXAFMCABYACAgcGzUXAFMCABIABgj3GdUJAJoBAAAA.',Ow='Owir:BAABLAAECoEbAAIIAAgI1xWXEwBCAgAIAAgI1xWXEwBCAgAAAA==.',Pa='Pain:BAABLAAECoEgAAIVAAgI8yObAwAiAwAVAAgI8yObAwAiAwAAAA==.Palajana:BAAALAADCggIEAAAAA==.Palatin:BAACLAAFFIEIAAIBAAQIyxphCABeAQABAAQIyxphCABeAQAsAAQKgS8AAgEACAghJjoCAIQDAAEACAghJjoCAIQDAAAA.Paragga:BAAALAADCgYIBgAAAA==.Parbo:BAAALAADCgEIAQAAAA==.',Pf='Pfeiline:BAAALAAECggIDwAAAA==.Pfifoltra:BAAALAAECggIDwAAAA==.Pfosten:BAACLAAFFIEHAAIBAAII8xrjIgCqAAABAAII8xrjIgCqAAAsAAQKgRUAAgEACAguGY1FAEECAAEACAguGY1FAEECAAAA.',Ph='Phenex:BAAALAADCgYICgAAAA==.',Pi='Piepsi:BAAALAAECgQICgAAAA==.',Po='Poppy:BAAALAAECggIBwAAAA==.',Pr='Prestoc:BAABLAAECoEVAAIIAAgI2B+nBgDjAgAIAAgI2B+nBgDjAgAAAA==.Propheteggs:BAAALAADCggICAAAAA==.Propheteggxi:BAAALAAECgYIEgAAAA==.',Pu='Puffdaddyy:BAAALAAECgcIBAAAAA==.Puregewalt:BAAALAAECggICAAAAA==.',Qu='Quindo:BAAALAAECgUIBQAAAA==.Quixxor:BAABLAAECoEiAAIdAAgIzSBiCQDnAgAdAAgIzSBiCQDnAgAAAA==.Quixxus:BAAALAAECgYIBgAAAA==.',Ra='Racaf:BAAALAADCggIHwAAAA==.Rattopher:BAAALAADCggIHQAAAA==.Razador:BAAALAAECggIDwAAAA==.Razó:BAAALAADCggIFAAAAA==.',Re='Realness:BAAALAADCgcIBwAAAA==.Reanimator:BAAALAADCgcIBwAAAA==.Regenwetter:BAAALAADCgcIBwABLAAECggIIwAQANQjAA==.',Rh='Rheeja:BAAALAADCggICQAAAA==.',Ri='Rin:BAABLAAECoEWAAMGAAcISxvKGAAxAgAGAAcISxvKGAAxAgAHAAEIJAw34AAzAAAAAA==.Rindersteak:BAABLAAECoEYAAIeAAgIRQNrdgCJAAAeAAgIRQNrdgCJAAAAAA==.',Ro='Robmaster:BAABLAAECoEUAAIfAAYI8QcAjQAXAQAfAAYI8QcAjQAXAQAAAA==.Rokthal:BAAALAADCggICAAAAA==.Rotweiler:BAAALAAECgIIAgAAAA==.',Ru='Rumi:BAAALAAFFAIIAgAAAA==.Ruvena:BAAALAADCggIBgAAAA==.',Ry='Ryndiira:BAAALAADCggICAAAAA==.Ryshala:BAAALAAECggICAABLAAECggIEAALAAAAAA==.',['Rá']='Ránzén:BAAALAAECgUICQAAAA==.',['Rä']='Rämsr:BAAALAADCggIDgAAAA==.',Sa='Sad:BAAALAAECgYICgAAAA==.Sanyex:BAAALAADCggICAABLAAECggIJAABAA0lAA==.Saorla:BAAALAADCgYIBgAAAA==.Saree:BAAALAAECgYIDAAAAA==.',Sc='Scotta:BAABLAAFFIEHAAMVAAQIMRnKBgDVAAACAAQICheABAA3AQAVAAMI1wrKBgDVAAAAAA==.',Se='Seirina:BAAALAADCgEIAQABLAAECgEIAQALAAAAAA==.Seriouzmatze:BAAALAADCgMIAwAAAA==.Seriâ:BAAALAAECgQIBAAAAA==.',Sh='Shakti:BAAALAAECgcIEwAAAA==.Shimarah:BAABLAAECoEYAAIgAAYImBv5BwD2AQAgAAYImBv5BwD2AQAAAA==.Shirá:BAAALAAECgUIDgAAAA==.Shiyana:BAABLAAECoEVAAIHAAgIXQgGfwBvAQAHAAgIXQgGfwBvAQAAAA==.Shorash:BAAALAAECgMIBAAAAA==.',Sn='Snowflaké:BAAALAAECgIIBgAAAA==.',So='Sopala:BAABLAAECoEWAAMKAAYIpxcxKwCZAQAKAAYIpxcxKwCZAQABAAUImAtW3AAOAQAAAA==.Sorata:BAABLAAECoEwAAITAAgILR4eHQC7AgATAAgILR4eHQC7AgAAAA==.Sorayja:BAABLAAECoEWAAIDAAYIgwc4XgAPAQADAAYIgwc4XgAPAQAAAA==.',Sp='Spring:BAAALAAECgYICgAAAA==.',St='Steinbeißer:BAABLAAECoEjAAMQAAgI1COMAQA/AwAQAAgIpSOMAQA/AwAfAAEIFiAAAAAAAAAAAA==.Stoopsr:BAAALAAECgcICgAAAA==.Stregone:BAABLAAECoEYAAITAAgI7QHwugCLAAATAAgI7QHwugCLAAAAAA==.Stronker:BAABLAAECoEYAAIYAAcIow6/GQB2AQAYAAcIow6/GQB2AQAAAA==.Strubelkopf:BAAALAAECgQIBQAAAA==.',Su='Sunic:BAAALAADCggICAAAAA==.Sunji:BAAALAAECgcIEgAAAA==.',Sy='Syhm:BAACLAAFFIEJAAIKAAMI4wtCCwDdAAAKAAMI4wtCCwDdAAAsAAQKgScAAwoACAiuGrweAO4BAAoACAiuGrweAO4BAAEABwgWDeGSAJcBAAAA.Syn:BAAALAAECgYIEAABLAAECggIMAABABYhAA==.',['Sâ']='Sâlira:BAAALAAECgIIAgAAAA==.',['Sî']='Sîlas:BAAALAAECgUICgAAAA==.',['Sú']='Súvá:BAABLAAECoElAAIeAAgIAhxbHABTAgAeAAgIAhxbHABTAgAAAA==.',Ta='Talamera:BAAALAAECggIEAAAAA==.Tallynus:BAABLAAECoEXAAIUAAgIACNsAQAzAwAUAAgIACNsAQAzAwAAAA==.Taloxx:BAAALAADCggICAAAAA==.Talys:BAAALAAECgYICAAAAA==.Tanís:BAABLAAECoEmAAMTAAgIwxmENAA8AgATAAgInhmENAA8AgAIAAQIyxIFVQDyAAAAAA==.Tavaros:BAAALAAECgYICAAAAA==.Taz:BAAALAADCggIDwAAAA==.',Te='Tedia:BAAALAAECgYIEAAAAA==.Teekanne:BAAALAAECgIIAgABLAAECggIFwAUAAAjAA==.',Th='Thcil:BAAALAADCggICAAAAA==.Theoderích:BAAALAAECgMIBgAAAA==.Theóderich:BAAALAAECgYICgAAAA==.Theôderich:BAAALAADCggICAAAAA==.Theøderich:BAAALAAECgUIBgAAAA==.Thjasse:BAACLAAFFIEVAAIOAAUIlxnjBQCYAQAOAAUIlxnjBQCYAQAsAAQKgTEAAg4ACAiPJaMBAGADAA4ACAiPJaMBAGADAAAA.Thorbine:BAABLAAECoEeAAIMAAcIzSHJLgBhAgAMAAcIzSHJLgBhAgAAAA==.Thêoderich:BAAALAADCgQIBQAAAA==.',To='Tomea:BAAALAADCggICAAAAA==.Totemtimo:BAAALAAECgYIDAAAAA==.',Tr='Train:BAAALAAECggIAQAAAA==.Tranq:BAABLAAECoEfAAMRAAgIlxs7GgBpAgARAAgIlxs7GgBpAgAeAAUIEQvRYQDvAAAAAA==.Tranquila:BAAALAAECgUIBQAAAA==.Trekor:BAABLAAECoEjAAIhAAgIlxEdBgD8AQAhAAgIlxEdBgD8AQAAAA==.Trishka:BAAALAAECgcIEAAAAA==.',Ts='Tschiffra:BAAALAAECggIDQAAAA==.',Tu='Turbo:BAACLAAFFIENAAIfAAMIsh9iDgARAQAfAAMIsh9iDgARAQAsAAQKgS8AAh8ACAgJJK0JAD8DAB8ACAgJJK0JAD8DAAAA.',Ty='Tyrodal:BAABLAAECoEdAAIPAAcIHxxuFQAfAgAPAAcIHxxuFQAfAgAAAA==.',['Tá']='Tálînà:BAAALAADCgYIBgAAAA==.',Uk='Ukanu:BAABLAAECoEZAAMiAAYInBnbNwBmAQAiAAUIsBvbNwBmAQAfAAUI3xM+ggA5AQAAAA==.',Ul='Ulkhor:BAABLAAECoEeAAIMAAcIBRN3bQCmAQAMAAcIBRN3bQCmAQAAAA==.',Un='Unclebarry:BAAALAAECgYICQAAAA==.',Ur='Urshâg:BAAALAADCgIIAgAAAA==.',Uw='Uwudan:BAEALAAECgEIAQABLAAFFAUIDQAHAIAfAA==.Uwumage:BAECLAAFFIENAAIHAAUIgB8oBgADAgAHAAUIgB8oBgADAgAsAAQKgSwAAgcACAiRJW0GAFMDAAcACAiRJW0GAFMDAAAA.',Va='Vaelira:BAAALAAECggICAAAAA==.Vagra:BAAALAAECgYICwAAAA==.Vains:BAAALAADCgcIEAAAAA==.Valesia:BAABLAAECoEVAAIBAAYIAx6jVwAQAgABAAYIAx6jVwAQAgAAAA==.Valinus:BAAALAADCggIGQAAAA==.Vaphex:BAABLAAECoEVAAMXAAgIpRr9DgBSAgAXAAgIpRr9DgBSAgAcAAIIjR2cRgCsAAAAAA==.Vasu:BAAALAAECgcIEwAAAA==.Vazu:BAAALAAECgUICgABLAAECgcIEwALAAAAAA==.',Ve='Vezz:BAABLAAECoEYAAMOAAgI0xpORQDlAQAOAAcImRlORQDlAQAJAAcInw+ZTQClAQAAAA==.',Vi='Victôry:BAABLAAECoEiAAMIAAgI9BqrDACKAgAIAAgI9BqrDACKAgATAAEISQgK1wA6AAAAAA==.Violaine:BAAALAADCgMIAwAAAA==.',Vu='Vulturas:BAAALAAECggIDAAAAA==.Vuvigdrood:BAAALAAECgEIAQAAAA==.',Wa='Wakaboom:BAAALAAECgIIAwAAAA==.Washedup:BAAALAAECgYIDAAAAA==.',Xa='Xaeros:BAAALAADCggICAABLAAECggIDAALAAAAAA==.Xaki:BAABLAAECoEdAAMVAAgILxyNCgCXAgAVAAgILxyNCgCXAgAEAAEItgXJWgElAAAAAA==.Xao:BAAALAAECgYIDAAAAA==.',Xe='Xeana:BAAALAADCggIDgAAAA==.Xelodie:BAAALAADCgMIAwABLAAECggIDAALAAAAAA==.Xelsia:BAAALAADCgQIBAAAAA==.Xentronius:BAABLAAECoEcAAIMAAgIQhuHRwAIAgAMAAgIQhuHRwAIAgAAAA==.',Xh='Xhalta:BAAALAADCggICAAAAA==.',Xi='Xilas:BAAALAADCggICAAAAA==.',Xp='Xplórer:BAAALAAECggICAAAAA==.',Xu='Xull:BAAALAADCgcIDQAAAA==.',['Xî']='Xîrr:BAAALAADCgYICAAAAA==.',Ya='Yaely:BAAALAAECgYIEwAAAA==.',Ys='Ysegrim:BAABLAAECoEiAAIOAAcI2B9uJABfAgAOAAcI2B9uJABfAgAAAA==.',Yv='Yve:BAAALAAECgUICAABLAAECgYIBgALAAAAAA==.',Za='Zackding:BAAALAAECgMIAwAAAA==.Zappyboy:BAABLAAECoEbAAIjAAYIog1TFgBbAQAjAAYIog1TFgBbAQAAAA==.',Ze='Zechnet:BAAALAADCgcICAAAAA==.Zeppelin:BAABLAAECoEYAAIMAAcIvgkfnwBBAQAMAAcIvgkfnwBBAQAAAA==.Zerquetscher:BAAALAADCggIEAAAAA==.',Zi='Zilas:BAABLAAFFIEGAAIkAAMI5BxADwAUAQAkAAMI5BxADwAUAQAAAA==.Zipacna:BAABLAAECoEgAAMJAAgIyxIUPADqAQAJAAgIyxIUPADqAQAOAAEIhAF0HQEYAAAAAA==.Zischpeng:BAAALAADCggIEgAAAA==.',Zy='Zyn:BAAALAAECggIEgAAAA==.',['Æl']='Ælumø:BAAALAAECgUIBQAAAA==.',['Æm']='Æmalia:BAAALAADCggICAABLAAFFAMIDAAiAGslAA==.',['Æo']='Æoreth:BAACLAAFFIEMAAIiAAMIayVNBQBOAQAiAAMIayVNBQBOAQAsAAQKgS8AAiIACAjXJi8AAJwDACIACAjXJi8AAJwDAAAA.',['Æw']='Æwyen:BAAALAAECgYICQAAAA==.',['Ðj']='Ðjango:BAAALAAECggIBgAAAA==.',['Ýâ']='Ýâðæßêæßðæðð:BAAALAAECggIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end