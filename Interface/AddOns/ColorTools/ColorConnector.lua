-- ColorTools ColorConnector
-- Creates and manages color palettes for the addon

local addonName, ColorTools =  ...
local L = LibStub("AceLocale-3.0"):GetLocale("ColorTools")
local _ = LibStub("LibLodash-1"):Get()

-- Color conversion utilities
local ColorUtils = {}

-- Validates if a table has valid color properties
function ColorUtils.isValidColor(color)
	return color and type(color) == "table" and color.r and color.g and color.b
end

-- Extracts RGBA values from a color object
function ColorUtils.extractRGBA(color)
	return {color.r, color.g, color.b, color.a or 1}
end

-- Creates a color entry for palettes
function ColorUtils.createColorEntry(sort, description, color)
	return {
		sort = sort,
		description = description,
		color = color
	}
end

-- Sorts colors alphabetically by description
function ColorUtils.sortColorsByDescription(colors)
	table.sort(colors, function(a, b)
		return tostring(a.description) < tostring(b.description)
	end)
	return colors
end

-- Generic function to process color tables into palette format
function ColorUtils.processColorTable(colorTable, nameProvider, sortProvider)
    local colors = {}
    _.forEach(colorTable, function(v, k)
        if ColorUtils.isValidColor(v) then
            local name = nameProvider and nameProvider(k, v) or tostring(k)
            local sort = sortProvider and sortProvider(k, v) or k
            table.insert(colors, ColorUtils.createColorEntry(
                sort,
                name,
                ColorUtils.extractRGBA(v)
            ))
        end
    end)
    return colors
end

-- Process nested color tables (like PowerBarColor)
function ColorUtils.processNestedColorTable(colorTable, nameProvider)
    local colors = {}
    _.forEach(colorTable, function(v, k)
        if type(k) == "string" and v and type(v) == "table" then
            if ColorUtils.isValidColor(v) then
                local name = nameProvider and nameProvider(k, v) or tostring(k)
                table.insert(colors, ColorUtils.createColorEntry(k, name, ColorUtils.extractRGBA(v)))
            else
                -- Handle nested structures
                _.forEach(v, function(subVal, subKey)
                    if ColorUtils.isValidColor(subVal) then
                        local combinedKey = k .. "-" .. subKey
                        local combinedName = nameProvider and nameProvider(combinedKey, subVal) or combinedKey
                        table.insert(colors, ColorUtils.createColorEntry(combinedKey, combinedName, ColorUtils.extractRGBA(subVal)))
                    end
                end)
            end
        end
    end)
    return colors
end

-- Generic palette creation helpers
local function createBasicPalette(name, colors)
	return {
		name = L[name],
		colors = colors or {}
	}
end

local function createGenericPalette(colorTable, name, customProcessor)
	local colors = customProcessor and customProcessor(colorTable) or ColorUtils.processColorTable(colorTable)
	return createBasicPalette(name, ColorUtils.sortColorsByDescription(colors))
end

-- Palette creation functions
local PaletteCreators = {}

-- Creates the palette for last used colors
function PaletteCreators.createLastUsedPalette()
	return {
		name = L["lastUsedColors"],
		colors = {}
	}
end

-- Creates the favorites palette
function PaletteCreators.createFavoritePalette()
	return {
		name = L["favoriteColors"],
		colors = {}
	}
end

-- Creates the class colors palette
function PaletteCreators.createClassPalette()
    local classNames = LocalizedClassList()
    local sortedClasses = {}
    _.forEach(classNames, function(value, key)
        table.insert(sortedClasses, { key = key, value = value })
    end)
    table.sort(sortedClasses, function(a, b) return a.value < b.value end)

    local function processClassColors(colorsTable)
        local cTable = {}
        _.forEach(sortedClasses, function(classObj, idx)
            local colorObj = colorsTable[classObj.key]
            if colorObj and colorObj.GetRGBA then
                table.insert(cTable, ColorUtils.createColorEntry(
                    idx,
                    classObj.value,
                    {colorObj:GetRGBA()}
                ))
            end
        end)
        return cTable
    end

    local classTable = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    return {
        name = L["classColors"],
        colors = processClassColors(classTable)
    }
end

-- Creates the item quality colors palette
function PaletteCreators.createItemQualityPalette()
    local colors = {}
    _.forEach(Enum.ItemQuality, function(id, key)
        local entry = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[id]
        if ColorUtils.isValidColor(entry) then
            table.insert(colors, ColorUtils.createColorEntry(
                id,
                key,
                ColorUtils.extractRGBA(entry)
            ))
        end
    end)
    return createBasicPalette("ItemQuality", colors)
end

