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
 local lookup = {'Monk-Mistweaver','DemonHunter-Havoc','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Hunter-BeastMastery','Shaman-Restoration','Warrior-Fury','Shaman-Enhancement','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Rogue-Assassination',}; local provider = {region='EU',realm='DerRatvonDalaran',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aaliyah:BAAALAAECgIIBAAAAA==.',Ab='Abraxana:BAAALAADCgcIEAAAAA==.',Ac='Achale:BAAALAAECgcIDAAAAA==.Acharon:BAAALAADCggIDAABLAAFFAMIBQABAF4bAA==.',Ad='Adamanda:BAAALAADCggIFQAAAA==.Adanos:BAAALAADCggICAABLAAECggIGAACAAMiAA==.',Ae='Aentenmann:BAAALAADCgcICQAAAA==.',Ag='Agnodh:BAAALAADCgMIAQAAAA==.Agnodk:BAAALAAECgYIEAAAAA==.Agrawain:BAAALAADCgYIDgAAAA==.',Ai='Aiuma:BAAALAADCggIDwAAAA==.',Ak='Akaruii:BAABLAAECoEXAAIDAAgIqxrsGgA7AgADAAgIqxrsGgA7AgAAAA==.',Al='Aldatha:BAAALAADCggICAABLAAECgMIBAAEAAAAAA==.Alira:BAAALAADCggIDwABLAAECgMIBQAEAAAAAA==.Allysera:BAAALAADCggIEAAAAA==.Alpamaja:BAAALAADCgYIBgAAAA==.Alythess:BAAALAADCgYIBgAAAA==.',Am='Amazeroth:BAAALAADCggICAAAAA==.Amesha:BAABLAAECoEXAAIFAAgIaCWHAQBdAwAFAAgIaCWHAQBdAwAAAA==.Amnur:BAAALAADCgYIDgAAAA==.',An='Anjíne:BAAALAADCgYIBgAAAA==.Annadoria:BAAALAADCgYIBgABLAADCggIFQAEAAAAAA==.Annemore:BAAALAADCggICAAAAA==.',Ar='Arctic:BAAALAAECgYICgAAAA==.Argaal:BAAALAAECgYICgAAAA==.Ariafeedyone:BAABLAAECoEVAAICAAgIchq/EwB/AgACAAgIchq/EwB/AgAAAA==.',As='Asimov:BAAALAADCggIEAAAAA==.',At='Atair:BAAALAAECgcIDgAAAA==.Atairis:BAAALAADCgYIDgAAAA==.Athavarion:BAAALAAECgIIAgAAAA==.',Au='Auwibald:BAAALAAECgEIAQAAAA==.',Av='Averiel:BAAALAADCgQIAwABLAAECgYIDwAEAAAAAA==.',Ay='Ayûmî:BAAALAAECgYIBwAAAA==.',Az='Azogh:BAAALAAFFAIIAgAAAA==.',Ba='Baegrim:BAAALAADCgcIBwAAAA==.Balïndor:BAAALAAECgIIAQAAAA==.Batidá:BAAALAADCgMIAwAAAA==.',Be='Beliar:BAABLAAECoEYAAICAAgIAyLxBgAeAwACAAgIAyLxBgAeAwAAAA==.',Bi='Biggerbär:BAAALAAECgYICQAAAA==.Bilba:BAAALAAECgUIBgAAAA==.',Bl='Blacksuny:BAAALAADCggICAAAAA==.Bloodryan:BAAALAAECgMIBQAAAA==.Blueberry:BAAALAAECgIIAwAAAA==.',Bo='Borkaar:BAAALAAECgYICQAAAA==.Borìto:BAAALAAECgMIAwAAAA==.',Br='Bragma:BAAALAAECgYIDAAAAA==.Brod:BAAALAADCggICAABLAAECggIFQAGAOseAA==.Brooklyn:BAAALAAECgYICgAAAA==.Brödle:BAABLAAECoEVAAIGAAgI6x5JDgDBAgAGAAgI6x5JDgDBAgAAAA==.',['Bú']='Búwús:BAAALAADCggIEAAAAA==.',Ca='Calanon:BAAALAADCggIEgAAAA==.',Ch='Chrytha:BAAALAAECgYICgAAAA==.Chíllee:BAAALAADCgcIDAAAAA==.',Ci='Ciêc:BAAALAAECggICgAAAA==.',Co='Comyn:BAAALAAFFAIIAgAAAA==.Cowmanbebop:BAAALAAECgYICQAAAA==.',Cr='Crabby:BAAALAAECggICwAAAA==.Crascha:BAAALAADCgQIBAAAAA==.Crytøs:BAAALAAECgYIDQAAAA==.',Cu='Curcuma:BAAALAADCgIIAgAAAA==.Curilia:BAAALAADCgYIDgAAAA==.Custermato:BAAALAADCggICAAAAA==.',Cy='Cyrell:BAAALAADCggICAAAAA==.',Da='Dakhathkiam:BAAALAADCgYICQAAAA==.Darkdefs:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.Darkko:BAAALAAECgEIAQAAAA==.Darkroxx:BAAALAAECgMIBQAAAA==.',De='Deanerys:BAAALAAECgYIBgAAAA==.Dearmama:BAAALAADCggICAAAAA==.Deffs:BAAALAAECggIBgABLAAECggIEwAEAAAAAA==.Defs:BAAALAAECggIEwAAAA==.Defsmage:BAAALAAECgYIAwABLAAECggIEwAEAAAAAA==.',Di='Dinguskhan:BAAALAADCggIDwAAAA==.Dixon:BAAALAADCggIDAAAAA==.',Dk='Dkdefs:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.',Dr='Dragali:BAAALAAECgcICgAAAA==.Draggo:BAAALAAECgYICwAAAA==.Dragnoss:BAAALAADCgMIAwAAAA==.Draladin:BAAALAADCggICwABLAAECgcICgAEAAAAAA==.Drayani:BAAALAADCggICAAAAA==.Driest:BAAALAADCggIEAABLAAECgcICgAEAAAAAA==.',Du='Dungard:BAAALAAECgEIAQAAAA==.',['Dé']='Défs:BAAALAAECgYIBgABLAAECggIEwAEAAAAAA==.',Ea='Earawen:BAAALAADCggICAABLAAECggICgAEAAAAAA==.',Ed='Eddan:BAAALAADCgYIDwAAAA==.',El='Elmø:BAAALAADCgcIBwAAAA==.Elohim:BAABLAAECoEXAAIDAAgI8B/cCgDlAgADAAgI8B/cCgDlAgAAAA==.Elunara:BAAALAADCgUIAwAAAA==.',Em='Emkystone:BAAALAADCggICAAAAA==.',En='Enji:BAAALAADCggICAAAAA==.Entagor:BAAALAADCgIIAgAAAA==.',Ep='Epidemiç:BAAALAADCggICAAAAA==.',Et='Etiennê:BAAALAADCgcICgAAAA==.',Ev='Eveleen:BAAALAAECgYICgAAAA==.',Ex='Excon:BAAALAAECgEIAQAAAA==.',Fa='Faer:BAAALAADCggICAABLAAECgcICgAEAAAAAA==.Fangnix:BAAALAAECgEIAQAAAA==.Fatbutdead:BAACLAAFFIEFAAMHAAMI5xwxBgBfAAAHAAIIyCAxBgBfAAAIAAEIJBU/EwBUAAAsAAQKgRcAAwcACAhHJMwCAN8CAAcABwiWJMwCAN8CAAgABgjQHQkuANQBAAAA.Faylen:BAAALAADCggICAABLAAECggICwAEAAAAAA==.',Fe='Felladriel:BAAALAAECgEIAQAAAA==.Felyscha:BAAALAADCggIFQABLAAECgIIAgAEAAAAAA==.',Fi='Finlay:BAAALAAECgYIDAAAAA==.Firefox:BAAALAADCgEIAQAAAA==.',Fj='Fjoelnir:BAAALAAECggICwAAAA==.',Fl='Flavy:BAAALAADCgYIBgAAAA==.Flickamentis:BAAALAADCggICAAAAA==.',Fo='Fohri:BAAALAADCggICAAAAA==.',Fr='Frungrolosch:BAABLAAECoEXAAIJAAgI2w/LCQDCAQAJAAgI2w/LCQDCAQAAAA==.',Fu='Fumio:BAABLAAECoEXAAIKAAgIEB95AgDhAgAKAAgIEB95AgDhAgAAAA==.Funnylady:BAAALAADCggICAAAAA==.Futzi:BAAALAAECgYICwAAAA==.',Ga='Gaiane:BAAALAAECgIIAgAAAA==.Gallowos:BAAALAAECgEIAQAAAA==.Gammelbert:BAAALAAECgEIAgAAAA==.Ganda:BAAALAADCggIFAABLAAECgYICgAEAAAAAA==.Gandrosh:BAAALAAECgYICQAAAA==.',Ge='Gepo:BAAALAAECgYICgAAAA==.Gesu:BAAALAAECgIIAgAAAA==.',Gl='Globoss:BAABLAAECoEXAAILAAgIsR8LBACuAgALAAgIsR8LBACuAgAAAA==.',Go='Gottom:BAABLAAECoEXAAQMAAgIIR21DgDyAQAMAAYICh21DgDyAQANAAQIvRyeNABGAQAOAAQILxH3EAAvAQAAAA==.',Gr='Grantolph:BAAALAADCggICwAAAA==.Grider:BAABLAAECoEXAAIPAAgIthu0DQCcAgAPAAgIthu0DQCcAgAAAA==.Grosus:BAAALAAECggIEAAAAA==.',Gt='Gtmr:BAAALAADCggICAAAAA==.',Gu='Gurano:BAAALAADCggIEAABLAAECgYICgAEAAAAAA==.',Ha='Halcyon:BAAALAAECgIIAgAAAA==.',He='Heihachi:BAAALAADCgYIBgABLAAFFAIIBQAQAJoMAA==.Hemie:BAAALAAECgYICgAAAA==.Hephestes:BAAALAADCgYIBgAAAA==.Hexerdefs:BAAALAAECgYIBwABLAAECggIEwAEAAAAAA==.',Hi='Himiiko:BAAALAAECgcIEAAAAA==.',Ho='Holysalt:BAABLAAECoEUAAMLAAgIsxJTEABtAQALAAgIfw1TEABtAQADAAQIFBDDigBcAAAAAA==.Hornstar:BAAALAAECgUIBgAAAA==.Horstilein:BAAALAADCggIDQABLAAECgYICgAEAAAAAA==.Hotshots:BAAALAADCggIFgAAAA==.',Hy='Hyrah:BAAALAAECgYICgAAAA==.',['Hé']='Hékathe:BAAALAAECgIIBAAAAA==.',['Hê']='Hêrmês:BAAALAADCggICQAAAA==.',Ic='Ichika:BAAALAAECgMIAwAAAA==.',Ik='Iklatschdi:BAAALAAECgQIBAAAAA==.Ikto:BAAALAADCggIEAAAAA==.',Il='Illecebra:BAAALAADCgcIBwAAAA==.Illiá:BAAALAADCggICAAAAA==.Ilyne:BAAALAADCgEIAQAAAA==.',Im='Implinella:BAAALAAECgIIBAABLAAECggIGAACAAMiAA==.',In='Inobaff:BAAALAAECgEIAQAAAA==.',Ir='Iradiel:BAAALAAECgMIAwAAAA==.',Is='Isabellâ:BAAALAADCggICAABLAAECgYICgAEAAAAAA==.Isen:BAAALAAFFAIIAgAAAA==.Islanzadî:BAAALAAECgEIAQABLAAECgIIBAAEAAAAAA==.Istná:BAAALAAECgQIBwAAAA==.Iszan:BAAALAADCgYIBgAAAA==.Iszangralson:BAAALAADCgEIAQAAAA==.',Iy='Iyonaya:BAAALAAECgMIBAAAAA==.',Iz='Izza:BAAALAADCggIFAABLAAECgYICgAEAAAAAA==.',Ja='Jania:BAAALAADCgcIBwAAAA==.Jastos:BAABLAAECoEXAAIRAAgIzh/4BwD2AgARAAgIzh/4BwD2AgAAAA==.',Ji='Jiltanith:BAAALAADCgYIDAAAAA==.Jinxs:BAAALAADCgYIBwAAAA==.',Jo='Joolaran:BAAALAADCgYIDQAAAA==.',Ka='Kahmoz:BAABLAAECoEXAAISAAgIHRvyAgCfAgASAAgIHRvyAgCfAgAAAA==.Kaisar:BAAALAADCgcIDQAAAA==.Kalithon:BAAALAAECgYIDQAAAA==.Kandusa:BAAALAAECgYICgAAAA==.Kariná:BAAALAAECggICAAAAA==.Karía:BAAALAADCgYIDgAAAA==.Kasap:BAAALAAECgcICwAAAA==.Katlynn:BAAALAADCgYIBgAAAA==.Kayonara:BAAALAADCggIDAABLAAECgcICgAEAAAAAA==.Kayonik:BAAALAAECgcICgAAAA==.Kayowaid:BAAALAADCgYICgABLAAECgcICgAEAAAAAA==.',Ke='Kedal:BAAALAADCgcICAAAAA==.Keishara:BAAALAADCggICAABLAAECgIIBAAEAAAAAA==.Kendrani:BAAALAADCgcIDQAAAA==.Kerae:BAABLAAECoEUAAITAAgIjCHyAQAzAwATAAgIjCHyAQAzAwAAAA==.Kernchen:BAAALAAECgMIBQAAAA==.Keshia:BAAALAAECgIIAgAAAA==.Keóna:BAAALAAECgMIAwAAAA==.',Kh='Khêstrel:BAAALAAECgYICQAAAA==.',Kn='Knalli:BAABLAAECoEXAAIUAAgIASMfAgAoAwAUAAgIASMfAgAoAwAAAA==.Knirykas:BAAALAAECgYIDQAAAA==.',Kr='Krampe:BAAALAADCggICAAAAA==.',Ku='Kupfì:BAAALAAECgcIEAAAAA==.',Kv='Kvelthar:BAAALAAECgYIDwAAAA==.',Ky='Kyrina:BAAALAADCgYIBgAAAA==.',La='Lacriluna:BAAALAADCgcICQAAAA==.Lasarif:BAAALAAECggIDQAAAA==.Laydie:BAAALAADCggICAAAAA==.',Le='Leafmetender:BAAALAAECgYIBgABLAAECgcIDwAEAAAAAA==.Learose:BAAALAAECgEIAQAAAA==.Leboo:BAAALAAECgYIDAAAAA==.Leoníe:BAAALAADCggICgAAAA==.Leoníê:BAAALAADCggIDQAAAA==.Letsgoevo:BAAALAAECgYIDAAAAA==.',Li='Lightshot:BAAALAADCgYIBgAAAA==.Lilofin:BAAALAADCggICAAAAA==.Lingpigg:BAAALAADCgUIBQAAAA==.Littlefun:BAAALAAECgQICAAAAA==.',Lo='Lokíí:BAAALAAECgMIAwAAAA==.Lorendana:BAAALAADCgEIAQAAAA==.Lothlórien:BAAALAADCgcIDQAAAA==.Loulâ:BAAALAADCgEIAQAAAA==.',Lu='Lulua:BAAALAAECgYICgAAAA==.Lunicor:BAAALAAECgYICQAAAA==.',Ly='Lywyna:BAAALAAECgYICgAAAA==.Lyzea:BAABLAAECoEXAAMOAAgIQhnTBAA0AgAOAAcIYRrTBAA0AgANAAQIEBRoPQAOAQAAAA==.',Ma='Mahoaga:BAAALAADCgcIBwAAAA==.Mamata:BAAALAAECgYICgAAAA==.Mammon:BAAALAAECgEIAQAAAA==.Mandragòr:BAAALAADCgYIBgAAAA==.Maniac:BAABLAAECoEUAAIFAAgIih85BgDvAgAFAAgIih85BgDvAgAAAA==.Maveen:BAAALAAECgcIDwAAAA==.',Mc='Mcpeanuts:BAAALAADCggIDwAAAA==.',Me='Meilena:BAAALAADCgcICwAAAA==.Meliandora:BAAALAAECgYICQAAAA==.Meraxes:BAAALAADCggICAABLAAECgYICgAEAAAAAA==.Merlinboo:BAAALAAECgYICwAAAA==.Merrix:BAAALAAECgIIAgAAAA==.',Mi='Mirya:BAAALAADCgYIBgAAAA==.Mirácúlix:BAAALAAECgYICAAAAA==.',Mo='Monkdefs:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.Morohid:BAAALAAECgMIBQAAAA==.Mortai:BAAALAADCggIDwAAAA==.',Mu='Murakvonriva:BAAALAAECgcIEAABLAAECggIGAACAAMiAA==.Musashi:BAAALAAECgUIBgAAAA==.',My='Myka:BAAALAAECgUIBQAAAA==.Mystiqu:BAAALAAECggICAAAAA==.Mystíco:BAAALAADCggICAAAAA==.',['Má']='Máliá:BAAALAAECgYIDgAAAA==.',['Mê']='Mêersalz:BAAALAADCgIIAgABLAAECggIFAALALMSAA==.',['Mî']='Mîlo:BAAALAAECgYICwAAAA==.',Na='Naela:BAAALAAECgcIDwAAAA==.',Ne='Nefrateti:BAAALAAECgYIDQAAAA==.Nemantica:BAAALAADCgMIAwAAAA==.Neoboomer:BAAALAAECgYIEAAAAA==.Netharia:BAAALAADCggICAAAAA==.',Ni='Niemand:BAAALAAECgYIBwAAAA==.Nirrti:BAAALAAECgMIBQAAAA==.Nitara:BAAALAAECggIBgAAAA==.',No='Nocterra:BAAALAAECgMIAwAAAA==.Norara:BAAALAAECgYIBwAAAA==.Nordesch:BAAALAAECgMIBgAAAA==.Norgar:BAAALAADCgEIAgAAAA==.Noturpal:BAAALAAECgEIAQAAAA==.Nove:BAAALAAECgQIBwAAAA==.',Nu='Nudle:BAAALAAECgMIAwAAAA==.Numpsi:BAAALAAECggIDQAAAA==.Nunnelly:BAAALAADCgcIBwAAAA==.',Od='Oduhr:BAAALAADCgYIBgAAAA==.',Ok='Okara:BAAALAAECgEIAQAAAA==.',On='Onìshi:BAAALAAECgMIBgAAAA==.',Or='Orackel:BAAALAAECgcIEAAAAA==.Orcer:BAAALAAECgUIAwAAAA==.Orâge:BAAALAAECgcICwAAAA==.',Ov='Over:BAAALAADCgcIBwAAAA==.',Pa='Paline:BAAALAAECgMIBAAAAA==.',Pe='Pentagrimm:BAAALAADCgcIBwABLAAECgUIBgAEAAAAAA==.',Pi='Pimkiê:BAAALAADCgYIBgAAAA==.Pisdez:BAAALAAECgMIBAAAAA==.',Pl='Pleitegeier:BAAALAADCgUICAAAAA==.',Py='Pydocar:BAAALAAECggIAwAAAA==.',['Pá']='Pálóc:BAAALAADCgEIAQAAAA==.',Qu='Quazzle:BAAALAAECgMIAwABLAAECgMIBgAEAAAAAA==.',Ra='Radiate:BAAALAAECgIIAgAAAA==.Raeve:BAAALAADCgcIDQAAAA==.Ragebullet:BAAALAAECgcIEAAAAA==.Ramadon:BAAALAAECgMIBQAAAA==.Rasil:BAAALAADCggICAAAAA==.',Re='Remor:BAABLAAECoEWAAMVAAgIOhrJDQCFAgAVAAgIOhrJDQCFAgAQAAUIEw9ETwDzAAAAAA==.Restokupfi:BAAALAADCggICAABLAAECgcIEAAEAAAAAA==.',Rh='Rhainiakassa:BAAALAAECgYIBgAAAA==.Rhainiakdrac:BAAALAADCgQIBAAAAA==.Rhainiaksham:BAAALAADCggICAAAAA==.',Ro='Rommili:BAAALAAECgYICgAAAA==.Rommilii:BAAALAADCgMIAwABLAAECgYICgAEAAAAAA==.Rommiroar:BAAALAADCggIEAAAAA==.Rootcare:BAAALAAECgYIBwAAAA==.Rosafee:BAAALAADCggICAAAAA==.Roxx:BAAALAADCggIFQAAAA==.',['Rè']='Rèdich:BAAALAADCggICAAAAA==.Rèsu:BAAALAADCggIEAAAAA==.',['Ré']='Rénnâ:BAAALAAECggIBgAAAA==.',['Rî']='Rîthara:BAAALAAECgYIBwAAAA==.',Sa='Sanjir:BAAALAAECgcIBwAAAA==.Sarahangel:BAAALAAECgQICQAAAA==.Sarlinaria:BAAALAAECgQICAAAAA==.Sassy:BAAALAAECgIIAgABLAAECgYICQAEAAAAAA==.Sasur:BAAALAAECgMIBQAAAA==.Savo:BAABLAAECoEVAAIPAAgIvAyqLQCkAQAPAAgIvAyqLQCkAQAAAA==.Savook:BAAALAAECggIAgABLAAECggIFQAPALwMAA==.',Sc='Schadrack:BAAALAADCgYIDAAAAA==.Schamanni:BAAALAADCggIDwAAAA==.Schwonklsham:BAAALAAECgMIBQAAAA==.',Se='Senhor:BAAALAADCggICAABLAAECgUIBgAEAAAAAA==.Servas:BAAALAAECgcIDwAAAA==.',Sh='Shadowspawn:BAAALAAECggICgAAAA==.Shadowtoast:BAAALAADCggIDwABLAAECgYICgAEAAAAAA==.Shaps:BAAALAAECgIIAgAAAA==.Shatara:BAAALAAECgYIBgABLAAECggIGAACAAMiAA==.Shedovv:BAAALAAECgYIDwAAAA==.Shenlyen:BAAALAAECgIIAgAAAA==.Shieki:BAABLAAECoEVAAIGAAgI0yEjCQD4AgAGAAgI0yEjCQD4AgAAAA==.Shinlu:BAAALAADCggICgAAAA==.Shoopz:BAAALAAECgYICQAAAA==.Shurá:BAAALAADCggIDAAAAA==.Shyrinu:BAAALAAFFAIIAgAAAA==.',Si='Sillahz:BAAALAADCggIEAAAAA==.Sixerfit:BAAALAADCggICAAAAA==.',Sk='Skulard:BAAALAAECgQIBQAAAA==.Skullion:BAAALAADCgEIAQABLAAECgEIAQAEAAAAAA==.',So='Sohafee:BAAALAADCgYICQAAAA==.Sori:BAAALAADCgYIDgAAAA==.',Ss='Ssenx:BAAALAAFFAIIAgAAAA==.',St='Storchi:BAABLAAECoEYAAIGAAgIbR9iDADUAgAGAAgIbR9iDADUAgAAAA==.Styrja:BAAALAAECggICQAAAA==.Stôrm:BAAALAAECgYIDwAAAA==.',Su='Sunfighter:BAAALAADCgcIBwAAAA==.',Sw='Swiftblâde:BAAALAAECgMIBQAAAA==.',Sy='Sydri:BAAALAADCgYIBgAAAA==.Sylaell:BAAALAAECgMIBQAAAA==.Syola:BAAALAAECgYIBgABLAAFFAMIBQABAF4bAA==.Syrma:BAAALAAECgQIBAAAAA==.Syrâx:BAAALAAECgMIBQAAAA==.',Ta='Ta:BAAALAAECggICAAAAA==.Tabyja:BAAALAADCgUIBQABLAAECgIIAgAEAAAAAA==.Talandra:BAAALAAECgMIBQAAAA==.Taledos:BAAALAAECgIIAgAAAA==.Tanja:BAAALAADCggIDwAAAA==.Taonid:BAAALAAECgYIDQAAAA==.Tarquin:BAAALAAECgIIAgAAAA==.',Te='Tegra:BAAALAAECgYICQAAAA==.Teldarat:BAAALAAECgIIAgAAAA==.Telnas:BAAALAADCggICAAAAA==.',Th='Thandralos:BAAALAADCggICAAAAA==.Thanía:BAAALAAECgYICQAAAA==.Thorog:BAAALAADCgMIAwAAAA==.',Ti='Timbelzwick:BAACLAAFFIEFAAIBAAMIXhszAwDHAAABAAMIXhszAwDHAAAsAAQKgRcAAgEACAhWI2cBACgDAAEACAhWI2cBACgDAAAA.',To='Tocdh:BAAALAAECgYIDQAAAA==.Tolonos:BAAALAAECgYIDgAAAA==.Totdefs:BAAALAAECgYIBgABLAAECggIEwAEAAAAAA==.',Tr='Tristias:BAAALAADCgIIAgAAAA==.Trueno:BAAALAAECgYIDQAAAA==.',Tu='Tulpilein:BAAALAADCggIDgAAAA==.Turco:BAAALAADCggICAAAAA==.',Tw='Twyni:BAAALAAECgYIDAAAAA==.',Ty='Tyride:BAAALAAECgMIBAAAAA==.Tysaleh:BAAALAAECgYIBgAAAA==.Tytós:BAAALAADCgYIDgAAAA==.',['Tá']='Tárus:BAABLAAECoEXAAIRAAgIrh5KCQDhAgARAAgIrh5KCQDhAgAAAA==.',Uk='Ukio:BAAALAAECgMIAwAAAA==.',Ul='Ulinda:BAABLAAECoEXAAIKAAgInRe2CABOAgAKAAgInRe2CABOAgAAAA==.',Us='Uschì:BAAALAADCggIBgAAAA==.',Va='Vaalzari:BAAALAAECgYICQAAAA==.Valuney:BAAALAAECgIIAgAAAA==.Vandul:BAAALAAECgIIAgAAAA==.Vanen:BAAALAAECgcICAAAAA==.',Ve='Ver:BAAALAADCggIDAABLAAECggICgAEAAAAAA==.Versuhl:BAAALAAECgIIAgAAAA==.',Vi='Videl:BAAALAAECgcIEAAAAA==.Vilitch:BAAALAAECgMIAwAAAA==.Viori:BAAALAAECgYICgAAAA==.Viscyria:BAAALAAECgYICwAAAA==.',Vo='Voss:BAABLAAECoEXAAICAAgI2Ry4DQDGAgACAAgI2Ry4DQDGAgAAAA==.',Vu='Vuggi:BAAALAADCgIIAgAAAA==.',Vy='Vyrdris:BAAALAAECgMIBQAAAA==.',['Væ']='Vænøm:BAAALAADCgcIDQAAAA==.',Wa='Waidmann:BAAALAADCggIGwAAAA==.War:BAAALAAFFAIIAgAAAA==.Warklon:BAAALAADCggIDAAAAA==.',Wr='Wrenn:BAAALAAECgYIDwAAAA==.',['Wí']='Wícked:BAAALAADCgYIBgAAAA==.',Xa='Xamana:BAAALAADCggIDwABLAAECgIIAgAEAAAAAA==.',Xy='Xyleng:BAAALAADCggIDwAAAA==.',Ya='Yaven:BAAALAAECgIIAgAAAA==.',Yi='Yiaro:BAAALAAECgUICwAAAA==.',Ys='Ysren:BAAALAADCgcIBwAAAA==.',Yu='Yuna:BAABLAAECoEXAAIWAAgI5h2TBgDXAgAWAAgI5h2TBgDXAgAAAA==.Yuul:BAAALAAECgYICgAAAA==.',Ze='Zelarrin:BAAALAADCgYIDAAAAA==.Zeydra:BAAALAADCgMIBQAAAA==.',Zi='Zizjajim:BAAALAAECgMIAwAAAA==.',Zu='Zuly:BAAALAADCgcICQABLAAECgYIAgAEAAAAAA==.Zulyo:BAAALAAECgYIAgAAAA==.',Zy='Zylaas:BAAALAAECgEIAQAAAA==.',['Æo']='Æonia:BAAALAAECgYIDAAAAA==.',['Æs']='Æsilence:BAAALAADCgUIBQAAAA==.',['Êl']='Êllinar:BAACLAAFFIEHAAIDAAMI5R5MAQAhAQADAAMI5R5MAQAhAQAsAAQKgRgAAgMACAitJZ8DAFADAAMACAitJZ8DAFADAAAA.',['Ód']='Ódién:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end