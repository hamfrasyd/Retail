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
 local lookup = {'Warlock-Destruction','Paladin-Holy','Paladin-Retribution','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Fury','Mage-Fire','Priest-Holy','Mage-Arcane','Monk-Windwalker','Shaman-Elemental','DemonHunter-Vengeance','Unknown-Unknown','Evoker-Devastation','Evoker-Preservation','Monk-Mistweaver','Mage-Frost','Shaman-Restoration','Druid-Restoration','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Druid-Feral','DemonHunter-Havoc','DeathKnight-Unholy','DeathKnight-Blood','Priest-Shadow','Warrior-Protection','Monk-Brewmaster','Warrior-Arms','Warlock-Affliction','Druid-Balance','Hunter-Survival','Warlock-Demonology',}; local provider = {region='EU',realm='Sunstrider',name='EU',type='weekly',zone=44,date='2025-09-22',data={Aa='Aaba:BAABLAAECoEVAAIBAAcIqhQ8TQDQAQABAAcIqhQ8TQDQAQAAAA==.',Ae='Aelx:BAAALAAECgcIBwAAAA==.',Ak='Akariel:BAABLAAECoEcAAMCAAgIJSTCAQA+AwACAAgIJSTCAQA+AwADAAEIagpfNwEzAAAAAA==.Aksorz:BAAALAAECgMIBAAAAA==.',An='Andrak:BAABLAAECoEVAAIEAAgInh6hHgDTAgAEAAgInh6hHgDTAgAAAA==.Angie:BAABLAAECoEgAAMFAAgIcyQvBwBDAwAFAAgIcyQvBwBDAwAGAAEIoR5wmQBZAAABLAAFFAUIDAADACYaAA==.Annamae:BAAALAAECgUIBwAAAA==.Annamosity:BAAALAAECgcIDgAAAA==.Annatomic:BAAALAAECgQIBAAAAA==.Antaress:BAABLAAECoEZAAIHAAcI/BdLDwDEAQAHAAcI/BdLDwDEAQAAAA==.Anurr:BAAALAAECgIIAgAAAA==.',Ar='Arathea:BAAALAAECgIIAgAAAA==.Aridemon:BAAALAADCggICAABLAAECggIHAAIAEweAA==.Armelle:BAAALAAECggICAAAAA==.Arvis:BAABLAAECoEbAAIJAAgIihrLAgCUAgAJAAgIihrLAgCUAgAAAA==.Arzely:BAAALAADCgYIDQAAAA==.',As='Asce:BAAALAAECggIDgAAAA==.Ashbery:BAAALAADCgIIAgAAAA==.Ashoofk:BAAALAAECgYIDQAAAA==.Ashyra:BAACLAAFFIEJAAIKAAMIQhcKDQD6AAAKAAMIQhcKDQD6AAAsAAQKgS0AAgoACAjsIaIIABQDAAoACAjsIaIIABQDAAAA.Askebardé:BAAALAAECgYIBwAAAA==.Assumi:BAAALAAECggICAAAAA==.Asumah:BAAALAAECgYIEwABLAAFFAMICwALAPofAA==.',Au='Augustis:BAABLAAECoEiAAIDAAgIlCT5DwAlAwADAAgIlCT5DwAlAwAAAA==.',Av='Averhan:BAAALAAECgYIDgABLAAFFAMIBwAMACkEAA==.Avila:BAAALAADCgUICAAAAA==.',['Aý']='Aýá:BAAALAADCgcIDAAAAA==.',Ba='Babavoss:BAAALAAECgMIAgAAAA==.Baldi:BAAALAADCggICAAAAA==.Balduzzi:BAABLAAECoEgAAINAAgIsRizJQBWAgANAAgIsRizJQBWAgAAAA==.Ballathor:BAAALAAECgIIAgAAAA==.Barlan:BAABLAAECoEpAAIOAAgIWRRDGQC+AQAOAAgIWRRDGQC+AQAAAA==.Barlon:BAAALAADCgYIBgABLAAECggIKQAOAFkUAA==.Barlonn:BAAALAAECgMIAwAAAA==.Barlun:BAAALAADCgYIBgABLAAECggIKQAOAFkUAA==.Barlán:BAAALAADCgcIBwABLAAECggIKQAOAFkUAA==.Basbos:BAAALAADCgUIBQABLAAECgYIEgAPAAAAAA==.',Bb='Bbywoke:BAABLAAECoEZAAMQAAgIVhzHDwCiAgAQAAgIVhzHDwCiAgARAAMITBFCKwCoAAAAAA==.',Be='Beefymagé:BAACLAAFFIEGAAILAAIInRyHKACkAAALAAIInRyHKACkAAAsAAQKgSsAAwsACAgkJQIGAFQDAAsACAgLJQIGAFQDAAkAAQicJZkWAFwAAAAA.Beefymagë:BAAALAADCgYIBgAAAA==.Beerwolf:BAAALAAECgcIEAAAAA==.Ben:BAABLAAECoEcAAIDAAgIEB1APABXAgADAAgIEB1APABXAgAAAA==.',Bi='Biftatwista:BAAALAAECgYICwAAAA==.',Bj='Bjarnulf:BAAALAAECgMIBAAAAA==.',Bl='Blackhowl:BAAALAADCgIIAgAAAA==.Blackthought:BAAALAAECggIEwAAAA==.Blindfíre:BAAALAAECgcIBwAAAA==.Bloodydead:BAAALAAECggIEgABLAAFFAMICgASAFwhAA==.',Bo='Bobbyboucher:BAABLAAECoEXAAMLAAcIthUtWADUAQALAAcIthUtWADUAQATAAEIIRJ/fgAxAAAAAA==.Boblin:BAABLAAECoEcAAIIAAcIzQ4PWACkAQAIAAcIzQ4PWACkAQAAAA==.Bojak:BAAALAADCggICQABLAAECggIGAAUAGciAA==.Borgnarr:BAAALAADCgcIDQAAAA==.',Br='Breokz:BAAALAADCggIDAAAAA==.Broxigan:BAAALAADCgMIAwABLAAECgYIIQADABoYAA==.',Bu='Bublixvi:BAAALAAECgIIAgAAAA==.Burge:BAAALAADCgYIBwAAAA==.Burritoboris:BAACLAAFFIEFAAIFAAMIpxXhEQDeAAAFAAMIpxXhEQDeAAAsAAQKgScAAgUACAhNITAdAK4CAAUACAhNITAdAK4CAAAA.',Ca='Cafù:BAABLAAECoEcAAIVAAgIVybPAAB1AwAVAAgIVybPAAB1AwAAAA==.Capalots:BAAALAAECgcICwAAAA==.Capalotski:BAAALAAECgcIDAAAAA==.',Ch='Charvel:BAAALAADCggICAAAAA==.Chevron:BAAALAADCgMIAwAAAA==.Chumbus:BAABLAAECoEXAAIGAAcIphaJMgDXAQAGAAcIphaJMgDXAQAAAA==.Chunk:BAAALAAECgEIAQABLAAECgcIFwAGAKYWAA==.',Ci='Ciraxis:BAAALAAECgYIBgAAAA==.',Co='Coltor:BAABLAAECoEZAAMWAAcIcBqYDwARAgAWAAcIshiYDwARAgAXAAYILxl/LgCeAQAAAA==.Consabre:BAAALAAECgEIAQAAAA==.Cornu:BAABLAAECoEdAAMDAAgIGxytPABWAgADAAgIpRqtPABWAgAYAAYIsRfiHgC+AQAAAA==.',Cr='Crowley:BAAALAAECgYIBgAAAA==.Crusher:BAAALAAECgYICQAAAA==.',Cu='Curran:BAAALAAECgcIEQAAAA==.',['Cá']='Cáfu:BAAALAADCggIEwAAAA==.',Da='Daendros:BAAALAAECgMIAwAAAA==.Daendryn:BAAALAADCgcIAwAAAA==.Daylen:BAAALAADCggICAAAAA==.',De='Deadclass:BAAALAADCgIIAgAAAA==.Deaddealerke:BAAALAADCggICAAAAA==.Deadrow:BAAALAADCgYIBwAAAA==.Demoesh:BAAALAAECgEIAQAAAA==.Demomage:BAAALAADCgQIBAAAAA==.Demotaz:BAAALAADCggIFgAAAA==.Derpup:BAECLAAFFIETAAIZAAUIqCR+AAAsAgAZAAUIqCR+AAAsAgAsAAQKgSUAAhkACAjBJm0AAIIDABkACAjBJm0AAIIDAAEsAAUUBwgYAAcApSYA.Desi:BAAALAAECggIDwAAAA==.Desteel:BAAALAADCgYIBgAAAA==.Destronarr:BAABLAAECoEcAAIBAAcIBxBIWgCmAQABAAcIBxBIWgCmAQAAAA==.Desync:BAAALAAECgMIBAAAAA==.',Di='Discoyorish:BAABLAAECoEcAAIKAAgICiE/CwD5AgAKAAgICiE/CwD5AgAAAA==.',Do='Dogon:BAAALAAECggICAAAAA==.Dohfos:BAABLAAECoEjAAIUAAgIwhVkPAD7AQAUAAgIwhVkPAD7AQAAAA==.Domadk:BAAALAADCgEIAQAAAA==.Doublejump:BAACLAAFFIEFAAIaAAMIMw40FADhAAAaAAMIMw40FADhAAAsAAQKgRYAAhoACAjpHk4dAM0CABoACAjpHk4dAM0CAAEsAAUUBwgUAAQAWyIA.Dozzyr:BAABLAAECoEbAAMCAAYIBheCKwCPAQACAAYIBheCKwCPAQADAAMI1wzuGgFlAAAAAA==.',Dr='Draewonk:BAAALAAECgcIBwABLAAECgcIGgAJAFcbAA==.Dreagnor:BAABLAAECoEdAAQbAAgIGApGJAB8AQAbAAcIVAlGJAB8AQAcAAgIwQd5HwBBAQAEAAEItQFBUwEcAAAAAA==.Drhouse:BAAALAAECggIEwABLAAECggIIAAFAOsgAA==.Driezer:BAAALAAFFAIIAgAAAA==.Drollemage:BAAALAADCgYIBgAAAA==.',Du='Dumbawumba:BAABLAAECoEkAAILAAgIzhbiPgAqAgALAAgIzhbiPgAqAgAAAA==.',Dw='Dwergfluit:BAAALAADCggIDQAAAA==.',Dy='Dysdemona:BAAALAAECgYIEgAAAA==.',Dz='Dza:BAAALAAECgIIAQAAAA==.',['Dé']='Défibrilator:BAABLAAECoEgAAMKAAgI5BAfOQDMAQAKAAgI5BAfOQDMAQAdAAMIWAZVdQB8AAAAAA==.',Ea='Eachan:BAAALAAECgYICAAAAA==.',Ed='Edgelord:BAAALAAECgMIBQAAAA==.',El='Elevenincher:BAAALAAECgMIAwAAAA==.Elinorana:BAAALAADCggICAAAAA==.Elkstryparen:BAAALAAECggICgAAAA==.Elmina:BAAALAAECgcIEwAAAA==.Elunis:BAABLAAECoEWAAIaAAYIByD3RAAhAgAaAAYIByD3RAAhAgAAAA==.Elùn:BAACLAAFFIEJAAIVAAMI0xooCQAAAQAVAAMI0xooCQAAAQAsAAQKgSgAAhUACAj/IcgHAAQDABUACAj/IcgHAAQDAAAA.',Em='Embry:BAAALAAECgMIAwABLAAECgYIFAAXAEENAA==.Emilos:BAAALAAECggICAAAAA==.',Er='Erp:BAAALAAECggIBwAAAA==.',Es='Eshpriest:BAABLAAECoEjAAMdAAgIMhnnHABoAgAdAAgIMhnnHABoAgAKAAMIFx5OdADuAAAAAA==.',Et='Eti:BAAALAAECgYIBwAAAA==.',Eu='Euphotic:BAAALAAECgMIAwAAAA==.',Ev='Evonizar:BAAALAAECgYIEgAAAA==.',Ex='Exavi:BAAALAAFFAIIAgAAAA==.',Fa='Faervel:BAAALAAECgUIBQABLAAFFAMICQAVANMaAA==.Fatherflaps:BAAALAAECgQIBAABLAAECggIIAAFAOsgAA==.',Fe='Felatra:BAABLAAECoEeAAILAAgIEAgVcwCHAQALAAgIEAgVcwCHAQAAAA==.Felore:BAABLAAECoEcAAIdAAcI+w+TPgCbAQAdAAcI+w+TPgCbAQAAAA==.',Fi='Fireyblade:BAAALAADCggIDwABLAAECggIJQADAJ4cAA==.Fiveincher:BAABLAAECoEgAAIbAAgIHBhCDQBkAgAbAAgIHBhCDQBkAgAAAA==.',Fl='Flaskepost:BAABLAAECoEgAAIaAAgIOgv7eACdAQAaAAgIOgv7eACdAQAAAA==.Flintblade:BAAALAADCgUIBQAAAA==.Flumiis:BAABLAAFFIEGAAIUAAIIUBgmHgCjAAAUAAIIUBgmHgCjAAAAAA==.Flummann:BAAALAAFFAIIAgAAAA==.Flummis:BAACLAAFFIEPAAIRAAUIghg+AwCyAQARAAUIghg+AwCyAQAsAAQKgS4AAhEACAgFIw8CAC4DABEACAgFIw8CAC4DAAAA.Flûffy:BAAALAADCgYIBAAAAA==.',Fo='Foosi:BAAALAAECgcIBwAAAA==.',Fr='Frauj:BAAALAAECgYIDgAAAA==.Frieren:BAAALAAECgIIAgABLAAECgYICAAPAAAAAA==.',Fu='Furiòn:BAABLAAECoEhAAIEAAgIRSJaKgCeAgAEAAgIRSJaKgCeAgAAAA==.Furión:BAAALAAECgEIAQAAAA==.',Ga='Gahandi:BAAALAADCggICAAAAA==.Galdin:BAAALAAECggIEAAAAA==.Gangnamup:BAEBLAAFFIEFAAIMAAMIHhdwBQAFAQAMAAMIHhdwBQAFAQABLAAFFAcIGAAHAKUmAA==.Garosshh:BAAALAAECgYIBgABLAABCgcIBwAPAAAAAA==.',Ge='Genryu:BAAALAADCggICwAAAA==.Geranyll:BAAALAAECgEIAQAAAA==.',Gh='Ghostbuilder:BAAALAAECgIIAQAAAA==.',Gi='Gimlii:BAAALAADCggICAAAAA==.Ginroi:BAAALAAECggICAAAAA==.',Go='Goblingirl:BAABLAAECoEaAAIJAAcIVxt2BAA6AgAJAAcIVxt2BAA6AgAAAA==.Gohan:BAAALAAECgUIDAAAAA==.Gomek:BAABLAAECoEcAAMIAAgITB7cIwCCAgAIAAgIBR3cIwCCAgAeAAUIsBqZRwAMAQAAAA==.Gordrell:BAAALAADCggICAAAAA==.',Gr='Gresh:BAAALAAECgQIBAAAAA==.Greyface:BAAALAADCggICAABLAAECggIEwAPAAAAAA==.Grimkash:BAABLAAECoEeAAIcAAgIshpRDQBCAgAcAAgIshpRDQBCAgAAAA==.',['Gä']='Gäng:BAAALAADCgIIAQAAAA==.',Ha='Hammerdin:BAAALAADCgMIAwAAAA==.Haribka:BAAALAADCggIDAAAAA==.Harryportal:BAAALAAECgYIBgAAAA==.Havaks:BAAALAAECggICAAAAA==.Haxxie:BAAALAADCgcIBwAAAA==.Hazeleyes:BAAALAADCgEIAgAAAA==.',He='Hegge:BAAALAAECgUIBQAAAA==.Hellbringer:BAAALAADCggIDwAAAA==.Hexwhelp:BAAALAAECgMIAwAAAA==.',Hi='Himiko:BAAALAAECgYICAABLAAECgYIIQADABoYAA==.',Ho='Holydruidly:BAAALAAECggICQAAAA==.',Hu='Huntflaps:BAABLAAECoEgAAIFAAgI6yABGQDIAgAFAAgI6yABGQDIAgAAAA==.Huntun:BAAALAAECgMIAwAAAA==.Hunux:BAAALAAECgYICwABLAAECggIEwAPAAAAAA==.',Hx='Hx:BAAALAAECggICAAAAA==.',['Hä']='Hääl:BAAALAADCgIIAgAAAA==.',Ib='Ibo:BAAALAAECggIEwAAAA==.',Ic='Ice:BAAALAAECgIIAgAAAA==.Iceballs:BAAALAAECgYIBgAAAA==.',Il='Ileprechaun:BAAALAAECgMIAwAAAA==.Ilevea:BAAALAAFFAIIAwAAAA==.Illidia:BAAALAADCgcIBwABLAAECgcIGgAJAFcbAA==.Illuné:BAAALAADCggICAABLAAECgUIBwAPAAAAAA==.',Im='Imploding:BAAALAAECgYIBgAAAA==.',In='Infoxicated:BAAALAADCggICAAAAA==.Instigator:BAABLAAECoEWAAIfAAgIHxYMEwD5AQAfAAgIHxYMEwD5AQAAAA==.Intermezzo:BAAALAADCggICAAAAA==.',It='Itswiseomg:BAAALAAECgYIBwAAAA==.',Ja='Jackiie:BAABLAAFFIEGAAIEAAIIiBvZLQChAAAEAAIIiBvZLQChAAAAAA==.Jazmon:BAAALAAECgcIEQAAAA==.',Jh='Jhonnysins:BAAALAADCggICAAAAA==.',Ji='Jimeth:BAABLAAECoElAAIDAAgInhxHLACUAgADAAgInhxHLACUAgAAAA==.Jinbei:BAACLAAFFIEHAAMMAAMIKQSQCgCiAAAMAAMIKQSQCgCiAAASAAIIPwMPEQB0AAAsAAQKgSwAAwwACAi2F4QSAFkCAAwACAi2F4QSAFkCABIACAiZGF0SABgCAAAA.',Jo='Joe:BAAALAADCggIFAAAAA==.Josuas:BAAALAAECgYIDwAAAA==.',Js='Jsonyo:BAAALAAECgYICgAAAA==.',Ju='Jumpup:BAECLAAFFIEGAAIaAAQIPSMXCACtAQAaAAQIPSMXCACtAQAsAAQKgSMAAhoACAgqJcYIAEkDABoACAgqJcYIAEkDAAEsAAUUBwgYAAcApSYA.',Ka='Kalev:BAAALAAECgYIBgAAAA==.Kaljador:BAAALAAECggIEwAAAA==.Kalkyl:BAAALAAECgYICwABLAAECgcICQAPAAAAAA==.Kampkran:BAAALAAECgcICQAAAA==.Kapu:BAAALAAECgYIBgAAAA==.Karenfromhr:BAAALAADCgcIBwAAAA==.Karlmark:BAAALAADCggIAgAAAA==.Kasirius:BAAALAADCggICQAAAA==.Katyparry:BAABLAAECoEhAAIeAAgISSA5CQDpAgAeAAgISSA5CQDpAgAAAA==.Kaykrill:BAAALAAECgIIAgAAAA==.',Ke='Kellà:BAAALAADCggICAABLAAECgYICAAPAAAAAA==.Kerni:BAAALAADCgUIBQAAAA==.Kerno:BAABLAAECoEaAAIUAAgITRSESADTAQAUAAgITRSESADTAQAAAA==.',Kh='Khalaar:BAAALAADCggICAAAAA==.Khar:BAAALAADCgcIBwAAAA==.Kharox:BAAALAADCgcICAABLAAECggIHgAcALIaAA==.',Ki='Kibin:BAAALAAECgMIAwAAAA==.Kitcat:BAAALAADCgYIBgAAAA==.',Kl='Kladd:BAABLAAECoEcAAIVAAcICAvXYgAjAQAVAAcICAvXYgAjAQAAAA==.',Ko='Koras:BAACLAAFFIEIAAIgAAMIjQ8eAQDpAAAgAAMIjQ8eAQDpAAAsAAQKgSUAAiAACAjiIqcBADYDACAACAjiIqcBADYDAAAA.',Kr='Krazey:BAAALAAECgcIDQAAAA==.Kreíos:BAAALAAECggIAgAAAA==.',Ku='Kuw:BAAALAAECgUICQAAAA==.Kuydo:BAABLAAECoEVAAIdAAgIMRcMJAAxAgAdAAgIMRcMJAAxAgAAAA==.',Kv='Kvg:BAAALAAECggIEwAAAA==.',Ky='Kynnia:BAABLAAECoETAAIEAAYIcgc82gAbAQAEAAYIcgc82gAbAQAAAA==.',['Ká']='Kátniss:BAAALAAECgYIBgAAAA==.',['Kí']='Kíng:BAAALAADCggICAAAAA==.',La='Lamiai:BAAALAADCggIDwAAAA==.Landuck:BAAALAAECgcIDwAAAA==.Laquin:BAACLAAFFIEIAAIHAAMIsxyYAQAwAQAHAAMIsxyYAQAwAQAsAAQKgRwAAgcACAi7IYQJADcCAAcACAi7IYQJADcCAAAA.Lassebird:BAABLAAECoEdAAIDAAgIJxIJXQD8AQADAAgIJxIJXQD8AQAAAA==.Lastguard:BAAALAAECgYIBgAAAA==.',Le='Legs:BAABLAAECoEYAAIeAAgILwG5dgAsAAAeAAgILwG5dgAsAAAAAA==.Lev:BAAALAAECgYICgAAAA==.Leviantus:BAABLAAECoEXAAMaAAgInQ49fwCQAQAaAAcIjQ49fwCQAQAOAAEIEA/xVAAzAAAAAA==.',Li='Liubie:BAAALAADCgQIBAAAAA==.',Ll='Lleya:BAAALAAECgYICgABLAAECggIHAAIAEweAA==.',Ln='Lndk:BAAALAAECgUIBwABLAAECgcIDwAPAAAAAA==.',Lo='Loleta:BAAALAADCgMIAwABLAAECgYIEgAPAAAAAA==.Lonelya:BAABLAAECoEgAAMBAAgICRc2MQBEAgABAAgIdxY2MQBEAgAhAAcIXAbtFQBCAQAAAA==.Loord:BAAALAAECgMIAwAAAA==.Losestreak:BAABLAAECoEXAAMQAAgIuBDIIQDnAQAQAAgIuBDIIQDnAQARAAcIAAAAAAAAAAAAAA==.',['Lá']='Lántz:BAAALAADCggICAAAAA==.',Ma='Macmongoloid:BAAALAAECgMIBwAAAA==.Madulun:BAABLAAECoEqAAMNAAgIlgRYaABAAQANAAgIlgRYaABAAQAUAAgI8AT6pwDpAAAAAA==.Majicalman:BAAALAAECgYIBgABLAAECggIJQADAJ4cAA==.Malpriest:BAAALAADCgQIBAAAAA==.Maurees:BAAALAAECgEIAQAAAA==.Mauti:BAACLAAFFIEIAAIEAAIIBxxOJgCuAAAEAAIIBxxOJgCuAAAsAAQKgSEAAgQACAjRIxEKAEEDAAQACAjRIxEKAEEDAAAA.Maxsprittet:BAAALAADCgcIBwAAAA==.',Mc='Mcdonnell:BAAALAADCgcIBwAAAA==.',Me='Mellanmjolk:BAAALAAECgcIBwABLAAECggIFAAIAOYVAA==.Mesmer:BAAALAAECgMIBAAAAA==.',Mi='Minty:BAAALAADCggICAABLAAFFAIIBgADAPQZAA==.Misschieef:BAAALAADCgIIAgAAAA==.Mistyjohn:BAAALAADCgcIBwABLAAFFAIIBgARACofAA==.',Mj='Mjolksyra:BAABLAAECoEUAAIIAAgI5hXuPgD8AQAIAAgI5hXuPgD8AQAAAA==.',Mo='Moila:BAAALAAECgYIBwAAAA==.Morhoprst:BAAALAAECgYICQAAAA==.Moudo:BAAALAAECggIEwAAAA==.',My='Myon:BAACLAAFFIEFAAMVAAIIeRg6GACZAAAVAAIIeRg6GACZAAAiAAEIegirHwA8AAAsAAQKgRwAAyIACAjBGGUjABcCACIACAjBGGUjABcCABUAAwgyEnyLAKsAAAAA.Myopicant:BAABLAAECoEmAAIKAAgIFwviSACIAQAKAAgIFwviSACIAQAAAA==.',Na='Nargothord:BAABLAAECoEkAAIBAAgIthyCIACfAgABAAgIthyCIACfAgAAAA==.Nazes:BAAALAADCgcIBwAAAA==.',Ne='Nedric:BAAALAAECggICQABLAAECggIIgADAJQkAA==.Nej:BAAALAAECggICQAAAA==.Neophobia:BAAALAAECgYIDQABLAAECggIIAAFAOsgAA==.Nevi:BAAALAADCgUIBQAAAA==.',Ni='Nibblesworth:BAAALAADCgcIBwAAAA==.Niblo:BAAALAAECgQIBAAAAA==.Nickster:BAAALAAECggIEgAAAA==.Nightmärë:BAAALAADCggIDwABLAAECggIHAAQAB0UAA==.Nimhe:BAAALAADCggICQAAAA==.',No='Norris:BAAALAAECgYICAAAAA==.Notmedusa:BAAALAAECgYIEwAAAA==.Notworksafe:BAABLAAECoEjAAIXAAgIChjEFwBFAgAXAAgIChjEFwBFAgAAAA==.',Np='Np:BAAALAAECgYIBgABLAAECggICQAPAAAAAA==.',Ns='Nsfw:BAAALAADCgcIBwAAAA==.',['Ný']='Nýxx:BAABLAAECoElAAIdAAgI/hiNHwBSAgAdAAgI/hiNHwBSAgAAAA==.',Ol='Ollefans:BAABLAAECoEYAAIUAAgICR6BHQB6AgAUAAgICR6BHQB6AgAAAA==.',Oo='Oomadin:BAAALAADCgEIAQAAAA==.',Op='Opräh:BAABLAAECoEZAAILAAgI0CO+GADeAgALAAgI0CO+GADeAgAAAA==.',Or='Ormstryparen:BAAALAAECgQICAABLAAECggICgAPAAAAAA==.',Ou='Ourcaptain:BAABLAAECoEUAAIQAAcIGB8pFgBZAgAQAAcIGB8pFgBZAgAAAA==.',Oy='Oyzmr:BAAALAADCgcIBwAAAA==.',Pa='Palalaladin:BAAALAAECgEIAQABLAAECgcIGgAJAFcbAA==.Patchar:BAAALAAECgQICAAAAA==.',Pb='Pb:BAAALAAECggIEAAAAA==.',Pe='Perona:BAAALAAECgYIBgAAAA==.',Ph='Pheeb:BAAALAAECgEIAQAAAA==.',Pl='Plalalala:BAAALAADCgcIBwAAAA==.',Po='Poesjemeow:BAAALAADCgcIBwAAAA==.Poka:BAEALAAECgYIBgABLAAFFAcIHAADAPIiAA==.Pompa:BAAALAAECgIIAgAAAA==.Pomutzi:BAAALAADCggICAAAAA==.',Pr='Prëdätör:BAAALAAECgIIAgABLAAECggIHAAQAB0UAA==.',Pu='Puntha:BAACLAAFFIELAAIMAAMIQxNSBgDxAAAMAAMIQxNSBgDxAAAsAAQKgTYAAwwACAhGIIkIAO0CAAwACAhGIIkIAO0CAB8ACAhjBdYpAPsAAAAA.Pusekruse:BAABLAAECoEYAAISAAgIQheeEgAUAgASAAgIQheeEgAUAgAAAA==.',Py='Pykken:BAAALAAECgMIBQAAAA==.',['Pô']='Pôlden:BAAALAAECgYIBgABLAAECggIIAANAFIiAA==.',['Pû']='Pûck:BAAALAAECggICQAAAA==.',Qu='Quotay:BAABLAAECoEXAAIjAAgI0xlsBgA5AgAjAAgI0xlsBgA5AgABLAAFFAUIEAAMADMSAA==.Quotey:BAACLAAFFIEQAAIMAAUIMxIYAwCaAQAMAAUIMxIYAwCaAQAsAAQKgSIAAgwACAjZIwIFAC0DAAwACAjZIwIFAC0DAAAA.',Ra='Raffetax:BAAALAADCgUIBQAAAA==.Ragegnell:BAAALAADCgYIBgAAAA==.Rathrak:BAAALAAECgYICAABLAAECgYIIQADABoYAA==.Raád:BAAALAAECgMIBAAAAA==.',Re='Remorse:BAAALAAECgEIAQABLAAECggIHgAeAGYWAA==.Renewal:BAABLAAECoEVAAIVAAgIrReuJgAYAgAVAAgIrReuJgAYAgAAAA==.Reveor:BAAALAADCggIDwABLAAFFAMICAAHALMcAA==.',Ri='Ristiminii:BAAALAAECgYIDAAAAA==.Rixaii:BAAALAADCggICAAAAA==.',Rm='Rmz:BAAALAAECgIIAgAAAA==.Rmzetta:BAAALAAECgYIBgAAAA==.Rmzito:BAAALAAECgEIAQAAAA==.Rmzyo:BAAALAAECgcIEAAAAA==.Rmzà:BAAALAADCgIIAgAAAA==.',Ro='Rokamhlol:BAAALAADCgYIBwABLAAECgYIEgAPAAAAAA==.Royaly:BAAALAADCggICQABLAAFFAUIFAAJACgkAA==.',Sa='Sabbath:BAABLAAECoEhAAIDAAgIESP6EQAZAwADAAgIESP6EQAZAwAAAA==.Sacamano:BAAALAAECgQIBAAAAA==.Samwarrior:BAAALAADCggIDQAAAA==.Sangreal:BAAALAADCgEIAQAAAA==.Sariel:BAAALAAECggIBgAAAA==.Saxxun:BAAALAADCgIIAgAAAA==.',Se='Seeda:BAAALAAECggICAAAAA==.Seerdania:BAABLAAECoEeAAIkAAgIBR/QBgDcAgAkAAgIBR/QBgDcAgAAAA==.Selrissa:BAABLAAECoEnAAIJAAgI2Qg2CACmAQAJAAgI2Qg2CACmAQAAAA==.Seras:BAAALAAECggIEgAAAA==.Sertoriuss:BAAALAADCggIBgAAAA==.',Sh='Shadowfel:BAAALAAECgMIBAAAAA==.Shamanitocy:BAAALAADCggIFgAAAA==.Sheaman:BAAALAAECgEIAQAAAA==.Shenna:BAAALAADCggIEAAAAA==.Shindâ:BAAALAAECgUIBwAAAA==.Shuffledozer:BAACLAAFFIEFAAIfAAMI7xhOBwDnAAAfAAMI7xhOBwDnAAAsAAQKgSQAAh8ACAjFIWAHANQCAB8ACAjFIWAHANQCAAEsAAUUBwgYAB4AExQA.',Si='Sidajj:BAAALAADCggICAAAAA==.Sidisi:BAACLAAFFIEFAAMkAAMIMCKqBQDCAAAkAAIISCGqBQDCAAABAAEIACQTOABuAAAsAAQKgSoAAwEACAg/I9ExAEECAAEACAiAINExAEECACQABQidIsogANsBAAAA.Siggern:BAAALAAECggICAAAAA==.Sionnachh:BAAALAAECgIIAgAAAA==.Sixincher:BAAALAADCggICAAAAA==.',Sk='Skarzgarr:BAAALAADCgcICgAAAA==.Skeiron:BAABLAAECoEXAAIMAAgIPBqBFwAdAgAMAAgIPBqBFwAdAgABLAAFFAcIFAAEAFsiAA==.',Sm='Smokis:BAAALAAECgYIDAAAAA==.',Sn='Snømåke:BAAALAAECggIBwAAAA==.',Sp='Speedy:BAAALAADCgMIAwAAAA==.Spunkup:BAEALAAFFAMIAwABLAAFFAcIGAAHAKUmAA==.',Sq='Sqvirrel:BAAALAADCggICAAAAA==.',St='Stealthmode:BAAALAADCggICAAAAA==.Steltar:BAAALAAECggIBgAAAA==.Steroidman:BAABLAAECoEVAAIYAAgI6BqHEABLAgAYAAgI6BqHEABLAgAAAA==.Stjärten:BAAALAAECgcICQAAAA==.Storebror:BAAALAAECggIDQAAAA==.Stormboltz:BAAALAADCggIDAAAAA==.Strive:BAAALAAECgEIAQAAAA==.',Su='Sunoea:BAABLAAECoEnAAIVAAgIxhwOGgBjAgAVAAgIxhwOGgBjAgAAAA==.',Sv='Svarog:BAAALAADCggIDgAAAA==.Svida:BAAALAAECgcIDAABLAAECgcIGQAWAHAaAA==.',Sw='Sweetname:BAABLAAECoEUAAMfAAgIPBYYFADqAQAfAAgIWhUYFADqAQAMAAIItRf0RgCXAAAAAA==.Sweettotems:BAABLAAECoEhAAMNAAgIHiM5CwAjAwANAAgIHiM5CwAjAwAUAAEIXhSKBQExAAABLAAECggIFAAfADwWAA==.Swejeppe:BAAALAADCgMIAwAAAA==.',['Sø']='Sølvreven:BAABLAAECoElAAIXAAgICyKnBgAKAwAXAAgICyKnBgAKAwAAAA==.',['Sú']='Súperkossan:BAAALAAECgcIEAAAAA==.',Ta='Tankairon:BAAALAAECgcIBwAAAA==.Tauresswipe:BAAALAADCgcIBwAAAA==.',Te='Tenincher:BAAALAADCgUIBQAAAA==.Terrador:BAABLAAECoEnAAMIAAgIiyJ1EwDxAgAIAAgI1yF1EwDxAgAgAAYIECKcBwBbAgAAAA==.',Th='Theater:BAABLAAECoEWAAIUAAgIZxAjYACRAQAUAAgIZxAjYACRAQAAAA==.Theorize:BAAALAADCggIEAAAAA==.Theorizer:BAABLAAECoEWAAIOAAcIIBG7IwBVAQAOAAcIIBG7IwBVAQAAAA==.Thingol:BAABLAAECoEfAAITAAgIhwwlKQC2AQATAAgIhwwlKQC2AQAAAA==.Thorwind:BAAALAAECgYIEgAAAA==.Thundercall:BAAALAADCgcIBwAAAA==.',Ti='Tilted:BAABLAAECoEgAAIFAAgI4CXWAwBiAwAFAAgI4CXWAwBiAwAAAA==.Tirina:BAAALAADCggIGAAAAA==.',To='Tohotfordots:BAABLAAECoEVAAIGAAYIdxCNWAA3AQAGAAYIdxCNWAA3AQAAAA==.Torbén:BAAALAADCgcIIAAAAA==.Tordennæve:BAAALAADCgQIBAAAAA==.Tosuro:BAABLAAECoEhAAMDAAYIGhiEdgDFAQADAAYIGhiEdgDFAQACAAIIRgYNXgBWAAAAAA==.',Tr='Trazox:BAAALAADCgYIBgAAAA==.Trexi:BAAALAADCgcIBwAAAA==.Trickster:BAAALAAFFAIIAgABLAAFFAQIDgAFAKMlAA==.',Tu='Turbomage:BAABLAAECoEWAAITAAYI6yEyFwA5AgATAAYI6yEyFwA5AgAAAA==.',Ty='Tyga:BAABLAAECoEYAAIIAAgIvR18GgDBAgAIAAgIvR18GgDBAgABLAAECggIHAAQAB0UAA==.Tygä:BAAALAAECgcIEwABLAAECggIHAAQAB0UAA==.Tygäâä:BAABLAAECoEcAAIQAAgIHRSXHQANAgAQAAgIHRSXHQANAgAAAA==.Tykée:BAAALAAECgYIDAAAAA==.Tylande:BAAALAAECgYIDgABLAAECggIJwAIAIsiAA==.Tyon:BAABLAAECoEmAAIKAAgI9RdNIwBBAgAKAAgI9RdNIwBBAgAAAA==.Tyreli:BAABLAAECoEjAAIiAAgIsCF1DADvAgAiAAgIsCF1DADvAgAAAA==.Tyyreli:BAAALAADCggICAAAAA==.',Ul='Ulgrath:BAABLAAECoEXAAINAAgIBxjwJABbAgANAAgIBxjwJABbAgAAAA==.Ulyana:BAAALAADCgcICQAAAA==.',Us='Usop:BAAALAADCgQICAAAAA==.',Va='Varatha:BAAALAAECgMIAwAAAA==.Vari:BAABLAAECoEVAAIGAAgIdgmUUQBQAQAGAAgIdgmUUQBQAQAAAA==.Varjager:BAAALAADCgUICgAAAA==.',Ve='Venny:BAAALAADCgcIBwAAAA==.Verdande:BAAALAAECgIIAgABLAAFFAMICQAVANMaAA==.Vespasiana:BAABLAAECoEWAAIBAAYIPhKpagB2AQABAAYIPhKpagB2AQAAAA==.',Vi='Visk:BAACLAAFFIEXAAMLAAYIER4oCADZAQALAAUIlR8oCADZAQAJAAEIfBY6BwBUAAAsAAQKgRwAAwsACAiDJdERAAYDAAsACAiDJdERAAYDAAkAAQhYG8EYAEoAAAAA.',Vo='Vordeith:BAAALAADCggICAABLAAECgYIFAAVAPQLAA==.',Vr='Vrieshunter:BAABLAAECoEeAAIaAAgI/x6xGQDhAgAaAAgI/x6xGQDhAgAAAA==.',We='Weqkmjnrbg:BAAALAADCgYIBgAAAA==.Werdup:BAECLAAFFIEYAAIHAAcIpSYCAAAJAwAHAAcIpSYCAAAJAwAsAAQKgSAAAgcACAjcJjIAAIYDAAcACAjcJjIAAIYDAAAA.',Wi='Wiarius:BAAALAAECgYIDAAAAA==.Widget:BAABLAAECoEkAAIVAAgIUxEUPACxAQAVAAgIUxEUPACxAQAAAA==.',Wo='Wootas:BAAALAAECgYICwAAAA==.',Wr='Wrathwing:BAAALAADCgcIBwAAAA==.Wrint:BAAALAAECgEIAQAAAA==.',Xe='Xekus:BAAALAAECgIIAgAAAA==.',Xf='Xfrost:BAABLAAECoEoAAILAAgIGR+GIgCqAgALAAgIGR+GIgCqAgAAAA==.',Xo='Xoryan:BAABLAAECoEWAAIcAAYIgBzBEwDUAQAcAAYIgBzBEwDUAQAAAA==.',Xu='Xuv:BAABLAAECoEmAAIIAAgIQBcLLgBHAgAIAAgIQBcLLgBHAgAAAA==.',Za='Zankara:BAAALAADCgcIDQABLAAFFAMICAAHALMcAA==.',Ze='Zephos:BAACLAAFFIEUAAMEAAcIWyJ8AQBxAgAEAAYIyiN8AQBxAgAbAAEIwBm3EgBgAAAsAAQKgSIAAwQACAj1JYEIAEoDAAQACAj1JYEIAEoDABsAAQjzJdNIAGgAAAAA.Zernerino:BAACLAAFFIEGAAIMAAIINSWLBwDOAAAMAAIINSWLBwDOAAAsAAQKgSwAAgwACAiEJTYCAGIDAAwACAiEJTYCAGIDAAAA.',Zg='Zgrti:BAAALAAECgMIAwAAAA==.',Zh='Zhaix:BAACLAAFFIEMAAIhAAII4yVHAQDSAAAhAAII4yVHAQDSAAAsAAQKgSQAAiEACAiXJfAAAFUDACEACAiXJfAAAFUDAAAA.',Zi='Zigote:BAAALAAECgYIBgAAAA==.',Zl='Zlobyla:BAAALAADCgcIBwAAAA==.',['Ãs']='Ãshy:BAAALAAECgUICQAAAA==.',['Ðo']='Ðoss:BAAALAADCgUIBQAAAA==.',['Öp']='Öprah:BAAALAAECgQIBAAAAA==.',['Øw']='Øwen:BAAALAAECgEIAwAAAA==.',['Üb']='Überpepega:BAABLAAECoEVAAIaAAgIDBZkRQAgAgAaAAgIDBZkRQAgAgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end