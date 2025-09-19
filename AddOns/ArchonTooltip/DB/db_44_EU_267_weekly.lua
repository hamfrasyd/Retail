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
 local lookup = {'Monk-Brewmaster','Hunter-Marksmanship','Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','DeathKnight-Frost','Rogue-Subtlety','DemonHunter-Havoc','Rogue-Assassination','Rogue-Outlaw','Druid-Restoration','Paladin-Holy','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental',}; local provider = {region='EU',realm='BronzeDragonflight',name='EU',type='weekly',zone=44,date='2025-09-06',data={Ab='Abluchi:BAACLAAFFIEJAAIBAAMItxrNAgABAQABAAMItxrNAgABAQAsAAQKgSEAAgEACAgRIPYDAO0CAAEACAgRIPYDAO0CAAAA.Abusqa:BAAALAAECgUICwAAAA==.',Ad='Adge:BAAALAAECgcIDwAAAA==.',Ak='Akämï:BAAALAADCggIDAAAAA==.',Al='Alcatrax:BAAALAADCgYIBgAAAA==.Aleantara:BAAALAADCggICAAAAA==.Aliceo:BAAALAAECgEIAQAAAA==.Alvar:BAAALAAECggIEQAAAA==.Alyssandra:BAAALAADCgYIBgAAAA==.',Am='Amat:BAACLAAFFIEFAAICAAMIbQu3CgCiAAACAAMIbQu3CgCiAAAsAAQKgRsAAwIACAhOH2gQAH4CAAIACAhOH2gQAH4CAAMAAQhmDhGbACYAAAAA.Amiryth:BAAALAAECgUICwAAAA==.Amun:BAAALAAECgMIBgAAAA==.Amythiste:BAAALAAECggIDgAAAA==.',An='Angelwings:BAAALAAECgMIBAAAAA==.Antarion:BAAALAADCggICAAAAA==.',Ar='Aracari:BAAALAAECgYICwAAAA==.Aralan:BAABLAAFFIEFAAIEAAMILB8HAwAnAQAEAAMILB8HAwAnAQAAAA==.Arczii:BAAALAADCgYIBgAAAA==.Argonis:BAAALAADCggICgAAAA==.Aroman:BAAALAAECgIIAgAAAA==.',As='Asaêl:BAAALAADCgYIBgAAAA==.Asimin:BAAALAAECggICQAAAA==.',At='Atonis:BAAALAAECgYICwAAAA==.',Au='Auraablu:BAAALAAECgYIBgABLAAFFAMICQABALcaAA==.Auralux:BAAALAAECgUIBQAAAA==.Aurelian:BAAALAADCgcIBgAAAA==.',Az='Azarathal:BAAALAAECgYIDgAAAA==.Azríel:BAAALAADCgMIAwAAAA==.',Ba='Babspo:BAAALAAECgIIAgAAAA==.Badbuffy:BAAALAADCggIGQAAAA==.Bagerbyg:BAAALAADCgMIAwAAAA==.Balthazzar:BAAALAAECgYICgAAAA==.Barachus:BAAALAADCggIFAABLAADCggIGwAFAAAAAA==.',Be='Beammeup:BAABLAAECoEeAAMGAAgIQxmSFABaAgAGAAgIQxmSFABaAgAHAAYI3hGMMAB8AQAAAA==.Belafon:BAAALAAECgIIAgAAAA==.Belfdin:BAAALAADCgYIBgAAAA==.Bellemeow:BAABLAAFFIEGAAQIAAQIuh0uBQCxAAAIAAIIDBkuBQCxAAAJAAIIihkQBACnAAAKAAIImCAAAAAAAAAAAA==.Beni:BAAALAAECgUICgAAAA==.Beriothien:BAAALAADCgQIBgAAAA==.',Bh='Bhambu:BAAALAAECgEIAQAAAA==.',Bi='Bietle:BAAALAAECgQIBwAAAA==.',Bl='Blackdeathz:BAAALAADCgQIBAABLAAECgUICwAFAAAAAA==.Blodgnome:BAAALAADCggIEAAAAA==.Blodrae:BAAALAADCggICQAAAA==.',Bo='Boldir:BAAALAAECgYICAAAAA==.Boredome:BAAALAAECggICwAAAA==.Bowbelle:BAAALAAECgQIBQAAAA==.',Br='Brannburn:BAAALAAECgMIAwAAAA==.',Bu='Bughnrakh:BAAALAADCggIDwAAAA==.Bumps:BAAALAAECgQICAAAAA==.Burningflame:BAAALAADCgcIFAAAAA==.',Ca='Caatjee:BAAALAAECgEIAQAAAA==.Caitin:BAAALAAECgUICAAAAA==.Calethbe:BAAALAADCgcIBwAAAA==.Cap:BAAALAADCgUIBQAAAA==.Capradeus:BAAALAADCgcIBwAAAA==.Cartey:BAAALAAECgcICgAAAA==.Catastrophic:BAAALAAECgUICQABLAAFFAMIBAALALAOAA==.',Ch='Chantea:BAAALAAECgUIBQAAAA==.Chaztastic:BAAALAAECgQICAAAAA==.Chillidan:BAAALAAECgYIDwAAAA==.Chipnorris:BAAALAAECgIIBAAAAA==.Chlamydiara:BAAALAAECgEIAQABLAAFFAMIBQAEACwfAA==.Chubbycheeks:BAAALAADCgQIBAAAAA==.',Ci='Cierpliwy:BAAALAAECggICQAAAA==.',Cr='Crazyzz:BAAALAADCgUICAAAAA==.Creeps:BAAALAADCgQIBAAAAA==.Crispee:BAAALAAECgYICwAAAA==.Cryslin:BAAALAADCgcIFAAAAA==.',Cy='Cylea:BAAALAAECgQICAAAAA==.Cylia:BAAALAAECgQICAAAAA==.',Da='Daddymen:BAAALAADCgcIBwAAAA==.Daemi:BAAALAADCggIEgAAAA==.Daryana:BAAALAADCgMIAwAAAA==.',De='Deamonpas:BAAALAAECgEIAQAAAA==.Deathjump:BAABLAAECoEYAAIMAAgIqBqkGwCBAgAMAAgIqBqkGwCBAgAAAA==.Decapidave:BAAALAAECgYIDQAAAA==.Deeds:BAAALAAECgMICAAAAA==.Dempotat:BAAALAADCggIEAAAAA==.',Di='Diamondmoon:BAAALAADCggIEwAAAA==.Dibly:BAAALAAECgYIDwAAAA==.Dishevelled:BAAALAAECgUICwAAAA==.',Dj='Djokkoo:BAAALAAECggIEAAAAA==.',Do='Dolfke:BAAALAAECgcIDwAAAA==.Doomcow:BAAALAAECgMIAwAAAA==.Doralei:BAAALAADCggICAAAAA==.Dorph:BAAALAAECgcIEgAAAA==.',Dr='Dremura:BAAALAADCgYIBgAAAA==.Druidpeppa:BAAALAAECgYIDwABLAAECggIEgAFAAAAAA==.',Du='Dullemarc:BAAALAAECgQIBgAAAA==.',Dw='Dwarfomage:BAAALAAECgUIBQABLAAECggIEgAFAAAAAA==.',El='Elefier:BAAALAADCggIFQAAAA==.Elessar:BAAALAAECgIIAgAAAA==.Eliel:BAAALAADCggICAAAAA==.Ellosena:BAAALAADCgcIBwAAAA==.',Em='Emberdin:BAAALAADCgIIAgAAAA==.',En='Enirep:BAAALAAECgYICwAAAA==.',Er='Erendiel:BAABLAAECoEWAAIEAAcIDBmQLwAVAgAEAAcIDBmQLwAVAgAAAA==.',Es='Esplenda:BAAALAADCgcIDgAAAA==.',Ev='Evanía:BAAALAADCggIGAAAAA==.Eviane:BAAALAADCgYIBgAAAA==.Evíe:BAAALAADCggIEQAAAA==.',Fa='Faldirn:BAAALAAECgIIAgAAAA==.Fantur:BAAALAAECgcIEQAAAA==.Farida:BAAALAADCggICAAAAA==.Fauna:BAAALAADCggIFgAAAA==.',Fe='Felweave:BAAALAADCgEIAQAAAA==.Femz:BAAALAADCgEIAQAAAA==.',Fi='Fiber:BAAALAAECgEIAQAAAA==.Fivebyfive:BAAALAADCggIGwAAAA==.',Fj='Fjaari:BAAALAADCggICAABLAAECgYIDgAFAAAAAA==.',Fl='Flaire:BAAALAADCgUIBQAAAA==.Flamingburn:BAAALAAECgMIBgAAAA==.',Fo='Foghorn:BAAALAADCgcICgAAAA==.Forestfloor:BAAALAAECggICAAAAA==.',Fu='Fugur:BAAALAADCgcIBwAAAA==.Funli:BAAALAAECgQICgAAAA==.',Ga='Galga:BAAALAADCgMIAwAAAA==.Gallian:BAAALAAECgIIAgAAAA==.',Ge='Geam:BAAALAAECgIIAgAAAA==.',Gh='Ghan:BAAALAADCggIFgAAAA==.Ghanadriel:BAAALAADCgEIAQAAAA==.Ghanisham:BAAALAADCgUIAgAAAA==.Ghosturtle:BAAALAAECgMIAwAAAA==.',Gi='Gingerrunner:BAAALAADCggIDgAAAA==.',Gl='Gliter:BAAALAAECgUICwAAAA==.',Gn='Gnomia:BAAALAADCgYIBgAAAA==.',Gr='Grimer:BAAALAADCggIEQAAAA==.',['Gá']='Gáea:BAAALAADCgMIAwAAAA==.',Ha='Hallonbåt:BAAALAAECgQICAAAAA==.Hated:BAAALAAFFAIIBAAAAA==.Hatedholy:BAAALAAFFAIIAgABLAAFFAIIBAAFAAAAAA==.Hazyfantazy:BAAALAADCgcIDQAAAA==.',He='Heavycumer:BAAALAADCgYICAAAAA==.',Ho='Holgier:BAAALAAECgYIDgAAAA==.Hopka:BAAALAADCggICAAAAA==.',Hu='Hunterette:BAAALAADCgQIBAAAAA==.',['Hä']='Härfjätter:BAAALAAECgYICgAAAA==.',Ik='Iki:BAAALAAECgUICwAAAA==.',Il='Illididdydan:BAAALAADCgcICQAAAA==.',Im='Imadh:BAAALAADCgcIDgAAAA==.',In='Insane:BAAALAADCggICAAAAA==.',Is='Issyrath:BAAALAADCgcIBwAAAA==.',It='Itchyorcass:BAAALAADCggIFwAAAA==.',Ja='Jancä:BAAALAADCggIDAAAAA==.Jaryn:BAAALAADCggICAAAAA==.Jayeboyz:BAACLAAFFIEEAAILAAMIsA42AwC9AAALAAMIsA42AwC9AAAsAAQKgRsABAsACAi1IkYCAP0CAAsACAjkIUYCAP0CAA0ABwiLHoATADMCAA4AAQieEZQSADwAAAAA.',Je='Jerby:BAAALAADCgIIAgAAAA==.',Ji='Jinxit:BAAALAADCgcIDQABLAAECgMICAAFAAAAAA==.',Jo='Joddy:BAAALAAECgMICAAAAA==.Joj:BAAALAADCgIIAQAAAA==.',Jt='Jterrible:BAAALAAECgYIDAAAAA==.Jtsoaring:BAAALAAECgYIBgABLAAECgYIDAAFAAAAAA==.',Ju='Justtaki:BAAALAAECgIIAgAAAA==.',Ka='Kach:BAAALAAECggICAAAAA==.Katiya:BAAALAADCggIFAAAAA==.Kaz:BAAALAADCggICwAAAA==.Kazar:BAAALAADCgcIDgABLAAECgMIBgAFAAAAAA==.',Ke='Kernadronn:BAAALAADCggIEAAAAA==.',Ki='Kigomar:BAAALAAECgQIBAAAAA==.Kinte:BAABLAAECoEWAAIPAAcIDxyDEwA6AgAPAAcIDxyDEwA6AgAAAA==.',Ko='Kobato:BAAALAAECgUIDQAAAA==.Kohee:BAAALAAECgYIBwABLAAFFAMICQAQAHYiAA==.Korwalc:BAAALAADCggICAAAAA==.',Ky='Kyosi:BAAALAADCggIEgAAAA==.',Li='Liane:BAAALAADCggICQAAAA==.Lightrancid:BAAALAADCgQIBAAAAA==.Lirin:BAAALAAECgYIDQAAAA==.Litgnigpalad:BAAALAADCgYIBgAAAA==.Littlex:BAAALAADCggICAABLAAECgMIAwAFAAAAAA==.Liulu:BAAALAAECgMICAAAAA==.Liónsoul:BAAALAAECgUICAAAAA==.',Lo='Lobellia:BAAALAAECgYIDwAAAA==.Lonjohnshiva:BAAALAAECggIDQAAAA==.Lopen:BAAALAADCgUIBQABLAAECgYICAAFAAAAAA==.',Lu='Lucyline:BAAALAAECgYICwAAAA==.Lunacy:BAAALAAECgUICwAAAA==.Lunamarije:BAAALAADCgMIAwAAAA==.Lune:BAABLAAECoEcAAIEAAgIYgdSWwB9AQAEAAgIYgdSWwB9AQAAAA==.Lupocetflu:BAAALAADCgcIDAAAAA==.Luzzy:BAAALAAECgEIAQABLAAECggIEAAFAAAAAA==.',Ma='Maalfurion:BAAALAAECgIIAgAAAA==.Magixsammy:BAAALAAECgYIEgAAAA==.Mahzáel:BAAALAAECgYICwAAAA==.Maleficia:BAAALAAECgUICwAAAA==.Malinmystere:BAAALAAECgYICwAAAA==.Malleus:BAAALAAECggICAAAAA==.Mandar:BAAALAADCgYIBgAAAA==.Mapuxyaha:BAAALAADCggIDgAAAA==.Mattdæmon:BAAALAAECgYIBwAAAA==.',Me='Megapop:BAAALAAECgcIEQAAAA==.Meluniel:BAAALAAECgUIBQAAAA==.Meowmix:BAAALAAECgQIBQAAAA==.Merwllyra:BAAALAAECgUICwAAAA==.Mesara:BAAALAADCggICAABLAAECgYICwAFAAAAAA==.',Mi='Miilkyway:BAAALAAECgYIBgAAAA==.Miliantide:BAAALAAFFAIIAgAAAA==.Missivismo:BAAALAADCgQIBAAAAA==.',Mj='Mjazo:BAAALAADCggICAAAAA==.',Mu='Murderyard:BAAALAAECgQIBQAAAA==.',My='Mylord:BAAALAAECgQICgAAAA==.',['Må']='Månne:BAAALAADCggIDAAAAA==.',Na='Nazrael:BAAALAAECgMIAgAAAA==.',Ne='Necrotic:BAAALAADCgIIAgAAAA==.Necrozia:BAAALAADCgQIBAAAAA==.Nemesís:BAAALAADCggIEgAAAA==.Nessana:BAAALAAECgMIAwAAAA==.Nexttime:BAAALAAECgEIAQAAAA==.Nexuiz:BAAALAADCgYICQAAAA==.',Ni='Nimuelsa:BAAALAAECgQIBwAAAA==.',No='Norbez:BAAALAAECgMIBQAAAA==.Nordak:BAAALAAECgQIBAAAAA==.',['Ná']='Nátshèp:BAABLAAECoEUAAMRAAgI9BlOFwB2AgARAAgI9BlOFwB2AgASAAII1QkRVwBvAAAAAA==.',Om='Omachi:BAABLAAECoEcAAITAAgIgAgBNgCPAQATAAgIgAgBNgCPAQAAAA==.',Or='Orcshard:BAABLAAECoEaAAIKAAgIWiC2DwDdAgAKAAgIWiC2DwDdAgAAAA==.Organza:BAAALAADCgEIAgAAAA==.',Pa='Pallyndrome:BAAALAADCgQIBAAAAA==.Pammycakes:BAAALAAECgQIBAAAAA==.Pandella:BAAALAAECgMICAAAAA==.Paranoía:BAAALAADCgcIBwABLAADCgcIBwAFAAAAAA==.',Pe='Penkoburziq:BAAALAAECgYIDQAAAA==.',Ph='Phaora:BAAALAADCggICAAAAA==.Pheobs:BAAALAAECgQICgAAAA==.Phobosx:BAAALAADCggIDgABLAAECgMIAwAFAAAAAA==.',Pi='Pinewar:BAAALAAECgMIAwAAAA==.Pirreson:BAAALAAECgMIBQAAAA==.',Pl='Plaiqe:BAAALAADCgcIBwAAAA==.',Po='Poppie:BAAALAADCggIEQAAAA==.',Pr='Pro:BAAALAAECgUICwAAAA==.',Py='Pyrah:BAAALAAECgUIBQAAAA==.Pytscha:BAAALAAECgcIEwAAAA==.',Qu='Quanticos:BAAALAAECgUICwAAAA==.',Ra='Rasmar:BAAALAADCgUIBQAAAA==.',Re='Renascent:BAAALAAECggIDgAAAA==.',Ri='Rideit:BAAALAADCgYIBgABLAADCggIDgAFAAAAAA==.Riedis:BAAALAADCggIFQAAAA==.',Ro='Rothus:BAAALAADCgIIAgAAAA==.Rovadi:BAAALAADCgEIAgAAAA==.',['Rá']='Rázhar:BAAALAAECgYICwAAAA==.',Sa='Sambloom:BAAALAAECgQICQAAAA==.Samdeath:BAAALAADCgQIBAAAAA==.Samwisé:BAAALAADCgIIAgAAAA==.Sashiko:BAAALAAECgUICAAAAA==.Saslegrip:BAAALAAECgIIAgAAAA==.Saterskajsa:BAAALAAECgYIDwAAAA==.',Sc='Scalesworth:BAAALAAECgMIBAAAAA==.Schattenherz:BAAALAADCgUIBgAAAA==.Schmaug:BAAALAADCgcIBwAAAA==.Scorphina:BAAALAAECgEIAQAAAA==.',Se='Sendai:BAAALAADCggIEwAAAA==.Serenity:BAAALAAECgMIAwAAAA==.',Sg='Sgtdirtface:BAAALAAECggIEgAAAA==.',Sh='Shaari:BAAALAAECgcIEAAAAA==.Shadowze:BAAALAADCgIIAgAAAA==.Shamanmone:BAAALAADCggICAABLAADCggIDAAFAAAAAA==.Shamfox:BAAALAADCggICgAAAA==.Shamima:BAAALAADCggICAAAAA==.Shaojunz:BAAALAAECggICwAAAA==.Shaolight:BAAALAADCgcIBwAAAA==.Sharosha:BAAALAADCggIFAAAAA==.Sheerin:BAAALAAECgYICQAAAA==.Shiany:BAAALAAECgYICQAAAA==.Shiftshappen:BAAALAAECgUICgAAAA==.Shãmmy:BAAALAADCggIDwAAAA==.',Si='Sián:BAAALAADCggICwAAAA==.',Sl='Sleepydragon:BAAALAADCgcIDAAAAA==.',Sn='Sny:BAAALAAECgUICAAAAA==.Sníp:BAAALAADCgcICwAAAA==.',So='Solsken:BAAALAADCgMIAwAAAA==.',Sq='Squiggle:BAAALAADCgEIAQAAAA==.',St='Steve:BAAALAAECgQICAAAAA==.Strangerzord:BAAALAAECgYIDwAAAA==.Stripe:BAAALAAECgMIAwAAAA==.Stryff:BAAALAADCgIIAgAAAA==.',Su='Sunnai:BAAALAAECgYIDQAAAA==.Suspérious:BAAALAADCgQIBAAAAA==.',Sy='Syeriah:BAAALAAECgYIDwAAAA==.Sylsa:BAAALAADCgcIEAAAAA==.',['Sê']='Sêcare:BAAALAADCgcIBwAAAA==.',Ta='Taldron:BAAALAAECgMIAwAAAA==.Tankdroid:BAAALAADCgQIBAAAAA==.Tarabi:BAAALAAECgYICwAAAA==.Targas:BAAALAAECgEIAQAAAA==.Tariel:BAAALAADCgIIAgAAAA==.Tashenka:BAAALAADCgcICwAAAA==.',Te='Teioh:BAAALAAECgUIBgABLAAFFAMIBQACAG0LAA==.',Th='Thechiefhulk:BAAALAAECgQIBwAAAA==.Thenegative:BAAALAAECgUICAAAAA==.Thesalia:BAAALAAECgYIDAAAAA==.Thrallina:BAAALAADCgYICgAAAA==.',To='Toburr:BAAALAADCggICAAAAA==.Topless:BAAALAADCgIIAgAAAA==.Tornsoul:BAAALAADCgcIBwAAAA==.Toyo:BAAALAAECgIIAgABLAAECggIEQAFAAAAAA==.',Tr='Triphuntard:BAAALAADCggIHwAAAA==.Tryxodia:BAAALAADCgcIFgAAAA==.Tryxodiaa:BAAALAADCgYIBgABLAADCgcIFgAFAAAAAA==.',Un='Unholyselena:BAAALAADCgMIAwAAAA==.',Ur='Urieth:BAAALAAECgMICAAAAA==.',Va='Vaesandryn:BAAALAADCggIGAAAAA==.Valianá:BAAALAADCgMIAwAAAA==.Valthrenys:BAAALAADCggICwAAAA==.Vapouris:BAAALAADCggICAAAAA==.Vasiliki:BAAALAAECgYICgAAAA==.',Ve='Vebreihaedra:BAAALAADCggIDwAAAA==.Vedina:BAAALAAECgYIDAAAAA==.Vell:BAAALAADCgcIBwAAAA==.Vendir:BAAALAAECgUIBQAAAA==.Vesnir:BAAALAAECgMIBQAAAA==.',Vi='Virkon:BAAALAAECgIIAgABLAAECggIEAAFAAAAAA==.Vito:BAAALAADCggIEAAAAA==.',Vl='Vlaeye:BAAALAADCggIDAAAAA==.',Vo='Voidlocked:BAAALAAECgQICgAAAA==.',Wa='Wakio:BAAALAAECgIIAgAAAA==.Warmachienn:BAAALAAECgYICwAAAA==.',Wy='Wyrm:BAAALAADCgYIBgAAAA==.',Xb='Xberg:BAAALAAECgMIAwAAAA==.',Xe='Xerxes:BAAALAADCgEIAQAAAA==.',Ya='Yamasito:BAAALAADCgQIAQAAAA==.Yamii:BAAALAADCgIIAgAAAA==.Yasmiin:BAAALAADCgYIBgAAAA==.Yayxx:BAAALAAECgQIBAAAAA==.',Ym='Yma:BAAALAADCgQIBAAAAA==.',Yo='Yolandha:BAAALAAECgQIDAAAAA==.',Za='Zaigo:BAAALAADCgcIDQAAAA==.Zanzillt:BAAALAAECggIAgAAAQ==.',Zd='Zdzich:BAAALAAECgMICAAAAA==.',Ze='Zes:BAAALAADCgEIAQAAAA==.',Zh='Zhing:BAAALAAECgMIBgAAAA==.',Zo='Zophÿ:BAAALAAECgYICwAAAA==.',['Ár']='Árágorn:BAAALAAECgQIBAAAAA==.',['Ðy']='Ðyahx:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end