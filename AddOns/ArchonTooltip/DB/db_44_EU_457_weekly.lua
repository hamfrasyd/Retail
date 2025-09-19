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
 local lookup = {'Unknown-Unknown','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','Monk-Mistweaver','Paladin-Retribution','Priest-Holy','Shaman-Elemental','Paladin-Protection','Druid-Feral','Mage-Arcane','Mage-Frost','Shaman-Restoration','Priest-Shadow','Warrior-Arms','Warrior-Fury',}; local provider = {region='EU',realm='Nozdormu',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aamun:BAAALAADCggICQABLAAECgQICgABAAAAAA==.Aayla:BAAALAADCggIAQAAAA==.',Ac='Accuresh:BAABLAAECoEVAAICAAgIhhmyEQCUAgACAAgIhhmyEQCUAgAAAA==.Acera:BAAALAADCgQIBAAAAA==.Achatria:BAAALAAECgQIBgAAAA==.Acidera:BAAALAAECgYICgAAAA==.',Ad='Adr:BAAALAAECgEIAQAAAA==.Adrfourdtone:BAAALAAECgYIBgAAAA==.',Ae='Aegón:BAAALAADCgYICwABLAADCggIDwABAAAAAA==.Aetheris:BAAALAAECggIBgAAAA==.',Ak='Akanì:BAAALAADCggIFgAAAA==.',Al='Alamaîs:BAAALAAECgIIAgAAAA==.Aldrellyn:BAAALAAECggIEgAAAA==.Algim:BAAALAAECgEIAQABLAAECggIEgABAAAAAA==.Alutech:BAAALAADCgMIAwAAAA==.',An='Andz:BAAALAADCgYIBgAAAA==.Anfissa:BAAALAADCgYIDQAAAA==.Angeldust:BAAALAADCgYIBgAAAA==.Angerboda:BAAALAADCggICAAAAA==.Annuia:BAAALAAECgMIAwABLAAECgYICgABAAAAAA==.Anschelin:BAAALAADCgcIEAAAAA==.Antista:BAAALAADCgYIBgAAAA==.',Ap='Aphexx:BAAALAADCgYIBgABLAAECgcIDwABAAAAAA==.',Ar='Ariaela:BAAALAADCggIFgAAAA==.Aridh:BAAALAAECgcIEAAAAA==.Artaios:BAAALAADCggIEgABLAADCggIEgABAAAAAA==.Artisan:BAAALAAECgIIAgAAAA==.Aru:BAAALAADCgcIFAAAAA==.Arzandra:BAAALAAECgcIEAAAAA==.Aràza:BAAALAADCgcIBwAAAA==.Arôx:BAAALAADCggIDgAAAA==.',As='Ashyla:BAAALAAECgMIBAAAAA==.Asmodéus:BAAALAADCgcIBwAAAA==.Aspyria:BAAALAADCgYIBgAAAA==.Astoria:BAAALAADCgcICAAAAA==.Asura:BAAALAAECgcIDwAAAA==.',At='Atenae:BAAALAADCgcIBwAAAA==.Atherion:BAAALAAECgIIAwAAAA==.Atthia:BAAALAADCgcIBwAAAA==.',Au='Auora:BAAALAADCgIIAgAAAA==.Auros:BAAALAAECgMIBQAAAA==.Aurreon:BAAALAADCgIIAgAAAA==.',Av='Avadorius:BAAALAADCggICwAAAA==.',Az='Azasel:BAAALAAECgcIEQAAAA==.Azeroth:BAABLAAECoEVAAIDAAgILSO3AgAlAwADAAgILSO3AgAlAwAAAA==.Aztia:BAAALAADCgcIBwAAAA==.',Ba='Bakyma:BAAALAADCgcIBwAAAA==.Balinehl:BAABLAAECoEVAAMEAAgIfSTrAQBcAwAEAAgIfSTrAQBcAwADAAMIwh8/OADJAAAAAA==.Bambas:BAAALAADCggIFgAAAA==.Baschdiê:BAAALAADCggICAAAAA==.Baschdíe:BAAALAAECgEIAQAAAA==.Bassiste:BAAALAAECggIEwAAAA==.',Be='Beastmasterr:BAAALAADCggIFgAAAA==.',Bi='Bieraculix:BAAALAADCgcIBwAAAA==.',Bl='Blasted:BAAALAAECgQICgAAAA==.Blint:BAAALAAECgcIDwAAAA==.Bloodtwister:BAAALAADCggICgAAAA==.Bloodyfamas:BAAALAAECgYICQAAAA==.',Bo='Bogga:BAAALAADCggIFgAAAA==.Boomyftw:BAAALAAECgcIDwAAAA==.Boosty:BAAALAADCggIDQAAAA==.',Br='Bramsalia:BAAALAADCggIDgAAAA==.Bramy:BAAALAAECgEIAQAAAA==.Brenna:BAAALAAECgYICQAAAA==.Brotbox:BAAALAADCgEIAQAAAA==.Brudertikal:BAAALAAECgQIBwAAAA==.Bryce:BAAALAADCggIFQAAAQ==.',Bs='Bsuff:BAAALAAECgQIBgAAAA==.',Bu='Buddâ:BAAALAAECgUIAwAAAA==.Buffhunter:BAAALAADCgQIBAAAAA==.Bumbledore:BAAALAAECgUIBQAAAA==.Butzi:BAAALAADCgQIBAAAAA==.Butzinator:BAAALAADCgQIBAAAAA==.',['Bâ']='Bâlín:BAAALAADCgMIAwAAAA==.',['Bä']='Bärbél:BAAALAADCggICAABLAAECggIFgAFAKAeAA==.',['Bè']='Bèth:BAABLAAECoEXAAMGAAgIiR7mBQDlAgAGAAgIiR7mBQDlAgAHAAMIqQVzFwBnAAAAAA==.',Ca='Calliera:BAAALAADCggIDwAAAA==.Carrywurst:BAAALAADCggICAAAAA==.Casarelis:BAAALAADCggIDwAAAA==.Cattie:BAAALAADCggIDwAAAA==.',Ce='Cereals:BAAALAAECgQIBAAAAA==.',Ch='Chace:BAAALAAECgYIBgABLAAFFAMIAwABAAAAAA==.Charlieze:BAAALAADCgcIBwAAAA==.Chilipepper:BAAALAAECgIIAgAAAA==.',Cl='Claricé:BAAALAAECgEIAQAAAA==.',Co='Cooldown:BAAALAAECgYICQAAAA==.Coolfire:BAAALAAECgEIAQAAAA==.Coronna:BAAALAADCgcIDAAAAA==.Cowalski:BAAALAADCggIDwAAAA==.',Cr='Crossar:BAAALAADCgYIBgAAAA==.Crónck:BAAALAADCgcIBwAAAA==.',['Cá']='Cásius:BAAALAAECggICQAAAA==.',Da='Dalila:BAAALAAECgEIAQAAAA==.Dally:BAAALAAECgYIEQAAAA==.Daradur:BAAALAADCggIFgAAAA==.Darkaan:BAAALAADCgYIEAAAAA==.Darkmidnight:BAAALAAECgQIBQAAAA==.',De='Dejtwelf:BAAALAADCgUIBQAAAA==.',Dj='Djosa:BAAALAADCggIEAABLAADCggIFAABAAAAAA==.',Do='Docglobuli:BAAALAAECgIIAgAAAA==.',Dr='Drahauctyr:BAAALAADCggICAABLAAECggIFAAIAI8MAA==.Dreez:BAAALAAECgYICwAAAA==.Drmiagi:BAAALAAECgYIDQAAAA==.Drumshot:BAAALAAECgYIDwAAAA==.',Du='Durmm:BAAALAADCgQIBwABLAAECgIIAgABAAAAAA==.',Ed='Edigna:BAAALAAECgEIAQAAAA==.',Ei='Eiluna:BAAALAAECgYICQAAAA==.Eisenherz:BAAALAADCggICAAAAA==.',El='Elanis:BAAALAAFFAEIAQAAAA==.Elexiah:BAAALAADCgcICgAAAA==.Elizaveta:BAAALAAECgIIAgAAAA==.Elmador:BAAALAAECgcIEAAAAA==.Elnaror:BAAALAAECgQIBgAAAA==.Elunia:BAAALAAECgQIBAAAAA==.Elydea:BAAALAAECggIDgAAAA==.',En='Enedrai:BAAALAAECgUIBgAAAA==.Engellisa:BAAALAADCgEIAQAAAA==.',Eo='Eowyne:BAAALAAECgIIAwAAAA==.',Er='Erozion:BAAALAAECgYIBwAAAA==.Erunax:BAAALAADCggIDgAAAA==.',Eu='Eulenmania:BAAALAADCgYIBgAAAA==.',Ey='Eyru:BAAALAADCgcIBwAAAA==.',Fa='Fapf:BAAALAAECgcICgAAAA==.',Fe='Ferukh:BAAALAAECgcIEAAAAA==.Feuerkiesel:BAEALAADCggICAAAAA==.Feura:BAAALAAECgQIBQAAAA==.',Fi='Fizzbolt:BAAALAADCggIEAAAAA==.',Fl='Flokì:BAAALAAECgYIBgABLAAECggIDgABAAAAAA==.Fluki:BAAALAADCggIDwABLAAECgQIBAABAAAAAA==.',Fr='Freezio:BAABLAAECoEVAAIJAAgImx5ZIAAWAgAJAAgImx5ZIAAWAgAAAA==.Frosnik:BAAALAAECgQICAAAAA==.',Fu='Fublue:BAAALAAECgQIBQAAAA==.Fumiel:BAAALAAECgIIAgAAAA==.',['Fé']='Féâgh:BAAALAAECgYIDgAAAA==.',['Fí']='Fíréfly:BAAALAAECgIIAgAAAA==.',Ga='Gawki:BAAALAADCggIDwAAAA==.',Ge='Gemrock:BAAALAAECgIIAwAAAA==.',Go='Goner:BAAALAAECgcIDAAAAA==.Gothós:BAAALAADCggIDwAAAA==.',Gr='Gramosch:BAAALAAECgUIBgAAAA==.Grauefrau:BAAALAAECgMIBgAAAA==.Greyeagle:BAABLAAECoEXAAIKAAgIxhvSCgCPAgAKAAgIxhvSCgCPAgAAAA==.Grimsel:BAAALAADCgQIBAAAAA==.',Gu='Gullprime:BAAALAADCggIDwAAAA==.Guts:BAAALAAECgYIDgAAAA==.',['Gé']='Gérard:BAAALAADCggICAABLAAECgcIEQABAAAAAA==.',Ha='Haroshi:BAAALAAECggICwAAAA==.Haumonkey:BAABLAAECoEUAAIIAAgIjww2DwCmAQAIAAgIjww2DwCmAQAAAA==.Haxes:BAAALAADCggIFgAAAA==.Haxxork:BAAALAAECgQIBQAAAA==.',He='Healtax:BAAALAAECgEIAQAAAA==.Heffertonne:BAAALAAECgQIBwAAAA==.Heftîe:BAAALAADCgcIBwAAAA==.Heillin:BAAALAADCgcIBwAAAA==.',Hi='Hiwani:BAAALAADCggIEgAAAA==.',Ho='Hoholy:BAAALAAECgYIDgAAAA==.Hothanatos:BAEALAAECggIDwAAAA==.',Hu='Huetti:BAAALAAECgIIAgAAAA==.Hugohabicht:BAAALAADCgMIAwAAAA==.',Hy='Hyjazinth:BAAALAADCggIEAAAAA==.',['Hî']='Hîrnschaden:BAAALAADCggIDgAAAA==.',Il='Ilidaria:BAAALAADCggIFAAAAA==.Illidias:BAAALAAECgMIBgAAAA==.',Is='Isilios:BAAALAAECgQIBAAAAA==.',Iy='Iyaary:BAAALAADCgcIDgAAAA==.',Ja='Janbo:BAAALAADCgcIDgAAAA==.Jandeny:BAAALAADCggIDgAAAA==.',Je='Jemhadar:BAAALAAECgUIBwAAAA==.',Ji='Jinxîe:BAAALAADCgIIAgAAAA==.',Jo='Jonshami:BAAALAAECggIAwAAAA==.',['Jä']='Jägerhans:BAAALAADCgQIBAAAAA==.',Ka='Kaaya:BAAALAAECgIIAwAAAA==.Kaede:BAAALAADCgcIBwAAAA==.Kaidaria:BAAALAADCggICAAAAA==.Kaiju:BAAALAADCgYIBgAAAA==.Kalestrasza:BAAALAAECgEIAQAAAA==.Kalissra:BAAALAAECgcIDgAAAA==.Kamikaze:BAAALAAECgEIAQAAAA==.Kamizuka:BAAALAAECgIIBAAAAA==.Kampfkrümel:BAAALAAECgIIBgAAAA==.Kasi:BAAALAADCggIDQAAAA==.Katriana:BAAALAAECgMIAwAAAA==.Katsumi:BAAALAAECgIIAgAAAA==.',Ke='Kellsor:BAAALAAECgQICQAAAA==.Kelzur:BAAALAADCgcIBAAAAA==.',Ki='Kichilora:BAAALAADCgEIAQAAAA==.Kieze:BAAALAAECgEIAQAAAA==.Kikky:BAAALAADCgcIDgAAAA==.Kimaty:BAAALAADCgUIBgAAAA==.',Kl='Kleinmonk:BAAALAADCgEIAQAAAA==.',Ko='Kohaai:BAAALAAECgYICwABLAAECgYIFQACAKkfAA==.Kontos:BAAALAADCgMIAwAAAA==.Koohhai:BAABLAAECoEVAAICAAYIqR+nGwA5AgACAAYIqR+nGwA5AgAAAA==.',Kr='Krisna:BAAALAAECgMIAwAAAA==.',Ky='Kyura:BAAALAADCggIFgAAAA==.',['Ká']='Káyona:BAAALAAECgYIBAAAAA==.',['Kï']='Kïkk:BAAALAADCggICAAAAA==.',La='Laertes:BAAALAAECgcIEAAAAA==.Lassandria:BAAALAADCgEIAQAAAA==.Laurelin:BAABLAAECoEWAAMFAAgIoB7WBACZAgAFAAgIoB7WBACZAgAJAAUIpAklWQAVAQAAAA==.Lazahr:BAAALAADCgcIBwAAAA==.',Le='Lechucky:BAAALAAECgEIAQABLAAECggIFgAFAKAeAA==.Leogen:BAAALAAECgMIAQAAAA==.Leovince:BAAALAAECggICwAAAA==.Leuchte:BAAALAADCggICwAAAA==.Leyda:BAAALAADCggIEgAAAA==.',Li='Lisann:BAAALAAECgYICQAAAA==.Lizù:BAABLAAECoEWAAILAAgIKRidDgB4AgALAAgIKRidDgB4AgAAAA==.',Lo='Loleinkeks:BAAALAAECgMIAwAAAA==.',Lu='Lukára:BAAALAAECggICAAAAA==.Lumpo:BAAALAAECgIIAgAAAA==.Lunarios:BAAALAAECgIIAgAAAA==.',Ly='Lyngar:BAAALAAECgIIAgAAAA==.',['Lê']='Lêgôlass:BAAALAADCgcIDAAAAA==.Lêonix:BAAALAADCggICAAAAA==.',Ma='Maerodk:BAAALAADCgcIDQAAAA==.Marfa:BAAALAADCggICAAAAA==.Marliea:BAAALAADCgYIBgAAAA==.Marsilia:BAAALAADCgYIEAAAAA==.Marul:BAAALAAECgMIAwAAAA==.Mautzzi:BAAALAAECgUIBgAAAA==.Maveríc:BAAALAADCggIEAAAAA==.Mawexx:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.',Me='Metaar:BAAALAAECgIIAgAAAA==.Methanol:BAAALAAECggIEwAAAA==.',Mi='Milkaselnuss:BAAALAADCgcIBwAAAA==.Milèèna:BAAALAADCggICAABLAADCggIFAABAAAAAA==.Mirrì:BAAALAADCgYIBgAAAA==.Missmandy:BAABLAAECoEUAAIMAAgIEx9KBACjAgAMAAgIEx9KBACjAgAAAA==.Miwa:BAAALAAECgMIAwAAAA==.Miyuko:BAAALAAECgIIBAAAAA==.Mizutsune:BAAALAAECgEIAQABLAAECgcIEAABAAAAAA==.',Mo='Monkchéri:BAAALAADCgcIBwAAAA==.Mooladin:BAAALAAECgIIAgAAAA==.Morb:BAAALAAECgEIAQAAAA==.Mototimbo:BAAALAADCgMIAwAAAA==.',Mu='Mudoron:BAAALAAECggIEwAAAA==.Mustafar:BAAALAAECggICwAAAA==.Mustang:BAAALAADCgMIAgAAAA==.',['Má']='Márídá:BAAALAADCgcIBwAAAA==.',['Mä']='Männlein:BAAALAADCgcICwAAAA==.',['Mè']='Mèrcý:BAAALAAECgMIBwAAAA==.',['Mö']='Möve:BAAALAAECgcIDwAAAA==.',Na='Nachen:BAAALAADCgcIBwAAAA==.Nairá:BAAALAAECgQIBwAAAA==.Napoleone:BAABLAAECoEXAAIFAAgIkxiVBwBgAgAFAAgIkxiVBwBgAgAAAA==.Nathare:BAAALAAECgQIBwAAAA==.Natháel:BAAALAADCgYIBgAAAA==.Nayoki:BAAALAAECgQIBgAAAA==.Nayu:BAAALAAECgYIDAAAAA==.Nayus:BAAALAAECgIIAwAAAA==.',Ne='Nefi:BAAALAADCgMIAwAAAA==.Nemeia:BAAALAAECgMIBgAAAA==.Neylora:BAAALAAECgcIEQAAAA==.Neyugi:BAABLAAECoEXAAINAAgI+yLmAAA6AwANAAgI+yLmAAA6AwAAAA==.',Ni='Nibbles:BAAALAAECgMIBAAAAA==.Nigma:BAAALAADCgcIDQABLAADCggIFgABAAAAAA==.Nikarah:BAAALAAECgIIAgAAAQ==.Nilopheus:BAAALAADCggICwAAAA==.',No='Noadras:BAAALAADCggIEAAAAA==.Norem:BAAALAADCgQIBAAAAA==.',Nu='Nukeprime:BAACLAAFFIEFAAIOAAMI4RNaCgC2AAAOAAMI4RNaCgC2AAAsAAQKgRcAAw4ACAhTI3QEADYDAA4ACAhTI3QEADYDAA8AAgiNGkU7AHYAAAAA.Numeriê:BAAALAAECgIIBAAAAA==.',Ny='Nyphai:BAAALAAECgQIBwAAAA==.',['Nö']='Nösianna:BAABLAAECoEWAAIQAAgI4hqVDgBTAgAQAAgI4hqVDgBTAgAAAA==.',Op='Ophioneus:BAAALAADCgMIAwAAAA==.',Os='Osarya:BAAALAAECgcIDwAAAA==.',Pa='Paddington:BAAALAADCggICAAAAA==.Paduan:BAAALAAECgcIEAAAAA==.Paladinenser:BAAALAAECggICwAAAA==.',Pe='Petratt:BAABLAAECoEWAAICAAgIDh6DDQDIAgACAAgIDh6DDQDIAgAAAA==.',Ph='Pheyphey:BAAALAAECgEIAQAAAA==.Philanthrop:BAAALAAECgcIBwAAAA==.',Pi='Pinkdrache:BAAALAADCggIDwAAAA==.',Pr='Pradbitt:BAAALAAECgcIDwAAAA==.',Py='Pyb:BAAALAAECgQIBAAAAA==.',Ra='Rafsa:BAAALAADCgMIAwAAAA==.Ralisso:BAAALAADCggICAAAAA==.Raphtari:BAAALAADCggIEAAAAA==.Rawsauce:BAAALAAECgYIDAAAAA==.Raíd:BAAALAADCgYIBgAAAA==.',Re='Rebekah:BAAALAAECgQICQAAAA==.Redarrow:BAAALAADCgUIBQAAAA==.Redb:BAAALAADCggIFAAAAA==.Remedium:BAAALAAECgQIBAAAAA==.',Ri='Riesenrohr:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.Rimuhu:BAAALAAFFAEIAQAAAA==.',Ro='Roderric:BAAALAAECgcIBwAAAA==.Rolarion:BAAALAADCggICAAAAA==.Romeo:BAAALAADCgcIDgAAAA==.Rosalindé:BAAALAADCggICAAAAA==.',Ru='Ruin:BAABLAAECoEWAAIRAAgIsB4hCADcAgARAAgIsB4hCADcAgAAAA==.',['Râ']='Râvenna:BAAALAAECgMIBgAAAA==.',Sa='Saleanor:BAAALAADCgcICgAAAA==.Samoná:BAAALAADCggIFgAAAA==.Sarox:BAAALAADCgYIBwAAAA==.Savadix:BAAALAAECgIIAwAAAA==.Sayana:BAAALAAECgUIAwAAAA==.',Sc='Schallo:BAAALAAECgcICwAAAA==.Schamrech:BAAALAADCgUIBQAAAA==.',Se='Selis:BAAALAAECgMIBQAAAA==.Selmah:BAAALAAECgMIAwAAAA==.Serâs:BAAALAAECgIIAwAAAA==.',Sh='Shanjala:BAAALAAECgQIBwAAAA==.Shareya:BAAALAAECgIIBAAAAA==.Shidoh:BAAALAAECgcIDgAAAA==.Shiipriest:BAAALAADCgcICwABLAADCggICAABAAAAAA==.Shiishaman:BAAALAADCggICAAAAA==.Shinano:BAAALAAECgcIDwAAAA==.Shocksur:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Shyon:BAAALAADCgQIAwAAAA==.Sháx:BAAALAADCgcIDgABLAAECgQICgABAAAAAA==.Shârona:BAAALAADCgcIBwAAAA==.',Si='Sickbooy:BAAALAADCgcICAAAAA==.Sinilga:BAAALAADCgcIEwAAAA==.Sirblack:BAAALAAECgcIDwAAAA==.Siwa:BAAALAAECgEIAQAAAA==.',Sk='Skudde:BAAALAAFFAMIAwAAAA==.',Sm='Smoóve:BAAALAADCgcIBwAAAA==.',Sn='Snuck:BAAALAAECgEIAQAAAA==.',So='Solariá:BAAALAAECgIIAwAAAA==.Sonya:BAAALAADCggIDAAAAA==.',Su='Surrad:BAAALAADCggIDQAAAA==.Suruna:BAAALAADCgYIBgAAAA==.',Sv='Sveena:BAAALAAECgEIAQAAAA==.',Sw='Swêêty:BAAALAADCggIFgAAAA==.',Sy='Sylvannâ:BAAALAAECgMIBAAAAA==.',['Sá']='Sámàel:BAAALAADCgUIBQAAAA==.',Ta='Taelyn:BAAALAAECgQICAAAAA==.Taeylana:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Taijitsu:BAAALAADCggICAAAAA==.Talaná:BAAALAAECgQICgAAAA==.Taling:BAAALAADCggIEAAAAA==.Tarluna:BAAALAAECgYIDQAAAA==.',Te='Teal:BAAALAADCgcIBwAAAA==.Telang:BAAALAADCgcIBwAAAA==.Teldirani:BAAALAADCggIDgAAAA==.Terakles:BAAALAAECgYIDQAAAA==.',Th='Tharen:BAAALAADCgcIBwAAAA==.Thirdy:BAAALAAECgYIBgAAAA==.Thorgrîm:BAAALAADCggIDwAAAA==.Thorrick:BAAALAAECgYIDAAAAA==.Thrarion:BAAALAAECgUIBwAAAA==.',Ti='Titannia:BAAALAADCgcIBwAAAA==.',To='Tonke:BAAALAAECgcIEAAAAA==.',Tr='Treebender:BAAALAAECgYIDQAAAA==.Trym:BAAALAADCgcIBwABLAAECgcIEQABAAAAAA==.',['Tî']='Tîron:BAAALAAECgYICQAAAA==.Tîrîon:BAAALAAECgMIBAABLAAECgYICQABAAAAAA==.',Ul='Ultron:BAAALAAECgQIBgAAAA==.',Va='Valdea:BAABLAAECoEXAAMSAAgIZiRfAABPAwASAAgI5yNfAABPAwATAAQIqhncNgAaAQAAAA==.Valdriin:BAAALAADCgQIBAAAAA==.Valleya:BAAALAAECgYIDwAAAA==.Valthalak:BAAALAAECgEIAQAAAA==.Valveris:BAAALAADCgYIDAABLAAECgQICgABAAAAAA==.Vanaria:BAAALAADCggIDwAAAA==.Varaugh:BAAALAADCgYICgAAAA==.',Ve='Verfehlt:BAAALAAECgQIBAAAAA==.',Vi='Vintor:BAAALAAECgQIBwAAAA==.',Vo='Vonriva:BAAALAADCgMIAwAAAA==.Vontaviouse:BAAALAADCgQIBAAAAA==.',Vu='Vulbo:BAAALAADCggICAAAAA==.',Wa='Wallnir:BAAALAAECgYIDAAAAA==.',We='Weedstyletv:BAAALAADCgcIEAAAAA==.',Wi='Wintår:BAAALAAECgYICQAAAA==.Wisnadi:BAAALAADCgcIBwAAAA==.',Wu='Wulpi:BAAALAADCgcICwAAAA==.',['Wü']='Würzel:BAAALAAECgMICAAAAA==.',Xa='Xaleris:BAAALAADCgcIBwAAAA==.',Ya='Yamada:BAAALAAECgYICQAAAA==.',Yi='Yian:BAAALAADCgcIBwAAAA==.',Yl='Ylenja:BAAALAADCgcIDAABLAAECgQIBgABAAAAAA==.',Yo='Yolari:BAAALAADCggIDgAAAA==.Yolonaise:BAAALAADCgUIBQAAAA==.Yomaru:BAAALAAECgQIBAAAAA==.',Za='Zag:BAAALAAECggICgAAAA==.Zaleria:BAAALAADCgcIBwAAAA==.Zash:BAAALAADCgIIAgAAAA==.',Ze='Zeerax:BAAALAAECgYIBgAAAA==.Zel:BAAALAAECgcIEQAAAA==.',Zi='Zirbe:BAAALAADCggIDAAAAA==.',Zt='Ztrom:BAAALAAECggICAAAAA==.',Zu='Zuloa:BAAALAADCgYIBgABLAAECgMIAwABAAAAAA==.',['Ál']='Álfrigg:BAAALAADCgEIAQAAAA==.',['Âc']='Âchilles:BAAALAADCgQIBAAAAA==.',['Ây']='Âyaya:BAAALAADCgcIBwAAAA==.',['Än']='Änäkin:BAAALAADCgQIBQAAAA==.',['Æs']='Æsrâh:BAAALAAECgMIAwAAAA==.',['Él']='Élameth:BAAALAADCgcIDQABLAAECgQIBgABAAAAAA==.',['Òn']='Òne:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end