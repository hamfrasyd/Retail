local _, FragUI = ...
local PLAYER_CLASS = select(2, UnitClass("player"))
local PLAYER_CLASS_COLOR = RAID_CLASS_COLORS[PLAYER_CLASS]
local PLAYER_CLASS_COLOR_HEX = CreateColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b):GenerateHexColor()
local FONT = "Fonts\\FRIZQT__.ttf"
local Serialize = LibStub:GetLibrary("AceSerializer-3.0")
local Compress = LibStub:GetLibrary("LibDeflate")

function FragUI:RequestReload()
    StaticPopupDialogs["FRAGUI_RELOAD_PROMPT"] = {
        text = "Reload Required. Reload Now?",
        button1 = "Yes",
        button2 = "Later",
        OnAccept = function() ReloadUI() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("FRAGUI_RELOAD_PROMPT")
end

function FragUI:RequestConfirmation(confirmationRequested, confirmationFunction)
    StaticPopupDialogs["FRAGUI_REQUEST_CONFIRMATION"] = {
        text = "Are you sure you want to " .. confirmationRequested .. "?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = confirmationFunction,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("FRAGUI_REQUEST_CONFIRMATION")
end

function FragUI:GetAddOnProfilesList()
    local ShortenedExpected = {
        ["FragUI - Colour"] = "Colour",
        ["FragUI - Dark"] = "Dark",
        ["FragUI - Colour - Healer"] = "Colour - Healer",
        ["FragUI - Dark - Healer"] = "Dark - Healer",
    }

    local function FormatProfilesLine(addonDisplayName, db, expectedProfiles)
        if not db or type(db.profiles) ~= "table" then return nil end

        local existingProfiles = {}
        for profileName in pairs(db.profiles) do
            existingProfiles[profileName] = true
        end

        local displayProfiles = {}
        for _, expected in ipairs(expectedProfiles) do
            local label = ShortenedExpected[expected] or expected
            if existingProfiles[expected] then
                table.insert(displayProfiles, "|cFF40FF40" .. label .. "|r")
            else
                table.insert(displayProfiles, "|cFFFF4040" .. label .. "|r")
            end
        end

        return addonDisplayName .. ": " .. table.concat(displayProfiles, ", ")
    end

    local output = {}

    local list = {
        { name = "Unhalted Unit Frames", loaded = "UnhaltedUF", db = UUFDB, expected = { "FragUI - Colour", "FragUI - Dark" } },
        { name = "Grid2",                loaded = "Grid2",      db = Grid2DB, expected = { "FragUI - Colour", "FragUI - Dark", "FragUI - Colour - Healer", "FragUI - Dark - Healer" } },
        { name = "OmniCD",               loaded = "OmniCD",     db = OmniCDDB, expected = { "FragUI - Colour", "FragUI - Dark", "FragUI - Colour - Healer", "FragUI - Dark - Healer" } },
        { name = "BigWigs",              loaded = "BigWigs",    db = BigWigs3DB, expected = { "FragUI" } },
        { name = "Bufflehead",           loaded = "Bufflehead", db = BuffleheadDB, expected = { "FragUI" } },
        { name = "Prat",                 loaded = "Prat-3.0",   db = Prat3DB, expected = { "Default" } },
        { name = "BasicMinimap",         loaded = "BasicMinimap", db = BasicMinimapSV, expected = { "FragUI" } },
        { name = "OmniCC",               loaded = "OmniCC",     db = OmniCCDB, expected = { "FragUI" } },
    }

    for _, addon in ipairs(list) do
        if C_AddOns.IsAddOnLoaded(addon.loaded) then
            local line = FormatProfilesLine(addon.name, addon.db, addon.expected)
            if line then
                table.insert(output, line)
            end
        end
    end

    return table.concat(output, "\n")
end

local function SkipAllCinematics()
    if not FragUI.DB.global.General.SkipCinematics then return end
    local SkipCinematicsFrame = CreateFrame("Frame")
    SkipCinematicsFrame:RegisterEvent("CINEMATIC_START")
    SkipCinematicsFrame:SetScript("OnEvent", function(self, event, ...) if event == "CINEMATIC_START" then CinematicFrame_CancelCinematic() end end)
    MovieFrame_PlayMovie = function(...)
        CinematicFinished(0)
        CinematicFinished(1)
        CinematicFinished(2)
        CinematicFinished(3)
    end
end

local function HideTalkingHeadFrame()
    if not FragUI.DB.global.General.HideTalkingHead then return end
    local TalkingHeadBlocker = CreateFrame("Frame", nil, UIParent)
    TalkingHeadBlocker:SetAllPoints(TalkingHeadFrame)
    TalkingHeadBlocker:SetFrameStrata("BACKGROUND")
    TalkingHeadBlocker:RegisterEvent("TALKINGHEAD_REQUESTED")
    TalkingHeadBlocker:HookScript("OnEvent", function(self, event, ...)
        if event == "TALKINGHEAD_REQUESTED" then
            TalkingHeadFrame:SetAlpha(0)
            TalkingHeadFrame:Hide()
        end
    end)
end

local function CleanUpChat()
    if not FragUI.DB.global.General.CleanUpChat then return end
    if not C_AddOns.IsAddOnLoaded("Prat-3.0") then return end
    for i = 1, NUM_CHAT_WINDOWS do
        local chatFrame = _G["ChatFrame" .. i]
        local chatFrameScrollBar = chatFrame.ScrollBar
        if chatFrameScrollBar then
            chatFrameScrollBar:UnregisterAllEvents()
            chatFrameScrollBar:SetScript("OnShow", chatFrameScrollBar.Hide)
            chatFrameScrollBar:Hide()
        end
        chatFrame:SetShadowColor(0, 0, 0, 1)
        chatFrame:SetShadowOffset(0, 0)
    end
    C_Timer.After(1, function() ChatFrame1EditBox:ClearAllPoints() ChatFrame1EditBox:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 1, 1) ChatFrame1EditBox:SetWidth(ChatFrame1:GetWidth() - 2) ChatFrame1EditBox:SetHeight(28) end)
end

local function StyleBlizzard()
    if not FragUI.DB.global.General.StyleBlizzard then return end
    local Frames = {
        ZoneTextFrame,
        SubZoneTextFrame,
        ObjectiveTrackerFrame.Header.Background,
        QuestObjectiveTracker.Header.Background,
        WorldQuestObjectiveTracker.Header.Background,
        ScenarioObjectiveTracker.Header.Background,
        MonthlyActivitiesObjectiveTracker.Header.Background,
        BonusObjectiveTracker.Header.Background,
        ProfessionsRecipeTracker.Header.Background,
        AchievementObjectiveTracker.Header.Background,
        CampaignQuestObjectiveTracker.Header.Background,
    }
    for _, Frame in pairs(Frames) do
        Frame:SetAlpha(0) Frame:Hide() Frame:SetScript("OnShow", function(Frame) Frame:SetAlpha(0) Frame:Hide() end)
    end

end

local function StyleCharacterPane()
    if not FragUI.DB.global.CharacterPane.StyleCharacterPane then return end
    CharacterStatsPane.ItemLevelCategory.Title:SetTextColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b)
    CharacterStatsPane.AttributesCategory.Title:SetTextColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b)
    CharacterStatsPane.EnhancementsCategory.Title:SetTextColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b)
    CharacterModelScene.ControlFrame:SetAlpha(0)
    CharacterModelScene.ControlFrame:Hide()
    CharacterModelScene.ControlFrame:SetScript("OnShow", function() CharacterModelScene.ControlFrame:SetAlpha(0) CharacterModelScene.ControlFrame:Hide() end)

    local Fonts = {
        CharacterLevelText,
        CharacterFrameTitleText,
        CharacterStatsPane.ItemLevelCategory.Title,
        CharacterStatsPane.AttributesCategory.Title,
        CharacterStatsPane.EnhancementsCategory.Title,
    }
    for _, Font in pairs(Fonts) do
        Font:SetFont(FONT, 12, "OUTLINE")
        Font:SetShadowOffset(0, 0)
    end
