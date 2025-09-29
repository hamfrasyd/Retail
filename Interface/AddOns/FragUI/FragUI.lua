local _, FragUI = ...
local FUI = LibStub("AceAddon-3.0"):NewAddon("FragUI")
local ADDON_NAME = C_AddOns.GetAddOnMetadata("FragUI", "Title")

function FUI:OnInitialize()
    FragUI.DB = LibStub("AceDB-3.0"):New("FragUIDB", FragUI.Defaults, true)
    for k, v in pairs(FragUI.Defaults.global) do
        if FragUI.DB.global[k] == nil then
            FragUI.DB.global[k] = v
        end
    end
end

function FUI:OnEnable()
    print(ADDON_NAME .. ": '|cFF8080FF/fragui|r' for in-game configuration!")
    FragUI:Setup()
end