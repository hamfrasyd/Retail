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
 local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','Unknown-Unknown','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Hunter-Marksmanship','Monk-Brewmaster','Mage-Fire','Mage-Frost','Priest-Holy','Paladin-Retribution','Druid-Balance','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','DeathKnight-Frost','DeathKnight-Unholy',}; local provider = {region='EU',realm='Echsenkessel',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ag='Agro:BAAALAADCggIEAAAAA==.',Aj='Ajel:BAAALAAFFAIIAgAAAA==.',Ak='Akadech:BAAALAADCgcIBwAAAA==.',Ar='Arathia:BAAALAADCggICAAAAA==.Argador:BAABLAAECoEXAAMBAAgIdx+GAwCZAgABAAgIdx+GAwCZAgACAAEIIgSBigAzAAABLAAFFAIIAgADAAAAAA==.Aridala:BAAALAADCggIEwAAAA==.Arnakuagsak:BAAALAAECgcIEAAAAA==.',As='Asafiri:BAAALAADCgYIBgAAAA==.Ashi:BAAALAAECgQIBAABLAAECggIFgAEABkcAA==.Ashkael:BAAALAADCggIEAAAAA==.',At='Ataxis:BAAALAADCggICAAAAA==.Atze:BAAALAAECgYIDAAAAA==.',Av='Avalas:BAAALAAECgUICwAAAA==.Aviá:BAAALAAECgIIAgAAAA==.',Ay='Ayuzuria:BAABLAAECoEXAAMFAAgIphiACADWAQAFAAcINRiACADWAQAGAAgIIwsRFQDOAQAAAA==.',Az='Azuchapus:BAAALAAECgMIBQAAAA==.',Ba='Baltor:BAAALAAECgcIEQAAAA==.',Be='Benny:BAAALAAFFAEIAQAAAA==.',Bh='Bhalrog:BAAALAAECgUIDQAAAA==.',Bi='Bimsalasim:BAAALAAECgIIAgAAAA==.',Bj='Björnström:BAAALAADCgEIAQAAAA==.',Bl='Blintschiki:BAAALAAECgIIAwAAAA==.Blitzfuchs:BAAALAADCggICwABLAAECggICAADAAAAAA==.Bloodeye:BAAALAADCgYIBgAAAA==.Bloodraven:BAABLAAECoEVAAQHAAgIYhvaCAA9AgAHAAcI3xvaCAA9AgAIAAIIqBgZGwCsAAAJAAEIBRBiZgA/AAAAAA==.',Bo='Bombär:BAAALAAECggIEgAAAA==.Boxxi:BAAALAADCgQIBAAAAA==.',Br='Brillux:BAABLAAECoEVAAIKAAgIXBy0CwCoAgAKAAgIXBy0CwCoAgAAAA==.Bruderhorst:BAAALAADCgcIBwAAAA==.',['Bî']='Bîernot:BAAALAAECgEIAQAAAA==.',Ca='Carnivora:BAAALAAECgYIBgAAAA==.Caîne:BAAALAADCgYICgABLAAECgYIEAADAAAAAA==.',Cr='Creami:BAAALAADCgcIDQAAAA==.',Cy='Cypherdrone:BAAALAADCgcIBwAAAA==.',De='Deathknight:BAAALAAECgMIBAAAAA==.Demoniaa:BAAALAAECgEIAQAAAA==.Deréntis:BAAALAAECgcIEwAAAA==.',Di='Diabout:BAAALAAECgMIBAAAAA==.Divinetales:BAAALAAFFAMIAwAAAA==.',Do='Donnatroy:BAAALAADCggIFwAAAA==.Doppelfrogg:BAAALAADCgMIAwAAAA==.',Dr='Dragonlord:BAAALAAECgEIAQAAAA==.Drecon:BAAALAAECgQIBAAAAA==.Druggy:BAAALAADCggICAAAAA==.',['Dä']='Dämonenfuchs:BAAALAADCggIDgABLAAECggICAADAAAAAA==.',El='Elaih:BAAALAAECgMIAwAAAA==.Eldhior:BAAALAADCgcIBwAAAA==.',Em='Emden:BAAALAADCgcIBwABLAAECgYIDAADAAAAAA==.',En='Enhuensn:BAAALAADCgQIBAAAAA==.Ensa:BAAALAAECgMIBQAAAA==.',Ep='Epiphany:BAAALAAECgMIBAAAAA==.',Fa='Fabsl:BAAALAADCggICAAAAA==.Facemeltorz:BAAALAADCgQIBAABLAADCgcIBwADAAAAAA==.',Fl='Flameon:BAAALAADCgEIAQAAAA==.Floki:BAAALAAECgYIEAAAAA==.',Fu='Fuji:BAAALAADCgYIBgAAAA==.Fulgur:BAAALAADCgcIBwAAAA==.',Ga='Garaldor:BAAALAADCggICAABLAAFFAIIAgADAAAAAA==.Garmiant:BAAALAAECgcIBwABLAAFFAIIAgADAAAAAA==.Gatrig:BAAALAAECgEIAQAAAA==.',Gh='Ghouldan:BAABLAAECoEXAAMJAAgIkBopEQBdAgAJAAgIlBgpEQBdAgAHAAYI9RwdDwDtAQAAAA==.',Go='Goldendemon:BAAALAAECgMIAwAAAA==.Goldenpriest:BAAALAAECgYIBgAAAA==.',Gr='Grehna:BAAALAADCgUIBQAAAA==.Grygoria:BAAALAADCgcIDQAAAA==.',Ha='Hagebär:BAAALAAECgYICAAAAA==.Haumíchum:BAAALAAECgcIEgAAAA==.',He='Healiix:BAAALAADCgcIBwAAAA==.',Hi='Himemiya:BAAALAAECgYIDAAAAA==.Hirara:BAABLAAECoEUAAILAAgIuxWtFwDOAQALAAgIuxWtFwDOAQAAAA==.Hisse:BAAALAADCgYIBgAAAA==.',Hu='Hunthor:BAAALAAECgMIBAAAAA==.',Ic='Icarium:BAAALAAECgYIEAAAAA==.Icedearth:BAAALAADCgUIBQAAAA==.Icee:BAAALAADCgYIAwABLAAECggIFgAEABkcAA==.Iceplexus:BAAALAAECggIEAAAAA==.',Il='Ildabeam:BAAALAAECgYIDQAAAA==.',In='Inu:BAAALAADCggIDQAAAA==.Inuki:BAAALAAECgYIBwABLAAECggIFwAFAKYYAA==.',Ir='Iryeos:BAAALAAECgcIDQAAAA==.',Ja='Jaqhi:BAAALAADCggICAABLAAECggIFwAMAA8fAA==.Jayqui:BAABLAAECoEXAAIMAAgIDx9BAwDQAgAMAAgIDx9BAwDQAgAAAA==.',Ji='Jincy:BAAALAAECgcICgAAAA==.Jincydruid:BAAALAAECggICAAAAA==.',Ka='Kanaga:BAAALAADCgcIAwAAAA==.Karanti:BAAALAADCgcIBwAAAA==.Kaymera:BAAALAADCggICAAAAA==.',Kh='Khersha:BAAALAAECgYIBgAAAA==.',Ki='Kirchenwirt:BAAALAADCgcIBwAAAA==.',Ko='Koffie:BAAALAAECgYIBgAAAA==.Kota:BAABLAAECoEVAAMNAAgILB+AAAAEAwANAAgILB+AAAAEAwAOAAYIOBQkHABoAQAAAA==.',Kp='Kptn:BAAALAAECggIEAAAAA==.',Le='Leechia:BAAALAAECgIIAwAAAA==.Lennox:BAAALAAECgIIAgAAAA==.Leshi:BAABLAAECoEVAAIPAAgIvhWxEwAoAgAPAAgIvhWxEwAoAgAAAA==.',Li='Liesanna:BAAALAADCggICAAAAA==.Liizz:BAAALAADCgEIAQAAAA==.Lilliandra:BAAALAADCggIFwAAAA==.',Lo='Lockybalboà:BAAALAADCggIDgABLAAECggIFQAQAKkiAA==.Loonrage:BAAALAADCgcIBwAAAA==.Lophenia:BAAALAADCgcIBwAAAA==.Lothi:BAAALAAECgUIBQAAAA==.',Ma='Mandos:BAAALAAECgcIDgAAAQ==.Masodist:BAAALAAECgYIBgAAAA==.',Mc='Mcmuffin:BAAALAAECgIIAgAAAA==.',Me='Me:BAAALAAECgYIDgAAAA==.',Mi='Mieze:BAAALAADCgcIDAAAAA==.Milie:BAACLAAFFIEGAAIPAAMI9Q6ZAwABAQAPAAMI9Q6ZAwABAQAsAAQKgRUAAg8ACAhdGBkOAGUCAA8ACAhdGBkOAGUCAAAA.Milli:BAAALAAECgMIAwABLAAFFAMIBgAPAPUOAA==.Mirakulix:BAABLAAECoEWAAIRAAgIKhoVDAB1AgARAAgIKhoVDAB1AgAAAA==.Miriamda:BAAALAAECgMIAwAAAA==.',Mo='Mokbahrn:BAAALAAECgYICgAAAA==.',My='Mysalim:BAAALAAFFAIIAgAAAA==.Myu:BAAALAADCggICAAAAA==.',['Mî']='Mîdnight:BAAALAADCggIDwAAAA==.',['Mü']='Münlì:BAAALAAECgYIBwAAAA==.Müsli:BAABLAAECoEUAAISAAcI4B3QDQB6AgASAAcI4B3QDQB6AgAAAA==.',Na='Nachtfuchs:BAAALAAECggICAABLAAECggICAADAAAAAA==.Nam:BAAALAADCggIDgAAAA==.Nanashii:BAAALAAECgYICAAAAA==.',Ne='Nene:BAAALAADCgUIBQAAAA==.Nexev:BAAALAADCgcIDgAAAA==.',Ni='Niahri:BAAALAAECgQIBAAAAA==.Nichsotief:BAAALAAECgcICwAAAA==.',No='Norsîa:BAAALAADCgcIEAAAAA==.',Ny='Nymora:BAAALAADCgYIBgAAAA==.',Ok='Oksana:BAAALAADCggICAAAAA==.',Or='Orakel:BAAALAADCgYIBgABLAAECgcIEQADAAAAAA==.',Pe='Perian:BAAALAAECgMIBQAAAA==.',Ph='Phèlan:BAAALAAECgcIDwAAAA==.',Pr='Precioso:BAAALAAECgcIBwAAAA==.Prestabo:BAAALAADCgcIBwAAAA==.',Pu='Puschl:BAAALAAECgYIDQAAAA==.Pusteblume:BAAALAAECgMIBAAAAA==.',Ra='Raimy:BAAALAAECgEIAQAAAA==.Rapidfire:BAAALAADCggIFgAAAA==.',Re='Reaperxdante:BAAALAAECgIIAwAAAA==.Remornia:BAAALAADCgUIBQABLAADCggICAADAAAAAA==.Renneria:BAAALAADCgMIAwAAAA==.',Rh='Rhababara:BAAALAADCgcICgAAAA==.Rhiâna:BAAALAAECgMIBwAAAA==.',Ro='Rothgar:BAAALAADCggIDwABLAAECgYIEAADAAAAAA==.',Ru='Rue:BAABLAAECoEVAAMSAAgIVB6ZDwBfAgASAAcIGR6ZDwBfAgAPAAEInAMAAAAAAAAAAA==.Rumi:BAABLAAECoEWAAIEAAgIGRzSBQCPAgAEAAgIGRzSBQCPAgAAAA==.Runcandel:BAAALAADCggICAAAAA==.',Ry='Rynthor:BAAALAAECgMIAwAAAA==.',['Rø']='Røulade:BAAALAAECgQICQAAAA==.',Sc='Schmalzo:BAAALAAECgMIAwAAAA==.',Se='Sectás:BAAALAADCggIEAAAAA==.Sedith:BAAALAADCgQIBAABLAADCggICAADAAAAAA==.',Sh='Shapeshift:BAAALAADCggICAAAAA==.Shea:BAAALAAECgEIAQABLAAECgMIAwADAAAAAA==.Sheltear:BAAALAADCggICAAAAQ==.',Si='Sigler:BAAALAAECgQIBwAAAA==.Sisaa:BAAALAAECggIEgAAAA==.Sisu:BAAALAADCgYIBgAAAA==.Sivanas:BAAALAAECggICgAAAA==.',Sk='Skalí:BAAALAAECggICgAAAA==.',Sn='Snoope:BAAALAAECgYIBwAAAA==.',So='Sodranoel:BAAALAAECggICAAAAA==.',St='Stechfuchs:BAAALAADCgcIDQABLAAECggICAADAAAAAA==.',['Sì']='Sìegfrìed:BAABLAAECoEVAAIQAAgIqSJ2BwATAwAQAAgIqSJ2BwATAwAAAA==.',Ta='Taiitó:BAAALAADCggIDgAAAA==.Tarnefana:BAEBLAAECoEVAAMTAAgIrSMGCQCoAgATAAcIIyEGCQCoAgAUAAMIxCFTDQAiAQAAAA==.',Tb='Tbøne:BAAALAADCgMIBAAAAA==.',Th='Theran:BAAALAAFFAIIAgAAAA==.Thorric:BAAALAADCgYIBgABLAAECgcIFAAVANEkAA==.Thorrik:BAABLAAECoEUAAIVAAcI0SR9BADdAgAVAAcI0SR9BADdAgAAAA==.',Ti='Tilo:BAAALAAFFAIIAgAAAA==.',To='Togo:BAAALAAECgQICAAAAA==.Toxical:BAAALAADCgUIBQAAAA==.',Tr='Trnkzz:BAAALAAECgIIAgAAAA==.',Ts='Tsoi:BAAALAAECgUIBgAAAA==.Tsundereclap:BAAALAAECgIIAwABLAAECgYICQADAAAAAA==.',Tu='Tusker:BAAALAADCgcIBwAAAA==.',Ty='Tyhla:BAAALAAECgMIBAAAAA==.Tyra:BAAALAADCggICAAAAA==.Tyrloc:BAAALAAECggIBwAAAA==.',Ug='Uglymon:BAAALAADCggICAAAAA==.',Va='Vaelira:BAAALAAECgcIEAAAAA==.Valaar:BAAALAAECgEIAgAAAA==.Valithria:BAAALAAECgYICwAAAA==.Valtherion:BAAALAADCgUIBQAAAA==.Vanessa:BAAALAADCggICAAAAA==.Varmint:BAAALAAECggIDgAAAA==.Varros:BAAALAAECgYICgAAAA==.Vatheron:BAABLAAECoEZAAIGAAgINiXzAABnAwAGAAgINiXzAABnAwAAAA==.',Ve='Velanda:BAAALAAECgIIAgAAAA==.Verono:BAAALAAECgYIDwAAAA==.',Vi='Violet:BAAALAADCggICAAAAA==.Virgilius:BAAALAADCgcIBwABLAAECgYICgADAAAAAA==.',Vo='Voidbert:BAABLAAECoEWAAISAAgIXhRgFQAYAgASAAgIXhRgFQAYAgAAAA==.',Wa='Warum:BAAALAAECgQIBAABLAAECgYICQADAAAAAA==.',Wi='Wieso:BAAALAAECgYICQAAAA==.Windfury:BAAALAADCggICQAAAA==.',Wo='Wobär:BAAALAAECgMIBgAAAA==.Wolfsdeath:BAAALAAECgMICAAAAA==.Wolfssatan:BAAALAADCgcIBwABLAAECgMICAADAAAAAA==.',Xa='Xaladoom:BAAALAAECgYIEAAAAA==.',Xe='Xerpy:BAACLAAFFIEHAAMWAAYI/xurAACfAQAWAAUIDiCrAACfAQAXAAEItgejBQBjAAAsAAQKgRQAAxYACAj8JfkBAGIDABYACAj8JfkBAGIDABcAAQgcJJwuAGsAAAAA.',Ya='Yashako:BAAALAADCgcIDAABLAAECggIFgAEABkcAA==.',Ye='Yep:BAAALAADCgYIBgAAAA==.',Yn='Ynos:BAAALAADCgcIBwAAAA==.',Yo='Yomiko:BAAALAAECgIIAgAAAA==.Yorren:BAAALAAECgIIAwAAAA==.',Yu='Yukiji:BAAALAAECgYICgAAAA==.',Za='Zalty:BAAALAAECgYICAAAAA==.',Ze='Zercichan:BAAALAAECgEIAgAAAA==.',Zo='Zona:BAAALAADCgMIAwAAAA==.',Zu='Zulsaframano:BAAALAADCggICAAAAA==.',Zy='Zyrion:BAAALAADCggIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end