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
 local lookup = {'Unknown-Unknown','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Druid-Restoration','Monk-Windwalker','Rogue-Subtlety','Priest-Shadow','Priest-Discipline','Paladin-Protection','Warlock-Destruction','Priest-Holy','DeathKnight-Unholy','Warrior-Protection','Shaman-Elemental','Mage-Arcane','Mage-Frost','Evoker-Preservation','Mage-Fire','Monk-Brewmaster','Shaman-Restoration','Druid-Balance','Warlock-Affliction','Paladin-Holy','DemonHunter-Vengeance','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Blood','Evoker-Devastation','Rogue-Assassination','Warrior-Fury',}; local provider = {region='EU',realm='Nordrassil',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abraxos:BAAALAADCgIIAgAAAA==.',Ac='Achiliesheal:BAAALAAECgEIAQAAAA==.',Ad='Adhrazan:BAAALAAECgUICwAAAA==.Adorien:BAAALAAECgcIDQAAAA==.Adyen:BAAALAAECgYIBgABLAAECggIDgABAAAAAA==.Adyenchi:BAAALAAECgMIAwABLAAECggIDgABAAAAAA==.Adyendh:BAAALAAECggIDgAAAA==.',Ae='Aeleisia:BAABLAAECoEUAAQCAAcI8ByzBQDpAQACAAYILh2zBQDpAQADAAUIvBq7KgCVAQAEAAQIPBv3WwAYAQAAAA==.',Af='Afterglow:BAABLAAECoEXAAIFAAcIiwwSNwBKAQAFAAcIiwwSNwBKAQAAAA==.',Ag='Agnar:BAAALAAECgYICAAAAA==.',Al='Alcides:BAAALAADCggIEgAAAA==.Alfréd:BAAALAAECgYIDgAAAA==.Alicé:BAAALAAECgcIDQAAAA==.Althuin:BAAALAAECgYIDgAAAA==.',Am='Amoretti:BAAALAAECgMIAgAAAA==.Amuril:BAAALAADCgIIAgAAAA==.',An='Ancore:BAAALAAECggICgAAAA==.Anguirel:BAAALAAECgEIAQAAAA==.Anime:BAAALAADCgQIBQAAAA==.',Ap='Appelos:BAABLAAFFIEFAAIGAAIIMBFTBgCdAAAGAAIIMBFTBgCdAAAAAA==.Apt:BAABLAAECoEfAAIHAAgIgyXVAABRAwAHAAgIgyXVAABRAwAAAA==.',Ar='Archerr:BAAALAADCgcIBwAAAA==.Arcynne:BAAALAADCgQIBAAAAA==.Ariës:BAAALAAECgYIDgAAAA==.',As='Asheartz:BAAALAAECgUIDQAAAA==.Astriel:BAAALAADCgMIAwAAAA==.',Az='Azgot:BAAALAADCgYIBgAAAA==.',Ba='Babser:BAAALAAECgYICwAAAA==.Balboner:BAAALAAECgQICAAAAA==.',Be='Bea:BAAALAAECgMIBQAAAA==.Beefghast:BAAALAAECgMIBgAAAA==.Belcor:BAAALAAECgMICAAAAA==.Bettenøk:BAAALAAECgEIAQAAAA==.',Bl='Blackheart:BAAALAAECggIBQAAAA==.Blastus:BAAALAADCggIFAAAAA==.Blatz:BAAALAAECgUIBQAAAA==.Blewog:BAAALAADCgMIAwAAAA==.Blezzboy:BAAALAADCggIHgAAAA==.Blindnezz:BAAALAADCggICAAAAA==.Blodpressure:BAAALAAECgEIAQAAAA==.Bloodkay:BAAALAADCgQIBAAAAA==.Bloodkayhz:BAAALAAECgYIDwAAAA==.',Bo='Boozecruise:BAAALAADCggIDwAAAA==.Borcu:BAAALAADCgcICAAAAA==.Ború:BAAALAADCgMIAwAAAA==.Boukhiar:BAAALAADCgMIAwAAAA==.',Br='Brambleberry:BAAALAAECgMICAAAAA==.Brawna:BAAALAADCgcIFAAAAA==.Brecert:BAABLAAECoEVAAIIAAgI5BPiHAAQAgAIAAgI5BPiHAAQAgAAAA==.Breewfest:BAAALAAECggIEQAAAA==.',Bt='Bturner:BAAALAAECgYIDwAAAA==.',['Bá']='Bárackoshama:BAAALAADCgUICQAAAA==.',['Bú']='Búffy:BAAALAAECgQICQAAAA==.',Ca='Caetaam:BAAALAAECgIIBQAAAA==.Camaël:BAAALAAECgYIEQAAAA==.Cancerbat:BAAALAADCgEIAQABLAADCgcIDgABAAAAAA==.Cap:BAAALAAECgYICAABLAAECgYIDAABAAAAAA==.Cast:BAAALAAECgYIDQAAAA==.Cavnic:BAAALAADCgcIBwAAAA==.',Ch='Chadmommy:BAABLAAFFIEFAAIJAAMItCEQAABHAQAJAAMItCEQAABHAQAAAA==.Cheron:BAAALAAECgMIAwABLAAECgcIDgABAAAAAA==.Chichiryutei:BAAALAAECgYICAAAAA==.Chok:BAAALAADCgYIBgAAAA==.Christopher:BAAALAAECgYIDgAAAA==.Chucknóurish:BAAALAAECgcICQAAAA==.Chúcknóurísh:BAAALAAECggIAQAAAA==.',Ci='Ciel:BAAALAADCgEIAQAAAA==.Cinnabar:BAAALAADCgcIBwAAAA==.Civladine:BAABLAAECoEeAAIKAAgIuCLRAgAfAwAKAAgIuCLRAgAfAwAAAA==.',Cl='Clancyan:BAAALAAECgEIAQAAAA==.Cleamage:BAAALAADCgcIBwAAAA==.Cliffy:BAAALAAECgUICgAAAA==.',Co='Cortesh:BAAALAADCggIFgAAAQ==.Covsas:BAACLAAFFIEFAAILAAMIjg9dCQD5AAALAAMIjg9dCQD5AAAsAAQKgR4AAgsACAimHFkTAJsCAAsACAimHFkTAJsCAAAA.',Cr='Cr:BAAALAAECgYIDQAAAA==.Crazyrazor:BAAALAAECgMIBQAAAA==.',Da='Dak:BAAALAADCggIDQAAAA==.Dalën:BAAALAADCgcIBwAAAA==.Darkblatz:BAAALAAECggIEQAAAA==.Darkoth:BAAALAAECgMIBQAAAA==.Darkshades:BAAALAAECgQIBgAAAA==.Darlie:BAAALAADCgQIBAAAAA==.Darð:BAAALAADCggICwABLAAECgYIDwABAAAAAA==.Daró:BAAALAAECgYIDwAAAA==.',De='Deathson:BAAALAAECgIIAwAAAA==.Deessveeone:BAAALAAECgIIAwAAAA==.Deliane:BAAALAAECgcIBwAAAA==.Demoniclego:BAAALAAECgYICwAAAA==.Denhvide:BAAALAADCgYIDgAAAA==.Devyri:BAAALAAECgQICgAAAA==.',Di='Didhuelst:BAAALAADCggICAAAAA==.Didit:BAAALAADCgYIBwAAAA==.',Dj='Djoser:BAAALAAECgEIAQAAAA==.',Do='Dominatrixi:BAAALAAECggIBAAAAA==.Dovakhíin:BAAALAADCgcIDgAAAA==.',Dr='Drathyla:BAAALAAECgEIAQAAAA==.Drazillá:BAAALAAECgYICwAAAA==.Dredika:BAAALAAECgEIAQAAAA==.Driller:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Drizzle:BAAALAADCgcIBwAAAA==.',Du='Dumbfoundead:BAAALAAECgMIAwAAAA==.',Dw='Dwarfey:BAAALAADCggICAAAAA==.',Ea='Earthres:BAAALAADCgQIBAAAAA==.',Eb='Ebony:BAAALAAECgMIBQAAAA==.',Ed='Eddcol:BAAALAAECgMICAAAAA==.',Ee='Eektastic:BAAALAADCggIFAAAAA==.',El='Eldron:BAAALAAECgUIDAAAAA==.Eleni:BAAALAAECgYIDgAAAA==.Elfblod:BAAALAADCgcIFAABLAAECgMICAABAAAAAA==.Elfwind:BAAALAAECgMICAAAAA==.Elragorn:BAAALAAECgYICAABLAAECgYIEQABAAAAAA==.Elucidator:BAAALAAECgYICwAAAA==.Elyscia:BAAALAAECgYICwAAAA==.Elythae:BAAALAADCgIIAgAAAA==.',Em='Emberlock:BAAALAAECgYIBwAAAA==.',Eo='Eonfix:BAAALAADCggICgAAAA==.',Er='Erawyn:BAAALAADCggIDwAAAA==.Erith:BAAALAAECgUIBwAAAA==.Erlold:BAAALAAECgYIDgAAAA==.Erush:BAAALAAECgUIDAAAAA==.',Fe='Feellinca:BAAALAAECgYICwAAAA==.Fenja:BAAALAADCgYIBgAAAA==.Fenriz:BAAALAADCgcIFAAAAA==.',Fi='Fiedler:BAAALAAECgYIDAAAAA==.',Fl='Flapalot:BAAALAADCgMIAwAAAA==.Fluffybelly:BAAALAADCggICQAAAA==.',Fr='Friist:BAAALAAECgYICwAAAA==.Frrosty:BAAALAAECgcIBwAAAA==.',Fu='Fuggi:BAAALAADCggIDwAAAA==.',Ge='Gensis:BAAALAAECgUIDQAAAA==.Gentleblade:BAAALAADCgEIAQAAAA==.Genzou:BAAALAAECgYICwAAAA==.',Gh='Ghostluna:BAAALAAECgMIBQAAAA==.',Gi='Gilraena:BAAALAADCggIFgAAAA==.',Gk='Gkio:BAAALAADCggIFgAAAA==.',Gl='Glyttix:BAAALAAECgYICgAAAA==.',Go='Goatjugs:BAAALAAECgMIBQAAAA==.Gobkorum:BAAALAADCgcIDgABLAAECgMICAABAAAAAA==.Golkra:BAAALAAECggIAwAAAA==.Goo:BAAALAADCggICAAAAA==.',Gr='Greyscale:BAAALAAECgMICAAAAA==.',Gy='Gyroblade:BAAALAADCggIFgAAAA==.Gyrolock:BAAALAADCgQIBAAAAA==.',Ha='Hannabi:BAAALAADCgcIBwAAAA==.Harald:BAAALAAECgMIBgAAAA==.Harute:BAAALAADCgYIBgAAAA==.Hazzat:BAAALAAECgEIAQAAAA==.',He='Healbelly:BAAALAAECgYIBgAAAA==.Hellghast:BAAALAADCgcIBwAAAA==.',Ho='Holyaspect:BAAALAADCggICAAAAA==.Hoofs:BAAALAADCgMIAwAAAA==.Hornihoofed:BAAALAAECgIIAgAAAA==.',Hu='Huana:BAAALAAECgQICAAAAA==.Hugono:BAAALAADCgcIBwAAAA==.Huntisophi:BAAALAADCggICAAAAA==.',Ib='Ibee:BAAALAAECgcIEAAAAA==.',Ic='Icebloke:BAAALAADCgMIAwAAAA==.',Ig='Iggydh:BAAALAAECgMIAwAAAA==.Igris:BAAALAADCgcIBwAAAA==.',Il='Illium:BAAALAAECgUICQAAAA==.',In='Insapirest:BAABLAAECoEfAAMIAAgI/B0pEQCMAgAIAAgI/B0pEQCMAgAMAAgIxRaCGQAwAgAAAA==.',Io='Ioorek:BAAALAADCgcIBwAAAA==.',Je='Jeff:BAAALAAECggICQAAAA==.',Jo='Jormunthun:BAAALAADCgQIBAABLAAECgcIFwANAA0gAA==.Jotuhn:BAABLAAECoEXAAINAAcIDSCjBgCZAgANAAcIDSCjBgCZAgAAAA==.',Ka='Kalagai:BAAALAAECgYIEQAAAA==.Kalawayz:BAAALAAECgUIDAAAAA==.Kalileus:BAACLAAFFIEIAAIOAAMIYhfMAgAAAQAOAAMIYhfMAgAAAQAsAAQKgR8AAg4ACAjhI/cCACoDAA4ACAjhI/cCACoDAAAA.Kalindaa:BAABLAAECoEWAAIEAAcI1A73SABlAQAEAAcI1A73SABlAQAAAA==.Kanyeewest:BAAALAADCgMIAgABLAAECgMIAwABAAAAAA==.Karen:BAAALAAECgcIDgABLAAECggIIgAPAB4mAA==.Katoma:BAAALAADCggIDQABLAAECgcIFwABAAAAAQ==.Katroyana:BAAALAAECgUIDQAAAA==.',Ke='Kejser:BAAALAAECgYIEQAAAA==.Keltharion:BAAALAAECgMIAgAAAA==.Keshina:BAAALAAECggICAAAAA==.Keyrra:BAAALAAECgMIBAAAAA==.',Kh='Khalisee:BAAALAADCgMIBAAAAA==.',Ki='Kiie:BAAALAADCggICAAAAA==.Kirá:BAAALAADCggIDwAAAA==.Kitch:BAAALAAECgYIDwAAAA==.',Kr='Kray:BAAALAAECgYICgAAAA==.Krayvoker:BAAALAAECgQIBwABLAAECgYICgABAAAAAA==.Krayzie:BAAALAAECgIIAwABLAAECgYICgABAAAAAA==.Krayzier:BAAALAAECgUICQABLAAECgYICgABAAAAAA==.Krus:BAAALAADCggIEgAAAA==.',Ku='Kulens:BAAALAADCgMIAwAAAA==.',La='Larsia:BAAALAADCgYIBgAAAA==.Laukr:BAAALAAECgIIAgAAAA==.Lazaruss:BAAALAAECgYIDwAAAA==.',Le='Leightôx:BAAALAAECgIIAgAAAA==.Lekaface:BAAALAAECggICAAAAA==.Leonie:BAAALAAECgUIDQAAAA==.Leoric:BAAALAAECggIDgAAAA==.Lev:BAAALAAECgYIDQAAAA==.Levri:BAAALAADCggICwAAAA==.',Lh='Lhyrin:BAAALAAECgIIBAAAAA==.',Li='Lisbet:BAAALAAECgEIAQAAAA==.',Lo='Locutuz:BAAALAADCgcIBgAAAA==.',Lu='Lucille:BAAALAAECgYIDgAAAA==.Luuna:BAAALAAECgYIBgAAAA==.',Ly='Lylli:BAAALAAECgQICgAAAA==.',['Lò']='Lòky:BAAALAADCgcICAAAAA==.',['Ló']='Lóckybalboa:BAAALAADCggIBAAAAA==.',['Lø']='Løvehjerte:BAAALAAECgIIBgABLAAECgYIEQABAAAAAA==.',Ma='Maddman:BAAALAADCggICAAAAA==.Maranque:BAABLAAECoEXAAMQAAcIxBw7JABLAgAQAAcIxBw7JABLAgARAAMIQBRdQgCjAAAAAA==.Marqeez:BAAALAAECgIIBAAAAA==.Marík:BAAALAAECgQICgAAAA==.Maseraati:BAAALAAECgYICAABLAAECgcIFwAEAKAXAA==.Mazekine:BAAALAADCgcIDgAAAA==.',Me='Meowdyen:BAAALAAECggICQABLAAECggIDgABAAAAAA==.Meowmonster:BAAALAAECgEIAQAAAA==.',Mi='Mightymind:BAAALAAECgUIDQAAAA==.Millgid:BAAALAAECgYIDgAAAA==.Minzan:BAAALAAECgIIAgAAAA==.Missdagger:BAABLAAECoEgAAIHAAgInyAVAgAJAwAHAAgInyAVAgAJAwAAAA==.Mivie:BAAALAAECgEIAQABLAAFFAMIBQAFAGsKAA==.Mivielle:BAAALAAFFAEIAQABLAAFFAMIBQAFAGsKAA==.Mivstrangler:BAACLAAFFIEGAAISAAIILQu6BwCRAAASAAIILQu6BwCRAAAsAAQKgRwAAhIACAj1GbMFAHMCABIACAj1GbMFAHMCAAEsAAUUAwgFAAUAawoA.',Mo='Monkry:BAAALAADCgIIAgABLAAECgYIDwABAAAAAA==.Moochacho:BAAALAADCgMIAwAAAA==.Moontouched:BAAALAAECgYIBgAAAA==.Moonwitch:BAAALAAECgMICAAAAA==.Moosekorum:BAAALAADCgYIBgABLAAECgMICAABAAAAAA==.Morgonljus:BAABLAAECoEaAAIEAAgIfAtXMgDGAQAEAAgIfAtXMgDGAQAAAA==.Morpheen:BAABLAAECoEdAAMQAAgIsyU/AwBVAwAQAAgIsyU/AwBVAwATAAEIJxqVEQBGAAAAAA==.Morza:BAAALAADCggIDgAAAA==.',Mu='Munk:BAABLAAFFIEIAAIUAAUIJxoSAQDLAQAUAAUIJxoSAQDLAQAAAA==.Mushaweth:BAAALAAECggIDAAAAA==.',My='Mysticfinger:BAAALAAECgcIDQAAAA==.Myztery:BAAALAAECgIIAgAAAA==.',['Mø']='Møth:BAAALAADCggICAAAAA==.',Na='Nalen:BAAALAAECgUICQAAAA==.Nanya:BAAALAADCgcIBwAAAA==.Narayana:BAAALAADCgQIBAAAAA==.Naschahoof:BAAALAAECgYICwAAAA==.Nathanial:BAAALAAECgMIBQAAAA==.',Ne='Necrathen:BAAALAAECgMIBQAAAA==.Neithnepthys:BAAALAAECgUIBwAAAA==.Nemethys:BAACLAAFFIEHAAIVAAMIyxdjBAD3AAAVAAMIyxdjBAD3AAAsAAQKgRgAAhUACAggHUUNAJQCABUACAggHUUNAJQCAAAA.Nephelle:BAAALAAECgMICAAAAA==.Neurotiica:BAAALAAECgMIBgAAAA==.Neztemic:BAAALAAECgcIEAAAAA==.',No='Northman:BAAALAADCggIFgAAAA==.',Nu='Nuttynut:BAAALAAECgYIDgAAAA==.',['Nø']='Nøkk:BAAALAAECgcIDwAAAA==.',Ok='Okatsuki:BAAALAADCgcIBwAAAA==.',Ol='Olliemage:BAAALAAECgUIDQABLAAFFAMIBwAWAM8QAA==.Ollievol:BAACLAAFFIEHAAIWAAMIzxB/BADxAAAWAAMIzxB/BADxAAAsAAQKgR0AAhYACAjKIpIFACEDABYACAjKIpIFACEDAAAA.',Op='Opprørgutt:BAAALAAECgYICQAAAA==.',Or='Oritka:BAAALAAECgMIBwAAAA==.Orpser:BAABLAAECoEXAAIXAAcIDRo1BQBBAgAXAAcIDRo1BQBBAgAAAA==.',Ov='Ovenmitt:BAABLAAECoEXAAIEAAgIpyImCgD1AgAEAAgIpyImCgD1AgAAAA==.',Pa='Paladinima:BAAALAAECgcIEQAAAA==.Palapipinz:BAAALAAECgEIAQAAAA==.Pathpoppy:BAAALAADCgUIAgAAAA==.',Pe='Perfo:BAABLAAECoEXAAIYAAcIjBs/DgAqAgAYAAcIjBs/DgAqAgAAAA==.',Ph='Phyrra:BAAALAADCgcIDgAAAA==.',Pi='Pinkres:BAAALAAECgIIAQAAAA==.Pinobianco:BAAALAAECgEIAQAAAA==.',Po='Poityfish:BAAALAAECgMIBQAAAA==.Polkra:BAAALAADCgUIBwAAAA==.Pookiebéar:BAAALAADCggIDwAAAA==.Posix:BAAALAAECgEIAQAAAA==.Powz:BAAALAAECgUIDQAAAA==.Pozzik:BAAALAAECgYIDwAAAA==.',Pr='Praeis:BAAALAADCgEIAQABLAAECgcIDgABAAAAAA==.Pronyma:BAAALAADCgcIBwAAAA==.Protégé:BAAALAADCgIIAgAAAA==.',Py='Pyris:BAAALAAECgcIEwAAAA==.',Qn='Qnt:BAAALAAECgYICgAAAA==.',Qt='Qtn:BAAALAAECggICAAAAA==.',Qu='Quacksalot:BAAALAAECgYIDgAAAA==.',Ra='Ralith:BAAALAADCgcIBwAAAA==.Rapidutza:BAAALAAECgYICwAAAA==.',Rh='Rhensie:BAAALAAECgUIDQAAAA==.',Ri='Rini:BAACLAAFFIEFAAIZAAMIax3CAAAWAQAZAAMIax3CAAAWAQAsAAQKgRgAAhkACAjBJMMBADQDABkACAjBJMMBADQDAAAA.',Ru='Ruse:BAAALAADCgMIAwAAAA==.',Ry='Ryerow:BAABLAAECoEXAAMaAAgI/CCvFQC0AgAaAAgI/CCvFQC0AgAYAAgIGA2iGAC2AQAAAA==.Ryro:BAAALAADCggICAABLAAECggIFwAaAPwgAA==.Ryspank:BAAALAAECgYICgABLAAECgYIDwABAAAAAA==.',['Rý']='Rý:BAAALAAECgYIDwAAAA==.',Sa='Saltysbear:BAAALAAECgEIAQAAAA==.Sanguinius:BAAALAADCgQIAwAAAA==.',Sc='Scarly:BAAALAAECgUIBQAAAA==.Scrubba:BAAALAADCgcIBgAAAA==.',Se='Selekker:BAAALAADCgYICgAAAA==.Selekkers:BAAALAADCggIFgAAAA==.',Sh='Shaensyl:BAABLAAECoEeAAIbAAgIDyDwDQD1AgAbAAgIDyDwDQD1AgAAAA==.Sharona:BAAALAADCgUIBQAAAA==.Shaula:BAAALAAECgEIAQAAAA==.Shinybob:BAAALAAECgYIDgAAAA==.Shion:BAAALAAECgMIBQAAAA==.Shínoblí:BAAALAADCggICAAAAA==.',Si='Sinikarhu:BAAALAADCgIIAgAAAA==.',Sl='Slackalice:BAAALAADCggICAAAAA==.',Sm='Smithydh:BAABLAAECoEVAAIbAAcIvhbLNgDpAQAbAAcIvhbLNgDpAQAAAA==.',Sn='Snaffle:BAABLAAECoEfAAIPAAgIPSRzBABIAwAPAAgIPSRzBABIAwAAAA==.Snehvit:BAAALAAECgQICgAAAA==.Snif:BAAALAADCgYIBgAAAA==.',So='Solledemon:BAAALAADCgYIBgAAAA==.Solstice:BAAALAAECgMIAwAAAA==.Someholybreh:BAABLAAECoEXAAIMAAcIyxo9HQAUAgAMAAcIyxo9HQAUAgAAAA==.Somemagebreh:BAAALAADCgIIAgAAAA==.Soorman:BAAALAAECgYICQAAAA==.',Sp='Speedtank:BAAALAAECgMICAAAAA==.Spitebobels:BAAALAADCgcIBwAAAA==.Splinter:BAAALAAECgcIFwAAAQ==.',St='Starstrider:BAAALAADCgQIBAAAAA==.Stinkum:BAACLAAFFIEIAAIcAAMIVhRCAgDwAAAcAAMIVhRCAgDwAAAsAAQKgRsAAhwACAjZG7EHAFECABwACAjZG7EHAFECAAAA.Sturmente:BAABLAAECoEXAAIdAAgI1xq1DwBeAgAdAAgI1xq1DwBeAgAAAA==.',Su='Sulyatha:BAAALAAECgIIAgAAAA==.Sunstórm:BAAALAAECgYIDgAAAA==.Suspeak:BAAALAAECgUIDAAAAA==.',Sy='Sycolich:BAAALAAECgYIDwAAAA==.Sylvan:BAAALAADCgYIBgABLAAECgYIDgABAAAAAA==.Synical:BAAALAAECgMIBQAAAA==.',Sz='Szeras:BAAALAAFFAMIAwAAAA==.',Te='Tedwardian:BAAALAAECgUIBQABLAAECgcIDgABAAAAAA==.Tela:BAAALAAECgcIBwABLAAFFAMIBQAZAGsdAA==.Templaxi:BAAALAAECgMIAwAAAA==.',Th='Thejoker:BAAALAADCggIDQAAAA==.Therix:BAAALAAECgYICQAAAA==.Thommee:BAAALAAECgYIDAAAAA==.Thora:BAAALAAECggICAAAAA==.Thoreleo:BAABLAAECoETAAIeAAgIDRKgFQAbAgAeAAgIDRKgFQAbAgAAAA==.Thorgrim:BAAALAADCgcIDAAAAA==.',Ti='Tinkerbel:BAABLAAECoEXAAMEAAcIoBf4KgDrAQAEAAcIoBf4KgDrAQADAAEI1hDucQAxAAAAAA==.',To='Tomato:BAAALAADCggICQAAAA==.',Tr='Transformerx:BAAALAAECgUIDQAAAA==.Tripin:BAAALAAECgUICwAAAA==.Tropix:BAAALAADCggICAAAAA==.',Ty='Tylee:BAABLAAFFIEFAAIFAAMIawr1BQDZAAAFAAMIawr1BQDZAAAAAA==.Tyranious:BAAALAAECgcIBwAAAA==.Tyrell:BAAALAADCgUIBQAAAA==.',['Tá']='Tállia:BAAALAADCgMIAwAAAA==.',Um='Umauma:BAAALAADCgYIBgAAAA==.',Un='Unkelbob:BAAALAADCgMIAwAAAA==.',Ut='Utur:BAAALAADCgMIAwAAAA==.',Va='Valkora:BAAALAAECgMIAwAAAA==.',Ve='Vedalken:BAAALAADCgcIBwAAAA==.Vexareh:BAAALAAECgMIBQAAAA==.Vexorc:BAAALAADCgcIBwAAAA==.',Vi='Violamania:BAAALAAECgYICgABLAABCgIIAgABAAAAAA==.Viridi:BAAALAAECgUICQAAAA==.',Vo='Voidmark:BAAALAAECgcICwAAAA==.',Vr='Vreemdevogel:BAAALAADCggIFwAAAA==.Vriseida:BAAALAADCggIFAAAAA==.',['Vá']='Várkáld:BAAALAADCgcIBwAAAA==.',Wa='Walpole:BAAALAAECggIBgAAAA==.Waytooslow:BAAALAAECgMIBAAAAA==.',Wi='Willowblade:BAAALAAECgIIAgAAAA==.Winterente:BAAALAAECgcIBwABLAAECggIFwAdANcaAA==.Wipers:BAAALAADCgcIEQAAAA==.',Xe='Xenions:BAAALAAECgcIEgAAAA==.Xeoxar:BAAALAADCggICwAAAA==.Xeryhn:BAAALAAECgcIDwAAAA==.',Xi='Xialan:BAAALAADCggIGgAAAA==.Xias:BAAALAAECgYICAAAAA==.',Ya='Yakstrangler:BAABLAAECoEfAAIfAAgIpB+JDADgAgAfAAgIpB+JDADgAgAAAA==.',Ye='Yesmir:BAAALAADCgEIAQAAAA==.',Yo='Yokilee:BAAALAADCggIEAAAAA==.Yonghwa:BAAALAADCgcIFAABLAAECgMICAABAAAAAA==.',Yu='Yudokuna:BAAALAAECgUICAAAAA==.',Za='Zabaws:BAAALAADCggICwAAAA==.Zanean:BAAALAAECgUICAAAAA==.Zapemall:BAAALAAECgUIBQAAAA==.Zatiah:BAAALAADCgYIBgAAAA==.',Ze='Zelmaran:BAAALAAECgYIEAAAAA==.Zewz:BAAALAAECgMIBQAAAA==.',Zi='Zinpala:BAAALAAECgYIBgABLAAECgcIDQABAAAAAA==.',Zn='Znek:BAAALAAECgQICgAAAA==.',Zo='Zorhen:BAAALAAECgQICgAAAA==.',Zu='Zussa:BAAALAADCgQIBAAAAA==.',['Ðx']='Ðxc:BAAALAAECgYIDQAAAA==.',['Øp']='Øpa:BAAALAADCgIIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end