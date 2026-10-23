local UI = VanillaBonkUI
UI.Coop = { enabled = false, members = 1, ready = 0, total = 0 }
local coop = UI.Coop
local EDGE = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }

local function Surface(frame)
    frame:SetBackdrop(EDGE)
    frame:SetBackdropColor(0.045, 0.035, 0.025, 0.96)
    frame:SetBackdropBorderColor(0.72, 0.55, 0.28, 0.9)
end

local panel = CreateFrame("Frame", "VanillaBonkCoop", UIParent)
panel:SetWidth(204)
panel:SetHeight(54)
panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -172)
Surface(panel)
panel:Hide()
panel.title = UI.Text(panel, 12)
panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -11)
panel.title:SetTextColor(1, 0.82, 0.4)
panel.status = UI.Text(panel, 10)
panel.status:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -5)
panel.status:SetWidth(180)
panel.status:SetJustifyH("LEFT")
local roster = {}
local rosterPage = 0
local hidden = CreateFrame("Frame")
hidden:Hide()

local function UnitAt(index)
    if GetNumRaidMembers() > 0 then return "raid" .. index end
    if index == 1 then return "player" end
    return "party" .. (index - 1)
end

local function Refresh()
    if not coop.enabled then panel:Hide() return end
    panel:Show()
    local count = GetNumRaidMembers() > 0 and GetNumRaidMembers() or GetNumPartyMembers() + 1
    panel.title:SetText(count > 1 and ("EXPEDITION PARTY · " .. count) or "OPEN WORLD")
    if coop.total > 0 then
        panel.status:SetText(coop.ready .. "/" .. coop.total .. " ready · " .. coop.seconds .. "s")
    elseif coop.paused then panel.status:SetText("Paused · a hero is making a choice")
    else panel.status:SetText(count > 1 and (coop.members .. " heroes in the expedition") or "Friends can join at any time") end
    rosterPage = min(rosterPage, floor((count - 1) / 8))
    for i = 1, min(count - rosterPage * 8, 8) do
        local row = roster[i]
        if not row then
            row = CreateFrame("Button", nil, panel)
            row:SetWidth(180)
            row:SetHeight(26)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -48 - (i - 1) * 28)
            row.health = CreateFrame("StatusBar", nil, row)
            row.health:SetAllPoints(row)
            row.health:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
            row.health:SetMinMaxValues(0, 1)
            row.health:SetStatusBarColor(0.18, 0.4, 0.25, 0.8)
            row.name = UI.Text(row.health, 11)
            row.name:SetPoint("LEFT", row, "LEFT", 6, 0)
            row.name:SetWidth(120)
            row.name:SetJustifyH("LEFT")
            row.value = UI.Text(row.health, 10)
            row.value:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            row:SetScript("OnClick", function() if this.unit then TargetUnit(this.unit) end end)
            roster[i] = row
        end
        row.unit = UnitAt(i + rosterPage * 8)
        local hp, maximum = UnitHealth(row.unit) or 0, UnitHealthMax(row.unit) or 0
        local connected = UnitIsConnected(row.unit)
        row.name:SetText(UnitName(row.unit) or "Joining…")
        row.value:SetText(not connected and "Offline" or maximum > 0 and (floor(hp / maximum * 100) .. "%") or "—")
        row.health:SetValue(connected and maximum > 0 and hp / maximum or 0)
        row:SetAlpha(connected and 1 or 0.5)
        if count > 1 then row:Show() else row:Hide() end
    end
    for i = min(count - rosterPage * 8, 8) + 1, getn(roster) do roster[i]:Hide() end
    if count > 8 then panel.title:SetText("PARTY " .. count .. " - " .. (rosterPage + 1) .. "/" .. ceil(count / 8)) end
    panel:SetHeight(count > 1 and (54 + min(count, 8) * 28) or 54)
    for i = 1, 4 do
        local stock = getglobal("PartyMemberFrame" .. i)
        if stock and stock:GetParent() ~= hidden then stock:SetParent(hidden) end
    end
end

panel:EnableMouseWheel(true)
panel:SetScript("OnMouseWheel", function() rosterPage = max(0, rosterPage - arg1) Refresh() end)
panel:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Expedition party", 1, 0.82, 0.4)
    GameTooltip:AddLine("Scroll to see more heroes. Click a hero to target them.", 1, 1, 1, 1)
    GameTooltip:Show()
end)
panel:SetScript("OnLeave", function() GameTooltip:Hide() end)
panel.cancel = UI.Button(panel, 70, "Cancel", function() SendChatMessage(".bonk coop cancel", "SAY") end)
panel.cancel:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
panel.cancel:Hide()

