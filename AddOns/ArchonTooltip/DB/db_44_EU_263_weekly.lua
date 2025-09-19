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
 local lookup = {'Unknown-Unknown','Rogue-Subtlety','Rogue-Assassination','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','Paladin-Protection','Shaman-Enhancement','Warrior-Fury','Druid-Balance','Druid-Restoration','Priest-Shadow','Mage-Frost','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Mage-Arcane','Mage-Fire','Hunter-Survival',}; local provider = {region='EU',realm='Bloodfeather',name='EU',type='weekly',zone=44,date='2025-09-06',data={Al='Aldanil:BAAALAADCggIFgABLAAECgYIBgABAAAAAA==.Aldriel:BAACLAAFFIEFAAMCAAMI3AmYBgCFAAADAAII2Q05CwCnAAACAAII4gOYBgCFAAAsAAQKgSAAAwMACAg0G7ANAH8CAAMACAgZG7ANAH8CAAIABwiBDN8RAGABAAAA.',An='Antimage:BAAALAADCgEIAQAAAA==.Antimuu:BAACLAAFFIEIAAIEAAMISRPPBgADAQAEAAMISRPPBgADAQAsAAQKgRgAAgQACAgyIAARANwCAAQACAgyIAARANwCAAAA.',Ar='Arathene:BAACLAAFFIEIAAIFAAMIYw+7BwD6AAAFAAMIYw+7BwD6AAAsAAQKgR8AAgUACAhfIcUMAPcCAAUACAhfIcUMAPcCAAAA.Arte:BAAALAADCgcIDwAAAA==.',As='Astoria:BAAALAADCgYIBgABLAAECggIGAAGAP0aAA==.',At='Ataraxy:BAAALAADCggICAABLAAFFAMICAAHAOEWAA==.',Av='Avakin:BAACLAAFFIEIAAIHAAMIqB5hAgAaAQAHAAMIqB5hAgAaAQAsAAQKgR8AAgcACAg8I/YBAD0DAAcACAg8I/YBAD0DAAAA.',Ax='Axis:BAAALAAECgUIBQABLAAFFAUIDQABAAAAAQ==.',Ba='Bachius:BAAALAADCgQIBAAAAA==.Bajceps:BAAALAADCggIFgAAAA==.Balcones:BAABLAAECoEZAAQIAAgIhhcpCgBdAgAIAAgIhhcpCgBdAgAJAAgICwswOgCQAQAKAAEI5xeaKwBRAAAAAA==.Ball:BAAALAADCggICAAAAA==.Balra:BAAALAADCggICAAAAA==.',Be='Beargrylls:BAAALAAECgYIBgABLAAFFAMICAAHAOEWAA==.Beregor:BAAALAAECgMIAwAAAA==.Berttdk:BAAALAAECgYIBQAAAA==.',Bi='Bigfistalert:BAAALAADCgcIBwAAAA==.Bigzortax:BAAALAADCgYIBgAAAA==.Bikdmg:BAAALAADCgcIBwAAAA==.Bip:BAAALAADCgYIBgAAAA==.',Bl='Blackfyre:BAACLAAFFIEFAAMLAAIIuRciCQCqAAALAAIIuRciCQCqAAAMAAEI2wDfCgAwAAAsAAQKgSAAAwsACAjXIKEFAAcDAAsACAjXIKEFAAcDAAwACAioCjYPAIkBAAAA.Blade:BAAALAAECgUIBQABLAAFFAMIBgAEAJ0SAA==.Bloodyrain:BAAALAAECgYICwAAAA==.Blueeyes:BAAALAAECgcIDgAAAA==.',Bo='Bobjohnny:BAAALAAECgcICAAAAA==.Borjeq:BAAALAAECgcIEgAAAA==.',Br='Brakstad:BAABLAAECoEVAAMNAAgIRhq5HgAaAgANAAcIWhm5HgAaAgAOAAQIcBTXZAD9AAAAAA==.',Bu='Bubbleguy:BAAALAAECgcIEgAAAA==.Bunnymann:BAABLAAECoEWAAMPAAgIeh38DgDAAgAPAAgIUx38DgDAAgAQAAMIkBhjUQC4AAAAAA==.Buq:BAAALAAECgIIAgAAAA==.',Ca='Carwick:BAABLAAECoEYAAIFAAgIiB5SGACdAgAFAAgIiB5SGACdAgAAAA==.',Ch='Choccie:BAAALAAECgcIEAAAAA==.Chriska:BAAALAADCgcICQAAAA==.Chromatica:BAAALAADCgMIAwAAAA==.',Cr='Crazath:BAAALAAECgcIDAAAAA==.',Cs='Csempe:BAAALAADCgcIEQAAAA==.',Cu='Cupcakedemon:BAAALAAECgYIBgAAAA==.',Da='Dalatu:BAACLAAFFIENAAIRAAUISBQrAQC5AQARAAUISBQrAQC5AQAsAAQKgSAAAhEACAipHUMMAKwCABEACAipHUMMAKwCAAAA.Darion:BAAALAAECgYIDAAAAA==.Darkjukka:BAACLAAFFIEIAAISAAMIGiMnAQAyAQASAAMIGiMnAQAyAQAsAAQKgR8AAhIACAhkJdIAAHQDABIACAhkJdIAAHQDAAAA.',De='Deepbear:BAAALAADCgYIBgABLAAECggIHgATAOAgAA==.Deepspark:BAABLAAECoEeAAITAAgI4CDzAQADAwATAAgI4CDzAQADAwAAAA==.Delyraidë:BAABLAAECoEYAAMGAAgI/RpUBgCgAgAGAAgI/RpUBgCgAgAFAAIILAIFxgA5AAAAAA==.Demonui:BAAALAAECgYICwAAAA==.',Di='Digtini:BAAALAAECgQIBQAAAA==.Dina:BAABLAAECoEYAAIUAAgIrRQVHQAwAgAUAAgIrRQVHQAwAgAAAA==.Dip:BAAALAAECgIIAQAAAA==.',Do='Donkraften:BAAALAADCggICAAAAA==.Dorius:BAAALAAECgQIBQAAAA==.',Dr='Dracsel:BAAALAAECgcIBwAAAA==.Drainwife:BAACLAAFFIEKAAMJAAUIPBqcAwCMAQAJAAQIdBmcAwCMAQAIAAII7h+9AwC9AAAsAAQKgR8ABAkACAjZIxEIABMDAAkACAi4IhEIABMDAAoABwjDEhoGACoCAAgAAgibJv0/AOEAAAAA.Drakkaris:BAAALAADCggIEAAAAA==.',Du='Durzag:BAABLAAECoEYAAIQAAgIgxdHGAAmAgAQAAgIgxdHGAAmAgAAAA==.',Dw='Dwarvlars:BAAALAAECgYICgAAAA==.',Eb='Ebrel:BAAALAAECgYIDwAAAA==.',Ed='Edinprime:BAAALAADCggIDAAAAA==.',Eh='Ehrys:BAABLAAECoEWAAIRAAcIXxpiGQAxAgARAAcIXxpiGQAxAgAAAA==.',El='Eldrid:BAAALAAECgQIBgAAAA==.Elee:BAAALAADCggICAAAAA==.Elf:BAAALAAECgYICAAAAA==.Elie:BAAALAAFFAMIBQAAAQ==.',Em='Emberlyn:BAAALAADCgEIAQAAAA==.Emidar:BAACLAAFFIEIAAIEAAMI0iAjBAAsAQAEAAMI0iAjBAAsAQAsAAQKgR8AAgQACAhcJoABAH0DAAQACAhcJoABAH0DAAAA.Emofrost:BAAALAADCgQIBAAAAA==.',Ep='Epicone:BAAALAADCgMIAwABLAAECggIFgAPAHodAA==.',Er='Erak:BAAALAADCggICAAAAA==.Erooxdruid:BAACLAAFFIEMAAMVAAUIIxw7AgAxAQAVAAMI6R07AgAxAQAWAAMIBhuFAwAGAQAsAAQKgSAAAxUACAgWJH8CAFkDABUACAgWJH8CAFkDABYACAieDtA0AFYBAAAA.',Et='Etra:BAAALAADCgYIBgAAAA==.Etran:BAAALAAECgUIBwAAAA==.',Ev='Evejk:BAAALAAECgQIBAAAAA==.Evenia:BAACLAAFFIEIAAIPAAMIWhZRBAAAAQAPAAMIWhZRBAAAAQAsAAQKgR8AAg8ACAiTH+oLAOECAA8ACAiTH+oLAOECAAAA.Evoke:BAAALAADCgYIBgAAAA==.Evokeli:BAAALAADCgYIBgAAAA==.Evopei:BAAALAADCgcIEwAAAA==.',Ex='Executie:BAAALAADCggIFQABLAAECgcIEQABAAAAAA==.',Fe='Felglider:BAAALAADCgcICAABLAAECgcIEgABAAAAAA==.Fermoza:BAACLAAFFIEMAAINAAUI5huAAQDoAQANAAUI5huAAQDoAQAsAAQKgR8AAg0ACAg0JT4DAFoDAA0ACAg0JT4DAFoDAAAA.',Fl='Floris:BAAALAADCggIEAAAAA==.',Fo='Fohi:BAAALAAECgYICQAAAA==.',Fr='Frostfyre:BAAALAAECgYIBgABLAAFFAIIBQALALkXAA==.Frostvoid:BAACLAAFFIEIAAIXAAMItx94AwAvAQAXAAMItx94AwAvAQAsAAQKgRgAAhcACAhwI4kEADkDABcACAhwI4kEADkDAAAA.',Fu='Fudokarion:BAAALAADCggIAQAAAA==.Fudoki:BAAALAAECgcIEAAAAA==.Fudokiel:BAAALAADCgEIAQAAAA==.',Fw='Fwiti:BAAALAAFFAUIDQAAAQ==.',Gi='Gidorah:BAAALAADCgQIBAAAAA==.Girthp:BAABLAAECoEeAAIXAAgIYB2iCwDPAgAXAAgIYB2iCwDPAgAAAA==.',Gl='Glinda:BAAALAAECgUIBQAAAA==.',Go='Gobsmaker:BAAALAADCgMIBAAAAA==.Goofydk:BAAALAADCggICAAAAA==.Goresorrow:BAAALAAECgQIAwAAAA==.',Ha='Haelinn:BAAALAAECgQIBAAAAA==.Haki:BAAALAAECgMIBAAAAA==.',He='Healur:BAAALAAECgQIBAABLAAECgcIEAABAAAAAA==.Hellzpals:BAAALAADCggICAAAAA==.',Hi='Hiimlorenzo:BAAALAADCgEIAQAAAA==.',Ho='Holyskyer:BAAALAADCgcIBwAAAA==.Hopsukka:BAAALAAECgUIBQAAAA==.Hotgirth:BAAALAADCggICAABLAAECggIHgAXAGAdAA==.',Ic='Icastspells:BAAALAADCggIFgAAAA==.',Im='Iminari:BAAALAADCggIDwAAAA==.Imperius:BAAALAAECggIDQAAAA==.Imrik:BAAALAAECgYIBQAAAA==.',Ja='Jameroz:BAAALAAECgUIDQAAAA==.Jammer:BAACLAAFFIEGAAIYAAMIEAu9AgC9AAAYAAMIEAu9AgC9AAAsAAQKgR0AAhgACAgaIwoEAA8DABgACAgaIwoEAA8DAAAA.Jappew:BAACLAAFFIEFAAMJAAMISCOnCwDLAAAJAAIIgiOnCwDLAAAIAAEI1CIiDgBmAAAsAAQKgRUABAkACAgpI+4JAP0CAAkACAgpI+4JAP0CAAoABAjdGbYRAEgBAAgAAQhOHUtdAFAAAAAA.Jawsy:BAAALAADCgUIBQAAAA==.',Je='Jessâ:BAACLAAFFIELAAIPAAQILhVZAQBfAQAPAAQILhVZAQBfAQAsAAQKgSAAAg8ACAhEI+gFACoDAA8ACAhEI+gFACoDAAAA.',Jk='Jkillop:BAAALAADCgYIBwAAAA==.',Jo='Joikabyte:BAEBLAAECoEYAAIRAAgI8SN3AQBcAwARAAgI8SN3AQBcAwAAAA==.',Ju='Juicyscale:BAABLAAECoEWAAMLAAgIYhq2DwBeAgALAAgIYhq2DwBeAgAMAAEI1ggmJQAsAAAAAA==.',Ka='Kakansson:BAAALAADCggICwAAAA==.Kamiipappi:BAACLAAFFIEIAAIRAAMImhoKBQASAQARAAMImhoKBQASAQAsAAQKgR8AAhEACAj9F8EYADYCABEACAj9F8EYADYCAAAA.Katamurr:BAAALAAECgIIAgAAAA==.Kaunisnaama:BAAALAAECgQIBAAAAA==.Kazumi:BAABLAAECoEYAAIXAAgI5wUeQwAFAQAXAAgI5wUeQwAFAQAAAA==.',Ke='Kelbner:BAAALAADCgYIBgAAAA==.Kenonk:BAABLAAECoEgAAIHAAgIzh1aBgCZAgAHAAgIzh1aBgCZAgAAAA==.',Ki='Kickatoir:BAABLAAECoEaAAIZAAgIgBoYCwBoAgAZAAgIgBoYCwBoAgAAAA==.',Kj='Kjelliss:BAAALAADCggICwAAAA==.',Ko='Kosser:BAABLAAECoEYAAMEAAgI5BvEHgBqAgAEAAgIUxnEHgBqAgAaAAIIoySvJQDFAAAAAA==.Kosserz:BAAALAADCgYIBgABLAAECggIGAAEAOQbAA==.',Kr='Kratosex:BAABLAAECoEVAAQSAAgI6RpiCgA5AgASAAgIsxpiCgA5AgAbAAQIrRMcLgD8AAAcAAIIRBZaogCSAAAAAA==.',Ku='Kugisaki:BAAALAADCgcIBwAAAA==.',Ky='Kyntsi:BAAALAADCgIIAgAAAA==.',Le='Lemon:BAAALAAECgMIAwAAAA==.Leonesh:BAAALAADCggICAAAAA==.',Li='Liljah:BAAALAAECgYIDwABLAAFFAMICAAEANIgAA==.Linnormen:BAAALAADCggIDwABLAAECggIFgAPAHodAA==.Lionell:BAAALAADCgYIBgAAAA==.',Lo='Logrek:BAAALAADCggICAABLAAFFAUIDAAXABMkAA==.',Lu='Lucyón:BAAALAADCgcIDgABLAAECgUIBAABAAAAAA==.Lume:BAAALAADCgcIFAAAAA==.Lumoava:BAACLAAFFIEGAAIYAAMIJRZoAQD5AAAYAAMIJRZoAQD5AAAsAAQKgR0AAhgACAh6JJABAFoDABgACAh6JJABAFoDAAAA.Lun:BAAALAAECgcIDgAAAA==.Lunalei:BAAALAADCggIDwAAAA==.Luv:BAAALAADCggICAAAAA==.',Ly='Lyatha:BAAALAAFFAIIAgABLAAFFAUICAAbAJwSAA==.Lyrie:BAAALAAECgYICwABLAAFFAUIDQAbALoeAA==.Lythi:BAACLAAFFIEIAAIbAAUInBI1AQCzAQAbAAUInBI1AQCzAQAsAAQKgRQAAhsACAjdIeABABIDABsACAjdIeABABIDAAAA.',Ma='Macgreger:BAAALAADCggIDwAAAA==.Maguz:BAAALAAECgcICgAAAA==.Marlon:BAAALAAECgYIDAAAAA==.Mato:BAABLAAECoEcAAIYAAgIpSRjAQBhAwAYAAgIpSRjAQBhAwAAAA==.',Me='Medesimus:BAAALAADCggICgAAAA==.Mehukatti:BAAALAAECgYIBgAAAA==.Meneldur:BAAALAAECgYIEQAAAA==.',Mi='Micolash:BAAALAAECgcIEQAAAA==.Missie:BAACLAAFFIELAAIEAAUIhwtmAgCdAQAEAAUIhwtmAgCdAQAsAAQKgSAAAgQACAiKJBQHADkDAAQACAiKJBQHADkDAAAA.',Mo='Monarch:BAAALAAECgcIEwAAAA==.Moonfighter:BAAALAAECgcIDgAAAA==.Mosmendrain:BAAALAAECgMIAwAAAA==.',Mu='Musashi:BAAALAADCggIEAAAAA==.',['Mò']='Mòrgoth:BAAALAAECgcIEQAAAA==.',Na='Nali:BAACLAAFFIENAAIbAAUIuh7RAADwAQAbAAUIuh7RAADwAQAsAAQKgSAAAhsACAiqJKMAAEsDABsACAiqJKMAAEsDAAAA.Nasiahaze:BAAALAADCgcICQAAAA==.',Ne='Nellithedog:BAAALAADCgYIBgAAAA==.Nemaro:BAAALAAECgIIAgAAAA==.Nezzom:BAAALAAECgEIAQAAAA==.',Ni='Nipe:BAAALAADCgcICQAAAA==.Niriya:BAAALAADCggIFAABLAAFFAUIDQAbALoeAA==.',Nu='Nugsnugs:BAACLAAFFIEIAAIHAAMI4RYYAwD1AAAHAAMI4RYYAwD1AAAsAAQKgRcAAwcACAgrGysLABMCAAcACAgrGysLABMCABkABQhqDHooAPoAAAAA.',Ok='Okafor:BAAALAADCgcIBwAAAA==.',On='Onoxous:BAAALAAECgUIBwAAAA==.',Op='Oppsi:BAAALAADCgcIDQAAAA==.',Pa='Paladinen:BAAALAAECgMIAwABLAAECggIFQADAGsVAA==.Paleli:BAAALAADCgYIBgABLAAFFAMIBQABAAAAAQ==.Pawpatine:BAAALAADCggICwAAAA==.',Po='Polishmafia:BAACLAAFFIEFAAIFAAII9yGACgDKAAAFAAII9yGACgDKAAAsAAQKgRsAAgUACAgnIKsOAOYCAAUACAgnIKsOAOYCAAAA.Popsicle:BAAALAADCgYICAAAAA==.',Pu='Punasiipi:BAAALAADCgMIAwAAAA==.',Qa='Qashanova:BAAALAAECgMIBQAAAA==.',Ra='Raghok:BAAALAAFFAEIAQAAAA==.Rantakäärme:BAACLAAFFIEGAAQLAAMINgvyBgDZAAALAAMIewnyBgDZAAAdAAIIqAsNAgCRAAAMAAEIKha7CQBQAAAsAAQKgR8ABB0ACAiOHTsBANYCAB0ACAgiHTsBANYCAAsACAg8GjMPAGYCAAwABwiQFYwMAL0BAAAA.Raraldin:BAAALAADCgcIEQAAAA==.Razzo:BAAALAADCgcIDwAAAA==.',Re='Resozen:BAABLAAECoEWAAIZAAgI7iToAgAyAwAZAAgI7iToAgAyAwAAAA==.',Rh='Rhosyn:BAAALAADCggICQABLAAECgcIFgARAF8aAA==.',Ro='Rocks:BAAALAAECgUIBgAAAA==.Roguen:BAABLAAECoEVAAIDAAgIaxWCEwAyAgADAAgIaxWCEwAyAgAAAA==.Romppadru:BAAALAAECgUIBQAAAA==.Roxybabe:BAAALAAECgQIBAAAAA==.',Ru='Rubbz:BAAALAAECgYIEQAAAA==.Runkemonk:BAABLAAECoEXAAMZAAgIehjwDABFAgAZAAgIehjwDABFAgAHAAcIdQrwFgBEAQAAAA==.',Sa='Salaatti:BAACLAAFFIEIAAIUAAMIDhA2BwD4AAAUAAMIDhA2BwD4AAAsAAQKgR8AAhQACAhkInQHAB8DABQACAhkInQHAB8DAAAA.Sazakan:BAAALAADCggIDwAAAA==.',Sc='Scuffed:BAAALAADCgQIBgAAAA==.',Se='Sebahunt:BAABLAAECoEWAAIQAAgINhYvGAAnAgAQAAgINhYvGAAnAgABLAAFFAIIBQAFAPchAA==.Sebby:BAACLAAFFIEFAAILAAMIJhPVBQD0AAALAAMIJhPVBQD0AAAsAAQKgRsAAgsACAhvIloEACEDAAsACAhvIloEACEDAAAA.Señormoist:BAAALAAECgMIAwABLAAECggIFgAPAHodAA==.',Sh='Shasur:BAAALAAECgYIDgAAAA==.Shasuri:BAAALAADCgQIBAAAAA==.Shawski:BAAALAAECgYIEAAAAA==.Shibaevo:BAAALAADCggICAAAAA==.Shindy:BAAALAAECgUIBQAAAA==.Shumumu:BAACLAAFFIEGAAITAAIIERDbAgCoAAATAAIIERDbAgCoAAAsAAQKgRkAAhMACAjFHBEEAJoCABMACAjFHBEEAJoCAAAA.',Si='Silence:BAABLAAECoEZAAIRAAgI2B6uCgDAAgARAAgI2B6uCgDAAgAAAA==.',Sk='Skeleton:BAAALAAECgQICAAAAA==.Skipperz:BAAALAAECgYIDQAAAA==.Skogspingvin:BAAALAAECggIEQAAAA==.',Sl='Slipnir:BAAALAADCggICAAAAA==.',Sm='Smasher:BAAALAADCgcIBwAAAA==.Smiskk:BAAALAAECgYIDAAAAA==.Smuc:BAAALAADCgUIBQAAAA==.',Sn='Snipedamage:BAACLAAFFIEHAAIeAAMIRiAPBgAqAQAeAAMIRiAPBgAqAQAsAAQKgR8AAx4ACAhFIwAIACUDAB4ACAhFIwAIACUDAB8AAQj/Gp0QAEsAAAAA.Snipedamagee:BAAALAADCgEIAQABLAAFFAMIBwAeAEYgAA==.Snipeshaman:BAAALAAECgYIDgABLAAFFAMIBwAeAEYgAA==.',So='Soare:BAAALAADCggIEgAAAA==.Sontaseppo:BAAALAAECgUICAAAAA==.',Sp='Spazzio:BAAALAAECgQIBAAAAA==.Spoonfork:BAAALAADCgMIAwAAAA==.Sprite:BAAALAAECgMIBAAAAA==.Spyroq:BAAALAADCgcICgAAAA==.',St='Stinkynator:BAABLAAECoEUAAIEAAgI8yLBCAAoAwAEAAgI8yLBCAAoAwAAAA==.Stinkypete:BAAALAAECgYIBgABLAAECggIFAAEAPMiAA==.Stormalia:BAAALAAECgcIEAAAAA==.',Su='Suomulainen:BAACLAAFFIEHAAILAAMIoxcgBQAAAQALAAMIoxcgBQAAAQAsAAQKgR8AAgsACAh+HzUIANkCAAsACAh+HzUIANkCAAAA.',Sy='Synchro:BAAALAADCggICQAAAA==.',Ta='Tamriel:BAAALAADCggICAABLAAECgcIFgARAF8aAA==.',Te='Temmu:BAAALAADCgcIDQAAAA==.',Th='Thanil:BAAALAADCggIEgAAAA==.Thanthalas:BAABLAAECoEfAAIPAAgIyRyIEQClAgAPAAgIyRyIEQClAgAAAA==.Thebusdriver:BAAALAADCggIBQAAAA==.Thrunde:BAAALAADCggIDwAAAA==.',Ti='Tinkarti:BAACLAAFFIEIAAIYAAMICyGcAAAuAQAYAAMICyGcAAAuAQAsAAQKgR8AAhgACAjaJCMBAGkDABgACAjaJCMBAGkDAAAA.Tipslock:BAAALAAECggIEQAAAA==.Titaa:BAAALAADCgcIBwAAAA==.',Tr='Trapkers:BAACLAAFFIEGAAIgAAMI2RNlAAAMAQAgAAMI2RNlAAAMAQAsAAQKgR8AAiAACAhZIf4AABMDACAACAhZIf4AABMDAAAA.Trusetyven:BAAALAAECgcIBwABLAAECgcICgABAAAAAA==.',Tu='Turker:BAAALAADCggIDwABLAAECgYIEQABAAAAAA==.',Ty='Tyrdan:BAACLAAFFIEHAAIbAAMIEiQwAgBAAQAbAAMIEiQwAgBAAQAsAAQKgRgAAhsACAhPICYGAKECABsACAhPICYGAKECAAAA.',['Tö']='Tötterö:BAAALAAECgQIAgAAAA==.',Ui='Uisce:BAAALAAECgIIAwAAAA==.',Uk='Uklu:BAAALAADCgcIDgAAAA==.',Ul='Ulio:BAAALAAECggIEQAAAA==.',Um='Umisia:BAAALAADCggIFgAAAA==.',Ut='Utnola:BAAALAAECgYIEQAAAA==.',Va='Valantyr:BAAALAAECgEIAQAAAA==.',Ve='Veggis:BAAALAADCggIEwAAAA==.Veilside:BAAALAAECgIIAgAAAA==.Vespera:BAAALAAECgcIDgAAAA==.',Vo='Voidlisa:BAAALAAECgYIDAAAAA==.Volcan:BAAALAAECgIIAgAAAA==.',Vy='Vynthas:BAAALAADCgMIAwAAAA==.',Wt='Wtdouservher:BAAALAAECgEIAQAAAA==.',Xa='Xad:BAAALAADCgcIBwAAAA==.',Xi='Xien:BAAALAAECgMIAwAAAA==.',Xy='Xye:BAAALAAECgMIBQAAAA==.',Ya='Yadena:BAAALAADCgMIAwAAAA==.Yaederiel:BAAALAADCgQIBAAAAA==.Yahenni:BAACLAAFFIEMAAIXAAUIEyTuAAAfAgAXAAUIEyTuAAAfAgAsAAQKgSIAAhcACAiLJlkAAI8DABcACAiLJlkAAI8DAAAA.',Zo='Zoeý:BAAALAAECgEIAQAAAA==.',Zu='Zugmar:BAAALAAECgEIAQAAAA==.',Zy='Zyarel:BAAALAADCggIHwABLAAECgYIBgABAAAAAA==.',['Öo']='Öo:BAAALAAECggIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end