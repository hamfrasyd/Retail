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
 local lookup = {'Monk-Brewmaster','Hunter-Marksmanship','Priest-Holy','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Unknown-Unknown','DeathKnight-Blood','Druid-Balance','Druid-Restoration','DemonHunter-Vengeance','Shaman-Elemental','Mage-Arcane','Monk-Mistweaver','Monk-Windwalker','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','Mage-Frost','Paladin-Retribution','DemonHunter-Havoc','Warlock-Demonology','Warlock-Affliction','DeathKnight-Frost','Paladin-Holy','Warrior-Fury','Priest-Shadow','DeathKnight-Unholy','Warrior-Arms','Druid-Feral','Warrior-Protection','Paladin-Protection','Rogue-Assassination','Evoker-Augmentation','Rogue-Subtlety','Priest-Discipline','Druid-Guardian',}; local provider = {region='EU',realm='Destromath',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aatrox:BAAALAAFFAIIAgAAAA==.',Ab='Abaraxis:BAAALAAECgYICgAAAA==.',Ae='Aegis:BAAALAADCgUIBQABLAAECggIJwABAOUYAA==.Aelya:BAABLAAECoEfAAICAAgIFR3qGgB4AgACAAgIFR3qGgB4AgAAAA==.',Ag='Agrât:BAAALAAECgIIAgAAAA==.',Ah='Ahiku:BAABLAAECoEkAAIDAAgILxSoKwAYAgADAAgILxSoKwAYAgAAAA==.',Ai='Aido:BAAALAAECgUICAAAAA==.Aiela:BAAALAAECgYIDwAAAA==.Ainzooalgown:BAAALAADCggICAAAAA==.',Al='Alarî:BAAALAAECgUIBQABLAAECggIJQAEALIcAA==.Alecxxo:BAAALAAECggIDwAAAA==.Alphahunta:BAAALAADCgQIBAAAAA==.Alterschwede:BAABLAAECoEjAAMFAAgI1B/kHAC5AgAFAAgI1B/kHAC5AgACAAEIpgLYvgAaAAAAAA==.Alyrstreza:BAAALAADCgIIAgAAAA==.',Am='Amîla:BAAALAAECgIIAgAAAA==.',An='Angash:BAAALAAECggIEQAAAA==.Angelachim:BAAALAADCgUIBQAAAA==.Angmar:BAABLAAECoEUAAIGAAYI8BqGTADbAQAGAAYI8BqGTADbAQAAAA==.Annery:BAAALAADCggICAAAAA==.Anoldor:BAAALAADCgcIBwAAAA==.',Ap='Apøçålypsê:BAAALAADCgEIAQAAAA==.',Ar='Aragonn:BAAALAADCgcIDwAAAA==.Araxina:BAAALAAECgUICQABLAAECgYIBgAHAAAAAA==.Arisah:BAAALAADCggIEAABLAAECgUIDwAHAAAAAA==.Arkash:BAABLAAECoEsAAIIAAgI7CNKAwA1AwAIAAgI7CNKAwA1AwAAAA==.Arktos:BAAALAAECgEIAQAAAA==.Arkæsh:BAAALAAECgYICwAAAA==.Arox:BAABLAAECoEoAAIDAAgIRR5FGQCJAgADAAgIRR5FGQCJAgAAAA==.Artemia:BAAALAAECgIIAgAAAA==.Artemìs:BAAALAAECgcIDgAAAA==.Arzoth:BAABLAAECoEbAAIEAAYIxiPhJwBPAgAEAAYIxiPhJwBPAgAAAA==.',As='Astaro:BAAALAADCgMIAwAAAA==.',Av='Avarie:BAAALAADCgYIBgAAAA==.',Ay='Ayah:BAABLAAECoElAAIEAAgIshxLGwCMAgAEAAgIshxLGwCMAgAAAA==.Ayanamii:BAAALAAECgMIBAAAAA==.',Az='Azania:BAAALAAECgUIBQAAAA==.Azki:BAAALAAECgYIBgAAAA==.Azrag:BAACLAAFFIEFAAIJAAIIQxnuDwCqAAAJAAIIQxnuDwCqAAAsAAQKgSUAAgkACAjbJGAFAEgDAAkACAjbJGAFAEgDAAAA.Azzulol:BAABLAAECoEWAAMKAAYI8yH1IQA6AgAKAAYI8yH1IQA6AgAJAAEIthyUiwA7AAAAAA==.Azzutotem:BAAALAAFFAEIAQAAAA==.',Ba='Bamigoreng:BAAALAAECgMIBQAAAA==.Barbîe:BAAALAAECgYIDwAAAA==.Barkonora:BAABLAAECoEnAAIFAAgIKxvPRQAOAgAFAAgIKxvPRQAOAgAAAA==.Bartleby:BAAALAAECggICAABLAAECggIJwABAOUYAA==.Barttak:BAAALAADCgcIBgABLAAECgcIHAAGAO0RAA==.',Be='Bele:BAAALAAECgYIBgABLAAECgcIDgAHAAAAAA==.Bellona:BAABLAAECoEZAAILAAgIjwyoJwA/AQALAAgIjwyoJwA/AQABLAAECgcIDgAHAAAAAA==.Beutêl:BAAALAADCgQIBAAAAA==.',Bi='Bifrost:BAAALAAECggIDgAAAA==.',Bl='Blackbetti:BAAALAAECgYIEgAAAA==.Blackhéart:BAAALAADCggICAAAAA==.Blackone:BAABLAAECoEoAAIMAAgIwyWJAwBvAwAMAAgIwyWJAwBvAwAAAA==.Blastingway:BAABLAAECoEWAAINAAgIvyH/MABrAgANAAgIvyH/MABrAgAAAA==.',Bo='Bodymilk:BAAALAADCggICAAAAA==.Boio:BAAALAADCgYIBgAAAA==.Boostêr:BAAALAADCgEIAQABLAAECggIJwAOAHAkAA==.Bothline:BAABLAAECoEiAAMPAAgI3h/lCQDcAgAPAAgI3h/lCQDcAgABAAQIdRDYMwCnAAAAAA==.',Br='Braduk:BAABLAAECoEnAAIQAAgIYhsvBgCaAgAQAAgIYhsvBgCaAgAAAA==.Brannrik:BAAALAAECgYIBgAAAA==.Brunhildegar:BAAALAAECgYIDQAAAA==.',Bu='Bubblebunny:BAAALAAECgIIAgAAAA==.Buddydk:BAAALAAECgYICgAAAA==.Buddyhunt:BAABLAAECoEZAAMFAAgIahPVfACEAQAFAAYIXhfVfACEAQACAAgI5Qs+WAA+AQAAAA==.Buddymage:BAAALAAECgIIAgAAAA==.Bundy:BAAALAAECgYIBgAAAA==.',Bw='Bwoah:BAAALAADCggICAAAAA==.',Ca='Caeruleis:BAABLAAECoEjAAMRAAgITBliFwBRAgARAAgITBliFwBRAgASAAUIxxQpIAAuAQAAAA==.Callan:BAAALAADCggICAABLAAECggIJwATAD0bAA==.Carrie:BAAALAAECgYIEQAAAA==.Carter:BAAALAAECgMIAwAAAA==.Casten:BAABLAAECoEVAAIUAAgIvQqphQCvAQAUAAgIvQqphQCvAQAAAA==.',Ch='Chaini:BAAALAAECgUIBQAAAA==.Chapis:BAAALAADCgcIBwAAAA==.Chardia:BAAALAAECggIDQAAAA==.Charraz:BAABLAAECoEUAAIGAAcI+ATrmAABAQAGAAcI+ATrmAABAQAAAA==.Chav:BAABLAAECoEtAAIEAAgIhyTJBAA0AwAEAAgIhyTJBAA0AwAAAA==.Cheeto:BAAALAADCggICAAAAA==.Cheezynet:BAAALAAECggIDAAAAA==.Chiastix:BAAALAAECgYICQAAAA==.Chicka:BAAALAAECggICQAAAA==.Chrry:BAAALAAECgcIEgAAAA==.Cháká:BAAALAAECgYIBgAAAA==.',Ci='Cirien:BAAALAADCggIDwABLAAECgUIDwAHAAAAAA==.',Cl='Cleave:BAAALAAECgQIBAABLAAECggICQAHAAAAAA==.Clêzz:BAABLAAECoEeAAMLAAgIehNAHQCbAQALAAcILBVAHQCbAQAVAAUIhwpo1gDbAAAAAA==.',Co='Cocó:BAABLAAECoEZAAIUAAgIRg1wfQC+AQAUAAgIRg1wfQC+AQAAAA==.Cometó:BAAALAADCgcIBwAAAA==.Copingway:BAAALAAECgYIBgAAAA==.Cotic:BAABLAAECoEeAAIUAAgIWR5tJwCvAgAUAAgIWR5tJwCvAgAAAA==.',Cr='Cranks:BAABLAAECoEWAAMFAAgI1yTsUADtAQAFAAgIgCTsUADtAQACAAMI/hssdADgAAAAAA==.Cree:BAACLAAFFIEIAAMGAAIIBSL+HgDCAAAGAAIIpCH+HgDCAAAWAAEIGR6jHABXAAAsAAQKgRoAAwYABwiLJEgdALoCAAYABwiLJEgdALoCABcABghBGMoNALkBAAEsAAUUAwgJAAUAdBwA.Crrx:BAAALAAECgYICgAAAA==.Crusted:BAABLAAECoESAAIYAAYIyxPTqwB1AQAYAAYIyxPTqwB1AQAAAA==.Cruzander:BAACLAAFFIEGAAIZAAIIdSHoDADJAAAZAAIIdSHoDADJAAAsAAQKgS8AAhkACAiGIbADABgDABkACAiGIbADABgDAAAA.',['Cô']='Cônstantin:BAAALAAECgYIBgAAAA==.',Da='Dabaaws:BAABLAAECoEnAAMOAAgIcCQ/AwAoAwAOAAgIcCQ/AwAoAwAPAAcIDxotFwAnAgAAAA==.Dammed:BAAALAAECggIEAAAAA==.Danami:BAAALAAECgYIDQAAAA==.Dandu:BAAALAAECgYIBgAAAA==.Danduin:BAAALAADCgcIBwAAAA==.Daník:BAAALAADCggIDAAAAA==.Darkram:BAAALAAECgEIAQABLAAECgYIFQAFAPgaAA==.Dasraubtier:BAAALAADCgcIBwAAAA==.Davesh:BAAALAADCgcIBwAAAA==.Daypak:BAAALAAECggIDQAAAA==.',De='Deadge:BAAALAAECgYIBgAAAA==.Demonet:BAABLAAECoEYAAIVAAcIWR8CMQBzAgAVAAcIWR8CMQBzAgAAAA==.Denaly:BAAALAADCgYIBgABLAADCgcIBwAHAAAAAA==.Deni:BAACLAAFFIEJAAIVAAIIuBnhJACgAAAVAAIIuBnhJACgAAAsAAQKgRoAAhUABgh9I+BKABcCABUABgh9I+BKABcCAAAA.Desgoss:BAAALAAECgYIEAAAAA==.',Dh='Dhugrin:BAACLAAFFIEGAAILAAIItAs6DgBnAAALAAIItAs6DgBnAAAsAAQKgScAAgsACAg2GYUSABUCAAsACAg2GYUSABUCAAAA.',Di='Diana:BAAALAADCgcIDgAAAA==.Diversidan:BAAALAAECgYIEgAAAA==.',Do='Docholiday:BAAALAAECgYIBwAAAA==.Dorodos:BAAALAAECgYIBgAAAA==.Dorofa:BAAALAAECgYIBgAAAA==.Dorofies:BAAALAADCggIHQAAAA==.Dorolie:BAAALAAECgYICgAAAA==.Dorolieb:BAAALAADCggIJgAAAA==.Dorostern:BAABLAAECoEYAAITAAYIDhRzRQAzAQATAAYIDhRzRQAzAQAAAA==.Dorosüß:BAABLAAECoEUAAIFAAgI5hO9WgDTAQAFAAgI5hO9WgDTAQAAAA==.Dorovoki:BAAALAADCggIIAAAAA==.',Dr='Dragonball:BAAALAAECgMIAwAAAA==.Draki:BAAALAADCgIIAgAAAA==.Drazok:BAAALAAECgYIBgAAAA==.Drcalculus:BAAALAADCggIEAAAAA==.Droknoz:BAABLAAECoEoAAMYAAgIDxqOewDKAQAYAAgIDxqOewDKAQAIAAcI0wkIJAAdAQAAAA==.Druidinoso:BAAALAAECggICAAAAA==.Drynes:BAAALAAECgcIDQABLAAECggICQAHAAAAAA==.Drédd:BAAALAAECgYIEwAAAA==.',Du='Durza:BAAALAAECgYICQAAAA==.Duskshadow:BAAALAADCgcIDgABLAAECggICAAHAAAAAA==.',['Dô']='Dôla:BAAALAAECgYICAAAAA==.',['Dü']='Düsterblick:BAAALAAECgMIAwAAAA==.',Ea='Eatya:BAAALAADCgYICgAAAA==.',Ed='Edamommy:BAAALAAECgMIAwAAAA==.',El='Eleadan:BAAALAADCggICAAAAA==.Elgordo:BAAALAAECgcIEAAAAA==.Elinora:BAAALAAECggICAAAAA==.Elonía:BAAALAAECgYIBgAAAA==.Elyora:BAAALAAECgYIEgAAAA==.',Em='Emier:BAABLAAECoEeAAIFAAgIKgqSnABFAQAFAAgIKgqSnABFAQAAAA==.',En='Enea:BAAALAAECgYIDwAAAA==.Enjuu:BAAALAAECgYICQAAAA==.Entsafter:BAAALAAECgMIBAABLAAECgYIDQAHAAAAAA==.',Er='Erada:BAAALAAECggIBgAAAA==.',Ex='Exspin:BAAALAADCgQIBAAAAA==.',Fa='Faelora:BAAALAAECgUIBgAAAA==.Faez:BAAALAAECgUIBwABLAAECggILgAUALMgAA==.Fappo:BAAALAAECgEIAQAAAA==.Fatameki:BAAALAADCgIIAgAAAA==.',Fe='Felara:BAAALAAECgYIEAAAAA==.Felinn:BAAALAADCgQIBAABLAAECggIEwAHAAAAAA==.Felori:BAAALAAECggIEwAAAA==.Fepsos:BAAALAAECgYIDwAAAA==.',Fi='Finnami:BAABLAAECoEZAAMEAAgIwRdbOQANAgAEAAgIwRdbOQANAgAMAAYIrg0lcwAlAQAAAA==.Finnbeast:BAABLAAECoEcAAIFAAgI5R3wIgCYAgAFAAgI5R3wIgCYAgAAAA==.Finnuwu:BAAALAAECgYICwAAAA==.Fiorello:BAAALAAECgIIBgAAAA==.Firan:BAAALAADCgYIBgAAAA==.Fireon:BAAALAAECggICAAAAA==.Fireshami:BAAALAAECggICgAAAA==.',Fl='Flarè:BAABLAAECoEgAAIEAAgILh4CFgCrAgAEAAgILh4CFgCrAgAAAA==.Flipster:BAAALAADCggICwAAAA==.Flogtheblood:BAAALAAECgcIDwAAAA==.Floope:BAAALAAECgYIBgAAAA==.Floôpê:BAAALAAECgMIBAABLAAECgYIBgAHAAAAAA==.Flumy:BAAALAAECgIIAgAAAA==.Flôopé:BAAALAAECgMIBQABLAAECgYIBgAHAAAAAA==.',Fo='Foose:BAAALAADCggIDgAAAA==.',Fr='Freedoom:BAAALAADCgcICAAAAA==.Freewey:BAAALAAECgIIBQAAAA==.Frostboy:BAABLAAECoEWAAITAAYIUwZETwAEAQATAAYIUwZETwAEAQAAAA==.Froxx:BAABLAAFFIEFAAIUAAMIehUADwD8AAAUAAMIehUADwD8AAAAAA==.',Fu='Fuchslicht:BAAALAADCgMIAwAAAA==.Fufuku:BAAALAADCgMIAwAAAA==.',Ga='Garaad:BAABLAAECoEgAAMMAAgIwAkVWQB9AQAMAAgI0ggVWQB9AQAQAAcIOwgNFQBuAQAAAA==.Garen:BAAALAADCggICwAAAA==.Gargo:BAAALAAECgUIBQAAAA==.Garmophob:BAAALAADCggIEAAAAA==.Gaâro:BAAALAAECggICwAAAA==.',Ge='Gelorya:BAAALAAECgQIBgAAAA==.Gerâld:BAABLAAECoEZAAIaAAYI2RJLZgCHAQAaAAYI2RJLZgCHAQAAAA==.Gewaltfee:BAAALAAECgUIBAABLAAFFAIIAgAHAAAAAA==.',Gh='Ghreeny:BAAALAAECgMIAwAAAA==.',Gi='Gizmogott:BAAALAAECgYIDQAAAA==.',Go='Gobbees:BAAALAAECgYIBQAAAA==.',Gr='Griedi:BAAALAAECgMIAwAAAA==.Griedlock:BAAALAAECgMIAwAAAA==.Gronzul:BAAALAADCgUIBwAAAA==.',Ha='Haher:BAAALAAECgMIBwAAAA==.Hal:BAABLAAECoEeAAINAAgItRybKwCEAgANAAgItRybKwCEAgAAAA==.Halasta:BAAALAAECgYIDAABLAAECggIHgANALUcAA==.Halaster:BAABLAAECoEVAAIbAAcIVxv0JQAqAgAbAAcIVxv0JQAqAgABLAAECggIHgANALUcAA==.Halgrim:BAAALAAECgYICgAAAA==.Haliøs:BAAALAADCgcIBgAAAA==.Hanspetra:BAAALAADCggIDQAAAA==.Haruya:BAAALAAFFAIIBAAAAA==.Hazekin:BAAALAADCggICAAAAA==.',He='Healsupply:BAAALAAECgYICQAAAA==.Hegel:BAABLAAECoEUAAQIAAgIbhxjLADKAAAYAAgIbhwM4gAaAQAIAAQIrxFjLADKAAAcAAMIdQ/LPQC8AAAAAA==.Hegi:BAAALAADCggICAAAAA==.',Hi='Hida:BAAALAAECgYIDgAAAA==.',Ho='Hotmedaddy:BAABLAAFFIEIAAIKAAIICRhrFwCjAAAKAAIICRhrFwCjAAAAAA==.',Hu='Hunam:BAAALAAECgYIEAAAAA==.',['Há']='Hárthór:BAABLAAECoEgAAIdAAgI8R8rAwD1AgAdAAgI8R8rAwD1AgAAAA==.',Ia='Iamhigh:BAAALAAECgYIBgABLAAECggIJgAWAHQiAA==.',Ie='Iex:BAABLAAECoEVAAIaAAcI7RnjNgAnAgAaAAcI7RnjNgAnAgAAAA==.',If='Ifron:BAAALAADCgYIDQAAAA==.',In='Inkemannek:BAAALAADCgcIBwAAAA==.Inkman:BAAALAAECgQICQAAAA==.',Is='Isizuku:BAABLAAECoEYAAIeAAcIiRUVFQDiAQAeAAcIiRUVFQDiAQAAAA==.',Iv='Ivotem:BAAALAADCgcIBwABLAAECgYIBgAHAAAAAA==.Ivøry:BAAALAADCgMIAwAAAA==.',['Iê']='Iêx:BAABLAAECoEWAAIEAAYIiRzSRwDeAQAEAAYIiRzSRwDeAQAAAA==.',Ja='Jahi:BAAALAADCggICAAAAA==.Jarli:BAABLAAECoEnAAMTAAgIPRtjFQBRAgATAAcI9xxjFQBRAgANAAgIERjHVgDgAQAAAA==.',Je='Jesera:BAAALAAECgQIBgAAAA==.',Ji='Jiray:BAABLAAECoEeAAMcAAgIhR7GDwBFAgAcAAgIhR7GDwBFAgAYAAEIHwbCVAEuAAAAAA==.',Jo='Joeyderulo:BAAALAAECgYIBgAAAA==.',Ju='Julmara:BAAALAAECggIDwAAAA==.Juné:BAAALAAECgYICQAAAA==.Justd:BAAALAAECgMIAwAAAA==.Justicow:BAAALAADCgcIBwAAAA==.',Ka='Kardak:BAAALAADCgcIBwAAAA==.Kashmirr:BAAALAAECgYICQABLAAECggIGQAKAGAcAA==.Kathleya:BAABLAAECoEWAAIUAAgIPQlVtwBVAQAUAAgIPQlVtwBVAQAAAA==.Katzenchef:BAAALAADCggICAAAAA==.Kavoth:BAAALAADCgIIAgAAAA==.',Ke='Kekvin:BAAALAAECgUIBQAAAA==.Kekwin:BAABLAAECoEiAAIGAAgIDyQQCwAxAwAGAAgIDyQQCwAxAwAAAA==.Kenergy:BAABLAAECoEpAAIVAAgI/RtNKgCRAgAVAAgI/RtNKgCRAgAAAA==.Kevin:BAAALAAECgQIBgABLAAECggIIgAGAA8kAA==.Kevlarknight:BAABLAAECoEgAAMcAAgIGB4dCADFAgAcAAgIox0dCADFAgAIAAYIdxZsMQCVAAABLAAECggIIgAGAA8kAA==.',Kh='Khorija:BAAALAAECggIBgAAAA==.',Kn='Knille:BAAALAAECggICwAAAA==.Knutderbär:BAAALAAECgYIDwAAAA==.',Ko='Kochen:BAAALAAECggICAAAAA==.',Kr='Kretock:BAAALAAECgIIAgAAAA==.Kroqgar:BAAALAADCggIDwAAAA==.Kruptschuk:BAAALAAECgcIEAAAAA==.Krônôs:BAABLAAECoEoAAIfAAgIwiABEwBxAgAfAAgIwiABEwBxAgAAAA==.',Ku='Kuhtwo:BAAALAADCggICAAAAA==.',Kv='Kvedu:BAABLAAECoEmAAQWAAgIdCLTBgDgAgAWAAgI6R7TBgDgAgAGAAcItRpUOgAjAgAXAAEIVBeDNABLAAAAAA==.',Ky='Kyana:BAAALAAECgcIBAAAAA==.',['Kî']='Kîth:BAAALAAECgIIBAAAAA==.Kîwîsâft:BAAALAAECgEIAQAAAA==.',La='Lamirá:BAAALAADCgcIBwAAAA==.Lanz:BAAALAAFFAIIBAAAAA==.Laquat:BAAALAAECgYIDAABLAAECgYIFwAEAEQeAA==.Laquatqt:BAABLAAECoEXAAIEAAYIRB6dPwD4AQAEAAYIRB6dPwD4AQAAAA==.Layat:BAAALAAECgIIBAAAAA==.',Le='Lesco:BAAALAADCgcIDAAAAA==.',Li='Lighthearted:BAAALAAECgMIAwABLAAECggICAAHAAAAAA==.Liilandi:BAAALAAECgcIDQAAAA==.Liloh:BAAALAAECgYICQAAAA==.Limead:BAAALAADCgEIAQABLAAECgQIBgAHAAAAAA==.Linali:BAAALAADCgcIEQABLAAECggICAAHAAAAAA==.Linoxis:BAABLAAECoEeAAITAAgICxmZEwBiAgATAAgICxmZEwBiAgAAAA==.',Lo='Lorpendium:BAABLAAECoElAAIFAAgIch3zKQB1AgAFAAgIch3zKQB1AgAAAA==.Losty:BAAALAAECggIAwAAAA==.Lothâire:BAAALAAECggIBgAAAA==.',Lu='Lunharia:BAAALAAECgYIEAABLAAECggIDgAHAAAAAA==.Lunri:BAAALAAECgYIBwABLAAECggIIwACAJQfAA==.Luxarion:BAAALAAECggIDgAAAA==.',['Lé']='Lévaria:BAABLAAECoEdAAIFAAgI5hqTRQAPAgAFAAgI5hqTRQAPAgAAAA==.',Ma='Maddalene:BAAALAADCgMIAwAAAA==.Madeuce:BAAALAAECgYIDAAAAA==.Madiras:BAAALAADCgYIBgAAAA==.Madquat:BAAALAAECgYIDQAAAA==.Maligno:BAAALAADCgQIBAAAAA==.Malîgnô:BAAALAAECgEIAQAAAA==.Massedk:BAAALAADCgcIBwAAAA==.Massewarri:BAAALAAECgUIBgAAAA==.Maxia:BAAALAADCgUIBQAAAA==.Maxilia:BAABLAAECoEiAAIFAAgIzRs8LQBnAgAFAAgIzRs8LQBnAgAAAA==.Mazeltov:BAAALAAECgMICwAAAA==.Mazikean:BAAALAAECggIBwAAAA==.',Me='Meados:BAAALAADCggICAABLAAECgcIFwAVANsUAA==.Medion:BAAALAAECgIIAgAAAA==.Mellu:BAAALAAECgYIBgAAAA==.Melv:BAAALAADCgYICgAAAA==.Mephizto:BAAALAADCgEIAQABLAAECgUIBQAHAAAAAA==.Merun:BAAALAADCgUICQAAAA==.Mexl:BAAALAADCgIIAgABLAAECgcIEgAHAAAAAA==.',Mf='Mfmf:BAAALAADCggIDQAAAA==.',Mi='Minax:BAABLAAECoElAAITAAgIcx6NCQDmAgATAAgIcx6NCQDmAgAAAA==.Mindrea:BAACLAAFFIEHAAMcAAMIYSFIAwAsAQAcAAMIYSFIAwAsAQAYAAIIKBKbSgCOAAAsAAQKgSwAAxwACAiOJGcCAD4DABwACAhsI2cCAD4DABgACAjFI4McAOACAAAA.',Mo='Moníqué:BAAALAAECgcIEAAAAA==.Moonydude:BAAALAAECgQIAQAAAA==.Moonyhunt:BAAALAADCgIIAgAAAA==.Moralf:BAABLAAECoEfAAIGAAgIpRvBHQC3AgAGAAgIpRvBHQC3AgABLAAECggIMwAVAHgkAA==.',My='Mylildk:BAAALAAECgEIAQAAAA==.',['Mâ']='Mâjorlazer:BAAALAAECggIDgAAAA==.Mâzîkêên:BAAALAAECgYIEQABLAAECggIBwAHAAAAAA==.',['Mø']='Møin:BAAALAAECgIIAgAAAA==.',Na='Nandaleè:BAAALAAFFAIIAgAAAA==.Nasadh:BAACLAAFFIEHAAIVAAMIIw5fFQDiAAAVAAMIIw5fFQDiAAAsAAQKgTMAAhUACAh4JCcSABMDABUACAh4JCcSABMDAAAA.Natot:BAABLAAECoEZAAQWAAgIuhlvGQAQAgAWAAgIuhlvGQAQAgAXAAIIAgykPQA0AAAGAAEIQAg53wAtAAAAAA==.',Ne='Neiva:BAAALAAFFAIIBAAAAA==.Nekronomikos:BAAALAADCggICAAAAA==.Neroz:BAAALAAECgIIBAAAAA==.Nesuko:BAAALAADCgYIBgABLAAECggIEQAHAAAAAA==.Netsend:BAABLAAECoEfAAIEAAcIbBSbWgCoAQAEAAcIbBSbWgCoAQAAAA==.Nexxidus:BAABLAAECoEtAAMGAAgIwiH0FgDiAgAGAAgIOSH0FgDiAgAWAAcImB9KEwBEAgAAAA==.',Ni='Niixon:BAABLAAECoEVAAMgAAYITgltPQD0AAAgAAYITgltPQD0AAAZAAYIFghSSQDwAAAAAA==.Nirak:BAAALAAECggICAAAAA==.',No='Noshgun:BAABLAAECoEnAAIIAAgIrSJIBAAcAwAIAAgIrSJIBAAcAwAAAA==.Novano:BAAALAAECgMIAwAAAA==.',Nu='Nuke:BAAALAAECgUICAABLAAFFAMICgAVAFkKAA==.',Ny='Nyai:BAAALAADCggIIgABLAAECggICAAHAAAAAA==.Nyatsu:BAAALAADCgcIAgABLAAECgcIHQAeAJ8dAA==.Nyxie:BAAALAADCggIDwAAAA==.',Oc='Océané:BAAALAAECgYIBgABLAAECggICAAHAAAAAA==.',Od='Odufuel:BAAALAAECgcICwAAAA==.',Oh='Ohaa:BAAALAADCggICAAAAA==.',Ol='Olivia:BAAALAAECgUICAABLAAFFAUIEgAEAKAUAA==.',Om='Omawaltraut:BAAALAADCggICAAAAA==.Omeno:BAAALAAECgEIAQAAAA==.',On='Onebuttonman:BAABLAAECoElAAIfAAgI2xl8FwBHAgAfAAgI2xl8FwBHAgAAAA==.Onlycloakz:BAABLAAECoEXAAIhAAgI4xgvEQCMAgAhAAgI4xgvEQCMAgAAAA==.Ony:BAAALAADCgcIDgAAAA==.',Or='Ortì:BAAALAADCgcIBwAAAA==.Orundar:BAAALAAECgYIDwAAAA==.',Os='Ose:BAAALAADCggIDQABLAAECgYICwAHAAAAAA==.',Pa='Palerino:BAAALAADCgUIBwAAAA==.Parac:BAAALAADCgcIBwAAAA==.',Pe='Pentacore:BAAALAAECgMIAwAAAA==.Peppo:BAABLAAECoEUAAMSAAgIgiBZBADrAgASAAgIgiBZBADrAgARAAQIEw4bRQDyAAAAAA==.',Ph='Pharmaboy:BAAALAADCggIFAAAAA==.',Pl='Plaguebearer:BAAALAAECgIIAgAAAA==.Plüschbombe:BAACLAAFFIEFAAIEAAMIHRVTFADOAAAEAAMIHRVTFADOAAAsAAQKgRsAAwQABwgOHgQlAFwCAAQABwgOHgQlAFwCAAwAAQiGFYCoAD0AAAAA.',Pr='Primrose:BAAALAAECggIDwAAAA==.Progon:BAAALAADCggIEQAAAA==.Protector:BAAALAADCggIEwAAAA==.',Pu='Puddlehoof:BAAALAAECgYIBgABLAAECgYIBgAHAAAAAA==.Punkschami:BAAALAADCggICAAAAA==.Puppenmacher:BAAALAADCggIDwABLAAFFAIIAgAHAAAAAA==.',Py='Pyranius:BAAALAADCgcIDQAAAA==.',Ra='Racé:BAABLAAECoEkAAITAAgIJyA6CwDMAgATAAgIJyA6CwDMAgAAAA==.Ragnarisa:BAABLAAECoEUAAMRAAcI1w5zLQCWAQARAAcI1w5zLQCWAQAiAAYIgwWsEADOAAAAAA==.Rammer:BAAALAADCggIDgAAAA==.Ramus:BAAALAAECgEIAQAAAA==.Rantaladar:BAABLAAECoEXAAMaAAcI6Bv1MwA1AgAaAAcI6Bv1MwA1AgAfAAEIgRwUewAtAAABLAAECggIJAADAC8UAA==.Raosh:BAAALAADCgEIAQAAAA==.',Re='Regîna:BAAALAADCgYIEgAAAA==.Reku:BAAALAADCgIIAwABLAAECgUIBQAHAAAAAA==.Rey:BAAALAAECgcIDAAAAA==.Reyna:BAAALAAECgUICAAAAA==.',Rh='Rhazin:BAAALAAECgcIDwABLAAECggIHgAUAFkeAA==.Rhuno:BAAALAAECgYIDQAAAA==.',Ri='Rialis:BAAALAAECggICAAAAA==.Ripplycips:BAAALAAECgYIEQAAAA==.',Ro='Rosada:BAAALAAECgYIDwAAAA==.Rotznaga:BAAALAAECgQIBAAAAA==.Roxsy:BAAALAADCgUIBQABLAAECgYICgAHAAAAAA==.Roxxz:BAACLAAFFIEIAAIGAAMI/hjmGAD0AAAGAAMI/hjmGAD0AAAsAAQKgS4AAgYACAiQI48MACcDAAYACAiQI48MACcDAAAA.',Ru='Rujunoy:BAAALAADCggIBAAAAA==.Rusthex:BAAALAADCgcIBwAAAA==.',Sa='Saizz:BAABLAAECoEdAAIbAAcIWh6nJQAsAgAbAAcIWh6nJQAsAgAAAA==.Salmara:BAABLAAECoEgAAIbAAgI8xEALQD/AQAbAAgI8xEALQD/AQAAAA==.Sarozp:BAAALAAECggICAAAAA==.',Sc='Schlackesven:BAAALAADCgYIBgAAAA==.Schokan:BAAALAADCggICAAAAA==.Scrubbï:BAABLAAECoEZAAMDAAgI7B1lMQD6AQADAAgI7B1lMQD6AQAbAAEIWwzvhQBAAAAAAA==.',Se='Selfhated:BAAALAADCgcICwAAAA==.Selthantar:BAABLAAECoEVAAIFAAYIjA0MrQAmAQAFAAYIjA0MrQAmAQAAAA==.Semiaramis:BAAALAAECggIDwAAAA==.Senan:BAABLAAECoEUAAIZAAgIjxbnGQAUAgAZAAgIjxbnGQAUAgAAAA==.Sento:BAAALAAECgYIDAABLAAECggILgAUALMgAA==.Sequana:BAAALAAECgYIBgAAAA==.Sethidrood:BAAALAADCgUIBwABLAAFFAIIAgAHAAAAAA==.Sethimage:BAAALAADCgQIBAABLAAFFAIIAgAHAAAAAA==.Sethishami:BAAALAAFFAIIAgAAAA==.Sethiwarri:BAAALAAECgUICwABLAAFFAIIAgAHAAAAAA==.Sethunter:BAABLAAECoEgAAMCAAgIhR7wEgC7AgACAAgIhR7wEgC7AgAFAAIIvxUr+wBnAAABLAAFFAIIAgAHAAAAAA==.Settschmo:BAAALAADCgQIBgAAAA==.',Sh='Shaozen:BAABLAAECoEnAAIBAAgI5RgAEAAvAgABAAgI5RgAEAAvAgAAAA==.Sharilyn:BAABLAAECoEdAAIjAAgIUSIzBAABAwAjAAgIUSIzBAABAwAAAA==.Sharybdis:BAAALAAECgYIDwAAAA==.Shayera:BAABLAAECoEfAAIPAAgIPhxoEgBhAgAPAAgIPhxoEgBhAgAAAA==.Shaólín:BAAALAAECgYIBgABLAAECggIJgAWAHQiAA==.Shelbee:BAAALAAECgYIBgAAAA==.Sherria:BAAALAAECggIAgAAAA==.Shootah:BAAALAADCgcIDAAAAA==.Shurkul:BAAALAAECgIIAQAAAA==.Sházam:BAAALAADCgcICAAAAA==.Shîne:BAAALAAECgIIAgAAAA==.',Si='Si:BAAALAAECgcICwAAAA==.Sicario:BAAALAADCgcIBwAAAA==.Silènce:BAAALAAECggIDwAAAA==.Sinnx:BAAALAADCgYIBwAAAA==.Sinthoràs:BAAALAADCggIFgAAAA==.',Sn='Snaliv:BAABLAAECoErAAMhAAgIPBvuGAA+AgAhAAgIPBvuGAA+AgAjAAMIXQ5xNACoAAAAAA==.Sner:BAAALAADCgQIBAAAAA==.Snickerz:BAAALAADCggICAAAAA==.',So='Solaclypsa:BAAALAADCggIDwAAAA==.',Sp='Spártacus:BAAALAADCggICAABLAAECggIMwAVAHgkAA==.',St='Stockanwand:BAAALAADCggIDQAAAA==.Stormorc:BAAALAAECgUIEAAAAA==.Strahlemann:BAABLAAECoEWAAMgAAgIsxSaMABFAQAgAAgIsxSaMABFAQAUAAYI1Qjx1AAdAQAAAA==.Strandlümmel:BAABLAAECoEWAAIFAAgIHx6wPAAtAgAFAAgIHx6wPAAtAgAAAA==.',Su='Supreme:BAAALAAECgYIBgAAAA==.Surrak:BAAALAAECgIIAgAAAA==.Sutella:BAAALAAECgQIBAAAAA==.',Sy='Synopsis:BAAALAADCggICAAAAA==.Syrelia:BAABLAAECoEdAAITAAgIQRnEJgDKAQATAAgIQRnEJgDKAQAAAA==.',['Sâ']='Sândrô:BAAALAAECggICAAAAA==.',['Sé']='Séthiel:BAAALAADCggICAABLAAFFAIIAgAHAAAAAA==.',Ta='Tagwandler:BAABLAAECoEXAAIVAAcI2xSPagDFAQAVAAcI2xSPagDFAQAAAA==.Talirona:BAAALAADCggIEAAAAA==.Taochi:BAAALAAECgUIBgABLAAECgYIBgAHAAAAAA==.Taros:BAACLAAFFIEHAAIMAAMIoQ7pEQDlAAAMAAMIoQ7pEQDlAAAsAAQKgR4AAgwACAh1IboPAP8CAAwACAh1IboPAP8CAAAA.Tascha:BAAALAADCgIIAgAAAA==.Taztaxes:BAAALAAECgcIDQAAAA==.',Tc='Tched:BAAALAADCgQIBQAAAA==.',Te='Temyrel:BAABLAAECoEVAAIkAAcI8xVJCwDKAQAkAAcI8xVJCwDKAQAAAA==.Tenchi:BAAALAADCgEIAQAAAA==.Teninchtaker:BAAALAAECgYICwABLAAECgYIDQAHAAAAAA==.',Th='Thedestroya:BAABLAAECoEZAAIQAAgI9hTqCwANAgAQAAgI9hTqCwANAgAAAA==.Theraila:BAAALAADCgYIBgAAAA==.Thrazor:BAAALAADCggICwABLAAECgYIFQAFAPgaAA==.Throllk:BAAALAADCggIDQAAAA==.Thyorn:BAAALAAECgYICwAAAA==.',Ti='Timoo:BAABLAAECoEZAAMKAAgIYBwaMQDsAQAKAAgIYBwaMQDsAQAlAAMIuAx5JQB7AAAAAA==.Tiraja:BAAALAAECggIEQAAAA==.',Tm='Tmoo:BAAALAADCgYIAwABLAAECggIGQAKAGAcAA==.',To='Toirin:BAAALAADCgYIBgABLAAECgUIDwAHAAAAAA==.Tomatênsaft:BAAALAADCgcIBwAAAA==.',Tr='Troxxas:BAAALAAECgYICgAAAA==.Troxxs:BAAALAAECgMIAwABLAAECgYICgAHAAAAAA==.Trìx:BAABLAAECoEuAAMUAAgIsyCEHQDfAgAUAAgIJiCEHQDfAgAgAAgIvRwAAAAAAAAAAA==.',['Tý']='Týr:BAAALAADCggIFAAAAA==.',Uh='Uhaa:BAAALAADCggICAAAAA==.',Ul='Ulffi:BAAALAADCgQIBAAAAA==.Ulffoonso:BAAALAADCggIDAAAAA==.Ultrawookie:BAABLAAECoEXAAIYAAgIER8WNwByAgAYAAgIER8WNwByAgAAAA==.',Un='Undercover:BAAALAAECgYIBgABLAAFFAMICgAVAFkKAA==.Underiya:BAAALAAECgYIBgABLAAECggICAAHAAAAAA==.',Us='Uschï:BAAALAAECgYICwAAAA==.User:BAAALAADCgYIDAAAAA==.',Ut='Utopia:BAABLAAECoEnAAIZAAgIdxwFDQCRAgAZAAgIdxwFDQCRAgAAAA==.',Va='Valasse:BAABLAAECoEqAAMDAAgIthvJGwB4AgADAAgIthvJGwB4AgAbAAcI0QfyTwBSAQAAAA==.Valkodor:BAAALAADCggIEAAAAA==.Vangance:BAAALAAECgYICwAAAA==.',Ve='Vendetta:BAAALAAECggIBgABLAAECggIJwABAOUYAA==.Vesíca:BAAALAAFFAIIAgABLAAECggIMwAVAHgkAA==.',Vi='Vinkavinka:BAAALAAECggICAAAAA==.Vizuna:BAAALAADCgcIDgAAAA==.',Vu='Vulpinia:BAAALAADCgYICAAAAA==.Vulpix:BAAALAAECgYIBgABLAAFFAMIDQAaADodAA==.',['Ví']='Vípea:BAAALAAECggICAAAAA==.',Wa='Warrxo:BAAALAAECgEIAQAAAA==.Waurox:BAABLAAECoEVAAIFAAYI+Br0bACnAQAFAAYI+Br0bACnAQAAAA==.',We='Weberdin:BAAALAAECgYIDAAAAA==.',Wh='Whiskysour:BAAALAAECgcIEgAAAA==.',Wi='Windywalker:BAAALAADCggICAAAAA==.',Wu='Wutelfe:BAAALAAFFAIIAgAAAA==.',Xa='Xal:BAAALAAFFAIIAgAAAA==.',Xe='Xerogon:BAAALAADCgcIBAAAAA==.',Xi='Xibalbá:BAAALAADCgYIBgAAAA==.',Xu='Xuan:BAABLAAECoEXAAIPAAgI9BPCIQDAAQAPAAgI9BPCIQDAAQAAAA==.',Xy='Xyllius:BAACLAAFFIEGAAIcAAMIdg/sBQD0AAAcAAMIdg/sBQD0AAAsAAQKgSIAAhwACAhuIisEABQDABwACAhuIisEABQDAAAA.',Ya='Yannel:BAABLAAECoEfAAIIAAcISBsgEAAYAgAIAAcISBsgEAAYAgAAAA==.Yarîîa:BAAALAAECgIIAgAAAA==.',Yu='Yukino:BAAALAAECgIIAwABLAAECggIJAADAC8UAA==.Yukisa:BAAALAAECggIEQAAAA==.',Za='Zaiaku:BAAALAAECgUICwAAAA==.',Ze='Zebolon:BAAALAADCgcICwAAAA==.',Zl='Zlâtan:BAAALAADCgYIBgAAAA==.',Zu='Zuulok:BAAALAAECggICAAAAA==.',Zy='Zyphyros:BAAALAAECggIEgAAAA==.',['Zà']='Zàr:BAAALAAECggICAAAAA==.',['Âr']='Ârês:BAAALAAECgYICAAAAA==.',['Âs']='Âshby:BAAALAAECgYICgABLAAECggIBwAHAAAAAA==.',['Çe']='Çesto:BAAALAADCggICAAAAA==.',['Øl']='Ølaf:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end