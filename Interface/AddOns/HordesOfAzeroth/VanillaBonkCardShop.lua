local UI = VanillaBonkUI

local ROW_HEIGHT = 46
local ROW_GAP = 6
local BUTTON_WIDTH = 70
local SCROLLBAR_WIDTH = 30
local BUSY_SECONDS = 3
local PANE_ART = "Interface\\TalentFrame\\MageArcane"

local CardShop = {}
VanillaBonkCardShop = CardShop

local holder
local busySince
local tickets = 0
local shownKind = "c"

local KINDS = {
    c = {
        entries = function() return VanillaBonkCodex.Cards() end,
        tooltip = function(owner, entry) VanillaBonkCodex.ShowCardTooltip(owner, entry) end,
        waiting = "Sayge is shuffling the deck...",
        done = "You have unlocked every Darkmoon Card Sayge has.",
    },
    g = {
        entries = function() return VanillaBonkCodex.Glyphs() end,
        tooltip = function(owner, entry) VanillaBonkCodex.ShowGlyphTooltip(owner, entry) end,
        waiting = "Sayge is reading the stars...",
        done = "You have unlocked every Glyph Sayge has.",
    },
}

local function Rarity(card)
    return UI.RARITY[card.rarity] or UI.RARITY[0]
end

local function CopiesText(card)
    if card.maxCopies == 1 then
        return "1 copy per run"
    end
    return "up to " .. card.maxCopies .. " copies per run"
end

local function Detail(entry, rarity)
    if entry.kind == "g" then
        return rarity.name .. " Glyph" .. (entry.drawback and entry.drawback ~= "" and " with a |cffff4a3adrawback|r" or "")
    end
    return rarity.name .. " Darkmoon Card, " .. CopiesText(entry)
end

local function EntriesToUnlock()
    local list = {}
    for _, entry in pairs(KINDS[shownKind].entries() or {}) do
        if entry.forSale then
            tinsert(list, entry)
        end
    end
    table.sort(list, function(a, b)
        if a.rarity ~= b.rarity then
            return a.rarity < b.rarity
        end
        return a.name < b.name
    end)
    return list
end

local function Unlock(card)
    if busySince or not card or not card.forSale or tickets < card.price then
        return
    end
    busySince = GetTime()
    PlaySound("LOOTWINDOWCOINSOUND")
    VanillaBonkUI.Command("unlock " .. card.kind .. " " .. card.id)
    CardShop.Refresh()
end

local function ShowRowTooltip(owner, row)
    row:SetBackdropBorderColor(1, 0.82, 0, 1)
    KINDS[row.card.kind or shownKind].tooltip(owner, row.card)
end

local function HideRowTooltip(row)
    row:SetBackdropBorderColor(0.55, 0.42, 0.1, 1)
    GameTooltip:Hide()
end

