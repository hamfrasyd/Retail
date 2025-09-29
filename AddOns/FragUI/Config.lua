local _, FragUI = ...
local AG = LibStub("AceGUI-3.0")
local ConfigOpen = false
local isInDevMode = false
local LSM = LibStub:GetLibrary("LibSharedMedia-3.0") or LibStub("LibSharedMedia-3.0")
local ANCHORS = {
    ["TOPLEFT"] = "TOPLEFT",
    ["TOP"] = "TOP",
    ["TOPRIGHT"] = "TOPRIGHT",
    ["LEFT"] = "LEFT",
    ["CENTER"] = "CENTER",
    ["RIGHT"] = "RIGHT",
    ["BOTTOMLEFT"] = "BOTTOMLEFT",
    ["BOTTOM"] = "BOTTOM",
    ["BOTTOMRIGHT"] = "BOTTOMRIGHT",
}
local SLIDER_OFFSET_MAX, SLIDER_OFFSET_MIN = 1000, -1000
local SLIDER_HEIGHT_MAX, SLIDER_HEIGHT_MIN = 1000, -1000
local SLIDER_WIDTH_MAX, SLIDER_WIDTH_MIN = 1000, -1000
local SLIDER_FONT_MAX, SLIDER_FONT_MIN = 64, 8

local function GenerateTextureName(texturePath)
    for key, val in pairs(LSM:HashTable("statusbar")) do
        if val == texturePath then
            return key
        end
    end
    return nil
end

local function GenerateFontName(fontPath)
    for key, val in pairs(LSM:HashTable("font")) do
        if val == fontPath then
            return key
        end
    end
    return nil
end

local function CreateProfileButton(buttonText, profileName, parentAnchor)
    local ProfileButton = AG:Create("Button")
    ProfileButton:SetText(buttonText)
    ProfileButton:SetRelativeWidth(0.25)
    ProfileButton:SetCallback("OnClick", function()
        FragUI:RequestConfirmation("apply the |cFF8080FF" .. profileName .. "|r Profile", function()
            print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: Applying " .. profileName .. "|r Profile... Please be patient!")
            FragUI:ApplyProfiles(profileName)
        end)
    end)
    parentAnchor:AddChild(ProfileButton)
end

local function CheckImportedProfiles()
    local AddOnDBList = {
        ["Bufflehead"]     = {"BuffleheadDB", "FragUI"},
        ["Prat-3.0"]       = {"Prat3DB", "Default"},
        ["BasicMinimap"]   = {"BasicMinimapSV", "FragUI"},
        ["ls_Toasts"]      = {"LS_TOASTS_GLOBAL_CONFIG", "FragUI"},
    }

    local AddOnNameMap = {
        ["Bufflehead"]     = "Bufflehead",
        ["Prat-3.0"]       = "Prat",
        ["BasicMinimap"]   = "BasicMinimap",
        ["ls_Toasts"]      = "LS: Toasts",
    }

    local CrossTexture = "|A:Radial_Wheel_Icon_Close:16:16|a"
    local CheckTexture = "|A:perks-tick:16:16|a"

    local results = {}

    for addOnName, dbInfo in pairs(AddOnDBList) do
        local status = AddOnNameMap[addOnName] .. ": |cFFCCCCCC" .. dbInfo[2] .. "|r " .. CrossTexture
        if C_AddOns.IsAddOnLoaded(addOnName) then
            local db = _G[dbInfo[1]]
            if db and db.profileKeys then
                for _, profile in pairs(db.profileKeys) do
                    if profile == dbInfo[2] then
                        status = AddOnNameMap[addOnName] .. ": |cFFCCCCCC" .. dbInfo[2] .. "|r " .. CheckTexture
                        break
                    end
                end
            end
        end
        table.insert(results, status)
    end

    return table.concat(results, "\n")
end

FragUI.Defaults = {
    global = {
        General = {
            SkipCinematics = true,
            HideTalkingHead = true,
            CleanUpChat = true,
            StyleBlizzard = true,
            SkinMicroMenu = true,
        },
        CharacterPane = {
            StyleCharacterPane = true,
            StyleItemLevelFrame = true,
            ItemLevelDecimals = 1,
            ItemLevelFontSize = 15,
            ShowDurabilityFrame = true,
            DurabilityFrameAnchorFrom = "BOTTOMRIGHT",
            DurabilityFrameAnchorTo = "BOTTOMRIGHT",
            DurabilityFrameOffsetX = 40,
            DurabilityFrameOffsetY = -27,
            DurabilityFrameFontSize = 12,
        },
        BlizzardFonts = {
            StyleActionStatusText = true,
            ActionStatusTextAnchorFrom = "CENTER",
            ActionStatusTextAnchorTo = "CENTER",
            ActionStatusTextOffsetX = 0,
            ActionStatusTextOffsetY = 175,
            ActionStatusTextFontSize = 12,
            StyleUIErrorsFrame = true,
            HideUIErrorsFrame = false,
            UIErrorsFrameTextAnchorFrom = "CENTER",
            UIErrorsFrameTextAnchorTo = "CENTER",
            UIErrorsFrameTextOffsetX = 0,
            UIErrorsFrameTextOffsetY = 175,
            UIErrorsFrameTextFontSize = 12,
            StyleChatBubbleText = true,
            ChatBubbleTextFontSize = 8,
            StyleObjectiveTracker = true,
            ObjectiveTrackerLineFontSize = 12,
            ObjectiveTrackerHeaderFontSize = 15
        },
        DetailsBackdrops = {
            DetailsLayout = "Horizontal",
            AdjustTipTac = true,
            DetailsFrameOne = {
                Enabled = true,
                DetailsBackdropColor = { 26/255, 26/255, 26/255, 1 },
                DetailsBackdropBorderColor = { 0, 0, 0, 1 },
                Rows = 5,
                Width = 222,
                AnchorFrom = "BOTTOMRIGHT",
                AnchorTo = "BOTTOMRIGHT",
                OffsetX = -1,
                OffsetY = 1.1,
            },
            DetailsFrameTwo = {
                Enabled = true,
                DetailsBackdropColor = { 26/255, 26/255, 26/255, 1 },
                DetailsBackdropBorderColor = { 0, 0, 0, 1 },
                Rows = 5,
                Width = 222,
                AnchorFrom = "BOTTOMRIGHT",
                AnchorTo = "BOTTOMLEFT",
                OffsetX = -1,
                OffsetY = 0.1,
            }
        },
    }
}

local GUIContainer;

local function ColourTextIfImported(addOnName, text, profileName)
    local AddOnDBMap = {
        ["Bufflehead"]     = "BuffleheadDB",
        ["Prat-3.0"]       = "Prat3DB",
        ["BasicMinimap"]   = "BasicMinimapSV",
        ["ls_Toasts"]      = "LS_TOASTS_GLOBAL_CONFIG",
    }

    local dbName = AddOnDBMap[addOnName]
    if not dbName then return "|cFFFF4040" .. text .. "|r" end

    if C_AddOns.IsAddOnLoaded(addOnName) then
        local db = _G[dbName]
        if db and db.profileKeys then
            for _, profile in pairs(db.profileKeys) do
                if profile == profileName then
                    return "|cFF40FF40" .. text .. "|r"
                end
            end
        end
    end

    return "|cFFFF4040" .. text .. "|r"
end

local function OpenURL(url, addOnName)
    if not url or url == "" then return end
    StaticPopupDialogs["FragUI_OpenURL"] = {
        text = "|cFF8080FF" .. addOnName .. "|r URL",
        button1 = "Okay",
        OnAccept = function() end,
        hasEditBox = true,
        maxLetters = 255,
        editBoxWidth = 300,
        OnShow = function(self)
            self.EditBox:SetText(url)
            self.EditBox:SetFocus()
            self.EditBox:HighlightText()
        end,
        timeout = 0,
        whileDead = true,
    }
    StaticPopup_Show("FragUI_OpenURL")
end

local function CreateCreditSection(GuiContainer, addOnTitle, addOnAuthor, addOnURL, addOnDescription)
    local AddOnLabel = AG:Create("InteractiveLabel")
    if addOnAuthor ~= nil then addOnAuthor = " - " .. addOnAuthor else addOnAuthor = "" end
    if addOnTitle == nil then addOnTitle = "" end
    if addOnURL == nil then
        AddOnLabel:SetText("|cFF8080FF" .. addOnTitle .. "|r" .. addOnAuthor)
    else
        AddOnLabel:SetText("|TInterface/AddOns/FragUI/Media/Link.png:14:14|t|cFF8080FF" .. addOnTitle .. "|r" .. addOnAuthor)
    end
    AddOnLabel:SetRelativeWidth(1)
    AddOnLabel:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    AddOnLabel:SetJustifyH("LEFT")
    AddOnLabel:SetJustifyV("MIDDLE")
    AddOnLabel:SetCallback("OnClick", function() OpenURL(addOnURL, addOnTitle) end)
    AddOnLabel:SetCallback("OnEnter", function() if addOnURL == nil then return end AddOnLabel:SetText("|TInterface/AddOns/FragUI/Media/Link_Hover.png:14:14|t|cFFCCCCCC" .. addOnTitle .. "|r" .. addOnAuthor) end)
    AddOnLabel:SetCallback("OnLeave", function() if addOnURL == nil then return end AddOnLabel:SetText("|TInterface/AddOns/FragUI/Media/Link.png:14:14|t|cFF8080FF" .. addOnTitle .. "|r" .. addOnAuthor) end)
    GuiContainer:AddChild(AddOnLabel)

    local AddOnDescription = AG:Create("Label")
    AddOnDescription:SetText(addOnDescription)
    AddOnDescription:SetRelativeWidth(1)
    AddOnDescription:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    AddOnDescription:SetJustifyH("LEFT")
    AddOnDescription:SetJustifyV("MIDDLE")
    GuiContainer:AddChild(AddOnDescription)

    local Spacer = AG:Create("Label")
    Spacer:SetText("")
    Spacer:SetRelativeWidth(1)
    Spacer:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    Spacer:SetJustifyH("LEFT")
    Spacer:SetJustifyV("MIDDLE")
    GuiContainer:AddChild(Spacer)
