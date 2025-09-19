local _, FragUI = ...
local PLAYER_CLASS = select(2, UnitClass("player"))
local PLAYER_CLASS_COLOR = RAID_CLASS_COLORS[PLAYER_CLASS]
local UNIT_CLASS_COLOUR = (function(c) return ("ff%02x%02x%02x"):format(c.r*255, c.g*255, c.b*255) end)(RAID_CLASS_COLORS[select(2, UnitClass("player"))] or {r=1, g=1, b=1})

local MythicPlusGreatVaultiLvls = {
    [2] = "691",        -- +2
    [3] = "694",        -- +3
    [4] = "694",        -- +4
    [5] = "697",        -- +5
    [6] = "697",        -- +6
    [7] = "701",        -- +7
    [8] = "704",        -- +8
    [9] = "704",        -- +9
    [10] = "707",       -- +10
}
local RaidGreatVaultiLvls = {
    [14] = "636",                   -- Normal
    [15] = "649",                   -- Heroic
    [16] = "662",                   -- Mythic
    [17] = "623",                   -- LFR
}
local WorldGreatVaultiLvls = {
    [1] = "668",                    -- Tier 1
    [2] = "671",                    -- Tier 2
    [3] = "675",                    -- Tier 3
    [4] = "678",                    -- Tier 4
    [5] = "684",                    -- Tier 5
    [6] = "688",                    -- Tier 6
    [7] = "691",                    -- Tier 7
    [8] = "694",                    -- Tier 8
}

local GarrisonInstanceIDs = {
    [1152] = true,
    [1153] = true,
    [1154] = true,
    [1158] = true,
    [1159] = true,
    [1160] = true,
}

local RaidDifficultyIDs = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
}

local function FetchTime()
    local currTime = date("%H:%M")
    local currDate = date("%d %b")
    return string.format("%s - %s", currTime, currDate)
end

local function CreateTimeFrame()
    if _G["FragUI_MinimapStats_TimeFrame"] then return end
    local TimeFrame = CreateFrame("Frame", "FragUI_MinimapStats_TimeFrame", UIParent)
    TimeFrame:ClearAllPoints()
    TimeFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -3, -3)
    local TimeFrameText = TimeFrame:CreateFontString(nil, "OVERLAY")
    TimeFrameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    TimeFrameText:SetPoint("RIGHT", TimeFrame, "RIGHT")
    TimeFrameText:SetTextColor(1, 1, 1)
    TimeFrameText:SetText(FetchTime())
    TimeFrame:SetScript("OnUpdate", function(self, elapsed) self.elapsed = (self.elapsed or 0) + elapsed if self.elapsed >= 60 then TimeFrameText:SetText(FetchTime()) self.elapsed = 0 end end)
    TimeFrame:SetSize(TimeFrameText:GetStringWidth(), TimeFrameText:GetStringHeight())
    TimeFrame:SetFrameStrata("MEDIUM")
    TimeFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            ToggleCalendar()
        end
    end)
end

local function FetchSystemStats()
    local FPS = math.ceil(GetFramerate())
    local MS = select(3, GetNetStats())
    return string.format("%d|c%sFPS|r - %d|c%sMS|r", FPS, UNIT_CLASS_COLOUR, MS, UNIT_CLASS_COLOUR)
end

