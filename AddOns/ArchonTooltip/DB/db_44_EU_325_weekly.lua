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
 local lookup = {'Paladin-Holy','Druid-Feral','Hunter-BeastMastery','Hunter-Marksmanship','Mage-Arcane','Rogue-Assassination','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','Mage-Frost','Warlock-Demonology','Warlock-Destruction','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Retribution','DeathKnight-Blood','Priest-Holy','Rogue-Subtlety','Druid-Restoration','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','Rogue-Outlaw','Priest-Discipline','Priest-Shadow','Mage-Fire','Paladin-Protection','Druid-Balance',}; local provider = {region='EU',realm='ScarshieldLegion',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ad='Adey:BAAALAADCggICAAAAA==.',Ae='Aerim:BAACLAAFFIEJAAIBAAQIBh8KBQB3AQABAAQIBh8KBQB3AQAsAAQKgR4AAgEACAgiG6kOAHsCAAEACAgiG6kOAHsCAAAA.',Ak='Akuji:BAAALAAECgcIEQAAAA==.',Al='Allecto:BAAALAAECgMIBAAAAA==.Allexsis:BAAALAADCggIFQAAAA==.',An='Anemona:BAABLAAECoEhAAICAAYIQSFjDgA7AgACAAYIQSFjDgA7AgAAAA==.Anjin:BAABLAAECoEpAAMDAAgILCYoAgB1AwADAAgILCYoAgB1AwAEAAEIowdnrQAuAAAAAA==.Anthro:BAAALAAFFAEIAQAAAQ==.',Ar='Arynth:BAABLAAECoElAAIFAAgIwR9mFwDmAgAFAAgIwR9mFwDmAgAAAA==.',As='Asa:BAAALAADCggIDwAAAA==.',Av='Aven:BAABLAAECoEXAAIGAAgI8g/yKADBAQAGAAgI8g/yKADBAQAAAA==.',Ay='Aym:BAABLAAECoEoAAQHAAgICiL3AgD+AgAHAAgICiL3AgD+AgAIAAMIcBzudwD/AAAJAAEIOhcq+wBEAAAAAA==.',Ba='Bathsheba:BAAALAADCgUIAgAAAA==.',Be='Belfer:BAAALAAECgMIAwABLAAECggIDAAKAAAAAA==.Berdrin:BAAALAADCggIFAAAAA==.',Bj='Bjorc:BAAALAADCggICAAAAA==.',Bl='Blux:BAAALAAECggIDgAAAA==.',Bo='Boblock:BAAALAAECgYIBgAAAA==.',Cd='Cdeeznutzs:BAAALAADCggICAAAAA==.',Ce='Cevry:BAABLAAECoEVAAMLAAYI2BWJMQBzAQALAAYI2BWJMQBzAQAMAAIIQBcSLwB8AAAAAA==.',Ch='Cheeb:BAAALAAECgYIBgAAAA==.Cherrith:BAAALAAECgUICgAAAA==.Cheryl:BAABLAAECoEYAAMFAAcIVRTCWgDNAQAFAAcI9RLCWgDNAQANAAMImxVjXACzAAAAAA==.',Ci='Ciasteczko:BAAALAAECgUICwAAAA==.',Cl='Clarrissaa:BAAALAADCgUIBQAAAA==.',Co='Cocôn:BAACLAAFFIEFAAILAAIIdhb8EACcAAALAAIIdhb8EACcAAAsAAQKgRQAAgsABwgiHhsXAE8CAAsABwgiHhsXAE8CAAEsAAUUAggGAA4AnBoA.Comets:BAAALAAECgcICAAAAA==.Cotedor:BAAALAAECgEIAQAAAA==.',['Có']='Cócón:BAABLAAFFIEGAAMOAAIInBrnDQChAAAOAAIIvBPnDQChAAAPAAEIJx9eOwBTAAAAAA==.',De='Deathbob:BAABLAAECoEpAAMQAAgIdyN3CQBFAwAQAAgIdyN3CQBFAwARAAMInxHcOQDVAAAAAA==.Delendra:BAAALAAFFAEIAQAAAA==.',Do='Dougertron:BAABLAAECoEeAAIEAAgItRRSKgAHAgAEAAgItRRSKgAHAgAAAA==.',Dr='Drosus:BAAALAAECgYIBgAAAA==.',Du='Duppy:BAAALAADCgcIBwAAAA==.',Ei='Eightbit:BAAALAAECgcIEgAAAA==.',El='Elendra:BAAALAAECgYIBgABLAAFFAEIAQAKAAAAAA==.',Eo='Eonamir:BAAALAAECggIDQAAAA==.',Er='Erahdic:BAABLAAECoEVAAISAAgIXx8VJAC4AgASAAgIXx8VJAC4AgAAAA==.',Et='Ethereals:BAAALAAECgMIAwAAAA==.',Fa='Fappy:BAAALAADCgEIAQABLAAECggIIwADAB4dAA==.',Fe='Fern:BAAALAAECgEIAQABLAAECgUIDAAKAAAAAA==.',Fi='Fitzwaldo:BAAALAAECggICgAAAA==.',Fo='Fotonio:BAABLAAECoEYAAIEAAYIARtJMgDZAQAEAAYIARtJMgDZAQAAAA==.',Fr='Frostedbark:BAAALAAECgYIBgAAAA==.',Fu='Furox:BAAALAAECgcIDgAAAA==.',Ga='Garlath:BAAALAAECgcIDgAAAA==.',Gl='Glaive:BAAALAAECgcICwAAAA==.',Go='Gobbo:BAAALAAFFAIIAgAAAA==.Gokorosh:BAAALAAECgYIBgAAAA==.Gorrish:BAAALAAECgYIBgAAAA==.',Gu='Gunbarrel:BAAALAAECgYIBgAAAA==.',Ha='Hades:BAACLAAFFIEHAAIQAAMIxRnWEAAYAQAQAAMIxRnWEAAYAQAsAAQKgS4AAxAACAhSITYeANUCABAACAhSITYeANUCABMACAg8FoEPABoCAAAA.',He='Hellcry:BAAALAADCggIFwAAAA==.Hellspring:BAAALAADCgcIBwAAAA==.Hevaroth:BAAALAADCgEIAQAAAA==.',Hi='Hibeam:BAAALAADCgcICQAAAA==.Hiilimakkara:BAABLAAECoEgAAIUAAgIZCR7BABDAwAUAAgIZCR7BABDAwAAAA==.',Ho='Hobogoblin:BAAALAAECgYIDAAAAA==.Hokuspokus:BAABLAAECoEYAAINAAgIPA0xLgCaAQANAAgIPA0xLgCaAQAAAA==.',Hu='Huaktuah:BAAALAAECgcIEAAAAA==.',Im='Imconfused:BAAALAAECggIDAAAAA==.',Is='Isellgold:BAAALAAECgUIBQABLAAFFAYIFwAVAMMYAA==.',Ja='Jack:BAAALAADCgUIBQABLAAECggIKQAVAIsdAA==.',Je='Jealousy:BAABLAAECoEpAAMJAAgIzxxLHgB2AgAJAAgIzxxLHgB2AgAIAAUIVggneAD+AAAAAA==.',Ji='Jilian:BAABLAAECoEYAAIWAAgIGAaHaAARAQAWAAgIGAaHaAARAQAAAA==.',Jo='Joukahainen:BAABLAAECoEWAAMWAAgI5yIXCQD2AgAWAAgI5yIXCQD2AgACAAUIcRhOHgB0AQAAAA==.',['Já']='Jáde:BAAALAAECgYIEQAAAA==.',Ka='Kaelarak:BAAALAADCgcIBwAAAA==.Kageshisai:BAAALAAECgYIDAAAAA==.Kale:BAAALAAECggIDQAAAA==.Kalopsia:BAABLAAECoEVAAIHAAYIfBhsEACwAQAHAAYIfBhsEACwAQAAAA==.Kaper:BAABLAAECoERAAIHAAcIsiETBQC3AgAHAAcIsiETBQC3AgAAAA==.',Ke='Keg:BAABLAAECoEUAAMXAAcILh7YDQBbAgAXAAcILh7YDQBbAgAYAAIIkRRUSACMAAABLAAECggIKAAHAAoiAA==.Keystonebrew:BAAALAAECgUIBQAAAA==.',Ku='Kuu:BAAALAADCggIFAAAAA==.',Ky='Kynai:BAAALAADCggIGQAAAA==.',La='Lanalier:BAABLAAECoEcAAIPAAcIvhKvVAC3AQAPAAcIvhKvVAC3AQAAAA==.Lariadel:BAAALAAECgMIBQAAAA==.',Le='Leipä:BAAALAAECgYIDQAAAA==.Leipäpala:BAAALAADCggICAAAAA==.Leona:BAAALAAECgYIDAAAAA==.Lexir:BAAALAADCggICAAAAA==.Lexpala:BAAALAADCgcIBwABLAAECgQICgAKAAAAAA==.',Li='Lianlu:BAABLAAECoEeAAIZAAgIyCRaAgBIAwAZAAgIyCRaAgBIAwAAAA==.Liavia:BAAALAAECggICQABLAAFFAYIDQAPAJoaAA==.Lightup:BAAALAAECgUIBwAAAA==.',Lo='Lockrock:BAAALAAECgcIDAAAAA==.',Lu='Lumaelys:BAAALAAECgcICgAAAA==.Lusacan:BAAALAADCggIDgAAAA==.',Ly='Lyan:BAABLAAECoEaAAIWAAcIrhW4OAC/AQAWAAcIrhW4OAC/AQAAAA==.',Ma='Madmax:BAAALAADCggIEwAAAA==.Maltheron:BAAALAAECgMIAwAAAA==.',Me='Melandra:BAAALAADCgUIBwAAAQ==.',Mi='Mightyjugs:BAAALAADCggICAAAAA==.',Mo='Moczi:BAACLAAFFIEHAAIFAAII/xKNLgCbAAAFAAII/xKNLgCbAAAsAAQKgSMAAgUACAimHEMkAKICAAUACAimHEMkAKICAAAA.Moczineo:BAAALAAECgYIBgAAAA==.Moonie:BAAALAADCgIIAgABLAADCgUIBQAKAAAAAA==.Morana:BAABLAAECoEYAAIQAAgIPw1EdgDOAQAQAAgIPw1EdgDOAQAAAA==.Mouses:BAAALAADCggIKQAAAA==.',Mu='Munchies:BAABLAAECoEgAAIUAAgIdx+6DwDRAgAUAAgIdx+6DwDRAgAAAA==.Munchíes:BAAALAADCgUIBQAAAA==.',My='Myrra:BAABLAAECoEeAAMVAAgIOyFEBAD8AgAVAAgIOyFEBAD8AgAaAAEIFgISHQATAAAAAA==.Mythadon:BAABLAAECoEhAAMGAAgI+x2+DQCuAgAGAAgIWh2+DQCuAgAaAAII+QpzFgB1AAAAAA==.',Na='Naruto:BAAALAAECgcIDgAAAA==.Nauris:BAAALAADCggICAAAAA==.',Ne='Nelfer:BAAALAAECggIDAAAAA==.Nemesis:BAAALAAECgEIAQAAAA==.',No='Nocticula:BAAALAAECgEIAQAAAA==.',Nu='Nuan:BAAALAAECgMIBAAAAA==.Nuggets:BAAALAADCgcIBwAAAA==.',['Ní']='Níbble:BAAALAAECgcIEwAAAA==.',Om='Omashi:BAAALAAECgcIDwAAAA==.',Or='Oreo:BAAALAADCggICAAAAA==.',Pa='Pabby:BAABLAAECoEjAAIDAAgIHh0jKwBmAgADAAgIHh0jKwBmAgAAAA==.Pawnstar:BAAALAADCgYIBgAAAA==.',Pe='Petit:BAAALAADCgUIBQAAAA==.',Pi='Pickl:BAAALAADCgYIBgAAAA==.Pie:BAAALAAECgUIBQAAAA==.Pip:BAAALAAECgYIDQABLAAECggIKAAHAAoiAA==.',Po='Poutsaras:BAAALAAECgYIDQAAAA==.',Qu='Quendria:BAAALAAECggIDwAAAA==.Quintessa:BAABLAAECoEgAAQbAAgIHxUyDQCaAQAUAAgITBDPOgDFAQAbAAcIOREyDQCaAQAcAAQImApWaQDBAAAAAA==.Quintillus:BAAALAAECgYIBgAAAA==.',Ra='Raizel:BAAALAAECgYIDAAAAA==.Ratboy:BAAALAAECgIIAwAAAA==.',Rh='Rhaella:BAABLAAECoEXAAIdAAcIJxuIBAA3AgAdAAcIJxuIBAA3AgAAAA==.Rharmonar:BAAALAAFFAIIAgAAAA==.',Ro='Rosuku:BAAALAAECgMIAwAAAA==.',Ry='Ryppy:BAABLAAECoEoAAIUAAgI2BGcNwDUAQAUAAgI2BGcNwDUAQAAAA==.',Sa='Saintbarrel:BAAALAAECgEIAQAAAA==.Saltbarrel:BAABLAAECoEoAAIXAAgI7xCHGgCsAQAXAAgI7xCHGgCsAQAAAA==.',Se='Selvec:BAACLAAFFIEKAAIeAAMIABtkBAD6AAAeAAMIABtkBAD6AAAsAAQKgS8AAx4ACAgmI94DADEDAB4ACAgmI94DADEDABIABQiRDdPgAPQAAAAA.',Sh='Shadock:BAAALAAFFAIIAgAAAQ==.Shagdiva:BAAALAAECgEIAQAAAA==.',Si='Silvercross:BAABLAAECoEXAAIeAAcIRBP2JACNAQAeAAcIRBP2JACNAQAAAA==.',Sl='Slayerozzie:BAABLAAECoEjAAIfAAgIChZLIQAkAgAfAAgIChZLIQAkAgAAAA==.',So='Sorazero:BAAALAAECgYIBgABLAAECgYIFQALANgVAA==.',St='Star:BAAALAADCggICAAAAA==.Steelbarrel:BAAALAADCggIEAAAAA==.',Su='Sus:BAACLAAFFIEXAAMVAAYIwxg1AQAtAgAVAAYI/xY1AQAtAgAGAAQILBddBABkAQAsAAQKgSwAAxUACAjxI7YBAE0DABUACAjvI7YBAE0DAAYACAgRGUsSAHsCAAAA.',Ta='Taelia:BAAALAAECgEIAQAAAQ==.Tallion:BAAALAADCggICAAAAA==.Talotaikuri:BAAALAADCgYIBgAAAA==.Tammenterho:BAAALAAECgcIEQAAAA==.Tangó:BAAALAAECgcIBwAAAA==.Taslamp:BAAALAAECgMIAQABLAAECgcIEAAKAAAAAA==.',Te='Teflur:BAAALAADCgYIBgAAAA==.',Ti='Tiren:BAAALAADCggICAAAAA==.',To='Toad:BAAALAADCgcIBwABLAAECggIKAAHAAoiAA==.Tomjin:BAAALAADCgIIAgAAAA==.',Tr='Trashia:BAAALAAECgQIBwAAAA==.Trorin:BAABLAAECoEUAAIeAAcIcxgqGAD6AQAeAAcIcxgqGAD6AQAAAA==.',Ty='Typhoeus:BAAALAADCgcIBwAAAA==.Tyrannia:BAAALAAFFAIIAgAAAA==.',Us='Ustarte:BAAALAAECggICAAAAA==.',Ut='Uthad:BAAALAADCggICAAAAA==.',Va='Vanya:BAAALAAECgQIBAABLAAECggIHgAZAMgkAQ==.',Vi='Vivi:BAAALAADCggICAAAAA==.',Wa='Waykingo:BAABLAAECoEXAAMTAAcIHwuQIgAhAQATAAcI3wqQIgAhAQAQAAUIigWc+ADWAAAAAA==.',We='Weeb:BAAALAAECgQIBQABLAAFFAYIFwAVAMMYAA==.',Wi='Wickerwitch:BAAALAAECgEIAQAAAA==.Windfury:BAAALAAFFAIIAgABLAAFFAMIBwAQAMUZAA==.',Xu='Xuffie:BAAALAADCgYIBgAAAA==.',Ya='Yamasz:BAAALAADCgIIAgAAAA==.',Yi='Yin:BAABLAAECoEpAAIDAAgIbh5QGwC5AgADAAgIbh5QGwC5AgAAAA==.',Yo='Yorii:BAAALAAECgcIEwAAAA==.',Yu='Yuffie:BAAALAADCgYICAAAAA==.',Za='Zabulon:BAABLAAECoEWAAIQAAYIbSPBQABPAgAQAAYIbSPBQABPAgAAAA==.Zaggius:BAAALAAECgcIEAAAAA==.Zakali:BAABLAAECoEjAAISAAgIPyJjDwAoAwASAAgIPyJjDwAoAwAAAA==.Zakdoek:BAABLAAFFIEHAAISAAMIxg68DwDsAAASAAMIxg68DwDsAAAAAA==.',Ze='Zellíe:BAABLAAECoEmAAIDAAgIJQt9cgCOAQADAAgIJQt9cgCOAQAAAA==.Zengar:BAAALAADCggIFAAAAA==.',['Äl']='Äleris:BAAALAAECgYIBgABLAAECgcIDwAKAAAAAA==.',['Èg']='Ègil:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end