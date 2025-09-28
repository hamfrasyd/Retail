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
 local lookup = {'Druid-Restoration','Priest-Holy','Warlock-Demonology','Priest-Shadow','Druid-Balance','Unknown-Unknown','Warrior-Fury','Druid-Guardian','Mage-Arcane','Mage-Fire','Paladin-Retribution','Mage-Frost','DeathKnight-Frost','Monk-Windwalker','Shaman-Restoration','DeathKnight-Blood','Evoker-Preservation','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Havoc','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Monk-Brewmaster','Priest-Discipline','Evoker-Devastation','Warrior-Protection','Shaman-Elemental','Paladin-Holy','DemonHunter-Vengeance','Druid-Feral','Shaman-Enhancement','Warlock-Affliction',}; local provider = {region='EU',realm='Proudmoore',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abundantia:BAAALAAECgMIAwAAAA==.',Ac='Acri:BAAALAADCgcIBwAAAA==.',Ad='Adaneth:BAAALAAECgEIAQAAAA==.',Ai='Aigil:BAABLAAECoEtAAIBAAgIFBzPJAAqAgABAAgIFBzPJAAqAgAAAA==.',Ak='Akwin:BAACLAAFFIEGAAICAAMI3w+yEQDfAAACAAMI3w+yEQDfAAAsAAQKgSYAAgIACAgbGOEjAEQCAAIACAgbGOEjAEQCAAAA.',Al='Alani:BAAALAAECgMIAwAAAA==.Albus:BAABLAAECoEjAAIDAAcIKSWJBwDTAgADAAcIKSWJBwDTAgAAAA==.Aleshanee:BAAALAADCgcICgABLAAECgcIGwAEAIAMAA==.Alyna:BAAALAADCggICAAAAA==.Alyssaa:BAABLAAECoEVAAIFAAYI+AdtXQAFAQAFAAYI+AdtXQAFAQAAAA==.Alytdris:BAAALAAECgIIAgAAAA==.',Am='Amaine:BAAALAADCgcIBwAAAA==.Ambêrly:BAAALAAECgYIBgAAAA==.Amenos:BAAALAAECgcIEAAAAA==.Ametyst:BAAALAADCgcICwAAAA==.Amularí:BAAALAAECgQIBAAAAA==.Amâzonin:BAAALAADCgIIAgABLAAECgYIDAAGAAAAAA==.',An='Anemsis:BAAALAAECgYIBgAAAA==.Angelsky:BAAALAAECgYICQAAAA==.Antoniá:BAAALAADCggIHgAAAA==.Anutiris:BAAALAAECgQIBAAAAA==.',Ar='Aratoc:BAAALAAECggICAAAAA==.Ariee:BAAALAAECgYICwAAAA==.Ariya:BAAALAADCgQIBAAAAA==.Armawen:BAAALAADCgQIBAAAAA==.Arîsha:BAAALAADCggIEAAAAA==.',As='Ashwing:BAAALAAECgYICgAAAA==.Asin:BAAALAAECgcIBwAAAA==.',At='Ateragon:BAAALAAECgYICQAAAA==.',Au='Audítóre:BAABLAAECoEtAAIHAAgIhCJdEAAOAwAHAAgIhCJdEAAOAwAAAA==.Auryna:BAAALAAECgMIBQAAAA==.',Ax='Axeeffect:BAABLAAECoEXAAIIAAYIPhKpFABNAQAIAAYIPhKpFABNAQAAAA==.',Ay='Ayuki:BAABLAAECoEbAAIIAAcIcxVTDgC4AQAIAAcIcxVTDgC4AQAAAA==.',Ba='Balren:BAACLAAFFIESAAIJAAUIwxzvCADeAQAJAAUIwxzvCADeAQAsAAQKgTAAAwkACAhXJJIKADQDAAkACAhXJJIKADQDAAoAAQgzIA0bAEIAAAAA.',Be='Benda:BAAALAADCggIBwABLAAECgcIGAAJALQRAA==.Beohn:BAAALAAECgYIDAAAAA==.Beredan:BAABLAAECoEgAAMBAAcINBDzSQCBAQABAAcINBDzSQCBAQAFAAcIXhBZUwAwAQAAAA==.',Bi='Bigland:BAAALAAECggIEwAAAA==.Bigschatten:BAAALAADCgYIBgAAAA==.Bislipur:BAAALAADCggIDQAAAA==.',Bj='Bjarka:BAAALAADCgYIBgAAAA==.',Bl='Blackmámba:BAAALAAECgYIBgABLAAECggILQAHAIQiAA==.Blackpánn:BAAALAAECgYIBwAAAA==.Blúeshirtguy:BAAALAAECgEIAQAAAA==.',Bo='Bobi:BAABLAAECoEVAAIBAAcIXAvlewDlAAABAAcIXAvlewDlAAAAAA==.Bogey:BAAALAAECgcIDQABLAAECggILQAGAAAAAQ==.Bomboor:BAAALAADCgcIEAABLAAFFAIIAgAGAAAAAA==.Bombôr:BAABLAAECoEWAAILAAYIFyR5NQB1AgALAAYIFyR5NQB1AgABLAAFFAIIAgAGAAAAAA==.',Br='Bratac:BAAALAAECgUIDQAAAA==.Brron:BAAALAAECgMIAwAAAA==.',Bu='Bummbelbe:BAAALAAECgEIAQAAAA==.Bunnahabhain:BAAALAAECgYICwAAAA==.Buschmann:BAACLAAFFIEJAAIFAAQIPBK3BwA1AQAFAAQIPBK3BwA1AQAsAAQKgSYAAgUACAh0IIgRALwCAAUACAh0IIgRALwCAAAA.',['Bö']='Bösirella:BAAALAADCgcIDQAAAA==.',Ca='Cainnix:BAAALAADCggIKgAAAA==.Carras:BAABLAAECoEdAAIMAAcIKhueKQC5AQAMAAcIKhueKQC5AQAAAA==.Castorius:BAAALAAECgIIAgAAAA==.Cateater:BAAALAADCgYIBgAAAA==.',Ce='Cerebres:BAAALAAECgMICAABLAAECgYICwAGAAAAAA==.',Ch='Chomps:BAAALAAECggIEwAAAA==.Chuckman:BAAALAADCgcIBwABLAAECgcIHAANAE8eAA==.Chupsi:BAAALAADCggICAAAAA==.',Ci='Cikua:BAAALAADCgYIBgAAAA==.Cinin:BAABLAAECoEXAAIOAAcIPCQnCwDGAgAOAAcIPCQnCwDGAgABLAAFFAIICAAPAJsfAA==.',Cl='Claw:BAAALAAECgUICwAAAA==.',Co='Cocoheal:BAAALAAECgYIDwABLAAFFAIIAgAGAAAAAA==.Coonz:BAAALAAECgYICAAAAA==.Coraheal:BAAALAAECgYIBgABLAAFFAIIAgAGAAAAAA==.',['Cá']='Cástiell:BAAALAADCgMIAwAAAA==.',['Cí']='Cíjara:BAAALAAECgYICgABLAAECggIJAALAGYgAA==.',['Cô']='Côsma:BAABLAAECoEXAAICAAYIhBdxRACfAQACAAYIhBdxRACfAQAAAA==.',Da='Daemis:BAAALAAECgYIDAAAAA==.Daemon:BAAALAAECgYIBgAAAA==.Darkdeamon:BAAALAAECgYIEAAAAA==.Darkpando:BAAALAAECgYIDQAAAA==.Darkser:BAAALAAECgEIAQAAAA==.Darkweaver:BAAALAADCgcICAAAAA==.',De='Deathcaller:BAAALAADCggIJAAAAA==.Deathdog:BAACLAAFFIEJAAIQAAQIdg9JBQAKAQAQAAQIdg9JBQAKAQAsAAQKgSAAAhAACAgJGSQQABgCABAACAgJGSQQABgCAAAA.Deathsoul:BAAALAAECgYICgAAAA==.Delmon:BAABLAAECoEaAAILAAYItx2jZADxAQALAAYItx2jZADxAQAAAA==.Deluna:BAAALAAECgYIDQAAAA==.Dema:BAAALAAECgYICQAAAA==.Demeter:BAAALAAECgYIEAAAAA==.Demønic:BAAALAAECgYICAAAAA==.Dermike:BAAALAAECgIIAQAAAA==.Devilschurk:BAAALAAECgMICQAAAA==.Deymos:BAAALAAECgYIDwAAAA==.',Dh='Dhariya:BAAALAADCgcIEgAAAA==.',Di='Distronik:BAAALAAECgYIBgAAAA==.',Do='Dolchdieter:BAAALAAECgYIDAABLAAFFAIIAgAGAAAAAA==.',Dr='Drachine:BAAALAAECgYICQAAAA==.Dracpro:BAACLAAFFIEMAAIRAAQIehKCBQA6AQARAAQIehKCBQA6AQAsAAQKgTEAAhEACAinHRcHAKYCABEACAinHRcHAKYCAAAA.Drahgo:BAAALAADCgcIIwAAAA==.Dreggi:BAAALAAECgcICgAAAA==.Dreggsklasse:BAAALAAECgYIDQAAAA==.Droden:BAACLAAFFIEFAAIPAAIIShkbJQCWAAAPAAIIShkbJQCWAAAsAAQKgU0AAg8ACAgiJY4CAFEDAA8ACAgiJY4CAFEDAAAA.Droxa:BAAALAAECgYIEQAAAA==.',Du='Dud:BAAALAAECgYICwAAAA==.',Dy='Dyonisa:BAAALAAECgEIAQAAAA==.',['Dé']='Déllingr:BAAALAADCgYIBgAAAA==.',Ec='Echtjetzt:BAACLAAFFIEJAAISAAMItBzHEwDfAAASAAMItBzHEwDfAAAsAAQKgSsAAhIACAjyJD8PAAsDABIACAjyJD8PAAsDAAAA.',Ed='Edfeáren:BAABLAAECoEUAAITAAYIehSIaQCCAQATAAYIehSIaQCCAQABLAAFFAQICQAUAMQiAA==.',El='Elae:BAAALAADCgcICAAAAA==.Elandaa:BAAALAAECgYICwAAAA==.Elanorel:BAABLAAECoEnAAIPAAcI7hbuVwCvAQAPAAcI7hbuVwCvAQAAAA==.Elazra:BAAALAADCggICAAAAA==.Elborn:BAAALAADCggIDgAAAA==.Elumyr:BAAALAADCggICAAAAA==.Elénaá:BAAALAADCgUIBQAAAA==.',En='Enzii:BAACLAAFFIEIAAIPAAIImx+4HQCsAAAPAAIImx+4HQCsAAAsAAQKgSIAAg8ACAgnJAgFADEDAA8ACAgnJAgFADEDAAAA.',Eo='Eomer:BAAALAADCggIIAAAAA==.',Er='Erol:BAAALAADCgYIBgAAAA==.',Es='Esari:BAAALAADCgEIAQAAAA==.',Ey='Eyeswîdeshut:BAAALAAECgQICQAAAA==.',['Eí']='Eínmalíg:BAABLAAECoEqAAIVAAgI3BoWFQAiAgAVAAgI3BoWFQAiAgAAAA==.',Fa='Fazknight:BAAALAAECgYICQABLAAECgYIEAAGAAAAAA==.',Fe='Feuerbluete:BAABLAAECoEeAAIPAAcI3QxvlQAYAQAPAAcI3QxvlQAYAQAAAA==.Fexxquo:BAAALAAECggICAAAAA==.',Fi='Fiana:BAAALAAECgYIDwAAAA==.',Fo='Fodo:BAAALAAECgYIDwAAAA==.Fosco:BAABLAAECoEVAAICAAgIFwl3XgA9AQACAAgIFwl3XgA9AQAAAA==.Foxxi:BAAALAAECgMIAwAAAA==.',Fr='Frank:BAAALAADCgQIBAAAAA==.Freakyfrkzz:BAAALAAECggICAABLAAECggIGwASAMgkAA==.Freakymeaky:BAABLAAECoEbAAMSAAgIyCSIOgA0AgASAAgI8yKIOgA0AgAWAAQIhB7jTQBlAQAAAA==.Freckless:BAAALAAECgcIDwAAAA==.Freundschaft:BAAALAAECgYICgAAAA==.Friendlyfire:BAAALAAECgYIBgABLAAFFAIIAgAGAAAAAA==.',Fu='Furybeast:BAAALAAECggICAAAAA==.',Fy='Fyreyell:BAABLAAECoEmAAISAAgImhT9VgDdAQASAAgImhT9VgDdAQAAAA==.',['Fá']='Fáýólá:BAABLAAECoEbAAMEAAcIgAyMVAA+AQAEAAcIgAyMVAA+AQACAAMIIwQKlQBrAAAAAA==.',['Fâ']='Fâlkê:BAABLAAECoEWAAILAAcIWxuLSgAzAgALAAcIWxuLSgAzAgAAAA==.',Ga='Gajus:BAAALAAECgEIAQAAAA==.',Ge='Geisteskind:BAAALAAECgQIBAABLAAFFAMIBgACAN8PAA==.Geobeo:BAABLAAECoEkAAQXAAgIACFYCADBAgAXAAgIACFYCADBAgAQAAUI/xlBIABDAQANAAEIrQkAAAAAAAAAAA==.Gerret:BAAALAADCgcICAAAAA==.Getreumt:BAAALAAECgIIAQAAAA==.',Gh='Ghôst:BAAALAAECgMIBAAAAA==.',Gi='Gieridan:BAABLAAECoEfAAIUAAcIaB2fRQAnAgAUAAcIaB2fRQAnAgAAAA==.',Gl='Glítterbean:BAAALAAECgQIBAAAAA==.',Gn='Gnexer:BAAALAAECgYIDAAAAA==.Gnomferatu:BAABLAAECoEUAAITAAYIQB5aPgARAgATAAYIQB5aPgARAgAAAA==.Gnomkiller:BAAALAAECgQIBAAAAA==.',Go='Gorena:BAABLAAECoEgAAIFAAcI1BbtMQDIAQAFAAcI1BbtMQDIAQAAAA==.',Gr='Grexx:BAAALAADCgcIDAAAAA==.Grimnar:BAAALAADCggICAAAAA==.Grizoo:BAABLAAECoEYAAIJAAcItBFtgwBjAQAJAAcItBFtgwBjAQAAAA==.',Gu='Gulzerian:BAAALAAECgcIBwABLAAFFAIICAAPAJsfAA==.Guthrum:BAAALAADCggIFQAAAA==.',['Gà']='Gàl:BAACLAAFFIEGAAIEAAQIIw8eCgAvAQAEAAQIIw8eCgAvAQAsAAQKgRoAAgQACAiJGvkgAE4CAAQACAiJGvkgAE4CAAAA.',['Gä']='Gälicmoods:BAAALAAECgYICQAAAA==.',['Gå']='Gål:BAACLAAFFIEEAAMYAAIICRj7FABLAAAZAAEIUxhnGwBTAAAYAAEIvxf7FABLAAAsAAQKgR0AAxkACAgAIUQOAKwCABkACAgtIEQOAKwCABgAAwgVEoEyALoAAAAA.',['Gí']='Gíldarts:BAAALAAECgEIAQAAAA==.',Ha='Hallypally:BAAALAADCggICAAAAA==.Hammersdann:BAAALAAECgEIAQAAAA==.Hanasa:BAAALAAECgYIBwABLAAFFAIICAAPAJsfAA==.Hanna:BAAALAAECgEIAQAAAA==.Harne:BAAALAAECgYIBgAAAA==.',He='Heleneá:BAAALAAECgcIBwAAAA==.Henro:BAAALAAECgYICQAAAA==.Hestia:BAAALAADCggICwAAAA==.',Hi='Himbeertoni:BAAALAAECgQICAAAAA==.',Ho='Hoernchen:BAAALAADCgcIBwAAAA==.Holycat:BAAALAADCggICAAAAA==.Holyschatten:BAAALAADCgQIBAAAAA==.Holystone:BAAALAADCgcIBwAAAA==.Homelander:BAAALAADCggICAAAAA==.Homîecîde:BAABLAAECoEgAAISAAcIHR1KQQAcAgASAAcIHR1KQQAcAgAAAA==.Hornstars:BAACLAAFFIEJAAIUAAQIxCJ0CgCDAQAUAAQIxCJ0CgCDAQAsAAQKgR4AAhQACAjzIUwaAOMCABQACAjzIUwaAOMCAAAA.Hotbaby:BAAALAAECgYIEAAAAA==.',['Hä']='Hädbängä:BAAALAADCggICAAAAA==.',Ic='Iceregen:BAABLAAECoEhAAISAAcI5RD3igBoAQASAAcI5RD3igBoAQAAAA==.',Ik='Ikamun:BAAALAAECgUIDgAAAA==.',In='Indria:BAAALAADCgEIAQAAAA==.Indydrakes:BAACLAAFFIELAAIaAAQIUhtsAgBZAQAaAAQIUhtsAgBZAQAsAAQKgR8AAhoACAg/IzgCANMCABoACAg/IzgCANMCAAAA.Indypalas:BAAALAAECgYIBgABLAAFFAQICwAaAFIbAA==.Inkheart:BAAALAAECggICAABLAAFFAQIDAAbABMKAA==.Inouske:BAAALAAECgYIEAAAAA==.Inside:BAAALAADCgEIAQABLAAECggIFwASAGAUAA==.Insidebeam:BAABLAAECoEfAAIFAAcIvB7aHQBHAgAFAAcIvB7aHQBHAgABLAAECggIFwASAGAUAA==.',Is='Isende:BAAALAAECgQICQAAAA==.',Ja='Jadefell:BAAALAADCggICAAAAA==.Jadisme:BAAALAAECggIEwAAAA==.Jakeperalta:BAAALAADCggICAAAAA==.Jalari:BAAALAADCgcIBwAAAA==.',Ji='Jivos:BAAALAAECgMIBQAAAA==.',['Jé']='Jénná:BAAALAADCgcIGAABLAAECgYICAAGAAAAAA==.',Ka='Kadai:BAAALAAECgUIBgAAAA==.Kagari:BAABLAAECoEYAAIcAAYIOSYLBACBAgAcAAYIOSYLBACBAgAAAA==.Kakibabuu:BAACLAAFFIEGAAIXAAII5xLoDACjAAAXAAII5xLoDACjAAAsAAQKgS4AAhcACAgEJHUEAA0DABcACAgEJHUEAA0DAAAA.Kaladum:BAABLAAECoEiAAITAAYIyRVpYwCTAQATAAYIyRVpYwCTAQAAAA==.Kaluana:BAAALAADCgIIAgAAAA==.Kamelot:BAAALAADCgcIBwAAAA==.Karlheinrich:BAAALAADCggIEAAAAA==.Karragos:BAACLAAFFIEOAAIdAAQIuCRABQCnAQAdAAQIuCRABQCnAQAsAAQKgSEAAh0ACAi8JT8EAEEDAB0ACAi8JT8EAEEDAAAA.Katuhl:BAAALAAECgYIEAAAAA==.',Ke='Keddana:BAAALAADCggICAAAAA==.Keddomania:BAAALAAECggIBQAAAA==.Keji:BAAALAAECgMIAwAAAA==.Kertschak:BAAALAADCggIAQAAAA==.Keuschmann:BAAALAAECgQIBAAAAA==.',Ki='Kirah:BAAALAAECgIIAgAAAA==.Kirasha:BAAALAAECgMIBQAAAA==.Kiyomî:BAAALAAECgQIDAAAAA==.',Kl='Klosterbräu:BAAALAADCggICAAAAA==.',Km='Kmae:BAAALAADCgYIBgABLAAFFAMICQASALQcAA==.',Ko='Kokoro:BAAALAAECgYIDAAAAA==.Koyari:BAAALAADCggIHQABLAAECgYIDAAGAAAAAA==.',Kr='Krelli:BAAALAAECgYICQAAAA==.Kromsgor:BAAALAAECgEIAQAAAA==.',Ku='Kulchas:BAAALAADCgMIAwAAAA==.Kulem:BAAALAADCgIIAgABLAAECgcIGgAPANkdAA==.Kungpandia:BAAALAADCggIIwAAAA==.',['Kê']='Kêddo:BAABLAAECoElAAMeAAcIBx0AHQAWAgAeAAcI4xsAHQAWAgAHAAcIohYjmADxAAAAAA==.',['Kö']='Kölsch:BAAALAADCgYIBgAAAA==.',['Kú']='Kúbítér:BAAALAAECgcIEgAAAA==.',La='Lakkal:BAAALAAECgQIDgAAAA==.Langdron:BAACLAAFFIELAAMfAAMIGBQUEgDjAAAfAAMIGBQUEgDjAAAPAAMIDxNqEwDSAAAsAAQKgSIAAx8ACAjrHC40AA8CAB8ABwh7Gy40AA8CAA8ACAjWEk1SAL4BAAAA.Larper:BAAALAAECgYIBgAAAA==.',Le='Leelement:BAAALAADCggIGQAAAA==.Legende:BAAALAAECgYIDAAAAA==.Leshan:BAAALAADCgIIAgAAAA==.',Lh='Lhìz:BAABLAAECoEnAAILAAgIjSQxDAA+AwALAAgIjSQxDAA+AwAAAA==.',Li='Lilìth:BAAALAADCgcIBwAAAA==.Lingerkiller:BAABLAAECoEbAAISAAcI9hXQiQBqAQASAAcI9hXQiQBqAQAAAA==.Linvala:BAAALAAECgYIEAAAAA==.Lionar:BAAALAADCggIHAAAAA==.Liorana:BAAALAAECgEIAQAAAA==.Lisayah:BAAALAAECgQIEAAAAA==.',Lo='Lockyin:BAAALAAECgMIAwAAAA==.Loldarkylol:BAABLAAECoEkAAIEAAgIcBHjOAC+AQAEAAgIcBHjOAC+AQAAAA==.Lonely:BAAALAAECgUIBQAAAA==.Longdron:BAAALAADCgMIAwABLAAFFAMICQASALQcAA==.Loreal:BAAALAAECgYIBgABLAAECgcIGAAVACQRAA==.Lorelli:BAAALAAECggICAAAAA==.Lorisaniea:BAAALAAFFAIIAgAAAA==.Loudron:BAAALAAECggICAAAAA==.Loux:BAACLAAFFIEJAAIBAAMIqB4YCQASAQABAAMIqB4YCQASAQAsAAQKgR8AAwEACAgPGpogAEICAAEACAgPGpogAEICAAUABAh8FO1kAOAAAAAA.',Lu='Lumielana:BAAALAADCggICAAAAA==.Lupisregina:BAABLAAECoEVAAMNAAYIqx31aADvAQANAAYIah31aADvAQAQAAMI0BYOMACkAAAAAA==.',Ly='Lykari:BAABLAAECoEdAAIfAAcIHB3UJQBdAgAfAAcIHB3UJQBdAgAAAA==.',['Lè']='Lèylin:BAAALAAECgMIAwAAAA==.',['Lø']='Løkì:BAACLAAFFIEGAAMXAAIIaRN7DQChAAAXAAIIaRN7DQChAAANAAEILwW4bQA+AAAsAAQKgS0AAxcACAicIcAGAN4CABcACAicIcAGAN4CAA0ABgicGBvEAE4BAAAA.Løkï:BAAALAAECggIDQAAAA==.',['Lú']='Lúnar:BAAALAADCgEIAQAAAA==.',Ma='Maajida:BAAALAADCgYIDQAAAA==.Mabelle:BAAALAAECgEIAQAAAA==.Madekk:BAAALAADCgUIBQAAAA==.Maisie:BAAALAADCgQIBAABLAAECgcIGgAPANkdAA==.Maisíê:BAAALAADCggIDwABLAAECgcIGgAPANkdAA==.Maizie:BAAALAADCgYIBgABLAAECgcIGgAPANkdAA==.Malltera:BAAALAAECgYIEgABLAAECggIKAATAFgbAA==.Mandrakor:BAAALAADCgcICgAAAA==.Manuels:BAAALAAECgMIAwAAAA==.Mardi:BAAALAADCgcIBwAAAA==.Marsh:BAAALAADCgQIAwAAAA==.Mausling:BAAALAAECgYIDwAAAA==.Mazekyel:BAAALAADCggIEAABLAAECggIJgASAJoUAA==.Maëla:BAAALAAECgMIAwAAAA==.',Me='Meatshield:BAAALAAECggIGQABLAAECggILQAGAAAAAQ==.Medo:BAAALAADCgcIBwAAAA==.Medorah:BAABLAAECoEnAAITAAgIzRVjTgDUAQATAAgIzRVjTgDUAQAAAA==.Medy:BAABLAAECoEgAAIgAAcIPRgOHgD0AQAgAAcIPRgOHgD0AQAAAA==.Melinda:BAAALAAECgYIBwAAAA==.Melnyna:BAABLAAECoEoAAIBAAcIeBiQPAC3AQABAAcIeBiQPAC3AQAAAA==.Merlìn:BAAALAAECgEIAQAAAA==.',Mi='Mirî:BAAALAAECgQIBAAAAA==.Missdark:BAAALAADCgYIBgAAAA==.',Mo='Mobbarley:BAAALAADCggICAAAAA==.Mobyhood:BAAALAADCggIEAAAAA==.Monddrache:BAAALAADCggIHgABLAAECgYIFwAIAD4SAA==.Monktana:BAAALAAFFAIIBwAAAQ==.Mooniya:BAABLAAECoEfAAICAAcIthBuRgCXAQACAAcIthBuRgCXAQAAAA==.Morgenstern:BAAALAAECgIIAgAAAA==.Moyin:BAAALAADCggIEwAAAA==.Moyine:BAAALAADCgYIBgAAAA==.',My='Myrrima:BAABLAAECoEWAAIbAAcI8wfULQDjAAAbAAcI8wfULQDjAAAAAA==.',['Mâ']='Mâizîe:BAABLAAECoEaAAMPAAcI2R3nOwAEAgAPAAcI2R3nOwAEAgAfAAII/AwAAAAAAAAAAA==.Mâlrîôn:BAABLAAECoEXAAMUAAcIzSHnMwBnAgAUAAcIzSHnMwBnAgAhAAMIQA7uRgB8AAAAAA==.',['Mö']='Möwe:BAAALAADCggICQAAAA==.',Na='Nagràch:BAAALAADCgcIBwAAAA==.Naishaa:BAAALAAECgYIEAAAAA==.Narila:BAAALAADCggIJgAAAA==.Naruko:BAABLAAECoEWAAISAAgIDh80HgCxAgASAAgIDh80HgCxAgAAAA==.Narulak:BAAALAADCgcIDQAAAA==.Narí:BAACLAAFFIEFAAIIAAIIJyWOAQDYAAAIAAIIJyWOAQDYAAAsAAQKgS4AAggACAi+JkEAAJQDAAgACAi+JkEAAJQDAAAA.',Ne='Negy:BAAALAAECgYIBgABLAAFFAMICwAfABgUAA==.Nerzyasan:BAABLAAECoEaAAINAAYI2AKOCgG/AAANAAYI2AKOCgG/AAAAAA==.Netherlise:BAAALAAECgIIAgABLAAECggIEQAGAAAAAA==.Nevelle:BAABLAAECoEYAAMBAAcINSJiFgCFAgABAAcINSJiFgCFAgAFAAcIhBi9KwDrAQAAAA==.',Ni='Nightpanther:BAAALAADCggICAAAAA==.Nightro:BAAALAADCgMIAwAAAA==.Nihaø:BAAALAADCggICAABLAAECggIJAALAGYgAA==.Niriande:BAAALAAECgUIBwAAAA==.Niveà:BAABLAAECoEYAAMVAAcIJBFxLgBTAQAVAAcItxBxLgBTAQALAAIIpA3UFwF9AAAAAA==.',No='Nográch:BAAALAADCgYIBgAAAA==.Noirbert:BAAALAAECgcIBwABLAAFFAIICAAPAJsfAA==.Noirvoker:BAABLAAECoEVAAIRAAgIwhM7EAD8AQARAAgIwhM7EAD8AQABLAAFFAIICAAPAJsfAA==.Nokrazul:BAAALAADCggICAABLAAECgYIFwAIAD4SAA==.Noorie:BAAALAAECgYICQAAAA==.Nounoobie:BAABLAAECoEgAAIBAAcIYRupKgAMAgABAAcIYRupKgAMAgAAAA==.',Nu='Nutsandbolts:BAACLAAFFIEMAAIbAAQIEwqJBwDxAAAbAAQIEwqJBwDxAAAsAAQKgR8AAxsACAiyEmwbAJMBABsACAiyEmwbAJMBAA4ACAjICv4sAGsBAAAA.',Nw='Nwave:BAAALAADCgYIBwAAAA==.',Ny='Nyxaria:BAAALAAECgYIDwAAAA==.',['Nâ']='Nâomi:BAAALAADCgMIAwAAAA==.',['Né']='Néniel:BAAALAADCggIDwABLAAFFAIIAgAGAAAAAA==.',['Nó']='Nómin:BAAALAAECgYIDQAAAA==.',Ob='Obi:BAAALAAECgIIAgAAAA==.',Om='Ombra:BAAALAADCgMIAwAAAA==.',Or='Ore:BAAALAADCggIDAAAAA==.',Pa='Painster:BAAALAAECggILQAAAQ==.Paldros:BAAALAAECgUIBQABLAAFFAUIEgAJAMMcAA==.Panski:BAAALAADCgMIAwAAAA==.Papito:BAAALAAECgcIEwAAAA==.',Pe='Pectoralis:BAACLAAFFIELAAIHAAQIdx2HCQCCAQAHAAQIdx2HCQCCAQAsAAQKgSoAAgcACAiAJRYJAEMDAAcACAiAJRYJAEMDAAAA.Penaten:BAAALAAECgQIBAABLAAECgcIGAAVACQRAA==.Pendragos:BAAALAAECgEIAQAAAA==.',Pi='Pitobi:BAAALAAECgcIBwAAAA==.Pizzalotti:BAAALAAECgEIAQABLAAECgUIBwAGAAAAAA==.',Po='Polygnøm:BAABLAAECoESAAITAAcIKRS0TgDTAQATAAcIKRS0TgDTAQAAAA==.',Pr='Praylan:BAAALAAECgYICQAAAA==.Prryon:BAABLAAECoEaAAIEAAYIGB90JwAgAgAEAAYIGB90JwAgAgAAAA==.',Pu='Puncto:BAAALAAECgYIBwAAAA==.',['Pá']='Pámuk:BAAALAADCggICAAAAA==.',Qn='Qny:BAAALAADCgIIAwAAAA==.',Qu='Quent:BAAALAADCgYIBgAAAA==.Qumaira:BAABLAAECoEeAAIIAAcIHgyRFgAyAQAIAAcIHgyRFgAyAQAAAA==.Quzila:BAAALAAFFAIIBAABLAAFFAIICAAPAJsfAA==.',Ra='Radnór:BAAALAAECgcIDwAAAA==.Rahu:BAAALAAECggIEgAAAA==.Rajáthen:BAAALAADCgcIBwAAAA==.Raketenralf:BAAALAADCgIIAgAAAA==.Ransom:BAAALAAECgEIAQAAAA==.Razziel:BAAALAADCgcICwAAAA==.Razzila:BAAALAADCggIDwAAAA==.',Re='Reaper:BAABLAAECoEbAAMNAAgILQzxhQC3AQANAAgILQzxhQC3AQAQAAEIOwpkQAAtAAAAAA==.Rejoy:BAAALAADCgUICAAAAA==.Renesme:BAAALAADCggIEgAAAA==.Renlesh:BAAALAADCggICAAAAA==.Reznia:BAABLAAECoEjAAICAAgI0BSqLgAIAgACAAgI0BSqLgAIAgAAAA==.',Rh='Rhaenyra:BAAALAAECgUIDgAAAA==.',Ri='Ribulos:BAAALAAECgIIAgABLAAECggIEQAGAAAAAA==.',Ro='Roguefish:BAAALAAECgYIEAAAAA==.Rohnîn:BAAALAADCgcIBwAAAA==.Roswitha:BAAALAADCgcICQAAAA==.Rotznás:BAAALAAECgYIEAAAAA==.',Ru='Rubat:BAAALAADCgMIBgAAAA==.Rubedo:BAAALAAECgYIBgABLAAECgYIFQANAKsdAA==.Rubîna:BAAALAADCgYIDAAAAA==.Runar:BAAALAADCgQIBAAAAA==.',Ry='Rynn:BAABLAAECoEZAAMSAAcIWxW2kgBYAQASAAcIWxW2kgBYAQAWAAUIXhFgZQASAQAAAA==.',['Rö']='Rök:BAABLAAECoEUAAIeAAcICh0JGQA4AgAeAAcICh0JGQA4AgABLAAFFAIIBQAaAIsNAA==.',['Rú']='Rúnar:BAAALAAECgIIAgAAAA==.',['Rû']='Rûnâr:BAAALAAECggICAAAAA==.',Sa='Safina:BAABLAAECoEeAAMRAAcIZB9GCQB6AgARAAcIZB9GCQB6AgAdAAEIYgNMYAAcAAAAAA==.Sakura:BAAALAAECgYIEAAAAA==.Salu:BAEALAAECgcICwAAAA==.Sanku:BAAALAAECgMIAwAAAA==.Sapiosa:BAAALAADCgYIDAABLAAFFAIICAAPAJsfAA==.Sapralot:BAAALAAECgQIEAAAAA==.Sareena:BAAALAAECgYIEQAAAA==.Sarenrae:BAAALAADCggICAAAAA==.Sariff:BAAALAADCgcICwAAAA==.Saroc:BAAALAADCggIFgABLAAECgYIGgARACQiAA==.Sazuku:BAAALAADCgcICQAAAA==.',Sc='Scharfkralle:BAABLAAECoEcAAINAAcITx6fUAAoAgANAAcITx6fUAAoAgAAAA==.Schneggschen:BAAALAADCgcICAAAAA==.Screas:BAABLAAECoEaAAIUAAYI5iKdQgAxAgAUAAYI5iKdQgAxAgABLAAECggIGwASAMgkAA==.',Se='Sehnenriss:BAAALAADCgIIAgAAAA==.Selana:BAAALAAECgMIAwAAAA==.Seriana:BAAALAAECgEIAQAAAA==.Serra:BAAALAAECgYIDAAAAA==.',Sh='Shamîra:BAABLAAECoEiAAIPAAgIQxExcQBsAQAPAAgIQxExcQBsAQABLAAFFAIIAgAGAAAAAA==.Sharazada:BAABLAAECoEXAAIEAAgI9xBkLgD3AQAEAAgI9xBkLgD3AQAAAA==.Sheldox:BAAALAADCgUIBQAAAA==.Shikii:BAAALAAECgYIDwAAAA==.Shiroshan:BAAALAADCgYIBgAAAA==.Shjo:BAAALAAECgcICwABLAAECggIJAAXAAAhAA==.Shredders:BAAALAADCgcIBgAAAA==.Shufu:BAABLAAECoEZAAIPAAcIohWOXgCdAQAPAAcIohWOXgCdAQABLAAFFAQIDAAJAKARAA==.Shùrýk:BAAALAAECgIIAgAAAA==.',Si='Siale:BAABLAAECoEbAAIEAAgIWB/1EgDCAgAEAAgIWB/1EgDCAgAAAA==.Sickniss:BAAALAADCggICgAAAA==.Silessa:BAAALAADCgEIAQAAAA==.Silverlol:BAAALAAECgYIBgAAAA==.Simonp:BAAALAAECgEIAQAAAA==.',Sk='Skeppo:BAAALAADCgMIBQAAAA==.Skysha:BAAALAADCggIAQAAAA==.Skîbby:BAAALAAECgcIEQABLAAECgcIFAAEAF8RAA==.',Sm='Smaragd:BAAALAADCggIDwAAAA==.',Sn='Snair:BAABLAAECoEpAAMJAAgIzxNgTgD6AQAJAAgIAxFgTgD6AQAMAAcIZBClMwCCAQAAAA==.',So='Solaris:BAAALAADCgcIBwAAAA==.Sonne:BAAALAAECgYIDgAAAA==.Sonnenkind:BAAALAADCgYICQAAAA==.Sophieheal:BAAALAAFFAIIAgAAAA==.Sophiya:BAAALAAECgYICwAAAA==.',Sp='Speedylicous:BAAALAADCgcIBwAAAA==.Sportfrei:BAAALAADCggICAABLAAECgcIKAAdACshAA==.',St='Stealth:BAAALAADCgYIBgAAAA==.Stupid:BAABLAAECoEXAAMSAAgIYBRXUgDqAQASAAgIYBRXUgDqAQAWAAII/QMUtwAnAAAAAA==.Störtebärker:BAABLAAECoEYAAIiAAcICxUlGAC9AQAiAAcICxUlGAC9AQAAAA==.',Su='Succthebus:BAAALAADCgYIBgAAAA==.Sundream:BAAALAAECggIBAAAAA==.Sunyata:BAAALAAECgYICAAAAA==.',['Sâ']='Sâbí:BAAALAADCggICAAAAA==.Sâphirâa:BAAALAADCgEIAQAAAA==.Sâvírana:BAACLAAFFIEMAAILAAUIUhQFBgC0AQALAAUIUhQFBgC0AQAsAAQKgRsAAgsACAg2HAtBAE4CAAsACAg2HAtBAE4CAAAA.',['Sä']='Säbeluschi:BAAALAAECggIEQAAAA==.Säxyhäxy:BAAALAAECgcIBwAAAA==.',Ta='Tabby:BAAALAAECgYIDAAAAA==.Tabrean:BAAALAADCggIDwAAAA==.Talisah:BAABLAAECoEUAAILAAcIzA7joQB7AQALAAcIzA7joQB7AQAAAA==.Taonas:BAAALAAECgcICgABLAAECggIKAAjAPogAA==.Tariah:BAAALAAECgQIBAAAAA==.Tarok:BAAALAADCggIBwAAAA==.',Te='Teal:BAAALAAECgcIEwAAAA==.Telenda:BAABLAAECoEVAAMEAAcIwCACIQBOAgAEAAcIwCACIQBOAgAcAAIICxVXJQCAAAABLAAFFAIICAAPAJsfAA==.Tenguakiba:BAAALAADCgUIBQAAAA==.Terangor:BAAALAAECggIBQAAAA==.',Th='Thanators:BAAALAAECgEIAQAAAA==.Thandoria:BAABLAAECoEhAAIMAAcIJAUGTgAKAQAMAAcIJAUGTgAKAQAAAA==.Tharkûn:BAAALAADCggIEQAAAA==.Tharodil:BAAALAADCgYIBgAAAA==.Tharodin:BAAALAADCgYIBgAAAA==.Tharok:BAAALAAECgYIDwAAAA==.Thorgeir:BAAALAAECgYICwAAAA==.',Ti='Tibialis:BAABLAAECoEdAAMMAAcIhBsKFgBKAgAMAAcIhBsKFgBKAgAJAAYIFxQAAAAAAAABLAAFFAQICwAHAHcdAA==.Tikani:BAAALAADCggICAAAAA==.Tilda:BAABLAAECoEZAAISAAYI/Q77oAA9AQASAAYI/Q77oAA9AQAAAA==.Tiria:BAAALAADCggIDgAAAA==.',Tj='Tjell:BAAALAAECgMIAwAAAA==.',To='Torador:BAAALAADCgcIBwAAAA==.Totenbart:BAAALAAECgEIAQAAAA==.',Tr='Trym:BAAALAAECgYIBgAAAA==.',Ty='Tyrianoor:BAABLAAECoEaAAMBAAcIkRfVOQDDAQABAAcIkRfVOQDDAQAiAAYIEBTYHgB1AQAAAA==.',['Tá']='Táráh:BAAALAAECgMIBQAAAA==.',['Tä']='Tämon:BAAALAADCggICAABLAAECgYICwAGAAAAAA==.',['Tí']='Tífa:BAAALAADCggIEAABLAAECgMIAwAGAAAAAA==.',Ug='Uglyx:BAAALAADCgUIBQAAAA==.',Un='Underfire:BAABLAAECoEWAAMLAAgImwej6wDqAAALAAgIYASj6wDqAAAVAAYIYwmPSwCXAAAAAA==.',Us='Uschy:BAABLAAECoEoAAIjAAgI+iAgAwD8AgAjAAgI+iAgAwD8AgAAAA==.',Va='Vailem:BAABLAAECoEWAAMfAAcI+hCLcQArAQAfAAcI+hCLcQArAQAjAAQIIwNtHwCSAAABLAAFFAQIDQATAHQQAA==.Vapor:BAAALAADCgYIBgAAAA==.',Ve='Venommonk:BAAALAAECgcICgAAAA==.',Vo='Volira:BAAALAAECgYIDgAAAA==.Vortéx:BAAALAAECgMIAwAAAA==.',Wa='Warhawk:BAABLAAECoEWAAIBAAcIPAixbAAPAQABAAcIPAixbAAPAQAAAA==.Warianagrnde:BAAALAAFFAMIBQABLAAFFAIIBwAGAAAAAQ==.',Wh='Whitney:BAAALAADCggICAABLAAECgcIDQAGAAAAAA==.',Wi='Wildeagle:BAAALAAECggICAAAAA==.',Wo='Wonky:BAAALAAECgMIAwABLAAECggIKAAjAPogAA==.',['Wí']='Wítchlord:BAAALAADCggICgAAAA==.',['Wü']='Würgen:BAAALAAECgYIEAAAAA==.',Xa='Xalathron:BAAALAADCgcICQAAAA==.Xarfeigh:BAABLAAECoEaAAIMAAcIrhuuJADYAQAMAAcIrhuuJADYAQAAAA==.',Xo='Xoono:BAAALAADCggIIQAAAA==.Xoran:BAABLAAECoEnAAISAAgIoyCXFgDdAgASAAgIoyCXFgDdAgAAAA==.',Xs='Xsara:BAAALAAECgcIDQAAAA==.',Xw='Xwd:BAACLAAFFIEMAAIJAAQIoBEXFAAnAQAJAAQIoBEXFAAnAQAsAAQKgSQAAgkACAjCJLgNACEDAAkACAjCJLgNACEDAAAA.',['Xâ']='Xââi:BAAALAADCgcIEQAAAA==.',['Xé']='Xéron:BAACLAAFFIEIAAIMAAMImRcABADuAAAMAAMImRcABADuAAAsAAQKgSsAAgwACAgLI50IAPQCAAwACAgLI50IAPQCAAAA.',Yi='Yidhranos:BAACLAAFFIENAAMTAAQIdBCHEgA1AQATAAQIZA2HEgA1AQAkAAEItBv4BABYAAAsAAQKgR8AAxMACAh3GRoxAEwCABMACAh3GRoxAEwCACQABwhWCpYQAIsBAAAA.',Yl='Ylarah:BAACLAAFFIEOAAILAAQI/hgRCABoAQALAAQI/hgRCABoAQAsAAQKgTEAAwsACAh0Ii0dAOECAAsACAh0Ii0dAOECABUABggpECg0AC4BAAAA.',Yo='Yoniá:BAABLAAECoEUAAIEAAcIXxHoVwAuAQAEAAcIXxHoVwAuAQAAAA==.',Yv='Yviel:BAAALAADCgQIBAAAAA==.',Za='Zanto:BAAALAAECgMIAwAAAA==.Zantropas:BAAALAAECgcIEwAAAA==.',Ze='Zenwarrior:BAAALAAECgIIAgAAAA==.Zephi:BAAALAAECgUIBQAAAA==.',Zo='Zortak:BAAALAAECgYIBQAAAA==.',Zs='Zsuzsanna:BAAALAADCggICAAAAA==.',Zu='Zugmaschinê:BAABLAAECoEUAAINAAYIRxn0gADAAQANAAYIRxn0gADAAQAAAA==.',Zw='Zwérgaugé:BAAALAADCgQIBAAAAA==.',['Ák']='Ákírá:BAABLAAECoEUAAITAAYIBAqliAAxAQATAAYIBAqliAAxAQAAAA==.',['Âr']='Ârgometh:BAABLAAECoEbAAIeAAcI1BglKwCvAQAeAAcI1BglKwCvAQAAAA==.Âryá:BAABLAAECoEbAAICAAcIKBWsUQBrAQACAAcIKBWsUQBrAQAAAA==.',['Ðe']='Ðestruction:BAABLAAECoEkAAILAAcIZiATOwBgAgALAAcIZiATOwBgAgAAAA==.',['Öl']='Ölaf:BAAALAADCggIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end