end

local function SetPlayerItemLevel() local _, iLvlEquipped = GetAverageItemLevel() return string.format("%." .. FragUI.DB.global.CharacterPane.ItemLevelDecimals .. "f", iLvlEquipped) end

local function StyleItemLevelFrame()
    if not FragUI.DB.global.CharacterPane.StyleItemLevelFrame then return end
    CharacterStatsPane.ItemLevelFrame.Value:SetAlpha(0)
    CharacterStatsPane.ItemLevelFrame.Value:Hide()
    CharacterStatsPane.ItemLevelFrame.Value:HookScript("OnShow", function(self) self:SetAlpha(0) self:Hide() end)
    local FragUIItemLevelFrame = CreateFrame("Frame", "FragUIItemLevelFrame", CharacterStatsPane.ItemLevelCategory)
    FragUIItemLevelFrame:SetSize(120, 24)
    FragUIItemLevelFrame:SetPoint("TOP", CharacterStatsPane.ItemLevelCategory, "BOTTOM", 0, -3)
    FragUIItemLevelFrame:SetFrameStrata("HIGH")
    FragUIItemLevelFrame.Text = FragUIItemLevelFrame:CreateFontString(nil, "OVERLAY")
    FragUIItemLevelFrame.Text:SetFont(FONT, FragUI.DB.global.CharacterPane.ItemLevelFontSize, "OUTLINE")
    FragUIItemLevelFrame.Text:SetShadowOffset(0, 0)
    FragUIItemLevelFrame.Text:SetTextColor(0.64, 0.21, 0.93)
    FragUIItemLevelFrame.Text:SetPoint("CENTER", FragUIItemLevelFrame, "CENTER", 0, 0)
    FragUIItemLevelFrame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
    FragUIItemLevelFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    FragUIItemLevelFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    FragUIItemLevelFrame:SetScript("OnEvent", function(_, event, ...) FragUIItemLevelFrame.Text:SetText(SetPlayerItemLevel()) end)
    FragUI.FragUIItemLevelFrame = FragUIItemLevelFrame
end

function FragUI:UpdateItemLevelFrame()
    if not FragUI.DB.global.CharacterPane.StyleItemLevelFrame then return end
    if not self.FragUIItemLevelFrame then return end

    self.FragUIItemLevelFrame.Text:SetFont(FONT, FragUI.DB.global.CharacterPane.ItemLevelFontSize, "OUTLINE")
    self.FragUIItemLevelFrame.Text:SetText(SetPlayerItemLevel())
