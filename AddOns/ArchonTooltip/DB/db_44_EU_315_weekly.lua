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
 local lookup = {'Druid-Feral','Druid-Restoration','Unknown-Unknown','Priest-Holy','Priest-Shadow','Priest-Discipline','Paladin-Retribution','DeathKnight-Frost','Evoker-Devastation','Evoker-Augmentation','Warlock-Destruction','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Unholy','Shaman-Elemental','Monk-Windwalker','Warrior-Fury','Mage-Arcane','Shaman-Restoration','Warrior-Protection','Monk-Brewmaster','Hunter-Marksmanship','Druid-Balance','Warlock-Demonology','Warlock-Affliction','Mage-Frost','Paladin-Protection','Paladin-Holy','Hunter-BeastMastery','Shaman-Enhancement','DemonHunter-Havoc',}; local provider = {region='EU',realm='Nagrand',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adrassal:BAAALAAECgcIDwAAAA==.Adryhlia:BAAALAAECgQIBAAAAA==.',Ag='Aguir:BAAALAAECgMIBQAAAA==.Aguiri:BAAALAAECgYIDAAAAA==.',Ai='Aisw:BAAALAAECgYIDwAAAA==.',Al='Alashar:BAABLAAECoEUAAIBAAcIfRuVCQA2AgABAAcIfRuVCQA2AgAAAA==.Alassahr:BAABLAAECoEUAAICAAgIbiDdBQDdAgACAAgIbiDdBQDdAgAAAA==.',Am='Amidamaru:BAAALAAECgMIBQAAAA==.',An='Andothar:BAAALAADCgcICwAAAA==.Angeryman:BAAALAAECgYICwAAAA==.Angrycat:BAAALAADCgYICgABLAADCgYICgADAAAAAA==.Angrymonk:BAAALAADCgYICgAAAA==.Angryxp:BAAALAADCgMIAwABLAADCgYICgADAAAAAA==.Anillusión:BAAALAAECggIEAAAAA==.Anossa:BAABLAAECoEYAAQEAAgIiR48DACtAgAEAAgIiR48DACtAgAFAAEI+BhMXgBSAAAGAAEIFxH2IAA7AAAAAA==.Antonios:BAAALAAECgcIEQAAAA==.',Ar='Ardisee:BAAALAADCggICQAAAA==.Ariely:BAAALAADCgYIBgAAAA==.Arkenstone:BAAALAADCgEIAQAAAA==.Arleigh:BAAALAADCgQIBAAAAA==.Arysa:BAAALAAECgYICQAAAA==.',As='Asnac:BAAALAADCgIIAgAAAA==.Astonz:BAAALAADCggIFQAAAA==.',At='Athoman:BAAALAAECgIIAgAAAA==.',Av='Avacado:BAAALAADCggIDgAAAA==.Avaer:BAAALAADCggIEAABLAAECggIHQAHAGElAA==.Avaleth:BAAALAADCgcIBwAAAA==.',Aw='Awsomeinc:BAAALAADCggICAAAAA==.Awsomepreist:BAAALAADCgIIAgAAAA==.',Ay='Ayari:BAAALAADCgYIBgAAAA==.',Az='Azaeyl:BAAALAAECgYIDAAAAA==.Azhagu:BAAALAADCgIIAgABLAAECgcIDwADAAAAAA==.Azlan:BAAALAADCggIFgAAAA==.Azurik:BAAALAADCgMIAwAAAA==.',Ba='Battlemaster:BAAALAAECgcICAAAAA==.Bawface:BAAALAAECgIIAgAAAA==.Bayok:BAAALAADCgYIBgAAAA==.Bazim:BAAALAAECgcICAAAAA==.Bazrabbitz:BAAALAADCgYIBgAAAA==.',Be='Bemon:BAAALAAECgcIEwAAAA==.Bemons:BAAALAADCggIDAAAAA==.Benga:BAAALAAECgUIBQAAAA==.',Bi='Bigjuicy:BAAALAADCgUIBQAAAA==.',Bl='Bloodcrazy:BAAALAAECgYIDAAAAA==.Bloodninja:BAAALAAECgUIBQAAAA==.Blurredsight:BAAALAAECgcIDAAAAA==.',Bo='Boldric:BAAALAAECgYIDwAAAA==.Borkblomst:BAAALAAECggICAAAAA==.Botini:BAAALAADCgcIAgAAAA==.',Br='Bridget:BAAALAAECggIAwAAAA==.Briggle:BAAALAADCgcIBwAAAA==.Broxic:BAAALAADCggICAAAAA==.Broxxoli:BAAALAAECgUIBQAAAA==.Brykar:BAAALAADCggIEAABLAAECggIHQAIAGEaAA==.',Bu='Buffalosadie:BAAALAAECggIDAAAAA==.Buffblzer:BAAALAADCgUIBQAAAA==.Bumblebean:BAAALAADCgQIBAAAAA==.',Ca='Cabbagegirl:BAAALAAECgYIDwAAAA==.Cabus:BAACLAAFFIEHAAMJAAMICR16BQD6AAAJAAMI1xR6BQD6AAAKAAIIDSI+AQDNAAAsAAQKgR8AAwoACAiKJEkAAFsDAAoACAi6I0kAAFsDAAkACAgDJGwDADUDAAAA.Cacophony:BAAALAADCgYICwAAAA==.Cadal:BAAALAAECgEIAQAAAA==.Caddie:BAAALAADCggICwAAAA==.Camaron:BAAALAAECgYICgAAAA==.Cashhunter:BAAALAAECgYICAAAAA==.Cassalanter:BAAALAAECgMIAwAAAA==.Castraaza:BAAALAAECgcICgAAAA==.Caulïflower:BAAALAADCggICAAAAA==.',Ce='Cerpx:BAAALAAECgIIAgAAAA==.',Ch='Chikenplain:BAAALAAECgYICAAAAA==.Chiraku:BAAALAAECgQIBgAAAA==.Chrissen:BAAALAAECggIBgAAAA==.Chubbpain:BAAALAAECgYIDAAAAA==.',Co='Contrac:BAAALAADCggICwAAAA==.Controler:BAAALAAECgQIBgAAAA==.Corvaen:BAAALAADCggIDwABLAAECggIHQAHAGElAA==.Cowdwarf:BAAALAAECgcIBwAAAA==.',Cr='Crowe:BAAALAAECgcIDwAAAA==.Crucaebena:BAAALAAECgcIEwAAAA==.Cryó:BAAALAADCggIEAAAAA==.',Da='Dalriena:BAAALAADCggICAAAAA==.Darah:BAAALAADCggIDQAAAA==.Darkoo:BAAALAAECgYICgAAAA==.Darkreggie:BAAALAAECgcICgAAAA==.Darkself:BAAALAADCgUIBQAAAA==.Darkthunders:BAAALAAECgIIAgABLAAECgUICQADAAAAAA==.Darkzör:BAACLAAFFIEFAAILAAMI9wohCgDtAAALAAMI9wohCgDtAAAsAAQKgRsAAgsACAhiIS8NANgCAAsACAhiIS8NANgCAAAA.Dash:BAABLAAECoEZAAMMAAgIZx4fEgBEAgAMAAcI8RkfEgBEAgANAAUIyRdWDwCGAQAAAA==.',De='Deadlycookie:BAABLAAECoEPAAIIAAgIfQ5CQQDSAQAIAAgIfQ5CQQDSAQAAAA==.Deathawaits:BAABLAAECoEUAAMIAAgIvxurMQAQAgAIAAcIlBurMQAQAgAOAAUIrRjjHABlAQAAAA==.Deathhere:BAAALAAECgQIBgAAAA==.Deathlysmoke:BAAALAADCgIIAgAAAA==.Deathmace:BAAALAAECggICAAAAA==.Deathrazer:BAAALAADCgYIBgAAAA==.Deathsythe:BAAALAAECgUICAAAAA==.Debs:BAAALAAECgQIBgAAAA==.Dedleg:BAABLAAECoEaAAIIAAgI1RsjHgB2AgAIAAgI1RsjHgB2AgAAAA==.Deidran:BAAALAADCgIIAgABLAAECgYIDwADAAAAAA==.Deliriarick:BAAALAAECgUIBgAAAA==.Deltroth:BAAALAAECgYIBgAAAA==.Demonbaz:BAAALAADCgcIBwAAAA==.Demonkapa:BAAALAAECgYIBgAAAA==.Demonwish:BAAALAADCgIIAgAAAA==.Desalona:BAAALAADCggICAAAAA==.Desmodus:BAAALAAECgcIDwAAAA==.Dettolwipes:BAAALAAECgIIAwAAAA==.Devoratrix:BAAALAAECgYIEwAAAA==.Dewar:BAAALAADCgIIAgAAAA==.',Di='Dingleberri:BAAALAAECgIIAgAAAA==.Dirtbocks:BAAALAADCggICAAAAA==.Distracted:BAAALAADCgQIBAABLAAECgcIFgAPAKEZAA==.Distressed:BAAALAADCggIEAABLAAECgcIFgAPAKEZAA==.Distrusted:BAABLAAECoEWAAIPAAcIoRlrHQAlAgAPAAcIoRlrHQAlAgAAAA==.',Dm='Dmn:BAAALAAECgYICgAAAA==.',Dr='Dracdeeznuts:BAAALAADCgcIBwABLAAECggIGgAIANUbAA==.Dracolock:BAAALAADCgcIEQAAAA==.Drogons:BAAALAADCgIIAgAAAA==.Drunkenfurry:BAAALAAECggICAABLAAECggIEAADAAAAAA==.',Du='Dulla:BAAALAAECgMIBAAAAA==.',['Dá']='Dánte:BAAALAADCgcIDAAAAA==.',Eb='Eben:BAAALAAECgYIEAABLAAECgcIEwADAAAAAA==.',Ek='Ekoh:BAAALAAECgIIAgAAAA==.',El='Elanio:BAAALAAECggICgAAAA==.Elema:BAAALAAECgYIDAABLAAFFAMIBQAQAAsSAA==.Elevenfour:BAAALAAECggICgAAAA==.Elive:BAAALAAECggIEAAAAA==.Ellington:BAAALAADCgcIFQAAAA==.Elsuck:BAAALAADCgUIBgAAAA==.Elyino:BAAALAAECgMIAwAAAA==.Elysara:BAAALAAECgIIAgAAAA==.',En='Enhich:BAAALAADCgEIAQAAAA==.',Es='Eske:BAAALAADCgYIBgAAAA==.',Ev='Evilpriest:BAAALAAECgQIBQABLAAECgcICgADAAAAAA==.Evokaz:BAAALAAECgYICgAAAA==.Evokyrrh:BAAALAADCggIDQAAAA==.',Ex='Exalto:BAAALAADCgcIEwAAAA==.',Fa='Fad:BAABLAAECoEXAAIRAAYIjxeKKwDJAQARAAYIjxeKKwDJAQAAAA==.Fartingonyou:BAACLAAFFIEFAAISAAIIdA4kGwCaAAASAAIIdA4kGwCaAAAsAAQKgR0AAhIACAhvIO8TAMACABIACAhvIO8TAMACAAAA.',Fe='Felonious:BAAALAADCgUIBQAAAA==.',Fi='Filty:BAABLAAECoEUAAITAAcIwxX+MAC7AQATAAcIwxX+MAC7AQAAAA==.Fimbultyr:BAAALAAECgcICwAAAA==.',Fl='Florhavelin:BAAALAAECgEIAQAAAA==.Flyingaround:BAAALAAECgYIBgAAAA==.',Fo='Foxymaz:BAAALAAECgQIBgAAAA==.',Fr='Frieren:BAAALAADCggIDgAAAA==.Frostos:BAAALAAECgUIBwAAAA==.',Fu='Furlie:BAAALAAECgIIAgAAAA==.Furryming:BAAALAADCggICAAAAA==.',['Fë']='Fëdedyr:BAAALAADCgUIBQAAAA==.',Ga='Gardyn:BAABLAAECoEaAAIFAAgI+CLeBQAkAwAFAAgI+CLeBQAkAwAAAA==.',Ge='Gethope:BAAALAAECgUICQABLAAFFAMIBQALAPcKAA==.',Gi='Giddly:BAAALAAECgQIBAAAAA==.',Gl='Glass:BAAALAADCgcIBwAAAA==.',Gn='Gnarss:BAAALAAECggIDwAAAA==.',Go='Goldenballs:BAAALAAECgQIBAAAAA==.Gorian:BAAALAAECggIDgAAAA==.Goronmalares:BAAALAAECgYIDAAAAA==.Gortan:BAAALAADCgYIBgAAAA==.Gorwen:BAAALAAECgYICAAAAA==.Gowithit:BAAALAAECgUICgAAAA==.',Gr='Gravastar:BAAALAAECgYIBwAAAA==.Greenwish:BAAALAADCgYICgAAAA==.Griglosh:BAAALAAECgYIDAAAAA==.Grimbo:BAAALAAECgQIBAAAAA==.Grimhoof:BAAALAAECgcICQAAAA==.Grimnoir:BAAALAADCgUIBgAAAA==.Grizzlyadamz:BAAALAAECgcICQAAAA==.Grysti:BAABLAAECoEaAAIUAAgIMhmxDQA4AgAUAAgIMhmxDQA4AgAAAA==.Gráhl:BAAALAADCgcIDAABLAAECgUIBwADAAAAAA==.Gráhll:BAAALAAECgUIBwAAAA==.Grísty:BAAALAAECgUIBQAAAA==.',Gu='Gulpan:BAAALAAECgYIDQAAAA==.',Gw='Gwynevere:BAAALAAECgYICgAAAA==.',Gy='Gyardos:BAABLAAECoEaAAIVAAcI+xfhDQDcAQAVAAcI+xfhDQDcAQAAAA==.',Ha='Hallowhunt:BAAALAAECgcIDQABLAAFFAIIBAADAAAAAA==.Hallów:BAAALAAFFAIIBAAAAA==.Halycon:BAAALAADCgYICAABLAAECggIGQALAMgdAA==.Hamburger:BAAALAADCggICAAAAA==.Harnessa:BAAALAADCgEIAQAAAA==.Hazian:BAABLAAECoEYAAMUAAcIdhQaGgCXAQAUAAcIdhQaGgCXAQARAAIIXg3wYQB5AAAAAA==.',He='Healyhemmo:BAAALAADCggICwAAAA==.Heldigt:BAAALAAECgMIBAAAAA==.',Hi='Hikee:BAAALAAECgEIAQABLAAECggIFQAJAOEJAA==.Hikeedevo:BAABLAAECoEVAAIJAAgI4QnAHAC3AQAJAAgI4QnAHAC3AQAAAA==.Hilly:BAAALAADCgMIAwAAAA==.',Ho='Homlessasian:BAAALAAECgYIBgABLAAECgYICAADAAAAAA==.',Hu='Huntardinho:BAAALAAECgEIAQAAAA==.Huntardx:BAABLAAECoEUAAIWAAgIPiSiAwAxAwAWAAgIPiSiAwAxAwAAAA==.Hurr:BAAALAAECgQIBgAAAA==.',Hy='Hydroxide:BAAALAADCgYIBgAAAA==.',Ib='Ibuprofen:BAAALAAECgIIAgAAAA==.',Ig='Ige:BAAALAAECgYIBgAAAA==.',Ik='Ikabod:BAAALAAECgYIDgAAAA==.',Il='Illiduh:BAAALAAECgIIBAAAAA==.Illmercius:BAAALAADCgEIAQAAAA==.',Im='Imagfu:BAAALAADCgYIBgABLAAECgcIDwADAAAAAA==.',Ir='Irina:BAAALAAECgEIAQAAAA==.',Is='Isukki:BAAALAAECggIBwAAAA==.',Ja='Jafka:BAAALAADCggICAAAAA==.Janko:BAAALAAECgMIBQAAAA==.Janra:BAAALAAECgYIDAAAAA==.Jantharas:BAAALAAECgMIAwAAAA==.Jatra:BAAALAADCgcICgAAAA==.',Je='Jejoba:BAACLAAFFIEFAAIRAAIIoxtrCQC+AAARAAIIoxtrCQC+AAAsAAQKgRgAAhEACAgFIWMJAAcDABEACAgFIWMJAAcDAAAA.Jeph:BAAALAADCggIEQAAAA==.Jexie:BAAALAADCgYIBgAAAA==.Jezzilla:BAABLAAECoEVAAIXAAcILBK5JAC0AQAXAAcILBK5JAC0AQAAAA==.',Jg='Jgglybeard:BAAALAADCgcIBwAAAA==.',Ji='Jiraip:BAAALAAECgMIAwAAAA==.Jirais:BAAALAADCgUIBgAAAA==.',Ju='Juppinn:BAAALAAECgYICAAAAA==.Justine:BAAALAADCgEIAQAAAA==.',Ka='Kaeyl:BAAALAADCgQIBgABLAAECgYIDAADAAAAAA==.Karage:BAAALAAECgMIAwAAAA==.Karlak:BAAALAAECgYIEAAAAA==.Katete:BAAALAAECgYIDAAAAA==.',Ke='Kegfist:BAAALAADCggIEAAAAQ==.Keldorai:BAAALAAECgYICAAAAA==.Kenza:BAABLAAECoEUAAMCAAcI6SMgBwDHAgACAAcI6SMgBwDHAgAXAAEI4woAAAAAAAAAAA==.Kerwin:BAAALAAECgcIEwAAAA==.',Kh='Khamsin:BAAALAAECggICAAAAA==.',Ki='Killerdwarfi:BAABLAAECoEdAAMYAAgIEiZOAACGAwAYAAgIEiZOAACGAwAZAAEInBGKLQBLAAAAAA==.Kimnadine:BAAALAADCggICAAAAA==.',Kl='Klopuu:BAAALAAECgcIEAAAAA==.',Ko='Kobaydwarf:BAAALAAECgQIBgAAAA==.Koevoet:BAAALAAECgIIAgAAAA==.Kolgan:BAAALAAECgcICwAAAA==.Koutsojohn:BAAALAAECgMIBAAAAA==.',Kr='Kronös:BAAALAAECggICAAAAA==.',Ku='Kum:BAAALAAECgQIBAAAAA==.',Ky='Kyphi:BAAALAADCgUICAAAAA==.Kyrill:BAAALAADCggICAAAAA==.',['Kí']='Kíllumínatí:BAAALAAECgIIAgAAAA==.',La='Lav:BAAALAADCgcIBwAAAA==.Layluu:BAAALAADCgYIBgAAAA==.Lazeil:BAAALAAECgIIAgAAAA==.Lazymage:BAABLAAECoEUAAMaAAgIoByvCwBmAgAaAAgIoByvCwBmAgASAAEISgPznwAeAAAAAA==.Lazywar:BAAALAAECgUIBgABLAAECggIFAAaAKAcAA==.',Ld='Lddr:BAACLAAFFIEGAAIHAAMI6iQfAgBKAQAHAAMI6iQfAgBKAQAsAAQKgR8AAgcACAiHJVwCAHIDAAcACAiHJVwCAHIDAAAA.',Le='Ledia:BAAALAAECgMIAwAAAA==.Legitqp:BAABLAAECoEYAAISAAgIOBUwKQAtAgASAAgIOBUwKQAtAgAAAA==.Leluelf:BAAALAAECgQIBgAAAA==.Leluhunter:BAAALAADCgYIBgAAAA==.',Li='Lickmycrít:BAAALAAECgYICAAAAA==.Lightbane:BAAALAADCgcIBwAAAA==.Lightdarkie:BAAALAAECgUICQAAAA==.Lightningsky:BAAALAAECgMIBgAAAA==.Linnae:BAABLAAECoEXAAMFAAgILhkqJgDFAQAFAAcIsRcqJgDFAQAEAAgIjAyLLQCoAQAAAA==.',Lo='Lockley:BAAALAADCgcIBwAAAA==.Lokaron:BAAALAADCggICAAAAA==.Lopac:BAAALAAECgcIEAAAAA==.Lorewalkerpø:BAAALAAECgEIAQAAAA==.Lorhas:BAAALAAECgcIEwAAAA==.Lorna:BAAALAADCgYICQAAAA==.Lozknight:BAAALAAECgYIDwAAAA==.',Lu='Lucyfer:BAAALAADCgYIDAAAAA==.',Ly='Lysandria:BAAALAADCgYIDAAAAA==.Lysteriax:BAAALAADCgEIAQAAAA==.Lyza:BAAALAAECgYIEAAAAA==.',['Là']='Làvelý:BAAALAAECgIIAgAAAA==.',Ma='Mahamatra:BAAALAADCggICAAAAA==.Mamsbeauty:BAAALAAECgYICgAAAA==.Marilith:BAAALAADCggIFgAAAA==.Markfallen:BAAALAADCgUIBQAAAA==.Math:BAAALAAECgQICAAAAA==.Matsoo:BAAALAAECgYICQAAAA==.',Me='Medyza:BAAALAAECgYIBgAAAA==.Meleager:BAAALAADCggIHQAAAA==.Merliandra:BAAALAAECgYIDwAAAA==.Merranderr:BAABLAAECoEVAAILAAgIqhLlJwD2AQALAAgIqhLlJwD2AQAAAA==.Merraveth:BAAALAADCggICAAAAA==.Metalhooves:BAAALAADCgUIBQAAAA==.',Mi='Mightysloth:BAAALAAECgYIDwAAAA==.Mikanni:BAAALAAECgcIEwAAAA==.Milojin:BAAALAAECgMIAwABLAAECgYICAADAAAAAA==.Miloladin:BAAALAADCgcIDgABLAAECgYICAADAAAAAA==.Missflame:BAAALAAECggICAAAAA==.Mistpirit:BAAALAAECggICgAAAA==.',Mo='Moo:BAACLAAFFIENAAIbAAUIwSBSAAD7AQAbAAUIwSBSAAD7AQAsAAQKgRgAAhsACAgUJukAAHADABsACAgUJukAAHADAAAA.Mooglo:BAABLAAECoEWAAIcAAcI7A2cIABvAQAcAAcI7A2cIABvAQAAAA==.Moonowl:BAAALAADCggIHQAAAA==.Moonwolf:BAAALAADCgMIAwAAAA==.Moradine:BAAALAAECgYIDAAAAA==.Morilith:BAAALAAECgYIDwAAAA==.Morningstar:BAAALAAECgYICQAAAA==.Morphfang:BAAALAAECgQIBgAAAA==.Mosheh:BAAALAAECgYIDgAAAA==.Motto:BAAALAAECgUICQAAAA==.Moxzin:BAAALAAECgMIAwAAAA==.',Mu='Mudder:BAAALAADCggIDgAAAA==.Muddles:BAAALAAECgQIBgAAAA==.Mudlock:BAAALAAECgUICQAAAA==.Multiruss:BAAALAAECgUIBQAAAA==.',My='Mystfall:BAABLAAECoEgAAIdAAgIqiA7DQDSAgAdAAgIqiA7DQDSAgAAAA==.',['Mö']='Möonhunter:BAAALAADCgcIBwAAAA==.',Ne='Nephes:BAAALAAECgQIBQAAAA==.Nerishanna:BAAALAAECgEIAQAAAA==.Newstrand:BAAALAAECgEIAQAAAA==.Nexen:BAAALAADCgcICgAAAA==.',Ni='Niranu:BAAALAAECgQIBAAAAA==.Niridami:BAAALAAECgcIEwAAAA==.',No='Nodri:BAAALAADCgUIDQAAAA==.Norzhyl:BAAALAADCggIEwAAAA==.Notsoawsome:BAAALAAECgcICwAAAA==.',Nu='Nudgess:BAAALAAECgYIEgAAAA==.Nutelia:BAAALAADCgcICwAAAA==.',Oc='Oculeth:BAAALAADCgEIAQAAAA==.',On='Onenightstab:BAABLAAECoEjAAMMAAgI6h3XFQAYAgAMAAYImB7XFQAYAgANAAUIRxkrDwCJAQAAAA==.Onias:BAAALAADCggICgAAAA==.Onlyhots:BAAALAAECgIIAQABLAAECggIGgAIAKkeAA==.',Or='Orangessham:BAAALAAECgYIBgAAAA==.Orclander:BAAALAAECgMIAwAAAA==.Orcrizz:BAAALAADCgYIBgAAAA==.Oromer:BAABLAAECoEZAAIHAAgIECJkDAAIAwAHAAgIECJkDAAIAwAAAA==.Oromiz:BAAALAAECgYICQABLAAECggIGQAHABAiAA==.',Oz='Ozamudazai:BAAALAADCggIEAAAAA==.',Pa='Painkilla:BAAALAAECgUIBQAAAA==.Paluman:BAAALAAECgYICgAAAA==.Pandamonioom:BAAALAAECgYICAAAAA==.Pandelement:BAAALAADCgMIAwAAAA==.Paterson:BAAALAAECgQIAwABLAAECgcIEwADAAAAAA==.Pats:BAAALAAECgcIEwAAAA==.Patts:BAAALAADCggIDwABLAAECgcIEwADAAAAAA==.Païnkïller:BAAALAADCgQIBAAAAA==.',Pe='Pestilënce:BAABLAAECoEaAAIIAAgIqR5hEwDBAgAIAAgIqR5hEwDBAgAAAA==.Pete:BAAALAAECggIDwAAAA==.',Ph='Pheea:BAAALAADCggIBwABLAADCggIEAADAAAAAA==.',Po='Popiku:BAAALAADCggICAAAAA==.Posof:BAABLAAECoEcAAIeAAgIBRk1BACTAgAeAAgIBRk1BACTAgAAAA==.',Pu='Punchnkick:BAAALAAECgIIAgAAAA==.',Py='Pyranna:BAAALAADCgYICAAAAA==.',['Pá']='Párzival:BAAALAAECggIAwAAAA==.',['Pî']='Pîngù:BAAALAADCggICwAAAA==.',Qu='Qudeda:BAAALAAECgcIEwAAAA==.',Ra='Radopinecone:BAAALAAECgMIBgAAAA==.Rakas:BAAALAAECgIIBAABLAAECgcIFAAfAD4fAA==.Ravensoul:BAAALAAECgcIBwAAAA==.Rayaan:BAAALAADCggICAAAAA==.Razna:BAAALAAFFAEIAQAAAA==.',Re='Redleg:BAAALAAECgcICgABLAAECggIGgAIANUbAA==.Relcloud:BAAALAADCgUIBQAAAA==.Renadriel:BAAALAAECgYIEAAAAA==.Repayment:BAAALAAECgYIBgAAAA==.Revienor:BAAALAADCggICAAAAA==.',Ri='Rianna:BAAALAADCgcICAAAAA==.Rikai:BAAALAADCgcIEAAAAA==.Rikky:BAACLAAFFIEHAAIXAAMIVh+4AgAdAQAXAAMIVh+4AgAdAQAsAAQKgR8AAhcACAjkJSIBAHkDABcACAjkJSIBAHkDAAAA.',Ro='Rognesh:BAAALAAECgYIDwAAAA==.Rollinger:BAAALAADCggICAAAAA==.',Sa='Salita:BAAALAADCggIFgAAAA==.Salmanrushdi:BAAALAADCgcICQAAAA==.Salém:BAAALAAECgYIBgAAAA==.Sanatoré:BAAALAAECgIIBAAAAA==.Sardothien:BAAALAAECgMIAwAAAA==.Sausage:BAAALAAECgYIDAAAAA==.',Se='Sephiroo:BAAALAADCgcIBwAAAA==.Serf:BAAALAADCgcIBwAAAA==.Serpentt:BAAALAADCgIIAgAAAA==.',Sh='Shabagooba:BAAALAADCggICAAAAA==.Shame:BAAALAADCgIIAgAAAA==.Shark:BAAALAAECggIDQAAAA==.Shatterlyn:BAAALAADCggIEAAAAA==.Shaðd:BAAALAAECgQIBAABLAAECggIHQAYACgbAA==.Shaðð:BAABLAAECoEdAAQYAAgIKBslCgBdAgAYAAgIMBklCgBdAgALAAgIkhQ2IQAlAgAZAAEI+BA8LQBMAAAAAA==.Shiftpala:BAABLAAECoEZAAIbAAgIMhniCQBFAgAbAAgIMhniCQBFAgAAAA==.Shinkawa:BAAALAADCgcIBwAAAA==.Sháx:BAABLAAECoEWAAIIAAcItiN5FQCxAgAIAAcItiN5FQCxAgAAAA==.',Si='Siemano:BAAALAAECgMIBgAAAA==.Sigyn:BAAALAAECgcIEAAAAA==.Silmaril:BAAALAAECgYIDQAAAA==.Sionuazel:BAAALAADCgIIAgAAAA==.',Sk='Skallepär:BAAALAADCggICAAAAA==.Skinkefeen:BAAALAADCggIFwAAAA==.Skyeblue:BAAALAAECgEIAQAAAA==.Skyggepræst:BAAALAAECggICAAAAA==.',Sl='Slaan:BAAALAAECgYIEAAAAA==.Slobbo:BAAALAADCggICAABLAADCggIEAADAAAAAQ==.Slubz:BAAALAAECgcIBwAAAA==.',Sn='Snuv:BAABLAAECoEWAAILAAcI9CRECgD5AgALAAcI9CRECgD5AgAAAA==.',So='Soluna:BAAALAAECgQIBAABLAAECgUIBQADAAAAAA==.Sonnyy:BAAALAAECgMIAwAAAA==.Soshinoki:BAAALAAECgIIAgAAAA==.',Sq='Sqezz:BAAALAADCgEIAQAAAA==.',St='Starie:BAAALAADCggIGAAAAA==.Starsurge:BAAALAAECggIDAAAAA==.',Su='Sufix:BAAALAADCggIHQAAAA==.',['Sá']='Sátan:BAAALAADCgMIAwAAAA==.',['Sä']='Säphira:BAAALAADCgcIBwAAAA==.',Ta='Taelorea:BAABLAAECoEdAAIIAAgIYRroIABmAgAIAAgIYRroIABmAgAAAA==.Takeidi:BAAALAADCggIDwABLAAECgYIEAADAAAAAA==.Takeily:BAAALAAECgYIEAAAAA==.Takeimo:BAAALAADCggIDgABLAAECgYIEAADAAAAAA==.Tal:BAAALAADCggICAAAAA==.Tamagotchi:BAAALAADCgEIAQAAAA==.Tank:BAAALAADCggICAABLAAFFAUIDQAbAMEgAA==.Tatsuya:BAAALAADCgcICgAAAA==.',Te='Teamtek:BAACLAAFFIEGAAIPAAMI+g07BwDvAAAPAAMI+g07BwDvAAAsAAQKgR8AAg8ACAhkHgsMAOICAA8ACAhkHgsMAOICAAAA.Temutank:BAAALAAECgUICAAAAA==.Tenegor:BAAALAADCgcIDgAAAA==.Tezz:BAAALAADCggIDAAAAA==.',Th='Thaelion:BAAALAADCggIDwAAAA==.Tharlin:BAAALAADCggIDwAAAA==.Thefezz:BAAALAAECgMIBAAAAA==.Thegreyorion:BAAALAADCgYIDAAAAA==.Thelin:BAAALAADCgcIBwAAAA==.Themoonlight:BAAALAAECgYIBgAAAA==.Thepurifier:BAAALAAECgIIAgAAAA==.Theqila:BAAALAAFFAIIAgAAAA==.Therighteous:BAAALAADCgQIBAAAAA==.Thevelen:BAAALAAECgcIBwAAAA==.Thorale:BAAALAAECgEIAQAAAA==.Thundérshade:BAACLAAFFIEGAAIFAAIICiE2CADGAAAFAAIICiE2CADGAAAsAAQKgR8AAgUACAgjJm8AAIsDAAUACAgjJm8AAIsDAAAA.Thylathras:BAAALAAECgEIAQAAAA==.Thégrínch:BAAALAADCgYIDAAAAA==.',Ti='Tinyclap:BAAALAAECgUIBQABLAAECggIGgAIANUbAA==.Tiriiron:BAAALAADCgUIBwAAAA==.',To='Toadslapper:BAAALAADCggICAABLAAECgYIBgADAAAAAA==.Toblock:BAAALAAECgYIDwAAAA==.',Tr='Triage:BAABLAAECoEWAAICAAcIfhRrJgCqAQACAAcIfhRrJgCqAQAAAA==.Trol:BAAALAAECgcIDgAAAA==.Trollbear:BAAALAADCggIAwAAAA==.',Ts='Tsantuuro:BAAALAAECgMIAwAAAA==.',Tu='Tubez:BAAALAAECgMIAwAAAA==.Tumbletoe:BAAALAAECgIIAgAAAA==.Tupio:BAAALAAECgcICQAAAA==.',Ty='Tyrtael:BAABLAAECoEdAAIdAAgIsCM7BQA0AwAdAAgIsCM7BQA0AwAAAA==.Tyrtaele:BAAALAADCggIGAAAAA==.',Un='Unbearabull:BAAALAAECgcIDQAAAA==.',Va='Vaarsanarius:BAAALAADCgcIDgABLAAECgYICAADAAAAAA==.Vaduum:BAAALAADCggICAAAAA==.Vaelerise:BAAALAADCgcIBwAAAA==.Valerous:BAAALAAECgQIBgAAAA==.Valleyfury:BAAALAADCgYIBwAAAA==.Valleyhunt:BAAALAAECgYIBgAAAA==.Valleymist:BAAALAAECgMIAwAAAA==.Valleymoon:BAAALAAECgcIEgAAAA==.Valvari:BAAALAAECgYIDQAAAA==.Vaolen:BAAALAADCgYIBgAAAA==.',Ve='Veiria:BAAALAADCggIHgAAAA==.Vek:BAAALAADCgUICgAAAA==.Verity:BAAALAADCgcICwAAAA==.Veyrix:BAAALAADCggIDgAAAA==.',Vi='Videogames:BAAALAAECgMIAwAAAA==.Vikingness:BAAALAAECgYICgAAAA==.Viollet:BAAALAAECgYIDAAAAA==.Virus:BAAALAADCggIEAAAAA==.Visaen:BAABLAAECoEdAAMHAAgIYSWrAgBuAwAHAAgITCWrAgBuAwAbAAYIuiEHEQDHAQAAAA==.',Vo='Voiddemon:BAAALAADCgYICgAAAA==.Voidpriesty:BAAALAADCgcICwAAAA==.Vorp:BAAALAAECgcIEwAAAA==.Voídz:BAAALAADCgQIBAAAAA==.',['Ví']='Víóla:BAAALAAECgYIEAAAAA==.',Wa='Warlockywoo:BAAALAAECgYIBwAAAA==.',Wi='Wildi:BAAALAAECgQICQAAAA==.Winghunter:BAAALAADCgEIAQAAAA==.Wintertooth:BAAALAAECgYIEQAAAA==.Wipp:BAAALAAECgMIBgAAAA==.',Wo='Wombleshed:BAAALAAECgMIBQAAAA==.',Wt='Wtbname:BAAALAAECgcICAAAAA==.',Xa='Xaben:BAAALAAECgQIBgAAAA==.Xabriel:BAAALAAECgUIBQAAAA==.',Xi='Xisuka:BAAALAAECgcIDQABLAAECggIGQAHABAiAA==.',Xy='Xylor:BAAALAAECggICAAAAQ==.Xylordh:BAAALAADCggICAABLAAECggICAADAAAAAA==.Xylorsh:BAAALAADCgYIDAABLAAECggICAADAAAAAQ==.Xyo:BAAALAAECgEIAQABLAAECgUIBQADAAAAAA==.Xyothene:BAAALAADCggICAABLAAECgUIBQADAAAAAA==.',Ye='Yea:BAAALAAECgMIBAAAAA==.Yesusjupp:BAAALAAECgEIAQABLAAECgYICAADAAAAAA==.',Yo='Yora:BAAALAAECgYIDQAAAA==.',Yu='Yubabazeniba:BAACLAAFFIEIAAIdAAMIdyMwAgA0AQAdAAMIdyMwAgA0AQAsAAQKgRoAAh0ACAiXJrUBAGkDAB0ACAiXJrUBAGkDAAAA.',Za='Zaldias:BAAALAADCggIDQAAAA==.Zanav:BAAALAADCgQIBAAAAA==.Zarartan:BAAALAADCgYIDAAAAA==.Zaravos:BAABLAAECoEUAAIfAAcIPh+jHQByAgAfAAcIPh+jHQByAgAAAA==.',Ze='Zerotoniaa:BAABLAAECoEaAAIFAAgIriAeCAABAwAFAAgIriAeCAABAwAAAA==.',Zh='Zharelyn:BAAALAAECgQIBgAAAA==.',Zi='Zicklewick:BAAALAADCggIEAAAAA==.Ziyala:BAAALAAECgYICgAAAA==.',Zy='Zynadin:BAAALAAECgQIBAAAAA==.',['Áu']='Áura:BAAALAAECgMIAQAAAA==.',['Ðr']='Ðrafi:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end