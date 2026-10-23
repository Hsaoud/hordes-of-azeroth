local UI = VanillaBonkUI

local DIFFICULTY_COLORS = {
    Normal = { 0.25, 1, 0.25 },
    Heroic = { 1, 0.82, 0 },
    Mythic = { 1, 0.3, 0.3 },
}

local run = { duration = 600, stage = 1, difficulty = "" }

local tracker = CreateFrame("Frame", "VanillaBonkTracker", UIParent)
tracker:SetWidth(240)
tracker:SetHeight(60)
tracker:SetPoint("TOP", UIParent, "TOP", 0, 0)
tracker:Hide()

tracker.timer = UI.Text(tracker, 28, UI.FONT, "OUTLINE")
tracker.timer:SetPoint("TOP", tracker, "TOP", 0, -4)

tracker.stage = UI.Text(tracker, 11)
tracker.stage:SetPoint("TOP", tracker.timer, "BOTTOM", 0, -3)

tracker.progress = CreateFrame("StatusBar", nil, tracker)
tracker.progress:SetPoint("TOP", tracker.stage, "BOTTOM", 0, -7)
tracker.progress:SetWidth(240)
tracker.progress:SetHeight(4)
tracker.progress:SetStatusBarTexture(UI.FLAT)
tracker.progress:SetMinMaxValues(0, 1)
tracker.progress:SetStatusBarColor(0.85, 0.65, 0.25)
local BEAT_WALL, BEAT_MINIBOSS = 2, 3
local BEAT_ICONS = { [BEAT_WALL] = "Ability_Warrior_Challange", [BEAT_MINIBOSS] = "Ability_Rogue_Eviscerate" }

local list = CreateFrame("Frame", "VanillaBonkRewards", UIParent)
list:SetWidth(242)
list:SetHeight(140)
list:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -196)
list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
list:SetBackdropColor(0.045, 0.035, 0.025, 0.94)
list:SetBackdropBorderColor(0.72, 0.55, 0.28, 0.9)
list:Hide()

local rows = {}
local function Row(index, label, icon, tooltip)
    local row = CreateFrame("Frame", nil, list)
    row:SetWidth((index == 1 or index == 3) and 106 or 218)
    row:SetHeight(26)
    local points = { {12, -10}, {12, -101}, {128, -10}, {12, -40}, {12, -70} }
    row:SetPoint("TOPLEFT", list, "TOPLEFT", points[index][1], points[index][2])
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexture(UI.ICON_PATH .. icon)
    row.icon:SetWidth(22)
    row.icon:SetHeight(22)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.value = UI.Text(row, 12)
    row.value:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
    row.label = UI.Text(row, 12)
    row.label:SetPoint("RIGHT", row.value, "LEFT", -5, 0)
    row.label:SetTextColor(1, 0.82, 0)
    row.label:SetText(label)
    row.label:Hide()
    row:EnableMouse(true)
    row.tooltip = tooltip
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        this.tooltip()
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[index] = row
    return row
end

