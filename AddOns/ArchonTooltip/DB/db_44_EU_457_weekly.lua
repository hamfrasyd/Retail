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
 local lookup = {'Paladin-Protection','DemonHunter-Havoc','Shaman-Elemental','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Monk-Windwalker','Mage-Arcane','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','DemonHunter-Vengeance','Hunter-Marksmanship','Mage-Frost','Druid-Guardian','Paladin-Retribution','Priest-Holy','Priest-Shadow','Monk-Brewmaster','Shaman-Enhancement','Paladin-Holy','Rogue-Assassination','Rogue-Subtlety','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Monk-Mistweaver','Druid-Feral','Warrior-Protection','Rogue-Outlaw','Warrior-Fury','Evoker-Augmentation','Mage-Fire','Evoker-Preservation','Warrior-Arms',}; local provider = {region='EU',realm='Nozdormu',name='EU',type='weekly',zone=44,date='2025-09-24',data={Aa='Aamun:BAAALAAECgMIAwABLAAECgcIHwABAOUXAA==.Aayla:BAAALAADCggIAQAAAA==.',Ab='Abraxâs:BAAALAAECgIIAgABLAAECgcIFQACAPsWAA==.',Ac='Accuresh:BAACLAAFFIEJAAICAAQIxguaDQAtAQACAAQIxguaDQAtAQAsAAQKgS0AAgIACAi3IX8SABEDAAIACAi3IX8SABEDAAAA.Acera:BAAALAADCgcIHQAAAA==.Achatria:BAABLAAECoEYAAMDAAYIRg/IXwBoAQADAAYIRg/IXwBoAQAEAAYIhRPffwBIAQABLAAECgcIDQAFAAAAAA==.Acidera:BAACLAAFFIEHAAIGAAUIIxnsCgDCAQAGAAUIIxnsCgDCAQAsAAQKgRcABAYACAigI2giAJsCAAYABwiIImgiAJsCAAcABQiNJbcKAO8BAAgAAQgdIkd7AFQAAAAA.Acnologia:BAAALAAECgIIAgABLAAFFAIIBQAJAI4bAA==.',Ad='Adonais:BAAALAAECgYICgABLAAECgcIHwABAOUXAA==.Adr:BAAALAAECgQIBQAAAA==.Adrfourdtone:BAABLAAECoEaAAIKAAgIhBTuQwAeAgAKAAgIhBTuQwAeAgAAAA==.',Ae='Aegón:BAAALAAECgYIDgABLAAECgcIIgAEANoTAA==.Aetheris:BAAALAAECggIDgAAAA==.Aeyla:BAAALAADCgMIAwAAAA==.',Ag='Agroholix:BAAALAADCgYIBgAAAA==.',Ak='Akanì:BAAALAAECgYICQAAAA==.',Al='Alamaîs:BAAALAAECggIEQAAAA==.Alberte:BAAALAADCgYIBwAAAA==.Alcana:BAAALAADCgUIBwAAAA==.Aldrellyn:BAABLAAECoEqAAMLAAgIwCL1CAAbAwALAAgIwCL1CAAbAwAMAAMItxsbggDUAAAAAA==.Alennya:BAAALAAECgYIBgAAAA==.Alessaná:BAAALAADCggIFwAAAA==.Algim:BAAALAAECgEIAQABLAAECggIKgALAMAiAA==.Alorora:BAAALAAECggICAAAAA==.Alutech:BAAALAADCgMIAwAAAA==.Aléxandrá:BAAALAADCgcIDgAAAA==.Alöna:BAAALAADCgYIDAAAAA==.',An='Andz:BAAALAADCgYIBgAAAA==.Anfissa:BAAALAADCggIIAAAAA==.Angeldust:BAAALAADCgYIBgAAAA==.Angerboda:BAAALAADCggICAAAAA==.Angryman:BAAALAADCggICQAAAA==.Annuia:BAABLAAECoEWAAINAAgIVCNmGgDHAgANAAgIVCNmGgDHAgABLAAFFAUIBwAGACMZAA==.Anschelin:BAAALAADCggIHgAAAA==.Antista:BAAALAADCgYIBgAAAA==.',Ap='Aphexx:BAAALAAECgUICQABLAAECggIIAALAMQlAA==.',Ar='Aramasa:BAAALAAECgcIDgAAAA==.Aratrex:BAAALAADCgcIBwABLAAECgcIHwABAOUXAA==.Ariaela:BAAALAAECgQIBgAAAA==.Aridh:BAABLAAECoEdAAIOAAgIwSRqAwAxAwAOAAgIwSRqAwAxAwAAAA==.Artaios:BAAALAAECgYIDAABLAAECgYIDAAFAAAAAA==.Artemîs:BAAALAADCggICAAAAA==.Artisan:BAAALAAECgIIAgAAAA==.Aru:BAAALAAECgYICgAAAA==.Arzandra:BAABLAAECoEsAAICAAgIbiD9FQD9AgACAAgIbiD9FQD9AgAAAA==.Aràza:BAAALAADCgcIBwAAAA==.Arôx:BAAALAADCggIDgAAAA==.',As='Ashfang:BAAALAADCgcIBwAAAA==.Ashyla:BAABLAAECoEbAAIMAAYIvR1pLwD0AQAMAAYIvR1pLwD0AQAAAA==.Asklépios:BAAALAAECgYIBgAAAA==.Asmodéus:BAAALAAECgEIAQAAAA==.Aspyria:BAAALAADCgYIBgAAAA==.Astoria:BAAALAADCggIEAAAAA==.Asura:BAABLAAECoEnAAILAAgI+B9gEQC9AgALAAgI+B9gEQC9AgAAAA==.',At='Atenae:BAAALAADCgcIBwAAAA==.Atherion:BAAALAAECgMIBwAAAA==.Atthia:BAAALAADCgcIBwAAAA==.',Au='Auros:BAABLAAECoEZAAIMAAcIcRjELgD4AQAMAAcIcRjELgD4AQAAAA==.Aurreon:BAAALAADCgIIAgAAAA==.',Av='Avadorius:BAAALAAECgYIDgAAAA==.',Az='Azasel:BAACLAAFFIEFAAIJAAIIjhvVCAC5AAAJAAIIjhvVCAC5AAAsAAQKgSgAAgkACAiWJSYBAHgDAAkACAiWJSYBAHgDAAAA.Azeroth:BAACLAAFFIEIAAIPAAII7iUjDQDeAAAPAAII7iUjDQDeAAAsAAQKgSwAAg8ACAjyJSMBAHcDAA8ACAjyJSMBAHcDAAAA.Aztia:BAAALAADCgcIEwAAAA==.',Ba='Bakyma:BAAALAADCgcIBwAAAA==.Balesebul:BAAALAADCgYIBgAAAA==.Balindal:BAAALAADCggICAAAAA==.Balinehl:BAACLAAFFIEMAAMNAAUIYhxHBwClAQANAAUIYhxHBwClAQAPAAMIoBDODwDGAAAsAAQKgSoAAw0ACAh2Jb4IADoDAA0ACAhzJb4IADoDAA8ACAgbH4cSAL8CAAAA.Bambas:BAAALAAECgIIBgAAAA==.Baragour:BAACLAAFFIEFAAMEAAMIbgqWOABzAAAEAAII4gqWOABzAAADAAMIlQEvLQBDAAAsAAQKgRgAAwMACAiOGbEgAH4CAAMACAiOGbEgAH4CAAQACAjADrFuAHIBAAAA.Baschdie:BAAALAADCggICAAAAA==.Baschdiê:BAAALAADCggICAAAAA==.Baschdíe:BAAALAAECgIIBAAAAA==.Bassiste:BAABLAAECoEjAAMKAAgI1B6eIwCqAgAKAAgI1B6eIwCqAgAQAAYI3Q1PSwAYAQAAAA==.',Be='Beastmasterr:BAAALAAECgYICwAAAA==.',Bi='Bieraculix:BAAALAADCgcIBwAAAA==.Bierbier:BAAALAADCggIEAABLAAECgcIGgARAOgYAA==.Bigarty:BAAALAADCgcIDAAAAA==.Birgitte:BAAALAAECggIBwAAAA==.',Bl='Blasted:BAABLAAECoEfAAMBAAcI5Rd3GgDuAQABAAcI5Rd3GgDuAQASAAQIPwvI/QC7AAAAAA==.Blint:BAABLAAECoEbAAMTAAgIrCJxCQAPAwATAAgIrCJxCQAPAwAUAAcI3RspLgD4AQAAAA==.Bloodtwister:BAAALAADCggICgAAAA==.Bloodyfamas:BAABLAAECoEdAAMBAAcIvBgfGQD6AQABAAcIvBgfGQD6AQASAAYIDAYs7QDmAAAAAA==.Blura:BAAALAADCggIDgAAAA==.',Bo='Bogga:BAAALAAECgMIBwAAAA==.Boomyftw:BAABLAAECoEgAAILAAgIxCVkBgA8AwALAAgIxCVkBgA8AwAAAA==.Boosty:BAAALAADCggIFQAAAA==.',Br='Bramsalia:BAAALAADCggIDgAAAA==.Bramy:BAAALAAECgEIAwAAAA==.Brenna:BAAALAAECgcIEgAAAA==.Brewdaddy:BAABLAAECoEWAAMJAAgIog4fKwB5AQAJAAgIog4fKwB5AQAVAAYIFgDgRgACAAAAAA==.Brotbox:BAAALAADCgYIBwAAAA==.Brudertikal:BAAALAAECgcIEQAAAA==.Bryce:BAAALAADCggIJQAAAQ==.',Bs='Bsuff:BAABLAAECoEXAAIWAAcIqQ81EQCrAQAWAAcIqQ81EQCrAQAAAA==.',Bu='Buddâ:BAAALAAECgUIBwAAAA==.Buffhunter:BAAALAADCgQIBAAAAA==.Bumbledore:BAAALAAECgUIBQAAAA==.Butzi:BAAALAAECgUICgAAAA==.Butzilla:BAAALAAECgYIEQAAAA==.Butzinator:BAAALAAECgYIEAAAAA==.Butzlee:BAAALAAECgcIEwAAAA==.',['Bâ']='Bâlín:BAAALAADCgUICgAAAA==.',['Bä']='Bärbél:BAAALAADCggICAABLAAFFAUIDQAXAKoOAA==.',['Bè']='Bèth:BAACLAAFFIEJAAMYAAQIggx1CwDjAAAYAAMI6A91CwDjAAAZAAII+QG+EQB3AAAsAAQKgSEAAxgACAjFIPoPAJoCABgACAjFIPoPAJoCABkAAwiqBfI9AFkAAAAA.',['Bö']='Böngchen:BAAALAAECgIIAwABLAAECgMIAQAFAAAAAA==.',Ca='Caeles:BAAALAADCggICAAAAA==.Calliera:BAABLAAECoEaAAMSAAcIzCJJRgA/AgASAAcIzCJJRgA/AgABAAIIcB7mRwCuAAAAAA==.Carrywurst:BAAALAADCggICAAAAA==.Casahexer:BAAALAADCgUIBQABLAAECgcIEQAFAAAAAA==.Casamausi:BAAALAADCggICwABLAAECgcIEQAFAAAAAA==.Casamolo:BAAALAADCggIFgABLAAECgcIEQAFAAAAAA==.Casarelis:BAAALAAECgcIEQAAAA==.Cattie:BAABLAAECoEVAAIQAAcIhgeSTQAMAQAQAAcIhgeSTQAMAQAAAA==.',Ce='Cereals:BAAALAAECgcIEwAAAA==.',Ch='Chace:BAABLAAECoEUAAMNAAYIFiKPPAAtAgANAAYIvh+PPAAtAgAPAAYI3h5wNADTAQABLAAFFAQICAAPAEUcAA==.Chainhealz:BAAALAADCggICAAAAA==.Charlieze:BAAALAAECgIIAgAAAA==.Chie:BAAALAADCggICAAAAA==.Chilipepper:BAAALAAECgYICQAAAA==.Choper:BAAALAADCgcICQAAAA==.',Cl='Claricé:BAAALAAECgEIAQAAAA==.',Co='Confused:BAAALAAECggICAAAAA==.Cooldown:BAABLAAECoEdAAIQAAgI0Ry4DQCnAgAQAAgI0Ry4DQCnAgAAAA==.Coolfire:BAAALAAECgIIBQAAAA==.Coronna:BAAALAADCgcIDAAAAA==.Cowalski:BAAALAADCggIDwAAAA==.',Cr='Crepsley:BAAALAAECggICAAAAA==.Crossar:BAAALAADCgYIBgAAAA==.Cruz:BAAALAAECgIIAgABLAAFFAUIEwAKAJcfAA==.Crónck:BAAALAADCgcIBwAAAA==.',['Cá']='Cásius:BAACLAAFFIEGAAIMAAIIqBETIACMAAAMAAIIqBETIACMAAAsAAQKgSEAAgwACAjNIs0FACIDAAwACAjNIs0FACIDAAAA.',Da='Dalila:BAAALAAECgEIAgAAAA==.Dally:BAABLAAECoEvAAIMAAgIdR5TEQCuAgAMAAgIdR5TEQCuAgAAAA==.Daradur:BAAALAADCggIKgAAAA==.Darkaan:BAAALAAECgIIAQAAAA==.Darkmidnight:BAABLAAECoEUAAMaAAYIARMCqAB7AQAaAAYIARMCqAB7AQAbAAQI2QhIPADIAAAAAA==.Darzul:BAAALAADCgYIDAABLAAECgIIBgAFAAAAAA==.',De='Dejtwelf:BAAALAAECgEIAQAAAA==.Delya:BAAALAADCggICAAAAA==.Deviloso:BAAALAAECgYIBgAAAA==.',Dj='Djosa:BAAALAADCggIIgABLAAECgQIDAAFAAAAAA==.',Do='Docglobuli:BAAALAAECgYIDwAAAA==.Doppelkorn:BAAALAAECgIIAgAAAA==.',Dr='Drahauctyr:BAABLAAECoEeAAIcAAgIKhHlJADVAQAcAAgIKhHlJADVAQABLAAECggILAAdAHsPAA==.Draxya:BAAALAADCggICgABLAAECgUIDwAFAAAAAA==.Dreez:BAABLAAECoEdAAIPAAcI4Rq4IwA2AgAPAAcI4Rq4IwA2AgAAAA==.Dreza:BAAALAAECgIIAgAAAA==.Drmiagi:BAABLAAECoErAAIJAAgIkBxTEAB7AgAJAAgIkBxTEAB7AgAAAA==.Drumshot:BAABLAAECoElAAIPAAgIjh1GFgCeAgAPAAgIjh1GFgCeAgAAAA==.',Du='Durmm:BAAALAADCgQIBwABLAAECgUIDwAFAAAAAA==.',['Dé']='Déàdpool:BAAALAAECgIIAgAAAA==.',Ed='Edigna:BAAALAAECgEIAQAAAA==.',Ei='Eiluna:BAAALAAECgcIEwAAAA==.Eisenherz:BAAALAAECggICAAAAA==.',El='Elanis:BAACLAAFFIEGAAIeAAIItxmGCAChAAAeAAIItxmGCAChAAAsAAQKgSYAAh4ACAiAIigEABgDAB4ACAiAIigEABgDAAAA.Elanys:BAAALAAECgYIBgAAAA==.Elexiah:BAAALAAECgIIAwAAAA==.Elizaveta:BAAALAAECgUIDwAAAA==.Elmador:BAABLAAECoEoAAIfAAgILiB/DADBAgAfAAgILiB/DADBAgAAAA==.Elnaror:BAABLAAECoEZAAIEAAcI1xbsUgC9AQAEAAcI1xbsUgC9AQAAAA==.Elunia:BAAALAAECgQICAAAAA==.Elydea:BAABLAAECoEeAAICAAgIHBZQQwAvAgACAAgIHBZQQwAvAgAAAA==.Elísabeth:BAAALAAECgQIBgAAAA==.',Em='Em:BAAALAADCggICAAAAA==.',En='Enedrai:BAABLAAECoEaAAIgAAcIxxEyCQDSAQAgAAcIxxEyCQDSAQAAAA==.Engellisa:BAAALAADCggICQAAAA==.',Er='Erozion:BAABLAAECoEVAAIDAAgIlSCvFADWAgADAAgIlSCvFADWAgAAAA==.Erunax:BAAALAADCggIDgAAAA==.',Eu='Eulenmania:BAAALAADCgYIBgAAAA==.',Ev='Evalena:BAAALAADCggIDgAAAA==.',Ey='Eyru:BAAALAAECgYIDAAAAA==.',Fa='Falox:BAAALAAECgUICAAAAA==.Faoron:BAAALAAECgIIAgABLAAECgcIHAAaAKsgAA==.Fapf:BAABLAAECoEfAAIMAAcIyRjkLAABAgAMAAcIyRjkLAABAgAAAA==.',Fe='Ferukh:BAABLAAECoEoAAIeAAgI3htXCgCKAgAeAAgI3htXCgCKAgAAAA==.Feuerkiesel:BAEALAADCggICAAAAA==.Feura:BAABLAAECoEUAAMIAAYIYBvtHgDqAQAIAAYIYBvtHgDqAQAGAAEIKgfw4AApAAAAAA==.',Fi='Fizzbolt:BAAALAADCggIEAAAAA==.',Fl='Flokì:BAABLAAECoEcAAIhAAgIuRgfVAC9AQAhAAgIuRgfVAC9AQABLAAECggIHgACABwWAA==.Fluki:BAAALAADCggIDwABLAAECgQICAAFAAAAAA==.',Fr='Freezio:BAABLAAECoEtAAISAAgIryGIGAD5AgASAAgIryGIGAD5AgAAAA==.Fridericus:BAAALAAFFAIIAgAAAA==.Frostyscrews:BAAALAAECggIBQAAAA==.',Fu='Fublue:BAABLAAECoEUAAIEAAYIvhSnbwBvAQAEAAYIvhSnbwBvAQAAAA==.Fumiel:BAAALAAECgMIBwAAAA==.',['Fé']='Féâgh:BAABLAAECoEfAAIYAAgIhyByCQDmAgAYAAgIhyByCQDmAgAAAA==.',['Fí']='Fíréfly:BAAALAAECgYIEwAAAA==.',['Fï']='Fïre:BAAALAADCggIEAAAAA==.',Ga='Gawki:BAAALAADCggIDwAAAA==.',Ge='Gemrock:BAAALAAECgYIEwAAAA==.',Gg='Ggwp:BAAALAAECgIIAgAAAA==.',Gl='Glaimdal:BAAALAADCggICgAAAA==.',Go='Golgothan:BAAALAADCggICAABLAADCggICAAFAAAAAA==.Goner:BAABLAAECoEYAAIhAAgIHRzAIQCXAgAhAAgIHRzAIQCXAgAAAA==.Gothós:BAAALAADCggIFgABLAAECgcIIgAEANoTAA==.Gouzu:BAAALAAECggICAAAAA==.',Gr='Gramosch:BAABLAAECoEUAAIhAAgIghWzQQD8AQAhAAgIghWzQQD8AQAAAA==.Grauefrau:BAAALAAECgYIEAAAAA==.Greyeagle:BAACLAAFFIEMAAITAAUIEBolBADaAQATAAUIEBolBADaAQAsAAQKgS4AAhMACAgYH8oQAMsCABMACAgYH8oQAMsCAAAA.Grimsel:BAAALAAECgYIBgAAAA==.',Gu='Gullprime:BAAALAAECggICAAAAA==.Gungfu:BAAALAADCggIDwABLAAECgcIGgAUAHAWAA==.Guts:BAABLAAECoEeAAIfAAgI0CPoBQAjAwAfAAgI0CPoBQAjAwAAAA==.',['Gé']='Gérard:BAAALAAECggIEQABLAAFFAIIBQAJAI4bAA==.',Ha='Haroshi:BAABLAAECoEYAAIDAAgIOg8gUACcAQADAAgIOg8gUACcAQAAAA==.Haumonkey:BAABLAAECoEsAAIdAAgIew/KHACbAQAdAAgIew/KHACbAQAAAA==.Haxes:BAAALAAECgIIBAAAAA==.Haxxork:BAABLAAECoEVAAICAAYI8BNukQB2AQACAAYI8BNukQB2AQAAAA==.',He='Healcouch:BAAALAAECgEIAQAAAA==.Healtax:BAAALAAECgMIBQAAAA==.Heffertonne:BAACLAAFFIEFAAIQAAIIHhjXDgCMAAAQAAIIHhjXDgCMAAAsAAQKgR8AAhAACAjzIZsKANYCABAACAjzIZsKANYCAAAA.Heftîe:BAAALAADCgcIBwAAAA==.Heillin:BAAALAAECgIIAgAAAA==.',Hi='Hinatâ:BAAALAAECggICAAAAA==.Hiwani:BAAALAAECgYIDAAAAA==.',Ho='Hoholy:BAABLAAECoEnAAIUAAgI3R/6DgDqAgAUAAgI3R/6DgDqAgAAAA==.Holgerson:BAAALAADCggICAAAAA==.Hothanatos:BAEBLAAECoEfAAIXAAgI1go4LgCHAQAXAAgI1go4LgCHAQAAAA==.',Hu='Huetti:BAABLAAECoEaAAIhAAgI0yA9FADyAgAhAAgI0yA9FADyAgAAAA==.Huettî:BAABLAAECoEVAAMPAAcI8xY4TQBnAQAPAAcI8xY4TQBnAQANAAIIQw2q/ABkAAAAAA==.',Hy='Hyjazinth:BAAALAADCggIHwAAAA==.Hyouka:BAAALAAECgIIAgABLAAECggIKAAeAN4bAA==.',['Hé']='Hédges:BAAALAAECgcICwAAAA==.',['Hî']='Hîrnschaden:BAABLAAECoEdAAIZAAcIaBM8FwC3AQAZAAcIaBM8FwC3AQAAAA==.',['Hü']='Hühnerbrühe:BAAALAAECgEIAQAAAA==.',Il='Ilidaria:BAAALAAECgcIDwAAAA==.Illidias:BAABLAAECoEZAAICAAcI0R68LACFAgACAAcI0R68LACFAgAAAA==.',Im='Impaza:BAAALAAECgYIDAABLAAFFAUIEwAKAJcfAA==.',Ir='Ir:BAAALAAECggIBgAAAA==.',Is='Isilios:BAAALAAECgcIEQAAAA==.Istas:BAAALAAECgYIBgABLAAFFAQICAAPAEUcAA==.',Iy='Iyaary:BAAALAADCgcIDgAAAA==.',Ja='Jabder:BAAALAADCgcICQAAAA==.Janbo:BAAALAAECgYICAAAAA==.Jandeny:BAAALAADCggIFgAAAA==.',Je='Jemhadar:BAABLAAECoEYAAIEAAYIcx08PwD5AQAEAAYIcx08PwD5AQAAAA==.',Ji='Jinxta:BAAALAAECgEIAQAAAA==.Jinxîe:BAAALAADCgIIAgAAAA==.',Jo='Johannes:BAAALAADCggICAAAAA==.Jondk:BAAALAAECggIDAAAAA==.Jonshami:BAAALAAECggIBQAAAA==.',['Já']='Jándry:BAAALAAECgYICQAAAA==.',['Jä']='Jägerhans:BAAALAADCgQIBwAAAA==.',Ka='Kaaya:BAAALAAECgIIAwAAAA==.Kado:BAAALAADCgYIBgABLAAECgcIBwAFAAAAAA==.Kaede:BAAALAADCgcIBwAAAA==.Kaidaria:BAAALAADCggIDQAAAA==.Kaiju:BAAALAADCgYIBgAAAA==.Kalestrasza:BAAALAAECgEIAQAAAA==.Kalishtra:BAAALAAECgYIDAAAAA==.Kalissra:BAABLAAECoEnAAMiAAgIWyEQAQAnAwAiAAgIWyEQAQAnAwAcAAgIgBihGQA6AgAAAA==.Kamikaze:BAAALAAECgIIAwAAAA==.Kamizuka:BAABLAAECoEUAAIhAAYIMRorTQDTAQAhAAYIMRorTQDTAQAAAA==.Kampfkrümel:BAABLAAECoEVAAICAAcI+xZTZwDMAQACAAcI+xZTZwDMAQAAAA==.Karalas:BAAALAADCgYIBgABLAAECgUIBgAFAAAAAA==.Kasi:BAAALAAECgcIBwAAAA==.Kastjel:BAAALAADCgYICAABLAAECgQIDAAFAAAAAA==.Katriana:BAABLAAECoEVAAMHAAYI6AxJGQAbAQAGAAYIoAvwgABEAQAHAAYI3wdJGQAbAQAAAA==.Katsumi:BAAALAAECgcIEQAAAA==.',Ke='Kellsor:BAAALAAECgcIDwAAAA==.Kelzur:BAAALAAECgMIBAAAAA==.',Ki='Kichilora:BAAALAADCgEIAQAAAA==.Kieze:BAAALAAECgEIAQAAAA==.Kikky:BAAALAAECgIIAgAAAA==.Kimaty:BAABLAAECoEUAAMGAAYIxR1UXACoAQAGAAYIBhxUXACoAQAIAAMIjRfcaACbAAAAAA==.Kimáty:BAAALAADCgYIBwABLAAECgYIFAAGAMUdAA==.',Kl='Kl:BAAALAADCgQIBAABLAAFFAIICAAMAC8mAA==.Klein:BAAALAADCggICAAAAA==.Kleinmonk:BAAALAADCgEIAQAAAA==.',Ko='Kohaai:BAAALAAECgYICwABLAAECgcIIwACAPgiAA==.Kontos:BAAALAADCggICQAAAA==.Koohhai:BAABLAAECoEjAAICAAcI+CLwIgC1AgACAAcI+CLwIgC1AgAAAA==.Koryu:BAAALAAECggICAAAAA==.',Kr='Krata:BAAALAADCgcICwAAAA==.Kriegshamm:BAAALAAECggICAAAAA==.Krisna:BAAALAAECgMIAwAAAA==.',Ky='Kyura:BAAALAAECgQIBgAAAA==.',['Kà']='Kàyona:BAAALAADCgcIDQAAAA==.',['Ká']='Káyona:BAABLAAECoEWAAIUAAcIxiGzIQBJAgAUAAcIxiGzIQBJAgAAAA==.',['Kï']='Kïkk:BAAALAADCggICAAAAA==.',La='Laertes:BAABLAAECoEZAAITAAgIfwmAUABwAQATAAgIfwmAUABwAQAAAA==.Larissandra:BAAALAADCggIDQAAAA==.Lassandria:BAAALAADCggICQAAAA==.Laurelin:BAACLAAFFIENAAIXAAUIqg5gBwAqAQAXAAUIqg5gBwAqAQAsAAQKgS8AAxcACAjYHzkPAHoCABcACAjYHzkPAHoCABIABgj4C9nGADkBAAAA.Lazahr:BAAALAAECgYIDAAAAA==.',Le='Lechucky:BAAALAAECgcIDAABLAAFFAUIDQAXAKoOAA==.Leogen:BAAALAAECgQIBAAAAA==.Leonica:BAAALAADCgYIBAABLAAECggIKAAeAN4bAA==.Leovince:BAABLAAECoEYAAIDAAgIKR8nFQDTAgADAAgIKR8nFQDTAgAAAA==.Leuchte:BAAALAAECgMIAwAAAA==.Leyda:BAAALAAECgYIDAAAAA==.',Li='Lisann:BAAALAAECgYIDwAAAA==.Lizù:BAABLAAECoEmAAIDAAgIdRuLHQCTAgADAAgIdRuLHQCTAgAAAA==.',Lo='Loleinkeks:BAAALAAECgMIAwAAAA==.Lollipopp:BAAALAADCgYIBQAAAA==.',Lu='Luinel:BAAALAAECgMIAwAAAA==.Lukára:BAACLAAFFIEHAAINAAIILRBuNQCCAAANAAIILRBuNQCCAAAsAAQKgSUAAw0ACAi5Gzs/ACQCAA0ACAi5Gzs/ACQCAA8ABAi9C+CFAJ8AAAAA.Lumpo:BAAALAAECgIIAgAAAA==.Lumînon:BAAALAAECgMIAwAAAA==.Lunarios:BAAALAAECgYIDwAAAA==.Lupiling:BAAALAADCggIEAAAAA==.',Ly='Lyla:BAABLAAECoEVAAILAAgIshWqJAAWAgALAAgIshWqJAAWAgAAAA==.Lyncis:BAAALAADCgQIBAABLAAECgcIDQAFAAAAAA==.Lyngar:BAAALAAECgUIDgAAAA==.',['Lê']='Lêgôlass:BAAALAADCggIHQAAAA==.Lêonix:BAAALAAECgcIDAAAAA==.',Ma='Maerodk:BAAALAADCgcIDwAAAA==.Magdalene:BAAALAADCgUIBwAAAA==.Magichar:BAAALAADCggIFQAAAA==.Majirella:BAAALAADCgIIAgAAAA==.Maldir:BAAALAAECggIDwAAAA==.Marfa:BAAALAADCggICAAAAA==.Marliea:BAAALAADCgYIBgAAAA==.Marsilia:BAAALAADCggIHAAAAA==.Martelbarrt:BAAALAADCggIDwAAAA==.Marul:BAAALAAECgcIEAAAAA==.Mautzzi:BAAALAAECgYIDAAAAA==.Maveríc:BAAALAADCggIEAAAAA==.Mawexx:BAAALAADCgcIBwABLAAECggIJwAKACAbAA==.',Mc='Mctoken:BAAALAAECgMIAwABLAAFFAIICQATAEomAA==.',Me='Melisashunt:BAAALAAECgIIAgAAAA==.Merch:BAAALAAECgIIAgAAAA==.Metaar:BAABLAAECoEZAAMWAAcIIBhZDgDeAQAWAAcIIBhZDgDeAQADAAEIVAoAAAAAAAAAAA==.Methanol:BAACLAAFFIEJAAITAAIISiaXEQDfAAATAAIISiaXEQDfAAAsAAQKgSsAAhMACAhcJtEAAH8DABMACAhcJtEAAH8DAAAA.',Mi='Milkaselnuss:BAAALAAECgUIBgAAAA==.Milèèna:BAAALAAECgMIAwABLAAECgQIDAAFAAAAAA==.Mirrì:BAAALAADCgYIBgAAAA==.Misschaotica:BAAALAAECggIEAAAAA==.Missmandy:BAACLAAFFIEKAAIBAAMIeRpvBAAGAQABAAMIeRpvBAAGAQAsAAQKgSgAAgEACAg8JMgCAE8DAAEACAg8JMgCAE8DAAAA.Miwa:BAAALAAECgMIAwAAAA==.Miyuko:BAABLAAECoEdAAMTAAcI4h9gKQAkAgATAAcI4h9gKQAkAgAUAAEIOQvFhwA7AAAAAA==.Mizutsune:BAABLAAECoEVAAIKAAcIjwq3dQCHAQAKAAcIjwq3dQCHAQABLAAECggIKAAeAN4bAA==.',Mo='Mogaro:BAAALAAECggICAAAAA==.Mondstaub:BAAALAAECgIIAwAAAA==.Mooladin:BAAALAAECgYIDwAAAA==.Morb:BAAALAAECgEIAQAAAA==.Mototimbo:BAAALAADCgMIAwAAAA==.',Mu='Mudoron:BAABLAAECoErAAIXAAgIxA6ZKQCjAQAXAAgIxA6ZKQCjAQAAAA==.Mupharl:BAAALAAECggIDgAAAA==.Muskat:BAAALAADCgYIBgAAAA==.Mustafar:BAABLAAECoEUAAIWAAgIqRlnBwB7AgAWAAgIqRlnBwB7AgAAAA==.Mustang:BAAALAADCgMIAgAAAA==.',My='Myli:BAAALAAECgQIBAAAAA==.',['Má']='Márídá:BAAALAAECgMIBQAAAA==.',['Mä']='Männlein:BAAALAAECgQICQAAAA==.',['Mè']='Mèrcý:BAABLAAECoEgAAITAAgIyxplFwCWAgATAAgIyxplFwCWAgAAAA==.',['Mê']='Mêxer:BAAALAADCgEIAQAAAA==.',['Mö']='Möve:BAABLAAECoEnAAIKAAgIIBuCNgBTAgAKAAgIIBuCNgBTAgAAAA==.Mövä:BAAALAAECgUIBQABLAAECggIJwAKACAbAA==.',Na='Nachen:BAAALAADCgcIBwAAAA==.Nairá:BAABLAAECoEaAAILAAcIpxOeNAC7AQALAAcIpxOeNAC7AQAAAA==.Napoleone:BAACLAAFFIEIAAIXAAUIigmXBQB4AQAXAAUIigmXBQB4AQAsAAQKgS4AAhcACAiKG2sOAIICABcACAiKG2sOAIICAAAA.Nathare:BAABLAAECoEaAAIRAAcI6BgVCwD7AQARAAcI6BgVCwD7AQAAAA==.Natháel:BAAALAAECgMIBgAAAA==.Nayoki:BAABLAAECoEjAAIJAAcIoSG6FgAtAgAJAAcIoSG6FgAtAgAAAA==.Nayu:BAABLAAECoEkAAIJAAcILSFXDgCVAgAJAAcILSFXDgCVAgAAAA==.Nayus:BAAALAAECgYIDgAAAA==.',Ne='Nefi:BAAALAADCgMIAwAAAA==.Nehlux:BAAALAAECgMIBgABLAAFFAUIDAANAGIcAA==.Nelwan:BAAALAADCggIDwABLAAFFAIIBQAGAEYfAA==.Nemeia:BAABLAAECoEXAAINAAYIqAS/0QDQAAANAAYIqAS/0QDQAAAAAA==.Neylora:BAABLAAECoEqAAIUAAgI1BCBLwDxAQAUAAgI1BCBLwDxAQAAAA==.Neyugi:BAABLAAECoEwAAIeAAgIGSUfAgBMAwAeAAgIGSUfAgBMAwAAAA==.',Ni='Nibbles:BAABLAAECoEVAAIdAAYIYBHKJgA5AQAdAAYIYBHKJgA5AQAAAA==.Nigma:BAAALAADCgcIDQABLAAECgIIBgAFAAAAAA==.Nikarah:BAAALAAECggIBAAAAQ==.Nilopheus:BAAALAADCggIEwAAAA==.',No='Noadras:BAAALAAECgYICAAAAA==.Norem:BAAALAADCgQIBAAAAA==.Noxxa:BAAALAAECgYIBgABLAAECgcIHwABAOUXAA==.',Nu='Nukeprime:BAACLAAFFIETAAIKAAUIlx9gBgAAAgAKAAUIlx9gBgAAAgAsAAQKgSUAAwoACAipI2kSAAYDAAoACAipI2kSAAYDABAAAgiNGnZuAGoAAAAA.Numeriê:BAABLAAECoEUAAIPAAYIuiGIIABMAgAPAAYIuiGIIABMAgAAAA==.Nuur:BAAALAADCgIIAgABLAAECgUIBQAFAAAAAA==.',Ny='Nyphai:BAACLAAFFIEFAAIEAAIIMQ1/OgBxAAAEAAIIMQ1/OgBxAAAsAAQKgR8AAgQACAiiGocwACwCAAQACAiiGocwACwCAAAA.Nyra:BAAALAAECgYIEQABLAAECggIJgAXAIIaAA==.',['Né']='Nésquik:BAAALAAECgMIAwAAAA==.',['Nö']='Nösianna:BAACLAAFFIEKAAIEAAUIggy3CABNAQAEAAUIggy3CABNAQAsAAQKgS4AAgQACAhOHbMhAGsCAAQACAhOHbMhAGsCAAAA.',Oc='Oceanic:BAAALAAECggIEAAAAA==.Oceanica:BAAALAAECgIIBAAAAA==.',Op='Ophioneus:BAAALAADCgMIAwAAAA==.',Os='Osarya:BAABLAAECoEnAAMjAAgI/B74AQDYAgAjAAgI/B74AQDYAgAKAAEIOgjX4gAuAAAAAA==.',Ot='Otis:BAAALAADCggIEAAAAA==.',Pa='Paddington:BAAALAAECggICAAAAA==.Paduan:BAABLAAECoEoAAINAAgILSUwCAA/AwANAAgILSUwCAA/AwAAAA==.Paladinenser:BAABLAAECoEcAAISAAgIFyG6FgADAwASAAgIFyG6FgADAwAAAA==.Parker:BAAALAAECgYIDAAAAA==.',Pe='Petratt:BAACLAAFFIELAAICAAMIxyJkDQAwAQACAAMIxyJkDQAwAQAsAAQKgS4AAgIACAjCJPUGAFgDAAIACAjCJPUGAFgDAAAA.',Ph='Pheyphey:BAAALAAECgEIAgAAAA==.Philanthrop:BAAALAAECgcIBwAAAA==.',Pi='Pinkdrache:BAAALAAECgMIBQAAAA==.Piupeew:BAAALAADCggICAAAAA==.',Pl='Pladion:BAAALAADCgQIBAAAAA==.Pluto:BAAALAADCggIFwABLAADCggIJQAFAAAAAA==.',Pr='Pradbitt:BAABLAAECoEdAAIhAAcIux86KwBfAgAhAAcIux86KwBfAgAAAA==.',Pu='Punch:BAAALAAECgIIAgAAAA==.',Py='Pyb:BAABLAAECoEVAAMOAAcI5BJfIQBxAQAOAAcICxFfIQBxAQACAAQIeBaIzgDxAAAAAA==.',Ra='Rafsa:BAAALAADCgQIBwAAAA==.Ralisso:BAAALAADCggICAAAAA==.Ranoria:BAAALAADCggICAAAAA==.Raphtari:BAAALAADCggIEAAAAA==.Rapwnzl:BAAALAAECggICAAAAA==.Raqueli:BAAALAADCggIGwABLAADCggIJQAFAAAAAA==.Rawsauce:BAABLAAECoEaAAICAAcIRxnYVgD1AQACAAcIRxnYVgD1AQAAAA==.Rayneshia:BAAALAADCgYIBgAAAA==.Raíd:BAAALAAFFAIIAgAAAA==.',Re='Rebekah:BAACLAAFFIEHAAIPAAIIwhhYFwCZAAAPAAIIwhhYFwCZAAAsAAQKgSIAAg8ACAg3G+khAEMCAA8ACAg3G+khAEMCAAAA.Recýclerin:BAAALAADCgUIBQAAAA==.Redarrow:BAAALAADCgUIBQAAAA==.Redb:BAAALAAECgQIDAAAAA==.Redtearz:BAAALAAECgYIEAAAAA==.Remedium:BAAALAAECgQIBAAAAA==.Retributzion:BAAALAAECgYIDgAAAA==.Retrïbutiðn:BAAALAAECgIIAgAAAA==.',Ri='Riesenrohr:BAAALAAECgYIBwAAAA==.Rimuhu:BAACLAAFFIEJAAILAAQIWiPaBQCIAQALAAQIWiPaBQCIAQAsAAQKgSEAAgsACAiOJoICAG8DAAsACAiOJoICAG8DAAAA.Rimuru:BAAALAADCgcIBwAAAA==.',Ro='Roderric:BAABLAAECoEdAAISAAgI+xuwJgCyAgASAAgI+xuwJgCyAgAAAA==.Rogueedition:BAAALAADCgMIAwAAAA==.Rolarion:BAAALAADCggICAAAAA==.Romeo:BAAALAAECgQIBAAAAA==.Rosalindé:BAAALAADCggICAAAAA==.',Ru='Ruin:BAACLAAFFIEKAAIUAAQIPBjwCABUAQAUAAQIPBjwCABUAQAsAAQKgSoAAhQACAioIvsJABkDABQACAioIvsJABkDAAAA.',Ry='Rykêr:BAAALAADCggIDgABLAAECgcIFQACAPsWAA==.',['Râ']='Râvenna:BAAALAAECgcIEQAAAA==.',Sa='Saleanor:BAAALAADCgcICgAAAA==.Samoná:BAAALAAECgIIBgAAAA==.Sanirana:BAAALAADCggIDAAAAA==.Sarox:BAAALAAECgYIDgAAAA==.Savadix:BAAALAAECgYIEwAAAA==.Sayana:BAAALAAECggIDgAAAA==.',Sc='Scardoz:BAAALAADCgQIBAAAAA==.Schamrech:BAAALAAECgUIBgAAAA==.',Se='Seigi:BAAALAAECgEIAQAAAA==.Selis:BAAALAAECgMIBQAAAA==.Selmah:BAAALAAECgYIBgABLAAECgYIBwAFAAAAAA==.Semyda:BAAALAAECgYIBgAAAA==.Serâs:BAAALAAECgIIAwAAAA==.',Sh='Shaladar:BAAALAADCgcIBwAAAA==.Shanjala:BAABLAAECoEaAAMUAAcIcBbJLgD1AQAUAAcIcBbJLgD1AQATAAEIuCFklgBmAAAAAA==.Shareya:BAAALAAECgIIBwAAAA==.Shazzu:BAAALAADCggICAAAAA==.Sherona:BAAALAAECgYICQAAAA==.Shidoh:BAABLAAECoEmAAMYAAgIOyTqAgBGAwAYAAgIOyTqAgBGAwAZAAMIBhOGMwCwAAAAAA==.Shiipriest:BAAALAADCgcICwABLAAFFAIIBQAdAP0UAA==.Shiishaman:BAAALAAECgUIBgABLAAFFAIIBQAdAP0UAA==.Shinano:BAABLAAECoEfAAMiAAgIxxIDCADQAQAcAAgIyBELJQDUAQAiAAcI0RIDCADQAQAAAA==.Shiningx:BAAALAADCgcIBwAAAA==.Shinyhunter:BAAALAADCgYICwAAAA==.Shocksur:BAAALAADCggICAABLAAECgYIBwAFAAAAAA==.Shuani:BAAALAAECgUIBwAAAA==.Shyon:BAAALAADCgQIAwAAAA==.Sháx:BAAALAAECgYICAABLAAECgcIHwABAOUXAA==.Shârona:BAAALAADCgcIBwAAAA==.',Si='Sickbooy:BAAALAADCgcICAAAAA==.Sidonia:BAAALAADCggICAABLAAECgcIGgAUAHAWAA==.Sinilga:BAAALAADCggIJQAAAA==.Sirblack:BAABLAAECoEmAAISAAgIJh09LwCOAgASAAgIJh09LwCOAgAAAA==.Sisillia:BAAALAAECgcIDQAAAA==.Siwa:BAAALAAECgEIAwAAAA==.',Sj='Sjöfn:BAAALAAECggIDwAAAA==.',Sk='Skalyj:BAAALAAECgYIEAAAAA==.Skudde:BAACLAAFFIEIAAMPAAQIRRyWCwD0AAAPAAMI0ByWCwD0AAANAAMIgg5pGgC8AAAsAAQKgSsAAw0ACAjEJFYFAFUDAA0ACAiLJFYFAFUDAA8ACAg0I/UJAAwDAAAA.',Sm='Smoóve:BAAALAADCgcIBwAAAA==.',Sn='Snuck:BAAALAAECgIIBQAAAA==.',So='Solariá:BAAALAAECgUICQAAAA==.Soma:BAAALAADCgQIBAAAAA==.Sonya:BAAALAADCggIEAAAAA==.Sophia:BAAALAADCgYIBgABLAAECgYIDAAFAAAAAA==.Sovinya:BAAALAADCgQIBAAAAA==.',St='Sturmbulle:BAAALAADCggICAAAAA==.',Su='Surrad:BAABLAAECoEdAAISAAcIPg/2kACaAQASAAcIPg/2kACaAQAAAA==.Suruna:BAAALAADCgYIBgAAAA==.',Sv='Sveena:BAAALAAECgMICAAAAA==.',Sw='Swêêty:BAAALAAECgEIAQAAAA==.',Sy='Syphos:BAAALAAECgIIAQAAAA==.',['Sá']='Sáleanor:BAAALAADCggICgAAAA==.Sámàel:BAAALAAECgYICgAAAA==.',['Sî']='Sîröga:BAAALAADCgMIAwAAAA==.',Ta='Taelyn:BAABLAAECoEeAAMcAAgIaRijFwBPAgAcAAgIaRijFwBPAgAkAAEIoAlNOAAzAAAAAA==.Taeylana:BAAALAADCgcIBwABLAAECgcIJAAJAC0hAA==.Taijitsu:BAAALAADCggICAAAAA==.Talaná:BAAALAAECgcIEAAAAA==.Taling:BAAALAAECgYIBgAAAA==.Tarluna:BAACLAAFFIEIAAIMAAIILyZkDADhAAAMAAIILyZkDADhAAAsAAQKgS0AAwwACAgHI9MKAOoCAAwACAgHI9MKAOoCAAsABgigGXY6AJ4BAAAA.',Te='Teal:BAAALAAECgcICQAAAA==.Telang:BAAALAADCgcIBwAAAA==.Teldirani:BAAALAADCggIDgAAAA==.Terakles:BAABLAAECoEbAAMTAAcI9R2dHgBlAgATAAcI9R2dHgBlAgAUAAIIcgm5fwBZAAAAAA==.Teylu:BAAALAADCggICAAAAA==.',Th='Tharen:BAAALAAECgUIBQAAAA==.Thieyos:BAAALAAECgUIBQABLAAECgYIDgAFAAAAAA==.Thirdy:BAABLAAECoEeAAIhAAgItyG4EAALAwAhAAgItyG4EAALAwAAAA==.Thorgrîm:BAABLAAECoEWAAIhAAgIsRreJwBzAgAhAAgIsRreJwBzAgAAAA==.Thorrick:BAABLAAECoEkAAIVAAgIfBI6GAC6AQAVAAgIfBI6GAC6AQAAAA==.Thrarion:BAABLAAECoEZAAIcAAcIWBPYKAC2AQAcAAcIWBPYKAC2AQAAAA==.Thurion:BAAALAADCggICAAAAA==.Thustrak:BAAALAAECggICAAAAA==.',Ti='Timmee:BAAALAADCgcICgAAAA==.Titannia:BAAALAAECgMIBAAAAA==.',To='Tonke:BAABLAAECoEoAAMNAAgI1yKfDQAWAwANAAgIUiKfDQAWAwAPAAgILBvNHwBRAgAAAA==.Touaro:BAAALAADCgcIBwAAAA==.',Tr='Treebender:BAABLAAECoEpAAQLAAgI0yKRDADxAgALAAgI0yKRDADxAgARAAIIKSAmIQCzAAAeAAEIqwsAAAAAAAAAAA==.Trisagion:BAAALAADCggICAAAAA==.Trym:BAAALAAECgUICgABLAAFFAIIBQAGAEYfAA==.',['Tî']='Tîron:BAAALAAECgcIEAAAAA==.Tîrîon:BAAALAAECgUICgABLAAECgcIEAAFAAAAAA==.',['Tô']='Tôxîc:BAAALAADCggICAAAAA==.',Ul='Ultron:BAAALAAECgYIEwAAAA==.',Va='Valdea:BAACLAAFFIEJAAMhAAUIDB+mBAADAgAhAAUIDB+mBAADAgAlAAIIzyDqAQC7AAAsAAQKgSwAAyUACAhWJqIAAHADACUACAihJaIAAHADACEACAhwJWwEAGgDAAAA.Valdriin:BAAALAAECgMIAwAAAA==.Valerian:BAAALAADCgYIBgAAAA==.Valleya:BAABLAAECoEVAAIGAAYIexeDXwCeAQAGAAYIexeDXwCeAQAAAA==.Valnir:BAABLAAECoEVAAIDAAgIqw2SQwDLAQADAAgIqw2SQwDLAQAAAA==.Valthalak:BAAALAAECgYIEAAAAA==.Valveris:BAAALAAECgMIAwABLAAECgcIHwABAOUXAA==.Vanaria:BAAALAAECgIIAgAAAA==.Varaugh:BAAALAADCgYICgABLAAECgcIHAAaAKsgAA==.',Ve='Verfehlt:BAAALAAECgYIDgAAAA==.',Vi='Vintor:BAABLAAECoEaAAIBAAcI6ySsBgD2AgABAAcI6ySsBgD2AgAAAA==.',Vo='Vonriva:BAAALAADCggICwAAAA==.Vontaviouse:BAAALAADCgQIBAAAAA==.',Vu='Vulbo:BAAALAADCggICgAAAA==.Vulpidings:BAAALAADCggIGAAAAA==.',Wa='Wallnir:BAAALAAECgcIDQAAAA==.Wanbedk:BAAALAAECggIAgAAAA==.',We='Webstahunt:BAAALAAECgYIBgAAAA==.Weedstyletv:BAAALAADCggIJQAAAA==.',Wi='Wintår:BAAALAAECgcIEgAAAA==.Wisnadi:BAAALAADCggIDwAAAA==.',Wu='Wulpi:BAAALAAECgYIEgAAAA==.',['Wü']='Würzel:BAABLAAECoElAAIDAAcIxQxjWAB/AQADAAcIxQxjWAB/AQAAAA==.',Xa='Xaleris:BAAALAADCggIFQAAAA==.Xamil:BAABLAAECoEcAAIcAAgI3Qj/MQB2AQAcAAgI3Qj/MQB2AQAAAA==.',Xe='Xetias:BAAALAAECgYIBgAAAA==.',Xi='Xianlee:BAAALAADCgUIBAAAAA==.',Ya='Yamada:BAAALAAECgcIEAAAAA==.Yanayin:BAAALAADCgYIBgABLAADCggICAAFAAAAAA==.',Yi='Yian:BAAALAADCgcIBwAAAA==.',Yl='Ylenja:BAAALAADCggIFAABLAAECgcIIwAJAKEhAA==.',Yo='Yolari:BAAALAADCggIDgAAAA==.Yolonaise:BAABLAAECoEYAAIEAAYIWiU7KgBGAgAEAAYIWiU7KgBGAgAAAA==.Yomaru:BAAALAAECgQICAAAAA==.',Za='Zag:BAABLAAECoEbAAMIAAcICyX8CwCRAgAIAAYIuCX8CwCRAgAGAAUIChlPawB9AQAAAA==.Zaleria:BAAALAAECggICgAAAA==.Zash:BAAALAAECgYIEgAAAA==.Zatyria:BAAALAADCggIDwAAAA==.',Ze='Zeerax:BAAALAAECgcIDwAAAA==.Zel:BAACLAAFFIEFAAIGAAIIRh+2HwC9AAAGAAIIRh+2HwC9AAAsAAQKgS8ABAYACAhWJNYYANYCAAYABwhXI9YYANYCAAcABAgpJTMPAKEBAAgAAwgHIptQAAUBAAAA.Zerya:BAAALAAECgYICQABLAAFFAcIGAAVABwkAA==.',Zi='Zirbe:BAAALAAECgUIBQAAAA==.',Zo='Zoneta:BAAALAADCgQIBAAAAA==.',Zt='Ztrom:BAAALAAECggICAAAAA==.',Zu='Zuloa:BAAALAADCgYIBgABLAAECgYIBwAFAAAAAA==.',['Âc']='Âchilles:BAAALAADCgQIBAAAAA==.',['Ây']='Âyaya:BAAALAADCgcIBwAAAA==.',['Än']='Ännie:BAAALAAECgEIAQAAAA==.Änäkin:BAAALAAECgIIAgAAAA==.',['Æs']='Æsrâh:BAAALAAECgYIEwAAAA==.',['Él']='Élameth:BAAALAAECgcIDQAAAA==.',['Òn']='Òne:BAAALAADCggIDwAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end