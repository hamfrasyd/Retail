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
 local lookup = {'Unknown-Unknown',}; local provider = {region='EU',realm='Minahonda',name='EU',type='weekly',zone=44,date='2025-08-31',data={Aa='Aagamer:BAAALAADCgMIAgAAAA==.',Ab='Abigor:BAAALAADCgYIBQAAAA==.',Ac='Acehood:BAAALAADCggIDgAAAA==.',Ad='Adrarc:BAAALAAECgEIAQAAAA==.Adrianlegaz:BAAALAADCggIFAAAAA==.',Ae='Aediel:BAAALAADCgQIBAAAAA==.Aetha:BAAALAADCggICwAAAA==.',Af='Aftereffects:BAAALAADCgcIBwAAAA==.',Al='Alakazim:BAAALAAECgMIBQAAAA==.Alcatraz:BAAALAADCgIIAgAAAA==.Alexor:BAAALAAECgQIBAAAAA==.Alì:BAAALAADCggIFwAAAA==.',Am='Amulg:BAAALAADCgcIFQAAAA==.',Ap='Apechusques:BAAALAADCgUICgAAAA==.',Ar='Arcanita:BAAALAADCgYICAABLAADCgcIBwABAAAAAA==.Arcenfren:BAAALAAECgYICAAAAA==.Armostrazon:BAAALAAECgEIAQAAAA==.Arrowgirl:BAAALAADCgMIAwAAAA==.Arthalgor:BAAALAAECgMIAwAAAA==.',As='Ascenom:BAAALAADCgUIBgAAAA==.',Au='Aura:BAAALAADCgcIBwAAAA==.',Av='Avernus:BAAALAAECgYIBgAAAA==.',Ba='Badbunni:BAAALAADCgcIEAAAAA==.Barrilete:BAAALAADCgEIAQAAAA==.Bashara:BAAALAADCggICAAAAA==.',Be='Bernkastel:BAAALAADCggIDwABLAADCggIDwABAAAAAA==.',Bl='Blinja:BAAALAADCgcIBwABLAAECgEIAQABAAAAAA==.',Br='Brulee:BAAALAAECgEIAQAAAA==.',['Bú']='Búdspencer:BAAALAADCggIDwAAAA==.Búrbuja:BAAALAADCggIDwAAAA==.',Ca='Calpizar:BAAALAADCgcIBwAAAA==.Caminallum:BAAALAAECgYIBgAAAA==.Carnatum:BAAALAAECgIIAgAAAA==.',Ch='Chamitoo:BAAALAADCgYIBgAAAA==.Cherath:BAAALAADCgIIAgAAAA==.Cherroky:BAAALAADCgYIBgAAAA==.Chesterwin:BAAALAAECgEIAQAAAA==.Chimbiri:BAAALAAECgIIBAAAAA==.Chüsina:BAAALAADCggIEAAAAA==.',Cl='Clair:BAAALAADCgcIBwABLAADCggIDwABAAAAAA==.Cluck:BAAALAAECgcIDgAAAA==.',Cr='Crujiento:BAAALAADCgYIDAAAAA==.',['Cä']='Cäl:BAAALAADCggIEAAAAA==.',Da='Daddymilker:BAAALAAECgMIBgAAAA==.Damamuerte:BAAALAADCgMIAwAAAA==.Damaoscuraa:BAAALAAECgEIAQAAAA==.Danasgul:BAAALAADCgcICwAAAA==.Darkdwarf:BAAALAAECgEIAgAAAA==.Darkdwarfx:BAAALAADCgQIBAAAAA==.Darkphoenix:BAAALAAECgYICQAAAA==.Darktora:BAAALAADCgIIAgAAAA==.',De='Deathmasc:BAAALAADCggICAAAAA==.Demonyalo:BAAALAAECgcICgAAAA==.',Dg='Dguts:BAAALAAECgMIAwAAAA==.',Dh='Dharkhonn:BAAALAADCggICQAAAA==.',Di='Diriom:BAAALAAECgMIBQAAAA==.',Dk='Dkhuerso:BAAALAADCggIGAAAAA==.',Dr='Dracarhys:BAAALAAECgcIEQAAAA==.Draconath:BAAALAAECgEIAQAAAA==.Dragon:BAAALAAECgcIDQAAAA==.Drakariel:BAAALAAECgIIBAAAAA==.Drawnir:BAAALAAECgYIBgAAAA==.Drákenden:BAAALAAECgQICAAAAA==.',Du='Dukira:BAAALAADCgEIAQAAAA==.Duquesi:BAAALAADCgIIBAAAAA==.',Ed='Edros:BAAALAADCgIIAgAAAA==.',Ei='Eiguer:BAAALAADCggICQAAAA==.',El='Elderon:BAAALAAECgYICAAAAA==.Eldtara:BAAALAAECgEIAQAAAA==.Electrø:BAAALAADCgcIBwAAAA==.Elisacutberg:BAAALAAECgYIDwAAAA==.',En='Enoc:BAAALAAECgYICAAAAA==.',Es='Esquizo:BAAALAADCgcIBwABLAAECgQICAABAAAAAA==.Estronko:BAAALAADCgYIBgABLAAECggIEgABAAAAAA==.',Et='Etreumut:BAAALAAECgEIAQAAAA==.',Eu='Eustodia:BAAALAADCgIIAgAAAA==.',Ev='Everglide:BAAALAADCgcICAAAAA==.',Ex='Exoodos:BAAALAADCgEIAQAAAA==.',['Eô']='Eôwïn:BAAALAADCggIDAAAAA==.',Fa='Falkkor:BAAALAAECgEIAQAAAA==.Faloscuro:BAAALAADCggIDQAAAA==.Falufractum:BAAALAADCggIDwAAAA==.',Fi='Filpos:BAAALAADCgYIDAAAAA==.',Fl='Flakita:BAAALAADCggICAAAAA==.Flamongo:BAAALAAECgQIBwAAAA==.',Fo='Fonti:BAAALAADCgYICwAAAA==.',Fr='Frônt:BAAALAADCggICAAAAA==.',Ga='Galactus:BAAALAADCgUIBQAAAA==.Galafa:BAAALAAECgMIBwAAAA==.',Ge='Genesi:BAAALAADCggIDgAAAA==.Gesserit:BAAALAAECgEIAQAAAA==.',Gh='Ghuleh:BAAALAADCggIDwAAAA==.',Gi='Gilvard:BAAALAAECgEIAQAAAA==.Gipsydavy:BAAALAAECgQICAAAAA==.Gipsydávid:BAAALAADCgMIAgAAAA==.Gisselle:BAAALAADCgQIAwAAAA==.',Gl='Glavin:BAAALAADCgMIAwAAAA==.',Gn='Gnaru:BAAALAAECgMIBgAAAA==.',Go='Gorkcroth:BAAALAADCgYIBwAAAA==.Gotga:BAAALAAECgQICAAAAA==.',Gr='Grelos:BAAALAAECgQICAAAAA==.Gremmori:BAAALAAECggIAQAAAA==.Griffithxiv:BAAALAADCgEIAQAAAA==.Gromgar:BAAALAAECgIIAwAAAA==.',Gw='Gwenella:BAAALAADCggICQAAAA==.',['Gö']='Gödzila:BAAALAADCgcIBwAAAA==.',Ha='Hakethemeto:BAAALAAECgYIDQAAAA==.Hayaax:BAAALAADCgcICwAAAA==.Hayaxz:BAAALAADCgQIBwAAAA==.',He='Hechi:BAAALAADCgQIAgAAAA==.Hectorlkm:BAAALAADCgQIBAAAAA==.Helenitsette:BAAALAAECggIBgAAAA==.',Ho='Hockney:BAAALAADCggIDwAAAA==.',Hy='Hydropaw:BAAALAAECgMIBgAAAA==.',In='Infeliz:BAAALAADCgUIBgAAAA==.',Ix='Ixchelia:BAAALAAECgYICwAAAA==.',Ja='Jadon:BAAALAAFFAIIAgAAAA==.',Jo='Joseleitor:BAAALAAECgEIAQAAAA==.',Ju='Juanchope:BAAALAADCgUIBQAAAA==.Juank:BAAALAAECgMIBgAAAA==.',['Jü']='Jülk:BAAALAADCgYIBgAAAA==.',Ka='Kaedelolz:BAAALAADCgMIAwAAAA==.Kaissa:BAAALAADCgIIAgAAAA==.Kana:BAAALAADCgUIBgAAAA==.Karionat:BAAALAAECgMIAQAAAA==.Kazbo:BAAALAADCgUIBQAAAA==.',Ke='Keikø:BAAALAAECgMIAwAAAA==.Kerveroos:BAAALAADCgQIBAAAAA==.',Kh='Kharmä:BAAALAADCgQIBAAAAA==.Khasstier:BAAALAADCgMIAwAAAA==.Khiana:BAAALAADCgcICwAAAA==.Khorner:BAAALAADCggIEAAAAA==.',Ki='Kiilldemon:BAAALAAECgEIAQAAAA==.Kimära:BAAALAAECgUICAAAAA==.',Ko='Konamy:BAAALAAECgYIDwAAAA==.Konnita:BAAALAADCgQIBAAAAA==.',Kr='Krampus:BAAALAADCgEIAQAAAA==.',['Kí']='Kírsi:BAAALAAECgMIAwAAAA==.',La='Lacurona:BAAALAADCgYIBgAAAA==.Lagartîja:BAAALAADCgQIBAAAAA==.Laurye:BAAALAAECgMIBgAAAA==.Layloft:BAAALAADCgYIBgAAAA==.',Le='Lechucico:BAAALAADCggIEQAAAA==.Legaedon:BAAALAAECgYIDAAAAA==.Leuwone:BAAALAAECgMIAwAAAA==.',Li='Liatris:BAAALAAECgMIBAAAAA==.Lilparka:BAAALAADCgUIBQAAAA==.Limboch:BAAALAADCgUIBQAAAA==.Limongordo:BAAALAADCgcIBwAAAA==.Limonobeso:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.Litrix:BAAALAAECgIIAwAAAA==.',Ll='Lluvîa:BAAALAADCggICwAAAA==.',Lm='Lmans:BAAALAADCgIIAgAAAA==.',Lu='Luffamer:BAAALAAECgcIDgAAAA==.Lugami:BAAALAADCgcICwAAAA==.Lulisha:BAAALAADCgcIBwABLAAECgYIDQABAAAAAA==.Lunsi:BAAALAADCggICwAAAA==.Lunsy:BAAALAAECgMIBAAAAA==.Luppo:BAAALAADCggICAAAAA==.Luxuri:BAAALAADCgcIDAAAAA==.',Lx='Lxk:BAAALAADCgYIDAAAAA==.',Ma='Maataas:BAAALAAECgMIAwAAAA==.Macondo:BAAALAADCggIGwAAAA==.Madamers:BAAALAADCggIEwAAAA==.Maekary:BAAALAADCgQIBAAAAA==.Magickash:BAAALAADCgMIAwAAAA==.Maius:BAAALAADCgYIDAAAAA==.Martica:BAAALAADCgUIBgAAAA==.Maxdeadlord:BAAALAADCggIEQAAAA==.',Me='Mechabello:BAAALAAECgEIAQAAAA==.Melmet:BAAALAAECggICAAAAA==.Memlaks:BAAALAAECgYIBgAAAA==.Mennón:BAAALAAECgEIAQAAAA==.Meshoj:BAAALAAECgcIDwAAAA==.',Mi='Midrake:BAAALAAECgQIBgAAAA==.Mimiko:BAAALAAECgMIBAAAAA==.Minifalo:BAAALAAECgQIBAAAAA==.Mithas:BAAALAADCgYIDAAAAA==.',Mo='Mochi:BAAALAADCgcIBwAAAA==.Mogaro:BAAALAADCgUIBQAAAA==.Moogur:BAAALAADCgUICAAAAA==.Morgans:BAAALAAECgUICgAAAA==.Mowglí:BAAALAADCgUIBQAAAA==.',['Mä']='Mäxdeadlord:BAAALAADCggICwAAAA==.',Na='Naomicampbel:BAAALAADCggICwAAAA==.Naral:BAAALAADCggICAAAAA==.',Ne='Nefiire:BAAALAADCgYIDAAAAA==.Nely:BAAALAADCgIIAgAAAA==.Nessalia:BAAALAADCgQIBAAAAA==.Newydd:BAAALAADCgcIBwAAAA==.',Ni='Nigrodian:BAAALAADCgcICQAAAA==.Nilea:BAAALAAECgYIDAAAAA==.Ninfaev:BAAALAADCgIIAgAAAA==.Niue:BAAALAAECgYIDQAAAA==.',No='Nochebuena:BAAALAADCgYIBgAAAA==.Noraah:BAAALAADCgYIBgAAAA==.Noå:BAAALAADCgcIBwAAAA==.',Oh='Ohmycát:BAAALAADCgcIBwAAAA==.',On='Onawha:BAAALAADCgEIAQABLAADCgcIBwABAAAAAA==.',Pa='Paladió:BAAALAAECgIIAgAAAA==.Papawelo:BAAALAADCgIIAgAAAA==.',Pe='Pecu:BAAALAAECgMIAwAAAA==.Pepemoncho:BAAALAADCgIIAgAAAA==.Pepinilloo:BAAALAAECgMIAwAAAA==.',Pk='Pkearcher:BAAALAAECgYIDwAAAA==.Pkepala:BAAALAAECgMIAwAAAA==.',Po='Polcar:BAAALAAECgUIBQAAAA==.',Pp='Ppïm:BAAALAADCgUIBQAAAA==.',Pu='Puzzle:BAAALAADCggIBwAAAA==.',Qi='Qiare:BAAALAADCgcIBwAAAA==.',Qu='Quin:BAAALAAECgcIEQAAAA==.',Qw='Qweeck:BAAALAAECgYIDAAAAA==.',Ra='Raaeghal:BAAALAADCggIDwAAAA==.Radahn:BAAALAADCgYIBgAAAA==.Raikuh:BAAALAADCgYIDAAAAA==.Raistlìn:BAAALAAECgIIBAAAAA==.Raitlinn:BAAALAADCgQIAQAAAA==.Ramala:BAAALAADCggICgAAAA==.Randirla:BAAALAADCgIIAQAAAA==.Rarnarg:BAAALAADCgYICgAAAA==.',Re='Redflag:BAAALAAECgMIBgAAAA==.Retraa:BAAALAADCgQIBQAAAA==.Revientalmas:BAAALAADCgUICAAAAA==.',Rh='Rhelar:BAAALAAECgYIDgAAAA==.Rhukah:BAAALAADCggICAAAAA==.',Ro='Rontal:BAAALAADCgcIBwAAAA==.Roostrife:BAAALAAECgEIAQAAAA==.',Ru='Runas:BAAALAAECgMIBAAAAA==.',Ry='Ryø:BAAALAADCgcIBwAAAA==.',['Rô']='Rôxy:BAAALAAECgEIAQAAAA==.',Sa='Saauron:BAAALAADCggIFgAAAA==.Sadoom:BAAALAAECgMIBQAAAA==.Sarâh:BAAALAADCgIIAgAAAA==.',Se='Seiuro:BAAALAADCgIIAgAAAA==.Sekki:BAAALAADCgcIBwAAAA==.Seldoria:BAAALAAECgYICQAAAA==.Selenebreath:BAAALAADCgEIAQAAAA==.Sercomart:BAAALAADCgQIBgAAAA==.Serenix:BAAALAADCgYIBgAAAA==.Serify:BAAALAADCgYICgAAAA==.Severuxx:BAAALAADCgcIBwAAAA==.Seycan:BAAALAADCggIDgAAAA==.Seznax:BAAALAADCgcICAAAAA==.',Sh='Shadowstar:BAAALAAECgcIEgAAAA==.Shads:BAAALAAECgQIBAAAAA==.Shamael:BAAALAADCgIIAgAAAA==.Shamalia:BAAALAADCgcICAAAAA==.Shanndo:BAAALAADCgUIBQAAAA==.Shinon:BAAALAAECgYICgAAAA==.Shogunneko:BAAALAAECgMIBAAAAA==.Shánks:BAAALAADCgYIBgAAAA==.',Si='Silwex:BAAALAAECgMIBgAAAA==.',Sk='Skartus:BAAALAAECggIEAAAAA==.',Sn='Snim:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.',So='Socerdotta:BAAALAAECgYIBgAAAA==.Sonne:BAAALAADCggICQAAAA==.',Sp='Spt:BAAALAADCgUIBQAAAA==.',Su='Suguuru:BAAALAAECgMIAwAAAA==.Sunder:BAAALAAECgYIDQAAAA==.Surelya:BAAALAADCgcIBwAAAA==.',Sy='Sylvänas:BAAALAADCgYIBgAAAA==.Syraax:BAAALAADCgcIBwAAAA==.',Ta='Tadín:BAAALAAECgMIAwAAAA==.Tamahome:BAAALAAECgQIBAAAAA==.Tarkoth:BAAALAAECgMIBAAAAA==.',Te='Tejeleo:BAAALAADCgcICAAAAA==.Teskachami:BAAALAAECgUIBQAAAA==.',Th='Thejosema:BAAALAADCgIIAgAAAA==.Thelriza:BAAALAAECgQIBAAAAA==.Théodred:BAAALAAECgUICAAAAA==.',Ti='Tiodelamaza:BAAALAADCgQIBAAAAA==.',To='Tottenwolf:BAAALAADCgcIBwAAAA==.',Tr='Tráckfol:BAAALAAECgIIAwAAAA==.',Tu='Turmi:BAAALAADCgIIAgAAAA==.',Ty='Tyrondalia:BAAALAAECgYICQAAAA==.',Tz='Tzarkos:BAAALAADCgMIAwAAAA==.',Ur='Urthas:BAAALAADCgEIAQAAAA==.',Us='Ushiø:BAAALAADCggIDAAAAA==.',Va='Vaiu:BAAALAAECgMIBgAAAA==.',Ve='Vello:BAAALAADCgIIAgAAAA==.Verysa:BAAALAAECgUIBQAAAA==.',Vh='Vhaldemar:BAAALAADCgcIDgAAAA==.Vhenom:BAAALAADCggIDQAAAA==.',Vi='Vikram:BAAALAADCggIEAAAAA==.Villanaa:BAAALAADCgYIBgAAAA==.',Vm='Vml:BAAALAADCgQIBAAAAA==.',We='Webofrito:BAAALAADCgEIAQAAAA==.Weizer:BAAALAADCgYIBgAAAA==.Welfi:BAAALAADCgcIDQAAAA==.Welolock:BAAALAADCgYICgAAAA==.Welvor:BAAALAADCgIIBAAAAA==.',Wh='Whatsername:BAAALAADCgIIAgAAAA==.Whiteligth:BAAALAADCggICAAAAA==.Whololook:BAAALAADCggIEwAAAA==.',Wi='Winola:BAAALAAECgYICQAAAA==.',Wt='Wthrgeralt:BAAALAAECgEIAQAAAA==.',Xh='Xhilaxh:BAAALAADCgMIAwAAAA==.',Xi='Xiaoyu:BAAALAAECgQICAAAAA==.Ximixurry:BAAALAAECgYIDQAAAA==.Xireth:BAAALAAECgUIBQAAAA==.',Ya='Yalamagic:BAAALAADCgUICAABLAAECgcICgABAAAAAA==.Yalohm:BAAALAAECgYIAwABLAAECgcICgABAAAAAA==.Yarrik:BAAALAADCgEIAQAAAA==.',Yi='Yiazmat:BAAALAADCggICAAAAA==.',Yo='Yohdise:BAAALAAECgcIDwAAAA==.',Yu='Yuiznita:BAAALAAECgIIAgAAAA==.Yunaka:BAAALAADCggIDAAAAA==.',Za='Zakaria:BAAALAADCgcIBwAAAA==.Zakwd:BAAALAAECgIIAgAAAA==.Zalek:BAAALAADCgcICgAAAA==.Zapétrel:BAAALAADCgMIAwAAAA==.Zarguk:BAAALAAECgMIAgAAAA==.',Zi='Zif:BAAALAADCggICAAAAA==.',Zu='Zum:BAAALAAECgMIAwAAAA==.',['Ál']='Álicai:BAAALAADCggIFAAAAA==.',['Áz']='Ázazél:BAAALAADCgcIBwAAAA==.',['Æñ']='Æñ:BAAALAAECgYIDAAAAA==.',['Ðe']='Ðersuuzala:BAAALAAECgYIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end