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
 local lookup = {'DeathKnight-Blood','Unknown-Unknown','Paladin-Holy','DeathKnight-Frost','DeathKnight-Unholy','Warlock-Destruction','Priest-Holy','Priest-Shadow','DemonHunter-Havoc',}; local provider = {region='EU',realm='Destromath',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ah='Ahiku:BAAALAAECgcIBwAAAA==.',Ai='Aido:BAAALAADCggICAAAAA==.Aiela:BAAALAAECgYICQAAAA==.',Al='Alecxxo:BAAALAAECggICAAAAA==.Alterschwede:BAAALAAECgYICwAAAA==.',An='Angash:BAAALAAECgYICQAAAA==.Angmar:BAAALAAECgMIAwAAAA==.Annery:BAAALAADCggICAAAAA==.Anoldor:BAAALAADCgcIBwAAAA==.',Ap='Apøçålypsê:BAAALAADCgEIAQAAAA==.',Ar='Araxina:BAAALAADCgYIBgAAAA==.Arkash:BAABLAAECoEUAAIBAAgIkiOnAgDsAgABAAgIkiOnAgDsAgAAAA==.Arox:BAAALAAECgYICwAAAA==.Artemìs:BAAALAAECgMIAwAAAA==.Arzoth:BAAALAAECgMIAwAAAA==.',Av='Avarie:BAAALAADCgYIBgAAAA==.',Ay='Ayah:BAAALAAECggIEwAAAA==.',Az='Azki:BAAALAAECgYIBgAAAA==.Azrag:BAAALAAECgcIDQAAAA==.Azzulol:BAAALAAECgYIDgAAAA==.Azzutotem:BAAALAAECgYICQAAAA==.',Ba='Bamigoreng:BAAALAAECgMIBQAAAA==.Barbîe:BAAALAADCgYICgAAAA==.Barkonora:BAAALAAECggICwAAAA==.',Be='Bellona:BAAALAAECgYICQABLAAECgMIAwACAAAAAA==.Beutêl:BAAALAADCgQIBAAAAA==.',Bl='Blackbetti:BAAALAAECgQIBgAAAA==.Blackone:BAAALAAECgYIDwAAAA==.Blastingway:BAAALAAECgYICQAAAA==.',Bo='Boio:BAAALAADCgYIBgAAAA==.Bothline:BAAALAAECgYICQAAAA==.',Br='Braduk:BAAALAAECgYIDgAAAA==.Brannrik:BAAALAADCggIDAAAAA==.',Bu='Buddyhunt:BAAALAAECggICgAAAA==.Bundy:BAAALAAECgYIBgAAAA==.',Ca='Caeruleis:BAAALAAECgYIDgAAAA==.Carrie:BAAALAAECgMIBQAAAA==.Casten:BAAALAAECgYIBgAAAA==.',Ch='Chapis:BAAALAADCgcIBwAAAA==.Chav:BAAALAAECgcIDgAAAA==.Cheeto:BAAALAADCggICAAAAA==.Chiastix:BAAALAAECgIIAwAAAA==.Chicka:BAAALAAECggIBwAAAA==.Chrry:BAAALAAECgUIBwAAAA==.',Cl='Clêzz:BAAALAAECggIDwAAAA==.',Co='Cocó:BAAALAAECgYICAAAAA==.Cotic:BAAALAAECgYICQAAAA==.',Cr='Cranks:BAAALAAECgYIBgAAAA==.Cree:BAAALAAFFAIIAgAAAA==.Crrx:BAAALAAECgMIBwAAAA==.Crusted:BAAALAADCggIDQAAAA==.Cruzander:BAABLAAECoEWAAIDAAcIdBzyDQD+AQADAAcIdBzyDQD+AQAAAA==.',Da='Dabaaws:BAAALAAECgYIDgAAAA==.Danduin:BAAALAADCgcIBwAAAA==.Daník:BAAALAADCggIDAAAAA==.Dasraubtier:BAAALAADCgcIBwAAAA==.Daypak:BAAALAAECggICAAAAA==.',De='Demonet:BAAALAAECgYICQAAAA==.Deni:BAAALAAECggIEgAAAA==.Desgoss:BAAALAAECgYIDQAAAA==.',Dh='Dhugrin:BAAALAAECggIEQAAAA==.',Di='Diana:BAAALAADCgcIDQAAAA==.',Do='Docholiday:BAAALAADCgUIBQAAAA==.Dorofa:BAAALAADCggIFAAAAA==.Dorofies:BAAALAADCgcIDQAAAA==.Dorolie:BAAALAADCggIDwAAAA==.Dorolieb:BAAALAADCggIEAAAAA==.Dorostern:BAAALAADCggICQAAAA==.Dorosüß:BAAALAADCggIFAAAAA==.Dorovoki:BAAALAADCggICgAAAA==.',Dr='Dragonball:BAAALAAECgMIAwAAAA==.Draki:BAAALAADCgIIAgAAAA==.Droknoz:BAAALAAECggICwAAAA==.Drédd:BAAALAAECgIIAgAAAA==.',Du='Durza:BAAALAAECgEIAQAAAA==.Duskshadow:BAAALAADCgcIDgAAAA==.',['Dô']='Dôla:BAAALAAECgYICAAAAA==.',['Dü']='Düsterblick:BAAALAAECgMIAwAAAA==.',Ed='Edamommy:BAAALAADCgcIDgAAAA==.',El='Elgordo:BAAALAAECgEIAQAAAA==.Elyora:BAAALAAECgMIAwAAAA==.',Em='Emier:BAAALAAECgcIEAAAAA==.',En='Enea:BAAALAADCggIEAAAAA==.Enjuu:BAAALAADCggICQAAAA==.Entsafter:BAAALAAECgEIAQABLAAECgYICwACAAAAAA==.',Ex='Exspin:BAAALAADCgQIBAAAAA==.',Fa='Faez:BAAALAAECgMIAwABLAAECgcIDgACAAAAAA==.Fappo:BAAALAAECgEIAQAAAA==.Fatameki:BAAALAADCgIIAgAAAA==.',Fe='Felori:BAAALAAECgIIAgAAAA==.Fepsos:BAAALAAECgEIAQAAAA==.',Fi='Finnami:BAAALAAECgYICQAAAA==.Finnbeast:BAAALAAECgYICQAAAA==.',Fl='Flogtheblood:BAAALAADCggIDgAAAA==.Floôpê:BAAALAAECgMIBAABLAAECgMIBQACAAAAAA==.Flôopé:BAAALAAECgMIBQAAAA==.',Fo='Foose:BAAALAADCggIDgAAAA==.',Fr='Freedoom:BAAALAADCgcICAAAAA==.Freewey:BAAALAADCggIFQAAAA==.Frostboy:BAAALAAECgQICQAAAA==.',Fu='Fuchslicht:BAAALAADCgMIAwAAAA==.',Ga='Garaad:BAAALAAECgcICgAAAA==.Gargo:BAAALAAECgIIAQAAAA==.Garmophob:BAAALAADCggIEAAAAA==.',Ge='Gelorya:BAAALAADCgcICgAAAA==.Gerâld:BAAALAAECgMIBwAAAA==.Gewaltfee:BAAALAADCgIIAgABLAAECgcIDwACAAAAAA==.',Gh='Ghreeny:BAAALAAECgEIAQAAAA==.',Gr='Griedi:BAAALAAECgMIAwAAAA==.Grombrindal:BAAALAADCgcIBwAAAA==.Gronzul:BAAALAADCgUIBwAAAA==.',Ha='Haher:BAAALAAECgEIAQAAAA==.Hal:BAAALAAECgcIDwAAAA==.Halasta:BAAALAAECgYIBgABLAAECgcIDwACAAAAAA==.Halaster:BAAALAAECgcIDwABLAAECgcIDwACAAAAAA==.Halgrim:BAAALAADCggIEAAAAA==.Haliøs:BAAALAADCgcIBgAAAA==.Hanspetra:BAAALAADCggICAAAAA==.Hazekin:BAAALAADCggICAAAAA==.',He='Healsupply:BAAALAADCgcIEgAAAA==.Hegel:BAAALAAECgUIBQAAAA==.Hegi:BAAALAADCggICAAAAA==.',Hi='Hida:BAAALAAECgIIAgAAAA==.',Ho='Hotmedaddy:BAAALAAECgQIBAAAAA==.',Hu='Hunam:BAAALAAECgYICAAAAA==.',['Há']='Hárthór:BAAALAAECgYICwAAAA==.',Ie='Iex:BAAALAAECgIIBAAAAA==.',If='Ifron:BAAALAADCgYICQAAAA==.',In='Inkman:BAAALAADCggICQAAAA==.',Is='Isizuku:BAAALAAECgYICAAAAA==.',Iv='Ivotem:BAAALAADCgcIBwAAAA==.',['Iê']='Iêx:BAAALAAECgMIBQAAAA==.',Ja='Jarli:BAAALAAECgYICgAAAA==.',Je='Jesera:BAAALAAECgQIBgAAAA==.',Ji='Jiray:BAAALAAECgcICwAAAA==.',Jo='Joeyderulo:BAAALAAECgYIBgAAAA==.',Ju='Julmara:BAAALAADCgcIBwAAAA==.Juné:BAAALAADCggICAAAAA==.Justd:BAAALAAECgMIAwAAAA==.Justicow:BAAALAADCgcIBwAAAA==.',Ka='Kardak:BAAALAADCgcIBwAAAA==.Kashmirr:BAAALAAECgMIAwABLAAECgYICQACAAAAAA==.Kathleya:BAAALAAECgMIBgAAAA==.',Ke='Kekwin:BAAALAAECgYIEgAAAA==.Kenergy:BAAALAAECggIEQAAAA==.',Kn='Knille:BAAALAAECgQIBQAAAA==.Knutderbär:BAAALAAECgMIBAAAAA==.',Ko='Kochen:BAAALAAECggICAAAAA==.',Kr='Kruptschuk:BAAALAADCggICAAAAA==.Krônôs:BAAALAAECggICwAAAA==.',Kv='Kvedu:BAAALAAECgYIDQAAAA==.',['Kî']='Kîth:BAAALAADCgcIDQAAAA==.Kîwîsâft:BAAALAADCgMIAwAAAA==.',La='Lamirá:BAAALAADCgcIBwAAAA==.Lanz:BAAALAAECgIIBAAAAA==.Laquat:BAAALAAECgYIDAAAAA==.Laquatqt:BAAALAAECgYIEQAAAA==.Layat:BAAALAADCgcIDQAAAA==.',Le='Lesco:BAAALAADCgUIBQAAAA==.',Li='Liilandi:BAAALAAECgYIBgAAAA==.Liloh:BAAALAADCgYIBgAAAA==.Limead:BAAALAADCgEIAQABLAADCgcIBgACAAAAAA==.Linali:BAAALAADCgcIDAABLAADCgcIDgACAAAAAA==.Lincí:BAAALAADCgcICQAAAA==.Linoxis:BAAALAAECgYIDAAAAA==.',Lo='Lorpendium:BAAALAAECgYIDwAAAA==.Losty:BAAALAAECgMIAwAAAA==.Lothâire:BAAALAAECggIBgAAAA==.',Lu='Lunharia:BAAALAAECgYICgAAAA==.',['Lé']='Lévaria:BAAALAAECgYICQAAAA==.',Ma='Maddalene:BAAALAADCgMIAwAAAA==.Madiras:BAAALAADCgYIBgAAAA==.Maligno:BAAALAADCgQIBAAAAA==.Massedk:BAAALAADCgcIBwAAAA==.Massewarri:BAAALAAECgQIBQAAAA==.Maxilia:BAAALAAECgcICwAAAA==.Mazeltov:BAAALAADCggIFgAAAA==.',Me='Mephizto:BAAALAADCgEIAQABLAADCgIIAwACAAAAAA==.Merun:BAAALAADCgUIBQAAAA==.Mexl:BAAALAADCgIIAgABLAAECgcIDAACAAAAAA==.',Mf='Mfmf:BAAALAADCggIDAAAAA==.',Mi='Minax:BAAALAAECgUIBwAAAA==.Mindrea:BAABLAAECoEUAAMEAAcI2yOXGABTAgAEAAcI/yGXGABTAgAFAAUIdSNACgAJAgAAAA==.',Mo='Moníqué:BAAALAADCggIEQAAAA==.Moonydude:BAAALAAECgQIBAAAAA==.',My='Mylildk:BAAALAAECgEIAQAAAA==.',['Mâ']='Mâjorlazer:BAAALAAECggIDgAAAA==.Mâzîkêên:BAAALAAECgQIBgAAAA==.',Na='Nandaleè:BAAALAAECgYIBgAAAA==.Natot:BAAALAAECgYICQAAAA==.',Ne='Netsend:BAAALAAECgYICwAAAA==.Nexxidus:BAAALAAECgcIEAAAAA==.',Ni='Niixon:BAAALAAECgMIAwAAAA==.',No='Noshgun:BAAALAAECgYIDgAAAA==.',Nu='Nuke:BAAALAAECgUICAAAAA==.',Ny='Nyai:BAAALAADCgcICgABLAADCgcIDgACAAAAAA==.Nyatsu:BAAALAADCgcIAgAAAA==.Nyxie:BAAALAADCggIDwAAAA==.',Oc='Océané:BAAALAAECgYIBgABLAAECgYIBgACAAAAAA==.',Od='Odufuel:BAAALAAECgIIAgAAAA==.',Ol='Olivia:BAAALAAECgQIBAAAAA==.',On='Onebuttonman:BAAALAAECgYIDAAAAA==.Onlycloakz:BAAALAADCgcIBwAAAA==.Ony:BAAALAADCgcIDgAAAA==.',Or='Ortì:BAAALAADCgcIBwAAAA==.Orundar:BAAALAAECgUIBQAAAA==.',Os='Ose:BAAALAADCggIDQABLAAECgYICwACAAAAAA==.',Pa='Palerino:BAAALAADCgQIBAAAAA==.Parac:BAAALAADCgcIBwAAAA==.',Pe='Pentacore:BAAALAADCgcIDgAAAA==.Peppo:BAAALAAECggICAAAAA==.',Ph='Pharmaboy:BAAALAADCggIEgAAAA==.',Pl='Plaguebearer:BAAALAAECgIIAgAAAA==.Plüschbombe:BAAALAAECgQIBAAAAA==.',Pr='Primrose:BAAALAADCggICAAAAA==.Progon:BAAALAADCggIDwAAAA==.Protector:BAAALAADCggIDAAAAA==.',Pu='Puppenmacher:BAAALAADCggICAABLAAECgcIDwACAAAAAA==.',Py='Pyranius:BAAALAADCgcIDQAAAA==.',Ra='Racé:BAAALAAECgYIDAAAAA==.Ragnarisa:BAAALAAECgYIBgAAAA==.Ramus:BAAALAADCggIFwAAAA==.Rantaladar:BAAALAAECgYIDQABLAAECgcIBwACAAAAAA==.Raosh:BAAALAADCgEIAQAAAA==.',Re='Regîna:BAAALAADCgYIBgAAAA==.Reku:BAAALAADCgIIAwAAAA==.Rey:BAAALAAECgMIBQAAAA==.Reyna:BAAALAADCggIEQAAAA==.',Rh='Rhazin:BAAALAADCgYIBgAAAA==.Rhuno:BAAALAAECgQIBQAAAA==.',Ri='Ripplycips:BAAALAADCgUIBQAAAA==.',Ro='Rosada:BAAALAAECgMIAwAAAA==.Rotznaga:BAAALAADCgcICAAAAA==.Roxsy:BAAALAADCgUIBQABLAAECgYICAACAAAAAA==.Roxxz:BAABLAAECoEXAAIGAAgItyJZBAAjAwAGAAgItyJZBAAjAwAAAA==.',Ru='Rujunoy:BAAALAADCggIBAAAAA==.Rusthex:BAAALAADCgcIBwAAAA==.',Sa='Saizz:BAAALAAECgcIEQAAAA==.Salmara:BAAALAAECgYIDAAAAA==.',Sc='Schlackesven:BAAALAADCgYIBgAAAA==.Schokan:BAAALAADCggICAAAAA==.Scrubbï:BAAALAAECgYICQAAAA==.',Se='Selfhated:BAAALAADCgcICwAAAA==.Selthantar:BAAALAADCggIFAAAAA==.Semiaramis:BAAALAAECgYICQAAAA==.Senan:BAAALAAECgcICwAAAA==.Sento:BAAALAADCggIEAABLAAECgcIDgACAAAAAA==.Sethidrood:BAAALAADCgUIBwABLAAECgUICAACAAAAAA==.Sethishami:BAAALAAECgEIAQABLAAECgUICAACAAAAAA==.Sethunter:BAAALAAECgUICAAAAA==.Settschmo:BAAALAADCgQIBQAAAA==.',Sh='Shaozen:BAAALAAECgYIDgAAAA==.Sharilyn:BAAALAAECgUICwAAAA==.Sharybdis:BAAALAADCgQIBAAAAA==.Shayera:BAAALAAECgYIDwAAAA==.Shurkul:BAAALAADCggIDgAAAA==.Sházam:BAAALAADCgcICAAAAA==.Shîne:BAAALAAECgIIAgAAAA==.',Si='Si:BAAALAAECgMIBAAAAA==.Sicario:BAAALAADCgcIBwAAAA==.Silènce:BAAALAADCggICAAAAA==.',Sn='Snaliv:BAAALAAECgYIDQAAAA==.Sner:BAAALAADCgQIBAAAAA==.Snickerz:BAAALAADCggICAAAAA==.',So='Solaclypsa:BAAALAADCggIDwAAAA==.',St='Stockanwand:BAAALAADCggICgAAAA==.Stormorc:BAAALAAECgMIBQAAAA==.Strahlemann:BAAALAAECgYIBgAAAA==.Strandlümmel:BAAALAADCgcIBwAAAA==.',Su='Sutella:BAAALAADCggIDwAAAA==.',Sy='Synopsis:BAAALAADCggICAAAAA==.Syrelia:BAAALAAECgYICQAAAA==.',Ta='Tagwandler:BAAALAAECgcICgAAAA==.Taochi:BAAALAADCgcIBwABLAADCggIDAACAAAAAA==.Taros:BAAALAAECggICAAAAA==.Taztaxes:BAAALAAECgYICwAAAA==.',Te='Temyrel:BAAALAAECgIIBAAAAA==.Tenchi:BAAALAADCgEIAQAAAA==.Teninchtaker:BAAALAAECgYICwAAAA==.',Th='Thedestroya:BAAALAAECgYICQAAAA==.Theraila:BAAALAADCgYIBgAAAA==.Throllk:BAAALAADCgIIAgAAAA==.Thularis:BAAALAADCggIGAAAAA==.',Ti='Timoo:BAAALAAECgYICQAAAA==.Tiraja:BAAALAADCggICgAAAA==.',To='Tomatênsaft:BAAALAADCgcIBwAAAA==.',Tr='Troxxas:BAAALAAECgYICAAAAA==.Troxxs:BAAALAAECgMIAwABLAAECgYICAACAAAAAA==.Trìx:BAAALAAECgcIDgAAAA==.',['Tý']='Týr:BAAALAADCggICgAAAA==.',Ul='Ulffoonso:BAAALAADCgQIBAAAAA==.',Un='Underiya:BAAALAAECgYIBgAAAA==.',Us='Uschï:BAAALAAECgYICwAAAA==.',Ut='Utopia:BAAALAAECgYIDwAAAA==.',Va='Valasse:BAABLAAECoEUAAMHAAgItxbbGwDcAQAHAAgItxbbGwDcAQAIAAUIFwMGPgCzAAAAAA==.',Ve='Vesíca:BAAALAADCggICAABLAAECggIFQAJACwfAA==.',Vi='Vizuna:BAAALAADCgcIDgAAAA==.',Wa='Waurox:BAAALAAECgYICQAAAA==.',Wh='Whiskysour:BAAALAAECgcIDAAAAA==.',Wu='Wutelfe:BAAALAAECgcIDwAAAA==.',Xa='Xal:BAAALAAECgYIDAAAAA==.',Xe='Xerogon:BAAALAADCgcIBAAAAA==.',Xi='Xibalbá:BAAALAADCgYIBgAAAA==.',Xu='Xuan:BAAALAAECgYIBgAAAA==.',Xy='Xyllius:BAABLAAECoEWAAIFAAgIex1GAwDKAgAFAAgIex1GAwDKAgAAAA==.',Ya='Yannel:BAAALAAECgYICwAAAA==.Yarîîa:BAAALAADCgcIDQAAAA==.',Yu='Yukino:BAAALAADCggIDwABLAAECgcIBwACAAAAAA==.Yukisa:BAAALAADCgcIBwAAAA==.',Za='Zaiaku:BAAALAAECgMIAwAAAA==.',Zy='Zyphyros:BAAALAAECgYICQAAAA==.',['Âr']='Ârês:BAAALAAECgIIAgAAAA==.',['Âs']='Âshby:BAAALAAECgMIAwABLAAECgQIBgACAAAAAA==.',['Øl']='Ølaf:BAAALAADCggICAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end