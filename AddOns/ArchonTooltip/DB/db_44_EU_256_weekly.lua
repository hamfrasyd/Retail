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
 local lookup = {'Shaman-Restoration','Mage-Arcane','Monk-Windwalker','Paladin-Retribution','Unknown-Unknown','Warlock-Demonology','Paladin-Protection','Druid-Feral','Shaman-Elemental','Priest-Shadow','Priest-Discipline','Priest-Holy','DemonHunter-Havoc','Monk-Brewmaster','Rogue-Outlaw','Hunter-BeastMastery','Druid-Balance','Warrior-Protection','Shaman-Enhancement','Druid-Guardian','Warrior-Fury','DeathKnight-Frost','Evoker-Devastation','Paladin-Holy','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Hunter-Survival','DemonHunter-Vengeance','Mage-Frost','Mage-Fire','Evoker-Preservation',}; local provider = {region='EU',realm='Aszune',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abshifter:BAAALAAECgYIEwAAAA==.Abwilliams:BAAALAADCgQIBAAAAA==.',Ac='Acirel:BAAALAAECggIAgAAAA==.',Ad='Adromeq:BAAALAAECgYICwAAAA==.',Af='Afirmacja:BAAALAAECgYICQAAAA==.',Ag='Agility:BAAALAAECgYIEgAAAA==.',Ah='Ahotnjiks:BAAALAADCgcIBwAAAA==.',Ak='Akizs:BAABLAAECoEWAAIBAAcIOhi2JgDuAQABAAcIOhi2JgDuAQAAAA==.',Al='Aldorex:BAAALAAECgEIAQAAAA==.Alfenster:BAAALAAECgYIDwAAAA==.Alkometrs:BAAALAAECgcIDQAAAA==.Alocacoc:BAAALAADCgcIBwAAAA==.Aluidariis:BAAALAADCggICAAAAA==.Alyssar:BAAALAAECgcIEAAAAA==.',Am='Ambriosa:BAAALAAECgYIEQAAAA==.Ammonium:BAAALAADCgcIBwAAAA==.',An='Anatastarte:BAAALAAECgYIDwAAAA==.Angtoria:BAAALAADCgYIBgAAAA==.Aniko:BAAALAAECgUIBwAAAA==.Anisconjurer:BAABLAAECoEVAAICAAgIEhdzKwAhAgACAAgIEhdzKwAhAgAAAA==.Anisvore:BAAALAAECgYIEgABLAAECggIFQACABIXAA==.Anthonysala:BAAALAADCgcIEQAAAA==.',Ar='Arantir:BAAALAAECgYIDgAAAA==.Arda:BAAALAADCggIEwABLAAECggIGAADAN8iAA==.Arisen:BAAALAADCgYIBgAAAA==.Aristah:BAABLAAECoEYAAIBAAgIQxLVMAC8AQABAAgIQxLVMAC8AQAAAA==.Arîel:BAAALAAECgMIAgAAAA==.',As='Asdertis:BAABLAAECoEUAAIEAAcIgxwzKgAuAgAEAAcIgxwzKgAuAgAAAA==.Asdertpala:BAAALAADCggICAAAAA==.Asibia:BAAALAADCgcIBwAAAA==.Assy:BAAALAAECgIIAgAAAA==.Astoord:BAAALAAECggIDwAAAA==.Astrid:BAAALAADCgIIBAAAAA==.',At='Ati:BAAALAAECgEIAQAAAA==.',Az='Azarrack:BAAALAAECgYIEAAAAA==.Azeisha:BAAALAAECgIIAwABLAAECgYIBwAFAAAAAA==.Azzania:BAAALAAECgYIDwAAAA==.',Ba='Baarrd:BAAALAADCggIDQABLAAECgIIAgAFAAAAAA==.Babaad:BAAALAADCggIBgAAAA==.',Be='Bearwalker:BAAALAADCggIEwAAAA==.Beatemgood:BAAALAAECgMIBgAAAA==.Bekon:BAAALAAFFAIIBAAAAA==.Bekons:BAAALAAFFAIIBAAAAA==.Bekonz:BAAALAADCggIEAAAAA==.Belzebubben:BAAALAADCggICAAAAA==.',Bh='Bhutas:BAABLAAECoEYAAIGAAgIzwkVGQDKAQAGAAgIzwkVGQDKAQAAAA==.',Bi='Biezoknis:BAABLAAECoEXAAIHAAcI5Q9NGgBIAQAHAAcI5Q9NGgBIAQAAAA==.',Bl='Blastygosa:BAAALAADCggICAAAAA==.Bloom:BAAALAAECgIIAgAAAA==.Blyatovski:BAAALAADCggIDgAAAA==.',Bo='Bobawolf:BAAALAAECgEIAQAAAA==.Boh:BAAALAAECgYICAAAAA==.Bohémian:BAABLAAECoEWAAIIAAcIFxruCgAWAgAIAAcIFxruCgAWAgAAAA==.Borgmester:BAAALAADCgIIAgAAAA==.Bosh:BAAALAADCgcIFAAAAA==.Bottlebee:BAABLAAECoEXAAMBAAgI1Q4JOwCQAQABAAgI1Q4JOwCQAQAJAAYImwYBSQAlAQAAAA==.',Br='Brickabrac:BAAALAADCgcIDQAAAA==.',Bu='Bumbin:BAAALAAECggIEwAAAA==.Bumbuls:BAAALAAECgIIAgAAAA==.',Bx='Bx:BAAALAAECgcIBwAAAA==.',Ca='Caliban:BAAALAADCggICAAAAA==.Calid:BAABLAAECoEWAAIKAAcIMiOHDADEAgAKAAcIMiOHDADEAgAAAA==.Carñal:BAABLAAECoEjAAICAAgIxh9/EgDMAgACAAgIxh9/EgDMAgAAAA==.',Ce='Celeb:BAAALAADCgMIAwABLAAECggIEgAFAAAAAA==.Cellagon:BAABLAAECoEVAAQLAAcI1Ay3CwBQAQALAAYIpw23CwBQAQAMAAMItwp9XgCcAAAKAAEIugQ4ZQA1AAAAAA==.Ceryn:BAAALAAECgYIDwAAAA==.',Ch='Charala:BAABLAAECoEUAAINAAgIEA+INQDvAQANAAgIEA+INQDvAQAAAA==.Chavilina:BAAALAADCgIIAgABLAAECggIFAANABAPAA==.Chiddi:BAAALAADCggIDAAAAA==.Chinoiserie:BAAALAAECgUIBQAAAA==.Choronzon:BAAALAAECgIIAgAAAA==.Chumule:BAAALAADCgcIDQAAAA==.Chuprest:BAAALAADCgMIAwAAAA==.Churgie:BAAALAADCgcIDAAAAA==.',Ci='Cidonijs:BAAALAAECgQIAQABLAAFFAIIAgAFAAAAAA==.',Co='Cooljustice:BAAALAAECgMIAwAAAA==.Corrupted:BAAALAAECgMIAwAAAA==.',Cr='Creepyspy:BAAALAAECgYICwAAAA==.Cromwell:BAAALAAECgIIAgAAAA==.Crystylol:BAAALAADCgcICAAAAA==.',Cu='Curar:BAAALAAECgYIBgABLAAECggIGAADAN8iAA==.Cuthalion:BAAALAAECggIDAAAAA==.',['Cá']='Cárnal:BAAALAAECgIIAgABLAAECggIIwACAMYfAA==.',['Có']='Cóffeebeanz:BAAALAAECgYIDgAAAA==.',Da='Daemoni:BAAALAAECgEIAQABLAAECggIHAAJAFcXAA==.Dagren:BAAALAADCggIFQAAAA==.Damnson:BAABLAAECoEXAAIOAAcIlA5IFABsAQAOAAcIlA5IFABsAQAAAA==.Dangerguy:BAAALAAECgcIEQAAAA==.Danni:BAAALAADCggIDAAAAA==.Danwell:BAAALAADCggICAAAAA==.Darit:BAABLAAECoEUAAIIAAcIJBaUDAD1AQAIAAcIJBaUDAD1AQAAAA==.Darkdindon:BAAALAADCgMIAwAAAA==.Darkhearth:BAAALAAECgYICwAAAA==.',De='Deadbeast:BAAALAADCgMIAwABLAAECggIGAAPANMXAA==.Deafknight:BAAALAAECgcIEwAAAA==.Deathecus:BAAALAAECgYIDAABLAAECgcIGAAFAAAAAQ==.Deathglare:BAAALAAECgcIDAAAAA==.Deixares:BAAALAAECgYICQAAAA==.Demonslide:BAAALAAECgYIEQAAAA==.Demontrigger:BAAALAAFFAIIAgAAAA==.Dezi:BAAALAAECggIDgAAAA==.',Dj='Djbobo:BAAALAADCggIEAAAAA==.',Dk='Dkruz:BAAALAAECgEIAQAAAA==.Dktäx:BAAALAAECgYIDwAAAA==.',Dr='Dryftwood:BAAALAADCgEIAQAAAA==.',Du='Dubbz:BAAALAAECgIIAgAAAA==.Duckie:BAABLAAECoEVAAIQAAYIlRpqOwCdAQAQAAYIlRpqOwCdAQAAAA==.',Ei='Eithel:BAAALAADCgcIDAAAAA==.',El='Elandra:BAAALAAECgMIAwAAAA==.Elenate:BAAALAAECgEIAQAAAA==.Elidhu:BAAALAADCggIFAAAAA==.Eline:BAAALAADCgEIAQAAAA==.Eliviotter:BAABLAAECoEWAAIRAAgIKiCZCgDJAgARAAgIKiCZCgDJAgAAAA==.Elizaveta:BAAALAAECggIEwAAAA==.Eluneadore:BAAALAAECgcIEQAAAA==.Elunera:BAAALAAECgMIBQAAAA==.Elusïve:BAAALAAECggIDwAAAA==.',Em='Emcix:BAAALAAECgEIAQAAAA==.',En='Enkoz:BAAALAADCggICAABLAAECgMIBQAFAAAAAA==.Enotrig:BAAALAAECgYIDwAAAA==.',Ex='Exceed:BAAALAAECgIIAgABLAAECgcIFgAKADIjAA==.',Fe='Feanoris:BAAALAAECgYIDQAAAA==.Feysti:BAAALAADCgcICgAAAA==.',Fi='Fikkie:BAAALAAECggIEgAAAA==.Finch:BAAALAADCggIEAABLAAECggIFgABALUcAA==.Finchfly:BAAALAAECggIDAABLAAECggIFgABALUcAA==.Finchpanda:BAABLAAECoEWAAMBAAcItRxOGABBAgABAAcItRxOGABBAgAJAAMINRN2VgDBAAAAAA==.Fistusèér:BAAALAAECgMIAwAAAA==.',Fl='Flarn:BAAALAAECgMIAwABLAAECgMIBQAFAAAAAA==.',Fo='Foror:BAAALAAECgIIAgAAAA==.Foxxzorr:BAAALAAECgcIDQAAAA==.',Fr='Fragolina:BAAALAAECgIIAgAAAA==.',Fu='Fugue:BAAALAAECgIIAgAAAA==.',['Fæ']='Færdæ:BAABLAAECoEWAAISAAcICxtaDwAgAgASAAcICxtaDwAgAgAAAA==.',['Fú']='Fúbárr:BAAALAAECgMIAwAAAA==.',Ga='Ganilf:BAAALAADCgcIBwABLAAECgMIBQAFAAAAAA==.Gargamelz:BAABLAAECoEUAAIMAAcIYxDfMACWAQAMAAcIYxDfMACWAQAAAA==.Garyx:BAABLAAECoEYAAITAAgIPhX0BQBMAgATAAgIPhX0BQBMAgAAAA==.Gatovs:BAAALAAECgIIAgAAAA==.',Ge='Georgé:BAABLAAECoEYAAIPAAgI0xcSAwBtAgAPAAgI0xcSAwBtAgAAAA==.Gerppo:BAABLAAECoEcAAIJAAgIVxccFwBeAgAJAAgIVxccFwBeAgAAAA==.',Gi='Giirtoone:BAAALAAECgYICgAAAA==.Girtonnen:BAAALAAECgcIDQAAAA==.',Gl='Glox:BAABLAAECoEVAAIUAAgIxg+/CQBtAQAUAAgIxg+/CQBtAQAAAA==.',Go='Gojos:BAAALAADCgcIBwAAAA==.Gokû:BAAALAADCgEIAQAAAA==.Golimir:BAAALAADCggIDwAAAA==.',Gr='Gregorb:BAAALAAECgYICgAAAA==.',Gu='Guf:BAAALAADCggICAAAAA==.Gulldan:BAAALAAECgIIAgAAAA==.Guojing:BAAALAAECgQIBgAAAA==.',Gz='Gzus:BAAALAAECgMIAwAAAA==.',['Gó']='Gódivá:BAAALAAECgYICwAAAA==.',Ha='Haaleon:BAAALAAECgcIEgAAAA==.Halston:BAABLAAECoEUAAIVAAcI+xqYHwAcAgAVAAcI+xqYHwAcAgAAAA==.Harmony:BAAALAADCggICAAAAA==.Harveyprice:BAAALAAECgMIAwAAAA==.Hasa:BAAALAADCgYIBgAAAA==.',He='Helkaz:BAAALAAECgcIDQAAAA==.Helsong:BAAALAAECgEIAQAAAA==.',Hi='Hinkreborn:BAABLAAECoEYAAIWAAgIEhLENwD2AQAWAAgIEhLENwD2AQAAAA==.Hiva:BAABLAAECoEXAAIXAAgIfCOtAgBGAwAXAAgIfCOtAgBGAwAAAA==.',Ho='Holyfinch:BAAALAADCggIDAABLAAECggIFgABALUcAA==.Holygyatt:BAAALAADCggICAAAAA==.Hotter:BAAALAAECgMIAwAAAA==.',Hu='Hufflegruff:BAAALAAECgYIEQABLAAECgcIDAAFAAAAAA==.Humaneftw:BAAALAADCgQIBAAAAA==.Hundell:BAAALAAECgcIDAAAAA==.',Il='Ileya:BAAALAAECgIIAgAAAA==.Ilior:BAAALAADCggIDwAAAA==.Illior:BAABLAAECoEaAAMEAAgIwhHHPADgAQAEAAcIAhTHPADgAQAYAAIIfALPRQAsAAAAAA==.',In='Influenza:BAAALAAECgIIAgAAAA==.Inori:BAAALAAECgIIAgAAAA==.',Is='Iskandarr:BAAALAAECgUICAAAAA==.',Ja='Jaaniits:BAAALAAECgYICgAAAA==.Janorin:BAAALAADCgYIDAAAAA==.',Je='Jeyer:BAAALAAECgEIAQAAAA==.Jeyeri:BAAALAADCgYIDAABLAAECgEIAQAFAAAAAA==.Jeyers:BAAALAADCgYIDgABLAAECgEIAQAFAAAAAA==.',Ji='Jimthecheat:BAAALAADCggIDQAAAA==.Jingshen:BAABLAAECoEYAAIZAAgI+hitCQBUAgAZAAgI+hitCQBUAgAAAA==.Jinra:BAAALAAECgEIAQABLAAECggILAANAHEmAA==.',Jn='Jnsorange:BAABLAAECoEWAAMaAAgIjAkLNgClAQAaAAgIjAkLNgClAQAbAAQIKgNwHwCgAAAAAA==.',Jo='Joukahainen:BAAALAAECgYIDgAAAA==.',Ju='Jusa:BAAALAAECgMIBQABLAAECggIGgAXADAaAA==.Justífied:BAAALAADCggICgABLAAECggIGAAPANMXAA==.Juzandlis:BAABLAAECoEXAAMQAAgICB2sEgCbAgAQAAgItRusEgCbAgAcAAYIrRg1BwC6AQAAAA==.',['Jé']='Jéppe:BAABLAAECoEUAAMMAAcIghcqIwDpAQAMAAcIghcqIwDpAQAKAAMIGwLbXgBPAAAAAA==.',Ka='Kalgoth:BAAALAAECgMIAwAAAA==.Kartupelis:BAAALAAECgUIBQABLAAFFAIIAgAFAAAAAA==.Kay:BAABLAAECoEbAAIdAAgIuCY+AACLAwAdAAgIuCY+AACLAwAAAA==.Kaytress:BAAALAADCgMIBAAAAA==.',Ke='Kefir:BAAALAADCggICAABLAAECggIFwAQAAgdAA==.Kentang:BAAALAAECgYICQABLAAECgcIDgAFAAAAAA==.Kentong:BAAALAAECgcIDgAAAA==.Kerazael:BAAALAADCggIDwAAAA==.Keyæra:BAAALAAECgUIBQABLAAECgcIFgASAAsbAA==.',Kh='Khiko:BAAALAAECgYIBgAAAA==.',Ki='Kickdbucket:BAAALAAECgYIDwAAAA==.Kilzz:BAAALAADCgcIDQAAAA==.Kiruce:BAAALAADCggICAABLAAECgMIAwAFAAAAAA==.Kitty:BAACLAAFFIENAAIZAAUIeRXzAACyAQAZAAUIeRXzAACyAQAsAAQKgR8AAhkACAhKI/sBACcDABkACAhKI/sBACcDAAAA.',Ko='Korgoroth:BAAALAAECgcIGAAAAQ==.',Kr='Krovn:BAAALAAFFAIIAgAAAA==.Krovnmage:BAAALAADCgcIBwABLAAFFAIIAgAFAAAAAA==.Krovnpala:BAAALAAECgQIAwABLAAFFAIIAgAFAAAAAA==.',Ku='Kubii:BAAALAADCggIFQABLAAECgYIDAAFAAAAAA==.Kuubbii:BAAALAAECgYIDAAAAA==.',Ky='Kywol:BAAALAAECgYIEAAAAA==.',['Kê']='Kênpachi:BAAALAAECgcIDgAAAA==.',La='Labero:BAAALAAECgIIAgAAAA==.Laulund:BAAALAAECgIIAgAAAA==.Lavigne:BAAALAADCgcIBwABLAAECgEIAQAFAAAAAA==.Laylith:BAAALAADCgEIAQAAAA==.',Le='Leafy:BAAALAAECgMIAwAAAA==.Leetzorz:BAABLAAECoEWAAISAAcIxxtSDwAhAgASAAcIxxtSDwAhAgAAAA==.Leocore:BAAALAAECgYICwAAAA==.',Li='Lidonna:BAAALAAECgQIBAAAAA==.Liessa:BAAALAADCggICAAAAA==.Lightsunai:BAAALAADCggICAAAAA==.Lisica:BAAALAADCggIIAAAAA==.Litterbox:BAAALAAECgYIDwAAAA==.',Lj='Ljutause:BAAALAAECgcICAABLAAFFAIIAgAFAAAAAA==.',Lo='Locas:BAAALAAECgMIAwAAAA==.Lothoal:BAAALAADCgUIBQABLAAECgMIBQAFAAAAAA==.',Lu='Luckyman:BAAALAAECgIIBQAAAA==.Lumia:BAAALAAECgYIDgAAAA==.Lutzé:BAAALAAECgcIDgABLAAECgcIFgAIABcaAA==.',Ly='Lyijypulkka:BAAALAAECgYIBgABLAAECggIGgAXADAaAA==.',Ma='Madfub:BAAALAADCgcIBwABLAAECgcIFwACACUcAA==.Madnezs:BAAALAAECgIIAgAAAA==.Magicfinch:BAAALAADCggIFgABLAAECggIFgABALUcAA==.Magicfub:BAABLAAECoEXAAICAAcIJRygIwBPAgACAAcIJRygIwBPAgAAAA==.Magicwizzle:BAABLAAECoEYAAIeAAgIJxjyDABUAgAeAAgIJxjyDABUAgAAAA==.Mattaki:BAABLAAECoEYAAMCAAgI4x6fGQCUAgACAAgI4x6fGQCUAgAfAAEIewZZFgAhAAAAAA==.Mayaa:BAABLAAECoEWAAIcAAgI0AkABgDgAQAcAAgI0AkABgDgAQAAAA==.',Mc='Mctart:BAAALAADCggICAAAAA==.',Me='Meg:BAAALAAECgcIEwAAAA==.Mehito:BAAALAAECgYIDwAAAA==.Melhoot:BAAALAAECgQIBAABLAAECggIGAADAN8iAA==.Mellane:BAABLAAECoEYAAMDAAgI3yJpBgDSAgADAAcICSNpBgDSAgAZAAUI8RS6GwA1AQAAAA==.Melocutes:BAAALAADCggIEQAAAA==.Melphas:BAAALAADCggIGAAAAA==.Melshoots:BAAALAADCggIEgAAAA==.',Mh='Mhow:BAAALAADCgcICAAAAA==.',Mi='Minka:BAAALAADCggICAAAAA==.Mirona:BAAALAADCgYIBwAAAA==.Mithrala:BAAALAAECgcIEwAAAA==.',Mo='Monkalicious:BAAALAADCggICAAAAA==.Monkerinoo:BAAALAADCgUIBQABLAAFFAIIAgAFAAAAAA==.Monkosh:BAAALAAECgYIDgAAAA==.Moretotems:BAAALAADCgcIBwABLAAECgcIDgAFAAAAAA==.',Mu='Murksontagh:BAAALAADCggIHAAAAA==.Murkyshadow:BAAALAADCggIFQAAAA==.',My='Myohmy:BAAALAAECgEIAQAAAA==.',['Mí']='Míca:BAABLAAECoEYAAIYAAgI/CCnAgD2AgAYAAgI/CCnAgD2AgAAAA==.',['Mî']='Mîsts:BAAALAAECgcIDgAAAA==.',Na='Nacho:BAAALAADCggIEQAAAA==.Narcis:BAAALAAECgQIBAAAAA==.Narcisdh:BAABLAAECoEYAAINAAgILwwfRQCxAQANAAgILwwfRQCxAQAAAA==.Narcisdk:BAAALAADCgcIBwAAAA==.Narciskungfu:BAAALAAECgYIBgAAAA==.Narciswarr:BAAALAAECgYICAAAAA==.Naszgull:BAAALAAECgQIBAAAAA==.Nate:BAAALAADCgYIBgAAAA==.Naílah:BAAALAADCgcIBwAAAA==.',Ne='Nerobasta:BAAALAADCggIDwAAAA==.Neroli:BAAALAADCgUIBQAAAA==.Nethergray:BAABLAAECoEWAAIHAAcIoB9PCABmAgAHAAcIoB9PCABmAgAAAA==.Netiirais:BAABLAAECoEbAAIKAAcI5CCeEQCGAgAKAAcI5CCeEQCGAgAAAA==.',Ni='Nightlily:BAAALAAECgIIAgAAAA==.Nikita:BAAALAAECgMIBgAAAA==.Niue:BAAALAADCggIEgAAAA==.',No='Nogruni:BAAALAADCggICAAAAA==.Nonlv:BAAALAAFFAIIAgAAAA==.Nordmoon:BAAALAAECgEIAQAAAA==.',Nu='Nugar:BAAALAAECgEIAQAAAA==.',Ny='Nyxira:BAAALAAECgYIDgAAAA==.Nyzza:BAAALAAECggIBwAAAA==.',['Ná']='Náaved:BAABLAAECoEYAAIQAAgIhhS7IQAhAgAQAAgIhhS7IQAhAgAAAA==.',Ol='Oldways:BAAALAADCgcIBwAAAA==.',Om='Omnipollo:BAAALAAECgEIAQAAAA==.',Pa='Palalinda:BAAALAAECgEIAQAAAA==.Palefang:BAAALAAECgcIDAAAAA==.Palownator:BAAALAAECgUICgAAAA==.Pandaps:BAAALAADCgcIBwABLAADCggIDgAFAAAAAA==.Pargen:BAAALAADCggIFAABLAAECggIGAADAN8iAA==.Pawsofflight:BAAALAAECgYIEAAAAA==.Pawstruction:BAAALAAECgYIDQABLAAECgYIEAAFAAAAAA==.',Pe='Pedomednieks:BAABLAAECoEXAAINAAcI6hxIIABfAgANAAcI6hxIIABfAgAAAA==.Pekainitis:BAAALAAFFAIIAgAAAA==.Pennyback:BAAALAAECgEIAQAAAA==.',Ph='Phíl:BAABLAAECoEWAAIXAAcImBNeHAC8AQAXAAcImBNeHAC8AQAAAA==.',Pi='Piepie:BAAALAADCgcIDAAAAA==.Piruids:BAAALAADCggIEAAAAA==.Pix:BAAALAAECgIIAwAAAA==.',Pl='Plogen:BAAALAADCgcIBwAAAA==.Ploogen:BAAALAADCgcIBwAAAA==.Ploops:BAAALAAECggICAAAAA==.Plufs:BAAALAADCggIEAABLAAECgMIBQAFAAAAAA==.',Po='Poppylisciou:BAAALAADCggIDwABLAAECggIFAANABAPAA==.Potat:BAAALAAECgYIDwABLAAECggIGAACAOMeAA==.',Ps='Psygore:BAAALAAECgMIAwABLAAECgMIBAAFAAAAAA==.Psylef:BAAALAAECgMIBAAAAA==.',Pu='Punishers:BAAALAAECgYIBgAAAA==.Pusygourmet:BAAALAAECgQIBAAAAA==.',Py='Pyo:BAAALAAECgIIAgAAAA==.',Qw='Qwaanh:BAAALAAECgcIEwAAAA==.',Ra='Ragemen:BAAALAADCggIGAAAAA==.Rakhish:BAAALAADCggICAAAAA==.Rastlyn:BAABLAAECoEUAAIJAAcI+AkaNwCJAQAJAAcI+AkaNwCJAQAAAA==.Raventalon:BAABLAAECoEWAAIOAAcIeQ4gFQBfAQAOAAcIeQ4gFQBfAQAAAA==.Raziél:BAAALAADCggICAAAAA==.',Re='Reanimacija:BAAALAAFFAIIAgAAAA==.Repena:BAAALAAECgcICQAAAA==.Resnaaberta:BAAALAADCgcICQABLAAFFAIIAgAFAAAAAA==.Rettoz:BAAALAADCggIDgAAAA==.Rexdraconis:BAAALAAECgMIAwAAAA==.',Ri='Riáz:BAAALAADCggIDwAAAA==.',Ro='Robotnic:BAAALAADCggIDwABLAAECgMIBQAFAAAAAA==.Roller:BAAALAAECgcIEAAAAA==.',Ru='Runeforge:BAAALAADCgIIAgAAAA==.',Rw='Rwaawr:BAAALAAECggIDgAAAA==.',Sa='Saintslime:BAAALAAECgMIAwABLAAECggIFwABANUOAA==.Sakaro:BAAALAADCgMIAwAAAA==.',Sc='Scadi:BAAALAADCgYIBgAAAA==.Scalene:BAAALAADCgYIBgABLAAECggIGAADAN8iAA==.Schrödy:BAAALAADCggIDwAAAA==.',Se='Seffir:BAAALAAECgcIEQAAAA==.Sekerpare:BAAALAADCgcIDQAAAA==.Selûne:BAAALAADCgcIBwAAAA==.Sennahoj:BAAALAADCggICAABLAAECggIGgAXADAaAA==.Senzubean:BAAALAAECgYICQAAAA==.',Sh='Shaandra:BAAALAAECgIIAgAAAA==.Shabydh:BAAALAAECgYIBgAAAA==.Shadowazz:BAAALAADCggICAABLAAECgYIDwAFAAAAAA==.Shagrat:BAAALAAECgYICQAAAA==.Shalltear:BAAALAAECgYIDwAAAA==.Shambolic:BAAALAADCgYIBgAAAA==.Shellshócked:BAAALAADCgcIBwAAAA==.Shinki:BAAALAADCggIDQAAAA==.Shiuraz:BAAALAAECgYIBwAAAA==.Shálatar:BAABLAAECoEYAAQGAAgInSM6BADQAgAGAAcI7CI6BADQAgAaAAUIkR7YNACrAQAbAAMI5iQ+EwAvAQAAAA==.Shálysra:BAAALAADCggICAAAAA==.',Si='Siderte:BAAALAAECgEIAQAAAA==.Sieru:BAABLAAECoEYAAMaAAgI0SF7CgD3AgAaAAgIoiB7CgD3AgAGAAYIkh8bEwD6AQAAAA==.Sif:BAAALAADCggIFQAAAA==.Siipivihta:BAABLAAECoEaAAMXAAgIMBp/DACPAgAXAAgIMBp/DACPAgAgAAMIeQJqHwBuAAAAAA==.Silex:BAAALAAECgYICwAAAA==.Singularity:BAAALAADCgcIBwAAAA==.Sipmark:BAAALAAECgYICAAAAA==.',Sl='Slarva:BAAALAADCgUIBQAAAA==.',Sn='Sneeze:BAAALAAECgEIAQAAAA==.Snowfairy:BAAALAAECgIIAgAAAA==.',So='Sodapop:BAAALAADCgcICAAAAA==.Solin:BAAALAADCgcIDAAAAA==.Solnight:BAAALAADCgMIAwAAAA==.Soulsun:BAAALAAECgMIAwAAAA==.',Sp='Spirittfox:BAAALAADCggIDQAAAA==.Spook:BAAALAAECggICAAAAA==.',Sr='Sraaz:BAAALAAECgYIDwAAAA==.',St='Stabhion:BAAALAAECgYIEAAAAA==.Standruid:BAAALAADCggIEQAAAA==.Stanpaladin:BAAALAAECgIIAgAAAA==.Stinkßomb:BAAALAADCggICAAAAA==.Storgut:BAAALAAECgEIAQAAAA==.Stro:BAAALAAECgIIAgAAAA==.',Su='Sundrove:BAAALAAECgYIDwAAAA==.Susitar:BAAALAAECgIIAgAAAA==.',Sy='Syllen:BAAALAAECgYIEAAAAA==.Synnila:BAAALAADCggICQAAAA==.',Ta='Tatyhanna:BAAALAAECgQIBAAAAA==.',Te='Telerion:BAAALAADCggIDgAAAA==.Tenok:BAAALAAECgYIBgAAAA==.Teronar:BAAALAADCgYICQAAAA==.',Th='Thatdragon:BAABLAAECoEYAAIXAAgIxhYmEgA5AgAXAAgIxhYmEgA5AgAAAA==.Thatdwarf:BAAALAADCggIDwABLAAECggIGAAXAMYWAA==.Thatworgen:BAAALAADCgMIAwABLAAECggIGAAXAMYWAA==.',To='Tororo:BAAALAAECgcIBwAAAA==.',Tr='Trakulismonk:BAAALAAECgcIEAAAAA==.Traya:BAAALAAECgEIAQAAAA==.Tregioba:BAAALAAECgEIAgAAAA==.Treisijs:BAABLAAECoEQAAQaAAcI5B0dMADFAQAaAAYICBwdMADFAQAGAAMI1B4kOgAEAQAbAAEIxyC6KABfAAABLAAFFAIIAgAFAAAAAA==.Treysijs:BAAALAAFFAIIAgAAAA==.Triger:BAAALAADCgYIBgABLAAECgEIAQAFAAAAAA==.Trustyrusty:BAABLAAECoEUAAISAAgImB5kBgDJAgASAAgImB5kBgDJAgAAAA==.',Ts='Tsunarashi:BAAALAADCgYIBgAAAA==.',Tu='Tunchi:BAAALAADCggIDwAAAA==.',Tw='Twiddler:BAAALAADCgIIAwAAAA==.Twista:BAAALAADCgUIBQAAAA==.',Ty='Typhön:BAAALAADCggICQAAAA==.',['Té']='Térokk:BAAALAADCggICwAAAA==.',Ub='Ubiquinol:BAAALAAECggIBwAAAA==.',Ud='Udenslidejs:BAAALAADCgcIBwAAAA==.',Un='Unreflected:BAAALAAECgEIAQAAAA==.',Va='Vaash:BAAALAAECgMIAwAAAA==.Valdeko:BAAALAAECgYICQAAAA==.Valkyri:BAAALAADCgIIAgAAAA==.Vanguard:BAAALAAECgYIDwAAAA==.Vanida:BAAALAAECgYIDwAAAA==.Varaz:BAAALAAECgUIBgABLAAECgYIBwAFAAAAAA==.Varetna:BAAALAADCggIDgAAAA==.',Vb='Vbj:BAAALAAECgMIBwAAAA==.',Ve='Velcro:BAAALAAECgIIAwAAAA==.Venfica:BAAALAADCggIDgABLAAECgMIBQAFAAAAAA==.Vengerr:BAAALAADCgQIBAAAAA==.',Vi='Vidzemnieks:BAAALAADCggIEAAAAA==.Vilath:BAAALAADCgQIBQAAAA==.',Vm='Vmnbgh:BAAALAADCgEIAQAAAA==.',Vo='Vojd:BAAALAADCggIDgABLAAECgMIBQAFAAAAAA==.Voltenc:BAABLAAECoEaAAIOAAgIDiFUAwAEAwAOAAgIDiFUAwAEAwAAAA==.Vorador:BAAALAAFFAIIAgAAAA==.',Vu='Vuurvliegje:BAAALAADCgQIBAABLAAECgYICwAFAAAAAA==.',Vy='Vythera:BAAALAAECgcIEAABLAAECgcIEAAFAAAAAA==.',Wa='Wale:BAAALAAECgYIDgAAAA==.',We='Weywood:BAABLAAECoEYAAIRAAgIEh+0CQDaAgARAAgIEh+0CQDaAgAAAA==.',Wi='Wily:BAAALAADCggICAAAAA==.Wisdomness:BAABLAAECoEWAAQGAAcICxPYIgCKAQAaAAcI5Q1DOQCVAQAGAAYIphHYIgCKAQAbAAEI2goINAA4AAAAAA==.',Wo='Wochi:BAAALAAECgYIDwAAAA==.Worglock:BAAALAADCggIEwAAAA==.',Wr='Wraarw:BAAALAAECgYIBgAAAA==.',Wy='Wynteria:BAAALAAECgcIDgAAAA==.',Xe='Xere:BAAALAADCgcIDAAAAA==.',Xi='Xianga:BAAALAAECgEIAQAAAA==.',Xo='Xona:BAAALAADCgcIBwABLAAECgYIDgAFAAAAAA==.',Yr='Yrisius:BAABLAAECoEXAAIMAAgIwQqEMQCTAQAMAAgIwQqEMQCTAQAAAA==.',Za='Zann:BAAALAAECgYICgAAAA==.Zarvájh:BAAALAAECgQIBAAAAA==.Zaryx:BAABLAAECoEVAAIQAAYIBhvALQDdAQAQAAYIBhvALQDdAQAAAA==.Zatama:BAAALAAECgcIDAAAAA==.',Ze='Zende:BAAALAAECgYIDwAAAA==.Zetharel:BAAALAAECgYIEQABLAAECgYIFQAQAAYbAA==.',Zi='Zivjuzupa:BAAALAAECgYIDwAAAA==.',Zo='Zosma:BAAALAADCgYIBgAAAA==.',['Zâ']='Zârvâjh:BAAALAAECgEIAQAAAA==.',['Òw']='Òwó:BAAALAAECgYICgABLAAECggIEwAFAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end