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
 local lookup = {'Paladin-Protection','Paladin-Retribution','Paladin-Holy','Priest-Shadow','Rogue-Assassination','DeathKnight-Frost','DeathKnight-Unholy','Shaman-Restoration','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Holy','Shaman-Enhancement','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Warrior-Fury','Warlock-Destruction','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Mage-Frost','Rogue-Subtlety','Warlock-Affliction','Shaman-Elemental','Druid-Guardian','Druid-Restoration','Mage-Fire','DeathKnight-Blood','Warlock-Demonology','Druid-Balance','Rogue-Outlaw','Warrior-Protection','Warrior-Arms',}; local provider = {region='EU',realm='Baelgun',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aarie:BAAALAAECgQICgAAAA==.Aaylasecura:BAAALAAECggIBAAAAA==.Aaysin:BAAALAADCgUIBQAAAA==.',Ab='Abby:BAAALAAECgQIBAAAAA==.',Ag='Aggronator:BAAALAADCgYICQAAAA==.',Ah='Ahrgó:BAAALAAECgYIDQAAAA==.',Al='Alarjin:BAABLAAECoEcAAIBAAcILhsvFgAXAgABAAcILhsvFgAXAgAAAA==.Aldon:BAAALAADCgMIAwAAAA==.Alexis:BAAALAADCgYIBgAAAA==.Allvater:BAAALAAECgYIEgAAAA==.Alypse:BAAALAAECgEIAQAAAA==.Alïsa:BAAALAAECgYIDQAAAA==.',Am='Ambulanz:BAAALAAECgYIDQAAAA==.Amirii:BAABLAAECoEkAAICAAgIJh0bNgBzAgACAAgIJh0bNgBzAgAAAA==.',An='Anastasyá:BAABLAAECoEaAAIBAAYIrRK6MQA9AQABAAYIrRK6MQA9AQAAAA==.Ancilla:BAAALAADCgYICAAAAA==.Animàl:BAAALAADCgIIAgAAAA==.Anoriel:BAAALAAECgMIAwAAAA==.Ansotíca:BAAALAAECgYIEwAAAA==.Antarya:BAAALAAECgMIAwABLAAECgcIIAADAGcYAA==.',As='Aseya:BAAALAAECgYIEQABLAAECggIHwAEABYgAA==.Ashinna:BAAALAADCgQIBAAAAA==.',Az='Azran:BAAALAAECgYIBgAAAA==.Azurglut:BAAALAADCgcICQAAAA==.',Be='Beasticus:BAAALAAECgMIBgAAAA==.Beeri:BAAALAADCgUIBQAAAA==.Belpherus:BAABLAAECoEgAAIFAAgIrRTSGAA/AgAFAAgIrRTSGAA/AgAAAA==.Bendrin:BAAALAAECgYIDgAAAA==.',Bi='Bibbihexberg:BAAALAAECgUIBgAAAA==.Bigdickus:BAAALAAECgcIDgAAAA==.Bigevil:BAAALAADCggIBwAAAA==.Birtches:BAAALAADCgQIBAAAAA==.',Bl='Blackhexer:BAAALAAECgEIAQAAAA==.Blacklîght:BAAALAADCgcIBwAAAA==.Blaise:BAAALAADCggIHgAAAA==.Bleakness:BAABLAAECoEdAAMGAAcIHCMZJAC+AgAGAAcI6CIZJAC+AgAHAAYI3yD+FAAHAgAAAA==.Blitzbart:BAAALAADCggICAAAAA==.Blitzfalke:BAAALAADCgcICAAAAA==.Bluespark:BAABLAAECoEZAAIIAAcIASPCFACzAgAIAAcIASPCFACzAgAAAA==.Bluteria:BAAALAAECgYIDgAAAA==.',Bo='Bomba:BAAALAADCggIEwABLAAECgUIBgAJAAAAAA==.',Br='Brang:BAAALAAECgEIAgAAAA==.Breef:BAAALAAECgQIBgAAAA==.Breemy:BAAALAADCgcICAAAAA==.Brunt:BAAALAADCggICAAAAA==.',['Bá']='Bárbarella:BAAALAAECgYIBgAAAA==.',Ca='Cantouchthis:BAACLAAFFIEGAAIKAAIIRB/DJQCYAAAKAAIIRB/DJQCYAAAsAAQKgTYAAwoACAj/JUIEAGADAAoACAj/JUIEAGADAAsAAgjLE7iPAH4AAAAA.Carbonara:BAAALAAECgYICAABLAAECgYIDQAJAAAAAA==.Castiella:BAABLAAECoEdAAIMAAYI3xpgOwDIAQAMAAYI3xpgOwDIAQABLAAECggIHwANACweAA==.Catarrhini:BAAALAAECgQIBAABLAAECgYIDAAJAAAAAA==.',Ce='Cece:BAAALAADCggIEAAAAA==.Cemendur:BAAALAAECgUIBgABLAAECgcIFAADAPkYAA==.',Ch='Chabo:BAAALAAECgYIDAAAAA==.Chaosmagier:BAABLAAECoEaAAIOAAYIzQlPlgAtAQAOAAYIzQlPlgAtAQAAAA==.Chast:BAAALAADCgIIAgAAAA==.Chihiro:BAABLAAECoEfAAINAAgILB7hBADBAgANAAgILB7hBADBAgAAAA==.Chillajr:BAAALAAECgMIBQABLAAFFAUICQAPABMPAA==.Chillas:BAAALAADCgMIAwABLAAFFAUICQAPABMPAA==.Chiori:BAAALAAECgMIBwAAAA==.Chochang:BAAALAADCggICAAAAA==.Chuckyborris:BAAALAAECgcICQAAAA==.Chumana:BAAALAADCggIEAAAAA==.',Co='Collectór:BAAALAAECgYIDgAAAA==.',Cr='Crichton:BAABLAAECoEbAAIMAAYIlxdaRwCTAQAMAAYIlxdaRwCTAQAAAA==.',Cu='Curíe:BAAALAAECggICAAAAA==.',Da='Dabby:BAAALAADCgcIFwAAAA==.Dalma:BAABLAAECoEZAAIDAAcIWxVJJADHAQADAAcIWxVJJADHAQAAAA==.Dareklopak:BAAALAADCggIGwAAAA==.Darkdestiny:BAAALAADCggICAAAAA==.Darkmouth:BAAALAADCggIHgAAAA==.Darthgustel:BAAALAADCgcIBwAAAA==.',De='Deikoscha:BAAALAADCgEIAQAAAA==.Derweißè:BAAALAADCgcIDgAAAA==.Devrim:BAAALAAECgEIAQAAAA==.',Di='Diana:BAAALAAECggICAAAAA==.',Do='Dominka:BAAALAADCgYIBgAAAA==.Donnerknolle:BAAALAADCgUIBQAAAA==.Dorgun:BAAALAAECgQIBAABLAAECgYIGwABAG4jAA==.Dovarius:BAAALAADCgQIBAAAAA==.',Dr='Drafgo:BAAALAAECgEIAQAAAA==.Drakas:BAAALAADCgcIDgAAAA==.Dralgar:BAABLAAECoEbAAQBAAYIbiOvGAD9AQABAAYIAiCvGAD9AQACAAUIViRvawDjAQADAAUILB5aKACrAQAAAA==.Dreadbringer:BAABLAAECoEXAAIGAAgIGBWKYQD/AQAGAAgIGBWKYQD/AQAAAA==.',Du='Dungo:BAAALAAECgQIBQAAAA==.Durzzar:BAAALAADCgEIAQAAAA==.',['Dâ']='Dâdan:BAAALAADCggIDAABLAAFFAMICAAMAAcaAA==.',['Dä']='Dämom:BAAALAAECgcIDAAAAA==.',Ea='Eaglehorn:BAAALAADCggIEwABLAAECgUIBgAJAAAAAA==.',El='Elanya:BAABLAAECoEgAAMDAAcIZxhDHAABAgADAAcIZxhDHAABAgACAAEI5xNaPQE4AAAAAA==.Elanía:BAAALAADCggICAAAAA==.Eleen:BAAALAADCggICgAAAA==.Elenyadrak:BAAALAADCgIIAgAAAA==.Elerias:BAAALAAECgYIEgAAAA==.Elisabeth:BAAALAAECgYICgABLAAECggIHwAEABYgAA==.Ellanis:BAAALAADCggICAAAAA==.Elmentra:BAAALAADCggIIQAAAA==.Elosary:BAAALAADCgEIAQAAAA==.Elrunaya:BAAALAADCgEIAQAAAA==.Eltandana:BAAALAAECgUIBQAAAA==.Elvinara:BAAALAAECgUIBQAAAA==.Elyth:BAAALAADCgQIBAAAAA==.',Em='Embrasi:BAAALAADCgYIBgAAAA==.Emorii:BAABLAAECoEVAAIQAAYIwhXvIQBsAQAQAAYIwhXvIQBsAQAAAA==.',En='Enda:BAAALAADCgYIBgAAAA==.',Eo='Eonir:BAAALAAECgUIAwAAAA==.',Eq='Equinoxia:BAAALAAECgIIBAAAAA==.Equis:BAABLAAECoEgAAIRAAgITxEWGgC5AQARAAgITxEWGgC5AQAAAA==.',Es='Espressasino:BAAALAAECgYIBwAAAA==.',Et='Etheria:BAAALAAECgQIBwAAAA==.',Eu='Eupaisia:BAABLAAECoEYAAIKAAcIBAsNlABWAQAKAAcIBAsNlABWAQAAAA==.',Ev='Everend:BAAALAAECgYIDAAAAA==.',Ez='Ezekeel:BAAALAAECgUIBgAAAA==.',Fa='Famo:BAAALAADCgcICQAAAA==.Fanzerpaust:BAAALAADCgYIBgAAAA==.Faran:BAAALAAECgYIEQAAAA==.',Fe='Fengyu:BAABLAAECoEaAAMSAAYI5RLkLQBlAQASAAYI5RLkLQBlAQATAAYITw4BQgArAAAAAA==.Fenrir:BAABLAAECoEXAAIUAAYIlBeaXQCgAQAUAAYIlBeaXQCgAQAAAA==.Ferrin:BAAALAAECgYICwAAAA==.',Fl='Flauschilein:BAABLAAECoEoAAMCAAgI1BwNLACbAgACAAgI1BwNLACbAgADAAMImSHkTgDOAAAAAA==.Flintenuschi:BAAALAADCgcIFwAAAA==.',Fo='Foxit:BAAALAAECgYIDQAAAA==.',Fr='Fraubesen:BAABLAAECoEcAAIKAAgIsxaFTAD5AQAKAAgIsxaFTAD5AQAAAA==.Frózén:BAAALAADCgcIDQABLAADCggIEAAJAAAAAA==.',Fu='Furorio:BAAALAAECgYICAAAAA==.',Fy='Fynderis:BAAALAAECgYIBgAAAA==.',['Fí']='Fíre:BAAALAAECgIIAgAAAA==.',Ga='Gandelf:BAAALAADCgMIAwAAAA==.Ganjubas:BAABLAAECoEbAAIVAAgIRhbKPgAPAgAVAAgIRhbKPgAPAgAAAA==.',Ge='Getrunken:BAAALAADCgQIBAAAAA==.',Gl='Glevenluna:BAABLAAECoEXAAIPAAgIsRX1QwAtAgAPAAgIsRX1QwAtAgAAAA==.',Go='Golgater:BAAALAADCgMIAgABLAADCggIEAAJAAAAAA==.',Gr='Greatmage:BAAALAAECgMIAwAAAA==.Grimbur:BAABLAAECoEXAAIVAAYIgQY7mQAAAQAVAAYIgQY7mQAAAQAAAA==.',Gu='Gurumi:BAAALAAFFAMIAwAAAA==.',Ha='Haines:BAAALAAECgIIAQAAAA==.Halphas:BAAALAADCggIJAABLAAECgYIDgAJAAAAAA==.',He='Heide:BAAALAADCggICAAAAA==.Heimerdínger:BAAALAADCgcIBwAAAA==.',Ho='Holyglightly:BAAALAADCgYIBgAAAA==.Horízon:BAAALAADCgIIAgAAAA==.',['Hä']='Hässlichekuh:BAABLAAECoEiAAMWAAcI/xFoCADGAQAWAAcI/xFoCADGAQAXAAcItgvbHQBHAQAAAA==.',['Hê']='Hêstiâ:BAAALAAECggIEgAAAA==.',Ib='Ibus:BAAALAADCggIJQAAAA==.',Ig='Ignia:BAABLAAECoEuAAIYAAgIthv+FgBVAgAYAAgIthv+FgBVAgAAAA==.',Il='Ilaria:BAABLAAECoEdAAIKAAcI9yB7KQB3AgAKAAcI9yB7KQB3AgAAAA==.',Im='Impfactory:BAAALAAECgUIBwABLAAECgcIFAADAPkYAA==.',In='Inanis:BAABLAAECoEYAAIZAAcIUCE6DgCgAgAZAAcIUCE6DgCgAgABLAAFFAUICQAPABMPAA==.Inuradin:BAAALAADCggICAABLAAECgQIDQAJAAAAAA==.Inurael:BAAALAAECgQIDQAAAA==.Inystra:BAAALAAECgIIAgABLAAFFAMIBwAVAHYUAA==.',Ir='Ironhunter:BAAALAAECgYIDgAAAA==.',Is='Ishanri:BAAALAADCgcICgABLAAECgIIAgAJAAAAAA==.Ishas:BAABLAAECoEuAAICAAgIdRqVQwBHAgACAAgIdRqVQwBHAgAAAA==.',Iv='Ivredas:BAABLAAECoEWAAIVAAgIagddigAsAQAVAAgIagddigAsAQAAAA==.',Ja='Jaleria:BAABLAAECoEYAAMaAAcI5BQVFQDRAQAaAAcI5BQVFQDRAQAFAAMIVBB3UgCtAAAAAA==.Jano:BAABLAAECoElAAMVAAgIhyAAGwDJAgAVAAgIwB8AGwDJAgAbAAMIExxjHQDpAAAAAA==.Jasik:BAAALAADCggIDwAAAA==.Jaws:BAAALAADCggIEAAAAA==.',Jo='Joyohunter:BAAALAADCgcIBwAAAA==.',Js='Js:BAAALAAECgYIDAAAAA==.',Ju='Juti:BAAALAADCgUIBQAAAA==.',Ka='Kaelianne:BAAALAADCgQIBwAAAA==.Kaioshin:BAAALAAECggICAAAAA==.Kalingo:BAAALAADCgMIAwAAAA==.Kallen:BAAALAAECgYIBgABLAAFFAMICAAcAC4aAA==.Kaltorias:BAAALAADCgcIFwAAAA==.Kamaro:BAAALAAECgYIDgAAAA==.Kamîî:BAAALAAECgMIBAAAAA==.Kandrax:BAAALAAECgIIAgAAAA==.Karolína:BAAALAADCggICAAAAA==.Katzu:BAABLAAECoEYAAIUAAYI6Q2zdABfAQAUAAYI6Q2zdABfAQAAAA==.Kaìo:BAAALAAECgEIAQAAAA==.',Kh='Kheeza:BAAALAADCggICAAAAA==.',Kl='Kleopetra:BAAALAADCgQIBAAAAA==.Klinge:BAAALAADCgcIDQAAAA==.',Kn='Knall:BAAALAAECgQIDAAAAA==.Knatterjoe:BAAALAAECgEIAQAAAA==.',Ko='Korum:BAABLAAECoEdAAICAAcI+hkXQgBLAgACAAcI+hkXQgBLAgAAAA==.',Kr='Kragen:BAACLAAFFIEKAAIaAAUIgQyAAwCOAQAaAAUIgQyAAwCOAQAsAAQKgScAAxoACAgFGSYNADwCABoACAgFGSYNADwCAAUABghrDZE+AEYBAAAA.Krawâll:BAABLAAECoEfAAIKAAYIWht8agCtAQAKAAYIWht8agCtAQAAAA==.Kredar:BAAALAAECgQIBgAAAA==.Kri:BAAALAAECgYICgAAAA==.Kriwi:BAAALAAECgUICQAAAA==.Krombopulos:BAAALAAECgMIBwAAAA==.',Ky='Kyrenike:BAAALAAECgQIAwAAAA==.Kyseria:BAAALAADCgIIAgAAAA==.',['Kü']='Küstenkind:BAAALAAECgYIDgAAAA==.',La='Lanee:BAAALAAECgQIBAAAAA==.Larakiss:BAAALAAECggICAAAAA==.Larissa:BAAALAAECgYIDAAAAA==.Laronian:BAAALAAECgQIBgAAAA==.Lava:BAAALAAECgcIBwAAAA==.Lazyroshi:BAABLAAECoEcAAISAAcIuRuYFQA6AgASAAcIuRuYFQA6AgAAAA==.',Le='Leandrija:BAAALAAECgYIDwAAAA==.Leelokar:BAAALAAECggICAAAAA==.Legionatos:BAAALAADCgcIBwAAAA==.Legz:BAAALAADCgcIBwAAAA==.Lelarija:BAAALAAECgYIBAAAAA==.Lemocon:BAAALAAECgUICQAAAA==.Leoknox:BAAALAADCgcIFgAAAA==.Leva:BAAALAAECgIIAgAAAA==.',Li='Licky:BAABLAAECoEuAAIdAAgIMiS0AQA5AwAdAAgIMiS0AQA5AwAAAA==.Lieno:BAAALAADCgYIBgAAAA==.Liiará:BAAALAADCggICAABLAAECgYIDQAJAAAAAA==.Linorel:BAABLAAECoEWAAIGAAYIyCANXwAFAgAGAAYIyCANXwAFAgAAAA==.Lirath:BAAALAADCgQIBgAAAA==.',Lo='Lohse:BAAALAAECgUIBQAAAA==.Loid:BAAALAADCggICAAAAA==.Lovekurdishx:BAAALAAECgEIAgAAAA==.',Lu='Luckyswan:BAABLAAECoEuAAIeAAgIIBDTSQCBAQAeAAgIIBDTSQCBAQAAAA==.',Ly='Lycane:BAAALAADCgYICQAAAA==.Lyrra:BAAALAADCgMIAwAAAA==.Lywellion:BAAALAAECgYIBgABLAAECgYIFgAKAPUcAA==.Lyxae:BAAALAAECgIIAgAAAA==.',['Lé']='Lémontree:BAABLAAECoEfAAIeAAgIuSJSCgDvAgAeAAgIuSJSCgDvAgAAAA==.',['Lì']='Lìnglìng:BAAALAADCgQIBAABLAAECgcIDgAJAAAAAA==.',['Lí']='Línnéa:BAAALAADCgUIBQAAAA==.',['Lî']='Lîn:BAAALAAECgMIBAAAAA==.',Ma='Machtelf:BAAALAADCggICAAAAA==.Macumbá:BAAALAAECggICAAAAA==.Madrixx:BAAALAADCggIDQAAAA==.Maerea:BAAALAADCgIIBAABLAAECgIIAgAJAAAAAA==.Maethûn:BAAALAAECgYIDgAAAA==.Maggie:BAAALAAECgIIAgAAAA==.Magmaros:BAAALAAECgUIEQAAAA==.Mahani:BAAALAAECggICAAAAA==.Makara:BAAALAAECgUIBQAAAA==.Mansamunsà:BAAALAAECgMIAwAAAA==.Marajha:BAAALAAECgIIAgAAAA==.Marell:BAAALAAECgYIEAABLAAECgYIEgAJAAAAAA==.Mason:BAAALAAECgYIDwAAAA==.Maúrix:BAABLAAECoEhAAIBAAgIGSDsCADHAgABAAgIGSDsCADHAgAAAA==.',Mc='Mcdrowd:BAAALAAECggICAAAAA==.Mcfree:BAABLAAECoEYAAIDAAcIIh4iEwBQAgADAAcIIh4iEwBQAgAAAA==.',Md='Mdbsamur:BAAALAADCggIDQAAAA==.',Me='Meatwatz:BAABLAAECoEmAAIUAAgIMh7BIgCRAgAUAAgIMh7BIgCRAgAAAA==.Meggîe:BAAALAADCgYIDAAAAA==.Mellow:BAABLAAECoEdAAIMAAgIXBoBHQBwAgAMAAgIXBoBHQBwAgAAAA==.Melonezorn:BAAALAADCggIFAAAAA==.Memecoochie:BAAALAAECggIDgAAAA==.Menelora:BAAALAAECggICAAAAA==.',Mi='Mimii:BAAALAADCgUIBQAAAA==.Mindfreak:BAABLAAECoEhAAIOAAcI+Q8VaQCqAQAOAAcI+Q8VaQCqAQAAAA==.Mip:BAAALAAECggICAAAAA==.Mirasori:BAAALAADCgYIBgAAAA==.Mirilena:BAAALAADCgcIBwAAAA==.Missdotter:BAABLAAECoEXAAMbAAgIixytAwC1AgAbAAgIixytAwC1AgAVAAII8guTwgBzAAAAAA==.',Mo='Modrolux:BAAALAADCgcICAAAAA==.Moglin:BAABLAAECoEZAAMOAAcIdR0wOQBHAgAOAAcIdR0wOQBHAgAfAAEIIg4KHwA0AAAAAA==.Mokushiroku:BAACLAAFFIEHAAIgAAMIzxHnBgDPAAAgAAMIzxHnBgDPAAAsAAQKgR8AAiAACAiCHYkNAEcCACAACAiCHYkNAEcCAAAA.Monnimon:BAAALAADCggIEAAAAA==.Monspiet:BAAALAADCggICwAAAA==.Moonjade:BAAALAADCgYIEAAAAA==.Mooped:BAAALAAECgIIAwAAAA==.',Mu='Muhdot:BAAALAADCgcIBwABLAAECgcIIgAWAP8RAA==.',My='Myrah:BAAALAAECgUIAwAAAA==.Myránda:BAAALAADCgMIBAAAAA==.Myría:BAAALAAECgMIAwAAAA==.',['Mó']='Mómò:BAAALAAECgYICAAAAA==.Móðsognir:BAAALAAFFAIIBAABLAAFFAMICAAMAAcaAA==.',Na='Nadjara:BAAALAADCgUIBQAAAA==.Nagoon:BAAALAAECgUIBgAAAA==.Nainda:BAAALAADCgcIBwAAAA==.Nakata:BAAALAADCgcIDQAAAA==.',Ne='Nedoknight:BAAALAADCggIDQAAAA==.Nedonia:BAABLAAECoEpAAIEAAgIaxbOKAAZAgAEAAgIaxbOKAAZAgAAAA==.Neevi:BAAALAADCggICAAAAA==.Nehalennia:BAAALAADCggIIgABLAAECgYIDgAJAAAAAA==.Nerevár:BAAALAAECgYIDgABLAAECgYIDwAJAAAAAA==.Nervana:BAAALAADCgEIAQAAAA==.Nevista:BAAALAAECgcIBwAAAA==.Newotrix:BAAALAAECgQIAgAAAA==.Nexo:BAAALAADCgYICQAAAA==.',Ni='Nighthâwk:BAAALAAECgQIEAABLAAECgYIDgAJAAAAAA==.',No='Nohka:BAAALAAECgYIDAAAAA==.Nola:BAAALAADCgEIAQABLAAECgYIDAAJAAAAAA==.Nonya:BAAALAADCgcIEgAAAA==.Norberto:BAAALAAECgYIDAAAAA==.Northwind:BAAALAAECgYIDQAAAA==.',Nu='Nudelwasser:BAAALAADCgcIBwAAAA==.Nufahpriest:BAABLAAECoEdAAIMAAcIsxVGOgDNAQAMAAcIsxVGOgDNAQAAAA==.',['Nâ']='Nâssendra:BAAALAADCgcIBwAAAA==.',['Né']='Nécro:BAAALAAECgQICAAAAA==.',['Nì']='Nìghtwish:BAAALAADCgIIAgAAAA==.',['Nô']='Nôcti:BAABLAAECoEYAAIPAAcIgxutSgAXAgAPAAcIgxutSgAXAgAAAA==.Nôsferatu:BAAALAAECgIIAgAAAA==.',['Nÿ']='Nÿx:BAACLAAFFIEIAAIMAAMIBxoWDQAHAQAMAAMIBxoWDQAHAQAsAAQKgRwAAgwACAgMID0PANgCAAwACAgMID0PANgCAAAA.',Ol='Olessia:BAAALAAECgcIEgAAAA==.',Os='Ostfriesin:BAAALAADCgMIAwAAAA==.',Pa='Panderrius:BAAALAADCgcIDQAAAA==.Pandoryá:BAAALAADCgcICwAAAA==.Pandorâ:BAAALAAECgYIDgAAAA==.',Pe='Pegga:BAAALAADCgEIAQAAAA==.',Ph='Phonomenal:BAAALAADCggICAAAAA==.',Pi='Pilavpowa:BAAALAAECgcIBwABLAAFFAMIBwAgAM8RAA==.Pinneken:BAAALAADCgQIBAAAAA==.',Po='Polgara:BAAALAADCgcIFwAAAA==.Pommie:BAAALAAECgcIEAAAAA==.Portalicus:BAAALAADCggICAABLAAECgMIBgAJAAAAAA==.',Pr='Presbarhorn:BAAALAADCggICQAAAA==.Prettyswan:BAACLAAFFIEIAAIIAAMIORB9FgDFAAAIAAMIORB9FgDFAAAsAAQKgSkAAggACAh/Iu8KAPkCAAgACAh/Iu8KAPkCAAAA.Probe:BAAALAADCggICQAAAA==.',Pu='Puls:BAAALAADCggIFgABLAAECgYIDQAJAAAAAA==.Pupselchen:BAAALAADCggIEQAAAA==.',Qa='Qaui:BAAALAAECgEIAQAAAA==.',Qu='Quackfist:BAABLAAECoEuAAISAAgILha6GAAWAgASAAgILha6GAAWAgAAAA==.Quazeydax:BAAALAAECgQIBAAAAA==.Quirtan:BAAALAADCggICAAAAA==.Quivyx:BAAALAADCgUIBQAAAA==.',Ra='Ralarian:BAAALAAECgYICwAAAA==.Randalthor:BAAALAAECgYICwAAAA==.Ratatoskr:BAAALAADCgIIAQABLAAECgcIFAADAPkYAA==.Razala:BAABLAAECoEXAAIKAAYIshxlYADFAQAKAAYIshxlYADFAQAAAA==.Razzac:BAAALAAECgYICgABLAAECgYIFgAhAL8fAA==.Razzaraja:BAAALAAECgYIEQABLAAECgYIFgAhAL8fAA==.Razí:BAAALAAECgIIBAAAAA==.',Re='Rebrrth:BAAALAAECgcICQAAAA==.Regentonne:BAAALAAECgYIDgAAAA==.Rev:BAAALAADCgIIAgAAAA==.Reáper:BAAALAADCggICgAAAA==.',Ri='Ribéry:BAAALAAECgUIAwAAAA==.',Ro='Rocketeér:BAAALAAECgQICQAAAA==.Rofellos:BAABLAAECoEeAAIEAAcIDglHUwBDAQAEAAcIDglHUwBDAQAAAA==.',Ru='Ruon:BAAALAADCgcIBwAAAA==.',Sa='Sachithor:BAAALAADCgIIAgAAAA==.Sadul:BAAALAADCgIIAgAAAA==.Saintly:BAAALAADCggIEgAAAA==.Sanchin:BAAALAAECgcIEAAAAA==.Sanjin:BAAALAAECgYICAABLAAECgcIEAAJAAAAAA==.Santonix:BAABLAAECoEXAAMeAAcIFxKGYwAqAQAeAAcIFxKGYwAqAQAiAAQIZQ3IaADLAAAAAA==.Satoru:BAAALAAECgIIAgAAAA==.',Sc='Schaales:BAAALAAECgcIDgAAAA==.Schimly:BAAALAADCggIFQAAAA==.Schusselbaum:BAAALAAECgEIAQAAAA==.Scimitar:BAAALAAECgUIBgAAAA==.',Se='Seijona:BAAALAADCgcIBwAAAA==.Semphora:BAAALAAECgYIDwAAAA==.Servis:BAAALAADCgYIBwABLAADCggIEAAJAAAAAA==.Seuchentîffy:BAAALAADCgEIAQAAAA==.Severuss:BAAALAADCgUIBQAAAA==.',Sh='Shadling:BAAALAADCggIJAAAAA==.Shadowfever:BAAALAAECgMIAwAAAA==.Shadowraiser:BAABLAAECoElAAIVAAgI/RUZNgA1AgAVAAgI/RUZNgA1AgAAAA==.Shalissa:BAAALAAECgQIBwAAAA==.Shalivea:BAAALAADCggICwAAAA==.Sharp:BAAALAAECgYIDQAAAA==.Shds:BAACLAAFFIEJAAIIAAMIixnIDQD8AAAIAAMIixnIDQD8AAAsAAQKgR0AAggACAj9IqALAPMCAAgACAj9IqALAPMCAAAA.Sheris:BAAALAAECgYIEQAAAA==.Sheyanne:BAAALAADCggIFQAAAA==.Shikija:BAAALAAECgQIBAAAAA==.Shirako:BAAALAAECgYICQAAAA==.Shireen:BAAALAADCgcIFwAAAA==.',Si='Sillylilly:BAAALAADCgcIDgABLAADCggIGwAJAAAAAA==.',Sl='Slig:BAAALAAECggIBQAAAA==.',Sm='Smiâgôl:BAAALAADCgcIFwAAAA==.',So='Sophiá:BAAALAADCgcIBwAAAA==.Sophié:BAAALAAECgcIDQAAAA==.',Ss='Ssuussi:BAAALAADCgUIBQAAAA==.',St='Stabbro:BAABLAAECoEdAAMaAAcIKR42EAAQAgAaAAcIUxk2EAAQAgAFAAUI9h2ZKgC6AQAAAA==.Steelmag:BAAALAADCggIHwAAAA==.Stips:BAAALAADCgcIBwAAAA==.Stitchmaster:BAAALAAECgYIDgAAAA==.Streichelzoo:BAAALAAECgQIBQAAAA==.',Su='Sukie:BAAALAAECgcIDwAAAA==.Sumatira:BAAALAAECgYIEwAAAA==.',Sw='Swapzy:BAAALAAECgIIAgAAAA==.',['Sí']='Sílvania:BAAALAADCgUIBQAAAA==.Síná:BAAALAAECgcIBwAAAA==.',Ta='Tabata:BAAALAAECgYIEgAAAA==.Takizi:BAAALAADCggICgAAAA==.Talìa:BAABLAAECoEWAAQhAAYIvx8YHAD8AQAhAAYISx0YHAD8AQAVAAIIERvzsACtAAAbAAIILRkeKACNAAAAAA==.Tamira:BAAALAADCgQIBAAAAA==.Tankdoc:BAEBLAAECoEVAAIDAAYIsR19HgDxAQADAAYIsR19HgDxAQAAAA==.Tankyhunt:BAEALAAECgYICwABLAAECgYIFQADALEdAA==.Tarelon:BAAALAADCgcIEwAAAA==.Taureypsilon:BAABLAAECoEtAAIjAAcI0iEwBQBXAgAjAAcI0iEwBQBXAgAAAA==.',Te='Tehvil:BAAALAAECgYIEQAAAA==.Tentarus:BAAALAAECgQIBgAAAA==.Terené:BAAALAADCggIAQAAAA==.Tergo:BAAALAAECgYICgAAAA==.Tes:BAAALAAECgEIAQAAAA==.Tesseract:BAAALAAECgYIBgABLAAECgYIGwABAG4jAA==.Tevihl:BAAALAADCggIFQAAAA==.',Th='Therisian:BAAALAAECgIIAgAAAA==.Thevil:BAAALAADCggIHAAAAA==.Thivel:BAAALAAECgcIEgAAAA==.',Ti='Tiegerius:BAAALAAECgYIDQAAAA==.Tigerklâue:BAAALAAECgYIBgABLAAFFAMIBwAgAM8RAA==.',Tj='Tjalf:BAAALAAECgYIEgAAAA==.Tjorpel:BAABLAAECoEdAAIcAAcIPyIlJQBhAgAcAAcIPyIlJQBhAgAAAA==.',To='Tolwyn:BAAALAADCgYICwAAAA==.Tonk:BAAALAAECgYICAAAAA==.Tornianalf:BAAALAAECgcIEwAAAA==.',Tr='Trews:BAAALAADCggIEwAAAA==.Trickilil:BAAALAADCgcIBgAAAA==.Trixii:BAABLAAECoEUAAIKAAgI+BfKPwAiAgAKAAgI+BfKPwAiAgAAAA==.Trunks:BAABLAAECoEVAAQkAAYITRVGNQB0AQAkAAYIyxRGNQB0AQAlAAQIzBOzHAAFAQAUAAMIJgIizQA+AAAAAA==.Trîxo:BAAALAAECgYIEwAAAA==.',Ts='Tschacka:BAAALAADCggIJwABLAAECgYIDgAJAAAAAA==.',Ty='Tyrlich:BAAALAADCggIIwABLAAECgYIDgAJAAAAAA==.',['Té']='Ténchi:BAAALAAECgUIBgAAAA==.Ténchí:BAABLAAECoElAAIPAAcIth50UwD/AQAPAAcIth50UwD/AQAAAA==.Téruan:BAABLAAECoEXAAICAAcITiC3OQBlAgACAAcITiC3OQBlAgAAAA==.',Un='Unholylunala:BAAALAADCggICAAAAA==.Unsolved:BAAALAADCgIIAgABLAAECgcIGQAEANEPAA==.',Up='Upps:BAAALAAECgUIBQABLAAECgYIDgAJAAAAAA==.',Us='Ushteya:BAAALAADCgIIAgAAAA==.',Va='Valishea:BAAALAADCgcICgAAAA==.Vanderstorm:BAAALAADCgcIFAAAAA==.Vargan:BAAALAAECggICAABLAAECgcIFAADAPkYAA==.',Ve='Velanya:BAAALAADCgQIAQAAAA==.',Vi='Vishael:BAABLAAECoEWAAIIAAcIjRwuMAAuAgAIAAcIjRwuMAAuAgAAAA==.Vitel:BAAALAAECggICAAAAA==.',Vl='Vlaushi:BAAALAADCggICAAAAA==.',Vo='Voidrax:BAABLAAECoEUAAMYAAYIjRsCKwCmAQAYAAYIahoCKwCmAQAWAAIIUBg2EwB7AAAAAA==.Vorteilspak:BAAALAADCgYICAABLAADCggIGwAJAAAAAA==.Voy:BAAALAAECgIIAgAAAA==.',Vy='Vylnir:BAAALAADCgcICwAAAA==.',['Vî']='Vîgør:BAAALAAECgUIBgAAAA==.',Wa='Waidla:BAAALAAECgcIDwAAAA==.Waserius:BAAALAAECgEIAQAAAA==.',Wi='Wicket:BAAALAADCgYICAAAAA==.Windgebraus:BAABLAAECoEXAAIYAAcIgxBjKwCjAQAYAAcIgxBjKwCjAQAAAA==.Wionna:BAAALAADCgcIBAAAAA==.',Xa='Xanie:BAAALAAECgcIDwAAAA==.Xarthoc:BAAALAADCggICAAAAA==.',Xe='Xeyzadrath:BAAALAAECgUIBQAAAA==.',Xi='Ximerdh:BAABLAAECoEZAAIPAAgI2w1VrwA6AQAPAAgI2w1VrwA6AQAAAA==.',Xo='Xophia:BAAALAADCgQIBAABLAAECgYIDQAJAAAAAA==.',Xt='Xtremruléz:BAAALAAECgYIDwAAAA==.',Xu='Xursana:BAAALAADCgQIBAAAAA==.',Ya='Yamatanoroch:BAAALAADCggICAAAAA==.Yasil:BAAALAAECgUIBgAAAA==.Yavan:BAABLAAECoEWAAIKAAYI9RzpcQCbAQAKAAYI9RzpcQCbAQAAAA==.',['Yò']='Yò:BAAALAADCgEIAQAAAA==.',Za='Zalaya:BAAALAADCgYIBgABLAAECgYIFgAhAL8fAA==.Zammi:BAAALAAECggIBwAAAA==.',Zi='Zidane:BAAALAADCggIFAAAAA==.',Zo='Zofira:BAAALAADCggIEAAAAA==.',Zw='Zweistein:BAAALAADCgcIBwAAAA==.',['Zò']='Zògrel:BAAALAADCgcIBwAAAA==.',['Är']='Ärtémis:BAAALAADCggIDAAAAA==.',['Äs']='Äshbringer:BAAALAAECgcICwAAAA==.',['Æl']='Ælanør:BAAALAAECgYIDQAAAA==.',['Æs']='Æscanor:BAAALAAECgQIBgAAAA==.',['Êd']='Êdesem:BAAALAAECgQIAgABLAAECggIHwANACweAA==.',['Ðr']='Ðragon:BAABLAAECoEXAAIXAAYI4gdoJQD4AAAXAAYI4gdoJQD4AAAAAA==.Ðrako:BAAALAAECgQIBAAAAA==.Ðravën:BAABLAAECoEqAAIYAAgIRRPbIAD2AQAYAAgIRRPbIAD2AQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end