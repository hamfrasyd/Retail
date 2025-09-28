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
 local lookup = {'Monk-Windwalker','Monk-Mistweaver','Shaman-Restoration','DemonHunter-Havoc','Warlock-Destruction','Mage-Frost','Druid-Guardian','Rogue-Outlaw','Unknown-Unknown','DemonHunter-Vengeance','Warlock-Demonology','Rogue-Subtlety','Priest-Shadow','Druid-Restoration','Druid-Balance','Warrior-Fury','Paladin-Retribution','Warrior-Arms','Shaman-Elemental','Priest-Holy','Warrior-Protection','Warlock-Affliction','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Evoker-Preservation','Paladin-Holy','Paladin-Protection','Druid-Feral','Evoker-Devastation','DeathKnight-Frost','DeathKnight-Blood',}; local provider = {region='EU',realm='Naxxramas',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adelant:BAAALAADCgcIDwAAAA==.',Aj='Ajax:BAAALAAECgIIAgAAAA==.',Al='Alduins:BAABLAAECoEpAAMBAAgImyEMCgDZAgABAAgImyEMCgDZAgACAAQIgBLCOACoAAAAAA==.',Ar='Argowal:BAAALAADCgUIBQAAAA==.Argéa:BAACLAAFFIEHAAIDAAIIJRUGLACEAAADAAIIJRUGLACEAAAsAAQKgUoAAgMACAhLIWQQANACAAMACAhLIWQQANACAAAA.Argøs:BAAALAAECgIIAgAAAA==.',At='Athénaïsse:BAAALAAECgMIBAAAAA==.',Ay='Ayowarr:BAAALAAFFAEIAQAAAA==.',Ba='Baelia:BAABLAAECoEsAAIEAAgInh+DJACtAgAEAAgInh+DJACtAgAAAA==.Bannya:BAAALAAECgYICgAAAA==.Barago:BAAALAADCgcIBwAAAA==.',Be='Bell:BAABLAAECoElAAIFAAgIqh1zHQC5AgAFAAgIqh1zHQC5AgAAAA==.Bellagay:BAAALAADCgUIBQAAAA==.',Bj='Bjørn:BAABLAAECoEdAAIGAAgIfxCHJwDFAQAGAAgIfxCHJwDFAQAAAA==.',Br='Bradou:BAAALAADCggICAAAAA==.',Bu='Burstian:BAAALAADCgcIBwAAAA==.',['Bé']='Béliâl:BAAALAADCggICQAAAA==.',Ca='Café:BAAALAADCgcIBwAAAA==.',Ch='Chibanistyle:BAAALAADCgIIAgABLAAECggILAAHADQVAA==.',Ci='Cignale:BAAALAADCggICAAAAA==.Citrâ:BAAALAAECgEIAQAAAA==.',Co='Corviuse:BAAALAADCgYICAABLAAECggIKQABAJshAA==.',Da='Darcell:BAAALAAECgIIBAAAAA==.Darkellnight:BAAALAAECgUICwAAAA==.Darkrahir:BAAALAADCggIGwAAAA==.Dayron:BAAALAAECgUIBQAAAA==.',Di='Dindin:BAAALAAECgEIAQABLAAECggIKQABAJshAA==.',Do='Dolkian:BAACLAAFFIEHAAIIAAIIiBqiAgCuAAAIAAIIiBqiAgCuAAAsAAQKgUAAAggACAh+JLsAAFYDAAgACAh+JLsAAFYDAAAA.Dotlala:BAAALAADCggIFgABLAAECgYIEQAJAAAAAA==.',Dr='Dràcùla:BAABLAAECoEUAAMKAAYI1Rk1GwCxAQAKAAYI1Rk1GwCxAQAEAAIIdBdx8wCKAAAAAA==.',Du='Dudula:BAAALAADCggICAAAAA==.',['Dä']='Därmâak:BAACLAAFFIEKAAILAAIIfCW7AwDbAAALAAIIfCW7AwDbAAAsAAQKgUgAAwsACAgtJtUAAHcDAAsACAgtJtUAAHcDAAUAAgh0HSq2AJsAAAAA.',Ec='Eckosia:BAAALAADCgYICAABLAAECggIIwAMAAYiAA==.',Ei='Eiïziïoör:BAAALAADCggIBgAAAA==.',El='Elsas:BAAALAAECgYIBgAAAA==.Elye:BAABLAAECoEWAAINAAcIohnTMgDfAQANAAcIohnTMgDfAQAAAA==.',Et='Etaem:BAABLAAECoEbAAIDAAgIdxllKQBJAgADAAgIdxllKQBJAgAAAA==.',Fl='Floda:BAAALAAECgMIAwAAAA==.',Fr='Frèqz:BAAALAAECgUIDAAAAA==.',Gd='Gd:BAAALAAECggIEwAAAA==.',Go='Goldship:BAAALAADCgcIBwAAAA==.',Gr='Grao:BAAALAAECgYIBgAAAA==.Gripsoù:BAACLAAFFIEGAAIOAAIIVgWOLQB0AAAOAAIIVgWOLQB0AAAsAAQKgRQAAw4ACAjDErs4AMgBAA4ACAjDErs4AMgBAA8ABAjkE81iAOsAAAAA.Grøk:BAAALAAECgIIAgAAAA==.',Ha='Hawkhart:BAACLAAFFIEGAAIQAAIITRw8GQCwAAAQAAIITRw8GQCwAAAsAAQKgSUAAhAACAhZIlAPABUDABAACAhZIlAPABUDAAAA.',Hi='Hindowe:BAAALAAECgYIDAAAAA==.',Ho='Horeat:BAAALAAECgMIBQAAAA==.',Hy='Hymèrion:BAABLAAECoEdAAIRAAYIBQ9TtABbAQARAAYIBQ9TtABbAQAAAA==.Hyujin:BAAALAADCgYIBgAAAA==.',Is='Isaal:BAAALAAECgIIAgAAAA==.',Ja='Jahin:BAAALAADCggIDgABLAAECgYIDAAJAAAAAA==.',Je='Jenna:BAAALAADCgcIBwAAAA==.',Ka='Kalhaneamnel:BAAALAAECgYIEQAAAA==.Kame:BAABLAAECoEfAAMQAAgIFBnpLABWAgAQAAgIFBnpLABWAgASAAQIbgwwIwCxAAAAAA==.Kaonix:BAAALAAECgQIBwAAAA==.Kashoo:BAABLAAECoEcAAITAAcIShyVKABNAgATAAcIShyVKABNAgAAAA==.Katralis:BAAALAAECgYIDQAAAA==.Kazumi:BAABLAAECoEjAAIMAAgIBiJgBQDkAgAMAAgIBiJgBQDkAgAAAA==.',Kd='Kdaarlek:BAAALAADCggICAABLAAECgUIDAAJAAAAAA==.',Ke='Keeree:BAAALAADCggIJAABLAADCggIJwAJAAAAAA==.Keereejaune:BAAALAADCggIJwAAAA==.Keith:BAAALAAECgMIBgAAAA==.',Ki='Killcrow:BAAALAADCgcIBwAAAA==.',Kl='Klaid:BAAALAAECgIIAgAAAA==.Klayn:BAAALAAECgUICwAAAA==.',Ko='Koussipala:BAAALAAECgYIEQAAAA==.',Kr='Kragg:BAAALAAECgMIAwAAAA==.Kravenn:BAAALAADCgQIBgAAAA==.Krokmoo:BAABLAAECoEfAAIBAAcIKxeKHwDTAQABAAcIKxeKHwDTAQAAAA==.Krush:BAAALAAECgcIEwAAAA==.',Ku='Kurumii:BAABLAAECoEgAAIUAAgIIRdCJgA1AgAUAAgIIRdCJgA1AgAAAA==.',['Kä']='Käyo:BAABLAAECoEZAAMVAAcInBglIgDvAQAVAAcInBglIgDvAQAQAAYIdQeTigAfAQAAAA==.',['Kø']='Kørö:BAABLAAECoEeAAMFAAgIchEXSgDkAQAFAAgIchEXSgDkAQAWAAMI2wtnJQCgAAAAAA==.',La='Lazare:BAABLAAECoElAAIDAAgIzhljLgA0AgADAAgIzhljLgA0AgAAAA==.',Le='Lesacrifié:BAABLAAECoEgAAIBAAcINyMFDwCNAgABAAcINyMFDwCNAgAAAA==.',Lf='Lfchijibuff:BAAALAADCggICQAAAA==.',Li='Lindink:BAAALAADCgEIAQAAAA==.',Lo='Louboutîne:BAAALAADCggIGAAAAA==.',Lu='Lucïûs:BAAALAADCgcIBwABLAADCgcICQAJAAAAAA==.',Ma='Magicunicorn:BAABLAAECoEiAAQXAAYIRyB2KwAGAgAXAAYIZB52KwAGAgAYAAYI0BdzDwCEAQAZAAMIPhCt4ACoAAAAAA==.Mannisam:BAABLAAECoEYAAIPAAYI5BfjQgB3AQAPAAYI5BfjQgB3AQAAAA==.Mark:BAAALAAECgYIBgAAAA==.',Mo='Morcroft:BAABLAAECoEYAAIZAAgI5SAaFQDlAgAZAAgI5SAaFQDlAgAAAA==.Mortnoïre:BAABLAAECoEYAAIMAAcIKg8gGwCQAQAMAAcIKg8gGwCQAQAAAA==.',Na='Nacl:BAABLAAECoEYAAIRAAgIrgk1qgBtAQARAAgIrgk1qgBtAQAAAA==.Nahï:BAAALAADCggICAABLAAECgMIBAAJAAAAAA==.Naka:BAAALAAECgUIBQAAAA==.Nattilà:BAAALAAECgMIBAAAAA==.',Ni='Nihiil:BAAALAADCgcIBwAAAA==.Nik:BAABLAAECoEXAAIKAAcILg3UKwAiAQAKAAcILg3UKwAiAQAAAA==.',Ny='Nythis:BAACLAAFFIEGAAILAAIIhBVkDgCgAAALAAIIhBVkDgCgAAAsAAQKgSsAAwsACAgHIUIFAP4CAAsACAgHIUIFAP4CAAUAAQj9EmrUAD8AAAEsAAUUBAgHABkAXBUA.Nywen:BAABLAAECoEeAAIaAAgI4RXnDgATAgAaAAgI4RXnDgATAgAAAA==.Nywiz:BAAALAAECgMIAwAAAA==.',['Né']='Nébeleste:BAAALAADCgIIAgAAAA==.',Od='Od:BAAALAADCgcIDgAAAA==.',Or='Orchidna:BAABLAAECoE1AAIbAAYI6RT5LACOAQAbAAYI6RT5LACOAQAAAA==.Orionhunter:BAABLAAECoEgAAIZAAgI8xKwYADEAQAZAAgI8xKwYADEAQAAAA==.Ork:BAAALAADCggIDgABLAAECggIKgAPAAciAA==.',Oz='Ozî:BAABLAAECoEYAAIYAAgITg4CCQD9AQAYAAgITg4CCQD9AQAAAA==.',Pa='Panoranixme:BAABLAAECoEfAAMPAAYIixEzUgA1AQAPAAYIixEzUgA1AQAOAAUIlBHCcAAEAQAAAA==.',Pi='Pichtou:BAAALAAECgMIAwAAAA==.Pilierdrack:BAAALAADCgUIBQABLAAECggIGwACABMZAA==.Piliermono:BAABLAAECoEbAAICAAgIExkwDwBOAgACAAgIExkwDwBOAgAAAA==.Piratesamy:BAABLAAECoEYAAIFAAYIaQ+JhQA5AQAFAAYIaQ+JhQA5AQAAAA==.',Po='Poildecarrot:BAAALAAECgYIDgAAAA==.Popsmoke:BAAALAADCgEIAQAAAA==.Powertpa:BAABLAAECoElAAMcAAcIySKMCgCnAgAcAAcIySKMCgCnAgARAAYI1hxMcQDXAQAAAA==.',Pr='Prettyworgen:BAAALAADCgcICQAAAA==.Prédatørz:BAABLAAECoEVAAIXAAgICyCSDQDrAgAXAAgICyCSDQDrAgAAAA==.',Ra='Raituine:BAAALAAECgYIDAAAAA==.Razemibane:BAAALAAECgcIDgAAAA==.',Re='Redkov:BAAALAADCggIDQAAAA==.',Ri='Ridepré:BAAALAADCgcIDQAAAA==.Risson:BAAALAADCggIDwABLAAECgUIDAAJAAAAAA==.',Ro='Rokudastone:BAAALAAECgMIBwAAAA==.Ronn:BAAALAADCgcIEAAAAA==.',Sa='Saman:BAAALAAECgcIDAAAAA==.Samdécoiffe:BAAALAAECgYIBgAAAA==.Samdémonte:BAABLAAECoEaAAMVAAYI7SK2FgBOAgAVAAYI7SK2FgBOAgASAAQIOwZ7JQCZAAAAAA==.Samular:BAABLAAECoEiAAMRAAYIkiGqpgBzAQARAAYIYRGqpgBzAQAcAAYIkiGBOgAGAQAAAA==.Samybrother:BAAALAAECgYIDAAAAA==.Satanana:BAAALAAECgYIDwAAAA==.',Se='Seilo:BAAALAADCgQIBAAAAA==.Sephe:BAAALAADCggICAABLAAECggIKQABAJshAA==.Serpenta:BAAALAADCgYIBgAAAA==.',Sh='Shàølin:BAAALAAECgYIBgAAAA==.Shîn:BAABLAAECoEaAAINAAcIgiGyGQCIAgANAAcIgiGyGQCIAgABLAAECgYIFgAdAI0kAA==.',Si='Sidelrine:BAAALAADCggIDQAAAA==.',Sk='Skillbirds:BAAALAAECgQIBwAAAA==.',Sm='Smaûg:BAABLAAECoEdAAIeAAgIuAKlRwDaAAAeAAgIuAKlRwDaAAAAAA==.',So='Solïs:BAAALAAECgYIDQAAAA==.Sowen:BAAALAADCgQIBAABLAAFFAIIBwAZALkfAA==.',St='Starfall:BAAALAAECggIDwAAAA==.Stix:BAAALAADCgcICgABLAAECgMIAwAJAAAAAA==.',Su='Supersønic:BAABLAAECoEXAAIfAAcIwQha9ADzAAAfAAcIwQha9ADzAAAAAA==.',['Sõ']='Sõwen:BAACLAAFFIEHAAIZAAIIuR+mIACkAAAZAAIIuR+mIACkAAAsAAQKgUcAAhkACAg9JvEFAFADABkACAg9JvEFAFADAAAA.',Ta='Tamjid:BAAALAADCggILQAAAA==.Tatanki:BAABLAAECoEUAAMZAAcI4SBTPgAnAgAZAAcI4SBTPgAnAgAXAAEIxgGzvgAaAAAAAA==.Taurhel:BAAALAADCgcIBwAAAA==.',Tb='Tbest:BAAALAAECgYICgAAAA==.',Te='Teldar:BAAALAADCggICAAAAA==.Terranova:BAAALAADCgYIBwAAAA==.',To='Tonatiuh:BAAALAADCggICAAAAA==.Tonbot:BAAALAAECgYIDAAAAA==.',Tr='Trahin:BAAALAADCgMIAwAAAA==.',Tu='Turtlebif:BAAALAADCggICQABLAAECgYIBgAJAAAAAA==.',Ty='Tygr:BAAALAAECggIAgAAAA==.Typhoons:BAAALAADCgQIBAAAAA==.Tyraufarm:BAACLAAFFIEIAAIgAAMIoRdMBgDiAAAgAAMIoRdMBgDiAAAsAAQKgSwAAiAACAieIV8FAAADACAACAieIV8FAAADAAAA.',Vi='Visporis:BAAALAADCgMIAwAAAA==.',Vu='Vucépoin:BAAALAAECgcIBwAAAA==.',Wa='Warofraise:BAAALAAECgIIAgAAAA==.',Wo='Wolfuwu:BAAALAAECgYIDAAAAA==.',Xu='Xulino:BAAALAADCggIDQABLAAECgUIBQAJAAAAAA==.',Yl='Ylanel:BAAALAAECgUIBQABLAAECgYIDwAJAAAAAA==.',Za='Zajostücsök:BAAALAADCgYIBgAAAA==.',Ze='Zemonk:BAAALAADCggICAAAAA==.',Zo='Zolahica:BAAALAADCgYIBgAAAA==.Zolahïsse:BAAALAAECgcIEAAAAA==.',['Ës']='Ëssa:BAAALAAECgEIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end