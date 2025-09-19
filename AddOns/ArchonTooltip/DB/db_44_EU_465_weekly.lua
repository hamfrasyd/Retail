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
 local lookup = {'Warlock-Destruction','Mage-Arcane','Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','Paladin-Holy','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Frost','Priest-Shadow','Warrior-Fury','Priest-Holy','Warrior-Protection','Shaman-Elemental','Druid-Balance','Hunter-Marksmanship','Monk-Mistweaver','Rogue-Assassination','Shaman-Restoration','Paladin-Protection','Druid-Restoration','Mage-Fire','Hunter-BeastMastery','Warrior-Arms',}; local provider = {region='EU',realm='Taerar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ad='Adela:BAAALAADCggIFgABLAAECggIFgABAHogAA==.',Ag='Agira:BAAALAAECgYICAAAAA==.',Ah='Ahsoka:BAAALAAECgcIEQAAAA==.',Al='Alanihfanboi:BAABLAAECoEUAAICAAgIthnqFQBzAgACAAgIthnqFQBzAgABLAAFFAYIDQABAHUdAA==.Alukard:BAAALAAECgMIAwAAAA==.',Am='Amali:BAAALAADCgMIAwABLAAECggIBwADAAAAAA==.',An='Anoubis:BAABLAAECoEVAAQEAAgIxh7aCQAtAgAEAAYILh/aCQAtAgABAAYIThr+GwDvAQAFAAMI4hXmFADvAAAAAA==.Antheaa:BAAALAAECgYICAAAAA==.',Ar='Artiè:BAAALAAECgIIAgAAAA==.',As='Asa:BAABLAAECoEVAAIGAAgIBhqYCABPAgAGAAgIBhqYCABPAgAAAA==.Ashokar:BAAALAADCgcIDgAAAA==.Aszaera:BAAALAAECgYIBgAAAA==.',Aw='Awi:BAAALAAECgYIBgAAAA==.',Ax='Axero:BAAALAADCgcIBwAAAA==.',Az='Azelia:BAAALAAECgQIBQABLAAECggIGAAHAMoTAA==.Azeoríth:BAAALAAECgUICQAAAA==.',Ba='Babyyodah:BAAALAAFFAIIBAAAAA==.Banosh:BAAALAAECgYIDAABLAAECggIDgADAAAAAA==.Batushka:BAAALAADCgcIBwAAAA==.',Be='Beatmymeat:BAABLAAECoEUAAMIAAgI0BdECAAuAgAIAAgI0BdECAAuAgAJAAIIgQRziQBnAAABLAAFFAYIEAAKAJIjAA==.Beifahrer:BAAALAADCgcIBwAAAA==.Belaal:BAAALAADCggICAAAAA==.',Bi='Bibedibu:BAAALAADCgcIBwAAAA==.',Bl='Blakkii:BAACLAAFFIEKAAILAAUIpBmPAADpAQALAAUIpBmPAADpAQAsAAQKgRYAAgsACAiRJZUBAGcDAAsACAiRJZUBAGcDAAAA.Blakkiidh:BAAALAAECgYIDAABLAAFFAUICgALAKQZAA==.Bloomtales:BAAALAAECgEIAQAAAA==.Bluebärry:BAAALAAECgMIBAAAAA==.',Bo='Bonk:BAAALAAECgYIBgAAAA==.Boran:BAAALAADCgcICgAAAA==.',Br='Bradwarden:BAAALAADCggIDAAAAA==.Brewmaster:BAAALAADCgcIBwAAAA==.Brosita:BAAALAADCgMIAwABLAAECggIFgAMACwlAA==.Brunhílde:BAAALAAECggICAAAAA==.',Bu='Burle:BAAALAAECgMIBQAAAA==.',Ca='Caesario:BAAALAAECgIIAgAAAA==.Calamitas:BAAALAAFFAMIBAAAAA==.Catman:BAAALAAECgEIAQAAAA==.',Ce='Century:BAAALAADCgcIDQAAAA==.Cezar:BAAALAAECgUICgAAAA==.',Ch='Chain:BAAALAADCggIDgAAAA==.Channingtotm:BAAALAADCggIEAABLAAECgYIBgADAAAAAA==.Chaozstraza:BAAALAAFFAIIAwAAAA==.',Ci='Ci:BAAALAAECgcICwAAAA==.Cinni:BAAALAAECgMIAwAAAA==.',Cl='Clarity:BAAALAADCggICAAAAA==.Cloryne:BAAALAADCgcIBwAAAA==.',Cr='Crescentia:BAAALAADCgcIDgAAAA==.',['Cé']='Cénturio:BAAALAAECgUICAAAAA==.',['Cí']='Cínderella:BAAALAADCgEIAQAAAA==.',Da='Dallisham:BAAALAAECgcIEwAAAA==.Darior:BAAALAADCgcICgABLAAECgcIDgADAAAAAA==.',De='Deamion:BAAALAAECgEIAQAAAA==.Deeprumay:BAAALAAECgYICgAAAA==.Deichen:BAABLAAECoEWAAINAAgIhBOzDwC3AQANAAgIhBOzDwC3AQAAAA==.Deltopia:BAAALAAECgEIAQAAAA==.Devilknight:BAAALAAECgMIBAAAAA==.Devkev:BAAALAADCgYIBgAAAA==.Devourdragon:BAAALAAECgEIAQAAAA==.Dexor:BAAALAAECgcIDwAAAQ==.Dexoui:BAAALAADCggIDwABLAAECgcIDwADAAAAAA==.',Dh='Dhracyr:BAAALAAECgMIAwAAAA==.',Di='Dilemma:BAAALAADCggIEAAAAA==.Disc:BAAALAAECgMIAwAAAA==.Divineles:BAAALAADCgEIAQAAAA==.',Do='Dotti:BAAALAADCggIEAAAAA==.',Dr='Dracthyrke:BAAALAAECgYIDAAAAA==.Dreamerzz:BAAALAAECgYIBgABLAAFFAQIBgACAGsSAA==.',Dy='Dys:BAAALAAECgQIBAAAAA==.Dysteria:BAAALAAECgIIAgABLAAECgQIBAADAAAAAA==.',Ec='Eclipsis:BAAALAADCgYIBgABLAAECgUICwADAAAAAA==.',El='Elemegon:BAAALAAECgYICwAAAA==.Elexys:BAAALAAECgEIAQAAAA==.Elianor:BAAALAADCgQIBAAAAA==.Elly:BAAALAAECgQIBwAAAA==.Elunariya:BAAALAAECgEIAQAAAA==.',En='Ende:BAACLAAFFIEGAAIOAAIIGyOiBADUAAAOAAIIGyOiBADUAAAsAAQKgRQAAg4ACAgjJM8EACUDAA4ACAgjJM8EACUDAAAA.Endworld:BAABLAAECoEWAAIPAAgI/Rl/DABuAgAPAAgI/Rl/DABuAgABLAAFFAIIBgAOABsjAA==.Enternameplx:BAAALAAECgYIDQAAAA==.',Fa='Failerella:BAAALAAECgYIDwAAAA==.Falria:BAAALAAECgMIAwAAAA==.Favera:BAAALAAECgEIAQAAAA==.',Fe='Feljunkie:BAAALAAECgYIDgAAAA==.',Fi='Fineshyt:BAAALAADCgEIAQAAAA==.',Fl='Floria:BAAALAAECgMIBAAAAA==.',Fo='Foxyroxx:BAAALAAECgYIBwAAAA==.',Fr='Freaqqz:BAAALAAECgMIAwAAAA==.Freyja:BAAALAAECggICAAAAA==.',Fu='Futter:BAACLAAFFIENAAIOAAYIuiAfAABxAgAOAAYIuiAfAABxAgAsAAQKgRUAAg4ACAhCJrQAAIIDAA4ACAhCJrQAAIIDAAAA.Futterkaboom:BAAALAAFFAIIBAAAAA==.',['Fí']='Fíght:BAAALAAECgcIDgAAAA==.',Ga='Garzok:BAAALAAECgIIAwAAAA==.',Ge='Gefailix:BAAALAADCggICQAAAA==.Gesuchristie:BAAALAAECggICAAAAA==.',Gh='Gharex:BAACLAAFFIEHAAIQAAQIZiGGAACxAQAQAAQIZiGGAACxAQAsAAQKgRYAAhAACAgFJokAAGkDABAACAgFJokAAGkDAAAA.',Gi='Gigachad:BAAALAAECggIDQAAAA==.Giggasebb:BAACLAAFFIENAAIRAAYI1BUcAAAsAgARAAYI1BUcAAAsAgAsAAQKgRQAAhEACAiWI34BACMDABEACAiWI34BACMDAAAA.',Go='Goresoul:BAAALAAECgYICgABLAAFFAIIAwADAAAAAA==.Gorgooth:BAAALAAECgIIAQAAAA==.Gorthax:BAAALAAECgEIAQABLAAECggIFgAJAAkiAA==.Gorynn:BAAALAAFFAIIAwAAAQ==.Gotta:BAAALAADCgYIBgAAAA==.',Gy='Gyros:BAAALAAECgYIBgAAAA==.',Ha='Happyfeet:BAAALAADCggIDgAAAA==.',He='Hellidan:BAAALAADCgYIBgAAAA==.',Hi='Hinna:BAAALAAECgYICQAAAA==.',Ho='Hogenkobold:BAAALAAECgMIAwAAAA==.Holydevil:BAAALAAECgcIEAAAAA==.Holymacaroni:BAAALAADCgIIAgAAAA==.Holymilk:BAAALAADCggIDwAAAA==.Hopplahasi:BAACLAAFFIENAAMBAAYIdR1YAABWAgABAAYIdR1YAABWAgAEAAIIWBWEBACtAAAsAAQKgRQABAEACAjFIyYEACgDAAEACAjFIyYEACgDAAUABAiDHKsOAFkBAAQAAQgrHW9PAFEAAAAA.',Hy='Hypatia:BAAALAAECgMIAwAAAA==.',['Hâ']='Hâvock:BAAALAADCggIDAAAAA==.',['Hö']='Hörnie:BAAALAADCgcIBwAAAA==.',Ik='Ikkebinrogue:BAABLAAECoEZAAISAAgIvRI3EgAWAgASAAgIvRI3EgAWAgAAAA==.Iksdehqt:BAABLAAECoEVAAISAAgIcxkaDgBRAgASAAgIcxkaDgBRAgAAAA==.',Il='Ilyzia:BAABLAAECoEYAAMHAAgIyhMBIQASAgAHAAgIyhMBIQASAgAGAAQIiBM+IQAhAQAAAA==.',In='Ingtar:BAAALAAECggICAAAAA==.Intox:BAACLAAFFIEFAAIOAAMIURZPBgCvAAAOAAMIURZPBgCvAAAsAAQKgRYAAg4ACAghJEQCAFoDAA4ACAghJEQCAFoDAAAA.',Iw='Iwy:BAAALAAECggICwAAAA==.',Ji='Ji:BAAALAADCgEIAQABLAADCggIDwADAAAAAA==.Jiuna:BAAALAADCggIFQAAAA==.',Ju='Juvenile:BAAALAADCgcIEwABLAAECgUICgADAAAAAA==.',Ka='Kaleshmal:BAAALAAECgYIDwAAAA==.Kazzek:BAAALAAECgQIBgAAAA==.',Ke='Kefiin:BAAALAAECgMIBgAAAA==.Kelari:BAABLAAECoEWAAIJAAgICSKlBwAGAwAJAAgICSKlBwAGAwAAAA==.',Ki='Kibatachi:BAAALAADCggICAABLAAECgMIAwADAAAAAA==.Kimberlyhart:BAAALAAECggIBwAAAA==.',Kl='Kloppiwhoppi:BAAALAADCgcIBwAAAA==.',Ko='Kobe:BAACLAAFFIEGAAITAAIIxh6qBQC2AAATAAIIxh6qBQC2AAAsAAQKgRYAAhMACAiKHwwHAKsCABMACAiKHwwHAKsCAAAA.Koda:BAAALAADCggICAAAAA==.',Kr='Kräutereuter:BAAALAAECgcIDwABLAAFFAUICgAKABwgAA==.',Ku='Kubo:BAAALAAECgMIAwABLAAECggIFgAJAAkiAA==.',Ky='Kyson:BAACLAAFFIENAAIUAAYIaRcZAAAOAgAUAAYIaRcZAAAOAgAsAAQKgRUAAhQACAjwID4DANoCABQACAjwID4DANoCAAAA.Kysu:BAAALAADCgcIBwAAAA==.Kyula:BAAALAAECgIIAgABLAAECgcIDgADAAAAAA==.',La='Lakota:BAAALAAECgIIAgAAAA==.',Le='Leodragnos:BAAALAADCggICAABLAAECgMIAwADAAAAAA==.Leonardru:BAAALAAECgMIAwAAAA==.',Li='Libero:BAAALAAECgYICAAAAA==.Lileth:BAAALAAECgcIBwAAAA==.Linniah:BAAALAADCggIDwAAAA==.',Lo='Loctly:BAAALAADCggIEwAAAA==.Loráná:BAAALAADCgYIBgAAAA==.',Lu='Lukevoked:BAAALAAECgQIBwAAAA==.Lumiron:BAAALAAECgMIBAAAAA==.Lunaréth:BAAALAAECgIIAgAAAA==.Lunera:BAAALAAECgEIAQABLAAECgQIBwADAAAAAA==.Lutzzy:BAAALAADCgYIBgABLAAECgYICAADAAAAAA==.Luzifér:BAAALAAECgMIBAABLAAECgYIDgADAAAAAA==.Luzinde:BAAALAAECggIEQAAAA==.',Ly='Lykarì:BAAALAADCgQICAAAAA==.Lynarìah:BAAALAAECggICAABLAAECggICAADAAAAAA==.Lynthara:BAAALAAECgQIBwAAAA==.Lyrai:BAAALAADCgcIBwABLAAECgIIAgADAAAAAA==.Lysara:BAAALAADCgYICQABLAAECggIFgAJAAkiAA==.',['Lí']='Líleth:BAAALAAECgYICQABLAAECgcIBwADAAAAAA==.',Ma='Maey:BAAALAADCggIFQAAAA==.Magodestroyo:BAAALAAFFAEIAQAAAA==.Maniayaya:BAAALAADCgEIAQABLAAFFAYIDQABAL4VAA==.Maniuwu:BAACLAAFFIENAAMBAAYIvhUeAQDRAQABAAUIiRIeAQDRAQAEAAIIuSJZAQDHAAAsAAQKgRYABAQACAhWJgoKACoCAAEABgjfI1IPAHUCAAQABQizJgoKACoCAAUAAwh1ILQRACQBAAAA.Marieparie:BAAALAAECggICAAAAA==.',Me='Melissa:BAAALAADCgEIAQAAAA==.Messalina:BAAALAAECgYIDwAAAA==.Mexro:BAAALAADCgYIBgAAAA==.',Mi='Milkaa:BAAALAADCggICAAAAA==.Miniclap:BAAALAAECgMIAwABLAAECggICAADAAAAAA==.Minxibinxi:BAAALAAECgcICAAAAA==.Mirezr:BAABLAAECoEUAAISAAgIwhUgDABvAgASAAgIwhUgDABvAgAAAA==.Mirezw:BAABLAAECoEWAAILAAgIeCX7AQBfAwALAAgIeCX7AQBfAwAAAA==.Mistdevil:BAAALAADCggICAAAAA==.',Mo='Moodoo:BAAALAAECgYIDAAAAA==.Moodoodh:BAAALAADCgYIBgABLAAECgYIDAADAAAAAA==.Morgenkaffee:BAAALAADCggIDgAAAA==.',My='Myanis:BAACLAAFFIEGAAIPAAII0hN3BQCiAAAPAAII0hN3BQCiAAAsAAQKgRQAAw8ACAg6Hr4KAI4CAA8ACAg6Hr4KAI4CABUAAQi4ChJfADMAAAAA.Mythmaster:BAECLAAFFIENAAIGAAYIGCYEAACwAgAGAAYIGCYEAACwAgAsAAQKgRYAAgYACAgXIm8CAOMCAAYACAgXIm8CAOMCAAAA.',['Mî']='Mîrano:BAAALAADCgUIBgAAAA==.',Na='Nalria:BAAALAAECgMIAwAAAA==.Nayru:BAAALAADCgMIAwAAAA==.',Ne='Nehemia:BAAALAAECgUIBgAAAA==.Nekrogrunz:BAAALAADCgcIBwABLAAECggIBwADAAAAAA==.Nelima:BAAALAAECgMIAwAAAA==.Nerien:BAAALAADCgYIBgAAAA==.Newgate:BAAALAADCggICAAAAA==.',Ni='Niicetotem:BAAALAADCggIEgAAAA==.',No='Nomaam:BAAALAADCgcICAAAAA==.',Nu='Nukemage:BAACLAAFFIELAAMCAAYIXhkJAQDZAQACAAUIPRsJAQDZAQAWAAEIARAJAgBfAAAsAAQKgRUAAgIACAgzJv4BAFsDAAIACAgzJv4BAFsDAAAA.',['Né']='Nécron:BAAALAADCgcICAAAAA==.',On='Onwu:BAACLAAFFIEGAAICAAQIaxIVAgBaAQACAAQIaxIVAgBaAQAsAAQKgRgAAgIACAhHJIUDAEMDAAIACAhHJIUDAEMDAAAA.',Ot='Otis:BAAALAADCgYIBgAAAA==.',Pa='Paisho:BAAALAAECgcIBwAAAA==.Paper:BAAALAAECggIDgAAAA==.Parasoma:BAAALAAECgYIDQAAAA==.Pastinake:BAAALAAECgMIAwAAAA==.Pawpatrol:BAAALAADCggICAAAAA==.',Pe='Peevi:BAAALAADCggICAAAAA==.Penumbra:BAAALAADCgMIAwAAAA==.Peppa:BAAALAADCggIDwAAAA==.',Po='Poggerhontas:BAACLAAFFIENAAMQAAYITBxPAADoAQAQAAUI1R1PAADoAQAXAAEInRRiCwBcAAAsAAQKgRYAAxAACAi1IRsFAPACABAACAi1IRsFAPACABcAAQj6HIxyAFEAAAAA.Poipoipoi:BAACLAAFFIEQAAMKAAYIkiMJAAClAgAKAAYIkiMJAAClAgAMAAEI3AiXDwBMAAAsAAQKgRgAAgoACAhjJqUAAIEDAAoACAhjJqUAAIEDAAAA.Pompom:BAAALAAECgEIAgABLAAECgMIAwADAAAAAA==.Portales:BAAALAADCggICAAAAA==.Powermage:BAABLAAECoEVAAICAAgIKBe2GwBDAgACAAgIKBe2GwBDAgAAAA==.',Pr='Prahios:BAAALAAECgEIAQAAAA==.',Pu='Pu:BAAALAADCggICAAAAA==.Purity:BAABLAAECoEVAAIMAAcIAB6oEQA9AgAMAAcIAB6oEQA9AgAAAA==.',['Pô']='Pô:BAAALAAECgYICAAAAA==.',Qu='Quaderzucker:BAAALAADCgUIBQAAAA==.Quyncmepls:BAAALAAECgcIEQABLAAFFAUICQAIAFUTAA==.',Ra='Radix:BAAALAAECgYICAAAAA==.',Rd='Rdruidezclap:BAEALAAECgIIAgABLAAFFAYIDQAGABgmAA==.',Re='Ret:BAAALAADCgcIBwABLAAECggIDgADAAAAAA==.Rey:BAAALAADCggIDgAAAA==.',Rh='Rhya:BAAALAAECgUICQAAAA==.',Ri='Risopala:BAAALAADCgYIBgAAAA==.',Ro='Rockz:BAAALAAECgcIEAAAAA==.Rosalii:BAAALAADCggIFgAAAA==.',Ru='Ruvina:BAAALAADCggICAAAAA==.',['Rö']='Röllmeister:BAAALAAECgYICAAAAA==.',Sa='Sable:BAAALAADCgYICQABLAAECgYIBgADAAAAAA==.Sadge:BAAALAADCggICAAAAA==.',Sc='Schimmelkäse:BAAALAAFFAEIAQAAAA==.Schmatzie:BAAALAAECgUICgAAAA==.Schwarrie:BAAALAADCggICAAAAA==.',Se='Seb:BAAALAADCggICAAAAA==.Sebbqq:BAACLAAFFIEMAAIKAAYIjhRNAABOAgAKAAYIjhRNAABOAgAsAAQKgRYAAgoACAhPJMYDADADAAoACAhPJMYDADADAAAA.',Sh='Shabbab:BAAALAADCgcIBwAAAA==.Shaddâr:BAAALAAECgYICQAAAA==.Shade:BAAALAAECgYIBgAAAA==.Shadowlulqt:BAECLAAFFIEGAAIMAAIIsCLcBQDFAAAMAAIIsCLcBQDFAAAsAAQKgRQAAwwACAhnHMIOAF0CAAwACAhnHMIOAF0CAAoABAg/HhYqAGEBAAEsAAUUBggNAAYAGCYA.Shinokishi:BAAALAAECggICAAAAA==.Shiver:BAAALAAECgYIBgAAAA==.Shortilla:BAAALAADCggICAAAAA==.Shykitten:BAAALAAECggIEQAAAA==.',Si='Siari:BAAALAAECggICAAAAA==.',Sm='Smallo:BAAALAAFFAEIAQAAAA==.',Sn='Snaptrap:BAAALAADCggICAAAAA==.',Sp='Spekuhlatius:BAAALAAECgMIAwAAAA==.',St='Stearoid:BAAALAADCgYIBgAAAA==.Stevebruder:BAABLAAECoEWAAIMAAgILCWyAABqAwAMAAgILCWyAABqAwAAAA==.',Su='Sukkubus:BAAALAAECgIIAgAAAA==.Sultan:BAAALAAECgMIAwAAAA==.Supername:BAABLAAECoEUAAIJAAgIfRq7FABzAgAJAAgIfRq7FABzAgAAAA==.',['Sî']='Sîlenceroguê:BAAALAADCgcIBwAAAA==.',Ta='Talai:BAAALAAFFAIIBAAAAA==.Talaib:BAACLAAFFIELAAIMAAUIaA9uAAC9AQAMAAUIaA9uAAC9AQAsAAQKgRQAAgwACAi6H+AGAM0CAAwACAi6H+AGAM0CAAAA.Tandris:BAAALAAECgMIAwAAAA==.Tanyrra:BAAALAADCgQIBAAAAA==.Tarii:BAAALAAECggIDQAAAA==.Tasatulos:BAAALAADCggICAABLAAECgQIBgADAAAAAA==.',Te='Telira:BAAALAAECgUICwAAAA==.Telrok:BAAALAAECgEIAQAAAA==.Temlin:BAAALAAECgMIAwAAAA==.Teuton:BAAALAAECgQIBwAAAA==.',Th='Thalinor:BAAALAADCggIFQABLAAECggIFgAJAAkiAA==.Theodar:BAAALAAECgEIAQAAAA==.Thulu:BAACLAAFFIEJAAMIAAUIVRMfAACCAQAIAAQIAhcfAACCAQAJAAIIJw9JCwCmAAAsAAQKgRYAAwgACAh/JYAEAJwCAAgABgikJYAEAJwCAAkABwgiJC8SAIsCAAAA.',Ti='Tiata:BAAALAAECgcIDgAAAA==.',To='Todie:BAABLAAECoEWAAIHAAgIgyEaCAALAwAHAAgIgyEaCAALAwAAAA==.Tohrú:BAAALAAECgMIAwAAAA==.Tokki:BAAALAADCggIDgAAAA==.Totemtommy:BAAALAAECgQIBQAAAA==.',Tr='Treffsicher:BAABLAAECoElAAIXAAcIXQ6VLgCfAQAXAAcIXQ6VLgCfAQAAAA==.',Ts='Tschigerillo:BAABLAAECoEUAAIYAAgIxB2TAQC5AgAYAAgIxB2TAQC5AgABLAAFFAYIDAAKAI4UAA==.',Tv='Tvknòchèn:BAAALAAECgUICQAAAA==.',Va='Vaeliz:BAAALAAECgQICAAAAA==.Vaeniel:BAAALAADCgcIBwAAAA==.Vampirherz:BAAALAADCggIDQAAAA==.',Ve='Verathiell:BAAALAAECgIIAwAAAA==.Verflucht:BAAALAAECgUIBQAAAA==.Verrottete:BAAALAAECgYICAAAAA==.Vesrin:BAAALAAECgcIEgAAAA==.',Vi='Vivace:BAAALAAECgQIBQAAAA==.',Vo='Voidlady:BAAALAADCgYIBgAAAA==.Volltroll:BAAALAADCgcIDgAAAA==.',['Ví']='Víolett:BAAALAAECgcICwAAAA==.',Wi='Windspiel:BAABLAAECoEVAAIMAAgIoRMxFgARAgAMAAgIoRMxFgARAgAAAA==.',Wo='Wolverknight:BAACLAAFFIEKAAIKAAUIHCB0AAANAgAKAAUIHCB0AAANAgAsAAQKgRQAAgoACAiMJQwCAFcDAAoACAiMJQwCAFcDAAAA.Woses:BAAALAAECgMIAwAAAA==.',Xh='Xhandril:BAAALAAECgMIBAAAAA==.',Xo='Xoljun:BAAALAADCggIDwAAAA==.',Xu='Xuu:BAAALAAECgYIDAAAAQ==.',Ya='Yadana:BAAALAAECgMIAwAAAA==.',Ye='Yeji:BAAALAADCgYIBwAAAA==.',Yi='Yin:BAAALAAECgYIBgAAAA==.',Ys='Ysaria:BAAALAAECgMIAwAAAA==.',Yu='Yunasneak:BAAALAAFFAMIAwAAAA==.Yunawar:BAAALAAFFAIIAgABLAAFFAMIAwADAAAAAA==.',Yv='Yvenne:BAAALAADCggIDwABLAAECggIFgABAHogAA==.',Za='Zaia:BAABLAAECoEUAAIJAAgIkBSQHQAwAgAJAAgIkBSQHQAwAgABLAAECggIGAAHAMoTAA==.Zarona:BAAALAADCggIEAAAAA==.',Ze='Zeratul:BAAALAADCgYIBgAAAA==.Zeronos:BAAALAAECgEIAQAAAA==.Zerrac:BAAALAADCggIEAAAAA==.Zeyzan:BAAALAAECgQIBAAAAA==.',Zi='Ziehrandor:BAAALAAFFAIIAgAAAA==.Zirkuskanone:BAAALAAECgYIDAAAAA==.',Zo='Zomboss:BAAALAAECgEIAQAAAA==.',Zu='Zulsaframano:BAAALAAECggICgAAAA==.',Zw='Zwombie:BAAALAAECgEIAQAAAA==.Zwoses:BAAALAAECggIEgAAAA==.',Zx='Zx:BAAALAADCgMIAwAAAA==.',Zy='Zyko:BAAALAAECgMIAwAAAA==.Zynthoaa:BAAALAAECgYICgAAAA==.Zyx:BAAALAAECgcIDgAAAA==.',['Ær']='Ærthas:BAAALAAECgUIBQAAAA==.',['Æz']='Æzrael:BAAALAADCgIIAgAAAA==.',['Ín']='Ínnos:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end