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
 local lookup = {'Paladin-Retribution','Monk-Windwalker','Warlock-Destruction','Unknown-Unknown','Rogue-Assassination','Rogue-Subtlety','Paladin-Protection','Warrior-Protection','Mage-Arcane','Druid-Guardian','DeathKnight-Unholy','Monk-Brewmaster','Mage-Fire','Mage-Frost','DeathKnight-Blood','Priest-Shadow','Hunter-BeastMastery','Warrior-Fury','Warlock-Demonology','Shaman-Elemental','DeathKnight-Frost','Paladin-Holy',}; local provider = {region='EU',realm="Shen'dralar",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abäddon:BAAALAADCgEIAQAAAA==.',Ac='Ackerman:BAAALAAECgMIBAAAAA==.',Ae='Aebonne:BAAALAADCggIEQAAAA==.',Ah='Ahrimân:BAAALAADCggIDgAAAA==.',Ak='Akemi:BAAALAAECgEIAQAAAA==.Akulakhan:BAAALAAECgQIBQAAAA==.',Al='Albâ:BAAALAADCgcIBwAAAA==.Alescar:BAAALAAECgYIBgAAAA==.Alexol:BAAALAADCgEIAQABLAAECggIFgABAKkiAA==.Aleíx:BAAALAAECggIEQAAAA==.Alisandra:BAAALAADCgEIAQAAAA==.Allister:BAABLAAECoEbAAICAAcI8xuwBwBtAgACAAcI8xuwBwBtAgAAAA==.Almanegra:BAAALAAECgEIAQAAAA==.Alonzo:BAAALAADCgcIBwAAAA==.',Ar='Araxiel:BAAALAADCgUIBQAAAA==.Arbaal:BAAALAAECgMIBAAAAA==.Are:BAAALAAECgYICgAAAA==.Arona:BAAALAADCgYICwAAAA==.',As='Asa:BAAALAAECgcIBwAAAA==.Ashborn:BAAALAAECgMIAwAAAA==.Ashglace:BAAALAADCggICAAAAA==.Astrat:BAAALAADCgEIAQAAAA==.Aswen:BAAALAAECgYICQAAAA==.',At='Athelwyn:BAAALAAECgIIAgAAAA==.Atrami:BAAALAAECgYIEwAAAA==.',Ax='Axon:BAABLAAECoEXAAIDAAgIPBRzEwBCAgADAAgIPBRzEwBCAgAAAA==.',['Aï']='Aïlohrïa:BAAALAADCgcIDAAAAA==.',Be='Bearcatauren:BAAALAADCgEIAQAAAA==.Bennu:BAAALAAECgEIAQAAAA==.Berlen:BAAALAAECgQIBAABLAAECgQIBgAEAAAAAA==.Bestialis:BAAALAAECgIIAgAAAA==.',Bk='Bk:BAAALAADCgQIBAAAAA==.',Bl='Blackangel:BAAALAAECgYIDgAAAA==.Blake:BAAALAADCgYIEgAAAA==.Bleyex:BAAALAAECggICgAAAA==.',Bo='Bolmak:BAAALAADCgQIBAAAAA==.',Br='Brokan:BAAALAAECgcIDgAAAA==.',['Bä']='Bäel:BAAALAADCgQIBAAAAA==.',Ca='Cal:BAAALAADCggIEgAAAA==.Caya:BAAALAADCggIFgABLAAECgIIAgAEAAAAAA==.Cayetana:BAAALAAECgIIAgAAAA==.',Ce='Ceretrus:BAABLAAECoEWAAIDAAcIUBXDHQDgAQADAAcIUBXDHQDgAQAAAA==.',Ch='Cheyen:BAAALAAECgYIDgAAAA==.Chivø:BAAALAAECgYIDQAAAA==.Chiëko:BAACLAAFFIEFAAMFAAMIyxWEAgAUAQAFAAMIyxWEAgAUAQAGAAEIbgVvBgBCAAAsAAQKgRcAAgUACAgYI4ADABUDAAUACAgYI4ADABUDAAAA.',Ci='Ciberpanceta:BAAALAADCggICAAAAA==.',Cl='Cløud:BAAALAAECgQICAAAAA==.',Cr='Cryp:BAAALAADCgcICgAAAA==.',Da='Dalanae:BAAALAAECgcIDgAAAA==.Dalnim:BAAALAAECgMIBgAAAA==.Darkshadow:BAAALAADCgEIAQAAAA==.Daulgur:BAAALAADCgMIAwAAAA==.',De='Deluna:BAAALAAECgUIBQAAAA==.Dexmage:BAAALAAECgEIAQABLAAECgYIDAAEAAAAAA==.Dexsharch:BAAALAAECgYIDAAAAA==.',Dk='Dka:BAAALAAECgMIAwAAAA==.',Dl='Dlkk:BAAALAAECgYIEgAAAA==.',Do='Dovo:BAAALAAECgYICwAAAA==.',Dr='Drismol:BAAALAADCgMIAwAAAA==.Druta:BAAALAADCgIIAgAAAA==.',Du='Duduhunter:BAAALAAECgYIBwAAAA==.Dune:BAAALAAECgMIAwAAAA==.',Dw='Dwy:BAAALAAECgYIBgAAAA==.',['Dæ']='Dæva:BAAALAADCgcIBwAAAA==.',['Dø']='Døppler:BAAALAAFFAIIAgAAAA==.Døvo:BAACLAAFFIEGAAIHAAMInSGkAAArAQAHAAMInSGkAAArAQAsAAQKgRcAAgcACAgeJBEBAFEDAAcACAgeJBEBAFEDAAAA.',Ed='Edymchark:BAAALAADCgQIBAAAAA==.',El='Elerin:BAAALAADCggICAAAAA==.',Em='Emilvox:BAAALAADCgEIAQAAAA==.',Er='Erethin:BAAALAAECgUIBgAAAA==.Eronil:BAAALAAECgMIAwAAAA==.',Fa='Farone:BAAALAAECgcICgAAAA==.',Fe='Fedod:BAAALAADCgUIBQAAAA==.',Fi='Finjakew:BAAALAAECgcIDQAAAA==.Fizban:BAAALAADCgYIBgAAAA==.',Fl='Fluffy:BAAALAAECgYIBgAAAA==.',Fo='Forestgun:BAAALAAECgMIBAAAAA==.',Fr='Fraco:BAAALAADCgMIBAAAAA==.Frigodedo:BAAALAADCggICAABLAADCggIEAAEAAAAAA==.',Fu='Fulano:BAAALAADCggICgAAAA==.Furbi:BAAALAADCggICQAAAA==.',['Fü']='Fürrafuriosa:BAABLAAECoEUAAIIAAcIXSUKAwD2AgAIAAcIXSUKAwD2AgAAAA==.',Ga='Gargarita:BAAALAAECgIIAgAAAA==.Garo:BAAALAADCggIDQAAAA==.Gatoo:BAAALAAECgYIDQAAAA==.Gayman:BAAALAADCgYIBgAAAA==.',Go='Gordelion:BAAALAAECgIIAgAAAA==.',['Gá']='Gálador:BAAALAAECgYIBwAAAA==.',Ha='Haka:BAAALAAECgYIDAAAAA==.Harishan:BAAALAAECgcIEAAAAA==.Hashiba:BAAALAAECgUIBgAAAA==.',He='Heal:BAAALAAFFAIIAgAAAA==.Hexygranny:BAAALAAECgUIBgABLAAECggIFQAJAOMhAA==.',Hi='Hikäri:BAAALAADCggICAAAAA==.Historia:BAAALAAECgYIBgAAAA==.',Ho='Hodinz:BAAALAAECggICQAAAA==.Holy:BAAALAADCgQIBAAAAA==.',Hu='Huroncilla:BAAALAAECgEIAQAAAA==.Hustdnoe:BAAALAADCgMIAwAAAA==.',Hy='Hyuuga:BAABLAAECoEUAAIKAAcIWxnpAgAaAgAKAAcIWxnpAgAaAgAAAA==.',['Hê']='Hêlel:BAAALAAECgMIAwAAAA==.',Ib='Ibarâki:BAAALAAECgIIAgAAAA==.',Id='Idril:BAAALAADCgcIBwAAAA==.',Il='Illander:BAAALAAECgUICAAAAA==.',In='Inøri:BAAALAADCggICAABLAAFFAMIBgALAGUZAA==.',It='Ithilmar:BAAALAAECgQIBAAAAA==.',Iv='Ivaino:BAAALAAECgcICQAAAA==.',Iz='Izanagi:BAAALAADCgYIBgAAAA==.',Ja='Jalunne:BAAALAADCggIFQAAAA==.James:BAAALAADCgcIBwAAAA==.',Jh='Jhoira:BAABLAAECoEXAAIMAAgIIiZQAACDAwAMAAgIIiZQAACDAwAAAA==.',Ji='Jinwøø:BAAALAAECgEIAQAAAA==.',Ka='Kaelix:BAAALAADCgYIBgAAAA==.Kaesy:BAAALAAECgQIBAAAAA==.Kaeus:BAABLAAECoEYAAMJAAgIBiYMAQBwAwAJAAgIBiYMAQBwAwANAAEIcRQDDgBAAAAAAA==.Kai:BAAALAAECgYIBwABLAAECggIFAAOAG8hAA==.Kaizen:BAABLAAECoEUAAIOAAgIbyH/AQAtAwAOAAgIbyH/AQAtAwAAAA==.Kamu:BAAALAADCgcIBwAAAA==.Karel:BAABLAAECoEVAAIBAAcI5iGuIwACAgABAAcI5iGuIwACAgAAAA==.Karzog:BAAALAAECgEIAQAAAA==.',Ke='Keephe:BAAALAAECgYICwAAAA==.Kekzz:BAAALAAECgMIAwAAAA==.Kekô:BAAALAADCggICAAAAA==.Keros:BAAALAAECggIDwAAAA==.',Kh='Khoda:BAAALAADCgcIDgABLAAECgIIAgAEAAAAAA==.',Ki='Kivradash:BAAALAAECgIIAgAAAA==.',Kr='Krashus:BAAALAADCgQIBAABLAAECgMIAwAEAAAAAA==.Kritus:BAACLAAFFIEIAAIPAAMITB8IAQASAQAPAAMITB8IAQASAQAsAAQKgRgAAg8ACAgOJncAAHYDAA8ACAgOJncAAHYDAAAA.',Kt='Ktrÿn:BAAALAAECgUIBQABLAAECggICgAEAAAAAA==.',Ku='Kudo:BAABLAAECoEXAAIOAAgI+STqAABgAwAOAAgI+STqAABgAwAAAA==.Kudodru:BAAALAAECgYIDAABLAAECggIFwAOAPkkAA==.Kuromi:BAAALAAECgEIAQAAAA==.',Ky='Kymm:BAAALAAECgYIDQAAAA==.Kypa:BAAALAAECgYIDAAAAA==.',['Kä']='Kärîsa:BAAALAAECgMIAwAAAA==.',La='Lamari:BAAALAAECgEIAQAAAA==.Lautsuki:BAAALAAECgMIAwAAAA==.',Le='Leapofail:BAAALAAECgMIAwABLAAECgYIEQAEAAAAAA==.Leechuu:BAAALAADCggICAAAAA==.Leviosa:BAAALAADCggICAAAAA==.',Li='Limon:BAAALAADCgIIAgAAAA==.',Lu='Lucy:BAAALAADCgYIBgAAAA==.Lumobm:BAAALAAECgYICQAAAA==.Lumodu:BAAALAAECgEIAQAAAA==.Lunastrazsa:BAAALAADCgEIAQAAAA==.Luzdivina:BAAALAADCgcIBwAAAA==.',Ly='Lynm:BAAALAAECgUIBQAAAA==.Lyonlock:BAAALAAECggIDAAAAA==.Lysana:BAAALAADCgMIAwAAAA==.',['Lô']='Lôcki:BAAALAAECgYIDgAAAA==.',Ma='Maddax:BAAALAAECgYICgAAAA==.Maddox:BAAALAADCgcIBQAAAA==.Magufita:BAAALAADCgMIAwAAAA==.Malapipa:BAAALAADCgUIBQAAAA==.Maliketh:BAAALAAECgMIBAAAAA==.Manoplas:BAAALAADCggIDgABLAAECgIIAgAEAAAAAA==.Manáfila:BAAALAADCgMIAwAAAA==.Maped:BAABLAAECoEVAAIQAAgIBxwkCgC3AgAQAAgIBxwkCgC3AgAAAA==.Mariah:BAAALAADCgQIBAAAAA==.Marialitas:BAAALAADCgYICQAAAA==.Maribear:BAAALAAECgUICgAAAA==.Mariwar:BAAALAADCgQIBAAAAA==.',Me='Melibeâ:BAAALAAECgYICQAAAA==.Memories:BAABLAAECoEUAAIJAAcIahY2JgD4AQAJAAcIahY2JgD4AQAAAA==.Mendatron:BAAALAAECggICgAAAA==.Meredil:BAAALAAECgIIAwAAAA==.',Mi='Mignobrew:BAAALAAECgQIBAABLAAECgYIBgAEAAAAAA==.Mignomonk:BAAALAAECgYIBgAAAA==.Mignopala:BAAALAADCggICAABLAAECgYIBgAEAAAAAA==.Mimari:BAAALAAECgYIBgAAAA==.Minze:BAAALAAECgYIDQAAAA==.',Mo='Moghedien:BAAALAAECgYIDAAAAA==.Moonfall:BAAALAADCggICAAAAA==.Moonlady:BAAALAAECgcIDQAAAA==.Mordekalé:BAAALAAECgcIEAAAAA==.Morjek:BAAALAAECgYICAAAAA==.',Mu='Mugorne:BAAALAADCggICAAAAA==.',['Mï']='Mïlky:BAAALAAECgQIBAABLAAECgcICQAEAAAAAA==.',Na='Nadrog:BAAALAAECggIBAABLAAECggIFwADADwUAA==.Naerith:BAAALAAFFAIIBAAAAA==.Naxsar:BAAALAAECgYIDgAAAA==.',Ne='Nei:BAAALAAECgIIAgAAAA==.Neklaus:BAAALAAECgUIBQABLAAECgcIBwAEAAAAAA==.Nemuk:BAAALAAECgEIAQAAAA==.Nenya:BAAALAAECgcIEgAAAA==.Nepo:BAAALAAECgcIDwAAAA==.Nesaga:BAAALAAECgcIDQAAAA==.Neveralways:BAAALAAECgEIAQAAAA==.',Ni='Niara:BAAALAAECgYICgAAAA==.Niariel:BAAALAADCgcIBwAAAA==.Niña:BAAALAADCgYIDAAAAA==.',No='Nocuro:BAAALAAECgUIBQAAAA==.Nomepises:BAAALAAECgcIEQAAAA==.',Nu='Nuryys:BAAALAAECgEIAQAAAA==.',Ny='Nytheris:BAAALAADCgcIBwAAAA==.',['Nä']='Nämi:BAAALAADCgIIAgAAAA==.',Oz='Ozar:BAAALAAFFAIIAgAAAA==.',Pa='Palataza:BAAALAADCgYIBgAAAA==.',Pe='Pekebell:BAAALAADCggICQAAAA==.Pema:BAAALAAECgYIBgAAAA==.',Pi='Picaro:BAAALAADCggICAAAAA==.Pium:BAABLAAECoEUAAIRAAcICyEJDACyAgARAAcICyEJDACyAgAAAA==.',Pr='Prepared:BAAALAAECgYIEQAAAA==.',Ps='Pstdh:BAAALAAECgYICgAAAA==.',Ra='Rahzar:BAAALAAECgQIBwAAAA==.Ranzens:BAAALAAECgIIBAAAAA==.Ratmela:BAAALAADCgYIDAABLAAECgYIEQAEAAAAAA==.',Re='Reyexanime:BAAALAAECgMIBQAAAA==.Reznorilla:BAAALAAECgYIEQAAAA==.Reznorillaz:BAAALAADCggICAABLAAECgYIEQAEAAAAAA==.',Ri='Rivnex:BAAALAADCggICAAAAA==.',Rw='Rwby:BAAALAADCggIEAABLAAECggIFwAMACImAA==.',Ry='Rykush:BAAALAADCgcICwABLAAECgIIAgAEAAAAAA==.Rymvil:BAAALAADCgcIBgAAAA==.Ryuhen:BAAALAADCgcICwAAAA==.',Sa='Sanator:BAAALAADCggIDgABLAAECgYICAAEAAAAAA==.Sara:BAAALAAECgIIAwABLAAFFAIIAgAEAAAAAA==.Sathela:BAAALAAECgMIAwAAAA==.',Sc='Scalyflier:BAAALAAECgYICQAAAA==.',Se='Segarroamego:BAAALAADCggIEAAAAA==.Seldru:BAAALAAECgQIBAABLAAECgcIEQAEAAAAAA==.Selron:BAAALAAECgMIAwAAAA==.Selronz:BAAALAAECgcIEQAAAA==.Sethyr:BAAALAAECgYICQAAAA==.',Sh='Shadicar:BAAALAADCgcICAAAAA==.Shadoppler:BAAALAAFFAYIAgAAAA==.Sharwyn:BAAALAAECgIIAgAAAA==.Shel:BAAALAAECgQIBAABLAAFFAEIAQAEAAAAAA==.Shinøa:BAAALAAFFAIIAgABLAAFFAMIBgALAGUZAA==.Shiro:BAAALAAFFAIIAgAAAA==.Shufflylona:BAAALAAECgcIAgAAAA==.',Si='Silent:BAAALAAECgYIDAAAAA==.',Sk='Skaru:BAAALAADCgYIBgAAAA==.',So='Soycerdota:BAAALAAFFAEIAQAAAA==.',St='Starti:BAAALAADCgYIBgAAAA==.Statham:BAABLAAECoEVAAISAAgIDSGCBwD9AgASAAgIDSGCBwD9AgAAAA==.Stompy:BAAALAAECgYIBwAAAA==.Stonelee:BAAALAADCggIEAABLAAFFAMIBAAEAAAAAA==.',Su='Sunfall:BAAALAADCggICAAAAA==.Suo:BAAALAAECgcIEwAAAA==.Supay:BAAALAADCgcIBwAAAA==.Suw:BAAALAADCggIEAABLAAECgUIBAAEAAAAAA==.',Sx='Sxo:BAAALAAECgUIBgABLAAFFAEIAQAEAAAAAA==.',Sy='Syldraris:BAAALAAECgMIBAAAAA==.Syndern:BAAALAAECgMIBAAAAA==.Synphony:BAAALAADCgcICwAAAA==.',['Sí']='Símaco:BAAALAADCgEIAQAAAA==.',['Sï']='Sïsär:BAAALAAECgEIAQAAAA==.',['Sø']='Sølaire:BAAALAAECgcIDgAAAA==.',Ta='Takibi:BAAALAAECgcICQAAAA==.Tambör:BAAALAADCgYIBgABLAAECgcICQAEAAAAAA==.Tariok:BAAALAAECgUICAAAAA==.Taro:BAAALAADCgUIBwAAAA==.Tausondre:BAAALAADCgEIAQAAAA==.',Th='Theroc:BAAALAADCggIEAAAAA==.Thorios:BAAALAAECgQIBwABLAAFFAMIBgAJAFEYAA==.Thoughtseize:BAAALAADCggICAAAAA==.Thraindal:BAAALAADCggICAAAAA==.',Ti='Tienesfuego:BAAALAAECgEIAgAAAA==.Tiridh:BAAALAAECgMIAwAAAA==.Tirimonk:BAAALAAECgIIAgABLAAECgMIAwAEAAAAAA==.Tizzu:BAAALAAECgcIEAAAAA==.',Tp='Tpartoos:BAAALAAECgIIAgAAAA==.',Tr='Trektar:BAAALAAECgMIBQAAAA==.Trukumakdo:BAAALAADCggICAAAAA==.',Ty='Tykoldmage:BAABLAAECoEVAAIJAAgI4yEjGwBIAgAJAAgI4yEjGwBIAgAAAA==.',Ur='Urkog:BAAALAAECggIEgAAAA==.',Va='Vaartan:BAAALAAECgYIDAAAAA==.Vanishslvt:BAAALAAECgIIAgAAAA==.Varela:BAAALAAECgEIAgAAAA==.',Ve='Veciego:BAAALAAECgQIBAAAAA==.Venly:BAAALAAECgMIAwAAAA==.',Vi='Vi:BAAALAADCgQIAQAAAA==.Vildhjarta:BAAALAAECgYICAAAAA==.',Vo='Voycieego:BAAALAADCggIDwABLAAECgQIBAAEAAAAAA==.',Vy='Vyre:BAAALAADCgMIAwAAAA==.Vyssra:BAAALAAECgQIBgAAAA==.',Wa='Wannabe:BAABLAAECoEUAAIBAAcIlhaiOACbAQABAAcIlhaiOACbAQAAAA==.',We='Weathereport:BAAALAADCggIBAAAAA==.Wenn:BAAALAAECgIIBAAAAA==.',Wi='Wikingame:BAAALAAECgIIAgAAAA==.Willytoleda:BAAALAAECgYICwABLAAFFAMIBQAFAMsVAA==.Wingardium:BAAALAADCggICAAAAA==.',Wu='Wuarra:BAAALAADCgcIDQABLAADCggICgAEAAAAAA==.',['Wê']='Wênn:BAAALAAECgYIDgAAAA==.',Xa='Xandrian:BAAALAADCggIDwABLAAECgIIAgAEAAAAAA==.',Xe='Xerek:BAAALAAECgUIBgAAAA==.Xerivy:BAAALAADCgYIBgAAAA==.',Xi='Xirdas:BAAALAAECggIDgAAAA==.Xivölinhú:BAAALAAECgYICgABLAAECgYIDQAEAAAAAA==.',Xj='Xjbv:BAAALAAECgcIBwABLAAFFAMIBQATAAsXAA==.',Xo='Xouba:BAAALAAECgUICAAAAA==.',['Xû']='Xûrû:BAAALAADCgcIBwAAAA==.',Yh='Yhönkiriel:BAAALAADCgcICQABLAAECgIIAgAEAAAAAA==.',Yo='Yona:BAABLAAECoEYAAIUAAYIKR65GAD8AQAUAAYIKR65GAD8AQAAAA==.',Za='Zake:BAAALAAECgMIBQAAAA==.Zakishen:BAAALAAFFAMIBAAAAA==.Zalaek:BAAALAAECgYIBgAAAA==.Zaserk:BAAALAAECgMIBAAAAA==.',Ze='Zekro:BAAALAAECgcICAAAAA==.Zenva:BAAALAAECgYIDQABLAAFFAMIBgAJAFEYAA==.',Zi='Zinete:BAAALAAECgYIBgAAAA==.Zirack:BAACLAAFFIEGAAMLAAMIZRk5AgDBAAALAAIITBs5AgDBAAAVAAIIyBY0CQCuAAAsAAQKgRgAAwsACAjzItoCANwCAAsACAhfItoCANwCABUABwgMHiYVAG8CAAAA.Ziri:BAAALAADCggICAABLAAFFAMIBgALAGUZAA==.',Zo='Zohe:BAAALAADCgcIBwAAAA==.Zork:BAACLAAFFIEGAAIJAAMIURhFBAAQAQAJAAMIURhFBAAQAQAsAAQKgRcAAwkACAj0IqUGABYDAAkACAj0IqUGABYDAA0AAQheHOILAFIAAAAA.',Zr='Zrèox:BAAALAAECgYICwAAAA==.',['Zø']='Zørku:BAAALAAECgIIAgAAAA==.',['Ál']='Álex:BAABLAAECoEWAAMBAAgIqSLUCQDyAgABAAgIqSLUCQDyAgAWAAEIKgHrOQAcAAAAAA==.',['Âl']='Âlêx:BAAALAAECgYIDwAAAA==.',['Éd']='Édryel:BAAALAAECgIIAgAAAA==.',['Îv']='Îvân:BAAALAADCgIIAgAAAA==.',['Ðu']='Ðun:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end