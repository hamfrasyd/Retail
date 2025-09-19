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
 local lookup = {'DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Monk-Windwalker','Evoker-Preservation','Paladin-Holy','Mage-Fire','Priest-Shadow','Monk-Mistweaver','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Priest-Holy','Warrior-Fury','Mage-Arcane','Druid-Balance','Druid-Feral','Warlock-Demonology','Rogue-Assassination','Hunter-Marksmanship','DeathKnight-Blood','Evoker-Devastation','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Druid-Restoration','Evoker-Augmentation','Warrior-Protection','Rogue-Subtlety','Paladin-Protection',}; local provider = {region='EU',realm="Kael'thas",name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aamshagar:BAAALAADCgcIBwAAAA==.',Ab='Abrams:BAABLAAECoEXAAIBAAgIeCPuBAA7AwABAAgIeCPuBAA7AwAAAA==.',Ac='Acassïa:BAAALAAECgIIAgAAAA==.',Ad='Adrias:BAAALAADCggICAAAAA==.',Ae='Aeronia:BAABLAAECoEaAAMCAAgIlR29CADbAgACAAgIlR29CADbAgADAAEINQZ4iQApAAAAAA==.',Ai='Aito:BAAALAADCgYIBgAAAA==.',Al='Alastôr:BAAALAADCggIFwAAAA==.Aldia:BAAALAAECgYICAAAAA==.Alerlord:BAAALAADCgcIBwAAAA==.Allegessia:BAAALAAECgEIAQABLAAECgYIBgAEAAAAAA==.Alluka:BAAALAADCgYIBgAAAA==.Alnea:BAAALAAECgYIDAAAAA==.Alpaga:BAABLAAECoEXAAIFAAgIMxSVCgAjAgAFAAgIMxSVCgAjAgAAAA==.Alètheiä:BAAALAAECgMIAwAAAA==.',Am='Amily:BAAALAADCgcIBwAAAA==.',An='Anannas:BAAALAAECgYIDAABLAAECggIFwAFADMUAA==.Ancalainur:BAAALAADCgQIBAABLAADCgcICQAEAAAAAA==.Anemis:BAAALAADCggICAAAAA==.Annalphabete:BAAALAAECgMIAwAAAA==.',Ap='Apadrekt:BAAALAAECgQICAAAAA==.Apolyøn:BAAALAAECgYIDAAAAA==.',Ar='Aranel:BAAALAAECgcIEAAAAA==.Archimoon:BAAALAADCgYIBgAAAA==.Archângelia:BAAALAADCgYIBgAAAA==.Archïl:BAAALAADCggICgAAAA==.Argozdoc:BAAALAAECgYIDQAAAA==.',As='Asa:BAAALAAECgYICAAAAA==.Ashvâ:BAAALAAECgIIAgAAAA==.Ashzyra:BAAALAADCgUIBQAAAA==.Ashãena:BAAALAADCggICQAAAA==.Asrunn:BAAALAADCgMIAwAAAA==.Astæroth:BAAALAADCgEIAQAAAA==.Aswey:BAAALAADCgcIBwAAAA==.',At='Ataho:BAAALAAECgIIAwAAAA==.Athénâ:BAAALAADCggIFAAAAA==.Atøha:BAAALAAECgQICQAAAA==.',Av='Avigel:BAAALAAECgcIDwAAAA==.',Ay='Ayahia:BAAALAAECgIIAgAAAA==.',Az='Azayiel:BAAALAAECggIEQAAAA==.Azulistrasza:BAABLAAECoEVAAIGAAgIwQ4VCQDEAQAGAAgIwQ4VCQDEAQAAAA==.',['Aï']='Aïkix:BAAALAAECgMIAwAAAA==.',Ba='Baalorc:BAAALAADCgcIDgAAAA==.Bak:BAABLAAECoEXAAIHAAgIHhE3DwDsAQAHAAgIHhE3DwDsAQAAAA==.Baløsh:BAAALAADCgEIAQAAAA==.Bananegauche:BAAALAADCgcIAwAAAA==.Barkovich:BAAALAADCggIDwAAAA==.',Bb='Bbouuh:BAAALAAECgMIBAAAAA==.',Bc='Bchoinz:BAAALAADCgcIBwAAAA==.',Be='Bella:BAAALAADCgcICAAAAA==.Belli:BAAALAADCgYIBgAAAA==.Bely:BAACLAAFFIEFAAIIAAMIhhVMAAAHAQAIAAMIhhVMAAAHAQAsAAQKgRgAAggACAjsIYoAAAADAAgACAjsIYoAAAADAAAA.Benchiku:BAAALAADCgcIBwABLAAECggIFQAJALkfAA==.Bercifist:BAABLAAFFIEGAAIKAAMI4hatAQAJAQAKAAMI4hatAQAJAQAAAA==.',Bi='Bibleblock:BAACLAAFFIEFAAILAAMIOhGDBAADAQALAAMIOhGDBAADAQAsAAQKgRgAAwsACAh4IGQHAOsCAAsACAh4IGQHAOsCAAwAAgjMEyYfAI4AAAAA.Bigpoppà:BAABLAAECoEYAAIDAAgIfx3UCACQAgADAAgIfx3UCACQAgAAAA==.Bilieicelish:BAACLAAFFIEFAAINAAMIXwnOAADiAAANAAMIXwnOAADiAAAsAAQKgRgAAg0ACAgwGm8JAEsCAA0ACAgwGm8JAEsCAAAA.Biohazard:BAAALAADCggIEwAAAA==.Bistoo:BAAALAAECgYIDAAAAA==.',Bl='Blasto:BAAALAAECgMIBQAAAA==.Bloodrock:BAAALAADCgIIAQAAAA==.',Bo='Boretta:BAAALAADCggICAAAAA==.Borioze:BAAALAAECgIIAgAAAA==.Boudha:BAAALAAECgEIAQAAAA==.Bountycoco:BAAALAAECgYIBgAAAA==.Bourguignon:BAAALAADCgcIBwAAAA==.',Br='Breeze:BAAALAADCgYIBwAAAA==.Brinsöp:BAAALAADCgQIBAAAAA==.Brînsôp:BAABLAAECoEWAAIOAAgIfSLKAgAiAwAOAAgIfSLKAgAiAwAAAA==.',Bu='Bulleur:BAAALAAECgMIBgAAAA==.',['Bé']='Béli:BAAALAAECgYIEgAAAA==.',['Bê']='Bênus:BAAALAAECgcIDgAAAA==.',['Bî']='Bîscøtte:BAAALAADCggICAAAAA==.',Ca='Cabot:BAAALAAECgEIAQAAAA==.Cabécou:BAAALAADCggICAAAAA==.Caelis:BAACLAAFFIEFAAIPAAMIbxfcAgAVAQAPAAMIbxfcAgAVAQAsAAQKgRgAAg8ACAhkH/MIAOYCAA8ACAhkH/MIAOYCAAAA.Caillan:BAAALAAFFAEIAQAAAA==.Calientæ:BAABLAAECoEYAAIQAAgITByyEQCcAgAQAAgITByyEQCcAgAAAA==.Caloune:BAAALAADCggIEAAAAA==.Catslunas:BAAALAAECgMIBgAAAA==.',Ce='Celador:BAAALAADCgcICQAAAA==.',Ch='Chabalka:BAAALAAECggIEwAAAA==.Chadess:BAAALAADCggIFgAAAA==.Chamexplose:BAAALAAECgMIBQAAAA==.Chder:BAAALAAFFAIIBAAAAA==.Chdol:BAAALAADCgYIBgAAAA==.Chibiî:BAAALAADCggICAABLAAECggIFwARAA8hAA==.Chibiï:BAABLAAECoEXAAMRAAgIDyGQBwDTAgARAAgIrSCQBwDTAgASAAEItB0EHgBMAAAAAA==.Chignion:BAAALAADCgcICQAAAA==.Chorba:BAABLAAECoEYAAIMAAgIYxG5BQAWAgAMAAgIYxG5BQAWAgAAAA==.Chwims:BAAALAADCggIDgAAAA==.Chøssette:BAABLAAECoEaAAQMAAgIriDDBAA2AgALAAgIyxdxEABnAgAMAAYI3h/DBAA2AgATAAMIdR1oLwABAQAAAA==.',Ci='Cirdan:BAABLAAECoEXAAIRAAgIICGmBQD7AgARAAgIICGmBQD7AgAAAA==.',Cl='Cleela:BAAALAAECgYIDgAAAA==.',Co='Cocolasticot:BAAALAAECgMIAwAAAA==.Cokalol:BAAALAAECgcIEAAAAA==.Coquincola:BAAALAAECggIEQAAAA==.Coren:BAAALAAECgMIBgAAAA==.Corén:BAAALAADCgcIBwAAAA==.',Cr='Cricridk:BAAALAAECgYIAQABLAAECgYICQAEAAAAAA==.Cricrih:BAAALAAECgYICQAAAA==.Croustipette:BAAALAADCgcIBwAAAA==.Crystaltears:BAAALAADCggICAAAAA==.Crêpobeurre:BAAALAAECgMIBAAAAA==.Crêpone:BAAALAADCgYIBwAAAA==.',Cu='Cunkaah:BAAALAADCgUIBQAAAA==.',Cy='Cyannah:BAAALAAECgMIAwAAAA==.',['Cæ']='Cælùs:BAAALAAECgYIEgAAAA==.',['Cé']='Céphirose:BAAALAADCggICAAAAA==.',['Cô']='Côrên:BAAALAAECgMIBAAAAA==.',['Cø']='Cøkkin:BAAALAAECggIDgAAAA==.',Da='Daemialax:BAAALAADCggIFwAAAA==.Danielosan:BAAALAAECgcICwAAAA==.Dannath:BAAALAAECgMIBgAAAA==.Dannathor:BAAALAADCgcIBwAAAA==.Danïa:BAAALAADCgcIBwAAAA==.Daorys:BAAALAAECgMIAwAAAA==.Darkhî:BAAALAAECgcIEQAAAA==.Darouk:BAAALAAECgYIBwAAAA==.Darthion:BAAALAAECgMIBgABLAAECggIFgAUALgkAA==.',De='Deadmøn:BAAALAADCggICwAAAA==.Deathpröof:BAABLAAECoEZAAIVAAgIKxj4DQBJAgAVAAgIKxj4DQBJAgAAAA==.Deathstrokie:BAAALAAECgMIAwAAAA==.Deepsnow:BAAALAADCgcIFQAAAA==.Demetera:BAAALAADCgcIBwAAAA==.Demolich:BAAALAAECgMIAwAAAA==.Demoll:BAAALAAECgQIBQAAAA==.Densëtsu:BAAALAADCgQIBAAAAA==.Derpedro:BAABLAAECoEXAAQLAAgIJyGSDACaAgALAAcImiCSDACaAgAMAAUIWBS9CwCOAQATAAUICBGjJABJAQAAAA==.Derwenmarie:BAAALAADCgMIAwAAAA==.Descartes:BAACLAAFFIEKAAIWAAUIZRk+AADhAQAWAAUIZRk+AADhAQAsAAQKgRgAAhYACAhAJBABAE8DABYACAhAJBABAE8DAAAA.Dest:BAAALAAFFAIIAgAAAA==.Devilo:BAAALAAECggICwAAAA==.',Dh='Dhaelys:BAAALAAECgUIBwAAAA==.Dherzia:BAAALAAFFAEIAQAAAA==.',Di='Dicotomi:BAAALAADCgIIAgAAAA==.Dirkraknthyr:BAAALAAECgYIBgAAAA==.Discipline:BAAALAADCggIEQAAAA==.',Dk='Dkpsuleuze:BAAALAADCggICAAAAA==.',Do='Dodupor:BAAALAADCggICAAAAA==.Domzerion:BAACLAAFFIEGAAIXAAMI0xs5AgAYAQAXAAMI0xs5AgAYAQAsAAQKgRgAAhcACAicIMUGAM8CABcACAicIMUGAM8CAAAA.Domzzer:BAAALAAECgYIDAABLAAFFAMIBgAXANMbAA==.',Dr='Draaktil:BAAALAADCgcIBwAAAA==.Dragonz:BAAALAADCgEIAQABLAADCggICAAEAAAAAA==.Drakach:BAAALAAECgcIEAAAAA==.Drakkhaön:BAAALAAECgMIAwAAAA==.Draklord:BAAALAADCggIFQAAAA==.Draksoul:BAAALAADCgcIBwAAAA==.Dralekk:BAAALAAECgUIBwAAAA==.Dro:BAAALAAECgYICgAAAA==.Droodinours:BAAALAAFFAIIAgAAAA==.Drova:BAAALAAECgMIBwAAAA==.',Du='Dulcølax:BAAALAAECgYIDQAAAA==.Durator:BAAALAADCgcIEwAAAA==.Duwt:BAACLAAFFIEJAAIHAAUIFRCUAAC1AQAHAAUIFRCUAAC1AQAsAAQKgRgAAgcACAhOHLgFAIQCAAcACAhOHLgFAIQCAAAA.',Dy='Dyzt:BAAALAADCgQIBAAAAA==.',['Dé']='Dékah:BAAALAADCggIDwAAAA==.Dékâmage:BAAALAAECgYIBgABLAAFFAEIAQAEAAAAAA==.',['Dê']='Dêâthface:BAAALAADCgcIBwAAAA==.',['Dî']='Dîspair:BAABLAAECoEUAAMOAAgIURxfCQCkAgAOAAgIURxfCQCkAgAJAAEImh62TQBRAAAAAA==.',['Dø']='Døssardo:BAAALAADCgcIBwAAAA==.',['Dù']='Dùùk:BAAALAADCggIBwAAAA==.',Eh='Eha:BAABLAAECoEVAAIJAAgIuR83BwDtAgAJAAgIuR83BwDtAgAAAA==.Ehime:BAAALAADCgcICAABLAAECggIFwAYACkhAA==.',Ei='Eitritriste:BAAALAAECgYICQAAAA==.',Ek='Ekliipsofeu:BAABLAAECoEaAAINAAgIpR9ABADUAgANAAgIpR9ABADUAgAAAA==.',El='Elenaa:BAAALAAECgIIAgAAAA==.',Eq='Equina:BAAALAADCggIDgAAAA==.',Er='Erytry:BAAALAAECgIIAgAAAA==.',Et='Etouitmort:BAAALAADCgEIAQAAAA==.',Ev='Everly:BAAALAADCgYIDAAAAA==.',Ew='Ewery:BAACLAAFFIEKAAMZAAUIqR8TAACiAQAZAAQI3CITAACiAQAaAAIIFRe5BgC6AAAsAAQKgRgAAxkACAhmJk8AAHYDABkACAgjJk8AAHYDABoAAwjoI3tTADwBAAAA.',Ex='Exces:BAAALAADCggICAAAAA==.',['Eï']='Eïtris:BAAALAAECgYIDAAAAA==.',Fa='Fabulous:BAAALAADCgMIAwAAAA==.Fal:BAACLAAFFIEJAAIVAAUIRBGgAACWAQAVAAUIRBGgAACWAQAsAAQKgRcAAhUACAiwIjQEAAMDABUACAiwIjQEAAMDAAAA.Fantaysis:BAAALAAECgMIAwAAAA==.Farielle:BAAALAAECgYIDgAAAA==.Fawcet:BAAALAADCgcIDAAAAA==.',Fe='Fehna:BAAALAAECgMIBgAAAA==.Felcinis:BAAALAADCggICAAAAA==.',Fi='Firehornet:BAABLAAECoEXAAMbAAgI7x9JDgCUAgAbAAgIbB5JDgCUAgAVAAgIPhe7DgA8AgAAAA==.Fistoheal:BAAALAADCgYIBwAAAA==.',Fl='Flambeur:BAAALAADCggIFgAAAA==.Floraé:BAAALAADCgQIAgAAAA==.Flowlink:BAAALAADCgYIBgAAAA==.Flox:BAAALAAECgMIBQAAAA==.',Fr='Fratrya:BAAALAAECgcICgAAAA==.Frozgul:BAAALAAFFAIIAgAAAA==.Fräeya:BAAALAADCgYIAgAAAA==.',Fu='Fuhlong:BAAALAAECgMIBgAAAA==.Fulfory:BAAALAADCgEIAQAAAA==.Furavier:BAAALAAECgUIAwAAAA==.Furãx:BAAALAAECgEIAQAAAA==.',['Fø']='Føugère:BAAALAADCgIIAgAAAA==.',Ga='Gaalmar:BAAALAAECgMIAwAAAA==.Gabz:BAAALAADCgQIBAAAAA==.Galathé:BAAALAADCgcIBwAAAA==.Garkiel:BAAALAADCggIEAAAAA==.Garmarar:BAAALAADCggIDQAAAA==.',Gh='Ghormor:BAAALAADCggICAABLAADCggICAAEAAAAAA==.',Gi='Gilthas:BAAALAADCggIDgAAAA==.',Go='Gogolwol:BAAALAADCggICAAAAA==.Golbûte:BAAALAAECgUIBgAAAA==.Gorgrock:BAAALAADCggIDwAAAA==.Gossipgîrl:BAAALAADCgMIAwABLAADCggICQAEAAAAAA==.',Gr='Gravlin:BAAALAADCgEIAQAAAA==.Greubz:BAAALAADCgUIBQAAAA==.',Gw='Gwëndoline:BAAALAADCggIDgAAAA==.',['Gà']='Gàthiel:BAAALAADCgcIBwAAAA==.',['Gø']='Gølborg:BAABLAAECoEaAAIWAAgIlR8PAwDUAgAWAAgIlR8PAwDUAgAAAA==.',Ha='Halfman:BAABLAAECoEWAAIQAAgIgRbgHAA6AgAQAAgIgRbgHAA6AgAAAA==.Happyy:BAAALAAECgcIDQAAAA==.Hawkersøul:BAAALAADCggIGAAAAA==.Haylea:BAAALAAECgMIBgAAAA==.Hazrag:BAAALAADCgIIAgAAAA==.',He='Heavenlord:BAAALAAECggICAAAAA==.Heeroow:BAAALAAECgcIBQAAAA==.Herziazen:BAAALAADCgcIDgABLAAFFAEIAQAEAAAAAA==.Hestïa:BAAALAAECgYIBwAAAA==.',Hi='Hippopotame:BAAALAADCggIEQAAAA==.',Ho='Hohên:BAAALAADCggICAAAAA==.Holybunny:BAAALAAECgcIBwAAAA==.Holydream:BAAALAAECgEIAQAAAA==.Holyshamp:BAAALAAECggIDgABLAAFFAQICQAcADcfAA==.',Hr='Hrndk:BAABLAAECoEUAAMaAAgI+B41DgC2AgAaAAgI+B41DgC2AgAZAAcIrQjaFAB4AQAAAA==.',Hu='Hunkatastrof:BAAALAADCgUIBQAAAA==.',Hy='Hydrastartes:BAAALAAFFAIIAgAAAA==.Hydrastral:BAAALAAECgYIBgABLAAFFAIIAgAEAAAAAA==.Hysteria:BAAALAAECgMIBAAAAA==.',['Hâ']='Hâppyy:BAAALAAECgIIAgAAAA==.',['Hé']='Hérésia:BAAALAADCgIIAgAAAA==.',['Hë']='Hëlkäli:BAAALAADCgMIAwAAAA==.',['Hø']='Høhenheim:BAAALAADCgYIBgAAAA==.',Ii='Iivil:BAAALAADCggIEAABLAAECgYIDwAEAAAAAA==.Iizhékat:BAAALAADCggICwAAAA==.',Il='Ilianass:BAAALAAECgYIBgAAAA==.Ilmis:BAAALAAECgMIAwAAAA==.',Im='Imstuck:BAABLAAECoEWAAIXAAgIEByqCACjAgAXAAgIEByqCACjAgABLAAFFAIIAgAEAAAAAA==.',In='Inëth:BAAALAADCggICAABLAAECgYIDwAEAAAAAA==.',Is='Isumel:BAAALAADCgcIDgAAAA==.',Iz='Izumø:BAAALAAECgcIBQAAAA==.',['Iì']='Iìli:BAAALAAFFAMIAwAAAA==.',Ja='Jafah:BAAALAADCgcIBwAAAA==.Jangah:BAAALAAECgcIDQAAAA==.',Jn='Jnox:BAAALAADCgcIBwAAAA==.',Jo='Joejo:BAAALAAFFAQIBAAAAA==.',Ka='Kaartoön:BAAALAADCggICQAAAA==.Kadori:BAAALAADCggIDQAAAA==.Kaemus:BAAALAADCggICwAAAA==.Kaeyla:BAAALAAECgMIBAABLAAFFAMIBQALADoRAA==.Kafrine:BAAALAAECgMIBQAAAA==.Kagesou:BAAALAADCggICAABLAAECggIGAAbAFYmAA==.Kageya:BAABLAAECoEYAAIbAAgIViZLAACQAwAbAAgIViZLAACQAwAAAA==.Kaiix:BAAALAAECgEIAQAAAA==.Kainkin:BAAALAAECgYICgAAAA==.Kalannar:BAAALAAECgMIBAAAAA==.Kalen:BAAALAAECgMIAwAAAA==.Kalvert:BAAALAADCgYIBgAAAA==.Kalverth:BAAALAADCgEIAQAAAA==.Kalï:BAAALAADCgcIEQAAAA==.Kamadroody:BAACLAAFFIEIAAMSAAQI4hdZAABgAQASAAQI+hNZAABgAQARAAIIthOmBgCYAAAsAAQKgRgAAxIACAj/JFsAAGQDABIACAj/JFsAAGQDABEACAhnGCAUAAQCAAAA.Kamawings:BAAALAAECgcIBwAAAA==.Kamora:BAAALAAECgIIAgABLAAECgMIAwAEAAAAAA==.Kanapêche:BAAALAAECgYICgAAAA==.Kaphéïne:BAAALAADCggIEwAAAA==.Kappy:BAAALAAECgEIAQAAAA==.Kargün:BAAALAAECgYIBgABLAAFFAIIAgAEAAAAAA==.Karna:BAAALAADCgYIBgABLAAECgMIBgAEAAAAAA==.Kassdal:BAAALAAFFAIIAgAAAA==.Katelas:BAAALAAECgMIBgAAAA==.Kathremas:BAAALAADCgYIBgAAAA==.Katilo:BAAALAADCgcICwAAAA==.',Ke='Keellyy:BAAALAADCgYIBgAAAA==.Keeprollin:BAAALAAECgUICQAAAA==.Kehilde:BAABLAAECoEXAAMTAAgI3xx4DQAAAgATAAcIchh4DQAAAgALAAUI9hlGKgCEAQAAAA==.',Kh='Kharly:BAABLAAECoEZAAIZAAgIvxoaBQCGAgAZAAgIvxoaBQCGAgAAAA==.Khygon:BAAALAADCggICAAAAA==.',Ki='Kikiteub:BAAALAADCgcIDQAAAA==.Kina:BAAALAAECgEIAQAAAA==.Kinderpigoou:BAAALAAECgYIDgAAAA==.',Ko='Kodu:BAAALAAECgMIBgAAAA==.Kopuma:BAAALAADCggICAAAAA==.Koçero:BAAALAADCgIIAgAAAA==.',Kr='Krakoukas:BAAALAAECgYIBgAAAA==.Krizz:BAAALAADCgcICAABLAAECggIFwAHAB4RAA==.Krðw:BAAALAAECgYIBwAAAA==.Krøgaar:BAAALAADCgcIDAABLAADCggIDgAEAAAAAA==.',Ku='Kuatrequarts:BAAALAADCgcIBwAAAA==.Kumaneko:BAAALAAECgMIBgAAAA==.Kunzell:BAAALAADCgcIDQAAAA==.Kurmuda:BAABLAAECoEXAAMTAAgIlx8HAwDDAgATAAgIhx4HAwDDAgALAAcImxWCGQAEAgAAAA==.Kuroko:BAAALAADCgcIBwABLAAECggIFQADALAfAA==.',Ky='Kyarh:BAAALAAECgIIAgAAAA==.Kyubak:BAAALAAECgIIAgAAAA==.',['Kâ']='Kâlisi:BAAALAAECgMIBAAAAA==.',['Kä']='Käram:BAAALAAECgUIBgAAAA==.',['Kæ']='Kæshüa:BAAALAADCgUICAAAAA==.',['Kè']='Kèrt:BAAALAAFFAMIAwAAAA==.',La='Lakia:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.Lamagïcïenne:BAAALAADCgYICAAAAA==.Lanaël:BAAALAAECgMIBQAAAA==.Landroval:BAAALAAECgYIBgAAAA==.Landrösama:BAABLAAECoEaAAIVAAgIqiPGAgAjAwAVAAgIqiPGAgAjAwAAAA==.',Le='Ledk:BAAALAAECgQIBAAAAA==.Legreatfoldo:BAAALAADCggIDgABLAADCggIDwAEAAAAAA==.Lerem:BAAALAAFFAIIAgABLAAFFAUICgAUAKobAA==.Lesthys:BAAALAADCggICAAAAA==.Leubon:BAAALAAECgIIAgAAAA==.Leéloo:BAAALAADCggICAAAAA==.',Li='Liiviil:BAAALAAECgYIDwAAAA==.Lilwon:BAAALAAECgYIDwAAAA==.',Lo='Lotrith:BAAALAAECgUIBwABLAAECgYICAAEAAAAAA==.Loubinorc:BAAALAADCgcIBwAAAA==.',Lu='Lugna:BAAALAADCggICAABLAADCggIEQAEAAAAAA==.Lutie:BAABLAAECoEaAAILAAgIlB1xCwCqAgALAAgIlB1xCwCqAgAAAA==.',Ly='Lydrith:BAAALAAECgEIAQAAAA==.Lynsiia:BAAALAADCgMIAwAAAA==.Lynso:BAAALAAECgYIDgAAAA==.Lyria:BAAALAAECgYICQAAAA==.Lyrìa:BAAALAADCggIEAABLAAECgYICQAEAAAAAA==.Lyrìà:BAAALAAECgEIAQABLAAECgYICQAEAAAAAA==.Lyría:BAAALAADCggIDQABLAAECgYICQAEAAAAAA==.Lyríà:BAAALAADCgYIBgABLAAECgYICQAEAAAAAA==.Lyrîà:BAAALAAECgMIBgABLAAECgYICQAEAAAAAA==.',['Lâ']='Lâbrute:BAAALAADCgMIAwAAAA==.',['Lé']='Lénodrood:BAAALAADCggIGAAAAA==.',['Lï']='Lïta:BAAALAADCggIDAAAAA==.',['Lû']='Lûtine:BAAALAADCggICAAAAA==.',Ma='Machiavelus:BAAALAADCggICAAAAA==.Magikcham:BAAALAAECgYICAAAAA==.Magira:BAAALAADCggICAAAAA==.Magixx:BAAALAAECgYICwABLAAECggIFwATAJcfAA==.Mahkah:BAAALAAECgcIDwAAAA==.Maligan:BAABLAAECoEUAAMQAAgIsRnnIAAdAgAQAAgIexjnIAAdAgANAAMI6xKKLwC9AAAAAA==.Mamassita:BAAALAAECgMIBAAAAA==.Mamour:BAAALAADCggIDwAAAA==.Marss:BAAALAAECgMIAwAAAA==.Maryaa:BAAALAADCgQIBAAAAA==.Mauwice:BAAALAADCggICAAAAA==.Maxyster:BAAALAADCggICAABLAAECggIGgALAJQdAA==.Maysa:BAAALAADCggICAABLAAECgMIAwAEAAAAAA==.Maëlstrøm:BAAALAADCgcIBwAAAA==.Maîrîa:BAAALAADCggICAAAAA==.Maïwèen:BAAALAADCgcIDQAAAA==.',Me='Medjaïh:BAABLAAECoEXAAIPAAgISSDfBwD4AgAPAAgISSDfBwD4AgAAAA==.Megademon:BAAALAADCgUIBQAAAA==.Mermoud:BAAALAAFFAEIAQAAAA==.',Mi='Mifrostmiput:BAAALAAECgYIBgAAAA==.Miklah:BAAALAADCgIIAgABLAADCggIDgAEAAAAAA==.Minuit:BAAALAADCgYIBgAAAA==.Miryn:BAAALAAECgMIAwAAAA==.Mistickk:BAAALAAECgcIEgAAAA==.Miséo:BAABLAAECoEXAAMJAAgI7BgkDwBmAgAJAAgI7BgkDwBmAgAOAAEIsgGPZAAoAAAAAA==.Mixe:BAABLAAECoEXAAIYAAgIKSE6AwDRAgAYAAgIKSE6AwDRAgAAAA==.Miyax:BAAALAAECgcIDwAAAA==.',Mo='Moffê:BAAALAADCgEIAQAAAA==.Mojito:BAAALAADCggIFAAAAA==.Mokko:BAAALAAECgYICwAAAA==.Mokoö:BAACLAAFFIEKAAIYAAUInx5KAAD/AQAYAAUInx5KAAD/AQAsAAQKgRgAAhgACAh3JbEAAGcDABgACAh3JbEAAGcDAAEsAAQKBggLAAQAAAAA.Moköo:BAAALAAECgYIBgABLAAECgYICwAEAAAAAA==.Moldiver:BAAALAAECgMIAwAAAA==.Morsiat:BAABLAAECoEXAAINAAgIJiHHAgAMAwANAAgIJiHHAgAMAwAAAA==.Mortimar:BAABLAAECoEUAAIWAAcI3g+KCwCSAQAWAAcI3g+KCwCSAQAAAA==.Morzhan:BAAALAADCgcIBwABLAAFFAUICQAVAEQRAA==.',My='Myrna:BAAALAADCgEIAQAAAA==.Mystice:BAAALAADCgcIDQAAAA==.',['Mæ']='Mæsamune:BAAALAADCgcIBwAAAA==.',['Mè']='Mèrcurochrom:BAAALAADCgYIBgABLAAECgMIBgAEAAAAAA==.',['Mé']='Métapîté:BAAALAAFFAEIAQAAAA==.',['Mì']='Mìrabelle:BAAALAAECgIIAgAAAA==.',['Mî']='Mîmesis:BAAALAADCggICQAAAA==.',['Mù']='Mùrmüre:BAAALAADCggICAABLAAECgYIDwAEAAAAAA==.',['Mü']='Mürmûre:BAAALAAECgYIDwAAAA==.',Na='Nadgil:BAAALAADCggIEQAAAA==.Nagua:BAAALAAECgcIEQAAAA==.Nahuro:BAAALAADCgcIBwAAAA==.Nainpadaire:BAAALAADCgUIBQAAAA==.Nakunekouy:BAAALAAECgYIBwAAAA==.Nasbet:BAAALAAFFAIIAwAAAA==.Natarïel:BAAALAAECgMIAwAAAA==.Natch:BAACLAAFFIEGAAIGAAMISx4yAQArAQAGAAMISx4yAQArAQAsAAQKgRgAAgYACAjZH/IBANYCAAYACAjZH/IBANYCAAAA.Natsukï:BAAALAAECgcIDgAAAA==.Navì:BAAALAAECgMIBAAAAA==.',Ne='Neidx:BAAALAADCgcIBwAAAA==.Nelakk:BAAALAAFFAEIAQAAAA==.Nelaque:BAAALAAECgEIAQAAAA==.Nelfafion:BAACLAAFFIEKAAIXAAUILQ3sAACoAQAXAAUILQ3sAACoAQAsAAQKgRgAAxcACAjOHZUGANICABcACAjOHZUGANICAB0AAwhlEg0GALMAAAAA.Neyvaë:BAAALAADCggIFwAAAA==.',Ni='Nibelung:BAAALAADCggICAABLAAECgYIDgAEAAAAAA==.Nibâna:BAACLAAFFIEJAAMJAAUIaRulAADlAQAJAAUIaRulAADlAQAOAAEIiQp7DwBNAAAsAAQKgRgAAgkACAjsJXwBAGYDAAkACAjsJXwBAGYDAAAA.Nibäna:BAAALAAECggICAAAAA==.Nicolebolas:BAAALAAECgYICwAAAA==.Nicrou:BAAALAADCgUIBQAAAA==.Nightsorrow:BAAALAADCggIEAAAAA==.',No='Nojhadh:BAAALAAECgEIAQAAAA==.Nojhawar:BAABLAAECoEWAAIeAAgIkiStAQA6AwAeAAgIkiStAQA6AwAAAA==.Nomar:BAAALAADCggIDQAAAA==.Nondesdjou:BAAALAADCggICAAAAA==.Novawi:BAAALAADCggICAAAAA==.',Nu='Nuyzeph:BAAALAAECgEIAQAAAA==.',Ny='Nydk:BAAALAAECgYICwAAAA==.',['Né']='Néllyrr:BAAALAADCggIDgAAAA==.',['Nï']='Nïghtingale:BAAALAAECgYIEgAAAA==.',['Nö']='Nööt:BAAALAAECgcIDgAAAA==.',Ob='Obaldine:BAAALAADCggICAAAAA==.',Oh='Ohaine:BAAALAADCgYIBwAAAA==.',Ol='Olexstroszo:BAABLAAECoEXAAIXAAgI1iT6AABmAwAXAAgI1iT6AABmAwAAAA==.',Op='Ophidian:BAAALAAECgMIBQAAAA==.',Or='Orodiohtar:BAAALAADCggIFQAAAA==.',Ox='Oxe:BAAALAADCggIDwAAAA==.',Pa='Pabolechasso:BAAALAAECgIIAwAAAA==.Pachamama:BAAALAAECgYIBwAAAA==.Palado:BAAALAADCgYIBgAAAA==.Pappÿ:BAAALAADCgUIBQAAAA==.Parabéllüm:BAAALAADCgMIAwAAAA==.',Pe='Peige:BAAALAAFFAIIAgABLAAFFAIIAgAEAAAAAA==.Pepelaugh:BAAALAAECgYIDwAAAA==.Pera:BAAALAAECgYICAAAAA==.Perline:BAAALAAECgYICgAAAA==.Persone:BAAALAADCgYIBgAAAA==.Pewpewpew:BAABLAAECoEaAAIRAAgINSJsBQAAAwARAAgINSJsBQAAAwAAAA==.',Pi='Pilav:BAAALAAECgYIDgAAAA==.Pitô:BAAALAAECgYIDAABLAAFFAMIBQARABgeAA==.Pixiz:BAAALAAECgUIBQAAAA==.',Pl='Plearn:BAAALAAECgYICQAAAA==.Plùm:BAAALAAECgMIBgAAAA==.',Po='Potatonk:BAAALAADCgUIAgAAAA==.',Pr='Pretoriana:BAAALAADCggICQABLAAECgYICwAEAAAAAA==.Prins:BAAALAAECgYICgAAAA==.',Pw='Pwetpwet:BAAALAADCgcIFQAAAA==.',Py='Pyrothraxus:BAAALAADCggICAAAAA==.',['Pà']='Pàppy:BAAALAADCgEIAQAAAA==.',['Pã']='Pãppy:BAAALAADCgMIAwAAAA==.Pãppÿ:BAAALAADCggICwAAAA==.',['Pä']='Päppy:BAAALAADCgcIBwAAAA==.',['På']='Påppy:BAAALAAECgYIDAAAAA==.Påppÿ:BAAALAADCgYIBAAAAA==.',Qu='Quolt:BAAALAAECgMIAwAAAA==.',Ra='Racxyswar:BAACLAAFFIEKAAIPAAUIWRqCAADzAQAPAAUIWRqCAADzAQAsAAQKgRgAAg8ACAjkJGsBAGsDAA8ACAjkJGsBAGsDAAAA.Rakjan:BAAALAADCggIEgAAAA==.Ratakan:BAAALAADCggIHwAAAA==.Ravenstealer:BAAALAAECgMIBgAAAA==.Raylian:BAAALAAECgMICQAAAA==.',Re='Regdär:BAAALAADCgUIBQAAAA==.Retlol:BAAALAAECggIBQAAAA==.Rezmod:BAAALAAECgcIDwABLAAFFAMIBgAXANMbAA==.',Ri='Ricardo:BAAALAADCgYIBgAAAA==.Rileys:BAAALAADCgcIDQAAAA==.',Ro='Ronaldo:BAABLAAECoEVAAIbAAgIQyNdEAB7AgAbAAgIQyNdEAB7AgAAAA==.Rouki:BAAALAADCgcIBwAAAA==.',Ru='Rurka:BAAALAAECgMIAwAAAA==.',['Ré']='Ré:BAAALAAECggIEQAAAA==.',['Rî']='Rîn:BAABLAAECoEVAAIDAAgIsB+WBQDGAgADAAgIsB+WBQDGAgAAAA==.',Sa='Sakynah:BAAALAADCgYIBgAAAA==.Sancerre:BAAALAADCggIDwAAAA==.Saphiara:BAAALAADCgMIAwAAAA==.Saphyre:BAAALAAECgMIAwAAAA==.Sativva:BAAALAAECgcIEAAAAA==.Sawoumane:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.',Sc='Scarpy:BAAALAAECgYIDAAAAA==.Scattershot:BAAALAAECgIIBAAAAA==.',Se='Seb:BAAALAAECgMIBgAAAA==.Sedifen:BAAALAADCggIFAAAAA==.Serrezza:BAAALAADCggICAAAAA==.Sezeh:BAAALAAECgUIBQAAAA==.',Sh='Shadðw:BAAALAADCggICAAAAA==.Shalyssra:BAAALAADCgEIAQAAAA==.Shamyaleau:BAABLAAECoEXAAMDAAgIVBu7DQBbAgADAAgIVBu7DQBbAgACAAQItR9sKwBxAQAAAA==.Shandwà:BAACLAAFFIEGAAIQAAMIoiEeAwAnAQAQAAMIoiEeAwAnAQAsAAQKgRgAAhAACAjSJbsCAE4DABAACAjSJbsCAE4DAAAA.Shaolinsan:BAAALAAECggIEAAAAA==.Sharrah:BAAALAAECgMIBgAAAA==.Sheev:BAAALAADCggIFgAAAA==.Shyffu:BAAALAADCggICQAAAA==.Shérôn:BAAALAAECgIIAwAAAA==.Shêron:BAAALAADCggICAAAAA==.',Si='Siegvalde:BAABLAAECoEVAAMWAAgIViOxAgDqAgAWAAgIViOxAgDqAgAaAAEI3wOvnwArAAAAAA==.Silveria:BAAALAAECgMIBQAAAA==.',Sk='Skept:BAAALAAECgMIAwABLAAECggIDgAEAAAAAA==.Skunky:BAAALAADCggICgAAAA==.Skãdi:BAABLAAECoEXAAMbAAgIBx6pEQBtAgAbAAgI1BupEQBtAgAVAAcINRlYEQAWAgAAAA==.',Sn='Sneakyman:BAACLAAFFIEKAAMUAAUIqhtQAACsAQAUAAQIlh5QAACsAQAfAAEI/Q/7AwBaAAAsAAQKgRcAAx8ACAgPJHsAAE4DAB8ACAhfI3sAAE4DABQACAhhIZEFAOwCAAAA.',So='Solary:BAAALAADCgMIBQAAAA==.Sombrenuit:BAAALAAECggIDgAAAA==.Sorhen:BAAALAAECgMIBQAAAA==.Soulhammer:BAAALAAECgcIEQAAAA==.',Sp='Spooknick:BAAALAAECgQIBAAAAA==.',St='Stardust:BAAALAAECgQIBAABLAAFFAIIAgAEAAAAAA==.Stecia:BAAALAADCggICQAAAA==.Stönzz:BAAALAADCgMIAwAAAA==.',Su='Summernight:BAAALAAECggIEAABLAAFFAQIBwAOACcgAA==.Sumon:BAAALAADCggICAAAAA==.Surfacing:BAAALAADCggICAAAAA==.Suyriu:BAAALAAECgIIAgAAAA==.',Sy='Sylvaneth:BAAALAADCgcIFQAAAA==.Symoril:BAAALAAECgMIBQAAAA==.',['Sâ']='Sâthia:BAAALAADCggICAABLAAECgYICAAEAAAAAA==.',['Sé']='Séby:BAAALAADCggICAAAAA==.Sédirok:BAABLAAECoEWAAIbAAgIQhaIEAB5AgAbAAgIQhaIEAB5AgAAAA==.',['Sö']='Sölazya:BAAALAADCggIDAABLAAECggIEQAEAAAAAA==.',['Sø']='Sømbra:BAAALAAECgcIBwAAAA==.',Ta='Taakoma:BAAALAADCggIDwAAAA==.Tadliss:BAAALAAECgYICQAAAA==.Tagrine:BAAALAAFFAIIAgAAAA==.Tahine:BAAALAAECgMIAwAAAA==.Talosh:BAAALAADCggICAAAAA==.Tanouke:BAAALAAECgUIBgAAAA==.Taramasta:BAAALAADCgYICAAAAA==.Tatataque:BAAALAAECgMIAwAAAA==.Taylorswifer:BAAALAADCgcIBQAAAA==.Taylorswift:BAAALAADCgEIAQAAAA==.Tazer:BAAALAAECgYICQAAAA==.Tazgodin:BAAALAADCggIDwAAAA==.',Tc='Tchezie:BAAALAADCgIIAgAAAA==.',Te='Temôsare:BAAALAAECgYIBgAAAA==.Temøsare:BAACLAAFFIEGAAIgAAMI7h3bAAAOAQAgAAMI7h3bAAAOAQAsAAQKgRgAAiAACAjoI0UBAEYDACAACAjoI0UBAEYDAAAA.Teneb:BAAALAADCgEIAQABLAAECgYIDwAEAAAAAA==.',Th='Thailung:BAAALAAECgYICAAAAA==.Thalanyr:BAAALAAECgYIBwAAAA==.Thalyssraune:BAAALAADCggICAAAAA==.Theodryx:BAAALAADCgcICAAAAA==.Theoner:BAAALAAECgMIBgAAAA==.Thorgnol:BAAALAAECgMIBgAAAA==.Thp:BAAALAAECgMIBgAAAA==.Thröll:BAAALAAECggIDgAAAA==.',To='Toe:BAAALAAECgcIDwAAAA==.Tohrrin:BAAALAADCgYIBgAAAA==.Toomz:BAAALAAECgYIDQAAAA==.',Tr='Trakhline:BAAALAADCgQIBAAAAA==.Traumos:BAAALAAECgMIAwAAAA==.Tropbalec:BAAALAADCgYIBgAAAA==.',Tu='Tunare:BAAALAAECgMIBQAAAA==.Tupacalipss:BAAALAAECgYIBgAAAA==.',Tw='Twark:BAAALAAECgIIAgAAAA==.Twinsen:BAAALAAECgEIAQAAAA==.',Ty='Tyee:BAAALAAECgEIAQAAAA==.Tyrant:BAAALAADCgcIBwAAAA==.Tyttuss:BAAALAADCgEIAQAAAA==.',['Tÿ']='Tÿräël:BAAALAADCggICAAAAA==.',Um='Umea:BAAALAADCgIIAgAAAA==.',Va='Vakho:BAAALAADCgMIAwAAAA==.Vandal:BAAALAAECgYIDAAAAA==.Varen:BAAALAAECgYICAAAAA==.Vaxildan:BAAALAAFFAEIAQAAAA==.',Vi='Vigiel:BAAALAADCggIDQAAAA==.Villalobos:BAAALAADCgUIBQAAAA==.Vixenn:BAAALAAECgcIEAAAAA==.',Vu='Vulpix:BAAALAAECgMIBAAAAA==.',Wa='Walfvor:BAAALAAECgMIBQAAAA==.Wallcraft:BAAALAADCgcIBwAAAA==.',We='Welunock:BAAALAADCggICQAAAA==.Wemby:BAAALAADCgcIBwAAAA==.Wenlyra:BAAALAAECgUIBQAAAA==.',Wi='Wifi:BAAALAADCgcIBAAAAA==.Wizaniaùro:BAAALAADCgEIAQAAAA==.Wizdumz:BAAALAAECgcIDQAAAA==.',Wo='Wouloc:BAAALAADCggICAAAAA==.',['Wù']='Wùshi:BAAALAAECgMIBQAAAA==.',Xa='Xaerr:BAABLAAECoEYAAIBAAgI5iMIBABJAwABAAgI5iMIBABJAwAAAA==.Xasmia:BAAALAAECgcIBwAAAA==.',Xv='Xvll:BAAALAAFFAIIAgAAAA==.',['Xà']='Xàe:BAAALAAECgYIEgAAAA==.',['Xé']='Xéalainur:BAAALAAECgMIBgAAAA==.Xéanhort:BAABLAAECoEWAAIUAAgIuCTZAABjAwAUAAgIuCTZAABjAwAAAA==.',Ya='Yaboï:BAAALAAFFAEIAQAAAA==.Yaucky:BAAALAADCgcIEwAAAA==.',Yg='Yggdrazyl:BAAALAAECgIIAgAAAA==.',Yh='Yhann:BAAALAADCggIDwAAAA==.',Yi='Yilin:BAAALAAECgIIAgAAAA==.Yillin:BAAALAAECggIEwAAAA==.',Yj='Yjda:BAAALAADCgcIBwAAAA==.',Yo='Yogg:BAAALAAECgUIBwAAAA==.Yolowar:BAAALAADCggIDwAAAA==.Yoshinon:BAAALAADCgYICAABLAAECgcIDQAEAAAAAA==.',Ys='Ys:BAAALAAECgYIDgAAAA==.',Yu='Yukora:BAAALAAECgMIAwAAAA==.Yusuké:BAAALAAFFAMIAwABLAAFFAMIBQARABgeAA==.',['Yè']='Yèrsin:BAABLAAECoEXAAIPAAgIhyKLBQAeAwAPAAgIhyKLBQAeAwAAAA==.Yèrsinýa:BAAALAAECgMIAwAAAA==.Yèrsyn:BAAALAADCgIIAgAAAA==.',['Yû']='Yûsuke:BAACLAAFFIEFAAIRAAMIGB62AQASAQARAAMIGB62AQASAQAsAAQKgRYAAhEACAh2JbICAEADABEACAh2JbICAEADAAAA.',Za='Zaema:BAAALAADCggICAAAAA==.Zaganox:BAAALAAECggICQAAAA==.Zaily:BAAALAAECgYIBgAAAA==.Zalyssia:BAAALAAECgIIAgAAAA==.Zargadk:BAABLAAECoEUAAIaAAgICxwsEwCBAgAaAAgICxwsEwCBAgAAAA==.Zargostrasza:BAABLAAECoEYAAIXAAgIDiG0BgDQAgAXAAgIDiG0BgDQAgAAAA==.Zargothrym:BAAALAAECgQIBAABLAAECggIGAAXAA4hAA==.Zauzo:BAAALAADCgUIBQAAAA==.Zawawar:BAAALAAECgMIAwAAAA==.Zaynna:BAAALAADCgcICAAAAA==.',Ze='Zeenj:BAAALAADCgcICQAAAA==.Zeffuh:BAAALAADCgUIBwAAAA==.Zelryth:BAAALAADCggIDgAAAA==.Zendikar:BAAALAAECgYIBgABLAAECggIFQAJALkfAA==.',Zi='Zigue:BAAALAAECgEIAQABLAAFFAEIAQAEAAAAAA==.Zizanis:BAAALAAECgMICAAAAA==.',Zo='Zolt:BAAALAADCgQIBAAAAA==.Zornthorx:BAAALAAECgMIBAAAAA==.',Zu='Zupgugh:BAAALAADCgQIAwAAAA==.',['Zæ']='Zæd:BAAALAAECggIEAAAAA==.Zæliéo:BAAALAAECgYICAABLAAECggIEAAEAAAAAA==.',['Ät']='Ätøn:BAAALAADCggIFgAAAA==.',['Ås']='Åsgrr:BAAALAADCgQIBAAAAA==.',['Éo']='Éosx:BAABLAAECoEYAAIKAAgI5h4kBAC7AgAKAAgI5h4kBAC7AgAAAA==.',['Ép']='Époshamy:BAAALAADCggICgAAAA==.',['Ér']='Érøse:BAAALAAFFAEIAQAAAA==.',['Ëb']='Ëbolha:BAAALAADCgcIDgAAAA==.',['Ër']='Ërøse:BAAALAAECggICAAAAA==.',['Ës']='Ësoria:BAAALAAECgYIDgAAAA==.Ësyria:BAAALAAECgYICwABLAAECgYIDgAEAAAAAA==.',['Ðr']='Ðrøøð:BAAALAAECgIIAwAAAA==.',['Ðø']='Ðørã:BAAALAAECgMIAgAAAA==.',['ßa']='ßaal:BAAALAADCgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end