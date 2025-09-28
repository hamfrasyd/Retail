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
 local lookup = {'Mage-Frost','Paladin-Retribution','Unknown-Unknown','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Blood','DemonHunter-Havoc','Monk-Windwalker','DeathKnight-Unholy','Evoker-Devastation','Mage-Arcane','Shaman-Elemental','Druid-Guardian','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Druid-Feral','Priest-Discipline','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Priest-Holy','Hunter-Survival','DemonHunter-Vengeance','Paladin-Protection','Druid-Balance',}; local provider = {region='EU',realm='Trollbane',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ae='Aedion:BAABLAAECoEXAAIBAAcILCRgCQDmAgABAAcILCRgCQDmAgAAAA==.',Am='Amazedpally:BAACLAAFFIEFAAICAAIIdxQqJgClAAACAAIIdxQqJgClAAAsAAQKgR8AAgIACAghIooWAAIDAAIACAghIooWAAIDAAAA.',An='Anbu:BAAALAADCgQIBAAAAA==.',Ar='Arachnideae:BAAALAAECgYIDAAAAA==.',Av='Avary:BAAALAAECggICAAAAA==.',Be='Beast:BAAALAAECggIDgAAAA==.',Br='Brinik:BAAALAADCgIIAwABLAAECgMIBwADAAAAAA==.Brunøye:BAACLAAFFIEGAAIEAAIIPRSCEQClAAAEAAIIPRSCEQClAAAsAAQKgRoAAgQACAhCHHwSAHsCAAQACAhCHHwSAHsCAAAA.',Bu='Bulletraj:BAABLAAECoEWAAICAAYI1AuuxAA3AQACAAYI1AuuxAA3AQAAAA==.Bulma:BAAALAAECgEIAQAAAA==.',Ca='Cashten:BAAALAAECggICAAAAA==.',Ce='Celosia:BAAALAAECgYIBgAAAA==.Cerin:BAABLAAECoEYAAMFAAgIgRjoUAAkAgAFAAgI4hboUAAkAgAGAAQIYBSsJwD1AAAAAA==.',Cr='Crasher:BAAALAADCgMIAwAAAA==.Crillidina:BAABLAAECoEmAAIHAAgI1iG9EgANAwAHAAgI1iG9EgANAwAAAA==.Crilljina:BAABLAAECoEiAAICAAgIJyKBEwASAwACAAgIJyKBEwASAwABLAAECggIJgAHANYhAA==.',Cu='Curt:BAAALAADCgcIBwAAAA==.',Da='Daimen:BAAALAADCggIDQAAAA==.Dawnnblade:BAAALAAECgQIBAAAAA==.',Di='Dimsum:BAACLAAFFIEGAAIIAAMI3iRJBABAAQAIAAMI3iRJBABAAQAsAAQKgR4AAggACAiBJqkAAIYDAAgACAiBJqkAAIYDAAAA.',Do='Donkererubs:BAABLAAECoEQAAIJAAcIMxsUEgAmAgAJAAcIMxsUEgAmAgABLAAFFAYIEAAKAI4RAA==.',Dr='Dracharis:BAAALAAECgYIBgAAAA==.',Du='Duiru:BAAALAADCgEIAQAAAA==.',Dy='Dyngkuken:BAAALAADCgQIBAAAAA==.',Ei='Eilavon:BAAALAAECgMIBwAAAA==.',El='Elisawar:BAAALAADCggICAAAAA==.',Em='Emí:BAAALAAECgQIBgAAAA==.',Er='Ericphilips:BAABLAAECoEVAAILAAcINxlvRQAUAgALAAcINxlvRQAUAgAAAA==.Ernosgon:BAAALAAECgYIDgAAAA==.',Es='Escape:BAAALAADCggICAAAAA==.',Fa='Fallkvisto:BAAALAAFFAIIAwAAAA==.',Fl='Flafy:BAAALAAECgcIEwAAAA==.',Go='Gokuthehuntr:BAABLAAECoEcAAIHAAgILxxRLACDAgAHAAgILxxRLACDAgAAAA==.',Gu='Gurrag:BAABLAAECoEjAAIMAAgIFxoEIAB+AgAMAAgIFxoEIAB+AgAAAA==.',Ha='Hairball:BAABLAAECoEXAAINAAcIpSWdAgAFAwANAAcIpSWdAgAFAwAAAA==.',He='Hemistodr:BAABLAAFFIEGAAIOAAIIVgt5JQCCAAAOAAIIVgt5JQCCAAAAAA==.',Ho='Holyneel:BAAALAAECgIIAgAAAA==.Horris:BAABLAAECoEcAAIGAAcIRSN8CACuAgAGAAcIRSN8CACuAgAAAA==.',['Hå']='Hårdochhårig:BAAALAAECgEIAgAAAA==.',Im='Imhoteph:BAAALAAECgUIBwAAAA==.Impcaster:BAABLAAECoEXAAMPAAcI2Bq7FgAjAgAPAAcI2Bq7FgAjAgAQAAYIhwkflQAGAQAAAA==.',In='Innercity:BAAALAAECgQIBAAAAA==.',Ja='Jaggarr:BAAALAADCggIDQAAAA==.Jannah:BAAALAAECgcIEwAAAA==.Janzon:BAABLAAECoEWAAIPAAgI5xAAKAC1AQAPAAgI5xAAKAC1AQAAAA==.',Je='Jeppaz:BAAALAADCgcICwAAAA==.',Ka='Katlord:BAACLAAFFIEIAAIQAAMIihMrFwD8AAAQAAMIihMrFwD8AAAsAAQKgSAAAhAACAhvHAUhAJ8CABAACAhvHAUhAJ8CAAAA.Kazmodin:BAAALAAECgQIBAAAAA==.',Kh='Khab:BAABLAAECoEXAAIRAAcIvRs9MQA7AgARAAcIvRs9MQA7AgAAAA==.Khrek:BAAALAAECgEIAQAAAA==.',Ki='Kimura:BAAALAAECgcIEwAAAA==.',Kr='Kraku:BAABLAAECoEdAAISAAcIFwkNIQBdAQASAAcIFwkNIQBdAQAAAA==.Kreoon:BAAALAAECgMIBAAAAA==.Kriestress:BAABLAAECoEVAAITAAcI3R2kBABhAgATAAcI3R2kBABhAgAAAA==.',Kt='Ktesyan:BAAALAAECgMIBwAAAA==.',La='Lazerbeak:BAAALAADCgIIAgAAAA==.',Le='Leitmotif:BAABLAAECoEiAAITAAgIiht+AwCUAgATAAgIiht+AwCUAgAAAA==.Lemonarrow:BAAALAADCggICAAAAA==.',Li='Litleundead:BAABLAAECoEhAAMUAAgIAiNJDwAHAwAUAAgIAiNJDwAHAwAVAAQIYxhZawD7AAAAAA==.Littleundead:BAAALAAECgYICQABLAAECggIIQAUAAIjAA==.',Lu='Luckyroller:BAAALAADCgIIAgABLAADCggICAADAAAAAA==.',Ma='Macer:BAABLAAECoEZAAIRAAgI4w0fWwCgAQARAAgI4w0fWwCgAQAAAA==.',Me='Meconopsis:BAAALAAECgIIAgAAAA==.Meurte:BAACLAAFFIEKAAIOAAMIDxFlDgDQAAAOAAMIDxFlDgDQAAAsAAQKgSEAAg4ACAjaHm0SAKACAA4ACAjaHm0SAKACAAAA.',Mo='Moogie:BAABLAAECoEXAAIGAAcInBF3GQCNAQAGAAcInBF3GQCNAQAAAA==.Moriam:BAAALAADCggICgAAAA==.Mortred:BAAALAAECgYICgAAAA==.',Mw='Mwen:BAABLAAECoEcAAIWAAcI0BOGXACeAQAWAAcI0BOGXACeAQAAAA==.',Ne='Nebelkrieger:BAAALAAECgMIAwAAAA==.Neithyo:BAACLAAFFIEOAAILAAUI7R9uBgD6AQALAAUI7R9uBgD6AQAsAAQKgSIAAgsACAjmJTICAHkDAAsACAjmJTICAHkDAAAA.',Ni='Nightdex:BAAALAADCggIEgAAAA==.Nitrozeus:BAAALAAECgYIDgAAAA==.',No='Nolose:BAAALAAECgYICwAAAA==.Nolosepriest:BAAALAAECgYIDQAAAA==.Notsoyren:BAAALAAECggIDAABLAAFFAUIDwAGAFQeAA==.',Ny='Nyurga:BAAALAADCgYIBgAAAA==.',Om='Omskæreren:BAAALAAECggIEQAAAA==.',Oy='Oya:BAAALAAECgYIBgAAAA==.',Pa='Paladrome:BAAALAAECgIIAgAAAA==.Palludin:BAAALAAECgcIDQAAAA==.',Pe='Pestspridare:BAAALAAECgUIBQAAAA==.',Ph='Phlox:BAAALAAECggIEAAAAA==.',Pi='Pitaya:BAAALAAECgYIDwAAAA==.',Po='Popehunter:BAAALAADCgUIBQABLAAECggIIQAUAAIjAA==.',Pu='Puro:BAAALAAECgYIEwAAAA==.',Qu='Quadpolarelf:BAAALAADCgUIBQAAAA==.',Ri='Ringer:BAAALAAECggIDAABLAAFFAMICAAOAAYTAA==.',Ru='Rumpmasen:BAAALAADCgcIBwABLAAFFAEIAQADAAAAAQ==.',Sc='Schlingel:BAAALAAECgcICQAAAA==.Schnitzaren:BAAALAAECggIDgAAAA==.',Se='Sephassa:BAABLAAECoEXAAMTAAcIGg8IEQBfAQATAAcIAw4IEQBfAQAXAAMIlw0UiQCWAAAAAA==.Sephion:BAABLAAECoEkAAQYAAgIGiQ3AQA4AwAYAAgI9CM3AQA4AwAUAAUIcCK9kgBRAQAVAAIIVxqqjQCAAAAAAA==.',Sh='Shamadrix:BAAALAAECggICAAAAA==.',Sk='Skyballs:BAAALAAFFAIIAgAAAA==.',Sn='Snoesje:BAAALAAECgIIAgAAAA==.Snusmumrik:BAABLAAECoEcAAMZAAcIZB5iDQBZAgAZAAcIzh1iDQBZAgAHAAYIVh2PcQCwAQAAAA==.',So='Solidsnack:BAAALAADCgcICAABLAAECgEIAQADAAAAAA==.',St='Stabbyabby:BAAALAAECgEIAQAAAA==.',Su='Supremekai:BAAALAAECgMIAwAAAA==.',Sy='Syndrana:BAAALAADCggICAAAAA==.',Sz='Szeth:BAABLAAECoEXAAIPAAcICBSDHwDmAQAPAAcICBSDHwDmAQAAAA==.',Ta='Tah:BAAALAADCgEIAQAAAA==.',Th='Thirsty:BAAALAAECgEIAQAAAA==.',To='Toibenias:BAACLAAFFIEGAAIaAAMIUxH8BQDTAAAaAAMIUxH8BQDTAAAsAAQKgSQAAxoACAhKIg0FABUDABoACAhKIg0FABUDAAIAAggND1oUAXsAAAAA.Tolid:BAABLAAECoEoAAIRAAgI2SD2DwAOAwARAAgI2SD2DwAOAwAAAA==.Tolmir:BAAALAAECgcIEAAAAA==.Tonsas:BAAALAAECgEIAQAAAA==.',Tr='Trollmonk:BAAALAAECgYICwAAAA==.',Tu='Tubtoot:BAABLAAECoEcAAISAAcIihsMDgBFAgASAAcIihsMDgBFAgAAAA==.',Ty='Tygorn:BAAALAADCgcIBwAAAA==.Tyrife:BAAALAADCgEIAQAAAA==.Tysaria:BAAALAAECgYIDAAAAA==.',Ul='Uliyanas:BAAALAAECgYIEQAAAA==.',Un='Underlig:BAAALAADCgQIBAAAAA==.',Wi='Wildlady:BAABLAAECoEiAAIbAAgIUwqQRQBlAQAbAAgIUwqQRQBlAQAAAA==.',Xe='Xeira:BAABLAAECoEUAAIQAAcIIxDgWwClAQAQAAcIIxDgWwClAQAAAA==.',Xv='Xvpr:BAAALAAECggIEAAAAA==.',Ya='Yaerius:BAABLAAECoEeAAMFAAgIHB4+QgBNAgAFAAgIHB4+QgBNAgAGAAEIch1yOwBBAAAAAA==.',Yu='Yuki:BAAALAAECgEIAQAAAA==.',Za='Zaflon:BAAALAAECggICAAAAA==.',Ze='Zemiel:BAAALAAECgYICQAAAA==.',Zi='Zinney:BAACLAAFFIETAAIOAAYIoSRFAQAqAgAOAAYIoSRFAQAqAgAsAAQKgS4AAg4ACAirJmUAAIUDAA4ACAirJmUAAIUDAAAA.Zita:BAAALAADCgcICgAAAA==.',Zo='Zoga:BAABLAAECoEhAAIUAAgI+RSUWADSAQAUAAgI+RSUWADSAQAAAA==.Zoomies:BAAALAAECgMICQAAAA==.',Zy='Zyran:BAAALAAFFAEIAQAAAQ==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end