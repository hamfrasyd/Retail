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
 local lookup = {'Warlock-Demonology','Rogue-Subtlety','Warrior-Fury','Warrior-Arms','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','DemonHunter-Havoc','Rogue-Assassination','Rogue-Outlaw','Priest-Holy','Priest-Discipline','DeathKnight-Unholy','Mage-Arcane','Druid-Feral','Priest-Shadow','Druid-Restoration','DeathKnight-Frost','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement','Evoker-Devastation','Evoker-Preservation','DeathKnight-Blood','Mage-Frost','Warlock-Affliction','Unknown-Unknown','Druid-Balance','Monk-Windwalker','Monk-Mistweaver','Hunter-Survival','Warlock-Destruction',}; local provider = {region='EU',realm='Talnivarr',name='EU',type='weekly',zone=44,date='2025-09-22',data={Ac='Acespally:BAAALAAECgIIAgAAAA==.',Aj='Ajou:BAAALAAECggIEgAAAA==.',Ak='Akeno:BAAALAADCgUIBQAAAA==.',Al='Alakai:BAAALAAECgEIAQAAAA==.Albinodead:BAABLAAECoEkAAIBAAgIkiAHBgDqAgABAAgIkiAHBgDqAgAAAA==.Albyshamm:BAAALAADCgUIBQAAAA==.Alkan:BAAALAADCgIIAgABLAAECggIIwACAEIWAA==.',Ar='Ara:BAAALAAECgMIBAAAAA==.Archanfel:BAABLAAECoEjAAICAAgIQhaQDgAfAgACAAgIQhaQDgAfAgAAAA==.Armani:BAAALAAECggICAAAAA==.',Ax='Axehugs:BAABLAAECoEaAAMDAAgIABUQRQDkAQADAAYIgBsQRQDkAQAEAAgI4QG+LABVAAAAAA==.',Ba='Balmung:BAAALAADCggIFAAAAA==.Balorix:BAAALAADCgcICgAAAA==.',Be='Belothar:BAAALAADCggIHQAAAA==.Bennybultsax:BAAALAAECgYICwAAAA==.Bennyyo:BAAALAAECgQIBAAAAA==.Bestemor:BAABLAAECoEXAAIFAAgIBgtiYAAcAQAFAAgIBgtiYAAcAQAAAA==.',Br='Browneagle:BAAALAAECgYIBwABLAAECggIIAAGAMEgAA==.Bruiizeer:BAAALAAECgYICgAAAA==.',Bu='Bubblicious:BAABLAAECoEiAAIHAAgIxRqmLACSAgAHAAgIxRqmLACSAgAAAA==.Buurman:BAAALAAECgMIAwAAAA==.',['Bé']='Bénifit:BAAALAAECgIIAQAAAA==.',Ca='Cainztar:BAAALAAFFAIIAgABLAAFFAcIHwAGAOIhAA==.',Ch='Chiana:BAABLAAECoEYAAIGAAgIwhizOAAwAgAGAAgIwhizOAAwAgAAAA==.',Co='Constantyne:BAAALAAECgEIAQAAAA==.',Da='Dakerem:BAAALAAECggIEwAAAA==.Darkcrusade:BAAALAAECgYIDgAAAA==.',De='Deadon:BAAALAADCgcIBAAAAA==.Deathdeath:BAAALAAECgYICwABLAAFFAMIBQAIAP8aAA==.Deirdra:BAAALAAECgEIAQAAAA==.Deliçious:BAACLAAFFIEFAAMJAAIIKAl/FACXAAAJAAIIKAl/FACXAAAKAAIIOAKUBAB4AAAsAAQKgSYAAwkACAjJFAYbACgCAAkACAjJFAYbACgCAAoABwguDTcLAJkBAAAA.Demodemo:BAACLAAFFIEFAAIIAAMI/xqvDgANAQAIAAMI/xqvDgANAQAsAAQKgSQAAggACAieIyIPACEDAAgACAieIyIPACEDAAAA.Demonjester:BAAALAAECgYIBgAAAA==.',Di='Diamadi:BAAALAADCgcIAwAAAA==.Dingetje:BAAALAADCgUIBgAAAA==.Dino:BAABLAAECoEmAAIIAAgIQx4TJgCeAgAIAAgIQx4TJgCeAgAAAA==.Dinoxd:BAAALAAECgEIAQAAAA==.',Do='Docter:BAABLAAECoEXAAILAAcIARb2OADNAQALAAcIARb2OADNAQAAAA==.Doomstorm:BAAALAADCgIIAgAAAA==.',Du='Duvur:BAACLAAFFIEGAAIMAAIImgyTAgCBAAAMAAIImgyTAgCBAAAsAAQKgRgAAgwABghNFz0NAJkBAAwABghNFz0NAJkBAAAA.',Dw='Dwight:BAAALAADCgYIBgAAAA==.',Ea='Earthenfox:BAAALAAECgYIBgAAAA==.',El='Eldren:BAACLAAFFIEJAAIIAAMIuxcQDgATAQAIAAMIuxcQDgATAQAsAAQKgSAAAggACAiMJe4EAGYDAAgACAiMJe4EAGYDAAAA.Eldrenzil:BAABLAAFFIEFAAINAAIIiB4dCQC1AAANAAIIiB4dCQC1AAABLAAFFAIIBgAFAHEbAA==.',En='Enola:BAAALAAECgYIDAAAAA==.',Es='Esmerelda:BAABLAAECoEVAAIOAAYIKBDtegByAQAOAAYIKBDtegByAQAAAA==.',Fa='Faerinth:BAAALAAECggIBgAAAA==.Faylen:BAAALAADCgUIBQAAAA==.',Fe='Fehirdudu:BAABLAAECoEWAAIPAAYIGR5iEwDyAQAPAAYIGR5iEwDyAQABLAAECggIGgABACIdAA==.',Fi='Fihnzane:BAAALAAECgMIBAAAAA==.',Fl='Flawless:BAAALAAECgUIEAAAAA==.Floorpov:BAAALAAECgMIAwAAAA==.Floss:BAAALAADCggICAAAAA==.',Fo='Foxley:BAABLAAECoEkAAIGAAgI8hdUQwAKAgAGAAgI8hdUQwAKAgAAAA==.',Fu='Funus:BAAALAAECgIIAgAAAA==.',Ga='Garmm:BAAALAAECgUIBQABLAAECgcIHQAQAHEWAA==.',Gl='Gloom:BAAALAAECgMIAwAAAA==.',Go='Goldy:BAABLAAECoEZAAILAAcI4hS5NgDZAQALAAcI4hS5NgDZAQABLAAECggIIAAGAMEgAA==.Gorbah:BAABLAAECoEUAAIDAAgI4Ap9VgCpAQADAAgI4Ap9VgCpAQAAAA==.',Gr='Grief:BAAALAAECgYICAAAAA==.Gräddglass:BAAALAADCggICgAAAA==.',Ha='Halfs:BAACLAAFFIEJAAIRAAMI/BioCQD3AAARAAMI/BioCQD3AAAsAAQKgRoAAhEACAgPIv8GAA4DABEACAgPIv8GAA4DAAAA.Hannoying:BAAALAAECggIDwAAAA==.Happypony:BAAALAAECgYIDQABLAAECggIFAASAHodAA==.',He='Heavylight:BAACLAAFFIEGAAITAAMI/AfJCwDMAAATAAMI/AfJCwDMAAAsAAQKgSAAAxMACAhGE7QfAN8BABMACAhGE7QfAN8BAAcAAwhFBa8VAXAAAAAA.Henkepunk:BAAALAADCgQIBAAAAA==.',Hr='Hrefna:BAABLAAECoEaAAMCAAgIyh9zBwCqAgACAAgIiRxzBwCqAgAJAAYIXB81HAAdAgAAAA==.',Hu='Huggern:BAAALAAECgcIEAAAAA==.Huntared:BAAALAAECgEIAgAAAA==.Huntsig:BAABLAAECoEdAAIUAAgIlCA/FgDFAgAUAAgIlCA/FgDFAgAAAA==.',Ic='Icu:BAACLAAFFIEFAAIVAAII8BL5BACbAAAVAAII8BL5BACbAAAsAAQKgR4AAhUACAgVI4cCABADABUACAgVI4cCABADAAAA.',Il='Illusion:BAAALAADCggIEAAAAA==.',In='Ingvarwar:BAAALAAECgIIAgAAAA==.',Ja='Jarlsberg:BAAALAAECgYIBwAAAA==.',Ji='Jinjin:BAAALAAECgUICAAAAA==.',Jo='Jokklis:BAABLAAECoEXAAIRAAgIJhoZGgBjAgARAAgIJhoZGgBjAgAAAA==.Jonte:BAAALAADCggIFgAAAA==.',Ju='Juniper:BAAALAAECgYICQAAAA==.Jushur:BAAALAAECgEIAQAAAA==.',Ka='Kalameet:BAACLAAFFIEHAAMWAAII2BFmEgCVAAAWAAII2BFmEgCVAAAXAAIIXQ0uDgCVAAAsAAQKgSYAAxYACAhVIN0KAOECABYACAhVIN0KAOECABcAAQjwGa8zAE4AAAAA.Kanaya:BAAALAAECgYIDAAAAA==.',Kb='Kbrain:BAAALAAECgEIAQAAAA==.',Kd='Kdm:BAAALAADCggICAAAAA==.',Ko='Korrosh:BAABLAAECoEfAAIYAAgIYSSTAwAqAwAYAAgIYSSTAwAqAwAAAA==.',Kv='Kvurren:BAAALAAECgcIDQAAAA==.',La='Lahash:BAAALAAECggIEwAAAA==.Lahrian:BAABLAAECoElAAIGAAgIPBxkMwBEAgAGAAgIPBxkMwBEAgAAAA==.Lamanga:BAAALAADCgcICwAAAA==.',Lo='Lovéless:BAAALAADCggICAAAAA==.',Lu='Lussekatten:BAAALAADCgYIBgAAAA==.',Ma='Malanath:BAAALAAECgMIAwAAAA==.Mattack:BAAALAAFFAIIBAAAAA==.',Mc='Mcbrain:BAABLAAECoEhAAIJAAgIVA83IgDuAQAJAAgIVA83IgDuAQAAAA==.',Me='Meshu:BAAALAAECggICAAAAA==.',Mi='Mithril:BAAALAAECgQIBAAAAA==.',Mo='Mobi:BAACLAAFFIEIAAIZAAMIxhOSAwDyAAAZAAMIxhOSAwDyAAAsAAQKgSYAAxkACAgxH44JAOECABkACAgxH44JAOECAA4ABAi1Az3AAIEAAAAA.Mogwai:BAACLAAFFIEFAAIGAAIICQXENgBvAAAGAAIICQXENgBvAAAsAAQKgRcAAgYACAh4EopZAMsBAAYACAh4EopZAMsBAAAA.Moozalot:BAAALAADCgcIDQAAAA==.Morgase:BAABLAAECoEWAAIaAAcIRx3RBACEAgAaAAcIRx3RBACEAgAAAA==.',Na='Nasha:BAABLAAECoEdAAMQAAcIcRZ2MwDTAQAQAAcIcRZ2MwDTAQALAAYIqQj0bAAJAQAAAA==.',Ne='Nefeli:BAAALAAECgcICQAAAA==.Nephalem:BAAALAADCggICAAAAA==.Nessiri:BAABLAAECoEmAAIQAAgIwCG/CgAPAwAQAAgIwCG/CgAPAwAAAA==.',No='Nocturnal:BAACLAAFFIEGAAIQAAMIUQ7uDQDhAAAQAAMIUQ7uDQDhAAAsAAQKgSEAAhAACAj7IEsMAAEDABAACAj7IEsMAAEDAAAA.',['Nï']='Nïff:BAABLAAECoEUAAISAAgIeh0+NAB4AgASAAgIeh0+NAB4AgAAAA==.',Ok='Oki:BAAALAAECgYIEQAAAA==.',On='Onlyfear:BAAALAAFFAIIAgAAAA==.',Ph='Phillidan:BAABLAAECoEYAAIIAAgIDSQ8DQAsAwAIAAgIDSQ8DQAsAwAAAA==.',Pr='Prismo:BAAALAAECgYICwAAAA==.',Qf='Qfg:BAABLAAFFIEFAAICAAMIgRK2BgDrAAACAAMIgRK2BgDrAAAAAA==.',Ra='Ragequitter:BAAALAAECggIEgAAAA==.',Re='Rehana:BAAALAAECggIBgAAAA==.Rendaty:BAAALAADCgcIDwABLAADCggIFAAbAAAAAA==.',Ro='Rondi:BAAALAAECgUIBQABLAAFFAIIBgAcADEhAA==.Rossidudu:BAABLAAECoEbAAMPAAgIPB/NCQCSAgAPAAgIPB/NCQCSAgAcAAEIHg15jAAxAAAAAA==.',Ry='Ryla:BAAALAAECgcICgAAAA==.',Sa='Saintza:BAAALAAECgYIBgAAAA==.Samedi:BAAALAADCgUIBgAAAA==.Sash:BAAALAAECgYIDgAAAA==.',Se='Selyn:BAABLAAECoEkAAIHAAgIsR+XGwDlAgAHAAgIsR+XGwDlAgAAAA==.',Sh='Shidus:BAAALAAECgcIDQAAAA==.Shoogie:BAAALAADCgYIBgABLAAFFAMIBQAdAJwXAA==.Shoogy:BAACLAAFFIEFAAIdAAMInBezBQD/AAAdAAMInBezBQD/AAAsAAQKgSMAAx0ACAjZIloHAAMDAB0ACAjZIloHAAMDAB4ABAjZEOsvAOYAAAAA.',Si='Siph:BAAALAADCgYIBgABLAAECggIIAAIAOIXAA==.Sipharel:BAABLAAECoEgAAIIAAgI4hfEQAAvAgAIAAgI4hfEQAAvAgAAAA==.',Sn='Sniperkat:BAAALAADCggICAAAAA==.Snorkleguppy:BAAALAAECgYIDgABLAAECggIFAASAHodAA==.',Sp='Spankandtank:BAAALAAECgYIBgAAAA==.Spurdomage:BAAALAADCggIFQABLAAECggIEwAbAAAAAA==.',St='Stab:BAAALAAECgYIDAAAAA==.Stillburn:BAAALAAECggICwAAAA==.Stompers:BAAALAAECgYIDAAAAA==.',Su='Subzie:BAABLAAECoEbAAIfAAgIPwkQCwDJAQAfAAgIPwkQCwDJAQAAAA==.Sushi:BAAALAAECgYIBgAAAA==.',Sw='Swosher:BAAALAADCgUIBwAAAA==.',Ta='Talindra:BAAALAAECggICAAAAA==.Tarne:BAAALAAECggIEwAAAA==.',Th='Thadeka:BAAALAAECgMIAwABLAAECggIIwACAEIWAA==.Thatplyte:BAAALAAECgIIAgABLAAECgcIGgAJADElAA==.Thecoree:BAAALAAECgIIAgAAAA==.',Ti='Tittentei:BAAALAADCgIIAgAAAA==.',To='Tobbzki:BAAALAAECggICAAAAA==.Tookee:BAAALAADCgEIAQAAAA==.',Ts='Tsimpidas:BAAALAADCgQIBAAAAA==.',Tw='Tweekz:BAAALAAECgUIAwAAAA==.',Un='Unholymoly:BAAALAAECggICAAAAA==.',Va='Valhalla:BAAALAADCggICQAAAA==.Vanat:BAAALAADCggICgAAAA==.Varg:BAAALAAECggICAAAAA==.',Vi='Viçious:BAAALAAECgIIAgABLAAFFAIIBQAJACgJAA==.',Wa='Wamilla:BAACLAAFFIEGAAIcAAIIMSGsDgCrAAAcAAIIMSGsDgCrAAAsAAQKgRAAAhwABgiSJc0UAJMCABwABgiSJc0UAJMCAAAA.',Wi='Wildhoof:BAAALAADCggICAAAAA==.',Wo='Wongshjit:BAABLAAECoEaAAIeAAcIuBPmGgCpAQAeAAcIuBPmGgCpAQAAAA==.',Xa='Xaroponos:BAAALAADCggIGQAAAA==.',Xu='Xunthera:BAAALAADCgcIBwAAAA==.',Ya='Yarmen:BAABLAAECoEgAAIGAAgIwSA9HAC0AgAGAAgIwSA9HAC0AgAAAA==.',Za='Zanté:BAAALAAECgYICQAAAA==.',Ze='Zela:BAAALAAECgYICQAAAA==.Zemai:BAABLAAECoEyAAILAAgIRRaOKwATAgALAAgIRRaOKwATAgAAAA==.',Zn='Znuf:BAABLAAECoEZAAMgAAgIZR1PIACgAgAgAAgIZR1PIACgAgABAAEI8AomhQA4AAAAAA==.',Zo='Zografia:BAABLAAECoEdAAIOAAcISwgffwBnAQAOAAcISwgffwBnAQAAAA==.',Zu='Zugmon:BAACLAAFFIEGAAIFAAIIcRv/FQCaAAAFAAIIcRv/FQCaAAAsAAQKgS0AAgUACAjVJB4DAFMDAAUACAjVJB4DAFMDAAAA.',Zy='Zyra:BAAALAADCggICAAAAA==.',['Zé']='Zéw:BAACLAAFFIEIAAINAAMIQRiRBAAMAQANAAMIQRiRBAAMAQAsAAQKgSYAAw0ACAjiIjsDACkDAA0ACAjiIjsDACkDABgAAQgPDRlAACYAAAAA.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end