local prompt = CreateFrame("Frame", "VanillaBonkMissionInvite", UIParent)
prompt:SetWidth(420)
prompt:SetHeight(174)
prompt:SetPoint("TOP", UIParent, "TOP", 0, -130)
prompt:SetFrameStrata("DIALOG")
prompt:EnableMouse(true)
Surface(prompt)
prompt:Hide()
tinsert(UISpecialFrames, "VanillaBonkMissionInvite")
prompt.heading = UI.Text(prompt, 20, UI.TITLE_FONT)
prompt.heading:SetPoint("TOP", prompt, "TOP", 0, -18)
prompt.heading:SetTextColor(1, 0.82, 0.35)
prompt.heading:SetText("Your party awaits")
prompt.detail = UI.Text(prompt, 13)
prompt.detail:SetPoint("TOP", prompt.heading, "BOTTOM", 0, -12)
prompt.detail:SetWidth(380)
prompt.note = UI.Text(prompt, 11)
prompt.note:SetPoint("TOP", prompt.detail, "BOTTOM", 0, -9)
prompt.note:SetTextColor(0.75, 0.72, 0.65)
prompt.note:SetText("Accept to travel together. No need to visit the Run Master.")
local function Answer(accept)
    if coop.token then
        coop.answeredToken = coop.token
        SendChatMessage(".bonk coop " .. (accept and "accept " or "decline ") .. coop.token, "SAY")
    end
    prompt:Hide()
end
prompt:SetScript("OnHide", function()
    if coop.token and coop.answeredToken ~= coop.token then
        coop.answeredToken = coop.token
        SendChatMessage(".bonk coop decline " .. coop.token, "SAY")
    end
end)
prompt.accept = UI.Button(prompt, 170, "Join expedition", function() Answer(true) end)
prompt.accept:SetPoint("BOTTOMRIGHT", prompt, "BOTTOM", -6, 17)
prompt.decline = UI.Button(prompt, 170, "Not now", function() Answer(false) end)
prompt.decline:SetPoint("BOTTOMLEFT", prompt, "BOTTOM", 6, 17)

local invitation = UI.Window("VanillaBonkInvitation", 460, 190)
invitation:SetPoint("CENTER", UIParent, "CENTER", 0, 35)
invitation.title:SetText("Invite friends")
invitation.header:SetWidth(340)
invitation.header:SetJustifyH("LEFT")
invitation.header:SetText("Share this invitation with the friends you want to welcome.")
invitation.edit = CreateFrame("EditBox", nil, invitation, "InputBoxTemplate")
invitation.edit:SetWidth(400)
invitation.edit:SetHeight(26)
invitation.edit:SetPoint("TOPLEFT", invitation, "TOPLEFT", 32, -82)
invitation.edit:SetAutoFocus(false)
invitation.edit:SetScript("OnEscapePressed", function() invitation:Hide() end)
invitation.edit:SetScript("OnEditFocusGained", function() this:HighlightText() end)
invitation.copy = UI.Button(invitation, 180, "Copy invitation", function()
    if HoACoop_CopyInvitation and HoACoop_CopyInvitation() then
        invitation.header:SetText("Copied! Send it to your friends. They can join whenever they are ready.")
    else
        invitation.header:SetText("Press Ctrl+C to copy the selected invitation.")
        invitation.edit:SetFocus()
        invitation.edit:HighlightText()
    end
end)
invitation.copy:SetPoint("BOTTOM", invitation, "BOTTOM", 0, 24)
function UI.CopyCoopInvitation()
    local code = HoACoop_GetInvitation and HoACoop_GetInvitation()
    if not code then
        UIErrorsFrame:AddMessage("Launch an open game from the launcher to invite friends.", 1, 0.8, 0.3)
        return
    end
    invitation.edit:SetText(code)
    invitation:Show()
    invitation.edit:HighlightText()
    invitation.copy:Click()
end

local party = UI.Window("VanillaBonkParty", 420, 480)
party:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
party.title:SetText("Players in this world")
party.header:SetWidth(300)
party.header:SetJustifyH("LEFT")
party.header:SetText("Invite heroes to your party, then choose an expedition.")
local lobbyRows, lobbyEntries, lobbyPage = {}, {}, 0
local function RefreshLobby()
    local count = getn(lobbyEntries)
    local maxPages = max(1, ceil(count / 9))
    lobbyPage = min(lobbyPage, maxPages - 1)
    party.header:SetText(count > 0 and (count .. " heroes - page " .. (lobbyPage + 1) .. "/" .. maxPages) or "No other heroes yet. Share your invitation to welcome friends.")
    if lobbyPage > 0 then party.previous:Enable() else party.previous:Disable() end
    if lobbyPage < maxPages - 1 then party.next:Enable() else party.next:Disable() end
    for i = 1, 9 do
        local row, f = lobbyRows[i], lobbyEntries[lobbyPage * 9 + i]
        if f and not row then
            row = CreateFrame("Frame", nil, party)
            row:SetWidth(358) row:SetHeight(30)
            row:SetPoint("TOPLEFT", party, "TOPLEFT", 30, -80 - (i - 1) * 32)
            row.name = UI.Text(row, 12)
            row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.name:SetWidth(236)
            row.name:SetJustifyH("LEFT")
            row.invite = UI.Button(row, 106, "Invite", function()
                if GetNumPartyMembers() >= 4 and GetNumRaidMembers() == 0 and IsPartyLeader() then ConvertToRaid() end
                InviteByName(this.hero)
                this:SetText("Invited")
            end)
            row.invite:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            lobbyRows[i] = row
        end
        if row then
            if f then
                row.name:SetText((f[2] or "") .. (f[4] == "1" and " |cffb7a384(in mission)|r" or ""))
                row.invite.hero = f[2]
                row.invite:SetText(f[5] == "1" and "In your party" or "Invite")
                if f[5] == "1" then row.invite:Disable() else row.invite:Enable() end
                row:Show()
            else row:Hide() end
        end
    end
