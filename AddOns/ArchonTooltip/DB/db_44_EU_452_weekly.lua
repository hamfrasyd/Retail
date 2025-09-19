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
 local lookup = {'Shaman-Restoration','Unknown-Unknown','Mage-Arcane','Priest-Shadow','Warlock-Destruction','Warlock-Demonology','Rogue-Assassination','DeathKnight-Frost',}; local provider = {region='EU',realm='Nazjatar',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aelio:BAABLAAECoEaAAIBAAgIfCNaAQAzAwABAAgIfCNaAQAzAwAAAA==.',Ag='Agnessa:BAAALAADCgcIBwAAAA==.',Ai='Aide:BAAALAAECgMIBAAAAA==.Aidonn:BAAALAADCggIDwAAAA==.',Ak='Akarim:BAAALAADCggICAAAAA==.',Al='Alduîn:BAAALAADCgcIBwAAAA==.Alesina:BAAALAADCggIDgAAAA==.Algalon:BAAALAADCgEIAQAAAA==.Alistar:BAAALAADCggICAAAAA==.Aliyaah:BAAALAADCgcIBwAAAA==.Aluria:BAAALAADCgcICAAAAA==.',Am='Amance:BAAALAADCgcIBwAAAA==.Amedys:BAAALAADCgYIBgABLAAECgcIDwACAAAAAA==.',An='Antyo:BAAALAADCgIIAgAAAA==.',Ar='Aragonas:BAAALAAECgYIBgAAAA==.Arthanus:BAAALAADCgQIBAAAAA==.',As='Asahi:BAAALAADCgcIBwABLAAECgIIAgACAAAAAA==.Ascenic:BAAALAAECgYIDAAAAA==.Assalyn:BAAALAADCgYIBgAAAA==.',Az='Azsagi:BAAALAADCggICAAAAA==.',Ba='Badgrandma:BAAALAADCgcIFAAAAA==.Badoinks:BAAALAAECgQIBgAAAA==.Banditorinho:BAACLAAFFIEEAAIDAAMIMhuKAwAdAQADAAMIMhuKAwAdAQAsAAQKgRcAAgMACAhlJS0BAG0DAAMACAhlJS0BAG0DAAAA.Bashaa:BAAALAAECgMIAwAAAA==.',Be='Beardless:BAAALAADCggICAAAAA==.Bevilla:BAAALAADCggICAAAAA==.',Bi='Bilib:BAAALAAECgUIDAAAAA==.Bizou:BAAALAAECgQIBwAAAA==.',Bl='Blxckfire:BAAALAADCgcIBwAAAA==.Blòodheart:BAAALAAECgMIBQAAAA==.',Bo='Boss:BAAALAAECgMIAwAAAA==.',Bu='Bulweí:BAAALAADCgMIAwABLAAECgMIBAACAAAAAA==.',Ca='Caliburn:BAAALAADCgcIDgAAAA==.Capslock:BAAALAADCggICAAAAA==.Cayenne:BAAALAADCggICAAAAA==.',Ch='Chingdr:BAAALAADCggIDwAAAA==.',Cl='Clanz:BAAALAADCgYIBgAAAA==.Clanzì:BAAALAADCggICAAAAA==.',Co='Cody:BAACLAAFFIEJAAIEAAUIKRoyAQB3AQAEAAUIKRoyAQB3AQAsAAQKgRQAAgQACAhlJWYBAGgDAAQACAhlJWYBAGgDAAAA.',Cu='Cullyn:BAAALAADCgcIFQAAAA==.',Cx='Cx:BAAALAADCgcIBwAAAA==.',Da='Dajka:BAAALAAECgYICgAAAA==.Dambledor:BAAALAADCgcIDQAAAA==.',De='Deadfrost:BAAALAADCgQIBAABLAAECgMIBAACAAAAAA==.Decadence:BAAALAAECgcIDgAAAA==.Dedwen:BAAALAADCgYICwAAAA==.Delarosa:BAABLAAECoEVAAMFAAcIvRmdFwAWAgAFAAcIOxidFwAWAgAGAAUIShdDIABnAQAAAA==.Demir:BAAALAAECgYIBgAAAA==.',Di='Digglycupp:BAAALAAECgUICgAAAA==.Dima:BAAALAAECgYIDQAAAA==.',Do='Dorghrom:BAAALAAECgYIDAAAAA==.',Dz='Dzavo:BAAALAAECgYIDQAAAA==.',El='Elana:BAAALAADCgcICAABLAAECgYIBgACAAAAAA==.Ele:BAAALAAECgYIBgAAAA==.Elyna:BAAALAADCgcIBwAAAA==.',Ev='Eviscerake:BAAALAADCgIIAgABLAAECgYICgACAAAAAA==.',Fa='Fafnir:BAAALAAECgcIEAAAAA==.',Fe='Fenlyra:BAAALAAECgYIDQAAAA==.Feregix:BAAALAADCggICwABLAAECgYIDgACAAAAAA==.',Fl='Flintenholzi:BAAALAAECgQICAAAAA==.',Fo='Fonsk:BAAALAAECgIIAgAAAA==.',Fr='Frova:BAAALAAECgUIBwAAAA==.',Fu='Fuu:BAAALAADCgcIBwAAAA==.',['Fî']='Fînntrôll:BAAALAADCgcIBwAAAA==.',Gl='Glaringlight:BAAALAADCggICwAAAA==.',Go='Goldy:BAAALAAECgYICgAAAQ==.',Gu='Gueriseur:BAAALAADCggIDwAAAA==.',['Gô']='Gôrgon:BAAALAAECgYIBwAAAA==.',['Gõ']='Gõrdy:BAAALAADCgcIDgABLAAECgMIBQACAAAAAA==.',Ha='Hadkagan:BAAALAADCggIDgAAAA==.Haiza:BAAALAAECgYIDQAAAA==.Hasard:BAACLAAFFIEIAAIDAAMIAR1GAwAjAQADAAMIAR1GAwAjAQAsAAQKgRgAAgMACAjuJeAAAHUDAAMACAjuJeAAAHUDAAAA.',He='Helix:BAAALAAECgQIBAAAAA==.Helmý:BAAALAAECgMIBQAAAA==.Hennessy:BAAALAAECgMIAwABLAAECgUIBwACAAAAAA==.',Ho='Hotdogpirat:BAAALAAECgMIBAAAAA==.Hotz:BAAALAADCgUIBQAAAA==.',Hy='Hypnotize:BAAALAAECgYIDQABLAAFFAMICAADAAEdAA==.',['Hê']='Hênnêssy:BAAALAAECgUIBwAAAA==.',Il='Ilidarion:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.',Im='Impact:BAACLAAFFIEMAAIHAAUIkxgbAAD7AQAHAAUIkxgbAAD7AQAsAAQKgRQAAgcACAgPJJQBAEgDAAcACAgPJJQBAEgDAAAA.',Ir='Iratus:BAAALAAECgIIAgAAAA==.',Is='Isaliyah:BAAALAAECgEIAQAAAA==.',Ja='Jaegzor:BAAALAADCgcIBwAAAA==.',Jo='Jokard:BAAALAAECgMIAwAAAA==.',['Jä']='Jägernuss:BAAALAAECgcIDgAAAA==.',Ka='Kallolo:BAAALAADCgYIBgAAAA==.Karmiodk:BAAALAAECgYIDgAAAA==.',Ke='Kennylic:BAAALAADCgcICAAAAA==.Kerrok:BAAALAAECgQIBAAAAA==.',Kl='Klaix:BAAALAAECgYICgAAAA==.',Kn='Knaßter:BAAALAAECgMIBQAAAA==.',Ko='Kosmea:BAAALAADCgcIBwAAAA==.',['Kû']='Kûn:BAAALAAECgMIBAABLAAFFAMICAADAAEdAA==.',La='Lahmia:BAAALAADCgEIAQAAAA==.Landuriel:BAAALAADCggICgAAAA==.',Le='Legionofboom:BAAALAADCgUIBQAAAA==.',Li='Lieara:BAAALAAECgMIBQABLAAECgYICgACAAAAAA==.',Lo='Lorethal:BAAALAAECgEIAQAAAA==.',Lu='Lumex:BAAALAADCggICAAAAA==.Lunaarya:BAAALAAECgMIAwAAAA==.',['Lî']='Lîlâ:BAAALAAECgcIEAAAAA==.',['Lû']='Lûcyan:BAAALAADCgIIAQAAAA==.',Ma='Magicpat:BAAALAADCgYIBgAAAA==.Malibuluggen:BAAALAAECgcIEAAAAA==.Maligno:BAAALAAECgYICwAAAA==.Marceldavis:BAAALAADCgcICAAAAA==.Markusrühl:BAAALAADCgMIAQAAAA==.Marron:BAAALAAECgUICgAAAA==.Maéve:BAAALAADCgIIAgAAAA==.',Me='Medoran:BAAALAADCgMIAwAAAA==.',['Má']='Másterpiece:BAAALAADCgYIBgAAAA==.',['Mé']='Méchanceté:BAAALAADCggIDgAAAA==.Méléys:BAAALAADCgYICAAAAA==.',Na='Namir:BAAALAADCgYIBgAAAA==.Namí:BAAALAADCggICwAAAA==.Narfvader:BAAALAADCgcIBwAAAA==.',Ne='Nebligealge:BAAALAAECgcIBwAAAA==.Nexina:BAAALAAECgcIEQAAAA==.Nezrim:BAAALAAECgMIBAAAAA==.',No='Nobódy:BAAALAAECgMIBAAAAA==.Norton:BAAALAADCggICgABLAAECgYIBgACAAAAAA==.Notos:BAAALAAECgcIDwAAAA==.',Nv='Nvieer:BAAALAADCgYIBgAAAA==.',Ny='Nyxana:BAAALAAECgYIBgAAAA==.',Ok='Okmanik:BAAALAADCgYICAAAAA==.',On='Onibi:BAAALAADCgMIAwAAAA==.',Or='Orcshame:BAAALAAECgYICgAAAA==.',Ow='Owlbeback:BAAALAAECgMIAwAAAA==.',Pa='Palalini:BAAALAADCgcIBwAAAA==.Pandala:BAAALAAECgMICgAAAA==.Paranojas:BAAALAADCgcIBwABLAAECgYIBgACAAAAAA==.Pazmonk:BAAALAADCgYIBgAAAA==.Pazmut:BAAALAAECgUIDAAAAA==.',Pr='Prainlock:BAAALAAECgYIDgAAAA==.',['Pà']='Pàz:BAAALAAECgUICAAAAA==.',Qu='Quendulin:BAAALAADCgYIBgAAAA==.',Ra='Rahgam:BAAALAADCggIEAAAAA==.Raiden:BAAALAAECggICAAAAA==.',Re='Rekgar:BAAALAADCgUIBQAAAA==.Remero:BAAALAAECgYIDgAAAA==.',Ri='Rino:BAAALAAECgEIAQAAAA==.',Rn='Rnk:BAAALAADCggIDgAAAA==.',Ro='Roknar:BAAALAADCgcIDAAAAA==.Roodhunter:BAAALAAECgEIAQAAAA==.',Sa='Saiphon:BAAALAAECgIIAgAAAA==.Samueel:BAAALAAECgEIAQAAAA==.Samyjocleo:BAAALAADCgIIAgAAAA==.',Sc='Scalyfurry:BAAALAADCgcIBwAAAA==.Scarletwitch:BAAALAADCgYICwAAAA==.Schâmi:BAAALAAECgMIAwAAAA==.',Se='Selené:BAAALAAECgYICwAAAA==.Sema:BAAALAADCggIDQAAAA==.',Sh='Shadowfire:BAAALAADCggICAAAAA==.Shamsy:BAAALAADCggICAAAAA==.',Sl='Sluddjy:BAAALAAECgMIBQAAAA==.',So='Sollos:BAAALAADCggIEAAAAA==.Sonarok:BAAALAAECgIIBAAAAA==.',St='Steinbart:BAAALAAECgIIAgAAAA==.Steinhorn:BAAALAAECgUICgAAAA==.Stingray:BAAALAADCgcIBwAAAA==.Stormslider:BAAALAADCggICAAAAA==.Straycaz:BAAALAADCgcIBwAAAA==.',Su='Subrealic:BAAALAADCggIDwAAAA==.Sunki:BAAALAAECgYIBgAAAA==.',Sw='Swalie:BAAALAAECgIIAgAAAA==.',Ta='Taargaryen:BAAALAAECgMIAwAAAA==.Tacithia:BAAALAADCgcICAAAAA==.',Th='Thoughts:BAAALAAECgMIAwAAAA==.Throwback:BAAALAADCggIDwAAAA==.Thurok:BAAALAAECgYIBgAAAA==.',Tr='Trenbolon:BAAALAADCgcIDQAAAA==.Triffnix:BAAALAAECgEIAgAAAA==.Tritan:BAAALAADCggICAABLAAECgYIBgACAAAAAA==.',['Tá']='Tázé:BAAALAADCggICAAAAA==.',['Tî']='Tîtânîâ:BAAALAAECgIIAgAAAA==.',['Tø']='Tøpf:BAAALAADCggICAAAAA==.',Uf='Ufganda:BAAALAADCgMIAwAAAA==.',Va='Vandelar:BAAALAADCgcIBwAAAA==.Vanic:BAAALAADCgEIAQAAAA==.Vays:BAAALAADCggIDAAAAA==.',Ve='Veoon:BAAALAAECgYIDQAAAA==.',Vi='Vidre:BAAALAADCggIFAAAAA==.',Vo='Voidforge:BAAALAAECgIIAgAAAA==.Voidlemmiy:BAAALAADCggIFQAAAA==.',Wi='Wizzardy:BAAALAAECggICwAAAA==.',Wr='Wrathbasher:BAAALAAECgUIBwAAAA==.',['Wû']='Wûrstpriest:BAAALAAECggICgAAAA==.',Xy='Xyara:BAACLAAFFIEFAAIIAAMIsh0MAgAlAQAIAAMIsh0MAgAlAQAsAAQKgRgAAggACAjDJecAAHoDAAgACAjDJecAAHoDAAAA.',Xz='Xzen:BAAALAAECgYIDAAAAA==.',Yi='Yiuly:BAAALAADCggIDAAAAA==.',Ym='Ymononthi:BAAALAADCgcIBwAAAA==.',Yu='Yukí:BAAALAAECggICwAAAA==.Yuljana:BAAALAADCgYIBwAAAA==.Yulyvee:BAAALAADCggIDQAAAA==.',Ze='Zeereydk:BAAALAAECgEIAQAAAA==.Zelsor:BAAALAAECgYIDQAAAA==.Zelsór:BAAALAAECgYIBgABLAAECgYIDQACAAAAAA==.',Zh='Zhadá:BAAALAAECgMIBAAAAA==.',Zw='Zwblchen:BAAALAAECgIIAgABLAAECgMIBAACAAAAAA==.',Zy='Zyclô:BAAALAAECggICQAAAA==.',['Zý']='Zýrox:BAAALAADCggIBwAAAA==.',['Çe']='Çecil:BAAALAADCggICAAAAA==.',['Êz']='Êz:BAAALAAECgcIEQAAAA==.Êzy:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end