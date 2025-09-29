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
 local lookup = {'Druid-Guardian','Warlock-Demonology','Unknown-Unknown','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Hunter-BeastMastery','Hunter-Survival','DemonHunter-Vengeance','Warlock-Destruction','Paladin-Retribution','Monk-Mistweaver','Rogue-Subtlety','Paladin-Holy','Mage-Fire','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Feral','Shaman-Restoration','DeathKnight-Blood','Warrior-Fury','Priest-Discipline','Evoker-Preservation','Warrior-Arms','Rogue-Assassination','Evoker-Augmentation','Evoker-Devastation','Druid-Restoration','Priest-Shadow','Shaman-Enhancement','DeathKnight-Unholy','Paladin-Protection','Monk-Brewmaster','Warlock-Affliction','Monk-Windwalker',}; local provider = {region='EU',realm='Anetheron',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abendstille:BAABLAAECoEhAAIBAAcIjSXKAgABAwABAAcIjSXKAgABAwAAAA==.Abistir:BAAALAADCgMIAwAAAA==.',Ad='Adolar:BAAALAADCgQIBAAAAA==.',Aj='Ajur:BAABLAAECoEaAAICAAcIGxZtNgByAQACAAcIGxZtNgByAQAAAA==.',Ak='Akalí:BAAALAAECgYICwAAAA==.Akane:BAAALAADCgIIAgABLAAECgYICAADAAAAAA==.',Al='Alanea:BAAALAAECgMIAwAAAA==.Alisyá:BAAALAAECgUIBQAAAA==.Alium:BAAALAADCgcIBwABLAAECgYIBgADAAAAAA==.Aloccola:BAAALAAECgMIBAAAAA==.Altius:BAAALAAECgMIBQAAAA==.Alyana:BAAALAADCgEIAQAAAA==.',Ap='Apschada:BAAALAADCgEIAQABLAAECgYIBgADAAAAAA==.Apschaladla:BAAALAAECgIIAgABLAAECgYIBgADAAAAAA==.',Aq='Aquíla:BAAALAAECgYIEgAAAA==.',Ar='Ararat:BAABLAAECoEiAAIEAAcIqCGHIwBsAgAEAAcIqCGHIwBsAgABLAAFFAUICgAFAM8hAA==.Archidas:BAAALAAECgYICwAAAA==.Ares:BAAALAAECgMIAwAAAA==.Arrowynn:BAAALAAECgYIEwAAAA==.Artikus:BAAALAADCggICwAAAA==.',As='Asahina:BAAALAAECgcIBwAAAA==.Asheop:BAAALAAECgYIEQAAAA==.',Av='Avîella:BAABLAAECoEiAAIGAAgIKQViXgA9AQAGAAgIKQViXgA9AQAAAA==.',Ax='Axepai:BAAALAADCggICAAAAA==.',Ay='Ayumah:BAAALAAFFAIIAgAAAA==.',Az='Azrail:BAAALAAECgIIAgAAAA==.',Ba='Baelamina:BAAALAAECgYICQAAAA==.Baimei:BAAALAADCgcIBwABLAAECgMIAwADAAAAAA==.Balandos:BAAALAAFFAIIBAAAAA==.Baldorr:BAAALAAECgYIEAAAAA==.Baltier:BAAALAADCggIKQAAAA==.Balín:BAABLAAECoEXAAMHAAgITxyVLwBdAgAHAAgIkBqVLwBdAgAIAAYIbRFZEgBLAQAAAA==.Banshee:BAAALAAECgYICQAAAA==.Barlock:BAAALAAECgYIDAAAAA==.',Be='Beaca:BAAALAADCggIGgAAAA==.Beechén:BAAALAAECgYIDAAAAA==.Beelzebubb:BAABLAAECoEhAAIJAAcIDxpXEwALAgAJAAcIDxpXEwALAgAAAA==.',Bi='Bierfräsn:BAAALAAECgEIAQAAAA==.',Bo='Bonza:BAAALAADCggIEwAAAA==.',Br='Bratlainly:BAABLAAECoEbAAIKAAgIuh4fGgDOAgAKAAgIuh4fGgDOAgABLAAFFAIIBgAKAFYgAA==.Braumeîster:BAACLAAFFIEGAAILAAIIfBWHKACkAAALAAIIfBWHKACkAAAsAAQKgSMAAgsACAiSHm4pAKYCAAsACAiSHm4pAKYCAAAA.Brei:BAAALAAFFAIIBAABLAAFFAMIBwAMAMYZAA==.',Bu='Buthead:BAAALAADCgcIFwAAAA==.',['Bé']='Béorn:BAAALAAECggICAABLAAECggIFwAHAE8cAA==.',['Bî']='Bîrndl:BAAALAADCggIEgAAAA==.',Ca='Cae:BAABLAAECoEgAAINAAgIjxWDHQB7AQANAAgIjxWDHQB7AQAAAA==.Can:BAAALAAECgMIAwAAAA==.Capslôck:BAAALAAECgMICAAAAA==.Cartne:BAAALAAECgMIAwAAAA==.Cartneé:BAAALAADCgUIBQAAAA==.Cartné:BAAALAAECgEIAQAAAA==.',Ce='Cerebrum:BAABLAAECoEYAAIOAAcIgSAbDgCFAgAOAAcIgSAbDgCFAgAAAA==.',Ch='Chanji:BAAALAAECgIIAgABLAAECgYIEgADAAAAAA==.Choobbino:BAAALAAECgYIEgAAAA==.Chross:BAAALAADCggIDQAAAA==.',Cl='Clarity:BAAALAAECggICAAAAA==.Cloud:BAAALAAECgQIBAAAAA==.',Co='Cokí:BAAALAAECgYICAAAAA==.Colibriee:BAAALAAECggICQAAAA==.',Cr='Crowley:BAABLAAECoEVAAIPAAgISQQ2DAA7AQAPAAgISQQ2DAA7AQAAAA==.Crysanthem:BAACLAAFFIEMAAMQAAMIvSKcAgAeAQAQAAMIvSKcAgAeAQARAAEIeg7OTQBNAAAsAAQKgR8AAxAACAicIxQHAA4DABAACAicIxQHAA4DABEABwjEF0NMAAECAAAA.',Da='Darkdämona:BAABLAAECoEbAAIKAAcItA/EYACbAQAKAAcItA/EYACbAQAAAA==.Darkillaa:BAABLAAECoEfAAISAAcIWx/pHgA+AgASAAcIWx/pHgA+AgAAAA==.Darksigon:BAAALAAECgYIDwAAAA==.',De='Deelii:BAABLAAECoEUAAIFAAcIYR1qaADxAQAFAAcIYR1qaADxAQAAAA==.Deeps:BAAALAADCggIDgAAAA==.Deldar:BAAALAAECgIIAgAAAA==.Demonbat:BAAALAADCggIDQAAAA==.Derbrain:BAABLAAECoEUAAIEAAYIGRUbUACcAQAEAAYIGRUbUACcAQAAAA==.',Dh='Dhix:BAAALAADCgIIAgAAAA==.',Dr='Dragun:BAAALAADCgcICAAAAA==.Druidefix:BAAALAAECgIIAgABLAAECgYIBgADAAAAAA==.Drákstár:BAAALAADCgYIAgABLAAECgcIFAAFAGEdAA==.',Dw='Dwalìn:BAAALAAECggICAABLAAECggIFwAHAE8cAA==.',['Dâ']='Dârakin:BAAALAADCggICAAAAA==.',Ei='Eisenring:BAABLAAECoEXAAIEAAcIHxqDPQDkAQAEAAcIHxqDPQDkAQAAAA==.',El='Elarion:BAAALAAECggIBwAAAA==.Elementri:BAAALAAECgYICgAAAA==.',En='Enduran:BAAALAAECgYIBwAAAA==.',Es='Essence:BAAALAAECgYIDAABLAAFFAMIDAATAOUfAA==.Eszraa:BAAALAAECgYIBgAAAA==.',Eu='Euda:BAAALAADCgMIAwAAAA==.',Fa='Falling:BAABLAAECoEbAAMEAAYIByEQRADJAQAEAAUI3yAQRADJAQAUAAUIixQelAAbAQAAAA==.Fatzke:BAABLAAECoEeAAMSAAgIchTUKQD2AQASAAgIchTUKQD2AQABAAMI9RBqIwCWAAAAAA==.Fay:BAAALAADCgIIAgAAAA==.',Fe='Fearthyr:BAAALAAECgcIEwAAAA==.Fenrox:BAAALAAECgcIBwAAAA==.',Fi='Fil:BAAALAAECgcICAAAAA==.Firana:BAAALAAECgYIEQAAAA==.',Fl='Flops:BAAALAAECgYIDAAAAA==.',Fu='Fuhrmann:BAABLAAECoEUAAIVAAcIIBS7FwCpAQAVAAcIIBS7FwCpAQAAAA==.',Ga='Gainera:BAAALAADCgcIBwABLAAECgMIAwADAAAAAA==.Gainz:BAAALAAECggICwAAAA==.Garghoul:BAAALAAECgMIBAAAAA==.',Gi='Ginewà:BAAALAAECgcIDwAAAA==.',Gl='Globalmodel:BAAALAAECgMIAwABLAAECgYIGwAWAPQTAA==.Glóin:BAAALAADCggICAABLAAECggIFwAHAE8cAA==.',Go='Goblinmage:BAAALAAECgEIAQAAAA==.Gobolin:BAAALAADCgUIBQABLAAECgYIDAADAAAAAA==.Gothgirl:BAAALAAECgYICAAAAA==.Gozglob:BAAALAAECgIIAwAAAA==.',Gr='Grashüpfer:BAAALAAECgMIAwAAAA==.Gràùmähné:BAAALAADCgQIBAAAAA==.',Gu='Gudndag:BAAALAAECgIIAwAAAA==.Gummibærchen:BAACLAAFFIEJAAISAAMI7iKLCQACAQASAAMI7iKLCQACAQAsAAQKgTEAAhIACAh8JQsDAGgDABIACAh8JQsDAGgDAAAA.Gurnisson:BAAALAAECgYICQAAAA==.',Ha='Hardexx:BAAALAADCggIEwABLAAECgcIIAAXAHUiAA==.Hauminet:BAAALAADCggIGwAAAA==.Havocfeelya:BAAALAADCgMIAQAAAA==.',He='Hellifax:BAAALAAECgMIBgAAAA==.Herrhunter:BAAALAADCggIDwAAAA==.',Hi='Himmel:BAAALAADCgYIBgAAAA==.',Ho='Holeecow:BAAALAADCggICAAAAA==.',Hu='Huddle:BAAALAADCgEIAQABLAAFFAUIBgAGAJsSAA==.',Ic='Icecube:BAAALAADCgcIBwAAAA==.',Ig='Ignit:BAAALAAECgYIDAAAAA==.',Im='Immortalem:BAACLAAFFIERAAIYAAUIVw2ZBABxAQAYAAUIVw2ZBABxAQAsAAQKgSYAAhgACAiwIlYCACcDABgACAiwIlYCACcDAAAA.',Ip='Ipunishu:BAAALAADCggIHAAAAA==.',Jo='Jogi:BAAALAAECgIIAgAAAA==.Joi:BAAALAADCggICAAAAA==.Jojoloco:BAABLAAECoEbAAIWAAYI9BMkZACNAQAWAAYI9BMkZACNAQAAAA==.',Ju='Juma:BAACLAAFFIEIAAIUAAMIRRSkGAC9AAAUAAMIRRSkGAC9AAAsAAQKgR4AAhQACAiCHBAjAGYCABQACAiCHBAjAGYCAAAA.',Ka='Kadalar:BAAALAADCgcIBwAAAA==.Kahooli:BAAALAADCggICAAAAA==.Kalana:BAAALAAECgMIAwAAAA==.Kap:BAAALAAECgYICQAAAA==.Kardeya:BAAALAADCggIDQAAAA==.',Ke='Kelimas:BAAALAAECgIIAwAAAA==.Keluna:BAAALAAECgMIBQAAAA==.',Ki='Kili:BAAALAAECggIDwABLAAECggIFwAHAE8cAA==.Kishi:BAAALAADCggIFAAAAA==.',Kn='Knippeldicht:BAACLAAFFIEJAAIZAAMItBJeAQDbAAAZAAMItBJeAQDbAAAsAAQKgS8AAhkACAiPIgcCACgDABkACAiPIgcCACgDAAAA.',Ko='Koljadk:BAAALAAECgYIDgAAAA==.Kopfschmerz:BAACLAAFFIEIAAMNAAMI7xcLBgAIAQANAAMI7xcLBgAIAQAaAAEIbw5cHABPAAAsAAQKgSYAAw0ACAjlIpAFAN8CAA0ACAiMH5AFAN8CABoABwiVIkYSAIACAAAA.Kornholio:BAABLAAECoEeAAIWAAgI6ww6VAC8AQAWAAgI6ww6VAC8AQAAAA==.',Kr='Kragnarr:BAABLAAECoEYAAMWAAgIHBP1PQALAgAWAAgIHBP1PQALAgAZAAEIURIgNAAzAAAAAA==.Krotau:BAAALAADCggIGgABLAAECgEIAQADAAAAAA==.Krämon:BAAALAAECgEIAQAAAA==.',Ku='Kuhluntas:BAAALAADCgYIBgAAAA==.',Ky='Kyany:BAABLAAECoEVAAMbAAYI2hzQBwDXAQAbAAYI2hzQBwDXAQAcAAMIYxCPTgCUAAAAAA==.Kyojuro:BAAALAAECgYIEgAAAA==.Kyril:BAAALAAECgYIDAABLAAECgYIEAADAAAAAA==.Kyscha:BAABLAAECoEpAAIKAAgIXhMwRgDzAQAKAAgIXhMwRgDzAQAAAA==.Kyushu:BAAALAAECgMIAwAAAA==.',La='Laetheln:BAABLAAECoEqAAIdAAgI1BTJMQDpAQAdAAgI1BTJMQDpAQAAAA==.',Le='Leilas:BAAALAADCgcIDQAAAA==.Lensn:BAAALAADCgcIBwAAAA==.Leverius:BAAALAAECgQIBAAAAA==.Levús:BAABLAAECoEVAAIeAAYIkxPvTABfAQAeAAYIkxPvTABfAQAAAA==.',Li='Linea:BAAALAAECgcICgAAAA==.',Lo='Lolshock:BAACLAAFFIEFAAIfAAMIABZfAgACAQAfAAMIABZfAgACAQAsAAQKgTYAAh8ACAhII6ECAA8DAB8ACAhII6ECAA8DAAAA.',Lu='Luczin:BAAALAADCggIGwAAAA==.',Ly='Lycaon:BAAALAAECgYICwABLAAFFAMIDAATAOUfAA==.Lyssya:BAAALAAECggICAAAAA==.',['Lâ']='Lâppen:BAAALAADCgYICAAAAA==.Lâria:BAAALAADCggIDAAAAA==.',['Lì']='Lìchtkìng:BAABLAAECoEaAAIVAAgIJxk8EAAWAgAVAAgIJxk8EAAWAgAAAA==.',['Lÿ']='Lÿfaeâ:BAAALAADCgMIAQAAAA==.',Ma='Mabagal:BAAALAAECgYIBgAAAA==.Magnesium:BAAALAADCggICQAAAA==.Mainhunter:BAAALAAECgcIBwAAAA==.Manhunter:BAAALAADCgYIBgAAAA==.Mantits:BAAALAADCgYIBgAAAA==.Maritius:BAAALAAECgcICgAAAA==.',Me='Megadeath:BAABLAAECoEZAAMFAAcIgB4GQwBOAgAFAAcIgB4GQwBOAgAgAAQIyhgtMwAVAQAAAA==.Megumii:BAAALAAECgYIDAAAAA==.Mehli:BAAALAAECgcIEwAAAA==.Meleta:BAAALAADCggIAwAAAA==.',Mi='Mikio:BAAALAADCggICAABLAAECgYIBgADAAAAAA==.Milim:BAAALAAFFAMIAwAAAA==.Mishá:BAAALAADCggICAABLAAFFAUICgAFAM8hAA==.Mistborn:BAAALAADCggICQAAAA==.Mitrusa:BAAALAADCggIGgAAAA==.',Mo='Monro:BAAALAAECgEIAQAAAA==.Moomooland:BAAALAAECgIIAgAAAA==.Mordeop:BAAALAAECgcIBwAAAA==.Morgdilla:BAABLAAECoEVAAIUAAgIZhOpTgDJAQAUAAgIZhOpTgDJAQAAAA==.Morgona:BAAALAADCgcIBwAAAA==.',Mu='Mushuu:BAAALAAECgcIDAAAAA==.Muy:BAAALAAFFAMIAwABLAAFFAMIBwAMAMYZAA==.',Na='Nachtgrimm:BAAALAAECgMIBAAAAA==.Nashoba:BAABLAAECoEbAAIBAAYIDgnzHADlAAABAAYIDgnzHADlAAAAAA==.Nathrendil:BAABLAAECoEaAAMFAAYIcRwrggC+AQAFAAYIlhorggC+AQAVAAMIVh35JgABAQAAAA==.',Ne='Nebelstern:BAAALAADCggICAAAAA==.Necron:BAAALAADCggICAAAAA==.',Ni='Nihri:BAAALAAECggIEgAAAA==.Nijx:BAABLAAECoEeAAINAAcILhMNFgDFAQANAAcILhMNFgDFAQAAAA==.Nilenn:BAAALAADCgYICQABLAAECgcIFAAFAGEdAA==.Nimilora:BAAALAAECggIDQAAAA==.',Nu='Nunubaum:BAABLAAECoEfAAQBAAcIcSCjBwBLAgABAAcIcSCjBwBLAgATAAYIRBEHJABDAQAdAAEIgxqPtgA6AAAAAA==.',Ny='Nymeria:BAAALAAECgQICQAAAA==.Nypàax:BAABLAAECoEeAAMhAAcIVSWcBgD3AgAhAAcIVSWcBgD3AgALAAIINA1hIQFpAAAAAA==.',['Ná']='Náinn:BAABLAAECoEaAAIMAAgIpAyWIAByAQAMAAgIpAyWIAByAQABLAAECggIKwAOAE8VAA==.',['Né']='Néâ:BAAALAAECgcIDwAAAA==.',Oh='Ohjee:BAAALAAECgQIBgAAAA==.',Ok='Oktobär:BAAALAADCggICAAAAA==.',Om='Omertà:BAAALAAECgYICgABLAAFFAUICgAFAM8hAA==.',Or='Orea:BAAALAADCggICAAAAA==.',Os='Ossaya:BAACLAAFFIEZAAIEAAcIYR0QAQCRAgAEAAcIYR0QAQCRAgAsAAQKgTgAAgQACAinJkYBAIsDAAQACAinJkYBAIsDAAAA.',Ot='Otz:BAAALAAECgcIEQABLAAFFAMICwAFACMcAA==.',Ow='Owiwan:BAAALAAECgYIBgAAAA==.Owíwan:BAAALAAECgYICwAAAA==.',Pa='Packnum:BAAALAAECgIIAgAAAA==.Paddl:BAAALAADCggIAgABLAAFFAUIBgAGAJsSAA==.Paldana:BAAALAADCgIIAgAAAA==.',Pd='Pddly:BAACLAAFFIEGAAIGAAUImxKUMwBQAAAGAAUImxKUMwBQAAAsAAQKgSQAAwYACAjjJjgAAJUDAAYACAjjJjgAAJUDAB4ABgieHZcwAOwBAAAA.',Pe='Pepeer:BAAALAADCggICAAAAA==.',Ph='Phl:BAAALAAECgcICwAAAA==.',Pl='Plagegeist:BAAALAADCggICQAAAA==.',Pr='Presage:BAAALAADCgcIBwAAAA==.Princêss:BAAALAAECgQIBAAAAA==.Proselytizer:BAAALAAECgUICAAAAA==.',Pu='Puddl:BAAALAADCggIDgABLAAFFAUIBgAGAJsSAA==.Puddli:BAAALAAECgQIBQABLAAFFAUIBgAGAJsSAA==.Puenktcheen:BAAALAADCgYIBgABLAAECgIIAgADAAAAAA==.Pussti:BAAALAAECgMIBwAAAA==.',Pw='Pwnmnk:BAABLAAECoEfAAIiAAcIah0aEAAtAgAiAAcIah0aEAAtAgAAAA==.',['Pó']='Pów:BAAALAADCgYIBgAAAA==.',Qu='Quaigon:BAAALAADCgcICgAAAA==.Quitschiboo:BAAALAAECggICAAAAA==.',Ra='Rawr:BAABLAAECoEUAAIEAAcIhBiHMwASAgAEAAcIhBiHMwASAgAAAA==.Rawsteak:BAAALAADCggIEAAAAA==.',Re='Reesy:BAAALAAECgYIBwAAAA==.',Ri='Rikka:BAABLAAECoEdAAMcAAgIXR4TDwCwAgAcAAgIXR4TDwCwAgAYAAIISgzTMwBbAAAAAA==.Riku:BAAALAAECgYIBgAAAA==.',Ro='Roqu:BAACLAAFFIEPAAIMAAYIphBkAgDiAQAMAAYIphBkAgDiAQAsAAQKgSkAAgwACAhHI74DABwDAAwACAhHI74DABwDAAAA.Rouddly:BAAALAADCggICAABLAAFFAUIBgAGAJsSAA==.Roxî:BAAALAAECgUIDwAAAA==.',Ry='Ryuná:BAABLAAECoEZAAIhAAcI6BWdIQCyAQAhAAcI6BWdIQCyAQAAAA==.Ryò:BAABLAAECoEmAAIHAAYIfR9dbQCmAQAHAAYIfR9dbQCmAQAAAA==.',Sa='Sahtrâ:BAAALAADCgIIAgAAAA==.Sand:BAAALAAECgIIAgAAAA==.',Sc='Schlizi:BAAALAADCggICAABLAAECgcIHwABAHEgAA==.Schmarn:BAAALAAECgUICAAAAA==.',Se='Senfgurke:BAAALAADCggIDgAAAA==.Sengsi:BAAALAADCgEIAQAAAA==.Sentient:BAABLAAECoEeAAIjAAcIPBdgCQAHAgAjAAcIPBdgCQAHAgAAAA==.Serpentor:BAAALAADCgMIAwABLAAECgcICgADAAAAAA==.',Sg='Sgturgoth:BAAALAAECgYIBgAAAA==.',Sh='Shadowfist:BAAALAAECgEIAQAAAA==.Shamtastic:BAAALAAECgYIEgAAAA==.Shanei:BAAALAAECgYIEQAAAA==.Sharon:BAAALAAECgYIDAAAAA==.Shax:BAABLAAECoEbAAIhAAYI1Qr/OgACAQAhAAYI1Qr/OgACAQAAAA==.Shmo:BAAALAADCggICAAAAA==.Shàdów:BAAALAAECgYIDAABLAAECggIJAAWAHAVAA==.Shággy:BAAALAAECgYICAAAAA==.',Si='Sidious:BAAALAADCgYIBgAAAA==.Silora:BAAALAAECgcICgAAAA==.Sinopa:BAAALAAECgMICgAAAA==.',Sk='Skadin:BAAALAAECgIIAgAAAA==.',Sl='Slevìn:BAAALAADCggIFAAAAA==.Slizar:BAAALAAECgYIDQAAAA==.Slow:BAAALAAECgYIDAAAAA==.',Sn='Snekii:BAAALAADCgYIAwAAAA==.Snowblinder:BAABLAAECoEaAAIQAAcI0x+5EACAAgAQAAcI0x+5EACAAgAAAA==.Snowøwhite:BAAALAADCggICAAAAA==.Snúffy:BAAALAAECgIIBAAAAA==.',So='Soku:BAAALAADCggICAAAAA==.Solacé:BAAALAAECgEIAQABLAAECgIIAwADAAAAAA==.Solen:BAAALAAECgIIAwAAAA==.Solominati:BAAALAADCgcICgAAAA==.Soláce:BAAALAAECgIIAwAAAA==.',Su='Suarok:BAAALAAECgUICQABLAAECggIIAAEALggAA==.Sugar:BAACLAAFFIEKAAIFAAUIzyEbBgDxAQAFAAUIzyEbBgDxAQAsAAQKgTQAAwUACAhLJmQDAHEDAAUACAhLJmQDAHEDACAAAgiNIws+ALoAAAAA.',Sy='Sylvi:BAAALAADCgUIBQAAAA==.Sylviane:BAAALAAECggICAAAAA==.',['Sè']='Sèkèh:BAAALAADCgYIBgAAAA==.',['Sí']='Sírhealalot:BAAALAAECgYIBgAAAA==.Sírrollalot:BAAALAAECgYIDwAAAA==.',['Só']='Sólace:BAAALAADCgIIAwABLAAECgIIAwADAAAAAA==.',['Sý']='Sýd:BAAALAAECgcIEgAAAA==.',Ta='Tadea:BAAALAAFFAIIAgAAAA==.Talnazhar:BAABLAAECoEUAAILAAgIVhsoPwBTAgALAAgIVhsoPwBTAgAAAA==.Tanaka:BAAALAADCgcIDgAAAA==.Tanathos:BAABLAAECoEXAAIkAAcI5A59KQCFAQAkAAcI5A59KQCFAQAAAA==.',Te='Teddylinchen:BAAALAADCgIIAgAAAA==.Teddywulf:BAAALAADCggICAAAAA==.Teeparty:BAAALAAECgUICAAAAA==.Terestrior:BAABLAAECoErAAIOAAgITxX+GQAUAgAOAAgITxX+GQAUAgAAAA==.Terrorstorm:BAAALAADCgcIBwAAAA==.Teruka:BAABLAAECoEaAAIVAAcIMQrXIgAoAQAVAAcIMQrXIgAoAQAAAA==.Texasdk:BAAALAAECgIIAgAAAA==.Texashunt:BAAALAAECggIAwAAAA==.',Th='Thedaemon:BAAALAAECgIIAwAAAA==.Theresa:BAAALAAECgcIBwAAAA==.',Ti='Tigersclaw:BAAALAAECgMIAwAAAA==.',Tr='Trikmi:BAAALAADCggICAABLAAECgcIGQAFAIAeAA==.Trillion:BAAALAAECgYIEgAAAA==.',Ts='Tschaba:BAAALAADCggIEAAAAA==.',Ty='Tyrionas:BAAALAADCggIEgAAAA==.',['Tî']='Tîenchen:BAABLAAECoEUAAMCAAYIfQiGRwAtAQACAAYIYwiGRwAtAQAjAAMIlwO/LwBiAAAAAA==.',Va='Vaelthas:BAAALAADCgcIBwAAAA==.Valento:BAABLAAECoEfAAINAAcICSWfBAD0AgANAAcICSWfBAD0AgAAAA==.Varina:BAAALAAECgcIEwABLAAECggIDgADAAAAAA==.Vashthedevil:BAAALAAECgYIBwABLAAECgcIEQADAAAAAA==.',Vi='Villeroy:BAAALAAECgYIDAAAAA==.Virtuoso:BAAALAAECgEIAQAAAA==.',Vo='Voljathan:BAAALAAFFAIIAgAAAA==.',Vr='Vraagar:BAABLAAECoEbAAMKAAgI/B2OGwDFAgAKAAgI0B2OGwDFAgACAAMI7xPEXwDAAAAAAA==.',Wa='Warak:BAAALAAECgIIAgAAAA==.',Wo='Wogen:BAAALAAECgYIEgAAAA==.Wogon:BAACLAAFFIEMAAITAAMI5R+IAwAfAQATAAMI5R+IAwAfAQAsAAQKgSgAAhMACAhqJk8AAIkDABMACAhqJk8AAIkDAAAA.Wolke:BAAALAADCggICQAAAA==.',Wr='Wrööms:BAAALAADCgMIAwAAAA==.',Wu='Wubbel:BAABLAAECoEmAAISAAgIPx+lDwDRAgASAAgIPx+lDwDRAgAAAA==.Wusha:BAAALAAECgEIAQAAAA==.',Xa='Xarfai:BAAALAADCggIFgAAAA==.',Xr='Xrage:BAAALAAECgYIEgAAAA==.',Yi='Yinaya:BAACLAAFFIESAAIMAAUIIh5jAgDjAQAMAAUIIh5jAgDjAQAsAAQKgSQAAgwACAh7IdcEAAYDAAwACAh7IdcEAAYDAAAA.',Ym='Ymhitra:BAAALAADCggIEQABLAAECgYICwADAAAAAA==.',Yo='You:BAAALAAECggIDgAAAA==.',Yu='Yum:BAACLAAFFIEHAAIMAAMIxhlXBgALAQAMAAMIxhlXBgALAQAsAAQKgTMAAwwACAi+IGAFAPsCAAwACAi+IGAFAPsCACQABgiGIroVADkCAAAA.',Za='Zahnpasta:BAAALAAECgYIBgAAAA==.',Ze='Zenduran:BAACLAAFFIEHAAIUAAMIYg+YGAC9AAAUAAMIYg+YGAC9AAAsAAQKgSQAAhQACAhnGd80AB0CABQACAhnGd80AB0CAAAA.',Zh='Zhinn:BAABLAAECoEgAAIXAAcIdSJ0AgDIAgAXAAcIdSJ0AgDIAgAAAA==.',Zi='Ziim:BAABLAAECoEZAAMLAAcI8BnRVQAUAgALAAcI8BnRVQAUAgAhAAEIgB4oWABQAAAAAA==.',Zu='Zunný:BAAALAAECgEIAQAAAA==.',Zw='Zwoluntas:BAAALAAECgYIBwAAAA==.',['Zä']='Zäpfli:BAAALAAECgIIAwAAAA==.',['Ãc']='Ãce:BAAALAAECgYIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end