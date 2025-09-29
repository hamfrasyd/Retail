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
 local lookup = {'Rogue-Assassination','Hunter-BeastMastery','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Shaman-Restoration','Shaman-Elemental','Warlock-Destruction','Warlock-Affliction','Mage-Fire','DeathKnight-Frost','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','Warrior-Protection','Monk-Brewmaster','Monk-Mistweaver','Druid-Restoration','Druid-Guardian','Druid-Balance','DemonHunter-Havoc','Mage-Arcane','Warlock-Demonology','Paladin-Protection','Druid-Feral','Monk-Windwalker','Hunter-Marksmanship','DemonHunter-Vengeance','Mage-Frost','Priest-Shadow','Evoker-Augmentation','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Paladin-Holy','Hunter-Survival','Rogue-Subtlety','Rogue-Outlaw',}; local provider = {region='EU',realm='EarthenRing',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aawia:BAABLAAECoEnAAIBAAgINxRCGABAAgABAAgINxRCGABAAgAAAA==.',Ab='Abidi:BAABLAAECoEeAAICAAgIzgWtpgAiAQACAAgIzgWtpgAiAQAAAA==.Abracadavra:BAAALAAECggIEQAAAA==.',Ad='Addinio:BAABLAAECoEaAAIDAAgIBhgxMAA8AgADAAgIBhgxMAA8AgAAAA==.',Ae='Aenah:BAAALAAECgMIAwAAAA==.Aerdris:BAAALAAECgYIBgAAAA==.Aevathar:BAAALAADCgMIAwAAAA==.',Al='Alcyone:BAABLAAECoEUAAMEAAYIZBATNABhAQAEAAYIZBATNABhAQAFAAMIjgJwNwAuAAAAAA==.Alfredjokum:BAAALAAECgIIAgAAAA==.Alithyra:BAAALAADCgYIBgAAAA==.',Am='Amarula:BAAALAAECggIBgAAAA==.',An='Androva:BAAALAADCggICAAAAA==.Angrymalgus:BAAALAAECgIIAgAAAA==.Anirei:BAABLAAECoEfAAMGAAcIlB6kJABXAgAGAAcIlB6kJABXAgAHAAUIDghSeQD4AAAAAA==.Anorwen:BAAALAAECgcICAAAAA==.Anya:BAACLAAFFIEHAAIIAAMIbgwJGgDhAAAIAAMIbgwJGgDhAAAsAAQKgRcAAwgACAjBFBZBAP4BAAgACAjBFBZBAP4BAAkAAgg/EM0rAHMAAAAA.',Ar='Arathi:BAAALAAECgcIDAAAAA==.Arkam:BAABLAAECoEYAAIKAAcIhwaJCwBDAQAKAAcIhwaJCwBDAQAAAA==.Arlanius:BAABLAAFFIEKAAILAAYIFwAMZwA8AAALAAYIFwAMZwA8AAAAAA==.Arostis:BAAALAADCgcIEwAAAA==.Arthulaz:BAAALAAECgQIAQAAAA==.Arthyronyx:BAABLAAECoEhAAMFAAgIoBHcEwC7AQAFAAgIoBHcEwC7AQAEAAYIzwfzQAAKAQAAAA==.',As='Ashrethar:BAABLAAECoEZAAIJAAgIAQWzEgBtAQAJAAgIAQWzEgBtAQAAAA==.Askhim:BAAALAADCgYICgAAAA==.',Av='Avengeline:BAAALAADCggICQAAAA==.',Ba='Baelo:BAAALAADCgcICAAAAA==.Balex:BAAALAAECgQIAQAAAA==.Baxigo:BAAALAADCggICAAAAA==.',Be='Belladonná:BAAALAAECggICAAAAA==.Bemora:BAAALAAECgEIAQAAAA==.Bescea:BAABLAAECoEWAAMLAAgIqR9uHADeAgALAAgIqR9uHADeAgAMAAQIRQ7wKwDBAAAAAA==.Beástmaster:BAAALAADCgcIBwAAAA==.',Bh='Bhalnur:BAABLAAECoEgAAIHAAgIxyLxCQAuAwAHAAgIxyLxCQAuAwAAAA==.',Bl='Blair:BAAALAAECgIIAgAAAA==.',Bo='Bobokart:BAAALAAECgIIAgAAAA==.Bobopala:BAACLAAFFIEFAAINAAIINhamIwCmAAANAAIINhamIwCmAAAsAAQKgR4AAg0ACAjbIXkbAOUCAA0ACAjbIXkbAOUCAAAA.Bomidoff:BAAALAADCgcICQABLAAECgYICQAOAAAAAA==.Bomimeow:BAAALAADCgYIBgABLAAECgYICQAOAAAAAA==.Bonksik:BAACLAAFFIERAAMDAAUIqiLWAwAIAgADAAUIESHWAwAIAgAPAAEI4SEAAAAAAAAsAAQKgSUAAgMACAinJQ8FAGEDAAMACAinJQ8FAGEDAAAA.Bowmistress:BAABLAAECoEYAAICAAcImAWYtgD+AAACAAcImAWYtgD+AAAAAA==.',Br='Bratla:BAAALAADCgcIBwAAAA==.Bratsal:BAAALAAECgYICAAAAA==.Brimlor:BAAALAAECgIIAgAAAA==.Briuk:BAAALAADCgMIAwAAAA==.Bromeo:BAAALAADCgMIAgABLAADCggIDgAOAAAAAA==.Brumble:BAAALAAECgcICAABLAAECgcIEQAOAAAAAA==.Bruna:BAABLAAECoEpAAIQAAgIMSMeAwA5AwAQAAgIMSMeAwA5AwAAAA==.',By='Byakuren:BAAALAADCggIAgAAAA==.',Ca='Calamita:BAAALAADCggIHgAAAA==.Cathbadh:BAAALAAECgYICAAAAA==.',Ce='Cessalls:BAAALAADCggICAAAAA==.',Ch='Chobba:BAAALAAECgEIAQAAAA==.',Cl='Clerik:BAAALAADCggICQABLAAFFAMIBwARAHYZAA==.',Co='Cocowater:BAAALAAECgMIBQAAAA==.Cogwire:BAAALAAECggIDAAAAA==.',Cr='Crims:BAAALAAECgYIBgABLAAECggIIwAEADUfAA==.',Cy='Cyndrel:BAAALAADCgcIDAAAAA==.Cyrann:BAAALAAECgYIDAAAAA==.',Da='Dairus:BAAALAADCggIEAAAAA==.Dargoon:BAAALAADCggICAABLAAECgYICQAOAAAAAA==.Darkblaze:BAAALAAECgUIDgAAAA==.Darkmagiër:BAAALAADCgQIBAABLAAECgcIDgALACoYAA==.Darkstyle:BAAALAADCggICAABLAAECgcIDgALACoYAA==.Darkwank:BAABLAAECoEOAAILAAcIKhgkYgD5AQALAAcIKhgkYgD5AQAAAA==.Daylana:BAAALAAECgYIDAAAAA==.Daysie:BAAALAADCgcIBwAAAA==.',De='Deekadin:BAABLAAECoEWAAINAAgInBBubADaAQANAAgInBBubADaAQAAAA==.Demicha:BAAALAAECgYIBwAAAA==.Demonessia:BAAALAADCggICAAAAA==.',Di='Diamon:BAAALAAECgMIAwAAAA==.Dioni:BAAALAADCgcIBwAAAA==.Dirdam:BAAALAAECgYIBgAAAA==.Dizzy:BAAALAADCgcIBwAAAA==.',Do='Donutwarrior:BAAALAAECggIDgAAAA==.Donzi:BAAALAAECggIEAAAAA==.',Dr='Dracurion:BAAALAADCggIEAAAAA==.Dragosis:BAABLAAECoEmAAIEAAgImh6GDQC9AgAEAAgImh6GDQC9AgAAAA==.Drakkaroth:BAAALAAECgYIBgABLAAECggIKQAQADEjAA==.Draughen:BAAALAADCggIFgAAAA==.Draxari:BAAALAADCggICAAAAA==.Drekarth:BAAALAADCgYICwAAAA==.Drudoo:BAAALAADCggICAAAAA==.Drudu:BAABLAAECoEnAAQSAAgISxofHQBQAgASAAgISxofHQBQAgATAAYInggnHADjAAAUAAEITQaajAAwAAAAAA==.Drunkenfeet:BAAALAAECgYIBQAAAA==.',Du='Duskthorne:BAAALAADCgQIAwAAAA==.Dutchgeneral:BAAALAAECgYIBgAAAA==.',Dy='Dynglona:BAAALAAECgUIAQAAAA==.',['Dö']='Dödgrävarn:BAAALAAECgcIEQAAAA==.',Ea='Eamene:BAAALAADCgYIBgAAAA==.Eartenio:BAAALAADCgUIBQAAAA==.Earwigg:BAAALAADCggICQAAAA==.',Ei='Eiria:BAAALAADCgIIAgAAAA==.',El='Ellinarae:BAAALAADCggICAAAAA==.Elrathir:BAABLAAECoElAAINAAgIXxnEOABiAgANAAgIXxnEOABiAgAAAA==.Elsà:BAAALAADCgcIDAAAAA==.',Em='Emerick:BAABLAAECoEoAAINAAgITSRwDwAoAwANAAgITSRwDwAoAwAAAA==.',En='Enilea:BAAALAADCgYIBgAAAA==.Enory:BAAALAAECgIIAgAAAA==.',Eq='Equiliari:BAAALAAECgUIAQAAAA==.',Er='Eranaar:BAAALAADCggIDwAAAA==.Eraniir:BAAALAAECgYIDAAAAA==.',Ey='Eyesore:BAAALAADCgEIAQAAAA==.',Fa='Faclya:BAAALAAECgQICQAAAA==.Fannis:BAAALAAECgIIAgAAAA==.Fantast:BAAALAAECgYICwAAAA==.Fantazja:BAAALAADCgUIBQAAAA==.Favoxh:BAAALAAECgMIAwAAAA==.',Fe='Felkite:BAABLAAECoEnAAIVAAgIdiLOEgALAwAVAAgIdiLOEgALAwAAAA==.Feylari:BAAALAAECgYIDQAAAA==.Feythion:BAABLAAECoEeAAIQAAgILCGfBQD7AgAQAAgILCGfBQD7AgAAAA==.',Fi='Finnmag:BAABLAAECoEVAAIWAAcIIhNHdwB8AQAWAAcIIhNHdwB8AQABLAAFFAIIAwAOAAAAAA==.Fistrik:BAACLAAFFIEHAAIRAAMIdhndBQANAQARAAMIdhndBQANAQAsAAQKgSIAAhEACAhOJFwDACEDABEACAhOJFwDACEDAAAA.',Fr='Framan:BAAALAAECgYIDAABLAAECggIGwAJABkhAA==.Frankii:BAAALAAECgcICAAAAA==.Freyarose:BAAALAAECgMIBQAAAA==.Frima:BAABLAAECoEmAAICAAgINSERHwCjAgACAAgINSERHwCjAgAAAA==.Frunk:BAABLAAECoEbAAQJAAgIGSFlBACUAgAJAAcI8yFlBACUAgAXAAcIBxYPIwDOAQAIAAEINhmEyQBMAAAAAA==.',Ft='Ftgbztmr:BAABLAAFFIEGAAIIAAIIGRvgIwCiAAAIAAIIGRvgIwCiAAAAAA==.',Fy='Fyrirsát:BAAALAADCgYIBgAAAA==.',Ga='Gabbryx:BAAALAAECgEIAQAAAA==.Gaelisamar:BAAALAADCggICAAAAA==.',Gi='Giinjou:BAAALAAECgMIBgAAAA==.Gingernutter:BAAALAADCggIHwAAAA==.Gizzy:BAAALAAECgEIAQAAAA==.',Gl='Glitonea:BAAALAADCgEIAQAAAA==.Gloriette:BAABLAAECoEYAAMNAAgIyho5RAA/AgANAAgIxRo5RAA/AgAYAAcIhxYpHwC8AQAAAA==.Glödskägg:BAAALAAECggICAAAAA==.',Go='Gobbox:BAAALAADCggIDAAAAA==.',Gr='Greenpork:BAAALAAECgYICAAAAA==.Gruum:BAAALAAECgYIBgAAAA==.',Ha='Hacon:BAABLAAECoEVAAIUAAYI+BaBOACfAQAUAAYI+BaBOACfAQAAAA==.Halgir:BAABLAAECoEtAAINAAgIeB8QIwC9AgANAAgIeB8QIwC9AgAAAA==.Hammertime:BAAALAADCggICAAAAA==.Hangsocow:BAAALAAECgYIEAAAAA==.Hardtek:BAACLAAFFIEIAAQJAAIImw75AgCVAAAJAAII2Qz5AgCVAAAXAAEI1QYMJABJAAAIAAEI3QVdQQBDAAAsAAQKgRgABAkABgjmIOgKAOoBAAkABggaHOgKAOoBAAgAAwiMHaWVAP4AABcAAgiPG8pmAJwAAAAA.',He='Heathér:BAAALAAECgIIAgAAAA==.Helarn:BAAALAADCggICAAAAA==.',Hi='Hi:BAAALAADCgYIBgAAAA==.Hidedruid:BAABLAAECoEWAAIZAAgIviNGBgDeAgAZAAgIviNGBgDeAgABLAAFFAMIBgAEAHERAA==.Hideevoker:BAACLAAFFIEGAAIEAAMIcRFvCwDlAAAEAAMIcRFvCwDlAAAsAAQKgSAAAgQACAgMIKIIAP4CAAQACAgMIKIIAP4CAAAA.Hidemonk:BAAALAAECgYIBgABLAAFFAMIBgAEAHERAA==.Hillosilmä:BAAALAAECgYICwAAAA==.Hiyori:BAAALAADCgYIBwAAAA==.',Ho='Hoaqino:BAAALAADCggIDQAAAA==.Hokage:BAAALAAECggIDwAAAA==.Hoons:BAAALAAECgYICAAAAA==.Horntail:BAAALAAECgYIDAAAAA==.',Hu='Huai:BAABLAAECoEeAAMaAAgILxlQFgArAgAaAAgILxlQFgArAgAQAAgIYwzOHQBwAQAAAA==.Hueblo:BAABLAAECoEdAAIbAAcIXBwqIgA7AgAbAAcIXBwqIgA7AgAAAA==.Huntcore:BAAALAAECggIDgAAAA==.Huntess:BAAALAAECgYICwAAAA==.Hurjarja:BAAALAAECgEIAgAAAA==.Huror:BAABLAAECoEXAAINAAcIQBPDdADJAQANAAcIQBPDdADJAQAAAA==.',Hy='Hydrah:BAAALAAECgIIAgAAAA==.',['Hö']='Höder:BAAALAAECgYIEgAAAA==.',If='Ifalna:BAABLAAECoEgAAMUAAgI/xeQJwD7AQAUAAcIQRiQJwD7AQASAAgIIhDEPQCpAQAAAA==.',Ig='Igoroth:BAAALAADCggICAAAAA==.',Il='Ilireth:BAABLAAECoElAAIcAAgI7iDTBQDsAgAcAAgI7iDTBQDsAgAAAA==.Illadius:BAABLAAECoEgAAMcAAgIsh1oDwA3AgAVAAgIMhlaNQBZAgAcAAcIJBxoDwA3AgAAAA==.',In='Indran:BAAALAAECgUICQAAAA==.Ingà:BAAALAADCgIIAgAAAA==.',Ir='Irenna:BAAALAAECgIIBgAAAA==.',Is='Isabel:BAAALAAECgcIEQAAAA==.Ishtaris:BAAALAAECgIIAgAAAA==.',Iw='Iwanaga:BAAALAAFFAQIBAAAAA==.',Ji='Jinnia:BAAALAAECgYIDAAAAA==.Jizog:BAABLAAECoEnAAIcAAgIEx+7BwC8AgAcAAgIEx+7BwC8AgAAAA==.',Jo='Jon:BAAALAADCgMIAwAAAA==.Jou:BAAALAAECgYICwAAAA==.',Ka='Kalimba:BAAALAAECgMIBQAAAA==.Kalquan:BAAALAADCgcIFgAAAA==.Karasana:BAAALAAECgEIAQAAAA==.Katten:BAABLAAECoEUAAIZAAYISB1FEQAQAgAZAAYISB1FEQAQAgAAAA==.',Ke='Kerchak:BAAALAAECgcIBwAAAA==.',Kh='Khaya:BAAALAADCgYIBgAAAA==.',Ki='Kilana:BAAALAADCggICAABLAAECggIIAAHAMciAA==.Kiora:BAAALAADCggIHgABLAAECggIKQAQADEjAA==.Kirameow:BAAALAAECgMIBwAAAA==.',Kn='Kneeshooter:BAAALAAECgUIBgAAAA==.',Ko='Korenwolf:BAAALAADCggIFwAAAA==.Kostroma:BAAALAAECgYIEAAAAA==.',Kr='Kranosh:BAABLAAECoEgAAIHAAcI0htXJQBYAgAHAAcI0htXJQBYAgAAAA==.Krast:BAAALAAECgYIBgABLAAECgcIDAAOAAAAAA==.',Ky='Kyrena:BAAALAAECgYIDwAAAA==.Kyriea:BAAALAAECgcICgAAAA==.',La='Ladidruid:BAEALAADCggICAAAAA==.Laerbrithyre:BAABLAAECoEUAAIVAAYIpQ1QnABWAQAVAAYIpQ1QnABWAQAAAA==.Lampedampe:BAAALAAECgYICAABLAAECggIJAAWAPQcAA==.Lampedoo:BAABLAAECoEkAAMWAAgI9BxYLQB0AgAWAAgIvxpYLQB0AgAdAAYIcxbmOwBWAQAAAA==.Lampris:BAAALAADCggIEAAAAA==.Landuriel:BAAALAAECgYIBgAAAA==.Lanenaar:BAAALAAECgIIAgAAAA==.Lanthar:BAAALAAECgQIBAAAAA==.Laoganma:BAAALAADCgYIBgAAAA==.Lascap:BAAALAAECgcIDAAAAA==.Last:BAAALAADCgYIDwAAAA==.Latta:BAAALAAECggIDwAAAA==.',Le='Leikila:BAACLAAFFIEHAAIGAAMIegxcFgC/AAAGAAMIegxcFgC/AAAsAAQKgSwAAwYACAirF1IyAB8CAAYACAirF1IyAB8CAAcABAjUGlVnAEMBAAAA.',Li='Lightangel:BAAALAAECgUIAQAAAA==.Lightdealer:BAAALAADCggIDwAAAA==.Lightshope:BAAALAAECggIEgAAAA==.Lithi:BAAALAADCgYIBgAAAA==.Liung:BAAALAADCggIIAAAAA==.',Ll='Lloyyd:BAAALAAECgIIAgAAAA==.',Lo='Lockaio:BAAALAADCggIDwAAAA==.Looma:BAAALAADCggICAAAAA==.',Lu='Luxo:BAABLAAECoEaAAIGAAgIRhQ0SwDLAQAGAAgIRhQ0SwDLAQAAAA==.',['Là']='Làn:BAAALAAECgQIBgABLAAECgUIBQAOAAAAAA==.Lànn:BAAALAAECgEIAQAAAA==.',['Lá']='Lán:BAAALAAECgUIBQAAAA==.',['Læ']='Læknirinn:BAAALAAECggIEQAAAA==.',Ma='Mattma:BAAALAADCgYIBgAAAA==.Maximilian:BAAALAADCggICAAAAA==.',Me='Meara:BAAALAAECgEIAQAAAA==.Megastab:BAABLAAECoEpAAIBAAgIghsHEgB+AgABAAgIghsHEgB+AgAAAA==.Memebeam:BAEALAAECgYIBgABLAAECggIBwAOAAAAAA==.Meodi:BAEALAADCgcIDAABLAADCggICAAOAAAAAA==.Merkula:BAAALAAECgYIEwAAAA==.',Mi='Micarta:BAAALAAECgIIAgAAAA==.Mileeria:BAACLAAFFIEKAAIeAAMIGhOXDQDmAAAeAAMIGhOXDQDmAAAsAAQKgS0AAh4ACAhTI4UKABEDAB4ACAhTI4UKABEDAAAA.Minorkinhah:BAAALAAECgYICAAAAA==.Mirdad:BAAALAADCgQIBAAAAA==.',Mo='Mokraw:BAAALAADCggICAAAAA==.Morc:BAAALAAECggIBgABLAAFFAYICQAXABEbAA==.Mortiné:BAAALAADCggIDgAAAA==.Moxxira:BAABLAAECoEeAAICAAgIyBnCQQAPAgACAAgIyBnCQQAPAgAAAA==.',Mu='Mullered:BAAALAAECgMIAwAAAA==.Mumraa:BAAALAAECgYICwAAAA==.',My='Mymer:BAAALAAECgcIDAAAAA==.Mythragora:BAAALAAECgYIBwAAAA==.',Na='Nadriel:BAAALAADCgcICQAAAA==.Naksam:BAAALAADCggICwAAAA==.Nakula:BAAALAADCggICAAAAA==.Nalá:BAAALAADCggIDwAAAA==.Nava:BAAALAADCgUIBQAAAA==.',Ne='Nemiria:BAAALAAECgUICQAAAA==.Neomimad:BAAALAAECgQICgAAAA==.Nevagosa:BAABLAAECoEZAAMEAAgICgsmKwCfAQAEAAgICgsmKwCfAQAfAAMIIAODEgB3AAAAAA==.',Ni='Nikkori:BAAALAADCggICAAAAA==.Ninehell:BAAALAADCggICAAAAA==.Niriya:BAAALAAECgUIBwAAAA==.Nitro:BAABLAAECoEdAAIYAAgIaB32DQBtAgAYAAgIaB32DQBtAgAAAA==.',No='Noselingwa:BAAALAADCgMIBgAAAA==.Novakk:BAABLAAECoEVAAMIAAgIERLyRgDnAQAIAAgIXxDyRgDnAQAJAAYIdwnBFQBEAQAAAA==.',Nu='Nuubxie:BAACLAAFFIEGAAIDAAII6iR4EwDKAAADAAII6iR4EwDKAAAsAAQKgSYAAgMACAjNJRsEAGkDAAMACAjNJRsEAGkDAAAA.',Ny='Nyarlathotep:BAAALAAECgEIAQAAAA==.Nyvi:BAAALAADCggIDgAAAA==.Nyxii:BAAALAAECgQIBAAAAA==.',Nz='Nzk:BAAALAAECgEIAgAAAA==.',['Ní']='Níghtshayde:BAAALAADCggICAAAAA==.',Ob='Obeka:BAAALAAECgYIBgABLAAECggIKQAQADEjAA==.',Od='Oditts:BAAALAAECgMIBQAAAA==.',Ok='Okkie:BAAALAAECgYIDgAAAA==.',Oo='Oosterveld:BAAALAAECgIIAgABLAAECggIHgAQACwhAA==.',Or='Orenem:BAAALAAECgUIAwAAAA==.',Ou='Outie:BAAALAAECgIIAgAAAA==.Outlander:BAAALAAECgYICwAAAA==.',Pa='Palooz:BAAALAADCgMIAwAAAA==.',Pd='Pdwebslinger:BAACLAAFFIEGAAMNAAIIEgOwOwB+AAANAAIIEgOwOwB+AAAYAAIIAQLdFABSAAAsAAQKgSkAAw0ACAgPEmJvANQBAA0ACAi7DmJvANQBABgABwgmESkkAJIBAAAA.',Pe='Peggster:BAAALAAECgcIBwAAAA==.Perkele:BAABLAAECoEgAAIIAAgI0SL8DgATAwAIAAgI0SL8DgATAwAAAA==.',Ph='Phoebè:BAAALAADCgYIBgAAAA==.',Pi='Pickerin:BAABLAAECoEXAAMXAAgIiBlXDwBnAgAXAAgIiBlXDwBnAgAIAAEI3Qe52AAtAAAAAA==.Pico:BAAALAAECgIIAgAAAA==.',Pl='Pleochroic:BAAALAAECgYIBgAAAA==.',Po='Poet:BAAALAADCggIEwAAAA==.Potatofamer:BAAALAAFFAIIAgAAAA==.Potatoshamer:BAAALAADCgcIBwAAAA==.',Pr='Preeppe:BAAALAADCggICwAAAA==.Projacartel:BAAALAAECgIIAgABLAAECggIHQAYAGgdAA==.Prðteus:BAAALAADCgYIBgAAAA==.',Pu='Puckaio:BAAALAADCggICwAAAA==.',Qy='Qyo:BAAALAADCgcIBwAAAA==.',Ra='Rakarath:BAAALAAECgYIDAAAAA==.Rakoul:BAAALAADCggICAAAAA==.Razatt:BAABLAAECoEeAAMgAAgIzRuXFwCQAgAgAAgIzRuXFwCQAgAhAAEIvxMPMAA3AAAAAA==.',Re='Redflower:BAAALAADCggICAAAAA==.Redkiygost:BAAALAAECgQICAAAAA==.',Ri='Rigamitis:BAAALAAECgEIAgAAAA==.',Ro='Roasties:BAAALAAECgYIBgAAAA==.Rocha:BAAALAADCggICAAAAA==.Roxanne:BAAALAAECgIIBAAAAA==.Roxywolf:BAAALAADCgUIBQAAAA==.',Ry='Ryaio:BAAALAAECggIDQAAAA==.Ryvita:BAAALAADCgYIBgABLAAFFAIIBgADAOokAA==.',Sa='Sanniya:BAABLAAECoEdAAITAAcIIBxPCAAvAgATAAcIIBxPCAAvAgAAAA==.Saryssa:BAAALAAECggICAAAAA==.Saturos:BAAALAADCgEIAQAAAA==.',Sc='Scalerik:BAAALAAECgcIEQABLAAFFAMIBwARAHYZAA==.Schnoofas:BAAALAADCgEIAQABLAAFFAIIAgAOAAAAAA==.',Se='Seagaard:BAACLAAFFIEGAAIGAAIIuhecJQCOAAAGAAIIuhecJQCOAAAsAAQKgSEAAgYACAhcI6IGABsDAAYACAhcI6IGABsDAAAA.Seril:BAABLAAECoEbAAIBAAcIow8SKQDAAQABAAcIow8SKQDAAQAAAA==.Sevensad:BAAALAAECgMIAwAAAA==.',Sh='Shadowweaver:BAAALAADCgYIBgAAAA==.Shaikki:BAAALAAECggIEgAAAA==.Shanden:BAABLAAECoEdAAIVAAgIsh8WHADTAgAVAAgIsh8WHADTAgAAAA==.Sheshe:BAAALAADCgUIBQAAAA==.Shonin:BAABLAAECoEgAAINAAgIrQ5zdADJAQANAAgIrQ5zdADJAQAAAA==.Shímsham:BAAALAADCgYIBgAAAA==.',Si='Sigríd:BAAALAAECgIIAgAAAA==.Silveatia:BAAALAADCgQIBAABLAAECgcIEQAOAAAAAA==.',Sk='Skullrend:BAAALAADCggICAAAAA==.',Sl='Slakt:BAABLAAECoEgAAIDAAgInwr4WwCZAQADAAgInwr4WwCZAQAAAA==.Slavsquat:BAAALAADCggICAAAAA==.',Sn='Snipezz:BAAALAAECggIDgAAAA==.Snuffey:BAAALAAECgYICwAAAA==.',So='Soriel:BAABLAAECoEgAAIeAAgI1RnGHABpAgAeAAgI1RnGHABpAgAAAA==.Sorrell:BAAALAADCgMIAwAAAA==.',Sp='Spiriditus:BAAALAAECgMIAwABLAAFFAUIDAAfAJwWAA==.Spiridragon:BAACLAAFFIEMAAMfAAUInBY5AgBVAQAfAAQIehY5AgBVAQAEAAMIZxUxCwDpAAAsAAQKgS4AAx8ACAhSIT8BABMDAB8ACAgiIT8BABMDAAQACAghHPQVAFoCAAAA.Spiridymonk:BAAALAADCggICAABLAAFFAUIDAAfAJwWAA==.',Su='Sudaki:BAABLAAECoEWAAIXAAcIFRjmGQAJAgAXAAcIFRjmGQAJAgAAAA==.Sunglassdog:BAAALAADCgcIBwAAAA==.Sunnyside:BAAALAAECgcIDAAAAA==.',Sv='Svinpäls:BAABLAAECoEaAAINAAgIPBd2QgBEAgANAAgIPBd2QgBEAgAAAA==.',Sw='Sweeny:BAAALAADCggIFwAAAA==.',Sy='Syri:BAAALAAECgQIBwAAAA==.',['Sé']='Séphíróth:BAAALAAECgcIEAAAAA==.',Ta='Tahiri:BAABLAAECoEgAAIRAAgIQRhODwBGAgARAAgIQRhODwBGAgAAAA==.Tauler:BAAALAAFFAIIAgAAAA==.Taundris:BAAALAAECgUIAQAAAA==.Taurenus:BAAALAADCgYICgAAAA==.',Te='Teles:BAAALAADCgUIBQAAAA==.Teýla:BAAALAADCggICAAAAA==.',Th='Thechewerz:BAACLAAFFIEOAAILAAUIQxoWCACwAQALAAUIQxoWCACwAQAsAAQKgSUAAgsACAjsH9sbAOACAAsACAjsH9sbAOACAAAA.Thermidor:BAABLAAECoElAAIPAAgIziJABgAaAwAPAAgIziJABgAaAwAAAA==.Thoomrah:BAAALAAECgcIEQAAAA==.Thritraksh:BAAALAADCggICAAAAA==.Thurid:BAABLAAECoEYAAIIAAcIZCBAKAByAgAIAAcIZCBAKAByAgAAAA==.',Ti='Tiindra:BAAALAAECggIEQAAAA==.Tiurri:BAABLAAECoEaAAIgAAgIDw1lQACrAQAgAAgIDw1lQACrAQAAAA==.',To='Toasties:BAAALAAECgMIAwAAAA==.Toffeetapper:BAAALAADCgQIBgAAAA==.Tonant:BAAALAADCgYIEwAAAA==.Torgar:BAABLAAECoEjAAMIAAgIChEsRwDmAQAIAAgIbA8sRwDmAQAXAAMIUArgZACkAAAAAA==.Tourar:BAABLAAECoEmAAIbAAgIqx6VEwCxAgAbAAgIqx6VEwCxAgAAAA==.',Tr='Treguard:BAABLAAECoEVAAMLAAgIahmPNwBsAgALAAgIahmPNwBsAgAiAAYILxKXJQBxAQAAAA==.Treja:BAAALAAECgIIAgAAAA==.Trinkets:BAABLAAECoEfAAMCAAgI7xwRMQBNAgACAAgI7xwRMQBNAgAbAAEI7ROgpgA6AAAAAA==.Trubulox:BAABLAAECoEXAAINAAcIiw/0hwCjAQANAAcIiw/0hwCjAQAAAA==.Trä:BAABLAAECoEUAAISAAYI9As/bAAHAQASAAYI9As/bAAHAQAAAA==.',Tu='Tuhmamuumuu:BAAALAAECgMIBQAAAA==.Turboslug:BAAALAADCgEIAQABLAAECgMIBQAOAAAAAA==.Turkéy:BAAALAAECgYICQAAAA==.',Ul='Uliade:BAABLAAECoEUAAIjAAYIfAjIQgAKAQAjAAYIfAjIQgAKAQAAAA==.',Un='Undinna:BAAALAAECgIIAgAAAA==.',Ur='Ursla:BAAALAAECgYICgAAAA==.',Va='Valarie:BAAALAAECggIDwAAAA==.Valouri:BAABLAAECoEhAAMRAAgIQh9PBwDTAgARAAgIQh9PBwDTAgAaAAMI3wcyTQBpAAAAAA==.',Ve='Velorna:BAAALAADCggICwAAAA==.Verard:BAAALAADCgcIBwABLAADCggIDgAOAAAAAA==.Vesicular:BAABLAAECoEcAAIbAAgI3SBcDADzAgAbAAgI3SBcDADzAgAAAA==.',Vh='Vhazhreal:BAAALAADCgEIAQAAAA==.',Vi='Viktor:BAAALAADCggICQAAAA==.Vince:BAABLAAECoEeAAQbAAgIVxiqMQDcAQAbAAcIdheqMQDcAQACAAYIEw9pkgBLAQAkAAEINBFdHQBKAAAAAA==.',Vo='Voiddancer:BAAALAADCgQIBAAAAA==.Voodude:BAAALAAECgYICgAAAA==.Vordar:BAAALAADCggICAAAAA==.',['Væ']='Væv:BAAALAADCgcICwAAAA==.',Wa='Waggoner:BAACLAAFFIEIAAMlAAMI4QtOBwDeAAAlAAMI4QtOBwDeAAABAAEIRgzfGwBNAAAsAAQKgRsABCUACAhpFI8RAPQBACUABwhOFo8RAPQBAAEACAjQBqMxAIwBACYAAQi5E2gZAEEAAAAA.Walko:BAAALAAECgUIAQAAAA==.',We='Webslingerz:BAAALAAECgYICAABLAAFFAIIBgANABIDAA==.',Wi='Wildboi:BAABLAAECoEhAAIGAAgIRxC0YQCMAQAGAAgIRxC0YQCMAQAAAA==.Wildghosts:BAAALAADCggIDQAAAA==.',Wo='Wor:BAAALAAECgIIAgAAAA==.',Wr='Wrighty:BAAALAAECgYIDgAAAA==.',Wu='Wundo:BAAALAAECgIIBAAAAA==.',Xa='Xari:BAAALAAECgcIDgAAAA==.',Xe='Xenrie:BAAALAAECgYIDwAAAA==.Xerxes:BAAALAADCgUIBgAAAA==.',Xi='Xinzy:BAABLAAECoEaAAMRAAcI0QzoKQAVAQARAAYIPgzoKQAVAQAaAAQIagXbRgCYAAAAAA==.Xiuwei:BAABLAAECoEYAAIQAAcIjAXAKgDyAAAQAAcIjAXAKgDyAAAAAA==.',Xr='Xreinak:BAAALAADCgcIAQAAAA==.',Xu='Xueyang:BAAALAADCgUIBQAAAA==.',Xy='Xyrath:BAAALAADCgYIBgABLAADCggIDgAOAAAAAA==.',Yu='Yumo:BAABLAAECoEfAAINAAcIeBsFUwAVAgANAAcIeBsFUwAVAgAAAA==.',Za='Zaithrizeth:BAAALAADCgEIAQAAAA==.Zalazan:BAAALAAECgMIBQAAAA==.Zaté:BAAALAADCgcIBwABLAAECggIHgAQACwhAA==.',Ze='Zenee:BAABLAAECoEbAAIaAAgIvxUcFwAiAgAaAAgIvxUcFwAiAgAAAA==.',Zi='Zielonyork:BAAALAAECgYIBgAAAA==.',Zo='Zorgrom:BAABLAAECoEgAAIjAAgIiyJDBAALAwAjAAgIiyJDBAALAwAAAA==.',Zy='Zynix:BAAALAADCggICAABLAAECggIHgAQACwhAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end