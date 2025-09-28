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
 local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Guardian','Druid-Feral','Druid-Balance','Unknown-Unknown','Evoker-Devastation','Paladin-Retribution','DemonHunter-Havoc','DeathKnight-Frost','DeathKnight-Blood','Monk-Mistweaver','Monk-Windwalker','Warrior-Protection','Mage-Frost','Mage-Arcane','Priest-Shadow','Hunter-Survival','Rogue-Outlaw','Rogue-Assassination','Rogue-Subtlety','Shaman-Restoration','DemonHunter-Vengeance','Priest-Holy',}; local provider = {region='EU',realm='Executus',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aamon:BAAALAADCggICAAAAA==.',Ad='Adstatera:BAAALAAECgYIBgAAAA==.',Af='Affelock:BAACLAAFFIEQAAQBAAUI0hH8BgC6AAACAAQIpA1kDwBSAQABAAII9R/8BgC6AAADAAEIRgozBQBSAAAsAAQKgRcABAEABwimI94jAMkBAAEABQiOI94jAMkBAAIAAgjkI5+iAM0AAAMAAgjRFScmAJgAAAAA.Afferogue:BAAALAAECgYIEAAAAA==.',An='Anazul:BAAALAADCgYIBgAAAA==.Antadin:BAAALAADCgIIAgAAAA==.',As='Ashdrinker:BAAALAADCgUIBQAAAA==.',At='Athanatos:BAAALAADCgcICwAAAA==.',Ba='Bababloom:BAABLAAECoEXAAIEAAYINRhfTQBrAQAEAAYINRhfTQBrAQAAAA==.Babasneak:BAAALAADCgUIBQAAAA==.',Be='Bedemanden:BAAALAADCgMIAwAAAA==.',Bi='Bigboyvinnie:BAAALAAECgIIAgAAAA==.Bigorange:BAAALAAECgcICgAAAA==.Bingoxx:BAABLAAECoEYAAIFAAYILiRrIwCEAgAFAAYILiRrIwCEAgAAAA==.',Bl='Bladix:BAABLAAECoEnAAMGAAgIECWKBgBIAwAGAAgIBSWKBgBIAwAHAAcIzhEETABmAQAAAA==.Bloodwidow:BAABLAAECoEaAAIFAAcImhiIOgAOAgAFAAcImhiIOgAOAgAAAA==.',Bo='Bolerino:BAAALAAECgcIEwAAAA==.Bombaren:BAAALAAECgQIBQABLAAECgYIFQAIAIEZAA==.',Br='Briskart:BAAALAADCgMIAwAAAA==.',Bu='Buttinger:BAAALAAECggICAAAAA==.',By='Bygglov:BAAALAADCgYIBgAAAA==.',['Bú']='Búbhoshum:BAABLAAECoEWAAIGAAYIgxWyfQB1AQAGAAYIgxWyfQB1AQAAAA==.',Ca='Callmemetro:BAAALAADCgQIBAAAAA==.Cantah:BAAALAADCgMIAwAAAA==.Cat:BAACLAAFFIEGAAIJAAMINBu8AwAMAQAJAAMINBu8AwAMAQAsAAQKgRwAAwkACAiIIc4FAOgCAAkACAiIIc4FAOgCAAoABAgdF+VQADABAAAA.',Ch='Chicken:BAAALAADCgYICAAAAA==.Chrissbank:BAAALAAECggICAAAAA==.',Co='Coppertusk:BAAALAAECgYICQAAAA==.Cowcain:BAAALAAECgYIBQAAAA==.',Da='Dargon:BAAALAADCggICAABLAAECgcIDwALAAAAAA==.Darktorn:BAAALAADCggIDgAAAA==.',De='Denare:BAAALAAECgYIDwAAAA==.',Do='Donbul:BAAALAAECgUIBQABLAAECgYIFQAIAIEZAA==.Dopaz:BAAALAADCgYIBgAAAA==.',Dr='Draktuttar:BAABLAAECoENAAIMAAcInxDELACUAQAMAAcInxDELACUAQABLAAECggIJAANAPAjAA==.',Du='Dugaeruu:BAAALAAECgYICQAAAA==.',Eb='Ebinsur:BAAALAADCgUIBQAAAA==.',Ek='Eklig:BAAALAAECggICQAAAA==.',El='Elenarose:BAAALAAECgEIAQAAAA==.Elphida:BAAALAADCggIDgAAAA==.',Ep='Ephemeral:BAACLAAFFIEHAAIOAAIIBRrwHgCnAAAOAAIIBRrwHgCnAAAsAAQKgSEAAg4ACAiVHFAkAKcCAA4ACAiVHFAkAKcCAAAA.',Es='Essdk:BAABLAAECoEmAAMPAAgIryL5EAAaAwAPAAgIryL5EAAaAwAQAAcIIhm7EgDiAQAAAA==.Esset:BAABLAAECoEaAAMCAAgIFBzISwDVAQACAAcIuRrISwDVAQABAAEIjyVDcgBuAAAAAA==.',Ev='Evodgalang:BAAALAADCgUIBQAAAA==.',Ex='Executi:BAAALAADCgYIBgAAAA==.',Fa='Fatin:BAAALAAECgYIDQAAAA==.',Fi='Filthboi:BAABLAAECoEhAAIRAAgIPCFaBQD3AgARAAgIPCFaBQD3AgAAAA==.',Fr='Fruststrand:BAABLAAECoEVAAIOAAcI6yK3KQCNAgAOAAcI6yK3KQCNAgAAAA==.',Fu='Fudjih:BAAALAADCggICAABLAAECggIDgALAAAAAA==.Fukboivinnie:BAAALAADCgYIBgAAAA==.Furrylover:BAAALAADCggICgAAAA==.',Go='Goatbirdman:BAAALAAECgYIDAAAAA==.Goatcheese:BAAALAADCgQIBQAAAA==.Gornákk:BAABLAAECoEYAAIPAAgI1SDqIwC7AgAPAAgI1SDqIwC7AgAAAA==.Goroth:BAAALAAECgcIDwAAAA==.',Ho='Holyshet:BAAALAADCgIIAgAAAA==.',Hu='Hugurt:BAAALAADCgYIBgAAAA==.Hullabaloo:BAAALAAECgYIDgAAAA==.Hurtigast:BAABLAAECoEkAAISAAgIUSEABwAJAwASAAgIUSEABwAJAwAAAA==.',['Hå']='Hård:BAAALAAECgYIBwAAAA==.',['Hö']='Högrklickarn:BAAALAAECgYIDQAAAA==.',['Hù']='Hùlken:BAAALAAECgYIDgAAAA==.',Ic='Icyflame:BAAALAADCgEIAQAAAA==.',Ir='Ironwarrior:BAAALAAECgYICgAAAA==.',Ix='Ixusmash:BAACLAAFFIEXAAITAAYIlR8kAQBJAgATAAYIlR8kAQBJAgAsAAQKgRkAAhMACAiqJFYFACkDABMACAiqJFYFACkDAAAA.',Jo='Johnnyhoho:BAAALAAECgMIAwAAAA==.Jolocky:BAAALAADCggICAAAAA==.',Ju='Justasmolguy:BAABLAAECoEWAAIPAAgIdB6ZJQCzAgAPAAgIdB6ZJQCzAgAAAA==.',Ka='Kalmordun:BAAALAADCggICAAAAA==.',Ki='Kill:BAAALAAECgYIDQAAAA==.Killerelite:BAAALAAECgYICAAAAA==.Kirby:BAAALAAECgYIBwAAAA==.',Ko='Kong:BAAALAAECgcIDQAAAA==.',Le='Lemonardo:BAAALAAECgIIBwAAAA==.',Li='Lilleloksy:BAAALAADCggIBwAAAA==.',Lu='Lukl:BAAALAADCgMIAwAAAA==.',Ly='Lylith:BAAALAADCgQIBQAAAA==.',Ma='Malcom:BAAALAAFFAIIAwAAAA==.Mallyx:BAAALAAECgYICQAAAA==.Manrok:BAACLAAFFIEHAAICAAMIcCGeEQApAQACAAMIcCGeEQApAQAsAAQKgSUAAgIACAivIyIJAD4DAAIACAivIyIJAD4DAAAA.',Me='Meinbrew:BAAALAADCgYIBgABLAAFFAMIBQAHANUFAA==.Meinrad:BAABLAAECoEcAAINAAgIcBp8OQBgAgANAAgIcBp8OQBgAgABLAAFFAMIBQAHANUFAA==.',Mg='Mgx:BAABLAAECoEcAAINAAgI6h/qHQDYAgANAAgI6h/qHQDYAgAAAA==.',Mi='Mili:BAAALAAECgYIDwAAAA==.Miromaavlis:BAAALAAECgIIAwAAAA==.',Mo='Monka:BAAALAADCggIDwABLAAECgcICgALAAAAAA==.Moossacre:BAAALAAECgYIDAAAAA==.',Mu='Munkeydunkey:BAAALAAECgYIEgAAAA==.Murktres:BAAALAAFFAIIBAAAAA==.',Na='Naliora:BAABLAAECoEhAAIGAAgIlg/vXwC6AQAGAAgIlg/vXwC6AQAAAA==.Nascentri:BAABLAAECoEWAAINAAgI5xLSYADzAQANAAgI5xLSYADzAQAAAA==.',Ne='Nearly:BAABLAAECoEeAAIGAAgIXx+LJQCAAgAGAAgIXx+LJQCAAgABLAAECggIFgAPAHQeAA==.Nemesiss:BAAALAAECgcIDwAAAA==.Nepenthe:BAABLAAECoEVAAQIAAYIgRmmFABBAQAJAAYIFRUkHwBsAQAIAAYI9xCmFABBAQAEAAYIWQ1VagAMAQAAAA==.',Od='Odran:BAABLAAECoEYAAMUAAgITBToHQABAgAUAAgITBToHQABAgAVAAMI0AJF1ABBAAAAAA==.',Oo='Oopsmbheals:BAABLAAECoEdAAIEAAgIvxoqKAARAgAEAAgIvxoqKAARAgABLAAFFAIICgAWAHYXAA==.Oopsnoheals:BAACLAAFFIEKAAIWAAIIdhc2EwCfAAAWAAIIdhc2EwCfAAAsAAQKgS0AAhYACAjLIMkLAAUDABYACAjLIMkLAAUDAAAA.',Or='Orlaine:BAAALAAECggIDQAAAA==.',Pa='Palla:BAABLAAECoEkAAINAAgI8CPPDwAmAwANAAgI8CPPDwAmAwAAAA==.',Pi='Pingu:BAAALAAECgQIBQABLAAECggIDgALAAAAAA==.Pix:BAAALAADCgcICAABLAAECggIHwAXAJMjAA==.',Pl='Plumplera:BAAALAAECgYIDQAAAA==.',Po='Porchetta:BAAALAAECgcICgAAAA==.',Pr='Proximus:BAABLAAECoEQAAIPAAYI2hI+tABfAQAPAAYI2hI+tABfAQAAAA==.',Pu='Purplebeard:BAABLAAECoEbAAIYAAYIpRj5CADTAQAYAAYIpRj5CADTAQAAAA==.',Ri='Rihannafenty:BAAALAAECggICAAAAA==.',Ro='Rosié:BAAALAAECggIEwABLAAECggIJAANAPAjAA==.',['Rä']='Rättsåhård:BAAALAAFFAIIAgAAAA==.',Sa='Sadler:BAABLAAECoEhAAMZAAgI7BRkGQA1AgAZAAgI7BRkGQA1AgAaAAIItgmpOwBfAAAAAA==.Salvanos:BAAALAAECgQIBwABLAAECgYIFQAIAIEZAA==.',Se='Selektiv:BAAALAAECgEIAgABLAAECggIDgALAAAAAA==.Selektivt:BAAALAAECggIDgAAAA==.',Sh='Shamanus:BAAALAAECggIDQABLAAECggIJAANAPAjAA==.Shamlife:BAAALAAECgIIAgAAAA==.Sheldra:BAABLAAECoEUAAIbAAcIhhRqVgCrAQAbAAcIhhRqVgCrAQAAAA==.Shimarin:BAAALAAECgUIBwABLAAECggIFgAPAHQeAA==.Shinamashiro:BAABLAAECoEfAAIXAAgIkyNYAQArAwAXAAgIkyNYAQArAwAAAA==.Shomy:BAAALAADCggIFQAAAA==.Shutterlore:BAAALAAECggIDgAAAA==.Shylvana:BAABLAAECoEfAAIHAAcILw7pTgBaAQAHAAcILw7pTgBaAQAAAA==.',Si='Sickjackenn:BAAALAADCgYICAAAAA==.Simonézzo:BAABLAAECoEcAAMcAAcINhzeEAAkAgAcAAcINhzeEAAkAgAOAAYIvBJoigB6AQAAAA==.',Sk='Skyføll:BAAALAAFFAEIAQABLAAFFAIIBwAOAAUaAA==.',Sm='Smaderklask:BAAALAAECgIIAgAAAA==.',Sn='Sneakyminaj:BAAALAAFFAQIBAAAAA==.Snowstorm:BAAALAADCggIAwAAAA==.Snuskyluff:BAAALAAECgIIAQAAAA==.',So='Soprano:BAAALAAECggIBgAAAA==.',Sp='Speedygeézuz:BAAALAADCgYIBgAAAA==.',St='Stalecake:BAAALAAECgUICgABLAAECgYIDAALAAAAAA==.Stazi:BAAALAAECggIEwAAAA==.Stealthfenty:BAAALAAECggICAAAAA==.Stevenr:BAAALAADCgcIBwAAAA==.',Te='Tedariel:BAAALAAECgcICwABLAAECggIFgAPAHQeAA==.Teq:BAABLAAECoEeAAIWAAgIABSUJwAaAgAWAAgIABSUJwAaAgAAAA==.',Tj='Tjocksa:BAAALAAECgYIBgAAAA==.',To='Tomcioszaman:BAAALAAECgEIAQAAAA==.',Tr='Trickster:BAACLAAFFIEOAAIGAAQIoyUEBgCnAQAGAAQIoyUEBgCnAQAsAAQKgSkAAgYACAiwJtoCAGwDAAYACAiwJtoCAGwDAAAA.',Tu='Tumevo:BAACLAAFFIEHAAIMAAMItAsCDQDPAAAMAAMItAsCDQDPAAAsAAQKgSwAAgwACAhMHUkPAKgCAAwACAhMHUkPAKgCAAAA.',Tv='Tvättsvamp:BAAALAAECgMIAwAAAA==.',Ty='Tylôr:BAAALAAECgYICAABLAAFFAMIBQAHANUFAA==.',Va='Valoretta:BAABLAAECoEcAAIdAAgInQncVwBPAQAdAAgInQncVwBPAQAAAA==.',Vv='Vv:BAABLAAECoEUAAIWAAYI+B0hMADnAQAWAAYI+B0hMADnAQAAAA==.',['Vì']='Vìnníe:BAABLAAECoEZAAMSAAYI4RulIgCyAQASAAYI4RulIgCyAQARAAQIZxdOKwAJAQAAAA==.',Wa='Wallinpala:BAACLAAFFIETAAINAAYIFiPfAABZAgANAAYIFiPfAABZAgAsAAQKgSAAAg0ACAgZJlcEAHADAA0ACAgZJlcEAHADAAAA.Waluigi:BAAALAAECgUICQAAAA==.Warchef:BAAALAAECggICAAAAA==.',Wi='Wideass:BAAALAAFFAIIBAABLAAFFAIICgAWAHYXAA==.',Wo='Worstlock:BAAALAADCggIDwAAAA==.',['Xí']='Xímo:BAAALAADCggIIgAAAA==.',Zu='Zulsoka:BAAALAADCgYIBgABLAAECggIDgALAAAAAA==.',Zy='Zyra:BAAALAADCgcICAAAAA==.',['Îo']='Îona:BAACLAAFFIEFAAIHAAMI1QVKGwCIAAAHAAMI1QVKGwCIAAAsAAQKgRwAAgcACAhUHokXAI4CAAcACAhUHokXAI4CAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end