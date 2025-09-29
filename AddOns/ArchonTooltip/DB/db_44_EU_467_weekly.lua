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
 local lookup = {'Shaman-Elemental','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Restoration','DemonHunter-Havoc','Unknown-Unknown','Shaman-Enhancement','Paladin-Retribution','Monk-Windwalker','Priest-Holy','Priest-Discipline','Evoker-Preservation','Priest-Shadow','Warlock-Demonology','Warrior-Fury','Warrior-Arms','DeathKnight-Blood','Druid-Guardian','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Mage-Frost','DeathKnight-Frost','Paladin-Holy','Warrior-Protection','Monk-Mistweaver','Druid-Balance',}; local provider = {region='EU',realm='Terrordar',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aalfänger:BAAALAADCggICAAAAA==.',Ai='Aior:BAAALAADCgcIEwAAAA==.',Ak='Akeno:BAABLAAECoEVAAIBAAcIpg3+UACZAQABAAcIpg3+UACZAQAAAA==.',Al='Aldun:BAAALAAECgcIBwAAAA==.Algaan:BAAALAAECgYIBgAAAA==.Allinone:BAAALAAECgYIDAAAAA==.Allucanheal:BAAALAAECgYIBwAAAA==.Alphenia:BAABLAAECoEbAAMCAAcIdRrUWQDVAQACAAcIdRrUWQDVAQADAAMI5xC6iACVAAAAAA==.Altf:BAAALAADCgMIAwAAAA==.',An='Anubíz:BAAALAAECgQIBgABLAAFFAMIBQAEAHUYAA==.',Ap='Apokalypto:BAAALAAECggICAAAAA==.',Ar='Arinya:BAABLAAECoEgAAICAAgIpBo1OgA1AgACAAgIpBo1OgA1AgAAAA==.Arkana:BAAALAAECgMIBAAAAA==.Arya:BAAALAAECgIIAgAAAA==.',As='Asanyeo:BAAALAADCggIDgAAAA==.Asmodiná:BAABLAAECoEZAAIFAAYIVgmjwwAOAQAFAAYIVgmjwwAOAQAAAA==.Asmodäus:BAAALAAECgQIDwAAAA==.',Ax='Axernos:BAAALAADCggIEgABLAAECggIIwACANQjAA==.',Ba='Barôn:BAAALAADCggICAAAAA==.',Be='Bellafonte:BAAALAAECgYIDQAAAA==.Benhîndert:BAAALAAECgYICgAAAA==.',Bi='Bissza:BAAALAADCgYIBgAAAA==.',Bo='Bootcamp:BAAALAAECgEIAQAAAA==.',Bu='Bulwark:BAAALAAECggICAAAAA==.',Ca='Calea:BAAALAADCggICwAAAA==.Calikessy:BAAALAADCggICAAAAA==.Caturday:BAAALAAECgYIBgAAAA==.',Ce='Celtics:BAAALAAECgYIDgAAAA==.',Co='Coogan:BAAALAAECgYIBgAAAA==.',Cr='Croiffin:BAAALAADCggIEgAAAA==.',Cy='Cyria:BAAALAADCggIDgAAAA==.',Di='Disgrace:BAAALAAECggICAABLAAECggILgACAGomAA==.',Dj='Djeezy:BAAALAADCgYIBwAAAA==.',Do='Doktorgewalt:BAAALAADCgMIBAABLAADCggICgAGAAAAAA==.',Dr='Dropa:BAAALAADCggIGAAAAA==.',Ea='Earthchan:BAAALAADCggIDAAAAA==.',Em='Emlaiel:BAAALAADCggIGAAAAA==.',Ex='Ex:BAAALAADCgcIBwAAAA==.Extremos:BAAALAADCgcICAAAAA==.Exundari:BAAALAAECgQIBAABLAAECggIIAAHAGskAA==.',Fe='Felizitâs:BAAALAAECgYIBwAAAA==.Fenril:BAAALAAECgYIEAAAAA==.',Ge='Germane:BAAALAADCggICAAAAA==.',Go='Golddiggee:BAAALAAECgYIDQAAAA==.Golgatha:BAABLAAECoEZAAIFAAYISBJIoABYAQAFAAYISBJIoABYAQAAAA==.',Gr='Grello:BAABLAAECoEcAAIBAAYIAB9JPADqAQABAAYIAB9JPADqAQAAAA==.Grisu:BAAALAADCggICAABLAAECggIIAAHAGskAA==.',Gu='Guacamole:BAAALAAECgIIAQAAAA==.',Ha='Hackepater:BAAALAADCgEIAQAAAA==.Hansmowl:BAABLAAECoEWAAIIAAcICxK/fgC8AQAIAAcICxK/fgC8AQAAAA==.Haru:BAAALAADCgEIAQAAAA==.',He='Hellchick:BAAALAADCggICAAAAA==.',Ho='Hormeas:BAAALAAECgUIBQAAAA==.',Hu='Huhnerauge:BAAALAADCggIFQAAAA==.',Hy='Hyacia:BAAALAAECggIEgAAAA==.',['Hì']='Hìnata:BAABLAAECoEdAAIJAAgIHBWjGQAMAgAJAAgIHBWjGQAMAgAAAA==.',Im='Immortalem:BAABLAAECoEUAAMKAAgIBB4UFwCZAgAKAAgIBB4UFwCZAgALAAYIbRTEDgCJAQABLAAFFAUIEQAMAFcNAA==.',In='Inanisumbra:BAABLAAECoEfAAINAAcIdRbxLgD1AQANAAcIdRbxLgD1AQAAAA==.Inkman:BAAALAADCggIFwAAAA==.Invidia:BAAALAAECggICAAAAA==.',Ja='Jagdgermanin:BAAALAADCggICAAAAA==.',Je='Jebigabrate:BAAALAADCgYIDAAAAA==.Jessy:BAABLAAECoElAAICAAgI/Q1JcgCaAQACAAgI/Q1JcgCaAQAAAA==.',Ji='Jimbar:BAAALAAECggIDwAAAA==.',Jo='Joox:BAAALAADCgMIBAAAAA==.',Ka='Kainazzo:BAABLAAECoEgAAIHAAgIayTUAABaAwAHAAgIayTUAABaAwAAAA==.Kalthas:BAAALAADCgYIBgABLAAECggIIQAOAIYeAA==.Karaswa:BAABLAAECoEgAAICAAgIVBcfRwAKAgACAAgIVBcfRwAKAgAAAA==.Karleeh:BAABLAAECoEsAAICAAgIdSCOHQC1AgACAAgIdSCOHQC1AgAAAA==.Kashmirinche:BAABLAAECoEcAAIKAAgIGxI6OADXAQAKAAgIGxI6OADXAQAAAA==.',Ke='Kellerkolle:BAAALAADCgcIBwAAAA==.',Kh='Khabaal:BAAALAADCggICAAAAA==.',Kr='Krilza:BAAALAADCggICAAAAA==.',Ku='Kupo:BAAALAADCgcIBwAAAA==.',La='Laluna:BAAALAADCgYIBgAAAA==.Lanea:BAAALAADCgQIBAAAAA==.',Li='Lichtgermane:BAAALAAECgEIAQAAAA==.Lixyo:BAAALAADCggICAAAAA==.',Lo='Lockpick:BAAALAADCggICAABLAAECgcIHgAPAG8hAA==.Lokki:BAAALAADCgUICQAAAA==.',Lu='Lupercia:BAAALAADCggICAAAAA==.',Ma='Mahrus:BAABLAAECoEgAAIQAAgI+w4eDgDSAQAQAAgI+w4eDgDSAQAAAA==.Maikel:BAAALAADCgcIBwAAAA==.Mainè:BAAALAADCggIDAAAAA==.Mangis:BAAALAADCgUIBQAAAA==.Mantorock:BAABLAAECoEWAAIRAAcItxvCDwAeAgARAAcItxvCDwAeAgAAAA==.',Me='Medinagreen:BAAALAAECggICAAAAA==.Melthaz:BAAALAAECgcIEQAAAA==.Metaslave:BAAALAAECgYIDAABLAAECggIDAAGAAAAAA==.',Mi='Milany:BAAALAADCggICAAAAA==.',Mo='Mogy:BAABLAAECoEWAAIFAAYIDAdMwwAOAQAFAAYIDAdMwwAOAQAAAA==.Monkyponky:BAAALAADCggIEAABLAAECggIIAAQAPsOAA==.',Na='Nakarox:BAAALAAECgcIDwABLAAFFAIIBwASAJUjAA==.Natdal:BAAALAADCgcIBwAAAA==.Nawdal:BAAALAAECgYICwAAAA==.Nazguhl:BAAALAADCgUIBQAAAA==.',Ne='Nerzul:BAABLAAECoEhAAIOAAgIhh41CADJAgAOAAgIhh41CADJAgAAAA==.',Ni='Nibbl:BAAALAAECgYIEgABLAAECgcIGgAFAOkdAA==.',No='Norbertglock:BAAALAAECgIIAgAAAA==.',Pe='Perridur:BAABLAAECoEfAAIEAAgILhw4FACVAgAEAAgILhw4FACVAgAAAA==.',Pi='Pilika:BAAALAAECgIIAgAAAA==.',Pl='Plexia:BAABLAAECoEXAAQTAAcINhycOwAdAgATAAcIlhicOwAdAgAOAAMIHBeUXgDFAAAUAAIIqAZFLQBuAAAAAA==.',Py='Pythagorazz:BAABLAAECoElAAIBAAgIVhzUNgADAgABAAgIVhzUNgADAgAAAA==.',['Pê']='Pêrsês:BAAALAAECggIBgAAAA==.',['Pü']='Püppi:BAABLAAECoEVAAICAAcIChJVgwB3AQACAAcIChJVgwB3AQAAAA==.',Qu='Quelte:BAAALAAECgQIBwABLAAFFAIIBQAVAOkcAA==.',Ra='Rainaa:BAABLAAECoEeAAIPAAcIbyG9HwClAgAPAAcIbyG9HwClAgAAAA==.Rakesha:BAAALAADCggICAABLAAECgcIBwAGAAAAAA==.Rapdepp:BAABLAAECoEbAAIWAAcIliF+DgCcAgAWAAcIliF+DgCcAgAAAA==.',Re='Renfield:BAABLAAECoEXAAIXAAYIJyASbADpAQAXAAYIJyASbADpAQABLAAFFAUIEQAFACwaAA==.Rewak:BAAALAADCggICAAAAA==.',Ro='Robn:BAAALAAECgYIEAAAAA==.',Sa='Sadisticon:BAAALAADCgcIDQAAAA==.Santhe:BAAALAADCggICgAAAA==.Savi:BAAALAADCgcIBwABLAAECgcIGgAFAOkdAA==.',Sc='Scarletwitch:BAAALAADCgMIBAAAAA==.Schnittza:BAAALAADCgQIBAAAAA==.',Se='Seeräubär:BAAALAAECgcIDAAAAA==.Serale:BAABLAAECoExAAIYAAgIohMXHgD0AQAYAAgIohMXHgD0AQAAAA==.Sews:BAABLAAECoEgAAMZAAgIqQROVwDMAAAZAAgIqQROVwDMAAAPAAgIywHavgBnAAAAAA==.',Sh='Shaderon:BAAALAAECgcIEAAAAA==.Shira:BAAALAAECgQIDAABLAAECggIMQAYAKITAA==.',Sj='Sjet:BAAALAAECgcIDgAAAA==.',Sn='Snylck:BAAALAADCggICAAAAA==.',St='Strul:BAAALAADCggICAAAAA==.',Su='Suedi:BAAALAAECgYICwAAAA==.',Sy='Sy:BAAALAAECggICAAAAA==.',['Sí']='Sínthóras:BAABLAAECoEgAAIRAAgI0RWcEQABAgARAAgI0RWcEQABAgAAAA==.',Ta='Tamilea:BAAALAADCgEIAQAAAA==.Tarlas:BAABLAAECoEtAAIPAAgIQBu5MgA6AgAPAAgIQBu5MgA6AgAAAA==.Tayun:BAAALAADCgcIBwAAAA==.',Te='Teroxx:BAAALAADCgUIBQAAAA==.',Th='Thalienne:BAAALAADCgcIDQAAAA==.Thaloria:BAAALAAECgYICQAAAA==.Thelea:BAAALAAECggICgAAAA==.Theleâs:BAAALAADCggIEAABLAAECggICgAGAAAAAA==.',Ti='Tidu:BAAALAAECgUIBQAAAA==.',To='Toastbrot:BAAALAADCgcIDQAAAA==.',Tr='Trolladin:BAAALAADCgcIBwAAAA==.',Tu='Tungsten:BAAALAADCgYIBwAAAA==.',['Té']='Téodory:BAAALAAECggIBwAAAA==.',Va='Valanthe:BAAALAADCggIEgAAAA==.',Vi='Viebistyl:BAAALAADCggICAAAAA==.Viljar:BAACLAAFFIEPAAINAAYIzxl0AgA3AgANAAYIzxl0AgA3AgAsAAQKgSkAAg0ACAjxJYECAHEDAA0ACAjxJYECAHEDAAEsAAQKBwgHAAYAAAAA.Vipa:BAAALAAECgcIBwAAAA==.Vivi:BAABLAAECoEaAAIFAAcI6R1caADKAQAFAAcI6R1caADKAQAAAA==.',['Vî']='Vîollett:BAAALAAECgcIDQAAAA==.',Xa='Xanthà:BAABLAAECoEkAAIaAAgIgRuVDQBnAgAaAAgIgRuVDQBnAgAAAA==.',Xe='Xelos:BAABLAAECoEcAAMEAAgI5RDsPgCtAQAEAAgI5RDsPgCtAQAbAAcIFAi+VAArAQAAAA==.',Yv='Yvos:BAAALAAECgIIAgAAAA==.',Zi='Zifrel:BAAALAADCggIGQAAAA==.',Zr='Zroolek:BAAALAADCgEIAQAAAA==.',['Ào']='Àon:BAAALAAECgYIEAAAAA==.',['Áa']='Áatrox:BAAALAADCgEIAQAAAA==.',['Èl']='Èlede:BAAALAAECgEIAQABLAAECgcIHgAPAG8hAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end