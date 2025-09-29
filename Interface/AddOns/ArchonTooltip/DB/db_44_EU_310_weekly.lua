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
 local lookup = {'Priest-Shadow','Warlock-Demonology','Shaman-Elemental','Warrior-Arms','Hunter-BeastMastery','Evoker-Preservation','DemonHunter-Havoc','Druid-Guardian','Druid-Restoration','Druid-Feral','Unknown-Unknown','Hunter-Marksmanship','Shaman-Restoration','Paladin-Retribution','Monk-Mistweaver','Mage-Frost','Mage-Arcane','DeathKnight-Blood','DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Druid-Balance','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Vengeance','Warrior-Protection','Rogue-Outlaw','Paladin-Protection','Priest-Holy','Priest-Discipline','Mage-Fire','Warlock-Affliction','Warlock-Destruction','Evoker-Devastation','Paladin-Holy','Shaman-Enhancement','Warrior-Fury',}; local provider = {region='EU',realm='Lightbringer',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ad='Adventine:BAAALAAECgcIDgAAAA==.Adventro:BAAALAAECgEIAQAAAA==.',Ae='Aedan:BAAALAAECgIIAgAAAA==.Aeldine:BAABLAAECoEbAAIBAAcIKyLwFQCiAgABAAcIKyLwFQCiAgAAAA==.',Ag='Agathys:BAABLAAECoEaAAICAAcIxxt9EgBIAgACAAcIxxt9EgBIAgAAAA==.Agigaue:BAABLAAECoEZAAIDAAcIYwjlYABZAQADAAcIYwjlYABZAQAAAA==.',Ah='Aheleziel:BAAALAAECgcIBwAAAA==.',Ai='Ainnyston:BAAALAAECggIBwAAAA==.',Ak='Akhiron:BAAALAADCgYICwAAAA==.',Al='Alaven:BAAALAAECgIIAgAAAA==.Alestair:BAAALAADCggICAAAAA==.Algirdoska:BAABLAAECoEaAAIEAAcIBRkRCwAHAgAEAAcIBRkRCwAHAgAAAA==.Alitaki:BAAALAAECgYICwAAAA==.Alitia:BAAALAAECgYIEwAAAA==.Alityria:BAABLAAECoEbAAIBAAcIeAz1QQCJAQABAAcIeAz1QQCJAQAAAA==.Alkrun:BAAALAAECgcIDgAAAA==.Almanes:BAABLAAECoEhAAIFAAgI0yFHDwAGAwAFAAgI0yFHDwAGAwABLAAFFAUIDAAGAJgZAA==.Alranea:BAAALAAECgUIDgAAAA==.',Am='Amazone:BAABLAAECoEoAAIFAAcI6R6kMwBDAgAFAAcI6R6kMwBDAgAAAA==.',An='Anarkhys:BAAALAAECgUIBAAAAA==.Ancaeus:BAAALAAECgMIAwAAAA==.Ancsmoke:BAAALAAECgEIAQAAAA==.Andonian:BAABLAAECoEWAAIHAAgI1yIGDQAtAwAHAAgI1yIGDQAtAwAAAA==.Anduviel:BAABLAAECoEiAAQIAAcIfB6nBgBgAgAIAAcIfB6nBgBgAgAJAAYIWg7MZwATAQAKAAEIMwZNQgAfAAABLAAECgcIKAAFAOkeAA==.Anjomaa:BAAALAAECgMIBAAAAA==.Annissa:BAAALAADCgMIAwABLAAECgUIBQALAAAAAA==.Antaras:BAAALAADCggICAAAAA==.',Ao='Aokoh:BAABLAAECoEUAAMFAAcIMRkAfAB5AQAFAAYIJBoAfAB5AQAMAAcI0RCHVwA7AQAAAA==.',Ar='Arasara:BAAALAADCggIDgAAAA==.',As='Ascad:BAAALAAECgYICAAAAA==.Ashpaw:BAAALAADCgcICwAAAA==.Astiarus:BAABLAAECoEkAAIFAAcIShd2VADYAQAFAAcIShd2VADYAQABLAAECggIHwANANgMAA==.Astronemer:BAAALAAECgYICAAAAA==.Aszdormu:BAAALAADCggICgAAAA==.',At='Athorion:BAAALAADCggICAAAAA==.Atrexie:BAABLAAECoEYAAIOAAcI1Bx3QABKAgAOAAcI1Bx3QABKAgAAAA==.Attentipo:BAABLAAECoEWAAIPAAcIpAN2MgDTAAAPAAcIpAN2MgDTAAAAAA==.',Av='Avengarde:BAAALAAECgQIBwAAAA==.',Ax='Axedd:BAABLAAECoEdAAMMAAcIWw6VUgBNAQAMAAcIHA2VUgBNAQAFAAcIbQlamQA+AQAAAA==.',Ay='Ayika:BAAALAADCgEIAQAAAA==.Ayoubb:BAAALAAECgUIBQAAAA==.',Ba='Bakeneko:BAAALAAECgIIAgAAAA==.Baleus:BAAALAADCggIDwAAAA==.Baloney:BAABLAAECoEaAAIJAAcIixcMLQD4AQAJAAcIixcMLQD4AQAAAA==.Barboa:BAAALAAECgIIAgAAAA==.Basileus:BAAALAADCgcICQAAAA==.',Be='Bejórn:BAAALAADCgIIAgAAAA==.Bellar:BAAALAADCggICAAAAA==.Bellatrixa:BAABLAAECoEZAAICAAcIxQP7SAAhAQACAAcIxQP7SAAhAQAAAA==.Bennike:BAABLAAECoEUAAMQAAgIfAWaYQCZAAAQAAcIMgaaYQCZAAARAAQIRAF50gBGAAAAAA==.Bewearorc:BAABLAAECoEnAAISAAgIHBNsEwDZAQASAAgIHBNsEwDZAQAAAA==.',Bi='Bigwagyu:BAAALAADCggIGAAAAA==.Biscoff:BAAALAADCgYIBgAAAA==.',Bj='Bjorrn:BAAALAAECgYIEQAAAA==.',Bl='Blackleon:BAAALAADCgIIAgAAAA==.Blodsam:BAAALAAECgMIAwAAAA==.Bloodyhel:BAABLAAECoEXAAMTAAYIhyG2XwD+AQATAAYIhyG2XwD+AQAUAAQItBb7MQAYAQAAAA==.',Bo='Bojowy:BAAALAADCgIIAgAAAA==.Boldensjane:BAACLAAFFIEHAAIEAAIIjhrhAQC6AAAEAAIIjhrhAQC6AAAsAAQKgSsAAgQACAidGoIFAJcCAAQACAidGoIFAJcCAAAA.Bonarius:BAAALAAECgMIBgAAAA==.Bozanaestra:BAAALAADCgcIBwABLAAECgQICQALAAAAAA==.',Br='Bratsaras:BAAALAAECgYIEgAAAA==.Bruceflea:BAAALAAECgMIAwAAAA==.Brumbazz:BAAALAAECgQIBgAAAA==.Bréèd:BAAALAADCgcIBwAAAA==.',['Bá']='Bámbí:BAAALAADCgcIBwAAAA==.',['Bú']='Búl:BAAALAAECgMIAwAAAA==.',Ca='Calalith:BAAALAAECggICgAAAA==.Calistha:BAABLAAECoEZAAIFAAcICxBocACTAQAFAAcICxBocACTAQAAAA==.Callack:BAAALAAECgUIDgAAAA==.Carepolice:BAAALAAECgYIDAAAAA==.Cascara:BAABLAAECoEeAAIBAAgIpR5rHABrAgABAAgIpR5rHABrAgAAAA==.Caspean:BAAALAAECggIEAAAAA==.Caye:BAAALAAECgMIBgAAAA==.',Cc='Cc:BAAALAADCggICAAAAA==.',Ce='Cedian:BAAALAADCggICAABLAAECggIIQAOAPgeAA==.Celestial:BAAALAADCggICAAAAA==.Celetus:BAAALAADCgcIBwAAAA==.',Ch='Chadwizard:BAAALAAECgcICwABLAAECggIHAAVAHYYAA==.Charnelestra:BAABLAAECoElAAIBAAgIgxPJKAARAgABAAgIgxPJKAARAgABLAAECgcIFwADAHEiAA==.Chedward:BAABLAAECoEaAAIVAAgIaB38CwBsAgAVAAgIaB38CwBsAgAAAA==.Chibi:BAAALAAECgUICwAAAA==.Chisei:BAAALAAECggIAwAAAA==.Chopsuey:BAABLAAECoEZAAITAAcIsxhyWwAHAgATAAcIsxhyWwAHAgAAAA==.',Ci='Cibus:BAAALAAECgMIAwAAAA==.',Cl='Clerick:BAAALAADCggICAAAAA==.Clyde:BAAALAAECggIBwAAAA==.',Co='Cocodudu:BAABLAAECoEVAAMJAAcI7BEeaAATAQAJAAYIJhAeaAATAQAWAAcIDAXHXwDsAAAAAA==.Colino:BAAALAADCggICAAAAA==.Coowchie:BAAALAAECgUIBQAAAA==.',Cr='Craesa:BAAALAADCggICAABLAAECggICAALAAAAAA==.Crowblade:BAAALAAECgcICgAAAA==.Cruell:BAAALAAECggICQAAAA==.',Cs='Csontii:BAABLAAECoEaAAIXAAgIkhLhGgD6AQAXAAgIkhLhGgD6AQAAAA==.',Cy='Cyni:BAABLAAECoEaAAMPAAgIhBMsFwDXAQAPAAgIhBMsFwDXAQAXAAEIYQjhWAAtAAAAAA==.Cynicane:BAAALAADCgMIAwABLAAECggIGgAPAIQTAA==.',Da='Daddycool:BAABLAAECoElAAINAAgIFxltLwAqAgANAAgIFxltLwAqAgAAAA==.Daetha:BAAALAADCgcIFAAAAA==.Dahlamar:BAAALAADCgIIAgAAAA==.Danifullsend:BAACLAAFFIEHAAIYAAMILiNHBQBAAQAYAAMILiNHBQBAAQAsAAQKgS4AAxgACAiDJRsBAHEDABgACAiDJRsBAHEDABkAAQi5F1s/AEIAAAAA.Darkbarumky:BAAALAAECgYIBwAAAA==.Darkdragon:BAAALAADCggIGwAAAA==.Darkfaíth:BAAALAAECgcIBwAAAA==.Darkthrone:BAAALAAECggIEQAAAA==.Davtumal:BAAALAAECgcIDgAAAA==.',De='Deadcorpse:BAAALAAECgMIBgAAAA==.Deathgooner:BAAALAAECgIIAwAAAA==.Deathless:BAAALAAECgEIAQAAAA==.Deathnas:BAAALAAECgEIAgAAAA==.Deathstrôke:BAAALAAECggICAAAAA==.Decuma:BAAALAAECgQIBAAAAA==.Demonkinge:BAABLAAECoEZAAIaAAcI1hzwEAAjAgAaAAcI1hzwEAAjAgAAAA==.',Dh='Dhrakor:BAAALAADCgQIBAAAAA==.',Di='Diamondtetra:BAABLAAECoEXAAIbAAcIxRHiMQB8AQAbAAcIxRHiMQB8AQAAAA==.Diebobyy:BAABLAAECoEWAAIaAAcIvCNTCQCbAgAaAAcIvCNTCQCbAgAAAA==.Dimensius:BAAALAADCggICAAAAA==.Dirtjam:BAAALAAECgIIAgABLAAECgMIAwALAAAAAA==.Diville:BAAALAADCggIGAAAAA==.Dizzblud:BAAALAADCgMIAwAAAA==.',Dk='Dkbalu:BAAALAAECgQIBgAAAA==.',Do='Doftoroaia:BAAALAADCgMIAwAAAA==.',Dr='Draghter:BAAALAADCgIIAgAAAA==.Dragonpew:BAAALAAECgQIBgAAAA==.Drakoulini:BAAALAADCggIDwAAAA==.Draxxion:BAAALAADCggIDQAAAA==.Dreadnaughty:BAAALAAECggIEQAAAA==.Drstabby:BAABLAAECoEVAAIcAAcIlyOkAgDVAgAcAAcIlyOkAgDVAgAAAA==.Drummerdude:BAAALAADCgcIEgAAAA==.Drumzforeva:BAAALAAECgUICgAAAA==.Drøl:BAAALAAECgYIDwAAAA==.',Du='Duclip:BAABLAAECoEVAAIJAAgIpBs+GgBiAgAJAAgIpBs+GgBiAgAAAA==.Duffadin:BAABLAAECoEZAAIdAAcIBhBHKwBdAQAdAAcIBhBHKwBdAQAAAA==.',Ea='Ealo:BAAALAAECgYIEQAAAA==.',Ed='Edubbledee:BAABLAAECoEZAAIQAAcITBOdIwDYAQAQAAcITBOdIwDYAQAAAA==.',El='Elase:BAAALAADCgcIDgAAAA==.Elementalist:BAAALAADCgcIDgAAAA==.Elementalize:BAAALAADCggIDQAAAA==.Elfitta:BAAALAAECgYICQABLAAECgYICgALAAAAAA==.Elihm:BAABLAAECoEiAAIJAAcIlRbLMwDXAQAJAAcIlRbLMwDXAQAAAA==.Ellendrim:BAAALAAECgcIBwAAAA==.Ellis:BAAALAADCggICAAAAA==.Elric:BAAALAAECgUICgAAAA==.Elunaria:BAAALAAECgIIAgAAAA==.Elvispriesty:BAAALAAECgcIBwABLAAECgcIGwAHAFUfAA==.Elwevyn:BAAALAAECgYIEgAAAA==.Elyssae:BAAALAADCggIEAAAAA==.',Ep='Ephanim:BAAALAADCggICAAAAA==.',Er='Erogan:BAAALAADCggICAAAAA==.',Eu='Eurus:BAABLAAECoEZAAQeAAgIXhOcRACZAQAeAAYINBicRACZAQABAAcIzAUXWAAkAQAfAAEISAbVNwAfAAAAAA==.',Ev='Evening:BAAALAAECgcIAwAAAA==.',Ew='Ewl:BAAALAAECgUIDAAAAA==.',Ex='Extrem:BAAALAAECgYIDAAAAA==.',Fa='Fafita:BAAALAADCgYIBwAAAA==.Fakinjo:BAAALAAECgYICAAAAA==.Falenix:BAABLAAECoEXAAIWAAcIJxffMgC8AQAWAAcIJxffMgC8AQAAAA==.Fangslasherr:BAABLAAECoEkAAIFAAgIoCFlEgDwAgAFAAgIoCFlEgDwAgAAAA==.',Fe='Feldem:BAAALAAECgQIBAAAAA==.Felissa:BAAALAADCggIEQAAAA==.Felnatik:BAABLAAECoEgAAMaAAcIFiarBAAIAwAaAAcIFiarBAAIAwAHAAYIMiEnQwAnAgAAAA==.Feltetra:BAAALAADCgcIBwAAAA==.Fengan:BAAALAAECgcIBwAAAA==.Feulmage:BAABLAAECoEbAAIgAAgIvA19BgDoAQAgAAgIvA19BgDoAQAAAA==.',Fi='Fierystormz:BAAALAAECgMICAAAAA==.Firechu:BAAALAAECgYIDAAAAA==.',Fl='Flipz:BAAALAAECgcIDgAAAA==.Floppypigeon:BAAALAAECgcIBQAAAA==.Florijn:BAAALAAECgYIBgABLAAECgcIKAAFAOkeAA==.',Fo='Forata:BAAALAAECgUIDwAAAA==.Forkandknife:BAAALAAECgUIDAAAAA==.',Fr='Freelance:BAAALAAECgYIBgABLAAFFAIIBgANABofAA==.Fregless:BAAALAAECgIIAgAAAA==.Freglles:BAAALAADCggICAABLAAECgIIAgALAAAAAA==.Froztbite:BAAALAAECgUIBQAAAA==.Fröstiebear:BAABLAAECoEWAAMhAAcI1wotGQAaAQAhAAYIHwctGQAaAQAiAAUIXgtYmwDpAAAAAA==.',Fu='Fujï:BAAALAAECgEIAgAAAA==.',['Fé']='Féntriox:BAAALAADCggIEAAAAA==.',Ga='Gargámel:BAAALAAECgYICQAAAA==.',Ge='Geosham:BAAALAAECgcICAAAAA==.',Gi='Gibpetsuwu:BAAALAAECgYIDAAAAA==.Gildarts:BAAALAADCgMIAwAAAA==.Gilgamaesh:BAAALAADCgYIEgAAAA==.',Gl='Glamourdale:BAAALAAECgEIAQABLAAECgcIFQAQADYGAA==.',Go='Gorgogrim:BAABLAAECoEZAAIaAAcIzheZFgDcAQAaAAcIzheZFgDcAQAAAA==.Gorz:BAAALAAECgcIAwAAAA==.',Gr='Griffèn:BAAALAAECggIBgAAAA==.Grimicus:BAAALAADCgQIAwAAAA==.Grimlir:BAAALAADCgcIBwAAAA==.Grimmtotem:BAABLAAECoEdAAMDAAcIiRlDLgAmAgADAAcIiRlDLgAmAgANAAYIugqtrADfAAAAAA==.Grog:BAAALAADCgMIAwAAAA==.',Gw='Gwendolyn:BAAALAADCggICQAAAA==.',Ha='Haaldiir:BAABLAAECoETAAIDAAcIkBuZKABGAgADAAcIkBuZKABGAgAAAA==.Haddokken:BAAALAADCggICwAAAA==.Halgrimur:BAAALAAECggICAAAAA==.Harvs:BAAALAAECgMIAwAAAA==.Hauntmedk:BAAALAAECgQICQAAAA==.Hauntu:BAABLAAECoEUAAMBAAYIHxo7NADPAQABAAYIHxo7NADPAQAeAAMIUhivewDQAAAAAA==.Havhingsten:BAAALAADCggICAAAAA==.',He='Hellshocked:BAAALAADCgcIBwAAAA==.Hellstrike:BAAALAADCgcICAAAAA==.Hexxrg:BAAALAAECgIIAwAAAA==.',Hi='Himse:BAAALAADCgcIBwAAAA==.Hiz:BAABLAAECoEaAAMjAAcIFiBRHAAZAgAjAAYIcx9RHAAZAgAGAAMIHBprJgDhAAAAAA==.',Ho='Hoegan:BAAALAAECgIIAgABLAAECgcIFQAcAJcjAA==.',Hr='Hragon:BAABLAAECoEbAAIjAAgIxxGXJADRAQAjAAgIxxGXJADRAQAAAA==.',Hu='Humlinheart:BAAALAAECgQICQAAAA==.',Hy='Hyeju:BAABLAAECoEkAAIHAAgImBTAQwAlAgAHAAgImBTAQwAlAgAAAA==.',Ic='Icecoldd:BAAALAADCggICAAAAA==.Iceolate:BAAALAADCgIIAgAAAA==.',Ik='Ikklepickle:BAAALAADCggICAAAAA==.Ikonn:BAAALAADCggICAAAAA==.',Il='Ilann:BAAALAADCggIDgAAAA==.Ilarian:BAAALAAECgIIAgAAAA==.Illidarix:BAAALAAECgcIEQAAAA==.Illydoor:BAAALAAECgMIAwAAAA==.',In='Incredibul:BAAALAAECgMIAwAAAA==.Indirah:BAABLAAECoEbAAIDAAcILiEZGwCfAgADAAcILiEZGwCfAgAAAA==.Infinidormi:BAAALAADCgcIBwAAAA==.Inyangá:BAAALAADCggICAABLAAECgUIBQALAAAAAA==.',Is='Ishana:BAABLAAECoEYAAIFAAcIJRkYRwD+AQAFAAcIJRkYRwD+AQAAAA==.Issilid:BAAALAADCgUIBAAAAA==.',It='Itherion:BAAALAADCgEIAQAAAA==.Itsnoturzits:BAAALAAECgMIAwAAAA==.',Ix='Ixtus:BAAALAADCgcICgABLAAFFAQIBAALAAAAAA==.',Ja='Jacepwnx:BAAALAADCggIDgAAAA==.Jaegër:BAAALAADCgUIBQAAAA==.Janickaa:BAABLAAECoEoAAIPAAgIYhUYEwANAgAPAAgIYhUYEwANAgAAAA==.Jaybied:BAAALAADCgcIBwABLAAECgYIFAAFADgkAA==.',Jo='Johnthomas:BAABLAAECoEiAAMNAAcIHB5VKABHAgANAAcIHB5VKABHAgADAAQI3AosggDKAAAAAA==.Joliyty:BAAALAAECgEIAQAAAA==.Jondalar:BAAALAADCggICAAAAA==.Joroboros:BAAALAAECgMIAwAAAA==.',Ju='Judgeeyou:BAAALAAECgMIAwAAAA==.Justicë:BAAALAAECgUIBQAAAA==.',['Jä']='Järnkamìn:BAAALAADCggICAAAAA==.',Ka='Kadresh:BAAALAADCgcICgAAAA==.Kaenthar:BAAALAAECggIAQAAAA==.Kahunt:BAAALAAECggIDAABLAAFFAIICQAWAOElAA==.Kajkage:BAAALAAECgQICQAAAA==.Kalitz:BAAALAADCgYIBgAAAA==.Karlog:BAAALAAECgcIEwAAAA==.Kawaki:BAAALAADCgMIAwAAAA==.Kazana:BAAALAADCggIFwAAAA==.Kazymod:BAAALAADCggICAAAAA==.',Ke='Kelsin:BAAALAAECgYIBwABLAAECgcIGQACAPUZAA==.Kenagon:BAAALAAECgMIAwABLAAECggIJwASABwTAA==.Kenagone:BAAALAAECgMIAwABLAAECggIJwASABwTAA==.Keratoula:BAAALAADCggIDQAAAA==.Kercske:BAAALAADCgcIBwAAAA==.',Kh='Khaani:BAAALAAECgEIAQAAAA==.Kharn:BAAALAADCgMIAwABLAAECggIJQATAPkhAA==.',Ki='Kielith:BAABLAAECoEZAAICAAgIkxrkFQAoAgACAAgIkxrkFQAoAgAAAA==.Kikyoass:BAAALAAECgYICQAAAA==.Kiriara:BAAALAADCgcIEQAAAA==.Kitch:BAACLAAFFIETAAIdAAcIeiEoAACXAgAdAAcIeiEoAACXAgAsAAQKgRoAAh0ACAhoI54GAPACAB0ACAhoI54GAPACAAAA.',Ko='Kokobanana:BAAALAAECgUIBQAAAA==.Kokorokara:BAAALAAECgMIBwABLAAECgUIBQALAAAAAQ==.Kossian:BAABLAAECoEgAAIOAAcI9B5bOwBaAgAOAAcI9B5bOwBaAgAAAA==.',Kr='Kravinus:BAAALAAECgQIBAAAAA==.Krumpen:BAAALAAECggIBAABLAAECggIFAAQAHwFAA==.',Ky='Kyndra:BAAALAAECgMIBAAAAA==.Kyy:BAAALAADCggICQAAAA==.',La='Lagerthaa:BAAALAAECgIIAgAAAA==.Lamemonkey:BAAALAAECgYIEAAAAA==.Lamithralas:BAABLAAECoEWAAIUAAcI4xiEEQAqAgAUAAcI4xiEEQAqAgAAAA==.Lanxy:BAACLAAFFIEIAAMeAAMIHxw0CwASAQAeAAMIHxw0CwASAQAfAAIINgyhAgCAAAAsAAQKgVsABAEACAjbIaAIACYDAAEACAjbIaAIACYDAB4ACAjMHscQAMcCAB8ACAiyHBUDAKACAAAA.Lapaladin:BAAALAAECgYICAAAAA==.Larra:BAAALAAECgYICwABLAAECggIGQAeAF4TAA==.Latlock:BAAALAADCgcICAAAAA==.Laurana:BAAALAADCggIEAAAAA==.',Le='Letry:BAAALAAECgYICgAAAA==.',Li='Libber:BAAALAAECgMIBQAAAA==.Lillard:BAAALAAECgEIAQAAAA==.Lilwïz:BAAALAADCggIFgAAAA==.Linnea:BAAALAADCgMIAwAAAA==.Lionell:BAAALAAECgYIEQAAAA==.Lirík:BAACLAAFFIESAAIOAAYIvh0fAQBJAgAOAAYIvh0fAQBJAgAsAAQKgSgAAg4ACAiJJVcKAEcDAA4ACAiJJVcKAEcDAAAA.Lizardpally:BAABLAAECoEVAAIkAAcIDh+gDgB8AgAkAAcIDh+gDgB8AgAAAA==.',Ll='Lloydari:BAAALAAECgYIDgAAAA==.',Lo='Lockié:BAAALAAECgEIAQABLAAECgUIBQALAAAAAA==.Lokiarie:BAABLAAECoEXAAIFAAcIdQ0WgABwAQAFAAcIdQ0WgABwAQAAAA==.Loreki:BAAALAADCgUIBQAAAA==.Lorieth:BAABLAAECoEbAAIFAAcIARN2egB8AQAFAAcIARN2egB8AQAAAA==.Lorié:BAAALAAECgQIBAAAAA==.Lorsan:BAAALAADCgcIDgAAAA==.Losspli:BAAALAADCggIEQAAAA==.',Lu='Ludidoktor:BAABLAAECoEwAAMDAAgIbRRwLAAwAgADAAgIbRRwLAAwAgANAAQITA7VxACyAAAAAA==.Lukoo:BAAALAAECgcIBAAAAA==.Luku:BAAALAADCgIIAgAAAA==.Lunadawn:BAABLAAECoEWAAMQAAcIYhSRJgDFAQAQAAcIYhSRJgDFAQAgAAIICQXmFwBQAAAAAA==.',Ly='Lyriana:BAABLAAECoEiAAIFAAgIThHmcACSAQAFAAgIThHmcACSAQAAAA==.Lysannah:BAAALAAECgIIAgAAAA==.Lysera:BAAALAADCgIIBQABLAAECgcIGAAFACUZAA==.Lyétin:BAAALAADCggICAAAAA==.',['Lé']='Léeroy:BAABLAAECoEYAAIOAAYIKCKPQgBEAgAOAAYIKCKPQgBEAgAAAA==.',['Lü']='Lücifêr:BAAALAAECggICAAAAA==.',Ma='Macbeth:BAAALAADCgcIBwAAAA==.Macmicke:BAAALAAECgQICAAAAA==.Maeldore:BAAALAADCggIDwAAAA==.Magnarstrom:BAAALAAECgQIBAAAAA==.Magnussen:BAAALAAECgUIEwAAAA==.Malice:BAABLAAECoEcAAMdAAcI9hdvGgDmAQAdAAcI9hdvGgDmAQAOAAYInhDDrQBdAQAAAA==.Maligné:BAABLAAECoEiAAMYAAcIOgwdMgCJAQAYAAcIFwwdMgCJAQAZAAII0AJaQAA9AAAAAA==.Marackez:BAABLAAECoEcAAIOAAgIFwgJmACFAQAOAAgIFwgJmACFAQAAAA==.Marallie:BAAALAAECgUIBQAAAA==.Marmellinjr:BAAALAADCgQIBgABLAAECgUIDgALAAAAAA==.Marsupia:BAAALAAECgYIBgAAAA==.Marumi:BAAALAADCgQIBAABLAAECgcIGQAcALAfAA==.Mayaa:BAABLAAECoEhAAIfAAgI0SU+AAB0AwAfAAgI0SU+AAB0AwAAAA==.Maylive:BAABLAAECoEaAAMGAAcIahrGEwC9AQAGAAYIbRnGEwC9AQAjAAIIBw0KVwBDAAAAAA==.Mayuu:BAAALAADCggIEAAAAA==.',Me='Meffiu:BAAALAAECgYIDgAAAA==.Meisietjie:BAAALAAECggIEAAAAA==.Mekca:BAAALAADCggICAAAAA==.Melaen:BAAALAADCggIEAAAAA==.Melagorn:BAAALAAECgUIDgAAAA==.Meniere:BAABLAAECoEaAAIVAAcIAAKAMgCnAAAVAAcIAAKAMgCnAAAAAA==.Meskiukas:BAABLAAECoEbAAIEAAcIuhyqBwBZAgAEAAcIuhyqBwBZAgAAAA==.Metalforeva:BAAALAADCgMIBAAAAA==.Methalis:BAABLAAECoEaAAIHAAcIgBsvSgAQAgAHAAcIgBsvSgAQAgAAAA==.',Mi='Miade:BAAALAADCgIIAgAAAA==.Mies:BAAALAADCggICAAAAA==.Mightyshield:BAAALAAECgQICQAAAA==.Mintus:BAAALAAECggIBAAAAA==.Miranda:BAAALAAECgQIBwAAAA==.Mistledove:BAAALAAECgYIEAAAAA==.Miyuki:BAABLAAECoEZAAIUAAcIqRRLFwDoAQAUAAcIqRRLFwDoAQAAAA==.',Mo='Mokkle:BAAALAADCgMIAwAAAA==.Moony:BAAALAADCggICAAAAA==.Morendel:BAAALAAECgYIDgABLAAECgcIHAAdAPYXAA==.Morgoar:BAAALAADCgcIBwAAAA==.Morog:BAAALAAECgMIAwAAAA==.',['Mâ']='Mâgius:BAACLAAFFIEHAAIQAAQI5gSPCgCXAAAQAAQI5gSPCgCXAAAsAAQKgSgAAhAACAhhHroKAM0CABAACAhhHroKAM0CAAAA.',['Mó']='Mórphéuz:BAAALAADCgEIAQAAAA==.',['Mö']='Mörkajonte:BAAALAADCgcIBwAAAA==.Mörphy:BAAALAAECgIIAgAAAA==.',['Mú']='Múji:BAAALAAECggIDgAAAA==.',Na='Narjala:BAAALAAECgYIDwAAAA==.Nazaró:BAAALAAECggICAAAAA==.',Ne='Neclach:BAABLAAECoEuAAIiAAgI9RNMOwAWAgAiAAgI9RNMOwAWAgAAAA==.Neffri:BAAALAADCgcIBwAAAA==.Nesoi:BAAALAADCgcIBwAAAA==.',Ni='Nikyvara:BAAALAADCgcIBwAAAA==.Nilyssa:BAAALAADCgUIBwAAAA==.',No='Nomadx:BAABLAAECoEUAAIFAAcIeAwIhABpAQAFAAcIeAwIhABpAQAAAA==.Nosaint:BAAALAADCgMIAwAAAA==.Novalock:BAAALAAECgMIBwAAAA==.Noxlumina:BAAALAAECgQIBQAAAA==.',Ny='Nyffe:BAAALAADCgEIAQAAAA==.Nyhm:BAAALAAECgUIBQAAAA==.Nymfel:BAABLAAECoEfAAIHAAgIwSK4HgDFAgAHAAgIwSK4HgDFAgAAAA==.',['Ná']='Náevia:BAAALAADCgIIAgABLAAECggIGQAOAN4OAA==.',['Nä']='Näckromanser:BAAALAAECgMIAwAAAA==.',Od='Oddo:BAABLAAECoEeAAITAAgImQdiwwBGAQATAAgImQdiwwBGAQAAAA==.',Ok='Okuyasuni:BAAALAADCgYIBgAAAA==.',Ol='Oldhag:BAAALAAECgYIEAAAAA==.Oldk:BAABLAAECoEUAAITAAcI0CCWNwBsAgATAAcI0CCWNwBsAgAAAA==.',On='Onlyfangs:BAAALAADCgcICQAAAA==.',Oo='Oomyty:BAAALAADCgQIAwAAAA==.',Op='Opeews:BAAALAAECggIDgAAAA==.Oppstoppa:BAAALAAECgMIAwAAAA==.',Pa='Painbringer:BAABLAAECoEhAAIBAAgIIxJrLAD7AQABAAgIIxJrLAD7AQAAAA==.Paladinsolo:BAAALAAECgEIAQAAAA==.Paladiná:BAAALAAECgUIBQAAAA==.Palajane:BAAALAAFFAEIAQAAAA==.Pallypowers:BAAALAADCgEIAQABLAAECgYICgALAAAAAA==.Panerai:BAABLAAECoEiAAIlAAcIJxdLDAD9AQAlAAcIJxdLDAD9AQAAAA==.Pannipa:BAAALAAECgQIBgAAAA==.Papapopoff:BAAALAADCgUIBQAAAA==.Papasmerf:BAAALAAECgYIBgAAAA==.Parsifal:BAABLAAECoEWAAIOAAYI5wWO3QD8AAAOAAYI5wWO3QD8AAAAAA==.Paulpeewee:BAAALAAECgYICAAAAA==.',Pe='Pedrø:BAABLAAECoEZAAIcAAcIsB9mBAB1AgAcAAcIsB9mBAB1AgAAAA==.Petersen:BAAALAADCggIFgAAAA==.',Ph='Phelloz:BAAALAAECgYIBgAAAA==.Phongeline:BAAALAADCggIFgAAAA==.',Pi='Piciipocok:BAABLAAECoEVAAMdAAcIdyKxCwCMAgAdAAcIdyKxCwCMAgAOAAEIiwybNAE3AAAAAA==.Pippínz:BAABLAAECoEZAAIOAAgI3g55iQCgAQAOAAgI3g55iQCgAQAAAA==.Pius:BAABLAAECoEYAAMBAAgInBgIHgBeAgABAAgInBgIHgBeAgAeAAcIdRZdNQDgAQAAAA==.',Pl='Pleunie:BAABLAAECoEcAAIiAAcI/wrXbABxAQAiAAcI/wrXbABxAQAAAA==.',Po='Poisonrose:BAAALAAECgcICQAAAA==.Pompa:BAAALAADCggICAAAAA==.',Pr='Priestelf:BAAALAAECgIIAgAAAA==.Prinxe:BAAALAADCgcIDQAAAA==.Pristiai:BAAALAADCgUIBQABLAAECgUIBQALAAAAAA==.Protection:BAAALAADCggICAAAAA==.',Ps='Pseudomonas:BAAALAAECgcIDgAAAA==.',Pu='Pubmasher:BAAALAADCgcICAAAAA==.',['Pí']='Píppínz:BAAALAAECgMIBAABLAAECggIGQAOAN4OAA==.',Qd='Qd:BAAALAAECggICwAAAA==.',Ra='Ragnul:BAAALAADCgIIAgAAAA==.Rammas:BAABLAAECoEWAAIBAAcIIB9THgBcAgABAAcIIB9THgBcAgAAAA==.Ramzee:BAAALAAECgcICQAAAA==.Ramzess:BAABLAAECoEhAAMeAAgITB86EADNAgAeAAgITB86EADNAgAfAAQI6xbcFQAXAQAAAA==.Ranea:BAABLAAECoEXAAMXAAcIIxLkIwCoAQAXAAcIIxLkIwCoAQAPAAYIhg9CJgA2AQAAAA==.Rastaa:BAAALAADCgcIBwAAAA==.Ravnel:BAAALAAECgMIBQAAAA==.',Re='Recky:BAAALAAECgIIAgAAAA==.Reekplar:BAAALAADCgcIBwAAAA==.Rekenekon:BAAALAAECgYIBgAAAA==.Rethras:BAAALAAECgcIBwAAAA==.Reínhardt:BAAALAADCggICAABLAADCggIEAALAAAAAA==.',Ri='Ribbe:BAAALAAECgMIAwAAAA==.Rinse:BAAALAADCggIGQAAAA==.Rirgoun:BAAALAAECgYIDwAAAA==.Ritual:BAAALAADCgYIBgABLAAECgcIFgAbAI0eAA==.',Ro='Rogueslave:BAAALAAECgMIAwAAAA==.Rohân:BAAALAADCggICAAAAA==.Rotkwa:BAAALAAECgYIDQAAAA==.',Ru='Rumzedh:BAABLAAECoElAAIHAAgIORJnVAD0AQAHAAgIORJnVAD0AQAAAA==.',Ry='Ryorek:BAAALAAECgUIDQAAAA==.',['Rä']='Rät:BAAALAADCggICAAAAA==.',['Rö']='Röllí:BAAALAAECgYIAwAAAA==.',Sa='Safyra:BAABLAAECoElAAIMAAgIqw2KQACVAQAMAAgIqw2KQACVAQAAAA==.Saihtam:BAABLAAECoEVAAINAAcILh3CLAA0AgANAAcILh3CLAA0AgAAAA==.Saintcube:BAAALAADCggIDwAAAA==.Saitha:BAAALAAECgcIEgAAAA==.Salendris:BAAALAADCgYIBgAAAA==.Salroma:BAABLAAECoEcAAIiAAcIgARTlQD/AAAiAAcIgARTlQD/AAAAAA==.Samathe:BAAALAAECgYIDwAAAA==.Samsræv:BAAALAADCggICAAAAA==.Sanitari:BAAALAADCggIHQAAAA==.Santamansdr:BAAALAAECgcIBwAAAA==.Santder:BAABLAAECoEdAAImAAcI+iW7EgD2AgAmAAcI+iW7EgD2AgAAAA==.Saqib:BAABLAAECoEVAAIDAAcI8gnSWwBqAQADAAcI8gnSWwBqAQAAAA==.Saruto:BAAALAADCgEIAQAAAA==.Saty:BAABLAAECoEZAAISAAcImBaQEwDWAQASAAcImBaQEwDWAQAAAA==.',Sc='Schnoofis:BAAALAADCggICAABLAAFFAIIAgALAAAAAA==.Schuggs:BAAALAADCgcICQAAAA==.Scopydead:BAABLAAECoEfAAITAAgIxxjfQQBLAgATAAgIxxjfQQBLAgAAAA==.Scopyfo:BAAALAAECgcIBwAAAA==.Scousepowa:BAAALAADCggIDQAAAA==.',Se='Selengosa:BAAALAAECgYIEAAAAA==.Senzaemon:BAAALAAECggIEAAAAA==.Sephira:BAAALAADCgUIBQABLAAECgcIGQAcALAfAA==.Serune:BAABLAAECoEbAAIVAAcImB3JDgA6AgAVAAcImB3JDgA6AgAAAA==.',Sh='Shaa:BAAALAAECgcIEgAAAA==.Shabam:BAAALAADCggIFAAAAA==.Shadowclear:BAAALAADCgQIBAAAAA==.Shadowleaves:BAAALAADCgMIAwAAAA==.Shakaralakar:BAAALAAECgYIDAAAAA==.Shamagus:BAABLAAECoEbAAIlAAcIDRrFCwAGAgAlAAcIDRrFCwAGAgAAAA==.Shankyy:BAAALAADCgcICQAAAA==.Shao:BAAALAADCggICAAAAA==.Shaoli:BAAALAADCgcIDQAAAA==.Shardina:BAABLAAECoEWAAIeAAcIjQ4HTwBwAQAeAAcIjQ4HTwBwAQAAAA==.Shibury:BAAALAADCggIDgAAAA==.Shinobuchan:BAAALAADCggIEgAAAA==.Shinypants:BAAALAAECgEIAQAAAA==.Shiori:BAAALAAECgUIDAAAAA==.Shiorí:BAAALAAECgcIDgAAAA==.Shnack:BAAALAAECggIEwAAAA==.Shocksin:BAAALAADCgEIAQABLAAECgcIGgAjABYgAA==.Shwinky:BAAALAADCggIDQABLAAFFAUIEAASAPUeAA==.Shyana:BAABLAAECoEaAAIRAAcIIA0PcgCJAQARAAcIIA0PcgCJAQAAAA==.Shïo:BAAALAAECgYICQAAAA==.Shïorií:BAAALAAECgYICAAAAA==.',Si='Sidnee:BAAALAAECgQICgAAAA==.Sinxuel:BAAALAAECgMIBQAAAA==.',Sk='Skydin:BAAALAAECgIIAgAAAA==.Skyolex:BAAALAAECgUIBwAAAA==.',Sm='Smokinggold:BAAALAADCggIDgAAAA==.',So='Sokratis:BAAALAADCgQIBAAAAA==.Soulo:BAAALAADCggIEgAAAA==.',Sp='Span:BAABLAAECoEiAAITAAcIJCDRMgB9AgATAAcIJCDRMgB9AgAAAA==.Spellfire:BAABLAAECoEZAAIHAAcIvxWxUQD7AQAHAAcIvxWxUQD7AQABLAAFFAQIBwAQAOYEAA==.Spéxx:BAAALAADCgMIAwABLAAECgYIFwATAIchAA==.',St='Stolpiller:BAAALAADCggICgABLAAECgMIAwALAAAAAA==.Stonedpally:BAAALAAECgUIBQAAAA==.Stooned:BAAALAADCgMIAwAAAA==.Stormhawk:BAAALAADCggIHQAAAA==.Sttry:BAABLAAECoEbAAIOAAcIWhYNbQDZAQAOAAcIWhYNbQDZAQAAAA==.',Su='Survikpriest:BAAALAADCgYIBgAAAA==.',Sy='Sycus:BAAALAAECgYICgAAAA==.Synik:BAAALAADCgcIBwAAAA==.Synogosa:BAAALAADCggIEAAAAA==.Sytek:BAAALAAECgYIDAAAAA==.',Sz='Szczena:BAABLAAECoEXAAIYAAgIvhclFABnAgAYAAgIvhclFABnAgAAAA==.',['Sä']='Säcken:BAABLAAECoEdAAIFAAgIJCNfCgApAwAFAAgIJCNfCgApAwAAAA==.',['Sí']='Sílvara:BAAALAADCggICQAAAA==.',['Só']='Sónny:BAAALAAECgIIAgAAAA==.',Ta='Tahel:BAAALAADCgEIAQAAAA==.Taiger:BAAALAADCggIEAAAAA==.Tamerall:BAAALAADCggICAAAAA==.Tanaleif:BAAALAAECgcIDwAAAA==.Tarheelhal:BAAALAAECgYICgAAAA==.Tauryn:BAABLAAECoEUAAIOAAgImR7IMgB5AgAOAAgImR7IMgB5AgABLAAFFAUIDAABAMIZAA==.Tazlock:BAAALAADCggIFAAAAA==.Tazos:BAABLAAECoEXAAITAAcIziJyQQBNAgATAAcIziJyQQBNAgAAAA==.',Te='Teddy:BAAALAADCggIDQAAAA==.Teil:BAABLAAECoEZAAIeAAcIhhZlNwDVAQAeAAcIhhZlNwDVAQAAAA==.Telica:BAAALAADCgIIAgAAAA==.Templaar:BAABLAAECoEVAAIkAAcI/heTHAD5AQAkAAcI/heTHAD5AQAAAA==.Tencanto:BAAALAADCggIFgAAAA==.Tenskwatawa:BAAALAAECgIIAgABLAAECgcIFgABACAfAA==.',Th='Thaarius:BAAALAAECgUICQAAAA==.Thalzera:BAABLAAECoEbAAIHAAcISxSsZQDIAQAHAAcISxSsZQDIAQAAAA==.Therigamesh:BAAALAAECgYIDgAAAA==.Thesis:BAABLAAECoEYAAIOAAcIywm4owBvAQAOAAcIywm4owBvAQAAAA==.Thorwaler:BAAALAAECggICQABLAAECggIFAAQAHwFAA==.Thugsley:BAAALAADCgcIBwABLAAECgcIIgANABweAA==.',Ti='Ticcus:BAAALAADCggICAABLAAECgMIAwALAAAAAA==.Timotheus:BAAALAAECgYIBwAAAA==.',To='Toon:BAABLAAECoEbAAIHAAcIVR+kLwBxAgAHAAcIVR+kLwBxAgAAAA==.Totemtree:BAABLAAECoEfAAMNAAgI2AyOfQBEAQANAAcISg6OfQBEAQADAAEIYwKWtAAIAAAAAA==.',Tr='Trixxii:BAAALAAECgcIAwAAAQ==.',Ts='Tsú:BAAALAADCggICQAAAA==.',Tu='Tuffsmonk:BAAALAAECgYIDAAAAA==.Tuomusissi:BAAALAADCggIEAAAAA==.',Tw='Tweetholinka:BAAALAAECggIEQAAAA==.',Ty='Tyranuel:BAACLAAFFIEFAAIkAAIIqQ8TEwCXAAAkAAIIqQ8TEwCXAAAsAAQKgSIAAiQACAhpGlkRAF4CACQACAhpGlkRAF4CAAAA.Tyrisflare:BAABLAAECoEWAAImAAcIHiNXGQDJAgAmAAcIHiNXGQDJAgAAAA==.',['Tí']='Tíkkí:BAAALAADCgIIAgAAAA==.',['Tú']='Túrnz:BAAALAAECgYIDQABLAAECggIGQAOAN4OAA==.',Ul='Ulxar:BAAALAADCggIFwAAAA==.',Un='Undercutter:BAAALAADCgUIBgAAAA==.Unnown:BAAALAADCggIFgAAAA==.',Ur='Urïel:BAAALAAECgUIBgAAAA==.',Uz='Uzil:BAAALAADCgYIBgABLAAECgYIEQALAAAAAA==.Uzilmonk:BAAALAADCggICAABLAAECgYIEQALAAAAAA==.Uzilsham:BAAALAAECgYIEQAAAA==.',Va='Vadeth:BAABLAAECoEVAAIkAAgIfw2hMgBmAQAkAAgIfw2hMgBmAQAAAA==.Vaelar:BAAALAAECgEIAQAAAA==.Vaelira:BAAALAADCgYICwAAAA==.Valat:BAAALAAECgIIAgABLAAECggIEwALAAAAAA==.Vampìrella:BAAALAADCggIGgAAAA==.Vanília:BAABLAAECoEYAAINAAcIrCKwFACuAgANAAcIrCKwFACuAgAAAA==.Varamas:BAAALAADCgUIBQAAAA==.',Ve='Veltigor:BAAALAAECggICAAAAA==.',Vi='Vild:BAAALAADCgcICAAAAA==.',Vo='Vodkadrac:BAABLAAECoEaAAIjAAcIIg04LgCKAQAjAAcIIg04LgCKAQAAAA==.Voidpræst:BAAALAADCgMIAwAAAA==.Volantie:BAABLAAECoEXAAIIAAcIchQwDgCvAQAIAAcIchQwDgCvAQAAAA==.',Vr='Vrugdush:BAABLAAECoEiAAMbAAcIAiHxFQBNAgAbAAcIYR/xFQBNAgAmAAcIyBxoLgBFAgAAAA==.',Vu='Vulpestra:BAAALAADCgEIAQAAAA==.',['Vó']='Vórag:BAAALAAECggICAAAAA==.',Wa='Walkingdrunk:BAAALAAECggIDAAAAA==.Walnor:BAAALAADCggICgAAAA==.Walsey:BAABLAAECoEYAAISAAcIcgksIgAlAQASAAcIcgksIgAlAQAAAA==.Waring:BAAALAAECgEIAQAAAA==.Waxy:BAACLAAFFIEGAAIDAAIIdBngFgCmAAADAAIIdBngFgCmAAAsAAQKgRQAAgMACAg3I4MNAA8DAAMACAg3I4MNAA8DAAAA.',Wh='Whysober:BAAALAADCgIIAgABLAAECgYICgALAAAAAA==.',Wo='Wolfinstein:BAAALAADCgUIBQAAAA==.Woofrawrmeow:BAAALAADCggIDgAAAA==.',Wy='Wyrmbane:BAAALAAECgQICQAAAA==.',Xa='Xaziala:BAAALAADCggIDgAAAA==.',Xe='Xelrath:BAABLAAECoEcAAIkAAcIowfcOwAwAQAkAAcIowfcOwAwAQAAAA==.',Xy='Xyeet:BAABLAAECoEYAAMgAAcIrw7gBwCxAQAgAAcIrw7gBwCxAQARAAEI6wB46AAJAAAAAA==.',Ya='Yahenni:BAAALAADCgYIBgABLAAECgYIEQALAAAAAA==.Yasu:BAAALAAECgEIAQAAAA==.',Yo='Yogibear:BAAALAAECggIDgAAAA==.Yollidan:BAABLAAECoEfAAIQAAgI9xldEQByAgAQAAgI9xldEQByAgAAAA==.Yossarin:BAAALAADCgcIBwAAAA==.',['Yö']='Yönvartija:BAAALAAECgcIEwAAAA==.',Za='Zab:BAAALAAECgIIAgABLAAECggIEwALAAAAAA==.Zaephod:BAAALAAECgYICQAAAA==.Zarwollf:BAAALAAECgYIEQAAAA==.Zazalamel:BAAALAAECgIIAgAAAA==.',Ze='Zeddiah:BAAALAADCggIDwAAAA==.Zelraa:BAAALAAECgUICgAAAA==.Zentia:BAAALAADCgMIAwAAAA==.Zerrodale:BAAALAADCgEIAQABLAAECgcIFQAQADYGAA==.Zethgor:BAAALAAECgYIEAABLAAFFAIIAgALAAAAAQ==.Zetsuix:BAAALAADCgUIBgAAAA==.',Zi='Zilyara:BAAALAAECgYICwAAAA==.',Zo='Zonotte:BAAALAADCgQIBAAAAA==.',Zu='Zuldaz:BAABLAAECoEbAAINAAgI0Q3DZwB7AQANAAgI0Q3DZwB7AQAAAA==.',['Ár']='Árnyróka:BAAALAAECgYIBgAAAA==.',['Ás']='Áshur:BAAALAAECgYIBgABLAAECggIGQAOAN4OAA==.Ásvaldr:BAAALAADCgcIBwABLAAECgIIAgALAAAAAA==.',['Év']='Éva:BAAALAAECgIIAgABLAAECgUIDgALAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end