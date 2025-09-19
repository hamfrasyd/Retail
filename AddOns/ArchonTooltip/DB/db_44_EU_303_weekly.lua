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
 local lookup = {'Hunter-Marksmanship','Unknown-Unknown','Rogue-Assassination','Paladin-Retribution','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Mage-Arcane','Hunter-Survival','Monk-Brewmaster','Rogue-Subtlety','Warrior-Fury','Monk-Mistweaver','Warrior-Protection','Druid-Feral','Mage-Fire',}; local provider = {region='EU',realm='Karazhan',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aavux:BAABLAAECoEUAAIBAAcIfhn9GQAWAgABAAcIfhn9GQAWAgAAAA==.',Ae='Aedàn:BAAALAADCgcIBwAAAA==.Aethio:BAAALAAECgIIAgAAAA==.',Ai='Airman:BAAALAAECgIIAgAAAA==.',Ak='Akronnys:BAAALAAECgUIBwAAAA==.',Al='Algethi:BAAALAADCggICAABLAAECgcIEQACAAAAAA==.Alphapo:BAAALAAECggICAAAAA==.Altergeist:BAAALAAECgQIBQAAAA==.',Am='Amarabub:BAAALAADCggICAAAAA==.',An='Andragon:BAAALAAECgIIAgAAAA==.Andrahad:BAAALAAECgIIAgAAAA==.',Ar='Arnathil:BAAALAAECggICwAAAA==.Arthuss:BAAALAADCggIEwAAAA==.Articono:BAAALAAECggICAAAAA==.',Au='Auer:BAAALAADCggICAABLAAECgEIAQACAAAAAA==.',Az='Azeous:BAAALAAECggICAAAAA==.',Ba='Battôsai:BAAALAAECgYIEAABLAAECggIEgACAAAAAA==.',Be='Beliriosus:BAAALAAECgcICgAAAA==.Bemortal:BAAALAADCggICwAAAA==.',Bi='Bicklige:BAABLAAECoErAAIDAAgIkSYkAACSAwADAAgIkSYkAACSAwAAAA==.Bimortals:BAAALAADCggICAABLAADCggICwACAAAAAA==.',Bl='Blades:BAAALAADCgcIFQAAAA==.',Br='Brandón:BAAALAAECgMIAwAAAA==.Brickedpope:BAAALAAECgcICQAAAA==.Brokk:BAAALAADCggICAABLAAECggIFwAEAI0kAA==.',Bu='Buildmeister:BAAALAAECgYICwAAAA==.Bumbuliits:BAAALAAECgcIDQAAAA==.Burnthedemon:BAAALAADCgUICgAAAA==.',Ca='Calida:BAAALAAECgYIBgAAAA==.Caltaq:BAAALAADCgUIBQAAAA==.Caprice:BAAALAAECgMIAwAAAA==.',Ce='Celice:BAAALAAECgQICAAAAA==.',Ch='Chamdrin:BAAALAADCgcIBwAAAA==.Charlock:BAAALAADCggIGAAAAA==.',Ci='Cibbry:BAAALAADCgQIBwAAAA==.',Co='Comastca:BAAALAAECgIIAgAAAA==.',Cr='Crackattack:BAAALAAECgYIDgAAAA==.Crackshot:BAAALAAECgUIBQAAAA==.Cryopriest:BAABLAAECoEZAAIFAAgIuyJ2BgAaAwAFAAgIuyJ2BgAaAwAAAA==.Cryowar:BAAALAAECgcIEgAAAA==.',Cu='Cuggul:BAAALAAECgMIAwAAAA==.',Cy='Cynder:BAAALAAECgcIEgAAAA==.',Da='Dalix:BAAALAAFFAIIAwAAAA==.Damianoo:BAAALAAECgEIAQAAAA==.Darkmatter:BAAALAADCggICAAAAA==.',De='Deathanddk:BAAALAADCgUIBQAAAA==.Deatherlo:BAAALAAECgYIDgAAAA==.Deathwalker:BAAALAAECgYICgAAAA==.Debieltje:BAABLAAECoEdAAMGAAgIziVoAAB7AwAGAAgIziVoAAB7AwAHAAMI1BwWmwCwAAAAAA==.Demonil:BAAALAADCgEIAQAAAA==.Desi:BAAALAAECgEIAQAAAA==.',Dh='Dhanvantari:BAAALAADCggIFQAAAA==.',Di='Dianase:BAAALAAECgYICAAAAA==.Disceplin:BAAALAADCggICwAAAA==.Disk:BAAALAAECggICAAAAA==.Diya:BAABLAAECoEeAAMIAAgIMyV5AQBGAwAIAAgIMyV5AQBGAwAJAAEIfQ0BcAA4AAAAAA==.',Dj='Djonz:BAAALAADCggIBQAAAA==.Djtwo:BAAALAAECgcIDwAAAA==.',Dr='Drakkan:BAABLAAECoEeAAIEAAgIPiASEADlAgAEAAgIPiASEADlAgAAAA==.Drzed:BAAALAAECgMIAwAAAA==.',Du='Duppi:BAAALAAECggIFgAAAQ==.',Dw='Dwarfmorph:BAAALAAECgQIBAAAAA==.Dwel:BAABLAAECoEYAAIKAAgIix4yAQDbAgAKAAgIix4yAQDbAgAAAA==.',['Dí']='Díana:BAAALAADCgUIBQAAAA==.',Ea='Earwin:BAAALAAECgcIDQAAAA==.',Ef='Efern:BAAALAAECgcIDgAAAA==.',En='Entropeth:BAAALAAECgIIAgAAAA==.Enyo:BAAALAADCgcIBwABLAAECgcIEQACAAAAAA==.',Er='Erduhoar:BAAALAADCgMIBAAAAA==.',Fa='Falk:BAAALAADCggICAABLAAECggIHgALAIojAA==.',Fe='Felipoz:BAABLAAECoEeAAMMAAgIWyLBBAC0AgANAAgIlR7WEQDUAgAMAAgIVSDBBAC0AgAAAA==.Feraloration:BAAALAAECgYIDQAAAA==.Feythion:BAAALAAFFAIIAgAAAA==.',Fi='Firefiddy:BAAALAADCgIIAgAAAA==.',Fl='Flaxxmix:BAAALAAECgEIAQAAAA==.',Fr='Frumpwarden:BAAALAADCgYIBgAAAA==.',Fu='Furrball:BAAALAADCgIIAgAAAA==.Fuzzybeast:BAAALAAECgEIAQAAAA==.',Ga='Gabzz:BAABLAAECoEeAAMLAAgIiiMqAgBJAwALAAgIiiMqAgBJAwAOAAgIEBHXNADwAQAAAA==.Galadin:BAAALAAECggICAAAAA==.Galaxes:BAAALAAECgIIAgAAAA==.Garez:BAAALAADCgIIAgAAAA==.',Gd='Gdpriest:BAAALAAECgYIEAAAAA==.',Go='Goatyboi:BAAALAAECgcIBwAAAA==.Goliäth:BAAALAAECggIEwAAAA==.',Gr='Grindelwald:BAAALAAECggIEgAAAA==.',Ha='Harmöny:BAAALAAECgYICQAAAA==.',Hi='Highchief:BAAALAAECgcIEQAAAA==.',Ho='Holycow:BAAALAADCggICAAAAA==.Holynuka:BAAALAAECgIIAgAAAA==.',Hu='Hungsolo:BAAALAAECgIIAgAAAA==.',Ic='Icaríum:BAAALAAECggIEwAAAA==.',Id='Idioot:BAAALAAECgUIDAAAAA==.',Ig='Igotbubble:BAAALAAECggIEgAAAQ==.',Io='Iol:BAAALAADCggICAABLAAECgYIEAACAAAAAA==.',Ja='Jacinto:BAAALAAECgIIBAAAAA==.Jamaico:BAAALAAECgYICwAAAA==.',Jo='Joltcola:BAAALAAECgYIEAAAAA==.',Jp='Jpoopmypants:BAAALAAFFAIIAgAAAA==.',Ju='Juicen:BAAALAAECgQIBAAAAA==.Justlock:BAAALAAECgYICAAAAA==.',Ka='Kalyssa:BAAALAAECgYIBgAAAA==.Karakize:BAAALAADCgcIBwAAAA==.Kaskassim:BAAALAAECgMIAwAAAA==.Katukas:BAABLAAECoEhAAIPAAgINSL0AAAXAwAPAAgINSL0AAAXAwAAAA==.',Ki='Kikle:BAAALAAECgcIEwAAAA==.',Ko='Koggan:BAAALAAECgMIAQAAAA==.',Ku='Kulamagdula:BAAALAADCgcIBwAAAA==.Kusneymonk:BAABLAAECoEVAAIQAAgIRSZYAACHAwAQAAgIRSZYAACHAwABLAAECggIGQARANciAA==.Kusneyrogue:BAABLAAECoEZAAMRAAgI1yIEAgANAwARAAgIOiEEAgANAwADAAYIgh/cGwDdAQAAAA==.Kusneywar:BAAALAAECgQIBgABLAAECggIGQARANciAA==.',['Ká']='Káal:BAABLAAECoEXAAISAAcI4xYpJAD6AQASAAcI4xYpJAD6AQAAAA==.',La='Lackra:BAAALAADCgYIBgAAAA==.Lackro:BAAALAAECgcIEAAAAA==.',Lo='Lockiè:BAAALAAECgYIBgAAAA==.Lokthar:BAAALAAECgUIBwAAAA==.Lost:BAAALAADCggICAAAAA==.Lovenote:BAAALAADCgEIAQAAAA==.',Lu='Lunya:BAAALAAECgcIEAAAAA==.',Lv='Lv:BAAALAAECgcICwAAAA==.',Ly='Lynex:BAAALAAECgIIAgAAAA==.',['Lé']='Léhál:BAAALAAECggICAAAAA==.',Ma='Madoushi:BAAALAAECgEIAQAAAA==.Madstorm:BAAALAAECgcIDgAAAA==.Magnusz:BAAALAAECgEIAQAAAA==.Magx:BAAALAADCggICAABLAAFFAIIAgACAAAAAA==.Makhel:BAAALAADCgcIBwABLAAECggIEgACAAAAAA==.Marfa:BAAALAAECgYICAAAAA==.Marone:BAAALAADCgYICgAAAA==.Maverick:BAAALAADCgMIAwABLAADCgcIBwACAAAAAA==.',Me='Mechamonk:BAAALAAECgYICQABLAAECggIGQATAIwjAA==.Metrox:BAAALAAECggICAAAAA==.',Mi='Mischiefra:BAAALAADCgcIDAAAAA==.',Mo='Moofassa:BAAALAADCggIFAAAAA==.',Mu='Muleria:BAAALAADCgIIAgAAAA==.',My='Myfaith:BAAALAADCgYIBgAAAA==.Myzzo:BAAALAADCgcIBwAAAA==.',['Má']='Málly:BAAALAAECgUIBwAAAA==.',['Mö']='Mörkerz:BAAALAAECgMIAwAAAA==.',Na='Naidala:BAABLAAECoEUAAIOAAgIgw+6NADxAQAOAAgIgw+6NADxAQAAAA==.Najimä:BAAALAADCggICQAAAA==.Naverene:BAAALAAECgYIDAAAAA==.Nayomi:BAAALAADCgYIBgABLAAECgMIAwACAAAAAA==.',Ne='Nedol:BAAALAAECgEIAQAAAQ==.Neiloth:BAAALAADCggIFAAAAA==.Nell:BAAALAAECggIEQAAAQ==.',Ni='Nibel:BAABLAAECoEUAAIUAAcIeBZsFADYAQAUAAcIeBZsFADYAQAAAA==.Nightroar:BAAALAADCgUIBgAAAA==.',No='Nowaytorun:BAAALAADCgEIAQAAAA==.',['Né']='Nééko:BAAALAAECggIBgAAAA==.',Oc='October:BAAALAAECgMIAwAAAA==.',Od='Oda:BAABLAAECoEZAAITAAgIjCOcAQA1AwATAAgIjCOcAQA1AwAAAA==.Odinwarrior:BAABLAAECoEjAAIUAAgIJiK5AwARAwAUAAgIJiK5AwARAwAAAA==.',Ok='Okoo:BAAALAAECgIIAQAAAA==.',Or='Oriens:BAABLAAECoEUAAIBAAYIiyHIIgDMAQABAAYIiyHIIgDMAQAAAA==.',Pa='Palamok:BAAALAADCgcIBwAAAA==.Palando:BAAALAADCgUIBQAAAA==.Palayumix:BAAALAAECgMIAwAAAA==.Paraceta:BAAALAADCggICAAAAA==.',Pe='Peldronn:BAAALAADCggIDwAAAA==.Pepe:BAAALAADCgcIBwAAAA==.',Pi='Pigwa:BAAALAAECgIIAwAAAA==.Pitchou:BAABLAAECoEUAAIVAAcIJBYWCwATAgAVAAcIJBYWCwATAgAAAA==.',Pl='Plork:BAAALAAECgcIDAAAAA==.',Po='Poka:BAEALAAFFAIIAgAAAA==.Polgaria:BAAALAAECgYIDAAAAA==.',Pr='Preb:BAAALAAECgUIBQAAAA==.Pressure:BAAALAAECgYIEQAAAA==.Prottyprott:BAAALAAECgQICAAAAA==.Prézz:BAAALAAECgEIAQAAAA==.',Pu='Puth:BAAALAADCggICAAAAA==.',Ra='Randhunter:BAAALAADCggIGAAAAA==.Randproest:BAAALAADCggICAABLAADCggIGAACAAAAAA==.Rawrzen:BAAALAADCgcICQAAAA==.',Re='Reia:BAABLAAECoEXAAIEAAgIjSSBDAAHAwAEAAgIjSSBDAAHAwAAAA==.Renado:BAAALAADCgYIDAAAAA==.',Ro='Rockandstone:BAAALAAECgcICAAAAA==.',['Ró']='Róan:BAAALAADCggICAAAAA==.',Sc='Scully:BAAALAAECgUIBAAAAA==.',Se='Seldarina:BAAALAAECgYIBwAAAA==.',Sh='Shadowpaws:BAAALAAECgMIAwAAAA==.Shamastic:BAAALAAECgUIBgAAAA==.Shammymcdady:BAAALAADCggIEQAAAA==.Shawan:BAAALAADCggIEwAAAA==.',So='Sorrowfull:BAAALAAECggIEAAAAA==.Soulcooker:BAAALAAECgcICQAAAA==.',Sp='Spiritnature:BAAALAADCgcIBwAAAA==.',St='Starcallêr:BAAALAAECgEIAQAAAA==.Storcritsyo:BAAALAADCggICAAAAA==.Stormbringer:BAAALAAECgEIAQAAAA==.Stramifisken:BAAALAADCgQIBAAAAA==.',Su='Sup:BAAALAAECgcIDQAAAA==.',Sw='Swollen:BAAALAADCggIFgAAAA==.',Ta='Tavarine:BAAALAADCggIEAABLAAECgYIDAACAAAAAA==.',Th='Thelavar:BAAALAAECgcIDAAAAA==.Thorinaun:BAAALAADCggICAAAAA==.Thoringaarn:BAAALAAECgYICwABLAAECggIGQAIAH8RAA==.Thorinmuin:BAABLAAECoEZAAIIAAgIfxHLNACrAQAIAAgIfxHLNACrAQAAAA==.Thundersmash:BAAALAADCggICAABLAAECgEIAQACAAAAAQ==.',Tr='Trumpsbeach:BAAALAAECgUIBgAAAA==.',Tu='Turambar:BAAALAAECgcIDwAAAA==.',['Tø']='Tøysekopp:BAAALAADCggIDAAAAA==.',Va='Varlon:BAAALAADCggICAAAAA==.',Ve='Veinlash:BAAALAAECgcIEgAAAA==.',Vi='Vincetti:BAAALAAECgEIAQAAAA==.',Vo='Voided:BAAALAAECgMIAwAAAA==.',Wa='Wakanda:BAAALAAECgYICAAAAA==.Warner:BAAALAAECgMIBgAAAA==.',Wi='Wilder:BAAALAAECgMIAwAAAA==.Willy:BAAALAADCggIBgAAAA==.Winkles:BAABLAAECoESAAQOAAYIzRRTWgBRAQAOAAUIMxZTWgBRAQALAAQIEhUUOQDkAAAWAAEIYwqJFAA2AAAAAA==.',Xd='Xdalipala:BAAALAAECgUIBQAAAA==.',Ya='Yara:BAAALAAECgcIDwAAAA==.Yarn:BAAALAAECgUIBQABLAAECgYICAACAAAAAA==.',Yo='Yogsoggoth:BAAALAAECgEIAgAAAA==.You:BAAALAAECgYIBgAAAA==.',Za='Zanamaseluta:BAAALAAECgYIDAAAAA==.Zañithy:BAAALAAECggIDgAAAA==.',Ze='Zexu:BAAALAAECgcIBwAAAA==.',Zo='Zoltar:BAAALAADCgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end