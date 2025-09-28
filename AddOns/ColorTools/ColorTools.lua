local addonName, ColorTools =  ...
local L = LibStub("AceLocale-3.0"):GetLocale("ColorTools")
local _ = LibStub("LibLodash-1"):Get()

ColorTools.colorPalettes = {}

ColorTools.updateRunning = false

ColorTools.config = {
	frameExtend = 80,
	swatchSize = 32,
	spacer = 5,
	maxLastUsedColors = 30,
	selected = "lastUsedColors"
}



ColorTools.init = CreateFrame("Frame")
ColorTools.init:RegisterEvent("PLAYER_LOGIN")
ColorTools.init:SetScript("OnEvent", function()
	ColorToolsSelected = ColorToolsSelected or ColorTools.config.selected
	ColorToolsLastUsed = ColorToolsLastUsed or {}
	ColorToolsFavorites = ColorToolsFavorites or {}
	ColorTools.colorPalettes["lastUsedColors"].colors = ColorToolsLastUsed
	ColorTools.colorPalettes["favoriteColors"].colors = ColorToolsFavorites
	ColorPickerFrame:SetHeight(ColorPickerFrame:GetHeight() + 90)
	ColorToolsDropdown.selected = ColorToolsSelected
	ColorTools:gererateAllColorsTable()

	ColorTools.Options:init()
end)

ColorTools.allColors = {}


function ColorTools:gererateAllColorsTable()
	ColorTools.allColors = {}
	local allColorsi = 0
	_.forEach(ColorTools.colorPalettes, function(pallet, key)
		if key == "lastUsedColors" then return end

		
		_.forEach(pallet.colors, function(color, k)
			allColorsi = allColorsi + 1

			local pallettName = pallet.name
			local description = color.description


			if key == "favoriteColors" then
				pallettName = L["infavoriteColors"]
				description = nil
			end
			local format = description and "%s - %s" or "%s"
			table.insert(ColorTools.allColors, {
				name = string.format(format, pallettName, description),
				sort = allColorsi,
				color = CreateColor(unpack(color.color)),
			})
		end)
	end)

end


ColorPickerFrame.Footer.OkayButton:HookScript('OnClick', function()  
	local r, g, b = ColorPickerFrame:GetColorRGB();
	local alpha = ColorToolsOptions.lastUsedColors_alpha_as_new and ColorPickerFrame:GetColorAlpha() or 1
	local color = {r, g ,b, alpha}
	
	if ColorToolsOptions.lastUsedColors_duplicates then
		if not _.isEmpty(ColorToolsLastUsed) then
			local c1 = CreateColor(unpack(ColorToolsLastUsed[1].color))
			local c2 = CreateColor(unpack(color))

			if ColorToolsOptions.lastUsedColors_alpha_as_new then 
				if c1:IsEqualTo(c2) then return end
			else 
				if c1:IsEqualTo(c2) then return end
			end
		end
	end

	-- insert new color 
	table.insert(ColorToolsLastUsed, 1, { sort = time(), color = color })

	if not ColorToolsOptions.lastUsedColors_duplicates then
		ColorToolsLastUsed = _.uniq(ColorToolsLastUsed, function(n)
			if ColorToolsOptions.lastUsedColors_alpha_as_new then 
				return string.format("%d-%d-%d-%d", n.color[1], n.color[2], n.color[3], n.color[4])
			else
				return string.format("%d-%d-%d", n.color[1], n.color[2], n.color[3])
			end
		end)
	end

	ColorToolsLastUsed = _.slice(ColorToolsLastUsed, 1, ColorTools.config.maxLastUsedColors)
	ColorTools.colorPalettes["lastUsedColors"].colors = ColorToolsLastUsed
end)


ColorPickerFrame:HookScript('OnShow', function(self)
	self.Content:SetPoint("BOTTOMRIGHT", ColorPickerFrame, "BOTTOMRIGHT", ColorTools.config.frameExtend * -1, 0 )

	local w = 331 + ColorTools.config.frameExtend
	if self.hasOpacity then
		w = 388 + ColorTools.config.frameExtend
    end

	ColorPickerFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN");

	self:SetWidth(w);
	ColorToolsPaletteFrame:updateColorPalette(w)
end)   


function ColorTools.updateColorPalette(pallete)
	if ColorToolsDropdown.selected == "favoriteColors" then
		ColorToolsPaletteFrame:updateColorPalette()
	end
end










ColorTools.favorits = {}

function ColorTools.favorits:is(color, i)
	local fn = i and _.findIndex or _.find
	return fn(ColorToolsFavorites, function(entry)
		return CreateColor(unpack(entry.color)):IsEqualTo(CreateColor(unpack(color)))
	end)
end

function ColorTools.favorits:add(color)
	if self:is(color.color)then return end
	table.insert(ColorToolsFavorites, 1, color)
	ColorTools:updateColorPalette()
end

function ColorTools.favorits:remove(color)
	local index = self:is(color, true)
	table.remove(ColorToolsFavorites, index)
	ColorTools:updateColorPalette()
end











ColorTools.Options = {} 

function ColorTools.Options:init()
	ColorToolsOptions = ColorToolsOptions or {}

	local AddOnInfo = {C_AddOns.GetAddOnInfo(addonName)}
    local category, layout = Settings.RegisterVerticalLayoutCategory(AddOnInfo[2])
    self.category = category
    self.layout = layout
    Settings.RegisterAddOnCategory(category)
    ColorTools.OptionsID = category:GetID()



    self.layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["lastUsedColors"]));

	local setting = Settings.RegisterAddOnSetting(self.category, "lastUsedColors_duplicates", "lastUsedColors_duplicates", ColorToolsOptions, "boolean", L["Options_lastUsedColors_duplicates_name"], true)
    Settings.CreateCheckbox(self.category, setting, L["Options_lastUsedColors_duplicates_desc"])


	local setting = Settings.RegisterAddOnSetting(self.category, "lastUsedColors_alpha_as_new", "lastUsedColors_alpha_as_new", ColorToolsOptions, "boolean", L["Options_lastUsedColors_alpha_as_new_name"], true)
	setting:SetValueChangedCallback(function(self)
        if self:GetValue() then 
        else 
			ColorToolsLastUsed = _.forEach(ColorToolsLastUsed, function(entry)
				entry.color[4] = 1
				return entry
			end)
        end
    end)
	
	Settings.CreateCheckbox(self.category, setting, L["Options_lastUsedColors_alpha_as_new_desc"])


	StaticPopupDialogs["COLORTOOLS_COMFIRMCLEAN_ColorToolsLastUsed"] = {
		text =  L["Options_lastUsedColors_clearConfirm_text"],
		button1 = L["Options_lastUsedColors_clearConfirm_yes"],
		button2 = L["Options_lastUsedColors_clearConfirm_no"],
		OnAccept = function()
			ColorToolsLastUsed = {}
			ColorTools.colorPalettes["lastUsedColors"].colors =  {}
		 end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}

	local function onButtonClick()
		StaticPopup_Show("COLORTOOLS_COMFIRMCLEAN_ColorToolsLastUsed")
	end

	local addSearchTags = false;
	local initializer = CreateSettingsButtonInitializer("", L["Options_lastUsedColors_clearButton"], onButtonClick, nil, addSearchTags);
	layout:AddInitializer(initializer);
end