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
 local lookup = {'Unknown-Unknown','Warrior-Protection','Priest-Holy','Druid-Feral','Paladin-Holy','DemonHunter-Havoc','Mage-Arcane','Warlock-Destruction','Warlock-Affliction','Shaman-Restoration','Shaman-Elemental',}; local provider = {region='EU',realm='Xavius',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abdallahlol:BAAALAADCggICAAAAA==.',Ad='Adi:BAAALAADCgcICQAAAA==.',Ar='Arovs:BAAALAAECgYIDwAAAA==.Artoria:BAAALAADCggICAAAAA==.',Au='Augustus:BAAALAAECgYICwAAAA==.',Ax='Axio:BAAALAAECgIIAgAAAA==.',Ay='Ayizan:BAAALAAECggIDgAAAA==.',Ba='Bacalao:BAAALAADCgYIBQABLAAECgYIDgABAAAAAA==.Barabím:BAAALAAECgcIAQAAAA==.Baradins:BAAALAADCggICAAAAA==.',Be='Beastmeister:BAAALAAECgMIAwAAAA==.Beermaster:BAAALAADCggICAAAAA==.Beliar:BAAALAADCggIDgAAAA==.Betrayèr:BAAALAAECgYIDwAAAA==.',Bl='Bloodborne:BAAALAADCggIEAAAAA==.Bloodyrosa:BAAALAADCgcIBwAAAA==.',Bo='Bobbybrunkuk:BAAALAADCgEIAQAAAA==.Bobthepriest:BAAALAADCgQIBAAAAA==.Bobthetank:BAAALAADCgIIAgAAAA==.Bombarda:BAAALAADCgcIBwAAAA==.Bonebearer:BAAALAADCgcIBwAAAA==.',Br='Brunkuken:BAAALAAECgYIBgAAAA==.',Bu='Bunnyfufu:BAAALAADCgYIBgAAAA==.',['Bå']='Bålkugler:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.',Ca='Cactuss:BAAALAADCgYICAAAAA==.Candymán:BAAALAAECgEIAQAAAA==.',Da='Dagoat:BAAALAAECgYIDAAAAA==.Dalinar:BAAALAAECgIIAQAAAA==.',De='Deathshade:BAAALAADCggICAAAAA==.Deathview:BAAALAAECggIEAAAAA==.Dexii:BAAALAAECgEIAQAAAA==.',Di='Diaga:BAAALAADCggIAQAAAA==.',Dj='Djtwo:BAAALAAECgQIBAAAAA==.',Dr='Dracoelfa:BAAALAADCgEIAQAAAA==.Draconero:BAAALAADCgIIAgAAAA==.Drudru:BAAALAADCgEIAQAAAA==.',Du='Dure:BAAALAADCgIIAgABLAAECgcIDQABAAAAAA==.',Ex='Exort:BAACLAAFFIEHAAICAAMInhpfAQAFAQACAAMInhpfAQAFAQAsAAQKgSYAAgIACAgtJHEBAEIDAAIACAgtJHEBAEIDAAAA.',Fa='Fantasygirl:BAAALAADCgcIBwAAAA==.',Fe='Felwinter:BAAALAADCgIIAgAAAA==.',Fi='Fidoodle:BAAALAADCggICAAAAA==.',Fl='Flannel:BAAALAAECgYIBgAAAA==.Florx:BAAALAAECgYICgAAAA==.',Fr='François:BAAALAADCggICAAAAA==.Frenchie:BAAALAAECgUIBQAAAA==.Frosteyes:BAAALAAECgYICgAAAA==.',Fu='Fuksdeluks:BAAALAAECgcICwAAAA==.',Ga='Gaya:BAAALAADCgMIAwAAAA==.',Gh='Ghila:BAAALAADCggICAAAAA==.',Gi='Gimbrumdwal:BAAALAADCggICAAAAA==.',Gl='Glacialmaw:BAAALAADCgcIBwAAAA==.Glare:BAABLAAECoEVAAIDAAgIcyKTCgCKAgADAAgIcyKTCgCKAgAAAA==.',Gx='Gxy:BAAALAADCgUIBQAAAA==.',Ha='Hardcøre:BAAALAADCggICQAAAA==.',He='Heltsinnes:BAAALAAECgcICAAAAA==.Helya:BAAALAADCgUIBQAAAA==.',Hi='Hiereas:BAAALAADCgYIBgAAAA==.',Im='Imoogi:BAAALAAFFAIIAgABLAAECggIGAAEAE4iAA==.',Ir='Iron:BAAALAADCggIDAAAAA==.',Iv='Ivchony:BAAALAAECgEIAQAAAA==.',Ja='Jayal:BAAALAAECgYICwAAAA==.',Jo='Joelyn:BAAALAADCgEIAQAAAA==.',Ke='Kenthegreat:BAAALAADCgEIAQAAAA==.',Kl='Klokkeblomst:BAAALAAECgYICQAAAA==.Klum:BAAALAADCggIDwAAAA==.',Ko='Kolamola:BAAALAADCgcIBwAAAA==.',Kr='Kriptis:BAAALAADCgQIBAAAAA==.',La='Laddenx:BAAALAADCgYICwAAAA==.Laminia:BAAALAAECgYICgAAAA==.',Le='Leviachan:BAAALAAECgYICQAAAA==.',Li='Lichtfut:BAAALAAECggICgAAAA==.',Lu='Luciefear:BAAALAADCggICAAAAA==.Lufoo:BAAALAADCgcIBwAAAA==.Luicfer:BAAALAADCgMIBQAAAA==.',Ly='Lyra:BAAALAAECgEIAQAAAA==.Lyrà:BAAALAADCggICgABLAAECgEIAQABAAAAAA==.',['Lý']='Lýra:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.',Ma='Mageny:BAAALAADCgcIBwAAAA==.Malaedan:BAAALAADCggICAAAAA==.Malathar:BAAALAADCgIIAgAAAA==.',Me='Meeb:BAAALAAECgYIDgAAAA==.Mentemonk:BAAALAADCgUIBQAAAA==.Merulion:BAAALAADCggICAAAAA==.Messenjaah:BAAALAAECgQIBwAAAA==.Metahelah:BAAALAAECgcIDQAAAA==.',Mo='Mogiie:BAAALAAECgEIAQAAAA==.Moj:BAAALAAECgYIDAAAAA==.',Mw='Mwi:BAAALAAECgEIAQAAAA==.',My='Mylonian:BAAALAADCggICAAAAA==.Myrna:BAAALAAECggIDgABLAAECggIGAAFAO0MAA==.Myrongaines:BAAALAAECggIBgAAAA==.',Na='Nairdan:BAAALAADCgIIAgAAAA==.',Of='Ofrisk:BAABLAAECoEUAAIGAAcIxhvtGABCAgAGAAcIxhvtGABCAgAAAA==.',Ot='Ott:BAAALAAECgMIAwAAAA==.',Ow='Owo:BAAALAADCgIIAQAAAA==.',Ph='Phalynx:BAAALAADCgYIDAAAAA==.Phax:BAAALAAECgUICQAAAA==.Phaxos:BAAALAADCgQIBAAAAA==.Phenome:BAAALAAECgIIAgAAAA==.',Pi='Picikukkpapa:BAAALAADCgUIBQAAAA==.Pilavpowa:BAAALAADCggIDQAAAA==.Pivnoenechto:BAAALAADCgQIBwAAAA==.',Po='Pontiff:BAAALAADCgYICgAAAA==.',['Pä']='Päddy:BAAALAAECgMIBQAAAA==.',Ra='Rachellaa:BAAALAADCggICAAAAA==.Ragnap:BAAALAADCgcIBwAAAA==.Raoden:BAAALAADCgIIAgAAAA==.',Re='Rectifier:BAABLAAECoEgAAIHAAgI/COVAwBBAwAHAAgI/COVAwBBAwAAAA==.Redcloud:BAAALAAECgYICgAAAA==.',Ri='Riams:BAAALAAECgEIAQAAAA==.Riesenriemen:BAAALAADCgYIBgAAAA==.',Ry='Ryuk:BAAALAAECgYIDQAAAA==.',Sa='Saeva:BAAALAADCggICAAAAA==.Sam:BAABLAAECoEVAAMIAAgIJxtQDgB3AgAIAAgI+BhQDgB3AgAJAAEIcBNvKQBLAAAAAA==.Sassy:BAAALAAECggIEgAAAA==.Satudarah:BAAALAAECgYIDwAAAA==.',Sc='Scourgespree:BAAALAAECgcIEAAAAA==.',Se='Serniczek:BAAALAAECgcIDQAAAA==.',Sh='Shatterhoof:BAAALAADCgQIBAAAAA==.Shinazugawa:BAAALAADCgcIBwAAAA==.Shivanizy:BAAALAAECgcIEQAAAA==.',Si='Sigmund:BAAALAADCgcICAAAAA==.Sinic:BAAALAADCgcIBwAAAA==.Siz:BAAALAADCggIEQABLAAECgcICwABAAAAAA==.',Sl='Slaayer:BAAALAADCgQIBAAAAA==.',So='Solfryd:BAAALAAECgYIEQAAAA==.Solutions:BAAALAADCggIFwABLAAECgUIBAABAAAAAA==.Solutionx:BAAALAAECgUIBAAAAA==.Sonicaz:BAAALAAECgUICwAAAA==.',Sp='Spaenk:BAAALAADCggICQAAAA==.Spiritarrow:BAAALAADCgYIBgABLAADCggICgABAAAAAA==.',St='Stinkbreath:BAAALAAECggIAgAAAA==.',Te='Teslatrassel:BAAALAAECgcICgAAAA==.',Th='Thalendris:BAAALAADCgcIBwAAAA==.',Ti='Tissyndeia:BAAALAAECgMIBAAAAA==.',Tm='Tmt:BAAALAAECgQIBwAAAA==.',Tn='Tnt:BAAALAADCgYIBgAAAA==.',To='Tobleon:BAAALAAECgcIDgAAAA==.Tossler:BAABLAAECoEUAAMKAAcIWQ8YNQBQAQAKAAcIWQ8YNQBQAQALAAMIqAFvSwBrAAAAAA==.Tovah:BAAALAADCggICQAAAA==.Tovaro:BAAALAADCgYICwABLAADCggICQABAAAAAA==.',Tu='Tutankamoon:BAAALAAECgYIBwAAAA==.',Ty='Tyríon:BAAALAADCgYIBgAAAA==.',Uk='Ukrotitelj:BAAALAAECgYIDgAAAA==.',Un='Untitledone:BAAALAAECgIIAgAAAA==.',Va='Vanilor:BAAALAAECgEIAQAAAA==.Vankisa:BAAALAAECgcICAAAAA==.Vasher:BAAALAADCgcIBwAAAA==.',Ve='Velrathis:BAAALAADCgUICAAAAA==.Verbati:BAAALAAECgcICwAAAA==.Veresaa:BAAALAAECgEIAQAAAA==.',Vi='Vidov:BAAALAADCgMIAwAAAA==.',Vl='Vladimiry:BAAALAAECgUICAAAAA==.',Vy='Vynvalin:BAAALAADCggICAAAAA==.',['Vå']='Vårlök:BAAALAADCgUIBQAAAA==.',Wa='Waxillium:BAAALAAECgMIBAAAAA==.Wayne:BAAALAADCggIFQAAAA==.',We='Welehu:BAAALAAECgYIBgAAAA==.',Wi='Wingedhavoc:BAAALAADCgUIBQAAAA==.',Wo='Wolfixia:BAAALAADCgQIBAAAAA==.',Xo='Xoduz:BAAALAAFFAEIAQAAAA==.',Za='Zalisrcemoje:BAAALAADCggICAAAAA==.',Zh='Zhaenya:BAAALAADCgcIBwAAAA==.',Zo='Zoraide:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end