end

local AnchorToJustification = {
    ["TOPLEFT"] = "LEFT",
    ["TOPRIGHT"] = "RIGHT",
    ["BOTTOMLEFT"] = "LEFT",
    ["BOTTOMRIGHT"] = "RIGHT",
    ["LEFT"] = "LEFT",
    ["RIGHT"] = "RIGHT",
    ["CENTER"] = "CENTER",
    ["TOP"] = "CENTER",
    ["BOTTOM"] = "CENTER",
}

local function CreateDurabilityFrame()
    if not FragUI.DB.global.CharacterPane.ShowDurabilityFrame then return end
    local FragUIDurabilityFrame = CreateFrame("Frame", "FragUIDurabilityFrame", CharacterModelScene)
    FragUIDurabilityFrame:SetSize(120, FragUI.DB.global.CharacterPane.DurabilityFrameFontSize + 6)
    FragUIDurabilityFrame:SetPoint(FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom, CharacterModelScene, FragUI.DB.global.CharacterPane.DurabilityFrameAnchorTo, FragUI.DB.global.CharacterPane.DurabilityFrameOffsetX, FragUI.DB.global.CharacterPane.DurabilityFrameOffsetY)
    FragUIDurabilityFrame:SetFrameStrata("HIGH")
    FragUIDurabilityFrame.Text = FragUIDurabilityFrame:CreateFontString(nil, "OVERLAY")
    FragUIDurabilityFrame.Text:SetFont(FONT, FragUI.DB.global.CharacterPane.DurabilityFrameFontSize, "OUTLINE")
    FragUIDurabilityFrame.Text:SetShadowOffset(0, 0)
    FragUIDurabilityFrame.Text:SetPoint(AnchorToJustification[FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom], FragUIDurabilityFrame, AnchorToJustification[FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom], 0, 0)
    FragUIDurabilityFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    FragUIDurabilityFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    FragUIDurabilityFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_INVENTORY_DURABILITY" then
            local TotalDurability, CurrentDurability = 0, 0
            for i = 1, 18 do
                local SlotDurability, SlotMaxDurability = GetInventoryItemDurability(i)
                if SlotDurability then
                    TotalDurability = TotalDurability + SlotMaxDurability
                    CurrentDurability = CurrentDurability + SlotDurability
                end
            end
            local DurabilityPercentage = CurrentDurability / TotalDurability * 100
            FragUIDurabilityFrame.Text:SetText(format("|c%sDurability|r: %.f%%", PLAYER_CLASS_COLOR_HEX, DurabilityPercentage))
        end
    end)
    FragUI.FragUIDurabilityFrame = FragUIDurabilityFrame
    FragUIDurabilityFrame:GetScript("OnEvent")(FragUIDurabilityFrame, "UPDATE_INVENTORY_DURABILITY")
end

function FragUI:UpdateDurabilityFrame()
    if not FragUI.DB.global.CharacterPane.ShowDurabilityFrame then
        if self.FragUIDurabilityFrame then
            self.FragUIDurabilityFrame:UnregisterAllEvents()
            self.FragUIDurabilityFrame:Hide()
            self.FragUIDurabilityFrame = nil
        end
    else
        if self.FragUIDurabilityFrame then
            self.FragUIDurabilityFrame:Show()
        else
            FragUI:CreateDurabilityFrame()
            self.FragUIDurabilityFrame:Show()
        end

        if self.FragUIDurabilityFrame then
            self.FragUIDurabilityFrame:ClearAllPoints()
            self.FragUIDurabilityFrame:SetPoint(
                FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom,
                CharacterModelScene,
                FragUI.DB.global.CharacterPane.DurabilityFrameAnchorTo,
                FragUI.DB.global.CharacterPane.DurabilityFrameOffsetX,
                FragUI.DB.global.CharacterPane.DurabilityFrameOffsetY
            )
            self.FragUIDurabilityFrame.Text:SetFont(FONT, FragUI.DB.global.CharacterPane.DurabilityFrameFontSize, "OUTLINE")
            self.FragUIDurabilityFrame.Text:SetPoint(AnchorToJustification[FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom], self.FragUIDurabilityFrame, AnchorToJustification[FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom], 0, 0)
            self.FragUIDurabilityFrame:Show()
        end
    end
    if self.FragUIDurabilityFrame and self.FragUIDurabilityFrame:GetScript("OnEvent") then
        self.FragUIDurabilityFrame:GetScript("OnEvent")(self.FragUIDurabilityFrame, "UPDATE_INVENTORY_DURABILITY")
    end
end

local function StyleActionStatusText()
    if not FragUI.DB.global.BlizzardFonts.StyleActionStatusText then return end
    ActionStatus.Text:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ActionStatusTextFontSize, "OUTLINE")
    ActionStatus.Text:SetShadowOffset(0, 0)
    ActionStatus.Text:ClearAllPoints()
    ActionStatus.Text:SetPoint(FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorFrom, UIParent, FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorTo, FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetX, FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetY)
end

