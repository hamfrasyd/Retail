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
 local lookup = {'Monk-Windwalker','Evoker-Devastation','Unknown-Unknown','Mage-Frost','Paladin-Retribution','Hunter-Marksmanship','Warrior-Arms','Warrior-Fury','Mage-Arcane','Mage-Fire','Hunter-BeastMastery','DemonHunter-Havoc','Priest-Shadow','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Druid-Balance','Druid-Restoration','Monk-Brewmaster','Shaman-Elemental',}; local provider = {region='EU',realm="Kel'Thuzad",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aelluvienne:BAAALAAECgIIAgAAAA==.',Ai='Aiphatron:BAAALAADCgEIAQAAAA==.',Ak='Akraton:BAAALAADCggICAAAAA==.Akróma:BAAALAAECgQIBAAAAA==.',Al='Algalon:BAAALAAECgQIBgAAAA==.Allacaya:BAAALAADCgcIDQAAAA==.Allanea:BAAALAADCgcIBwAAAA==.Alyndriel:BAAALAAECgQIBwAAAA==.',An='Anfalas:BAAALAADCgcICQABLAAECggIGgABANQZAA==.Anthropic:BAAALAAECgYIBgAAAA==.',Ar='Aranae:BAAALAAECgMIAwABLAAECggIGgACAK4fAA==.Aronta:BAAALAAECgYIBgAAAA==.',As='Asdasdk:BAAALAAECgYIDAAAAA==.Assault:BAAALAADCgQIBAAAAA==.',Av='Avetaar:BAAALAADCgMIAwAAAA==.',Ay='Ayutra:BAAALAAFFAIIAgAAAA==.',Ba='Baaltyr:BAABLAAECoEaAAICAAgIrh+0BQDmAgACAAgIrh+0BQDmAgAAAA==.Babak:BAAALAAECggIEAAAAA==.Balur:BAAALAAECgMIAwAAAA==.Balî:BAAALAAFFAIIAgAAAA==.Barlorg:BAAALAADCgYIBgAAAA==.Bayan:BAAALAAECgMIAwABLAAECgMIAwADAAAAAA==.',Be='Beeva:BAAALAADCgUIBQAAAA==.Belicia:BAAALAADCggICAABLAAECggIFwAEAOMkAA==.',Bi='Big:BAAALAADCgYICwAAAA==.Bigbrain:BAAALAAECgMIAwABLAAECggIGgABANQZAA==.Bigmage:BAAALAADCgYIBgAAAA==.Bigwave:BAAALAADCgYIBgAAAA==.',Bo='Bozza:BAAALAADCggICAAAAA==.',Br='Braini:BAAALAADCgYICQABLAAECggIGgABANQZAA==.',Ca='Canondorf:BAAALAAECgcIEwAAAA==.',Ch='Chaneirá:BAAALAADCggICAAAAA==.Charcoal:BAAALAADCgIIAgABLAAECggIGAAFABkcAA==.Cheesecake:BAAALAAECgEIAQAAAA==.Chiku:BAAALAAECgMIBAAAAA==.Chötzli:BAAALAAECgYICgAAAA==.',Ci='Ciroline:BAAALAADCggIEAAAAA==.',Co='Coolekuh:BAAALAAECgcICgAAAA==.',Da='Daleila:BAAALAADCggIDwAAAA==.',De='Debro:BAAALAADCgcICAAAAA==.Deet:BAAALAAECgYIDwAAAA==.Dejay:BAAALAAECgMIAwAAAA==.Demerus:BAAALAADCggIEwAAAA==.Demeya:BAAALAAECgEIAQAAAA==.Demonja:BAAALAAECgYIBgAAAA==.Dentera:BAAALAADCgEIAQABLAAECgYIBgADAAAAAA==.Depletas:BAAALAAECgcIDgAAAA==.',Do='Donnerbräu:BAAALAADCggIDwAAAA==.',Dr='Draggi:BAAALAADCgYIBgAAAA==.Draginoi:BAAALAAECgMIAwAAAA==.Draufgänger:BAAALAAECgcIEAAAAA==.Drfrost:BAAALAAECgYIDgAAAA==.Drument:BAAALAAECgMIAwABLAAECgcIDgADAAAAAA==.Drumont:BAAALAAECgUIBQAAAA==.',Du='Duckdot:BAAALAADCgcIFQAAAA==.',El='Elayne:BAAALAAECgEIAQAAAA==.Eleonoway:BAABLAAECoEVAAIGAAcIvh3kDABZAgAGAAcIvh3kDABZAgAAAA==.',En='Enziano:BAAALAAECgEIAQAAAA==.',Fa='Fabi:BAAALAADCggICAAAAA==.Farugo:BAAALAADCggIDgAAAA==.',Fe='Feiron:BAAALAAECgMIAwAAAA==.Ferrers:BAAALAAECgYIBgAAAA==.',Fi='Fiftys:BAAALAAECgYIDQAAAA==.',Fl='Fluppi:BAAALAAECgIIAgAAAA==.',Fu='Furball:BAAALAAECgMIAwAAAA==.',Ga='Galoc:BAAALAAECgcIEAAAAA==.',Ge='Geno:BAAALAADCgUIBQAAAA==.Georg:BAAALAAECgUIBQAAAA==.',Gi='Gimpelhexe:BAAALAAECgYIDgAAAA==.Gini:BAAALAAECgEIAQAAAA==.',Go='Gono:BAAALAADCgcIDQAAAA==.Gontlike:BAAALAAECgMIAwAAAA==.Gorgó:BAAALAAECgYIBwAAAA==.',Gr='Grolock:BAAALAADCgcICwAAAA==.',Gu='Gumbel:BAAALAADCgcIBwAAAA==.',Ha='Hailmary:BAAALAADCgcICQABLAAECgMIAwADAAAAAA==.Hase:BAAALAAECgEIAQAAAA==.Hatorihanzoo:BAAALAADCgUIBQAAAA==.Haudrauf:BAAALAAECgIIAgAAAA==.Haxil:BAABLAAECoEWAAMHAAgIxBytAgBYAgAIAAgIeRk3EgBaAgAHAAgI4BetAgBYAgAAAA==.',Ho='Horendoss:BAAALAADCgMIAwAAAA==.',Hy='Hyutra:BAABLAAECoEbAAMJAAgIDiFDCQD2AgAJAAgIDiFDCQD2AgAKAAEIShMxDQBGAAABLAAFFAIIAgADAAAAAA==.',['Hè']='Hèllcruiser:BAAALAAECgYICAAAAA==.',['Hê']='Hêndragôn:BAABLAAECoEYAAIFAAgIGRzNFQBlAgAFAAgIGRzNFQBlAgAAAA==.',['Hî']='Hîtme:BAABLAAECoEaAAIBAAgI1BmFBwByAgABAAgI1BmFBwByAgAAAA==.',Il='Ildai:BAAALAADCgQIBAABLAAECggIGgACAK4fAA==.',In='Indathan:BAAALAADCgYIDAAAAA==.Indecorus:BAAALAAECgMIBgAAAA==.Insena:BAABLAAECoEWAAILAAgInBhpGAArAgALAAgInBhpGAArAgAAAA==.',Is='Ischisu:BAAALAAECgEIAQAAAQ==.',['Iø']='Iø:BAAALAADCgcIBwABLAAECgEIAQADAAAAAA==.',Ji='Jinyou:BAABLAAECoEVAAIMAAgIwiGzCAAGAwAMAAgIwiGzCAAGAwAAAA==.',Jo='Jonahs:BAAALAAECgMIBAAAAA==.',['Já']='Jáina:BAAALAAECggICAAAAA==.',Ka='Kailarei:BAAALAAECgYICwABLAAECgcIDgADAAAAAQ==.Kamy:BAAALAADCgcICgAAAA==.Katárina:BAAALAAECggIEAAAAA==.',Kh='Khaliisha:BAAALAADCggICAAAAA==.',Ki='Kinvara:BAAALAAECgMIBAAAAA==.Kiyam:BAAALAAECgMIAwABLAAECgcIDgADAAAAAA==.Kiyane:BAAALAAECgMIBAABLAAECgcIDgADAAAAAA==.Kiyanio:BAAALAAECgYIBgABLAAECgcIDgADAAAAAA==.Kiyanu:BAAALAAECgcIDgAAAA==.',Kn='Knubbe:BAAALAAECggIAgAAAA==.',Ko='Kornexperte:BAAALAADCgQIBAAAAA==.',Ku='Kungfukuh:BAAALAAECggICQAAAA==.',Ky='Kylus:BAAALAADCgcICwAAAA==.',La='Latruen:BAAALAAECgYIBgAAAA==.',Le='Lestarte:BAAALAAECgEIAQAAAA==.Lexx:BAAALAADCgcIDAAAAA==.',Li='Likörchen:BAAALAAECgMIAwAAAA==.Lizzee:BAAALAAECgYICAAAAA==.',Ll='Lloyd:BAAALAAECgYIDgAAAA==.',Lu='Lucrum:BAAALAAECgYICQAAAA==.Lunarii:BAAALAAECgYIBgAAAA==.Lupina:BAAALAADCgcIDgAAAA==.Lusyloo:BAAALAAECgMIAwAAAA==.',['Lí']='Línkin:BAAALAADCgIIAgAAAA==.',Ma='Maragoth:BAAALAADCgcIBwAAAA==.',Me='Meatshield:BAAALAAECgEIAQAAAA==.Meradesch:BAAALAADCggICgABLAAECgMIBAADAAAAAA==.',Mi='Mimiteh:BAAALAAECgYICgAAAA==.',Mo='Monkii:BAAALAAECgYICAAAAA==.Moottv:BAAALAADCgEIAQAAAA==.Morgvomorg:BAAALAAECgMIBAAAAA==.Motte:BAAALAADCgIIAgAAAA==.',Na='Naish:BAABLAAECoEYAAINAAgICCKOBgD5AgANAAgICCKOBgD5AgAAAA==.Naku:BAABLAAECoEXAAMOAAgIyhdCBQAlAgAPAAgIyhdyEgBNAgAOAAgIeg5CBQAlAgABLAAFFAIIAgADAAAAAA==.Narune:BAAALAAECggIDQAAAA==.',Ne='Necromenia:BAAALAAECggIEgAAAA==.Nedbigbi:BAABLAAECoEXAAIQAAgI1xoAEgCNAgAQAAgI1xoAEgCNAgAAAA==.Nekrothar:BAAALAAECgIIAgAAAA==.Neony:BAAALAADCgcIBwAAAA==.',Nh='Nhumrod:BAAALAAECgMIBQAAAA==.',Ni='Nirinia:BAAALAAECgcIBwABLAAECggIGAANAAgiAA==.',No='Noirrion:BAAALAAECggIEwAAAA==.Nomad:BAAALAADCgIIAgAAAA==.',['Ná']='Nádeya:BAAALAAECgEIAQAAAA==.',['Né']='Néváh:BAAALAAECgEIAQAAAA==.',['Nê']='Nêvah:BAAALAAECgMIAwAAAA==.',Or='Originaldrac:BAAALAAECgcIEAAAAA==.',Pa='Paola:BAAALAAECgEIAQAAAA==.',Pe='Pelliox:BAABLAAECoEaAAMRAAgIJyJSBQACAwARAAgIJyJSBQACAwASAAcI/go6KwA9AQAAAA==.Pendarean:BAAALAAECgEIAQAAAA==.',Ph='Phantastic:BAAALAADCgcIDQABLAAECgMIAwADAAAAAA==.Phoebé:BAAALAAECgMIBAAAAA==.',Pr='Prizen:BAAALAAECgMIAwABLAAECggIFgAJAIgdAA==.',['Pø']='Pøstmørtem:BAAALAAECgYIBwAAAA==.',Ra='Rageheart:BAAALAADCgEIAQAAAA==.Raspberry:BAAALAAECgMIBQAAAA==.',Re='Rebbenole:BAAALAAECgYICQAAAA==.',Rh='Rhogata:BAAALAADCggICAAAAA==.',Ri='Rittorn:BAAALAAECggIBQAAAA==.',Ru='Ruhepuls:BAAALAAECgIIAgAAAA==.',['Rü']='Rührfischle:BAAALAADCgEIAQAAAA==.',Sa='Saya:BAAALAADCgEIAQABLAAECgYIBgADAAAAAA==.',Se='Senadraz:BAAALAAECgYIBgAAAA==.Sendhelppls:BAAALAAECgYIBgAAAA==.',Sh='Shadowlîke:BAAALAADCgUIAgABLAADCggICAADAAAAAA==.Shawnee:BAAALAADCgcIBwAAAA==.Sheldor:BAAALAAECgEIAQABLAAECgMIBAADAAAAAA==.Shifthappens:BAAALAAECgcIDgAAAA==.',Si='Sisalinaa:BAAALAADCgcIBwAAAA==.',Sk='Skalaska:BAAALAADCggICAAAAA==.Skalinska:BAAALAADCggICAAAAA==.',Sl='Slieze:BAAALAADCggIEAAAAA==.',Sm='Smokason:BAAALAADCgYIBgAAAA==.',So='Solarius:BAAALAAECgUIBQAAAA==.Solot:BAAALAADCggIDwAAAA==.Sorfilia:BAAALAAFFAIIAwAAAA==.',Sp='Spir:BAAALAAECgcIEwAAAA==.',St='Stardust:BAAALAAECgcIDQAAAA==.Stickét:BAAALAAECgYICQAAAA==.Stárdust:BAAALAADCgUIBQAAAA==.',Su='Sugár:BAAALAADCggIDgABLAAECgMIAwADAAAAAA==.Susano:BAAALAAECgUICAAAAA==.',Sw='Swixxbims:BAAALAAECgcIBwAAAA==.Swixxwins:BAAALAAECggIDQAAAA==.Swürgelchen:BAAALAAECggIEAAAAA==.',Sy='Synnmage:BAABLAAECoEaAAIJAAgIiCB2CgDoAgAJAAgIiCB2CgDoAgAAAA==.',Ta='Taiji:BAAALAADCgYIBwAAAA==.Takao:BAAALAAECgYICQAAAA==.Tamayo:BAAALAAECgEIAQAAAA==.',Te='Terageal:BAAALAAECgIIBAAAAA==.Teresa:BAAALAADCgcIBwAAAA==.',Th='Thorwa:BAAALAAECgUICQABLAAECgYIBgADAAAAAA==.Thylin:BAABLAAECoEXAAITAAgIgh4OBQB9AgATAAgIgh4OBQB9AgAAAA==.Thámek:BAAALAAECgIIAgAAAA==.',To='Tokrika:BAAALAAECgMIAwAAAA==.Toph:BAAALAADCgcIDAAAAA==.',Tu='Tugdil:BAAALAAECgIIAgAAAA==.',Ty='Tyraél:BAAALAAECgYIDgAAAA==.',['Tù']='Tùsk:BAAALAAECgMIBQAAAA==.',Uh='Uhry:BAAALAADCgcIBwAAAA==.',Us='Usô:BAAALAAECgMIAwAAAA==.',Va='Vaney:BAAALAADCgMIBQAAAA==.Vanitas:BAABLAAECoEXAAIEAAgI4yTmAABgAwAEAAgI4yTmAABgAwAAAA==.Vanthyr:BAAALAADCggIDwAAAA==.Varimathris:BAAALAAECgYIDwAAAA==.',Ve='Vellu:BAAALAADCggICwAAAA==.',Vi='Violencé:BAAALAADCgMIAwAAAA==.',Vo='Volthalak:BAACLAAFFIEGAAIQAAMIHRkZAwAKAQAQAAMIHRkZAwAKAQAsAAQKgRgAAhAACAggJSoBAHMDABAACAggJSoBAHMDAAAA.',Vu='Vulcanor:BAAALAAECgEIAQAAAA==.',Wa='Wantanran:BAAALAAECgMIBAAAAA==.',Wh='Whoopie:BAAALAADCgEIAQAAAA==.',Wi='Windgrace:BAAALAADCggIDgAAAA==.Winghaven:BAAALAADCgYIBgAAAA==.',Xe='Xenyos:BAAALAADCgYIBgAAAA==.Xerberi:BAAALAADCgcIDgAAAA==.',Xy='Xyoo:BAAALAAECgIIAgAAAA==.',Yo='Yogibär:BAAALAAECgIIAgAAAA==.Yolojuli:BAAALAAECgEIAQAAAA==.',Yv='Yvarr:BAAALAADCggIBAAAAA==.',Ze='Zelpin:BAAALAAECgEIAQAAAA==.Zent:BAABLAAECoEWAAIJAAgIiB33DwCvAgAJAAgIiB33DwCvAgAAAA==.Zentpala:BAAALAAECgEIAQABLAAECggIFgAJAIgdAA==.Zeppo:BAAALAAECgMIBAAAAA==.',Zi='Zidina:BAABLAAECoEXAAIUAAgISx70CgC0AgAUAAgISx70CgC0AgAAAA==.Zitterfaust:BAAALAAECgYICQAAAA==.',Zo='Zophie:BAAALAADCgQIBAAAAA==.Zorkas:BAAALAAECgMIAQAAAA==.',Zr='Zrada:BAAALAADCggICAAAAA==.',Zs='Zsky:BAAALAAECgMIBAAAAA==.',['Zè']='Zèrry:BAAALAADCggIDAAAAA==.',['Ðe']='Ðean:BAAALAADCggIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end