end

function FragUI:ReOpenGUI()
    if ConfigOpen and GUIContainer then
        GUIContainer:ReleaseChildren()
        GUIContainer:Hide()
        FragUI:CreateGUI("DetailsBackdrops")
    end
end

function FragUI:CreateGUI(tabToOpen)
    if ConfigOpen then return end
    if InCombatLockdown() then return end
    ConfigOpen = true

    GUIContainer = AG:Create("Frame")
    GUIContainer:SetTitle("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t FragUI |TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t")
    GUIContainer:SetStatusText("Developed by |cFF8080FFUnhalted|r | |TInterface/AddOns/FragUI/Media/Twitch.png:14:13|t/Fragnance")
    GUIContainer:SetLayout("Fill")
    GUIContainer:SetWidth(600)
    GUIContainer:SetHeight(680)
    GUIContainer:EnableResize(false)
    GUIContainer:SetCallback("OnClose", function(widget) AG:Release(widget) isInDevMode = false ConfigOpen = false  end)

    local function DrawGeneralContainer(GUIContainer)
        local WipeActionBarsButton = AG:Create("Button")
        WipeActionBarsButton:SetText("Wipe Action Bars")
        WipeActionBarsButton:SetRelativeWidth(1)
        WipeActionBarsButton:SetCallback("OnClick", function() FragUI:RequestConfirmation("wipe your action bars", function() for i = 1,120 do PickupAction(i) PutItemInBackpack() ClearCursor() end end) end)
        WipeActionBarsButton:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will wipe all action bars, removing all spells & items from them.") end)
        WipeActionBarsButton:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        GUIContainer:AddChild(WipeActionBarsButton)

        local KeybindOptionsContainer = AG:Create("InlineGroup")
        KeybindOptionsContainer:SetTitle("Keybinds")
        KeybindOptionsContainer:SetLayout("Flow")
        KeybindOptionsContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(KeybindOptionsContainer)

        local KeybindDescription = AG:Create("Label")
        KeybindDescription:SetText("Several keybinds have been added to |TInterface/AddOns/FragUI/Media/FragUI.png:12:12|tFragUI for |cFF8080FFQuality of Life|r.\nYou can access them via the Keybindings Options in Blizzard Options.\n|cFF8080FFKeybinds|r:\n• Toggle Action Bars.\n• Leave Party.\n• Reset Instances.")
        KeybindDescription:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        KeybindDescription:SetRelativeWidth(1)
        KeybindOptionsContainer:AddChild(KeybindDescription)

        local ToggleContainer = AG:Create("InlineGroup")
        ToggleContainer:SetTitle("General Settings")
        ToggleContainer:SetLayout("List")
        ToggleContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(ToggleContainer)

        local SkipCinematicsCheckbox = AG:Create("CheckBox")
        SkipCinematicsCheckbox:SetLabel("Skip Cinematics")
        SkipCinematicsCheckbox:SetValue(FragUI.DB.global.General.SkipCinematics)
        SkipCinematicsCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.General.SkipCinematics then FragUI.DB.global.General.SkipCinematics = value FragUI:RequestReload() end end)
        SkipCinematicsCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will skip all cinematics in the game, instantly.") end)
        SkipCinematicsCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        ToggleContainer:AddChild(SkipCinematicsCheckbox)

        local HideTalkingHeadCheckbox = AG:Create("CheckBox")
        HideTalkingHeadCheckbox:SetLabel("Hide Talking Head Frame")
        HideTalkingHeadCheckbox:SetValue(FragUI.DB.global.General.HideTalkingHead)
        HideTalkingHeadCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.General.HideTalkingHead then FragUI.DB.global.General.HideTalkingHead = value FragUI:RequestReload() end end)
        ToggleContainer:AddChild(HideTalkingHeadCheckbox)

        local CleanUpChatCheckbox = AG:Create("CheckBox")
        CleanUpChatCheckbox:SetLabel("Clean Up Chat")
        CleanUpChatCheckbox:SetValue(FragUI.DB.global.General.CleanUpChat)
        CleanUpChatCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.General.CleanUpChat then FragUI.DB.global.General.CleanUpChat = value FragUI:RequestReload() end end)
        CleanUpChatCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will do the following:\n- Hide All Scroll Bars.\n- Remove Font Shadows.\n- Increases Chat Edit Box Height.\n- Forces Chat Edit Box to Bottom Left of Chat Window.") end)
        CleanUpChatCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        ToggleContainer:AddChild(CleanUpChatCheckbox)

        local StyleBlizzardCheckbox = AG:Create("CheckBox")
        StyleBlizzardCheckbox:SetLabel("Style Blizzard UI")
        StyleBlizzardCheckbox:SetValue(FragUI.DB.global.General.StyleBlizzard)
        StyleBlizzardCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.General.StyleBlizzard then FragUI.DB.global.General.StyleBlizzard = value FragUI:RequestReload() end end)
        StyleBlizzardCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will do the following:\n- Hide Zone Text.\n- Hide Sub Zone Text.\n- Hide Textures from Objective Tracker.") end)
        StyleBlizzardCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        ToggleContainer:AddChild(StyleBlizzardCheckbox)

        local SkinMicroMenuCheckbox = AG:Create("CheckBox")
        SkinMicroMenuCheckbox:SetLabel("Skin Micro Menu")
        SkinMicroMenuCheckbox:SetValue(FragUI.DB.global.General.SkinMicroMenu)
        SkinMicroMenuCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.General.SkinMicroMenu then FragUI.DB.global.General.SkinMicroMenu = value FragUI:RequestReload() end end)
        SkinMicroMenuCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Change the appearance of the Micro Menu buttons.") end)
        SkinMicroMenuCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        ToggleContainer:AddChild(SkinMicroMenuCheckbox)

        local ProfileContainer = AG:Create("InlineGroup")
        ProfileContainer:SetTitle("Profile Settings")
        ProfileContainer:SetLayout("List")
        ProfileContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(ProfileContainer)

        local ProfileSwitcherContainer = AG:Create("InlineGroup")
        ProfileSwitcherContainer:SetTitle("Profile Switcher")
        ProfileSwitcherContainer:SetLayout("Flow")
        ProfileSwitcherContainer:SetRelativeWidth(1)

        CreateProfileButton("|A:Adventures-Tank:14:14|a|A:Adventures-DPS:14:14|a Colour", "FragUI - Colour", ProfileSwitcherContainer)
        CreateProfileButton("|A:Adventures-Tank:14:14|a|A:Adventures-DPS:14:14|a Dark", "FragUI - Dark", ProfileSwitcherContainer)
        CreateProfileButton("|A:Adventures-Healer:14:14|a Colour", "FragUI - Colour - Healer", ProfileSwitcherContainer)
        CreateProfileButton("|A:Adventures-Healer:14:14|a Dark", "FragUI - Dark - Healer", ProfileSwitcherContainer)

        local AddOnProfilesHeader = AG:Create("Heading")
        AddOnProfilesHeader:SetText("AddOn Profiles")
        AddOnProfilesHeader:SetRelativeWidth(1)
        ProfileSwitcherContainer:AddChild(AddOnProfilesHeader)

        local AddOnProfilesList = AG:Create("Label")
        AddOnProfilesList:SetText(FragUI:GetAddOnProfilesList())
        AddOnProfilesList:SetRelativeWidth(1)
        AddOnProfilesList:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        ProfileSwitcherContainer:AddChild(AddOnProfilesList)
        ProfileContainer:AddChild(ProfileSwitcherContainer)

        local AdditionalProfilesContainer = AG:Create("InlineGroup")
        AdditionalProfilesContainer:SetTitle("Additional Profiles")
        AdditionalProfilesContainer:SetLayout("Flow")
        AdditionalProfilesContainer:SetRelativeWidth(1)
        ProfileContainer:AddChild(AdditionalProfilesContainer)

        local ImportBuffleheadButton = AG:Create("Button")
        ImportBuffleheadButton:SetText(ColourTextIfImported("Bufflehead", "Bufflehead", "FragUI"))
        ImportBuffleheadButton:SetRelativeWidth(0.33)
        ImportBuffleheadButton:SetCallback("OnClick", function() if not C_AddOns.IsAddOnLoaded("Bufflehead") then return end FragUI:ImportBufflehead() FragUI:RequestReload() end)
        AdditionalProfilesContainer:AddChild(ImportBuffleheadButton)

        local ImportPrat3Button = AG:Create("Button")
        ImportPrat3Button:SetText(ColourTextIfImported("Prat-3.0", "Prat", "Default"))
        ImportPrat3Button:SetRelativeWidth(0.33)
        ImportPrat3Button:SetCallback("OnClick", function() if not C_AddOns.IsAddOnLoaded("Prat-3.0") then return end FragUI:ImportPrat() FragUI:RequestReload() end)
        AdditionalProfilesContainer:AddChild(ImportPrat3Button)

        local ImportBasicMinimapButton = AG:Create("Button")
        ImportBasicMinimapButton:SetText(ColourTextIfImported("BasicMinimap", "BasicMinimap", "FragUI"))
        ImportBasicMinimapButton:SetRelativeWidth(0.33)
        ImportBasicMinimapButton:SetCallback("OnClick", function() if not C_AddOns.IsAddOnLoaded("BasicMinimap") then return end FragUI:ImportBasicMinimap() FragUI:RequestReload() end)
        AdditionalProfilesContainer:AddChild(ImportBasicMinimapButton)

        local ImportLSToastsButton = AG:Create("Button")
        ImportLSToastsButton:SetText(ColourTextIfImported("ls_Toasts", "LS: Toasts", "FragUI"))
        ImportLSToastsButton:SetRelativeWidth(0.5)
        ImportLSToastsButton:SetCallback("OnClick", function() if not C_AddOns.IsAddOnLoaded("ls_Toasts") then return end FragUI:ImportLSToasts() FragUI:RequestReload() end)
        AdditionalProfilesContainer:AddChild(ImportLSToastsButton)

        local ImportMRTButton = AG:Create("Button")
        ImportMRTButton:SetText("MRT Import String")
        ImportMRTButton:SetRelativeWidth(0.5)
        ImportMRTButton:SetCallback("OnClick", function()
            StaticPopupDialogs["FragUI_CreateMRTString"] = {
                text = "|cFF8080FFMRT|r Import String",
                button1 = "Okay",
                OnAccept = function() end,
                hasEditBox = true,
                editBoxWidth = 300,
                OnShow = function(self)
                    self.EditBox:SetText(FragUI:FetchMRTString())
                    self.EditBox:SetFocus()
                    self.EditBox:HighlightText()
                end,
                timeout = 0,
                whileDead = true,
            }
            StaticPopup_Show("FragUI_CreateMRTString")
        end)
        ImportMRTButton:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will provide the string for importing into |cFF8080FFMRT|r.\nOpen MRT > Profiles > Import & Paste This String.") end)
        ImportMRTButton:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        AdditionalProfilesContainer:AddChild(ImportMRTButton)

        local ImportAllProfilesButton = AG:Create("Button")
        ImportAllProfilesButton:SetText("Import Profiles")
        ImportAllProfilesButton:SetRelativeWidth(1)
        ImportAllProfilesButton:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText(CheckImportedProfiles()) end)
        ImportAllProfilesButton:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        ImportAllProfilesButton:SetCallback("OnClick", function()
            print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: Importing All Profiles... Please be patient!")
            C_Timer.After(1, function()
                if not C_AddOns.IsAddOnLoaded("Bufflehead") then print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Bufflehead not installed, skipping...") return end
                print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Importing Bufflehead Profile...")
                FragUI:ImportBufflehead()
            end)
            C_Timer.After(2, function()
                if not C_AddOns.IsAddOnLoaded("Prat-3.0") then print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Prat-3.0 not installed, skipping...") return end
                print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Importing Prat Profile...")
                FragUI:ImportPrat()
            end)
            C_Timer.After(3, function()
                if not C_AddOns.IsAddOnLoaded("BasicMinimap") then print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t BasicMinimap not installed, skipping...") return end
                print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Importing BasicMinimap Profile...")
                FragUI:ImportBasicMinimap()
            end)
            C_Timer.After(4, function()
                if not C_AddOns.IsAddOnLoaded("ls_Toasts") then print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t LS: Toasts not installed, skipping...") return end
                print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t Importing LS: Toasts Profile...")
                FragUI:ImportLSToasts()
            end)
            C_Timer.After(5, function()
                if not C_AddOns.IsAddOnLoaded("Bufflehead") and not C_AddOns.IsAddOnLoaded("Prat-3.0") and not C_AddOns.IsAddOnLoaded("BasicMinimap") then print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: All Additional AddOns are missing, please install / load them & try again!") return end
                print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: All Profiles Imported Successfully!")
                FragUI:RequestReload()
            end)
        end)
        AdditionalProfilesContainer:AddChild(ImportAllProfilesButton)

        if isInDevMode then
            local ExportButtonContainer = AG:Create("InlineGroup")
            ExportButtonContainer:SetTitle("Export Profiles")
            ExportButtonContainer:SetLayout("Flow")
            ExportButtonContainer:SetRelativeWidth(1)
            ProfileContainer:AddChild(ExportButtonContainer)

            local ExportBuffleheadButton = AG:Create("Button")
            ExportBuffleheadButton:SetText("Export Bufflehead Profile")
            ExportBuffleheadButton:SetRelativeWidth(0.5)
            ExportBuffleheadButton:SetCallback("OnClick", function() FragUI:ExportBufflehead() end)
            ExportButtonContainer:AddChild(ExportBuffleheadButton)

            local ExportPrat3Button = AG:Create("Button")
            ExportPrat3Button:SetText("Export Prat3 Profile")
            ExportPrat3Button:SetRelativeWidth(0.5)
            ExportPrat3Button:SetCallback("OnClick", function() FragUI:ExportPrat() end)
            ExportButtonContainer:AddChild(ExportPrat3Button)

            local ExportBasicMinimapButton = AG:Create("Button")
            ExportBasicMinimapButton:SetText("Export Basic Minimap Profile")
            ExportBasicMinimapButton:SetRelativeWidth(0.5)
            ExportBasicMinimapButton:SetCallback("OnClick", function() FragUI:ExportBasicMinimap() end)
            ExportButtonContainer:AddChild(ExportBasicMinimapButton)

            local ExportLSToastsButton = AG:Create("Button")
            ExportLSToastsButton:SetText("Export LS: Toasts Profile")
            ExportLSToastsButton:SetRelativeWidth(0.5)
            ExportLSToastsButton:SetCallback("OnClick", function() FragUI:ExportLSToasts() end)
            ExportButtonContainer:AddChild(ExportLSToastsButton)
        end
    end

    local function DrawCharacterPaneContainer(GUIContainer)
        -- Style Character Pane
        local StyleCharacterPaneCheckbox = AG:Create("CheckBox")
        StyleCharacterPaneCheckbox:SetLabel("Style Character Pane")
        StyleCharacterPaneCheckbox:SetValue(FragUI.DB.global.CharacterPane.StyleCharacterPane)
        StyleCharacterPaneCheckbox:SetRelativeWidth(1)
        StyleCharacterPaneCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.CharacterPane.StyleCharacterPane then FragUI.DB.global.CharacterPane.StyleCharacterPane = value FragUI:RequestReload() end end)
        StyleCharacterPaneCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Adjusts the Character Pane with Class Coloured & Outlined Fonts.") end)
        StyleCharacterPaneCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        GUIContainer:AddChild(StyleCharacterPaneCheckbox)

        -- Item Level Frame Settings
        local ItemLevelFrameContainer = AG:Create("InlineGroup")
        ItemLevelFrameContainer:SetTitle("Item Level Frame")
        ItemLevelFrameContainer:SetLayout("Flow")
        ItemLevelFrameContainer:SetRelativeWidth(1)
        local StyleItemLevelFrameCheckbox = AG:Create("CheckBox")
        StyleItemLevelFrameCheckbox:SetLabel("Style Item Level Frame")
        StyleItemLevelFrameCheckbox:SetValue(FragUI.DB.global.CharacterPane.StyleItemLevelFrame)
        StyleItemLevelFrameCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.CharacterPane.StyleItemLevelFrame then FragUI.DB.global.CharacterPane.StyleItemLevelFrame = value FragUI:RequestReload() end FragUI:UpdateItemLevelFrame() end)
        StyleItemLevelFrameCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Replaces Default Item Level Text with a more detailed version.") end)
        StyleItemLevelFrameCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        StyleItemLevelFrameCheckbox:SetRelativeWidth(0.5)
        ItemLevelFrameContainer:AddChild(StyleItemLevelFrameCheckbox)
        local ItemLevelDecimalsSlider = AG:Create("Slider")
        ItemLevelDecimalsSlider:SetLabel("Item Level Decimals")
        ItemLevelDecimalsSlider:SetValue(FragUI.DB.global.CharacterPane.ItemLevelDecimals)
        ItemLevelDecimalsSlider:SetSliderValues(0, 3, 1)
        ItemLevelDecimalsSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.ItemLevelDecimals = value FragUI:UpdateItemLevelFrame() end)
        ItemLevelDecimalsSlider:SetRelativeWidth(0.5)
        ItemLevelFrameContainer:AddChild(ItemLevelDecimalsSlider)
        GUIContainer:AddChild(ItemLevelFrameContainer)

        -- Durability Frame Settings
        local DurabilityFrameContainer = AG:Create("InlineGroup")
        DurabilityFrameContainer:SetTitle("Durability Frame")
        DurabilityFrameContainer:SetLayout("Flow")
        DurabilityFrameContainer:SetRelativeWidth(1)
        local AddDurabilityFrameCheckbox = AG:Create("CheckBox")
        AddDurabilityFrameCheckbox:SetLabel("Show Durability Frame")
        AddDurabilityFrameCheckbox:SetValue(FragUI.DB.global.CharacterPane.ShowDurabilityFrame)
        AddDurabilityFrameCheckbox:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.ShowDurabilityFrame = value FragUI:UpdateDurabilityFrame() end)
        AddDurabilityFrameCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Adds a durability text to the Character Pane.") end)
        AddDurabilityFrameCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        AddDurabilityFrameCheckbox:SetRelativeWidth(1)
        DurabilityFrameContainer:AddChild(AddDurabilityFrameCheckbox)
        local DurabilityFrameAnchorFromDropdown = AG:Create("Dropdown")
        DurabilityFrameAnchorFromDropdown:SetLabel("Anchor From")
        DurabilityFrameAnchorFromDropdown:SetList(ANCHORS)
        DurabilityFrameAnchorFromDropdown:SetValue(FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom)
        DurabilityFrameAnchorFromDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.DurabilityFrameAnchorFrom = value FragUI:UpdateDurabilityFrame() end)
        DurabilityFrameAnchorFromDropdown:SetRelativeWidth(0.5)
        DurabilityFrameContainer:AddChild(DurabilityFrameAnchorFromDropdown)
        local DurabilityFrameAnchorToDropdown = AG:Create("Dropdown")
        DurabilityFrameAnchorToDropdown:SetLabel("Anchor To")
        DurabilityFrameAnchorToDropdown:SetList(ANCHORS)
        DurabilityFrameAnchorToDropdown:SetValue(FragUI.DB.global.CharacterPane.DurabilityFrameAnchorTo)
        DurabilityFrameAnchorToDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.DurabilityFrameAnchorTo = value FragUI:UpdateDurabilityFrame() end)
        DurabilityFrameAnchorToDropdown:SetRelativeWidth(0.5)
        DurabilityFrameContainer:AddChild(DurabilityFrameAnchorToDropdown)
        local DurabilityFrameOffsetXSlider = AG:Create("Slider")
        DurabilityFrameOffsetXSlider:SetLabel("Offset X")
        DurabilityFrameOffsetXSlider:SetValue(FragUI.DB.global.CharacterPane.DurabilityFrameOffsetX)
        DurabilityFrameOffsetXSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DurabilityFrameOffsetXSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.DurabilityFrameOffsetX = value FragUI:UpdateDurabilityFrame() end)
        DurabilityFrameOffsetXSlider:SetRelativeWidth(0.33)
        DurabilityFrameContainer:AddChild(DurabilityFrameOffsetXSlider)
        local DurabilityFrameOffsetYSlider = AG:Create("Slider")
        DurabilityFrameOffsetYSlider:SetLabel("Offset Y")
        DurabilityFrameOffsetYSlider:SetValue(FragUI.DB.global.CharacterPane.DurabilityFrameOffsetY)
        DurabilityFrameOffsetYSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DurabilityFrameOffsetYSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.DurabilityFrameOffsetY = value FragUI:UpdateDurabilityFrame() end)
        DurabilityFrameOffsetYSlider:SetRelativeWidth(0.33)
        DurabilityFrameContainer:AddChild(DurabilityFrameOffsetYSlider)
        local DurabilityFrameFontSizeSlider = AG:Create("Slider")
        DurabilityFrameFontSizeSlider:SetLabel("Font Size")
        DurabilityFrameFontSizeSlider:SetValue(FragUI.DB.global.CharacterPane.DurabilityFrameFontSize)
        DurabilityFrameFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, SLIDER_FONT_MAX, 1)
        DurabilityFrameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.CharacterPane.DurabilityFrameFontSize = value FragUI:UpdateDurabilityFrame() end)
        DurabilityFrameFontSizeSlider:SetRelativeWidth(0.33)
        DurabilityFrameContainer:AddChild(DurabilityFrameFontSizeSlider)
        GUIContainer:AddChild(DurabilityFrameContainer)
    end

    local function DrawBlizzardFontsContainer(GUIContainer)
        local ActionStatusTextContainer = AG:Create("InlineGroup")
        ActionStatusTextContainer:SetTitle("Action Status Text")
        ActionStatusTextContainer:SetLayout("Flow")
        ActionStatusTextContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(ActionStatusTextContainer)

        local StyleActionStatusTextCheckbox = AG:Create("CheckBox")
        StyleActionStatusTextCheckbox:SetLabel("Style Action Status Text")
        StyleActionStatusTextCheckbox:SetValue(FragUI.DB.global.BlizzardFonts.StyleActionStatusText)
        StyleActionStatusTextCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.BlizzardFonts.StyleActionStatusText then FragUI.DB.global.BlizzardFonts.StyleActionStatusText = value FragUI:RequestReload() end end)
        StyleActionStatusTextCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Adjusts Action Status Text to be better positioned & aesthetic.\nThis text usually display system messages, such as `|cFFFFFFFFSound Effects Enabled|r` or `|cFFFFFFFFMusic Enabled|r`.") end)
        StyleActionStatusTextCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        StyleActionStatusTextCheckbox:SetRelativeWidth(1)
        ActionStatusTextContainer:AddChild(StyleActionStatusTextCheckbox)
        local ActionStatusTextAnchorFromDropdown = AG:Create("Dropdown")
        ActionStatusTextAnchorFromDropdown:SetLabel("Anchor From")
        ActionStatusTextAnchorFromDropdown:SetList(ANCHORS)
        ActionStatusTextAnchorFromDropdown:SetValue(FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorFrom)
        ActionStatusTextAnchorFromDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorFrom = value FragUI:UpdateActionStatusText() end)
        ActionStatusTextAnchorFromDropdown:SetRelativeWidth(0.5)
        ActionStatusTextContainer:AddChild(ActionStatusTextAnchorFromDropdown)
        local ActionStatusTextAnchorToDropdown = AG:Create("Dropdown")
        ActionStatusTextAnchorToDropdown:SetLabel("Anchor To")
        ActionStatusTextAnchorToDropdown:SetList(ANCHORS)
        ActionStatusTextAnchorToDropdown:SetValue(FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorTo)
        ActionStatusTextAnchorToDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ActionStatusTextAnchorTo = value FragUI:UpdateActionStatusText() end)
        ActionStatusTextAnchorToDropdown:SetRelativeWidth(0.5)
        ActionStatusTextContainer:AddChild(ActionStatusTextAnchorToDropdown)
        local ActionStatusTextOffsetXSlider = AG:Create("Slider")
        ActionStatusTextOffsetXSlider:SetLabel("Offset X")
        ActionStatusTextOffsetXSlider:SetValue(FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetX)
        ActionStatusTextOffsetXSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        ActionStatusTextOffsetXSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetX = value FragUI:UpdateActionStatusText() end)
        ActionStatusTextOffsetXSlider:SetRelativeWidth(0.33)
        ActionStatusTextContainer:AddChild(ActionStatusTextOffsetXSlider)
        local ActionStatusTextOffsetYSlider = AG:Create("Slider")
        ActionStatusTextOffsetYSlider:SetLabel("Offset Y")
        ActionStatusTextOffsetYSlider:SetValue(FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetY)
        ActionStatusTextOffsetYSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        ActionStatusTextOffsetYSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ActionStatusTextOffsetY = value FragUI:UpdateActionStatusText() end)
        ActionStatusTextOffsetYSlider:SetRelativeWidth(0.33)
        ActionStatusTextContainer:AddChild(ActionStatusTextOffsetYSlider)
        local ActionStatusTextFontSizeSlider = AG:Create("Slider")
        ActionStatusTextFontSizeSlider:SetLabel("Font Size")
        ActionStatusTextFontSizeSlider:SetValue(FragUI.DB.global.BlizzardFonts.ActionStatusTextFontSize)
        ActionStatusTextFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, SLIDER_FONT_MAX, 1)
        ActionStatusTextFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ActionStatusTextFontSize = value FragUI:UpdateActionStatusText() end)
        ActionStatusTextFontSizeSlider:SetRelativeWidth(0.33)
        ActionStatusTextContainer:AddChild(ActionStatusTextFontSizeSlider)

        local UIErrorsTextContainer = AG:Create("InlineGroup")
        UIErrorsTextContainer:SetTitle("UI Errors Text")
        UIErrorsTextContainer:SetLayout("Flow")
        UIErrorsTextContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(UIErrorsTextContainer)
        local StyleUIErrorsFrameCheckbox = AG:Create("CheckBox")
        StyleUIErrorsFrameCheckbox:SetLabel("Style UI Errors Frame")
        StyleUIErrorsFrameCheckbox:SetValue(FragUI.DB.global.BlizzardFonts.StyleUIErrorsFrame)
        StyleUIErrorsFrameCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.BlizzardFonts.StyleUIErrorsFrame then FragUI.DB.global.BlizzardFonts.StyleUIErrorsFrame = value FragUI:RequestReload() end end)
        StyleUIErrorsFrameCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("Adjusts UI Errors Frame to be better positioned & aesthetic.\nThis text usually display system messages, such as `|cFFFFFFFFYou can't do that yet.|r` or `|cFFFFFFFFYou have no target.|r`") end)
        StyleUIErrorsFrameCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        StyleUIErrorsFrameCheckbox:SetRelativeWidth(0.5)
        UIErrorsTextContainer:AddChild(StyleUIErrorsFrameCheckbox)
        local HideUIErrorsFrameCheckbox = AG:Create("CheckBox")
        HideUIErrorsFrameCheckbox:SetLabel("Hide UI Errors Frame")
        HideUIErrorsFrameCheckbox:SetValue(FragUI.DB.global.BlizzardFonts.HideUIErrorsFrame)
        HideUIErrorsFrameCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.BlizzardFonts.HideUIErrorsFrame then FragUI.DB.global.BlizzardFonts.HideUIErrorsFrame = value FragUI:RequestReload() end end)
        HideUIErrorsFrameCheckbox:SetRelativeWidth(0.5)
        UIErrorsTextContainer:AddChild(HideUIErrorsFrameCheckbox)
        local UIErrorsFrameTextAnchorFromDropdown = AG:Create("Dropdown")
        UIErrorsFrameTextAnchorFromDropdown:SetLabel("Anchor From")
        UIErrorsFrameTextAnchorFromDropdown:SetList(ANCHORS)
        UIErrorsFrameTextAnchorFromDropdown:SetValue(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorFrom)
        UIErrorsFrameTextAnchorFromDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorFrom = value FragUI:UpdateUIErrorsFrame() end)
        UIErrorsFrameTextAnchorFromDropdown:SetRelativeWidth(0.5)
        UIErrorsTextContainer:AddChild(UIErrorsFrameTextAnchorFromDropdown)
        local UIErrorsFrameTextAnchorToDropdown = AG:Create("Dropdown")
        UIErrorsFrameTextAnchorToDropdown:SetLabel("Anchor To")
        UIErrorsFrameTextAnchorToDropdown:SetList(ANCHORS)
        UIErrorsFrameTextAnchorToDropdown:SetValue(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorTo)
        UIErrorsFrameTextAnchorToDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextAnchorTo = value FragUI:UpdateUIErrorsFrame() end)
        UIErrorsFrameTextAnchorToDropdown:SetRelativeWidth(0.5)
        UIErrorsTextContainer:AddChild(UIErrorsFrameTextAnchorToDropdown)
        local UIErrorsFrameTextOffsetXSlider = AG:Create("Slider")
        UIErrorsFrameTextOffsetXSlider:SetLabel("Offset X")
        UIErrorsFrameTextOffsetXSlider:SetValue(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetX)
        UIErrorsFrameTextOffsetXSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        UIErrorsFrameTextOffsetXSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetX = value FragUI:UpdateUIErrorsFrame() end)
        UIErrorsFrameTextOffsetXSlider:SetRelativeWidth(0.33)
        UIErrorsTextContainer:AddChild(UIErrorsFrameTextOffsetXSlider)
        local UIErrorsFrameTextOffsetYSlider = AG:Create("Slider")
        UIErrorsFrameTextOffsetYSlider:SetLabel("Offset Y")
        UIErrorsFrameTextOffsetYSlider:SetValue(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetY)
        UIErrorsFrameTextOffsetYSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        UIErrorsFrameTextOffsetYSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextOffsetY = value FragUI:UpdateUIErrorsFrame() end)
        UIErrorsFrameTextOffsetYSlider:SetRelativeWidth(0.33)
        UIErrorsTextContainer:AddChild(UIErrorsFrameTextOffsetYSlider)
        local UIErrorsFrameTextFontSizeSlider = AG:Create("Slider")
        UIErrorsFrameTextFontSizeSlider:SetLabel("Font Size")
        UIErrorsFrameTextFontSizeSlider:SetValue(FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextFontSize)
        UIErrorsFrameTextFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, SLIDER_FONT_MAX, 1)
        UIErrorsFrameTextFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.UIErrorsFrameTextFontSize = value FragUI:UpdateUIErrorsFrame() end)
        UIErrorsFrameTextFontSizeSlider:SetRelativeWidth(0.33)
        UIErrorsTextContainer:AddChild(UIErrorsFrameTextFontSizeSlider)

        if UIErrorsTextContainer then
            if FragUI.DB.global.BlizzardFonts.HideUIErrorsFrame then
                StyleUIErrorsFrameCheckbox:SetDisabled(true)
                UIErrorsFrameTextAnchorFromDropdown:SetDisabled(true)
                UIErrorsFrameTextAnchorToDropdown:SetDisabled(true)
                UIErrorsFrameTextOffsetXSlider:SetDisabled(true)
                UIErrorsFrameTextOffsetYSlider:SetDisabled(true)
                UIErrorsFrameTextFontSizeSlider:SetDisabled(true)
            else
                StyleUIErrorsFrameCheckbox:SetDisabled(false)
                UIErrorsFrameTextAnchorFromDropdown:SetDisabled(false)
                UIErrorsFrameTextAnchorToDropdown:SetDisabled(false)
                UIErrorsFrameTextOffsetXSlider:SetDisabled(false)
                UIErrorsFrameTextOffsetYSlider:SetDisabled(false)
                UIErrorsFrameTextFontSizeSlider:SetDisabled(false)
            end
        end

        local ChatBubbleTextContainer = AG:Create("InlineGroup")
        ChatBubbleTextContainer:SetTitle("Chat Bubble Text")
        ChatBubbleTextContainer:SetLayout("Flow")
        ChatBubbleTextContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(ChatBubbleTextContainer)
        local StyleChatBubbleTextCheckbox = AG:Create("CheckBox")
        StyleChatBubbleTextCheckbox:SetLabel("Style Chat Bubble Text")
        StyleChatBubbleTextCheckbox:SetValue(FragUI.DB.global.BlizzardFonts.StyleChatBubbleText)
        StyleChatBubbleTextCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.BlizzardFonts.StyleChatBubbleText then FragUI.DB.global.BlizzardFonts.StyleChatBubbleText = value FragUI:RequestReload() end end)
        StyleChatBubbleTextCheckbox:SetRelativeWidth(1)
        ChatBubbleTextContainer:AddChild(StyleChatBubbleTextCheckbox)
        local ChatBubbleTextFontSizeSlider = AG:Create("Slider")
        ChatBubbleTextFontSizeSlider:SetLabel("Font Size")
        ChatBubbleTextFontSizeSlider:SetValue(FragUI.DB.global.BlizzardFonts.ChatBubbleTextFontSize)
        ChatBubbleTextFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, 12, 1)
        ChatBubbleTextFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ChatBubbleTextFontSize = value FragUI:UpdateChatBubbleFont() end)
        ChatBubbleTextFontSizeSlider:SetRelativeWidth(1)
        ChatBubbleTextContainer:AddChild(ChatBubbleTextFontSizeSlider)

        local QuestLogFontsContainer = AG:Create("InlineGroup")
        QuestLogFontsContainer:SetTitle("Quest Log Fonts")
        QuestLogFontsContainer:SetLayout("Flow")
        QuestLogFontsContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(QuestLogFontsContainer)
        local StyleObjectiveTrackerFontsCheckbox = AG:Create("CheckBox")
        StyleObjectiveTrackerFontsCheckbox:SetLabel("Style Quest Log Fonts")
        StyleObjectiveTrackerFontsCheckbox:SetValue(FragUI.DB.global.BlizzardFonts.StyleObjectiveTracker)
        StyleObjectiveTrackerFontsCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value ~= FragUI.DB.global.BlizzardFonts.StyleObjectiveTracker then FragUI.DB.global.BlizzardFonts.StyleObjectiveTracker = value FragUI:RequestReload() end end)
        StyleObjectiveTrackerFontsCheckbox:SetRelativeWidth(1)
        QuestLogFontsContainer:AddChild(StyleObjectiveTrackerFontsCheckbox)

        local ObjectiveTrackerLineFontSizeSlider = AG:Create("Slider")
        ObjectiveTrackerLineFontSizeSlider:SetLabel("Objective Tracker Line Font Size")
        ObjectiveTrackerLineFontSizeSlider:SetValue(FragUI.DB.global.BlizzardFonts.ObjectiveTrackerLineFontSize)
        ObjectiveTrackerLineFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, SLIDER_FONT_MAX, 1)
        ObjectiveTrackerLineFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ObjectiveTrackerLineFontSize = value FragUI:UpdateObjectiveTrackerFonts() end)
        ObjectiveTrackerLineFontSizeSlider:SetRelativeWidth(0.5)
        QuestLogFontsContainer:AddChild(ObjectiveTrackerLineFontSizeSlider)
        local ObjectiveTrackerHeaderFontSizeSlider = AG:Create("Slider")
        ObjectiveTrackerHeaderFontSizeSlider:SetLabel("Objective Tracker Header Font Size")
        ObjectiveTrackerHeaderFontSizeSlider:SetValue(FragUI.DB.global.BlizzardFonts.ObjectiveTrackerHeaderFontSize)
        ObjectiveTrackerHeaderFontSizeSlider:SetSliderValues(SLIDER_FONT_MIN, SLIDER_FONT_MAX, 1)
        ObjectiveTrackerHeaderFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.BlizzardFonts.ObjectiveTrackerHeaderFontSize = value FragUI:UpdateObjectiveTrackerFonts() end)
        ObjectiveTrackerHeaderFontSizeSlider:SetRelativeWidth(0.5)
        QuestLogFontsContainer:AddChild(ObjectiveTrackerHeaderFontSizeSlider)
    end

    local function DrawDetailsBackdropsContainer(GUIContainer)
        if (_detalhes_global and _detalhes_global["always_use_profile"] and _detalhes_global["always_use_profile"] == true and _detalhes_global["always_use_profile_name"] ~= "FragUI") or (_detalhes_database and _detalhes_database["active_profile"] and _detalhes_database["active_profile"] ~= "FragUI") then
            local IncorrectProfileLabel = AG:Create("Label")
            IncorrectProfileLabel:SetText("|cFFFF4040FragUI Profile Inactive|r.\nPlease switch to the FragUI Profile in Details Options.\nYou must reload for changes to take effect.")
            IncorrectProfileLabel:SetRelativeWidth(1)
            IncorrectProfileLabel:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
            IncorrectProfileLabel:SetJustifyH("CENTER")
            IncorrectProfileLabel:SetJustifyV("MIDDLE")
            GUIContainer:AddChild(IncorrectProfileLabel)
            return
        end

        local DetailsLayoutSelectorDropdown = AG:Create("Dropdown")
        DetailsLayoutSelectorDropdown:SetLabel("Details Layout")
        DetailsLayoutSelectorDropdown:SetList({
            ["Horizontal"] = "Horizontal",
            ["Vertical"] = "Vertical",
        })
        DetailsLayoutSelectorDropdown:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsLayout)
        DetailsLayoutSelectorDropdown:SetCallback("OnValueChanged", function(widget, event, value)
            if value == FragUI.DB.global.DetailsBackdrops.DetailsLayout then return end
            FragUI.DB.global.DetailsBackdrops.DetailsLayout = value
            FragUI:ApplyDetailsPreset(value)
            FragUI:UpdateDetailsBackdrops()
            FragUI:PositionTipTac()
            FragUI:ReOpenGUI()
        end)
        DetailsLayoutSelectorDropdown:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will swap the layout of the Details Windows.") end)
        DetailsLayoutSelectorDropdown:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        DetailsLayoutSelectorDropdown:SetRelativeWidth(0.5)
        GUIContainer:AddChild(DetailsLayoutSelectorDropdown)

        local AdjustTipTacCheckbox = AG:Create("CheckBox")
        AdjustTipTacCheckbox:SetLabel("Adjust TipTac")
        AdjustTipTacCheckbox:SetValue(FragUI.DB.global.DetailsBackdrops.AdjustTipTac)
        AdjustTipTacCheckbox:SetCallback("OnValueChanged", function(_, _, value) FragUI.DB.global.DetailsBackdrops.AdjustTipTac = value FragUI:RequestReload() end)
        AdjustTipTacCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will automatically position TipTac based on the Details Layout.\nThis ignores the anchor position set by TipTac.\nIf you want to position yourself, |cFFFF4040uncheck|r this.") end)
        AdjustTipTacCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        AdjustTipTacCheckbox:SetRelativeWidth(0.5)
        GUIContainer:AddChild(AdjustTipTacCheckbox)
        local DetailsFrameOneContainer = AG:Create("InlineGroup")
        DetailsFrameOneContainer:SetTitle("Details Frame One")
        DetailsFrameOneContainer:SetLayout("Flow")
        DetailsFrameOneContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(DetailsFrameOneContainer)
        local DetailsFrameOneEnabledCheckbox = AG:Create("CheckBox")
        DetailsFrameOneEnabledCheckbox:SetLabel("Enabled")
        DetailsFrameOneEnabledCheckbox:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Enabled)
        DetailsFrameOneEnabledCheckbox:SetCallback("OnValueChanged", function(_, _, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Enabled = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneEnabledCheckbox:SetRelativeWidth(1)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneEnabledCheckbox)
        local DetailsFrameOneBackdropColorPicker = AG:Create("ColorPicker")
        DetailsFrameOneBackdropColorPicker:SetLabel("Backdrop Color")
        local DF1R, DF1G, DF1B, DF1A = unpack(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor)
        DetailsFrameOneBackdropColorPicker:SetColor(DF1R, DF1G, DF1B, DF1A)
        DetailsFrameOneBackdropColorPicker:SetHasAlpha(true)
        DetailsFrameOneBackdropColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
            FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropColor = { r, g, b, a }
            FragUI:UpdateDetailsBackdrops()
        end)
        DetailsFrameOneBackdropColorPicker:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneBackdropColorPicker)
        local DetailsFrameOneBackdropBorderColorPicker = AG:Create("ColorPicker")
        DetailsFrameOneBackdropBorderColorPicker:SetLabel("Backdrop Border Color")
        local DF1BR, DF1BG, DF1BB, DF1BA = unpack(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor)
        DetailsFrameOneBackdropBorderColorPicker:SetColor(DF1BR, DF1BG, DF1BB, DF1BA)
        DetailsFrameOneBackdropBorderColorPicker:SetHasAlpha(true)
        DetailsFrameOneBackdropBorderColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
            FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.DetailsBackdropBorderColor = { r, g, b, a }
            FragUI:UpdateDetailsBackdrops()
        end)
        DetailsFrameOneBackdropBorderColorPicker:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneBackdropBorderColorPicker)
        local DetailsFrameOneRowsSlider = AG:Create("Slider")
        DetailsFrameOneRowsSlider:SetLabel("Rows")
        DetailsFrameOneRowsSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Rows)
        DetailsFrameOneRowsSlider:SetSliderValues(1, 20, 1)
        DetailsFrameOneRowsSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Rows = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneRowsSlider:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneRowsSlider)
        local DetailsFrameOneWidthSlider = AG:Create("Slider")
        DetailsFrameOneWidthSlider:SetLabel("Width")
        DetailsFrameOneWidthSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Width)
        DetailsFrameOneWidthSlider:SetSliderValues(SLIDER_WIDTH_MIN, SLIDER_WIDTH_MAX, 1)
        DetailsFrameOneWidthSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.Width = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneWidthSlider:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneWidthSlider)
        local DetailsFrameOneAnchorFromDropdown = AG:Create("Dropdown")
        DetailsFrameOneAnchorFromDropdown:SetLabel("Anchor From")
        DetailsFrameOneAnchorFromDropdown:SetList(ANCHORS)
        DetailsFrameOneAnchorFromDropdown:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom)
        DetailsFrameOneAnchorFromDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorFrom = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneAnchorFromDropdown:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneAnchorFromDropdown)
        local DetailsFrameOneAnchorToDropdown = AG:Create("Dropdown")
        DetailsFrameOneAnchorToDropdown:SetLabel("Anchor To")
        DetailsFrameOneAnchorToDropdown:SetList(ANCHORS)
        DetailsFrameOneAnchorToDropdown:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo)
        DetailsFrameOneAnchorToDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.AnchorTo = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneAnchorToDropdown:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneAnchorToDropdown)
        local DetailsFrameOneOffsetXSlider = AG:Create("Slider")
        DetailsFrameOneOffsetXSlider:SetLabel("Offset X")
        DetailsFrameOneOffsetXSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX)
        DetailsFrameOneOffsetXSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DetailsFrameOneOffsetXSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetX = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneOffsetXSlider:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneOffsetXSlider)
        local DetailsFrameOneOffsetYSlider = AG:Create("Slider")
        DetailsFrameOneOffsetYSlider:SetLabel("Offset Y")
        DetailsFrameOneOffsetYSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY)
        DetailsFrameOneOffsetYSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DetailsFrameOneOffsetYSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameOne.OffsetY = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameOneOffsetYSlider:SetRelativeWidth(0.5)
        DetailsFrameOneContainer:AddChild(DetailsFrameOneOffsetYSlider)

        local DetailsFrameTwoContainer = AG:Create("InlineGroup")
        DetailsFrameTwoContainer:SetTitle("Details Frame Two")
        DetailsFrameTwoContainer:SetLayout("Flow")
        DetailsFrameTwoContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(DetailsFrameTwoContainer)

        local DetailsFrameTwoEnabledCheckbox = AG:Create("CheckBox")
        DetailsFrameTwoEnabledCheckbox:SetLabel("Enabled")
        DetailsFrameTwoEnabledCheckbox:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Enabled)
        DetailsFrameTwoEnabledCheckbox:SetCallback("OnValueChanged", function(_, _, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Enabled = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoEnabledCheckbox:SetRelativeWidth(1)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoEnabledCheckbox)
        local DetailsFrameTwoBackdropColorPicker = AG:Create("ColorPicker")
        DetailsFrameTwoBackdropColorPicker:SetLabel("Backdrop Color")
        local DF2R, DF2G, DF2B, DF2A = unpack(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor)
        DetailsFrameTwoBackdropColorPicker:SetColor(DF2R, DF2G, DF2B, DF2A)
        DetailsFrameTwoBackdropColorPicker:SetHasAlpha(true)

        DetailsFrameTwoBackdropColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
            FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropColor = { r, g, b, a }
            FragUI:UpdateDetailsBackdrops()
        end)
        DetailsFrameTwoBackdropColorPicker:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoBackdropColorPicker)
        local DetailsFrameTwoBackdropBorderColorPicker = AG:Create("ColorPicker")
        DetailsFrameTwoBackdropBorderColorPicker:SetLabel("Backdrop Border Color")
        local DF2BR, DF2BG, DF2BB, DF2BA = unpack(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor)
        DetailsFrameTwoBackdropBorderColorPicker:SetColor(DF2BR, DF2BG, DF2BB, DF2BA)
        DetailsFrameTwoBackdropBorderColorPicker:SetHasAlpha(true)
        DetailsFrameTwoBackdropBorderColorPicker:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
            FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.DetailsBackdropBorderColor = { r, g, b, a }
            FragUI:UpdateDetailsBackdrops()
        end)
        DetailsFrameTwoBackdropBorderColorPicker:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoBackdropBorderColorPicker)
        local DetailsFrameTwoRowsSlider = AG:Create("Slider")
        DetailsFrameTwoRowsSlider:SetLabel("Rows")
        DetailsFrameTwoRowsSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Rows)
        DetailsFrameTwoRowsSlider:SetSliderValues(1, 20, 1)
        DetailsFrameTwoRowsSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Rows = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoRowsSlider:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoRowsSlider)
        local DetailsFrameTwoWidthSlider = AG:Create("Slider")
        DetailsFrameTwoWidthSlider:SetLabel("Width")
        DetailsFrameTwoWidthSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Width)
        DetailsFrameTwoWidthSlider:SetSliderValues(SLIDER_WIDTH_MIN, SLIDER_WIDTH_MAX, 1)
        DetailsFrameTwoWidthSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.Width = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoWidthSlider:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoWidthSlider)
        local DetailsFrameTwoAnchorFromDropdown = AG:Create("Dropdown")
        DetailsFrameTwoAnchorFromDropdown:SetLabel("Anchor From")
        DetailsFrameTwoAnchorFromDropdown:SetList(ANCHORS)
        DetailsFrameTwoAnchorFromDropdown:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom)
        DetailsFrameTwoAnchorFromDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorFrom = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoAnchorFromDropdown:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoAnchorFromDropdown)
        local DetailsFrameTwoAnchorToDropdown = AG:Create("Dropdown")
        DetailsFrameTwoAnchorToDropdown:SetLabel("Anchor To")
        DetailsFrameTwoAnchorToDropdown:SetList(ANCHORS)
        DetailsFrameTwoAnchorToDropdown:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo)
        DetailsFrameTwoAnchorToDropdown:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.AnchorTo = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoAnchorToDropdown:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoAnchorToDropdown)
        local DetailsFrameTwoOffsetXSlider = AG:Create("Slider")
        DetailsFrameTwoOffsetXSlider:SetLabel("Offset X")
        DetailsFrameTwoOffsetXSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX)
        DetailsFrameTwoOffsetXSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DetailsFrameTwoOffsetXSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetX = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoOffsetXSlider:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoOffsetXSlider)
        local DetailsFrameTwoOffsetYSlider = AG:Create("Slider")
        DetailsFrameTwoOffsetYSlider:SetLabel("Offset Y")
        DetailsFrameTwoOffsetYSlider:SetValue(FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY)
        DetailsFrameTwoOffsetYSlider:SetSliderValues(SLIDER_OFFSET_MIN, SLIDER_OFFSET_MAX, 1)
        DetailsFrameTwoOffsetYSlider:SetCallback("OnValueChanged", function(widget, event, value) FragUI.DB.global.DetailsBackdrops.DetailsFrameTwo.OffsetY = value FragUI:UpdateDetailsBackdrops() end)
        DetailsFrameTwoOffsetYSlider:SetRelativeWidth(0.5)
        DetailsFrameTwoContainer:AddChild(DetailsFrameTwoOffsetYSlider)
    end

    local function DrawCVarContainer(GUIContainer)
        local GeneralContainer = AG:Create("InlineGroup")
        GeneralContainer:SetTitle("General CVars")
        GeneralContainer:SetLayout("Flow")
        GeneralContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(GeneralContainer)

        local AutoPushSpellToActionBarCheckbox = AG:Create("CheckBox")
        AutoPushSpellToActionBarCheckbox:SetLabel("Auto Push Spells")
        AutoPushSpellToActionBarCheckbox:SetValue(GetCVar("autoPushSpellToActionBar") == "1")
        AutoPushSpellToActionBarCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("autoPushSpellToActionBar", "1") else SetCVar("autoPushSpellToActionBar", "0") end end)
        AutoPushSpellToActionBarCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will automatically push new spells to your action bar.") end)
        AutoPushSpellToActionBarCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        AutoPushSpellToActionBarCheckbox:SetRelativeWidth(0.33)
        GeneralContainer:AddChild(AutoPushSpellToActionBarCheckbox)

        local AlwaysResharpenCheckbox = AG:Create("CheckBox")
        AlwaysResharpenCheckbox:SetLabel("Always Resharpen")
        AlwaysResharpenCheckbox:SetValue(GetCVar("ResampleAlwaysSharpen") == "1")
        AlwaysResharpenCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will always resharpen the UI textures, which can improve visual quality.") end)
        AlwaysResharpenCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        AlwaysResharpenCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("ResampleAlwaysSharpen", "1") else SetCVar("ResampleAlwaysSharpen", "0") end end)
        AlwaysResharpenCheckbox:SetRelativeWidth(0.33)
        GeneralContainer:AddChild(AlwaysResharpenCheckbox)

        local ShowTutorialsCheckbox = AG:Create("CheckBox")
        ShowTutorialsCheckbox:SetLabel("Show Tutorials")
        ShowTutorialsCheckbox:SetValue(GetCVar("showTutorials") == "1")
        ShowTutorialsCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("showTutorials", "1") else SetCVar("showTutorials", "0") end end)
        ShowTutorialsCheckbox:SetRelativeWidth(0.33)
        GeneralContainer:AddChild(ShowTutorialsCheckbox)

        local SpellQueueWindowSlider = AG:Create("Slider")
        SpellQueueWindowSlider:SetLabel("Spell Queue Window")
        SpellQueueWindowSlider:SetValue(GetCVar("spellQueueWindow"))
        SpellQueueWindowSlider:SetSliderValues(0, 1000, 1)
        SpellQueueWindowSlider:SetCallback("OnValueChanged", function(widget, event, value) SetCVar("spellQueueWindow", value) end)
        SpellQueueWindowSlider:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will adjust the spell queue window, which allows you to queue spells while casting.") end)
        SpellQueueWindowSlider:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        SpellQueueWindowSlider:SetRelativeWidth(1)
        GeneralContainer:AddChild(SpellQueueWindowSlider)

        local CombatTextContainer = AG:Create("Heading")
        CombatTextContainer:SetText("Floating Combat Text CVars")
        GeneralContainer:AddChild(CombatTextContainer)

        local EnableFloatingCombatTextCheckbox = AG:Create("CheckBox")
        EnableFloatingCombatTextCheckbox:SetLabel("Combat Text on Player")
        EnableFloatingCombatTextCheckbox:SetValue(GetCVar("enableFloatingCombatText") == "1")
        EnableFloatingCombatTextCheckbox:SetRelativeWidth(0.33)
        EnableFloatingCombatTextCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will display the incoming healing / damage on you.") end)
        EnableFloatingCombatTextCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        EnableFloatingCombatTextCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("enableFloatingCombatText", "1") else SetCVar("enableFloatingCombatText", "0") end end)
        GeneralContainer:AddChild(EnableFloatingCombatTextCheckbox)

        local FloatingCombatTextCombatDamageCheckbox = AG:Create("CheckBox")
        FloatingCombatTextCombatDamageCheckbox:SetLabel("Combat Damage")
        FloatingCombatTextCombatDamageCheckbox:SetValue(GetCVar("floatingCombatTextCombatDamage") == "1")
        FloatingCombatTextCombatDamageCheckbox:SetRelativeWidth(0.33)
        FloatingCombatTextCombatDamageCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will display the damage you deal to enemies.") end)
        FloatingCombatTextCombatDamageCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        FloatingCombatTextCombatDamageCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("floatingCombatTextCombatDamage", "1") else SetCVar("floatingCombatTextCombatDamage", "0") end end)
        GeneralContainer:AddChild(FloatingCombatTextCombatDamageCheckbox)

        local FloatingCombatTextCombatHealingCheckbox = AG:Create("CheckBox")
        FloatingCombatTextCombatHealingCheckbox:SetLabel("Combat Healing")
        FloatingCombatTextCombatHealingCheckbox:SetValue(GetCVar("floatingCombatTextCombatHealing") == "1")
        FloatingCombatTextCombatHealingCheckbox:SetRelativeWidth(0.33)
        FloatingCombatTextCombatHealingCheckbox:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will display the healing you do.") end)
        FloatingCombatTextCombatHealingCheckbox:SetCallback("OnLeave", function() GameTooltip:Hide () end)
        FloatingCombatTextCombatHealingCheckbox:SetCallback("OnValueChanged", function(_, _, value) if value then SetCVar("floatingCombatTextCombatHealing", "1") else SetCVar("floatingCombatTextCombatHealing", "0") end end)
        GeneralContainer:AddChild(FloatingCombatTextCombatHealingCheckbox)

        local RaidSpecificContainer = AG:Create("InlineGroup")
        RaidSpecificContainer:SetTitle("Raid CVars")
        RaidSpecificContainer:SetLayout("Flow")
        RaidSpecificContainer:SetRelativeWidth(1)
        GUIContainer:AddChild(RaidSpecificContainer)

        local RaidWaterDetailSlider = AG:Create("Slider")
        RaidWaterDetailSlider:SetLabel("Raid Water Detail")
        RaidWaterDetailSlider:SetValue(GetCVar("raidWaterDetail"))
        RaidWaterDetailSlider:SetSliderValues(0, 3, 1)
        RaidWaterDetailSlider:SetCallback("OnValueChanged", function(widget, event, value) SetCVar("raidWaterDetail", value) end)
        RaidWaterDetailSlider:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will adjust the water detail in raids.\n0: Low, 3: High") end)
        RaidWaterDetailSlider:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        RaidWaterDetailSlider:SetRelativeWidth(0.5)
        RaidSpecificContainer:AddChild(RaidWaterDetailSlider)

        local RaidWeatherDensitySlider = AG:Create("Slider")
        RaidWeatherDensitySlider:SetLabel("Raid Weather Density")
        RaidWeatherDensitySlider:SetValue(GetCVar("raidWeatherDensity"))
        RaidWeatherDensitySlider:SetSliderValues(0, 3, 1)
        RaidWeatherDensitySlider:SetCallback("OnValueChanged", function(widget, event, value) SetCVar("raidWeatherDensity", value) end)
        RaidWeatherDensitySlider:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will adjust the weather density in raids.\n0: None, 3: All") end)
        RaidWeatherDensitySlider:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        RaidWeatherDensitySlider:SetRelativeWidth(0.5)
        RaidSpecificContainer:AddChild(RaidWeatherDensitySlider)

        local RaidFogLevelSlider = AG:Create("Slider")
        RaidFogLevelSlider:SetLabel("Raid Fog Level")
        RaidFogLevelSlider:SetValue(GetCVar("RAIDVolumeFogLevel"))
        RaidFogLevelSlider:SetSliderValues(0, 3, 1)
        RaidFogLevelSlider:SetCallback("OnValueChanged", function(widget, event, value) SetCVar("RAIDVolumeFogLevel", value) end)
        RaidFogLevelSlider:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will adjust the fog level in raids.\n0: None, 3: Full") end)
        RaidFogLevelSlider:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        RaidFogLevelSlider:SetRelativeWidth(0.5)
        RaidSpecificContainer:AddChild(RaidFogLevelSlider)

        local SpellClutterSlider = AG:Create("Slider")
        SpellClutterSlider:SetLabel("Spell Clutter")
        SpellClutterSlider:SetValue(GetCVar("spellClutter"))
        SpellClutterSlider:SetSliderValues(-1, 100, 1)
        SpellClutterSlider:SetCallback("OnValueChanged", function(widget, event, value) SetCVar("spellClutter", value) end)
        SpellClutterSlider:SetCallback("OnEnter", function(widget) GameTooltip:SetOwner(widget.frame, "ANCHOR_CURSOR_RIGHT") GameTooltip:SetText("This will adjust the spell clutter in raid.\n-1: Based on TargetFPS, 0: None, 100: Full\nThe more you cull, the bigger the performance impact.") end)
        SpellClutterSlider:SetCallback("OnLeave", function() GameTooltip:Hide() end)
        SpellClutterSlider:SetRelativeWidth(0.5)
        RaidSpecificContainer:AddChild(SpellClutterSlider)
    end

    local function DrawCreditsContainer(GUIContainer)
        local CreditsHeading = AG:Create("Heading")
        CreditsHeading:SetText("Credits")
        CreditsHeading:SetRelativeWidth(1)
        GUIContainer:AddChild(CreditsHeading)

        CreateCreditSection(GUIContainer, "DPS / Tank WeakAuras",  "|cFFA330C9Hype|r", "https://www.twitch.tv/hypewow", "Supported with DPS / Tank Class WeakAuras.")
        CreateCreditSection(GUIContainer, "Healer WeakAuras", "|cFFFFFFFFArgentwings|r", nil, "Supported with the Healer UI & Healer Class WeakAuras.")
        CreateCreditSection(GUIContainer, "Healer WeakAuras",  "|cFFF48CBAMky|r", nil, "Supported with the Healer UI & Healer Class WeakAuras.")
        CreateCreditSection(GUIContainer, "Death Knight WeakAuras",  "|cFFC41E3AObli|r", "https://www.youtube.com/@obliwow", "Supported with Death Knight.")
        CreateCreditSection(GUIContainer, "Hunter WeakAuras",  "|cFFABD473Nep|r", nil, "Supported with Hunter.")
        CreateCreditSection(GUIContainer, "Shadow Priest WeakAuras",  "|cFF4080FFNezy|r", "https://www.twitch.tv/nezyyxd", "Supported with Shadow Priest.")
        CreateCreditSection(GUIContainer, "Warlock WeakAuras",  "|cFF9482C9Torvastad|r", nil, "Supported with Warlock.")
        CreateCreditSection(GUIContainer, "Warrior WeakAuras",  "|cFFC69B6DSleepy|r", nil, "Supported with Warrior.")
        CreateCreditSection(GUIContainer, "Dungeon WeakAuras", "|cFFAAD372Nørskenwow|r", "https://wago.io/p/N%C3%B8rskenwow", "Dungeon WeakAuras.")

        local MegSpecialThanks = AG:Create("Label")
        MegSpecialThanks:SetText("|cFFFF40FFMeg|r")
        MegSpecialThanks:SetRelativeWidth(1)
        MegSpecialThanks:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        MegSpecialThanks:SetJustifyH("LEFT")
        GUIContainer:AddChild(MegSpecialThanks)
    end

    function SelectedGroup(GUIContainer, _, Group)
        GUIContainer:ReleaseChildren()

        local ScrollFrame = AG:Create("ScrollFrame")
        ScrollFrame:SetLayout("Flow")
        ScrollFrame:SetFullWidth(true)
        ScrollFrame:SetFullHeight(true)
        GUIContainer:AddChild(ScrollFrame)

        if Group == "General" then
            DrawGeneralContainer(ScrollFrame)
        elseif Group == "CharacterPane" then
            DrawCharacterPaneContainer(ScrollFrame)
        elseif Group == "BlizzardFonts" then
            DrawBlizzardFontsContainer(ScrollFrame)
        elseif Group == "DetailsBackdrops" then
            DrawDetailsBackdropsContainer(ScrollFrame)
        elseif Group == "CVars" then
            DrawCVarContainer(ScrollFrame)
        elseif Group == "Credits" then
            DrawCreditsContainer(ScrollFrame)
        end
    end


    GUIContainerTabGroup = AG:Create("TabGroup")
    GUIContainerTabGroup:SetLayout("Flow")
    GUIContainerTabGroup:SetTabs({
        { text = "General", value = "General"},
        { text = "Character Pane", value = "CharacterPane"},
        { text = "Blizzard Fonts", value = "BlizzardFonts"},
        { text = "Details Backdrops", value = "DetailsBackdrops"},
        { text = "CVars", value = "CVars"},
        { text = "Credits", value = "Credits"},
    })
    GUIContainerTabGroup:SetCallback("OnGroupSelected", SelectedGroup)
    GUIContainerTabGroup:SelectTab(tabToOpen or "General")
    GUIContainer:AddChild(GUIContainerTabGroup)
end

SLASH_FRAGUI1 = "/fragui"
SLASH_FRAGUI2 = "/fraguienhanced"
SLASH_FRAGUI3 = "/fui"
SlashCmdList["FRAGUI"] = function(msg)
    if msg == "dev" then
        isInDevMode = true
        FragUI:CreateGUI()
    else
        FragUI:CreateGUI(nil)
    end
end