function FragUI:UpdateActionStatusText()
    if not FragUI.DB.global.BlizzardFonts.StyleActionStatusText then return end
    ActionStatus.Text:SetText("FragUI: Updating Frame...")
    ActionStatus.Text:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ActionStatusTextFontSize, "OUTLINE")
    ActionStatus.Text:SetShadowOffset(0, 0)
    ActionStatus.Text:ClearAllPoints()
    ActionStatus.Text:SetPoint(FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorFrom, UIParent, FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorTo, FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetX, FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetY)
    ActionStatus.startTime = GetTime()
    ActionStatus.holdTime = 10
    ActionStatus.fadeTime = 1
    ActionStatus:Show()
end

local function StyleUIErrorsFrame()
    if FragUI.DB.global.BlizzardFonts.HideUIErrorsFrame then
        UIErrorsFrame:UnregisterAllEvents()
        UIErrorsFrame:Hide()
        return
    end
    if not FragUI.DB.global.BlizzardFonts.StyleUIErrorsFrame then return end
    UIErrorsFrame:SetFont(FONT, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextFontSize, "OUTLINE")
    UIErrorsFrame:SetShadowOffset(0, 0)
    UIErrorsFrame:ClearAllPoints()
    UIErrorsFrame:SetPoint(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorFrom, UIParent, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorTo, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetX, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetY)
end

function FragUI:UpdateUIErrorsFrame()
    if not FragUI.DB.global.BlizzardFonts.StyleUIErrorsFrame then return end
    UIErrorsFrame:AddMessage("FragUI: Updating Frame...", 1, 0, 0, 1.0, 10)
    UIErrorsFrame:SetFont(FONT, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextFontSize, "OUTLINE")
    UIErrorsFrame:SetShadowOffset(0, 0)
    UIErrorsFrame:ClearAllPoints()
    UIErrorsFrame:SetPoint(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorFrom, UIParent, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorTo, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetX, FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetY)
end

local function StyleChatBubbleFont()
    if not FragUI.DB.global.BlizzardFonts.StyleChatBubbleText then return end
    ChatBubbleFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ChatBubbleTextFontSize, "OUTLINE")
end

function FragUI:UpdateChatBubbleFont()
    if not FragUI.DB.global.BlizzardFonts.StyleChatBubbleText then return end
    ChatBubbleFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ChatBubbleTextFontSize, "OUTLINE")
end

local function StyleObjectiveTrackerFonts()
    if not FragUI.DB.global.BlizzardFonts.StyleObjectiveTracker then return end
    ObjectiveTrackerLineFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ObjectiveTrackerLineFontSize, "OUTLINE")
    ObjectiveTrackerLineFont:SetShadowOffset(0, 0)
    ObjectiveTrackerHeaderFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ObjectiveTrackerHeaderFontSize, "OUTLINE")
    ObjectiveTrackerHeaderFont:SetShadowOffset(0, 0)
end

function FragUI:UpdateObjectiveTrackerFonts()
    if not FragUI.DB.global.BlizzardFonts.StyleObjectiveTracker then return end
    ObjectiveTrackerLineFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ObjectiveTrackerLineFontSize, "OUTLINE")
    ObjectiveTrackerLineFont:SetShadowOffset(0, 0)
    ObjectiveTrackerHeaderFont:SetFont(FONT, FragUI.DB.global.BlizzardFonts.ObjectiveTrackerHeaderFontSize, "OUTLINE")
    ObjectiveTrackerHeaderFont:SetShadowOffset(0, 0)
end

local function DrawDetailsBackdrops()
    local DBF1 = _G["DetailsBaseFrame1"]
    local DWF1 = _G["Details_WindowFrame1"]
    local DBF2 = _G["DetailsBaseFrame2"]
    local DWF2 = _G["Details_WindowFrame2"]
    if not C_AddOns.IsAddOnLoaded("Details") then return end
    if _detalhes_global then
        if (_detalhes_global and _detalhes_global["always_use_profile"] and _detalhes_global["always_use_profile"] == true and _detalhes_global["always_use_profile_name"] ~= "FragUI") or (_detalhes_database and _detalhes_database["active_profile"] and _detalhes_database["active_profile"] ~= "FragUI") then
            return
        end
    end
    if not DBF1 or not DWF1 or not DBF2 or not DWF2 then
        print("|cFF8080FFFrag|rUI: Details Backdrops could not be created. Please ensure Details! is installed and enabled.")
        return
    end
    local DetailsFrameOne = CreateFrame("Frame", "DetailsFrameOne", UIParent, "BackdropTemplate")
    if FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Enabled then
        DetailsFrameOne:Show()
    else
        DetailsFrameOne:Hide()
    end
    DetailsFrameOne:SetSize(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Width, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Rows * 28.2)
    DetailsFrameOne:SetPoint(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom, UIParent, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY)
    DetailsFrameOne:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 1, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    DetailsFrameOne:SetBackdropColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[4])
    DetailsFrameOne:SetBackdropBorderColor(0, 0, 0, 1)
    DetailsFrameOne:SetFrameStrata("LOW")
    DBF1:ClearAllPoints()
    DWF1:ClearAllPoints()
    DBF1:SetSize(DetailsFrameOne:GetWidth() - 2, DetailsFrameOne:GetHeight())
    DWF1:SetSize(DetailsFrameOne:GetWidth() - 2, DetailsFrameOne:GetHeight())
    DBF1:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "BOTTOMRIGHT", -1, -1)
    DWF1:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "BOTTOMRIGHT", -1, -1)
    local DetailsFrameTwo = CreateFrame("Frame", "DetailsFrameTwo", UIParent, "BackdropTemplate")
    if FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Enabled then
        DetailsFrameTwo:Show()
    else
        DetailsFrameTwo:Hide()
    end
    DetailsFrameTwo:SetSize(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Width, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Rows * 28.2)
    DetailsFrameTwo:SetPoint(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom, DetailsFrameOne, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY)
    DetailsFrameTwo:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true, tileSize = 1, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    DetailsFrameTwo:SetBackdropColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[4])
    DetailsFrameTwo:SetBackdropBorderColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[4])
    DetailsFrameTwo:SetFrameStrata("LOW")
    DBF2:ClearAllPoints()
    DWF2:ClearAllPoints()
    DBF2:SetSize(DetailsFrameTwo:GetWidth() - 2, DetailsFrameTwo:GetHeight())
    DWF2:SetSize(DetailsFrameTwo:GetWidth() - 2, DetailsFrameTwo:GetHeight())
    DBF2:SetPoint("BOTTOMRIGHT", DetailsFrameTwo, "BOTTOMRIGHT", -1, -1)
    DWF2:SetPoint("BOTTOMRIGHT", DetailsFrameTwo, "BOTTOMRIGHT", -1, -1)
