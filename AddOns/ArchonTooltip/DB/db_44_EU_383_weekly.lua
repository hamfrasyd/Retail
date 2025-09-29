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
 local lookup = {'Paladin-Retribution','Unknown-Unknown','Priest-Discipline','Shaman-Restoration','Priest-Holy','DemonHunter-Havoc','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Elemental','Druid-Balance','Paladin-Protection','DeathKnight-Frost','DeathKnight-Blood','Priest-Shadow','Druid-Restoration','Warrior-Protection','Warrior-Fury','Priest-Healing','Warlock-Demonology','Warlock-Destruction','Mage-Fire','Paladin-Holy','Mage-Frost','Druid-Guardian',}; local provider = {region='EU',realm='Rashgarroth',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ab='Abhaya:BAAALAADCggIEAAAAA==.',Ag='Agapee:BAAALAAECgMIAwAAAA==.',Al='Alfonççeur:BAAALAADCgIIAgAAAA==.Altanaïr:BAAALAAECgYICgABLAAECggIKgABAAchAA==.',Am='Amenadiell:BAAALAAFFAUIFQAAAQ==.Amogue:BAAALAAECgEIAQABLAAFFAUIFQACAAAAAQ==.',An='Ankle:BAAALAADCgcIBwAAAA==.Annäk:BAAALAADCgYIBwAAAA==.Any:BAAALAADCgcIBwAAAA==.',Ar='Archaos:BAAALAADCgYIBgABLAAECgcIIQADAOgfAA==.Arthuros:BAAALAAECgUIBQAAAA==.Artoss:BAAALAAECggIDQAAAA==.Artöss:BAABLAAECoE5AAIEAAgIgx7qHACDAgAEAAgIgx7qHACDAgAAAA==.',['Aë']='Aëlnara:BAACLAAFFIETAAIFAAUIYBEIBwCLAQAFAAUIYBEIBwCLAQAsAAQKgSwAAgUACAg2IMgPANQCAAUACAg2IMgPANQCAAAA.',Ba='Basmet:BAAALAAECgQICgAAAA==.Bassecote:BAAALAAFFAIIAgAAAA==.',Bb='Bbgregore:BAAALAAECgYICwABLAAECggIIwAGADcaAA==.',Bg='Bgreggore:BAAALAAECgYIEgABLAAECggIIwAGADcaAA==.Bgregoraa:BAAALAADCggIEQABLAAECggIIwAGADcaAA==.Bgregore:BAABLAAECoEjAAIGAAcINxoNTgANAgAGAAcINxoNTgANAgAAAA==.',Br='Branbylon:BAAALAADCgMIAwAAAA==.Brigatmicron:BAAALAADCggIFwAAAA==.Brisingr:BAAALAAECgcICAAAAA==.',Ca='Cassetibiat:BAAALAADCgcIBwAAAA==.Castella:BAAALAAECgcICwAAAA==.',Ch='Chaûssette:BAAALAADCggIJgABLAAECgcIEAACAAAAAA==.Chupideamon:BAAALAAECgYIDAABLAAECggIJQAHABgaAA==.Chupimord:BAABLAAECoElAAMHAAgIGBpkBQBkAgAHAAgIGBpkBQBkAgAIAAYInQw0awD/AAAAAA==.Chïefthunder:BAAALAAECgYIEgAAAA==.',Cl='Claudy:BAAALAAECgYIBgAAAA==.',Cr='Crokette:BAAALAADCggICAABLAAFFAUIDAABAIwgAA==.',De='Demoby:BAAALAAECgcICwAAAA==.',Di='Diennain:BAAALAAECgYIEgAAAA==.Dienno:BAAALAAECgYICAAAAA==.',Do='Dodolina:BAAALAADCggIBQAAAA==.',Dr='Dracochupi:BAAALAAECgIIAgABLAAECggIJQAHABgaAA==.Drakastrasza:BAAALAAECggIDwAAAA==.Drazhal:BAAALAAECgIIAgABLAAECgYIBgACAAAAAA==.',Ds='Dsemoor:BAAALAADCggIEQAAAA==.',Ei='Eileen:BAAALAAECgUIEgAAAA==.',El='Elelalarera:BAAALAAECgEIAQAAAA==.',Em='Emäne:BAACLAAFFIETAAMJAAUIvhIaAQCrAQAJAAUIvhIaAQCrAQAEAAEIVQAGVAAeAAAsAAQKgSsAAwkACAh0JF0BAEMDAAkACAh0JF0BAEMDAAQACAgBBJikAPoAAAAA.',En='Enclûme:BAAALAAECgYIBgABLAAECgcIEAACAAAAAA==.',Er='Erkaë:BAAALAADCgcIBwAAAA==.',Ey='Eyko:BAAALAADCgUIBQAAAA==.',Fe='Feemdemon:BAAALAADCggIGAAAAA==.Fendribeer:BAAALAAECgYICAAAAA==.',Fi='Fizkefaaz:BAABLAAECoEYAAIBAAcIlh4fRgA/AgABAAcIlh4fRgA/AgAAAA==.',Fl='Flørthas:BAAALAADCgcIBwAAAA==.',Fo='Foxjing:BAAALAADCgYIBgAAAA==.',Fr='Frag:BAAALAAECgcIEwAAAA==.',Ga='Gallia:BAAALAAECgYIDgAAAA==.Gaïa:BAABLAAECoEcAAMKAAgIUxjkJwBRAgAKAAgIUxjkJwBRAgAEAAEIzwPAGgEdAAAAAA==.',Gi='Gimiekiss:BAAALAADCggIEAAAAA==.',Gy='Gyo:BAAALAAECgIIAgAAAA==.Gypox:BAAALAAECgYICAAAAA==.',Ha='Hartoss:BAAALAAECgYIBgAAAA==.Hazumi:BAAALAAECgYIDAABLAAECgcIIQADAOgfAA==.',He='Healmoibibi:BAAALAADCgcIBwABLAAFFAMICwALAMYWAA==.Heroneus:BAAALAADCggICgAAAA==.Hethari:BAAALAADCggICAAAAA==.',Ho='Holardus:BAAALAADCggIHQAAAA==.',Hy='Hylune:BAAALAAECgEIAQAAAA==.',Ic='Iceko:BAAALAAECgIIAgABLAAECgcIHwAMAG0cAA==.Icekonen:BAABLAAECoEfAAIMAAcIbRzhHADYAQAMAAcIbRzhHADYAQAAAA==.',Im='Immortalius:BAABLAAECoEbAAMNAAcIBxzqZwDyAQANAAcIhhrqZwDyAQAOAAQIXxQZLQDDAAABLAAECggIDwACAAAAAA==.',Ja='Jacknill:BAAALAAECgYIBgAAAA==.',Ka='Kafrina:BAAALAADCgcIBwAAAA==.Karolika:BAABLAAECoEcAAIEAAcIXg5OfQBOAQAEAAcIXg5OfQBOAQAAAA==.Kawaah:BAAALAADCgcIGwABLAAECgEIAQACAAAAAA==.Kawabomba:BAAALAADCgcIFwABLAAECgEIAQACAAAAAA==.Kawadractha:BAAALAADCggIEQAAAA==.Kawakawa:BAAALAAECgEIAQAAAA==.Kawamamba:BAAALAADCggIEwABLAAECgEIAQACAAAAAA==.',Ke='Kezome:BAAALAADCggIDQAAAA==.',Ki='Kiros:BAAALAADCggIEwAAAA==.',Kl='Klug:BAAALAADCgcICwABLAAECgcIHAAEAF4OAA==.',Ko='Kokabiel:BAAALAAECgEIAQAAAA==.',Kr='Krakhorn:BAAALAADCgUIBwAAAA==.Kronakaï:BAABLAAECoEmAAIPAAgIgxvtGwB1AgAPAAgIgxvtGwB1AgAAAA==.Kroubou:BAAALAAECgYIEAAAAA==.',La='Lancetre:BAABLAAECoEZAAIPAAYIRBGwRwB1AQAPAAYIRBGwRwB1AQAAAA==.Lauryne:BAABLAAECoEcAAMQAAYIlh3dLgD3AQAQAAYIlh3dLgD3AQALAAQIPAdbcQCgAAABLAAECggIJQAHABgaAA==.',Le='Lebôn:BAAALAADCgEIAQAAAA==.',Li='Lightalius:BAAALAADCgEIAQAAAA==.Linorias:BAAALAADCgIIAgAAAA==.',Lu='Luxunofwu:BAAALAAECgYIDgAAAA==.',Ma='Maasdormu:BAAALAADCggIGQAAAA==.Maudïte:BAAALAAECggICQAAAA==.',Mi='Minïpati:BAAALAADCgYIBgAAAA==.',Mu='Muthlon:BAAALAAECgYIBwAAAA==.Muthraad:BAAALAADCgUIBQABLAAFFAUIFQACAAAAAQ==.',My='Myria:BAAALAAECgQIBgAAAA==.',['Mé']='Méluzyne:BAABLAAECoEgAAIQAAcIJBtqPAC4AQAQAAcIJBtqPAC4AQAAAA==.',Na='Nabräd:BAABLAAECoEdAAMRAAgIIhjEKgCyAQARAAcI/xrEKgCyAQASAAYImwfGnADgAAAAAA==.Nax:BAAALAAECgcIEQAAAA==.',Ni='Nico:BAAALAAECgIIAgAAAA==.',No='Nodoka:BAAALAADCggIFgAAAA==.',Ob='Obak:BAABLAAECoEUAAISAAgINSDBGwC/AgASAAgINSDBGwC/AgAAAA==.',Or='Orcbölg:BAAALAAECgQIDQAAAA==.',Pa='Parcoeur:BAAALAAECgQICQAAAA==.',Pi='Pitipenda:BAAALAAECgcIEwAAAA==.',Po='Polnedra:BAAALAAECgYIEwAAAA==.Poulpitus:BAABLAAECoElAAIBAAgI9R4WJAC+AgABAAgI9R4WJAC+AgAAAA==.',['Pä']='Pänørãmîxøø:BAAALAADCgYIBgABLAAECgMIAgACAAAAAA==.',Qu='Quasar:BAAALAAECgUIEgAAAA==.',Ra='Raashgaroth:BAABLAAECoEgAAIQAAgIcyXUAQBfAwAQAAgIcyXUAQBfAwABLAAFFAUIBQATAK0hAA==.Ragnnar:BAAALAADCgYIBgAAAA==.Ravachole:BAAALAADCggICAAAAA==.',Rh='Rhoetas:BAAALAAECgYICgAAAA==.',Ri='Ridback:BAAALAAECgEIAQAAAA==.Rindaman:BAABLAAECoEUAAISAAYIiBfZVgC0AQASAAYIiBfZVgC0AQAAAA==.',Ro='Rocket:BAAALAADCgMIAwABLAAECgYIDwACAAAAAA==.Rokumine:BAAALAADCggICQAAAA==.Romsh:BAAALAADCggICAAAAA==.',Ry='Rynor:BAAALAADCgYIBgAAAA==.',['Rô']='Rôxxane:BAAALAAECgYIDwAAAA==.',['Rø']='Røxxànne:BAAALAAECgYIDgAAAA==.',Sa='Sachi:BAABLAAECoEhAAIDAAcI6B/oAwCGAgADAAcI6B/oAwCGAgAAAA==.Salcon:BAACLAAFFIEFAAIUAAIIHRSyDQCiAAAUAAIIHRSyDQCiAAAsAAQKgSkAAxQACAipH9sHAM4CABQACAipH9sHAM4CABUAAghzDtrMAFUAAAAA.Sarkas:BAAALAADCggICAABLAAFFAUIFQACAAAAAQ==.',Sc='Schrodinger:BAAALAAECgYIDgABLAAECggIGAAWAEobAA==.',Se='Selkis:BAABLAAECoEUAAIPAAYIbxi+OAC+AQAPAAYIbxi+OAC+AQAAAA==.',Sh='Shamaladin:BAACLAAFFIEGAAIXAAIIiSM2DQDFAAAXAAIIiSM2DQDFAAAsAAQKgR8AAhcACAj6H3EIAMwCABcACAj6H3EIAMwCAAAA.Shinratensei:BAAALAAECgYIBgAAAA==.',Sk='Skiadram:BAAALAADCgcIBwABLAAECgIIAQACAAAAAA==.',Sl='Sltatous:BAAALAADCgMIAwAAAA==.',Su='Submoneyy:BAAALAADCgEIAQAAAA==.Submôney:BAAALAADCgMIBAAAAA==.',Sy='Sylpheed:BAAALAADCggIFwAAAA==.',['Sï']='Sïgmar:BAAALAAECgYIBgAAAA==.',Ta='Tagtag:BAAALAAECgcIEgAAAA==.',Te='Texfists:BAAALAADCggIEAABLAAFFAUIFQACAAAAAQ==.',Th='Thelassir:BAABLAAECoEiAAMXAAgIuhTfHAD9AQAXAAgIuhTfHAD9AQABAAIIRASSKwFVAAAAAA==.',To='Toitucreuses:BAAALAAECgEIAQAAAA==.',Tr='Trunkss:BAAALAADCggIDgAAAA==.',Tu='Tundershaman:BAAALAAECgIIBAAAAA==.',Ty='Tyaline:BAAALAADCgQIBAAAAA==.',Ur='Uriã:BAAALAAECgYICgAAAA==.Uriãã:BAAALAADCgYIBgAAAA==.',Ve='Veldeptus:BAAALAAECgUIDQAAAA==.Versaillis:BAAALAAECgMIAwAAAA==.',Vi='Viineas:BAAALAADCgIIAgAAAA==.',Vo='Voljans:BAABLAAECoEtAAIVAAgIRRf+NwAtAgAVAAgIRRf+NwAtAgAAAA==.',Vu='Vulcapal:BAABLAAECoEqAAIBAAgIByHGKwCcAgABAAgIByHGKwCcAgAAAA==.',['Vî']='Vîrgin:BAAALAAECggIEAAAAA==.',Wa='War:BAAALAAECggIAgAAAA==.',We='Wenguette:BAAALAAECgcIEwAAAA==.',Wi='Winnilourson:BAAALAADCgcIBwAAAA==.Wirden:BAAALAAECgYIBgABLAAECgcIGAAFAEsWAA==.',Yo='Yodidi:BAAALAADCgYICwAAAA==.Yonî:BAAALAADCgcIBwAAAA==.',['Yø']='Yøndû:BAAALAADCgYICgAAAA==.',Za='Zangÿa:BAABLAAECoEhAAIYAAcIZCCjEgBsAgAYAAcIZCCjEgBsAgAAAA==.',Ze='Zendosh:BAABLAAECoEeAAIGAAgIwx0hKgCSAgAGAAgIwx0hKgCSAgAAAA==.',Zy='Zylumé:BAAALAAECgEIAQABLAAECgcIHwAMAG0cAA==.',['Áe']='Áeris:BAAALAAECggICQAAAA==.',['Îc']='Îchigo:BAAALAAECgMIBAABLAAECgYIEAACAAAAAA==.',['Ðo']='Ðoul:BAAALAAECgIIAgAAAA==.',['Ói']='Óin:BAABLAAECoEYAAIRAAYI+BnOKwCrAQARAAYI+BnOKwCrAQAAAA==.',['ßo']='ßoom:BAABLAAECoEXAAMZAAgIehrLCAAsAgAZAAYI0iDLCAAsAgALAAIIcQcAAAAAAAAAAA==.',['ßõ']='ßõõm:BAAALAAECgYICwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end