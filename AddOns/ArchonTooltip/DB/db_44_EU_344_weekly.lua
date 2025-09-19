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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Warrior-Fury','Mage-Frost','Mage-Arcane',}; local provider = {region='EU',realm="TheSha'tar",name='EU',type='weekly',zone=44,date='2025-08-30',data={Ac='Achlys:BAAALAADCgYIBQAAAA==.',Ae='Aehra:BAAALAAECgYIDgAAAA==.Aelia:BAAALAADCggIFgAAAA==.Aelria:BAAALAAECggICwAAAA==.',Af='Afyxpaladin:BAAALAAECgcICQABLAAECggICAABAAAAAA==.',Al='Alatáriel:BAAALAADCggICAAAAA==.Alenêa:BAAALAAECgYIDwAAAA==.Alliwar:BAAALAAECgMIAwAAAA==.Almighty:BAAALAADCgQIBAAAAA==.Altegos:BAAALAADCggIEQAAAA==.',An='Analda:BAAALAAECgMIAwAAAA==.',Ao='Aodha:BAAALAADCggICQAAAA==.',Ar='Arcstwin:BAAALAAECggICAAAAA==.Arius:BAAALAAECgQIBAAAAA==.Arreas:BAAALAAECgUIBQAAAA==.Arthoríus:BAAALAAECgYICgAAAA==.Arvensis:BAAALAAECgMIAwAAAA==.',As='Assos:BAAALAADCggIEQAAAA==.',Au='Augustipo:BAAALAADCggIDgAAAA==.Aurora:BAAALAAECgQIBAAAAA==.',['Aé']='Aéther:BAAALAADCgcIBwAAAA==.',Ba='Baelmun:BAAALAAECgEIAQAAAA==.Bahämut:BAAALAAECgcIEQAAAA==.Bailsong:BAAALAAECgMIBwAAAA==.Bananas:BAAALAAECgIIAwAAAA==.',Be='Be:BAABLAAECoEWAAQCAAgI2xmUDgBzAgACAAgI2xmUDgBzAgADAAIIGg3rHQCVAAAEAAEI/A+dVAA7AAAAAA==.Benglish:BAAALAAECgIIAgAAAA==.Berthbrew:BAAALAADCgQIBAAAAA==.',Bi='Bigdragonuk:BAAALAADCgEIAQABLAAECgEIAQABAAAAAA==.',Bl='Blackpink:BAAALAAECgIIAQAAAA==.Bleaik:BAAALAAECgIIAgAAAA==.Blinkblin:BAAALAAECgYIDwAAAA==.Blitzø:BAAALAADCgYIBgABLAAECgIIAgABAAAAAA==.Bloodforgive:BAAALAADCggICAAAAA==.',Bo='Bos:BAAALAADCggIDwAAAA==.',Br='Brenwan:BAAALAAECgIIAgAAAA==.Brockus:BAAALAAECgYICQAAAA==.',Bu='Bupsik:BAAALAADCgcIBwABLAAECgcICwABAAAAAA==.',Ca='Cach:BAAALAAECgIIAgAAAA==.Caladrius:BAAALAADCgcIBwAAAA==.Cartoons:BAAALAAECgEIAQAAAA==.',Ce='Cele:BAAALAAECgYICQAAAA==.',Ch='Chamsin:BAAALAADCggICQAAAA==.Chaupté:BAAALAADCgcIDQAAAA==.',Co='Coeus:BAAALAAECggICAAAAA==.Contempt:BAAALAAECgYICwAAAA==.',Cr='Cressidae:BAAALAADCggIEQAAAA==.',Da='Daffid:BAAALAAECgcIBwAAAA==.Dairon:BAAALAADCggICAAAAA==.Darkstyler:BAAALAADCgEIAQAAAA==.',De='Delola:BAAALAAECgcIEwAAAA==.Delori:BAAALAAECgcIDQABLAAECgcIEwABAAAAAA==.Demonchase:BAAALAAECgYIBwAAAA==.',Dh='Dharek:BAAALAADCgMIAwAAAA==.',Di='Dian:BAAALAADCggICAAAAA==.Digitalocean:BAAALAAECgUIBQAAAA==.Dironel:BAAALAADCgcIBwAAAA==.',Dr='Dragonite:BAAALAAECgYIDwABLAAECgcICQABAAAAAA==.',Du='Dumari:BAAALAAECgMIAwAAAA==.Durreos:BAAALAAECgYIBgAAAA==.',El='Elorë:BAAALAADCgcIDAAAAA==.Elyra:BAAALAADCgcIBwAAAA==.',Em='Emb:BAAALAAECgMIBwAAAA==.',Fa='Faith:BAAALAAECgYICQAAAA==.Falthus:BAAALAAECgIIBAAAAA==.',Fi='Fission:BAAALAAECgIIBAAAAA==.',Fl='Flexie:BAAALAAECgMIBgAAAA==.Flufy:BAAALAAECgQIBAAAAA==.',Fo='Forang:BAAALAADCgcIBwAAAA==.',Fr='Freejon:BAABLAAECoEYAAMFAAgIKSQKGgA7AgAFAAYInSMKGgA7AgAGAAMIEiUTGQA7AQAAAA==.Fruitpaste:BAABLAAECoEdAAIHAAgIyB4TBgDdAgAHAAgIyB4TBgDdAgAAAA==.',Ge='Getåfix:BAAALAADCgMIAwAAAA==.',Gh='Ghaos:BAAALAAECgIIAgAAAA==.',Gl='Glorim:BAAALAAECgIIAgAAAA==.',Gr='Grengan:BAAALAAECgMIBwAAAA==.Greytlee:BAAALAAECgYICQAAAA==.Griffy:BAAALAAECgcICQAAAA==.Grimlock:BAAALAADCgQIBwAAAA==.Grúmpz:BAAALAADCggIEAAAAA==.',Ha='Happydotter:BAAALAADCggIDwAAAA==.Harkevich:BAABLAAECoEUAAIIAAgITAizJACdAQAIAAgITAizJACdAQAAAA==.',He='Helenikemen:BAAALAAECggIBgAAAA==.',Hi='Hialoun:BAAALAAECgQICQAAAA==.',Ho='Hog:BAAALAAECgEIAQAAAA==.Hozorun:BAAALAADCgcIBwAAAA==.',Hu='Huntarina:BAAALAADCggICAAAAA==.Hunvel:BAAALAADCggIGAAAAA==.',Il='Ilisara:BAAALAADCggICAAAAA==.Illien:BAAALAADCgYIBgAAAA==.Ilufana:BAAALAADCgIIAgAAAA==.',Im='Imizael:BAAALAAECgMIBgAAAA==.',In='Indraneth:BAAALAADCgcICwAAAA==.',It='Ittygritty:BAAALAADCgIIAgAAAA==.',Je='Jerboa:BAAALAAECgYICQAAAA==.',Ji='Jineve:BAAALAAECgYICAAAAA==.',Kj='Kjelde:BAAALAAECgUIBwAAAA==.',Kl='Klaskadin:BAAALAADCgcIDgAAAA==.',Kn='Knezir:BAAALAADCggIFgAAAA==.',Ko='Kolkman:BAAALAADCgIIAgABLAADCggIDwABAAAAAA==.',La='Laskey:BAAALAADCgcIDAAAAA==.Lays:BAAALAAECggICQAAAA==.',Le='Lemmony:BAAALAADCggIEQAAAA==.',Li='Lightningz:BAAALAADCgcIBgAAAA==.Lilystar:BAAALAADCggICQAAAA==.',Lo='Loverbull:BAAALAADCgcICwAAAA==.',Lu='Lundsveen:BAAALAADCgYICAAAAA==.Lundsvinet:BAAALAADCgUIBQAAAA==.',Ly='Lyaelor:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.',['Lí']='Lía:BAAALAAECgIIAgAAAA==.',Ma='Magfiredon:BAAALAADCgQIBAAAAA==.Malachór:BAAALAAECgMIAwAAAA==.Malakin:BAAALAAECgIIAgAAAA==.Mammu:BAAALAADCgcIBwAAAA==.Manapoly:BAAALAAECgMIBgAAAA==.Maraat:BAAALAADCggICAAAAA==.Marcine:BAAALAAECgMIAwAAAA==.Maxïmo:BAAALAADCggIFQAAAA==.',Mc='Mcfappious:BAAALAAECgYICwAAAA==.',Me='Megwyn:BAAALAAECgYIBgAAAA==.Mercsy:BAAALAAECgYICQAAAA==.Merlot:BAAALAADCgcICAAAAA==.Metrovoid:BAAALAADCgcIBwAAAA==.',Mi='Mikira:BAAALAADCgQIBAAAAA==.Milgrym:BAAALAADCgcICAAAAA==.Milne:BAAALAAECgIIAgAAAA==.Mindafy:BAAALAADCggICAAAAA==.Missbhave:BAAALAADCggICAAAAA==.Misself:BAAALAAECggICQAAAA==.',My='Myrmidons:BAABLAAECoEWAAIJAAgI5B9aAgAUAwAJAAgI5B9aAgAUAwAAAA==.',Na='Nathelsa:BAAALAADCggIFgAAAA==.',Ne='Nehell:BAAALAAECggIAgAAAA==.Neruatnamash:BAAALAAECgcICwAAAA==.',Ni='Nirco:BAAALAADCggIDAAAAA==.Nirtak:BAAALAAECgcICwAAAA==.',No='Noralina:BAAALAADCgYIBgAAAA==.Nour:BAAALAADCgcIBwAAAA==.Novalok:BAAALAAECgQICAAAAA==.Novawólf:BAAALAADCggIDAABLAAECgQICAABAAAAAA==.',['Nø']='Nøvawølf:BAAALAADCgcIDgABLAAECgQICAABAAAAAA==.',Ob='Obihave:BAAALAAECgcIEAAAAA==.Obihiro:BAAALAAECgcICwABLAAECgcIEAABAAAAAA==.',Os='Oshosi:BAAALAAECgYIBgAAAA==.',Pa='Parzivaleu:BAAALAAECgQIBAAAAA==.',Pi='Pixí:BAAALAADCgcIDQAAAA==.',Pr='Prinpringles:BAAALAAECgYIBwABLAAECggICQABAAAAAA==.',Pt='Pthar:BAAALAAECgQIBgAAAA==.',Ra='Ramalama:BAAALAAECgIIBAAAAA==.',Re='Rends:BAAALAAECgYIDQAAAA==.Revlen:BAAALAAECgYIDwAAAA==.',Ri='Rich:BAAALAADCgYIBgAAAA==.Riseragnarok:BAAALAADCgcIDgAAAA==.',Ro='Robinjur:BAAALAADCggIDQAAAA==.Romzi:BAAALAADCgEIAQAAAA==.Roulder:BAAALAADCgcIBwAAAA==.',Sa='Sajoni:BAAALAADCgIIAgAAAA==.Sandarin:BAAALAADCggIFgAAAA==.Satyco:BAAALAAECgMIAwAAAA==.Sautros:BAAALAAECgYIDAAAAA==.',Se='Seanser:BAAALAAECgQICQAAAA==.Sebyz:BAAALAAECgYICQAAAA==.Serpard:BAAALAADCgcIBwAAAA==.Seskâ:BAAALAADCggIEQAAAA==.',Sh='Shendaral:BAAALAADCggIFgAAAA==.Shinayne:BAAALAADCgcIFAABLAADCggIFgABAAAAAA==.',Si='Sidera:BAAALAADCggIEAAAAA==.',Sm='Smìgu:BAAALAADCgcIBwAAAA==.',Sn='Sneb:BAAALAAECgQIAgAAAA==.',Sp='Spiron:BAAALAAECgMIBwAAAA==.',Sq='Squirrelle:BAAALAADCgcIDgAAAA==.',St='Stich:BAAALAAECgEIAgAAAA==.Stokie:BAAALAAECgIIAgAAAA==.',Su='Sunsèt:BAAALAAECgYIDAAAAA==.',Sw='Sweeny:BAAALAAECgYIDwAAAA==.',Ta='Taqui:BAAALAAECgUICAAAAA==.Tavore:BAAALAADCgcIDQAAAA==.',Te='Teelna:BAAALAADCgcIDQAAAA==.Tellwinna:BAAALAADCggIEAAAAA==.Terressio:BAAALAADCgcIBwAAAA==.Tesaki:BAAALAADCgcIBwAAAA==.',Th='Tharaline:BAAALAADCgcIBwAAAA==.Thelei:BAAALAAECgIIBAAAAA==.Thetruedead:BAAALAAECgEIAQAAAA==.Thunderpaw:BAAALAADCgcIBwAAAA==.Thuridain:BAAALAAECgMIBAAAAA==.',To='Tommzan:BAAALAAECgMIBwAAAA==.',Tr='Tryggt:BAAALAADCggICAAAAA==.',Ve='Velskabt:BAAALAADCggIFAAAAA==.Vensom:BAAALAAECgMIAwAAAA==.Verdany:BAAALAAECgYICQAAAA==.',Vi='Viathon:BAAALAADCgcIDQAAAA==.Victos:BAAALAADCgcIDgAAAA==.Vizindra:BAABLAAECoEdAAMKAAgIQRbYKwDRAQAKAAcIVhPYKwDRAQAJAAYIXhJaHABWAQAAAA==.',Vo='Voidmilf:BAAALAADCggICAAAAA==.',Wa='Waldo:BAAALAAECgQIBAAAAA==.',Wi='Wize:BAAALAADCgcICQAAAA==.',Wo='Wolfstar:BAAALAAECgIIAgAAAA==.',Xa='Xanomeline:BAABLAAECoEeAAIDAAgIwCGDAAAyAwADAAgIwCGDAAAyAwAAAA==.',Ze='Zeytinbass:BAAALAAECgYICQAAAA==.',Zh='Zhon:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end