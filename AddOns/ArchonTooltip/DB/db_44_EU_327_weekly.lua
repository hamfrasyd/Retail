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
 local lookup = {'Druid-Restoration','Druid-Feral','Monk-Brewmaster','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Warrior-Fury','Evoker-Preservation','Priest-Holy','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Unknown-Unknown','DemonHunter-Havoc','Paladin-Retribution','Paladin-Protection','DeathKnight-Blood','Mage-Frost','Mage-Fire','Mage-Arcane','Warrior-Protection','Monk-Mistweaver','Monk-Windwalker','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','Warrior-Arms','Hunter-Marksmanship',}; local provider = {region='EU',realm='ShatteredHalls',name='EU',type='weekly',zone=44,date='2025-09-22',data={Al='Altheä:BAAALAAECggICQAAAA==.Alti:BAAALAADCgcIDgAAAA==.Alymantara:BAABLAAECoEbAAMBAAgIvQkUWQBBAQABAAgIvQkUWQBBAQACAAYINgeGKAAIAQAAAA==.Alythess:BAAALAAECgIIAgAAAA==.',Am='Amalka:BAABLAAECoEbAAIDAAgIxB9aBwDUAgADAAgIxB9aBwDUAgAAAA==.Ampularecti:BAABLAAECoEcAAIEAAgI2RepDgBOAgAEAAgI2RepDgBOAgAAAA==.',Ap='Apotheosis:BAAALAAECgIIAgAAAA==.',Ar='Argael:BAAALAAECgYICAAAAA==.Arlan:BAAALAADCgcIBwAAAA==.Arpad:BAAALAAECgYIBwAAAA==.Arthon:BAABLAAECoEXAAMFAAcIfA8RmwCJAQAFAAcIfA8RmwCJAQAEAAEIsAOtVgApAAAAAA==.Aryïa:BAAALAADCggIEwABLAAECggIGQAGAPwhAA==.',As='Ashm:BAAALAAFFAIIAgAAAA==.Ashmodai:BAABLAAECoEYAAIGAAgIXgfINABZAQAGAAgIXgfINABZAQAAAA==.',Ba='Bacardii:BAABLAAECoEfAAIHAAgINBUrNAApAgAHAAgINBUrNAApAgAAAA==.Bash:BAABLAAECoEbAAIHAAgIqQYAdgBNAQAHAAgIqQYAdgBNAQAAAA==.',Be='Beastheart:BAAALAAECgYIDAAAAA==.Beloslava:BAABLAAECoEeAAIIAAcIEBXQEgDLAQAIAAcIEBXQEgDLAQAAAA==.Benedict:BAAALAAECgYIBgAAAA==.Bestwaifu:BAAALAAECggIDgAAAA==.',Bi='Bigbumdragan:BAAALAAECgYIDAABLAAECggIHQAJADofAA==.',Bl='Blazun:BAAALAADCgUIBQAAAA==.',Br='Brainrot:BAABLAAECoEUAAIFAAgInAfgogB8AQAFAAgInAfgogB8AQAAAA==.',By='Bystrozraky:BAAALAAECgIIAgABLAAECggIGwADAMQfAA==.',Ch='Chrome:BAAALAAECgUIEAAAAA==.Chytrusek:BAABLAAECoEgAAIKAAgIQhNPMgAQAgAKAAgIQhNPMgAQAgAAAA==.',Ci='Ciderblom:BAAALAAECgIIAgAAAA==.',Co='Coconut:BAAALAAECgYIDgAAAA==.',Cr='Crx:BAAALAADCgMIBAAAAA==.',Da='Daddydj:BAAALAAECggICAAAAA==.Dandarkk:BAABLAAECoEfAAIFAAgIiQiwkwCWAQAFAAgIiQiwkwCWAQAAAA==.Darkazaar:BAAALAADCggICAABLAAECggIHQALAJwgAA==.',De='Decap:BAAALAAECgYIEQAAAA==.Deku:BAAALAAECgYICwAAAA==.Demonwaifu:BAAALAAECgYICAAAAA==.Deurpaneus:BAAALAAECgUIBQAAAA==.',Di='Discobogdan:BAAALAAECggIDgAAAA==.',Do='Douevendkbro:BAAALAAECggIEAAAAA==.',Dr='Dragalicious:BAABLAAECoEdAAMJAAgIOh89DwDVAgAJAAgIOh89DwDVAgAMAAcIJxc2LAD8AQAAAA==.',Ed='Ederologos:BAAALAAECgYICQAAAA==.',Fa='Fate:BAAALAAECgMIAwABLAAFFAIIAgANAAAAAA==.',Fe='Felicja:BAABLAAECoEYAAIOAAgI/xA6WQDnAQAOAAgI/xA6WQDnAQAAAA==.Feínt:BAAALAADCggICAAAAA==.',Fi='Fittberitbum:BAABLAAECoEZAAIPAAgIyh50KQCgAgAPAAgIyh50KQCgAgAAAA==.',Fl='Flabby:BAAALAADCggICwAAAA==.',Fo='Fortianna:BAACLAAFFIEIAAIQAAMIrBBlBgDIAAAQAAMIrBBlBgDIAAAsAAQKgSEAAhAACAgzHkwMAIMCABAACAgzHkwMAIMCAAAA.',Fr='Frostone:BAABLAAECoEhAAMFAAgIBhfrVgATAgAFAAgIBhfrVgATAgARAAEIEREOQAAnAAAAAA==.Frostyflake:BAAALAADCggIDAAAAA==.',Go='Goofyclaw:BAABLAAECoEVAAQSAAgISSMHEACBAgASAAcItyIHEACBAgATAAUIRxx+CACeAQAUAAEIBwmT3AAwAAAAAA==.',Gu='Gudrinieks:BAABLAAFFIEGAAIJAAIIfw92IQCSAAAJAAIIfw92IQCSAAAAAA==.',['Gø']='Gødsgift:BAACLAAFFIEIAAIFAAMIxSDlDwAhAQAFAAMIxSDlDwAhAQAsAAQKgRgAAgUABgg2I2M8AF0CAAUABgg2I2M8AF0CAAAA.',Ha='Havarea:BAAALAADCggIDAABLAAECggIIAAPAJsUAA==.Havran:BAABLAAECoEgAAIPAAgImxS2UgAWAgAPAAgImxS2UgAWAgAAAA==.',Hu='Hunterytza:BAAALAAECgIIAgABLAAECggIHQALAJwgAA==.',['Hó']='Hólycow:BAAALAAECggICAAAAA==.',Il='Illiilliilli:BAABLAAECoEZAAIKAAcIsRVsPADgAQAKAAcIsRVsPADgAQAAAA==.',Im='Imera:BAAALAAECgYIDgAAAA==.',Ir='Irí:BAAALAAECgIIAgAAAA==.',Ja='Jadepaws:BAABLAAECoEhAAIBAAgIux2ZFACLAgABAAgIux2ZFACLAgAAAA==.',Jo='Jodariel:BAAALAAECgQIBAAAAA==.',Ka='Kafzaru:BAAALAAECgYICgAAAA==.Kazzataur:BAAALAAECgIIAgAAAA==.',Ke='Kejchal:BAAALAADCgUIBQAAAA==.Kelac:BAAALAADCgcIBwABLAAFFAYIFgADAK4hAA==.',Kh='Kheiya:BAABLAAECoEZAAIGAAYI/CGREwBHAgAGAAYI/CGREwBHAgAAAA==.',Ki='Kihelheim:BAACLAAFFIEIAAIOAAIIwh/HFwDDAAAOAAIIwh/HFwDDAAAsAAQKgSQAAg4ACAgpI5cOACQDAA4ACAgpI5cOACQDAAAA.Kiinai:BAAALAAECgQIBgAAAA==.Killmarosh:BAAALAAECgYIBQAAAA==.',Kl='Klempavi:BAAALAADCgQIBAAAAA==.',Kr='Krexil:BAABLAAECoEhAAIJAAgIKCD9DwDOAgAJAAgIKCD9DwDOAgAAAA==.',Kw='Kwazam:BAABLAAECoEVAAMSAAgITxokEwBgAgASAAgITxokEwBgAgATAAEIhgtgHQA3AAAAAA==.',Ky='Kyzzpope:BAABLAAECoEXAAIJAAgIBw7rRACYAQAJAAgIBw7rRACYAQAAAA==.',La='Lackadeath:BAAALAAECgYICAAAAA==.Lastspark:BAAALAAECgYIDQAAAA==.',Le='Leccee:BAACLAAFFIEFAAIUAAIIaAmqPQCIAAAUAAIIaAmqPQCIAAAsAAQKgRkAAhQACAhQHUkwAGcCABQACAhQHUkwAGcCAAEsAAUUAggIAA4Awh8A.',Li='Lightshope:BAAALAADCgYIBAAAAA==.Limeblom:BAABLAAECoEgAAMSAAgIzSDICADtAgASAAgIzSDICADtAgAUAAcIrhehTAD5AQAAAA==.',Lo='Loanshark:BAAALAADCggICAAAAA==.Lotus:BAAALAAECgIIAgAAAA==.Louke:BAABLAAECoEhAAMQAAgICx2rEgAzAgAQAAcIHh2rEgAzAgAPAAEIgRw0IgFVAAAAAA==.',Lu='Luck:BAAALAADCggIEwAAAA==.',Ma='Mark:BAAALAAECgYIEAAAAA==.',Me='Medullarum:BAABLAAECoEfAAMKAAgITA0gSQCsAQAKAAgITA0gSQCsAQALAAcIlwwuiQApAQAAAA==.Meimei:BAAALAADCgcIBwAAAA==.Mellody:BAAALAAECgYICQAAAA==.',Mi='Miggi:BAABLAAECoEfAAIDAAgIABfYEAAaAgADAAgIABfYEAAaAgAAAA==.Mindedas:BAAALAADCggIDwAAAA==.Minilandswe:BAABLAAECoEXAAMHAAcIARVCUgC3AQAHAAcIPRFCUgC3AQAVAAYIIhU+OgBNAQAAAA==.',Mo='Monolithus:BAAALAAECgMIBAAAAA==.Morrighan:BAAALAADCggIEQAAAA==.',My='Mystie:BAABLAAECoErAAQWAAgItiEqBQD7AgAWAAgItiEqBQD7AgADAAYIOhaZGwCIAQAXAAIIHA+uTwBbAAAAAA==.',['Mä']='Mäsha:BAAALAAECgYIEwABLAAECggIIgAHAK0UAA==.',Na='Nakali:BAABLAAECoEjAAIPAAgIrxQiXgD5AQAPAAgIrxQiXgD5AQAAAA==.',Ne='Nelthil:BAAALAAECggIEAAAAA==.',Ny='Nyxe:BAAALAAECgcIEwAAAA==.',Ob='Obzen:BAAALAADCggICAAAAA==.',Pa='Pagodan:BAAALAAECgYIBgAAAA==.Partu:BAAALAADCggIDAAAAA==.',Po='Pokelar:BAAALAAECgYIBQAAAA==.Pokellah:BAAALAADCgEIAQAAAA==.',Pr='Priso:BAABLAAECoEUAAILAAYIShUBbgBqAQALAAYIShUBbgBqAQAAAA==.',['Pé']='Péna:BAAALAADCgYIBgAAAA==.',Qa='Qaelithus:BAAALAADCggIGQAAAA==.',Ra='Ragefire:BAAALAAECgQIBgAAAA==.Raspoutin:BAAALAADCgcIBwABLAAECggIGQAGAPwhAA==.Raventhyr:BAAALAADCgcIDAABLAAECggIIAAPAJsUAA==.',Re='Restoration:BAAALAAECgEIAQAAAA==.Retoddid:BAABLAAECoEhAAMKAAgIVAYuXQBmAQAKAAgIVAYuXQBmAQALAAgIawiBjgAdAQAAAA==.',Ri='Ril:BAABLAAECoEhAAIEAAgIxx64BQDuAgAEAAgIxx64BQDuAgAAAA==.',Ro='Rodormu:BAAALAAECgIIAgAAAA==.Rohun:BAABLAAECoEhAAIGAAgIMCHwBQDuAgAGAAgIMCHwBQDuAgAAAA==.',Sa='Sanglord:BAABLAAECoEaAAMYAAgIfBs8LABeAgAYAAgIexk8LABeAgAZAAQIChNgUgD3AAAAAA==.Sanivam:BAAALAAECgEIAQAAAA==.Sansya:BAABLAAECoEjAAIGAAgIkxtXDACVAgAGAAgIkxtXDACVAgAAAA==.Sardaukar:BAAALAADCggICAAAAA==.',Sc='Scrolls:BAABLAAECoEVAAIPAAgIRh/4KwCWAgAPAAgIRh/4KwCWAgAAAA==.Scrooty:BAABLAAECoEVAAILAAcIBw1UhwAtAQALAAcIBw1UhwAtAQAAAA==.',Sh='Shallain:BAAALAADCgcIBwABLAAFFAYIFgADAK4hAA==.Shieldheart:BAAALAAECggICQABLAAFFAYIFgADAK4hAA==.Shiru:BAAALAADCgUIBQAAAA==.Shogan:BAAALAAECgYIDQAAAA==.Shortstack:BAABLAAECoEkAAIYAAgItiHgEQD+AgAYAAgItiHgEQD+AgAAAA==.',Si='Sillentwrath:BAAALAAECggICgAAAA==.Sindorei:BAAALAAECggICwAAAA==.Sinvanna:BAAALAADCgEIAQAAAA==.',Sn='Snöret:BAABLAAECoEbAAIFAAgIwh1wJgCvAgAFAAgIwh1wJgCvAgAAAA==.',Sp='Sparagi:BAAALAADCggICAAAAA==.Sparagus:BAAALAADCggICAAAAA==.Spartacuus:BAAALAAECggIEAAAAA==.',Su='Suchdotswow:BAAALAADCgEIAQAAAA==.',Sv='Svetlomet:BAAALAAECgIIAgABLAAECggIGwADAMQfAA==.',Te='Tecrapintrei:BAAALAAECgMIBQAAAA==.',Th='Therealmcroy:BAABLAAECoEhAAIaAAgIoh8HGADOAgAaAAgIoh8HGADOAgAAAA==.Throrn:BAABLAAECoEhAAIHAAgIIRO0OwAJAgAHAAgIIRO0OwAJAgAAAA==.',To='Toraz:BAAALAADCgcIBwAAAA==.',Tr='Trollny:BAAALAAECgYICQABLAAECggIGwAFAMIdAA==.',Tw='Twelfdk:BAAALAAECgIIAgAAAA==.',Ub='Ubba:BAAALAADCggICAAAAA==.',Ug='Uglybull:BAAALAADCgYIBgAAAA==.Uglyvulp:BAACLAAFFIEIAAMbAAII3xmlEwCcAAAbAAIIbA6lEwCcAAAcAAEIHBuREgBRAAAsAAQKgSIAAxsACAgTIokJAOMCABsACAjaIIkJAOMCABwAAwjlHcoqAP0AAAAA.',Un='Unariel:BAAALAADCgUIAwAAAA==.Ungentle:BAAALAAECgMIBgAAAA==.Unohana:BAAALAAECgYIEgAAAA==.',Ut='Uti:BAAALAADCggICwAAAA==.',Va='Varjovasama:BAAALAADCgcIDgAAAA==.',Ve='Vecernice:BAAALAADCgUIBQABLAAECggIGwADAMQfAA==.',Vo='Voidlord:BAABLAAECoEkAAIYAAgILx3rGwC9AgAYAAgILx3rGwC9AgAAAA==.',Wa='Warpath:BAABLAAECoEWAAMVAAgI/xCSJwC+AQAVAAgI/xCSJwC+AQAdAAcINgLkKgBiAAAAAA==.Warrwîk:BAAALAAECggIEgAAAA==.',We='Weltiran:BAACLAAFFIEFAAIFAAIIOROlPgCSAAAFAAIIOROlPgCSAAAsAAQKgRUAAgUABwjlGaNwANkBAAUABwjlGaNwANkBAAAA.',Xa='Xant:BAAALAADCggIDgAAAA==.',Xy='Xynovia:BAAALAADCgMIAgABLAAECggICQANAAAAAA==.',Za='Zaknazaar:BAABLAAECoEdAAILAAgInCApDwDTAgALAAgInCApDwDTAgAAAA==.Zambarth:BAAALAADCgYIDQAAAA==.Zarae:BAABLAAECoEZAAMaAAYIhBoOcQCRAQAaAAYIhBoOcQCRAQAeAAEIaRI3rgAtAAAAAA==.',Ze='Zesvaflown:BAABLAAECoEYAAIJAAgIgh5EEwCxAgAJAAgIgh5EEwCxAgABLAAFFAIICAAOAMIfAA==.',Zh='Zhivotnoto:BAAALAADCggIDwAAAA==.',Zo='Zombaa:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end