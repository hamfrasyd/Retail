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
 local lookup = {'Warrior-Protection','DemonHunter-Vengeance','Warrior-Fury','Paladin-Retribution','Warlock-Destruction','Monk-Windwalker','Monk-Mistweaver','Mage-Arcane','Unknown-Unknown','Rogue-Outlaw','Evoker-Devastation','Druid-Guardian','DemonHunter-Havoc','Hunter-BeastMastery','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Monk-Brewmaster','Priest-Holy','DeathKnight-Frost','Paladin-Protection','Shaman-Restoration','Shaman-Enhancement','Shaman-Elemental','Hunter-Marksmanship','Druid-Balance','Mage-Frost','Druid-Feral','Mage-Fire','Hunter-Survival','Priest-Discipline','Priest-Shadow','DeathKnight-Blood','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Warrior-Arms','Evoker-Preservation',}; local provider = {region='EU',realm="Shen'dralar",name='EU',type='weekly',zone=44,date='2025-09-25',data={Ab='Abäddon:BAAALAADCgEIAQAAAA==.',Ac='Ackerman:BAAALAAECggIDgAAAA==.',Ae='Aebonne:BAAALAAECgcICgAAAA==.',Ah='Ahrimân:BAAALAAECgMIAwAAAA==.',Ak='Akame:BAABLAAECoEZAAIBAAcIlCHFFgBNAgABAAcIlCHFFgBNAgABLAAECggIIQACAPAlAA==.Akemi:BAAALAAECgEIAQAAAA==.Akhelión:BAAALAADCgYIBgAAAA==.Akulakhan:BAAALAAECgQIBQAAAA==.',Al='Albâ:BAAALAADCgcIBwAAAA==.Alescar:BAABLAAECoEaAAIDAAgIRCHqEgD8AgADAAgIRCHqEgD8AgAAAA==.Alexol:BAAALAAECggIEgABLAAFFAYIEwAEAJEeAA==.Aleíx:BAABLAAECoEcAAIFAAgI/hpEKgBvAgAFAAgI/hpEKgBvAgAAAA==.Alhealal:BAAALAAECgYIDQAAAA==.Alisandra:BAAALAADCggICQAAAA==.Allister:BAACLAAFFIEIAAIGAAIIsh0HCgCnAAAGAAIIsh0HCgCnAAAsAAQKgTMAAgYACAiXH3oJAOICAAYACAiXH3oJAOICAAAA.Almanegra:BAAALAAECgEIAQAAAA==.Alonzo:BAAALAADCgcIBwAAAA==.Altarian:BAAALAAFFAEIAQAAAA==.',Am='Amilus:BAAALAAECgIIAgAAAA==.Amorch:BAAALAAECgcIDQAAAA==.',Ar='Araxiel:BAAALAAFFAIIAgAAAA==.Arbaal:BAABLAAECoEhAAICAAcIWx3WEAArAgACAAcIWx3WEAArAgAAAA==.Are:BAABLAAECoEfAAIHAAcIyRaoFwDYAQAHAAcIyRaoFwDYAQAAAA==.Ares:BAAALAAECgYIBgAAAA==.Arobynn:BAAALAADCggICAAAAA==.Arona:BAAALAAECgQICAAAAA==.',As='Asa:BAACLAAFFIEFAAIDAAIIAhGYIgCeAAADAAIIAhGYIgCeAAAsAAQKgR8AAgMACAhbHKcgAJ8CAAMACAhbHKcgAJ8CAAAA.Ashborn:BAAALAAECgMIAwAAAA==.Ashglace:BAABLAAECoEUAAIIAAgImgrBZgCwAQAIAAgImgrBZgCwAQAAAA==.Asterio:BAAALAADCgIIAgABLAAECgcIEwAJAAAAAA==.Astrat:BAAALAADCgEIAQAAAA==.Aswen:BAABLAAECoEmAAIIAAgIFB6sOgBBAgAIAAgIFB6sOgBBAgAAAA==.',At='Athelwyn:BAABLAAECoEeAAIEAAcINxCckACbAQAEAAcINxCckACbAQAAAA==.Atrami:BAABLAAECoEZAAIBAAYIUx/vIAD2AQABAAYIUx/vIAD2AQAAAA==.',Ax='Axon:BAACLAAFFIETAAIFAAUIrQ1WDgCHAQAFAAUIrQ1WDgCHAQAsAAQKgSYAAgUACAjtIBoWAOcCAAUACAjtIBoWAOcCAAAA.',['Aï']='Aïlohrïa:BAAALAADCgcIDAAAAA==.',Ba='Backrolla:BAACLAAFFIEHAAIKAAII+xFiAwCgAAAKAAII+xFiAwCgAAAsAAQKgSkAAgoACAjSH1oCAOgCAAoACAjSH1oCAOgCAAAA.',Be='Beako:BAAALAADCgMIAwAAAA==.Bearcatauren:BAAALAADCgEIAQAAAA==.Belami:BAAALAADCggICAABLAAECggIHAAFAP4aAA==.Belorion:BAAALAAECgIIAwAAAA==.Bennu:BAAALAAECgcIEAAAAA==.Berlen:BAAALAAECgcIDwAAAA==.Bestialis:BAABLAAECoEaAAILAAcIWgyONABlAQALAAcIWgyONABlAQAAAA==.Beticismo:BAAALAAECgYIBgAAAA==.',Bk='Bk:BAAALAADCgQIBAAAAA==.',Bl='Blackangel:BAABLAAECoEUAAIMAAYITxJBFwApAQAMAAYITxJBFwApAQAAAA==.Blackstar:BAAALAADCggICAABLAAFFAUIEwAFAK0NAA==.Blake:BAAALAAECgYIBgAAAA==.Bleyex:BAAALAAECggICgAAAA==.',Bo='Bolmak:BAAALAAECgMIAwAAAA==.',Br='Brishen:BAAALAADCggICAABLAAECgMIAwAJAAAAAA==.Brokan:BAAALAAECgcIDwAAAA==.',['Bä']='Bäel:BAAALAADCgYICwAAAA==.',Ca='Cal:BAAALAADCggIEgABLAAECggIIAANAPMaAA==.Cammavinga:BAAALAAECgIIAgAAAA==.Candle:BAAALAAECgQIAwAAAA==.Caprihunt:BAAALAADCgYIBgAAAA==.Caprisham:BAAALAAECgMIBQAAAA==.Caya:BAAALAAECgIIAgABLAAECgYICgAJAAAAAA==.Cayetana:BAAALAAECgIIAgAAAA==.',Ce='Celstra:BAAALAADCggICAABLAAECgUIBQAJAAAAAA==.Cerealbox:BAAALAADCgcIBwABLAAECggIHAAFAP4aAA==.Ceretrus:BAACLAAFFIEHAAIFAAMI3A2EGwDjAAAFAAMI3A2EGwDjAAAsAAQKgS4AAgUACAhPHbIeALECAAUACAhPHbIeALECAAAA.',Ch='Chamanloco:BAAALAAECgUIBgAAAA==.Chamanza:BAAALAAECgcIDQAAAA==.Charmion:BAAALAAECgcIEgAAAA==.Cheyen:BAABLAAECoEpAAIOAAcI8BoMWADaAQAOAAcI8BoMWADaAQAAAA==.Chirito:BAAALAAECgcIDwABLAAFFAUIEwAGAGIkAA==.Chivø:BAAALAAECgYIEQABLAAECgYIFgAPAN8gAA==.Chiëko:BAACLAAFFIETAAMQAAYIUxnHAQAIAgAQAAYIMhnHAQAIAgARAAMI8ByjCAANAQAsAAQKgR4AAxEACAiNI5EMAL8CABEACAgYI5EMAL8CABAABQgEHlwXALYBAAAA.Chufa:BAAALAAECgIIAwAAAA==.',Ci='Ciberpanceta:BAAALAADCggICAABLAAFFAIIAgAJAAAAAA==.Cirnelle:BAAALAAECgYIDAAAAA==.',Cl='Clapcerola:BAAALAAFFAIIAgABLAAFFAIIBwANADMiAA==.Cløud:BAAALAAECgUIDQAAAA==.',Co='Coyote:BAAALAADCggIDQABLAAECgcIIQACAFsdAA==.',Cr='Crown:BAAALAAECgYIBgAAAA==.Cryp:BAAALAADCgcIEQAAAA==.',Cu='Cucurruspeta:BAAALAAECgYIBgAAAA==.',Cy='Cynthia:BAAALAAECgUIBQAAAA==.',Da='Dalanae:BAABLAAECoEkAAISAAgINRcAJQApAgASAAgINRcAJQApAgAAAA==.Dalnim:BAABLAAECoEaAAITAAcIDAwrJgAoAQATAAcIDAwrJgAoAQAAAA==.Danarith:BAAALAAECgIIAgAAAA==.Darkshadow:BAAALAADCgEIAQAAAA==.Daulgur:BAAALAADCgMIAwAAAA==.',De='Deluna:BAABLAAECoEVAAINAAYIOh4AXADoAQANAAYIOh4AXADoAQAAAA==.Deskolorio:BAAALAADCgYIBwAAAA==.Deva:BAAALAAECgYICAABLAAECgcIIQACAFsdAA==.Dexlock:BAAALAAECgYIBwABLAAFFAUIAgAJAAAAAA==.Dexmage:BAAALAAECgYIBwABLAAFFAUIAgAJAAAAAA==.Dexshar:BAAALAAFFAUIAgAAAA==.Dexsharch:BAAALAAFFAIIAgABLAAFFAUIAgAJAAAAAA==.',Dh='Dhelron:BAAALAAECgUIBAABLAAECggIKgAUAJgjAA==.',Di='Dinofelis:BAAALAADCggICAABLAAFFAUIFQADAEcbAA==.',Dk='Dka:BAAALAAECgMIAwAAAA==.',Dl='Dlkk:BAACLAAFFIEGAAIVAAIIpCIeIADIAAAVAAIIpCIeIADIAAAsAAQKgRcAAhUABwgfI4gwAIoCABUABwgfI4gwAIoCAAAA.',Do='Dovo:BAAALAAECgYICwAAAA==.',Dr='Drainkhan:BAAALAAECgIIAwAAAA==.Drakopako:BAAALAAFFAIIAgAAAA==.Draktizzu:BAAALAAECgYIAQABLAAFFAIIBQAWALodAA==.Drismol:BAAALAADCggIDAABLAAFFAMIDAAEAGccAA==.Druta:BAAALAADCggICgAAAA==.Drâno:BAAALAAECgcIDQAAAA==.',Du='Duduhunter:BAAALAAECgYIDQAAAA==.Dune:BAAALAAECgYICQAAAA==.',Dw='Dwy:BAABLAAECoEWAAIXAAgIwx7GFACzAgAXAAgIwx7GFACzAgAAAA==.',['Dæ']='Dæva:BAAALAADCgcIBwAAAA==.',['Dø']='Døppler:BAABLAAFFIEHAAINAAIITx5tHQCyAAANAAIITx5tHQCyAAAAAA==.Døvo:BAACLAAFFIEGAAIWAAMInSF4BAAEAQAWAAMInSF4BAAEAQAsAAQKgRcAAhYACAgeJEIFABQDABYACAgeJEIFABQDAAAA.',Ed='Edymchark:BAAALAAECgQIBwAAAA==.',Ei='Eiros:BAAALAADCgEIAQAAAA==.',Ek='Eklai:BAABLAAECoEYAAMYAAgIBQhtGAA0AQAYAAgI4gNtGAA0AQAZAAgI8gcAAAAAAAAAAA==.',El='Eladryn:BAAALAAECgcIBwABLAAFFAMIBQAJAAAAAA==.Elerin:BAAALAADCggICAAAAA==.Elexius:BAAALAAECgQIBQABLAAFFAMIBwAFAFoZAA==.',Em='Emilvox:BAAALAADCgEIAQAAAA==.',Er='Erethin:BAAALAAECgYICwAAAA==.Eronil:BAAALAAECgUICAAAAA==.',Fa='Farone:BAABLAAECoEhAAISAAgIbyCtCgDsAgASAAgIbyCtCgDsAgAAAA==.Fate:BAAALAAECgYICQABLAAFFAIIBgAFAHwYAA==.',Fe='Fedod:BAAALAADCgUIBQAAAA==.',Fi='Finjakew:BAAALAAECggIDwABLAAFFAYIEgAaAHQlAA==.Fizban:BAAALAADCgYIDgAAAA==.',Fl='Fluffy:BAAALAAECgYIEgABLAAFFAMICQAUAJcbAA==.',Fo='Forestgun:BAAALAAECgMIBAAAAA==.',Fr='Fraco:BAAALAADCgMIBAAAAA==.Fregs:BAAALAAECgYIBgAAAA==.Frigodedo:BAAALAAECgYICwABLAAECgcIBwAJAAAAAA==.',Fu='Fulano:BAAALAADCggICgABLAAFFAIIBQAaAK8iAA==.Furbi:BAAALAAECgYIDgAAAA==.',['Fü']='Fürrafuriosa:BAACLAAFFIEKAAIBAAMIdSE+BgAmAQABAAMIdSE+BgAmAQAsAAQKgSwAAgEACAgYJkwBAHgDAAEACAgYJkwBAHgDAAAA.',Ga='Galathiel:BAABLAAFFIEGAAIbAAUIJxX7BACsAQAbAAUIJxX7BACsAQAAAA==.Gargarita:BAAALAAECgIIAgAAAA==.Garo:BAAALAADCggIDQAAAA==.Gatoo:BAABLAAECoEqAAIcAAgIjxNTHgADAgAcAAgIjxNTHgADAgAAAA==.Gayman:BAAALAADCgYIBgAAAA==.',Gi='Giocrimsondh:BAAALAAECgIIAgAAAA==.',Gn='Gneshia:BAAALAADCgYIBQAAAA==.',Go='Gordelion:BAAALAAECgMIBQAAAA==.',['Gá']='Gálador:BAAALAAECgYIEwAAAA==.',['Gø']='Gøldita:BAAALAADCgYICAAAAA==.',Ha='Haka:BAAALAAFFAIIAgAAAA==.Harbodk:BAABLAAECoEVAAIVAAcIYCMFJAC+AgAVAAcIYCMFJAC+AgAAAA==.Harddboiled:BAAALAAECgYIBgABLAAECggIFQAVAGAjAA==.Harishan:BAACLAAFFIEGAAMMAAIIVh7sAgCkAAAMAAIIjhzsAgCkAAAdAAIInBJjCgCWAAAsAAQKgSAABR0ACAiaHXgLAHUCAB0ACAjBHHgLAHUCAAwABwg8GnAJAB4CABIABgg7ET5pABoBABsABQgsEZNeAP8AAAAA.Harune:BAAALAADCggIDgAAAA==.Hashiba:BAABLAAECoEYAAMXAAYIew5UmwAMAQAXAAYIew5UmwAMAQAZAAYIPgQphQDRAAAAAA==.Hauk:BAAALAAECggICAAAAA==.',He='Heal:BAAALAAFFAMIBQAAAQ==.Hexygranny:BAABLAAFFIEGAAIXAAIIIx0JHgCrAAAXAAIIIx0JHgCrAAABLAAFFAMICAAIAAUfAA==.',Hi='Hikikomori:BAAALAADCgMIAwAAAA==.Hikäri:BAAALAADCggIEAAAAA==.Historia:BAAALAAECgYIBgAAAA==.',Ho='Hodinz:BAACLAAFFIEGAAIUAAIIeyTaEgDYAAAUAAIIeyTaEgDYAAAsAAQKgRQAAhQABgi9JAAcAHcCABQABgi9JAAcAHcCAAAA.Holy:BAAALAAECgYIBwAAAA==.',Hu='Huroncilla:BAAALAAECgEIAQAAAA==.Hustdnoe:BAAALAADCggICwAAAA==.',Hy='Hyuuga:BAABLAAECoEdAAIMAAgIixnbCAAqAgAMAAgIixnbCAAqAgAAAA==.',['Hê']='Hêlel:BAAALAAECgMIAwAAAA==.',Ib='Ibarâki:BAAALAAECgIIAgAAAA==.',Id='Idril:BAAALAAECgIIAgAAAA==.',Il='Illander:BAABLAAECoEdAAIEAAgI3BblTQAqAgAEAAgI3BblTQAqAgAAAA==.',In='Inøri:BAAALAADCggICAABLAAFFAYIEQAVAKoYAA==.',It='Ithilmar:BAAALAAECgcIEwAAAA==.',Iv='Ivaino:BAAALAAFFAIIAwAAAA==.',Iz='Izanagi:BAAALAADCgYIBgAAAA==.Izyr:BAABLAAFFIEGAAIaAAIIixrBGgCMAAAaAAIIixrBGgCMAAAAAA==.Izzet:BAAALAAECgEIAQAAAA==.',Ja='Jabaki:BAAALAADCggICAAAAA==.Jalunne:BAAALAAECgEIAQAAAA==.Jamarior:BAAALAAECggIDgABLAAECggIIwACAP0lAA==.James:BAAALAADCgcIBwAAAA==.Jarezs:BAAALAADCgQIBAAAAA==.',Jh='Jhoira:BAACLAAFFIEHAAITAAMIkSQMBgAxAQATAAMIkSQMBgAxAQAsAAQKgSMAAhMACAgqJrMBAGEDABMACAgqJrMBAGEDAAAA.',Ji='Jigari:BAAALAADCgcIBwABLAAECgYIBgAJAAAAAA==.Jinwoo:BAAALAADCgYICAAAAA==.Jinwøø:BAAALAAECgIIBAAAAA==.',Ju='Jusus:BAAALAAECgEIAQAAAA==.',Ka='Kaeli:BAAALAAECggIDgAAAA==.Kaelix:BAAALAADCgYIBgAAAA==.Kaesy:BAAALAAECgYIBgAAAA==.Kaeus:BAACLAAFFIEOAAIIAAUIrRzmCgDHAQAIAAUIrRzmCgDHAQAsAAQKgSMAAwgACAgZJvQOABkDAAgACAgGJvQOABkDAB4AAQhSJVkVAG8AAAAA.Kai:BAACLAAFFIEGAAIOAAMItxj8GQC9AAAOAAMItxj8GQC9AAAsAAQKgRoABA4ABgiEIMlaANMBAA4ABgjtHMlaANMBABoABghEGjo9AKkBAB8AAQjrDbUfAD0AAAEsAAUUAwgJABwAsBgA.Kaizen:BAACLAAFFIEJAAIcAAMIsBinAwD7AAAcAAMIsBinAwD7AAAsAAQKgRwAAhwACAhKJJYFACgDABwACAhKJJYFACgDAAAA.Kalthyr:BAAALAAECgcICwAAAA==.Kalyana:BAAALAADCgYIBgAAAA==.Kamu:BAAALAADCgcIBwAAAA==.Karel:BAABLAAECoEdAAIEAAgIrR60RABDAgAEAAgIrR60RABDAgAAAA==.Karlopaloq:BAAALAADCggICAABLAAECgMIAwAJAAAAAA==.Karzog:BAAALAAECgYICgAAAA==.Kattherine:BAAALAADCggICQAAAA==.',Ke='Keephe:BAABLAAECoEnAAMXAAgI8wnUjwAlAQAXAAgI8wnUjwAlAQAZAAUI9wrefQD2AAAAAA==.Kekzz:BAACLAAFFIEIAAINAAIIhRuNKwCZAAANAAIIhRuNKwCZAAAsAAQKgRUAAg0ABgjqGjJcAOgBAA0ABgjqGjJcAOgBAAAA.Kekô:BAAALAAECgYIDQAAAA==.Keros:BAABLAAECoEnAAQgAAgIqx6OAgDEAgAgAAgIqx6OAgDEAgAhAAcIdxYJNQDSAQAUAAgICg8dQACyAQAAAA==.Kevdh:BAAALAAECgIIAgABLAAFFAIIBgAVAKQiAA==.',Kh='Kherak:BAAALAADCggICAAAAA==.Khoda:BAAALAADCggIEgABLAAECgYICgAJAAAAAA==.',Ki='Kilin:BAAALAADCgcICQABLAAECgcICwAJAAAAAA==.Kiura:BAAALAAECgIIAgAAAA==.Kivradash:BAAALAAECgYICgAAAA==.',Ko='Kotonoha:BAAALAADCgQICAABLAAFFAQICgAEABgmAA==.',Kr='Krashus:BAAALAADCgcIDwABLAAECgUICAAJAAAAAA==.Kritus:BAACLAAFFIEfAAIiAAYIniOKAAByAgAiAAYIniOKAAByAgAsAAQKgTEAAiIACAitJoUAAIcDACIACAitJoUAAIcDAAAA.Krutus:BAAALAAECggIEAABLAAFFAYIHwAiAJ4jAA==.',Kt='Ktrÿn:BAAALAAECgYIEQABLAAECggIDAAJAAAAAA==.',Ku='Kudo:BAACLAAFFIEOAAIcAAQI3SKEAQCEAQAcAAQI3SKEAQCEAQAsAAQKgSYAAhwACAhgJjEBAH4DABwACAhgJjEBAH4DAAAA.Kudodru:BAAALAAECgYIDAABLAAFFAQIDgAcAN0iAA==.Kuromi:BAAALAAECgYIDwAAAA==.',Ky='Kylana:BAAALAAECgYIDAABLAAECgcICwAJAAAAAA==.Kymm:BAABLAAECoEaAAIIAAgIcSK4HgDDAgAIAAgIcSK4HgDDAgAAAA==.Kypa:BAACLAAFFIEHAAIIAAII7iISJQC0AAAIAAII7iISJQC0AAAsAAQKgSYAAggABwhHIy4qAIsCAAgABwhHIy4qAIsCAAAA.Kyria:BAAALAAECgIIAgAAAA==.Kyriell:BAAALAAECggICAAAAA==.',['Kä']='Kärîsa:BAAALAAECgUICAAAAA==.',La='Lamari:BAAALAAECgIIAgAAAA==.Lautsuki:BAABLAAECoEbAAIhAAcIKAVJWwAeAQAhAAcIKAVJWwAeAQAAAA==.',Le='Leadrel:BAAALAAECgYIBgAAAA==.Leapofail:BAAALAAECgMIAwABLAAFFAIIBwANADMiAA==.Leechuu:BAAALAADCggICAAAAA==.Leviosa:BAAALAADCggICAAAAA==.',Li='Lightgirl:BAAALAAECgIIAgAAAA==.Limon:BAAALAADCgIIAgAAAA==.Liräz:BAAALAADCgYIBQABLAAECgUICAAJAAAAAA==.',Lo='Loxiath:BAAALAADCgYIDgABLAAECgUICAAJAAAAAA==.',Lu='Lucy:BAAALAAECgMIAwAAAA==.Lulaby:BAAALAAECgMIAwABLAAFFAIIBQAjAGIiAA==.Lumobm:BAABLAAECoEfAAMOAAcI6yKKHgCvAgAOAAcI6yKKHgCvAgAaAAIIUxTSkgB0AAAAAA==.Lumodu:BAAALAAECgIIAwAAAA==.Lumopris:BAAALAAECgUICAAAAA==.Lunastrazsa:BAAALAADCgEIAQAAAA==.Luzdivina:BAAALAAECgcICAAAAA==.',Ly='Lynm:BAAALAAFFAIIAgAAAA==.Lyonlock:BAABLAAECoEWAAQFAAgIPBYzQwD+AQAFAAcImhczQwD+AQAkAAMI9xRfXwDCAAAlAAMIXQJRJwCTAAAAAA==.Lysana:BAAALAADCgYICwAAAA==.',['Lô']='Lôcki:BAABLAAECoEsAAIkAAgIiSQXAwAyAwAkAAgIiSQXAwAyAwAAAA==.',Ma='Maddax:BAAALAAECgYIEAAAAA==.Maddox:BAAALAADCgcIBQAAAA==.Madriak:BAAALAAECgUIBwAAAA==.Magitus:BAAALAAECgYIEAABLAAFFAIIBgAVAKQiAA==.Magufita:BAAALAADCggIDQAAAA==.Malacat:BAAALAADCggICAAAAA==.Malapipa:BAAALAADCgUIBQAAAA==.Maliketh:BAABLAAECoEbAAIPAAcIFxKAGwDIAQAPAAcIFxKAGwDIAQAAAA==.Manoplas:BAAALAAECgYICgABLAAECgYICgAJAAAAAA==.Manáfila:BAAALAAECgYIBwAAAA==.Maped:BAACLAAFFIEKAAIhAAMIshd0DAD8AAAhAAMIshd0DAD8AAAsAAQKgSoAAyEACAiMIB8PAOkCACEACAiMIB8PAOkCACAAAQjCHAAAAAAAAAAA.Mariah:BAAALAADCgQIBAAAAA==.Marialitas:BAAALAAECgUICAAAAA==.Maribear:BAABLAAECoEUAAQbAAYIwRy2MwC/AQAbAAYIwRy2MwC/AQASAAUIWhITbQAOAQAdAAII2hGsOgBYAAAAAA==.Marikonis:BAAALAAECgcIBwABLAAFFAUIBQAXACQQAA==.Marilight:BAAALAAECgQIBQAAAA==.Marimurk:BAAALAAECgIIAgAAAA==.Mariwar:BAAALAADCgQIBAAAAA==.',Me='Melibeâ:BAABLAAECoEWAAMZAAcI4R2LJwBTAgAZAAcI4R2LJwBTAgAXAAMINxUl1wCcAAAAAA==.Memories:BAABLAAECoEjAAIIAAgIrBpmOgBDAgAIAAgIrBpmOgBDAgAAAA==.Mendatron:BAAALAAECggIDAAAAA==.Meredil:BAAALAAECgYICwAAAA==.',Mi='Mignobrew:BAAALAAECgQIBAABLAAFFAQIBwAHAMAUAA==.Mignomonk:BAACLAAFFIEHAAIHAAQIwBQ4BgAPAQAHAAQIwBQ4BgAPAQAsAAQKgRQAAgcACAhYHoULAIkCAAcACAhYHoULAIkCAAAA.Mignopala:BAAALAADCggICAABLAAFFAQIBwAHAMAUAA==.Milennia:BAAALAAECgQIBAAAAA==.Mimari:BAAALAAECgYICwAAAA==.Minze:BAABLAAECoEbAAIgAAcIcSL2AgCuAgAgAAcIcSL2AgCuAgAAAA==.Missko:BAAALAAECgMIAwAAAA==.',Mj='Mjuarez:BAAALAAECgIIAwAAAA==.',Mo='Moghedien:BAABLAAECoEZAAIhAAcIbRevLwDwAQAhAAcIbRevLwDwAQAAAA==.Mokinto:BAAALAAECgYICwAAAA==.Moonfall:BAAALAADCggICAAAAA==.Moonlady:BAABLAAECoEjAAINAAcI8RTCYADdAQANAAcI8RTCYADdAQAAAA==.Mordekalé:BAABLAAECoEpAAMdAAgIiRnYDwArAgAdAAgIHRfYDwArAgAbAAUIrBupgQBdAAAAAA==.Morjek:BAABLAAECoEbAAIUAAgI/hkPGwB9AgAUAAgI/hkPGwB9AgAAAA==.',Mu='Mugorne:BAAALAAECgQIBAAAAA==.Mulkdrog:BAAALAADCggICAAAAA==.Muuak:BAAALAAECgUIDAAAAA==.',['Mï']='Mïlky:BAAALAAECgQIBAABLAAFFAIIAwAJAAAAAA==.',Na='Nadrog:BAAALAAFFAEIAQABLAAFFAUIEwAFAK0NAA==.Naerith:BAABLAAFFIEJAAISAAUI1RmnAwDCAQASAAUI1RmnAwDCAQAAAA==.Naxsar:BAABLAAECoEmAAIVAAgIxSM1CwA7AwAVAAgIxSM1CwA7AwAAAA==.Nazah:BAAALAADCgMIAwAAAA==.',Ne='Nei:BAABLAAECoEXAAIEAAYIPQyNvwBHAQAEAAYIPQyNvwBHAQAAAA==.Neklaus:BAAALAAECgYICQABLAAFFAIIBQADAAIRAA==.Nemuk:BAAALAAECggIBQAAAA==.Nenya:BAACLAAFFIEFAAIjAAIIYiKLDADNAAAjAAIIYiKLDADNAAAsAAQKgSsAAyMACAjEHTwPAHkCACMACAjEHTwPAHkCAAQABwgsHxQ7AGACAAAA.Nepo:BAABLAAECoElAAQTAAgICRWfFQDdAQATAAgICRWfFQDdAQAGAAcIcw7yKgB6AQAHAAUItBBWLgD6AAAAAA==.Nerfux:BAAALAADCgMIAwABLAAECgUICAAJAAAAAA==.Nesaga:BAABLAAECoEhAAIOAAcIsxrWRwAIAgAOAAcIsxrWRwAIAgAAAA==.Neveralways:BAAALAAECggICQAAAA==.Neøx:BAAALAADCggICAAAAA==.',Ni='Niara:BAAALAAECgYICgAAAA==.Niariel:BAAALAADCgcIBwAAAA==.Nica:BAAALAADCgQIBAAAAA==.Niña:BAAALAAECgIIBQAAAA==.',No='Nocuro:BAABLAAECoEVAAIEAAgIGR6gJgCyAgAEAAgIGR6gJgCyAgAAAA==.Notmari:BAAALAADCgMIAQAAAA==.',Nu='Nuryys:BAAALAAECggIEQAAAA==.',Ny='Nymfrost:BAAALAAECggICAABLAAECggIEQAJAAAAAA==.Nytheris:BAAALAADCgcIBwAAAA==.',['Nä']='Nämi:BAAALAAECgYIBwAAAA==.',['Në']='Nëzükô:BAAALAADCgYIBgAAAA==.',Oz='Ozar:BAABLAAFFIESAAIZAAUIvyWLAwAcAgAZAAUIvyWLAwAcAgABLAAFFAYIFQAhAI0kAA==.',Pa='Palataza:BAAALAAECggICAAAAA==.Pandakuduro:BAAALAADCgYIBgAAAA==.Patucha:BAAALAADCgcIBwAAAA==.',Pe='Pekebell:BAAALAADCggIEAAAAA==.Pema:BAAALAAECgYIBgABLAAECggIIAAOANEeAA==.',Pi='Picaro:BAAALAADCggICAAAAA==.Pium:BAABLAAECoEqAAIOAAgITSJKIACmAgAOAAgITSJKIACmAgAAAA==.',Pr='Prepared:BAACLAAFFIEHAAINAAIIMyIZGADMAAANAAIIMyIZGADMAAAsAAQKgRsAAg0ABwhUIdwtAIACAA0ABwhUIdwtAIACAAAA.',Ps='Pstdh:BAABLAAECoEgAAICAAgI/BrMDQBYAgACAAgI/BrMDQBYAgAAAA==.Pstdk:BAAALAAECggIEAAAAA==.',Ra='Rahzar:BAABLAAECoEkAAImAAcIzhXbDADoAQAmAAcIzhXbDADoAQAAAA==.Rainy:BAAALAAECgIIAgABLAAECggIIQACAPAlAA==.Rakhsa:BAAALAAECgYIBgABLAAFFAMIBgAaAIsaAA==.Ranzens:BAAALAAECgIIBAAAAA==.Rasgullx:BAAALAAECgIIAgABLAAFFAYIEgAOAIQfAA==.Ratmela:BAAALAAECgYIEgABLAAECggIKAAjAIMbAA==.Raysniper:BAAALAAECgYIBgABLAAFFAYIDwAVAK0jAA==.',Re='Regar:BAAALAAECggICAAAAA==.Reyexanime:BAAALAAECgUIEAAAAA==.Reznorilla:BAABLAAECoEoAAIjAAgIgxsoDgCEAgAjAAgIgxsoDgCEAgAAAA==.Reznorillaz:BAAALAADCggIDgABLAAECggIKAAjAIMbAA==.',Ri='Rivnex:BAABLAAFFIEGAAIbAAIIqRx9DgC3AAAbAAIIqRx9DgC3AAAAAA==.',Ru='Ruinërø:BAAALAAECgYIBwAAAA==.',Rw='Rwby:BAAALAADCggIEAABLAAFFAMIBwATAJEkAA==.',Ry='Rykush:BAAALAADCggIEAABLAAECgYICgAJAAAAAA==.Rymvil:BAAALAADCgcIBgABLAADCggIFwAJAAAAAA==.Ryuhen:BAAALAADCgcICwAAAA==.',Sa='Sadril:BAAALAAECggICQAAAA==.Saelyth:BAAALAADCgYIDQABLAAECgUICAAJAAAAAA==.Sanator:BAABLAAECoEUAAIUAAYIvhKjVgBZAQAUAAYIvhKjVgBZAQABLAAECggIIgAnAJoaAA==.Sara:BAAALAAECgIIAwABLAAFFAMIBQAJAAAAAA==.Sareena:BAAALAAECgYIEQAAAA==.Sathela:BAAALAAECgUICAAAAA==.',Sc='Scalyflier:BAABLAAECoEfAAILAAgInByVEACdAgALAAgInByVEACdAgAAAA==.',Se='Segarroamego:BAAALAAECgcIBwAAAA==.Seldini:BAAALAAECgYIDAAAAA==.Seldru:BAAALAAECgUICQABLAAECggIKgAUAJgjAA==.Selron:BAABLAAECoEcAAMXAAgIYiNuCgD9AgAXAAgIYiNuCgD9AgAZAAEIBwnirAA0AAAAAA==.Selronz:BAABLAAECoEqAAIUAAgImCNJCAAaAwAUAAgImCNJCAAaAwAAAA==.Selzerg:BAAALAADCggICAABLAAECggIKgAUAJgjAA==.Sethyr:BAAALAAECggIDQAAAA==.',Sh='Shadicar:BAAALAADCgcICAAAAA==.Shadoppler:BAABLAAFFIEKAAIhAAMIpyVWCQBGAQAhAAMIpyVWCQBGAQAAAA==.Sharwyn:BAABLAAECoEXAAIEAAcIXRmfagDlAQAEAAcIXRmfagDlAQAAAA==.Shattered:BAAALAADCgYIBgAAAA==.Shaylix:BAAALAAFFAIIAgAAAA==.Shel:BAABLAAECoEWAAISAAgI1iAhDADeAgASAAgI1iAhDADeAgABLAAFFAQICQAJAAAAAA==.Shinedown:BAAALAAECgQIBAABLAAFFAIICAAGALIdAA==.Shinøa:BAACLAAFFIEFAAINAAMIKRWhEwDvAAANAAMIKRWhEwDvAAAsAAQKgRoAAg0ACAjYHvkeAMkCAA0ACAjYHvkeAMkCAAEsAAUUBggRABUAqhgA.Shiro:BAACLAAFFIETAAIGAAUIYiQXAgDeAQAGAAUIYiQXAgDeAQAsAAQKgR8AAgYACAjfJSECAGMDAAYACAjfJSECAGMDAAAA.Shufflylona:BAAALAAECggIDgAAAA==.Shywarr:BAAALAAECgQIBQABLAAFFAQICQAIAFIeAA==.',Si='Silent:BAABLAAECoEmAAIVAAcIUCL9JgCyAgAVAAcIUCL9JgCyAgAAAA==.',Sk='Skaru:BAAALAADCgYIBgAAAA==.',So='Sosias:BAAALAADCggICAABLAAECgcIFgAZAOEdAA==.Soycerdota:BAAALAAFFAEIAQABLAAECgcIMAAdAA0mAA==.',Sp='Sputnik:BAAALAAECgMIAwAAAA==.',St='Starrix:BAAALAAECggIEAAAAA==.Starti:BAAALAAECgUIBQAAAA==.Statham:BAACLAAFFIEIAAIDAAMIsh9gDgARAQADAAMIsh9gDgARAQAsAAQKgS0AAgMACAhwJUMEAGoDAAMACAhwJUMEAGoDAAAA.Stevendx:BAAALAADCggIDgAAAA==.Stompy:BAABLAAECoEeAAIDAAcIeBOHTgDPAQADAAcIeBOHTgDPAQAAAA==.Stonelee:BAAALAAECggIDgABLAAFFAUIFQADAEcbAA==.',Su='Sunfall:BAAALAADCggICAAAAA==.Suo:BAABLAAECoErAAIDAAgIFCRPEQAHAwADAAgIFCRPEQAHAwAAAA==.Supay:BAAALAADCgcIBwAAAA==.Suw:BAAALAADCggIEAAAAA==.',Sx='Sxmnx:BAAALAAECgYIBgABLAAFFAIIBgAbAKkcAA==.Sxo:BAAALAAFFAIIAgABLAAECgcIMAAdAA0mAA==.',Sy='Syldraris:BAABLAAECoEhAAINAAcIyRptTgAMAgANAAcIyRptTgAMAgAAAA==.Syndern:BAAALAAECgMIBAAAAA==.Synphony:BAAALAADCgcICwAAAA==.Syramil:BAAALAADCgcIDAABLAAECgUICAAJAAAAAA==.',['Sí']='Símaco:BAAALAAECgEIAQAAAA==.',['Sï']='Sïsär:BAAALAAECgYIDgAAAA==.',['Sø']='Sølaire:BAABLAAECoEiAAIWAAgIJCDqBwDdAgAWAAgIJCDqBwDdAgAAAA==.',Ta='Takibi:BAAALAAECgcICQAAAA==.Tambör:BAAALAADCgYIBgABLAAFFAIIAwAJAAAAAA==.Taozu:BAAALAAECgIIAwAAAA==.Tariok:BAAALAAECgUIDgAAAA==.Taro:BAAALAAECgYIBwAAAA==.Tausondre:BAAALAADCgEIAQAAAA==.',Th='Thandriel:BAAALAADCgcIDQAAAA==.Theroc:BAAALAAECgcIBwAAAA==.Thorios:BAACLAAFFIEGAAIdAAIIwhyXBgC3AAAdAAIIwhyXBgC3AAAsAAQKgSQAAh0ACAiNILMFAO8CAB0ACAiNILMFAO8CAAEsAAUUBggaAAgAcBsA.Thormenthxo:BAAALAAECggIBgABLAAFFAIICAAXAPQZAA==.Thormentus:BAAALAAECgYIEAAAAA==.Thoughtseize:BAAALAADCggICAAAAA==.Thraindal:BAAALAADCggICAABLAAFFAUIEgASAOYcAA==.',Ti='Tienesfuego:BAABLAAECoEfAAIcAAcIlwvWOABpAQAcAAcIlwvWOABpAQAAAA==.Tiridh:BAAALAAECgMIAwAAAA==.Tirimonk:BAAALAAECgIIAgABLAAECgMIAwAJAAAAAA==.Tizzu:BAACLAAFFIEFAAIWAAIIuh3LCACvAAAWAAIIuh3LCACvAAAsAAQKgSgAAhYACAiMJP0CAEkDABYACAiMJP0CAEkDAAAA.',Tp='Tpartoos:BAAALAAECgIIAgAAAA==.',Tr='Treelandar:BAAALAADCgcIBwAAAA==.Trektar:BAAALAAECgMIBwAAAA==.Trukumakdo:BAAALAADCggICgAAAA==.',Tu='Tumari:BAAALAADCgEIAQAAAA==.',Ty='Tykoldmage:BAACLAAFFIEIAAIIAAMIBR8LFQAcAQAIAAMIBR8LFQAcAQAsAAQKgSMAAggACAgBJPkRAAkDAAgACAgBJPkRAAkDAAAA.',['Tï']='Tïzzu:BAAALAAECgMIAwABLAAFFAIIBQAWALodAA==.',Uk='Ukaste:BAAALAAECgQIBQAAAA==.',Ur='Urkog:BAABLAAECoEjAAIHAAgIlxwxCwCRAgAHAAgIlxwxCwCRAgAAAA==.',Va='Vaartan:BAABLAAECoEUAAIgAAcIlyQVAgDiAgAgAAcIlyQVAgDiAgAAAA==.Vanishslvt:BAAALAAECgIIAgAAAA==.Varela:BAAALAAECgEIAgAAAA==.',Ve='Veciego:BAABLAAECoEmAAIVAAgIHiLwGwDjAgAVAAgIHiLwGwDjAgAAAA==.Venly:BAABLAAECoEUAAIEAAgItCJ6CgBIAwAEAAgItCJ6CgBIAwAAAA==.',Vi='Vi:BAAALAAECgcIBwAAAA==.Vildhjarta:BAAALAAECgYICAAAAA==.Viruzzdk:BAAALAAECggIEwAAAA==.',Vo='Voycieego:BAAALAAECgEIAQABLAAECggIJgAVAB4iAA==.',Vy='Vyre:BAAALAAECgYIDAAAAA==.Vyssra:BAAALAAECgQIBwABLAAECgcIDwAJAAAAAA==.',Wa='Wannabe:BAACLAAFFIEFAAIEAAIIOiX4EgDbAAAEAAIIOiX4EgDbAAAsAAQKgTQAAgQACAhNI8IRAB4DAAQACAhNI8IRAB4DAAAA.',We='Weathereport:BAAALAADCggIBQAAAA==.Weirdwaters:BAABLAAFFIEFAAIXAAUIJBDgBwBhAQAXAAUIJBDgBwBhAQAAAA==.Wenn:BAAALAAECgYIDAAAAA==.',Wi='Wikingame:BAAALAAECgcIDwAAAA==.Willytoleda:BAAALAAECgYIDgABLAAFFAYIEwAQAFMZAA==.Wingardium:BAAALAADCggICAAAAA==.',Wu='Wuarra:BAAALAAECgIIAgABLAAFFAIIBQAaAK8iAA==.',['Wê']='Wênn:BAABLAAECoEfAAIXAAgIKB1SIAByAgAXAAgIKB1SIAByAgAAAA==.',Xa='Xandrian:BAAALAADCggIDwABLAAECgYICgAJAAAAAA==.',Xe='Xerek:BAAALAAECgYIDAAAAA==.Xerivy:BAAALAADCgYIBgAAAA==.',Xi='Xirdas:BAACLAAFFIEHAAINAAII5R46HQCyAAANAAII5R46HQCyAAAsAAQKgSYAAg0ACAi8I5ANAC4DAA0ACAi8I5ANAC4DAAAA.Xivölinhú:BAABLAAECoEWAAIPAAYI3yDoEwATAgAPAAYI3yDoEwATAgAAAA==.',Xj='Xjbv:BAAALAAECgcIBwABLAAFFAYIEwAkANogAA==.',Xo='Xouba:BAABLAAECoEYAAMhAAcIAxaOLgD3AQAhAAcIAxaOLgD3AQAUAAIIzhjZjgCGAAAAAA==.',['Xû']='Xûrû:BAAALAADCgcIBwAAAA==.',Yh='Yhönkiriel:BAAALAADCggIEwABLAAECgYICgAJAAAAAA==.',Yo='Yona:BAACLAAFFIEHAAIZAAIIqRu7GAClAAAZAAIIqRu7GAClAAAsAAQKgTcAAhkACAgrHy4WAMsCABkACAgrHy4WAMsCAAAA.',Yu='Yugo:BAAALAAECgYIBgAAAA==.',Za='Zadeny:BAAALAAECgMIAwAAAA==.Zake:BAABLAAECoEVAAINAAYIYB+OTAASAgANAAYIYB+OTAASAgAAAA==.Zakishen:BAACLAAFFIEVAAIDAAUIRxtnBwDIAQADAAUIRxtnBwDIAQAsAAQKgSkAAgMACAgEJUEGAFkDAAMACAgEJUEGAFkDAAAA.Zalaek:BAABLAAECoEbAAIBAAYINR2yIAD4AQABAAYINR2yIAD4AQAAAA==.Zandalari:BAAALAAECgYIDgAAAA==.',Ze='Zekro:BAABLAAECoEXAAIKAAcIcyFeAwCtAgAKAAcIcyFeAwCtAgAAAA==.Zenva:BAACLAAFFIEHAAIDAAIITR2wFQDBAAADAAIITR2wFQDBAAAsAAQKgSQAAgMACAg1IvURAAMDAAMACAg1IvURAAMDAAEsAAUUBggaAAgAcBsA.',Zi='Zinete:BAAALAAECgYIBgAAAA==.Zinoth:BAAALAAECgUIBQAAAA==.Zirack:BAACLAAFFIERAAMVAAYIqhjxBgDiAQAVAAYIBxjxBgDiAQAPAAMIKxbUBAAOAQAsAAQKgS4AAxUACAg2JR4MADYDABUACAhMJB4MADYDAA8ACAhfIosMAHUCAAAA.Ziri:BAAALAAECggICgABLAAFFAYIEQAVAKoYAA==.',Zo='Zohe:BAAALAADCgcIBwAAAA==.Zork:BAACLAAFFIEaAAMIAAYIcBt1CQDXAQAIAAUILB51CQDXAQAeAAEIww2pCABPAAAsAAQKgTAAAwgACAg2Jg8CAHsDAAgACAg2Jg8CAHsDAB4AAQheHBoaAEYAAAAA.',Zr='Zrèox:BAAALAAECgYIDwAAAA==.Zréox:BAAALAAECgYICwAAAA==.',Zu='Zuk:BAAALAAECgYIBgAAAA==.',['Zø']='Zørku:BAAALAAECgMIBwAAAA==.',['Ál']='Álex:BAACLAAFFIETAAIEAAYIkR5AAQBQAgAEAAYIkR5AAQBQAgAsAAQKgT4AAwQACAjlJkgAAKIDAAQACAjlJkgAAKIDACMAAgieALJsABgAAAAA.',['Âl']='Âlêx:BAABLAAECoEoAAIUAAgIqh+HEgC7AgAUAAgIqh+HEgC7AgAAAA==.',['Éd']='Édryel:BAAALAAECgUIDgAAAA==.',['Îv']='Îvân:BAAALAADCgYICAAAAA==.',['Ðu']='Ðun:BAABLAAECoEZAAINAAYItx7TWQDtAQANAAYItx7TWQDtAQAAAA==.',['Òs']='Òsci:BAAALAAECgIIAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end