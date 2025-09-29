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
 local lookup = {'Warlock-Demonology','Hunter-Marksmanship','DemonHunter-Havoc','Paladin-Retribution','Evoker-Devastation','Druid-Guardian','Hunter-BeastMastery','Warlock-Destruction','Rogue-Outlaw','Rogue-Assassination','Druid-Restoration','Unknown-Unknown','Priest-Shadow','Druid-Feral','Mage-Arcane','Mage-Frost','Mage-Fire','Priest-Holy','Priest-Discipline','Paladin-Holy','Warrior-Fury','Shaman-Elemental','Paladin-Protection','Druid-Balance','Monk-Windwalker','DemonHunter-Vengeance','Shaman-Restoration',}; local provider = {region='EU',realm='Bloodscalp',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ak='Akemy:BAAALAADCggICQAAAA==.',Al='Alien:BAAALAAECgUIBQAAAA==.',As='Ashtoreth:BAABLAAECoEYAAIBAAYIzRbKKQCpAQABAAYIzRbKKQCpAQAAAA==.Astor:BAAALAADCgcIGQAAAA==.',Az='Azie:BAABLAAECoEiAAICAAgIdSCZEgC6AgACAAgIdSCZEgC6AgAAAA==.',Be='Belezogep:BAABLAAECoEZAAIDAAcInRIraQDAAQADAAcInRIraQDAAQAAAA==.',Bl='Blackwind:BAAALAADCggICAAAAA==.',Bo='Boltyourbean:BAAALAAECggIDgABLAAECggIJQAEAKgkAA==.',Ch='Chugnorris:BAAALAADCgQIBAABLAAECggIIAAFALAQAA==.',Ci='Cirkuskungen:BAAALAAECgQIAwAAAA==.Citoplazma:BAAALAADCggIDwAAAA==.',Cl='Clarabelle:BAABLAAECoEeAAIGAAgIIxYeCQAcAgAGAAgIIxYeCQAcAgAAAA==.',Co='Codex:BAACLAAFFIEHAAIHAAMIWBO1EADnAAAHAAMIWBO1EADnAAAsAAQKgToAAgcACAh1IxUMABwDAAcACAh1IxUMABwDAAAA.Cottoneyejoe:BAAALAADCggIDgAAAA==.',Cp='Cptpicard:BAAALAADCggIEAAAAA==.Cpttower:BAAALAADCggIJgAAAA==.',Cr='Cryptolon:BAABLAAECoEXAAIIAAYIFhmuTwDIAQAIAAYIFhmuTwDIAQAAAA==.',Da='Darthmalak:BAABLAAECoEdAAMJAAgIhxjgBgATAgAJAAcI/BjgBgATAgAKAAUIRxKNOQBfAQAAAA==.Darthpsydius:BAAALAADCgIIAgABLAAECggIIAAFALAQAA==.',De='Delly:BAAALAAECgEIAQAAAA==.Derl:BAAALAAECgYICwAAAA==.',Di='Diversity:BAACLAAFFIEGAAILAAIICBHuHgCKAAALAAIICBHuHgCKAAAsAAQKgSoAAgsACAggHSgXAHgCAAsACAggHSgXAHgCAAAA.Divinyl:BAAALAADCgUIBQAAAA==.',Dr='Dreamfire:BAAALAADCgcICgAAAA==.',Du='Dumog:BAAALAADCgcICAAAAA==.',['Dö']='Dödsgeneral:BAAALAADCgUIBQABLAAECgEIAQAMAAAAAA==.',El='Elemqt:BAAALAADCgMIAwAAAA==.',En='Envee:BAAALAAECgYIEgAAAA==.',Ep='Epicentre:BAAALAAECgEIAgAAAA==.',Er='Ericius:BAAALAADCggICAAAAA==.',Es='Espclose:BAABLAAECoEfAAINAAcIVyJmFACwAgANAAcIVyJmFACwAgAAAA==.',Fe='Felgibson:BAAALAAECgYIBgABLAAECggIIAAFALAQAA==.',Fl='Flare:BAAALAAECgIIAgAAAA==.Flavin:BAAALAAECgUICAAAAA==.',Gh='Ghizbolt:BAAALAADCggIDQAAAA==.',Go='Goldiepawn:BAABLAAECoEgAAIFAAgIsBDkIADuAQAFAAgIsBDkIADuAQAAAA==.',Gr='Grahn:BAABLAAECoEWAAIOAAgI3BQUEgAFAgAOAAgI3BQUEgAFAgAAAA==.Graland:BAABLAAECoEUAAQPAAgI9RtiNgBMAgAPAAgIPhtiNgBMAgAQAAEI1xz+dQBFAAARAAEIKwkPHwAwAAAAAA==.Grayson:BAAALAADCgYIBgABLAAFFAMIBgAHAK8bAA==.Greenhearts:BAAALAADCgYIDQAAAA==.',Ha='Hadvezer:BAAALAAECggIEwAAAA==.Hairypawter:BAAALAAECgQIBAABLAAECggIIAAFALAQAA==.Haru:BAAALAAECgUIBQABLAAECggIEgAMAAAAAA==.',Ho='Holyjustice:BAAALAADCggICAAAAA==.Holysith:BAAALAAECgEIAQAAAA==.Hoori:BAABLAAECoEWAAIEAAYISxBZqgBkAQAEAAYISxBZqgBkAQAAAA==.Hopebreakers:BAAALAAECgEIAQAAAA==.',Hu='Huntarto:BAAALAADCggIGAAAAA==.',Im='Impernal:BAABLAAECoEdAAIKAAgIFxkOFABoAgAKAAgIFxkOFABoAgAAAA==.',Ir='Ironmíke:BAAALAADCgIIAgAAAA==.',Ja='Jaenor:BAABLAAECoEfAAMSAAgIxSIuCQAPAwASAAgIxSIuCQAPAwATAAEIRhQoLwA8AAAAAA==.',Je='Jenn:BAABLAAECoEdAAIHAAgIRhfWQAATAgAHAAgIRhfWQAATAgAAAA==.',Jo='Jorguina:BAAALAADCgcIBwAAAA==.',Ju='Jugaruh:BAABLAAECoEfAAIUAAgI+yAGBQD9AgAUAAgI+yAGBQD9AgAAAA==.Junglemoon:BAAALAADCggIFQAAAA==.',Ka='Kahlan:BAAALAADCggIDQAAAA==.Kakeldos:BAABLAAECoEoAAIVAAgI4Rn2JQB1AgAVAAgI4Rn2JQB1AgAAAA==.',Kn='Knuffelpàndà:BAAALAADCggICAAAAA==.',Ko='Kordrax:BAABLAAECoEcAAIDAAcIPRkbTwADAgADAAcIPRkbTwADAgAAAA==.Kormoska:BAAALAAECgYICQAAAA==.',Kr='Krissinov:BAAALAADCggICAAAAA==.Krpa:BAAALAAECgIIAgAAAA==.',Ku='Kuhli:BAAALAAECgcICwAAAA==.Kuromi:BAAALAAECggIEgAAAA==.',Kv='Kvasenjoyer:BAABLAAECoEYAAIIAAgInR8aFwDcAgAIAAgInR8aFwDcAgAAAA==.',La='Laslie:BAAALAADCggIIAAAAA==.',Li='Liontauren:BAABLAAECoEbAAIVAAcIyRyPKwBTAgAVAAcIyRyPKwBTAgAAAA==.',Lu='Luzifer:BAABLAAECoEaAAIBAAcIwBNqHQDxAQABAAcIwBNqHQDxAQAAAA==.',Ma='Mackovsky:BAAALAAFFAIIAgAAAA==.Madskull:BAAALAAECgIIAgABLAAECgYICAAMAAAAAA==.Magalo:BAAALAADCgYIEwAAAA==.Magiciana:BAAALAAECgYICwAAAA==.Mai:BAABLAAECoEbAAIWAAcIHx91HwB/AgAWAAcIHx91HwB/AgABLAAECggIEgAMAAAAAA==.Mandem:BAABLAAECoEjAAMHAAgI3B8DGgDBAgAHAAgI3B8DGgDBAgACAAYIKxbQUgBMAQAAAA==.Marlah:BAABLAAECoEfAAIXAAgIxRoLEABQAgAXAAgIxRoLEABQAgAAAA==.Mathaysan:BAAALAAECgYIBgAAAA==.Mauekos:BAAALAADCgQIBAAAAA==.',Me='Melkon:BAAALAADCgMIAwAAAA==.Meridox:BAAALAADCggIEAAAAA==.',Mi='Missaffix:BAAALAAECgMIAwAAAA==.Missklick:BAABLAAECoEkAAIIAAgIDgaBfwA/AQAIAAgIDgaBfwA/AQAAAA==.',Mo='Mockie:BAAALAADCggIDAAAAA==.Moszatprince:BAAALAADCggIDAAAAA==.',My='Myologia:BAAALAADCgIIAgAAAA==.',Ne='Necray:BAAALAADCgQIBAABLAAECggIJAAYAAEWAA==.Nemvokmagus:BAAALAADCgcIDAAAAA==.Nevermr:BAAALAADCgEIAQAAAA==.Nexo:BAAALAAECggIDAAAAA==.',Ni='Nickfurry:BAAALAAECgIIAgABLAAECggIIAAFALAQAA==.Nicolasrage:BAAALAADCgYIBgABLAAECggIIAAFALAQAA==.',No='Nolena:BAAALAADCggIDQAAAA==.',Nu='Nutmegch:BAABLAAECoElAAISAAgIXx2MEgC3AgASAAgIXx2MEgC3AgAAAA==.Nutmegcha:BAAALAAECgQIBAAAAA==.',Or='Oren:BAAALAADCgcIBwAAAA==.',Pa='Palo:BAAALAAECgIIAgAAAA==.',Pe='Pew:BAAALAADCggICgAAAA==.',Pf='Pfobos:BAABLAAECoEeAAILAAgIHh8+DADXAgALAAgIHh8+DADXAgAAAA==.',Pi='Pimas:BAAALAAECgIIAgAAAA==.',Pr='Proex:BAABLAAECoEfAAIHAAgIkA5xbwCVAQAHAAgIkA5xbwCVAQAAAA==.',Qw='Qwyn:BAACLAAFFIEFAAISAAII/wjYJgCIAAASAAII/wjYJgCIAAAsAAQKgSIAAxMACAh9GN8IAPEBABMABghgHt8IAPEBABIACAgSDvE8ALoBAAAA.',Ra='Ramzi:BAABLAAECoEYAAIEAAgIJR+iJAC2AgAEAAgIJR+iJAC2AgABLAAECggIIwAHANwfAA==.',Ri='Rilva:BAABLAAECoEeAAIZAAgIigrFKQB8AQAZAAgIigrFKQB8AQAAAA==.',Ro='Rose:BAAALAAECgIIAgAAAA==.Rosszaság:BAAALAADCgcIBwAAAA==.',Ru='Rudasham:BAAALAAECgQIBAAAAA==.Ruläh:BAAALAADCgIIAgAAAA==.Russó:BAABLAAECoEUAAIEAAcIvxJ3ewC7AQAEAAcIvxJ3ewC7AQAAAA==.',Sa='Satyrica:BAAALAADCgYICgAAAA==.',Sc='Scarlettvond:BAAALAAECgUIBQAAAA==.',Sh='Shaku:BAABLAAECoEYAAMCAAcIShVCPACoAQACAAcI9RJCPACoAQAHAAcI7xMacgCPAQAAAA==.Shazhir:BAAALAAECgYIDAAAAA==.Shonka:BAAALAAECggIDQAAAA==.Shroomy:BAAALAAECgMIAwAAAA==.',Si='Sigismund:BAAALAAECgMIBQAAAA==.',Sk='Skafistadig:BAABLAAECoEfAAIaAAgIuhuFDABjAgAaAAgIuhuFDABjAgAAAA==.',Sl='Slask:BAACLAAFFIEGAAIPAAIIvRWcLgCbAAAPAAIIvRWcLgCbAAAsAAQKgRQAAg8ABgh7HFVgALwBAA8ABgh7HFVgALwBAAAA.',So='Sonir:BAAALAAECgYIBgAAAA==.Sorayana:BAAALAADCgQIBAAAAA==.',St='Strygwyr:BAAALAAECgYICgAAAA==.',Su='Sugarplum:BAABLAAECoEUAAIHAAgIEwrQfwBxAQAHAAgIEwrQfwBxAQAAAA==.',Sw='Switchmage:BAABLAAECoEWAAQPAAcICw1KcACOAQAPAAcIYgxKcACOAQAQAAEIlxWHeAA+AAARAAEImQeeHwAtAAAAAA==.',Sz='Szaszo:BAAALAADCgUIBQAAAA==.',['Sá']='Sámibácsi:BAAALAADCgIIAgAAAA==.',['Sé']='Sénu:BAAALAAECgMIAwAAAA==.',Ta='Taeyeon:BAAALAAECgQIBQABLAAECgcIFwALAH4cAA==.Tandolorien:BAAALAAECgIIAgAAAA==.Tankendk:BAAALAADCgcIBwAAAA==.',Tr='Tru:BAAALAAECggIEgABLAAFFAMIBwAbACYTAA==.',Ty='Tyrauhell:BAAALAAECggICAAAAA==.',Vo='Volaira:BAAALAAECgYIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end