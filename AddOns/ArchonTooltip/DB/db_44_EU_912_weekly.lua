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
 local lookup = {'Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Monk-Windwalker','Evoker-Devastation',}; local provider = {region='EU',realm='Ner’zhul',name='EU',type='weekly',zone=44,date='2025-09-01',data={Ad='Adrianna:BAAALAAECgMIBgAAAA==.',Ae='Aeternum:BAAALAAECgMIAwAAAA==.',Ar='Arise:BAAALAADCgQIBAAAAA==.Arîana:BAAALAADCggICAABLAAECgcICgABAAAAAA==.',Az='Azoth:BAAALAAECgMIAwAAAA==.',Ba='Baboom:BAAALAAECgMIAwAAAA==.Bamboklat:BAAALAAECgYIDQAAAA==.Bastet:BAAALAADCggICAABLAAECgcICgABAAAAAA==.Bazile:BAAALAAECgcICgAAAA==.',Bi='Bigdrake:BAAALAADCgEIAQAAAA==.Bigone:BAAALAADCggIDAAAAA==.Biothopie:BAAALAADCggIFQAAAA==.Bipodactyle:BAAALAAECgYICAAAAA==.Biproselyte:BAAALAAECgIIAgABLAAECgYICAABAAAAAA==.Biwaa:BAAALAADCgMIAwABLAAECgcIEAABAAAAAA==.Biwaamage:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Biwaapriest:BAAALAAECgcIEAAAAA==.',Bl='Blacklagoon:BAAALAAECgYIDgAAAA==.Bliitz:BAAALAAECgUIBQAAAA==.Blyyat:BAAALAAECgcIDwABLAAECgUIBQABAAAAAA==.',Bu='Bubulteypey:BAAALAAECgIIAgAAAA==.',Bw='Bwonsamedi:BAAALAAECggICAAAAA==.',Ca='Carpouette:BAAALAAECgMIAwAAAA==.Caxu:BAAALAADCggIFgAAAA==.',Ce='Cetearyl:BAAALAAECgYIBwAAAA==.',Ch='Choupinouze:BAAALAAECgUICwAAAA==.',Cu='Cutch:BAAALAAECgMIAwAAAA==.',Da='Daerkhan:BAAALAAECgMIAwAAAA==.Dafykrue:BAAALAAECgYIDAAAAA==.Dak:BAAALAADCggIFAAAAA==.Darugal:BAAALAAECgEIAQAAAA==.',De='Demønø:BAAALAAECgUIBgAAAA==.',Do='Dobozz:BAAALAADCgYIBgAAAA==.Dohko:BAAALAAECgIIBAAAAA==.Dominas:BAAALAADCgUIBQAAAA==.',Dr='Drakay:BAAALAAECgEIAQAAAA==.Dreanessa:BAAALAADCgUIBQAAAA==.Drifer:BAACLAAFFIELAAMCAAUIhxa6AAB/AQACAAQIkBO6AAB/AQADAAIItxinAQCzAAAsAAQKgRgAAwMACAgsJJoAAD8DAAMACAgsJJoAAD8DAAIABwgFES4XANwBAAAA.Drifermop:BAAALAAECggIDwABLAAFFAUICwACAIcWAA==.Druo:BAAALAAECgMIBAAAAA==.',Ed='Edde:BAAALAAECgYIBgAAAA==.',Ei='Eisenfaust:BAAALAAECgUIBwAAAA==.',Er='Erudk:BAAALAAECgMIAwAAAA==.Erupal:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.',Es='Espritdesam:BAAALAAECgMIBgAAAA==.',Ev='Evanessor:BAAALAADCgQIBAAAAA==.',Ex='Exalty:BAAALAAECgMIAwAAAA==.',Ez='Ezrim:BAAALAADCgEIAQAAAA==.',Fa='Falorendal:BAAALAADCgQIBAAAAA==.',Fe='Febreze:BAAALAAECgcIEwAAAA==.',Fl='Flökki:BAAALAAECgcIBwAAAA==.',Fu='Funkystar:BAAALAAECgcIEAAAAA==.',Ge='Genødrakcide:BAAALAADCggICwAAAA==.Geronïmo:BAAALAAECgMIAwAAAA==.Geumjalee:BAABLAAECoEVAAIEAAgIMx9KBADcAgAEAAgIMx9KBADcAgAAAA==.',Go='Gonfeï:BAAALAAECgMIBgAAAA==.',Gr='Grantrouble:BAAALAAECgEIAQAAAA==.Grishnàkh:BAAALAAECgMIAwAAAA==.Groumm:BAAALAAECggIDwAAAA==.Grëg:BAAALAAECgMIBQAAAA==.',Gu='Guldhin:BAAALAAECggICAAAAA==.Gusttox:BAAALAAECggIAQAAAA==.',Ha='Haeven:BAAALAADCgcIBwAAAA==.Hauktt:BAAALAAECgYICgAAAA==.',He='Herumor:BAAALAAECgIIAgAAAA==.',Ho='Hoopi:BAAALAADCgYICQAAAA==.Hopa:BAAALAADCgcIEwAAAA==.Hopium:BAAALAADCgYICwAAAA==.',Hu='Hunei:BAAALAAECggIDgAAAA==.',Hy='Hypso:BAAALAADCgcIDAAAAA==.',Il='Illidalol:BAAALAAECggIEQAAAA==.',It='Itersky:BAAALAAECgYIBgAAAA==.',Je='Jeandh:BAAALAADCggICQAAAA==.',Jh='Jhereg:BAAALAAECgYIBgAAAA==.',Ji='Jigsaw:BAAALAAECgUICAAAAA==.Jimmy:BAAALAAECgEIAQAAAA==.',Ka='Kamewar:BAAALAADCgcIDAAAAA==.',Kb='Kbossé:BAAALAADCgYIBwAAAA==.',Kh='Khidra:BAAALAAECgUIBwAAAA==.',Ki='Kiose:BAAALAADCgQIBwAAAA==.Kishar:BAAALAADCgQIBAAAAA==.',Km='Kmenbert:BAAALAADCgcIDgAAAA==.Kmouflé:BAAALAADCggIDwAAAA==.',Kt='Ktastrophe:BAAALAADCgcIDAAAAA==.',Ku='Kurùn:BAAALAAECgYICgABLAAECggIFQAEADMfAA==.',La='Lali:BAAALAADCgIIAgAAAA==.',Li='Lilyguana:BAAALAAECgYIDgABLAAFFAIIBQAFAJEQAA==.Lilyzard:BAACLAAFFIEFAAIFAAIIkRBLBwCbAAAFAAIIkRBLBwCbAAAsAAQKgRcAAgUACAhLH0cIAKwCAAUACAhLH0cIAKwCAAAA.Livin:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Lizyrio:BAAALAAECggIEQAAAA==.',Lo='Lomy:BAAALAAECgIIAgAAAA==.',Ly='Lyneeth:BAAALAAECgMIAwAAAA==.',Ma='Maggnux:BAAALAAECgYICQAAAA==.Mallyn:BAAALAAECggICAAAAA==.Martyr:BAAALAAECggIEAAAAA==.',Me='Mekerspal:BAAALAAECgMIBAAAAA==.',Mo='Molten:BAAALAAECgIIAgAAAA==.Moonlight:BAAALAAECgYICgAAAA==.',['Mé']='Méphie:BAAALAAECgMIAwAAAA==.',No='Nonobox:BAAALAAECgYICgAAAA==.Norm:BAAALAAECgMIBgAAAA==.',['Nø']='Nøün:BAAALAAECgYIBwAAAA==.',Ob='Obscurie:BAAALAAECgIIAgAAAA==.',Og='Ogyrajiu:BAAALAAECgcIEAAAAA==.Ogyraju:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.',Ol='Olgah:BAAALAAECgYICgAAAA==.',Or='Oracle:BAAALAADCggIEQAAAA==.Oroshimarru:BAAALAADCgYIBgABLAAFFAIIBQAFAJEQAA==.',Pa='Pacounet:BAAALAAECgcICwAAAA==.Palyatiff:BAAALAAECgYIBwAAAA==.Pandemania:BAAALAAECgcICgAAAA==.',Pe='Pensé:BAAALAAECgQIBAAAAA==.Percevaal:BAAALAAECgUIBQAAAA==.Perssone:BAAALAADCggIEgAAAA==.',Pi='Piegeaøurs:BAAALAAECgYIBwAAAA==.',Po='Pourtoibb:BAAALAADCggICAAAAA==.',Ra='Razi:BAAALAAECgMIBwAAAA==.',Ry='Ryanthusar:BAAALAAECgMIAwAAAA==.',['Rê']='Rêtbull:BAAALAAECgMIBgAAAA==.',Se='Seclad:BAAALAADCggIDgAAAA==.',Sh='Shadowbursts:BAAALAAECggIDgAAAA==.Shamy:BAAALAADCggIFQAAAA==.Shangøo:BAAALAADCggIKAAAAA==.Sharenn:BAAALAADCgUIBQAAAA==.Sharkilol:BAAALAAECgMIBQAAAA==.Sharkiz:BAAALAADCggICAAAAA==.Shæmus:BAAALAAECgMIAwAAAA==.',Si='Sidiouz:BAAALAAECgYIDgAAAA==.Silentðeath:BAAALAAECgMIBgAAAA==.',Sk='Skuggor:BAAALAAECgUICQAAAA==.',So='Solk:BAAALAAECgYIEAAAAA==.Sonofmorkh:BAAALAAECgMIAwAAAA==.Sorann:BAAALAAECgUIBQABLAAECgYICgABAAAAAA==.',Sp='Spunkmeyer:BAAALAAECgEIAgAAAA==.',St='Sticouette:BAAALAADCggICAABLAADCggIJAABAAAAAA==.Stix:BAAALAADCggIJAAAAA==.Stonefree:BAAALAAECgUICgAAAA==.',Su='Sukisck:BAAALAAECgYIDAAAAA==.',Sw='Swän:BAAALAAECgYIBgAAAA==.',Te='Tetvide:BAAALAAECgcIEAAAAA==.',To='Tourm:BAAALAAECgYIDgAAAA==.',Tr='Trukidemont:BAAALAAECgYIDgAAAA==.Trâfalgar:BAAALAAECgYIBwAAAA==.',['Tä']='Täräh:BAAALAAECgEIAQAAAA==.',['Tø']='Tøyesh:BAAALAADCgUIBAAAAA==.',Va='Valaraukar:BAAALAADCggICAABLAAECggICAABAAAAAA==.',Ve='Ved:BAAALAAECgYICgAAAA==.Vespéro:BAAALAAECgMIAwAAAA==.',Wa='Wastrack:BAAALAAECgMIBgAAAA==.',['Xä']='Xämena:BAAALAAECgEIAgAAAA==.',Ze='Zephs:BAAALAADCgYIBgAAAA==.',Zo='Zomjyroth:BAAALAAECgMIBQAAAA==.',['Ål']='Åldebaron:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end