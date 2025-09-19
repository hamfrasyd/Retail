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
 local lookup = {'Priest-Holy','Mage-Arcane','Mage-Fire','Unknown-Unknown','Mage-Frost','Priest-Shadow','DeathKnight-Blood','Evoker-Preservation','Hunter-BeastMastery','Rogue-Assassination','Rogue-Subtlety','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Shaman-Elemental','Paladin-Retribution','Druid-Restoration','Druid-Balance','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Priest-Discipline','Warlock-Affliction','Warlock-Destruction',}; local provider = {region='EU',realm='Proudmoore',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Acri:BAAALAADCgcIBwAAAA==.',Ad='Adaneth:BAAALAADCgcIBwAAAA==.',Ai='Aigil:BAAALAAECgcIEAAAAA==.Airok:BAAALAADCggICAAAAA==.',Ak='Akwin:BAABLAAECoEXAAIBAAgIwxNUEwArAgABAAgIwxNUEwArAgAAAA==.',Al='Albus:BAAALAAECgYICQAAAA==.Alyna:BAAALAADCggICAAAAA==.Alyssaa:BAAALAAECgMIAwAAAA==.Alytdris:BAAALAAECgEIAQAAAA==.',Am='Ametyst:BAAALAADCgUIBAAAAA==.',An='Anemsis:BAAALAADCgcICQAAAA==.Angelsky:BAAALAAECgIIAgAAAA==.Antoniá:BAAALAADCggIFAAAAA==.',Ar='Ariee:BAAALAAECgQIBAAAAA==.',As='Ashwing:BAAALAADCggIGAAAAA==.',Au='Audítóre:BAAALAAECgcIDgAAAA==.Auryna:BAAALAAECgMIBQAAAA==.',Ax='Axeeffect:BAAALAAECgMIBQAAAA==.',Ay='Ayuki:BAAALAAECgYICQAAAA==.',Ba='Balren:BAABLAAECoEXAAMCAAgIWCH4CQDtAgACAAgI3h/4CQDtAgADAAEIwBiLDABKAAAAAA==.',Be='Benda:BAAALAADCgYIBgABLAADCggIEAAEAAAAAA==.Beohn:BAAALAADCggIFAAAAA==.Beredan:BAAALAAECgMIAwAAAA==.',Bi='Bigland:BAAALAAECgYICgAAAA==.Bislipur:BAAALAADCgUIBQAAAA==.',Bl='Blackpánn:BAAALAADCgcIDQAAAA==.',Bo='Bobi:BAAALAADCggICAAAAA==.Bogey:BAAALAADCgYIBgABLAAECggIDgAEAAAAAQ==.Bomboor:BAAALAADCgcIDQABLAAECgMIAwAEAAAAAA==.Bombôr:BAAALAAECgMIAwABLAAECgMIAwAEAAAAAA==.',Br='Bratac:BAAALAAECgIIAgAAAA==.',Bu='Bunnahabhain:BAAALAAECgEIAQAAAA==.Buschmann:BAAALAAFFAIIAgAAAA==.',Ca='Cainnix:BAAALAADCggICAAAAA==.Carras:BAABLAAECoEMAAIFAAYIWg0gHwBOAQAFAAYIWg0gHwBOAQAAAA==.',Ce='Cerebres:BAAALAAECgMIAwAAAA==.',Ch='Chomps:BAAALAADCgcIDAAAAA==.Chuckman:BAAALAADCgcIBwABLAAECgcIDwAEAAAAAA==.Chupsi:BAAALAADCggICAAAAA==.',Ci='Cinin:BAAALAAECgcICgABLAAECgcIFQAGAMAgAA==.',Cl='Claw:BAAALAADCggIFAAAAA==.',Co='Cocoheal:BAAALAAECgMIAwAAAA==.Coonz:BAAALAAECgYICAAAAA==.',['Cá']='Cástiell:BAAALAADCgMIAwAAAA==.',['Cí']='Cíjara:BAAALAADCggIEAABLAAECggIDAAEAAAAAA==.',['Cô']='Côsma:BAAALAAECgMIAwAAAA==.',Da='Daemis:BAAALAADCggIFAAAAA==.Darkdeamon:BAAALAAECgIIAwAAAA==.Darkpando:BAAALAAECgMIAwAAAA==.Darkweaver:BAAALAADCgcICAAAAA==.',De='Deathcaller:BAAALAADCggIFgAAAA==.Deathdog:BAABLAAECoEXAAIHAAgIXRHkCADeAQAHAAgIXRHkCADeAQAAAA==.Deathsoul:BAAALAADCgEIAQAAAA==.Delmon:BAAALAAECgMIBAAAAA==.Deluna:BAAALAAECgMIAwAAAA==.Dema:BAAALAAECgMIAwAAAA==.Demeter:BAAALAAECgIIAwAAAA==.Demønic:BAAALAAECgUIBgAAAA==.Devilschurk:BAAALAAECgMIBgAAAA==.Deymos:BAAALAAECgIIAwAAAA==.',Do='Dolchdieter:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.',Dr='Dracpro:BAABLAAECoEXAAIIAAgIARhFBABqAgAIAAgIARhFBABqAgAAAA==.Drahgo:BAAALAADCgUICgAAAA==.Dreggi:BAAALAAECgQIBAAAAA==.Droden:BAAALAAECgcIEAAAAA==.Droxa:BAAALAAECgUIBQAAAA==.',Du='Dud:BAAALAAECgEIAgABLAAECgMIAwAEAAAAAA==.',['Dé']='Déllingr:BAAALAADCgYIBgAAAA==.',Ec='Echtjetzt:BAABLAAECoEXAAIJAAgIhCOtAwA5AwAJAAgIhCOtAwA5AwAAAA==.',El='Elae:BAAALAADCgcICAAAAA==.Elandaa:BAAALAAECgEIAQAAAA==.Elanorel:BAAALAAECgYICgAAAA==.Elazra:BAAALAADCggICAAAAA==.Elborn:BAAALAADCggIDgAAAA==.Elumyr:BAAALAADCggICAAAAA==.',Eo='Eomer:BAAALAADCggIEwAAAA==.',Er='Erol:BAAALAADCgEIAQAAAA==.',Es='Esari:BAAALAADCgEIAQAAAA==.',Ey='Eyeswîdeshut:BAAALAAECgQICQAAAA==.',['Eí']='Eínmalíg:BAAALAAECgYICwAAAA==.',Fa='Fazknight:BAAALAADCggICAABLAAECgIIAwAEAAAAAA==.',Fe='Feuerbluete:BAAALAAECgMIBQAAAA==.Fexxquo:BAAALAAECggICAAAAA==.',Fi='Fiana:BAAALAAECgMIAwAAAA==.',Fo='Fodo:BAAALAAECgIIAwAAAA==.Fosco:BAAALAAECgIIBAAAAA==.Foxxi:BAAALAADCgcIBwAAAA==.',Fr='Freakymeaky:BAAALAAECgMIBwAAAA==.Freundschaft:BAAALAADCggICAAAAA==.Friendlyfire:BAAALAADCgQIAgABLAAECgMIAwAEAAAAAA==.',Fu='Furybeast:BAAALAADCggICAAAAA==.',Fy='Fyreyell:BAAALAAECgcIEAAAAA==.',['Fá']='Fáýólá:BAAALAAECgMIAwAAAA==.',['Fâ']='Fâlkê:BAAALAAECgQICQAAAA==.',Ga='Gajus:BAAALAADCgcIBwAAAA==.',Ge='Geobeo:BAAALAAECgYICQAAAA==.',Gh='Ghôst:BAAALAAECgMIBAAAAA==.',Gi='Gieridan:BAAALAAECgYICQAAAA==.',Gl='Glítterbean:BAAALAADCggIAwAAAA==.',Gn='Gnexer:BAAALAAECgEIAQAAAA==.',Go='Gorena:BAAALAAECgQIBQAAAA==.',Gr='Grexx:BAAALAADCgcIDAAAAA==.Grizoo:BAAALAADCggIEAAAAA==.',Gu='Gulzerian:BAAALAAECgcIBwABLAAECgcIFQAGAMAgAA==.Guthrum:BAAALAADCgYIBgAAAA==.',['Gä']='Gälicmoods:BAAALAAECgEIAQAAAA==.',['Gå']='Gål:BAABLAAECoEXAAMKAAgIdx8+BgDeAgAKAAgIdx8+BgDeAgALAAMIgQwqEwCmAAAAAA==.',['Gí']='Gíldarts:BAAALAADCggIEAAAAA==.',Ha='Hallypally:BAAALAADCggICAAAAA==.Hanasa:BAAALAAECgYIBwABLAAECgcIFQAGAMAgAA==.Hanna:BAAALAADCgMIAwAAAA==.',He='Heleneá:BAAALAADCggICAAAAA==.Henro:BAAALAAECgMIAwAAAA==.Hestia:BAAALAADCggICwAAAA==.',Hi='Himbeertoni:BAAALAADCggIFAAAAA==.',Ho='Hoernchen:BAAALAADCgcIBwAAAA==.Holyshiit:BAAALAAECgMIAwABLAAECgMIAwAEAAAAAA==.Homîecîde:BAAALAAECgYIDQAAAA==.Hornstars:BAABLAAECoEWAAIMAAgInSAzCgDxAgAMAAgInSAzCgDxAgAAAA==.Hotbaby:BAAALAAECgIIAwAAAA==.',['Hä']='Hädbängä:BAAALAADCggICAAAAA==.',Ic='Iceregen:BAAALAAECgYIBgAAAA==.',Ik='Ikamun:BAAALAAECgIIAwAAAA==.',In='Indria:BAAALAADCgEIAQAAAA==.Indydrakes:BAABLAAECoEXAAINAAgIOiN5AAAYAwANAAgIOiN5AAAYAwAAAA==.Indypalas:BAAALAADCgIIAgABLAAECggIFwANADojAA==.Inouske:BAAALAAECgIIAwAAAA==.Inside:BAAALAADCgEIAQABLAAECgMIBgAEAAAAAA==.Insidebeam:BAAALAAECgMIBgAAAA==.',Is='Isende:BAAALAADCggIIAAAAA==.',Ja='Jalari:BAAALAADCgcIBwAAAA==.',Ji='Jivos:BAAALAAECgMIBAAAAA==.',['Jé']='Jénná:BAAALAADCgYICQAAAA==.',Ka='Kadai:BAAALAAECgUIBgAAAA==.Kagari:BAAALAAECgMIAwAAAA==.Kakibabuu:BAAALAAECgcIDwAAAA==.Kaladum:BAAALAAECgYICgAAAA==.Kaluana:BAAALAADCgIIAgAAAA==.Karlheinrich:BAAALAADCgMIAwAAAA==.Karragos:BAABLAAECoEWAAIOAAgILCUvAQBdAwAOAAgILCUvAQBdAwAAAA==.Katuhl:BAAALAAECgIIAwAAAA==.',Ke='Keddana:BAAALAADCggICAAAAA==.Keji:BAAALAADCgcIBwABLAADCggICAAEAAAAAA==.',Ki='Kirah:BAAALAAECgIIAgAAAA==.Kirasha:BAAALAAECgIIAgAAAA==.Kiyomî:BAAALAAECgMIAwAAAA==.',Ko='Kokoro:BAAALAAECgMIAwAAAA==.Koyari:BAAALAADCggIFwABLAAECgMIAwAEAAAAAA==.',Kr='Krelli:BAAALAADCgcIEgAAAA==.Kromsgor:BAAALAADCgcICgAAAA==.',Ku='Kungpandia:BAAALAADCgcIBwAAAA==.',['Kê']='Kêddo:BAAALAAECgYIDwAAAA==.',['Kú']='Kúbítér:BAAALAAECgMIBAAAAA==.',La='Lakkal:BAAALAAECgEIAQAAAA==.Langdron:BAABLAAECoEWAAMPAAgIUxCqJQCuAQAPAAgIUxCqJQCuAQAQAAUIjhz2IwCiAQAAAA==.',Le='Leelement:BAAALAADCggICAAAAA==.Leshan:BAAALAADCgIIAgAAAA==.',Lh='Lhìz:BAABLAAECoEWAAIRAAgIiyDFCAABAwARAAgIiyDFCAABAwAAAA==.',Li='Lilìth:BAAALAADCgcIBwAAAA==.Lingerkiller:BAAALAAECgMIAwAAAA==.Linvala:BAAALAADCgYIBgAAAA==.Lisayah:BAAALAAECgQIBAAAAA==.',Lo='Lockyin:BAAALAAECgMIAwAAAA==.Loldarkylol:BAAALAAECggIEgAAAA==.Lonely:BAAALAAECgUIBQAAAA==.Lorisaniea:BAAALAADCggIEAABLAAECgcIEAAEAAAAAA==.Loux:BAABLAAECoEXAAMSAAgIjBVEFgDcAQASAAgIjBVEFgDcAQATAAQIfBQELwARAQAAAA==.',Lu='Lupisregina:BAAALAAECgMIBAAAAA==.',Ly='Lykari:BAAALAAECgYICQAAAA==.',['Lø']='Løkì:BAAALAAECgcIEQAAAA==.Løkï:BAAALAAECgYIBgAAAA==.',Ma='Maajida:BAAALAADCgYIBgAAAA==.Mabelle:BAAALAADCggIEAAAAA==.Maisie:BAAALAADCgQIBAABLAAECgMIAwAEAAAAAA==.Maisíê:BAAALAADCggIDwABLAAECgMIAwAEAAAAAA==.Maizie:BAAALAADCgYIBgABLAAECgMIAwAEAAAAAA==.Malltera:BAAALAADCgcIBwABLAAECgcIEAAEAAAAAA==.Mandrakor:BAAALAADCgcICgAAAA==.Manuels:BAAALAADCgcIBwAAAA==.Mardi:BAAALAADCgcIBwAAAA==.Marsh:BAAALAADCgQIAwAAAA==.Mausling:BAAALAAECgMIBgAAAA==.',Me='Meatshield:BAAALAAECgYIBgABLAAECggIDgAEAAAAAQ==.Medo:BAAALAADCgcIBwAAAA==.Medorah:BAAALAAECgQICgAAAA==.Medy:BAAALAAECgYIDQAAAA==.Melinda:BAAALAADCggICAAAAA==.Melnyna:BAAALAAECgcIDQAAAA==.Merlìn:BAAALAADCgcICQAAAA==.',Mo='Monddrache:BAAALAADCgYIBgABLAAECgMIBQAEAAAAAA==.Monktana:BAABLAAECoEXAAIUAAgI9iCtBQCpAgAUAAgI9iCtBQCpAgAAAA==.Mooniya:BAAALAAECgYIDAAAAA==.Morgenstern:BAAALAADCggICAAAAA==.Moyin:BAAALAADCgIIAgAAAA==.',My='Myrrima:BAAALAADCggIEAAAAA==.',['Mâ']='Mâizîe:BAAALAAECgMIAwAAAA==.Mâlrîôn:BAAALAAECgUICwAAAA==.',Na='Nagràch:BAAALAADCgcIBwAAAA==.Naishaa:BAAALAAECgIIAwAAAA==.Narila:BAAALAADCgcICgAAAA==.Naruko:BAAALAADCgcIBwAAAA==.Narulak:BAAALAADCgcIBwAAAA==.Narí:BAAALAAECgcIEAAAAA==.',Ne='Nerzyasan:BAAALAAECgMIBQAAAA==.Nevelle:BAAALAAECgYICgAAAA==.',Ni='Nightor:BAAALAAECgEIAgAAAA==.Nightro:BAAALAADCgMIAwAAAA==.Niriande:BAAALAAECgMIAwAAAA==.Niveà:BAAALAAECgYICAAAAA==.',No='Noirvoker:BAAALAAECgYIBgABLAAECgcIFQAGAMAgAA==.Nokrazul:BAAALAADCggICAABLAAECgMIBQAEAAAAAA==.Noorie:BAAALAAECgMIAwAAAA==.Nounoobie:BAAALAAECgMIBgAAAA==.',Nu='Nutsandbolts:BAABLAAECoEXAAIVAAgIshIOCgDcAQAVAAgIshIOCgDcAQAAAA==.',Nw='Nwave:BAAALAADCgYIBgAAAA==.',Ny='Nyxaria:BAAALAAECgIIAgAAAA==.',['Nâ']='Nâomi:BAAALAADCgMIAwAAAA==.',['Nó']='Nómin:BAAALAAECgIIAwAAAA==.',Ob='Obi:BAAALAAECgIIAgAAAA==.',Om='Ombra:BAAALAADCgMIAwAAAA==.',Or='Ore:BAAALAADCggIDAAAAA==.',Pa='Painster:BAAALAAECggIDgAAAQ==.Paldros:BAAALAADCggIDgABLAAECggIFwACAFghAA==.Panski:BAAALAADCgMIAwAAAA==.Papito:BAAALAAECgIIAgAAAA==.',Pe='Pectoralis:BAABLAAECoEXAAIWAAgI1yLvAwA5AwAWAAgI1yLvAwA5AwAAAA==.',Po='Polygnøm:BAAALAAECgQIBgAAAA==.',Pr='Praylan:BAAALAAECgEIAQAAAA==.Prryon:BAAALAAECgMIBQAAAA==.',Qn='Qny:BAAALAADCgEIAQAAAA==.',Qu='Qumaira:BAAALAAECgYICgAAAA==.Quzila:BAAALAAECgYICAABLAAECgcIFQAGAMAgAA==.',Ra='Rahu:BAAALAAECgMIAwAAAA==.Ransom:BAAALAADCgcIBwAAAA==.Razziel:BAAALAADCgcICwAAAA==.Razzila:BAAALAADCggICgAAAA==.',Re='Reaper:BAAALAAECgcICwAAAA==.Rejoy:BAAALAADCgUICAAAAA==.Renesme:BAAALAADCgcIBwAAAA==.Renlesh:BAAALAADCggICAAAAA==.Reznia:BAAALAAECgMIBQAAAA==.',Ro='Roguefish:BAAALAAECgIIAwAAAA==.Rotznás:BAAALAAECgIIAwAAAA==.',Ru='Rubîna:BAAALAADCgYICgAAAA==.Runar:BAAALAADCgQIBAAAAA==.',Ry='Rynn:BAAALAAECgMIAwAAAA==.',['Rö']='Rök:BAAALAAECgcIBwAAAA==.',Sa='Safina:BAAALAAECgYICgAAAA==.Sakura:BAAALAAECgIIAwAAAA==.Salu:BAEALAAECgcICwAAAA==.Sanku:BAAALAADCggIDAAAAA==.Sapiosa:BAAALAADCgYIDAABLAAECgcIFQAGAMAgAA==.Sapralot:BAAALAAECgIIAgAAAA==.Sareena:BAAALAAECgMIAwAAAA==.Sariff:BAAALAADCgcICwAAAA==.Sazuku:BAAALAADCgIIAwAAAA==.',Sc='Scharfkralle:BAAALAAECgcIDwAAAA==.Screas:BAAALAAECggIDgAAAA==.',Se='Selana:BAAALAADCgcIBwAAAA==.Seriana:BAAALAADCggIGgAAAA==.Serra:BAAALAADCgMIAwAAAA==.',Sh='Shamîra:BAAALAAECgcIEAAAAA==.Sheldox:BAAALAADCgEIAQAAAA==.Shikii:BAAALAAECgIIAwAAAA==.Shjo:BAAALAADCgcIBwABLAAECgYICQAEAAAAAA==.Shredders:BAAALAADCgcIBgAAAA==.Shùrýk:BAAALAAECgIIAgAAAA==.',Si='Siale:BAAALAAECgYIDQAAAA==.Silessa:BAAALAADCgEIAQAAAA==.Silverlol:BAAALAADCgcICgAAAA==.Simonp:BAAALAAECgEIAQAAAA==.',Sk='Skeppo:BAAALAADCgMIBQAAAA==.Skysha:BAAALAADCggIAQAAAA==.Skîbby:BAAALAAECgMIBAAAAA==.',Sn='Snair:BAAALAAECgcIEAAAAA==.',So='Sonne:BAAALAAECgIIAwAAAA==.Sophiya:BAAALAADCggIFAAAAA==.',St='Stupid:BAAALAAECgIIAwABLAAECgMIBgAEAAAAAA==.Störtebärker:BAAALAAECgMIBAAAAA==.',Su='Succthebus:BAAALAADCgYIBgAAAA==.',['Sâ']='Sâphirâa:BAAALAADCgEIAQAAAA==.Sâvírana:BAABLAAECoEUAAIRAAcIhh4tFwBZAgARAAcIhh4tFwBZAgAAAA==.',['Sä']='Säbeluschi:BAAALAAECgQIAwAAAA==.',Ta='Tabby:BAAALAADCggIFAAAAA==.Talisah:BAAALAAECgUICQAAAA==.',Te='Teal:BAAALAAECgMIBQAAAA==.Telenda:BAABLAAECoEVAAMGAAcIwCB3CwCgAgAGAAcIwCB3CwCgAgAXAAIICxUUEwCIAAAAAA==.',Th='Thanators:BAAALAADCgMIAwAAAA==.Thandoria:BAAALAAECgYIBgAAAA==.Tharodil:BAAALAADCgYIBgAAAA==.Tharok:BAAALAAECgMIAwAAAA==.Thorgeir:BAAALAADCgcIBwAAAA==.',Ti='Tilda:BAAALAAECgIIAgAAAA==.',Tj='Tjell:BAAALAADCgcIBwAAAA==.',To='Torador:BAAALAADCgcIBwAAAA==.',Tr='Trym:BAAALAADCgcIBwAAAA==.',Ty='Tyrianoor:BAAALAAECgMIBgAAAA==.',['Tá']='Táráh:BAAALAAECgIIAgAAAA==.',['Tí']='Tífa:BAAALAADCggICAAAAA==.',Ug='Uglyx:BAAALAADCgUIBQAAAA==.',Un='Underfire:BAAALAADCggIFgAAAA==.',Us='Uschy:BAAALAAECggIEgAAAA==.',Ve='Venommonk:BAAALAAECgMIAwAAAA==.',Vo='Volira:BAAALAAECgQIBQAAAA==.Vortéx:BAAALAADCgYIAQAAAA==.',Wa='Warhawk:BAAALAAECgMIAwAAAA==.',['Wí']='Wítchlord:BAAALAADCgIIAgAAAA==.',['Wü']='Würgen:BAAALAAECgIIAwAAAA==.',Xa='Xalathron:BAAALAADCgEIAgAAAA==.Xarfeigh:BAAALAAECgYIBgAAAA==.',Xo='Xoono:BAAALAADCgcIDAAAAA==.Xoran:BAAALAAECgcIEAAAAA==.',Xs='Xsara:BAAALAAECgEIAQAAAA==.',Xw='Xwd:BAABLAAECoEWAAICAAgI0yIaBQAsAwACAAgI0yIaBQAsAwAAAA==.',['Xâ']='Xââi:BAAALAADCgcICgAAAA==.',['Xé']='Xéron:BAAALAAECgcIEgAAAA==.',Yi='Yidhranos:BAABLAAECoEVAAMYAAgIIBSuCQC3AQAZAAgIKxM6GQAGAgAYAAcIVgquCQC3AQAAAA==.',Yl='Ylarah:BAABLAAECoEXAAIRAAgIHCGiCwDaAgARAAgIHCGiCwDaAgAAAA==.',Za='Zanto:BAAALAADCggIDwAAAA==.Zantropas:BAAALAAECgUIBwAAAA==.',Ze='Zephi:BAAALAAECgUIBQAAAA==.',Zu='Zugmaschinê:BAAALAAECgIIAwAAAA==.',['Ák']='Ákírá:BAAALAAECgMIAwAAAA==.',['Âr']='Ârgometh:BAAALAAECgMIAwAAAA==.Âryá:BAAALAAECgMIAwAAAA==.',['Ðe']='Ðestruction:BAAALAAECggIDAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end