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
 local lookup = {'Unknown-Unknown','Warlock-Destruction','Druid-Restoration','Hunter-BeastMastery','Mage-Arcane','Priest-Shadow','Hunter-Marksmanship','Warrior-Fury','Warrior-Protection','Druid-Balance','DemonHunter-Havoc','Shaman-Enhancement','Paladin-Retribution','Shaman-Restoration','Rogue-Subtlety','Rogue-Assassination','Warrior-Arms','Mage-Frost','Monk-Mistweaver','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Warlock-Demonology','Paladin-Protection','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','DeathKnight-Blood','Druid-Feral','Warlock-Affliction','DemonHunter-Vengeance','Rogue-Outlaw',}; local provider = {region='EU',realm='Ner’zhul',name='EU',type='weekly',zone=44,date='2025-09-25',data={Ad='Adrianna:BAAALAAECgcIEgAAAA==.',Ae='Aeternum:BAAALAAECgYIDwAAAA==.',Ak='Akyna:BAAALAAECgcICgAAAA==.',Al='Alktar:BAAALAAECgcIBwAAAA==.Allyciao:BAAALAAECgYIDAAAAA==.',An='Anübïs:BAAALAAECgIIAgAAAA==.',Ar='Arise:BAAALAADCgcIEQAAAA==.Arîana:BAAALAAECgYIBwABLAAECggIEwABAAAAAA==.',Az='Azanami:BAAALAAECggIEAAAAA==.Azoth:BAABLAAECoEVAAICAAcIaBbyRgD3AQACAAcIaBbyRgD3AQAAAA==.',Ba='Baboom:BAABLAAECoEVAAIDAAcIAQm5bQATAQADAAcIAQm5bQATAQAAAA==.Bamboklat:BAABLAAECoEhAAIEAAgIUBcvVQDqAQAEAAgIUBcvVQDqAQAAAA==.Bastet:BAAALAADCggICAABLAAECggIHQAFACQMAA==.Bazile:BAABLAAECoEdAAIFAAgIJAwBYwC+AQAFAAgIJAwBYwC+AQAAAA==.',Bi='Bigdemo:BAAALAADCggIDAAAAA==.Bigdrake:BAAALAADCgEIAQAAAA==.Bigone:BAAALAAECgYIBwAAAA==.Biothopie:BAAALAAECgYICQAAAA==.Bipodactyle:BAAALAAECggIEAAAAA==.Biproselyte:BAAALAAECgQIBAABLAAECggIEAABAAAAAA==.Biwaa:BAAALAADCgMIAwABLAAFFAMIBQAGAHgTAA==.Biwaadrood:BAAALAAECgIIAgABLAAFFAMIBQAGAHgTAA==.Biwaahunt:BAABLAAFFIEGAAIHAAII7BudFgCgAAAHAAII7BudFgCgAAABLAAFFAMIBQAGAHgTAA==.Biwaamage:BAAALAADCggICAABLAAFFAMIBQAGAHgTAA==.Biwaapriest:BAACLAAFFIEFAAIGAAMIeBMvDgDuAAAGAAMIeBMvDgDuAAAsAAQKgRYAAgYABwizH5YfAF0CAAYABwizH5YfAF0CAAAA.',Bl='Blacklagoon:BAABLAAECoEWAAMIAAgIGRtmMQBGAgAIAAgIGRtmMQBGAgAJAAYITQwDUwDtAAAAAA==.Bliitz:BAABLAAECoEfAAIHAAYI5h95JQAtAgAHAAYI5h95JQAtAgAAAA==.Bliitzdem:BAAALAADCgcIBwAAAA==.Blyyat:BAABLAAECoE4AAIKAAgIOCLRCgAIAwAKAAgIOCLRCgAIAwABLAAECgcIHwAHAOYfAA==.',Bo='Borrdi:BAAALAADCgcIBwAAAA==.',Bu='Bubulteypey:BAAALAAECgYICgABLAAFFAIICAALAL0eAA==.',Bw='Bwonsamedi:BAAALAAECggICQAAAA==.',['Bø']='Børrdi:BAAALAAECgEIAQAAAA==.',Ca='Camila:BAAALAADCggICAAAAA==.Carpouette:BAAALAAECgcIEAAAAA==.Cassien:BAAALAAECggICwAAAA==.Caxu:BAAALAAECggICwAAAA==.',Ce='Cetearyl:BAAALAAECgYIBwAAAA==.',Ch='Choupinouze:BAABLAAECoEYAAIMAAcIsh4JCgA6AgAMAAcIsh4JCgA6AgAAAA==.',Ci='Ciara:BAAALAAECggIEQAAAA==.Cik:BAAALAAECgYIBwAAAA==.',Cu='Cut:BAAALAADCggIFgAAAA==.Cutch:BAABLAAECoEZAAINAAYIIRXImQCRAQANAAYIIRXImQCRAQAAAA==.',['Cø']='Cøønan:BAAALAADCggICAAAAA==.',Da='Daerkhan:BAAALAAECgQICwAAAA==.Dafykrue:BAACLAAFFIEGAAIOAAIIUBgUKACSAAAOAAIIUBgUKACSAAAsAAQKgRwAAg4ACAiGIWMNAOgCAA4ACAiGIWMNAOgCAAAA.Dak:BAAALAADCggIFAAAAA==.Dargash:BAAALAADCgQIBAAAAA==.Darugal:BAAALAAFFAIIBAAAAA==.',De='Demønø:BAABLAAECoEcAAICAAgIEh50HgC4AgACAAgIEh50HgC4AgAAAA==.',Di='Dianaha:BAABLAAFFIEHAAIHAAII6iKSEQC9AAAHAAII6iKSEQC9AAAAAA==.',Dj='Django:BAAALAADCgYIBgAAAA==.',Do='Dobozz:BAAALAADCgYIBgAAAA==.Dohko:BAAALAAECgYIEQAAAA==.Dominas:BAAALAADCgUIBQAAAA==.',Dr='Drakay:BAAALAAECgEIAQAAAA==.Dreanessa:BAAALAADCgUIBQAAAA==.Drifer:BAACLAAFFIEWAAMPAAUI6CKHAwCbAQAPAAQIDiOHAwCbAQAQAAQIkBNpBQBVAQAsAAQKgSUAAw8ACAjgJLUCAC8DAA8ACAjZJLUCAC8DABAABwhWFf8iAPABAAAA.Drifermop:BAAALAAECggIDwABLAAFFAUIFgAPAOgiAA==.Druo:BAABLAAECoEUAAIDAAYItBnHQQCoAQADAAYItBnHQQCoAQAAAA==.Drøodix:BAAALAADCgcICwAAAA==.',Ed='Edde:BAAALAAECgcIDgAAAA==.',Ei='Eisenfaust:BAABLAAECoEdAAMRAAgIJhsdBgCMAgARAAgIJhsdBgCMAgAIAAEIfgum1QA3AAAAAA==.',Er='Erudk:BAAALAAECgcIEAAAAA==.Erupal:BAAALAADCgcIBwABLAAECgcIEAABAAAAAA==.Erzy:BAAALAADCgUIBQAAAA==.',Es='Espritdesam:BAABLAAECoEYAAMSAAcIjwlTPABfAQASAAcIjwlTPABfAQAFAAEIGwN26AAoAAAAAA==.',Et='Ethz:BAAALAAECgIIAgABLAAECgYIDAABAAAAAA==.',Ev='Evanessor:BAAALAADCgQIBAAAAA==.',Ex='Exalty:BAAALAAECgYIEAAAAA==.',Ez='Ezri:BAAALAADCggIEwAAAA==.Ezrim:BAAALAADCgEIAQAAAA==.Ezëkiele:BAAALAADCgYIBgABLAAECgcIEAABAAAAAA==.',Fa='Falorendal:BAAALAADCgQIBAAAAA==.Famifasoldo:BAAALAADCgYIBgAAAA==.',Fe='Febreze:BAACLAAFFIEIAAITAAII9SDiCQDEAAATAAII9SDiCQDEAAAsAAQKgSYAAxMACAgkH+IHANACABMACAgkH+IHANACABQABgh8BwtAAO4AAAAA.',Fl='Flökki:BAAALAAECgcICAAAAA==.',Fu='Funkystar:BAABLAAECoEiAAMVAAcI+A/JHwCoAQAVAAcI+A/JHwCoAQAWAAEIDQMSZAEfAAAAAA==.',Ge='Genødrakcide:BAAALAADCggIGQAAAA==.Geronïmo:BAAALAAECgcIEwAAAA==.Geumjalee:BAACLAAFFIEQAAIUAAUI4hj0AgC+AQAUAAUI4hj0AgC+AQAsAAQKgSAAAhQACAg4I3MHAAcDABQACAg4I3MHAAcDAAAA.',Gi='Gigui:BAAALAADCgYIAwABLAAECggIHAACABIeAA==.',Go='Gonfeï:BAAALAAECgcIEAAAAA==.Goodspeed:BAAALAAECgYIBgAAAA==.',Gr='Grantrouble:BAABLAAECoEXAAMCAAgIihQ5RwD2AQACAAgIihQ5RwD2AQAXAAEIRgjLigA0AAAAAA==.Grishnàkh:BAAALAAECggIEgAAAA==.Groumm:BAABLAAECoEfAAMQAAgILBQqIgD1AQAQAAgILBQqIgD1AQAPAAMIWQaFPQBkAAAAAA==.Grëg:BAABLAAECoEjAAIYAAcIHBJUKACIAQAYAAcIHBJUKACIAQAAAA==.',Gu='Guerrators:BAAALAADCgUIBQAAAA==.Guldhin:BAAALAAECggIEAAAAA==.Gusttox:BAAALAAECggICQAAAA==.',Ha='Haeven:BAAALAADCgcIBwAAAA==.Hauktt:BAAALAAECgYICgAAAA==.',He='Herumor:BAAALAAECggIEgAAAA==.',Ho='Hoopi:BAAALAADCggIIAAAAA==.Hopa:BAAALAADCggIHAAAAA==.Hopium:BAAALAAECgYIBgAAAA==.Hopside:BAAALAADCggIEgAAAA==.Hopso:BAAALAADCggIGAAAAA==.',Hu='Hunei:BAAALAAECggIDgAAAA==.',Hy='Hypso:BAAALAADCggIGwAAAA==.',Ig='Igalope:BAAALAAECggICAAAAA==.',Ik='Ikrahs:BAAALAAECgEIAQAAAA==.',Il='Illidalol:BAACLAAFFIEJAAILAAMI4RSfFQDpAAALAAMI4RSfFQDpAAAsAAQKgSoAAgsACAh/IfscANkCAAsACAh/IfscANkCAAAA.',It='Itersky:BAABLAAECoEiAAIFAAgIXRbpQAAtAgAFAAgIXRbpQAAtAgAAAA==.',Je='Jeandh:BAAALAADCggICQAAAA==.',Jh='Jhereg:BAAALAAECgcIBwAAAA==.',Ji='Jigsaw:BAABLAAECoEbAAIGAAYIXQ1+UQBRAQAGAAYIXQ1+UQBRAQAAAA==.Jimmy:BAAALAAECgMIBAAAAA==.',Jo='Joanna:BAABLAAFFIEHAAINAAII0SUsEwDhAAANAAII0SUsEwDhAAAAAA==.',Ka='Kamewar:BAAALAAECgYIEAAAAA==.Kamissol:BAAALAADCgEIAQAAAA==.',Kb='Kbossé:BAAALAADCggIFQAAAA==.Kboum:BAAALAADCggIEwAAAA==.',Kc='Kchair:BAAALAADCgYIBgAAAA==.',Kh='Khidra:BAAALAAECgYICwAAAA==.',Ki='Kiose:BAAALAAECgQIBAAAAA==.Kishar:BAAALAADCgQIBAAAAA==.',Kl='Klamité:BAAALAADCgcIFwAAAA==.Kleopswawa:BAAALAADCgQIBAAAAA==.Klypso:BAAALAADCgcIDQAAAA==.',Km='Kmenbert:BAAALAAECgYICwAAAA==.Kmouflé:BAAALAADCggIHQAAAA==.',Ko='Kozette:BAAALAADCggIEgAAAA==.',Kr='Krma:BAAALAADCgYIBQAAAA==.',Ks='Ksocial:BAAALAADCggIGQAAAA==.',Kt='Ktastrophe:BAAALAAECgMIBwAAAA==.',Ku='Kurùn:BAABLAAECoEfAAIZAAgIByCiDgALAwAZAAgIByCiDgALAwABLAAFFAUIEAAUAOIYAA==.',La='Lali:BAAALAADCgIIAgAAAA==.',Li='Lilydan:BAAALAAECgcIDgAAAA==.Lilyguana:BAABLAAECoEgAAMaAAgI0R2TDQDDAgAaAAgIkB2TDQDDAgAbAAgIWRMsCADWAQABLAAFFAMIEAAaAEUbAA==.Lilyzard:BAACLAAFFIEQAAMaAAMIRRt3CgAIAQAaAAMIRRt3CgAIAQAbAAEIEAjcCAA9AAAsAAQKgTQAAxoACAhpI7IEADoDABoACAhZI7IEADoDABsACAhzHQwEAHoCAAAA.Lilìth:BAAALAAECgMIAwAAAA==.Livin:BAAALAAECgcIEgABLAAECggIKwAJAMMdAA==.Lizyrio:BAACLAAFFIEJAAIcAAMI4RIfBwDSAAAcAAMI4RIfBwDSAAAsAAQKgSkAAhwACAiCFp8QABgCABwACAiCFp8QABgCAAAA.',Lo='Lomy:BAAALAAECgYIEwAAAA==.Lomÿ:BAAALAADCggIDgAAAA==.',Lu='Lunasa:BAAALAAECgYICQABLAAECggIJgAQADAcAA==.',Ly='Lyhoamnolé:BAAALAAECgEIAQAAAA==.Lyneeth:BAAALAAECgMIAwAAAA==.',['Lé']='Léolias:BAAALAAECgIIAgAAAA==.',Ma='Maggnux:BAABLAAECoEUAAIKAAYI+BqdNwCyAQAKAAYI+BqdNwCyAQAAAA==.Mallyn:BAAALAAECggICAAAAA==.Mandareen:BAABLAAECoEVAAISAAcI9gReTwAJAQASAAcI9gReTwAJAQAAAA==.Martyr:BAACLAAFFIEGAAIZAAII4BhBGwCeAAAZAAII4BhBGwCeAAAsAAQKgSYAAhkACAiMI3UJADgDABkACAiMI3UJADgDAAAA.',Me='Mekerspal:BAAALAAECgMIBAAAAA==.',Mo='Moi:BAAALAAECgEIAQABLAAFFAIICAATAPUgAA==.Molten:BAAALAAECgYIDAAAAA==.Moonlight:BAAALAAECgYICgABLAAECgYIGgAdAHIiAA==.Morgaliel:BAAALAAECgUICQAAAA==.',['Mé']='Méphie:BAABLAAECoEYAAIOAAYIuAqgtwDdAAAOAAYIuAqgtwDdAAAAAA==.',Na='Narvath:BAAALAAECgUIBQAAAA==.',Ne='Nefiria:BAAALAADCgcIDwAAAA==.Neversee:BAAALAAECgUIBQAAAA==.',Ng='Ngatsun:BAAALAAECgMIAwABLAAECgYICgABAAAAAA==.',No='Noatheneleth:BAAALAAECgcIDgAAAA==.Nonobox:BAAALAAECgYICgAAAA==.Norm:BAABLAAECoEYAAIJAAcIyBcYJQDgAQAJAAcIyBcYJQDgAQAAAA==.Notranomus:BAAALAAECgEIAQAAAA==.',['Nï']='Nïnïel:BAAALAADCgcIBwABLAAECggIHAACABIeAA==.',['Nø']='Nøphya:BAAALAADCgMIAwAAAA==.Nøün:BAAALAAECgYIBwAAAA==.',Ob='Obscurie:BAAALAAECgIIAgAAAA==.',Oc='Océya:BAAALAADCggICAAAAA==.',Og='Ogyrajiu:BAABLAAECoEpAAMYAAgISCDNCQC7AgAYAAgISCDNCQC7AgANAAUImg353QAVAQAAAA==.Ogyraju:BAABLAAECoEbAAIEAAYIBCDCSwAEAgAEAAYIBCDCSwAEAgABLAAECggIKQAYAEggAA==.',Ol='Oldguldan:BAAALAAFFAIIAgAAAA==.Olgah:BAABLAAECoEfAAIQAAcI4B3tFABmAgAQAAcI4B3tFABmAgAAAA==.',Or='Oracle:BAAALAADCggIJgAAAA==.Oroshimarru:BAAALAADCgYIBgABLAAFFAMIEAAaAEUbAA==.',Pa='Pacounet:BAABLAAECoEZAAIIAAgI1RTxOwAZAgAIAAgI1RTxOwAZAgAAAA==.Palyatiff:BAAALAAECgcIDgAAAA==.Pandemania:BAAALAAECggIEwAAAA==.',Pe='Pensé:BAAALAAECgQIBgAAAA==.Percevaal:BAABLAAECoEUAAMNAAYIFQ08wgBKAQANAAYI3gw8wgBKAQAYAAIIewpAXABIAAAAAA==.Perssone:BAAALAADCggIEgAAAA==.',Pi='Piegeaøurs:BAAALAAECgYIDAAAAA==.Piloufi:BAAALAAECgYICAAAAA==.',Po='Pompompom:BAAALAADCgcIBwABLAADCgYIBgABAAAAAA==.Poubelle:BAAALAAECgIIAgABLAAFFAIICAATAPUgAA==.Pourtoibb:BAAALAADCggICAAAAA==.',Qu='Quark:BAAALAADCgcICgAAAA==.Quyra:BAAALAAFFAIIAwAAAA==.',Ra='Ragnarorc:BAAALAADCggICAAAAA==.Razi:BAABLAAECoEaAAICAAYIRhfdWQC2AQACAAYIRhfdWQC2AQAAAA==.',Ry='Ryanthusar:BAAALAAECgQICwAAAA==.',['Rê']='Rêtbull:BAAALAAECgcIEwAAAA==.',Sa='Saprikion:BAAALAAECgYIBgAAAA==.',Se='Seclad:BAABLAAECoEUAAIJAAYIvheQLwCbAQAJAAYIvheQLwCbAQAAAA==.',Sh='Shadovia:BAAALAAFFAIIAgAAAA==.Shadowbursts:BAABLAAECoEcAAIaAAgIVhjcGABGAgAaAAgIVhjcGABGAgAAAA==.Shadowpriest:BAAALAADCgYIDAAAAA==.Shamy:BAAALAAECgUIBQAAAA==.Shangoo:BAAALAADCggICAAAAA==.Shangøo:BAAALAAECgYICgAAAA==.Sharenn:BAAALAADCggICwAAAA==.Sharkilol:BAAALAAECgMIBQAAAA==.Sharkiz:BAAALAADCggICAAAAA==.Shæmus:BAAALAAECgcICwAAAA==.',Si='Sidiouz:BAABLAAECoEcAAMCAAcIMgrDdABrAQACAAcIMgrDdABrAQAeAAIIAgNlOQA+AAAAAA==.Silentðeath:BAAALAAECgcIEwAAAA==.',Sk='Skuggor:BAABLAAECoEjAAICAAcIuR3qMABUAgACAAcIuR3qMABUAgAAAA==.',So='Solk:BAABLAAECoEYAAICAAgIMxmsOQAsAgACAAgIMxmsOQAsAgAAAA==.Sonofmorkh:BAAALAAECgYIDQAAAA==.Sorann:BAABLAAECoEaAAIdAAYIciIUDgBOAgAdAAYIciIUDgBOAgAAAA==.',Sp='Spunkmeyer:BAABLAAECoEYAAMcAAYIuBWAHAB2AQAcAAYIuBWAHAB2AQAWAAEIuwMUYgEkAAAAAA==.',St='Sticobalt:BAAALAADCggIFgAAAA==.Sticouette:BAAALAADCggIEAABLAAECgcIFwADAHwXAA==.Stix:BAAALAADCggIJAABLAAECgcIFwADAHwXAA==.Stonefree:BAAALAAECggIEgAAAA==.',Su='Sukisck:BAACLAAFFIEGAAIUAAII5BpDCwCiAAAUAAII5BpDCwCiAAAsAAQKgR0AAhQABggiINcXACYCABQABggiINcXACYCAAAA.',Sw='Swän:BAAALAAFFAEIAQAAAA==.',['Sâ']='Sâprikion:BAAALAAECgYIBgAAAA==.',Te='Tetvide:BAABLAAECoErAAMJAAgIwx0ZFgBZAgAJAAgI9hoZFgBZAgAIAAUIWyDMSwDfAQAAAA==.',Th='Thirain:BAAALAADCggICAAAAA==.',Ti='Tirauloin:BAAALAAECgcIBwABLAAECggICQABAAAAAA==.Titikaka:BAAALAADCgIIAgAAAA==.',To='Tourm:BAABLAAECoEVAAIQAAcIrQ5gMACaAQAQAAcIrQ5gMACaAQAAAA==.',Tr='Trukidemont:BAABLAAECoEcAAIfAAgIXSF/BgDnAgAfAAgIXSF/BgDnAgAAAA==.Trâfalgar:BAABLAAECoEkAAIKAAgI5yGSCQAXAwAKAAgI5yGSCQAXAwAAAA==.',['Tä']='Täräh:BAAALAAECgYIDwAAAA==.',['Tð']='Tðyæsh:BAABLAAECoEZAAIIAAgI1RWONAA4AgAIAAgI1RWONAA4AgAAAA==.',['Tø']='Tøyesh:BAAALAAECgYIDQAAAA==.Tøýesh:BAAALAADCgYIBgAAAA==.',Ur='Urielle:BAAALAADCggICAABLAAECggIEwABAAAAAA==.',Va='Valaraukar:BAAALAADCggICAABLAAECggICQABAAAAAA==.',Ve='Ved:BAABLAAECoEpAAIIAAgIkBcwMQBHAgAIAAgIkBcwMQBHAgAAAA==.Vespéro:BAABLAAECoEVAAIgAAcIMRVXCADwAQAgAAcIMRVXCADwAQAAAA==.',Vi='Viscera:BAAALAADCgUIBQAAAA==.',Vo='Voleurdemob:BAAALAAECgEIAQABLAAECggIKwAJAMMdAA==.',Wa='Wastrack:BAABLAAECoEVAAIaAAcIggy/MgB1AQAaAAcIggy/MgB1AQAAAA==.',['Wö']='Wörf:BAAALAADCgcIBwAAAA==.',['Xä']='Xämena:BAABLAAECoEVAAITAAYIGwr4LwDzAAATAAYIGwr4LwDzAAAAAA==.',Yu='Yufi:BAAALAADCgcICgAAAA==.',Ze='Zephs:BAAALAADCgYIBgAAAA==.',Zo='Zomjyroth:BAAALAAECgcIDwAAAA==.Zoulim:BAAALAADCgcIFAAAAA==.',['Ål']='Åldebaron:BAAALAAECggIEAAAAA==.',['Ðe']='Ðeathless:BAAALAAECgUIBQABLAAECgcIEwABAAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end