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
 local lookup = {'Unknown-Unknown','Shaman-Restoration','Paladin-Protection','DemonHunter-Havoc','Mage-Arcane','Mage-Frost','Mage-Fire','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety',}; local provider = {region='EU',realm='ShatteredHalls',name='EU',type='weekly',zone=44,date='2025-09-06',data={Al='Alti:BAAALAADCgYIBgAAAA==.Alymantara:BAAALAAECgUICgAAAA==.',Am='Amalka:BAAALAAECgcIEAAAAA==.Ampularecti:BAAALAAECgYIEgAAAA==.',Ar='Argael:BAAALAADCggIEQAAAA==.Arlan:BAAALAADCgcIBwAAAA==.Arpad:BAAALAADCgcIDwAAAA==.Arthon:BAAALAAECgcIEAAAAA==.Aryïa:BAAALAADCggIEwABLAAECggIEQABAAAAAA==.',As='Ashm:BAAALAAFFAIIAgAAAA==.Ashmodai:BAAALAAECgYIDwAAAA==.',Ba='Bacardii:BAAALAAECgcIDwAAAA==.Bash:BAAALAAECgYIDgAAAA==.',Be='Beastheart:BAAALAADCggIEQAAAA==.Beloslava:BAAALAAECgcIEAAAAA==.Benedict:BAAALAADCgEIAQAAAA==.Bestwaifu:BAAALAAECgcIDQAAAA==.',Br='Brainrot:BAAALAAECgcIEwAAAA==.',By='Bystrozraky:BAAALAAECgIIAgABLAAECgcIEAABAAAAAA==.',Ch='Chrome:BAAALAAECgMICwAAAA==.Chytrusek:BAAALAAECgYIEAAAAA==.',Cr='Crx:BAAALAADCgMIBAAAAA==.',Da='Dandarkk:BAAALAAECgIIBAAAAA==.Darkazaar:BAAALAADCggICAABLAAECgYIFAACAG0hAA==.',De='Decap:BAAALAAECgQIBgAAAA==.Deku:BAAALAAECgQIBQAAAA==.Demonwaifu:BAAALAAECgIIAgAAAA==.Deurpaneus:BAAALAADCggICAAAAA==.',Do='Douevendkbro:BAAALAAECggIDgAAAA==.',Dr='Dragalicious:BAAALAAECgYIAwAAAA==.',Ed='Ederologos:BAAALAAECgYICQAAAA==.',Fa='Fate:BAAALAAECgMIAwABLAAFFAIIAgABAAAAAA==.',Fe='Felicja:BAAALAAECgYIDwAAAA==.Feínt:BAAALAADCggICAAAAA==.',Fi='Fittberitbum:BAAALAAECgYICgAAAA==.',Fl='Flabby:BAAALAADCggICQAAAA==.',Fo='Fortianna:BAABLAAECoEWAAIDAAgI0RzxCgAtAgADAAgI0RzxCgAtAgAAAA==.',Fr='Frostone:BAAALAAECgYIEAAAAA==.Frostyflake:BAAALAADCggICgAAAA==.',Go='Goofyclaw:BAAALAAECgYIDQAAAA==.',Gu='Gudrinieks:BAAALAAFFAIIBAAAAA==.',['Gø']='Gødsgift:BAAALAAFFAIIAgAAAA==.',Ha='Havarea:BAAALAADCggIDAABLAAECgcIEgABAAAAAA==.Havran:BAAALAAECgcIEgAAAA==.',Il='Illiilliilli:BAAALAAECgQICQAAAA==.',Im='Imera:BAAALAAECgUICAAAAA==.',Ir='Irí:BAAALAAECgIIAgAAAA==.',Ja='Jadepaws:BAAALAAECgYIEAAAAA==.',Jo='Jodariel:BAAALAADCgYIDAAAAA==.',Ka='Kafzaru:BAAALAAECgUICQAAAA==.Kazzataur:BAAALAAECgIIAgAAAA==.',Kh='Kheiya:BAAALAAECggIEQAAAA==.',Ki='Kihelheim:BAABLAAECoEUAAIEAAgIOCFqDwDpAgAEAAgIOCFqDwDpAgABLAAECggIFQAFAFAdAA==.Kiinai:BAAALAAECgQIBgAAAA==.Killmarosh:BAAALAAECgUIBAAAAA==.',Kr='Krexil:BAAALAAECgYIEAAAAA==.',Kw='Kwazam:BAABLAAECoEUAAMGAAcIchv3DQBFAgAGAAcIchv3DQBFAgAHAAEIhgtoEwA9AAAAAA==.',Ky='Kyzzpope:BAAALAAECgcIDwAAAA==.',La='Lackadeath:BAAALAAECgIIAgAAAA==.',Le='Leccee:BAABLAAECoEVAAIFAAgIUB3EFwCiAgAFAAgIUB3EFwCiAgAAAA==.',Li='Lightshope:BAAALAADCgYIBAAAAA==.Limeblom:BAAALAAECgcIEgAAAA==.',Lo='Louke:BAAALAAECgcIEgAAAA==.',Lu='Luck:BAAALAADCggIEwAAAA==.',Ma='Mark:BAAALAAECgYICgAAAA==.',Me='Medullarum:BAAALAAECgYICgAAAA==.Meimei:BAAALAADCgcIBwAAAA==.Mellody:BAAALAADCgcIEgAAAA==.',Mi='Miggi:BAAALAAECgYIDgAAAA==.Mindedas:BAAALAADCggIDwAAAA==.Minilandswe:BAAALAAECgYICQAAAA==.',Mo='Monolithus:BAAALAAECgMIAwAAAA==.Morrighan:BAAALAADCggIDwAAAA==.',My='Mystie:BAABLAAECoEVAAMIAAcI5R5TCgBHAgAIAAcI5R5TCgBHAgAJAAIIHA/FNQBjAAAAAA==.',['Mä']='Mäsha:BAAALAAECgYICwAAAA==.',Na='Nakali:BAAALAAECgcIEwAAAA==.',Ne='Nelthil:BAAALAAECgQICAAAAA==.',Ny='Nyxe:BAAALAAECgYIBwAAAA==.',Pa='Pagodan:BAAALAADCggIFgAAAA==.',Po='Pokelar:BAAALAAECgUIBAAAAA==.Pokellah:BAAALAADCgEIAQAAAA==.',Pr='Priso:BAAALAAECgYICAAAAA==.',Qa='Qaelithus:BAAALAADCggIEAAAAA==.',Ra='Ragefire:BAAALAAECgMIAwAAAA==.Raspoutin:BAAALAADCgcIBwABLAAECggIEQABAAAAAA==.',Re='Restoration:BAAALAAECgEIAQAAAA==.Retoddid:BAAALAAECgYIEAAAAA==.',Ri='Ril:BAAALAAECgYIEAAAAA==.',Ro='Rohun:BAAALAAECgcIEgAAAA==.',Sa='Sanglord:BAAALAAECgYIDAAAAA==.Sanivam:BAAALAAECgEIAQAAAA==.Sansya:BAAALAAECgcIEwAAAA==.Sardaukar:BAAALAADCggICAAAAA==.',Sc='Scrolls:BAABLAAECoEUAAIKAAcILR9kHgByAgAKAAcILR9kHgByAgAAAA==.Scrooty:BAAALAAECgQICAAAAA==.',Sh='Shallain:BAAALAADCgcIBwABLAAECggICQABAAAAAA==.Shieldheart:BAAALAAECggICQAAAA==.Shogan:BAAALAADCggIFAAAAA==.Shortstack:BAABLAAECoEVAAILAAcI0R1nGQBkAgALAAcI0R1nGQBkAgAAAA==.',Si='Sinvanna:BAAALAADCgEIAQAAAA==.',Sn='Snöret:BAAALAAECgYICgAAAA==.',Su='Suchdotswow:BAAALAADCgEIAQAAAA==.',Te='Tecrapintrei:BAAALAADCggIFQAAAA==.',Th='Therealmcroy:BAAALAAECgYIEAAAAA==.Throrn:BAAALAAECgYIEAAAAA==.',To='Toraz:BAAALAADCgcIBwAAAA==.',Ug='Uglybull:BAAALAADCgYIBgAAAA==.Uglyvulp:BAABLAAECoEbAAMMAAgIKiHgBQD4AgAMAAgImiDgBQD4AgANAAEIFBuQJQBQAAAAAA==.',Un='Unariel:BAAALAADCgMIAwAAAA==.Ungentle:BAAALAAECgMIBgAAAA==.Unohana:BAAALAAECgYIEgAAAA==.',Ut='Uti:BAAALAADCggICwAAAA==.',Va='Varjovasama:BAAALAADCgcIDgAAAA==.',Vo='Voidlord:BAAALAAECgYIDQAAAA==.',Wa='Warpath:BAAALAAECgcIBwAAAA==.Warrwîk:BAAALAAECgQICAAAAA==.',We='Weltiran:BAAALAAECgcIEAAAAA==.',Xa='Xant:BAAALAADCggIDgAAAA==.',Xy='Xynovia:BAAALAADCgMIAgAAAA==.',Ya='Yanâ:BAAALAAECgMIAwAAAA==.',Za='Zaknazaar:BAABLAAECoEUAAICAAYIbSF/GgAyAgACAAYIbSF/GgAyAgAAAA==.Zambarth:BAAALAADCgYICAAAAA==.Zarae:BAAALAAECgYIDgAAAA==.',Ze='Zesvaflown:BAAALAAECgYIDAABLAAECggIFQAFAFAdAA==.',Zh='Zhivotnoto:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end