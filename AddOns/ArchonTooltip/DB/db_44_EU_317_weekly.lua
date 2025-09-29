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
 local lookup = {'Evoker-Devastation','Druid-Feral','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Druid-Restoration','Paladin-Retribution','Monk-Brewmaster','Monk-Windwalker','Warrior-Fury','Rogue-Subtlety','Warlock-Demonology','Warrior-Protection','Warrior-Arms','Unknown-Unknown','Priest-Shadow','DeathKnight-Frost','Priest-Discipline','Shaman-Restoration','Paladin-Protection','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Holy','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Unholy','Shaman-Elemental','Monk-Mistweaver','Druid-Guardian','DeathKnight-Blood','Rogue-Assassination','Rogue-Outlaw','Mage-Arcane','Mage-Frost','Mage-Fire','Druid-Balance','Warlock-Affliction','Shaman-Enhancement',}; local provider = {region='EU',realm='Nordrassil',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abraxos:BAAALAADCgIIAgAAAA==.',Ac='Achiliesheal:BAAALAAECggICgAAAA==.',Ad='Adhrazan:BAAALAAECgcIEwAAAA==.Adorien:BAABLAAECoEZAAIBAAcIfBJ2KQCrAQABAAcIfBJ2KQCrAQAAAA==.Adyen:BAAALAAECgYIBgABLAAECggIGQACANUcAA==.Adyenchi:BAAALAAECgMIAwABLAAECggIGQACANUcAA==.Adyendh:BAAALAAECggIDgABLAAECggIGQACANUcAA==.Adyenstorm:BAAALAAECggIBQAAAA==.Adyenzeal:BAAALAAECggICAABLAAECggIGQACANUcAA==.',Ae='Aeleisia:BAABLAAECoEjAAQDAAgIYyBaGwC5AgADAAgInh9aGwC5AgAEAAYILh01CwDGAQAFAAUIvBpQRwB5AQAAAA==.',Af='Afterglow:BAABLAAECoEnAAIGAAgIVRXyKgACAgAGAAgIVRXyKgACAgAAAA==.',Ag='Agnar:BAAALAAECgYICAAAAA==.',Al='Alcides:BAAALAADCggIIQAAAA==.Alfréd:BAAALAAECgYIDgAAAA==.Alicé:BAABLAAECoEVAAIHAAgIQxt7MgB6AgAHAAgIQxt7MgB6AgAAAA==.Althuin:BAABLAAECoEeAAIIAAcINiIICQCpAgAIAAcINiIICQCpAgAAAA==.',Am='Amberlé:BAAALAADCggICAAAAA==.Amoretti:BAAALAAECgYIDgAAAA==.Amuril:BAAALAAECgEIAQAAAA==.',An='Anguirel:BAAALAAECgQIBAAAAA==.Anime:BAAALAADCgQIBQAAAA==.',Ap='Appelos:BAACLAAFFIEIAAIJAAMIpg7+BgDgAAAJAAMIpg7+BgDgAAAsAAQKgRgAAgkACAg2IGgJAN8CAAkACAg2IGgJAN8CAAEsAAQKCAgkAAoA9yYA.Apt:BAACLAAFFIENAAILAAUIvSG+AQDzAQALAAUIvSG+AQDzAQAsAAQKgSwAAgsACAjuJU8BAFwDAAsACAjuJU8BAFwDAAAA.',Ar='Archerr:BAAALAADCgcIBwAAAA==.Arclíght:BAAALAAECgMIAwAAAA==.Arcynne:BAAALAAECgMIBQAAAA==.Ariës:BAABLAAECoEcAAIDAAcIYwzOiABfAQADAAcIYwzOiABfAQAAAA==.Arney:BAAALAADCgcIDQAAAA==.Arryn:BAAALAAECgEIAQABLAAECgcIHgAIADYiAA==.Arthexia:BAAALAAECgQIAwAAAA==.Arwan:BAAALAADCgEIAQAAAA==.',As='Asheartz:BAABLAAECoEUAAIMAAYIgQ4KNwBtAQAMAAYIgQ4KNwBtAQAAAA==.Astriel:BAAALAADCgYICQAAAA==.',Au='Aukuna:BAAALAAECgQIBAAAAA==.',Az='Azgot:BAAALAADCgYIBgAAAA==.Azurá:BAAALAADCgcIDAAAAA==.',Ba='Babser:BAABLAAECoEdAAINAAcIBRXrKAC2AQANAAcIBRXrKAC2AQAAAA==.Backbreakers:BAAALAADCgQIBAAAAA==.Balboner:BAAALAAECgcIEgAAAA==.Balrok:BAAALAAECgUIBQAAAA==.',Be='Bea:BAAALAAECgYIDgAAAA==.Beefghast:BAAALAAECgYIDwAAAA==.Belcor:BAAALAAECgYIEQABLAAECggIIAAOAOkhAA==.Bettenøk:BAAALAAECgMIBQAAAA==.',Bi='Bigbaldpala:BAAALAADCgYIBgAAAA==.',Bl='Blackheart:BAAALAAECggIBQAAAA==.Blastus:BAAALAADCggIFAAAAA==.Blatz:BAAALAAECgYIBgAAAA==.Blewog:BAAALAADCgMIAwAAAA==.Blezzboy:BAAALAADCggILQAAAA==.Blindnezz:BAAALAADCggICAAAAA==.Blodpressure:BAAALAAECgYIDAAAAA==.Bloodkay:BAAALAADCgQIBAAAAA==.Bloodkayhz:BAAALAAECgYIDwAAAA==.',Bo='Bole:BAAALAAECgIIAgAAAA==.Boozecruise:BAAALAADCggIDwAAAA==.Borcu:BAAALAADCgcICQAAAA==.Ború:BAAALAADCgMIAwABLAAECgQIBAAPAAAAAA==.Boukhiar:BAAALAADCgMIAwABLAAFFAMIBQAHAEQSAA==.',Br='Brambleberry:BAABLAAECoEXAAIGAAYImBQPTABvAQAGAAYImBQPTABvAQAAAA==.Brawna:BAAALAAECgEIAQAAAA==.Brecert:BAABLAAECoEkAAIQAAgILBb8IgA5AgAQAAgILBb8IgA5AgAAAA==.Breewfest:BAAALAAECggIEgAAAA==.',Bt='Bturner:BAABLAAECoEbAAIRAAgIfxLGXwD+AQARAAgIfxLGXwD+AQAAAA==.',['Bá']='Bárackoshama:BAAALAAECgUIBgAAAA==.',['Bú']='Búffy:BAAALAAECgYIDwAAAA==.',Ca='Caetaam:BAAALAAECgIIBwAAAA==.Camaël:BAABLAAECoEaAAMJAAcI7hgMHQDlAQAJAAcIaxgMHQDlAQAIAAIIFxx1MwCcAAAAAA==.Cancerbat:BAAALAADCgEIAQABLAADCgcIDgAPAAAAAA==.Cap:BAAALAAFFAIIAgABLAAFFAYIEAALAEMeAA==.Captpewpew:BAAALAAECggICQAAAA==.Carlito:BAAALAADCggICAAAAA==.Cast:BAAALAAECgYIEwAAAA==.Cavnic:BAAALAADCgcIBwAAAA==.',Ch='Chadmommy:BAABLAAFFIEQAAISAAUIRSMNAAAyAgASAAUIRSMNAAAyAgABLAAFFAYIFgASAIAkAA==.Cheron:BAAALAAECgYIBwABLAAECggIFAATAJUdAA==.Chichiryutei:BAABLAAECoEVAAICAAcIuxiDEAAbAgACAAcIuxiDEAAbAgAAAA==.Chok:BAAALAADCgYIBgAAAA==.Chokladwar:BAAALAAECgIIAwAAAA==.Christopher:BAABLAAECoEfAAIDAAcIxxicUADjAQADAAcIxxicUADjAQAAAA==.Chucknóurish:BAABLAAECoEVAAIGAAcI1SE8EgCfAgAGAAcI1SE8EgCfAgAAAA==.Chúcknóurísh:BAAALAAECggIAQAAAA==.',Ci='Ciel:BAAALAAECgEIAQAAAA==.Cindurella:BAAALAADCgQIBAAAAA==.Cinnabar:BAAALAADCgcIBwAAAA==.Civimage:BAAALAAECgIIAgABLAAFFAQICwAUAJkaAA==.Civladine:BAACLAAFFIELAAIUAAQImRrMAgBIAQAUAAQImRrMAgBIAQAsAAQKgR8AAhQACAi4IlYGAPcCABQACAi4IlYGAPcCAAAA.',Cl='Clancyan:BAAALAADCggIDAAAAA==.Cleamage:BAAALAADCgcIBwAAAA==.Cliffy:BAAALAAECgUIDAAAAA==.',Co='Cortesh:BAAALAAECgEIAQAAAQ==.Covsas:BAACLAAFFIERAAIVAAUIOx1JCADgAQAVAAUIOx1JCADgAQAsAAQKgSwAAhUACAhrI+UIAEADABUACAhrI+UIAEADAAAA.',Cr='Cr:BAABLAAECoEjAAMDAAgIGiQ+CAA6AwADAAgIGiQ+CAA6AwAFAAEIZwy2rgAtAAAAAA==.Crazyrazor:BAAALAAECgYIEQAAAA==.',Da='Dak:BAAALAAECgQIBAAAAA==.Dalën:BAAALAADCgcIBwAAAA==.Damen:BAAALAADCgIIAgAAAA==.Darkblatz:BAABLAAECoEkAAIVAAgIzBWGOAAiAgAVAAgIzBWGOAAiAgAAAA==.Darkoth:BAAALAAECgYIEQAAAA==.Darkshades:BAAALAAECgUIBwAAAA==.Darlie:BAAALAADCgQIBAAAAA==.Darð:BAAALAADCggICwABLAAECggIHgAWAEcgAA==.Daró:BAABLAAECoEeAAIWAAgIRyDlKgCHAgAWAAgIRyDlKgCHAgAAAA==.',De='Deathciv:BAAALAAECggIDwABLAAFFAQICwAUAJkaAA==.Deathseeker:BAAALAADCggIFAAAAA==.Deathson:BAAALAAECgIIBQAAAA==.Deessveeone:BAAALAAECgYIDwAAAA==.Deliane:BAAALAAECgcIBwAAAA==.Demoniclego:BAABLAAECoEYAAIXAAcIBCUxBgDjAgAXAAcIBCUxBgDjAgAAAA==.Denhvide:BAAALAADCgYIEgAAAA==.Devilfish:BAAALAADCggICAAAAA==.Devyri:BAABLAAECoEXAAIJAAYIVhs4HwDRAQAJAAYIVhs4HwDRAQAAAA==.Dezision:BAAALAADCgUIBQABLAAECgUIBQAPAAAAAA==.',Di='Didhuelst:BAAALAADCggICAAAAA==.Didit:BAAALAADCgYIDQAAAA==.',Dj='Djoser:BAAALAAECgQIBAAAAA==.',Do='Dominatrixi:BAAALAAECggIBAAAAA==.Dovakhíin:BAAALAADCgcIDgAAAA==.',Dr='Drathyla:BAAALAAECgYICQAAAA==.Drazillá:BAABLAAECoEXAAIDAAcI/giwlgBDAQADAAcI/giwlgBDAQAAAA==.Dredika:BAAALAAECgYIDAAAAA==.Driller:BAAALAADCgYIBgABLAAECgMIAwAPAAAAAA==.Drizzle:BAAALAADCggIDwAAAA==.',Du='Dumbfoundead:BAAALAAECgMIAwAAAA==.',Dw='Dwarfey:BAAALAAECgcIBwAAAA==.',['Dê']='Dêz:BAAALAAECgUIBQAAAA==.',Ea='Earthres:BAAALAADCgQIBAAAAA==.',Eb='Ebony:BAAALAAECgYIEAAAAA==.',Ed='Eddcol:BAABLAAECoEXAAIHAAYIbxIlmgCBAQAHAAYIbxIlmgCBAQAAAA==.',Ee='Eektastic:BAAALAAECgUIBQAAAA==.',El='Elará:BAAALAADCgcIBwAAAA==.Eldron:BAABLAAECoEZAAIDAAcIRg6HgABwAQADAAcIRg6HgABwAQAAAA==.Eleni:BAABLAAECoEfAAIYAAcIdQ3wUQBlAQAYAAcIdQ3wUQBlAQAAAA==.Elfblod:BAAALAAECgEIAQABLAAECgYIFwAFALsGAA==.Elfwind:BAABLAAECoEXAAIFAAYIuwbXcgDdAAAFAAYIuwbXcgDdAAAAAA==.Eligosa:BAAALAAECgcIBwAAAA==.Elpicu:BAAALAADCggICAABLAAECgIIAgAPAAAAAA==.Elragorn:BAABLAAECoEbAAIHAAcIABPNeADAAQAHAAcIABPNeADAAQAAAA==.Elucidator:BAABLAAECoEdAAQHAAcImiDTMwB1AgAHAAcImiDTMwB1AgAUAAUILxYJLgBJAQAZAAEIxhNoYgA6AAAAAA==.Elusiveelf:BAAALAADCggIEgAAAA==.Elyscia:BAABLAAECoEXAAIKAAcI6RuHMAA6AgAKAAcI6RuHMAA6AgAAAA==.Elythae:BAAALAADCgIIAgAAAA==.',Em='Emberlock:BAAALAAECggIEQAAAA==.',Eo='Eonfix:BAAALAADCggICgAAAA==.',Er='Erith:BAABLAAECoEaAAIHAAgINhAYZADsAQAHAAgINhAYZADsAQAAAA==.Erlold:BAABLAAECoEYAAIHAAcIkw6TjQCYAQAHAAcIkw6TjQCYAQAAAA==.Erush:BAABLAAECoEZAAIZAAcIIBfjHQDtAQAZAAcIIBfjHQDtAQAAAA==.',Ev='Everfaith:BAAALAAECggIAQAAAA==.Evikin:BAAALAADCgcIBwAAAA==.',Fe='Feellinca:BAABLAAECoEdAAIWAAcIGx+JLQB6AgAWAAcIGx+JLQB6AgAAAA==.Fenja:BAAALAADCggIDgAAAA==.Fenriz:BAAALAAECgMIBQAAAA==.',Fi='Fiedler:BAAALAAECgYIDAABLAAFFAYIEAALAEMeAA==.',Fl='Flapalot:BAAALAADCgMIAwAAAA==.Fluffybelly:BAAALAADCggIDQAAAA==.',Fr='Friisex:BAAALAADCggIDgABLAAECggIIAAQAMYiAA==.Friist:BAABLAAECoEgAAIQAAgIxiIbFACzAgAQAAgIxiIbFACzAgAAAA==.Frrosty:BAAALAAECgcIBwABLAAFFAIIBwAaAEEUAA==.Früchtetraum:BAAALAAECgYIBgABLAAFFAYIEAALAEMeAA==.',Fu='Fuggi:BAAALAAECgMIAwAAAA==.',['Fú']='Fújín:BAAALAADCggICQABLAAECggIAgAPAAAAAA==.',Ge='Gensis:BAABLAAECoEaAAIQAAcI8QMYXwD/AAAQAAcI8QMYXwD/AAAAAA==.Gentleblade:BAAALAADCgEIAQAAAA==.Genzou:BAAALAAECgcIEgAAAA==.',Gh='Ghostluna:BAAALAAECgYIEQAAAA==.',Gi='Gilraena:BAAALAAECgMIBAAAAA==.',Gk='Gkio:BAAALAAECgEIAQAAAA==.',Gl='Gladiatorr:BAAALAADCgQIBAAAAA==.Glyttix:BAABLAAECoEXAAQBAAcIbw3aLQCNAQABAAcIbw3aLQCNAQAaAAUIZhcQHABRAQAbAAYI1wbIDQAYAQAAAA==.',Go='Goatjugs:BAAALAAECgcIEwAAAA==.Gobkorum:BAAALAAECgMIBAABLAAECggIIAAOAOkhAA==.Golkra:BAAALAAECggIDAAAAA==.Goo:BAAALAADCggICAAAAA==.',Gr='Greyscale:BAABLAAECoEXAAIBAAYIQBUdLQCSAQABAAYIQBUdLQCSAQAAAA==.',Gy='Gyroblade:BAAALAAECgMIBAAAAA==.Gyrolock:BAAALAADCgQIBAABLAAECgMIBAAPAAAAAA==.',Ha='Hannabi:BAAALAADCgcIBwAAAA==.Harald:BAABLAAECoEVAAMKAAYIEhT7XwCNAQAKAAYIhxL7XwCNAQAOAAUIfA6IGgAaAQAAAA==.Harambe:BAAALAAECgIIAgAAAA==.Harute:BAAALAADCggIDgAAAA==.Hazzat:BAAALAAECgEIAQAAAA==.',He='Healbelly:BAAALAAECgYICAAAAA==.Hellghast:BAAALAADCggIDgABLAAECgYIDwAPAAAAAA==.Herbo:BAAALAAECggICAAAAA==.',Hi='Hiromishi:BAAALAADCgQIBAAAAA==.',Ho='Holyaspect:BAAALAADCggICAAAAA==.Holyrash:BAAALAADCggICAAAAA==.Hoofs:BAAALAADCgMIAwAAAA==.Hornihoofed:BAAALAAECgYIEAAAAA==.',Hu='Huana:BAAALAAECgYIEwAAAA==.Hugono:BAAALAADCgcIBwAAAA==.Huntisophi:BAAALAADCggICAAAAA==.',Hy='Hygge:BAAALAAFFAIIAgABLAAFFAIIBwAGAHUiAA==.',Ib='Ibee:BAABLAAECoEZAAIKAAgIYRTGOgANAgAKAAgIYRTGOgANAgAAAA==.',Ic='Icebloke:BAAALAADCgMIAwAAAA==.',Ig='Iggydh:BAAALAAECgYICwAAAA==.Igris:BAAALAADCgcIBwAAAA==.',Il='Illium:BAAALAAECgUICQAAAA==.Ilthommiél:BAAALAAECgYICwAAAA==.',In='Insapirest:BAACLAAFFIEFAAIQAAMIRAbsDwDCAAAQAAMIRAbsDwDCAAAsAAQKgSQAAxAACAj8HfsbAG8CABAACAj8HfsbAG8CABgACAjFFngmAC4CAAEsAAUUBQgIABUA7gkA.',Io='Ioorek:BAAALAADCgcIBwAAAA==.',Je='Jeff:BAAALAAECggICQAAAA==.',Jo='Jormunthun:BAAALAADCgQIBAABLAAECggIJwAcAOwgAA==.Jotuhn:BAABLAAECoEnAAIcAAgI7CDWBQDsAgAcAAgI7CDWBQDsAgAAAA==.',Ka='Kalagai:BAABLAAECoEaAAMdAAcIzwvKUwCGAQAdAAcIzwvKUwCGAQATAAIIqBML3wB9AAAAAA==.Kalawayz:BAABLAAECoEZAAIXAAcIrQMhNwDRAAAXAAcIrQMhNwDRAAAAAA==.Kalileus:BAACLAAFFIESAAINAAUICxzgAgDJAQANAAUICxzgAgDJAQAsAAQKgSkAAg0ACAgQJFUGABkDAA0ACAgQJFUGABkDAAAA.Kalindaa:BAABLAAECoEnAAIDAAgISRAyZACwAQADAAgISRAyZACwAQAAAA==.Kanyeewest:BAAALAADCgMIAgABLAAECgMIAwAPAAAAAA==.Karatekidd:BAAALAADCgcIBwAAAA==.Karen:BAABLAAECoEfAAIdAAgIHSXnBABeAwAdAAgIHSXnBABeAwABLAAFFAUICgAdABkfAA==.Katoma:BAAALAAECgYICwABLAAFFAIIBAAPAAAAAQ==.Katroyana:BAABLAAECoEaAAIeAAcIcB7CDQBdAgAeAAcIcB7CDQBdAgAAAA==.',Ke='Kejser:BAABLAAECoEXAAIDAAYIoBczbQCaAQADAAYIoBczbQCaAQABLAAECgcIGwAHAAATAA==.Keltharion:BAAALAAECgYIDgAAAA==.Keshina:BAAALAAECggICAAAAA==.Keyrra:BAAALAAECgMIBAAAAA==.',Kh='Khalisee:BAAALAADCgUICQAAAA==.',Ki='Kiie:BAAALAADCggIFAAAAA==.Kirá:BAAALAADCggIHwAAAA==.Kitch:BAACLAAFFIEFAAIfAAUISh1OAADxAQAfAAUISh1OAADxAQAsAAQKgRcAAh8ACAifJDUBAFMDAB8ACAifJDUBAFMDAAAA.Kitiaraa:BAAALAADCgcIBwAAAA==.',Kp='Kp:BAAALAAECgEIAQAAAA==.',Kr='Kray:BAAALAAECgYIDAABLAAECgYIFgAZAEgdAA==.Krayvoker:BAAALAAECgYIDQABLAAECgYIFgAZAEgdAA==.Krayzie:BAAALAAECgIIAwABLAAECgYIFgAZAEgdAA==.Krayzier:BAABLAAECoEWAAIZAAYISB1eHgDpAQAZAAYISB1eHgDpAQAAAA==.Krayzz:BAAALAADCgMIAwABLAAECgYIFgAZAEgdAA==.Krus:BAAALAADCggIGAAAAA==.',Ku='Kulens:BAAALAADCgMIAwAAAA==.',La='Larsia:BAAALAADCgYIBgAAAA==.Laukr:BAAALAAECggIEQAAAA==.Lazaruss:BAABLAAECoEgAAMUAAcIqwjKPwDRAAAHAAcIEAcf0gAWAQAUAAcIeQTKPwDRAAAAAA==.',Le='Leightôx:BAAALAAECgQIBgAAAA==.Lekaface:BAAALAAECggICAAAAA==.Leonie:BAAALAAECgYIEwAAAA==.Leoric:BAABLAAECoEYAAIgAAgIpx/BBgDVAgAgAAgIpx/BBgDVAgAAAA==.Leraa:BAAALAAECgIIAgAAAA==.Lev:BAAALAAECgYIEgAAAA==.Levri:BAAALAAECgYIBgAAAA==.',Lh='Lhyrin:BAAALAAECgIIBgAAAA==.',Li='Lisbet:BAAALAAECgMIBAABLAAECgYIEgAPAAAAAA==.',Lo='Lockybalbóa:BAAALAAECgQIBAAAAA==.Locutuz:BAAALAAECgIIAgAAAA==.',Lu='Lucille:BAABLAAFFIEFAAMhAAUImhNVBgAmAQAhAAMI7hhVBgAmAQAiAAIInAtWAwCfAAAAAA==.Lulumcstab:BAAALAADCggICwAAAA==.Luminosus:BAAALAAECgIIAgAAAA==.Lutherdevile:BAAALAAECgIIAgAAAA==.Luuna:BAAALAAECgYIDAAAAA==.',Ly='Lylli:BAABLAAECoEVAAIYAAYIAwaQcQD5AAAYAAYIAwaQcQD5AAAAAA==.Lyralith:BAAALAADCgYICwAAAA==.',['Lò']='Lòky:BAAALAADCggICwAAAA==.',['Ló']='Lóckybalboa:BAAALAADCggIBAAAAA==.',['Lø']='Løffy:BAAALAADCgIIAgAAAA==.Løvehjerte:BAAALAAECgYIDwABLAAECgcIGwAHAAATAA==.',['Lú']='Lúná:BAAALAADCgcICwAAAA==.',Ma='Maddman:BAAALAADCggICAAAAA==.Maranque:BAABLAAECoEnAAMjAAgIIxxpKwB+AgAjAAgIIxxpKwB+AgAkAAMIQBSLYQCZAAAAAA==.Marqeez:BAAALAAECgIIBgAAAA==.Marík:BAAALAAECgYIEgAAAA==.Maseraati:BAAALAAECgYIDgABLAAECggIJwADAEwdAA==.Mazekine:BAAALAAECgYICQAAAA==.',Me='Meowdyen:BAABLAAECoEZAAICAAgI1RwKBwDNAgACAAgI1RwKBwDNAgAAAA==.Meowmonster:BAAALAAECgYIEAAAAA==.Metternixx:BAAALAAECgIIAgAAAA==.',Mi='Mightymind:BAABLAAECoEaAAIkAAcIlwxXMwB+AQAkAAcIlwxXMwB+AQAAAA==.Millgid:BAABLAAECoEfAAIUAAcIBBjdHADPAQAUAAcIBBjdHADPAQAAAA==.Minzan:BAAALAAECgUICwAAAA==.Missdagger:BAACLAAFFIEGAAILAAIIlB8jCQCwAAALAAIIlB8jCQCwAAAsAAQKgSwAAgsACAiCI8wCACkDAAsACAiCI8wCACkDAAAA.Mivie:BAAALAAECgEIAQABLAAFFAUIEAAGAFAYAA==.Miviel:BAAALAAECgYIBgABLAAFFAUIEAAGAFAYAA==.Mivielle:BAABLAAFFIEGAAMTAAUIzhQsFwC8AAATAAMIbQ4sFwC8AAAdAAIIuAEAAAAAAAABLAAFFAUIEAAGAFAYAA==.Mivstrangler:BAACLAAFFIEIAAIaAAMI9gnICADYAAAaAAMI9gnICADYAAAsAAQKgSEAAxoACAj1GbwJAGgCABoACAj1GbwJAGgCAAEABQinGxgsAJgBAAEsAAUUBQgQAAYAUBgA.',Mo='Mondrian:BAAALAAECgQIBQAAAA==.Monkry:BAAALAADCgIIAgABLAAECggIHwAfAOQcAA==.Moochacho:BAAALAADCgMIAwAAAA==.Moontouched:BAAALAAECgcIEwAAAA==.Moonwitch:BAAALAAECgYIEAAAAA==.Moosekorum:BAAALAADCgYIBgABLAAECggIIAAOAOkhAA==.Morgonljus:BAABLAAECoEwAAIDAAgI5Q6eYgC0AQADAAgI5Q6eYgC0AQAAAA==.Morio:BAAALAADCggIDwAAAA==.Morpheen:BAACLAAFFIELAAIjAAUI9R03CADYAQAjAAUI9R03CADYAQAsAAQKgSsAAyMACAgbJvIBAHwDACMACAgbJvIBAHwDACUAAQgnGv8aAEAAAAAA.Morphiaz:BAAALAAECgEIAQAAAA==.Morza:BAAALAAECgQIBQAAAA==.',Mu='Mugar:BAAALAADCggICAAAAA==.Munk:BAACLAAFFIEUAAIIAAYIcx5wAQAvAgAIAAYIcx5wAQAvAgAsAAQKgRUAAwgACAj6I2kDADIDAAgACAj6I2kDADIDAAkAAgg0G05GAJ4AAAAA.Murter:BAAALAAECgYICgAAAA==.Mushaweth:BAABLAAECoEYAAIkAAgIWwjwQABAAQAkAAgIWwjwQABAAQAAAA==.',My='Mysticfinger:BAAALAAECgcIDQAAAA==.Myztery:BAAALAAECgYIDgAAAA==.',['Mø']='Møth:BAAALAADCggICAAAAA==.',Na='Nalen:BAAALAAECgUICQAAAA==.Namôr:BAAALAADCgUIBQABLAAECgcIGwAHAAATAA==.Nanya:BAAALAADCgcIBwAAAA==.Narayana:BAAALAADCgQIBAAAAA==.Naschahoof:BAABLAAECoEVAAMmAAYI8RXeOQCYAQAmAAYI4xXeOQCYAQACAAEIuANpQAAqAAAAAA==.Nathanial:BAAALAAECgUIDAAAAA==.',Ne='Necrathen:BAAALAAECgYIEQAAAA==.Neithnepthys:BAAALAAECgcIEgAAAA==.Nemethys:BAACLAAFFIEQAAITAAUIORj4BACbAQATAAUIORj4BACbAQAsAAQKgRgAAhMACAggHc8cAH0CABMACAggHc8cAH0CAAAA.Nephelle:BAABLAAECoEXAAIVAAYI1g10dQBYAQAVAAYI1g10dQBYAQAAAA==.Neurotiica:BAAALAAECgYIEAAAAA==.Neztemic:BAABLAAECoEfAAITAAgI2h2PEwC1AgATAAgI2h2PEwC1AgAAAA==.',Ni='Nixxar:BAAALAADCggICAAAAA==.',No='Northman:BAAALAAECgMIBAAAAA==.',Nu='Nuttynut:BAABLAAECoEfAAITAAcIDRnbPgDyAQATAAcIDRnbPgDyAQAAAA==.',['Nø']='Nøkk:BAABLAAECoEcAAIdAAcIvRuVKwA1AgAdAAcIvRuVKwA1AgABLAAFFAMICQAdAPYgAA==.',Ok='Okatsuki:BAAALAADCgcIBwAAAA==.',Ol='Olliemage:BAAALAAECgUIDQABLAAFFAUIEQAmAEsYAA==.Ollievol:BAACLAAFFIERAAImAAUISxi2AwDCAQAmAAUISxi2AwDCAQAsAAQKgSIAAiYACAhBI+sKAAADACYACAhBI+sKAAADAAAA.',On='Onodera:BAAALAADCggICAAAAA==.',Op='Opprørgutt:BAAALAAECgYICQAAAA==.',Or='Oristar:BAAALAAECggIAQAAAA==.Oritka:BAAALAAECgMIBwAAAA==.Orpser:BAABLAAECoEjAAInAAgIvBsFBQB7AgAnAAgIvBsFBQB7AgAAAA==.',Ov='Ovenmitt:BAACLAAFFIERAAMDAAUIBhhIBgChAQADAAUIBhhIBgChAQAFAAMIzQXJFAChAAAsAAQKgSIAAwMACAgVI0kYAM0CAAMACAgVI0kYAM0CAAUAAQgbGMygAEcAAAAA.',Pa='Paladinima:BAABLAAECoEhAAIHAAgIMheHSQAwAgAHAAgIMheHSQAwAgAAAA==.Palapipinz:BAAALAAECgEIAQAAAA==.Pathpoppy:BAAALAADCgUIAgAAAA==.',Pe='Perfo:BAABLAAECoEeAAIZAAgI+RrRDgB5AgAZAAgI+RrRDgB5AgAAAA==.',Ph='Phyrra:BAAALAAECgEIAQAAAA==.',Pi='Pinkres:BAAALAAECgQIBQAAAA==.Pinobianco:BAAALAAECgEIAQAAAA==.',Po='Poepzak:BAAALAADCgYIBgAAAA==.Poityfish:BAAALAAECgYIEQAAAA==.Polkra:BAAALAADCgUIBwAAAA==.Pookiebéar:BAAALAAECgUIBQAAAA==.Posix:BAAALAAECgYICAAAAA==.Powz:BAABLAAECoEVAAMJAAcI5h43EQBrAgAJAAcI5h43EQBrAgAIAAEIGA36PwAtAAAAAA==.Pozzik:BAABLAAECoEdAAIoAAgIABoLCgAsAgAoAAgIABoLCgAsAgAAAA==.',Pr='Praeis:BAAALAAECgUIBQABLAAECggIFAATAJUdAA==.Pronyma:BAAALAADCgcIBwAAAA==.Protégé:BAAALAADCgIIAgAAAA==.',Py='Pyris:BAABLAAECoEdAAMjAAgInR4mLgBwAgAjAAgIfh4mLgBwAgAkAAIISR/WaQByAAAAAA==.',Qn='Qnt:BAAALAAFFAIIAgAAAA==.',Qt='Qtn:BAAALAAECggICAAAAA==.',Qu='Quacksalot:BAABLAAECoEcAAIgAAcIFSJ0CQCVAgAgAAcIFSJ0CQCVAgAAAA==.',Ra='Ralith:BAAALAADCgcIBwAAAA==.Randô:BAAALAAECggICAAAAA==.Raphaeil:BAAALAADCgYIBgAAAA==.Rapidutza:BAAALAAECggIEwAAAA==.',Re='Resina:BAAALAADCgcIDgABLAAECgQIBQAPAAAAAA==.',Rh='Rhensie:BAABLAAECoEaAAIJAAcIXiECDwCIAgAJAAcIXiECDwCIAgAAAA==.',Ri='Rini:BAACLAAFFIEMAAIXAAUICR+VAADeAQAXAAUICR+VAADeAQAsAAQKgRgAAhcACAjBJN4DAB8DABcACAjBJN4DAB8DAAAA.Ripclaw:BAAALAADCggICAAAAA==.',Ro='Romanda:BAAALAAECgIIAgAAAA==.Rorydruid:BAAALAAECgUIBQAAAA==.',Ru='Ruse:BAAALAADCgQIBAAAAA==.',Ry='Ryerow:BAACLAAFFIEOAAIHAAUIth6fAwDhAQAHAAUIth6fAwDhAQAsAAQKgSgAAwcACAjgJFISABcDAAcACAjgJFISABcDABkACAjPDwwkAMEBAAAA.Ryro:BAAALAAECgQIBAABLAAFFAUIDgAHALYeAA==.Ryspank:BAABLAAECoEWAAIXAAYINB6rFQDmAQAXAAYINB6rFQDmAQABLAAECggIHwAfAOQcAA==.',['Rý']='Rý:BAABLAAECoEfAAUfAAgI5BzhDQC2AQAfAAgIGxfhDQC2AQACAAUIihrcGwCQAQAmAAEIXxdshABGAAAGAAEIswZCuQAnAAAAAA==.',Sa='Saltysbear:BAAALAAECgEIAQAAAA==.Sanguinius:BAAALAADCgUIBAAAAA==.',Sc='Scarly:BAAALAAECgYIDgAAAA==.Scrubba:BAAALAADCgcIBgAAAA==.',Se='Selekker:BAAALAAECgUIBQAAAA==.Selekkers:BAAALAAECggIBwAAAA==.Sevaar:BAAALAAECgEIAQAAAA==.',Sh='Shaensyl:BAACLAAFFIEHAAIWAAMIEhdrEAD9AAAWAAMIEhdrEAD9AAAsAAQKgR4AAhYACAgPIIUhALYCABYACAgPIIUhALYCAAAA.Shaula:BAAALAAECgEIAQAAAA==.Shinybob:BAABLAAECoEfAAIdAAcIUhQ0PADhAQAdAAcIUhQ0PADhAQAAAA==.Shion:BAAALAAECgYIEQAAAA==.Shínoblí:BAAALAADCggICAAAAA==.Shínóblí:BAAALAAECgYIBgAAAA==.',Si='Sinikarhu:BAAALAADCgIIAgAAAA==.',Sl='Slackalice:BAAALAADCggICAAAAA==.',Sm='Smithydh:BAABLAAECoElAAIWAAgI7xnZMwBgAgAWAAgI7xnZMwBgAgAAAA==.Smyd:BAAALAADCgYIBgAAAA==.',Sn='Snaffle:BAACLAAFFIEKAAIdAAQI7Rl+CQBcAQAdAAQI7Rl+CQBcAQAsAAQKgSMAAh0ACAiOJNIJAC8DAB0ACAiOJNIJAC8DAAAA.Snehvit:BAABLAAECoEXAAMKAAYIiRDPewA8AQAKAAUIeBHPewA8AQANAAUIgw5gTQDwAAAAAA==.Snif:BAAALAADCgYIBgAAAA==.',So='Solledemon:BAAALAADCgYICwAAAA==.Solstice:BAAALAAECgcIDgAAAA==.Someholybreh:BAABLAAECoEmAAIYAAgIxB/RDQDhAgAYAAgIxB/RDQDhAgAAAA==.Somemagebreh:BAAALAAECgIIAgAAAA==.Soorman:BAABLAAECoEWAAIJAAcIHgjyMQBCAQAJAAcIHgjyMQBCAQAAAA==.',Sp='Speedtank:BAABLAAECoEXAAIUAAYI6BE7LwBBAQAUAAYI6BE7LwBBAQAAAA==.Spitebobels:BAAALAADCggIHwAAAA==.Splinter:BAAALAAFFAIIBAAAAQ==.',St='Starstrider:BAAALAADCgQIBAAAAA==.Stinkum:BAACLAAFFIESAAIgAAUIQxInAwCDAQAgAAUIQxInAwCDAQAsAAQKgRsAAiAACAjZGxwRAAACACAACAjZGxwRAAACAAAA.Sturmente:BAACLAAFFIEPAAMbAAUI2hdqAQC0AQAbAAUIFxdqAQC0AQABAAMIag0IDQDOAAAsAAQKgRcAAgEACAjXGu4ZADICAAEACAjXGu4ZADICAAAA.',Su='Sulyatha:BAAALAAECgQIBAAAAA==.Sunstórm:BAABLAAECoEeAAIDAAcIhBUTYgC1AQADAAcIhBUTYgC1AQAAAA==.Suspeak:BAAALAAECgcIEgAAAA==.',Sy='Sycolich:BAAALAAECgYIDwAAAA==.Sylvan:BAAALAADCgYIBgABLAAECgcIHgAIADYiAA==.Synical:BAAALAAECgYIEQAAAA==.',Sz='Szeras:BAACLAAFFIEOAAIJAAUI7w8aAwCaAQAJAAUI7w8aAwCaAQAsAAQKgRcAAgkACAjxHQ4PAIcCAAkACAjxHQ4PAIcCAAAA.',Te='Tedwardian:BAAALAAECgUIBQABLAAECggIFAATAJUdAA==.Tela:BAACLAAFFIEGAAIgAAQIWB8xAwCBAQAgAAQIWB8xAwCBAQAsAAQKgRUAAiAACAgxHxcHAM4CACAACAgxHxcHAM4CAAEsAAUUBQgMABcACR8A.Telithil:BAAALAADCgEIAQAAAA==.Templaxi:BAAALAAECgMIBQAAAA==.',Th='Thejoker:BAAALAAECgYICQAAAA==.Therix:BAAALAAECgcICgAAAA==.Thommee:BAAALAAECgcIEQAAAA==.Thora:BAABLAAECoEXAAINAAYIPxRZNgBjAQANAAYIPxRZNgBjAQAAAA==.Thoreleo:BAABLAAECoEgAAIhAAgI6BW0FwBGAgAhAAgI6BW0FwBGAgAAAA==.Thorgrim:BAAALAADCgcIDQAAAA==.Thyz:BAAALAADCggICQAAAA==.',Ti='Tinkerbel:BAABLAAECoEnAAMDAAgITB3xIgCNAgADAAgITB3xIgCNAgAFAAII1g19mQBZAAAAAA==.',To='Tomato:BAAALAAECgMIAwAAAA==.',Tr='Transformerx:BAABLAAECoEUAAImAAcIqyAVFwB6AgAmAAcIqyAVFwB6AgAAAA==.Tripin:BAABLAAECoEZAAIDAAcIcxw/OAAxAgADAAcIcxw/OAAxAgAAAA==.Tropix:BAAALAADCggICAAAAA==.',Ty='Tylee:BAACLAAFFIEQAAIGAAUIUBjAAwCpAQAGAAUIUBjAAwCpAQAsAAQKgRcAAgYACAjiIQ8IAAIDAAYACAjiIQ8IAAIDAAAA.Tyranious:BAAALAAECgcIDwAAAA==.Tyrell:BAAALAADCgUIBQAAAA==.Tyriell:BAAALAADCgEIAQAAAA==.',['Tá']='Tállia:BAAALAADCgcICQAAAA==.',['Tô']='Tômmy:BAAALAAECgcIBwAAAA==.',Um='Umauma:BAAALAADCgYIBgAAAA==.',Un='Unkelbob:BAAALAADCgMIAwAAAA==.',Ut='Utur:BAAALAADCgMIAwAAAA==.',Va='Valkar:BAAALAADCggICAAAAA==.Valkora:BAAALAAECgYICQAAAA==.Vanya:BAAALAAECgYICAAAAA==.',Ve='Vedalken:BAAALAADCgcIBwAAAA==.Vexareh:BAAALAAECgMIBQAAAA==.Vexorc:BAAALAADCgcIBwAAAA==.',Vi='Violamania:BAAALAAECgYIEgAAAA==.Viridi:BAAALAAECgYIEwAAAA==.',Vo='Voidmark:BAAALAAECgcICwAAAA==.',Vr='Vreemdevogel:BAAALAAECgUIBQAAAA==.Vriseida:BAAALAADCggIIgAAAA==.',['Vá']='Várkáld:BAAALAADCgcIBwAAAA==.',Wa='Walpole:BAAALAAECggIBgAAAA==.Waytooslow:BAAALAAECgYIEAAAAA==.',Wh='Whitestorm:BAAALAADCgcIBwAAAA==.',Wi='Willowblade:BAAALAAECgYICwAAAA==.Winterente:BAAALAAECgcIBwABLAAFFAUIDwAbANoXAA==.Wipers:BAAALAAECgUICgAAAA==.',Xe='Xenions:BAABLAAECoEiAAMlAAgI+hCRBQAIAgAlAAgI+hCRBQAIAgAjAAEI8gaP3wApAAAAAA==.Xeoxar:BAAALAADCggICwAAAA==.Xeryhn:BAABLAAECoEXAAIDAAcI1Q55fAB4AQADAAcI1Q55fAB4AQAAAA==.',Xi='Xialan:BAAALAAECgMIBAAAAA==.Xias:BAABLAAECoEXAAIQAAgIuwiuSwBdAQAQAAgIuwiuSwBdAQAAAA==.',Ya='Yakstrangler:BAACLAAFFIEOAAIKAAUIvBBRBwCwAQAKAAUIvBBRBwCwAQAsAAQKgS0AAgoACAgFIYcUAOkCAAoACAgFIYcUAOkCAAAA.',Ye='Yesmir:BAAALAAECgEIAgAAAA==.',Yo='Yokilee:BAAALAADCggIEAAAAA==.Yonghwa:BAAALAADCggIJAABLAAECgYIFwABAEAVAA==.',Yu='Yudokuna:BAAALAAECgYIDgAAAA==.',Za='Zabaws:BAAALAAECggICAAAAA==.Zanean:BAAALAAECgYIDwAAAA==.Zapemall:BAAALAAECgcICwAAAA==.Zatiah:BAAALAADCgYIBgAAAA==.',Ze='Zeanort:BAAALAAECggIBwAAAA==.Zelmaran:BAABLAAECoEfAAMmAAgIMxZLLQDZAQAmAAcI+RZLLQDZAQAGAAcILhYqXgAxAQAAAA==.Zewz:BAAALAAECgMICAAAAA==.',Zi='Zinpala:BAAALAAECgYIBgABLAAECgcIDQAPAAAAAA==.',Zn='Znek:BAAALAAECgYIEAAAAA==.',Zo='Zorhen:BAABLAAECoEWAAIgAAYIpBxNEwDbAQAgAAYIpBxNEwDbAQAAAA==.',Zu='Zussa:BAAALAADCgQIBAAAAA==.Zuzza:BAAALAADCgIIAgAAAA==.',['Ár']='Árlo:BAAALAADCggIDQAAAA==.Árthur:BAAALAAECggIBgAAAA==.',['Ðx']='Ðxc:BAABLAAECoEcAAIfAAgItQ3jFAA9AQAfAAgItQ3jFAA9AQAAAA==.',['Øp']='Øpa:BAAALAADCgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end