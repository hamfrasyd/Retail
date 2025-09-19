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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-BeastMastery','Priest-Holy','DeathKnight-Frost','Paladin-Retribution','Priest-Shadow','Paladin-Protection','Mage-Frost','Warlock-Demonology','Paladin-Holy','DeathKnight-Blood','DeathKnight-Unholy','Warlock-Destruction','Druid-Restoration','Shaman-Restoration','Druid-Balance','DemonHunter-Havoc','Priest-Discipline','Druid-Feral','Druid-Guardian','Warlock-Affliction','Shaman-Elemental','Hunter-Marksmanship',}; local provider = {region='EU',realm='Azuremyst',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aaylara:BAAALAAECgYIDQAAAA==.',Ag='Agatone:BAAALAAECgEIAQABLAAECgcIDQABAAAAAA==.Aggromuffin:BAAALAAECggIBwAAAA==.',Ak='Akenno:BAAALAADCggIDgAAAA==.',Al='Alakezan:BAABLAAECoEWAAICAAgI7B5ADwDnAgACAAgI7B5ADwDnAgAAAA==.Alarica:BAAALAADCggICAAAAA==.Alira:BAAALAADCgYIBgAAAA==.Aliyan:BAAALAADCgIIAgAAAA==.Alizra:BAAALAAECgMIAwAAAA==.Allvarus:BAAALAADCgUIBwAAAA==.',Am='Amarie:BAAALAAECgMIBAAAAA==.',An='Annao:BAAALAADCgcIFwAAAA==.',Ar='Arcanyx:BAAALAADCggICAAAAA==.Aredhel:BAABLAAECoEcAAIDAAgItx0XEwCXAgADAAgItx0XEwCXAgAAAA==.',As='Asmodan:BAAALAAECgMIAwAAAA==.Astrafox:BAAALAADCgcIBwAAAA==.',At='Ateist:BAABLAAECoEYAAIEAAgI8xvtDACmAgAEAAgI8xvtDACmAgAAAA==.',Av='Avelline:BAABLAAECoEXAAIDAAcInBeRJQAKAgADAAcInBeRJQAKAgAAAA==.',Aw='Awu:BAAALAAECgUIBQAAAA==.',Ax='Axl:BAAALAADCggICAAAAA==.',Az='Azhag:BAABLAAECoEUAAIFAAcI0hIXRwC9AQAFAAcI0hIXRwC9AQAAAA==.',Ba='Bababooey:BAAALAAECgEIAQAAAA==.Baelim:BAAALAADCggIFQAAAA==.Baonty:BAAALAADCggICAAAAA==.Barrom:BAAALAADCggIDwAAAA==.Basadin:BAAALAADCgYIBgAAAA==.Basseele:BAAALAAECgUIBgAAAA==.',Be='Bearcareful:BAAALAAECgMIBwAAAA==.Beldri:BAAALAAECgYIBwAAAA==.Bellzar:BAAALAADCgcIBwABLAAECgcIFQAGAOwOAA==.Berserk:BAAALAADCggICAAAAA==.',Bi='Bii:BAACLAAFFIEIAAMHAAMIYhaTBQD8AAAHAAMIYhaTBQD8AAAEAAEIkAA8GwA5AAAsAAQKgRwAAwcABwiKHdAVAFYCAAcABwiKHdAVAFYCAAQABAiYBnNZALwAAAAA.Birta:BAABLAAECoEVAAIHAAcIahKBJwC7AQAHAAcIahKBJwC7AQAAAA==.',Bj='Björnbus:BAAALAADCgIIAgAAAA==.',Bl='Blackthorne:BAAALAAECgQIBgAAAA==.',Bo='Boldy:BAAALAADCgYICgAAAA==.Bonebroken:BAAALAADCggIEAAAAA==.Bonusbuff:BAAALAADCggIDwAAAA==.Borrie:BAAALAADCggICAABLAAECgcIEwABAAAAAA==.Borryblast:BAAALAADCgcIBwABLAAECgcIEwABAAAAAA==.Borrydk:BAAALAAECgIIAgABLAAECgcIEwABAAAAAA==.Bowme:BAAALAAECggICAAAAA==.',Br='Bry:BAAALAADCgcIBwAAAA==.Brítneyfeárs:BAABLAAECoEWAAMHAAgIvh7ECgDcAgAHAAgIvh7ECgDcAgAEAAEIfgX/dAAyAAAAAA==.',Bu='Buffyflewbs:BAAALAAECgMIBAAAAA==.',['Bö']='Böbcat:BAAALAADCgQIBAABLAAECgIIAgABAAAAAA==.',Ca='Calix:BAAALAAECgYIDwAAAA==.Cameow:BAAALAADCgcIDQAAAA==.Castellan:BAAALAADCggICAABLAAECgcIFAAIAAESAA==.Caylum:BAAALAADCgcICwABLAAECgMIBwABAAAAAA==.',Cd='Cdevilfish:BAAALAADCggICAAAAA==.',Ce='Ceesayby:BAAALAADCgUIBQAAAA==.Celimbrimbor:BAAALAAECgUIDAABLAAECggIDwABAAAAAA==.',Ch='Chat:BAAALAADCgMIBAAAAA==.Chemosh:BAABLAAECoEVAAIJAAcIRyCzCQCLAgAJAAcIRyCzCQCLAgAAAA==.',Ci='Cinema:BAAALAAECggIBgAAAA==.',Cl='Clevster:BAABLAAECoEXAAIKAAgI1yXlAABaAwAKAAgI1yXlAABaAwAAAA==.',Co='Cofelock:BAAALAADCggIFQABLAADCggIHQABAAAAAA==.Coffejar:BAAALAADCggIHQAAAA==.',Ct='Cthon:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Cu='Cujek:BAAALAADCgcIBwAAAA==.Currykungen:BAAALAADCgYIBgAAAA==.',['Cå']='Cålypso:BAAALAADCggICAAAAA==.',['Cé']='Célés:BAABLAAECoEWAAILAAgIfiSbAABOAwALAAgIfiSbAABOAwAAAA==.',Da='Daemonic:BAAALAADCggICgAAAA==.Daniellos:BAAALAADCgYIBgAAAA==.Darling:BAABLAAECoEWAAIFAAcIuBJ2SQC1AQAFAAcIuBJ2SQC1AQAAAA==.',De='Demolision:BAABLAAECoEYAAMMAAgI8g8VEACOAQAMAAcIzBEVEACOAQANAAII0wZHOQBfAAAAAA==.Demolisious:BAAALAADCggIDwABLAAECggIGAAMAPIPAA==.Desdemora:BAAALAAECgMIBgAAAA==.Destrospoon:BAABLAAECoEaAAMKAAgIfSC6BADDAgAKAAgIfSC6BADDAgAOAAYIMhTWPACEAQAAAA==.Destructon:BAAALAAECggICAAAAA==.',Dr='Dracena:BAAALAAECgEIAQABLAAECggIGAAMAPIPAA==.Draenier:BAABLAAECoEUAAIIAAcIARKdEwCfAQAIAAcIARKdEwCfAQAAAA==.Dreklay:BAAALAAECgQIBAAAAA==.',Du='Dudububz:BAAALAAECgYIDwAAAA==.Dugguxii:BAABLAAECoEZAAIMAAcIbSS0AwDtAgAMAAcIbSS0AwDtAgAAAA==.Durinaz:BAAALAADCgEIAQAAAA==.',Dw='Dwolk:BAAALAADCggIDwAAAA==.',['Dí']='Dína:BAAALAAECgMIBwAAAA==.',['Dó']='Dóakey:BAAALAADCggICAAAAA==.',Ea='Eallara:BAAALAAFFAEIAQAAAA==.',El='Elelia:BAAALAAECggICAAAAA==.Elriel:BAAALAAECgYIBgAAAA==.Elviass:BAAALAAECggICAAAAA==.Elvisbacon:BAAALAAECgQIAgAAAA==.Elíza:BAABLAAECoEVAAIOAAcIpBZ0JwD5AQAOAAcIpBZ0JwD5AQAAAA==.',Em='Embery:BAAALAAECgUICQAAAA==.',['Eø']='Eøs:BAAALAADCgIIAgAAAA==.',Fa='Faereen:BAAALAADCggICAABLAAFFAQICwAPAIQeAA==.Faerion:BAAALAADCggICAABLAAFFAQICwAPAIQeAA==.Fareon:BAACLAAFFIELAAIPAAQIhB40AQCXAQAPAAQIhB40AQCXAQAsAAQKgRcAAg8ACAiCIvgFANsCAA8ACAiCIvgFANsCAAAA.Farithh:BAAALAADCggIEQAAAA==.Farky:BAAALAADCgIIAgAAAA==.',Fe='Feldari:BAAALAAECgEIAQAAAA==.Felnight:BAAALAAECgYIBgAAAA==.',Fi='Fierynoodle:BAAALAAECgMIAwAAAA==.Fizziepop:BAAALAADCggIGQAAAA==.',Fl='Flatwhite:BAAALAAECgcIBwAAAA==.Flayem:BAAALAADCgcIFwAAAA==.Fliplock:BAAALAADCggICAAAAA==.Flippala:BAAALAAECgcIEgAAAA==.Flipperboy:BAAALAADCggIBwAAAA==.',Fr='Frag:BAAALAADCgcIFgAAAA==.Frankherbert:BAAALAADCgYIBgAAAA==.Frieren:BAAALAAECgIIAgAAAA==.Fristy:BAAALAAECgYIEQAAAA==.',Fu='Fu:BAAALAAECgcIEgAAAA==.Furliss:BAAALAAECggIDgAAAA==.Fuzzywuzzy:BAAALAAECgYIDwAAAA==.',Ga='Gamehuntersh:BAAALAAECgMIAwAAAA==.Gastromix:BAAALAAECgMIBwAAAA==.Gay:BAAALAAECgEIAQAAAA==.',Ge='Gerrardnoone:BAAALAAECgMIBwAAAA==.',Gh='Ghumbie:BAAALAADCggICAAAAA==.',Gi='Gio:BAAALAADCgcIDQAAAA==.',Go='Goodnight:BAAALAADCgMIAwAAAA==.Gorion:BAAALAAECgcICgABLAAECgcIGQAMAG0kAA==.Gork:BAAALAAECgMIBQAAAA==.Goy:BAAALAADCgYICQAAAA==.',Gr='Gracie:BAAALAAECgYIDQAAAA==.Greer:BAAALAADCggIEgAAAA==.Greertv:BAAALAAFFAIIBAAAAA==.',Gu='Gup:BAAALAAFFAIIAgAAAA==.',Ha='Hakuren:BAABLAAECoEVAAIIAAcIHCITBgCjAgAIAAcIHCITBgCjAgAAAA==.Halz:BAAALAAECggIBAAAAA==.Hasturist:BAAALAAECgcICgAAAA==.Havs:BAAALAADCgcICgAAAA==.Havumetted:BAAALAADCggICAABLAAECgcIFwAQAAIfAA==.',Hu='Huehuehhue:BAAALAADCgEIAQAAAA==.Hunterskills:BAAALAADCgcIBwAAAA==.Hunttrex:BAAALAADCgcIDgAAAA==.Hurm:BAAALAAECgMIAwAAAA==.',Ic='Icekizz:BAABLAAECoEVAAIEAAcIMAfWQQA7AQAEAAcIMAfWQQA7AQAAAA==.',Il='Illit:BAAALAAECgEIAQAAAA==.',In='Injured:BAAALAAECggICAAAAA==.Inmedk:BAAALAAFFAEIAQABLAAECggIGAARAHocAA==.Inquis:BAAALAAECgIIAgAAAA==.',Ir='Irydion:BAAALAADCgYICAAAAA==.',Is='Ishtarion:BAAALAADCgcIDwAAAA==.Ismere:BAAALAADCgIIAgABLAAECggICAABAAAAAA==.',Ja='Jaeger:BAAALAAECgMIBQAAAA==.',Jo='Jolia:BAAALAAECgIIAgAAAA==.Joob:BAAALAAECgYIBgAAAA==.Jovanasi:BAAALAADCgcIFQAAAA==.',['Jó']='Jónus:BAAALAADCgYIBgAAAA==.',Ka='Kaelyr:BAABLAAECoEWAAIQAAgIaxr5EwBeAgAQAAgIaxr5EwBeAgAAAA==.Kahmu:BAAALAADCgcIDQAAAA==.Kaidø:BAAALAAECgcIDQAAAA==.Karub:BAAALAAECgYIDQAAAA==.Kasteld:BAABLAAECoEXAAIQAAcInwY5YwACAQAQAAcInwY5YwACAQAAAA==.Katsi:BAAALAAECgMIBAAAAA==.',Ke='Keket:BAAALAAECgYIDgAAAA==.Ketanako:BAAALAAECgcIEgAAAA==.',Ki='Kiro:BAAALAADCgIIAgAAAA==.',Kk='Kkerr:BAAALAADCgcIFgAAAA==.',Kn='Knitingale:BAAALAADCgcIBwAAAA==.',Ko='Kopimage:BAABLAAECoEVAAICAAcIuh2yIABjAgACAAcIuh2yIABjAgABLAAECgcIFQAEADAHAA==.Kopster:BAAALAADCgYIBgABLAAECgcIFQAEADAHAA==.Koradji:BAAALAADCggICQAAAA==.',Kr='Kragok:BAAALAAECgIIBAAAAA==.',Ku='Kuchidh:BAABLAAECoEVAAISAAgISBphHQBzAgASAAgISBphHQBzAgAAAA==.Kuchimage:BAAALAADCgYIBgABLAAECggIFQASAEgaAA==.Kurojii:BAAALAADCgMIAwAAAA==.Kurtie:BAAALAADCgcIBwAAAA==.Kurtié:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.',Ky='Kyutoryuzoro:BAAALAADCgYIBgAAAA==.',La='Lazarion:BAAALAAECgMIBwAAAA==.Lazek:BAAALAAECggICQAAAA==.',Le='Leandra:BAAALAADCggIDwAAAA==.Leijóna:BAABLAAECoEUAAMTAAcIUQcsDABHAQATAAcIUQcsDABHAQAEAAEIhgFyfAAWAAAAAA==.Lerouge:BAAALAADCggIDAAAAA==.Lexå:BAAALAADCgQIBgAAAA==.',Li='Lightbeard:BAAALAADCggICAAAAA==.Lipinizzi:BAAALAAECgIIAgAAAA==.Lirishax:BAAALAADCggICQAAAA==.Lisstwo:BAAALAAECgYIBgABLAAECggIDgABAAAAAA==.',Ll='Llabnalla:BAAALAAECgcIEgAAAA==.',Lo='Loralia:BAAALAAECgQIBAAAAA==.Loudair:BAAALAAECgQIBAAAAA==.Loveslove:BAAALAAECgUIBQAAAA==.',Lu='Lucil:BAAALAAECgYIDAAAAA==.Lucivar:BAAALAAECgYIDAABLAAECggIGAAMAPIPAA==.Lunashade:BAABLAAECoEVAAMUAAcIOhZsDAD3AQAUAAcIOhZsDAD3AQARAAIISgvJWABaAAAAAA==.Luntytbh:BAAALAAFFAIIAgAAAA==.Luná:BAAALAADCggIDwABLAAECgcIFQAOAKQWAA==.',Ly='Lyktan:BAABLAAECoEUAAIVAAYIvxcICAChAQAVAAYIvxcICAChAQAAAA==.',['Lø']='Løvblåser:BAAALAAECggIEAAAAA==.',Ma='Madspedersen:BAAALAADCgYIBgAAAA==.Mageffic:BAABLAAECoEZAAICAAcInxWwOgDVAQACAAcInxWwOgDVAQAAAA==.Magestix:BAAALAADCgcIDQABLAAFFAQICgAMAK4XAA==.Mansk:BAAALAADCggIDwAAAA==.Martonionlux:BAAALAADCgcIDwAAAA==.Maëllys:BAAALAAECggIDwAAAA==.Maÿhem:BAAALAADCgcIBwAAAA==.',Me='Menibanni:BAAALAAECgMIAwAAAA==.',Mi='Microvlot:BAAALAAECgMIBAAAAA==.Mieka:BAAALAAECgEIAQAAAA==.Mightythrall:BAAALAADCgUIBQAAAA==.',Mj='Mjos:BAACLAAFFIEGAAMOAAMIlhEJCQD9AAAOAAMIlhEJCQD9AAAKAAEIvQgaFQBNAAAsAAQKgRgABA4ACAhXI8kYAGkCAA4ACAh3HMkYAGkCABYABAjvIMoOAHkBAAoABAhmIF4tAE4BAAAA.',Mo='Monkeymind:BAAALAAECgcIDQAAAA==.Mooberry:BAAALAAECgYIDAAAAA==.Mordale:BAAALAAECgIIBAAAAA==.Mordollwen:BAAALAADCggICgAAAA==.Mothem:BAAALAAECgYIDAAAAA==.',Mt='Mtfgamer:BAAALAADCgcICwAAAA==.',My='Mysec:BAAALAAFFAIIBAAAAA==.',['Mé']='Mégaira:BAAALAADCgcIFAAAAA==.',Na='Naras:BAAALAAECgUIBAAAAA==.Navier:BAAALAAECgYIBwAAAA==.Nayah:BAAALAAECgYIDgAAAA==.',Ne='Necropium:BAAALAADCgcIBwAAAA==.',Ni='Nibbø:BAABLAAECoEWAAIWAAcIWxeKBQA3AgAWAAcIWxeKBQA3AgAAAA==.Nimerya:BAAALAAECgYIDQAAAA==.',No='Nonesovile:BAAALAAECgcIDwAAAA==.Noorke:BAAALAAECgIIAgAAAA==.Nopsalock:BAAALAADCgcIBwAAAA==.Noryxith:BAAALAADCggIDwAAAA==.Novareaper:BAAALAADCggICAAAAA==.',Nu='Nubbish:BAAALAADCgEIAQAAAA==.',Ny='Nyehehe:BAAALAAECgQIBAAAAA==.',['Nú']='Núgzz:BAABLAAECoEVAAIXAAYIyyD9GgA6AgAXAAYIyyD9GgA6AgAAAA==.',Og='Ogmalog:BAAALAADCgcIFwAAAA==.',Op='Ophelhia:BAAALAADCgUIBQAAAA==.',Or='Oranges:BAAALAADCggICAAAAA==.',Os='Osferth:BAAALAAECgYIEwAAAA==.',Pa='Pallasathene:BAAALAADCgcIDQAAAA==.Pandàmonium:BAAALAAECgIIAwAAAA==.Panicore:BAAALAADCgcIBwAAAA==.Pavwo:BAAALAAECgEIAQAAAA==.',Pi='Picerusonix:BAAALAAECgIIAgAAAA==.Pippuri:BAAALAADCgQIBAAAAA==.',Pl='Plainrenew:BAAALAADCggIDwABLAAECgcIFQAYAIseAA==.Plainview:BAABLAAECoEVAAIYAAcIix4rFQBHAgAYAAcIix4rFQBHAgAAAA==.',Po='Poottle:BAAALAADCgcIFgAAAA==.Poprose:BAAALAADCgYICQAAAA==.',Pr='Proclusangel:BAAALAADCgcIEAAAAA==.',Qu='Quylsta:BAAALAADCgUIBwAAAA==.',Ra='Ragamuffinb:BAAALAADCggICAAAAA==.Ragamuffind:BAAALAADCgcIBwAAAA==.Raidium:BAAALAAECgYIDQAAAQ==.Razorslock:BAAALAAECgcIDQAAAA==.Razsalgul:BAABLAAECoEYAAMKAAgIaCJbFADvAQAKAAUIASRbFADvAQAOAAUIMyA0NACvAQAAAA==.',Rh='Rheanyraa:BAAALAADCgEIAQAAAA==.Rhine:BAAALAAECgYIDwAAAA==.',Ri='Rillarosa:BAAALAAECgEIAgAAAA==.Ripson:BAAALAAECgQIBAAAAA==.',Ru='Ruffepuffe:BAABLAAECoEWAAMGAAYIvhLtYQBoAQAGAAYIAhLtYQBoAQAIAAYIQxFCHwAPAQAAAA==.Ruin:BAAALAADCgcIBwABLAAECggIFgAFACclAA==.',Ry='Ryoku:BAAALAAECgYIDAAAAA==.',Se='Seasalts:BAAALAADCgYICwAAAA==.Sebasalfie:BAAALAADCgcICgAAAA==.Semlan:BAAALAADCggICAABLAAECgcIFAATAFEHAA==.Senara:BAAALAADCggIDwAAAA==.',Sh='Shaloom:BAAALAADCggICgAAAA==.Shuriken:BAAALAADCgQIBAAAAA==.',Si='Silvercurse:BAAALAADCgYIBQAAAA==.Simbalu:BAAALAADCgQIAgAAAA==.Sixpacc:BAAALAADCggIEwAAAA==.',Sk='Skychaser:BAAALAAECggIDwAAAA==.',Sm='Sminted:BAAALAADCgcIFwAAAA==.',Sn='Sneakyborry:BAAALAAECgcIEwAAAA==.',So='Soulavenger:BAAALAADCggICAAAAA==.Soulevoker:BAAALAAECgYIDQAAAA==.Soulsavior:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Sp='Speiredonia:BAAALAADCgcICAAAAA==.',Su='Summy:BAABLAAECoEYAAMCAAgIJCDCGgCMAgACAAgIDyDCGgCMAgAJAAMIJxbYRQCOAAAAAA==.',Sw='Swifttiffany:BAABLAAECoEXAAIQAAcIAh9oFgBNAgAQAAcIAh9oFgBNAgAAAA==.',Sy='Synithia:BAAALAADCgcIBwAAAA==.',Td='Tdevilfish:BAAALAAECgcIEAAAAA==.',Te='Tenshó:BAAALAADCgcIBwABLAAECgcIFQAIABwiAA==.Terrorglaive:BAAALAAECgcIDQAAAA==.',Ti='Tink:BAAALAADCggIEAAAAA==.Tiotis:BAAALAAECgQICAAAAA==.',To='Tofu:BAAALAADCggICAABLAAECgcIFAAFANISAA==.',Tr='Trebold:BAAALAADCgIIAgAAAA==.',Tu='Turaath:BAAALAAECgUIBgAAAA==.',Ul='Ulir:BAAALAAECgQIAwAAAA==.',Uz='Uzu:BAAALAAECgcIEgAAAA==.',Va='Vaccine:BAAALAAECgIIBAAAAA==.Valeryah:BAAALAAECgYIDgAAAA==.',Ve='Veidec:BAAALAADCgcIBwAAAA==.Vexxen:BAAALAAECgYICQAAAA==.',Vi='Viccky:BAAALAAECgQIBAAAAA==.Vinara:BAAALAADCgEIAQAAAA==.',Vu='Vuurdoop:BAAALAADCgYIBgAAAA==.',Wa='Wabiskai:BAAALAAECgQICQAAAA==.Warbornlock:BAAALAADCgcIBwAAAA==.Warorr:BAAALAADCggICAAAAA==.Warriorsas:BAAALAAECgIIAgAAAA==.Warrmann:BAAALAADCgcIBwAAAA==.Warthun:BAAALAADCggIFgAAAA==.',Wo='Wox:BAAALAADCggICQABLAAECgEIAQABAAAAAA==.',['Wë']='Wëlkín:BAAALAADCggICAAAAA==.',Xa='Xandhorian:BAAALAAECgcIBwAAAA==.Xaviera:BAABLAAECoEVAAIIAAcIwxrHDwDbAQAIAAcIwxrHDwDbAQAAAA==.',Xg='Xgén:BAAALAAECgMIBwAAAA==.',Xt='Xtal:BAAALAAECgEIAQAAAA==.',Ya='Yasmin:BAAALAADCggICAAAAA==.',Ye='Yesugei:BAAALAAECgcIDQAAAA==.',Yo='Yomifour:BAAALAAECgEIAQAAAA==.',Za='Zaafira:BAABLAAECoEVAAIGAAcI7A7jUACdAQAGAAcI7A7jUACdAQAAAA==.',Zi='Zimerion:BAAALAAECgcIDgAAAA==.',Zu='Zultax:BAAALAAECggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end