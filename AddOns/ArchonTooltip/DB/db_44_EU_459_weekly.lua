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
 local lookup = {'Mage-Frost','Priest-Holy','Hunter-BeastMastery','Warrior-Fury','Unknown-Unknown','Shaman-Elemental','Druid-Balance','Druid-Guardian','Warrior-Arms','Shaman-Restoration','Paladin-Retribution','Warlock-Affliction','Warlock-Destruction','Monk-Windwalker','Warrior-Protection','Warlock-Demonology','Mage-Arcane','DemonHunter-Vengeance','Druid-Restoration','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Paladin-Holy','Evoker-Preservation','Evoker-Devastation','Hunter-Marksmanship','Priest-Discipline','Shaman-Enhancement','Monk-Mistweaver','Monk-Brewmaster','Priest-Shadow','DeathKnight-Frost','DeathKnight-Unholy','Rogue-Outlaw','Hunter-Survival','Paladin-Protection','DeathKnight-Blood',}; local provider = {region='EU',realm='Perenolde',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abgelaufen:BAABLAAECoEZAAIBAAYItRUaNgB1AQABAAYItRUaNgB1AQAAAA==.Abstrakt:BAABLAAECoEVAAIBAAYIwxekLACoAQABAAYIwxekLACoAQAAAA==.',Ac='Acdc:BAAALAAECgYIDwAAAA==.Aceio:BAAALAAECggICAAAAA==.',Ae='Aelin:BAAALAAECgYICAABLAAFFAYIDQACAAoIAA==.',Ag='Aggroluna:BAAALAADCgUIBQAAAA==.',Al='Aldieb:BAABLAAECoEYAAIDAAcI5gsJkQBcAQADAAcI5gsJkQBcAQAAAA==.Alextrasa:BAAALAAECgMIAwAAAA==.Allegretta:BAAALAAECgcIEQAAAA==.Alpaniad:BAAALAAECggICgAAAA==.Alpha:BAAALAAECgYIDQAAAA==.',Am='Amicalunae:BAAALAADCgIIAgAAAA==.Amügdala:BAAALAADCgIIAgAAAA==.',An='Andoriá:BAAALAADCgEIAQAAAA==.Angelhawk:BAAALAAECgIIBAAAAA==.Ankelar:BAAALAAECgYICwAAAA==.Anklimus:BAAALAADCgcIBwAAAA==.Antarus:BAABLAAECoEUAAICAAYIsAw4ZAAqAQACAAYIsAw4ZAAqAQAAAA==.Anthuria:BAAALAAECgIIAgAAAA==.',Ao='Aonas:BAABLAAECoEbAAIEAAgIfxSlPAARAgAEAAgIfxSlPAARAgAAAA==.',Ar='Araflo:BAAALAAECgMIAwAAAA==.Aranjo:BAAALAAECgYIEgAAAA==.Arceus:BAAALAAECgYIBwABLAAECgcIIgAEAKYZAA==.Arilia:BAAALAADCgcICAAAAA==.Arnulf:BAAALAAECgUIDgAAAA==.Aroxi:BAAALAAECgMIAwABLAAECgYIDAAFAAAAAA==.Aroxs:BAAALAAECgQICQAAAA==.Arthalis:BAAALAADCggIDwAAAA==.Arýa:BAABLAAECoEVAAIBAAcIlBcIHwD+AQABAAcIlBcIHwD+AQABLAAFFAIIBgAGAMwYAA==.',As='Asgerd:BAAALAADCgQIBAAAAA==.Ashlay:BAAALAADCggIJgAAAA==.Ashleyy:BAAALAAECgYICQAAAA==.Asmodân:BAABLAAECoEkAAMHAAgIRw72OgCcAQAHAAgI7gz2OgCcAQAIAAUI0ApPHwDKAAAAAA==.Asteron:BAAALAAECgYIDQAAAA==.Astoriá:BAAALAAECgUIBgAAAA==.',Au='Autohitwarri:BAAALAAECgYIDwAAAA==.',Ay='Ayalis:BAAALAAECgEIAQAAAA==.Ayebeambeast:BAAALAAECgIIAgABLAAECgUICAAFAAAAAA==.',Az='Azenth:BAAALAAECgUICAAAAA==.Azhu:BAACLAAFFIEFAAIJAAIIzhzpAQC7AAAJAAIIzhzpAQC7AAAsAAQKgSMAAgkACAj1JWMAAH0DAAkACAj1JWMAAH0DAAAA.',Ba='Balgaroth:BAAALAAECgYIDAAAAA==.Baragoûr:BAAALAAECgYICwABLAAFFAMIBQAKAG4KAA==.Baromyr:BAAALAAECgEIAgAAAA==.Basilone:BAAALAAECgQIBAAAAA==.Bathasar:BAABLAAECoEZAAILAAgIpg3weQDFAQALAAgIpg3weQDFAQAAAA==.Baumäffchen:BAABLAAECoEYAAIDAAcILAtNmQBMAQADAAcILAtNmQBMAQAAAA==.',Be='Beak:BAABLAAECoEYAAIMAAgIIh2mAwC3AgAMAAgIIh2mAwC3AgAAAA==.Beefbolts:BAABLAAECoEbAAINAAYI1BdXXACoAQANAAYI1BdXXACoAQAAAA==.Beerbelly:BAAALAAECgIIAgAAAA==.Beleron:BAAALAAECgYIDwAAAA==.Bellinah:BAAALAADCggIKAAAAA==.',Bi='Biby:BAABLAAECoEdAAMNAAcIGRl6SwDfAQANAAcIJRh6SwDfAQAMAAYI7A1fGAAlAQABLAAFFAIIBgAOABYaAA==.Bigschuz:BAABLAAECoEbAAIDAAgINh6BMgBSAgADAAgINh6BMgBSAgAAAA==.',Bl='Blackcovied:BAAALAADCggICwAAAA==.Blackhorn:BAAALAAECgYIDgAAAA==.Blackmask:BAAALAADCggIDwAAAA==.Blindfolded:BAABLAAECoElAAIPAAcIThv8IwDgAQAPAAcIThv8IwDgAQAAAA==.Bloodpath:BAAALAADCgUIBQABLAAECgYIDgAFAAAAAA==.Bludeis:BAAALAADCggICAAAAA==.Blueschami:BAAALAAECgIIAgAAAA==.Blànká:BAAALAADCggICAAAAA==.',Bo='Bobbyroxx:BAAALAAECgIIAgABLAAECgYIBgAFAAAAAA==.Bobô:BAAALAAECgEIAQAAAA==.Bodeus:BAAALAADCgUIBQAAAA==.Bollek:BAAALAAECgMIAwAAAA==.Bonecrusher:BAAALAADCgEIAQAAAA==.Borbarad:BAABLAAECoEYAAIQAAcICBsZGQATAgAQAAcICBsZGQATAgAAAA==.Borgramm:BAAALAADCggICAAAAA==.Bovex:BAAALAADCgYIBgABLAAECgEIAQAFAAAAAA==.',Br='Brassas:BAAALAAECggICAAAAA==.Braum:BAAALAAECgIIAgABLAAFFAIIBgAOABYaAA==.Bravier:BAAALAADCgcIBwAAAA==.Britneyfearz:BAABLAAECoEWAAINAAgIeh4KGwDJAgANAAgIeh4KGwDJAgABLAAFFAUICwAHADAWAA==.',Bu='Bubblegummi:BAAALAADCgcIBwABLAAECgQIBAAFAAAAAA==.Buddelbernd:BAAALAADCggIEAAAAA==.Budrick:BAAALAAECgMIAwAAAA==.Bullfîre:BAABLAAECoEZAAIRAAgI8BU4UAD0AQARAAgI8BU4UAD0AQABLAAFFAEIAQAFAAAAAA==.Bullroot:BAAALAAFFAEIAQAAAQ==.',['Bä']='Bämy:BAAALAADCggICAAAAA==.Bärenstark:BAAALAADCggIGwAAAA==.',['Bè']='Bèyz:BAABLAAECoEmAAISAAgIDCMaBAAeAwASAAgIDCMaBAAeAwAAAA==.',['Bê']='Bêâ:BAAALAADCggICQAAAA==.',Ca='Cachou:BAAALAAECgYIDwAAAA==.Cadmasch:BAAALAAECggIDgAAAA==.Camouflage:BAAALAAECgYIBgABLAAECgYICQAFAAAAAA==.Caradhras:BAACLAAFFIEGAAIGAAIIzBgYGQCkAAAGAAIIzBgYGQCkAAAsAAQKgS0AAgYACAj7IRYMAB0DAAYACAj7IRYMAB0DAAAA.Carahunter:BAAALAAECgYIDAAAAA==.Caramîra:BAABLAAECoEUAAIPAAgI+RkGGQA4AgAPAAgI+RkGGQA4AgAAAA==.Castello:BAABLAAECoEdAAITAAcIPBYvNADdAQATAAcIPBYvNADdAQAAAA==.Catdog:BAAALAADCgcIDgAAAA==.',Ce='Celil:BAAALAAECgQIBwAAAA==.Celinda:BAAALAAECgYIDwAAAA==.Centorea:BAAALAADCgcICQAAAA==.Cerusela:BAAALAAECggIBgAAAA==.',Ch='Chargebiene:BAABLAAECoEeAAQJAAcIjA+yGgAgAQAJAAUIyRCyGgAgAQAPAAcIJAtdTQD+AAAEAAEIzQzLzQA9AAAAAA==.Cherríe:BAAALAADCggIEwAAAA==.Churki:BAACLAAFFIEJAAIUAAMIqCFsBwAaAQAUAAMIqCFsBwAaAQAsAAQKgSUAAxQACAipI2EFAB4DABQACAipI2EFAB4DABUAAQhnGe5AAEIAAAAA.Churkilol:BAAALAAECgUIBgABLAAFFAMICQAUAKghAA==.',Ci='Cic:BAAALAADCggIEAABLAAECgMIAwAFAAAAAA==.',Co='Cobrew:BAAALAADCggIGAAAAA==.Coibrew:BAAALAADCggIGAAAAA==.Conrep:BAABLAAECoEVAAIQAAcI4xDYJgC8AQAQAAcI4xDYJgC8AQAAAA==.Corann:BAABLAAECoElAAITAAgIChqkGwBgAgATAAgIChqkGwBgAgAAAA==.',Cr='Cribl:BAAALAAECgYIEwAAAA==.Crich:BAAALAAECggIBwAAAA==.Crital:BAAALAADCggICAABLAAECgUICAAFAAAAAA==.Critpala:BAAALAAECgUICAAAAA==.Cronii:BAAALAAFFAIIAgABLAAFFAQICQAKAJQZAA==.Cruiser:BAAALAADCggIEAAAAA==.',Cu='Cusack:BAAALAAECggIEAAAAA==.Cutterrina:BAAALAAECgcIBwAAAA==.',['Cí']='Círí:BAAALAAECgMIAwAAAA==.',Da='Dalarios:BAAALAADCgYIEQAAAA==.Darkknuffel:BAAALAADCggICgAAAA==.Darkyoda:BAAALAADCgMIAwAAAA==.Daywalkerdh:BAABLAAECoEgAAIWAAgItxCmYgDYAQAWAAgItxCmYgDYAQAAAA==.',De='Deceptico:BAAALAADCgUIBQAAAA==.Delareyna:BAABLAAECoEaAAIXAAcIvwTEQgATAQAXAAcIvwTEQgATAQAAAA==.Deluge:BAAALAAECgUIBQABLAAECgQIDwAFAAAAAA==.Demonslayer:BAAALAADCgIIAgABLAAFFAUIEAAUAMUQAA==.Denegar:BAABLAAECoEdAAMPAAgIfiAzCgDiAgAPAAgIfiAzCgDiAgAJAAUIXRuqEQCaAQAAAA==.Deneth:BAAALAAECggICAAAAA==.Deschein:BAAALAAECgQIBQAAAA==.Destard:BAAALAAECgIIBAAAAA==.',Di='Diamagiclein:BAAALAADCggIHgAAAA==.Diggah:BAAALAAECgEIAQAAAA==.',Do='Dondurin:BAAALAADCgYIBgAAAA==.',Dr='Drachenhauch:BAAALAAECggICAAAAA==.Dragaran:BAAALAADCggIEAAAAA==.Dragonia:BAABLAAECoEYAAIYAAgI5AICJwDnAAAYAAgI5AICJwDnAAAAAA==.Dragonmcm:BAAALAAECgIIAgAAAA==.Drakaries:BAABLAAECoEnAAMYAAgIcBSEDwAJAgAYAAgIcBSEDwAJAgAZAAcIhRnGHwAAAgAAAA==.Drakoth:BAAALAADCgYIBgAAAA==.Drâgønøs:BAAALAADCgYIBgAAAA==.',Du='Dugesia:BAAALAAECgcIEwAAAA==.Dummpfbacke:BAAALAADCggIEQAAAA==.Dunkeleins:BAAALAADCggICAAAAA==.',['Dø']='Døgne:BAABLAAECoEdAAILAAgIER43JgC0AgALAAgIER43JgC0AgAAAA==.Dønkeykøng:BAAALAAECgYIBgAAAA==.',Ea='Eagleuno:BAAALAAECggIDQAAAA==.Eatviol:BAAALAAECggIDwAAAA==.',Ee='Eelessa:BAABLAAECoEUAAIKAAcIWR3wUQC/AQAKAAcIWR3wUQC/AQAAAA==.',Ei='Eilleen:BAAALAAECgMIBQAAAA==.',El='Eladria:BAACLAAFFIEIAAIaAAII6xnzFgCbAAAaAAII6xnzFgCbAAAsAAQKgTMAAhoACAjnIBgOAOYCABoACAjnIBgOAOYCAAAA.Elarion:BAAALAADCggICAAAAA==.Eldrado:BAAALAADCggICAAAAA==.Elliè:BAAALAAECgYIEAAAAA==.Elo:BAAALAAECgUICgAAAA==.Elvenmaster:BAAALAAECgIIAgAAAA==.Elynea:BAAALAADCgcIBwABLAAECggIIgAQAMohAA==.',Eo='Eosphoros:BAAALAAECgcIBwAAAA==.',Ep='Ephrodite:BAAALAAECgYIEgABLAAECgYIGwAWAG8IAA==.',Er='Eraagon:BAAALAAECggICQAAAA==.Erdwip:BAAALAADCggIFgAAAA==.Erich:BAAALAAECgEIAQAAAA==.Erina:BAABLAAECoEWAAMCAAcI9xO0RQCaAQACAAcIghG0RQCaAQAbAAMIVBi3HADQAAAAAA==.',Es='Eskordilia:BAAALAADCggICAAAAA==.Ession:BAABLAAECoElAAIIAAcIuBaUEACRAQAIAAcIuBaUEACRAQAAAA==.',Et='Ethendrial:BAAALAAECgUIBQABLAAFFAUIEAAUAMUQAA==.',Eu='Euphory:BAAALAADCggICAAAAA==.',Ez='Ezy:BAAALAAECgMIAwAAAA==.',Fa='Faffnír:BAAALAAECgIIAgAAAA==.Fancynancy:BAAALAADCgcIEQAAAA==.',Fe='Felhound:BAAALAAECggIEwAAAA==.Felshade:BAABLAAECoEfAAISAAgIkyXCAQBeAwASAAgIkyXCAQBeAwAAAA==.Fener:BAABLAAECoEnAAIXAAgImiTqAQA8AwAXAAgImiTqAQA8AwAAAA==.Ferodar:BAAALAADCgIIAgAAAA==.Fettesschaf:BAAALAAECgYIEQABLAAECgYIGwAWAG8IAA==.',Fi='Filicytas:BAAALAAECgYIDwAAAA==.Finiz:BAAALAADCgUIBQABLAADCgcICwAFAAAAAA==.Fiochi:BAAALAAECgYIEQAAAA==.Firunnexe:BAAALAADCgMIAwABLAAFFAUIEAAUAMUQAA==.Firunnqt:BAAALAAECgIIAgABLAAFFAUIEAAUAMUQAA==.Firuun:BAAALAADCgQIBAABLAAFFAUIEAAUAMUQAA==.Fizzle:BAAALAAECgQIBAABLAAFFAUICwAHADAWAA==.',Fl='Flakest:BAAALAADCggIIAAAAA==.',Fo='Foha:BAAALAAECgYICwAAAA==.',Fr='Frigobald:BAAALAAECgYIEwAAAA==.',Fu='Furorean:BAAALAAECgYIDAAAAA==.',Ga='Gamagos:BAACLAAFFIEGAAILAAII5hzoHwCuAAALAAII5hzoHwCuAAAsAAQKgRsAAgsACAhOIcoXAP0CAAsACAhOIcoXAP0CAAAA.Gannicus:BAAALAADCgcIBwABLAAECgcIGAARAOIbAA==.',Ge='Geertje:BAAALAAECggICAAAAA==.Gegengîft:BAAALAADCggICAAAAA==.Gegenverkehr:BAAALAADCggICAAAAA==.Gercrusher:BAABLAAECoEZAAIEAAYIVxm/UgDBAQAEAAYIVxm/UgDBAQAAAA==.',Gi='Gienga:BAABLAAECoEZAAIBAAcIHBeELACpAQABAAcIHBeELACpAQAAAA==.Gilhalad:BAAALAADCgcIDAAAAA==.Gilondil:BAABLAAECoEUAAIDAAgIUyHAFgDcAgADAAgIUyHAFgDcAgABLAAFFAUICwAHADAWAA==.',Gl='Glaphan:BAABLAAECoEcAAIMAAgIohgTBgBcAgAMAAgIohgTBgBcAgAAAA==.Glauron:BAAALAAECgQICgAAAA==.',Go='Goldensun:BAAALAAECggIDgABLAAECggIJgAWAFweAA==.Goldwing:BAABLAAECoEaAAMCAAgIUxoGJQA8AgACAAgIUxoGJQA8AgAbAAIIqRrmIgCUAAAAAA==.Golgatha:BAAALAADCgcIFAAAAA==.Goslaktrote:BAABLAAECoEoAAIOAAgIzBoXEQByAgAOAAgIzBoXEQByAgAAAA==.Gothan:BAABLAAECoEVAAIcAAgI3SCjAgAOAwAcAAgI3SCjAgAOAwAAAA==.',Gr='Gragàs:BAAALAADCgcIBwAAAA==.Grighor:BAAALAAECgEIAgAAAA==.Gronjavil:BAABLAAECoEYAAIOAAgI/gG2SwCDAAAOAAgI/gG2SwCDAAAAAA==.Grêg:BAABLAAECoEYAAIEAAYIYx8QPAATAgAEAAYIYx8QPAATAgAAAA==.',Gu='Gulsin:BAAALAAECgQIEAAAAA==.',Gw='Gwint:BAAALAAECggICgAAAA==.',['Gû']='Gûndabur:BAAALAAFFAEIAQAAAA==.',Ha='Habibi:BAAALAADCgcIBwAAAA==.Haché:BAAALAADCggICAAAAA==.Haffí:BAABLAAECoEeAAIKAAgIYhQQSADdAQAKAAgIYhQQSADdAQAAAA==.Hagazusa:BAAALAAECgEIAQAAAA==.Halkhar:BAABLAAECoEcAAIdAAgIQBTzFAD8AQAdAAgIQBTzFAD8AQAAAA==.Halldor:BAAALAADCggIEQAAAA==.Hanako:BAAALAAECgYICQAAAA==.',He='Healndeal:BAAALAAECgEIAQAAAA==.Heavenly:BAAALAAECgYICwAAAA==.Hedu:BAABLAAECoEaAAIRAAcIAQqDeACAAQARAAcIAQqDeACAAQAAAA==.Heilpflaster:BAAALAADCgQIBAAAAA==.Helaskreem:BAAALAADCggIFwAAAA==.Hexeanita:BAABLAAECoEjAAINAAcIaA9TYACcAQANAAcIaA9TYACcAQAAAA==.Hexiexi:BAAALAAECggIDwABLAAECggIEwAFAAAAAA==.Hexodus:BAAALAAECgYIDAAAAA==.',Hi='Hima:BAAALAAECgEIAQAAAA==.Hippo:BAABLAAECoEYAAQMAAcIDxgaDgC0AQAMAAYI9xYaDgC0AQAQAAUIrRjVNQB1AQANAAUIyw+AkAAaAQABLAAFFAIIBQAQANUdAA==.Hippodh:BAAALAAECgMIAwABLAAFFAIIBQAQANUdAA==.Hippofive:BAAALAAECgYIDgAAAA==.Hippofour:BAAALAADCgYIBgABLAAFFAIIBQAQANUdAA==.Hippopr:BAAALAADCggICAABLAAFFAIIBQAQANUdAA==.Hipposix:BAAALAADCgYIBgABLAAFFAIIBQAQANUdAA==.Hippothree:BAAALAADCgYIBgABLAAFFAIIBQAQANUdAA==.Hippotwo:BAACLAAFFIEFAAMQAAII1R0bBwC7AAAQAAII1R0bBwC7AAANAAEIOgAQSQAOAAAsAAQKgSUABBAACAioIVoEABMDABAACAhdIVoEABMDAA0ACAjiFkI1ADkCAAwABQhBI4ALAOABAAAA.Hipptotemaus:BAAALAADCgUIBQABLAAFFAIIBQAQANUdAA==.',Ho='Holyfists:BAAALAAECgYIDgAAAA==.Horda:BAAALAAECgEIAQAAAA==.',Hu='Hullatrulla:BAAALAADCgYIFQAAAA==.Huntertank:BAAALAADCggIDQABLAAECggIGQAWAI0WAA==.',Hy='Hypeset:BAAALAAECgUICgAAAA==.',['Hê']='Hêl:BAAALAAECgUIBwAAAA==.',['Hô']='Hôlly:BAAALAADCggIEAAAAA==.',Ic='Icrisp:BAAALAADCggIGAAAAA==.',Id='Idrien:BAAALAADCgcIBAAAAA==.',Ii='Iibu:BAAALAAECgMIBwAAAA==.',Il='Ilahjà:BAAALAAECgEIAgAAAA==.Illumina:BAABLAAECoEiAAMQAAgIyiF+CADDAgAQAAgI6x9+CADDAgANAAgI1xkyKAB6AgAAAA==.Ilárà:BAAALAADCgcIBwAAAA==.',In='Inania:BAAALAAECgYIDAAAAA==.Indirà:BAABLAAECoEUAAMQAAYIyB1NJwC6AQAQAAUISR5NJwC6AQANAAMIQxQ5qwDAAAAAAA==.Indra:BAAALAADCggIEQABLAAECgcIIgAEAKYZAA==.Infèctión:BAEALAADCggICAAAAA==.Inkipinki:BAAALAADCggICAAAAA==.',Ir='Ironstan:BAAALAADCgMIAwAAAA==.Irrii:BAABLAAECoElAAIeAAcIWRI5HACLAQAeAAcIWRI5HACLAQAAAA==.',Is='Issil:BAAALAAECgIIAgAAAA==.',Iz='Izanagi:BAAALAAECgYICQABLAAECgcIIgAEAKYZAA==.',Ja='Jalani:BAAALAADCgcICAAAAA==.Jassdudu:BAAALAADCggICAAAAA==.',Je='Jerestiné:BAAALAAECgQIBAAAAA==.Jeânne:BAAALAAECgYICgAAAA==.',Jh='Jhove:BAAALAAECgYIDQAAAA==.',Ji='Jinidan:BAAALAADCgQIBAAAAA==.Jirokhan:BAAALAAECgYICwAAAA==.',Jo='Jodi:BAAALAADCgcIBwAAAA==.Jokerr:BAABLAAECoEfAAIfAAgI/B4TFAC5AgAfAAgI/B4TFAC5AgAAAA==.',Ju='Jupiter:BAAALAAECgYIEQABLAAECgcIIgAEAKYZAA==.Jurá:BAABLAAECoEUAAIDAAYI9h1qdQCUAQADAAYI9h1qdQCUAQAAAA==.',Jy='Jysar:BAAALAADCgQIBAAAAA==.',['Jø']='Jøke:BAAALAADCgUIBQABLAAECggIHwAfAPweAA==.',Ka='Kaahanu:BAACLAAFFIEFAAITAAIIggtnJgCCAAATAAIIggtnJgCCAAAsAAQKgS0AAhMACAh6EwIxAO0BABMACAh6EwIxAO0BAAAA.Kagenomiko:BAAALAAECgYIDQABLAAECggIGQAWAI0WAA==.Kamiragi:BAAALAADCggIDwAAAA==.Kardanar:BAAALAAECgYIDAAAAA==.Karila:BAAALAAECgMIAwABLAAECgYIDAAFAAAAAA==.Kathleen:BAAALAADCgYIBgAAAA==.',Ke='Keana:BAABLAAECoEVAAIKAAcIOw4YhAA+AQAKAAcIOw4YhAA+AQAAAA==.Kenai:BAAALAADCggIBwAAAA==.Kermanudâs:BAABLAAECoEuAAMBAAgIVxXiMACSAQARAAgIgRAFVwDfAQABAAYIbRbiMACSAQAAAA==.',Ki='Killmachine:BAABLAAECoElAAIDAAcIOR/mRwAIAgADAAcIOR/mRwAIAgAAAA==.Kimono:BAAALAAECgQICQAAAA==.Kiânâ:BAAALAAECgYIBgAAAA==.',Kl='Klaatu:BAAALAAECgIIAgAAAA==.Kleng:BAAALAADCgcIBgABLAAECgYIDAAFAAAAAA==.Klingsohr:BAAALAAECggICAAAAA==.Klópfaer:BAABLAAECoEVAAIGAAcIFhoBLwApAgAGAAcIFhoBLwApAgAAAA==.',Ko='Kodoschänder:BAAALAAECggIEQABLAAECgYIFAADAPYdAA==.Kodumatu:BAAALAAECgMIBAAAAA==.Kongroa:BAAALAAECgYIDAAAAA==.Korkran:BAAALAADCgYIDwAAAA==.Koyakhar:BAAALAAECgIIAgAAAA==.',Kr='Kriegnieheal:BAAALAADCggIEAAAAA==.Kruber:BAAALAADCgYICQAAAA==.Kryzen:BAAALAAECgIIAgAAAA==.',Ku='Kurdran:BAAALAAECgcIEgAAAA==.Kurushimu:BAAALAADCgcIDQAAAA==.',Ky='Kydia:BAAALAAECgYIDAAAAA==.',['Ká']='Káli:BAABLAAECoEVAAIPAAcIxxu3GQAyAgAPAAcIxxu3GQAyAgAAAA==.',['Kâ']='Kâkuzu:BAAALAADCggIEAABLAAECggIIAAWALcQAA==.',['Kí']='Kíra:BAAALAAECgcIBwAAAA==.',La='Laconia:BAAALAAECgIIAgAAAA==.Lasouris:BAAALAADCgYIDwAAAA==.',Le='Leisepranke:BAAALAAECgMIAwAAAA==.Lemia:BAAALAADCgcIDwABLAADCggIGAAFAAAAAA==.Lenarî:BAAALAAECgUICQAAAA==.Leolaz:BAAALAADCgIIAgAAAA==.Levera:BAAALAADCgQIBAABLAAFFAUICwAHADAWAA==.Lexaeus:BAAALAAECgYIBgAAAA==.Lexiza:BAAALAADCggIFAAAAA==.',Li='Lictor:BAABLAAECoEVAAMLAAYI9BY6gQC3AQALAAYI9BY6gQC3AQAXAAYI6QxeRgABAQAAAA==.Lilya:BAABLAAECoEVAAIBAAgIARqXFwA9AgABAAgIARqXFwA9AgAAAA==.Limbozot:BAAALAADCgcIEQAAAA==.Littleyoda:BAAALAAECgIIAgAAAA==.Liânâ:BAAALAAECgcICQAAAA==.',Lo='Lonara:BAAALAADCggICAAAAA==.Loqx:BAAALAADCggICAAAAA==.Lorian:BAAALAAECgUIBwAAAA==.Lotgar:BAAALAADCgUIBQAAAA==.',Lu='Lulubadgirl:BAAALAADCgUIBgAAAA==.Luminexa:BAAALAADCgcICgAAAA==.Luniar:BAAALAADCggICAAAAA==.Lunábird:BAABLAAECoEeAAICAAcIXAmRXABEAQACAAcIXAmRXABEAQAAAA==.Lunêxos:BAAALAADCggIDwAAAA==.Luro:BAAALAAECgYIDAAAAA==.Luzifara:BAAALAAECgYIEQABLAAECggIDgAFAAAAAA==.',Ly='Lydi:BAAALAAECgEIAQAAAA==.Lyranne:BAABLAAECoEWAAIKAAYIfSAENQAcAgAKAAYIfSAENQAcAgAAAA==.Lyrissa:BAAALAAECgcIEwAAAA==.',['Lâ']='Lânessâ:BAAALAADCggICAAAAA==.',['Lé']='Léxa:BAAALAADCggICAABLAAECgYIFgAKAH0gAA==.Léyá:BAAALAAECgMIAwAAAA==.',['Lî']='Lîyana:BAACLAAFFIEPAAMgAAMI1BvWGADuAAAgAAMI/RXWGADuAAAhAAIIFSB7CAC/AAAsAAQKgTIAAyAACAi2JDEeANkCACAACAieIjEeANkCACEABgjwJBoLAIwCAAAA.',Ma='Mado:BAABLAAECoEUAAMiAAcIYQ5YDACGAQAiAAcI2QpYDACGAQAUAAcINQtBNACBAQAAAA==.Maio:BAAALAADCggIGgAAAA==.Malirog:BAAALAADCggICAAAAA==.Maluforion:BAAALAAECgYIDwAAAA==.Manscreeda:BAABLAAECoEtAAMRAAgImSQJCgA3AwARAAgImSQJCgA3AwABAAQIDx4EUwDwAAAAAA==.Manuellsen:BAABLAAECoEgAAIEAAgImg1QWQCsAQAEAAgImg1QWQCsAQAAAA==.Maultäschle:BAABLAAECoEbAAIWAAYIbwhDuwAhAQAWAAYIbwhDuwAhAQAAAA==.Mayva:BAAALAAECgMIBQAAAA==.Mazzerules:BAAALAAECgYIBgAAAA==.',Mc='Mcgee:BAAALAAECgcIEQAAAA==.Mcwastey:BAAALAAECgYICQAAAA==.',Me='Meganfrost:BAAALAAECgMIAwAAAA==.Mehran:BAACLAAFFIELAAIHAAUIMBZdBQCdAQAHAAUIMBZdBQCdAQAsAAQKgSYAAgcACAiMJJQHACwDAAcACAiMJJQHACwDAAAA.',Mi='Mickey:BAABLAAECoEeAAIKAAcIHCQzGwCMAgAKAAcIHCQzGwCMAgAAAA==.Millii:BAABLAAECoEcAAIWAAgI9AsKoABZAQAWAAgI9AsKoABZAQAAAA==.Miniarthas:BAAALAAECgYICQAAAA==.Mirakulix:BAABLAAECoEoAAIIAAgITSJLAgAZAwAIAAgITSJLAgAZAwAAAA==.',Mj='Mjölnýr:BAAALAADCgYIBgAAAA==.',Mo='Monkeykøng:BAAALAAECggIEAAAAA==.Monkomg:BAAALAAECgYICQAAAA==.Mononoke:BAAALAAECgYIDwAAAA==.Moonnights:BAAALAAECgIIBgAAAA==.Morgainea:BAAALAAECgcIEgAAAA==.Morodeth:BAABLAAECoEnAAIQAAgI8CH5AwAbAwAQAAgI8CH5AwAbAwAAAA==.',My='Mybabe:BAAALAAECgYICgABLAAECgYIFAADAPYdAA==.Mykera:BAAALAADCgYIEQAAAA==.Myrelia:BAAALAADCgcIIQAAAA==.',['Má']='Májor:BAABLAAECoEgAAIEAAcIcxkERgDsAQAEAAcIcxkERgDsAQAAAA==.',['Mä']='Mäggi:BAAALAADCgYIDAAAAA==.',['Mì']='Mìkasa:BAABLAAECoEWAAMVAAcItBfGFQDIAQAVAAcItBfGFQDIAQAUAAYIxw+oOwBXAQAAAA==.',['Mí']='Míraculix:BAAALAAECgYICQABLAAECgQIDwAFAAAAAA==.',['Mø']='Mørpheus:BAAALAAECgEIAQABLAAECgQIDwAFAAAAAA==.',Na='Nabu:BAAALAAECgYIDwAAAA==.Nahza:BAAALAAECgMIAwAAAA==.Nailbomb:BAAALAAECggICAAAAA==.Nane:BAAALAADCggIDQAAAA==.Naraani:BAABLAAECoEeAAICAAgIZCN4BQA4AwACAAgIZCN4BQA4AwAAAA==.Nariâna:BAABLAAECoEcAAIWAAgIFAmYjgB7AQAWAAgIFAmYjgB7AQAAAA==.Nathare:BAAALAADCgIIAgAAAA==.Nathiniel:BAAALAAECgYIDwABLAAFFAQICQAKAJQZAA==.Nature:BAAALAAECgIIAgAAAA==.Naíra:BAABLAAECoEoAAIWAAgIah2kJQCoAgAWAAgIah2kJQCoAgAAAA==.',Ne='Neadana:BAAALAADCgUIBQAAAA==.Nebbia:BAAALAAECgIIAgAAAA==.Necrox:BAABLAAECoEVAAIgAAYILhrXjQCoAQAgAAYILhrXjQCoAQAAAA==.Needamedic:BAABLAAECoEWAAICAAgINwcbbAASAQACAAgINwcbbAASAQAAAA==.Nefflo:BAAALAAECgYIDQAAAA==.Neolon:BAAALAAECgYIDwAAAA==.Neptune:BAAALAADCgcIEwABLAAECgcIIgAEAKYZAA==.Nergrim:BAAALAAECgQIBQAAAA==.Nezukø:BAAALAAECgYIBwABLAAECggIIAAWALcQAA==.Neÿtiri:BAAALAAECggIDgAAAA==.',Ni='Nia:BAACLAAFFIEGAAICAAIIKR8lFwC6AAACAAIIKR8lFwC6AAAsAAQKgS0AAx8ACAhDIKkeAF8CAB8ABwiFH6keAF8CAAIACAj6GD8jAEgCAAAA.Nidhog:BAAALAADCgcICwAAAA==.Nimiel:BAABLAAECoEkAAILAAgIiBeSVAAXAgALAAgIiBeSVAAXAgAAAA==.Ninwe:BAABLAAECoEmAAIWAAgIXB5rHwDIAgAWAAgIXB5rHwDIAgAAAA==.Nirî:BAAALAADCggIEAAAAA==.',No='Nordfee:BAAALAADCggIGAAAAA==.Nose:BAAALAADCggIDwAAAA==.Noura:BAAALAAECggIEQABLAAFFAUICwAHADAWAA==.Novania:BAAALAAECgMIAwAAAA==.',Ny='Nyzti:BAAALAAECgcIAQAAAA==.',['Né']='Néelo:BAAALAAECgUICQAAAA==.Nééla:BAAALAAECgYICwAAAA==.',['Ní']='Nímué:BAAALAADCgUIBQAAAA==.',Oa='Oahin:BAAALAAECgYIEAAAAA==.',Oc='Ocinsperle:BAAALAAECgYIDAAAAA==.',Od='Odetta:BAAALAAECgYIBgABLAAECggIMAAKAKUZAA==.',Ok='Okoma:BAAALAADCgUIBQAAAA==.Oktayo:BAABLAAECoEmAAIPAAgI6CJUBgAdAwAPAAgI6CJUBgAdAwAAAA==.',Ol='Olleg:BAAALAADCggICAAAAA==.',On='Onlybuffing:BAABLAAECoEZAAIWAAgIjRawQwAuAgAWAAgIjRawQwAuAgAAAA==.',Or='Orion:BAAALAAECgIIAwABLAAECgcIIgAEAKYZAA==.Ork:BAAALAAECgcIAwAAAA==.Orklord:BAAALAAECgYIDgAAAA==.',Oy='Oya:BAAALAAECgYIEAAAAA==.',Pa='Pahtfinder:BAABLAAECoEoAAIDAAcIHhnVZwCzAQADAAcIHhnVZwCzAQAAAA==.Panicpriest:BAAALAAECgYIDwAAAA==.',Pe='Perccival:BAAALAADCgcIDgAAAA==.',Ph='Phirunn:BAABLAAECoEbAAMLAAcIiBqkWQALAgALAAcIiBqkWQALAgAXAAcIZgMKSwDnAAABLAAFFAUIEAAUAMUQAA==.Phoinix:BAABLAAECoEaAAMEAAgI/h9WFQDqAgAEAAgI8x9WFQDqAgAPAAYIXRkILQCjAQAAAA==.',Pi='Piandao:BAAALAAECgIIAQAAAA==.Pierrekill:BAAALAAECgIIAgAAAA==.',Pl='Plattenrind:BAAALAAECgQIDgAAAA==.Pluizig:BAAALAADCggICwAAAA==.Pluto:BAABLAAECoEiAAIEAAcIphntRQDsAQAEAAcIphntRQDsAQAAAA==.',Po='Polyphemus:BAAALAADCggICAAAAA==.',Pr='Priestar:BAAALAADCgMIAwAAAA==.Priestomat:BAAALAAECgMIAwAAAA==.Primez:BAAALAADCggICAAAAA==.Protóss:BAAALAAECgcIDgAAAA==.Pruegel:BAAALAADCgcIBwAAAA==.Própper:BAAALAADCggIDwAAAA==.',Pu='Pulsarine:BAAALAADCgcIBwAAAA==.',['Pí']='Píwo:BAAALAAECgIIAgAAAA==.',['Pû']='Pûrple:BAAALAAECgYIDwAAAA==.',Ra='Rado:BAABLAAECoEcAAIjAAcIqhXACAADAgAjAAcIqhXACAADAgAAAA==.Raftalia:BAABLAAECoEhAAQNAAgINRg7RQD2AQANAAgIPBU7RQD2AQAMAAIILg1WLQBuAAAQAAQIJxsAAAAAAAAAAA==.Rainjuná:BAAALAADCgYIBgAAAA==.Raldor:BAAALAAECgEIAQAAAA==.Rallyway:BAAALAADCgEIAQAAAA==.Ranctar:BAAALAAECgYIEAAAAA==.Randalegabi:BAAALAAECgQIBAAAAA==.Ravish:BAABLAAECoEcAAILAAcILRxFTQArAgALAAcILRxFTQArAgAAAA==.',Re='Reaktorkalle:BAAALAAECgQIBgAAAA==.Redban:BAABLAAECoEVAAMMAAcIwiHAAwCyAgAMAAcIwiHAAwCyAgANAAEIPQ+P2AA4AAAAAA==.Reira:BAAALAAECgMIBgAAAA==.',Rh='Rhoninn:BAAALAAECgIIAgAAAA==.',Ri='Riragu:BAAALAAECgYICwAAAA==.Riéke:BAAALAAECggICAAAAA==.',Ro='Roniñ:BAAALAAECgUIBQAAAA==.Rowyn:BAAALAAECgIIAwAAAA==.',Ru='Rubbeldekatz:BAAALAAECgMIAwAAAA==.Rudanja:BAAALAADCgYICQAAAA==.Runar:BAAALAADCggIEwAAAA==.',Ry='Ryllira:BAABLAAECoEwAAIKAAgIpRkxJgBXAgAKAAgIpRkxJgBXAgAAAA==.Ryú:BAAALAAECgcICwAAAA==.',['Rì']='Rìger:BAAALAAECgYIBgAAAA==.',['Rí']='Ríger:BAAALAADCgMIAQAAAA==.',['Rý']='Rýu:BAABLAAECoEnAAMXAAgI1x6tCgCvAgAXAAgI1x6tCgCvAgALAAMIHx2h4AAEAQAAAA==.',Sa='Sahlex:BAAALAAECgIIAgAAAA==.Sameth:BAAALAAECgYIEAAAAA==.Sandje:BAAALAADCgcIBwAAAA==.Sanitas:BAAALAAECgMIBQAAAA==.Sanity:BAAALAAECggIBwAAAA==.Sanitöterin:BAAALAADCggIFQAAAA==.Sarabald:BAAALAADCgQIBAAAAA==.Satinja:BAAALAAECgIIAgAAAA==.Saturn:BAAALAADCgcICwABLAAECgcIIgAEAKYZAA==.Saïx:BAAALAADCgcIBwAAAA==.',Sc='Scami:BAAALAAECggICAAAAA==.Schadownight:BAAALAADCggIDgAAAA==.Schnensch:BAAALAADCggIDQAAAA==.',Se='Seraphini:BAAALAADCgcIDAAAAA==.Seraphìne:BAABLAAECoEYAAIkAAgIjwiVMgA4AQAkAAgIjwiVMgA4AQAAAA==.Seresa:BAABLAAECoEeAAICAAcI/hmoLwADAgACAAcI/hmoLwADAgAAAA==.Serino:BAAALAAECgcICAABLAAECggIHQAPAH4gAA==.Serion:BAAALAADCgcIDgAAAA==.Seyfira:BAAALAAECgYIAwABLAAECggIJQATAAoaAA==.',Sh='Shamystyles:BAAALAAECgYICAABLAAECgYIFAADAPYdAA==.Sharíva:BAAALAAECgcIEgAAAA==.Shenlian:BAAALAADCgEIAQAAAA==.Sheriv:BAAALAADCggICAAAAA==.Shivà:BAAALAAECgIIAgAAAA==.Shièk:BAAALAAECgIIAgAAAA==.Shonyy:BAAALAAECgYIEAAAAA==.Shruikán:BAAALAAECgYIDQABLAAECggIHAAMAKIYAA==.Shy:BAAALAAECgUICAAAAA==.',Si='Sicklikemanu:BAAALAAECggIBAABLAAECggIHwAfAPweAA==.Sinchunter:BAAALAADCggICAAAAA==.Sinder:BAAALAADCgYICwAAAA==.',Sk='Skruggur:BAAALAAECgQIBgAAAA==.',Sn='Snakebíte:BAAALAAECgQIDwAAAA==.Sniju:BAAALAAECgMIAwAAAA==.',So='Soláris:BAAALAADCggIDwAAAA==.Sorabara:BAAALAAECgQIBAAAAA==.',Sp='Speik:BAAALAADCggICAAAAA==.Spiek:BAAALAADCggICAAAAA==.Spycha:BAAALAADCggIGAAAAA==.Spárks:BAAALAAECgYIBgAAAA==.',St='Starshine:BAABLAAECoElAAMDAAgIHRVPTAD6AQADAAgIHRVPTAD6AQAaAAEInQeXtwAmAAAAAA==.Steenbaard:BAAALAAECgEIAQAAAA==.Stefeu:BAAALAADCgYIBgABLAAECggIHwASAJMlAA==.Stoneghost:BAAALAAECgMIAgAAAA==.Stumpy:BAAALAADCggIEAAAAA==.Stêak:BAAALAAECgMIAwAAAA==.',Su='Sugarswini:BAABLAAECoEfAAINAAcIZQXzjwAcAQANAAcIZQXzjwAcAQAAAA==.Sumire:BAAALAADCgYIBgAAAA==.Sumurdh:BAAALAADCggICAAAAA==.Sumíre:BAACLAAFFIEJAAIKAAQIlBl3CABSAQAKAAQIlBl3CABSAQAsAAQKgSoAAgoACAjhIZESAMECAAoACAjhIZESAMECAAAA.Sunaya:BAAALAADCgYIDQABLAAECgYIDAAFAAAAAA==.',Sw='Swagbanana:BAABLAAECoEVAAILAAYI1BfctABaAQALAAYI1BfctABaAQAAAA==.Swiffer:BAABLAAECoEtAAIEAAgIux+eFwDbAgAEAAgIux+eFwDbAgAAAA==.Swordart:BAAALAAECgYICQAAAA==.',Sy='Syndra:BAAALAADCgQIBAAAAA==.Syntia:BAAALAADCggICAAAAA==.',Sz='Szerris:BAAALAADCgcIBwAAAA==.',['Só']='Sódóm:BAAALAAECggICAAAAA==.Sóláris:BAAALAAECggIBQAAAA==.',Ta='Tabalugo:BAAALAAECgEIAQAAAA==.Takade:BAAALAAECgIIAgAAAA==.Takeku:BAAALAADCggIDgAAAA==.Talej:BAAALAADCgcICgAAAA==.Taleridormi:BAAALAAECgMIAwAAAA==.Tarabo:BAAALAADCgEIAQAAAA==.Taramira:BAABLAAECoEkAAIlAAgISiIoBgDqAgAlAAgISiIoBgDqAgAAAA==.Tayulia:BAACLAAFFIELAAIWAAMIvxlYEgD4AAAWAAMIvxlYEgD4AAAsAAQKgSwAAhYACAgiJboKAD8DABYACAgiJboKAD8DAAAA.',Tb='Tbone:BAAALAAECgYIDgAAAA==.',Te='Teitus:BAAALAAECggIBgAAAA==.Telura:BAAALAAECgYIAgAAAA==.Telvor:BAAALAADCgUIBgAAAA==.Terendant:BAAALAADCggIFQAAAA==.',Th='Thargoll:BAABLAAECoEWAAIMAAgIqBwFBACnAgAMAAgIqBwFBACnAgABLAAFFAYIDQALAP8eAA==.Thetamarie:BAAALAAECgQIBgAAAA==.Thoreas:BAAALAAECgUIBwAAAA==.Threndar:BAAALAAECgIIBAAAAA==.Throndor:BAAALAADCgcIBwABLAADCgcIDAAFAAAAAA==.Thulazea:BAABLAAECoEYAAIZAAgIBg1HKAC7AQAZAAgIBg1HKAC7AQAAAA==.Thuzad:BAACLAAFFIEJAAIgAAMINRUbGADxAAAgAAMINRUbGADxAAAsAAQKgSoAAiAACAjEIj0WAAADACAACAjEIj0WAAADAAAA.',Ti='Tifilou:BAAALAADCgcIBwAAAA==.Tiggy:BAAALAAECggICgAAAA==.Tilandra:BAAALAADCgUIBQAAAA==.Tingting:BAAALAADCggICAAAAA==.',Tj='Tjojo:BAAALAADCgYIBgAAAA==.Tjotjo:BAAALAAECgUIBQAAAA==.',To='Torglosch:BAAALAADCgcICQAAAA==.',Tr='Treefu:BAAALAAECgcIEgAAAA==.Trivia:BAAALAADCgEIAQAAAA==.Trokdur:BAAALAADCgYIBgAAAA==.Trucy:BAAALAAECgcIEgAAAA==.Trînîty:BAAALAAECgcIEgAAAA==.',Ts='Tsarhood:BAAALAAECggIEwAAAA==.',Tu='Tubyra:BAAALAADCggICAAAAA==.',Tw='Twace:BAAALAAECgcIDgAAAA==.',Ty='Tyrael:BAAALAADCgMIAwABLAAECgQIDwAFAAAAAA==.Tyraja:BAAALAAECgIIAgAAAA==.',Tz='Tzeentch:BAAALAAECgEIAQAAAA==.',['Tá']='Tájá:BAAALAAECgMIAwAAAA==.',Ul='Ulfgrim:BAAALAADCggIFAAAAA==.Ulthane:BAAALAAECgYIDwAAAA==.Ultrajoker:BAAALAADCgcICgAAAA==.',Un='Ungoliant:BAAALAADCggIDAABLAAECgcIIgAEAKYZAA==.Union:BAAALAADCggICAAAAA==.Unmenschlich:BAAALAADCgYIBgAAAA==.',Va='Valunia:BAAALAADCgcIBwABLAAECgEIAQAFAAAAAA==.Vandis:BAAALAAECgMIAwAAAA==.Varojin:BAABLAAECoEdAAMcAAcImRs7CwAcAgAcAAcIWBg7CwAcAgAGAAcIxhkAAAAAAAAAAA==.Vattghern:BAAALAAECggIEAABLAAECggIHAAMAKIYAA==.',Ve='Vectus:BAAALAAECgUIBwAAAA==.Vegacraftdk:BAAALAAECgYIDwAAAA==.Vegadudu:BAAALAADCgIIAgAAAA==.Velgja:BAAALAADCgcIBwAAAA==.Venatrixx:BAAALAAECgMIBwAAAA==.Veroniká:BAAALAAECgIIAgAAAA==.',Vi='Viseris:BAAALAAECggICAAAAA==.',Vo='Vokalmatadór:BAAALAAECgMIBQABLAAECggIHgALAP0hAA==.',Wa='Waldfèe:BAABLAAECoEjAAIfAAgIUBKiMQDmAQAfAAgIUBKiMQDmAQAAAA==.Warnichtda:BAAALAADCgcIDwAAAA==.',Wi='Wizzie:BAAALAAECgYIDQAAAA==.',Wu='Wuschig:BAAALAAECggIDgABLAAECggIFAAPAPkZAA==.Wutzz:BAAALAAECggICAAAAA==.',['Wü']='Wünschelrute:BAAALAAECgYIDAAAAA==.',Xa='Xaren:BAACLAAFFIEGAAIOAAIIFhp+CgCkAAAOAAIIFhp+CgCkAAAsAAQKgRkAAg4ABwiiIeQMAKsCAA4ABwiiIeQMAKsCAAAA.',Xe='Xemnas:BAAALAAECgQIBwAAAA==.Xerath:BAAALAAECgMIAwAAAA==.',Xi='Xiakan:BAACLAAFFIETAAIeAAUI1yV4AQA2AgAeAAUI1yV4AQA2AgAsAAQKgTcAAh4ACAjjJjwAAJIDAB4ACAjjJjwAAJIDAAAA.',Xj='Xjang:BAAALAADCgYIBgAAAA==.Xjâng:BAAALAADCgYIBgAAAA==.',Xo='Xonay:BAABLAAECoEeAAIDAAgIrB3CLABpAgADAAgIrB3CLABpAgAAAA==.Xorean:BAAALAADCgYIBgAAAA==.',Xy='Xyriel:BAAALAADCgcICwAAAA==.',['Xà']='Xàvador:BAAALAAECgMIAwAAAA==.',Ya='Yasuo:BAAALAAECgUIEwAAAA==.Yaya:BAAALAADCggIEAAAAA==.',Yo='Yooda:BAAALAAECgYIDAAAAA==.Yoshino:BAAALAAECgYICgABLAAECgcIEAAFAAAAAA==.Youri:BAAALAAECgYIBgAAAA==.',Yu='Yukino:BAAALAAECgEIAgAAAA==.',Za='Zadora:BAAALAAECgQICgAAAA==.Zahard:BAAALAADCgYIBgAAAA==.Zalagos:BAAALAAECgIIAgAAAA==.Zarakez:BAAALAADCggIFQAAAA==.Zarb:BAAALAADCgEIAQAAAA==.Zareena:BAAALAADCgYIBgABLAAECggIBwAFAAAAAA==.Zauberkeks:BAAALAADCgYIBwAAAA==.Zayhira:BAAALAADCggICAAAAA==.',Ze='Zeeus:BAAALAADCgcIBwAAAA==.',Zh='Zharhelcut:BAAALAAECgUIBgAAAA==.',Zi='Zirash:BAAALAAECgYIEAAAAA==.',Zu='Zunâde:BAAALAAFFAIIBAAAAA==.Zurako:BAAALAADCgUIBQAAAA==.',Zw='Zwergblase:BAAALAADCggIDwAAAA==.Zwergfell:BAAALAAECggIEAAAAA==.',['Zø']='Zøa:BAAALAAECgIIAgAAAA==.',['Àr']='Àrìçè:BAAALAAECgIIAgAAAA==.',['Âl']='Âlessia:BAABLAAECoEUAAIQAAYIFwKXZgClAAAQAAYIFwKXZgClAAAAAA==.',['Ân']='Ânastasiâ:BAABLAAECoEeAAIbAAcIDRqsBwAUAgAbAAcIDRqsBwAUAgAAAA==.',['Ât']='Âtârî:BAAALAADCggILAAAAA==.',['År']='Årtemis:BAAALAAECgYICQAAAA==.',['Æs']='Æsyr:BAAALAAECgEIAgAAAA==.',['Æy']='Æyla:BAAALAAECgIIAgAAAA==.',['Én']='Éndure:BAAALAADCggIDwAAAA==.',['Îc']='Îcarus:BAAALAADCggICAAAAA==.',['Ðe']='Ðementeus:BAABLAAECoEhAAMEAAgIQSNtEwD4AgAEAAgIiCFtEwD4AgAJAAEIvSF7LABeAAAAAA==.',['Ði']='Ðingsdá:BAAALAADCgcIBwAAAA==.',['Ðo']='Ðomitianos:BAAALAAECgYIBgAAAA==.',['Ök']='Ökobob:BAAALAADCgcIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end