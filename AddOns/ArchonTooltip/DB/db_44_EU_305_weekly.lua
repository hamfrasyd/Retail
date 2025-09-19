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
 local lookup = {'Unknown-Unknown','Hunter-Marksmanship','Hunter-BeastMastery','Warlock-Affliction','Warlock-Destruction','DeathKnight-Frost','Druid-Balance','Monk-Brewmaster','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','DemonHunter-Havoc','Paladin-Retribution','Priest-Holy','DemonHunter-Vengeance','Paladin-Protection','DeathKnight-Blood','DeathKnight-Unholy',}; local provider = {region='EU',realm='Khadgar',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abcd:BAAALAADCggIFgABLAAECgYIDwABAAAAAA==.',Ac='Acina:BAAALAADCgcIBwAAAA==.',Ai='Aiming:BAABLAAECoEbAAMCAAgIviIiBQAZAwACAAgIviIiBQAZAwADAAMISQpmegCNAAAAAA==.Aithir:BAAALAAECgMIAwAAAA==.',Al='Alanz:BAABLAAECoEUAAMEAAYITxSeDACcAQAEAAYINxCeDACcAQAFAAIIpRVacgCKAAAAAA==.Alfwar:BAAALAAECgYICwAAAA==.Altemo:BAAALAADCggIEgAAAA==.',Am='Amaranthes:BAAALAAECgMIBAAAAA==.Ambrosios:BAABLAAECoEUAAIGAAYIOx78MwAGAgAGAAYIOx78MwAGAgAAAA==.',An='Annanninai:BAAALAADCgYIBgAAAA==.Anodir:BAAALAAECgIIAgAAAA==.Ansuz:BAAALAAECgYIEAAAAA==.Anun:BAABLAAECoEWAAIHAAcI8x26EABwAgAHAAcI8x26EABwAgAAAA==.',Ar='Arkill:BAAALAAECgYICAAAAA==.Arèon:BAAALAAECgYIEQAAAA==.',As='Ashimat:BAAALAADCgcIDgAAAA==.',Ay='Ayasha:BAAALAADCggIEgAAAA==.',Ba='Badgerclaw:BAAALAAECgEIAgAAAA==.Badseed:BAAALAAECgEIAgAAAA==.Balboola:BAAALAADCgQIBAAAAA==.Bandagespex:BAAALAAECgMIBQABLAAECgYIDAABAAAAAA==.Barrbjörn:BAAALAAECgEIAgAAAA==.',Be='Beasttamer:BAAALAAECgUICgAAAA==.Behegor:BAAALAADCggICAAAAA==.Behemight:BAAALAAECgYIEQAAAA==.',Bl='Bladesmith:BAABLAAECoEYAAIIAAcI2BrXDQDcAQAIAAcI2BrXDQDcAQAAAA==.Blames:BAAALAADCgEIAQABLAADCgMIAwABAAAAAA==.Blöodshot:BAAALAADCgEIAQAAAA==.',Bo='Boldi:BAAALAADCgEIAQAAAA==.Bombastic:BAAALAADCggIEwAAAA==.Bomshakalaka:BAAALAAECgEIAgAAAA==.Booss:BAAALAADCggIEAAAAA==.',Br='Bravepeter:BAAALAADCgcIFAAAAA==.Brokevoker:BAABLAAECoEdAAMJAAgI0BqLBgBZAgAJAAgI0BqLBgBZAgAKAAYImRAsJQBoAQAAAA==.Bruv:BAAALAADCggICQABLAADCggIEAABAAAAAQ==.',Bu='Bullmeister:BAABLAAECoEaAAILAAgIrhltDABNAgALAAgIrhltDABNAgAAAA==.Bulverik:BAAALAAECgYIEQAAAA==.',['Bå']='Bågsträngen:BAAALAAECgUICgAAAA==.',Ch='Chaosbôlt:BAAALAAECggICwAAAA==.',Cl='Clangeddin:BAAALAADCgYIBgAAAA==.Classic:BAAALAAECgMIAwAAAA==.Classiker:BAAALAAECgIIAgAAAA==.',Co='Codebreakeer:BAAALAADCgYIBwAAAA==.Cohdii:BAAALAAECgYIDQAAAA==.Cokekiller:BAAALAAECgYIDwAAAA==.Conn:BAAALAAECgQIBAAAAA==.Corax:BAAALAAECggIBwAAAA==.Corgihymn:BAAALAAECgYIDgAAAA==.Corgillidan:BAAALAADCggICAABLAAECgYIDgABAAAAAA==.',Cr='Crepuscule:BAAALAAECgcIEQAAAA==.',Da='Danty:BAAALAAECgEIAQAAAA==.Darkinside:BAAALAAECggICAAAAA==.Darkwa:BAAALAADCggIEQAAAA==.Dastridos:BAAALAADCgcIBwABLAAECgUICAABAAAAAA==.',De='Deadcenter:BAAALAAECggIEwAAAA==.Dementhea:BAAALAADCggICAAAAA==.Demonicess:BAAALAADCggIHAAAAA==.Demonlorrd:BAABLAAECoEWAAIMAAcIABxHKAAvAgAMAAcIABxHKAAvAgAAAA==.',Do='Doflamíngo:BAAALAAECgUICQAAAA==.Dotdamien:BAAALAADCggIGwAAAA==.Dottipotti:BAAALAADCggIFAAAAA==.',Dr='Draenerion:BAAALAAECgEIAQAAAA==.Drargonia:BAAALAADCgQIBwAAAA==.',Ea='Earthward:BAAALAAECggIEgAAAA==.Eatmenot:BAAALAADCgYIBAAAAA==.',Eg='Eggnoodle:BAAALAADCgIIAQAAAA==.',El='Elém:BAAALAAECgEIAgAAAA==.',Em='Emberhead:BAAALAADCgUIBQAAAA==.',Er='Erocc:BAABLAAECoEXAAIJAAgIcguHDwCEAQAJAAgIcguHDwCEAQAAAA==.Erth:BAAALAAECgIIAgABLAADCggIEAABAAAAAQ==.',Ev='Evoks:BAAALAADCgcIBwAAAA==.',Fa='Fattyelf:BAAALAADCggIEAAAAA==.',Fe='Feldemon:BAAALAAECgYIBgAAAA==.',Fo='Foamix:BAAALAAECgYICwAAAA==.Footsize:BAAALAAECggIBgAAAA==.',Fr='Frankzapper:BAAALAAECgYIDAAAAA==.Frozenheart:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',Ga='Ganon:BAAALAAECgUICAAAAA==.',Gi='Gillton:BAAALAADCgUIBQAAAA==.',Gn='Gneisshammer:BAAALAAECgYIBgAAAA==.',Go='Gonville:BAAALAADCgEIAQAAAA==.Goodshag:BAABLAAECoEaAAINAAgIJxxaGACfAgANAAgIJxxaGACfAgAAAA==.Gorthek:BAAALAAECgYIBwAAAA==.',Gr='Grippér:BAAALAADCgYIBgAAAA==.Grønnjævel:BAAALAAECggICAAAAA==.',Ha='Haywyre:BAAALAAECgEIAQAAAA==.Hazeygrom:BAAALAAECgYICgAAAA==.',He='Hektelion:BAAALAAECggICAAAAA==.Hellsz:BAAALAADCgMIAwABLAAECgcIFwAOABUbAA==.Helvexc:BAABLAAFFIEGAAIGAAIIcyJNCwDEAAAGAAIIcyJNCwDEAAAAAA==.',Hi='Hirviowner:BAAALAADCggIDwAAAA==.',Ho='Holyomen:BAAALAADCgcIBwABLAAECgcIGAAIANgaAA==.',Hu='Hunterofdoom:BAAALAADCggIGwAAAA==.',['Hé']='Hép:BAAALAAECgYIDwAAAA==.',Il='Ilicadaver:BAAALAAECgUICgAAAA==.',In='Inciter:BAAALAAECgYIDgAAAA==.Inyourmind:BAABLAAECoEUAAIFAAgIVBY3HgA8AgAFAAgIVBY3HgA8AgAAAA==.',Ir='Irisis:BAAALAAECgYIDwAAAA==.Irídi:BAAALAADCgMIAwAAAA==.',It='Itseperkele:BAAALAADCgcICQAAAA==.',Ka='Kabell:BAAALAAECgMIBgAAAA==.Kail:BAAALAADCggIDgAAAA==.Kamu:BAAALAAECgEIAQAAAA==.Karlovacko:BAAALAADCgMIAwAAAA==.Kaz:BAAALAAECgEIAgAAAA==.',Ke='Kevin:BAAALAADCgcIBwAAAA==.',Ki='Kigamor:BAAALAAECgYIDgAAAA==.Kitagawa:BAAALAAECgIIBQAAAA==.',Ko='Konàn:BAAALAAECgMIAwAAAA==.Koydai:BAAALAADCggICAAAAA==.',Kr='Kraziekenan:BAAALAAECgYICAAAAA==.Krygem:BAAALAAECgEIAQAAAA==.',Ku='Kuzco:BAAALAAECgYIDgAAAA==.',['Kä']='Kääriäinen:BAAALAAECgYIEQAAAA==.',Le='Legollas:BAAALAAECgIIAgAAAA==.',Li='Liandriala:BAAALAAECgYIDgAAAA==.Lighier:BAAALAAECggICAAAAA==.Lilistrasza:BAAALAAECgIIAgAAAA==.Linwee:BAAALAADCgcIEAAAAA==.',Lm='Lm:BAAALAADCgcIEgAAAA==.',Lo='Lolxd:BAAALAADCggIEAABLAAECgYIDwABAAAAAA==.Longdonngg:BAAALAAECgYICgAAAA==.Lorgaalis:BAAALAAECgYIDgAAAA==.',Lu='Lutyo:BAAALAADCggICQAAAA==.',Ma='Macarenna:BAAALAADCgYIBgAAAA==.Magliana:BAAALAADCgcIDQAAAA==.Mahtilisko:BAAALAADCgcIBwAAAA==.Margo:BAAALAAECgIIBAAAAA==.Matthek:BAAALAADCgIIAgAAAA==.',Mc='Mcboogerbals:BAAALAADCggIDQAAAA==.',Me='Meekadin:BAAALAADCggICAAAAA==.Menarath:BAAALAADCggICgAAAA==.Mercryn:BAAALAADCgMIAwAAAA==.Metallíca:BAAALAADCgcIBwAAAA==.',Mi='Minatriel:BAAALAAECgMIAwAAAA==.Misty:BAAALAAECgMIBwAAAA==.Mizanthien:BAABLAAECoEWAAIPAAcI9BcGDwDKAQAPAAcI9BcGDwDKAQAAAA==.',Mo='Mony:BAAALAADCggIEAAAAA==.Morrior:BAAALAAECgMIBwAAAA==.',Mu='Murdåck:BAAALAADCggIDgAAAA==.',My='Mydarling:BAAALAADCggICAAAAA==.Mylonniy:BAAALAAECgYIBwAAAA==.Mystogan:BAAALAADCgYIBgAAAA==.',['Mí']='Mík:BAAALAAECgYIDAAAAA==.',Na='Nachtmerrie:BAAALAAECgYIDAAAAA==.Naroses:BAAALAADCgcIBwAAAA==.',Ne='Nevermore:BAAALAAECgMICAAAAA==.',Nh='Nhash:BAAALAAECggIDgAAAA==.',Ni='Nightfader:BAABLAAECoEXAAIDAAcIJh3/GwBKAgADAAcIJh3/GwBKAgAAAA==.',Ny='Nyckene:BAAALAAECgQIBwAAAA==.Nyxara:BAAALAAECgQICQAAAA==.',Od='Ody:BAAALAAECgYIDQAAAA==.',Ok='Ok:BAAALAADCggIEgAAAA==.',Ol='Oldboy:BAAALAAECgYICgAAAA==.Olum:BAAALAADCgcIBwAAAA==.',Or='Orumi:BAAALAAECgMIAwAAAA==.',Pa='Painsha:BAAALAAECgYICAAAAA==.Panda:BAAALAAECgUICgAAAA==.Panser:BAAALAAECgYIBgAAAA==.',Pe='Pearlfinder:BAAALAADCgcICAAAAA==.Pezpix:BAAALAAECgYIDAABLAAECgYIDwABAAAAAA==.',Pi='Piciu:BAAALAADCggICAAAAA==.Pilgara:BAAALAADCgEIAQAAAA==.',Po='Popcat:BAAALAAFFAMIAwAAAA==.Portemonnaie:BAAALAADCgUICgAAAA==.Postmalorn:BAAALAADCggICAAAAA==.',Pp='Pphole:BAAALAADCgcIBwAAAA==.',Pr='Pravús:BAAALAAECgYIEgAAAA==.',Pu='Puffi:BAAALAAECgYIDAAAAA==.',Py='Pyra:BAAALAADCgcIBwAAAA==.',Qa='Qatari:BAAALAADCggIFQAAAA==.Qatarie:BAAALAADCggIGQAAAA==.',Qt='Qtri:BAAALAADCggIEwAAAA==.Qtrvip:BAAALAADCggIFAAAAA==.',Ra='Ragedcorpse:BAAALAAECgMIAwAAAA==.Rayce:BAECLAAFFIEGAAIFAAMIBRp+BwAOAQAFAAMIBRp+BwAOAQAsAAQKgR0AAgUACAgKI+MJAP0CAAUACAgKI+MJAP0CAAAA.Raynn:BAAALAAECgcIEQAAAA==.',Re='Relistrix:BAAALAADCgcIBwAAAA==.',Rh='Rhyhad:BAAALAAECgUICAAAAA==.',Ro='Rollyboi:BAAALAADCgcIBwABLAAECgYIDwABAAAAAA==.Rostislav:BAAALAADCggIFQAAAA==.',['Rö']='Röß:BAAALAAECgEIAQAAAA==.',Sa='Saffiron:BAAALAAECgIIAgAAAA==.Salubris:BAAALAADCgcIDwAAAA==.Samtyler:BAAALAAECgIIAgAAAA==.Sandblood:BAAALAADCgEIAQAAAA==.Saximus:BAAALAADCgcIBwAAAA==.',Sc='Scarymonstrs:BAAALAAECgYICgAAAA==.Scuz:BAAALAADCgcICwAAAA==.Scuzz:BAAALAAECgEIAQAAAA==.',Sh='Shahd:BAAALAADCggIDwAAAA==.Shamish:BAAALAAECgIIAgAAAA==.Shamonk:BAAALAADCgMIAwABLAAECgIIAgABAAAAAA==.Shermán:BAAALAAECgIIAgAAAA==.Shoq:BAAALAADCggIDAAAAA==.Shämán:BAAALAAECgMIAwAAAA==.',Sl='Sláshdk:BAAALAADCgcIBwAAAA==.',Sn='Snapjaw:BAAALAAECggIEQAAAA==.',So='Softis:BAAALAAECgQICQAAAA==.Soulscarr:BAAALAAECgUIAwAAAA==.',Sp='Spacegoat:BAAALAAECgIIAgAAAA==.Spidéy:BAAALAAECgIIAgAAAA==.Spiritu:BAAALAADCgMIBAABLAADCggIDgABAAAAAA==.Spriggz:BAAALAAECgYIDAAAAA==.',St='Stabbybobby:BAAALAADCggIEwAAAA==.Starcalling:BAAALAAECggIDQAAAA==.Starguide:BAAALAADCgYICQABLAAECggIDQABAAAAAA==.Stephywefy:BAAALAAECgUIBgAAAA==.Stinkyboi:BAAALAADCggIEAABLAAECgYIDwABAAAAAA==.Strikster:BAAALAAECgEIAQAAAA==.',Su='Sunrose:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.Superdps:BAAALAAECgYIDwAAAA==.',Sv='Svea:BAAALAAECgEIAgAAAA==.',Sw='Sweasta:BAAALAAECgYICQAAAA==.',Sy='Synapse:BAAALAADCgcIBwAAAA==.',Ta='Talizha:BAAALAAECgYIDwAAAA==.Talys:BAAALAAECgYICAAAAA==.Tankyskills:BAAALAADCggIEAABLAAECgYIDwABAAAAAA==.Tarecgosa:BAABLAAECoEZAAMQAAgIoRuKDgDvAQAQAAcI/hyKDgDvAQANAAEIFRJWvABJAAAAAA==.Tarithel:BAAALAAECgUIBQAAAA==.Taurine:BAAALAADCggIEgAAAA==.',Te='Terosh:BAAALAADCgQIBAAAAA==.',Th='Theldrasol:BAAALAADCggIDQAAAA==.Theonewizard:BAAALAAECgYIBwAAAA==.Throe:BAAALAAECggICQAAAA==.Thánatus:BAAALAAECgMIAwAAAA==.Thällasillor:BAAALAAECgMIBQAAAA==.',Ti='Timmee:BAAALAAECgYIDwAAAA==.Tirinee:BAAALAADCggIFAAAAA==.',To='Totemew:BAAALAADCggIDwABLAAECgYICgABAAAAAA==.',Tp='Tpyo:BAAALAAECgYICwAAAA==.',Tr='Trinky:BAAALAADCgcIBwAAAA==.',Ut='Utaab:BAAALAADCgIIAgAAAA==.',Uu='Uunimaestro:BAAALAADCggIDgAAAA==.',Va='Valethria:BAAALAAECgcIDQAAAA==.Vanthryn:BAAALAADCggIDgAAAA==.',Ve='Veloarc:BAAALAAECgYIDAAAAA==.Vermithrax:BAAALAAECgYIEgAAAA==.Vesipuhveli:BAAALAAECgYICQAAAA==.',Vr='Vrath:BAAALAAECgYIBgAAAA==.',Vu='Vulk:BAAALAAECgYIEQAAAA==.Vulksp:BAAALAADCggICAAAAA==.Vulkswagen:BAAALAADCgUIBQAAAA==.',Vy='Vyrith:BAAALAAECgYIEQAAAA==.',Wa='Waiteyak:BAAALAADCgcICgAAAA==.Wals:BAAALAAECgIIAgAAAA==.Warbringer:BAAALAADCgcIDgAAAA==.Waroftunder:BAAALAADCgYICwAAAA==.Warrirors:BAAALAAECgYIDwAAAA==.Wauweltesjch:BAAALAADCggICgAAAA==.',We='Wealing:BAAALAAECgcIEQAAAA==.Weurrior:BAAALAADCgYICAAAAA==.',['Wô']='Wôlfsbane:BAAALAAECggIDAAAAA==.',Xu='Xuanzong:BAAALAADCgMIAwABLAAECgQICQABAAAAAA==.',['Xé']='Xénophon:BAAALAADCgMIBQAAAA==.',Ye='Yeshua:BAABLAAECoEXAAQRAAgIUwoJEgBqAQARAAgI5gkJEgBqAQAGAAMI+AThqACGAAASAAEI8gGQQQAzAAAAAA==.',Yp='Yperbarrage:BAAALAAECgYIBgABLAAECgcIGAAIANgaAA==.',Ze='Zeldora:BAAALAAECgMIBwAAAA==.Zenon:BAAALAAECgUIBwAAAA==.Zeroblood:BAAALAAECgYIBgAAAA==.Zeús:BAABLAAECoEXAAIOAAcIFRtgGAA5AgAOAAcIFRtgGAA5AgAAAA==.',Zs='Zsana:BAAALAAECgMIBwAAAA==.',['Âk']='Âkmunrâ:BAAALAAECgQICQAAAA==.',['Îb']='Îbitê:BAAALAAECgYIBgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end