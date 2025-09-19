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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Balance',}; local provider = {region='EU',realm='DerMithrilorden',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aarón:BAAALAADCggIEAABLAAFFAEIAQABAAAAAA==.',Ac='Acavius:BAAALAAECggIAwAAAA==.Acoxagan:BAAALAAECgEIAQAAAA==.',Af='Affomickii:BAAALAADCgEIAQAAAA==.Affotropia:BAAALAADCgYIBwAAAA==.',Ag='Agrippae:BAAALAADCgcIBwAAAA==.',Al='Aleriana:BAAALAADCgcIEQABLAADCggIDQABAAAAAA==.',Am='Amidas:BAAALAAECgMIAwAAAA==.',An='Anganuk:BAAALAADCgMIAwAAAA==.Ansin:BAAALAAECgcIDgAAAA==.',Ar='Ara:BAAALAAECgEIAQAAAA==.Armadeyra:BAAALAAECgMIAwAAAA==.Arwensstern:BAAALAADCgYIBgAAAA==.',As='Asdromedos:BAABLAAECoEVAAICAAgIPho5JAD/AQACAAgIPho5JAD/AQAAAA==.Askalesia:BAAALAAECgMIAwAAAA==.Astarion:BAAALAADCgYIDAAAAA==.',Au='Aurion:BAAALAADCgQIBwAAAA==.',Av='Aventurian:BAAALAAECgEIAQAAAA==.',Az='Azuron:BAAALAAECgQIBwAAAA==.',Ba='Bariga:BAAALAADCggIBgAAAA==.',Be='Bearnose:BAACLAAFFIEIAAIDAAMIKR4vAQAvAQADAAMIKR4vAQAvAQAsAAQKgRoAAgMACAjaIv8BAA8DAAMACAjaIv8BAA8DAAAA.Belamy:BAAALAAECgIIBAAAAA==.',Bl='Blackschaman:BAAALAADCggIEwAAAA==.Bluki:BAAALAAECgMIBAAAAA==.',Bo='Bomradur:BAAALAAECgcIDwAAAA==.',Br='Bramgar:BAAALAADCggIDQAAAA==.Brogan:BAAALAADCggIFwAAAA==.Broguard:BAAALAADCgYIBgAAAA==.',Ca='Caramel:BAAALAAECgIIAgAAAA==.',Ce='Celdaron:BAAALAAECgcIDQAAAA==.',Co='Cochones:BAAALAAECgQIBAAAAA==.',Cr='Croonos:BAAALAADCggIEAAAAA==.Cryp:BAAALAADCggICAAAAA==.',Cy='Cycløn:BAAALAADCgYIBgAAAA==.',Da='Dagum:BAAALAADCggIDwAAAA==.Dane:BAAALAAECgEIAQAAAA==.Darkjii:BAAALAADCggICAAAAA==.Daryun:BAAALAADCggICAAAAA==.',De='Deathtoll:BAAALAAECgIIAgAAAA==.Dem:BAAALAADCgQIBAAAAA==.Demonia:BAAALAAECgIIAgAAAA==.Dendra:BAAALAADCgIIAgAAAA==.',Dh='Dhârá:BAAALAADCgIIAQAAAA==.',Do='Dotexe:BAAALAADCggICAAAAA==.Doty:BAAALAAECgEIAQAAAA==.',Dr='Druinos:BAAALAADCgcIBwAAAA==.Dryex:BAAALAADCggICAAAAA==.Drágomir:BAAALAADCgIIAgAAAA==.',['Dä']='Dämmer:BAAALAADCgQIBAAAAA==.Dämonin:BAAALAAECgYICgAAAA==.',['Dæ']='Dæx:BAAALAADCggIDwAAAA==.',['Dí']='Díggor:BAAALAADCggIEAAAAA==.Díru:BAABLAAECoEVAAIDAAgIog7DIACFAQADAAgIog7DIACFAQAAAA==.',Ei='Eisenwolf:BAAALAAECgEIAQAAAA==.',El='Eldunari:BAAALAADCggICAAAAA==.',Em='Emphira:BAAALAAECgEIAQAAAA==.',Er='Erdbärsahne:BAAALAADCggIEAAAAA==.',Es='Eskair:BAAALAAECggIDgAAAA==.Esmé:BAAALAADCgYIBgAAAA==.',Ex='Exodus:BAAALAAECgEIAQAAAA==.',Fa='Faylith:BAAALAAFFAEIAQAAAA==.',Fe='Fenerica:BAAALAADCgMIAwAAAA==.Fenny:BAAALAADCgQIBwAAAA==.',Fi='Finnson:BAAALAADCgcIBwAAAA==.Fireburner:BAAALAAECgYIEAAAAA==.',Fu='Furianix:BAAALAAECgEIAQAAAA==.Furin:BAAALAADCgcIBwABLAAECgcIDgABAAAAAA==.Furiøus:BAAALAADCggICgAAAA==.',Ga='Gareka:BAAALAADCgUIAQAAAA==.',Ge='Gerrî:BAAALAAECgcIDwAAAA==.',Gi='Gizisham:BAAALAAECgYICAAAAA==.',Go='Goshan:BAAALAADCggIBQAAAA==.',Gr='Grandos:BAAALAAFFAIIBAAAAA==.Gridy:BAAALAADCgQIBgAAAA==.',Gs='Gschafaar:BAAALAAECgEIAQAAAA==.',Gw='Gwifith:BAAALAAECgEIAQAAAA==.',Ha='Haava:BAAALAADCgQIBwAAAA==.Hazzenpala:BAABLAAECoEXAAICAAgI1SJBBwAXAwACAAgI1SJBBwAXAwAAAA==.',He='Healmaster:BAAALAAECgMIBAAAAA==.',Ho='Holydox:BAAALAADCgQIBAAAAA==.Hopeful:BAAALAAECgMIAwABLAAECgMIBgABAAAAAA==.Hornia:BAAALAADCgcIDQAAAA==.',Ic='Icd:BAAALAADCgYIBgAAAA==.Icécube:BAAALAADCggIEAABLAAFFAEIAQABAAAAAA==.',Il='Ileila:BAAALAADCggICAAAAA==.Illuminor:BAAALAAECgcIDgAAAA==.Illyriá:BAAALAAECgMIBAAAAA==.',Is='Iskalder:BAAALAADCggICAAAAA==.Isuna:BAAALAAECgIIAgAAAA==.',Ja='Jadyeracrow:BAAALAADCgYIBgAAAA==.',Jo='Jon:BAAALAAECgMIBgAAAA==.',Ka='Kaltesherz:BAAALAADCggIEAAAAA==.Kamaro:BAAALAAECgEIAQABLAAECgYIDQABAAAAAQ==.',Ke='Kecklienchen:BAAALAADCgQIBwAAAA==.',Ko='Kojiro:BAAALAADCgUIBQABLAAECgcIDwABAAAAAA==.',Kr='Krachbu:BAAALAAECgEIAQAAAA==.Krístoff:BAAALAAECgYICwAAAA==.',Ku='Kumako:BAAALAADCgQIBwAAAA==.Kuzaku:BAAALAAECgcIDwAAAA==.',['Kê']='Kêcklienchen:BAAALAADCggICAAAAA==.',La='Lakotas:BAAALAAECgMIAwAAAA==.',Le='Leconer:BAAALAAECgYICgAAAA==.Lewar:BAAALAAECgcIDQAAAA==.',Li='Lightkeeper:BAAALAAECgMIBgAAAA==.Linnik:BAAALAAECgQIBgAAAA==.Liondra:BAAALAAECgcIDQAAAA==.',Lo='Lorey:BAAALAAECgIIAwAAAA==.',Lu='Lukbox:BAAALAAECgEIAQAAAA==.Lundizo:BAAALAADCggIFAAAAA==.',Ly='Lyrià:BAAALAADCggICAAAAA==.',['Lü']='Lüise:BAAALAADCgIIAgAAAA==.Lünöa:BAAALAADCggIGgAAAA==.',Ma='Maerlin:BAAALAADCggICwAAAA==.Magmatûs:BAAALAADCgEIAQAAAA==.Marmax:BAAALAADCggICAAAAA==.Maruki:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Mawa:BAAALAAECgEIAgAAAA==.Maxera:BAAALAAECgIIAgAAAA==.',Mc='Mccragg:BAAALAADCgYIBgAAAA==.',Me='Meko:BAAALAAECgcIDwAAAA==.',Mi='Michaelixx:BAAALAADCgcIDQAAAA==.',Mo='Morima:BAAALAAECgEIAQAAAA==.Moritana:BAAALAADCgMIAwAAAA==.Morphdeamon:BAAALAADCggIEAABLAAECgcIDQABAAAAAA==.Mozzo:BAAALAAECgMIBQAAAA==.',Mu='Mubarak:BAAALAADCgEIAQAAAA==.Munuun:BAAALAAECgIIAgAAAA==.Murdil:BAAALAAECgMIBAAAAA==.',My='Myouzó:BAAALAAECgcIEAAAAA==.Myrael:BAAALAAECgYIDwAAAA==.Mystîque:BAAALAAECgEIAQABLAAECgIIAgABAAAAAA==.',['Mä']='Märlien:BAAALAADCgQIBAAAAA==.',['Mê']='Mêrlín:BAAALAADCgYICQAAAA==.',Na='Nagut:BAAALAADCggIDQAAAA==.Nakorem:BAAALAADCggICAAAAA==.Nakwa:BAAALAADCggIDgAAAA==.Nashsven:BAAALAADCgEIAQAAAA==.',Ni='Nichaun:BAAALAAECgMIBAAAAA==.Nikkee:BAAALAADCgUIDAAAAA==.Ninsles:BAAALAADCggIDgAAAA==.',No='Norania:BAAALAADCgcIBwAAAA==.Noricul:BAAALAAECgQIBwAAAA==.Norin:BAAALAAECggIDQAAAA==.',['Ná']='Náfalia:BAAALAAECgcIDQAAAA==.',['Né']='Néele:BAAALAADCgYICQAAAA==.',Ob='Obscurus:BAAALAADCggIDwAAAA==.',Ov='Oversize:BAAALAAECgYIBgAAAA==.',Pa='Paladrin:BAAALAADCgQIAgAAAA==.Palomino:BAAALAAECgIIAgAAAA==.',Pi='Piorun:BAAALAAECgMIBwAAAA==.Pip:BAAALAADCggICAAAAA==.',Po='Polarion:BAAALAADCgQIBwAAAA==.',Pu='Puren:BAAALAAECgMIBgAAAA==.',Qu='Quastos:BAAALAADCgIIAgAAAA==.',Ra='Ralanji:BAAALAAECgEIAQAAAA==.Razzulmage:BAAALAAECggIAQAAAA==.',Re='Reesi:BAAALAAECgEIAQAAAA==.',Ri='Ribaldcorelo:BAAALAADCgcICQAAAA==.',Ro='Ronotron:BAAALAAECgEIAQAAAA==.Roxus:BAAALAADCggIDgAAAA==.',Ru='Ruki:BAAALAADCggICAAAAA==.',Ry='Rynu:BAAALAADCgcIBwAAAA==.',Sa='Sallykitty:BAAALAAECgcIDwAAAA==.Saphiranda:BAAALAADCgcIBwAAAA==.Sarthara:BAAALAAECggICAABLAAECggIDQABAAAAAA==.',Sc='Scharella:BAAALAADCgQIBwAAAA==.Schaumfolger:BAAALAAECgIIAwAAAA==.Schneehasi:BAAALAADCgcIBwAAAA==.',Sh='Shadowigor:BAAALAADCggICAAAAA==.Shadowrayne:BAAALAAECgEIAQAAAA==.Shamanalekum:BAAALAAFFAEIAQABLAAFFAEIAQABAAAAAA==.Shamanski:BAAALAAECgYIDgAAAA==.Shangchi:BAAALAAECgEIAQABLAAFFAEIAQABAAAAAA==.Shaylah:BAAALAADCggIFAAAAA==.',Si='Sinesefer:BAAALAADCgcIBwAAAA==.',Sk='Skydo:BAAALAAECgcIDQAAAA==.',Sl='Sloia:BAAALAADCgQIBwAAAA==.Slyriass:BAAALAADCggIDwAAAA==.',So='Solix:BAAALAAECgMIAgAAAA==.',Sp='Spyró:BAAALAAECgcIDgAAAA==.',St='Stapfan:BAAALAADCgIIAgAAAA==.',Su='Sunrisei:BAAALAADCgYIBgAAAA==.',Sy='Sylthara:BAAALAAECgcIDgAAAA==.',Ta='Takia:BAAALAAECgQIBwAAAA==.Tapion:BAAALAADCgcIDgAAAA==.Taraan:BAAALAAECgIIAgAAAA==.',Te='Teldur:BAAALAAECgEIAQAAAA==.',Th='Thalorien:BAAALAADCgcICgAAAA==.Thingol:BAAALAADCgYIBgAAAA==.Thorân:BAAALAAECgYIDAAAAA==.Thyr:BAAALAADCggICAAAAA==.Thòran:BAAALAADCggICwABLAAECgYIDAABAAAAAA==.Thôrân:BAAALAADCgUIBQABLAAECgYIDAABAAAAAA==.',Ti='Tiramisu:BAAALAADCgMIAwAAAA==.',To='Tomatensauce:BAAALAAECgQIBwAAAA==.Torenga:BAAALAADCgcICAAAAA==.Tormentus:BAAALAADCggIDgAAAA==.',Ts='Tsutey:BAAALAADCggICQAAAA==.',Tu='Tuura:BAAALAADCggICAAAAA==.',['Tá']='Tálari:BAAALAAECgcIDwAAAA==.',Ve='Vemeria:BAAALAAECgMIBgAAAA==.',Vi='Vidrix:BAAALAADCgQIBwAAAA==.Virusz:BAAALAADCgcICgAAAA==.',Vo='Vollstrécker:BAAALAADCggIFAAAAA==.',Wa='Walahfrid:BAAALAAECgQIBwAAAA==.Walsh:BAAALAADCggICAAAAA==.',We='Wetzler:BAAALAADCgQIBwAAAA==.',Wi='Willgates:BAACLAAFFIEFAAMEAAMIdRFuBgDBAAAEAAMIdRFuBgDBAAAFAAIIjhPbBACrAAAsAAQKgRcABAQACAiaJG8CAE8DAAQACAiYJG8CAE8DAAUABQimFjUlAEQBAAYAAghpHagZALkAAAAA.',Wo='Worlly:BAAALAAECgcIEAAAAA==.',Xa='Xaáru:BAAALAAECggICAAAAA==.',Xe='Xellesia:BAAALAADCgcIBwAAAA==.Xenor:BAAALAAECgIIAgABLAAFFAIIBAABAAAAAA==.',Ya='Yanua:BAAALAADCggICAAAAA==.Yappies:BAAALAAECgcIBwAAAA==.',Ye='Yelenaay:BAAALAADCgYIBgAAAA==.',Yu='Yukî:BAABLAAECoEUAAMDAAgI+SD8BAC9AgADAAgI+SD8BAC9AgAHAAEIqAVsVAAmAAAAAA==.',Za='Zarkarion:BAAALAADCggICAAAAA==.',Zo='Zouh:BAAALAAECgUIBQAAAA==.',Zu='Zussa:BAAALAAECgIIAgAAAA==.',['Àl']='Àlysth:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.',['Án']='Ángélus:BAAALAAECgMIAwAAAA==.',['Áá']='Áárón:BAAALAADCgYIBgABLAAFFAEIAQABAAAAAA==.',['Âl']='Âluka:BAAALAAECgYIBgAAAA==.',['Ãr']='Ãryulie:BAAALAADCgcICwAAAA==.',['Ær']='Ærdsturm:BAAALAADCggICAAAAA==.',['Ód']='Ódina:BAAALAADCgcIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end