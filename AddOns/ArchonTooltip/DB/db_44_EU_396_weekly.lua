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
 local lookup = {'Shaman-Enhancement','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Mistweaver','Evoker-Augmentation','Evoker-Devastation','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination','Warrior-Protection','Druid-Restoration','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Monk-Windwalker','DemonHunter-Vengeance','DeathKnight-Unholy','Warrior-Fury','Priest-Holy','Shaman-Elemental','Priest-Discipline','Warrior-Arms','Druid-Balance',}; local provider = {region='EU',realm="Aman'Thul",name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aaronzen:BAAALAADCgIIAgAAAA==.Aaryon:BAAALAADCgcICwAAAA==.',Ab='Abrakedabra:BAAALAADCgcIBwAAAA==.Absinth:BAABLAAECoEYAAIBAAgIFyOwAAA8AwABAAgIFyOwAAA8AwAAAA==.',Ac='Accelerator:BAAALAAECgMIAwAAAA==.',Ad='Adamandrion:BAAALAADCgYIBQAAAA==.Addie:BAAALAAECgcIDwAAAA==.Adriah:BAAALAAECgcIEQAAAA==.Adrîanâ:BAAALAAECgEIAQAAAA==.',Ae='Aedie:BAAALAAECgYIBgAAAA==.Aelindra:BAAALAAFFAIIAgAAAA==.Aevret:BAAALAAECgEIAQAAAA==.',Af='Afromen:BAAALAADCgEIAQAAAA==.',Ag='Aggromoo:BAAALAAECgYICAAAAA==.',Ai='Aiana:BAAALAADCggICgAAAA==.Aislyn:BAAALAAECgIIAgAAAA==.',Ak='Akoy:BAAALAAECgUICAAAAA==.Akumu:BAAALAAECgMIAwABLAAECgcIDQACAAAAAA==.',Al='Alakod:BAAALAADCgYIBgAAAA==.Alaskaa:BAAALAAECgMIBAAAAA==.Aldarion:BAAALAAECgQICAAAAA==.Aleacia:BAAALAAFFAIIAgAAAA==.Alexru:BAAALAADCgYIBgAAAA==.Alkanol:BAAALAADCggIBwABLAAECgMIBgACAAAAAA==.Alèro:BAAALAAECgMIBgAAAA==.',Am='Amanda:BAAALAADCgYIBgAAAA==.Amoresecreta:BAAALAADCggICAAAAA==.Amyloe:BAAALAADCgcIBwAAAA==.Amáura:BAAALAADCgcIBwAAAA==.',An='Anak:BAAALAADCggICAAAAA==.Andelas:BAAALAADCggIDAAAAA==.Andugar:BAAALAAECgUIAQAAAA==.Angelynna:BAAALAADCggIFAAAAA==.Anuubis:BAAALAADCggIFQAAAA==.',Ao='Aoifusson:BAAALAADCggIFgAAAA==.',Ap='Apela:BAAALAADCggICAABLAAECgcIDwACAAAAAA==.Aphroditê:BAAALAADCgcIDAAAAA==.Apii:BAAALAAECgIIAgAAAA==.Apofîs:BAAALAADCgIIAgAAAA==.Apøphis:BAAALAAECgIIAgAAAA==.',Ar='Aradrion:BAAALAADCgEIAQAAAA==.Archius:BAAALAADCgIIAgAAAA==.Arrell:BAAALAAECgIIAgAAAA==.Aríya:BAAALAADCggICAAAAA==.',As='Ashcaly:BAAALAAECgQIAgAAAA==.Ashvera:BAAALAADCgYIBAAAAA==.Ashándria:BAAALAAECgIIAgAAAA==.Asires:BAAALAADCgUIBQAAAA==.Asmodenia:BAAALAADCggIDwAAAA==.Asmódiena:BAAALAADCggIDQABLAAECgMIBQACAAAAAA==.',At='Atzenadmiral:BAAALAADCgcICAAAAA==.',Au='Augusbrauus:BAAALAAECgMIAwAAAA==.Aunema:BAAALAADCgMIAwAAAA==.',Ba='Babsí:BAAALAAECgQIBwAAAA==.Backfinish:BAAALAADCgcIBwAAAA==.Balerock:BAAALAAECgIIAgAAAA==.Bambyhunter:BAABLAAECoEWAAMDAAgIxhtPDQChAgADAAgIihtPDQChAgAEAAMIQAzfQgCFAAAAAA==.Bambyqt:BAAALAADCggIDgABLAAECggIFgADAMYbAA==.',Be='Beatrice:BAAALAADCgcIBwAAAA==.Beazlebee:BAAALAADCgQIBAABLAAECgMIAwACAAAAAA==.Belethel:BAAALAAECgMIBAAAAA==.Beliar:BAAALAADCggIEQAAAA==.Belidía:BAAALAADCgIIAgABLAAECgcIDgACAAAAAA==.Bellaluna:BAAALAAECgEIAgAAAA==.Bellasina:BAAALAADCggICAAAAA==.Belána:BAAALAADCgcICQAAAA==.Belídia:BAAALAADCggICAABLAAECgcIDgACAAAAAA==.Belîdia:BAAALAADCgYICwAAAA==.Benjen:BAAALAAECgMIBAAAAA==.Beregond:BAAALAAECgIIAgAAAA==.Betasi:BAABLAAECoEWAAIFAAgISR91AwDTAgAFAAgISR91AwDTAgAAAA==.Beæst:BAAALAAECggICAAAAA==.',Bi='Biffbuff:BAAALAAECgYICQAAAA==.Bigmác:BAAALAADCgMIAwAAAA==.Bigshow:BAAALAAECgEIAQAAAA==.Biokriegerin:BAAALAADCgYIBgAAAA==.Biotea:BAAALAAECgUIBQAAAA==.Bishbashbosh:BAAALAADCggICAAAAA==.',Bl='Blackby:BAAALAADCggICAAAAA==.Blackmage:BAAALAADCgEIAQABLAAECgYIBAACAAAAAA==.Blackwôlf:BAAALAAECgYIDQAAAA==.Bleazy:BAAALAAECgMIAwAAAA==.Blindnotdeaf:BAAALAADCggICAAAAA==.Blitzty:BAAALAADCgUIBQAAAA==.Bláde:BAAALAADCgEIAQABLAAECgQIBAACAAAAAA==.',Bo='Boomfrog:BAAALAAECgUIBQAAAA==.Boondocsaint:BAAALAAECgMIBgAAAA==.',Br='Braids:BAAALAAECggIDgAAAA==.Brathaak:BAAALAAECgMIBAAAAA==.Brehzell:BAAALAADCgIIAgAAAA==.',Bu='Bubbleblock:BAAALAADCggICgAAAA==.Bubblebî:BAAALAAECggIAgAAAA==.Buddhaghosa:BAAALAAECgYIBwABLAAECgcIDAACAAAAAA==.Buhh:BAAALAADCggICAABLAAECgcIEAACAAAAAA==.Bulda:BAAALAAECgIIAgAAAA==.Bummelhummel:BAAALAADCggICAAAAA==.',['Bè']='Bèobull:BAAALAADCgYIBgAAAA==.',['Bê']='Bêâst:BAAALAADCggICAAAAA==.',['Bó']='Bóllék:BAAALAADCggIDgAAAA==.',Ca='Caesar:BAAALAADCgcIBwAAAA==.Caia:BAAALAAECgEIAQAAAA==.Cany:BAAALAAECgEIAQAAAA==.Cassîan:BAAALAADCgcIDwAAAA==.',Ce='Celebrator:BAAALAAECgEIAgAAAA==.',Ch='Chadfist:BAAALAADCgcIBwABLAAECgYICQACAAAAAA==.Chadstance:BAAALAAECgYICQAAAA==.Champagn:BAAALAAECgIIAQAAAA==.Chandini:BAAALAADCgcIEQAAAA==.Chernoby:BAAALAADCgcICwAAAA==.Chrong:BAAALAAECgYICAABLAAECggIFQAGAHkhAA==.',Cl='Closerera:BAAALAADCggIEgAAAA==.',Co='Comondra:BAAALAADCgcICQAAAA==.Cowcaine:BAAALAADCgcIBwAAAA==.',Cu='Cultdisco:BAAALAAECgMIAQAAAA==.Cursti:BAAALAADCgYIBgAAAA==.',['Cû']='Cûthalion:BAAALAAECgYIBwAAAA==.',Da='Daenerya:BAAALAADCgcIBwABLAAECgQIBQACAAAAAA==.Dajuna:BAAALAAECgcIDQAAAA==.Darknáturá:BAAALAAECgYIDwAAAA==.Darksbier:BAAALAADCggICAAAAA==.Darkêngel:BAAALAAECgEIAQABLAAECgMIAwACAAAAAA==.Darthvatter:BAAALAADCgMIAwAAAA==.',De='Deathader:BAAALAADCggIEAAAAA==.Deathknife:BAAALAADCggIDgABLAAECgYIBgACAAAAAA==.Deedolit:BAAALAAECgIIAgAAAA==.Deeppoisen:BAAALAADCggIDwAAAA==.Delcato:BAAALAADCgEIAQAAAA==.Demetrios:BAAALAADCggIDwABLAADCggIFgACAAAAAA==.Demonía:BAAALAAECgMIBAAAAA==.Demtry:BAAALAAECgYICwAAAA==.Dendayar:BAAALAADCggIEAAAAA==.Derriên:BAAALAAECgMIBQAAAA==.Desmonia:BAAALAADCggIFQAAAA==.Desolation:BAAALAADCggIDgAAAA==.Destrox:BAAALAADCgMIAwAAAA==.',Di='Diddelmaus:BAAALAADCgUIBQAAAA==.Dirbu:BAAALAAECgYICQAAAA==.Disi:BAAALAADCggICAABLAAFFAIIAgACAAAAAA==.Disithay:BAAALAADCgEIAQABLAAFFAIIAgACAAAAAA==.Dissonance:BAAALAAECgMIAwAAAA==.Dizol:BAAALAADCgcIDQAAAA==.Diônys:BAAALAAECgIIAwAAAA==.',Dj='Djean:BAAALAAECgEIAQAAAA==.',Do='Doomone:BAAALAAECgEIAQAAAA==.Dorkknight:BAAALAADCggIEAABLAAECgcIDAACAAAAAA==.Dornenfee:BAAALAADCgcIDQAAAA==.Dotlocker:BAAALAAECgcICgAAAA==.',Dr='Draneia:BAAALAAECgUICQAAAA==.Drevin:BAAALAADCggIGAAAAA==.Drihx:BAAALAAECggIDgAAAA==.Druîdê:BAAALAAECgYIBwAAAA==.',Du='Duduwinne:BAAALAADCgcIDQAAAA==.Dusclops:BAAALAADCggIFwAAAA==.',Dy='Dyprosium:BAAALAAECgYIBgAAAA==.',['Dé']='Déalus:BAAALAADCgcIDgAAAA==.',Ea='Easyc:BAAALAAECgUICAAAAA==.',Ed='Edramor:BAAALAADCggIEAAAAA==.',Eg='Egonkowalski:BAAALAADCgMIAwAAAA==.',Eh='Ehony:BAAALAAECgMIBAAAAA==.',Ei='Einfallslos:BAAALAAECggIEgAAAA==.',Ek='Eklypse:BAAALAAECgYIBwAAAA==.',El='Elathriell:BAAALAADCggIDwABLAAECggIFgAHAOMbAA==.Elberèth:BAAALAADCgcIEQAAAA==.Elpir:BAAALAAECggIAwAAAA==.Elrîa:BAAALAADCgQIBAAAAA==.Elsaahr:BAAALAAECgUIBwAAAA==.Elsahrthree:BAABLAAECoEYAAQIAAgIvR1aAwBlAgAIAAcIRBxaAwBlAgAJAAcIOBk2AwAhAgAKAAIILBLUOQCYAAABLAAECgUIBwACAAAAAA==.Elsahrtwo:BAAALAADCgcIBwABLAAECgUIBwACAAAAAA==.Elyise:BAAALAAECgYICQAAAA==.',Em='Emmia:BAAALAAECgQIBAAAAA==.Emïly:BAAALAAECgYICQAAAA==.',En='Ensignion:BAAALAAECgMIAwAAAA==.Envera:BAAALAADCgcIDAAAAA==.',Eo='Eomernemo:BAAALAAECgMIBAAAAA==.',Ep='Epix:BAAALAADCgQIBAAAAA==.',Er='Erfan:BAAALAADCgMIAgAAAA==.Eryndis:BAAALAADCggIDwAAAA==.',Es='Esil:BAAALAADCggIGAABLAAECgMIBQACAAAAAA==.Eskandar:BAAALAAECgYICQAAAA==.',Ev='Evølutzion:BAAALAAECgMIBQAAAA==.',Ex='Exochordaa:BAAALAADCggICAAAAA==.Exochordiâ:BAAALAAECgIIAgAAAA==.',Ey='Eydis:BAAALAADCggIFAAAAA==.',Ez='Ezina:BAAALAAECgYICAAAAA==.',['Eê']='Eêtu:BAAALAADCggIFgAAAA==.',['Eì']='Eìsenhorn:BAAALAADCggIFAAAAA==.',Fa='Fabibi:BAAALAADCggICAABLAAECgcIBwACAAAAAA==.Faithly:BAAALAAECgYIDgAAAA==.Farns:BAAALAADCgEIAQAAAA==.Faunuhua:BAABLAAECoEVAAIDAAgICBNhHgD/AQADAAgICBNhHgD/AQAAAA==.Favil:BAAALAAECggIAwAAAA==.',Fe='Feliane:BAAALAADCggIDQAAAA==.Feliciâ:BAAALAAECgMIBQAAAA==.Feuerhupe:BAAALAADCggIFgAAAA==.Feyndriel:BAAALAADCgcICgABLAAECgIIAgACAAAAAA==.',Fi='Fiorella:BAAALAADCgEIAQAAAA==.Fisgon:BAAALAAECgIIAgABLAAECgYICQACAAAAAA==.Fisgôn:BAAALAAECgYICQAAAA==.',Fl='Flenzer:BAAALAAECgYIBgAAAA==.Fleshgemes:BAAALAADCggICgAAAA==.Fluxxi:BAAALAAECgEIAQAAAA==.Flynnster:BAAALAADCgMIAwAAAA==.',Fr='Frèak:BAABLAAECoEWAAMDAAgIth5nCgDIAgADAAgIth5nCgDIAgAEAAMIjg2JQwCCAAAAAA==.Frídullîn:BAAALAAECgEIAQAAAA==.',Fu='Fullmétal:BAAALAAECgcIDwAAAA==.',Fy='Fya:BAAALAAECgMIBAAAAA==.Fyssl:BAAALAAECgYIBgAAAA==.',['Fê']='Fêrâdâr:BAAALAADCggIDQAAAA==.',Ga='Galadriél:BAAALAAECgQIBAAAAA==.Galigus:BAAALAADCgcICAABLAAFFAIIAgACAAAAAA==.Ganummel:BAAALAADCggIDwAAAA==.Garryh:BAAALAADCggIEQABLAAECgYIEgACAAAAAA==.',Ge='Geflügelgabi:BAAALAAECgYIBwAAAA==.',Gi='Girmar:BAAALAAECgEIAQAAAA==.',Gl='Glaubanwinne:BAAALAADCgYIAgAAAA==.Glubsch:BAAALAAECgYIDwAAAA==.',Go='Gogolîn:BAAALAADCgMIAwAAAA==.Gohstraider:BAAALAADCggIDwAAAA==.Golbez:BAAALAAFFAIIAgAAAA==.Golomer:BAAALAADCggIEAAAAA==.Gomjar:BAAALAADCgYIBgAAAA==.Gormas:BAAALAAECgYIDAAAAA==.',Gr='Greyvyard:BAAALAADCggICAAAAA==.Grishnakh:BAAALAADCgYICQAAAA==.Groyg:BAAALAADCgcIBwAAAA==.Gruselbude:BAAALAAECgUIBQAAAA==.',Gu='Gudrun:BAAALAADCgMIAwAAAA==.Gunta:BAAALAADCggICAAAAA==.',Gw='Gwentyla:BAAALAAECgMIBQAAAA==.Gwyddon:BAAALAADCgYIBgABLAAECgYICQACAAAAAA==.',Gy='Gyømei:BAAALAAECgcIDwAAAA==.',['Gî']='Gîn:BAAALAAECgMIAwAAAA==.',Ha='Haazinul:BAAALAAECgMIBQAAAA==.Halbilly:BAAALAAECgIIAgAAAA==.Haldír:BAAALAAECgIIAgAAAA==.Halloerstmal:BAAALAAECgIIAgAAAA==.Hamsterz:BAAALAAECgIIAgAAAA==.Handmaid:BAAALAADCgcIEgABLAAECgIIAgACAAAAAA==.Harlif:BAAALAADCgIIAgAAAA==.Hasslehoof:BAACLAAFFIEGAAILAAMIsxl3AQADAQALAAMIsxl3AQADAQAsAAQKgRcAAgsACAidJDIBAFMDAAsACAidJDIBAFMDAAAA.',He='Hektor:BAAALAAECgcIBwAAAA==.Heliodorus:BAAALAADCgcICwAAAA==.Henktoniter:BAAALAAECgIIAgAAAA==.Heschti:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.',Hi='Himbeere:BAAALAADCggICAABLAADCggICAACAAAAAA==.Hippo:BAAALAADCggICAABLAADCggICgACAAAAAA==.Hippolas:BAAALAADCgYIBgABLAADCggICgACAAAAAA==.Hippoleos:BAAALAADCggICgAAAA==.Hipporas:BAAALAADCgYIBwABLAADCggICgACAAAAAA==.',Ho='Hoignar:BAAALAAECgYIBwAAAA==.Holyroli:BAAALAAECgIIAgAAAA==.Horadrim:BAAALAAECgMIBAAAAA==.Hornyox:BAAALAAECgYIDQAAAA==.',Hu='Hucktoo:BAAALAAECgIIAgAAAA==.Humanoid:BAAALAAECggIEAAAAA==.Huntiboy:BAABLAAECoEXAAIDAAgIkyKbBgAEAwADAAgIkyKbBgAEAwAAAA==.',Hy='Hypo:BAAALAADCgIIAgAAAA==.',['Hà']='Hàdes:BAAALAAECgMIBgAAAA==.',['Hâ']='Hâvøc:BAAALAADCggICAAAAA==.',['Hé']='Hélmút:BAAALAADCgMIAQABLAAECggIFQAGAHkhAA==.',['Hê']='Hêphaistos:BAAALAADCgEIAQAAAA==.',['Hü']='Hüln:BAAALAAECggICAAAAA==.',Ia='Ialin:BAAALAADCggIFgAAAA==.',If='Iful:BAAALAAECgcIEQAAAA==.',Ik='Ikonikus:BAAALAADCggICAAAAA==.',Il='Ildressa:BAAALAADCggICAAAAA==.Ilmaré:BAAALAAECgQICQAAAA==.',In='Indriadsson:BAAALAAECgcIEAAAAA==.Inøsuke:BAAALAAECgYIBgABLAAECggIGAABABcjAA==.',Is='Islaria:BAAALAAECgIIAgAAAA==.Isyria:BAAALAADCggICAAAAA==.',Iv='Ivy:BAAALAADCggICAAAAA==.',Ix='Ixi:BAAALAAECgIIAgAAAA==.',Iz='Izigric:BAAALAADCggIDgAAAA==.',Ja='Jabbel:BAAALAAECgQICQAAAA==.Jaedana:BAAALAADCggIGAABLAAECgIIAgACAAAAAA==.Jalysea:BAAALAADCggICQAAAA==.Janus:BAAALAADCgcICAAAAA==.Jaro:BAAALAAECgEIAgAAAA==.',Je='Jetvin:BAAALAAECgEIAQAAAA==.',Ji='Jimmypearl:BAAALAAECggIAgAAAA==.',Jo='Jolanar:BAAALAAECgYIBwAAAA==.Jolle:BAAALAAECggIDgAAAA==.',Ju='Justbl:BAAALAAECgcIDwAAAA==.Justnonsense:BAAALAADCgYICQAAAA==.Justnotwoke:BAAALAADCggIEAAAAA==.',['Jä']='Jägergeile:BAAALAADCgcICAAAAA==.',['Jé']='Jéanné:BAAALAAECgMIBAAAAA==.',Ka='Kaelan:BAAALAAECggICAAAAA==.Kaelwryn:BAAALAAECgcIDQAAAA==.Kanra:BAAALAADCgYIBgABLAAFFAMIBgAMAJkdAA==.Karathena:BAAALAAECgMIBgAAAA==.Karesa:BAAALAAECgEIAQAAAA==.Kargolt:BAAALAAECgYIDwAAAA==.',Ke='Kerra:BAAALAADCgMIAwAAAA==.Keyano:BAAALAADCgcIBwAAAA==.',Kh='Kheyrá:BAAALAAECgQIBQAAAA==.Khorgar:BAAALAADCggIDwAAAA==.',Ki='Kidsdevourer:BAAALAADCggIDwABLAAECgcIDwACAAAAAA==.Kiridormi:BAAALAAECgMIBAAAAA==.Kiyuga:BAAALAADCggIEAAAAA==.',Kn='Knuspêrhêxê:BAAALAADCgQIAwAAAA==.',Ko='Konomi:BAAALAADCgMIAwAAAA==.Kortak:BAAALAADCggIFAABLAADCggIFgACAAAAAA==.',Kr='Kreiga:BAAALAADCggICgAAAA==.',Ku='Kuragari:BAAALAAECgcIDQAAAA==.Kurathir:BAAALAAECgIIAwAAAA==.Kuvert:BAAALAADCgcICgAAAA==.',Ky='Kyloo:BAAALAADCggIEAABLAAECgYIBAACAAAAAA==.Kyriu:BAAALAAECgcIEAAAAA==.Kytana:BAAALAAECgYIDwAAAA==.',['Kì']='Kìss:BAABLAAECoEWAAINAAgIoBXIGAABAgANAAgIoBXIGAABAgAAAA==.',La='Ladariel:BAAALAADCggIEwAAAA==.Laith:BAAALAADCggIFQABLAAECgMIAgACAAAAAA==.Lamont:BAAALAADCggIFgAAAA==.Lausel:BAAALAADCgMIAwAAAA==.',Le='Leduch:BAAALAAECgQIBAAAAA==.Leethria:BAAALAAECgYIDAAAAA==.Lejon:BAAALAAECgMIAgAAAA==.Leodorya:BAAALAAECgcIEAAAAA==.',Li='Licks:BAAALAAECgYICgAAAA==.Lienà:BAAALAAECgEIAQAAAA==.Lilthia:BAABLAAECoEWAAMOAAgInhqtBgBjAgAOAAgIwxmtBgBjAgAPAAUIgQ4/OQApAQAAAA==.Lirus:BAAALAAECgMIBQAAAA==.Littleevilin:BAAALAAECgMIBAAAAA==.Littlelluna:BAAALAADCgUIBgAAAA==.Livlyn:BAAALAAECgMIBgAAAA==.',Lj='Lj:BAAALAADCggIFQAAAA==.',Lo='Lockedin:BAAALAADCgYIBgABLAAECggIFQAGAHkhAA==.Lockslaý:BAAALAAECgIIAwAAAA==.Loqx:BAAALAADCgIIAgAAAA==.Lorênai:BAAALAADCgMIAwAAAA==.Low:BAAALAAECgcIBwAAAA==.',Lu='Luciana:BAAALAADCgcIBwAAAA==.Lucksnice:BAAALAADCgQIBQAAAA==.Luhx:BAAALAAECgYIBgAAAA==.Lumisade:BAAALAADCggICwAAAA==.Lunaticà:BAAALAADCggICAAAAA==.Luni:BAAALAADCgUIBQAAAA==.Lupiana:BAAALAAECgIIAwAAAA==.Luzìan:BAAALAAECgMIAwAAAA==.',Ly='Lymine:BAAALAAFFAIIAgAAAA==.',['Lâ']='Lânunâ:BAAALAAECgEIAQAAAA==.',['Lé']='Léxo:BAAALAADCgcICQAAAA==.',['Lî']='Lîcht:BAAALAAECgYICAAAAA==.Lîlîv:BAAALAADCggICwAAAA==.',['Lô']='Lôraine:BAABLAAECoEWAAIQAAgIuxpyBwBzAgAQAAgIuxpyBwBzAgAAAA==.',Ma='Magdran:BAAALAAECgMIBgAAAA==.Magrar:BAAALAAECgEIAQAAAA==.Mahr:BAAALAADCggICQAAAA==.Makeo:BAAALAAECggIEgAAAA==.Makkarôv:BAAALAAECgYIDAAAAA==.Mantro:BAAALAAECgIIAgAAAA==.Marisôl:BAAALAADCgcICAAAAA==.Markenbuddha:BAAALAADCgYIBgAAAA==.Marsbar:BAAALAADCgEIAQAAAA==.Maríschká:BAAALAADCggIBwAAAA==.Mash:BAAALAADCgYIDAAAAA==.Massmodudu:BAAALAAECgMIBAAAAA==.Massmuuh:BAAALAAECgIIAgAAAA==.Matew:BAAALAAECgMIAwAAAA==.Mathastrophe:BAABLAAECoEWAAIRAAgIyyKEAQARAwARAAgIyyKEAQARAwAAAA==.Mathemann:BAAALAAECgMIAwABLAAECggIFgARAMsiAA==.',Mc='Mcgun:BAAALAADCggIFQAAAA==.',Me='Mektita:BAAALAADCggIFwAAAA==.Mero:BAAALAAECggIDwAAAA==.Merobow:BAAALAAECgMIAwABLAAECggIDwACAAAAAA==.Merphêus:BAAALAADCggIFAAAAA==.Merryachi:BAAALAAECgMIBAAAAA==.Metablock:BAAALAAECgIIAgABLAAECgQIAgACAAAAAA==.',Mi='Microwave:BAAALAAECgcIBwAAAA==.Miekie:BAAALAADCggIFgAAAA==.Mikana:BAAALAAECgIIAgAAAA==.Mikejägger:BAAALAADCgcIBgAAAA==.Mineâ:BAAALAADCggIDwAAAA==.Minotas:BAAALAAECgYIDAAAAA==.Minotauruss:BAACLAAFFIEGAAIMAAMImR07AQArAQAMAAMImR07AQArAQAsAAQKgRcAAgwACAg6IHYEAMsCAAwACAg6IHYEAMsCAAAA.Minudeath:BAAALAADCggIFgAAAA==.Mistêryhunt:BAAALAAECgIIAgAAAA==.',Mo='Mokubar:BAAALAAECgEIAQAAAA==.Molly:BAAALAAECgEIAQAAAA==.Mooh:BAAALAADCggIEAABLAAECgMIBQACAAAAAA==.Moongomery:BAAALAAECgYIBgABLAAECgYIBgACAAAAAA==.Mormut:BAAALAAECgEIAgAAAA==.Moschus:BAAALAADCggICAAAAA==.',Mu='Murdonk:BAAALAADCggICAAAAA==.',My='Mydude:BAAALAADCggIDgAAAA==.',['Má']='Mádmáx:BAAALAADCggIFQAAAA==.',['Mä']='Mädimäd:BAAALAADCgYIBgAAAA==.',['Mî']='Mîmí:BAAALAAECgQIBwAAAA==.Mîzumi:BAAALAADCgUIBQAAAA==.',['Mô']='Môrgana:BAAALAADCgEIAQAAAA==.',Na='Narcissa:BAAALAADCgIIAgAAAA==.Narcîssus:BAAALAADCgcICgAAAA==.Narmora:BAAALAAFFAIIAgAAAA==.Natajo:BAAALAAECgMIBAAAAA==.Nathanus:BAAALAADCggIFQAAAA==.Navarone:BAAALAADCggIDwAAAA==.',Ne='Neferatah:BAAALAAECgMIBAAAAA==.Neltharíon:BAAALAAECgMIBAAAAA==.Nettchen:BAAALAAECgIIAgAAAA==.Nezumichan:BAAALAADCgcIBwABLAAECgcIDQACAAAAAA==.',Ni='Nightcløud:BAAALAADCgcIBwAAAA==.Nihlathak:BAAALAAECggICAAAAA==.Nimistrasz:BAABLAAECoEWAAIHAAgI4xvMCQCLAgAHAAgI4xvMCQCLAgAAAA==.Nirnaaeth:BAAALAAECgYIBgAAAA==.Nißa:BAAALAAECgMIBAAAAA==.',No='Nodruid:BAAALAAECgYIDQAAAA==.Novadine:BAAALAADCggICAAAAA==.Nowayout:BAAALAADCgUICAAAAA==.',Nu='Nucleus:BAAALAAECgMIAwAAAA==.Nudellauf:BAAALAAECgIIAgAAAA==.Nuhará:BAAALAADCgcIBwAAAA==.Nussknacko:BAAALAAECgYIDwAAAA==.',Ny='Nyadri:BAAALAADCgMIAwAAAA==.Nyløs:BAAALAAECgMIAwABLAAECgYICAACAAAAAA==.Nyriá:BAAALAADCggIDwAAAA==.Nysiyp:BAAALAAECgYIBgAAAA==.',Ob='Obelix:BAAALAADCgYIBgAAAA==.Obitoo:BAAALAADCgQIBAAAAA==.',Ol='Olivenschlec:BAAALAADCgIIAgAAAA==.',On='Ondriju:BAAALAAECgUIBQAAAA==.',Or='Orokbrom:BAAALAADCgYIBgAAAA==.',Pa='Paarn:BAAALAAECgMIBgAAAA==.Padre:BAAALAAECgcIEAAAAA==.Painsharer:BAAALAADCggICAAAAA==.Pak:BAAALAAECggICgAAAA==.Palinko:BAAALAADCggIDwABLAAECgcIDgACAAAAAA==.Palorizor:BAAALAADCgcIBwAAAA==.Pandemíe:BAABLAAECoEWAAISAAgIbSHWAQATAwASAAgIbSHWAQATAwAAAA==.Papaflo:BAAALAAECgMIAwAAAA==.Papercuttzi:BAAALAAECgQIBgAAAA==.Papperlpabb:BAAALAAECgEIAQAAAA==.Paranoiâ:BAAALAADCgYICgAAAA==.Paranoîa:BAAALAADCggIDwAAAA==.Past:BAAALAAECgMIAwAAAA==.',Pe='Peppône:BAAALAADCgYICgAAAA==.Petfluencer:BAAALAADCggICwAAAA==.',Pf='Pfeilokowski:BAAALAAECgQIBwAAAA==.',Ph='Phaemere:BAAALAADCgMIAwAAAA==.Phelba:BAAALAAFFAIIAgAAAA==.Philae:BAAALAAECgcIEQAAAA==.',Pi='Piccodie:BAAALAADCgcIBwAAAA==.',Po='Poisonangel:BAAALAADCggIFwAAAA==.Polybotes:BAABLAAECoEWAAMTAAgI+RwaCwDEAgATAAgI+RwaCwDEAgALAAgIFwsjFQBmAQAAAA==.Pouli:BAAALAADCggIFAAAAA==.',Pr='Presswurst:BAAALAAECgYICAAAAA==.Pricella:BAABLAAECoEWAAIUAAgICxRAFAAkAgAUAAgICxRAFAAkAgAAAA==.Propanol:BAAALAADCgYICQABLAAECgMIBgACAAAAAA==.Proskynese:BAAALAADCggIEAAAAA==.',Pu='Pullor:BAAALAADCgcIBwAAAA==.Purzelbrumpf:BAAALAAECgYICAAAAA==.',['Pí']='Píllepalle:BAAALAADCgcIEQAAAA==.',['Pú']='Púpsi:BAAALAAECgYIDAABLAAECggICAACAAAAAA==.',Ql='Ql:BAAALAADCgEIAQAAAA==.',Qu='Quarzerz:BAAALAADCgcICwAAAA==.Qupid:BAAALAAECgMIBgAAAA==.Qux:BAAALAAECgYICQAAAA==.',Ra='Raidii:BAAALAADCgYICAAAAA==.Rainrider:BAAALAADCggICQAAAA==.Raishan:BAAALAADCgcIDAAAAA==.Ramboe:BAAALAADCgcIBwAAAA==.Rambotan:BAAALAAECgIIAgAAAA==.Ranka:BAAALAADCggICgAAAA==.Rasalgul:BAAALAAECgEIAQAAAA==.',Re='Realolive:BAAALAADCgIIAgAAAA==.Redox:BAAALAADCgcICAAAAA==.Redzoraa:BAAALAADCgEIAQAAAA==.Reistlen:BAAALAAECgMIBAAAAA==.Rekrosh:BAAALAAECgEIAgAAAA==.Remux:BAAALAADCgIIAgAAAA==.',Rh='Rhaadraxas:BAAALAADCgUIBQAAAA==.Rhezy:BAAALAAECgQIBAAAAA==.',Ri='Riftmage:BAAALAAECgcIDQAAAA==.Rinarona:BAAALAADCggICAAAAA==.Rindeastwod:BAAALAADCggICgAAAA==.',Ro='Rogan:BAAALAAECgMIBAAAAA==.Roselyn:BAAALAADCgcIBwAAAA==.Rotauge:BAAALAAECgEIAQAAAA==.Rothen:BAAALAAECgEIAQAAAA==.Rox:BAAALAAECgMIBQAAAA==.Roxxzo:BAAALAADCgIIAgAAAA==.',Ru='Rubbeldekatz:BAAALAAECgIIAgAAAA==.Rubina:BAAALAADCgUIBQAAAA==.Rujen:BAAALAAECgMIBgAAAA==.Rupley:BAAALAADCgMIAwAAAA==.',Ry='Rylljin:BAAALAADCgIIAgABLAAECgMIBwACAAAAAA==.',['Rá']='Rágnâr:BAAALAAECggIAwAAAA==.',['Râ']='Râul:BAAALAADCgEIAQAAAA==.',['Ræ']='Ræged:BAAALAADCggIDwAAAA==.',['Ré']='Rédrum:BAAALAADCgYIBgAAAA==.',['Rî']='Rîftén:BAAALAADCgUIBQABLAAECgcIDQACAAAAAA==.',Sa='Salomeé:BAAALAADCggICAAAAA==.Salrithan:BAAALAADCgEIAQAAAA==.Salzigger:BAAALAAECgUIBQAAAA==.Samyll:BAAALAAECgMIBwAAAA==.Saphriel:BAAALAAECgYICAAAAA==.Sasali:BAAALAADCggICAAAAA==.Sasalie:BAAALAAECgIIAgAAAA==.',Sc='Schafira:BAAALAAECgYIDgAAAA==.Schattenwolf:BAAALAAECgIIAwAAAA==.Schawamalord:BAAALAADCggICAAAAA==.Scheintôt:BAAALAADCggIFgAAAA==.Schiruka:BAAALAAECgUIBQAAAA==.Schmohn:BAAALAAECgQICAAAAA==.Schmy:BAAALAAECgcIBwABLAAECggIFwAUABUbAA==.Schnurrbert:BAAALAAECgQIBQAAAA==.Schnuurpfau:BAAALAADCggICAAAAA==.Schuko:BAAALAAECgYIDgAAAA==.Schulrike:BAAALAADCgcIBwAAAA==.Schânee:BAAALAADCggICAAAAA==.Scrumhel:BAAALAAECgMIBAAAAA==.Scythê:BAAALAADCgUIBQAAAA==.Scârêcrow:BAAALAADCgcIBwAAAA==.',Se='Seralin:BAAALAAECgEIAgAAAA==.Sereban:BAAALAADCgMIAwAAAA==.Seuchenfürst:BAAALAADCgcICwAAAA==.',Sh='Shagaru:BAAALAAECgIIBAAAAA==.Shanoh:BAAALAAECgMIAwAAAA==.Shaolinda:BAAALAAECgMIBAAAAA==.Sharlin:BAAALAAECgMIAwAAAA==.Shazamshazam:BAAALAAECgMIAwAAAA==.Sheian:BAAALAADCgYIBgABLAAECgEIAQACAAAAAA==.Shephor:BAAALAADCgIIAgAAAA==.Shibuki:BAAALAADCgYIBQAAAA==.Shigure:BAAALAAECgIIAgAAAA==.Shinsen:BAAALAADCgIIAgABLAAECgcIDQACAAAAAA==.Shizensaigai:BAAALAADCgYIBgABLAAECgcIDQACAAAAAA==.Shizuka:BAAALAADCggIDQABLAAECgYICQACAAAAAA==.Shockblocked:BAAALAADCgQIBAAAAA==.Shoily:BAAALAADCgcIBwAAAA==.Shradou:BAAALAAECgMIBgAAAA==.Shánindrá:BAAALAAECgMIBgAAAA==.Shêîlá:BAAALAADCgEIAQAAAA==.Shîfty:BAAALAADCggICAAAAA==.Shîgo:BAAALAAECgYIDAAAAA==.Shûna:BAAALAADCgcIDQAAAA==.',Si='Sitalia:BAAALAADCggIEAAAAA==.',Sk='Skarthul:BAAALAAECgcIEQAAAA==.Skype:BAABLAAECoEXAAIVAAgI2h82BwD3AgAVAAgI2h82BwD3AgAAAA==.Skálkur:BAAALAAECgMIAwAAAA==.Skýllár:BAAALAADCggICAABLAAECgcIDAACAAAAAA==.',Sl='Slixz:BAAALAAECgYICAAAAA==.',Sm='Smmi:BAAALAAECgIIAgABLAAECggIFwAUABUbAA==.Smy:BAAALAADCggIDwABLAAECggIFwAUABUbAA==.Smördy:BAAALAAECgIIAgAAAA==.Smý:BAABLAAECoEXAAMUAAgIFRsWCwCLAgAUAAgIgRoWCwCLAgAWAAcIohIEBQDHAQAAAA==.',Sn='Snatsh:BAAALAADCggIGAAAAA==.Sneasel:BAAALAAECgcIDAAAAA==.Snessak:BAAALAAECgQIBAAAAA==.Snâp:BAAALAAECgIIAgAAAA==.',So='Socy:BAAALAADCgcIBwAAAA==.Sonnenglanz:BAAALAADCgQIBgAAAA==.Sorolk:BAAALAADCggICAAAAA==.',Sp='Sphinx:BAAALAADCgUIBQAAAA==.Spoz:BAAALAAECgUICQAAAA==.Springlêaf:BAAALAADCggIFAAAAA==.Späcksi:BAAALAAECgYIBwAAAA==.Spéctróhúnt:BAAALAAECggIAQAAAA==.',St='Stablumpe:BAAALAADCgIIAgAAAA==.Staub:BAAALAADCgcIBwABLAAECgYIDQACAAAAAA==.Stellå:BAAALAADCgcIBwAAAA==.',Su='Sukassa:BAAALAAECgIIAgAAAA==.Sulfar:BAAALAADCgcIBwAAAA==.Sundae:BAAALAAECgcIDwAAAA==.Sural:BAAALAADCgcIBwAAAA==.',Sy='Syndrar:BAAALAAECgYIDgAAAA==.',['Sè']='Sèntii:BAAALAAECgYIDwAAAA==.',['Sê']='Sêt:BAAALAAECgUICAAAAA==.',['Sî']='Sîggi:BAAALAAECgMIBQAAAA==.',Ta='Tafkao:BAAALAAECgIIAgAAAA==.Taishar:BAAALAADCgcIBwAAAA==.Takkofashion:BAAALAAECgYIEgAAAA==.Tamorîa:BAAALAADCggICAABLAAECgMIBQACAAAAAA==.Tarina:BAABLAAECoEWAAMXAAgIUSL6AAD9AgAXAAgITyD6AAD9AgATAAcI6h3zEwBEAgAAAA==.Tasira:BAAALAAECgcIEwAAAA==.Tauniki:BAAALAADCgcIAQAAAA==.',Te='Tekli:BAAALAAECgMIBAAAAA==.Temerair:BAAALAADCgMIAwAAAA==.Tempestcv:BAAALAAFFAIIAgAAAA==.Tenestro:BAAALAADCggIDAAAAA==.Tenzoku:BAABLAAECoEWAAMDAAgIPCazAQBiAwADAAgIPCazAQBiAwAEAAUI8xskHwCHAQAAAA==.Teranola:BAAALAAECgYIDAAAAA==.Terrixd:BAAALAAECggIDgAAAA==.',Th='Thalrion:BAAALAAECggICAAAAA==.Theophanie:BAAALAAECgcIDwAAAA==.Therianis:BAAALAADCggIBAAAAA==.Thermacare:BAAALAAECgYICwABLAAECgcIDAACAAAAAA==.Thomeik:BAAALAADCggICAAAAA==.Thràxx:BAAALAADCgUIBQAAAA==.Théea:BAAALAAECggIEgAAAA==.',Ti='Tifana:BAAALAAECgEIAQAAAA==.Tiggipriest:BAAALAADCgMIAwAAAA==.Tiggitroll:BAAALAAECgMIBgAAAA==.Tinkâ:BAAALAAECgcICgAAAA==.',To='Toastada:BAAALAADCggIEQAAAA==.Togrem:BAAALAADCggICAAAAA==.Tomdruid:BAAALAAECgMIAwAAAA==.Tomfusíon:BAAALAADCgcIBwAAAA==.Tonks:BAAALAADCgcICwAAAA==.Torjana:BAEALAAECgMIBAAAAA==.Torunel:BAAALAAECgEIAQAAAA==.Tosantre:BAAALAADCggICAAAAA==.Totoschka:BAAALAADCgcIBwAAAA==.',Tr='Treox:BAAALAADCggICQAAAA==.Trollgrim:BAAALAAECgYIDAAAAA==.Truinx:BAAALAAECgIIBAAAAA==.',Tu='Turtrix:BAAALAADCgQIBAABLAADCgYIBgACAAAAAA==.',Ty='Tyrae:BAAALAAECgMIBgAAAA==.Tyranus:BAAALAAECgUIBQAAAA==.Tyronnemo:BAAALAADCgcICgAAAA==.Tyrånde:BAAALAAECgMIBAAAAA==.',Tz='Tziguerrilla:BAAALAADCgcIBwAAAA==.',['Tí']='Tíana:BAAALAAECgUIBQAAAA==.',['Tî']='Tîffy:BAAALAADCggIDwAAAA==.',['Tó']='Tóm:BAAALAADCgYIBgAAAA==.',Uh='Uhruz:BAAALAAECgIIAgAAAA==.',Ul='Ulmus:BAAALAAECgMIBgAAAA==.',Us='Username:BAAALAADCgcIEgAAAA==.Ushikuru:BAAALAAECgMIBQAAAA==.',Va='Vaalie:BAAALAAECgIIAgAAAA==.Vaerina:BAAALAADCgUIBQAAAA==.Vahinko:BAAALAAECgcIDgAAAA==.Valêria:BAAALAAECgEIAQAAAA==.Vanum:BAAALAAECgMIBAAAAA==.Varûlv:BAAALAADCggICQABLAAECgMIAgACAAAAAA==.Vateria:BAAALAADCgcICwAAAA==.',Ve='Velaranya:BAAALAADCggIEgAAAA==.Vene:BAAALAAECgYIBAAAAA==.Vesperus:BAAALAADCgYIBwAAAA==.',Vi='Viennah:BAAALAAECgYIEQAAAA==.Violah:BAAALAADCgEIAQAAAA==.Violetmight:BAAALAADCggIDwAAAA==.Visinas:BAAALAAECgYIDwAAAA==.',Vu='Vulterlorian:BAAALAADCgcIBwAAAA==.',Vy='Vycé:BAAALAAECgIIAgABLAAECggIEAACAAAAAA==.',['Vä']='Väktari:BAAALAADCggIEgAAAA==.',['Vè']='Vèntress:BAAALAAECgYIBgAAAA==.',['Ví']='Vílâ:BAAALAAECgMIAwAAAA==.',['Vý']='Výcè:BAAALAAECggIEAAAAA==.',Wa='Waltraud:BAAALAAECgcICwAAAA==.Wapuza:BAAALAAECgIIAgAAAA==.Warrix:BAAALAADCgEIAQAAAA==.',Wh='Whitebeard:BAAALAADCgcIDQAAAA==.',Wi='Winnehex:BAAALAADCgUIBQAAAA==.Winnepuu:BAAALAADCgYIDAAAAA==.Winneschuss:BAAALAADCgYIBwAAAA==.',Wo='Woelfchen:BAAALAAECgYICQAAAA==.Wollebi:BAAALAAECgcIDAAAAA==.Woodlaw:BAABLAAECoEVAAIYAAgImxitCwB8AgAYAAgImxitCwB8AgAAAA==.',Wu='Wutknete:BAAALAAECgQIBAAAAA==.',Wy='Wyldflames:BAAALAADCgcIDgAAAA==.',Xe='Xenielle:BAAALAAECgMIAwAAAA==.',Xg='Xgongivit:BAAALAADCggIEAABLAAECggIEgACAAAAAA==.',Xh='Xheng:BAAALAAECgUICQAAAA==.',Xi='Xiqura:BAAALAADCgUIBQAAAA==.Xiroy:BAAALAAECgMIAwAAAA==.',Xo='Xoon:BAAALAADCgcIEgABLAADCggIFgACAAAAAA==.',['Xâ']='Xâz:BAAALAAECgMIBwAAAA==.',Ya='Yaaen:BAAALAADCggIFgABLAAECgIIAgACAAAAAA==.Yamakiri:BAAALAAECgQICAAAAA==.Yawar:BAAALAAECgUIBgAAAA==.',Ye='Yelzar:BAAALAAECgYIBwAAAA==.Yevî:BAAALAAECgIIAgAAAA==.',Yo='Yokal:BAAALAADCggICAAAAA==.Yousei:BAAALAAECgYIDQABLAAECgcIDQACAAAAAA==.',Yr='Yrene:BAAALAADCggIFQAAAA==.',Yu='Yuneria:BAAALAAECgIIBAAAAA==.Yuú:BAAALAAECgMIBQAAAA==.',Za='Zabosius:BAAALAADCgcICAAAAA==.Zadel:BAAALAAECgEIAQAAAA==.Zarurion:BAAALAADCgUIBQAAAA==.Zaz:BAAALAADCgcIBwAAAA==.',Ze='Zerodh:BAAALAADCggICAAAAA==.Zestymemes:BAAALAADCgYIBgAAAA==.',Zo='Zolthur:BAAALAAECgMIBgAAAA==.Zoronta:BAAALAAECgMIBQAAAA==.',Zu='Zurathul:BAAALAADCggIFwAAAA==.',Zw='Zwiderwurzn:BAAALAADCgcICQAAAA==.',['Zè']='Zèldâ:BAAALAAECgEIAQAAAA==.',['Ât']='Âthel:BAAALAADCggIEAAAAA==.',['Äb']='Äbbel:BAAALAADCggICAAAAA==.Äbbell:BAAALAAECgcIBwAAAA==.Äbble:BAAALAADCgYIBgAAAA==.',['Äs']='Äsera:BAAALAAECgMIAgAAAA==.',['Æb']='Æba:BAAALAADCgEIAQABLAADCggICQACAAAAAA==.',['Æt']='Æthas:BAAALAADCgcIBwABLAADCggICQACAAAAAA==.',['Æx']='Æxitus:BAAALAADCggICQAAAA==.',['Ça']='Çaru:BAAALAAECgEIAQAAAA==.',['Ço']='Çolonia:BAAALAADCgUIBQAAAA==.',['Ðí']='Ðíablo:BAAALAADCgYIBgAAAA==.',['Ñy']='Ñyúú:BAAALAAECgUICwAAAA==.',['Üb']='Übärmythisch:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end