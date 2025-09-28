local addonName, ColorTools =  ...
local L = LibStub("AceLocale-3.0"):GetLocale("ColorTools")
local _ = LibStub("LibLodash-1"):Get()




ColorToolsPaletteMixin = {}

function ColorToolsPaletteMixin:OnLoad()
	self.scrollBarHideable = false;
	ScrollFrame_OnLoad(self);

	self.swatchSize = ColorTools.config.swatchSize;
	self.spacer = ColorTools.config.spacer

	self.swatchSpace = self.swatchSize + self.spacer
	self.scrollheight = self.swatchSpace * 2

	self.Contents.NoContentText:SetPoint("TOP", self.swatchSpace - 7)
	self.pool = CreateFramePool("Button", self.Contents, "ColorToolsColorButton")
end


function ColorToolsPaletteMixin:updateColorPalette(width)
	if width then
		self:SetWidth(width)
		self.Contents:SetWidth(width)
		self:SetHeight(self.scrollheight)
		self.cols = math.floor(width/self.swatchSpace) - 1
	end


	self.pool:ReleaseAll();
	local palette = ColorTools.colorPalettes[ColorToolsDropdown.selected]
	local colors = (palette and palette.colors) or {}

	if ColorToolsDropdown.selected ~= "lastUsedColors" then 
		table.sort(colors, function(a,b) 
			local sa = tonumber(a.sort) or 0
			local sb = tonumber(b.sort) or 0
			return sa < sb
		end)
	end

	-- set child height
	local height = math.ceil(#colors / self.cols) * self.swatchSpace;
	height = math.max(self.scrollheight, height)
	self.Contents:SetHeight(height)

	local function getPos(type, index)
		index = index -1
		local row = math.floor(index / self.cols) 
		if type == "y" then return row * self.swatchSpace end
		return (index - (row * self.cols)) *  self.swatchSpace
	end


	self.Contents.NoContentText:SetShown(#colors == 0)

    _.forEach(colors, function(v, k)
        if not v then return end
        if not v.color then return end
        local frame = self.pool:Acquire()
        frame:SetPoint("TOPLEFT", self.Contents, "TOPLEFT", getPos("x", k), getPos("y", k) *-1)
        frame.Color:SetColorTexture(unpack(v.color))
        frame.color = v.color 
        frame.description = self:getDescription(v)
        frame:Show()
        frame:RegisterForClicks("RightButtonDown", "LeftButtonDown")
    end)
end



function ColorToolsPaletteMixin:getDescription(v)
	if v.description then return v.description end

	if ColorToolsDropdown.selected == "lastUsedColors" or ColorToolsDropdown.selected == "favoriteColors" then
		local currentColor = CreateColor(unpack(v.color))
		local matches = _.filter(ColorTools.allColors, function(color, k) return color.color:IsEqualTo(currentColor) end)
		if #matches == 0 then return "" end

		local out = {}
		_.forEach(matches, function(match)
			if match.name == L["infavoriteColors"] and ColorToolsDropdown.selected == "favoriteColors" then return end
			table.insert(out, match.name)
		end)
		return table.concat(out, "\n")
	end
	return v.description or ""
end



ColorToolsColorButtonMixin = {}


function ColorToolsColorButtonMixin:OnClick(button, b,c)
	if button == "LeftButton" then 
		ColorPickerFrame.Content.ColorPicker:SetColorRGB(unpack(self.color));
		if ColorPickerFrame.hasOpacity then
			ColorPickerFrame.Content.ColorPicker:SetColorAlpha(self.color[4])
		end
	elseif button == "RightButton" then 
		MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
			rootDescription:SetTag("MENU_COLORTOOLS_COLOR_SWATCH")
			if ColorTools.favorits:is(self.color) then 
				rootDescription:CreateButton(L["favoriteRemove"], function() ColorTools.favorits:remove(self.color) end)
			else
				local color = {
					sort = time(),
					description = self.description,
					color = self.color
				}
				rootDescription:CreateButton(L["favoriteAdd"], function() ColorTools.favorits:add(color) end)
			end
			self:SetFrameStrata("TOOLTIP")
		end)
	end
end




function ColorToolsColorButtonMixin:OnEnter()
	if not self.description then return end
	GameTooltip:SetOwner(ColorPickerFrame, "ANCHOR_CURSOR_RIGHT", 35, 0);
	GameTooltip:SetText(self.description, 1, 1, 1, 1, 1)
	GameTooltip:Show()
end

function ColorToolsColorButtonMixin:OnLeave()
	GameTooltip:Hide() 
end























ColorToolsDropdownMixin = {}


function ColorToolsDropdownMixin:OnLoad()
	-- self:SetWidth(160);

	-- ColorToolsDropdown.selected = ColorToolsSelected
	
	self:SetSelectionTranslator(function(selection)		
		return ColorTools.colorPalettes[selection.data].name;
	end);

	local items = {}
    _.forEach(ColorTools.colorPalettes, function(v, k)
        table.insert(items, {order = v.order, key = k, name = v.name})
    end)

    table.sort(items, function (a, b) return a.order < b.order end)
	items = _.map(items, function(entry) return {entry.name, entry.key}; end)

    MenuUtil.CreateRadioMenu(self,
        function(value)
          	return value == ColorToolsDropdown.selected
        end, 
        function(value)
			self.selected = value
			ColorToolsSelected = value
			ColorToolsPaletteFrame:updateColorPalette()
        end,
        unpack(items)
    )


	-- ugly fix for AceGUI 
	local function OnShow()
        self.menu:SetFrameStrata("TOOLTIP")
		-- self.menu:SetFrameStrata("TOOLTIP")
	end

 	self:RegisterCallback(DropdownButtonMixin.Event.OnMenuOpen, OnShow);
end











ColorToolsInputMixin = {}

function ColorToolsInputMixin:OnLoad()
	ColorPickerFrame.Content.HexBox:ClearAllPoints()
	ColorPickerFrame.Content.HexBox:SetPoint("TOPLEFT", ColorPickerFrame.Content, "TOPRIGHT", -40, -35)


	ColorPickerFrame.Content.ColorPicker:HookScript('OnColorSelect', function() 
		if ColorTools.updateRunning then return end
		self:UpdateInputs();
	end)
end

function ColorToolsInputMixin:OnShow()
	self:UpdateInputs();
end


function ColorToolsInputMixin:UpdateInputs()

	local colorsTable = {}
	colorsTable["R"], colorsTable["G"], colorsTable["B"], colorsTable["A"] = CreateColor(ColorPickerFrame.Content.ColorPicker:GetColorRGB()):GetRGBAAsBytes()
	colorsTable["H"], colorsTable["S"], colorsTable["V"] = ColorPickerFrame.Content.ColorPicker:GetColorHSV()
	colorsTable["A"] = ColorPickerFrame.Content.ColorPicker:GetColorAlpha()

	for k, input in pairs({self:GetChildren()}) do
        local type = input.text
        local color = colorsTable[type];
        if type == "S" or type == "V" or type == "A" then
            color = color * 100
        end

        if color < 0 then color = 0 end
        input:SetNumber(math.floor(color))
    end
end


function ColorToolsInputMixin:SetColor(mode, type, value)
	ColorTools.updateRunning =  true
	local colorsTable = {}
	if mode == "RGB" then
		colorsTable["R"], colorsTable["G"], colorsTable["B"] = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
		colorsTable[type] = value / 255
		ColorPickerFrame.Content.ColorPicker:SetColorRGB(colorsTable["R"], colorsTable["G"], colorsTable["B"])
	elseif mode == "HSV" then 
		colorsTable["H"], colorsTable["S"], colorsTable["V"] = ColorPickerFrame.Content.ColorPicker:GetColorHSV()
		colorsTable[type] = (type ~= "H") and value / 100 or value
		ColorPickerFrame.Content.ColorPicker:SetColorHSV(colorsTable["X"], colorsTable["Y"], colorsTable["Z"])
	elseif mode == "ALPHA" then 
		colorsTable[type] = ColorPickerFrame.Content.ColorPicker:GetColorAlpha()
		colorsTable[type] = value / 100
		ColorPickerFrame.Content.ColorPicker:SetColorAlpha(colorsTable[type])
	end

	ColorTools.updateRunning =  false
end




ColorToolsInputEditboxMixin = {}

function ColorToolsInputEditboxMixin:OnLoad()
    self:SetTextInsets(16, 0, 0, 0);
	self.Text:SetText(self.text)
end
function ColorToolsInputEditboxMixin:OnEscapePressed()
	self:ClearFocus()
	self:GetParent():SetColor(self.mode, self.text, self:GetNumber())
end

function ColorToolsInputEditboxMixin:OnEditFocusGained()
	self:HighlightText(0, self:GetNumLetters())
end

function ColorToolsInputEditboxMixin:OnEditFocusLost()
	self:HighlightText(self:GetNumLetters())
	self:GetParent():SetColor(self.mode, self.text, self:GetNumber())
end

function ColorToolsInputEditboxMixin:OnEnterPressed()
	self:ClearFocus() 
	self:GetParent():SetColor(self.mode, self.text, self:GetNumber())
end

function ColorToolsInputEditboxMixin:OnEnter()
	local title = L[string.format("EditBox_tooltip_%s", self.text)] or nil
	local desription = L[string.format("EditBox_tooltip_%s_description", self.text)] or nil
	if not title or not desription then return end

	GameTooltip:SetOwner(ColorPickerFrame, "ANCHOR_CURSOR_RIGHT", 35, 0);
	GameTooltip_SetTitle(GameTooltip, title)
	GameTooltip_AddNormalLine(GameTooltip, desription);
	GameTooltip:Show()
end

function ColorToolsInputEditboxMixin:OnLeave()
	GameTooltip:Hide() 
end








ColorToolsColorSwatchMixin = {}

function ColorToolsColorSwatchMixin:OnLoad()
	self:RegisterForClicks("RightButtonDown", "LeftButtonDown")
end
function ColorToolsColorSwatchMixin:OnClick(button)
	local r,g,b,a;
	if self.current then 
		r,g,b = ColorPickerFrame:GetColorRGB()
		a = ColorPickerFrame:GetColorAlpha()
	else 
		r,g,b,a = ColorPickerFrame:GetPreviousValues()
	end

	self.color = {
		sort = time(),
		color = {r,g,b,a}
	}

	if button == "LeftButton" then 
		if self.current then return end
		ColorPickerFrame.Content.ColorPicker:SetColorRGB(r,g,b);
	elseif button == "RightButton" then 

		MenuUtil.CreateContextMenu(self, function(ownerRegion, rootDescription)
			rootDescription:SetTag("MENU_COLORTOOLS_COLOR_SWATCH")
			if ColorTools.favorits:is(self.color.color) then
				rootDescription:CreateButton(L["favoriteRemove"], function() ColorTools.favorits:remove(self.color.color) end)
			else
				rootDescription:CreateButton(L["favoriteAdd"], function() ColorTools.favorits:add(self.color) end)
			end
			self:SetFrameStrata("TOOLTIP")
		end)
	end
end