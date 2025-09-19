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
 local lookup = {'Warrior-Arms','Paladin-Retribution','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Unknown-Unknown','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Druid-Restoration','Druid-Balance','DeathKnight-Unholy','Paladin-Holy','Hunter-Marksmanship','Shaman-Restoration','Mage-Arcane','Mage-Frost','Warrior-Fury',}; local provider = {region='EU',realm='Wildhammer',name='EU',type='weekly',zone=44,date='2025-08-30',data={Ae='Aenos:BAAALAAECgcIDwAAAA==.',Ag='Agapi:BAAALAADCggICAAAAA==.',Ah='Ahktar:BAAALAAECgQICAAAAA==.',Ak='Akujidormu:BAAALAADCggIDgAAAA==.',Al='Aladriel:BAAALAAECgYIDAAAAA==.Alyndea:BAAALAAECgcIEAAAAA==.Alynnah:BAAALAAECgcIEAAAAA==.Alyrai:BAAALAAECgMIBgAAAA==.',Am='Amnesys:BAAALAADCgQIBAAAAA==.',An='Angus:BAAALAADCgcIBwAAAA==.Anusówka:BAAALAAECgMIBAAAAA==.',Ap='Aphu:BAAALAAECgUIBQAAAA==.Appleknocker:BAAALAADCggICQAAAA==.',Aq='Aquadella:BAAALAAECgMIBAAAAA==.',Ar='Archocko:BAAALAAECgQIBQAAAA==.Arieth:BAAALAAECgMIBwAAAA==.Ariyel:BAAALAADCggICwAAAA==.Arterra:BAAALAAECgMIBAAAAA==.Artorius:BAAALAADCgcIBwAAAA==.Arttu:BAAALAADCgIIAgAAAA==.Arwén:BAAALAADCggIDwAAAA==.',As='Ashlynn:BAABLAAECoEUAAIBAAgIOyVsAAA8AwABAAgIOyVsAAA8AwAAAA==.Ashmedai:BAAALAADCggICAABLAAECggIFwACAA8jAA==.Astaroth:BAAALAADCggICAAAAA==.',Av='Avoided:BAAALAAECgEIAQAAAA==.Avsdh:BAAALAAECgYIDQAAAA==.Avsplinters:BAAALAADCgUIBQAAAA==.',Aw='Awenita:BAAALAAECgIIAgAAAA==.',Ay='Ayvan:BAAALAADCgcIBwAAAA==.',Az='Azala:BAAALAADCgEIAQAAAA==.Azaleara:BAAALAADCggIDAAAAA==.Azéko:BAABLAAECoEVAAIBAAgIHxffAgBGAgABAAgIHxffAgBGAgAAAA==.',Ba='Babsyknight:BAAALAAECgcIDgAAAA==.Babygirl:BAAALAADCgIIAgAAAA==.Baldr:BAAALAAECgMIAwAAAA==.Ballsatron:BAAALAAECgMIBQAAAA==.Ballsfreezer:BAAALAAECgcIEQAAAA==.Barrypal:BAABLAAECoEVAAIDAAgI2hzQBACBAgADAAgI2hzQBACBAgAAAA==.Baton:BAAALAAECgMIAwAAAA==.',Be='Beardozer:BAAALAADCgUIAwAAAA==.Beefybért:BAAALAAECgcIDwAAAA==.Belgath:BAAALAADCgYIDAAAAA==.Belora:BAAALAAECgYIDwAAAA==.Beltainuss:BAAALAAECgMIAwAAAA==.',Bl='Blbonka:BAAALAADCgIIAgAAAA==.Blitzwing:BAAALAAECgMIAwAAAA==.Bloomy:BAAALAAECggICAAAAA==.Blox:BAAALAAECgYIDgABLAAECgYIFAAEADAbAA==.Bluxilidan:BAAALAAECgMIAwABLAAECgYIFAAEADAbAA==.Bluxrthen:BAABLAAECoEUAAIEAAYIMBsxBwDbAQAEAAYIMBsxBwDbAQAAAA==.',Bo='Borda:BAAALAADCgcIDQAAAA==.',Br='Bracket:BAAALAAECgEIAQAAAA==.Brawlyx:BAAALAADCgIIAgAAAA==.Brozacek:BAAALAADCgEIAQAAAA==.',Bu='Bubbelstorm:BAAALAAECgYICwAAAA==.Bumhunter:BAAALAAECgcIDwAAAA==.Burned:BAAALAAECggIDwAAAA==.',Ca='Captur:BAAALAAECgMIBAAAAA==.Cargilly:BAAALAADCgMIAwAAAA==.Carmelitaa:BAABLAAECoEXAAIFAAgIFRLBDADLAQAFAAgIFRLBDADLAQAAAA==.Carnatus:BAAALAADCgcIBwABLAAECgMIBwAGAAAAAA==.Caçapiolhos:BAAALAADCgIIAgABLAAECgMIBwAGAAAAAA==.',Ce='Cewik:BAAALAAECgUIBwAAAA==.',Ch='Chibbobo:BAAALAADCggIEAAAAA==.Chibbobobo:BAAALAAFFAIIBAAAAA==.Christus:BAAALAADCgQIBAAAAA==.Chucklee:BAAALAAECgQIBAAAAA==.',Cl='Cloudcaller:BAAALAADCgMIAwAAAA==.',Co='Coramora:BAAALAAECgMIAwAAAA==.Coramóra:BAAALAADCggICAABLAAECgMIAwAGAAAAAA==.',Cr='Credite:BAAALAAECgQIBgAAAA==.Crg:BAAALAADCgUIBQAAAA==.Crowenuss:BAAALAAECggICAAAAA==.Cruciatus:BAAALAADCgcIDgABLAAECgMIBwAGAAAAAA==.Crushi:BAAALAAECgcIEwAAAA==.',Cu='Cupcake:BAABLAAECoEUAAIHAAcIuh71EgB4AgAHAAcIuh71EgB4AgAAAA==.Curséd:BAAALAAECgMIBAAAAA==.',Cy='Cybersony:BAAALAAECgcIEgAAAA==.',Da='Daddyfufu:BAAALAAECgEIAQAAAA==.Daerron:BAAALAAECgYIDwAAAA==.Daklol:BAAALAAECgUIBgABLAAECggIFAAGAAAAAQ==.Damusc:BAAALAADCggIDwAAAA==.Danzka:BAAALAAECgcICgAAAA==.Daxford:BAAALAAECgIIAgAAAA==.',De='Deathmän:BAAALAADCgEIAQAAAA==.Deceptacon:BAAALAAECgIIAwAAAA==.Defoa:BAAALAAECgIIAgAAAA==.Deiwtheevok:BAABLAAECoEVAAMIAAgIQBvEBABNAgAIAAgIQBvEBABNAgAJAAEInQM8NwA2AAAAAA==.Demonvoider:BAAALAADCgcIEQAAAA==.Destroyerftw:BAAALAADCgcIBwAAAA==.Devilinpink:BAAALAADCggIDgAAAA==.',Dh='Dharkh:BAAALAAECggICAAAAA==.',Di='Diaval:BAAALAAECgYIDgAAAA==.Diggit:BAAALAAECgIIAgAAAA==.Discgolfer:BAAALAADCgUIBQAAAA==.',Do='Dodo:BAAALAADCggIFQAAAA==.Dolfik:BAAALAAECgUIBgAAAA==.Dombagrim:BAAALAAECgMIAwAAAA==.Doubledrop:BAAALAADCgcIDgAAAA==.',Dr='Dracu:BAAALAADCgQIBAABLAAECgMIBwAGAAAAAA==.Dragonmann:BAAALAADCgcIBwAAAA==.Dragónnitte:BAAALAADCgYIBgAAAA==.Drahnir:BAAALAAECgIIAwAAAA==.Dravenmain:BAAALAAECgcIDAAAAA==.Draxigal:BAAALAAECgMIBAAAAA==.Drceax:BAAALAAECgQIBAAAAA==.Drdax:BAAALAAECgYIDQAAAA==.Drenno:BAABLAAECoEWAAMKAAgI3yFeBADHAgAKAAgI3yFeBADHAgALAAEIZholRwBMAAAAAA==.Driztd:BAAALAAECgEIAgAAAA==.Dropje:BAAALAAECgYIBAAAAA==.Druidlook:BAAALAAECgQIBwAAAA==.Drumse:BAAALAADCggIEwAAAA==.Dréw:BAAALAADCgMIAwAAAA==.',Du='Dudeao:BAAALAAECgQIBQAAAA==.',Dw='Dwinchester:BAAALAADCgIIAgABLAAECgYICAAGAAAAAA==.Dwomsamdi:BAAALAAECgQIBQAAAA==.',['Dä']='Däklul:BAAALAAECggIFAAAAQ==.',Ec='Eclipse:BAAALAAECgYIDwAAAA==.',Ed='Edgemasterr:BAAALAAECgYIBgAAAA==.',Ei='Eiríksdóttir:BAAALAADCggICAAAAA==.',El='Elemona:BAAALAAECgYIBwAAAA==.Elnadris:BAAALAAECgQICAAAAA==.Elvadia:BAAALAAECgQICAAAAA==.',Em='Emulow:BAAALAAECgEIAQAAAA==.',En='Enterrorist:BAAALAAECgUICgAAAA==.',Er='Ereski:BAAALAAECgcIDgAAAA==.',Es='Esda:BAAALAADCgIIAgAAAA==.',Et='Eternall:BAAALAADCggIDwAAAA==.Etostra:BAAALAADCgEIAQAAAA==.',Ex='Exp:BAAALAAECgQIBgAAAA==.Exya:BAAALAAECgMIAwAAAA==.',Fa='Falantys:BAABLAAECoEUAAIMAAgI7xqUBQBtAgAMAAgI7xqUBQBtAgAAAA==.Farswarlock:BAAALAADCgYIBgAAAA==.Fascinujici:BAAALAADCgcIBwAAAA==.Fassarias:BAAALAAECgIIBAAAAA==.Fazurion:BAAALAADCggIEQAAAA==.',Fe='Fellaw:BAAALAAECgQIBwAAAA==.Feloora:BAAALAAECgIIAgAAAA==.',Fl='Fladorr:BAAALAAECgMIAwAAAA==.Floofmonster:BAAALAAECgIIAgAAAA==.',Fo='Forcefulpoke:BAAALAAECgMIAwABLAAECgYICQAGAAAAAA==.Fozziestitch:BAAALAAECgMIBQAAAA==.',Fr='Frazes:BAACLAAFFIEFAAIIAAMIqh07AQAmAQAIAAMIqh07AQAmAQAsAAQKgRgAAggACAibITUBAAEDAAgACAibITUBAAEDAAAA.Frostspree:BAAALAADCgYIBgAAAA==.Frozensiñ:BAAALAAECgEIAQABLAAECggIFQABAB8XAA==.Fríeren:BAAALAAECgYIDAABLAAECgcIEwAGAAAAAA==.',Fu='Furvus:BAAALAADCggIFgABLAAECgMIBwAGAAAAAA==.',['Fö']='Försenad:BAAALAADCgcIDQAAAA==.',Ga='Galaireal:BAAALAAECgMIBQAAAA==.Galbutronix:BAAALAAECgEIAQAAAA==.Galifraej:BAAALAADCggICAAAAA==.Gardenwood:BAAALAADCggIFwAAAA==.Gas:BAAALAAECgcIEwAAAA==.',Ge='Genetica:BAAALAAECgQIBgAAAA==.Gengar:BAAALAADCggICAAAAA==.Geralten:BAAALAAECgMIBAAAAA==.Gerrome:BAAALAADCggICAABLAAECgIIAwAGAAAAAA==.Gerzhul:BAAALAAECggIDwAAAA==.',Gh='Ghaka:BAAALAAECgEIAQAAAA==.',Gi='Gimblood:BAAALAAECgEIAQAAAA==.',Gn='Gnoku:BAAALAADCgYIBgAAAA==.',Go='Gob:BAAALAAECgcIDAAAAA==.',Gr='Grainknight:BAAALAAECgMIBQAAAA==.Grawp:BAAALAAECgYICQAAAA==.Graydevil:BAAALAAECgMIBAAAAA==.Greenhide:BAAALAAECgIIAgAAAA==.Grellis:BAAALAAECgUIBQAAAA==.Grendiz:BAAALAAECgUIBQAAAA==.Greshar:BAAALAADCgcIDgAAAA==.Grimnir:BAAALAAECgEIAQAAAA==.',Gu='Guapa:BAAALAAECgEIAQAAAA==.',Ha='Haazzard:BAAALAAECgMIBwAAAA==.Handsomebob:BAAALAADCgcIBwAAAA==.Hanuka:BAAALAADCggIEQAAAA==.',He='Healthy:BAAALAADCgEIAQAAAA==.Heavenofgods:BAAALAADCggICAAAAA==.Hemlock:BAAALAAECgMIAwAAAA==.Herlindd:BAAALAAECgEIAQAAAA==.Herskster:BAAALAAECgMIAwAAAA==.',Hi='Hiewaa:BAAALAADCgcIBwAAAA==.Hippolyta:BAAALAAECgYICAAAAA==.Hizzy:BAAALAADCgUIBQABLAAECgMIBwAGAAAAAA==.Hizzyy:BAAALAADCgUIBQABLAAECgMIBwAGAAAAAA==.',Ho='Hoolk:BAAALAAECgQICAAAAA==.',Hu='Humanshrek:BAAALAAECgYIDAAAAA==.Humperdoo:BAAALAADCgUIBQAAAA==.',Hy='Hydura:BAAALAADCgEIAQAAAA==.Hyggetøs:BAAALAADCggICAAAAA==.',['Hø']='Høneycomb:BAAALAADCgIIAgAAAA==.',Il='Iloule:BAAALAADCgYIBwAAAA==.',In='Ingmr:BAAALAAECgQICAAAAA==.',Is='Ishva:BAAALAADCggIEwABLAAECgcIEwAGAAAAAA==.Ishvalan:BAAALAAECgcIEwAAAA==.Ishvá:BAAALAAECgMIBQABLAAECgcIEwAGAAAAAA==.',It='Ithano:BAAALAADCggICAAAAA==.Ithila:BAAALAADCggIFwAAAA==.',Iu='Iustus:BAAALAADCgcIDgABLAAECgMIBwAGAAAAAA==.',['Iø']='Iøl:BAAALAADCgcIBwABLAAECgYIBgAGAAAAAA==.',Je='Jesborgir:BAABLAAECoEXAAIHAAgIjSJMBAA0AwAHAAgIjSJMBAA0AwAAAA==.Jessiie:BAAALAADCggIGAAAAA==.',Ji='Jinwoo:BAAALAADCggIFQAAAA==.',Jo='Johnykefa:BAAALAAECgEIAQAAAA==.',Ju='Jukolan:BAAALAAECgYIDgAAAA==.Julannou:BAAALAADCggICAAAAA==.',Ka='Kabanos:BAAALAAECgMIBQAAAA==.Kabuch:BAABLAAECoEUAAINAAgIzRsEBACqAgANAAgIzRsEBACqAgAAAA==.Kafroos:BAAALAAECgEIAQAAAA==.Kalidor:BAAALAADCggIFwAAAA==.Kalis:BAAALAAFFAIIAwAAAA==.Kalízan:BAAALAADCgcIBwAAAA==.Katuga:BAAALAADCggIDAAAAA==.',Ke='Kecups:BAAALAAECgMIAwAAAA==.Kerkyra:BAAALAADCggIFwAAAA==.',Kh='Khebohrinn:BAAALAAECgUICwAAAA==.Khokhot:BAAALAADCgUIBQAAAA==.',Ki='Kiiwi:BAAALAADCggIBAAAAA==.Kindlewang:BAAALAADCggICAAAAA==.Kinlav:BAAALAAECgEIAQAAAA==.Kintsugi:BAAALAADCggIFAAAAA==.Kirbie:BAAALAADCggICQAAAA==.Kittenbbq:BAAALAAECgcIEQAAAA==.',Kl='Klavenhoof:BAAALAAECgQICAAAAA==.Klostasa:BAAALAAECgMIAwAAAA==.',Kr='Krackenn:BAAALAADCgcIEAAAAA==.Kristianek:BAAALAAECgIIAgAAAA==.',Ku='Kulkuns:BAAALAAECgEIAQAAAA==.Kungpán:BAAALAAECgUIBgAAAA==.Kurppeli:BAAALAAECgMIAwAAAA==.',La='Lacii:BAAALAADCggICwAAAA==.Langmar:BAAALAADCgcIBwAAAA==.',Le='Leffli:BAAALAAECgcIEwAAAA==.',Li='Liejin:BAAALAAECggIBAAAAA==.Lighthope:BAAALAAECgMIBgAAAA==.Littellady:BAAALAADCgcIDgAAAA==.Littletripod:BAAALAAECgcIEAAAAA==.',Lo='Loftypala:BAAALAAECgYICgAAAA==.Loofty:BAAALAADCgcIBwAAAA==.Losanne:BAAALAAECgcIEgAAAA==.',Lu='Lukaz:BAAALAAECgUICAAAAA==.',Ly='Lynnsdale:BAAALAAECgcIEwAAAA==.Lyxxion:BAAALAADCggIFQAAAA==.',Ma='Madmonkk:BAAALAADCggIGAAAAA==.Mafiona:BAAALAAECgYICAAAAA==.Maguffin:BAAALAADCgYICQABLAAECgMIBwAGAAAAAA==.Malignance:BAAALAAECgYICAAAAA==.Malinovka:BAAALAAECgEIAgAAAA==.Malolin:BAAALAADCgcIBwAAAA==.Mamrot:BAAALAADCgYIDAAAAA==.Maniok:BAAALAAECgYICAAAAA==.Mareritt:BAAALAADCggIDwAAAA==.Martian:BAAALAAECgYIDAAAAA==.Marttina:BAAALAAECgYICQAAAA==.Mathatlath:BAAALAADCgYICgAAAA==.Mattidemoni:BAAALAAECgcIDQAAAA==.',Me='Medacus:BAAALAADCgcIBwAAAA==.Mercl:BAAALAAECgIIAQAAAA==.',Mg='Mgthy:BAAALAADCggIEAAAAA==.',Mi='Michu:BAAALAAECgQIBAAAAA==.Mihao:BAAALAAECgEIAgAAAA==.Minguz:BAAALAADCggIDwAAAA==.Mithril:BAABLAAECoEXAAIOAAgIxRZrEgD6AQAOAAgIxRZrEgD6AQAAAA==.Mizi:BAAALAADCgIIAgAAAA==.',Mo='Mojda:BAAALAADCggIDAAAAA==.Moonbeak:BAAALAADCggICAAAAA==.Mooré:BAAALAAECgYICwAAAA==.Mortier:BAAALAAECgMIBAAAAA==.',Mu='Muattin:BAAALAAECgEIAQAAAA==.Mudrd:BAAALAAECgMIAwAAAA==.Muhsu:BAAALAAECgYICAAAAA==.',Na='Naigh:BAAALAADCgYIBgAAAA==.Nallad:BAAALAADCggIEAAAAA==.Narbosska:BAABLAAECoEUAAIHAAgI+RXVHAAnAgAHAAgI+RXVHAAnAgAAAA==.Naztheros:BAAALAAECgYICAAAAA==.',Ne='Necronym:BAAALAAECgMIBAAAAA==.Neen:BAAALAAECgQICAAAAA==.Neffely:BAAALAADCggIEAAAAA==.Nehonsi:BAAALAAECgcIEwAAAA==.Nelfix:BAAALAAECgYIBgAAAA==.Nemessis:BAAALAADCgMIAwAAAA==.Nerrias:BAAALAAECgQIBAAAAA==.Nexie:BAAALAADCggIFwAAAA==.',Ni='Nicki:BAAALAADCgMIAwAAAA==.Nimfomanka:BAAALAAECgYIDAAAAA==.',No='Noosha:BAAALAADCgcIBwAAAA==.Noriqes:BAAALAADCggICAAAAA==.Nosorozec:BAABLAAECoEXAAIBAAgINyR6AAA3AwABAAgINyR6AAA3AwAAAA==.Nostrils:BAAALAADCgQIBAAAAA==.Notnice:BAAALAAECgMIAwAAAA==.Novakaine:BAAALAADCgcIBwAAAA==.',Ny='Nysina:BAAALAAECgQICAAAAA==.',['Ní']='Níxx:BAAALAAECgUICAAAAA==.',Ob='Obstruktor:BAAALAADCggICAAAAA==.',Oh='Ohjay:BAAALAAECggIEgAAAA==.',Or='Orchanes:BAAALAADCgMIAwAAAA==.Orden:BAAALAAECgMIBQAAAA==.',Os='Ossivondark:BAAALAADCggIEAAAAA==.',Ox='Oxoraidenox:BAAALAAECgQIBwAAAA==.',Oz='Ozak:BAAALAAECgcIDgAAAA==.',Pa='Paladox:BAAALAAECgYICQAAAA==.Palaheals:BAAALAAECgIIAgAAAA==.Palqvadin:BAAALAADCggICAAAAA==.Pasifisti:BAABLAAECoEUAAIFAAcInhobCgAFAgAFAAcInhobCgAFAgAAAA==.',Pi='Pinoderain:BAABLAAECoEUAAIPAAcIuCIVCACSAgAPAAcIuCIVCACSAgAAAA==.Pinorlin:BAAALAAECgEIAQABLAAECgcIFAAPALgiAA==.Piorra:BAAALAADCggICAAAAA==.Pitrci:BAAALAADCgYIBgAAAA==.',Po='Pocieszny:BAAALAAECgYIDAAAAA==.',Pr='Praedator:BAAALAADCggIFgABLAAECgMIBwAGAAAAAA==.Profe:BAAALAAECgYICgAAAA==.Prästt:BAAALAADCggICAABLAAECggIFAAGAAAAAQ==.',Pu='Pulhra:BAAALAAECgQICAAAAA==.Purr:BAAALAAFFAIIAgAAAA==.',['På']='Påven:BAAALAADCggIFwAAAA==.',Qu='Quanxi:BAAALAADCggIDAABLAADCggIGAAGAAAAAA==.Quaranteen:BAAALAAECgYICAAAAA==.Quiwi:BAAALAADCgcIBwAAAA==.',Qv='Qvé:BAAALAAECggIDgAAAA==.',Ra='Raadynll:BAAALAAECgUICAAAAA==.Racek:BAAALAADCggIDwAAAA==.Radnez:BAAALAAECgQIBAABLAAECgQICAAGAAAAAA==.Raelak:BAAALAADCggIEAABLAAECgMIAwAGAAAAAA==.Raenne:BAAALAADCgcIBwAAAA==.Raex:BAAALAADCgYIDAABLAAECgMIAwAGAAAAAA==.Raexll:BAAALAAECgMIAwAAAA==.Raexp:BAAALAADCgUIBgABLAAECgMIAwAGAAAAAA==.Raful:BAAALAADCggIFgABLAAECgEIAQAGAAAAAA==.Rasheen:BAAALAAECgMIBAAAAA==.',Re='Reborn:BAAALAAECgQIBAAAAA==.Reikana:BAAALAAECgEIAQAAAA==.Reli:BAAALAAECgIIBAAAAA==.',Rh='Rhaegál:BAAALAAECgcICAAAAA==.Rhias:BAAALAAECgMIBAAAAA==.Rháenyra:BAAALAAECgEIAQAAAA==.',Ri='Rinnesthra:BAABLAAECoETAAMQAAgIYR5jEgCQAgAQAAgI0h1jEgCQAgARAAUITR6rHABTAQAAAA==.Ritual:BAAALAAECgMIBQAAAA==.',Ro='Robs:BAAALAAECgMIBAAAAA==.Rogren:BAAALAADCgcIDgAAAA==.Romadima:BAAALAAECgYICgAAAA==.Rooibaard:BAAALAADCggIDgAAAA==.Rostan:BAAALAAECgcIEwAAAA==.Roste:BAAALAADCggICAAAAA==.Rottenz:BAAALAADCgcIBwAAAA==.Rowanne:BAAALAADCgcIDgAAAA==.',Ru='Rubencz:BAAALAADCggICAAAAA==.Rukarn:BAAALAAECgMIBgAAAA==.',Rx='Rxqll:BAAALAADCggIDAABLAAECgMIAwAGAAAAAA==.',Ry='Rychlokvaska:BAAALAADCgcIBwAAAA==.',['Rë']='Rëliq:BAAALAADCggICAAAAA==.',Sa='Saeedka:BAAALAAECggICAAAAA==.Sagiri:BAAALAADCggIEAAAAA==.Sakix:BAAALAAECgMIBAAAAA==.Saltybtw:BAAALAADCgYIBgAAAA==.Samira:BAAALAADCgcIDQAAAA==.Sapphirre:BAAALAAECgEIAQAAAA==.Sashaana:BAAALAADCggIDAAAAA==.',Sc='Scarrychop:BAAALAADCgcICQAAAA==.Sciorro:BAAALAADCggICAABLAAECgcIEwAGAAAAAA==.Scoda:BAAALAAECgMIBQAAAA==.Scottishlass:BAAALAADCgEIAQAAAA==.Scripto:BAAALAADCgYIBgAAAA==.Scárlett:BAAALAADCgcIBwAAAA==.',Se='Seb:BAAALAAECgMIBgAAAA==.Sectum:BAAALAADCggIDwAAAA==.Seeknstrike:BAAALAAECgYICwAAAA==.Segnis:BAAALAADCggIDwABLAAECgMIBwAGAAAAAA==.Sehra:BAAALAAECgQICAAAAA==.',Sh='Shadár:BAAALAAECgIIAwAAAA==.Shamaz:BAAALAADCgcIBwAAAA==.Shambo:BAAALAAECgYICAAAAA==.Shetarra:BAAALAADCgcIHwAAAA==.Shilaleya:BAAALAAECgYIDAAAAA==.Shiloh:BAAALAADCgcIDQAAAA==.',Si='Sibuli:BAABLAAECoEUAAMSAAcIcRvhEQBRAgASAAcIcRvhEQBRAgABAAIIcRVKEgBuAAAAAA==.',Sk='Skandaali:BAAALAAECgcIBwAAAA==.',Sl='Slammedaddy:BAAALAADCggICAABLAAECgcIDAAGAAAAAA==.Slejonk:BAAALAAECgYICgAAAA==.',Sm='Smasharito:BAAALAAECgYICAAAAA==.Smokepala:BAAALAAECgIIAgAAAA==.Smrksa:BAAALAADCgYIBgAAAA==.',Sn='Sneck:BAAALAADCggICAAAAA==.Snowglow:BAAALAAECgQIBgAAAA==.',So='Soccebomb:BAAALAADCggICAAAAA==.Sorisio:BAAALAADCgYICgAAAA==.',Sp='Sparnhawk:BAABLAAECoEXAAICAAgIDyMTJgDsAQACAAgIDyMTJgDsAQAAAA==.Spartukas:BAAALAADCgYICwAAAA==.Spherical:BAAALAADCggIGAAAAQ==.',Sq='Squidmarx:BAAALAADCggIDwAAAA==.',St='Starbreezer:BAAALAADCgUIBQAAAA==.Stellari:BAAALAAECgYIDwAAAA==.Steviwonder:BAAALAAECgMIAwAAAA==.Strains:BAAALAADCggIFwAAAA==.Straken:BAAALAAECgQIBAAAAA==.Stévé:BAAALAAECgQIBgAAAA==.',Su='Sugarmama:BAAALAAECgYIDAAAAA==.Supreme:BAAALAADCggICAAAAA==.Suriel:BAAALAAECgIIAwAAAA==.',Sy='Syncremental:BAAALAADCgIIAgAAAA==.',Ta='Tatters:BAAALAADCggIEAAAAA==.Taurenil:BAAALAADCgcIEAAAAA==.',Te='Telekomeriss:BAAALAADCggICQAAAA==.Telewarrior:BAAALAADCgIIAgAAAA==.Teoli:BAAALAAECgMIAwAAAA==.Terrer:BAAALAADCgUIBQAAAA==.Terroristeen:BAAALAADCgcIBwAAAA==.',Th='Theramas:BAAALAAECgMIAwAAAA==.Thodeus:BAAALAAECgEIAQAAAA==.Thompie:BAAALAADCgcIBwAAAA==.Thornbrew:BAAALAAECgYICQAAAA==.Thornuwiell:BAAALAADCgcIBwAAAA==.Thror:BAAALAADCggIFwAAAA==.Thunderstone:BAAALAADCggIFwAAAA==.',Ti='Timurt:BAAALAAECgQICAAAAA==.Tirvu:BAABLAAECoEUAAIPAAgIHRqMCwBnAgAPAAgIHRqMCwBnAgAAAA==.',To='Tolppajuntta:BAAALAAECgEIAQAAAA==.Toxow:BAAALAAECgYIDgAAAA==.',Tr='Trixan:BAAALAADCggIFwAAAA==.Trollwar:BAAALAADCgYICgAAAA==.Trulscirvis:BAAALAAECgIIAwAAAA==.',Tu='Tulipkka:BAAALAADCggICwAAAA==.',Tw='Twylia:BAAALAAECgEIAQAAAA==.',Ty='Tyila:BAAALAADCgcIBwAAAA==.Tyrhalion:BAAALAADCgcICgAAAA==.',Ul='Ulgrin:BAAALAADCgYIBgAAAA==.Ullzock:BAAALAADCggIDwAAAA==.Ultimecia:BAAALAAECgIIAgAAAA==.',Un='Undiv:BAAALAAECgMIBAAAAA==.',Va='Vargus:BAAALAAECgMIBQAAAA==.',Ve='Venator:BAAALAADCgcICQAAAA==.Veridia:BAAALAAECgEIAQAAAA==.Verran:BAAALAAECgIIAwAAAA==.',Vi='Viivika:BAAALAAECgMIBAAAAA==.Vinkulelu:BAAALAADCgQIBAAAAA==.Vixxina:BAAALAADCggICAAAAA==.Vizion:BAAALAADCggIFwAAAA==.',Vl='Vladthorn:BAAALAAECgIIAgAAAA==.',Vo='Vobla:BAAALAAECgQICAAAAA==.Voidlocker:BAAALAAECgQIBQAAAA==.Voidzeffer:BAAALAADCgYIBgAAAA==.Voodooh:BAAALAAECgcICgAAAA==.Vorgar:BAAALAAECgMIBAAAAA==.',Wa='Walys:BAAALAADCggIFwAAAA==.Waqein:BAAALAAECgMIAwAAAA==.Wardur:BAAALAADCggIDAAAAA==.Warhamerdark:BAABLAAECoEWAAICAAgIICG4CQDtAgACAAgIICG4CQDtAgAAAA==.Warlockii:BAAALAAECgIIAgAAAA==.Warzar:BAAALAADCggIFwAAAA==.Waxy:BAAALAADCgIIAgAAAA==.',We='Werenique:BAAALAAECgYIDwAAAA==.',Wi='Wishsquish:BAAALAAECgQICAAAAA==.',Wo='Wodniczek:BAAALAADCggIFgAAAA==.Wookye:BAAALAAECgYICgAAAA==.',Xa='Xalafeet:BAAALAADCgcICQAAAA==.Xana:BAAALAADCggIDgAAAA==.Xarick:BAAALAADCggIDwAAAA==.Xathol:BAAALAADCggICwAAAA==.',Xe='Xelarate:BAAALAAECgcIDwAAAA==.',Xh='Xhantia:BAAALAADCgMIAwAAAA==.',Xi='Xiuhan:BAAALAAECgMIAwAAAA==.',Yo='Yourk:BAAALAAECgMIAwAAAA==.',Za='Zaera:BAAALAAECgMIAwAAAA==.Zapus:BAAALAAECgMIBAAAAA==.Zarchy:BAAALAADCggICAAAAA==.',Ze='Zerajin:BAAALAAECgQICAAAAA==.',Zi='Zirrix:BAAALAADCgcIBwAAAA==.Zizia:BAAALAAECgYICQAAAA==.',Zo='Zollok:BAAALAAECgMIBAAAAA==.Zorxx:BAAALAADCgcIDQABLAAECgQIBQAGAAAAAA==.',Zw='Zwipess:BAAALAAECgcIEQAAAA==.',Zy='Zyncoolfrost:BAAALAADCgYICwAAAA==.',['Áj']='Ájín:BAAALAAECggICQAAAA==.',['Áu']='Áubrey:BAAALAAECgMIBQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end