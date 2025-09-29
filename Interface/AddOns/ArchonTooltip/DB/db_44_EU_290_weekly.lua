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
 local lookup = {'Monk-Mistweaver','Evoker-Preservation','Evoker-Devastation','Paladin-Retribution','Unknown-Unknown','Mage-Frost','Rogue-Assassination','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Warrior-Fury','DemonHunter-Vengeance','Druid-Restoration','Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Warrior-Protection','DemonHunter-Havoc','Rogue-Outlaw','Shaman-Restoration','Hunter-Survival','Druid-Guardian','Druid-Feral','Priest-Shadow','Priest-Holy',}; local provider = {region='EU',realm='Emeriss',name='EU',type='weekly',zone=44,date='2025-09-22',data={Af='Afleyushka:BAABLAAECoEaAAIBAAgIhSM+BgDmAgABAAgIhSM+BgDmAgAAAA==.',Ai='Airuna:BAAALAAECgYIBgAAAA==.',Al='Alekc:BAAALAADCgQIBAAAAA==.Aleksi:BAAALAAECgQIBAAAAA==.Alfeya:BAACLAAFFIEeAAMCAAcI8CMZAAAFAwACAAcI8CMZAAAFAwADAAEIzgDaGwA9AAAsAAQKgRkAAwIACAhLJk4AAHkDAAIACAhLJk4AAHkDAAMAAwj+EXpLAKEAAAAA.Allayan:BAAALAADCggIIgAAAA==.Aluriël:BAAALAADCgYIBgAAAA==.Alvico:BAAALAADCgEIAQAAAA==.',Am='Amity:BAAALAADCggICAAAAA==.',An='Angelight:BAABLAAECoEfAAIEAAgI7hsyJwCqAgAEAAgI7hsyJwCqAgAAAA==.Anthracite:BAAALAAECgEIAgAAAA==.Antoaneta:BAAALAADCgQIBAAAAA==.Anty:BAAALAADCggICAAAAA==.Anu:BAAALAAECggIEQABLAAECgYICwAFAAAAAA==.',Ar='Artharian:BAAALAADCgEIAQAAAA==.',As='Ashwing:BAAALAAECgcIDAAAAA==.',Aw='Awleya:BAAALAAFFAMIAwAAAA==.',Ba='Baldrun:BAAALAADCggIBAAAAA==.',Bi='Bixtonim:BAAALAADCgcIBwAAAA==.',Bl='Bloodkael:BAAALAAECgYIBgAAAA==.Bläze:BAAALAADCgcIBwAAAA==.',Bo='Bolg:BAAALAAECgYICgAAAA==.Boog:BAAALAAECggICAAAAA==.Booghy:BAAALAAECggICwAAAA==.Bourge:BAAALAAECgcIDQAAAA==.Bouvet:BAAALAAECgMIBgABLAAECgcIHQAGAI0VAA==.',Br='Brotemaikata:BAAALAAECgYICAAAAA==.Brummie:BAAALAAECgMIAwAAAA==.',Bu='Bunkhy:BAAALAADCgUIBQAAAA==.',Ca='Cantbstopped:BAAALAADCgYIBgAAAA==.',Ch='Chazyb:BAAALAAECgYICwAAAA==.Chyhiro:BAAALAAECgYICgABLAAFFAIIBgAHAIkfAA==.',Ci='Cilera:BAABLAAECoEvAAMIAAgI5SEOFwDUAgAIAAgI0yAOFwDUAgAJAAYIaiKpHQBcAgAAAA==.',Cl='Clión:BAAALAAECgYIDAABLAAECgcIIwAJANchAA==.',Co='Cosmick:BAAALAADCggIEAAAAA==.Cottillion:BAAALAAECgQIBwAAAA==.',Cr='Crestfall:BAAALAAECggICAAAAA==.Crivian:BAAALAAECggICAAAAA==.Crow:BAAALAAECgYICwAAAA==.',Da='Dairblade:BAAALAAECgYIDAAAAA==.Daircane:BAABLAAECoEdAAIKAAcINx9kMQBiAgAKAAcINx9kMQBiAgAAAA==.Darkzen:BAAALAAECgEIAQAAAA==.Darthos:BAAALAAECgUIBgAAAA==.Dawnseeker:BAAALAAECgcIBwAAAA==.',De='Deathlayer:BAAALAAECgIIAgAAAA==.Demolator:BAAALAAECgEIAQAAAA==.Derpsi:BAABLAAECoEeAAILAAgIcR4tFwDYAgALAAgIcR4tFwDYAgAAAA==.',Di='Diaolos:BAABLAAECoEdAAIMAAgI7w2UIABvAQAMAAgI7w2UIABvAQAAAA==.Dirtyegg:BAAALAADCgMIAwAAAA==.Disrupt:BAABLAAECoEkAAIMAAcInBh7FQDoAQAMAAcInBh7FQDoAQAAAA==.',Dn='Dny:BAAALAADCgUIBwAAAA==.',Do='Dojacat:BAAALAAECgYIBgAAAA==.',Dr='Dragosia:BAAALAADCggICwAAAA==.Drgndeeznutz:BAAALAAECggIEAAAAA==.Druidro:BAACLAAFFIEGAAINAAIIIRCyHwCJAAANAAIIIRCyHwCJAAAsAAQKgSEAAg0ACAizH4AMANQCAA0ACAizH4AMANQCAAAA.',El='Elathaï:BAACLAAFFIEGAAIHAAIIiR9uDQC4AAAHAAIIiR9uDQC4AAAsAAQKgSUAAwcACAg8IVsFAB0DAAcACAg8IVsFAB0DAA4AAwi6FC4yALEAAAAA.Elektras:BAAALAAECgUIBQAAAA==.Elenera:BAAALAAECgUICQAAAA==.Elizer:BAAALAAFFAIIAgAAAA==.',Em='Emby:BAAALAADCgcICgAAAA==.Empoly:BAABLAAECoEXAAIEAAYIDx0PbwDUAQAEAAYIDx0PbwDUAQAAAA==.',Et='Etlar:BAAALAAECgYICgAAAA==.',Fi='Fibrex:BAAALAAECgIIAgAAAA==.',Fj='Fjollegoej:BAAALAADCgcIDAAAAA==.',Fo='Form:BAABLAAECoEeAAINAAcImBp5KgAFAgANAAcImBp5KgAFAgAAAA==.Fortitude:BAAALAAECgIIAwAAAA==.',Ge='Genjistyle:BAAALAADCgcICQAAAA==.Getdunked:BAABLAAECoEcAAMIAAgIUiDfFgDVAgAIAAgI/R/fFgDVAgAJAAcITRXNPgCdAQAAAA==.',Gi='Gimin:BAAALAAECgQIBgAAAA==.',Gl='Gladiss:BAABLAAECoEaAAMPAAgIMw6PYwCKAQAPAAgIMw6PYwCKAQAQAAEIxAA1kAAEAAAAAA==.Glorificus:BAAALAADCggICAAAAA==.Gloww:BAABLAAECoEWAAINAAgI1hmuIQAzAgANAAgI1hmuIQAzAgAAAA==.',Gn='Gná:BAAALAADCgcIBwAAAA==.',Gr='Gragas:BAAALAAECgYIDAAAAA==.Gravitys:BAAALAAECgcIBwAAAA==.Gravìtý:BAAALAADCgMIAwAAAA==.Greta:BAAALAADCgcIBwAAAA==.Grimoire:BAAALAAECgQIBAAAAA==.',Gu='Gullmnr:BAAALAAECggICQAAAA==.',Ha='Harishhjjaja:BAAALAAECgYIEwAAAA==.',He='Helland:BAABLAAECoEdAAIGAAcIjRWNIgDfAQAGAAcIjRWNIgDfAQAAAA==.Hellsing:BAAALAADCggICAAAAA==.',Hh='Hh:BAAALAADCgIIBAABLAAFFAIIBwARAAMdAA==.',Hu='Hurfan:BAABLAAECoEXAAIEAAYISCKGOgBcAgAEAAYISCKGOgBcAgAAAA==.',Ib='Ibwa:BAABLAAECoEiAAMQAAgIch51CwCUAgAQAAcIXSB1CwCUAgAPAAQIPBTRjwAQAQAAAA==.',Id='Idkhöwtoplay:BAAALAAECgYICwAAAA==.',Ig='Igrith:BAAALAAECggIBgAAAA==.',It='Ithilid:BAAALAAECgQIAgAAAA==.',Ja='Jana:BAAALAAECgQIBQAAAA==.Jarle:BAAALAAECgYIDAAAAA==.',Jo='Jorii:BAAALAAECgIIAgAAAA==.',Ka='Kali:BAAALAADCgcIBwAAAA==.Kawny:BAAALAAECgMIAwAAAA==.Kawnywl:BAAALAAECgMIAgAAAA==.',Ke='Kersh:BAAALAAECgMIAwABLAAECggIIAASAHQhAA==.',Ki='Kilkov:BAAALAADCgMIAwAAAA==.',Ku='Kurnela:BAAALAAECgIIAgAAAA==.',Ky='Kyladrieth:BAAALAAECgYIBgAAAA==.',Le='Leewanglong:BAAALAADCgcICAAAAA==.Leocut:BAAALAAECgIIAgAAAA==.',Li='Liami:BAABLAAECoEcAAIEAAgIag1shACqAQAEAAgIag1shACqAQAAAA==.Lizard:BAAALAAECgMIBQAAAA==.',Lo='Longtooth:BAABLAAECoElAAIIAAgImB3NIACZAgAIAAgImB3NIACZAgAAAA==.',Lu='Ludogore:BAABLAAECoEZAAMJAAcILxmOTgBbAQAJAAYI2hGOTgBbAQAIAAYI1BFNkQBOAQAAAA==.Lunarkitty:BAAALAAECgIIAgAAAA==.',Ly='Lylian:BAAALAAFFAIIAgABLAAFFAIIBgAHAIkfAA==.',Ma='Mageya:BAABLAAECoEbAAIKAAgIiRj2NgBKAgAKAAgIiRj2NgBKAgAAAA==.Magneza:BAAALAAECgYIDgAAAA==.Maljinn:BAAALAADCggICAAAAA==.Manja:BAAALAADCggIFgAAAA==.Maraunda:BAAALAAECgYIBgAAAA==.Marta:BAAALAAECgMIBAAAAA==.Marthen:BAAALAAECgMIBAAAAA==.',Me='Mea:BAABLAAECoEUAAIBAAcImwogJwAtAQABAAcImwogJwAtAQAAAA==.Megashark:BAABLAAECoEVAAMTAAYI6yT1BABbAgATAAYI6yT1BABbAgAOAAEIDhtfPgBIAAAAAA==.',Mi='Midias:BAAALAAECgIIAgAAAA==.Mini:BAABLAAECoEaAAIQAAgInhurCgCeAgAQAAgInhurCgCeAgAAAA==.',Mo='Moirai:BAAALAAECgIIAwAAAA==.',Na='Nargal:BAAALAADCgcIDQAAAA==.Nazlo:BAAALAAECgMIBAAAAA==.',Ne='Negara:BAABLAAECoEWAAIPAAgIsRNVOgAaAgAPAAgIsRNVOgAaAgAAAA==.',Ni='Nickboi:BAAALAAECgUIBQAAAA==.Nightlovel:BAAALAAECgcIEQAAAA==.Niuel:BAAALAADCggIGgAAAA==.',Nn='Nnexar:BAABLAAECoEXAAISAAgIYhGgWQDmAQASAAgIYhGgWQDmAQAAAA==.',Ns='Nsiya:BAAALAAECgMIBQAAAA==.',Ny='Nycore:BAAALAAECgcICgAAAA==.',['Nà']='Nàmi:BAAALAADCggICAAAAA==.',['Ná']='Náttfarinn:BAABLAAECoEXAAMHAAYIrRMPNQB4AQAHAAYIxhAPNQB4AQAOAAUIbxJ0JAA7AQAAAA==.',Od='Odilolly:BAAALAAECgYICQAAAA==.',Pa='Pavkata:BAAALAAECgYICAAAAA==.',Pe='Penguindrumr:BAAALAAECgYIDgAAAA==.Percocets:BAAALAADCggICAAAAA==.Perun:BAABLAAECoEXAAIUAAgI6BV2QADtAQAUAAgI6BV2QADtAQAAAA==.',Pf='Pff:BAABLAAECoEbAAIPAAgI5BFuSwDWAQAPAAgI5BFuSwDWAQAAAA==.',Po='Pop:BAAALAADCgYIDQAAAA==.',Pr='Primall:BAAALAADCggICAAAAA==.',Pu='Pusheka:BAAALAADCggIIQAAAA==.',Ra='Ratzy:BAABLAAECoEbAAMIAAgI8Rn5LwBSAgAIAAgI8Rn5LwBSAgAJAAcIhwksXAAqAQAAAA==.',Re='Rebuke:BAAALAAECggIEAAAAA==.Regelee:BAAALAAECgYIBgAAAA==.Restindemon:BAAALAAECggIAQAAAA==.Rev:BAAALAAECgYIDwAAAA==.Revzy:BAAALAAECgMIAwAAAA==.',Sa='Saphiron:BAAALAADCggIEAAAAA==.',Sc='Scarab:BAAALAADCgYIBgABLAAECggILAAVAEAdAA==.',Se='Sengar:BAAALAAECgQIBgAAAA==.Sephirae:BAAALAAECgcIDgAAAA==.',Sh='Shackle:BAAALAAECgcICQAAAA==.Shadowpray:BAAALAAECgcIDQAAAA==.Sharn:BAAALAAECggIAwAAAA==.Sherman:BAAALAAFFAIIAgAAAA==.Shermon:BAAALAAFFAIIAgAAAA==.',Si='Silvdruid:BAABLAAECoEeAAMWAAgIByReAQBJAwAWAAgIByReAQBJAwAXAAYIOgznJQAmAQAAAA==.Silvwarrior:BAAALAAECggIDwABLAAECggIHgAWAAckAA==.Sixtypersent:BAAALAAECgIIAgABLAAECggIFwAYAEgeAA==.',Sk='Skinnygirl:BAAALAAECgYIBQAAAA==.',Sl='Slavery:BAAALAADCggIDgAAAA==.',Sm='Smerdyid:BAAALAAECgUICgAAAA==.',Sn='Snizz:BAAALAAECgQIAQAAAA==.',Sp='Spaguettis:BAAALAAECgIIAgAAAA==.Spartanetsa:BAAALAADCggIGAAAAA==.',St='Sta:BAAALAADCggIEAAAAA==.Stoney:BAAALAADCggICAAAAA==.',Sw='Swany:BAAALAADCgEIAQAAAA==.',Sy='Sylena:BAAALAAECgMIBQAAAA==.Syragix:BAAALAADCggICAAAAA==.',Ta='Tauriel:BAAALAADCgIIAgABLAAECgYICgAFAAAAAA==.',Th='Thedragonman:BAAALAAFFAMIBAAAAA==.Theshadowman:BAAALAADCggICAABLAAFFAMIBAAFAAAAAA==.Thooms:BAAALAAECgYICwAAAA==.Thrunite:BAAALAAECgEIAQAAAA==.',Tr='Trapt:BAAALAADCggIDgABLAAECggIAwAFAAAAAA==.Trolilufi:BAABLAAECoEWAAIEAAcItAcstABRAQAEAAcItAcstABRAQAAAA==.Trollwizard:BAAALAADCgIIAgAAAA==.',Ty='Typhoeus:BAAALAAECgYIDwAAAA==.',Ug='Ugrahk:BAABLAAECoEWAAILAAgIXh2xIQCOAgALAAgIXh2xIQCOAgAAAA==.',Uw='Uwufleya:BAAALAAFFAIIAgAAAA==.',Va='Vabu:BAACLAAFFIEIAAIUAAUI8R/QAgDhAQAUAAUI8R/QAgDhAQAsAAQKgRUAAhQACAikHvkQAMcCABQACAikHvkQAMcCAAEsAAUUAwgIABkAbCMA.Valkhor:BAABLAAECoEWAAIYAAcIshRoMQDfAQAYAAcIshRoMQDfAQAAAA==.',Vi='Vinrael:BAAALAAECgEIAQAAAA==.Violancebg:BAAALAADCgcIDAAAAA==.',Vy='Vylia:BAAALAADCggICAAAAA==.',Wa='Wafleya:BAAALAAECgcICwAAAA==.',Wh='Whelp:BAAALAAECgcIBQAAAA==.Whitefoot:BAAALAAECgUIDAAAAA==.',Wi='Windytornado:BAAALAAECgIIAgAAAA==.',Wo='Wolfclaw:BAABLAAECoEYAAILAAgIixyyJAB8AgALAAgIixyyJAB8AgAAAA==.Wolfix:BAAALAAECgIIAgABLAAECggIGAALAIscAA==.Wolftail:BAAALAAECgYIBgABLAAECggIGAALAIscAA==.',Yo='Yo:BAAALAADCggICAAAAA==.',Za='Zagor:BAAALAADCggICQAAAA==.',Zl='Zlobarkata:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end