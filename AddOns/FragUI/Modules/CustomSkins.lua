local PLAYER_CLASS = select(2, UnitClass("player"))
local PLAYER_CLASS_COLOR = RAID_CLASS_COLORS[PLAYER_CLASS]
local PLAYER_CLASS_COLOR_HEX = CreateColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b):GenerateHexColor()
local _, FragUI = ...
local function RegisterLSToastSkins()
	if not C_AddOns.IsAddOnLoaded("ls_Toasts") then return end
	local LST = _G.ls_Toasts
	if not LST or not LST[1] or not LST[1].RegisterSkin then return end

	LST[1]:RegisterSkin("fragui", {
		name = "|TInterface/AddOns/FragUI/Media/FragUI.png:12:12|t FragUI",
		template = "elv",
		text_bg = { hidden = true },
		leaves = { hidden = true },
		dragon = { hidden = true },
		icon_highlight = { hidden = true },
		bg = {
			default = {
				texture = {26/255, 26/255, 26/255, 1.0},
			},
		},
		glow = {
			texture = {1, 1, 1, 0.25},
			size = {226, 50},
		},
		shine = {
			tex_coords = {403 / 512, 465 / 512, 15 / 256, 61 / 256},
			size = {0.1, 0.1},
			point = { y = 0, },
		},
	})
end

local function SkinMicroMenu()
	if not C_AddOns.IsAddOnLoaded("Bartender4") then return end
	if not FragUI.DB.global.General.SkinMicroMenu then return end
	local microButtons = {
		"CharacterMicroButton",
		"SpellbookMicroButton",
		"TalentMicroButton",
		"AchievementMicroButton",
		"QuestLogMicroButton",
		"GuildMicroButton",
		"LFDMicroButton",
		"CollectionsMicroButton",
		"EJMicroButton",
		"StoreMicroButton",
		"MainMenuMicroButton",
		"HelpMicroButton",
		"ProfessionMicroButton",
		"PlayerSpellsMicroButton"
	}

	for _, name in ipairs(microButtons) do
		local button = _G[name]
		if button and button.Background then
			button.Background:SetTexture(nil)
			button.Background:Hide()
			button.PushedBackground:SetTexture(nil)
			button.PushedBackground:Hide()
		end
	end

	for i, name in ipairs(microButtons) do
		local button = _G[name]
		if button and not button.BorderFrame then
			local border = CreateFrame("Frame", nil, button, "BackdropTemplate")
			border:SetFrameLevel(button:GetFrameLevel() - 1)

			local offset = 1
			if i == 5 or i == 9 then
				offset = 1.5
			elseif i == 13 then
				offset = offset + 0.1
			elseif i == 14 then
				offset = offset + 0.5
			end

			border:SetPoint("TOPLEFT", button, -offset, offset)
			border:SetPoint("BOTTOMRIGHT", button, offset, -offset)
			border:SetBackdrop({
				bgFile = "Interface\\Buttons\\WHITE8x8",
				edgeFile = "Interface\\Buttons\\WHITE8x8",
				edgeSize = 1,
			})
			border:SetBackdropColor(26/255, 26/255, 26/255, 1)
			border:SetBackdropBorderColor(0, 0, 0, 1)
			button.BorderFrame = border
		end
	end


	for _, name in ipairs(microButtons) do
		local button = _G[name]
		if button and button.OnEnter then
			button:HookScript("OnEnter", function()
				button.BorderFrame:SetBackdropColor(60/255, 60/255, 60/255, 1)
			end)
			button:HookScript("OnLeave", function()
				button.BorderFrame:SetBackdropColor(26/255, 26/255, 26/255, 1)
			end)
		end
	end
end

local function SkinBugsack()
	if not C_AddOns.IsAddOnLoaded("BugSack") then return end
	local ldb = LibStub("LibDataBroker-1.1", true)
	if not ldb then return end

	local bugSackLDB = ldb:GetDataObjectByName("BugSack")
	if not bugSackLDB then return end

	local bugAddon = _G["BugSack"]
	if not bugAddon or not bugAddon.UpdateDisplay or not bugAddon.GetErrors then return end

	if _G["FragUIBugsackButton"] then return end
	local FragUIBugsackButton = CreateFrame("Button", "FragUIBugsackButton", UIParent, "BackdropTemplate")
	FragUIBugsackButton:SetSize(16, 16)
	FragUIBugsackButton:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", 1, 1)
	FragUIBugsackButton.Text = FragUIBugsackButton:CreateFontString(nil, "OVERLAY")
	FragUIBugsackButton.Text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
	FragUIBugsackButton.Text:SetPoint("CENTER", FragUIBugsackButton, "CENTER", 2, 0)
	FragUIBugsackButton.Text:SetTextColor(1, 1, 1)
	FragUIBugsackButton.Text:SetText("|cFF40FF400|r")
	FragUIBugsackButton:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		tile = false, tileSize = 0, edgeSize = 1,
		insets = { left = 0, right = 0, top = 0, bottom = 0 },
	})
	FragUIBugsackButton:SetBackdropColor(26/255, 26/255, 26/255, 1.0)
	FragUIBugsackButton:SetBackdropBorderColor(0, 0, 0, 1)

	FragUIBugsackButton:SetScript("OnClick", function(self, mouseButton)
		if bugSackLDB.OnClick then
			bugSackLDB.OnClick(self, mouseButton)
		end
	end)

	FragUIBugsackButton:SetScript("OnEnter", function(self)
		if bugSackLDB.OnTooltipShow then
			FragUIBugsackButton:SetBackdropBorderColor(PLAYER_CLASS_COLOR.r, PLAYER_CLASS_COLOR.g, PLAYER_CLASS_COLOR.b, 1.0)
			GameTooltip:SetOwner(self, "ANCHOR_NONE")
			GameTooltip:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMLEFT", -2, -1)
			bugSackLDB.OnTooltipShow(GameTooltip)
			GameTooltip:Show()
		end
	end)

	FragUIBugsackButton:SetScript("OnLeave", function()
		FragUIBugsackButton:SetBackdropBorderColor(0, 0, 0, 1)
		GameTooltip:Hide()
	end)

	hooksecurefunc(bugAddon, "UpdateDisplay", function()
		local count = #bugAddon:GetErrors(BugGrabber:GetSessionId())
		if count == 0 then
			FragUIBugsackButton.Text:SetText("|cFF40FF40" .. count .. "|r")
		else
			FragUIBugsackButton.Text:SetText("|cFFFF4040" .. count .. "|r")
		end
	end)
end

local RegisterSkinsFrame = CreateFrame("Frame")
RegisterSkinsFrame:RegisterEvent("ADDON_LOADED")
RegisterSkinsFrame:SetScript("OnEvent", function(_, _, name)
	if name == "ls_Toasts" then
		RegisterLSToastSkins()
	end
	SkinMicroMenu()
	SkinBugsack()
	FragUI:SetupMinimapStats()
end)

