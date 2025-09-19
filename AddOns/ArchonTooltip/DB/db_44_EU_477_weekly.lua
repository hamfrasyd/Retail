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
 local lookup = {'DeathKnight-Frost','Unknown-Unknown','DemonHunter-Havoc','Warrior-Protection','Rogue-Assassination','Warlock-Destruction','Warlock-Demonology','DeathKnight-Blood','Rogue-Subtlety','Rogue-Outlaw','DemonHunter-Vengeance','Priest-Holy','Priest-Shadow',}; local provider = {region='EU',realm='Ysera',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Abscheu:BAAALAAECgYIBwAAAA==.',Ae='Aegís:BAAALAADCgEIAQAAAA==.Aetheris:BAAALAADCgcIDgAAAA==.',Aj='Ajicake:BAAALAAECgIIAgAAAA==.',Ak='Akash:BAAALAADCggICAAAAA==.Akinomó:BAAALAADCggIEAAAAA==.Akita:BAAALAADCgcIDgAAAA==.',Al='Alatria:BAAALAADCggIEQAAAA==.Alexlouis:BAAALAAFFAEIAQAAAA==.Almasor:BAAALAAECgMIAwAAAA==.',Am='Ambroo:BAAALAAECgMIAwAAAA==.Amnesia:BAAALAADCggIDwAAAA==.',An='Anthariâ:BAAALAAECgIIAgAAAA==.',Ar='Arcanefluff:BAAALAAECgIIBAAAAA==.Ariodana:BAAALAADCggIDwAAAA==.Artemion:BAAALAADCgMIAwAAAA==.Arzosah:BAAALAADCggIFAAAAA==.',['Aé']='Aésir:BAABLAAECoEVAAIBAAgI8BFVNQCyAQABAAgI8BFVNQCyAQAAAA==.',Ba='Baojin:BAAALAADCggIDwAAAA==.Bargol:BAAALAADCgMIAwAAAA==.Barios:BAAALAADCggICAAAAA==.Barockaa:BAAALAADCggICAAAAA==.Bastit:BAAALAADCggICAAAAA==.',Be='Belatona:BAAALAAECggICAAAAA==.Bery:BAAALAADCggIDwAAAA==.Betheny:BAAALAADCggIDwAAAA==.',Bi='Biegel:BAAALAAECgYICAAAAA==.Bigshortyinc:BAAALAADCgIIAgABLAAECggIEAACAAAAAA==.Bilderrahmen:BAAALAADCggIEAAAAA==.Bilu:BAAALAAECgYIDAAAAA==.Bitburger:BAABLAAECoEcAAIDAAgIPRpGFQBuAgADAAgIPRpGFQBuAgAAAA==.',Bl='Blackdum:BAAALAAECgUICAAAAA==.',Bo='Boesesetwas:BAAALAADCggICAAAAA==.Bohahaiha:BAAALAAECgYIBwAAAA==.Bomb:BAAALAAECgEIAQAAAA==.',Br='Braumeìster:BAAALAADCggIDwABLAAECgYIDAACAAAAAA==.Broeri:BAAALAAECgYICgAAAA==.Bromhilda:BAAALAADCggIDgAAAA==.',Ca='Calipsos:BAAALAADCggICAAAAA==.Calypsos:BAAALAADCgYICwAAAA==.Cat:BAAALAAECgYIBQAAAA==.Catrebellin:BAAALAAECgEIAQAAAA==.Catyy:BAAALAADCgUIBQAAAA==.',Ce='Centurío:BAAALAAECgMIAwAAAA==.',Ch='Chantal:BAAALAADCgYIAgAAAA==.Charlena:BAAALAADCgMIAwAAAA==.Cheyene:BAAALAADCgUICAAAAA==.Chikage:BAAALAADCgcIEAAAAA==.Chimalia:BAAALAAECgEIAQAAAA==.Chonker:BAAALAADCgEIAQAAAA==.Chrissanty:BAAALAADCgYIBgAAAA==.Christroyer:BAAALAADCgcICAAAAA==.Chérub:BAAALAAECgYIBgAAAA==.Chông:BAAALAAECggICAAAAA==.',Ci='Ciphedias:BAAALAADCggICAAAAA==.Cirina:BAABLAAECoEVAAIDAAgIrx5TFgBjAgADAAgIrx5TFgBjAgAAAA==.',Cp='Cptken:BAABLAAECoEVAAIEAAgIjhgEDgDSAQAEAAgIjhgEDgDSAQAAAA==.',Cr='Crystallex:BAAALAADCggIDgAAAA==.',Da='Daemon:BAAALAAFFAEIAQAAAA==.Daeral:BAAALAAECgQIBQAAAA==.',De='Dedmoros:BAAALAAECggIAgAAAA==.',Di='Dizcopriest:BAAALAAECgcIEAAAAA==.',Do='Dorkuraz:BAAALAADCgMIAwAAAA==.',Dr='Draconas:BAAALAAECgMIBAAAAA==.Draina:BAAALAAECgMIAwAAAA==.',Du='Duffslayer:BAAALAAECgcICgAAAA==.Duwubai:BAAALAADCggIDQAAAA==.',['Dè']='Dèény:BAAALAADCgcIBwAAAA==.',['Dö']='Dövelgrönn:BAAALAAECgIIAgAAAA==.',Eg='Eggbertus:BAAALAADCggICAAAAA==.',Ei='Eidena:BAAALAAECgEIAQAAAA==.',El='Elissa:BAAALAADCgYIDAAAAA==.Ellaria:BAAALAADCgYIBwABLAADCgcIBwACAAAAAA==.',Em='Emptyelsa:BAAALAAECgMIAwAAAA==.',Er='Erco:BAAALAADCgYIDAAAAA==.Erito:BAAALAADCgYIDAAAAA==.Erwinovic:BAAALAADCggICQABLAAECgEIAQACAAAAAA==.',Ex='Excelion:BAAALAAECgYIBwAAAA==.',Ey='Eyedevil:BAAALAADCgcIBwAAAA==.',Fa='Faylinn:BAAALAAECgQIBAAAAA==.',Fe='Feelsbad:BAAALAAECgMIBAAAAA==.Fellbürste:BAAALAADCgQIBAAAAA==.Fenr:BAAALAAECgYICgAAAA==.Feuerdrache:BAAALAADCgYIBgAAAA==.',Fi='Fidikus:BAAALAAECgIIAgAAAA==.Firstsoulfly:BAAALAADCgYIAwAAAA==.Firtycino:BAAALAADCggICAAAAA==.',Fl='Flodrood:BAAALAADCgcIBwABLAAECggIFgAFACkbAA==.Flâminis:BAAALAAECgcIDgAAAA==.',Fr='Frieren:BAAALAAECgcIDgAAAA==.',Fu='Fulgurion:BAAALAADCggICAAAAA==.',Fy='Fynnsh:BAAALAAECgcIEgAAAA==.',['Fâ']='Fâbîenne:BAAALAAECgUIBQAAAA==.',['Fü']='Fürstin:BAAALAAECgYICwAAAA==.',Ga='Ganginamonk:BAAALAAECgYIBwAAAA==.Ganondorf:BAAALAAECgIIBQAAAA==.',Gh='Ghõst:BAAALAAECgYIDAAAAA==.',Gi='Gimi:BAAALAADCgUIBQAAAA==.Gimiliei:BAAALAADCgYIBgAAAA==.Ginka:BAAALAADCgUIBQAAAA==.',Gn='Gnomox:BAAALAADCgIIAgAAAA==.',Go='Gonzoô:BAAALAAECgYICQAAAA==.',Gy='Gylford:BAAALAAECgMIBAAAAA==.',['Gú']='Gúldan:BAAALAADCggIDgAAAA==.',Ha='Hardaes:BAAALAAECgQIBAAAAA==.',He='Helal:BAAALAAECggIEAAAAA==.Heleniamavil:BAAALAAECggIDQAAAA==.Hexerhelga:BAAALAADCgIIAgAAAA==.',Hi='Hillx:BAAALAAECgYICAAAAA==.Himl:BAAALAAECgcIDgAAAA==.',Ho='Hornyataro:BAAALAAECgUICAAAAA==.Horster:BAAALAAECgMIAwAAAA==.',Hu='Hunterer:BAAALAADCgUIBQAAAA==.',['Hî']='Hîmmel:BAAALAAECgYICgAAAA==.',Id='Idûna:BAAALAADCggIEwAAAA==.',Il='Ilyks:BAAALAAECggIAQAAAA==.Ilîas:BAAALAAECgYIDwAAAA==.',In='Insanity:BAAALAAECgYIEQAAAA==.',Ir='Irene:BAAALAAECgIIAgAAAA==.',Je='Jellybeef:BAAALAADCgcIDgAAAA==.Jennaortega:BAAALAAECgYIEAAAAA==.',Jo='Jolande:BAAALAAECgYIEAAAAA==.',Jp='Jp:BAAALAADCgcIEQAAAA==.',Ju='Judgelin:BAAALAAECggICAAAAA==.Jurzul:BAAALAAECgYICwAAAA==.',Ka='Kalvari:BAAALAADCggICwAAAA==.Kaorioda:BAAALAADCgcIDQAAAA==.Katryn:BAAALAAECgEIAQAAAA==.Kazejin:BAAALAAECgIIAwAAAA==.',Ke='Keimchen:BAAALAAFFAIIAgAAAA==.Kenshyn:BAAALAAECgIIAwAAAA==.',Kh='Khaleesi:BAAALAADCgcIBwABLAAECgYIDAACAAAAAA==.Khyriel:BAAALAAECggIEAAAAA==.',Ki='Killdot:BAAALAAECgEIAQAAAA==.',Kn='Knallerbse:BAAALAADCggIDQAAAA==.',Ko='Kodamitsuki:BAAALAAECgMIBQAAAA==.Konstantine:BAAALAAECgYIBgAAAA==.',Kr='Kratzbaûm:BAAALAAECgcIDQAAAA==.Krektar:BAAALAADCgYIBgAAAA==.Kresina:BAAALAAECgMIBAAAAA==.Krötchen:BAAALAAECgMIBQAAAA==.',Ku='Kumimirai:BAAALAADCggICAAAAA==.Kunan:BAAALAADCgcIDgAAAA==.Kunsistraza:BAAALAAFFAIIAgAAAA==.',['Ká']='Kárathas:BAAALAAECgYIBwAAAA==.',La='Laru:BAAALAADCggIDAAAAA==.Last:BAAALAADCggIDwAAAA==.',Le='Leelalein:BAABLAAECoEVAAMGAAgIYhOKHQDhAQAGAAgIYhOKHQDhAQAHAAIIUwdESwBoAAAAAA==.Leysun:BAAALAADCgcICgAAAA==.',Li='Lillyann:BAAALAAFFAIIAgAAAQ==.Linchén:BAAALAAECgMIAwAAAA==.Littleaji:BAAALAAECgYIDAAAAA==.Littleleny:BAAALAADCggICAAAAA==.Livory:BAAALAAECgMIAwAAAA==.',Lo='Loofio:BAAALAADCgYIBgABLAADCggICAACAAAAAA==.Loorai:BAAALAADCgYIBQAAAA==.Lootmeplx:BAAALAAFFAIIAgAAAA==.Loveyouxo:BAAALAAECgEIAQAAAA==.',Lu='Lucîfêr:BAAALAADCggIAwABLAAECggIFgAFACkbAA==.Luvos:BAAALAAECgcIDwAAAA==.',Ly='Lycy:BAAALAADCgYIBwAAAA==.Lynes:BAAALAADCgcIBwAAAA==.',['Lô']='Lôthâr:BAAALAADCggICAAAAA==.',['Lü']='Lümmel:BAAALAAECgYIEQAAAA==.',Ma='Maghoros:BAAALAADCgUIBQAAAA==.Magiepower:BAAALAAECgMIAwAAAA==.Magott:BAAALAADCggIDQAAAA==.Malanior:BAAALAAECgYIDwAAAA==.Malrissa:BAAALAADCgcICwAAAA==.Marabella:BAAALAADCggIDgABLAAECgYIEAACAAAAAA==.Maxén:BAAALAADCggIEAAAAA==.Maybel:BAAALAAECgMIBAAAAA==.',Me='Meisterworge:BAABLAAECoEVAAIIAAgIkiRHAwDGAgAIAAgIkiRHAwDGAgAAAA==.Melisan:BAAALAADCggICAAAAA==.Melíssá:BAAALAADCgcIAwAAAA==.Mettmeister:BAABLAAECoEYAAQFAAgIEyN+AwAVAwAFAAgI5SJ+AwAVAwAJAAEIvB7dGQBFAAAKAAEIygIhEAArAAAAAA==.Metusalem:BAAALAADCgcIBwABLAAECgIIBQACAAAAAA==.',Mi='Milèycyrús:BAAALAAECgYIDgABLAAECgYIEAACAAAAAA==.Minzag:BAAALAAECgEIAQABLAAECggIFQAIAJIkAA==.',Mo='Moniq:BAAALAADCgcIBwAAAA==.Moonshine:BAAALAADCgcIDQAAAA==.',My='Myshka:BAAALAADCgIIAgABLAAECgYICgACAAAAAA==.Mythriel:BAAALAAECggIEAAAAA==.',['Mò']='Mòesha:BAAALAAECgEIAQAAAA==.',Na='Nausica:BAAALAAECgMIBAAAAA==.',Ne='Ne:BAAALAAECgEIAQAAAA==.Necronossos:BAAALAADCggIDAAAAA==.Nehara:BAAALAADCgUIAQAAAA==.Nescádiá:BAAALAAECgMIBQAAAA==.',No='Noranor:BAAALAAECgUIDAAAAA==.Nosfera:BAAALAAECgMIBgAAAA==.Noxx:BAAALAADCgUIBQAAAA==.',Ny='Nyhm:BAAALAAECgYICQAAAA==.',['Nè']='Nè:BAAALAAECgYICAAAAA==.',['Nô']='Nôsfératu:BAAALAADCggIFAAAAA==.',Oa='Oathbound:BAAALAADCgYIBwAAAA==.',Op='Opax:BAAALAADCgUIBQAAAA==.',Ot='Otterzunge:BAAALAADCggIDwAAAA==.',Pa='Pandha:BAAALAAECgUICgAAAA==.Parryhôtter:BAAALAADCgcIBwAAAA==.Paterrod:BAAALAADCggIDAAAAA==.',Pe='Perry:BAAALAADCgQIBAAAAA==.',Ph='Phury:BAAALAAECgMIAwAAAA==.Phîra:BAAALAAECgMIBAAAAA==.',Pl='Plastehao:BAAALAAECgYICQAAAA==.',Po='Poong:BAAALAAECgMIAQAAAA==.',Pr='Premiûs:BAAALAAECgEIAQAAAA==.',Pu='Pukk:BAAALAAECgYICgAAAA==.',['Pá']='Pálatedy:BAAALAADCggICAAAAA==.',['Pê']='Pêppermint:BAAALAADCggICAAAAA==.',Ra='Radahan:BAAALAADCgMIAwAAAA==.',Re='Reisender:BAAALAAECgIIAgAAAA==.Rellaron:BAAALAAECgEIAgAAAA==.Rewoo:BAAALAAECgcIEQAAAA==.',Rh='Rhyza:BAAALAADCggICQAAAA==.Rhyzâ:BAAALAAECgYICQAAAA==.',Ri='Riewmeister:BAAALAADCgEIAQAAAA==.Riihmaa:BAAALAAECgMICAAAAA==.',Ro='Rocklee:BAAALAADCgcICgAAAA==.Rockxor:BAAALAAECgYICQAAAA==.Rohr:BAAALAADCgMIAwAAAA==.Rohrschach:BAAALAADCggIEgAAAA==.Roxas:BAAALAAECgYICgAAAA==.',Ry='Ryukotsusei:BAAALAAECgYICgAAAA==.',['Râ']='Râzul:BAAALAAECgMIBAAAAA==.',Sa='Sambö:BAAALAAECgYICAAAAA==.Samhaine:BAAALAADCgEIAQAAAA==.Samisher:BAAALAAFFAIIAgAAAA==.Satsujinlock:BAAALAADCggIEAABLAAECgEIAQACAAAAAA==.Sayena:BAAALAAECgYICgABLAAECgYIDwACAAAAAA==.Saýnara:BAAALAADCggICwAAAA==.',Sc='Schambulance:BAAALAAECgEIAQAAAA==.Schameline:BAAALAAECgMIAwAAAA==.Schamone:BAAALAADCgUIBQAAAA==.Schurke:BAAALAAECgMIBQAAAA==.Scorpina:BAAALAADCgcIBQAAAA==.',Se='Secretmuffin:BAAALAAECgYIBwAAAA==.Seleen:BAAALAAECggICAAAAA==.Seraphel:BAAALAADCgYIBgAAAA==.Seulgi:BAAALAAECgYICAAAAA==.',Sh='Sheo:BAAALAAECgMIAwAAAA==.Sheuwu:BAAALAADCgUIBQAAAA==.Shortyincl:BAAALAAECgEIAQABLAAECggIEAACAAAAAA==.Shortyincs:BAAALAAECggIEAAAAA==.Shortymonk:BAAALAADCggIEAABLAAECggIEAACAAAAAA==.Shortyxinc:BAAALAADCgcIBwABLAAECggIEAACAAAAAA==.Shrink:BAAALAADCgEIAQABLAAECgEIAQACAAAAAA==.Shárgo:BAAALAAECgYICQAAAA==.Shôtgun:BAAALAADCgYIDgAAAA==.',Sk='Skydevil:BAAALAAECgMIBQAAAA==.',Sn='Sneakerz:BAABLAAECoEWAAMFAAgIKRsyCQCkAgAFAAgIKRsyCQCkAgAJAAIITw2bFQB/AAAAAA==.Sneakyminaj:BAAALAAECgcIEQABLAADCgEIAQACAAAAAA==.',So='Solischia:BAAALAAECgMIAwAAAA==.Soréx:BAAALAADCgcIBwABLAAECgYICAACAAAAAA==.',Sq='Squidi:BAAALAAECgYICgAAAA==.Squishy:BAAALAAECgYIDAAAAA==.',Su='Surân:BAABLAAECoEYAAMLAAgITA8jDgB9AQALAAgIMA8jDgB9AQADAAgIcwFiaQCqAAAAAA==.',Sw='Sweetsnow:BAAALAAECgYICgAAAA==.Sweetsugarly:BAAALAADCggICAAAAA==.',['Sû']='Sûnset:BAAALAADCgcIEAAAAA==.',Ta='Taleschra:BAAALAAECgEIAgAAAA==.Tamî:BAAALAADCggICAAAAA==.Tarith:BAAALAADCgcIBwABLAAECgEIAQACAAAAAA==.Tashì:BAAALAAECgEIAQAAAA==.',Te='Telori:BAAALAADCggICAAAAA==.Tengen:BAAALAADCgcIBwAAAA==.',Th='Thanariøn:BAAALAAECgEIAQAAAA==.Tharea:BAAALAAFFAIIAgAAAA==.Thunderblud:BAAALAADCgcIBwAAAA==.Thymara:BAAALAAECgUICAAAAA==.',Ti='Timbolan:BAAALAAECgYIDwAAAA==.Tipsiz:BAAALAAECgQIBAAAAA==.Tirla:BAAALAAFFAIIAgAAAA==.',Tl='Tlaluc:BAAALAADCgcIBwABLAAECgYIDwACAAAAAA==.',To='Toastydh:BAAALAADCggICAABLAAECggIGAAFABMjAA==.Tobel:BAAALAADCgcIBwAAAA==.Tourok:BAAALAADCggICAAAAA==.',Tr='Trepolon:BAAALAADCgIIAgAAAA==.Trien:BAAALAAFFAIIAgAAAA==.Trêkk:BAAALAAECgcIBwAAAA==.',Ty='Tyrasis:BAAALAAECgEIAQAAAA==.',Va='Val:BAAALAAECgcIDAAAAA==.Valkiere:BAAALAAECgEIAQAAAA==.Vappaner:BAAALAADCgQIBAAAAA==.',Ve='Veela:BAAALAADCgcIAgABLAAECgYIDAACAAAAAA==.Veldryn:BAABLAAECoEVAAIFAAgIzRmXEQAdAgAFAAgIzRmXEQAdAgAAAA==.',Vo='Vooura:BAAALAADCgcIBwAAAA==.Vortun:BAAALAADCggICQAAAA==.',Vu='Vulkhan:BAAALAAECgYICQAAAA==.',['Vé']='Véxx:BAAALAADCggICAABLAAECgYICQACAAAAAA==.',Wa='Warlatm:BAAALAAECgMIAwAAAA==.',Wo='Wohtan:BAAALAAECgMIBAAAAA==.',Xa='Xantoria:BAAALAADCgUICAAAAA==.Xarandria:BAAALAADCggICAAAAA==.Xaviâ:BAAALAADCgcIBwAAAA==.',Xe='Xedille:BAAALAAFFAIIAgAAAA==.Xels:BAAALAAECgYIDAAAAA==.',Xh='Xhanto:BAAALAADCgUICAAAAA==.',Xo='Xotika:BAAALAAECgMIAwABLAAECgQIBAACAAAAAA==.',Xs='Xsnow:BAAALAADCggIDQAAAA==.',Ys='Ysann:BAAALAAECgYICgAAAA==.',Yu='Yunasky:BAAALAADCggIEgAAAA==.Yurgi:BAAALAADCggICAAAAA==.',Yv='Yvriel:BAAALAAECggICAAAAA==.',Za='Zagreus:BAAALAAECgUICgAAAA==.Zandos:BAAALAADCggIDwAAAA==.Zanesama:BAAALAADCgcIBwAAAA==.',Zc='Zcht:BAAALAAFFAIIAgAAAA==.',Ze='Zeatt:BAABLAAECoEXAAMMAAgI5h17CgCUAgAMAAcIsCB7CgCUAgANAAYI2AyQMwATAQAAAA==.Zetheon:BAAALAADCgYIBgABLAAECgUICgACAAAAAA==.Zewii:BAAALAAFFAIIAgAAAA==.',Zu='Zucker:BAAALAADCggIFgAAAA==.',['Âm']='Âmý:BAAALAADCgcIEwAAAA==.',['Âs']='Âszari:BAAALAAECgYICAAAAA==.',['Ðy']='Ðyzy:BAAALAADCggICAAAAA==.',['Ök']='Ökonome:BAAALAAECggICQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end