local function FetchVaultOptions()
    local RaidsCompleted = {}
    local MythicPlusRunsCompleted = {}
    local WorldRunsCompleted = {}
    if not C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then C_AddOns.LoadAddOn("Blizzard_WeeklyRewards") end

    local RaidRuns = C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.Raid)
    for i = 1, 3 do
        local DifficultyName = RaidDifficultyIDs[RaidRuns[i].level]
        local GViLvl = RaidGreatVaultiLvls[RaidRuns[i].level]
        if DifficultyName == nil then break end
        table.insert(RaidsCompleted, string.format("Slot #%d: |c" .. UNIT_CLASS_COLOUR .. "%s|r [%d]", i, DifficultyName, GViLvl))
    end

    local MythicPlusRuns = C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.MythicPlus)
    for i = 1, 3 do
        local KeyLevel = MythicPlusRuns[i].level
        local GViLvl = MythicPlusGreatVaultiLvls[MythicPlusRuns[i].level]
        if KeyLevel == nil or KeyLevel == 0 then break end
        if KeyLevel > 10 then GViLvl = MythicPlusGreatVaultiLvls[10] end
        table.insert(MythicPlusRunsCompleted, string.format("Slot #%d: |c" .. UNIT_CLASS_COLOUR .. "+%d|r [%d]", i, KeyLevel, GViLvl))
    end

    local WorldRuns = C_WeeklyRewards.GetActivities(Enum.WeeklyRewardChestThresholdType.World)
    for i = 1, 3 do
        local WorldLevel = WorldRuns[i].level
        local GViLvl = WorldGreatVaultiLvls[WorldRuns[i].level]
        if WorldLevel == nil or WorldLevel == 0 then break end
        if WorldLevel > 8 then GViLvl = WorldGreatVaultiLvls[8] end
        table.insert(WorldRunsCompleted, string.format("Slot #%d: |c" .. UNIT_CLASS_COLOUR .. "%d|r [%d]", i, WorldLevel, GViLvl))
    end

    if #RaidsCompleted > 0 then
        GameTooltip:AddLine("Raid", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
        for _, Raid in pairs(RaidsCompleted) do
            GameTooltip:AddLine(Raid, 1, 1, 1)
        end
    end

    if #MythicPlusRunsCompleted > 0 then
        if #RaidsCompleted > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1, 1)
        end
        GameTooltip:AddLine("Mythic+", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
        for _, Key in pairs(MythicPlusRunsCompleted) do
            GameTooltip:AddLine(Key, 1, 1, 1)
        end
    end

    if #WorldRunsCompleted > 0 then
        if #RaidsCompleted > 0 or #MythicPlusRunsCompleted > 0 then
            GameTooltip:AddLine(" ", 1, 1, 1, 1)
        end
        GameTooltip:AddLine("World", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
        for _, Delve in pairs(WorldRunsCompleted) do
            GameTooltip:AddLine(Delve, 1, 1, 1)
        end
    end

    if #RaidsCompleted > 0 or #MythicPlusRunsCompleted > 0 or #WorldRunsCompleted > 0 then
        GameTooltip:AddLine(" ", 1, 1, 1, 1)
    end
end

local function FetchKeystoneInformation()
    local TextureSize = 12
    local NoKeyTextureIcon = "|TInterface/Icons/inv_relics_hourglass.blp:" .. TextureSize .. ":" .. TextureSize .. ":0|t"
    local IsInDelve = select(4, GetInstanceInfo()) == "Delve"
    local OR = LibStub:GetLibrary("LibOpenRaid-1.0", true)
    OR.KeystoneInfoManager.OnReceiveRequestData()
    OR.RequestAllData()
    OR.GetAllKeystonesInfo()
    if not OR then return end

    local KeystoneInfo = OR.GetKeystoneInfo("player")
    GameTooltip:AddLine("Your |cFFFFFFFFKeystone|r", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
    if KeystoneInfo then
        local KeystoneLevel = KeystoneInfo.level
        local Keystone, _, _, KeystoneIcon = C_ChallengeMode.GetMapUIInfo(KeystoneInfo.challengeMapID)
        if Keystone and KeystoneIcon then
            local TexturedIcon = "|T" .. KeystoneIcon .. ":" .. TextureSize .. ":" .. TextureSize .. ":0|t"
            GameTooltip:AddLine(TexturedIcon .. " +" .. KeystoneLevel .. " " .. Keystone, 1, 1, 1, 1)
        elseif Keystone then
            GameTooltip:AddLine(NoKeyTextureIcon .. " +" .. KeystoneLevel .. " " .. Keystone, 1, 1, 1, 1)
        else
            GameTooltip:AddLine(NoKeyTextureIcon .. " No Keystone", 1, 1, 1, 1)
        end
    end
    if (IsInGroup() and not IsInRaid() and not IsInDelve) then
        GameTooltip:AddLine(" ", 1, 1, 1, 1)
    end

    local PartyMembers = {}
    local WHITE_COLOUR_OVERRIDE = "|cFFFFFFFF"
    if IsInGroup() and not IsInRaid() and not IsInDelve then
        GameTooltip:AddLine("Party |cFFFFFFFFKeystones|r", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
        for i = 1, GetNumGroupMembers() - 1 do
            local UnitID = "party" .. i
            local UnitName = GetUnitName(UnitID, true)
            if UnitName then
                table.insert(PartyMembers, UnitID)
            end
        end

        for _, UnitID in ipairs(PartyMembers) do
            local UnitName = GetUnitName(UnitID, true)
            local FormattedUnitName = UnitName:match("([^-]+)")
            local UnitClassColour = RAID_CLASS_COLORS[select(2, UnitClass(UnitID))]
            local KeystoneInfo = OR.GetKeystoneInfo(UnitID)

            if KeystoneInfo then
                local Keystone, _, _, KeystoneIcon = C_ChallengeMode.GetMapUIInfo(KeystoneInfo.challengeMapID)
                local KeystoneLevel = KeystoneInfo.level
                if Keystone and KeystoneIcon then
                    local TexturedIcon = "|T" .. KeystoneIcon .. ":" .. TextureSize .. ":" .. TextureSize .. ":0|t"
                    GameTooltip:AddLine(FormattedUnitName .. ": " .. WHITE_COLOUR_OVERRIDE .. TexturedIcon .. " +" .. KeystoneLevel .. " " .. Keystone .. "|r", UnitClassColour.r, UnitClassColour.g, UnitClassColour.b)
                elseif Keystone then
                    GameTooltip:AddLine(FormattedUnitName .. ": " .. WHITE_COLOUR_OVERRIDE .. NoKeyTextureIcon .. " +" .. KeystoneLevel .. " |r" .. Keystone, UnitClassColour.r, UnitClassColour.g, UnitClassColour.b)
                else
                    GameTooltip:AddLine(FormattedUnitName .. ": " .. WHITE_COLOUR_OVERRIDE .. NoKeyTextureIcon .. " No Keystone", UnitClassColour.r, UnitClassColour.g, UnitClassColour.b)
                end
            else
                GameTooltip:AddLine(FormattedUnitName .. ": " .. WHITE_COLOUR_OVERRIDE .. NoKeyTextureIcon .. " No Keystone", UnitClassColour.r, UnitClassColour.g, UnitClassColour.b)
            end
        end
    end
end

local function FetchUtilityInformation()
    local DelveMapCompleted = C_QuestLog.IsQuestFlaggedCompleted(86371)

    local DelveMapText = DelveMapCompleted and "|cFF40FF40Completed|r" or "|cFFFF4040Not Completed|r"
    GameTooltip:AddLine(" ", 1, 1, 1, 1)
    GameTooltip:AddLine("Delve Map: " .. DelveMapText, PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1)
end

local function FetchTooltipInfo()
    GameTooltip:SetOwner(Minimap, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", -2, -1)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(FetchVaultOptions())
    GameTooltip:AddLine(FetchKeystoneInformation())
    GameTooltip:AddLine(FetchUtilityInformation())
    GameTooltip:AddLine(" ", 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Left-Click", "Fetch Keystone Information", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1, 1, 1)
    GameTooltip:AddDoubleLine("Right-Click", "Open FragUI Options", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1, 1, 1)
    GameTooltip:AddDoubleLine("Middle-Click", "Reload UI", PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1, 1, 1)
    GameTooltip:Show()
end

local function ForceFetchKeystoneInformation()
    if GameTooltip:IsShown() then
        GameTooltip:Hide()
    end
    FetchTooltipInfo()
    print("|TInterface/AddOns/FragUI/Media/FragUI.png:16:16|t|cFF8080FFFrag|rUI: Refreshing Keystone Data...")
end

local function CreateSystemStatsFrame()
    if _G["FragUI_MinimapStats_SystemStatsFrame"] then return end
    local SystemStatsFrame = CreateFrame("Frame", "FragUI_MinimapStats_SystemStatsFrame", UIParent)
    SystemStatsFrame:ClearAllPoints()
    if _G["FragUIBugsackButton"] then
        SystemStatsFrame:SetPoint("LEFT", _G["FragUIBugsackButton"], "RIGHT", 1, 0)
    else
        SystemStatsFrame:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 3, 3)
    end
    local SystemStatsFrameText = SystemStatsFrame:CreateFontString(nil, "OVERLAY")
    SystemStatsFrameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    SystemStatsFrameText:SetPoint("LEFT", SystemStatsFrame, "LEFT")
    SystemStatsFrameText:SetTextColor(1, 1, 1)
    SystemStatsFrameText:SetText(FetchSystemStats())
    SystemStatsFrame:SetScript("OnUpdate", function(self, elapsed) self.elapsed = (self.elapsed or 0) + elapsed if self.elapsed >= 10 then SystemStatsFrameText:SetText(FetchSystemStats()) self.elapsed = 0 end end)
    SystemStatsFrame:SetSize(SystemStatsFrameText:GetStringWidth(), SystemStatsFrameText:GetStringHeight())
    SystemStatsFrame:SetFrameStrata("MEDIUM")
    SystemStatsFrame:SetScript("OnEnter", FetchTooltipInfo)
    SystemStatsFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    SystemStatsFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
                ForceFetchKeystoneInformation()
        elseif button == "RightButton" then
            FragUI:CreateGUI()
        elseif button == "MiddleButton" then
            ReloadUI()
        end
    end)
end

local function FetchLocation()
    return GetMinimapZoneText()
end

local function CreateLocationFrame()
    if _G["FragUI_MinimapStats_LocationFrame"] then return end
    local LocationFrame = CreateFrame("Frame", "FragUI_MinimapStats_LocationFrame", UIParent)
    LocationFrame:ClearAllPoints()
    LocationFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 3, -3)
    LocationFrame:RegisterEvent("ZONE_CHANGED")
    LocationFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    LocationFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    LocationFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    LocationFrame:RegisterEvent("PLAYER_LOGIN")
    local LocationFrameText = LocationFrame:CreateFontString(nil, "OVERLAY")
    LocationFrameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    LocationFrameText:SetPoint("LEFT", LocationFrame, "LEFT")
    LocationFrameText:SetTextColor(1, 1, 1)
    LocationFrameText:SetText(FetchLocation())
    LocationFrame:SetScript("OnEvent", function() LocationFrameText:SetText(FetchLocation()) end)
    LocationFrame:SetSize(220, 12)
    LocationFrame:SetFrameStrata("MEDIUM")
end

local function FetchInstanceDifficulty()
    local _, _, DiffID, _, MaxPlayers, _, _, InstanceID, CurrentPlayers = GetInstanceInfo()
    local KeystoneLevel = C_ChallengeMode.GetActiveKeystoneInfo()
    local PlayerInGarrison = GarrisonInstanceIDs[InstanceID]
    local InstanceDifficulty = ""

    if DiffID == 0 then
        InstanceDifficulty = ""
    elseif PlayerInGarrison then
        InstanceDifficulty = ""
    elseif DiffID == 1 or DiffID == 3 or DiffID == 4 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "N" .. "|r"
    elseif DiffID == 2 or DiffID == 5 or DiffID == 6 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "H" .. "|r"
    elseif DiffID == 16 or DiffID == 23 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "M" .. "|r"
    elseif DiffID == 8 then
        InstanceDifficulty = "|c" .. UNIT_CLASS_COLOUR .. "M" .. "|r" .. KeystoneLevel
    elseif DiffID == 9 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "N" .. "|r"
    elseif DiffID == 7 or DiffID == 17 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "LFR" .. "|r"
    elseif DiffID == 14 then
        InstanceDifficulty = CurrentPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "N" .. "|r"
    elseif DiffID == 15 then
        InstanceDifficulty = CurrentPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "H" .. "|r"
    elseif DiffID == 18 or DiffID == 19 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "EVT" .. "|r"
    elseif DiffID == 24 or DiffID == 33 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "TW" .. "|r"
    elseif DiffID == 11 or DiffID == 39 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "S+" .. "|r"
    elseif DiffID == 12 or DiffID == 38 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "S" .. "|r"
    elseif DiffID == 205 then
        InstanceDifficulty = MaxPlayers .. "|c" .. UNIT_CLASS_COLOUR .. "F" .. "|r"
    elseif DiffID == 208 then
        InstanceDifficulty = "D"
    end

    return string.format("%s", InstanceDifficulty)
end

local function CreateInstanceDifficultyFrame()
    if _G["FragUI_MinimapStats_InstanceDifficultyFrame"] then return end
    local InstanceDifficultyFrame = CreateFrame("Frame", "FragUI_MinimapStats_InstanceDifficultyFrame", UIParent)
    InstanceDifficultyFrame:ClearAllPoints()
    InstanceDifficultyFrame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 3, -17)
    InstanceDifficultyFrame:RegisterEvent("ZONE_CHANGED")
    InstanceDifficultyFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    InstanceDifficultyFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    InstanceDifficultyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    InstanceDifficultyFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    InstanceDifficultyFrame:RegisterEvent("GROUP_FORMED")
    InstanceDifficultyFrame:RegisterEvent("GROUP_JOINED")
    InstanceDifficultyFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    InstanceDifficultyFrame:RegisterEvent("CHALLENGE_MODE_START")
    InstanceDifficultyFrame:RegisterEvent("GROUP_LEFT")
    InstanceDifficultyFrame:RegisterEvent("PLAYER_LOGIN")
    local InstanceDifficultyFrameText = InstanceDifficultyFrame:CreateFontString(nil, "OVERLAY")
    InstanceDifficultyFrameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    InstanceDifficultyFrameText:SetPoint("LEFT", InstanceDifficultyFrame, "LEFT")
    InstanceDifficultyFrameText:SetTextColor(1, 1, 1)
    InstanceDifficultyFrameText:SetText(FetchInstanceDifficulty())
    InstanceDifficultyFrame:SetScript("OnEvent", function() InstanceDifficultyFrameText:SetText(FetchInstanceDifficulty()) end)
    InstanceDifficultyFrame:SetSize(220, 12)
    InstanceDifficultyFrame:SetFrameStrata("MEDIUM")
end

function FragUI:SetupMinimapStats()
    CreateTimeFrame()
    CreateSystemStatsFrame()
    CreateLocationFrame()
    CreateInstanceDifficultyFrame()
end