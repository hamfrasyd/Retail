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
 local lookup = {'Priest-Discipline','Priest-Holy','Priest-Shadow','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Protection','Evoker-Preservation','Evoker-Devastation','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Shaman-Elemental','Paladin-Holy','Warrior-Fury','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Retribution','Evoker-Augmentation','Mage-Fire','Mage-Frost','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Protection','Monk-Windwalker','Mage-Arcane','Druid-Feral','Rogue-Subtlety','Rogue-Assassination',}; local provider = {region='EU',realm='Echsenkessel',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ag='Agro:BAAALAADCggIEAAAAA==.',Aj='Ajel:BAABLAAECoEhAAMBAAgIsCDsAQDrAgABAAgIsCDsAQDrAgACAAMI3he2fADXAAAAAA==.',Ak='Akadech:BAAALAADCgcIBwAAAA==.',Al='Alyura:BAAALAAECgcICgAAAA==.',An='Anarys:BAAALAAECgcIDQABLAAECggIFQADAFMeAA==.Anthazul:BAAALAADCggICQAAAA==.Anxex:BAAALAADCggICAAAAA==.',Ar='Arathia:BAAALAAECgUICQAAAA==.Argador:BAABLAAECoEaAAMEAAgIxh8+DQBgAgAEAAgIxh8+DQBgAgAFAAEIIgSDIQErAAABLAAFFAMICwAGAF8YAA==.Aridala:BAAALAADCggIEwAAAA==.Arnakuagsak:BAABLAAECoEvAAMHAAgIex7YIwCTAgAHAAgIex7YIwCTAgAIAAMISBaVeQDLAAAAAA==.',As='Asafiri:BAAALAADCgYIBgAAAA==.Ashi:BAABLAAECoEVAAMHAAYIuiQUKwBwAgAHAAYIuiQUKwBwAgAIAAYIkBkTNwDGAQABLAAFFAMIBwAJAFgXAA==.Ashkael:BAABLAAFFIEHAAIFAAIIDBLBKwCYAAAFAAIIDBLBKwCYAAAAAA==.Asifara:BAAALAADCgYIBgAAAA==.',At='Ataxis:BAAALAADCggICAAAAA==.Atze:BAAALAAECgYIDAAAAA==.',Av='Avalas:BAAALAAECgUICwAAAA==.Aviá:BAAALAAECgYICAAAAA==.',Ay='Ayuzuria:BAACLAAFFIEKAAIKAAMIuxFNCADgAAAKAAMIuxFNCADgAAAsAAQKgScAAwoACAg/G1kJAHgCAAoACAg/G1kJAHgCAAsACAgcE0sfAAUCAAAA.',Az='Azuchapus:BAAALAAECgcIDAAAAA==.',Ba='Baileys:BAABLAAECoEVAAIMAAYI1RhbWgCpAQAMAAYI1RhbWgCpAQAAAA==.Bajrodz:BAAALAADCggICAAAAA==.Baltor:BAABLAAECoEXAAMEAAcIWhMfJABaAQAEAAcI0BIfJABaAQAFAAQIBQ424wC2AAAAAA==.',Be='Benny:BAAALAAFFAMIAwABLAAFFAUIDgACAK8bAA==.Bethekk:BAAALAAECggICAAAAA==.',Bh='Bhalrog:BAABLAAECoElAAIHAAYInCOoPwAiAgAHAAYInCOoPwAiAgAAAA==.',Bi='Bigdk:BAAALAADCggICAAAAA==.Bimsalasim:BAAALAAECgYIDgAAAA==.',Bj='Björnström:BAAALAADCggIDQAAAA==.',Bl='Blintschiki:BAAALAAECgQIDwAAAA==.Blitzfuchs:BAAALAADCggIEwABLAAECggICAANAAAAAA==.Bloodeye:BAAALAADCgYIBgAAAA==.Bloodraven:BAACLAAFFIEKAAMOAAUIixKhEABVAQAOAAQIwxGhEABVAQAPAAII7xLQDwCdAAAsAAQKgTUABA4ACAjLJCwOABwDAA4ACAj0IiwOABwDAA8ABwhdHqoRAFMCABAAAwgOHk8bAAMBAAAA.',Bn='Bngz:BAAALAAECgYICgAAAA==.',Bo='Bombär:BAACLAAFFIEGAAIRAAII1xzAAgCoAAARAAII1xzAAgCoAAAsAAQKgR4AAhEACAiPIGYDAOQCABEACAiPIGYDAOQCAAAA.Boxxi:BAAALAAECgcIEwAAAA==.',Br='Bradok:BAAALAAECgIIAgAAAA==.Brai:BAAALAADCggICAAAAA==.Brillux:BAACLAAFFIEKAAISAAMI8BPyDwD1AAASAAMI8BPyDwD1AAAsAAQKgSUAAhIACAh6IckRAO0CABIACAh6IckRAO0CAAAA.Bruderhorst:BAAALAAECgYICgABLAAECggIGgATAFsaAA==.Brüdiggar:BAAALAAECgYICwABLAAECggIGgATAFsaAA==.',Bu='Buhh:BAAALAAECgYIBgAAAA==.Bulbaj:BAAALAADCggICAAAAA==.Butterfach:BAAALAADCggICAAAAA==.',['Bâ']='Bâm:BAAALAADCgYIBgAAAA==.',['Bî']='Bîernot:BAAALAAECgEIAQAAAA==.',Ca='Camel:BAAALAADCggIGgAAAA==.Carnivora:BAABLAAECoEUAAIUAAgIGRKXQgD5AQAUAAgIGRKXQgD5AQAAAA==.Caîne:BAAALAAECgcIDQABLAAFFAIIAgANAAAAAA==.',Ce='Celestialx:BAAALAADCgIIAwAAAA==.',Cp='Cptn:BAAALAAECgIIBAABLAAECggIFwAHABIMAA==.',Cr='Creami:BAAALAAECgYIDAAAAA==.',Cy='Cypherdrone:BAAALAADCggIDQAAAA==.',De='Deathknight:BAABLAAECoEhAAQVAAcIVxqaFQAAAgAVAAcIGhmaFQAAAgAWAAcI1BDuDgG0AAAXAAQIwwvfLwCmAAAAAA==.Demoniaa:BAAALAAECgYIBwAAAA==.Deréntis:BAABLAAECoEiAAMYAAcIwB6fQABPAgAYAAcIwB6fQABPAgATAAYIKRNpNgBYAQAAAA==.',Di='Diabout:BAABLAAECoEfAAIEAAcIpBSRHwCCAQAEAAcIpBSRHwCCAQAAAA==.Divinetales:BAACLAAFFIEQAAMTAAUIbR3VAgDrAQATAAUIbR3VAgDrAQAYAAEIzAXnRQBOAAAsAAQKgRYAAxMACAijHksMAJoCABMACAijHksMAJoCABgABwgAEtCCALQBAAAA.',Do='Donnatroy:BAAALAADCggILwAAAA==.Doppelfrogg:BAAALAADCgMIAwAAAA==.Dormammu:BAAALAAECgUIBQAAAA==.',Dr='Dragonlord:BAAALAAECgEIAQAAAA==.Drecon:BAAALAAECgQIBAAAAA==.Drorrik:BAAALAAECgUIBQAAAA==.Druggy:BAAALAADCggICAABLAAFFAYIFQACADIiAA==.',['Dä']='Dämonenfuchs:BAAALAADCggIDgABLAAECggICAANAAAAAA==.',['Dé']='Dérentis:BAAALAAECggICAABLAAECggIIgAYAMAeAA==.',El='Elaih:BAAALAAECgMIAwAAAA==.Eldhior:BAAALAADCgcIBwAAAA==.Eldhor:BAAALAADCgYIBgAAAA==.Eldhrion:BAAALAADCgYIBgAAAA==.',Em='Emden:BAAALAADCgcIBwABLAAECgYIDAANAAAAAA==.Emoo:BAAALAAECggIAQABLAAECggIFwAHABIMAA==.',En='Endzone:BAAALAADCggICAAAAA==.Enhuensn:BAAALAADCgQIBAAAAA==.Ensa:BAABLAAECoEgAAMWAAgIOSKQGAD0AgAWAAgI4yGQGAD0AgAXAAEIfSFpOgBOAAAAAA==.',Ep='Epiphany:BAAALAAECgYIEwAAAA==.',Es='Estus:BAAALAAECgYIEQAAAA==.',Ev='Evil:BAAALAADCgcIBwAAAA==.',Fa='Facemeltorz:BAAALAADCgcICwABLAADCggIDQANAAAAAA==.',Fl='Flameon:BAAALAAECgUIBQAAAA==.Floki:BAABLAAECoEmAAIWAAgIrR/5HwDQAgAWAAgIrR/5HwDQAgABLAAFFAIIAgANAAAAAA==.Flurry:BAAALAADCgYIBgABLAADCgcIBwANAAAAAA==.',Fu='Fuji:BAAALAADCggIDwAAAA==.Fulgur:BAAALAADCgcIBwAAAA==.',Ga='Garaldor:BAAALAAECggIBwABLAAFFAMICwAGAF8YAA==.Garmiant:BAAALAAECgcICgABLAAFFAMICwAGAF8YAA==.Garpal:BAAALAAECggICAAAAA==.Gatrig:BAAALAAECggICQAAAA==.',Ge='Gemächlich:BAAALAADCggICAAAAA==.Gerodar:BAAALAADCggICAAAAA==.',Gh='Ghouldan:BAACLAAFFIEKAAIOAAIIvR3iIgCrAAAOAAIIvR3iIgCrAAAsAAQKgSgAAw4ACAj7IJAYANgCAA4ACAiTIJAYANgCAA8ABgj1HGYpALABAAAA.',Go='Goldendemon:BAAALAAECgYICQAAAA==.Goldenpriest:BAABLAAECoEUAAIDAAYIBBUnQQCVAQADAAYIBBUnQQCVAQAAAA==.',Gr='Grafshamy:BAAALAAECgIIAgAAAA==.Grapesoda:BAAALAADCgIIAgAAAA==.Grehna:BAAALAADCgUIBQAAAA==.Grimreaper:BAAALAAECggIEQAAAQ==.Grygoria:BAAALAADCgcIDQAAAA==.',Ha='Hagebär:BAABLAAECoEfAAIRAAgIHhYgCgAPAgARAAgIHhYgCgAPAgAAAA==.Haumíchum:BAAALAAECgcIEgAAAA==.',He='Headtrick:BAAALAADCgMIAwAAAA==.Healiix:BAAALAAECgcIEwAAAA==.Henryf:BAAALAADCgQIBAAAAA==.',Hi='Himemiya:BAAALAAECgYIDAAAAA==.Hirara:BAACLAAFFIEHAAMHAAMI6Qe2GgC6AAAHAAMI6Qe2GgC6AAAIAAEIlAFKMQAqAAAsAAQKgTIAAwcACAgHIlQWAN8CAAcACAgHIlQWAN8CAAgACAj9FwkuAPcBAAAA.Hisse:BAAALAADCgYIBgAAAA==.',Ho='Hoko:BAAALAAECgYIBgABLAAFFAYIDQAJAEQVAA==.',Hu='Hunthor:BAAALAAECgMIBAAAAA==.',Ic='Icarium:BAABLAAFFIEIAAIWAAIIxyNzIADHAAAWAAIIxyNzIADHAAAAAA==.Icedearth:BAAALAADCgUIBQAAAA==.Icee:BAAALAAECgYIBgABLAAFFAMIBwAJAFgXAA==.Iceplexus:BAABLAAECoEdAAIWAAgIRBLAdgDUAQAWAAgIRBLAdgDUAQAAAA==.',Il='Ildabeam:BAAALAAECgcIDgAAAA==.Ildagrimm:BAABLAAECoEWAAIMAAgITRjFWwClAQAMAAgITRjFWwClAQAAAA==.Illídan:BAAALAAECgIIAQABLAAECggIHQAWAEQSAA==.',In='Inu:BAAALAAECgYICwAAAA==.Inuki:BAAALAAECgYIBwABLAAFFAMICgAKALsRAA==.',Ir='Iryeos:BAABLAAECoEgAAMHAAgIrR/WJACOAgAHAAgIrR/WJACOAgAIAAEIxQ+qrwAwAAAAAA==.',Ja='Jaqhi:BAAALAADCggICAABLAAFFAUIDQAGANQUAA==.Jayqui:BAACLAAFFIENAAIGAAUI1BRmBgAfAQAGAAUI1BRmBgAfAQAsAAQKgSsAAgYACAimIaUHANMCAAYACAimIaUHANMCAAAA.',Ji='Jincy:BAABLAAECoEVAAIZAAcIFiHdBABGAgAZAAcIFiHdBABGAgAAAA==.Jincydruid:BAAALAAECggICAAAAA==.',['Jö']='Jörmungand:BAAALAADCggIDwAAAA==.',Ka='Kanaga:BAAALAADCggICwAAAA==.Karanti:BAAALAADCgcIBwAAAA==.Kargalgan:BAAALAADCgUICQAAAA==.Kaymera:BAAALAADCggIDgABLAAECgcIFgAMAAAUAA==.',Ke='Kezzan:BAAALAADCgcIBgAAAA==.',Kh='Khersha:BAAALAAECggIBgAAAA==.',Ki='Kirchenwirt:BAAALAADCgcICgAAAA==.',Kl='Klatschdích:BAAALAADCgQIBAAAAA==.',Ko='Koffie:BAAALAAECgYIDAAAAA==.Kota:BAACLAAFFIELAAIaAAMImx9uAQARAQAaAAMImx9uAQARAQAsAAQKgSwAAxoACAjwI98AADwDABoACAjwI98AADwDABsABgg4FJRAAEgBAAAA.',Kp='Kptn:BAABLAAECoEXAAMHAAgIEgz8qQAsAQAHAAYI5w/8qQAsAQAIAAQIvgC+vAAeAAAAAA==.',Kr='Kromlok:BAAALAAECgMIAgAAAA==.',['Kä']='Käptn:BAAALAAECgYIBgABLAAECggIFwAHABIMAA==.',Le='Leechia:BAAALAAECgIIAwAAAA==.Lennox:BAAALAAECgIIAgABLAAFFAYIEgAMAEUUAA==.Leshi:BAACLAAFFIEHAAICAAMIoAnEEwDSAAACAAMIoAnEEwDSAAAsAAQKgRsAAgIACAjUF5QrABgCAAIACAjUF5QrABgCAAAA.',Li='Liesanna:BAAALAAECgIIAgAAAA==.Liizz:BAAALAADCgEIAQAAAA==.Lilliandra:BAAALAAECgQIBAAAAA==.',Lo='Lockybalboà:BAAALAADCggIDgABLAAECggIFQAYAKkiAA==.Lohya:BAAALAADCgMIAwABLAAECggIIgASAGYiAA==.Loonrage:BAAALAAECgMIAwABLAAECggIJQAcAOcQAA==.Lophenia:BAAALAADCgcIBwAAAA==.Lorna:BAAALAADCggICAAAAA==.Lothi:BAABLAAECoEUAAMTAAgISBPHIQDXAQATAAgISBPHIQDXAQAYAAUIjgyw2AAWAQAAAA==.',['Lý']='Lýssa:BAAALAAECggICQAAAA==.',Ma='Machmá:BAABLAAECoEeAAMIAAYI5SABJwAhAgAIAAYIch8BJwAhAgAHAAYInBsAAAAAAAABLAAFFAIIBgAMABsXAA==.Mageblood:BAAALAAECgYIEgABLAAECgYIFQAHAIsdAA==.Magicmili:BAAALAAECgEIAQABLAAFFAUIEgACAPALAA==.Mandos:BAAALAAECggIJQAAAQ==.Masodist:BAAALAAECgcIDwAAAA==.',Mc='Mcmuffin:BAAALAAECgUIDgAAAA==.',Me='Me:BAAALAAECgYIDgAAAA==.',Mi='Mieze:BAAALAADCgcIEwAAAA==.Milie:BAACLAAFFIESAAICAAUI8AurBwB6AQACAAUI8AurBwB6AQAsAAQKgSgAAgIACAgFHkkUAK0CAAIACAgFHkkUAK0CAAAA.Milli:BAABLAAECoEVAAMMAAcIeRUoVwCxAQAMAAcIeRUoVwCxAQASAAIIXwovnwBgAAABLAAFFAUIEgACAPALAA==.Mirakulix:BAACLAAFFIEJAAIdAAMI6xT0CgDrAAAdAAMI6xT0CgDrAAAsAAQKgS8AAh0ACAgbIr4LAPsCAB0ACAgbIr4LAPsCAAAA.Miriamda:BAAALAAECgYICQAAAA==.Missesx:BAAALAADCgcIBwAAAA==.',Mo='Mokbahrn:BAABLAAECoEfAAMYAAcIuhUiYgD3AQAYAAcIuhUiYgD3AQATAAYI/g9ZNQBfAQAAAA==.Mokut:BAAALAADCgcIBwAAAA==.Mortuna:BAAALAADCgcIBwAAAA==.Mottenmann:BAAALAADCggICAAAAA==.',My='Mysalim:BAAALAAFFAIIAwAAAA==.Myu:BAAALAAECgYIDAAAAA==.',['Mî']='Mîdnight:BAAALAADCggIFwAAAA==.',['Mü']='Münlì:BAABLAAECoEfAAIOAAYIbwrhiwAnAQAOAAYIbwrhiwAnAQAAAA==.Müsli:BAACLAAFFIEHAAIDAAMIqxiACwAOAQADAAMIqxiACwAOAQAsAAQKgSwAAgMACAiaI9kFAEQDAAMACAiaI9kFAEQDAAAA.',Na='Nachtfuchs:BAAALAAECggICAABLAAECggICAANAAAAAA==.Nam:BAAALAADCggIDgAAAA==.Nanashii:BAAALAAECgcIEAAAAA==.',Ne='Nene:BAAALAAECggICwAAAA==.Nexev:BAAALAADCgcIDgAAAA==.',Ni='Niahri:BAABLAAECoEaAAIeAAgIhSLjAQAtAwAeAAgIhSLjAQAtAwAAAA==.Nichsotief:BAABLAAECoEaAAMTAAgIWxp+DgCBAgATAAgIWxp+DgCBAgAYAAEI9woUOgE8AAAAAA==.Niven:BAAALAADCgYIBgAAAA==.',No='Norsîa:BAAALAAECgQIBQAAAA==.',Ny='Nymora:BAAALAADCgYIBgABLAAFFAYIDAALAFEdAA==.',['Nâ']='Nândra:BAAALAAECggIEAABLAAFFAcIEQAYAMIUAA==.',Oh='Ohnezahn:BAAALAAECgcICwAAAA==.',Ok='Oksana:BAAALAADCggICAAAAA==.',Or='Orakel:BAAALAADCgYIBgABLAAECgcIFwAEAFoTAA==.',Oz='Oz:BAAALAADCgcIBwABLAADCgcIBwANAAAAAA==.',Pa='Parcival:BAABLAAECoEWAAIfAAgIDRWHGgDtAQAfAAgIDRWHGgDtAQAAAA==.',Pe='Perian:BAABLAAECoEgAAIgAAcIpAfnOwAGAQAgAAcIpAfnOwAGAQAAAA==.',Ph='Phèlan:BAABLAAECoEXAAIYAAgIJBVFXgAAAgAYAAgIJBVFXgAAAgAAAA==.',Po='Porzagosa:BAAALAAECggICAABLAAECggIHQAWAEQSAA==.',Pr='Precioso:BAABLAAECoEXAAIUAAcIVh0jOAAjAgAUAAcIVh0jOAAjAgAAAA==.Prestabo:BAABLAAECoEUAAIhAAUIagkhpgD4AAAhAAUIagkhpgD4AAAAAA==.',Pu='Puschl:BAABLAAECoEbAAICAAgIHAz4RQCZAQACAAgIHAz4RQCZAQAAAA==.Pusteblume:BAAALAAECgQIBgAAAA==.',Ra='Raimy:BAAALAAECgQIBQAAAA==.Rapidfire:BAAALAAECgYIBwAAAA==.',Re='Reaperxdante:BAAALAAECgQICwAAAA==.Remornia:BAAALAAECgIIAwAAAA==.Renneria:BAAALAADCgMIAwAAAA==.',Rh='Rhababara:BAAALAAECgYIBwAAAA==.Rhiâna:BAABLAAECoEiAAITAAcIKxe1IADfAQATAAcIKxe1IADfAQAAAA==.',Ro='Rothgar:BAAALAAECgYIBgABLAAFFAIIAgANAAAAAA==.',Ru='Rue:BAABLAAECoEVAAMDAAgIUx6SKQAUAgADAAcIGR6SKQAUAgACAAEIuQPxpgAsAAAAAA==.Rumi:BAACLAAFFIEHAAIJAAMIWBeVCADkAAAJAAMIWBeVCADkAAAsAAQKgSYAAgkACAhNIroHAAcDAAkACAhNIroHAAcDAAAA.Runcandel:BAAALAADCggICAABLAAECgIIAwANAAAAAA==.',Ry='Ryku:BAAALAADCgcIBwAAAA==.Rynthor:BAAALAAECgcIEAAAAA==.',['Rø']='Røulade:BAABLAAECoEgAAMWAAgI2hjuUQAlAgAWAAgIJRbuUQAlAgAXAAQItRnrKgDbAAAAAA==.',Sa='Sacerdote:BAAALAADCggIDgAAAA==.Salvator:BAAALAADCgYIBgABLAAECgIIAwANAAAAAA==.Saphiré:BAAALAADCgUIBQAAAA==.',Sc='Schlagpfote:BAAALAADCgYIBgABLAAECggICAANAAAAAA==.Schmalzo:BAAALAAECgMIAwAAAA==.',Se='Sectrína:BAAALAAECggIBgAAAA==.Sectás:BAABLAAECoEWAAIbAAgIZwgtTAAUAQAbAAgIZwgtTAAUAQAAAA==.Sedith:BAAALAADCgQIBAABLAAECgIIAwANAAAAAA==.',Sh='Shamrox:BAAALAAECgYIBgAAAA==.Shapeshift:BAAALAADCggICAAAAA==.Sharvara:BAAALAADCgcIBwAAAA==.Shea:BAAALAAECgEIAQABLAAECgMIAwANAAAAAA==.Sheltear:BAAALAADCggICAABLAAECggIEQANAAAAAQ==.',Si='Sigler:BAACLAAFFIEFAAICAAIInBTQHgCbAAACAAIInBTQHgCbAAAsAAQKgRoAAgIACAiTE+kxAPcBAAIACAiTE+kxAPcBAAAA.Sindragos:BAAALAAFFAIIAgAAAA==.Sisaa:BAACLAAFFIEGAAIMAAIIGxcuJwCRAAAMAAIIGxcuJwCRAAAsAAQKgSMAAgwACAi4G88gAG8CAAwACAi4G88gAG8CAAAA.Sisu:BAAALAADCgYIBgAAAA==.Sivanas:BAAALAAECggICgAAAA==.',Sk='Skalí:BAABLAAECoEYAAIiAAgIfRD7FADjAQAiAAgIfRD7FADjAQAAAA==.',Sn='Snirs:BAAALAADCgYIBgAAAA==.Snoope:BAAALAAECgYIBwABLAAECggIIgASAGYiAA==.',So='Sodranoel:BAAALAAECggICAAAAA==.',St='Stechfuchs:BAAALAADCgcIDQABLAAECggICAANAAAAAA==.Streit:BAAALAADCggICAAAAA==.Stupsia:BAAALAAECgQIBAAAAA==.',Su='Subnodoubt:BAAALAADCggICQABLAAECggIIgASAGYiAA==.',Sy='Sylire:BAAALAAECgQIBAAAAA==.',['Sì']='Sìegfrìed:BAABLAAECoEVAAIYAAgIqSI3KQCnAgAYAAgIqSI3KQCnAgAAAA==.',Ta='Taiitó:BAAALAAECgYICwAAAA==.Tarnefana:BAECLAAFFIEPAAMjAAUImRxxBQAbAQAjAAMIgh1xBQAbAQAkAAMIoxcuCAASAQAsAAQKgSYAAyMACAjYIwUFAOwCACMACAhxIgUFAOwCACQABwgjIcMTAG8CAAAA.Taziri:BAAALAADCgYIAwAAAA==.',Tb='Tbøne:BAAALAADCgMIBAAAAA==.',Th='Thaliana:BAAALAADCggICAAAAA==.Theran:BAACLAAFFIELAAIGAAMIXxjDBwDrAAAGAAMIXxjDBwDrAAAsAAQKgR0AAgYACAgfH3MIAMACAAYACAgfH3MIAMACAAAA.Thorric:BAAALAADCgYIBwABLAAECggILAAMAG0lAA==.Thorrik:BAABLAAECoEsAAIMAAgIbSUSBAA8AwAMAAgIbSUSBAA8AwAAAA==.',Ti='Tilo:BAACLAAFFIEIAAIdAAMIPx4bCQAMAQAdAAMIPx4bCQAMAQAsAAQKgSoAAh0ACAgXJNwFAEIDAB0ACAgXJNwFAEIDAAAA.',To='Togo:BAABLAAECoEjAAMHAAcIUB/EPwAiAgAHAAcIUB/EPwAiAgAIAAEI4QQLtQAqAAAAAA==.Togy:BAAALAADCggICgAAAA==.Toxical:BAAALAAECgYIDQAAAA==.',Tr='Tributar:BAAALAAECgYICgABLAAECgUIFAAhAGoJAA==.Trnkzz:BAAALAAECgMIBAAAAA==.',Ts='Tsoi:BAAALAAECgYIDQAAAA==.Tsundereclap:BAAALAAECgIIBQABLAAECgYIFQAHAIsdAA==.',Tu='Tusker:BAAALAADCgcIBwAAAA==.',Ty='Tyhla:BAAALAAECgYIEwAAAA==.Tyra:BAAALAAECggICAAAAA==.Tyrloc:BAAALAAECggIBwAAAA==.',Ug='Uglymon:BAAALAADCggICAAAAA==.',Ul='Ulthar:BAAALAAECgEIAQAAAA==.',Va='Vaelira:BAABLAAECoEfAAITAAgIux9WBgDrAgATAAgIux9WBgDrAgAAAA==.Valaar:BAABLAAECoEdAAIYAAcIYBilYwDzAQAYAAcIYBilYwDzAQAAAA==.Valithria:BAABLAAECoEjAAIOAAcILhncTgDTAQAOAAcILhncTgDTAQAAAA==.Valtherion:BAAALAADCgUIBQAAAA==.Vanessa:BAAALAADCggICAAAAA==.Varmint:BAABLAAECoEmAAMPAAgI7iMJAgBRAwAPAAgI7iMJAgBRAwAOAAgIhxKWSQDmAQAAAA==.Varros:BAABLAAECoEkAAIUAAgI9x7gGwC/AgAUAAgI9x7gGwC/AgAAAA==.Vatheron:BAACLAAFFIEUAAILAAYIsh0XAgAeAgALAAYIsh0XAgAeAgAsAAQKgSsAAgsACAhCJkwBAHcDAAsACAhCJkwBAHcDAAAA.',Ve='Velanda:BAAALAAECgYIDQAAAA==.Verono:BAACLAAFFIEGAAITAAIIwiBwDQDCAAATAAIIwiBwDQDCAAAsAAQKgSYAAxMACAjYIN0FAPICABMACAjYIN0FAPICABgABwjdH9g8AFsCAAAA.',Vi='Violet:BAAALAADCggICAAAAA==.Virgilius:BAAALAADCggIHgABLAAECggIJAAUAPceAA==.',Vo='Voidbert:BAACLAAFFIEGAAIDAAMIkgRzEQC5AAADAAMIkgRzEQC5AAAsAAQKgS4AAgMACAgiIIgNAPkCAAMACAgiIIgNAPkCAAAA.',Wa='Warum:BAAALAAECgYICQABLAAECgYIFQAHAIsdAA==.',Wi='Wieso:BAABLAAECoEVAAIHAAYIix1AdQCUAQAHAAYIix1AdQCUAQAAAA==.Windfury:BAAALAAECggIEgABLAAFFAIIAgANAAAAAA==.',Wo='Wobär:BAAALAAECgQICQAAAA==.Wolfsatans:BAAALAADCgcIBwABLAAECggIIgAHAIUWAA==.Wolfsdeath:BAABLAAECoEiAAIHAAcIhRaDXwDHAQAHAAcIhRaDXwDHAQAAAA==.Wolfssatan:BAAALAAECgYIDgABLAAECggIIgAHAIUWAA==.',Xa='Xaladoom:BAABLAAECoEiAAMVAAYIThrgGwDFAQAVAAYImhjgGwDFAQAWAAYI0xWdoQCGAQABLAAECgcIFAAiAN4VAA==.Xaldarian:BAABLAAECoEUAAIiAAcI3hVfFQDeAQAiAAcI3hVfFQDeAQAAAA==.Xaltari:BAAALAAECgEIAQABLAAECgcIFAAiAN4VAA==.Xaltarion:BAAALAAECgMIAwABLAAECgcIFAAiAN4VAA==.',Xe='Xerpy:BAACLAAFFIEXAAMWAAcIACFLAgBcAgAWAAcIACFLAgBcAgAVAAEItgcuFQBZAAAsAAQKgRwAAxYACAg+JiEKAEEDABYACAg+JiEKAEEDABUAAQgcJPBLAFwAAAAA.',Ya='Yashako:BAAALAAECgYIDAABLAAFFAMIBwAJAFgXAA==.',Ye='Yep:BAAALAADCgYIBwAAAA==.',Yn='Ynos:BAAALAADCgcIBwAAAA==.',Yo='Yomiko:BAAALAAECgIIAgABLAAECgcIFAAFAHEcAA==.Yorren:BAAALAAECgUIEAAAAA==.',Yu='Yukiji:BAAALAAECgYICwAAAA==.Yun:BAAALAAFFAIIAgABLAAFFAcIFgAFAPQYAA==.',Za='Zahrakul:BAAALAAECgEIAQABLAAECgcIEgANAAAAAA==.Zalty:BAABLAAECoEjAAIEAAcIJyKOCgCLAgAEAAcIJyKOCgCLAgAAAA==.Zarakul:BAAALAAECgcIEgAAAA==.',Ze='Zercichan:BAAALAAECgYIDQAAAA==.',Zo='Zona:BAAALAAECgYIBAAAAA==.',Zu='Zulsaframano:BAAALAADCggICAAAAA==.',Zw='Zwal:BAAALAADCggIGgAAAA==.',Zy='Zyrion:BAAALAADCggIDgAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end