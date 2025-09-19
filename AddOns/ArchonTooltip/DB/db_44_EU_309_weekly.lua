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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','DeathKnight-Blood','Mage-Arcane','Monk-Brewmaster','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Druid-Balance','Mage-Fire','Evoker-Preservation','Paladin-Holy','Paladin-Retribution','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Hunter-BeastMastery','Evoker-Devastation','Shaman-Restoration','Paladin-Protection','Druid-Feral','Priest-Discipline','DeathKnight-Unholy','DeathKnight-Frost','Rogue-Outlaw','Warrior-Fury','Rogue-Assassination','Monk-Mistweaver','Priest-Shadow','Mage-Frost','Rogue-Subtlety',}; local provider = {region='EU',realm='LaughingSkull',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Absoul:BAAALAADCgcICQAAAA==.',Ac='Acidxoxo:BAAALAADCggIDwAAAA==.',Ad='Ada:BAAALAADCggICAAAAA==.',Al='Aleksz:BAAALAADCggICAAAAA==.Alexxya:BAAALAAECgQIBAAAAA==.Alina:BAAALAADCggIDgAAAA==.Allannia:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Alzerax:BAAALAAECgUIBQAAAA==.',Am='Amosel:BAAALAAECgcIBwAAAA==.',An='Anatolia:BAAALAADCggIDgAAAA==.Animaknight:BAAALAAECggIAwAAAA==.',Ar='Archimedes:BAAALAADCgYIBgAAAA==.',Au='Aurum:BAAALAAECgQIBgAAAA==.',Aw='Aw:BAAALAAECgIIAgABLAAFFAIIBgACAFsZAA==.Awoken:BAAALAAECggICAAAAA==.',Ax='Axewrath:BAABLAAECoEbAAIDAAgI4h80BADWAgADAAgI4h80BADWAgAAAA==.Axi:BAABLAAECoEaAAIEAAgIpB7gFQCwAgAEAAgIpB7gFQCwAgAAAA==.',Ba='Balddozer:BAABLAAECoEfAAIFAAgIix6ZBQCzAgAFAAgIix6ZBQCzAgABLAAFFAYIEQAGAP4TAA==.Barbrodoom:BAABLAAECoEcAAIHAAgIcB/CDADdAgAHAAgIcB/CDADdAgAAAA==.',Be='Bevaragåsen:BAAALAADCgcIBwAAAA==.',Bi='Bigblast:BAACLAAFFIEFAAIEAAMIKxUvCAANAQAEAAMIKxUvCAANAQAsAAQKgRsAAgQACAiYItEMAPoCAAQACAiYItEMAPoCAAEsAAUUBggOAAgAUR8A.Bigdruid:BAABLAAECoEXAAIJAAgIMxpBEwBQAgAJAAgIMxpBEwBQAgABLAAFFAYIDgAIAFEfAA==.Bigpee:BAACLAAFFIEOAAIIAAYIUR9PAABTAgAIAAYIUR9PAABTAgAsAAQKgR4AAggACAivJmsAAIEDAAgACAivJmsAAIEDAAAA.',Bl='Blayze:BAAALAADCgcIDAAAAA==.Blitz:BAAALAADCgcIBwAAAA==.Bluewarlock:BAABLAAECoEaAAMEAAgISSQnCAAjAwAEAAgISSQnCAAjAwAKAAEIpSEAAAAAAAAAAA==.',Bo='Boutacum:BAAALAAECgYIBgAAAA==.',Br='Brena:BAAALAAECgMIBwAAAA==.Brenson:BAAALAAECgUICgAAAA==.Bromire:BAAALAADCgYIBgABLAAECgUICgABAAAAAA==.',Bu='Buldog:BAAALAADCgcICAAAAA==.Bullydozer:BAAALAAFFAIIAgABLAAFFAYIEQAGAP4TAA==.Burnings:BAABLAAECoEbAAIEAAgI6Rh/IgBWAgAEAAgI6Rh/IgBWAgAAAA==.',By='Byrrah:BAAALAADCgcIIAAAAA==.',['Bü']='Bürstbürn:BAAALAADCggICAAAAA==.',Ca='Caeruleus:BAABLAAECoEcAAILAAgIiyI8AQApAwALAAgIiyI8AQApAwAAAA==.',Ce='Cebiz:BAAALAADCgQIBAAAAA==.Centyfive:BAAALAADCggIDgAAAA==.',Ch='Chielsmaider:BAAALAADCgMIAwAAAA==.Chlochii:BAAALAAECggIEgAAAA==.Choke:BAABLAAECoEYAAMMAAgI8CD/AgDtAgAMAAgI8CD/AgDtAgANAAEIeRVHvQBHAAAAAA==.',Co='Cobaltine:BAAALAAECgYIEQAAAA==.Coldbeer:BAAALAAECgIIAgAAAA==.',Cr='Craitz:BAAALAAECgMIAwAAAA==.Craitza:BAAALAAECgUIBQAAAA==.Crusherdruid:BAABLAAECoEUAAIOAAgIvx5PDgBrAgAOAAgIvx5PDgBrAgAAAA==.',Da='Danderion:BAAALAAECgUIBgAAAA==.Darkweaver:BAAALAAECgIIAwAAAA==.Daunt:BAABLAAECoEWAAIIAAgIbSQeBQAZAwAIAAgIbSQeBQAZAwAAAA==.',De='Deatheclipse:BAAALAAECgIIAwAAAA==.Deathguard:BAAALAADCggICAAAAA==.Deathmones:BAABLAAECoEZAAIHAAgIWiBxCwDsAgAHAAgIWiBxCwDsAgAAAA==.Deathwish:BAAALAADCggICAAAAA==.Defect:BAAALAADCgEIAQAAAA==.Defectx:BAAALAADCggICAAAAA==.Demongoon:BAAALAAECggIEwAAAA==.Dendario:BAAALAAECgQIBAAAAA==.',Dh='Dholy:BAABLAAECoEWAAMPAAgIrxycDADzAQAQAAgI6BPZMAAEAgAPAAYIXyGcDADzAQABLAAFFAYIDwADAB4kAA==.',Di='Didntask:BAACLAAFFIEPAAIOAAYIehZyAAAdAgAOAAYIehZyAAAdAgAsAAQKgRcAAg4ACAhfITMEAPsCAA4ACAhfITMEAPsCAAAA.Dimonda:BAABLAAECoEbAAIRAAgIRCCwBwDpAgARAAgIRCCwBwDpAgAAAA==.Dimoond:BAAALAAECgMIBAABLAAECggIGwARAEQgAA==.Divinedaf:BAAALAADCggIFQAAAA==.',Dk='Dkangel:BAAALAADCgcICQAAAA==.Dkdozer:BAAALAAECgcICQABLAAFFAYIEQAGAP4TAA==.',Do='Dozydoo:BAAALAADCgUIBQAAAA==.',Dr='Dracodraco:BAACLAAFFIENAAMSAAYIohS7AACkAQASAAUInBG7AACkAQAIAAQIpBkNAgB1AQAsAAQKgSAAAwgACAjcJLsEAB8DAAgACAgII7sEAB8DABIACAgNJPAHABADAAAA.Draconorea:BAAALAAFFAIIAgABLAAFFAYIDQASAKIUAA==.Dracostralz:BAABLAAECoEbAAICAAgI4SI0CAATAwACAAgI4SI0CAATAwABLAAFFAYIDQASAKIUAA==.Dracothyr:BAACLAAFFIEGAAITAAIIsB28BwDDAAATAAIIsB28BwDDAAAsAAQKgR0AAhMACAgoIkEEACMDABMACAgoIkEEACMDAAAA.Dragonmaul:BAAALAAECgUIBwAAAA==.Drakeondeez:BAABLAAECoEUAAMTAAcIIBKXGgDNAQATAAcIIBKXGgDNAQALAAQIFg7JGQDMAAAAAA==.Dreadtotem:BAAALAAECggIAQAAAA==.',Du='Dunders:BAAALAADCggIDwABLAAECgUIBgABAAAAAA==.Durgus:BAABLAAECoEWAAIUAAgIzR6mCADJAgAUAAgIzR6mCADJAgAAAA==.',Dw='Dw:BAACLAAFFIEGAAICAAIIWxmlCwCpAAACAAIIWxmlCwCpAAAsAAQKgRUAAgIABwi4HpsYAE8CAAIABwi4HpsYAE8CAAAA.',Dz='Dzamino:BAAALAADCgYIBgAAAA==.',['Dø']='Dødsridderen:BAAALAADCgIIAgAAAA==.',Ea='Eatmyaura:BAABLAAECoEaAAMMAAcIARoVFADlAQAMAAcIARoVFADlAQAVAAEIExQaNwA9AAAAAA==.',Ei='Eiku:BAAALAAECggIEAAAAA==.',Ek='Ekuliser:BAABLAAECoEaAAIWAAgI9hk+BwBzAgAWAAgI9hk+BwBzAgAAAA==.',Em='Emu:BAAALAAECgQIBAAAAA==.',En='Enviwar:BAAALAAECgIIAgABLAAFFAcIFwAEAIkeAA==.',Es='Eskan:BAAALAADCggIEwAAAA==.',Ex='Exephia:BAAALAAECgYIBQAAAA==.',Fe='Feibo:BAAALAADCgYIBgAAAA==.Fetacheese:BAAALAAECgUIBQAAAA==.',Fl='Flaggermus:BAAALAADCgcICAAAAA==.',Fr='Frosty:BAABLAAECoEWAAIEAAgIph3uGgCLAgAEAAgIph3uGgCLAgAAAA==.Frostytips:BAABLAAECoEWAAIEAAgIGRk5KwAiAgAEAAgIGRk5KwAiAgAAAA==.Froxine:BAAALAADCgIIAgAAAA==.',Fu='Futtiwar:BAAALAADCggIDwAAAA==.',Fy='Fya:BAABLAAECoEdAAINAAgI4SM3BgBHAwANAAgI4SM3BgBHAwAAAA==.',Ga='Gamz:BAECLAAFFIEOAAMJAAYI1BmSAAD5AQAJAAUI7B6SAAD5AQAWAAQIWg0AAQA6AQAsAAQKgSwAAwkACAjVJjUAAJoDAAkACAjVJjUAAJoDABYACAhfHrsEAMQCAAAA.Gaozhan:BAAALAADCggICAAAAA==.Garamala:BAAALAAECggIEAABLAAECggIGgAUAJoZAA==.Garendor:BAAALAAECgUIBQAAAA==.',Ge='Gedebanger:BAAALAAFFAYIAgAAAA==.Geostigma:BAAALAADCggIFQAAAA==.',Gi='Gis:BAAALAAECgUIBQAAAA==.',Go='Gossykin:BAACLAAFFIEIAAIUAAQI6gw+AwAaAQAUAAQI6gw+AwAaAQAsAAQKgRgAAhQACAjzFcorANUBABQACAjzFcorANUBAAAA.',Gr='Gretha:BAAALAAECgQIBgAAAA==.Grimzau:BAAALAAECgYIDQAAAA==.',Gu='Gupuwarlock:BAAALAAFFAIIAgAAAA==.Guspriest:BAACLAAFFIEFAAMRAAMIsg+ACADgAAARAAMIMQWACADgAAAXAAIIlxW4AACpAAAsAAQKgRcAAxcACAjhIbAAABwDABcACAjhIbAAABwDABEACAgsEeskANwBAAAA.',Ha='Hawktuæh:BAAALAADCggICAAAAA==.',Hi='Hilga:BAAALAADCggIEAAAAA==.',Ho='Holyana:BAAALAAECgEIAgAAAA==.',Hu='Huntinit:BAAALAADCgcICgABLAAECggIGgAUAJoZAA==.',Hy='Hybridowner:BAAALAAECgYICwAAAA==.',Ic='Ice:BAAALAAECgIIAgABLAAECgQIBgABAAAAAA==.',Ig='Ignorebull:BAACLAAFFIERAAIGAAYI/hOmAAAJAgAGAAYI/hOmAAAJAgAsAAQKgR4AAgYACAgRI0IDACEDAAYACAgRI0IDACEDAAAA.',Iz='Izánami:BAAALAADCggICQAAAA==.',Je='Jeeves:BAAALAAECgUICAAAAA==.',Ju='Justfadelol:BAAALAAECgcICQAAAA==.Justus:BAAALAADCggICAAAAA==.',Ka='Karolain:BAAALAAECgcIEQAAAA==.Karén:BAAALAAECgcICwAAAA==.Kathael:BAAALAADCgcIFwAAAA==.Kazrii:BAAALAAECggIEQAAAA==.',Ke='Keb:BAABLAAECoEbAAMYAAgIIB+lCgBDAgAYAAcIdxqlCgBDAgAZAAcIoB5tNQAAAgAAAA==.Kebkeb:BAAALAAECgQIBAAAAA==.Keito:BAAALAADCgEIAQAAAA==.',Kh='Khornez:BAAALAAECgIIAgAAAA==.',Kn='Knex:BAAALAADCggIEAAAAA==.Knives:BAABLAAECoEcAAIaAAgIrht5AgCfAgAaAAgIrht5AgCfAgAAAA==.',Kr='Krigarson:BAAALAAECgQIBAABLAAECgYIDQABAAAAAA==.',Ku='Kungfupo:BAAALAADCgIIAgAAAA==.',La='Lariath:BAAALAAECggICAAAAA==.',Le='Leekolasse:BAAALAADCggICAAAAA==.Leif:BAAALAAECgMIBQAAAA==.Lensi:BAAALAAECgcIEQAAAA==.Lenso:BAAALAAECgYIDAABLAAECgcIEQABAAAAAA==.',Li='Lifar:BAAALAADCgQIBAAAAA==.Lilhunter:BAAALAADCgMIAwAAAA==.Lilsbank:BAABLAAECoEWAAIUAAcIoAulWQAgAQAUAAcIoAulWQAgAQAAAA==.Liss:BAAALAADCgYIBgAAAA==.',Lo='Lolba:BAABLAAECoEUAAIbAAcICiDUGQBMAgAbAAcICiDUGQBMAgAAAA==.Lollba:BAAALAADCgMIAwAAAA==.Lootti:BAAALAAECgQIBAAAAA==.Loti:BAAALAAECgcIEwAAAA==.Lovia:BAAALAAECgQIBAAAAA==.',Lu='Lucky:BAAALAAFFAYIEgAAAQ==.Luckymonkas:BAAALAAFFAIIBAABLAAFFAYIEgABAAAAAQ==.Luckyone:BAAALAAFFAMIAwABLAAFFAYIEgABAAAAAQ==.Luckytwo:BAAALAAFFAIIBAABLAAFFAYIEgABAAAAAQ==.Lulba:BAAALAAECgYICAAAAA==.Luntraria:BAAALAADCgcIDgABLAAECgYICQABAAAAAA==.Lurks:BAABLAAECoEXAAIQAAgI0iNiCAAsAwAQAAgI0iNiCAAsAwABLAAFFAQIDAAZACkiAA==.Lurx:BAACLAAFFIEMAAMZAAQIKSLgAwA3AQAZAAMI+CPgAwA3AQAYAAEIuxyrCQBnAAAsAAQKgR4AAxkACAgqJhUGADgDABkACAieJRUGADgDABgAAwi1IqohADwBAAAA.',['Lá']='Lácuna:BAABLAAECoEXAAIOAAgINxIeJAC5AQAOAAgINxIeJAC5AQAAAA==.',Ma='Malefice:BAAALAAECgYIBgABLAAECggIHQANAOEjAA==.Manded:BAAALAAECgIIAgABLAAECggIHgAJAGUlAA==.Mandedamus:BAAALAADCgcIBwAAAA==.Matdk:BAABLAAECoEVAAMZAAgIOxM3OwDpAQAZAAgIpRE3OwDpAQADAAIIhRakIACDAAAAAA==.Matthia:BAAALAADCggIFQAAAA==.Maugrim:BAAALAADCgcIBwAAAA==.',Mc='Mcmaistro:BAAALAAECgYIDQAAAA==.',Md='Mdmx:BAAALAADCgUIBQAAAA==.',Me='Melina:BAAALAAECggICwAAAA==.Meredy:BAABLAAECoEbAAIcAAgImBoxCwCiAgAcAAgImBoxCwCiAgAAAA==.Merrlin:BAAALAADCggIDwAAAA==.',Mi='Mijes:BAAALAADCggIEAAAAA==.Mikeyp:BAAALAAFFAQIBAAAAA==.Mikeypi:BAABLAAECoEYAAIRAAgIpiBVCADgAgARAAgIpiBVCADgAgAAAA==.Miloktor:BAAALAAECgYIEQAAAA==.Miloraddodik:BAAALAAECggIEQABLAAECggIGgAUAJoZAA==.Milosha:BAAALAADCggIDQAAAA==.Mirthshadow:BAABLAAECoEVAAIQAAgIVRXmTwCKAQAQAAgIVRXmTwCKAQAAAA==.',Mo='Monoroth:BAACLAAFFIEOAAINAAYIHhkzAABJAgANAAYIHhkzAABJAgAsAAQKgR4AAg0ACAg3JtcBAHoDAA0ACAg3JtcBAHoDAAAA.Monstrul:BAAALAADCgIIBAAAAA==.Mopsi:BAACLAAFFIEFAAIEAAMIeRvtBgAdAQAEAAMIeRvtBgAdAQAsAAQKgR4AAwQACAhyJKIDAFADAAQACAhyJKIDAFADAAoABghDFMgGAF4BAAAA.Mopsidots:BAAALAAECgYIBQABLAAFFAMIBQAEAHkbAA==.',Ms='Msdemonhunt:BAAALAADCgIIAgAAAA==.',Na='Nalgust:BAABLAAECoEbAAIdAAgIKCKfAwDyAgAdAAgIKCKfAwDyAgABLAAFFAMIBQARALIPAA==.',Ni='Nicolas:BAAALAAECgYICgAAAA==.Nikifox:BAAALAAECgYIDAAAAA==.Ninjagoat:BAACLAAFFIEMAAICAAYItCB4AABfAgACAAYItCB4AABfAgAsAAQKgRsAAgIACAhOJokAAI8DAAIACAhOJokAAI8DAAAA.Ninjalock:BAAALAAFFAIIAgAAAA==.Ninjalol:BAAALAAECggIDQAAAA==.',No='Noorda:BAAALAAECgYIBgAAAA==.Nottango:BAAALAAECgcIBwAAAA==.',Pa='Paina:BAAALAADCgcICQAAAA==.Paladingus:BAAALAAECgcIEAAAAA==.Pallydozer:BAAALAAECgUIBQABLAAFFAYIEQAGAP4TAA==.Papi:BAAALAADCggIFQAAAA==.Pawnstar:BAAALAAECgUIDAAAAA==.Payna:BAABLAAECoEUAAIZAAcI0xc8UgCXAQAZAAcI0xc8UgCXAQAAAA==.',Pi='Piper:BAAALAADCgQIBQAAAA==.',Pl='Placebø:BAAALAAFFAEIAQAAAA==.Plattfisk:BAAALAADCgMIAwAAAA==.',Pr='Proxi:BAAALAAECgYICAAAAA==.',Pu='Puddy:BAAALAAFFAIIAgAAAA==.Pukki:BAAALAAECgYICwABLAAECggIHQANAOEjAA==.',['Pä']='Pändora:BAAALAAECggIDgAAAA==.',Qu='Quannah:BAAALAADCggIGAAAAA==.',Ra='Ragausalsa:BAABLAAECoEcAAMGAAgIYhyLCwBdAgAGAAgIlhmLCwBdAgAbAAUIxhwWNQCOAQAAAA==.Razorcow:BAAALAADCgYIBgAAAA==.',Re='Reholy:BAACLAAFFIEPAAIDAAYIHiQNAACWAgADAAYIHiQNAACWAgAsAAQKgR4AAgMACAjuJhEAAKUDAAMACAjuJhEAAKUDAAAA.Rekyyli:BAAALAAECgYIDwAAAA==.Rerolly:BAAALAAECgYIDAABLAAFFAYIDwADAB4kAA==.Revoked:BAABLAAECoEbAAMTAAgIdyR3AwA0AwATAAgIdyR3AwA0AwALAAEInwS7JAAuAAABLAAFFAYIDwADAB4kAA==.',Rh='Rháegon:BAAALAAECggICAAAAA==.',Ri='Rilmaclya:BAACLAAFFIEGAAIbAAIIuRkCDACvAAAbAAIIuRkCDACvAAAsAAQKgSsAAhsACAhOJWoBAHUDABsACAhOJWoBAHUDAAAA.',Ro='Rokir:BAAALAADCgEIAQAAAA==.Rorschach:BAAALAAECgcIDwAAAA==.Rosalia:BAAALAADCggIFQAAAA==.Rosaluma:BAAALAADCgYIBAAAAA==.Rottington:BAAALAAECgUIBQAAAA==.',['Rï']='Rïlmaclya:BAAALAAFFAIIAgABLAAFFAIIBgAbALkZAA==.',Sa='Sager:BAAALAAECgYIBgAAAA==.Sasori:BAAALAAECgEIAQAAAA==.',Sc='Scriim:BAAALAAECgUICwAAAA==.',Se='Servus:BAAALAAECgIIAgAAAA==.',Sh='Sh:BAAALAAFFAIIBAABLAAFFAIIBgACAFsZAA==.Shaderz:BAAALAADCgEIAQAAAA==.Shadowlock:BAABLAAECoEUAAIeAAgI8BoyFABoAgAeAAgI8BoyFABoAgAAAA==.Shallan:BAAALAADCggIDwAAAA==.Shamu:BAAALAADCgEIAQAAAA==.Sharkhan:BAAALAADCggICAAAAA==.Shieldman:BAACLAAFFIEGAAIVAAQISBf+AABCAQAVAAQISBf+AABCAQAsAAQKgRgAAxUACAhUJPMBAEADABUACAhUJPMBAEADAA0AAQimHPS4AFMAAAEsAAUUBggPAAMAHiQA.Shinfo:BAAALAADCggIDQAAAA==.Shoots:BAAALAADCgQIBQAAAA==.Sháegon:BAAALAAECgUICwABLAAECggICAABAAAAAA==.',Si='Sinne:BAAALAAECgcIDAAAAA==.',Sm='Smauglypuff:BAAALAAECgIIAgABLAAECgYIBgABAAAAAA==.',So='Soulstéaler:BAAALAAECggIDAAAAA==.',Sp='Spalavac:BAABLAAECoEaAAIUAAgImhltFgBNAgAUAAgImhltFgBNAgAAAA==.Spiritusks:BAABLAAECoEeAAIJAAgIZSXOAQBoAwAJAAgIZSXOAQBoAwAAAA==.Spìnxy:BAAALAADCgQIBQABLAAECgIIAgABAAAAAA==.',St='Stabnhide:BAAALAADCggICAAAAA==.Stephenlogic:BAAALAAECgUIBQAAAA==.Stew:BAABLAAECoEVAAISAAgITxx3FwBvAgASAAgITxx3FwBvAgAAAA==.Stilnox:BAAALAAECgYICgAAAA==.Stingos:BAAALAAECgYIBgABLAAECggIGgAUAJoZAA==.Stonedh:BAACLAAFFIETAAIQAAYIqBe+AABMAgAQAAYIqBe+AABMAgAsAAQKgR0AAhAACAj9JD0FAE0DABAACAj9JD0FAE0DAAAA.Stonedru:BAAALAAECgcIDgABLAAFFAYIEwAQAKgXAA==.Stonepal:BAAALAAECggICwAAAA==.Stonewar:BAABLAAFFIEFAAMbAAMITQrEBwDlAAAbAAMITQrEBwDlAAAGAAII6QSQCwBsAAABLAAFFAYIEwAQAKgXAA==.',Sy='Sykes:BAAALAADCggIAQAAAA==.Syks:BAAALAAFFAIIAgAAAA==.Synida:BAABLAAECoEcAAIIAAgItiERBwD8AgAIAAgItiERBwD8AgAAAA==.',Ta='Tallfoot:BAAALAAECggIDQAAAA==.Tango:BAAALAAECggIDwAAAA==.Taobao:BAAALAADCgEIAQAAAA==.',Te='Tersilla:BAAALAADCggIEgAAAA==.',Th='Themanslayer:BAAALAAECggICAAAAA==.Thock:BAABLAAECoEcAAIGAAgIkB/zBQDVAgAGAAgIkB/zBQDVAgAAAA==.Thonne:BAAALAADCgEIAQABLAAECgcIDwABAAAAAA==.',Ti='Tinhay:BAAALAAECgcIBgAAAA==.',To='Tomikadzi:BAAALAAECgMIAwABLAAECggIHgAEAP4eAA==.Tomïkadzi:BAABLAAECoEeAAIEAAgI/h6hEQDTAgAEAAgI/h6hEQDTAgAAAA==.Toshiro:BAAALAADCgYIBgAAAA==.',Tr='Trzuncek:BAAALAAECgYICgAAAA==.',Tw='Twíst:BAAALAAECgIIAgAAAA==.',Ty='Tya:BAAALAAECgUIBQAAAA==.',Ur='Urthadur:BAABLAAECoEXAAIQAAgIkSBsEQDYAgAQAAgIkSBsEQDYAgABLAAFFAYIDgANAB4ZAA==.',Va='Vacaria:BAAALAAECgYICQAAAA==.Vassagô:BAAALAADCggICAAAAA==.',Vo='Voidshuffle:BAACLAAFFIERAAIeAAYI/h5QAACGAgAeAAYI/h5QAACGAgAsAAQKgR4AAh4ACAieJksAAJMDAB4ACAieJksAAJMDAAAA.Voidstar:BAAALAADCggICAAAAA==.Voodooms:BAAALAAECgUICwAAAA==.',Vu='Vulgrìm:BAAALAADCggICAAAAA==.',Wh='Whiplasher:BAABLAAECoEWAAIfAAgI3xuQCgB6AgAfAAgI3xuQCgB6AgAAAA==.',Wi='Winxi:BAAALAAECgUICQAAAA==.Withinterest:BAAALAADCggIFQAAAA==.Wiztuin:BAAALAADCgQIBAAAAA==.',Wu='Wuguene:BAAALAAECgcIBwAAAA==.',Xe='Xelion:BAACLAAFFIEOAAMcAAYIISYWAABDAgAcAAUIWSYWAABDAgAgAAIIbiWTAgDXAAAsAAQKgR4AAxwACAhaJjgAAIkDABwACAhaJjgAAIkDACAAAQi9JTIjAGoAAAAA.Xelionsplit:BAABLAAECoEXAAMcAAgI8yPRBAANAwAcAAgI0h/RBAANAwAgAAIIoR8THQC2AAABLAAFFAYIDgAcACEmAA==.',Ya='Yasar:BAAALAADCgQIBAAAAA==.',Yu='Yunited:BAAALAAECgYIDgAAAA==.',Zi='Zirick:BAABLAAECoEUAAINAAcI2RnNMgAHAgANAAcI2RnNMgAHAgAAAA==.',Zu='Zugzugz:BAAALAAECgcIDAAAAA==.',['Zó']='Zóroark:BAABLAAECoEXAAIHAAcIJwpQPwB4AQAHAAcIJwpQPwB4AQAAAA==.',['Ða']='Ðanter:BAAALAADCgUIBAAAAA==.',['Ðö']='Ðööm:BAAALAADCgIIAgABLAAECgIIAgABAAAAAA==.',['Óx']='Óxxen:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end