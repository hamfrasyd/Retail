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
 local lookup = {'Unknown-Unknown','Monk-Mistweaver','DeathKnight-Frost','Mage-Arcane','DemonHunter-Vengeance','Mage-Frost','Druid-Balance','Druid-Feral','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Warlock-Demonology','Priest-Shadow','Priest-Holy','Shaman-Restoration','Hunter-BeastMastery','DemonHunter-Havoc','Druid-Restoration','Shaman-Elemental','DeathKnight-Blood','Monk-Windwalker','Evoker-Augmentation','Evoker-Preservation',}; local provider = {region='EU',realm='Ambossar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Al='Alarich:BAAALAAECgEIAQAAAA==.Albundy:BAAALAAECgIIAgAAAA==.Alystaire:BAAALAAECgEIAQAAAA==.',Am='Amydala:BAAALAADCggICAABLAAECggICgABAAAAAA==.',Ar='Aranuk:BAAALAADCgYIBgAAAA==.Ariamus:BAAALAAECgYIDAAAAA==.Ariseá:BAAALAADCgcIBwABLAAECgcICgABAAAAAA==.Arisá:BAAALAAECgcICgAAAA==.Arkarius:BAAALAADCgUIBQAAAA==.Arki:BAAALAAECgYIDAABLAAECgYIDgABAAAAAA==.Aryn:BAAALAAECgYIDwAAAA==.',As='Asiya:BAAALAADCgUIBQAAAA==.Asrima:BAAALAADCgUIBQABLAAECgcICgABAAAAAA==.',At='Athandriel:BAAALAAECgEIAQAAAA==.Attacke:BAAALAAECgMIBAAAAA==.',Au='Auffeglogge:BAAALAADCggICAAAAA==.',Be='Belakora:BAAALAADCggICAAAAA==.Berrenike:BAAALAAECgMIBQAAAA==.',Bi='Bigbluedress:BAAALAAECgMIAwAAAA==.Bishoop:BAAALAADCggIDQAAAA==.',Bl='Blixix:BAAALAAECgcIDwAAAA==.Bloodhunt:BAAALAAECgIIAgABLAAECgQIBAABAAAAAA==.Bloodyroots:BAAALAAECgIIBAAAAA==.Bluecollar:BAAALAADCgcIDgAAAA==.',Bo='Boazn:BAABLAAECoEWAAICAAgIsiMtAQA0AwACAAgIsiMtAQA0AwAAAA==.Bobbý:BAAALAADCgcIBwAAAA==.Bogenbetti:BAAALAAECgcIEwAAAA==.Bolgour:BAAALAADCggICgAAAA==.Bowzer:BAAALAAECgcIEQAAAA==.',Br='Brainstrain:BAAALAADCgYIBgAAAA==.',Bu='Bugrash:BAABLAAECoEUAAIDAAcIvR47GABWAgADAAcIvR47GABWAgAAAA==.Bull:BAAALAADCggIGwABLAAECgIIAgABAAAAAA==.',Ca='Caesarius:BAAALAAECgcICgAAAQ==.Carag:BAAALAADCggIDwABLAAECgQIBAABAAAAAA==.Carrion:BAAALAAECggIAQAAAA==.Cassiopeya:BAAALAAECgMIBAAAAA==.',Ch='Chia:BAAALAAFFAIIAgAAAA==.Chrischop:BAAALAAECgcIDwAAAA==.',Ci='Ciddia:BAAALAAECgEIAQAAAA==.',Cl='Clementine:BAAALAADCgMIAwAAAA==.Clêo:BAAALAADCgcIBwAAAA==.',Co='Comealotinu:BAAALAAECgYIBgABLAAECgcIEAABAAAAAA==.Convallaria:BAAALAAECgYICwAAAA==.Copd:BAAALAADCgcIBwAAAA==.Cowbust:BAABLAAECoEYAAIEAAgI/iRlAgBUAwAEAAgI/iRlAgBUAwAAAA==.Cowded:BAABLAAECoEQAAIDAAcIQiLRDADGAgADAAcIQiLRDADGAgABLAAECggIGAAEAP4kAA==.Cowsneak:BAAALAAECgYIBgABLAAECggIGAAEAP4kAA==.',Cu='Cubidan:BAABLAAECoEUAAIFAAcIfiW9AQD/AgAFAAcIfiW9AQD/AgAAAA==.',Cy='Cylaris:BAAALAAECgYICgAAAA==.Cysî:BAAALAAECgMICAAAAA==.',Da='Dahnyr:BAAALAAECggIBwAAAA==.Dalin:BAAALAAECgYICQAAAA==.Danielboone:BAAALAAECgMIBQAAAA==.Darkbiscuit:BAEALAAECgYIDwAAAA==.',De='Deadlyne:BAAALAADCgYICQAAAA==.Deadoxygen:BAAALAAECgMIAwAAAA==.Deamonheart:BAAALAAECgEIAgAAAA==.Decido:BAAALAAECgcIBwAAAA==.Dekandra:BAAALAADCgcIEQAAAA==.Demontar:BAABLAAECoEVAAIGAAgIvxiPCQBJAgAGAAgIvxiPCQBJAgAAAA==.Denariss:BAAALAADCgMIAwAAAA==.Derhelle:BAAALAAECgEIAQAAAA==.Derschamane:BAAALAAECgYICAAAAA==.',Di='Dirinal:BAAALAADCgcIEQAAAA==.',Dm='Dmage:BAAALAAECgIIAgABLAAFFAUICgAEAHskAA==.',Do='Dotdotgoose:BAAALAADCgYIBgAAAA==.',Dr='Drale:BAAALAAFFAIIAgAAAA==.Dranava:BAAALAADCggIBQAAAA==.Draven:BAACLAAFFIEKAAIEAAUIeyRWAAAUAgAEAAUIeyRWAAAUAgAsAAQKgRQAAgQACAgmIocPALMCAAQACAgmIocPALMCAAAA.Drvn:BAAALAAECgYIEQABLAAFFAUICgAEAHskAA==.',Du='Duesentrieb:BAAALAAECgIIBAAAAA==.Duncanidaho:BAAALAAECgMIBAAAAA==.',Dw='Dwalîn:BAAALAAECggICAAAAA==.',['Dá']='Dárkhuntér:BAAALAAECggICwAAAA==.',['Dò']='Dòc:BAAALAAECgMIAwAAAA==.',Ea='Easer:BAAALAAECgEIAgAAAA==.',El='Elkabone:BAAALAADCgcICQAAAA==.Eludril:BAAALAADCgcIBwAAAA==.Eluenak:BAAALAAECgIIAgAAAA==.',Er='Erle:BAABLAAECoEYAAMHAAgIZSRLAwAxAwAHAAgIZSRLAwAxAwAIAAIIzhfKGACXAAAAAA==.',Et='Etto:BAAALAADCgEIAQAAAA==.',Ex='Exudoss:BAAALAAECgcIEAAAAA==.',Fa='Fabielle:BAAALAAECgMIBQAAAA==.Faddy:BAAALAADCggIAwAAAA==.Fakepriest:BAAALAADCgQIBAAAAA==.Fanila:BAAALAADCgcIEQAAAA==.Faves:BAAALAAECgIIAgAAAA==.Faxies:BAAALAAECgUIBgAAAA==.',Fe='Fesylie:BAAALAAECgYIBgABLAAECgcICgABAAAAAA==.',Fi='Finkelstein:BAAALAADCgcIBwAAAA==.',Fl='Flagdru:BAAALAADCgUIBQAAAA==.Flauschsen:BAAALAAECgcIDgAAAA==.Flocko:BAAALAAECgMIBQAAAA==.',Fo='Foxyhunt:BAAALAAECgEIAQAAAA==.',Fr='Frosttitude:BAAALAAECgYIDAAAAA==.Frozenshadow:BAAALAAECgYICwAAAA==.',Fu='Futoeki:BAAALAADCggIEAAAAA==.',['Fâ']='Fâlk:BAAALAADCggICAAAAA==.',['Fî']='Fîzzîe:BAABLAAECoEWAAIDAAgI1B/PCgDdAgADAAgI1B/PCgDdAgAAAA==.',Ga='Gabaria:BAAALAADCgcIEgAAAA==.Galadhon:BAAALAAECgEIAgAAAA==.Gambler:BAAALAADCgcIBwAAAA==.',Ge='Geràlt:BAAALAAECgEIAQAAAA==.',Gi='Gigachad:BAAALAAECgYIBgAAAA==.Gilbert:BAABLAAECoEVAAQGAAgIZyWRAwDtAgAGAAcIiySRAwDtAgAEAAgI1yRdCwDfAgAJAAEIgB2ZDABKAAAAAA==.',Gl='Gladiator:BAAALAAECgYIDwAAAA==.',Gn='Gnichneda:BAAALAAECgMIAwAAAA==.',Go='Gobihunt:BAAALAAECggIEAAAAA==.Gobiwarr:BAAALAAECgMIAwAAAA==.Goff:BAAALAAECgEIAQAAAA==.Goodi:BAAALAAECgcIEAAAAA==.Goodnìght:BAAALAADCgEIAQAAAA==.',Gr='Grambarias:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.Granaria:BAABLAAECoEWAAQKAAgIABs5BABGAgAKAAcIfxg5BABGAgALAAcImRkgGgD+AQAMAAEItQoxWQA3AAAAAA==.Grimz:BAAALAAECgYICwAAAA==.Grindela:BAABLAAECoEYAAMNAAgI+CMeBAApAwANAAgI+CMeBAApAwAOAAEIgg6ZXQA+AAAAAA==.Grisimdor:BAAALAAECgYIBgAAAA==.Grumthor:BAAALAAECgMIBQAAAA==.',Gu='Guldån:BAAALAAECggICAAAAA==.',Ha='Habidutl:BAAALAADCgUIBgAAAA==.Hammading:BAAALAAECgQIBAAAAA==.Hammerfalle:BAAALAADCgIIAgAAAA==.Harmléss:BAAALAAECgIIAgAAAA==.Havarie:BAAALAAECgYICgAAAA==.',He='Heilaggro:BAAALAADCgcIDQAAAA==.Hellkitty:BAAALAAECgEIAQAAAA==.Hephaisto:BAAALAAECgEIAgAAAA==.Heptâ:BAAALAAECgcIEAAAAA==.Herania:BAAALAADCgEIAQAAAA==.Hexerhenry:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.',Hi='Hiina:BAAALAADCgIIAgAAAA==.',Hu='Hunterguntz:BAAALAAECgMIBAAAAA==.Huntschi:BAAALAAECgUICgABLAADCggIFgABAAAAAA==.',['Hé']='Héxmi:BAAALAADCggIDQAAAA==.',Id='Idrael:BAABLAAECoEWAAIEAAcI6BcTIgAUAgAEAAcI6BcTIgAUAgAAAA==.',In='Infinichi:BAAALAAECggICgAAAA==.',It='Itspriestora:BAAALAADCgYIBgAAAA==.',Iv='Ivaine:BAAALAAFFAEIAQAAAA==.',Ja='Jackguny:BAAALAAECgYIBwAAAA==.Jairo:BAAALAADCggICgAAAA==.Januszz:BAAALAADCggIEAAAAA==.Jaro:BAAALAADCgMIAwAAAA==.',Ji='Jidran:BAAALAAECgcIDwAAAA==.Jigu:BAAALAADCggICAAAAA==.',Ju='Julì:BAAALAADCggICQAAAA==.',['Já']='Járwen:BAAALAAECgMIAwAAAA==.',['Jê']='Jêtîxd:BAABLAAECoEcAAIPAAgIGBk+HwDWAQAPAAgIGBk+HwDWAQAAAA==.',['Jó']='Jóons:BAAALAADCgEIAQAAAA==.',Ka='Kaitosan:BAAALAADCgQIBAABLAAECgYIDAABAAAAAA==.Katon:BAAALAAECggICQABLAAFFAMIBQANAEIiAA==.',Ke='Kevinsan:BAAALAADCgYIBwAAAA==.',Ki='Killermix:BAAALAADCgcICAAAAA==.Killroar:BAAALAADCgcIEQAAAA==.',Kr='Kristalli:BAAALAADCggIDQAAAA==.Kristallina:BAAALAADCgcIDQAAAA==.',Kv='Kvóthe:BAAALAADCggICQAAAA==.',Ky='Kylmää:BAAALAAECgUICQAAAA==.',La='Laloona:BAAALAAECgIIAwAAAA==.Lardonian:BAAALAADCggIFwAAAA==.Larkra:BAAALAAECgIIAgAAAA==.Lary:BAAALAAECgQIBAAAAA==.Lausepelz:BAAALAAECgQICAAAAA==.',Le='Leddi:BAAALAADCggICAAAAA==.Legionz:BAAALAADCgUIBQABLAAECgYIDgABAAAAAA==.Lenie:BAAALAADCgYIBgAAAA==.Leoniê:BAAALAAECgYIDwAAAA==.',Li='Lich:BAAALAADCgMIAwAAAA==.Lickmybowbow:BAAALAAECgEIAQAAAA==.Likeless:BAAALAAECgIIAwAAAA==.Liuna:BAAALAAECgEIAQAAAA==.',Lo='Loun:BAAALAAECgUICgAAAA==.',Lu='Lugh:BAAALAADCgYIBgAAAA==.Lukês:BAAALAAECgIIAgAAAA==.Lutáno:BAAALAAECgYICwAAAA==.Luzífer:BAAALAAECggIBgAAAA==.',Ly='Lynxarosia:BAAALAAECgIIAgAAAA==.Lyriska:BAAALAADCgYIDwAAAA==.',['Lè']='Lèddi:BAAALAAECgMIBQAAAA==.',['Lø']='Løstlock:BAAALAAECgYICQAAAA==.',['Lú']='Lúxe:BAAALAAECgYICwAAAA==.',Ma='Machtlos:BAAALAAECggIDgAAAA==.Machtlôs:BAAALAAECggIBQAAAA==.Maggus:BAAALAADCgcIDgAAAA==.Magierhenry:BAAALAADCggIDwABLAAECgYIDAABAAAAAA==.Magnison:BAAALAAECgMIBQAAAA==.Malnor:BAAALAADCggICgAAAA==.Malthus:BAAALAAECgUIAgAAAA==.Manoloo:BAAALAAECgMIBAAAAA==.Marodan:BAAALAAECgYIDwAAAA==.Marone:BAABLAAECoEVAAIQAAcIXiNMCQDZAgAQAAcIXiNMCQDZAgAAAA==.Marsh:BAAALAADCgEIAQAAAA==.Matarama:BAAALAADCgYIDAAAAA==.Matero:BAAALAAECggIEgAAAA==.Maxdhmage:BAAALAAFFAIIAgAAAQ==.Mazus:BAAALAADCgYICgAAAA==.',Me='Meng:BAAALAAECgUICwAAAA==.Metuin:BAAALAAECgMIBgABLAAECggIHAAPABgZAA==.Mexxy:BAAALAAECgMIBAAAAA==.',Mi='Miniwuscht:BAAALAADCgYIBgAAAA==.',Mo='Moguay:BAAALAAECgEIAQAAAA==.Moint:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.Moktaran:BAAALAADCggICAAAAA==.Moniànà:BAAALAAECgIIAgAAAA==.Moonz:BAABLAAECoEYAAIRAAgIuSIZCAAOAwARAAgIuSIZCAAOAwAAAA==.Moranír:BAAALAAECgYICwAAAA==.Morla:BAAALAADCgUIBQAAAA==.Moírá:BAAALAADCgYIBgAAAA==.',Mu='Mubarak:BAAALAAECgYICQAAAA==.Mundgeruch:BAAALAAECgYIBgABLAAFFAIIAgABAAAAAA==.',['Mì']='Mìchi:BAAALAAECgcIDAAAAA==.Mìkasa:BAAALAADCgIIAgAAAA==.',Na='Nabilu:BAAALAAECgcIEwAAAA==.',Ne='Nesua:BAAALAADCgcIDAAAAA==.Neve:BAAALAAECgEIAQAAAA==.Nevillé:BAAALAADCggICAAAAA==.Nexodia:BAAALAADCgcICQAAAA==.',Ni='Niass:BAAALAAECggIBQAAAA==.Nikkix:BAAALAAECggICAAAAA==.Nirviena:BAAALAADCgYIDwAAAA==.',No='Nofxy:BAAALAAECgcIEAAAAA==.',Nu='Nudelbeißer:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.',Ny='Nyxiaza:BAAALAAECgYICAABLAAECggIBgABAAAAAA==.',['Nô']='Nôdónn:BAAALAADCggICAAAAA==.Nôx:BAAALAAECgcIEwAAAA==.',Ob='Obmar:BAAALAADCgcIBwAAAA==.',Oh='Ohrschloch:BAAALAAECgUICAAAAA==.',Ok='Oktaris:BAAALAAECgYIDgAAAA==.',Ol='Oldshadow:BAAALAADCgYIBgAAAA==.',Or='Orcan:BAAALAADCggICAAAAA==.',Ox='Oxia:BAAALAAECgEIAgAAAA==.',Oz='Ozzburn:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Pa='Palahenry:BAAALAAECgYIDAAAAA==.Palakadabra:BAAALAAECgYICQAAAA==.Pardus:BAAALAAECgIIAgAAAA==.Paulporter:BAAALAADCgYIDwAAAA==.Paunchy:BAAALAADCggIDAAAAA==.',Pe='Peena:BAAALAAECgIIBAAAAA==.Peria:BAAALAAECgYIDwAAAA==.Pexl:BAAALAADCgUICAABLAADCgcIDgABAAAAAA==.',Ph='Phénomenom:BAAALAAECgYIEQAAAA==.',Pi='Pinu:BAAALAAECgEIAgAAAA==.',Po='Poorhomie:BAAALAAFFAIIAgAAAA==.',Pr='Praystation:BAAALAADCgYIBgAAAA==.Preesthenry:BAAALAADCggIFwABLAAECgYIDAABAAAAAA==.',Qu='Quéendemón:BAAALAADCgcICQAAAA==.',Ra='Raassiieerrt:BAAALAAECgcICQAAAA==.Raedan:BAAALAAECgYICAABLAAECggIEgABAAAAAA==.Raiden:BAAALAAECgcIEAAAAA==.Rassiieerrt:BAAALAAECggICAAAAA==.Rassiieerrtt:BAAALAAECggIEgAAAA==.Rasziel:BAAALAAECgYIDwAAAA==.Raxor:BAAALAADCgcIBwAAAA==.',Re='Redfírefox:BAAALAAECgIIAgAAAA==.Remmi:BAAALAAECgIIAgAAAA==.Revoker:BAAALAAECgMIAwABLAAECggIGAANAPgjAA==.Rexl:BAAALAADCgcIDgAAAA==.',Ri='Rilthaien:BAAALAADCgEIAQAAAA==.',Ro='Romeo:BAAALAAECgIIAgAAAA==.Royalhaze:BAAALAAECgYIDgAAAA==.',Ry='Ryl:BAAALAADCgcIDgAAAA==.',['Rè']='Rèva:BAAALAAECgIIAgAAAA==.',['Rê']='Rêinsch:BAAALAADCggIDQAAAA==.',Sa='Salázar:BAAALAADCgIIAgAAAA==.',Sc='Schamanie:BAAALAADCgQIBAAAAA==.Schandel:BAAALAAECggICAAAAA==.Schlumpfee:BAAALAADCggIFgAAAA==.Schámin:BAAALAADCgcIBwAAAA==.',Se='Senndy:BAAALAAECgMIAwAAAA==.',Sh='Shamehenry:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Showfear:BAAALAADCgcIDQAAAA==.Showgamer:BAAALAAECgYIBwAAAA==.Shây:BAAALAAECgcIDQAAAA==.Shócker:BAAALAAECgYICwAAAA==.',Si='Sigung:BAAALAAECgYICwAAAA==.Silvera:BAAALAAECgMIBgAAAA==.Sinoa:BAAALAADCggICAAAAA==.Sinthrael:BAAALAADCggICQAAAA==.',Sk='Skeletór:BAAALAAECgYIBwAAAA==.Skádí:BAAALAADCgEIAQAAAA==.',Sl='Sloth:BAAALAAECgMIAwAAAA==.Slumlius:BAAALAAECgUICAAAAA==.Slôw:BAAALAADCggIFwAAAA==.',So='Soranaja:BAAALAAECgYIDwAAAA==.Sorbaratina:BAAALAADCggIDwABLAAECgIIAgABAAAAAA==.',Sp='Spikê:BAAALAADCgMIAwAAAA==.Spitzi:BAAALAADCggIEAAAAA==.',Sr='Srames:BAAALAAECgcIDQABLAAECggIGAAFACcmAA==.',St='Stafford:BAAALAADCgcICgABLAAECgEIAQABAAAAAA==.Strawman:BAAALAAECgQIBAAAAA==.Stêfbert:BAAALAAECgYICwAAAA==.Stêfbêrt:BAAALAAECggIAgAAAA==.',Su='Surrenity:BAAALAAECgYICwAAAA==.',Sy='Syana:BAAALAADCgIIAgAAAA==.Syleene:BAAALAAECgcIEAABLAAECggIGAASAKMlAA==.Syreeza:BAABLAAECoEYAAISAAgIoyUuAQA0AwASAAgIoyUuAQA0AwAAAA==.Syrun:BAAALAAECgYIBgABLAAECggIGAASAKMlAA==.',['Sâ']='Sâia:BAAALAADCggIDQAAAA==.',['Sé']='Séance:BAACLAAFFIEJAAITAAUIoBzMAADXAQATAAUIoBzMAADXAQAsAAQKgRgAAhMACAiCJj8AAJYDABMACAiCJj8AAJYDAAAA.',['Sý']='Sýlvâna:BAAALAADCggIDgAAAA==.',Ta='Tabaluca:BAAALAADCgUIBgAAAA==.Tamtamta:BAAALAAECgYIBgAAAA==.Tasuim:BAAALAADCgYIBgAAAA==.Taton:BAAALAAECgYIBwAAAA==.',Te='Teldiatide:BAAALAAECgYICwAAAA==.Terinak:BAAALAAECgYIDQAAAA==.',Th='Theelement:BAAALAAECgYIBgAAAA==.',Ti='Tisôrân:BAAALAAECgIIAwAAAA==.',To='Todie:BAAALAAECgIIAwAAAA==.Toffees:BAAALAADCggIGAAAAA==.Tohranus:BAAALAADCggIEAAAAA==.Tokrahexe:BAAALAAECgIIAgAAAA==.',Tr='Trag:BAAALAADCgYICAABLAAECgEIAQABAAAAAA==.Trivion:BAAALAAECgYIBgAAAA==.Troros:BAAALAADCggIDwAAAA==.Trulli:BAAALAAECgEIAgAAAA==.Tràxéx:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Träumchen:BAAALAAECggICAAAAA==.Trôublemâker:BAAALAAECgYIDAABLAAECgIIAwABAAAAAA==.',Ts='Tscholle:BAABLAAECoEYAAIUAAgICiLpAQAcAwAUAAgICiLpAQAcAwAAAA==.',Tu='Tubbii:BAAALAADCggIGwAAAA==.Tubfrost:BAAALAAECgIIAQAAAA==.',['Tâ']='Târya:BAAALAADCgMIBAAAAA==.',['Tó']='Tórras:BAAALAAECgYIDwAAAA==.',Vi='Victori:BAAALAADCgcIDAAAAA==.',Vo='Vollid:BAAALAAECgYICQABLAAECggIGAANAPgjAA==.Vollverwesen:BAAALAAFFAIIAgAAAA==.',['Vé']='Véntu:BAAALAAECggIBwAAAA==.',Wa='Walturion:BAAALAAECgcIDQAAAA==.Wandaja:BAAALAAECgQIBAAAAA==.',Wh='Whitebelt:BAABLAAECoEYAAIVAAgI7CG3AgAVAwAVAAgI7CG3AgAVAwAAAA==.',Wi='Wildbumser:BAAALAAECgQIBAAAAA==.Wilnari:BAAALAAECgUIBAAAAA==.',Xa='Xauld:BAAALAADCgUIBQAAAA==.',Xo='Xornan:BAAALAADCgYICwAAAA==.',Xy='Xyrene:BAABLAAECoEYAAIFAAgIJyZCAACDAwAFAAgIJyZCAACDAwAAAA==.',Yi='Yiikez:BAAALAAECgcIEwAAAA==.Yikezdh:BAAALAAECgYIBwABLAAECgcIEwABAAAAAA==.',Ym='Ymir:BAAALAADCgYIBgAAAA==.',Yo='Yore:BAAALAAECgcIDwAAAA==.Yorkzy:BAABLAAECoEUAAMWAAcI+yTBAADoAgAWAAcI+yTBAADoAgAXAAYIRhNyDQBYAQAAAA==.',Yu='Yunney:BAAALAAECgYICAAAAA==.',Za='Zaerox:BAAALAAECgUIBgAAAA==.Zauberponny:BAAALAAECgYICQAAAA==.Zawala:BAAALAADCgcIEQAAAA==.',Ze='Zeraphine:BAABLAAECoEYAAMTAAgIcyJ/BAArAwATAAgIcyJ/BAArAwAPAAQI3wx4XgC1AAAAAA==.Zeuu:BAAALAADCgUIBQAAAA==.',Zu='Zuano:BAAALAADCggIDwAAAA==.',['Øs']='Øskar:BAAALAAECggICAABLAAECggICgABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end