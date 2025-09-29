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
 local lookup = {'Priest-Discipline','Priest-Holy','Hunter-Marksmanship','Rogue-Subtlety','Druid-Restoration','Druid-Feral','Unknown-Unknown','Warlock-Affliction','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Warrior-Arms','Warrior-Fury','DeathKnight-Frost','Priest-Shadow','Warlock-Demonology','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Druid-Guardian','Shaman-Restoration','Rogue-Outlaw','Shaman-Elemental','DeathKnight-Blood','DeathKnight-Unholy','Mage-Arcane','Monk-Brewmaster','Warrior-Protection','Rogue-Assassination','Shaman-Enhancement','Druid-Balance','Monk-Windwalker','Mage-Frost',}; local provider = {region='EU',realm='ConseildesOmbres',name='EU',type='weekly',zone=44,date='2025-09-23',data={Aa='Aalba:BAABLAAECoEUAAMBAAYIcw9/FAArAQABAAYIYw5/FAArAQACAAYI3whUbAAPAQAAAA==.',Ab='Abd:BAABLAAECoEeAAIDAAgI4CFwDwDZAgADAAgI4CFwDwDZAgAAAA==.Abdaroth:BAACLAAFFIEUAAIEAAYI5R7LAABfAgAEAAYI5R7LAABfAgAsAAQKgS0AAgQACAiHJckAAG8DAAQACAiHJckAAG8DAAAA.Abdoul:BAAALAAECgcIBwAAAA==.',Ad='Adiard:BAABLAAECoEhAAIDAAgIqhoJHABsAgADAAgIqhoJHABsAgAAAA==.',Ae='Aerïth:BAABLAAECoEfAAMFAAcIjB5cGgBlAgAFAAcIjB5cGgBlAgAGAAUImwzEKQABAQAAAA==.Aeternia:BAAALAAECgcICQABLAAECggIEAAHAAAAAA==.',Ah='Ahé:BAAALAAECgEIAQABLAAECgYIJgAHAAAAAQ==.',Ak='Akeeyah:BAABLAAECoEZAAIIAAcIpB15BQBuAgAIAAcIpB15BQBuAgABLAAFFAMIBwAJAF8XAA==.',Al='Alistar:BAAALAAECgcIEwABLAAECgcIFgAKAHckAA==.Almiraj:BAAALAAECgIIAgAAAA==.Alucar:BAAALAAECgYIEwAAAA==.',Am='Amnesià:BAAALAAECgYIDAAAAA==.',An='Anarkia:BAAALAAECgQICAAAAA==.Anasteros:BAAALAAECgEIAQAAAA==.Angedie:BAAALAADCgYIBgABLAAECggIJgALAJkYAA==.Anita:BAAALAADCgIIAgAAAA==.Anoeth:BAAALAADCggICwABLAAECgMIBwAHAAAAAA==.Anosapin:BAAALAAECggIDwAAAA==.',Ao='Aoqin:BAABLAAECoEiAAMMAAcIuhG8CAC0AQAMAAcIKRG8CAC0AQANAAUIxA3HQgD/AAAAAA==.',Ap='Apnwx:BAAALAAECgYIEwAAAA==.Apnwy:BAAALAAECgMIAwABLAAECgYIEwAHAAAAAA==.',Ar='Aralÿs:BAACLAAFFIEGAAIDAAIITRY8GACTAAADAAIITRY8GACTAAAsAAQKgRkAAwMABwjCINkhAEECAAMABghkItkhAEECAAoAAQj5FkIEAUUAAAAA.Arbal:BAAALAADCgcIBwABLAAECgYIFQAOAGQUAA==.Ardo:BAAALAAECggIBQAAAA==.Arnek:BAAALAAECggIEwAAAA==.Artirro:BAAALAADCggICQAAAA==.Arüka:BAAALAADCgIIAgAAAA==.',As='Ascaroth:BAAALAAECgQIBQABLAAECgcIFQANAEAOAA==.Ashäa:BAACLAAFFIEHAAICAAMIKCBrCwAaAQACAAMIKCBrCwAaAQAsAAQKgSUAAwIACAgdIlAKAAUDAAIACAgdIlAKAAUDAAEABwjkGjMHABoCAAAA.Aspectdukiki:BAAALAAECgYICQAAAA==.Aspergian:BAABLAAECoEZAAMPAAYIeSW2BgB2AgAPAAYIdyW2BgB2AgAQAAQIphr4fABAAQAAAA==.Aspy:BAABLAAECoElAAICAAgIKgfbVgBVAQACAAgIKgfbVgBVAQAAAA==.Astarius:BAAALAADCggIEwAAAA==.Astranar:BAAALAAECgEIAgAAAA==.',At='Atagloire:BAAALAADCggICwAAAA==.Athäe:BAABLAAECoEoAAIFAAgI5SNEBQAoAwAFAAgI5SNEBQAoAwAAAA==.Atyka:BAAALAAECgcIBwAAAA==.',Au='Aurphèe:BAAALAAECgEIAQABLAAECgYIJgAHAAAAAQ==.Authority:BAABLAAECoEYAAIRAAgI/xvJMgB/AgARAAgI/xvJMgB/AgAAAA==.',Av='Avarosa:BAAALAADCgcIBwAAAA==.Average:BAAALAADCgcIBwAAAA==.',Aw='Awhkì:BAAALAAECgEIAQABLAAECgYIJgAHAAAAAQ==.Awki:BAAALAADCgUIDQABLAAECgYIJgAHAAAAAA==.',Ay='Aygon:BAAALAADCggICwAAAA==.',Az='Azaran:BAABLAAECoEeAAISAAcISBnyJwAaAgASAAcISBnyJwAaAgAAAA==.Azaërus:BAACLAAFFIEFAAMTAAMIGAyqFQCIAAALAAMIGAxLKQCbAAATAAIISAWqFQCIAAAsAAQKgScAAxMACAgoIDkIAMYCABMACAirHzkIAMYCAAsABghWGwhDAPsBAAAA.Azhure:BAABLAAECoEdAAISAAgIfCAJDgDwAgASAAgIfCAJDgDwAgAAAA==.Azrãel:BAAALAAFFAIIAgAAAA==.Azzap:BAAALAAECgIIAgAAAA==.Azzaran:BAAALAAECgYIBgAAAA==.',['Aé']='Aélys:BAABLAAECoEYAAISAAYIzQmqVgAuAQASAAYIzQmqVgAuAQAAAA==.',Ba='Babøun:BAAALAADCgUIBgAAAA==.Baguetta:BAAALAAECgcIEgAAAA==.Bala:BAAALAADCgMIAwAAAA==.Balycouli:BAAALAADCggICAAAAA==.Barador:BAAALAADCggIIQAAAA==.Barbapapaff:BAAALAAECgYIBwABLAAECgcIEwAHAAAAAA==.Barbiekungfu:BAEALAAECgMIAwABLAAFFAMICwAUAEIjAA==.',Be='Behemaute:BAAALAAECgYIDQAAAA==.Believe:BAAALAAECgYIDAAAAA==.Belém:BAAALAADCgUIBQAAAA==.',Bi='Bigbroo:BAAALAADCgIIAgAAAA==.Bigmamelle:BAAALAADCggICAAAAA==.Bigmoine:BAAALAADCgcIBwAAAA==.Bignoobars:BAAALAAECgEIAQAAAA==.Bigoun:BAAALAAECgYIBgAAAA==.Bigskiper:BAAALAADCgcIBwAAAA==.Bigwyrm:BAAALAADCgUIBQAAAA==.',Bo='Bobketchup:BAAALAAECgYIDgAAAA==.',Br='Brossadam:BAABLAAECoEWAAIVAAgIMiKJDwAgAwAVAAgIMiKJDwAgAwAAAA==.Brotheur:BAAALAADCgcIDgAAAA==.',Bu='Bugzit:BAAALAADCgIIAgABLAAECgYIDAAHAAAAAA==.',['Bä']='Bärlok:BAAALAADCgcIBwAAAA==.',['Bè']='Bèást:BAACLAAFFIEIAAMQAAQIjhNSCgBSAQAQAAQIjhNSCgBSAQAPAAEIOgVzBwA9AAAsAAQKgToAAxAACAh6I6sJAD0DABAACAhBI6sJAD0DAA8ABwh9IdIFAI8CAAAA.',Ca='Caiitlyne:BAAALAADCgcICQABLAAECgcIFQANAEAOAA==.Camyne:BAAALAAECgcIEwAAAA==.Candra:BAABLAAECoEjAAIWAAgI7STEAgBAAwAWAAgI7STEAgBAAwAAAA==.Carmila:BAABLAAECoEWAAICAAYInRzwMgDvAQACAAYInRzwMgDvAQAAAA==.Carnage:BAABLAAECoEUAAIKAAcI3hqSRQAIAgAKAAcI3hqSRQAIAgAAAA==.Caylia:BAAALAADCggIFQABLAAECgcIFQANAEAOAA==.',Ce='Ceriize:BAAALAADCggICAAAAA==.',Ch='Chamanheal:BAAALAADCgQIAQAAAA==.Chibroly:BAABLAAECoEXAAMJAAYIASZeLgCOAgAJAAYI2iVeLgCOAgAXAAEIjyV/UABsAAAAAA==.Chienpo:BAAALAADCggICAABLAAECggIIwAWAO0kAA==.Châcal:BAAALAAECgIIAgAAAA==.',Co='Coeurblanc:BAAALAADCgMIAwAAAA==.Cordelys:BAAALAAECgQICwAAAA==.',Cr='Creamy:BAAALAADCgIIAgAAAA==.',Cy='Cyparius:BAAALAADCggICAAAAA==.',['Cé']='Cézanne:BAABLAAECoEkAAMGAAgIQCLgAwAcAwAGAAgIQCLgAwAcAwAYAAEI6Aq+LgAkAAAAAA==.',Da='Daedraas:BAAALAAECgEIAQABLAAECgMIAgAHAAAAAA==.Daléora:BAACLAAFFIEFAAIZAAII5xKhLACAAAAZAAII5xKhLACAAAAsAAQKgSYAAhkACAjHG2IkAFsCABkACAjHG2IkAFsCAAAA.Damuuth:BAAALAAECgQICAAAAA==.',De='Deathdemon:BAABLAAECoEeAAIaAAgIZQvLCQDBAQAaAAgIZQvLCQDBAQAAAA==.Deepshii:BAAALAAECgYIEAAAAA==.Deloise:BAABLAAECoEoAAIUAAgIChXWGwABAgAUAAgIChXWGwABAgAAAA==.Delyna:BAAALAADCgcIDQABLAAECgcIIgAMALoRAA==.Desdez:BAAALAADCgQIBQABLAAECgYICwAHAAAAAA==.Devak:BAAALAAECgYICwAAAA==.Devilskîng:BAAALAAECgcIEwAAAA==.',Di='Diplopie:BAABLAAECoEhAAIJAAgIQBcPRABCAgAJAAgIQBcPRABCAgAAAA==.Dipstick:BAAALAAECgIIAgAAAA==.',Dk='Dkthlon:BAABLAAECoEcAAIRAAgIeRmEPwBVAgARAAgIeRmEPwBVAgAAAA==.',Dr='Dracqween:BAAALAAECgUICAAAAA==.Dragorkk:BAABLAAECoElAAIDAAcI4iQrDQDuAgADAAcI4iQrDQDuAgAAAA==.Drakare:BAAALAADCgcIAwABLAAECgcIFQANAEAOAA==.Drakorn:BAAALAAECgYIBgAAAA==.Drathen:BAAALAAECggIEQAAAA==.Dreigone:BAAALAADCgcIBwAAAA==.Droogo:BAABLAAECoEVAAINAAcIQA7vLACUAQANAAcIQA7vLACUAQAAAA==.Droom:BAAALAADCgYIBgAAAA==.Drpolaton:BAAALAAECgcIDwABLAAFFAYIHAANAGEgAA==.Druidee:BAAALAAECgMIBQAAAA==.Druidmoine:BAAALAADCgYIBgAAAA==.Drøogo:BAAALAADCgYICgABLAAECgcIFQANAEAOAA==.',Du='Dumbe:BAABLAAECoEWAAMZAAgIxSLQBwARAwAZAAgIxSLQBwARAwAbAAQItRl0aQBBAQAAAA==.',['Dé']='Dédémone:BAAALAAECgcIDQABLAAECggIHgAaAGULAA==.Démarate:BAAALAAECgYIBgAAAA==.',Ea='Eauskøur:BAAALAAECgYICQABLAAECggIFgAFAM4eAA==.',Eg='Egeanine:BAAALAAECgIIAgAAAA==.',Ek='Ekzay:BAABLAAECoEWAAIVAAgIZxbQPQA9AgAVAAgIZxbQPQA9AgAAAA==.Ekzaylol:BAAALAAECggICAABLAAECggIFgAVAGcWAA==.Ekzayxd:BAAALAAECggIEQABLAAECggIFgAVAGcWAA==.',El='Elementö:BAAALAADCggIEQAAAA==.Elendél:BAAALAADCggIFwAAAA==.Elhatno:BAAALAAECgMIBwAAAA==.Elmaev:BAAALAAECgIIAgAAAA==.Elnia:BAAALAAECgcIDgAAAA==.Elnïa:BAAALAAECggIEwAAAA==.Elsariel:BAAALAAECgYICwAAAA==.Elsheitan:BAAALAAECgIIAgAAAA==.Eltak:BAAALAAECggIDgAAAA==.Elzbieta:BAABLAAECoEgAAQcAAgIgRpUDgAyAgAcAAgIgRpUDgAyAgAdAAMI8QSUQwCOAAARAAIIyAMaPQFIAAAAAA==.',Em='Emeuha:BAABLAAECoEaAAMZAAgIFhpOKABKAgAZAAgIFhpOKABKAgAbAAQIZAcMhwC7AAAAAA==.Emmy:BAAALAAECgYIEwAAAA==.',En='Eneïde:BAABLAAECoEeAAIJAAcIaAgGrgBiAQAJAAcIaAgGrgBiAQAAAA==.',Eo='Eolias:BAABLAAECoEgAAIeAAgI7QVQhgBVAQAeAAgI7QVQhgBVAQABLAABCgEIAQAHAAAAAA==.',Ep='Epitaphe:BAAALAAECgcIBwABLAAFFAUIDQAZAK8TAA==.',Ev='Evengel:BAAALAAECggIDAAAAA==.',Fa='Fantome:BAAALAAECgYIBgABLAAECgYIDAAHAAAAAA==.Farblard:BAAALAADCgcIDAAAAA==.Farëndh:BAAALAAECgEIAQAAAA==.Fatsac:BAAALAAECgMIAwAAAA==.',Fi='Fildentaire:BAAALAAECgQICQABLAAECggIFgAVADIiAA==.Filzareis:BAAALAADCggIIAAAAA==.',Fo='Foncedslemur:BAAALAAECgMIBQAAAA==.Fourure:BAAALAADCgUIBQAAAA==.',Fr='Frastrixs:BAAALAADCgcIDAAAAA==.',Ga='Gadwina:BAAALAADCggICAAAAA==.Gadwyna:BAAALAADCggIBwAAAA==.Gaianne:BAABLAAECoEdAAIOAAcI+h2JCgBdAgAOAAcI+h2JCgBdAgAAAA==.Galateia:BAAALAAECgYICwAAAA==.Garadak:BAAALAAECgEIAQAAAA==.Garbotank:BAAALAAECgQIBQAAAA==.',Gn='Gnominay:BAAALAAECgIIAgABLAAECgYIEwAHAAAAAA==.',Go='Gorbul:BAAALAADCgYIBgAAAA==.Gorgrim:BAAALAAECgEIAQABLAAECgYIEQAHAAAAAA==.Gorgron:BAAALAADCgIIAgAAAA==.',Gr='Grogmar:BAABLAAECoEcAAIRAAgILAqciwCoAQARAAgILAqciwCoAQAAAA==.Grohlar:BAAALAAECgYIBgAAAA==.Grohnai:BAAALAADCgUIBQAAAA==.Groms:BAAALAADCggIDgAAAA==.Grossemite:BAABLAAECoEWAAIKAAcIdySLIACeAgAKAAcIdySLIACeAgAAAA==.Gríef:BAAALAADCggIBQABLAAFFAQIBAAHAAAAAA==.Grîbouille:BAABLAAECoEcAAICAAgIXB1vFQCiAgACAAgIXB1vFQCiAgAAAA==.Grøldan:BAAALAADCgcIDAAAAA==.Grü:BAAALAADCgcIBwAAAA==.',Gw='Gwedaen:BAAALAAECggIDAAAAA==.Gwenan:BAAALAADCgcIBwAAAA==.Gwoklibre:BAAALAAECgYIDgAAAA==.',Ha='Haersvelg:BAAALAADCggIDgAAAA==.Halarion:BAAALAAECgcIEQAAAA==.Happymheal:BAAALAAECgYIDwAAAA==.Harricovert:BAAALAADCgcIDQAAAA==.Hautdesaine:BAABLAAECoEXAAMRAAcIVBiyXQAFAgARAAcIVBiyXQAFAgAcAAIIJAPcOwA/AAAAAA==.Haxas:BAABLAAECoEbAAILAAcIgxzqMgA/AgALAAcIgxzqMgA/AgAAAA==.',He='Helldarion:BAABLAAECoEUAAMJAAcI+w3qkwCRAQAJAAcI+w3qkwCRAQAUAAII+QFSYwA8AAAAAA==.Hexi:BAABLAAECoEbAAIVAAgISBaFRAAmAgAVAAgISBaFRAAmAgAAAA==.',Hi='Hide:BAAALAADCgYICAAAAA==.',Ho='Holyra:BAAALAADCgcICAAAAA==.Honix:BAAALAAECgEIAQAAAA==.Hortense:BAAALAADCgEIAQAAAA==.Hoxus:BAAALAADCgUIBQABLAAECgcIGwALAIMcAA==.',Hu='Huntizz:BAAALAAECgYIBgAAAA==.',Hy='Hyuna:BAAALAAFFAIIBAAAAA==.',Ib='Ibexphénix:BAACLAAFFIEcAAMNAAYIYSAtAQBWAgANAAYIYSAtAQBWAgAMAAMILxpIAwD1AAAsAAQKgSoAAw0ACAhhJbsGABkDAA0ACAg5JLsGABkDAAwACAgkH98BAOQCAAAA.',Ic='Icandre:BAAALAAECgYIEwAAAA==.',Im='Imaro:BAAALAADCggIDAAAAA==.',In='Inatîa:BAAALAAECgYICgAAAA==.Indika:BAAALAADCggIIQAAAA==.Infernuss:BAAALAAECgQICQAAAA==.',Is='Ishä:BAAALAAECgMIAwAAAA==.',Ja='Javine:BAAALAADCgcIBwABLAAECggIIQADAKoaAA==.',Ji='Jinizz:BAABLAAECoEYAAIfAAcI+hVpHQB4AQAfAAcI+hVpHQB4AQAAAA==.',Jo='Jolyana:BAAALAAECgUICAAAAA==.Joye:BAAALAAECgYICwABLAAECggIGgAWAMMSAA==.',Ju='Justunetaf:BAAALAAECgcIEwAAAA==.Juuki:BAAALAAECgIIAgAAAA==.',['Jï']='Jïzo:BAAALAAECgMIAQAAAA==.',['Jü']='Jürgen:BAAALAAECggIDwAAAA==.',Ka='Kaaltorak:BAAALAADCggICAABLAAECgQICAAHAAAAAA==.Kahd:BAABLAAECoEhAAMTAAgIOxoVDwBsAgATAAgIOxoVDwBsAgALAAIIKRIAvQB6AAAAAA==.Kains:BAAALAAFFAEIAQAAAA==.Kaldiria:BAACLAAFFIEbAAMSAAYITCQrAQB2AgASAAYITCQrAQB2AgACAAIIsw7cIACVAAAsAAQKgSwAAhIACAjaJnAAAJYDABIACAjaJnAAAJYDAAAA.Kalyantsa:BAAALAAECgEIAgABLAAECggIIgACACIfAA==.Kameokami:BAACLAAFFIEVAAIZAAYI6yDcAABYAgAZAAYI6yDcAABYAgAsAAQKgRgAAhkACAiCHiodAH4CABkACAiCHiodAH4CAAAA.Kamoulox:BAABLAAECoEWAAIZAAcIrQ/5eQBQAQAZAAcIrQ/5eQBQAQAAAA==.Kantaï:BAAALAAECgMIBAAAAA==.Karädras:BAAALAAECgIIAgAAAA==.Kashyyk:BAAALAADCgYICQAAAA==.Katerina:BAAALAAECgMIBAAAAA==.Kaôô:BAAALAADCgMIAwAAAA==.',Ke='Kelzal:BAABLAAECoEXAAIVAAgI7ANG1gDQAAAVAAgI7ANG1gDQAAAAAA==.Kern:BAABLAAECoEVAAMOAAYIZBQ6IgARAQAOAAYIZBQ6IgARAQANAAMILgiYTgCLAAAAAA==.Kerodruid:BAAALAADCggIDgABLAAECgQIBwAHAAAAAA==.',Kh='Khazgrol:BAAALAAECgMIAwAAAA==.Khiera:BAABLAAECoEeAAICAAcIGiClGgB9AgACAAcIGiClGgB9AgAAAA==.Khrak:BAABLAAECoEiAAMJAAcISBkWVQATAgAJAAcISBkWVQATAgAXAAQI/g5XQwDBAAAAAA==.Khéliana:BAAALAAECgYIDwAAAA==.',Ki='Kiixt:BAABLAAECoEYAAIQAAgIMhZVLQBOAgAQAAgIMhZVLQBOAgAAAA==.Kiklash:BAAALAADCgcIDgAAAA==.Kin:BAAALAADCgcIDgAAAA==.Kissyfrôtte:BAAALAAECgMIAwAAAA==.',Kl='Klifft:BAABLAAECoEXAAITAAYI5Ak9RAA5AQATAAYI5Ak9RAA5AQAAAA==.Klyesh:BAAALAAECgEIAgAAAA==.',Kn='Knozibul:BAABLAAECoEmAAIJAAgIbyGhFgACAwAJAAgIbyGhFgACAwAAAA==.',Ko='Konveex:BAAALAAECgMIBAAAAA==.Korasek:BAAALAAECgUIDAAAAA==.',Kr='Kreaze:BAACLAAFFIEMAAIQAAQIiBplCQB1AQAQAAQIiBplCQB1AQAsAAQKgSYAAhAACAi6IlgOABoDABAACAi6IlgOABoDAAAA.Krilldur:BAAALAAECgQIBgAAAA==.',Ku='Kura:BAABLAAECoEUAAMWAAYIKRBVLAAaAQAWAAYIYQ9VLAAaAQAVAAQIdg2P2gDEAAAAAA==.',Ky='Kysira:BAAALAAECgEIAQAAAA==.',['Kä']='Kälipsow:BAAALAAECgYIDgAAAA==.',['Kè']='Kèrö:BAAALAADCggIDwABLAAECgQIBwAHAAAAAA==.Kèrø:BAAALAAECgQIBwAAAA==.',['Kî']='Kîra:BAAALAAECgMIAwABLAAECgcIIgAMALoRAA==.',La='Lapinôu:BAAALAAECgcICAAAAA==.Lauviah:BAAALAAECgMIAwABLAAECggIEwAHAAAAAA==.Lazarüs:BAAALAADCgEIAQAAAA==.',Le='Ledragon:BAAALAADCggIJwABLAAFFAIIBgALAFYgAA==.Leebowsky:BAAALAADCggICAAAAA==.Leexa:BAAALAADCggIDwAAAA==.Leilys:BAAALAAECgIIAgAAAA==.',Li='Libowsky:BAAALAAECgcIEwAAAA==.Ligesol:BAAALAAECgEIAgAAAA==.Littleheal:BAAALAADCgQIBAAAAA==.',Lo='Lonely:BAAALAADCgYIBgAAAA==.Loushinglar:BAAALAAECgEIAgAAAA==.Loûrs:BAAALAADCgQIBAAAAA==.',Lu='Lumarmacil:BAABLAAECoEWAAIJAAcI9hHwfQC6AQAJAAcI9hHwfQC6AQAAAA==.Lund:BAEALAADCgEIAQABLAAFFAMICwAUAEIjAA==.',Ly='Lysandre:BAAALAADCgYIBgAAAA==.',['Lö']='Löurs:BAAALAAECggICwAAAA==.',Ma='Madamedark:BAAALAAECgYIBgABLAAFFAQIDAAfACMeAA==.Madsu:BAAALAAECgYIDQAAAA==.Mageisfun:BAAALAADCgcIDQABLAAFFAQICAAQAI4TAA==.Maggiesmith:BAAALAAECgUIBQAAAA==.Magruk:BAAALAADCgYIBgAAAA==.Makaveli:BAAALAADCggICAAAAA==.Maldraxx:BAAALAAECgMIAwAAAA==.Malfy:BAAALAADCgIIAgAAAA==.Mamuuth:BAAALAAECggICAABLAAECggIDwAHAAAAAA==.Mardrim:BAACLAAFFIEGAAIQAAMIYBDSHQCkAAAQAAMIYBDSHQCkAAAsAAQKgScAAhAACAjZG/AiAIoCABAACAjZG/AiAIoCAAAA.Massax:BAAALAAECgYICQAAAA==.Masstodont:BAAALAAFFAIIAgAAAA==.Mataji:BAAALAADCgcIBwAAAA==.Mathematix:BAACLAAFFIEKAAIVAAQIQhnmCgBeAQAVAAQIQhnmCgBeAQAsAAQKgSsAAhUACAgIJEUNAC0DABUACAgIJEUNAC0DAAAA.Matusin:BAAALAADCgcICQABLAAECgMIBwAHAAAAAA==.Maïsse:BAAALAADCgcIEgAAAA==.',Me='Meandre:BAAALAADCgcIDQAAAA==.Megaplow:BAAALAAFFAIIBAABLAAFFAIIBAAHAAAAAA==.Melchiah:BAAALAADCgEIAQAAAA==.Melkorlock:BAAALAAECgMICQAAAA==.Melkorpriest:BAAALAADCggICgAAAA==.Meriah:BAAALAAECgIIAgABLAAECggIHAAWAJAXAA==.',Mi='Miami:BAAALAAECgYIBgABLAAECgYIEAAHAAAAAA==.Mifali:BAABLAAECoEdAAIUAAgIEiE5BAANAwAUAAgIEiE5BAANAwAAAA==.Milac:BAAALAADCggICAAAAA==.Milkshake:BAAALAADCgUIBQAAAA==.',Mk='Mkvennair:BAABLAAECoEVAAIXAAcIJhnhGwDcAQAXAAcIJhnhGwDcAQAAAA==.',Mo='Momygoodmage:BAAALAAECgYIBwAAAA==.Monsterteub:BAAALAADCggIDwABLAAECgcIGgAUAGASAA==.Montalieu:BAAALAADCgQIBAAAAA==.Moourinou:BAAALAAECgEIAQAAAA==.Morgrom:BAAALAADCgYIBgAAAA==.Mortice:BAAALAAECgcIDgABLAAECgcIGgAUAGASAA==.Mortlalune:BAAALAAECggICgAAAA==.',Mu='Murosawa:BAABLAAECoEXAAIgAAYIjiX9DwCPAgAgAAYIjiX9DwCPAgABLAAECggIIwAWAO0kAA==.',My='Myleäs:BAABLAAECoEaAAIbAAcIkRS+PADiAQAbAAcIkRS+PADiAQAAAA==.Myrtiah:BAABLAAECoEVAAIgAAcIHxeSJADVAQAgAAcIHxeSJADVAQABLAAECggIHAAWAJAXAA==.Mythrill:BAAALAAECgUICAABLAAECggIJwAEAGQYAA==.',['Mà']='Mària:BAAALAADCgQIBAAAAA==.',['Mé']='Méprisante:BAAALAAECgEIAQABLAAECggIHAAWAJAXAA==.Mériah:BAABLAAECoEcAAMWAAgIkBc7FQDvAQAWAAgIkBc7FQDvAQAVAAYIOhJpkAByAQAAAA==.',Na='Naatah:BAAALAADCgcICAAAAA==.Naili:BAAALAADCgcICAAAAA==.Nanøm:BAABLAAECoEcAAIhAAgICxQZHAAgAgAhAAgICxQZHAAgAgAAAA==.Narisson:BAABLAAECoEZAAQiAAgIeg9vEAC0AQAiAAcInhBvEAC0AQAbAAEIfQd8rQAtAAAZAAEIaALvGAEYAAAAAA==.Narotia:BAABLAAECoEUAAMZAAYIqCABLwAvAgAZAAYIqCABLwAvAgAbAAEIYwNHrwApAAAAAA==.Nasteria:BAABLAAECoEeAAIKAAcILg3QhwBnAQAKAAcILg3QhwBnAQAAAA==.Nazarius:BAAALAAECgQIAwAAAA==.Nazghull:BAAALAAECgUIDAAAAA==.Nazorkros:BAAALAAECgUIBQABLAAECgcIFQANAEAOAA==.',Ne='Neeyah:BAAALAAECgYIBgABLAAFFAMIBwAJAF8XAA==.Nelth:BAAALAAECgEIAQAAAA==.Nephty:BAAALAAECgEIAQAAAA==.Nergal:BAAALAADCgYIBgAAAA==.Nessadiou:BAAALAAECgMIAwAAAA==.Nesta:BAABLAAECoEhAAIJAAgIHx9HJwCtAgAJAAgIHx9HJwCtAgAAAA==.Netsune:BAABLAAECoEZAAIiAAcIPxx/CQA8AgAiAAcIPxx/CQA8AgAAAA==.',Ni='Nicklauss:BAABLAAECoEdAAMKAAgI3RfQOgAsAgAKAAgI3RfQOgAsAgADAAYISQ6eXAAsAQAAAA==.Nidhog:BAAALAAECgIIAgAAAA==.Nightmahr:BAABLAAECoEXAAIQAAgIbh3kGADPAgAQAAgIbh3kGADPAgAAAA==.Nixma:BAAALAAECgYIDwAAAA==.',No='Noishpa:BAAALAAECgEIAgABLAAECgcIIgAJAEgZAA==.Noldor:BAAALAADCggICgAAAA==.',Nu='Nuÿ:BAAALAAECgYIBgAAAA==.',Ny='Nyarae:BAAALAAECgYIEQAAAA==.Nyù:BAAALAAECgQIBwAAAA==.',['Nø']='Nøøkie:BAAALAADCgMIAwAAAA==.',Oh='Ohanzee:BAAALAAECggICAAAAA==.',Or='Orena:BAABLAAECoEVAAIhAAcI3A6WLACrAQAhAAcI3A6WLACrAQAAAA==.Orfelia:BAABLAAECoEeAAIRAAcIaRy2SAA6AgARAAcIaRy2SAA6AgAAAA==.Orphay:BAAALAAECgYIJgAAAQ==.',Os='Osti:BAAALAADCgMIBAABLAAECgcIFQANAEAOAA==.Oswÿn:BAAALAAECgcIDgAAAA==.',Ou='Oupsie:BAAALAAECgMIAwABLAAECgYIEAAHAAAAAA==.',Oz='Ozwyn:BAAALAADCgYIBgAAAA==.',Pa='Palagaule:BAAALAAECgcIEQAAAA==.Palaplow:BAAALAAECggIBgABLAAFFAIIBAAHAAAAAA==.Palaslayer:BAAALAAECgEIAQABLAAECgcIFQANAEAOAA==.Palatinaë:BAABLAAECoEeAAIJAAcIBgsUoQB5AQAJAAcIBgsUoQB5AQAAAA==.Parbuffle:BAABLAAECoEYAAIgAAcIEBFgNgBnAQAgAAcIEBFgNgBnAQAAAA==.',Pe='Pegidouze:BAABLAAECoElAAMFAAgIvCNIBgAZAwAFAAgIvCNIBgAZAwAjAAIIdQwRfQBlAAAAAA==.Perlette:BAAALAADCgYICwAAAA==.Petoplow:BAAALAAFFAIIAgABLAAFFAIIBAAHAAAAAA==.',Pi='Pinkiyouti:BAAALAADCgUIBgAAAA==.Pitchounoute:BAAALAAECgUIBwAAAA==.',Po='Polaton:BAAALAAECgQIBAABLAAFFAYIHAANAGEgAA==.Pooöôh:BAAALAAECggIDAAAAA==.',Pr='Protmalone:BAACLAAFFIEZAAIJAAYIpRubAQA0AgAJAAYIpRubAQA0AgAsAAQKgSoAAgkACAhrJUMHAFwDAAkACAhrJUMHAFwDAAAA.Prøtectøra:BAAALAAECgYICgABLAAFFAQIDAAfACMeAA==.Prøxima:BAABLAAECoEcAAIJAAcIuxE/fgC5AQAJAAcIuxE/fgC5AQAAAA==.',['Qü']='Qübï:BAAALAAECgMIAwAAAA==.',Ra='Raknathõr:BAABLAAECoEdAAIbAAgIkxgmJABjAgAbAAgIkxgmJABjAgAAAA==.Raksharan:BAABLAAECoEWAAMLAAgIzg8SUQDHAQALAAgIXw0SUQDHAQATAAcITQvANAB4AQAAAA==.Rastofire:BAAALAAECgQIBwABLAAECgUIBAAHAAAAAA==.Razzmatazz:BAABLAAECoEcAAIOAAcIPxfsEADsAQAOAAcIPxfsEADsAQAAAA==.',Rc='Rcdrink:BAAALAADCgYIBgAAAA==.',Re='Redlïght:BAAALAADCggICAAAAA==.Rei:BAABLAAECoEYAAIgAAcIIRbpKQCxAQAgAAcIIRbpKQCxAQAAAA==.Replicant:BAAALAAECgYIDwAAAA==.',Ri='Rinzï:BAAALAAECgYIDQAAAA==.',Ro='Roubidou:BAAALAAECgcIDQAAAA==.',Rq='Rqch:BAACLAAFFIEIAAMQAAMIDRAqEQDxAAAQAAMIDRAqEQDxAAAgAAEI2QZ9IQA1AAAsAAQKgRgAAxAACAjBFzlEAOwBABAABwhTFTlEAOwBACAABwi9FYU4AFoBAAAA.',Ru='Russell:BAAALAAECgUICwAAAA==.',Ry='Ryuk:BAAALAAECgIIAgAAAA==.',['Rö']='Rödyy:BAAALAADCggICAABLAAECgMIBAAHAAAAAA==.Röxäne:BAAALAADCgMIAwAAAA==.',['Rø']='Røxäne:BAAALAAECgYIEQAAAA==.',Sa='Sablé:BAAALAAECgEIAQAAAA==.Sacraì:BAAALAADCggIEAAAAA==.Safian:BAABLAAECoEYAAIZAAYIhwjQugDJAAAZAAYIhwjQugDJAAAAAA==.Sajï:BAAALAADCgYIFgAAAA==.Satoru:BAABLAAECoEXAAIRAAgI1xULYgD8AQARAAgI1xULYgD8AQAAAA==.Saurôn:BAAALAADCgQIBAAAAA==.Sayphix:BAAALAAECgcIDwAAAA==.',Sc='Scary:BAAALAADCgUIBQAAAA==.Schyz:BAAALAAECggIEAAAAA==.Scores:BAAALAAFFAYIFQAAAQ==.',Se='Seido:BAAALAADCgYICwAAAA==.Seldara:BAECLAAFFIEGAAICAAIIexsaGACvAAACAAIIexsaGACvAAAsAAQKgSwAAwIABwgXH0sgAFcCAAIABwgXH0sgAFcCABIABghcICkjADoCAAEsAAUUAwgLABQAQiMA.Serpillère:BAABLAAECoEWAAIFAAgIzh5WEwCZAgAFAAgIzh5WEwCZAgAAAA==.',Sh='Shadowphra:BAAALAAECgYIBgABLAAFFAIIBAAHAAAAAA==.Shaerazad:BAAALAADCggIFAAAAA==.Shakyz:BAAALAADCgcIDgAAAA==.Shamless:BAABLAAECoEUAAMbAAcIvA0/UACWAQAbAAcImQ0/UACWAQAiAAYI+AaeGQATAQAAAA==.Shanae:BAAALAADCgcIEAABLAAECgcIFQANAEAOAA==.Sheratan:BAAALAAECgEIAgAAAA==.Shorey:BAAALAADCgcICgAAAA==.Shushen:BAABLAAECoEaAAIkAAcImhzxEwBJAgAkAAcImhzxEwBJAgAAAA==.Shyn:BAABLAAECoEaAAIgAAcIaR4NFABiAgAgAAcIaR4NFABiAgAAAA==.Shànnøn:BAAALAADCgcIGAAAAA==.Shämo:BAAALAAECgYIDQAAAA==.',Si='Siltheas:BAAALAADCgMIAwAAAA==.',Sm='Smila:BAAALAADCgYIBgABLAAECgYIFAAZAKggAA==.Smith:BAAALAADCggIEAAAAA==.',So='Sof:BAAALAADCggIFAAAAA==.Somaliangoat:BAAALAAECgUIBQABLAAFFAYIHAANAGEgAA==.Sombreponant:BAAALAAECgEIAQAAAA==.',St='Stainless:BAAALAADCgIIAgAAAA==.Stalkyz:BAABLAAECoEiAAIeAAgInSU7AwBtAwAeAAgInSU7AwBtAwAAAA==.Starflax:BAAALAAECgYIEAAAAA==.Starloose:BAABLAAECoEaAAIUAAcIYBJgJwCtAQAUAAcIYBJgJwCtAQAAAA==.Starÿ:BAAALAADCgIIAQAAAA==.Staticx:BAABLAAECoElAAIQAAgI6CL2DAAkAwAQAAgI6CL2DAAkAwAAAA==.Stinkiwinki:BAAALAADCgIIAQABLAAECggIHAAfALEkAA==.Stoumaz:BAAALAADCgUIBQAAAA==.',Su='Sulenya:BAAALAADCgMIAwAAAA==.Sunfire:BAAALAAECgYIEwABLAAECgcIHgAGACEaAA==.Sunkayne:BAAALAAECgUICwABLAAECgcIHgAGACEaAA==.Sunkyuu:BAABLAAECoEeAAMGAAcIIRosEQAUAgAGAAcIIRosEQAUAgAFAAEImAoWvQAlAAAAAA==.',Sy='Syleams:BAAALAADCgQIBAAAAA==.Sylvannanas:BAAALAAECgYIBgABLAAECgcIGgAUAGASAA==.Syniel:BAABLAAECoEnAAMEAAgIZBjeDAA+AgAEAAgIQBfeDAA+AgAhAAYI/BEiNQB5AQAAAA==.Synrael:BAAALAADCgcIFAAAAA==.Synécham:BAAALAAECggIBwAAAA==.',['Sé']='Sétèsh:BAABLAAECoEcAAIFAAcIUg7xVQBQAQAFAAcIUg7xVQBQAQAAAA==.',['Sï']='Sïnypscø:BAACLAAFFIEGAAMRAAQIHxNaDgA9AQARAAQIHxNaDgA9AQAdAAEIfwflGQBJAAAsAAQKgSAAAxEACAgtIg8VAAUDABEACAgtIg8VAAUDAB0ACAi1FCoUAA4CAAAA.',['Sô']='Sôlstice:BAAALAADCgYICgAAAA==.',['Sù']='Sùnzen:BAAALAADCgYICAABLAAECgcIHgAGACEaAA==.',Ta='Taeki:BAAALAADCggIDwAAAA==.Tai:BAABLAAECoEeAAIQAAgI2hdlNAAsAgAQAAgI2hdlNAAsAgAAAA==.Taspez:BAAALAADCgcIDQAAAA==.Tawen:BAACLAAFFIELAAILAAQIowy0EQA6AQALAAQIowy0EQA6AQAsAAQKgSoAAwsACAhCHTUgAKQCAAsACAhCHTUgAKQCAAgABwjvEOYMAMcBAAAA.',Te='Teane:BAAALAADCggICAABLAAECggIHAAWAJAXAA==.Teeyah:BAAALAAECgYIBgABLAAFFAMIBwAJAF8XAA==.Tehlarissa:BAACLAAFFIEGAAMdAAIIigxRDwCXAAAdAAIIqgtRDwCXAAARAAIIjAQAAAAAAAAsAAQKgRkABB0ABwjPH4INAGICAB0ABwjPH4INAGICABwABAhjG+siACIBABEAAwh5FYD+ANEAAAAA.Tenarzi:BAAALAAECgEIAQAAAA==.Terr:BAABLAAECoEUAAIWAAYInxBZKgAoAQAWAAYInxBZKgAoAQAAAA==.',Th='Thanoos:BAAALAADCgcICgABLAAECgcIFQANAEAOAA==.Thebam:BAAALAAECgUIBgAAAA==.Thunderbolts:BAAALAAECgEIAQAAAA==.Thynae:BAAALAAECgUIBQAAAA==.',Ti='Tidus:BAAALAADCggICQAAAA==.Tiladia:BAAALAADCggIEwABLAAECgcIFgAFAEIaAA==.Tilluss:BAABLAAECoEdAAIKAAcI1Ac6pwApAQAKAAcI1Ac6pwApAQAAAA==.Titoxy:BAAALAADCggIFwAAAA==.',To='Torgrom:BAAALAADCgcIBwAAAA==.Totemrun:BAAALAAECgYICwAAAA==.',Tr='Trolent:BAAALAADCgcIBwAAAA==.Tryxe:BAAALAAECgcICwAAAA==.',Ts='Tsunade:BAAALAAECgYIBgABLAAECgYIFAAZAKggAA==.',Ty='Tyrkusia:BAAALAAECgEIAgAAAA==.',Tz='Tzanta:BAAALAADCgMIAwAAAA==.Tzukin:BAAALAAECggIEAAAAA==.',['Tä']='Täaz:BAAALAAECgcIEQAAAA==.',['Tô']='Tôga:BAAALAADCgUIBQAAAA==.',Un='Unepadeu:BAAALAAFFAIIAgAAAA==.',Ut='Uthar:BAAALAADCgMIAwAAAA==.',Uw='Uwuïkø:BAAALAAECgYIBwABLAAFFAQICAAQAI4TAA==.',Uz='Uzo:BAAALAAFFAIIBAAAAA==.',Va='Valmir:BAAALAAECgMIAwAAAA==.Vanivel:BAABLAAECoEhAAIgAAcIHRekJgDIAQAgAAcIHRekJgDIAQAAAA==.Vargruk:BAAALAAECgUIBgAAAA==.Vaxarus:BAAALAADCgQIAgAAAA==.Vayray:BAEALAAFFAEIAQABLAAFFAMICwAUAEIjAA==.',Ve='Velarian:BAAALAAECgYIDAAAAA==.Venusa:BAABLAAECoEYAAIUAAYI2yAIFgAxAgAUAAYI2yAIFgAxAgABLAAECggIIAAhAMQYAA==.Verestrasza:BAEALAAECgIIAgABLAAFFAMICwAUAEIjAA==.Vereva:BAECLAAFFIELAAIUAAMIQiPrBgAvAQAUAAMIQiPrBgAvAQAsAAQKgSYAAhQACAiaI6IDABgDABQACAiaI6IDABgDAAAA.',Vi='Vicioeh:BAAALAADCggICAABLAAECggIKAAOAPwgAA==.Viego:BAAALAAECgYICQAAAA==.Viegos:BAAALAADCgYIBgAAAA==.Visorak:BAAALAADCggICAAAAA==.',Vl='Vladï:BAAALAAECgMIAwAAAA==.',Vu='Vulperinette:BAAALAAECgEIAQAAAA==.',['Vô']='Vôletavie:BAAALAAECgEIAgAAAA==.',Wa='Walrot:BAAALAADCggICAAAAA==.Wazaaãaa:BAABLAAECoEWAAINAAcImRSnJADSAQANAAcImRSnJADSAQAAAA==.',Wh='Whatanrsham:BAAALAAECggIAQAAAA==.Whatapal:BAABLAAECoEXAAQUAAcIIB1RFABCAgAUAAcIIB1RFABCAgAJAAUIdQ4azgAlAQAXAAEI6Q3mXgAtAAABLAAECggIAQAHAAAAAA==.Whity:BAABLAAECoEWAAIFAAcIQhqCLAD+AQAFAAcIQhqCLAD+AQAAAA==.',Wi='Wiish:BAABLAAECoEaAAIWAAgIwxJWGgC2AQAWAAgIwxJWGgC2AQAAAA==.Windstormind:BAABLAAECoEWAAIhAAcIfhf3IAD4AQAhAAcIfhf3IAD4AQABLAAFFAQICAAQAI4TAA==.Windstriker:BAAALAAECgUIBQAAAA==.Wingosho:BAABLAAECoEYAAIQAAgIJRGNRADrAQAQAAgIJRGNRADrAQAAAA==.',['Wÿ']='Wÿzën:BAABLAAECoEaAAIkAAgIHxcfGAAZAgAkAAgIHxcfGAAZAgAAAA==.',Xe='Xeeyah:BAAALAAECgYIBgABLAAFFAMIBwAJAF8XAA==.',Ya='Yaminiga:BAAALAADCggICAAAAA==.Yath:BAAALAADCgEIAQAAAA==.',Ye='Yeezys:BAAALAAECgEIAQAAAA==.',Yi='Yikiolth:BAAALAADCggIDgAAAA==.Yikthu:BAAALAADCgYIBgAAAA==.',Yl='Yllamis:BAAALAADCgcIBwAAAA==.',Yr='Yrélia:BAAALAAECgYICwAAAA==.',Yu='Yukïe:BAAALAADCgEIAQAAAA==.Yunoh:BAAALAAECgMIAwABLAAECggIKAAOAPwgAA==.Yunormi:BAABLAAECoEoAAMOAAgI/CCMBADkAgAOAAgI/CCMBADkAgANAAcI6BmtGwAiAgAAAA==.Yunorok:BAAALAADCggICAAAAA==.',Za='Zanshoua:BAAALAAECggIBgAAAA==.Zantekutsia:BAABLAAECoEdAAIlAAcIVCBaDgCaAgAlAAcIVCBaDgCaAgAAAA==.Zargoths:BAAALAADCgcIBgABLAAECgcIFQANAEAOAA==.',Ze='Zertare:BAAALAADCgEIAQAAAA==.Zevil:BAAALAAECgYICwAAAA==.Zevilus:BAAALAADCgcIDQABLAAECgYICwAHAAAAAA==.',Zh='Zhedd:BAACLAAFFIEHAAIJAAMIXxcwDQAFAQAJAAMIXxcwDQAFAQAsAAQKgSkAAgkACAjcI6sMADoDAAkACAjcI6sMADoDAAAA.Zhonyas:BAAALAAECgIIAgABLAAECgcIDwAHAAAAAA==.',Zk='Zkarbon:BAAALAAECgQIBAAAAA==.',Zn='Zni:BAABLAAECoEYAAISAAYIpiNLHwBXAgASAAYIpiNLHwBXAgAAAA==.Znw:BAAALAAECgYICAAAAA==.',Zo='Zochalbak:BAABLAAECoEaAAIjAAcIExgMKgDwAQAjAAcIExgMKgDwAQAAAA==.Zorodémo:BAABLAAECoEZAAMLAAgI5B1bIgCXAgALAAgI5B1bIgCXAgATAAIIXAd1eABbAAAAAA==.',Zv='Zv:BAAALAAECgYIEgAAAA==.',['Âr']='Ârtarus:BAAALAAECggIBwAAAA==.',['Ât']='Âthenna:BAAALAAECgIIBAAAAA==.',['Är']='Ärwwen:BAAALAAECgYIDQAAAA==.',['Éd']='Édoras:BAABLAAECoEVAAIDAAcI6A96SwBrAQADAAcI6A96SwBrAQAAAA==.',['Él']='Éliriane:BAAALAAECgYIEwAAAA==.',['Ða']='Ðarkmønk:BAACLAAFFIEMAAIfAAQIIx7PBABrAQAfAAQIIx7PBABrAQAsAAQKgSsAAh8ACAiWJJ4CAEcDAB8ACAiWJJ4CAEcDAAAA.',['Ðr']='Ðraemir:BAABLAAECoEUAAIZAAYIhhMPkwAYAQAZAAYIhhMPkwAYAQAAAA==.',['Öb']='Öbaâl:BAAALAAECgEIAgAAAA==.',['Ün']='Ündead:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end