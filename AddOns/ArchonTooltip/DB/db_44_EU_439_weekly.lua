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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Arcane','Warrior-Fury',}; local provider = {region='EU',realm="Kil'jaeden",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Act:BAAALAAECgcIDgAAAA==.Acth:BAAALAADCggICgAAAA==.',Ae='Aedaira:BAAALAAECgIIAwAAAA==.',Ai='Aiphatonos:BAAALAAECgMIBQAAAA==.',Al='Alanìa:BAAALAAECgYICAAAAA==.Allegro:BAAALAADCggICAAAAA==.',An='Androgeus:BAAALAAECgYICgAAAA==.Anfaenger:BAAALAADCgcIDQABLAAECgcIEAABAAAAAA==.Ankär:BAAALAAECgYIDAAAAA==.Antarus:BAAALAAECgcIEQAAAA==.Anuri:BAAALAAECgUIAgAAAA==.',Ao='Aoì:BAAALAADCgIIAwAAAA==.',Aq='Aqua:BAAALAAECgcIEwAAAA==.',Ar='Aristelle:BAAALAAECgYIBwAAAA==.Arlik:BAAALAAECgcIEQAAAA==.',As='Asklepia:BAAALAADCgcICgAAAA==.',At='Atali:BAAALAADCgcICAAAAA==.Atheon:BAAALAAECgQIBwAAAA==.',Ay='Ayvi:BAAALAAECgUIBwAAAA==.',Be='Becki:BAAALAADCggICwAAAA==.',Bl='Blâckbêard:BAAALAAECgcIEQAAAA==.',Bo='Bonham:BAAALAADCgcIFQAAAA==.',Br='Bright:BAAALAADCggIDwAAAA==.Brônkô:BAAALAADCgcIDgAAAA==.',Bu='Bulltin:BAAALAADCgIIAgAAAA==.',['Bä']='Bängor:BAAALAAECgEIAQAAAA==.',Ca='Califa:BAAALAAECgEIAgAAAA==.Candy:BAAALAAECgEIAQAAAA==.Cap:BAAALAAECgYICQAAAA==.',Ce='Celilinda:BAAALAAECgEIAQAAAA==.',Ch='Charra:BAAALAADCgYIBgAAAA==.',Ci='Cinan:BAAALAADCgcICgAAAA==.',Cl='Cláymore:BAAALAADCggICAAAAA==.',Co='Coraíja:BAAALAAECgcICgAAAA==.',Cr='Crota:BAAALAADCgQIBAAAAA==.',Da='Darkeflam:BAAALAAECgUIBgAAAA==.Darriss:BAAALAADCgUIBQAAAA==.',Do='Donna:BAAALAAECgMIBQAAAA==.',Dr='Drave:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Dy='Dysnomia:BAAALAAECgMIBgAAAA==.',['Dà']='Dàrà:BAAALAADCgEIAQAAAA==.',El='Eleni:BAAALAADCggIDwAAAA==.',Er='Ernstaugust:BAAALAAECgYICAAAAA==.',Eu='Eulenbär:BAAALAAECgQICAAAAA==.',Ex='Extrém:BAAALAADCgUIBQAAAA==.',Ga='Gammaray:BAAALAAECgEIAQAAAA==.',Gl='Glóin:BAAALAAECgQICAAAAA==.',['Gô']='Gôdîs:BAAALAADCgUIBQAAAA==.',He='Healzero:BAAALAAECgEIAQAAAA==.Hellrazór:BAAALAADCgcIBwAAAA==.Hellsong:BAAALAAECgYICwAAAA==.',Ho='Hocahoshi:BAAALAADCgYICQAAAA==.Horgaar:BAAALAADCggICwAAAA==.',Hu='Hufflepuf:BAAALAAECgcIEQAAAA==.Hulkmoor:BAAALAAECgQIBAAAAA==.',['Hô']='Hôkûspôkus:BAAALAADCgMIAwAAAA==.',Ii='Iisi:BAAALAADCgYIBgAAAA==.',In='Inflâmes:BAAALAAECggIBwAAAA==.',Is='Isabellaa:BAAALAAECgIIAgAAAA==.',It='Itari:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.',Je='Jee:BAAALAADCgcIEwAAAA==.Jendoo:BAAALAAECgEIAgAAAA==.',Ji='Jiika:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.',Ka='Kagrosh:BAAALAADCgcIBwAAAA==.Kaledrial:BAAALAADCggICAAAAA==.Karlach:BAAALAADCgcICgAAAA==.',Ke='Kelridan:BAAALAAECgcIEQAAAA==.',Ki='Kip:BAAALAADCgcIEwAAAA==.',Kr='Krampf:BAAALAADCggICAAAAA==.Krýss:BAAALAAECgUICAABLAAECgcIEQABAAAAAA==.',La='Lanna:BAAALAAECgQIBAAAAA==.',Le='Lecitania:BAAALAADCggIDQAAAA==.',Li='Ligon:BAAALAAECgEIAQAAAA==.',Lo='Loipy:BAAALAAECgYIBwAAAA==.Los:BAAALAADCgcIBwABLAAECggIFgACANAdAA==.Lossy:BAABLAAECoEWAAICAAgI0B2yCQCFAgACAAgI0B2yCQCFAgAAAA==.',Ly='Lyra:BAAALAADCgcICgAAAA==.',['Lê']='Lêyara:BAABLAAECoEUAAIDAAgIihFjLQDNAQADAAgIihFjLQDNAQAAAA==.',['Lû']='Lûxx:BAAALAAECgYICAAAAA==.',Ma='Maidemonboi:BAAALAAECgEIAQABLAAECggIFgAEAEgeAA==.Maiself:BAABLAAECoEWAAIEAAgISB4lCwDDAgAEAAgISB4lCwDDAgAAAA==.Marahi:BAAALAAECgIIAgAAAA==.Marinchen:BAAALAADCgcIEgAAAA==.',Me='Merain:BAAALAAECgIIAgAAAA==.',Mi='Miaupy:BAAALAADCggICAAAAA==.Miazaan:BAAALAAECgYICgAAAA==.Micaleya:BAAALAAECgMIBAAAAA==.Miisha:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.Milek:BAAALAADCgEIAQAAAA==.Mimmimimimii:BAAALAADCgcICAAAAA==.Mirato:BAAALAAECgUICwAAAA==.',Mo='Mokuyoubi:BAAALAAECgcIDgAAAA==.Moyo:BAAALAADCgQIBAAAAA==.',Mu='Muckmúck:BAAALAAECgYIBgABLAAECgcIEwABAAAAAA==.',My='Myrte:BAAALAADCgMIAwAAAA==.',['Mæ']='Mæsticor:BAAALAAECgYICgAAAA==.',['Mí']='Mía:BAAALAAECgYICQAAAA==.',['Mî']='Mîsâ:BAAALAAECgUIAwAAAA==.',Na='Nachtara:BAAALAADCgUIBQAAAA==.Nahimana:BAAALAADCgcIBwAAAA==.Nahin:BAAALAAECgEIAQAAAA==.',Ne='Nefertiabet:BAAALAADCgcICQAAAA==.',Ni='Nightshade:BAAALAAECgcIDAAAAA==.',['Nâ']='Nârthasdûm:BAAALAAECgEIAQAAAA==.',['Né']='Nécray:BAAALAAECgIIAgAAAA==.',On='Onah:BAAALAADCgMIAwAAAA==.',Op='Opia:BAAALAADCgcICAAAAA==.',Or='Orm:BAAALAAECgIIAgAAAA==.Orodrun:BAAALAADCgcICAAAAA==.',Os='Osiriss:BAAALAADCgcIBwAAAA==.',Pa='Pandirio:BAAALAAECgcICQAAAA==.Pauluß:BAAALAAECgYICgAAAA==.',Pe='Peterzwegyat:BAAALAAECgYIBwAAAA==.Peusie:BAAALAADCgcIBwAAAA==.',Pl='Plazer:BAAALAADCggICQAAAA==.',Ra='Ragoo:BAAALAAECgMIBgAAAA==.Rawley:BAAALAADCgcIBwAAAA==.',Re='Redpala:BAAALAADCgQIBAAAAA==.Reed:BAAALAADCgUIBgABLAAECgYICQABAAAAAA==.',Ri='Ridcully:BAAALAAECgMIBAAAAA==.',Ro='Robsn:BAAALAAECgcIDgAAAA==.Ronin:BAAALAADCgIIAgAAAA==.',Ru='Rufi:BAAALAADCgEIAQAAAA==.Rush:BAAALAADCgQIBAAAAA==.',Ry='Rykki:BAAALAADCgYIBgAAAA==.',Sa='Sadry:BAAALAADCgcIBwAAAA==.Sazpal:BAAALAAECgIIAgAAAA==.',Sc='Schneeschatz:BAAALAADCgYIBgAAAA==.Schorliele:BAAALAADCggIEwAAAA==.',Se='Seecrow:BAAALAAECgcIEAAAAA==.',Sh='Shadî:BAAALAADCgMIAwAAAA==.Shammy:BAAALAADCgUIBQAAAA==.Shaymin:BAAALAADCgcIBwAAAA==.Shredd:BAAALAAECgIIAgAAAA==.Shándro:BAAALAAECgQIBwAAAA==.Shíla:BAAALAAECgcIEwAAAA==.',Sk='Skangra:BAAALAAECgcIEQAAAA==.',St='Steckmann:BAAALAAECgIIAgAAAA==.',Sy='Syna:BAAALAAECgUIAgAAAA==.',['Sè']='Sèlie:BAAALAADCgQIBAAAAA==.',['Sê']='Sêlka:BAAALAADCgcIBwAAAA==.',['Sî']='Sîvéry:BAAALAADCgYIBgAAAA==.',Ta='Taolun:BAAALAADCgcIFQAAAA==.',Th='Thanatôs:BAAALAAECgcIEQAAAA==.Thandolin:BAAALAADCgMIAwAAAA==.',Ti='Tinerala:BAAALAADCgYIBgAAAA==.',['Tä']='Tänkgirl:BAAALAADCggICAAAAA==.',['Tô']='Tôbî:BAAALAADCggICgAAAA==.',Ve='Velanìa:BAAALAADCggICAABLAAECgYICAABAAAAAA==.Veromoth:BAAALAADCgcICAAAAA==.',['Vè']='Vègètà:BAAALAAECgMIBAAAAA==.',We='Wendigo:BAAALAADCgMIAwAAAA==.',Wo='Wolfhunter:BAAALAAECgEIAQAAAA==.',['Wâ']='Wârt:BAAALAAECgMIBQAAAA==.',Ya='Yamatô:BAAALAAECgYICgAAAA==.Yannik:BAAALAADCgIIAgAAAA==.',Yl='Ylida:BAAALAADCgcIDgAAAA==.',Yu='Yugoschmugo:BAAALAAECgcIEQAAAA==.Yukìi:BAAALAADCgUIBQAAAA==.',['Yû']='Yûna:BAAALAADCgcICAAAAA==.',Zu='Zues:BAAALAADCgIIAgAAAQ==.Zufall:BAAALAADCgcIDgAAAA==.Zuthugaurk:BAAALAAECgYICQAAAA==.',Zy='Zyklo:BAAALAADCgcIEwAAAA==.',['Át']='Átrox:BAAALAAECgcIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end