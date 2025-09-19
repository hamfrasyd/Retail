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
 local lookup = {'Unknown-Unknown','Warlock-Demonology',}; local provider = {region='EU',realm='ColinasPardas',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ac='Acratim:BAAALAAECgcIEAABLAAECgcIEQABAAAAAA==.',Ak='Akima:BAAALAADCgcICQAAAA==.Akumáa:BAAALAADCggICQAAAA==.',Al='Alahoguera:BAAALAAECgIIAwAAAA==.Aldienar:BAAALAADCgUIBQAAAA==.Alexut:BAAALAADCgcIBwAAAA==.Alykr:BAAALAADCgMIBAAAAA==.',Am='Amatoma:BAAALAAECgEIAQAAAA==.',An='Angrod:BAAALAADCgUIBAABLAAECgMIBQABAAAAAA==.Aniqilador:BAAALAAECgEIAQAAAA==.Annàbelle:BAAALAAECgMIBgAAAA==.',Ar='Arcal:BAAALAADCggIDwAAAA==.Arienai:BAAALAAECgMIAwAAAA==.Arrgus:BAAALAAECgMIBgAAAA==.',As='Asmodeo:BAAALAAECgYIDgAAAA==.',At='Ataräh:BAAALAAECgIIAwAAAA==.Athemens:BAAALAAECgcIDQAAAA==.Athenas:BAAALAAECgIIAgAAAA==.',Au='Aurembiaix:BAAALAADCgUIBQAAAA==.',Ax='Axelrod:BAAALAADCggICAAAAA==.',Az='Azräel:BAAALAAECgEIAQAAAA==.',Ba='Bagdemagus:BAAALAAECgMIBAAAAA==.',Be='Beastserk:BAAALAAECgEIAQAAAA==.Beca:BAAALAAECgUICAAAAA==.Belcebúh:BAAALAAECgEIAQAAAA==.',Bl='Blackamy:BAAALAAECgYIDAAAAA==.Bleedslolz:BAAALAAECgIIAgAAAA==.Bloodj:BAAALAADCgUIBQAAAA==.',Bn='Bnty:BAAALAADCgMIAwAAAA==.',Br='Brits:BAAALAADCgQIBAAAAA==.Brolur:BAAALAADCgMIAwAAAA==.Brunore:BAAALAADCgcIBwAAAA==.',['Bö']='Böss:BAAALAADCggIDgAAAA==.',Ca='Camuflaged:BAAALAADCgcIDAAAAA==.Cannaliator:BAAALAAECgEIAQAAAA==.Capadorr:BAAALAAECgEIAQAAAA==.Cartafilo:BAAALAAECgEIAQABLAAECgcIDgABAAAAAA==.',Ch='Chamakö:BAAALAAECgIIBAAAAA==.Chamiblu:BAAALAADCggICAAAAA==.',Ci='Cidzelgadis:BAAALAAECgYIDAAAAA==.',Co='Corpetit:BAAALAAECgIIAgAAAA==.Corvinus:BAAALAADCgYIBwAAAA==.',Cr='Cranne:BAAALAADCgYIAgAAAA==.Croquetón:BAAALAADCgQIBwAAAA==.',Da='Dainø:BAAALAADCgcIBwAAAA==.Dalinnar:BAAALAAECgMIBQAAAA==.Dardu:BAAALAADCgQIBAAAAA==.Darkium:BAAALAADCgYICQAAAA==.Daynø:BAAALAAECggICAAAAA==.',De='Demonlucy:BAAALAAECgcIDgAAAA==.Demontrunyk:BAAALAADCggIEAAAAA==.',Do='Dohna:BAAALAAECgEIAQAAAA==.Dosiq:BAAALAAECgEIAQAAAA==.',Dr='Drackprox:BAAALAAECgIIAgAAAA==.Drakinio:BAAALAAECgEIAQAAAA==.Drakten:BAAALAADCgcIDAAAAA==.Draugth:BAAALAAECgEIAQAAAA==.Drenna:BAAALAAECgIIAwAAAA==.Dryadark:BAAALAADCgYICQAAAA==.',Dt='Dtamo:BAAALAADCggICAAAAA==.',Du='Duentay:BAAALAAECgEIAQAAAA==.',['Dö']='Dönald:BAAALAAECgYICgAAAA==.',El='Elconfinao:BAAALAAECgYIDQAAAA==.Elmastarugo:BAAALAAECgMIAwAAAA==.Elyscee:BAAALAADCgIIAgAAAA==.',En='Enfermiza:BAAALAADCggIDAAAAA==.Engel:BAAALAAECgEIAQAAAA==.',Es='Eslak:BAAALAADCgcICwAAAA==.',Fi='Fievo:BAAALAADCgEIAQAAAA==.',Fl='Flakii:BAAALAADCgIIAgAAAA==.Flickzy:BAAALAADCgUIAgAAAA==.Flï:BAAALAADCgMIAwAAAA==.',Fo='Foresta:BAAALAAECgMIBQAAAA==.Foscuro:BAAALAADCggICAAAAA==.',Fr='Frangar:BAAALAAECgYICgAAAA==.',Fu='Furrymuffin:BAAALAADCgQIBAAAAA==.',Fy='Fylox:BAAALAADCggICAAAAA==.',Ge='Gelato:BAAALAAECgMIBAAAAA==.',Gn='Gnl:BAAALAAECgIIAgAAAA==.',Go='Goliath:BAAALAADCgcIBwAAAA==.Gorul:BAAALAAECgIIAwAAAA==.',Gr='Grimana:BAAALAADCgcIBwAAAA==.Gromash:BAAALAADCgUIBwAAAA==.',Gs='Gsus:BAAALAADCgUIBgAAAA==.',Gu='Gunforce:BAAALAADCggICAABLAADCggICAABAAAAAA==.',Ha='Hazarku:BAAALAAECgMIBAAAAA==.',Ho='Horrorvacui:BAAALAAECgYIBgAAAA==.Howkeye:BAAALAADCgYICAABLAADCgYICwABAAAAAA==.',Hy='Hydrax:BAAALAADCgcIBwAAAA==.',Id='Idone:BAAALAAECgUICQAAAA==.',Il='Ilidani:BAAALAAECgEIAQAAAA==.',Is='Isíldur:BAAALAADCgMIAwAAAA==.',Ja='Javiventas:BAAALAADCggICQAAAA==.',Jo='Johanwar:BAAALAAECgYICwAAAA==.Joseagui:BAAALAADCgcIDQAAAA==.',Ju='Juanmator:BAAALAADCgYIBAAAAA==.',Ka='Kamisamma:BAAALAADCgcICAAAAA==.Karman:BAAALAADCgUIBQAAAA==.',Ke='Kefren:BAAALAAECgMIBgAAAA==.',Kh='Khalios:BAAALAADCgMIAwAAAA==.',Ki='Kirades:BAAALAAECgYIDQAAAA==.',Km='Kmilian:BAAALAAECgMIBgAAAA==.',Ko='Kokil:BAAALAAECgEIAQABLAAECgcIEQABAAAAAA==.Kowek:BAAALAADCgcIBwAAAA==.',Kr='Kraid:BAAALAADCgUICAAAAA==.',Ky='Kynne:BAAALAADCgcICQAAAA==.Kyrays:BAAALAADCgYIBgAAAA==.',La='Laghertha:BAAALAAECgMIBgAAAA==.Lambohuracán:BAAALAADCgMIAwAAAA==.',Le='Legola:BAAALAADCggIEAAAAA==.Leviosa:BAAALAADCgIIAgAAAA==.',Li='Licán:BAAALAADCgQIBAAAAA==.',Lo='Lorzitas:BAAALAADCgYIBgAAAA==.',Lu='Luciaann:BAAALAADCggICAAAAA==.Lunastra:BAAALAADCgcIDAAAAA==.Lupopala:BAAALAAECgUIBgAAAA==.',Ly='Lyrïana:BAAALAADCgMIAwAAAA==.',['Lì']='Lìllìth:BAAALAADCgQIAwAAAA==.',['Lï']='Lïrath:BAAALAADCgUIBgAAAA==.',Ma='Malaki:BAAALAAECgMIBgAAAA==.Maldar:BAAALAADCggICAAAAA==.Malosobueno:BAAALAADCgUIBQAAAA==.Mangetsu:BAAALAAECgYICQAAAA==.Marselus:BAAALAADCggIDwAAAA==.Matatorerös:BAAALAADCgIIAgAAAA==.',Me='Medioamedias:BAAALAADCgUIBgAAAA==.Meliades:BAAALAADCgMIBAAAAA==.Meñiqüe:BAAALAAECgcIEQAAAA==.',Mi='Miiau:BAAALAADCgMIAwAAAA==.Mikewazowski:BAAALAADCgIIAgAAAA==.Minxi:BAAALAAECgQIBgAAAA==.',Mu='Muerodeamor:BAAALAADCgcIBwAAAA==.',['Mâ']='Mândaloriana:BAAALAADCggIDwAAAA==.',['Mä']='Mädara:BAAALAAECgIIAgAAAA==.',Na='Naereth:BAAALAADCgcIBwAAAA==.Nanis:BAAALAAECgMIAwAAAA==.',Ne='Necromourne:BAAALAADCgIIAgAAAA==.Neffer:BAAALAADCgcICQAAAA==.Nemorio:BAAALAADCgMIBQAAAA==.Nemësis:BAAALAADCggIFAAAAA==.Neonara:BAAALAADCgcIBwAAAA==.Neroi:BAAALAADCggIEAAAAA==.',Ni='Nichus:BAAALAADCgIIAgAAAA==.Nicolae:BAAALAAECgQIBAAAAA==.',No='Nomahec:BAAALAAECgEIAQAAAA==.Novem:BAAALAADCggIFQAAAA==.',Nu='Nuite:BAAALAAECgMIAwAAAA==.Numüs:BAAALAADCgcIBwAAAA==.',['Né']='Négulo:BAAALAAECgIIAgAAAA==.',Ol='Olwyn:BAAALAADCgYICQAAAA==.',On='Onixtar:BAAALAADCgYIDgAAAA==.',Or='Oroxxuss:BAAALAAECgcIEAAAAA==.',Os='Oscensillo:BAAALAADCgcIDwAAAA==.',Pa='Paeron:BAAALAAECgMIBQAAAA==.Palnano:BAAALAADCgcICwAAAA==.Panday:BAAALAADCgcIBwAAAA==.Parcheta:BAAALAADCgcICQAAAA==.',Pe='Persefoné:BAAALAADCggIDwAAAA==.',Pr='Profanatak:BAAALAADCggIDwAAAA==.Prolen:BAAALAAECgcICwAAAA==.Proxam:BAAALAADCgcICQAAAA==.',Pu='Pulsor:BAAALAADCgcICwAAAA==.',Py='Pycadillo:BAAALAAECgIIAgAAAA==.',Ra='Rabuillo:BAAALAADCgYIBgAAAA==.Racoon:BAAALAADCgEIAQAAAA==.Rafit:BAAALAAECgYICQAAAA==.Raynesia:BAAALAADCgIIAgAAAA==.Raysa:BAAALAADCggIDAAAAA==.',Re='Reshad:BAAALAADCgMIAwAAAA==.',Ro='Robín:BAAALAADCgIIAgAAAA==.Ronniie:BAAALAADCgcIDgAAAA==.Rothgar:BAAALAADCgIIAgAAAA==.',Ru='Rustrail:BAAALAADCgEIAQAAAA==.',Ry='Ryohei:BAAALAADCgcICwAAAA==.Ryuseiken:BAAALAADCggIBwABLAADCggICAABAAAAAA==.',['Rè']='Rèvenant:BAAALAAECgIIAwAAAA==.',Sa='Sanamaxx:BAAALAAECgYIDQAAAA==.Satrik:BAAALAAECgcIEQAAAA==.Satrïk:BAAALAADCgQIBAABLAAECgcIEQABAAAAAA==.',Se='Seero:BAAALAADCgEIAQAAAA==.Selosarigsol:BAAALAADCgIIAgAAAA==.Serag:BAAALAAECgcIDQAAAA==.Setheria:BAAALAADCggICAAAAA==.',Sh='Shadöw:BAAALAADCgUIBQAAAA==.Shallteàr:BAAALAADCgYIBgAAAA==.Shebelia:BAAALAADCgEIAQAAAA==.Sheryl:BAAALAAECgEIAQAAAA==.Sherä:BAAALAAECgYIDwAAAA==.Shirime:BAAALAAECgcIEQAAAA==.',Si='Sifh:BAAALAADCgYICwAAAA==.Siniestro:BAAALAAECgYICQAAAA==.Sióhn:BAAALAADCgIIAgAAAA==.',Sk='Skolld:BAAALAADCgUIBQAAAA==.',Sn='Snachy:BAAALAADCggICAAAAA==.Snevill:BAAALAAECgYICQAAAA==.',So='Solasta:BAAALAADCggICAAAAA==.Sorfilax:BAAALAADCgQIAwAAAA==.',St='Steelblood:BAAALAAECgIIAgAAAA==.',Su='Suiyan:BAAALAAECgIIAwAAAA==.Susantidad:BAAALAAECgIIAgAAAA==.',Ta='Tanketona:BAAALAADCgEIAQAAAA==.Tarquinius:BAAALAADCgcICAAAAA==.',Te='Tenwa:BAAALAADCgYIBgAAAA==.Teostra:BAAALAADCggICQABLAAECgMIBQABAAAAAA==.Teresa:BAAALAAECgQIBAAAAA==.',Th='Thechaos:BAAALAAECgcIDwAAAA==.Theforsaken:BAAALAADCgYIBgAAAA==.Thordral:BAAALAADCgcIEAAAAA==.Thornei:BAAALAAECgYIDwAAAA==.Thraellysa:BAAALAADCgcICQAAAA==.Thráiin:BAAALAADCgIIAgAAAA==.',To='Touryan:BAAALAAECgcIEQAAAA==.',Tr='Tripa:BAAALAADCgUIBQAAAA==.Triply:BAAALAADCgcIDgAAAA==.Trolee:BAAALAADCggIFgAAAA==.Trollin:BAAALAADCggIFwAAAA==.',Ts='Tsubhaki:BAAALAADCgcICgAAAA==.',Tu='Tumbuska:BAAALAAECgMIBgAAAA==.',Tx='Txu:BAAALAADCgUIBQAAAA==.',Uf='Ufita:BAAALAAECgEIAgAAAA==.',Ul='Ulthér:BAAALAAECgEIAQAAAA==.',Va='Vadri:BAAALAADCggICwAAAA==.Valents:BAAALAADCgEIAQAAAA==.',Ve='Ventini:BAAALAADCgcICgAAAA==.',Vo='Vornak:BAAALAADCgMIBAAAAA==.',Vu='Vulcan:BAAALAAECgMIAwAAAA==.',Wa='Warrblo:BAAALAAECgMIAwAAAA==.Warri:BAAALAADCggICAAAAA==.',We='Weonwe:BAAALAAECgYICQAAAA==.',Wh='Whatisthis:BAAALAADCggIGAABLAAECgYICgABAAAAAA==.Whattson:BAAALAAECgYICQAAAA==.',Wi='Willär:BAAALAADCgYICAAAAA==.',Xe='Xeraaya:BAAALAADCgUIBQAAAA==.',Xu='Xurxiño:BAAALAAECgEIAQAAAA==.',Ya='Yatekuro:BAAALAADCgcIBwAAAA==.',Yj='Yjbv:BAAALAAECgIIAgABLAAFFAMIBQACAAsXAA==.',Yo='Yonatan:BAAALAAECgYICwAAAA==.',Ys='Ysella:BAAALAADCgcIBwAAAA==.',Za='Zagaar:BAAALAADCgcIEAAAAA==.Zakürra:BAAALAAECgMIBQAAAA==.',Ze='Zendra:BAAALAADCgcIBwAAAA==.',['Ät']='Ätaisæ:BAAALAAECgQIBwAAAA==.',['Ér']='Érynn:BAAALAAECgMIAwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end