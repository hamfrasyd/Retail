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
 local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-BeastMastery','Priest-Shadow','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Shaman-Enhancement','Paladin-Holy','DeathKnight-Unholy','Druid-Guardian','Hunter-Marksmanship','Druid-Restoration','Priest-Holy',}; local provider = {region='EU',realm='Mazrigos',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aattrox:BAABLAAECoEUAAMBAAYIMBXlTwCKAQABAAYI6xPlTwCKAQACAAIIDRlGKwCTAAAAAA==.',Ak='Akane:BAAALAAECgYIDgAAAA==.',Al='Alsarath:BAAALAAECgIIAwAAAA==.',An='Angelluss:BAACLAAFFIEGAAIDAAIIxBhpCwCjAAADAAIIxBhpCwCjAAAsAAQKgRYAAgMACAgfGy4TAJYCAAMACAgfGy4TAJYCAAAA.Angrymuffin:BAAALAADCggIEAAAAA==.Annelise:BAAALAADCgMIAwAAAA==.',Ar='Arkadia:BAAALAADCgcIDAAAAA==.Arkaedus:BAAALAAECggIEQAAAA==.Arrivol:BAACLAAFFIEGAAIEAAIIyxY3CgCmAAAEAAIIyxY3CgCmAAAsAAQKgR4AAgQACAhxIuMGABQDAAQACAhxIuMGABQDAAAA.',As='Astoxidis:BAAALAAECgYICQAAAA==.',At='Atreu:BAAALAADCgYIDQAAAA==.',Av='Avrem:BAAALAADCgQICAAAAA==.',Az='Azaliya:BAAALAAECgMIAwAAAA==.Aziray:BAAALAAECgYICQAAAA==.Azniren:BAAALAADCgIIAgAAAA==.Azzimage:BAAALAAECgUIDAAAAA==.',Ba='Backstabs:BAAALAADCgcIBwAAAA==.',Bu='Burritos:BAAALAADCgYIBgAAAA==.',['Bæ']='Bædønthurtmë:BAAALAADCgcIDgAAAA==.',Ca='Capensis:BAAALAADCggIEQABLAAECgYIEwAFAAAAAA==.Carthego:BAAALAADCggIDwAAAA==.Caseille:BAAALAADCgYIBgAAAA==.Cayles:BAAALAAECgIIAgAAAA==.',Cb='Cballs:BAABLAAECoEdAAQGAAgIHSQXDQDZAgAGAAcIOSQXDQDZAgAHAAYIVh3kGADLAQAIAAEI5Az0LQBKAAAAAA==.',Ce='Ceire:BAAALAAECgEIAQAAAA==.Cerulrath:BAAALAADCggICAABLAAFFAIIBgAEAMsWAA==.',Ch='Chilla:BAAALAAECgcIDgAAAA==.Choppaninyo:BAAALAADCgEIAQAAAA==.',Co='Corukh:BAAALAADCggICAABLAAECgcIDgAFAAAAAA==.',Cr='Cruz:BAAALAADCggICAAAAA==.',Ct='Cthullu:BAAALAAECgEIAQABLAAECgYIDwAFAAAAAA==.',Da='Daria:BAAALAAECgMIBAAAAA==.Darlíng:BAAALAAECgUICAAAAA==.Darow:BAAALAADCgYIFAAAAA==.',De='Dealylama:BAAALAAECgIIAgAAAA==.Devinecow:BAAALAAECgMIAwAAAA==.',Do='Dolarel:BAAALAADCgcIBwAAAA==.',Dr='Dracaris:BAACLAAFFIEFAAIJAAIItBQHCgCjAAAJAAIItBQHCgCjAAAsAAQKgRUAAwkACAg4GY0SADQCAAkACAg4GY0SADQCAAoAAwihA2QfAG4AAAEsAAUUAggGAAMAxBgA.Dreamie:BAAALAADCggIEAAAAA==.Drêåd:BAAALAAECgYIDAAAAA==.',Du='Durwin:BAAALAADCgYICAAAAA==.',Eb='Ebenezergood:BAAALAADCggICAABLAAECgIIAgAFAAAAAA==.',Ed='Ednarix:BAAALAAECgYIDQAAAA==.',Eh='Ehunterharry:BAAALAADCgUIBQAAAA==.',El='Elivia:BAABLAAECoEVAAILAAcI5xeYCAD5AQALAAcI5xeYCAD5AQAAAA==.Elmroot:BAAALAADCgMIAwAAAA==.',En='Endeavor:BAABLAAECoEVAAIMAAYI9Qe2KwARAQAMAAYI9Qe2KwARAQAAAA==.',Ew='Ewilyn:BAAALAAECgYIBgABLAAFFAIIBgADAMQYAA==.',Fa='Faerill:BAAALAAECgMIBAAAAA==.Faiythe:BAAALAADCgcIBwAAAA==.',Fe='Felbíte:BAAALAAECgUIBQAAAA==.Feral:BAAALAADCgIIAgAAAA==.',Ga='Gabinka:BAAALAADCgcIBwAAAA==.',Ge='Gengir:BAAALAAECgYIDAAAAA==.',Gi='Gibbs:BAAALAAECgQIBwAAAA==.',Gr='Grromash:BAAALAADCgIIAgAAAA==.',Ha='Hagbard:BAAALAAECgIIBAAAAA==.Haryi:BAAALAAECgUICAAAAA==.Hassedeathz:BAAALAADCgIIAgAAAA==.Hawkblade:BAABLAAECoEXAAINAAgI8yV/AAB1AwANAAgI8yV/AAB1AwAAAA==.',He='Hellios:BAAALAADCgEIAQAAAA==.',Hi='Hitmonjam:BAAALAAECgYICQAAAA==.',Ho='Holyazzi:BAAALAADCggICAAAAA==.Holysheeyt:BAAALAAECgIIAgAAAA==.',Hu='Hubavelka:BAAALAAECgUIBgAAAA==.',['Hä']='Hästpräst:BAAALAAECgQIBAAAAA==.',Ia='Iamdruid:BAAALAAECgEIAQAAAA==.',Il='Illirage:BAAALAADCgUIBQAAAA==.',Io='Iol:BAAALAAECgIIAgAAAA==.',Je='Jesster:BAAALAADCggIDwAAAA==.',Jo='Johnsmith:BAAALAAECgMIBAAAAA==.Jorgoman:BAAALAADCgMIAwAAAA==.',Ka='Kaela:BAAALAAECgQIBAAAAA==.Kagome:BAAALAADCggICAAAAA==.Kaiyra:BAAALAADCgUIBQAAAA==.',Kh='Khabecim:BAAALAADCggIFwAAAA==.',Ki='Killerweasel:BAAALAAECgMIBgABLAAECgIIAgAFAAAAAA==.Kinara:BAAALAAECgYIBgABLAAECgYIDAAFAAAAAA==.Kiyomi:BAAALAAECgUICQAAAA==.',Ko='Komarcek:BAAALAAECgQIBAAAAA==.',Kr='Krexx:BAAALAAECggICQABLAAECggIEwAFAAAAAA==.',La='Lapun:BAAALAAECgYIEwAAAA==.',Le='Leonardo:BAAALAAECgQIAQAAAA==.Leporidae:BAAALAADCggIDAABLAAECgYIEwAFAAAAAA==.',Li='Lidrin:BAAALAAECgIIAgAAAA==.Littlebige:BAAALAADCggIBwAAAA==.',Lu='Lukadh:BAAALAAECggIDgAAAA==.',Ma='Maddicuss:BAAALAADCgEIAQAAAA==.Mahemi:BAAALAAECgIIAgAAAA==.Marmelladin:BAAALAAECgQIBgAAAA==.Marmellin:BAAALAAECgIIAgABLAAECgQIBgAFAAAAAA==.Massblast:BAAALAAECgIIAgAAAA==.Mayuri:BAAALAAECgYIBwAAAA==.',Me='Meh:BAAALAADCgYIEAAAAA==.Mercus:BAAALAAECgQIBAAAAA==.Merendis:BAAALAADCggICAAAAA==.',Mi='Minothauri:BAAALAADCgEIAQAAAA==.',Mo='Monkeyhealer:BAAALAADCggIFQAAAA==.Moongoddess:BAAALAADCgYIBgAAAA==.',Mu='Munnu:BAAALAAECgIIAgAAAA==.',Na='Nagini:BAAALAAECgUIDAAAAA==.Nahlind:BAAALAADCggICAAAAA==.',Ne='Neeya:BAAALAADCgUIBQAAAA==.Nemetsk:BAACLAAFFIEFAAMHAAIIlg49FABPAAAGAAEIwxGbHQBQAAAHAAEIaQs9FABPAAAsAAQKgRYAAwYACAjZF4EeADoCAAYACAipFoEeADoCAAcABwgJESMZAMkBAAEsAAUUAggGAAQAyxYA.',Nr='Nrala:BAABLAAECoEWAAIDAAcIvQ1qPgCQAQADAAcIvQ1qPgCQAQAAAA==.',Nu='Nubbski:BAAALAAECgMIAwAAAA==.Nushina:BAAALAAECgMICAAAAA==.',Ob='Obasen:BAAALAAECgIIAgAAAA==.',Ol='Olimpija:BAAALAADCgcIBwAAAA==.',Or='Orylag:BAAALAADCggICAAAAA==.',Pa='Patek:BAAALAAECggICAAAAA==.',Pe='Penguin:BAAALAADCgcIBwAAAA==.',Pi='Pim:BAAALAAECgcIEwAAAA==.Pimm:BAAALAADCgcIBwABLAAECgcIEwAFAAAAAA==.',Pr='Prothnus:BAABLAAECoEVAAIOAAYIgyTxAgB0AgAOAAYIgyTxAgB0AgAAAA==.',Ra='Ramash:BAAALAADCggIEAAAAA==.Ravenshadow:BAAALAAECgYIDAAAAA==.',Re='Realion:BAAALAADCggICAAAAA==.Redwynd:BAAALAAECgYIDQAAAA==.Resisto:BAAALAAECgMIBAAAAA==.',Rh='Rhika:BAAALAADCgIIAgAAAA==.',Ri='Ripped:BAAALAAFFAIIAgAAAA==.Ritual:BAAALAAECgEIAQAAAA==.',Ro='Rocksalt:BAAALAADCggIDwAAAA==.',['Rö']='Rölli:BAAALAADCggIDQAAAA==.',Sa='Salemcraft:BAAALAADCgEIAQAAAA==.Sayf:BAAALAADCgIIBAAAAA==.',Sc='Scai:BAAALAAECgYICgAAAA==.',Se='Sewwal:BAABLAAECoEVAAMDAAYIYwpzUgBBAQADAAYIYwpzUgBBAQAPAAMISAMuawBFAAAAAA==.',Sh='Shamanstyles:BAAALAAECgYIDwAAAA==.Shanai:BAAALAADCgcIBwAAAA==.Shindriell:BAAALAAECggIEwAAAA==.Shirai:BAAALAAECgYIEgABLAAECggIEwAFAAAAAA==.Shiso:BAAALAADCgcIBwAAAA==.Shuitu:BAAALAAECggIEAABLAAECggIEwAFAAAAAA==.',Sj='Sjukdom:BAAALAADCgYICAAAAA==.',Sk='Skelde:BAAALAADCggIDwABLAAECgcIGgAPAMISAA==.',St='Stiil:BAABLAAECoEWAAIQAAcIMRtCFQAqAgAQAAcIMRtCFQAqAgAAAA==.',Ta='Tacticus:BAABLAAECoEaAAIPAAcIwhK4JgCxAQAPAAcIwhK4JgCxAQAAAA==.Tahlut:BAAALAADCggICAAAAA==.',Te='Tessarion:BAAALAAECgYIDgAAAA==.',Th='Thekaypriest:BAABLAAECoEdAAIRAAgIRSCWCADcAgARAAgIRSCWCADcAgAAAA==.Thekayshaman:BAAALAADCggICAABLAAECggIHQARAEUgAA==.',To='Toive:BAAALAAECgIIAgAAAA==.Tossuman:BAAALAAECgIIAgAAAA==.Totemklarna:BAAALAADCggICAAAAA==.',Tr='Trap:BAAALAAECggIEAAAAA==.',Ts='Tsukimusha:BAAALAADCggIGwAAAA==.Tsún:BAAALAAECgEIAQAAAA==.Tsúnzu:BAAALAAECgIIAgAAAA==.',Va='Varthyr:BAAALAADCgcIBwAAAA==.',Ve='Velynar:BAAALAAECgYIDQAAAA==.Veridis:BAAALAADCggIDwAAAA==.Vesanus:BAAALAADCgUIBgAAAA==.',Vu='Vulzalh:BAAALAADCgYICQAAAA==.',Wa='Warweasel:BAAALAAECgIIAgAAAA==.',Xe='Xeal:BAABLAAECoEXAAMGAAgIoSNoBgAmAwAGAAgIoSNoBgAmAwAIAAIIMwgmJwBpAAAAAA==.Xelyth:BAAALAAECgYICgAAAA==.Xerphos:BAAALAADCgEIAgAAAA==.',Ya='Yamihime:BAAALAADCggICAAAAA==.',['Yö']='Yöruichi:BAAALAADCgUIBwAAAA==.',Za='Zandhal:BAAALAAECgMIAwAAAA==.Zayn:BAAALAAECgEIAgAAAA==.',Ze='Zefer:BAAALAAECgYIDgAAAA==.',Zi='Zirriath:BAAALAADCgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end