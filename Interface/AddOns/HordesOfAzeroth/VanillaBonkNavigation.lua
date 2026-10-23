local UI = VanillaBonkUI
local nav = CreateFrame("Frame", "VanillaBonkNavigation", UIParent)
nav:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -18, -16)
nav:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
nav:SetBackdropColor(0.045, 0.035, 0.025, 0.95)
nav:SetBackdropBorderColor(0.72, 0.55, 0.28, 0.95)
nav.zone = UI.Text(nav, 12)
nav.zone:SetPoint("TOPLEFT", nav, "TOPLEFT", 13, -13)
nav.zone:SetJustifyH("LEFT")
nav.zone:SetTextColor(1, 0.82, 0.4)
nav.map = UI.Button(nav, 116, "World map", function() ToggleWorldMap() end)
nav.map:SetPoint("BOTTOMLEFT", nav, "BOTTOMLEFT", 10, 10)
nav.plus = UI.Button(nav, 26, "+", function() Minimap:SetZoom(min(Minimap:GetZoomLevels() - 1, Minimap:GetZoom() + 1)) end)
nav.plus:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT", -10, 10)
nav.minus = UI.Button(nav, 26, "-", function() Minimap:SetZoom(max(0, Minimap:GetZoom() - 1)) end)
nav.minus:SetPoint("RIGHT", nav.plus, "LEFT", -4, 0)

local function Layout()
    local size = min(248, max(224, floor(UIParent:GetHeight() * 0.28)))
    nav:SetWidth(size + 20)
    nav:SetHeight(size + 78)
    nav.zone:SetWidth(size - 8)
    nav.zone:SetText(GetMinimapZoneText() or GetZoneText() or "Azeroth")
    Minimap:SetParent(nav)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("TOPLEFT", nav, "TOPLEFT", 10, -35)
    Minimap:SetWidth(size)
    Minimap:SetHeight(size)
    Minimap:SetMaskTexture("Interface\\Buttons\\WHITE8X8")
    Minimap:EnableMouseWheel(true)
    Minimap:SetScript("OnMouseWheel", function() Minimap:SetZoom(min(Minimap:GetZoomLevels() - 1, max(0, Minimap:GetZoom() + arg1))) end)
    Minimap:Show()
    for _, name in ipairs({ "MinimapBorder", "MinimapBorderTop", "MinimapBackdrop", "MinimapToggleButton", "MinimapZoneTextButton", "MinimapZoomIn", "MinimapZoomOut", "MiniMapWorldMapButton", "GameTimeFrame" }) do
        local frame = getglobal(name)
        if frame then frame:Hide() end
    end
    if MinimapCluster then MinimapCluster:Hide() end
    if MiniMapMailFrame then
        MiniMapMailFrame:SetParent(nav)
        MiniMapMailFrame:ClearAllPoints()
        MiniMapMailFrame:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -5, -5)
    end
    if VanillaBonkRewards then
        VanillaBonkRewards:ClearAllPoints()
        VanillaBonkRewards:SetPoint("TOPRIGHT", nav, "BOTTOMRIGHT", 0, -8)
        VanillaBonkRewards:SetWidth(size + 20)
    end
end
UI.NavigationSquare = true
nav:RegisterEvent("PLAYER_ENTERING_WORLD")
nav:RegisterEvent("ZONE_CHANGED")
nav:RegisterEvent("ZONE_CHANGED_INDOORS")
nav:RegisterEvent("ZONE_CHANGED_NEW_AREA")
nav:RegisterEvent("DISPLAY_SIZE_CHANGED")
nav:SetScript("OnEvent", Layout)
Layout()
