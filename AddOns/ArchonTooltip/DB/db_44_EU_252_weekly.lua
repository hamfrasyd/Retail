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
 local lookup = {'DeathKnight-Frost','Unknown-Unknown','Mage-Frost','Druid-Restoration','Druid-Balance','Shaman-Elemental','Priest-Holy','Priest-Shadow','Hunter-Marksmanship','Paladin-Retribution','Paladin-Holy','Shaman-Restoration','Warlock-Destruction','Warrior-Fury','Warrior-Arms','Paladin-Protection',}; local provider = {region='EU',realm='Alonsus',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Acerimer:BAAALAAECgMIAwAAAA==.Achlys:BAAALAADCgcIBwAAAA==.',Ai='Aidos:BAAALAAECgYIEAAAAA==.Aim:BAAALAAECgYIBwAAAA==.',Ak='Akumma:BAABLAAECoEWAAIBAAgIqBxjFAC5AgABAAgIqBxjFAC5AgAAAA==.',Al='Alexuss:BAAALAADCgIIAgAAAA==.Alipala:BAAALAAECgcIEAAAAA==.Alixia:BAAALAADCggIEAAAAA==.',Am='Amesha:BAAALAADCggIEAAAAA==.',An='Andorei:BAAALAAECgMIBAAAAA==.',Ar='Arnfrid:BAAALAADCgMIAwABLAAECgIIAgACAAAAAA==.Artethion:BAAALAADCggIDwAAAA==.',As='Assasinwar:BAAALAAECgUICwAAAA==.Asunela:BAABLAAECoEUAAIDAAYIURtuGQDJAQADAAYIURtuGQDJAQAAAA==.',Av='Avatuss:BAAALAAECgMIBgAAAA==.',Ba='Badbonesdr:BAAALAADCggICAABLAAECggIBwACAAAAAA==.Badbonesp:BAAALAAECggIBwAAAA==.Balenciaga:BAAALAAECgcIEQAAAA==.Barathrum:BAACLAAFFIEFAAMEAAII0BrLCQCoAAAEAAII0BrLCQCoAAAFAAEI1gdEEABFAAAsAAQKgR4AAwQACAirHE0OAGsCAAQACAirHE0OAGsCAAUABQhtHTknAKMBAAAA.Bavarion:BAAALAAFFAIIBAAAAA==.',Be='Beefquake:BAAALAADCggIFQAAAA==.Beefstake:BAAALAADCggIEwAAAA==.Beefsteak:BAAALAAECgIIAwAAAA==.Behamat:BAAALAADCggIGAAAAA==.Belfsteak:BAAALAADCggIEwAAAA==.',Bi='Bigdaddruid:BAAALAAECgIIAQAAAA==.Biglez:BAAALAAECgQIBQAAAA==.Bimsatron:BAABLAAECoEUAAIGAAcIeRcWIAAQAgAGAAcIeRcWIAAQAgAAAA==.',Bl='Blackarrow:BAAALAADCggIEAAAAA==.Blamblam:BAAALAADCgcIBwAAAA==.Blixtnedslag:BAAALAADCgUIBQAAAA==.Blueshameh:BAAALAAECgYIDAAAAA==.',Bo='Bootleg:BAAALAAECggICQAAAA==.Bosjesvrouw:BAAALAADCgUIBQAAAA==.',Br='Brittlebones:BAAALAADCggIDwAAAA==.Bronzebarda:BAAALAADCgMIAwAAAA==.',Ca='Calanthea:BAAALAADCgMIAwAAAA==.Candyfloss:BAAALAAECgYIBgAAAA==.',Ch='Choaslord:BAAALAAECgYIDQAAAA==.',Cl='Cloudie:BAAALAAECgYIBgABLAAECgcIDwACAAAAAA==.Cloudmink:BAAALAAECgcIDwAAAA==.Cloudnosoul:BAAALAADCgcIBwABLAAECgcIDwACAAAAAA==.Cloudrockin:BAAALAADCgYICAABLAAECgcIDwACAAAAAA==.',Co='Colliewong:BAAALAAECgMIBAAAAA==.Conno:BAAALAAECgcIDQAAAA==.Coomknight:BAAALAADCggICAAAAA==.',Cy='Cylia:BAAALAAECggICAAAAA==.Cyntax:BAAALAAECggIEAAAAA==.',Da='Dagochnatt:BAAALAADCgYIDAAAAA==.Dalinar:BAAALAAECgQIBAAAAA==.Dandelion:BAAALAAECgYIDwAAAA==.Dawei:BAAALAAECgYIDgAAAA==.',De='Deaderror:BAAALAADCgcIBwAAAA==.Degros:BAAALAAECgMIBgAAAA==.Deisin:BAAALAAECgMIBgAAAA==.Destroboom:BAAALAADCgYIBgAAAA==.Dewie:BAAALAAECgYIEgAAAA==.',Di='Dieselolle:BAAALAAECgIIAgAAAA==.Diggerdagger:BAAALAADCgMIAwAAAA==.Dikkespier:BAAALAADCggIGgAAAA==.Disturbia:BAAALAAECggIDAAAAA==.',Do='Dormantdrago:BAAALAAECgYICgAAAA==.Dormy:BAAALAADCgEIAQABLAAECgYICgACAAAAAA==.',Dr='Draxdh:BAAALAAECgYICwAAAA==.Draxmage:BAAALAADCgcIBwAAAA==.',Du='Dundo:BAAALAAECgYIDAAAAA==.',Ee='Eery:BAAALAADCgcIDAAAAA==.',Ei='Eirnith:BAACLAAFFIEGAAIHAAMINhpHBQAOAQAHAAMINhpHBQAOAQAsAAQKgR8AAwcACAijHqYMAKgCAAcACAijHqYMAKgCAAgABwjDEDAoALYBAAAA.',El='Eledamiri:BAAALAADCgMIAwAAAA==.',Em='Emptyhead:BAAALAAECgEIAQAAAA==.',En='Enyo:BAAALAADCgIIAQAAAA==.',Ew='Ewsyde:BAAALAADCgMIAwAAAA==.',Ex='Exo:BAAALAAECgQIBAAAAA==.',Fa='Faab:BAAALAADCggIDAAAAA==.',Fe='Ferisons:BAAALAAECgYIDwAAAA==.Ferrin:BAAALAAECgYIEAAAAA==.',Fi='Fil:BAAALAAECgMIAwAAAA==.Fireborn:BAABLAAFFIEIAAIJAAMIVSTVAgA9AQAJAAMIVSTVAgA9AQAAAA==.',Fl='Fluffnut:BAAALAAECgYIBwAAAA==.',Fr='Frostyyballs:BAAALAAECgIIAgAAAA==.',Ga='Gaiyaa:BAAALAAECgMIAwAAAA==.',Ge='Geowrath:BAAALAAECgMIBgAAAA==.',Gi='Gilfread:BAAALAAECgMIBgAAAA==.',Gr='Griswold:BAAALAAECggICwAAAA==.',Gw='Gwandryas:BAAALAAECgYICgAAAA==.',Ha='Harei:BAAALAAECgMIBAAAAA==.Harriét:BAAALAADCgUIBQAAAA==.',He='Hellhunter:BAAALAAECgYIDAAAAA==.Hexenbiest:BAAALAAECgYIEAAAAA==.Hexorcist:BAAALAAECggIEAAAAA==.',Hi='Hipolita:BAAALAADCgYIBgAAAA==.Hitman:BAAALAADCgEIAQAAAA==.',Hk='Hkxytall:BAAALAAECgYIBwAAAA==.',Ho='Hobomagic:BAAALAADCgIIAgAAAA==.Holyfelf:BAAALAAECgIIAgAAAA==.Hotlegochick:BAAALAADCggICAAAAA==.',Ig='Igglepiggle:BAAALAADCgcICAAAAA==.',Il='Ilarie:BAAALAAECgYICgAAAA==.Illidiggity:BAAALAADCggIDwAAAA==.Illirari:BAAALAAECgMIBgAAAA==.',In='Incidina:BAAALAAECgIIAwAAAA==.Infinity:BAABLAAECoEWAAIKAAgIKxePKwAoAgAKAAgIKxePKwAoAgAAAA==.',Iw='Iwwy:BAAALAADCgYICQAAAA==.',Ja='Jadelee:BAAALAADCggIDwABLAAECgUICwACAAAAAA==.Janie:BAAALAAECgYIEwAAAA==.',Je='Jeppydin:BAAALAADCgEIAQABLAAECgMIAwACAAAAAA==.',Jo='Johero:BAAALAAECgYIBgABLAAFFAIIBQAEANAaAA==.',['Jä']='Jägern:BAAALAAECgYIAgAAAA==.',Ka='Karix:BAAALAAECgcIEwAAAA==.Karnayna:BAAALAADCgcIBwAAAA==.',Ke='Keldral:BAAALAADCggICAABLAAFFAIIBQAEANAaAA==.Kelfrost:BAAALAAECgcIDQAAAA==.Kerath:BAAALAADCgMIAwAAAA==.',Kl='Klootvioolss:BAAALAAECgQIBQAAAA==.',Ko='Kolwl:BAAALAAFFAIIBAAAAA==.Koorvaak:BAAALAADCgcIBwAAAA==.Kotonelock:BAAALAADCggIDwAAAA==.',Kr='Krokcydruidh:BAAALAADCgQIBAAAAA==.',['Kå']='Kåsago:BAAALAAFFAIIAgAAAA==.',La='Laenas:BAAALAADCgYIDAAAAA==.Lanni:BAEALAAECggICQAAAA==.Lant:BAAALAAECgQIBAAAAA==.Lavendere:BAAALAAECgYIDgAAAA==.',Le='Legolás:BAAALAAECgYIAgAAAA==.Lentukas:BAAALAAECgMIBgAAAA==.',Li='Lindael:BAAALAADCgcIBwAAAA==.Liptan:BAAALAADCgUIBQAAAA==.Liquidsnake:BAAALAADCggICAAAAA==.',Ll='Llurien:BAAALAAECgIIAgAAAA==.',Lo='Loonyblade:BAAALAAECgEIAQAAAA==.',Lu='Luxara:BAAALAAECgEIAQAAAA==.',Lx='Lxstsoul:BAAALAAECgIIAgAAAA==.',Ma='Mackenpuffz:BAAALAADCgMIAwAAAA==.Magekéld:BAAALAADCgUIBQAAAA==.Maitri:BAAALAADCgQIBAABLAAECgYIDAACAAAAAA==.Malevolence:BAAALAAECgUICAAAAA==.Mari:BAAALAAECgUICgAAAA==.Marlet:BAAALAAECgUIBwAAAA==.',Me='Med:BAAALAAECggIEgAAAA==.Medieev:BAAALAAFFAMIAgAAAA==.Mekkaburn:BAAALAAECgMIAwAAAA==.Messai:BAAALAADCgIIAgAAAA==.',Mi='Michika:BAAALAAECgYIDwAAAA==.Miedmar:BAAALAADCggICAABLAAECgYIEQACAAAAAA==.Miedvoker:BAAALAAECgYIEQAAAA==.Miidgeski:BAAALAADCgcIBwAAAA==.Minimagimage:BAAALAAECgYIEQAAAA==.',Mn='Mnemetress:BAAALAAECgcIDwAAAA==.',Mo='Monkeypk:BAAALAAECgUIBQABLAAECgcIEAACAAAAAA==.Monniela:BAAALAAECgYIDQAAAA==.Moonclavs:BAAALAADCggICAAAAA==.Morgana:BAAALAAECgMIBQAAAA==.Morticus:BAAALAADCgcIBwAAAA==.Morí:BAAALAADCggICQAAAA==.',My='Mysterie:BAAALAADCgcIBwAAAA==.',Na='Nabulous:BAAALAADCggIDwAAAA==.',Ne='Nerk:BAAALAAFFAIIAgAAAA==.Nerrk:BAAALAAECgYICgABLAAFFAIIAgACAAAAAA==.',Ni='Nicle:BAAALAADCgYIBgAAAA==.',No='Nosmite:BAAALAADCgQIBAAAAA==.',Nu='Nurgle:BAAALAAECgYIDwAAAA==.',Ol='Olordwhite:BAAALAAECgcIEAAAAA==.',Ov='Overground:BAABLAAECoEVAAILAAYIjBiGGQCuAQALAAYIjBiGGQCuAQAAAA==.',Ph='Phoenixw:BAAALAADCggIGAAAAA==.',Pr='Protean:BAAALAAECgYIEAAAAA==.',Pu='Puddled:BAAALAADCggICAABLAAECgYICgACAAAAAA==.',Qu='Qunable:BAAALAADCggICAAAAA==.',Ra='Raylee:BAAALAAECgEIAgAAAA==.',Re='Rennac:BAAALAADCgMIAwAAAA==.Renno:BAAALAADCggIEAAAAA==.',Rh='Rhya:BAAALAADCggICAAAAA==.',Ro='Rob:BAAALAADCgcIBwAAAA==.Robbosaur:BAAALAADCggICAAAAA==.Rohanda:BAAALAAECgcIBwAAAA==.',Ru='Ruhsar:BAAALAADCggIDwAAAA==.',Sa='Sanfori:BAAALAAECgQIBQAAAA==.Sanforis:BAAALAADCggICAAAAA==.',Sh='Shammzie:BAAALAAECgYIEgAAAA==.Shardly:BAAALAAECgYIDwAAAA==.Shiriek:BAAALAADCgIIAgAAAA==.Shivs:BAAALAADCgcIBwABLAAECggIEwACAAAAAA==.Shivslady:BAAALAAECggIEwAAAA==.',Si='Sixxi:BAAALAAECgMIAwAAAA==.',Sk='Skuffè:BAABLAAECoEZAAIMAAYIgSXyDwB8AgAMAAYIgSXyDwB8AgAAAA==.',Sm='Smollie:BAAALAADCggIFAAAAA==.',Sn='Sndrpala:BAAALAADCggICAAAAA==.',So='Solent:BAAALAAECgEIAQABLAAECgYIEAACAAAAAA==.Soltea:BAAALAAECgYIEAAAAA==.Sondrius:BAAALAADCgIIAgAAAA==.Songwen:BAAALAADCggICAAAAA==.Soulless:BAAALAADCggICAAAAA==.',St='Stampead:BAAALAADCgMIAwAAAA==.Starzyk:BAAALAAECgUICAAAAA==.Stevenalex:BAAALAADCgMIBAAAAA==.',Su='Sugmadic:BAAALAAECgYIBgAAAA==.Surtfire:BAAALAAECgYICgAAAA==.',Sy='Syrthio:BAAALAAECgYICwAAAA==.',Te='Telori:BAAALAADCgQIBAAAAA==.Terrorskorn:BAAALAADCgYIBgAAAA==.',Th='Thaderyl:BAAALAAECgYIEwAAAA==.Thisislovac:BAAALAAECgYIDAABLAAECggIGgANANEiAA==.Thisiswrong:BAAALAAECgYIDAAAAA==.',Ti='Timesmage:BAAALAADCggICAABLAAECggIDgACAAAAAA==.Tio:BAAALAADCggIEAAAAA==.',To='Tom:BAAALAADCgYICwAAAA==.Tommy:BAABLAAECoEeAAMOAAgIrhZDFgBvAgAOAAgIrhZDFgBvAgAPAAYIzwMhFwCzAAAAAA==.Tormen:BAAALAADCgUIBQABLAAECgUICwACAAAAAA==.',Tr='Traigar:BAAALAAECgIIAwABLAAFFAIIBQAEANAaAA==.',['Tâ']='Tâstiç:BAAALAAECgIIAwAAAA==.',Un='Undefeated:BAAALAAECgYIAwAAAA==.Unholyness:BAAALAAECgYIEwAAAA==.Unholynéss:BAAALAAECgYICwAAAA==.',Va='Valeerian:BAAALAADCgMIAwAAAA==.Vall:BAAALAADCggIDwAAAA==.Vanish:BAAALAAECgUIBQAAAA==.Vargen:BAAALAAECgYIBgAAAA==.',Vb='Vbj:BAAALAADCgQIBAAAAA==.',Ve='Veldahar:BAAALAADCgQIBAAAAA==.Vendrakis:BAAALAADCgMIAwAAAA==.',Vi='Viliya:BAAALAADCggICAAAAA==.',Vo='Voxifera:BAAALAAECgYICQAAAA==.',Vr='Vrykuln:BAAALAAECgYIEgAAAA==.',['Vè']='Vèl:BAAALAADCggICAAAAA==.',Wa='Wartooth:BAAALAAECgMIBgAAAA==.',Wi='Wickern:BAAALAADCggIFAAAAA==.Willowtreé:BAAALAADCggIEAAAAA==.Windwatcher:BAAALAAECgMIBgAAAA==.',Xd='Xdiesel:BAAALAAECgcIDAAAAA==.',Ya='Yakubu:BAAALAAECggIDgAAAA==.',Yo='Young:BAAALAAECgIIAgAAAA==.',Za='Zabuzan:BAACLAAFFIEJAAMKAAQI2xxSAQCUAQAKAAQI2xxSAQCUAQAQAAIIJQtcCABvAAAsAAQKgSkAAgoACAgPJv0BAHgDAAoACAgPJv0BAHgDAAAA.Zador:BAAALAAECgMIBgAAAA==.Zalstra:BAAALAADCgcIDQAAAA==.Zarupia:BAAALAAECgYICAAAAA==.',Ze='Zepphiron:BAAALAADCggICAAAAA==.',Zi='Zihso:BAAALAAECgMIBgAAAA==.',Zo='Zonuu:BAAALAADCggIDQABLAAECgMIBgACAAAAAA==.Zoroastrian:BAAALAAECgUICwAAAA==.',Zw='Zwerfur:BAAALAADCggICgAAAA==.',['Ém']='Émilia:BAAALAADCgYIBgAAAA==.Émortal:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end