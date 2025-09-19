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
 local lookup = {'Unknown-Unknown','Priest-Holy','Shaman-Enhancement','Shaman-Restoration','Warlock-Destruction',}; local provider = {region='EU',realm='Rashgarroth',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abhaya:BAAALAADCggIEAAAAA==.',Am='Amenadiell:BAAALAAFFAMIBQAAAQ==.Amogue:BAAALAADCgcIDgABLAAFFAMIBQABAAAAAQ==.',An='Annäk:BAAALAADCgYIBwAAAA==.Any:BAAALAADCgcIBwAAAA==.',Ar='Archaos:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.Artöss:BAAALAAECgYICwAAAA==.',['Aë']='Aëlnara:BAACLAAFFIEFAAICAAMIvRTsCACtAAACAAMIvRTsCACtAAAsAAQKgRcAAgIACAgTHaMJAKACAAIACAgTHaMJAKACAAAA.',Ba='Basmet:BAAALAAECgQIBgAAAA==.Bassecote:BAAALAAECgMIAwAAAA==.',Bg='Bgreggore:BAAALAADCgcIBgABLAAECgUIBgABAAAAAA==.Bgregoraa:BAAALAADCggIEQABLAAECgUIBgABAAAAAA==.Bgregore:BAAALAAECgUIBgAAAA==.',Br='Branbylon:BAAALAADCgMIAwAAAA==.Brigatmicron:BAAALAADCggIEgAAAA==.',Ca='Cassetibiat:BAAALAADCgcIBwAAAA==.',Ch='Chaûssette:BAAALAADCggIFwAAAA==.Chupimord:BAAALAAECgYIBgABLAAECgYICgABAAAAAA==.',De='Demoby:BAAALAAECgYICgAAAA==.',Di='Diennain:BAAALAADCggICAAAAA==.Dienno:BAAALAAECgIIAgAAAA==.',Do='Dodolina:BAAALAADCggIBQAAAA==.',Dr='Dracochupi:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.',Ds='Dsemoor:BAAALAADCgcIBwAAAA==.',Ei='Eileen:BAAALAAECgMIAwAAAA==.',El='Elelalarera:BAAALAAECgEIAQAAAA==.',Em='Emäne:BAABLAAECoEZAAMDAAgIch+9AQDtAgADAAgIch+9AQDtAgAEAAgIAQQpRAAdAQAAAA==.',Fe='Feemdemon:BAAALAADCggIEQAAAA==.',Fi='Fizkefaaz:BAAALAAECgUICAAAAA==.',Fl='Flørthas:BAAALAADCgcIBwAAAA==.',Fo='Foxjing:BAAALAADCgYIBgAAAA==.',Fr='Frag:BAAALAADCgEIAQAAAA==.',Ga='Gallia:BAAALAADCgcIEgAAAA==.Gaïa:BAAALAAECgYIDgAAAA==.',Gi='Gimiekiss:BAAALAADCggIEAAAAA==.',Gy='Gypox:BAAALAAECgIIAgAAAA==.',Ha='Hazumi:BAAALAAECgYICwABLAAECgYIDwABAAAAAA==.',He='Healmoibibi:BAAALAADCgcIBwAAAA==.Heroneus:BAAALAADCgcICAAAAA==.Hethari:BAAALAADCggICAAAAA==.',Hy='Hylune:BAAALAADCgcIBwAAAA==.',Ic='Iceko:BAAALAADCgEIAQAAAA==.Icekonen:BAAALAAECgMIBgAAAA==.',Im='Immortalius:BAAALAAECgYIDgAAAA==.',Ka='Kafrina:BAAALAADCgcIBwAAAA==.Karolika:BAAALAAECgYICAAAAA==.Kawaah:BAAALAADCgQIBgABLAADCgcIDQABAAAAAA==.Kawabomba:BAAALAADCgcIDQAAAA==.Kawakawa:BAAALAADCgcIBwABLAADCgcIDQABAAAAAA==.',Ki='Kiros:BAAALAADCggIDAAAAA==.',Ko='Kokabiel:BAAALAADCgcIFQAAAA==.',Kr='Kronakaï:BAAALAAECgYIBwAAAA==.Kroubou:BAAALAAECgIIAgAAAA==.',La='Lancetre:BAAALAAECgIIAgAAAA==.Lauryne:BAAALAAECgYICgAAAA==.',Le='Lebôn:BAAALAADCgEIAQAAAA==.',Li='Lightalius:BAAALAADCgEIAQAAAA==.Linorias:BAAALAADCgIIAgAAAA==.',Lo='Lookram:BAAALAADCggICAAAAA==.',Lu='Luxunofwu:BAAALAADCggIFQAAAA==.',Ma='Maasdormu:BAAALAADCggIEAAAAA==.',Mu='Muthraad:BAAALAADCgUIBQABLAAFFAMIBQABAAAAAQ==.',My='Myria:BAAALAAECgQIBgAAAA==.',['Mé']='Méluzyne:BAAALAAECgMIBgAAAA==.Métanor:BAAALAADCgIIAgAAAA==.',Na='Nabräd:BAAALAAECgMIBgAAAA==.Nax:BAAALAAECgYICAAAAA==.',Ni='Nico:BAAALAADCgcIDgAAAA==.',No='Nodoka:BAAALAADCggIFgAAAA==.',Ob='Obak:BAAALAAECgcIBwAAAA==.',Or='Orcbölg:BAAALAAECgMIAwAAAA==.',Pa='Parcoeur:BAAALAADCggIFAAAAA==.',Pi='Pitipenda:BAAALAAECgYICwAAAA==.',Po='Poulpitus:BAAALAAECgcIDwAAAA==.',['Pä']='Pänørãmîxøø:BAAALAADCgYIBgABLAAECgMIAgABAAAAAA==.',Qu='Quasar:BAAALAAECgMIAwAAAA==.',Ra='Raashgaroth:BAAALAAECgMIAwAAAA==.',Rh='Rhoetas:BAAALAAECgQIBAAAAA==.',Ri='Ridback:BAAALAADCggIDAAAAA==.Rindaman:BAAALAAECgIIAgAAAA==.',Ro='Rocket:BAAALAADCgMIAwAAAA==.Rokumine:BAAALAADCggICQAAAA==.Romsh:BAAALAADCggICAAAAA==.',Ry='Rynor:BAAALAADCgYIBgAAAA==.',['Rô']='Rôxxane:BAAALAAECgMIAwAAAA==.',['Rø']='Røxxànne:BAAALAAECgIIAgAAAA==.',Sa='Sachi:BAAALAAECgYIDwAAAA==.Salcon:BAAALAAECgcIEQAAAA==.Sarkas:BAAALAADCggICAABLAAFFAMIBQABAAAAAQ==.',Se='Selkis:BAAALAAECgIIAgAAAA==.',Sh='Shamaladin:BAAALAAECgcIEAAAAA==.Shinratensei:BAAALAADCggICAAAAA==.',Sl='Sltatous:BAAALAADCgMIAwAAAA==.',Su='Submoneyy:BAAALAADCgEIAQAAAA==.Submôney:BAAALAADCgMIBAAAAA==.',Ta='Tagtag:BAAALAAECgcICwAAAA==.',Te='Texfists:BAAALAADCggIEAABLAAFFAMIBQABAAAAAQ==.',Th='Thelassir:BAAALAAECgYIDQAAAA==.',To='Toitucreuses:BAAALAAECgEIAQAAAA==.',Tr='Trunkss:BAAALAADCggIDgAAAA==.',Tu='Tundershaman:BAAALAAECgIIAgAAAA==.',Ty='Tyaline:BAAALAADCgQIBAAAAA==.',Ve='Veldeptus:BAAALAAECgEIAQAAAA==.',Vi='Viineas:BAAALAADCgIIAgAAAA==.',Vo='Voljans:BAABLAAECoEXAAIFAAgI6RTKGQACAgAFAAgI6RTKGQACAgAAAA==.',Vu='Vulcapal:BAAALAAECgYICwAAAA==.',['Vî']='Vîrgin:BAAALAAECggIEAAAAA==.',Wi='Winnilourson:BAAALAADCgcIBwAAAA==.',Yo='Yodidi:BAAALAADCgUIBQAAAA==.',['Yø']='Yøndû:BAAALAADCgYICgAAAA==.',Za='Zangÿa:BAAALAAECgMICAAAAA==.',Ze='Zendosh:BAAALAAECgcIDgAAAA==.',Zy='Zylumé:BAAALAADCgcIBwAAAA==.',['Îc']='Îchigo:BAAALAADCggIDgABLAAECgIIAgABAAAAAA==.',['Ðo']='Ðoul:BAAALAAECgIIAgAAAA==.',['Ói']='Óin:BAAALAAECgYIBgAAAA==.',['ßo']='ßoom:BAAALAAECgQIBAAAAA==.',['ßõ']='ßõõm:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end