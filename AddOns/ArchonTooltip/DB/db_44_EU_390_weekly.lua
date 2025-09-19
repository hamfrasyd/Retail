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
 local lookup = {'Monk-Mistweaver','Paladin-Protection','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','Druid-Restoration',}; local provider = {region='EU',realm='Varimathras',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aazøg:BAAALAAECgYIDwAAAA==.',Ad='Adamar:BAAALAADCggICgAAAA==.',Ae='Aelynh:BAAALAAECgMIAwABLAAECggIHAABAOkgAA==.Aelynn:BAABLAAECoEcAAIBAAgI6SA5AgABAwABAAgI6SA5AgABAwAAAA==.',Ai='Aimis:BAAALAADCgUIBQAAAA==.',Ak='Akapulco:BAAALAAECgEIAgAAAA==.Akuona:BAAALAADCggICAAAAA==.Akylô:BAAALAAECgcIDQAAAA==.',Al='Alcassoulet:BAAALAADCgQIBgAAAA==.Aliz:BAAALAAECgYIDwABLAAFFAYIDQACADcRAA==.Allita:BAAALAADCgYIBgAAAA==.',An='Anely:BAAALAADCgcIEgAAAA==.',Ao='Aodren:BAAALAAECgQIBwAAAA==.',Ar='Arkaliane:BAAALAADCgYIBgABLAAECgcIEAADAAAAAA==.Arkonan:BAAALAADCggICAAAAA==.Arthyos:BAAALAAECgMIAwAAAA==.Arzaloth:BAAALAADCgcIBwAAAA==.',As='Asaevok:BAAALAAECgIIAgAAAA==.Asaflash:BAAALAADCgcIBwAAAA==.Asayondaime:BAAALAADCgcIBwAAAA==.Ashurà:BAAALAADCgQIBAAAAA==.Asrageth:BAAALAADCgYIBgAAAA==.',At='Atamagatakai:BAAALAAECgIIAwAAAA==.Attovst:BAAALAAECgYICQAAAA==.',Az='Azuria:BAAALAADCgcIBwAAAA==.',Ba='Barbun:BAAALAADCgUICQAAAA==.Bastèt:BAAALAAECgQIBwAAAA==.',Be='Belzebûth:BAAALAADCgQIBAAAAA==.',Bo='Bobby:BAAALAADCgYIBwAAAA==.Borujerd:BAAALAADCggIDwAAAA==.Boumbatta:BAAALAAECgMIAwAAAA==.',Ca='Calypsô:BAAALAADCggIDwAAAA==.Carlocalamar:BAAALAAECgcIEAAAAA==.Cassecoup:BAAALAADCggICAAAAA==.',Ch='Chagrin:BAAALAAECgUIBwAAAA==.Charlélox:BAAALAAECgYIDgAAAA==.Chekupp:BAAALAAECgYICwAAAA==.Chô:BAAALAAECgcIBwAAAA==.',Cl='Closetodeath:BAAALAAECgQICQAAAA==.',Co='Cocoyolas:BAAALAAECgYIDwAAAA==.Cortacoïde:BAAALAAECgEIAQAAAA==.Cortacula:BAAALAADCgYIBgABLAAECgEIAQADAAAAAA==.Cortaleptik:BAAALAADCgEIAQABLAAECgEIAQADAAAAAA==.Cortarke:BAAALAADCgcICQABLAAECgEIAQADAAAAAA==.Couetecouete:BAAALAADCggIDwAAAA==.',De='Debelon:BAAALAADCggIFgAAAA==.Dehous:BAAALAAECgYIBwAAAA==.Desmonphe:BAAALAAECgMIBAAAAA==.',Di='Diøxÿde:BAAALAADCggIDQAAAA==.',Dk='Dkpsulait:BAAALAAECgcIEgAAAA==.',Do='Doomyniste:BAAALAAECgEIAQAAAA==.',Dr='Dragby:BAAALAAECgYIBgAAAA==.Drakara:BAAALAADCgUIBQAAAA==.Dricannos:BAAALAADCgcIEwAAAA==.Droven:BAAALAAECgQIBwAAAA==.',Du='Dunken:BAAALAAECgcIEAAAAA==.Duomonk:BAAALAADCggICAAAAA==.',['Dé']='Déimos:BAAALAADCgMIAwAAAA==.Démonistah:BAAALAADCgcIDgAAAA==.',['Dø']='Døømsday:BAAALAADCggIDwAAAA==.',Ed='Edo:BAAALAAECgcIDQAAAA==.',El='Ell:BAAALAADCgcIDAAAAA==.',Em='Emperatork:BAAALAADCgcIBwAAAA==.',En='Enorelbot:BAAALAAECgcIDQAAAA==.Entropy:BAAALAAECgQIBQAAAA==.',Et='Ethnna:BAAALAAECgMIAgAAAA==.',Ev='Evannescence:BAAALAADCgcIBwAAAA==.',Fe='Fendheria:BAAALAADCgUIBQAAAA==.Fendrïl:BAAALAAECggICAAAAA==.',Fl='Flashdream:BAAALAAECgMIAwAAAA==.',Fu='Fumemocouete:BAAALAADCgcIBwAAAA==.',Ga='Gaagàa:BAAALAAECgUIBgAAAA==.Galyrith:BAAALAAECgEIAQAAAA==.Ganessha:BAAALAAECgIIAgAAAA==.',Ge='Gersiflet:BAAALAADCgIIAgAAAA==.',Go='Gonzochimy:BAAALAADCggIFgABLAADCggIFwADAAAAAA==.Gonzodaelia:BAAALAAECgEIAQABLAADCggIFwADAAAAAA==.Gonzoshen:BAAALAADCggIFwAAAA==.',Gr='Grizler:BAAALAADCgQIBAABLAAECgcIEAADAAAAAA==.',Gu='Gundarth:BAAALAAECgEIAQAAAA==.',['Gé']='Génézya:BAAALAADCggICAAAAA==.',['Gî']='Gîpsy:BAAALAAECgYIBgAAAA==.',Ha='Hamaât:BAAALAADCgMIAwAAAA==.Hamesh:BAAALAAECgMIAwAAAA==.Haquecoucou:BAAALAADCgcIDgAAAA==.Harlock:BAAALAAECggIDAAAAA==.',He='Heypahd:BAEALAAECgYICgAAAA==.',Hi='Hiboux:BAAALAADCggIEAAAAA==.Hikazu:BAABLAAECoEWAAIEAAgIUiOAAwA8AwAEAAgIUiOAAwA8AwAAAA==.',Hy='Hykazü:BAAALAADCgQIBAAAAA==.Hylam:BAAALAADCgcIFAAAAA==.Hylania:BAAALAADCgcIDgAAAA==.Hypotène:BAAALAAECgMIBgAAAA==.',Il='Illyasvield:BAAALAADCggICAAAAA==.',In='Inøri:BAAALAAECgUIBQAAAA==.',Ir='Irachi:BAAALAADCggICAAAAA==.',Is='Isilmë:BAAALAADCgcIDAAAAA==.',Ja='Jalyne:BAAALAAECgEIAQAAAA==.',Je='Jenz:BAACLAAFFIENAAICAAYINxFFAACeAQACAAYINxFFAACeAQAsAAQKgRgAAgIACAgoJdgAAF4DAAIACAgoJdgAAF4DAAAA.',Ji='Jiziee:BAAALAAECgIIAwAAAA==.',Jy='Jylane:BAAALAADCgcIBwAAAA==.',Ka='Kamu:BAAALAADCgEIAQAAAA==.Kaqn:BAAALAADCggIDgAAAA==.Karaliane:BAAALAAECgcIEAAAAA==.Kardra:BAAALAAECgMIAwAAAA==.Kazrock:BAAALAAECgYIDgAAAA==.',Ke='Ketuirint:BAAALAAECgYIBgAAAA==.',Ki='Kinuty:BAAALAADCgcIBwAAAA==.Kironash:BAAALAAECgMIBgAAAA==.Kironyx:BAAALAADCgcIDgAAAA==.Kisadh:BAAALAADCggIEAAAAA==.Kisaé:BAAALAADCgcICgAAAA==.',Ko='Kolosse:BAAALAADCgcIBwAAAA==.',Kr='Kramassax:BAAALAAECgEIAgAAAA==.Kratøx:BAAALAADCgcIBwAAAA==.',['Kø']='Køsetzu:BAAALAADCgcICgAAAA==.',La='Lamevengeres:BAAALAADCggIDQAAAA==.Lanatur:BAABLAAECoEUAAMFAAgI3RWKEAAwAgAFAAgI3RWKEAAwAgAGAAYIgh9tGwCvAQAAAA==.',Le='Leilam:BAAALAAECgMIBAAAAA==.',Li='Licht:BAAALAADCgcICwAAAA==.Lirkana:BAAALAADCgYIBgABLAAECgcIEAADAAAAAA==.',Lo='Lombax:BAAALAADCgcIDgAAAA==.Louac:BAAALAAECgEIAQAAAA==.',Ls='Lsaltar:BAAALAADCgYIBgAAAA==.',Lu='Ludð:BAAALAAECgUIBQAAAA==.',Ly='Lyliana:BAAALAADCggICAAAAA==.Lysterya:BAAALAADCgEIAQAAAA==.',Ma='Magicalguys:BAAALAADCgQIBAAAAA==.Mahh:BAAALAADCgcIEQAAAA==.Mariateresa:BAAALAADCggIFQAAAA==.Maskimir:BAAALAAECgMIAwAAAA==.Mathysded:BAAALAAECgIIAgAAAA==.Maylicia:BAAALAADCgIIAgAAAA==.',Me='Menorsraza:BAAALAAECgYIBgAAAA==.',Mi='Minionegnome:BAAALAAECgQICAAAAA==.Miyu:BAAALAAECgMIAwAAAA==.',Mo='Moorwen:BAAALAADCgMIAwAAAA==.Morgun:BAAALAAECgcIEAAAAA==.Morks:BAAALAADCggICAAAAA==.Morrgh:BAAALAAECgMIAwAAAA==.',Mu='Munolas:BAAALAADCggIFQAAAA==.',My='Myndra:BAACLAAFFIEFAAIGAAMI5hOXBACyAAAGAAMI5hOXBACyAAAsAAQKgRcAAgYACAhQHGgKAGICAAYACAhQHGgKAGICAAAA.Myrcella:BAAALAAECgYIDAAAAA==.Myuléona:BAAALAAECgEIAQAAAA==.',Na='Narwel:BAAALAADCggIDAABLAAECgQIBwADAAAAAA==.',Ne='Neyssë:BAAALAAECgMIAwAAAA==.',No='Nolystia:BAAALAAECgEIAQAAAA==.',Pa='Pasdacdutout:BAAALAADCgQIBAAAAA==.Pasnetdutout:BAAALAAECgYIDAAAAA==.',Pe='Petitgateau:BAAALAAECgQIBAAAAA==.',Pr='Prayse:BAAALAAECgYICgAAAA==.Provencal:BAAALAADCgcIBwAAAA==.',['Pé']='Pédiluve:BAAALAAECgYIBgAAAA==.',Ra='Rapsodyr:BAAALAADCgcICwAAAA==.',Rh='Rheïa:BAAALAADCgIIAgAAAA==.',Ro='Rozzi:BAAALAADCggICQAAAA==.',Ry='Ryûnosuke:BAAALAADCggICAAAAA==.',Sa='Sanjay:BAAALAAFFAMIAwAAAA==.',Se='Septimus:BAAALAAECgEIAQAAAA==.',Sh='Shalti:BAAALAADCggICAAAAA==.Shankss:BAAALAAECgYIBwAAAA==.Shirayuki:BAAALAAECgYICAAAAA==.',Sk='Skibidî:BAAALAADCgMIAwAAAA==.',Sl='Sløw:BAAALAADCggICAAAAA==.',So='Solsagan:BAAALAADCggIEwAAAA==.',Sp='Spectre:BAAALAAECgYIDgAAAA==.',St='Stefflock:BAAALAAECgYIDwAAAA==.',['Sä']='Säta:BAAALAAECgYICgAAAA==.',['Sí']='Síanka:BAAALAADCgEIAQAAAA==.',Ta='Talion:BAAALAADCgcIBgAAAA==.',Th='Thiorgnole:BAAALAAECgEIAQAAAA==.Thylda:BAAALAAECgUIBQAAAA==.',Ti='Timmida:BAAALAADCgcIFAAAAA==.Tiranosorus:BAAALAAECgMIBAAAAA==.',Tr='Troméo:BAAALAAECgUIBgAAAA==.Trynd:BAAALAAECgYICgAAAA==.',Ts='Tsunimi:BAAALAADCggIDwAAAA==.',Ty='Tyvar:BAAALAAECgUIDAAAAA==.',['Té']='Tétrazépam:BAAALAAECgMIBgAAAA==.',Va='Vachementoro:BAAALAAECgMIBAAAAA==.Vador:BAAALAADCgQIBAAAAA==.Valador:BAAALAADCggICAAAAA==.',Ve='Vegewarian:BAAALAAECgEIAQAAAA==.',Wa='Warlack:BAAALAAECgUICAAAAA==.',We='Weuzork:BAAALAADCgYIBgAAAA==.',Xh='Xhyotine:BAAALAADCggIFQAAAA==.',Xy='Xywoxuw:BAAALAADCgYICgABLAADCggICAADAAAAAA==.',Ya='Yatuwalker:BAAALAAECgUIBwAAAA==.',Yu='Yugo:BAAALAAECgMIAwAAAA==.',Za='Zamadsu:BAAALAADCgMIAwAAAA==.',Zy='Zywu:BAAALAADCggICAAAAA==.',['Æn']='Ænzu:BAAALAADCggIDQAAAA==.',['Ér']='Érèzir:BAAALAAECgEIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end