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
 local lookup = {'Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','DeathKnight-Frost','Monk-Windwalker','Priest-Holy','Shaman-Enhancement','Druid-Guardian','Monk-Brewmaster','DeathKnight-Unholy','Paladin-Retribution','Hunter-Survival','Hunter-BeastMastery','Shaman-Elemental','Hunter-Marksmanship','Rogue-Assassination','Paladin-Holy','Rogue-Subtlety','Druid-Balance',}; local provider = {region='EU',realm='Tichondrius',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ab='Absurdistan:BAAALAADCgcIEgAAAA==.',Ad='Adalycia:BAAALAAECgQIBAAAAA==.',Ae='Aestoreth:BAAALAAECgMIAwAAAA==.',Al='Alcadaias:BAABLAAECoEVAAIBAAgIfSFpAwDlAgABAAgIfSFpAwDlAgABLAAFFAQICQACAI0ZAA==.Alcadraias:BAACLAAFFIEJAAICAAQIjRnCAABxAQACAAQIjRnCAABxAQAsAAQKgRYAAwIACAgjGhQFAEoCAAIACAgjGhQFAEoCAAMABgi6GwIRAAoCAAAA.Alyndriel:BAAALAAECgEIAQAAAA==.',Am='Amygdalá:BAABLAAECoEXAAMEAAgIoB5OAgDhAgAEAAgIoB5OAgDhAgAFAAIIZAuCWgBvAAAAAA==.',An='Angèle:BAAALAADCgYIDAAAAA==.Anillja:BAAALAADCggICgAAAA==.',Ar='Arcanebomber:BAAALAADCggICAAAAA==.Areefa:BAAALAADCggICAAAAA==.Arin:BAAALAADCgEIAQAAAA==.',As='Asgora:BAAALAAECgYIDwAAAA==.Asharuu:BAAALAADCggICAAAAA==.Asymptote:BAAALAAECgYIDAAAAA==.',At='Atmo:BAAALAADCgUIBQABLAAECgMIAgAGAAAAAA==.',Au='Aurisdiamond:BAABLAAECoEWAAIHAAgIEx1ODwCqAgAHAAgIEx1ODwCqAgAAAA==.Auríél:BAAALAADCggIDQAAAA==.',Av='Avye:BAAALAAECgIIAgAAAA==.',Ay='Aymee:BAAALAAECgcICgAAAA==.Ayumiro:BAAALAADCgcIBwAAAA==.',Ba='Babsack:BAAALAAECgYICwAAAA==.Backstábbath:BAAALAADCgYIBgABLAAECgUICAAGAAAAAA==.Baphomèt:BAAALAAECggIDAABLAAECgMIAwAGAAAAAA==.Baphowar:BAAALAAECgMIAwAAAA==.Batuun:BAAALAAECggIDQAAAA==.',Be='Benhal:BAAALAAECgUIBwAAAA==.',Bl='Blackshot:BAAALAAECgYICwAAAA==.Bluetiger:BAAALAAECggIEAAAAA==.Bluewolfy:BAAALAADCgMIAwAAAA==.',Bo='Botschinka:BAAALAADCgYICQAAAA==.',Br='Brewtality:BAABLAAECoEUAAIIAAgIbR/2BQCeAgAIAAgIbR/2BQCeAgAAAA==.Britneyfears:BAAALAAECggIDgAAAA==.Bro:BAAALAADCgEIAQAAAA==.Brunhilde:BAAALAAECgQIBwAAAA==.Brötchen:BAAALAAECgQICAAAAA==.',Ca='Caliope:BAAALAAECgUIBwAAAA==.Caydrin:BAAALAAECgUICAAAAA==.',Ch='Chontamenti:BAAALAAECgcICAAAAA==.Chopsueytom:BAAALAAECggIEAAAAA==.Chríssy:BAAALAADCgcIBwAAAA==.',Cl='Classik:BAAALAAECgQIBwAAAA==.',Cr='Craye:BAAALAADCggICQAAAA==.',Cu='Cursingeagle:BAAALAADCgYIBgAAAA==.',Da='Daemonikan:BAAALAAECgcICAAAAA==.Danori:BAABLAAECoEUAAIJAAgIzxZFEwArAgAJAAgIzxZFEwArAgAAAA==.Darkrazorx:BAAALAADCggICgAAAA==.Darkslash:BAAALAADCggICAAAAA==.',De='Dethecus:BAAALAADCgMIAwAAAA==.',Dk='Dks:BAAALAAECgMIAwAAAA==.',Dr='Dracthyra:BAAALAAECgYIBwABLAAECggIFAAJAM8WAA==.Drakí:BAAALAAFFAIIAgAAAA==.Drowsy:BAAALAAECgMIAwABLAAECgYIBgAGAAAAAA==.Drowsygrip:BAAALAAECgYIBgAAAA==.Drowsyjudge:BAAALAAECgYIBgAAAA==.Drowsyshot:BAAALAADCgYIBgAAAA==.',Du='Dunjovaca:BAAALAADCggIDwAAAA==.Durlin:BAAALAAECgMIAwAAAA==.',Ei='Eisír:BAAALAAECgUICAAAAA==.',Ej='Ejima:BAAALAADCgYICAAAAA==.',El='Elastine:BAAALAADCggIDwAAAA==.Elbandito:BAAALAADCgEIAQAAAA==.Eleen:BAAALAADCggIEwAAAA==.Eliorn:BAAALAADCgMIBgAAAA==.',Er='Ereschkigal:BAAALAADCgMIBQAAAA==.Ermelyn:BAAALAAECgcIEgAAAA==.',Es='Eswe:BAAALAADCggIDgAAAA==.',Eu='Eulila:BAAALAADCgcIBwAAAA==.',Ex='Extoria:BAAALAAECgcICwAAAA==.',Ez='Ezo:BAAALAADCggIDwAAAA==.',Fa='Fadrim:BAAALAADCggIEAAAAA==.',Fe='Felaryon:BAAALAAECgUIBwABLAAECggIFgAKAKAeAA==.Feyriel:BAAALAADCggIFgAAAA==.',Fi='Fier:BAAALAADCggICAAAAA==.Firunn:BAAALAAECgYIBgAAAA==.',Fj='Fjedn:BAABLAAECoEWAAIKAAgIoB7kAQDkAgAKAAgIoB7kAQDkAgAAAA==.',Fl='Flügelschlag:BAAALAAECgIIBAAAAA==.',Fo='Forion:BAAALAAECgcIDgAAAA==.',Fr='Frozenbuns:BAAALAADCgcIBwABLAAECgUICAAGAAAAAA==.',Fu='Fuwamoco:BAAALAADCggICAAAAA==.',Ga='Gardor:BAAALAAECgcIBwAAAA==.',Ge='Genuine:BAAALAADCgcIEgAAAA==.Gerá:BAAALAAECgYICAAAAA==.',Gi='Gitte:BAAALAAECgIIAgAAAA==.',Gl='Glurack:BAAALAADCgcIBwAAAA==.Gláedr:BAAALAADCgcIBwAAAA==.',Go='Gorlad:BAAALAAECgUIBwABLAAECggIFQALALAiAA==.',Gr='Griffindor:BAAALAADCggIDwAAAA==.Grimmbard:BAAALAADCgcIEgAAAA==.Grixus:BAAALAADCgcICAAAAA==.',Ha='Hajoohh:BAAALAADCggIDwAAAA==.Hannahl:BAAALAAECgEIAQAAAA==.',Hr='Hraldrim:BAAALAAECgMIAwAAAA==.',Hu='Hulao:BAABLAAECoEVAAIMAAgI6iKtAQAlAwAMAAgI6iKtAQAlAwAAAA==.Hulosh:BAAALAADCgYIBgABLAAECggIFQAMAOoiAA==.Huzzr:BAAALAADCggIEwAAAA==.',['Hâ']='Hâchî:BAAALAADCgMIBQAAAA==.',['Hä']='Härbärt:BAAALAAECgIIBQAAAA==.',['Hò']='Hònéy:BAAALAADCgIIAgAAAA==.',Ig='Igu:BAAALAADCggIEwAAAA==.',Ik='Ikkusama:BAAALAADCggIDAAAAA==.',Il='Illario:BAAALAADCgcIDAABLAADCggIEwAGAAAAAA==.Ilrise:BAAALAADCgYIBgAAAA==.',Im='Imbecile:BAAALAAFFAIIAgAAAA==.Imimaru:BAAALAAECgcIDAAAAA==.',Is='Iskierka:BAAALAADCgYIBgAAAA==.',Ja='Jarestin:BAAALAADCgMIAwAAAA==.',Je='Jenná:BAAALAADCggICAAAAA==.',Jo='Josoja:BAAALAADCggICAAAAA==.',['Jä']='Jägerpony:BAAALAAECgcIEQAAAA==.',Ka='Katyparry:BAABLAAFFIEFAAMNAAMIYx9MAQDfAAANAAIIFyVMAQDfAAAHAAII/xPPCQCsAAAAAA==.',Ke='Keindruide:BAAALAAECgQIBQABLAAFFAQICwAOAE8bAA==.Keineisen:BAAALAAECggIDgABLAAFFAQICwAOAE8bAA==.Keinpaladin:BAACLAAFFIELAAIOAAQITxtpAACeAQAOAAQITxtpAACeAQAsAAQKgSsAAg4ACAisJsgAAIYDAA4ACAisJsgAAIYDAAAA.',Kn='Knâllâ:BAABLAAECoEWAAMPAAgIUR2kAQCEAgAPAAcISB6kAQCEAgAQAAgI/xU4FwA2AgAAAA==.',Ko='Kowalskî:BAAALAAECgEIAQAAAA==.',Kr='Krower:BAAALAAECgEIAQAAAA==.',Ku='Kumajin:BAAALAAECgYIDwAAAA==.Kurio:BAAALAADCgUICQAAAA==.',Kw='Kwazii:BAAALAAECgIIAgAAAA==.',['Kâ']='Kârami:BAAALAADCgYIBgAAAA==.',La='Laphroaig:BAAALAADCgUIBQAAAA==.',Le='Leinani:BAABLAAECoEWAAIRAAgIeR21CQDJAgARAAgIeR21CQDJAgAAAA==.Lennox:BAAALAAECgIIAgAAAA==.Leoníeè:BAAALAAECggIDAAAAA==.Leoníêe:BAAALAADCggICAAAAA==.Leonîeé:BAAALAADCgcIBwAAAA==.Lestrange:BAAALAADCggIDwAAAA==.Leónîee:BAAALAAECgYIBgAAAA==.',Ll='Lleon:BAAALAADCgIIAgAAAA==.',Lo='Lorki:BAABLAAECoEUAAISAAgIyCLsBAD0AgASAAgIyCLsBAD0AgAAAA==.',Ma='Maghazar:BAAALAADCggICAABLAAECgQIBwAGAAAAAA==.Marizzá:BAAALAAECgcIDwAAAA==.',Mc='Mcløvin:BAAALAAECgYICwAAAA==.',Me='Metaa:BAAALAAECgUIBQAAAA==.Metademon:BAAALAAECgYICQAAAA==.',Mi='Mihla:BAAALAADCgIIAgAAAA==.Minajas:BAAALAAECgYIBwAAAA==.Mitochondria:BAAALAADCggIEgAAAA==.',Mo='Moloko:BAAALAADCgMIAwAAAA==.Monámi:BAAALAAECgcIEAAAAA==.Moolaan:BAABLAAECoEVAAILAAgIsCJvAAA0AwALAAgIsCJvAAA0AwAAAA==.Moynn:BAAALAAECgMIBwAAAA==.',Mu='Muhlani:BAAALAADCgIIAgABLAAECgIIAgAGAAAAAA==.Muuhii:BAAALAADCgUIBQAAAA==.',My='Myrana:BAAALAADCgcIEgAAAA==.',['Má']='Márgê:BAAALAADCggIDwAAAA==.',['Mî']='Mîn:BAAALAADCggIEQAAAA==.',Na='Naramas:BAABLAAECoEVAAIHAAgIlB6ICwDUAgAHAAgIlB6ICwDUAgAAAA==.',Ne='Nehemetawai:BAAALAADCgcIBwAAAA==.Nekira:BAAALAADCggIEAAAAA==.Nexhex:BAAALAADCggIFgAAAA==.',Ni='Nigiri:BAAALAAECgIIAgAAAA==.Nikos:BAAALAADCgYIBgAAAA==.Ninka:BAAALAAECgYIDgAAAA==.Ninni:BAAALAADCgMIAwAAAA==.',No='Notnîthz:BAAALAAECgcIEAAAAA==.Nowan:BAAALAADCgYIBgAAAA==.',Nu='Nuiiman:BAAALAAECgYIDQAAAA==.',On='Onkadien:BAAALAAECgMIBAABLAAECgQIBwAGAAAAAA==.',Or='Orpheoos:BAAALAADCgMIAwAAAA==.',Ox='Oxyana:BAAALAAECgIIAwABLAAECggIFAAJAM8WAA==.',Pa='Paara:BAAALAAECgMIAgAAAA==.Padaf:BAAALAAECgQIBwAAAA==.Palabine:BAAALAAECgMIAwAAAA==.Palax:BAAALAAECggIBwAAAA==.',Pe='Perseus:BAAALAAECggIDQAAAA==.',Pl='Plumplum:BAAALAADCggICAAAAA==.',Po='Pohaare:BAAALAAECgUIBwAAAA==.',Pr='Priesterpony:BAAALAADCggIDwABLAAECgcIEQAGAAAAAA==.',Pu='Purpleshadow:BAAALAADCgYIBgAAAA==.',Pw='Pwnshaman:BAAALAAECggICAAAAA==.',Py='Pyríít:BAAALAADCggIEAAAAA==.',['Pâ']='Pâul:BAAALAAECggIDwAAAA==.',Ra='Radizen:BAAALAAECgEIAQAAAA==.Radun:BAAALAADCgUIBAAAAA==.',Re='Reptikrieg:BAAALAAECgMIBAAAAA==.Ressler:BAAALAAECgYICwAAAA==.',Ri='Ricvoker:BAAALAADCggICwAAAA==.Rinjii:BAAALAADCggIFAAAAA==.Riwen:BAABLAAECoEdAAITAAgIyB98BAACAwATAAgIyB98BAACAwAAAA==.',Ro='Rohlinor:BAAALAADCggICAAAAA==.',Ry='Ryuko:BAAALAADCgcIBwAAAA==.',Sa='Sabarabiskos:BAABLAAECoEWAAIFAAgIwx+dEQBXAgAFAAgIwx+dEQBXAgAAAA==.Saelyana:BAAALAADCggIAgAAAA==.Sajou:BAAALAADCgcIBwAAAA==.',Sc='Sciamano:BAAALAAECggIEwABLAAFFAUICQASAJ0eAA==.Scutuma:BAAALAAECgIIAgAAAA==.',Se='Seppel:BAAALAADCggIDwAAAA==.',Sh='Shadowpi:BAAALAAECgIIAgAAAA==.Shakesbêêr:BAAALAAECgUIBQAAAA==.Shinny:BAABLAAECoEWAAIUAAgI7RzKBQCDAgAUAAgI7RzKBQCDAgAAAA==.Shuroko:BAAALAAECgcIEgAAAA==.Shínigamì:BAEALAAECggIEQAAAA==.',Sk='Skeddit:BAAALAADCggICAAAAA==.',St='Staudir:BAAALAAECgYIBgAAAA==.Stealth:BAABLAAECoESAAIVAAgIWhirAwBTAgAVAAgIWhirAwBTAgAAAA==.Stormnìghtì:BAAALAAECgMIAwAAAA==.Stuhl:BAAALAADCgcIBwAAAA==.',Su='Suiriu:BAAALAAECggIEwAAAA==.Sunaris:BAACLAAFFIELAAIMAAUIziMpAAA1AgAMAAUIziMpAAA1AgAsAAQKgRYAAgwACAh0JjYAAIwDAAwACAh0JjYAAIwDAAAA.',['Sâ']='Sâramane:BAAALAAFFAIIAgAAAA==.',Ta='Talkamar:BAAALAAECgMIAwAAAA==.Tanka:BAAALAADCgIIAgAAAA==.',Te='Terast:BAAALAADCgEIAQAAAA==.',Th='Thanaron:BAABLAAECoEWAAIWAAgIHCV4AQBeAwAWAAgIHCV4AQBeAwAAAA==.Thenehr:BAAALAADCgYIBAAAAA==.Thrilux:BAAALAADCgYIBgAAAA==.Throttnuk:BAAALAAECggIDgAAAA==.',Ti='Timeismonney:BAAALAAECgMIAwAAAA==.',Tj='Tjul:BAAALAADCggICgAAAA==.',To='Toklo:BAAALAADCggICAAAAA==.Tomwolf:BAAALAAECgIIAgAAAA==.',Tr='Treffnix:BAAALAADCggIFgAAAA==.',['Tö']='Törk:BAAALAADCggIEAAAAA==.',Ur='Urunaar:BAAALAADCggICAAAAA==.',Va='Vailara:BAAALAADCgcIBwAAAA==.Valakyra:BAAALAAECgEIAQABLAAECggIFwAEAKAeAA==.Valoridan:BAAALAADCgcIDQABLAABCgMIAwAGAAAAAA==.Vaterdudu:BAAALAADCgcIDgAAAA==.',Ve='Velzard:BAAALAAECgcICAAAAA==.Venegar:BAAALAADCgIIAgAAAA==.',Vi='Victoriá:BAAALAAECgcIDgAAAA==.Vinlai:BAAALAAECgIIBAAAAA==.',Vo='Volshy:BAABLAAECoEWAAIDAAgIUhnECwBhAgADAAgIUhnECwBhAgAAAA==.',Wi='Wichteltrude:BAAALAAECgQIBQAAAA==.',Wu='Wurstwerfer:BAAALAAECgIIBAAAAA==.Wutáng:BAAALAAECgIIAgAAAA==.',Xa='Xarkoshaman:BAAALAADCgYIBgAAAA==.',Xi='Xigbar:BAAALAAECgYICQAAAA==.',Xu='Xuty:BAAALAAECgMIBAAAAA==.',Ya='Yahto:BAAALAAECgYIBgAAAA==.Yamyim:BAAALAADCgcIBAAAAA==.Yandere:BAAALAAECgYICgAAAA==.',Yo='Yolo:BAAALAAECgYIBwAAAA==.',Yu='Yulania:BAAALAADCggICAAAAA==.',Ze='Zephy:BAAALAAECgIIAgAAAA==.Zeranis:BAAALAAECgUIBwAAAA==.Zerberas:BAAALAAECgIIAgAAAA==.',['Zî']='Zîcklein:BAAALAAECgQIBwAAAA==.',['Ál']='Álganosch:BAAALAADCgcIBwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end