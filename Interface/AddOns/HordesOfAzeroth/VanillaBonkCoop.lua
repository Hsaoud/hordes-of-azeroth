local UI = VanillaBonkUI
UI.Coop = { enabled = false }
local coop = UI.Coop

local panel = CreateFrame("Frame", "VanillaBonkCoop", UIParent)
panel:SetWidth(244)
panel:SetHeight(98)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -165)
panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
panel:SetBackdropColor(0.06, 0.04, 0.03, 0.92)
panel:SetBackdropBorderColor(0.7, 0.52, 0.22, 0.8)
panel:Hide()

local title = UI.Text(panel, 12)
title:SetPoint("TOPLEFT", panel, "TOPLEFT", 13, -12)
title:SetTextColor(1, 0.82, 0)
title:SetText("CO-OP · 2 PLAYERS")

local name = UI.Text(panel, 13)
name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -7)

local health = CreateFrame("StatusBar", nil, panel)
health:SetWidth(216)
health:SetHeight(7)
health:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
health:SetStatusBarColor(0.25, 0.75, 0.38)
health:SetMinMaxValues(0, 1)

local status = UI.Text(panel, 10)
status:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, -7)
status:SetWidth(216)
status:SetJustifyH("LEFT")

local cancel = UI.Button(panel, 110, "Cancel ready", function()
    SendChatMessage(".bonk stop", "SAY")
end)
cancel:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 9, -2)
cancel:Hide()

local function Refresh()
    if not coop.enabled then
        panel:Hide()
        return
    end
    panel:Show()
    name:SetText(coop.friend ~= "" and coop.friend or "Waiting for your friend")
    local unit = "party1"
    local maximum = UnitHealthMax(unit) or 0
    health:SetValue(maximum > 0 and (UnitHealth(unit) or 0) / maximum or 0)
    if coop.paused then
        status:SetText("Paused together · choosing an upgrade")
    elseif coop.ready then
        status:SetText("Ready for " .. coop.difficulty .. " · waiting")
    elseif coop.friendReady then
        status:SetText("Your friend is ready for " .. coop.difficulty)
    elseif coop.friend == "" then
        status:SetText("Both heroes must be at the outpost")
    elseif not UnitIsConnected(unit) then
        status:SetText("Your friend has disconnected")
    else
        status:SetText("Together in Azeroth")
    end
    if coop.ready then cancel:Show() else cancel:Hide() end
    if VanillaBonkArena and VanillaBonkArena.button then
        VanillaBonkArena.button:SetText(coop.ready and "Waiting…" or "Ready together")
        if coop.ready or coop.friend == "" then
            VanillaBonkArena.button:Disable()
        else
            VanillaBonkArena.button:Enable()
        end
    end
end

local elapsed = 0
panel:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= 0.25 then
        elapsed = 0
        Refresh()
    end
end)

UI.Listen({
    coop = function(f)
        coop.enabled = true
        coop.friend = f[2] or ""
        coop.ready = f[3] == "1"
        coop.difficulty = f[4] or ""
        coop.paused = f[5] == "1"
        coop.friendReady = f[6] == "1"
        Refresh()
    end,
})
