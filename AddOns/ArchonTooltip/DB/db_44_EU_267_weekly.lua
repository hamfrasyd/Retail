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
 local lookup = {'Monk-Brewmaster','Warrior-Protection','DeathKnight-Blood','Shaman-Elemental','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Monk-Windwalker','Paladin-Retribution','Hunter-Survival','Warlock-Demonology','Unknown-Unknown','Paladin-Holy','Priest-Holy','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Assassination','Druid-Restoration','Rogue-Subtlety','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','DemonHunter-Vengeance','Warrior-Fury','Druid-Guardian','Druid-Balance','Rogue-Outlaw','Shaman-Restoration','Monk-Mistweaver','Mage-Arcane','Mage-Frost','Priest-Discipline','Paladin-Protection','Druid-Feral','Mage-Fire',}; local provider = {region='EU',realm='BronzeDragonflight',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abluchi:BAACLAAFFIEVAAIBAAYIohyeAQAjAgABAAYIohyeAQAjAgAsAAQKgSQAAgEACAiZIZAGAOYCAAEACAiZIZAGAOYCAAAA.Ablueyes:BAAALAAECgcIBwABLAAFFAYIFQABAKIcAA==.Ablupew:BAAALAADCggICAABLAAFFAYIFQABAKIcAA==.Abusqa:BAABLAAECoEZAAICAAcIORPQKwChAQACAAcIORPQKwChAQAAAA==.',Ad='Adge:BAABLAAECoEgAAIDAAgICRObFQC8AQADAAgICRObFQC8AQAAAA==.',Ak='Akämï:BAAALAAECgUIBQAAAA==.',Al='Alcatrax:BAAALAADCgYIBgAAAA==.Aleantara:BAAALAAECgUIBQAAAA==.Aliceo:BAAALAAECgEIAQAAAA==.Allera:BAAALAADCggICAAAAA==.Alvar:BAABLAAECoEXAAIEAAgIdxWpMAAZAgAEAAgIdxWpMAAZAgAAAA==.Alyssandra:BAAALAAECgMIBgAAAA==.',Am='Amat:BAACLAAFFIEFAAIFAAMIbQtmFwCUAAAFAAMIbQtmFwCUAAAsAAQKgRsAAwUACAhOH6sdAFwCAAUACAhOH6sdAFwCAAYAAQhmDvYHATQAAAAA.Amiryth:BAABLAAECoEZAAMGAAcISBidTwDmAQAGAAcISBidTwDmAQAFAAMI6wlrjwB1AAAAAA==.Amun:BAABLAAECoEVAAIHAAYIbxizKQCpAQAHAAYIbxizKQCpAQAAAA==.Amythiste:BAAALAAECggIDgAAAA==.',An='Angelwings:BAAALAAECgYIDQAAAA==.Antarion:BAAALAADCggICAAAAA==.',Ar='Aracari:BAABLAAECoEZAAIIAAcImA3gKQB8AQAIAAcImA3gKQB8AQAAAA==.Aralan:BAABLAAFFIELAAIJAAUIuSBcAwDpAQAJAAUIuSBcAwDpAQAAAA==.Arczii:BAAALAADCgYIBgAAAA==.Aredin:BAAALAAECggIAgAAAA==.Argonis:BAAALAADCggICgAAAA==.Aroman:BAAALAAECgUIBwAAAA==.',As='Asaêl:BAAALAADCgYIBgAAAA==.Asimin:BAAALAAECggICQAAAA==.Astec:BAAALAAECgQIBAAAAA==.',At='Atonis:BAABLAAECoEZAAIJAAcIvg93hgCmAQAJAAcIvg93hgCmAQAAAA==.',Au='Auraablu:BAAALAAECgcICwABLAAFFAYIFQABAKIcAA==.Auralux:BAAALAAECgUIBQAAAA==.Aurelian:BAAALAADCgcIBgAAAA==.',Aw='Awzombie:BAAALAADCgEIAQAAAA==.',Az='Azarathal:BAABLAAECoEYAAIKAAcIugfkDwByAQAKAAcIugfkDwByAQAAAA==.Azríel:BAAALAADCgMIAwAAAA==.',Ba='Babspo:BAAALAAECgIIAgAAAA==.Babysham:BAAALAADCgIIAgAAAA==.Badbuffy:BAAALAAECgMIBAAAAA==.Bagerbyg:BAAALAADCgMIAwAAAA==.Balthazzar:BAABLAAECoEUAAILAAYIKRrzIwDJAQALAAYIKRrzIwDJAQAAAA==.Barachus:BAAALAADCggIIgABLAADCggIIwAMAAAAAA==.Barki:BAAALAAECggIDQABLAAFFAYIFAANANEfAA==.',Be='Beammeup:BAACLAAFFIEKAAIOAAMIAw5qEQDaAAAOAAMIAw5qEQDaAAAsAAQKgSwAAw4ACAhDGVwkADoCAA4ACAhDGVwkADoCAA8ABwjZFrQqAAYCAAAA.Belafon:BAAALAAECgIIAgAAAA==.Belfdin:BAAALAADCgYIBgAAAA==.Bellemeow:BAABLAAFFIETAAQQAAYIICQiAQCEAgAQAAYIICQiAQCEAgARAAIIDBlIDACkAAADAAIIihmgCQCPAAABLAAFFAgIFQAQAIgkAA==.Beni:BAAALAAECggIEAAAAA==.Beriothien:BAAALAADCgcIDAAAAA==.Bezoar:BAAALAADCgYIBgABLAADCggIIwAMAAAAAA==.',Bh='Bhambu:BAAALAAECgEIAQAAAA==.',Bi='Bietle:BAABLAAECoEUAAIEAAYItxeESgCnAQAEAAYItxeESgCnAQAAAA==.Biig:BAAALAAECgIIAgAAAA==.',Bl='Blackdeathz:BAAALAADCgQIBAABLAAECgcIGQAGAEgYAA==.Bladoula:BAAALAADCggIEAAAAA==.Blaen:BAAALAAECggIAgAAAA==.Blodgnome:BAAALAADCggIEAAAAA==.Blodrae:BAAALAADCggICQAAAA==.',Bo='Boldir:BAAALAAECgYIDgAAAA==.Boredome:BAABLAAECoEZAAIEAAgI2hCzQgDFAQAEAAgI2hCzQgDFAQAAAA==.Bowbelle:BAAALAAECgUICgAAAA==.',Br='Brambles:BAAALAADCgIIAgAAAA==.Brannburn:BAAALAAECgYICgABLAAFFAUIBQASAJoTAA==.',Bu='Bughnrakh:BAAALAAECgMICAAAAA==.Bumps:BAAALAAECgYICwAAAA==.Burningflame:BAAALAAECgEIAQAAAA==.',Ca='Caatjee:BAAALAAECgYIEAAAAA==.Caitin:BAAALAAECgUICAAAAA==.Calethbe:BAAALAADCgcIBwAAAA==.Calimut:BAAALAADCgYIBgAAAA==.Capradeus:BAAALAADCgcIBwAAAA==.Cartey:BAABLAAECoEVAAITAAYIvxURSgB3AQATAAYIvxURSgB3AQAAAA==.Catastrophic:BAAALAAECgUICQABLAAFFAMIBAAUALAOAA==.',Ch='Chantea:BAAALAAECggIBQAAAA==.Chaztastic:BAABLAAECoEVAAIGAAcILiLJHQCqAgAGAAcILiLJHQCqAgAAAA==.Chillidan:BAAALAAECgYIEQAAAA==.Chipnorris:BAAALAAECgYICgAAAA==.Chlamydiara:BAAALAAECgEIAQABLAAFFAUICwAJALkgAA==.Christiex:BAAALAADCgMIBgAAAA==.Chubbycheeks:BAAALAADCgQIBAAAAA==.',Ci='Cierpliwy:BAAALAAECggICQAAAA==.',Cr='Crazyzz:BAAALAADCgUICAAAAA==.Creeps:BAAALAADCgQIBAAAAA==.Crispee:BAABLAAECoEdAAQVAAcIyBA9FABZAQAVAAUINRI9FABZAQAWAAUIzwbcngDcAAALAAMI7wmYaACUAAAAAA==.Cryslin:BAAALAAECgEIAQAAAA==.',Cy='Cylea:BAABLAAECoEVAAILAAYI+R1HGAAWAgALAAYI+R1HGAAWAgAAAA==.Cylia:BAABLAAECoEVAAITAAYIgh1KLQD2AQATAAYIgh1KLQD2AQAAAA==.',Da='Daddymen:BAAALAADCggIEwAAAA==.Daemi:BAAALAAECgcIBwAAAA==.Danger:BAAALAAECggIDgABLAAFFAIIAgAMAAAAAA==.Daryana:BAAALAADCgMIAwAAAA==.',De='Deamonpas:BAAALAAECgYIDAAAAA==.Deathjump:BAACLAAFFIENAAIXAAMI3RGPEQD0AAAXAAMI3RGPEQD0AAAsAAQKgToAAxcACAhDIjIdAM0CABcACAicIDIdAM0CABgABghJIdgOAEACAAAA.Decapidave:BAABLAAECoEbAAMZAAcIkBx9LwBAAgAZAAcIkBx9LwBAAgACAAII4REWbABTAAAAAA==.Deeds:BAABLAAECoEWAAIJAAYI8yLoOQBfAgAJAAYI8yLoOQBfAgAAAA==.Dempotat:BAAALAADCggIEAAAAA==.Devil:BAAALAAECggICAAAAA==.',Di='Diamondmoon:BAAALAADCggIGwAAAA==.Dibly:BAABLAAECoEcAAIaAAcIdxmbCgD7AQAaAAcIdxmbCgD7AQAAAA==.Dishevelled:BAABLAAECoEZAAIGAAcIiQ0mgABwAQAGAAcIiQ0mgABwAQAAAA==.',Dj='Djokkoo:BAABLAAECoEWAAIXAAgIDyHoIAC5AgAXAAgIDyHoIAC5AgAAAA==.',Do='Dolfke:BAABLAAECoEdAAMJAAcIBhSMegC9AQAJAAcIBhSMegC9AQANAAUIYgOyVACTAAAAAA==.Doomcow:BAAALAAECgMIAwAAAA==.Doralei:BAAALAADCggICAAAAA==.Dorph:BAABLAAECoEVAAIPAAcIERWrMQDeAQAPAAcIERWrMQDeAQAAAA==.',Dr='Dremura:BAAALAADCgYIBgAAAA==.Druidpeppa:BAABLAAECoEWAAMbAAgI9hL5OACdAQAbAAcIbxH5OACdAQATAAQIMxDcgQDJAAABLAAFFAIIBQAEAGULAA==.',Du='Dullemarc:BAAALAAECgYIDQAAAA==.',Dw='Dwarfomage:BAAALAAECgUIBQABLAAFFAIIBQAEAGULAA==.',El='Elefier:BAAALAADCggIFQAAAA==.Elessar:BAAALAAECgUICgAAAA==.Eliel:BAAALAAECgUIBQAAAA==.Ellosena:BAAALAADCgcIBwAAAA==.Elrondill:BAAALAADCgUIBQAAAA==.',Em='Emberdin:BAAALAADCgIIAgAAAA==.',En='Enirep:BAABLAAECoEdAAIGAAcIxBAPbwCWAQAGAAcIxBAPbwCWAQAAAA==.',Er='Erendiel:BAABLAAECoEmAAIJAAgIxRpbLwCHAgAJAAgIxRpbLwCHAgAAAA==.',Es='Esplenda:BAAALAADCgcIDgAAAA==.',Ev='Evanía:BAAALAAECgMICAAAAA==.Eviane:BAAALAADCgYIBgAAAA==.Evíe:BAAALAADCggIFQAAAA==.',Fa='Faldirn:BAAALAAECgcIDwAAAA==.Fantur:BAABLAAECoEZAAICAAgIFyBkCgDZAgACAAgIFyBkCgDZAgAAAA==.Farida:BAAALAADCggICAAAAA==.Fauna:BAAALAADCggIFgAAAA==.',Fe='Felweave:BAAALAADCgcIBwAAAA==.Femz:BAAALAADCgEIAQAAAA==.',Fi='Fiber:BAAALAAECgYIBwAAAA==.Fivebyfive:BAAALAADCggIIwAAAA==.',Fj='Fjaari:BAAALAADCggICAABLAAECgcIHwAcANMhAA==.',Fl='Flaire:BAAALAADCgUIBQAAAA==.Flamingburn:BAAALAAECgYIEgAAAA==.',Fo='Foghorn:BAAALAADCgcICgAAAA==.Forestfloor:BAAALAAFFAIIBAAAAA==.Forward:BAAALAADCgcIDAAAAA==.',Fq='Fqx:BAAALAAECgYIDgAAAA==.',Fr='Freyla:BAAALAAECgIIAgAAAA==.',Fu='Fugur:BAAALAAECgEIAQAAAA==.Funli:BAAALAAECgYIEQAAAA==.',Ga='Galga:BAAALAADCgMIAwAAAA==.Gallian:BAAALAAECgIIAgAAAA==.',Ge='Geam:BAAALAAECgYIDwAAAA==.',Gh='Ghan:BAAALAADCggIFgAAAA==.Ghanadriel:BAAALAADCgEIAQAAAA==.Ghanisham:BAAALAADCgUIAgAAAA==.Gheenas:BAAALAAECgIIAgAAAA==.Ghosturtle:BAAALAAECgMIAwAAAA==.',Gi='Gilvar:BAAALAAECgMIAwAAAA==.Gingerrunner:BAAALAADCggIFgAAAA==.',Gl='Gliter:BAABLAAECoEZAAIaAAcIchY5DADWAQAaAAcIchY5DADWAQAAAA==.',Gn='Gnomia:BAAALAADCgYICAAAAA==.',Gr='Grimer:BAAALAAECgMICAAAAA==.',['Gá']='Gáea:BAAALAADCgYICAAAAA==.',Ha='Hallonbåt:BAABLAAECoEVAAIdAAYIIiDHMQAhAgAdAAYIIiDHMQAhAgAAAA==.Hated:BAABLAAFFIEGAAIXAAIIdRG3LgCSAAAXAAIIdRG3LgCSAAABLAAFFAMICQANADENAA==.Hatedholy:BAABLAAFFIEJAAINAAMIMQ1zCgDdAAANAAMIMQ1zCgDdAAAAAA==.Hazyfantazy:BAAALAAECgEIAQAAAA==.',He='Heavycumer:BAAALAADCgYICAAAAA==.',Hi='Hino:BAAALAAECgUIBQAAAA==.',Ho='Holgier:BAABLAAECoEfAAIcAAcI0yFAAwCvAgAcAAcI0yFAAwCvAgAAAA==.Holyshocks:BAAALAADCggIDQABLAAFFAIIBQAEAGULAA==.Hopka:BAAALAAECgcICgAAAA==.Horlicks:BAAALAADCgIIAgAAAA==.',Hu='Hunterette:BAAALAADCgQIBAAAAA==.',['Hä']='Härfjätter:BAABLAAECoEZAAIdAAcIdiIHFgClAgAdAAcIdiIHFgClAgAAAA==.',Ig='Igris:BAAALAADCgIIAgAAAA==.',Ik='Iki:BAABLAAECoEYAAIJAAcIdQ3ZjQCYAQAJAAcIdQ3ZjQCYAQAAAA==.',Il='Ildi:BAAALAADCggICAAAAA==.Illididdydan:BAAALAAECgUICwAAAA==.',Im='Imadh:BAAALAADCgcIEwAAAA==.',In='Insane:BAAALAADCggIEAAAAA==.',Is='Issyrath:BAAALAADCgcIBwAAAA==.',It='Itchyorcass:BAAALAAECggIBQAAAA==.',Ja='Jakora:BAAALAAECgEIAQAAAA==.Jancä:BAAALAAECgUIBQAAAA==.Jaryn:BAAALAADCggIDQAAAA==.Jayeboyz:BAACLAAFFIEEAAIUAAMIsA4aCQCxAAAUAAMIsA4aCQCxAAAsAAQKgRsABBQACAi1IkkGAMYCABQACAjkIUkGAMYCABIABwiLHocdABECABwAAQieEVYaADcAAAAA.Jaysmo:BAAALAADCgYIBgABLAAECgYIFwAGALIVAA==.',Je='Jerby:BAAALAADCgYICAAAAA==.',Ji='Jinxit:BAAALAADCgcIDQABLAAECgYIFwAeAGwWAA==.',Jo='Joddy:BAABLAAECoEXAAMGAAYIshXedgCFAQAGAAYIshXedgCFAQAFAAQIEArOgwCdAAAAAA==.Joj:BAAALAADCgIIAQAAAA==.',Jt='Jterrible:BAAALAAECgYIEgABLAAFFAYIBAAMAAAAAA==.Jtsoaring:BAAALAAECgYIBgABLAAFFAYIBAAMAAAAAA==.',Ju='Justtaki:BAAALAAECgIIAgAAAA==.',['Jì']='Jìnx:BAAALAAECgcIDQAAAA==.',Ka='Kach:BAAALAAECggICAAAAA==.Kalinx:BAAALAADCgUIBQAAAA==.Katiya:BAAALAAECgMIAwAAAA==.Kaz:BAAALAADCggICwABLAAFFAUICAAfAMYKAA==.Kazar:BAAALAADCgcIDgABLAAECgYIFQAHAG8YAA==.',Ke='Kernadronn:BAAALAAECgMICAAAAA==.',Kh='Khratos:BAAALAADCgIIAgAAAA==.',Ki='Kigomar:BAAALAAECgYICwAAAA==.Kinte:BAABLAAECoEmAAITAAgI5RtKGABwAgATAAgI5RtKGABwAgAAAA==.',Kl='Klark:BAAALAAECggICgAAAA==.',Ko='Kobato:BAABLAAECoEaAAMgAAcIyRlFHAAMAgAgAAcIyRlFHAAMAgAfAAEI6g821gA9AAAAAA==.Kohee:BAAALAAECgYIEgABLAAFFAYIFAANANEfAA==.Korwalc:BAAALAADCggIEAAAAA==.',Ky='Kyosi:BAAALAAECgIIAgAAAA==.',['Ké']='Kéina:BAAALAADCggICAAAAA==.',Li='Liane:BAAALAADCggIDgAAAA==.Lightrancid:BAAALAADCgQIBAAAAA==.Lionbreath:BAAALAADCgIIAgAAAA==.Lirin:BAABLAAECoEXAAIeAAcISAqaKAAgAQAeAAcISAqaKAAgAQAAAA==.Litgnigpalad:BAAALAADCgYIBgAAAA==.Littlex:BAAALAADCggICAABLAAFFAMIBwAdAA0LAA==.Liulu:BAABLAAECoEXAAIeAAYIbBZ/HQCLAQAeAAYIbBZ/HQCLAQAAAA==.Liónsoul:BAABLAAECoEVAAIEAAYIgxlvQgDGAQAEAAYIgxlvQgDGAQAAAA==.',Lo='Lobellia:BAABLAAECoEdAAIOAAcI+g7/SACIAQAOAAcI+g7/SACIAQAAAA==.Lonjohnshiva:BAABLAAECoEaAAIcAAgIcyMWAQA5AwAcAAgIcyMWAQA5AwAAAA==.Lopen:BAAALAADCgUIBQABLAAECgYIDgAMAAAAAA==.Loraneda:BAAALAADCggIEAAAAA==.',Lu='Lucyline:BAABLAAECoEWAAIWAAcIUwzKZgCBAQAWAAcIUwzKZgCBAQAAAA==.Lunacy:BAABLAAECoEZAAIhAAcIbCKQAgC7AgAhAAcIbCKQAgC7AgAAAA==.Lunamarije:BAAALAADCgMIAwAAAA==.Lune:BAABLAAECoEqAAMiAAgI9AqlKgBiAQAJAAgIFwlMlQCKAQAiAAgI9AqlKgBiAQAAAA==.Lupocetflu:BAAALAADCgcIDAAAAA==.Luzzy:BAAALAAECgEIAQABLAAECggIEAAMAAAAAA==.',['Lá']='Láyas:BAAALAADCgYIBgAAAA==.',Ma='Maalfurion:BAAALAAECgYICAAAAA==.Magixsammy:BAABLAAECoEeAAIbAAYI7wQuYgDfAAAbAAYI7wQuYgDfAAAAAA==.Mahzáel:BAABLAAECoEVAAMdAAcIPQyrhAAzAQAdAAcIPQyrhAAzAQAEAAIIQAWPngBOAAAAAA==.Malchezante:BAAALAADCggIDgABLAABCgEIAQAMAAAAAA==.Maleficia:BAABLAAECoEZAAIjAAcIJQUWKAAOAQAjAAcIJQUWKAAOAQAAAA==.Malinmystere:BAABLAAECoEdAAIfAAcIVRD4XQDDAQAfAAcIVRD4XQDDAQAAAA==.Malleus:BAAALAAECggICQAAAA==.Mandar:BAAALAADCgYIBgAAAA==.Mapuxyaha:BAAALAAECgUIBQAAAA==.Mattdæmon:BAAALAAECgYIBwAAAA==.',Me='Megapop:BAAALAAECgcIEQAAAA==.Meluniel:BAAALAAECgYICwAAAA==.Meowmix:BAAALAAECgcIEgAAAA==.Merwllyra:BAABLAAECoEZAAIkAAcIAwMcDwDcAAAkAAcIAwMcDwDcAAAAAA==.Mesara:BAAALAADCggICAABLAAECgcIHQATACkMAA==.',Mi='Miilkyway:BAABLAAECoEYAAIQAAYIbgV+5AAGAQAQAAYIbgV+5AAGAQAAAA==.Miliantide:BAABLAAFFIEHAAIEAAMINBIoEADpAAAEAAMINBIoEADpAAAAAA==.Missivismo:BAAALAADCgQIBAAAAA==.',Mj='Mjazo:BAAALAADCggICAAAAA==.',Mu='Murderyard:BAAALAAECgQIBQABLAAECggIMQAcAKcTAA==.',My='Mylord:BAAALAAECgYIEQAAAA==.Mythrande:BAAALAAECgYIDQABLAAECgYIDgAMAAAAAA==.',['Må']='Månne:BAAALAAECgEIAQAAAA==.',Na='Nazrael:BAAALAAECgcIDgAAAA==.',Ne='Necrotic:BAAALAADCgIIAgAAAA==.Necrozia:BAAALAADCgQIBAAAAA==.Nemesís:BAAALAAECgIIAwAAAA==.Nessana:BAAALAAECgMIAwAAAA==.Nexttime:BAAALAAECgUIBgAAAA==.Nexuiz:BAAALAADCgYICQAAAA==.',Ni='Nickolaj:BAAALAAECgYICgAAAA==.Nimuelsa:BAAALAAECgYIDQAAAA==.',No='Nooman:BAAALAADCgcIBwAAAA==.Norbez:BAAALAAECgYIDwAAAA==.Nordak:BAAALAAECggIEAAAAA==.',['Ná']='Nátshèp:BAABLAAECoEjAAMWAAgIVh4ZGwDCAgAWAAgIVh4ZGwDCAgALAAII1QlScwBqAAAAAA==.Nátshép:BAAALAAECggIEAABLAAECggIIwAWAFYeAA==.',Of='Ofte:BAAALAAECgUIBQABLAAECggIHQASAJMZAA==.',Om='Omachi:BAABLAAECoEqAAIEAAgIHA1dRgC3AQAEAAgIHA1dRgC3AQAAAA==.',Or='Orcshard:BAACLAAFFIEIAAIQAAII9RpnMACeAAAQAAII9RpnMACeAAAsAAQKgScAAxAACAhzIhUVAAMDABAACAhzIhUVAAMDAAMAAQgHCG4+AC0AAAAA.Organza:BAAALAADCgEIAgAAAA==.',Pa='Pallyndrome:BAAALAADCgQIBAAAAA==.Pammycakes:BAAALAAECggIDwAAAA==.Pandella:BAABLAAECoEXAAIOAAYIzQoVZwAcAQAOAAYIzQoVZwAcAQAAAA==.Paranoía:BAAALAADCgcIBwABLAADCgcIBwAMAAAAAA==.',Pe='Penkoburziq:BAAALAAECgYIEAAAAA==.',Ph='Phaora:BAAALAAECgUIBQAAAA==.Pheobs:BAABLAAECoEXAAIOAAYI5AyMYgAqAQAOAAYI5AyMYgAqAQAAAA==.Phobosx:BAAALAADCggIDgABLAAFFAMIBwAdAA0LAA==.',Pi='Pikola:BAAALAAECggICAAAAA==.Pinewar:BAAALAAECgMIAwAAAA==.Pirreson:BAAALAAECgMIBQABLAAECgUICAAMAAAAAA==.',Pl='Plaiqe:BAAALAADCgcIBwAAAA==.',Po='Pokmen:BAAALAADCggICAAAAA==.Poppie:BAAALAADCggIFAAAAA==.',Pr='Pro:BAAALAAECgUICwAAAA==.',Py='Pyrah:BAAALAAECgcIEgAAAA==.Pytscha:BAABLAAECoEdAAILAAcImh/UDgBsAgALAAcImh/UDgBsAgAAAA==.',Qu='Quanticos:BAABLAAECoEZAAITAAcIOCAIFQCIAgATAAcIOCAIFQCIAgAAAA==.Quorra:BAAALAADCgUIBQAAAA==.',Ra='Ramaniel:BAAALAADCgQIBAAAAA==.Rasmar:BAAALAADCgUIBQAAAA==.',Re='Renascent:BAABLAAECoEaAAIJAAcIrQUbyAArAQAJAAcIrQUbyAArAQAAAA==.',Ri='Rideit:BAAALAADCgYIBgABLAADCggIFgAMAAAAAA==.Riedis:BAAALAADCggIFQAAAA==.',Ro='Rockblast:BAAALAADCggICAAAAA==.Rothus:BAAALAADCgIIAgAAAA==.Rovadi:BAAALAADCgEIAgAAAA==.',['Rá']='Rázhar:BAAALAAECgYIEwAAAA==.',Sa='Sambloom:BAABLAAECoEWAAITAAgIOh3VEQCjAgATAAgIOh3VEQCjAgAAAA==.Samdeath:BAAALAADCgQIBAAAAA==.Samtide:BAAALAAECgMIAwAAAA==.Samwisé:BAAALAADCgIIAgAAAA==.Sashiko:BAABLAAECoEVAAIGAAYIQhIBigBcAQAGAAYIQhIBigBcAQAAAA==.Saslegrip:BAAALAAECgIIAgAAAA==.Saterskajsa:BAAALAAECgcIEwAAAA==.',Sc='Scalesworth:BAAALAAECgYICgAAAA==.Schattenherz:BAAALAADCgUIBgAAAA==.Schmaug:BAAALAADCgcIBwAAAA==.Scorphina:BAAALAAECgEIAQAAAA==.',Se='Sendai:BAAALAAECgIIAwAAAA==.Serenity:BAAALAAECgcICwAAAA==.',Sg='Sgtdirtface:BAACLAAFFIEFAAIEAAIIZQtsHwCQAAAEAAIIZQtsHwCQAAAsAAQKgSIAAwQACAhsGyUaAKcCAAQACAhsGyUaAKcCAB0ABAifEFa0ANAAAAAA.',Sh='Shaari:BAAALAAECgcIEAAAAA==.Shadowze:BAAALAADCgIIAgAAAA==.Shamanmone:BAAALAADCggICAABLAAECgEIAQAMAAAAAA==.Shamfox:BAAALAAECgIIAgAAAA==.Shamima:BAAALAADCggICAABLAAECggIKgAGAMokAA==.Shaojun:BAAALAAECggIBQAAAA==.Shaolight:BAAALAADCgcIDAAAAA==.Shaoxy:BAAALAADCggIAwAAAA==.Sharosha:BAAALAAECgQIBwAAAA==.Sheerin:BAABLAAECoEbAAMTAAcIwhg7LgDyAQATAAcIwhg7LgDyAQAbAAYIYRfROgCTAQAAAA==.Shiany:BAABLAAECoEUAAIeAAcI0AzwIwBLAQAeAAcI0AzwIwBLAQAAAA==.Shiftshappen:BAABLAAECoEYAAMPAAcIFgtvUABIAQAPAAYILwxvUABIAQAOAAYI9AhAagASAQAAAA==.Shãmmy:BAAALAADCggIDwAAAA==.',Si='Sián:BAAALAAECgMIBAAAAA==.',Sl='Sleepydragon:BAAALAADCgcIDAAAAA==.',Sn='Sny:BAABLAAECoEVAAISAAcIxAwCLwCbAQASAAcIxAwCLwCbAQAAAA==.Sníp:BAAALAAECgEIAQAAAA==.',So='Solsken:BAAALAADCgMIAwAAAA==.',Sq='Squiggle:BAAALAADCgEIAQAAAA==.',St='Starjar:BAAALAADCgUIBQAAAA==.Steve:BAABLAAECoEVAAIHAAYINxYTLQCSAQAHAAYINxYTLQCSAQAAAA==.Strangerzord:BAABLAAECoEWAAISAAcIVB4VFQBdAgASAAcIVB4VFQBdAgAAAA==.Stripe:BAAALAAECgQIBQAAAA==.Stryff:BAAALAADCgIIAgAAAA==.',Su='Sulla:BAAALAADCggIEQAAAA==.Sunnai:BAABLAAECoEbAAINAAcISx04EQBfAgANAAcISx04EQBfAgAAAA==.Suspérious:BAAALAADCgQIBAAAAA==.',Sv='Svetimir:BAAALAADCggIDwAAAA==.',Sw='Sweett:BAAALAADCgcIBwAAAA==.',Sy='Syeriah:BAABLAAECoEWAAMfAAcIFwN4rQDKAAAfAAYI/gJ4rQDKAAAgAAEIqwM4hAAfAAAAAA==.Sylsa:BAAALAAECgMICAAAAA==.',['Sê']='Sêcare:BAAALAADCgcICwAAAA==.',['Sí']='Síx:BAAALAADCggICAABLAAECgEIAQAMAAAAAA==.',Ta='Taitus:BAAALAADCgcIDQAAAA==.Taldron:BAAALAAECgQIBAAAAA==.Tankdroid:BAAALAADCgQIBAAAAA==.Tarabi:BAABLAAECoEdAAMTAAcIKQz0WABCAQATAAcIKQz0WABCAQAbAAMIDRUHaQC5AAAAAA==.Targas:BAAALAAECgIIAgAAAA==.Tariel:BAAALAADCgIIAgAAAA==.Tashenka:BAAALAADCgcICwAAAA==.',Te='Teioh:BAAALAAECgUIBgABLAAFFAMIBQAFAG0LAA==.',Th='Thechiefhulk:BAABLAAECoEVAAICAAYItBKNOABXAQACAAYItBKNOABXAQAAAA==.Thenegative:BAAALAAECgUICAAAAA==.Thesalia:BAABLAAECoEVAAMWAAcIZBn+YwCJAQAWAAYIchP+YwCJAQALAAQIIhz1RwAmAQAAAA==.Thrallina:BAAALAADCgcIEAAAAA==.',To='Toburr:BAAALAADCggICAAAAA==.Topless:BAAALAADCgIIAgAAAA==.Tornsoul:BAAALAADCggIFwAAAA==.Toyo:BAAALAAECgUIBwABLAAECggIFwAEAHcVAA==.',Tr='Triphuntard:BAAALAAECgMIAwAAAA==.Tristan:BAAALAADCggICAABLAAECgQIBQAMAAAAAA==.Tryxatika:BAAALAAECgQICAABLAAECgcIDgAMAAAAAA==.Tryxodia:BAAALAAECgcIDgAAAA==.Tryxodiaa:BAAALAADCgYIBgABLAAECgcIDgAMAAAAAA==.',Tw='Twixter:BAAALAADCggICAAAAA==.',['Tí']='Tícks:BAAALAADCgYIDAAAAA==.',Ud='Uddir:BAAALAADCgcIBwAAAA==.',Un='Unholyselena:BAAALAADCgYIDgAAAA==.',Ur='Urieth:BAABLAAECoEXAAITAAYIdhEvVQBOAQATAAYIdhEvVQBOAQAAAA==.',Va='Vaesandryn:BAAALAAECgMICAAAAA==.Valianá:BAAALAADCgMIAwAAAA==.Valthrenys:BAAALAADCggICwAAAA==.Vapouris:BAAALAADCggICAAAAA==.Vasiliki:BAABLAAECoEfAAIGAAgIFxJdUQDhAQAGAAgIFxJdUQDhAQAAAA==.',Ve='Vebreihaedra:BAAALAAECgYIBgAAAA==.Vedina:BAABLAAECoEcAAIPAAgItAptOwCqAQAPAAgItAptOwCqAQAAAA==.Vell:BAAALAADCgcIBwAAAA==.Vendir:BAAALAAECgYIEQABLAAECggIHQASAJMZAA==.Vesnir:BAAALAAECgYIEAAAAA==.',Vi='Virkon:BAAALAAECgIIAgABLAAECggIEAAMAAAAAA==.Vito:BAAALAAECgUIBQAAAA==.',Vl='Vlaeye:BAAALAAECgMIBAAAAA==.',Vo='Voidlocked:BAAALAAECgYIEgAAAA==.',Wa='Wakio:BAAALAAECgIIAgAAAA==.Warmachienn:BAABLAAECoEZAAIGAAcIOCJmHwChAgAGAAcIOCJmHwChAgAAAA==.',Wi='Wizbitt:BAAALAADCgYIBgABLAADCggIFgAMAAAAAA==.',Wy='Wyrm:BAAALAADCgYIBgAAAA==.',Xb='Xberg:BAAALAAECgMIAwABLAAFFAMIBwAdAA0LAA==.',Xe='Xerxes:BAAALAADCgEIAQAAAA==.',Ya='Yamasito:BAAALAADCgQIAQAAAA==.Yamii:BAAALAADCgMIBQAAAA==.Yasmiin:BAAALAADCggIEAAAAA==.Yayxx:BAAALAAECgQIBAAAAA==.',Ym='Yma:BAAALAADCgQIBAAAAA==.',Yo='Yolandha:BAAALAAECgcIEwAAAA==.',Za='Zacký:BAAALAAECgUIBQABLAAFFAYIFAANANEfAA==.Zaigo:BAAALAADCgcIDQAAAA==.Zanean:BAAALAAECgEIAQAAAA==.Zanzillt:BAAALAAECggIAgAAAQ==.',Zd='Zdzich:BAAALAAECgYIEAAAAA==.',Ze='Zeerix:BAAALAADCggICAAAAA==.Zes:BAAALAADCgEIAQAAAA==.',Zh='Zharviin:BAAALAAECgYIBwAAAA==.Zhing:BAAALAAECgMICAAAAA==.',Zn='Znailmonkey:BAAALAADCggICAABLAAECgcIHwAcANMhAA==.',Zo='Zophÿ:BAABLAAECoEdAAMNAAcI/BLhJgCtAQANAAcI/BLhJgCtAQAJAAEI7AYwNgE1AAAAAA==.Zorine:BAAALAADCgUIBQAAAA==.',['Ár']='Árágorn:BAAALAAECgQIBAAAAA==.',['Ðy']='Ðyahx:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end