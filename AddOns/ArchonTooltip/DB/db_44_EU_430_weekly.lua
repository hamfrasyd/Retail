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
 local lookup = {'Unknown-Unknown','DeathKnight-Blood','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Monk-Windwalker','Priest-Discipline','Mage-Arcane','Paladin-Protection','Warrior-Fury','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Enhancement',}; local provider = {region='EU',realm='Frostmourne',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aatroce:BAAALAAECgEIAQABLAAECgMIAwABAAAAAA==.',Ab='Abigaile:BAAALAAECgcIDQAAAA==.Abrahammer:BAAALAADCgcIBwAAAA==.',Ae='Aeluneth:BAAALAADCgIIAgAAAA==.Aenthyr:BAAALAADCggIAgAAAA==.Aerojin:BAAALAAECgMIBQAAAA==.Aeve:BAAALAAECgYICgAAAA==.',Ai='Airy:BAAALAADCggICAAAAA==.',Aj='Ajina:BAAALAAECgQICAAAAA==.',Ak='Akamechân:BAACLAAFFIEFAAICAAMI+RYvAQADAQACAAMI+RYvAQADAQAsAAQKgRgAAgIACAi3IRMCABEDAAIACAi3IRMCABEDAAAA.Akasha:BAAALAADCgcICgAAAA==.',Al='Aldania:BAAALAADCgMIAwAAAA==.Alessà:BAAALAAECgUIBwAAAA==.',Am='Amailana:BAAALAAECgEIAQABLAAECgUIBQABAAAAAA==.Amarru:BAACLAAFFIEFAAIDAAMIhxbvAgANAQADAAMIhxbvAgANAQAsAAQKgRcAAgMACAjNHuMHAL0CAAMACAjNHuMHAL0CAAAA.Ambrò:BAABLAAECoEWAAIEAAgIAyA6BgDWAgAEAAgIAyA6BgDWAgAAAA==.',An='Andreá:BAAALAADCggIGAAAAA==.Anri:BAAALAADCggIFQAAAA==.Anunnaki:BAAALAAECgMIAwAAAA==.',Ar='Arator:BAAALAADCgYIBgAAAA==.Aryasine:BAAALAAECgYICgAAAA==.',As='Ashyra:BAAALAAECgEIAQAAAA==.Asiontis:BAABLAAECoEWAAMFAAgIvCPmBQAPAwAFAAgIrCLmBQAPAwAEAAcI2h+9CQCRAgAAAA==.Asurei:BAAALAADCgYIBgAAAA==.',At='Ativivi:BAAALAAECgMIAwAAAA==.',Ay='Ayana:BAAALAAECgEIAQAAAA==.',Az='Azaha:BAACLAAFFIEIAAIGAAQIhxqBAACLAQAGAAQIhxqBAACLAQAsAAQKgRgAAgYACAh0Jg0BAIADAAYACAh0Jg0BAIADAAAA.',Ba='Baaym:BAAALAAECgEIAQAAAA==.Backautomat:BAAALAAECgEIAQAAAA==.Balenty:BAAALAAECgMICAAAAQ==.Bambamsen:BAAALAAECgIIAgAAAA==.Bambelbe:BAAALAADCgQIBAAAAA==.Barrager:BAAALAADCgcIBwAAAA==.',Be='Bellebaatar:BAAALAAFFAIIBAAAAA==.Benzino:BAAALAADCggIDgAAAA==.Bethen:BAAALAAECgYICgAAAA==.',Bi='Bigboydps:BAAALAAECgYIDAAAAA==.',Bl='Blink:BAAALAAECgIIAgAAAA==.Bloodcrane:BAAALAADCgQIBAAAAA==.Blóódge:BAAALAADCgIIAgAAAA==.Blôôdge:BAAALAAECgIIAgAAAA==.',Bo='Boomsenn:BAAALAAECgMIAwAAAA==.Borodir:BAAALAADCggIFwAAAA==.',Br='Brecs:BAAALAAECggIDwAAAA==.Brocktar:BAAALAAECgMIBAAAAA==.',Bu='Bullhahn:BAAALAADCggIDgAAAA==.Butscher:BAAALAADCgcIDQAAAA==.',['Bê']='Bêtrix:BAAALAADCgUIBQAAAA==.',Ca='Cani:BAAALAADCgUIBQAAAA==.Carissima:BAAALAADCgYICAAAAA==.Cashncarry:BAAALAADCgcIBgAAAA==.',Ce='Cepheid:BAAALAADCggICAAAAA==.Cerys:BAAALAAECgUIBwAAAA==.Cessai:BAABLAAECoEWAAIDAAgIzxc2DwBYAgADAAgIzxc2DwBYAgAAAA==.',Ch='Chalow:BAAALAAECgMIAwAAAA==.Chaoz:BAAALAADCgYIBgAAAA==.',Ci='Cirila:BAAALAAECgEIAQAAAA==.',Co='Cobi:BAAALAAECggIEQAAAA==.',Da='Daizawa:BAAALAAECgcICwAAAA==.Damnbro:BAAALAADCgcIBwAAAA==.Danie:BAAALAADCggIGAAAAA==.Darzz:BAAALAADCggIDgABLAADCggIDgABAAAAAA==.',De='De:BAAALAAECgcIEAAAAA==.Deathhulf:BAAALAADCgcIDQAAAA==.Deflector:BAAALAADCggICAAAAA==.Delia:BAAALAAECgcIDgAAAA==.Demonicsoul:BAAALAADCgcIBwABLAAECgYICgABAAAAAA==.Dertotemtyp:BAAALAAECgYICwAAAA==.Deusregum:BAAALAAECgIIAgAAAA==.',Dk='Dkdanja:BAAALAADCggICwAAAA==.',Dn='Dny:BAACLAAFFIEGAAMHAAQI9BElAAByAQAHAAQI9BElAAByAQAIAAEI8wFgFgBAAAAsAAQKgSAAAwgACAiEIhMQAKECAAgACAiGIBMQAKECAAcABggKHRcKAAwCAAAA.',Do='Doclynx:BAAALAAECgcICQAAAA==.Donk:BAAALAAECgMIAwAAAA==.',Dr='Drachenhuso:BAAALAAECggICAAAAA==.Dragondeez:BAAALAAECgYICAAAAA==.Drekakona:BAAALAADCgcICgAAAA==.Drivebypetra:BAAALAAECgQIBAAAAA==.',Ds='Dsumma:BAAALAAECgYICwAAAA==.',Dv='Dvalinn:BAAALAADCgcIDQAAAA==.',Ea='Earthbane:BAAALAADCgYIBgAAAA==.',Eb='Eblis:BAAALAAECgcIDgAAAA==.',El='Elânt:BAAALAAECgYICgAAAA==.',En='Encor:BAAALAAECgYICQAAAA==.Ender:BAAALAAECgIIAgAAAA==.Enorah:BAAALAAECgYIDAAAAA==.',Er='Erikes:BAAALAAECgQIBwAAAA==.',Eu='Euke:BAAALAAECgIIBQAAAA==.',Ev='Evêyh:BAAALAAECgYICwAAAA==.',Fa='Falerah:BAAALAADCgEIAQAAAA==.Farvounius:BAAALAADCggIDwAAAA==.',Fi='Fion:BAAALAAECgcIDgAAAA==.',Fo='Folker:BAAALAAECgUIDAAAAA==.Forestghost:BAAALAADCgUIBQAAAA==.Foria:BAAALAAECgYIBgAAAA==.Forsilaiser:BAAALAADCggIEAAAAA==.Foxdeath:BAAALAAECgYICQAAAA==.',Fr='Franziskaner:BAAALAADCggIFAAAAA==.',['Fü']='Fürchtegott:BAAALAADCggIEwAAAA==.',Ge='Getreal:BAAALAAECgQICAAAAA==.',Gl='Glotzer:BAAALAADCggIEAAAAA==.',Go='Gojosatoru:BAAALAADCggIDgAAAA==.Gorash:BAAALAADCgcIAwAAAA==.',Gr='Gray:BAAALAAECgYICgAAAA==.Greeven:BAAALAAECgYICgAAAA==.Gremory:BAAALAAECgYIDAABLAAFFAMIBQACAPkWAA==.Großdobby:BAAALAAECgQIBwAAAA==.',Gu='Gulfim:BAAALAAECgcIDAAAAA==.Guruno:BAAALAADCggIEAAAAA==.',Gw='Gwinever:BAAALAAECgUICAAAAA==.',Hi='Hidratos:BAAALAADCggICAABLAADCggIEwABAAAAAA==.Highsound:BAABLAAECoEXAAIJAAgIlxuVCgCuAgAJAAgIlxuVCgCuAgAAAA==.Hilond:BAAALAADCggIFgAAAA==.Hinat:BAAALAAECgMIBAAAAA==.Hirru:BAAALAADCggIFwAAAA==.',Ho='Hordée:BAAALAAFFAEIAQAAAA==.Hornstar:BAAALAADCggICQAAAA==.Hotuaek:BAAALAADCgYIDAAAAA==.',Hu='Hunterhulf:BAAALAAECgYIBgAAAA==.',Il='Ilune:BAAALAADCgEIAQAAAA==.',In='Inaria:BAAALAAECgYIDAAAAA==.Inmodudu:BAAALAAECgYICgAAAA==.',It='Itsmelove:BAACLAAFFIEIAAIDAAMIqxr2AQAjAQADAAMIqxr2AQAjAQAsAAQKgRgAAgMACAj2GhsNAHACAAMACAj2GhsNAHACAAAA.',Ja='Jayaa:BAAALAAECgMIAwAAAA==.',Jo='Jordy:BAAALAAECgYIDQAAAA==.',Ka='Kalidan:BAAALAADCgcICAAAAA==.Kashram:BAAALAADCgEIAQAAAA==.',Ke='Kekfist:BAABLAAECoEWAAIKAAgIfiIBAgAxAwAKAAgIfiIBAgAxAwAAAA==.Kelathel:BAAALAADCgQIBAAAAA==.',Ki='Kirenda:BAAALAAECgQIAwAAAA==.',Kl='Kleti:BAABLAAECoEYAAILAAgILiQ7AABQAwALAAgILiQ7AABQAwABLAAFFAMICAAMAK0WAA==.Kletom:BAABLAAFFIEIAAIMAAMIrRZ2BAANAQAMAAMIrRZ2BAANAQAAAA==.Kletos:BAAALAAECgYIBgABLAAFFAMICAAMAK0WAA==.',Kr='Krabàt:BAAALAADCgMIBQAAAA==.Kranklur:BAAALAAECgMIAwAAAA==.',['Kñ']='Kñøbísham:BAAALAADCggICAAAAA==.',La='Lana:BAAALAAECgYIBgAAAA==.Lanada:BAAALAADCgYIBgAAAA==.Larunami:BAAALAAECgEIAQAAAA==.Lauchzelot:BAACLAAFFIEFAAINAAMI+hwtAQDyAAANAAMI+hwtAQDyAAAsAAQKgRgAAg0ACAjyJXgAAHkDAA0ACAjyJXgAAHkDAAAA.',Le='Legos:BAAALAADCgYIBgAAAA==.Leline:BAAALAAECgYICQAAAA==.',Li='Lieebe:BAAALAAECgIIAgAAAA==.Limoian:BAAALAADCgUICQAAAA==.',Lo='Lolxd:BAAALAAFFAIIAgAAAA==.',Lu='Lungenpest:BAAALAAECgQICAAAAA==.Luri:BAAALAAECgQICAAAAA==.',Ly='Lytha:BAAALAAECgQIBwAAAA==.',['Lá']='Láúrá:BAAALAADCggIDQAAAA==.',['Ló']='Lótta:BAAALAADCgQIBAAAAA==.',Ma='Maezee:BAAALAADCggICAAAAA==.Mahina:BAAALAADCggICAAAAA==.Malika:BAAALAADCgQIBAAAAA==.Marvs:BAAALAADCggICAAAAA==.Mazhug:BAAALAAECgcIEQABLAAFFAQICAAGAIcaAA==.Maìa:BAAALAAECggIDwAAAA==.',Me='Melvyn:BAAALAAECgcIEAAAAA==.Meridan:BAAALAAECgUIBQAAAA==.Merô:BAAALAAECgYIBwAAAA==.',Mi='Mieuke:BAAALAADCggICQABLAAECgIIBQABAAAAAA==.Millimaus:BAAALAAECgQIBwAAAA==.',My='Myrtana:BAAALAAECgYICQAAAA==.Myrtix:BAAALAADCgYIBgAAAA==.',['Mé']='Mégus:BAAALAAECggIEgAAAA==.',Na='Nalia:BAAALAAECgQIBQAAAA==.Narak:BAAALAADCggIDwABLAAECgcIEQABAAAAAA==.Narkatoh:BAAALAAECgYIBAAAAA==.Natroll:BAAALAADCggICAAAAA==.Nayla:BAAALAADCggIEwAAAA==.',Ne='Neemi:BAAALAADCgEIAQAAAA==.Nekra:BAAALAAECgUIBgAAAA==.Nelfurion:BAAALAADCggICAABLAAECgYICgABAAAAAA==.Nerevar:BAAALAADCgcIDgAAAA==.',Ni='Nija:BAAALAAECgYIBgAAAA==.Nila:BAAALAAECgYIDQAAAA==.Nizana:BAAALAAFFAMICAAAAQ==.',No='Noemy:BAAALAAECgUIBQAAAA==.Nofugazi:BAAALAADCggIGAAAAA==.Nogí:BAAALAADCggIFQAAAA==.Notreeforyou:BAAALAAECgMIAwAAAA==.Novaz:BAACLAAFFIEIAAICAAMI8BsAAQAUAQACAAMI8BsAAQAUAQAsAAQKgRgAAgIACAg5JFIBAD8DAAIACAg5JFIBAD8DAAAA.',Nu='Nurôfen:BAABLAAECoEYAAIOAAgI8BfeFwAZAgAOAAgI8BfeFwAZAgAAAA==.',Ny='Nyissa:BAABLAAECoEVAAIPAAgI7hiDEABbAgAPAAgI7hiDEABbAgAAAA==.Nymtex:BAAALAADCgMIAwABLAADCgcIDgABAAAAAA==.',['Nê']='Nêltharion:BAAALAAECgYICgAAAA==.',On='Onkelztribut:BAAALAAECgYICgAAAA==.',Or='Orcens:BAAALAAECgQIBQAAAA==.',Pa='Paralilapsi:BAAALAADCgIIAgABLAADCgcIAwABAAAAAA==.Pauwy:BAAALAADCgcIBwAAAA==.',Pe='Pewpewlove:BAAALAAECgYIBgAAAA==.',Ph='Phänomenalia:BAAALAADCggICAAAAA==.Phänophilox:BAAALAAECgYIDAAAAA==.',Pu='Puccini:BAAALAADCggIDwAAAA==.',Ra='Raisedfist:BAAALAADCgYIBgAAAA==.Rakhun:BAAALAADCgEIAQABLAADCgQIBAABAAAAAA==.Rarg:BAAALAAECggICAAAAA==.Razzle:BAAALAADCgYIBgAAAA==.',Re='Reduwene:BAAALAAECgIIAgAAAA==.',Rh='Rhaenyra:BAAALAADCggICAAAAA==.',Ri='Rialana:BAAALAADCgcIBwABLAAFFAIIAwABAAAAAA==.',Ro='Roofus:BAAALAAECgMIBAAAAA==.',['Rô']='Rômulus:BAAALAADCgYIBgAAAA==.',Sa='Sagome:BAAALAAECgYICgAAAA==.Sangheili:BAAALAADCggIEwAAAA==.Saro:BAAALAAFFAIIAwAAAA==.Sataníc:BAAALAADCgcIDAAAAA==.',Sc='Schamordy:BAAALAADCggICAAAAA==.Scheppy:BAAALAADCgcIBwAAAA==.Schoko:BAAALAAECgMIBAAAAA==.',Se='Sempiternai:BAAALAAECgUIBQAAAA==.Serady:BAAALAAECgYIBwAAAA==.Sethan:BAAALAAECgMIBAAAAA==.Sethane:BAAALAAECgQIBwAAAA==.Sethin:BAAALAAECgMIBAAAAA==.Sethon:BAAALAADCgEIAQAAAA==.Seygu:BAAALAADCgcIBwAAAA==.',Sh='Shalamar:BAAALAADCggIFAAAAA==.Shanie:BAAALAAECgIIAgAAAA==.Shaquiloheal:BAAALAADCgcIBwAAAA==.She:BAAALAAECgMIBAAAAA==.Shinjikane:BAAALAADCggICAAAAA==.Shortydh:BAAALAADCgcIBwAAAA==.Shym:BAAALAAECgIIAgAAAA==.',Sk='Skanki:BAAALAADCgYIBgAAAA==.Skele:BAACLAAFFIEIAAMQAAMICCP/AADMAAAQAAII0CP/AADMAAARAAIIpBWcBwC2AAAsAAQKgRgAAxEACAg2JYQBAGQDABEACAiMJIQBAGQDABAACAgGI30BAAwDAAAA.',So='Sombalius:BAAALAAECgUIBwAAAA==.Soultaken:BAAALAAECgIIBAAAAA==.',St='Stranzi:BAAALAAECggIEQAAAA==.',Su='Suguru:BAAALAAECgYIDQAAAA==.',Sw='Swiizy:BAACLAAFFIEIAAISAAMInhxpAAANAQASAAMInhxpAAANAQAsAAQKgRgAAhIACAinJN0AAEYDABIACAinJN0AAEYDAAAA.Swizzy:BAAALAADCgEIAQAAAA==.',['Sô']='Sôngôku:BAAALAAECgYICgAAAA==.',Ta='Takashisa:BAAALAADCggICAAAAA==.Takayo:BAAALAADCggIGAAAAA==.Tallin:BAAALAAECgYIDAAAAQ==.Tann:BAAALAADCgYIBgABLAADCggIDgABAAAAAA==.Tanry:BAAALAADCggIDgAAAA==.Tatia:BAAALAADCgcIBwAAAA==.',Te='Telz:BAAALAADCgEIAQABLAAECgYICwABAAAAAA==.',Th='Thalîonmel:BAAALAAECgQIBwAAAA==.Thanea:BAAALAADCgcIDAAAAA==.Thorgâll:BAAALAAECgQIBwAAAA==.',Ti='Tinuviel:BAAALAADCggICAAAAA==.Tion:BAAALAADCgYIBQAAAA==.Tiranou:BAAALAAECgYIBgAAAA==.',To='Tobilicious:BAAALAAECgQICAAAAA==.',Tr='Tricky:BAAALAADCgEIAQAAAA==.',Ts='Tsabotavoc:BAAALAAECgEIAQAAAA==.',Ty='Tykja:BAAALAAECgYIDwAAAA==.',Ut='Utopian:BAAALAAECgUIDAAAAA==.',Va='Valfá:BAAALAAECgUIDAAAAA==.Vanisenpai:BAACLAAFFIEIAAITAAMIWiM3AABCAQATAAMIWiM3AABCAQAsAAQKgRcAAhMACAh/JjEAAHUDABMACAh/JjEAAHUDAAAA.',Vi='Vior:BAAALAAECgIIAwAAAA==.',Vo='Voltaire:BAAALAADCgMIAwAAAA==.',Vy='Vystara:BAAALAAECgMIAQAAAA==.',Wa='Wasserkraft:BAAALAAECgYIBwAAAA==.',Wi='Wingulin:BAAALAAECggIDgAAAA==.Winspriest:BAAALAAECgMIBAAAAA==.',Wy='Wyzzl:BAAALAADCgUICAAAAA==.',Xa='Xantra:BAAALAAECgQIBQAAAA==.',Xh='Xhalthurac:BAAALAADCgEIAQAAAA==.',Xi='Xinie:BAAALAAECgEIAQABLAAECgYIDAABAAAAAQ==.Xiresa:BAAALAAECgMIAwAAAA==.Xirisa:BAAALAAECgcIDQAAAA==.',Xo='Xolinur:BAAALAAECgQICAAAAA==.',Xy='Xynthia:BAAALAAECgcIDgAAAA==.',['Xê']='Xêlias:BAAALAAECgYICwAAAA==.',Yd='Yduj:BAAALAAECgcIEQAAAA==.',Yu='Yun:BAAALAAECgYIDAAAAA==.Yunaria:BAAALAADCgMIAwAAAA==.Yuukira:BAAALAAECgYIEQAAAA==.',Za='Zadru:BAAALAADCggICAABLAAECgcIEAABAAAAAA==.Zamazenta:BAAALAAECgcIBgAAAA==.',Zo='Zorro:BAAALAAECgcIDgAAAA==.',Zy='Zykow:BAAALAAFFAEIAQAAAA==.',Zz='Zzarclolz:BAAALAAECgcIEQAAAA==.',['Zä']='Zähmbar:BAAALAADCggICAAAAA==.',['Zü']='Züriana:BAAALAAFFAMIBAAAAA==.',['Ên']='Êncor:BAAALAAECgUICgABLAAECgYICQABAAAAAA==.',['Ín']='Ínever:BAAALAADCgcICAAAAA==.',['În']='Înurias:BAAALAAECgcIEQAAAA==.',['Ÿu']='Ÿuna:BAAALAAECgcICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end