end

function FragUI:UpdateDetailsBackdrops()
    local DetailsFrameOne = _G["DetailsFrameOne"]
    local DetailsFrameTwo = _G["DetailsFrameTwo"]
    local DBF1 = _G["DetailsBaseFrame1"]
    local DWF1 = _G["Details_WindowFrame1"]
    local DBF2 = _G["DetailsBaseFrame2"]
    local DWF2 = _G["Details_WindowFrame2"]

    if FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Enabled then
        DetailsFrameOne:Show()
    else
        DetailsFrameOne:Hide()
    end
    DetailsFrameOne:ClearAllPoints()
    DetailsFrameOne:SetSize(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Width, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Rows * 28.2)
    DetailsFrameOne:SetPoint(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom, UIParent, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX, FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY)
    DetailsFrameOne:SetBackdropColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor[4])
    DetailsFrameOne:SetBackdropBorderColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor[4])
    DBF1:ClearAllPoints()
    DWF1:ClearAllPoints()
    DBF1:SetSize(DetailsFrameOne:GetWidth() - 2, DetailsFrameOne:GetHeight())
    DWF1:SetSize(DetailsFrameOne:GetWidth() - 2, DetailsFrameOne:GetHeight())
    DBF1:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "BOTTOMRIGHT", -1, -1)
    DWF1:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "BOTTOMRIGHT", -1, -1)

    if FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Enabled then
        DetailsFrameTwo:Show()
    else
        DetailsFrameTwo:Hide()
    end

    DetailsFrameTwo:ClearAllPoints()
    DetailsFrameTwo:SetSize(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Width, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Rows * 28.2)
    DetailsFrameTwo:SetPoint(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom, DetailsFrameOne, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX, FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY)
    DetailsFrameTwo:SetBackdropColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor[4])
    DetailsFrameTwo:SetBackdropBorderColor(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[1], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[2], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[3], FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor[4])
    DBF2:ClearAllPoints()
    DWF2:ClearAllPoints()
    DBF2:SetSize(DetailsFrameTwo:GetWidth() - 2, DetailsFrameTwo:GetHeight())
    DWF2:SetSize(DetailsFrameTwo:GetWidth() - 2, DetailsFrameTwo:GetHeight())
    DBF2:SetPoint("BOTTOMRIGHT", DetailsFrameTwo, "BOTTOMRIGHT", -1, -1)
    DWF2:SetPoint("BOTTOMRIGHT", DetailsFrameTwo, "BOTTOMRIGHT", -1, -1)
end

function FragUI:ApplyDetailsPreset(selectedPreset)
    if selectedPreset == "Horizontal" then
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX = -1
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY = 1.1
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo = "BOTTOMLEFT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX = -1
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY = 0.1
    end

    if selectedPreset == "Vertical" then
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX = -1
        FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY = 1.1
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom = "BOTTOMRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo = "TOPRIGHT"
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX = 0
        FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY = 25.1
    end
end

local function ApplyAddonProfile(addonName, db, dbKey, targetProfile, logoPath)
    if InCombatLockdown() then return end
    if not db or not C_AddOns.IsAddOnLoaded(addonName) then return end
    if db["profiles"][targetProfile] == nil then
        print(string.format("|T%s:16:16|t%s|r: |cFFFF4040%s|r: |cFFFFFFFFThis profile does not exist, please import it via the WagoApp!|r", logoPath, addonName, targetProfile))
        return
    end

    local charName, charRealm = UnitName("player"), GetRealmName()
    local profileKey = charName .. " - " .. charRealm
    local currentProfile = db["profileKeys"][profileKey]

    if currentProfile == targetProfile then
        print(string.format("|T%s:16:16|t%s|r: |cFF40FF40%s|r: |cFFFFFFFFAlready Applied!|r", logoPath, addonName, targetProfile))
        return
    else
        db["profileKeys"][profileKey] = targetProfile
        print(string.format("|T%s:16:16|t%s|r: |cFFFF4040%s|r to |cFF40FF40%s|r", logoPath, addonName, currentProfile or "None", targetProfile))
    end
