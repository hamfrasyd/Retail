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
 local lookup = {'Shaman-Elemental','Paladin-Holy','Mage-Arcane','DeathKnight-Frost','Warrior-Protection','Shaman-Restoration','DemonHunter-Havoc','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Rogue-Outlaw','DemonHunter-Vengeance','Druid-Balance','Druid-Guardian','Unknown-Unknown','Druid-Restoration','Warrior-Fury','Paladin-Retribution','Warlock-Destruction','Hunter-Survival','Paladin-Protection','DeathKnight-Blood','Warrior-Arms','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Feral','Warlock-Demonology','Priest-Shadow','Rogue-Assassination','Rogue-Subtlety','Warlock-Affliction','Monk-Brewmaster','Mage-Frost','Shaman-Enhancement','DeathKnight-Unholy','Evoker-Devastation',}; local provider = {region='EU',realm='Ysera',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aaronia:BAAALAAECgQIBAAAAA==.',Ab='Abscheu:BAABLAAECoEYAAIBAAgI9AQsegAIAQABAAgI9AQsegAIAQAAAA==.',Ad='Adrianie:BAAALAADCggICAAAAA==.',Ae='Aegís:BAAALAADCgEIAQAAAA==.Aetheris:BAAALAAECgUIBQAAAA==.',Ai='Aisfogel:BAAALAAECgYIBgAAAA==.',Aj='Ajicake:BAAALAAECgUIBQAAAA==.Ajidragon:BAAALAADCggIFwAAAA==.',Ak='Akash:BAAALAADCggIGAAAAA==.Akinomó:BAAALAADCggIHAAAAA==.Akita:BAAALAADCggIFgAAAA==.Akyra:BAAALAADCggICAAAAA==.',Al='Alatria:BAAALAADCggIFgAAAA==.Alexlouis:BAACLAAFFIEJAAICAAMIfAnRCwDWAAACAAMIfAnRCwDWAAAsAAQKgS8AAgIACAg1FxQYACMCAAIACAg1FxQYACMCAAAA.Almasor:BAAALAAECgcIDwAAAA==.Alunia:BAAALAAECgYICwAAAA==.',Am='Ambroo:BAAALAAECgMIAwAAAA==.Amnesia:BAAALAADCggIFQAAAA==.',An='Antharia:BAAALAADCgIIAgAAAA==.Anthariâ:BAAALAAECgYICAAAAA==.Antor:BAAALAAECgMIAwAAAA==.',Ar='Arcadio:BAAALAAECgUIBQAAAA==.Arcanefluff:BAAALAAECgIIBAAAAA==.Ariodana:BAAALAADCggIHwABLAAECgcIHQADAHgKAA==.Artemion:BAAALAAECgIIAgAAAA==.Arzosah:BAAALAAECgMICgAAAA==.',As='Ashantia:BAAALAAECggIAgAAAA==.',Av='Avishamtur:BAAALAADCggIGAAAAA==.',['Aé']='Aésir:BAACLAAFFIELAAIEAAMIggvTHgDOAAAEAAMIggvTHgDOAAAsAAQKgTEAAgQACAiYHW0wAIoCAAQACAiYHW0wAIoCAAAA.',Ba='Baojin:BAAALAAECgEIAgAAAA==.Bareja:BAABLAAECoEVAAIFAAgIzQlHUADwAAAFAAgIzQlHUADwAAAAAA==.Bargol:BAAALAADCgMIAwAAAA==.Barios:BAAALAADCggIDwAAAA==.Barockaa:BAAALAADCggICAAAAA==.Bastit:BAAALAADCggICAAAAA==.',Be='Belatona:BAAALAAECggICAAAAA==.Bery:BAAALAAECgUIBQAAAA==.Betheny:BAAALAAECgEIAgAAAA==.',Bi='Biegel:BAAALAAECgYICAAAAA==.Bigshortyinc:BAAALAADCgIIAgABLAAECggIFQAGADAYAA==.Bilderrahmen:BAAALAADCggIEAAAAA==.Bilu:BAAALAAECgcIDQAAAA==.Bitburger:BAABLAAECoEhAAIHAAgIQR6NKgCQAgAHAAgIQR6NKgCQAgAAAA==.',Bl='Blackdum:BAAALAAECgYIEwAAAA==.Bloodyroots:BAAALAADCggIGAAAAA==.',Bo='Boesesetwas:BAAALAADCggIDQAAAA==.Bohahaiha:BAACLAAFFIEGAAIIAAMIUxxTCwAiAQAIAAMIUxxTCwAiAQAsAAQKgW4AAggACAjCJk0AAJEDAAgACAjCJk0AAJEDAAAA.Bomb:BAAALAAECgEIAQAAAA==.',Br='Braumeìster:BAABLAAECoEeAAMJAAYI7A+oJwAxAQAJAAYI7A+oJwAxAQAKAAEItAONWwAtAAABLAAFFAQICAADAIALAA==.Broeri:BAABLAAECoEmAAIDAAcIIBaBUwDqAQADAAcIIBaBUwDqAQAAAA==.Bromhilda:BAAALAAECgMIAwAAAA==.Brooké:BAAALAADCgcIBwAAAA==.',['Bâ']='Bârejaa:BAAALAAECggIEAAAAA==.',Ca='Cailá:BAAALAADCggICAAAAA==.Calipsos:BAAALAAECgYIDQAAAA==.Calypsos:BAAALAADCgYICwAAAA==.Cat:BAAALAAECgYICwAAAA==.Catrebellin:BAAALAAECgEIAQAAAA==.',Ce='Centurío:BAAALAAECgMIAwAAAA==.',Ch='Chantal:BAAALAADCgYIAgAAAA==.Charlena:BAAALAADCgUICAAAAA==.Charmane:BAAALAADCgcIBwAAAA==.Cheyene:BAAALAADCgcIDwAAAA==.Chikage:BAAALAAECggIEgAAAA==.Chimalia:BAAALAAECgYIDwAAAA==.Chimuffin:BAAALAADCggICAABLAAECgcIIgALAFwXAA==.Chonker:BAAALAAECgQIBAAAAA==.Chrissanty:BAAALAADCgYIBgAAAA==.Christroyer:BAAALAADCgcICAAAAA==.Chérub:BAABLAAECoEUAAICAAcIzw2vMwBoAQACAAcIzw2vMwBoAQAAAA==.Chông:BAAALAAECggICAAAAA==.',Ci='Ciphedias:BAAALAAECggIAgAAAA==.Cirina:BAACLAAFFIEFAAIHAAMIiQrjRgBIAAAHAAMIiQrjRgBIAAAsAAQKgSEAAgcACAjJIHApAJUCAAcACAjJIHApAJUCAAAA.',Co='Coolsplâsh:BAAALAAECggIDQAAAA==.',Cp='Cptken:BAACLAAFFIELAAIFAAMINRTICQDRAAAFAAMINRTICQDRAAAsAAQKgTEAAgUACAi1HTwOAKkCAAUACAi1HTwOAKkCAAAA.',Cr='Crystallex:BAAALAAECgIIAgAAAA==.',Da='Daemon:BAACLAAFFIEHAAIMAAIILAlHEABdAAAMAAIILAlHEABdAAAsAAQKgRYAAgwABgglEYUpADMBAAwABgglEYUpADMBAAAA.Daeral:BAABLAAECoEXAAMNAAgIWhxzFQCTAgANAAgIWhxzFQCTAgAOAAEIqR2RKQBQAAAAAA==.Daeval:BAAALAAECggICAABLAAECggIFwANAFocAA==.Dagrow:BAAALAAECgMIAwAAAA==.Dare:BAAALAADCgIIAgAAAA==.',De='Dedmoros:BAAALAAECggIBAAAAA==.',Di='Diastate:BAAALAADCgIIAgAAAA==.Dizcopriest:BAABLAAECoEoAAIIAAgI8hB3NwDcAQAIAAgI8hB3NwDcAQAAAA==.',Do='Doreyn:BAAALAADCggICAAAAA==.Dorkuraz:BAAALAADCgMIAwAAAA==.',Dr='Draconas:BAAALAAECgYICgAAAA==.Draina:BAAALAAECgMIBgAAAA==.Druidixs:BAAALAADCgEIAQAAAA==.',Du='Duffslayer:BAABLAAECoEdAAIMAAgIFCOGBAAUAwAMAAgIFCOGBAAUAwAAAA==.Duwubai:BAABLAAECoEZAAIHAAcI7xcqUgADAgAHAAcI7xcqUgADAgAAAA==.',['Dè']='Dèény:BAAALAADCgcIBwABLAAECgMIAwAPAAAAAA==.',['Dö']='Dövelgrönn:BAAALAAECgQIBgAAAA==.',['Dø']='Døbbie:BAAALAAECgMIAwAAAA==.',['Dü']='Düsterhorn:BAAALAADCgcIBwAAAA==.',Eg='Eggbertus:BAAALAADCggICAAAAA==.',Ei='Eidena:BAABLAAECoEUAAIQAAYIdATwjQCyAAAQAAYIdATwjQCyAAAAAA==.',El='Elissa:BAAALAADCgYIDAAAAA==.Ellaria:BAAALAAECgYIBgABLAAECggIIgAIAPcLAA==.',Em='Emptyelsa:BAAALAAECgMIBgAAAA==.',En='Engul:BAAALAADCgEIAQAAAA==.',Ep='Epischscharf:BAAALAADCggICAAAAA==.',Er='Erco:BAAALAADCgYIDAAAAA==.Ercoles:BAAALAADCgcIBQAAAA==.Erito:BAAALAAECgEIAwAAAA==.Erwinovic:BAAALAAFFAIIAgABLAAFFAUIDAARAIsQAA==.',Ev='Evermore:BAAALAADCggICAAAAA==.',Ex='Excelion:BAABLAAECoEjAAMCAAcIhCJvCgCxAgACAAcIhCJvCgCxAgASAAYIhhwAAAAAAAAAAA==.',Ey='Eyedevil:BAAALAADCggIDwAAAA==.',Fa='Faylinn:BAAALAAECgYIEwAAAA==.',Fe='Feelsbad:BAAALAAECgYIDAAAAA==.Fellbürste:BAAALAADCgQIBAAAAA==.Fenr:BAAALAAFFAIIBAAAAA==.Feuerdrache:BAAALAADCgYIBgAAAA==.',Fi='Fidikus:BAAALAAECgYICAAAAA==.Firstsoulfly:BAAALAADCgYIAwAAAA==.Firtycino:BAAALAAECgYIEAAAAA==.',Fl='Flodrood:BAAALAADCgcIBwABLAAECggIFQATAHscAA==.Floof:BAAALAADCggIDgAAAA==.Floot:BAAALAADCggIEwAAAA==.Fluffzzy:BAAALAAECgQIBAABLAAECggIIQASAOERAA==.Flâminis:BAABLAAECoElAAIBAAgIdBrTHQCRAgABAAgIdBrTHQCRAgAAAA==.',Fr='Frieren:BAABLAAECoElAAIRAAgIoxnaMgA6AgARAAgIoxnaMgA6AgAAAA==.',Fu='Fulgurion:BAAALAAECgYIEAAAAA==.Fusselinho:BAAALAAECgIIAgAAAA==.',Fy='Fynnsh:BAACLAAFFIEIAAIUAAMIFxYmAQD2AAAUAAMIFxYmAQD2AAAsAAQKgS4AAhQACAhkIpwBAB0DABQACAhkIpwBAB0DAAAA.',['Fâ']='Fâbîenne:BAABLAAECoEVAAMOAAgIag1AHQDiAAAOAAYIfwhAHQDiAAAQAAgIvwLsuAA0AAAAAA==.',['Fü']='Fürstin:BAAALAAECgYICwAAAA==.',Ga='Gabbi:BAAALAAECgIIAgABLAAECgcIDQAPAAAAAA==.Ganginamonk:BAAALAAECgYICQAAAA==.Ganondorf:BAAALAAECgUIEAAAAA==.Garador:BAAALAADCggIEAABLAAECgYIFAAVAA0RAA==.Gardenia:BAAALAADCggICAABLAAECggIFQATAHscAA==.',Ge='Gedòsenin:BAAALAAECgEIAQAAAA==.Geita:BAAALAAECgEIAQABLAAFFAMICwAWAEIhAA==.Gevatertót:BAAALAAECgIIAgAAAA==.',Gh='Ghõst:BAABLAAECoEcAAIGAAYI0RDYjgAnAQAGAAYI0RDYjgAnAQAAAA==.',Gi='Gimi:BAAALAADCgUIBQAAAA==.Gimiliei:BAAALAADCgYIBgAAAA==.Ginka:BAAALAADCgcIDQAAAA==.',Gn='Gnomox:BAAALAADCgIIAgAAAA==.',Go='Gonzoo:BAAALAAECgcIDQABLAAECggICAAPAAAAAA==.Gonzoô:BAAALAAECgYICQABLAAECggICAAPAAAAAA==.',Gy='Gylford:BAABLAAECoEfAAIXAAcIpSMcBADPAgAXAAcIpSMcBADPAgAAAA==.',['Gé']='Gédosenin:BAAALAAECgEIAQAAAA==.',['Gú']='Gúldan:BAAALAADCggIDgAAAA==.',Ha='Hardaes:BAAALAAECgQIBAAAAA==.Haudraufinîx:BAAALAADCggIEAAAAA==.',He='Helal:BAAALAAECggIEgAAAA==.Hexerhelga:BAAALAAECgEIAQAAAA==.',Hi='Hillx:BAABLAAECoEcAAISAAcIqR5zOgBjAgASAAcIqR5zOgBjAgAAAA==.Himl:BAABLAAECoEUAAMYAAcIphjsZwCzAQAYAAcIphjsZwCzAQAZAAMIVwmSkwByAAAAAA==.',Ho='Hornyarms:BAAALAAECgYICQAAAA==.Hornyataro:BAABLAAECoEWAAIEAAYIghlRfADJAQAEAAYIghlRfADJAQAAAA==.Hornyhorn:BAAALAAECgYIDAAAAA==.Horster:BAABLAAECoEcAAIVAAYIlhGFMwAyAQAVAAYIlhGFMwAyAQAAAA==.Hoshikami:BAAALAAECgYIBgAAAA==.',Hu='Hunterer:BAAALAADCgUIBQAAAA==.',['Hé']='Héllbóy:BAAALAADCgYIBgAAAA==.',['Hì']='Hìmmel:BAAALAAECgUIBQAAAA==.',['Hî']='Hîmmel:BAABLAAECoEhAAIGAAcISBuHNwATAgAGAAcISBuHNwATAgAAAA==.',Id='Idin:BAAALAAECgEIAQAAAA==.',Il='Ilyks:BAAALAAECggIAQAAAA==.Ilîas:BAABLAAECoEuAAIVAAgIqSX+AQBjAwAVAAgIqSX+AQBjAwAAAA==.',In='Insanity:BAABLAAECoEmAAMQAAYIASPKHwBHAgAQAAYIASPKHwBHAgANAAYI2xCqSQBYAQAAAA==.',Ir='Irdinus:BAAALAADCggIEAAAAA==.Irene:BAAALAAECgYICAAAAA==.Ironfist:BAAALAADCgIIAgAAAA==.',Is='Isadorah:BAAALAADCgMIBQAAAA==.Isulia:BAAALAADCggICAABLAAECgYIDwAPAAAAAA==.',Iv='Ivka:BAAALAADCgYIBgAAAA==.',Ja='Jaryn:BAAALAADCgcIBwAAAA==.Jasmin:BAAALAADCggIEAAAAA==.Javyn:BAAALAAECggICQAAAA==.Jayster:BAAALAADCgcICQAAAA==.',Je='Jellybeef:BAAALAADCggIGAAAAA==.Jennaortega:BAABLAAECoEcAAIQAAcIVyDBFgCCAgAQAAcIVyDBFgCCAgAAAA==.',Jo='Jolande:BAABLAAECoEhAAIDAAcILQ24cACVAQADAAcILQ24cACVAQAAAA==.',Jp='Jp:BAAALAAECgQIBgAAAA==.',Ju='Judgelin:BAAALAAECggIEAAAAA==.Jurzul:BAAALAAECgYIEwAAAA==.',['Jø']='Jøsi:BAAALAADCggIEAAAAA==.',Ka='Kaelith:BAAALAADCgIIBAAAAA==.Kalvari:BAAALAAECgIIAgAAAA==.Kaorioda:BAAALAADCgcIDQAAAA==.Kargu:BAAALAADCgUIBQABLAADCggICAAPAAAAAA==.Katryn:BAAALAAECgYIDwAAAA==.Kaylá:BAAALAADCgYICAAAAA==.Kazejin:BAAALAAECgYIEAAAAA==.',Ke='Keevah:BAAALAADCggICAABLAAECggIDgAPAAAAAA==.Keimchen:BAABLAAFFIEGAAIQAAIIvx0FFgCpAAAQAAIIvx0FFgCpAAAAAA==.Kenshyn:BAABLAAECoEUAAITAAYIewftkwAQAQATAAYIewftkwAQAQAAAA==.',Kh='Khaleesi:BAAALAADCgcIBwABLAAECgcIDQAPAAAAAA==.Khrunshock:BAAALAAFFAIIAgAAAA==.Khyriel:BAAALAAECggIEAAAAA==.',Ki='Killdot:BAAALAAECgYIDwAAAA==.',Kn='Knallerbse:BAAALAADCggIDQAAAA==.',Ko='Kodamitsuki:BAAALAAECgYICgAAAA==.Konstantine:BAABLAAECoEgAAINAAcIqSCqGAB0AgANAAcIqSCqGAB0AgAAAA==.',Kr='Kratzbaûm:BAABLAAECoEfAAIaAAcIyh2yCwBxAgAaAAcIyh2yCwBxAgAAAA==.Krektar:BAAALAADCgYIBgAAAA==.Kresina:BAAALAAECgYIEAAAAA==.Krylock:BAAALAADCgEIAQAAAA==.Krötchen:BAABLAAECoEcAAIHAAcIHxSSZQDRAQAHAAcIHxSSZQDRAQAAAA==.',Ku='Kuhrios:BAAALAADCgcIDwAAAA==.Kumimirai:BAABLAAECoEUAAMVAAcIqQ3qLQBXAQAVAAcIqQ3qLQBXAQACAAYIhAU9SQDxAAAAAA==.Kunan:BAAALAAECgMIAwAAAA==.Kungfulo:BAAALAAECgMIAwAAAA==.Kungpaø:BAAALAAECgMIAwAAAA==.Kunsistraza:BAAALAAFFAIIAgAAAA==.',Ky='Kyrièn:BAAALAADCggICAABLAAFFAUIEgASABYeAA==.',['Ká']='Kárathas:BAABLAAECoEbAAIGAAcIpiDnHACDAgAGAAcIpiDnHACDAgAAAA==.',La='Larthor:BAAALAADCggICAABLAAECgYIDwAPAAAAAA==.Laru:BAAALAADCggIGwAAAA==.Last:BAAALAAECgEIAQAAAA==.Lavivaputa:BAAALAADCgYIBgAAAA==.',Le='Leap:BAAALAADCgYIBgABLAADCggICAAPAAAAAA==.Leelalein:BAACLAAFFIELAAITAAMIbBcxGQDyAAATAAMIbBcxGQDyAAAsAAQKgTEAAxMACAh7HPwmAIECABMACAh7HPwmAIECABsAAghTB/93AGEAAAAA.Leysun:BAAALAADCgcICgAAAA==.',Li='Lilika:BAAALAADCggICAAAAA==.Lillyann:BAAALAAFFAIICAAAAQ==.Linchén:BAAALAAECgMIAwAAAA==.Liore:BAAALAADCgYIDQAAAA==.Liq:BAAALAAECgIIAgAAAA==.Littleaji:BAABLAAECoEoAAIcAAcIeBe5MwDZAQAcAAcIeBe5MwDZAQAAAA==.Littleleny:BAAALAADCggIGQAAAA==.Livnary:BAAALAADCgMIAwAAAA==.Livory:BAAALAAECgYIDQAAAA==.',Ll='Llayne:BAAALAADCgcIBwAAAA==.',Lo='Loofio:BAAALAADCgcICQABLAADCggICAAPAAAAAA==.Loorai:BAAALAADCgYICgAAAA==.Lootmeplx:BAACLAAFFIEIAAICAAII9CLgDADJAAACAAII9CLgDADJAAAsAAQKgSAAAgIACAi2H/gIAMUCAAIACAi2H/gIAMUCAAAA.Lorida:BAAALAAECgYIEAABLAAECgYIEwAPAAAAAA==.Loveyouxo:BAAALAAECgEIAQAAAA==.',Lu='Lucîfêr:BAABLAAECoEVAAITAAgIexw4IQChAgATAAgIexw4IQChAgAAAA==.Lully:BAAALAADCggIFAAAAA==.Luthanda:BAAALAAECgYIBgAAAA==.Luvos:BAABLAAECoEfAAIVAAcINSAKDwBmAgAVAAcINSAKDwBmAgAAAA==.',Ly='Lycci:BAAALAADCgMIAwAAAA==.Lycy:BAAALAADCggIHwAAAA==.Lykarate:BAAALAADCgEIAQAAAA==.Lynes:BAAALAADCgcIBwAAAA==.',['Lô']='Lôthâr:BAAALAADCggICAAAAA==.',['Lû']='Lûana:BAAALAAECgQIBgAAAA==.',['Lü']='Lümmel:BAABLAAECoEeAAISAAYITyDBcgDUAQASAAYITyDBcgDUAQAAAA==.',Ma='Macix:BAAALAADCggICAAAAA==.Maghoros:BAAALAADCgUIBQAAAA==.Magiepower:BAAALAAECgYICQAAAA==.Magott:BAAALAADCggIIgAAAA==.Malanior:BAABLAAECoEjAAMCAAgI6BsmEABvAgACAAgI6BsmEABvAgASAAUIJRkqowB5AQAAAA==.Malrissa:BAAALAADCgcICwAAAA==.Mantarochen:BAAALAAECgMIBgAAAA==.Marabella:BAAALAAECgYIDwABLAAECgcIIQADAC0NAA==.Maxén:BAAALAADCggIEAAAAA==.Maybel:BAABLAAECoEdAAIIAAcIdRykLQANAgAIAAcIdRykLQANAgAAAA==.',Me='Megumín:BAAALAAECgMIAwAAAA==.Meisterworge:BAACLAAFFIELAAIWAAMIQiEWBQAXAQAWAAMIQiEWBQAXAQAsAAQKgTEAAhYACAhGJtcAAHoDABYACAhGJtcAAHoDAAAA.Melisan:BAAALAAECggICAAAAA==.Melíssá:BAAALAADCgcIAwAAAA==.Mettmeister:BAACLAAFFIEHAAMdAAQIZRUMCQAIAQAdAAMIZRwMCQAIAQAeAAEIYgDvGAA4AAAsAAQKgRgABB0ACAgTI/MLAMcCAB0ACAjlIvMLAMcCAB4AAQi8Hm5CADsAAAsAAQjKAswcACYAAAAA.Metusalem:BAAALAADCgcIBwABLAAECgUIEAAPAAAAAA==.',Mi='Miez:BAAALAADCggICwAAAA==.Milèycyrús:BAABLAAECoEmAAIfAAcISx0fBgBbAgAfAAcISx0fBgBbAgABLAAECgcILAABABgkAA==.Minzag:BAAALAAECgQIBQABLAAFFAMICwAWAEIhAA==.Miracelwîp:BAAALAADCgYIBgAAAA==.Mirikiel:BAAALAAECgQIBgABLAAECgcIDgAPAAAAAA==.Mirikíel:BAAALAADCgcIDQABLAAECgcIDgAPAAAAAA==.Missfeuermut:BAAALAADCggICAAAAA==.',Mo='Moniq:BAAALAADCgcIBwAAAA==.Moodey:BAAALAAECgYIBgAAAA==.Moonshine:BAAALAADCgcIDQAAAA==.',Mv='Mvshortyinc:BAAALAADCgYIBgABLAAECggIFQAGADAYAA==.',My='Myshka:BAAALAAECgEIAQABLAAECgcIIQAGAEgbAA==.Mythriel:BAAALAAECggIEAAAAA==.',['Mî']='Mîraculîx:BAAALAADCgEIAQAAAA==.',['Mò']='Mòesha:BAAALAAECgYIDQAAAA==.',Na='Nadjaná:BAAALAAECggIAgAAAA==.Nausica:BAABLAAECoEVAAIaAAYI+RFSIABmAQAaAAYI+RFSIABmAQAAAA==.Nazríal:BAAALAAECgcIBgAAAA==.',Ne='Ne:BAAALAAECgEIAQABLAAECgcIDgAPAAAAAA==.Necronossos:BAAALAADCggIDAAAAA==.Nediah:BAAALAAECgcIDQABLAAECgcIEwAPAAAAAA==.Nehara:BAAALAADCgUIAQAAAA==.Nescádiá:BAAALAAECggIBwAAAA==.',Ni='Nineinchflay:BAAALAAECgYIDAABLAAECgQIBAAPAAAAAA==.Nithuel:BAAALAAECgYIDgAAAA==.',No='Noranor:BAABLAAECoEmAAQgAAYIRQ4ALADzAAAKAAUIhw9lPQD6AAAgAAYIBgkALADzAAAJAAUIOwk/NgC+AAAAAA==.Nosfera:BAAALAAECgYIDAAAAA==.Noxx:BAAALAADCgUIBQAAAA==.',Ny='Nyaw:BAAALAADCggIDgAAAA==.Nyhm:BAAALAAECgYICQAAAA==.Nytrox:BAAALAAECgIIAgAAAA==.',['Nè']='Nè:BAAALAAECgcIDgAAAA==.',['Nê']='Nêzuko:BAAALAAECgIIAgABLAAECggIFQATAHscAA==.',['Nô']='Nôsfératu:BAAALAAECggIDgAAAA==.',Oa='Oathbound:BAAALAADCgYICgAAAA==.',Oc='Ochocinco:BAAALAADCggIBwAAAA==.',Oe='Oenomaus:BAAALAAECgIIAwAAAA==.',Oh='Ohrmuhzd:BAAALAAECgYIDAABLAAECgQIBAAPAAAAAA==.',Op='Opax:BAAALAADCgUIBQAAAA==.',Ot='Otterzunge:BAAALAAECgQIBAAAAA==.Ottfried:BAAALAAECgQIBAABLAAFFAUIDAARAIsQAA==.',Pa='Pandha:BAABLAAECoEfAAIRAAcIfB6yKQBoAgARAAcIfB6yKQBoAgAAAA==.Parryhôtter:BAAALAADCgcIBwAAAA==.Paterrod:BAAALAADCggIDAAAAA==.',Pe='Perianth:BAAALAADCgQIBAAAAA==.Perry:BAAALAAECgIIAgAAAA==.',Ph='Phury:BAABLAAECoEXAAIYAAYI1A9tmABNAQAYAAYI1A9tmABNAQAAAA==.Phîra:BAABLAAECoEdAAMRAAcIgyBzPQANAgARAAcIPiBzPQANAgAFAAMIbCIZRgAeAQAAAA==.',Pl='Plastehao:BAAALAAFFAIIAgAAAA==.Plumskörber:BAAALAADCgQIBAAAAA==.',Po='Poong:BAAALAAECggIEgAAAA==.',Pr='Premius:BAAALAAECgYIDAAAAA==.Premiûs:BAAALAAECgEIAQAAAA==.',Pu='Pukk:BAABLAAECoEaAAMQAAcIhQuGYAAzAQAQAAcIhQuGYAAzAQAOAAQIbAl2IwCVAAAAAA==.',['Pá']='Pálatedy:BAAALAADCggICAAAAA==.',['Pê']='Pêppermint:BAAALAADCggIDwAAAA==.',Qu='Quentín:BAAALAADCgMIAwAAAA==.',Ra='Radahan:BAAALAADCgMIAwABLAADCgcIEwAPAAAAAA==.Raelan:BAAALAADCggIEAABLAAECggIIwACAOgbAA==.',Re='Reisender:BAAALAAECgIIAgABLAAECgcIGAAgALYVAA==.Rellaron:BAAALAAECgEIAgAAAA==.Rewoo:BAACLAAFFIEIAAISAAMI/gobFgDIAAASAAMI/gobFgDIAAAsAAQKgSQAAhIACAhhHwooAKwCABIACAhhHwooAKwCAAAA.',Rh='Rhyza:BAAALAADCggICQAAAA==.Rhyzâ:BAAALAAECgYIDwAAAA==.',Ri='Riewmeister:BAAALAADCgEIAQAAAA==.Riihmaa:BAAALAAECgYIEQAAAA==.Rilan:BAAALAAECgEIAQABLAAECgYIDgAPAAAAAA==.',Ro='Rocklee:BAAALAAECgMIAwABLAAECgYIEgAPAAAAAA==.Rockxor:BAACLAAFFIEGAAIQAAIIbw6WIwCHAAAQAAIIbw6WIwCHAAAsAAQKgSAAAhAACAjqGcwbAF8CABAACAjqGcwbAF8CAAAA.Rohr:BAAALAAECgMIAwAAAA==.Rohrbach:BAAALAADCgcIDAAAAA==.Rohrschach:BAAALAAECgYICwAAAA==.Roxas:BAABLAAECoEmAAIKAAcIXh5ZEwBUAgAKAAcIXh5ZEwBUAgAAAA==.',Ry='Ryukotsusei:BAABLAAECoEcAAIKAAcIHhVvIgC6AQAKAAcIHhVvIgC6AQAAAA==.Ryzhy:BAAALAAECggIEgAAAA==.Ryùk:BAAALAADCggICAAAAA==.',['Râ']='Râzul:BAAALAAECgMIBAAAAA==.',Sa='Safthicc:BAAALAADCgIIAgAAAA==.Sambö:BAAALAAECgYIEgAAAA==.Samhaine:BAAALAADCgEIAQAAAA==.Samisher:BAACLAAFFIEIAAIhAAIIASODBQDMAAAhAAIIASODBQDMAAAsAAQKgR8AAiEACAgZJsYAAIkDACEACAgZJsYAAIkDAAAA.Saphrona:BAAALAAECgMIAwAAAA==.Satsujinlock:BAABLAAECoEWAAITAAgIYSIRDQAjAwATAAgIYSIRDQAjAwABLAAFFAIIAgAPAAAAAA==.Sayena:BAABLAAECoEcAAICAAYI2xs/IQDbAQACAAYI2xs/IQDbAQABLAAECggIIwACAOgbAA==.Saýnara:BAAALAAECgIIAwAAAA==.',Sc='Scarifa:BAAALAADCggIDgAAAA==.Schambulance:BAAALAAECgIIAwAAAA==.Schameline:BAAALAAECgYICwAAAA==.Schamone:BAAALAADCgcIDQAAAA==.Schnuckel:BAAALAADCggIFgAAAA==.Schurke:BAAALAAECggIDAAAAA==.Schusselinus:BAAALAAECgMIAwAAAA==.Scorpina:BAAALAADCggIDQAAAA==.',Se='Secretmuffin:BAABLAAECoEiAAMLAAcIXBfkBwD5AQALAAcIGxfkBwD5AQAeAAcIkxE0HQB+AQAAAA==.Seleen:BAAALAAECggICAAAAA==.Seraphel:BAAALAAECggICAAAAA==.Seulgi:BAABLAAECoEXAAIZAAYIsyLBIQBEAgAZAAYIsyLBIQBEAgAAAA==.',Sh='Shadygaga:BAAALAADCgYIBgABLAAECgQIBAAPAAAAAA==.Sheo:BAABLAAECoEXAAIbAAYITRvSHgDrAQAbAAYITRvSHgDrAQAAAA==.Sheuwu:BAAALAADCgUIBQAAAA==.Shiyanlin:BAAALAAECgEIAQAAAA==.Shortyinc:BAAALAADCgIIAgAAAA==.Shortyincl:BAAALAAECgEIAQABLAAECggIFQAGADAYAA==.Shortyincmv:BAAALAAECgIIAgABLAAECggIFQAGADAYAA==.Shortyincs:BAABLAAECoEVAAMGAAgIMBgzYgCUAQAGAAYI6BgzYgCUAQABAAUIYgtCiQC9AAAAAA==.Shortymonk:BAAALAADCggIEAABLAAECggIFQAGADAYAA==.Shortyxinc:BAAALAADCgcIBwABLAAECggIFQAGADAYAA==.Shrink:BAAALAADCgcICgABLAAECgEIAQAPAAAAAA==.Shuryo:BAAALAADCgMIAwAAAA==.Shárgo:BAABLAAECoEdAAIiAAcIXxndCwAOAgAiAAcIXxndCwAOAgAAAA==.Shôtgun:BAAALAAECgYIBwAAAA==.',Sk='Skydevil:BAAALAAECgYICwAAAA==.',Sl='Slatko:BAAALAAECggICAAAAA==.',Sm='Smirâ:BAABLAAECoEXAAINAAYIBRm1PACUAQANAAYIBRm1PACUAQAAAA==.',Sn='Sneakerz:BAABLAAECoEWAAMdAAgIKRvBFgBSAgAdAAgIKRvBFgBSAgAeAAIITw3bOgBwAAABLAAECggIFQATAHscAA==.Sneakyminaj:BAABLAAECoEdAAMLAAcIqxx/BQBNAgALAAcIqxx/BQBNAgAdAAEIKgpzZgAwAAABLAAECgQIBAAPAAAAAA==.',So='Sol:BAAALAAECgMIAwAAAA==.Solischia:BAABLAAECoEcAAIQAAgI2SEjBwASAwAQAAgI2SEjBwASAwAAAA==.Soníí:BAABLAAECoEWAAITAAgI3hVcSADrAQATAAgI3hVcSADrAQABLAAFFAMIDAASALwdAA==.Soréx:BAAALAADCggIFwABLAAECggIHgAHAGQXAA==.',Sq='Squidi:BAABLAAECoEmAAIFAAcIKBZALwCWAQAFAAcIKBZALwCWAQAAAA==.Squishy:BAABLAAECoEUAAIcAAYIZxrFOAC+AQAcAAYIZxrFOAC+AQABLAAFFAQICAADAIALAA==.Sqwippy:BAAALAADCgMIAwAAAA==.',St='Steelfíst:BAAALAAECggICQAAAA==.',Su='Subotai:BAAALAADCgcIEwAAAA==.Surân:BAABLAAECoEmAAMMAAgIaw/sJgBFAQAMAAgIMA/sJgBFAQAHAAgIGwOD3wDBAAAAAA==.',Sw='Sweetsnow:BAABLAAECoEkAAIQAAcIUx0jJwAdAgAQAAcIUx0jJwAdAgAAAA==.Sweetsugarly:BAAALAADCggIEAAAAA==.',['Sû']='Sûnset:BAAALAAECgUICgAAAA==.',Ta='Taiin:BAAALAADCggIBAABLAADCggICAAPAAAAAA==.Taleschra:BAAALAAECgYIEgAAAA==.Tamî:BAAALAADCggICAAAAA==.Taojin:BAAALAADCgcIBgABLAAECgEIAgAPAAAAAA==.Targazh:BAAALAADCggICAAAAA==.Tarith:BAAALAADCgcIBwABLAAECgYIDwAPAAAAAA==.Tashì:BAAALAAECgMICAAAAA==.',Te='Teerrah:BAAALAADCggICAAAAA==.Telori:BAAALAADCggIGAABLAAECgcIJgADACAWAA==.Tengen:BAAALAADCgcIBwAAAA==.',Th='Thanarion:BAAALAADCgYIBgAAAA==.Thanariøn:BAAALAAECgYIDgAAAA==.Tharea:BAACLAAFFIEIAAMXAAIIUCF6AgCrAAARAAIIUCETFQDIAAAXAAIIERx6AgCrAAAsAAQKgSUAAxcACAicIikDAPUCABEACAhIIpINACIDABcACAiLICkDAPUCAAAA.Thesaa:BAAALAAECggIDgAAAA==.Thunderblud:BAAALAADCggIHgAAAA==.Thymara:BAAALAAECgYIDgAAAA==.',Ti='Timbolan:BAAALAAECgYIEgAAAA==.Tipsiz:BAABLAAECoEWAAIjAAYIahA2JACBAQAjAAYIahA2JACBAQAAAA==.Tirla:BAACLAAFFIEIAAIQAAIIrwsdKQB+AAAQAAIIrwsdKQB+AAAsAAQKgR8AAhAACAiQFQAsAAUCABAACAiQFQAsAAUCAAAA.',Tl='Tlaluc:BAAALAADCgcIBwABLAAECggIIwACAOgbAA==.',To='Toastydh:BAAALAAFFAIIAgABLAAFFAQIBwAdAGUVAA==.Tobel:BAAALAADCgcIBwAAAA==.Tourok:BAAALAADCggICAAAAA==.',Tr='Trepolon:BAAALAADCgYIBwAAAA==.Trien:BAACLAAFFIEIAAIFAAIIgxfXEQCNAAAFAAIIgxfXEQCNAAAsAAQKgSAAAgUACAgWHQwSAHwCAAUACAgWHQwSAHwCAAAA.Trêkk:BAACLAAFFIEGAAIgAAII+QxhEAB3AAAgAAII+QxhEAB3AAAsAAQKgR8AAiAACAiPG5cLAHkCACAACAiPG5cLAHkCAAAA.',Ty='Tyrasis:BAAALAAECgMIBAABLAAECgcIGwAWAAkRAA==.',['Tö']='Törtchen:BAAALAADCgUIBQAAAA==.',Un='Ungêsund:BAAALAADCggIBwAAAA==.',Va='Val:BAABLAAECoEbAAIcAAgI4xelJQAsAgAcAAgI4xelJQAsAgAAAA==.Valkiere:BAAALAAECgEIAQAAAA==.Valnar:BAAALAADCggIFQAAAA==.Vappaner:BAAALAADCgQIBAAAAA==.',Ve='Veela:BAAALAAECgYIBgABLAAECgcIDQAPAAAAAA==.Veldryn:BAACLAAFFIELAAIdAAMIqSEGBwAhAQAdAAMIqSEGBwAhAQAsAAQKgTEAAh0ACAi/IUgHAAMDAB0ACAi/IUgHAAMDAAAA.',Vo='Vooura:BAAALAAECgYICQAAAA==.Vortun:BAAALAADCggICgAAAA==.',Vu='Vulkhan:BAABLAAECoEdAAISAAcIBRmzVgASAgASAAcIBRmzVgASAgAAAA==.',['Vé']='Véxx:BAAALAAECgYIBgABLAAECgcIHQAiAF8ZAA==.',Wa='Walhalla:BAAALAADCgUIBQAAAA==.Warlatm:BAAALAAECggIBQAAAA==.',Wi='Wittmann:BAAALAAECgMIAwAAAA==.Wivela:BAAALAAECgMIAwAAAA==.',Wl='Wlatron:BAAALAAECgMIAwAAAA==.',Wo='Wohtan:BAABLAAECoEdAAISAAcI+xaeiQCoAQASAAcI+xaeiQCoAQAAAA==.',Wu='Wuludia:BAAALAAECgQIBAAAAA==.Wusano:BAAALAADCggIFAAAAA==.',Xa='Xalon:BAAALAAECgQIBAABLAAECggICAAPAAAAAA==.Xantoria:BAAALAADCgUICAAAAA==.Xarandria:BAAALAADCggIEgAAAA==.Xaviâ:BAAALAADCgcIBwAAAA==.',Xe='Xedille:BAACLAAFFIEIAAISAAIIQiW5EwDVAAASAAIIQiW5EwDVAAAsAAQKgSgAAhIACAgWJVUHAF0DABIACAgWJVUHAF0DAAAA.Xels:BAAALAAECgcIEwAAAA==.Xenthul:BAAALAADCgUIBQABLAAECgQIBAAPAAAAAA==.',Xh='Xhanto:BAAALAADCgUICAAAAA==.',Xo='Xotika:BAAALAAECgMIAwABLAAECgQIBAAPAAAAAA==.',Xs='Xshortyinc:BAAALAAECgYIEgAAAA==.Xsnow:BAAALAAECgYIDwAAAA==.',Ya='Yasi:BAAALAAECgEIAQAAAA==.Yasindera:BAAALAADCgIIAgAAAA==.',Yi='Yidhra:BAAALAADCggICAABLAAECggIHQALAOwZAA==.',Ys='Ysann:BAABLAAECoEmAAIYAAcIMiHALABpAgAYAAcIMiHALABpAgAAAA==.',Yu='Yunafly:BAAALAADCgEIAQAAAA==.Yunasky:BAAALAAECgIIAwAAAA==.',Yv='Yvriel:BAAALAAECggICAAAAA==.',Za='Zagreus:BAABLAAECoEfAAIkAAcIlBuBHAAfAgAkAAcIlBuBHAAfAgAAAA==.Zandos:BAAALAAECgYIBgAAAA==.Zanesama:BAAALAAECggIDwAAAA==.Zaphyria:BAAALAADCgMIAwAAAA==.Zastermann:BAAALAADCgcIBwAAAA==.Zavicefta:BAAALAADCgYIBgAAAA==.',Zc='Zcht:BAACLAAFFIEIAAMjAAIIrgU1EQCLAAAjAAIIrgU1EQCLAAAEAAII5gIbYAB1AAAsAAQKgSUAAyMACAiZFU8UAA8CACMACAgiFE8UAA8CAAQACAjFD3ptAOYBAAAA.',Ze='Zeatt:BAACLAAFFIEKAAIIAAMI8x4KDQAHAQAIAAMI8x4KDQAHAQAsAAQKgTEAAwgACAgXIsIMAO8CAAgACAgXIsIMAO8CABwACAg6GhYhAE0CAAAA.Zetheon:BAAALAAECgMIAwABLAAECgcIHwAkAJQbAA==.Zewii:BAACLAAFFIEMAAISAAMIvB0zDQAKAQASAAMIvB0zDQAKAQAsAAQKgSIAAhIACAjmJBYNADgDABIACAjmJBYNADgDAAAA.',Zu='Zucker:BAAALAAECgUIBgAAAA==.Zurie:BAAALAAECgUIBQABLAAFFAIICAAXAFAhAA==.Zuwild:BAAALAAECgYIBgAAAA==.',['Ár']='Áragorn:BAAALAADCggICAAAAA==.',['Âm']='Âmý:BAAALAAECgEIAgAAAA==.',['Âs']='Âszari:BAABLAAECoEeAAIHAAgIZBfGQAA3AgAHAAgIZBfGQAA3AgAAAA==.',['Æk']='Æktøpriest:BAAALAADCgYICQAAAA==.',['Ér']='Érnesto:BAAALAADCgcIBwAAAA==.',['Ðy']='Ðyzy:BAAALAADCggICAAAAA==.',['Ök']='Ökonome:BAABLAAECoEVAAITAAgIUgdRfgBLAQATAAgIUgdRfgBLAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end