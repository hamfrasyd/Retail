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
 local lookup = {'Warrior-Fury','Mage-Arcane','Monk-Windwalker','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Paladin-Retribution','Warlock-Destruction','Hunter-Marksmanship','Rogue-Outlaw','Paladin-Holy','Mage-Frost','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Unholy','Unknown-Unknown','Druid-Feral','Rogue-Assassination','Rogue-Subtlety','Druid-Guardian','DemonHunter-Vengeance','Paladin-Protection','Druid-Restoration','Druid-Balance','DeathKnight-Blood','Priest-Holy','Shaman-Elemental','Warlock-Affliction','Hunter-BeastMastery','Monk-Brewmaster','Priest-Shadow','Warlock-Demonology','Warrior-Protection','Shaman-Enhancement',}; local provider = {region='EU',realm='TheVentureCo',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ad='Adeela:BAAALAAECgEIAQAAAA==.Adeon:BAAALAADCgQIBAAAAA==.',Ah='Ahota:BAAALAADCgcIBQAAAA==.',Ai='Aiinee:BAAALAAECgYIBgABLAAFFAQIDAABAFoeAA==.',Al='Alferian:BAAALAADCggIDgAAAA==.Althan:BAAALAADCggICAAAAA==.Alunys:BAAALAADCgEIAQAAAA==.Alyssà:BAAALAAECgQIBAABLAAFFAMICAACAAMZAA==.',Ap='Apo:BAAALAADCggIDgAAAA==.Apodiction:BAAALAADCggIDwAAAA==.Apogeum:BAAALAADCggIFQAAAA==.',Ar='Arduli:BAABLAAECoEdAAIDAAcIFBSxIwCtAQADAAcIFBSxIwCtAQAAAA==.Arevia:BAAALAADCgQIBAAAAA==.Arexana:BAAALAAECgEIAQAAAA==.Arexelie:BAAALAAECgYIBgAAAA==.',At='Athelin:BAAALAAECggIDgAAAA==.Atixez:BAABLAAECoEgAAIEAAgIShzDGwCGAgAEAAgIShzDGwCGAgAAAA==.',Aw='Awen:BAAALAADCggIEwAAAA==.',Az='Azuryl:BAABLAAECoEgAAMFAAgIhRfEBABEAgAFAAgIhRfEBABEAgAGAAUIMBnhGQBvAQAAAA==.',Be='Bearboy:BAAALAADCgYIBgAAAA==.Beaver:BAAALAADCggICAAAAA==.Beefyfather:BAACLAAFFIEFAAIHAAIIJxhjIgCpAAAHAAIIJxhjIgCpAAAsAAQKgScAAgcACAjvHrUgAMwCAAcACAjvHrUgAMwCAAAA.Beefymm:BAAALAAECgIIAgAAAA==.Beefytrans:BAAALAAECgUIBQAAAA==.',Bo='Bobbyross:BAAALAAECgYICQAAAA==.Bolti:BAAALAADCggICAAAAA==.Boltwyn:BAABLAAECoEeAAIIAAcIhhYeSwDbAQAIAAcIhhYeSwDbAQAAAA==.Bonkie:BAAALAADCggICAAAAA==.',Br='Branulfr:BAABLAAECoEbAAIJAAcI5xQ+PACrAQAJAAcI5xQ+PACrAQAAAA==.Bròx:BAAALAAECgcIBwAAAA==.',Bu='Burbie:BAAALAADCggICAAAAA==.',Ca='Calyssa:BAABLAAECoEgAAIKAAgIrxwuAwC2AgAKAAgIrxwuAwC2AgAAAA==.Caps:BAABLAAECoEUAAMLAAcIhRx7HQD1AQALAAYIlhx7HQD1AQAHAAcIbhL7igChAQAAAA==.Carcia:BAABLAAECoEcAAIMAAgILCKIBgAVAwAMAAgILCKIBgAVAwAAAA==.',Ch='Charleena:BAABLAAECoEaAAINAAgIRAtRKAC1AQANAAgIRAtRKAC1AQAAAA==.Charízard:BAAALAADCgYIBwAAAA==.Chunder:BAABLAAECoEiAAILAAgImBP1HAD5AQALAAgImBP1HAD5AQAAAA==.',Co='Correm:BAACLAAFFIERAAMOAAYIPibKAACvAgAOAAYIPibKAACvAgAPAAMINRffBAAKAQAsAAQKgRwAAw4ACAglJmkDAHIDAA4ACAglJmkDAHIDAA8AAQjqIaJNAE8AAAAA.Corvin:BAAALAADCgUIBQABLAADCgcIBwAQAAAAAA==.',Cy='Cydane:BAACLAAFFIEHAAIRAAMIBBfmAwAKAQARAAMIBBfmAwAKAQAsAAQKgS4AAhEACAh7Iu4DABsDABEACAh7Iu4DABsDAAAA.',Da='Daggerin:BAABLAAECoEYAAMSAAgI2R8OEQCLAgASAAYIByUOEQCLAgATAAgINhLrEQDzAQAAAA==.Daimx:BAAALAADCggICAAAAA==.Danath:BAAALAADCgYIBgABLAAECgYIFQAUAIEZAA==.',De='Deathshot:BAAALAAECgYICAAAAA==.Demonade:BAABLAAECoEXAAIVAAcI/Q9kKAA2AQAVAAcI/Q9kKAA2AQAAAA==.Devistofeles:BAAALAAECgEIAQAAAA==.',Dh='Dhorrem:BAAALAADCgEIAQABLAAFFAYIEQAOAD4mAA==.Dhremix:BAAALAADCggICAAAAA==.',Do='Doeden:BAAALAADCgYIBgABLAAECgYICQAQAAAAAA==.Dorgin:BAABLAAECoEjAAIWAAgItx/7CQCtAgAWAAgItx/7CQCtAgAAAA==.',Dr='Drackie:BAAALAAECggICgAAAA==.Draculesti:BAABLAAFFIEFAAIVAAMIxAhjBwCcAAAVAAMIxAhjBwCcAAAAAA==.Dradragongon:BAAALAAFFAIIBAABLAAFFAQIDAABAFoeAA==.Druumz:BAAALAADCggICAABLAAECggICAAQAAAAAA==.',Ed='Edera:BAAALAAECgEIAQAAAA==.',El='Eluinae:BAAALAAECgcIBwAAAA==.',Et='Etheréal:BAABLAAECoEUAAISAAcIIQ7+LACoAQASAAcIIQ7+LACoAQAAAA==.',Ev='Evilkilli:BAAALAAECgUIBQAAAA==.',Fa='Fatale:BAAALAAECgEIAQAAAA==.',Fe='Fellandria:BAAALAAECggIDQAAAA==.',Fi='Firbol:BAAALAADCgcIBwAAAA==.Firehorn:BAAALAAECgcIEAAAAA==.Fizzlesmash:BAAALAADCgcIBwAAAA==.',Fo='Foxvulder:BAAALAAECgcIEwAAAA==.',Fr='Frigg:BAAALAADCgcIBwAAAA==.Froboz:BAAALAAECgEIAQAAAA==.Froggy:BAABLAAECoElAAMXAAgIWSKxCAD9AgAXAAgIWSKxCAD9AgAYAAQIdw4ZYwDhAAAAAA==.Frydo:BAAALAAECgMIAwAAAA==.',Fu='Fuzzy:BAAALAAECgYICwAAAA==.',Ga='Gakuya:BAABLAAECoEkAAMPAAgImiE0CgCaAgAPAAgINxw0CgCaAgAZAAgIYR/iCgB5AgAAAA==.Galian:BAAALAADCggICAAAAA==.',Ge='Gemet:BAABLAAECoEbAAIZAAcIYxIDGACfAQAZAAcIYxIDGACfAQAAAA==.',Gh='Ghor:BAAALAAECgcIEAAAAA==.',Gn='Gnaesus:BAAALAAECgIIAgAAAA==.',Gr='Gregorious:BAABLAAECoEfAAIXAAgIFhWTLgD0AQAXAAgIFhWTLgD0AQAAAA==.Gruk:BAAALAADCggICAAAAA==.',Ha='Hades:BAAALAADCgIIAgAAAA==.Hammertime:BAAALAADCgYIBwAAAA==.Harrow:BAAALAADCgYIBgAAAA==.',He='Hedwig:BAAALAAECgMIAwABLAAECggIFgACAA4eAA==.Heldia:BAAALAAECgMIAwAAAA==.Helux:BAAALAADCggIDgAAAA==.Herbart:BAAALAAECgUIAQAAAA==.',Ho='Hodgedog:BAAALAADCgcIBwAAAA==.',Io='Iolaana:BAACLAAFFIELAAIEAAMIQg09GQC4AAAEAAMIQg09GQC4AAAsAAQKgRkAAgQACAhaEpBaAKMBAAQACAhaEpBaAKMBAAAA.Ioli:BAAALAAECgYIDAAAAA==.',Ir='Irzi:BAABLAAECoEaAAIaAAcIIhfqNADkAQAaAAcIIhfqNADkAQAAAA==.',Is='Islo:BAABLAAECoEbAAMbAAgIHxd4JQBbAgAbAAgIHxd4JQBbAgAEAAgI0BCbWACpAQAAAA==.',Ja='Jamie:BAAALAADCggICgAAAA==.Jampo:BAAALAAECggICAAAAA==.Jayee:BAACLAAFFIEPAAIIAAYIohrTAwBIAgAIAAYIohrTAwBIAgAsAAQKgSwAAwgACAhFJsYBAIQDAAgACAhFJsYBAIQDABwABgg6GY8NAL4BAAAA.',Ju='Juicy:BAAALAAECgYICwAAAA==.Justinio:BAAALAADCgUIBQAAAA==.',Ka='Kaeira:BAAALAAECgcIEQAAAA==.Kalastura:BAABLAAECoEYAAIBAAcIlxJIVQCyAQABAAcIlxJIVQCyAQAAAA==.Kanna:BAAALAADCgcIBwAAAA==.Kareeva:BAAALAADCgYIBgAAAA==.',Ke='Kenbro:BAAALAADCgUIBQAAAA==.',Kh='Khal:BAAALAAECgQIBAAAAA==.Kheydar:BAABLAAECoERAAMJAAcIFBb1MwDSAQAJAAcIFBb1MwDSAQAdAAMIhw4Q6gB+AAAAAA==.',Ki='Kildok:BAAALAADCgQIBwAAAA==.',Kj='Kjiiljgk:BAAALAADCgMIAwAAAA==.',Kr='Kristain:BAAALAADCgcIBwAAAA==.',La='Ladih:BAAALAAECgIIAgAAAA==.',Le='Lemao:BAAALAAECgQICQAAAA==.Leroux:BAAALAADCggICAAAAA==.Lewtoo:BAAALAAECgYICgAAAA==.',Li='Lisanalgaib:BAAALAAECgYIBgAAAA==.',Lo='Lorkan:BAAALAAECgEIAQAAAA==.',['Lú']='Lúne:BAAALAAECgcIEAAAAA==.',Ma='Magyna:BAAALAADCggIGAAAAA==.Magynga:BAABLAAECoEfAAIdAAgImREnVwDWAQAdAAgImREnVwDWAQAAAA==.Magynka:BAAALAAECgYICwAAAA==.Malo:BAABLAAECoEpAAIeAAgIYx6/CAC2AgAeAAgIYx6/CAC2AgAAAA==.Mandymandy:BAAALAAECgIIAQAAAA==.Marwol:BAABLAAECoEiAAMfAAgIJB3GIQBEAgAfAAcI/BvGIQBEAgAaAAEIKyGYlQBhAAAAAA==.',Mc='Mcdougle:BAAALAAECgcIDQAAAA==.',Me='Meffisto:BAACLAAFFIEOAAIXAAUIsBjoAwCuAQAXAAUIsBjoAwCuAQAsAAQKgRgAAhcACAifI3MKAOsCABcACAifI3MKAOsCAAAA.Merra:BAAALAAECgIIAgAAAA==.',Mi='Mikafergusar:BAAALAADCgEIAQAAAA==.Mim:BAAALAADCgYIBgAAAA==.Missdoxy:BAAALAAECgcIEwAAAA==.',Na='Naproxin:BAAALAADCgcIBwAAAA==.Nayasin:BAABLAAECoEUAAIYAAcIuhiiKAD3AQAYAAcIuhiiKAD3AQAAAA==.',Ne='Neida:BAABLAAECoEaAAIEAAcIDhIMbAB0AQAEAAcIDhIMbAB0AQAAAA==.Newt:BAAALAADCgYIBgAAAA==.',Ni='Nidda:BAAALAADCgcICgAAAA==.Nirron:BAAALAADCgcIBwAAAA==.',No='Nofun:BAAALAAECgUIBwAAAA==.',Nu='Nuggìe:BAABLAAECoEaAAIcAAcIKBbXCQABAgAcAAcIKBbXCQABAgAAAA==.Numlock:BAAALAADCgIIAgAAAA==.',Ny='Nymar:BAAALAADCggICAAAAA==.',['Nô']='Nôbeard:BAABLAAECoEgAAIVAAgIvyA2BgDmAgAVAAgIvyA2BgDmAgAAAA==.',Ob='Obegriplig:BAAALAAECgcIBwAAAA==.',On='Ontora:BAAALAADCggIGgAAAA==.',['Oî']='Oîc:BAAALAADCgMIAwAAAA==.',Pa='Palman:BAAALAADCggICQAAAA==.',Pe='Pelenise:BAAALAADCggIHQAAAA==.Petting:BAAALAADCggIEgAAAA==.',Pi='Pillaren:BAAALAAECgcIBwABLAAECggIIAAVAJINAA==.',Ql='Qlix:BAAALAADCgUIBgAAAA==.',Ra='Radyra:BAAALAADCggICAAAAA==.Raynon:BAAALAADCgMIAwABLAAECgEIAQAQAAAAAA==.',Re='Redemption:BAAALAADCgYIBgAAAA==.Remba:BAAALAAECgYIBgAAAA==.Retribution:BAAALAADCggICwAAAA==.',Ru='Ruffybad:BAAALAADCggICAABLAAFFAUICwALANQNAA==.',['Rá']='Ráccóón:BAAALAAECgUICwAAAA==.',Sa='Saephynea:BAAALAAECgMIAwABLAAECgcIGgALAP8VAA==.Sagahrefna:BAABLAAECoEaAAIfAAcIfwxjQwCFAQAfAAcIfwxjQwCFAQAAAA==.Saiyan:BAAALAADCggICAAAAA==.Sammaani:BAAALAAECgQICQAAAA==.Sashelle:BAABLAAECoEeAAIfAAgI9AYCTwBRAQAfAAgI9AYCTwBRAQAAAA==.Saudade:BAAALAAFFAIIAgAAAA==.',Sc='Scriv:BAAALAAECgQIBAAAAA==.',Se='Selenne:BAAALAAECgYIEAABLAAFFAUICwALAC4SAA==.Sengíra:BAABLAAECoEYAAIfAAgIURQPJgAlAgAfAAgIURQPJgAlAgAAAA==.',Sh='Shailangor:BAABLAAECoEeAAIgAAcIghzqEgBGAgAgAAcIghzqEgBGAgAAAA==.Shamiac:BAAALAADCgcIDQAAAA==.Shamoak:BAAALAAFFAEIAQAAAA==.Shipstress:BAAALAAECgYIDwAAAA==.Shorrem:BAAALAAECgEIAQABLAAFFAYIEQAOAD4mAA==.',Si='Sidiousa:BAAALAADCgIIAgAAAA==.Simuzz:BAABLAAECoEaAAICAAgITw0GXADLAQACAAgITw0GXADLAQAAAA==.Sinni:BAAALAADCgIIAgAAAA==.Sinon:BAACLAAFFIEJAAIYAAIIoCMIDQDEAAAYAAIIoCMIDQDEAAAsAAQKgSEAAhgACAg8JBwHADEDABgACAg8JBwHADEDAAAA.',Sl='Slayerdin:BAABLAAECoElAAIHAAgIQBbNSwAsAgAHAAgIQBbNSwAsAgAAAA==.Slayetr:BAAALAAECgYIAwAAAA==.',Sn='Snowprincess:BAAALAAECgQIBgABLAAECgYIDQAQAAAAAA==.',So='Sodomar:BAAALAAECgIIAwAAAA==.Soultorixs:BAAALAAECgcIAwAAAA==.',Sp='Spectro:BAAALAADCggIDAAAAA==.',St='Stoned:BAAALAAECgMIAwAAAA==.Strangulate:BAAALAAECgIIBAAAAA==.',Su='Sumec:BAABLAAECoEwAAIYAAgI2yKeBwAqAwAYAAgI2yKeBwAqAwAAAA==.',Sv='Svokra:BAAALAADCggICAABLAAECgcIBwAQAAAAAA==.',Sy='Sylarisse:BAAALAAECgYIBgABLAAECggIIAAhADElAA==.Sylvatica:BAABLAAECoEWAAIdAAcIZRKmcgCTAQAdAAcIZRKmcgCTAQAAAA==.',Ta='Tagoun:BAAALAAECgQIBAAAAA==.Takara:BAAALAADCggICAAAAA==.Taku:BAABLAAECoEYAAIiAAgIrhC+DAD3AQAiAAgIrhC+DAD3AQAAAA==.Tali:BAAALAADCgQIBAAAAA==.Taliore:BAAALAADCggICAAAAA==.Talirea:BAAALAAECgcIEAABLAAFFAMIDgAHAPcaAA==.Taliri:BAACLAAFFIEOAAIHAAMI9xprDQADAQAHAAMI9xprDQADAQAsAAQKgRkAAgcABwgnIwc1AHMCAAcABwgnIwc1AHMCAAAA.',Te='Telsa:BAABLAAECoEgAAIVAAgIkg2KIwBbAQAVAAgIkg2KIwBbAQAAAA==.Tevari:BAAALAADCggIEAAAAA==.',Th='Thokmar:BAAALAAECgMIAwAAAA==.',Ti='Tirani:BAACLAAFFIEHAAIfAAMIywZJEQC2AAAfAAMIywZJEQC2AAAsAAQKgS4AAh8ACAiQGUkeAF8CAB8ACAiQGUkeAF8CAAAA.Tiwani:BAAALAADCggICAAAAA==.',Tr='Treewarden:BAAALAADCggICAAAAA==.Tricksie:BAAALAAECgUIBwABLAAECgcIBwAQAAAAAA==.',Ty='Tyaltir:BAAALAADCgUIBQABLAAECgcIEwAQAAAAAA==.Tyaltis:BAAALAAECgcIEwAAAA==.Tyraelon:BAAALAADCgYIBgAAAA==.',['Tß']='Tßc:BAAALAAECgIIAgAAAA==.',['Tö']='Tösen:BAAALAAECgYICQAAAA==.',Ul='Ulya:BAABLAAECoEaAAIEAAcIMRXZVwCrAQAEAAcIMRXZVwCrAQAAAA==.',Ur='Ursakta:BAABLAAECoEZAAIfAAgIWxB5MwDWAQAfAAgIWxB5MwDWAQAAAA==.',Va='Valker:BAACLAAFFIEHAAMdAAMIWib7CQBXAQAdAAMIWib7CQBXAQAJAAII3hesGQCOAAAsAAQKgSwAAwkACAgbJWQHACUDAAkACAjRI2QHACUDAB0ABwjhIuogAJ0CAAAA.',Ve='Verinäz:BAAALAAECgEIAQAAAA==.Vesuvia:BAAALAADCggIFQAAAA==.',Vi='Vibranium:BAAALAAECgUICgABLAAFFAMIBwAdAFomAA==.',Vo='Volteri:BAAALAAECgcIBwAAAA==.',Wa='Warship:BAAALAADCgIIAgAAAA==.Wayo:BAAALAAECgUIBQAAAA==.',We='Weiwei:BAAALAAECgIIAgAAAA==.',Wh='Wheez:BAAALAAECgIIAgAAAA==.Whinestein:BAAALAAECgYICQAAAA==.',Wi='Wicboi:BAAALAAECgYICgABLAAECgYICgAQAAAAAA==.Wicclock:BAAALAAECgYICgABLAAECgYICgAQAAAAAA==.Wiccyvoker:BAAALAAECgYICgAAAA==.Wicded:BAAALAAECgYICwAAAA==.Wizia:BAABLAAECoEYAAIaAAgIKg1wQgClAQAaAAgIKg1wQgClAQAAAA==.',Wo='Wolfekey:BAABLAAECoEgAAMJAAgIViOhBQA3AwAJAAgIViOhBQA3AwAdAAEItAb4GQEiAAAAAA==.',Xa='Xarotha:BAAALAADCgcIBwAAAA==.',Xu='Xuelin:BAAALAAECgcIDgAAAA==.',Yg='Yggdrasíl:BAAALAAECggICAAAAA==.',Yi='Yi:BAAALAAFFAIIAgABLAAFFAYIDAACAE0XAA==.',Yu='Yulineacctwo:BAAALAADCgIIAgAAAA==.',Za='Zam:BAACLAAFFIEOAAIbAAMIdhA6EQDlAAAbAAMIdhA6EQDlAAAsAAQKgSAAAhsABwgmIVojAGkCABsABwgmIVojAGkCAAAA.',Zd='Zdzich:BAAALAADCgEIAQAAAA==.',Ze='Zehir:BAAALAADCggICAAAAA==.Zerno:BAABLAAECoEvAAMEAAgIiSMjBwAYAwAEAAgIiSMjBwAYAwAbAAEIsgExtQASAAAAAA==.',Zi='Ziozio:BAACLAAFFIEFAAIBAAMIDhpxDQAUAQABAAMIDhpxDQAUAQAsAAQKgSsAAgEACAi3I4kKADcDAAEACAi3I4kKADcDAAAA.',['Zí']='Zíózio:BAAALAAECgUIBQABLAAFFAMIBQABAA4aAA==.',['Ál']='Ályssá:BAAALAAECgMIAwABLAAFFAMICAACAAMZAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end