end

local function ApplyUUFProfile(newProfile)
    if InCombatLockdown() then return end
    if not UUFDB or not C_AddOns.IsAddOnLoaded("UnhaltedUF") then return end

    local profileAssignment = {
        ["FragUI - Dark - Healer"] = "FragUI - Dark",
        ["FragUI - Colour - Healer"] = "FragUI - Colour",
    }

    local resolvedProfile = profileAssignment[newProfile] or newProfile

    if UUFDB["profiles"][resolvedProfile] == nil then
        print("|TInterface/AddOns/UnhaltedUF/Media/Logo.tga:16:16|tUnhalted Unit Frames|r: |cFFFF4040" .. resolvedProfile .. "|r: |cFFFFFFFFThis profile does not exist, please import it via the WagoApp!|r")
        return
    end

    local name, realm = UnitName("player"), GetRealmName()
    local profileKey = name .. " - " .. realm
    local current = UUFDB["profileKeys"][profileKey] or UUFDB["global"]["GlobalProfile"]

    if current == resolvedProfile then
        print("|TInterface/AddOns/UnhaltedUF/Media/Logo.tga:16:16|tUnhalted Unit Frames|r: |cFF40FF40" .. resolvedProfile .. "|r: |cFFFFFFFFAlready Applied!|r")
        return
    end

    if UUFDB["global"]["UseGlobalProfile"] then
        UUFDB["global"]["GlobalProfile"] = resolvedProfile
    else
        UUFDB["profileKeys"][profileKey] = resolvedProfile
    end

    print("|TInterface/AddOns/UnhaltedUF/Media/Logo.tga:16:16|tUnhalted Unit Frames|r: |cFFFF4040" .. current .. "|r to |cFF40FF40" .. resolvedProfile)
end


function FragUI:ApplyProfiles(newProfile)
    local steps = {
        function() ApplyUUFProfile(newProfile) end,
        function() ApplyAddonProfile("Grid2", Grid2DB, "profileKeys", newProfile, "Interface/AddOns/Grid2/media/iconsmall.tga") end,
        function() ApplyAddonProfile("OmniCD", OmniCDDB, "profileKeys", newProfile, "Interface/AddOns/OmniCD/Media/omnicd-logo64-c.tga") end,
        function() ApplyAddonProfile("BigWigs", BigWigs3DB, "profileKeys", "FragUI", "Interface/AddOns/BigWigs/Media/Icons/minimap_raid.tga") end,
        function() ApplyAddonProfile("Bufflehead", BuffleheadDB, "profileKeys", "FragUI", "Interface/AddOns/FragUI/Media/FragUI.png") end,
        function() ApplyAddonProfile("Prat-3.0", Prat3DB, "profileKeys", "Default", "Interface/AddOns/Prat-3.0/textures/prat.tga") end,
        function() ApplyAddonProfile("BasicMinimap", BasicMinimapSV, "profileKeys", "FragUI", "Interface/AddOns/FragUI/Media/FragUI.png") end,
        function() ApplyAddonProfile("OmniCC", OmniCCDB, "profileKeys", "FragUI", "Interface/Icons/spell_nature_timestop") end,
        function() ApplyAddonProfile("ls_Toasts", LS_TOASTS_GLOBAL_CONFIG, "profileKeys", "FragUI", "Interface/AddOns/ls_Toasts/assets/logo-64") end,
        function() print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: All Profiles Applied! Please reload!") end,
        function() FragUI:RequestReload() end,
    }

    for i, step in ipairs(steps) do
        C_Timer.After(i * 0.5, step)
    end
end

