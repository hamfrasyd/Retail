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
 local lookup = {'Priest-Shadow','Unknown-Unknown','DemonHunter-Havoc','Warrior-Arms','Evoker-Devastation','Mage-Arcane','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Druid-Feral','Warrior-Fury','DeathKnight-Frost','DeathKnight-Unholy','Mage-Frost','Hunter-BeastMastery','DeathKnight-Blood','Druid-Restoration','Hunter-Marksmanship','Shaman-Enhancement','Priest-Holy','Shaman-Restoration','Mage-Fire','Rogue-Assassination','Rogue-Subtlety',}; local provider = {region='EU',realm='Lordaeron',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abegeh:BAAALAAECgEIAgAAAA==.Abgsh:BAAALAADCggICAAAAA==.',Ad='Adalfuchs:BAAALAADCggIBwAAAA==.Adalgrip:BAAALAADCgIIAQAAAA==.Adalwyn:BAAALAAECgYIDQAAAA==.Addblockerin:BAAALAADCgYIBgAAAA==.Adeliná:BAAALAADCgcICgAAAA==.',Ae='Aeliora:BAAALAADCggIDgAAAA==.Aerdaras:BAAALAAECgMIAwABLAAECggIFQABAEcYAA==.Aerion:BAAALAADCggIFAAAAA==.',Ag='Agura:BAAALAAECgMIBAAAAA==.',Ak='Akrinara:BAAALAAECgYIDwAAAA==.',Al='Alamea:BAAALAAECgUIBgAAAA==.Alegrion:BAAALAAECgYIDwAAAA==.Alicyâ:BAAALAAECgMIAwABLAAECgYICQACAAAAAA==.Alinya:BAAALAADCgYIBgAAAA==.Alythia:BAAALAADCggIHwABLAAECgMIAwACAAAAAA==.',Ao='Aowê:BAAALAAECgMIAwAAAA==.',Ar='Arcaneo:BAAALAADCgIIAgABLAAECggIFwADABoiAA==.Arkturus:BAAALAADCgcIBwAAAA==.Arombolosch:BAAALAADCgEIAQAAAA==.Arrgonaut:BAABLAAECoEWAAIEAAgIOiLgAAAHAwAEAAgIOiLgAAAHAwAAAA==.Artaíos:BAAALAAECggICQAAAA==.Artimos:BAAALAADCggIEQAAAA==.',As='Asgardt:BAAALAAECgYICgABLAAECggIGwAFAOkVAA==.Ashàyà:BAAALAAECgcIDQAAAA==.Asmodk:BAAALAADCgcIDQABLAAECgYIDQACAAAAAA==.Asmonk:BAAALAAECgYIDQAAAA==.Asmorg:BAAALAADCggICAABLAAECgYIDQACAAAAAA==.Asthon:BAAALAADCggICAABLAAFFAIIAgACAAAAAA==.Astraja:BAAALAADCggICAAAAA==.',At='Atenuiel:BAAALAAECggICQAAAA==.Atterian:BAAALAAECgEIAQAAAA==.',Au='Augustinos:BAAALAADCgcIAwAAAA==.Aurok:BAAALAADCggIEAAAAA==.',Av='Avariss:BAAALAAECgEIAgAAAA==.',Az='Azâzêl:BAAALAAECgMIBQAAAA==.',Ba='Baecon:BAAALAAECgMIAwAAAA==.',Be='Begur:BAAALAADCgcIDgAAAA==.Beldan:BAAALAAECgMIBgAAAA==.',Bi='Bimm:BAAALAADCggIEAABLAAECgMIBwACAAAAAA==.',Bl='Blaueslicht:BAAALAAECgEIAQAAAA==.Bluekay:BAAALAAECgEIAQAAAA==.Blutmacht:BAAALAAECgYIDAAAAA==.Bláckearth:BAAALAAECgIIBAAAAA==.',Bo='Borkar:BAAALAADCgcIBwAAAA==.',Br='Bralrus:BAAALAADCgcIBwAAAA==.Brítneyfears:BAAALAADCgMIAwAAAA==.',Bu='Bukela:BAAALAAECgMIAwAAAA==.Bullwark:BAAALAAECgMIAwAAAA==.',Ca='Caraniera:BAAALAAECgYIBgAAAA==.Carramba:BAAALAAECgMIAwAAAA==.Cazh:BAAALAAECgEIAQAAAA==.',Ce='Ceabela:BAAALAADCgcIBwABLAADCggICgACAAAAAA==.',Ch='Chade:BAAALAAECgUIBwABLAAECggIFgAGAGEfAA==.Cheeseman:BAAALAADCgcIBwAAAA==.Chester:BAAALAADCggICAAAAA==.Chinni:BAAALAAECgUIBAAAAA==.Chiuvana:BAAALAADCggIFgAAAA==.Chrisvôltiâ:BAAALAAECgcIBwAAAA==.',Ci='Ciilay:BAAALAAECgYIDAAAAA==.Cila:BAAALAADCggIFgAAAA==.Ciryon:BAABLAAECoEWAAIGAAgIYR/OCwDZAgAGAAgIYR/OCwDZAgAAAA==.',Cl='Cleganer:BAAALAADCgQIBAAAAA==.',Co='Coolibri:BAAALAAECgYIDwAAAA==.',Cr='Crazyspirit:BAAALAAECgQIBwAAAA==.Crewel:BAAALAADCggIFQAAAA==.Cristine:BAAALAADCgYIAwAAAA==.Crowdy:BAAALAAECgYICAAAAA==.',Cy='Cyress:BAAALAADCggIDAAAAA==.',['Câ']='Câlista:BAAALAAECgEIAgAAAA==.',Da='Dagor:BAAALAAFFAIIAgAAAA==.Dakotá:BAAALAAECgYIDAABLAAFFAIIAgACAAAAAA==.Daliasis:BAAALAAECgIIBAAAAA==.Damocles:BAAALAAECgIIAgAAAA==.Daramuur:BAAALAAECgMIAwAAAA==.Darkfury:BAAALAADCgcIBwAAAA==.',De='Death:BAAALAAECgEIAQAAAA==.Desdemonía:BAAALAADCggIDwAAAA==.Devoto:BAAALAAECggIBgAAAA==.',Di='Diridari:BAAALAADCgQIBAAAAA==.',Dk='Dkayo:BAAALAAECgIIAwAAAA==.',Dn='Dna:BAAALAAECgYICQAAAA==.Dnaidkit:BAAALAADCgIIAgAAAA==.Dnalock:BAAALAAFFAIIAgAAAA==.',Do='Dopeleler:BAAALAAFFAEIAQAAAA==.Dowjoens:BAAALAAECgYIBwAAAA==.Doyavexony:BAAALAAECgEIAgAAAA==.',Dr='Draag:BAAALAADCgQIBgAAAA==.Dracar:BAAALAADCggIDwAAAA==.',Ds='Dsync:BAAALAADCgIIAwAAAA==.',Du='Dunkoro:BAAALAADCggIFwABLAAECgYIDwACAAAAAA==.',['Dâ']='Dârkrevenge:BAAALAAECgEIAgAAAA==.',Ed='Edvin:BAAALAADCgQIBAAAAA==.',El='Eledeath:BAAALAADCgEIAQABLAAECgYIBwACAAAAAQ==.Elfigos:BAAALAAECgYICQAAAA==.Eligos:BAAALAADCgYICAAAAA==.Elung:BAAALAADCggICgAAAA==.Elysîon:BAAALAADCgUICQAAAA==.',Em='Emriss:BAAALAAECgMIAwAAAA==.',En='Entertaîn:BAABLAAECoEXAAIDAAgIGiKsDADSAgADAAgIGiKsDADSAgAAAA==.Envinya:BAAALAAECgYICQAAAA==.',Ep='Ephistod:BAAALAADCgcIBwAAAA==.',Ev='Even:BAAALAADCgIIAgAAAA==.Eventide:BAAALAAECgYICQAAAA==.Evokadó:BAAALAADCggIDQAAAA==.',Fa='Fabio:BAAALAAECgYIDAAAAA==.Fairie:BAAALAAECgIIAwAAAA==.',Fe='Feelya:BAAALAADCgcIFgAAAA==.Feeni:BAAALAAECgEIAQAAAA==.Feini:BAAALAAECggIEwABLAAFFAMIBQAHAHYfAA==.Fel:BAABLAAECoFlAAQIAAgIXiauAAB/AwAIAAgIXiauAAB/AwAJAAEI0CL1JABhAAAKAAIISyL2TQBZAAAAAA==.Felay:BAAALAAECgUICQAAAA==.Felipa:BAABLAAECoEWAAILAAgIBBbpBQBTAgALAAgIBBbpBQBTAgAAAA==.Femdomlover:BAAALAADCgcIDQAAAA==.Fentura:BAAALAAECgMIAwAAAA==.',Fi='Fibiane:BAAALAADCggICAAAAA==.Fireball:BAAALAAECgYIBwABLAAECgYIDAACAAAAAA==.',Fl='Flocke:BAAALAAECgYICQAAAA==.Floristika:BAAALAAECgMIAwAAAA==.Flows:BAAALAAECgYICAAAAA==.',Fo='Formops:BAAALAADCgcIBgAAAA==.Forreel:BAAALAADCgEIAQAAAA==.Forrockz:BAAALAADCgYIBwAAAA==.',Fu='Fugurus:BAAALAAECgEIAQAAAA==.',Ga='Gamakichi:BAAALAADCgIIAgAAAA==.',Gh='Ghostbladé:BAAALAAECgUIDQAAAA==.',Gi='Ginkoro:BAAALAAECgIIBAAAAA==.',Go='Goodnìght:BAAALAADCggIFgAAAA==.Gorgasch:BAAALAADCgYIBgAAAA==.Gorlox:BAAALAAECgEIAgAAAA==.Goukai:BAAALAAECgYIDwAAAA==.',Gr='Gramor:BAAALAAECgIIAwAAAA==.Grinds:BAAALAAECggIEAAAAA==.',Ha='Haniel:BAAALAADCgYIBgAAAA==.Harmony:BAAALAADCgcIBwAAAA==.Harok:BAAALAADCggIBwAAAA==.Hatori:BAAALAAECgEIAQAAAA==.',He='Healomo:BAAALAAECgcIEQAAAA==.Heiligerbimm:BAAALAAECgMIBwAAAA==.Hepatitís:BAAALAAECgIIAgAAAA==.Hexoduz:BAAALAAECgYICgAAAA==.Heyo:BAAALAAECgMIAwAAAA==.',Ho='Hogri:BAAALAAECgMIAwAAAA==.Holyrose:BAAALAAECgYICQAAAA==.',Hy='Hyolmyr:BAAALAADCggICAAAAA==.',['Hä']='Hänk:BAAALAADCgYIBgAAAA==.',Il='Ilell:BAAALAAECgYIDwAAAA==.Illidana:BAAALAAECgYICAAAAA==.',Im='Immortâl:BAAALAAECgYIDAAAAA==.',In='Innovindils:BAABLAAECoEbAAIMAAgIryCSBwD8AgAMAAgIryCSBwD8AgAAAA==.',Iq='Iqo:BAAALAADCgcIEQAAAA==.',Ir='Ironwill:BAAALAADCggIEwAAAA==.Irvíne:BAAALAAECgYIDwAAAA==.',It='Itsuki:BAAALAADCgcIBwAAAA==.',Ja='Jannâ:BAAALAAECgYICgAAAA==.',Jo='Joachim:BAAALAADCgcIBwABLAAECgYIDwACAAAAAA==.Jormungandr:BAAALAAECgIIAwAAAA==.Jormungåndr:BAAALAADCgcIBwAAAA==.',Ju='Juani:BAAALAAECgQIBAAAAA==.Julién:BAAALAAECgQIBwAAAA==.Junii:BAAALAAECgYICgAAAA==.Junischnee:BAAALAADCggICAAAAA==.',['Jâ']='Jâîná:BAAALAADCggICAAAAA==.',Ka='Kaboohm:BAAALAAECgIIAgAAAA==.Kalachakra:BAAALAADCggIDgAAAA==.Kaliana:BAAALAAECgcICwABLAAECgcIDQACAAAAAA==.Kaltara:BAAALAADCgcIBwAAAA==.Kalvara:BAAALAAECgYIDwAAAA==.Karamnor:BAAALAAECgUIBgAAAA==.Karrazz:BAAALAAECgEIAQAAAA==.',Ke='Kerah:BAAALAAECgEIAgAAAA==.Kerimi:BAAALAAECgYICQAAAA==.Kerotek:BAAALAAECgYICQAAAA==.',Kh='Khartok:BAAALAAECgYIBwAAAA==.Khorag:BAABLAAECoEXAAMNAAgIxyGoCwDTAgANAAgIrSGoCwDTAgAOAAMIRh+1IwDKAAAAAA==.Khron:BAAALAADCgYIBgAAAA==.',Ki='Kinki:BAAALAADCgMIAwAAAA==.Kire:BAAALAAECgYICgAAAA==.',Kl='Klokra:BAAALAADCggICAAAAA==.',Kn='Kneffus:BAAALAADCgcIDQAAAA==.',Ko='Kotalkahn:BAAALAADCgcICgAAAA==.',Kr='Kravok:BAAALAADCgcIBwAAAA==.Kremer:BAAALAAECgYIBgABLAAECggICQACAAAAAA==.Krilon:BAAALAADCgYIBgAAAA==.Krisiz:BAAALAADCgcIBwAAAA==.Kritikel:BAAALAAECggICAAAAA==.',['Kâ']='Kâiros:BAAALAADCgcIBwAAAA==.',La='Lanadelslay:BAAALAAECgYIDwAAAA==.Lavinia:BAAALAAECgMICAAAAA==.',Le='Leeviatan:BAABLAAECoEbAAIFAAgI6RXlDABMAgAFAAgI6RXlDABMAgAAAA==.Leilianne:BAAALAADCgYIBgAAAA==.Leni:BAAALAADCgcICQAAAA==.Lerasol:BAAALAADCggICAAAAA==.',Li='Lilypierce:BAAALAAECgIIAgAAAA==.Lisanda:BAAALAAECggIBgAAAA==.',Lo='Lockout:BAAALAAECggICAABLAAFFAQICwAHAE8bAA==.Lophelia:BAAALAAFFAIIAgAAAA==.',Lu='Luccifera:BAABLAAECoEVAAMPAAgIiBy2CgA0AgAPAAcIUB22CgA0AgAGAAcIRBPnKwDWAQAAAA==.Luiquinnade:BAAALAAECgYICQAAAA==.',Ly='Lycanroc:BAAALAADCgYIBgAAAA==.Lythia:BAAALAADCgcIDgAAAA==.',Ma='Makkarroni:BAAALAAECggIDwAAAA==.Malgorr:BAACLAAFFIEFAAIQAAMITxYsAgANAQAQAAMITxYsAgANAQAsAAQKgRgAAhAACAibJK0BAGIDABAACAibJK0BAGIDAAAA.Marco:BAAALAAECgUIBAABLAAECgYIDwACAAAAAA==.Marz:BAAALAADCggIFQAAAA==.',Mc='Mcmatyss:BAAALAAECgEIAQAAAA==.',Me='Menphina:BAAALAADCggICQAAAA==.Merieke:BAAALAAECgYIDgAAAA==.Merlinx:BAAALAADCggIFgAAAA==.',Mh='Mhystery:BAAALAADCggICAAAAA==.',Mi='Mightydk:BAABLAAECoEYAAMNAAgIlQ10RwBqAQANAAgIWwx0RwBqAQARAAEIxCOGHABfAAAAAA==.Minato:BAAALAADCgMIAwAAAA==.Miwou:BAAALAADCgYIBgAAAA==.',Mo='Monihunt:BAAALAAECgYIBwAAAA==.',Mu='Mulingor:BAAALAAECgIIBAAAAA==.Munyoth:BAAALAADCgYICQAAAA==.',My='Mylento:BAAALAAECgUIBQAAAA==.Myrâgè:BAAALAAECgcICgAAAA==.Mysthariel:BAAALAADCggIGAABLAAECgMIAwACAAAAAA==.Myzea:BAAALAAECgEIAQAAAA==.',['Mí']='Mídna:BAAALAAECgYIBgAAAA==.',Na='Nachtshatten:BAAALAAECgYIBgAAAA==.Nados:BAAALAAECgYICQAAAA==.Nanami:BAAALAADCgcIBwAAAA==.Nargana:BAABLAAECoEdAAISAAgIOBwFCQB2AgASAAgIOBwFCQB2AgAAAA==.Nathrael:BAAALAAECgUIBgAAAA==.Navyfree:BAAALAADCgcIEgABLAAECgYIDwACAAAAAA==.',Ne='Nelory:BAAALAADCgcIDQAAAA==.Neseria:BAAALAAECgYIDgAAAA==.Neutro:BAABLAAECoEUAAITAAgI2h80BwDCAgATAAgI2h80BwDCAgAAAA==.Nezukó:BAAALAADCgIIAgAAAA==.',Ni='Nightydk:BAABLAAECoEXAAMNAAgIPSKNFAB1AgANAAcIsiGNFAB1AgAOAAUIqh+kDQDUAQAAAA==.Nijamo:BAAALAAECgEIAQAAAA==.Nimoria:BAAALAADCggIFgAAAA==.Nippi:BAAALAADCgIIAgAAAA==.',No='Noniel:BAAALAAECgIIBAAAAA==.Nooe:BAAALAADCggICAAAAA==.',Ny='Nymue:BAAALAADCggICAAAAA==.Nysha:BAAALAAECgYIBgAAAA==.',['Nî']='Nîmue:BAAALAADCgMIAwAAAA==.',['Nï']='Nïhtøræ:BAAALAAECgMIBQAAAA==.',['Nô']='Nôva:BAAALAAECgIIAgAAAA==.',['Nõ']='Nõmi:BAAALAAECgcIDQAAAA==.',['Nú']='Núri:BAAALAAECggIDgAAAA==.',['Nû']='Nûrag:BAAALAADCggIEwAAAA==.',Oj='Ojiisan:BAAALAAECgEIAgAAAA==.',Ok='Oktalius:BAAALAADCgQIBAAAAA==.',Or='Or:BAAALAADCgEIAQAAAA==.Orb:BAAALAADCgcIDQAAAA==.Ortel:BAAALAADCgIIAgAAAA==.Ortl:BAAALAAECggIEAAAAA==.',Ou='Outlock:BAAALAAECgIIAgABLAAFFAQICwAHAE8bAA==.',Pa='Paleria:BAAALAAECgEIAQAAAA==.Pandahao:BAAALAAECgcIDgAAAA==.',Pe='Pepperminz:BAAALAADCgcIBgAAAA==.Perilia:BAAALAAECgcIDgAAAA==.Perodeath:BAAALAADCgUIBQAAAA==.',Po='Pockpockdown:BAAALAADCggIDgAAAA==.Popelklaus:BAABLAAECoEXAAIUAAgITSYRAACMAwAUAAgITSYRAACMAwAAAA==.Popelpaul:BAAALAAECgYIBgAAAA==.',Pr='Praliene:BAACLAAFFIEFAAIHAAMIdh8dAQApAQAHAAMIdh8dAQApAQAsAAQKgRkAAgcACAjrJXQBAHYDAAcACAjrJXQBAHYDAAAA.Priestreeth:BAABLAAECoElAAIVAAgIix2SFQAXAgAVAAgIix2SFQAXAgABLAAFFAMICgAWAGkbAA==.',Ps='Psybeast:BAAALAADCggIBgAAAA==.',Pu='Purplefox:BAAALAAECgEIAQAAAA==.',['Pú']='Púg:BAAALAAFFAIIAgAAAA==.',['Pû']='Pûg:BAAALAAECgYICQABLAAFFAIIAgACAAAAAA==.',Ra='Ragnarök:BAAALAAECgEIAQAAAA==.Rajina:BAAALAAECgUIBQAAAA==.Raycah:BAAALAAECgEIAQAAAA==.',Re='Recâsa:BAAALAAECgcIEQAAAA==.Revo:BAABLAAECoEXAAMXAAgIMSSvAADiAgAGAAgIwCEZBwARAwAXAAgIsiOvAADiAgAAAA==.',Rh='Rheá:BAAALAAECgIIAwAAAA==.',Ro='Ronleut:BAAALAADCggIFgAAAA==.',Rw='Rwz:BAAALAAECgIIAgAAAA==.',Ry='Ryhok:BAAALAADCgMIAwAAAA==.',['Rá']='Ráyzer:BAAALAAECgcIEAAAAA==.',['Rî']='Rîvers:BAAALAADCgcIBwABLAADCggICAACAAAAAA==.',['Rò']='Rògolan:BAAALAADCgcICAAAAA==.',Sa='Safrix:BAAALAAECgMIAwAAAA==.Safrïx:BAAALAADCgcIBwABLAAECgMIAwACAAAAAA==.Saintnavy:BAAALAAECgYIDwAAAA==.Salobir:BAAALAADCggIDwAAAA==.Sanatores:BAAALAADCgMIAwAAAA==.Saryana:BAAALAADCggIFgAAAA==.',Sc='Schurie:BAAALAAECgEIAQAAAA==.',Se='Seluna:BAAALAAECgcICwAAAA==.Semtaxxdk:BAAALAAECgIIAgAAAA==.Sereney:BAAALAADCgIIAgAAAA==.Serã:BAAALAAECgcIEgAAAA==.',Sh='Shalill:BAAALAAECgEIAgAAAA==.Shamonireeth:BAACLAAFFIEKAAIWAAMIaRuqAQAQAQAWAAMIaRuqAQAQAQAsAAQKgTAAAhYACAjzHwIEAOcCABYACAjzHwIEAOcCAAAA.Shaolin:BAAALAADCggICAAAAA==.Shellie:BAAALAADCgMIAwAAAA==.Shiaf:BAAALAAECgMIBAAAAA==.Shyn:BAAALAAECgMIAwAAAA==.Shòckwãve:BAAALAAECgQIBwAAAA==.',Si='Sickomode:BAAALAADCgIIAgAAAA==.Siirlocker:BAAALAADCggICAAAAA==.Silwardagah:BAAALAADCgUIBQAAAA==.',Sk='Skoogage:BAAALAAECgIIBAAAAA==.Skøgtrøll:BAAALAADCggICAAAAA==.',Sl='Slimak:BAABLAAECoEeAAMYAAcIgx2zDwA5AgAYAAYIvCGzDwA5AgAZAAEIMAR0HAA0AAAAAA==.',Sn='Snoozydk:BAACLAAFFIEFAAMNAAMIHhj3BgC4AAANAAMIghT3BgC4AAAOAAII0hc2AwCsAAAsAAQKgRYAAw4ACAgnJMICAOACAA4ACAgnJMICAOACAA0ABAg9F9dcABIBAAAA.',So='Sokràtes:BAAALAAECgYICQAAAA==.Soraní:BAAALAAECgIIBAAAAA==.',Sp='Speedy:BAAALAAECgYICQAAAA==.',St='Starboy:BAAALAAECgYIBgABLAAFFAIIAgACAAAAAA==.',Sy='Syd:BAAALAAECgEIAQAAAA==.Sydneya:BAAALAAECgMIAwAAAA==.Syren:BAAALAADCggIHQABLAAECggIEAACAAAAAA==.',['Sâ']='Sâmìrá:BAAALAADCgYIBgAAAA==.',Ta='Taelisa:BAAALAADCggIDwAAAA==.Tagharr:BAAALAAECgMIAwAAAA==.Takanashidh:BAAALAAFFAIIAgAAAA==.Takanashidk:BAAALAAECgYICQAAAA==.Tawii:BAAALAADCgcIBwAAAA==.',Te='Teddybärly:BAAALAAECgcIBwAAAA==.Teliâ:BAAALAAECgcIDQAAAA==.',Th='Thalandriel:BAAALAAECgcIDgAAAA==.Tharalina:BAAALAAECgEIAQAAAA==.Tharissan:BAAALAADCgEIAQAAAA==.Thaurelia:BAAALAAECgYIDgAAAA==.Theadore:BAAALAAFFAIIAgAAAA==.',Ti='Tienti:BAAALAADCggIFQAAAA==.Tigerchen:BAAALAAECgcIDwAAAA==.Tigergirl:BAAALAAECgYIDQAAAA==.Timurion:BAAALAADCggIFgAAAA==.Tinck:BAAALAAECgIIAwAAAA==.',Tk='Tkoda:BAAALAAECgEIAQAAAA==.',To='Tohuwabohu:BAAALAAECgQIBwAAAA==.Tonar:BAAALAAECgIIBAAAAA==.Torokk:BAAALAADCggICAAAAA==.Toxxiie:BAAALAADCggICQAAAA==.',Tr='Trashroguex:BAAALAADCgYICQAAAA==.Trixia:BAAALAAECgMIAwAAAA==.Trudï:BAAALAAECgIIAgAAAA==.',Tu='Turtôk:BAAALAAECggIDQAAAA==.',Ty='Tyridon:BAAALAAECgcIEQAAAA==.Tyskie:BAAALAAECgIIAgAAAA==.Tyxa:BAABLAAECoEUAAIOAAgIihVdCQAaAgAOAAgIihVdCQAaAgAAAA==.',Ul='Ularia:BAAALAADCgUIBwAAAA==.Ultrícis:BAAALAADCggICgAAAA==.',Um='Umbrêon:BAEALAADCgcIBwAAAA==.',Un='Unvershaman:BAAALAADCgcIBwAAAA==.',Va='Valkohr:BAAALAAECggIDgAAAA==.',Ve='Veasna:BAAALAADCgYIBgAAAA==.Veldo:BAAALAAECgYIBQAAAA==.Veluneth:BAAALAADCgIIAgAAAA==.',Vi='Viehtreiber:BAAALAADCgcIEgAAAA==.Vilso:BAAALAADCgcIBgABLAAECgYIDwACAAAAAA==.',Vo='Voxdeii:BAABLAAECoEcAAIPAAgIwRtgBgCMAgAPAAgIwRtgBgCMAgAAAA==.',Wa='Walli:BAAALAADCggICAAAAA==.Warpspeed:BAAALAADCgcICwAAAA==.Watchmeshock:BAAALAAFFAIIAgAAAA==.Watchyoback:BAAALAADCgcIBwAAAA==.',We='Weisserwolf:BAAALAAECgEIAgAAAA==.',Wh='Whysoserious:BAAALAADCggICAAAAA==.Whysoseríous:BAAALAAECgQIBAAAAA==.',Wi='Wisperwind:BAAALAADCggICAAAAA==.',Wo='Woltan:BAAALAAECgQIBAAAAA==.Woozywow:BAAALAADCgQIBAAAAA==.',Wr='Wrian:BAAALAAECgEIAQAAAA==.',Xe='Xerog:BAAALAADCggICwAAAA==.',Xo='Xoxlena:BAAALAAECgEIAQAAAA==.',Xu='Xuanyu:BAAALAAECggIEgAAAA==.',Xx='Xxholic:BAAALAAECgIIAgAAAA==.',Ya='Yadi:BAAALAAECgEIAQAAAA==.',Yi='Yinlin:BAAALAAECgYIDQAAAA==.',Za='Zakary:BAABLAAECoEVAAIBAAgIRxg0EABWAgABAAgIRxg0EABWAgAAAA==.Zanlock:BAAALAAECgYICgAAAA==.Zappyboi:BAAALAAECgYIDwAAAA==.',Ze='Zeyphira:BAAALAADCgYIBgAAAA==.',Zo='Zorlog:BAAALAAECgcIEAAAAA==.',Zu='Zunder:BAAALAAECggIEgAAAA==.',['Zê']='Zêlda:BAAALAAECgMIAwAAAA==.',['Àr']='Àrwèn:BAAALAAECgMIAwAAAA==.',['Ân']='Ânyu:BAABLAAECoEUAAIVAAcItSXiAwAGAwAVAAcItSXiAwAGAwAAAA==.',['Æc']='Æceu:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end