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
 local lookup = {'Rogue-Assassination','Mage-Frost','Mage-Arcane','Priest-Holy','Unknown-Unknown','Priest-Shadow','Druid-Restoration','Hunter-Marksmanship','Druid-Balance','Evoker-Devastation','DeathKnight-Frost','Monk-Mistweaver','Druid-Feral','Monk-Windwalker','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','DemonHunter-Havoc',}; local provider = {region='EU',realm='Zenedar',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ad='Adinferno:BAAALAADCgUICAAAAA==.',Ae='Ae:BAAALAADCgcIBwAAAA==.',Ag='Aggereth:BAAALAAECgMIBAAAAA==.',Ai='Aiwendul:BAAALAAECgYIDwAAAA==.',Ak='Akuma:BAAALAAECgMIBAAAAA==.',Al='Alfôr:BAABLAAECoEWAAIBAAgImyEJAgA4AwABAAgImyEJAgA4AwAAAA==.Allyguurda:BAAALAADCgQIBAAAAA==.Alzuldahomar:BAAALAAECgYICwAAAA==.Aléyna:BAABLAAECoEWAAMCAAgIkSAVBwBwAgACAAgI7xsVBwBwAgADAAYIFxTzOgB9AQAAAA==.',Am='Amstelor:BAABLAAECoEVAAIEAAgI8w8+HADOAQAEAAgI8w8+HADOAQAAAA==.',An='Antoria:BAAALAAECgYIDgAAAA==.',Ap='Apapapa:BAAALAADCggICAAAAA==.Appolonia:BAAALAAECgEIAQAAAA==.',Ar='Arazux:BAAALAADCgYIBgAAAA==.Arûhim:BAAALAAECgMICQAAAA==.',As='Astrian:BAAALAAECgYICQAAAA==.',At='Atrius:BAAALAADCggICgAAAA==.',Av='Avell:BAAALAADCgcICgAAAA==.',Az='Azadall:BAAALAAECgQIBQAAAA==.Azarel:BAAALAAECgQIBAABLAAECgQIBQAFAAAAAA==.',Ba='Backstab:BAAALAADCgYIBgAAAA==.Bae:BAAALAADCgMIAwAAAA==.Baffe:BAAALAAECgIIAgAAAA==.Barely:BAAALAAECgYICgAAAA==.',Be='Belorie:BAAALAAECggIEAAAAA==.',Bi='Bigmuff:BAAALAAECggIDAAAAA==.Bilbobaggins:BAAALAAECgUIBgAAAA==.',Bl='Blasphemia:BAABLAAECoEWAAIGAAgIiSJYBQAMAwAGAAgIiSJYBQAMAwAAAA==.Blindsteve:BAAALAADCgQIBQAAAA==.Blueballs:BAAALAADCgcIBwAAAA==.',Bo='Bonzai:BAAALAAECggIAgAAAA==.Bonè:BAAALAAECgUICQAAAA==.Bossen:BAABLAAECoEWAAIHAAgIqCMRAgAIAwAHAAgIqCMRAgAIAwAAAA==.',Bt='Btiy:BAAALAAECgYICwAAAA==.',Bu='Bubblefett:BAAALAAECgYICQAAAA==.Butterfly:BAAALAAECgQIBQAAAA==.Buuldan:BAAALAADCgMIAwAAAA==.',['Bé']='Bénder:BAAALAADCggICAABLAAFFAEIAQAFAAAAAA==.',['Bö']='Börre:BAAALAADCggICAAAAA==.',Ca='Carelei:BAAALAAFFAEIAQAAAA==.Carmone:BAAALAAECgUIBwAAAA==.',Ch='Chadstalker:BAAALAAECggIEwAAAA==.Chitan:BAAALAADCggICAAAAA==.Christer:BAAALAAECgYIDwAAAA==.',Ci='Cindraya:BAAALAAECgIIAgAAAA==.',Co='Cold:BAAALAADCgYIBgAAAA==.',Cr='Cryto:BAAALAAECgYICgAAAA==.',Cu='Curvaguutee:BAAALAAECgYIDAAAAA==.',Da='Dagrath:BAAALAADCggICAAAAA==.Darai:BAAALAAECgYIDwAAAA==.Darnia:BAAALAADCggIEAAAAA==.',De='Deathbacon:BAAALAADCggICAAAAA==.Deathboyslim:BAAALAAECgYICQAAAA==.Deathfad:BAAALAAECgUIBQAAAA==.',Di='Dico:BAAALAAECggICgAAAA==.',Dr='Dragon:BAAALAADCgcIBgAAAA==.Drakarys:BAAALAAECgQIBQAAAA==.Drphil:BAAALAAECggIBAAAAA==.',['Dê']='Dêaqon:BAAALAAECggICQAAAA==.',Ec='Ecthelion:BAAALAADCgcIBwAAAA==.',Ei='Eirithur:BAAALAAECgYICAAAAA==.',Ek='Ekshi:BAAALAADCgcIBwABLAAECggIEwAFAAAAAA==.',El='Elaniel:BAAALAAECgYIDAAAAA==.',Em='Emmzi:BAAALAAECggIBgAAAA==.Empress:BAAALAAECggICAAAAA==.',En='Endre:BAAALAADCgYICwAAAA==.',Ep='Epicdruid:BAAALAAECgYIBgAAAA==.Epicevoker:BAAALAADCgEIAQAAAA==.Epichunt:BAAALAADCgEIAQAAAA==.Epicpally:BAAALAADCgIIAgAAAA==.',Ex='Exdeusdruid:BAAALAAECgYICgAAAA==.Exodius:BAAALAAECggICAAAAA==.',Fa='Fahmy:BAAALAAECgYICwAAAA==.',Fe='Felpunch:BAAALAADCgUIBQAAAA==.',Fl='Flaze:BAAALAADCggICAAAAA==.Flecha:BAAALAADCgEIAQAAAA==.Flipaides:BAAALAADCgYIDwAAAA==.',Fo='Foal:BAAALAAECgYIDAAAAA==.',Fr='Frófró:BAABLAAECoEWAAIIAAgIiRX1EgD0AQAIAAgIiRX1EgD0AQAAAA==.',Fu='Fukntonk:BAAALAAECgMIBAAAAA==.',Ga='Gablegable:BAAALAADCggICAAAAA==.',Ge='Geglash:BAAALAAECgUICQAAAA==.',Gi='Gilmas:BAAALAADCgIIAgAAAA==.Giraia:BAAALAADCggICAAAAA==.',Gs='Gster:BAAALAAECgEIAQAAAA==.',Gu='Guldrek:BAAALAADCgIIAwABLAAECgMIBAAFAAAAAA==.',Ha='Hakhan:BAAALAADCgQIBAAAAA==.Happysteven:BAAALAADCgEIAQABLAADCgQIBQAFAAAAAA==.Harleen:BAAALAADCgYIBgABLAAECgYICwAFAAAAAA==.',He='Heltseriös:BAABLAAECoEVAAMJAAgIzCCEBQD5AgAJAAgIzCCEBQD5AgAHAAQIOAyzPAC/AAAAAA==.',Hi='Hirolde:BAAALAADCgcIBwAAAA==.',Ho='Holyhäst:BAAALAADCgcIBwABLAAECggIFgAHAMUVAA==.Hoskii:BAAALAAECgcIDAAAAA==.',Hu='Huntdogeski:BAAALAADCggICAAAAA==.',['Hä']='Hästkraften:BAABLAAECoEWAAMHAAgIxRW4DwAVAgAHAAgIxRW4DwAVAgAJAAEIIwdWUAAqAAAAAA==.',Ja='Jab:BAAALAADCgcIBwAAAA==.Jagärböb:BAABLAAECoETAAIKAAgIjRvaCQCEAgAKAAgIjRvaCQCEAgAAAA==.Jamx:BAAALAAECgYIBwAAAA==.',Je='Jedbartlet:BAAALAAECgYICQAAAA==.Jeskud:BAAALAAECgYICAAAAA==.',['Jä']='Jäätynyt:BAAALAAECgYIDAAAAA==.',Ka='Kameelpewpew:BAAALAADCgYIBgAAAA==.Kamelpewdk:BAAALAAECggICgAAAA==.Kataramenosr:BAAALAADCgYIBgAAAA==.',Ke='Kehveli:BAAALAADCggICwAAAA==.',Kh='Khyber:BAAALAADCgYIBgAAAA==.',Ko='Kokhammer:BAAALAAECgIIAgAAAA==.',Kr='Krakatoa:BAAALAAECgYICQAAAA==.',Kt='Ktdru:BAAALAADCgIIAgAAAA==.',Ku='Kultapoika:BAAALAAECgQIBAAAAA==.Kumana:BAAALAADCgMIAwAAAA==.',La='Lathz:BAAALAAECgIIAwAAAA==.',Le='Lemmy:BAAALAADCggIBgAAAA==.Leprotect:BAAALAAECgQIBAAAAA==.',Li='Lisko:BAAALAAECgQIBgAAAA==.',Lu='Luxmodar:BAAALAADCggICAABLAAECgYICgAFAAAAAA==.',Ma='Machodk:BAABLAAECoEWAAILAAgIRCXMAgBPAwALAAgIRCXMAgBPAwAAAA==.Machô:BAAALAADCggICAABLAAFFAEIAQAFAAAAAA==.Maddas:BAAALAAECgYIDwAAAA==.Mammazmunk:BAABLAAECoEWAAIMAAgISB4XBAC1AgAMAAgISB4XBAC1AgAAAA==.Mayz:BAAALAAECggICgAAAA==.',Me='Meatball:BAAALAADCggICAAAAA==.Mechahun:BAAALAADCgcIBwAAAA==.Mejch:BAAALAADCgIIBAABLAAECgMIBAAFAAAAAA==.Menethar:BAAALAADCggICAAAAA==.Mesmori:BAABLAAECoEVAAINAAgIoCOvAABHAwANAAgIoCOvAABHAwAAAA==.',Mi='Miksuu:BAAALAAECgYIDAAAAA==.Mirata:BAAALAADCgUIBQABLAADCgcIDQAFAAAAAA==.',Mo='Moikani:BAAALAAECgcIEAAAAA==.Monkbacon:BAAALAADCgcIDQAAAA==.Monkeponke:BAABLAAECoEYAAIOAAgI0B+3AwDsAgAOAAgI0B+3AwDsAgAAAA==.Morningstar:BAAALAAECgUICwAAAA==.',['Mö']='Möhnä:BAAALAADCgcIBwAAAA==.',['Mü']='Mürf:BAABLAAECoEWAAIPAAgINSBlCQDYAgAPAAgINSBlCQDYAgAAAA==.',Na='Nables:BAAALAADCggICAAAAA==.Nacchi:BAAALAAECgYICQAAAA==.Nagraz:BAAALAAECgYIDAAAAA==.Navia:BAAALAADCggICAAAAA==.',Ne='Nezuko:BAAALAAECgYIBwAAAA==.',No='Nobodyy:BAAALAADCggIGAAAAA==.Noltreza:BAAALAADCgYICQAAAA==.',Nu='Nubcake:BAAALAAECgYIDwAAAA==.',['Nò']='Nòa:BAAALAADCggIEAAAAA==.',Oq='Oqzu:BAAALAAECgYICwAAAA==.',Ov='Overtop:BAAALAADCgcIBwAAAA==.',Ox='Oxen:BAAALAADCgcICwAAAA==.',Pa='Pannahinen:BAAALAADCggICAAAAA==.Pask:BAAALAADCggIDAAAAA==.Patriarken:BAABLAAECoEWAAMQAAgIwhp7AwCsAgAQAAgIwhp7AwCsAgARAAEIRxBBYwA6AAAAAA==.Patron:BAAALAADCgcIDAAAAA==.',Po='Polli:BAAALAADCggICwAAAA==.',Qr='Qrmas:BAAALAAECgYIDAAAAA==.',Ra='Radiostyle:BAAALAADCgUIBQAAAA==.',Re='Revenge:BAAALAAECgYIDAAAAA==.Rezon:BAAALAADCgYIBgAAAA==.',Ro='Rossdormu:BAAALAAECgYICQAAAA==.',Ru='Ruggugglat:BAAALAADCgYIBgAAAA==.',Sa='Sairen:BAAALAAECgYIDwAAAA==.Salai:BAAALAADCgIIAgAAAA==.Salaioo:BAAALAADCgUIBQAAAA==.Saltmuch:BAAALAAECgYICQAAAA==.',Se='Serpian:BAAALAAECgYICgAAAA==.Sethaap:BAAALAADCgMIAwAAAA==.Setth:BAAALAADCggICQAAAA==.',Sh='Shadowsemp:BAAALAADCgUIBQAAAA==.',Sk='Skadi:BAAALAADCggICAAAAA==.Skrallan:BAABLAAECoEWAAMSAAgIVhtUBQBMAgASAAgILxtUBQBMAgATAAUIgxCwSAA6AQAAAA==.Skybreaker:BAAALAADCgUIBQAAAA==.',Sl='Slushie:BAAALAADCgQIBgAAAA==.',Sn='Snosk:BAAALAADCggICAAAAA==.',So='Sokaris:BAAALAAECgIIBAAAAA==.',Sp='Spellsender:BAAALAAECgEIAQAAAA==.',Ss='Ssjgoku:BAAALAADCgcIAwAAAA==.',St='Striker:BAAALAAECgUIBQAAAA==.Stuffy:BAAALAAECgMIAwAAAA==.Stycket:BAAALAADCgcIBwAAAA==.',Su='Surkimus:BAAALAAECgcIDwAAAA==.',['Sà']='Sàlái:BAAALAAECgEIAQAAAA==.',Ta='Tappiukko:BAAALAAECgYICgAAAA==.',Te='Teach:BAAALAAECggIAwAAAA==.Teekkari:BAAALAAECgMIBQAAAA==.Temetias:BAAALAAECgYIDAAAAA==.',Th='Thelaren:BAAALAAECgcIDAAAAA==.Thunderhand:BAAALAAECgMIBAAAAA==.',Ti='Tinymage:BAAALAAECgcIEgAAAA==.',To='Tohtorivarjo:BAAALAAECgcIEAAAAA==.Tokaku:BAAALAAECggIBwAAAA==.Toothles:BAAALAADCgIIAgAAAA==.',Tr='Treehoney:BAAALAADCgcIEAAAAA==.Trillöx:BAAALAAECgEIAQAAAA==.Tréébear:BAAALAADCgYIBwAAAA==.',Ts='Tsarina:BAAALAADCgYIBgAAAA==.',Tw='Twentyone:BAAALAAECgUIBQAAAA==.',Ty='Tyrion:BAAALAAECggIDgAAAA==.',Ut='Uthgor:BAAALAAECgYIBwAAAA==.',Va='Vados:BAAALAADCgUIBQABLAAECgYICwAFAAAAAA==.Valow:BAAALAADCggIDwAAAA==.Varon:BAAALAADCgMIAwAAAA==.Vator:BAAALAAECgYIBgABLAAECgcIEgAFAAAAAA==.',Ve='Veertje:BAAALAAECgIIBAAAAA==.',Vi='Vilhelmina:BAAALAAECgMIBAAAAA==.Vindemiatrix:BAAALAAECgUIBQAAAA==.',Vo='Voidgigz:BAAALAAECgYIDwAAAA==.Vonherra:BAAALAAECgcIEAAAAA==.Vorgla:BAAALAAECgYIBwAAAA==.',Vu='Vulhun:BAAALAADCgMIAwAAAA==.',Wa='Wartezia:BAAALAAECgMIBAAAAA==.',Wh='Whiteluna:BAAALAAECgcICgAAAA==.',Wo='Workkworkk:BAAALAAECgYIBgAAAA==.',Xe='Xeoz:BAAALAAECgcIDAAAAA==.',Xi='Xingfu:BAAALAADCggIBwAAAA==.',Xu='Xurknight:BAAALAAECgYIDAAAAA==.Xurukin:BAACLAAFFIEFAAIKAAMIMxaPAgAIAQAKAAMIMxaPAgAIAQAsAAQKgRkAAgoACAhdJMMBAEoDAAoACAhdJMMBAEoDAAAA.',['Xé']='Xéphanite:BAAALAAECgYIDAAAAA==.',Za='Zappie:BAAALAADCggIEAAAAA==.Zayla:BAAALAADCggIDgAAAA==.',Ze='Zeision:BAAALAAECgYICQAAAA==.Zeptow:BAAALAAECgYIBgAAAA==.Zezhva:BAAALAADCggIEQAAAA==.',Zi='Zium:BAAALAAECgMIBAAAAA==.',Zv='Zvezda:BAAALAAECgYICAAAAA==.',Zy='Zyntharen:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end