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
 local lookup = {'Unknown-Unknown','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Monk-Brewmaster','Warrior-Fury','Monk-Mistweaver','DemonHunter-Havoc','DeathKnight-Frost','Hunter-Marksmanship','Paladin-Holy','Shaman-Restoration','Monk-Windwalker','Rogue-Outlaw','Priest-Holy','DeathKnight-Blood',}; local provider = {region='EU',realm="Anub'arak",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abram:BAAALAADCgQIBAAAAA==.',Ak='Akenadragon:BAAALAAECgYIDQAAAA==.',Al='Alii:BAAALAADCgYIBwAAAA==.',Am='Amra:BAAALAADCgYICAABLAAECgQIBAABAAAAAA==.',An='Anassa:BAAALAAECgQIBAAAAA==.Ankha:BAAALAAECgYICQAAAA==.Annihilatio:BAAALAAECgYICwAAAA==.Anyá:BAAALAADCgcIBwAAAA==.',Ap='Apophîs:BAAALAADCgcICQAAAA==.',Aq='Aquilone:BAAALAADCgcIDgAAAA==.',Ar='Arkii:BAAALAAECgcIDAAAAA==.Arásáka:BAAALAADCggICAAAAA==.Arîna:BAAALAADCggIHAAAAA==.',As='Asmodea:BAAALAADCgUIBQAAAA==.Asuká:BAAALAADCggIFgAAAA==.',At='Athronas:BAAALAADCgcICAAAAA==.Atûm:BAAALAAECgYICwAAAA==.',Ay='Ayende:BAAALAAECgUICgAAAA==.',Ba='Bafyum:BAAALAADCgUIBQAAAA==.Balamir:BAAALAAECgMIBAAAAA==.Bambàm:BAAALAADCgcIBwAAAA==.Banoki:BAAALAAECgYIBgAAAA==.Baratas:BAAALAADCggIFAAAAA==.',Be='Beartreecat:BAAALAADCggICAAAAA==.Beleria:BAAALAADCgcICQAAAA==.Beule:BAAALAAFFAEIAQAAAA==.',Bl='Blaucrowdchi:BAAALAAECgcIEQAAAA==.Blindshot:BAAALAADCggIDgAAAA==.Blutpaladin:BAABLAAECoEXAAICAAgIdxxWEQCTAgACAAgIdxxWEQCTAgAAAA==.',Bo='Bobblldûdû:BAAALAAECgUIBQAAAA==.Bompe:BAAALAAECgYIDwAAAA==.Bosshi:BAAALAAECgYIBwABLAAECggIEgABAAAAAA==.Bottles:BAAALAAECgcIDwAAAA==.',Br='Brassica:BAAALAADCggIDQAAAA==.Bribella:BAAALAAECgIIAgAAAA==.Brolydan:BAAALAAECgMIAwAAAA==.Brumborn:BAAALAAECgYICwAAAA==.Brunaxiâ:BAAALAADCgcIBwAAAA==.',Bu='Bubbeldin:BAAALAAECgYIDAAAAA==.Budgethulk:BAAALAADCgcIBwAAAA==.Budunde:BAAALAADCgEIAQAAAA==.',Bw='Bwjbs:BAAALAADCggICQAAAA==.',By='Bylo:BAAALAAECgIIAwAAAA==.',Ca='Calligenia:BAAALAAECgMIAwAAAA==.',Ch='Chaossniper:BAAALAAECgEIAgAAAA==.Charlieb:BAAALAADCgcIBwAAAA==.Charoz:BAAALAAECgYICwAAAA==.Cheesuzsham:BAAALAADCgEIAQAAAA==.',Ci='Ciaokakow:BAAALAAECgUIBwAAAA==.',Cr='Crahzerphyka:BAAALAADCgcICgAAAA==.Creusa:BAAALAAECgYICgAAAA==.Crocogeil:BAAALAADCgIIAgAAAA==.',Cx='Cxart:BAAALAADCgcIBQABLAAECgYIBgABAAAAAA==.',['Cê']='Cêli:BAAALAAECgMIAwAAAA==.',Da='Daernaeris:BAAALAAECgEIAQAAAA==.Dangerdan:BAAALAADCggIDwAAAA==.Daroon:BAAALAAECgIIAwAAAA==.',De='Deathoni:BAAALAADCgQIBwAAAA==.Deimoss:BAAALAAECgYIBgAAAA==.Derbste:BAAALAAECgIIAwAAAA==.Derevex:BAAALAAECgYIDQAAAA==.',Di='Diapal:BAAALAAECgIIAgAAAA==.Dimimops:BAAALAAECgYICwAAAA==.Disdain:BAAALAAECgcIEAAAAA==.',Do='Dotlul:BAAALAADCggICQAAAA==.Dowen:BAAALAADCgcIBwAAAA==.',Dr='Draxxoo:BAAALAAECgYICwAAAA==.Drågonskull:BAAALAAECgMIBAAAAA==.',Du='Durn:BAAALAAECgMIAwAAAA==.',['Dü']='Dübi:BAAALAAECgYIDAABLAAECggIGAACAGgjAA==.',Eb='Ebbiteb:BAAALAADCgcICAAAAA==.',Ei='Einprozent:BAAALAADCggIEgAAAA==.',El='Eldack:BAAALAAECgUIBQAAAA==.Elfentank:BAAALAAECggICQAAAA==.Elgordo:BAAALAADCggICAAAAA==.Ell:BAAALAAECgYIDQAAAA==.Elsharion:BAAALAAECgUICwAAAA==.Elumia:BAAALAAECgIIAwAAAA==.',Er='Ermelyn:BAAALAADCgUIBwAAAA==.',Ev='Evolina:BAAALAAECgIIAgAAAA==.',Ex='Exzellenz:BAAALAAECgYIBwAAAA==.',Ez='Ezhjyr:BAAALAADCgMIAwAAAA==.',Fe='Felli:BAAALAAECgYIDQAAAA==.Feylenne:BAAALAAECgYIBgAAAA==.',Fi='Firuna:BAAALAAECggIEgAAAA==.',Fl='Flint:BAAALAAECgYIBwAAAA==.Fluppy:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.',Fr='Freezeur:BAAALAADCgQIBAAAAA==.',Fu='Fueguchi:BAAALAADCgIIAgAAAA==.',Fy='Fynvola:BAAALAAECgYICwAAAA==.',['Fß']='Fß:BAAALAAECgMIAwAAAA==.',['Få']='Fåb:BAAALAAECgcIDgAAAA==.',['Fé']='Féyrón:BAAALAAECgIIAgAAAA==.',['Fó']='Fórtéx:BAAALAAECggIEAAAAA==.',Ga='Garug:BAAALAAECgIIAgAAAA==.',Go='Goodkaren:BAAALAAECgIIAwAAAA==.Gooz:BAAALAAECgYICwAAAA==.Gordrohn:BAAALAADCgcIBwAAAA==.Gothbaddie:BAAALAAECgEIAQAAAA==.Gottzilla:BAAALAAECgYIDQAAAA==.',Gr='Greavessamdi:BAAALAADCgcICQAAAA==.Grimmiger:BAAALAADCggIEwAAAA==.Grümling:BAAALAADCgcIBwAAAA==.',Gu='Gurkengökhan:BAAALAAECgQIBwAAAA==.Gurthalak:BAAALAADCgYIBgAAAA==.Gutenacht:BAAALAAECgYIBgAAAA==.',['Gé']='Gérier:BAAALAADCgcIDAAAAA==.',Ha='Haarfarbè:BAAALAAECgMIAwAAAA==.Haelina:BAAALAADCggICAAAAA==.Hahnsgeorc:BAABLAAECoEYAAIDAAgIpAqWNwBzAQADAAgIpAqWNwBzAQAAAA==.Hakeem:BAABLAAECoERAAMEAAcI3Rl6IADKAQAEAAYIRxl6IADKAQAFAAMI/BIHOADKAAAAAA==.Hakka:BAAALAAECgQIBAAAAA==.Havaldt:BAAALAADCggIEgAAAA==.',He='Healbadudead:BAAALAAECgIIAgAAAA==.',Hu='Hulkbusta:BAAALAAECgYIBgAAAA==.Huntnix:BAAALAADCggIBgAAAA==.',Hy='Hyänenwolf:BAAALAADCgcIFAAAAA==.',['Hô']='Hôlyhâte:BAAALAAECgYIBgAAAA==.',['Hú']='Húggy:BAAALAADCgYIAwAAAA==.',Ib='Ibaz:BAAALAAECgMIAwAAAA==.',Ic='Icetot:BAAALAAECgMIBAAAAA==.',If='Ifeyus:BAAALAAECgUIBgAAAA==.',In='Insenate:BAAALAADCgcIBwAAAA==.',Ir='Irkalla:BAAALAAECgYICwAAAA==.',Iv='Ivana:BAAALAADCgcIBgABLAAECggIFQAGAFMdAA==.Ivera:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.',Ja='Jaakko:BAAALAADCgcIBwAAAA==.Jacki:BAAALAADCgcIBwAAAA==.Jaelâ:BAAALAAECgYIBwAAAA==.',Je='Jenno:BAAALAADCgUIBQAAAA==.Jep:BAAALAAECgMIAwAAAA==.',Jo='Joanaqt:BAAALAADCgUIBQAAAA==.',Ka='Kadia:BAAALAADCggIDgAAAA==.Kalidasi:BAAALAADCggICAAAAA==.Kallîsto:BAAALAADCgMIAwAAAA==.Kamikaze:BAAALAADCgUIBQAAAA==.Kaneda:BAAALAAECgMIAQAAAA==.Kanna:BAAALAADCggICQAAAA==.Kaputtschino:BAAALAADCggICQAAAA==.Karoo:BAAALAAFFAIIAgAAAA==.Katjastrophe:BAAALAAECgYICQAAAA==.',Ki='Kilja:BAAALAADCggICgAAAA==.Killdygion:BAAALAAECgUICgAAAA==.',Kl='Klpr:BAABLAAECoEXAAIHAAgIbCUkAQB0AwAHAAgIbCUkAQB0AwAAAA==.',Ko='Koarl:BAAALAADCggICAAAAA==.Kohlsen:BAAALAAECgYIDQAAAA==.Koju:BAAALAAECgYIEAAAAA==.Kokove:BAAALAADCggICAABLAADCggICwABAAAAAA==.Koleos:BAAALAADCgQIBAABLAADCgcIDgABAAAAAA==.Kortosus:BAAALAAECgYICAAAAA==.Kove:BAAALAADCggICwAAAA==.',Kr='Kristijan:BAAALAADCgcIDgAAAA==.',Ku='Kuromi:BAAALAADCggICAAAAA==.Kuurgon:BAAALAADCggIDwAAAA==.',Ky='Kythraya:BAABLAAECoEXAAIIAAgICRvSBQCFAgAIAAgICRvSBQCFAgAAAA==.',La='Laki:BAAALAAECgIIAQABLAAECggIFQAGAFMdAA==.Lakibrew:BAAALAADCggICAAAAA==.Lakiê:BAABLAAECoEVAAIGAAgIUx0sBACkAgAGAAgIUx0sBACkAgAAAA==.Larowen:BAABLAAFFIEFAAIJAAMIUxLpAwAMAQAJAAMIUxLpAwAMAQAAAA==.Lathriel:BAAALAAECgYICgAAAA==.',Le='Levana:BAAALAADCggICAABLAAECgUIBgABAAAAAA==.',Li='Lilifi:BAAALAADCggICAAAAA==.Linael:BAAALAAECgYIDQAAAA==.Lincka:BAAALAAECgYIBgAAAA==.Lirada:BAAALAADCggICQAAAA==.Liria:BAAALAAECgYIBgAAAA==.Lissana:BAAALAAECgIIAgAAAA==.',Lo='Longrunner:BAAALAAECgcIDwAAAA==.Lopepp:BAAALAAECgYICAAAAA==.',Lu='Lumîêl:BAAALAADCgMIBAAAAA==.',Ly='Lyudmila:BAAALAAECgYICQAAAA==.',Ma='Maark:BAAALAAECgMIAgAAAA==.Madgain:BAAALAAECggIAgAAAA==.Magni:BAAALAAECgMIBQAAAA==.Mahari:BAAALAADCggIFgAAAA==.Malou:BAAALAAECgEIAQAAAA==.Malá:BAAALAADCgUIBQABLAADCgcIBwABAAAAAA==.Manîaç:BAAALAAECgEIAQAAAA==.Manôxhunt:BAAALAAECgMIBgAAAA==.Mara:BAAALAAECgUICgAAAA==.Martinique:BAAALAAECgMIAwAAAA==.Marunda:BAAALAADCgcIBwAAAA==.',Mc='Mcbeth:BAAALAAECgYICwABLAAECggIFwAIAAkbAA==.',Me='Melanzani:BAAALAAECgcICwAAAA==.Melisandre:BAAALAADCgcICAAAAA==.Mentyriel:BAAALAADCgYICwAAAA==.',Mi='Milyandra:BAAALAAECgYICQAAAA==.Minotar:BAAALAAECgYICQAAAA==.Miracel:BAAALAAECgYICQABLAAECggIFgAKAHkdAA==.Mirauk:BAAALAAECgYIBgAAAA==.Miriana:BAAALAAECgMIBAAAAA==.Mizuna:BAAALAADCgcIDAABLAAECgMIAQABAAAAAA==.',Mj='Mjølnir:BAAALAAECgcIDgAAAA==.',Mu='Murmanndanya:BAAALAADCgYICgAAAA==.',My='Myre:BAAALAADCgcIBwAAAA==.Myrilia:BAAALAAECgYICwAAAA==.Mysteryele:BAAALAAECggICwABLAAECggIDwABAAAAAA==.Mysteryhexe:BAAALAAECgMIBQABLAAECggIDwABAAAAAA==.Mysterymage:BAAALAADCgIIAgABLAAECggIDwABAAAAAA==.Mysterywar:BAAALAAECggIDwAAAA==.',Na='Nazgor:BAAALAAECgMIAwAAAA==.',Ne='Nejslutá:BAAALAAECgEIAQAAAA==.Neldrok:BAAALAADCgYIBgAAAA==.',Ni='Nichtpoly:BAAALAADCggIEAAAAA==.Niederschlag:BAAALAAECgEIAQAAAA==.Niernen:BAAALAADCgEIAQAAAA==.Nina:BAAALAADCggICQAAAA==.',Nk='Nkari:BAAALAAECgMIBAAAAA==.',No='Norah:BAABLAAECoEXAAMLAAgIJhrvEwD2AQALAAgIVhXvEwD2AQADAAUI7BrzLgCdAQAAAA==.',Ny='Nyca:BAAALAAECgUIBwAAAA==.Nyrian:BAAALAAECgYICQAAAA==.',Or='Orletwarr:BAAALAAECgcICgAAAA==.',Pa='Paynjada:BAAALAADCgIIAgAAAA==.',Pi='Picoprep:BAAALAAECgMIBQAAAA==.',Pr='Prinzipal:BAAALAAECgMIBAAAAA==.',Pu='Pudding:BAAALAADCggIEQABLAAECgYICgABAAAAAA==.',Py='Pyroxion:BAAALAAECgUICgAAAA==.',Ra='Raelith:BAAALAADCgUIBQAAAA==.Ragequiteasy:BAAALAAECgEIAQAAAA==.Rahzúl:BAAALAAECgYIBgAAAA==.Ranjuul:BAAALAADCgcIBwAAAA==.',Re='Revexia:BAAALAADCggIDQAAAA==.Revolte:BAAALAADCggICAAAAA==.',Ri='Rikuchan:BAAALAAECgcICgAAAA==.',Ru='Rulaní:BAAALAAECgcIDwAAAA==.Rulferin:BAAALAAFFAEIAQAAAA==.',Ry='Ryuku:BAABLAAECoEXAAIHAAgIWSQTAwBIAwAHAAgIWSQTAwBIAwAAAA==.Ryushu:BAAALAAECgYIEAABLAAECggIFwAHAFkkAA==.Ryuuk:BAAALAAECgUICwAAAA==.',['Râ']='Râvên:BAAALAADCgYICQAAAA==.',['Ræ']='Ræyna:BAAALAADCgUIBQABLAAECgUIBgABAAAAAA==.',Sc='Scentíic:BAAALAADCgYIBgABLAAECgYIBgABAAAAAA==.Schamixyz:BAAALAAECgUICgAAAA==.Schissbär:BAAALAAECggIDgAAAA==.Schnackerl:BAAALAADCgcICAAAAA==.Scárab:BAAALAAECgYIBgAAAA==.',Se='Seelenloser:BAAALAAECgMIAQAAAA==.Senfei:BAABLAAECoEYAAMCAAgIaCOPBwASAwACAAgIaCOPBwASAwAMAAUIOBFFHgBCAQAAAA==.Senjutsu:BAAALAAECgQIBgAAAA==.Senshi:BAAALAAECgYICQAAAA==.Sepolock:BAAALAADCgEIAQAAAA==.Serifea:BAAALAAECgEIAQAAAA==.Serini:BAAALAADCgcIBwABLAADCggICgABAAAAAA==.Serki:BAABLAAECoEWAAINAAgI0h7kBwCeAgANAAgI0h7kBwCeAgAAAA==.Serrat:BAAALAAECgcIEQAAAA==.',Sh='Shakfernis:BAAALAAECgYIDQAAAA==.Shakraxus:BAAALAADCgYICwAAAA==.Shamanicus:BAAALAADCggICAAAAA==.Shambulance:BAAALAADCgcIDQAAAA==.Shamey:BAABLAAECoEUAAINAAgIrhUjGwDxAQANAAgIrhUjGwDxAQAAAA==.Sharimara:BAAALAAECgUICgAAAA==.Shizoki:BAAALAADCgMIAwAAAA==.Shusui:BAAALAADCggICAABLAAECggIFwAHAFkkAA==.Shuyin:BAAALAADCggIDgAAAA==.',Si='Silora:BAAALAAECgUIBwAAAA==.Simra:BAAALAAECgcIEAAAAA==.Sindra:BAAALAADCgYIBgAAAA==.',Sk='Skai:BAAALAAECgMIBQAAAA==.Skarog:BAAALAAECgYIDQAAAA==.Skull:BAAALAAECgcIEAAAAA==.',So='Solvey:BAAALAADCggIDgAAAA==.Sozialhilfe:BAAALAADCggIDgAAAA==.',St='Steinhard:BAAALAAECgYICQAAAA==.Stiibu:BAAALAADCgEIAQAAAA==.Sturmheiler:BAAALAADCggIEAAAAA==.',Su='Sunarian:BAAALAAECgIIAgAAAA==.',Sw='Swaydh:BAAALAAECgMIAgAAAA==.Swaypal:BAAALAADCggIBwAAAA==.',Sy='Sypers:BAAALAADCgIIAQAAAA==.',Ta='Tamarú:BAAALAADCggICAAAAA==.Tamin:BAAALAAECgIIAgAAAA==.Tatom:BAAALAADCggICAAAAA==.',Tb='Tbcbeste:BAACLAAFFIEFAAIOAAMIHRKjAQD6AAAOAAMIHRKjAQD6AAAsAAQKgRgAAg4ACAhpI5gCABkDAA4ACAhpI5gCABkDAAAA.',Th='Thermo:BAAALAADCgEIAQAAAA==.Thomsn:BAAALAAECgMIBQAAAA==.Thorín:BAAALAAECgEIAQAAAA==.Thérry:BAAALAAECgQIBQAAAA==.Thôrdril:BAAALAADCgcIDQAAAA==.',Ti='Tinary:BAAALAADCgUICQAAAA==.Tinéoidea:BAAALAADCggICAAAAA==.Tirza:BAAALAAECggIAgAAAA==.',To='Toggie:BAACLAAFFIEFAAIPAAMIzRo1AAApAQAPAAMIzRo1AAApAQAsAAQKgRcAAg8ACAhUJSQAAHMDAA8ACAhUJSQAAHMDAAAA.',Tr='Trillin:BAAALAAECgUICwABLAAECgYIEAABAAAAAA==.Tritorius:BAAALAADCgIIAgAAAA==.Trollomollo:BAAALAADCggICAAAAA==.Truefruits:BAAALAADCgYIBgAAAA==.',Ty='Tyrigosà:BAABLAAECoEeAAIQAAgICCOfAgAlAwAQAAgICCOfAgAlAwAAAA==.',Us='Useless:BAAALAAECgYICgAAAA==.',Ut='Utaka:BAAALAAFFAEIAQAAAA==.',Va='Valandir:BAAALAAECgMIAwAAAA==.Valthurian:BAAALAADCggICQAAAA==.Vanfelsing:BAAALAADCggIEAAAAA==.Vapø:BAAALAADCgcIBwABLAAECgUIBgABAAAAAA==.',Ve='Vecazz:BAABLAAECoEXAAIHAAgIwCHcBAAqAwAHAAgIwCHcBAAqAwAAAA==.Venira:BAAALAAECgcIEAAAAA==.Venuss:BAAALAADCgQIBAAAAA==.Vermithrax:BAAALAAECgYICQAAAA==.Vestia:BAAALAAECgYICwAAAA==.',Vr='Vrasi:BAAALAADCggICAAAAA==.',['Và']='Vàley:BAAALAADCgcIBAAAAA==.',['Vá']='Váleriuz:BAAALAADCgcICwAAAA==.',Wa='Warflock:BAAALAADCggICAAAAA==.Warrî:BAAALAAECgYICQAAAA==.',Wh='Whack:BAABLAAECoEWAAMKAAgIeR3kEACZAgAKAAgIeR3kEACZAgARAAEIMwb9IAAxAAAAAA==.Whiteneyra:BAAALAADCgYICwAAAA==.',Wi='Willydan:BAAALAAECgcIDAAAAA==.',Wo='Wolthan:BAAALAADCgcIBwAAAA==.',Wu='Wurzelpeter:BAAALAAECgYIBwAAAA==.Wutbürger:BAAALAADCgcIBwAAAA==.',Xa='Xalatath:BAAALAADCggICAAAAA==.Xarion:BAAALAADCgYIBgAAAA==.',Xe='Xereos:BAAALAAECgQIBwAAAA==.',Xi='Xillia:BAAALAAECgYIDAAAAA==.',Xo='Xorkaren:BAAALAAECgYICgAAAA==.',Yo='Yocheved:BAAALAAECggICAAAAA==.Yoram:BAAALAADCgIIAQAAAA==.',Yp='Ypsi:BAAALAADCgYIBgAAAA==.',Ys='Yselîa:BAAALAAECgYICgAAAA==.',Yu='Yuffshot:BAAALAADCgYIBgABLAAECgYIDQABAAAAAA==.Yuffïe:BAAALAAECgYIDQAAAA==.Yujii:BAAALAADCgcIBwAAAA==.',Za='Zabbo:BAAALAAECgYIBwAAAA==.Zaelron:BAAALAAECggICAAAAA==.',Ze='Zelma:BAAALAAECgYIBwAAAA==.',Zh='Zhanrael:BAAALAADCgQIBAAAAA==.',Zi='Zinker:BAAALAADCgcIBwAAAA==.',Zo='Zoltarus:BAAALAADCgYIBwAAAA==.',Zu='Zuulja:BAAALAAECgQIBAAAAA==.',Zy='Zyru:BAAALAAECgYIBgAAAA==.',['Zà']='Zàwárudo:BAAALAAECggIBAAAAA==.',['Àm']='Àmy:BAAALAADCggIFAAAAA==.',['Äl']='Ällikillä:BAAALAAECgYICQAAAA==.',['Ça']='Çalypto:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end