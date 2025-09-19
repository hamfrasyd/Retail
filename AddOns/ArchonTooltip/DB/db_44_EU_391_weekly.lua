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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Druid-Restoration','Monk-Brewmaster','Monk-Windwalker','Warrior-Protection','DemonHunter-Havoc','Mage-Arcane','Priest-Shadow','Priest-Holy',}; local provider = {region='EU',realm="Vol'jin",name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aamook:BAAALAAECgEIAQAAAA==.',Ad='Adrakîn:BAAALAAECggICAAAAA==.',Ae='Aegön:BAAALAAECgMIBAAAAA==.Aelthys:BAAALAAECgYIDQAAAA==.Aeri:BAAALAADCgMIAwAAAA==.Aesily:BAAALAAECgEIAQAAAA==.',Ai='Aino:BAAALAAECgQICAAAAA==.',Ak='Akîrä:BAAALAAECgIIAwAAAA==.',Al='Alakajir:BAAALAAECgYICwAAAA==.Alandilas:BAAALAAECgMIBQAAAA==.Aldéha:BAAALAADCggICAAAAA==.Alfirk:BAAALAADCggICAABLAAECgMIBAABAAAAAA==.Allirâsa:BAAALAADCgYIBgAAAA==.',An='Angelic:BAAALAAECgIIAwAAAA==.Angron:BAAALAADCgEIAQAAAA==.Anthowarlike:BAAALAADCgcIEAAAAA==.Antiles:BAAALAADCgcICAAAAA==.Anwyn:BAAALAAECgMIBgAAAA==.',Ar='Aramos:BAAALAAECgQIBQAAAA==.Ariekor:BAAALAAECgcICwAAAA==.Artessia:BAABLAAECoEUAAICAAgItSAEBQDzAgACAAgItSAEBQDzAgAAAA==.',As='Asthya:BAAALAAECgQICgAAAA==.Astrania:BAAALAAECgIIAgAAAA==.Asunä:BAAALAADCgcIDgABLAADCgcIEwABAAAAAA==.',Au='Aurinko:BAAALAAECgMIAwAAAA==.',Az='Azhur:BAAALAADCgYIBgAAAA==.Azmu:BAAALAADCggICAAAAA==.Azn:BAAALAADCggICgAAAA==.',Ba='Balzac:BAAALAADCgYICAAAAA==.Base:BAAALAAECggIAQABLAAECggIDwABAAAAAA==.Bayard:BAAALAADCgYIBwAAAA==.',Be='Bellabeca:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.',Bi='Bigelcham:BAAALAAECgYICgAAAA==.Bikop:BAAALAAECgYIBgAAAA==.Bili:BAAALAAECgQIBwAAAA==.',Bl='Blackblues:BAAALAAECgQIBAAAAA==.Blackmamer:BAAALAAECgYICQAAAA==.Blïnnkk:BAAALAADCgYIEAAAAA==.',Bo='Bodjjackk:BAAALAADCgcIDAAAAA==.Bonchamps:BAAALAADCggIFgAAAA==.Borch:BAAALAAECgIIAgAAAA==.Boreale:BAAALAAECgMIBwAAAA==.',Br='Breakiss:BAAALAADCgMIAwAAAA==.Brisac:BAAALAAECgYICQAAAA==.Brîgitte:BAAALAADCgcIBwAAAA==.Brøm:BAAALAAECgYIBgAAAA==.',['Bâ']='Bâlder:BAAALAADCgYIBgAAAA==.',Ca='Cactuar:BAAALAAECgEIAQAAAA==.Caliawën:BAAALAAECgEIAQAAAA==.Callum:BAAALAADCggIFQAAAA==.Carloman:BAAALAADCgYIBgAAAA==.Cathelyn:BAAALAAECgEIAgAAAA==.Catsays:BAAALAADCgMIAwAAAA==.',Ce='Celeas:BAAALAADCgIIAgAAAA==.Celsius:BAAALAADCggICQAAAA==.Cerf:BAAALAADCgcICgAAAA==.',Ch='Chagun:BAAALAAECgYICwAAAA==.Chamanne:BAAALAADCgMIAwAAAA==.Chamdark:BAAALAADCgEIAQAAAA==.Chassounico:BAAALAADCgcIDgAAAA==.Chenfen:BAAALAAECgMIAwAAAA==.Chouubi:BAAALAAECgUIBQAAAA==.Chrismad:BAAALAAECgQIBwAAAA==.Chémi:BAAALAADCggICAAAAA==.',Ci='Cinquante:BAAALAADCgMIAwABLAAECgYIFAADAC0JAA==.',Cl='Clâff:BAAALAAECgQIBwAAAA==.Clédetreize:BAAALAADCgIIAgAAAA==.',Co='Cobax:BAAALAADCgEIAQAAAA==.Cobrablanc:BAAALAADCgcICwAAAA==.Codo:BAAALAADCgYIBgAAAA==.',Cr='Crakoo:BAAALAADCggICAAAAA==.',Cu='Cunikael:BAAALAADCgYIBgAAAA==.',Cy='Cydia:BAAALAAECgYICQAAAA==.',Da='Dai:BAAALAADCgUIBQABLAAECgYICAABAAAAAA==.Darkelectra:BAAALAADCgQIBAAAAA==.Darkfox:BAAALAADCgYIBwAAAA==.Darklola:BAAALAADCgIIAgAAAA==.Darkujä:BAAALAADCgMIAwAAAA==.Darkxof:BAAALAADCgUIBQAAAA==.',De='Deadhuntter:BAAALAAECgUICQAAAA==.Dekaatlon:BAAALAAECgEIAQAAAA==.Demelza:BAAALAAECgMIBQAAAA==.Denverstraza:BAAALAADCggIFgAAAA==.Dexide:BAAALAAECggIEwAAAA==.',Di='Dimra:BAAALAAECgMIBgAAAA==.',Dj='Djedje:BAAALAAECgcIEQABLAAFFAEIAQABAAAAAA==.Djogo:BAAALAAECgUIBwABLAAECggIFwAEAOElAA==.Djuskarow:BAAALAAECgUIBQABLAAECggIFwAEAOElAA==.Djusko:BAABLAAECoEXAAMEAAgI4SWqAABpAwAEAAgI4SWqAABpAwAFAAEIgRT6LQBDAAAAAA==.',Do='Dondaflexx:BAAALAAECgYIBwAAAA==.Donddaflexx:BAAALAADCggIEAABLAAECgYIBwABAAAAAA==.',Dr='Draugur:BAAALAADCgcIEgAAAA==.Drogur:BAAALAADCggIFgAAAA==.Druiok:BAAALAADCggICAAAAA==.Drôgur:BAAALAADCgcICQAAAA==.',Dw='Dwarderon:BAAALAADCggICAAAAA==.',['Dï']='Dïnadrion:BAAALAADCggIEAAAAA==.',Ea='Eadric:BAAALAAECgEIAQAAAA==.',Ed='Eddiedh:BAAALAAECgMIAwAAAA==.',Ef='Eferalgant:BAAALAADCggICAAAAA==.',El='Eloon:BAAALAADCgcICgAAAA==.Elylia:BAAALAAECgMIBgAAAA==.',En='Enahpets:BAAALAADCgYIBgAAAA==.Entité:BAAALAAECgYICQAAAA==.',Eo='Eowend:BAAALAAECgEIAQAAAA==.',Er='Erénäly:BAAALAADCggICAABLAAECgYICAABAAAAAA==.',Et='Etèrnèl:BAAALAADCggICAAAAA==.',Ex='Exu:BAAALAADCggIFgAAAA==.',Ey='Eykira:BAAALAAECgYIDAAAAA==.',Ez='Ezekia:BAAALAAECgIIBQAAAA==.',Fa='Faenor:BAAALAADCgIIAgAAAA==.',Fe='Feijoa:BAAALAAECgYICgAAAA==.Feitan:BAAALAADCggICgAAAA==.Fendlabrise:BAAALAADCggIDQABLAAECgYICAABAAAAAA==.',Fi='Filledenyx:BAAALAADCggIDgAAAA==.Filypesto:BAAALAAECgYICAAAAA==.',Fo='Formapal:BAAALAADCgcIBwAAAA==.',Fr='Fraziel:BAAALAAECgQIBwAAAA==.Fresh:BAAALAAECgYIDAAAAA==.Frickyd:BAABLAAECoEVAAIGAAgIqhiICABBAgAGAAgIqhiICABBAgAAAA==.Frickyx:BAAALAAECgUICQABLAAECggIFQAGAKoYAA==.Frigouille:BAAALAAFFAEIAQAAAQ==.Fryka:BAAALAADCgcICQAAAA==.',['Fê']='Fêlicîa:BAAALAADCggIEgAAAA==.',['Fë']='Fëlicia:BAAALAAECggIEwAAAA==.',Ga='Gaby:BAAALAAECgEIAQAAAA==.Gainor:BAAALAADCggICAAAAA==.Gandall:BAAALAADCgYIBgAAAA==.',Ge='Gerbeux:BAAALAADCgYIBgAAAA==.',Go='Goldie:BAAALAAECgEIAQAAAA==.Goodold:BAAALAADCgcICQAAAA==.',Gr='Graben:BAAALAAECggICAAAAA==.Grazax:BAAALAADCggIDgAAAA==.Griguef:BAAALAADCggIDgAAAA==.',Ha='Haldiss:BAAALAADCgcICgAAAA==.Haldistress:BAAALAADCgIIAgAAAA==.Hattorï:BAAALAAECgUICAAAAA==.',He='Herion:BAAALAADCgYIBgABLAAECgcIDQABAAAAAA==.Hexumed:BAAALAADCggICAABLAADCggIFgABAAAAAA==.',Hi='Hidemaker:BAAALAADCggICAAAAA==.Hirocham:BAAALAAECgMIAwAAAA==.Hizalina:BAAALAADCggIDwABLAAECgcIEAABAAAAAA==.',Ho='Hokdk:BAAALAAECgEIAQAAAA==.',Hy='Hypak:BAAALAAECgEIAQAAAA==.',['Hé']='Hélène:BAAALAADCgUICwAAAA==.',['Hï']='Hïsoka:BAAALAADCgYIBgAAAA==.',['Hü']='Hüxley:BAAALAAECgcIEAAAAA==.',Ic='Icemen:BAAALAADCgMIBQAAAA==.',Id='Ideum:BAAALAAECgQICAAAAA==.Idkhowtogrip:BAAALAAECgYIBgABLAAECggIFwAHAMwlAA==.Idrila:BAAALAAECgYICgAAAA==.',Il='Illiciaa:BAAALAADCggIEwAAAA==.Illiciae:BAAALAADCggICwAAAA==.Illidash:BAAALAADCgcIDAAAAA==.Ilmoi:BAAALAAECgEIAQAAAA==.Ilokime:BAAALAAECgYICgAAAA==.',In='Ingwiel:BAAALAAECgYIDwAAAA==.',Is='Ishikix:BAAALAADCgMIBQAAAA==.Isyan:BAAALAAECgcIDgAAAA==.',['Iä']='Iäe:BAAALAAECgQICQAAAA==.',Ja='Jahouaka:BAAALAADCgYIBgAAAA==.Jakekill:BAAALAAECgYIDwAAAA==.Jamenia:BAAALAADCggICAAAAA==.Jaugrain:BAAALAADCgMIBgAAAA==.Jaypatousheo:BAAALAAECgYIBgABLAAECgYICAABAAAAAA==.Jaï:BAAALAAECgYICQAAAA==.',Jo='Johnmacbobby:BAAALAAECgQIBgAAAA==.',Ju='Juska:BAAALAAECgUICAAAAA==.Jusklock:BAAALAAECgIIAgAAAA==.',Ka='Kaelden:BAAALAAECgcIEgAAAA==.Kagemitsu:BAAALAAECgMIBAAAAA==.Kagrenac:BAAALAADCgcIDgAAAA==.Kainblade:BAAALAADCggICAAAAA==.Kalab:BAAALAAECgYICwAAAA==.Kapteyn:BAAALAAECgEIAQAAAA==.Karole:BAAALAADCgYICQAAAA==.Kathmandu:BAAALAAECgYICAAAAA==.',Ke='Kenavö:BAAALAADCgMIBQAAAA==.Kenryo:BAAALAAECggICwAAAA==.Keyalerhouse:BAAALAADCgcIDQAAAA==.Keïzho:BAAALAADCgMIAwAAAA==.',Kh='Khaleesî:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.Khensi:BAAALAADCgYIBgAAAA==.Khourouk:BAAALAADCgIIAgAAAA==.Khoursk:BAAALAADCgYIAwAAAA==.Khrystall:BAAALAADCgYIBgAAAA==.Khrÿstall:BAAALAADCggIFAAAAA==.',Ki='Kialys:BAAALAADCggIDQAAAA==.Killerbaal:BAAALAAECgMICAAAAA==.Killerblood:BAAALAADCggIDwABLAAECgMICAABAAAAAA==.Kilowog:BAAALAAECgQIBQAAAA==.Kirozan:BAAALAADCgcIDAAAAA==.',Ko='Koban:BAAALAAECgQIBwAAAA==.Kobsinette:BAAALAAECgMIBgAAAA==.',Kr='Krakoo:BAAALAAECgYIDgAAAA==.',Ku='Kumano:BAAALAAECgYICAAAAA==.',Kw='Kwäk:BAAALAADCgcIDAAAAA==.',Ky='Kyel:BAAALAAECgYICQAAAA==.Kylianã:BAAALAAECgMIBwAAAA==.Kyliøna:BAAALAADCgcICQAAAA==.Kylrïss:BAAALAAECgYICgAAAA==.Kysendra:BAAALAADCgYICAAAAA==.',Kz='Kzey:BAABLAAECoEXAAIHAAgIzCU1AQB9AwAHAAgIzCU1AQB9AwAAAA==.',['Ké']='Kétta:BAAALAADCgcIBwAAAA==.',['Kø']='Kørbustiøn:BAAALAADCgEIAQAAAA==.',La='Labomba:BAAALAADCggIDwAAAA==.Lavalaisanne:BAAALAADCgcIDQAAAA==.Laverde:BAAALAAECgYICwABLAAECgYIFAADAC0JAA==.',Le='Legandel:BAAALAAECgIIAgAAAA==.Legeek:BAAALAADCgYICQAAAA==.Lenwe:BAAALAAECgYICAAAAA==.Letmekissyou:BAAALAADCgcIDQAAAA==.',Li='Lioubia:BAAALAADCgQIBAAAAA==.Lisacendress:BAAALAAECgEIAQAAAA==.',Lo='Lopin:BAAALAAECgQICAAAAA==.Loubleue:BAAALAAECgYIDQAAAA==.Loumas:BAAALAADCgUIBQAAAA==.',Lu='Ludeka:BAAALAADCgcIBwAAAA==.Luluxy:BAAALAAECgIIAgAAAA==.Lunah:BAAALAADCgEIAQAAAA==.Lunatikos:BAAALAAECgEIAQAAAA==.Lunelya:BAAALAADCgMIAwAAAA==.',Ly='Lydwïn:BAAALAAECgQIBAAAAA==.',Ma='Maiia:BAAALAAECgYIDwAAAA==.Malaryäa:BAAALAAECgYICAAAAA==.Mallunée:BAEALAAECgYIDQAAAA==.Malocanine:BAAALAAECgMIBAAAAA==.Malé:BAAALAAECgMIBgAAAA==.Mathania:BAAALAAECgYIBgAAAA==.',Me='Medav:BAAALAAECgYICwAAAA==.Medavv:BAAALAADCgUIBQABLAAECgYICwABAAAAAA==.Medjin:BAAALAADCggICAAAAA==.Meduse:BAAALAAECgMIBAABLAAECgYICAABAAAAAA==.Medzer:BAABLAAECoEVAAIIAAgI2xXgJgD0AQAIAAgI2xXgJgD0AQAAAA==.Megazombie:BAAALAADCggIFwAAAA==.Mell:BAAALAADCgcIBwAAAA==.',Mi='Micrognøme:BAAALAADCgcIDwAAAA==.Microlax:BAAALAADCggIFgAAAA==.Mihtzen:BAAALAADCggIEgAAAA==.Mimelone:BAAALAADCgcIBwAAAA==.',Mo='Moinouille:BAAALAAECgMIAwAAAA==.Morphéis:BAAALAADCgcIBgABLAAECggIFAACALUgAA==.Moî:BAAALAADCgcIDgAAAA==.',Mu='Multani:BAAALAAECgMIBwAAAA==.',My='Myù:BAAALAAECgIIBAAAAA==.',['Mà']='Màrika:BAAALAADCggIFgAAAA==.',['Mé']='Mévlock:BAAALAAECgYICAAAAA==.',['Më']='Mëth:BAAALAADCggIEAABLAAECgYICQABAAAAAA==.Mëthan:BAAALAAECgYICQAAAA==.',['Mô']='Môi:BAAALAADCgYIBgAAAA==.',['Mø']='Mørfine:BAAALAAECgYIDAAAAA==.',Na='Nabøu:BAAALAAECgMIBAAAAA==.Nagios:BAAALAADCgUIBgAAAA==.Nagrosh:BAAALAAECgQICgAAAA==.Namixie:BAAALAAECgMIAwAAAA==.Nanöu:BAAALAAECgIIAgAAAA==.Nassiim:BAAALAAECgQIBAAAAA==.Naysa:BAAALAADCggIDgAAAA==.',Ne='Nearkhos:BAAALAADCgYIBgAAAA==.Necrodrake:BAAALAAFFAEIAQAAAA==.Necromonger:BAAALAADCgYIBgABLAAFFAEIAQABAAAAAA==.Nekfà:BAAALAADCgIIAgABLAAECggIHAAJABAiAA==.Nekfâ:BAABLAAECoEcAAMJAAgIECLaBQAFAwAJAAgIECLaBQAFAwAKAAYIUSMfDgBlAgAAAA==.Nesliors:BAAALAAECgMIBgAAAA==.Nessypew:BAAALAADCgEIAQAAAA==.',Ni='Niniapaspeur:BAAALAADCgYIBgAAAA==.Ninodrood:BAAALAADCggIFgAAAA==.Niro:BAAALAAECgcIDQAAAA==.',No='Normà:BAAALAADCgEIAQAAAA==.Norâh:BAAALAAECgMIAwAAAA==.',Np='Npsaarrive:BAAALAAECgcIDwAAAA==.',Nu='Nualan:BAAALAADCggIDQAAAA==.',Ny='Nyffa:BAAALAADCgYIBgAAAA==.',['Nï']='Nïell:BAAALAADCgYIBgAAAA==.',Od='Odrix:BAAALAAECgYIDwAAAA==.',Oh='Ohkvir:BAAALAADCgUICgAAAA==.',Ok='Okam:BAAALAADCgIIAgAAAA==.',Op='Opàx:BAAALAAECgIIAgAAAA==.',Or='Orgruk:BAAALAAECgIIAgAAAA==.',Os='Oshova:BAAALAAECgYICQAAAA==.',Oz='Ozztralie:BAAALAAECgYICQAAAA==.',Pa='Pakaaru:BAAALAADCggIFgAAAA==.Palafox:BAAALAADCggIFgAAAA==.Paliakov:BAAALAADCgcIDQAAAA==.Pample:BAAALAADCgQIBAAAAA==.Pandøøræ:BAAALAADCggICAAAAA==.Patateheu:BAAALAAECgUIBwAAAA==.Pattobeurre:BAAALAAECgcICgABLAAECgcIDgABAAAAAA==.',Pe='Pellopée:BAAALAAECgQIBAABLAAECgYIDwABAAAAAA==.Petya:BAAALAAECggIDwAAAA==.',Ph='Phoenicis:BAAALAAECgMIBAAAAA==.',Pl='Plassébo:BAAALAADCggIFgAAAA==.',Po='Poirewilliam:BAAALAADCgcICAAAAA==.',Pr='Propa:BAAALAADCgcIBwAAAA==.',['Pî']='Pîtch:BAAALAADCgcIBwAAAA==.',Ra='Raazgul:BAAALAADCgYIDAAAAA==.Rajab:BAAALAAECgcIBwAAAA==.Raskarkapak:BAAALAADCgMIAwAAAA==.',Re='Redmasteur:BAAALAADCggIEwAAAA==.Reza:BAAALAAECgMIAwAAAA==.Reïgna:BAAALAAECgQIBwAAAA==.',Rh='Rhâa:BAAALAAECgIIAgAAAA==.',Ri='Richelieu:BAAALAADCgYIBgAAAA==.Rinata:BAAALAADCgcIDQAAAA==.',Rm='Rmillia:BAAALAADCggIEAAAAA==.',Ro='Robinhood:BAAALAAECggIEAAAAA==.Robinhook:BAAALAADCggICAABLAAECggIEAABAAAAAA==.Romasst:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Romast:BAAALAAECgYICQAAAA==.',Ru='Rushty:BAAALAADCgMIAwAAAA==.',['Rê']='Rêvy:BAAALAAECgMIAwAAAA==.',['Rø']='Røbb:BAAALAAECgUIDAAAAA==.',Sa='Sacerdoce:BAAALAADCgUIBQAAAA==.Sacerdos:BAAALAAECgQIBwAAAA==.Sapphyre:BAAALAAECgEIAQAAAA==.Sardion:BAAALAAECgQICgAAAA==.Sasûké:BAAALAAECgYIAgAAAA==.Satsu:BAAALAAECgMIAwAAAA==.Satsujinpala:BAAALAADCggICAABLAAECgEIAQABAAAAAA==.Saween:BAAALAAECgMIAwAAAA==.',Sb='Sbariou:BAAALAAECgIIAgAAAA==.',Sc='Scratt:BAAALAAECgEIAQAAAA==.',Se='Segaroth:BAAALAAECgYICQAAAA==.Selahani:BAAALAAECgYICgAAAA==.Seleriion:BAAALAAECgMIAwAAAA==.Sellundra:BAAALAAECgIIAgAAAA==.',Sh='Shadrys:BAAALAADCgYIBgAAAA==.Shalumo:BAAALAAECgYICAAAAA==.Shampooze:BAAALAAECgMIAwAAAA==.Shams:BAAALAAECgEIAQAAAA==.Sherloch:BAAALAADCgcICgAAAA==.Sheya:BAAALAAECgYIBgAAAA==.Shyroxx:BAAALAADCgcIBwAAAA==.',Si='Siegward:BAAALAADCgcIBwABLAAECgcICwABAAAAAA==.Sillys:BAAALAADCgcIEAAAAA==.Sinkarley:BAAALAADCggIDgAAAA==.',Sl='Slagger:BAAALAAECgQIBAAAAA==.Släy:BAAALAAECgMIAwAAAA==.',So='Sombreeclat:BAAALAAECgEIAQAAAA==.Soranaar:BAAALAAECgYIDwAAAA==.',Ss='Ssaso:BAAALAADCgYIBgAAAA==.',St='Strakk:BAAALAAECgYICQAAAA==.Strukkmonk:BAAALAADCgcIBwAAAA==.',Su='Sunken:BAAALAAECgYIBgAAAA==.',['Sà']='Sàbrina:BAAALAAECgMIBQAAAA==.',['Sâ']='Sââlikhorn:BAAALAADCggIEgAAAA==.',['Sé']='Ségnolia:BAAALAADCgcIEAAAAA==.Sérénithy:BAAALAAECgYIBgAAAA==.',['Sï']='Sïlâs:BAAALAAECgEIAQAAAA==.',Ta='Taedrun:BAAALAAECgEIAgAAAA==.Tazrek:BAAALAAECgYIDwAAAA==.',Te='Tepes:BAAALAADCgMIAwAAAA==.',Th='Thenewbiche:BAAALAAECgIIAgAAAA==.Thewillou:BAAALAAECgYICQAAAA==.Thyrofix:BAAALAADCgQIBAAAAA==.Thémîs:BAAALAADCgYIBgAAAA==.Thöragrim:BAAALAADCgcIEwAAAA==.',Ti='Tindh:BAAALAAECgMIAwAAAA==.',To='Tomawok:BAAALAAECgYICAAAAA==.Torakka:BAAALAAECgIIAwABLAAECgQICAABAAAAAA==.Tossiborg:BAAALAADCgIIAgAAAA==.',Tr='Traceymartel:BAAALAADCgcIDQAAAA==.Trestycia:BAAALAAECgQIBwAAAQ==.Trynket:BAAALAADCgYIBgAAAA==.',Tu='Tue:BAAALAAECggICAAAAA==.',Tw='Tweetycar:BAAALAADCgUICwAAAA==.',Ty='Tyene:BAAALAAECgYIDQAAAA==.Tyrhenias:BAAALAADCgUIDAAAAA==.',Ul='Ultrafin:BAABLAAECoEUAAIDAAYILQnxNgD4AAADAAYILQnxNgD4AAAAAA==.',Ut='Uturbe:BAAALAADCgcIBwABLAAECgcIDgABAAAAAA==.',Va='Valduin:BAAALAADCggICAAAAA==.Valyrian:BAAALAADCgIIAgAAAA==.Vanbowl:BAAALAAECgYICQAAAA==.',Ve='Velhari:BAAALAAECgMIBgAAAA==.Velmira:BAAALAADCggICAABLAAECgYIDQABAAAAAQ==.Veridiana:BAAALAADCgYIBgAAAA==.',Vi='Viortus:BAAALAAECgQIBAAAAA==.Visalic:BAAALAADCgQIBAAAAA==.',Vo='Vortiguën:BAAALAADCgYIBgAAAA==.',['Và']='Vàmpà:BAAALAAECgMIBgAAAA==.',['Vî']='Vîsk:BAAALAADCgYIBgAAAA==.',Wa='Warhogar:BAAALAAECgMIAwAAAA==.',We='Wentworth:BAAALAADCggIFgAAAA==.Wenuss:BAAALAADCgMIAwAAAA==.',Wo='Worssinferno:BAAALAAECgcIDQAAAA==.',Xe='Xerpî:BAAALAAECgcIDAAAAA==.',Xy='Xyang:BAAALAADCgEIAQAAAA==.',Ya='Yakari:BAAALAADCgEIAQABLAAECgcICwABAAAAAA==.Yanoushka:BAAALAADCggIDwAAAA==.',Ye='Yenlo:BAAALAAECgYIBgABLAAECgYICAABAAAAAA==.',Yo='Yorgl:BAAALAAECgQIBwAAAA==.You:BAAALAADCgUIBQAAAA==.',Yu='Yudima:BAAALAADCgcICwAAAA==.Yuja:BAAALAAECgYIDQAAAA==.Yuri:BAAALAAECgIIAgAAAA==.',Za='Zaiilyo:BAAALAADCggICAAAAA==.Zalurine:BAAALAADCgcIBwAAAA==.',Zi='Zibargor:BAAALAAECgcIEAAAAA==.Zibojin:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Zimtstern:BAAALAADCgIIAgAAAA==.',Zo='Zoüz:BAAALAADCgIIAgAAAA==.',Zu='Zurken:BAAALAAECgQIBwAAAA==.',['Zü']='Züwa:BAAALAAECgYICQAAAA==.',['Äm']='Ämørkë:BAAALAADCgEIAQAAAA==.',['Æp']='Æppø:BAAALAADCggIDwAAAA==.',['Ép']='Épicure:BAAALAADCgYIBgAAAA==.',['Ïa']='Ïae:BAAALAAECgYICgAAAA==.',['Õp']='Õpti:BAAALAAECgEIAQAAAA==.',['Øw']='Øwødd:BAAALAAECgUIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end