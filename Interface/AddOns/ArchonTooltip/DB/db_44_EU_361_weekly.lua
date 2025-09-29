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
 local lookup = {'Druid-Balance','DeathKnight-Unholy','Priest-Shadow','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','Warrior-Protection','Warlock-Destruction','Unknown-Unknown','Priest-Holy','Paladin-Retribution','Shaman-Enhancement','Shaman-Restoration','Druid-Guardian','Druid-Restoration','DemonHunter-Vengeance','Mage-Arcane','Paladin-Holy','Monk-Brewmaster','Warlock-Demonology','DeathKnight-Frost','Monk-Mistweaver','Hunter-BeastMastery','Druid-Feral','Mage-Frost','DeathKnight-Blood','Evoker-Preservation','Evoker-Devastation','Paladin-Protection','Monk-Windwalker','Hunter-Marksmanship','Hunter-Survival','Warlock-Affliction','Mage-Fire','Rogue-Subtlety','Shaman-Elemental','Priest-Discipline',}; local provider = {region='EU',realm='ConfrérieduThorium',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ac='Acuité:BAAALAADCgcIBwABLAAFFAIIBgABAJMWAA==.Acuitédr:BAACLAAFFIEGAAIBAAIIkxZREgCbAAABAAIIkxZREgCbAAAsAAQKgS0AAgEACAi5IRAOAN4CAAEACAi5IRAOAN4CAAAA.Acuitésham:BAAALAAECgIIAgABLAAFFAIIBgABAJMWAA==.Acuitévok:BAAALAADCggIBwABLAAFFAIIBgABAJMWAA==.',Ad='Addy:BAAALAADCgcIBwAAAA==.Addîson:BAAALAADCgQIBAAAAA==.Adelheidy:BAAALAADCgYIEAAAAA==.Adhaa:BAAALAAECgUICAAAAA==.Adyria:BAAALAAECgcIDwABLAAECggIHQACAF4aAA==.Adyrlow:BAAALAAECgYIBwABLAAECggIHQACAF4aAA==.Adyrxzt:BAAALAADCgcIBwABLAAECggIHQACAF4aAA==.',Af='Afierte:BAACLAAFFIEIAAIDAAIIKCEuEADEAAADAAIIKCEuEADEAAAsAAQKgRwAAgMACAggGmsaAH8CAAMACAggGmsaAH8CAAAA.Afîerte:BAAALAAECggICAABLAAFFAIICAADACghAA==.',Ag='Agaväen:BAACLAAFFIELAAMEAAUIYRthBgDTAQAEAAUIYRthBgDTAQAFAAEIDAVOBwBBAAAsAAQKgSkAAwQACAiOI74KADUDAAQACAiOI74KADUDAAUABAgUGCMbABUBAAAA.Agrât:BAACLAAFFIEHAAIGAAUIbhCsCQCMAQAGAAUIbhCsCQCMAQAsAAQKgSsAAgYACAjFJF8JAEYDAAYACAjFJF8JAEYDAAAA.',Ai='Airénshùshi:BAAALAADCggIDwAAAA==.',Ak='Akarui:BAAALAADCgUIBwAAAA==.Akhileusdh:BAABLAAECoEYAAIGAAcIkRsLWwDlAQAGAAcIkRsLWwDlAQAAAA==.Akiru:BAABLAAECoEfAAIHAAgImxgGGAA8AgAHAAgImxgGGAA8AgAAAA==.Akêno:BAAALAAFFAIIAgABLAAFFAcIHgAIAO4iAA==.',Al='Alariel:BAAALAADCgYICQAAAA==.Albereth:BAAALAAECgYIDgAAAA==.Alcyon:BAAALAADCggICAAAAA==.Allarya:BAAALAADCgcIDQABLAAECgYIBgAJAAAAAA==.Allwhitte:BAABLAAECoEXAAMKAAYIqxL5TgBzAQAKAAYIqxL5TgBzAQADAAQIngO3cACaAAAAAA==.Allya:BAAALAADCggIDwABLAAECggIIgALANAeAA==.Allëssä:BAAALAAECgIIAgAAAA==.Almana:BAAALAADCggIDwABLAADCggIEwAJAAAAAA==.Altrius:BAAALAADCgIIAgAAAA==.Altriuss:BAAALAADCggIDwAAAA==.Aly:BAAALAAECgQIBgAAAA==.Alîssa:BAAALAAECggICAABLAAFFAIICAADACghAA==.Alïcïa:BAAALAAECgYIDAAAAA==.',Am='Amaliaa:BAABLAAECoEYAAIMAAcI1wi2FABuAQAMAAcI1wi2FABuAQAAAA==.Amandrà:BAAALAAECggIEAAAAA==.Amphorea:BAAALAADCgcIDQAAAA==.',An='Anajinn:BAAALAAECgYIBgAAAA==.Anasdahala:BAAALAAECgYIDwAAAA==.Anübys:BAAALAAECgcIBgAAAA==.',Aq='Aquos:BAAALAAECgYICAAAAA==.',Ar='Arcandria:BAAALAAECgMIBwAAAA==.Areni:BAAALAADCgYIBgAAAA==.Ariié:BAABLAAECoEXAAINAAcIlhLoaAB8AQANAAcIlhLoaAB8AQAAAA==.Armadyl:BAAALAAECgcICgAAAA==.Arrowfstørms:BAABLAAECoEWAAINAAcI7CMlEgDBAgANAAcI7CMlEgDBAgAAAA==.Artemystel:BAAALAADCggIHAABLAAECgQICQAJAAAAAA==.Arthia:BAACLAAFFIEQAAIOAAUIVB5SAADtAQAOAAUIVB5SAADtAQAsAAQKgS8AAg4ACAj0JYMAAH4DAA4ACAj0JYMAAH4DAAAA.Arîa:BAAALAADCggIEwAAAA==.',As='Asherah:BAABLAAECoEdAAILAAcIngvAmACIAQALAAcIngvAmACIAQAAAA==.Ashiki:BAAALAADCggICAABLAAECgcIGQAPAJARAA==.Ashuwo:BAAALAADCgYIBgAAAA==.Asmo:BAABLAAECoEUAAIQAAcI0hkdFQDwAQAQAAcI0hkdFQDwAQAAAA==.Astamage:BAABLAAECoEaAAIRAAcIRx4IOgA/AgARAAcIRx4IOgA/AgABLAAECgYIFAALAN8jAA==.Asthadk:BAAALAADCggICAABLAAECgYIFAALAN8jAA==.Astharoths:BAABLAAECoEUAAILAAYI3yNXNwBqAgALAAYI3yNXNwBqAgAAAA==.Astrome:BAACLAAFFIENAAILAAQIihSPCABOAQALAAQIihSPCABOAQAsAAQKgS4AAgsACAiqJUkHAFwDAAsACAiqJUkHAFwDAAAA.',At='Athanora:BAAALAAECgMIBgAAAA==.Athrelya:BAAALAADCggIFAAAAA==.Atronos:BAAALAAECgYIDQAAAA==.',Au='Auraure:BAAALAADCggIDwABLAAECgcIGAASAJgaAA==.',Av='Avalanches:BAAALAADCgMIBQAAAA==.',Ay='Ayae:BAAALAAECgIIAgAAAA==.',Az='Azersdf:BAAALAADCgUIBQAAAA==.Azkyn:BAABLAAECoEbAAITAAcIbRNiGgCaAQATAAcIbRNiGgCaAQAAAA==.Azranail:BAAALAADCggICAAAAA==.',['Aê']='Aêly:BAAALAADCgcIBwAAAA==.',['Aë']='Aëlwynn:BAAALAADCggICwAAAA==.',Ba='Bahàmut:BAAALAADCggIDgABLAAECgYIFAALAN8jAA==.Balarane:BAAALAAECggIEgAAAA==.Balash:BAAALAAECgYIDwAAAA==.Balbî:BAAALAADCgQIBAAAAA==.Balgamor:BAAALAADCggICAAAAA==.Balthamus:BAAALAADCgUICgAAAA==.Barth:BAABLAAECoEkAAIUAAgIGh1UCQCzAgAUAAgIGh1UCQCzAgAAAA==.Bartholomew:BAAALAAECgYIBgABLAAECggIJAAUABodAA==.Bawlt:BAAALAAECgMIBwABLAAECgcIGwAPABsjAA==.Bawltimor:BAABLAAECoEbAAIPAAcIGyM4EACzAgAPAAcIGyM4EACzAgAAAA==.',Be='Beber:BAAALAAECgYIDAAAAA==.Becarus:BAAALAADCgcIDgAAAA==.Beelzesam:BAAALAADCgEIAQAAAA==.Beenøuz:BAABLAAECoEXAAIVAAYIAggt2gAhAQAVAAYIAggt2gAhAQAAAA==.Berethore:BAAALAADCgQICAAAAA==.',Bl='Blancoau:BAAALAAECgcIEwAAAA==.Blankette:BAAALAAECgYIBwAAAA==.Blennorrhas:BAAALAADCgcIBwAAAA==.Blëssed:BAAALAAECgQIBgAAAA==.',Bo='Boralex:BAABLAAECoEYAAIWAAcIeBHKHgCBAQAWAAcIeBHKHgCBAQAAAA==.Borval:BAAALAADCgMIAwAAAA==.Bouddhé:BAAALAADCggICAAAAA==.',Br='Brasylax:BAAALAADCggIHQAAAA==.Breedühr:BAAALAADCgUIBQAAAA==.Brezan:BAAALAADCgUIAgAAAA==.Broqu:BAABLAAECoEcAAIXAAgIkBo0MQBRAgAXAAgIkBo0MQBRAgAAAA==.Brumeurr:BAAALAADCggIEAAAAA==.',Bu='Bulasturu:BAABLAAECoEhAAIFAAgI7iE3AgAfAwAFAAgI7iE3AgAfAwAAAA==.Buliwif:BAAALAADCgYICQAAAA==.',Bw='Bwayan:BAAALAADCgEIAQAAAA==.',['Bé']='Bénédictiøn:BAAALAADCgMIAwAAAA==.',Ca='Calize:BAAALAAECgYICwAAAA==.',Ce='Cerbére:BAAALAADCggICAAAAA==.',Ch='Chagou:BAAALAAECgcIDwAAAA==.Chamilia:BAAALAAECgYICwAAAA==.Chaminny:BAAALAAECgYIEwAAAA==.Chandefleuve:BAAALAAECgYICgAAAA==.Charlîe:BAABLAAECoEXAAIXAAcIthkOTAD1AQAXAAcIthkOTAD1AQAAAA==.Chassequipeu:BAAALAAECgQIBAAAAA==.Chlouf:BAAALAADCggIHgAAAA==.Chöwper:BAAALAAECgcIDAAAAA==.',Co='Cobrat:BAAALAAECgUIBQAAAA==.Colmart:BAAALAAECgUIBQAAAA==.Complaìnte:BAAALAAECgcIEwAAAA==.Convoitise:BAAALAADCgYIBgABLAAECggIFwAYAOsdAA==.Coobrat:BAAALAADCggIDgABLAAECgUIBQAJAAAAAA==.Corru:BAAALAADCgEIAQAAAA==.',Cr='Cranenpodku:BAAALAADCgcIBwABLAAECgcIEQAJAAAAAA==.Cranhanpodku:BAAALAAECgcIEQAAAA==.Craseux:BAAALAAECgYIDwAAAA==.Crimewaves:BAAALAAECgYIEQAAAA==.',Cy='Cyraei:BAAALAADCggIFAAAAA==.',['Cà']='Càpriseum:BAAALAAECggIEAAAAA==.',['Cä']='Cässou:BAAALAAECgEIAQAAAA==.',Da='Damexia:BAAALAAECgMIBAAAAA==.Dananshee:BAAALAADCgcICAAAAA==.',De='De:BAAALAAECgYICwABLAAFFAIICAAZAG0jAA==.Deme:BAABLAAECoEVAAILAAcIYxJqggCyAQALAAcIYxJqggCyAQAAAA==.Demiecorne:BAAALAADCggIDwAAAA==.Den:BAABLAAECoEbAAMaAAcIHyS0BgDZAgAaAAcIHyS0BgDZAgACAAEIXhHuTgBJAAAAAA==.Deshamhar:BAAALAAECgcIDQAAAA==.Deuxdeqi:BAAALAADCgcIBwAAAA==.',Dh='Dhürak:BAAALAAECgMIAwAAAA==.',Di='Difole:BAABLAAECoEYAAIEAAgIeQ3YSwDRAQAEAAgIeQ3YSwDRAQAAAA==.Dipio:BAAALAADCggIFAAAAA==.Discretion:BAAALAAFFAYIAwAAAA==.Diter:BAAALAAECgYICgAAAA==.Diurza:BAAALAAECgcIEQAAAA==.',Dk='Dkgnöme:BAAALAADCggICAAAAA==.Dkzorg:BAAALAADCgUIAwAAAA==.',Do='Dorsator:BAAALAAECggICwAAAA==.Doublec:BAAALAADCggIDgAAAA==.',Dr='Drachktar:BAAALAADCggIDwAAAA==.Drakedög:BAAALAAECgcIEgABLAAFFAYIFgAXAIYhAA==.Dralingea:BAAALAAECgYICwAAAA==.Dranom:BAAALAADCggICgAAAA==.Drazhoath:BAAALAAECgcIEQAAAA==.Dreddpër:BAAALAAECgUIBQABLAAECgcIDAAJAAAAAA==.Dreïh:BAAALAADCgIIAgAAAA==.Droudix:BAAALAAECgUIAgAAAA==.Drunkfox:BAABLAAECoEgAAIIAAgIygiJYgCRAQAIAAgIygiJYgCRAQAAAA==.Dryknight:BAABLAAECoEdAAIVAAcIARkMXAAJAgAVAAcIARkMXAAJAgAAAA==.Drëa:BAAALAADCggICAAAAA==.Drøpsy:BAABLAAECoEhAAMPAAgInQ3EUQBfAQAPAAgInQ3EUQBfAQABAAcIHwvdRwBbAQAAAA==.',['Dø']='Dønsham:BAAALAAECgMIBAAAAA==.',Ea='Easywind:BAAALAAECgYICwAAAA==.',Ef='Efreetul:BAABLAAECoEYAAISAAcImBoRFQA7AgASAAcImBoRFQA7AgAAAA==.',Eh='Ehma:BAAALAADCgQIBAAAAA==.',El='Elfybloody:BAAALAADCggICAAAAA==.Elletank:BAABLAAECoEXAAIEAAcIWxUiTQDNAQAEAAcIWxUiTQDNAQAAAA==.Elnarian:BAAALAAECgIIAgAAAA==.Elone:BAAALAADCggICwAAAA==.Elpatron:BAAALAADCgMIAwAAAA==.Eltesya:BAAALAADCgYIBgABLAAECggIJwAPAEkcAA==.Elysera:BAABLAAECoEXAAMbAAcIXw8sGQB4AQAbAAcIXw8sGQB4AQAcAAUI1gaJRwDSAAAAAA==.Elíae:BAABLAAECoEeAAIMAAcIiCGeBgCKAgAMAAcIiCGeBgCKAgAAAA==.',Em='Emeràld:BAAALAAECgQICAAAAA==.Emorya:BAAALAADCgYIBgAAAA==.',En='Enëtary:BAAALAADCggICAAAAA==.',Er='Eraëldy:BAABLAAECoEbAAMdAAcIXiKdCwCQAgAdAAcIXiKdCwCQAgALAAII2Aj5KQFOAAAAAA==.Erodan:BAAALAADCggICAAAAA==.Erzza:BAABLAAECoEjAAINAAgIWR/uEgC8AgANAAgIWR/uEgC8AgAAAA==.',Es='Escalop:BAABLAAECoEZAAIeAAgIRQzcMABNAQAeAAgIRQzcMABNAQAAAA==.Eschatologue:BAAALAAECgYIEgAAAA==.Esthete:BAABLAAECoEaAAIZAAgIMA9JJADXAQAZAAgIMA9JJADXAQAAAA==.',Et='Ettervel:BAAALAAECgYIBgAAAA==.',Ev='Evazur:BAAALAADCgEIAQAAAA==.Evollya:BAAALAADCgMIAwAAAA==.Evolock:BAAALAAECggIEQAAAA==.',['Eï']='Eïir:BAAALAAECgMIAwAAAA==.',Fa='Faràs:BAAALAAECgYIBwAAAA==.',Fe='Fendarion:BAAALAADCggICAAAAA==.',Fi='Filomene:BAAALAADCgcIDgAAAA==.Finsaë:BAABLAAECoEXAAIKAAYITwjcbQAJAQAKAAYITwjcbQAJAQAAAA==.',Fl='Flac:BAAALAADCgcIBwAAAA==.Flynnee:BAAALAAECgEIAQAAAA==.',Fr='Fragaria:BAAALAAECgIIBAAAAA==.Fredale:BAABLAAECoEZAAIGAAcItRfNUwD5AQAGAAcItRfNUwD5AQAAAA==.Frêëze:BAAALAAECggICgAAAA==.',Fu='Fufuloh:BAAALAAECggICAABLAAECggIFwAYAOsdAA==.Fulohdh:BAAALAAECggIDwABLAAECggIFwAYAOsdAA==.Fulohunt:BAAALAAECggIEAABLAAECggIFwAYAOsdAA==.',['Fâ']='Fâwn:BAAALAAECgIIAgAAAA==.Fââyyaa:BAAALAADCgUIBQAAAA==.',['Fé']='Félhun:BAAALAADCggIEAAAAA==.Féllyne:BAAALAAECggICAAAAA==.',['Fø']='Føùføù:BAAALAAECgYIDAAAAA==.Føüfou:BAAALAADCgIIAgAAAA==.',Ga='Galorus:BAAALAAECgYIDQAAAA==.',Gi='Gianoli:BAAALAADCgQICgAAAA==.',Go='Goathrokk:BAABLAAECoEcAAIXAAcIwCRFGQDJAgAXAAcIwCRFGQDJAgAAAA==.Golderä:BAAALAADCgEIAQAAAA==.Gorodrim:BAAALAADCggIDQAAAA==.Gotei:BAAALAAECgQIBAAAAA==.Gourmandïse:BAABLAAECoEXAAIYAAgI6x0sBgDhAgAYAAgI6x0sBgDhAgAAAA==.',Gr='Grabtar:BAAALAAECgIIAwAAAA==.Gradzia:BAAALAAECgYIDQAAAA==.Grenn:BAAALAAECgYIEgAAAA==.Greyson:BAAALAAECgYIBgAAAA==.Grita:BAAALAAECgEIAQAAAA==.Groaar:BAAALAADCgUIBgAAAA==.Grumir:BAAALAADCgcIBwAAAA==.',Gu='Gulrosh:BAAALAADCgYIBgAAAA==.Gurzraki:BAAALAAECgIIBAAAAA==.',['Gó']='Góld:BAAALAAECgMIAwAAAA==.',['Gõ']='Gõrtke:BAAALAADCggICAAAAA==.',['Gö']='Göld:BAACLAAFFIEWAAMXAAYIhiE7BgCwAQAfAAUINxxABAC2AQAXAAUIKRw7BgCwAQAsAAQKgSgAAx8ACAjDJcoIABYDAB8ACAiII8oIABYDABcABQiKJHtaAM0BAAAA.',['Gø']='Gøuken:BAAALAADCgcICAAAAA==.',['Gù']='Gùnnar:BAAALAADCggICAABLAAECggIIgALANAeAA==.',Ha='Hafthør:BAAALAAECgcIBwAAAA==.Hagrîd:BAAALAADCgYICQAAAA==.Hastings:BAAALAAECgEIAQAAAA==.Hayre:BAAALAADCggICAAAAA==.',He='Hearty:BAAALAADCggICgAAAA==.Hemyc:BAAALAAECgUICwAAAA==.Herah:BAAALAADCggICAAAAA==.Hermos:BAAALAADCgcIBwAAAA==.',Hi='Hironeiden:BAAALAAECgYIEQAAAA==.',Ho='Hopale:BAAALAADCggIDwAAAA==.Hoshiyo:BAAALAAECgEIAQAAAA==.Houblonnix:BAAALAADCgEIAQAAAA==.',Hu='Hudren:BAAALAADCgIIAgAAAA==.',Hy='Hyles:BAAALAAECgQIBAAAAA==.',['Hø']='Hølycøw:BAAALAAECgEIAQAAAA==.Hørriblette:BAAALAAECgYIDwAAAA==.',Ic='Icallianna:BAAALAADCggICwAAAA==.Icekiss:BAAALAADCgUIBQAAAA==.Icàriam:BAABLAAECoEhAAQXAAgIqyFdEwDsAgAXAAgIqyFdEwDsAgAgAAIIhhTMGQCPAAAfAAIINxtJiQCOAAAAAA==.',Il='Illuminäety:BAAALAAECgcIEgAAAA==.Illïad:BAAALAAECgYIDgAAAA==.',Im='Imarlia:BAAALAAECgIIAgAAAA==.',In='Inarï:BAAALAAECgIIAgAAAA==.',Ip='Ipsi:BAAALAADCgUIBQAAAA==.',Ir='Iridiensse:BAAALAAECgYIDAAAAA==.Irøq:BAAALAADCgcIBwAAAA==.',Is='Ispirane:BAAALAADCgMIAwAAAA==.',Iv='Ivalys:BAAALAAECgYICQAAAA==.',Iw='Iwasan:BAAALAAECgQIBAAAAA==.Iwashan:BAAALAADCgcIBwAAAA==.',Ji='Jiahynn:BAAALAADCgYIBgAAAA==.Jieldã:BAAALAADCgIIAgAAAA==.Jinwoo:BAAALAAECgcIDgABLAAFFAcIHgAIAO4iAA==.Jinwøø:BAACLAAFFIEeAAMIAAcI7iKOAADjAgAIAAcI7iKOAADjAgAUAAEItR1gHABWAAAsAAQKgSEAAwgACAgJJvIHAEgDAAgACAgJJvIHAEgDACEAAQiRIAQwAF8AAAAA.',Ka='Kaladjin:BAAALAAECgYICgAAAA==.Kallÿ:BAAALAAECgEIAQAAAA==.Kalyloup:BAAALAAECgIIAgABLAAECgcIGgALAIoeAA==.Kalyzx:BAAALAAECgYIEgABLAAECgcIGgALAIoeAA==.Karm:BAAALAADCgcIEAAAAA==.Karsham:BAAALAAECgYIEgAAAA==.Kaîzen:BAAALAADCggIFQAAAA==.Kaïzen:BAAALAAECgIIAgAAAA==.',Ke='Ketheru:BAAALAAECgQIBQAAAA==.',Kh='Khaljin:BAAALAADCgQIBAAAAA==.Khardgin:BAAALAAECgYICAABLAAECgYIDwAJAAAAAA==.',Ki='Kihrin:BAAALAAECgUICgAAAA==.Kirjava:BAAALAAECgYIBAABLAAECgYIDwAJAAAAAA==.Kiro:BAAALAAECgYIDgAAAA==.Kirothius:BAAALAADCgcIEwAAAA==.',Kl='Klaatu:BAAALAADCggIFwAAAA==.Klåus:BAAALAAECgIIBAAAAA==.',Ko='Koa:BAAALAAECgMIAwAAAA==.Kohor:BAAALAADCgQIBAAAAA==.Koniak:BAAALAAECgYIDQAAAA==.Kormgor:BAAALAAECgUICwAAAA==.',Kr='Kreustian:BAAALAAECgYICgAAAA==.',Ku='Kudix:BAAALAAECgYIDwAAAA==.Kumania:BAAALAADCggIFQAAAA==.Kurrama:BAAALAAECgcIEgAAAA==.Kushiel:BAAALAADCggIDgAAAA==.',Kw='Kwicky:BAABLAAECoEbAAIEAAcIIhiiQAD6AQAEAAcIIhiiQAD6AQAAAA==.',Ky='Kylana:BAAALAADCgcIBwAAAA==.Kyodh:BAAALAAFFAIIAgABLAAFFAcIHgAIAO4iAA==.Kyodruid:BAAALAAECggIDgABLAAFFAcIHgAIAO4iAA==.Kysail:BAAALAAECgMIDAAAAA==.Kysoke:BAABLAAECoEiAAIBAAgImCFsDADwAgABAAgImCFsDADwAgAAAA==.Kysumi:BAAALAAECgIIAgAAAA==.',['Kä']='Käemy:BAAALAADCggICAAAAA==.',La='Laharasj:BAAALAADCggIDwAAAA==.Lamadar:BAAALAADCgcICwAAAA==.Lasagna:BAAALAAECgYIDAAAAA==.',Le='Leblanco:BAAALAADCgIIAgAAAA==.Lecter:BAAALAAECgYIDwAAAA==.Letitgo:BAACLAAFFIEJAAMZAAMIViBWAgAoAQAZAAMIViBWAgAoAQARAAEIzQcmTwA+AAAsAAQKgSwABBkACAjEJfIBAGwDABkACAjEJfIBAGwDACIAAQglGCAZAEkAABEAAQhTF6TUAEcAAAAA.Leysj:BAAALAADCggICAABLAADCggIDwAJAAAAAA==.',Lh='Lhanzu:BAAALAADCgYIBgAAAA==.',Li='Lianzo:BAAALAADCgcIBwAAAA==.Liliana:BAAALAAECgQIBAAAAA==.Lililarousse:BAAALAAECgYICgAAAA==.Linoas:BAAALAAECgEIAQAAAA==.Linreeya:BAABLAAECoEeAAIdAAcIpSF+CgCjAgAdAAcIpSF+CgCjAgAAAA==.Linyë:BAAALAAECgMIAwAAAA==.Liriel:BAAALAADCggIDwAAAA==.',Lo='Lolatora:BAAALAAECgYIEQAAAA==.',Lu='Luccifher:BAAALAADCgMIAwAAAA==.Lucifera:BAAALAAECgEIAQAAAA==.Luhk:BAAALAADCgcICQAAAA==.Lunaewen:BAAALAAECgYIEQAAAA==.Lunea:BAAALAAECgIIAgAAAA==.Lunëa:BAAALAAECgYICgAAAA==.',Ly='Lyara:BAAALAAECgIICAAAAA==.Lysapriest:BAACLAAFFIELAAIKAAMI4iS+EQDcAAAKAAMI4iS+EQDcAAAsAAQKgRoAAgoACAhHJUkDAFUDAAoACAhHJUkDAFUDAAEsAAUUBwgUAAoA4RoA.',['Lé']='Léynia:BAABLAAECoEVAAILAAgIShH8bQDaAQALAAgIShH8bQDaAQAAAA==.',['Lë']='Lëtharion:BAAALAAECgYIBgAAAA==.',['Lí']='Línoù:BAAALAADCgcIBwAAAA==.',['Lî']='Lîlith:BAAALAAECgIIAgAAAA==.',['Lï']='Lïlîth:BAAALAADCggICAAAAA==.',['Lø']='Lønfor:BAAALAAECgYICgAAAA==.',['Lü']='Lümpa:BAAALAADCgYIBwAAAA==.',Ma='Magdi:BAAALAADCggICAAAAA==.Mahbit:BAABLAAECoEXAAIfAAcI4Br/LQD1AQAfAAcI4Br/LQD1AQAAAA==.Malith:BAAALAADCgMIAwAAAA==.Maltack:BAAALAAECgcIDwAAAA==.Maléfika:BAAALAADCgQIBAAAAA==.Mamena:BAAALAADCgUIBAAAAA==.Manabu:BAABLAAECoEUAAIeAAgIXxXCGwDzAQAeAAgIXxXCGwDzAQAAAA==.Manatiomé:BAAALAADCgcICgAAAA==.Manekalma:BAABLAAECoEcAAMEAAgIVhx6JQB7AgAEAAgIUBt6JQB7AgAHAAYIWBdWLgCVAQAAAA==.Mariecurly:BAAALAADCgYIBgABLAAECgcIEQAJAAAAAA==.Massella:BAABLAAECoEWAAIPAAgIuxxeEwCZAgAPAAgIuxxeEwCZAgAAAA==.Matine:BAABLAAECoEdAAIKAAcIJxASRwCSAQAKAAcIJxASRwCSAQAAAA==.Maugraîne:BAAALAAECgQICAAAAA==.Maulie:BAAALAAECgYIDAAAAA==.Maybel:BAAALAAECgYIDwAAAA==.Mayü:BAABLAAECoEXAAIKAAgIUADSkwBoAAAKAAgIUADSkwBoAAAAAA==.Maë:BAAALAAECgIIAwAAAA==.Maëz:BAAALAADCggICAAAAA==.',Me='Meetoo:BAAALAADCgUIBQABLAAECgcIGwAPABsjAA==.Meoleo:BAAALAAECgMIAwAAAA==.Merewen:BAABLAAECoETAAIZAAgIsgpZLwCWAQAZAAgIsgpZLwCWAQAAAA==.Merveilles:BAABLAAECoEVAAIXAAYIigdhtQALAQAXAAYIigdhtQALAQAAAA==.Mexxa:BAAALAAECgMIAwAAAA==.',Mh='Mhogéras:BAAALAAECggIEAAAAA==.Mhorphéus:BAAALAADCggIEAAAAA==.',Mi='Miaoumiaou:BAAALAAECgIIAgABLAAFFAYIAwAJAAAAAA==.Mistalova:BAAALAAECggICAABLAAFFAYIFgAXAIYhAA==.Mitsukiia:BAAALAAECgYIEgAAAA==.',Mo='Moiranne:BAAALAAECgYIDAAAAA==.Molosse:BAAALAADCggICAAAAA==.Morgonn:BAAALAAECgEIAgAAAA==.Mortels:BAAALAADCgIIBgAAAA==.',Mu='Multypass:BAAALAADCgcIBwAAAA==.',['Mæ']='Mælice:BAAALAADCggIEwABLAADCggIEwAJAAAAAA==.',['Mé']='Ménalas:BAAALAAECgYIDAAAAA==.',['Mï']='Mïnerve:BAAALAADCgcIDQAAAA==.',['Mö']='Mömötte:BAAALAADCgQIBAAAAA==.',['Mø']='Møkatea:BAAALAAECgYIDAAAAA==.Møkati:BAAALAAECgYICQABLAAECgYIDAAJAAAAAA==.',Na='Nagenda:BAAALAADCggICAABLAAECgcIHwAZACgjAA==.Naliana:BAAALAAECgEIAQAAAA==.Nalrot:BAAALAAECgYIEQAAAA==.Nancho:BAAALAADCgUIBQAAAA==.Nargrim:BAAALAADCgcIGAAAAA==.Nashala:BAAALAADCggICAAAAA==.Naveis:BAABLAAECoEgAAIcAAgIvxsTFQBlAgAcAAgIvxsTFQBlAgAAAA==.Nawopal:BAABLAAECoEWAAMdAAYIfhh5KQBvAQALAAYIyhWvlQCNAQAdAAYIABh5KQBvAQABLAAFFAIIBQABALQWAA==.Nayram:BAACLAAFFIEGAAIIAAIIcCVDHADXAAAIAAIIcCVDHADXAAAsAAQKgSUAAggACAhWJaYTAPUCAAgACAhWJaYTAPUCAAAA.Naÿram:BAAALAAFFAIIAgABLAAFFAIIBgAIAHAlAA==.',Ne='Neilammar:BAAALAADCgUIBQAAAA==.Neyliel:BAAALAADCggICQAAAA==.',Ni='Niackette:BAAALAADCggICwAAAA==.Niamorcm:BAAALAADCgcICAAAAA==.Ninougat:BAAALAADCggIFQAAAA==.Nisskorn:BAABLAAECoEYAAINAAgIwAiXmgAIAQANAAgIwAiXmgAIAQAAAA==.',No='Noirpresage:BAAALAAECgYIBgAAAA==.Noklë:BAABLAAECoEnAAIPAAgISRygFgB+AgAPAAgISRygFgB+AgAAAA==.Nonobbzh:BAAALAAECgYIEQAAAA==.',Nu='Nukâ:BAAALAAECgUIBgAAAA==.',Ny='Nykypala:BAAALAAECgcIDQAAAA==.',['Ná']='Náte:BAAALAAFFAIIAgABLAAFFAIIBQABALQWAA==.Náteh:BAAALAADCggICAABLAAFFAIIBQABALQWAA==.Nátte:BAAALAADCggIFgABLAAFFAIIBQABALQWAA==.',['Né']='Néphilim:BAAALAADCggICAAAAA==.',['Në']='Nëphthÿs:BAAALAAECgcIDgAAAA==.',['Nø']='Nøok:BAAALAAECgQIBAAAAA==.',Og='Ogmatar:BAAALAADCgUIBQAAAA==.',Ok='Oku:BAAALAADCggIDAAAAA==.',Ol='Olkerdys:BAAALAADCggICAAAAA==.',Op='Oppalinette:BAAALAADCggICAABLAAECgYIDwAJAAAAAA==.Oppalïa:BAAALAAECgYIDwAAAA==.',Or='Oranis:BAABLAAECoEXAAIXAAcIUg9BfgB6AQAXAAcIUg9BfgB6AQAAAA==.Orenyshi:BAAALAADCgQIBAAAAA==.Orhan:BAAALAAECgQIBAABLAAECgQICAAJAAAAAA==.Orkann:BAAALAAECgcIEwAAAA==.Orphelia:BAAALAAECgYIDQAAAA==.Orvaal:BAAALAADCgIIAgAAAA==.Orvahal:BAAALAADCggICAAAAA==.',Os='Oscarnak:BAAALAAECgYICgAAAA==.',Ou='Oupsïtv:BAABLAAFFIEKAAINAAMIDRdGDwDkAAANAAMIDRdGDwDkAAAAAA==.',Ow='Oweed:BAAALAAECgEIAQAAAA==.',['Oï']='Oïron:BAAALAAECgYIDgAAAA==.',Pa='Padar:BAAALAAECgYIDwAAAA==.Palamiya:BAAALAAECgQIBAABLAAECgQICAAJAAAAAA==.Pamik:BAAALAADCggICAAAAA==.Pansepignon:BAAALAADCgYIEAAAAA==.Paperheal:BAABLAAECoEZAAINAAgIZBpgIwBgAgANAAgIZBpgIwBgAgAAAA==.Papÿ:BAABLAAECoEUAAIKAAcIIgymVQBaAQAKAAcIIgymVQBaAQAAAA==.Pariàh:BAAALAAECgYIEgAAAA==.',Pe='Pewnáte:BAACLAAFFIEFAAIBAAIItBYvEQCfAAABAAIItBYvEQCfAAAsAAQKgSMAAwEACAgtHL0aAFwCAAEACAgtHL0aAFwCAA8ABghrESRbAD8BAAAA.Peyo:BAAALAAECggIGwAAAQ==.',Ph='Phoènix:BAABLAAECoEXAAIMAAYIUx0kDgDdAQAMAAYIUx0kDgDdAQAAAA==.Phèdres:BAABLAAECoEVAAIZAAYItwUVUAD6AAAZAAYItwUVUAD6AAAAAA==.',Pi='Piwinator:BAAALAADCggICAAAAA==.',Pl='Playmobhêal:BAAALAADCgIIBAAAAA==.Plezal:BAAALAADCgMIAwAAAA==.',Po='Polosis:BAAALAADCgMIAwABLAAECgYIDAAJAAAAAA==.',Pr='Prismatica:BAABLAAECoEUAAMLAAcIEQ9JiQCkAQALAAcIEQ9JiQCkAQASAAUIjAmHSgDiAAAAAA==.',Ps='Psychô:BAAALAAECgUICwAAAA==.',Pu='Putrasse:BAAALAAECgYIDAABLAAFFAMICQAZAFYgAA==.Putrius:BAAALAAECgQIBQAAAA==.',Py='Pyotrr:BAAALAADCgcIBwAAAA==.',['Pé']='Pércée:BAAALAADCgcIBQAAAA==.',['Pí']='Píwa:BAAALAAECgMIBQAAAA==.',['Pø']='Pøli:BAAALAAECgEIAQAAAA==.',Ra='Raenag:BAAALAADCgEIAQAAAA==.Rahan:BAAALAAECgcIEgAAAA==.Rallena:BAABLAAECoEXAAIGAAgIzx9jHQDPAgAGAAgIzx9jHQDPAgAAAA==.Ramonetou:BAAALAADCgYIDQAAAA==.Raniack:BAAALAADCggICAAAAA==.Razanon:BAABLAAECoEYAAIjAAgIrBZ6DQA0AgAjAAgIrBZ6DQA0AgAAAA==.Razgriz:BAABLAAECoEVAAIMAAcIiR0ICABhAgAMAAcIiR0ICABhAgAAAA==.Razurios:BAAALAAECgYIBwAAAA==.Razâkh:BAAALAADCgQIBAAAAA==.',Re='Redwa:BAAALAAECgUIBgABLAAECgcIGQALANUjAA==.Redwh:BAABLAAECoEZAAMLAAcI1SOZIgDDAgALAAcI1SOZIgDDAgAdAAIIGBroVQBRAAAAAA==.Rentao:BAAALAAECgYIEQABLAAECgcIGAASAJgaAA==.Rezles:BAAALAADCggICAAAAA==.Rezvie:BAAALAADCgYIBgAAAA==.Reînhär:BAAALAADCgEIAQAAAA==.',Rh='Rhazör:BAAALAADCggIDQAAAA==.',Ro='Robindéboite:BAAALAAECgcIEQAAAA==.',['Rä']='Rägnart:BAAALAAECgYIBgABLAAFFAQIDQALAIoUAA==.Rägnärok:BAAALAAECgcIEwAAAA==.',['Ré']='Rémî:BAAALAADCgEIAQAAAA==.Rémï:BAABLAAECoEVAAIDAAYIjAk4VwAsAQADAAYIjAk4VwAsAQAAAA==.',Sa='Sabbath:BAAALAAECgYICwAAAA==.Saewelune:BAAALAADCgYIEAAAAA==.Saious:BAEALAAECgIIBAAAAA==.Salsifï:BAAALAADCgYIBgABLAAECgcIEQAJAAAAAA==.Sangofvoleur:BAAALAAECggIEAAAAA==.Sangtelle:BAAALAAECgYICwAAAA==.Santoline:BAABLAAECoEXAAIPAAcI9xmMJwAXAgAPAAcI9xmMJwAXAgAAAA==.Sardyne:BAAALAADCgcIBwAAAA==.Sarfest:BAAALAAECgMIAwAAAA==.Saskuacht:BAAALAADCggICAAAAA==.',Sc='Scindios:BAAALAAECgEIAQAAAA==.',Se='Seditmonk:BAAALAAECgUIBgAAAA==.Segojan:BAABLAAECoEXAAIkAAcIFQhrYQBcAQAkAAcIFQhrYQBcAQAAAA==.Seir:BAABLAAECoEbAAIXAAcI+BfcTgDtAQAXAAcI+BfcTgDtAQAAAA==.Selyna:BAAALAAECgIIAwAAAA==.Serenity:BAAALAAECgIIAgAAAA==.Setsunà:BAABLAAECoEVAAINAAcITBbdTQDHAQANAAcITBbdTQDHAQAAAA==.Severina:BAAALAAECgIIAgABLAAECgcIGAASAJgaAA==.Seyrarm:BAAALAADCggICAAAAA==.',Sh='Shankhill:BAAALAADCgYICAABLAAECgIIBAAJAAAAAA==.Shaÿn:BAAALAADCggICQAAAA==.Shemz:BAACLAAFFIEMAAINAAUIsh17AwDSAQANAAUIsh17AwDSAQAsAAQKgSUAAw0ACAhsHe8kAFkCAA0ACAhsHe8kAFkCACQABwixGOI6AOsBAAAA.Shenlee:BAAALAADCgMIAwABLAADCggICAAJAAAAAA==.Shira:BAAALAAFFAIIAgAAAA==.Shungate:BAACLAAFFIEGAAINAAII3BE4LACBAAANAAII3BE4LACBAAAsAAQKgScAAw0ACAidH5gYAJgCAA0ACAidH5gYAJgCACQABQjREGJzABsBAAAA.Shuryo:BAAALAAECgMIBQAAAA==.Shêld:BAAALAADCgcIBwAAAA==.Shïnai:BAAALAAECgQIBAAAAA==.',Si='Siiria:BAAALAADCgUIBQABLAADCggIFAAJAAAAAA==.Sip:BAAALAADCgUIBQAAAA==.Siuky:BAAALAADCggICAAAAA==.',Sm='Smookie:BAAALAAECgMICQABLAAECgcIFgANAFIUAA==.',So='Solyuid:BAAALAAECgYIBgAAAA==.Solÿn:BAAALAADCgYIEAAAAA==.Sorbed:BAAALAADCgIIAgAAAA==.Soufflemort:BAAALAAFFAEIAQAAAA==.',Sp='Spacemiaou:BAAALAAFFAIIAgAAAA==.',Ss='Ssolock:BAABLAAECoEkAAIIAAcImB3tKwBjAgAIAAcImB3tKwBjAgAAAA==.',St='Staberky:BAAALAADCggIDwABLAAECgMIAwAJAAAAAA==.Stanhopea:BAAALAADCgIIAgAAAA==.Starski:BAAALAADCgYIBgABLAAECggIGQAeAEUMAA==.Stiich:BAAALAADCgcICgAAAA==.Stress:BAABLAAECoEjAAMVAAgIpBj9TQAsAgAVAAgIpBj9TQAsAgAaAAgIbAsoHgBUAQAAAA==.',Sw='Sweetzer:BAABLAAECoEmAAMfAAgIyyO9BgAsAwAfAAgIyyO9BgAsAwAXAAEI3iSF8gBqAAAAAA==.Swëetwar:BAAALAAFFAIIAgAAAA==.Swöôp:BAAALAADCgMIAwAAAA==.',Sy='Sylbadas:BAAALAADCgcICAAAAA==.Sylphilia:BAAALAAECgcIEgAAAA==.Sylvranas:BAAALAADCgYIBgAAAA==.Syrnie:BAABLAAECoEXAAMFAAcIigtFFABtAQAFAAcIigtFFABtAQAHAAEIRhB3eQAqAAAAAA==.Syvelt:BAAALAADCggICAAAAA==.',['Sé']='Sébastien:BAAALAADCgcIEwAAAA==.Sédatîîf:BAAALAAECgEIAgAAAA==.Séphorias:BAAALAADCgYICQAAAA==.',['Sï']='Sïndarîn:BAAALAADCgcIBwAAAA==.',['Sø']='Sølomonkane:BAAALAAECgYIDwAAAA==.',Ta='Taarna:BAABLAAECoEiAAIdAAgIvyVTAQB0AwAdAAgIvyVTAQB0AwABLAAFFAYIAwAJAAAAAA==.Talcö:BAAALAADCgYIEgAAAA==.Talullâh:BAAALAAECgYIBgAAAA==.Talykko:BAAALAADCgEIAQAAAA==.Tampaxxe:BAABLAAECoEYAAIKAAcI2xkvKgAdAgAKAAcI2xkvKgAdAgAAAA==.Tass:BAAALAADCgIIAwAAAA==.Taverniertv:BAACLAAFFIEKAAMEAAMItxe/DwD+AAAEAAMItxe/DwD+AAAHAAEIaxVQIABCAAAsAAQKgSYAAgQACAhyJBkTAPcCAAQACAhyJBkTAPcCAAAA.',Te='Tehupoo:BAAALAAECgEIAQAAAA==.Telron:BAAALAAECgcIBwAAAA==.Tenval:BAAALAADCgIIAgAAAA==.Teuffa:BAAALAAECgQIBwAAAA==.Teushiba:BAAALAAECgYIDAAAAA==.Teyko:BAAALAAECgMIBwAAAA==.',Th='Thebosspekor:BAAALAADCgUIBQAAAA==.Thenoobatorr:BAAALAADCggICAAAAA==.Theradin:BAAALAADCgcIBwAAAA==.Thhorr:BAAALAADCgcIFAAAAA==.Thundernain:BAEALAADCggIDgABLAAECgIIBAAJAAAAAA==.Thuzrin:BAAALAAECgYIDwAAAA==.Thyralion:BAAALAADCgcIBwAAAA==.Thànøs:BAABLAAECoEWAAIEAAYI8Au+dwBOAQAEAAYI8Au+dwBOAQAAAA==.Thörald:BAACLAAFFIEFAAILAAMI3RSpDgD5AAALAAMI3RSpDgD5AAAsAAQKgSQAAgsACAh8JSMEAHMDAAsACAh8JSMEAHMDAAAA.',Ti='Tialmère:BAAALAAECgQICAAAAA==.',To='Togghloff:BAAALAADCgYICAAAAA==.Tontontank:BAAALAADCgcIDAAAAA==.Torsix:BAAALAADCggICAABLAAECgcIGAASAJgaAA==.Tozi:BAAALAAECgYIDwAAAA==.Toøk:BAAALAADCgMIAwABLAAECgYIDAAJAAAAAA==.',Tr='Trena:BAAALAAFFAYIAwAAAA==.Triela:BAAALAAECggICAAAAA==.Trâmox:BAAALAADCgQIBAAAAA==.',Tw='Tws:BAAALAADCggICAAAAA==.',Ty='Tyséria:BAABLAAECoEVAAIBAAgIsRVnJQAMAgABAAgIsRVnJQAMAgAAAA==.',['Tä']='Tälvar:BAAALAADCggICAAAAA==.',['Tê']='Têyla:BAAALAADCggIDgABLAAECggIJAAYAEUhAA==.',['Tø']='Tøurøk:BAAALAAECggICAAAAA==.Tøviic:BAAALAADCggICAAAAA==.',Ui='Uialwen:BAAALAAECgYIBgAAAA==.',Um='Umbrozae:BAAALAAECgYIEAAAAA==.Umpä:BAAALAAECgIIAgAAAA==.',Va='Vaelune:BAAALAAECgEIAgAAAA==.Valanice:BAAALAAECgYICAABLAAECgcIGwAdAF4iAA==.Valirias:BAAALAADCgUIBgABLAAECgIIBAAJAAAAAA==.Valkeriya:BAAALAAECgIIAgAAAA==.Valmont:BAAALAAECgQIBgAAAA==.Vassily:BAABLAAECoEaAAIBAAgI9RiwHgA7AgABAAgI9RiwHgA7AgAAAA==.Vava:BAACLAAFFIETAAMkAAYIbBYWBAAGAgAkAAYIbBYWBAAGAgANAAMI/AZlIQCdAAAsAAQKgR8AAyQACAiAJGsbAKACACQABwhnJGsbAKACAA0AAgj9EqzpAG0AAAAA.Vavâ:BAAALAAECgYICAAAAA==.',Ve='Venatorix:BAAALAADCgYIBwAAAA==.Venuz:BAAALAADCgYICgAAAA==.',Vl='Vlazen:BAAALAADCgYIEAAAAA==.',Vo='Voldru:BAAALAADCggIEwAAAA==.Voldusyn:BAAALAADCgEIAQAAAA==.Volkillos:BAAALAADCgQIBAAAAA==.Voltigeur:BAAALAADCgQIBAAAAA==.Voltigeurs:BAAALAADCgcICwAAAA==.Volurgin:BAAALAAECgYIBwAAAA==.Vone:BAAALAADCggILAAAAA==.',Vr='Vraxen:BAAALAAECgIIAgAAAA==.',Vy='Vyelnarys:BAAALAAECgcIDwAAAA==.Vyrazeth:BAAALAAECgIIAgAAAA==.',Wa='Wahzgul:BAAALAADCgcIBwAAAA==.Waltaras:BAABLAAECoEVAAIVAAYIgRpsdADVAQAVAAYIgRpsdADVAQAAAA==.Walï:BAAALAADCggICgAAAA==.Wargheus:BAAALAADCgcIBwAAAA==.Warlaud:BAAALAADCgYIBgAAAA==.Wavÿ:BAAALAADCgQIBAAAAA==.',Wh='Whiterabbit:BAAALAADCgMIAgAAAA==.',['Wó']='Wólf:BAAALAADCgcIBwABLAAFFAYIFgAXAIYhAA==.',['Wø']='Wølfverine:BAAALAADCgIIAgAAAA==.Wøøda:BAAALAADCgYIBgAAAA==.',Xa='Xal:BAAALAAECgYIEgAAAA==.Xaltanis:BAAALAADCgIIAQAAAA==.',Xe='Xertis:BAABLAAECoEYAAIXAAgIQhSEUQDlAQAXAAgIQhSEUQDlAQAAAA==.',Xi='Xipam:BAAALAAECgcIEgAAAA==.',Xy='Xyanaa:BAABLAAECoEdAAIOAAcIFQ8MEgBwAQAOAAcIFQ8MEgBwAQAAAA==.Xyle:BAAALAADCgMIAwAAAA==.',Ya='Yakady:BAAALAADCgcIBgAAAA==.Yakjzak:BAAALAAECgQICAAAAA==.Yasdemo:BAAALAADCgYIDQAAAA==.Yasylkad:BAAALAADCgIIAgAAAA==.',Yd='Ydriel:BAAALAAECgEIAQAAAA==.',Yl='Ylvicî:BAACLAAFFIEGAAIBAAMIEg1FDADRAAABAAMIEg1FDADRAAAsAAQKgRgAAgEACAj7HtsSAKsCAAEACAj7HtsSAKsCAAAA.',Yn='Ynferia:BAAALAAECgYIBgAAAA==.',Yo='Youzu:BAAALAAECgQIBAAAAA==.',Yu='Yunkaï:BAAALAADCggICAAAAA==.Yunà:BAAALAADCggIDwAAAA==.',Yv='Yvalys:BAAALAAECgEIAQABLAAECgYICQAJAAAAAA==.',Yz='Yza:BAACLAAFFIEMAAIOAAQIzx6OAACFAQAOAAQIzx6OAACFAQAsAAQKgSEAAg4ACAjzJAEBAGEDAA4ACAjzJAEBAGEDAAAA.Yzae:BAAALAADCggICAAAAA==.Yzara:BAAALAADCgUIBQAAAA==.',['Yö']='Yöba:BAABLAAECoEUAAIPAAcI8CIgEAC0AgAPAAcI8CIgEAC0AgAAAA==.',Za='Zaely:BAAALAADCgMIBAABLAAECgYIFQALALoJAA==.Zahely:BAABLAAECoEVAAILAAYIuglZyAAwAQALAAYIuglZyAAwAQAAAA==.Zakaarys:BAAALAADCgYIBgAAAA==.Zaïtche:BAAALAADCgcIBgABLAAECgYIEgAJAAAAAA==.',Zb='Zbug:BAAALAADCgUIAgAAAA==.',Ze='Zegvor:BAABLAAECoEmAAIhAAgIUyHcAQASAwAhAAgIUyHcAQASAwAAAA==.Zeldala:BAAALAADCggIIwAAAA==.Zeldo:BAAALAAECgUIBAAAAA==.Zeldoris:BAAALAADCgEIAQABLAADCgYIBgAJAAAAAA==.Zeldormi:BAAALAADCgYIBgAAAA==.Zetick:BAAALAAECgYICgAAAA==.Zewielle:BAABLAAECoEfAAMKAAgIEBlTIQBQAgAKAAgIEBlTIQBQAgAlAAQIewx+HgC3AAAAAA==.',Zo='Zoe:BAAALAAECgYIDgAAAA==.',Zu='Zulgart:BAAALAAECgMIAwABLAAECgUICAAJAAAAAA==.',Zy='Zylia:BAAALAAECgYIBgAAAA==.',Zz='Zzaegir:BAABLAAECoElAAIfAAgIMSUFAwBVAwAfAAgIMSUFAwBVAwAAAA==.Zzeimdall:BAABLAAECoEZAAIkAAcIJSRvFADXAgAkAAcIJSRvFADXAgABLAAECggIJQAfADElAA==.',['Zè']='Zèll:BAAALAAECgQIBAABLAAECgYICgAJAAAAAA==.',['Zé']='Zéravas:BAAALAAECgYICwAAAA==.',['Zë']='Zëlfk:BAAALAADCggIDwAAAA==.',['Ân']='Ângêls:BAAALAAECgUIBwAAAA==.',['Ãx']='Ãxreder:BAABLAAECoEbAAILAAYIHCTqNwBoAgALAAYIHCTqNwBoAgAAAA==.',['Äz']='Äzell:BAABLAAECoEiAAMLAAgI0B7KRQA9AgALAAgIFhzKRQA9AgAdAAcIdRsWFgASAgAAAA==.',['Ða']='Ðalania:BAAALAADCggICQAAAA==.Ðamédia:BAAALAAECgMIBQAAAA==.',['Öl']='Öllïe:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end