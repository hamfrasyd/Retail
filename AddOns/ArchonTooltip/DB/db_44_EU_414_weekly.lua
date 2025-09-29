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
 local lookup = {'Shaman-Restoration','DeathKnight-Frost','Unknown-Unknown','Druid-Restoration','DemonHunter-Havoc','Paladin-Retribution','DeathKnight-Blood','Warrior-Protection','Priest-Shadow','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Devastation','Shaman-Enhancement','Monk-Windwalker','Monk-Brewmaster','Druid-Balance','Mage-Frost','Mage-Arcane','Paladin-Holy','DeathKnight-Unholy','Priest-Holy','DemonHunter-Vengeance','Mage-Fire','Warlock-Destruction','Monk-Mistweaver','Warlock-Demonology','Warlock-Affliction','Paladin-Protection',}; local provider = {region='EU',realm='DerMithrilorden',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarón:BAAALAADCggIEAABLAAFFAIIBQABAN8ZAA==.',Ac='Acavius:BAABLAAECoEXAAICAAcIVxmiYAABAgACAAcIVxmiYAABAgAAAA==.Acoxagan:BAAALAAECgYIEQAAAA==.',Af='Affomickii:BAAALAADCgEIAQAAAA==.Affotropia:BAAALAADCgYIBwAAAA==.',Ag='Agrippae:BAAALAAECgYIBgAAAA==.',Al='Alcina:BAAALAAECgMIAwAAAA==.Aleriana:BAAALAADCgcIEQABLAAECggICQADAAAAAA==.Alessâ:BAAALAAECgQIBAAAAA==.Aleynaa:BAAALAAECggIEAAAAA==.Alvari:BAAALAAECggICAAAAA==.',Am='Amidas:BAAALAAECgMIBQAAAA==.',An='Anganuk:BAAALAADCggIEAAAAA==.Ansin:BAABLAAECoEkAAIEAAgI6CICJgAkAgAEAAgI6CICJgAkAgAAAA==.',Ar='Ara:BAAALAAECgYIBgAAAA==.Arais:BAAALAADCgcIEwAAAA==.Armadeyra:BAABLAAECoEbAAIFAAgIfBPsYADcAQAFAAgIfBPsYADcAQAAAA==.Arrmazing:BAAALAADCgcIDgAAAA==.Arwensstern:BAAALAADCgYIBgAAAA==.',As='Asdromedos:BAACLAAFFIEHAAIGAAMITxK4LwCdAAAGAAMITxK4LwCdAAAsAAQKgTAAAgYACAgNHR05AGcCAAYACAgNHR05AGcCAAAA.Askalesia:BAAALAAECgcIEQAAAA==.Astarion:BAAALAAECgYICgAAAA==.',Au='Auralis:BAAALAADCggICAABLAADCggIEAADAAAAAA==.Aurion:BAAALAADCgcIEgAAAA==.',Av='Aventurian:BAAALAAECgIIBAAAAA==.Avéntinus:BAAALAAECgYIEQAAAA==.',Ay='Aydana:BAAALAADCggICAAAAA==.Ayur:BAAALAAECgYICwAAAA==.',Az='Azuron:BAABLAAECoEmAAIHAAgIEh+xCgCCAgAHAAgIEh+xCgCCAgAAAA==.',Ba='Badshooter:BAAALAAECgQIBAABLAAECggIJAADAAAAAQ==.Bariga:BAAALAAECgQICAAAAA==.',Be='Bearnose:BAACLAAFFIEgAAIEAAYI8hzAAQAUAgAEAAYI8hzAAQAUAgAsAAQKgSEAAgQACAgeJMsHAAoDAAQACAgeJMsHAAoDAAAA.Belamy:BAAALAAECggIDAAAAA==.',Bl='Blackschaman:BAAALAADCggIFgAAAA==.Bluki:BAAALAAECgYIDQAAAA==.',Bo='Bomradur:BAABLAAECoEnAAIIAAgIdBTUJQDSAQAIAAgIdBTUJQDSAQAAAA==.Boralius:BAAALAAECgEIAQAAAA==.',Br='Braendy:BAAALAADCgcIBwAAAA==.Bramgar:BAAALAAECggICQAAAA==.Brogan:BAAALAAECgMIBAAAAA==.Broguard:BAAALAADCgYIBgAAAA==.Brändet:BAAALAADCgQIBAABLAAECgYIEQADAAAAAA==.',Bu='Burnfight:BAAALAAECgMIAwABLAAECggIJAADAAAAAQ==.Butleer:BAAALAADCgEIAQAAAA==.',['Bû']='Bûrzum:BAAALAADCggICAAAAA==.',Ca='Caramel:BAABLAAECoEYAAIBAAYI6Ai3vQDKAAABAAYI6Ai3vQDKAAAAAA==.',Cb='Cbum:BAAALAAECggICAAAAA==.',Ce='Celdaron:BAAALAAECgcIEwABLAAECggIEgADAAAAAA==.',Ch='Cherrypepsi:BAAALAAECgQIBgAAAA==.',Cl='Cly:BAAALAAECgIIAgAAAA==.',Co='Cochones:BAABLAAECoEWAAIJAAYIVwg4XAAaAQAJAAYIVwg4XAAaAQAAAA==.Coolrunnings:BAAALAAECgQIBgABLAAECggIJAADAAAAAQ==.',Cr='Croonos:BAAALAAECgIIAgAAAA==.Cryp:BAAALAADCggIDwAAAA==.',Da='Dagum:BAAALAADCggIFAAAAA==.Dane:BAAALAAECgcICAAAAA==.Darkangell:BAAALAADCgIIAgAAAA==.Darkjii:BAAALAADCggICAAAAA==.Daryun:BAAALAAECgYIDAAAAA==.',De='Deathtoll:BAAALAAECgIIAgAAAA==.Dejura:BAAALAAECgUIBQAAAA==.Delios:BAAALAADCgQIBQAAAA==.Dem:BAAALAADCggIGgAAAA==.Demonia:BAAALAAECgcIDwAAAA==.Dendra:BAAALAADCgIIAgAAAA==.',Dh='Dhârá:BAAALAADCggIEAAAAA==.',Do='Doty:BAAALAAECgEIAQAAAA==.',Dr='Druidikus:BAAALAADCggICAAAAA==.Druinos:BAAALAAECgcIBwAAAA==.Dryex:BAAALAADCggICAAAAA==.Drágomir:BAAALAADCgIIAgAAAA==.',Du='Durane:BAAALAADCggICAAAAA==.',['Dä']='Dämmer:BAAALAADCgQIBAAAAA==.Dämonin:BAAALAAECgcIDQAAAA==.',['Dæ']='Dæx:BAAALAAECgYIDAAAAA==.',['Dí']='Díggor:BAAALAADCggIGAAAAA==.Díru:BAACLAAFFIEOAAIEAAUIQwwfBgBeAQAEAAUIQwwfBgBeAQAsAAQKgRUAAgQACAiiDkFWAFQBAAQACAiiDkFWAFQBAAAA.',Ei='Eisenwolf:BAAALAAECgYIEgAAAA==.',El='Eldunari:BAAALAAECgQIBwAAAA==.Elentàri:BAAALAAECgMIBgAAAA==.',Em='Emphira:BAAALAAECgYIEQAAAA==.',Er='Erdbärsahne:BAAALAADCggIFwAAAA==.',Es='Eskair:BAABLAAECoEsAAIKAAgI8x93GQDMAgAKAAgI8x93GQDMAgAAAA==.Esmé:BAAALAADCgYIBgAAAA==.',Ex='Excelsior:BAAALAAECgEIAQAAAA==.Exodus:BAABLAAECoEWAAIEAAYINRL0bQAMAQAEAAYINRL0bQAMAQAAAA==.Exrar:BAAALAADCggIEQAAAA==.',Fa='Faylith:BAABLAAECoEaAAIFAAYI6iACUAAIAgAFAAYI6iACUAAIAgABLAAFFAIIBQABAN8ZAA==.',Fe='Fenerica:BAAALAADCggIFwAAAA==.Fenny:BAAALAADCgcIEgAAAA==.',Fi='Finnson:BAAALAADCggIFgAAAA==.Fireburner:BAAALAAECggIJAAAAQ==.',Fl='Flexto:BAAALAADCgYIBgAAAA==.',Fu='Furianix:BAAALAAECgYIDwAAAA==.Furin:BAAALAADCggIFwABLAAECggIJQALADIjAA==.Furiøus:BAAALAADCggIEgAAAA==.',Ga='Gareka:BAAALAADCgUIAQAAAA==.',Ge='Gerrî:BAABLAAECoEgAAIMAAgI6RJuIQDxAQAMAAgI6RJuIQDxAQAAAA==.',Gi='Gizisham:BAACLAAFFIEIAAINAAIIhha4BACiAAANAAIIhha4BACiAAAsAAQKgRQAAg0ABggpHwoMAAoCAA0ABggpHwoMAAoCAAAA.Gizordk:BAAALAAECgYIBgAAAA==.',Go='Gobbiee:BAAALAADCggICAAAAA==.Gomez:BAAALAADCggICAAAAA==.Goshan:BAAALAADCggIDQAAAA==.',Gr='Grandos:BAACLAAFFIEGAAIOAAII1xGODQCSAAAOAAII1xGODQCSAAAsAAQKgRkAAw4ACAgJFooZAA0CAA4ACAgJFooZAA0CAA8AAQjMC/VAADEAAAAA.Grathok:BAAALAADCgcICAAAAA==.Gridy:BAAALAADCgcIEQAAAA==.',Gs='Gschafaar:BAABLAAECoEUAAIQAAYIxCHgHABPAgAQAAYIxCHgHABPAgAAAA==.',Gw='Gwifith:BAAALAAECgQIBgAAAA==.',Ha='Haava:BAAALAADCgQIBwAAAA==.Hanke:BAAALAAECgMIBQABLAAECgMIBgADAAAAAA==.Hazzenpala:BAACLAAFFIERAAIGAAUI8xq5BQC9AQAGAAUI8xq5BQC9AQAsAAQKgS8AAgYACAi0JQcGAGUDAAYACAi0JQcGAGUDAAAA.',He='Healmaster:BAAALAAECgYIEQAAAA==.Heidewitzka:BAAALAADCgcIBwAAAA==.Heilsimir:BAAALAAECgYIBgAAAA==.Hestia:BAAALAADCgYIBgAAAA==.',Hi='Hindokush:BAAALAADCgYIBgAAAA==.',Ho='Holydox:BAAALAADCgQIBAAAAA==.Holymoli:BAAALAAECgIIAgAAAA==.Hopeful:BAABLAAECoEXAAIEAAYIZxBnXgA6AQAEAAYIZxBnXgA6AQABLAAECggIJQARADkeAA==.Horks:BAAALAAECgYICQAAAA==.Hornia:BAAALAAECgEIAQAAAA==.',Hu='Humdy:BAAALAAECggIDAAAAA==.',Ic='Icd:BAAALAADCgYIBgAAAA==.Icécube:BAAALAADCggIEAABLAAFFAIIBQABAN8ZAA==.',Il='Ileila:BAAALAAECgQIBAAAAA==.Illuminor:BAABLAAECoElAAILAAgIMiN8CAAaAwALAAgIMiN8CAAaAwAAAA==.Illyriá:BAABLAAECoEWAAISAAYI7gbzngASAQASAAYI7gbzngASAQAAAA==.',Is='Iskalder:BAAALAADCggICAAAAA==.Isuna:BAAALAAECgIIAgABLAAFFAIIAgADAAAAAA==.',Ja='Jadyeracrow:BAAALAADCggIDQAAAA==.',Je='Jeany:BAAALAADCgcIDQAAAA==.',Jo='Jon:BAABLAAECoEaAAIOAAcIUhGLJQChAQAOAAcIUhGLJQChAQAAAA==.',Ka='Kakamazo:BAAALAAECgYICAAAAA==.Kaltesherz:BAAALAAECgYIEAAAAA==.Kamaro:BAAALAAECgUIEgABLAAECgcIKgADAAAAAQ==.Katika:BAAALAAECgYIBgAAAA==.Katsien:BAAALAAECgYIBgAAAA==.',Ke='Kecklienchen:BAAALAADCggIGAAAAA==.Keyterrorist:BAAALAADCgYIDAAAAA==.',Ki='Kiyarrâ:BAABLAAECoEcAAIRAAgIwBK4HgABAgARAAgIwBK4HgABAgAAAA==.',Ko='Koji:BAAALAADCgYIBgABLAAECggIGgACAMMjAA==.Kojiro:BAAALAADCgUIBQABLAAECggIGgACAMMjAA==.',Kr='Krachbu:BAAALAAECgMIBAAAAA==.Krístoff:BAABLAAECoEfAAMKAAgIVx+KIwCVAgAKAAgIVx+KIwCVAgALAAII+RGmlQBsAAAAAA==.',Ku='Kumako:BAAALAADCgcIEgAAAA==.Kuzaku:BAABLAAECoEaAAICAAgIwyPFGwDkAgACAAgIwyPFGwDkAgAAAA==.',['Kê']='Kêcklienchen:BAAALAADCggIEwAAAA==.',La='Lakotas:BAABLAAECoEUAAIGAAYInQ15twBVAQAGAAYInQ15twBVAQAAAA==.',Le='Leconer:BAABLAAECoEbAAITAAgIjxrqEQBcAgATAAgIjxrqEQBcAgAAAA==.Lewar:BAABLAAECoElAAIFAAgIOBvwNQBfAgAFAAgIOBvwNQBfAgAAAA==.',Li='Lightkeeper:BAABLAAECoElAAIRAAgIOR5/CwDHAgARAAgIOR5/CwDHAgAAAA==.Linnik:BAAALAAECgQIBgAAAA==.Liondra:BAABLAAECoElAAMCAAgIJRr0OgBmAgACAAgIsBn0OgBmAgAUAAMIuxWFOwDPAAAAAA==.',Lo='Lorania:BAAALAADCggIEAAAAA==.Lorey:BAAALAAECgIIAwAAAA==.Lorinia:BAAALAADCggICAABLAAECggIJQALADIjAA==.',Lu='Lukbox:BAAALAAECgUICAAAAA==.Lundizo:BAAALAAECgUIBQAAAA==.Luníkoff:BAAALAADCggICwAAAA==.',Ly='Lyrià:BAAALAADCggICAAAAA==.',['Lî']='Lînnck:BAAALAAECgYIBgAAAA==.',['Lü']='Lüise:BAAALAADCgIIAgAAAA==.Lünöa:BAAALAAECgIIAwAAAA==.',Ma='Maelun:BAAALAAECgYIEQAAAA==.Maerlin:BAAALAADCggIHAAAAA==.Magmatûs:BAAALAADCgEIAQAAAA==.Marmax:BAABLAAECoEbAAIUAAcIvgsuJgByAQAUAAcIvgsuJgByAQAAAA==.Marmex:BAAALAADCgQIBAAAAA==.Maruki:BAAALAAECgYICQABLAAECgYIEQADAAAAAA==.Marunor:BAAALAADCggIEAAAAA==.Maschin:BAAALAAECgcIAQAAAA==.Mawa:BAABLAAECoEVAAMJAAYIrwrPVAA9AQAJAAYIrwrPVAA9AQAVAAEILwQiqAAqAAAAAA==.',Mc='Mccragg:BAAALAADCgYIBgAAAA==.',Me='Meko:BAABLAAECoEfAAIGAAgI8yJ2GAD5AgAGAAgI8yJ2GAD5AgAAAA==.Melanix:BAAALAAECgEIAQAAAA==.',Mi='Michaelixx:BAAALAAECgEIAgAAAA==.Miloo:BAAALAAECgYIBwAAAA==.Minze:BAAALAAECgYIBgAAAA==.Mirika:BAAALAAECggICAAAAA==.Miz:BAAALAADCggIFgAAAA==.',Mo='Moitai:BAAALAADCgQIBAAAAA==.Moldred:BAAALAADCgEIAQAAAA==.Morima:BAAALAAECgEIAQAAAA==.Moritana:BAAALAADCgcIDgAAAA==.Morphdeamon:BAABLAAECoEWAAMWAAYIcBpKKwAmAQAFAAYIBBgPjQB+AQAWAAQIvxtKKwAmAQABLAAECggIHgAMAP4cAA==.Mozzo:BAABLAAECoEZAAMXAAcI/wa8DQASAQASAAcIbAVqkwA2AQAXAAYI9Aa8DQASAQAAAA==.',Mu='Mubarak:BAAALAADCgEIAQAAAA==.Munuun:BAAALAAECgYICQAAAA==.Murdil:BAAALAAECgYIEQAAAA==.',My='Myouzó:BAABLAAECoEwAAIHAAgIxR2PCgCFAgAHAAgIxR2PCgCFAgAAAA==.Myrael:BAABLAAECoEpAAIVAAgIqB5ZEADPAgAVAAgIqB5ZEADPAgAAAA==.Mystîque:BAABLAAECoEUAAIYAAYIsgWWmAACAQAYAAYIsgWWmAACAQABLAAECgYIGAAQADUMAA==.',['Mä']='Märlien:BAAALAADCggIFAAAAA==.',['Mè']='Mèra:BAAALAAECgYICgAAAA==.',['Mê']='Mêrlín:BAAALAADCggIKQAAAA==.',Na='Nadimchen:BAAALAAECggICAAAAA==.Nagut:BAAALAADCggIFwAAAA==.Nakorem:BAAALAAECgYICAAAAA==.Nakwa:BAAALAADCggIDgAAAA==.Nashsven:BAAALAADCgIIAgAAAA==.',Ni='Nichaun:BAABLAAECoEfAAIZAAgILQ7BIQBnAQAZAAgILQ7BIQBnAQAAAA==.Niirax:BAAALAAECggICAAAAA==.Nikkee:BAAALAADCggIGAAAAA==.Ninsles:BAAALAAECgMIAwAAAA==.',No='Nokash:BAAALAAECgIIAgAAAA==.Norania:BAAALAADCgcIBwAAAA==.Noricul:BAABLAAECoEmAAMGAAgIjxW4WQALAgAGAAgIjxW4WQALAgATAAII7QTFYABWAAAAAA==.Norin:BAABLAAECoEuAAMPAAgIpCJFBgDyAgAPAAgIpCJFBgDyAgAOAAIIMgGsYQALAAAAAA==.Notagrizzly:BAAALAAECgUIBQABLAAECggICQADAAAAAA==.',['Ná']='Náfalia:BAABLAAECoEeAAIMAAgI/hwAEACkAgAMAAgI/hwAEACkAgAAAA==.',['Né']='Néele:BAAALAADCgYICQAAAA==.',['Nó']='Nómin:BAAALAAECgYIDwAAAA==.',Ob='Obscurus:BAAALAADCggIFQAAAA==.',Ov='Oversize:BAAALAAECgYIDgAAAA==.',Pa='Paladrin:BAAALAADCggIDgAAAA==.Palomino:BAABLAAECoEYAAIQAAYINQyGWQAWAQAQAAYINQyGWQAWAQAAAA==.',Pi='Piorun:BAABLAAECoEUAAIVAAcIWgxvVgBZAQAVAAcIWgxvVgBZAQAAAA==.Pip:BAAALAAECgYICwAAAA==.',Po='Poi:BAAALAAECgYICwAAAA==.Polarion:BAAALAADCgcIEgAAAA==.',Pr='Prakkz:BAAALAADCgUIBQAAAA==.',Pu='Puren:BAACLAAFFIEGAAIBAAIInRHXMAB8AAABAAIInRHXMAB8AAAsAAQKgRkAAgEACAjbGjcoAE4CAAEACAjbGjcoAE4CAAAA.',['Pæ']='Pæx:BAAALAAECgYIBgAAAA==.',Qu='Quastos:BAAALAADCgcIFQAAAA==.',Ra='Rakhar:BAAALAADCggIEAAAAA==.Ralanji:BAAALAAECgYIEgAAAA==.Razzulmage:BAAALAAFFAIIAgAAAA==.',Re='Reesi:BAABLAAECoEXAAIYAAYI+AczkwASAQAYAAYI+AczkwASAQAAAA==.Rentaheal:BAAALAADCgcIBwAAAA==.',Ri='Ribaldcorelo:BAAALAADCggIHQAAAA==.Rihoki:BAAALAAECggICAAAAA==.Riû:BAAALAADCgQIBAAAAA==.',Ro='Ronotron:BAAALAAECgEIAQAAAA==.Rosalinde:BAAALAADCggIDwAAAA==.Roxus:BAAALAADCggIDgAAAA==.',Ru='Ruki:BAAALAAECgYIEQAAAA==.Rushuna:BAAALAAECgUIBQAAAA==.',Ry='Rynu:BAAALAAECgEIAQAAAA==.',Sa='Sahnesteif:BAAALAADCgUIBQAAAA==.Sallykitty:BAABLAAECoEvAAIVAAgIKQ3dSgCFAQAVAAgIKQ3dSgCFAQAAAA==.Samweiss:BAAALAAECggIEAAAAA==.Saphiranda:BAAALAAECggICAAAAA==.Sarthara:BAABLAAECoEYAAIFAAgIdRKWTAASAgAFAAgIdRKWTAASAgABLAAECggILgAPAKQiAA==.Sayablanka:BAAALAADCggICAAAAA==.',Sc='Scharella:BAAALAADCgcIDgAAAA==.Schaumfolger:BAABLAAECoEWAAILAAYIHgW8eQDLAAALAAYIHgW8eQDLAAAAAA==.Schneehasi:BAAALAADCggIHAAAAA==.',Se='Seraxi:BAAALAAECgYICwABLAAECgYIDAADAAAAAA==.',Sh='Shadowigor:BAAALAADCggICAAAAA==.Shadowrayne:BAAALAAECgYIEgAAAA==.Shamanalekum:BAACLAAFFIEFAAIBAAII3xn8IgCcAAABAAII3xn8IgCcAAAsAAQKgRoAAgEABggUH9RHAN0BAAEABggUH9RHAN0BAAAA.Shamanski:BAABLAAECoEdAAMNAAgIuBncBwBtAgANAAgIuBncBwBtAgABAAEIZwz3DwEsAAAAAA==.Shangchi:BAAALAAECgEIAQABLAAFFAIIBQABAN8ZAA==.Shaxire:BAAALAADCggICAAAAA==.Shaylah:BAAALAADCggIFgAAAA==.Shrok:BAAALAAECgMIAwAAAA==.',Si='Siluettha:BAAALAADCgcIBwAAAA==.Sinesefer:BAAALAADCggIFQAAAA==.',Sk='Skydo:BAAALAAFFAIIAgAAAA==.Skydoo:BAAALAAECgcIDgAAAA==.',Sl='Sloia:BAAALAADCgcIGgAAAA==.Slyriass:BAAALAAECgcIDQAAAA==.',So='Solix:BAAALAAECgYICgAAAA==.',Sp='Spyró:BAAALAAECgcIDgAAAA==.',St='Stapfan:BAAALAADCgIIAgAAAA==.',Su='Sunrisei:BAAALAADCgYIDAAAAA==.',Sy='Sybara:BAAALAAECggIAwABLAAECggILgAPAKQiAA==.Sylthara:BAABLAAECoElAAQaAAgINRyOCgCkAgAaAAgINRyOCgCkAgAYAAcIPws7cQBtAQAbAAYItQxaFQBMAQAAAA==.',['Så']='Sådness:BAAALAADCggIEAAAAA==.',Ta='Takia:BAAALAAECgQIBwAAAA==.Tapion:BAAALAADCgcIDgAAAA==.Taraan:BAABLAAECoEbAAIBAAcIWxTVZgCHAQABAAcIWxTVZgCHAQAAAA==.',Te='Teldur:BAAALAAECgYIDgAAAA==.',Th='Thalorien:BAAALAADCgcIDgAAAA==.Thingol:BAAALAADCgYIBgAAAA==.Thorân:BAABLAAECoEZAAIBAAcI4hvCOAAPAgABAAcI4hvCOAAPAgAAAA==.Thyr:BAAALAAECggIEAAAAA==.Thòran:BAAALAAECgEIAQABLAAECgcIGQABAOIbAA==.Thôrân:BAAALAADCgUIBQABLAAECgcIGQABAOIbAA==.',Ti='Tiramisu:BAAALAADCggICwAAAA==.',To='Tomatensauce:BAABLAAECoEYAAIKAAcIrRjbYADEAQAKAAcIrRjbYADEAQAAAA==.Torenga:BAAALAADCgcICAAAAA==.Tormentus:BAAALAADCggIFgAAAA==.',Ts='Tsutey:BAAALAAECggIBAAAAA==.',Tu='Tuura:BAAALAAECgcIBQAAAA==.',['Tá']='Tálari:BAABLAAECoEnAAMRAAgISibgAACFAwARAAgISibgAACFAwASAAEIFCDq0ABcAAAAAA==.',Va='Valerious:BAAALAAECgYIEQAAAA==.',Ve='Velendyl:BAAALAADCgYIBgAAAA==.Vemeria:BAABLAAECoEaAAIVAAcIrQYAZAArAQAVAAcIrQYAZAArAQAAAA==.',Vi='Vidrix:BAAALAADCgYIDQAAAA==.Virusz:BAAALAADCgcICgAAAA==.',Vo='Volksworgenn:BAAALAADCgYIDAAAAA==.Vollstrécker:BAAALAADCggIMwAAAA==.Volodymyr:BAAALAAECgMIAwAAAA==.',Wa='Walahfrid:BAABLAAECoEmAAIVAAgILSOlCAAWAwAVAAgILSOlCAAWAwAAAA==.Walsh:BAAALAADCggICwAAAA==.War:BAAALAAECgYIBgAAAA==.',We='Wetzler:BAAALAADCgcIDgAAAA==.',Wi='Willgates:BAACLAAFFIEQAAMYAAUIjCA0CADvAQAYAAUIjCA0CADvAQAaAAIIjhNFEACcAAAsAAQKgRcABBgACAiaJKsSAP0CABgACAiYJKsSAP0CABoABQimFuNJACMBABsAAghpHTIkAKkAAAAA.Wintermond:BAAALAADCgYIBgABLAAECggIKQAVAKgeAA==.',Wo='Worlly:BAABLAAECoEoAAMaAAgIOCD7CgCfAgAaAAgIYh77CgCfAgAbAAcIJR+NBQBsAgAAAA==.',Wu='Wusaa:BAAALAADCggICgAAAA==.Wuschbusch:BAAALAAECgIIAgAAAA==.',Xa='Xaáru:BAAALAAECggIEAAAAA==.',Xe='Xellesia:BAAALAADCgcIBwABLAAECgYIEQADAAAAAA==.Xenor:BAAALAAECgMIAwABLAAFFAIIBgAOANcRAA==.',Xo='Xolîa:BAAALAADCggIBAAAAA==.',Ya='Yanua:BAAALAADCggICAAAAA==.Yappies:BAACLAAFFIEFAAIFAAIIdBaaOQCJAAAFAAIIdBaaOQCJAAAsAAQKgRwAAgUACAjuFQFGACYCAAUACAjuFQFGACYCAAAA.',Ye='Yelenaay:BAAALAAECgIIAgAAAA==.',Yo='Yosai:BAAALAADCgQIBAABLAAECggIGgACAMMjAA==.',Yu='Yukî:BAACLAAFFIEKAAIEAAMI9xlKCQAOAQAEAAMI9xlKCQAOAQAsAAQKgSgAAwQACAi6It8KAOoCAAQACAi6It8KAOoCABAABgiSFdo+AIkBAAAA.Yuyanus:BAAALAAECggICAAAAA==.',Za='Zarkarion:BAAALAADCggICAAAAA==.Zavi:BAAALAAECgYIDAAAAA==.',Ze='Zerpu:BAAALAADCgcICAAAAA==.',Zi='Zimbil:BAAALAAECggIBwAAAA==.',Zo='Zouh:BAABLAAECoEWAAIOAAYIWRhTIgC7AQAOAAYIWRhTIgC7AQAAAA==.',Zu='Zussa:BAAALAAECgIIAgAAAA==.',Zw='Zwiebelchen:BAAALAADCggICAAAAA==.',['Àa']='Àaron:BAABLAAECoEYAAIcAAgIqwAQaQAOAAAcAAgIqwAQaQAOAAABLAAFFAIIBQABAN8ZAA==.',['Àl']='Àlysth:BAAALAAECgIIAgABLAAECgcIGQABAOIbAA==.',['Án']='Ángélus:BAAALAAECgYIDAAAAA==.',['Áá']='Áárón:BAAALAADCgYIBgABLAAFFAIIBQABAN8ZAA==.',['Âl']='Âluka:BAABLAAECoEaAAIYAAcIHQxUhQA5AQAYAAcIHQxUhQA5AQAAAA==.',['Âm']='Âmabella:BAAALAAECgEIAQAAAA==.',['Ãr']='Ãryulie:BAAALAAECgYICgAAAA==.',['Æl']='Ælune:BAAALAADCgQIBAAAAA==.',['Ær']='Ærdsturm:BAAALAADCggICAAAAA==.',['Ód']='Ódina:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end