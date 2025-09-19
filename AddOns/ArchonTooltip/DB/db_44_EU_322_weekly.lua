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
 local lookup = {'Unknown-Unknown','Mage-Arcane','Hunter-Survival','Monk-Brewmaster','Warrior-Fury','Mage-Frost','Mage-Fire','Paladin-Holy','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Devastation','Paladin-Protection','DeathKnight-Frost','Druid-Feral','Warrior-Arms','Druid-Restoration','Hunter-BeastMastery','Rogue-Subtlety','Rogue-Outlaw','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Paladin-Retribution','Priest-Holy','Rogue-Assassination','Druid-Guardian','Hunter-Marksmanship','Shaman-Restoration','DemonHunter-Havoc','Monk-Mistweaver','Shaman-Elemental','DeathKnight-Blood',}; local provider = {region='EU',realm='Ravenholdt',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ae='Aeonthe:BAAALAAECgYIEAAAAA==.',Ai='Aizendk:BAAALAAECggIDgAAAA==.Aizenstab:BAAALAADCgcIBwABLAAECggIDgABAAAAAA==.',Al='Alrisaera:BAAALAAECgcIEAAAAA==.Alwaysborne:BAAALAADCgYIBgAAAA==.Alyssá:BAABLAAECoEbAAICAAgI+x9QEQDWAgACAAgI+x9QEQDWAgAAAA==.Alzu:BAABLAAECoEWAAIDAAcIYh9PAgCXAgADAAcIYh9PAgCXAgAAAA==.',Am='Ambrotor:BAAALAAECgcIEAAAAA==.',An='Annabéth:BAAALAAECgMIBAAAAA==.Anubarrak:BAAALAAECgYICgAAAA==.',Ar='Arleigh:BAEALAADCggICAABLAAFFAMICAAEAOsIAA==.Artemás:BAAALAADCgcIBwAAAA==.Arthrasz:BAAALAAECgQIBwABLAAFFAMIBgAFAKcaAA==.Aruál:BAACLAAFFIEGAAIGAAMIJxVxAQD2AAAGAAMIJxVxAQD2AAAsAAQKgR8AAgYACAhfIyMDACcDAAYACAhfIyMDACcDAAAA.Aruáll:BAAALAAFFAIIAgABLAAFFAMIBgAGACcVAA==.',As='Ashe:BAAALAAECgcIEAAAAA==.Ashynn:BAAALAADCggICAAAAA==.',Au='Aube:BAAALAADCgYIBgAAAA==.Auragen:BAABLAAECoEVAAICAAcIMx4EIQBhAgACAAcIMx4EIQBhAgAAAA==.Aurah:BAAALAADCggICAAAAA==.',Av='Avelîna:BAAALAAECgYICwAAAA==.',Az='Azalen:BAAALAADCggICAAAAA==.Azone:BAAALAAECgcIEAAAAA==.',['Aû']='Aûtumn:BAAALAAECgIIAgAAAA==.',Ba='Baladans:BAAALAADCgcIBwAAAA==.Balgho:BAAALAAECgcIBwAAAA==.Balgorok:BAAALAADCgUIBQAAAA==.',Be='Beelzeebub:BAAALAAECgIIAgAAAA==.',Bi='Bighunterman:BAAALAAECggICAABLAAFFAQIDQAFAMkeAA==.Bigpow:BAAALAADCggIDwAAAA==.Billydoll:BAAALAAECgYICQAAAA==.',Bl='Bladyos:BAABLAAECoEYAAIHAAgIjRaTAgBMAgAHAAgIjRaTAgBMAgAAAA==.',Bo='Bodgers:BAAALAADCgUIBQAAAA==.Bonkers:BAAALAAECggIAgAAAA==.Bothadis:BAAALAAECgYIDgAAAA==.',Bu='Bumbulerini:BAAALAAECgMIBQAAAA==.Bumbulio:BAAALAAECgcIBwAAAA==.Bumbulis:BAACLAAFFIEKAAIIAAQI+x6JAQCCAQAIAAQI+x6JAQCCAQAsAAQKgSAAAggACAjfITQDAOcCAAgACAjfITQDAOcCAAAA.Burdoc:BAAALAAECgYIDQAAAA==.',Bw='Bwarrior:BAAALAADCggIFQAAAA==.',Ca='Caelen:BAAALAADCggICAAAAA==.Caeven:BAACLAAFFIENAAIJAAQI/B85AgB+AQAJAAQI/B85AgB+AQAsAAQKgSAAAwkACAjbJX0BAG8DAAkACAjbJX0BAG8DAAoAAQi9C1ojADMAAAAA.Cazati:BAAALAADCggICAAAAA==.',Ce='Cephi:BAAALAAECggICQAAAA==.',Ch='Chloè:BAAALAADCgEIAQAAAA==.Chonkylee:BAABLAAECoEXAAILAAcImBkZEAASAgALAAcImBkZEAASAgAAAA==.Chrissi:BAAALAADCggIEAAAAA==.',Ci='Cibriks:BAAALAAECgQIBgABLAAFFAQIDQAFAMkeAA==.Cinderhood:BAAALAAECgcIEwAAAA==.',Co='Connelia:BAAALAAECgYIDAAAAA==.Coom:BAAALAAECgMIAwAAAA==.Cooney:BAAALAADCgcICAAAAA==.Cozystrasza:BAABLAAECoEWAAIMAAYIwhuFGADmAQAMAAYIwhuFGADmAQAAAA==.',Cr='Creedzable:BAACLAAFFIEIAAIFAAMIuCb2AgBcAQAFAAMIuCb2AgBcAQAsAAQKgRYAAgUACAj/JYsHAB4DAAUACAj/JYsHAB4DAAAA.',Cy='Cybershock:BAAALAAECgMIBgAAAA==.Cyne:BAACLAAFFIEHAAINAAQIkBzJAABXAQANAAQIkBzJAABXAQAsAAQKgRgAAg0ACAhNJSwBAGMDAA0ACAhNJSwBAGMDAAAA.Cyrano:BAAALAADCggICAABLAAFFAQIBwANAJAcAA==.',['Cé']='Céris:BAAALAADCggIFwAAAA==.',Da='Dajaf:BAAALAAFFAMIBAABLAAFFAUIAgABAAAAAA==.Dalrell:BAAALAADCgYIBgABLAAECgcIEgABAAAAAA==.Dammerflinn:BAAALAAECgcIEAAAAA==.Darknes:BAAALAAECggICwAAAA==.Daríon:BAAALAADCggIFAAAAA==.',De='Deadtibbs:BAAALAAFFAIIBAAAAA==.Deathwalksxd:BAAALAADCgUIBAAAAA==.Demonlove:BAAALAAECggIEwAAAA==.Demonrise:BAAALAADCgMIAgAAAA==.Demontard:BAAALAAECggIBwABLAAFFAQIDQAFAMkeAA==.Demontay:BAAALAADCggICAAAAA==.Desica:BAAALAADCgcIDQAAAA==.Destructiv:BAABLAAECoEXAAIOAAgIrgulSQC0AQAOAAgIrgulSQC0AQAAAA==.',Di='Dirahlia:BAAALAADCggICAAAAA==.',Do='Dotzilla:BAAALAAECgYIDQAAAA==.Doxxadruid:BAAALAAECgYIBgAAAA==.Doxxapapa:BAAALAAECgcIBgAAAA==.',Dr='Dracdeeznuts:BAAALAADCgcIBwAAAA==.Dracthel:BAAALAAECgIIAgAAAA==.',['Dë']='Dëvo:BAAALAAECgMIAwAAAA==.',['Dø']='Dødstrolden:BAAALAAECggIBgAAAA==.',El='Eliaskw:BAAALAAECgIIAgAAAA==.Elmoboom:BAAALAAECgcIBwAAAA==.Elnea:BAAALAAECgYIBwAAAA==.Elp:BAAALAAECggIDAABLAAFFAQIDQACAJ4hAA==.Elulin:BAAALAAECgIIAgABLAAFFAQIDQAJAPwfAA==.',En='Enzou:BAAALAAECgcIEAAAAA==.',Ep='Epinon:BAABLAAECoEXAAIJAAcI+hp8GwAdAgAJAAcI+hp8GwAdAgAAAA==.Epÿon:BAAALAADCgYIBgAAAA==.',Er='Erok:BAAALAADCggICAAAAA==.',Ev='Eversonn:BAAALAAECggIBQAAAA==.Evië:BAAALAADCgQIBAAAAA==.',Ez='Ezerak:BAAALAADCgcICAAAAA==.',Fe='Ferlain:BAAALAADCggIDwAAAA==.',Fi='Fikisulik:BAAALAAECgUIBgAAAA==.',Fl='Flap:BAAALAAECgcIEAAAAA==.',Fo='Follie:BAACLAAFFIELAAIPAAQIHBusAAB3AQAPAAQIHBusAAB3AQAsAAQKgSAAAg8ACAiLJUoAAH8DAA8ACAiLJUoAAH8DAAAA.Foxife:BAAALAADCgcIBwAAAA==.',Fu='Fulakazam:BAABLAAECoEYAAICAAgI1xaSKAAxAgACAAgI1xaSKAAxAgAAAA==.Fulburst:BAAALAADCgEIAgAAAA==.Furii:BAAALAAECgcIDQAAAA==.',['Fí']='Fíré:BAAALAADCgcICAAAAA==.',Ga='Gadren:BAAALAAECgYIBwAAAA==.Gandélf:BAAALAAECgEIAQAAAA==.',Gh='Ghostrabbit:BAAALAAECgYIBgAAAA==.',Gi='Gintama:BAAALAAECgMIBAAAAA==.',Gn='Gnomie:BAAALAAFFAUIAgAAAA==.Gnomielash:BAAALAAECggIEgABLAAFFAUIAgABAAAAAA==.Gnomiemagus:BAAALAADCgcIBwABLAAFFAUIAgABAAAAAA==.Gnomiepal:BAAALAAFFAMIAwABLAAFFAUIAgABAAAAAA==.Gnomietwo:BAAALAAFFAMIAwABLAAFFAUIAgABAAAAAA==.',Go='Gobstoppers:BAAALAAECgcIBwAAAA==.Gordían:BAAALAAECgYICwAAAA==.',Gr='Gramm:BAAALAAECgMIBwAAAA==.Grimblade:BAAALAAECgYIBgAAAA==.Gristonius:BAAALAAECgcIDQAAAA==.',Gu='Guinan:BAAALAAECgUIDgAAAA==.Gumma:BAAALAADCgYIAgAAAA==.Guyy:BAACLAAFFIENAAMFAAQIyR4+AgCQAQAFAAQIGxw+AgCQAQAQAAEI9B8jAwBhAAAsAAQKgSAAAwUACAgaJdkDAE4DAAUACAgWJNkDAE4DABAABQiJJJMGABUCAAAA.',Ha='Haeger:BAAALAADCggIEAAAAA==.Haku:BAAALAAECgUIBAAAAA==.Hamsterxd:BAAALAADCgEIAQAAAA==.',He='Helline:BAAALAADCggIDAAAAA==.',Ho='Holyhéll:BAAALAAECgMIBAAAAA==.Hoolyz:BAAALAAECgIIAgAAAA==.Hotwings:BAAALAADCggIDQABLAAECggIFwARAAoaAA==.Houdoe:BAAALAADCggICAAAAA==.',Hu='Hunttrix:BAAALAAECgEIAQAAAA==.',Hy='Hydrate:BAAALAADCgcIBgAAAA==.',Ic='Icarus:BAAALAAECgcIBwAAAA==.',Ik='Ikachu:BAABLAAECoEWAAIEAAcI6x10CQA9AgAEAAcI6x10CQA9AgAAAA==.',Im='Imtheflash:BAAALAAECgMIBAAAAA==.',In='Indigo:BAABLAAECoEVAAIIAAgIERyMCgBaAgAIAAgIERyMCgBaAgAAAA==.Indris:BAAALAAECgcIEAAAAA==.Insaneshamz:BAAALAAECgYIDAAAAA==.',Ir='Ironsight:BAABLAAECoEWAAISAAcISxxqGgBWAgASAAcISxxqGgBWAgAAAA==.',Is='Isleen:BAACLAAFFIEGAAIRAAQIPg8HAgA+AQARAAQIPg8HAgA+AQAsAAQKgRgAAhEACAgJFjMgANUBABEACAgJFjMgANUBAAAA.',Ja='Jack:BAABLAAECoEYAAMTAAcIwxmOCQDzAQATAAcI4xWOCQDzAQAUAAcIVxVqBQDuAQAAAA==.Jayee:BAACLAAFFIEKAAIVAAQI6hvyAwB5AQAVAAQI6hvyAwB5AQAsAAQKgRsABBUACAjTIawGACMDABUACAguIawGACMDABYABQiGJSAXANgBABcAAggyIDocALwAAAAA.',Jo='Joemomma:BAAALAAECgcIDQABLAAECgcIFgADAGIfAA==.Joheltro:BAAALAADCggIFwAAAA==.',Ju='Jumpy:BAAALAAECgYIBgAAAA==.',Jw='Jweddy:BAABLAAECoEUAAIYAAcIlR6FEgBYAgAYAAcIlR6FEgBYAgAAAA==.',Ka='Kakirage:BAAALAAECgUIBgAAAA==.Kaktperekdk:BAAALAADCgUIBQAAAA==.Kalrell:BAAALAAECgIIAwABLAAECgcIEgABAAAAAA==.Kann:BAABLAAECoEgAAIZAAgIFh5kFADAAgAZAAgIFh5kFADAAgAAAA==.Kannada:BAAALAAECgcIDwABLAAECggIIAAZABYeAA==.Karatiewater:BAAALAAECgYICQABLAAECgcIFgASAEscAA==.Karlakh:BAAALAADCgUICQAAAA==.Kasida:BAAALAAECgYIDAAAAA==.Katsùki:BAAALAAECgYIDAAAAA==.Katsúki:BAAALAAECgIIAQABLAAECgYIDAABAAAAAA==.',Ke='Keiron:BAACLAAFFIENAAICAAQIniFdAwCfAQACAAQIniFdAwCfAQAsAAQKgSAAAgIACAgxJFEEAEkDAAIACAgxJFEEAEkDAAAA.Kelhben:BAAALAADCggIDwAAAA==.Kelrel:BAAALAADCgEIAQABLAAECgcIEgABAAAAAA==.Kenoo:BAAALAADCggIEAAAAA==.',Ki='Kijo:BAAALAAECgYIBgAAAA==.',Kn='Knit:BAAALAAECgMIBwAAAA==.',Ko='Kotlin:BAABLAAECoEXAAIRAAgIChqCEQBMAgARAAgIChqCEQBMAgAAAA==.Kovú:BAAALAAECgMIAwAAAA==.',Kr='Kreppy:BAABLAAECoEWAAIRAAcIbhxkFAAyAgARAAcIbhxkFAAyAgAAAA==.Krieger:BAAALAAECggIBQABLAAECggICAABAAAAAA==.Krimmyr:BAAALAAECgcIDwAAAA==.Krimotar:BAAALAADCgcIBwAAAA==.Krippi:BAAALAAECgcIDwAAAA==.Krippy:BAAALAADCgcIBwABLAAECgcIDwABAAAAAA==.',Ku='Kullervo:BAAALAAECgQICwAAAA==.Kux:BAACLAAFFIENAAMaAAQIJhrUAQB7AQAaAAQIJhrUAQB7AQAJAAEIVQluEgBVAAAsAAQKgSAAAhoACAhcIFMHAO8CABoACAhcIFMHAO8CAAAA.',La='Laerin:BAAALAADCgcIBwABLAAECgQIBAABAAAAAA==.Lakshmi:BAAALAAECgYICAAAAA==.Larenta:BAAALAADCggICAAAAA==.Lavinna:BAAALAADCgcIBwAAAA==.',Le='Leaba:BAAALAAECgYIDgAAAA==.Leblanc:BAAALAADCggICAAAAA==.Lexania:BAAALAAECgIIAgAAAA==.',Li='Lightbrand:BAAALAAECggIEQAAAA==.Lightisun:BAAALAAECgYIEQAAAA==.Lightmane:BAABLAAECoEZAAIZAAgIIR6RFwCmAgAZAAgIIR6RFwCmAgAAAA==.Lilacree:BAAALAADCgcIBwAAAA==.',Lo='Lostglaive:BAAALAAECggIDgAAAA==.',Lu='Lucarion:BAAALAAECgYIBgAAAA==.Luftem:BAAALAAECgMIAwAAAA==.',Ma='Madbones:BAAALAAECgYIDAAAAA==.Magexd:BAAALAAECgYICwAAAA==.Magrin:BAAALAAECgYIDgAAAA==.Maldom:BAAALAAECgYICQAAAA==.Manglorious:BAABLAAECoEXAAIbAAcIMh/RDQB9AgAbAAcIMh/RDQB9AgAAAA==.Marissa:BAAALAADCggIDwAAAA==.Mará:BAABLAAECoEXAAQPAAgIlBEwDQDqAQAPAAgILQ8wDQDqAQAcAAcIjQ1tCgBbAQARAAYIOBUiNABZAQAAAA==.Masterchef:BAABLAAECoElAAIdAAgITyK4CADlAgAdAAgITyK4CADlAgAAAA==.Maxdisc:BAAALAAECggIBgAAAA==.Maxdps:BAAALAAECggICAAAAA==.Maxi:BAAALAAECggICAAAAA==.',Mi='Mihdo:BAAALAAECgQIBwAAAA==.Mindkiller:BAAALAAECgEIAQAAAA==.Mithos:BAAALAADCggICAAAAA==.',Mo='Molka:BAAALAADCggICAAAAA==.Monte:BAAALAAECgcIDwAAAA==.Morrígu:BAAALAADCgIIAgAAAA==.',Mu='Muffadin:BAAALAAECgEIAQAAAA==.Murtagh:BAAALAADCggIDwAAAA==.',['Mí']='Míshka:BAAALAAECgcIEAAAAA==.',Na='Nadeko:BAAALAADCgMIBQAAAA==.Nairod:BAAALAADCgcIBwAAAA==.Naiya:BAABLAAECoEWAAIeAAcISiRBCADOAgAeAAcISiRBCADOAgAAAA==.Nasrudan:BAAALAAECggICAAAAA==.Navissa:BAAALAADCgcIBwAAAA==.',Ne='Nealson:BAABLAAECoEVAAIOAAcI2xj2MQAPAgAOAAcI2xj2MQAPAgAAAA==.Necri:BAABLAAECoEXAAIfAAgICCIqCgAaAwAfAAgICCIqCgAaAwAAAA==.Nemophila:BAAALAAECgYIBgABLAAECgcIEAABAAAAAA==.',Ni='Nikkans:BAACLAAFFIEJAAIZAAQIMByfAQB1AQAZAAQIMByfAQB1AQAsAAQKgR8AAhkACAg9Jo0BAIADABkACAg9Jo0BAIADAAAA.Nina:BAAALAAECgIIAQAAAA==.Ninnoc:BAAALAAECgQIBAAAAA==.',No='Nobume:BAAALAADCgQIBAAAAA==.Nogearnofear:BAAALAADCgYIBwAAAA==.Norbi:BAAALAAECgcIEAAAAA==.',Nu='Nuit:BAAALAADCggIBgAAAA==.',['Nö']='Nöx:BAAALAAECgYICAAAAA==.',Op='Opalus:BAAALAADCgcICgAAAA==.',Or='Orothaine:BAAALAADCggICgAAAA==.',Os='Osiria:BAAALAAECgcIEAAAAA==.Oswynn:BAAALAAECgYIEAAAAA==.Osyluth:BAAALAADCgQIBAAAAA==.',Ou='Ouchie:BAABLAAECoEWAAIEAAgITByGBwBzAgAEAAgITByGBwBzAgAAAA==.',Pe='Peepars:BAAALAAECgQICAABLAAECggIFgAPAMIjAA==.Peepers:BAABLAAECoEWAAIPAAgIwiNTAQBFAwAPAAgIwiNTAQBFAwAAAA==.Person:BAAALAAECgIIAgAAAA==.',Ph='Phoeñix:BAAALAAECgUIAwAAAA==.',Po='Pocketpicka:BAAALAADCgYIBwAAAA==.',Pr='Prokletija:BAABLAAECoEUAAIVAAcIPB5QFwB2AgAVAAcIPB5QFwB2AgAAAA==.',Py='Pyromaniac:BAABLAAECoEfAAIHAAgIHx0mAQDSAgAHAAgIHx0mAQDSAgABLAAFFAQIDQAJAPwfAA==.',Qu='Quellandra:BAAALAADCgMIAwAAAA==.Quilith:BAAALAADCggICAAAAA==.',Ra='Rafael:BAAALAAECgEIAQAAAA==.Raitou:BAAALAAECgQICQABLAAECgcIDwABAAAAAA==.Raphius:BAAALAADCggICAAAAA==.Rastafman:BAAALAADCggIDgAAAA==.Ratut:BAABLAAECoEYAAIMAAgIBR0BCwCoAgAMAAgIBR0BCwCoAgAAAA==.',Re='Reikärauta:BAAALAAECgUIDgAAAA==.Reliance:BAABLAAECoEYAAMJAAgIiBgiIAD1AQAJAAcIUBciIAD1AQAaAAUIoQjsUQDsAAAAAA==.Renminnda:BAABLAAECoEcAAIJAAgI7xxCDADHAgAJAAgI7xxCDADHAgAAAA==.Retier:BAACLAAFFIEFAAITAAQI/hnjAABrAQATAAQI/hnjAABrAQAsAAQKgSAAAxMACAhyJKUAAFwDABMACAhyJKUAAFwDABsAAQjABwxRADkAAAAA.Revybrew:BAACLAAFFIEGAAMgAAIIECMKBQDNAAAgAAIIECMKBQDNAAAEAAEI4hQFCwA/AAAsAAQKgRQAAiAABwghJtgDAOsCACAABwghJtgDAOsCAAAA.Revyti:BAAALAAECgMIAwAAAA==.',Rh='Rhydan:BAAALAADCggICAAAAA==.',Ri='Riftr:BAAALAAECggICAAAAA==.Rigonda:BAACLAAFFIENAAIfAAQIIiM6AgCxAQAfAAQIIiM6AgCxAQAsAAQKgRsAAh8ACAjoJe8BAHcDAB8ACAjoJe8BAHcDAAAA.',Rk='Rkyuub:BAAALAADCgcIBwAAAA==.',Ro='Rodati:BAABLAAECoEUAAIhAAcIyiNXDQDQAgAhAAcIyiNXDQDQAgAAAA==.Rosebútt:BAAALAADCgcIEwABLAAECgcIEAABAAAAAA==.',Ru='Ru:BAAALAAECgMIAwAAAA==.Rulan:BAAALAAECgcIBwAAAA==.Rustybubbles:BAAALAAECgcIEQAAAA==.',Sa='Sael:BAAALAAECgMIDAAAAA==.Saephynea:BAAALAAECgMIBQAAAA==.Sahtiämpäri:BAAALAADCgYICgAAAA==.Saka:BAAALAAECgcIEQAAAA==.Sappyboi:BAAALAAECggIBgABLAAFFAQIDQAFAMkeAA==.Sarethas:BAAALAAECgEIAQAAAA==.',Sc='Scala:BAAALAADCgEIAQAAAA==.Scrin:BAAALAAECgcIEAAAAA==.',Se='Secondnoob:BAAALAADCgYIBgAAAA==.Seldarine:BAAALAADCggICAAAAA==.Seyrin:BAAALAAECgQIBAAAAA==.',Sh='Shrinkeysham:BAACLAAFFIEGAAIhAAQIhRcTAwBdAQAhAAQIhRcTAwBdAQAsAAQKgR0AAiEACAgNJL4GACgDACEACAgNJL4GACgDAAAA.',Si='Sipwel:BAAALAAECgEIAQAAAA==.',Sk='Skadi:BAAALAAECgcIEAAAAA==.Skumplast:BAAALAADCgMIAwAAAA==.Skærverg:BAAALAADCggIDgABLAAECgYIBgABAAAAAA==.',Sl='Slamse:BAAALAADCggICAAAAA==.',Sm='Smirkymonk:BAAALAADCgcIBwAAAA==.',Sn='Sniffa:BAAALAAECgYIBgABLAAFFAUIAgABAAAAAA==.',So='Solastro:BAAALAAFFAIIAgAAAA==.',Sq='Squashee:BAAALAADCggIEAAAAA==.Squashiclysm:BAAALAAECgcIEQAAAA==.',St='Stoorm:BAAALAAECgYIBwAAAA==.Stormvalor:BAAALAAECgYIDwAAAA==.',Su='Supercell:BAAALAAECgcIEAAAAA==.',Ta='Tauler:BAAALAAECgYIDQAAAA==.',Te='Tedrass:BAAALAAECgYIBgAAAA==.Terendrýn:BAAALAAECgYIEAAAAA==.',Th='Thalario:BAAALAAECgIIAgAAAA==.Thalaron:BAAALAAECgYICQAAAA==.',Ti='Tibbor:BAACLAAFFIEGAAIFAAMIpxqOBQATAQAFAAMIpxqOBQATAQAsAAQKgR0AAgUACAi7JEEIABQDAAUACAi7JEEIABQDAAAA.Tiktik:BAAALAAECgcIEwAAAA==.Tinre:BAABLAAECoEbAAQaAAgIOCH6BgD0AgAaAAgIGCH6BgD0AgAJAAQIHBRdRQDzAAAKAAEI+CMSGwBpAAAAAA==.',To='Today:BAAALAAECgIIAgAAAA==.Topdkey:BAAALAAECggIBAABLAAFFAQIDQAFAMkeAA==.Totemjävel:BAAALAADCgEIAQAAAA==.Totemkin:BAAALAAECgYICAAAAA==.',Tr='Tristantate:BAAALAADCgEIAQAAAA==.Truesittkens:BAAALAADCgMIAwAAAA==.',Ts='Tsukuyo:BAAALAADCgcIDQAAAA==.',Ty='Tyraea:BAAALAADCggICgABLAAECgcIEAABAAAAAA==.',Ug='Uglygrill:BAAALAADCgcIDQAAAA==.',Ut='Utsa:BAAALAADCggIEwAAAA==.',Va='Vallrell:BAAALAAECgYICwABLAAECgcIEgABAAAAAA==.Valrell:BAAALAAECgcIEgAAAA==.Vanillacroco:BAAALAADCggICAAAAA==.',Ve='Veloskm:BAAALAAECgMIAwAAAA==.Ventriss:BAAALAADCgUIBQAAAA==.Verdell:BAAALAADCgUIBQAAAA==.Vestigium:BAACLAAFFIENAAIiAAQIKSLVAACSAQAiAAQIKSLVAACSAQAsAAQKgSAAAiIACAiLJaoAAHgDACIACAiLJaoAAHgDAAAA.',Vi='Vileplume:BAAALAADCggICAAAAA==.',Vo='Votka:BAAALAADCgEIAQAAAA==.Voïd:BAAALAADCggICAAAAA==.',Wa='Wac:BAAALAAECgMIAwABLAAFFAQIBgAJAGkaAA==.Wacmage:BAAALAAECgcICwABLAAFFAQIBgAJAGkaAA==.Wanhéda:BAAALAAECgMIAgAAAA==.',Wh='Wheelchair:BAAALAAECgcIDwAAAA==.',Wi='Willjum:BAAALAADCgQIBAAAAA==.Wit:BAAALAAECgQIBwAAAA==.',Wo='Wombats:BAACLAAFFIELAAMSAAQIhiD/AAB/AQASAAQIhiD/AAB/AQAdAAIIHhn8CgCgAAAsAAQKgSAAAxIACAhsJJUDAEwDABIACAhsJJUDAEwDAB0ACAj+H2EHAPgCAAAA.Wonkie:BAAALAAECgIIAgAAAA==.Wonton:BAAALAAECgMIBAAAAA==.',Wr='Wren:BAAALAAECgYIEQAAAA==.',['Wà']='Wàc:BAAALAADCgYIBgABLAAFFAQIBgAJAGkaAA==.',['Wá']='Wác:BAACLAAFFIEGAAIJAAQIaRqRAgBfAQAJAAQIaRqRAgBfAQAsAAQKgSAAAwkACAjxJRMCAGMDAAkACAjxJRMCAGMDABoAAgg/C8lmAHIAAAAA.',Xo='Xo:BAAALAAECgcIEgAAAA==.Xor:BAACLAAFFIEFAAMWAAMIoR2HBAC3AAAWAAIIWB6HBAC3AAAVAAEINBzsGQBhAAAsAAQKgSAABBYACAgkJk4FALQCABYABgh4Jk4FALQCABUAAwhTJElOADkBABcAAQikI60oAF8AAAAA.',Ya='Yadé:BAAALAAFFAIIAgAAAA==.Yathrien:BAAALAADCgYIBgABLAAECggIFwARAAoaAA==.Yawnie:BAAALAADCggIEAABLAAECgcIEAABAAAAAA==.',Ye='Yevar:BAAALAADCggIDgAAAA==.',Yo='Yokeshi:BAAALAADCgEIAQAAAA==.',Za='Zain:BAAALAADCgcIBwAAAA==.Zam:BAAALAAECgYICwAAAA==.',Ze='Zetsupt:BAAALAAECgYIBgAAAA==.',Zo='Zoogi:BAAALAADCggIGAAAAA==.Zorokao:BAAALAADCggIGAAAAA==.',Zu='Zubye:BAABLAAECoEaAAICAAgI0RtuIABkAgACAAgI0RtuIABkAgAAAA==.',['Öt']='Öttiäinen:BAAALAAECgUIDgAAAA==.',['Üb']='Übeåvieel:BAAALAADCggIFAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end