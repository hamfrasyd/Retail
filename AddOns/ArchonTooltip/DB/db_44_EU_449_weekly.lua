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
 local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Monk-Brewmaster','Unknown-Unknown','Rogue-Assassination','Druid-Feral','Evoker-Devastation','Warrior-Protection','Paladin-Retribution','Shaman-Enhancement','Priest-Holy','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','Rogue-Subtlety','Mage-Frost','Mage-Arcane','Shaman-Restoration','Druid-Balance','Paladin-Holy',}; local provider = {region='EU',realm='Mannoroth',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ag='Agonizer:BAAALAAECgMIBwAAAA==.',Ai='Aiolia:BAAALAAECggICwAAAA==.',Aj='Ajur:BAAALAADCgcIBwAAAA==.',Ak='Akki:BAAALAADCggIBwAAAA==.',Al='Alfhari:BAAALAAECgIIBAAAAA==.Aliurá:BAAALAADCgYIBgAAAA==.Allani:BAABLAAECoEUAAMBAAcI/yNtJAAGAgABAAYI9yFtJAAGAgACAAMIMiaWFwBYAQAAAA==.',An='Anastassiya:BAAALAADCgQIBAAAAA==.Andigossa:BAAALAAECgYIDQAAAA==.Anduíl:BAAALAAECgYICQAAAA==.Anima:BAAALAAECgEIAQAAAA==.',Ar='Arodberia:BAAALAAECgQICAAAAA==.Arte:BAAALAADCgIIAgAAAA==.',As='Asarie:BAAALAADCgcIBwAAAA==.Ashena:BAAALAADCgUIBQAAAA==.Ashên:BAAALAADCggIDQAAAA==.',Av='Avarrion:BAAALAADCgYIDAAAAA==.',Az='Azubi:BAAALAAECgQIBAAAAA==.',Ba='Babylegs:BAAALAAECgYIDAAAAA==.Balloroc:BAAALAAECgcICwAAAA==.Barimgar:BAABLAAECoEUAAIDAAgI5R3WBQBfAgADAAgI5R3WBQBfAgAAAA==.Bava:BAAALAAECgUICwAAAA==.',Be='Berniedh:BAAALAAECgYICAAAAA==.',Bl='Blinc:BAAALAAECgIIBAAAAA==.Bloodrage:BAAALAADCggICAAAAA==.',Bo='Botis:BAAALAAECgQIBAABLAAECgcICwAEAAAAAA==.Botistadk:BAAALAADCggIEAABLAAECgcICwAEAAAAAA==.Botistawl:BAAALAADCgcIBwABLAAECgcICwAEAAAAAA==.',Br='Branx:BAAALAADCgIIBQAAAA==.Broxy:BAAALAAECgMIBAAAAA==.Broxyma:BAAALAADCgcIDgAAAA==.',Bu='Bujinkahn:BAAALAADCgcIDwAAAA==.',Ca='Catharsia:BAAALAADCgMIAwABLAADCggIDQAEAAAAAA==.Cazi:BAAALAAECgcIDgAAAA==.',Ch='Chirte:BAAALAADCgUIBQAAAA==.Chrîsi:BAAALAADCgcIDQAAAA==.Chrütli:BAAALAAECgYIDgAAAA==.',Co='Cowbustion:BAAALAAECgQIBAABLAAECgcIFAAFABglAA==.',Cu='Curcaryen:BAAALAAECggICwAAAA==.',De='Dessembrae:BAABLAAECoEXAAIGAAgI5x05AwDDAgAGAAgI5x05AwDDAgAAAA==.',Di='Diarrha:BAAALAAECgUICQAAAA==.Diaze:BAABLAAECoEUAAIHAAgIJxkNDgA3AgAHAAgIJxkNDgA3AgAAAA==.Dinavier:BAAALAAECgMIAwAAAA==.',Do='Dohaam:BAAALAADCgEIAQAAAA==.Dohan:BAAALAADCgUIBQAAAA==.Dokmar:BAAALAAECgQICQAAAA==.Doros:BAABLAAECoEUAAIIAAcIniQ0BADKAgAIAAcIniQ0BADKAgAAAA==.Dorosmonk:BAAALAAECgcICwABLAAECgcIFAAIAJ4kAA==.Dorosrogue:BAAALAADCgQIBAABLAAECgcIFAAIAJ4kAA==.',Dr='Drudax:BAAALAAECgQIBAAAAA==.',Dy='Dyrîos:BAABLAAECoEUAAIJAAcI6iKWDADMAgAJAAcI6iKWDADMAgAAAA==.',El='Elara:BAAALAADCgEIAQAAAA==.Eldarik:BAAALAAECgIIAgAAAA==.Eldreanne:BAAALAAECggICAAAAA==.Ele:BAAALAAECgUIBgAAAA==.Elisra:BAAALAADCgMIAwAAAA==.Elissha:BAAALAADCgMIBQAAAA==.Ellendil:BAAALAAECgIIAgAAAA==.',Em='Emousa:BAAALAADCggICAABLAAECgcICwAEAAAAAA==.',En='Engîîns:BAAALAADCgQIBAAAAA==.',Er='Eruja:BAAALAADCggICgAAAA==.',Ev='Evil:BAAALAAECgIIBAAAAA==.Evoiin:BAABLAAECoEVAAIKAAgIDxtHBQAoAgAKAAgIDxtHBQAoAgAAAA==.',Fa='Falkriya:BAAALAAECgYIDwAAAA==.',Fe='Feeldis:BAAALAAECgYIBgAAAA==.',Fi='Finchen:BAAALAAECgMIAwAAAA==.',Fr='Friedda:BAAALAADCgMIAwAAAA==.Fropoq:BAAALAAECgQIBwAAAA==.',Ga='Ganjialf:BAAALAAECgIIAgAAAA==.Garak:BAAALAAECgEIAQAAAA==.',Ge='Getshwifty:BAAALAADCgcIBwAAAA==.',Gl='Glramlin:BAAALAAECgEIAQAAAA==.',Go='Gonnameowbro:BAAALAAFFAMIAwAAAA==.Gorok:BAAALAAECgEIAQAAAA==.Gortan:BAAALAAECgEIAQAAAA==.',Gr='Grimstone:BAAALAADCggIDgAAAA==.',Ha='Hairbert:BAAALAADCgYIBgABLAAECgcIFAAIAJ4kAA==.Haruhi:BAAALAADCggIDgAAAA==.',He='Hefesaft:BAAALAAECgMIBQAAAA==.Heimì:BAAALAAECgcIEAAAAA==.Hexer:BAAALAADCggICAAAAA==.',Ho='Homegrow:BAAALAADCgcICAAAAA==.',Hu='Humanitär:BAABLAAECoEeAAILAAgI4hpRDAB6AgALAAgI4hpRDAB6AgAAAA==.',['Hü']='Hügelhans:BAAALAAECgQIBwAAAA==.',Ic='Icky:BAAALAADCgYIBgAAAA==.',Im='Imperio:BAAALAAECgcIEQAAAA==.',Ip='Ipolita:BAAALAADCggIFQAAAA==.',Ir='Irgendwas:BAAALAAECgQIAwAAAA==.',Is='Isilock:BAABLAAECoEUAAQMAAcIgCUaBwDwAgAMAAcIPSUaBwDwAgANAAUIbyP9BgD2AQAOAAEIHSY2TABjAAAAAA==.Isimage:BAAALAAECgcICQABLAAECgcIFAAMAIAlAA==.Isome:BAAALAAFFAEIAQAAAA==.Isril:BAAALAAECggIDwAAAA==.',Iz='Izuriel:BAAALAAECgQIBAAAAA==.',Ja='Jablonek:BAAALAAECgMIBgAAAA==.Jaffia:BAABLAAECoEUAAIPAAgItRgaBAA5AgAPAAgItRgaBAA5AgAAAA==.Jairá:BAABLAAECoEUAAIQAAcIZyUdAwD+AgAQAAcIZyUdAwD+AgAAAA==.',Ka='Kaius:BAAALAAECgYICgAAAA==.Kajany:BAAALAADCgcIDQAAAA==.Karon:BAAALAAECggIDQAAAA==.Kateri:BAAALAAECgcICwABLAAECgcIFAALAHojAA==.Kazan:BAABLAAECoEUAAIBAAcIvh4hEgCLAgABAAcIvh4hEgCLAgAAAA==.',Kc='Kcelsham:BAAALAAECgcIDgAAAA==.',Ke='Kendora:BAAALAAECgQIBgAAAA==.',Kl='Klappmässä:BAAALAADCgQIBAAAAA==.Kleymar:BAAALAADCgcICQAAAA==.',Km='Kmxdot:BAAALAAECgUIBQAAAA==.',Ko='Konua:BAAALAADCgUIBQAAAA==.',Kr='Kriegesgott:BAAALAADCggICAAAAA==.',Ku='Kux:BAAALAADCgMIBwAAAA==.',Ky='Kystiran:BAAALAADCgIIAgAAAA==.',['Kâ']='Kâin:BAAALAAECgIIBQAAAA==.',La='Lalatina:BAAALAADCgcIBwAAAA==.Lavanda:BAAALAADCggICAAAAA==.',Le='Leoryn:BAAALAADCggIDwAAAA==.Leándra:BAAALAADCgcIDgAAAA==.',Li='Liliax:BAAALAAECgYICwAAAA==.Lissya:BAAALAADCgcIDQAAAA==.Lisyra:BAABLAAECoEgAAMMAAgIBxlzDwB0AgAMAAgIBxlzDwB0AgANAAYILAQEEgAfAQAAAA==.',Ll='Llewellyn:BAAALAAECgEIAQAAAA==.',Lo='Lorîanna:BAABLAAECoEUAAILAAcIeiN/BgDTAgALAAcIeiN/BgDTAgAAAA==.',Lu='Lueska:BAAALAADCgcIBwAAAA==.',Ma='Malkus:BAAALAAECgcICAAAAA==.',Mi='Miisha:BAAALAAECgcICwAAAA==.Mijah:BAAALAAECgcIDgAAAA==.Mirtariann:BAAALAADCggIEAAAAA==.Mirtorrion:BAAALAADCgUIBgAAAA==.',Mo='Morgor:BAAALAAECgUIDAAAAA==.',Mu='Murtan:BAAALAAECgUIBQAAAA==.',My='Mylandre:BAAALAADCgMIAwAAAA==.Mylie:BAAALAADCggICAAAAA==.',['Mî']='Mîaný:BAAALAAECgEIAQAAAA==.',['Mô']='Môndrael:BAAALAAECgQICQAAAA==.',['Mü']='Mürtary:BAAALAADCggIDgAAAA==.',Na='Narias:BAAALAADCgYIBgAAAA==.Nawakmage:BAAALAAECggICAAAAA==.Nayelí:BAAALAADCgcIBwAAAA==.',Ne='Nefalia:BAAALAADCgYIBgABLAAECgYIDwAEAAAAAA==.Neumond:BAAALAADCgYIBgAAAA==.',Ni='Niméri:BAAALAADCgYICgABLAAECgcIFAALAHojAA==.Nitropenta:BAAALAAECgEIAgAAAA==.',Nk='Nkaa:BAAALAAECgYIEgAAAA==.',['Nä']='Näggi:BAAALAADCggICAABLAAECgcIDgAEAAAAAA==.',Ol='Olympiâ:BAAALAADCggIFwAAAA==.',On='Onigi:BAAALAADCgUIBQAAAA==.',Or='Orethoc:BAAALAAECgIIAgAAAA==.',Pa='Palatrix:BAAALAAECgQIBAAAAA==.Panoli:BAAALAAECgMIBAAAAA==.Pascal:BAAALAAECggIBgAAAA==.Pascoolism:BAAALAAECgYIDAAAAA==.',Pe='Perus:BAABLAAECoEUAAIQAAcIjyNsBADOAgAQAAcIjyNsBADOAgAAAA==.',Pi='Pixelchen:BAAALAAECgIIAgAAAA==.Pixia:BAAALAAECgEIAQAAAA==.',Pl='Plumsbär:BAAALAAECggIDgAAAA==.',['Pá']='Páblo:BAAALAADCgYIBgAAAA==.',Qu='Quinney:BAAALAADCggICAABLAAECgcIDgAEAAAAAA==.',Ra='Ragingsoul:BAAALAAECgMIBAAAAA==.Ragnon:BAAALAADCggIDwAAAA==.Rakuyo:BAAALAADCgYIBgAAAA==.Ranya:BAAALAAECgUICAAAAA==.',Re='Restofurry:BAAALAAECgYIBgABLAAECggIDQAEAAAAAA==.Retro:BAAALAADCggICAAAAA==.',Ri='Risiko:BAAALAADCggIDwAAAA==.',Ru='Rudos:BAAALAADCgcIBwAAAA==.',Sa='Saberchopf:BAAALAAECgYIDgAAAA==.Sathil:BAAALAAECggIEQAAAA==.Sawny:BAAALAADCggICAABLAAECgcIDgAEAAAAAA==.',Sc='Scheryna:BAAALAAECgYIAwAAAA==.Scherýn:BAAALAAECgUIBgAAAA==.Schnibbl:BAAALAADCggICAAAAA==.Schnippler:BAAALAADCggICAABLAADCggICAAEAAAAAA==.Schæfchën:BAAALAAECgUIBQAAAA==.Scortum:BAAALAAECgMIBQAAAA==.',Se='Serénity:BAAALAADCggIEAABLAAECggIDQAEAAAAAA==.',Sh='Shamfire:BAAALAAECgYICwAAAA==.Shaniv:BAAALAAECgcIEAAAAA==.Shapeslift:BAAALAAECggIEwAAAA==.Shiiwa:BAAALAADCgEIAQAAAA==.Shinsei:BAABLAAECoEgAAMBAAgICx4/EgCKAgABAAgIyRs/EgCKAgACAAQI3RiZGABOAQAAAA==.Shyniil:BAAALAAECggICAAAAA==.Shòkkx:BAAALAAECgYICwAAAA==.Shókkx:BAAALAADCggICAABLAAECgYICwAEAAAAAA==.',Sl='Sliftbolt:BAAALAADCggICAABLAAECggIEwAEAAAAAA==.',Sn='Sneakyshart:BAABLAAECoEUAAMFAAcIGCU7BQDzAgAFAAcIGCU7BQDzAgAPAAMI3x7rDQAUAQAAAA==.',Sp='Spirulinia:BAAALAADCggIDwAAAA==.',Sw='Swdmiss:BAAALAAECgYIBQAAAA==.Swordmastery:BAABLAAECoEKAAIBAAcIdRX1MgC9AQABAAcIdRX1MgC9AQAAAA==.',Sy='Syaoran:BAAALAADCgcIBwAAAA==.',['Só']='Sólstafir:BAAALAADCggICAAAAA==.',Ta='Taduros:BAAALAADCgcIDQAAAA==.Takingdown:BAAALAAECgYICAAAAA==.Talahon:BAABLAAECoEUAAIRAAgISR4VIQAbAgARAAgISR4VIQAbAgAAAA==.Tanya:BAEALAAECgcICQAAAA==.Tarifas:BAAALAADCgEIAQAAAA==.Taselol:BAAALAAFFAEIAQAAAA==.',Th='Thauriel:BAAALAAECgcIEwAAAA==.Thazdingo:BAAALAAECgEIAQAAAA==.Thorger:BAAALAAECgYICwAAAA==.',Ti='Tiiramisuu:BAABLAAECoEWAAISAAgIFA5rNABiAQASAAgIFA5rNABiAQAAAA==.Tisari:BAAALAADCgcIBwAAAA==.',To='Toyz:BAAALAAECgEIAQAAAA==.',Tr='Tranis:BAAALAADCgcIDQAAAA==.Treejin:BAAALAADCggICAAAAA==.Trhey:BAAALAADCgcIBwAAAA==.',Ts='Tsavong:BAAALAAECgcICwAAAA==.Tsukihi:BAAALAAECgIIAgAAAA==.',Tu='Tuulanî:BAAALAADCggIGAABLAAECgcICwAEAAAAAA==.Tuz:BAAALAAECgMIBAAAAA==.',Ty='Tycrius:BAAALAAECgcIDQAAAA==.',Ue='Uerige:BAAALAADCgcIBwAAAA==.',Um='Umága:BAAALAADCgUIBQAAAA==.',Va='Valadrake:BAAALAAECgIIAgAAAA==.Valandu:BAAALAADCgcICQABLAAECgIIAgAEAAAAAA==.Valavulp:BAAALAADCgEIAQABLAAECgIIAgAEAAAAAA==.Valvier:BAAALAAECgIIAwAAAA==.Vanni:BAAALAAFFAIIAgAAAA==.',Ve='Verbanskaste:BAAALAAECggICAAAAA==.',Vo='Vodjin:BAAALAADCgYIBgAAAA==.Vogel:BAAALAADCgcICwAAAA==.Vonah:BAAALAAECgMIAwAAAA==.',Vr='Vrask:BAAALAADCgEIAQAAAA==.',Wa='Waldi:BAAALAAECgYICQAAAA==.Wanev:BAAALAAECgMIBAAAAA==.',Xa='Xalatath:BAAALAADCgcIBwAAAA==.Xandôs:BAAALAAECggIDgAAAA==.',Xe='Xenderamonki:BAAALAAECgEIAQABLAAECgUIBQAEAAAAAA==.',Yo='Yogibär:BAAALAAECgYIBgAAAA==.Yortu:BAABLAAECoEUAAITAAcIwhFZGQDLAQATAAcIwhFZGQDLAQAAAA==.',['Yé']='Yésterday:BAAALAAECgYIBwAAAA==.',Za='Zalandotroll:BAAALAADCggICAAAAA==.Zalasia:BAABLAAECoEUAAMUAAgIex+DEgDHAQAUAAgIex+DEgDHAQAJAAYIzxopOQCYAQAAAA==.Zanndana:BAAALAAECgYIDwAAAA==.',Ze='Zelya:BAAALAADCggICAAAAA==.',['Zê']='Zêrklor:BAAALAAECgMIBAAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end