-- Creates the font colors palette
function PaletteCreators.createFontColorsPalette()
    local fontColorDefinitions = {
        {color = WHITE_FONT_COLOR, name = L["White"]},
        {color = RED_FONT_COLOR, name = L["Red"]},
        {color = GREEN_FONT_COLOR, name = L["Green"]},
        {color = BLUE_FONT_COLOR, name = L["Blue"]},
        {color = GRAY_FONT_COLOR, name = L["Gray"]},
        {color = BLACK_FONT_COLOR, name = L["Black"]},
        {color = HIGHLIGHT_FONT_COLOR, name = L["Highlight"]},
        {color = DISABLED_FONT_COLOR, name = L["Disabled"]},
        {color = DIM_RED_FONT_COLOR, name = L["DimRed"]},
        {color = ORANGE_FONT_COLOR, name = L["Orange"]},
        {color = YELLOW_FONT_COLOR, name = L["Yellow"]},
        {color = BRIGHTBLUE_FONT_COLOR, name = L["BrightBlue"]},
        {color = LIGHTYELLOW_FONT_COLOR, name = L["LightYellow"]},
        {color = ARTIFACT_GOLD_COLOR, name = L["ArtifactGold"]},
    }
    local colors = {}
    _.forEach(fontColorDefinitions, function(entry, i)
        if ColorUtils.isValidColor(entry.color) then
            table.insert(colors, ColorUtils.createColorEntry(
                i,
                entry.name,
                ColorUtils.extractRGBA(entry.color)
            ))
        end
    end)
    return createBasicPalette("FontColors", colors)
end

-- Creates the covenant colors palette
function PaletteCreators.createCovenantColorsPalette()
    local filtered = {}
    _.forEach(COVENANT_COLORS, function(v, k)
        if type(k) == "string" and ColorUtils.isValidColor(v) then
            table.insert(filtered, ColorUtils.createColorEntry(k, k, ColorUtils.extractRGBA(v)))
        end
    end)
    return createBasicPalette("CovenantColors", ColorUtils.sortColorsByDescription(filtered))
end

-- Creates the material text colors palette
function PaletteCreators.createMaterialTextColorsPalette()
	return createGenericPalette(MATERIAL_TEXT_COLOR_TABLE, "MaterialTextColors")
end

-- Creates the power bar colors palette
function PaletteCreators.createPowerBarPalette()
	local colors = ColorUtils.processNestedColorTable(PowerBarColor)
	return createBasicPalette("PowerBarColor", ColorUtils.sortColorsByDescription(colors))
end

-- Creates the objective tracker colors palette
function PaletteCreators.createObjectiveTrackerPalette()
	return createGenericPalette(OBJECTIVE_TRACKER_COLOR, "ObjectiveTrackerColor")
end

-- Creates the player faction colors palette
function PaletteCreators.createPlayerFactionColorsPalette()
    local factionNames = {
        [0] = "Horde",
        [1] = "Alliance"
    }
    local nameProvider = function(k, v) return factionNames[k] or tostring(k) end
    local colors = ColorUtils.processColorTable(PLAYER_FACTION_COLORS, nameProvider)
    -- Filter and sort by faction order
    local filteredColors = {}
    _.forEach(colors, function(color)
        if color.sort == 0 or color.sort == 1 then
            table.insert(filteredColors, color)
        end
    end)
    table.sort(filteredColors, function(a, b) return a.sort < b.sort end)
    return createBasicPalette("PlayerFactionColors", filteredColors)
end

-- Creates the material title text colors palette
function PaletteCreators.createMaterialTitleTextColorsPalette()
	return createGenericPalette(MATERIAL_TITLETEXT_COLOR_TABLE, "MaterialTitleTextColors")
end

-- Register palettes alphabetically
local paletteRegistry = {
	{"lastUsedColors", PaletteCreators.createLastUsedPalette},
	{"favoriteColors", PaletteCreators.createFavoritePalette},
	{"classColors", PaletteCreators.createClassPalette},
	{"CovenantColors", PaletteCreators.createCovenantColorsPalette},
	{"FontColors", PaletteCreators.createFontColorsPalette},
	{"ItemQuality", PaletteCreators.createItemQualityPalette},
	{"MaterialTextColors", PaletteCreators.createMaterialTextColorsPalette},
	{"MaterialTitleTextColors", PaletteCreators.createMaterialTitleTextColorsPalette},
	{"ObjectiveTrackerColor", PaletteCreators.createObjectiveTrackerPalette},
	{"PlayerFactionColors", PaletteCreators.createPlayerFactionColorsPalette},
	{"PowerBarColor", PaletteCreators.createPowerBarPalette},
}

-- Initialize all palettes
_.forEach(paletteRegistry, function(entry, order)
    local key, creatorFn = entry[1], entry[2]
    local palette = creatorFn()
    palette.order = order
    ColorTools.colorPalettes[key] = palette
end)
