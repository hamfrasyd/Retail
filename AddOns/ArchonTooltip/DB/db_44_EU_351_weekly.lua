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
 local lookup = {'Mage-Arcane','Warrior-Fury','Druid-Balance','DeathKnight-Frost','Unknown-Unknown','Priest-Holy','Priest-Discipline','Rogue-Assassination','DemonHunter-Vengeance','DemonHunter-Havoc','Evoker-Devastation','Druid-Feral','Monk-Windwalker','Paladin-Retribution','Warrior-Protection','Hunter-BeastMastery','Mage-Frost','DeathKnight-Blood','Druid-Restoration','Warlock-Destruction','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Paladin-Protection','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Paladin-Holy','Priest-Shadow','Hunter-Survival','Monk-Mistweaver','Evoker-Preservation','Mage-Fire','Monk-Brewmaster',}; local provider = {region='EU',realm='Vashj',name='EU',type='weekly',zone=44,date='2025-09-23',data={Aa='Aangel:BAAALAADCgIIAQAAAA==.Aaravos:BAACLAAFFIEKAAIBAAIIkiTDHQDYAAABAAIIkiTDHQDYAAAsAAQKgRgAAgEACAjBIkgYAOECAAEACAjBIkgYAOECAAEsAAUUBwgUAAIAnyIA.',Ad='Adhdh:BAAALAADCgYIBgABLAAFFAMICgADAHoXAA==.',Ae='Aegor:BAAALAADCggICAAAAA==.',Af='Affena:BAAALAAECgcIDwAAAA==.',Ai='Ai:BAAALAADCggIGwAAAA==.',Ak='Aknana:BAAALAADCgEIAQAAAA==.',Al='Aldrakith:BAAALAADCgMIBgAAAA==.',Am='Amsun:BAAALAAECgIIAgAAAA==.',An='Andarr:BAABLAAECoEhAAIEAAgIghrbPgBXAgAEAAgIghrbPgBXAgAAAA==.',Ap='Apocaliptus:BAAALAAECgYIDwAAAA==.',Ar='Arianad:BAAALAAECgYICwAAAA==.Arr:BAAALAADCgIIAgABLAAECgUICAAFAAAAAA==.',As='Ashpri:BAAALAAECgYICwABLAAFFAQIBgACAPwGAA==.',At='Atonement:BAABLAAECoEUAAMGAAgIrxolHQBsAgAGAAgIrxolHQBsAgAHAAII8gjvKgBVAAAAAA==.',Ba='Baaphomet:BAABLAAECoEcAAIIAAgIAg1NJADgAQAIAAgIAg1NJADgAQAAAA==.',Be='Begood:BAAALAAECgYIDQAAAA==.',Bl='Blackdin:BAAALAAECgQIBQAAAA==.',Bo='Bosso:BAAALAAECgYIDAAAAA==.Bossodh:BAABLAAECoEhAAMJAAgIjSVoAQBnAwAJAAgIjSVoAQBnAwAKAAII7BXY9wB1AAAAAA==.Bossoe:BAACLAAFFIEaAAILAAcIvyQrAADvAgALAAcIvyQrAADvAgAsAAQKgSYAAgsACAjxJjwAAJcDAAsACAjxJjwAAJcDAAAA.Bossom:BAAALAAECggIDQAAAA==.',Br='Broderplupp:BAAALAAECgYIBgAAAA==.Brol:BAAALAAECgQIBgAAAA==.Brutanaz:BAABLAAECoEnAAIMAAgIcyA/BgDgAgAMAAgIcyA/BgDgAgAAAA==.',Bu='Buddahman:BAABLAAECoEXAAINAAcIxRthFABEAgANAAcIxRthFABEAgAAAA==.Budmaash:BAAALAAECgYIBgAAAA==.Bungler:BAAALAADCggICAAAAA==.',Ca='Cadman:BAAALAADCgcIDQAAAA==.',Ch='Charliegreen:BAAALAADCgIIAgAAAA==.',Cr='Crypthia:BAABLAAECoEYAAIOAAgIchnuPABXAgAOAAgIchnuPABXAgAAAA==.',Da='Damodred:BAAALAADCgcIBwAAAA==.',De='Deathiscomin:BAAALAADCgcIDAAAAA==.Deir:BAAALAAECggIDwAAAA==.Demonfarter:BAAALAAECggIDQAAAA==.Depressed:BAABLAAFFIEGAAIEAAIIQQmIUQCGAAAEAAIIQQmIUQCGAAABLAAFFAMICQAOAKEWAA==.',Do='Dorrak:BAAALAADCgQIBAAAAA==.',Du='Dumrak:BAAALAADCgcIBwAAAA==.',Ek='Ekriz:BAABLAAECoEcAAMJAAcIXRp0EwAEAgAJAAcIXRp0EwAEAgAKAAYIRBb3mABhAQAAAA==.',El='Elarune:BAAALAADCgcIDwAAAA==.Elashia:BAABLAAECoEVAAIJAAYI9iPPDQBSAgAJAAYI9iPPDQBSAgAAAA==.Eloth:BAAALAADCgcIDgABLAAECgcIIgAFAAAAAQ==.Elwind:BAABLAAECoEpAAMCAAgIkB4FGQDOAgACAAgIkB4FGQDOAgAPAAYInAqbUQDgAAAAAA==.',Er='Ere:BAAALAAECgUIBwAAAA==.Eredin:BAABLAAECoEmAAIOAAgIoR9NLgCPAgAOAAgIoR9NLgCPAgAAAA==.Erewar:BAAALAAFFAEIAQAAAA==.Erise:BAAALAADCggICQAAAA==.',Es='Escanor:BAAALAAECgYIBgABLAAECggIIwADAAciAA==.',Fe='Felran:BAAALAAFFAIIBAABLAAFFAcIHwAQAPQfAA==.Fenar:BAACLAAFFIEGAAIRAAIItRrECQCdAAARAAIItRrECQCdAAAsAAQKgRYAAhEACAihHxIKANsCABEACAihHxIKANsCAAAA.',Fi='Five:BAAALAAECgYIBwAAAA==.',Fl='Floorpov:BAAALAADCggICAAAAA==.',Fr='Fraile:BAAALAADCgMIBgAAAA==.',Fs='Fsj:BAACLAAFFIEfAAISAAcInBhxAAB+AgASAAcInBhxAAB+AgAsAAQKgSIAAhIACAgrJfUDACMDABIACAgrJfUDACMDAAAA.',Ga='Gallox:BAAALAAECgIIAwAAAA==.',Go='Gothgf:BAAALAADCggIDwABLAAFFAMICQAOAKEWAA==.',Gr='Grzegorz:BAABLAAECoEZAAITAAcIxBIORQCPAQATAAcIxBIORQCPAQAAAA==.',Gu='Gurumage:BAAALAAECgYIDQAAAA==.Guruwl:BAABLAAECoEVAAIUAAYIUxvvRwDnAQAUAAYIUxvvRwDnAQAAAA==.',He='Hedan:BAAALAAECgEIAQABLAAECgUIBwAFAAAAAA==.Heimdal:BAAALAADCgcIBwAAAA==.',Hi='Highrite:BAAALAAECgcIBwAAAA==.',In='Intix:BAAALAADCggICAAAAA==.',Ir='Irpellion:BAABLAAECoEXAAIMAAgIPx0nBwDLAgAMAAgIPx0nBwDLAgAAAA==.',Ja='Jazzhjørna:BAAALAAECgIIAgAAAA==.',Js='Jsf:BAAALAAECgYIDAAAAA==.',Ju='Julmajoni:BAAALAAFFAMIAwABLAAFFAYICwAKAIEPAA==.',Ka='Kaffis:BAAALAAECgYIBgAAAA==.Kaidron:BAAALAAFFAMICQAAAQ==.Karsta:BAACLAAFFIEZAAITAAYIzBqJAQAaAgATAAYIzBqJAQAaAgAsAAQKgR0AAhMACAh0I0AHAA4DABMACAh0I0AHAA4DAAAA.Kate:BAABLAAECoEgAAIOAAgItiBUGgDuAgAOAAgItiBUGgDuAgAAAA==.',Ke='Kekethul:BAAALAAECgIIAgAAAA==.',Ki='Kitkatt:BAABLAAECoEaAAMRAAYIiArYQwA2AQARAAYIiArYQwA2AQABAAMIlgVuyQBrAAAAAA==.',Ko='Kojosh:BAAALAADCgIIAgAAAA==.',Kr='Kratos:BAABLAAFFIEUAAICAAcInyJNAADTAgACAAcInyJNAADTAgAAAA==.Krukesh:BAAALAAECgcIBwAAAA==.',Ku='Kuparipilli:BAAALAADCgcIBwAAAA==.Kutt:BAAALAAECgQIBAABLAAECggIKQAIAMghAA==.',Kw='Kwaaiseun:BAAALAAECgcIEQAAAA==.',Le='Lemmu:BAABLAAECoEYAAMVAAgIXB7VEwC2AgAVAAgIXB7VEwC2AgAWAAgIDht5HgCJAgAAAA==.Lemmudin:BAAALAAECgEIAQAAAA==.Leqa:BAACLAAFFIEIAAIUAAIIoyDgHgC8AAAUAAIIoyDgHgC8AAAsAAQKgSQAAxQACAhwIggOABsDABQACAhwIggOABsDABcAAQgcAh5CABMAAAAA.',Li='Lightphoenix:BAABLAAECoEgAAIMAAgI8hyHBwDBAgAMAAgI8hyHBwDBAgAAAA==.Liny:BAACLAAFFIEZAAIYAAcI8xpDAACAAgAYAAcI8xpDAACAAgAsAAQKgRwAAhgACAiCJk8BAHQDABgACAiCJk8BAHQDAAAA.',Lo='Lorck:BAAALAADCgEIAQAAAA==.Lost:BAAALAAECgYIDAAAAA==.',Lu='Luke:BAAALAAECgcICQAAAA==.',Ly='Lynna:BAAALAAECgMIAwAAAA==.',Ma='Madcan:BAAALAADCgcICgAAAA==.Magekko:BAAALAAFFAMIAwAAAA==.Malfurion:BAAALAADCggICAABLAAECgcIEgAFAAAAAA==.Malkeenian:BAAALAADCggICAAAAA==.Malzahar:BAAALAADCgYIDAAAAA==.Mansicki:BAAALAADCgYIBgAAAA==.Marcicia:BAAALAADCgcIBwAAAA==.Marmus:BAAALAAECggIBgAAAQ==.',Me='Meowdy:BAAALAAFFAIIBAAAAA==.',Mi='Mighty:BAAALAAECgIIAgABLAAECgcIIgAFAAAAAQ==.Mightypriest:BAAALAADCgcIDwABLAAECgcIIgAFAAAAAA==.Mimtan:BAAALAAECggIDwAAAA==.Misfire:BAAALAAECgcIIgAAAQ==.Mithrina:BAABLAAECoEiAAIQAAcIUBH6gAB0AQAQAAcIUBH6gAB0AQAAAA==.',Mo='Monkstronk:BAAALAAECggIDgAAAA==.Morena:BAAALAAECgcIDgAAAA==.',Mu='Muikkukukko:BAAALAADCggICAAAAA==.Murduck:BAABLAAECoEfAAIZAAgIgAqKEACzAQAZAAgIgAqKEACzAQAAAA==.',Na='Nanu:BAAALAADCgUIBQAAAA==.',Ne='Nesai:BAABLAAECoEZAAIaAAgIFx6VEwCzAgAaAAgIFx6VEwCzAgAAAA==.',Ni='Ninnya:BAAALAADCgcIBwAAAA==.',No='Noodle:BAACLAAFFIEQAAQbAAQIuRNDBABKAQAbAAQIZhJDBABKAQAcAAMILhKXAQDuAAAIAAIIQxPxEgCgAAAsAAQKgS8ABBsACAi2IUYGAMgCABsACAj4HUYGAMgCABwABwiXH1UEAHoCAAgACAi1GgYWAFYCAAAA.',Ny='Nyhm:BAAALAADCgYIBgAAAA==.',['Nô']='Nôstradamus:BAABLAAECoEjAAIDAAgIMg2APACOAQADAAgIMg2APACOAQAAAA==.',Od='Oddislajos:BAACLAAFFIEaAAIIAAYIdCUXAACZAgAIAAYIdCUXAACZAgAsAAQKgR4AAggACAgnJhMCAFgDAAgACAgnJhMCAFgDAAAA.',Oh='Ohalvaro:BAAALAADCggIDQAAAA==.',Om='Omageo:BAAALAADCggIEwAAAA==.',Oo='Oomdh:BAAALAADCggIFAAAAA==.',Pa='Panja:BAABLAAECoEkAAMQAAgIjhdMRAAMAgAQAAgIjhdMRAAMAgAaAAIIAASPqwAzAAAAAA==.Panjaa:BAAALAADCgcIDgAAAA==.Parrupaavali:BAAALAAECgYIDgAAAA==.',Pe='Penny:BAABLAAECoEhAAIdAAgI8Bt9DQCKAgAdAAgI8Bt9DQCKAgAAAA==.',Ph='Pho:BAAALAADCggICAAAAA==.',Pi='Picklock:BAABLAAECoEcAAMUAAgIURdZNQA0AgAUAAgIURdZNQA0AgAXAAUIOQbqHADuAAAAAA==.',Po='Poker:BAAALAAECgYIBgAAAA==.',Pr='Prestigé:BAABLAAECoEiAAQGAAgIixtkHQBrAgAGAAgIsBpkHQBrAgAeAAcI2xbDLgDxAQAHAAEIzR1pKwBSAAAAAA==.Prixy:BAAALAADCggIFQAAAA==.Proxante:BAAALAAECgIIAgAAAA==.Proxus:BAAALAADCggIDAAAAA==.Prutq:BAAALAAECggICAAAAA==.',Qa='Qaeril:BAAALAAECgYIDAABLAAFFAcIHwAQAPQfAA==.',Qo='Qo:BAAALAADCggICAAAAA==.',Ra='Raghunt:BAAALAAECggICAABLAAFFAIIBAAFAAAAAA==.Ranfel:BAACLAAFFIEfAAMQAAcI9B8+AACzAgAQAAcI0x4+AACzAgAaAAYIOyAcAQA2AgAsAAQKgSgAAxoACAhRJuACAFgDABoACAhMJuACAFgDABAABggQI9Q0AEMCAAAA.Ranmash:BAAALAAECggICAABLAAFFAcIHwAQAPQfAA==.',Re='Reina:BAAALAADCgYIAgAAAA==.Rexith:BAAALAAECgQIBAABLAAECgcIHAAJAF0aAA==.',Ro='Rontti:BAAALAAECgUIBQAAAA==.Rooki:BAAALAAECgUIBwAAAA==.Roppmm:BAAALAAFFAIIAgAAAA==.',Ry='Rydrian:BAAALAADCgEIAQAAAA==.',Sa='Sacrae:BAAALAADCgcIDAAAAA==.Saftsusme:BAAALAAECgYIDAAAAA==.Sannimarin:BAAALAAECgEIAQABLAAECgYIBgAFAAAAAA==.Sanniti:BAAALAAECgYIBgAAAA==.Santalokki:BAAALAAECggIEwABLAAFFAYIEQABAJwaAA==.Sarinto:BAAALAADCgcIBwAAAA==.Saskia:BAACLAAFFIEUAAIZAAYI5iAfAABgAgAZAAYI5iAfAABgAgAsAAQKgRoAAxkACAhtIFIFALACABkACAhtIFIFALACABYAAwgEER2PAJUAAAAA.',Se='Seyella:BAAALAADCggIDwABLAAECgUIBwAFAAAAAA==.',Sh='Shinjo:BAABLAAECoEaAAMVAAYIjgwWmwAHAQAVAAYIjgwWmwAHAQAWAAQIBQIBlwB0AAAAAA==.Shynee:BAAALAADCggICgABLAAECgYIBgAFAAAAAA==.',Si='Sillis:BAAALAAECgUICAAAAA==.',Sj='Sjena:BAAALAAECgYICAAAAA==.',Sk='Skorm:BAACLAAFFIEPAAIfAAUI+h8tAAARAgAfAAUI+h8tAAARAgAsAAQKgRYAAh8ACAj4HFsFAF8CAB8ACAj4HFsFAF8CAAEsAAUUBwgUAAIAnyIA.',Sl='Sleepy:BAABLAAECoEUAAIgAAYI9AvNKwAJAQAgAAYI9AvNKwAJAQABLAAFFAMICQAOAKEWAA==.Slerbad:BAABLAAFFIEGAAITAAIIqxxDFQCqAAATAAIIqxxDFQCqAAAAAA==.Slerbaevoker:BAACLAAFFIEGAAIhAAIIlxYSDACnAAAhAAIIlxYSDACnAAAsAAQKgRwAAiEACAgLFbMOABICACEACAgLFbMOABICAAAA.Slerbamonk:BAAALAAFFAIIBAAAAA==.Slerbapriest:BAACLAAFFIEWAAIGAAYIEBIrAwDtAQAGAAYIEBIrAwDtAQAsAAQKgSAAAwYACAjbF0smADECAAYACAjbF0smADECAAcAAQjsAak5ABkAAAAA.',So='Solaro:BAAALAADCgYIBgABLAAECgUIBwAFAAAAAA==.Souw:BAABLAAECoEnAAIPAAgIJRxCEgB0AgAPAAgIJRxCEgB0AgAAAA==.',Sp='Spregnik:BAAALAADCgUIBQAAAA==.',St='Stommz:BAACLAAFFIETAAIDAAYIzB/mAABZAgADAAYIzB/mAABZAgAsAAQKgSIAAgMACAigJhQEAFgDAAMACAigJhQEAFgDAAAA.',Su='Suffdk:BAAALAAECgcIDgABLAAFFAcIFgAbADgYAA==.Suski:BAABLAAECoEWAAMcAAgIlxd7BQBIAgAcAAgIQBZ7BQBIAgAIAAcIxBLkIQDxAQABLAAFFAYIFAAZAOYgAA==.',Te='Tear:BAACLAAFFIEHAAIiAAMIPCBDAQAeAQAiAAMIPCBDAQAeAQAsAAQKgSMAAiIACAh9JKYAAE0DACIACAh9JKYAAE0DAAAA.Terranostra:BAAALAAECggIEAAAAA==.',Th='Thundermaw:BAAALAADCgIIAgAAAA==.',To='Toolzhaman:BAABLAAECoEmAAIVAAgI2R1XFgCmAgAVAAgI2R1XFgCmAgAAAA==.Toolzy:BAAALAAECgcIEAABLAAECggIJgAVANkdAA==.Torsház:BAAALAADCgQIBAAAAA==.Totu:BAAALAADCggIEAAAAA==.',Tu='Tuesdaymplus:BAAALAAFFAIIBAAAAA==.',['Tö']='Törsky:BAAALAAECggICAAAAA==.',Ul='Ultah:BAAALAAECgIICAAAAA==.',Ut='Uther:BAAALAADCggIEAABLAAECgcIEgAFAAAAAA==.',Ve='Vengance:BAABLAAECoEZAAIPAAgIAAhmQQAtAQAPAAgIAAhmQQAtAQAAAA==.',Vi='Vilulettu:BAAALAAECgYIBgAAAA==.Vixxen:BAAALAADCgMIBgAAAA==.',Vr='Vryndar:BAABLAAECoEhAAIJAAgIQyB0BgDgAgAJAAgIQyB0BgDgAgAAAA==.',Wh='Whojin:BAABLAAECoEVAAMWAAgIpwenagA8AQAWAAcIRQanagA8AQAVAAQISgzAywCrAAAAAA==.',Xe='Xerion:BAAALAAECgEIAQAAAA==.Xewe:BAABLAAECoEoAAIDAAgITCK6CQAQAwADAAgITCK6CQAQAwAAAA==.',Xi='Xirev:BAABLAAECoEpAAMBAAgIjSZJCwAuAwABAAgIjSZJCwAuAwAiAAEIFSA5FwBZAAAAAA==.',Xy='Xydru:BAAALAAECgMIAwABLAAECgcIHAAJAF0aAA==.',Za='Zanza:BAABLAAFFIEIAAIjAAIITyarBwDlAAAjAAIITyarBwDlAAABLAAFFAcIFAACAJ8iAA==.Zatinth:BAAALAAECgEIAQABLAAFFAYIFgAjAK4hAA==.',Zo='Zombie:BAABLAAFFIEKAAISAAYIAyVCAACdAgASAAYIAyVCAACdAgAAAA==.',Zu='Zugchoochoo:BAAALAAECgcIBwAAAA==.',['Öö']='Ööke:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end