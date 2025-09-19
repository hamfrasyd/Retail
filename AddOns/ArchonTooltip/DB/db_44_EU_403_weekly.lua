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
 local lookup = {'Unknown-Unknown','DeathKnight-Frost','DeathKnight-Unholy','Evoker-Devastation','Paladin-Retribution','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Warlock-Destruction','Hunter-BeastMastery','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Druid-Restoration',}; local provider = {region='EU',realm='Arygos',name='EU',type='weekly',zone=44,date='2025-08-31',data={Ae='Aelor:BAAALAAECgYIBgAAAA==.',Ag='Aganubon:BAAALAADCggICgAAAA==.',Ai='Ainarios:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',Ak='Aka:BAABLAAECoEXAAMCAAgIRCNbJgD7AQACAAcImhZbJgD7AQADAAQIGSVIEACwAQAAAA==.',Al='Alaskatraz:BAAALAADCggIDwAAAA==.Aleke:BAAALAADCgcIDQAAAA==.Aliaa:BAAALAAECgQIBgAAAA==.Alric:BAAALAAECgMIBQAAAA==.Alvari:BAAALAAECgMIAwAAAA==.',Am='Amalaswintha:BAAALAAECgQICAAAAA==.Amaree:BAAALAADCgEIAQAAAA==.Amayai:BAAALAAECgYIDQAAAA==.',An='Angmida:BAAALAADCgQIBAAAAA==.',Ar='Aribêth:BAAALAAECgYICQAAAA==.Arkira:BAAALAADCgEIAQAAAA==.',As='Astraanar:BAAALAAECgIIAgAAAA==.',Au='Auxo:BAAALAADCgYIDwAAAA==.',Av='Avelie:BAAALAADCggIFgAAAA==.',Az='Azzinóth:BAAALAAECgUIBwABLAAECgYIFgAEAK0dAA==.Azzuro:BAAALAADCggICAAAAA==.',Ba='Balîndys:BAAALAAECgIIAgAAAA==.Bambî:BAAALAADCggICAAAAA==.Bansenvonnod:BAAALAADCgMIAwAAAA==.Baphuon:BAAALAAECgcIDgAAAA==.Bartakus:BAAALAAECgMIAwAAAA==.',Be='Beaux:BAAALAAECgMIBQAAAA==.Beernator:BAAALAADCgcICgAAAA==.Bellasopie:BAAALAADCgIIAwAAAA==.',Bi='Biiduubiiduu:BAAALAADCgEIAQABLAAECgMIBAABAAAAAA==.',Bl='Blackzora:BAAALAAECgQICAAAAA==.Blueray:BAAALAAECgMIBQAAAA==.Blóom:BAAALAAECggICQAAAA==.',Bo='Boomiie:BAAALAAECggIBgAAAA==.Boundless:BAAALAADCggICAAAAA==.',Br='Brautt:BAAALAADCggICAAAAA==.',Bu='Bualie:BAAALAAECgYICAAAAA==.Bubilein:BAAALAADCggIDgAAAA==.Buggtide:BAAALAADCgYIBgAAAA==.Bullwalker:BAAALAADCggIFgAAAA==.Butterbart:BAAALAADCggICwAAAA==.',Bz='Bzztbzzt:BAAALAAECgYIDwAAAA==.',['Bä']='Bärchénn:BAAALAADCgYIBgABLAADCgYIBgABAAAAAA==.',['Bå']='Bådlock:BAAALAAECgEIAQAAAA==.',['Bí']='Bísam:BAAALAAECgYIDgAAAA==.',['Bù']='Bùfù:BAAALAADCggICAAAAA==.',Ca='Cagliosttro:BAAALAAECgIIAgAAAA==.Caidana:BAAALAADCggICAAAAA==.Cardrill:BAAALAADCggIDwAAAA==.Casjopaya:BAAALAADCgQIBgAAAA==.Catori:BAAALAAFFAIIAgAAAA==.Catthebest:BAAALAADCgQIBAAAAA==.Catweesel:BAAALAADCgUIAwAAAA==.',Ce='Celiah:BAAALAAECgMIBwAAAA==.',Ch='Charell:BAAALAADCggIDQAAAA==.Charina:BAAALAADCgcIAwAAAA==.Charlu:BAAALAADCgIIAgAAAA==.Cheynestoke:BAAALAADCgEIAQAAAA==.Chiv:BAAALAAECgYICQAAAA==.',Ci='Cinderrella:BAAALAAECgcICAAAAA==.',Co='Conina:BAAALAADCggIFgAAAA==.Coriona:BAAALAAECgYIBgAAAA==.Corristo:BAAALAAECgEIAQAAAA==.',Cu='Curlos:BAAALAAECgUICgAAAA==.',['Câ']='Câtaléya:BAAALAADCggICAAAAA==.',['Cí']='Círí:BAAALAAECgMIBQAAAA==.',Da='Dagolad:BAAALAADCgcIBwAAAA==.Daméé:BAAALAADCgcIBwAAAA==.Darkmarko:BAAALAAECgEIAQAAAA==.',De='Deathiras:BAAALAAECgUIBQAAAA==.Deathzacki:BAAALAADCggIEAABLAAECgYIBAABAAAAAA==.Delphino:BAAALAADCgQIBgAAAA==.Detor:BAAALAAECgMIAwAAAA==.',Di='Dibster:BAAALAADCgQIBAAAAA==.Dirk:BAAALAADCggICAAAAA==.Dirtybash:BAAALAAECgMICAAAAA==.',Dk='Dk:BAAALAAECgMIBAAAAA==.',Do='Dokarion:BAAALAAECgYIDAAAAA==.',Dr='Dragonator:BAAALAAECgEIAQAAAA==.Dragonbane:BAAALAADCggIBgAAAA==.Dreamfyre:BAAALAAECgYICAAAAA==.Dreek:BAAALAADCggICwAAAA==.Dreihandaxt:BAABLAAECoEXAAIFAAgINySiAwBQAwAFAAgINySiAwBQAwAAAA==.Drias:BAAALAAECgIIAgAAAA==.',Dw='Dwarusch:BAAALAAECgMIBAAAAA==.',['Dá']='Dádá:BAAALAAECgQIBAAAAA==.',['Dä']='Dämoni:BAAALAAECgMIAwAAAA==.',Eb='Eberrippchen:BAAALAAECggIEgAAAA==.',Ef='Efeel:BAAALAAECgEIAQAAAA==.',Eg='Egaleddi:BAAALAAECggICAAAAA==.',El='Elaisa:BAAALAAECgcIEgAAAA==.Elisina:BAAALAADCgcIBwAAAA==.Eltika:BAAALAADCgcIBwAAAA==.Elymas:BAAALAAECgYIDwAAAA==.',Em='Emix:BAAALAAECggICgAAAA==.Emmea:BAAALAADCggIFgAAAA==.',En='Ennox:BAAALAAECgUICQAAAA==.Enyâ:BAAALAAECgYICgAAAA==.',Er='Erleuchtung:BAAALAAECgUIBQAAAA==.Erâdyâs:BAAALAADCgcIFgABLAAECgYIBgABAAAAAA==.Erêk:BAAALAADCggICAAAAA==.',Es='Essy:BAAALAADCggICAAAAA==.',Eu='Eutrasusrex:BAAALAADCgcIBwAAAA==.',Ev='Evángéliné:BAAALAADCgQIBgAAAA==.',Ez='Ezakimak:BAAALAAECgMIBQAAAA==.Eziioo:BAAALAAECgMIBAAAAA==.',Fa='Fafnis:BAAALAAECgYICAAAAA==.Fayaris:BAAALAADCggIHgAAAA==.',Fe='Feight:BAAALAAECgMIBQAAAA==.Felgrim:BAAALAAECgMIBAAAAA==.Felun:BAAALAAECgMIBgAAAA==.Femorka:BAAALAADCggIFwAAAA==.Feuerkachel:BAAALAAECgEIAQAAAA==.',Fi='Filrakuna:BAAALAADCgYIBgAAAA==.Finduz:BAABLAAECoEWAAIEAAgI6iAYBwDHAgAEAAgI6iAYBwDHAgAAAA==.Fireflint:BAAALAAECgQIBwAAAA==.Firefly:BAAALAAECgEIAQAAAA==.',Fr='Friedjín:BAAALAAECgYICAAAAA==.Fructi:BAAALAAECgEIAQAAAA==.',Fu='Fummlerin:BAAALAADCgcIDAAAAA==.Furorion:BAABLAAECoEWAAIEAAYIrR1qEwDlAQAEAAYIrR1qEwDlAQAAAA==.Fururion:BAAALAADCggIDgAAAA==.Fuyugá:BAAALAAECgUICwAAAA==.',Ga='Gafludi:BAAALAADCggIDgAAAA==.Gartogg:BAAALAAECgEIAQAAAA==.Garviel:BAAALAADCgQIBAAAAA==.',Gl='Glandahl:BAAALAADCggIFQAAAA==.Globorg:BAAALAAECgMIBAAAAA==.Glühbirne:BAAALAAECgEIAQAAAA==.',Go='Goldfielder:BAAALAADCgYIBgAAAA==.Goldíe:BAAALAAECgIIAgAAAA==.Goliat:BAAALAADCggICAAAAA==.Goralax:BAAALAADCgcIEwABLAAECgYIBgABAAAAAA==.',Gr='Grotzog:BAAALAADCgIIAgAAAA==.Grómbârt:BAAALAADCggICwAAAA==.',Gu='Gusti:BAAALAADCggIDwAAAA==.',['Gö']='Gönndalf:BAAALAADCgQIBAAAAA==.Göpe:BAABLAAECoEXAAIGAAgIGyRUAwAxAwAGAAgIGyRUAwAxAwAAAA==.',['Gú']='Gúltiriá:BAAALAAECgYIBgAAAA==.',Ha='Hanei:BAAALAAECgEIAQABLAAECgYIDQABAAAAAA==.Hardthor:BAAALAADCggIFAAAAA==.Harryhoff:BAAALAAECggIEwAAAA==.Haunei:BAAALAADCgEIAgAAAA==.Haybow:BAAALAADCggICAAAAA==.Hazesa:BAAALAADCgEIAQAAAA==.Hazè:BAAALAAECgIIAgAAAA==.',He='Healbilly:BAAALAADCggIEAAAAA==.Helgê:BAAALAADCgcIFAAAAA==.Hellgrazer:BAAALAADCgMIAwAAAA==.Herminator:BAAALAADCgYIDAAAAA==.Heslo:BAAALAADCgcIBwAAAA==.',Ho='Honeyhoff:BAAALAAECggIEwAAAA==.Horgata:BAAALAADCgQIBgAAAA==.',Hu='Huntinghero:BAAALAADCgQIBwAAAA==.Huurga:BAAALAADCgcIEgAAAA==.',['Há']='Hálfar:BAAALAAECgYIDgAAAA==.',['Hè']='Hèllsbèlls:BAAALAADCgYIBgAAAA==.',Ic='Ichmagblumen:BAAALAADCgQIAwAAAA==.',Ig='Igerus:BAAALAAECgYIDAAAAA==.',Il='Illumzar:BAAALAADCgQIBgAAAA==.',Im='Imigran:BAAALAADCggIDAAAAA==.',In='Inadequate:BAAALAAECgQIBgAAAA==.Ingbar:BAAALAAECgEIAQAAAA==.Injuria:BAABLAAECoEXAAIHAAgI0R32CQDEAgAHAAgI0R32CQDEAgAAAA==.',Iv='Ivraviel:BAABLAAECoEVAAIIAAcIIhe1HwDUAQAIAAcIIhe1HwDUAQAAAA==.Ivóny:BAAALAAECggICAAAAA==.',Ja='Jacat:BAAALAAECgMIBQAAAA==.Jagana:BAAALAAECgIIAgAAAA==.',Je='Jenolix:BAAALAADCgcIBwAAAA==.',Ji='Jiani:BAAALAADCggIFQAAAA==.',Jo='Johta:BAAALAAECgIIAgAAAA==.Jokerbabe:BAAALAADCgcIBwAAAA==.',Jr='Jrpepa:BAAALAADCggICAAAAA==.',Ju='Juster:BAAALAAECgMIAwAAAA==.',['Jû']='Jûdasprîest:BAAALAADCgUIBQABLAAECgYIDwABAAAAAA==.',Ka='Kaatschauu:BAAALAADCgUIBQAAAA==.Kajusha:BAAALAAECgMICAAAAA==.Kammí:BAAALAADCggICAABLAAECgMIAwABAAAAAA==.Kasat:BAAALAAECgEIAQAAAA==.Kassiphone:BAAALAADCgcIEgAAAA==.Katargo:BAAALAADCgcIBwAAAA==.Kay:BAAALAAECggIEwAAAA==.Kayorus:BAAALAAECgMIBQAAAA==.',Ke='Keenreevs:BAAALAAECggIEwAAAA==.Keksschmiedê:BAAALAADCgMIBgAAAA==.Kelnarzul:BAABLAAECoEXAAIJAAgIBx4gDACgAgAJAAgIBx4gDACgAgAAAA==.Kezo:BAAALAAECggIEwAAAA==.',Kn='Knopp:BAAALAADCggIEwAAAA==.Knüppeldrauf:BAAALAADCgQIBgAAAA==.',Ko='Kohaku:BAAALAADCggIFQAAAA==.',Kr='Krallamari:BAAALAAECgIIAgAAAA==.Krasota:BAAALAADCgYICwAAAA==.Krystalia:BAAALAAECgIIAgAAAA==.Krüppling:BAAALAAECgMIAwABLAAECgYIDwABAAAAAA==.',Ku='Kuhgelblitz:BAABLAAECoEXAAMHAAgIdiFhBgAHAwAHAAgIdiFhBgAHAwAIAAEIbQWtiQApAAAAAA==.',Kv='Kvothiras:BAAALAAECgYIEAAAAA==.',Ky='Kyda:BAAALAADCgcIBwAAAA==.Kynez:BAAALAADCgMIAwAAAA==.Kyø:BAAALAAFFAIIAgAAAA==.',La='Lanfêar:BAAALAADCggICAAAAA==.Laylas:BAAALAAECgYIDAAAAA==.',Le='Leoardrry:BAAALAAECgIIAwAAAA==.',Lh='Lhilia:BAAALAADCggICAAAAA==.',Li='Liabell:BAAALAAECgEIAQAAAA==.Liikex:BAAALAAECgcIEQAAAA==.Lilars:BAAALAADCgcIBwAAAA==.Lillith:BAAALAAECgMIAwAAAA==.Limoncella:BAAALAADCggIFgAAAA==.Lirius:BAAALAADCgcICwAAAA==.',Lo='Lockda:BAAALAAECgYICgAAAA==.Lokna:BAAALAADCgcIBwAAAA==.Loparia:BAAALAADCggIDgAAAA==.Lorat:BAAALAAECgQIBQAAAA==.Loraven:BAAALAADCgcICwAAAA==.',Lu='Lukou:BAAALAAECgUIBQAAAA==.Lunostrion:BAAALAADCgcIBwABLAAECgYICwABAAAAAA==.',['Lê']='Lêâ:BAAALAAECggICgAAAA==.',['Lô']='Lôckchen:BAAALAADCggIEQABLAAECgYICAABAAAAAA==.',['Lû']='Lûcius:BAAALAADCgUICQAAAA==.',Ma='Majenda:BAAALAADCggIFgAAAA==.Maktorr:BAAALAAECgUIBgAAAA==.Malatus:BAAALAAECgIIAgAAAA==.Malesteria:BAAALAAECgEIAQABLAAECgYIBgABAAAAAA==.Malgrimace:BAAALAAECgMIBQAAAA==.Marasi:BAAALAADCgUIBQAAAA==.Maribela:BAAALAADCggIDQAAAA==.Martinika:BAAALAAECgIIAgAAAA==.',Mc='Mcdemon:BAAALAAECgIIAgAAAA==.',Me='Medon:BAAALAADCggICAAAAA==.Melasculâ:BAAALAAECgYICwAAAA==.Memphes:BAAALAAECgEIAQAAAA==.Mendrin:BAAALAAECgMIAwAAAA==.Meranbir:BAAALAADCgcIBwAAAA==.Merile:BAAALAADCgQIBAAAAA==.Merrlin:BAAALAADCggIEgAAAA==.',Mi='Midorii:BAAALAAECgYIDwAAAA==.Mikael:BAAALAADCggICQAAAA==.Millhaus:BAAALAADCgIIAgAAAA==.Minette:BAAALAADCggIDwAAAA==.Missbanshee:BAAALAADCgcIBwAAAA==.Misumi:BAAALAADCgYICAAAAA==.Miyoko:BAAALAADCggICAAAAA==.',Mo='Moonwitch:BAAALAADCgcIBwAAAA==.Mordsith:BAAALAADCgcIDgAAAA==.Moriyama:BAAALAADCggIEAAAAA==.Moth:BAAALAADCggIFAAAAA==.',Mu='Mumanz:BAAALAAECgEIAQAAAA==.',Mx='Mxpaladin:BAAALAAECggIBQAAAA==.Mxpriester:BAAALAADCgcICgAAAA==.',My='Mystikmage:BAAALAAECgMIBAAAAA==.Myynach:BAAALAADCggIFgAAAA==.',['Mê']='Mêlanes:BAAALAADCggICAAAAA==.',['Mî']='Mîu:BAAALAAECgYICwAAAA==.',Na='Nakavoker:BAAALAAECgIIAgAAAA==.Naschi:BAAALAADCgcIDQAAAA==.Nationalelfe:BAAALAADCggICAABLAAECgYIBgABAAAAAA==.Naturesprime:BAAALAAECgIIAgAAAA==.',Ne='Needforspeed:BAAALAADCgQIBAAAAA==.Neldai:BAAALAAECgMIBQAAAA==.Neltarion:BAAALAADCgcIDgAAAA==.Nemaide:BAAALAAECgIIAgAAAA==.Neoblomný:BAAALAAECgQIBAAAAA==.Neoxt:BAAALAAECgEIAQAAAA==.',Ni='Nightblade:BAAALAAECgIIAwAAAA==.Nimativ:BAAALAAECgMIBQAAAA==.',No='Noala:BAAALAADCggIFgAAAA==.Nojoy:BAABLAAECoEXAAIGAAgI1CKRAwArAwAGAAgI1CKRAwArAwAAAA==.Nolity:BAAALAAECgYICgAAAA==.Nomié:BAEALAAECgQIBAABLAAECggICAABAAAAAA==.Nomíé:BAEALAADCgQIBAABLAAECggICAABAAAAAA==.Notärztin:BAAALAAECgMIAwAAAA==.',Nu='Nuy:BAABLAAECoEUAAIKAAgIiiHECQDSAgAKAAgIiiHECQDSAgAAAA==.',Ny='Nymea:BAAALAAECgYICgAAAA==.Nyrel:BAAALAAECgMIAwAAAA==.',['Nà']='Nàsty:BAAALAADCggICAAAAA==.',['Nâ']='Nânamii:BAAALAADCgcICQABLAAECgEIAQABAAAAAA==.',['Nî']='Nîcý:BAAALAAECgUIBQAAAA==.',['Nó']='Nómie:BAEALAADCggIAgABLAAECggICAABAAAAAA==.',['Nô']='Nômie:BAEALAAECggICAAAAA==.',['Nû']='Nûdelhunter:BAAALAAECgcIEAAAAA==.',Oa='Oaschkazel:BAAALAADCgcICAAAAA==.',Oc='Ochsford:BAAALAAECgMIBwAAAA==.',Ol='Olio:BAAALAADCggICAAAAA==.',On='Onlein:BAAALAAECgIIAgAAAA==.',Or='Oreane:BAAALAADCgcIBwABLAADCggICAABAAAAAA==.Oryx:BAAALAADCgYIBgABLAAECgEIAQABAAAAAA==.Orzowei:BAAALAADCggICAAAAA==.',Os='Osana:BAAALAADCgQIBgAAAA==.',Ou='Outzider:BAAALAAECgEIAQAAAA==.',Pa='Padma:BAAALAAECgcIEAAAAA==.Painbow:BAAALAAECgUIBQAAAA==.Palacetamol:BAAALAAECgQIBAAAAA==.Palaver:BAAALAADCggIFQAAAA==.Palinaí:BAAALAADCggICAAAAA==.Papadudu:BAAALAAECgEIAQAAAA==.París:BAAALAAECgQIBAAAAA==.Patzeclap:BAAALAAECgIIAgABLAAECgYICgABAAAAAA==.Patzedh:BAAALAAECgYICgAAAA==.Pava:BAAALAAECggIBgAAAA==.',Pe='Pelaios:BAAALAADCggICAAAAA==.Pendash:BAAALAAECgIIAgAAAA==.Pennerbombe:BAAALAAECgMIAwAAAA==.Perditaamo:BAAALAAECgMIBAAAAA==.',Ph='Phaye:BAAALAADCggICAAAAA==.Phèx:BAABLAAECoEXAAILAAgILCVpAgBlAwALAAgILCVpAgBlAwAAAA==.',Pi='Pifpoffeline:BAAALAADCgcICgAAAA==.',Pl='Plelf:BAAALAAECgMIAwAAAA==.Ploedeq:BAAALAADCggICAAAAA==.',Po='Powerbogen:BAAALAADCggIFQAAAA==.',Pr='Profdrmed:BAABLAAECoEXAAMMAAgIiCGRAwAOAwAMAAgIiCGRAwAOAwANAAEIyAk+HAA0AAAAAA==.',Pu='Puuhlee:BAAALAADCgYIBgABLAAECgYICQABAAAAAA==.',['Pá']='Pálínai:BAAALAAECgIIBAAAAA==.',['Pâ']='Pâlínai:BAAALAADCggICAAAAA==.',['Pí']='Píng:BAAALAADCgEIAQAAAA==.',Qi='Qiin:BAAALAAECgYICgAAAA==.',Ql='Qlöde:BAAALAADCggIEAABLAAECgcIDwABAAAAAA==.',Ra='Raaku:BAAALAAECgEIAQAAAA==.Ragnarogg:BAAALAADCgcIDQABLAAECgMIBAABAAAAAA==.Rainmakerex:BAAALAADCgMIAwAAAA==.Ramondis:BAAALAAECgEIAQAAAA==.Rasorae:BAAALAADCggIEwAAAA==.Razørs:BAAALAAECgcIAwAAAA==.',Ri='Rischi:BAAALAAECgYICQAAAA==.Ritzos:BAAALAAECgYICwAAAA==.',Ro='Rockylein:BAAALAADCgcIDQAAAA==.Rogar:BAAALAADCggICwAAAA==.Roguecilia:BAAALAADCggICAAAAA==.',Ry='Ryco:BAAALAAECgMIBQAAAA==.',['Rî']='Rîkku:BAAALAAECggICAAAAA==.',Sa='Salacia:BAAALAADCggICAAAAA==.Saloc:BAAALAAECgYICAAAAA==.Sanitoeter:BAAALAADCggIFgAAAA==.Santi:BAAALAAECgMIBAAAAA==.Sanusi:BAAALAADCgYIBgAAAA==.Saphurion:BAAALAADCgcICgAAAA==.Sayla:BAAALAADCgcICQAAAA==.',Sc='Schamili:BAAALAADCggIDwAAAA==.Schams:BAAALAAECgYIBwAAAA==.Schnuffelie:BAAALAADCgIIAgABLAADCgYIBgABAAAAAA==.Schwarzwald:BAAALAADCggICwAAAA==.',Se='Seccu:BAAALAADCggIDwABLAAECgMIAwABAAAAAA==.Semaphine:BAAALAAECgMIBQAAAA==.Senpai:BAAALAADCggICAAAAA==.Senra:BAAALAAECgQIBQAAAA==.Serà:BAAALAAECgMIAwAAAA==.',Sh='Shabhazza:BAAALAAECggICAAAAA==.Shaiýa:BAAALAAECgQIBgAAAA==.Shanressar:BAAALAAECgYICgAAAA==.Sheenah:BAAALAAECgYIDwAAAA==.Shenjar:BAAALAAECgYIBgAAAA==.Shinkawa:BAAALAADCgQIBAABLAADCgcIBwABAAAAAA==.Shinrà:BAAALAADCggIEAAAAA==.Shodh:BAAALAADCgcIBwAAAA==.Shuichi:BAAALAADCggIFQAAAA==.Sháné:BAAALAADCggICAAAAA==.Shøøtemup:BAAALAADCgMIAwAAAA==.',Si='Sibul:BAAALAAECgIIAgAAAA==.Silesta:BAAALAAECgYIDQABLAAECgYIEAABAAAAAA==.Sindra:BAAALAADCgcIBwAAAA==.Sinuvil:BAAALAADCgcIBwABLAAECggIEwABAAAAAA==.',Sk='Skol:BAAALAADCgQIBgAAAA==.Skymonki:BAAALAAECgQICAAAAA==.',So='Sorbya:BAAALAADCgcIBwAAAA==.',Sp='Spinnbert:BAAALAADCggICAABLAAECgYICgABAAAAAA==.',Sr='Srîka:BAAALAADCgQIBAAAAA==.',St='Stahl:BAAALAADCggIDwAAAA==.Stahlrock:BAAALAADCggICAAAAA==.Strohhut:BAAALAAECgIIAgAAAA==.Stylewalker:BAAALAAECgIIAgAAAA==.Stâhlrock:BAAALAAECgMIBQAAAA==.Stérnenkind:BAAALAAECgMIBQAAAA==.',Sy='Syrialis:BAAALAADCgYIBgAAAA==.',['Sí']='Sínuviel:BAAALAAECggIEwAAAA==.',Ta='Takako:BAAALAADCggICAAAAA==.Takeomasaki:BAAALAADCggIFAAAAA==.Talantor:BAAALAAECgYIBgAAAA==.Tassdrago:BAAALAAECgIIBAAAAA==.Taunix:BAAALAADCgcIDAAAAA==.',Te='Teval:BAAALAADCgMIBAAAAA==.',Th='Theressa:BAAALAAECgYICwAAAA==.Thorneblood:BAAALAAECgEIAQAAAA==.Threeinch:BAAALAADCgcIBwAAAA==.',Ti='Tinares:BAAALAADCgYIBgAAAA==.',To='Tomcruisader:BAAALAADCgcIDQABLAADCggICwABAAAAAA==.Totemmeister:BAAALAADCgYIBgAAAA==.',Tr='Treffníx:BAAALAAECgMIAwAAAA==.Trex:BAAALAADCgYIBgAAAA==.',Tu='Tutzel:BAAALAADCgcICwAAAA==.',Ty='Tygerlilly:BAAALAAECgYICAABLAAECgYIDwABAAAAAA==.Tynaria:BAAALAAECgYICQAAAA==.Tysen:BAAALAAECgMIAwABLAAECgYIDgABAAAAAA==.',Tz='Tziki:BAAALAAECgcIEAAAAA==.',Ue='Uelidehealer:BAABLAAECoEVAAMOAAgIBwy2JQBgAQAOAAgIBwy2JQBgAQAGAAUIhwsXLgAaAQAAAA==.',Va='Vahltas:BAAALAAECgMIBQAAAA==.Vaila:BAAALAAECgYICgAAAA==.Valkye:BAAALAADCggICwAAAA==.Varithra:BAAALAAECgIIAgAAAA==.Vashara:BAAALAADCggIDwAAAA==.',Ve='Veijari:BAAALAADCgcIEAAAAA==.Velaryn:BAAALAAECgcIDwAAAA==.Velerius:BAAALAADCgcIBwABLAADCggIFQABAAAAAA==.Ventipala:BAAALAAECggIEwAAAA==.',Vi='Vicany:BAAALAAECggIEwAAAA==.',Vo='Voolverine:BAAALAADCgYIAQAAAA==.Vortrak:BAAALAADCggIEAAAAA==.Vortrek:BAAALAADCgcIBwAAAA==.Vortrik:BAAALAADCgUICAAAAA==.',Vu='Vuppi:BAAALAADCgcIDgAAAA==.',Vy='Vyrez:BAAALAADCgEIAQAAAA==.',Wa='Waffeleisen:BAAALAAFFAIIAgAAAA==.Waifu:BAAALAAECgcICgAAAA==.Warristyles:BAAALAADCggICAABLAADCggICwABAAAAAA==.',Wh='Whityxd:BAAALAADCgEIAQAAAA==.',Wi='Wiczi:BAAALAAECggIDAAAAA==.',['Wà']='Wàrheàrt:BAAALAADCgcIBwAAAA==.',['Wì']='Wìsh:BAAALAADCgcIBwABLAAECgMICAABAAAAAA==.',['Wó']='Wódan:BAAALAADCggIFQAAAA==.',Xa='Xalindare:BAAALAADCgMIAwAAAA==.Xarthul:BAAALAAECgMIBAAAAA==.',Xe='Xemnás:BAAALAADCgEIAQAAAA==.',Xo='Xosad:BAAALAADCggIDwAAAA==.',Xs='Xsen:BAAALAADCggIDQAAAA==.',Ya='Yanê:BAAALAADCgcIBwAAAA==.',Yo='Yoruíchí:BAAALAADCggIDgAAAA==.Yoshino:BAAALAADCgcIDAAAAA==.',Yu='Yumeko:BAAALAADCgcIBwAAAA==.',['Yû']='Yûkí:BAAALAAECgEIAQAAAA==.',Za='Zackipriest:BAAALAAECgYIBAAAAA==.Zackthyr:BAAALAADCggIFQABLAAECgYIBAABAAAAAA==.Zagzagelia:BAAALAADCggIFQAAAA==.',Ze='Zelaous:BAAALAAECgEIAQAAAA==.Zenchou:BAAALAADCggICQABLAAECgMIBgABAAAAAA==.Zerberos:BAAALAADCgUIBQAAAA==.Zerebro:BAAALAADCgEIAQAAAA==.',Zi='Zihua:BAAALAAECgYICwAAAA==.Zilana:BAAALAAECgYIEAAAAA==.Zilverblade:BAAALAAECgIIAQAAAA==.',Zo='Zoniya:BAAALAAECgMIAwAAAA==.',['Zö']='Zöschi:BAAALAADCgcIDgAAAA==.',['Ån']='Åndrox:BAAALAAECgMIBgAAAA==.',['În']='Înostrion:BAAALAAECgYICwAAAA==.',['Ðî']='Ðîrk:BAAALAAECgYICAAAAA==.',['Óf']='Óf:BAAALAAECgIIAgAAAA==.',['Ör']='Örchên:BAAALAADCgcIEgAAAA==.',['Ør']='Øreøz:BAAALAADCggICAAAAA==.',['Ýu']='Ýuuki:BAAALAADCggIDQAAAA==.',},}; provider.parse = parse;if ArchonTooltip.AddProviderV2 then ArchonTooltip.AddProviderV2(lookup, provider) end