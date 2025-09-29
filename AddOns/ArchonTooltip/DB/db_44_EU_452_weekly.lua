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
 local lookup = {'Shaman-Restoration','Warlock-Demonology','Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Shaman-Elemental','Paladin-Protection','Paladin-Holy','Mage-Arcane','Mage-Fire','Shaman-Enhancement','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Priest-Holy','Priest-Discipline','Mage-Frost','Druid-Balance','DemonHunter-Havoc','DeathKnight-Frost','Hunter-Marksmanship','Druid-Guardian','Warrior-Protection','Rogue-Outlaw','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Blood',}; local provider = {region='EU',realm='Nazjatar',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abusi:BAAALAAECgMIBAAAAA==.',Ad='Addictive:BAAALAAECgYIBgAAAA==.',Ae='Aelio:BAACLAAFFIELAAIBAAMICR3yDAAGAQABAAMICR3yDAAGAQAsAAQKgTEAAgEACAh/JCsHABoDAAEACAh/JCsHABoDAAAA.',Ag='Agnessa:BAAALAADCgcIBwAAAA==.',Ai='Aide:BAABLAAECoEbAAICAAYIQx1pHgDtAQACAAYIQx1pHgDtAQAAAA==.Aidonn:BAAALAADCggIDwAAAA==.',Ak='Akarim:BAAALAADCggICAAAAA==.Akimoto:BAAALAAECgYIDAAAAA==.',Al='Alduîn:BAAALAADCgcIBwAAAA==.Alesina:BAAALAADCggIDgAAAA==.Algalon:BAAALAAECggIDQAAAA==.Alistar:BAAALAAECgYIDAAAAA==.Aliyaah:BAAALAADCgcIBwAAAA==.Aluria:BAAALAADCgcICAAAAA==.Alurie:BAAALAADCgcIBwABLAADCgcICAADAAAAAA==.',Am='Amance:BAAALAADCgcIBwAAAA==.Amedys:BAAALAADCgYIBgABLAAECgcIGwAEAGQaAA==.Amrasholzi:BAAALAAECgIIAgAAAA==.',An='Antyo:BAAALAADCgIIAgABLAAECgcIHQAFAPEXAA==.',Ar='Aragonas:BAABLAAECoEXAAMBAAgICBajTwDGAQABAAYIORujTwDGAQAGAAMIxgQqowBQAAAAAA==.Argull:BAAALAAECgEIAQAAAA==.Arnjuna:BAAALAADCgYIEQAAAA==.Arthanus:BAAALAADCgQIBAAAAA==.',As='Asahi:BAAALAAECgYIBgABLAAECggIGAAHAOwdAA==.Ascenic:BAABLAAECoEsAAIIAAgIBx6gEQBfAgAIAAgIBx6gEQBfAgAAAA==.Assalyn:BAAALAADCgYIBgAAAA==.',Au='Aufstuhl:BAAALAAECgMIBAAAAA==.',Az='Azsagi:BAAALAADCggICAAAAA==.',Ba='Babossà:BAAALAADCgcICgAAAA==.Badgrandma:BAAALAAECgYICwAAAA==.Badoinks:BAAALAAECgUICQAAAA==.Banditorinho:BAACLAAFFIEUAAIJAAUI7iLABgD7AQAJAAUI7iLABgD7AQAsAAQKgSAAAwkACAieJdYHAEgDAAkACAieJdYHAEgDAAoAAQiOG10YAFIAAAAA.Bashaa:BAAALAAECgQIBwABLAAECggIHwAEAMoYAA==.',Be='Beardless:BAAALAADCggICAAAAA==.Benemuke:BAAALAADCgQIBAAAAA==.Beodar:BAAALAADCgcIBwABLAAECgYICAADAAAAAA==.Betonharry:BAAALAADCgcIBwABLAAECgYIDAADAAAAAA==.Bevilla:BAAALAADCggICAAAAA==.',Bi='Bilib:BAABLAAECoEkAAMBAAgI/BiGMAAsAgABAAgI/BiGMAAsAgALAAcILBMkDwDPAQAAAA==.Bizou:BAAALAAECgYIDwAAAA==.',Bl='Blxckfire:BAAALAADCgcIBwAAAA==.Blòodheart:BAAALAAECgQICQABLAAECgYIBgADAAAAAA==.',Bo='Boss:BAAALAAECgMIAwAAAA==.',Br='Bralf:BAAALAAECgQIBAABLAAECggIJgAMALEgAA==.Brewtocol:BAAALAADCgIIAQABLAAECgYIHAAJAHkgAA==.',Bu='Bulweí:BAAALAAECgIIAgABLAAECgYICwADAAAAAA==.',Ca='Calcifer:BAAALAAECggICAAAAA==.Caliburn:BAAALAAECgMIBwAAAA==.Camille:BAAALAAECggICAAAAA==.Capslock:BAAALAADCggICAAAAA==.Cayenne:BAAALAADCggICAAAAA==.',Ce='Celiniá:BAAALAADCgYIBgABLAAECgcIHQAFAPEXAA==.',Ch='Chingdr:BAAALAAECgYIEAAAAA==.',Ci='Ciri:BAAALAADCgcICwAAAA==.',Cl='Clanz:BAAALAADCgYICwAAAA==.Clanzì:BAAALAADCggICAAAAA==.',Co='Cody:BAACLAAFFIEXAAINAAcItiBpAQBqAgANAAcItiBpAQBqAgAsAAQKgSQAAg0ACAi9Jk4AAJwDAA0ACAi9Jk4AAJwDAAAA.',Cr='Cragfist:BAAALAAECgUIBgAAAA==.',Cu='Cullyn:BAAALAAECgQIBQAAAA==.',Cx='Cx:BAAALAADCgcIBwAAAA==.',Da='Dajka:BAAALAAECgYICgABLAAECgYIHAAJAHkgAA==.Dambledor:BAAALAADCgcIDQAAAA==.Dantalia:BAAALAAECggICAAAAA==.Darksign:BAAALAADCggICAABLAAECgYIFQAOABweAA==.',De='Deadfrost:BAAALAAECgUICAABLAAECgYICwADAAAAAA==.Decadence:BAABLAAECoEmAAIPAAgIER5/DADAAgAPAAgIER5/DADAAgAAAA==.Dedwen:BAAALAADCgYICwAAAA==.Dekadence:BAAALAADCggICAABLAAECggIJgAPABEeAA==.Dekadenz:BAAALAADCggIDgABLAAECggIJgAPABEeAA==.Delarosa:BAABLAAECoEiAAMQAAgIHBtGKgBvAgAQAAgIthpGKgBvAgACAAUISheuQgBAAQAAAA==.Delaroso:BAAALAADCggICAABLAAECggIIgAQABwbAA==.Demir:BAAALAAECgYIEQAAAA==.',Di='Digglycupp:BAABLAAECoEkAAQRAAgIYx1mGACQAgARAAgIWx1mGACQAgASAAYIZha6DQCZAQANAAUI9hnvRACDAQAAAA==.Dima:BAABLAAECoEsAAMTAAgIIRlOLACqAQAJAAgInRWYWQDXAQATAAYIWhpOLACqAQAAAA==.',Dk='Dkx:BAAALAADCgQIBAAAAA==.',Do='Dorghrom:BAABLAAECoEkAAIRAAgICSPeBwAeAwARAAgICSPeBwAeAwAAAA==.Doubt:BAAALAAECggIDgAAAA==.',Dr='Draniél:BAAALAAECgEIAQAAAA==.Dreamhunter:BAAALAADCgQIBQAAAA==.Druiduu:BAAALAADCgIIAgAAAA==.',Du='Dudo:BAAALAADCgMIAwAAAA==.',Dy='Dynam:BAAALAAECgUIBQAAAA==.',Dz='Dzavo:BAAALAAECgYIDwAAAA==.',['Dø']='Dønky:BAAALAADCgcIBwAAAA==.',El='Elana:BAAALAADCggIEQABLAAECggIFwABAAgWAA==.Ele:BAABLAAFFIEFAAIGAAII4yKOFQC5AAAGAAII4yKOFQC5AAAAAA==.Elfili:BAAALAADCggIDAAAAA==.Elyna:BAAALAADCggIDwAAAA==.',Er='Eronax:BAAALAAECgYIBgAAAA==.',Es='Eshanari:BAAALAAECgYICQAAAA==.',Ev='Eviscerake:BAAALAADCgIIAgABLAAECgYIHAAJAHkgAA==.',Ex='Exuro:BAAALAADCgUIBgAAAA==.',Fa='Fafnir:BAABLAAECoEnAAIUAAgIEiO8CAAdAwAUAAgIEiO8CAAdAwAAAA==.',Fe='Fenlyra:BAABLAAECoEtAAIVAAgIah0dKgCSAgAVAAgIah0dKgCSAgAAAA==.Feregix:BAAALAADCggICwABLAAECggIJwAWAI8UAA==.',Fi='Firefly:BAAALAADCgIIAgABLAAECggIJgAPABEeAA==.',Fl='Flintenholzi:BAAALAAECgQICAAAAA==.',Fo='Fonsk:BAAALAAECgYIDgAAAA==.',Fr='Frostí:BAAALAADCgcIDAAAAA==.Frova:BAAALAAECgUIBwABLAAECggILgAPAKojAA==.Fränkthetank:BAAALAADCgUIBQAAAA==.',Fu='Fuffikahba:BAAALAAECgQIBgAAAA==.Fuu:BAAALAAECgEIAQAAAA==.',['Fî']='Fînntrôll:BAAALAADCgcIBwAAAA==.',Gi='Ginmoto:BAAALAAECgEIAQAAAA==.',Gl='Glaringlight:BAAALAADCggICwAAAA==.Glomox:BAAALAADCgcIBwAAAA==.',Go='Goldy:BAAALAAECggIIAAAAQ==.',Gu='Gueriseur:BAAALAAECgYIDQAAAA==.Guldardan:BAAALAADCgQIBAAAAA==.',['Gô']='Gôrgon:BAABLAAECoEZAAMXAAcIaRRSSAB7AQAXAAYIWxRSSAB7AQAFAAYIKBEooAA/AQAAAA==.',['Gõ']='Gõrdy:BAAALAAECgYIBgAAAA==.',Ha='Hadkagan:BAAALAAECgYICAAAAA==.Haiio:BAAALAADCgUIBQAAAA==.Hairuken:BAAALAADCgIIAgAAAA==.Haiza:BAABLAAECoErAAIFAAgIziS+CwAjAwAFAAgIziS+CwAjAwAAAA==.Hasard:BAACLAAFFIEUAAMJAAYILiP5BQAHAgAJAAUIFiX5BQAHAgAKAAEIpRkhBwBXAAAsAAQKgSYAAwkACAgRJq0EAGEDAAkACAgRJq0EAGEDAAoAAQhGHP0YAE0AAAAA.',He='Healie:BAAALAADCgcIDAABLAAECggIFwABAAgWAA==.Helix:BAAALAAECgYICQAAAA==.Helmý:BAAALAAECgcIDAAAAA==.Hennessy:BAAALAAECgQIBAABLAAECggIHgAYACsmAA==.Herechia:BAAALAADCggIDgAAAA==.Herio:BAAALAADCggICAABLAAECggIGQAGAL4YAA==.',Ho='Hotz:BAAALAADCgUIBQAAAA==.',Hy='Hypnotize:BAABLAAECoEZAAIGAAYIXx55OwDtAQAGAAYIXx55OwDtAQABLAAFFAYIFAAJAC4jAA==.',['Hê']='Hênnêssy:BAABLAAECoEeAAIYAAgIKyZsAACEAwAYAAgIKyZsAACEAwAAAA==.',['Hô']='Hôlymôly:BAAALAADCgcIBwAAAA==.',Il='Ilidarion:BAAALAAECgYIBwABLAAECgYICwADAAAAAA==.Iltis:BAAALAAECgYICQAAAA==.',Im='Impact:BAAALAAFFAcIHQAAAQ==.',In='Ine:BAAALAADCggICAABLAAECgYIFQAZAIkbAA==.',Ir='Iratus:BAABLAAECoEYAAMHAAgI7B2/CQC3AgAHAAgI7B2/CQC3AgAEAAYIuAvExwA3AQAAAA==.',Is='Isaliyah:BAABLAAECoEdAAIVAAgIYgurjAB/AQAVAAgIYgurjAB/AQAAAA==.',Ja='Jaegzor:BAAALAADCgcIBwAAAA==.',Jo='Jokard:BAABLAAECoEdAAIEAAgIYhftQgBIAgAEAAgIYhftQgBIAgAAAA==.',['Jä']='Jägernuss:BAABLAAECoEmAAIXAAgIayGdGQCCAgAXAAgIayGdGQCCAgAAAA==.',Ka='Kallolo:BAAALAADCgYIBgAAAA==.Karmiodk:BAABLAAECoEnAAIWAAgIjxS2WgAPAgAWAAgIjxS2WgAPAgAAAA==.',Ke='Keeploving:BAAALAAECgIIAgAAAA==.Kennylic:BAAALAAECgMIAwAAAA==.Kerrok:BAAALAAECgUICgAAAA==.',Kh='Khargrim:BAAALAAECgYIBgAAAA==.',Ki='Killerfrost:BAAALAADCgcIBwAAAA==.',Kl='Klaix:BAABLAAECoEkAAIJAAgIZxQGSwAFAgAJAAgIZxQGSwAFAgAAAA==.',Kn='Knaßter:BAABLAAECoEbAAIaAAgIoxZJBQBTAgAaAAgIoxZJBQBTAgAAAA==.Knister:BAAALAAECgQIBgAAAA==.Knochenklaus:BAAALAAECgMIAwABLAAFFAMICwABAAkdAA==.',Ko='Kopfkaputt:BAAALAAECggIDQAAAA==.Kosmea:BAAALAADCgcIBwAAAA==.',['Kû']='Kûn:BAAALAAECgYICwABLAAFFAYIFAAJAC4jAA==.',La='Lahmia:BAAALAADCgIIAgAAAA==.Landuriel:BAAALAADCggIDwAAAA==.Laraelva:BAAALAADCgMIAwAAAA==.',Le='Legionofboom:BAAALAADCgUIBQAAAA==.',Li='Lieara:BAABLAAECoEcAAIJAAYIeSAvRwASAgAJAAYIeSAvRwASAgAAAA==.',Lo='Lorethal:BAAALAAECgYICAAAAA==.',Lu='Lumex:BAAALAADCggICAABLAAECggIFgAVAAcgAA==.Lunaarya:BAAALAAECgMIAwAAAA==.',['Lî']='Lîlâ:BAAALAAECgcIEAAAAA==.',['Lû']='Lûcyan:BAAALAADCgIIAQAAAA==.',Ma='Maghara:BAAALAADCgEIAQAAAA==.Magicpat:BAAALAADCgYIBgAAAA==.Malibuluggen:BAABLAAECoEXAAIBAAgIDRZPPgD8AQABAAgIDRZPPgD8AQAAAA==.Maligno:BAABLAAECoEbAAMQAAgITBDRRwDtAQAQAAgITBDRRwDtAQACAAMIOwdpbgCDAAAAAA==.Marceldavis:BAAALAADCggIFwAAAA==.Markusrühl:BAAALAAECgMIAwAAAA==.Marlow:BAAALAAECgYICQAAAA==.Marron:BAABLAAECoEkAAIBAAgIyxncKgBDAgABAAgIyxncKgBDAgAAAA==.Mastamax:BAAALAADCggICAAAAA==.Maéve:BAAALAADCgIIAgAAAA==.',Me='Medoran:BAAALAADCgMIAwAAAA==.',Mi='Mib:BAAALAAECggICQAAAA==.Miga:BAAALAAECgYIBgAAAA==.Minass:BAAALAADCgEIAQAAAA==.',Mo='Montylic:BAAALAADCgUIBQAAAA==.',My='My:BAAALAAECggICAAAAA==.',['Má']='Másterpiece:BAAALAADCgYIBgAAAA==.',['Mé']='Méchanceté:BAAALAAECgEIAQAAAA==.Méchant:BAAALAAECgcIDAAAAA==.Méléys:BAAALAADCggIFwAAAA==.',Na='Namir:BAAALAADCgYIBgAAAA==.Namí:BAAALAAECggIEwAAAA==.Narfvader:BAAALAADCgcIBwAAAA==.Nataschá:BAAALAAECggIBwAAAA==.Naturdünger:BAAALAAECgYICQABLAAECgYIDAADAAAAAA==.',Ne='Nebligealge:BAAALAAECgcIEQAAAA==.Nenuky:BAAALAADCgcIBwAAAA==.Nexina:BAABLAAECoEoAAIbAAgIMSGACQCvAgAbAAgIMSGACQCvAgAAAA==.Nezrim:BAABLAAECoEYAAIVAAgIWBeqRwAhAgAVAAgIWBeqRwAhAgAAAA==.',Ni='Nikka:BAAALAADCgcIDQAAAA==.',No='Nobódy:BAAALAAECgYICwAAAA==.Norton:BAAALAAECgcIBwABLAAECggIFwABAAgWAA==.Notoriousp:BAAALAAECgYIBgABLAAFFAYIFAAJAC4jAA==.Notos:BAABLAAECoEbAAIEAAcIZBq0YwDzAQAEAAcIZBq0YwDzAQAAAA==.',Nv='Nvieer:BAAALAADCgYIBgAAAA==.',Ny='Nyxana:BAAALAAECgYIEgAAAA==.Nyzzethree:BAAALAADCggIDgAAAA==.',Ok='Okmanik:BAAALAAECgUICgAAAA==.',On='Onibi:BAAALAADCgMIAwAAAA==.',Or='Orcshame:BAABLAAECoEUAAQBAAYIFRi9cQBqAQABAAUIwBm9cQBqAQAGAAMInx7IeAAOAQALAAMI2RNEHgCsAAAAAA==.',Ow='Owlbeback:BAAALAAECgYIDQAAAA==.',Pa='Palalini:BAAALAAECgYIBgAAAA==.Pandala:BAABLAAECoEYAAIcAAgI+hxSEAB7AgAcAAgI+hxSEAB7AgAAAA==.Paranojas:BAAALAADCggIDgABLAAECggIFwABAAgWAA==.Pazmonk:BAAALAADCgYIBgAAAA==.Pazmut:BAACLAAFFIEGAAIJAAII/h0bJAC4AAAJAAII/h0bJAC4AAAsAAQKgRsAAgkACAgfIDYbANQCAAkACAgfIDYbANQCAAAA.Pazz:BAAALAAECgQIBwAAAA==.',Pe='Petmebaby:BAAALAAECgYICwAAAA==.',Pr='Prainlock:BAABLAAECoEmAAQMAAgIsSAoAgADAwAMAAgIsSAoAgADAwAQAAgIeBrCLABjAgACAAIIMwtreABfAAAAAA==.',Py='Pyrana:BAAALAAECgIIAgAAAA==.',['Pà']='Pàz:BAAALAAFFAIIAwAAAA==.',Qu='Quendulin:BAAALAADCgcIDAAAAA==.',Ra='Rafik:BAAALAAECgYIDgAAAA==.Rahgam:BAAALAAECgYIDAAAAA==.Raiden:BAAALAAECggICAAAAA==.Raidlighter:BAAALAAECgYIBwAAAA==.',Re='Rekgar:BAAALAADCgUIBQAAAA==.Remero:BAAALAAECgYIDgAAAA==.',Ri='Rino:BAABLAAECoEWAAIZAAcIWw0cPQBKAQAZAAcIWw0cPQBKAQAAAA==.',Rn='Rnk:BAAALAADCggIDgAAAA==.',Ro='Roknar:BAAALAADCgcIDAAAAA==.Rolexronny:BAAALAADCgcICQAAAA==.Roodhunter:BAAALAAECgEIAQAAAA==.',['Rí']='Ríddîck:BAAALAADCgYIBgAAAA==.',Sa='Saiphon:BAAALAAECgYIEgABLAAECgcIBwADAAAAAA==.Samueel:BAAALAAECgEIAQAAAA==.Samyjo:BAAALAAECggIEwAAAA==.Samyjocleo:BAAALAADCgIIAgAAAA==.Sango:BAAALAADCggICAABLAAECggIEwADAAAAAA==.Sauphon:BAAALAAECgcIBwAAAA==.',Sc='Scalyfurry:BAAALAADCgcIBwAAAA==.Scarletwitch:BAAALAAECgIIAQAAAA==.Schâmi:BAAALAAECgYIDwAAAA==.Scorpor:BAAALAADCgYIBgAAAA==.',Se='Seleene:BAAALAAECggICAAAAA==.Selené:BAABLAAECoErAAIVAAgITiJkHADXAgAVAAgITiJkHADXAgAAAA==.Sema:BAAALAADCggIGgAAAA==.Senzwblchen:BAAALAAECgYIDAAAAA==.',Sh='Shadowfire:BAAALAAECgYICgAAAA==.Shadowsteal:BAAALAADCgYIBgAAAA==.Shamidami:BAAALAAECggIAgAAAA==.Shamsy:BAAALAADCggICAAAAA==.Shokulà:BAAALAADCggICwAAAA==.Shottra:BAAALAAECgYICwABLAAECgcIEQADAAAAAA==.',Sl='Sluddjy:BAAALAAECgMIBQAAAA==.',Sn='Snicki:BAAALAADCgUIBQAAAA==.',So='Sollos:BAAALAAECggIDgAAAA==.Sonarok:BAAALAAECggIEwAAAA==.',Sp='Spirit:BAAALAADCgcIDgAAAA==.',St='Steinbart:BAAALAAECgcICwAAAA==.Steinhorn:BAABLAAECoEcAAIYAAgI8iFJAgAZAwAYAAgI8iFJAgAZAwAAAA==.Stingray:BAAALAADCgcIBwAAAA==.Straycaz:BAAALAAECgMIAwAAAA==.',Su='Subrealic:BAAALAADCggIDwAAAA==.Sunki:BAABLAAECoElAAIUAAgIQRdLJwAFAgAUAAgIQRdLJwAFAgAAAA==.',Sw='Swalie:BAAALAAECgYIDwAAAA==.',Ta='Taargaryen:BAAALAAECgQICAAAAA==.Tacithia:BAAALAADCgcICAAAAA==.Taripa:BAAALAAECgYIBgAAAA==.Tarotar:BAAALAADCgEIAQAAAA==.',Th='Thoughts:BAAALAAECgMIAwAAAA==.Throrin:BAAALAAECgMIAwAAAA==.Throwback:BAAALAAECgIIAgAAAA==.Thurok:BAAALAAECgYIBgAAAA==.',Ti='Tigglyluff:BAAALAADCggICAABLAAECggIJAARAGMdAA==.',To='Totem:BAAALAAECggIDwAAAA==.',Tr='Trenbolon:BAAALAAECgQIBAAAAA==.Triffnix:BAAALAAECgEIBAAAAA==.Tritan:BAAALAADCggICAABLAAECggIFwABAAgWAA==.',Ts='Tsaroth:BAAALAADCggIEAAAAA==.',Tu='Tudos:BAAALAAECgIIAgAAAA==.',['Tá']='Tázé:BAAALAADCggICAAAAA==.',['Tî']='Tîtânîâ:BAABLAAECoEWAAMHAAcITxLzKAB6AQAHAAcILBLzKAB6AQAEAAQIlA4I8gDaAAAAAA==.',['Tø']='Tøpf:BAAALAAECgYIDAAAAA==.',Uf='Ufganda:BAAALAADCgMIAwAAAA==.',Un='Unsmash:BAAALAADCggICAAAAA==.',Va='Vandelar:BAAALAADCgcIBwAAAA==.Vanic:BAAALAADCggICQAAAA==.Vankill:BAAALAADCggICAABLAAECggIFwABAAgWAA==.Vays:BAABLAAECoEUAAIJAAYIfRszUQDxAQAJAAYIfRszUQDxAQAAAA==.',Ve='Velyxa:BAAALAAECggICAAAAA==.Veoon:BAABLAAECoEtAAIdAAgIyiD1BQDvAgAdAAgIyiD1BQDvAgAAAA==.',Vi='Vidre:BAAALAADCggIFAAAAA==.Vildred:BAAALAADCgYIBgAAAA==.Viral:BAAALAAECggICAAAAA==.',Vo='Voidforge:BAAALAAECgMIBQAAAA==.Voidlemmiy:BAAALAAECgMICgAAAA==.Voidserra:BAAALAAECgQIAwAAAA==.Volnoon:BAAALAAECgYIBgAAAA==.',Wi='Wizzardy:BAABLAAECoEpAAIJAAgI0yBkHwDAAgAJAAgI0yBkHwDAAgAAAA==.',Wo='Woaini:BAAALAAECgMIAwAAAA==.',Wr='Wrathbasher:BAABLAAECoEZAAIGAAgIvhhDKQBKAgAGAAgIvhhDKQBKAgAAAA==.',['Wû']='Wûrstdh:BAAALAAECggIBwAAAA==.Wûrstpriest:BAABLAAECoEXAAINAAgIlBNpKwAIAgANAAgIlBNpKwAIAgAAAA==.',Xy='Xyara:BAACLAAFFIERAAMWAAUI1B4BBwDhAQAWAAUI1B4BBwDhAQAdAAEI1gxLEQA6AAAsAAQKgTAAAxYACAhBJrUFAF4DABYACAhBJrUFAF4DAB0ACAiDGgAAAAAAAAAA.',Xz='Xzen:BAABLAAECoEgAAIFAAcIMRtGUADvAQAFAAcIMRtGUADvAQAAAA==.',Yi='Yiuly:BAAALAADCggIDQAAAA==.',Ym='Ymononthi:BAAALAADCgcIBwAAAA==.',Yu='Yuca:BAAALAADCggIEAAAAA==.Yukí:BAACLAAFFIEFAAIcAAII0wrMDgCLAAAcAAII0wrMDgCLAAAsAAQKgSMAAhwACAiIHQcMALgCABwACAiIHQcMALgCAAAA.Yuljana:BAAALAADCgYIBwAAAA==.Yulyvee:BAAALAAECgYIBgAAAA==.',Yv='Yvéss:BAAALAAECggICAAAAA==.',Ze='Zedmain:BAAALAAECggICgAAAA==.Zeereydk:BAABLAAECoEcAAIWAAgIgR8NLACcAgAWAAgIgR8NLACcAgAAAA==.Zelso:BAAALAAECgYIEwABLAAECgYIFQAOABweAA==.Zelsor:BAABLAAECoEVAAIOAAYIHB67MgDkAQAOAAYIHB67MgDkAQAAAA==.Zelsór:BAAALAAECgYIEQABLAAECgYIFQAOABweAA==.',Zh='Zhadá:BAABLAAECoEbAAIUAAYIOhOLRwBiAQAUAAYIOhOLRwBiAQAAAA==.',Zw='Zwblchen:BAAALAAECgIIAgABLAAECgYIDAADAAAAAA==.Zwiderwurz:BAAALAAECgYIBgAAAA==.Zwiderwurzn:BAAALAADCgUIBQAAAA==.',Zy='Zyclô:BAABLAAECoEbAAIBAAYItRKYfQBNAQABAAYItRKYfQBNAQAAAA==.',['Zý']='Zýrox:BAAALAADCggIBwAAAA==.',['Æs']='Æsilara:BAAALAADCgEIAQAAAA==.',['Æt']='Æther:BAAALAADCgcICQAAAA==.',['Çe']='Çecil:BAAALAADCggICAAAAA==.',['Êz']='Êz:BAABLAAECoEoAAQBAAgIPyFKEQDJAgABAAgIPyFKEQDJAgAGAAYIlgyJZgBRAQALAAEIsAjPJAA0AAAAAA==.Êzy:BAAALAADCggICAAAAA==.Êzzy:BAAALAAECggICAAAAA==.',['În']='Îngwa:BAAALAAECggIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end