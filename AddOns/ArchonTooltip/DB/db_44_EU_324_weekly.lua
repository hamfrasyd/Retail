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
 local lookup = {'Monk-Brewmaster','Unknown-Unknown','DeathKnight-Blood','DemonHunter-Havoc','Priest-Shadow','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Hunter-BeastMastery','Druid-Feral','Paladin-Retribution','Priest-Discipline','Shaman-Elemental','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Paladin-Protection','Mage-Arcane','Paladin-Holy','Shaman-Restoration','Warrior-Fury','Mage-Frost',}; local provider = {region='EU',realm='Saurfang',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aapie:BAAALAAECgYIDwAAAA==.',Ae='Aesir:BAAALAAECggICAAAAA==.Aetheria:BAAALAAECgQIBgAAAA==.Aethra:BAAALAADCggIHgAAAA==.',Ai='Aimandready:BAAALAAECgMIAwAAAA==.Aisae:BAAALAADCgcIBwAAAA==.',Al='Alakan:BAAALAAECgcIDQAAAA==.Alan:BAACLAAFFIEJAAIBAAMIXBrWAgAAAQABAAMIXBrWAgAAAQAsAAQKgRsAAgEACAj2I9IBAEIDAAEACAj2I9IBAEIDAAAA.Alise:BAAALAADCggICAAAAA==.Alishira:BAAALAADCggIEAABLAAECgQIBQACAAAAAA==.Alofury:BAAALAAECgcIEQAAAA==.Alsek:BAAALAAECgMICAAAAA==.Altchamp:BAAALAAECgMIAwAAAA==.',Am='Amanari:BAAALAAECgcIDwAAAA==.Amara:BAAALAADCgcIBwABLAAECgcIFAADAJoOAA==.Amaral:BAAALAADCggIHgAAAA==.Amidrasil:BAAALAADCgcIBwAAAA==.',An='Anaya:BAAALAADCgMIAgAAAA==.',Ap='Apoker:BAACLAAFFIEFAAIEAAII0hpHDQCyAAAEAAII0hpHDQCyAAAsAAQKgR0AAgQACAj3I6sFAEkDAAQACAj3I6sFAEkDAAAA.',Ar='Arrhythmia:BAACLAAFFIEGAAIFAAIIyxprCgClAAAFAAIIyxprCgClAAAsAAQKgTsAAgUACAjiI+kEADMDAAUACAjiI+kEADMDAAAA.',As='Aspin:BAAALAAECgIIBgAAAA==.',At='Atrocity:BAAALAADCgIIAgAAAA==.',Aw='Awda:BAAALAADCgYIBgAAAA==.Awoogah:BAAALAAECgEIAgAAAA==.',Az='Azerak:BAAALAAECgIIBAAAAA==.',Ba='Badel:BAAALAAECggIBQAAAA==.Baiser:BAABLAAECoEVAAQGAAgIjA13CgDFAQAGAAcI5wx3CgDFAQAHAAYIeAldMQA3AQAIAAEI1gE6kAAoAAAAAA==.Bambi:BAAALAADCggIGAAAAA==.Bayonetta:BAAALAADCgUIBQAAAA==.',Be='Beniu:BAAALAAECgUIAwAAAA==.Bert:BAAALAADCgMIAwAAAA==.',Bi='Bigbloodyboy:BAAALAAECgQIBAABLAAECggIFgAHANckAA==.',Bl='Blitzcow:BAAALAADCgEIAQAAAA==.Bloodeye:BAAALAADCgQIBAAAAA==.Bloodmace:BAAALAADCggIDgAAAA==.Bloodreeinaa:BAAALAADCgUIBwAAAA==.Bloodyfloof:BAAALAADCgUIBQAAAA==.Bloomkin:BAAALAADCggIFQAAAA==.Bludder:BAAALAAECgYIDgAAAA==.Bluerock:BAAALAAECgcIEQAAAA==.Bluékel:BAAALAADCggIDwAAAA==.',Bo='Bobbie:BAAALAAECggIDgAAAA==.Boombam:BAAALAAECgcIEQAAAA==.Bosston:BAAALAAECgIIAgAAAA==.',Br='Brathair:BAABLAAECoEVAAIBAAcIbhfxDQDaAQABAAcIbhfxDQDaAQAAAA==.',Ca='Canieatyouup:BAABLAAECoEXAAMEAAgIuiC0EQDVAgAEAAgIuiC0EQDVAgAJAAMIrx1+IAD0AAAAAA==.Cartron:BAAALAAECgYIDQAAAA==.',Ce='Ceasar:BAAALAAECgIIAgAAAA==.',Ch='Chachadans:BAAALAADCgcIBwAAAA==.Chaín:BAAALAAECgQIBAAAAA==.Chib:BAABLAAECoEVAAIFAAcI2R+HEgB7AgAFAAcI2R+HEgB7AgAAAA==.Chiraya:BAAALAAECgYICwAAAA==.Chrysiana:BAAALAADCgYIDAAAAA==.',Co='Cogwheal:BAAALAAECgYICAAAAA==.Concord:BAAALAADCgcIDQAAAA==.Convectus:BAAALAADCgcIBwAAAA==.',Cr='Cresela:BAAALAAECgYIDQAAAA==.',Cy='Cynára:BAABLAAECoEWAAMHAAgI1yQAAwD1AgAHAAcI8yQAAwD1AgAIAAUIjSPdJgD9AQAAAA==.',['Cí']='Círi:BAAALAAECgYIBgAAAA==.',Da='Darkflight:BAAALAADCggICAAAAA==.Darkpanther:BAABLAAECoEeAAIKAAgISx0DEQCrAgAKAAgISx0DEQCrAgAAAA==.Dawoud:BAAALAAECgIIAwABLAAECgcIFQABAG4XAA==.',De='Deadlift:BAAALAADCggICAAAAA==.Deadpool:BAAALAAECgEIAQAAAA==.Deadshøt:BAAALAAECgIIAwAAAA==.Deartháir:BAAALAADCgYIBgABLAAECgcIFQABAG4XAA==.Deathdarh:BAAALAAECgMIBgAAAA==.Deathseekerv:BAAALAAECgYICAAAAA==.Deathseker:BAAALAAECgMIBwAAAA==.Deathurn:BAAALAADCggICAABLAAECgYIBwACAAAAAA==.Demoillidan:BAAALAADCgUIBQAAAA==.Demonbanana:BAAALAADCgcIDQAAAA==.Demonina:BAAALAAECgMIBwAAAA==.Demoniça:BAAALAAECgMIBgAAAA==.Demonsftw:BAAALAADCggIDgAAAA==.Desideria:BAAALAADCgcIBwAAAA==.Desinty:BAAALAAECgIIAwAAAA==.',Di='Diallo:BAAALAADCgUIBQABLAADCgYIBgACAAAAAA==.Dilithium:BAAALAADCggIHAAAAA==.Dimitrios:BAAALAADCgYICwAAAA==.Discotroll:BAAALAAECgYIBgAAAA==.',Do='Dorfa:BAAALAADCggIHgAAAA==.',Dr='Dragoneye:BAAALAAECgIIAgAAAA==.Drakoron:BAAALAADCgYIBgAAAA==.Dreki:BAAALAAECgYIDQAAAA==.',Dv='Dverghamster:BAAALAAECgYIAwAAAA==.',El='Eleo:BAAALAADCgYIBgAAAA==.',Em='Emzgas:BAAALAADCgEIAQAAAA==.',En='Envisious:BAAALAADCgUIBQABLAADCgYIBgACAAAAAA==.',Et='Ethurilien:BAAALAAECgYIDQAAAA==.',Ev='Everild:BAAALAAFFAIIAwAAAA==.',Fa='Faulissra:BAAALAAECgMIBQAAAA==.',Fe='Feoto:BAAALAAECgEIAQAAAA==.',Ff='Ffse:BAAALAADCggIEwAAAA==.',Fh='Fhatman:BAAALAADCggIDwAAAA==.',Fi='Fiorelle:BAAALAAECgQIBAAAAA==.Firepawn:BAAALAADCggICAAAAA==.',Fl='Floofíe:BAAALAADCggIHgAAAA==.',Fo='Foilsz:BAAALAAECgYICgAAAA==.Forthewild:BAAALAAECgQIBgAAAA==.',Fu='Furiahal:BAAALAADCggIHgAAAA==.Fuzzibear:BAAALAADCggIFgAAAA==.',['Fá']='Fáfnir:BAAALAAECgEIAQAAAA==.Fáttpanda:BAAALAAECggIEQABLAAECggIFgAHANckAA==.',Ge='Georgé:BAAALAADCgcIBwAAAA==.',Gh='Ghanapriest:BAAALAADCgcIBwAAAA==.Ghoulash:BAAALAAECgEIAQAAAA==.',Gn='Gnoom:BAAALAADCggIEgABLAAECgcIEQACAAAAAA==.',Go='Goldigoddess:BAAALAADCggIGAAAAA==.Gothevoker:BAAALAAECggICAAAAA==.',Ha='Harm:BAAALAAECgYIBgAAAA==.',He='Heiress:BAAALAADCggICAAAAA==.Hellkeeper:BAAALAAECggICwAAAA==.Helneth:BAAALAADCggIFwAAAA==.Hermanus:BAABLAAECoEVAAILAAcIkA6OEQCfAQALAAcIkA6OEQCfAQAAAA==.Heset:BAAALAAECgYIDAAAAA==.',Hi='Hikari:BAABLAAECoEUAAIDAAcImg49EgBmAQADAAcImg49EgBmAQAAAA==.Hitzz:BAAALAAECgIIAwAAAA==.',Ho='Holymonster:BAAALAAECgYIDgAAAA==.Hooklock:BAAALAADCgcIBwAAAA==.Horakel:BAABLAAECoEXAAIMAAcIyyNXEQDaAgAMAAcIyyNXEQDaAgAAAA==.',Hu='Huntsekker:BAAALAAECgQIBQAAAA==.Huntärd:BAAALAADCgMIAwAAAA==.',Hy='Hybris:BAAALAAECggIEQAAAA==.',['Hé']='Hélléstrá:BAAALAAECggICAAAAA==.',If='Ifrita:BAAALAAECgYIDgAAAA==.',Il='Illarinn:BAAALAADCgMIBgAAAA==.Illuminatí:BAAALAADCgYIBgAAAA==.Illuminnae:BAAALAADCggICAABLAAECggIHgAKAEsdAA==.Iltran:BAAALAADCggICwAAAA==.',Im='Imawful:BAAALAADCgEIAQAAAA==.Imhere:BAAALAADCggICAAAAA==.Imterrible:BAAALAADCgMIAwAAAA==.',Is='Ishootthings:BAAALAAECggIEwAAAA==.',Ja='Jayanthi:BAAALAAFFAIIAwAAAA==.',Ju='Juant:BAAALAAECgYIDQAAAA==.',Jy='Jyjiyi:BAAALAADCgYIBgAAAA==.',['Já']='Jáz:BAAALAADCgQIBAAAAA==.',Ka='Kaei:BAAALAAECgEIAQAAAA==.Kaelth:BAAALAADCgYIBgAAAA==.Kakaomælk:BAAALAADCgUIBQAAAA==.',Ke='Kebule:BAAALAAECggIAgAAAA==.Keethrax:BAAALAADCggIHgAAAA==.Kelzo:BAAALAADCgcIBwABLAADCggIDgACAAAAAA==.Kenji:BAAALAADCggIFgAAAA==.',Ki='Killerfrozen:BAAALAADCgcIBwAAAA==.Killershot:BAAALAADCgYIBgAAAA==.Kitagawa:BAAALAAECgcICQAAAA==.',Kr='Kram:BAAALAAECgIIAgAAAA==.Krazay:BAAALAAECgUIDgAAAA==.Krispy:BAAALAAECgcIBwABLAAFFAMIBgANAAwkAA==.',Kw='Kwoh:BAAALAADCggICAAAAA==.',['Kà']='Kàli:BAAALAADCggICQABLAADCggIFwACAAAAAA==.',['Ké']='Kélorn:BAAALAAECgQIBQAAAA==.',La='Lalana:BAAALAADCgcIEQAAAA==.',Le='Leahx:BAAALAAECgcIBwAAAA==.Legendhusk:BAAALAAECgcIDgABLAAFFAQIBgAOAIULAA==.Legionella:BAAALAADCgQIBwAAAA==.Legithusky:BAACLAAFFIEGAAIOAAQIhQuVAwA8AQAOAAQIhQuVAwA8AQAsAAQKgR0AAg4ACAibIRMIABUDAA4ACAibIRMIABUDAAAA.',Li='Lion:BAAALAAECgUIDQAAAA==.Liukasmuikku:BAAALAAECgEIAQAAAA==.',Lo='Loftyy:BAAALAAECgEIAQABLAAECgcIEQACAAAAAA==.Logaan:BAAALAAECgcIEQAAAA==.Lorth:BAAALAADCgYIBgAAAA==.',Lu='Lutador:BAAALAAECgEIAQAAAA==.Luxitedxx:BAAALAAECgYICQAAAA==.',Ly='Lyonsgldblnd:BAAALAAECgQICAAAAA==.Lysyzfelwood:BAAALAAECgYIDgAAAA==.',Ma='Magda:BAAALAADCgYIBgAAAA==.Mahnaaz:BAAALAADCggICQAAAA==.Mailine:BAAALAADCggIFgAAAA==.Makgora:BAAALAAECgIIAwAAAA==.Marisan:BAAALAAECgYIDgAAAA==.Mazahs:BAAALAAECgUIDgAAAA==.Mazajaja:BAAALAADCgcIBwAAAA==.',Mc='Mcmac:BAAALAAECgQIBAAAAA==.Mcpats:BAAALAAECgYIEAAAAA==.',Me='Mementomori:BAAALAAECgUIBQABLAAECgYIBwACAAAAAA==.Meowsforheal:BAAALAAECgMIAwAAAA==.Meryn:BAAALAAECgYIDAAAAA==.Meso:BAAALAAECgEIAQAAAA==.Metamörph:BAAALAADCgcIEQAAAA==.',Mi='Mibba:BAAALAAECggIEAAAAA==.Milixxy:BAAALAAECgYIDgAAAA==.Minuer:BAAALAAECgEIAQAAAA==.Missiman:BAAALAADCgEIAQAAAA==.Mistresdíz:BAAALAAECgYICAAAAA==.',Mo='Moonpantz:BAAALAADCgYIBgABLAADCgYIBgACAAAAAA==.',['Má']='Márin:BAAALAAECgYIBgAAAA==.',['Må']='Månljus:BAAALAADCggIFAAAAA==.',Na='Natur:BAACLAAFFIEGAAIPAAMIaiE2AgAlAQAPAAMIaiE2AgAlAQAsAAQKgR8ABBAACAgDHy4LAKUCABAABwipIS4LAKUCAA8ABwjFH6MGAFYCABEABghMGiYEANgBAAAA.Nazha:BAAALAADCggICAAAAA==.',Ne='Needdatsalt:BAAALAADCgEIAQAAAA==.',Ni='Nicolae:BAABLAAECoEWAAISAAcImQ2pGABcAQASAAcImQ2pGABcAQAAAA==.',No='Noskillz:BAAALAADCgMIAwAAAA==.Novemberxii:BAAALAADCggICAAAAA==.',Nr='Nrgwayne:BAAALAAECgQICAAAAA==.',Ny='Nyrrh:BAAALAAECgcIDQAAAA==.',Pa='Papamortem:BAAALAAECgcIDAAAAA==.Paprikafox:BAAALAAECgQIBwAAAA==.Patsy:BAABLAAECoEWAAIKAAcItReFKQD0AQAKAAcItReFKQD0AQAAAA==.',Pe='Peeledbanana:BAAALAADCggICAAAAA==.',Ph='Philelf:BAAALAADCggIDAAAAA==.Phineas:BAAALAAECgYIEAAAAA==.',Po='Pooksi:BAAALAAECggIDgAAAA==.Popina:BAAALAAECgYICAABLAAECggIEwATABAbAA==.Porventi:BAAALAAECgUICQAAAA==.',Pr='Priam:BAAALAADCggIHgAAAA==.Protadin:BAABLAAECoEUAAIMAAgIGiPYCAArAwAMAAgIGiPYCAArAwAAAA==.',Ra='Rafilock:BAAALAAECgMIBAAAAA==.Rasha:BAAALAAECgYIBgAAAA==.Ravage:BAAALAAECgIIBAAAAA==.',Re='Restro:BAAALAAECgMIAwAAAA==.',Rh='Rhainebow:BAAALAAECgUICQAAAA==.Rhainedance:BAAALAADCggIDAAAAA==.Rhan:BAAALAAECgIIAwAAAA==.',Ri='Rishko:BAAALAADCggIEAAAAA==.Rival:BAAALAADCggIDAAAAA==.',Ro='Rosemare:BAAALAADCgUIBQAAAA==.',Ru='Rubyi:BAAALAADCgcIDgAAAA==.Ruguwu:BAAALAADCggICAAAAA==.Runrig:BAAALAADCgMIAwAAAA==.Rusmula:BAAALAAECgYIEgAAAA==.',Ry='Ryoko:BAAALAAECgMIAwAAAA==.',['Rá']='Ráymón:BAAALAAECgcIEAAAAA==.',Sa='Saaz:BAAALAAECgcIEAAAAA==.Saerdnaa:BAAALAAECgEIAgAAAA==.Saggat:BAAALAADCggIGQAAAA==.Saltlover:BAAALAAECgEIAQABLAAECgMIBAACAAAAAA==.Samistra:BAAALAADCggIDQAAAA==.Sanguellan:BAAALAADCgMIAwAAAA==.',Sc='Schindy:BAABLAAECoEVAAIUAAcIix60BwCIAgAUAAcIix60BwCIAgAAAA==.',Sh='Shalaria:BAAALAADCggIDgAAAA==.Shalbywalk:BAABLAAFFIEGAAMNAAMIDCQTAABCAQANAAMIDCQTAABCAQAFAAEIVRD0EgBPAAAAAA==.Shally:BAAALAAECggIAQAAAA==.Shaloune:BAAALAADCgMIAwAAAA==.Shamansftw:BAABLAAECoEXAAMOAAgIlRvbDwCvAgAOAAgIlRvbDwCvAgAVAAEIURYRowBCAAAAAA==.Shambanana:BAAALAAECgYIBgAAAA==.Shamiurn:BAAALAAECgYIBwAAAA==.Shandu:BAAALAAECgcIEQAAAA==.Sharkfury:BAABLAAECoEhAAIWAAgIKiJMBwAhAwAWAAgIKiJMBwAhAwAAAA==.Shelled:BAAALAAECgYICgAAAA==.Shenlong:BAAALAADCggICAAAAA==.Shnxz:BAAALAADCggIDgAAAA==.Shosànna:BAAALAADCggIGAAAAA==.Shrikei:BAAALAADCggICAABLAAECgEIAgACAAAAAA==.',Si='Silvermage:BAAALAADCggIFwAAAA==.',Sk='Skogsbruden:BAAALAADCgQIBAAAAA==.',Sl='Slowly:BAAALAADCgIIAgAAAA==.Slunicko:BAAALAADCggIBQAAAA==.',So='Solenne:BAAALAAECgcIEQAAAA==.Solkan:BAAALAADCgYIBgAAAA==.Sololeveling:BAAALAAECgMIAwAAAA==.Sophie:BAAALAAECgQIBQAAAA==.Soupreme:BAAALAAECgcIBwAAAA==.',Sp='Sparkplug:BAAALAADCgIIAgAAAA==.Spellora:BAAALAADCggIDgAAAA==.Spyrogos:BAABLAAECoEWAAIPAAcIhw/GDwB+AQAPAAcIhw/GDwB+AQAAAA==.',St='Stava:BAAALAAECgYIDgAAAA==.Stonesmasher:BAAALAAECgYICgAAAA==.Stryike:BAAALAAECgMIBgAAAA==.Sturmfänger:BAABLAAECoEdAAMXAAgI2xZkFAD6AQAXAAcIFhNkFAD6AQATAAgIXBCdPADMAQAAAA==.',Su='Sunderhowl:BAAALAAECgYIDwAAAA==.Suramarac:BAABLAAECoETAAMTAAgIEBt7MwD3AQATAAcInhp7MwD3AQAXAAYIyg9cKgBOAQAAAA==.',Sw='Swaff:BAAALAAECgYIEAAAAA==.Swaffsie:BAAALAADCggICAAAAA==.',Sy='Sybilla:BAAALAAECgYICgABLAAECgcIEQACAAAAAA==.',['Sé']='Sékhmet:BAAALAAECgMIBAAAAA==.',['Sø']='Sødeida:BAAALAAECgEIAQAAAA==.',Ta='Tahlin:BAAALAADCgYIBgAAAA==.Taladin:BAAALAADCgcICQAAAA==.Talrione:BAAALAADCggICAAAAA==.Tamiya:BAAALAADCggIFgAAAA==.Tavin:BAAALAADCggICAABLAAECgEIAgACAAAAAA==.',Te='Tevar:BAAALAADCgUIBwAAAA==.',Th='Tharaniel:BAAALAAECgYIDAAAAA==.Thelithi:BAAALAADCgcIEQAAAA==.Thiena:BAAALAADCgYICgAAAA==.Thoradin:BAAALAAECgEIAQAAAA==.Thorxx:BAAALAADCggIEAAAAA==.Thrawn:BAAALAAECgcIDwAAAA==.Thrawneekaar:BAAALAADCgcIBwAAAA==.',Ti='Tigse:BAAALAADCggIDAAAAA==.Tin:BAAALAAECgYICwAAAA==.Tinyshammy:BAAALAAECgMIAwAAAA==.Tinystab:BAAALAAECgIIAgAAAA==.Tirilion:BAAALAADCgYIBgAAAA==.Tirius:BAAALAAECgYIEQABLAAFFAIIAwACAAAAAA==.Tirys:BAAALAADCgIIAgABLAADCggIFwACAAAAAA==.',To='Towox:BAAALAADCggIFwAAAA==.',Tu='Tupacshakur:BAAALAADCgcIBwABLAAECggIFgAHANckAA==.',Tw='Twiztednipz:BAAALAAECgEIAQAAAA==.',Tz='Tzien:BAAALAADCggIDAAAAA==.',Va='Valentîne:BAAALAAECgYICgAAAA==.Valfreja:BAAALAAECgQICAAAAA==.Valyro:BAAALAADCggIHgAAAA==.',Ve='Verntas:BAAALAAECgIIAgAAAA==.Vespin:BAAALAADCgQIBAAAAA==.',Vi='Vivong:BAAALAADCgcIBgAAAA==.',Vo='Voltigeuse:BAAALAAECgEIAQAAAA==.Voo:BAAALAADCggIEwAAAA==.',Vu='Vulpine:BAAALAADCgIIAgAAAA==.',Vv='Vvest:BAAALAAECgcICwAAAA==.',Wa='Waroxeal:BAAALAAECgYIBgAAAA==.',Wh='Whittlers:BAAALAAECgMIBQAAAA==.',Wi='Wickedwalker:BAAALAAECgYICwAAAA==.Wida:BAAALAAECgYIEAAAAA==.',Wo='Woodenchair:BAAALAADCgYIBwAAAA==.Wooladin:BAAALAADCggIDwAAAA==.Woolyish:BAAALAAECgYICgAAAA==.',Xy='Xyphyr:BAABLAAECoEVAAIVAAcIzgmPXQATAQAVAAcIzgmPXQATAQAAAA==.',Yu='Yune:BAAALAADCgIIAgAAAA==.',Ze='Zenith:BAAALAADCggICAAAAA==.Zewei:BAAALAAECgMIBQAAAA==.',['Àn']='Àngh:BAAALAADCggIFwAAAA==.',['És']='És:BAAALAAECgMIAwAAAA==.',['Íl']='Ílluminati:BAAALAADCgUIBQABLAADCgYIBgACAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end