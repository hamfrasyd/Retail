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
 local lookup = {'Warlock-Demonology','Warlock-Destruction','Druid-Restoration','DemonHunter-Havoc','Rogue-Assassination','Druid-Balance','Mage-Frost','Mage-Arcane','Priest-Holy','Priest-Discipline','Hunter-BeastMastery','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Druid-Guardian','Paladin-Holy','Warlock-Affliction','Priest-Shadow','Paladin-Protection','Warrior-Fury','Hunter-Marksmanship','Shaman-Elemental','Shaman-Restoration','DeathKnight-Blood','DeathKnight-Unholy','Evoker-Devastation','Warrior-Protection','Monk-Mistweaver','Druid-Feral','Rogue-Outlaw','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Vengeance','Warrior-Arms','Rogue-Subtlety','Evoker-Augmentation','Evoker-Preservation','Hunter-Survival',}; local provider = {region='EU',realm='Zenedar',name='EU',type='weekly',zone=44,date='2025-09-23',data={Ad='Adinferno:BAAALAADCgUICAAAAA==.',Ae='Ae:BAAALAADCgcICwAAAA==.',Ag='Aggereth:BAABLAAECoEUAAMBAAgIZhWqEwA/AgABAAgIZhWqEwA/AgACAAEISQYF2wAuAAAAAA==.',Ai='Aiwendul:BAABLAAECoEcAAIDAAgIXhTeOQC+AQADAAgIXhTeOQC+AQAAAA==.',Ak='Akuma:BAABLAAECoEdAAIEAAgIphVOSAAZAgAEAAgIphVOSAAZAgAAAA==.',Al='Alfôr:BAACLAAFFIEOAAIFAAUIIxmeAQDWAQAFAAUIIxmeAQDWAQAsAAQKgS4AAgUACAhjI34EACkDAAUACAhjI34EACkDAAAA.Algra:BAAALAAECgcIDwAAAA==.Allyguurda:BAAALAADCgQIBAAAAA==.Alzuldahomar:BAABLAAECoEjAAIGAAgIzSGJCgAGAwAGAAgIzSGJCgAGAwAAAA==.Aléyna:BAACLAAFFIELAAMHAAUI2A7nAwDtAAAIAAUIXAd8DwBsAQAHAAMI1hbnAwDtAAAsAAQKgSYAAwcACAjSI44UAFUCAAgABwjaH/MoAIwCAAcACAhQHI4UAFUCAAAA.',Am='Amstelor:BAACLAAFFIEMAAIJAAUIIAmlBwBrAQAJAAUIIAmlBwBrAQAsAAQKgR4AAwkACAi6FAwqAB4CAAkACAi6FAwqAB4CAAoAAQiRB8Y0ACoAAAAA.',An='Andid:BAABLAAECoEVAAMCAAcIYxPsTQDSAQACAAcIYxPsTQDSAQABAAQIAAAAAAAAAAABLAAECggIJQALABYiAA==.Antoria:BAABLAAECoEVAAIMAAcIuSBVSQA4AgAMAAcIuSBVSQA4AgAAAA==.',Ap='Apapapa:BAAALAADCggICAAAAA==.Appolonia:BAAALAAECgYIDwAAAA==.',Ar='Arazux:BAAALAAECgEIAQAAAA==.Arûhim:BAABLAAECoEgAAIMAAgIvgtfgAC9AQAMAAgIvgtfgAC9AQAAAA==.',As='Ashbringer:BAAALAAECgcIEAAAAA==.Astrian:BAABLAAECoEdAAINAAcI+h9LMACGAgANAAcI+h9LMACGAgAAAA==.',At='Atrius:BAAALAADCggICgAAAA==.',Au='Aura:BAAALAAECgUIBQAAAA==.',Av='Avell:BAAALAAECgcIBwAAAA==.',Az='Azadall:BAAALAAECgUIBgABLAAECgcIEwAOAAAAAA==.Azarel:BAAALAAECgcIEwAAAA==.',Ba='Baalsamael:BAAALAAECgYIDAAAAA==.Backstab:BAAALAADCgYIBgAAAA==.Bae:BAAALAADCgMIAwAAAA==.Baffe:BAAALAAECgYICgAAAA==.Balrogg:BAAALAADCggIDQAAAA==.Barely:BAABLAAECoEeAAMGAAgIKSBRDQDnAgAGAAgI/x9RDQDnAgAPAAUIxRb6FQAzAQAAAA==.',Be='Belorie:BAABLAAECoEgAAMNAAgIeSDFIgDCAgANAAgIeSDFIgDCAgAQAAQIShZJQwAMAQAAAA==.Berylia:BAAALAAECgYICwAAAA==.Bestinslot:BAAALAAECggICAAAAA==.',Bh='Bhorkita:BAAALAADCgcIBwAAAA==.',Bi='Bigdix:BAAALAADCggICAABLAAECgcIFAAPAMQMAA==.Bigmuff:BAABLAAECoEaAAMCAAgI6hpIKgBrAgACAAgI6hpIKgBrAgARAAEIdRcAOgA9AAAAAA==.Bilbobaggins:BAAALAAECgUIBgAAAA==.',Bl='Blasphemia:BAACLAAFFIEIAAISAAMI6h/WCgAYAQASAAMI6h/WCgAYAQAsAAQKgS4AAhIACAjfJNgEAFEDABIACAjfJNgEAFEDAAAA.Blastin:BAAALAAECgMIBAAAAA==.Bleurgh:BAAALAAECgcIBwAAAA==.Blindsteve:BAAALAADCgQIBQAAAA==.Blueballs:BAAALAAECgIIAgABLAAECgYIDAAOAAAAAA==.',Bo='Bonfíre:BAAALAADCggICwAAAA==.Bonzai:BAAALAAECggIAgAAAA==.Bonè:BAABLAAECoEZAAITAAgIHhJSHwC/AQATAAgIHhJSHwC/AQAAAA==.Borah:BAAALAAECgEIAQABLAAECggIEwAUALQiAA==.Bossen:BAACLAAFFIEOAAIDAAUI8B7yAgDXAQADAAUI8B7yAgDXAQAsAAQKgS4AAwMACAiwIw0NANECAAMACAiwIw0NANECAAYABghADsNRADEBAAAA.',Bt='Btiy:BAABLAAECoEWAAIGAAYIRxT6QgBxAQAGAAYIRxT6QgBxAQAAAA==.',Bu='Bubblefett:BAABLAAECoEYAAMNAAgIIx9ZJgCxAgANAAgIIx9ZJgCxAgATAAUIpQxzRAC6AAAAAA==.Bullukka:BAAALAAECgYIBgABLAAECggIHwALAA0iAA==.Butterfly:BAAALAAECgQIBQAAAA==.Buuffalo:BAAALAAECgUIBQAAAA==.Buuldan:BAAALAADCgMIAwAAAA==.',['Bé']='Bénder:BAAALAADCggICAABLAAFFAIIBQASAKggAA==.',['Bö']='Börre:BAAALAAECgYICAAAAA==.',Ca='Carelei:BAACLAAFFIEFAAISAAIIqCAKEgCtAAASAAIIqCAKEgCtAAAsAAQKgSEAAhIACAhjHvISAMACABIACAhjHvISAMACAAAA.Carmone:BAAALAAECgYIDQAAAA==.',Ch='Chadstalker:BAABLAAECoElAAMLAAgIFiKCGwC8AgALAAgIFiKCGwC8AgAVAAQIQBpwdwDPAAAAAA==.Chaóz:BAAALAADCggICAAAAA==.Chitan:BAAALAADCggICAAAAA==.Christer:BAAALAAECgcIEAAAAA==.',Ci='Cindraya:BAAALAAECgIIAgAAAA==.',Co='Cold:BAAALAADCgYIBgAAAA==.',Cr='Craig:BAAALAADCgQIBgAAAA==.Cryto:BAABLAAECoEfAAIQAAgIcx80BwDcAgAQAAgIcx80BwDcAgAAAA==.',Cu='Curvaguutee:BAABLAAECoEcAAMWAAgIKxmHIgBtAgAWAAgIKxmHIgBtAgAXAAMILQMW9gBVAAAAAA==.Cuso:BAAALAAECggICgAAAA==.',Da='Darai:BAABLAAECoEXAAIVAAgI7Rf+JAArAgAVAAgI7Rf+JAArAgAAAA==.Darnia:BAAALAADCggIEAAAAA==.',De='Deathbacon:BAAALAADCggICAAAAA==.Deathboyslim:BAABLAAECoEoAAIMAAgIWiAXGQDwAgAMAAgIWiAXGQDwAgAAAA==.Deathfad:BAABLAAECoEZAAQMAAgIFBuGMwB9AgAMAAgIFBuGMwB9AgAYAAUI8AR8LwChAAAZAAEIbgBSWgACAAABLAAFFAIICAAIALggAA==.Demonis:BAAALAAECgYICAAAAA==.Dethfele:BAAALAAECgYIBgAAAA==.Devilhunt:BAAALAAECggIDgAAAA==.',Di='Dico:BAAALAAECggIEwAAAA==.',Dr='Dragon:BAAALAADCgcIBgAAAA==.Drakarys:BAAALAAECgcIEgAAAA==.Drakiz:BAAALAAECgYIBgAAAA==.Drphil:BAABLAAECoERAAIZAAYIqR3nFAAFAgAZAAYIqR3nFAAFAgAAAA==.',['Dê']='Dêaqon:BAABLAAECoEbAAIVAAgIHhssGgB7AgAVAAgIHhssGgB7AgAAAA==.',Ec='Ecthelion:BAAALAAECgMIAwAAAA==.',Ei='Eirithur:BAABLAAECoEXAAIaAAYI+B0IIAD4AQAaAAYI+B0IIAD4AQAAAA==.',Ek='Ekshi:BAAALAAECgcIBgABLAAECggIJQALABYiAA==.',El='Elaniel:BAABLAAECoEcAAIEAAgIkxE5XgDeAQAEAAgIkxE5XgDeAQAAAA==.Elementard:BAAALAAECgEIAQABLAAECggIGgAEAEsZAA==.',Em='Emmzi:BAABLAAECoEaAAIEAAgISxmtNgBXAgAEAAgISxmtNgBXAgAAAA==.Empress:BAABLAAECoEUAAQRAAgIwBLDEgBuAQARAAYIEBDDEgBuAQACAAgI7guJdwBXAQABAAEIZhNHhAA7AAAAAA==.',En='Endre:BAAALAADCgYICwAAAA==.',Ep='Epicdruid:BAAALAAECgYIBgAAAA==.Epicevoker:BAAALAADCgEIAQAAAA==.Epichunt:BAAALAADCgEIAQAAAA==.Epicpally:BAAALAADCgIIAgAAAA==.',Ev='Evilidaofc:BAAALAAECgUIBQAAAA==.',Ex='Exdeusdruid:BAABLAAECoEeAAIDAAgI4Bt3GABxAgADAAgI4Bt3GABxAgAAAA==.Exodiua:BAAALAADCgcIBwAAAA==.Exodius:BAAALAAECggICAAAAA==.',['Eæ']='Eætank:BAAALAADCgIIAgAAAA==.',Fa='Fahmy:BAABLAAECoEYAAMXAAgI/A+mXACdAQAXAAgI/A+mXACdAQAWAAEItQLZrwAnAAAAAA==.',Fe='Felpunch:BAAALAADCgcIEQAAAA==.',Fj='Fjodor:BAAALAAECgYIBgAAAA==.',Fl='Flaze:BAAALAAECggICAAAAA==.Flecha:BAAALAADCggIEAAAAA==.Flipaides:BAAALAAECgUICwAAAA==.',Fo='Foal:BAABLAAECoEcAAMSAAgIgRd8LQD4AQASAAcIGRd8LQD4AQAJAAcIAhbONgDcAQAAAA==.Foalduran:BAAALAADCgcIBwABLAAECggIHAASAIEXAA==.Fotovolidos:BAAALAAECgQIAQAAAA==.',Fr='Frófró:BAACLAAFFIEJAAIVAAUIhxCCBgBpAQAVAAUIhxCCBgBpAQAsAAQKgS4AAhUACAhHHxERAMoCABUACAhHHxERAMoCAAAA.',Fu='Fukntonk:BAABLAAECoEUAAIbAAgIyRZUHAAVAgAbAAgIyRZUHAAVAgAAAA==.',Ga='Gablegable:BAAALAADCggICAAAAA==.Gammeldoge:BAAALAAECggIAwAAAA==.',Ge='Geglash:BAABLAAECoEiAAIHAAgIZiKxBQAkAwAHAAgIZiKxBQAkAwAAAA==.',Gi='Gigglezz:BAAALAAECgYIDAABLAAECggIHAASABgcAA==.Gilmas:BAAALAADCgYIBgAAAA==.Giraia:BAAALAAECgUIBQAAAA==.',Gs='Gster:BAAALAAECgEIAQAAAA==.',Gu='Guldrek:BAAALAADCgIIAwABLAAFFAIIAgAOAAAAAA==.',Ha='Hakhan:BAAALAAECgYICwAAAA==.Happysteven:BAAALAADCgEIAQABLAADCgQIBQAOAAAAAA==.Harleen:BAAALAADCggIDAABLAAECggIIwAGAM0hAA==.Havkat:BAAALAAECgIIAgAAAA==.',He='Heltseriös:BAACLAAFFIEMAAIGAAUIPR9eAwDcAQAGAAUIPR9eAwDcAQAsAAQKgS0AAwYACAg2Jn4BAH0DAAYACAg2Jn4BAH0DAAMABAg4DNCLALEAAAAA.Hengenpaimen:BAAALAADCgcICwABLAAECggIJAARAFIgAA==.Hexfang:BAAALAADCgUIBQAAAA==.',Hi='Highmane:BAAALAAECgYICgAAAA==.Hirolde:BAAALAADCgcIBwAAAA==.',Ho='Holyhäst:BAAALAAFFAEIAQABLAAFFAMIBQADAGcOAA==.Honungswoff:BAAALAADCggICAAAAA==.Hooligun:BAAALAAECgYIBgABLAAFFAIIBQASAKggAA==.Hoskii:BAABLAAECoEbAAIIAAgILwtpYQC7AQAIAAgILwtpYQC7AQAAAA==.',Hu='Huntdogeski:BAAALAADCggICAAAAA==.',Hy='Hyödyntäjä:BAAALAADCggIEAAAAA==.',['Hä']='Hästkraften:BAACLAAFFIEFAAIDAAMIZw5XDwDLAAADAAMIZw5XDwDLAAAsAAQKgRwAAwMACAiNGv4YAG4CAAMACAiNGv4YAG4CAAYAAQgjBwOUACUAAAAA.',Id='Idktactics:BAAALAADCgYIBgAAAA==.',Ja='Jab:BAAALAADCgcIBwAAAA==.Jagärböb:BAACLAAFFIENAAIaAAUIxRseBADLAQAaAAUIxRseBADLAQAsAAQKgSoAAhoACAh1IwcFADQDABoACAh1IwcFADQDAAAA.Jamx:BAAALAAECgYIBwAAAA==.',Je='Jedbartlet:BAABLAAECoEoAAIEAAgInySqBwBTAwAEAAgInySqBwBTAwAAAA==.Jeskud:BAABLAAECoEYAAIGAAgItxsIGQBrAgAGAAgItxsIGQBrAgAAAA==.',Jo='Jorgen:BAABLAAECoEUAAMYAAYIfRH0HgBMAQAYAAYIfRH0HgBMAQAZAAQIkwE/RwB1AAAAAA==.',['Jä']='Jäätynyt:BAABLAAECoEcAAIYAAgIzhtODQBGAgAYAAgIzhtODQBGAgAAAA==.',Ka='Kalidan:BAAALAAECgEIAQAAAA==.Kameelpewpew:BAAALAADCgYIBgAAAA==.Kamelpewdk:BAABLAAECoEXAAIMAAYI9iAUSwA0AgAMAAYI9iAUSwA0AgAAAA==.Kataramenosr:BAAALAAECgUICgAAAA==.',Ke='Kehveli:BAAALAADCggIDwAAAA==.',Kh='Khyber:BAAALAADCgcIDQAAAA==.',Ki='Kivesleipuri:BAAALAADCgUIBQABLAAECggIHwALAA0iAA==.',Ko='Kokhammer:BAAALAAECgYICwABLAAECggIEwAOAAAAAA==.',Kr='Krakatoa:BAABLAAECoEcAAMWAAcIUxGSYABfAQAWAAYIDA6SYABfAQAXAAcIJg00hgA0AQAAAA==.',Kt='Ktdru:BAAALAADCgIIAgAAAA==.',Ku='Kultapoika:BAAALAAECggIEAAAAA==.Kumana:BAAALAADCgMIAwAAAA==.',La='Lathisa:BAAALAAECgYIBQAAAA==.',Le='Leecter:BAAALAAECgMIAwAAAA==.Lemmy:BAAALAADCggIBgAAAA==.Leprotect:BAABLAAECoEiAAMNAAgIMB+qHgDWAgANAAgIMB+qHgDWAgAQAAEIrAdTZAA2AAAAAA==.',Li='Lisko:BAAALAAECgQIBgAAAA==.',Lo='Loaofapes:BAAALAAECgYIEgABLAAECgcIFQAMALkdAA==.Loladiini:BAABLAAECoEdAAIQAAgIgQ3jJwCqAQAQAAgIgQ3jJwCqAQAAAA==.',Lu='Luxmodar:BAAALAAECgYIDgABLAAFFAIIBQACAGAVAA==.',Ma='Machodk:BAACLAAFFIEMAAIMAAUIWRtSBgDjAQAMAAUIWRtSBgDjAQAsAAQKgS0AAgwACAh1JncCAHsDAAwACAh1JncCAHsDAAAA.Machô:BAAALAADCggICAABLAAFFAIIBQASAKggAA==.Maddas:BAABLAAECoEeAAIXAAgI9xgDLAA7AgAXAAgI9xgDLAA7AgAAAA==.Magnificence:BAAALAADCgYIBgABLAAFFAIIBQACAGAVAA==.Mammazmage:BAAALAAECgYICgABLAAFFAUIDgAcAJAQAA==.Mammazmunk:BAACLAAFFIEOAAIcAAUIkBC/AwCOAQAcAAUIkBC/AwCOAQAsAAQKgS4AAhwACAhjIpUEAAkDABwACAhjIpUEAAkDAAAA.Mamose:BAAALAADCgIIAgAAAA==.Mashonos:BAAALAADCgUIBQABLAAFFAUIDAAJACAJAA==.Maybetank:BAAALAADCggIDwAAAA==.Mayz:BAABLAAECoETAAIUAAgItCKVDQAfAwAUAAgItCKVDQAfAwAAAA==.',Me='Meatball:BAAALAADCggICAAAAA==.Mechahun:BAAALAAECgQIBAAAAA==.Mejch:BAAALAADCgIICQABLAAFFAIIAgAOAAAAAA==.Menethar:BAAALAADCggICAAAAA==.Mesmori:BAACLAAFFIEIAAIdAAMIHBb2AwAIAQAdAAMIHBb2AwAIAQAsAAQKgScAAh0ACAjgJU0BAGQDAB0ACAjgJU0BAGQDAAAA.',Mi='Miksuu:BAABLAAECoEcAAIeAAgIkBBRBwAJAgAeAAgIkBBRBwAJAgAAAA==.Mirata:BAAALAADCgUIBQABLAADCgcIDQAOAAAAAA==.',Mo='Mohdzadeh:BAAALAADCgcIBwAAAA==.Moikani:BAABLAAECoElAAIGAAgIJx+MDwDOAgAGAAgIJx+MDwDOAgAAAA==.Monarchx:BAAALAAECggIEAAAAA==.Monkbacon:BAAALAADCgcIDQAAAA==.Monkeponke:BAACLAAFFIENAAIfAAQICRA6BABDAQAfAAQICRA6BABDAQAsAAQKgTQAAx8ACAg6IowGABIDAB8ACAg6IowGABIDACAAAwivFrIvAMoAAAAA.Morningstar:BAABLAAECoEhAAIMAAgIbBvyQQBOAgAMAAgIbBvyQQBOAgAAAA==.',Mu='Munckyoyo:BAAALAADCgcIBwAAAA==.',My='Myrkgy:BAAALAAECgYIAwAAAA==.',['Mö']='Möhnä:BAAALAADCgcIBwAAAA==.',['Mü']='Mürf:BAACLAAFFIELAAIUAAUIrhC1BwC0AQAUAAUIrhC1BwC0AQAsAAQKgS4AAhQACAhlJTUFAGEDABQACAhlJTUFAGEDAAAA.',Na='Nables:BAAALAADCggICAAAAA==.Nacchi:BAABLAAECoEoAAIZAAgIeyYrAACWAwAZAAgIeyYrAACWAwAAAA==.Nagraz:BAABLAAECoEcAAIeAAgI3AnYCgCnAQAeAAgI3AnYCgCnAQAAAA==.Navia:BAAALAADCggICAAAAA==.',Ne='Nej:BAAALAADCgYIBgABLAAECggIEQAZAKkdAA==.Nezuko:BAABLAAECoEcAAIhAAgIrxcSEQAkAgAhAAgIrxcSEQAkAgAAAA==.',No='Nobodyy:BAABLAAECoEXAAIWAAgIyRSrLAAyAgAWAAgIyRSrLAAyAgABLAAFFAQIDQAZAE8UAA==.Noltreza:BAAALAAECgIIAgAAAA==.',Nu='Nubcake:BAABLAAECoEoAAINAAgIWx6mKACnAgANAAgIWx6mKACnAgAAAA==.',['Në']='Nëcro:BAAALAADCgIIAgAAAA==.',['Nò']='Nòa:BAAALAAECgQIBgAAAA==.',Om='Oma:BAAALAAECgYIBgAAAA==.',Oq='Oqzu:BAABLAAECoEbAAIiAAgIJxK5CwD8AQAiAAgIJxK5CwD8AQAAAA==.',Ov='Overtop:BAAALAADCgcIBwAAAA==.',Ox='Oxen:BAAALAAECgYICgAAAA==.Oxycontin:BAAALAADCgUIBQAAAA==.',Pa='Paltmääh:BAAALAADCgYIBgAAAA==.Pannahinen:BAAALAAECgcIBwAAAA==.Paranormal:BAAALAAECggIEAAAAA==.Pask:BAAALAADCggIDAAAAA==.Patriarken:BAACLAAFFIEIAAMBAAUI2BakAABkAQABAAQIwhekAABkAQACAAIIlBI1IACzAAAsAAQKgS4AAwEACAjQIhAEABgDAAEACAi3IhAEABgDAAIABQgUHDBbAKcBAAAA.Patron:BAAALAAECgMIBAAAAA==.Paulina:BAAALAAECgQIBAAAAA==.',Pe='Petronella:BAAALAADCggICAAAAA==.',Ph='Phftevie:BAAALAAECgUIBQAAAA==.',Po='Polli:BAAALAADCggICwAAAA==.',Pr='Premiumwound:BAAALAADCgcIBwAAAA==.',Qr='Qrmas:BAABLAAECoEbAAMMAAgIEiEBIgDGAgAMAAgIASEBIgDGAgAYAAYITR1eFgC2AQAAAA==.',Ra='Radiostyle:BAAALAADCgUIBQAAAA==.',Re='Renault:BAAALAADCggIEAAAAA==.Revenge:BAABLAAECoEbAAIUAAgIqh9sFQDmAgAUAAgIqh9sFQDmAgAAAA==.Rexarian:BAAALAAECgYIBgABLAAECggIGgAEAEsZAA==.Rezon:BAAALAADCgYIBgAAAA==.',Ri='Risky:BAAALAAECgcICAAAAA==.',Ro='Rossdormu:BAABLAAECoEWAAIaAAcIyhtzGgAvAgAaAAcIyhtzGgAvAgAAAA==.',Ru='Ruggugglat:BAAALAADCgYIBgAAAA==.',Sa='Sairen:BAABLAAECoEfAAITAAgIqxiwGAD5AQATAAgIqxiwGAD5AQAAAA==.Salai:BAAALAADCgIIAgAAAA==.Salaioo:BAAALAADCgUIBQAAAA==.Saltmuch:BAABLAAECoEfAAIDAAgIeQ+IQwCVAQADAAgIeQ+IQwCVAQAAAA==.Samhanta:BAAALAADCggICAAAAA==.Sandyclaws:BAAALAAECggICAAAAA==.Saymynamebit:BAAALAAECggICAABLAAFFAQIDQAZAE8UAA==.',Sc='Scariett:BAAALAAECggICAAAAA==.',Se='Sehaine:BAAALAAECgMIAwAAAA==.Selkath:BAAALAAECgEIAQAAAA==.Serpian:BAACLAAFFIEFAAICAAIIYBXJJgCfAAACAAIIYBXJJgCfAAAsAAQKgSMAAgIACAhjISwUAPECAAIACAhjISwUAPECAAAA.Sethaap:BAAALAADCgUIBQAAAA==.Setth:BAAALAAECgEIAgAAAA==.Settofatto:BAAALAADCgUIBQAAAA==.',Sh='Shadowsemp:BAAALAADCgUIBQAAAA==.Shai:BAAALAAECggICAAAAA==.Shammymaster:BAAALAAECggIEgAAAA==.Shiroioni:BAAALAAECgYIDgAAAA==.',Si='Sister:BAAALAADCggIEAABLAAECggIHgAGACkgAA==.',Sk='Skadi:BAAALAADCggICAAAAA==.Skrallan:BAACLAAFFIEOAAMhAAUIRBVOAQCEAQAhAAUIRBVOAQCEAQAEAAEIbwFdRgA8AAAsAAQKgS4AAyEACAjLHmsJAJwCACEACAisHmsJAJwCAAQACAjoGQYyAGoCAAAA.Skybreaker:BAAALAADCgUIBQAAAA==.',Sl='Slushie:BAAALAAECgYICwAAAA==.',Sn='Snosk:BAAALAAECggIBAAAAA==.',So='Sokaris:BAAALAAECgYIDwAAAA==.Soulnius:BAAALAAECgQIAgAAAA==.',Sp='Spellsender:BAAALAAECgEIAQAAAA==.',Ss='Ssjgoku:BAAALAADCgcIAwAAAA==.',St='Striker:BAAALAAECgYIEgAAAA==.Stuffy:BAAALAAECgcIEQAAAA==.Stycket:BAAALAADCgcIBwAAAA==.',Su='Surkimus:BAABLAAECoEmAAMCAAgIPhyeIwCQAgACAAgIPhyeIwCQAgARAAIIFwwiLQBuAAAAAA==.Sushiroll:BAABLAAECoEWAAQgAAgImQjQJQAlAQAgAAcIjAnQJQAlAQAcAAEIrQKASgAdAAAfAAcIZAC4XwANAAAAAA==.',Sw='Sweristell:BAAALAAECgYIBgAAAA==.',['Sà']='Sàlái:BAAALAAECgEIAQAAAA==.',Ta='Tappiukko:BAABLAAECoEfAAILAAgIDSItDwAIAwALAAgIDSItDwAIAwAAAA==.Tarnishedd:BAAALAAFFAIIAgAAAA==.',Te='Teach:BAABLAAECoEXAAIMAAgI+xN+eQDKAQAMAAgI+xN+eQDKAQAAAA==.Teekkari:BAAALAAECggIDwAAAA==.Temetias:BAABLAAECoEhAAMCAAgIKiR9CQA8AwACAAgIKiR9CQA8AwARAAIIyCPpJACjAAAAAA==.Temmetias:BAAALAAECgUIBQABLAAECggIIQACACokAA==.',Th='Thelaren:BAABLAAECoEkAAIRAAgIUiBsAgDzAgARAAgIUiBsAgDzAgAAAA==.Thomasandre:BAAALAAECggIDgAAAA==.Thrashnbash:BAAALAADCggIEAAAAA==.Thunderacdc:BAABLAAECoEVAAINAAgImiAAGwDrAgANAAgImiAAGwDrAgAAAA==.Thundercoil:BAAALAADCggICAAAAA==.Thunderhand:BAAALAAECgYIDwAAAA==.',Ti='Tinymage:BAACLAAFFIEIAAIIAAIIuCCgIwC2AAAIAAIIuCCgIwC2AAAsAAQKgSkAAggACAgMJKcLACsDAAgACAgMJKcLACsDAAAA.',To='Togouchi:BAAALAADCggICAAAAA==.Tohtorivarjo:BAABLAAECoEgAAMFAAgIsiAYCwDQAgAFAAgIsiAYCwDQAgAjAAgI4ReACwBXAgAAAA==.Tokaku:BAAALAAECggIEgAAAA==.Toothles:BAAALAADCgQIBgAAAA==.',Tr='Treehoney:BAAALAADCgcIGAAAAA==.Trillux:BAAALAAECgYIDAAAAA==.Trillöx:BAABLAAECoEZAAMWAAgIKRyxGwCdAgAWAAgIKRyxGwCdAgAXAAcI2g28fQBHAQAAAA==.Trollen:BAAALAAECgYIBgAAAA==.Tréébear:BAAALAAECgUIBQAAAA==.',Ts='Tsarina:BAAALAADCgYIBgAAAA==.',Tw='Twentyone:BAAALAAECgYICwAAAA==.',Ty='Tyrion:BAABLAAECoEbAAMLAAgIsRweJQCGAgALAAgIsRweJQCGAgAVAAEIvRIBsAAtAAAAAA==.',Ut='Uthgor:BAABLAAECoEZAAMXAAgINhPhnQACAQAXAAYIlA3hnQACAQAWAAIIyQcUmgBoAAAAAA==.',Va='Vados:BAABLAAECoEWAAIIAAgIdw/uTAD6AQAIAAgIdw/uTAD6AQABLAAECggIIwAGAM0hAA==.Valow:BAAALAAECgIIAgAAAA==.Vantablack:BAAALAAECgEIAQABLAAFFAIIBQACAGAVAA==.Varon:BAAALAAECggICwAAAA==.Vator:BAABLAAECoEaAAIbAAgICiIhBgAdAwAbAAgICiIhBgAdAwABLAAFFAIICAAIALggAA==.',Ve='Veertje:BAABLAAECoEVAAIHAAYIshBHOABoAQAHAAYIshBHOABoAQAAAA==.Verm:BAAALAAECgcIDQAAAA==.',Vi='Vilhelmina:BAAALAAFFAIIAgAAAA==.Vindemiatrix:BAABLAAECoEcAAMcAAYIUgcrMgDZAAAcAAYIUgcrMgDZAAAfAAUIEALJTgBmAAAAAA==.',Vo='Voidgigz:BAABLAAECoEcAAMSAAgIGBxBGgCAAgASAAgIGBxBGgCAAgAJAAYISxOwUwBhAQAAAA==.Vonherra:BAABLAAECoEZAAMfAAgIBRsbGwD6AQAfAAcI+RobGwD6AQAcAAgIpgg+JgA5AQAAAA==.Vorgla:BAAALAAECgcIEwAAAA==.Vouvali:BAAALAADCggICAAAAA==.',Vu='Vulhun:BAAALAADCggIEAAAAA==.',Wa='Waltzer:BAAALAAECgYIBgABLAAECggIEwAOAAAAAA==.Wartezia:BAABLAAECoEWAAIUAAYIfAwoeABNAQAUAAYIfAwoeABNAQAAAA==.',Wh='Whiteluna:BAAALAAECggIEgAAAA==.',Wo='Workkworkk:BAABLAAECoEdAAMWAAgIJB6NFQDOAgAWAAgIJB6NFQDOAgAXAAMIogJG+ABQAAAAAA==.',Xa='Xalvedor:BAAALAAECgIIAgAAAA==.',Xe='Xeoz:BAAALAAECgcIDAAAAA==.Xeromus:BAAALAADCggIEAAAAA==.',Xi='Xingfu:BAAALAAECgQIBAAAAA==.',Xu='Xurknight:BAAALAAECggIEQABLAAFFAYIEwAaAKwXAA==.Xurudin:BAAALAAECgQICAABLAAFFAYIEwAaAKwXAA==.Xurukin:BAACLAAFFIETAAMaAAYIrBdGBQCjAQAkAAUI1BOTAQCqAQAaAAUIZBhGBQCjAQAsAAQKgSQAAhoACAiiJAAHABUDABoACAiiJAAHABUDAAAA.',Xy='Xylo:BAAALAADCggIDgAAAA==.',['Xé']='Xéphanite:BAABLAAECoEcAAIcAAgIdxguEAA7AgAcAAgIdxguEAA7AgAAAA==.',Yu='Yuzuki:BAAALAADCgUIBgAAAA==.',Za='Zanopipe:BAAALAAECgMIBgAAAA==.Zappie:BAAALAAECgYIBgAAAA==.Zayla:BAAALAADCggIGQAAAA==.',Ze='Zeision:BAABLAAECoEeAAMlAAgI4w7EFACyAQAlAAgI4w7EFACyAQAaAAMIDQX8UwBhAAAAAA==.Zeptow:BAABLAAECoEbAAISAAgIaCINCwANAwASAAgIaCINCwANAwAAAA==.Zezhva:BAAALAADCggIKAAAAA==.',Zi='Zium:BAABLAAECoEWAAMJAAgIwwwhSACOAQAJAAgIwwwhSACOAQASAAQISwrJZwDPAAAAAA==.',Zo='Zogzóg:BAAALAAECgUIBgABLAAECggIEQAZAKkdAA==.',Zu='Zulfir:BAAALAAECgYIDQAAAA==.',Zv='Zvezda:BAAALAAECggIEwABLAAFFAMIBwAmAGwTAA==.',Zy='Zyntharen:BAAALAAECgYIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end