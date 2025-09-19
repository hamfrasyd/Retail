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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','Paladin-Retribution','Rogue-Outlaw','Rogue-Assassination','Paladin-Protection','Warlock-Destruction','Warlock-Affliction','Evoker-Devastation','Mage-Arcane','Warrior-Fury','Paladin-Holy',}; local provider = {region='EU',realm='Garona',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abryco:BAAALAADCgcIBwAAAA==.',Ae='Aegøn:BAAALAADCgcIDQAAAA==.Aelwyn:BAAALAAECgEIAQAAAA==.',Ah='Ahnnya:BAAALAADCgQICAAAAA==.',Ai='Aikha:BAAALAAECgcIDwAAAA==.',Ak='Akabane:BAAALAADCgcICQAAAA==.Akabané:BAAALAADCggIEAAAAA==.',Al='Aldric:BAAALAAECgIIAgAAAA==.Alfpipe:BAAALAADCggICAABLAAECgYIDAABAAAAAA==.Alicecooper:BAAALAADCgEIAQAAAA==.Althar:BAAALAADCgcIBwAAAA==.Althorack:BAAALAAECgMIAwAAAA==.Alura:BAAALAAECggIDgABLAAFFAMIBAABAAAAAA==.',Am='Amanó:BAAALAADCgIIAwAAAA==.Améris:BAAALAAECgYIBgAAAA==.',An='Andrømède:BAAALAADCgYICQAAAA==.Antek:BAAALAADCggICAAAAA==.',Ar='Arioch:BAAALAADCggIEAAAAA==.Aräthörn:BAAALAADCggIBAAAAA==.',As='Ashproof:BAABLAAECoEUAAICAAgIvRMjKgDoAQACAAgIvRMjKgDoAQAAAA==.Asrubalde:BAAALAAECgcIDQAAAA==.',Az='Azarock:BAAALAADCgMIAwAAAA==.Azufame:BAAALAADCggICgAAAA==.',Ba='Babardashian:BAAALAAECgEIAQAAAA==.Bashok:BAAALAAECgUICQAAAA==.',Be='Behwolf:BAAALAADCggICQAAAA==.Bernkastel:BAAALAAECgcIEgABLAAECggIFQADAAglAA==.',Bl='Bloodswordz:BAAALAADCgcIBwAAAA==.Bläckyjäck:BAAALAAECgYICQAAAA==.',Br='Braduval:BAAALAADCgQIBgAAAA==.Brazael:BAAALAADCgYICQAAAA==.Breator:BAAALAAECgEIAQAAAA==.Bricewullus:BAAALAAECgUICAAAAA==.Brubru:BAAALAAECggICAAAAA==.',Bu='Bubblegum:BAAALAADCgcIBwAAAA==.',Bz='Bzrk:BAAALAAECgIIAgAAAA==.',Ca='Cahlanne:BAAALAAECgEIAQAAAA==.Caraxes:BAAALAAECgEIAQAAAA==.',Ce='Cemillia:BAAALAADCgYIBgAAAA==.Cemina:BAAALAAECgEIAQAAAA==.',Ch='Chameuuh:BAAALAADCgcIBwAAAA==.Chamoulox:BAAALAADCggIDgAAAA==.Chaussonopom:BAAALAAECgYICgAAAA==.Chocola:BAAALAAECgEIAQAAAA==.Choufa:BAAALAAECgYICQAAAA==.Chronosia:BAAALAAECgUIBgAAAA==.Chuckloriss:BAAALAADCgcIDgAAAA==.',Cl='Clëoh:BAAALAAECgQIBAAAAA==.',Co='Corca:BAAALAADCgEIAQAAAA==.',Cr='Crazydiamond:BAABLAAECoEVAAIDAAgICCU/AwBWAwADAAgICCU/AwBWAwAAAA==.Critical:BAAALAAECgEIAQAAAA==.',Cu='Cuthulu:BAAALAAFFAIIAgAAAA==.',['Cø']='Cøpãin:BAABLAAECoEXAAMEAAgIUiNtAAA8AwAEAAgIUiNtAAA8AwAFAAMIyCS0KABEAQAAAA==.',Da='Dain:BAAALAAECgYIBgAAAA==.Darkløck:BAAALAAECgMIBwAAAA==.Darkshamy:BAAALAADCgcIBgAAAA==.Darkwood:BAAALAAECgYIDwAAAA==.Darkxhunt:BAAALAADCgUIBQAAAA==.',De='Deadfada:BAAALAAECgMIAwAAAA==.Deadzr:BAAALAADCggIGQAAAA==.Deathmute:BAAALAADCgEIAQAAAA==.Demandrëd:BAAALAADCgYIBwAAAA==.',Di='Diamantfou:BAAALAAECggIEQABLAAECggIFQADAAglAA==.Diëgo:BAAALAADCgIIAgAAAA==.',Do='Dooms:BAAALAAECgYICAAAAA==.',Dr='Dracozouille:BAAALAADCgYIBgAAAA==.Drakolynette:BAAALAAECgYIBgABLAAECgQIBwABAAAAAA==.Drastark:BAAALAAECgYIDQAAAA==.Drical:BAAALAAECggIDwAAAA==.Drilic:BAAALAAECgYIDAAAAA==.',Dt='Dtress:BAAALAAECgMIBQAAAA==.',Du='Dunkie:BAAALAADCgYIBgAAAA==.',['Dæ']='Dædmønk:BAAALAADCgcIDgAAAA==.',['Dé']='Déps:BAAALAAECgEIAQAAAA==.',['Dï']='Dïetrich:BAAALAADCgYICgAAAA==.',['Dø']='Dørmammu:BAAALAAECgIIAgAAAA==.',El='Elfihunt:BAAALAADCgUIBwAAAA==.Elfilette:BAAALAADCgcIBwAAAA==.',En='Enero:BAAALAAECgEIAQAAAA==.',Eo='Eoliä:BAAALAAECgEIAQAAAA==.',Ep='Epicmøuse:BAAALAAECggIEgAAAA==.',Er='Erazekiel:BAAALAADCggIFQAAAA==.Erienne:BAAALAAECgYICgAAAA==.',Es='Escanor:BAAALAAECgcIBwAAAA==.',Et='Eternété:BAAALAADCggIFwAAAA==.',Ev='Evena:BAABLAAECoEVAAIGAAgIiiI6AgATAwAGAAgIiiI6AgATAwAAAA==.',Ex='Exers:BAAALAADCggIFgAAAA==.',Ez='Ezøp:BAAALAAECgYIAQAAAA==.',Fa='Faufilé:BAAALAAECgMIBQAAAA==.',Fl='Flammeche:BAAALAADCgYICQAAAA==.',Fo='Foufours:BAAALAAECgMIBQAAAA==.',Fr='Friskette:BAAALAADCggIDgAAAA==.',Ga='Gaab:BAAALAADCggICAAAAA==.Gaaby:BAAALAADCgYIBgAAAA==.Gajil:BAAALAAECggIEwAAAA==.Galawìn:BAAALAAECgYICgAAAA==.Gaélon:BAAALAAECgYIDgAAAA==.',Gr='Grhöm:BAAALAADCgcIBwAAAA==.Grimg:BAAALAADCgMIAwAAAA==.Grodhar:BAAALAAECgYIBgAAAA==.Gryrgrax:BAAALAADCgMIAwAAAA==.',Gu='Gum:BAAALAAECgUIBQAAAA==.',Gw='Gwenha:BAAALAADCgYIBgAAAA==.Gwo:BAAALAAECgYIDAAAAA==.',Ha='Hadrii:BAABLAAECoEVAAMHAAgIXCQaAwA+AwAHAAgIXCQaAwA+AwAIAAEIvySBIwBsAAAAAA==.Hagimage:BAAALAADCgcICAAAAA==.Halebos:BAAALAADCggIGAAAAA==.Hanibhal:BAAALAADCgcICAAAAA==.Hazlayk:BAAALAAECgIIBAABLAAECgMIBQABAAAAAA==.',Hi='Hitokirü:BAAALAADCggIFwAAAA==.Hitoyama:BAAALAADCggIDAAAAA==.',Ho='Hororro:BAAALAAECgMIBQAAAA==.',Hy='Hyzaal:BAAALAAECgEIAQAAAA==.',Ir='Iridia:BAAALAAECgUICQAAAA==.',Iv='Iverhild:BAAALAAECgYIBgAAAA==.',Ja='Jafaar:BAAALAAECgcIDAAAAA==.',Je='Jeddead:BAAALAADCgMIAwAAAA==.Jeskodas:BAAALAAECgMIBgAAAA==.Jezàbel:BAAALAAECgIIAgAAAA==.',['Jë']='Jërykô:BAAALAAECgYIDgAAAA==.',Ka='Kaguâ:BAAALAAECgIIAgAAAA==.Kaherdin:BAAALAADCggIDwAAAA==.Kakouzz:BAAALAAECgcIDAAAAA==.Karaw:BAAALAAECgMIBgAAAA==.Karnilla:BAAALAAECgMIBQAAAA==.',Ke='Kellam:BAAALAAECgcIEAAAAA==.Kelthorya:BAAALAAECgMIAwAAAA==.Kendral:BAAALAAECgMIBQAAAA==.Keros:BAAALAAECgEIAQAAAA==.Ketama:BAAALAAECgIIAgAAAA==.',Kh='Khaha:BAAALAADCgEIAQAAAA==.',Ki='Kilogramprod:BAAALAADCggICAAAAA==.Kissî:BAAALAAFFAIIAgAAAA==.Kizera:BAAALAADCgcIBwABLAAFFAIIBAABAAAAAA==.Kizerx:BAAALAAFFAIIBAAAAA==.',Ko='Koalatell:BAAALAADCgIIAgAAAA==.Koumba:BAAALAADCggIDgAAAA==.',Ku='Kuaigonjin:BAAALAAECgcIEQAAAA==.',Ky='Kynicham:BAAALAAECggIEwAAAA==.',La='Lalina:BAAALAAECgUIBQAAAA==.Layam:BAAALAADCggIEAAAAA==.',Le='Lei:BAAALAADCggIFgAAAA==.Lepetitedrag:BAAALAAECgEIAQABLAAECgYICgABAAAAAA==.Lerodra:BAAALAAECgMIBQAAAA==.Leynora:BAAALAAECgYIBgAAAA==.',Lh='Lhøälex:BAAALAAECgYIDwAAAA==.',Li='Lieferte:BAAALAAECgYIDAAAAA==.Liliths:BAAALAAECgYIBgAAAA==.Littlejuice:BAAALAAECgYIBgAAAA==.Lixfem:BAAALAADCgMIAwAAAA==.',Lo='Loteilin:BAAALAADCgIIAgAAAA==.',Ly='Lycus:BAAALAADCgIIAgAAAA==.',Ma='Maabout:BAAALAAECgIIAgAAAA==.Madfog:BAAALAADCggICAAAAA==.Magounight:BAAALAADCgYICQAAAA==.Maidisana:BAAALAAECgUICAAAAA==.Makmk:BAAALAADCgUIBQAAAA==.Makoclaque:BAAALAADCgIIAgAAAA==.Makötao:BAAALAADCggIDQAAAA==.Malagnyr:BAAALAADCgQIBAAAAA==.Mantax:BAAALAADCggICAAAAA==.Mara:BAAALAADCgEIAQAAAA==.Maralora:BAAALAAECgUIBwAAAA==.',Me='Meltosse:BAAALAADCggIDgAAAA==.',Mi='Miellaa:BAAALAADCgQIBAAAAA==.Mihli:BAAALAAECgUIBgAAAA==.Miraidon:BAAALAAECgYICgAAAA==.Misstoc:BAAALAADCggIFwAAAA==.',Ml='Mlyn:BAAALAADCgMIAwAAAA==.',Mo='Moinearya:BAAALAADCgYIBgAAAA==.Mordrède:BAAALAADCgQIBAAAAA==.Moreplease:BAAALAAFFAIIAgAAAA==.Morganouu:BAAALAAECgMIAwAAAA==.Mortifere:BAAALAAECgcIDwAAAA==.',My='Myr:BAAALAADCgUIBQABLAAECgcIDwABAAAAAA==.Myrlight:BAAALAAECgYICgABLAAECgcIDwABAAAAAA==.Myrmana:BAAALAADCggIDgAAAA==.Myrnone:BAAALAAECgcIDwAAAA==.',['Mà']='Màkassh:BAAALAADCggICAAAAA==.',['Mÿ']='Mÿlia:BAAALAAECgYICwAAAA==.',Na='Nainpo:BAAALAAECgYIBgAAAA==.Nanÿ:BAAALAADCggIFwAAAA==.Nashøba:BAAALAADCgcIBwAAAA==.Naïnladin:BAAALAADCgUIBwAAAA==.',Ni='Nicala:BAAALAAECgMIAwAAAA==.Nidéio:BAAALAAECgQICAAAAQ==.Nikitya:BAAALAAECgYICAAAAA==.',No='Norlundo:BAAALAADCgcIBwAAAA==.Novea:BAAALAAECgcICQAAAA==.Noziroth:BAAALAAECgYIDAAAAA==.',Nu='Numiielia:BAAALAAECgYICQAAAA==.',['Nè']='Nèréïde:BAAALAAECggICwAAAA==.',Oc='Océannia:BAAALAADCggIFwAAAA==.',Ok='Okalm:BAAALAADCgYIBgAAAA==.Okapirette:BAAALAAECgQIBQAAAA==.',Ol='Olgacat:BAABLAAECoEWAAIJAAgIFSFbBQDuAgAJAAgIFSFbBQDuAgAAAA==.',Om='Omayia:BAAALAADCgYIBgAAAA==.Omeada:BAAALAAECgIIAgAAAA==.',Or='Orkau:BAAALAADCgYIBgAAAA==.',Oz='Ozza:BAAALAADCgMIAwABLAAFFAQIBgAKAEEWAA==.',Pa='Papynou:BAAALAAECgIIAgAAAA==.Pawaxe:BAAALAADCggIDwAAAA==.',Pe='Penyble:BAAALAAECgUICQAAAA==.Perisol:BAAALAADCggIDwAAAA==.Persifal:BAAALAADCgQIBAAAAA==.Petronille:BAAALAADCgIIAwAAAA==.',Pi='Piroste:BAAALAAECgYIBgAAAA==.',Po='Polnodianno:BAAALAAECgYIDgAAAA==.Poubz:BAAALAAECgcIDQAAAA==.Poubzouk:BAAALAADCgYIBgAAAA==.',Pt='Ptipoicarote:BAAALAADCggICAAAAA==.Ptitgui:BAAALAADCgQIBAAAAA==.',Pu='Pushandgo:BAAALAAECgMIAwAAAA==.',Qn='Qny:BAAALAADCgMIAwAAAA==.',Qu='Quetzâl:BAAALAAECgYICgAAAA==.',['Qä']='Qälmünö:BAAALAADCgUIBQAAAA==.',Ra='Radamanthis:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Raminagrobis:BAAALAADCggICAAAAA==.Rastamon:BAAALAADCgcICAAAAA==.Rayfinkle:BAAALAADCgQIBAAAAA==.',Re='Redeker:BAAALAADCgQIBAAAAA==.Revawar:BAAALAADCggIDwAAAA==.Revhell:BAAALAADCggIFwAAAA==.',Ry='Rykoh:BAAALAADCgcIBwAAAA==.Ryudø:BAAALAAECgcIDwAAAA==.',Rz='Rzâ:BAAALAADCggICAAAAA==.',['Rø']='Røcket:BAAALAADCgIIAgAAAA==.Røndubidøu:BAAALAADCggICQAAAA==.',['Rû']='Rûbîs:BAAALAADCgcICwAAAA==.',Sa='Saero:BAAALAADCggICAAAAA==.Sakai:BAAALAAECgcIDwAAAA==.Sangeilli:BAAALAADCggIDwAAAA==.Sartana:BAAALAADCgYIBwAAAA==.Sartørius:BAAALAAECgMIBgAAAA==.Saz:BAAALAADCgcIBwAAAA==.',Se='Seiykø:BAAALAAECggIEQAAAA==.Selucia:BAAALAAECgEIAQAAAA==.Sephis:BAAALAADCgcIBwABLAAECgcIDgABAAAAAA==.Sephix:BAAALAAECgcIDgAAAA==.Seryn:BAAALAAECgYIBgAAAA==.',Sh='Shallinfisto:BAAALAAECggIEAAAAA==.Shaniou:BAAALAADCggIFgAAAA==.Shenara:BAAALAAECgIIAwABLAAECgUIBwABAAAAAA==.Sheïyk:BAAALAAECgcICAAAAA==.Shrakle:BAAALAAECgcIEQAAAQ==.Shëëro:BAAALAAECgYICQAAAA==.Shïper:BAAALAAECgQIBwAAAA==.',Si='Sikarna:BAAALAADCggICgAAAA==.Silyar:BAAALAADCggIFwAAAA==.Sintknight:BAAALAAECgIIAgAAAA==.',Sk='Skydeath:BAAALAAECgMIAgAAAA==.Skystormm:BAAALAADCgcIBwAAAA==.',Sl='Slevin:BAABLAAECoERAAILAAgI0R2qDgCNAgALAAgI0R2qDgCNAgAAAA==.Slürm:BAAALAAECgUIBQAAAA==.',Sm='Smoz:BAAALAADCggIDwAAAA==.',Sn='Snyck:BAAALAAECgYICAAAAA==.',So='Soleîl:BAAALAAECgEIAQAAAA==.Sompa:BAAALAADCggIGAAAAA==.',Sp='Speakeasy:BAAALAADCgMIAwAAAA==.',St='Steziel:BAAALAADCggIDwAAAA==.',Su='Subutex:BAAALAADCgcICAAAAA==.Sunja:BAAALAAECgIIAgAAAA==.',Sy='Synopteak:BAAALAAECgIIAgAAAA==.',['Sÿ']='Sÿriane:BAAALAAECggIEQAAAA==.',Ta='Taho:BAAALAAECgMIBQAAAA==.Take:BAAALAAECgcIEQAAAA==.Tarãsboulba:BAAALAADCggIDwABLAAECgcIDQABAAAAAA==.Tatoumonkey:BAAALAAECgUICgAAAA==.Taurantes:BAACLAAFFIEFAAMDAAMISRhGBQC3AAADAAIIahtGBQC3AAAMAAEI/QHLCABCAAAsAAQKgRcAAgMACAgiIp4HABEDAAMACAgiIp4HABEDAAAA.',Th='Thalim:BAAALAAECgYICQAAAA==.Thanaor:BAAALAADCggICAAAAA==.Thâor:BAAALAAECgcIEAAAAA==.',To='Totemixa:BAAALAAECgYIDAAAAA==.Toufoux:BAAALAADCggIDAABLAAECgYIDAABAAAAAA==.',Tr='Trodzia:BAAALAAECgcIDwAAAA==.Trèv:BAAALAAECgUIDAAAAA==.Trøllya:BAAALAAECgYIDAAAAA==.Trøy:BAAALAADCggICAAAAA==.',['Tä']='Tälim:BAAALAAECgYICwAAAA==.',['Tö']='Töøc:BAAALAAECgcIDgAAAA==.',Va='Valaena:BAAALAAECgcICQAAAA==.Valgorn:BAAALAAECgMICAAAAA==.Valløris:BAAALAAECgUIBQAAAA==.Vanael:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.Vandraxi:BAAALAADCggIDgAAAA==.',Vi='Vitalitys:BAAALAAECgcIDQAAAA==.',Vr='Vraccas:BAAALAADCggICQAAAA==.',We='Weubi:BAAALAAECgMIBAAAAA==.',Wo='Wolfrie:BAAALAADCgUIBQAAAA==.Wolvgang:BAAALAAECgcIDgAAAA==.Worldd:BAAALAAECgcICgAAAA==.Wouahoioi:BAAALAAECgMIBgAAAA==.',Xi='Xiandarius:BAAALAAECgcIDgAAAA==.',Xz='Xzensh:BAAALAADCgcIBwABLAAECggICwABAAAAAA==.',Yh='Yhwa:BAAALAAECgQIBQAAAA==.',Yv='Yvalf:BAAALAAECgIIBAAAAA==.',['Yä']='Yäku:BAAALAADCgEIAQAAAA==.',Za='Zaphicham:BAAALAAECgIIAgAAAA==.Zargun:BAAALAAECgIIAgABLAAECgUIBwABAAAAAA==.',Ze='Zemeno:BAACLAAFFIEFAAMIAAMI8g8YAAAIAQAIAAMI8g8YAAAIAQAHAAIINAUJDACZAAAsAAQKgRgAAggACAj2IIkAADQDAAgACAj2IIkAADQDAAAA.Zepandawan:BAAALAAECgcIDwAAAA==.Zepheüs:BAAALAADCggIEgAAAA==.Zephs:BAAALAAECgMIBgAAAA==.',Zi='Zilë:BAAALAAECgMIBAAAAA==.',Zo='Zouille:BAAALAADCgYIBgAAAA==.Zoulzi:BAAALAADCgMIAwAAAA==.',['Äz']='Äzazelle:BAAALAADCgcIBwAAAA==.',['Ça']='Çavavoker:BAAALAADCggICAAAAA==.',['Ðr']='Ðrøwzer:BAAALAAECgEIAgAAAA==.',['Óm']='Ómirrëa:BAAALAADCggIFwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end