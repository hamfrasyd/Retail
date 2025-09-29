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
 local lookup = {'DemonHunter-Havoc','Paladin-Retribution','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','Mage-Arcane','Mage-Fire','Druid-Restoration','Unknown-Unknown','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','DeathKnight-Unholy','Paladin-Protection','Warlock-Demonology','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Druid-Balance','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Monk-Windwalker','Priest-Holy','Hunter-BeastMastery','Priest-Shadow','Warlock-Affliction','Mage-Frost',}; local provider = {region='EU',realm='Dragonmaw',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ab='Abracanobra:BAAALAAECgMIAwAAAA==.',Ac='Acidride:BAAALAAECgYIDwAAAA==.',Ae='Aernath:BAAALAADCggICAABLAAECgcIHwABAPsWAA==.Aescanor:BAABLAAECoEhAAICAAgIfCHnGQDuAgACAAgIfCHnGQDuAgAAAA==.Aeth:BAACLAAFFIEKAAMDAAYI0Bo2BwBNAQADAAUIZho2BwBNAQAEAAEIOgTTEgBKAAAsAAQKgSQAAwMACAgBJl0CAGADAAMACAgBJl0CAGADAAQABgj4F1UVAKcBAAAA.',Al='Alexius:BAABLAAECoEWAAIFAAgIhg1MmQCMAQAFAAgIhg1MmQCMAQABLAAECggIIQACAHwhAA==.Alune:BAABLAAECoEsAAMGAAgIUh+AIgCqAgAGAAgI+R6AIgCqAgAHAAYI7Rz3BgDTAQAAAA==.',Ar='Arda:BAAALAAECgYIDAAAAA==.Arshes:BAAALAADCgYIBgAAAA==.',At='Atheïst:BAAALAAECgcIBwAAAA==.',Au='Autoshots:BAAALAADCggIFAAAAA==.',Ba='Badogas:BAAALAAECgYIEAAAAA==.Bakstabbath:BAAALAADCgcIBwAAAA==.Bapcan:BAAALAAECgQIBAAAAA==.Barnw:BAAALAADCggICAAAAA==.',Be='Belladonna:BAAALAADCggICAAAAA==.Benafflock:BAAALAAECgMIAwAAAA==.',Bi='Bigjuicerx:BAAALAAECgQIBAAAAA==.',Bo='Boddit:BAABLAAECoEdAAIIAAgIph+WFwB0AgAIAAgIph+WFwB0AgAAAA==.Bokku:BAAALAAECgIIAgAAAA==.Boosinka:BAAALAAECggICAAAAA==.',Bu='Bubbleoseven:BAAALAAECgYIEQAAAA==.',['Bí']='Bía:BAAALAAECgIIAgAAAA==.',Ce='Cenobite:BAAALAADCggIGAAAAA==.',Ch='Ch:BAAALAAECgcIEwAAAA==.Chãd:BAAALAADCgYIBgAAAA==.',Ci='Cilitbang:BAAALAADCggICQAAAA==.',Co='Coké:BAAALAADCgUIBQABLAAECgcIDgAJAAAAAA==.Coronos:BAAALAADCgQIBAAAAA==.Corwi:BAACLAAFFIEKAAIKAAMIzx/OBQAgAQAKAAMIzx/OBQAgAQAsAAQKgR8AAgoACAi1IxsDADkDAAoACAi1IxsDADkDAAAA.',Cr='Crimm:BAABLAAECoEcAAMLAAgIdhPfSQDTAQALAAgI3RLfSQDTAQAMAAQIuhNnHQDzAAAAAA==.Crystalblack:BAAALAAECgIIAgAAAA==.',Da='Daddydot:BAAALAADCggIEAAAAA==.Daisay:BAAALAAECgcICQAAAA==.Darchi:BAABLAAECoEbAAINAAcI0Q1AMACUAQANAAcI0Q1AMACUAQAAAA==.',De='Deathstrik:BAAALAADCgEIAQAAAA==.Deavirys:BAAALAADCggICAAAAA==.Demoana:BAAALAADCgMIAwAAAA==.Demonaboody:BAABLAAECoEUAAIBAAgIcgYDnABWAQABAAgIcgYDnABWAQAAAA==.Desyre:BAABLAAECoEXAAMOAAcITxCCGwDDAQAOAAcITxCCGwDDAQAFAAIIowTrNQFNAAAAAA==.',Di='Diggerxcv:BAAALAAFFAIIAgAAAA==.Diggerxxvii:BAABLAAECoEVAAIKAAgIeBt8EAAfAgAKAAgIeBt8EAAfAgAAAA==.Disdain:BAAALAAFFAEIAQAAAA==.',Dr='Drizzleriz:BAAALAAECgIIAgAAAA==.Drrazzilb:BAAALAAECgQIBAAAAA==.',Du='Duskclaw:BAAALAADCggICgAAAA==.Dust:BAAALAAECgYIDgAAAA==.',Dy='Dyx:BAAALAAECgcIDgAAAA==.',Dz='Dzeaz:BAAALAADCgcIBwAAAA==.',Ei='Eidolorne:BAAALAAECgQICAAAAA==.Eikoos:BAAALAADCgIIAgAAAA==.Einmyria:BAABLAAECoEdAAIPAAgIZxpsEABMAgAPAAgIZxpsEABMAgAAAA==.',El='Elcolorete:BAAALAADCgMIAgAAAA==.Ellora:BAABLAAECoEVAAIQAAcI7gxDKwCiAQAQAAcI7gxDKwCiAQAAAA==.Ellorã:BAAALAAECgYIDAAAAA==.Elzorab:BAAALAADCgYIBgAAAA==.',Et='Ethog:BAABLAAECoEdAAMMAAcI1hi+CgAOAgAMAAcIABi+CgAOAgALAAcIbBQgSADZAQAAAA==.',Fa='Fatiguéet:BAAALAADCgcICAAAAA==.',Fe='Felsolo:BAAALAADCggICAAAAA==.',Fo='Fordragon:BAABLAAECoEUAAICAAYIqB0+UQAaAgACAAYIqB0+UQAaAgAAAA==.',Fu='Fuzzywuzzy:BAAALAADCggICAAAAA==.',Ga='Gallywix:BAAALAAECgYICwAAAA==.Galor:BAABLAAECoEWAAMRAAcI6hjDLwAdAgARAAcI6hjDLwAdAgASAAYIsQfuuADIAAAAAA==.',Gl='Gloryna:BAAALAADCgUIBQABLAAECggIHgABABsaAA==.',Gn='Gnome:BAAALAADCggIDwABLAAECgcIEgAJAAAAAA==.Gnomelock:BAABLAAECoEWAAMQAAgIuxH6KQCoAQAQAAcIcBH6KQCoAQATAAQINQjyrQClAAAAAA==.Gnomer:BAAALAADCggIEAABLAAECgcIEgAJAAAAAA==.',Go='Goanga:BAAALAAECgYIBgAAAA==.Golíat:BAAALAAECgYIBwAAAA==.Gordonramsey:BAAALAADCgcIDwAAAA==.Goyathlay:BAAALAADCggICAAAAA==.',Gr='Greta:BAAALAADCgIIAgAAAA==.',Ha='Hanthraxus:BAAALAADCgUIBQAAAA==.Hasbulla:BAAALAAECggICAAAAA==.Havermoud:BAAALAADCgEIAQAAAA==.Hazedevil:BAAALAADCggILAAAAA==.Hazeke:BAAALAADCggILQAAAA==.Hazel:BAAALAADCggILgAAAA==.Haìtch:BAACLAAFFIEOAAIBAAUIcBgrBgDdAQABAAUIcBgrBgDdAQAsAAQKgSsAAgEACAgSIwIQABsDAAEACAgSIwIQABsDAAAA.',Hc='Hcaz:BAAALAAECggICwAAAA==.',He='Hektor:BAAALAAECggICAAAAA==.',Hi='Hiorith:BAABLAAECoEXAAIUAAgI5hNVKgDrAQAUAAgI5hNVKgDrAQAAAA==.Hissy:BAABLAAECoEWAAITAAcI6xI+TADUAQATAAcI6xI+TADUAQAAAA==.',Ho='Holymights:BAAALAAECgIIAgAAAA==.',Hr='Hrd:BAAALAAECgMIBwAAAA==.',In='Innoruk:BAABLAAECoEeAAIFAAgI1xldQQBNAgAFAAgI1xldQQBNAgAAAA==.',Iq='Iquqnus:BAAALAADCgcIBQAAAA==.',Jo='Johndoe:BAAALAADCggIEgAAAA==.Johnlennon:BAAALAAECgcIDwAAAA==.Joksy:BAAALAAECgYIDAAAAA==.Jomi:BAAALAAECgYIBgAAAA==.Jox:BAACLAAFFIEMAAIUAAUIChgoBACzAQAUAAUIChgoBACzAQAsAAQKgSwAAhQACAgcJRYFAEkDABQACAgcJRYFAEkDAAAA.Joxi:BAAALAAECgYIDAAAAA==.Joxikor:BAAALAADCgEIAQABLAAFFAUIDAAUAAoYAA==.',Ka='Kaelthorn:BAABLAAECoEVAAMVAAcI3RE+KwAdAQABAAcIdQmkmgBZAQAVAAYItBM+KwAdAQAAAA==.Kaj:BAAALAAECgMIAwAAAA==.Kajuka:BAAALAAECgUIBQAAAA==.Karim:BAAALAADCgcIDAABLAAECggILAACAGgaAA==.Karo:BAAALAAECgIIAwAAAA==.Karsh:BAAALAADCgEIAQAAAA==.',Ke='Kenlée:BAAALAAECgEIAQAAAA==.',Kh='Khalisthar:BAAALAADCgUIBQAAAA==.',Ki='Kimo:BAABLAAECoEWAAIIAAYIzgw2ZQAbAQAIAAYIzgw2ZQAbAQAAAA==.',Ko='Koponen:BAAALAADCgYIBgAAAA==.Korretin:BAAALAADCgYIBgAAAA==.',Ku='Kurisuti:BAAALAAECgUIBQAAAA==.',La='Laacuks:BAAALAAECgUICAABLAAECggIIwAWAOcXAA==.Lakazam:BAAALAAECgYICQAAAA==.Lamar:BAAALAAECggIDAABLAAECggIEwAJAAAAAA==.Lazydruid:BAABLAAECoEmAAMUAAgIyxGIMwC4AQAUAAgIdxCIMwC4AQAXAAcI/Q+bEQByAQAAAA==.',Le='Leahh:BAAALAADCgUIBQAAAA==.',Li='Libodo:BAAALAADCgMIAwAAAA==.Lilhaze:BAAALAADCggIEAAAAA==.Liluni:BAABLAAECoEWAAIOAAgIxxGjEQApAgAOAAgIxxGjEQApAgAAAA==.',Lo='Lockdown:BAAALAAECgYIBwAAAA==.Lockto:BAAALAADCgEIAQAAAA==.',Lu='Lurt:BAAALAAECgMICAAAAA==.',Ly='Lyceria:BAAALAADCgEIAQAAAA==.',Ma='Magik:BAAALAADCgcIDQAAAA==.Mandarinka:BAAALAAECgYIBgAAAA==.Manur:BAAALAAECgMIAwAAAA==.Masrawi:BAABLAAECoEsAAICAAgIaBphNwBnAgACAAgIaBphNwBnAgAAAA==.Masree:BAABLAAECoEfAAMVAAcIEQ7tJABLAQAVAAcIEQ7tJABLAQABAAIIVgNwDwE6AAABLAAECggILAACAGgaAA==.',Me='Meiling:BAABLAAECoEdAAMKAAgI/BtmDQBRAgAKAAcInh1mDQBRAgAYAAYItxI2OQAPAQAAAA==.Melina:BAAALAAECgQIBAAAAA==.',Mi='Midgar:BAAALAADCggIGAAAAA==.Mixarn:BAAALAADCgQIAwABLAAECggIIgABAKUjAA==.',Mo='Modern:BAABLAAFFIEHAAIGAAIIRiTFHQDQAAAGAAIIRiTFHQDQAAAAAA==.Moozle:BAAALAADCgcICAABLAAFFAQIBwAZAJ8PAA==.Morghan:BAAALAADCggICAABLAAECgYICwAJAAAAAA==.Morgkam:BAAALAADCgQIBAABLAAECgYICwAJAAAAAA==.Morgomir:BAAALAAECgYICwAAAA==.Moxi:BAAALAAECgYIDwAAAA==.',My='Myhunt:BAAALAAECgYIEgABLAAECggIEwAJAAAAAA==.',Na='Natsuka:BAAALAAECgcIEwAAAA==.',Ne='Nefarius:BAAALAAECggICAABLAAECggIJQAaABYiAA==.',Ni='Nieram:BAAALAADCggICgAAAA==.',No='Noctyra:BAAALAADCggICQAAAA==.Noravalkyrie:BAAALAADCgcICgAAAA==.',Ny='Nyxclaw:BAAALAADCggICgAAAA==.',['Nô']='Nôvaa:BAAALAADCgYIBgAAAA==.',Oa='Oakley:BAAALAADCgcIBwAAAA==.',Od='Oden:BAAALAAECgMIAwAAAA==.',Or='Orgrims:BAAALAADCgcIBwAAAA==.',Oy='Oyvnordk:BAABLAAECoEcAAIFAAgI+gu4oACAAQAFAAgI+gu4oACAAQAAAA==.',Oz='Ozgard:BAABLAAECoEVAAIRAAgICBFlNwD4AQARAAgICBFlNwD4AQAAAA==.',Pa='Palato:BAAALAAECgYIBgAAAA==.',Pl='Play:BAABLAAECoEYAAIGAAYIUiClYAC7AQAGAAYIUiClYAC7AQABLAAFFAIIAgAJAAAAAA==.',Po='Pojope:BAAALAADCggIEAAAAA==.Popeadin:BAAALAAECggICAAAAA==.Poshlepa:BAABLAAECoEbAAITAAgI+yGlGgDFAgATAAgI+yGlGgDFAgAAAA==.Pow:BAAALAAECgYIDwAAAA==.',Pr='Prid:BAAALAADCggICAAAAA==.',Pu='Puritan:BAAALAADCgcIBwAAAA==.',Ra='Razum:BAACLAAFFIEHAAMZAAQInw82DQD4AAAZAAMIsRM2DQD4AAAbAAII3QgLGgCHAAAsAAQKgTEAAxkACAjzI0kGAC4DABkACAjzI0kGAC4DABsABwgOIA0bAHcCAAAA.',Ro='Roadblock:BAAALAAECgYICwAAAA==.Roadglock:BAAALAAECgYICgAAAA==.Roadlock:BAAALAAECgYIDwAAAA==.Rora:BAAALAAECgYIDgAAAA==.Rotandroll:BAAALAADCgYICgAAAA==.Rouqe:BAAALAADCgYICAAAAA==.',Sa='Saltyalte:BAACLAAFFIEOAAIRAAUIux0RBQDkAQARAAUIux0RBQDkAQAsAAQKgSgAAhEACAglJQIHAEsDABEACAglJQIHAEsDAAAA.Sarelia:BAAALAAECgYIDQAAAA==.',Sc='Schorie:BAABLAAECoEgAAQTAAgI8BkXQwD2AQATAAYItxoXQwD2AQAQAAYIKA27TAAQAQAcAAEIFBYAAAAAAAAAAA==.Scorti:BAAALAAECggIEwAAAA==.',Sh='Shadowatcher:BAAALAAECggIEgAAAA==.Shadowfriend:BAAALAAECgMIAwAAAA==.Shamanwill:BAAALAADCggIDAAAAA==.Shocktherapy:BAAALAADCgYIBwAAAA==.Shoktowar:BAAALAADCgcICQAAAA==.',Si='Sick:BAAALAAECggICAABLAAFFAIIAgAJAAAAAA==.',Sk='Skurk:BAAALAAFFAIIAgAAAA==.',Sl='Slammy:BAAALAAECggIDAAAAA==.Slimshadey:BAAALAADCggIBgAAAA==.',Sn='Snappi:BAAALAAECgYIBgAAAA==.',Sp='Spacedpr:BAACLAAFFIEFAAIZAAIIqhXXGACnAAAZAAIIqhXXGACnAAAsAAQKgS8AAxkACAivGzoaAH0CABkACAivGzoaAH0CABsAAgjcAnuEADwAAAAA.',St='Stormz:BAAALAADCgcIBwAAAA==.',Su='Surfacing:BAAALAAECggIBwAAAA==.',Sw='Sweetmommy:BAAALAAECgcIBwAAAA==.Swirples:BAAALAADCgcIBwAAAA==.',['Sü']='Sütas:BAAALAADCgYIBQABLAAECgYICwAJAAAAAA==.',Ta='Tagashi:BAAALAAECgQIBAABLAAECggILAAGAFIfAA==.Taurd:BAABLAAECoEbAAIaAAcIlhITdQCIAQAaAAcIlhITdQCIAQAAAA==.',Te='Tealq:BAAALAAECgIIAgAAAA==.Teddypally:BAAALAAECgIIAgAAAA==.Tekx:BAAALAADCgMIBAAAAA==.Terrazul:BAACLAAFFIEFAAIRAAIIJxevFgCnAAARAAIIJxevFgCnAAAsAAQKgSAAAhEACAhNHu8XALgCABEACAhNHu8XALgCAAEsAAQKCAglABoAFiIA.Teruhashi:BAABLAAECoESAAMLAAgIBBiQOgAOAgALAAgIohSQOgAOAgAMAAUImBXFFABmAQAAAA==.',Th='Tharkan:BAAALAADCgYIBgABLAAECgYIFAACAKgdAA==.Thayoli:BAABLAAECoEVAAISAAgIihctLQAzAgASAAgIihctLQAzAgAAAA==.',To='Tomba:BAAALAADCgYIBgAAAA==.',Tr='Tremortoe:BAAALAADCgIIAgAAAA==.Trey:BAAALAAECgYIDQAAAA==.',Tu='Tuborg:BAAALAADCgcIFAAAAA==.',Ty='Tyrull:BAAALAAECggICwABLAAFFAYICgADANAaAA==.',Ur='Urbabydaddy:BAAALAADCggICAAAAA==.',Va='Valennia:BAAALAAECgcIDQABLAAECggIHgABABsaAA==.Valorie:BAAALAAECgEIAQABLAAECggIHgABABsaAA==.',Ve='Velena:BAAALAADCggICgAAAA==.Vereena:BAAALAADCggIGAAAAA==.',Vo='Voidelf:BAACLAAFFIEGAAIdAAIIYxFoDACRAAAdAAIIYxFoDACRAAAsAAQKgSsAAh0ACAiMHxsKANgCAB0ACAiMHxsKANgCAAAA.Voleth:BAAALAAECgYIBgABLAAECggIEAAJAAAAAA==.',Vr='Vrox:BAAALAAECggICAAAAA==.',Wa='Wardancer:BAABLAAECoEXAAIYAAgIeyFlCwC9AgAYAAgIeyFlCwC9AgAAAA==.',We='Weiwa:BAABLAAECoEjAAMWAAgI5xfBBwALAgAWAAcIyRjBBwALAgAZAAEIuRFqnQA7AAAAAA==.Wendymarvell:BAAALAADCgMIAwAAAA==.',Wh='Whaat:BAAALAAECgYIDAAAAA==.Whoon:BAAALAAECgIIAgABLAAECgMIAwAJAAAAAA==.',Ye='Yehh:BAAALAAECgYIDAAAAA==.',Za='Zayron:BAAALAADCggICAAAAA==.',Zi='Zilfion:BAACLAAFFIEPAAIYAAUI9BsYAgDUAQAYAAUI9BsYAgDUAQAsAAQKgS0AAhgACAhDJRECAGUDABgACAhDJRECAGUDAAAA.',Zu='Zulda:BAAALAADCgQIBAAAAA==.',['Ði']='Ðiane:BAAALAADCgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end