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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','Monk-Windwalker','Mage-Fire','Druid-Feral','Druid-Balance','Warrior-Arms','Shaman-Enhancement','Rogue-Subtlety','Paladin-Holy','Shaman-Elemental','Monk-Mistweaver',}; local provider = {region='EU',realm='Anetheron',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abendstille:BAAALAAECgYIDQAAAA==.Abistir:BAAALAADCgMIAwAAAA==.',Ac='Ace:BAAALAAECgYIDAAAAA==.',Ad='Adolar:BAAALAADCgQIBAAAAA==.',Aj='Ajur:BAAALAAECgIIAwAAAA==.',Ak='Akalí:BAAALAAECgYICAAAAA==.Akane:BAAALAADCgIIAgABLAAECgYIBgABAAAAAA==.',Al='Alisyá:BAAALAADCggIFwAAAA==.Aloccola:BAAALAAECgMIBAAAAA==.Altius:BAAALAAECgMIBQAAAA==.',Ap='Apschaladla:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.',Aq='Aquíla:BAAALAADCggIFwAAAA==.',Ar='Ararat:BAAALAAECgYIDgABLAAECggIFQACAMkdAA==.Arrowynn:BAAALAAECgIIAgAAAA==.',As='Asheop:BAAALAADCgUIBwAAAA==.Aszraa:BAAALAADCgcICAAAAA==.',Av='Avîella:BAAALAAECgcIDQAAAA==.',Ax='Axepai:BAAALAADCggICAAAAA==.',Ay='Ayumah:BAAALAAECgUIBgAAAA==.',Az='Azrail:BAAALAAECgIIAgAAAA==.',['Aé']='Aéro:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',Ba='Baelamina:BAAALAAECgMIAwAAAA==.Baimei:BAAALAADCgcIBwAAAA==.Baldorr:BAAALAAECgYICwAAAA==.Baltier:BAAALAADCggICgAAAA==.Balín:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.',Be='Beaca:BAAALAADCgUICQAAAA==.Beechén:BAAALAAECgQIBgAAAA==.Beelzebubb:BAAALAAECgYIDQAAAA==.',Bi='Bierfräsn:BAAALAAECgEIAQAAAA==.',Br='Bratlainly:BAAALAADCggIHwABLAAECgYICgABAAAAAA==.Braumeîster:BAAALAAECggIDAAAAA==.Brei:BAAALAAECgMIBAABLAAECgYIGAADADIgAA==.',Bu='Buthead:BAAALAADCgcICwAAAA==.',['Bî']='Bîrndl:BAAALAADCgUICgAAAA==.',Ca='Cae:BAAALAAECggICAAAAA==.Capslôck:BAAALAAECgMIBQAAAA==.Cartne:BAAALAADCggIDQAAAA==.',Ce='Cerebrum:BAAALAAECgYICgAAAA==.',Cl='Cloud:BAAALAAECgQIBAAAAA==.',Co='Cokí:BAAALAAECgMIBAAAAA==.Colibriee:BAAALAADCgQIBAAAAA==.',Cr='Crowley:BAABLAAECoEVAAIEAAgISQSnBABdAQAEAAgISQSnBABdAQAAAA==.Crysanthem:BAAALAAFFAIIAgAAAA==.',Da='Darkdämona:BAAALAAECgYICAAAAA==.Darkillaa:BAAALAAECgMIBgAAAA==.Darksigon:BAAALAAECgMIBAAAAA==.',De='Deelii:BAABLAAECoEUAAICAAcIYR0NFwBfAgACAAcIYR0NFwBfAgAAAA==.Deeps:BAAALAADCgEIAQAAAA==.Deldar:BAAALAADCgUICgAAAA==.Demonbat:BAAALAADCggICQAAAA==.Derbrain:BAAALAAECgMIBQAAAA==.',Dr='Drákstár:BAAALAADCgYIAgABLAAECgcIFAACAGEdAA==.',Ei='Eisenring:BAAALAADCgcIBwAAAA==.',El='Elementri:BAAALAAECgUIBQAAAA==.',Es='Essence:BAAALAADCgYIBgABLAAECgcIFAAFAKckAA==.',Eu='Euda:BAAALAADCgMIAwAAAA==.',Fa='Falling:BAAALAAECgUICAAAAA==.Fatzke:BAAALAAECgYICQAAAA==.',Fe='Fearthyr:BAAALAAECgMIBQAAAA==.',Fi='Fil:BAAALAADCgcIBwAAAA==.Firana:BAAALAADCgcIBQAAAA==.',Fu='Fuhrmann:BAAALAAECgMIBAAAAA==.',Ga='Gainera:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Gainz:BAAALAADCgUIBwAAAA==.Garghoul:BAAALAAECgMIBAAAAA==.',Gi='Ginewà:BAAALAAECgEIAQAAAA==.',Gl='Globalmodel:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.',Go='Gothgirl:BAAALAAECgYIBgAAAA==.',Gr='Grashüpfer:BAAALAAECgMIAwAAAA==.',Gu='Gudndag:BAAALAAECgIIAwAAAA==.Gummibærchen:BAABLAAECoEZAAIGAAcIvSQUBwDdAgAGAAcIvSQUBwDdAgAAAA==.Gurnisson:BAAALAAECgIIAgAAAA==.',Ha='Hardexx:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Hauminet:BAAALAADCgUICgAAAA==.Havocfeelya:BAAALAADCgMIAQAAAA==.',He='Hellifax:BAAALAAECgMIBgAAAA==.',Hi='Himmel:BAAALAADCgYIBgAAAA==.',Ic='Icecube:BAAALAADCgcIBwAAAA==.',Ig='Ignit:BAAALAADCggICwAAAA==.',Im='Immortalem:BAAALAAFFAMIAwAAAA==.',Ip='Ipunishu:BAAALAADCggICAAAAA==.',Jo='Jojoloco:BAAALAADCggICAAAAA==.',Ju='Juma:BAAALAAECgYICgAAAA==.',Ka='Kadalar:BAAALAADCgcIBwAAAA==.Kap:BAAALAADCggIFwAAAA==.',Ke='Keluna:BAAALAAECgMIBQAAAA==.',Ki='Kili:BAAALAAECgYIBwAAAA==.Kishi:BAAALAADCgUICgAAAA==.',Kn='Knippeldicht:BAABLAAECoEXAAIHAAcIthrjAwAWAgAHAAcIthrjAwAWAgAAAA==.',Ko='Koljadk:BAAALAAECgYIDgAAAA==.Kopfschmerz:BAAALAAECgcIEwAAAA==.Kornholio:BAAALAAECgUICAAAAA==.',Kr='Kragnarr:BAAALAAECgIIAwAAAA==.Krotau:BAAALAADCgYICwAAAA==.Krämon:BAAALAADCgUIBgABLAADCgYICwABAAAAAA==.',Ku='Kuhluntas:BAAALAADCgYIBgAAAA==.',Ky='Kyany:BAAALAAECgYICQAAAA==.Kyojuro:BAAALAADCggIFAAAAA==.Kyril:BAAALAADCggIFQABLAAECgMIBAABAAAAAA==.Kyscha:BAAALAAECggICwAAAA==.Kyushu:BAAALAAECgMIAwAAAA==.',La='Laetheln:BAAALAAECgMIBQAAAA==.',Le='Leilas:BAAALAADCgUIBgAAAA==.Leverius:BAAALAADCgMIAwAAAA==.Levús:BAAALAADCgcIEQAAAA==.',Li='Linea:BAAALAAECgYICQAAAA==.',Lo='Lolshock:BAABLAAECoEWAAIIAAgIuiBQAQAOAwAIAAgIuiBQAQAOAwAAAA==.',Lu='Luczin:BAAALAADCgUICgAAAA==.',Ly='Lycaon:BAAALAADCggICAABLAAECgcIFAAFAKckAA==.',['Lì']='Lìchtkìng:BAAALAAECggIDAAAAA==.',['Lÿ']='Lÿfaeâ:BAAALAADCgMIAQAAAA==.',Ma='Magnesium:BAAALAADCggICAAAAA==.Mainhunter:BAAALAADCggICAAAAA==.Manhunter:BAAALAADCgYIBgAAAA==.Maritius:BAAALAAECgYICQAAAA==.',Me='Megadeath:BAAALAAECgYIDQAAAA==.Megumii:BAAALAADCgQIBAAAAA==.Mehli:BAAALAAECgYICgAAAA==.',Mi='Mikio:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Milim:BAAALAADCggICAAAAA==.Mistborn:BAAALAADCggICAAAAA==.Mitrusa:BAAALAADCgcIDQAAAA==.',Mo='Monro:BAAALAAECgEIAQAAAA==.Mordeop:BAAALAADCggICAAAAA==.Morgdilla:BAAALAAECgYIBgAAAA==.',Mu='Muy:BAAALAAECgUIBwABLAAECgYIGAADADIgAA==.',Na='Nachtgrimm:BAAALAAECgMIBAAAAA==.Nashoba:BAAALAAECgMIBAAAAA==.Nathrendil:BAAALAAECgYICgAAAA==.',Ni='Nihri:BAAALAAECgcIDQAAAA==.Nijx:BAABLAAECoEOAAIJAAYIlA72CgBcAQAJAAYIlA72CgBcAQAAAA==.Nilenn:BAAALAADCgYICQABLAAECgcIFAACAGEdAA==.',Nu='Nunubaum:BAAALAAECgYICgAAAA==.',Ny='Nymeria:BAAALAAECgIIAgAAAA==.Nypàax:BAAALAAECgIIAgAAAA==.',['Ná']='Náinn:BAAALAAECgIIAgABLAAECggIFQAKAI0SAA==.',['Né']='Néâ:BAAALAADCggIFQAAAA==.',Ok='Oktobär:BAAALAADCggICAAAAA==.',Om='Omertà:BAAALAADCggICAABLAAECggIFQACAMkdAA==.',Or='Orea:BAAALAADCggICAAAAA==.',Os='Ossaya:BAACLAAFFIEMAAILAAYI4BdEAABMAgALAAYI4BdEAABMAgAsAAQKgRgAAgsACAjiJZ0AAIYDAAsACAjiJZ0AAIYDAAAA.',Ot='Otz:BAAALAAECgYICgAAAA==.',Ow='Owiwan:BAAALAADCggICgAAAA==.Owíwan:BAAALAAECgEIAQAAAA==.',Pa='Paldana:BAAALAADCgIIAgAAAA==.',Pd='Pddly:BAAALAAECgcIEAAAAA==.',Pu='Puddl:BAAALAADCggIDgABLAAECgcIEAABAAAAAA==.Puddli:BAAALAAECgQIBAABLAAECgcIEAABAAAAAA==.Puenktcheen:BAAALAADCgYIBgAAAA==.Pussti:BAAALAAECgEIAQAAAA==.',Pw='Pwnmnk:BAAALAAECgMIBgAAAA==.',Qu='Quaigon:BAAALAADCgcICgAAAA==.',Ra='Rawr:BAAALAAECgIIAgAAAA==.Rawsteak:BAAALAADCggICAAAAA==.',Re='Reesy:BAAALAADCgEIAQAAAA==.',Ri='Rikka:BAAALAAECgMICAAAAA==.Riku:BAAALAAECgYIBgAAAA==.',Ro='Roqu:BAACLAAFFIELAAIMAAYIRAs4AADzAQAMAAYIRAs4AADzAQAsAAQKgRgAAgwACAhmIRsCAAYDAAwACAhmIRsCAAYDAAAA.Roxî:BAAALAAECgMIBgAAAA==.',Ry='Ryuná:BAAALAAECgYIBwAAAA==.Ryò:BAAALAAECgYIDgAAAA==.',Sa='Sand:BAAALAAECgIIAgAAAA==.',Se='Senfgurke:BAAALAADCggIDgAAAA==.Sengsi:BAAALAADCgEIAQAAAA==.Sentient:BAAALAAECgMIBwAAAA==.',Sh='Shadowfist:BAAALAADCggICAAAAA==.Shanei:BAAALAAECgEIAQAAAA==.Sharon:BAAALAADCgUIBQAAAA==.Shax:BAAALAAECgMIBAAAAA==.Shàdów:BAAALAADCggIDwAAAA==.',Si='Sinopa:BAAALAAECgEIAQAAAA==.',Sl='Slevìn:BAAALAADCggIFAAAAA==.Slizar:BAAALAAECgYICAAAAA==.Slow:BAAALAAECgQIBgAAAA==.',Sn='Snowblinder:BAAALAAECgYIBwAAAA==.Snowøwhite:BAAALAADCggICAAAAA==.Snúffy:BAAALAADCggICAAAAA==.',So='Solominati:BAAALAADCgcICAAAAA==.',Su='Suarok:BAAALAAECgMIAwAAAA==.Sugar:BAABLAAECoEVAAICAAgIyR22FgBiAgACAAgIyR22FgBiAgAAAA==.',['Sè']='Sèkèh:BAAALAADCgYIBgAAAA==.',['Sí']='Sírrollalot:BAAALAADCggICAAAAA==.',['Sý']='Sýd:BAAALAAECgMIBgAAAA==.',Ta='Talnazhar:BAAALAAECgQIBgAAAA==.Tanaka:BAAALAADCgcICAAAAA==.Tanathos:BAAALAAECgMIBAAAAA==.',Te='Teddywulf:BAAALAADCggICAAAAA==.Terestrior:BAABLAAECoEVAAIKAAgIjRIrDAAWAgAKAAgIjRIrDAAWAgAAAA==.Teruka:BAAALAAECgYIBwAAAA==.',Th='Thedaemon:BAAALAADCgEIAQAAAA==.Theresa:BAAALAADCgcIBwAAAA==.Thraín:BAAALAADCggIDgABLAAECgYIBwABAAAAAA==.',Ti='Tigersclaw:BAAALAAECgMIAwAAAA==.',Tr='Trillion:BAAALAAECgQIBwAAAA==.',Ts='Tschaba:BAAALAADCggICAAAAA==.',Ty='Tyrionas:BAAALAADCggIEgAAAA==.',['Tî']='Tîenchen:BAAALAAECgMIBwAAAA==.',Va='Vaelthas:BAAALAADCgcIBwAAAA==.Valento:BAAALAAECgMIBQAAAA==.Vashthedevil:BAAALAADCggIDQAAAA==.',Vi='Villeroy:BAAALAADCgUIBQAAAA==.Virtuoso:BAAALAADCggIEAAAAA==.',Vr='Vraagar:BAAALAAECgQIBwAAAA==.',Wo='Wogen:BAAALAADCggIDQAAAA==.Wogon:BAABLAAECoEUAAIFAAcIpySTAgDiAgAFAAcIpySTAgDiAgAAAA==.',Wu='Wubbel:BAAALAAECgcIDwAAAA==.',Xa='Xarfai:BAAALAADCgcIBwAAAA==.',Xr='Xrage:BAAALAAECgYIEgAAAA==.',Yi='Yinaya:BAACLAAFFIEFAAIMAAMIOxBIBQCcAAAMAAMIOxBIBQCcAAAsAAQKgRcAAgwACAjRG3AGAHICAAwACAjRG3AGAHICAAAA.',Ym='Ymhitra:BAAALAADCggIEQABLAAECgYICAABAAAAAA==.',Yo='You:BAAALAAECggICAAAAA==.',Yu='Yum:BAABLAAECoEYAAMDAAYIMiBzCQA/AgADAAYIMiBzCQA/AgAMAAYIFxsFDwCqAQAAAA==.',Za='Zahnpasta:BAAALAAECgYIBgAAAA==.',Ze='Zenduran:BAAALAAECgYIEQAAAA==.',Zh='Zhinn:BAAALAAECgYIDQAAAA==.',Zi='Ziim:BAAALAAECgYIBgAAAA==.',Zu='Zunný:BAAALAADCggICAAAAA==.',Zw='Zwoluntas:BAAALAAECgYIBwAAAA==.',['Zä']='Zäpfli:BAAALAAECgIIAwAAAA==.',['Ãc']='Ãce:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end