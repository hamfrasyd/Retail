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
 local lookup = {'Warrior-Protection','Mage-Frost','Warlock-Destruction','Shaman-Elemental','Warrior-Arms','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Warlock-Affliction','Paladin-Protection','Paladin-Holy','Mage-Arcane','Priest-Holy','Druid-Restoration','Priest-Shadow','Shaman-Restoration','Monk-Brewmaster','Warrior-Fury','Hunter-BeastMastery','Druid-Balance','Druid-Feral','DemonHunter-Havoc','Monk-Windwalker','Warlock-Demonology','Hunter-Marksmanship','Priest-Discipline','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Rogue-Assassination',}; local provider = {region='EU',realm='Anachronos',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Achmethax:BAAALAAECgYICgAAAA==.Ackles:BAAALAADCgMIAwAAAA==.',Ad='Admon:BAAALAAECggICAAAAA==.Ads:BAABLAAECoEWAAIBAAgIrxzCDgCdAgABAAgIrxzCDgCdAgAAAA==.',Ae='Aegyptus:BAAALAAECgYIBgAAAA==.',Ag='Aginor:BAAALAAECgIIAgAAAA==.Agnitio:BAABLAAECoEXAAICAAcIEgujNAB2AQACAAcIEgujNAB2AQAAAA==.Agnuks:BAABLAAECoEaAAIDAAcIzg+GWQCoAQADAAcIzg+GWQCoAQAAAA==.',Ai='Airetta:BAABLAAECoEXAAIEAAcILwjjYQBWAQAEAAcILwjjYQBWAQAAAA==.Aitarel:BAAALAAECgYIDgAAAA==.',Am='Amarii:BAAALAADCggICAAAAA==.',An='Andicon:BAAALAAECgUIBgAAAA==.',As='Ashbringer:BAAALAADCgcIBwAAAA==.Ashimmu:BAABLAAECoEfAAMFAAgISRhlCwABAgAFAAcIkRdlCwABAgABAAcIexQTKAC7AQAAAA==.Asura:BAABLAAECoEdAAIGAAgILxUaTwAmAgAGAAgILxUaTwAmAgAAAA==.',At='Attanocorvo:BAAALAAECggIDgAAAA==.',Av='Avanez:BAAALAAECggIDgAAAA==.Avery:BAAALAAECgcIEgAAAA==.',Ba='Baka:BAABLAAECoEZAAICAAgIMA7HJQDKAQACAAgIMA7HJQDKAQAAAA==.Barthelot:BAAALAAECgIIAgAAAA==.Batoutofhell:BAAALAADCggIDQAAAA==.',Be='Benrangel:BAAALAADCgMIAwAAAA==.Bernch:BAAALAAECgMIBAAAAA==.',Bg='Bg:BAAALAAECgYIBgAAAA==.',Bj='Bjerg:BAAALAADCgMIAwABLAAECgYIFQAHAA0bAA==.',Bl='Blindwizard:BAAALAADCgMIAwAAAA==.',Bo='Bones:BAAALAADCggIHAAAAA==.',Br='Bradnir:BAAALAAECgcIAwAAAA==.Brightlight:BAAALAADCggICgAAAA==.Bronne:BAAALAADCgEIAQABLAAECgYIBgAIAAAAAA==.Broulin:BAABLAAECoEXAAIBAAcI+BiIHwD5AQABAAcI+BiIHwD5AQAAAA==.Bruk:BAAALAAECgYICwAAAA==.',Bs='Bsugarri:BAAALAADCgIIAgAAAA==.',Bu='Bugyertem:BAAALAAECgYIBgAAAA==.',Ca='Cambridgelol:BAACLAAFFIEIAAIDAAIIhh14IACtAAADAAIIhh14IACtAAAsAAQKgRYAAwMACAh0HH0kAIcCAAMACAg4HH0kAIcCAAkABQiaGFMTAGUBAAAA.Carzzy:BAABLAAECoEVAAMHAAYIDRvCeADBAQAHAAYIrhrCeADBAQAKAAIIMRxERwCfAAAAAA==.',Ce='Cessator:BAAALAAECgcICwAAAA==.',Ch='Chaosprime:BAAALAADCgUIBgAAAA==.Chillvanas:BAAALAAECgYIBgAAAA==.Chizx:BAAALAAECgUICQAAAA==.Chéznéy:BAAALAAECgQIBgAAAA==.',Co='Corydorras:BAAALAAECgQIBAAAAA==.',Da='Dalt:BAABLAAECoEiAAILAAcIYh6DEgBSAgALAAcIYh6DEgBSAgAAAA==.Daltanyan:BAAALAADCgYIBgAAAA==.Dalthazar:BAAALAAECgMIAwABLAAECgcIIgALAGIeAA==.Darla:BAAALAAECgYIDAAAAA==.',Dd='Ddraigfach:BAAALAAECgQIBAAAAA==.',De='Deadlycalm:BAAALAAECgIIAwAAAA==.Deftly:BAAALAAECgQIBAABLAAECgYIFQAHAA0bAA==.Dev:BAABLAAECoEXAAIMAAgIEhgfOwA5AgAMAAgIEhgfOwA5AgAAAA==.',Di='Dikoos:BAABLAAECoEXAAIHAAgIJBKBagDeAQAHAAgIJBKBagDeAQAAAA==.',Do='Doks:BAAALAADCgIIAgAAAA==.',Dr='Drypp:BAAALAADCgUICAABLAADCgcICQAIAAAAAA==.',['Dé']='Dérpington:BAAALAAECgQIBAAAAA==.',Ec='Ecarus:BAACLAAFFIEHAAINAAMImyCkCgAdAQANAAMImyCkCgAdAQAsAAQKgRoAAg0ACAiBIJgQAMkCAA0ACAiBIJgQAMkCAAAA.',Ed='Edéa:BAAALAADCgcICQAAAA==.',Ej='Ejoker:BAAALAADCgQIBAAAAA==.',El='Elans:BAAALAADCggIHgAAAA==.Elnuzard:BAAALAADCgMIAwAAAA==.Elogis:BAABLAAECoEZAAIEAAcIqwmyWAB1AQAEAAcIqwmyWAB1AQAAAA==.Elvenmageo:BAABLAAFFIEFAAIOAAQImAn1CwDcAAAOAAQImAn1CwDcAAAAAA==.',Ep='Epiteh:BAAALAADCggICAAAAA==.',Er='Ert:BAAALAADCgQIBAABLAADCgcICQAIAAAAAA==.',Es='Especti:BAABLAAECoEaAAIPAAcIog3UPgCZAQAPAAcIog3UPgCZAQAAAA==.',Fa='Fano:BAABLAAECoEcAAICAAcIOCPUCgDKAgACAAcIOCPUCgDKAgAAAA==.',Fe='Feck:BAAALAADCgUIBQAAAA==.Femina:BAAALAAECggICAAAAA==.',Fo='Foul:BAAALAAECgUICQAAAA==.',Fr='Frazelbur:BAAALAADCgYIBgAAAA==.Fraztid:BAAALAADCgcIBwAAAA==.Frosthammer:BAABLAAECoEWAAIQAAcIjiRAEADMAgAQAAcIjiRAEADMAgAAAA==.',Fu='Furìous:BAAALAAECgEIAQABLAAFFAUIDgAHAK4gAA==.',Fx='Fxw:BAAALAAECgMIAwAAAA==.',Fy='Fyakuza:BAAALAADCgYIBgAAAA==.Fyrun:BAAALAADCgIIAgAAAA==.',Ga='Gallvin:BAAALAADCggICAAAAA==.Gambrinus:BAAALAAECgYIDgAAAA==.',Ge='Gematría:BAAALAAECgYIEgAAAA==.Gembersnor:BAAALAADCggICAAAAA==.',Gh='Ghorda:BAAALAAECgcIDQABLAAECggIJgARAHobAA==.',Gi='Gigah:BAAALAAECggIDQAAAA==.',Gj='Gjørmebrytar:BAAALAADCgMIAwABLAADCgcICQAIAAAAAA==.',Gl='Glacial:BAAALAADCgEIAQABLAAFFAUIDgAHAK4gAA==.',Go='Gorihrgrom:BAAALAADCgIIAgABLAADCgUIBgAIAAAAAA==.Gourtcool:BAEALAAECggICAAAAA==.',Gr='Graninza:BAAALAADCgYICQAAAA==.Griggle:BAAALAADCgYIBgAAAA==.Grimlight:BAAALAADCggICAAAAA==.Grimlynch:BAAALAADCggICAAAAA==.Grimn:BAAALAAECgcIDgAAAA==.Grizlyadams:BAABLAAECoEaAAISAAcIZB7eJwBpAgASAAcIZB7eJwBpAgAAAA==.',Ha='Habrok:BAABLAAECoEgAAIOAAgIYB9ADgDDAgAOAAgIYB9ADgDDAgAAAA==.Hamaya:BAABLAAECoEaAAITAAcIcwc0oAAwAQATAAcIcwc0oAAwAQAAAA==.Harríe:BAAALAADCggICQAAAA==.',He='Heck:BAAALAAECgYIDQAAAA==.Hempuma:BAABLAAECoEUAAMUAAgIzQyVOwCQAQAUAAgIzQyVOwCQAQAOAAYImQhSewDbAAAAAA==.Henno:BAAALAAECggICgAAAA==.',Hf='Hfaistos:BAAALAADCggICAAAAA==.',Ho='Honeywell:BAABLAAECoEZAAMOAAgIYiAWCgDsAgAOAAgIYiAWCgDsAgAUAAEIqgVejgAtAAAAAA==.',Ij='Ijin:BAAALAAECgYIDgAAAA==.',It='Itshal:BAAALAAECgYIEAAAAA==.',Ja='Janove:BAAALAAECggIDgAAAA==.Jaythedruid:BAABLAAECoEYAAIVAAcISA5YGwCUAQAVAAcISA5YGwCUAQAAAA==.',Je='Jeeralt:BAAALAAECggIDAAAAA==.',Ju='Jump:BAAALAADCggICAAAAA==.',Ka='Kartara:BAAALAAECgIIAgAAAA==.',Ke='Keomo:BAABLAAECoEdAAMBAAcI7iEbDwCYAgABAAcI7iEbDwCYAgAFAAUIfRo2EwB8AQAAAA==.Ketdrinker:BAABLAAECoEWAAMPAAgInQjCQwCBAQAPAAgInQjCQwCBAQANAAMI4wOhjQB8AAAAAA==.',Ki='Kierang:BAABLAAECoEcAAMEAAgIwh1QFwC9AgAEAAgIwh1QFwC9AgAQAAEI7A3CBgEuAAAAAA==.',Km='Kmotr:BAAALAAECggIBgAAAA==.',Kn='Knotwell:BAAALAADCgUIBQAAAA==.Knyght:BAAALAAECgQIBAAAAA==.',Kr='Krassix:BAAALAAECgYIDgAAAA==.',Ku='Kunacross:BAAALAADCggICAAAAA==.',Ky='Kyariek:BAABLAAECoEdAAIVAAcIlQ9iGgCeAQAVAAcIlQ9iGgCeAQAAAA==.Kyxobype:BAABLAAECoEUAAIEAAcIXA50TgCZAQAEAAcIXA50TgCZAQAAAA==.',La='Labubu:BAABLAAECoEVAAIMAAcIxR7HKwB8AgAMAAcIxR7HKwB8AgABLAAECggIHwAWAOAgAA==.Lanceabit:BAAALAAECgYIBgAAAA==.Lapianos:BAAALAAECgUIDgAAAA==.Larry:BAAALAAECgcICAAAAA==.Lazam:BAAALAAECgcIEQAAAA==.',Le='Leelu:BAAALAAECgYIBwABLAAECggIGQAMAH8YAA==.',Li='Liath:BAAALAADCggIBwAAAA==.Lilkitsune:BAAALAAECgYIDQABLAAECggIKQAHAC0gAA==.Liuzhigang:BAAALAAECggIEAAAAA==.',Lo='Locporcia:BAAALAADCggIDgABLAAECgcIFgATAKcHAA==.Loriel:BAAALAADCggICAAAAA==.',Lr='Lrdyy:BAAALAAECgcIBAAAAA==.',Lu='Luthari:BAAALAAECgYIBgAAAA==.Lutharii:BAAALAAECgEIAQAAAA==.',Lz='Lzmsham:BAAALAADCggICAAAAA==.',['Lí']='Líghtbringer:BAAALAAECgMIBAAAAA==.',Ma='Manson:BAABLAAECoEXAAIXAAYIQx6FGQAIAgAXAAYIQx6FGQAIAgAAAA==.Mattdraclock:BAABLAAECoEaAAIYAAcIeBbGGgADAgAYAAcIeBbGGgADAgAAAA==.Mavric:BAAALAAECgYICQAAAA==.',Me='Meathoof:BAAALAAECgUICQAAAA==.Meggy:BAAALAAECgEIAQAAAA==.Menor:BAAALAAECgYICAAAAA==.',Mg='Mgd:BAAALAAECggIDAAAAA==.',Mi='Mikra:BAABLAAECoEcAAIZAAcIShuWJgAeAgAZAAcIShuWJgAeAgAAAA==.Misiolkin:BAAALAAECgYIEQAAAA==.Mitta:BAABLAAECoEbAAIWAAcIuxjPTgAEAgAWAAcIuxjPTgAEAgAAAA==.',Mj='Mjøll:BAAALAAECgcIDgABLAAECggIGQAMAH8YAA==.',Mo='Mokum:BAAALAAECggICgAAAA==.Monica:BAABLAAECoEbAAIUAAcIrxU1LgDUAQAUAAcIrxU1LgDUAQAAAA==.Morgenfruen:BAABLAAECoEcAAINAAcI8QsCVABdAQANAAcI8QsCVABdAQAAAA==.',Mp='Mpalanteza:BAAALAADCgUIBQAAAA==.',My='Mykernios:BAAALAADCgcIDwAAAA==.Mypetiswet:BAAALAADCggIDgAAAA==.Mystry:BAAALAAECgYIDAAAAA==.',Na='Nameless:BAAALAADCgcIDAABLAAECgcIFwABAPgYAA==.Napierniczak:BAAALAADCggIEAAAAA==.Naravi:BAAALAADCgcICgAAAA==.Naturestar:BAABLAAECoEbAAIOAAcI+g0WVgBLAQAOAAcI+g0WVgBLAQAAAA==.Natyala:BAABLAAECoEZAAIMAAgIfxjCMQBhAgAMAAgIfxjCMQBhAgAAAA==.',Ne='Nebring:BAAALAADCgUIBgAAAA==.',Ni='Nilwavy:BAAALAADCgYICQAAAA==.Nivd:BAAALAADCggICAAAAA==.',No='Nocent:BAAALAADCggICAAAAA==.Nocturm:BAAALAAECgUIBQAAAA==.Nohe:BAAALAADCggIGgAAAA==.Nowan:BAAALAADCggIFgAAAA==.',Nu='Nueleth:BAAALAADCgUIBQABLAAECgcIEgAIAAAAAA==.',['Nè']='Nèmesis:BAAALAADCgYIDAAAAA==.',Ol='Olgi:BAAALAADCgMIAwAAAA==.',On='Onefistyboy:BAAALAADCggIEAAAAA==.Onevoneme:BAAALAAECgQIBAAAAA==.',Op='Opheliah:BAAALAAECgYIDgAAAA==.',Pa='Paladerson:BAAALAAECgIIAgAAAA==.Palamala:BAAALAAECgYIBgAAAA==.Palladan:BAACLAAFFIEOAAIHAAUIriBBBgCLAQAHAAUIriBBBgCLAQAsAAQKgScAAgcACAhXJWIIAFQDAAcACAhXJWIIAFQDAAAA.Pandatings:BAAALAADCggICAAAAA==.',Pl='Plush:BAAALAAECgYICgAAAA==.',Po='Porcia:BAABLAAECoEWAAITAAcIpwe6qAAeAQATAAcIpwe6qAAeAQAAAA==.',Pr='Príesty:BAABLAAECoEcAAIPAAcIoRPvNwC7AQAPAAcIoRPvNwC7AQAAAA==.',Ps='Psirens:BAABLAAECoEWAAQUAAcIEB4GJAASAgAUAAcIEB4GJAASAgAVAAQIAQyHLgDCAAAOAAEIkQaUvAAhAAAAAA==.',Qy='Qysa:BAABLAAECoEYAAMPAAcIAhTVMwDRAQAPAAcIAhTVMwDRAQAaAAYIpBH4EQBMAQAAAA==.',Ra='Rabubabu:BAAALAAECgYIBgABLAAECggIGQAMAH8YAA==.Radhoc:BAAALAADCgcICQAAAA==.Raktrak:BAAALAADCgcIBwAAAA==.Rambôô:BAABLAAECoEZAAIOAAYIRhx6MADmAQAOAAYIRhx6MADmAQAAAA==.Ranna:BAABLAAECoEjAAIDAAgIpRF4RADxAQADAAgIpRF4RADxAQAAAA==.Raynieman:BAAALAAECggIBQAAAA==.Rayniemen:BAAALAAECggICAAAAA==.',Re='Redbeardd:BAABLAAECoEhAAMTAAgI2B/cGADIAgATAAgI2B/cGADIAgAZAAEIMg7CsgAoAAAAAA==.Reeko:BAAALAAECgcIHQAAAQ==.Renascentia:BAAALAADCgQIBAAAAA==.Rendoniss:BAABLAAECoEVAAMbAAgI+wqHGAB8AQAbAAgI+wqHGAB8AQAcAAEIMAcLWQA4AAAAAA==.',Rh='Rhoald:BAABLAAECoExAAISAAgIgyDWFQDhAgASAAgIgyDWFQDhAgAAAA==.',Ri='Rippy:BAAALAAFFAIIAgAAAA==.',Ro='Rothcore:BAABLAAECoEgAAMYAAgInyCBFAA1AgAYAAYIsyCBFAA1AgAJAAMIzxloHADyAAAAAA==.',Ru='Ruinedk:BAACLAAFFIELAAIGAAQICxfVCwBWAQAGAAQICxfVCwBWAQAsAAQKgS0AAgYACAiCImERABgDAAYACAiCImERABgDAAAA.Ruinersback:BAABLAAECoEXAAILAAcIBRyaFgAqAgALAAcIBRyaFgAqAgAAAA==.Russell:BAAALAAECgcIDgAAAA==.',Ry='Ryakuzou:BAAALAAECgcIBwAAAA==.',['Ré']='Rémus:BAAALAADCgYICgAAAA==.',Sa='Santaverde:BAAALAADCggICAAAAA==.Saphaera:BAAALAADCggIDwAAAA==.Satanisten:BAAALAADCgUICgAAAA==.',Sc='Scrog:BAAALAAECgcIBwAAAA==.Scylla:BAAALAAECggICAAAAA==.',Se='Sebej:BAAALAADCgIIAgAAAA==.Seraphena:BAAALAAECgIIAgAAAA==.Serinity:BAAALAAECgYIDgAAAA==.Serpez:BAAALAAECgMIAwAAAA==.',Sh='Shaarla:BAAALAAFFAIIAgABLAAFFAIICAADAIYdAA==.Shaggyrogers:BAAALAAECgQIBgAAAA==.Shahzad:BAAALAAECgYIBgAAAA==.',Sj='Sjager:BAABLAAECoEcAAMZAAcIEiGBGACGAgAZAAcIJiCBGACGAgATAAQIexh8rgARAQAAAA==.',Sk='Skopeutis:BAAALAADCgUIBQAAAA==.',Sl='Slayersboxer:BAAALAAECgIIAwAAAA==.',Sm='Smeister:BAABLAAECoEnAAICAAgIpyQ7AwBQAwACAAgIpyQ7AwBQAwAAAA==.',Sn='Sniggles:BAABLAAECoEmAAIEAAgIExhWKgA8AgAEAAgIExhWKgA8AgAAAA==.Sniperspeed:BAAALAADCggIDwAAAA==.Snuiter:BAAALAADCgYIBgAAAA==.',So='Soldshort:BAAALAADCggIDwABLAAECggIJQAHANcZAA==.Soothy:BAABLAAECoEZAAIRAAgISiAdCADCAgARAAgISiAdCADCAgAAAA==.Sootysh:BAAALAADCggICAABLAAECggIGQARAEogAA==.',Sp='Spartalock:BAAALAAECgcIEgAAAA==.Spiritivan:BAAALAADCggICgAAAA==.',St='Stamos:BAAALAADCgcIBwAAAA==.Stefi:BAAALAAECgYICQAAAA==.Stevie:BAAALAAECgcIEgAAAA==.',Ta='Taihuntsham:BAAALAAECgYIEQAAAA==.Targhor:BAAALAAECgUIBQAAAA==.',Te='Tenandris:BAAALAADCggICAAAAA==.Ternuvoker:BAAALAADCgYIBwABLAAECgYIIAANADgaAA==.',Th='Thelsennos:BAAALAADCgMIAwAAAA==.Thorí:BAAALAADCgUIBQAAAA==.Thristy:BAAALAAECgEIAQAAAA==.Thórinal:BAAALAADCgYIBgAAAA==.',Ti='Tievar:BAAALAAFFAQIBAAAAA==.Titanmage:BAAALAADCgEIAQAAAA==.',To='Tolmyr:BAAALAADCgQIBAAAAA==.',Tr='Traci:BAAALAADCggICAAAAA==.Tru:BAAALAADCgcIDgABLAAFFAMIBwAQACYTAA==.',Tu='Turowai:BAABLAAECoEZAAITAAYIJgjprQASAQATAAYIJgjprQASAQAAAA==.',Tw='Twocancarl:BAAALAAECggIEQAAAA==.',Ty='Tyarah:BAAALAAECgYIDgABLAAECgYIDgAIAAAAAA==.',Uk='Ukitake:BAAALAAECggICQAAAA==.',Ur='Ursur:BAAALAAECgQIBAAAAA==.',Va='Vaes:BAABLAAECoEmAAMNAAgIvh4JEQDEAgANAAgIvh4JEQDEAgAPAAEI4QHdjQAkAAAAAA==.Vandejoa:BAAALAAECgMIAQAAAA==.Vayne:BAABLAAECoEbAAIOAAcIQyDJFACKAgAOAAcIQyDJFACKAgAAAA==.',Ve='Velver:BAAALAADCggIEwAAAA==.Velvor:BAAALAADCggIJAAAAA==.Venakros:BAABLAAECoEfAAIWAAgI4CAFKQCQAgAWAAgI4CAFKQCQAgAAAA==.Venkhar:BAAALAAECgYIBgAAAA==.Ventaros:BAAALAAECgYIEgABLAAECggIHwAWAOAgAA==.',Vi='Vinnsanity:BAAALAAECgYICQABLAAECgcIHAAZABIhAA==.Vinzen:BAAALAAECgYIBgABLAAECgcIHAAZABIhAA==.Viosback:BAAALAADCgcIBwAAAA==.Viserionn:BAABLAAECoEUAAIQAAgIDBZIQgDnAQAQAAgIDBZIQgDnAQAAAA==.Vitorios:BAABLAAECoEaAAIcAAcIHRvFGAA9AgAcAAcIHRvFGAA9AgAAAA==.Vivian:BAAALAAECgcIEgAAAA==.',Vo='Volara:BAABLAAECoEXAAMdAAcIGxRvBwDXAQAdAAcIGxRvBwDXAQAcAAQIXgW/TQCMAAAAAA==.Voltaran:BAAALAAECgEIAQAAAA==.Volver:BAAALAAECgcIBwAAAA==.Vonji:BAABLAAECoEbAAIeAAcIQQ48LACsAQAeAAcIQQ48LACsAQAAAA==.Voodu:BAAALAAECgUIBQAAAA==.',Vr='Vredna:BAAALAAECgcIEQAAAA==.',['Vî']='Vîrtue:BAAALAAECgIIAgAAAA==.',Wa='Warren:BAABLAAECoEbAAIEAAcIAhj9NgD6AQAEAAcIAhj9NgD6AQAAAA==.',Wo='Woodie:BAAALAADCggIEAAAAA==.',Xa='Xarias:BAAALAAECgEIAQAAAA==.',Xe='Xenastraza:BAAALAAECgcICwAAAA==.',Xh='Xharin:BAAALAAECgQICQAAAA==.',Xl='Xlzm:BAABLAAECoETAAIcAAgIyxlCFgBYAgAcAAgIyxlCFgBYAgAAAA==.',Yi='Yiwofuren:BAAALAADCgcIBwAAAA==.',Yu='Yugbertem:BAAALAAECgMIBQABLAAECgYIBgAIAAAAAA==.',Yw='Ywenfach:BAAALAADCgEIAQAAAA==.',Ze='Zerant:BAAALAAECgUICgAAAA==.',Zi='Ziekgast:BAAALAADCggICAAAAA==.Zilvèr:BAAALAAECgYIBgAAAA==.Zim:BAAALAAECgYICAAAAA==.',['Zý']='Zýzz:BAAALAAFFAEIAQAAAA==.',['Ár']='Árthas:BAAALAAECggIDwABLAAFFAUIDgAHAK4gAA==.',['Îs']='Îshtar:BAAALAADCggIGwAAAA==.',['Ðr']='Ðrudict:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end