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
 local lookup = {'Unknown-Unknown','Priest-Shadow',}; local provider = {region='EU',realm='DieewigeWacht',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abraxsas:BAAALAADCggICgABLAAECgYICwABAAAAAA==.',Ad='Adranos:BAAALAAECgMIAwAAAA==.',Ae='Aetheriion:BAAALAADCgQIBAAAAA==.',Al='Alaris:BAAALAAECgYICwAAAA==.Alea:BAAALAADCgcIDAAAAA==.',An='Anchsenamun:BAAALAADCgIIAgAAAA==.Anelia:BAAALAADCgYICwAAAA==.Anemone:BAAALAADCggIBwAAAA==.Anur:BAAALAAECgYIDwAAAA==.',Aq='Aquira:BAAALAAECgcICgAAAA==.',Ar='Arwenis:BAAALAADCgcIBwAAAA==.',As='Asmera:BAAALAAECgYIDgAAAA==.',At='Atharion:BAAALAAECggICAABLAAECggIEAABAAAAAA==.',Au='Aurôn:BAAALAADCgcIDAAAAA==.',Ay='Aymee:BAAALAADCgUICAAAAA==.',Az='Azaba:BAAALAADCggIGQAAAA==.',Ba='Baelorr:BAAALAADCggIEwAAAA==.Baruc:BAAALAADCgUIBQAAAA==.',Bi='Bielefeld:BAAALAADCgcIBwAAAA==.',Bl='Blackstaff:BAAALAADCggIGwAAAA==.Blutbertina:BAAALAAECgMIAwAAAA==.',Bu='Bufferl:BAAALAAFFAIIAgAAAA==.Buffy:BAAALAAECgQIBAAAAA==.',Ca='Calariel:BAAALAAECgEIAQAAAA==.Caninus:BAAALAADCgYIBgAAAA==.',Ch='Chaosdemon:BAAALAADCgEIAQAAAA==.Chinaclyra:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Chinassa:BAAALAAECgMIAwAAAA==.',Cl='Classless:BAAALAAECgQIBgAAAA==.Clipeatusus:BAAALAADCgMIAwAAAA==.',Co='Coên:BAAALAAECgQIBgAAAA==.',Cr='Crest:BAAALAADCgYIBgAAAA==.Cricou:BAAALAAECgEIAQAAAA==.Cronu:BAAALAAECgIIAgAAAA==.Créatures:BAAALAAECgEIAQAAAA==.Crëst:BAAALAADCgQIBAAAAA==.',Cy='Cyrus:BAAALAADCggICwAAAA==.',Da='Dalían:BAAALAAECgEIAQAAAA==.Darcelf:BAAALAADCggIEAAAAA==.Darkie:BAAALAAECgQIAgAAAA==.Darknîght:BAAALAAECgcIDQAAAA==.',De='Denramonix:BAAALAAECgYICwAAAA==.Derethor:BAAALAAECggIDwAAAA==.Devlin:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',Dh='Dhionas:BAAALAAECgIIAwAAAA==.',Do='Dokatha:BAAALAADCgEIAQABLAADCgQIBgABAAAAAA==.',Dr='Dronatega:BAAALAAECgEIAQAAAA==.',['Dá']='Dániá:BAAALAAECgMIBAAAAA==.Dáxx:BAAALAADCgcIBwAAAA==.',['Dâ']='Dârklîght:BAAALAADCgcIBwAAAA==.',['Dí']='Dímìtri:BAAALAAECgQIBQAAAA==.',['Dî']='Dîamond:BAAALAAECgMIAwAAAA==.',Ek='Ekoo:BAAALAAECgMIAwABLAAECgcIDwABAAAAAA==.',El='Elsana:BAAALAAECgIIAgAAAA==.',Em='Emmalina:BAAALAAECgMIAwAAAA==.',En='Endora:BAAALAADCggICAAAAA==.Enthyro:BAAALAAECgQIBgAAAA==.',Es='Eshren:BAAALAADCggICAABLAAECgMIBgABAAAAAA==.',Fa='Falloutflo:BAAALAAECgIIAgAAAA==.Fauny:BAAALAADCgcIFQAAAA==.',Fe='Fedérs:BAAALAADCgIIAgAAAA==.',Fh='Fhijondhreas:BAAALAADCgQIBgAAAA==.',Fi='Fischt:BAAALAAECgYICgAAAA==.',Fl='Flamel:BAAALAADCggIDAAAAA==.',Ga='Garim:BAAALAAECgYICwAAAA==.Garina:BAAALAADCggICwAAAA==.',Ge='Gekkò:BAAALAADCggIFQAAAA==.',Gh='Ghedra:BAAALAADCgcIDwAAAA==.',Gn='Gnomero:BAAALAAECgYIEQAAAA==.',Gr='Grevonimo:BAAALAADCggIDQAAAA==.',Ha='Hariana:BAAALAAECgMIAwAAAA==.',He='Healenâ:BAAALAAECgYICwAAAA==.Hellios:BAAALAAECgcIEAAAAA==.Hexx:BAAALAADCggICAAAAA==.',Hi='Hiaria:BAAALAAECgMIAwAAAA==.',Ho='Hornia:BAAALAADCgcIFAAAAA==.',Hu='Huyana:BAAALAADCgQIBgAAAA==.',Ia='Iang:BAAALAADCggICAABLAADCggIEAABAAAAAA==.',Ic='Icecreamman:BAAALAAECgQIBAAAAA==.',Ik='Ikamia:BAAALAADCgYIDwABLAAECgQIBgABAAAAAA==.',Ir='Irisfacem:BAAALAAECgQIBwAAAA==.',Ja='Jasemin:BAAALAADCgcIDQAAAA==.',Jh='Jhola:BAAALAAECgQIBgAAAA==.',Jo='Jodara:BAAALAAECgYICwAAAA==.',Ju='Julês:BAAALAAECgYIBgAAAA==.Jumaji:BAAALAAECgMIAwAAAA==.',Ka='Kaeda:BAAALAADCgcIBwAAAA==.Kaleeza:BAAALAAECgYIDAAAAA==.Kariná:BAAALAADCgcICgAAAA==.Katchen:BAAALAAECgIIAgAAAA==.Kawib:BAAALAAECgYICgAAAA==.',Kh='Khoriel:BAAALAAECgYICAABLAAECggIAgABAAAAAA==.',Ki='Kinobi:BAAALAADCgcICQAAAA==.',Kl='Klautomatix:BAAALAADCgUIBQAAAA==.',Kr='Kratia:BAAALAADCgcICgAAAA==.Kreatör:BAAALAAECgMIAwAAAA==.Kropolis:BAAALAADCggICAAAAA==.',La='Larouge:BAAALAADCggICAAAAA==.Lauie:BAAALAADCgMIAwAAAA==.Layra:BAAALAADCgcICgAAAA==.',Li='Liandrell:BAAALAAECgUICAAAAA==.Lianka:BAAALAADCgYICQAAAA==.',Lo='Lodar:BAAALAAECgIIAgAAAA==.Lorule:BAAALAADCggICgAAAA==.Loupapagarou:BAAALAAECgQIBAAAAA==.',Lu='Lunarg:BAAALAAECgUICAAAAA==.',Ly='Lynise:BAAALAAECgEIAQAAAA==.',['Lý']='Lýdan:BAAALAAECgEIAQAAAA==.',Ma='Madrakor:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.Madymu:BAAALAADCgQIBwAAAA==.Magnix:BAAALAAECgQIBgAAAA==.Mahaji:BAAALAADCgMIAwAAAA==.Malyana:BAAALAAECgYIBgAAAA==.Mansan:BAAALAADCgcIBwAAAA==.Marøk:BAAALAADCgEIAgABLAADCgcIGwABAAAAAA==.Maximin:BAAALAADCggIEAAAAA==.',Mc='Mcandy:BAAALAAFFAIIAgAAAA==.',Me='Meltdown:BAAALAAECgcIDwAAAA==.',Mi='Michaghar:BAAALAAECgYIEAAAAA==.Mierro:BAAALAAECgMIAwAAAA==.Miralyn:BAAALAAECgMIAwAAAA==.Mirlan:BAAALAADCgEIAQAAAA==.Misandei:BAAALAAECgMIBgAAAA==.',Mo='Mord:BAAALAADCggIDgAAAA==.Morg:BAAALAAECgYICwAAAA==.Morieria:BAAALAADCgcIGwAAAA==.',Mu='Munchkín:BAAALAADCggIHQAAAA==.',['Mâ']='Mârimo:BAAALAADCggIFQAAAA==.',['Mô']='Môônlight:BAAALAAECgMIBgAAAA==.',Na='Nagînî:BAAALAAECgEIAQAAAA==.Nap:BAAALAADCgcIBwAAAA==.Narîko:BAAALAAECgcIEAAAAA==.',Ne='Nemet:BAAALAADCgcIDgAAAA==.Nereus:BAAALAAECgcIDgAAAA==.Neyith:BAAALAADCggICAAAAA==.',Ni='Niari:BAAALAADCgcIFQABLAADCgcIFQABAAAAAA==.Nina:BAAALAADCgIIAwAAAA==.Nitche:BAAALAADCgcIBgAAAA==.',['Ná']='Náomy:BAAALAADCgcIBwABLAAECgMIBAABAAAAAA==.',['Nâ']='Nâsty:BAAALAAECgYIBgAAAA==.',['Nî']='Nîrlana:BAAALAADCgcIDQAAAA==.',['Nü']='Nüssli:BAAALAAECgYICAAAAA==.',Om='Ommespommes:BAAALAADCggICAAAAA==.',Pa='Palibaba:BAAALAAECgIIAgAAAA==.Patos:BAAALAADCgMIBAAAAA==.Paulline:BAAALAAECggIAQAAAA==.',Ph='Philldloong:BAAALAAECgQIBgAAAA==.',Pp='Ppriest:BAAALAADCgcIBwAAAA==.',Pr='Protektor:BAAALAADCgUIBQAAAA==.',['Pí']='Píper:BAAALAAECgcIEAAAAA==.',Ra='Ravennia:BAAALAAECgEIAQAAAA==.Razka:BAAALAADCgcICAAAAA==.',Re='Reojin:BAAALAAECgYICwAAAA==.',Rh='Rhelon:BAAALAADCgcIBwAAAA==.',Ro='Rosaga:BAAALAAECgEIAQAAAA==.Roxadoxa:BAAALAAECgEIAQAAAA==.',Ru='Ruras:BAAALAADCgIIAgAAAA==.',Ry='Rynera:BAAALAAECgMIAwAAAA==.Ryuuk:BAAALAAECggICAABLAAECggIEAABAAAAAA==.',['Rê']='Rêvên:BAAALAAECgIIAgAAAA==.',['Rì']='Rìnoa:BAAALAADCgcICAAAAA==.',Sa='Sajon:BAAALAADCgEIAQAAAA==.Saluná:BAAALAADCggIDQAAAA==.Santina:BAAALAADCgYIBwAAAA==.',Sc='Schädowelff:BAAALAAECgMIAwAAAA==.',Se='Secre:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Selolan:BAAALAADCggICAAAAA==.Senaya:BAAALAAECgEIAQAAAA==.Seranety:BAAALAAECgcIDwAAAA==.Seytanja:BAAALAAECgIIAgAAAA==.',Sh='Shakotan:BAAALAADCggIHQAAAA==.Shanadorion:BAAALAAECgMIBAAAAA==.Sherì:BAAALAADCgMIAwAAAA==.Shi:BAAALAAFFAIIAgAAAA==.Shiro:BAAALAAECgYIDgAAAA==.Shizuko:BAAALAAECgcIBwAAAA==.Shoca:BAAALAAECgYIDgAAAA==.Shoci:BAAALAAECgIIAwAAAA==.Shunia:BAAALAADCgcIDwAAAA==.Shyrâna:BAAALAADCgQIBAAAAA==.',Si='Sinsemilla:BAAALAAECgYICAAAAA==.',Sl='Slyder:BAAALAADCgcIDQAAAA==.Slyver:BAAALAAECgYICQAAAA==.',So='Sojih:BAAALAAECgYIEAAAAA==.Solerian:BAAALAADCgEIAQAAAA==.',St='Stormi:BAAALAADCggICAAAAA==.',['Sé']='Sénaya:BAAALAADCggIDwABLAAECgEIAQABAAAAAA==.',Ta='Tadog:BAAALAAECgEIAQAAAA==.Tarelia:BAAALAAECgIIAwAAAA==.',Te='Telemnar:BAAALAAECgIIAQAAAA==.',Th='Thorîn:BAAALAAECgEIAQAAAA==.Thutmosina:BAAALAADCgYICgAAAA==.',Ti='Tibera:BAAALAADCgMIBAABLAADCggIHQABAAAAAA==.Tiniare:BAAALAADCggIFAAAAA==.',Tr='Triana:BAAALAAFFAIIAgAAAA==.Tristanus:BAAALAAECgIIAgAAAA==.Trîst:BAAALAAFFAIIAgAAAA==.',Ts='Tscholls:BAAALAADCgYIBgABLAADCgQIBgABAAAAAA==.Tsurára:BAAALAADCgIIAgABLAAECgYIDgABAAAAAA==.',Va='Valinôr:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.',Ve='Veklar:BAAALAAECgEIAQAAAA==.Verala:BAAALAAECggIAgAAAA==.Verflucht:BAAALAADCgcICwAAAA==.',Vh='Vhaulor:BAAALAAECgEIAQABLAADCgQIBgABAAAAAA==.',Vy='Vykas:BAAALAAECgIIAQAAAA==.',['Ví']='Víola:BAAALAADCggIDwAAAA==.',Wa='Wallkürè:BAAALAADCggIDQAAAA==.',We='Wendehals:BAAALAAECgEIAgAAAA==.',Wi='Wichteltante:BAAALAADCgcIBwAAAA==.',Wo='Wolfhexx:BAAALAADCgQIBAAAAA==.Woogyo:BAABLAAECoEWAAICAAgIbR8eCADcAgACAAgIbR8eCADcAgAAAA==.Worcesters:BAAALAAECgMIBAAAAA==.',Xa='Xaden:BAAALAADCgYIBgAAAA==.Xalih:BAAALAAECgcIEAAAAA==.',Xo='Xolon:BAAALAADCgYIBgAAAA==.',Ye='Yellowdragon:BAAALAADCggIEQAAAA==.',Yo='Yodaschi:BAAALAAECgcIEQAAAA==.Yoshimitsumg:BAAALAAECgMIAwAAAA==.',Yu='Yukihime:BAAALAADCggIDQABLAAECgYIDgABAAAAAA==.',Za='Zacknefein:BAAALAAECgYICgAAAA==.Zamor:BAAALAADCgQIBAAAAA==.',Ze='Zeiron:BAAALAAECgIIAwAAAA==.Zeitgeist:BAAALAADCgUIBQAAAA==.Zeroforone:BAAALAADCgcIDQAAAA==.',Zy='Zyr:BAAALAAECggIEAAAAA==.',['Zü']='Zündhütchen:BAAALAAECgQIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end