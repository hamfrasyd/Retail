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
 local lookup = {'Shaman-Elemental','Hunter-Marksmanship','Paladin-Retribution','Mage-Arcane','Mage-Frost','Paladin-Holy','DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Druid-Feral','Druid-Restoration','Druid-Guardian','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Assassination','DeathKnight-Frost','Warlock-Destruction','Evoker-Preservation','Shaman-Restoration','Druid-Balance','DeathKnight-Unholy','Monk-Brewmaster','Warrior-Fury','DeathKnight-Blood','Priest-Shadow','Evoker-Devastation','Paladin-Protection','Shaman-Enhancement','Warlock-Demonology','Monk-Windwalker','Mage-Fire','Priest-Holy','Monk-Mistweaver','Warlock-Affliction','Warrior-Protection','Priest-Discipline',}; local provider = {region='EU',realm='Krasus',name='EU',type='weekly',zone=44,date='2025-09-24',data={Ad='Adael:BAAALAAECgEIAQAAAA==.Adaonna:BAABLAAECoEhAAIBAAgI/xznFwC9AgABAAgI/xznFwC9AgAAAA==.Adlana:BAABLAAECoEdAAICAAcInhfnNgDHAQACAAcInhfnNgDHAQAAAA==.',Ae='Aecro:BAAALAADCggICAABLAAECggIHgADAP0VAA==.Aeglos:BAACLAAFFIEGAAIEAAIIJxqOLgCfAAAEAAIIJxqOLgCfAAAsAAQKgS4AAwUACAjAIQgSAHICAAQACAiSIV0uAHcCAAUABwhSIQgSAHICAAAA.Aenonis:BAAALAADCggIFwAAAA==.Aeriis:BAAALAAECgUICQAAAA==.Aerris:BAAALAAECgMIAwAAAA==.',Ag='Agoryax:BAAALAAECgcIBwAAAA==.',Ai='Aidermoi:BAABLAAECoEZAAIGAAcIuhK0LQCKAQAGAAcIuhK0LQCKAQAAAA==.',Ak='Akina:BAABLAAECoEcAAMHAAYI+xwgXQDlAQAHAAYIrRwgXQDlAQAIAAYIrBNtIgBoAQAAAA==.',Al='Alexstraszá:BAAALAADCgIIAgABLAADCgMIAwAJAAAAAA==.Alliçia:BAAALAAECgYIEQAAAA==.Alérion:BAAALAADCggICAAAAA==.',Am='Amogus:BAABLAAECoEZAAMKAAgIAB7ACACqAgAKAAgIAB7ACACqAgALAAUImB+cPwCrAQAAAA==.',Ap='Apik:BAAALAADCggIEQAAAA==.',Ar='Arakné:BAAALAAECgcIEwAAAA==.Argès:BAAALAAECgMIAgAAAA==.Ariel:BAABLAAECoEVAAIHAAcIQiO1HwDGAgAHAAcIQiO1HwDGAgABLAAECggIEgAJAAAAAA==.Arkane:BAAALAAECgEIAQAAAA==.Arows:BAAALAADCgMIAwAAAA==.Arwen:BAABLAAECoEbAAIMAAYImhElFgA4AQAMAAYImhElFgA4AQAAAA==.',As='Ascarit:BAABLAAECoEVAAIFAAYIrCKYFABZAgAFAAYIrCKYFABZAgABLAAECgcICQAJAAAAAA==.Asckarit:BAAALAAECgEIAQABLAAECgcICQAJAAAAAA==.Ashketchum:BAAALAADCggIDQAAAA==.Askarit:BAAALAAECgcICQAAAA==.Asmodéa:BAAALAADCgcIEQAAAA==.Asmôdaïos:BAAALAAECgYIDgAAAA==.Astrelia:BAABLAAECoEWAAMCAAcIMQreewDDAAANAAYIswp2vwD/AAACAAUIKQneewDDAAAAAA==.Astärøth:BAABLAAECoETAAIDAAgIyxZwTAAuAgADAAgIyxZwTAAuAgAAAA==.',Av='Avanie:BAAALAAECgEIAQAAAA==.Avataress:BAAALAADCgEIAQAAAA==.',['Aê']='Aêdex:BAAALAADCgcIBwAAAA==.',Ba='Balmora:BAAALAAECggIEQAAAA==.Banshée:BAAALAADCgcIBwABLAADCggICAAJAAAAAA==.',Bi='Bigg:BAAALAAECgEIAQAAAA==.',Bl='Blackopala:BAAALAADCggICAAAAA==.Blodreina:BAACLAAFFIEGAAIOAAII7h/LCADCAAAOAAII7h/LCADCAAAsAAQKgRkAAw4ACAioI08CADoDAA4ACAioI08CADoDAA8ABwh4FmwrALUBAAEsAAUUBggNABAAqR4A.',Bo='Boblerenard:BAABLAAECoEeAAILAAcIqxf6NADZAQALAAcIqxf6NADZAQAAAA==.Boltsofchaos:BAABLAAECoEYAAIRAAYIYB3DRAD4AQARAAYIYB3DRAD4AQAAAA==.Bordelic:BAAALAAECgMIBgAAAA==.',Bu='Buumbastik:BAAALAAECgEIAQAAAA==.',['Bâ']='Bâzil:BAAALAAECgEIAQAAAA==.',['Bä']='Bähälmung:BAABLAAECoEXAAISAAYIURxqFQCuAQASAAYIURxqFQCuAQAAAA==.',['Bé']='Bédélia:BAAALAADCgYIBgABLAADCggICAAJAAAAAA==.',Ca='Capiahh:BAAALAAECgQIBwAAAA==.Capïah:BAAALAAECgMIBAAAAA==.Carissa:BAAALAADCggIEQABLAAECggIJgATADgZAA==.',Ce='Centaur:BAAALAADCggICAAAAA==.Ceriwena:BAAALAADCgMIAwAAAA==.Cesandraa:BAAALAADCggIAwAAAA==.',Ch='Chagraal:BAAALAAECgYICwAAAA==.Chamanoxx:BAACLAAFFIELAAITAAMIVhdfDwDoAAATAAMIVhdfDwDoAAAsAAQKgSwAAhMACAjuIYgMAOwCABMACAjuIYgMAOwCAAAA.Chamegonfle:BAAALAAFFAIIBAAAAA==.Chamys:BAAALAAECggIEgAAAA==.Chassonne:BAAALAAECgEIAQAAAA==.Chiana:BAABLAAECoEkAAIDAAcIvR8pMwB+AgADAAcIvR8pMwB+AgAAAA==.Chyro:BAAALAADCggIDwAAAA==.Chå:BAAALAAECgIIAgAAAA==.',Co='Coloboss:BAAALAAECggIEAAAAA==.',Cq='Cqs:BAAALAAECgYIBgAAAA==.',Cy='Cydriel:BAAALAADCgUIBQABLAAECgcIGgADAKAiAA==.',['Cï']='Cïernïa:BAAALAAECgQICAAAAA==.',Da='Darkdryms:BAAALAADCggICAAAAA==.Darkyro:BAAALAADCggIEAAAAA==.Das:BAABLAAECoEgAAMUAAcIeRq5KQD2AQAUAAcIeRq5KQD2AQAKAAEIYxOCPgA8AAAAAA==.',De='Deadman:BAABLAAECoEZAAMVAAcIdAlgLgA3AQAVAAcIaAlgLgA3AQAQAAYI1wGjJwF+AAAAAA==.Deathofmen:BAACLAAFFIEQAAIQAAQIEhQFFgD/AAAQAAQIEhQFFgD/AAAsAAQKgSQAAhAACAjoIPciAMMCABAACAjoIPciAMMCAAAA.Defny:BAABLAAECoEbAAIIAAgIewh7KgAsAQAIAAgIewh7KgAsAQAAAA==.Demoman:BAAALAADCgMIAwAAAA==.Demox:BAAALAADCggIDwAAAA==.Deuteros:BAACLAAFFIEPAAIHAAQI0hdoEAAJAQAHAAQI0hdoEAAJAQAsAAQKgSQAAgcACAieIlcVAAEDAAcACAieIlcVAAEDAAAA.Devildrak:BAAALAAECgEIAQAAAA==.',Dh='Dham:BAAALAADCgcIAQAAAA==.',Di='Diesirae:BAAALAADCgMIAwABLAAECgYIFgAWAKwRAA==.',Do='Docdrood:BAAALAADCggICAAAAA==.',Dr='Dragounet:BAAALAAECgcIEwAAAA==.Dranae:BAAALAAECgYICQAAAA==.Drucillaa:BAAALAAECgIIAgAAAA==.Drucillâ:BAABLAAECoEaAAILAAcIMAjKawASAQALAAcIMAjKawASAQAAAA==.Dräh:BAAALAAECgMIAwAAAA==.Drömédya:BAABLAAECoEUAAIRAAYIHQjmjQAhAQARAAYIHQjmjQAhAQAAAA==.Drüzilla:BAABLAAECoEgAAMKAAgIrxVbEAAkAgAKAAgIrxVbEAAkAgALAAIIfwwGrQBTAAAAAA==.',Du='Dur:BAAALAADCgQIBAAAAA==.',['Dè']='Dèmonesstia:BAAALAADCgcIBwABLAAECgYIGwAXALsLAA==.',Ea='Eatis:BAAALAAECgYIBgABLAAECggIIgAYAHQgAA==.',Ee='Eelvegan:BAAALAAECgYIDwAAAA==.',Ek='Ekyria:BAAALAADCgQIBAAAAA==.',El='Elfinara:BAAALAAECgYIDAAAAA==.Elfìà:BAAALAAECgEIAQAAAA==.Elisaphrodit:BAAALAADCgMIAwABLAAECgYIFgAZACEQAA==.Ellanna:BAAALAADCgcICAABLAAECgcIEgAJAAAAAA==.Ellinna:BAAALAAECgcIEgAAAA==.',Em='Emmarie:BAAALAAECgEIAgAAAA==.Emule:BAABLAAECoEhAAIUAAcIchV4MwDAAQAUAAcIchV4MwDAAQAAAA==.',En='Enelym:BAAALAADCggICAAAAA==.',Er='Erilea:BAAALAADCgcIDQABLAAECgYIFgAZACEQAA==.Eroaht:BAAALAAECgIIAgABLAAECggIHgADAP0VAA==.Erop:BAAALAAECgYIBwAAAA==.Erwann:BAAALAAECgYICQAAAA==.Erydän:BAAALAADCgMIAQAAAA==.Erzilla:BAAALAADCgcIBwAAAA==.',Eu='Euphoria:BAAALAAECgUIBgABLAAECgYIBwAJAAAAAA==.',Ev='Evokina:BAABLAAECoEZAAMaAAgI7RQ3IgDqAQAaAAgI7RQ3IgDqAQASAAIItwGeNwA4AAABLAAECgYIHAAHAPscAA==.',Ew='Ewin:BAAALAAECgEIAQAAAA==.Ewïlän:BAAALAADCgUIBQABLAAECgcIEgAJAAAAAA==.',Ex='Expløsion:BAABLAAECoEWAAIEAAgIERH2TAD/AQAEAAgIERH2TAD/AQAAAA==.',Fa='Falvineus:BAABLAAECoEaAAMDAAcIoCIBJgC1AgADAAcIoCIBJgC1AgAGAAQI6RDBSwDiAAAAAA==.',Fe='Feelïng:BAAALAAECgMIBAAAAA==.Feelïngs:BAABLAAECoEYAAMGAAYIxxelKQCjAQAGAAYIxxelKQCjAQAbAAYI/g/4XgA0AAAAAA==.Felixyne:BAAALAADCggICAAAAA==.Ferendall:BAAALAADCgcIDQAAAA==.',Fi='Filius:BAAALAADCgcICwAAAA==.',Fl='Flamie:BAAALAAECgYIDgAAAA==.',Fr='Frainen:BAAALAADCgYIBgABLAAECgEIAQAJAAAAAA==.Fredazura:BAAALAAECgYIDwAAAA==.Frenessia:BAAALAADCgcIBwAAAA==.Fromaj:BAAALAAECgEIAQAAAA==.Frowny:BAAALAADCggIEAAAAA==.',Fu='Fufuman:BAAALAADCggICAABLAAECgcIFgAcAIQeAA==.',['Fë']='Fënrïr:BAAALAAECgcIEgAAAA==.',Ga='Galadrieil:BAABLAAECoEXAAINAAYIggvjrwAgAQANAAYIggvjrwAgAQAAAA==.Gallizzenae:BAAALAADCgYIBgAAAA==.Gazdrek:BAABLAAECoEkAAMDAAgI2RxmNgBxAgADAAgI2RxmNgBxAgAGAAYI2xAIOgBDAQAAAA==.',Ge='Genpal:BAAALAADCggIHgABLAAECggIIQARALcaAA==.Genryu:BAABLAAECoEhAAIRAAgItxqgKwBpAgARAAgItxqgKwBpAgAAAA==.',Gi='Girlzÿ:BAAALAADCggIDwAAAA==.',Go='Gokerz:BAAALAAECgYIBwAAAA==.Gokerzette:BAAALAADCggICAABLAAECgYIBwAJAAAAAA==.Gormash:BAABLAAECoEVAAIdAAYIgAdXRQA2AQAdAAYIgAdXRQA2AQAAAA==.Gouda:BAAALAAECgMIAwAAAA==.',Gr='Grortidimmir:BAAALAAECgYIBgABLAAECgYIFgAWAKwRAA==.Growny:BAAALAADCggIDgAAAA==.',Gu='Guiguii:BAABLAAECoEXAAIbAAgImR72CQCzAgAbAAgImR72CQCzAgAAAA==.Guiiguii:BAAALAAECgEIAQABLAAECggIFwAbAJkeAA==.',['Gé']='Génésys:BAAALAADCgMIBQABLAADCggICAAJAAAAAA==.',Ha='Hanakupichan:BAABLAAECoErAAINAAgIihW7XQDLAQANAAgIihW7XQDLAQAAAA==.Harta:BAABLAAECoEiAAMDAAgIHxegXAAEAgADAAcI+BigXAAEAgAGAAYItRcsJgC6AQAAAA==.',He='Healfécho:BAAALAAECgIIAgAAAA==.Heaven:BAAALAAECgEIAQAAAA==.Helow:BAABLAAECoElAAIZAAgIKSB/DwDlAgAZAAgIKSB/DwDlAgAAAA==.',Ho='Holygraille:BAAALAAECgMIBQAAAA==.Homage:BAABLAAECoEWAAIEAAcIowYflAA0AQAEAAcIowYflAA0AQAAAA==.Homonxa:BAAALAADCggICQAAAA==.Hopîsgone:BAAALAADCggICAAAAA==.Horchac:BAACLAAFFIEFAAIXAAIIVR5BHwCjAAAXAAIIVR5BHwCjAAAsAAQKgScAAhcACAgEJAELADUDABcACAgEJAELADUDAAAA.',Hu='Huhanaa:BAABLAAECoEXAAIbAAgI/Rg8GQD5AQAbAAgI/Rg8GQD5AQAAAA==.',Hy='Hyørinmarù:BAAALAAECgYIDgABLAAECggIKQAEAEgZAA==.',['Hâ']='Hâyâbûsâ:BAAALAADCgMIAwAAAA==.Hâyä:BAAALAAECgcIEAAAAA==.',['Hä']='Häyhä:BAAALAAECgcIEwAAAA==.',['Hæ']='Hæla:BAAALAAECgYIBwAAAA==.',['Hè']='Hècate:BAAALAAECgQIBAAAAA==.',['Hé']='Hélà:BAAALAAECgYIBAAAAA==.',['Hô']='Hôpisgone:BAAALAADCggIBwAAAA==.',['Hø']='Høly:BAAALAAECgMIAwAAAA==.Høøps:BAAALAAECgIIAwABLAAECgYICQAJAAAAAA==.',Id='Idrael:BAABLAAECoEcAAIMAAYISCAYCQAlAgAMAAYISCAYCQAlAgAAAA==.',Io='Iordillidan:BAAALAAECgMIBAAAAA==.',Iw='Iwop:BAAALAAECgMIBgABLAAECgYIBwAJAAAAAA==.',Iz='Izo:BAAALAAECgYIEQAAAA==.',Ja='Jasna:BAABLAAECoEaAAIeAAgIqhRXHADxAQAeAAgIqhRXHADxAQAAAA==.',Je='Jeckwecker:BAAALAADCggIIQAAAA==.',Jo='Jocla:BAABLAAECoEmAAITAAgIOBk4MwAjAgATAAgIOBk4MwAjAgAAAA==.Johnnash:BAAALAAECgUIEAAAAA==.Jolynna:BAAALAAECgMIAwAAAA==.Jolâin:BAAALAAECgUIEwAAAA==.Joïy:BAAALAADCgcICgAAAA==.',Ju='Juuki:BAAALAAECgYIBgAAAA==.',['Jö']='Jörmungand:BAABLAAECoEUAAISAAYIyhO+GQB2AQASAAYIyhO+GQB2AQABLAAECgYIFgAWAKwRAA==.',Ka='Kasos:BAAALAADCggICAAAAA==.Kassiah:BAABLAAECoEmAAMTAAgIKxxeKABNAgATAAgIKxxeKABNAgABAAEIWA0AAAAAAAAAAA==.Katihunt:BAACLAAFFIEMAAINAAQIPx/cCgBTAQANAAQIPx/cCgBTAQAsAAQKgTEAAg0ACAjGJRcJADgDAA0ACAjGJRcJADgDAAAA.',Ke='Kelts:BAAALAAECgIIAgAAAA==.',Kh='Khaotik:BAABLAAECoEoAAIfAAgI8Au7BwDBAQAfAAgI8Au7BwDBAQAAAA==.',Ki='Kimiwaro:BAAALAADCgIIAgAAAA==.Kimlie:BAAALAAECgEIAQAAAA==.',Kl='Kleriøsse:BAAALAAECgcIEQAAAA==.',Ko='Kohane:BAAALAAECgYICQAAAA==.Kosmopoli:BAAALAAECggIDwAAAA==.Kozo:BAAALAADCgcICwAAAA==.',Kr='Krazhul:BAAALAADCgUIBQAAAA==.',Ku='Kurau:BAAALAADCgUIBQAAAA==.Kurlly:BAABLAAECoElAAMUAAgIwB2aFACcAgAUAAgIwB2aFACcAgALAAYIXhOLWQBJAQAAAA==.Kurlsham:BAAALAADCgIIAgAAAA==.',Ky='Kylian:BAAALAADCgYIBgAAAA==.',La='Lamortu:BAAALAAECgYICwAAAA==.Laëticia:BAAALAAECgEIAQAAAA==.',Le='Lebang:BAAALAADCgcIBwABLAAECgQICQAJAAAAAA==.Lektus:BAAALAADCgEIAQAAAA==.',Li='Lichkiing:BAAALAAECgcIDQAAAA==.Likæ:BAAALAADCgUIBQAAAA==.',Lo='Lonstret:BAAALAAECgYICgAAAA==.Louâne:BAABLAAECoElAAITAAcIwhLwdABiAQATAAcIwhLwdABiAQAAAA==.',Ly='Lynëa:BAABLAAECoEYAAIUAAcIOA3FRQBrAQAUAAcIOA3FRQBrAQAAAA==.Lyopa:BAABLAAECoEgAAIgAAgIvwuxSACOAQAgAAgIvwuxSACOAQAAAA==.Lyow:BAAALAAECgMIAwABLAAECggIIAAgAL8LAA==.Lyrrä:BAAALAADCgUIAgAAAA==.',['Lä']='Läuräne:BAABLAAECoEgAAIGAAYITRwcIgDUAQAGAAYITRwcIgDUAQAAAA==.',['Lö']='Lödëa:BAAALAADCgcIBwAAAA==.',['Lü']='Lüv:BAAALAADCgcIBwAAAA==.',Ma='Magikchami:BAAALAAECgYIEgAAAA==.Magnuss:BAAALAADCgIIAgAAAA==.Malyage:BAAALAADCgcIBwAAAA==.Mamiebaker:BAABLAAECoEgAAIZAAgIqhyXFAC0AgAZAAgIqhyXFAC0AgAAAA==.Marwo:BAAALAADCgQIBAAAAA==.Marylène:BAAALAAECgQIBgAAAA==.Matchaa:BAAALAAECgUICAABLAAECgcIDwAJAAAAAA==.Mattmdevoker:BAAALAADCgcICQAAAA==.Mattmdkr:BAABLAAECoEmAAIYAAgI+RndDgAtAgAYAAgI+RndDgAtAgAAAA==.Mayuu:BAACLAAFFIEOAAIKAAMIgiCTAwAcAQAKAAMIgiCTAwAcAQAsAAQKgS4AAgoACAjNJdYAAHEDAAoACAjNJdYAAHEDAAAA.Mazamune:BAAALAADCggIEAABLAAECggIJgATADgZAA==.Maêglyn:BAAALAADCgcIBwAAAA==.',Mc='Mcoco:BAAALAADCgcIDAAAAA==.',Md='Mdfury:BAAALAADCggICgAAAA==.',Me='Melchioz:BAAALAAECgMIBAAAAA==.Metalhead:BAABLAAECoEWAAMWAAYIrBGoIgBIAQAWAAYIrBGoIgBIAQAhAAYIKwRaNgC9AAAAAA==.Meuhtal:BAAALAADCggIBgABLAAECgYIFgAWAKwRAA==.',Mi='Midrashim:BAABLAAECoEhAAIiAAgI2gmvDgCqAQAiAAgI2gmvDgCqAQAAAA==.Mikado:BAAALAADCgcICQAAAA==.Miladiou:BAAALAAECgUIBQAAAA==.Miridas:BAAALAAECgYIDAAAAA==.Misska:BAAALAAECgUICAAAAA==.Missliadrin:BAAALAADCggIHwAAAA==.Mitterrand:BAABLAAECoEWAAMQAAgILCPhHgDWAgAQAAgILCPhHgDWAgAYAAEIxiBiPABCAAAAAA==.',Mo='Moinica:BAAALAADCgYIBgAAAA==.Molbytus:BAAALAADCgQIBQAAAA==.Mongrototem:BAAALAAECgYICgAAAA==.Mortro:BAAALAAECgEIAQAAAA==.Mousitig:BAAALAAECgMIAwAAAA==.',My='Mystérya:BAAALAAECgEIAQAAAA==.',['Mä']='Mäxøu:BAACLAAFFIEPAAIhAAQIrRW1BABaAQAhAAQIrRW1BABaAQAsAAQKgSYAAiEACAhrHnQLAIsCACEACAhrHnQLAIsCAAAA.',['Mé']='Mélo:BAAALAADCgcIBwAAAA==.',['Mî']='Mîmîc:BAABLAAECoEoAAIjAAgITB0HEACTAgAjAAgITB0HEACTAgAAAA==.',['Mô']='Môb:BAAALAADCgYIBgAAAA==.',['Mø']='Møøn:BAAALAAECgEIAQAAAA==.',Na='Naael:BAACLAAFFIEZAAMOAAYIKh9oAQAsAgAOAAYIKh9oAQAsAgAPAAIIdhrWEACpAAAsAAQKgScAAw4ACAgvI6AEAPQCAA4ACAgVIaAEAPQCAA8ACAhbIMEMAL0CAAAA.Nael:BAAALAAECgYICgAAAA==.Naincappable:BAAALAAECgUICQABLAAFFAQIDQASAGcQAA==.Nainpausepas:BAABLAAECoEfAAIGAAgIlx+xBwDYAgAGAAgIlx+xBwDYAgAAAA==.Nascraf:BAAALAAECgUIDQAAAA==.',Ne='Nedraï:BAAALAADCgEIAQAAAA==.Neferupitø:BAAALAAECgEIAQAAAA==.',Ni='Niroel:BAABLAAECoEVAAIQAAgIcRrZSgA3AgAQAAgIcRrZSgA3AgAAAA==.Nishi:BAAALAADCgIIAgAAAA==.Nist:BAAALAADCgcIBwAAAA==.',No='Nohealforyou:BAABLAAECoEWAAIZAAYI4wk9XAAaAQAZAAYI4wk9XAAaAQAAAA==.Normux:BAAALAAECgQICAAAAA==.',Ny='Nyzzra:BAAALAAECgcIEwAAAA==.',Oc='Océanika:BAAALAAECgQIBQAAAA==.',Og='Ogïon:BAABLAAECoEXAAIDAAYI9xd6kgCXAQADAAYI9xd6kgCXAQAAAA==.',Ok='Okaya:BAAALAADCgIIAgAAAA==.',Op='Opaal:BAAALAAECgcIDwAAAA==.',Pa='Paki:BAAALAAECgYIDAAAAA==.Paladoxis:BAAALAADCggIDQAAAA==.Paladuse:BAAALAAECgEIAQAAAA==.Palapagou:BAABLAAECoEZAAIDAAcI5BquTQAqAgADAAcI5BquTQAqAgAAAA==.Palofou:BAAALAADCgcIBwAAAA==.Pandöra:BAABLAAECoEkAAICAAcItQxLWAA+AQACAAcItQxLWAA+AQAAAA==.Patheal:BAAALAAECgYIBQAAAA==.',Pe='Pewpewpewpew:BAACLAAFFIEGAAITAAIIDBzUKgCHAAATAAIIDBzUKgCHAAAsAAQKgSgAAxMACAjPH4UVAK4CABMACAjPH4UVAK4CAAEABwi8ColXAIIBAAAA.',Ph='Phiauna:BAABLAAECoEaAAIdAAcINhpEHgDuAQAdAAcINhpEHgDuAQAAAA==.Physal:BAAALAAECgcICAABLAAECgcIDwAJAAAAAA==.',Pi='Pied:BAABLAAECoEcAAIXAAgIVSG2HgCrAgAXAAgIVSG2HgCrAgAAAA==.Pitu:BAAALAAECgEIAQAAAA==.',Pl='Plubobo:BAABLAAECoEWAAMgAAgIWyJ3CQAPAwAgAAgIWyJ3CQAPAwAkAAEIDRR6LwBCAAAAAA==.Plug:BAAALAADCgMIAwAAAA==.',Po='Poppi:BAAALAAFFAIIAgAAAA==.Poutou:BAAALAAECgYIDgAAAA==.',['Pà']='Pàblo:BAABLAAECoEbAAIGAAYI/BKlMwBoAQAGAAYI/BKlMwBoAQAAAA==.',['På']='Påf:BAAALAAECgUIDAAAAA==.',['Pø']='Pøivre:BAAALAAECgYICQAAAA==.',Qh='Qhari:BAAALAAECggIDgAAAA==.Qharidk:BAAALAAECggICAAAAA==.Qharisham:BAAALAAECggICAAAAA==.',Ra='Rakarash:BAABLAAECoEiAAMLAAgIXB/gDgDDAgALAAgIXB/gDgDDAgAUAAUI0RL3UQA2AQAAAA==.Razack:BAAALAAECgYIBgAAAA==.Razorgate:BAAALAAECgQIDgAAAA==.Raëlthas:BAAALAADCgcIBwAAAA==.',Rh='Rhinoféroce:BAABLAAECoEYAAINAAYIzxIPoQA9AQANAAYIzxIPoQA9AQAAAA==.',Ri='Riggnarok:BAAALAADCggICAABLAAECgYIFgAWAKwRAA==.Rivella:BAABLAAECoEVAAIGAAcIew/ELwB+AQAGAAcIew/ELwB+AQAAAA==.',Ru='Rusty:BAAALAAECggIAwAAAA==.',Sa='Saaka:BAAALAAECgMIAwAAAA==.Saharash:BAABLAAECoEXAAIHAAcIgiCfLACGAgAHAAcIgiCfLACGAgABLAAFFAYIDQAQAKkeAA==.Saille:BAABLAAECoEaAAIRAAcIAwXykAAZAQARAAcIAwXykAAZAQAAAA==.Saiseï:BAACLAAFFIERAAIhAAYIkgsVAwC/AQAhAAYIkgsVAwC/AQAsAAQKgSkAAiEACAhKF+YSABgCACEACAhKF+YSABgCAAAA.Saku:BAAALAAECgIIAgAAAA==.Sandatus:BAAALAADCgIIAgABLAAECgEIAQAJAAAAAA==.Satîna:BAAALAAECgQIBgAAAA==.Savanïa:BAAALAADCggIEAABLAAECggIIAAgAL8LAA==.',Se='Sergisergio:BAACLAAFFIENAAMSAAQIZxCyCADaAAASAAQIZxCyCADaAAAaAAEIKBkiHABIAAAsAAQKgSQAAxoACAgSIOQLANYCABoACAgSIOQLANYCABIABQgMF9AcAFIBAAAA.Sevastyana:BAAALAADCgcIDQAAAA==.Severine:BAAALAAECggICAAAAA==.',Sh='Shadowangel:BAAALAADCggICAAAAA==.Shiinjii:BAAALAADCgYIBgAAAA==.Shiiro:BAABLAAECoEZAAILAAgIFRhvJQAnAgALAAgIFRhvJQAnAgAAAA==.Shiroo:BAAALAADCgcIDgAAAA==.Shoob:BAAALAADCgUIBQAAAA==.Shoryuken:BAAALAAECgEIAQAAAA==.Shãlliã:BAAALAADCgIIAwAAAA==.',Si='Siléçao:BAAALAAECgcIBwAAAA==.',Sk='Skiunk:BAAALAADCgUIBAABLAADCgUIBQAJAAAAAA==.Skäldÿ:BAABLAAECoEUAAIBAAgInA9EPwDdAQABAAgInA9EPwDdAQAAAA==.',Sl='Slðw:BAABLAAECoEtAAIbAAgIBCLeBgDxAgAbAAgIBCLeBgDxAgAAAA==.',Sp='Spartiates:BAAALAADCgUIBQAAAA==.',St='Stargane:BAABLAAECoEkAAIDAAcIqBoAXAAFAgADAAcIqBoAXAAFAgAAAA==.Stil:BAAALAADCgYIBgAAAA==.Stéllà:BAABLAAECoEXAAIUAAYIPRclPwCIAQAUAAYIPRclPwCIAQAAAA==.Størmss:BAAALAADCggICQAAAA==.',Su='Sunrise:BAAALAADCgcIEQAAAA==.Sunshine:BAAALAAECgYIBgAAAA==.Surprise:BAAALAADCgcIBwAAAA==.Survie:BAAALAAECgcICQAAAA==.',Sv='Sveltus:BAAALAAECgUICwAAAA==.',Sw='Swén:BAAALAAECgUIBQAAAA==.',Sy='Symbâd:BAAALAADCggIHAAAAA==.',['Sø']='Søùltrâp:BAACLAAFFIEGAAIdAAIIBRb2CQCtAAAdAAIIBRb2CQCtAAAsAAQKgScAAh0ACAibJcQAAHkDAB0ACAibJcQAAHkDAAEsAAUUBggWABEAPRMA.Søùlträp:BAACLAAFFIEWAAMRAAYIPRNqCADsAQARAAYIGxJqCADsAQAiAAEIMwcAAAAAAAAsAAQKgS0AAhEACAjjI/cKADIDABEACAjjI/cKADIDAAAA.Søültrâp:BAACLAAFFIEFAAIiAAII8CKOAQDHAAAiAAII8CKOAQDHAAAsAAQKgTwAAiIACAjUJgsAAJ8DACIACAjUJgsAAJ8DAAEsAAUUBggWABEAPRMA.',Te='Teillya:BAAALAAECgMIAwAAAA==.',Tg='Tgpied:BAABLAAECoEXAAIQAAcIaRxLXQAJAgAQAAcIaRxLXQAJAgAAAA==.',Th='Thania:BAAALAADCggIEAABLAAECgYIFgAWAKwRAA==.Thaoreghil:BAABLAAECoEeAAIDAAgI/RURWQAMAgADAAgI/RURWQAMAgAAAA==.Theopoil:BAABLAAECoEWAAIZAAYIIRDpTABfAQAZAAYIIRDpTABfAQAAAA==.Thémesta:BAAALAADCgMIAwAAAA==.',Ti='Timalf:BAAALAAECgYICQAAAA==.',To='Tonko:BAAALAADCgcIGwAAAA==.Torchon:BAABLAAECoEdAAIEAAgIXhGiXwDFAQAEAAgIXhGiXwDFAQAAAA==.Torgale:BAAALAAECgMIBAAAAA==.Tototeman:BAABLAAECoEWAAMcAAcIhB7jCQA4AgAcAAcIahzjCQA4AgABAAYIABkAAAAAAAAAAA==.Toudindecou:BAACLAAFFIEWAAMQAAYIWCAJAwBBAgAQAAYIcx8JAwBBAgAYAAYItxIAAAAAAAAsAAQKgSgAAhAACAh2JX8JAEUDABAACAh2JX8JAEUDAAAA.Touxdincou:BAAALAAECgcIDwABLAAFFAYIFgAQAFggAA==.Towi:BAABLAAECoEXAAIcAAgIKBAaDgDiAQAcAAgIKBAaDgDiAQAAAA==.Towny:BAABLAAECoEiAAMRAAgIyyXlAgB3AwARAAgIwCXlAgB3AwAdAAIIDibZZwCfAAAAAA==.',Tr='Triplesix:BAAALAAECgYICgAAAA==.Trollhiwood:BAAALAAECgYICgAAAA==.Trollos:BAAALAADCggICAAAAA==.',Tu='Tungsten:BAAALAADCggICwABLAAECgUIBQAJAAAAAA==.Tunkashilla:BAAALAAECgcICwAAAA==.',Ty='Tykanis:BAAALAADCgYIBgAAAA==.Tyrandis:BAAALAAECgYICwABLAAECggIGgADAG4bAA==.Tyshz:BAAALAAECgUIBQABLAAECggIEAAJAAAAAA==.Tyshzdk:BAAALAAECggIEAAAAA==.Tyshzlock:BAABLAAECoEgAAMRAAcItRm7QAAHAgARAAcItRm7QAAHAgAiAAEIxAoCPgAzAAABLAAECggIEAAJAAAAAA==.',['Té']='Tétraktys:BAAALAADCgcICwAAAA==.',['Tø']='Tøshirø:BAABLAAECoEpAAIEAAgISBm4PQA1AgAEAAgISBm4PQA1AgAAAA==.',Ul='Ulvik:BAAALAAECgEIAQAAAA==.',Un='Unthuwa:BAAALAAECgcIBwAAAA==.',Us='Usée:BAABLAAECoEUAAIDAAYI2wZf2QAUAQADAAYI2wZf2QAUAQAAAA==.',Va='Valery:BAAALAADCgcIBwAAAA==.Valye:BAAALAAECgMIBAAAAA==.Valythir:BAABLAAECoEbAAIXAAgI8xaHNgApAgAXAAgI8xaHNgApAgAAAA==.Vany:BAABLAAECoEoAAIgAAgIZgs6UABxAQAgAAgIZgs6UABxAQAAAA==.Varko:BAABLAAECoEiAAIYAAgIdCBVBwDOAgAYAAgIdCBVBwDOAgAAAA==.Varkunt:BAAALAADCggICAABLAAECggIIgAYAHQgAA==.',Vi='Vingtcinqcl:BAAALAAECgIIAgAAAA==.Vitolino:BAABLAAECoEbAAIPAAYIwAjJQwAiAQAPAAYIwAjJQwAiAQAAAA==.',Vn='Vnl:BAAALAADCgcIFAAAAA==.Vnll:BAAALAADCgIIAgAAAA==.Vnlpal:BAAALAADCgcIEQAAAA==.',Vo='Voodoux:BAAALAAECgMIAwAAAA==.Vorka:BAAALAADCgcIDQABLAAECggIIgAYAHQgAA==.',Wa='Wartaff:BAABLAAECoEeAAIgAAgIWhnEIABXAgAgAAgIWhnEIABXAgAAAA==.Waryana:BAABLAAECoEbAAIXAAYIuwvkfQBFAQAXAAYIuwvkfQBFAQAAAA==.Watibonk:BAABLAAECoEeAAIGAAgIRx+aCQC9AgAGAAgIRx+aCQC9AgAAAA==.Watijtgoume:BAAALAADCggIEQAAAA==.',We='Wendass:BAAALAADCgcIFAAAAA==.',Wh='Whitekilleur:BAABLAAECoEXAAIDAAcI3h2WQABPAgADAAcI3h2WQABPAgAAAA==.',Wi='Witta:BAAALAAECgUIBwAAAA==.',Wo='Wolferine:BAABLAAECoEZAAINAAYIlhlqcACfAQANAAYIlhlqcACfAQAAAA==.Wolframite:BAAALAAECgUIBQAAAA==.Worgenae:BAAALAAECgQIBgAAAA==.',['Wø']='Wølf:BAABLAAECoEbAAIQAAcI7BcgfADJAQAQAAcI7BcgfADJAQAAAA==.',Xe='Xelha:BAAALAAECgcIBwAAAA==.',Ya='Yalfeu:BAAALAADCgcIDQAAAA==.Yamajii:BAAALAADCgcIDwAAAA==.Yasmina:BAAALAAECgQIBQAAAA==.Yaundel:BAAALAADCgQIBAAAAA==.',Yo='Yotsuba:BAAALAAECggIEgAAAA==.Youffette:BAAALAADCgcIBwAAAA==.',Ys='Ysirhia:BAAALAAECgYIBQAAAA==.Yséline:BAAALAAECgYIBgAAAA==.',Yu='Yujinn:BAAALAADCgcIBwABLAAECgYIBwAJAAAAAA==.Yulam:BAAALAAECgIIAwAAAA==.Yunal:BAAALAADCgYIBwAAAA==.',['Yö']='Yöuffy:BAAALAADCggIGAAAAA==.',['Yø']='Yøupi:BAAALAAECgYICAAAAA==.',Za='Zagzill:BAAALAAECgQICAAAAA==.Zarakí:BAABLAAECoEZAAIVAAgIuBuSCgCWAgAVAAgIuBuSCgCWAgAAAA==.',Ze='Zenethor:BAABLAAECoEfAAIFAAcIVhbKJADXAQAFAAcIVhbKJADXAQAAAA==.Zephyrïa:BAABLAAECoEcAAITAAYIJSLaLQA3AgATAAYIJSLaLQA3AgAAAA==.',Zr='Zréya:BAAALAADCgUIBQAAAA==.',Zu='Zunn:BAAALAAECgMIBAAAAA==.Zunnh:BAAALAAECgYICgAAAA==.',['Zü']='Zühl:BAAALAADCgcICAAAAA==.',['Ál']='Álexstrászá:BAAALAADCgMIAwAAAA==.',['Äb']='Äbbydh:BAABLAAECoEUAAIIAAcIhiJ8CQCeAgAIAAcIhiJ8CQCeAgAAAA==.Äbbysale:BAABLAAECoEVAAIbAAgIYSFoBgD7AgAbAAgIYSFoBgD7AgAAAA==.',['Æz']='Æzertyx:BAAALAADCggIFgAAAA==.',['Él']='Élmére:BAAALAAECggIAgAAAA==.',['Ét']='Étèrnité:BAAALAADCgIIAgAAAA==.',['Ïq']='Ïquero:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end