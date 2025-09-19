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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Balance','Shaman-Elemental','Evoker-Devastation','Warlock-Demonology','Warrior-Protection','Warlock-Affliction','Priest-Shadow','Mage-Frost','Druid-Restoration','Paladin-Retribution','Warrior-Fury','DemonHunter-Vengeance','Druid-Feral','DeathKnight-Frost','Shaman-Restoration','Shaman-Enhancement','Warlock-Destruction','Hunter-Survival','DeathKnight-Unholy','Warrior-Arms','Druid-Guardian','Monk-Mistweaver','Priest-Holy','Mage-Arcane','Paladin-Protection','Monk-Windwalker','Paladin-Holy',}; local provider = {region='EU',realm='Darksorrow',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ac='Acserus:BAAALAAECgEIAQAAAA==.',Ad='Adeliné:BAAALAAECgMIAQAAAA==.Adrastia:BAAALAADCgUIBQAAAA==.',Ae='Aeeshma:BAAALAAECgIIAgAAAA==.Aelara:BAAALAADCgEIAQAAAA==.',Al='Alenowyn:BAAALAAECgYIDQAAAA==.Alethar:BAAALAADCggICAAAAA==.Alko:BAAALAADCggICAAAAA==.Allandin:BAAALAAECgYIBgAAAA==.Allisius:BAAALAAECgUIDQABLAAECgYIDAABAAAAAA==.',Am='Amazona:BAAALAAECgYICgAAAA==.Amixx:BAAALAAECgMIBAAAAA==.',An='Anoril:BAAALAADCgIIAgAAAA==.',Ar='Arafon:BAAALAAECgYIBwAAAA==.Ardeth:BAAALAAECgcIEAAAAA==.Armpit:BAAALAAECgYIDgAAAA==.Arthozs:BAAALAAFFAIIAgAAAA==.',As='Asacshreder:BAAALAADCgcIDAAAAA==.Asiliath:BAAALAADCggICAAAAA==.',At='Atheenaa:BAAALAADCgYIBgAAAA==.',Au='Auraria:BAAALAAECgMIAwAAAA==.Aurea:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Av='Avisage:BAAALAADCggIDgAAAA==.',Bb='Bbdr:BAAALAAECgEIAQABLAAECggIFQACADwXAA==.Bbh:BAABLAAECoEVAAMCAAgIPBdHJADBAQACAAcI3hVHJADBAQADAAEIzSBFhgBjAAAAAA==.',Be='Beagelli:BAAALAAECgYIDAAAAA==.Beefstar:BAAALAADCgYIBgABLAADCggICAABAAAAAA==.Beelzébub:BAAALAAECgYICwAAAA==.Beffpumper:BAAALAAECggIBgAAAA==.Bergstrom:BAAALAAECgMIBQAAAA==.',Bi='Bigearn:BAAALAAFFAIIAgAAAA==.Biggershoe:BAAALAADCggICAAAAA==.Bigs:BAAALAADCgcIBwAAAA==.Bigsnus:BAAALAAECggIDQAAAA==.Bigtroll:BAAALAADCgUIBQAAAA==.Biksu:BAAALAAECgYIDQAAAA==.Bili:BAAALAADCggICAAAAA==.',Bl='Blackghost:BAAALAAECgcICgAAAA==.Blackwitch:BAAALAADCgQIBAAAAA==.Blindvold:BAAALAADCggIDgAAAA==.Bludy:BAAALAAECgYIBwAAAA==.Blurryxx:BAAALAADCggIDQAAAA==.Blïzp:BAAALAAECgIIAgAAAA==.',Bo='Bodytypeonex:BAAALAADCggICAAAAA==.Bonkd:BAAALAADCggICAAAAA==.Boon:BAAALAAECgEIAQAAAA==.',Br='Bracomaniacu:BAAALAADCgYIBgAAAA==.Bradias:BAAALAADCggICAAAAA==.Breanan:BAAALAAECgYIDgAAAA==.Brezax:BAAALAADCgYIBQAAAA==.Brudonna:BAABLAAECoEYAAIEAAgIxQfEKgCLAQAEAAgIxQfEKgCLAQAAAA==.Bruik:BAAALAADCgUIBQAAAA==.',Bu='Bubbels:BAAALAAECgEIAQABLAAECgYIEQABAAAAAA==.Bue:BAAALAADCgcICAABLAAECgYIDQABAAAAAA==.Bugabuser:BAAALAAECgQICAAAAA==.Bulkers:BAAALAAECgIIAgAAAA==.',['Bä']='Bälsk:BAAALAAECggICAAAAA==.',Ca='Caelix:BAAALAADCggICAABLAAECggIGwADANYgAA==.Caiera:BAAALAADCgcIDgAAAA==.Caldaru:BAAALAADCggICAABLAAECgQICgABAAAAAA==.Calisso:BAAALAADCgMIAwAAAA==.Carthadras:BAAALAADCggIDwAAAA==.Cayla:BAAALAADCggIEAAAAA==.',Ce='Ceaseless:BAAALAAECggICAAAAA==.',Ch='Chappee:BAAALAADCggIBQAAAA==.Charred:BAAALAAECgMIAwABLAAECgcIFQAFAKcWAA==.Cheryl:BAAALAAECgYICgAAAA==.Chihuahuá:BAAALAAECgYIBgAAAA==.Chronic:BAAALAADCgQICAABLAAECgcIBwABAAAAAA==.Chronicza:BAAALAAECgcIBwAAAA==.Chánchú:BAAALAAECgIIAwAAAA==.',Co='Coolmagician:BAAALAADCggIDwAAAA==.Coolreformed:BAAALAAECgYICwAAAA==.Cor:BAAALAADCggICAAAAA==.Corilith:BAAALAAECgcIDwAAAA==.Corx:BAAALAADCgYIBgAAAA==.Corxial:BAAALAAECgMIBAAAAA==.Cowpatrol:BAAALAAECgIIAgABLAAECgYIDQABAAAAAA==.',Cr='Crusade:BAAALAAECgYIBgAAAA==.Cruxlol:BAAALAADCggIFQAAAA==.Cryovex:BAAALAADCggIEQAAAA==.',Cu='Cutesy:BAAALAADCggIEAAAAA==.',Cx='Cxl:BAAALAADCgQIBAAAAA==.',Cy='Cyanidegecko:BAABLAAECoEVAAIGAAcIsSJQCwCjAgAGAAcIsSJQCwCjAgAAAA==.Cyclonis:BAAALAAECgEIAQAAAA==.Cylian:BAAALAAECgYICgAAAA==.',Da='Dagdromer:BAABLAAECoEUAAIHAAcI0B1BCgBcAgAHAAcI0B1BCgBcAgAAAA==.Damodre:BAAALAAECgUIEAAAAA==.Dane:BAAALAAECgYIBwAAAA==.Darrellwar:BAACLAAFFIEFAAIIAAIIKh3ABQCrAAAIAAIIKh3ABQCrAAAsAAQKgRcAAggACAjbIMkEAPUCAAgACAjbIMkEAPUCAAAA.Darutan:BAAALAADCggICwAAAA==.',De='Deadecho:BAAALAADCggIDwAAAA==.Deathangél:BAAALAAECgMIBQAAAA==.Defiance:BAAALAAECgYICwAAAA==.Demone:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Demonlina:BAAALAAECgYICQABLAAECgYIEAABAAAAAA==.Destíní:BAAALAAECgYICgAAAA==.',Di='Diidel:BAAALAAECgYIDgAAAA==.Dinahn:BAAALAAECgYIBwAAAA==.Dippendots:BAABLAAECoEaAAMJAAgIbxh9AwCCAgAJAAgIbxh9AwCCAgAHAAUICQmdOAANAQAAAA==.Dixsie:BAAALAAECggIDQAAAA==.',Dj='Djape:BAAALAAECgMIBQAAAA==.',Dm='Dmonico:BAAALAADCgYIBwAAAA==.',Do='Domythic:BAAALAAECgYIBwAAAA==.Donxe:BAABLAAECoEXAAIIAAgIByPKAgAxAwAIAAgIByPKAgAxAwAAAA==.Dopeshot:BAAALAADCgUIBQAAAA==.Dorvax:BAAALAAECgYIDgAAAA==.Dotsnohots:BAAALAADCggICAAAAA==.',Dr='Dragonpet:BAAALAADCggIGAAAAA==.Drakkreb:BAAALAAECgYICQAAAA==.Dreamingdare:BAAALAAECgMIAwAAAA==.',Dw='Dwarfey:BAAALAAECggIEAAAAA==.',Ef='Effy:BAACLAAFFIELAAIKAAYIERfcAAArAgAKAAYIERfcAAArAgAsAAQKgR4AAgoACAgIJV0CAF4DAAoACAgIJV0CAF4DAAAA.',Eh='Ehterem:BAAALAAECgMICAAAAA==.',Ei='Eiwýn:BAAALAAECgYIDgAAAA==.',Ek='Ekke:BAAALAADCggIIAAAAA==.',El='Elique:BAAALAAECgcIEAAAAA==.Elvadin:BAAALAAECgYIBgAAAA==.Elvin:BAAALAAECgYICwAAAA==.Elycia:BAAALAAECgEIAQAAAA==.',Em='Emilla:BAAALAAECgYIDQAAAA==.Empire:BAAALAADCggIEwABLAAECgYIBgABAAAAAA==.Empyreal:BAAALAADCgYIBgAAAA==.',En='End:BAAALAADCgIIAgAAAA==.Enys:BAABLAAECoEYAAILAAcIuiMQBgDYAgALAAcIuiMQBgDYAgAAAA==.',Eo='Eonnico:BAAALAADCgYIBgAAAA==.',Er='Ernor:BAAALAAECgEIAQAAAA==.Eruco:BAABLAAECoEcAAIKAAgIJByIDgCqAgAKAAgIJByIDgCqAgAAAA==.',Es='Esaty:BAAALAAECgUIAwAAAA==.',Ex='Exya:BAACLAAFFIEFAAIMAAMILA+MBQDgAAAMAAMILA+MBQDgAAAsAAQKgSAAAgwACAgfIt8EAO8CAAwACAgfIt8EAO8CAAAA.',Fa='Farastall:BAAALAAECgcIDQAAAA==.Fatliz:BAAALAAECgUICAAAAA==.',Fe='Fearthepleb:BAAALAADCgEIAQAAAA==.Felmm:BAABLAAECoEXAAINAAgIOhfvLwAUAgANAAgIOhfvLwAUAgAAAA==.Ferallan:BAABLAAECoEXAAIMAAgIrSXUAABeAwAMAAgIrSXUAABeAwAAAA==.',Fl='Flax:BAAALAADCggIDQAAAA==.',Fo='Foemp:BAAALAAECgcIEgAAAA==.Fondence:BAAALAADCgUIBQAAAA==.Fowls:BAAALAAECgIIAgAAAA==.Fowlz:BAAALAAECggICQAAAA==.',Fr='Frostburst:BAAALAAECggIDwAAAA==.Fráze:BAAALAADCggICAAAAA==.',Fu='Furrific:BAAALAADCgYIBgAAAA==.',['Fê']='Fêlfinger:BAAALAAECggICAAAAA==.',['Fø']='Føgl:BAAALAAECgYIDQAAAA==.',Ga='Gathilian:BAAALAAECgYICgAAAA==.',Ge='Gerlit:BAAALAAECgIIAgAAAA==.',Gi='Gibbon:BAAALAADCggICAABLAAECgYIEQABAAAAAA==.',Go='Gobbash:BAAALAAECgUIBwAAAA==.Gothec:BAAALAADCgUIBQAAAA==.',Gr='Grétà:BAAALAAECgcIEAAAAA==.',Gu='Gudgrun:BAAALAAECgYICAAAAA==.Gudzeal:BAAALAADCgUIBQAAAA==.',Gz='Gzrt:BAAALAAECggIEwAAAA==.',['Gî']='Gîlly:BAAALAAECgQIBQAAAA==.',Ha='Halesgrim:BAABLAAECoEUAAMOAAcIyiCBEgCZAgAOAAcIyiCBEgCZAgAIAAEIFg47SQAqAAAAAA==.Halk:BAAALAADCggIDAAAAA==.Halvthorn:BAAALAAECgYIDQAAAA==.',He='Healyoouup:BAAALAADCggICAAAAA==.Heerria:BAAALAAECgYIBgAAAA==.Helladiin:BAAALAAECgYIDQAAAA==.Henriete:BAAALAAECggIEAAAAA==.Henry:BAAALAADCggICwAAAA==.',Hi='Hiigaran:BAAALAADCgcIBwAAAA==.Hildor:BAAALAAECgEIAQAAAA==.Hiyaldi:BAAALAAECgMIAwAAAA==.',Ho='Holina:BAAALAADCgcIBwAAAA==.Hopeasuoli:BAABLAAECoEZAAMOAAcIuCDFFgBpAgAOAAcIgSDFFgBpAgAIAAQItyCtIwA7AQAAAA==.Howlbourne:BAAALAADCggIDwAAAA==.',Hu='Humble:BAABLAAECoEYAAIOAAgINyWbAQByAwAOAAgINyWbAQByAwAAAA==.Hunds:BAAALAADCggIEAABLAAECgYIDgABAAAAAA==.Huntlyfe:BAABLAAECoEeAAMCAAgIYyX4CADiAgACAAgIXSD4CADiAgADAAgIYyWADADaAgAAAA==.',['Há']='Hálibel:BAABLAAECoEVAAIDAAcI6R00HABIAgADAAcI6R00HABIAgAAAA==.',Ic='Icedlatte:BAAALAADCgYIBgAAAA==.',Il='Iliyatheares:BAAALAAECgMIBQAAAA==.Illislan:BAABLAAECoEXAAIPAAgI2BjmCABAAgAPAAgI2BjmCABAAgAAAA==.Ilmentymä:BAAALAAECgIIAgAAAA==.',Im='Imbalover:BAAALAADCgcIDQAAAA==.Immoonen:BAAALAAECgcIDwAAAA==.',Ir='Iriediana:BAAALAADCggIDAAAAA==.Ironbender:BAAALAADCggICAAAAA==.',Is='Isklar:BAAALAAECgYICAAAAA==.Istvan:BAAALAADCggIGQAAAA==.',Iv='Ivelinwe:BAAALAAECgEIAQAAAA==.',Ja='Jaana:BAAALAADCggIGAAAAA==.Jarush:BAAALAAECgYICAAAAA==.',Je='Jegerpurløg:BAAALAAECgMIBgAAAA==.Jerngnomen:BAAALAAECgYIBgAAAA==.',Jo='Jorkingpeen:BAAALAAECgEIAQAAAA==.Joshps:BAAALAADCgEIAQAAAA==.',Ju='Juicebox:BAAALAAECgYIBgAAAA==.',Ka='Kabayan:BAAALAAECgYIDQABLAAECgcIFQAFAKcWAA==.Kaheer:BAAALAADCgQIBAABLAAECgcIDQABAAAAAA==.Karitapio:BAAALAAECgYICQAAAA==.Karkara:BAABLAAECoEWAAIEAAgIHwLJSgCmAAAEAAgIHwLJSgCmAAAAAA==.Karnaisleet:BAAALAAECgUICQAAAA==.Karrin:BAAALAAECgIIAgAAAA==.Karrypto:BAAALAAECgYIDgAAAA==.Kasuhira:BAAALAAECgQIBQAAAA==.Kayotick:BAABLAAECoEZAAIQAAgI2R3wBAC8AgAQAAgI2R3wBAC8AgAAAA==.',Ke='Keerena:BAAALAAECgIIAgAAAA==.Kellagh:BAAALAAECgEIAQAAAA==.',Ki='Kickazsham:BAAALAAECgYICgABLAAECgYICgABAAAAAA==.Kickzsh:BAAALAAECgYICgAAAA==.Kimjongbill:BAAALAADCggIDgABLAAECgMIBQABAAAAAA==.Kiresa:BAAALAAECgMIBAAAAA==.Kironi:BAABLAAECoEWAAIMAAcI8AhePgAoAQAMAAcI8AhePgAoAQAAAA==.Kittkatt:BAABLAAECoEWAAINAAcIGR8rHQB6AgANAAcIGR8rHQB6AgAAAA==.',Kj='Kjakan:BAAALAADCggICAAAAA==.',Kl='Klammekalle:BAAALAAECgYIEAAAAA==.',Kn='Knekten:BAAALAADCggIDwABLAADCggIEwABAAAAAA==.',Ko='Konrad:BAAALAAFFAIIAgAAAA==.Kostok:BAAALAAECgMIBQAAAA==.',Kr='Krnellion:BAABLAAECoEaAAIRAAgIRBzuGgCMAgARAAgIRBzuGgCMAgAAAA==.Krom:BAAALAAECgcIDQABLAAFFAIIBgANAJ4jAA==.',Ku='Kusgan:BAABLAAECoEVAAQFAAcIpxZKJQDrAQAFAAcIuBVKJQDrAQASAAIIchLWlABnAAATAAEIUx09GQBYAAAAAA==.Kusinen:BAAALAADCgEIAQAAAA==.',La='Lahlaan:BAAALAAECgYIDAAAAA==.Lassudan:BAAALAAECgUICQAAAA==.Lazerkylling:BAAALAADCgIIAgAAAA==.',Li='Likeice:BAAALAAECgIIAgAAAA==.Limonelle:BAAALAAECgMIAwAAAA==.Littlesir:BAABLAAECoEWAAQUAAYIVh/HJAALAgAUAAYIVh/HJAALAgAJAAQIjBCvFgD+AAAHAAMIQRVlQQDZAAAAAA==.Livet:BAAALAAECgQIBAAAAA==.',Ll='Lleania:BAAALAADCggIGAABLAAECgcIFAAOAMogAA==.',Lo='Lockè:BAABLAAECoEXAAIGAAcIAgogIwB5AQAGAAcIAgogIwB5AQAAAA==.Lonemagrethe:BAAALAAECggICgAAAA==.Loratrage:BAAALAAECgYIEQAAAA==.',Ly='Lycal:BAABLAAECoEcAAMDAAgIWwz/LgDWAQADAAgIWwz/LgDWAQACAAEIOgNGewAfAAAAAA==.',Ma='Maaskantje:BAABLAAECoEYAAIVAAgI1x2/AQDKAgAVAAgI1x2/AQDKAgAAAA==.Madamada:BAAALAAECgYIBQAAAA==.Maestaff:BAAALAAECgEIAQAAAA==.Maestrof:BAAALAADCggIDgAAAA==.Magikerhulv:BAAALAAECgYIBQAAAA==.Magnhild:BAAALAAECggIEwAAAA==.Magnüs:BAAALAAECggIEAAAAA==.Malex:BAAALAAECgYIBgAAAA==.Malie:BAAALAAECgIIAgAAAA==.Mamet:BAAALAADCgYIBgAAAA==.Manadar:BAACLAAFFIEGAAINAAIIniO6BwDNAAANAAIIniO6BwDNAAAsAAQKgRsAAg0ACAgDJT4EAFwDAA0ACAgDJT4EAFwDAAAA.Manis:BAAALAAECgYIDAAAAA==.Marcules:BAAALAADCgUIBQAAAA==.',Mc='Mcmoe:BAAALAADCgcIBwAAAA==.',Me='Mediumshoe:BAAALAADCggICAAAAA==.Melian:BAAALAAECgYIDAAAAA==.Melpomeni:BAABLAAECoEXAAIWAAcIqB/PBgCUAgAWAAcIqB/PBgCUAgAAAA==.Mephìsto:BAAALAAECgYIEwAAAA==.',Mi='Midriff:BAAALAAECgIIAgAAAA==.Mikká:BAAALAAECgUIBwAAAA==.Mikromus:BAAALAAECgYICQAAAA==.Misanthrope:BAAALAAECgYICwAAAA==.Misspain:BAAALAADCgcIBwAAAA==.',Mo='Moko:BAAALAADCgcIBwAAAA==.Monkboom:BAAALAAECgYIBgAAAA==.Morgore:BAABLAAECoEbAAMHAAcIox6BBwCHAgAHAAcIox6BBwCHAgAJAAEIrw7qLQBKAAAAAA==.Morgoth:BAAALAAECgMIAwAAAA==.Morska:BAAALAAECgMIBQAAAA==.Morwen:BAAALAADCgUIBQAAAA==.Mourbyd:BAAALAADCgUIAwABLAADCggIDwABAAAAAA==.Mourbydpal:BAAALAADCggIDwAAAA==.',Mq='Mqq:BAAALAADCgcIBwAAAA==.',Mu='Mutsuko:BAAALAADCgcIDAAAAA==.',My='Mynni:BAACLAAFFIEIAAIIAAMIhRDuAwDYAAAIAAMIhRDuAwDYAAAsAAQKgRQAAwgABwinID8aAJUBAAgABwinID8aAJUBABcABgiNBeQVAMcAAAAA.Myuoh:BAAALAAECgYIBwAAAA==.',['Mä']='Mättökone:BAAALAADCggIEgAAAA==.',['Mø']='Mørtem:BAAALAADCggICAAAAA==.',Na='Nacataar:BAAALAAECgYICwAAAA==.Nacattar:BAAALAADCgYIBgABLAAECgYICwABAAAAAA==.Naryui:BAAALAAECgMIBAAAAA==.',Ne='Nejnej:BAAALAADCgEIAQAAAA==.Nektar:BAAALAAECgUIBQAAAA==.Nenu:BAAALAADCgcIBwAAAA==.Nescalz:BAAALAADCggICAAAAA==.',Ni='Nioramy:BAAALAADCgIIAQAAAA==.',No='Nocticula:BAAALAAECgYIBgABLAAECggIHAARANofAA==.',Nu='Nutcrackr:BAAALAADCgEIAQAAAA==.Nuuska:BAAALAAECgMIBgAAAA==.',['Nö']='Nöxíe:BAABLAAECoEVAAILAAcI5A0sHgChAQALAAcI5A0sHgChAQAAAA==.',Op='Opaber:BAAALAADCgQIBAAAAA==.',Os='Ossý:BAAALAAECgYIBwAAAA==.',Ov='Oversightx:BAAALAADCgEIAQAAAA==.',Pa='Pacquiao:BAAALAADCggICAAAAA==.Pakkaskarhu:BAAALAADCgcICQAAAA==.Pakoputki:BAAALAAECgYIBgAAAA==.Pandabro:BAAALAADCgMIAwAAAA==.Pandabroski:BAABLAAECoEUAAIEAAgIBwy2MABlAQAEAAgIBwy2MABlAQAAAA==.Parkzicht:BAAALAADCggIEgAAAA==.Partatuke:BAAALAADCgcIBwAAAA==.Paxdrood:BAAALAADCggICAAAAA==.',Pe='Peachpie:BAAALAADCgIIAgAAAA==.Peccifighter:BAAALAAECgYICAABLAAECgYIDAABAAAAAA==.Peccilight:BAAALAAECgYIDAAAAA==.Pewuid:BAABLAAECoEdAAQEAAgIaxbUFQA0AgAEAAgIaxbUFQA0AgAYAAMI1wn0FQB3AAAQAAEIXgIiKwAsAAAAAA==.',Pi='Pinkley:BAAALAAECggIEQAAAA==.',Pl='Plub:BAAALAAECgYIEgAAAA==.',Po='Porrib:BAAALAAECgYIDQAAAA==.',Pr='Prutwuzzel:BAAALAAECgYIDQAAAA==.',Ps='Psyeh:BAAALAADCggIEQAAAA==.Psyfer:BAAALAADCgcIBwAAAA==.',Pu='Puffrider:BAAALAAECgEIAQABLAAECgYIEAABAAAAAA==.',Py='Pyrosham:BAAALAADCggICAAAAA==.Pyrò:BAAALAAFFAIIAgAAAA==.Pyrô:BAAALAADCgYIBgABLAAFFAIIAgABAAAAAA==.',['Pí']='Pímu:BAABLAAECoEWAAIRAAgIhR5OEwDCAgARAAgIhR5OEwDCAgAAAA==.',Ql='Qllix:BAAALAAECgcIDwAAAA==.Qllixlol:BAAALAAECgYIBgAAAA==.',Qu='Quatier:BAAALAADCggICAAAAA==.',Ra='Rafnagud:BAAALAADCgcIDQAAAA==.Ragoya:BAAALAADCggIDQAAAA==.',Re='Reactjs:BAAALAAECgQICgAAAA==.Rege:BAAALAAECgYICwAAAA==.Regor:BAAALAADCgIIAgAAAA==.Retnak:BAAALAAECgQIBQAAAA==.Rewindwalker:BAAALAAECggIEQAAAA==.',Ri='Rio:BAAALAADCgcIBwAAAA==.',Ro='Roguenak:BAAALAAECgYICQAAAA==.',Ru='Runardenvite:BAAALAADCggICgABLAAECgcIEAABAAAAAA==.Runhar:BAAALAADCgYIDAAAAA==.Ruuvii:BAAALAAECgYIDwAAAA==.Ruzyo:BAAALAADCggIEAABLAAECgcIEAABAAAAAA==.',Ry='Rykunamatata:BAAALAAECgcIEwAAAA==.',['Rá']='Rámpagè:BAAALAADCggIEAAAAA==.',['Ré']='Régnak:BAAALAAECggIEQAAAA==.',Sa='Safcejo:BAAALAAECggIEQABLAAFFAIIAgABAAAAAA==.Safcer:BAAALAAFFAIIAgAAAA==.Sagaroth:BAABLAAECoEZAAMMAAgIfSFPBgDUAgAMAAgIfSFPBgDUAgAEAAUIoRRgMgBaAQAAAA==.Sakya:BAAALAAECggICAAAAA==.Samcredible:BAAALAAECgMIAwAAAA==.Sanjikun:BAAALAAECgQIBgAAAA==.',Se='Secdruid:BAAALAAECgEIAQAAAA==.Sergenthull:BAAALAAECgUIBgAAAA==.Serrith:BAAALAAECgYICQAAAA==.',Sh='Shadowm:BAABLAAECoEWAAIZAAgIphWqDgD1AQAZAAgIphWqDgD1AQABLAAFFAIIAgABAAAAAA==.Shadowoluf:BAAALAAFFAIIAgAAAA==.Shalaren:BAAALAAECgYIBgABLAAECgYIEQABAAAAAA==.Shamnex:BAAALAAECgYICAAAAA==.Shaoiboy:BAAALAAECgMIBgAAAA==.Shogun:BAAALAAECgMIAwAAAA==.Shviker:BAAALAADCggICAAAAA==.',Si='Sierrammy:BAAALAAECgYIDQAAAA==.Sikiz:BAABLAAECoEVAAIaAAcIDyLuDAClAgAaAAcIDyLuDAClAgAAAA==.Sinclaire:BAAALAADCggICAABLAAECggIHAARANofAA==.Sinyx:BAAALAAECgEIAQAAAA==.Sithmaster:BAAALAADCggIGgAAAA==.',Sk='Skiller:BAAALAAECgUIBQAAAA==.Skilltotem:BAAALAAECgEIAQAAAA==.',Sl='Slambulance:BAAALAADCggIDQABLAAECgMIBQABAAAAAA==.Slembt:BAAALAADCggICAAAAA==.',Sm='Smitealicius:BAAALAADCggIDgAAAA==.Smorcish:BAAALAAECgMIBAAAAA==.',Sn='Snilleulf:BAAALAAECgYIDQAAAA==.Snokarn:BAAALAADCgcIBwAAAA==.',So='Sojuyakult:BAAALAADCggIDAAAAA==.Sowwy:BAAALAAECgIIAgAAAA==.',Sp='Sparke:BAAALAADCgIIAgAAAA==.Spyderman:BAAALAAECgYIEQAAAA==.Spydruid:BAAALAADCggICAAAAA==.Spylock:BAAALAADCggICAAAAA==.Spymonk:BAAALAADCgYIBgAAAA==.',St='Stan:BAAALAADCgUIBwABLAAECgYIBgABAAAAAA==.Stardust:BAAALAADCgEIAQAAAA==.Steelfeel:BAAALAADCggICwAAAA==.Steffebatan:BAAALAADCgEIAgABLAAECgYIBgABAAAAAA==.Stg:BAAALAAECgIIAgAAAA==.Stopher:BAAALAADCgcIBwAAAA==.Styxiia:BAAALAAECgMIAgAAAA==.Stælnisse:BAAALAADCggICAAAAA==.',Su='Superbirb:BAAALAADCgYIBgAAAA==.',Sv='Sveinarild:BAAALAADCggIEwAAAA==.Svártskägg:BAAALAADCggIGQAAAA==.',Sy='Sylvannawind:BAAALAAECgYICQAAAA==.',['Sá']='Sáber:BAAALAADCgUIBwAAAA==.',['Sú']='Súnsun:BAAALAADCgcIDAABLAAECgcIFQADAOkdAA==.',Ta='Takeursoul:BAAALAADCgcIBwAAAA==.Talshara:BAAALAAECgMIAwAAAA==.Tambor:BAAALAADCggIDwAAAA==.Tapanikansa:BAABLAAECoEYAAMKAAgInyMhCQDyAgAKAAgInyMhCQDyAgAaAAIIeRudXwCWAAAAAA==.Taydera:BAAALAAECgMIAwAAAA==.',Te='Terenes:BAABLAAECoEXAAIRAAgIzhKfMwAHAgARAAgIzhKfMwAHAgAAAA==.',Th='Thargrim:BAAALAADCggIDwABLAADCggIGQABAAAAAA==.Thecountmezz:BAAALAADCgcIDQAAAA==.Thelastvulva:BAAALAADCgcIBwAAAA==.Theurho:BAABLAAECoEaAAINAAgIQBqsIgBXAgANAAgIQBqsIgBXAgAAAA==.Thoms:BAAALAAECgEIAQAAAA==.',Ti='Timbah:BAAALAADCggICAABLAAECgUIBQABAAAAAA==.Tiné:BAAALAAECgIIAwAAAA==.Tismagi:BAABLAAECoEXAAIbAAgIbh+5DwDjAgAbAAgIbh+5DwDjAgAAAA==.Tissikeisari:BAAALAAECgYIDwAAAA==.',To='Tonin:BAABLAAECoEXAAMcAAgIyA7MGwA2AQAcAAYI3BLMGwA2AQANAAcISQhkdQAvAQAAAA==.Tonitio:BAAALAAECggIEwAAAA==.Torsdagsöl:BAAALAADCgIIAgAAAA==.Totastic:BAAALAAECgEIAQAAAA==.Toulouse:BAABLAAECoEXAAIMAAcIERlcIQDMAQAMAAcIERlcIQDMAQAAAA==.Tozza:BAEALAADCgQIBAABLAAECgUIBQABAAAAAA==.',Tr='Trustfall:BAABLAAECoEUAAIaAAgIoQx9MwCIAQAaAAgIoQx9MwCIAQABLAAECggIGgAJAG8YAA==.Trylord:BAAALAADCgYIBgAAAA==.Tryx:BAAALAAECgYICgAAAA==.Trønderstorm:BAAALAADCgMIAgAAAA==.',Ts='Tsuran:BAAALAADCggICQAAAA==.',Tu='Tuffgrabb:BAAALAAECgYIEAAAAA==.Tulu:BAABLAAECoEWAAIOAAgIUyMTCAAWAwAOAAgIUyMTCAAWAwAAAA==.Tulua:BAAALAAECgIIAwAAAA==.',Ty='Tyrael:BAAALAAECggIEAAAAA==.Tyyppi:BAAALAAECgcIEwAAAA==.',Ub='Ubos:BAAALAADCggIDgABLAAECgYIBgABAAAAAA==.',Uk='Ukulele:BAAALAAECgYIBgAAAA==.',Ul='Ullasven:BAAALAAECgcIDgAAAA==.',Um='Umbra:BAAALAADCggIBgAAAA==.',Un='Unlocky:BAAALAAECgUIBwAAAA==.',Ur='Urgatt:BAAALAADCgQIBAAAAA==.Uruzgan:BAAALAADCgIIAgAAAA==.',Va='Vadåvoldsomt:BAAALAAECgYICwAAAA==.Vandemerwe:BAAALAADCgMIAwABLAAECgcIBwABAAAAAA==.Vanetia:BAABLAAECoEcAAIRAAgI2h/RDwDcAgARAAgI2h/RDwDcAgAAAA==.Varon:BAAALAADCgEIAQAAAA==.Vaseera:BAAALAADCggICAAAAA==.Vazov:BAAALAAECgYICQAAAA==.',Ve='Velmu:BAABLAAECoEXAAIMAAcIzhjJHADtAQAMAAcIzhjJHADtAQAAAA==.Veno:BAAALAAECgUICAABLAAECgcIDQABAAAAAA==.Venoar:BAAALAADCgcIDAABLAAECgcIDQABAAAAAA==.',Vh='Vhayne:BAAALAAECgYIDQAAAA==.',Vi='Vivina:BAAALAADCggIGAAAAA==.',Vo='Voetto:BAAALAADCggIDAABLAAECgYIDwABAAAAAA==.Volsung:BAAALAAECgYIEQAAAA==.',['Vå']='Våpen:BAAALAADCggICAAAAA==.',Wa='Warriuden:BAAALAADCggICQAAAA==.',We='Weaverix:BAAALAADCgYIBgAAAA==.',Wi='Wienermunkki:BAABLAAECoEfAAMZAAgI6R8tAwD+AgAZAAgI6R8tAwD+AgAdAAQIqQ7GLADCAAAAAA==.Wiippa:BAAALAAECgYIDAAAAA==.Wildflame:BAAALAADCgcIDAAAAA==.Wimzy:BAAALAAFFAIIAgAAAA==.Winntie:BAABLAAECoEXAAIeAAcI9BPRGAC0AQAeAAcI9BPRGAC0AQAAAA==.',Wq='Wqeqwewqe:BAAALAADCggIFAAAAA==.',Xi='Xinna:BAAALAADCgYIBgAAAA==.',Ya='Yagata:BAAALAAECgYICAAAAA==.',Yi='Yinxx:BAAALAAECggIEAAAAA==.',Yo='Yopotato:BAABLAAECoEPAAIUAAgIwxQZIgAeAgAUAAgIwxQZIgAeAgAAAA==.',Za='Zabroz:BAAALAADCgMIAwABLAAECgcIFQAFAKcWAA==.Zandox:BAAALAADCgcIBwAAAA==.Zarra:BAAALAAECgYIBwAAAA==.',Ze='Zealvoker:BAAALAADCgcIBwAAAA==.Zetonex:BAEALAADCggIDgABLAAECgUIBQABAAAAAA==.Zetx:BAEALAAECgUIBQAAAA==.Zeuhs:BAAALAADCggICAAAAA==.',Zh='Zhaili:BAAALAADCgcIBwAAAA==.Zhen:BAABLAAECoEWAAIRAAYISxldSgCxAQARAAYISxldSgCxAQAAAA==.Zhhoop:BAAALAADCggIDwABLAAECgcIFAAOAMogAA==.',Zi='Ziagon:BAAALAAECgYIDQAAAA==.Zibol:BAAALAAECgYIEAAAAA==.',Zk='Zku:BAAALAAECgcIDgAAAA==.',Zo='Zordiak:BAABLAAECoEeAAIOAAgITCCmCQAEAwAOAAgITCCmCQAEAwAAAA==.Zorrillo:BAAALAADCgcIBwAAAA==.',Zr='Zravis:BAAALAAECgYIDwAAAA==.',Zw='Zwietracht:BAAALAAECgYIBwAAAA==.',Zy='Zyborgagain:BAABLAAECoEVAAMNAAcIWBuSJQBHAgANAAcIWBuSJQBHAgAcAAcIdg87GgBJAQAAAA==.',Zz='Zzloud:BAAALAADCgIIAgAAAA==.',['Zé']='Zét:BAEALAAECgEIAQABLAAECgUIBQABAAAAAA==.',['Ån']='Ånnas:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',['Éi']='Éiwyn:BAAALAAECgYIDQAAAA==.',['Øl']='Ølmann:BAAALAAECgYIDwAAAA==.',['ßl']='ßlïzp:BAAALAAECgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end