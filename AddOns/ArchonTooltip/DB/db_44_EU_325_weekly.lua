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
 local lookup = {'Paladin-Holy','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Shaman-Enhancement','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','DeathKnight-Frost','DeathKnight-Unholy','DeathKnight-Blood','Priest-Holy','Druid-Restoration','Warlock-Destruction','Rogue-Assassination','Monk-Mistweaver','Paladin-Protection','Paladin-Retribution','Druid-Balance','Rogue-Subtlety',}; local provider = {region='EU',realm='ScarshieldLegion',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adey:BAAALAADCggICAAAAA==.',Ae='Aerim:BAABLAAECoEeAAIBAAgIIhtSBwCOAgABAAgIIhtSBwCOAgAAAA==.',Al='Allecto:BAAALAAECgMIBAAAAA==.Allexsis:BAAALAADCggIEAAAAA==.',An='Anemona:BAABLAAECoEZAAICAAYIxxL4FABsAQACAAYIxxL4FABsAQAAAA==.Anjin:BAABLAAECoEYAAMDAAcI7CRDCgD0AgADAAcI7CRDCgD0AgAEAAEIowdxcQAyAAAAAA==.Anthro:BAAALAAECgcIBwAAAQ==.',Ar='Arynth:BAABLAAECoEXAAIFAAcI2B+bHwBpAgAFAAcI2B+bHwBpAgAAAA==.',Av='Aven:BAAALAAECgcIDwAAAA==.',Ay='Aym:BAABLAAECoEYAAMGAAcI7iBdBACLAgAGAAcI7iBdBACLAgAHAAEIOhfLoQBFAAAAAA==.',Ba='Bathsheba:BAAALAADCgcIBwAAAA==.',Be='Belfer:BAAALAAECgMIAwABLAAECgcICgAIAAAAAA==.Berdrin:BAAALAADCggIFAAAAA==.',Bj='Bjorc:BAAALAADCgYIBgAAAA==.',Cd='Cdeeznutzs:BAAALAADCggICAAAAA==.',Ce='Cevry:BAABLAAECoEVAAMJAAYI2BWIIACSAQAJAAYI2BWIIACSAQAKAAIIQBddHgB+AAAAAA==.',Ch='Cherrith:BAAALAAECgUICgAAAA==.Cheryl:BAAALAAECgMICgAAAA==.',Ci='Ciasteczko:BAAALAAECgIIAgAAAA==.',Cl='Clarrissaa:BAAALAADCgUIBQAAAA==.',Co='Cocôn:BAAALAAFFAIIAwAAAA==.Comets:BAAALAAECgcICAAAAA==.',['Có']='Cócón:BAAALAAFFAIIAgABLAAFFAIIAwAIAAAAAA==.',De='Deathbob:BAABLAAECoEYAAMLAAcIyB7LIgBaAgALAAcIyB7LIgBaAgAMAAIIHg3zMwCJAAAAAA==.Delendra:BAAALAAECgMIAwAAAA==.',Do='Dougertron:BAAALAAECgYICwAAAA==.',Du='Duppy:BAAALAADCgcIBwAAAA==.',Ei='Eightbit:BAAALAAECgMIBQAAAA==.',Eo='Eonamir:BAAALAAECgcICAAAAA==.',Er='Erahdic:BAAALAAECggICwAAAA==.',Et='Ethereals:BAAALAAECgMIAwAAAA==.',Fa='Fappy:BAAALAADCgEIAQABLAAECggIFQADAOkaAA==.',Fo='Fotonio:BAAALAAECgYIDAAAAA==.',Fr='Frostedbark:BAAALAAECgYIBgAAAA==.',Fu='Furox:BAAALAAECgMIBAAAAA==.',Ga='Garlath:BAAALAAECgcIDQAAAA==.',Go='Gobbo:BAAALAAECgYICQAAAA==.',Gu='Gunbarrel:BAAALAADCggICQAAAA==.',Ha='Hades:BAABLAAECoEeAAMLAAgIliDCFAC2AgALAAgIliDCFAC2AgANAAgIRQ3XDgClAQAAAA==.',He='Hellcry:BAAALAADCggICAAAAA==.Hellspring:BAAALAADCgcIBwAAAA==.Hevaroth:BAAALAADCgEIAQAAAA==.',Hi='Hibeam:BAAALAADCgcICQAAAA==.Hiilimakkara:BAABLAAECoEYAAIOAAcI7SMgCQDWAgAOAAcI7SMgCQDWAgAAAA==.',Ho='Hobogoblin:BAAALAADCggIFQAAAA==.Hokuspokus:BAAALAAECggICQAAAA==.',Hu='Huaktuah:BAAALAAECgIIAgABLAAECgMIAQAIAAAAAA==.',Im='Imconfused:BAAALAAECggICAAAAA==.',Is='Isellgold:BAAALAAECgIIAgAAAA==.',Je='Jealousy:BAABLAAECoEYAAIHAAcIFB7pFQBRAgAHAAcIFB7pFQBRAgAAAA==.',Ji='Jilian:BAAALAAECgcICQAAAA==.',Jo='Joukahainen:BAABLAAECoEUAAMPAAcIkCQFBwDIAgAPAAcIkCQFBwDIAgACAAUIcRjgEQCaAQAAAA==.',['Já']='Jáde:BAAALAAECgYICwAAAA==.',Ka='Kaelarak:BAAALAADCgcIBwAAAA==.Kageshisai:BAAALAAECgYIDAAAAA==.Kale:BAAALAAECgIIAgAAAA==.Kalopsia:BAAALAAECgYIBwAAAA==.Kaper:BAAALAAECgMIBQAAAA==.',Ke='Keg:BAAALAAECgYIBgABLAAECgcIGAAGAO4gAA==.Keystonebrew:BAAALAAECgUIBQAAAA==.',Ku='Kuu:BAAALAADCggIFAAAAA==.',Ky='Kynai:BAAALAADCggICQAAAA==.',La='Lanalier:BAABLAAECoERAAIQAAYI4RFbPwB4AQAQAAYI4RFbPwB4AQAAAA==.Lariadel:BAAALAAECgIIAgAAAA==.',Le='Leipä:BAAALAAECgYIDQAAAA==.Leona:BAAALAAECgYIDAAAAA==.Lexir:BAAALAADCggICAAAAA==.',Li='Lianlu:BAAALAAECgcIEgAAAA==.Lightup:BAAALAAECgMIAwAAAA==.',Lo='Lockrock:BAAALAAECgMIBQAAAA==.',Lu='Lusacan:BAAALAADCgMIAwAAAA==.',Ly='Lyan:BAAALAAECgYIDAAAAA==.',Ma='Madmax:BAAALAADCggIEQAAAA==.Maltheron:BAAALAAECgMIAwAAAA==.',Me='Melandra:BAAALAADCgUIBwAAAQ==.',Mi='Mightyjugs:BAAALAADCggICAAAAA==.',Mo='Moczi:BAAALAAFFAIIAwAAAA==.Moonie:BAAALAADCgIIAgAAAA==.Morana:BAAALAAECgYICAAAAA==.Mouses:BAAALAADCggIHAAAAA==.',Mu='Munchies:BAAALAAECgcIEQAAAA==.',My='Myrra:BAAALAAECgYIDgAAAA==.Mythadon:BAABLAAECoEXAAIRAAcIdR8dDQCHAgARAAcIdR8dDQCHAgAAAA==.',Na='Naruto:BAAALAADCggIEgAAAA==.Nauris:BAAALAADCggICAAAAA==.',Ne='Nelfer:BAAALAAECgcICgAAAA==.Nemesis:BAAALAAECgEIAQAAAA==.',['Ní']='Níbble:BAAALAAECgcIDQAAAA==.',Om='Omashi:BAAALAAECgYIDgAAAA==.',Or='Oreo:BAAALAADCggICAAAAA==.',Pa='Pabby:BAABLAAECoEVAAIDAAgI6Rq8FACHAgADAAgI6Rq8FACHAgAAAA==.Pawnstar:BAAALAADCgYIBgAAAA==.',Po='Poutsaras:BAAALAAECgEIAQAAAA==.',Qu='Quendria:BAAALAAECgcIDgAAAA==.Quintessa:BAAALAAECgYIEAAAAA==.Quintillus:BAAALAADCggICAAAAA==.',Ra='Raizel:BAAALAADCgEIAQAAAA==.Ratboy:BAAALAAECgIIAwAAAA==.',Rh='Rhaella:BAAALAAECgYIEAAAAA==.Rharmonar:BAAALAADCgcIBwAAAA==.',Ro='Rosuku:BAAALAAECgMIAwAAAA==.',Ry='Ryppy:BAABLAAECoEXAAIOAAcIiwxzNQB8AQAOAAcIiwxzNQB8AQAAAA==.',Sa='Saintbarrel:BAAALAADCggICQAAAA==.Saltbarrel:BAABLAAECoEXAAISAAcIBQ64GABbAQASAAcIBQ64GABbAQAAAA==.',Se='Selvec:BAABLAAECoEeAAMTAAgI9xzyCQBDAgATAAgI7RzyCQBDAgAUAAUIkQ1BgQAIAQAAAA==.',Sh='Shadock:BAAALAAECgYIDQAAAQ==.',Si='Silvercross:BAAALAAECgQICgAAAA==.',Sl='Slayerozzie:BAABLAAECoEZAAIVAAgIxxBYGgAGAgAVAAgIxxBYGgAGAgAAAA==.',St='Steelbarrel:BAAALAADCggICAAAAA==.',Su='Sus:BAACLAAFFIEMAAMRAAUIgxYzAQCGAQARAAQILBczAQCGAQAWAAIIOQ+SBAChAAAsAAQKgSAAAxYACAiTIbwEAI0CABEACAgRGW0LAJ8CABYACAhZH7wEAI0CAAAA.',Ta='Tallion:BAAALAADCggICAAAAA==.Talotaikuri:BAAALAADCgYIBgAAAA==.Tammenterho:BAAALAAECgYICgAAAA==.Taslamp:BAAALAAECgMIAQAAAA==.',Te='Teflur:BAAALAADCgYIBgAAAA==.',To='Tomjin:BAAALAADCgIIAgAAAA==.',Tr='Trashia:BAAALAAECgIIBAAAAA==.Trorin:BAAALAAECgMIBQAAAA==.',Ty='Tyrannia:BAAALAAECgYICQAAAA==.',Wa='Waykingo:BAAALAAECgYIDQAAAA==.',We='Weeb:BAAALAAECgEIAQABLAAFFAUIDAARAIMWAA==.',Wi='Windfury:BAAALAADCggIEAABLAAECggIHgALAJYgAA==.',Xu='Xuffie:BAAALAADCgYIBgAAAA==.',Yi='Yin:BAABLAAECoEYAAIDAAcIFBj7IgAaAgADAAcIFBj7IgAaAgAAAA==.',Yo='Yorii:BAAALAAECgYIBgAAAA==.',Yu='Yuffie:BAAALAADCgYIBgAAAA==.',Za='Zabulon:BAAALAAECgYIDAAAAA==.Zaggius:BAAALAAECgUICAAAAA==.Zakali:BAAALAAECgcIEwAAAA==.Zakdoek:BAAALAAECgYICwAAAA==.',Ze='Zellíe:BAABLAAECoEWAAIDAAcIcgb1UABHAQADAAcIcgb1UABHAQAAAA==.Zengar:BAAALAADCggIFAAAAA==.',['Äl']='Äleris:BAAALAADCgYICAABLAAECgYIDgAIAAAAAA==.',['Èg']='Ègil:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end