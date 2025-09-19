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
 local lookup = {'Druid-Restoration','Hunter-Marksmanship','Unknown-Unknown','DemonHunter-Havoc','Warrior-Arms','Warrior-Protection','Warrior-Fury','Shaman-Restoration','Hunter-Survival','Mage-Arcane','Mage-Fire',}; local provider = {region='EU',realm="Throk'Feroth",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ag='Agouéé:BAAALAAECgIIAgAAAA==.Aguerros:BAAALAAECgMIBQAAAA==.',Ai='Aiku:BAAALAADCgcIBwAAAA==.',Ak='Akirep:BAAALAADCgYICQAAAA==.',Al='Alakaosy:BAAALAADCggICAAAAA==.Alderion:BAAALAADCggIDQAAAA==.Alganuz:BAAALAADCgIIAgAAAA==.Alirea:BAAALAAECgMIAwAAAA==.',Am='Amjed:BAAALAAECgYIBgAAAA==.',An='Animaz:BAAALAADCgMIAwAAAA==.Anjara:BAAALAADCgYIBgAAAA==.',Ao='Aonae:BAAALAAECggIBwAAAA==.',Ar='Argusson:BAAALAADCggIDAAAAA==.',Bi='Biscotte:BAAALAAECggIEgAAAA==.',Bl='Blackops:BAAALAAECgMIBQAAAA==.Blackøps:BAAALAAECgYICQAAAA==.Bloodyfest:BAAALAAECgMIAwAAAA==.',Bo='Bouglarun:BAAALAADCgYIBgAAAA==.Bouyah:BAAALAADCggIHAAAAA==.',Br='Bruluxx:BAAALAAECgYIDAAAAA==.',Ca='Carritangue:BAAALAADCgYIBgAAAA==.',Ce='Celéthor:BAAALAADCgYIBgAAAA==.',Ch='Chance:BAAALAAECggIDAAAAA==.Chassousacer:BAAALAAECgQIBAAAAA==.Christoo:BAAALAAECgUIBQAAAA==.',Ci='Ciszo:BAAALAADCgcIBwAAAA==.',Cl='Clippyx:BAAALAADCgcIDQAAAA==.',Cr='Criçks:BAAALAADCggIGQAAAA==.',['Cø']='Cøwax:BAAALAAECgQIBAAAAA==.',Da='Dardargnan:BAAALAAECgEIAQAAAA==.Darkeïge:BAAALAADCggIDAAAAA==.',Do='Dopainperdu:BAAALAAECgcIEAAAAA==.',Dr='Drakturd:BAAALAADCgYIBgAAAA==.',Du='Duryk:BAAALAAECgcIDgAAAA==.',['Dé']='Dédaria:BAABLAAECoEXAAIBAAgIsiMWAgALAwABAAgIsiMWAgALAwAAAA==.Déshi:BAABLAAECoEXAAICAAgIhB/ECACjAgACAAgIhB/ECACjAgAAAA==.Déshiré:BAAALAAECgYIDAAAAA==.',El='Eléonia:BAAALAADCggIDgAAAA==.',Em='Emeylà:BAAALAADCgEIAQABLAADCgUIBwADAAAAAA==.',Es='Eskanor:BAAALAADCgcIBwAAAA==.',Eu='Eucalÿptus:BAAALAAECgQIBAAAAA==.',Ey='Eyoha:BAAALAADCgYIBgAAAA==.',Fa='Facerol:BAAALAAECgMIBAAAAA==.Fafnyr:BAAALAAECgEIAQAAAA==.Fayez:BAABLAAECoEYAAIEAAgI8hvnEACdAgAEAAgI8hvnEACdAgAAAA==.',Fb='Fbzottoute:BAAALAADCgYIBgAAAA==.',Fe='Federig:BAAALAAECgYIDQAAAA==.',Fi='Fileali:BAAALAAECgMIBAAAAA==.',Fl='Fleurdoré:BAAALAAECgYIDQAAAA==.',Fr='Frekence:BAAALAADCggIDwAAAA==.',Ga='Galwishe:BAAALAAECgMIAwAAAA==.',Go='Goldor:BAAALAAECgQIBAAAAA==.Gon:BAAALAAECggICAABLAAECggIBwADAAAAAA==.',Gr='Grimggor:BAAALAADCgIIAgAAAA==.',Ha='Hagrog:BAAALAADCgIIAgAAAA==.Happyy:BAAALAADCgcIDAAAAA==.Haresse:BAAALAADCgYIBgABLAAECgMIBAADAAAAAA==.',He='Heima:BAAALAADCgQIBAAAAA==.',Ho='Hok:BAAALAAECgUIBQAAAA==.',Hy='Hyunae:BAAALAADCggICgAAAA==.',Ja='Jacøcculte:BAAALAADCgQIBAAAAA==.Jacøsan:BAAALAADCgYIBgAAAA==.',Jo='Jolithorax:BAAALAAECgUIBQAAAA==.Joyboy:BAAALAADCggICAAAAA==.',Ju='Julciléa:BAAALAAECgMIBAAAAA==.',['Jæ']='Jæz:BAAALAADCggICAAAAA==.',Ka='Kaelysta:BAAALAADCgcIDQAAAA==.Kamazinz:BAAALAAFFAIIAwAAAA==.',Ke='Keupstorm:BAAALAAECgcICAAAAA==.',Kh='Khesh:BAACLAAFFIEFAAMFAAMIPxsqAAASAQAFAAMIeBcqAAASAQAGAAIIphYTBACZAAAsAAQKgRkABAUACAiPJS0AAHUDAAUACAiMJS0AAHUDAAYACAjkH14FAJ0CAAcAAwhgEItEAKwAAAAA.',Ko='Koroma:BAAALAAECgcIDAAAAA==.Koub:BAAALAADCgYIBgAAAA==.',Kr='Krèk:BAAALAADCggIEAAAAA==.',Kt='Ktos:BAAALAAECgMIAwAAAA==.',La='Lathspell:BAAALAADCgMIAwAAAA==.Layu:BAAALAADCgEIAQAAAA==.',Le='Leftorie:BAAALAAECgcIEAAAAA==.Legna:BAAALAAECgYIDwAAAA==.Levlevrai:BAAALAAECgUICAAAAA==.',Li='Lifebløøm:BAAALAAECggICAAAAA==.',Ly='Lythom:BAAALAADCggIFAAAAA==.',['Lø']='Løck:BAAALAAECgMIAwAAAA==.',Ma='Mandolyne:BAAALAAECgMIBAAAAA==.Maoif:BAAALAADCggICAAAAA==.Marlëÿ:BAAALAAECgYIBgAAAA==.Maszo:BAAALAADCgYIBgAAAA==.',Me='Mega:BAAALAAECgQIBQAAAA==.Meline:BAAALAAECgYICgAAAA==.Mercurochrom:BAAALAADCgcIBwAAAA==.',Mi='Mistik:BAAALAAECgQIBAAAAA==.',Mo='Moka:BAAALAAECggICAAAAA==.',['Mí']='Mílanó:BAAALAADCgIIAgAAAA==.',['Mü']='Müwen:BAAALAADCgUIBwAAAA==.',Na='Nalivendälle:BAAALAADCggICQAAAA==.',Ne='Neoo:BAAALAAECgQIBAAAAA==.',No='Noctua:BAAALAADCggICAAAAA==.',Ny='Nymoria:BAAALAAECgEIAQAAAA==.',['Nô']='Nôji:BAAALAAFFAEIAQAAAA==.',Ou='Oural:BAAALAAECgUIBQAAAA==.Ousuije:BAAALAADCggIEAAAAA==.',Pa='Pandahanne:BAAALAADCggIEQAAAA==.Paraphon:BAAALAAFFAIIAgAAAA==.',Ph='Phumera:BAAALAAECgUIBQAAAA==.',Pi='Pi:BAAALAADCggICAAAAA==.',Po='Poppykline:BAAALAAECgUICwAAAA==.',Pr='Pralïne:BAAALAAECgIIAwAAAA==.',Ps='Psychí:BAAALAAECgMIBQAAAA==.',Qu='Quietotem:BAAALAADCgQIBQABLAAECgYICQADAAAAAA==.Quietpriest:BAAALAAECgYICQAAAA==.',Sa='Sacreb:BAAALAAECgUIBQAAAA==.Saradomin:BAAALAAECgYIDgAAAA==.',Sc='Scarr:BAAALAADCgYIDAAAAA==.Schaerbee:BAAALAADCgcIBwAAAA==.',Se='Selfette:BAAALAAECgYICwAAAA==.Septquatre:BAAALAADCggIEQAAAA==.Seravee:BAAALAADCgUIBgAAAA==.',Sf='Sfyle:BAAALAADCggICAAAAA==.',Sh='Shinigamî:BAAALAADCgYIBgABLAADCgYIBgADAAAAAA==.Shintaro:BAAALAADCgYIBgAAAA==.Shinzoo:BAAALAAECgUIBgAAAA==.',Si='Sinøk:BAAALAADCggIDAAAAA==.',Sk='Sknder:BAACLAAFFIEFAAIIAAMIdxqlAQAQAQAIAAMIdxqlAQAQAQAsAAQKgRgAAggACAjNIuQCAAEDAAgACAjNIuQCAAEDAAAA.Skndër:BAAALAAECgYIEgAAAA==.',Sp='Spamolol:BAAALAAECgMIAgABLAAECggIDgADAAAAAA==.Spamøoøoøoøo:BAAALAAECggIDgAAAA==.',['Sé']='Sékis:BAAALAADCggIDwAAAA==.',['Sð']='Sðul:BAAALAADCgIIAgABLAAECgMIBQADAAAAAA==.',Ta='Tahor:BAAALAADCgUIBQAAAA==.Tayu:BAABLAAECoEZAAIJAAgIXiUjAAB/AwAJAAgIXiUjAAB/AwAAAA==.',Te='Terock:BAAALAADCgcIBwAAAA==.',Th='Thaelys:BAAALAADCgYIBgAAAA==.Thaïny:BAAALAADCgcICQAAAA==.',Ti='Tigouane:BAAALAADCgcIBwAAAA==.Tijacmur:BAAALAAECgYICgAAAA==.Timaljk:BAAALAAECggICAAAAA==.',Tr='Troctroc:BAAALAADCgYIBgAAAA==.',Tw='Twitchothory:BAAALAADCgcICAAAAA==.',Ve='Vellevache:BAAALAAECgUIBQAAAA==.',['Vä']='Välmont:BAAALAADCggIDwAAAA==.',Xt='Xtasy:BAABLAAECoEVAAMKAAgIYhrrFAB9AgAKAAgIYhrrFAB9AgALAAEIviAbDwA5AAAAAA==.',Ya='Yaxe:BAAALAADCgcIAgAAAA==.',Yo='Youlounet:BAAALAAECgMIBQAAAA==.',['Yù']='Yùme:BAAALAADCgMIAwAAAA==.',Za='Zafi:BAAALAADCgQIBwAAAA==.Zafinâ:BAAALAADCgYIBgAAAA==.Zafî:BAAALAAECgEIAQAAAA==.Zafîna:BAAALAADCggICAAAAA==.Zambrozat:BAAALAADCgQIBAABLAAECgYICgADAAAAAA==.Zavaouquoi:BAAALAADCggIFAAAAA==.',['Ëz']='Ëzea:BAAALAADCggICAAAAA==.',['Ðe']='Ðexter:BAAALAAECgYIEAAAAA==.',['Ôu']='Ôunagui:BAAALAAECgYIBwAAAA==.',['ßã']='ßãtmãñgøðx:BAAALAADCggICAAAAA==.',['ßò']='ßòòm:BAAALAADCggICAAAAA==.',['ßö']='ßööm:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end