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
 local lookup = {'Unknown-Unknown','Paladin-Protection','Druid-Feral','Shaman-Restoration','Shaman-Elemental','Priest-Holy','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Arms','Warrior-Fury','Mage-Arcane','Mage-Fire','Evoker-Devastation','Druid-Restoration','Druid-Balance','Paladin-Holy','Rogue-Assassination','DeathKnight-Unholy','Paladin-Retribution',}; local provider = {region='EU',realm='LaCroisadeécarlate',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abëlus:BAAALAADCgEIAQAAAA==.',Ad='Adhir:BAAALAADCggIDgABLAAECgYIDAABAAAAAA==.Adremalech:BAAALAAECgIIAwAAAA==.',Ah='Ahestrasza:BAAALAADCggICAABLAAECgYIEgABAAAAAQ==.',Al='Albis:BAAALAADCgcIBwAAAA==.Alfötracy:BAAALAADCggIGQAAAA==.Alkknight:BAAALAADCgYICQABLAAECgYIEgABAAAAAA==.Alkrogue:BAAALAAECgYIEgAAAA==.Alsynea:BAAALAAECgcIBwAAAA==.Alysaïa:BAAALAAECgYICQAAAA==.Alïss:BAAALAAECgMIAwAAAA==.',An='Anamelorn:BAAALAADCggICAAAAA==.Andariel:BAAALAADCgcIBwAAAA==.Anwynn:BAAALAAECgMIAwAAAA==.',Ar='Arelline:BAACLAAFFIEGAAICAAMIFx3iAAAMAQACAAMIFx3iAAAMAQAsAAQKgRgAAgIACAgrI4QBADgDAAIACAgrI4QBADgDAAAA.Arifaeapo:BAAALAADCgQIBAAAAA==.Arkayl:BAAALAAECgMIAwAAAA==.Arksham:BAAALAAECgcIEAAAAA==.Artipal:BAAALAAECgMIBAAAAA==.',As='Ascavyr:BAAALAADCgcIBwAAAA==.Asûne:BAAALAADCggICAAAAA==.',At='Ataria:BAAALAADCggIDQAAAA==.Atekovoo:BAAALAADCggICQAAAA==.',Av='Avadar:BAAALAADCgcICAAAAA==.',Az='Azyris:BAAALAAECgIIAgAAAA==.',Ba='Balarog:BAAALAAFFAEIAQAAAA==.Barbaroze:BAAALAADCggICwABLAAECgEIAQABAAAAAA==.Barbouc:BAAALAADCgMIBAAAAA==.',Be='Beastabber:BAACLAAFFIEGAAIDAAMI5RfPAAARAQADAAMI5RfPAAARAQAsAAQKgRUAAgMACAhgI+IAADsDAAMACAhgI+IAADsDAAAA.Beerus:BAAALAADCgYIBgAAAA==.Belennos:BAAALAADCggIDwAAAA==.Belhian:BAAALAADCggIFgAAAA==.Benii:BAAALAAECgYIDQAAAA==.',Bi='Bianco:BAAALAAECgMIBQAAAA==.',Bl='Bloodrops:BAAALAADCggIDwAAAA==.Bloodshark:BAAALAAECgYIBwAAAA==.Blubibulga:BAAALAAECgIIAwAAAA==.',Bo='Bodwick:BAAALAAECgYICgAAAA==.Bouilloncube:BAABLAAECoEVAAIEAAgI3CJsBQDKAgAEAAgI3CJsBQDKAgAAAA==.Bouledefuri:BAAALAADCgcIBwAAAA==.',Br='Brucius:BAAALAAECgYICwAAAA==.',Ch='Chamclya:BAACLAAFFIEJAAIEAAQI9SF0AACnAQAEAAQI9SF0AACnAQAsAAQKgRgAAwUACAgAJrMJAMkCAAUACAgAJrMJAMkCAAQABwgBHJIYAAICAAAA.Chibross:BAAALAADCggICAAAAA==.Chromo:BAAALAAECgYIDAAAAA==.',Cl='Clang:BAAALAAECgMIAwAAAA==.Clöé:BAAALAAECgIIAgAAAA==.',Co='Coldscale:BAAALAAECgcIEAAAAA==.Colorioz:BAABLAAECoEVAAIGAAgIWx1gCQCkAgAGAAgIWx1gCQCkAgAAAA==.',Cp='Cptobvious:BAAALAAECgYIDAAAAA==.',Cr='Crystä:BAACLAAFFIEIAAMHAAQIzQ+sAABVAQAHAAQIzQ+sAABVAQAIAAMIXQdFBAC8AAAsAAQKgRgAAwcACAjXIA0MALICAAcACAhVHw0MALICAAgACAi9FwAAAAAAAAAA.',Da='Danïaleth:BAACLAAFFIELAAMJAAUICx3yAADqAQAJAAUI8BzyAADqAQAKAAEIYR8KCgBbAAAsAAQKgRcABAkACAiJJb4BAF4DAAkACAiFJb4BAF4DAAsABQh+HC0KAKwBAAoAAwiwFT0zAOYAAAAA.Dartt:BAAALAAECgMIBgAAAA==.',De='Deamonslayer:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.Deina:BAAALAAECgIIAgAAAA==.Dekuhunter:BAAALAADCgUICgABLAAECgYICAABAAAAAA==.Destinÿ:BAAALAAECgIIBAAAAA==.',Di='Diamare:BAAALAADCgcICAAAAA==.Diether:BAAALAAECgYIDQAAAA==.Dink:BAAALAADCgQIBQAAAA==.',Do='Dogui:BAAALAAECgIIAgAAAA==.Domastoc:BAAALAADCgcIBwAAAA==.',Dr='Dracnova:BAAALAADCgQIBAAAAA==.Dragoniste:BAAALAAECgMIAwAAAA==.Dromar:BAABLAAECoEWAAMMAAgIuCQXAgCJAgAMAAYIRCUXAgCJAgANAAcI2yDMEQBgAgAAAA==.Drustan:BAAALAAECgUIDAAAAA==.',Dz='Dzertik:BAAALAAECgYIBwAAAA==.',['Dé']='Déku:BAAALAADCgUIBwABLAAECgYICAABAAAAAA==.Dékû:BAAALAADCgYIBgABLAAECgYICAABAAAAAA==.Dékûpriest:BAAALAADCgcIBwAAAA==.Délandra:BAAALAAECgcIEQAAAA==.',Ed='Edgy:BAAALAAECgUIBgAAAA==.Edrahil:BAAALAADCggIDAAAAA==.',El='Eldragogol:BAACLAAFFIEKAAQJAAUIvBuJAQCNAQAJAAQIUhuJAQCNAQAKAAIIMwtxBgChAAALAAEIZh1mAQBWAAAsAAQKgR0ABAkACAjqJJYCAEoDAAkACAgZJJYCAEoDAAoABQh4IAcSANABAAsABggcFOcIAMgBAAAA.Eldrâ:BAAALAAECgYICwAAAA==.Elenthus:BAAALAADCggICAAAAA==.Elhìn:BAAALAAECgIIAwABLAAFFAIIAwABAAAAAA==.Elihn:BAAALAAFFAIIAwAAAA==.Elnéas:BAAALAADCggICAAAAA==.Elrodk:BAAALAADCggIDgAAAA==.Elsiom:BAAALAADCgcIBwAAAA==.Elyvoker:BAAALAAECgMIBAAAAA==.Elëdhwën:BAAALAAECgEIAQAAAA==.',En='Enitonora:BAAALAAECgcIEgAAAA==.',Er='Eresarn:BAAALAADCgMIAwAAAA==.',Es='Escarcha:BAAALAAECgMIBgAAAA==.Estesia:BAAALAADCgcIBwAAAA==.',Et='Etania:BAAALAADCgMIBQAAAA==.',Ev='Evhen:BAAALAAECgcICwAAAA==.',Fa='Facepàlm:BAEALAADCgcIBwABLAAECgYICQABAAAAAA==.Faellyanne:BAACLAAFFIEJAAIOAAQIZhuXAQCNAQAOAAQIZhuXAQCNAQAsAAQKgRgAAw4ACAifJTkIAAQDAA4ACAifJTkIAAQDAA8AAQiyHwAAAAAAAAAA.Fakania:BAAALAADCgcIBwAAAA==.Fawkkes:BAAALAADCggICAAAAA==.',Fe='Feamago:BAABLAAECoEUAAIOAAgIhCExCgDrAgAOAAgIhCExCgDrAgAAAA==.',Fi='Filsae:BAAALAADCggIFQAAAA==.',Fl='Fléchette:BAAALAADCgYIBgAAAA==.',Ga='Gaambit:BAAALAAECgMIAwAAAA==.Galathil:BAAALAAECgYICAAAAA==.Galaxciel:BAAALAAECgIIAgAAAA==.Galazare:BAAALAAECgMIAwAAAA==.Galz:BAAALAAECgIIAgAAAA==.Gandâlf:BAAALAAECgYICAAAAA==.',Ge='Genovha:BAAALAADCggICAABLAAECgIIBAABAAAAAA==.',Gl='Glargh:BAAALAAECgEIAQAAAA==.',Go='Gouki:BAAALAAECgQIBAAAAA==.Gouteça:BAAALAAECgEIAQAAAA==.',Gr='Graphix:BAAALAADCggIDwAAAA==.',Ha='Habanera:BAAALAAECgYIBgAAAA==.Hantman:BAAALAAECggIDQAAAA==.Harno:BAAALAAECgIIAwAAAA==.',He='Herrellius:BAAALAAECgYICgAAAA==.',Hi='Hibouh:BAAALAADCggIDwAAAA==.Hitagi:BAAALAAECgcICwAAAA==.',Ho='Horochii:BAAALAAECgYICAAAAA==.',Hu='Huminob:BAABLAAECoEYAAIQAAgIjB5sBwDBAgAQAAgIjB5sBwDBAgAAAA==.',['Hä']='Häçéæ:BAAALAADCgUIBQAAAA==.',['Hé']='Hélèonor:BAAALAAECgYIDAAAAA==.',Ic='Icekrim:BAAALAAECgEIAQAAAA==.',Il='Ilidark:BAAALAAECgQIBAAAAA==.Illsira:BAAALAAECgEIAQAAAA==.',Ir='Iriz:BAAALAADCgIIAgAAAA==.Ironerf:BAAALAADCgcICgAAAA==.',It='Itorabbi:BAAALAADCgYICgAAAA==.',Ja='Jaesthènis:BAAALAAECgcICQAAAA==.Jassen:BAAALAAECgEIAQAAAA==.',Jc='Jcvð:BAAALAADCgYIBgAAAA==.',Ji='Jibile:BAAALAADCggICQAAAA==.',Ju='Jujunull:BAABLAAECoEWAAMRAAgIEiSHAQAjAwARAAgIEiSHAQAjAwASAAEIiQhXTgA5AAAAAA==.Junia:BAAALAAECgMIAwAAAA==.',Jy='Jynn:BAAALAADCgEIAQAAAA==.',Ka='Kaahaly:BAAALAAECgYIDQAAAA==.Kaledar:BAAALAAECgQIBAAAAA==.Kamoraz:BAAALAADCggICAAAAA==.Kamui:BAAALAADCgMIAwAAAA==.Karkadroodof:BAAALAAECgIIAgAAAA==.Karnicou:BAAALAADCggICAABLAAECgIIAwABAAAAAA==.',Ke='Keibou:BAABLAAECoEYAAITAAgILR0lAwDIAgATAAgILR0lAwDIAgAAAA==.',Kh='Khaltarion:BAAALAAECgEIAQAAAA==.',Ko='Koringar:BAACLAAFFIEJAAINAAQIPRkEAQCNAQANAAQIPRkEAQCNAQAsAAQKgRgAAg0ACAhIJpYGAAwDAA0ACAhIJpYGAAwDAAAA.',Kr='Krosus:BAAALAADCgUICAAAAA==.',Kw='Kwacha:BAAALAADCgcIBwAAAA==.',['Kè']='Kèlls:BAAALAAECgYIBgAAAA==.',['Kø']='Køruptiøn:BAAALAAECgEIAQAAAA==.',La='Laboulaite:BAAALAAECgIIAgAAAA==.Laenihunt:BAABLAAECoEaAAIIAAgITiSUAQBCAwAIAAgITiSUAQBCAwAAAA==.Lankaï:BAAALAAECgMIAwAAAA==.Larililarila:BAAALAADCgcIBwAAAA==.Laryfishrman:BAAALAADCggIAgAAAA==.Layñie:BAACLAAFFIEFAAMDAAQIZAl3AAAyAQADAAQIvAh3AAAyAQASAAEIyAOACgBCAAAsAAQKgRYAAxIACAiPJOAIALICABIACAiUIeAIALICAAMABwitH/ADAKACAAAA.',Le='Leyth:BAAALAAECgYIDAAAAA==.',Li='Ligthbringer:BAAALAAECgYICAAAAA==.',Lo='Loonies:BAAALAAECgYIBgAAAA==.Loonwolf:BAAALAADCgcIBwAAAA==.',Lu='Lurik:BAAALAADCggICQAAAA==.Luthielle:BAAALAADCggIDwAAAA==.',Ly='Lysna:BAAALAAECgMIAwAAAA==.Lyxiane:BAAALAAECgYICQABLAAFFAUICwAJAAsdAA==.',Ma='Malatiki:BAAALAADCgYIBgAAAA==.Malentir:BAAALAADCggICAAAAA==.Manubrium:BAAALAAECgEIAgAAAA==.Marsmara:BAAALAAECgYICwAAAA==.Marîkâ:BAAALAAECgMIAwAAAA==.Maseidr:BAAALAAECgQIBAAAAA==.Maveilatitan:BAAALAADCggICQAAAA==.Maënor:BAAALAAECgUIBQAAAA==.',Me='Meitav:BAAALAAECgMIAwAAAA==.Mezankor:BAAALAAECgEIAQAAAA==.',Mi='Mikasasept:BAAALAAECggIDQAAAA==.Mimita:BAAALAAECgIIAgAAAA==.Mirad:BAAALAAECgcIEgAAAA==.Mirron:BAAALAADCggICQAAAA==.Miâ:BAAALAADCgEIAQAAAA==.',Mo='Moki:BAAALAAECgMIBgAAAA==.Monkeybeam:BAAALAAECgMIAwAAAA==.Monklya:BAAALAAECgQIBQABLAAFFAQICQAEAPUhAA==.',Mu='Muyo:BAAALAAECgcIDwAAAA==.',['Mâ']='Mâkâ:BAAALAAECgIIAwAAAA==.Mârika:BAAALAAECgIIAgAAAA==.',['Mû']='Mûtenroshi:BAAALAAECgcIDgAAAA==.',Na='Nainlando:BAAALAADCggIDgABLAADCggIFgABAAAAAA==.Nairf:BAACLAAFFIEIAAIFAAQIOhw5AQB5AQAFAAQIOhw5AQB5AQAsAAQKgRgAAgUACAgyJpgHAO8CAAUACAgyJpgHAO8CAAAA.Nairøx:BAAALAAECgEIAQAAAA==.Nastyy:BAABLAAECoEYAAIHAAgI7R8PCADsAgAHAAgI7R8PCADsAgAAAA==.',Ne='Nelmy:BAAALAAECgMIAwAAAA==.Nemia:BAAALAADCgIIAgAAAA==.',Ng='Nguyen:BAAALAADCggIBwAAAA==.',Ni='Nibelheimr:BAAALAAECgIIAwAAAA==.Nibraisheimr:BAAALAADCggICwAAAA==.Nigthwing:BAAALAADCggIEAAAAA==.Nigun:BAAALAADCgcIBwAAAA==.Niline:BAAALAADCgcIBwAAAA==.Nitrojunkie:BAAALAAECgMIAwAAAA==.',No='Norigosa:BAAALAAECgIIAgAAAA==.',Ny='Nyna:BAAALAAECgEIAQAAAA==.Nyrven:BAAALAAECgQIBwAAAA==.',['Nø']='Nøløsham:BAAALAAECgMIAwAAAA==.',Ob='Obak:BAAALAAECgcIDAAAAA==.',Ol='Oliu:BAAALAAECgUIDQAAAA==.',Or='Orloom:BAAALAADCggIDwAAAA==.',Pa='Pajeh:BAAALAAECgMIBgAAAA==.Palucheur:BAAALAADCgMIAwAAAA==.Pandarbare:BAAALAAFFAEIAQAAAA==.Parrish:BAAALAADCgcICgAAAA==.Parsifal:BAAALAADCggIDgAAAA==.Partialymoon:BAAALAADCgcIBwAAAA==.',Pe='Penuts:BAAALAADCgIIAgAAAA==.Perihan:BAAALAAECgQIBgAAAA==.Persélock:BAAALAAFFAIIAQAAAA==.Persépriest:BAAALAADCggICAABLAAFFAIIAQABAAAAAA==.',Pi='Pimlarou:BAAALAAECgMIAwAAAA==.',Pl='Pléospouge:BAAALAADCggIEAAAAA==.',Po='Poilochon:BAABLAAECoEUAAILAAgIZhvyAQCvAgALAAgIZhvyAQCvAgAAAA==.',Pt='Ptigro:BAAALAADCgUIBQAAAA==.Ptitekanine:BAAALAADCgcIBwAAAA==.',Py='Pyrite:BAAALAADCgMIAwAAAA==.Pyxi:BAEALAAECgYICQAAAA==.',['Pø']='Pøupøugne:BAAALAADCggIDgAAAA==.',Ra='Ranaka:BAACLAAFFIEJAAMJAAQIHh+xAQCCAQAJAAQIJh2xAQCCAQAKAAIIQBlLAwC0AAAsAAQKgRgABAkACAg9JgMHAPICAAkACAj2JQMHAPICAAsABAjuIOQLAIsBAAoAAgh8JLE7ALcAAAAA.Rappsnitch:BAAALAADCggIDQAAAA==.Rarespawn:BAAALAAECgQIBAAAAA==.Rayden:BAABLAAECoEUAAIUAAgIcxzYBwC+AgAUAAgIcxzYBwC+AgAAAA==.Razuvious:BAAALAADCggICAAAAA==.',Re='Reds:BAAALAAECgMIBgAAAA==.Rembie:BAAALAADCggIFAAAAA==.',Rh='Rheya:BAAALAADCgEIAQAAAA==.Rhum:BAAALAAECgUIBgAAAA==.',Ri='Rireelfique:BAAALAAECgYIDAAAAA==.',Ro='Rorschiasse:BAAALAAFFAIIAwAAAA==.',Ru='Rui:BAAALAADCgcIBwAAAA==.',Ry='Rynne:BAAALAADCggIEwAAAA==.',['Rï']='Rïeka:BAAALAAECgUIBQAAAA==.',Sa='Sabato:BAAALAADCgUIBQAAAA==.Sabôt:BAAALAAECgYIDAAAAA==.Saeka:BAAALAADCgcIBwAAAA==.Sangrina:BAAALAAECgIIAgAAAA==.Sarakos:BAAALAAECgMIAwAAAA==.Saykaptain:BAAALAADCgYICwAAAA==.',Se='Sealennrv:BAABLAAECoEYAAIVAAgImxpmCAAsAgAVAAgImxpmCAAsAgAAAA==.Sedu:BAAALAADCggIFQAAAA==.Sekhret:BAABLAAECoEVAAMKAAgIMSAsAwC+AgAKAAcIXCIsAwC+AgAJAAMIbBhsQwDmAAAAAA==.',Sh='Sharolix:BAAALAAECgEIAQAAAA==.Shhira:BAAALAADCgUICQAAAA==.Shhirayuki:BAAALAADCgMIAwAAAA==.Sholla:BAAALAADCgUIBQAAAA==.Shïva:BAAALAADCggICAAAAA==.',Si='Sidon:BAAALAADCggICAAAAA==.Sinolia:BAAALAADCggIEAAAAA==.Sipyx:BAAALAAECgYIAwAAAA==.Sita:BAAALAADCggICgAAAA==.Siéa:BAAALAADCgcICAAAAA==.',Sk='Skaff:BAAALAAECgQIBwAAAA==.Skelton:BAAALAADCgcIBwAAAA==.Skyro:BAAALAAECgQIBAAAAA==.',So='Solarya:BAAALAAECgIIAgAAAA==.Soyboy:BAAALAAECgUIBgAAAA==.',St='Stefler:BAAALAAECgYIDQAAAA==.',Sy='Symbule:BAAALAAECgMIBgAAAA==.',Ta='Tafaim:BAAALAADCggICAAAAA==.Tarkuzad:BAAALAAECgcICwAAAA==.Taurentoro:BAAALAAECgUIBwAAAA==.Taÿt:BAAALAADCgQIAwAAAA==.',Th='Thaldriel:BAAALAAECgMIAwAAAA==.Thorvx:BAAALAAECgEIAQAAAA==.Thundder:BAAALAADCgYIBgAAAA==.Thäwäl:BAAALAAECgYIBgAAAA==.',To='Touchsky:BAAALAAECgYIBgAAAA==.',Tr='Tryxe:BAABLAAECoEXAAIWAAgIvhx1MADBAQAWAAgIvhx1MADBAQAAAA==.',Ts='Tsünia:BAAALAAECgEIAQAAAA==.',Ty='Tyes:BAAALAADCggICAAAAA==.',['Tï']='Tïll:BAAALAAECgIIBQAAAA==.',Un='Unholy:BAAALAAECgMIAgAAAA==.',Ur='Urunjin:BAAALAADCgcIDQAAAA==.',Va='Vahslof:BAAALAADCgIIAQAAAA==.Vanaderad:BAAALAAECgMIBAAAAA==.Varä:BAAALAADCgMIAwAAAA==.',Ve='Venom:BAAALAADCggICAAAAA==.',Vi='Vickyladin:BAAALAADCggICAAAAA==.',Vo='Vorajwarrior:BAAALAAECggIBQAAAA==.',Wa='Waban:BAAALAADCggICAAAAA==.Wanderlei:BAAALAAFFAIIAgAAAA==.Wartotem:BAAALAADCggIDAAAAA==.',We='Weisheng:BAAALAADCgMIAwAAAA==.',Wo='Wouallybis:BAAALAAECgcIDQAAAA==.',Xa='Xalatath:BAAALAAECgMIAwAAAA==.Xamoof:BAAALAAECgIIAwAAAA==.',Xi='Xilaka:BAAALAAECgEIAQAAAA==.',Ya='Yaeluira:BAAALAADCgYIBwAAAA==.Yasu:BAACLAAFFIEIAAIOAAQIFBnxAQBsAQAOAAQIFBnxAQBsAQAsAAQKgRgAAg4ACAg5JasPALICAA4ACAg5JasPALICAAAA.',Yo='Yocrita:BAAALAAECgIIAQAAAA==.Yonétsu:BAAALAADCgMIAwAAAA==.',Yr='Yragosa:BAAALAADCgUIBAAAAA==.',Ys='Ysae:BAAALAAECgMIAwAAAA==.',Yu='Yulia:BAAALAAECgMIBQAAAA==.Yushei:BAAALAAECgcIEAAAAA==.',['Yè']='Yèwéi:BAAALAADCgcICQAAAA==.',Za='Zaaléone:BAAALAADCggICAAAAA==.Zadimus:BAAALAADCggICAAAAA==.Zazalolo:BAAALAAECgIIAgAAAA==.',Zh='Zhanä:BAAALAAECgMIBwAAAQ==.',Zi='Zingiber:BAAALAAECgcIBwAAAA==.Zinjho:BAAALAAECgMIAwAAAA==.',Zo='Zouz:BAAALAAECggICAAAAA==.',Zy='Zyf:BAAALAADCggICAAAAA==.',['Zé']='Zélyna:BAAALAADCgYIBwAAAA==.',['Zë']='Zëkhæ:BAAALAADCgcIBwAAAA==.',['Éh']='Éh:BAAALAADCggICAAAAA==.',['Ët']='Ëthån:BAAALAAECgQIBwAAAA==.',['Ôr']='Ôrazumî:BAAALAAECgEIAQAAAA==.',['Ùn']='Ùnder:BAAALAADCggICQAAAA==.',['Ür']='Üranium:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end