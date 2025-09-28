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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Druid-Restoration','Monk-Windwalker','Druid-Balance','Evoker-Devastation','Paladin-Protection','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Vengeance','Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Mage-Frost','DeathKnight-Blood','Paladin-Retribution','DeathKnight-Frost','Rogue-Subtlety','Rogue-Assassination','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','Mage-Fire','Warlock-Demonology','Warrior-Protection','Priest-Shadow','Hunter-BeastMastery','Monk-Mistweaver','Priest-Discipline','Monk-Brewmaster',}; local provider = {region='EU',realm="Kel'Thuzad",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abbas:BAAALAAECgYIEAAAAA==.',Ae='Aelluvienne:BAAALAAECgIIAgAAAA==.',Ag='Agarel:BAAALAADCggICAAAAA==.',Ak='Akraton:BAAALAADCggICAABLAADCggIDAABAAAAAA==.Akróma:BAABLAAECoEVAAICAAgINSG0FQD+AgACAAgINSG0FQD+AgAAAA==.',Al='Algalon:BAABLAAECoEdAAIDAAgIRhQeLwD2AQADAAgIRhQeLwD2AQAAAA==.Allacaya:BAAALAAECgUICgAAAA==.Allanea:BAAALAADCgcIBwAAAA==.Alyndriel:BAAALAAECgYIEAAAAA==.',An='Anfalas:BAAALAADCgcICQABLAAFFAUIEgAEAAUXAA==.Angsthasî:BAAALAAECgYIEAAAAA==.Anom:BAAALAAECggIBAAAAA==.Anthropic:BAAALAAECgYIDgAAAA==.',Ar='Arak:BAAALAAECggIDgAAAA==.Aranae:BAABLAAECoEXAAIFAAcI5w4pPwCIAQAFAAcI5w4pPwCIAQABLAAFFAUIDwAGAJobAA==.Aronta:BAABLAAECoEVAAIHAAgIeR9PCgCsAgAHAAgIeR9PCgCsAgAAAA==.',As='Asdasdk:BAAALAAECgYIDwAAAA==.Assault:BAAALAAECgEIAQAAAA==.Astramia:BAAALAADCggICAABLAAECgMICwABAAAAAA==.',Av='Avetaar:BAAALAADCgMIAwAAAA==.',Ay='Ayutra:BAACLAAFFIEGAAMGAAQIbAbADgC7AAAGAAMIpwfADgC7AAAIAAEIvAIiCABFAAAsAAQKgRsAAwYACAiAFsUhAO4BAAYACAiAFsUhAO4BAAkABgjSC8MiABIBAAAA.',Ba='Baaltyr:BAACLAAFFIEPAAIGAAUImht/BwBYAQAGAAUImht/BwBYAQAsAAQKgTMAAgYACAhEI24GACADAAYACAhEI24GACADAAAA.Babak:BAACLAAFFIEHAAMKAAII+BKcCgB8AAACAAIIBgt8NQCOAAAKAAII+BKcCgB8AAAsAAQKgSYAAwoACAgPGqAOAEsCAAoACAgPGqAOAEsCAAIABwhOEgxtAL8BAAAA.Balur:BAABLAAECoEUAAILAAYIiBZlZQC0AQALAAYIiBZlZQC0AQAAAA==.Balî:BAACLAAFFIEFAAIMAAMIpQ++GAC9AAAMAAMIpQ++GAC9AAAsAAQKgSIAAwwACAjGIA4LAPgCAAwACAjGIA4LAPgCAA0AAwgjCGmWAIEAAAAA.Barlorg:BAAALAADCgYIBgAAAA==.Bayan:BAAALAAECgYIBwABLAAECgYIEAABAAAAAA==.',Be='Beeva:BAAALAADCgUIBQAAAA==.Belicia:BAAALAADCggICAABLAAFFAMICAAOAHUfAA==.Besenstiel:BAAALAADCgYIBgAAAA==.',Bi='Big:BAAALAAECgIIAgAAAA==.Bigbrain:BAAALAAECgYICQABLAAFFAUIEgAEAAUXAA==.Bigmage:BAAALAADCgYIBgAAAA==.Bigwave:BAAALAADCgYIBgAAAA==.',Bl='Bloodymarìe:BAAALAAECgQICAAAAA==.',Bo='Bozza:BAAALAADCggICAAAAA==.',Br='Braini:BAAALAAECggICgABLAAFFAUIEgAEAAUXAA==.Brazy:BAAALAAECgEIAQAAAA==.',Ca='Canondorf:BAACLAAFFIEHAAIFAAIILiG3DQDAAAAFAAIILiG3DQDAAAAsAAQKgSQAAgUACAjbIyIIACUDAAUACAjbIyIIACUDAAAA.',Ch='Chaneirá:BAAALAADCggICAABLAAECggIFgAPAJQaAA==.Charcoal:BAAALAADCgIIAgABLAAECggINgAQAOQhAA==.Chazer:BAAALAAECgYIBgABLAAECgYIBwABAAAAAA==.Cheesecake:BAABLAAECoEbAAIRAAcIOQpdtgBkAQARAAcIOQpdtgBkAQAAAA==.Chiku:BAABLAAECoEcAAMSAAYIBAkeKAAiAQASAAYIBAkeKAAiAQATAAMIogqWUwCkAAAAAA==.Chilliwillie:BAAALAADCggICAAAAA==.Chumâni:BAAALAADCgQIBAAAAA==.Chè:BAAALAAECgEIAQAAAA==.Chötzli:BAACLAAFFIEHAAIRAAQIAhFeGwDeAAARAAQIAhFeGwDeAAAsAAQKgSEAAhEACAhAI30NAC4DABEACAhAI30NAC4DAAAA.',Ci='Ciroline:BAAALAAECgMIAwAAAA==.',Co='Concept:BAAALAAECgYIBgABLAAECgYIFAALAIgWAA==.Coolekuh:BAABLAAECoEiAAIUAAgI5x7SBwC+AgAUAAgI5x7SBwC+AgAAAA==.',Cr='Crazeefreeze:BAAALAAECgcICwAAAA==.',['Cá']='Cáitlyn:BAAALAAECggIBwAAAA==.',['Cì']='Cìri:BAAALAAECgUICQAAAA==.',Da='Daleila:BAAALAAECggIEAAAAA==.Dalline:BAAALAAECgIIBAAAAA==.',Dd='Ddback:BAAALAAECggIEAAAAA==.',De='Debro:BAAALAAECgIIAwAAAA==.Deet:BAABLAAECoEfAAMMAAgIgBxPIQBtAgAMAAgIgBxPIQBtAgANAAEIRwSWrgAxAAAAAA==.Dejay:BAAALAAECgMIAwABLAAECgcIGwAVAG4MAA==.Demerus:BAAALAAECgUIDgAAAA==.Demeya:BAAALAAECgYIDAAAAA==.Demonja:BAAALAAECggICAAAAA==.Dentera:BAAALAADCgEIAQABLAAECgcIIQAQAIMjAA==.Depletas:BAACLAAFFIEKAAMWAAIIyRpUBACLAAAXAAIIyRrgIwCcAAAWAAIIfApUBACLAAAsAAQKgSYAAxYACAi+IN8FAJECABcACAiYHdYcALgCABYACAgFHt8FAJECAAAA.',Dj='Djarii:BAAALAADCgcIBwAAAA==.',Do='Donnerbräu:BAAALAADCggIFwAAAA==.Dora:BAAALAADCgQIBwAAAA==.',Dr='Draconya:BAAALAAECggICAAAAA==.Draggi:BAAALAADCgYIBgAAAA==.Draginoi:BAAALAAECgYIEAAAAA==.Draufgänger:BAABLAAECoEwAAMCAAgIMRPlWADwAQACAAgIHhPlWADwAQAKAAgISwo0QgCYAAAAAA==.Drfrost:BAABLAAECoEjAAIRAAgIrhQtWgAQAgARAAgIrhQtWgAQAgAAAA==.Drument:BAABLAAECoEYAAMDAAgIggYjaAAdAQADAAgIggYjaAAdAQAFAAUI6BHMXgD+AAAAAA==.Drumonk:BAAALAADCggICwABLAAECggIGAADAIIGAA==.Drumont:BAAALAAECgYIEQAAAA==.',Du='Duckdot:BAAALAADCggIHQABLAAECgIIAgABAAAAAA==.Dumpledore:BAAALAAECggICAAAAA==.',['Dá']='Dáin:BAAALAADCggIDAAAAA==.',Eh='Ehegorn:BAAALAADCgcIBwAAAA==.',El='Elayne:BAAALAAECgEIAQAAAA==.Eleonoway:BAACLAAFFIEHAAIYAAIIfhTjFgCbAAAYAAIIfhTjFgCbAAAsAAQKgSwAAhgACAiDIqAJAA8DABgACAiDIqAJAA8DAAAA.Elinna:BAAALAADCgMIBAAAAA==.',En='Envyxm:BAAALAADCgcIBwAAAA==.Enziano:BAAALAAECgMIBQAAAA==.',Es='Escanor:BAAALAAECgYIBgAAAA==.',Eu='Eury:BAAALAADCgYIBgAAAA==.',Fa='Fabi:BAAALAAECggIEAAAAA==.Fanatica:BAAALAADCggICAABLAAECgYIBwABAAAAAA==.Farugo:BAABLAAECoEVAAMZAAgIBRW8VgC5AQAZAAgI8xG8VgC5AQAaAAIIYSAAAAAAAAAAAA==.',Fe='Feiron:BAAALAAECggIEAAAAA==.Ferrers:BAABLAAECoEeAAQOAAcIuxThMQCMAQAOAAYIExbhMQCMAQAbAAcIuQ2eDAAvAQALAAQITghvswDEAAAAAA==.',Fi='Fiftys:BAABLAAECoEVAAINAAgIARwsIACBAgANAAgIARwsIACBAgAAAA==.',Fl='Fluppi:BAABLAAECoEXAAIZAAcI7xpgNgA0AgAZAAcI7xpgNgA0AgAAAA==.',Fr='Frozztina:BAAALAADCgUIBQAAAA==.',Fu='Furball:BAAALAAECgYICgAAAA==.',['Fí']='Fíora:BAAALAADCggIFgAAAA==.',Ga='Gaila:BAAALAAECgQIBAABLAAFFAIICgAWAMkaAA==.Galoc:BAABLAAECoEnAAIZAAgI+xyLHwCsAgAZAAgI+xyLHwCsAgAAAA==.',Ge='Geforce:BAAALAADCgYIBgAAAA==.Geno:BAAALAAECgEIAQAAAA==.Georg:BAABLAAECoEXAAMIAAgISCKyAQD2AgAIAAgIRCGyAQD2AgAGAAgIPR5gDQDEAgAAAA==.',Gi='Gimpelhexe:BAABLAAECoErAAIZAAgIKxiSMgBFAgAZAAgIKxiSMgBFAgAAAA==.Gini:BAAALAAECggIAgAAAA==.Giru:BAAALAADCggICAABLAAECgYIDQABAAAAAA==.',Gn='Gnomenpresse:BAAALAADCgcIBwAAAA==.',Go='Gono:BAAALAADCgcIDQAAAA==.Gontlike:BAAALAAECgMIAwAAAA==.Gooni:BAAALAAECgIIAgAAAA==.Gorgó:BAABLAAECoEVAAMcAAYIaBneJwC3AQAcAAYI0xjeJwC3AQAZAAMIgBHvrgC0AAAAAA==.',Gr='Grazzman:BAAALAAECgIIAgAAAA==.Griotamashar:BAAALAADCggIDwAAAA==.Grolock:BAAALAAECgYIEwAAAA==.Gráubart:BAAALAAECggIEAAAAA==.',Gu='Gumbel:BAAALAADCgcIBwAAAA==.',Ha='Hailmary:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Hammerdin:BAAALAAECgMIBAABLAAFFAIICgAWAMkaAQ==.Hardgore:BAAALAAECggICAAAAA==.Hase:BAAALAAECgEIAQAAAA==.Hatorihanzoo:BAAALAADCgYIEAAAAA==.Haudrauf:BAAALAAECgIIAgAAAA==.Haxil:BAACLAAFFIEKAAQXAAQIZg0BDgAWAQAXAAQIOwoBDgAWAQAWAAIIwQTPBAB+AAAdAAIIsxkAAAAAAAAsAAQKgSkABBYACAieIKwJACsCABcACAg3IFMnAHYCAB0ABwhZHnEWAFECABYACAjgF6wJACsCAAAA.',He='Hellokîtty:BAAALAADCggICAAAAA==.',Ho='Holyhubert:BAABLAAECoEbAAMVAAcIbgwmVwBXAQAVAAcIbgwmVwBXAQAeAAUIyALddQCGAAAAAA==.Horendoss:BAAALAADCgMIAwAAAA==.',Hy='Hyutra:BAACLAAFFIEMAAILAAMI9yCWFAAhAQALAAMI9yCWFAAhAQAsAAQKgSoAAwsACAiWJHQGAFMDAAsACAiWJHQGAFMDABsAAQhKEz8cAD4AAAEsAAUUBAgGAAYAbAYA.',['Hè']='Hèllcruiser:BAABLAAECoEUAAIYAAYIjRT2SgBwAQAYAAYIjRT2SgBwAQAAAA==.',['Hê']='Hêndragôn:BAABLAAECoE2AAIQAAgI5CG8FQAIAwAQAAgI5CG8FQAIAwAAAA==.',['Hî']='Hîtme:BAACLAAFFIESAAIEAAUIBRdKAwCiAQAEAAUIBRdKAwCiAQAsAAQKgTEAAgQACAhRIssGABADAAQACAhRIssGABADAAAA.',Il='Ildai:BAAALAADCgQIBAABLAAFFAUIDwAGAJobAA==.',In='Indathan:BAAALAAECgYIDQAAAA==.Indecorus:BAAALAAECgMICwAAAA==.Insena:BAACLAAFFIEMAAIfAAMIHRPiFwDIAAAfAAMIHRPiFwDIAAAsAAQKgTEAAh8ACAiYHuYhAJ0CAB8ACAiYHuYhAJ0CAAAA.',Is='Ischisu:BAAALAAECgYIFgAAAQ==.',['Iø']='Iø:BAAALAADCgcIBwABLAAECgYIGwANAPEUAA==.',Ja='Jackz:BAAALAAECgIIAgAAAA==.Jaisy:BAAALAADCgYIBgAAAA==.Jakzz:BAAALAAECgYIBgAAAA==.Jaxira:BAAALAAECgYIBgAAAA==.',Ji='Jinyou:BAACLAAFFIELAAICAAMIlCV+DABEAQACAAMIlCV+DABEAQAsAAQKgSUAAgIACAi7JqMAAJcDAAIACAi7JqMAAJcDAAAA.',Jo='Jochén:BAAALAADCggICAAAAA==.Johnsenf:BAAALAADCgQIBgAAAA==.Jonahs:BAABLAAECoEeAAIQAAgIfRPUbADgAQAQAAgIfRPUbADgAQAAAA==.',['Já']='Jáina:BAAALAAECggICAAAAA==.',Ka='Kailarei:BAAALAAECgcIEwABLAAFFAIICgAWAMkaAQ==.Kamy:BAAALAAECgEIAQAAAA==.Katárina:BAAALAAECggIEAAAAA==.',Kh='Khaliisha:BAAALAADCggICAABLAAECggIDgABAAAAAA==.',Ki='Kiiwi:BAAALAAECgcIDwAAAA==.Kinvara:BAABLAAECoEcAAIVAAYIsBoHSgCJAQAVAAYIsBoHSgCJAQAAAA==.Kiyam:BAAALAAECgUICAABLAAECggIGAADAIIGAA==.Kiyan:BAAALAAECgIIAgABLAAECggIGAADAIIGAA==.Kiyando:BAAALAAECgIIAgABLAAECggIGAADAIIGAA==.Kiyane:BAAALAAECgYIDwABLAAECggIGAADAIIGAA==.Kiyani:BAAALAADCggIEAABLAAECggIGAADAIIGAA==.Kiyanio:BAAALAAECgYIDAABLAAECggIGAADAIIGAA==.Kiyano:BAAALAAECgUICQABLAAECggIGAADAIIGAA==.Kiyanu:BAABLAAECoEYAAIMAAgIiROIUQDAAQAMAAgIiROIUQDAAQABLAAECggIGAADAIIGAA==.',Ko='Kornexperte:BAAALAADCgQIBAAAAA==.',Ku='Kungfukuh:BAAALAAECggIEQAAAA==.',Ky='Kylus:BAAALAADCgcICwABLAAECgEIAQABAAAAAA==.Kynara:BAAALAADCgcIDQAAAA==.',La='Labellina:BAABLAAECoEWAAIVAAYIqB/4KQAhAgAVAAYIqB/4KQAhAgABLAAECgcIIQAVAFMkAA==.Lachsfilet:BAAALAADCgcIBwAAAA==.Latruen:BAABLAAECoEcAAIQAAgILBjqQQBLAgAQAAgILBjqQQBLAgAAAA==.',Le='Less:BAAALAAECggICAAAAA==.Lestarte:BAABLAAECoEUAAIXAAYIMBQ0ZACNAQAXAAYIMBQ0ZACNAQAAAA==.Lexx:BAAALAAECgYICQAAAA==.',Li='Likörchen:BAAALAAECgMIAwAAAA==.Lizzee:BAAALAAECgYICAAAAA==.',Ll='Lloyd:BAABLAAECoEmAAIXAAgIOhsFIgCWAgAXAAgIOhsFIgCWAgAAAA==.',Lu='Luci:BAAALAADCgIIAgABLAADCggIDAABAAAAAA==.Lucrum:BAABLAAECoEcAAMCAAcIGxCUhwCIAQACAAcIMg2UhwCIAQAKAAYI7w2xLgANAQAAAA==.Lucrumdruid:BAAALAADCggICAAAAA==.Lunariel:BAAALAADCgQIBAAAAA==.Lunarii:BAAALAAECgYIDgAAAA==.Lupina:BAAALAAECgEIAgAAAA==.Lusyloo:BAAALAAECgMIAwABLAAECgYIBwABAAAAAA==.',['Lí']='Línkin:BAAALAADCgIIAgAAAA==.',Ma='Maragoth:BAAALAADCggIDwAAAA==.Maylu:BAAALAAECgYIDAAAAA==.',Me='Meatshield:BAAALAAECgYIEQAAAA==.Medura:BAAALAAECgIIBAAAAA==.Meleebrain:BAAALAADCgYIBwABLAAFFAUIEgAEAAUXAA==.Meradesch:BAAALAADCggICgABLAAECgcIHQAfAMUTAA==.',Mi='Mikarai:BAAALAADCgQIBAABLAAECggIEAABAAAAAA==.Milkshocklat:BAAALAAECgEIAQAAAA==.Millim:BAAALAAECgYICAAAAA==.Mimiteh:BAABLAAECoEfAAINAAcIFBn7MgAVAgANAAcIFBn7MgAVAgAAAA==.',Mo='Monkii:BAABLAAECoEbAAIgAAcILgphLQABAQAgAAcILgphLQABAQAAAA==.Moottv:BAAALAADCgEIAQAAAA==.Morgvomorg:BAABLAAECoEdAAIfAAcIxROXbgCjAQAfAAcIxROXbgCjAQAAAA==.Motte:BAAALAADCgIIAgAAAA==.',Mu='Muzét:BAAALAAECgIIAgAAAA==.',['Mö']='Mönchlina:BAAALAAECggICAAAAA==.',Na='Naish:BAACLAAFFIEIAAIeAAMInRDKDgDgAAAeAAMInRDKDgDgAAAsAAQKgTAAAh4ACAhQJEYGAEADAB4ACAhQJEYGAEADAAAA.Naku:BAABLAAECoEdAAMaAAgIfhlACwDkAQAZAAgIfhknMQBMAgAaAAgIeg5ACwDkAQABLAAFFAQIBgAGAGwGAA==.Narune:BAABLAAECoEjAAIFAAgINRnxJgAIAgAFAAgINRnxJgAIAgAAAA==.',Ne='Necromenia:BAABLAAECoEhAAIDAAgI1RtGFgCGAgADAAgI1RtGFgCGAgAAAA==.Nedbigbi:BAACLAAFFIEMAAIRAAMIUBS0FgD7AAARAAMIUBS0FgD7AAAsAAQKgS8AAhEACAi1IugSABIDABEACAi1IugSABIDAAAA.Nekrothar:BAAALAAECgIIAgAAAA==.Neony:BAAALAADCgcIBwAAAA==.',Nh='Nhumrod:BAABLAAECoEZAAIYAAcIZg1iVgBFAQAYAAcIZg1iVgBFAQAAAA==.',Ni='Nightglen:BAAALAAECgMIAwAAAA==.Nihl:BAAALAADCgQIBAAAAA==.Nirinia:BAAALAAECgcIBwABLAAFFAMICAAeAJ0QAA==.',No='Noirrion:BAABLAAECoEnAAMfAAgIChYfYADGAQAfAAgIChYfYADGAQAYAAMICwb7mgBdAAAAAA==.Nomad:BAAALAADCgIIAgAAAA==.',Nu='Nufa:BAAALAAECgIIAgAAAA==.',Ny='Nyandrix:BAAALAAECgEIAQAAAA==.Nymería:BAAALAAECgEIAQAAAA==.',['Ná']='Nádeya:BAEBLAAECoEUAAMFAAYIEB8gJwAGAgAFAAYIEB8gJwAGAgADAAEInglXvQArAAAAAA==.',['Né']='Nélvin:BAAALAADCgQIBAAAAA==.Néváh:BAABLAAECoEWAAMGAAYIQwRgSgC+AAAGAAYIQwRgSgC+AAAJAAIIOAKnNwA4AAAAAA==.',['Nê']='Nêvah:BAAALAAECgcICgAAAA==.',['Nô']='Nônâme:BAAALAAECgMIBQAAAA==.',Or='Originaldrac:BAAALAAECgcIEAAAAA==.Ortek:BAAALAAECgEIAQAAAA==.',Pa='Paola:BAAALAAECgEIAQAAAA==.',Pe='Pelliox:BAACLAAFFIESAAMFAAUIbhnUBgBbAQAFAAQIXBzUBgBbAQADAAQIXwYiCwDuAAAsAAQKgTAAAwUACAj8JRcCAHYDAAUACAj8JRcCAHYDAAMACAhED1FJAIMBAAAA.Pendarean:BAAALAAECggIDAAAAA==.',Ph='Phantastic:BAAALAAECgYIBgABLAAECgYIBwABAAAAAA==.Phoebé:BAAALAAECgcIDAABLAAECggIGgASAMALAA==.',Pi='Pixel:BAAALAAECgQIDQAAAA==.',Pn='Pnfüsi:BAAALAADCgYIBgABLAAFFAQIBwARAAIRAA==.',Pr='Prizen:BAAALAAECgMIAwABLAAFFAQIDAALAKgPAA==.Prototank:BAAALAADCgEIAQAAAA==.',['Pø']='Pøstmørtem:BAAALAAECgYIBwAAAA==.',Qo='Qorn:BAAALAADCggICAAAAA==.',Ra='Rageheart:BAAALAADCgEIAQAAAA==.Ragingordon:BAAALAAECgYIBgAAAA==.Rakeesh:BAAALAAECggICAAAAA==.Ranada:BAAALAAECgEIAQAAAA==.Raspberry:BAAALAAECgQICQAAAA==.',Re='Rebbenole:BAAALAAECgYICQAAAA==.',Rh='Rhogata:BAAALAAECgYICAAAAA==.',Ri='Riddim:BAAALAAECggICAAAAA==.Rider:BAAALAAECgIIAgABLAAECgYIBwABAAAAAA==.Rittorn:BAABLAAECoEVAAIRAAgI5BDafwDCAQARAAgI5BDafwDCAQAAAA==.',Ro='Rooibos:BAAALAAECggIAQAAAA==.',Ru='Ruhepuls:BAABLAAECoEUAAMfAAYIWg4QpQA1AQAfAAYIWg4QpQA1AQAYAAEIwgt8sgAtAAAAAA==.',['Rü']='Rührfischle:BAAALAADCgEIAQAAAA==.',Sa='Saba:BAAALAADCgcIBwAAAA==.Saoirse:BAAALAADCgYIBgABLAADCgcIBwABAAAAAA==.Saya:BAAALAADCgEIAQABLAAECgcIIQAQAIMjAA==.',Sc='Schocknorris:BAAALAAECgQIBAAAAA==.',Se='Senadraz:BAAALAAECgYIBgABLAAECgcIIQAQAIMjAA==.Sendhelppls:BAAALAAECgYIBgAAAA==.Sequana:BAAALAAECggIDwAAAA==.Session:BAAALAADCgcICQAAAA==.',Sh='Shade:BAAALAADCggICAAAAA==.Shadowlîke:BAAALAADCggIDAAAAA==.Shawnee:BAAALAADCgcIBwABLAAECgYIGgAUAJcKAA==.Shaylo:BAAALAAECgQIBAAAAA==.Sheldor:BAAALAAECgIIBAABLAAECgcIHQAfAMUTAA==.Shifthappens:BAABLAAECoEvAAIFAAgI/CTNBgA3AwAFAAgI/CTNBgA3AwAAAA==.',Si='Silvara:BAAALAADCgcIBwAAAA==.Sisalinaa:BAAALAADCgcIBwAAAA==.Sitas:BAAALAAECgYICAAAAA==.',Sk='Skalaska:BAAALAADCggICAAAAA==.Skalinska:BAAALAADCggICAAAAA==.Skyfiré:BAAALAAECgYICAABLAAECggIFQACADUhAA==.',Sl='Slieze:BAAALAADCggIEAAAAA==.',Sm='Smasher:BAAALAAECgEIAQAAAA==.Smokason:BAAALAADCggIDgAAAA==.',So='Solarius:BAAALAAECgUIBQAAAA==.Soldrake:BAAALAAECgYIBgABLAAFFAIICgAWAMkaAA==.Solot:BAAALAAECgQIBAAAAA==.Sorfilia:BAACLAAFFIEGAAICAAMI/xBAFQDkAAACAAMI/xBAFQDkAAAsAAQKgRoAAgIACAgdIAsjALUCAAIACAgdIAsjALUCAAAA.',Sp='Spir:BAACLAAFFIEHAAIDAAIIMSAUEwC5AAADAAIIMSAUEwC5AAAsAAQKgSQAAgMACAgcJAYHABMDAAMACAgcJAYHABMDAAAA.',St='Stardust:BAACLAAFFIEFAAMHAAII9gwNEQB4AAAQAAIIxgnSOACRAAAHAAIISwwNEQB4AAAsAAQKgR0AAwcACAiPFwEiAK8BABAABwjqFaF3AMoBAAcABgicFwEiAK8BAAAA.Stickét:BAABLAAECoEbAAIYAAYIlyHjIgA8AgAYAAYIlyHjIgA8AgABLAAFFAUIDwALANMbAA==.Stárdust:BAAALAAFFAEIAQAAAA==.',Su='Subsonic:BAABLAAECoEYAAMcAAcICwWAUwD5AAAcAAcI3QKAUwD5AAAZAAcICwUAAAAAAAAAAA==.Sugár:BAAALAAECgUICAABLAAECgYIBwABAAAAAA==.Susano:BAAALAAECgUICAAAAA==.Susi:BAAALAAECgYIDwAAAA==.',Sw='Swixxbims:BAAALAAECgcIBwAAAA==.Swixxwins:BAAALAAECggIDQAAAA==.Swürgelchen:BAACLAAFFIEHAAIVAAIIYRELIgCVAAAVAAIIYRELIgCVAAAsAAQKgSQAAxUACAjBGN4fAF0CABUACAjBGN4fAF0CACEAAQiICXA2ACkAAAAA.',Sy='Synnmage:BAACLAAFFIEMAAILAAUI2iB9CADjAQALAAUI2iB9CADjAQAsAAQKgTAAAgsACAhiJPALACsDAAsACAhiJPALACsDAAAA.',Ta='Taiji:BAAALAADCggIFgAAAA==.Takao:BAABLAAECoEpAAIQAAgIJh26KACpAgAQAAgIJh26KACpAgAAAA==.Tamayo:BAAALAAECgIIBAAAAA==.',Te='Terageal:BAAALAAECgIIBAAAAA==.Teresa:BAAALAADCgcIBwAAAA==.',Th='Thorwa:BAABLAAECoEhAAIQAAcIgyNrJgCzAgAQAAcIgyNrJgCzAgAAAA==.Thylin:BAACLAAFFIEMAAIiAAMIoB2tBgATAQAiAAMIoB2tBgATAQAsAAQKgS8AAiIACAgHJNkCAEEDACIACAgHJNkCAEEDAAAA.Thymiana:BAEALAADCggICAABLAAECgYIFAAFABAfAA==.Thámek:BAAALAAECgIIAgAAAA==.',Ti='Tiaraba:BAAALAADCgcIBwAAAA==.Tiecr:BAAALAADCgcICAAAAA==.',To='Tokrika:BAABLAAECoEUAAIVAAgIBBMUNgDiAQAVAAgIBBMUNgDiAQAAAA==.Toph:BAAALAADCggIGQAAAA==.',Tr='Trismegistus:BAEALAADCgYIBgABLAAECgYIFAAFABAfAA==.',Tu='Tugdil:BAAALAAECgIIAgAAAA==.',Ty='Tyraél:BAABLAAECoEgAAMQAAYIiyHnUQAeAgAQAAYIiyHnUQAeAgAHAAEISA4iXwAzAAAAAA==.Tyrø:BAAALAADCggIEAAAAA==.',['Tù']='Tùsk:BAAALAAECgMIBQAAAA==.',Uh='Uhry:BAAALAADCgcIBwAAAA==.',Us='Usô:BAAALAAECgYIDQAAAA==.',Va='Vaney:BAAALAADCgcIEAAAAA==.Vanitas:BAACLAAFFIEIAAIOAAMIdR/9AgARAQAOAAMIdR/9AgARAQAsAAQKgScAAg4ACAhTJkQBAH0DAA4ACAhTJkQBAH0DAAAA.Vanthyr:BAAALAADCggIDwAAAA==.Varimathris:BAABLAAECoEfAAMeAAgIJhzxGACOAgAeAAgIJhzxGACOAgAVAAYInhQfSQCMAQAAAA==.',Ve='Vellu:BAAALAAECgQIBgAAAA==.',Vi='Violencé:BAAALAADCgMIAwAAAA==.',Vo='Voidrend:BAAALAAECgYIBgAAAA==.Volthalak:BAACLAAFFIERAAMRAAYI3xnAAwApAgARAAYI3xnAAwApAgAPAAIIxhGGCwCEAAAsAAQKgS0AAxEACAhGJeYNACwDABEACAhGJeYNACwDAA8ACAjlHbAJAJcCAAAA.',Vu='Vulcanor:BAABLAAECoEbAAMNAAYI8RShUQCXAQANAAYI8RShUQCXAQAMAAEIZCVZ8ABmAAAAAA==.',Wa='Waldbeatle:BAAALAAECgYIBwAAAA==.Wantanran:BAAALAAECgMICQAAAA==.',We='Wenty:BAAALAAECgIIAgAAAA==.',Wi='Windgrace:BAAALAAECgYIEQAAAA==.Winghaven:BAAALAADCggIDAAAAA==.',Xe='Xenyos:BAAALAADCgYICQAAAA==.Xerberi:BAAALAAECgIIAgAAAA==.',Xy='Xyoo:BAAALAAECgIIAgAAAA==.',Yo='Yogibär:BAAALAAECgUICgAAAA==.Yolojuli:BAAALAAECgEIAgAAAA==.',Yv='Yvarr:BAAALAADCggIBAAAAA==.',Za='Zarusa:BAAALAAECggIEgAAAA==.',Ze='Zelpin:BAABLAAECoEWAAIKAAYIBRdFIAB8AQAKAAYIBRdFIAB8AQAAAA==.Zent:BAACLAAFFIEMAAILAAQIqA/NEgA8AQALAAQIqA/NEgA8AQAsAAQKgScAAgsACAhzHiMuAHkCAAsACAhzHiMuAHkCAAAA.Zentpala:BAAALAAECgYIDQABLAAFFAQIDAALAKgPAA==.Zeppo:BAABLAAECoEcAAIeAAgIkhHoLAAAAgAeAAgIkhHoLAAAAgABLAAFFAMIBQAZAG0JAA==.Zethos:BAAALAAECgEIAQABLAAECgYIBwABAAAAAA==.',Zi='Zidina:BAACLAAFFIEKAAINAAMIGRxRDAAnAQANAAMIGRxRDAAnAQAsAAQKgScAAg0ACAicIskJADIDAA0ACAicIskJADIDAAAA.Zitterfaust:BAAALAAECgcIEAAAAA==.',Zo='Zophie:BAAALAADCgcICwAAAA==.Zorkas:BAAALAAECgUIAQAAAA==.',Zr='Zrada:BAAALAADCggICAAAAA==.',Zs='Zsky:BAABLAAECoEUAAIQAAcIHhceagDmAQAQAAcIHhceagDmAQAAAA==.',Zy='Zyleane:BAAALAADCggICAAAAA==.',['Zè']='Zèrry:BAAALAADCggIDAAAAA==.',['Ðe']='Ðean:BAAALAAECgMIAwABLAAECggICAABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end