local kills = Row(1, "Kills", "INV_Misc_Bone_HumanSkull_01", function()
    GameTooltip:AddDoubleLine("Kills", run.kills or 0, 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("Enemies killed this run.", 1, 0.82, 0)
end)
local valor = Row(2, "Valor", "INV_Misc_Coin_04", function()
    GameTooltip:AddDoubleLine("Valor", run.valor or 0, 1, 1, 1, 1, 0.9, 0.45)
    GameTooltip:AddLine("Collected during the run and spent to open chests and buy from shops.", 1, 0.82, 0, 1)
    GameTooltip:AddLine("Next chest: " .. (run.chest or "?") .. " Valor", 1, 1, 1)
    GameTooltip:AddLine("Resets every run, it's not kept.", 0.6, 0.6, 0.6)
end)
local shards = Row(3, "Tickets", "INV_Misc_Ticket_Darkmoon_01", function()
    GameTooltip:AddDoubleLine("Darkmoon Tickets", "+" .. (run.shards or 0), 1, 1, 1, 0.75, 0.5, 1)
    GameTooltip:AddLine("Spend them with Sayge at the Inn.", 1, 0.82, 0)
end)
local gold = Row(4, "Gold", "INV_Misc_Coin_02", function()
    GameTooltip:AddDoubleLine("Gold earned", UI.FormatGold(run.gold or 0), 1, 1, 1, 1, 1, 1)
    GameTooltip:AddLine("Yours to keep, even if you die.", 1, 0.82, 0)
end)
local greed = Row(5, "Greed", "Spell_Nature_EarthBindTotem", function()
    GameTooltip:AddDoubleLine("Greed", (run.greed or 0) .. (run.greed == 1 and " stack" or " stacks"), 1, 1, 1, 1, 0.82, 0)
    GameTooltip:AddLine("+" .. (run.greedReward or 0) .. "% gold and Darkmoon Tickets", 0.25, 1, 0.25)
    GameTooltip:AddLine((run.greedMobs or 0) .. "% more enemies", 1, 0.4, 0.4)
    GameTooltip:AddLine("Every Greed Totem taken this run adds a stack.", 1, 0.82, 0, 1)
end)
greed:Hide()
valor.progress = CreateFrame("StatusBar", nil, valor)
valor.progress:SetPoint("BOTTOMLEFT", valor, "BOTTOMLEFT", 29, -2)
valor.progress:SetWidth(150)
valor.progress:SetHeight(3)
valor.progress:SetStatusBarTexture(UI.FLAT)
valor.progress:SetMinMaxValues(0, 1)
valor.progress:SetStatusBarColor(1, 0.82, 0.35)

local function Refresh()
    local elapsed = run.elapsed or 0
    if run.portal then
        tracker.timer:SetText("|cff40c0ffPORTAL OPEN|r")
    elseif run.boss then
        tracker.timer:SetText("|cffff5a4a" .. UI.FormatTime(elapsed) .. "|r")
    else
        tracker.timer:SetText(UI.FormatTime(elapsed))
    end
    local stage = "|cffffd100Stage " .. run.stage .. "|r"
    local color = DIFFICULTY_COLORS[run.difficulty]
    if run.difficulty ~= "" and color then
        stage = stage .. format("  |cff9d9d9d·|r  |cff%02x%02x%02x%s|r", color[1] * 255, color[2] * 255, color[3] * 255, run.difficulty)
    elseif run.difficulty ~= "" then
        stage = stage .. "  |cff9d9d9d·|r  " .. run.difficulty
    end
    tracker.stage:SetText(stage)
    tracker.progress:SetValue(min(1, elapsed / max(1, run.duration)))
    tracker.progress:SetStatusBarColor(run.boss and 1 or 0.85, run.boss and 0.25 or 0.65, 0.25)
    valor.progress:SetValue(min(1, (run.valor or 0) / max(1, tonumber(run.chest) or 1)))

    kills.value:SetText(run.kills or 0)
    valor.value:SetText("|cffffe873" .. (run.valor or 0) .. "|r |cff9d9d9d/ " .. (run.chest or "?") .. "|r")
    shards.value:SetText("|cffd6b0ff" .. (run.shards or 0) .. "|r")
    gold.value:SetText(UI.FormatGold(run.gold or 0))
    if (run.greed or 0) > 0 then
        greed.value:SetText("|cffffd100x" .. run.greed .. "|r |cff9d9d9d+" .. (run.greedReward or 0) .. "%|r")
        greed:Show()
    else
        greed:Hide()
    end
    for _, row in ipairs(rows) do
        row.value:SetWidth(row:GetWidth() - 29)
        row.value:SetJustifyH("LEFT")
    end
end

tracker:SetScript("OnUpdate", function()
    this.elapsed = (this.elapsed or 0) + arg1
    if this.elapsed < 0.1 then
        return
    end
    this.elapsed = 0
    if VanillaBonkBossBar and VanillaBonkBossBar:IsShown() then
        tracker.stage:Hide()
    else
        tracker.stage:Show()
    end
end)

local CALLOUT_FADE_IN = 0.2
local CALLOUT_FADE_OUT = 0.4

local callout = CreateFrame("Frame", nil, UIParent)
callout:SetWidth(440)
callout:SetHeight(30)
callout:SetPoint("TOP", tracker, "BOTTOM", 0, -4)
callout:Hide()
for side = 1, 2 do
    local half = callout:CreateTexture(nil, "BACKGROUND")
    half:SetTexture(UI.FLAT)
    half:SetWidth(220)
    half:SetHeight(30)
    if side == 1 then
        half:SetPoint("LEFT", callout, "LEFT", 0, 0)
        if half.SetGradientAlpha then
            half:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.65)
        end
    else
        half:SetPoint("RIGHT", callout, "RIGHT", 0, 0)
        if half.SetGradientAlpha then
            half:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0.65, 0, 0, 0, 0)
        end
    end
