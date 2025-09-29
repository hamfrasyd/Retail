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
 local lookup = {'Mage-Arcane','Monk-Mistweaver','Shaman-Restoration','Monk-Brewmaster','Paladin-Holy','Shaman-Elemental','Paladin-Retribution','Hunter-BeastMastery','Priest-Shadow','DemonHunter-Havoc','Warrior-Fury','Druid-Balance','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Protection','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','DeathKnight-Blood','Shaman-Enhancement','Monk-Windwalker','Hunter-Marksmanship','Hunter-Survival','Warrior-Arms','Warrior-Protection','Druid-Restoration','Evoker-Devastation','DeathKnight-Unholy','Rogue-Assassination','Warlock-Affliction',}; local provider = {region='EU',realm='Varimathras',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aazøg:BAABLAAECoEjAAIBAAgIFxxwJQCiAgABAAgIFxxwJQCiAgAAAA==.',Ac='Acønia:BAAALAAECgYICQAAAA==.Acønïa:BAAALAADCgYICAAAAA==.',Ad='Adamar:BAAALAAECgYIBwAAAA==.',Ae='Aelynh:BAAALAAECgYICQABLAAFFAUIEQACABEWAA==.Aelynn:BAACLAAFFIERAAICAAUIERZ2AwCqAQACAAUIERZ2AwCqAQAsAAQKgU0AAgIACAimI5UCADcDAAIACAimI5UCADcDAAAA.Aelyyn:BAAALAAECgYIEQABLAAFFAUIEQACABEWAA==.',Ai='Aimis:BAAALAADCgUIBQAAAA==.',Ak='Akapulco:BAAALAAECgYIDwAAAA==.Akuona:BAAALAADCggICAAAAA==.Akylä:BAABLAAECoEUAAIDAAcIfhHxcwBlAQADAAcIfhHxcwBlAQAAAA==.Akylô:BAAALAAECgcIDgABLAAECgcIFAADAH4RAA==.',Al='Alcassoulet:BAAALAADCgQIBgAAAA==.Aliz:BAABLAAFFIEQAAIEAAcIZx+SAACcAgAEAAcIZx+SAACcAgAAAA==.Allita:BAAALAADCgYIBgAAAA==.',Am='Amoranna:BAAALAADCggIGAAAAA==.',An='Andegis:BAAALAAECgIIAgAAAA==.Anely:BAAALAADCggIKgAAAA==.Angamor:BAAALAAECgcIDAAAAA==.',Ao='Aodren:BAABLAAECoEgAAIFAAgIjxOvGwAFAgAFAAgIjxOvGwAFAgAAAA==.',Ar='Arkaliane:BAAALAAECgIIAwABLAAFFAIIBQAGAOIBAA==.Arkonan:BAABLAAECoEUAAIHAAYILQSe7wDgAAAHAAYILQSe7wDgAAAAAA==.Arthyos:BAAALAAECgQIBQAAAA==.Arzaloth:BAAALAAECgcIDQAAAA==.',As='Asaevok:BAAALAAECgIIAgAAAA==.Asaflash:BAAALAADCgcIBwAAAA==.Asaforever:BAAALAAECgIIAgAAAA==.Asayondaime:BAAALAADCgcIBwAAAA==.Ashbringer:BAAALAAECgEIAQAAAA==.Ashurà:BAAALAADCggIDAAAAA==.Asrageth:BAAALAADCggIFgAAAA==.',At='Atamagatakai:BAAALAAECgYIEQAAAA==.Attovst:BAABLAAECoEkAAIBAAgIKBqtPwAuAgABAAgIKBqtPwAuAgAAAA==.',Az='Azuria:BAAALAADCgcIBwAAAA==.',Ba='Barbun:BAAALAADCgUICQAAAA==.Bastèt:BAAALAAECgUIDAAAAA==.',Be='Belzebûth:BAAALAAECgcIDQAAAA==.Bepo:BAAALAAECgcIDgAAAA==.',Bo='Bobby:BAAALAADCgYIDQAAAA==.Borujerd:BAAALAADCggIDwABLAAFFAMIBwAIAEUWAA==.Boumbatta:BAAALAAECgYIBgAAAA==.Bourrepif:BAAALAADCgMIAwAAAA==.',Ca='Calypsô:BAAALAAECgMIAwAAAA==.Carlocalamar:BAACLAAFFIEFAAIJAAIIIxksFACgAAAJAAIIIxksFACgAAAsAAQKgSYAAgkACAjiIBMPAOkCAAkACAjiIBMPAOkCAAAA.Cassecoup:BAAALAADCggICAAAAA==.',Ch='Chaccall:BAAALAAECgYIBwAAAA==.Chagrin:BAAALAAECgUIBwAAAA==.Charlélox:BAABLAAECoEiAAIKAAgIciRrDwAiAwAKAAgIciRrDwAiAwAAAA==.Chekupp:BAABLAAECoEiAAILAAgIZhxLLwBKAgALAAgIZhxLLwBKAgAAAA==.Chel:BAAALAADCgYIBgAAAA==.Chô:BAABLAAECoEVAAIMAAgIXR8aEwCrAgAMAAgIXR8aEwCrAgAAAA==.',Cl='Closetodeath:BAABLAAECoEhAAMNAAcIVBL7HQCTAQANAAcIVBL7HQCTAQAKAAcIxAiCrQA+AQAAAA==.',Co='Cocoyolas:BAACLAAFFIEFAAIMAAIIdCBxDwCuAAAMAAIIdCBxDwCuAAAsAAQKgSAAAgwACAgZJQoGAEADAAwACAgZJQoGAEADAAAA.Cortacoïde:BAABLAAECoEYAAIMAAYIph92LQDhAQAMAAYIph92LQDhAQAAAA==.Cortacula:BAAALAADCgYIBgABLAAECgYIGAAMAKYfAA==.Cortaleptik:BAAALAADCggICAABLAAECgYIGAAMAKYfAA==.Cortarke:BAAALAADCggIGQABLAAECgYIGAAMAKYfAA==.Cortaxe:BAAALAADCggICAABLAAECgYIGAAMAKYfAA==.Couetecouete:BAAALAADCggIDwAAAA==.',Da='Daya:BAAALAAECgIIBQABLAAECgUIDAAOAAAAAA==.',De='Debelon:BAAALAAECgcIBwAAAA==.Dehous:BAABLAAECoEcAAIPAAcI5x43DwBjAgAPAAcI5x43DwBjAgAAAA==.Desmonphe:BAABLAAECoEWAAMQAAYIdhjcWwCpAQAQAAYIXBfcWwCpAQARAAUIsxXgPABXAQAAAA==.Deudakas:BAAALAAECgYIBwAAAA==.',Di='Diablue:BAAALAADCggICAAAAA==.Divinia:BAAALAAECgYIDwAAAA==.Diøxÿde:BAAALAAECgEIAQAAAA==.',Dk='Dkpsulait:BAABLAAECoEjAAMSAAgIEyVnDgAqAwASAAgIMSRnDgAqAwATAAMIYiHMKgDcAAAAAA==.',Do='Doomyniste:BAAALAAECgYICAAAAA==.',Dr='Dragby:BAAALAAECgcIDQAAAA==.Dragcouette:BAAALAADCgEIAQAAAA==.Drakara:BAAALAADCgYICwAAAA==.Drayka:BAAALAADCggICAAAAA==.Dricannos:BAAALAAECgQIBwAAAA==.Droven:BAAALAAECgUIDwAAAA==.',Du='Dunken:BAACLAAFFIEFAAILAAIIeBfLHACoAAALAAIIeBfLHACoAAAsAAQKgSYAAgsACAihIPwSAPsCAAsACAihIPwSAPsCAAAA.Duomonk:BAAALAADCggICAAAAA==.',['Dé']='Déimos:BAAALAADCgMIAwAAAA==.Démonistah:BAAALAAECgYICAAAAA==.',['Dø']='Døømsday:BAAALAAECgYIDAAAAA==.',Ed='Edo:BAABLAAECoEgAAIRAAgIxhviDACHAgARAAgIxhviDACHAgAAAA==.',El='Elidoux:BAABLAAECoEXAAIUAAcINBWdDQDrAQAUAAcINBWdDQDrAQAAAA==.Ell:BAAALAADCggIDgAAAA==.Elspectre:BAAALAADCgUIBQAAAA==.',Em='Emperatork:BAAALAADCgcIBwABLAAECggIGAAQAHogAA==.',En='Enorelbot:BAABLAAECoEbAAMCAAcIIyKhCwCHAgACAAcIIyKhCwCHAgAVAAQIcw+9PwDoAAABLAAECggIHQAFABYdAA==.Entropy:BAAALAAECgQIBQAAAA==.',Et='Ethlinn:BAAALAADCggIDwAAAA==.Ethnna:BAAALAAECgcIBwAAAA==.',Ev='Evannescence:BAAALAADCgcIBwAAAA==.',Fa='Falkamir:BAAALAADCggICAAAAA==.',Fe='Felir:BAAALAADCggIFgAAAA==.Fendheria:BAAALAAECgIIAwAAAA==.Fendrïl:BAAALAAECggICAAAAA==.',Fl='Flashdream:BAAALAAECgMIAwAAAA==.',Fo='Forlor:BAAALAAECgYIDgAAAA==.',Fu='Fumemocouete:BAAALAADCgcIBwAAAA==.',Ga='Gaagàa:BAABLAAECoEcAAQIAAYIXhdPjABlAQAIAAYIpRNPjABlAQAWAAMI8hHhggCpAAAXAAUIbxYAAAAAAAAAAA==.Galyrith:BAAALAAECgYIDwAAAA==.Ganessha:BAAALAAECgcIDAAAAA==.Gargamelle:BAAALAADCgYICQAAAA==.',Ge='Gersiflet:BAAALAADCgIIAgAAAA==.',Gi='Gilgãmesh:BAAALAAECggICAAAAA==.',Gl='Glirïn:BAAALAAECgUIBQAAAA==.',Go='Gonzochimy:BAAALAADCggILgABLAAECgYIBgAOAAAAAA==.Gonzodaelia:BAABLAAECoEVAAIQAAYIrhjIVgC5AQAQAAYIrhjIVgC5AQABLAAECgYIBgAOAAAAAA==.Gonzodihan:BAAALAADCggICAABLAAECgYIBgAOAAAAAA==.Gonzoshen:BAAALAAECgYIBgAAAA==.',Gr='Gravalibaba:BAAALAADCggICwABLAAECggIKgAMACQiAA==.Graveraiser:BAAALAAECgUICAABLAAFFAIIBQAGAOIBAA==.Grizler:BAAALAADCgQIBAABLAAFFAIIBQASAIchAA==.',Gu='Gundarth:BAABLAAECoEUAAIWAAgINRntHgBXAgAWAAgINRntHgBXAgAAAA==.',['Gâ']='Gâagaa:BAAALAADCgIIAwAAAA==.',['Gé']='Génézya:BAAALAADCggICAAAAA==.',['Gî']='Gîpsy:BAAALAAECgYICAAAAA==.',Ha='Hakntoo:BAAALAADCgEIAQAAAA==.Hamaât:BAAALAADCgYIBgAAAA==.Hamesh:BAAALAAECgYIDAAAAA==.Haquecoucou:BAAALAAECgIIAwAAAA==.Harlock:BAAALAAECggIDAAAAA==.Hawkeyex:BAAALAADCgYIBgAAAA==.',He='Heypahd:BAEALAAECgYICgAAAA==.',Hi='Hiboux:BAAALAAECgYICwAAAA==.Hikazu:BAACLAAFFIENAAIIAAUItB2cCQByAQAIAAUItB2cCQByAQAsAAQKgTIAAggACAidJggDAG0DAAgACAidJggDAG0DAAAA.',Hy='Hykazü:BAAALAAECgEIAQAAAA==.Hylam:BAAALAAECgQIBwAAAA==.Hylania:BAAALAADCggIFwAAAA==.Hypotène:BAABLAAECoEdAAQLAAgIGR9BFwDdAgALAAgIGR9BFwDdAgAYAAMI/B4xHAANAQAZAAMIFBf7WgC4AAAAAA==.',Il='Illyasvield:BAAALAADCggICAAAAA==.',In='Insånity:BAAALAAECgEIAQAAAA==.Inøri:BAAALAAECgYIEQAAAA==.',Ir='Irachi:BAABLAAECoEXAAIHAAYIxAaU2gASAQAHAAYIxAaU2gASAQAAAA==.',Is='Isilmë:BAAALAADCggIDgAAAA==.',Ja='Jalyne:BAABLAAECoEYAAIDAAYIAhaLbwBwAQADAAYIAhaLbwBwAQAAAA==.',Je='Jenz:BAACLAAFFIETAAIPAAYIihKsAQDJAQAPAAYIihKsAQDJAQAsAAQKgSUAAg8ACAiPJXwCAFcDAA8ACAiPJXwCAFcDAAEsAAUUBwgQAAQAZx8A.',Ji='Jiziee:BAABLAAECoEZAAILAAcIFiPlHAC3AgALAAcIFiPlHAC3AgAAAA==.',Jy='Jylane:BAAALAAECgIIAgAAAA==.',Ka='Kamu:BAAALAADCgEIAQAAAA==.Kaqn:BAAALAAECgMIAwAAAA==.Karalian:BAAALAAECgYIEgABLAAFFAIIBQAGAOIBAA==.Karaliane:BAACLAAFFIEFAAIGAAII4gH8KABsAAAGAAII4gH8KABsAAAsAAQKgSAABAYACAhPHUgfAIgCAAYACAj3G0gfAIgCABQABQi1EfMZABQBAAMABAiKArLvAGgAAAAA.Kardra:BAABLAAECoEXAAMDAAYIKBKnhAA9AQADAAYIKBKnhAA9AQAUAAMI1gXxIABzAAAAAA==.Kassim:BAAALAAECgYICQAAAA==.Kazrock:BAABLAAECoEdAAIUAAcI+R/1CABQAgAUAAcI+R/1CABQAgAAAA==.',Ke='Ketuirint:BAABLAAECoEiAAIPAAgIhx1WCgCrAgAPAAgIhx1WCgCrAgAAAA==.Ketumdi:BAAALAAECggICAAAAA==.',Kh='Khairhy:BAAALAAECgYIBwAAAA==.Kharon:BAAALAADCgUIBQAAAA==.',Ki='Kinuty:BAAALAAFFAIIAgAAAA==.Kironash:BAAALAAECgMIBgAAAA==.Kironyx:BAAALAADCgcIDgAAAA==.Kisadh:BAAALAADCggIEAAAAA==.Kisaé:BAAALAADCgcICgAAAA==.',Ko='Kolosse:BAAALAAECgYIEAAAAA==.',Kr='Kramassax:BAAALAAECgYIEQAAAA==.Kratøx:BAAALAADCgcIBwAAAA==.Krumolcate:BAAALAADCggICAAAAA==.',['Kø']='Køsetzu:BAAALAADCgcIEAAAAA==.',La='Labuchette:BAABLAAECoEWAAIZAAcIPhHMOABgAQAZAAcIPhHMOABgAQAAAA==.Lamevengeres:BAAALAAECgQIBwAAAA==.Lanatur:BAACLAAFFIEKAAIaAAIImyEAEgC/AAAaAAIImyEAEgC/AAAsAAQKgRsAAxoACAiwHCcnAB0CABoABghsIScnAB0CAAwACAi/FyAtAOIBAAAA.',Le='Leilam:BAAALAAECgcIDgAAAA==.',Li='Licht:BAAALAAECgYICwAAAA==.Lilvee:BAAALAAECgcIBwABLAAECggIHQAFABYdAA==.Lirkana:BAAALAADCgYICAABLAAFFAIIBQAGAOIBAA==.',Lo='Lombax:BAABLAAECoEcAAIPAAgI+A66LwBLAQAPAAgI+A66LwBLAQAAAA==.Louac:BAABLAAECoEYAAIPAAYIdCS5FgARAgAPAAYIdCS5FgARAgAAAA==.',Ls='Lsaltar:BAAALAADCgYIBgAAAA==.',Lu='Ludð:BAABLAAECoEXAAIIAAYImg2HoQA8AQAIAAYImg2HoQA8AQAAAA==.Luryah:BAAALAADCgEIAQAAAA==.',Ly='Lyliana:BAAALAADCggICAAAAA==.',['Lö']='Lök:BAAALAADCgUIBQAAAA==.',['Lü']='Lüdivine:BAAALAADCggICAAAAA==.',Ma='Magicalguys:BAAALAADCgQIBAAAAA==.Mahh:BAAALAAECgUICgAAAA==.Maks:BAAALAAECgYIDAAAAA==.Mariateresa:BAAALAAECgQIBQAAAA==.Maskimir:BAAALAAECgYIEwAAAA==.Mathysded:BAAALAAECgYIDgAAAA==.Maylicia:BAAALAADCgIIAgAAAA==.',Me='Menorsraza:BAABLAAECoEXAAIbAAcIERKkKAC3AQAbAAcIERKkKAC3AQAAAA==.',Mi='Mimi:BAAALAADCggICAAAAA==.Mimold:BAAALAAECggICAAAAA==.Minionegnome:BAAALAAECgQIDAAAAA==.Miyu:BAAALAAECgYIEAAAAA==.',Mo='Moorwen:BAAALAADCgYIBgAAAA==.Morgun:BAACLAAFFIEFAAISAAIIhyGqJQC3AAASAAIIhyGqJQC3AAAsAAQKgSAAAxIACAiaIN8kALsCABIACAiaIN8kALsCABwAAQhICOxWAC4AAAAA.Morks:BAAALAAECgYICgAAAA==.Morrgh:BAAALAAECgMIAwAAAA==.Movezlang:BAAALAADCgMIAwAAAA==.',Mu='Munolas:BAAALAADCggIGwAAAA==.',My='Myndra:BAACLAAFFIEXAAIaAAYICSHsAABVAgAaAAYICSHsAABVAgAsAAQKgSkAAhoACAgYIMoQALICABoACAgYIMoQALICAAAA.Myrcella:BAAALAAECgYIDAAAAA==.Mystik:BAAALAAECgcICwAAAA==.Myuléona:BAAALAAECgMIBQAAAA==.',['Mû']='Mûfasa:BAAALAADCggICAAAAA==.',Na='Nartibald:BAAALAADCggIEAAAAA==.Narwel:BAAALAAECgMIAwABLAAECgUIDAAOAAAAAA==.',Ne='Nephtýs:BAAALAAECgEIAQAAAA==.Neyssë:BAABLAAECoEVAAIdAAcIJh3cFwBHAgAdAAcIJh3cFwBHAgAAAA==.',No='Nolystia:BAAALAAECgYIEgAAAA==.',Ny='Nyhal:BAAALAAECgMIAwAAAA==.',Oc='Océanias:BAAALAAECgIIAgAAAA==.',Pa='Palaplaie:BAAALAAECgIIAgAAAA==.Pasdacdutout:BAAALAADCgUIBQAAAA==.Pasnetdutout:BAABLAAECoEUAAMDAAcINxuKPAACAgADAAcINxuKPAACAgAGAAEIjwb6sgAoAAAAAA==.',Pe='Petitgateau:BAAALAAECgQIBAAAAA==.',Pr='Prayse:BAABLAAECoEdAAMcAAgIIxbEEAA4AgAcAAgIIxbEEAA4AgATAAQI7ApZLwCrAAAAAA==.Prisia:BAAALAADCgcIDAAAAA==.Provencal:BAAALAADCgcIBwAAAA==.',['Pé']='Pédiluve:BAAALAAECgcIDQAAAA==.',['Pï']='Pïmousse:BAAALAADCgcIDQAAAA==.',Ra='Rapsodyr:BAAALAADCgcICwAAAA==.',Re='Reems:BAAALAADCgYIBgAAAA==.Reillo:BAAALAAECgUIBQAAAA==.',Rh='Rheïa:BAAALAADCgcICQAAAA==.Rhoodelin:BAAALAAECgMIAwAAAA==.',Ri='Rizzøtonno:BAAALAADCggICAAAAA==.',Ro='Rozzi:BAAALAADCggICQAAAA==.',Ry='Ryûnosuke:BAAALAAECgEIAQAAAA==.',Sa='Saeco:BAAALAAECggICgABLAAECggIDQAOAAAAAA==.Saeko:BAAALAAECggIDQAAAA==.Sakamesh:BAAALAADCgcIBwAAAA==.Sanctidrizzt:BAAALAAECgIIBAAAAA==.Sanjay:BAACLAAFFIEOAAIVAAUIQwofBABaAQAVAAUIQwofBABaAQAsAAQKgSMAAhUACAiKHoQLAMACABUACAiKHoQLAMACAAAA.Satørù:BAAALAADCgYIDAAAAA==.',Sc='Scoory:BAAALAADCgIIAgABLAAFFAIIBQAGAOIBAA==.',Se='Septimus:BAABLAAECoEXAAISAAYIRgZk7QADAQASAAYIRgZk7QADAQAAAA==.',Sh='Shalti:BAACLAAFFIEFAAIJAAIIDw4TGgCMAAAJAAIIDw4TGgCMAAAsAAQKgScAAgkACAjWHQcYAJYCAAkACAjWHQcYAJYCAAAA.Shankss:BAAALAAECgcICQAAAA==.Shasta:BAAALAADCggIAQAAAA==.Shirayuki:BAAALAAECgYIDwAAAA==.Shivoa:BAAALAADCgEIAQAAAA==.Shunn:BAAALAADCggICQAAAA==.',Sk='Skibidî:BAAALAADCgMIAwAAAA==.',Sl='Sløw:BAAALAAECgIIAgAAAA==.',So='Solsagan:BAAALAADCggIGgAAAA==.',Sp='Spectre:BAABLAAECoEmAAIcAAgInSNNAwAqAwAcAAgInSNNAwAqAwAAAA==.',St='Stefflock:BAABLAAECoEkAAQRAAgIThqHEABfAgARAAgIFxqHEABfAgAeAAUIcRHFFgA4AQAQAAQIdgcUtQCfAAAAAA==.',Sy='Syril:BAAALAAECgIIAgAAAA==.Syyn:BAAALAADCgYIBgAAAA==.',['Sä']='Säta:BAABLAAECoEjAAIIAAgIMCImFQDlAgAIAAgIMCImFQDlAgAAAA==.Sätâs:BAAALAADCggICAABLAAECggIIwAIADAiAA==.',['Sí']='Síanka:BAAALAADCgEIAQAAAA==.',Ta='Tadiana:BAAALAADCggICAAAAA==.Talion:BAAALAAECggIEQAAAA==.Taluani:BAAALAAECgMIAwAAAA==.Tauridrizzt:BAAALAAECgIIBAAAAA==.',Th='Thiorgnole:BAAALAAECgMICAAAAA==.Thiorval:BAAALAAECgYIBgAAAA==.Thylda:BAABLAAECoElAAIHAAcIHQirvABMAQAHAAcIHQirvABMAQAAAA==.',Ti='Tidworth:BAAALAAECgIIAgABLAAFFAIIBQAGAOIBAA==.Timmida:BAAALAAECgQICQAAAA==.Tiranosorus:BAABLAAECoEXAAIGAAcIPBVDPQDlAQAGAAcIPBVDPQDlAQAAAA==.Tiwynn:BAAALAAECgYIBgAAAA==.',To='Tomoharu:BAAALAAECgMIAwAAAA==.',Tr='Troméo:BAABLAAECoEZAAIQAAcIVhduRQD2AQAQAAcIVhduRQD2AQAAAA==.Trynd:BAABLAAECoEkAAISAAgIviDwFgD9AgASAAgIviDwFgD9AgAAAA==.',Ts='Tsunimi:BAAALAAECgIIAgAAAA==.',Ty='Tyrvo:BAABLAAECoEWAAMSAAYIwRFQugBeAQASAAYIwRFQugBeAQAcAAEI3AA5WgANAAAAAA==.Tyvar:BAABLAAECoEYAAILAAYIBxlBXACjAQALAAYIBxlBXACjAQAAAA==.',['Té']='Tétrazépam:BAAALAAECgYIEQAAAA==.',['Tï']='Tïnk:BAABLAAECoEdAAMFAAgIFh13DgCBAgAFAAgIFh13DgCBAgAHAAMICAsAAAAAAAAAAA==.',Va='Vachementoro:BAABLAAECoEfAAIIAAcI8QfRrwAgAQAIAAcI8QfRrwAgAQAAAA==.Vador:BAAALAAECgIIAgAAAA==.Valador:BAAALAADCggIDQAAAA==.',Ve='Vegewarian:BAAALAAECggIDgAAAA==.Vestara:BAAALAADCgcIBwAAAA==.',Wa='Warlack:BAABLAAECoEbAAIeAAcIXSLmAwCtAgAeAAcIXSLmAwCtAgAAAA==.',We='Weuzork:BAAALAADCgYIBgAAAA==.',Xh='Xhyotine:BAAALAADCggIGwAAAA==.',Xy='Xywoxuw:BAAALAADCgYIDAABLAADCggICAAOAAAAAA==.',Ya='Yatuwalker:BAABLAAECoEhAAIHAAcIsg87lACUAQAHAAcIsg87lACUAQAAAA==.',Yu='Yugo:BAAALAAECgMIAwAAAA==.Yukino:BAAALAADCggICwAAAA==.',Za='Zamadsu:BAAALAADCgMIAwAAAA==.Zaryndrøth:BAAALAADCgYIBgAAAA==.',Zo='Zolunk:BAAALAADCgYICQAAAA==.',Zy='Zywu:BAAALAADCggICAAAAA==.',['Zé']='Zéddicus:BAAALAAECgEIAQAAAA==.',['Æn']='Ænzu:BAAALAADCggIIwAAAA==.',['Ér']='Érèzir:BAAALAAECgEIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end