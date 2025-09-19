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
 local lookup = {'Unknown-Unknown','Evoker-Devastation','Evoker-Augmentation','Paladin-Retribution','Warlock-Demonology','Warrior-Fury','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Hunter-Survival','Warlock-Destruction','Monk-Windwalker',}; local provider = {region='EU',realm='Todeswache',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aanwynn:BAAALAADCggIFAAAAA==.',Ab='Abrich:BAAALAAECgQIBwAAAA==.',Ak='Akando:BAAALAADCgcIDAAAAA==.',Al='Alani:BAAALAADCgcIBwAAAA==.',An='Aninja:BAAALAAECgMIBAAAAA==.Annahmezwang:BAAALAAECgEIAgAAAA==.Anorexîa:BAAALAADCgIIAgAAAA==.Anpu:BAAALAAECgUIBwAAAA==.',Ar='Aradon:BAAALAAECgYIBwAAAA==.Aredus:BAAALAADCgUIBQAAAA==.',As='Ashmar:BAAALAAECgcICAAAAA==.Astilan:BAAALAADCgcIDwAAAA==.Astilanas:BAAALAAECgEIAQAAAA==.',At='Athene:BAAALAAECgcIEAAAAA==.',Av='Avundadrhiel:BAAALAADCggIEwAAAA==.',Be='Belveth:BAAALAADCgcIBwAAAA==.',Bl='Blazé:BAAALAAECgEIAQAAAA==.',Bo='Bo:BAAALAAECgUIBQAAAA==.Boldar:BAAALAADCggIFgAAAA==.Bonobo:BAAALAADCggIDgAAAA==.',Br='Bradas:BAAALAADCgcIDQAAAA==.',Bu='Budonaga:BAAALAADCgcIBwAAAA==.Bukato:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Ca='Cagen:BAAALAAECgYIEgAAAA==.Caladrier:BAAALAADCggIFwAAAA==.',Ce='Cephion:BAAALAAECgMIBAAAAA==.',Co='Convei:BAAALAADCgIIAgAAAA==.Corvei:BAAALAAECgEIAQAAAA==.',Cr='Creez:BAAALAAECgEIAQAAAA==.Crincher:BAAALAAECgMIBQAAAA==.',Cu='Cursedtime:BAAALAADCgIIAgAAAA==.',['Cá']='Cássándrána:BAAALAADCggICwAAAA==.',Da='Darke:BAAALAAECgMIBQAAAA==.Darkneo:BAAALAADCggIFwAAAA==.',De='Delumine:BAAALAAECgEIAQAAAA==.',Do='Dotterl:BAAALAAECgEIAQAAAA==.',Dr='Dragongirl:BAAALAADCgMIAwAAAA==.Dragonil:BAABLAAECoEUAAMCAAgIzxPFDgArAgACAAgIzxPFDgArAgADAAEISxYsCQAzAAAAAA==.Dralon:BAAALAADCggIFwAAAA==.Drix:BAAALAADCgcIBwAAAA==.',['Dô']='Dôcválè:BAAALAAECgYIDgAAAA==.',Ed='Edessa:BAAALAAECgQIBwAAAA==.Edé:BAABLAAECoEUAAIEAAgIfRYzFQBqAgAEAAgIfRYzFQBqAgAAAA==.',Ei='Eiernockerl:BAAALAAECgQIBQAAAA==.',El='Elfenglanz:BAAALAADCgcIDAAAAA==.Elfron:BAAALAAECgMIBQAAAA==.',Er='Eradis:BAAALAADCggICAAAAA==.Erylai:BAAALAAECggIDQAAAA==.',Es='Estix:BAAALAADCgUIBQAAAA==.',['Eî']='Eîsblumè:BAAALAAECgMIAwAAAA==.',Fl='Flashbulb:BAAALAAECgYIDgAAAA==.',Fr='Freesheeps:BAAALAADCgcIDAAAAA==.Freýja:BAAALAADCgYIBgAAAA==.',Fu='Furian:BAAALAAECgIIAgAAAA==.',Ga='Gabareth:BAAALAADCgUIBAAAAA==.Gambít:BAAALAADCgMIAwAAAA==.Garroshtv:BAAALAAECgYICgAAAA==.',Gh='Ghostiee:BAAALAADCgcIDQAAAA==.',Gi='Girugamesh:BAAALAADCgYICAAAAA==.Gismono:BAAALAADCggIFwAAAA==.Gizmoe:BAAALAAECgUIBwAAAA==.',Go='Goji:BAAALAADCgYIAwABLAAECggIFAAFAM0gAA==.',Gr='Grandel:BAAALAAECggICAAAAA==.Grantlbart:BAAALAADCgEIAQABLAAECggIEgABAAAAAA==.Grimmfaust:BAAALAADCggIEAAAAA==.Gronmór:BAAALAADCggICgAAAA==.',Gu='Gufus:BAAALAAECgIIAgAAAA==.Gummar:BAAALAAECgEIAQAAAA==.',Ha='Halgrim:BAAALAAECgMIBQAAAA==.Harriola:BAAALAAECgMIBQAAAA==.',He='Hefekloß:BAAALAADCgMIAwAAAA==.',Ho='Honignockerl:BAAALAADCgcIDgAAAA==.Horat:BAAALAAECggICAAAAA==.',Hu='Huntard:BAAALAADCgEIAQAAAA==.',Ic='Icedblue:BAAALAADCggIEAAAAA==.',Is='Isea:BAAALAAECgEIAQAAAA==.',Ja='Jayh:BAAALAAECgcIDQAAAA==.',Ji='Jihnta:BAAALAAECgMIBQAAAA==.Jinclap:BAABLAAECoEUAAIGAAgIfh72CADmAgAGAAgIfh72CADmAgAAAA==.Jinoa:BAAALAAECgUICAABLAAECggIFAAGAH4eAA==.',Ka='Kacy:BAAALAAFFAIIAgAAAA==.Kaffeemaus:BAAALAADCgYIBwAAAA==.Kamilia:BAAALAAECgEIAgAAAA==.Karuzô:BAAALAADCgcIBwAAAA==.Kathor:BAAALAADCgcIBwAAAA==.Kaykay:BAAALAAECgMIBAAAAA==.',Ke='Keltaz:BAAALAAECgIIAwAAAA==.Kevin:BAAALAADCgcICQAAAA==.Keyex:BAAALAAECgMIBQAAAA==.Keyshâ:BAAALAAECgcIBwAAAA==.Kezzers:BAAALAAECgUIBgAAAA==.',Ki='Kiotsu:BAAALAAECgIIAwAAAA==.',Ko='Koriadan:BAAALAAECgUIBwAAAA==.',Kr='Kramurx:BAAALAAECggICwAAAA==.',Ku='Kundra:BAAALAADCggICAAAAA==.',['Ké']='Késsý:BAAALAAECgUICQAAAA==.',La='Lariena:BAAALAAECgIIAgAAAA==.',Le='Leerenpfote:BAAALAAECgUIBQAAAA==.Lenula:BAAALAAECgMICAAAAA==.',Li='Lichtwache:BAAALAADCgIIAgAAAA==.Linaewen:BAAALAAECgMIBgAAAA==.Line:BAAALAADCgcICQAAAA==.Linney:BAAALAAECgMIBQAAAA==.',Lo='Lorandia:BAAALAADCgcIDgAAAA==.Lorimbur:BAAALAADCgcIEgAAAA==.Lothrax:BAAALAAECgYIBwAAAA==.',Ly='Lymar:BAAALAADCgcIBwAAAA==.',['Lè']='Lègôlàs:BAAALAAECgIIAgAAAA==.',['Lø']='Løkii:BAAALAAECgcIDQAAAA==.',Ma='Magieperle:BAAALAAECgMIAwAAAA==.Maldoranei:BAAALAADCgcIBwAAAA==.Malric:BAAALAAECgcIEQAAAA==.Malumvulpis:BAAALAAECgEIAQAAAA==.Marshmellow:BAAALAADCgcIDwABLAAECggIFAAFAM0gAA==.Mashala:BAAALAADCggIDQAAAA==.',Me='Meghara:BAABLAAECoEUAAIHAAgIsBi1DwCCAgAHAAgIsBi1DwCCAgAAAA==.Melaidor:BAAALAADCgYIBgAAAA==.Melphice:BAAALAAECgUIBwAAAA==.Merta:BAAALAAECgcIBwAAAA==.Mexylynee:BAAALAADCggIFgAAAA==.',Mi='Mietzi:BAAALAADCggICAAAAA==.Milkmylight:BAAALAADCgcIBwAAAA==.Mime:BAAALAADCgEIAQAAAA==.Minua:BAAALAADCgYICwAAAA==.Mirel:BAAALAAECgMIBQAAAA==.Mirgnrug:BAAALAADCgYICgAAAA==.Mirà:BAAALAADCgUIBQAAAA==.Missdress:BAAALAADCggIDgAAAA==.',Mo='Moandor:BAAALAAECgIIAwAAAA==.Moktharok:BAAALAADCggICAABLAADCggIEwABAAAAAA==.Momji:BAAALAAECgIIAgAAAA==.Monti:BAAALAAECgYIDgAAAA==.Mord:BAAALAAECgQIBwAAAA==.Morkarr:BAAALAAECgQIBAAAAA==.',Mu='Muhzan:BAAALAADCggIEAAAAA==.',My='Mydei:BAAALAADCgcIBwAAAA==.',Na='Naamah:BAAALAAECggIAQAAAA==.Nagar:BAAALAADCgcIBwAAAA==.Nagferata:BAAALAADCggICAAAAA==.Nathanciel:BAAALAADCggICAAAAA==.Nathanciél:BAAALAADCgUIBQAAAA==.',Ni='Nightmare:BAAALAAECgYIBgAAAA==.',No='Noktrâ:BAAALAAECgEIAQAAAA==.',['Nâ']='Nâriko:BAAALAADCggICAAAAA==.',Or='Orista:BAAALAADCgMIAwAAAA==.',Pa='Palahon:BAAALAADCggIDAAAAA==.Palajunge:BAAALAADCgcIBwAAAA==.Paprika:BAAALAADCgIIAgAAAA==.Pastrami:BAAALAAECgMIAwAAAA==.',Pe='Peachclap:BAAALAAECgMIBAABLAAECggIFAAIAF4iAA==.Peachqt:BAABLAAECoEUAAMIAAgIXiJtAQAqAwAIAAgIwiFtAQAqAwAJAAYI3BzrCQC+AQAAAA==.Peachvoid:BAAALAADCgMIAwAAAA==.',Pi='Piknobi:BAAALAAECgIIAgABLAAECgUIBQABAAAAAA==.',Pl='Plumeria:BAAALAAECgIIAgAAAA==.',Po='Poena:BAAALAAFFAIIAgAAAA==.',Pr='Praha:BAAALAADCggIFwAAAA==.Propatria:BAABLAAECoEZAAMHAAgIcyQ9BQAZAwAHAAgI6iM9BQAZAwAKAAYITCP0AQBhAgABLAAFFAIIAgABAAAAAA==.',Qu='Quashranadon:BAAALAAECgEIAQAAAA==.',Ra='Raidra:BAABLAAECoEUAAIGAAgImxBbFwAfAgAGAAgImxBbFwAfAgAAAA==.Ravên:BAAALAADCggIFAAAAA==.',Re='Redayra:BAAALAADCggICwAAAA==.Reâlity:BAAALAAECgIIAgAAAA==.',Ri='Riâs:BAAALAAECgQICAAAAA==.',Rt='Rtyxa:BAAALAADCggIDQAAAA==.',Ru='Ruffnik:BAAALAAECgUIBwAAAA==.Rumpallotte:BAAALAAECgEIAgAAAA==.',['Rê']='Rêkâ:BAAALAADCggIDgAAAA==.',Sa='Sancturio:BAAALAADCgcIBwABLAAECggIFAAGAH4eAA==.Sarasarde:BAAALAAECgEIAQAAAA==.Sashila:BAAALAADCggIFwAAAA==.',Sc='Schatzl:BAAALAADCgcIDwAAAA==.Schnobi:BAAALAADCggIEAABLAAECgUIBQABAAAAAA==.Schokotueten:BAAALAAECgEIAQAAAA==.',Se='Seelenmord:BAAALAAECgEIAQAAAA==.Segelohr:BAAALAADCgYIBgAAAA==.Selan:BAAALAAECgIIAgAAAA==.',Sh='Shadowced:BAAALAAECgQIBAAAAA==.Shadowtoxin:BAAALAADCgIIAgAAAA==.Shanks:BAAALAADCgcIBwAAAA==.Sheilá:BAAALAADCgcIDQABLAAECgYICgABAAAAAA==.Shinomira:BAAALAAECgMIBAAAAA==.Shirohime:BAAALAAECgcIBwAAAA==.Shrimp:BAABLAAECoEUAAMFAAgIzSBAAgDjAgAFAAgI5h9AAgDjAgALAAUIEB6VIQDCAQAAAA==.Shrêk:BAAALAAECgMIAwAAAA==.',Si='Sidewigk:BAAALAADCgcIDwAAAA==.',Sk='Skarex:BAAALAADCggIAQAAAA==.Skênch:BAAALAADCgMIAwAAAA==.',Sm='Smaragdfeuer:BAAALAADCggIFAAAAA==.',St='Stillwaiting:BAAALAAECgUIDwAAAA==.Strawanza:BAAALAAECggIEgAAAA==.Stuffit:BAAALAAECgMIAwAAAA==.',Su='Sugarmama:BAAALAAECgQIBAABLAAFFAIIAgABAAAAAA==.',Sy='Sylfiná:BAAALAAECgQIBwAAAA==.Sylphiê:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâgnix:BAAALAAECgMIAwAAAA==.',Th='Thais:BAAALAADCgcIDAAAAA==.Thallia:BAAALAAECgYIBgAAAA==.Thallium:BAAALAAECgYICQAAAA==.Thorgash:BAAALAAECgcICwAAAA==.',Ti='Tickx:BAAALAAECggICAAAAA==.Tildjar:BAAALAADCgIIAgAAAA==.Timerin:BAAALAAECgQIBwAAAA==.Tiríon:BAAALAADCgYIBgAAAA==.',Tr='Trinanis:BAAALAAECgcIBwAAAA==.Trubak:BAAALAAECgQIBwAAAA==.Trîstân:BAAALAADCgcIBwAAAA==.',Tu='Tuvya:BAAALAAECgUIBQAAAA==.',Ty='Tyranusdra:BAAALAAECgUIBwAAAA==.',Ul='Ul:BAAALAADCggIFwAAAA==.',Un='Unbrauchbär:BAAALAAECgEIAQAAAA==.Unholischitt:BAAALAAFFAIIAgAAAA==.',Ur='Urssula:BAAALAAECgEIAQAAAA==.',Ve='Venzend:BAAALAAECgEIAQAAAA==.',Vi='Vindicatio:BAAALAADCgMIAwABLAAECggIFAAGAH4eAA==.Violenzia:BAAALAADCggICQAAAA==.Viskay:BAAALAADCggIEwAAAA==.Viskong:BAAALAADCgQIBAABLAADCggIEwABAAAAAA==.',Wa='Walküré:BAAALAAECgEIAQAAAA==.War:BAAALAADCggICAAAAA==.Wartak:BAAALAAECgIIAgAAAA==.',Wu='Wutburger:BAAALAAECgYICgAAAA==.',Xe='Xerfît:BAAALAAECgEIAQABLAAECgcICAABAAAAAA==.',Xi='Xirtanome:BAAALAAECgMIAwABLAAECgYICgABAAAAAA==.',Xw='Xwave:BAAALAADCggIEwAAAA==.',Yo='Yordar:BAAALAADCggIDQAAAA==.',Yr='Yraide:BAAALAADCgEIAQABLAADCggICwABAAAAAA==.',Yu='Yulo:BAAALAAECgcIDQAAAA==.',Ze='Zerdilla:BAABLAAECoEXAAIMAAgIOh27BQCnAgAMAAgIOh27BQCnAgAAAA==.',Zi='Zimtrose:BAAALAADCggIDwAAAA==.Zippel:BAAALAAECgIIAgAAAA==.',Zo='Zoraderon:BAAALAAECgMIBgAAAA==.',['Ád']='Áda:BAAALAAECgMIBQAAAA==.',['Ês']='Êsra:BAAALAADCggICwAAAA==.',['Ðe']='Ðeadend:BAAALAAECgUIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end