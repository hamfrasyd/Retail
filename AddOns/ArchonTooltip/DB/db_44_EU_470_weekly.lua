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
 local lookup = {'Paladin-Retribution','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Frost','Shaman-Elemental','Shaman-Restoration','Warrior-Fury','Hunter-BeastMastery','Druid-Guardian','Monk-Windwalker','Monk-Brewmaster','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Unholy','Monk-Mistweaver','Evoker-Augmentation','Paladin-Protection','Shaman-Enhancement','Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Blood','Mage-Arcane','Hunter-Survival','Druid-Balance','DemonHunter-Vengeance','Warrior-Protection','Rogue-Subtlety','Paladin-Holy',}; local provider = {region='EU',realm='Tichondrius',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Absurdistan:BAAALAAECgIIAgAAAA==.',Ac='Ace:BAABLAAECoEWAAIBAAgIUR3hJwCtAgABAAgIUR3hJwCtAgAAAA==.',Ad='Adalycia:BAAALAAECgYIDQAAAA==.',Ae='Aestoreth:BAAALAAECgYIBwAAAA==.',Al='Alcadaias:BAABLAAECoEaAAICAAgIdiMXCAAGAwACAAgIdiMXCAAGAwABLAAFFAYIHAADALcZAA==.Alcadraias:BAACLAAFFIEcAAMDAAYItxkWAgD+AQADAAYItxkWAgD+AQAEAAEIYAA0HgAdAAAsAAQKgSEAAwMACAjrIPkDAPUCAAMACAjrIPkDAPUCAAQABgi6Gw0mAMsBAAAA.Alwartan:BAAALAADCgcIBwAAAA==.Alyndriel:BAAALAAECgEIAQAAAA==.',Am='Amaresh:BAAALAADCgYIBgAAAA==.Amygdalá:BAACLAAFFIEMAAMFAAUIzRSbAgD/AAAFAAMIihSbAgD/AAAGAAMIDRNSFwD+AAAsAAQKgR8AAwUACAiJIsUEAAkDAAUACAiJIsUEAAkDAAYAAghBHMyzAKQAAAAA.Amøn:BAAALAAECggICAAAAA==.',An='Angèle:BAAALAAECgMIAwAAAA==.Anillja:BAAALAADCggICgAAAA==.Anjuna:BAAALAADCggICAAAAA==.Annabelle:BAAALAADCggICAAAAA==.Antownia:BAAALAADCgYIBQABLAAECgcIEQAHAAAAAA==.',Ar='Arcanebomber:BAAALAADCggICAAAAA==.Areefa:BAAALAAECgYIEQAAAA==.Arin:BAAALAADCgQIBAAAAA==.Aristeidis:BAAALAAECgYICgAAAA==.Arnodl:BAAALAAECgMIBAAAAA==.',As='Asgora:BAABLAAECoEoAAIFAAgIICL0BAAFAwAFAAgIICL0BAAFAwAAAA==.Asharuu:BAAALAADCggICAAAAA==.Asurâ:BAAALAAECgcIDQABLAAFFAUIDAAFAM0UAA==.Asymptote:BAACLAAFFIEHAAIIAAIIahEOIgCVAAAIAAIIahEOIgCVAAAsAAQKgRwABAgABwhBDapWAFkBAAgABwiLC6pWAFkBAAkAAwj6C2lzAJQAAAoAAwhCCkolAIAAAAAA.',At='Atmo:BAAALAAECgIIBQABLAAECgMIAgAHAAAAAA==.',Au='Aurisdiamond:BAACLAAFFIENAAILAAMImxJmGwDeAAALAAMImxJmGwDeAAAsAAQKgS4AAgsACAjPIXAdANwCAAsACAjPIXAdANwCAAAA.Auríél:BAAALAAECgMIAwAAAA==.Ausgieser:BAAALAADCggICgAAAA==.',Av='Avye:BAAALAAECgIIAgAAAA==.',Aw='Awilix:BAAALAADCggICAAAAA==.',Ay='Aymee:BAABLAAECoElAAMMAAgIeRZHQgDQAQAMAAgIeRZHQgDQAQANAAQI7gG/7wBoAAAAAA==.Ayumiro:BAAALAADCgcIBwAAAA==.',Ba='Babsack:BAABLAAECoEqAAIOAAgIzQ0yUQDGAQAOAAgIzQ0yUQDGAQAAAA==.Backstábbath:BAAALAADCgYIBgABLAAECggICAAHAAAAAA==.Baphomèt:BAAALAAECggIEAABLAAECggIFgABACELAA==.Batuun:BAABLAAECoElAAIBAAgIfw4lkwCWAQABAAgIfw4lkwCWAQAAAA==.',Be='Benhal:BAAALAAECgYIEQAAAA==.',Bl='Blackshot:BAABLAAECoEcAAIPAAYIhhTkjgBgAQAPAAYIhhTkjgBgAQAAAA==.Bluetiger:BAAALAAECggIEAAAAA==.Bluewolfy:BAAALAADCgMIAwAAAA==.',Bo='Bolaan:BAAALAAECgYICQABLAAFFAMIDgAQADgjAA==.Bonaut:BAAALAAECgUIBQAAAA==.Botschinka:BAAALAAECgEIAwAAAA==.',Br='Brewtality:BAACLAAFFIESAAMRAAUIqxnCAgC8AQARAAUIqxnCAgC8AQASAAEIpwXBFgArAAAsAAQKgSMAAxEACAjlJNcCAFUDABEACAjlJNcCAFUDABIAAgjlEGs6AGQAAAAA.Britneyfears:BAABLAAECoEeAAQGAAgITh1/LQBfAgAGAAgIFRx/LQBfAgAFAAQI3RgfUQADAQATAAEIgREBOgA9AAAAAA==.Bro:BAAALAAECgUIBQAAAA==.Broqi:BAAALAADCgYIBgAAAA==.Brunhilde:BAABLAAECoEhAAIBAAcIYgjurwBjAQABAAcIYgjurwBjAQAAAA==.Brötchen:BAABLAAECoEbAAITAAgImRN6BwA1AgATAAgImRN6BwA1AgAAAA==.',Ca='Caliope:BAABLAAECoElAAIBAAgI1hkPMgCCAgABAAgI1hkPMgCCAgAAAA==.Caydrin:BAAALAAECgUICAABLAAECggICAAHAAAAAA==.',Ch='Chase:BAAALAADCgYIBgAAAA==.Cherubîni:BAAALAAECgYIEwAAAA==.Chontamenti:BAABLAAECoEYAAIQAAcIPBSiDwChAQAQAAcIPBSiDwChAQAAAA==.Chopsueytom:BAABLAAECoEVAAIPAAgI9AJI2gC6AAAPAAgI9AJI2gC6AAAAAA==.Chrissý:BAAALAAECgYICAAAAA==.Chríssy:BAAALAAECgYIDQAAAA==.',Cl='Classik:BAAALAAECgQIBwABLAAECggIIwAUAEYkAA==.Classis:BAABLAAECoEjAAIUAAgIRiThCQBFAwAUAAgIRiThCQBFAwAAAA==.',Co='Combatcarl:BAAALAAECgYIBwAAAA==.',Cr='Craye:BAAALAADCggICQAAAA==.',Cu='Cursingeagle:BAAALAADCgYIBgAAAA==.',Da='Daegal:BAAALAAECgQIBAAAAA==.Daemonikan:BAACLAAFFIEHAAIUAAMIehXREAAFAQAUAAMIehXREAAFAQAsAAQKgRoAAhQACAg0H/klAKYCABQACAg0H/klAKYCAAAA.Danori:BAACLAAFFIELAAIIAAMIBhn/DQD7AAAIAAMIBhn/DQD7AAAsAAQKgSgAAggACAiWIeQJAAoDAAgACAiWIeQJAAoDAAAA.Darkrazorx:BAABLAAECoEVAAIVAAgIGASsKwBJAQAVAAgIGASsKwBJAQAAAA==.Darkslash:BAAALAADCggICAAAAA==.Datrelana:BAAALAADCgIIAgAAAA==.Davinara:BAAALAADCgYIBgAAAA==.',De='Deredere:BAAALAAECgIIAgABLAAECgcIHgAWAPYMAA==.Dethecus:BAAALAADCgMIAwAAAA==.Devanaa:BAAALAADCggIEAAAAA==.',Di='Disziplina:BAAALAADCgUIBQAAAA==.',Dk='Dks:BAAALAAECgMIAwAAAA==.',Do='Dolghar:BAAALAADCggICgAAAA==.',Dr='Dracthyra:BAABLAAECoEZAAIDAAcIlxcsEAD9AQADAAcIlxcsEAD9AQABLAAFFAMICwAIAAYZAA==.Dragonia:BAAALAAECgYICAAAAA==.Dragonir:BAAALAADCggICAAAAA==.Drakí:BAACLAAFFIEGAAIJAAQIqgziCgAcAQAJAAQIqgziCgAcAQAsAAQKgSYAAwkACAiGH20PAOUCAAkACAiGH20PAOUCAAgAAQgUCGyoACkAAAAA.Draín:BAAALAADCggICwAAAA==.Dreadmourn:BAAALAAECgYIDAAAAA==.Drowsy:BAAALAAECgMIAwABLAAECgYIBgAHAAAAAA==.Drowsygrip:BAAALAAECgcIDQAAAA==.Drowsyjudge:BAAALAAECgYIBgAAAA==.Drowsyshot:BAAALAADCgYIBgAAAA==.',Du='Dunjovaca:BAAALAAECgMIBAAAAA==.Durlin:BAAALAAECgcIDQAAAA==.',Ec='Ectheleon:BAAALAADCggICQAAAA==.',Ei='Eisír:BAABLAAECoEbAAQWAAcI5RmjEgAcAgAWAAcI5RmjEgAcAgARAAYITwcFPQD9AAASAAMIiwR5PABSAAAAAA==.',Ej='Ejima:BAAALAAECgYIBgAAAA==.',El='Elbandito:BAAALAADCgEIAQAAAA==.Eleen:BAAALAAECgYIEAAAAA==.Eleméntál:BAAALAAFFAIIAgAAAA==.Eliorn:BAAALAAECgEIAQAAAA==.Ellsattay:BAAALAADCgcICAABLAAECgYIBgAHAAAAAA==.',Er='Ermelyn:BAACLAAFFIEIAAIDAAIIGhLBDQCQAAADAAIIGhLBDQCQAAAsAAQKgScABAMACAhTH3gHAJ8CAAMACAhTH3gHAJ8CAAQABwjbGXseAAwCABcABQiwFnILAGoBAAAA.',Eu='Eulila:BAAALAADCgcIBwAAAA==.',Ev='Evolution:BAAALAADCgUIBQAAAA==.',Ex='Extoria:BAACLAAFFIEGAAIYAAIIrxilCgCcAAAYAAIIrxilCgCcAAAsAAQKgSsAAhgACAgQI30FAA8DABgACAgQI30FAA8DAAAA.',Ez='Ezo:BAAALAAECgIIAgAAAA==.',Fa='Fadrim:BAAALAADCggIEgAAAA==.Farrâh:BAAALAADCggIBwAAAA==.',Fe='Felaryon:BAABLAAECoElAAIEAAgIsiSjAgBcAwAEAAgIsiSjAgBcAwABLAAFFAMICwAZAHMjAA==.Fermage:BAAALAADCggIDQAAAA==.Feyriel:BAAALAAECgMIBwAAAA==.',Fi='Fier:BAAALAAECgYIBgABLAAFFAIIBQAPADoeAA==.Firunn:BAAALAAECgYIEgABLAAFFAUIEAAaAMUQAA==.',Fj='Fjedn:BAACLAAFFIELAAIZAAMIcyOyAQAyAQAZAAMIcyOyAQAyAQAsAAQKgS4AAhkACAgSJlMAAHsDABkACAgSJlMAAHsDAAAA.',Fl='Flügelschlag:BAAALAAECgIIBAAAAA==.',Fo='Forevermore:BAABLAAECoEWAAMBAAgIIQvVtABaAQABAAYIXw7VtABaAQAYAAgIrwBtZgAbAAAAAA==.Forion:BAACLAAFFIEGAAIbAAIIdyb/DADgAAAbAAIIdyb/DADgAAAsAAQKgR0AAhsACAiWJSwCAGQDABsACAiWJSwCAGQDAAAA.',Fr='Frozenbuns:BAAALAADCgcIDgABLAAECggICAAHAAAAAA==.',Fu='Fuwamoco:BAAALAAECgQIBAAAAA==.',Ga='Gardor:BAAALAAECgcIBwABLAAECggIJAAXAF4lAA==.',Ge='Genuine:BAAALAAECgIIBAAAAA==.Gerá:BAABLAAECoEgAAIEAAgIxxFcIgDpAQAEAAgIxxFcIgDpAQAAAA==.',Gi='Gitte:BAAALAAECgIIAgAAAA==.',Gl='Glurack:BAAALAADCgcIBwAAAA==.Gláedr:BAABLAAECoEUAAIUAAYIySFmPwA8AgAUAAYIySFmPwA8AgAAAA==.',Go='Gorlad:BAABLAAECoElAAIcAAgI+yGKBAAWAwAcAAgI+yGKBAAWAwABLAAFFAMIDgAQADgjAA==.',Gr='Griffindor:BAAALAAECgEIAQAAAA==.Grimmbard:BAAALAAECgIIBAAAAA==.Grixus:BAAALAADCgcICAABLAAECgYIDgAHAAAAAA==.Grosian:BAAALAAECgcIBwAAAA==.Grummush:BAAALAAECggICAAAAA==.',Gw='Gwyd:BAAALAAECggICAAAAA==.',Ha='Hajoohh:BAAALAAECgYIDAAAAA==.Hamadryade:BAAALAAECgIIAgAAAA==.Hannahl:BAAALAAECgQIBwAAAA==.Harlondir:BAAALAAECgQIBwABLAAECgcIGgAOADQjAA==.Hartgestofft:BAAALAAECgYIBgAAAA==.',He='Heilhannes:BAAALAADCgYIBgAAAA==.Hexler:BAAALAADCgYICgAAAA==.',Ho='Holyboom:BAAALAAECgMIAwABLAAFFAIIBwALABUaAA==.',Hr='Hraldrim:BAAALAAECgMIAwAAAA==.',Hu='Hulao:BAACLAAFFIENAAISAAMIdiKCBgAcAQASAAMIdiKCBgAcAQAsAAQKgS0AAhIACAgbJQUCAFgDABIACAgbJQUCAFgDAAAA.Hulosh:BAAALAADCgYICAABLAAFFAMIDQASAHYiAA==.Huzzr:BAAALAAECggIDAAAAA==.',['Hâ']='Hâchî:BAAALAADCgMIBQAAAA==.',['Hä']='Härbärt:BAABLAAECoEYAAIQAAcIQhjhCwDpAQAQAAcIQhjhCwDpAQAAAA==.',['Hò']='Hònéy:BAAALAAECgYICwAAAA==.',['Hö']='Hörmeline:BAAALAADCgYIBgAAAA==.Hörmipani:BAAALAADCggICAAAAA==.',Ia='Iatery:BAAALAAECgUICgAAAA==.',Id='Idlaldil:BAAALAAECgYIDAAAAA==.',If='Ifria:BAAALAADCgYIBgABLAAFFAMICQAMAA4PAA==.',Ig='Igu:BAAALAAECgQIBAABLAAFFAMIBgAdALkWAA==.',Ik='Ikkusama:BAAALAAFFAIIAgAAAA==.',Il='Illario:BAAALAAECgIIBAABLAAECgYIEAAHAAAAAA==.Ilrise:BAAALAADCgYIBgAAAA==.Iluschka:BAAALAAECgUIDgAAAA==.',Im='Imbecile:BAACLAAFFIENAAIMAAMI/QhGEwDVAAAMAAMI/QhGEwDVAAAsAAQKgSoAAwwACAjAHI4aAKoCAAwACAjAHI4aAKoCAA0AAQi2CWEQASsAAAAA.Imimaru:BAAALAAECgcIDAAAAA==.Imsn:BAAALAAECggICAAAAA==.',Is='Iskierka:BAAALAAECggIDQAAAA==.Issia:BAAALAADCggIFAAAAA==.',Ja='Jarestin:BAAALAADCgYICQAAAA==.',Je='Jenná:BAAALAADCggICAAAAA==.',Jo='Josoja:BAAALAADCggIEwAAAA==.',['Já']='Jámaican:BAAALAAECgYICwABLAAECggIFgABABceAA==.',['Jä']='Jägerpony:BAABLAAECoEwAAIPAAgIviOvEwDuAgAPAAgIviOvEwDuAgAAAA==.',Ka='Kasaí:BAAALAAFFAMIAwABLAAFFAcIDQAbAHIZAA==.Katyparry:BAACLAAFFIEOAAMLAAcI0B6yAADHAgALAAcIfB6yAADHAgAVAAIIFyXpBwDEAAAsAAQKgRwAAxUACAgiJoYDACUDABUACAjYJYYDACUDAAsACAiJJG0ZAPACAAAA.',Ke='Keindruide:BAAALAAECgQIBQABLAAFFAcIHwABAG0aAA==.Keineisen:BAACLAAFFIEIAAIBAAMIGiXkCQA5AQABAAMIGiXkCQA5AQAsAAQKgS4AAgEACAhgJuMBAIgDAAEACAhgJuMBAIgDAAEsAAUUBwgfAAEAbRoA.Keinpaladin:BAACLAAFFIEfAAIBAAcIbRpvAgAZAgABAAcIbRpvAgAZAgAsAAQKgUMAAgEACAjaJlsAAKADAAEACAjaJlsAAKADAAAA.',Kl='Klinaria:BAAALAAECgQIBAAAAA==.',Kn='Knâllâ:BAACLAAFFIELAAMeAAMI3AstAwCoAAAeAAIIogstAwCoAAAPAAMImwZYPABzAAAsAAQKgS4AAx4ACAhtIIECAOgCAB4ACAhtIIECAOgCAA8ACAj/FVdrAKsBAAAA.',Ko='Kowalskî:BAABLAAECoEPAAIFAAcIWBfPGwD+AQAFAAcIWBfPGwD+AQAAAA==.',Kr='Krower:BAAALAAECgYIEwAAAA==.',Ku='Kumajin:BAABLAAECoEoAAIIAAgIxRmFHwBfAgAIAAgIxRmFHwBfAgAAAA==.Kurio:BAAALAAECgYIEQAAAA==.Kurtkuhbein:BAAALAADCgIIAgAAAA==.',Kw='Kwazii:BAAALAAECgIIAgAAAA==.',['Kâ']='Kârami:BAAALAAECgQIBAABLAAECgcICgAHAAAAAA==.',La='Laphroaig:BAAALAADCgcIDAAAAA==.',Le='Leila:BAAALAAECggICAAAAA==.Leinani:BAACLAAFFIEJAAIMAAMIDg/LEgDbAAAMAAMIDg/LEgDbAAAsAAQKgSYAAgwACAh7H3kYALkCAAwACAh7H3kYALkCAAAA.Lennox:BAAALAAFFAIIAgABLAAFFAYIEgANAEUUAA==.Leoniéê:BAAALAAECggIEgAAAA==.Leoníeè:BAAALAAECggIEgAAAA==.Leoníêe:BAAALAADCggICAAAAA==.Leonîeé:BAAALAAECgYICgAAAA==.Lestrange:BAAALAAECgEIAQAAAA==.Leónîee:BAABLAAECoEZAAIfAAcI6RyNIAAyAgAfAAcI6RyNIAAyAgAAAA==.',Li='Lireesa:BAAALAAECggICAABLAAECggICAAHAAAAAA==.Lishara:BAAALAADCgcIBwAAAA==.',Ll='Lleon:BAAALAADCgIIAgAAAA==.',Lo='Lorki:BAACLAAFFIENAAIbAAMI3iQ0CAA2AQAbAAMI3iQ0CAA2AQAsAAQKgSwAAhsACAhXJWYCAGADABsACAhXJWYCAGADAAAA.Lostnithz:BAAALAAFFAIIAQAAAA==.',Lu='Luminios:BAAALAAECgMIAwAAAA==.',Ma='Maghazar:BAAALAADCggICgABLAAECgcIGgAOADQjAA==.Marizzá:BAABLAAECoEVAAINAAcIOhWaXACiAQANAAcIOhWaXACiAQAAAA==.Matrok:BAAALAADCggICAABLAAFFAIIBgASANgiAA==.',Mc='Mcløvin:BAABLAAECoEaAAIPAAYIlR9uWQDWAQAPAAYIlR9uWQDWAQAAAA==.',Me='Mei:BAAALAADCggICAAAAA==.Merlîn:BAAALAADCggICAABLAAECgQIDwAHAAAAAA==.Metaa:BAABLAAECoEjAAIPAAgIJh5MHwCrAgAPAAgIJh5MHwCrAgAAAA==.Metademon:BAAALAAECgYIDAAAAA==.',Mi='Mihla:BAAALAADCgIIAgAAAA==.Minajas:BAAALAAFFAIIAgAAAA==.Mirajanê:BAAALAADCgcICAAAAA==.Mitochondria:BAAALAADCggIIAAAAA==.',Mo='Moloko:BAAALAADCgMIAwAAAA==.Monámi:BAACLAAFFIEGAAIdAAIIVRBXOACUAAAdAAIIVRBXOACUAAAsAAQKgSAAAh0ACAgXHtssAH4CAB0ACAgXHtssAH4CAAAA.Moolaan:BAACLAAFFIEOAAIQAAMIOCPSAAA0AQAQAAMIOCPSAAA0AQAsAAQKgS0AAhAACAiHJkAAAJQDABAACAiHJkAAAJQDAAAA.Mordonos:BAABLAAECoEOAAMFAAcIEA7dMACJAQAFAAcIWA3dMACJAQAGAAQIFAnrugCLAAABLAABCgMIAwAHAAAAAA==.Motor:BAAALAADCgUIBQAAAA==.Moudajo:BAAALAADCgYIBgAAAA==.Moynn:BAABLAAECoEWAAIGAAgI9QheYwCTAQAGAAgI9QheYwCTAQAAAA==.',Mu='Muhlani:BAAALAAECgYICQABLAAECgYIEwAHAAAAAA==.Muuhii:BAAALAADCgUIBQAAAA==.',My='Myrana:BAAALAADCggIGgAAAA==.',['Má']='Márgê:BAAALAAECgYIDgAAAA==.',['Mî']='Mîn:BAAALAADCggIIQAAAA==.',Na='Nackdown:BAAALAADCgUIBQABLAAECgEIAQAHAAAAAA==.Naramas:BAACLAAFFIEKAAMVAAMIHB4LCQC5AAAVAAIIKh4LCQC5AAALAAEIAR5ZZwBOAAAsAAQKgS0AAwsACAgdI94mALICAAsACAhvId4mALICABUABAiuJaMdALYBAAAA.',Ne='Nedum:BAAALAAECggICAAAAA==.Nehemetawai:BAAALAAECgUIBwAAAA==.Nekira:BAAALAADCggIEAABLAAECggIJAAOACIiAA==.Nethor:BAAALAADCgYIBgAAAA==.Nexecute:BAAALAAECgMIAQAAAA==.Nexhex:BAAALAAECgIIBgABLAAECgMIAQAHAAAAAA==.',Nh='Nhala:BAAALAAECgYIDAAAAA==.',Ni='Nigiri:BAAALAAECgYIEwAAAA==.Nikos:BAAALAADCgYIBgAAAA==.Ninka:BAABLAAECoEXAAIPAAYImSGJUwDmAQAPAAYImSGJUwDmAQAAAA==.Ninni:BAAALAADCgMIAwAAAA==.Nitheful:BAAALAAECggIDQABLAAECggIFgABACELAA==.',No='Nomnom:BAAALAAECgEIAQAAAA==.Notnîthz:BAABLAAECoEjAAIdAAgIJCDUHADMAgAdAAgIJCDUHADMAgAAAA==.Nowan:BAAALAADCggIDgAAAA==.',Nu='Nuii:BAAALAAECgYICQAAAA==.Nuiiman:BAABLAAECoEcAAIJAAgIax9IEADcAgAJAAgIax9IEADcAgAAAA==.Nuurai:BAAALAADCgQIBAABLAAFFAUIEgARAKsZAA==.',['Nô']='Nôx:BAAALAAECgIIAgAAAA==.',Oa='Oacheschwoaf:BAAALAADCgcICwAAAA==.',Oi='Oidaqt:BAAALAAECgQIBAAAAA==.',On='Onkadien:BAAALAAFFAEIAQABLAAECgcIGgAOADQjAA==.',Or='Orpheoos:BAAALAADCgMIAwAAAA==.',Ox='Oxyana:BAABLAAECoEeAAINAAgICR85QwDsAQANAAgICR85QwDsAQABLAAFFAMICwAIAAYZAA==.',Pa='Paara:BAAALAAECgMIAgAAAA==.Padaf:BAABLAAECoEaAAIOAAcINCO+FwDaAgAOAAcINCO+FwDaAgAAAA==.Palabine:BAAALAAECgMIBQAAAA==.Palax:BAABLAAECoEWAAIBAAcIFx7ARgA9AgABAAcIFx7ARgA9AgAAAA==.',Pe='Peace:BAAALAAFFAIIBAAAAA==.Perseus:BAABLAAECoEYAAMUAAgIig9AeQClAQAUAAgIOw5AeQClAQAgAAUIKA5COgDIAAAAAA==.',Pl='Plumplum:BAABLAAECoEbAAINAAcIIB74LgAyAgANAAcIIB74LgAyAgAAAA==.',Po='Pohaare:BAAALAAECgcIDgAAAA==.Polizeiwagen:BAAALAAECgYICAAAAA==.',Pr='Priesterpony:BAAALAAECgQIBwABLAAECggIMAAPAL4jAA==.',Pu='Purplepenny:BAAALAADCggICAAAAA==.Purpleshadow:BAAALAADCgYIBgAAAA==.',Pw='Pwnshaman:BAAALAAECggICAAAAA==.',Py='Pyríít:BAAALAAECgUICQAAAA==.',['Pâ']='Pâul:BAABLAAECoEpAAMBAAgIfxccWwAHAgABAAgI5BUcWwAHAgAYAAYInhh5KAB+AQAAAA==.',Ra='Radizen:BAAALAAECgEIAQAAAA==.Radun:BAAALAADCgUIBAAAAA==.Randoms:BAAALAAECgUICgAAAA==.Ravên:BAAALAAECgIIAgAAAA==.',Re='Remixmage:BAAALAADCggICAABLAADCggICAAHAAAAAA==.Reptikor:BAAALAADCgQIBAABLAAECgYIFQAhAFwVAA==.Reptikrieg:BAABLAAECoEVAAMhAAYIXBXPNgBrAQAhAAYIXBXPNgBrAQAOAAUI8BHxhwAoAQAAAA==.Ressler:BAABLAAECoEiAAIBAAYIIR+lTAAtAgABAAYIIR+lTAAtAgAAAA==.',Rh='Rhiannøn:BAAALAAECggIEAAAAA==.Rhodesian:BAAALAAECgUIBQABLAAFFAIIBwALABUaAA==.',Ri='Ricvoker:BAAALAADCggICwAAAA==.Rinjii:BAAALAAECggIEgAAAA==.Riwen:BAACLAAFFIETAAMaAAUI4h15AgCrAQAaAAQIVSJ5AgCrAQAiAAIIqAjpFABLAAAsAAQKgUcAAxoACAjpJEACAFYDABoACAjpJEACAFYDACIABwjJHW8LAFsCAAAA.',Ro='Rohlinor:BAAALAADCggIEAABLAAECggIJAAEAK8kAA==.Rook:BAAALAAFFAIIAgAAAA==.',Ry='Ryuko:BAAALAADCgcIBwAAAA==.',Sa='Sabarabarbar:BAACLAAFFIEHAAILAAIIFRpoKwCrAAALAAIIFRpoKwCrAAAsAAQKgR0AAgsACAhUFYt6AMwBAAsACAhUFYt6AMwBAAAA.Sabarabiskos:BAABLAAECoEdAAMGAAgI7h8cLQBhAgAGAAgI7h8cLQBhAgAFAAEIVSGweQBaAAABLAAFFAIIBwALABUaAA==.Saelyana:BAAALAADCggIAgAAAA==.Safrix:BAAALAAECggICAABLAAECgMIAwAHAAAAAA==.',Sc='Sciamano:BAACLAAFFIEKAAIMAAUIjhMwCACoAQAMAAUIjhMwCACoAQAsAAQKgSMAAgwACAgiIaAOAAgDAAwACAgiIaAOAAgDAAEsAAUUBwgNABsAchkA.Scutuma:BAAALAAECgQIDgAAAA==.Scutumo:BAAALAAECgEIAQAAAA==.',Se='Sekira:BAAALAAECgYICgABLAAECggIJAAOACIiAA==.Seppel:BAAALAADCggIDwAAAA==.',Sh='Shadowpi:BAAALAAECgcIEQAAAA==.Shakesbêêr:BAAALAAECgUIBQAAAA==.Shamz:BAAALAADCgYIBgAAAA==.Shaî:BAAALAADCggIFAAAAA==.Shikei:BAAALAAECgIIAgAAAA==.Shinny:BAACLAAFFIEOAAIjAAMI+iQdBwAyAQAjAAMI+iQdBwAyAQAsAAQKgS4AAyMACAhlIkMFAP0CACMACAhlIkMFAP0CAAEABgiUG/1iAPUBAAAA.Shuroko:BAACLAAFFIEGAAIeAAII9xpdAgCyAAAeAAII9xpdAgCyAAAsAAQKgScAAh4ACAjNIcgBABUDAB4ACAjNIcgBABUDAAAA.Shíaná:BAAALAAECgYIDQAAAA==.Shínigamì:BAEBLAAECoExAAILAAgICCReFQAFAwALAAgICCReFQAFAwAAAA==.',Sk='Skeddit:BAAALAAECgMIAwAAAA==.',So='Sollon:BAAALAADCgEIAQAAAA==.Sophriel:BAAALAADCggICAAAAA==.',St='Staudir:BAAALAAFFAIIAgAAAA==.Stealth:BAACLAAFFIEHAAIiAAIIcR9eCQC3AAAiAAIIcR9eCQC3AAAsAAQKgRgAAiIACAjBGjQMAE0CACIACAjBGjQMAE0CAAAA.Stormnìghtì:BAAALAAECgMIAwAAAA==.Stuhl:BAAALAAECgYIEQAAAA==.',Su='Suiriu:BAABLAAECoElAAINAAgIkxaBPAACAgANAAgIkxaBPAACAgAAAA==.Sunaris:BAACLAAFFIEeAAISAAcIoSQuAAACAwASAAcIoSQuAAACAwAsAAQKgSYAAhIACAjIJswAAHwDABIACAjIJswAAHwDAAAA.Surab:BAAALAADCgcIDQAAAA==.',Sz='Szesty:BAAALAAECgIIAgAAAA==.',['Sâ']='Sâramane:BAACLAAFFIEGAAISAAII2CLfCADOAAASAAII2CLfCADOAAAsAAQKgS4AAhIACAg8JJkDAC8DABIACAg8JJkDAC8DAAAA.',Ta='Tacwrk:BAAALAAECgIIAgAAAA==.Talkamar:BAAALAAECgYIEAABLAAFFAUIFQAiABwfAA==.Talyo:BAAALAADCggIDwAAAA==.Tanka:BAAALAADCgIIAgAAAA==.',Te='Terast:BAAALAADCgEIAQAAAA==.',Th='Thanaron:BAACLAAFFIENAAIfAAMI/iQgCAAmAQAfAAMI/iQgCAAmAQAsAAQKgSMAAh8ACAikJYMHAC0DAB8ACAikJYMHAC0DAAAA.Thenehr:BAAALAADCgYIBAAAAA==.Thrilux:BAAALAADCgYIBgAAAA==.Throttnuk:BAACLAAFFIEIAAIZAAMIDxdVAgAEAQAZAAMIDxdVAgAEAQAsAAQKgSUAAhkACAitI5wBADkDABkACAitI5wBADkDAAAA.',Ti='Timeismonney:BAAALAAECgMIBwABLAAECgYIDgAHAAAAAA==.',Tj='Tjul:BAAALAAECgYIBwAAAA==.',To='Toklo:BAAALAADCggICAAAAA==.Tomwolf:BAAALAAECgIIAgAAAA==.Toppernow:BAAALAAECgIIAQAAAA==.',Ts='Tsuyuri:BAAALAADCgcIBwAAAA==.',['Tö']='Törk:BAAALAADCggIEAAAAA==.',Ur='Urunaar:BAAALAADCggICAAAAA==.',Va='Vailara:BAAALAADCgcIBwAAAA==.Valakyra:BAAALAAECgcICgABLAAFFAUIDAAFAM0UAA==.Valoridan:BAAALAADCgcIDQABLAABCgMIAwAHAAAAAA==.Vaterdudu:BAAALAADCgcIFQAAAA==.',Ve='Velzard:BAAALAAECgcICAAAAA==.Veneficus:BAAALAAECggIEAABLAAFFAcIDQAbAHIZAA==.Venegar:BAAALAAECgEIAQAAAA==.',Vi='Victoriá:BAACLAAFFIEHAAIdAAIIKw7LPACPAAAdAAIIKw7LPACPAAAsAAQKgR0AAh0ACAiHGEw4AEsCAB0ACAiHGEw4AEsCAAAA.Vinlai:BAABLAAECoEXAAIBAAcIVgnnqwBqAQABAAcIVgnnqwBqAQAAAA==.',Vo='Volshy:BAACLAAFFIEOAAIEAAMIRQ3GDQDLAAAEAAMIRQ3GDQDLAAAsAAQKgS4AAwQACAiBImQIAAUDAAQACAiBImQIAAUDAAMABgiUE/EYAH8BAAAA.',We='Wenko:BAAALAAECgQIBAAAAA==.',Wi='Wichteltrude:BAABLAAECoEZAAMGAAcIaxv5PgAPAgAGAAcIwBf5PgAPAgAFAAUIaRtVMACMAQAAAA==.',Wo='Wolfgâng:BAAALAADCggIEAAAAA==.',Wu='Wurstwerfer:BAABLAAECoEXAAIfAAcIMw+5PwCFAQAfAAcIMw+5PwCFAQAAAA==.Wutáng:BAAALAAECgIIBAAAAA==.',Xa='Xal:BAAALAADCggIDAAAAA==.Xarkoshaman:BAAALAADCgYIBgAAAA==.',Xi='Xigbar:BAABLAAECoEmAAIOAAgITRlNMABGAgAOAAgITRlNMABGAgAAAA==.',Xo='Xolius:BAAALAAECgYIBgABLAAECggIFgABABceAA==.',Xu='Xuty:BAAALAAECgcIEQAAAA==.',Xy='Xypewlq:BAAALAADCggIGAAAAA==.',Ya='Yahti:BAAALAADCggIDgAAAA==.Yahto:BAABLAAECoEUAAIOAAgIwAVEgQA8AQAOAAgIwAVEgQA8AQAAAA==.Yamyim:BAAALAADCggIEQAAAA==.Yandere:BAABLAAECoEeAAMWAAcI9gxqJQBGAQAWAAcI9gxqJQBGAQARAAYIbwwONQA1AQAAAA==.',Yo='Yolo:BAAALAAECgYICwAAAA==.',Yr='Yrii:BAAALAADCgcIBwAAAA==.',Yu='Yulania:BAAALAADCggICAAAAA==.',Ze='Zephy:BAAALAAECgYIEQAAAA==.Zeranis:BAABLAAECoEkAAIPAAgIhB8yHQC3AgAPAAgIhB8yHQC3AgAAAA==.Zerberas:BAAALAAFFAIIAgAAAA==.Zerodk:BAAALAAECgMIAwAAAA==.',Zr='Zraconati:BAAALAAECgEIAQAAAA==.',Zu='Zuzor:BAAALAAECgIIAwAAAA==.',['Zî']='Zîcklein:BAABLAAECoEeAAINAAcIJx1gKwBBAgANAAcIJx1gKwBBAgAAAA==.',['Ál']='Álganosch:BAAALAADCggIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end