local function CreateRow(index)
    local row = CreateFrame("Button", nil, holder.list)
    row:SetHeight(ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = UI.FLAT, edgeFile = UI.FLAT, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    row:SetBackdropColor(0.08, 0.06, 0.01, 0.78)
    row:SetBackdropBorderColor(0.55, 0.42, 0.1, 1)
    row:SetScript("OnEnter", function() ShowRowTooltip(this, this) end)
    row:SetScript("OnLeave", function() HideRowTooltip(this) end)

    row.slot = UI.Slot(row, 34, "Frame")
    row.slot:SetPoint("LEFT", row, "LEFT", 7, 0)

    row.name = UI.Text(row, 13)
    row.name:SetPoint("TOPLEFT", row.slot, "TOPRIGHT", 9, -2)
    row.name:SetJustifyH("LEFT")

    row.detail = UI.Text(row, 10)
    row.detail:SetPoint("BOTTOMLEFT", row.slot, "BOTTOMRIGHT", 9, 2)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetTextColor(0.75, 0.75, 0.75)

    row.unlock = UI.Button(row, BUTTON_WIDTH, "Unlock", function()
        Unlock(this:GetParent().card)
    end)
    row.unlock:SetPoint("RIGHT", row, "RIGHT", -8, -8)
    row.unlock:SetScript("OnEnter", function() ShowRowTooltip(this, this:GetParent()) end)
    row.unlock:SetScript("OnLeave", function() HideRowTooltip(this:GetParent()) end)

    row.price = UI.Text(row, 11)
    row.price:SetPoint("BOTTOMRIGHT", row.unlock, "TOPRIGHT", 0, 3)
    row.price:SetJustifyH("RIGHT")

    holder.rows[index] = row
    return row
end

local function FillRow(row, card, index, width)
    local rarity = Rarity(card)
    row.card = card
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", holder.list, "TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
    row:SetWidth(width)
    row.slot.icon:SetTexture(UI.ICON_PATH .. (card.icon ~= "" and card.icon or "INV_Misc_QuestionMark"))
    row.name:SetWidth(width - 60 - BUTTON_WIDTH)
    row.name:SetText(card.name)
    row.name:SetTextColor(rarity.r, rarity.g, rarity.b)
    row.detail:SetWidth(width - 60 - BUTTON_WIDTH)
    row.detail:SetText(Detail(card, rarity))

    local affordable = tickets >= card.price
    row.price:SetText(card.price .. (card.price == 1 and " Darkmoon Ticket" or " Darkmoon Tickets"))
    if affordable then
        row.price:SetTextColor(1, 1, 1)
    else
        row.price:SetTextColor(1, 0.3, 0.3)
    end
    if affordable and not busySince then
        row.unlock:Enable()
    else
        row.unlock:Disable()
    end
    if GetMouseFocus() == row or GetMouseFocus() == row.unlock then
        ShowRowTooltip(GetMouseFocus(), row)
    end
    row:Show()
end

local function CreateHolder(owner)
    holder = CreateFrame("Frame", nil, owner)
    holder:SetFrameLevel(owner:GetFrameLevel() + 1)
    holder.rows = {}

    holder.pane = UI.Pane(holder, 0, 0, 100, 100, PANE_ART, 0.7)

    holder.scroll = CreateFrame("ScrollFrame", "VanillaBonkCardShopScroll", holder, "UIPanelScrollFrameTemplate")
    holder.scroll:SetPoint("TOPLEFT", holder, "TOPLEFT", 8, -8)
    holder.scroll:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -SCROLLBAR_WIDTH, 8)
    holder.scroll:SetFrameLevel(holder.pane:GetFrameLevel() + 2)

    holder.list = CreateFrame("Frame", nil, holder.scroll)
    holder.list:SetWidth(100)
    holder.list:SetHeight(100)
    holder.scroll:SetScrollChild(holder.list)

    holder.empty = UI.Text(holder.list, 12)
    holder.empty:SetPoint("TOP", holder.list, "TOP", 0, -40)
    holder.empty:SetTextColor(0.6, 0.6, 0.6)

    holder:SetScript("OnUpdate", function()
        if busySince and GetTime() - busySince > BUSY_SECONDS then
            busySince = nil
            CardShop.Refresh()
        end
    end)
end

function CardShop.SetTickets(count)
    tickets = count or 0
end

function CardShop.Refresh()
    if not holder or not holder:IsShown() then
        return
    end
    local width = holder:GetWidth() - 8 - SCROLLBAR_WIDTH
    local height = holder:GetHeight() - 16
    holder.list:SetWidth(width)

    local cards = EntriesToUnlock()
    for index, card in ipairs(cards) do
        FillRow(holder.rows[index] or CreateRow(index), card, index, width)
    end
    for index = table.getn(cards) + 1, table.getn(holder.rows) do
        holder.rows[index]:Hide()
    end

    if not KINDS[shownKind].entries() then
        holder.empty:SetText(KINDS[shownKind].waiting)
    elseif table.getn(cards) == 0 then
        holder.empty:SetText(KINDS[shownKind].done)
    else
        holder.empty:SetText("")
    end

    holder.list:SetHeight(max(height, table.getn(cards) * (ROW_HEIGHT + ROW_GAP)))
    holder.scroll:UpdateScrollChildRect()
    holder.scroll:SetVerticalScroll(min(holder.scroll:GetVerticalScroll(), holder.scroll:GetVerticalScrollRange()))
end

function CardShop.Show(owner, left, top, width, height, kind)
    shownKind = KINDS[kind] and kind or "c"
    if not holder then
        CreateHolder(owner)
    end
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", owner, "TOPLEFT", left, -top)
    holder:SetWidth(width)
    holder:SetHeight(height)
    holder.pane:SetWidth(width)
    holder.pane:SetHeight(height)
    UI.SetPaneArt(holder.pane, PANE_ART)
    holder:Show()
    CardShop.Refresh()
end

function CardShop.Hide()
    if holder then
        holder:Hide()
    end
end

VanillaBonkCodex.onBook = function()
    busySince = nil
    CardShop.Refresh()
end
