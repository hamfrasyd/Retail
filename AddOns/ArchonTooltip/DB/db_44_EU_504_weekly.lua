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
 local lookup = {'DemonHunter-Vengeance','DemonHunter-Havoc','Warlock-Demonology','Unknown-Unknown','Rogue-Assassination','DeathKnight-Frost','Mage-Arcane','DeathKnight-Unholy','Hunter-BeastMastery','Druid-Balance','Warrior-Fury','Warlock-Destruction','Mage-Frost','Warlock-Affliction','Druid-Restoration','Priest-Holy','Paladin-Protection','Paladin-Retribution','Hunter-Marksmanship','Shaman-Restoration','Shaman-Elemental','Priest-Discipline','Paladin-Holy','DeathKnight-Blood','Priest-Shadow','Hunter-Survival','Rogue-Subtlety',}; local provider = {region='EU',realm='ColinasPardas',name='EU',type='weekly',zone=44,date='2025-09-25',data={Ac='Acratim:BAACLAAFFIEFAAIBAAIImiNZBADOAAABAAIImiNZBADOAAAsAAQKgSkAAwEACAgjJkQBAGsDAAEACAgjJkQBAGsDAAIAAQgSElUSAUMAAAAA.',Ad='Adrenalína:BAAALAADCgQIBAAAAA==.',Ak='Akaranos:BAAALAADCgcIBwAAAA==.Akima:BAAALAADCggIHwAAAA==.Akumáa:BAAALAAECgYIEwAAAA==.',Al='Alahoguera:BAABLAAECoEZAAIDAAcI4x/MDACIAgADAAcI4x/MDACIAgAAAA==.Albera:BAAALAAECgYICgAAAA==.Aldienar:BAAALAADCgcIDAAAAA==.Alexandra:BAAALAAECgYIBgAAAA==.Alexes:BAAALAAECgMIBgAAAA==.Alexut:BAAALAADCgcIBwAAAA==.Almina:BAAALAADCgYIBgAAAA==.Alykr:BAAALAADCgcICwAAAA==.Alyxd:BAAALAADCggICAABLAAECgYIDwAEAAAAAA==.',Am='Amara:BAAALAADCgcIBwAAAA==.Amatoma:BAAALAAECgYICwAAAA==.Amenathiel:BAAALAAECgYIBgABLAAECggIGwAFAGsZAA==.',An='Ananiëlle:BAAALAADCgIIAgAAAA==.Angrod:BAAALAADCgUIBAABLAAECgYIDAAEAAAAAA==.Aniqilador:BAAALAAECgQIBQAAAA==.Annàbelle:BAABLAAECoEcAAIGAAgItx3LKQClAgAGAAgItx3LKQClAgAAAA==.',Ar='Arcal:BAAALAAECgYIBgAAAA==.Arceox:BAAALAAECgYIBgAAAA==.Ardcross:BAAALAADCggIDwAAAA==.Ariadna:BAAALAADCgcICgAAAA==.Arienai:BAAALAAECgMIAwAAAA==.Armorblood:BAAALAADCggIDwAAAA==.Arrgus:BAAALAAECggIEAAAAA==.',As='Ase:BAAALAADCgcICwAAAA==.Asmodeo:BAABLAAECoEaAAIHAAcIwguYdQCHAQAHAAcIwguYdQCHAQAAAA==.',At='Ataräh:BAAALAAECgIIAwAAAA==.Athemens:BAABLAAECoEbAAIFAAgIaxnFFwBIAgAFAAgIaxnFFwBIAgAAAA==.Athenas:BAAALAAECgIIAwAAAA==.',Au='Aurembiaix:BAAALAADCgUIBQAAAA==.',Ax='Axelrod:BAAALAADCggIFQAAAA==.',Az='Azalea:BAAALAADCgcIBwAAAA==.Azräel:BAABLAAECoEZAAIIAAYIPQlrKwBKAQAIAAYIPQlrKwBKAQAAAA==.',Ba='Bacchus:BAAALAADCgMIBAAAAA==.Bagdemagus:BAAALAAECgcIEQAAAA==.',Be='Beastserk:BAABLAAECoERAAIGAAgI5glNsABuAQAGAAgI5glNsABuAQAAAA==.Beca:BAABLAAECoEZAAIJAAcIahA5hAB1AQAJAAcIahA5hAB1AQAAAA==.Belcebúh:BAAALAAECgMIBAAAAA==.',Bl='Blackamy:BAAALAAECggIIQAAAQ==.Bleedslolz:BAABLAAECoEUAAIKAAgIBBybFgCHAgAKAAgIBBybFgCHAgAAAA==.Bloodj:BAAALAAECgIIAgAAAA==.',Bn='Bnty:BAAALAADCgMIAwAAAA==.',Br='Brits:BAAALAADCgQIBAAAAA==.Brolur:BAAALAADCgMIAwAAAA==.Brunore:BAAALAADCgcIFQAAAA==.',Bu='Buclker:BAAALAADCgUIBQAAAA==.',Bw='Bwomsundy:BAAALAADCgcIDwAAAA==.',['Bö']='Böss:BAAALAAECgIIAgAAAA==.',Ca='Camuflaged:BAAALAADCgcIDAAAAA==.Cannaliator:BAAALAAECgYICgAAAA==.Capadorr:BAAALAAECgEIAQAAAA==.Cartafilo:BAAALAAECgYIDgABLAAECggIIQACACoZAA==.Cazdemkiller:BAAALAAECgUICAAAAA==.Cazynne:BAAALAADCgYIBgABLAAECgYIEQAEAAAAAA==.',Ch='Chamakö:BAAALAAECgMIBQAAAA==.Chamiblu:BAAALAADCggICQAAAA==.Chispadevida:BAAALAADCgYIBgAAAA==.',Ci='Cidzelgadis:BAABLAAECoEoAAILAAgIvhYuPgAKAgALAAgIvhYuPgAKAgAAAA==.',Cl='Cleomile:BAAALAAECgMIBQAAAA==.',Co='Coronavitus:BAAALAADCgMIBAAAAA==.Corpetit:BAAALAAECgIIAgAAAA==.Corvinus:BAAALAADCgcICAAAAA==.',Cr='Cranne:BAAALAAECgYIEAAAAA==.Croquetón:BAAALAADCgQIBwAAAA==.',Da='Dainø:BAAALAADCgcIBwAAAA==.Dalinnar:BAAALAAECgYIDAAAAA==.Danawe:BAAALAADCggICAAAAA==.Dantaliôn:BAAALAAECgEIAQAAAA==.Dardu:BAAALAADCgcIEgAAAA==.Darkium:BAAALAAECgEIAQAAAA==.Daynø:BAABLAAECoEdAAIHAAgI3x7sIAC3AgAHAAgI3x7sIAC3AgAAAA==.Daÿno:BAAALAAECgQIBQAAAA==.',De='Deaddragon:BAAALAADCggICAAAAA==.Debbie:BAAALAADCggIEAAAAA==.Demonlucy:BAABLAAECoEhAAICAAgIKhnTQAA3AgACAAgIKhnTQAA3AgAAAA==.Demontrunyk:BAAALAADCggIEAAAAA==.',Do='Dohna:BAAALAAECgYICwAAAA==.Dosiq:BAAALAAECgYIEwABLAAECgcIFgAMAI4eAA==.',Dr='Drackprox:BAAALAAECgIIAgAAAA==.Drakinio:BAAALAAECgcIEwAAAA==.Drakten:BAAALAAECgMIAwAAAA==.Draugth:BAAALAAECgEIAQAAAA==.Drenna:BAAALAAECgIIAwAAAA==.Druidakiller:BAAALAADCgQIBAAAAA==.Druidando:BAAALAAECgIIAgAAAA==.Dryadark:BAAALAAECgYIEgAAAA==.',Dt='Dtamo:BAAALAADCggICAAAAA==.',Du='Dudiras:BAAALAADCgUIBQABLAADCggICAAEAAAAAA==.Duentay:BAAALAAECgEIAQAAAA==.',['Dö']='Dönald:BAABLAAECoEiAAMNAAcIfxdWMACUAQANAAcIfxdWMACUAQAHAAYIaQNauQCtAAAAAA==.',El='Elconfinao:BAABLAAECoEWAAQMAAcIjh4YUgDIAQAMAAYI3BkYUgDIAQADAAUIYRiPNwBuAQAOAAII0SBXJACoAAAAAA==.Eleera:BAAALAADCggIDwAAAA==.Elmastarugo:BAAALAAECgUIBQAAAA==.Elmata:BAAALAAECggICAAAAA==.Elmega:BAAALAAECgUICwAAAA==.Elyscee:BAAALAAECgYIBgAAAA==.',En='Enfermiza:BAAALAAECgUIBAAAAA==.Engel:BAAALAAECgUICAAAAA==.',Es='Eslak:BAAALAADCgcICwAAAA==.',Fa='Falin:BAAALAAECgQIBAAAAA==.',Fe='Ferlfo:BAAALAADCgQIBAAAAA==.',Fi='Fievito:BAAALAADCgQIBAAAAA==.Fievo:BAAALAADCgIIAgAAAA==.Filoxx:BAAALAAECgQIBgAAAA==.',Fl='Flakii:BAAALAADCgUIBwAAAA==.Flickzy:BAAALAADCgUIAgAAAA==.Flï:BAAALAADCgMIAwAAAA==.',Fo='Foresta:BAABLAAECoEcAAIPAAcIzBvCJgAfAgAPAAcIzBvCJgAfAgAAAA==.',Fr='Frangar:BAAALAAECgYICgAAAA==.',Fu='Furrymuffin:BAAALAADCgQIBAAAAA==.',Fy='Fylox:BAAALAADCggICAAAAA==.',Ga='Gaticos:BAAALAAECggICAAAAA==.',Ge='Gelato:BAABLAAECoEZAAIHAAcIrQ9xZwCuAQAHAAcIrQ9xZwCuAQAAAA==.',Gl='Glurin:BAAALAADCggIAQAAAA==.',Gn='Gnl:BAAALAAECgIIAgAAAA==.',Go='Goliath:BAAALAADCgcIBwAAAA==.Gollumm:BAAALAADCgEIAQAAAA==.Gorul:BAAALAAECgMIBQAAAA==.',Gr='Grimana:BAAALAAECgMIBwAAAA==.Gromash:BAAALAAECgMIAwAAAA==.',Gs='Gsus:BAAALAADCgUIBgAAAA==.',Gu='Gunforce:BAAALAADCggICAABLAAECggICAAEAAAAAA==.',Ha='Hazarku:BAAALAAECgYIDwAAAA==.Hazzrazah:BAAALAADCgYIBgAAAA==.',He='Hekoaqe:BAAALAAECgIIAgAAAA==.',Hi='Hicarilla:BAAALAAECgIIAgABLAAECgYIEAAEAAAAAA==.',Ho='Horcrux:BAAALAAECgYICQAAAA==.Horrorvacui:BAABLAAECoEfAAIQAAgILBKfNADpAQAQAAgILBKfNADpAQAAAA==.Howkeye:BAAALAADCgcIGAAAAA==.',Hu='Humankiller:BAAALAADCggICAAAAA==.Hunterwarr:BAAALAAECgUICgAAAA==.',Hy='Hydrax:BAAALAADCgcIBwAAAA==.',Id='Idone:BAAALAAECgYIEAAAAA==.',Il='Ilidani:BAABLAAECoEUAAICAAcIKwq8lgBrAQACAAcIKwq8lgBrAQAAAA==.',Ip='Ipin:BAAALAADCgEIAQAAAA==.',Is='Isíldur:BAAALAAECgQIBgAAAA==.',Ja='Javiventas:BAAALAAECgYIDQAAAA==.Javlen:BAABLAAECoEVAAINAAYIDRaONAB+AQANAAYIDRaONAB+AQAAAA==.',Jo='Johanwar:BAABLAAECoEjAAMRAAcIaxY8JQCWAQARAAcIvhM8JQCWAQASAAYIMxX/vABLAQAAAA==.Joseagui:BAAALAADCgcIDQAAAA==.',Ju='Juanmator:BAAALAADCgYIBAAAAA==.Juhancar:BAAALAAECgIIAgAAAA==.',Ka='Kamisamma:BAAALAADCgcICAAAAA==.Karman:BAAALAAECgEIAQAAAA==.',Ke='Kefren:BAABLAAECoEYAAMSAAcIpBEepQB2AQASAAcIpBEepQB2AQARAAQI7AQaTgCGAAAAAA==.Kelsan:BAAALAADCgUIBwAAAA==.Ketemeto:BAAALAAECgQIBAAAAA==.',Kh='Khalios:BAAALAADCgQIBAAAAA==.',Ki='Kirades:BAAALAAECgYIDQAAAA==.Kiryn:BAAALAADCggIDQAAAA==.',Km='Kmilian:BAABLAAECoEUAAIPAAYIFh0rNQDYAQAPAAYIFh0rNQDYAQAAAA==.',Ko='Kokil:BAAALAAECgIIAgABLAAFFAIIBQABAJojAA==.Kowek:BAAALAADCgcIBwAAAA==.',Kr='Kraid:BAAALAAECgQIDAAAAA==.',Ky='Kyda:BAAALAADCgYIBgAAAA==.Kynne:BAAALAAECgYIEQAAAA==.Kyrays:BAAALAAECgMIAwAAAA==.',['Kä']='Kärmä:BAAALAAECgYICQAAAA==.',La='Laghertha:BAAALAAECgYIDwAAAA==.Lambohuracán:BAAALAADCgMIAwAAAA==.',Le='Legola:BAAALAADCggIFgAAAA==.Leviosa:BAAALAADCgIIAgAAAA==.',Li='Licán:BAAALAADCgQIBAAAAA==.Lincelot:BAAALAAECgIIAwAAAA==.',Lo='Lorzitas:BAAALAADCgYIBgAAAA==.',Lu='Luciaann:BAAALAADCggICAAAAA==.Lucinat:BAAALAADCggICAAAAA==.Lunastra:BAAALAAECgYIBgAAAA==.Lupopala:BAAALAAECgUIBgAAAA==.',Ly='Lyrïana:BAAALAADCgMIAwAAAA==.',['Lì']='Lìllìth:BAAALAADCggIDwAAAA==.',['Lï']='Lïrath:BAAALAADCgUIBgAAAA==.',Ma='Madelyn:BAAALAADCggIDwAAAA==.Malaki:BAABLAAECoEeAAITAAgIrROaLQD6AQATAAgIrROaLQD6AQAAAA==.Maldar:BAAALAAECgUIBwAAAA==.Malosobueno:BAAALAADCgUIBQAAAA==.Mangetsu:BAAALAAFFAEIAQAAAA==.Marselus:BAAALAAECgEIAQAAAA==.Matatorerös:BAAALAAECgMIBgAAAA==.Maylee:BAAALAAECggICAAAAA==.Maïris:BAAALAADCgQIBAAAAA==.',Me='Medioamedias:BAAALAADCgUIBgAAAA==.Meliades:BAAALAAECgIIAgAAAA==.Meñiquexd:BAABLAAECoEcAAMUAAgIsxrCVAC3AQAUAAgIsxrCVAC3AQAVAAgIVQtYSwCtAQAAAA==.Meñiqüe:BAABLAAECoEaAAMQAAgILxJLNQDmAQAQAAgILxJLNQDmAQAWAAEIrg+VMwAvAAAAAA==.',Mi='Midantorque:BAAALAADCgUIBQAAAA==.Miiau:BAAALAADCgMIAwAAAA==.Mikewazowski:BAAALAAECgMIBQAAAA==.Minxi:BAABLAAECoEWAAMSAAgIKxtAMwB+AgASAAgIKxtAMwB+AgAXAAIIvAs+XwBdAAAAAA==.',Mo='Mortheo:BAAALAADCgIIAgAAAA==.',Mu='Muerodeamor:BAAALAADCgcIBwAAAA==.',['Mâ']='Mândaloriana:BAAALAAECgYIDwAAAA==.',['Mä']='Mädara:BAAALAAECgIIAgAAAA==.',['Mï']='Mïlka:BAAALAADCggIDgAAAA==.',Na='Naereth:BAAALAADCggIFwAAAA==.Nanis:BAAALAAECgYIEAAAAA==.Nanisdruida:BAAALAADCgMIBwAAAA==.Nanthens:BAAALAADCgUIBQABLAAECggIGwAFAGsZAA==.Natasha:BAAALAADCgMIAwAAAA==.',Ne='Necromourne:BAAALAADCgMIAwAAAA==.Neffer:BAAALAADCggIGQAAAA==.Nemorio:BAAALAADCgMIBQAAAA==.Nemësis:BAAALAADCggIHAAAAA==.Neonara:BAAALAADCgcIDQAAAA==.Neptune:BAAALAADCggIEAAAAA==.Neroi:BAAALAAECgYIDwAAAA==.Nevire:BAAALAADCgIIAgAAAA==.',Ni='Nichus:BAAALAADCgIIAgAAAA==.Nicolae:BAAALAAECgUIBQAAAA==.',No='Nomahec:BAAALAAECgUIAQAAAA==.Nopego:BAAALAAECggICAAAAA==.Novem:BAAALAAECgcIBwAAAA==.',Nu='Nuite:BAAALAAECgMIAwAAAA==.Numüs:BAAALAADCgcICAAAAA==.Nuniras:BAAALAADCggICAAAAA==.',['Né']='Négulo:BAAALAAECgcIEQAAAA==.',Ol='Olwyn:BAAALAAECgIIAgAAAA==.',On='Onixtar:BAAALAADCgYIDgAAAA==.',Or='Oroxxuss:BAACLAAFFIEFAAIUAAII2BrFIgCcAAAUAAII2BrFIgCcAAAsAAQKgSkAAhQACAh8HF8cAIYCABQACAh8HF8cAIYCAAAA.',Os='Oscensillo:BAAALAADCgcIFQAAAA==.',Pa='Paeron:BAABLAAECoEcAAMYAAcIhBc1HQBlAQAYAAcIWhA1HQBlAQAGAAQIXhxj6wAHAQAAAA==.Painfuldeath:BAAALAAECggICgAAAA==.Palnano:BAAALAADCgcIDQAAAA==.Panday:BAAALAADCgcIBwAAAA==.Paprica:BAAALAAECgEIAQAAAA==.Parcheta:BAAALAAECgEIAQAAAA==.',Pe='Perill:BAAALAAECgEIAgABLAAECgUIAQAEAAAAAA==.Persefoné:BAAALAAECgYIBgAAAA==.',Pr='Profanatak:BAAALAADCggIEwAAAA==.Prolen:BAABLAAECoERAAIOAAcIFQ7RDgCpAQAOAAcIFQ7RDgCpAQAAAA==.Proxam:BAAALAAECgYIDQAAAA==.',Ps='Psyche:BAAALAAFFAEIAQAAAA==.',Pu='Pulsor:BAAALAAECgYIBgAAAA==.',Py='Pycadillo:BAAALAAECgIIAgAAAA==.',['Pö']='Pöseidön:BAAALAADCgYIBgAAAA==.Pötter:BAAALAADCgcIBwAAAA==.',Qu='Quememuero:BAAALAADCgYIBgAAAA==.',Ra='Rabuillo:BAAALAADCgYIBgAAAA==.Racoon:BAAALAADCgEIAQAAAA==.Rafit:BAABLAAECoEdAAMXAAcIAxdsGwAHAgAXAAcIAxdsGwAHAgASAAYI9AS55QD5AAAAAA==.Ragnarökk:BAABLAAECoEVAAISAAgI6RJupwByAQASAAgI6RJupwByAQAAAA==.Rave:BAAALAADCggICAAAAA==.Raynesia:BAAALAAECgMIBgAAAA==.Raysa:BAAALAAECgUIBAAAAA==.',Re='Reshad:BAAALAADCgMIAwAAAA==.',Rh='Rhinolophus:BAAALAAECgIIAgAAAA==.',Ro='Robín:BAAALAAECgMIBgAAAA==.Ronniie:BAABLAAECoEYAAIPAAgIWBu9NQDWAQAPAAgIWBu9NQDWAQAAAA==.Rothgar:BAAALAADCgIIAgAAAA==.',Ru='Rusly:BAAALAAECgYIBgABLAAECggIFAAKAAQcAA==.Rustrail:BAAALAADCgcICQAAAA==.',Ry='Ryohei:BAAALAADCgcICwAAAA==.Ryuseiken:BAAALAADCggIBwABLAAECggIEAAEAAAAAA==.',['Rè']='Rèvenant:BAAALAAECgIIAwAAAA==.',Sa='Sagah:BAAALAADCggICQAAAA==.Sanamaxx:BAAALAAECgcIDgAAAA==.Sansuna:BAAALAAECgYICQAAAA==.Sardon:BAAALAAECgUIBQAAAA==.Satrik:BAACLAAFFIEFAAIHAAIImx8TJgCxAAAHAAIImx8TJgCxAAAsAAQKgSwAAgcACAg0JUoGAFQDAAcACAg0JUoGAFQDAAEsAAUUAggFAAEAmiMA.Satrïk:BAAALAAECgYIDAABLAAFFAIIBQABAJojAA==.',Sc='Scruffy:BAAALAADCgYIBgAAAA==.',Se='Seero:BAAALAAECgUIBgAAAA==.Seiko:BAAALAADCgQIBAAAAA==.Selosarigsol:BAAALAAECgMIBgAAAA==.Senju:BAAALAAECggIEAABLAAFFAIIBQABAJojAA==.Serag:BAACLAAFFIEFAAIJAAIIThYcJgCXAAAJAAIIThYcJgCXAAAsAAQKgSgAAgkACAiFJLgSAPUCAAkACAiFJLgSAPUCAAAA.Setheria:BAAALAADCggIDgAAAA==.',Sh='Shadöw:BAAALAADCgUIBQAAAA==.Shallteàr:BAAALAAECgcIDQAAAA==.Shebelia:BAAALAADCgEIAQAAAA==.Sheryl:BAAALAAECgUIAQAAAA==.Sherä:BAABLAAECoEoAAIUAAgIAxC/ZwCFAQAUAAgIAxC/ZwCFAQAAAA==.Shirime:BAACLAAFFIEFAAIYAAIIFBCJCwCEAAAYAAIIFBCJCwCEAAAsAAQKgTIAAxgACAiNH0sJAKACABgACAgBH0sJAKACAAYABgh6GXyeAIsBAAAA.',Si='Sidhhi:BAAALAAECgYIBgAAAA==.Sifh:BAAALAADCgYICwABLAADCgcIGAAEAAAAAA==.Sigmund:BAAALAADCgYIDgAAAA==.Siniestro:BAABLAAECoEbAAQOAAYImRKLGAAjAQAMAAUIdhAChQA6AQADAAUIvA3uSAAnAQAOAAUIjAyLGAAjAQAAAA==.Sióhn:BAAALAAECgMIBQAAAA==.',Sk='Skolld:BAABLAAECoEXAAIGAAYITCJAQABWAgAGAAYITCJAQABWAgAAAA==.Skulblaka:BAAALAAECgYIBgABLAAECggIGwAFAGsZAA==.',Sn='Snachy:BAAALAADCggICAAAAA==.Snevill:BAABLAAECoEgAAIGAAgIhhiHRwBBAgAGAAgIhhiHRwBBAgAAAA==.',So='Solasta:BAAALAAECgQIBwABLAAECggIEAAEAAAAAA==.Solitariô:BAAALAAECgIIAgAAAA==.Sorfilax:BAAALAAECgIIBAAAAA==.',St='Steelblood:BAAALAAECgIIAwAAAA==.Stenger:BAAALAADCgcIBwAAAA==.',Su='Suiyan:BAAALAAECgUIBwAAAA==.Susantidad:BAAALAAECgMIAwAAAA==.Suyami:BAAALAADCggIDwAAAA==.',Ta='Tanketona:BAAALAAECgYIEgAAAA==.Tarquinius:BAAALAAECgIIAgAAAA==.Tarú:BAAALAAECggIEAAAAA==.',Te='Tenwa:BAAALAADCggIDgAAAA==.Teostra:BAAALAADCggICQABLAAECgYIDAAEAAAAAA==.Teresa:BAABLAAECoEVAAIXAAcIthm6GgANAgAXAAcIthm6GgANAgAAAA==.Termmomix:BAAALAADCgQIBAAAAA==.',Th='Tharko:BAAALAADCggICwAAAA==.Thechaos:BAABLAAECoEmAAILAAgIPSKQDwAUAwALAAgIPSKQDwAUAwAAAA==.Theforsaken:BAAALAAECgIIAwAAAA==.Thordral:BAAALAADCgcIFQAAAA==.Thormac:BAAALAADCgcIBwAAAA==.Thornei:BAABLAAECoEoAAQWAAgIfyCtAQD7AgAWAAgIfyCtAQD7AgAZAAcIERAFPQCpAQAQAAIIvhAAAAAAAAAAAA==.Thraellysa:BAAALAADCgcICQAAAA==.Thráiin:BAAALAAECgUIBQAAAA==.',To='Torian:BAAALAAECgIIAgAAAA==.Touryan:BAACLAAFFIEHAAISAAIIFCMNFQDNAAASAAIIFCMNFQDNAAAsAAQKgTIAAhIACAgyJVkHAFwDABIACAgyJVkHAFwDAAAA.',Tr='Treviento:BAAALAADCgQIBAABLAAECgMIBgAEAAAAAA==.Tripa:BAAALAADCgUIBQAAAA==.Triply:BAAALAAECgYICwAAAA==.Trolee:BAAALAAECggIDwAAAA==.Trollin:BAABLAAECoEUAAIaAAcINxIyCgDiAQAaAAcINxIyCgDiAQAAAA==.',Ts='Tsubhaki:BAAALAADCgcICgAAAA==.',Tu='Tumbuska:BAAALAAECgUICwAAAA==.Turke:BAAALAADCggIGwAAAA==.Turuman:BAAALAADCggIFgAAAA==.',Tx='Txu:BAAALAADCgUIBwAAAA==.',Uf='Ufita:BAABLAAECoEXAAIMAAcIbgyvZwCGAQAMAAcIbgyvZwCGAQAAAA==.',Ul='Ulthér:BAAALAAECgIIBAAAAA==.',Un='Unkas:BAAALAADCggICAAAAA==.',Ur='Urikrigare:BAAALAADCgMIAwAAAA==.',Va='Vacansada:BAAALAADCgQIAgABLAAECgUIBwAEAAAAAA==.Vadri:BAAALAAECgQICAAAAA==.Valents:BAAALAADCgEIAQAAAA==.',Ve='Ventini:BAAALAADCgcICgAAAA==.',Vo='Voolldaam:BAAALAAECgYIBgABLAAECgYIDAAEAAAAAA==.Vornak:BAAALAADCgMIBAAAAA==.',Vu='Vulcan:BAAALAAECgMIBAAAAA==.',Wa='Waligno:BAAALAAECggICAAAAA==.Warrblo:BAABLAAECoEWAAIbAAcIjw6ZGQCfAQAbAAcIjw6ZGQCfAQAAAA==.Warri:BAAALAADCggICAAAAA==.',We='Weonwe:BAAALAAECgcICgAAAA==.',Wh='Whatisthis:BAAALAAECggIEgABLAAFFAIIBgAMAFYgAA==.Whatson:BAAALAAECgIIAgAAAA==.Whattson:BAABLAAECoEhAAMZAAgILxf3MQDkAQAZAAcI+hb3MQDkAQAQAAgIuxu0PgC4AQAAAA==.',Wi='Wicket:BAAALAADCgcIDwAAAA==.Willär:BAAALAAECgUICwAAAA==.',Xe='Xeraaya:BAAALAAECgcICQAAAA==.',Xu='Xurxiño:BAABLAAECoEVAAIQAAYI2RgRQACyAQAQAAYI2RgRQACyAQAAAA==.',Ya='Yandrack:BAAALAADCggICAABLAAFFAIIBQABAJojAA==.Yatekuro:BAABLAAECoEYAAMZAAgIaxR9JwAgAgAZAAgIaxR9JwAgAgAQAAYIwhOkZAAoAQAAAA==.',Ye='Yeny:BAAALAADCggICgAAAA==.',Yj='Yjbv:BAAALAAECgIIAgABLAAFFAYIEwADANogAA==.',Yo='Yonatan:BAABLAAECoEeAAMSAAgI9Bw4QABQAgASAAgI9Bw4QABQAgARAAEIww9QZAAiAAAAAA==.',Yr='Yrand:BAAALAADCgcICQAAAA==.',Ys='Ysella:BAAALAAECgYIBgAAAA==.',Yu='Yusta:BAAALAADCgUIBQABLAAFFAIIBQABAJojAA==.',Za='Zagaar:BAAALAADCgcIFwAAAA==.Zakürra:BAABLAAECoEcAAIJAAcIJRGpegCJAQAJAAcIJRGpegCJAQAAAA==.',Ze='Zehro:BAAALAADCggICAAAAA==.Zendra:BAAALAADCgcIBwAAAA==.',Zu='Zukrulah:BAAALAAECgIIAgAAAA==.',['Zë']='Zëro:BAAALAADCgcICwAAAA==.',['Ât']='Âtaîså:BAAALAAECgQIBAAAAA==.',['Ät']='Ätaisæ:BAAALAAECgQIBwAAAA==.',['Ér']='Érynn:BAAALAAECgcIAwAAAA==.',['Ðe']='Ðewnz:BAAALAADCgcIBwABLAAECggIFAAKAAQcAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end