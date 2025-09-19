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
 local lookup = {'Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Unknown-Unknown','DemonHunter-Vengeance','Shaman-Enhancement','Hunter-BeastMastery','Monk-Brewmaster','Hunter-Marksmanship','Druid-Feral','Priest-Shadow','Paladin-Retribution','DeathKnight-Unholy','Hunter-Survival','Monk-Windwalker','DeathKnight-Frost','DemonHunter-Havoc',}; local provider = {region='EU',realm='MarécagedeZangar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aeranoss:BAAALAAECgYIDAAAAA==.',Af='Afterloose:BAAALAAECgYICQAAAA==.',Ag='Agøth:BAAALAAECgYIDQAAAA==.',Ak='Akodrako:BAAALAAECgIIAwAAAA==.',Al='Albatorh:BAAALAAECgYIEAAAAA==.Allusable:BAABLAAECoEUAAQBAAcIvBBJCgCkAQABAAcIvBBJCgCkAQACAAYIuRYGGQCYAQADAAQIBxbPBAAbAQAAAA==.Alphabyss:BAAALAADCgMIAwAAAA==.Alteya:BAAALAADCgcIBwAAAA==.Althissya:BAAALAAECgUIBwAAAA==.Alyth:BAAALAADCggIDAAAAA==.',Am='Amhät:BAAALAADCggICAAAAA==.',An='Anakô:BAAALAADCggICgAAAA==.Ananasnasdas:BAAALAADCgcICAAAAA==.Andart:BAAALAADCgYICwAAAA==.Ankhala:BAAALAAECgMIAwAAAA==.Anonymours:BAAALAADCgQIBAAAAA==.Antchamousse:BAAALAAECgcIEQAAAA==.',Ao='Aoe:BAAALAAECgIIAwAAAA==.',Ap='Aprune:BAAALAADCggICAABLAAECgYIEAAEAAAAAA==.',Ar='Arabedétendu:BAAALAAECgMIAwAAAA==.Arachtoi:BAAALAADCggIFQABLAAECgMIBAAEAAAAAA==.Arais:BAAALAADCggICwAAAA==.Arcanafly:BAAALAADCgUIBAAAAA==.Arein:BAAALAAECgYIDQABLAAECgcIFAAFAOggAA==.Arialyne:BAAALAADCgYIBgAAAA==.Arkale:BAAALAADCgMIAwAAAA==.Arkenor:BAAALAADCgcIEQAAAA==.Armel:BAAALAADCgcICAAAAA==.Arthodk:BAAALAADCgQIBAAAAA==.Arthosa:BAAALAADCggIFwAAAA==.Arthémonk:BAAALAAECgYIBwABLAAECggIEwAEAAAAAA==.Arthémîs:BAAALAAECggIEwAAAA==.Artolaz:BAAALAAFFAIIAgAAAA==.',As='Asattone:BAAALAADCgEIAQAAAA==.Asklés:BAAALAADCgUIBQAAAA==.Assmodée:BAAALAADCgcIFQAAAA==.',At='Athbor:BAAALAAECggICQAAAA==.',Au='Aurorae:BAAALAAECgIIBwAAAA==.Aurélien:BAAALAADCgEIAQAAAA==.',Ay='Ayanou:BAAALAADCggICQAAAA==.Ayasé:BAAALAADCgYIBgABLAAECgIIAwAEAAAAAA==.Aymo:BAABLAAECoEWAAIGAAcICR6HAwB6AgAGAAcICR6HAwB6AgABLAAFFAEIAQAEAAAAAA==.Aymonk:BAAALAAFFAEIAQAAAA==.',Az='Azyxgodx:BAAALAAECgYIBwAAAA==.',Ba='Baaldeath:BAAALAADCgQIBAAAAA==.Babasse:BAAALAAECgYICAAAAA==.Babouch:BAAALAAECgYIDAAAAA==.Bagella:BAAALAAECgQIBAAAAA==.Bags:BAAALAADCgcIBwAAAA==.Bagura:BAAALAAECgMIAwAAAA==.Bagz:BAAALAADCgcIBwAAAA==.Bahimouth:BAAALAADCgMIAwAAAA==.Bahrio:BAAALAAECgIIAwABLAAECgUICAAEAAAAAA==.Barbä:BAAALAAECgYICQAAAA==.Barhio:BAAALAAECgUICAAAAA==.Barka:BAAALAAECgQIBQAAAA==.Baruk:BAAALAADCgMIBwAAAA==.Bayes:BAAALAADCgYIBgAAAA==.',Be='Belzébut:BAAALAADCgQIBAAAAA==.',Bi='Biboü:BAAALAADCgYIBgAAAA==.',Bl='Blast:BAABLAAECoEWAAIHAAgIpyPbAwA2AwAHAAgIpyPbAwA2AwAAAA==.Blazztag:BAAALAAECgcIDwAAAA==.Bloodyelfe:BAAALAADCggIDAAAAA==.Blâck:BAAALAAECgMIAwAAAA==.',Bo='Bodhisattva:BAAALAAECgYICgAAAA==.Bourrepyf:BAAALAADCggICAAAAA==.',Br='Bramer:BAAALAAECgYIBgABLAAECgcIDQAEAAAAAA==.',['Bâ']='Bârbâ:BAAALAADCgUIBQAAAA==.',['Bî']='Bîgmacdø:BAAALAAECgYIDAAAAA==.',Ca='Cashel:BAAALAADCgIIAgAAAA==.Caïnn:BAAALAADCgQIBAAAAA==.',Ch='Chaseurxtrem:BAAALAADCgMIAwAAAA==.Chãtass:BAAALAAECgMIAwABLAAECgcIDQAEAAAAAA==.',Co='Cornichon:BAAALAAECgYIBgABLAAECgcIDQAEAAAAAA==.Couteloux:BAAALAADCgEIAQAAAA==.',Cr='Cromka:BAAALAADCgcIBwAAAA==.Crosh:BAAALAAECgYIBgABLAAECgcIDQAEAAAAAA==.Crumbette:BAAALAAECgMICQAAAA==.Crôttin:BAAALAAECggICAAAAA==.',Cy='Cyanite:BAAALAAECgcIEQAAAA==.',Da='Daarah:BAAALAADCgYIBgAAAA==.Dagrân:BAAALAAECgIIAgAAAA==.Darkoracle:BAAALAADCgUICQAAAA==.Dawna:BAAALAAECgYIDQAAAA==.Daz:BAAALAAECgcIEwAAAA==.',Dd='Ddazzedd:BAAALAADCggICAAAAA==.',De='Deckssam:BAAALAAECgIIAgAAAA==.Dedlit:BAAALAAECgQIBQAAAA==.Delether:BAAALAADCgcIBwAAAA==.Delos:BAAALAAECgYIDgAAAA==.Delyr:BAAALAAECgIIAgAAAA==.Democlak:BAAALAAECgMIAwAAAA==.Devilelf:BAAALAAECgQICQAAAA==.Deåthsoul:BAAALAADCgcIBwAAAA==.',Dh='Dhoumswar:BAAALAADCgUIBQAAAA==.Dhunterr:BAAALAAECgUIBQAAAA==.',Di='Diahré:BAAALAADCggIDwAAAA==.Diamond:BAAALAAECgYIBgAAAA==.Digata:BAAALAADCgcIBwAAAA==.Dimitrii:BAAALAAECgUICAAAAA==.',Do='Dokarth:BAAALAAECgEIAQAAAA==.Doke:BAAALAADCgMIAwAAAA==.Dorglas:BAAALAADCgIIAgAAAA==.',Dr='Drackir:BAAALAADCggIEAAAAA==.Dracokid:BAAALAAECgYIDAAAAA==.Dragonise:BAAALAADCgYICAAAAA==.Drakshadow:BAAALAAECgEIAQAAAA==.Drink:BAAALAADCgUIBQAAAA==.Driztta:BAAALAAECgYICQAAAA==.Druidly:BAAALAADCgEIAQABLAADCgYIEQAEAAAAAA==.Drörcan:BAAALAAECgIIAgAAAA==.',Du='Dumbledore:BAAALAADCgcIBwAAAA==.',['Dà']='Dànnyu:BAAALAADCgEIAQAAAA==.',['Dæ']='Dæmé:BAAALAAECgYIDAAAAA==.',['Dé']='Déllos:BAAALAADCggICAAAAA==.Dévox:BAAALAADCggIDwAAAA==.',Ec='Eclipal:BAAALAADCggICAAAAA==.',Eg='Eggxëc:BAAALAADCggIDwAAAA==.',Ei='Eiivir:BAAALAAECggIDwAAAA==.',El='Eladriel:BAAALAADCgIIAgAAAA==.Elathil:BAAALAADCggIDgAAAA==.Elfatorusrex:BAAALAAECgcIEAAAAA==.Elguepa:BAAALAAECgMIAwAAAA==.Ellerinâ:BAAALAAECgMIBQAAAA==.Elmekfrite:BAAALAADCggIEQAAAA==.Elpatou:BAAALAAECgcIBwAAAA==.Elröhir:BAAALAADCggICQAAAA==.Elyrà:BAAALAAECgYIDAAAAA==.Elzana:BAAALAADCgcIBwAAAA==.Elzanas:BAAALAAECgMIBQAAAA==.Elørà:BAAALAADCggIDQABLAAECgYIDAAEAAAAAA==.',Em='Emanea:BAAALAAECgIIAgAAAA==.Emeos:BAAALAAECgQICwAAAA==.Emilya:BAAALAADCgIIAgAAAA==.Emyn:BAACLAAFFIEFAAIIAAMIMybLAABbAQAIAAMIMybLAABbAQAsAAQKgRcAAggACAieJhwAAJYDAAgACAieJhwAAJYDAAAA.',En='Enaia:BAAALAAECgIIAgAAAA==.',Er='Erikál:BAAALAAECgcIEwAAAA==.Eríkâl:BAAALAADCggIEQABLAAECgcIEwAEAAAAAA==.Erïos:BAAALAADCgIIAgAAAA==.',Es='Escalrilia:BAAALAAECgMIBQAAAA==.',Ev='Evilboulette:BAAALAAECgQIBAAAAA==.Evozozo:BAAALAADCgcIBwAAAA==.',Ew='Ewyn:BAABLAAECoEVAAMJAAcIqiKlBwC6AgAJAAcIqiKlBwC6AgAHAAQIPxYzTAD9AAAAAA==.',Ex='Exopuissance:BAAALAAECgYICQAAAA==.',Fa='Falzel:BAAALAADCgcICgAAAA==.',Fe='Feelthepain:BAAALAAECgcIEAAAAA==.Fefe:BAAALAAECgEIAQAAAA==.Ferbuoi:BAAALAADCgcIDAAAAA==.',Fi='Fizzib:BAAALAAECgYIEAAAAA==.',Fl='Flagadajones:BAAALAAECgYIDAAAAA==.',['Fä']='Fährer:BAAALAAECgYICQAAAA==.',['Fê']='Fêedemonia:BAAALAADCgcIBwAAAA==.',['Fü']='Füneris:BAAALAAECgYICgAAAA==.',Ga='Gainé:BAAALAADCgcIBwAAAA==.Gaiuuki:BAAALAADCgIIAgAAAA==.Galhadrìel:BAAALAAECggICAAAAA==.Galltaz:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.Gapsu:BAAALAADCgcIDAAAAA==.Garko:BAAALAADCgIIAgAAAA==.Garkovgoth:BAAALAAECgYICAAAAA==.Gasper:BAAALAAECgEIAQAAAA==.Gauth:BAAALAAECgQICQAAAA==.',Gi='Gimlï:BAAALAADCgcIBwAAAA==.Givris:BAAALAAECgMIBQAAAA==.',Go='Goadz:BAAALAADCggIEgAAAA==.Golmono:BAAALAADCgcIDAAAAA==.Goza:BAAALAAECgcIDgAAAA==.',Gr='Griffelune:BAABLAAECoEUAAIKAAgIRh31BAB2AgAKAAgIRh31BAB2AgAAAA==.Grimore:BAAALAADCgIIAgAAAA==.Grubokledk:BAAALAAECgMIAwAAAA==.Gruboklewar:BAAALAADCgcIBwABLAAECgMIAwAEAAAAAA==.Gruboklsham:BAAALAADCgIIAgAAAA==.Grøúx:BAAALAAECgEIAQAAAA==.',Gu='Guylepieux:BAABLAAECoEVAAILAAgIEiQ9AgBSAwALAAgIEiQ9AgBSAwAAAA==.',['Gà']='Gànnïcûs:BAAALAADCggIFgAAAA==.',Ha='Hanthéa:BAAALAADCgcICwAAAA==.Hardztyle:BAAALAADCggICQAAAA==.Hardztylz:BAAALAADCgUIBAAAAA==.',He='Helizael:BAAALAAECgUIBQAAAA==.Hellhuna:BAAALAADCgcIBwAAAA==.Hellock:BAAALAADCgIIAgAAAA==.Heskan:BAAALAADCggIGQAAAA==.',Hi='Hinatâ:BAAALAADCggICAAAAA==.Hise:BAAALAAECggIAgAAAA==.Hisokà:BAAALAAECgUICgAAAA==.',Ho='Holybieru:BAAALAADCgcICAAAAA==.Holyshot:BAAALAADCgMIAgAAAA==.Hooper:BAAALAADCgUIBQAAAA==.',Hr='Hrdz:BAAALAAECgEIAgAAAA==.',Hu='Hunterminabl:BAAALAADCggICAAAAA==.',Hy='Hymlir:BAAALAAECgYICgAAAA==.Hyroye:BAACLAAFFIEFAAIMAAMIiBozBADFAAAMAAMIiBozBADFAAAsAAQKgRcAAgwACAjQJL4DAE4DAAwACAjQJL4DAE4DAAAA.',['Hæ']='Hænas:BAAALAAECgcIEgAAAA==.',['Hë']='Hëcâte:BAAALAADCgcIBwAAAA==.',['Hï']='Hïmegami:BAAALAAECgIIAwAAAA==.',Ir='Iridia:BAAALAADCgcIBwAAAA==.Irtidruid:BAAALAADCggICQABLAAFFAIIAgAEAAAAAA==.',Is='Ishtarr:BAAALAAECgYIDgAAAA==.',It='Itazura:BAAALAAECgIIAgAAAA==.',Iz='Izanamï:BAAALAADCgYICAABLAAECgMIBAAEAAAAAA==.',Ja='Jabulon:BAAALAADCgcIBwAAAA==.',Je='Jeanus:BAAALAAECgYIDgAAAA==.Jedha:BAAALAAECgcIEAAAAA==.Jessechester:BAAALAAECgEIAQAAAA==.Jesuisun:BAAALAADCgcIBwAAAA==.',Jf='Jfdmorgan:BAAALAADCggIFgAAAA==.',Ji='Jian:BAAALAAECgcIDgAAAA==.',['Jâ']='Jânelle:BAAALAAECgYIBgAAAA==.',['Jï']='Jïps:BAAALAADCggICAAAAA==.',['Jö']='Jörmoune:BAAALAAECgUIDAAAAA==.',['Jø']='Jøa:BAAALAADCgcIBwAAAA==.',Ka='Kaelthann:BAAALAADCgUIBQAAAA==.Kaimao:BAAALAAECgEIAQAAAA==.Kaleerian:BAAALAAECgMIAwAAAA==.Karm:BAAALAADCggICAAAAA==.Kartu:BAAALAADCggICAAAAA==.Karìa:BAAALAAECgcIDgAAAA==.Kavéra:BAAALAAECgcIBwABLAAECgcIEAAEAAAAAA==.Kaylia:BAAALAADCgYIBgAAAA==.Kaënnora:BAAALAADCgcIBwAAAA==.',Ke='Kementtari:BAAALAAECggIDQABLAAECggIDgAEAAAAAA==.',Kh='Khêzac:BAAALAAECgYICgAAAA==.',Ki='Kirô:BAAALAADCgEIAQABLAADCggICAAEAAAAAA==.Kiyoka:BAAALAADCgcIDgAAAA==.',Kl='Klayman:BAAALAAECgYIDwAAAA==.',Kp='Kpotejvousbz:BAAALAADCggIDAAAAA==.',Kr='Kroko:BAAALAAECgYIBwAAAA==.Kryssia:BAAALAADCgcIBAAAAA==.Krâckinou:BAAALAADCgYICQABLAAECgcIEQAEAAAAAA==.Krâcouette:BAAALAAECgQIBgABLAAECgcIEQAEAAAAAA==.Krâpule:BAAALAAECgcIEQAAAA==.Krøøm:BAAALAADCggICAAAAA==.Krùm:BAAALAAECgEIAQAAAA==.',Ku='Kukkai:BAAALAAECgYICwAAAA==.Kunn:BAAALAAECgIIAgAAAA==.',Kw='Kwokodil:BAAALAADCgcIBwAAAA==.',Ky='Kyck:BAAALAADCgQIBAAAAA==.Kynasta:BAAALAADCgYIBgAAAA==.',['Kâ']='Kârna:BAAALAAECgQICwAAAA==.Kâsstatete:BAAALAAECgYICQAAAA==.',['Kô']='Kôln:BAAALAADCgYIBgAAAA==.',['Kû']='Kûnn:BAAALAADCgcIBwAAAA==.',La='Labarquette:BAAALAAECgIIAgAAAA==.Ladaurade:BAAALAAECgMIBAAAAA==.Laminor:BAAALAAECgIIAwAAAA==.Lamuerte:BAAALAADCggIBwAAAA==.Laraskor:BAAALAAECgMIBgAAAA==.Latouf:BAAALAADCgcIBwAAAA==.',Le='Leanee:BAAALAADCggIFQAAAA==.Lechaman:BAAALAADCggICAAAAA==.Leetier:BAAALAAECgEIAQAAAA==.Lejoker:BAAALAADCgcICAAAAA==.Lensolo:BAAALAAECgcIDgAAAA==.Leodagan:BAAALAAECgEIAQAAAA==.Lepalhael:BAAALAADCgcICwAAAA==.',Li='Liau:BAAALAADCgIIAgAAAA==.Lifea:BAAALAAECgcIEwAAAA==.Lijepo:BAAALAADCggIDQAAAA==.Lileane:BAAALAADCggIEAAAAA==.Lillith:BAAALAADCgcIBwAAAA==.Linaé:BAAALAADCggIDQAAAA==.Lincolm:BAAALAADCgUIBQAAAA==.Linwan:BAAALAAECgYICQAAAA==.Lisøuille:BAAALAAECgcICgAAAA==.Littlecato:BAACLAAFFIEGAAIBAAMIQwWNAgDXAAABAAMIQwWNAgDXAAAsAAQKgRcAAgEACAj8FOIGAAgCAAEACAj8FOIGAAgCAAAA.Lizbëth:BAAALAADCggICAAAAA==.',Lo='Logitec:BAAALAADCgYIDAABLAAECgMIBQAEAAAAAA==.Lost:BAAALAAECgMIAQAAAA==.Loutus:BAAALAAECgMIBQAAAA==.',Lu='Lu:BAABLAAECoEVAAINAAgI8h+iAgDmAgANAAgI8h+iAgDmAgAAAA==.Lucifie:BAAALAAECgYIBgAAAA==.Lulù:BAAALAADCggIEwAAAA==.',Ly='Lyløü:BAAALAAECgIIAgAAAA==.Lyría:BAAALAAECgIIAgAAAA==.Lysithée:BAAALAAECgMIBgAAAA==.Lyz:BAAALAAECgcIEAAAAA==.Lyäna:BAAALAADCgYICQAAAA==.',['Lé']='Léonides:BAAALAAECgcIDAAAAA==.',['Lï']='Lïttledeath:BAAALAAECgYIDAAAAA==.',['Lô']='Lôlie:BAAALAAECgUICgAAAA==.',['Lü']='Lünakan:BAAALAAECgYIDgAAAA==.',Ma='Macova:BAAALAAECgcIEAAAAA==.Mageaufeu:BAAALAADCggICAAAAA==.Magicalgirl:BAAALAADCggICAAAAA==.Magøsi:BAAALAAECgMIBQAAAA==.Maitregims:BAAALAADCgUICQAAAA==.Malopié:BAAALAAECgYIDQAAAA==.Mangalo:BAAALAADCggICAAAAA==.Manngemortt:BAAALAAECgcICQAAAA==.Mano:BAAALAAECgcIEQAAAA==.Marlauck:BAAALAAECgUIBQAAAA==.Mathilda:BAAALAADCgUIBQAAAA==.Matsuki:BAAALAAECgYIDQAAAA==.Maxbby:BAAALAADCgEIAQAAAA==.Mayla:BAAALAAECgYICgAAAA==.Maélyss:BAAALAAECgMIAwAAAA==.',Me='Megitsune:BAAALAADCggICAAAAA==.Meillie:BAAALAAECggIDgAAAA==.Metaslave:BAAALAAECgMIBQAAAA==.',Mi='Microgiciel:BAABLAAECoEUAAIOAAgI5iLxAADiAgAOAAgI5iLxAADiAgAAAA==.Milata:BAAALAADCgMIAwAAAA==.Milkyligma:BAAALAAECgcIEAAAAA==.Mininzyl:BAAALAADCggIDwAAAA==.Mirage:BAAALAADCgcICAAAAA==.Mirida:BAAALAADCgcIBwABLAADCggIDgAEAAAAAA==.Mitchiko:BAAALAAECgUIBwAAAA==.',Mm='Mmiseasy:BAAALAAECgYIBgAAAA==.',Mo='Mollys:BAAALAADCgYIEQAAAA==.Monkyheal:BAAALAAECgcIDgAAAA==.Morkty:BAAALAADCggICAAAAA==.Mortim:BAAALAADCggICQAAAA==.Mortiork:BAAALAADCgcIBwAAAA==.Moïrra:BAAALAAECggIDAAAAA==.',My='Mythrandir:BAAALAAECgYICgAAAA==.',['Mà']='Màx:BAAALAAECgUIDwAAAA==.',['Mé']='Méliona:BAAALAADCgYIBwAAAA==.',['Më']='Mënd:BAAALAAECgQIBAAAAA==.',['Mî']='Mîdnïght:BAAALAAECgIIBAAAAA==.Mîskine:BAAALAAECgEIAQAAAA==.',['Mï']='Mïystic:BAAALAAECgEIAQAAAA==.',Na='Naeelys:BAAALAADCgMIAwAAAA==.Nainpis:BAAALAADCgYIBgAAAA==.Nakatsuki:BAAALAAECgMIBAAAAA==.Natu:BAAALAAECgYIDAAAAA==.Naturelment:BAAALAADCgcIBwAAAA==.Naëlle:BAAALAADCgUIBQAAAA==.',Ne='Neeztryh:BAAALAAECgYIBgABLAAECggIFQANAH0bAA==.Neilix:BAAALAADCggIEwAAAA==.Nethé:BAABLAAECoEXAAIPAAgIdBrwBwBlAgAPAAgIdBrwBwBlAgAAAA==.',Ni='Niinkø:BAAALAADCggIEwABLAAECgcIEAAEAAAAAA==.Ninck:BAAALAADCgUIBQABLAAECgcIEAAEAAAAAA==.Ninhpal:BAAALAADCggICAABLAAECgcIEAAEAAAAAA==.Ninkold:BAAALAAECgcIEAAAAA==.Ninku:BAAALAAECgYIBgAAAA==.Ninmk:BAAALAADCggICAABLAAECgcIEAAEAAAAAA==.',No='Nondedjou:BAAALAADCgUIBQAAAA==.Noox:BAAALAAECgQIBQAAAA==.',Nu='Nudeurgf:BAAALAADCgQIBAAAAA==.Nulos:BAAALAAECgEIAQAAAA==.',Nv='Nvs:BAAALAADCgYIBgAAAA==.',Nz='Nzeetryh:BAABLAAECoEVAAMNAAgIfRtNBACjAgANAAgIGxtNBACjAgAQAAYIhBk3NwCpAQAAAA==.',['Nà']='Nàllà:BAAALAAECgUICAAAAA==.Nàya:BAAALAADCgcIBwAAAA==.',['Nä']='Näya:BAAALAADCgcIBwAAAA==.',Og='Ogaze:BAAALAADCggIBwAAAA==.',Ok='Okailos:BAAALAADCgMIAwAAAA==.',Om='Omniscius:BAAALAAECgcIEQAAAA==.',Op='Opa:BAAALAAECgcIEAAAAA==.Optiminus:BAAALAADCggICQAAAA==.',Pa='Padduthû:BAAALAADCgQIBAAAAA==.Palongvoyant:BAAALAAECgEIAQAAAA==.Pandorya:BAAALAADCgYIBgAAAA==.',Ph='Phalarae:BAAALAADCgEIAQAAAA==.Pharenormand:BAAALAAECgUIBQABLAAECgcIDQAEAAAAAA==.',Pi='Pipounoob:BAAALAAECgYIDAAAAA==.Pipousah:BAAALAAECgYIBgAAAA==.Pititdémon:BAAALAAECgcIDQAAAA==.',Pl='Playgirls:BAAALAADCgYIBgABLAAECgMIBQAEAAAAAA==.',Po='Podie:BAAALAADCggIDwAAAA==.Poingpeste:BAAALAAECgcIDQAAAA==.Poloced:BAAALAADCggIBwAAAA==.',Pr='Prep:BAAALAADCgIIAgABLAADCgcIBwAEAAAAAA==.Prépared:BAAALAAECgYIDAAAAA==.Prøphète:BAAALAADCgMIAwAAAA==.',Pt='Ptitespattes:BAAALAAECgMIAwAAAA==.',Pu='Pudugland:BAAALAAECgcIEQAAAA==.Puffgoutpaff:BAAALAAECgYIBwAAAA==.Punchcoco:BAAALAADCgYIBgAAAA==.Punkachiotte:BAAALAAECgYIBgAAAA==.',['Pè']='Pèrefourtou:BAAALAADCgUIBQAAAA==.',['Pé']='Pétlédans:BAAALAADCgcIBwAAAA==.',['Pï']='Pïstas:BAAALAADCgEIAQAAAA==.',['Pó']='Pów:BAAALAAECgUIBQAAAA==.',['Pø']='Pøalpatine:BAAALAAECgEIAQAAAA==.Pøline:BAAALAADCgEIAQABLAADCgYIEQAEAAAAAA==.Pøwséy:BAAALAADCgcIBwABLAAECgUIBQAEAAAAAA==.',Ra='Rayako:BAAALAADCggIEAAAAA==.',Re='Retsudoe:BAAALAAECgcIBQAAAA==.Revna:BAAALAADCgIIAgABLAAECgQICwAEAAAAAA==.',Rh='Rhumambré:BAAALAAECgcIDQAAAA==.',Ri='Riô:BAAALAAECgYICgAAAA==.',Ru='Runi:BAAALAAECggIDwAAAA==.Rupan:BAAALAAECgMIBgAAAA==.',Ry='Ryv:BAAALAADCggICAAAAA==.Ryveaadh:BAABLAAECoEUAAMFAAcI6CAoBQBbAgAFAAcISx8oBQBbAgARAAUInhjsNQClAQAAAA==.Ryvheal:BAAALAAECgQIBwABLAAECgcIFAAFAOggAA==.',Sa='Saharya:BAAALAADCgUICAAAAA==.Saiøri:BAAALAAECgMIBAAAAA==.Sampho:BAAALAADCgUIBQAAAA==.Samsool:BAAALAADCggICAAAAA==.Sawsÿn:BAAALAAECgYICQAAAA==.',Sc='Scârlet:BAAALAAECgYIDQAAAA==.',Se='Sehn:BAAALAADCgUIBQABLAADCgYIBgAEAAAAAA==.Sehnn:BAAALAADCgYIBgAAAA==.Senkhöx:BAAALAADCgUIBQAAAA==.Setoxevo:BAAALAADCgYIBgAAAA==.',Sh='Shamale:BAAALAAECgEIAQAAAA==.Shamïa:BAAALAADCggICAAAAA==.Shan:BAAALAAECgQIBgAAAA==.Shaokill:BAAALAADCggICQAAAA==.Shattass:BAAALAAECgcIDQAAAA==.Shayaning:BAAALAAECgEIAQAAAA==.Shayn:BAAALAADCgEIAQABLAADCgYIBgAEAAAAAA==.Shincross:BAAALAAECgcIEAAAAA==.Shâde:BAAALAAECgMIBgAAAA==.Shïmÿ:BAAALAAECgcIBwAAAA==.',Si='Sijikü:BAAALAADCgYIDgAAAA==.Sillas:BAAALAADCggICAAAAA==.Silverwing:BAABLAAECoEXAAMBAAgIVh95AgC9AgABAAgIVh95AgC9AgACAAEI5gOsOQAyAAAAAA==.Simbur:BAAALAADCgUIBQAAAA==.',Sk='Skilløz:BAAALAADCgMIAwAAAA==.Skjörn:BAAALAADCgUIBQAAAA==.Skyzofaf:BAAALAAECgMIAgAAAA==.',So='Sovereign:BAAALAADCgIIAgAAAA==.Sovietonions:BAAALAAECgcIDAAAAA==.',Sp='Spartacusz:BAAALAAECgMIAwAAAA==.Spretsä:BAAALAAECgUIBQAAAA==.Spyrø:BAAALAAECgMIBQAAAA==.',Sq='Squallydh:BAAALAAECgMIBAAAAA==.',Ss='Sskkrrisshh:BAAALAADCgcICQABLAAECgMIBAAEAAAAAA==.',St='Stivas:BAAALAADCgQIBAAAAA==.Stonedge:BAAALAADCgcIBwAAAA==.Storms:BAAALAADCgcIDQABLAAECggIFwAPAHQaAA==.Strachers:BAAALAAECgYICQAAAA==.',Su='Sue:BAAALAADCgcIEgAAAA==.',Sw='Swark:BAAALAAECgYIDAAAAA==.',Sy='Sylveina:BAAALAAECgEIAQAAAA==.Syny:BAAALAAECgYIEAAAAA==.',Ta='Tacha:BAAALAAECgMIAwAAAA==.Tapetout:BAAALAAECgEIAQAAAA==.',Te='Tehru:BAAALAADCgcIBwAAAA==.Teilah:BAAALAADCggIGQAAAA==.Temudjin:BAAALAADCggIDgAAAA==.',Th='Theslimshady:BAAALAAECgEIAQAAAA==.',Ti='Tid:BAAALAADCgIIAgAAAA==.Tikzo:BAAALAADCggICQAAAA==.',Tl='Tlors:BAAALAAECgYIEAAAAA==.',To='Tog:BAAALAAECgcIEAAAAA==.Topdh:BAAALAAECgYIBgAAAA==.Toplexil:BAAALAADCgcIBwAAAA==.Topmage:BAAALAADCggIDwAAAA==.Topowar:BAAALAADCgYICgAAAA==.Topsham:BAAALAADCgQIBAAAAA==.Toreze:BAAALAADCggIAQAAAA==.Torsten:BAAALAADCgcIDwAAAA==.Touffue:BAAALAAECgQIBAAAAA==.',Tr='Tranxën:BAAALAAECgIIAgAAAA==.Trinetta:BAAALAADCggIEAAAAA==.Trollan:BAAALAADCgcICAAAAA==.Troolzilla:BAAALAAECgUICAAAAA==.Trophe:BAAALAAECgcICwAAAA==.',Tw='Twistere:BAAALAAECgQIBgAAAA==.',Ty='Tynäélle:BAAALAADCggICAABLAAECgUIBQAEAAAAAA==.Tyrexxéla:BAAALAADCgcIDgAAAA==.',['Té']='Téquïla:BAAALAADCggIDwAAAA==.',['Tø']='Tøøt:BAAALAAECgIIAgAAAA==.',Ug='Ugzear:BAAALAAECgYICAAAAA==.',Un='Unnilennium:BAAALAAECgMIAwAAAA==.',Ur='Uriiel:BAAALAAECgYICQAAAA==.Urÿel:BAAALAADCgcIBwAAAA==.',Ut='Utfar:BAAALAAECgEIAQAAAA==.',Va='Valtô:BAAALAAECgMIBgAAAA==.',Ve='Vegette:BAAALAAECgEIAgAAAA==.Vexx:BAAALAADCgUIBQAAAA==.',Vi='Viandehalal:BAAALAAECgYIBgAAAA==.Vidoqc:BAAALAADCgQIBAAAAA==.Viitchè:BAAALAADCgMIAwAAAA==.Violinah:BAAALAADCggIDwABLAAECgYIEAAEAAAAAA==.Virianne:BAAALAAECgcIDQAAAA==.Vitchéo:BAAALAADCgEIAQAAAA==.Vitchéà:BAAALAADCgcIBwAAAA==.Vizmisick:BAAALAAECggIEwAAAA==.',Vo='Volîno:BAAALAAECgYIBwABLAAECgYIEAAEAAAAAA==.',Vr='Vrakk:BAAALAAECgYIDAAAAA==.',Vu='Vulcan:BAAALAAECgIIAgAAAA==.',['Vå']='Vålkyrìe:BAAALAAECgIIAgAAAA==.',['Vë']='Vëldrä:BAAALAADCggIFQAAAA==.',['Vï']='Vïtché:BAAALAADCgYICAAAAA==.',['Vø']='Vødkacaramel:BAAALAADCgcICgAAAA==.',Wa='Watdafock:BAAALAADCgQIBAAAAA==.',Wh='Whok:BAAALAAECgMIAwAAAA==.',Wi='Widex:BAAALAADCgUIBQABLAAECgQIBgAEAAAAAA==.Willump:BAAALAAECgcIDQAAAA==.Wirac:BAAALAADCggICAAAAA==.Wize:BAAALAADCgMIBAAAAA==.',Wy='Wylthirsk:BAAALAAECgIIAgAAAA==.',['Wø']='Wølixxss:BAAALAADCgcICQAAAA==.Wølïxss:BAAALAADCggICAABLAAECgcIDQAEAAAAAA==.',Xe='Xenolord:BAAALAAECgMIAwAAAA==.',['Xã']='Xãnyã:BAAALAADCgcIDgAAAA==.',Ya='Yats:BAAALAAECgMIBAAAAA==.',Ye='Yelladin:BAAALAADCggIDAABLAAECgYICQAEAAAAAA==.Yellowcats:BAAALAAECgQIAwAAAA==.Yellowcoq:BAAALAAECgYICQAAAA==.Yepapii:BAAALAADCgUIBQAAAA==.',Yg='Yggdk:BAAALAAECggIDQAAAA==.',Yo='Yos:BAAALAAECgEIAQABLAAECgMIBAAEAAAAAA==.',Yr='Yrelle:BAAALAADCggICAAAAA==.',Yu='Yuyiy:BAAALAADCggICAAAAA==.',['Yö']='Yöshï:BAAALAADCggICAAAAA==.',['Yû']='Yûma:BAAALAAECgUIBwAAAA==.',Ze='Zelâd:BAAALAAECgMIBgAAAA==.Zephir:BAAALAADCgQIBAAAAA==.',Zo='Zozophlette:BAAALAADCgcIBwAAAA==.Zozototem:BAAALAADCgEIAQAAAA==.',Zy='Zypox:BAAALAAECgMIAwAAAA==.',['Zå']='Zåmel:BAAALAADCgEIAQAAAA==.',['Zé']='Zébulon:BAAALAAECgEIAQAAAA==.Zéphira:BAAALAAECgUICAAAAA==.',['Zø']='Zøkushin:BAAALAADCggICAAAAA==.',['Ãt']='Ãtrus:BAAALAADCgcIBwAAAA==.',['Äy']='Äyesâpïk:BAAALAADCgIIAgAAAA==.',['Æc']='Æchètpakofïs:BAAALAADCgcIBwAAAA==.',['Éf']='Éfeng:BAAALAAECgYICAAAAA==.',['Él']='Éli:BAAALAAECgQIBAAAAA==.',['Ér']='Éracles:BAAALAAECgMIAwAAAA==.',['És']='Éscanor:BAAALAAECgMIBAAAAA==.',['Ën']='Ënëlya:BAAALAAECgYIDgAAAA==.',['Ðr']='Ðrok:BAAALAAECgMIAwAAAA==.',['Ôt']='Ôtetamain:BAAALAADCggIDwAAAA==.',['Üb']='Übstark:BAAALAAECgMIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end