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
 local lookup = {'Shaman-Enhancement','Unknown-Unknown','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','Warrior-Fury','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Paladin-Retribution',}; local provider = {region='EU',realm="Eldre'Thalas",name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Aciclovir:BAAALAADCgYICgAAAA==.',Ai='Aimepty:BAABLAAECoEWAAIBAAgIFRzSAgClAgABAAgIFRzSAgClAgAAAA==.',Al='Alaid:BAAALAADCgcIBwAAAA==.',Am='Amélianne:BAAALAAECgUIBQABLAAECggIDwACAAAAAA==.',An='Anarchicia:BAAALAADCgUIBQAAAA==.',Ar='Arbonne:BAAALAAECgUIBwAAAA==.Arcanæ:BAAALAADCgcICgAAAA==.Arsôr:BAABLAAECoEVAAMDAAgICBchCgAQAgADAAgICBchCgAQAgAEAAIIpwenKQBrAAAAAA==.Arä:BAAALAADCgUIBQAAAA==.',As='Ashama:BAABLAAECoEYAAIFAAgITSVSAQBqAwAFAAgITSVSAQBqAwAAAA==.Asharcane:BAAALAADCggIFgAAAA==.',Ay='Ayunécro:BAAALAADCgQIAwAAAA==.Ayusham:BAAALAAECgYICQAAAA==.',Az='Azariel:BAAALAADCgYIBgAAAA==.',Be='Bellaya:BAAALAADCgYIBgAAAA==.Betrayer:BAABLAAECoEcAAIGAAgIfB+MCADtAgAGAAgIfB+MCADtAgAAAA==.',Bi='Biinnii:BAAALAADCggICAAAAA==.',Bl='Blôom:BAAALAAECgUICAAAAA==.Blùe:BAAALAAECgUIDgAAAA==.',Bo='Bobmarleybob:BAAALAADCgYIBgAAAA==.Boldash:BAAALAAECgIIAgAAAA==.Boorg:BAAALAADCgcIBwABLAAECgMIBAACAAAAAA==.Boudiouu:BAAALAADCgYICwAAAA==.',Br='Brigesse:BAAALAADCgcICQAAAA==.',Bu='Buffware:BAAALAAECgEIAQAAAA==.Burnhyl:BAAALAAECgEIAQAAAA==.',Ce='Cerace:BAAALAAECgEIAQAAAA==.',Ch='Chamanow:BAAALAADCgYIBgAAAA==.Chouille:BAAALAADCgcIBwAAAA==.Chura:BAAALAADCgcIBwAAAA==.Chynezh:BAAALAADCgYIBgAAAA==.',Cl='Claydhunt:BAAALAAECggIBgAAAA==.Clinsunset:BAAALAAECgEIAQAAAA==.',Co='Courtepaille:BAAALAADCgYIBgABLAAECgcIEgACAAAAAA==.',Cp='Cptlameule:BAABLAAECoEWAAIEAAgIqiQMAQBXAwAEAAgIqiQMAQBXAwAAAA==.',Cx='Cxa:BAAALAAECgcIBwAAAA==.',['Cé']='Céluné:BAAALAADCgcIBwAAAA==.',Da='Darkzintos:BAAALAADCgMIAwAAAA==.Dash:BAAALAADCggICAAAAA==.',De='Demerys:BAAALAAECggIEgAAAA==.Derrieri:BAAALAADCggIAgAAAA==.',Di='Diora:BAAALAAECgEIAgAAAA==.',Do='Dolares:BAAALAAECgEIAgAAAA==.Doomyria:BAAALAADCgcIBwAAAA==.Doomyrium:BAAALAADCggICwAAAA==.',Dr='Dramaqween:BAAALAADCggICAAAAA==.Dreykare:BAAALAADCggIDgAAAA==.Drogdur:BAAALAAECgYIBgAAAA==.Drâx:BAAALAADCgIIAgAAAA==.',['Dè']='Dènna:BAAALAADCggICAAAAA==.',El='Elloco:BAAALAAECgYICgAAAA==.Elrandir:BAAALAAECgIIAgAAAA==.',En='Engy:BAAALAAFFAIIAgAAAA==.Enzt:BAAALAAECgYICQAAAA==.',Eo='Eolya:BAAALAADCgQIBAAAAA==.',Er='Eraddak:BAAALAAECgYICQAAAA==.',Es='Eslanas:BAAALAAECgYICgAAAA==.Espérentya:BAAALAAECgYIBgAAAA==.',Fa='Fakedownn:BAAALAAECgMIAwAAAA==.',Fr='Frïgg:BAAALAAECgMIBgAAAA==.',Ga='Gangrelune:BAAALAADCggICQAAAA==.',Gh='Ghostofnijz:BAAALAAECgQIBAAAAA==.',Go='Gogrren:BAAALAAECgYIDwAAAA==.',Gr='Gromak:BAAALAAECgMIBAAAAA==.Grosciflard:BAAALAAECgcIEgAAAA==.Groød:BAAALAAECgMIBAAAAA==.',Gu='Guldur:BAAALAADCggIDwAAAA==.',Gy='Gyn:BAAALAADCgcICwAAAA==.',Hi='Hinoki:BAAALAADCggICAAAAA==.Hitreck:BAAALAADCgYIBgAAAA==.',Ho='Holce:BAAALAADCgcIDQAAAA==.',Hr='Hrafn:BAAALAADCgcIBwAAAA==.',Hy='Hybridame:BAAALAAECgIIBgAAAA==.Hypnotus:BAAALAAECgIIAwAAAA==.',['Hé']='Héloise:BAAALAADCgcIBwAAAA==.',['Hô']='Hôka:BAAALAAECgYIDAAAAA==.',Ih='Ihaveatoto:BAAALAADCggICAAAAA==.',In='Inayra:BAAALAAECgcICgAAAA==.',Ir='Irïnna:BAAALAAECggIDwAAAA==.',Is='Isildur:BAAALAADCgcICQAAAA==.',Je='Jeanbôb:BAAALAAECgYIDwAAAA==.',Ju='Judge:BAAALAADCggIFgAAAA==.Julieo:BAAALAAECgIIAgAAAA==.',Ka='Kahzdin:BAAALAADCgIIAgAAAA==.Kallyne:BAAALAADCgcICwAAAA==.Kascendre:BAAALAAECgYICwAAAA==.',Ke='Kento:BAAALAAECggIEwAAAA==.Keytala:BAAALAADCggIFgAAAA==.',Ki='Killgorm:BAAALAAECgIIAgAAAA==.Kiss:BAAALAAECgMIBQAAAA==.',Ky='Kyn:BAAALAADCgYIBgAAAA==.',['Kä']='Kälahan:BAAALAADCgcICAAAAA==.Kärmä:BAAALAAECgYIBwAAAA==.',['Kø']='Køsh:BAAALAADCggICAAAAA==.',La='Lagherta:BAAALAAECgEIAQAAAA==.Lagosh:BAAALAADCgYIBgAAAA==.Lanthanide:BAAALAADCgYICgABLAAECgYIDQACAAAAAA==.Lapire:BAAALAAECggICAAAAA==.',Le='Leahkcim:BAAALAADCgQIBAAAAA==.Lee:BAAALAAFFAEIAQAAAA==.Legrosdingue:BAAALAAFFAIIAgAAAA==.',Li='Libox:BAAALAADCgcIBwAAAA==.Lilÿth:BAAALAADCggIEAABLAAECgcICAACAAAAAA==.Liø:BAAALAADCgYIBgAAAA==.',Lo='Lorible:BAAALAAECgMIBQAAAA==.Lormonus:BAAALAADCgcIDgAAAA==.',Lu='Lugan:BAAALAAECgYICgAAAA==.Lukywi:BAAALAAECgMIBAAAAA==.',Ly='Lyandris:BAAALAADCggICAAAAA==.',['Lî']='Lîlïth:BAAALAAECgYIBwAAAA==.',['Lï']='Lïlýth:BAAALAAECgcICAAAAA==.',Ma='Maektha:BAAALAAECgUIBgAAAA==.Magalouche:BAAALAADCgYIDAAAAA==.Magmaurgar:BAAALAADCgQIBAAAAA==.Malgreen:BAAALAADCgUIBQAAAA==.Malkith:BAAALAADCggIEgAAAA==.Mandogore:BAAALAADCggICAAAAA==.Marcya:BAAALAAECgcIEQAAAA==.Marihma:BAAALAAECgEIAgAAAA==.Maxibuse:BAAALAAECgYICQAAAA==.Mazlumollum:BAAALAADCggIFwAAAA==.',Me='Mendine:BAAALAADCggIFgAAAA==.',Mi='Mimps:BAAALAAECgIIAgAAAA==.Mindset:BAAALAADCggICAAAAA==.Minucia:BAAALAAECgIIAwAAAA==.Miyunee:BAAALAADCgcIBwABLAAECgUICAACAAAAAA==.',Mo='Mogoyï:BAAALAADCgQIBAAAAA==.Mortïfïa:BAAALAADCgcIBwAAAA==.',Mu='Muktananda:BAAALAADCggIDwAAAA==.Murky:BAAALAAECgQIBgAAAA==.',My='Myraluxe:BAAALAAECgEIAQAAAA==.',['Má']='Mátto:BAAALAADCggIEAAAAA==.',['Mé']='Mérione:BAAALAADCgcIDQAAAA==.',['Mí']='Míriël:BAAALAADCgIIAgAAAA==.',['Mø']='Mønarch:BAAALAAECgYICgAAAA==.',Na='Nallà:BAAALAADCgQIBAAAAA==.Nanaconda:BAAALAAECgUIBgAAAA==.Naois:BAAALAAECgcIEwAAAA==.Naollidan:BAAALAADCgIIAgAAAA==.Narcaman:BAAALAADCggIFAAAAA==.Narnya:BAAALAAECgEIAQAAAA==.Naryko:BAAALAAECgMIAwAAAA==.Navysk:BAAALAAECgYICgAAAA==.Nazoh:BAAALAADCgUIBQAAAA==.',Ne='Nebuka:BAAALAAECgMIAwAAAA==.Necrom:BAAALAAECgIIBAAAAA==.Necropal:BAAALAADCgYIBgAAAA==.Nerd:BAAALAADCggIDgAAAA==.Nerif:BAAALAAECgMIBQAAAA==.',Ni='Niedr:BAAALAADCggIFgAAAA==.Nimportki:BAAALAADCgcIBwAAAA==.',Nu='Nuroflemme:BAAALAAECgUICQAAAA==.',['Né']='Néfertiti:BAAALAADCggICAABLAAFFAEIAQACAAAAAA==.',Om='Oméga:BAAALAADCgcIBwAAAA==.',Op='Opyz:BAAALAAECgYIDQAAAA==.',Or='Ordalyon:BAAALAADCgYIBgAAAA==.Oreillesan:BAAALAADCggICAABLAAECgUIBgACAAAAAA==.',Ov='Ovidi:BAAALAAECgYICAABLAAECgMIAwACAAAAAA==.',Pa='Padrane:BAAALAAECgEIAQAAAA==.Palaone:BAAALAADCggIFAAAAA==.Pauleth:BAAALAAECgYIEAAAAA==.',Pe='Pearly:BAAALAADCgcIEgAAAA==.',Ph='Phasmixia:BAAALAADCggIFAAAAA==.Phàrah:BAAALAADCgMIAwAAAA==.',Pl='Plick:BAAALAADCgYIBgAAAA==.',Po='Polzo:BAAALAADCgcIBwAAAA==.Pouladine:BAAALAADCgcICgAAAA==.',Pr='Prukin:BAAALAADCggIDAAAAA==.',Pu='Pupuce:BAAALAAECgYIDwAAAA==.',Py='Pyctograhm:BAAALAAECgYIDgAAAA==.',['Pä']='Päprîka:BAAALAAECgEIAQAAAA==.',Rh='Rhazoul:BAAALAADCgUIBwAAAA==.Rhiamina:BAAALAAECgEIAQAAAA==.Rhëa:BAAALAADCgcICAAAAA==.',Ri='Riacko:BAAALAADCgcIBwAAAA==.Riksho:BAAALAAECgYICQAAAA==.',Ro='Royalz:BAAALAAECgMIBAAAAA==.',Se='Selurecham:BAEALAAECgYIBgABLAAECgYIDgACAAAAAA==.Selureevoc:BAEALAAECgYIDgAAAA==.Senheiser:BAAALAADCgcIBwAAAA==.Seriall:BAAALAAECgMIBAAAAA==.Seropaladeen:BAAALAADCgcIBwAAAA==.',Si='Sica:BAABLAAECoEVAAQHAAgIbiIAAQAuAwAHAAgIbiIAAQAuAwAIAAEIIQf6LQA/AAAJAAEIMRpBaAA7AAAAAA==.',Sk='Skarlx:BAAALAAECgcIDAAAAA==.Skillcapped:BAAALAADCgYIBwABLAAECgMIAwACAAAAAA==.Skörie:BAAALAAECgQIBQAAAA==.',So='Souras:BAAALAADCgYIBgAAAA==.',Sp='Spartatouil:BAAALAADCgcIBwAAAA==.Spartiatte:BAAALAADCgYIBgAAAA==.',St='Stuppflipp:BAAALAADCgUICgAAAA==.Støya:BAAALAADCggICAAAAA==.',Sw='Swieits:BAAALAADCggICAAAAA==.Swørk:BAAALAADCgcIBwAAAA==.',Sy='Syphilis:BAAALAAECgMIBQAAAA==.',['Sà']='Sàckäpùçe:BAAALAAECgYIEQAAAA==.',Ta='Talix:BAAALAAECgMIBQAAAA==.Tamales:BAAALAADCggICwAAAA==.Tarkol:BAAALAADCgYIBgAAAA==.Tazzmania:BAAALAADCgYIDAAAAA==.',Te='Terrestre:BAAALAADCggICAAAAA==.',Th='Therèse:BAAALAAECgYIBgAAAA==.Thorgrama:BAAALAAECgIIBAAAAA==.Thorgrïm:BAAALAADCggICAAAAA==.',To='Totémique:BAAALAAECgYICgAAAA==.',Tu='Tupperware:BAAALAADCgcIBwAAAA==.',Ty='Tygacil:BAAALAAECgMIAwAAAA==.',['Tä']='Tärâ:BAAALAADCgcIBgAAAA==.',['Tÿ']='Tÿphâ:BAAALAADCgUIBQAAAA==.',Uh='Uha:BAAALAAECgMIBQAAAA==.',Un='Underd:BAAALAADCggIFgAAAA==.',Ut='Uthred:BAAALAADCgcIBwAAAA==.',Va='Vanie:BAAALAAECgQIBgAAAA==.Varaldor:BAACLAAFFIEGAAIKAAQIIhuHAACHAQAKAAQIIhuHAACHAQAsAAQKgRQAAgoACAidJk8AAJoDAAoACAidJk8AAJoDAAAA.Varthnir:BAAALAADCgcIDgAAAA==.',Ve='Velletrax:BAAALAADCggICQAAAA==.Veshkär:BAAALAADCgYIEgAAAA==.',Vo='Vorath:BAAALAAECgcICgAAAA==.',Wa='Warzam:BAAALAADCggICAAAAA==.Wazoo:BAAALAADCggIFwAAAA==.',Wo='Woknroll:BAAALAADCggICAAAAA==.',Xe='Xenium:BAAALAADCggICQAAAA==.Xetrøn:BAAALAAECgEIAQAAAA==.',Ya='Yaminge:BAAALAADCgIIAgAAAA==.',Yg='Ygethmor:BAAALAAECgYIDQAAAA==.',Yl='Ylva:BAAALAADCggIFwAAAA==.',Yo='Yopinette:BAAALAADCgUIBQAAAA==.',Ys='Ysphae:BAAALAAECgcIDgAAAA==.',Yu='Yudem:BAAALAADCggICAAAAA==.Yukki:BAAALAAECgQIBwAAAA==.',Za='Zagzor:BAAALAAECgcICwAAAA==.Zariah:BAAALAAECgEIAgAAAA==.Zatø:BAAALAADCgYIBgAAAA==.',Ze='Zeretor:BAAALAADCggIDAAAAA==.',Zh='Zherenyt:BAAALAAECgYIBgABLAAECgYIDQACAAAAAA==.Zheretyn:BAAALAAECgYIDQAAAA==.',Zo='Zolyna:BAAALAADCggIFQAAAA==.Zorgash:BAAALAAECgYICQAAAA==.',['Zà']='Zàm:BAAALAAECgYIDgAAAA==.',['Zö']='Zögzog:BAAALAAECgIIAgAAAA==.Zögzög:BAAALAADCgIIAgABLAAECgIIAgACAAAAAA==.',['Ár']='Árgo:BAAALAADCggIDQAAAA==.',['Är']='Ärgö:BAAALAADCgIIAgAAAA==.',['Ër']='Ërzäâ:BAAALAADCgcIBwAAAA==.',['Ïk']='Ïkers:BAAALAADCgEIAQAAAA==.',['Üf']='Üftack:BAAALAADCgcICAAAAA==.',['ßa']='ßahazen:BAAALAAECgQIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end