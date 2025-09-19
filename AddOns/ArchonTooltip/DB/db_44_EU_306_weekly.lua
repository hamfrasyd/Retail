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
 local lookup = {'Unknown-Unknown','Shaman-Elemental','Evoker-Preservation','Evoker-Augmentation','Evoker-Devastation','Monk-Brewmaster','Monk-Windwalker','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Frost','DeathKnight-Unholy','Warrior-Fury','Paladin-Retribution','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Mage-Arcane','Druid-Balance','Druid-Restoration','Paladin-Protection','Priest-Holy','Priest-Discipline','Monk-Mistweaver','Warrior-Protection','Druid-Feral','Rogue-Assassination','Druid-Guardian','Warrior-Arms','Warlock-Demonology','Priest-Shadow',}; local provider = {region='EU',realm='Kilrogg',name='EU',type='weekly',zone=44,date='2025-09-06',data={Aa='Aapjé:BAAALAADCgIIAgAAAA==.',Ae='Aerowynn:BAAALAADCggICAABLAAECgUICgABAAAAAA==.Aesha:BAAALAADCggIGwAAAA==.Aestas:BAABLAAECoEdAAICAAgI3yH3BgAkAwACAAgI3yH3BgAkAwAAAA==.',Ag='Agamur:BAAALAAECgYICQAAAA==.',Ak='Akio:BAAALAADCggIBAAAAA==.Akxu:BAAALAADCggIGwAAAA==.',Al='Alchydragon:BAACLAAFFIEGAAIDAAMIOyPuAQA4AQADAAMIOyPuAQA4AQAsAAQKgRwABAMACAiUH0wEAKICAAMACAiUH0wEAKICAAQABghSHhEDACICAAUABgh8Gx0aANEBAAAA.Alderhey:BAAALAADCggIDwAAAA==.Alexandría:BAAALAADCggIEAAAAA==.Algysmiter:BAAALAAECgMIAwAAAA==.Alisia:BAAALAAECgcIDQAAAA==.Alt:BAAALAAECgcICgAAAA==.',Am='Amanecer:BAAALAADCggIEAAAAA==.Amberiron:BAAALAADCgYIBgAAAA==.',An='Angelsspy:BAAALAAECgYIDQAAAA==.Angrymanny:BAAALAAFFAIIAgAAAA==.Anunnak:BAAALAAECgcIBwAAAA==.',Ar='Ardarathyn:BAAALAADCgIIAgAAAA==.Arthuría:BAAALAAECggICQAAAA==.Artog:BAAALAAECgYICwAAAA==.Arzira:BAAALAAECgYIDgAAAA==.',As='Astynaxx:BAAALAADCggIEAAAAA==.',Aw='Awwawawaa:BAAALAADCggICgAAAA==.',Ba='Baas:BAAALAAECgYIDAAAAA==.Baeldh:BAAALAAECgUIBgAAAA==.Barbapapa:BAAALAADCggIFgABLAAECggIEwABAAAAAA==.Bargush:BAAALAADCggIGwAAAA==.',Be='Bearrelroll:BAABLAAECoEUAAMGAAYI4RqIDgDQAQAGAAYI4RqIDgDQAQAHAAEISxsvOQBFAAAAAA==.Beduinne:BAAALAAECgQIBAAAAA==.Beelzeboss:BAAALAADCgMIAwAAAA==.Beeple:BAAALAADCgcIDgAAAA==.Beerbear:BAAALAADCgEIAQABLAAECggIEwABAAAAAA==.Belenus:BAAALAADCggICAAAAA==.Beltane:BAAALAAECggICAAAAA==.Bennythedog:BAAALAAECgEIAQAAAA==.',Bh='Bholadin:BAAALAADCgcIBwAAAA==.',Bi='Bigslappah:BAAALAAECggIDgAAAA==.Biscuit:BAAALAADCgQIBAAAAA==.',Bl='Blasphemysin:BAAALAADCggICAAAAA==.Blindnotdeaf:BAAALAAECgEIAQAAAA==.Bloodypluto:BAAALAAFFAIIBAABLAAFFAIIBgAIAG4jAA==.Bluedevils:BAAALAADCgEIAQAAAA==.',Bo='Boijlemus:BAAALAAECgEIAQABLAAFFAMIBgAJAEMMAA==.',Br='Bramm:BAAALAADCggIGgAAAA==.',Bu='Bumbi:BAAALAAECgUIBgAAAA==.Burningtusk:BAAALAAECgYICQAAAA==.Burrata:BAAALAADCgcIBwABLAAECgUIDQABAAAAAA==.',['Bä']='Bästipräst:BAAALAADCgUIBQAAAA==.',['Bé']='Béren:BAAALAADCggIDwAAAA==.',['Bú']='Búnny:BAAALAADCggIFgAAAA==.',Ca='Calidore:BAAALAADCggIDAAAAA==.Canofundeath:BAABLAAECoEhAAMKAAgIPCUhBwAuAwAKAAgI0iQhBwAuAwALAAUIFiFvEgDTAQAAAA==.Carnius:BAABLAAECoEaAAIMAAgIByAXDADlAgAMAAgIByAXDADlAgAAAA==.Casty:BAAALAAECgEIAQAAAA==.Cataloko:BAAALAAECgUICAAAAA==.Catmaddead:BAAALAAECgMIBQAAAA==.Catzhin:BAAALAAECgIIAgAAAA==.',Ce='Cervisia:BAAALAADCgcIBwAAAA==.',Ch='Chaosdemon:BAAALAADCgYIBgAAAA==.Chinpettum:BAABLAAECoEeAAINAAgI3CRCBwA7AwANAAgI3CRCBwA7AwAAAA==.Chipps:BAAALAAECgIIAgAAAA==.Chockbolt:BAAALAADCgcIDgAAAA==.Chrysophylax:BAAALAADCgYIBgAAAA==.Chuckleflux:BAAALAADCgYIBgAAAA==.',Ci='Ciganka:BAAALAADCggICAAAAA==.',Co='Colin:BAAALAAECgYIEgAAAA==.',Cr='Cruul:BAAALAAECgMIBgAAAA==.Cryptum:BAAALAAECgYIDQAAAA==.',Da='Daenarr:BAAALAAECgYIDQAAAA==.Dak:BAABLAAECoEVAAIHAAcI9hfJEAAFAgAHAAcI9hfJEAAFAgAAAA==.Darekamadore:BAAALAAECgcIEgAAAA==.Darkangle:BAAALAADCggIEAAAAA==.Darkirón:BAAALAADCggIGwAAAA==.Darkro:BAAALAAECgMIBAAAAA==.Dazba:BAAALAAECgYIDgAAAA==.',De='Deathshotee:BAAALAAECgYIEQAAAA==.Deemose:BAAALAADCggIEgAAAA==.Deleted:BAAALAADCgEIAQAAAA==.Deliriouscat:BAAALAAECgYIBwAAAA==.Demonikel:BAAALAAECgUIBQAAAA==.Demonià:BAABLAAECoEUAAIOAAYIxBxzNQDvAQAOAAYIxBxzNQDvAQAAAA==.Desmo:BAAALAADCgQIBgAAAA==.Devs:BAAALAAECgMIBAAAAA==.',Di='Diaboloz:BAAALAAECgYIDAAAAA==.Dicolfenac:BAACLAAFFIEHAAINAAMI+BwcAwAmAQANAAMI+BwcAwAmAQAsAAQKgR8AAg0ACAjqJOADAGADAA0ACAjqJOADAGADAAAA.Digitalmage:BAAALAAECggICAAAAA==.Digitalsiner:BAAALAAECggICAAAAA==.',Do='Dogshi:BAAALAAECgYIEQAAAA==.Doomscale:BAAALAADCgUIBQAAAA==.',Dr='Dracken:BAAALAAECgYIEwAAAA==.Dribblee:BAAALAAECgQIBAAAAA==.Drinkers:BAAALAADCggICAAAAA==.Dritte:BAAALAADCggICAAAAA==.Drkzippy:BAAALAAECgYIDQAAAA==.Drutheid:BAAALAADCgUIBQAAAA==.',Du='Duffins:BAAALAADCggICAAAAA==.Dunedain:BAAALAAECggIDgAAAA==.Durup:BAAALAAECgMIBgABLAAECgcIEwABAAAAAA==.Duryp:BAAALAADCggIEgABLAAECgcIEwABAAAAAA==.',Dw='Dwen:BAAALAADCgcIBwAAAA==.',Dy='Dylla:BAAALAAECggICAAAAA==.',Ec='Eclipsis:BAAALAADCggICAAAAA==.',Ed='Edgarous:BAAALAADCggICAAAAA==.',El='Elaryn:BAAALAADCgYIBgAAAA==.Elicka:BAAALAADCggICAAAAA==.Elithandrea:BAEALAADCggICAABLAAECgUIDQABAAAAAA==.Ellienne:BAAALAADCgcIBwAAAA==.Elylaya:BAAALAADCggICAAAAA==.',Em='Emeraldz:BAAALAADCggICwAAAA==.Emlaiah:BAAALAAECgUIBgAAAA==.Emriana:BAAALAAECgYIBgAAAA==.',Et='Eternaldraco:BAAALAAECgUICgAAAA==.',Ev='Evince:BAAALAAECgYIBwAAAA==.',Fa='Faction:BAAALAADCgIIAgAAAA==.Faldri:BAAALAAECgcIDQAAAA==.Farferifromp:BAAALAADCgIIAgAAAA==.Farlie:BAAALAADCggICAAAAA==.Faromier:BAAALAAECgMIAwAAAA==.Fartconjurer:BAAALAADCgcIBwABLAAECgUIDAABAAAAAA==.',Fe='Felam:BAAALAAECgcICQAAAA==.Feldiir:BAAALAAECgYICgAAAA==.',Fi='Fizzlock:BAAALAAECgYICwAAAA==.',Fj='Fjærlokt:BAACLAAFFIEGAAMJAAMIQwyEBgDPAAAJAAMIQwyEBgDPAAAPAAEIsgIsGAArAAAsAAQKgRgAAwkACAg8HNQXAGsCAAkACAhXGdQXAGsCAA8ABggJGsYsAIcBAAAA.',Fl='Flameofpast:BAAALAAECgYIDwAAAA==.Flar:BAAALAADCggICAAAAA==.Flaxxiz:BAACLAAFFIEGAAINAAIIYhsjDQCtAAANAAIIYhsjDQCtAAAsAAQKgRkAAg0ACAi7HTAiAFoCAA0ACAi7HTAiAFoCAAAA.',Fr='Frazyl:BAAALAADCgcICQAAAA==.Freezepop:BAAALAAECgYIBwAAAA==.Frozenpea:BAABLAAECoEPAAMQAAYIgw61KQBRAQAQAAYIPg61KQBRAQARAAUIEAveaQAMAQAAAA==.',Fu='Fufuro:BAAALAAECgYIBgABLAAECgUICgABAAAAAA==.Furri:BAAALAADCgYIBgAAAA==.',Ga='Gabbyjay:BAAALAADCgQIBAAAAA==.Gaiaa:BAAALAADCggICAAAAA==.Gatamephydi:BAAALAADCgYICAAAAA==.Gazuz:BAAALAADCggIHwAAAA==.',Ge='Genormica:BAAALAAECgIIBAAAAA==.Georgino:BAABLAAECoEZAAIRAAgIqR8UEgDPAgARAAgIqR8UEgDPAgAAAA==.',Gi='Gilbért:BAABLAAECoETAAIRAAYIFxm/QAC6AQARAAYIFxm/QAC6AQABLAAECggICQABAAAAAA==.',Gl='Glendracthyr:BAAALAADCgQIBAAAAA==.Glenlock:BAAALAADCggIFAAAAA==.Glissov:BAAALAAECggICgAAAA==.Glycera:BAAALAAECgYICAAAAA==.',Go='Goedemorgen:BAAALAAECgYIDAAAAA==.Gonzo:BAAALAADCgIIAgAAAA==.',Gr='Grevän:BAAALAAECgMIAwAAAA==.Grimlaar:BAAALAAECggIAQAAAA==.Grombrindal:BAAALAADCggICAAAAA==.Grunit:BAAALAAECgYIDQAAAA==.',Gu='Guffman:BAAALAAECgUIDAAAAA==.Gumielock:BAAALAAECgEIAQAAAA==.',Gz='Gzus:BAAALAAECgcIDAAAAA==.',['Gì']='Gìblet:BAABLAAECoEUAAMSAAYIvhViKACbAQASAAYIvhViKACbAQATAAEIrw9PeAAuAAAAAA==.',['Gí']='Gílan:BAAALAAECgQIBAABLAAECggICQABAAAAAA==.',Ha='Haborym:BAAALAADCggICAABLAAECgUIDwABAAAAAA==.Hardwork:BAAALAAECgYICwABLAAECgYIEAABAAAAAA==.Hauktuah:BAAALAADCggIEAAAAA==.Hayfire:BAACLAAFFIEIAAIUAAMImCbCAABcAQAUAAMImCbCAABcAQAsAAQKgR8AAhQACAjuJggAAKwDABQACAjuJggAAKwDAAAA.Hazaio:BAAALAAECgYIDAAAAA==.',He='Heikè:BAAALAADCgMIBQAAAA==.Hellspeaker:BAAALAAECgcIBwAAAA==.Herbadurb:BAAALAADCgIIAgAAAA==.',Ho='Holiestgoat:BAAALAAECgYICwAAAA==.Holynoodle:BAAALAAECgYIEgAAAA==.Holynoodles:BAAALAADCggIAQAAAA==.Honeyzapper:BAAALAADCgcICAAAAA==.Hopsaké:BAAALAAECgQIBQAAAA==.',Hu='Huanglong:BAAALAADCgcIBgAAAA==.Huna:BAAALAAECgMIBAAAAA==.Hunnah:BAAALAADCggICAAAAA==.',Hy='Hyoro:BAAALAAECgMIAwAAAA==.',Ic='Icezje:BAAALAADCgEIAQAAAA==.',Ih='Ihealyoustfu:BAAALAADCggICQAAAA==.',Il='Ilmr:BAAALAADCggIEgAAAA==.Ilonius:BAAALAAECgQICgAAAA==.',Im='Impassive:BAAALAADCgIIAgAAAA==.',In='Inkki:BAAALAAECggIEwAAAA==.',Iq='Iqrugoc:BAACLAAFFIEHAAMVAAMIKwymBwDvAAAVAAMI8AmmBwDvAAAWAAIIfw3+AACZAAAsAAQKgRcAAxYACAgBGo8DAEACABUACAjSGDkSAG8CABYACAjeFY8DAEACAAAA.',Is='Isekaied:BAAALAADCggICAAAAA==.',It='Itouchbutts:BAAALAAECgYIEwAAAA==.',Ja='Janisa:BAAALAADCgYIBgAAAA==.Jaxom:BAAALAAECggICAAAAA==.Jaybear:BAAALAAECgEIAQAAAA==.',Ji='Jinori:BAACLAAFFIEIAAIXAAMIiQwvBADsAAAXAAMIiQwvBADsAAAsAAQKgR8AAhcACAj9FjILADcCABcACAj9FjILADcCAAAA.',Ka='Kadae:BAAALAAECgYIDwAAAA==.Kadatonic:BAAALAAECgYIDQAAAA==.Kaelira:BAAALAADCgcIBgAAAA==.Kairó:BAAALAAECgIIAgAAAA==.Kalaris:BAAALAAECgMIBgAAAA==.Kat:BAAALAAECgYICgAAAA==.Katzen:BAAALAAECgMIAwAAAA==.',Ke='Keatonn:BAABLAAECoEVAAIKAAYIkxWqYgBkAQAKAAYIkxWqYgBkAQAAAA==.Kelpy:BAAALAAECgEIAQAAAA==.Ketaminee:BAAALAAECgYIDAAAAA==.',Ki='Kiingslayeer:BAAALAADCggICAAAAA==.Killthemoon:BAAALAADCggIDgABLAAFFAIIBgAIAG4jAA==.Kittslayer:BAAALAADCgIIAgAAAA==.',Kn='Knugwup:BAAALAAECgYICgAAAA==.',Ko='Kochanie:BAAALAAECgYIEAAAAA==.Korphite:BAAALAADCgMIAwAAAA==.',Ku='Kungfupanda:BAAALAADCggICAABLAAECgMIBQABAAAAAA==.Kurecutie:BAAALAAFFAIIAgAAAA==.Kurrewix:BAAALAADCgEIAQAAAA==.',La='Laivinë:BAAALAADCgcIBwAAAA==.Lazer:BAAALAADCggICAAAAA==.Lazoroth:BAEALAAECgcIEAAAAA==.',Le='Leasha:BAAALAADCggIFQAAAA==.Lefa:BAAALAAECgYIDQAAAA==.Leisheng:BAAALAADCggIGwAAAA==.Lemonhazé:BAAALAAECgYIDgABLAAECgYIEAABAAAAAA==.Leopardhajen:BAAALAADCggICAAAAA==.Leorian:BAAALAADCgYIBgAAAA==.Leyani:BAAALAADCggIEAAAAA==.',Li='Lightknight:BAAALAAECggIDAAAAA==.Lillhuntz:BAAALAADCggIFgAAAA==.',Lo='Lockielok:BAAALAADCggICAAAAA==.Logari:BAAALAADCggIDgAAAA==.',Lu='Luciian:BAAALAADCgcIDQABLAAECgQIBgABAAAAAA==.Lumineira:BAAALAAECgcICwAAAA==.',['Lï']='Lï:BAAALAAECgcIEwAAAA==.',['Lú']='Lúisa:BAAALAADCgUIAwAAAA==.',Ma='Maaza:BAAALAAECgYIBgABLAAFFAIIBgANAGIbAA==.Magali:BAAALAADCggIGwAAAA==.Magenex:BAAALAAECgUIBgAAAA==.Magnox:BAABLAAECoEdAAMQAAcIiSLACgB3AgAQAAcI/iHACgB3AgARAAcIRxqMMwD3AQABLAAECggICAABAAAAAA==.Magtoral:BAAALAAECgIIAgAAAA==.Mahboi:BAAALAADCgYIBgAAAA==.Maime:BAAALAADCgYIBgAAAA==.Majic:BAABLAAECoEVAAIQAAgICx9rBQDpAgAQAAgICx9rBQDpAgAAAA==.Malftruistic:BAAALAADCgUIBQABLAADCggICAABAAAAAA==.Manapause:BAAALAADCgEIAQAAAA==.Manight:BAAALAAECgMIBAAAAA==.Mardoosh:BAAALAAECgYIDAAAAA==.Maryboppins:BAAALAADCggICQAAAA==.Maxiepriest:BAAALAAECgcIEAAAAA==.Maxierogue:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Maxillectomy:BAAALAADCggIEQAAAA==.',Me='Mechanix:BAACLAAFFIEFAAIMAAMIuREYBwD6AAAMAAMIuREYBwD6AAAsAAQKgRYAAgwACAi5IUQRAKcCAAwACAi5IUQRAKcCAAAA.Meena:BAAALAAECgYICgAAAA==.Megadeeps:BAAALAADCgQIBAAAAA==.Megafuming:BAAALAADCgIIAwAAAA==.Mercurie:BAAALAAECgYIDwAAAA==.Metalbenji:BAAALAAECgUICwAAAA==.Methone:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',Mi='Mickyy:BAAALAAECgIIAgAAAA==.Mildred:BAAALAADCgcIEwAAAA==.Mildredd:BAAALAAECgYICAAAAA==.Minibanana:BAAALAADCgEIAQAAAA==.Missis:BAABLAAECoEYAAIIAAgI2Qf7UwAzAQAIAAgI2Qf7UwAzAQAAAA==.',Mm='Mmarko:BAABLAAECoEYAAIMAAgIMgjLMwCWAQAMAAgIMgjLMwCWAQAAAA==.',Mo='Moghedien:BAAALAAECgMIBgAAAA==.Moltenjo:BAAALAAECgMIAwAAAA==.Mommymamba:BAAALAADCggICAAAAA==.Monkdral:BAACLAAFFIEKAAIXAAQIEBGeAQBPAQAXAAQIEBGeAQBPAQAsAAQKgRgAAhcACAh3GAwMACUCABcACAh3GAwMACUCAAAA.Monkmagic:BAAALAADCgQIBAAAAA==.Monster:BAAALAAECgYIBAAAAA==.Morketá:BAAALAADCggICAAAAA==.Motivation:BAAALAAECgUICgAAAA==.',Mu='Mudmud:BAAALAAECggICAAAAA==.Mudneck:BAAALAADCgIIAgAAAA==.Muffins:BAAALAADCgEIAwAAAA==.Munkenmogens:BAAALAADCgIIAgAAAA==.',My='Myllanis:BAAALAAECgQIBgAAAA==.Mynthara:BAAALAADCggIEwAAAA==.',['Má']='Máge:BAAALAADCggICAAAAA==.',['Mæ']='Mæ:BAAALAAECgYIDQAAAA==.',['Mè']='Mètalbenji:BAAALAAECgEIAQAAAA==.',Ne='Neenae:BAAALAAECggIDwAAAA==.Nes:BAACLAAFFIEPAAMMAAYIRh2YAAAoAgAMAAUIpSGYAAAoAgAYAAEIbge3DABRAAAsAAQKgRoAAgwACAgMJYMEAEQDAAwACAgMJYMEAEQDAAAA.Nevermyfault:BAAALAADCgUIBQAAAA==.',Ni='Nicdead:BAAALAAECggIEAAAAA==.Niff:BAAALAAECgIIAgAAAA==.Nilfilleniun:BAAALAADCgYIBgAAAA==.Ninjagrisen:BAAALAAECgMIAwAAAA==.',No='Nofoxgiven:BAAALAAECgQICgAAAA==.Nohunter:BAAALAAECgYICgAAAA==.',Nu='Nulleria:BAAALAADCgcIBwABLAAECgYIBgABAAAAAA==.',Ny='Nymera:BAAALAAECgYIDQAAAA==.',['Nò']='Nòx:BAAALAAECgMIAwAAAA==.',['Nø']='Nøgen:BAAALAAECgYIDwAAAA==.',Od='Oda:BAAALAADCggICAABLAAECggIHAANAIUbAA==.',Os='Osíris:BAAALAAECgMIAwAAAA==.',Ov='Ov:BAAALAADCgEIAQAAAA==.',Pa='Pakz:BAAALAADCgUIBgAAAA==.Palight:BAAALAAECgMIBAAAAA==.Parme:BAAALAADCgUIBgAAAA==.Parmesan:BAAALAAECgUIDQAAAA==.Parranoia:BAAALAAECggIEwAAAA==.',Pe='Persephoné:BAAALAAECgYIEgAAAA==.Perôna:BAAALAADCgcIFQABLAADCggICAABAAAAAA==.',Pi='Pinkiepie:BAAALAADCgYICgAAAA==.Pipz:BAAALAAECggICAAAAA==.Pipzz:BAAALAADCgEIAQAAAA==.Pityek:BAAALAADCggICwAAAA==.',Po='Poef:BAAALAADCggICAABLAAECgIIAgABAAAAAA==.Pollini:BAAALAADCgYIBwAAAA==.',Pr='Protein:BAAALAAECgYIEgAAAA==.',Ps='Pstav:BAAALAAECgcICwAAAA==.',['Pø']='Pøh:BAAALAAECgYIEgAAAA==.',Qu='Quirine:BAAALAADCggICgAAAA==.',Ra='Racular:BAAALAAECgUIDwAAAA==.Raeldan:BAAALAADCggICQAAAA==.Ragi:BAAALAAECgQICwAAAA==.Rammhammer:BAAALAAECgMIAwAAAA==.Rastabution:BAAALAAECgYIDQAAAA==.Ratters:BAAALAADCgUIBQAAAA==.Raybanz:BAAALAAECgYIDgAAAA==.',Rh='Rhyme:BAAALAADCgIIAgAAAA==.',Ri='Rickarus:BAAALAAECgYIEgAAAA==.Rikati:BAAALAAECgEIAQAAAA==.',Ro='Royal:BAAALAADCgcIBwAAAA==.',Ru='Ruhbuhguh:BAAALAADCggICgAAAA==.',Ry='Rybin:BAAALAAECgYIEAABLAAECggIEwABAAAAAA==.Ryän:BAAALAAECgEIAQAAAA==.Ryé:BAAALAAECgcIDQAAAA==.',Sa='Sakil:BAAALAADCgIIAgAAAA==.Salenia:BAAALAAECgYIEgAAAA==.Santéz:BAAALAADCgYIBAAAAA==.Sarria:BAAALAADCggICAAAAA==.Sasha:BAAALAAFFAIIAgAAAA==.Satanzlight:BAAALAAECgEIAQAAAA==.Saváge:BAAALAADCgcIBwAAAA==.Saítama:BAAALAADCgcIDgABLAAECgYIDwABAAAAAA==.',Sc='Scubadiver:BAAALAAECgYIDAAAAA==.Scyaliecyn:BAAALAAECgUIBgAAAA==.',Se='Seen:BAAALAAECgMIAwAAAA==.Seggar:BAABLAAECoEcAAINAAgIhRt/GQCWAgANAAgIhRt/GQCWAgAAAA==.Senbonzakurä:BAAALAAECgEIAQAAAA==.Sennah:BAAALAADCgEIAQAAAA==.Seps:BAAALAADCgcIBwABLAAECggIFgABAAAAAQ==.Serama:BAAALAADCgcIDQABLAAECgUIDwABAAAAAA==.Sesp:BAAALAAECggIFgAAAQ==.',Sh='Shadowness:BAAALAADCggIEAAAAA==.Shadowruns:BAAALAADCgcICQAAAA==.Shallot:BAAALAADCggICAAAAA==.Shambear:BAAALAAECgYIDwAAAA==.Shambles:BAAALAAECgMIAwAAAA==.Shammylou:BAAALAADCgIIAgAAAA==.Shamonrah:BAAALAAECgcIEAAAAA==.Shamtastics:BAAALAAECgEIAQAAAA==.Shaq:BAAALAAECgUIBwAAAA==.Sheitposter:BAAALAAECgEIAQAAAA==.Shibbs:BAAALAAECgQIBAAAAA==.Shinden:BAAALAAECgQIBgAAAA==.Shinycow:BAAALAADCgYIBgAAAA==.Shotan:BAAALAADCgMIAwAAAA==.Shuwanawana:BAAALAADCgcIAgAAAA==.',Si='Sidékick:BAAALAAECgQIBAAAAA==.Sindrion:BAAALAADCgMIBgAAAA==.Singh:BAABLAAECoETAAIKAAcInRdlPgDcAQAKAAcInRdlPgDcAQAAAA==.',Sk='Skyé:BAAALAADCggICAAAAA==.Skåningen:BAAALAAECgcICQAAAA==.',Sl='Slepil:BAAALAAECgYICgAAAA==.Slurk:BAAALAADCgUIBQAAAA==.Slurkx:BAAALAAECgMIBAAAAA==.',Sm='Smitta:BAAALAADCgYIBwABLAAECggIGwAZAOkkAA==.',Sn='Snegkulak:BAAALAADCgQIBAAAAA==.Snyltgäst:BAAALAADCggIFgAAAA==.',So='Somnissette:BAAALAADCgYIBgAAAA==.Soulmaim:BAAALAADCgcICAAAAA==.',Sp='Sparx:BAAALAAECgYIDwAAAA==.Spliffy:BAAALAADCggICAAAAA==.Spoxangel:BAAALAADCggICAAAAA==.Sprucer:BAAALAADCgcIBwAAAA==.',St='Starcatcher:BAAALAAECggIEgAAAA==.Statskinsky:BAAALAADCggIFQAAAA==.Stofs:BAACLAAFFIEGAAIaAAII0BAICwCpAAAaAAII0BAICwCpAAAsAAQKgRcAAhoACAgeGVINAIQCABoACAgeGVINAIQCAAAA.Stolkolight:BAAALAAECgcIDAAAAA==.Strahil:BAAALAADCgUICAAAAA==.Strife:BAAALAAECgYIBwAAAA==.Stripemage:BAAALAADCggICAABLAAFFAMICAAYALMkAA==.Stripesham:BAAALAADCgcIBwABLAAFFAMICAAYALMkAA==.Stripewarr:BAACLAAFFIEIAAIYAAMIsyShAQBJAQAYAAMIsyShAQBJAQAsAAQKgR8AAhgACAiwJjQAAJgDABgACAiwJjQAAJgDAAAA.',Sw='Swambodi:BAABLAAECoEUAAIbAAYIQCCXBAAjAgAbAAYIQCCXBAAjAgAAAA==.',Sy='Sylvann:BAAALAAECggICAAAAA==.Syri:BAAALAAECgEIAQAAAA==.Syrisus:BAAALAAECgYICgAAAA==.',['Sí']='Sínatra:BAAALAAECgYIDAAAAA==.',Ta='Taendir:BAAALAADCggICwABLAAECgYIBgABAAAAAA==.Taigaplox:BAAALAADCggIDgAAAA==.Tamakeri:BAAALAAECgYIEQAAAA==.',Te='Tearocks:BAAALAAECgYIDAAAAA==.Tedric:BAAALAAECgYIDwAAAA==.Teleport:BAAALAAECggICAAAAA==.Teniza:BAAALAADCggIDgAAAA==.Terix:BAAALAADCggICAABLAAECggIIAAMAC8cAA==.Terrain:BAAALAADCgEIAQAAAA==.',Th='Thanatoss:BAAALAAECgYIDgAAAA==.Theophanie:BAAALAADCggICAAAAA==.Theorcbear:BAAALAAECgMIAwAAAA==.Theronna:BAAALAADCggIEAAAAA==.Thonk:BAAALAAECgYIEgAAAA==.Thruxx:BAABLAAECoEgAAMMAAgILxwsEgCdAgAMAAgI6xssEgCdAgAcAAQIIRWuEwDuAAAAAA==.Thug:BAAALAAECgYIBgAAAA==.Thugdk:BAAALAAECgYICgAAAA==.Thugdruid:BAAALAAECgYIBQAAAA==.Thunderkaern:BAEALAAECgUIDQAAAA==.',Ti='Tiantar:BAAALAADCgQIBAAAAA==.Tinytornado:BAAALAAECgcIDQAAAA==.Titchevo:BAAALAADCgUIBQABLAAECgYIDwABAAAAAA==.Titchi:BAAALAAECgYIDwAAAA==.Tix:BAAALAAECgYIBgABLAAECggICAABAAAAAA==.',To='Tonsilitus:BAAALAADCgcICQAAAA==.Totemmaker:BAAALAAECgYIBgAAAA==.Totemtwister:BAAALAADCggICAAAAA==.Towel:BAABLAAECoEeAAMTAAgIzCRIAQBLAwATAAgIzCRIAQBLAwAZAAEIJBuDJwBIAAAAAA==.',Tr='Tranzbi:BAAALAADCggICAAAAA==.Trillé:BAAALAAECggICAAAAA==.Trixibell:BAAALAADCgcIEQAAAA==.Trsaa:BAAALAADCgcIDQABLAAECgcIEwABAAAAAA==.',Ts='Tsuyu:BAAALAAECgMIAwAAAA==.',Tu='Tudz:BAAALAADCgcIBgABLAAFFAIIBgANAGIbAA==.Tuospala:BAAALAAECgYIEQAAAA==.Tuossham:BAAALAADCggIFQABLAAECgYIEQABAAAAAA==.Turnusol:BAAALAAECgEIAQAAAA==.Tussa:BAAALAAECggIDgAAAA==.',Ty='Tyraèl:BAAALAADCgYIBgAAAA==.Tyristrum:BAAALAAECggIDwAAAA==.',['Tî']='Tîb:BAAALAADCgcIBwAAAA==.',['Tï']='Tïb:BAAALAADCgQIBAAAAA==.',Uj='Ujnek:BAAALAADCgMIAwAAAA==.',Un='Undralord:BAABLAAECoEVAAIdAAgI+BYUCQBsAgAdAAgI+BYUCQBsAgAAAA==.',Va='Vammp:BAAALAAECgYICgAAAA==.Vampz:BAAALAADCggICAAAAA==.Vappu:BAAALAADCggIAwAAAA==.Varigros:BAAALAAECgQIBgAAAA==.Vasilievena:BAAALAAECgUIBwAAAA==.Vaughn:BAAALAADCggIDAAAAA==.',Ve='Veejayvee:BAAALAAECgEIAQAAAA==.Velarina:BAEALAADCgIIAgABLAAECgUIDQABAAAAAA==.',Vi='Vics:BAAALAADCgcIBwABLAAECgYIDAABAAAAAA==.Viktora:BAAALAADCgYIBgABLAAECgYIDwABAAAAAA==.Vizari:BAAALAAECgQICQAAAA==.',Vo='Voltaic:BAAALAADCgIIAgAAAA==.Voltariis:BAAALAADCggICAAAAA==.Voltarin:BAAALAAECgUIBQAAAA==.Vorrell:BAAALAAECgIIAgAAAA==.',Vu='Vuldr:BAAALAAECgYIDQAAAA==.Vulxie:BAAALAAECgQIBgAAAA==.',['Và']='Vàrgas:BAAALAAECgIIAgAAAA==.',Wa='Walee:BAAALAAECgYICQAAAA==.',Wh='Whiteengel:BAAALAAECgMIAwABLAAECgYIDQABAAAAAA==.',Wi='Wickedwanda:BAAALAADCgEIAQAAAA==.Wiifi:BAABLAAFFIEGAAIIAAIIbiOoBwDQAAAIAAIIbiOoBwDQAAAAAA==.Willyorthumb:BAAALAAECgYIDwAAAA==.',Wo='Words:BAAALAADCgcIBwAAAA==.',Wr='Wrenn:BAAALAAECgMIBgAAAA==.',Wu='Wukkést:BAAALAAECgYIEAAAAA==.',['Wì']='Wìl:BAAALAAECgYIEQAAAA==.',Xa='Xaltherion:BAAALAADCggICwAAAA==.',Xe='Xerr:BAACLAAFFIEGAAIeAAIICBexCgCjAAAeAAIICBexCgCjAAAsAAQKgRcAAh4ACAgwHq0PAJwCAB4ACAgwHq0PAJwCAAAA.',Xi='Ximia:BAAALAADCggICAAAAA==.',Ya='Yazoo:BAAALAADCggIDgAAAA==.',Ye='Yeahal:BAAALAAECgIIBAAAAA==.',Ym='Ymir:BAAALAADCgUIBgAAAA==.',Yo='Yoyulun:BAAALAADCggICgAAAA==.',Za='Zandid:BAAALAAECgYIEgAAAA==.Zaryndra:BAAALAAECgIIAgAAAA==.',Ze='Zeadora:BAAALAAECgMIBQAAAA==.Zeci:BAAALAAECgYIBwAAAA==.Zele:BAAALAADCggICwAAAA==.Zempí:BAAALAAECgMIAwAAAA==.',Zi='Zipzip:BAAALAAECgQICQAAAA==.',Zo='Zokual:BAABLAAECoEaAAITAAgIwBiFFwAXAgATAAgIwBiFFwAXAgAAAA==.Zonden:BAAALAAECgcIBwAAAA==.Zondina:BAAALAAECggICQAAAA==.Zoomíe:BAAALAAECgMIAgAAAA==.',Zu='Zubeia:BAAALAADCggIDwAAAA==.',Zv='Zvezda:BAAALAADCggICAAAAA==.Zvezdica:BAAALAAECgUICgAAAA==.',['Ât']='Âthena:BAAALAADCgYICgAAAA==.',['Äp']='Äppeljuice:BAAALAADCgYIBgAAAA==.',['Æn']='Ænema:BAAALAAECgcIEwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end