end
callout.text = UI.Text(callout, 18, UI.FONT, "OUTLINE")
callout.text:SetPoint("CENTER", callout, "CENTER", 12, 0)
callout.text:SetTextColor(1, 0.25, 0.2)
callout.icon = callout:CreateTexture(nil, "ARTWORK")
callout.icon:SetWidth(22)
callout.icon:SetHeight(22)
callout.icon:SetPoint("RIGHT", callout.text, "LEFT", -6, 0)
callout.alpha, callout.want = 0, 0

local function CalloutText()
    local left = max(1, (callout.at or 0) - (run.elapsed or 0))
    callout.text:SetText(callout.name .. " |cffffffffin " .. left .. "s|r")
end

callout:SetScript("OnUpdate", function()
    local low = -4
    local bossBar = VanillaBonkBossBar
    if bossBar and bossBar:IsVisible() then
        low = -32
        if bossBar.debuffs:IsVisible() then
            low = low - bossBar.debuffs.height - 4
        end
    end
    if low ~= this.low then
        this.low = low
        this:ClearAllPoints()
        this:SetPoint("TOP", tracker, "BOTTOM", 0, low)
    end
    if this.alpha ~= this.want then
        local fade = this.want > this.alpha and CALLOUT_FADE_IN or CALLOUT_FADE_OUT
        local step = arg1 / fade
        this.alpha = this.want > this.alpha and min(this.want, this.alpha + step) or max(this.want, this.alpha - step)
        if this.alpha <= 0 then
            this:Hide()
            return
        end
    end
    this:SetAlpha(this.alpha * (0.8 + 0.2 * sin(GetTime() * 360)))
end)

local function HideCallout()
    callout.want, callout.alpha = 0, 0
    callout.at = nil
    callout:Hide()
end

local handlers = {}

handlers["beat"] = function(f)
    local seconds = tonumber(f[4] or "") or 0
    if seconds <= 0 then
        callout.at = nil
        callout.want = 0
        return
    end
    callout.name = f[2] ~= "" and f[2] or "Mini-boss"
    callout.at = (run.elapsed or 0) + seconds
    callout.icon:SetTexture(UI.ICON_PATH .. (BEAT_ICONS[tonumber(f[3] or "")] or BEAT_ICONS[BEAT_WALL]))
    CalloutText()
    callout.want = 1
    callout:Show()
    PlaySound("RaidWarning")
end

handlers["start"] = function(f)
    run.map = f[2] or ""
    run.difficulty = f[3] or ""
    run.duration = tonumber(f[4]) or 600
    run.stage = tonumber(f[5]) or 1
    run.elapsed = 0
    HideCallout()
    run.boss, run.portal = false, false
    Refresh()
    tracker:Show()
    list:Show()
end

handlers["state"] = function(f)
    run.elapsed = tonumber(f[2]) or 0
    run.duration = tonumber(f[3]) or run.duration
    run.kills = tonumber(f[4]) or 0
    run.gold = tonumber(f[5]) or 0
    run.boss = f[7] == "1"
    run.valor = tonumber(f[8]) or 0
    run.chest = f[9] or "?"
    run.stage = tonumber(f[10]) or run.stage
    run.portal = f[11] == "1"
    run.shards = tonumber(f[12]) or 0
    if callout.at then
        CalloutText()
    end
    Refresh()
    if not tracker:IsShown() then
        tracker:Show()
        list:Show()
    end
end

handlers["greed"] = function(f)
    run.greed = tonumber(f[2] or "") or 0
    run.greedReward = tonumber(f[3] or "") or 0
    run.greedMobs = tonumber(f[4] or "") or 0
    Refresh()
end

handlers["end"] = function()
    run.greed, run.greedReward, run.greedMobs = 0, 0, 0
    HideCallout()
    tracker:Hide()
    list:Hide()
end

UI.Listen(handlers)
