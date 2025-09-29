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
 local lookup = {'Hunter-BeastMastery','Warrior-Fury','Monk-Windwalker','Warlock-Demonology','Shaman-Restoration','Druid-Restoration','Druid-Guardian','Druid-Balance','Paladin-Retribution','Unknown-Unknown','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Priest-Discipline','Paladin-Protection','Priest-Shadow','Mage-Frost','DemonHunter-Vengeance','Shaman-Enhancement','Warrior-Arms','Warlock-Destruction','Shaman-Elemental','Mage-Arcane','Druid-Feral','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Monk-Brewmaster','DeathKnight-Blood','Monk-Mistweaver','Warlock-Affliction','Priest-Holy','Hunter-Marksmanship','Warrior-Protection',}; local provider = {region='EU',realm='Terenas',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ab='Abbytailz:BAABLAAECoEiAAIBAAgIBBA1XwDBAQABAAgIBBA1XwDBAQAAAA==.Abufist:BAAALAADCgYIBwAAAA==.',Ad='Adew:BAABLAAECoEUAAICAAcI+B91KQBkAgACAAcI+B91KQBkAgAAAA==.Adlez:BAAALAAECgMIBAAAAA==.',Ae='Aegwynne:BAAALAAECgQICgAAAA==.Aendryr:BAAALAAECgEIAgAAAA==.Aeshan:BAAALAAECgYIDQABLAAECggIMQADACAZAA==.',Ah='Ahsoorkatano:BAAALAAECgYIBgAAAA==.',Ai='Aidra:BAAALAADCgcICQAAAA==.',Al='Alatariel:BAABLAAECoEWAAIBAAcIMxiiawCkAQABAAcIMxiiawCkAQAAAA==.Alcina:BAAALAADCgcIBwAAAA==.Alecto:BAAALAADCgYIBgAAAA==.Alerya:BAAALAADCgMIAwAAAA==.Alimorrisane:BAAALAAECgcIEAAAAA==.Alistrana:BAABLAAECoEeAAIEAAgIwQ0mHwDpAQAEAAgIwQ0mHwDpAQAAAA==.Alomomola:BAABLAAECoEXAAIFAAYIEiA2NAAcAgAFAAYIEiA2NAAcAgAAAA==.Alteril:BAAALAAECgQICQAAAA==.Alysielqt:BAACLAAFFIESAAIGAAYI8QrxAwCsAQAGAAYI8QrxAwCsAQAsAAQKgTEABAYACAjAIjgGABoDAAYACAjAIjgGABoDAAcACAitFQkKAAwCAAgAAwh2ENZwAJkAAAAA.',An='Analyzer:BAAALAAECgYIDQAAAA==.Annuwka:BAAALAADCgYIBgAAAA==.Anxiety:BAAALAAECgMIAwAAAA==.',Ap='Aphex:BAAALAADCgYIBgAAAA==.Applejuimce:BAAALAADCgQIBAAAAA==.',Ar='Araceli:BAAALAADCgIIAgAAAA==.Arael:BAAALAADCgMIAwAAAA==.Ariadine:BAABLAAECoEhAAIJAAgIjA5WcgDRAQAJAAgIjA5WcgDRAQAAAA==.Arkaos:BAAALAADCggIEgABLAADCggIFgAKAAAAAA==.Arpaclïsse:BAAALAAECgYIBgAAAA==.Arrownoobz:BAAALAAECgYIBgAAAA==.',As='Asari:BAAALAAECggICgAAAA==.Aspirin:BAAALAADCggIEgAAAA==.',Au='Aureial:BAAALAAECgUIBQABLAAFFAMIBwALAOAgAA==.',Av='Avyanna:BAAALAADCggIIAAAAA==.',Az='Azara:BAAALAADCgcIEwABLAAECgYIBgAKAAAAAA==.',Ba='Babadook:BAAALAAECggICAAAAA==.Baddwolf:BAABLAAECoEWAAMMAAYIPAeZLwArAQAMAAYIBQeZLwArAQANAAYIcAUr6AAFAQAAAA==.Baelthas:BAAALAADCgEIAQAAAA==.Balefin:BAAALAADCgYIBgAAAA==.Balvimir:BAAALAAECgcIEAAAAA==.Bao:BAAALAAECggIDQAAAA==.Baryon:BAAALAAECgYIEwAAAA==.Bazzeruk:BAABLAAECoEWAAIOAAYI4Bh5JQC6AQAOAAYI4Bh5JQC6AQAAAA==.',Be='Beautypruts:BAAALAADCggICQABLAAECgIIAgAKAAAAAA==.Bertyr:BAABLAAECoEWAAIBAAcIuSEsOwArAgABAAcIuSEsOwArAgABLAAECggIHgABADggAA==.Bettybear:BAAALAAECgcIEgAAAA==.',Bi='Bigkris:BAAALAADCggICAABLAADCggIFgAKAAAAAA==.Bigrawz:BAABLAAECoEWAAMPAAYIJxC3HwBmAQAPAAYIJxC3HwBmAQAQAAQI5wqsTADWAAAAAA==.Binnky:BAAALAADCgcIBwABLAAECgUIBQAKAAAAAA==.Bips:BAABLAAECoEWAAIRAAYIRh2WCAD5AQARAAYIRh2WCAD5AQAAAA==.Bisomerc:BAAALAADCggICAAAAA==.Bitzy:BAABLAAECoEfAAMGAAcIMRmuKQAMAgAGAAcIMRmuKQAMAgAIAAMIyQp+dwB7AAAAAA==.',Bj='Bjørstrup:BAAALAADCgEIAQAAAA==.',Bl='Blamdruid:BAABLAAECoEhAAIGAAgINx3SEgCdAgAGAAgINx3SEgCdAgAAAA==.Blaziken:BAAALAADCgEIAQAAAA==.Blightlord:BAAALAADCggICAAAAA==.Bloodpumping:BAAALAADCgYIBgAAAA==.',Bo='Bobbylightx:BAAALAAECgUIDAAAAA==.Bodilkjær:BAABLAAECoEdAAIEAAcIXSCkDACIAgAEAAcIXSCkDACIAgAAAA==.Bovarius:BAACLAAFFIEQAAISAAYI8wuyAgBeAQASAAYI8wuyAgBeAQAsAAQKgS4AAxIACAg6HSgMAIkCABIACAg6HSgMAIkCAAkACAi2B0nBAD4BAAAA.Boynextdoor:BAABLAAECoEbAAIJAAgIeyHuEwAQAwAJAAgIeyHuEwAQAwAAAA==.',Br='Bramin:BAAALAAECgYIBwAAAA==.Brevox:BAAALAADCgUIBQAAAA==.Brewgob:BAAALAADCgUIBQAAAA==.Broozelee:BAABLAAECoEWAAIDAAgI9CBSBwAFAwADAAgI9CBSBwAFAwABLAAFFAYIFgATAC4aAA==.Bréunor:BAAALAAECgYIBwAAAA==.',Bs='Bs:BAAALAAECgIIAgAAAA==.',Bu='Bubblebinky:BAAALAAECgYIBgABLAAFFAMIBwALAOAgAA==.Buckcherry:BAAALAADCgcIEQAAAA==.Buckdich:BAABLAAECoEUAAIUAAYI4wYYTAAPAQAUAAYI4wYYTAAPAQAAAA==.Buggernuts:BAAALAADCggIFgAAAA==.Buttbrain:BAACLAAFFIEHAAILAAMI4CB3DQAlAQALAAMI4CB3DQAlAQAsAAQKgTEAAwsACAgoJIQJAEUDAAsACAgoJIQJAEUDABUAAgj2G/JHAHEAAAAA.',By='Byzant:BAAALAAECgQIBAABLAAECgcIGAAFAL4fAA==.',['Bà']='Bàlthazar:BAAALAAECgcIEAAAAA==.',['Bé']='Béorfs:BAAALAAECgMIAwAAAA==.',Ca='Caleb:BAAALAAECgcIDwAAAA==.Caliente:BAAALAAECgUIBQAAAA==.Callandas:BAAALAAECgQICAAAAA==.Calyxanide:BAAALAAECgYICgABLAAFFAMICgAVAIcTAA==.Camdo:BAAALAAECgEIAQAAAA==.Capellini:BAAALAAECgcIEwAAAA==.',Ce='Celestra:BAAALAADCgYIBgABLAADCggIDgAKAAAAAA==.Cerena:BAACLAAFFIETAAIUAAYIBBraAADXAQAUAAYIBBraAADXAQAsAAQKgSgAAhQACAhYJjQBAH0DABQACAhYJjQBAH0DAAAA.',Ch='Chainmedaddy:BAAALAAECggIAgAAAA==.Chen:BAAALAADCgYIBgAAAA==.Chromaprime:BAAALAAECgMIBwABLAAECgYIDwAKAAAAAA==.',Ci='Cirius:BAAALAADCggICAAAAA==.',Co='Contorta:BAABLAAECoEbAAIWAAcIWg7eEACsAQAWAAcIWg7eEACsAQAAAA==.Coraline:BAAALAADCggIDAAAAA==.Corpseeater:BAAALAADCgIIAgAAAA==.Coshh:BAAALAAECgEIAQAAAA==.',Cr='Crazynutter:BAAALAADCgcIDQABLAADCggIFgAKAAAAAA==.Crompas:BAABLAAECoEbAAIOAAYIfh9gGQAVAgAOAAYIfh9gGQAVAgAAAA==.Crour:BAABLAAECoEWAAMCAAgImhc5LwBFAgACAAgIMxc5LwBFAgAXAAEIXRYALgBQAAAAAA==.',['Cé']='Célestra:BAAALAADCgIIAgABLAADCggIDgAKAAAAAA==.',Da='Daddiesgirl:BAAALAADCgIIAgAAAA==.Dadi:BAAALAAECgEIAQAAAA==.Darckense:BAABLAAECoEVAAIIAAYIrxhwOgCYAQAIAAYIrxhwOgCYAQAAAA==.Darkripper:BAAALAADCggIFAABLAADCggIFgAKAAAAAA==.Darkwillow:BAAALAADCgcIDQAAAA==.Darthdun:BAAALAADCgMIAwAAAA==.Davy:BAAALAADCgcIAQAAAA==.',Db='Dbhunter:BAAALAAECgQIBgAAAA==.Dblock:BAABLAAECoEdAAIYAAcIKBOyVAC7AQAYAAcIKBOyVAC7AQAAAA==.',De='Dedolas:BAAALAADCgIIAgAAAA==.Despair:BAAALAAECgQIBQAAAA==.Dethyl:BAAALAAECgYIBgABLAAFFAMICgAGAC4lAA==.',Di='Diizziie:BAAALAAECgQIBwAAAA==.Divalaguna:BAABLAAECoEXAAMZAAYI1gd2gQDXAAAZAAUIIQZ2gQDXAAAFAAQIkwtv1ACaAAAAAA==.Diáblos:BAAALAADCggIFwAAAA==.',Dj='Djyn:BAAALAADCggICAAAAA==.',Do='Docski:BAABLAAECoEiAAIDAAgI4xYwFwAjAgADAAgI4xYwFwAjAgAAAA==.Donkeyfooker:BAAALAADCgYIBgAAAA==.Doorn:BAAALAADCggIDwAAAA==.Dotcomboom:BAAALAADCggICAAAAA==.',Dr='Drahkahris:BAAALAADCgMIAwAAAA==.Dralin:BAABLAAECoEWAAIHAAYI0gX4HQDRAAAHAAYI0gX4HQDRAAAAAA==.Dreamnight:BAAALAADCggIFwAAAA==.Drevnal:BAAALAAECgQIBAAAAA==.Driadus:BAABLAAECoEWAAIHAAcI8SWWAgAHAwAHAAcI8SWWAgAHAwAAAA==.Drogon:BAAALAAECggIDQAAAA==.',Du='Dukaas:BAAALAADCgcICwAAAA==.',Dz='Dzoavits:BAAALAADCggIEAABLAADCggIFgAKAAAAAA==.',['Dà']='Dàrius:BAAALAAECgMIAwAAAA==.',['Dö']='Död:BAAALAADCggICAAAAA==.',Ei='Eiko:BAAALAAECgUIBQABLAAECgYIBgAKAAAAAA==.',Ej='Ej:BAAALAAECgMIBQAAAA==.',El='Eldory:BAABLAAECoEVAAIaAAYISAsEigBKAQAaAAYISAsEigBKAQAAAA==.Elephas:BAABLAAECoEdAAIbAAcInCTbBQDoAgAbAAcInCTbBQDoAgAAAA==.Eleragon:BAAALAADCgMIAwABLAAECgYIDAAKAAAAAA==.Elex:BAAALAAECgEIAQAAAA==.Elisablyat:BAAALAADCgcICwAAAA==.Ellesia:BAAALAADCggIDwABLAAECgYIFwAZANYHAA==.Ellex:BAABLAAECoEiAAIFAAgIERtCJwBOAgAFAAgIERtCJwBOAgAAAA==.Elmira:BAAALAADCggICAAAAA==.',Em='Empíre:BAABLAAECoEdAAINAAYIkBAEuQBbAQANAAYIkBAEuQBbAQABLAAECgcIFAAQALsYAA==.',En='Enelysion:BAABLAAFFIEHAAIbAAIIaSKbBQDJAAAbAAIIaSKbBQDJAAAAAA==.',Er='Eren:BAACLAAFFIEGAAILAAIIIx+eGgC5AAALAAIIIx+eGgC5AAAsAAQKgSQAAgsACAiiIpMRABQDAAsACAiiIpMRABQDAAAA.',Es='Esmënet:BAAALAAECgcIBwAAAA==.Esmëralda:BAAALAADCggICgABLAAECgcIBwAKAAAAAA==.Estibus:BAAALAADCgcIBwAAAA==.',Ev='Evenstar:BAAALAAECgIIAgAAAA==.Evàngeline:BAAALAAECgUIBQAAAA==.',Fe='Fearless:BAAALAAECggICAAAAA==.Fedayin:BAAALAAECgIIAgAAAA==.Feiman:BAAALAADCggICAABLAAECggICgAKAAAAAA==.Felixs:BAABLAAECoEmAAQGAAgIHSIVCAADAwAGAAgIHSIVCAADAwAIAAEIwAo5jAA0AAAHAAEIrg7vLQAoAAAAAA==.Feydrea:BAAALAAECggICAABLAAFFAMICwAJAOwdAA==.',Fi='Fiddles:BAAALAADCggIIAABLAAECgYIEwAKAAAAAA==.',Fl='Flaaffy:BAAALAADCggIEAAAAA==.Flaps:BAAALAAECgIIAgABLAAECggIEQAKAAAAAA==.Flashbacks:BAAALAADCgYIBgAAAA==.Fluffycuddle:BAAALAADCgMIAwAAAA==.',Fo='Forfe:BAABLAAECoEmAAIaAAgISRtULQB3AgAaAAgISRtULQB3AgAAAA==.',Fr='Frank:BAACLAAFFIETAAMOAAYIyRb+AwC2AQAOAAYIyRb+AwC2AQAJAAEI5Qa6RQBFAAAsAAQKgS4AAw4ACAjtHe0KAKgCAA4ACAjtHe0KAKgCAAkABghIERbCADwBAAAA.Frelsey:BAAALAAFFAQIBAAAAA==.Fritch:BAABLAAECoEWAAIVAAgIRxt1CwB2AgAVAAgIRxt1CwB2AgAAAA==.',Fu='Fuzeta:BAAALAADCgEIAQAAAA==.',Ga='Gaaskermel:BAAALAADCgMIAwAAAA==.Galehad:BAABLAAECoEWAAISAAcIzBMeKgBqAQASAAcIzBMeKgBqAQAAAA==.Ganicus:BAAALAADCggICAAAAA==.',Ge='Geirask:BAAALAAECgEIAQABLAAFFAYIEQAYAGEaAA==.',Gh='Ghangy:BAABLAAECoEiAAIaAAgI3hViQQAjAgAaAAgI3hViQQAjAgAAAA==.',Gi='Giffas:BAAALAADCggICAAAAA==.Gihei:BAAALAAECgYICQAAAA==.Gilrandar:BAAALAAECgEIAQAAAA==.Gimblie:BAAALAADCggIDwABLAAECggIJgAGAB0iAA==.Gipsy:BAAALAAECgEIAQAAAA==.',Gl='Glitch:BAAALAAECgcIBwABLAAFFAQIBwAcABYSAA==.Glitchdragon:BAACLAAFFIEHAAMcAAQIFhLUCgDzAAAcAAMI5hLUCgDzAAAdAAIIeA8BBQCYAAAsAAQKgTEABBwACAhvIr8IAP4CABwACAgCIr8IAP4CAB0ABggqG3wGAPwBAB4AAQjWCC05ACkAAAAA.Glitchfist:BAAALAADCgcIBwABLAAFFAQIBwAcABYSAA==.',Go='Golo:BAAALAAECgYICwAAAA==.',Gr='Graius:BAABLAAECoEWAAMXAAcIZxFuEwB6AQACAAcIUgybYgCKAQAXAAYIAhNuEwB6AQAAAA==.Gremit:BAAALAADCgYIBgAAAA==.',Ha='Halewyn:BAABLAAECoEVAAINAAYIzRBNsABpAQANAAYIzRBNsABpAQAAAA==.Haworthia:BAACLAAFFIEMAAMZAAQIjwYzFwCoAAAZAAMISAIzFwCoAAAFAAEIXQDcTwAvAAAsAAQKgS4AAhkACAg+EHE9AN8BABkACAg+EHE9AN8BAAAA.',He='Healya:BAAALAADCgUIBQAAAA==.Heikneuter:BAAALAAECgYICQAAAA==.Herleif:BAAALAADCggICAABLAAFFAMICwAJAOwdAA==.Hexa:BAAALAADCgIIAgABLAADCgIIAgAKAAAAAQ==.',Ho='Hojo:BAAALAADCgYIBgAAAA==.Hoktouh:BAAALAAECgYIDwABLAAFFAMIBwALAOAgAA==.Holdmykeg:BAAALAAECggIDwABLAAFFAQIDQAfAAsSAA==.Homeless:BAABLAAECoEiAAMgAAgIfB8ABwDTAgAgAAgIfB8ABwDTAgANAAQIRRW97gD2AAAAAA==.Honeydiw:BAABLAAECoEXAAMDAAYIywr1NwAbAQADAAYIywr1NwAbAQAhAAYIjw7wKQAYAQAAAA==.Honglair:BAAALAADCgYICAAAAA==.',Hr='Hriss:BAABLAAECoEhAAIfAAcIdSLjCACvAgAfAAcIdSLjCACvAgAAAA==.',Hu='Huinë:BAAALAAECgQIBgABLAAECgQICQAKAAAAAA==.Huquintas:BAAALAAECgEIAwAAAA==.',Ia='Ianthe:BAAALAADCgEIAQAAAA==.',Ic='Icywind:BAAALAAECggIKwAAAQ==.',Ie='Iemon:BAAALAADCgUIBQAAAA==.',Il='Illidankmeme:BAAALAAECgMIAQAAAA==.Ilyfaye:BAAALAAECgUIBQAAAA==.',Im='Imnotnice:BAABLAAECoEXAAIPAAYIxREpHgByAQAPAAYIxREpHgByAQAAAA==.',In='Insievwinsie:BAAALAAECgYIBwAAAA==.',Ir='Ironblade:BAAALAADCggICAABLAAECgcIGQAdAC8cAA==.Irsara:BAAALAAECgYIEwAAAA==.',Is='Iseldiarys:BAAALAADCgYIBgAAAA==.Ishana:BAAALAADCgcIBwAAAA==.Isunael:BAACLAAFFIERAAIYAAYIYRpGBQAnAgAYAAYIYRpGBQAnAgAsAAQKgS0ABBgACAjwJa8DAG8DABgACAivJa8DAG8DACIABwigG6kHADECAAQAAQgYEV6CAD8AAAAA.',Iu='Iuli:BAAALAAECgIIAgAAAA==.',Iw='Iwast:BAAALAADCgYIDAAAAA==.',Ja='Jabroni:BAACLAAFFIEGAAIDAAIIWB4iCwCeAAADAAIIWB4iCwCeAAAsAAQKgSsAAgMACAhJJGcDAEsDAAMACAhJJGcDAEsDAAAA.Jackzar:BAAALAADCgUIBQAAAA==.Jauthor:BAAALAADCggICAAAAA==.Jayjayjinx:BAABLAAECoEWAAIIAAgIPxtqGABxAgAIAAgIPxtqGABxAgAAAA==.',Je='Jendi:BAAALAAECgYIEQABLAAECggIMQADACAZAA==.Jenever:BAABLAAECoEZAAISAAcIXxFyJwB+AQASAAcIXxFyJwB+AQAAAA==.',Ji='Jinovchis:BAAALAADCgYIBgAAAA==.',Jo='Jojolene:BAAALAAECggICAAAAA==.',Ju='Juiice:BAAALAADCgcICgAAAA==.',Ka='Kalmin:BAAALAAECgYICAABLAAFFAEIAQAKAAAAAA==.Kazmere:BAABLAAECoEWAAIjAAYI+hBoVwBUAQAjAAYI+hBoVwBUAQAAAA==.',Ke='Keir:BAAALAADCggIEwAAAA==.Keiththetwat:BAAALAADCgcIBwAAAA==.Keldrack:BAABLAAECoEVAAMcAAYI/AX9QQAGAQAcAAYI/AX9QQAGAQAeAAYIsQKeKwCsAAAAAA==.Kenkyukai:BAACLAAFFIEFAAIhAAMI+gt4CADaAAAhAAMI+gt4CADaAAAsAAQKgSUAAiEACAj7GpINAGMCACEACAj7GpINAGMCAAAA.Kennygee:BAAALAADCgEIAQAAAA==.Keybrickeith:BAAALAADCggICgAAAA==.Keycard:BAAALAADCgcIBwAAAA==.',Kh='Khalldrogo:BAAALAAECgYICgAAAA==.',Ki='Kiku:BAAALAADCggIDgAAAA==.Kinusha:BAAALAADCggIFgABLAAECggIMQADACAZAA==.Kiriosh:BAABLAAECoEdAAIDAAcICRpRHgDcAQADAAcICRpRHgDcAQAAAA==.Kissmyaxe:BAAALAADCgcIBwAAAA==.Kitchlol:BAABLAAFFIEGAAIPAAIIAgeREAB/AAAPAAIIAgeREAB/AAAAAA==.Kixao:BAAALAAECgYIEAAAAA==.',Kl='Klyvarn:BAACLAAFFIELAAINAAQIlRMODQBRAQANAAQIlRMODQBRAQAsAAQKgR4AAw0ACAg+I7EPACIDAA0ACAg+I7EPACIDACAAAgiiB+k6AEQAAAAA.',Kn='Knallala:BAABLAAECoEWAAILAAcImA7IfQCXAQALAAcImA7IfQCXAQAAAA==.Knuckleskull:BAABLAAECoEeAAMNAAgINQ/0cgDYAQANAAgINQ/0cgDYAQAgAAEIZwNHQQAlAAAAAA==.Knucknorris:BAABLAAECoEWAAIfAAcI0yGPCQCgAgAfAAcI0yGPCQCgAgABLAAECggIGgAZAPYfAA==.',Ko='Kobaaz:BAAALAAECgYIEwAAAA==.Kolbasha:BAAALAAECggIBgAAAA==.',Kr='Kroll:BAAALAAECgEIAQAAAA==.',Ku='Kungfucow:BAAALAAECgYIEwAAAA==.Kurillia:BAABLAAECoEVAAIHAAYIVg6NFwAdAQAHAAYIVg6NFwAdAQAAAA==.Kuzzko:BAAALAAECgYIBgABLAAECggIIAAFAKskAA==.',Ky='Kyrugan:BAACLAAFFIELAAIJAAMI7B26CgAiAQAJAAMI7B26CgAiAQAsAAQKgScAAgkACAihIiIUAA8DAAkACAihIiIUAA8DAAAA.',['Kí']='Kítten:BAABLAAECoEVAAIjAAYIkh4QLwADAgAjAAYIkh4QLwADAgAAAA==.',La='Lansera:BAAALAAECgcIEAAAAA==.',Le='Legendairy:BAAALAAECgcIDwAAAA==.Lenox:BAAALAAECgcIEAAAAA==.Lenthyr:BAAALAAECgQIBwAAAA==.Letummortis:BAABLAAECoEYAAMMAAgIWxp/EAA4AgAMAAgIxxV/EAA4AgAgAAUIZx6MFgC0AQAAAA==.',Li='Liamm:BAAALAAECgUIBQAAAA==.Limitless:BAAALAAECgYICgAAAA==.Linkle:BAAALAADCggICAAAAA==.Litá:BAAALAAECgYIBgABLAAECggIEgANACMaAA==.Lizbella:BAABLAAECoEaAAIBAAcI3xXbXgDCAQABAAcI3xXbXgDCAQAAAA==.',Lo='Lockblock:BAAALAADCgUIBQAAAA==.Lodril:BAAALAADCgIIAgAAAA==.Lolaen:BAAALAAECgIIAgAAAA==.Lolik:BAACLAAFFIEMAAIDAAMIdiORBAAxAQADAAMIdiORBAAxAQAsAAQKgRoAAgMACAivJLQDAEYDAAMACAivJLQDAEYDAAAA.Lomegalu:BAAALAAECgYIBgAAAA==.Lonely:BAAALAAECggIEQABLAAECggIHQAFAOsVAA==.Loovia:BAAALAADCggIFgAAAA==.Louna:BAAALAADCggICAAAAA==.',Lu='Lucan:BAAALAADCggIDQAAAA==.Lucasgff:BAAALAADCggICAAAAA==.Lumnon:BAAALAADCgEIAQAAAA==.Lunak:BAABLAAECoEpAAICAAgIcBx9HAC1AgACAAgIcBx9HAC1AgAAAA==.Lurna:BAABLAAECoEcAAIBAAcI4RDkeQCEAQABAAcI4RDkeQCEAQAAAA==.',Ma='Maas:BAAALAAECgYIBgAAAA==.Machupo:BAAALAADCgUIBQAAAA==.Madmobster:BAAALAAECggICAAAAA==.Madrigal:BAAALAAECgcIEAAAAA==.Magoa:BAABLAAECoEWAAIUAAcIURK3KgCwAQAUAAcIURK3KgCwAQAAAA==.Malakit:BAACLAAFFIEKAAIVAAMIhxNjBADLAAAVAAMIhxNjBADLAAAsAAQKgRoAAhUACAjrFr4ZAL0BABUACAjrFr4ZAL0BAAAA.Manshan:BAAALAADCgQIBAAAAA==.Marcai:BAAALAAECgYIDQAAAA==.',Mc='Mcpuff:BAAALAAECgUIBQAAAA==.',Me='Memebeam:BAAALAAECgIIAgAAAA==.Meowforpi:BAAALAADCgcIBwAAAA==.Meowmeow:BAAALAAFFAIIAgAAAA==.Messi:BAAALAAECgEIAQAAAA==.',Mi='Milaazul:BAAALAAECgQIBAAAAA==.Millionia:BAAALAADCggIDgAAAA==.Minimaw:BAAALAADCgIIAgABLAAECgUIBQAKAAAAAA==.',Mn='Mnementhia:BAABLAAECoEWAAIbAAYIOhEzHgB5AQAbAAYIOhEzHgB5AQAAAA==.',Mo='Mogrotth:BAAALAAECgYIBgAAAA==.Monegasse:BAAALAAECgQIBAAAAA==.Monkita:BAAALAAECgEIAQAAAA==.Moot:BAAALAADCgYIAgAAAA==.Morrigan:BAAALAADCggICAAAAA==.Mortva:BAAALAAECgIIAgAAAA==.Mourn:BAABLAAECoEdAAMMAAcIahlgEwAWAgAMAAcIahlgEwAWAgANAAMI0xDaCwGwAAAAAA==.',Mp='Mpalarinos:BAAALAADCgQIBAAAAA==.',Mu='Muhri:BAAALAAECgYIDwAAAA==.Murrett:BAABLAAECoEWAAIFAAcI5R2kMgAhAgAFAAcI5R2kMgAhAgAAAA==.',My='Mylder:BAAALAADCgIIAgAAAA==.Mylderman:BAAALAAECgMIBgAAAA==.Mylen:BAAALAAECgEIAQAAAA==.Mynth:BAAALAAECgYIDQAAAA==.Myrtle:BAAALAAECgcICgAAAA==.Mystical:BAAALAAECgIIAgAAAA==.',['Mó']='Mória:BAAALAAECgYIEgAAAA==.',Na='Naeldrath:BAAALAAECgEIAwAAAA==.Nantosuelta:BAAALAAECgYICAAAAA==.Nardox:BAAALAAECgcIBwAAAA==.Nausicaä:BAAALAADCgcIBwAAAA==.',Ne='Nep:BAAALAADCggIEAAAAA==.Nespina:BAAALAADCgcIBwAAAA==.Nevra:BAAALAAECgYICAAAAA==.Nez:BAABLAAECoEaAAIZAAgI9h93EQDtAgAZAAgI9h93EQDtAgAAAA==.Nezdruid:BAAALAAECgcIDwABLAAECggIGgAZAPYfAA==.Nezuko:BAAALAAECggIAQABLAAFFAEIAQAKAAAAAA==.Nezulidh:BAAALAAECgUIBQABLAAECggIGgAZAPYfAA==.',Ni='Nightbert:BAABLAAECoEeAAIBAAgIOCDGGQDGAgABAAgIOCDGGQDGAgAAAA==.Nightrider:BAAALAADCgMIAwAAAA==.',No='Norbo:BAAALAAECgEIAQAAAA==.Norvegikus:BAAALAAECgcICwAAAA==.Notalock:BAAALAAECgcIEwAAAA==.Novalie:BAABLAAECoEXAAIJAAcInhTabgDYAQAJAAcInhTabgDYAQAAAA==.',['Ná']='Nástybrawn:BAACLAAFFIERAAICAAUIghe7BgDNAQACAAUIghe7BgDNAQAsAAQKgSgAAgIACAhqJG8QAAsDAAIACAhqJG8QAAsDAAAA.',['Nî']='Nîdhel:BAABLAAECoEbAAMkAAgIsB0wGwBzAgAkAAgIVxswGwBzAgABAAUIoh86YwC4AQAAAA==.',['Nó']='Nódin:BAAALAAECgcIEwAAAA==.',Ob='Obèryn:BAAALAADCggICAAAAA==.',Od='Odinsbane:BAAALAAECgQICwAAAA==.',Of='Offred:BAAALAADCgcIDQABLAAECgIIAgAKAAAAAA==.',Og='Oghraan:BAAALAAECggICAABLAAECggIFAAiAFoRAA==.Ogroth:BAABLAAECoEUAAMiAAgIWhG+FABUAQAiAAYI2xG+FABUAQAYAAgICQqklQAEAQAAAA==.',On='Onlyhorns:BAAALAAECgcIBwAAAA==.',Oo='Oorling:BAABLAAFFIEHAAIHAAIIlw//BABxAAAHAAIIlw//BABxAAAAAA==.Oorshi:BAAALAADCggICAAAAA==.Oorthael:BAAALAADCgIIAgAAAA==.Ooze:BAABLAAECoEbAAMCAAgIySNdCABIAwACAAgIySNdCABIAwAXAAEI/yQXLQBWAAABLAAFFAYIFgATAC4aAA==.',Or='Orakel:BAAALAADCgcIBwAAAA==.',Os='Osloan:BAAALAAECgYIBwAAAA==.',Pa='Pajmental:BAAALAADCgcIBwAAAA==.Paladíno:BAABLAAECoEWAAIJAAYIDQi92AAOAQAJAAYIDQi92AAOAQAAAA==.Palaeopeach:BAAALAAECgcIBwAAAA==.Paltnacke:BAACLAAFFIEGAAICAAII6SJ6EwDTAAACAAII6SJ6EwDTAAAsAAQKgR0AAgIACAhcJRkIAEoDAAIACAhcJRkIAEoDAAAA.Pammeow:BAACLAAFFIEUAAIIAAYIhyL4AgDqAQAIAAYIhyL4AgDqAQAsAAQKgSgAAggACAjLJjwBAIIDAAgACAjLJjwBAIIDAAAA.Pandion:BAAALAAECgMIBAAAAA==.Pangbruden:BAAALAADCggIIAAAAA==.',Pe='Pestoorcide:BAAALAADCggICAAAAA==.',Ph='Phaetón:BAAALAADCggIDgAAAA==.Phailadin:BAAALAADCgQIBAAAAA==.Pheebe:BAAALAAECgMIAwAAAA==.',Pi='Picasso:BAAALAADCggICAABLAAECgIIAgAKAAAAAA==.Pieces:BAAALAAECgYIBwAAAA==.Pika:BAAALAADCgIIAgAAAA==.',Pl='Plaguelander:BAAALAAECgUIBQAAAA==.Platotem:BAAALAAECgUIDwAAAA==.',Po='Polymorph:BAAALAAECggIDwAAAA==.Porugas:BAAALAADCggICAAAAA==.',Pr='Praydem:BAAALAAECgYICAAAAA==.Primrose:BAABLAAECoEjAAIBAAgIlRfhRQAHAgABAAgIlRfhRQAHAgAAAA==.',Qu='Quigone:BAABLAAECoEXAAIEAAYINB72FwAaAgAEAAYINB72FwAaAgABLAAECggIJgAGAB0iAA==.Quilthalas:BAAALAAECgYIEwAAAA==.',Ra='Raeka:BAAALAAECgMIBwAAAA==.Rage:BAAALAAECgcIDQAAAA==.Ragnarøkkr:BAAALAADCgUIBQABLAAECgEIAQAKAAAAAA==.Rahl:BAAALAADCgYIBgAAAA==.Rammsund:BAAALAAECgcIEQAAAA==.Randuwin:BAAALAADCgEIAQAAAA==.Ranesh:BAAALAAECgQIBgAAAA==.Rawlplug:BAABLAAECoEhAAIIAAcIyBv0HwAxAgAIAAcIyBv0HwAxAgAAAA==.',Re='Reliafluffy:BAAALAAECgYIBgAAAA==.Rendaeri:BAACLAAFFIEJAAILAAMIURFgEwDsAAALAAMIURFgEwDsAAAsAAQKgS4AAgsACAiBHjIkAKsCAAsACAiBHjIkAKsCAAAA.Revok:BAABLAAECoEnAAICAAgIuyG0DQAeAwACAAgIuyG0DQAeAwAAAA==.Revoker:BAAALAADCggICAAAAA==.',Ri='Richarda:BAAALAAECgIIAgAAAA==.',Ro='Rocklockster:BAAALAAECggICAAAAA==.Rocoto:BAAALAAECgYIEAAAAA==.Rollothenice:BAAALAADCggIDwAAAA==.Rosscko:BAAALAAECgYICAAAAA==.',Ru='Rualim:BAAALAADCggICAAAAA==.Ruhala:BAAALAAECgYIBgAAAA==.Rulai:BAAALAADCggIJQAAAA==.Runebladez:BAAALAADCgUIBQABLAAECggIKwAGAGAiAA==.',Ry='Ryac:BAABLAAECoEhAAIlAAcIpA9sNwBgAQAlAAcIpA9sNwBgAQAAAA==.Ryzuki:BAAALAAECgEIAQAAAA==.',['Rä']='Räsvelg:BAAALAAECgQIBAABLAAFFAMICgAVAIcTAA==.',['Rå']='Råge:BAAALAAECgQIBAABLAAECgYIBgAKAAAAAA==.',['Rè']='Rèkt:BAABLAAECoEXAAIJAAYI9BwZZADwAQAJAAYI9BwZZADwAQAAAA==.',Sa='Saeraphina:BAAALAAECggICAAAAA==.Sallyjo:BAAALAAECgUIEAAAAA==.Sammuell:BAAALAAECgYIDQAAAA==.Sandalphon:BAAALAAECgUICAAAAA==.Saplîng:BAAALAAECgEIAQAAAA==.Sayle:BAAALAADCgEIAQAAAA==.',Sc='Scareclaw:BAAALAADCgUIBQAAAA==.Scurlban:BAABLAAECoEWAAIEAAYIWRs3HwDoAQAEAAYIWRs3HwDoAQAAAA==.',Se='Senap:BAAALAAECgQIBAAAAA==.Serindè:BAAALAAECgIIAgAAAA==.Serinety:BAAALAAECgEIAQAAAA==.Seyla:BAAALAADCggIDgABLAAECgMIBwAKAAAAAA==.',Sg='Sgtmifii:BAAALAADCgYICQAAAA==.',Sh='Shadowbladee:BAAALAADCgIIAgAAAA==.Shelayra:BAABLAAECoErAAMIAAgIWSD9EAC+AgAIAAgIWSD9EAC+AgAGAAMIagqhmQCEAAAAAA==.Shimmyshammy:BAAALAADCggICAAAAA==.Shintaox:BAAALAAECgIIAgAAAA==.Shockedsloth:BAABLAAECoEYAAIZAAcI7RPgPwDVAQAZAAcI7RPgPwDVAQAAAA==.Shyyba:BAAALAAECgYIEgAAAA==.Shímsham:BAACLAAFFIEQAAIZAAYIKiAJBQDtAQAZAAYIKiAJBQDtAQAsAAQKgS4AAhkACAj4JdoCAHYDABkACAj4JdoCAHYDAAAA.',Si='Sibylla:BAAALAAECgMIAwAAAA==.Siepelrocker:BAAALAAECgUICAABLAAECgYIBgAKAAAAAA==.Silvers:BAAALAADCgYIBgAAAA==.Simplehuman:BAABLAAECoEVAAIBAAcIPAjnnQA7AQABAAcIPAjnnQA7AQAAAA==.',Sj='Sjarcanist:BAABLAAECoEVAAMUAAcICAu5NwBrAQAUAAcICAu5NwBrAQAaAAMIdgO90QBPAAAAAA==.',Sk='Skippedabeat:BAAALAADCgQIBAAAAA==.Skuld:BAAALAADCgEIAQAAAA==.Skweel:BAABLAAECoEbAAIUAAcIRRJ2JwDCAQAUAAcIRRJ2JwDCAQAAAA==.',Sl='Slompalompa:BAAALAAECgcIBwAAAA==.Sluuzhar:BAAALAADCgYIBgAAAA==.Slydee:BAAALAAECgcIDQAAAA==.',Sn='Sneezeweed:BAAALAADCgYIBQABLAAFFAMICgAVAIcTAA==.Snowsnout:BAAALAAECgIIBAAAAA==.Snowydemon:BAAALAAECgMIBAAAAA==.',So='Solarlights:BAABLAAFFIEFAAIIAAMIPBW5CQD3AAAIAAMIPBW5CQD3AAAAAA==.Soulpresent:BAAALAAECgMIBAABLAAECggICAAKAAAAAA==.',Sp='Spatial:BAAALAAECgYIBgAAAA==.Spijskop:BAAALAAECgUIBQAAAA==.Spritzee:BAAALAAECgUICwAAAA==.',Sq='Squigy:BAAALAAECgQIBQABLAAECgUIBQAKAAAAAA==.',Ss='Sshrek:BAAALAAECgMIBAAAAA==.',St='Stagstalker:BAABLAAECoEbAAIBAAcI9B72LwBWAgABAAcI9B72LwBWAgAAAA==.Stalk:BAAALAAECgcIEAAAAA==.Stepxsismish:BAAALAAECgMIBgAAAA==.Stoneheart:BAAALAADCggIGAAAAA==.Stretch:BAAALAADCggIBAAAAA==.',Su='Sude:BAABLAAECoEWAAIjAAcIfxUERQCbAQAjAAcIfxUERQCbAQAAAA==.',Sw='Swifftménd:BAAALAAECgUIBgAAAA==.',Sy='Syelen:BAAALAADCggIFgAAAA==.Syrastrasza:BAAALAAECgEIAQAAAA==.',Ta='Tallera:BAABLAAECoEcAAIZAAYI2Rg9QQDPAQAZAAYI2Rg9QQDPAQABLAAECgcIIQAfAHUiAA==.Talwyn:BAABLAAECoEiAAIEAAgIBhHOGwD9AQAEAAgIBhHOGwD9AQAAAA==.Tart:BAAALAADCggICAAAAA==.Taylorswifty:BAAALAADCgQIBAAAAA==.',Te='Tegaela:BAABLAAECoEUAAIeAAcIZRqjEQDgAQAeAAcIZRqjEQDgAQAAAA==.Teleportatoe:BAAALAADCgYIBgABLAADCgYIBgAKAAAAAA==.Tessi:BAABLAAECoEWAAIhAAYIuhIHJABOAQAhAAYIuhIHJABOAQAAAA==.',Th='Thatsbadass:BAABLAAECoEYAAILAAgIkQqVdwCjAQALAAgIkQqVdwCjAQABLAAFFAQIDQAfAAsSAA==.Thegis:BAAALAAECgYIDQAAAA==.Theorocks:BAAALAAECgYIEwAAAA==.Theresina:BAAALAAECgcIDwABLAAFFAMICwAJAOwdAA==.Thisbearge:BAAALAAECgcIEwAAAA==.Thrallzdad:BAABLAAECoEVAAIYAAgIrAeieABUAQAYAAgIrAeieABUAQAAAA==.Thundermuff:BAAALAAECgIIAgAAAA==.Thylae:BAAALAAECgIIAgAAAA==.',Ti='Tigon:BAAALAAECgYIEAAAAA==.Tissy:BAAALAAECggICAAAAA==.',To='Toblerone:BAABLAAECoEZAAMdAAcILxx2BQAlAgAdAAcIMxt2BQAlAgAcAAYIbxdxMgBuAQAAAA==.Tolstokotov:BAAALAAECggIDgAAAA==.Toteamic:BAAALAAECgQIBgAAAA==.Totemburn:BAAALAAECggIAQAAAA==.Totemin:BAACLAAFFIEJAAIWAAMIZgnVAgDhAAAWAAMIZgnVAgDhAAAsAAQKgSYAAhYACAjmHgoEANkCABYACAjmHgoEANkCAAAA.',Tr='Treesurgeon:BAAALAADCggIDwABLAAECggIJQAHAJEjAA==.Trevah:BAAALAADCgcIBwABLAAECggIJgAEAN0ZAA==.Trinkywinky:BAAALAADCgYIBgABLAAECggIGAAMAFsaAA==.Troetie:BAAALAAECgEIAwAAAA==.',Ts='Tsiona:BAAALAADCgQIBAAAAA==.Tsira:BAAALAADCggIIAAAAA==.',Tu='Tundra:BAABLAAECoEWAAIFAAYI+hNNdABeAQAFAAYI+hNNdABeAQAAAA==.',Ty='Typhoon:BAABLAAECoEYAAMFAAcIvh9LHQB+AgAFAAcIvh9LHQB+AgAZAAIIUAmfngBXAAAAAA==.',['Tå']='Tåylør:BAABLAAECoEgAAIUAAcIQBgFHwD7AQAUAAcIQBgFHwD7AQAAAA==.',['Të']='Tëddy:BAAALAAECggIDgAAAA==.',['Tì']='Tìm:BAAALAAECgEIAQAAAA==.',Um='Um:BAAALAADCgUIBQAAAA==.',Un='Unaruid:BAABLAAECoEVAAMHAAYIyRwUEACRAQAHAAUIgRwUEACRAQAbAAEIMB60OQBYAAAAAA==.',Va='Valefor:BAAALAAECgYIDQAAAA==.',Ve='Venomocity:BAAALAADCgUIBgAAAA==.',Vi='Virah:BAABLAAECoEdAAMYAAYIYBIkaACBAQAYAAYIYBIkaACBAQAEAAMICgygZACpAAAAAA==.',Vo='Voidessence:BAAALAADCggIEgAAAA==.Voidooze:BAACLAAFFIEWAAITAAYILhpUAgA2AgATAAYILhpUAgA2AgAsAAQKgRgAAhMACAiRJGMOAO0CABMACAiRJGMOAO0CAAAA.Volana:BAAALAADCggICAABLAAECgcIEAAKAAAAAA==.Volmi:BAAALAADCgEIAQAAAA==.Volmy:BAAALAAECgcIEQAAAA==.',['Ví']='Víolet:BAAALAADCgYIBgAAAA==.',Wh='Whitesaman:BAABLAAECoEdAAIFAAgI6xXgOQAIAgAFAAgI6xXgOQAIAgAAAA==.Whitvoker:BAAALAADCggIEAAAAA==.',Wi='Wickfield:BAAALAAECggICAAAAA==.Willowfaith:BAAALAADCgcIAQAAAA==.Wissan:BAABLAAECoEWAAISAAYIdhvrGwDcAQASAAYIdhvrGwDcAQAAAA==.',Ya='Yardie:BAABLAAECoEWAAIJAAYItx8GVwAOAgAJAAYItx8GVwAOAgAAAA==.Yardos:BAABLAAECoEWAAIJAAcI5A20sgBZAQAJAAcI5A20sgBZAQAAAA==.',Ye='Yennefoor:BAAALAAECgYIBwAAAA==.',Yh='Yh:BAAALAADCggIFwAAAA==.',Yo='Yomi:BAAALAADCggIDwAAAA==.',Ys='Ysuren:BAABLAAECoEmAAMEAAgI3RnlDgBuAgAEAAgIphnlDgBuAgAiAAYIYRCSEgBxAQAAAA==.',Yu='Yuna:BAABLAAECoEWAAIEAAgI8Aj5JwC1AQAEAAgI8Aj5JwC1AQAAAA==.',Za='Zabian:BAABLAAECoEnAAMhAAgITCJIBAAPAwAhAAgITCJIBAAPAwADAAYIDQ6MNQAtAQAAAA==.Zaraphie:BAAALAADCggICAABLAAECgcIGAAZAO0TAA==.Zas:BAAALAAECggICAAAAA==.',Ze='Zelis:BAAALAAECgEIAQAAAA==.Zerakel:BAAALAADCggICAAAAA==.Zerrard:BAABLAAECoEWAAIGAAgIDBeRJgAcAgAGAAgIDBeRJgAcAgAAAA==.Zeylu:BAAALAAECgMIBwAAAA==.Zezth:BAABLAAECoEfAAIVAAgIUBBAIgBlAQAVAAgIUBBAIgBlAQAAAA==.',Zh='Zhuna:BAABLAAECoExAAMDAAgIIBlxEgBdAgADAAgIIBlxEgBdAgAfAAMIFREyNQCOAAAAAA==.',Zi='Ziukiest:BAABLAAECoEfAAIjAAgIHRgTLgAIAgAjAAgIHRgTLgAIAgAAAA==.',Zo='Zoozabar:BAAALAAECgYIBgAAAA==.',Zs='Zsoka:BAABLAAECoEWAAIZAAYIXw2wYgBYAQAZAAYIXw2wYgBYAQAAAA==.',Zu='Zugzuug:BAAALAAECgYIBgAAAA==.Zukie:BAAALAAECgcIDgAAAA==.Zuulabar:BAAALAADCgEIAQAAAA==.Zuzz:BAAALAAECgEIAQABLAAECggIIgAgAHwfAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end