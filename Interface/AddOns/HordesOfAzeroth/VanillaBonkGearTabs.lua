local UI = VanillaBonkUI

local TABS_LEFT, TABS_TOP = 70, -40

local gear = { current = nil, tabs = {} }
local buttons = {}
local RefreshTabs

local function Command(text)
    VanillaBonkUI.Command("gear " .. text)
end

local function TabButton(index)
    if buttons[index] then
        return buttons[index]
    end
    local tab = CreateFrame("Button", "VanillaBonkGearTab" .. index, MerchantFrame, "TabButtonTemplate")
    tab:SetScript("OnClick", function()
        if this.group == gear.current then
            return
        end
        PlaySound("igCharacterInfoTab")
        gear.current = this.group
        MerchantFrame.page = 1
        Command("tab " .. this.group)
        RefreshTabs()
    end)
    buttons[index] = tab
    return tab
end

RefreshTabs = function()
    for _, tab in ipairs(buttons) do
        tab:Hide()
    end
    if not MerchantFrame:IsShown() or MerchantFrame.selectedTab ~= 1 or table.getn(gear.tabs) < 2 then
        return
    end
    local previous
    for index, entry in ipairs(gear.tabs) do
        local tab = TabButton(index)
        tab.group = entry.group
        tab:SetText(entry.name)
        PanelTemplates_TabResize(0, tab)
        tab:ClearAllPoints()
        if previous then
            tab:SetPoint("LEFT", previous, "RIGHT", 0, 0)
        else
            tab:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", TABS_LEFT, TABS_TOP)
        end
        if entry.group == gear.current then
            PanelTemplates_SelectTab(tab)
        else
            PanelTemplates_DeselectTab(tab)
        end
        tab:Show()
        previous = tab
    end
end

local MERCHANT_SLOTS = 10
local SLOT_SIZE = 37

local function QualityColor(link)
    if not link then
        return nil
    end
    local _, _, hex = strfind(link, "|c%x%x(%x%x%x%x%x%x)")
    if not hex or hex == "ffffff" or hex == "9d9d9d" then
        return nil
    end
    return tonumber(strsub(hex, 1, 2), 16) / 255, tonumber(strsub(hex, 3, 4), 16) / 255, tonumber(strsub(hex, 5, 6), 16) / 255
end

local function QualityBorder(button)
    if not button.quality then
        button.quality = button:CreateTexture(nil, "OVERLAY")
        button.quality:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        button.quality:SetBlendMode("ADD")
        button.quality:SetWidth(SLOT_SIZE * 64 / 37)
        button.quality:SetHeight(SLOT_SIZE * 64 / 37)
        button.quality:SetPoint("CENTER", button, "CENTER", 0, 0)
    end
    return button.quality
end

local function RefreshQualities()
    for index = 1, MERCHANT_SLOTS do
        local button = getglobal("MerchantItem" .. index .. "ItemButton")
        local name = getglobal("MerchantItem" .. index .. "Name")
        if button then
            local link
            if button:IsShown() then
                if MerchantFrame.selectedTab == 1 then
                    link = GetMerchantItemLink(button:GetID())
                elseif GetBuybackItemLink then
                    link = GetBuybackItemLink(button:GetID())
                end
            end
            local r, g, b = QualityColor(link)
            local border = QualityBorder(button)
            if r then
                border:SetVertexColor(r, g, b)
                border:Show()
                if name then
                    name:SetTextColor(r, g, b)
                end
            else
                border:Hide()
                if name then
                    name:SetTextColor(1, 1, 1)
                end
            end
        end
    end
end

local BaseMerchantUpdate = MerchantFrame_Update
function MerchantFrame_Update()
    BaseMerchantUpdate()
    RefreshTabs()
    RefreshQualities()
end

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("PLAYER_MONEY")
local lastMoney = GetMoney()
events:SetScript("OnEvent", function()
    if event == "PLAYER_MONEY" then
        local money = GetMoney()
        if money > lastMoney and MerchantFrame:IsShown() then
            PlaySound("LOOTWINDOWCOINSOUND")
        end
        lastMoney = money
        return
    end
    lastMoney = GetMoney()
    if event == "MERCHANT_SHOW" then
        if not gear.fresh then
            gear.current = nil
            gear.tabs = {}
        end
        gear.fresh = nil
    end
    RefreshTabs()
end)

local handlers = {}

handlers["geartabs"] = function(f)
    gear.fresh = true
    gear.current = f[2]
    gear.tabs = {}
    local index = 3
    while f[index] and f[index + 1] do
        tinsert(gear.tabs, { group = f[index], name = f[index + 1] })
        index = index + 2
    end
    RefreshTabs()
end

UI.Listen(handlers)
