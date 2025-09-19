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
 local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Hunter-Marksmanship','DeathKnight-Blood','Warrior-Arms','Priest-Shadow','Shaman-Elemental','Monk-Brewmaster','Druid-Restoration','Druid-Balance','Monk-Mistweaver','Shaman-Restoration','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','DeathKnight-Frost','Paladin-Protection','Priest-Discipline','Priest-Holy','Paladin-Retribution','Mage-Frost','Warlock-Destruction','DemonHunter-Havoc','Paladin-Holy',}; local provider = {region='EU',realm='Lightbringer',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adventine:BAAALAAECgEIAQAAAA==.Adventro:BAAALAAECgEIAQAAAA==.',Ae='Aedan:BAAALAAECgIIAgAAAA==.Aeldine:BAAALAAECgYIDAAAAA==.',Ag='Agathys:BAAALAAECgYIDQAAAA==.Agigaue:BAAALAAECgYICgAAAA==.',Ah='Aheleziel:BAAALAAECgMIAwAAAA==.',Ai='Ainnyston:BAAALAAECggIBwAAAA==.',Al='Alestair:BAAALAADCggICAAAAA==.Algirdoska:BAAALAAECgYIDwAAAA==.Alitaki:BAAALAADCggICgAAAA==.Alitia:BAAALAAECgIIBAAAAA==.Alityria:BAAALAAECgUICwAAAA==.Alkrun:BAAALAAECgYICgAAAA==.Almanes:BAAALAAECgYIEgAAAA==.Alranea:BAAALAAECgMIBAAAAA==.',Am='Amazone:BAABLAAECoEWAAIBAAYI9xtFKAD6AQABAAYI9xtFKAD6AQAAAA==.',An='Anarkhys:BAAALAAECgQIAwAAAA==.Ancaeus:BAAALAADCgcIDgAAAA==.Andonian:BAAALAAECgYIBgAAAA==.Anduviel:BAAALAAECgYIEQABLAAECgYIFgABAPcbAA==.Anjomaa:BAAALAAECgMIBAAAAA==.Annissa:BAAALAADCgMIAwABLAAECgUIBQACAAAAAA==.Antaras:BAAALAADCggICAAAAA==.',Ao='Aokoh:BAABLAAECoEUAAMBAAcIMRnnMQDIAQABAAYIJBrnMQDIAQADAAcI0RCTNQBQAQAAAA==.',Ar='Arasara:BAAALAADCggIDgAAAA==.',As='Ascad:BAAALAAECgIIAgAAAA==.Ashpaw:BAAALAADCgcICwAAAA==.Astiarus:BAABLAAECoEUAAIBAAcIDxPtMADNAQABAAcIDxPtMADNAQAAAA==.Astronemer:BAAALAADCgcIDQAAAA==.',At='Athorion:BAAALAADCggICAAAAA==.Atrexie:BAAALAAECgMIBQAAAA==.Attentipo:BAAALAAECggICQAAAA==.',Av='Avengarde:BAAALAAECgQIBwAAAA==.',Ax='Axedd:BAAALAAECgYIDwAAAA==.',Ay='Ayoubb:BAAALAAECgEIAQAAAA==.',Ba='Bakeneko:BAAALAAECgIIAgAAAA==.Baleus:BAAALAADCggIDwAAAA==.Baloney:BAAALAAECgYICwAAAA==.Barboa:BAAALAAECgIIAgAAAA==.',Be='Bellatrixa:BAAALAAECgYIDgAAAA==.Bennike:BAAALAAECggIAQABLAAECggICAACAAAAAA==.Berbrooke:BAAALAADCggICAAAAA==.Bewearorc:BAABLAAECoEXAAIEAAYIoxJzEwBSAQAEAAYIoxJzEwBSAQAAAA==.',Bi='Bigwagyu:BAAALAADCggIGAAAAA==.',Bj='Bjorrn:BAAALAAECgQIBQAAAA==.',Bl='Blodsam:BAAALAAECgMIAwAAAA==.Bloodyhel:BAAALAAECgYIDgAAAA==.',Bo='Bojowy:BAAALAADCgIIAgAAAA==.Boldensjane:BAACLAAFFIEFAAIFAAIIBBc/AQCtAAAFAAIIBBc/AQCtAAAsAAQKgRsAAgUACAjQFZUEAF0CAAUACAjQFZUEAF0CAAAA.Bonarius:BAAALAAECgIIAgAAAA==.Bozanaestra:BAAALAADCgcIBwABLAAECgEIAgACAAAAAA==.',Br='Bratsaras:BAAALAAECgMIBAAAAA==.Bruceflea:BAAALAAECgMIAwAAAA==.Brumbazz:BAAALAAECgEIAQAAAA==.',['Bú']='Búl:BAAALAADCggICAAAAA==.',Ca='Calalith:BAAALAAECggICgAAAA==.Calistha:BAAALAAECgYIDgAAAA==.Callack:BAAALAAECgMIBAAAAA==.Carepolice:BAAALAAECgQIBwAAAA==.Cascara:BAAALAAECgYIDwAAAA==.',Cc='Cc:BAAALAADCggICAAAAA==.',Ce='Celestial:BAAALAADCggICAAAAA==.Celetus:BAAALAADCgcIBwAAAA==.',Ch='Chadwizard:BAAALAAECgQIBAAAAA==.Charnelestra:BAABLAAECoEWAAIGAAcIXBAcKQCwAQAGAAcIXBAcKQCwAQABLAAECgcIFwAHAHEiAA==.Chedward:BAABLAAECoEWAAIIAAcIvR47CABfAgAIAAcIvR47CABfAgAAAA==.Chibi:BAAALAADCgcIBQAAAA==.Chisei:BAAALAAECggIAwAAAA==.Chopsuey:BAAALAAECgYIDgAAAA==.',Ci='Cibus:BAAALAAECgMIAwAAAA==.',Co='Cocodudu:BAABLAAECoEVAAMJAAcI7BFNPgAoAQAJAAYIJhBNPgAoAQAKAAcIDAWSPgAKAQAAAA==.Colino:BAAALAADCggICAAAAA==.',Cr='Craesa:BAAALAADCggICAAAAA==.Crowblade:BAAALAAECgMIAwAAAA==.',Cs='Csontii:BAAALAAECgYIEQAAAA==.',Cy='Cyni:BAABLAAECoEWAAILAAcInhV7EQDCAQALAAcInhV7EQDCAQAAAA==.Cynicane:BAAALAADCgMIAwABLAAECgcIFgALAJ4VAA==.',Da='Daddycool:BAABLAAECoEdAAIMAAgIGRifHAAmAgAMAAgIGRifHAAmAgAAAA==.Daetha:BAAALAADCgcIFAAAAA==.Dahlamar:BAAALAADCgIIAgAAAA==.Danifullsend:BAABLAAECoEeAAMNAAgIuSMGAwAtAwANAAgIuSMGAwAtAwAOAAEIuRcIJgBLAAAAAA==.Darkbarumky:BAAALAAECgYIBwAAAA==.Darkdragon:BAAALAADCggIDwAAAA==.Darkfaíth:BAAALAADCggICAAAAA==.Darkthrone:BAAALAAECgEIAQAAAA==.',De='Deadcorpse:BAAALAADCggIDgAAAA==.Deathless:BAAALAAECgEIAQAAAA==.Deathnas:BAAALAADCggIEAAAAA==.Decuma:BAAALAADCgcIDgAAAA==.Demonkinge:BAAALAAECgYICgAAAA==.',Di='Diamondtetra:BAAALAAECgYIDwAAAA==.Diebobyy:BAABLAAECoEWAAIPAAcIvCOSBAC6AgAPAAcIvCOSBAC6AgAAAA==.Dirtjam:BAAALAAECgIIAgAAAA==.',Dk='Dkbalu:BAAALAADCgcIEwAAAA==.',Dr='Draghter:BAAALAADCgIIAgAAAA==.Dragonpew:BAAALAAECgIIAgAAAA==.Drakoulini:BAAALAADCgcIBwAAAA==.Draxxion:BAAALAADCggIDQAAAA==.Dreadnaughty:BAAALAAECgIIAgAAAA==.Drstabby:BAAALAAECgQIBwAAAA==.Drummerdude:BAAALAADCgcICwAAAA==.Drumzforeva:BAAALAAECgMIAwAAAA==.Drøl:BAAALAAECgMIAwAAAA==.',Du='Duclip:BAAALAAECggIEgAAAA==.Duffadin:BAAALAAECgYIDgAAAA==.',Ea='Ealo:BAAALAAECgYIDQAAAA==.',Ed='Edubbledee:BAAALAAECgYIDgAAAA==.',El='Elase:BAAALAADCgcIBwAAAA==.Elementalist:BAAALAADCgcIBwAAAA==.Elementalize:BAAALAADCgcIBwAAAA==.Elfitta:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Elihm:BAAALAAECgYIEQAAAA==.Ellis:BAAALAADCggICAAAAA==.Elric:BAAALAADCggIDgAAAA==.Elvispriesty:BAAALAADCgcIFAABLAAECgYIDQACAAAAAA==.Elwevyn:BAAALAAECgYIDQAAAA==.Elyssae:BAAALAADCggIEAAAAA==.',Ep='Ephanim:BAAALAADCggICAAAAA==.',Er='Erogan:BAAALAADCggICAAAAA==.',Eu='Eurus:BAAALAAECgYIBgAAAA==.',Ev='Evening:BAAALAAECgMIAwAAAA==.',Ew='Ewl:BAAALAAECgMIBAAAAA==.',Ex='Extrem:BAAALAAECgMIAwAAAA==.',Fa='Fakinjo:BAAALAAECgYIBgAAAA==.Falenix:BAAALAAECgYIDwAAAA==.Fangslasherr:BAABLAAECoEUAAIBAAcIPCBYHgA4AgABAAcIPCBYHgA4AgAAAA==.',Fe='Feldem:BAAALAADCgcIBwAAAA==.Felissa:BAAALAADCgcIBwAAAA==.Felnatik:BAAALAAECgYIDwAAAA==.Feltetra:BAAALAADCgcIBwAAAA==.Fengan:BAAALAADCggIHQAAAA==.Feulmage:BAAALAAECgcIEgAAAA==.',Fi='Fierystormz:BAAALAAECgMIAwAAAA==.Firechu:BAAALAAECgIIAgAAAA==.',Fl='Floppypigeon:BAAALAAECgUIBQAAAA==.Florijn:BAAALAADCggICAABLAAECgYIFgABAPcbAA==.',Fo='Forata:BAAALAAECgMICAAAAA==.Forkandknife:BAAALAAECgUIDAAAAA==.',Fr='Fregless:BAAALAAECgIIAgAAAA==.Froztbite:BAAALAAECgUIBQAAAA==.Fröstiebear:BAAALAAECgMIBgAAAA==.',Fu='Fujï:BAAALAAECgEIAgAAAA==.',['Fé']='Féntriox:BAAALAADCggIEAAAAA==.',Ga='Gargámel:BAAALAAECgYIBgAAAA==.',Ge='Geosham:BAAALAAECgcICAAAAA==.',Gi='Gibpetsuwu:BAAALAAECgYIBwAAAA==.Gildarts:BAAALAADCgMIAwAAAA==.',Gl='Glamourdale:BAAALAAECgEIAQAAAA==.',Go='Gorgogrim:BAAALAAECgYIDgAAAA==.Gorz:BAAALAAECgcIAwAAAA==.',Gr='Griffèn:BAAALAAECggIAQAAAA==.Grimicus:BAAALAADCgQIAwAAAA==.Grimlir:BAAALAADCgcIBwAAAA==.Grimmtotem:BAAALAAECgYIDwAAAA==.Grog:BAAALAADCgMIAwAAAA==.',Gw='Gwendolyn:BAAALAADCgYIAQAAAA==.',Ha='Haaldiir:BAAALAAECgMIBAAAAA==.Harvs:BAAALAAECgMIAwAAAA==.Hauntmedk:BAAALAAECgEIAQAAAA==.Hauntu:BAAALAAECgUICAAAAA==.',He='Hellstrike:BAAALAADCgcICAAAAA==.Hexxrg:BAAALAAECgIIAwAAAA==.',Hi='Himse:BAAALAADCgcIBwAAAA==.Hiz:BAAALAAECgYICwAAAA==.',Ho='Hoegan:BAAALAAECgIIAgABLAAECgQIBwACAAAAAA==.',Hr='Hragon:BAAALAAECgYIEQAAAA==.',Hu='Humlinheart:BAAALAAECgEIAQAAAA==.',Hy='Hyeju:BAAALAAECgcIDQAAAA==.',Ic='Icecoldd:BAAALAADCggICAAAAA==.',Ik='Ikklepickle:BAAALAADCggICAAAAA==.',Il='Ilann:BAAALAADCggIDgAAAA==.Ilarian:BAAALAAECgIIAQAAAA==.Illidarix:BAAALAAECgEIAQAAAA==.Illydoor:BAAALAAECgMIAwAAAA==.',In='Incredibul:BAAALAAECgEIAQAAAA==.Indirah:BAAALAAECgYIDAAAAA==.',Is='Ishana:BAAALAAECgMIBQAAAA==.Issilid:BAAALAADCgUIBAAAAA==.',It='Itherion:BAAALAADCgEIAQAAAA==.',Ix='Ixtus:BAAALAADCgMIAwABLAADCggIFwACAAAAAA==.',Ja='Jacepwnx:BAAALAADCgYIBgAAAA==.Jaegër:BAAALAADCgUIBQAAAA==.Janickaa:BAABLAAECoEVAAILAAYImBgjEgC4AQALAAYImBgjEgC4AQAAAA==.Jaybied:BAAALAADCgcIBwAAAA==.',Jo='Johnthomas:BAAALAAECgYIEQAAAA==.Joliyty:BAAALAADCgcICgAAAA==.Jondalar:BAAALAADCggICAAAAA==.Joroboros:BAAALAADCggIGAAAAA==.',Ju='Justicë:BAAALAAECgUIBQAAAA==.',Ka='Kadresh:BAAALAADCgQIBAAAAA==.Kaenthar:BAAALAADCggICAAAAA==.Kahunt:BAAALAAECggIDAAAAA==.Kajkage:BAAALAAECgEIAQAAAA==.Kalitz:BAAALAADCgYIBgAAAA==.Karlog:BAAALAAECgMIBwAAAA==.Kawaki:BAAALAADCgMIAwAAAA==.Kazana:BAAALAADCggIFwAAAA==.Kazymod:BAAALAADCggICAAAAA==.',Ke='Kelsin:BAAALAAECgYIBwABLAAECgYIEQACAAAAAA==.Kenagone:BAAALAADCggIHQABLAAECgYIFwAEAKMSAA==.Kercske:BAAALAADCgcIBwAAAA==.',Kh='Khaani:BAAALAAECgEIAQAAAA==.Kharn:BAAALAADCgMIAwABLAAECgcIFQAQAD0gAA==.',Ki='Kielith:BAAALAAECgYICgAAAA==.Kikyoass:BAAALAAECgMIAwAAAA==.Kiriara:BAAALAADCgcIEQAAAA==.Kitch:BAACLAAFFIERAAIRAAYI8CEZAABpAgARAAYI8CEZAABpAgAsAAQKgRoAAhEACAhoIzoDABADABEACAhoIzoDABADAAAA.',Ko='Kokobanana:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.Kokorokara:BAAALAAECgMIBAAAAQ==.Kossian:BAAALAAECgYIEQAAAA==.',Kr='Kravinus:BAAALAADCggICAAAAA==.Kromash:BAAALAAECgUICgAAAA==.Krumpen:BAAALAAECggIBAABLAAECggICAACAAAAAA==.',Ky='Kyndra:BAAALAAECgEIAQAAAA==.Kyy:BAAALAADCggICQAAAA==.',La='Lagerthaa:BAAALAADCgMIAwAAAA==.Lamemonkey:BAAALAAECgYICgAAAA==.Lamithralas:BAAALAAECgYIDAAAAA==.Lanxy:BAABLAAECoEbAAMSAAgIJh6mAQC4AgASAAgIshymAQC4AgATAAYICBsAAAAAAAAAAA==.Latlock:BAAALAADCgcICAAAAA==.Laurana:BAAALAADCggIEAAAAA==.',Le='Letry:BAAALAAECgMIBQAAAA==.',Li='Libber:BAAALAADCgcIEQAAAA==.Lillard:BAAALAADCgUIBQAAAA==.Lilwïz:BAAALAADCggIFgAAAA==.Lionell:BAAALAAECgMIBQAAAA==.Lirík:BAACLAAFFIEJAAIUAAUIABufAAD1AQAUAAUIABufAAD1AQAsAAQKgSEAAhQACAjyJKkGAEIDABQACAjyJKkGAEIDAAAA.Lizardpally:BAAALAAECgYIDAAAAA==.',Ll='Lloydari:BAAALAAECgYIBgAAAA==.',Lo='Lockié:BAAALAAECgEIAQABLAAECgUIBQACAAAAAA==.Lokiarie:BAAALAAECgMIBwAAAA==.Loreki:BAAALAADCgUIBQAAAA==.Lorieth:BAAALAAECgYICQAAAA==.Lorié:BAAALAADCggIHwAAAA==.Lorsan:BAAALAADCgYICAAAAA==.Losspli:BAAALAADCggICAAAAA==.',Lu='Ludidoktor:BAABLAAECoEcAAMHAAgIxA/KIQADAgAHAAgIxA/KIQADAgAMAAMITAHDnQBOAAAAAA==.Lukoo:BAAALAAECgQIBAAAAA==.Luku:BAAALAADCgIIAgAAAA==.Lunadawn:BAAALAAECgYIDQAAAA==.',Ly='Lyriana:BAAALAAECgYIEgAAAA==.Lysera:BAAALAADCgEIAQABLAAECgMIBQACAAAAAA==.Lyétin:BAAALAADCggICAAAAA==.',['Lé']='Léeroy:BAAALAAECgYIDgAAAA==.',Ma='Macbeth:BAAALAADCgcIBwAAAA==.Macmicke:BAAALAADCggIFAAAAA==.Maeldore:BAAALAADCggIDwAAAA==.Magnarstrom:BAAALAADCgUIBQAAAA==.Magnussen:BAAALAAECgUICwAAAA==.Malice:BAAALAAECgYIDQAAAA==.Maligné:BAAALAAECgYIEQAAAA==.Marackez:BAAALAAECgcIEAAAAA==.Marallie:BAAALAADCggIFQAAAA==.Marsupia:BAAALAADCggIIAAAAA==.Marumi:BAAALAADCgQIBAABLAAECgYIDwACAAAAAA==.Mayaa:BAABLAAECoEZAAISAAgIGyU6AABsAwASAAgIGyU6AABsAwAAAA==.Maylive:BAAALAAECgYIDwAAAA==.Mayuu:BAAALAADCggIEAAAAA==.',Me='Mecence:BAAALAADCggIDgAAAA==.Meffiu:BAAALAAECgMIAwAAAA==.Meisietjie:BAAALAAECggICQAAAA==.Mekca:BAAALAADCggICAAAAA==.Melaen:BAAALAADCggIEAAAAA==.Melagorn:BAAALAAECgMIBAAAAA==.Meniere:BAAALAAECgYICwAAAA==.Meskiukas:BAAALAAECgYIDgAAAA==.Metalforeva:BAAALAADCgMIBAAAAA==.Methalis:BAAALAAECgYIEAAAAA==.',Mi='Mies:BAAALAADCggICAAAAA==.Mightyshield:BAAALAAECgEIAQAAAA==.Miranda:BAAALAADCggIDwAAAA==.Mistledove:BAAALAAECgYICAAAAA==.Miyuki:BAAALAAECgYIDgAAAA==.',Mo='Mokkle:BAAALAADCgMIAwAAAA==.Moony:BAAALAADCggICAAAAA==.Morendel:BAAALAADCggIEAABLAAECgYIDQACAAAAAA==.Morgoar:BAAALAADCgcIBwAAAA==.',['Mâ']='Mâgius:BAABLAAECoEXAAIVAAcIiBvuDQBFAgAVAAcIiBvuDQBFAgAAAA==.',['Mó']='Mórphéuz:BAAALAADCgEIAQAAAA==.',['Mö']='Mörkajonte:BAAALAADCgcIBwAAAA==.Mörphy:BAAALAAECgIIAgAAAA==.',Na='Narjala:BAAALAAECgIIAwAAAA==.',Ne='Neclach:BAABLAAECoEeAAIWAAgIgQxFMgC4AQAWAAgIgQxFMgC4AQAAAA==.Neffri:BAAALAADCgcIBwAAAA==.',Ni='Nikyvara:BAAALAADCgcIBwAAAA==.Nilyssa:BAAALAADCgUIBQAAAA==.',No='Nomadx:BAAALAAECgYIBgAAAA==.Nosaint:BAAALAADCgMIAwAAAA==.Novalock:BAAALAAECgMIBwAAAA==.Noxlumina:BAAALAAECgQIBQAAAA==.',Ny='Nyhm:BAAALAADCggICAAAAA==.Nymfel:BAAALAAECgYIEAAAAA==.',Od='Oddo:BAAALAAECggIEgAAAA==.',Ok='Okuyasuni:BAAALAADCgYIBgAAAA==.',Ol='Oldhag:BAAALAAECgYIEAAAAA==.Oldk:BAAALAAECgYIDQAAAA==.',On='Onlyfangs:BAAALAADCgcIBwAAAA==.',Oo='Oomyty:BAAALAADCgQIAwAAAA==.',Op='Opeews:BAAALAAECggICAAAAA==.Oppstoppa:BAAALAAECgMIAwAAAA==.',Pa='Painbringer:BAABLAAECoEXAAIGAAcIDxEPJwC+AQAGAAcIDxEPJwC+AQAAAA==.Paladinsolo:BAAALAAECgEIAQAAAA==.Paladiná:BAAALAAECgUIBQAAAA==.Palajane:BAAALAAECgEIAQAAAA==.Panerai:BAAALAAECgYIEQAAAA==.Pannipa:BAAALAAECgEIAQAAAA==.Papapopoff:BAAALAADCgUIBQAAAA==.Papasmerf:BAAALAADCggIGwAAAA==.Parsifal:BAAALAAECgYIDAAAAA==.Paulpeewee:BAAALAAECgYIBwAAAA==.',Pe='Pedrø:BAAALAAECgYIDwAAAA==.Petersen:BAAALAADCggIDgAAAA==.',Ph='Phongeline:BAAALAADCggIDwAAAA==.',Pi='Piciipocok:BAABLAAECoEUAAMRAAcIfiLGCABdAgARAAcIfiLGCABdAgAUAAEIewwAyAAzAAAAAA==.Pippínz:BAAALAAECggIBgAAAA==.Pius:BAAALAAECgYICQAAAA==.',Pl='Pleunie:BAAALAAECgYIEQAAAA==.',Po='Pompa:BAAALAADCggICAAAAA==.',Pr='Priestelf:BAAALAAECgIIAgAAAA==.Prinxe:BAAALAADCgYIBgAAAA==.Pristiai:BAAALAADCgUIBQAAAA==.Protection:BAAALAADCggICAAAAA==.',Ps='Pseudomonas:BAAALAADCgcICQAAAA==.',Pu='Pubmasher:BAAALAADCgcICAAAAA==.',Qd='Qd:BAAALAADCgYIBgAAAA==.',Ra='Rammas:BAAALAAECgYIDwAAAA==.Ramzess:BAAALAAECgYIEwAAAA==.Ranea:BAAALAAECgYIDAAAAA==.Rastaa:BAAALAADCgcIBwAAAA==.Ravnel:BAAALAAECgIIAgAAAA==.',Re='Recky:BAAALAAECgIIAgAAAA==.Reekplar:BAAALAADCgcIBwAAAA==.Rekenekon:BAAALAAECgYIBgAAAA==.Rethras:BAAALAADCgUIBQAAAA==.Reínhardt:BAAALAADCggICAABLAADCggIEAACAAAAAA==.',Rh='Rheyan:BAAALAADCggICAABLAADCggIEAACAAAAAA==.',Ri='Rinse:BAAALAADCggIFwAAAA==.Rirgoun:BAAALAAECgQICQAAAA==.Ritual:BAAALAADCgYIBgAAAA==.',Ro='Rohân:BAAALAADCggICAAAAA==.Rotkwa:BAAALAAECgYIDQAAAA==.',Ru='Rumzedh:BAABLAAECoEVAAIXAAYIDxLLVAB6AQAXAAYIDxLLVAB6AQAAAA==.',Ry='Ryorek:BAAALAAECgMIBAAAAA==.',['Rä']='Rät:BAAALAADCggICAAAAA==.',['Rö']='Röllí:BAAALAADCgYICQAAAA==.',Sa='Safyra:BAABLAAECoEVAAIDAAYIDQmqRAABAQADAAYIDQmqRAABAQAAAA==.Saihtam:BAAALAAECgMIBQAAAA==.Saintcube:BAAALAADCggIDwAAAA==.Saitha:BAAALAAECgYIDQAAAA==.Salendris:BAAALAADCgYIBgAAAA==.Salroma:BAAALAAECgYIDQAAAA==.Samathe:BAAALAAECgIIAwAAAA==.Samsræv:BAAALAADCggICAAAAA==.Sanitari:BAAALAADCggIDwAAAA==.Santder:BAAALAAECgMIBgAAAA==.Saqib:BAAALAAECgQIBAAAAA==.Saruto:BAAALAADCgEIAQAAAA==.Saty:BAAALAAECgYIDAAAAA==.',Sc='Schuggy:BAAALAADCggIDgAAAA==.Scopydead:BAABLAAECoEWAAIQAAcIzha/PADiAQAQAAcIzha/PADiAQAAAA==.Scousepowa:BAAALAADCggIDQAAAA==.',Se='Selengosa:BAAALAAECgYICgAAAA==.Sephira:BAAALAADCgUIBQABLAAECgYIDwACAAAAAA==.Serune:BAAALAAECgQICQAAAA==.',Sh='Shaa:BAAALAAECgUICwAAAA==.Shabam:BAAALAADCgUIBQAAAA==.Shadowclear:BAAALAADCgQIBAAAAA==.Shadowleaves:BAAALAADCgMIAwAAAA==.Shakaralakar:BAAALAADCgEIAQAAAA==.Shamagus:BAAALAAECgYIDAAAAA==.Shankyy:BAAALAADCgcICQAAAA==.Shao:BAAALAADCggICAAAAA==.Shaoli:BAAALAADCgcIDQAAAA==.Shardina:BAAALAAECgMIBwAAAA==.Shibury:BAAALAADCggIDgAAAA==.Shinypants:BAAALAAECgEIAQAAAA==.Shiori:BAAALAAECgUICgAAAA==.Shiorí:BAAALAADCggIEgAAAA==.Shnack:BAAALAAECggICwAAAA==.Shocksin:BAAALAADCgEIAQABLAAECgYICwACAAAAAA==.Shwinky:BAAALAADCggIDAAAAA==.Shyana:BAAALAAECgYIDwAAAA==.Shïorií:BAAALAAECgYICAAAAA==.',Si='Sidnee:BAAALAADCggIFQAAAA==.Sinxuel:BAAALAAECgMIBQAAAA==.',Sk='Skyolex:BAAALAAECgMIAwAAAA==.',So='Soulo:BAAALAADCggICgAAAA==.',Sp='Span:BAAALAAECgYIEQAAAA==.Spellfire:BAAALAAECgcIDgABLAAECggIFwAVAIgbAA==.Spéxx:BAAALAADCgMIAwABLAAECgYIDgACAAAAAA==.',St='Stonedpally:BAAALAAECgQIBAAAAA==.Stooned:BAAALAADCgMIAwAAAA==.Stormhawk:BAAALAADCggIEgAAAA==.Sttry:BAAALAAECgYIDAAAAA==.',Su='Survikpriest:BAAALAADCgYIBgAAAA==.',Sy='Sycus:BAAALAAECgYICgAAAA==.Synik:BAAALAADCgcIBwAAAA==.Synogosa:BAAALAADCggIEAAAAA==.Sytek:BAAALAAECgIIAgAAAA==.',Sz='Szczena:BAAALAAECgYIDwAAAA==.',['Sä']='Säcken:BAAALAAECgYIDwAAAA==.',['Sí']='Sílvara:BAAALAADCgEIAQAAAA==.',['Só']='Sónny:BAAALAAECgEIAQAAAA==.',Ta='Tahel:BAAALAADCgEIAQAAAA==.Taiger:BAAALAADCggICAAAAA==.Tanaleif:BAAALAAECgcIDwAAAA==.Tarheelhal:BAAALAAECgQIBAAAAA==.Tauryn:BAABLAAECoEUAAIUAAgImR7CFwCkAgAUAAgImR7CFwCkAgAAAA==.Tazlock:BAAALAADCgcIBwAAAA==.Tazos:BAABLAAECoEWAAIQAAcIziJNGQCWAgAQAAcIziJNGQCWAgAAAA==.',Te='Teddy:BAAALAADCggIDQAAAA==.Teil:BAAALAAECgYIDgAAAA==.Templaar:BAAALAAECgYIDgAAAA==.Tencanto:BAAALAADCggIEAAAAA==.Tenskwatawa:BAAALAAECgIIAgABLAAECgYIDwACAAAAAA==.',Th='Thaarius:BAAALAAECgUIBQAAAA==.Thalzera:BAAALAAECgUICwAAAA==.Therigamesh:BAAALAAECgYICAAAAA==.Thesis:BAAALAAECgYIDgAAAA==.Thorwaler:BAAALAAECggICAAAAA==.Thugsley:BAAALAADCgcIBwABLAAECgYIEQACAAAAAA==.',Ti='Ticcus:BAAALAADCggICAABLAAECgMIAwACAAAAAA==.Timotheus:BAAALAAECgYIBgAAAA==.',To='Toon:BAAALAAECgYIDQAAAA==.Totemtree:BAAALAAECgcIEgABLAAECgcIFAABAA8TAA==.',Tr='Trixxii:BAAALAAECgMIAwAAAQ==.',Tu='Tuomusissi:BAAALAADCggIEAAAAA==.',Ty='Tyranuel:BAABLAAECoEYAAIYAAgIphlDCQBsAgAYAAgIphlDCQBsAgAAAA==.Tyrisflare:BAAALAAECgYICwAAAA==.',['Tí']='Tíkkí:BAAALAADCgIIAgAAAA==.',['Tú']='Túrnz:BAAALAAECgMIBQABLAAECggIBgACAAAAAA==.',Ul='Ulxar:BAAALAADCggIFwAAAA==.',Un='Undercutter:BAAALAADCgUIBQAAAA==.Unnown:BAAALAADCggIDwAAAA==.',Uz='Uzil:BAAALAADCgYIBgABLAAECgYICwACAAAAAA==.Uzilmonk:BAAALAADCggICAABLAAECgYICwACAAAAAA==.Uzilsham:BAAALAAECgYICwAAAA==.',Va='Vadeth:BAABLAAECoEUAAIYAAcIXg85IAByAQAYAAcIXg85IAByAQAAAA==.Vaelar:BAAALAAECgEIAQAAAA==.Vaelira:BAAALAADCgYICwAAAA==.Vampìrella:BAAALAADCggIEAAAAA==.Vanília:BAAALAAECgQICQAAAA==.Varamas:BAAALAADCgUIBQAAAA==.',Ve='Veltigor:BAAALAAECggICAAAAA==.',Vi='Vild:BAAALAADCgcICAAAAA==.',Vo='Vodkadrac:BAAALAAECgQIDAAAAA==.Voidpræst:BAAALAADCgMIAwAAAA==.Volantie:BAAALAAECgMIBwAAAA==.',Vr='Vrugdush:BAAALAAECgYIEQAAAA==.',Vu='Vulpestra:BAAALAADCgEIAQAAAA==.',['Vó']='Vórag:BAAALAAECggICAAAAA==.',Wa='Walkingdrunk:BAAALAAECgYIBwAAAA==.Walnor:BAAALAADCggICgAAAA==.Walsey:BAAALAAECgMIBQAAAA==.Waxy:BAAALAAFFAEIAQAAAA==.',Wo='Woofrawrmeow:BAAALAADCggIDgAAAA==.',Wy='Wyrmbane:BAAALAAECgEIAgAAAA==.',Xa='Xaziala:BAAALAADCggIDgAAAA==.',Xe='Xelrath:BAAALAAECgYICQAAAA==.',Xy='Xyeet:BAAALAAECgQICQAAAA==.',Ya='Yahenni:BAAALAADCgYIBgABLAAECgYICwACAAAAAA==.Yasu:BAAALAAECgEIAQAAAA==.',Yo='Yogibear:BAAALAAECgYIBgAAAA==.Yollidan:BAAALAAECgYIDwAAAA==.',['Yö']='Yönvartija:BAAALAAECgYICwAAAA==.',Za='Zab:BAAALAAECgIIAgAAAA==.Zarwollf:BAAALAAECgYICwAAAA==.Zazalamel:BAAALAAECgIIAgAAAA==.',Ze='Zeddiah:BAAALAADCggIDwAAAA==.Zelraa:BAAALAAECgMIAwAAAA==.Zentia:BAAALAADCgMIAwAAAA==.Zetsuix:BAAALAADCgMIAwAAAA==.',Zi='Zilyara:BAAALAAECgYICQAAAA==.',Zo='Zonotte:BAAALAADCgQIBAAAAA==.',Zu='Zuldaz:BAABLAAECoEVAAIMAAgIcw22PQCEAQAMAAgIcw22PQCEAQAAAA==.',['Ár']='Árnyróka:BAAALAADCggIDwAAAA==.',['Év']='Éva:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end