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
 local lookup = {'Unknown-Unknown','Paladin-Holy','DeathKnight-Frost','Warlock-Destruction','Warrior-Arms','Mage-Frost','Mage-Arcane','Rogue-Assassination','Shaman-Restoration','Druid-Restoration','Druid-Balance','Druid-Guardian','Warrior-Fury','Shaman-Elemental','Priest-Holy','Hunter-BeastMastery','Mage-Fire','Warlock-Demonology','Warrior-Protection','Monk-Windwalker','DemonHunter-Havoc','Priest-Shadow','Paladin-Retribution','Hunter-Marksmanship','Evoker-Devastation','Hunter-Survival','DemonHunter-Vengeance','DeathKnight-Unholy','Monk-Mistweaver','Druid-Feral','Paladin-Protection','Priest-Discipline',}; local provider = {region='EU',realm='Alonsus',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Acerimer:BAAALAAECgcIEgAAAA==.Achlys:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Ai='Aidos:BAABLAAECoEbAAICAAgIQxg5GgAKAgACAAgIQxg5GgAKAgAAAA==.Aim:BAAALAAECgcIEwAAAA==.',Ak='Akumma:BAACLAAFFIEHAAIDAAMI8BRlFgDuAAADAAMI8BRlFgDuAAAsAAQKgRkAAgMACAiMHhkuAI8CAAMACAiMHhkuAI8CAAAA.',Al='Alexuss:BAAALAADCgIIAgAAAA==.Alipala:BAAALAAECgcIEQAAAA==.Alixia:BAAALAADCggIEAAAAA==.Altimage:BAAALAAFFAIIAgABLAAFFAcIEAAEAGYYAA==.',Am='Amesha:BAAALAAECgYIDAAAAA==.',An='Anakin:BAAALAADCgQIAgAAAA==.Andorei:BAAALAAECgYIDgAAAA==.',Ar='Arnfrid:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.Artethion:BAAALAADCggIDwAAAA==.',As='Assasinwar:BAABLAAECoEaAAIFAAcIxyFRBADCAgAFAAcIxyFRBADCAgAAAA==.Asunela:BAABLAAECoEkAAMGAAgIMhdaKQC1AQAHAAcI1hRYTwDwAQAGAAcIJBhaKQC1AQAAAA==.',Av='Avatuss:BAAALAAECgYIEAAAAA==.',Ba='Badbonesdr:BAAALAADCggICAABLAAECggIFAACAOccAA==.Badbonesp:BAABLAAECoEUAAICAAcI5xwlFQA3AgACAAcI5xwlFQA3AgAAAA==.Balenciaga:BAABLAAECoEcAAIIAAgIKR1qDwCcAgAIAAgIKR1qDwCcAgABLAAFFAMICwAJACUNAA==.Barathrum:BAACLAAFFIEJAAMKAAIIOxxJFQCmAAAKAAIIOxxJFQCmAAALAAEI1gcAHwBAAAAsAAQKgS0ABAsACAg6Hw4QAMYCAAsACAg6Hw4QAMYCAAoACAhMHXkWAH0CAAwAAgjhIEMfALwAAAAA.Bavarion:BAACLAAFFIEGAAINAAIIgx65GACuAAANAAIIgx65GACuAAAsAAQKgR0AAg0ACAjTHwsWAN8CAA0ACAjTHwsWAN8CAAAA.',Be='Bedoir:BAAALAADCggICAAAAA==.Beefquake:BAAALAADCggIGQAAAA==.Beefstake:BAAALAAECgMIAwAAAA==.Beefsteak:BAAALAAECgYICAAAAA==.Behamat:BAAALAAECgUIBQAAAA==.Belfsteak:BAAALAADCggIHAAAAA==.',Bi='Bigdaddruid:BAAALAAECgIIAQAAAA==.Biglez:BAAALAAECgQIBQAAAA==.Bimsatron:BAABLAAECoEeAAIOAAgIZRt4HgCGAgAOAAgIZRt4HgCGAgAAAA==.',Bl='Blackarrow:BAAALAAECgEIAQAAAA==.Blamblam:BAAALAADCgcIBwAAAA==.Blixtnedslag:BAAALAADCgUIBQAAAA==.Bloodhand:BAAALAADCgYIBgAAAA==.Blueshameh:BAABLAAECoEbAAIPAAcIkR05JAA7AgAPAAcIkR05JAA7AgAAAA==.',Bo='Bogalock:BAAALAAFFAIIAgAAAA==.Bootleg:BAAALAAECggICQAAAA==.Bosjesvrouw:BAAALAADCgcIEgAAAA==.',Br='Brittlebones:BAAALAADCggIDwAAAA==.Bronzebarda:BAAALAAECgIIAwAAAA==.',Bv='Bvoker:BAAALAAECgYIBwAAAA==.',Ca='Calanthea:BAAALAADCgYICgAAAA==.Candyfloss:BAAALAAECgcIEwAAAA==.',Ch='Channi:BAAALAADCgUIBQAAAA==.Choaslord:BAABLAAECoEZAAIQAAYIUw1WnAA4AQAQAAYIUw1WnAA4AQAAAA==.',Cl='Cloudele:BAAALAAECgIIAgAAAA==.Cloudie:BAABLAAECoEWAAQGAAgIRRlwEgBnAgAGAAgIRRlwEgBnAgAHAAQIrQrRqADdAAARAAEI+QewHgAyAAAAAA==.Cloudknight:BAAALAAECgIIAgAAAA==.Cloudmink:BAAALAAECgcIDwABLAAECggIFgAGAEUZAA==.Cloudnosoul:BAAALAADCgcIBwABLAAECggIFgAGAEUZAA==.Cloudrockin:BAAALAADCgYICAABLAAECggIFgAGAEUZAA==.',Co='Colliewong:BAAALAAECgYIDgAAAA==.Conno:BAABLAAECoEiAAISAAgI8x+qBQDyAgASAAgI8x+qBQDyAgAAAA==.Constructus:BAAALAAECgYICAAAAA==.Coomknight:BAAALAADCggICAAAAA==.',Cy='Cylia:BAAALAAECggICAAAAA==.Cyntax:BAABLAAECoEXAAQFAAgIZQ1ZGQApAQAFAAYI4wtZGQApAQATAAgIPwrrRQAUAQANAAEItAaTzwAnAAAAAA==.',Da='Dagochnatt:BAAALAADCgYIDAAAAA==.Daintree:BAAALAADCggIBQAAAA==.Dalinar:BAAALAAECgQIBAAAAA==.Dandelion:BAABLAAECoEWAAILAAcIHSGRFQCKAgALAAcIHSGRFQCKAgAAAA==.Dawei:BAABLAAECoEcAAIUAAcIlB7MEABxAgAUAAcIlB7MEABxAgAAAA==.',De='Deaderror:BAABLAAECoEUAAIDAAcILAX10gApAQADAAcILAX10gApAQAAAA==.Degros:BAAALAAECgYIEAAAAA==.Deisin:BAAALAAECgYIEAAAAA==.Destroboom:BAAALAADCgYIBgAAAA==.Dewie:BAABLAAECoEcAAIOAAcI4yC2HACSAgAOAAcI4yC2HACSAgAAAA==.',Di='Dieselolle:BAAALAAECgIIAgAAAA==.Diggerdagger:BAAALAADCgYICgAAAA==.Dikkespier:BAAALAAECgEIAwAAAA==.Disturbia:BAAALAAECggIDAAAAA==.',Do='Dormantdrago:BAABLAAECoEZAAIPAAgIpRIzMwDqAQAPAAgIpRIzMwDqAQAAAA==.Dormy:BAAALAADCgcICAABLAAECggIGQAPAKUSAA==.',Dr='Dragonbreath:BAAALAAECgYIBgAAAA==.Draxdh:BAABLAAECoEXAAIVAAYI6xeFgQCMAQAVAAYI6xeFgQCMAQAAAA==.Draxmage:BAAALAADCgcIBwAAAA==.Dreamwalk:BAAALAADCgQIBAABLAADCggICAABAAAAAA==.Drogba:BAAALAAECgYIDAAAAA==.',Du='Dundo:BAAALAAECgYIDAAAAA==.',Ea='Eadinumbra:BAAALAAECgYIDgAAAA==.',Ee='Eery:BAAALAADCggIFAAAAA==.',Ei='Eirnith:BAACLAAFFIEPAAIPAAUIzB6+AgDxAQAPAAUIzB6+AgDxAQAsAAQKgS8AAw8ACAhOJdYCAFsDAA8ACAhOJdYCAFsDABYACAhsFrYhAEICAAAA.',El='Eldinumbra:BAAALAAECgYIDgAAAA==.Eledamiri:BAAALAADCgMIAwAAAA==.',Em='Emptyhead:BAAALAAECgYICwAAAA==.',En='Enkilzar:BAAALAADCgIIAgAAAA==.Enyo:BAAALAADCgIIAQAAAA==.',Eo='Eowan:BAAALAAECgYIDgABLAAFFAIICQAKADscAA==.',Es='Escarcia:BAAALAADCgYIBwABLAAECgcICgABAAAAAA==.',Ev='Evenuel:BAAALAADCggICAAAAA==.',Ew='Ewsyde:BAAALAADCgYICgAAAA==.',Ex='Exo:BAAALAAECgQIBAAAAA==.',Ey='Eylaea:BAAALAAECgEIAQAAAA==.',Fa='Faab:BAAALAAECgYIBgABLAAECggIGAAHAM8iAA==.',Fe='Ferisons:BAABLAAECoEeAAIXAAcICQksqgBkAQAXAAcICQksqgBkAQAAAA==.Ferrin:BAABLAAECoEhAAIFAAgIQx4CBQCrAgAFAAgIQx4CBQCrAgAAAA==.',Fi='Fil:BAAALAAECgYICQAAAA==.Fireborn:BAACLAAFFIENAAMQAAUIgSKsBwCDAQAQAAQIWCOsBwCDAQAYAAQIEiGsBQB8AQAsAAQKgRQAAxgACAhXI0AWAJkCABgACAhXI0AWAJkCABAAAgjEE/HmAHcAAAAA.',Fl='Fluffnut:BAAALAAECggIDgAAAA==.',Fr='Friona:BAAALAAECgQIBAAAAA==.Frostyyballs:BAAALAAECgIIBAAAAA==.',Ga='Gaiyaa:BAAALAAECgMIAwAAAA==.',Ge='Geilschrulle:BAAALAAECgMIAwAAAA==.Geowrath:BAAALAAECgYIDwAAAA==.',Gi='Gilfread:BAAALAAECgYIEAAAAA==.',Gr='Griswold:BAAALAAECggICwAAAA==.Grizana:BAAALAAECgYIBgAAAA==.',Gu='Gustavgurt:BAAALAADCgcIDgAAAA==.',Gw='Gwandryas:BAABLAAECoEXAAIQAAcIzgZ6owApAQAQAAcIzgZ6owApAQAAAA==.',Ha='Harei:BAAALAAECgYIDgAAAA==.Harriét:BAAALAADCgUIBQABLAAECggIKwASAAAfAA==.',He='Hearthguard:BAAALAAECgUICQABLAAECgcIDgABAAAAAA==.Hellhunter:BAABLAAECoEdAAIQAAgIPhuGMgBHAgAQAAgIPhuGMgBHAgAAAA==.Hexenbiest:BAABLAAECoEZAAIWAAgI0RWiJQAlAgAWAAgI0RWiJQAlAgAAAA==.Hexorcist:BAAALAAECggIEAAAAA==.',Hi='Hipolita:BAAALAADCgYIBgAAAA==.Hitman:BAAALAAECgYIDgAAAA==.',Hk='Hkxytall:BAABLAAECoEWAAIVAAgIew7NZADKAQAVAAgIew7NZADKAQAAAA==.',Ho='Hobomagic:BAAALAADCgIIAgAAAA==.Holyfelf:BAAALAAECgIIAgAAAA==.Hotlegochick:BAAALAADCggICAAAAA==.',Ig='Igglepiggle:BAAALAADCgcICAAAAA==.',Il='Ilarie:BAAALAAECgYICgAAAA==.Illidiggity:BAAALAADCggIDwABLAAFFAUICgAHABIUAA==.Illirari:BAAALAAECgYIEAAAAA==.',Im='Imlerith:BAAALAADCgUIBgAAAA==.Immortall:BAAALAADCgIIAgAAAA==.',In='Incidina:BAAALAAECgIIBQAAAA==.Indolentus:BAAALAAECgUIBwAAAA==.Infinity:BAACLAAFFIEGAAIXAAII1AmPMgCVAAAXAAII1AmPMgCVAAAsAAQKgSYAAhcACAh6GgpDAEICABcACAh6GgpDAEICAAAA.',Iw='Iwwy:BAAALAADCgYICQAAAA==.',Ja='Jadelee:BAAALAAECgYIDgABLAAECgcIGgAPAFAgAA==.Janie:BAABLAAECoEiAAMKAAcI5AptXAA2AQAKAAcI5AptXAA2AQALAAEIIQdIjAAxAAAAAA==.',Je='Jeppydin:BAAALAADCgEIAQABLAAFFAEIAQABAAAAAA==.',Jo='Johero:BAAALAAFFAMIAwABLAAFFAIICQAKADscAA==.',['Jä']='Jägern:BAAALAAECgYICAAAAA==.',['Jó']='Jóórdy:BAAALAADCgcIBwAAAA==.',Ka='Karix:BAABLAAECoEjAAMCAAgI1gjxMgBkAQACAAgI1gjxMgBkAQAXAAMIEATeEQF4AAAAAA==.Karnayna:BAAALAAECgcICgAAAA==.',Ke='Keldral:BAAALAAECgYIBgABLAAFFAIICQAKADscAA==.Kelfrost:BAAALAAECgcIDQAAAA==.Kerath:BAAALAADCgYICQAAAA==.',Kl='Klootvioolss:BAABLAAECoEUAAIFAAcIvBZLCwACAgAFAAcIvBZLCwACAgAAAA==.',Ko='Kolwl:BAACLAAFFIEMAAMSAAYILyASAAAmAgASAAUIZSMSAAAmAgAEAAEIIxBPOwBUAAAsAAQKgSEAAxIACAjuJf8AAHEDABIACAgLJf8AAHEDAAQAAgj4IC6oALkAAAAA.Koorvaak:BAAALAADCgcIBwAAAA==.Kotonelock:BAAALAADCggIDwAAAA==.',Kr='Krokcydruidh:BAAALAADCgQIBAAAAA==.',Kv='Kvinnen:BAAALAADCgQICAAAAA==.',['Kå']='Kåsago:BAACLAAFFIEGAAITAAIImSUVCADhAAATAAIImSUVCADhAAAsAAQKgRcAAxMACAgdJFIJAOgCABMACAgdJFIJAOgCAA0AAgiDEoy8AFUAAAAA.',La='Laenas:BAAALAAECgIIAgAAAA==.Lalunatic:BAAALAAECgcIBwAAAA==.Lanni:BAEALAAECggIEQAAAA==.Lanniprie:BAEALAAECggICAABLAAECggIEQABAAAAAA==.Lant:BAAALAAECgQIBAAAAA==.Lavendere:BAABLAAECoEdAAILAAcIdRkdJAASAgALAAcIdRkdJAASAgAAAA==.',Le='Legolás:BAAALAAECgYIAgAAAA==.Lentukas:BAAALAAECgYIEAAAAA==.',Li='Licca:BAAALAAECgEIAQAAAA==.Lindael:BAAALAADCgcIBwAAAA==.Liptan:BAAALAADCgUIBQAAAA==.',Ll='Llurien:BAAALAAECgIIAgAAAA==.',Lu='Luxara:BAAALAAECgEIAQAAAA==.',Lx='Lxstsoul:BAAALAAECgIIAgAAAA==.',Ly='Lyndrathal:BAAALAAECgQIBAAAAA==.',Ma='Mackenpuffz:BAAALAADCggICwAAAA==.Madara:BAAALAADCgIIAgAAAA==.Madeinskåne:BAAALAAECggIEAAAAA==.Magekéld:BAAALAADCgUIBQABLAADCggIEgABAAAAAA==.Maitri:BAAALAAECgYICAABLAAECgcIGwAPAJEdAA==.Malevolence:BAAALAAECgcIDwAAAA==.Manticor:BAABLAAECoEkAAIEAAgIKwycdABbAQAEAAgIKwycdABbAQAAAA==.Marellet:BAAALAAECgQIBAABLAAECgcIEgABAAAAAA==.Mari:BAABLAAECoEZAAIEAAcIXgxbZACIAQAEAAcIXgxbZACIAQAAAA==.Marlet:BAAALAAECgcIEgAAAA==.',Me='Med:BAABLAAECoEXAAIDAAcI3RcQdwDMAQADAAcI3RcQdwDMAQAAAA==.Medieev:BAAALAAFFAUIAgAAAA==.Mekkaburn:BAAALAAECgMIAwAAAA==.Messai:BAAALAADCgIIAgAAAA==.Meí:BAAALAADCgYIBgAAAA==.',Mi='Michika:BAABLAAECoEeAAIGAAcI6A5wLgCYAQAGAAcI6A5wLgCYAQAAAA==.Miedmar:BAAALAADCggICAABLAAECgcIIAAZAL4fAA==.Miedvoker:BAABLAAECoEgAAIZAAcIvh9DEwB4AgAZAAcIvh9DEwB4AgAAAA==.Miidgeski:BAAALAADCgcIBwAAAA==.Minimagimage:BAABLAAECoEgAAMHAAgIHBhCPQAwAgAHAAgIHBhCPQAwAgAGAAUIDwgJVQDbAAAAAA==.',Mn='Mnemetress:BAABLAAECoEXAAQQAAgI8xK6XgC+AQAQAAgIexK6XgC+AQAaAAcI9wkpEQBXAQAYAAYI8we5bADzAAAAAA==.',Mo='Monkeypk:BAAALAAECgYICwABLAAECgcIEQABAAAAAA==.Monniela:BAABLAAECoEZAAIMAAYIRQS0HgDEAAAMAAYIRQS0HgDEAAAAAA==.Moonclavs:BAAALAADCggICAAAAA==.Morgana:BAAALAAECggIDQAAAA==.Morticus:BAAALAADCgcIBwAAAA==.Morí:BAAALAAECgYIBgAAAA==.',My='Mysterie:BAAALAADCgcIBwAAAA==.',['Mó']='Mórack:BAAALAAECgcIBwAAAA==.',Na='Nabulous:BAAALAADCggIDwAAAA==.',Ne='Nerk:BAACLAAFFIEHAAIVAAMIiRQCEAABAQAVAAMIiRQCEAABAQAsAAQKgRgAAhUACAhPGjUqAIoCABUACAhPGjUqAIoCAAAA.Nerrk:BAABLAAECoEZAAMVAAgIeh8bGQDlAgAVAAgIeh8bGQDlAgAbAAIIQhQgSQBmAAABLAAFFAMIBwAVAIkUAA==.',Ni='Nicle:BAAALAADCggIDgAAAA==.Nightsblade:BAAALAADCggICgAAAA==.Nightswar:BAAALAAECgQIBAABLAAECgcIEQABAAAAAA==.',No='Nosmite:BAAALAADCgQIBAAAAA==.',Nu='Nurgle:BAABLAAECoEeAAIcAAcIPR/VCgCLAgAcAAcIPR/VCgCLAgAAAA==.',Ob='Obosodk:BAAALAADCggIBwAAAA==.',Ol='Olordwhite:BAABLAAECoEXAAIQAAcIwB5VPgAbAgAQAAcIwB5VPgAbAgAAAA==.',Ov='Overground:BAABLAAECoEaAAMCAAYIMRkdJwCrAQACAAYIMRkdJwCrAQAXAAIIOhdjCQGLAAAAAA==.',Pa='Paninidk:BAAALAADCggICgAAAA==.Paninipriest:BAAALAADCggICAAAAA==.Paniniveng:BAAALAADCggICAAAAA==.Paranax:BAAALAAECgYIBgAAAA==.',Ph='Phoenixw:BAAALAADCggIKAAAAA==.',Pr='Protean:BAABLAAECoEgAAMMAAgIFxdMCQAYAgAMAAgIFxdMCQAYAgAKAAYIUB3aMgDbAQAAAA==.',Pu='Puddled:BAAALAAECgIIAgABLAAECggIGQAPAKUSAA==.Pulverdemon:BAAALAADCggICwAAAA==.',Qp='Qppa:BAAALAADCggICAAAAA==.',Qu='Qunable:BAAALAADCggIDwAAAA==.',Ra='Raycer:BAAALAADCgEIAQAAAA==.Raylee:BAAALAAECgMIBwAAAA==.Razneth:BAAALAADCgEIAQAAAA==.',Re='Rennac:BAAALAADCgQIBAAAAA==.Renno:BAAALAADCggIEAABLAAECgcIJgAdAEslAA==.',Rh='Rhya:BAAALAAECggIDAAAAA==.',Ri='Ribbedsteak:BAAALAADCgYIBgAAAA==.',Ro='Roach:BAAALAAECgMIBwAAAA==.Rob:BAAALAADCgcIBwAAAA==.Robbosaur:BAAALAADCggICAAAAA==.Rohanda:BAAALAAECggIEQAAAA==.Rosarias:BAAALAADCggIEAAAAA==.',Ru='Ruhsar:BAAALAADCggIHQAAAA==.',Sa='Salem:BAAALAADCgYIBgAAAA==.Sanfori:BAAALAAECgQIBQAAAA==.Sanforis:BAAALAADCggICAAAAA==.Sanguine:BAAALAAECgYICwAAAA==.',Se='Sembor:BAAALAAECgQIBgAAAA==.',Sh='Shammzie:BAABLAAECoEbAAIQAAcI+xCmcgCOAQAQAAcI+xCmcgCOAQAAAA==.Shamrock:BAAALAAECgcIBwAAAA==.Shardly:BAABLAAECoEaAAIEAAcIsQV0gwA0AQAEAAcIsQV0gwA0AQAAAA==.Shiriek:BAAALAAECgYIBgAAAA==.Shivs:BAAALAAECgYIBgABLAAECggIHwAEAEkMAA==.Shivslady:BAABLAAECoEfAAIEAAgISQweYgCOAQAEAAgISQweYgCOAQAAAA==.',Si='Sian:BAAALAADCgIIAgAAAA==.Sixxi:BAAALAAECgMIAwAAAA==.',Sk='Skuffè:BAABLAAECoEpAAIJAAcImyWRDADnAgAJAAcImyWRDADnAgAAAA==.',Sm='Smollie:BAAALAADCggIFAAAAA==.',Sn='Sndrpala:BAAALAADCggIEAAAAA==.',So='Solace:BAAALAADCggIEAABLAAECggIFAANACkWAA==.Solent:BAABLAAECoEUAAMNAAgIKRYJNgAhAgANAAgIlRUJNgAhAgATAAUIZwfPVwC3AAAAAA==.Solori:BAAALAAECgYIBgABLAAECggIFAANACkWAA==.Soltea:BAAALAAECggIEgABLAAECggIFAANACkWAA==.Sondrius:BAAALAADCgIIAgAAAA==.Songwen:BAAALAADCggICAAAAA==.Soulless:BAAALAADCggICAAAAA==.',St='Stampead:BAAALAADCgMIAwAAAA==.Starzyk:BAABLAAECoEWAAIPAAgI+QdqUQBnAQAPAAgI+QdqUQBnAQAAAA==.Stevenalex:BAAALAADCgMIBAAAAA==.Steviemadman:BAAALAAECgIIAgAAAA==.Steviewondér:BAAALAADCggIAwAAAA==.',Su='Surtfire:BAAALAAECgcIEQAAAA==.',Sy='Syrthio:BAAALAAECgYIEQAAAA==.',Te='Telori:BAAALAAECggIBwAAAA==.Terrorskorn:BAAALAADCgYIBgAAAA==.',Th='Thaderyl:BAABLAAECoEhAAMPAAgI3RvkFgCVAgAPAAgI3RvkFgCVAgAWAAEIHhMagwBAAAAAAA==.Thisislovac:BAABLAAECoEiAAITAAgI2xQ1KQCzAQATAAgI2xQ1KQCzAQABLAAFFAIIBgAEAFYgAA==.Thisiswrong:BAABLAAECoEbAAMQAAcI9yIMGgDBAgAQAAcI9yIMGgDBAgAYAAcIaA0gTwBZAQAAAA==.',Ti='Timesmage:BAAALAAECgcICwABLAAECggIFwABAAAAAA==.Tio:BAAALAADCggIEAAAAA==.',To='Tom:BAAALAADCgYICwAAAA==.Tommy:BAABLAAECoEeAAMNAAgIrhYdMQA4AgANAAgIrhYdMQA4AgAFAAYIzwPpIgCtAAAAAA==.Tormen:BAAALAAECgYICgABLAAECgcIGgAPAFAgAA==.',Tr='Traigar:BAAALAAECgYIEAABLAAFFAIICQAKADscAA==.Trayn:BAAALAAECgYIBgABLAAFFAMIDAAYAJoXAA==.',Ty='Tymann:BAAALAAECgYIBgABLAAECggIGQAWADAfAA==.Tysken:BAAALAADCggICAAAAA==.',['Tâ']='Tâstiç:BAAALAAECgcICgAAAA==.',Un='Undergången:BAAALAAECgYICQAAAA==.Unholyness:BAABLAAECoEjAAIWAAcI2R5nHABrAgAWAAcI2R5nHABrAgAAAA==.Unholynéss:BAAALAAECgYIEQAAAA==.',Va='Valeerian:BAAALAAECgYICwAAAA==.Vall:BAAALAADCggIDwAAAA==.Vanish:BAAALAAECgUIBQAAAA==.Vargen:BAAALAAECgcIDQAAAA==.',Vb='Vbj:BAAALAADCgQIBAAAAA==.',Ve='Veldahar:BAAALAAECgYIBQAAAA==.Vendrakis:BAAALAADCgMIAwAAAA==.',Vi='Viliya:BAAALAADCggICAAAAA==.',Vo='Voidborn:BAAALAAECgYIBgABLAAFFAUIDQAQAIEiAA==.Voxifera:BAABLAAECoEUAAIeAAcIjwq+IABdAQAeAAcIjwq+IABdAQAAAA==.',Vr='Vrykuln:BAABLAAECoEcAAIWAAcIYhuDIwA1AgAWAAcIYhuDIwA1AgAAAA==.',['Vè']='Vèl:BAAALAADCggICAAAAA==.',Wa='Wartooth:BAAALAAECgMIBgAAAA==.',Wi='Wickern:BAAALAAECgYIDAAAAA==.Willowtreé:BAAALAADCggIEAAAAA==.Windwatcher:BAAALAAECgYIEAAAAA==.',Xa='Xaliav:BAAALAADCgcIBwAAAA==.',Xd='Xdiesel:BAABLAAECoEYAAQLAAcIKA8DSQBRAQALAAcIKw4DSQBRAQAMAAII+BTRJQBnAAAeAAEIOQRsQgAeAAAAAA==.',Ya='Yakubu:BAAALAAECggIEwAAAA==.',Yo='Young:BAAALAAECgIIAgAAAA==.',Za='Zabuzan:BAACLAAFFIEPAAMXAAUIKB3GAwDdAQAXAAUIKB3GAwDdAQAfAAMIKgpPBwC7AAAsAAQKgSsAAhcACAgPJvMGAF0DABcACAgPJvMGAF0DAAAA.Zador:BAAALAAECgMIBgAAAA==.Zalstra:BAAALAADCgcIDQAAAA==.Zappaspino:BAAALAAECggICAAAAA==.Zarupia:BAAALAAECgYICQAAAA==.',Ze='Zephyr:BAAALAAECgYIBgABLAAECgcIGgAPAFAgAA==.Zepphiron:BAAALAADCggICAAAAA==.',Zi='Zihso:BAAALAAECgYIEAAAAA==.',Zo='Zonuu:BAAALAAECgEIAQABLAAECgYIEAABAAAAAA==.Zoroastrian:BAABLAAECoEaAAMPAAcIUCBAFwCTAgAPAAcIUCBAFwCTAgAgAAII0RPeIwCCAAAAAA==.',Zw='Zwerfur:BAAALAADCggIEQAAAA==.',['Ém']='Émilia:BAAALAADCgYIBgAAAA==.Émortal:BAAALAAECgYIDAAAAA==.',['Íl']='Íllidann:BAAALAADCgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end