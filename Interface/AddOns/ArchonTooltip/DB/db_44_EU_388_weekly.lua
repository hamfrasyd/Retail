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
 local lookup = {'Priest-Holy','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Feral','Warlock-Demonology','DemonHunter-Havoc','Priest-Shadow','Warrior-Fury','Warrior-Arms','Warrior-Protection','DeathKnight-Blood','Mage-Frost','Warlock-Destruction','Warlock-Affliction','Priest-Discipline','Druid-Guardian','Hunter-Survival','Paladin-Protection','Mage-Arcane','Mage-Fire',}; local provider = {region='EU',realm="Throk'Feroth",name='EU',type='weekly',zone=44,date='2025-09-24',data={Ag='Agouéé:BAAALAAECgcICgAAAA==.Aguerros:BAABLAAECoEXAAIBAAgIQwnGTwByAQABAAgIQwnGTwByAQAAAA==.',Ai='Aiku:BAAALAADCgcIDQAAAA==.',Ak='Akirep:BAAALAADCgYIEQAAAA==.',Al='Alakaosy:BAAALAAECgUICAABLAAECggIEgACAAAAAA==.Alderion:BAAALAADCggIDgAAAA==.Alganuz:BAAALAADCgMIBAAAAA==.Alganûz:BAAALAADCgYIBgAAAA==.Alirea:BAABLAAECoEUAAMDAAYIHRpabQCmAQADAAYI8xlabQCmAQAEAAUI8BZPVQBJAQAAAA==.',Am='Amjed:BAAALAAECgcIBwAAAA==.',An='Animaz:BAAALAADCgMIAwAAAA==.Anjara:BAAALAADCgYIBgAAAA==.',Ao='Aonae:BAAALAAFFAIIAgAAAA==.',Ap='Aprila:BAAALAAECgYIBgABLAAFFAMICwAFAMcgAA==.',Ar='Arakhnor:BAAALAADCgcIEQAAAA==.Argusson:BAAALAAECgIIBAAAAA==.Arkhange:BAAALAADCgcIEQAAAA==.',Ba='Baboukfurtif:BAAALAADCgYIDAAAAA==.',Be='Benilol:BAAALAADCgUIBQAAAA==.',Bi='Biscotte:BAABLAAECoEYAAIGAAgIoxvoEwBuAgAGAAgIoxvoEwBuAgAAAA==.',Bl='Blackops:BAABLAAECoEWAAMHAAgI0xoRLAA+AgAHAAgI0xoRLAA+AgAIAAUIIQc+gADqAAAAAA==.Blackøps:BAAALAAECgYIEQAAAA==.Bloodyfest:BAAALAAECgcIEgAAAA==.',Bo='Bonjour:BAAALAADCgUIBQAAAA==.Bouglarun:BAAALAADCgYIBgAAAA==.Bouyah:BAAALAAECgYIEAAAAA==.',Br='Branchtordue:BAAALAADCgcICAAAAA==.Bruluxx:BAAALAAECgYIEgAAAA==.Brûk:BAAALAADCggICwAAAA==.',Bu='Bubbleneoobz:BAAALAAECgcIEwAAAA==.',Ca='Carritangue:BAAALAADCgYIBgAAAA==.',Ce='Celéthor:BAAALAADCgYIBgAAAA==.',Ch='Chamage:BAAALAADCggIDQAAAA==.Chance:BAABLAAECoEeAAIGAAYInBatLACtAQAGAAYInBatLACtAQAAAA==.Chassousacer:BAABLAAECoEYAAIDAAgI7BAfZQC6AQADAAgI7BAfZQC6AQAAAA==.Christoo:BAABLAAECoEjAAIJAAgIHR91IwDBAgAJAAgIHR91IwDBAgAAAA==.',Ci='Ciszo:BAAALAAECgIIAgAAAA==.',Cl='Clippyx:BAAALAADCgcIDQAAAA==.',Cr='Criçks:BAAALAADCggIGQAAAA==.',Cy='Cyraêlle:BAAALAADCgUIBwAAAA==.',['Cø']='Cøwax:BAAALAAECgQIBAAAAA==.',Da='Dardargnan:BAAALAAECgEIAQAAAA==.Darkeïge:BAAALAAECgQIBAAAAA==.Darkome:BAAALAAECgYIBgAAAA==.',Do='Dopainperdu:BAACLAAFFIEFAAIFAAIIhAwQGACKAAAFAAIIhAwQGACKAAAsAAQKgSUAAgUACAg9HbIVAJECAAUACAg9HbIVAJECAAAA.',Dr='Drakturd:BAAALAADCgcICgAAAA==.Druzo:BAAALAADCggIEAAAAA==.',Du='Duryk:BAACLAAFFIEGAAIDAAIIJx3dIgCeAAADAAIIJx3dIgCeAAAsAAQKgSQAAgMACAjnHgcfAK0CAAMACAjnHgcfAK0CAAAA.',['Dé']='Dédaria:BAACLAAFFIETAAIKAAUIGhsnBACvAQAKAAUIGhsnBACvAQAsAAQKgScAAgoACAjLJP4DADsDAAoACAjLJP4DADsDAAAA.Dékhanix:BAAALAAECgYIBgABLAAFFAUICgALAEMRAA==.Déshi:BAACLAAFFIEPAAIEAAUISRvUBgBkAQAEAAUISRvUBgBkAQAsAAQKgScAAgQACAj/Il4JABEDAAQACAj/Il4JABEDAAAA.Déshiré:BAAALAAECgcIEwAAAA==.',['Dø']='Dødâ:BAAALAAECgYIEAAAAA==.',El='Eléonia:BAAALAAECgYICwAAAA==.',Es='Eskanor:BAAALAADCggIDwAAAA==.',Eu='Eucalÿptus:BAABLAAECoEaAAIMAAgI4xjSEwA/AgAMAAgI4xjSEwA/AgAAAA==.',Ey='Eyoha:BAAALAADCggICwAAAA==.',Fa='Facerol:BAAALAAECgYIEgAAAA==.Fafnyr:BAAALAAECgcIDQAAAA==.Fayez:BAACLAAFFIEJAAINAAUIzgwwCgCNAQANAAUIzgwwCgCNAQAsAAQKgSAAAg0ACAjPIOQeAMoCAA0ACAjPIOQeAMoCAAAA.',Fb='Fbzottoute:BAAALAADCgcIEgAAAA==.',Fe='Federig:BAABLAAECoEiAAILAAgI2iPOAgA7AwALAAgI2iPOAgA7AwAAAA==.',Ff='Ffooxx:BAAALAADCgYIBgAAAA==.',Fi='Fileali:BAABLAAECoEYAAIBAAYIkBPxTgB2AQABAAYIkBPxTgB2AQAAAA==.Fistoules:BAAALAADCgcIBwAAAA==.',Fl='Flaune:BAAALAAECgQIBAAAAA==.Fleurdoré:BAAALAAECgYIEwAAAA==.',Fo='Fouzitout:BAAALAADCggICAAAAA==.',Fr='Frekence:BAAALAAECgQIBAAAAA==.',Fu='Fugart:BAAALAAECgYIBgAAAA==.',['Fæ']='Fæli:BAAALAADCgcIDAAAAA==.Fælys:BAAALAADCgUIBQAAAA==.',['Fö']='Föx:BAAALAADCgYICwAAAA==.',Ga='Galwishe:BAABLAAECoEbAAIDAAYIaBB/lABVAQADAAYIaBB/lABVAQAAAA==.',Go='Goldor:BAAALAAECgYIDQAAAA==.Gon:BAAALAAECggIEwABLAAFFAIIAgACAAAAAA==.',Gr='Grimggor:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.Grooke:BAAALAADCggICAABLAAECgYIEgACAAAAAA==.Grômkan:BAAALAAECgUIBQABLAAECgYICwACAAAAAA==.',Ha='Hagaëb:BAAALAAECggIDgAAAA==.Hagrog:BAAALAAECggICAAAAA==.Happyy:BAAALAADCgcIDQAAAA==.Haresse:BAAALAAECgUIBQABLAAECgYIGAABAJATAA==.',He='Heima:BAAALAADCgQIBAAAAA==.Herasède:BAAALAADCgUIBQAAAA==.',Ho='Hok:BAABLAAECoEVAAIJAAgIRQczvQBLAQAJAAgIRQczvQBLAQAAAA==.',Hy='Hyunae:BAAALAADCggICgAAAA==.',In='Inoj:BAAALAAFFAIIBAAAAA==.',Ja='Jacøcculte:BAAALAADCgcICgAAAA==.Jacøsan:BAAALAAECgYIBgAAAA==.',Jh='Jhinsohya:BAAALAAECgYICQAAAA==.',Jo='Jolithorax:BAAALAAECgcIEgAAAA==.Jonluk:BAAALAAECgUIBQABLAAECgcIGgAOAAgjAA==.Joyboy:BAABLAAECoEaAAIPAAgIHxOGQgD5AQAPAAgIHxOGQgD5AQABLAAFFAUICwAPADscAA==.',Ju='Julciléa:BAABLAAECoEUAAIDAAYIfBWSgAB9AQADAAYIfBWSgAB9AQAAAA==.',['Jæ']='Jæz:BAAALAADCggICAAAAA==.',['Jï']='Jïm:BAAALAAECggIDgAAAA==.',Ka='Kaelista:BAAALAAECgYIDQAAAA==.Kaelysta:BAAALAAECgYICQAAAA==.Kamazinz:BAACLAAFFIEIAAIJAAII+BOmKwChAAAJAAII+BOmKwChAAAsAAQKgSsAAgkACAhWIskXAP0CAAkACAhWIskXAP0CAAAA.',Ke='Keupstorm:BAABLAAFFIEFAAINAAIIFQtnOACLAAANAAIIFQtnOACLAAAAAA==.',Kh='Khesh:BAACLAAFFIEWAAQQAAYIvR1PAACoAQAPAAYIPhYKBwDQAQAQAAQIkiNPAACoAQARAAQIFA/NBgAVAQAsAAQKgS8ABBAACAjfJZMAAHQDABAACAjdJZMAAHQDAA8ABgi4IcktAFECABEACAjkH9sWAEwCAAAA.',Ki='Kilui:BAAALAAECgQIBAAAAA==.',Ko='Koroma:BAABLAAECoEVAAISAAgI4QbTIQAzAQASAAgI4QbTIQAzAQAAAA==.Koub:BAAALAADCgYIBgAAAA==.',Kr='Krèk:BAAALAADCggIEAAAAA==.',Kt='Ktos:BAABLAAECoEXAAITAAcIJhkgGwAcAgATAAcIJhkgGwAcAgAAAA==.',Ku='Kuhaku:BAAALAADCgcIBwAAAA==.',La='Lannrogue:BAAALAAECgYIDAABLAAFFAIIAgACAAAAAA==.Lathspell:BAAALAADCgMIAwAAAA==.Layu:BAAALAAFFAIIAgAAAA==.',Le='Leftorie:BAABLAAECoEoAAIFAAgIaRvHHABQAgAFAAgIaRvHHABQAgAAAA==.Legna:BAABLAAECoEeAAQUAAcIiRoNNgA1AgAUAAcIdBoNNgA1AgAMAAQIKQoUXADRAAAVAAIIbA7NLQBrAAAAAA==.Levlevrai:BAABLAAECoEeAAIPAAcIURvEPAAQAgAPAAcIURvEPAAQAgAAAA==.',Li='Lifebløøm:BAAALAAECggICAAAAA==.',Lo='Louvetia:BAAALAADCgUIBQAAAA==.',Lu='Ludgex:BAAALAADCggIEwAAAA==.',Ly='Lythom:BAAALAAECgQICQAAAA==.',['Lø']='Løck:BAAALAAECgcIEgAAAA==.',Ma='Malephique:BAAALAAECgYIDAAAAA==.Mandolyne:BAABLAAECoEYAAIWAAYIBR3fCAD3AQAWAAYIBR3fCAD3AQAAAA==.Maoif:BAAALAAECgYICgAAAA==.Maooh:BAAALAAFFAIIBAAAAA==.Marlëÿ:BAAALAAECgYICwAAAA==.Maszo:BAAALAADCgYIBgAAAA==.',Mc='Mcwald:BAAALAADCggICAAAAA==.',Me='Mega:BAABLAAECoEVAAMFAAYIHwqMWwANAQAFAAYIHwqMWwANAQAKAAYIfQnFdAD5AAABLAAFFAIICQAJAD8RAA==.Meline:BAABLAAECoEeAAIHAAcIwh6dJQBZAgAHAAcIwh6dJQBZAgAAAA==.Mercurochrom:BAAALAADCggIDwAAAA==.',Mi='Mistik:BAAALAAECgQIBAAAAA==.',Mo='Moka:BAAALAAECggICAAAAA==.',My='Mykouze:BAAALAADCgcIBwAAAA==.',['Mä']='Märlëÿ:BAAALAAECgYIDwAAAA==.',['Mé']='Mékhamiaou:BAAALAAECgYIBgABLAAFFAUICgALAEMRAA==.Mékhanix:BAACLAAFFIEKAAILAAUIQxF1AgCKAQALAAUIQxF1AgCKAQAsAAQKgRcABAUACAiXIogfADkCAAUABgjoIogfADkCAAsABgj7HvsQABoCABcAAQgaICMoAF4AAAAA.',['Mí']='Mílanó:BAAALAAECgEIAgAAAA==.',['Mü']='Müwen:BAAALAADCggIDwAAAA==.',Na='Nalivendälle:BAAALAADCggICQAAAA==.',Ne='Neoo:BAABLAAECoEWAAIPAAYI1xvySADiAQAPAAYI1xvySADiAQAAAA==.Neoobz:BAAALAAECgYIBgABLAAECgYIFgAPANcbAA==.Nezuko:BAAALAADCgcICgAAAA==.',No='Noctua:BAAALAADCggICAAAAA==.Nokomi:BAAALAADCgMIBAAAAA==.Noltaz:BAAALAADCgYIBgAAAA==.Nolys:BAAALAADCgcIEQAAAA==.',Ny='Nymoria:BAAALAAECgYIDwAAAA==.',['Nô']='Nôji:BAABLAAECoEhAAMMAAcIcSGlCQCxAgAMAAcIcSGlCQCxAgAUAAYI6hlAWQCxAQAAAA==.',Ou='Oural:BAABLAAECoEYAAIHAAYI/Rg9igAxAQAHAAYI/Rg9igAxAQAAAA==.Ousuije:BAAALAADCggIEAAAAA==.',Ox='Oxidan:BAAALAADCgYIBgAAAA==.',Pa='Pandahanne:BAAALAAECgQICQAAAA==.Paraphon:BAAALAAFFAIIAgAAAA==.',Ph='Phumera:BAABLAAECoEUAAIPAAgIHBJTVQC5AQAPAAgIHBJTVQC5AQAAAA==.Phumisterie:BAAALAADCggICAAAAA==.',Pi='Pi:BAAALAADCggICAABLAAECggIIQADAOsmAA==.Pilope:BAAALAAECgYICQAAAA==.',Po='Poppykline:BAABLAAECoEiAAIMAAcImCATDACQAgAMAAcImCATDACQAgAAAA==.',Pr='Pralïne:BAABLAAECoEZAAINAAcIhR3VOABTAgANAAcIhR3VOABTAgAAAA==.Prayføryou:BAAALAADCgIIAgAAAA==.',Ps='Psychí:BAAALAAECgMIBwAAAA==.',Qu='Quietotem:BAAALAADCgQIBQABLAAECggIHwAOAKIcAA==.Quietpeace:BAAALAADCggIBQABLAAECggIHwAOAKIcAA==.Quietpriest:BAABLAAECoEfAAMOAAgIohxkGQCKAgAOAAgIohxkGQCKAgABAAEIDAgypgAtAAAAAA==.Quietsham:BAAALAADCggIDgABLAAECggIHwAOAKIcAA==.',Re='Rez:BAAALAADCgcICAABLAAFFAIIBwAMAFoGAA==.',Ro='Rolpala:BAAALAAECgUIBQAAAA==.',Sa='Sacreb:BAAALAAECggIEwAAAA==.Saradomin:BAAALAAECgYIEgAAAA==.',Sc='Scarr:BAAALAADCgYIDAAAAA==.Schaerbee:BAAALAADCggIDwAAAA==.Schokola:BAAALAADCgcIEQAAAA==.',Se='Selfette:BAABLAAECoEiAAIDAAYI6B4kWgDUAQADAAYI6B4kWgDUAQAAAA==.Septquatre:BAAALAAECgYICgAAAA==.Seravee:BAAALAAECgMIBQAAAA==.',Sf='Sfyle:BAAALAADCggICAABLAAECggIHQABAFMaAA==.',Sh='Shinigamî:BAAALAADCgYIBgABLAADCgYIBgACAAAAAA==.Shintaro:BAAALAADCgYIBgAAAA==.Shinzoo:BAAALAAECgUIDQAAAA==.',Si='Sinøk:BAAALAADCggIEAAAAA==.',Sk='Sknder:BAACLAAFFIEdAAIHAAYIPBl7AgD+AQAHAAYIPBl7AgD+AQAsAAQKgSgAAgcACAjNIt0OANsCAAcACAjNIt0OANsCAAAA.Skndër:BAABLAAECoEgAAIBAAcI+hx3HQBtAgABAAcI+hx3HQBtAgAAAA==.',Sp='Spamolol:BAAALAAFFAIIAgABLAAFFAMIBQAEAEoLAA==.Spamøoøoøoøo:BAACLAAFFIEFAAIEAAMISgtJEwCvAAAEAAMISgtJEwCvAAAsAAQKgS0AAgQACAjRE/kyANsBAAQACAjRE/kyANsBAAAA.Spyros:BAAALAADCgcIBwAAAA==.',['Sé']='Sékis:BAAALAADCggIDwAAAA==.',['Sð']='Sðul:BAAALAADCgIIAgABLAAECgMIBwACAAAAAA==.',Ta='Tahor:BAAALAAECgEIAQAAAA==.Tayu:BAACLAAFFIEPAAIYAAQIASVrAACvAQAYAAQIASVrAACvAQAsAAQKgSYAAhgACAi8JhsAAJUDABgACAi8JhsAAJUDAAAA.',Te='Terock:BAAALAADCgcIBwAAAA==.',Th='Thaelys:BAAALAADCgYIBgAAAA==.Thaïny:BAAALAAECgYIBgAAAA==.',Ti='Tigouane:BAAALAAECgYIDAAAAA==.Tijacmur:BAACLAAFFIEHAAMMAAIIWgaHFQCLAAAMAAIIWgaHFQCLAAAUAAIISAIHPABsAAAsAAQKgSQABAwACAgTGasbAP8BAAwABggfG6sbAP8BABQABQicCYCiAOEAABUAAgjuEhsnAJQAAAAA.Timaljk:BAAALAAECggICAAAAA==.Tiscaz:BAAALAAECgYICwAAAA==.',To='Torgar:BAAALAADCggICAABLAAECggIEwACAAAAAA==.',Tr='Troctroc:BAAALAAECgUIBQAAAA==.',Tw='Twitchothory:BAAALAADCgcICAAAAA==.',['Tï']='Tïtania:BAAALAAECgYIBwAAAA==.',Va='Vaillants:BAAALAADCggIEgAAAA==.Vaërus:BAAALAADCggICAAAAA==.',Ve='Vellevache:BAABLAAECoEZAAMXAAcINx9FBgB0AgAXAAcINx9FBgB0AgALAAUIVARVMwCaAAAAAA==.',['Vä']='Välmont:BAAALAADCggIDwAAAA==.',Wa='Warrh:BAAALAADCggICAAAAA==.',Xl='Xlow:BAABLAAECoEWAAMZAAgI9BPjGwDiAQAZAAgI9BPjGwDiAQAJAAEIUwQ3RwErAAAAAA==.',Xt='Xtasy:BAACLAAFFIEOAAIaAAUIbyLpDwB0AQAaAAUIbyLpDwB0AQAsAAQKgSoAAxoACAi8IhkQABMDABoACAi8IhkQABMDABsAAQi+IM8eADUAAAAA.Xtremz:BAAALAADCgEIAQAAAA==.',Ya='Yaxe:BAAALAAECgYIDQAAAA==.',Yo='Youlounet:BAABLAAECoEcAAIXAAcIWCD2BQB/AgAXAAcIWCD2BQB/AgAAAA==.Youshia:BAAALAAECgYIBgAAAA==.',Yu='Yuukii:BAAALAAECgYIBgAAAA==.',['Yù']='Yùme:BAAALAADCgYICQAAAA==.',Za='Zafi:BAAALAADCggIDwAAAA==.Zafinâ:BAAALAAECgYIBgAAAA==.Zafî:BAAALAAECgcICQAAAA==.Zafîna:BAAALAADCggIDwAAAA==.Zambrozat:BAAALAADCgQIBAABLAAFFAIIBwAMAFoGAA==.Zaphy:BAAALAADCggIDgAAAA==.Zapike:BAAALAADCgEIAQAAAA==.Zavafermal:BAAALAADCggICAAAAA==.Zavaouquoi:BAAALAAECgUIBQAAAA==.',['Zé']='Zéldorus:BAAALAADCgMIAwAAAA==.Zéphira:BAAALAADCgYIBgAAAA==.',['Ëz']='Ëzea:BAAALAAECgYIDAAAAA==.',['Ïl']='Ïllïdan:BAAALAADCgUIBQAAAA==.',['Ðe']='Ðexter:BAAALAAECgYIEQAAAA==.',['Ôu']='Ôunagui:BAABLAAECoEaAAIHAAgIvSFmDQDlAgAHAAgIvSFmDQDlAgAAAA==.',['ßã']='ßãtmãñgøðx:BAAALAADCggICAAAAA==.',['ßò']='ßòòm:BAAALAAECgYIDQAAAA==.',['ßö']='ßööm:BAAALAAECgEIAQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end