function FragUI:ExportBufflehead()
    local BuffleheadData = BuffleheadDB["profiles"]["FragUI"]
    local SerializedData = Serialize:Serialize(BuffleheadData)
    local CompressedData = Compress:CompressDeflate(SerializedData)
    local EncodedData = Compress:EncodeForPrint(CompressedData)
    StaticPopupDialogs["FRAGUI_EXPORT_BUFFLEHEAD"] = {
        text = "Bufflehead Data Exported. Copy the data below.",
        button1 = "OK",
        hasEditBox = true,
        maxLetters = 0,
        editBoxWidth = 400,
        OnShow = function(self)
            self.EditBox:SetText(EncodedData)
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FRAGUI_EXPORT_BUFFLEHEAD")
end

function FragUI:ImportBufflehead()
    if not C_AddOns.IsAddOnLoaded("Bufflehead") then
        print("|cFF8080FFFrag|rUI: Bufflehead isn't installed or loaded. Please ensure this is the case before importing.")
        return
    end
    local ImportString = FragUI:FetchBuffleheadString()
    local DecodedData = Compress:DecodeForPrint(ImportString)
    local DecompressedData = Compress:DecompressDeflate(DecodedData)
    local _, BuffleheadData = Serialize:Deserialize(DecompressedData)
    BuffleheadDB.profiles = BuffleheadDB.profiles or {}
    BuffleheadDB.profileKeys = BuffleheadDB.profileKeys or {}

    local CharacterProfile = UnitName("player") .. " - " .. GetRealmName()

    if BuffleheadDB.profiles["FragUI"] then
        wipe(BuffleheadDB.profiles["FragUI"])
        BuffleheadDB.profiles["FragUI"] = BuffleheadData
        BuffleheadDB.profileKeys[CharacterProfile] = "FragUI"
    else
        BuffleheadDB.profiles["FragUI"] = BuffleheadData
        BuffleheadDB.profileKeys[CharacterProfile] = "FragUI"
    end
    BuffleheadDB["global"]["hideOmniCC"] = false
end

function FragUI:ExportPrat()
    local Prat3Data = Prat3DB["profiles"]["FragUI"]
    local Prat3Namespaces = Prat3DB["namespaces"]
    local SerializedData = Serialize:Serialize(Prat3Data)
    local SerializedNamespaces = Serialize:Serialize(Prat3Namespaces)
    local CompressedData = Compress:CompressDeflate(SerializedData)
    local CompressedNamespaces = Compress:CompressDeflate(SerializedNamespaces)
    local EncodedData = Compress:EncodeForPrint(CompressedData)
    local EncodedNamespaces = Compress:EncodeForPrint(CompressedNamespaces)
    StaticPopupDialogs["FRAGUI_EXPORT_PRAT"] = {
        text = "Prat3 Data Exported. Copy the data below.",
        button1 = "OK",
        hasEditBox = true,
        maxLetters = 0,
        editBoxWidth = 400,
        OnShow = function(self)
            self.EditBox:SetText(EncodedData)
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopupDialogs["FRAGUI_EXPORT_PRAT_NAMESPACES"] = {
        text = "Prat3 Namespaces Exported. Copy the data below.",
        button1 = "OK",
        hasEditBox = true,
        maxLetters = 0,
        editBoxWidth = 400,
        OnShow = function(self)
            self.EditBox:SetText(EncodedNamespaces)
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FRAGUI_EXPORT_PRAT_NAMESPACES")
    StaticPopup_Show("FRAGUI_EXPORT_PRAT")
end

function FragUI:ImportPrat()
        if not C_AddOns.IsAddOnLoaded("Prat-3.0") then
        print("|cFF8080FFFrag|rUI: Prat isn't installed or loaded. Please ensure this is the case before importing.")
        return
    end
    local DataImport = FragUI:FetchPratDataString()
    local NamespacesImport = FragUI:FetchPratNamespacesString()
    local DecodedData = Compress:DecodeForPrint(DataImport)
    local NamespaceData = Compress:DecodeForPrint(NamespacesImport)
    local DecompressedData = Compress:DecompressDeflate(DecodedData)
    local DecompressedNamespaces = Compress:DecompressDeflate(NamespaceData)
    local _, PratData = Serialize:Deserialize(DecompressedData)
    local _, PratNamespaces = Serialize:Deserialize(DecompressedNamespaces)
    Prat3DB.profiles = Prat3DB.profiles or {}
    Prat3DB.profileKeys = Prat3DB.profileKeys or {}

    local CharacterProfile = UnitName("player") .. " - " .. GetRealmName()

    if Prat3DB.profiles["Default"] then
        wipe(Prat3DB.profiles["Default"])
        wipe(Prat3DB["namespaces"])
        Prat3DB["namespaces"] = PratNamespaces
        Prat3DB.profiles["Default"] = PratData
        Prat3DB.profileKeys[CharacterProfile] = "Default"
    else
        Prat3DB["namespaces"] = PratNamespaces
        Prat3DB.profiles["Default"] = PratData
        Prat3DB.profileKeys[CharacterProfile] = "Default"
    end
end

function FragUI:ExportBasicMinimap()
    local BasicMinimapData = BasicMinimapSV["profiles"]["FragUI"]
    local SerializedData = Serialize:Serialize(BasicMinimapData)
    local CompressedData = Compress:CompressDeflate(SerializedData)
    local EncodedData = Compress:EncodeForPrint(CompressedData)
    StaticPopupDialogs["FRAGUI_EXPORT_BASICMINIMAP"] = {
        text = "BasicMinimap Data Exported. Copy the data below.",
        button1 = "OK",
        hasEditBox = true,
        maxLetters = 0,
        editBoxWidth = 400,
        OnShow = function(self)
            self.EditBox:SetText(EncodedData)
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FRAGUI_EXPORT_BASICMINIMAP")
end

function FragUI:ImportBasicMinimap()
    if not C_AddOns.IsAddOnLoaded("BasicMinimap") then
        print("|cFF8080FFFrag|rUI: BasicMinimap isn't installed or loaded. Please ensure this is the case before importing.")
        return
    end
    local DataImport = FragUI:FetchBasicMinimapString()
    local DecodedData = Compress:DecodeForPrint(DataImport)
    local DecompressedData = Compress:DecompressDeflate(DecodedData)
    local _, BasicMinimapData = Serialize:Deserialize(DecompressedData)
    BasicMinimapSV.profiles = BasicMinimapSV.profiles or {}
    BasicMinimapSV.profileKeys = BasicMinimapSV.profileKeys or {}

    local CharacterProfile = UnitName("player") .. " - " .. GetRealmName()

    if BasicMinimapSV.profiles["FragUI"] then
        wipe(BasicMinimapSV.profiles["FragUI"])
        BasicMinimapSV.profiles["FragUI"] = BasicMinimapData
        BasicMinimapSV.profileKeys[CharacterProfile] = "FragUI"
    else
        BasicMinimapSV.profiles["FragUI"] = BasicMinimapData
        BasicMinimapSV.profileKeys[CharacterProfile] = "FragUI"
    end
end

function FragUI:ExportLSToasts()
    local LSToastsData = LS_TOASTS_GLOBAL_CONFIG["profiles"]["FragUI"]
    local SerializedData = Serialize:Serialize(LSToastsData)
    local CompressedData = Compress:CompressDeflate(SerializedData)
    local EncodedData = Compress:EncodeForPrint(CompressedData)
    StaticPopupDialogs["FRAGUI_EXPORT_LSTOASTS"] = {
        text = "LSToasts Data Exported. Copy the data below.",
        button1 = "OK",
        hasEditBox = true,
        maxLetters = 0,
        editBoxWidth = 400,
        OnShow = function(self)
            self.EditBox:SetText(EncodedData)
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("FRAGUI_EXPORT_LSTOASTS")
end

function FragUI:ImportLSToasts()
    if not C_AddOns.IsAddOnLoaded("ls_Toasts") then
        print("|cFF8080FFFrag|rUI: LS: Toasts isn't installed or loaded. Please ensure this is the case before importing.")
        return
    end
    local ImportString = FragUI:FetchLSToastsString()
    local DecodedData = Compress:DecodeForPrint(ImportString)
    local DecompressedData = Compress:DecompressDeflate(DecodedData)
    local _, LSToastsData = Serialize:Deserialize(DecompressedData)
    LS_TOASTS_GLOBAL_CONFIG.profiles = LS_TOASTS_GLOBAL_CONFIG.profiles or {}
    LS_TOASTS_GLOBAL_CONFIG.profileKeys = LS_TOASTS_GLOBAL_CONFIG.profileKeys or {}

    local CharacterProfile = UnitName("player") .. " - " .. GetRealmName()

    if LS_TOASTS_GLOBAL_CONFIG.profiles["FragUI"] then
        wipe(LS_TOASTS_GLOBAL_CONFIG.profiles["FragUI"])
        LS_TOASTS_GLOBAL_CONFIG.profiles["FragUI"] = LSToastsData
        LS_TOASTS_GLOBAL_CONFIG.profileKeys[CharacterProfile] = "FragUI"
    else
        LS_TOASTS_GLOBAL_CONFIG.profiles["FragUI"] = LSToastsData
        LS_TOASTS_GLOBAL_CONFIG.profileKeys[CharacterProfile] = "FragUI"
    end
end

function FragUI:PositionTipTac()
    if not FragUI.DB.global.DetailsBackdrops.AdjustTipTac then return end
    if not C_AddOns.IsAddOnLoaded("TipTac") then return end
    if _detalhes_global then
        if (_detalhes_global and _detalhes_global["always_use_profile"] and _detalhes_global["always_use_profile"] == true and _detalhes_global["always_use_profile_name"] ~= "FragUI") or (_detalhes_database and _detalhes_database["active_profile"] and _detalhes_database["active_profile"] ~= "FragUI") then
            return
        end
    end
    local DetailsFrameOne = _G["DetailsFrameOne"]
    local TipTac = _G["TipTac"]
    TipTac:ClearAllPoints()
    if FragUI.DB.global.DetailsBackdrops.DetailsLayout == "Horizontal" then
        TipTac:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "TOPRIGHT", 0, 1)
    else
        TipTac:SetPoint("BOTTOMRIGHT", DetailsFrameOne, "BOTTOMLEFT", -1, 0)
    end
end


local function MiscUpdates()
    if C_AddOns.IsAddOnLoaded("SimulationCraft") then
        if SimulationCraftDB and SimulationCraftDB["profiles"] then
            local charName, charRealm = UnitName("player"), GetRealmName()
            local profileKey = charName .. " - " .. charRealm
            if SimulationCraftDB["profiles"][profileKey] then
                if SimulationCraftDB["profiles"][profileKey]["minimap"]["hide"] == nil or SimulationCraftDB["profiles"][profileKey]["minimap"]["hide"] == false then
                    SimulationCraftDB["profiles"][profileKey]["minimap"]["hide"] = true
                end
            end
        end
    end
    -- Auto Populate "Delete Prompt" with "Delete"
    hooksecurefunc(StaticPopupDialogs["DELETE_GOOD_ITEM"], "OnShow", function(self) if self.EditBox then self.EditBox:SetText("DELETE") end end)
    -- Loss of Control Frame
    LossOfControlFrame.RedLineBottom:SetAlpha(0)
    LossOfControlFrame.RedLineTop:SetAlpha(0)
    LossOfControlFrame.blackBg:SetAlpha(0)
end

function FragUI:Setup()
    SkipAllCinematics()
    HideTalkingHeadFrame()
    CleanUpChat()
    StyleBlizzard()
    StyleCharacterPane()
    StyleItemLevelFrame()
    CreateDurabilityFrame()
    StyleActionStatusText()
    StyleUIErrorsFrame()
    StyleChatBubbleFont()
    StyleObjectiveTrackerFonts()
    DrawDetailsBackdrops()
    FragUI:PositionTipTac()
    MiscUpdates()
end