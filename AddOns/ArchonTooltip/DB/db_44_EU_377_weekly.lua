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
 local lookup = {'Evoker-Devastation','Mage-Arcane','Priest-Shadow','Priest-Holy','Unknown-Unknown','Shaman-Enhancement','Druid-Restoration','Warrior-Fury','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Paladin-Protection','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Unholy',}; local provider = {region='EU',realm='LesClairvoyants',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abbanhon:BAAALAADCgUICgAAAA==.Abd:BAAALAADCggICQAAAA==.',Ad='Ada:BAABLAAECoEWAAIBAAgIJxbvDABLAgABAAgIJxbvDABLAgAAAA==.',Ae='Aeka:BAAALAADCgMIAwAAAA==.Aelthas:BAAALAADCgIIAgAAAA==.',Ag='Agraou:BAAALAAECgcICwAAAA==.',Ah='Ahésior:BAAALAADCggIFwAAAA==.',Ai='Aigis:BAAALAAECgYIEQAAAA==.',Al='Alarinà:BAAALAADCggICwAAAA==.Aleidra:BAAALAAECgEIAQAAAA==.Alenice:BAAALAAECgcICgAAAA==.Alssahir:BAAALAADCgcIBwAAAA==.Alturiel:BAAALAADCgQIBAAAAA==.',An='Another:BAABLAAECoEWAAICAAgI5Bc/GQBXAgACAAgI5Bc/GQBXAgAAAA==.Anthénia:BAAALAADCgIIAwAAAA==.',Ar='Aragornn:BAAALAAECgEIAgAAAA==.Arcaneï:BAAALAADCgcIBwAAAA==.Arkangë:BAAALAADCgQIBAABLAAECggIFgADABkiAA==.Arkànges:BAABLAAECoEWAAMDAAgIGSIoBQAUAwADAAgIGSIoBQAUAwAEAAYIKxR1JwCGAQAAAA==.Arlyn:BAAALAAECgEIAgAAAA==.Arlynis:BAAALAAECgEIAQAAAA==.Artachaman:BAAALAADCggICgABLAAECgIIAgAFAAAAAA==.Artachasseur:BAAALAAECgIIAgAAAA==.Arwynn:BAAALAAECgUIBwAAAA==.',As='Ashford:BAAALAADCggICAAAAA==.Ashu:BAAALAAECgMIBgAAAA==.Asmodehus:BAAALAAECgYICgAAAA==.Aspen:BAAALAAECgYICwAAAA==.Astra:BAAALAAECgUICwAAAA==.',At='Athanas:BAAALAADCgYIBgAAAA==.',Au='Auroreane:BAAALAAECgEIAgAAAA==.',Av='Avalarion:BAAALAAECgEIAQAAAA==.Avochdar:BAAALAADCgcIBwAAAA==.',Ay='Ayasha:BAAALAADCgYIBwAAAA==.',Az='Azakiel:BAAALAADCggICAAAAA==.',Ba='Baalrog:BAAALAADCgMIAwAAAA==.Baalthazar:BAAALAADCggICgAAAA==.Barakdoum:BAABLAAECoEeAAIGAAgIBSC0AQDwAgAGAAgIBSC0AQDwAgAAAA==.Bartesounet:BAAALAAECgEIAgAAAA==.Battosai:BAAALAADCggIEwAAAA==.',Be='Belphéggorh:BAAALAADCggICAABLAADCggIDwAFAAAAAA==.Bendo:BAAALAADCgUIBgAAAA==.Berylia:BAAALAADCggIFwABLAAECgYIDAAFAAAAAA==.Bestgïrl:BAAALAADCgcIBwAAAA==.Beylphé:BAAALAADCggIDwAAAA==.',Bi='Bigbløødy:BAAALAADCgcIDgAAAA==.',Bl='Blacklîght:BAAALAAECgMIAwAAAA==.Bluenight:BAAALAADCggICwAAAA==.',Bo='Bombur:BAAALAADCgUICAAAAA==.Boombotte:BAAALAADCgcICAAAAA==.Boomerpal:BAAALAADCgUIBQAAAA==.',Br='Brennuss:BAAALAADCgMIAwABLAADCgcIDQAFAAAAAA==.',['Bé']='Bézivin:BAAALAADCgcIBwAAAA==.',['Bî']='Bîsmârck:BAAALAADCgEIAQAAAA==.',Ca='Calécia:BAAALAADCgIIAgAAAA==.Carmila:BAAALAADCgEIAQAAAA==.Carnage:BAAALAADCggICAAAAA==.Catala:BAAALAAECgMIAwAAAA==.',Ce='Celebryss:BAAALAAECgQIBwAAAA==.',Ch='Chevalistet:BAAALAAECgMIBwAAAA==.Chimio:BAAALAADCgcIDQAAAA==.Chässeömbre:BAAALAAECgMIBwAAAA==.',Cl='Clairvoyante:BAAALAADCgcIBwAAAA==.Claris:BAAALAAECgMIBAABLAAFFAIIBAAFAAAAAA==.Clautildae:BAAALAAECgEIAQAAAA==.Clymène:BAAALAADCgUIBQAAAA==.',Co='Coeurdamour:BAAALAAECgIIAgAAAA==.',Cr='Cracoth:BAAALAAECgIIAgAAAQ==.',Da='Daalina:BAAALAADCgEIAQAAAA==.Dabururuma:BAAALAAECggIEAAAAA==.Daezana:BAAALAAECgIIAgAAAA==.Damaladinn:BAAALAAECgMIAwAAAA==.Darkstorms:BAAALAAECgMIBwAAAA==.Darshao:BAAALAAECgYIBgABLAAFFAIIBAAFAAAAAA==.',De='Delysium:BAAALAAECgYICAAAAA==.Demoneldamar:BAAALAAECgYICgAAAA==.',Di='Diivinaa:BAAALAADCggIDAAAAA==.Dimsûm:BAAALAADCggICAAAAA==.',Dj='Djeskia:BAAALAADCgYIBgAAAA==.',Dk='Dkerth:BAAALAAECggIAgAAAA==.',Dr='Dractiizma:BAAALAAECgUIBAABLAAECggIFgAHAIUeAA==.Dreamofme:BAAALAADCggICAAAAA==.Drizzizt:BAAALAADCgIIAgAAAA==.Druidiizma:BAABLAAECoEWAAIHAAgIhR7ABADEAgAHAAgIhR7ABADEAgAAAA==.',Du='Durendael:BAAALAADCgMIBQAAAA==.',El='Elfsane:BAAALAAECgIIAgAAAA==.Ellénia:BAAALAAECgIIAgAAAA==.Eléogeon:BAAALAAECgUICAAAAA==.',Em='Emrakul:BAAALAADCggICAAAAA==.',En='Enotian:BAAALAAECgQIBgAAAA==.Entauma:BAAALAAECgMIBAAAAA==.',Eo='Eorl:BAAALAADCgUICgAAAA==.',Er='Erdemte:BAAALAADCgYIBgAAAA==.Eridana:BAAALAADCggIFwAAAA==.Erzá:BAAALAADCgIIAgAAAA==.',Es='Eskïz:BAAALAADCgcIBwAAAA==.Esmeriss:BAAALAAECgcIDgAAAA==.',Ev='Evictore:BAAALAAECgIIBAAAAA==.',Ez='Ezrille:BAAALAAECgMIAwAAAA==.',['Eà']='Eàrànël:BAAALAAECgUICwAAAA==.',['Eù']='Eùrydice:BAAALAADCgYICwAAAA==.',Fa='Faelthir:BAAALAADCgcIDwAAAA==.Falcora:BAAALAAECgMIBAAAAA==.Fatalquent:BAAALAADCggIBQAAAA==.',Fd='Fdjjingx:BAAALAADCgMIAwAAAA==.',Fh='Fheckt:BAAALAADCggICgAAAA==.',Fi='Fiegthas:BAAALAADCgcIBwAAAA==.Filaenas:BAAALAADCgMIAwAAAA==.',Fr='Fredounette:BAAALAADCgMIAwAAAA==.Frigide:BAAALAAECgUICAAAAA==.',Ft='Ftanck:BAAALAADCgIIAgAAAA==.',Ge='Geraldindø:BAAALAADCggIEAAAAA==.',Gh='Ghy:BAAALAAECgIIAgAAAA==.',Gl='Gliphéas:BAAALAADCgQICAAAAA==.Glàce:BAAALAADCggICAAAAA==.',Gr='Grafomage:BAAALAAECgUIBgAAAA==.Grahumf:BAAALAADCgUICAAAAA==.Gratöpoil:BAAALAADCgcIBwAAAA==.Grimbay:BAAALAADCgcIBwAAAA==.Grimdelwol:BAAALAAECgQICAAAAA==.Grimmbo:BAAALAADCgcICwAAAA==.Grokitape:BAAALAAECggIEwAAAQ==.Grosbaf:BAAALAADCggIDwAAAA==.',Gu='Gultir:BAAALAAECgQIBAAAAA==.',['Gö']='Gödiva:BAAALAAECggICgAAAA==.',Ha='Hadmire:BAAALAADCggIDwAAAA==.Haliki:BAAALAAECgcIEAAAAA==.Hallucard:BAAALAADCgQIBAAAAA==.Hamadreth:BAAALAADCgQIBwAAAA==.Haragorn:BAAALAAECgYIAgAAAA==.Hardgamerz:BAAALAADCggIFgAAAA==.',He='Heiiko:BAABLAAECoEYAAIIAAgImCWzAgBQAwAIAAgImCWzAgBQAwAAAA==.Herunúmen:BAAALAAECgcIEgAAAA==.Heyrin:BAAALAAECgEIAgAAAA==.',Hi='Highglandeur:BAAALAADCgIIAgAAAA==.Hildya:BAABLAAECoEUAAMJAAcI6xwpEgAMAgAJAAcIKxwpEgAMAgAKAAEIuB3dcgBQAAAAAA==.',Ho='Holystik:BAAALAAECgIIAgAAAA==.',Hu='Huntermarché:BAAALAADCgMIAwAAAA==.',Hy='Hytomì:BAAALAADCggICAAAAA==.',['Hè']='Hèra:BAAALAADCggIEQAAAA==.',['Hé']='Héphaistos:BAAALAAECgEIAQAAAA==.',['Hï']='Hïly:BAAALAADCggIDQAAAA==.',Ik='Ikthul:BAAALAADCgYIBwAAAA==.',In='Innaris:BAAALAADCgcIBwAAAA==.',Is='Isménien:BAAALAADCggIDwAAAA==.',Iw='Iwannakillu:BAAALAADCggICwAAAA==.',Jo='Jobloo:BAAALAAECgYIDgAAAA==.',['Jø']='Jømanouche:BAAALAAECgMIBQAAAA==.',Ka='Kakuzo:BAAALAADCgYIBwAAAA==.Kaldryel:BAAALAADCgEIAQAAAA==.Kalhindra:BAAALAAECgEIAQABLAAECgUICAAFAAAAAA==.Kaluksamdi:BAAALAAECgYICwAAAA==.Karros:BAAALAADCgYIBwAAAA==.Kathîa:BAAALAAECgIIAwAAAA==.Kattarn:BAAALAADCgMIAwAAAA==.',Ke='Kerronz:BAAALAAECgUIBQAAAA==.Kertchup:BAABLAAECoEWAAILAAgITRxuDwCpAgALAAgITRxuDwCpAgAAAA==.',Kh='Khanarbreizh:BAAALAADCgYIBgAAAA==.Khykhii:BAAALAAECgcICwAAAA==.Khâzar:BAAALAADCggICAAAAA==.',Ki='Kikixm:BAAALAAECgIIAgAAAA==.Kils:BAAALAAECgcIEQAAAA==.Kiradessus:BAAALAAECgEIAQAAAA==.',Ko='Koo:BAAALAADCgcIBwAAAA==.',Kr='Kraznar:BAAALAADCgQIBAAAAA==.Krivlak:BAAALAAECgMIBwAAAA==.Kronit:BAAALAAECgUICAABLAAECggIFgACAOQXAA==.Krotin:BAAALAAECgIIAgABLAAECggIFgACAOQXAA==.',Ks='Kshaic:BAAALAAECgMIAwABLAADCgcIDQAFAAAAAA==.',Ky='Kynara:BAAALAADCggIFAAAAA==.Kyubî:BAAALAADCggIDgAAAA==.',['Kà']='Kàmï:BAAALAAECgIIAgAAAA==.',['Kä']='Kält:BAAALAADCgcIBwAAAA==.Kätsøü:BAAALAAECgYIDQAAAA==.',['Kë']='Kërronz:BAAALAADCgcIBwABLAAECgUIBQAFAAAAAA==.',['Kï']='Kïnvara:BAAALAADCgcIBwAAAA==.',La='Lameta:BAAALAAECgIIAgAAAA==.Lastresort:BAAALAAECgEIAgAAAA==.Lastresört:BAAALAAECgEIAQAAAA==.Laylanaar:BAAALAADCgcICQAAAA==.Lazerman:BAAALAADCggICAAAAA==.',Le='Leonia:BAAALAADCgUICAAAAA==.Lewalløn:BAAALAAECgYIDAAAAA==.',Li='Lip:BAABLAAECoEWAAQMAAgIyiBeCwCrAgAMAAcIWSBeCwCrAgANAAUIahr8CgCcAQAOAAEIZRMFVwA8AAAAAA==.Lipstíck:BAAALAAECgIIAgAAAA==.Livynette:BAAALAADCgYIBgAAAA==.',Lo='Loulotte:BAAALAADCgUIBQAAAA==.Loxodon:BAAALAAECgUIBwAAAA==.Loztanka:BAAALAAECgIIAgAAAA==.',Lu='Lusir:BAAALAAECgUIBgAAAA==.Luthorr:BAAALAADCggICwAAAA==.',Ly='Lyanna:BAAALAADCggIDQAAAA==.',['Lé']='Léabeillae:BAAALAAFFAIIBAAAAA==.',['Lï']='Lïvy:BAAALAAECgEIAQAAAA==.',['Lô']='Lôlà:BAAALAADCggICwAAAA==.Lôlâ:BAAALAADCggICgAAAA==.',Ma='Mahri:BAAALAAECgYIDAAAAA==.Malyra:BAAALAADCggICwAAAA==.Malzabar:BAAALAAECgMIAwAAAA==.Matory:BAAALAAECgYICwAAAA==.Matsuda:BAAALAADCggIDgAAAA==.',Me='Melraan:BAAALAAECgEIAQAAAA==.Melzeth:BAAALAADCgIIAgAAAA==.Mercurocrøme:BAAALAADCgcIBwABLAAECgIIAgAFAAAAAA==.Metrozen:BAAALAAECgEIAgAAAA==.Meuhlterribl:BAAALAAECgEIAgAAAA==.',Mi='Mictita:BAAALAADCgMIAwAAAA==.Midorin:BAAALAAECgMIBwAAAA==.Minaka:BAAALAAECgYIBgAAAA==.Mirinda:BAAALAADCggIDwAAAA==.Mithrilak:BAAALAADCgQIBAAAAA==.',Mo='Mo:BAAALAADCggICAAAAA==.Molette:BAAALAADCgYIDgAAAA==.',My='Mylial:BAAALAADCgMIAwAAAA==.Mystilia:BAAALAAECgEIAQAAAA==.',['Mä']='Mäbelrode:BAAALAADCgMIAwAAAA==.',['Mé']='Méprèske:BAAALAADCggIDwAAAA==.Mézal:BAAALAADCgUIBQAAAA==.',Na='Naddia:BAAALAADCgYIBgAAAA==.Nalkas:BAAALAADCgYIBwAAAA==.Nariah:BAAALAAECgcIEQAAAA==.Natch:BAAALAAECgYIDAAAAA==.',Ne='Nealsynn:BAAALAADCgYIBwAAAA==.Nephalem:BAAALAADCggICAAAAA==.Neuvillette:BAAALAADCgMIAwAAAA==.Nevos:BAAALAAECgEIAQAAAA==.New:BAAALAADCggIDgAAAA==.Newtonun:BAAALAADCgMIAwAAAA==.Neíth:BAAALAAECgMIBAAAAQ==.',Ni='Nidhögg:BAAALAAECgEIAQAAAA==.Nilania:BAAALAAECgIIAgAAAA==.',No='Noffs:BAAALAAECgMICAAAAA==.',Ny='Nyll:BAAALAAECgUICAAAAA==.',['Né']='Nélidreth:BAAALAADCggIEAAAAA==.Néphys:BAAALAADCgEIAQAAAA==.',['Nü']='Nünquam:BAAALAAECgIIAgABLAAECgMIBAAFAAAAAQ==.',Oh='Ohryà:BAABLAAECoEUAAIPAAcIjhTkDwB2AQAPAAcIjhTkDwB2AQAAAA==.',On='Onardoclya:BAAALAADCgcIEQAAAA==.Onoza:BAAALAAECgEIAgAAAA==.',Or='Orthank:BAAALAADCgcIDgAAAA==.Orélindë:BAAALAADCggIEgAAAA==.',Os='Osteox:BAABLAAECoEXAAIQAAgI6SKRAgD2AgAQAAgI6SKRAgD2AgAAAA==.',Pa='Pakhao:BAAALAADCggICAAAAA==.Paldiuss:BAAALAADCgcIBwAAAA==.Pandaphné:BAAALAADCgcIBwAAAA==.',Pe='Peautter:BAAALAAECgEIAQAAAA==.Petitana:BAAALAAECgUICAAAAA==.Petitanagar:BAAALAADCggIFAAAAA==.',Ph='Physis:BAAALAAECgMIBgAAAA==.',Po='Pomtank:BAAALAAECgQICAAAAA==.',Pr='Prethayla:BAAALAADCgYICAAAAA==.Prinnceps:BAAALAAECgMIAwAAAA==.Prométhèe:BAAALAADCgUICQAAAA==.',Ps='Psalmonde:BAAALAADCgUIBQAAAA==.Psyche:BAAALAADCgMIBAAAAA==.',['Pä']='Pätatör:BAAALAADCgcIBwAAAA==.',Qu='Quickøx:BAAALAADCgEIAQAAAA==.',Ra='Ralariaa:BAAALAAECgcICgAAAA==.Rayhiryn:BAAALAAECgEIAgAAAA==.Razadur:BAAALAAECgMIBAAAAA==.',Rh='Rhyse:BAAALAADCgIIAgAAAA==.',Ri='Rimah:BAAALAAECgYICQAAAA==.',Ro='Ronchon:BAAALAADCgYICQAAAA==.',Sa='Saintebière:BAAALAADCgUIBQAAAA==.Samerlipupet:BAAALAADCggICAAAAA==.Samsaara:BAAALAADCgcIBwAAAA==.Samàel:BAAALAADCggICAAAAA==.Sanctaidd:BAAALAAECgMIBQAAAA==.Saulquipeut:BAAALAADCggIFwAAAA==.Savatte:BAABLAAECoEUAAMRAAcI0Ry5HAA1AgARAAcI9hq5HAA1AgASAAUI4BuFFAB7AQAAAA==.Savvattefufu:BAAALAAECgMIAwAAAA==.',Sc='Schlapükik:BAAALAAECgIIAwAAAA==.Schnerfy:BAAALAADCggIDwAAAA==.Screudot:BAAALAAECgYIBgAAAA==.',Se='Sento:BAAALAADCggICAAAAA==.Severüs:BAAALAAECgEIAQAAAA==.Sevy:BAAALAAECggICAAAAA==.',Sh='Shallyaa:BAAALAAECgIIAgAAAA==.Shameno:BAAALAAECggICAAAAA==.Shannel:BAAALAADCgYIBgAAAA==.Shaîtan:BAAALAADCggICQAAAA==.Shelra:BAAALAADCgQIBAAAAA==.Shenka:BAAALAADCgYIBgAAAA==.Shivaan:BAAALAADCgcIEQAAAA==.Shivanesca:BAAALAAECgYICQAAAA==.Shnerfouille:BAAALAADCggIDQABLAADCggIDwAFAAAAAA==.Shynwar:BAAALAAECgQIBAAAAA==.Shëli:BAAALAAECgYIDAAAAA==.',Si='Sigmunt:BAAALAADCgYIBwAAAA==.Silendil:BAAALAAECgcIEQAAAA==.',Sk='Skarrleth:BAAALAADCgYIDAABLAAECgMIBAAFAAAAAQ==.',Sn='Snack:BAAALAADCgUIBQAAAA==.',So='Sofiyaah:BAAALAADCgQIBAAAAA==.Soléra:BAAALAAECgIIAwAAAA==.Sombraura:BAAALAADCggIDAAAAA==.',Sq='Squeechy:BAAALAADCgQIBwAAAA==.',St='Sthelios:BAAALAAECgQIDAAAAA==.Stoness:BAAALAADCgcIBwAAAA==.Stormers:BAAALAAECgYICAAAAA==.',Su='Sulyah:BAAALAADCgIIAgAAAA==.Supremekaii:BAAALAADCgUIBQAAAA==.',Sy='Syll:BAAALAADCgMIAwAAAA==.',['Sä']='Sämaêl:BAAALAAECgMIBwAAAA==.',Ta='Tacocat:BAAALAAECgYIDgAAAA==.Taillon:BAAALAADCgEIAQAAAA==.Tartotémique:BAAALAADCggICAAAAA==.Taymas:BAAALAADCgcIBwABLAAECgMIAwAFAAAAAA==.',Th='Thaola:BAAALAADCgYIBgAAAA==.Thariantos:BAAALAADCggIGAAAAA==.Thasar:BAAALAAECgEIAgAAAA==.Thelarius:BAAALAADCggIDAAAAA==.Thrallgaze:BAAALAADCgcIBwAAAA==.Thranotyr:BAAALAADCgcIFQAAAA==.Thrän:BAAALAADCgcIBwAAAA==.Thylani:BAAALAADCgcIBwAAAA==.',Ti='Tirganac:BAAALAADCgcIBwAAAA==.',To='Toisondor:BAAALAADCggIDwAAAA==.Tokyö:BAAALAAECgUIBQABLAAECgcIDQAFAAAAAA==.Tourmantal:BAAALAAECgQIBwAAAA==.Toxixm:BAAALAAECgIIAgAAAA==.',Tr='Trafalgarlaw:BAAALAAFFAEIAQAAAA==.Traféïs:BAAALAADCgMIAwAAAA==.Triboule:BAABLAAECoEYAAIIAAgIriJxBAAxAwAIAAgIriJxBAAxAwAAAA==.Trikos:BAAALAADCgcIBwAAAA==.Trogo:BAAALAADCggIDgAAAA==.Tromagnon:BAAALAADCggIDwAAAA==.',Ts='Tsumah:BAAALAADCgcICQAAAA==.',Ty='Tyro:BAAALAADCgQIBAAAAA==.',['Tö']='Tökyo:BAAALAAECgcIDQAAAA==.',Um='Umbarto:BAAALAADCggIBgAAAA==.',Un='Unicorny:BAAALAAECgMIAwAAAA==.Unillusion:BAAALAADCgcIEQAAAA==.Unosdotes:BAAALAADCgYIBwAAAA==.',Ur='Urazon:BAAALAADCgcIBwAAAA==.',Ve='Venize:BAAALAADCgcIBwAAAA==.',Vi='Visaj:BAAALAAECgcIEQAAAA==.',Wa='Warorcs:BAAALAADCggIEwAAAA==.',Wo='Wofol:BAAALAAECgIIBQAAAA==.Worgdany:BAAALAADCggICAAAAA==.Woriten:BAAALAAECgcIEAAAAA==.',Wy='Wyl:BAAALAADCgIIAgAAAA==.',Xa='Xambla:BAAALAADCgcIFQAAAA==.',Xe='Xerosiis:BAAALAADCggICAABLAAECggIGAAIAJglAA==.',['Xà']='Xànthane:BAABLAAECoEWAAIQAAgI+AuNDQCEAQAQAAgI+AuNDQCEAQAAAA==.',Yu='Yuske:BAAALAADCgcIFQAAAA==.',['Yù']='Yùhé:BAAALAADCggIAQAAAA==.',Za='Zango:BAAALAADCggIEwAAAA==.',Ze='Zelmo:BAAALAAECgIIAgAAAA==.Zen:BAAALAAECgUICwAAAA==.',Zo='Zoradia:BAAALAAECgUIBwAAAA==.',Zu='Zulko:BAAALAADCggICAAAAA==.Zullwu:BAAALAAECgMIAwAAAA==.',Zy='Zyhn:BAAALAADCgEIAQAAAA==.',['Àl']='Àlex:BAAALAADCgMIAwAAAA==.',['Är']='Ärkänge:BAAALAADCgcIBwABLAAECggIFgADABkiAA==.',['Äz']='Äzael:BAAALAADCgYIBgAAAA==.',['Ær']='Ærzá:BAAALAADCggICAAAAA==.Ærzã:BAAALAADCgYIBgAAAA==.',['Æy']='Æyzä:BAAALAADCgYIBgAAAA==.',['Ér']='Éri:BAAALAADCgYICgAAAA==.Érydis:BAAALAADCggIEAAAAA==.Érèbos:BAAALAADCgUIDAAAAA==.',['Ðe']='Ðemøn:BAAALAAECggICAAAAA==.',['Ðé']='Ðéysa:BAAALAADCgIIAgAAAA==.',['Øl']='Øllàø:BAAALAADCgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end