end
party.previous = UI.Button(party, 70, "Previous", function() lobbyPage = max(0, lobbyPage - 1) RefreshLobby() end)
party.previous:SetPoint("BOTTOMLEFT", party, "BOTTOMLEFT", 30, 64)
party.next = UI.Button(party, 70, "Next", function() lobbyPage = lobbyPage + 1 RefreshLobby() end)
party.next:SetPoint("BOTTOMRIGHT", party, "BOTTOMRIGHT", -30, 64)
party.join = UI.Button(party, 174, "Join party expedition", function() party:Hide() coop.token = nil SendChatMessage(".bonk coop join", "SAY") end)
party.join:SetPoint("BOTTOM", party, "BOTTOM", 0, 64)
party.refresh = UI.Button(party, 160, "Refresh players", function() SendChatMessage(".bonk coop lobby", "SAY") end)
party.refresh:SetPoint("BOTTOM", party, "BOTTOM", 0, 24)
function UI.OpenCoopParty()
    party:Show()
    SendChatMessage(".bonk coop lobby", "SAY")
end

local timer = 0
panel:SetScript("OnUpdate", function()
    timer = timer + arg1
    if timer >= 0.25 then timer = 0 Refresh() end
end)
UI.Listen({
    coop = function(f)
        coop.enabled = true
        coop.members, coop.ready, coop.total = tonumber(f[2]) or 1, tonumber(f[3]) or 0, tonumber(f[4]) or 0
        coop.paused, coop.seconds = f[5] == "1", tonumber(f[6]) or 0
        Refresh()
        if coop.total > 0 then panel.cancel:Show() else panel.cancel:Hide() end
    end,
    coopprompt = function(f)
        local token = tonumber(f[2]) or 0
        if token == 0 then coop.token = nil prompt:Hide() return end
        if coop.token == token then return end
        coop.token = token
        prompt.detail:SetText((f[3] or "Your party") .. " invites you · " .. (f[4] or "") .. "\n" .. (f[5] or ""))
        prompt.accept:SetText(f[6] == "join" and "Join in progress" or "Ready to depart")
        prompt:Show()
        PlaySound("igQuestLogOpen")
    end,
    cooplobbyclear = function()
        lobbyEntries = {}
        lobbyPage = 0
        RefreshLobby()
    end,
    cooplobby = function(f)
        tinsert(lobbyEntries, f)
        RefreshLobby()
    end,
})

local rescue = CreateFrame("Frame", "VanillaBonkRescue", UIParent)
rescue:SetWidth(360)
rescue:SetHeight(80)
rescue:SetPoint("TOP", UIParent, "TOP", 0, -130)
Surface(rescue)
rescue:Hide()
rescue.title = UI.Text(rescue, 14)
rescue.title:SetPoint("TOP", rescue, "TOP", 0, -12)
rescue.title:SetTextColor(1, 0.82, 0.4)
rescue.help = UI.Text(rescue, 11)
rescue.help:SetPoint("TOP", rescue.title, "BOTTOM", 0, -7)
rescue.bar = CreateFrame("StatusBar", nil, rescue)
rescue.bar:SetWidth(330)
rescue.bar:SetHeight(12)
rescue.bar:SetPoint("BOTTOM", rescue, "BOTTOM", 0, 12)
rescue.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
rescue.bar:SetStatusBarColor(0.35, 0.8, 0.55)
rescue.bar:SetMinMaxValues(0, 1)
local fallen = {}
local function RefreshRescue()
    local selected
    for name, entry in pairs(fallen) do
        if not selected or entry.self or (not selected.self and name < selected.name) then selected = entry end
    end
    if not selected then rescue:Hide() return end
    rescue.title:SetText(selected.self and "Your allies can revive you" or ("Revive " .. selected.name))
    rescue.help:SetText("Stay within the circle for 6 seconds")
    rescue.bar:SetValue(min(1, selected.progress / selected.total))
    rescue:Show()
end
UI.Listen({
    rescue = function(f)
        local name, total, own = f[2], tonumber(f[4]) or 0, f[5] == "1"
        if total == 0 then fallen[name] = nil
        else fallen[name] = { name = name, total = total, progress = tonumber(f[3]) or 0, self = own } end
        if own then
            UI.CooperativeDeath = total > 0
            if UI.CooperativeDeath and StaticPopup_Hide then StaticPopup_Hide("DEATH") end
        end
        RefreshRescue()
    end,
    ["end"] = function() fallen = {} UI.CooperativeDeath = false rescue:Hide() end,
    start = function() fallen = {} UI.CooperativeDeath = false rescue:Hide() end,
})
