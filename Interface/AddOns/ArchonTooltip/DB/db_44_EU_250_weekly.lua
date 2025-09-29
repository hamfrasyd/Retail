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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Mage-Arcane','Priest-Discipline','Priest-Shadow','Hunter-Marksmanship','Mage-Fire','Rogue-Assassination','Warlock-Destruction','Monk-Mistweaver','DemonHunter-Vengeance','Priest-Holy','Hunter-BeastMastery','Shaman-Restoration','DeathKnight-Blood','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Druid-Balance','Paladin-Retribution','Paladin-Protection','Paladin-Holy','Rogue-Subtlety','Mage-Frost','Hunter-Survival','Shaman-Enhancement','Shaman-Elemental','DeathKnight-Frost','Warrior-Protection','DeathKnight-Unholy','Warlock-Demonology',}; local provider = {region='EU',realm="Ahn'Qiraj",name='EU',type='weekly',zone=44,date='2025-09-22',data={Ag='Agatul:BAAALAADCgYIBgAAAA==.',Ah='Ahleë:BAAALAAECggICgAAAA==.',Ai='Aivendil:BAAALAADCggIGgAAAA==.',Ak='Akison:BAAALAADCggICAAAAA==.Akumai:BAAALAADCggIEQABLAAECgYIEAABAAAAAA==.',Al='Alashar:BAAALAAECgEIAQAAAA==.Allnya:BAABLAAECoEcAAICAAgICAw1cACwAQACAAgICAw1cACwAQAAAA==.Aléxastraza:BAAALAAECgEIAQAAAA==.',Ar='Arcanus:BAABLAAECoEZAAIDAAgIAiE4HADLAgADAAgIAiE4HADLAgAAAA==.Arien:BAAALAADCgMIAwAAAA==.Arythc:BAABLAAECoEhAAMEAAgIJyGcAQD8AgAEAAgIJyGcAQD8AgAFAAMI7RHjaQC9AAAAAA==.',As='Ashpool:BAAALAADCggICAAAAA==.Assalta:BAABLAAECoEjAAIGAAgI/x7READKAgAGAAgI/x7READKAgAAAA==.',At='Atomica:BAACLAAFFIEHAAIDAAMIdR/ZEwATAQADAAMIdR/ZEwATAQAsAAQKgSMAAwMACAg+I4MiAKoCAAMABwjNJIMiAKoCAAcAAQhQGCAYAE4AAAAA.',Ax='Axarion:BAAALAAECgcIDQAAAA==.',Ba='Balphagore:BAAALAAECgIIAgABLAAECggIIwAIAMAdAA==.',Be='Beladi:BAAALAADCgUIBQAAAA==.Beyblade:BAAALAAFFAIIBAABLAAFFAIICAAJAAYhAA==.',Bi='Bigbarry:BAAALAADCgYIBgAAAA==.Bigfister:BAAALAAECggICAAAAA==.',Bl='Blluuxx:BAAALAAECgUIBQAAAA==.Bluuxx:BAAALAAECgcICAAAAA==.Bluxadin:BAAALAAECgQIBAAAAA==.Bluxx:BAABLAAECoEoAAIKAAgIsR5DCgCaAgAKAAgIsR5DCgCaAgAAAA==.Bluxxlock:BAAALAAECgcIDAAAAA==.',Bo='Borbalf:BAAALAADCgcIBwAAAA==.',Bu='Buicih:BAABLAAECoEYAAMLAAcIWiQ1BwDJAgALAAcIWiQ1BwDJAgACAAEIOhH5DAE+AAAAAA==.Bun:BAAALAAECgYICgAAAA==.',Ca='Cantaloupe:BAAALAADCgEIAQAAAA==.',Ce='Cedori:BAABLAAECoEeAAMFAAgIWSAFEADbAgAFAAgIWSAFEADbAgAMAAII6hMMigCLAAAAAA==.Cerio:BAAALAAECgQIBAABLAAECggIGQAJAHogAA==.',Ch='Charming:BAAALAADCgMIAwAAAA==.',Co='Coldrex:BAAALAADCgUIBQAAAA==.Comoapoel:BAABLAAECoEjAAIIAAgIwB3rCgDSAgAIAAgIwB3rCgDSAgAAAA==.',Cr='Crazinaa:BAAALAAECgcICAAAAA==.Crystek:BAAALAADCggICAAAAA==.',['Cá']='Cápslock:BAAALAAECgMIBAAAAA==.',Da='Daekon:BAABLAAECoEZAAICAAgIIBZ6RAAjAgACAAgIIBZ6RAAjAgAAAA==.Dakini:BAAALAADCgcICQABLAAECgYIEAABAAAAAA==.Daphnes:BAABLAAECoEXAAINAAgIrAw6egB9AQANAAgIrAw6egB9AQAAAA==.Darko:BAABLAAECoEZAAICAAcIMxhcVAD0AQACAAcIMxhcVAD0AQABLAAECggIGAAOAK8KAA==.Darkoff:BAAALAADCggICAAAAA==.',De='Deathkitteh:BAAALAADCgYIBgAAAA==.Delish:BAAALAADCgQIBAAAAA==.Dernar:BAAALAADCgYIBgAAAA==.Desmoon:BAAALAAECgIIAgAAAA==.',Di='Dischargê:BAAALAADCgEIAQAAAA==.',Dk='Dkshadow:BAAALAAECgcIBwABLAAECggIIwAPAMgcAA==.',Do='Docnidar:BAAALAAECgQIBAAAAA==.Doomakos:BAAALAAECgUICAAAAA==.Doomnezeu:BAABLAAECoEcAAMCAAcIrBbWVQDwAQACAAcIrBbWVQDwAQALAAYIVAh0OADJAAAAAA==.Dorgarag:BAAALAADCgcIBwAAAA==.Dotsfordays:BAACLAAFFIEIAAIJAAIIBiEgHgC5AAAJAAIIBiEgHgC5AAAsAAQKgSkAAgkACAjJJKsHAEoDAAkACAjJJKsHAEoDAAAA.',Dr='Draehunn:BAAALAAECgYIBgAAAA==.Draeknight:BAAALAADCggICAAAAA==.Dragdock:BAAALAAECgQIBAAAAA==.Droodfus:BAAALAAECgcIEAAAAA==.Drstrange:BAAALAAECgYIEgAAAA==.Drunkmaster:BAAALAADCgYICgAAAA==.',['Dø']='Døku:BAAALAADCggICAAAAA==.',Ek='Eksi:BAABLAAECoEUAAIOAAgIvBC2WwCdAQAOAAgIvBC2WwCdAQAAAA==.',Em='Emildruid:BAAALAAECgMIAwAAAA==.',Ep='Epokoloco:BAAALAAECgYICgAAAA==.',Ev='Evelin:BAAALAADCggIFQAAAA==.',Fa='Facetimee:BAAALAADCggICAAAAA==.Fahrun:BAAALAAECgMIAwAAAA==.Faraal:BAAALAADCggICAABLAAECggIIwAQAI8fAA==.Faélara:BAAALAAECgcICgAAAA==.',Fe='Ferocity:BAAALAADCgYICAAAAA==.',Fl='Flume:BAACLAAFFIEIAAIRAAIIbCG+EADAAAARAAIIbCG+EADAAAAsAAQKgScABBEACAj1JaMAAHsDABEACAj1JaMAAHsDABIACAhrH50FAO0CABMABQiwFSVTACcBAAAA.Flumedh:BAAALAAECgUIBQAAAA==.Flumehunter:BAAALAAECgEIAQAAAA==.Flumemage:BAABLAAFFIEGAAIDAAIIhhRbMQCYAAADAAIIhhRbMQCYAAAAAA==.Flumepala:BAABLAAECoEUAAQUAAcItgryvgA9AQAUAAcIbAbyvgA9AQAVAAQILw8gTAB/AAAWAAIIqRLKXQBXAAAAAA==.Flumewarr:BAAALAAECgIIAgAAAA==.',Fr='Freshmoon:BAAALAAECgcIEwAAAA==.',Ga='Garoosh:BAAALAADCgcIBwABLAAECgcIGAAXAAMPAA==.',Gr='Gregorlina:BAAALAAFFAIIAwAAAA==.',Ha='Haecubah:BAAALAADCgEIAQAAAA==.',He='Hedri:BAAALAAECgEIAQAAAA==.Helius:BAABLAAECoEoAAINAAgIkiFZFADlAgANAAgIkiFZFADlAgAAAA==.Hephaestus:BAAALAADCgcIBwABLAAECggIHwATALwbAA==.Heretika:BAAALAADCggIFgAAAA==.',Hi='Hitmanlee:BAAALAAECggIBgAAAA==.',Ho='Honeypoo:BAAALAADCgEIAQAAAA==.',Hz='Hzk:BAAALAAECgYIDAAAAA==.',Ic='Iceblock:BAAALAAECgYIDAABLAAECggIGAAOAK8KAA==.',Il='Ilikeballzz:BAAALAAECgYIEAAAAA==.Ilikebeellzz:BAAALAADCgcIBwAAAA==.Ilindan:BAAALAAECgUIBgAAAA==.',In='Insidious:BAAALAADCggICAAAAA==.',Is='Isabella:BAAALAADCgUICAAAAA==.',Je='Jens:BAAALAAECgcICwAAAA==.',Ju='Jumanjin:BAAALAAECgMIAwABLAAECgYIEAABAAAAAA==.',Ka='Kalandra:BAAALAADCgMIAwAAAA==.Kallorr:BAABLAAECoEjAAIQAAgIjx+6CACzAgAQAAgIjx+6CACzAgAAAA==.Kanondbhaal:BAABLAAECoEfAAMHAAgIfBuJAgCjAgAHAAgI6hqJAgCjAgAYAAYIfBSYPgBKAQAAAA==.',Ke='Kebabdrullen:BAAALAAECgMIAwAAAA==.Kepti:BAAALAADCggICAAAAA==.',Kl='Kljucis:BAABLAAECoEfAAITAAgIvBvkHgA3AgATAAgIvBvkHgA3AgAAAA==.Klortwo:BAAALAAECgIIAgAAAA==.',Kn='Knowidea:BAABLAAECoEeAAICAAgISRkFOABOAgACAAgISRkFOABOAgAAAA==.',Kr='Krungul:BAAALAADCggIDgAAAA==.',Ku='Kuan:BAABLAAECoErAAMLAAgIoyH5BQDqAgALAAgI4yD5BQDqAgACAAYImR4AAAAAAAAAAA==.',La='Laeriah:BAAALAADCgIIAgAAAA==.',Le='Leosolo:BAABLAAECoEcAAIIAAgIuiCcCADvAgAIAAgIuiCcCADvAgAAAA==.',Li='Liilith:BAABLAAECoEeAAICAAgIPyIJFQD+AgACAAgIPyIJFQD+AgAAAA==.Liliandra:BAAALAADCggIDwAAAA==.Lillaludret:BAAALAADCgcIDwAAAA==.Lincos:BAAALAADCgEIAQABLAAECggIHwAZAFcgAA==.',Lo='Losmi:BAAALAAECgMIBQAAAA==.',Ma='Maeyedk:BAAALAAECggICQAAAA==.Magou:BAAALAADCggICAABLAAECggIFQALAIsaAA==.Marakara:BAABLAAECoEfAAMZAAgIVyA3AgDzAgAZAAgIVyA3AgDzAgANAAEIgACgGgELAAAAAA==.Mardeth:BAAALAADCgcICAAAAA==.',Me='Meeris:BAAALAAECgUIBQABLAAECggIHwATALwbAA==.Mezereon:BAABLAAECoEdAAIDAAgI7x2AJwCSAgADAAgI7x2AJwCSAgAAAA==.',Mi='Michaela:BAAALAAECgYIBgAAAA==.Mistykitteh:BAAALAAECgYIBgAAAA==.',Ml='Mlokes:BAAALAADCgYIBgAAAA==.',Mo='Moa:BAAALAADCgcIDQAAAA==.Mohanje:BAAALAADCggIDwAAAA==.Moonhuntress:BAAALAADCgYIBgAAAA==.Moonmoon:BAABLAAECoEgAAIIAAgIMxYbGABCAgAIAAgIMxYbGABCAgAAAA==.Moriartree:BAAALAAECgEIAQAAAA==.',My='Myth:BAAALAAFFAIIBAAAAA==.',['Mø']='Møll:BAAALAAECgYICQAAAA==.',Na='Nandi:BAAALAADCggIEQAAAA==.Nathil:BAABLAAECoElAAIUAAgIQSSaFQAFAwAUAAgIQSSaFQAFAwAAAA==.Native:BAAALAAECgYICAAAAA==.',Ne='Nedge:BAAALAAECgMIBQAAAA==.Nenyasho:BAAALAADCgMIAwAAAA==.Nerir:BAAALAAECggICAAAAA==.Nerohk:BAAALAADCggICAAAAA==.',Ni='Niixten:BAAALAAECggIEAAAAA==.',Ny='Nymphetamine:BAAALAADCgEIAQAAAA==.Nyxara:BAAALAAECgcIBwAAAA==.',Ou='Outeast:BAAALAAECgIIAwAAAA==.',Pa='Papastorm:BAAALAAECgYIBgAAAA==.Partheus:BAAALAADCggICAAAAA==.',Pe='Pepa:BAABLAAECoEfAAMaAAcIXBxgCQA7AgAaAAcIXBxgCQA7AgAbAAIItQX6nwBIAAAAAA==.',Pl='Plesejs:BAAALAAECgIIAwABLAAECggIHwATALwbAA==.',Pr='Preach:BAAALAAECgYICAAAAA==.Prelina:BAAALAAECgUIBwAAAA==.Prix:BAABLAAECoEhAAIMAAgIkxCaNwDUAQAMAAgIkxCaNwDUAQAAAA==.Promocia:BAAALAAECgEIAQAAAA==.',['Pö']='Pö:BAAALAADCgcIBwAAAA==.',Qr='Qrypto:BAAALAADCgcIBwABLAAFFAMICAAbACQRAA==.',Qs='Qsien:BAABLAAECoEUAAIRAAgI4gowUABhAQARAAgI4gowUABhAQAAAA==.',Re='Reaper:BAABLAAECoEjAAIcAAYIYhDvvwBLAQAcAAYIYhDvvwBLAQAAAA==.Restoration:BAABLAAECoEgAAMbAAgI3x6DFQDMAgAbAAgI3x6DFQDMAgAOAAcIRA2ZhgAvAQAAAA==.',Ri='Rizskása:BAAALAADCgUIBQAAAA==.',Ro='Rowodent:BAAALAAECgEIAQAAAA==.',Ru='Rufsa:BAAALAADCggIFQAAAA==.',Ry='Ryrfy:BAAALAADCgYICgAAAA==.',Sa='Saab:BAABLAAECoEZAAIdAAgIsCZUAACVAwAdAAgIsCZUAACVAwAAAA==.Saabi:BAAALAADCggIHQAAAA==.Samstervoker:BAAALAAECgEIAQABLAAECgcIDgABAAAAAA==.Samstezz:BAAALAAECgcIDgAAAA==.Sashioman:BAAALAAECgIIAgAAAA==.',Sc='Scarhoof:BAAALAAECgIIBAAAAA==.',Sh='Shademd:BAAALAAECggIDgAAAA==.Shadowdk:BAABLAAECoEjAAMPAAgIyBwtCwBuAgAPAAgIyBwtCwBuAgAcAAIIuQuFMgFUAAAAAA==.Shadowonercy:BAABLAAECoEZAAIDAAYITA29gQBgAQADAAYITA29gQBgAQABLAAECggIIwAPAMgcAA==.Shadumbra:BAAALAADCgcIBwAAAA==.Shak:BAAALAADCgcIFQAAAA==.Shampynb:BAAALAAECgYIBwAAAA==.Shantaram:BAABLAAECoEcAAIOAAgIsRbUMgAeAgAOAAgIsRbUMgAeAgAAAA==.Shanti:BAAALAAECgQIBQAAAA==.Shepri:BAABLAAECoEtAAIMAAgIRRwMFACrAgAMAAgIRRwMFACrAgAAAA==.',Si='Sien:BAAALAAECgYICgAAAA==.Simonsay:BAAALAADCggIFwAAAA==.Sin:BAABLAAECoEeAAMXAAgIGxsEFwCzAQAXAAYIiRsEFwCzAQAIAAQIUxsNPABQAQAAAA==.',Sl='Slant:BAABLAAECoEaAAINAAgIrBq7PAAgAgANAAgIrBq7PAAgAgAAAA==.',Sn='Sneezepuff:BAAALAAECgYIDAABLAAECggIKAANAJIhAA==.Snow:BAACLAAFFIEGAAIWAAIIGxFgEgCZAAAWAAIIGxFgEgCZAAAsAAQKgRUAAhYACAjEGsgOAHoCABYACAjEGsgOAHoCAAAA.',So='Solziege:BAAALAAECgYIEAAAAA==.Sorrysussy:BAAALAAECgEIAQAAAA==.Souhila:BAAALAAECgYICgAAAA==.Souvlas:BAABLAAECoEbAAIOAAcIsxccRQDeAQAOAAcIsxccRQDeAQAAAA==.',St='Steemi:BAAALAAECgYICwAAAA==.Steeminator:BAABLAAECoEeAAMbAAgIiBRbPADhAQAbAAgIiBRbPADhAQAOAAcIZgx5igAnAQAAAA==.Stevéy:BAABLAAECoEWAAMIAAYIDwxsOgBZAQAIAAYIDwxsOgBZAQAXAAYIWwSoLADpAAAAAA==.Stingeh:BAAALAAECgQIBAABLAAECggIHQADAO8dAA==.Stravi:BAABLAAECoEVAAMLAAgIixqyEQAYAgALAAcIqRyyEQAYAgACAAEItwskEwE0AAAAAA==.',Su='Sunnyday:BAAALAADCggICAAAAA==.Superfreaky:BAAALAADCggICAAAAA==.Supernal:BAAALAAECgUIBQABLAAECggIHwATALwbAA==.',Sy='Sylvenia:BAAALAAECgUIBQAAAA==.',['Sï']='Sïnnsyk:BAAALAADCgYIBgABLAAECgYICgABAAAAAA==.',['Sø']='Sølvcent:BAAALAAECgYIBwAAAA==.',Te='Telra:BAAALAADCgYIBgAAAA==.',Th='Thehealer:BAAALAAECgQIBwABLAAECgcIBwABAAAAAA==.Thementor:BAAALAAECgYICwAAAA==.Thorock:BAAALAADCgQIBAAAAA==.',To='Tot:BAAALAAECgYIDAAAAA==.',Tr='Trempel:BAAALAAECgQIAgAAAA==.Trokara:BAABLAAECoEfAAITAAgINR7hEQCxAgATAAgINR7hEQCxAgAAAA==.Tryandie:BAABLAAECoEXAAIOAAgIoxc/OAAKAgAOAAgIoxc/OAAKAgAAAA==.Trylletøs:BAAALAAECgYIEgAAAA==.Trädet:BAAALAAECgcIEwAAAA==.',Tu='Tudella:BAABLAAECoEiAAIWAAgI1x8uBgDqAgAWAAgI1x8uBgDqAgAAAA==.Turboshooter:BAAALAAECgQIBAAAAA==.',Un='Unlimpower:BAAALAADCgYIBgAAAA==.Untouchable:BAAALAADCggICAAAAA==.',Ur='Ursador:BAAALAAECgYIAgAAAA==.Uruloki:BAAALAADCggICAAAAA==.',Us='Usedtobeabot:BAABLAAECoEjAAIeAAgIMhQoEgAiAgAeAAgIMhQoEgAiAgAAAA==.',Va='Vakhi:BAABLAAECoEcAAIfAAgIYRcLEgBLAgAfAAgIYRcLEgBLAgAAAA==.Vannesh:BAABLAAECoEcAAIIAAgIoxhNEwBwAgAIAAgIoxhNEwBwAgAAAA==.Vapenash:BAACLAAFFIEIAAIbAAMIJBGrDwDuAAAbAAMIJBGrDwDuAAAsAAQKgSUAAhsACAitIbUMABYDABsACAitIbUMABYDAAAA.',Ve='Verghast:BAAALAADCggICAAAAA==.',Vi='Viilieth:BAAALAAECgUIBQABLAAECggIHgAFAFkgAA==.',Vn='Vnero:BAABLAAECoEUAAIOAAgISA1pcgBfAQAOAAgISA1pcgBfAQAAAA==.',Vo='Vosita:BAAALAAECgEIAQAAAA==.',Xa='Xandem:BAAALAADCgQIBAAAAA==.',Xn='Xna:BAAALAAECggICAAAAA==.',Xr='Xray:BAAALAAECggIDgABLAAECggIFAAOALwQAA==.',Za='Zabkása:BAAALAADCggICAAAAA==.',Ze='Zenana:BAAALAADCggIDgAAAA==.Zeronine:BAAALAAECgYIDwABLAAFFAMIBwADAHUfAA==.',Zh='Zhantora:BAABLAAECoEgAAIMAAgIFhUBMQD2AQAMAAgIFhUBMQD2AQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end