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
 local lookup = {'Shaman-Enhancement','Hunter-BeastMastery','Paladin-Retribution','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Paladin-Holy','Druid-Restoration','Warrior-Fury','Priest-Holy','Priest-Discipline','Shaman-Restoration','Unknown-Unknown','Druid-Feral','Hunter-Survival','DemonHunter-Havoc','Mage-Arcane','Evoker-Preservation','Hunter-Marksmanship','Warrior-Arms','DeathKnight-Unholy','Druid-Guardian','Mage-Fire','Mage-Frost','Rogue-Outlaw','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Druid-Balance','DeathKnight-Frost','DeathKnight-Blood','Rogue-Assassination','Rogue-Subtlety','Shaman-Elemental','Warlock-Affliction','DemonHunter-Vengeance',}; local provider = {region='EU',realm="Eldre'Thalas",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ac='Aciclovir:BAAALAADCgYICgAAAA==.',Ai='Aimepty:BAABLAAECoErAAIBAAgIMyF+AwDvAgABAAgIMyF+AwDvAgAAAA==.',Ak='Akàb:BAAALAADCgcIDwAAAA==.',Al='Alaid:BAAALAADCgcIBwAAAA==.',Am='Amelianne:BAAALAADCggIDQAAAA==.Amélianne:BAAALAAECgUICgABLAAECggILAACAPYdAA==.',An='Anarchicia:BAAALAAECgIIAwAAAA==.Anarra:BAAALAAECgUIBQABLAAFFAYIFwADAIEjAA==.',Ar='Arbonne:BAAALAAECgcIDgAAAA==.Arcanæ:BAAALAADCgcICgAAAA==.Arcanîste:BAAALAADCggIEwAAAA==.Arsôr:BAACLAAFFIEQAAIEAAQIpRNdBwDuAAAEAAQIpRNdBwDuAAAsAAQKgScABAQACAjQIAEGAO8CAAQACAjQIAEGAO8CAAUAAginB+RRAFwAAAYAAQjhDyJAADcAAAAA.Arä:BAAALAADCgUIBQAAAA==.',As='Asap:BAAALAADCggICAAAAA==.Ashama:BAACLAAFFIESAAIHAAYIABt6AgA2AgAHAAYIABt6AgA2AgAsAAQKgTEAAgcACAj4JRAEAFsDAAcACAj4JRAEAFsDAAAA.Asharcane:BAAALAADCggIFgAAAA==.',Aw='Awikachikaën:BAAALAAECgYIBgABLAAFFAMICQAIAPcOAA==.',Ay='Ayunécro:BAAALAADCgQIAwAAAA==.Ayusham:BAAALAAECgcIEAAAAA==.',Az='Azariel:BAAALAADCgYIBgABLAAECgcIFAAJABMcAA==.',Ba='Bamboum:BAAALAADCgYIBwAAAA==.Barragan:BAAALAADCgQIBAAAAA==.',Be='Bellaya:BAAALAAECgMIAwAAAA==.Betrayer:BAACLAAFFIEKAAIKAAYIRh3JAQBlAgAKAAYIRh3JAQBlAgAsAAQKgTQAAgoACAgYJgQCAIEDAAoACAgYJgQCAIEDAAAA.',Bi='Biguemac:BAAALAADCggICAAAAA==.Biinnii:BAAALAAECggICAAAAA==.Bimbames:BAAALAADCggIDgAAAA==.Bimladin:BAAALAADCgUIBQAAAA==.',Bl='Blindd:BAAALAADCggICAAAAA==.Blôom:BAAALAAECgYIDQAAAA==.Blùe:BAABLAAECoEaAAMLAAYIkxzANgDeAQALAAYIkxzANgDeAQAMAAMI9QwAAAAAAAAAAA==.Blûe:BAABLAAECoEUAAINAAYIdhSZdQBhAQANAAYIdhSZdQBhAQABLAAECgYIGgALAJMcAA==.',Bo='Bobmarleybob:BAAALAADCgcIDgAAAA==.Boldash:BAAALAAECgYICAAAAA==.Boorg:BAAALAADCggIFgABLAAECgcICgAOAAAAAA==.Boudiouu:BAAALAADCgYICwAAAA==.Bouteilles:BAAALAADCgUIDgAAAA==.Boâ:BAAALAAECgYIDQAAAA==.',Br='Brie:BAAALAAECgQIBgABLAAECggIIwAPAO8eAA==.Brigesse:BAAALAADCgcIEAAAAA==.',Bu='Buffware:BAAALAAFFAEIAQAAAA==.Burnhyl:BAABLAAECoEWAAIDAAcI7xOdbQDfAQADAAcI7xOdbQDfAQAAAA==.Burnyyii:BAAALAAECgYIDQABLAAECgcIFgADAO8TAA==.',Ce='Cerace:BAAALAAECgEIAQAAAA==.',Ch='Chamanow:BAAALAADCggIGgAAAA==.Chasseterre:BAAALAAECgMIBAAAAA==.Chouille:BAAALAADCgcIBwAAAA==.Chura:BAAALAAECgYIDQAAAA==.Chynezh:BAAALAAECgIIBAAAAA==.',Ci='Cissoouu:BAAALAAECgYICgAAAA==.',Cl='Claydhunt:BAACLAAFFIEFAAIQAAIIziVNAQDbAAAQAAIIziVNAQDbAAAsAAQKgR0AAhAACAhAJisAAIwDABAACAhAJisAAIwDAAAA.Clinsunset:BAAALAAECgMIAwAAAA==.',Co='Coromak:BAAALAAECggIBgAAAA==.Couloirdebus:BAAALAAECgYIBgAAAA==.Courtepaille:BAAALAADCgcIDQABLAAECggIIwAPAO8eAA==.',Cp='Cptlameule:BAACLAAFFIENAAIFAAQISSQjAwCqAQAFAAQISSQjAwCqAQAsAAQKgTYAAgUACAilJlkBAHIDAAUACAilJlkBAHIDAAAA.',Cx='Cxa:BAABLAAECoEXAAIRAAgILBTrhACOAQARAAgILBTrhACOAQAAAA==.',['Cé']='Céluné:BAAALAAECgYIDQAAAA==.Célène:BAAALAADCggICAAAAA==.',Da='Darckmaul:BAAALAADCgYIBwAAAA==.Darkzintos:BAAALAADCgMIAwAAAA==.Dash:BAAALAADCggICAAAAA==.',De='Debzza:BAAALAADCggICAAAAA==.Demerys:BAAALAAECggIEgAAAA==.Demonhunter:BAAALAADCggIEwAAAA==.Derfo:BAAALAAECgYIDQAAAA==.Derrieri:BAAALAAECgMIAwAAAA==.Dexiliah:BAAALAAECgcIBwABLAAECggIEgAOAAAAAA==.',Dh='Dhuduke:BAAALAADCggIEAAAAA==.',Di='Diora:BAAALAAECgUICQAAAA==.',Do='Dolares:BAABLAAECoEUAAISAAYI0RcLYgC+AQASAAYI0RcLYgC+AQAAAA==.Doomyria:BAAALAADCggIEQAAAA==.',Dr='Dragnör:BAAALAADCgYIBgAAAA==.Dramaqween:BAAALAAECggICQAAAA==.Dramaqweeñ:BAAALAADCggIBgAAAA==.Dreykare:BAAALAAECggIDwAAAA==.Drogdur:BAAALAAECgYIBgAAAA==.Drâx:BAAALAADCgcICQAAAA==.',['Dè']='Dènna:BAAALAAECgYICgAAAA==.',Ec='Eclipsedawn:BAAALAADCgMIAwAAAA==.',El='Elloco:BAABLAAECoEYAAIDAAYIfBNWrABpAQADAAYIfBNWrABpAQAAAA==.Ellocogringo:BAAALAADCgYIBgABLAAECgYIGAADAHwTAA==.Elrandir:BAAALAAECgYICAABLAAFFAIIBgADAMQlAA==.Elyssëa:BAABLAAECoEUAAITAAcImh0aDABEAgATAAcImh0aDABEAgAAAA==.',En='Engii:BAAALAADCggICwAAAA==.Engy:BAACLAAFFIEJAAMUAAQInRBKEADDAAAUAAMIzhBKEADDAAACAAMI4wgAAAAAAAAsAAQKgTYAAxQACAg/IngOAOMCABQACAjIIHgOAOMCAAIABwh2I8ZMAPkBAAAA.Enzt:BAABLAAECoEgAAMKAAgI2SIiDgAdAwAKAAgIKyIiDgAdAwAVAAcI3SJpBADDAgAAAA==.',Eo='Eolya:BAAALAAECgEIAQAAAA==.',Er='Eraddak:BAABLAAECoEVAAIWAAYIhCO6DwBGAgAWAAYIhCO6DwBGAgAAAA==.',Es='Eslanas:BAAALAAECgYICgAAAA==.Espérentya:BAAALAAECgYIBgAAAA==.',Ev='Evozag:BAAALAADCgcIBgAAAA==.',Ex='Exilias:BAAALAAECggIEgAAAA==.',Fa='Fakedownn:BAAALAAECgMIAwABLAAECgcIGAAIAEggAA==.Fazzmania:BAAALAADCggIGAAAAA==.',Fi='Finaleva:BAAALAADCggICwAAAA==.Fireware:BAAALAADCggICAAAAA==.',Fr='Frostty:BAAALAADCgEIAQAAAA==.Frïgg:BAAALAAECgcIDgAAAA==.',Ga='Gangrelune:BAAALAAECgIIBAABLAAECggIHwARAL8iAA==.Gankbeng:BAAALAADCgYIBgABLAAFFAQICQAUAJ0QAA==.',Gh='Ghostofnijz:BAAALAAECggIEQAAAA==.',Gi='Ginkgo:BAAALAADCgUIBQAAAA==.',Go='Gogrren:BAABLAAECoEkAAIUAAcIqwzdWwAxAQAUAAcIqwzdWwAxAQAAAA==.',Gr='Gromak:BAAALAAECgYIEAABLAAECggIBgAOAAAAAA==.Grosciflard:BAABLAAECoEjAAMPAAgI7x7BCACqAgAPAAgI7x7BCACqAgAXAAQIcAs3IwCYAAAAAA==.Groød:BAABLAAECoEZAAIFAAYIQRwuIADNAQAFAAYIQRwuIADNAQAAAA==.Grreen:BAAALAAECgYIBgAAAA==.Grren:BAAALAAECgYIDAAAAA==.',Gu='Guldur:BAAALAAECgIIBAAAAA==.',Gw='Gwoboff:BAAALAAECgYIBgAAAA==.',Gy='Gyn:BAAALAADCgcICwAAAA==.',Ha='Hakime:BAAALAADCgYIBwAAAA==.Hargo:BAAALAADCgcIBwAAAA==.',He='Heîsenberg:BAAALAAECgcICgAAAA==.',Hi='Hinoki:BAAALAADCggICAAAAA==.Hitreck:BAAALAADCgYICAAAAA==.',Hr='Hrafn:BAAALAAECgYIDQAAAA==.',Hy='Hybridame:BAABLAAECoEZAAIYAAcIfxIBBwDcAQAYAAcIfxIBBwDcAQAAAA==.Hydrä:BAAALAAECgQIBgABLAAECggIGQAJAOYcAA==.Hypnofû:BAAALAADCggICAAAAA==.Hypnotus:BAAALAAECgYIEwAAAA==.',['Hé']='Héloise:BAAALAADCgcICAAAAA==.Hérøik:BAAALAADCggIDAAAAA==.',['Hô']='Hôka:BAABLAAECoEWAAINAAYIJRxZTADQAQANAAYIJRxZTADQAQAAAA==.',Ih='Ihaveatoto:BAAALAAECgIIAgABLAAECgcIDgAOAAAAAA==.',Il='Illidash:BAAALAADCgUIBQAAAA==.',Im='Immo:BAAALAADCgYIBgAAAA==.',In='Inayra:BAAALAAECgcICgAAAA==.Instagrahm:BAAALAAECgEIAQAAAA==.',Ir='Irïnna:BAABLAAECoEsAAICAAgI9h3qJwB+AgACAAgI9h3qJwB+AgAAAA==.',Is='Isildur:BAAALAADCgcICQAAAA==.Isshun:BAAALAADCgcIDAAAAA==.',Je='Jeanbôb:BAABLAAECoEfAAISAAgITRNjTgD6AQASAAgITRNjTgD6AQAAAA==.Jerrywallace:BAAALAAECgIIBgAAAA==.',Ju='Judge:BAAALAADCggIFgAAAA==.Julieo:BAAALAAECggICgAAAA==.',Ka='Kaexas:BAAALAADCgUIBQAAAA==.Kahzdin:BAAALAADCgIIAgAAAA==.Kahzdun:BAAALAAECggICQAAAA==.Kallyne:BAAALAADCggIEQAAAA==.Kamizøle:BAAALAADCgQIBAAAAA==.Kascendre:BAABLAAECoEqAAIMAAgIlhMxDAC3AQAMAAgIlhMxDAC3AQAAAA==.Katalinya:BAAALAAECgMIAwABLAAECgMIBgAOAAAAAA==.Kataouchee:BAAALAADCgcIBwAAAA==.Kayrina:BAAALAAECggICAAAAA==.Kaîoken:BAAALAAECgYIDAABLAAECgcICgAOAAAAAA==.',Ke='Kelthius:BAAALAAECgcICgAAAA==.Kento:BAABLAAECoEcAAIKAAgIdhggLwBLAgAKAAgIdhggLwBLAgAAAA==.Keytala:BAAALAAECgIIBAAAAA==.',Ki='Killgorm:BAAALAAECgcICwAAAA==.Kiss:BAABLAAECoEbAAMSAAcIPhVTZgCxAQASAAcIyRRTZgCxAQAZAAMIMgyXaQB9AAAAAA==.',Kr='Kreatør:BAAALAAECgYICwAAAA==.',Ky='Kylianne:BAAALAAECgEIAQABLAAECgYIBgAOAAAAAA==.Kyn:BAAALAADCgYIBgAAAA==.',['Kä']='Kälahan:BAAALAAECgYIDQAAAA==.Kärmä:BAABLAAECoEdAAIPAAgIjxCzFgDOAQAPAAgIjxCzFgDOAQAAAA==.',['Kï']='Kïtö:BAAALAADCgUICAAAAA==.',['Kø']='Køsh:BAABLAAECoEYAAINAAgIJhPWRgDhAQANAAgIJhPWRgDhAQAAAA==.',La='Lagherta:BAAALAAECgEIAQAAAA==.Lagosh:BAAALAADCgYIBgAAAA==.Lanthanide:BAAALAAECgUIBQABLAAECggIJAAaAAkdAA==.Lapire:BAAALAAECggICAABLAAECggIFAAZAMAPAA==.',Le='Leahkcim:BAAALAADCgcICgAAAA==.Lee:BAACLAAFFIEIAAMEAAMIdBH7BwDiAAAEAAMIdBH7BwDiAAAFAAII7AAlFAA+AAAsAAQKgR0AAwQACAj7HesJAKcCAAQACAj7HesJAKcCAAUABQjwDgs3ACcBAAAA.Legrosdingue:BAACLAAFFIEJAAIbAAMIhhuRBgAcAQAbAAMIhhuRBgAcAQAsAAQKgSIAAxsACAiyGGUbACMCABsACAiyGGUbACMCABUAAQjEANI6AAMAAAAA.Lepyr:BAABLAAECoEUAAMZAAYIwA+ATQANAQASAAYIaA8lhgBcAQAZAAUI/QuATQANAQAAAA==.',Li='Libox:BAAALAADCgcIBwAAAA==.Lifebloom:BAAALAADCgIIAgAAAA==.Lilÿth:BAAALAADCggIEAABLAAECgcIFQAcAEQZAA==.Liø:BAAALAADCggIDgAAAA==.',Lo='Lorible:BAABLAAECoEdAAILAAYIERqWRACeAQALAAYIERqWRACeAQAAAA==.Lormonia:BAAALAADCggIDwABLAAECgUICwAOAAAAAA==.Lormonus:BAAALAAECgUICwAAAA==.',Lu='Lugan:BAACLAAFFIEFAAILAAIIFg29JQCOAAALAAIIFg29JQCOAAAsAAQKgSEAAgsACAj1EFY8AMMBAAsACAj1EFY8AMMBAAAA.Lukywi:BAABLAAECoEcAAIbAAYIuiHiGAA6AgAbAAYIuiHiGAA6AgAAAA==.',Ly='Lyandris:BAABLAAFFIEHAAICAAQIXBWREgDpAAACAAQIXBWREgDpAAAAAA==.',['Lî']='Lîlïth:BAABLAAECoEUAAMIAAYIpBlFJQC/AQAIAAYIpBlFJQC/AQADAAUIzxevtQBYAQAAAA==.',['Lï']='Lïlýth:BAABLAAECoEVAAIcAAcIRBlsPwANAgAcAAcIRBlsPwANAgAAAA==.',Ma='Maejin:BAAALAAECgcIBwAAAA==.Maektha:BAAALAAECgcIDwAAAA==.Magalouche:BAAALAADCgYIDAAAAA==.Magimux:BAAALAADCgQIBAAAAA==.Magmaurgar:BAAALAADCgQIBAAAAA==.Malgreen:BAAALAADCgYIBgAAAA==.Malkith:BAAALAAECgIIAgAAAA==.Mandi:BAAALAAECgMIBgAAAA==.Mandii:BAAALAAECgIIAgABLAAECgMIBgAOAAAAAA==.Mandogore:BAAALAADCggICAAAAA==.Marcellus:BAAALAADCgMIAwABLAAECggIKgAZADolAA==.Marcya:BAACLAAFFIEGAAISAAIIOSRbIADMAAASAAIIOSRbIADMAAAsAAQKgRkAAhIACAgyJCsTAAEDABIACAgyJCsTAAEDAAAA.Marihma:BAABLAAECoEVAAISAAcI0BHFagClAQASAAcI0BHFagClAQAAAA==.Maulg:BAAALAAECgUIBQAAAA==.Maxibuse:BAABLAAECoEWAAIJAAYIQR97KAAXAgAJAAYIQR97KAAXAgAAAA==.Mazlumollum:BAAALAAECggIBQAAAA==.Mazykeen:BAAALAADCgEIAQAAAA==.',Me='Mehrziya:BAAALAADCggICAABLAAFFAUIEAAdAE0UAA==.Mendine:BAAALAAECgUICgAAAA==.',Mh='Mhatilem:BAAALAAECgYICgABLAAECggIGwAeAN4kAA==.',Mi='Mimps:BAAALAAECgYIDwAAAA==.Mindset:BAAALAADCggICAAAAA==.Minucia:BAAALAAECgYIEwAAAA==.Miyunee:BAAALAADCgcIBwABLAAECgYIDQAOAAAAAA==.',Mo='Mogoyï:BAAALAADCgQIBAABLAAECgMIBQAOAAAAAA==.Momon:BAAALAADCgUIBQABLAAECgcICgAOAAAAAA==.Mortïfïa:BAAALAADCggIIAAAAA==.',Mu='Muktananda:BAAALAAECgYIDQAAAA==.Murky:BAABLAAECoEUAAIUAAgIDR4VEwC6AgAUAAgIDR4VEwC6AgAAAA==.',My='Myheal:BAAALAADCgQIBAAAAA==.Myraluxe:BAAALAAECgYIEAAAAA==.',['Má']='Mátto:BAABLAAECoEWAAIZAAcIOBvkGQAnAgAZAAcIOBvkGQAnAgAAAA==.',['Mé']='Mérione:BAAALAAECgUICAAAAA==.',['Më']='Mël:BAAALAAECgYIBgAAAA==.',['Mí']='Míriël:BAABLAAECoEUAAMJAAcIExwWJAAuAgAJAAcIExwWJAAuAgAeAAEIZAVTlAApAAAAAA==.',['Mø']='Mønarch:BAABLAAECoEhAAMfAAgI7x2xOABtAgAfAAgI7x2xOABtAgAgAAcITAYIKAD3AAAAAA==.',Na='Nallà:BAAALAADCgQIBAABLAAECggIGQAJAOYcAA==.Nanaconda:BAABLAAECoEWAAIJAAcIZhtlJQAnAgAJAAcIZhtlJQAnAgAAAA==.Naois:BAABLAAECoEaAAIFAAcILiWHCQDhAgAFAAcILiWHCQDhAgAAAA==.Naollidan:BAAALAADCgIIAgAAAA==.Narcaman:BAAALAAECgYIBgABLAAECgcIFgAUAK4YAA==.Narnya:BAAALAAECgEIAQAAAA==.Naryko:BAABLAAECoEdAAICAAYIbRsjcgCbAQACAAYIbRsjcgCbAQAAAA==.Navysk:BAABLAAECoEgAAMhAAgIhBHZHwADAgAhAAgINhDZHwADAgAiAAcIZw7BGwCLAQAAAA==.Navysky:BAAALAAECggICgAAAA==.Nazoh:BAAALAAECgYIDwAAAA==.',Ne='Nebuka:BAABLAAECoEUAAMdAAcIExnHGwD/AQAdAAcIExnHGwD/AQAcAAEIgxPV0ABIAAAAAA==.Necrom:BAAALAAECgIIBAAAAA==.Necropal:BAAALAAECggIEwAAAA==.Nerd:BAAALAADCggIDgAAAA==.Nerif:BAAALAAECgMIBQAAAA==.Nerilith:BAAALAADCgIIAgABLAAECgYIDQAOAAAAAA==.',Ni='Niedr:BAAALAAECgIIBgAAAA==.Nimportki:BAAALAADCggIFgAAAA==.',Nu='Nuroflemme:BAABLAAECoEiAAMjAAgIHxOcOwDsAQAjAAgIHxOcOwDsAQANAAEIcAuoEgEnAAAAAA==.',['Nä']='Näch:BAAALAAECggIDgAAAA==.',['Né']='Néfertiti:BAAALAADCggICAABLAAFFAMICAAEAHQRAA==.',Ol='Olischean:BAAALAADCgcIEgAAAA==.',Om='Ombredouce:BAAALAADCggICAAAAA==.Oméga:BAAALAAECgYIDQAAAA==.',Op='Opyz:BAABLAAECoEkAAIJAAgIThdRKAAXAgAJAAgIThdRKAAXAgAAAA==.',Or='Ordalyon:BAAALAADCgYIBgAAAA==.Oreillesan:BAAALAAECgYIBgABLAAECgcIFgAJAGYbAA==.Orianis:BAAALAAECgQIBAABLAAFFAYIEgAHAAAbAA==.',Ov='Ovidi:BAABLAAECoElAAIjAAYIzhpRPwDcAQAjAAYIzhpRPwDcAQABLAAECgYIHQACAG0bAA==.',Pa='Padrane:BAAALAAECgEIAQAAAA==.Palaone:BAAALAAECgIIBgAAAA==.Palus:BAAALAADCgMIAwAAAA==.Pantaimort:BAAALAADCgUIBQAAAA==.Pauleth:BAABLAAECoEmAAIeAAgIhhm7IQApAgAeAAgIhhm7IQApAgAAAA==.',Pe='Pearly:BAAALAADCgcIEgAAAA==.',Ph='Phasmixia:BAAALAAECgIIAgAAAA==.Phàrah:BAAALAADCgMIAwAAAA==.',Pl='Plick:BAAALAAECgIIBAAAAA==.',Po='Polzo:BAAALAADCgcIBwAAAA==.Pouladine:BAAALAADCgcICgAAAA==.',Pr='Prekarius:BAAALAAECgYIBgAAAA==.Prukin:BAAALAAECgIIAgAAAA==.',Ps='Psycko:BAAALAADCggIDgAAAA==.',Pt='Ptitenature:BAAALAAECgYIBgAAAA==.',Pu='Pulpefiction:BAAALAAECgYICQAAAA==.Pupuce:BAABLAAECoEmAAISAAgIEiENGgDbAgASAAgIEiENGgDbAgAAAA==.',Py='Pyctograhm:BAABLAAECoEcAAIJAAgINBV6LQD+AQAJAAgINBV6LQD+AQAAAA==.',['Pä']='Päprîka:BAAALAAECgEIAQAAAA==.',Ra='Rachelle:BAAALAAECgQIBAABLAAFFAMICQAIAPcOAA==.Rastatouille:BAAALAAECgMIAwAAAA==.',Re='Reunar:BAAALAAECgIIAgAAAA==.',Rh='Rhazoul:BAAALAADCgUIBwAAAA==.Rhiamina:BAAALAAECgIIAwAAAA==.Rhëa:BAAALAAECgIIAgAAAA==.',Ri='Riacko:BAAALAADCgcIDgAAAA==.Riksho:BAABLAAECoEfAAIUAAgIGxEuOQC8AQAUAAgIGxEuOQC8AQAAAA==.',Ro='Rosemantic:BAAALAADCgMIBAAAAA==.Royalz:BAABLAAECoEcAAIKAAYIjxlwXgCeAQAKAAYIjxlwXgCeAQABLAAECgcICgAOAAAAAA==.',Ry='Ryùùjin:BAAALAAECgQIBAAAAA==.',Sa='Saffici:BAAALAADCgcIDAAAAA==.Sahaquiel:BAAALAADCgcIBwAAAA==.Sazz:BAAALAAECgcIDAAAAA==.',Se='Seizan:BAABLAAECoEZAAIGAAgIjxo/DABtAgAGAAgIjxo/DABtAgAAAA==.Selurecham:BAEALAAECgYIEwABLAAECggIIwATAKwOAA==.Selureevoc:BAEBLAAECoEjAAITAAgIrA7rHQBGAQATAAgIrA7rHQBGAQAAAA==.Senheiser:BAAALAADCgcIBwAAAA==.Seriall:BAABLAAECoEWAAIDAAYIjA8JsgBfAQADAAYIjA8JsgBfAQAAAA==.Seropaladeen:BAAALAADCgcIBwAAAA==.',Sh='Shaïïba:BAAALAAECgQIBAAAAA==.',Si='Sica:BAACLAAFFIEQAAMdAAUITRSaAAB0AQAdAAQIkxiaAAB0AQAcAAMI9QnFHADaAAAsAAQKgS4ABB0ACAg/JLcCAD8DAB0ACAg/JLcCAD8DABwAAwgnFQOmANQAACQAAQghBzY9ADUAAAAA.Simons:BAAALAADCggICAABLAAECggIKwABADMhAA==.',Sk='Skarlx:BAABLAAECoEqAAIhAAgIliSpBgAMAwAhAAgIliSpBgAMAwAAAA==.Skillcapped:BAABLAAECoEYAAIIAAcISCDlCwCeAgAIAAcISCDlCwCeAgAAAA==.Skörie:BAABLAAECoEZAAINAAcIcBPCaACCAQANAAcIcBPCaACCAQAAAA==.',So='Souras:BAAALAADCgYIBgAAAA==.',Sp='Spartatouil:BAAALAADCgcIGQAAAA==.Spartiatte:BAAALAADCggIFQAAAA==.Spystirit:BAAALAAECggIEgAAAA==.',St='Støya:BAAALAAFFAMIAwAAAA==.',Sw='Swieits:BAAALAAECgMIAwAAAA==.Swits:BAAALAAECgYIBgAAAA==.Swørk:BAAALAADCgcIBwABLAAECggIHQAdAMEgAA==.',Sy='Syinn:BAAALAADCggIIQAAAA==.Syphilis:BAABLAAECoEdAAIlAAYI7R7uFwDVAQAlAAYI7R7uFwDVAQAAAA==.',['Sà']='Sàckäpùçe:BAABLAAECoEhAAIJAAcIgRuZLwD0AQAJAAcIgRuZLwD0AQAAAA==.',Ta='Talix:BAABLAAECoEUAAIPAAYIwBLgIQBYAQAPAAYIwBLgIQBYAQAAAA==.Tamales:BAAALAAECgYIDgAAAA==.Tarkol:BAAALAADCgYIBgAAAA==.Tazzmania:BAAALAADCggIIwAAAA==.',Te='Terrestre:BAAALAADCggICAAAAA==.',Th='Therèse:BAACLAAFFIEJAAIIAAMI9w6lCgDjAAAIAAMI9w6lCgDjAAAsAAQKgR0AAggACAhNF98XACUCAAgACAhNF98XACUCAAAA.Thorgrama:BAABLAAECoEXAAICAAYIuQidtAAWAQACAAYIuQidtAAWAQAAAA==.Thorgrïm:BAAALAAECgIIAwAAAA==.',To='Totémique:BAABLAAECoEZAAIjAAgIJh9BGAC6AgAjAAgIJh9BGAC6AgAAAA==.',Tr='Traih:BAABLAAECoEWAAIDAAgIlh2yKACpAgADAAgIlh2yKACpAgAAAA==.',Tu='Tupperware:BAAALAADCgcIBwAAAA==.',Ty='Tygacil:BAAALAAECgUIDAAAAA==.',['Tä']='Tärâ:BAAALAADCggICgAAAA==.',['Tÿ']='Tÿphâ:BAAALAAECgIIAgAAAA==.',Uh='Uha:BAAALAAECgMIBQAAAA==.',Un='Underd:BAAALAAECgIIBgAAAA==.',Ut='Uthred:BAAALAADCgcIBwAAAA==.',Uw='Uwu:BAAALAADCgUIBQAAAA==.',Va='Valoryn:BAAALAAECgMIAQAAAA==.Vanie:BAAALAAECgYIDAAAAA==.Varaldor:BAACLAAFFIEXAAIDAAYIgSOpAACAAgADAAYIgSOpAACAAgAsAAQKgS0AAgMACAjoJuoAAJQDAAMACAjoJuoAAJQDAAAA.Varthnir:BAAALAAECgMIBgAAAA==.',Ve='Velletrax:BAAALAAECgYICgAAAA==.Venlodas:BAAALAAECggICAAAAA==.Veshkär:BAAALAADCgYIJwAAAA==.',Vo='Vorath:BAABLAAFFIEHAAIHAAMIMxE9DgDnAAAHAAMIMxE9DgDnAAAAAA==.',Vu='Vulg:BAAALAADCgQIBAAAAA==.',['Vâ']='Vârum:BAAALAAECggIBwABLAAECggIFAAZAMAPAA==.',Wa='Wardian:BAAALAAECgQIBAABLAAECggIGQAJAOYcAA==.Warzam:BAABLAAECoEYAAIBAAgITBXDCQA7AgABAAgITBXDCQA7AgAAAA==.Wazoo:BAAALAADCggIHwAAAA==.',Wi='Wirmyd:BAAALAADCggICAABLAAECgcIFAAJABMcAA==.',Wo='Woknroll:BAAALAADCggIGAAAAA==.',Xe='Xenium:BAAALAADCggIEQAAAA==.Xetrøn:BAAALAAFFAIIAgAAAA==.',Xy='Xyonus:BAAALAADCgcICQAAAA==.Xyoum:BAAALAADCggIDQAAAA==.',Ya='Yaminge:BAAALAADCgIIAgAAAA==.',Ye='Yelan:BAAALAADCggICAAAAA==.',Yg='Ygethmor:BAABLAAECoEkAAMaAAgICR1FAwC0AgAaAAgICR1FAwC0AgAiAAEI3gL3RwAiAAAAAA==.',Yl='Ylva:BAAALAADCggIFwAAAA==.',Yo='Yoji:BAAALAADCgYIBgAAAA==.Yopinette:BAAALAADCgUIBQAAAA==.',Yu='Yudem:BAAALAADCggICAAAAA==.Yukki:BAAALAAECgQIBwABLAAECggIGQAGAI8aAA==.',Za='Zagzor:BAABLAAECoEhAAMWAAgIsx7iCQCiAgAWAAgIPR3iCQCiAgAfAAcI6hnuUgAiAgAAAA==.Zariah:BAABLAAECoEWAAIDAAYIFRLDqABvAQADAAYIFRLDqABvAQAAAA==.Zatø:BAAALAADCgYIBgAAAA==.',Ze='Zeretor:BAAALAADCggIDAAAAA==.Zewo:BAAALAAECgUIBAAAAA==.',Zh='Zherenyt:BAAALAAFFAIIBAABLAAFFAQIDAAfACYXAA==.Zheretyn:BAACLAAFFIEGAAMQAAIIaBOBAwCkAAAQAAIIaBOBAwCkAAAUAAIIWglxIwB3AAAsAAQKgRgABBQABgjeF2JEAIsBABQABggAF2JEAIsBABAABQh3Fc4ZAJkAAAIAAggmDVH5AGoAAAEsAAUUBAgMAB8AJhcA.',Zo='Zolyna:BAAALAAECgIIBgAAAA==.Zorgash:BAABLAAECoElAAIIAAgIkQxHKwCZAQAIAAgIkQxHKwCZAQAAAA==.',['Zà']='Zàm:BAABLAAECoEkAAIRAAgIsB0NJgCmAgARAAgIsB0NJgCmAgAAAA==.',['Zö']='Zögzog:BAAALAAECgIIBAABLAAECgYIBgAOAAAAAA==.Zögzög:BAAALAADCgIIAgABLAAECgYIBgAOAAAAAA==.',['Ár']='Árgo:BAAALAAECgYIDQAAAA==.',['Âl']='Âlthea:BAAALAAECgIIBAAAAA==.',['Är']='Ärgö:BAAALAADCgIIAgAAAA==.',['Ër']='Ërzäâ:BAAALAADCggIIAAAAA==.',['Ïk']='Ïkers:BAAALAAECgYICQAAAA==.',['Üf']='Üftack:BAAALAAFFAEIAQAAAA==.',['ßa']='ßahazen:BAAALAAECgYIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end