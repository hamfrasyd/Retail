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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-Marksmanship','Mage-Fire','Rogue-Assassination','Warlock-Destruction','Monk-Mistweaver','DemonHunter-Vengeance','DemonHunter-Havoc','DeathKnight-Blood','Druid-Restoration','Druid-Balance','Druid-Feral','Hunter-BeastMastery','Paladin-Retribution','Shaman-Elemental','DeathKnight-Frost','Priest-Holy','Shaman-Restoration','Warlock-Demonology',}; local provider = {region='EU',realm="Ahn'Qiraj",name='EU',type='weekly',zone=44,date='2025-09-06',data={Ag='Agatul:BAAALAADCgYIBgAAAA==.',Ah='Ahleë:BAAALAAECgIIAgAAAA==.',Ai='Aivendil:BAAALAADCgcICgAAAA==.',Ak='Akumai:BAAALAADCggIEQABLAAECgYICgABAAAAAA==.',Al='Allnya:BAAALAAECgYIDwAAAA==.',Ar='Arcanus:BAABLAAECoEZAAICAAgIAiHSDAD6AgACAAgIAiHSDAD6AgAAAA==.Arien:BAAALAADCgMIAwAAAA==.Arythc:BAAALAAECgYIEwAAAA==.',As='Ashpool:BAAALAADCggICAAAAA==.Assalta:BAABLAAECoEYAAIDAAgI3RtFDwCMAgADAAgI3RtFDwCMAgAAAA==.',At='Atomica:BAABLAAECoEaAAMCAAgIviJMFQC0AgACAAcIOyRMFQC0AgAEAAEIUBiqDwBUAAAAAA==.',Ba='Balphagore:BAAALAADCggICAABLAAECgcIFAAFACUbAA==.',Be='Beladi:BAAALAADCgUIBQAAAA==.Beyblade:BAAALAAECgEIAQABLAAECggIGwAGALshAA==.',Bi='Bigbarry:BAAALAADCgYIBgAAAA==.',Bl='Bluuxx:BAAALAADCgUIBQAAAA==.Bluxx:BAABLAAECoEdAAIHAAgI9xnXBwCAAgAHAAgI9xnXBwCAAgAAAA==.Bluxxlock:BAAALAAECgIIAgAAAA==.',Bo='Borbalf:BAAALAADCgcIBwAAAA==.',Bu='Buicih:BAABLAAECoEXAAMIAAcIWiSHAwDkAgAIAAcIWiSHAwDkAgAJAAEI1QWKuAAkAAAAAA==.Bun:BAAALAADCgcICwAAAA==.',Ce='Cedori:BAAALAAECggIDgAAAA==.',Ch='Charming:BAAALAADCgMIAwAAAA==.',Co='Comoapoel:BAABLAAECoEUAAIFAAcIJRsIFAAsAgAFAAcIJRsIFAAsAgAAAA==.',Cr='Crazinaa:BAAALAAECgcICAAAAA==.',Da='Daekon:BAAALAAECgYIDwAAAA==.Dakini:BAAALAADCgcICQABLAAECgYICgABAAAAAA==.Daphnes:BAAALAAECgYICAAAAA==.Darko:BAAALAAECgcIEwAAAA==.',De='Deathkitteh:BAAALAADCgYIBgAAAA==.Delish:BAAALAADCgQIBAAAAA==.',Dk='Dkshadow:BAAALAADCggICAABLAAECgcIFAAKANwYAA==.',Do='Docnidar:BAAALAADCgYIAwAAAA==.Doomakos:BAAALAAECgUICAAAAA==.Doomnezeu:BAAALAAECgYIEQAAAA==.Dorgarag:BAAALAADCgcIBwAAAA==.Dotsfordays:BAABLAAECoEbAAIGAAgIuyFDCAAQAwAGAAgIuyFDCAAQAwAAAA==.',Dr='Draehunn:BAAALAAECgYIBgAAAA==.Draeknight:BAAALAADCggICAAAAA==.Dragdock:BAAALAADCggIDwAAAA==.Droodfus:BAAALAAECgMIAwAAAA==.Drstrange:BAAALAAECgQIBQAAAA==.Drunkmaster:BAAALAADCgYICgAAAA==.',['Dø']='Døku:BAAALAADCggICAAAAA==.',Em='Emildruid:BAAALAADCgYIBgAAAA==.',Ev='Evelin:BAAALAADCggIFQAAAA==.',Fa='Faraal:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.Faélara:BAAALAAECgMIAwAAAA==.',Fl='Flume:BAABLAAECoEXAAQLAAgIZxVwIgDFAQALAAgIZxVwIgDFAQAMAAUIsBVsNABPAQANAAEI8hf9JgBPAAAAAA==.Flumedh:BAAALAAECgUIBQAAAA==.Flumemage:BAAALAAECgYIBwAAAA==.Flumewarr:BAAALAADCggICwAAAA==.',Fr='Freshmoon:BAAALAAECgQIBAAAAA==.',Gu='Guldàmn:BAAALAADCggIDgAAAA==.',Ha='Haecubah:BAAALAADCgEIAQAAAA==.',He='Hedri:BAAALAAECgEIAQAAAA==.Helius:BAABLAAECoEXAAIOAAgIlBtNEQCoAgAOAAgIlBtNEQCoAgAAAA==.Hephaestus:BAAALAADCgcIBwABLAAECggIGAAMALwbAA==.Heretika:BAAALAADCggIFgAAAA==.',Hi='Hitmanlee:BAAALAADCggIDAAAAA==.',Ho='Honeypoo:BAAALAADCgEIAQAAAA==.',Hz='Hzk:BAAALAAECgUIAgAAAA==.',Ic='Iceblock:BAAALAAECgYICAABLAAECgcIEwABAAAAAA==.',Il='Ilikeballzz:BAAALAAECgYIDAAAAA==.Ilikebeellzz:BAAALAADCgcIBwAAAA==.Ilindan:BAAALAAECgUIBgAAAA==.',Je='Jens:BAAALAAECgcICwAAAA==.',Ka='Kalandra:BAAALAADCgMIAwAAAA==.Kallorr:BAAALAAECgcIEwAAAA==.Kanondbhaal:BAAALAAECggIDgAAAA==.',Kl='Kljucis:BAABLAAECoEYAAIMAAgIvBuVDwB/AgAMAAgIvBuVDwB/AgAAAA==.',Kn='Knowidea:BAAALAAECggIEAAAAA==.',Kr='Krungul:BAAALAADCggIDgAAAA==.',Ku='Kuan:BAABLAAECoEdAAIIAAgIVhwRBgCIAgAIAAgIVhwRBgCIAgAAAA==.',La='Laeriah:BAAALAADCgIIAgAAAA==.',Le='Leosolo:BAAALAAECgYIDAAAAA==.',Li='Liilith:BAAALAAECgYIDwAAAA==.Liliandra:BAAALAADCggIDwAAAA==.Lillaludret:BAAALAADCgcIDwAAAA==.Lincos:BAAALAADCgEIAQABLAAECgcIEAABAAAAAA==.',Lo='Lobo:BAAALAAECgIIAgAAAA==.Losmi:BAAALAAECgMIBQAAAA==.',Ma='Maeyedk:BAAALAADCgcICQAAAA==.Magou:BAAALAADCggICAABLAAECgcIFAAIAKkcAA==.Marakara:BAAALAAECgcIEAAAAA==.Mardeth:BAAALAADCgMIAQAAAA==.',Me='Meeris:BAAALAADCggIEQABLAAECggIGAAMALwbAA==.Mezereon:BAAALAAECgcIEwAAAA==.',Mi='Michaela:BAAALAADCgYIBgAAAA==.Mistykitteh:BAAALAADCgcIDQAAAA==.',Mo='Moa:BAAALAADCgcIDQAAAA==.Mohanje:BAAALAADCggIDwAAAA==.Moonmoon:BAAALAAECgcIEAAAAA==.Moriartree:BAAALAADCggIFgAAAA==.',My='Myth:BAAALAAECgYIBgAAAA==.',['Mø']='Møll:BAAALAADCggIGQAAAA==.',Na='Nandi:BAAALAADCggICAAAAA==.Nathil:BAABLAAECoEbAAIPAAgInCNoCQAmAwAPAAgInCNoCQAmAwAAAA==.Native:BAAALAAECgYICAAAAA==.',Ne='Nedge:BAAALAAECgIIAgAAAA==.Nenyasho:BAAALAADCgMIAwAAAA==.Nerohk:BAAALAADCggICAAAAA==.',Ny='Nyxara:BAAALAADCgcIBwABLAAECgQIBwABAAAAAA==.',Ou='Outeast:BAAALAAECgEIAQAAAA==.',Pe='Pepa:BAAALAAECgcIEQAAAA==.',Pl='Plesejs:BAAALAAECgIIAgABLAAECggIGAAMALwbAA==.',Pr='Preach:BAAALAAECgYICAAAAA==.Prelina:BAAALAADCgcICwAAAA==.Prix:BAAALAAECgcIEgAAAA==.Promocia:BAAALAADCgcIDgAAAA==.',['Pö']='Pö:BAAALAADCgcIBwAAAA==.',Qr='Qrypto:BAAALAADCgcIBwABLAAECgcIFQAQAP4gAA==.',Qs='Qsien:BAAALAAECgYIDAAAAA==.',Re='Reaper:BAABLAAECoEZAAIRAAYIYhBAZQBdAQARAAYIYhBAZQBdAQAAAA==.Restoration:BAAALAAFFAIIAgAAAA==.',Ri='Rizskása:BAAALAADCgUIBQAAAA==.',Ro='Rowodent:BAAALAADCgYIBgAAAA==.',Ru='Rufsa:BAAALAADCgcIDQAAAA==.',Ry='Ryrfy:BAAALAADCgYICgAAAA==.',Sa='Saab:BAAALAAECgYIDwAAAA==.Saabi:BAAALAADCggIEAAAAA==.Samstezz:BAAALAAECgQIBwAAAA==.Sashioman:BAAALAAECgIIAgAAAA==.',Sc='Scarhoof:BAAALAAECgEIAQAAAA==.',Sh='Shademd:BAAALAAECggIDgAAAA==.Shadowdk:BAABLAAECoEUAAMKAAcI3BixCwDqAQAKAAcI3BixCwDqAQARAAIIuQuwuABbAAAAAA==.Shadowonercy:BAAALAAECgUICwABLAAECgcIFAAKANwYAA==.Shak:BAAALAADCgcIFQAAAA==.Shantaram:BAAALAAECgcIDQAAAA==.Shanti:BAAALAAECgQIBQAAAA==.Shepri:BAABLAAECoEXAAISAAgIRxYfFgBLAgASAAgIRxYfFgBLAgAAAA==.',Si='Sien:BAAALAAECgYICAAAAA==.Simonsay:BAAALAADCggIFwAAAA==.Sin:BAAALAAECgYIEAAAAA==.',Sl='Slant:BAAALAAECgcIDgAAAA==.',Sn='Snow:BAAALAAFFAIIAgAAAA==.',So='Solziege:BAAALAAECgYICgAAAA==.Sorrysussy:BAAALAADCgYIBgAAAA==.Souhila:BAAALAADCggIDAAAAA==.Souvlas:BAABLAAECoEUAAITAAcIWhKtPACJAQATAAcIWhKtPACJAQAAAA==.',St='Steeminator:BAABLAAECoEUAAMQAAgIiBQHIgABAgAQAAgIiBQHIgABAgATAAMIuxGugACoAAAAAA==.Stevéy:BAAALAAECgMIBwAAAA==.Stingeh:BAAALAAECgQIBAABLAAECgcIEwABAAAAAA==.Stravi:BAABLAAECoEUAAIIAAcIqRzlCABAAgAIAAcIqRzlCABAAgAAAA==.',Su='Superfreaky:BAAALAADCggICAAAAA==.Supernal:BAAALAAECgUIBQABLAAECggIGAAMALwbAA==.',Sy='Sylvenia:BAAALAADCgIIAgAAAA==.',['Sï']='Sïnnsyk:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.',Th='Thehealer:BAAALAAECgQIBwAAAA==.Thementor:BAAALAADCggICAAAAA==.Thorock:BAAALAADCgQIBAAAAA==.',To='Tot:BAAALAAECgYIDAAAAA==.',Tr='Trempel:BAAALAAECgEIAQAAAA==.Trokara:BAAALAAECgcIEAAAAA==.Tryandie:BAAALAAECgcICwAAAA==.Trylletøs:BAAALAAECgYIEgAAAA==.Trädet:BAAALAAECgUICwAAAA==.',Tu='Tudella:BAAALAAECgcIEQAAAA==.Turboshooter:BAAALAAECgQIBAAAAA==.',Un='Unlimpower:BAAALAADCgYIBgAAAA==.Untouchable:BAAALAADCggICAAAAA==.',Us='Usedtobeabot:BAAALAAECgYIEwAAAA==.',Va='Vakhi:BAABLAAECoEUAAIUAAgI5BVOCgBbAgAUAAgI5BVOCgBbAgAAAA==.Vannesh:BAAALAAECggIDAAAAA==.Vapenash:BAABLAAECoEVAAIQAAcI/iCEEgCPAgAQAAcI/iCEEgCPAgAAAA==.',Ve='Verghast:BAAALAADCggICAAAAA==.',Vo='Vosita:BAAALAAECgEIAQAAAA==.',Xa='Xandem:BAAALAADCgQIBAAAAA==.',Xr='Xray:BAAALAAECgcIDQAAAA==.',Za='Zabkása:BAAALAADCggICAAAAA==.',Ze='Zenana:BAAALAADCggICAAAAA==.Zeronine:BAAALAAECgIIAgABLAAECggIGgACAL4iAA==.',Zh='Zhantora:BAAALAAECgYIEAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end