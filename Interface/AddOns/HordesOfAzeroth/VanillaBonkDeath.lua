local REVIVE_WAIT = 10

local watcher = CreateFrame("Frame")
watcher:Hide()

local function CanRelease()
    if VanillaBonkUI and VanillaBonkUI.CooperativeDeath then return false end
    local remaining = GetReleaseTimeRemaining()
    return remaining > 0 or remaining == -1
end

watcher:SetScript("OnUpdate", function()
    this.waited = this.waited + arg1
    if this.waited < REVIVE_WAIT then
        return
    end
    this:Hide()
    if UnitIsDead("player") and not UnitIsGhost("player") and CanRelease() and not StaticPopup_Visible("DEATH") then
        StaticPopup_Show("DEATH")
    end
end)

UIParent:UnregisterEvent("PLAYER_DEAD")

watcher:RegisterEvent("PLAYER_DEAD")
watcher:RegisterEvent("PLAYER_ALIVE")
watcher:RegisterEvent("PLAYER_UNGHOST")
watcher:SetScript("OnEvent", function()
    if event == "PLAYER_DEAD" then
        this.waited = 0
        this:Show()
    else
        this:Hide()
    end
end)
