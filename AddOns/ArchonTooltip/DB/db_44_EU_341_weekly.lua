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
 local lookup = {'Unknown-Unknown','Druid-Restoration','Paladin-Protection','Paladin-Retribution','Priest-Shadow','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Mage-Arcane','Paladin-Holy','Warlock-Affliction','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Druid-Balance','Shaman-Enhancement',}; local provider = {region='EU',realm='Terenas',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ab='Abbytailz:BAAALAAECgcIDAAAAA==.',Ad='Adew:BAAALAAECgQIBwAAAA==.Adlez:BAAALAAECgMIBAAAAA==.',Ae='Aegwynne:BAAALAAECgMIBgAAAA==.Aeshan:BAAALAAECgEIAQABLAAECgYIEQABAAAAAA==.',Ah='Ahsoorkatano:BAAALAADCgIIAgAAAA==.',Ai='Aidra:BAAALAADCgcIBwAAAA==.',Al='Alatariel:BAAALAADCggICAAAAA==.Alcina:BAAALAADCgcIBwAAAA==.Alimorrisane:BAAALAADCgUIAwAAAA==.Alistrana:BAAALAAECgYICAAAAA==.Alomomola:BAAALAAECgMIBgAAAA==.Alteril:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Alysielqt:BAABLAAECoEZAAICAAgIjRelEQABAgACAAgIjRelEQABAgAAAA==.',An='Analyzer:BAAALAAECgIIAgAAAA==.Anxiety:BAAALAAECgMIAwAAAA==.',Ap='Applejuimce:BAAALAADCgQIBAAAAA==.',Ar='Araceli:BAAALAADCgIIAgAAAA==.Arael:BAAALAADCgMIAwAAAA==.Arcanik:BAAALAADCgYIBgAAAA==.Ariadine:BAAALAAECgYICQAAAA==.Arpaclïsse:BAAALAAECgQIBAAAAA==.',As='Asari:BAAALAADCggIDwAAAA==.',Av='Avyanna:BAAALAADCgcICwAAAA==.',Az='Azara:BAAALAADCgcIDAABLAADCggICAABAAAAAA==.',Ba='Baddwolf:BAAALAAECgMIBAAAAA==.Baelthas:BAAALAADCgEIAQAAAA==.Balefin:BAAALAADCgYIBgAAAA==.Balvimir:BAAALAAECgIIAgAAAA==.Bao:BAAALAAECggICAAAAA==.Baryon:BAAALAAECgMIAwAAAA==.Bazzeruk:BAAALAAECgMIBgAAAA==.',Be='Bertyr:BAAALAADCggIEAABLAAECgYICAABAAAAAA==.Bettybear:BAAALAAECgIIAwAAAA==.',Bi='Bigrawz:BAAALAAECgMIBgAAAA==.Binnky:BAAALAADCgcIBwABLAAECgMIAwABAAAAAA==.Bips:BAAALAAECgMIBgAAAA==.Bisomerc:BAAALAADCggICAAAAA==.Bitzy:BAAALAAECgUICQAAAA==.',Bj='Bjørstrup:BAAALAADCgEIAQAAAA==.',Bl='Blamdruid:BAAALAAECgYICgAAAA==.',Bo='Bobbylightx:BAAALAAECgMIBgAAAA==.Bodilkjær:BAAALAAECgQIBwAAAA==.Bovarius:BAABLAAECoEaAAMDAAgIwBZnBwAmAgADAAgIwBZnBwAmAgAEAAgItgdQQABrAQAAAA==.Boynextdoor:BAAALAAECgUIBQAAAA==.',Br='Bramin:BAAALAAECgIIAgAAAA==.Brevox:BAAALAADCgUIBQAAAA==.Brewgob:BAAALAADCgUIBQAAAA==.Broozelee:BAAALAADCggICAABLAAFFAQIBwAFAO4TAA==.Bréunor:BAAALAAECgYIBwAAAA==.',Bs='Bs:BAAALAAECgIIAgAAAA==.',Bu='Buckcherry:BAAALAADCgcIDQAAAA==.Buckdich:BAAALAAECgIIAgAAAA==.Buttbrain:BAABLAAECoEXAAMGAAcIvyC4EgB/AgAGAAcIvyC4EgB/AgAHAAII9RuIIACMAAAAAA==.',['Bà']='Bàlthazar:BAAALAAECgQIBwAAAA==.',['Bé']='Béorfs:BAAALAAECgMIAwAAAA==.',Ca='Caleb:BAAALAAECgQIBwAAAA==.Callandas:BAAALAAECgQIBgAAAA==.Calyxanide:BAAALAADCggIFAABLAAECgcIFwAHAPIWAA==.Camdo:BAAALAADCgEIAQAAAA==.Capellini:BAAALAAECgQIBgAAAA==.',Ce='Celestra:BAAALAADCgYIBgAAAA==.Cerena:BAACLAAFFIEFAAIIAAMIgBpgAAAbAQAIAAMIgBpgAAAbAQAsAAQKgRgAAggACAjZJYYAAHQDAAgACAjZJYYAAHQDAAAA.',Ch='Chromaprime:BAAALAAECgMIBwAAAA==.',Ci='Cirius:BAAALAADCggICAAAAA==.',Co='Contorta:BAAALAAECgMIAwAAAA==.Corpseeater:BAAALAADCgIIAgAAAA==.',Cr='Crazynutter:BAAALAADCgcIBwAAAA==.Crompas:BAAALAAECgMIAwAAAA==.',['Cé']='Célestra:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.',Da='Daddiesgirl:BAAALAADCgIIAgAAAA==.Dadi:BAAALAADCgcIBwAAAA==.Darckense:BAAALAAECgMIBAAAAA==.Darkwillow:BAAALAADCgcIBwAAAA==.Davy:BAAALAADCgcIAQAAAA==.',Db='Dbhunter:BAAALAAECgMIBAAAAA==.Dblock:BAAALAAECgUIBQAAAA==.',De='Dedolas:BAAALAADCgIIAgAAAA==.Despair:BAAALAAECgMIAwAAAA==.Dethyl:BAAALAADCgQIBAAAAA==.',Di='Diizziie:BAAALAADCggICAAAAA==.Divalaguna:BAAALAAECgMIBgAAAA==.',Dj='Djyn:BAAALAADCggICAAAAA==.',Do='Docski:BAAALAAECgUICgAAAA==.Doorn:BAAALAADCgQIBgAAAA==.',Dr='Dralin:BAAALAAECgMIBAAAAA==.Dreamnight:BAAALAADCggIDwAAAA==.Drevnal:BAAALAADCggIDwAAAA==.Driadus:BAAALAAECgQIBwAAAA==.',['Dö']='Död:BAAALAADCggICAAAAA==.',Ej='Ej:BAAALAAECgMIBQAAAA==.',El='Eldory:BAAALAAECgIIAgAAAA==.Elephas:BAAALAAECgYICQAAAA==.Ellesia:BAAALAADCgcIBwABLAAECgMIBgABAAAAAA==.Ellex:BAAALAAECgYIDAAAAA==.Elmira:BAAALAADCggICAAAAA==.',Em='Empíre:BAAALAAECgMIBQABLAAECgYICgABAAAAAA==.',En='Enelysion:BAAALAADCgIIAgAAAA==.',Er='Eren:BAAALAAECggIEQAAAA==.',Es='Estibus:BAAALAADCgcIBwAAAA==.',Ev='Evenstar:BAAALAAECgIIAgAAAA==.',Fe='Fearless:BAAALAADCgcIBgAAAA==.Felixs:BAAALAAECgYIDQAAAA==.',Fi='Fiddles:BAAALAADCgcICwABLAAECgIIAgABAAAAAA==.',Fl='Flaaffy:BAAALAADCggICAAAAA==.Flaps:BAAALAADCggIFgAAAA==.Fluffycuddle:BAAALAADCgMIAwAAAA==.',Fo='Forfe:BAABLAAECoEUAAIJAAgIYRq5GABVAgAJAAgIYRq5GABVAgAAAA==.',Fr='Frank:BAABLAAECoEaAAMKAAgIdRUZCwAcAgAKAAgIdRUZCwAcAgAEAAUIYw8wVgAIAQAAAA==.Frelsey:BAAALAAECggICAAAAA==.',Ga='Galehad:BAAALAADCggIEAAAAA==.',Ge='Geirask:BAAALAAECgEIAQABLAAECggIFQALALUhAA==.',Gh='Ghangy:BAAALAAECgUICgAAAA==.',Gi='Gihei:BAAALAADCgcIBwAAAA==.Gilrandar:BAAALAADCggIDwAAAA==.Gimblie:BAAALAADCggIDwABLAAECgYIDQABAAAAAA==.Gipsy:BAAALAADCggIFgAAAA==.',Gl='Glitchdragon:BAABLAAECoEWAAMMAAgIJBy8CQCHAgAMAAgIJBy8CQCHAgANAAEI1ghgHAAsAAAAAA==.',Go='Golo:BAAALAAECgMIBAAAAA==.',Gr='Graius:BAAALAAECgYICQAAAA==.',Ha='Halewyn:BAAALAAECgMIBAAAAA==.Haworthia:BAABLAAECoEaAAIOAAgIBg7yGQDmAQAOAAgIBg7yGQDmAQAAAA==.',He='Healya:BAAALAADCgUIBQAAAA==.Heikneuter:BAAALAAECgYICQAAAA==.Hexa:BAAALAADCgIIAgAAAQ==.',Ho='Hojo:BAAALAADCgYIBgAAAA==.Hoktouh:BAAALAADCggICAABLAAECgcIFwAGAL8gAA==.Homeless:BAAALAAECgYIDgAAAA==.Honeydiw:BAAALAAECgUICQAAAA==.Honglair:BAAALAADCgYICAAAAA==.',Hr='Hriss:BAAALAAECgUICQABLAAECgYICgABAAAAAA==.',Hu='Huinë:BAAALAAECgMIAwAAAA==.Huquintas:BAAALAADCggIDwAAAA==.',Ia='Ianthe:BAAALAADCgEIAQAAAA==.',Ic='Icywind:BAAALAAECgcIEQAAAQ==.',Ie='Iemon:BAAALAADCgUIBQAAAA==.',Il='Illidankmeme:BAAALAAECgMIAQAAAA==.',Im='Imnotnice:BAAALAAECgMIBgAAAA==.',In='Insievwinsie:BAAALAAECgYIBwAAAA==.',Ir='Irsara:BAAALAAECgIIAgAAAA==.',Is='Ishana:BAAALAADCgcIBwAAAA==.Isunael:BAABLAAECoEVAAQLAAgItSEHAwBwAgALAAcIoBsHAwBwAgAPAAYI9yFWEgBEAgAQAAEIGBGRTwBHAAAAAA==.',Ja='Jabroni:BAAALAAECgcIEQAAAA==.Jauthor:BAAALAADCggICAAAAA==.',Je='Jendi:BAAALAADCggICAABLAAECgYIEQABAAAAAA==.Jenever:BAAALAAECgIIAgAAAA==.',Ka='Kalmin:BAAALAADCgcICQAAAA==.Kazmere:BAAALAAECgMIBAAAAA==.',Ke='Keir:BAAALAADCgIIAgAAAA==.Kenkyukai:BAAALAAECgcIDQAAAA==.Kennygee:BAAALAADCgEIAQAAAA==.Keycard:BAAALAADCgcIBwAAAA==.',Kh='Khalldrogo:BAAALAADCgcIBwAAAA==.',Ki='Kiku:BAAALAADCggICAAAAA==.Kiriosh:BAAALAAECgYIDQAAAA==.Kissmyaxe:BAAALAADCgcIBwAAAA==.Kitchlol:BAAALAAECgcIBwAAAA==.',Kl='Klyvarn:BAAALAAFFAEIAQAAAA==.',Kn='Knallala:BAAALAAECgQIBwAAAA==.Knuckleskull:BAAALAAECgMIAwAAAA==.Knucknorris:BAAALAAECgQIBwABLAAECgYIDgABAAAAAA==.',Ko='Kobaaz:BAAALAAECgEIAQAAAA==.Kolbasha:BAAALAAECggIBgAAAA==.',Ku='Kungfucow:BAAALAAECgIIAgAAAA==.Kurillia:BAAALAADCggICAAAAA==.Kuzzko:BAAALAADCgEIAQAAAA==.',Ky='Kyrugan:BAABLAAECoEbAAIEAAgIIyKqCAD8AgAEAAgIIyKqCAD8AgAAAA==.',['Kí']='Kítten:BAAALAAECgYICwAAAA==.',La='Lansera:BAAALAADCggIEAAAAA==.',Le='Legendairy:BAAALAAECgYIDgAAAA==.Lenox:BAAALAAECgMIBAAAAA==.Lenthyr:BAAALAAECgMIAwAAAA==.Letummortis:BAAALAAECgIIAgAAAA==.',Li='Lightfurry:BAAALAADCggICAAAAA==.Linkle:BAAALAADCggICAAAAA==.',Lo='Lolaen:BAAALAADCgMIAwAAAA==.Lolik:BAAALAAFFAIIAwAAAA==.Loovia:BAAALAADCgcIBwABLAADCgcIBwABAAAAAA==.',Lu='Lunak:BAAALAAECgcICgAAAA==.Lurna:BAAALAAECgMIBAAAAA==.',Ma='Machupo:BAAALAADCgUIBQAAAA==.Madrigal:BAAALAAECgQIBwAAAA==.Magoa:BAAALAAECgQIBwAAAA==.Malakit:BAABLAAECoEXAAIHAAcI8hYGCgDEAQAHAAcI8hYGCgDEAQAAAA==.Marcai:BAAALAADCggICAAAAA==.',Me='Meowforpi:BAAALAADCgcIBwAAAA==.',Mi='Minimaw:BAAALAADCgIIAgABLAAECgMIAwABAAAAAA==.',Mn='Mnementhia:BAAALAAECgMIBAAAAA==.',Mo='Moot:BAAALAADCgYIAgAAAA==.Morrigan:BAAALAADCggICAAAAA==.Mortva:BAAALAADCgcIBwAAAA==.Mourn:BAAALAAECgYICQAAAA==.',Mp='Mpalarinos:BAAALAADCgQIBAAAAA==.',Mu='Muhri:BAAALAADCgQIBAABLAAECgMIBwABAAAAAA==.Murrett:BAAALAADCggIEAAAAA==.',My='Mylder:BAAALAADCgIIAgAAAA==.Mylderman:BAAALAAECgMIBgAAAA==.Mylen:BAAALAADCgcICgAAAA==.Mynth:BAAALAAECgMIAwAAAA==.Myrtle:BAAALAAECgQIBAAAAA==.',['Mó']='Mória:BAAALAAECgMIBgAAAA==.',Na='Nantosuelta:BAAALAADCgMIBAAAAA==.Nausicaä:BAAALAADCgcIBwAAAA==.',Ne='Nep:BAAALAADCggIEAAAAA==.Nespina:BAAALAADCgcIBwAAAA==.Nevra:BAAALAAECgEIAQAAAA==.Nez:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.Nezdruid:BAAALAAECgYIDgAAAA==.',Ni='Nightbert:BAAALAAECgYICAAAAA==.',No='Novalie:BAAALAAECgQIBwAAAA==.',['Ná']='Nástybrawn:BAACLAAFFIEFAAIRAAMIgw99AwAEAQARAAMIgw99AwAEAQAsAAQKgRgAAhEACAidIUsGAA0DABEACAidIUsGAA0DAAAA.',['Nî']='Nîdhel:BAAALAAECgYIBgAAAA==.',['Nó']='Nódin:BAAALAAECgQIBQAAAA==.',Od='Odinsbane:BAAALAAECgEIAQAAAA==.',Og='Ogroth:BAABLAAECoEUAAMLAAgIWhEdDACEAQALAAYI2xEdDACEAQAPAAgICQq0NgAkAQAAAA==.',Oo='Oorling:BAAALAADCgIIAgAAAA==.Oorshi:BAAALAADCggICAAAAA==.Ooze:BAAALAAECgYICwABLAAFFAQIBwAFAO4TAA==.',Pa='Paladíno:BAAALAAECgMIBgAAAA==.Paltnacke:BAAALAAECgcIEgAAAA==.Pammeow:BAACLAAFFIEFAAISAAMIhhU8AgD0AAASAAMIhhU8AgD0AAAsAAQKgRgAAhIACAhbJk4AAI0DABIACAhbJk4AAI0DAAAA.Pandion:BAAALAAECgIIAQAAAA==.Pangbruden:BAAALAADCgcICwAAAA==.',Ph='Phailadin:BAAALAADCgQIBAAAAA==.Pheebe:BAAALAADCgcICgAAAA==.',Pi='Picasso:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Pieces:BAAALAADCggIEAAAAA==.',Pl='Plaguelander:BAAALAADCgYIBgAAAA==.Platotem:BAAALAAECgMIAwAAAA==.',Pr='Primrose:BAAALAAECgcIEQAAAA==.',Qu='Quigone:BAAALAAECgYIBgABLAAECgYIDQABAAAAAA==.Quilthalas:BAAALAAECgIIAwAAAA==.',Ra='Raeka:BAAALAAECgIIAgAAAA==.Rage:BAAALAAECgYIDAAAAA==.Rammsund:BAAALAAECgIIAgAAAA==.Randuwin:BAAALAADCgEIAQAAAA==.Ranesh:BAAALAAECgIIAgAAAA==.Rawlplug:BAAALAAECgUICQAAAA==.',Re='Rendaeri:BAABLAAECoEaAAIGAAgIbRnDEQCJAgAGAAgIbRnDEQCJAgAAAA==.Revok:BAAALAAECgcIEAAAAA==.',Ri='Richarda:BAAALAAECgIIAgAAAA==.',Ro='Rocoto:BAAALAAECgEIAQAAAA==.Rollothenice:BAAALAADCggIDwAAAA==.Rosscko:BAAALAADCgMIAwAAAA==.',Ru='Rulai:BAAALAADCggIGwAAAA==.',Ry='Ryac:BAAALAAECgUICQAAAA==.Ryzuki:BAAALAAECgEIAQAAAA==.',['Rå']='Råge:BAAALAADCggICAAAAA==.',['Rè']='Rèkt:BAAALAAECgMIBgAAAA==.',Sa='Sallyjo:BAAALAAECgMIBAAAAA==.Sammuell:BAAALAADCgUICQAAAA==.Sandalphon:BAAALAAECgIIAgAAAA==.Saplîng:BAAALAADCgUICQAAAA==.',Sc='Scareclaw:BAAALAADCgUIBQAAAA==.Scurlban:BAAALAAECgMIBAAAAA==.',Se='Senap:BAAALAADCggICwAAAA==.Seyla:BAAALAADCgUIBQABLAAECgIIAwABAAAAAA==.',Sg='Sgtmifii:BAAALAADCgYICQAAAA==.',Sh='Shelayra:BAAALAAECgcIEQAAAA==.Shockedsloth:BAAALAAECgMIBgAAAA==.Shyyba:BAAALAAECgMIAwAAAA==.Shímsham:BAABLAAECoEaAAIOAAgIFSVuAQBrAwAOAAgIFSVuAQBrAwAAAA==.',Si='Sibylla:BAAALAADCgcIBwAAAA==.Siepelrocker:BAAALAADCgcIBwAAAA==.Silvers:BAAALAADCgYIBgAAAA==.Simplehuman:BAAALAAECgMIAwAAAA==.',Sj='Sjarcanist:BAAALAAECgMIBQAAAA==.',Sk='Skuld:BAAALAADCgEIAQAAAA==.Skweel:BAAALAAECgMIAwAAAA==.',Sl='Slompalompa:BAAALAADCggICAAAAA==.Slydee:BAAALAAECgYIDAAAAA==.',Sn='Snowsnout:BAAALAADCggIEAAAAA==.Snowydemon:BAAALAAECgEIAQAAAA==.',So='Solarlights:BAAALAAECgYIDQAAAA==.Soulpresent:BAAALAADCggICAAAAA==.',Sp='Spatial:BAAALAADCgIIAgAAAA==.Spijskop:BAAALAADCgcIBwAAAA==.Spritzee:BAAALAADCggIDgAAAA==.',Sq='Squigy:BAAALAAECgMIAwAAAA==.',Ss='Sshrek:BAAALAAECgEIAQAAAA==.',St='Stagstalker:BAAALAAECgQIBwAAAA==.Stalk:BAAALAAECgMIAwAAAA==.Stepxsismish:BAAALAAECgMIAwAAAA==.Stoneheart:BAAALAADCggIGAAAAA==.',Su='Sude:BAAALAADCggIEAAAAA==.',Sw='Swifftménd:BAAALAADCgEIAQAAAA==.',Sy='Syrastrasza:BAAALAAECgEIAQAAAA==.',Ta='Tallera:BAAALAAECgYICgAAAA==.Talwyn:BAAALAAECgUICgAAAA==.',Te='Tegaela:BAAALAAECgUIBQAAAA==.Tessi:BAAALAAECgMIBAAAAA==.',Th='Thatsbadass:BAAALAADCggIGAAAAA==.Thegis:BAAALAAECgMIAwAAAA==.Theorocks:BAAALAAECgUICQAAAA==.Thisbearge:BAAALAAECgYIBgAAAA==.Thrallzdad:BAAALAADCggIFwAAAA==.Thylae:BAAALAAECgIIAgAAAA==.',Ti='Tigon:BAAALAAECgMIBAAAAA==.Tissy:BAAALAADCgcIBwAAAA==.',To='Toblerone:BAAALAAECgYICgAAAA==.Tolstokotov:BAAALAAECggIBgAAAA==.Toteamic:BAAALAAECgQIBAAAAA==.Totemin:BAABLAAECoEWAAITAAgI6xfoAwBeAgATAAgI6xfoAwBeAgAAAA==.',Tr='Treesurgeon:BAAALAADCggICAAAAA==.Troetie:BAAALAADCggIFgAAAA==.',Ts='Tsira:BAAALAADCgcICwAAAA==.',Tu='Tundra:BAAALAAECgMIBAAAAA==.',Ty='Typhoon:BAAALAAECgMIBAAAAA==.',['Tå']='Tåylør:BAAALAAECgYIDAAAAA==.',['Tì']='Tìm:BAAALAADCggICAAAAA==.',Um='Um:BAAALAADCgUIBQAAAA==.',Un='Unaruid:BAAALAAECgMIBgAAAA==.',Va='Valefor:BAAALAAECgIIAwAAAA==.',Vi='Virah:BAAALAAECgMIBgAAAA==.',Vo='Voidessence:BAAALAADCgYIBgAAAA==.Voidooze:BAACLAAFFIEHAAIFAAQI7hNfAQBVAQAFAAQI7hNfAQBVAQAsAAQKgRgAAgUACAiRJAIDADwDAAUACAiRJAIDADwDAAAA.Volmi:BAAALAADCgEIAQAAAA==.Volmy:BAAALAAECgYICQAAAA==.',Wh='Whitesaman:BAAALAAECgYIBwAAAA==.Whitvoker:BAAALAADCggICAAAAA==.',Wi='Willowfaith:BAAALAADCgcIAQAAAA==.Wissan:BAAALAAECgMIBgAAAA==.',Ya='Yardie:BAAALAAECgMIBgAAAA==.Yardos:BAAALAADCggIEAAAAA==.',Ye='Yennefoor:BAAALAAECgUIAwAAAA==.',Yh='Yh:BAAALAADCggIFwAAAA==.',Yo='Yomi:BAAALAADCggIDwAAAA==.',Ys='Ysuren:BAAALAAECgYIDgAAAA==.',Yu='Yuna:BAAALAAECgIIBAAAAA==.',Za='Zabian:BAAALAAECgYIDgAAAA==.',Ze='Zelis:BAAALAADCgcIDQAAAA==.Zerrard:BAAALAADCgcIBwAAAA==.Zeylu:BAAALAAECgIIAwAAAA==.Zezth:BAAALAAECgMIBgAAAA==.',Zh='Zhuna:BAAALAAECgYIEQAAAA==.',Zi='Ziukiest:BAAALAAECgMIBgAAAA==.',Zs='Zsoka:BAAALAAECgMIBgAAAA==.',Zu='Zukie:BAAALAAECgQIBwAAAA==.Zuulabar:BAAALAADCgEIAQAAAA==.Zuzz:BAAALAADCgQIBAABLAAECgYIDgABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end