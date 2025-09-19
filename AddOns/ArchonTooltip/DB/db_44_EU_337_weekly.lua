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
 local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Shaman-Enhancement','Warrior-Fury','Priest-Holy','Monk-Mistweaver','DemonHunter-Vengeance','Unknown-Unknown','Mage-Arcane','Mage-Fire','Druid-Feral','Shaman-Restoration','DeathKnight-Frost','Druid-Restoration','Evoker-Preservation','Warrior-Protection','DeathKnight-Blood','Monk-Windwalker','DemonHunter-Havoc','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','Shaman-Elemental','Druid-Balance','Evoker-Devastation','Rogue-Assassination','Priest-Shadow','Monk-Brewmaster','Hunter-Survival','Warlock-Demonology','DeathKnight-Unholy',}; local provider = {region='EU',realm='Sunstrider',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aaba:BAAALAAECgcIBwAAAA==.',Ae='Aelx:BAAALAAECgcIBwAAAA==.',Ak='Akariel:BAAALAAECgYIBgAAAA==.',An='Andrak:BAAALAAECgIIAgAAAA==.Angie:BAABLAAECoEVAAIBAAgIvh8XDADgAgABAAgIvh8XDADgAgABLAAFFAMIBwACAPwXAA==.Annamae:BAAALAADCggIFgAAAA==.Annamosity:BAAALAAECgcIDgAAAA==.Antaress:BAABLAAECoEXAAIDAAcI/BdjCQDjAQADAAcI/BdjCQDjAQAAAA==.',Ar='Aridemon:BAAALAADCggICAABLAAECggIGwAEAM8dAA==.Arvis:BAAALAAECgYICQAAAA==.Arzely:BAAALAADCgUIBgAAAA==.',As='Asce:BAAALAAECggICQAAAA==.Ashbery:BAAALAADCgIIAgAAAA==.Ashoofk:BAAALAAECgYICAAAAA==.Ashyra:BAABLAAECoEcAAIFAAgIZSCICQDQAgAFAAgIZSCICQDQAgAAAA==.Askebardé:BAAALAAECgQIBQAAAA==.Asumah:BAAALAAECgYICgAAAA==.',Au='Augustis:BAABLAAECoEaAAICAAgIcSSYBgBDAwACAAgIcSSYBgBDAwAAAA==.',Av='Averhan:BAAALAADCgcIDAABLAAECggIHAAGABwVAA==.Avila:BAAALAADCgUICAAAAA==.',['Aý']='Aýá:BAAALAADCgcIDAAAAA==.',Ba='Babavoss:BAAALAAECgMIAgAAAA==.Baldi:BAAALAADCggICAAAAA==.Balduzzi:BAAALAAECgYIEAAAAA==.Barlan:BAABLAAECoEcAAIHAAgIBxRUDgDXAQAHAAgIBxRUDgDXAQAAAA==.Barlon:BAAALAADCgYIBgABLAAECggIHAAHAAcUAA==.Barlán:BAAALAADCgcIBwABLAAECggIHAAHAAcUAA==.Basbos:BAAALAADCgUIBQABLAADCgYIBgAIAAAAAA==.',Bb='Bbywoke:BAAALAAECgYIDwAAAA==.',Be='Beefymagé:BAABLAAECoEbAAMJAAgIiSMbBgA3AwAJAAgIBiMbBgA3AwAKAAEInCVIDgBkAAAAAA==.Beefymagë:BAAALAADCgYIBgAAAA==.Beerwolf:BAAALAAECgYICQAAAA==.Ben:BAABLAAECoEcAAICAAgIEB2vGQCVAgACAAgIEB2vGQCVAgAAAA==.',Bi='Biftatwista:BAAALAAECgUIBQAAAA==.',Bj='Bjarnulf:BAAALAAECgMIBAAAAA==.',Bl='Blackthought:BAAALAAECggIDAAAAA==.Bloodydead:BAAALAAECgYIDAABLAAECggIHwAGAFwkAA==.',Bo='Bobbyboucher:BAAALAAECgcIDwAAAA==.Boblin:BAAALAAECgYICAAAAA==.Bojak:BAAALAADCgEIAQAAAA==.Borgnarr:BAAALAADCgcIBwAAAA==.',Br='Breokz:BAAALAADCggIBQAAAA==.Broxigan:BAAALAADCgEIAQABLAAECgYIDwAIAAAAAA==.',Bu='Bublixvi:BAAALAAECgIIAgAAAA==.Burritoboris:BAABLAAECoEaAAIBAAgISB/4DgDAAgABAAgISB/4DgDAAgAAAA==.',Ca='Cafù:BAAALAAECgYIDAAAAA==.Capalots:BAAALAAECgYIBgAAAA==.',Ch='Charvel:BAAALAADCggICAAAAA==.Chevron:BAAALAADCgMIAwAAAA==.Chumbus:BAAALAAECgQICAAAAA==.Chunk:BAAALAAECgEIAQABLAAECgQICAAIAAAAAA==.',Ci='Ciraxis:BAAALAADCgYICgAAAA==.',Co='Coltor:BAAALAAECgcIDwAAAA==.Consabre:BAAALAADCgUIBwAAAA==.Cornu:BAAALAAECgcIDgAAAA==.',Cr='Crusher:BAAALAAECgMIAwAAAA==.',Cu='Curran:BAAALAAECgYICAAAAA==.',['Cá']='Cáfu:BAAALAADCggIEAAAAA==.',Da='Daendros:BAAALAADCggIDwAAAA==.Daendryn:BAAALAADCgcIAwAAAA==.Daylen:BAAALAADCggICAAAAA==.',De='Deadclass:BAAALAADCgIIAgAAAA==.Demoesh:BAAALAADCggIDwAAAA==.Demomage:BAAALAADCgQIBAAAAA==.Demotaz:BAAALAADCggIDgAAAA==.Derpup:BAECLAAFFIEHAAILAAMIbSbEAABYAQALAAMIbSbEAABYAQAsAAQKgR0AAgsACAi+JhsAAJQDAAsACAi+JhsAAJQDAAEsAAUUBggSAAMAdyYA.Desi:BAAALAADCggICAAAAA==.Destronarr:BAAALAAECgYICAAAAA==.',Di='Discoyorish:BAAALAAECgUICQAAAA==.',Do='Dogon:BAAALAAECggICAAAAA==.Dohfos:BAABLAAECoEUAAIMAAcIAhQ6NACuAQAMAAcIAhQ6NACuAQAAAA==.Domadk:BAAALAADCgEIAQAAAA==.Doublejump:BAAALAAFFAIIAgABLAAFFAUIDgANAEAeAA==.Dozzyr:BAAALAAECgYIDwAAAA==.',Dr='Dreagnor:BAAALAAECgYIEAAAAA==.Driezer:BAAALAAECggIEQAAAA==.Drollemage:BAAALAADCgYIBgAAAA==.',Du='Dumbawumba:BAABLAAECoEVAAIJAAcILRUkOgDXAQAJAAcILRUkOgDXAQAAAA==.',Dw='Dwergfluit:BAAALAADCggIDQAAAA==.',Dy='Dysdemona:BAAALAAECgUICwAAAA==.',Dz='Dza:BAAALAADCgcIBwAAAA==.',['Dé']='Défibrilator:BAAALAAECgcIEQAAAA==.',Ea='Eachan:BAAALAAECgYICAAAAA==.',Ed='Edgelord:BAAALAAECgMIBQAAAA==.',El='Elevenincher:BAAALAADCgUIBwAAAA==.Elinorana:BAAALAADCggICAAAAA==.Elmina:BAAALAAECgUICwAAAA==.Elunis:BAAALAAECgUICQAAAA==.Elùn:BAABLAAECoEZAAIOAAgIgBaFGQAGAgAOAAgIgBaFGQAGAgAAAA==.',Em='Embry:BAAALAADCggIDwAAAA==.',Es='Eshpriest:BAAALAAECggIEwAAAA==.',Et='Eti:BAAALAAECgYIBwAAAA==.',Eu='Euphotic:BAAALAAECgMIAwAAAA==.',Ev='Evonizar:BAAALAADCggIGAAAAA==.',Ex='Exavi:BAAALAAFFAIIAgAAAA==.',Fa='Faervel:BAAALAAECgUIBQABLAAECggIGQAOAIAWAA==.',Fe='Felatra:BAAALAAECgYIDgAAAA==.Felore:BAAALAAECgYICAAAAA==.',Fi='Fireyblade:BAAALAADCgcIBwABLAAECgcIFQACAMAZAA==.Fiveincher:BAAALAAECgcIEQAAAA==.',Fl='Flaskepost:BAAALAAECgYIEAAAAA==.Flumiis:BAAALAAFFAIIAgAAAA==.Flummann:BAAALAAECgIIAgAAAA==.Flummis:BAACLAAFFIEGAAIPAAMIkBXfAgADAQAPAAMIkBXfAgADAQAsAAQKgR4AAg8ACAiuIUwCAO8CAA8ACAiuIUwCAO8CAAAA.Flûffy:BAAALAADCgYIBAAAAA==.',Fo='Foosi:BAAALAAECgcIBwAAAA==.',Fr='Frauj:BAAALAAECgYIDgAAAA==.Frieren:BAAALAAECgIIAgABLAAECgYICAAIAAAAAA==.',Fu='Furiòn:BAABLAAECoEaAAINAAgIRSKqDgDmAgANAAgIRSKqDgDmAgAAAA==.Furión:BAAALAADCgYIBgAAAA==.',Ga='Gahandi:BAAALAADCggICAAAAA==.Gangnamup:BAEALAAFFAIIAgABLAAFFAYIEgADAHcmAA==.',Ge='Genryu:BAAALAADCgcIBwAAAA==.Geranyll:BAAALAAECgEIAQAAAA==.',Gh='Ghostbuilder:BAAALAADCgcICAAAAA==.',Go='Goblingirl:BAABLAAECoELAAIKAAcITReNAwACAgAKAAcITReNAwACAgAAAA==.Gohan:BAAALAADCggIDwAAAA==.Gomek:BAABLAAECoEbAAMEAAgIzx0bEQCpAgAEAAgIiBwbEQCpAgAQAAUIsBoaJgAoAQAAAA==.Gordrell:BAAALAADCggICAAAAA==.',Gr='Greyface:BAAALAADCggICAABLAAECggIEwAIAAAAAA==.Grimkash:BAABLAAECoEXAAIRAAgI4BeLCAA7AgARAAgI4BeLCAA7AgAAAA==.',['Gä']='Gäng:BAAALAADCgIIAQAAAA==.',Ha='Hammerdin:BAAALAADCgMIAwAAAA==.Haribka:BAAALAADCggIDAAAAA==.Harryportal:BAAALAADCgYIBgAAAA==.Haxxie:BAAALAADCgcIBwAAAA==.Hazeleyes:BAAALAADCgEIAgAAAA==.',He='Hegge:BAAALAADCgcIBwAAAA==.Hellbringer:BAAALAADCggIDwAAAA==.Hexwhelp:BAAALAAECgEIAQAAAA==.',Hi='Himiko:BAAALAAECgYICAABLAAECgYIDwAIAAAAAA==.',Ho='Holydruidly:BAAALAAECgIIAgAAAA==.',Hu='Huntun:BAAALAAECgIIAgAAAA==.Hunux:BAAALAAECgQIBAABLAAECgYIBgAIAAAAAA==.',Hx='Hx:BAAALAAECggICAAAAA==.',['Hä']='Hääl:BAAALAADCgIIAgAAAA==.',Ib='Ibo:BAAALAAECgcICwAAAA==.',Ic='Ice:BAAALAAECgIIAgAAAA==.',Il='Ileprechaun:BAAALAAECgMIAwAAAA==.Ilevea:BAAALAAECgcIBwAAAA==.Illidia:BAAALAADCgcIBwABLAAECgcICwAKAE0XAA==.',In='Infoxicated:BAAALAADCggICAAAAA==.Instigator:BAAALAAECgcIEgAAAA==.',It='Itswiseomg:BAAALAAECgYIBwAAAA==.',Ja='Jackiie:BAAALAAFFAIIAgAAAA==.Jazmon:BAAALAAECgUIBQAAAA==.',Jh='Jhonnysins:BAAALAADCggICAAAAA==.',Ji='Jimeth:BAABLAAECoEVAAICAAcIwBmOLgAaAgACAAcIwBmOLgAaAgAAAA==.Jinbei:BAABLAAECoEcAAMGAAgIHBXjDQACAgAGAAgIHBXjDQACAgASAAcI0xPrFQDCAQAAAA==.',Jo='Joe:BAAALAADCggIFAAAAA==.Josuas:BAAALAAECgYIDwAAAA==.',Js='Jsonyo:BAAALAADCggICgAAAA==.',Ju='Jumpup:BAEBLAAECoEXAAITAAgIXySWBQBJAwATAAgIXySWBQBJAwABLAAFFAYIEgADAHcmAA==.',Ka='Kaljador:BAAALAAECggIEwAAAA==.Kalkyl:BAAALAADCgcIDAABLAAECgcICQAIAAAAAA==.Kampkran:BAAALAADCggICAAAAA==.Kapu:BAAALAADCggIFQAAAA==.Karenfromhr:BAAALAADCgcIBwAAAA==.Kasirius:BAAALAADCgcIBwAAAA==.Katyparry:BAAALAAECgcIEQAAAA==.Kaykrill:BAAALAADCgYIBgAAAA==.',Ke='Kellà:BAAALAADCggICAABLAAECgYICAAIAAAAAA==.Kerno:BAAALAAECgcICQAAAA==.',Kh='Khar:BAAALAADCgcIBwAAAA==.Kharox:BAAALAADCgcICAABLAAECggIFwARAOAXAA==.',Ki='Kibin:BAAALAADCgQIBQAAAA==.Kitcat:BAAALAADCgYIBgAAAA==.',Kl='Kladd:BAABLAAECoEWAAIOAAcImgrzPAAuAQAOAAcImgrzPAAuAQAAAA==.',Ko='Koras:BAABLAAECoEVAAIUAAcIfSCHAwCMAgAUAAcIfSCHAwCMAgAAAA==.',Kr='Krazey:BAAALAADCggICAAAAA==.Kreíos:BAAALAAECggIAgAAAA==.',Ku='Kuw:BAAALAAECgQIBQAAAA==.Kuydo:BAAALAAECgYIDAAAAA==.',Kv='Kvg:BAAALAAECgYIBgAAAA==.',Ky='Kynnia:BAAALAAECgUICgAAAA==.',['Ká']='Kátniss:BAAALAAECgYIBgAAAA==.',['Kí']='Kíng:BAAALAADCggICAAAAA==.',La='Lamiai:BAAALAADCgcIBwAAAA==.Landuck:BAAALAAECgUIBwAAAA==.Laquin:BAABLAAECoEUAAIDAAgISSFTAgDtAgADAAgISSFTAgDtAgAAAA==.Lassebird:BAAALAAECgYIDgAAAA==.',Le='Lev:BAAALAAECgYIBwAAAA==.Leviantus:BAAALAAECgcIDgAAAA==.',Li='Liubie:BAAALAADCgQIBAAAAA==.',Ll='Lleya:BAAALAAECgYICQABLAAECggIGwAEAM8dAA==.',Ln='Lndk:BAAALAAECgUIBgABLAAECgUIBwAIAAAAAA==.',Lo='Lonelya:BAABLAAECoEVAAMVAAgI6xCIEABbAQAWAAgIzg81LADcAQAVAAcIXAaIEABbAQAAAA==.Losestreak:BAAALAAECgcIBwAAAA==.',['Lá']='Lántz:BAAALAADCggICAAAAA==.',Ma='Macmongoloid:BAAALAAECgMIBAAAAA==.Madulun:BAABLAAECoEaAAMXAAgIhgeGRwAvAQAXAAcIFQSGRwAvAQAMAAgIVgJAbgDhAAAAAA==.Malpriest:BAAALAADCgQIBAAAAA==.Maurees:BAAALAAECgEIAQAAAA==.Mauti:BAAALAAFFAIIBAAAAA==.Maxsprittet:BAAALAADCgcIBwAAAA==.',Me='Mesmer:BAAALAAECgMIBAAAAA==.',Mi='Minty:BAAALAADCggICAAAAA==.Misschieef:BAAALAADCgIIAgAAAA==.Mistyjohn:BAAALAADCgcIBwAAAA==.',Mj='Mjolksyra:BAAALAAECgcIEwAAAA==.',Mo='Moila:BAAALAAECgYIBwAAAA==.Morhoprst:BAAALAAECgIIAgAAAA==.Moudo:BAAALAAECgYICwAAAA==.',My='Myon:BAABLAAECoEZAAMYAAgIcRhpEQBmAgAYAAgIcRhpEQBmAgAOAAIIfQs7bQBWAAAAAA==.Myopicant:BAABLAAECoEVAAIFAAcIqAsuNwByAQAFAAcIqAsuNwByAQAAAA==.',Na='Nargothord:BAABLAAECoEUAAIWAAYIpRorLgDPAQAWAAYIpRorLgDPAQAAAA==.',Ne='Neophobia:BAAALAAECgIIBAAAAA==.Nevi:BAAALAADCgUIBQAAAA==.',Ni='Niblo:BAAALAAECgMIAwAAAA==.Nickster:BAAALAAECgYICQAAAA==.Nightmärë:BAAALAADCggIDwABLAAECggIGAAZAB0UAA==.',No='Norris:BAAALAAECgYICAAAAA==.Notmedusa:BAAALAAECgUIBgAAAA==.Notworksafe:BAABLAAECoEcAAIaAAgI7BfvDwBfAgAaAAgI7BfvDwBfAgAAAA==.',Np='Np:BAAALAADCggICAAAAA==.',['Ný']='Nýxx:BAABLAAECoEVAAIbAAcIzRgIHQAPAgAbAAcIzRgIHQAPAgAAAA==.',Ol='Ollefans:BAABLAAECoEXAAIMAAcIPyCREgBnAgAMAAcIPyCREgBnAgAAAA==.',Oo='Oomadin:BAAALAADCgEIAQAAAA==.',Op='Opräh:BAABLAAECoEXAAIJAAgI0CNtCQAYAwAJAAgI0CNtCQAYAwAAAA==.',Or='Ormstryparen:BAAALAADCgcIBwAAAA==.',Ou='Ourcaptain:BAAALAAECgUIDQAAAA==.',Oy='Oyzmr:BAAALAADCgcIBwAAAA==.',Pa='Palalaladin:BAAALAAECgEIAQABLAAECgcICwAKAE0XAA==.Patchar:BAAALAAECgQIBAAAAA==.',Ph='Pheeb:BAAALAAECgEIAQAAAA==.',Pl='Plalalala:BAAALAADCgcIBwAAAA==.',Po='Poesjemeow:BAAALAADCgcIBwAAAA==.Poka:BAEALAAECgYIBgAAAA==.Pomutzi:BAAALAADCggICAAAAA==.',Pr='Prëdätör:BAAALAADCggICAABLAAECggIGAAZAB0UAA==.',Pu='Puntha:BAABLAAECoEfAAMSAAgISxw0CACmAgASAAgISxw0CACmAgAcAAgIYwVLGgAVAQAAAA==.Pusekruse:BAABLAAECoEXAAIGAAcIoBieDgD2AQAGAAcIoBieDgD2AQAAAA==.',Py='Pykken:BAAALAAECgMIBQAAAA==.',['Pû']='Pûck:BAAALAAECggICAAAAA==.',Qu='Quotay:BAABLAAECoEXAAIdAAgI0xneAgBnAgAdAAgI0xneAgBnAgABLAAFFAUIDAASADMSAA==.Quotey:BAACLAAFFIEMAAISAAUIMxLCAAC7AQASAAUIMxLCAAC7AQAsAAQKgR4AAhIACAh7I58CADoDABIACAh7I58CADoDAAAA.',Ra='Raffetax:BAAALAADCgUIBQAAAA==.Ragegnell:BAAALAADCgYIBgAAAA==.Rathrak:BAAALAAECgIIAgABLAAECgYIDwAIAAAAAA==.Raád:BAAALAAECgMIBAAAAA==.',Re='Remorse:BAAALAAECgEIAQAAAA==.Renewal:BAAALAAECgYIDAAAAA==.Reveor:BAAALAADCggIDwABLAAECggIFAADAEkhAA==.',Ri='Ristiminii:BAAALAAECgYIDAAAAA==.Rixaii:BAAALAADCggICAAAAA==.',Rm='Rmzetta:BAAALAAECgUIBQAAAA==.Rmzyo:BAAALAAECgcICQAAAA==.',Ro='Rokamhlol:BAAALAADCgYIBgAAAA==.Royaly:BAAALAADCggICQAAAA==.',Sa='Sabbath:BAAALAAECgcIEQAAAA==.Samwarrior:BAAALAADCggIDQAAAA==.Saxxun:BAAALAADCgIIAgAAAA==.',Se='Seeda:BAAALAAECggICAAAAA==.Seerdania:BAABLAAECoEWAAIeAAcInx4DCAB9AgAeAAcInx4DCAB9AgAAAA==.Selrissa:BAABLAAECoEXAAIKAAgIaQdMBQCjAQAKAAgIaQdMBQCjAQAAAA==.Seras:BAAALAAECggIEgAAAA==.',Sh='Shadowfel:BAAALAAECgMIBAAAAA==.Shamanitocy:BAAALAADCgYICQAAAA==.Sheaman:BAAALAAECgEIAQAAAA==.Shindâ:BAAALAADCggIFgAAAA==.Shuffledozer:BAACLAAFFIEFAAIcAAMI7xjbAgD/AAAcAAMI7xjbAgD/AAAsAAQKgRcAAhwACAiYId8DAO8CABwACAiYId8DAO8CAAAA.',Si='Sidajj:BAAALAADCggICAAAAA==.Sidisi:BAABLAAECoEcAAMeAAgIvCJHFADwAQAeAAUInSJHFADwAQAWAAUIiyDFLgDMAQAAAA==.Siggern:BAAALAAECggICAAAAA==.Sionnachh:BAAALAADCggIFQAAAA==.',Sk='Skarzgarr:BAAALAADCgcICgAAAA==.Skeiron:BAABLAAECoEXAAISAAgIPBqsDABKAgASAAgIPBqsDABKAgABLAAFFAUIDgANAEAeAA==.',Sn='Snømåke:BAAALAAECggIBwAAAA==.',Sp='Spunkup:BAEALAAECggIDgABLAAFFAYIEgADAHcmAA==.',Sq='Sqvirrel:BAAALAADCggICAAAAA==.',St='Stealthmode:BAAALAADCggICAAAAA==.Steroidman:BAAALAAECgYIDAAAAA==.Stjärten:BAAALAAECgcICQAAAA==.Storebror:BAAALAAECggICAAAAA==.Stormboltz:BAAALAADCggIDAAAAA==.Strive:BAAALAAECgEIAQAAAA==.',Su='Sunoea:BAABLAAECoEdAAIOAAgIvho/EwA8AgAOAAgIvho/EwA8AgAAAA==.',Sv='Svarog:BAAALAADCggIDgAAAA==.',Sw='Sweetname:BAAALAAECgcICgAAAA==.Sweettotems:BAAALAAECgYIEAABLAAECgcICgAIAAAAAA==.Swejeppe:BAAALAADCgMIAwAAAA==.',['Sø']='Sølvreven:BAABLAAECoEYAAIaAAgIFR9VBwDdAgAaAAgIFR9VBwDdAgAAAA==.',['Sú']='Súperkossan:BAAALAAECgcICQAAAA==.',Ta='Tauresswipe:BAAALAADCgcIBwAAAA==.',Te='Tenincher:BAAALAADCgUIBQAAAA==.Terrador:BAABLAAECoEUAAIEAAcIUCFJFQB6AgAEAAcIUCFJFQB6AgAAAA==.',Th='Theater:BAAALAAECgcIDwAAAA==.Theorize:BAAALAADCggIEAAAAA==.Theorizer:BAAALAAECgYIDgAAAA==.Thingol:BAAALAAECggIDwAAAA==.Thorwind:BAAALAAECgYIDAAAAA==.Thundercall:BAAALAADCgcIBwAAAA==.',Ti='Tilted:BAAALAAECgYIEAAAAA==.Tirina:BAAALAADCggIGAAAAA==.',To='Tohotfordots:BAAALAAECgMIBwAAAA==.Torbén:BAAALAADCgcIFgAAAA==.Tosuro:BAAALAAECgYIDwAAAA==.',Tr='Trazox:BAAALAADCgYIBgAAAA==.',Tu='Turbomage:BAAALAAECgYIEgAAAA==.',Ty='Tyga:BAAALAAECgcIBwABLAAECggIGAAZAB0UAA==.Tygäâä:BAABLAAECoEYAAIZAAgIHRQVEgA6AgAZAAgIHRQVEgA6AgAAAA==.Tylande:BAAALAAECgYICAABLAAECgcIFAAEAFAhAA==.Tyon:BAABLAAECoEUAAIFAAYIVhAhPABXAQAFAAYIVhAhPABXAQAAAA==.Tyreli:BAABLAAECoEVAAIYAAcIsyK6CgDHAgAYAAcIsyK6CgDHAgAAAA==.',Ul='Ulgrath:BAAALAAECgYICAAAAA==.Ulyana:BAAALAADCgcICQAAAA==.',Us='Usop:BAAALAADCgQICAAAAA==.',Va='Varatha:BAAALAADCgcIDAAAAA==.Vari:BAAALAAECgYIDAAAAA==.Varjager:BAAALAADCgUICgAAAA==.',Ve='Vespasiana:BAAALAAECgYICQAAAA==.',Vi='Visk:BAACLAAFFIENAAMJAAYIHhazAgDFAQAJAAUIsRezAgDFAQAKAAEIQw7DAwBaAAAsAAQKgRgAAwkACAh6JYIHACoDAAkACAh6JYIHACoDAAoAAQhYG9EPAFIAAAAA.',Vr='Vrieshunter:BAAALAAECgYICAAAAA==.',We='Werdup:BAECLAAFFIESAAIDAAYIdyYBAADAAgADAAYIdyYBAADAAgAsAAQKgRwAAgMACAjKJg8AAJYDAAMACAjKJg8AAJYDAAAA.',Wi='Widget:BAABLAAECoEVAAIOAAcIEgwqOQA/AQAOAAcIEgwqOQA/AQAAAA==.',Wo='Wootas:BAAALAAECgYICwAAAA==.',Wr='Wrathwing:BAAALAADCgcIBwAAAA==.',Xf='Xfrost:BAABLAAECoEXAAIJAAcIsSB5HwBrAgAJAAcIsSB5HwBrAgAAAA==.',Xo='Xoryan:BAAALAAECgUICQAAAA==.',Xu='Xuv:BAABLAAECoEWAAIEAAcIExBqLQC9AQAEAAcIExBqLQC9AQAAAA==.',Za='Zankara:BAAALAADCgcIDQABLAAECggIFAADAEkhAA==.',Ze='Zephos:BAACLAAFFIEOAAMNAAUIQB7UAQClAQANAAQIYB/UAQClAQAfAAEIwBmnCQBnAAAsAAQKgR4AAw0ACAjbJbYBAG0DAA0ACAjbJbYBAG0DAB8AAQjzJW83AG8AAAAA.Zernerino:BAABLAAECoEcAAISAAgIciSPAQBbAwASAAgIciSPAQBbAwAAAA==.',Zh='Zhaix:BAACLAAFFIEKAAIVAAIISB55AADKAAAVAAIISB55AADKAAAsAAQKgR0AAhUACAiXJVAAAHgDABUACAiXJVAAAHgDAAAA.',['Ãs']='Ãshy:BAAALAADCggICQAAAA==.',['Øw']='Øwen:BAAALAAECgEIAgAAAA==.',['Üb']='Überpepega:BAAALAAECgYIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end