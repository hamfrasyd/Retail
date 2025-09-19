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
 local lookup = {'DemonHunter-Vengeance','Monk-Brewmaster','Warrior-Arms','Druid-Balance','DemonHunter-Havoc','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Warlock-Demonology','Warlock-Affliction','Evoker-Devastation','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Warrior-Fury','Druid-Restoration','Paladin-Holy','Monk-Mistweaver','Warrior-Protection','Warlock-Destruction','Mage-Fire','Priest-Shadow','Priest-Holy','Hunter-Survival','Hunter-Marksmanship',}; local provider = {region='EU',realm='SteamwheedleCartel',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ad='Adaephonn:BAAALAAECgcIDAAAAA==.',Ae='Aelea:BAAALAAECgMIBAAAAA==.Aethelflaed:BAAALAAECgcICgAAAA==.',Af='Afrah:BAAALAAECgQIBQABLAAECgcIFwABAN4WAA==.',Ai='Aidune:BAAALAAECgIIAgAAAA==.Aigon:BAABLAAECoEVAAICAAgIqxOLDAD2AQACAAgIqxOLDAD2AQAAAA==.Aiyana:BAAALAADCggIEwAAAA==.',Al='Algelon:BAAALAAECgIIAgAAAA==.',An='Anilerda:BAAALAADCggIEAAAAA==.',Ar='Arashicage:BAABLAAECoEeAAIDAAgIZCFCAQAUAwADAAgIZCFCAQAUAwAAAA==.Arckadius:BAAALAAECgIIAgAAAA==.Ardend:BAAALAAECgYIEAAAAA==.Arrengel:BAAALAAECgQICQAAAA==.',As='Ashadon:BAAALAAECgUIBgAAAA==.Ashenne:BAABLAAECoEUAAIEAAgISgbOMgBYAQAEAAgISgbOMgBYAQAAAA==.Asterian:BAAALAAECgcIDwAAAA==.Asterionela:BAAALAAECgcIEQAAAA==.Astonhunt:BAAALAAECgYIEAAAAA==.Astonlock:BAAALAADCggIFAAAAA==.',Av='Avasarala:BAABLAAECoEXAAIFAAcIax0EJQBBAgAFAAcIax0EJQBBAgAAAA==.Avengerx:BAAALAAECgIIAgAAAA==.',Aw='Awoo:BAAALAAECgYIEAAAAA==.',Ba='Basphomet:BAAALAADCggICAABLAAECgcIEQAGAAAAAA==.',Be='Beerbelly:BAAALAAECgMIBQAAAA==.Before:BAAALAADCgcIDAABLAAECgcIEQAGAAAAAA==.Bekkey:BAAALAAECgcIEwAAAA==.Bellethanos:BAACLAAFFIEIAAQHAAMIsxSTBQCtAAAIAAIIgBG1EACuAAAHAAIIvxmTBQCtAAAJAAIIDRaVBACZAAAsAAQKgRgAAwkACAgsIN4EALYCAAkACAh4Ht4EALYCAAcACAjrGnQLADQCAAAA.Berdache:BAAALAAECgcIEQAAAA==.Bertrand:BAAALAAECgUICAAAAA==.Betrayer:BAAALAAECggIEwAAAA==.',Bl='Blightcall:BAABLAAECoEZAAMKAAcIMh6XEQAIAgAKAAYIzx2XEQAIAgALAAIIxRmrHwCeAAAAAA==.Blightmoore:BAAALAADCggICAAAAA==.Blinkhorn:BAAALAAECgYIDQAAAA==.Bloods:BAAALAADCgUICQAAAA==.',Bo='Bossdemon:BAAALAADCgUIBQABLAAECgYIBgAGAAAAAA==.Bossdragon:BAABLAAECoEeAAIMAAgIQiKpAwAwAwAMAAgIQiKpAwAwAwAAAA==.Bosspriest:BAAALAAECgYIBgAAAA==.',Br='Broly:BAAALAAFFAIIAgAAAA==.',['Bö']='Börjebula:BAAALAADCgcIBwAAAA==.',Ca='Cannibalize:BAABLAAECoEeAAMIAAgI/xvEIQBhAgAIAAgI/xvEIQBhAgAHAAMITQVjOABnAAAAAA==.',Ch='Chaseline:BAAALAADCgQIBAAAAA==.Chewbarka:BAABLAAECoEfAAINAAgIhCFUAgAaAwANAAgIhCFUAgAaAwAAAA==.Chibaron:BAAALAAECgcIDgAAAA==.',Ci='Cier:BAAALAADCggICQAAAA==.Ciri:BAABLAAECoEXAAIFAAcIrx1NJwA1AgAFAAcIrx1NJwA1AgAAAA==.',Cl='Clemency:BAAALAAECgMIBQAAAA==.',Co='Corix:BAAALAADCggICAAAAA==.Corlaa:BAABLAAECoEWAAMOAAgIERP6HAAoAgAOAAgIERP6HAAoAgAPAAYIYQb2cADaAAAAAA==.',Cr='Cratus:BAAALAAECgUIBgAAAA==.Croghailin:BAAALAAECgMIBQAAAA==.',Da='Dappledtree:BAAALAADCgcIDAAAAA==.Darkhallow:BAAALAAECgQIBAABLAAECggIHgADAGQhAA==.Darkhunter:BAABLAAECoEbAAIQAAgI1xswEgCfAgAQAAgI1xswEgCfAgAAAA==.Dawnflower:BAAALAAECgYIDwAAAA==.',De='Deathmike:BAAALAAECgYIEQAAAA==.Demodan:BAABLAAECoElAAIKAAgI4yCiAgACAwAKAAgI4yCiAgACAwAAAA==.',Di='Dihmon:BAABLAAECoEXAAIBAAcI3hauDgDQAQABAAcI3hauDgDQAQAAAA==.',Do='Dole:BAAALAADCgUIBQAAAA==.',Dr='Drakbert:BAAALAAECgcIDwAAAA==.Draxiah:BAAALAAECgMIBAAAAA==.Drazkon:BAAALAADCggIDwAAAA==.Dreaxan:BAAALAADCggICAAAAA==.Druidvirgin:BAAALAADCggIFAAAAA==.Drusanda:BAAALAADCgcIBwAAAA==.',Eb='Eblise:BAACLAAFFIEFAAIRAAMIbhWGBAALAQARAAMIbhWGBAALAQAsAAQKgRwAAhEACAi4G44KAKsCABEACAi4G44KAKsCAAAA.',Ec='Ecco:BAAALAAECgEIAgAAAA==.',Ed='Edofix:BAAALAADCggICgAAAA==.',Ei='Eiran:BAABLAAECoEdAAMOAAgIaSCVCgD2AgAOAAgIaSCVCgD2AgAPAAIINAUgogBEAAAAAA==.',El='Elenore:BAAALAADCggIFwAAAA==.Elowynn:BAAALAAECgMIAwAAAA==.',Ev='Evans:BAAALAAECgQICQAAAA==.',Fi='Fister:BAAALAADCgMIAwAAAA==.',Fl='Flaypenguin:BAAALAAFFAIIAgABLAAFFAQICAASAPciAA==.Flo:BAAALAAECgQIBQABLAAECgQIBgAGAAAAAA==.',Ga='Gangbo:BAAALAAECgMIBgAAAA==.Gazrul:BAAALAADCggICAAAAA==.',Ge='Getsugatensh:BAAALAAECgQIBQAAAA==.',Gh='Gharretth:BAAALAAECgIIAgAAAA==.',Gi='Gingerbread:BAAALAAECgYIBgAAAA==.',Gn='Gnarly:BAAALAAECgYIDAAAAA==.',Go='Goatface:BAABLAAFFIEGAAMDAAIIqxkBAQC2AAADAAIIqxkBAQC2AAATAAEIkA6FFQBQAAAAAA==.Goonst:BAAALAAECgEIAQAAAA==.',Gr='Grevoline:BAAALAAECgUIBQAAAA==.',Gu='Guthrik:BAAALAAECgYIDQAAAA==.',Ha='Hafthor:BAAALAAECgYIDQAAAA==.Hallowed:BAAALAAECgcIEQAAAA==.Hamdergert:BAAALAAECgYICgABLAAFFAMIBgAEABQRAA==.Hasslêhoof:BAAALAAECgYIBgAAAA==.',He='Hek:BAAALAAECgYIDQAAAA==.Hereboy:BAAALAAECgMIBQAAAA==.Hexanna:BAAALAAECgEIAQAAAA==.',Hi='Hickory:BAABLAAECoEXAAMUAAcI2RKfLgB4AQAUAAcI2RKfLgB4AQAEAAEIcwUhYwAxAAAAAA==.Hirani:BAAALAAECgYIDQAAAA==.',Ho='Hobow:BAAALAAECgYIDwAAAA==.',Hu='Hugorune:BAAALAAECgEIAQAAAA==.Huli:BAAALAAECgMIBQAAAA==.',['Hå']='Hårddreng:BAAALAADCggIDwAAAA==.',['Hó']='Hótalot:BAAALAAECgcIEQAAAA==.',Ic='Iceflower:BAAALAAECgIIAgAAAA==.',Ig='Igneo:BAAALAAECgYIEAAAAA==.',Il='Ilaria:BAABLAAECoEcAAIVAAgIHBzHBQCpAgAVAAgIHBzHBQCpAgAAAA==.Illuren:BAAALAAECgYIDwAAAA==.Ilphas:BAAALAADCgMIAgAAAA==.',Io='Ioni:BAAALAADCggIFwAAAA==.',Iv='Ivella:BAAALAADCgUIDAAAAA==.',Ja='Jaena:BAAALAADCggIFwAAAA==.Jayni:BAAALAAECgMIBQAAAA==.',Je='Jerzy:BAAALAADCggICwAAAA==.',Ji='Jiemierix:BAAALAAECgMIBQAAAA==.Jizy:BAAALAADCgcIEAAAAA==.Jizzly:BAAALAAECgYIEAAAAA==.',Jo='Jod:BAABLAAECoEdAAMHAAgIohSzDAAfAgAHAAgIERSzDAAfAgAIAAUIwAakkADTAAAAAA==.Jodders:BAAALAAECgMIBQAAAA==.',Ju='Jumanjí:BAAALAAECgcIDgAAAA==.',Ka='Kafi:BAAALAAECgYIDwABLAAECgYIEQAGAAAAAA==.Kafál:BAAALAAECgYIEQAAAA==.Karmael:BAABLAAECoEbAAIVAAgILxp1CQBoAgAVAAgILxp1CQBoAgAAAA==.',Ke='Kenatsa:BAAALAAECgMIAwABLAAECgYIDQAGAAAAAA==.',Kh='Khalfurion:BAABLAAECoEXAAIEAAgI9heNFABCAgAEAAgI9heNFABCAgAAAA==.Khialune:BAAALAAECgYIDQAAAA==.',Kl='Kledius:BAAALAADCggICwAAAA==.',Ko='Kodaan:BAAALAADCgcICAAAAA==.Kolkmonk:BAAALAADCggIDwAAAA==.',['Ká']='Káng:BAAALAADCgMIAwABLAAECgcIEAAGAAAAAA==.',La='Laochramóra:BAAALAADCggIFgAAAA==.Laphicet:BAAALAAECgYIDQAAAA==.',Le='Lessandre:BAAALAADCggICAAAAA==.Letum:BAAALAAECgIIAwAAAA==.Levimon:BAAALAAECggIDwAAAA==.Lexii:BAAALAAECgYIDwAAAA==.',Lh='Lhiip:BAAALAAECgIIAwAAAA==.',Li='Lightweight:BAAALAAECgMIAwAAAA==.',Lo='Lockstrider:BAAALAADCgYIBgABLAAECgcIDgAGAAAAAA==.',Ma='Maelstromike:BAAALAAECgYIBgABLAAECgYIEQAGAAAAAA==.Maeriko:BAACLAAFFIEFAAIWAAMIggH6BQCzAAAWAAMIggH6BQCzAAAsAAQKgR4AAhYACAgdFcgMABgCABYACAgdFcgMABgCAAAA.Maewynn:BAAALAADCggIDwAAAA==.Magickmike:BAAALAAECgQIBAABLAAECgYIEQAGAAAAAA==.Magnetica:BAAALAAECgEIAQAAAA==.Mak:BAAALAAECgYIDAAAAA==.Maksüno:BAAALAADCggICwABLAAECgcIEAAGAAAAAA==.Markahunt:BAAALAADCgcICAAAAA==.Maxlir:BAABLAAECoEWAAQTAAgIpxOdIgAFAgATAAgI6RKdIgAFAgAXAAIIIxdxOwB3AAADAAEI7g1qIwAzAAAAAA==.Mazoga:BAAALAAECgYICgAAAA==.',Me='Melephant:BAAALAADCgUIBQAAAA==.Mephi:BAAALAADCgMIAwAAAA==.',Mi='Miema:BAAALAADCgcIDAAAAA==.Milogor:BAAALAAECgMIBQAAAA==.Mirabeau:BAAALAADCgcICAAAAA==.Misrule:BAAALAADCggIFAAAAA==.',Mn='Mnee:BAAALAAECgQIBQAAAA==.',Mo='Morkvarg:BAABLAAECoEeAAILAAgIoh1rAQD4AgALAAgIoh1rAQD4AgAAAA==.',Mu='Musong:BAAALAAECgYIDQAAAA==.',Na='Nakedsnake:BAAALAADCgYIBgABLAAECgYIEQAGAAAAAA==.Natrey:BAAALAAECgYIEQAAAA==.Nazgrin:BAAALAADCgMIAwAAAA==.',Ne='Necalli:BAAALAADCggIDAAAAA==.Nemezis:BAAALAAECgcIEwAAAA==.',Ni='Nidhhogg:BAAALAAECgcIDwAAAA==.Nieve:BAAALAADCggIDwAAAA==.Niquil:BAAALAAECgEIAQAAAA==.Nivráthá:BAABLAAECoEYAAMKAAgIcRo4BwCMAgAKAAgIcRo4BwCMAgAYAAMIaA+UawCpAAAAAA==.Nixxar:BAABLAAECoEdAAISAAgIsCTNAwBhAwASAAgIsCTNAwBhAwAAAA==.',Ny='Nymdemon:BAAALAAECgMIBAAAAA==.Nyrelle:BAAALAAECgYICwAAAA==.',Ob='Obefix:BAAALAADCgIIAgAAAA==.',Od='Oddity:BAAALAADCgIIAgAAAA==.',Or='Ormandons:BAAALAAECgcIEAAAAA==.',Pa='Pakulia:BAAALAAECgcIDAAAAA==.Palastrider:BAAALAAECgQICQABLAAECgcIDgAGAAAAAA==.Pandem:BAAALAAECgYICwAAAA==.',Ph='Phos:BAAALAADCggIEAAAAA==.',Pr='Pretorius:BAABLAAECoEXAAITAAcIDgxoMgCfAQATAAcIDgxoMgCfAQAAAA==.Prevoker:BAACLAAFFIEFAAIMAAMIpQxGBgDqAAAMAAMIpQxGBgDqAAAsAAQKgRsAAgwACAhtGk8LAKMCAAwACAhtGk8LAKMCAAAA.',Qu='Queffa:BAABLAAECoEXAAIPAAgIghKVMQC5AQAPAAgIghKVMQC5AQAAAA==.Quellia:BAAALAAECgYIDwAAAA==.',Ra='Radahn:BAAALAAECgQICwAAAA==.Ralgon:BAAALAAECgIIAwAAAA==.',Re='Reave:BAAALAADCggICAABLAAECgcIEQAGAAAAAA==.Rexicorum:BAAALAAECgYIDQAAAA==.',Rh='Rhenna:BAAALAAECgYIDQAAAA==.',Ro='Ronshamson:BAAALAADCgYIBgAAAA==.Roythelan:BAABLAAECoEeAAIZAAgItBW4AgBAAgAZAAgItBW4AgBAAgAAAA==.',Ru='Runeblight:BAAALAAECgIIAgAAAA==.',Ry='Ryéhill:BAAALAAECgYIDQAAAA==.',Sa='Sanaivai:BAACLAAFFIEFAAIQAAIICA6UDQCaAAAQAAIICA6UDQCaAAAsAAQKgRwAAhAACAhfG34SAJwCABAACAhfG34SAJwCAAAA.Saneot:BAAALAAECgcIDAAAAA==.Sanguines:BAAALAAECgMIBAAAAA==.Sanrien:BAAALAAECgcIBwAAAA==.Saressa:BAAALAAECgYICQAAAA==.Saucysauce:BAAALAAECgYICgAAAA==.',Sc='Scorchbane:BAAALAADCggICQAAAA==.',Se='Seeren:BAAALAAECgYIEAAAAA==.',Sh='Shadowdemon:BAAALAADCgcICwAAAA==.Shadowlily:BAAALAAECgYIEAAAAA==.Shakarri:BAAALAAECgIIAgAAAA==.Shamsanda:BAABLAAECoEWAAIPAAgISBhoGgAzAgAPAAgISBhoGgAzAgAAAA==.Shamystrider:BAAALAAECgcIDgAAAA==.Shant:BAAALAADCggICAAAAA==.',Si='Sidenia:BAAALAADCgYIBgAAAA==.Silverbranch:BAAALAAECgcIDgAAAA==.Simosaki:BAAALAADCggIDwAAAA==.Sixseven:BAAALAAECgQIBgAAAA==.',Sk='Skyfall:BAABLAAECoEWAAQYAAgIIBtWFgB/AgAYAAgIIBtWFgB/AgAKAAIIHwwJVAB9AAALAAEIHgygMgA9AAAAAA==.Skyhope:BAAALAADCgYIBgAAAA==.',Sl='Sledgehammer:BAAALAAECgYIBgAAAA==.Sleipner:BAABLAAECoEaAAIJAAcIrCMaBADaAgAJAAcIrCMaBADaAgAAAA==.Slím:BAAALAAECgcIEQAAAA==.',Sm='Smíle:BAAALAADCgUICAAAAA==.',Sn='Sneb:BAAALAAECgIIAQAAAA==.',So='Solastra:BAAALAAECgYIDgAAAA==.',Sp='Spacejám:BAABLAAECoEeAAMaAAgI9xmIGQAvAgAaAAcImBuIGQAvAgAbAAQIqwPdWwCsAAAAAA==.Spunkmeyer:BAAALAADCgYIBgAAAA==.',St='Staggmatt:BAAALAAECgMIBQAAAA==.Stormrise:BAAALAADCgcIBwAAAA==.',Sy='Syhla:BAAALAAECgYIEAAAAA==.',Ta='Talana:BAAALAAECgIIAgABLAAECggIHgADAGQhAA==.Talneas:BAAALAAECgYIDAAAAA==.Tamaki:BAABLAAECoEWAAIFAAgIzB48EwDGAgAFAAgIzB48EwDGAgAAAA==.Tashrog:BAAALAADCggICAAAAA==.Taurances:BAAALAAECgYIDwAAAA==.',Te='Teremoo:BAAALAAECgMIBQAAAA==.',Th='Thoriata:BAAALAAECgYIDQAAAA==.Threretard:BAAALAADCggIIAAAAA==.',Ti='Tiiwaz:BAAALAADCggIFwAAAA==.Tinkerlight:BAAALAAECgMIBQAAAA==.Tinystark:BAAALAADCgEIAQAAAA==.',Tr='Trixzie:BAAALAADCggIEwAAAA==.',Ua='Uabhar:BAAALAAECgIIAgAAAA==.',Va='Vagner:BAAALAADCggICAAAAA==.Varunex:BAAALAAECgcIEgAAAA==.',Ve='Veklinash:BAAALAAECgQICQAAAA==.Versility:BAAALAADCgYIBwAAAA==.',Vo='Voidpete:BAAALAAECgYIBgAAAA==.Volgint:BAAALAADCgcIBwABLAAECgYIDQAGAAAAAA==.',Vy='Vyí:BAAALAADCgcICwAAAA==.',Wa='Wandi:BAAALAADCggIDgAAAA==.Warlocvirgin:BAAALAAECgMIBAAAAA==.',Wh='Whó:BAAALAADCgcIDAAAAA==.',Wi='Wittle:BAAALAAECgEIAQAAAA==.',Wo='Wolace:BAABLAAECoEUAAIcAAcIkQ6wBgDIAQAcAAcIkQ6wBgDIAQAAAA==.Woobs:BAACLAAFFIEGAAIEAAMIFBG2BADsAAAEAAMIFBG2BADsAAAsAAQKgRgAAgQACAguIfcIAOgCAAQACAguIfcIAOgCAAAA.Worze:BAAALAADCggIFgAAAA==.',Xa='Xav:BAAALAAECgMIBgAAAA==.',Ya='Yaria:BAAALAADCgMIAwAAAA==.',Yl='Yleera:BAAALAADCggIDAAAAA==.',Za='Zalaryndos:BAAALAADCggIFgAAAA==.Zandjil:BAABLAAECoEaAAMQAAgIjwxFMADQAQAQAAgIjwxFMADQAQAdAAcIIASTSQDlAAAAAA==.Zargon:BAAALAADCgcIBwAAAA==.',Ze='Zekeyeager:BAAALAADCgYIDAAAAA==.Zellida:BAACLAAFFIEFAAIBAAMIoyJ4AAA6AQABAAMIoyJ4AAA6AQAsAAQKgR4AAgEACAgtJeQAAGMDAAEACAgtJeQAAGMDAAAA.',Zo='Zork:BAAALAAECgMIAwAAAA==.',['Ûl']='Ûltra:BAAALAAECgYIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end