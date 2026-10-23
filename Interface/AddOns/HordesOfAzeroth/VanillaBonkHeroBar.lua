local UI = VanillaBonkUI

local SPELL_SLOTS = 5
local PASSIVE_SLOTS = 6
local SCALE = 10 / 9
local BAR_ART = "Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf"
local PET_ART = "Interface\\PetActionBar\\UI-PetBar"
local END_CAP = "Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Human"
local XP_WIDTH = 500

local run = { spells = {}, passives = {}, info = {}, stats = {} }
local inRun = false

local root = CreateFrame("Frame", "VanillaBonkHeroBar", UIParent)
root:SetWidth(1)
root:SetHeight(1)
root:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)

local runFrame = CreateFrame("Frame", nil, root)
runFrame:SetAllPoints(root)
local campFrame = CreateFrame("Frame", nil, root)
campFrame:SetAllPoints(root)

local function EndCap(parent, size, x, mirrored)
    if not parent.endCaps then
        parent.endCaps = CreateFrame("Frame", nil, parent)
        parent.endCaps:SetAllPoints(parent)
        parent.endCaps:SetFrameLevel(parent:GetFrameLevel() + 8)
    end
    local texture = parent.endCaps:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(END_CAP)
    texture:SetWidth(size)
    texture:SetHeight(size)
    texture:SetPoint("BOTTOMLEFT", root, "BOTTOM", x, 0)
    if mirrored then
        texture:SetTexCoord(1, 0, 0, 1)
    end
    return texture
end

local spellBar = CreateFrame("Frame", nil, runFrame)
spellBar:SetWidth(220 * SCALE)
spellBar:SetHeight(43 * SCALE)
spellBar:SetPoint("BOTTOM", root, "BOTTOM", 0, 0)
do
    local main = spellBar:CreateTexture(nil, "BACKGROUND")
    main:SetTexture(BAR_ART)
    main:SetTexCoord(0, 212 / 256, 213 / 256, 1)
    main:SetWidth(212 * SCALE)
    main:SetHeight(43 * SCALE)
    main:SetPoint("BOTTOMLEFT", spellBar, "BOTTOMLEFT", 0, 0)
    local cap = spellBar:CreateTexture(nil, "BACKGROUND")
    cap:SetTexture(BAR_ART)
    cap:SetTexCoord(8 / 256, 0, 213 / 256, 1)
    cap:SetWidth(8 * SCALE)
    cap:SetHeight(43 * SCALE)
    cap:SetPoint("BOTTOMLEFT", main, "BOTTOMRIGHT", 0, 0)
end

local wings = {}
for side = 1, 2 do
    local wing = spellBar:CreateTexture(nil, "BACKGROUND")
    wing:SetTexture(PET_ART)
    if side == 1 then
        wing:SetTexCoord(0, 146 / 256, 2 / 128, 46 / 128)
        wing:SetPoint("BOTTOMRIGHT", spellBar, "BOTTOMLEFT", 0, 0)
    else
        wing:SetTexCoord(146 / 256, 0, 2 / 128, 46 / 128)
        wing:SetPoint("BOTTOMLEFT", spellBar, "BOTTOMRIGHT", 0, 0)
    end
    wing:SetWidth(146)
    wing:SetHeight(44)
    wings[side] = wing
end

local halfBar = 110 * SCALE
EndCap(runFrame, 128, -halfBar - 146 - 88)
EndCap(runFrame, 128, halfBar + 146 - 40, true)

local xpRim = UI.CastRim(runFrame, XP_WIDTH)
xpRim:SetPoint("BOTTOM", root, "BOTTOM", 0, 48)
local xpBar = CreateFrame("StatusBar", nil, xpRim.opening)
xpBar:SetAllPoints(xpRim.opening)
xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
xpBar:SetStatusBarColor(0.58, 0.0, 0.55)
xpBar:SetMinMaxValues(0, 1)
xpBar:SetFrameLevel(xpRim.opening:GetFrameLevel() + 1)
xpRim.text = UI.Text(xpRim.art, 10, UI.NUMBER_FONT, "OUTLINE")
xpRim.text:SetPoint("CENTER", xpRim.opening, "CENTER", 0, 1)
for tick = 1, 19 do
    local line = xpBar:CreateTexture(nil, "OVERLAY")
    line:SetTexture(UI.FLAT)
    line:SetVertexColor(0, 0, 0, 0.55)
    line:SetWidth(1)
    line:SetPoint("TOP", xpBar, "TOPLEFT", (XP_WIDTH - 70) * tick / 20, 0)
    line:SetPoint("BOTTOM", xpBar, "BOTTOMLEFT", (XP_WIDTH - 70) * tick / 20, 0)
end

local levelRing = UI.Ring(runFrame, 52)
levelRing:SetPoint("BOTTOM", root, "BOTTOM", 0, 66)
VanillaBonkLevelRing = levelRing
levelRing:SetFrameLevel(xpRim:GetFrameLevel() + 6)
levelRing.art = UI.RingArt(levelRing, UI.ICON_PATH .. "Spell_Shadow_Teleport")
levelRing.art:SetVertexColor(0.45, 0.45, 0.5)
levelRing.text = UI.Text(levelRing, 18)
levelRing.text:SetPoint("CENTER", levelRing, "CENTER", 0, 1)
levelRing.text:SetTextColor(1, 0.82, 0)

local spellSlots, passiveSlots = {}, {}

local LOCKED_SLOTS = {
    spell = { talent = "Spell Slot", start = 3, ranks = {
        { quest = "Renowned", quests = 25 }, { quests = 45 },
    } },
    passive = { talent = "Passive Slot", start = 3, ranks = {
        { quest = "Trusted Adventurer", quests = 15 }, { quests = 35 }, { quests = 55 },
    } },
}

local function AddEntryLines(entry, stat)
    local info = run.info[entry.index] or {}
    local name = info.name or "?"
    if entry.kind == "p" then
        GameTooltip:AddDoubleLine(name, "Rank " .. entry.rank .. " / " .. entry.max, 1, 1, 1, 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Passive", 0.6, 0.6, 0.6)
        if info.description and info.description ~= "" then
            GameTooltip:AddLine(info.description, 1, 0.82, 0, 1)
        end
        return
    end

    local r, g, b = 1, 1, 1
    if entry.kind == "e" then
        r, g, b = 1, 0.5, 0
    end
    GameTooltip:AddDoubleLine(name, "Rank " .. entry.rank, r, g, b, 0.6, 0.6, 0.6)
    if info.evolvedFrom and info.evolvedFrom ~= "" then
        GameTooltip:AddLine("Legendary, evolved from " .. info.evolvedFrom, 1, 0.5, 0)
    end
    if info.line and info.line ~= "" then
        GameTooltip:AddLine(info.line, 1, 1, 1, 1)
    end
    if info.damage and info.damage ~= "" then
        GameTooltip:AddLine(info.damage, 1, 1, 1, 1)
    end
    if info.description and info.description ~= "" then
        GameTooltip:AddLine(info.description, 1, 0.82, 0, 1)
    end

    if info.ranks and info.ranks ~= "" then
        local counts = {}
        for index = 1, strlen(info.ranks) do
            local rarity = tonumber(strsub(info.ranks, index, index)) or 0
            counts[rarity] = (counts[rarity] or 0) + 1
        end
        local text = ""
        for rarity = 0, 4 do
            if counts[rarity] then
                text = text .. (text ~= "" and ", " or "") .. UI.RarityText(rarity, counts[rarity] .. " " .. UI.RARITY[rarity].name)
            end
        end
        GameTooltip:AddLine("Ranks: " .. text, 0.6, 0.6, 0.6, 1)
    end

    if stat and stat.damage > 0 then
        local total = 0
        for _, other in pairs(run.stats) do
            total = total + other.damage
        end
        local share = total > 0 and floor(stat.damage / total * 100 + 0.5) or 0
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(VanillaBonkUI.Short(stat.damage) .. " damage", share .. "% of total, " .. stat.kills .. " kills", 1, 1, 1, 0.6, 0.6, 0.6)
    end
end

local function ShowSlotTooltip()
    local slot = this
    GameTooltip:SetOwner(slot, "ANCHOR_TOP")
    local entry = slot.entry
    if slot.locked then
        local kind = slot.isSpell and "spell" or "passive"
        local unlock = LOCKED_SLOTS[kind]
        local rank = max(1, slot.slotIndex - unlock.start)
        local need = unlock.ranks[rank] or unlock.ranks[getn(unlock.ranks)]
        GameTooltip:AddLine("Locked " .. kind .. " slot", 1, 1, 1)
        if rank == 1 then
            GameTooltip:AddLine("Buy " .. unlock.talent .. " from Sayge at the Inn to unlock it.", 1, 0.82, 0, 1)
            GameTooltip:AddLine("Sayge sells it once you finish the quest \"" .. need.quest .. "\" (complete " ..
                need.quests .. " quests).", 0.6, 0.6, 0.6, 1)
        else
            GameTooltip:AddLine("Buy rank " .. rank .. " of " .. unlock.talent .. " from Sayge at the Inn to unlock it.", 1, 0.82, 0, 1)
            GameTooltip:AddLine("Sayge sells rank " .. rank .. " once you have completed " .. need.quests .. " quests.", 0.6, 0.6, 0.6, 1)
        end
        GameTooltip:Show()
        return
    end
    if not entry then
        if slot.isSpell then
            GameTooltip:AddLine("Empty spell slot", 1, 1, 1)
            GameTooltip:AddLine("Level-ups can offer a new spell while a slot is free.", 1, 0.82, 0, 1)
            GameTooltip:AddLine("Up to " .. SPELL_SLOTS .. " spells per run.", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("Empty passive slot", 1, 1, 1)
            GameTooltip:AddLine("Up to " .. PASSIVE_SLOTS .. " passives per run.", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
        return
    end

    AddEntryLines(entry, run.stats[slot.spellIndex])
    GameTooltip:Show()
end

local function ShowEntryTooltip(owner, entry)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    AddEntryLines(entry)
    GameTooltip:Show()
end

function VanillaBonk_LoadoutTooltip(owner, name)
    for _, entry in ipairs(run.spells) do
        local info = run.info[entry.index]
        if info and info.name == name then
            ShowEntryTooltip(owner, entry)
            return true
        end
    end
    return false
end

function VanillaBonk_SpellTooltip(owner, index)
    local entry = run.spells[index]
    if not entry then
        return false
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    AddEntryLines(entry, run.stats[index])
    GameTooltip:Show()
    return true
end

function VanillaBonk_PassiveTooltip(owner, index)
    local entry = run.passives[index]
    if not entry then
        return false
    end
    ShowEntryTooltip(owner, entry)
    return true
end

function VanillaBonkUI.Short(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return format("%.2fm", value / 1000000)
    elseif value >= 10000 then
        return format("%.1fk", value / 1000)
    end
    return tostring(floor(value))
end

local function CreateSlot(parent, size, isSpell)
    local slot = CreateFrame("Button", nil, parent)
    slot:SetWidth(size)
    slot:SetHeight(size)
    slot.isSpell = isSpell
    slot.icon = slot:CreateTexture(nil, "ARTWORK")
    slot.icon:SetAllPoints(slot)

    local top = CreateFrame("Frame", nil, slot)
    top:SetAllPoints(slot)
    top:SetFrameLevel(slot:GetFrameLevel() + 3)

    slot.shade = slot:CreateTexture(nil, "ARTWORK")
    slot.shade:SetTexture(UI.FLAT)
    slot.shade:SetVertexColor(0, 0, 0, 0.6)
    slot.shade:SetAllPoints(slot)
    slot.shade:Hide()
    slot.lock = top:CreateTexture(nil, "OVERLAY")
    slot.lock:SetTexture("Interface\\ChatFrame\\UI-ChatFrame-LockIcon")
    slot.lock:SetWidth(isSpell and 20 or 17)
    slot.lock:SetHeight(isSpell and 20 or 17)
    slot.lock:SetPoint("CENTER", slot, "CENTER", 0, 0)
    slot.lock:Hide()

    if isSpell then
        slot.cooldown = CreateFrame("Model", nil, slot, "CooldownFrameTemplate")
        slot.cooldown:ClearAllPoints()
        slot.cooldown:SetWidth(size)
        slot.cooldown:SetHeight(size)
        slot.cooldown:SetPoint("CENTER", slot, "CENTER", 0, -1)
        slot.glow = top:CreateTexture(nil, "OVERLAY")
        slot.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        slot.glow:SetBlendMode("ADD")
        slot.glow:SetWidth(size * 62 / 36)
        slot.glow:SetHeight(size * 62 / 36)
        slot.glow:SetPoint("CENTER", slot, "CENTER", 0, 0)
        slot.ready = top:CreateTexture(nil, "OVERLAY")
        slot.ready:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
        slot.ready:SetWidth(size * 64 / 40)
        slot.ready:SetHeight(size * 64 / 40)
        slot.ready:SetPoint("CENTER", slot, "CENTER", 0, 0)
    end

    slot.highlight = slot:CreateTexture(nil, "HIGHLIGHT")
    slot.highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    slot.highlight:SetBlendMode("ADD")
    slot.highlight:SetAllPoints(slot)

    slot.rank = UI.Text(top, isSpell and 15 or 12, UI.NUMBER_FONT, "OUTLINE")
    slot.rank:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -1, 2)

    slot:SetScript("OnEnter", ShowSlotTooltip)
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return slot
end

for index = 1, SPELL_SLOTS do
    local slot = CreateSlot(spellBar, 40, true)
    slot:SetPoint("TOPLEFT", spellBar, "TOPLEFT", (8 + (index - 1) * 42) * SCALE, -3 * SCALE)
    spellSlots[index] = slot
end
for index = 1, PASSIVE_SLOTS do
    local slot = CreateSlot(spellBar, 30, false)
    if index <= 3 then
        slot:SetPoint("TOPLEFT", wings[1], "TOPLEFT", 36 + (index - 1) * 38, -12)
    else
        slot:SetPoint("TOPLEFT", wings[2], "TOPLEFT", 80 - (6 - index) * 38, -12)
    end
    passiveSlots[index] = slot
end

local function RestartCooldown(slot)
    local info = slot.entry and run.info[slot.entry.index]
    if not info or not info.interval or info.interval <= 0 or info.held then
        slot.cooldown:Hide()
        slot.cycleStart = nil
        return
    end
    local interval = info.interval / 1000
    if not slot.cycleStart then
        slot.cycleStart = GetTime() - max(0, interval - (info.nextCast or 0) / 1000)
    end
    while GetTime() - slot.cycleStart >= interval do
        slot.cycleStart = slot.cycleStart + interval
    end
    CooldownFrame_SetTimer(slot.cooldown, slot.cycleStart, interval, 1)
end

local function UpdateSlot(slot, entry)
    slot.entry = entry
    if not entry then
        slot.icon:Hide()
        slot.rank:SetText("")
        if slot.glow then
            slot.glow:Hide()
            slot.ready:Hide()
            slot.cooldown:Hide()
        end
        return
    end
    slot.icon:SetTexture(UI.ICON_PATH .. entry.icon)
    slot.icon:Show()
    slot.rank:SetText(entry.rank)
    if not slot.glow then
        slot.rank:SetTextColor(1, 1, 1)
        return
    end

    local info = run.info[entry.index] or {}
    local best = 0
    if entry.kind == "e" then
        best = 4
    elseif info.ranks then
        for index = 1, strlen(info.ranks) do
            best = max(best, tonumber(strsub(info.ranks, index, index)) or 0)
        end
    end
    if best > 0 then
        local color = UI.RARITY[best]
        slot.glow:SetVertexColor(color.r, color.g, color.b)
        slot.glow:Show()
    else
        slot.glow:Hide()
    end
    if entry.kind == "e" then
        slot.rank:SetTextColor(1, 0.82, 0)
    else
        slot.rank:SetTextColor(1, 1, 1)
    end
    if info.chance and info.chance ~= "" and entry.kind ~= "e" and tonumber(info.chanceValue or 0) > 0 then
        slot.ready:Show()
    else
        slot.ready:Hide()
    end
    slot.cycleStart = nil
    RestartCooldown(slot)
end

local function SetLocked(slot, locked)
    slot.locked = locked
    if locked then
        slot.shade:Show()
        slot.lock:Show()
    else
        slot.shade:Hide()
        slot.lock:Hide()
    end
end

local function RefreshSlots()
    for index = 1, SPELL_SLOTS do
        UpdateSlot(spellSlots[index], run.spells[index])
        SetLocked(spellSlots[index], not run.spells[index] and index > (run.spellSlots or SPELL_SLOTS))
        spellSlots[index].spellIndex = index
        spellSlots[index].slotIndex = index
    end
    for index = 1, PASSIVE_SLOTS do
        UpdateSlot(passiveSlots[index], run.passives[index])
        SetLocked(passiveSlots[index], not run.passives[index] and index > (run.passiveSlots or PASSIVE_SLOTS))
        passiveSlots[index].slotIndex = index
    end
end

local function RunHeld()
    local offer, vendor, gear = getglobal("VanillaBonkOffer"), getglobal("VanillaBonkVendor"), getglobal("VanillaBonkGear")
    return UI.ServerPaused or (offer and offer.open) or (vendor and vendor.open) or (gear and gear.open) or (UI.MenuPaused and UI.MenuPaused())
end
UI.RunHeld = RunHeld

local function HoldCooldowns(elapsed)
    for _, slot in ipairs(spellSlots) do
        local info = slot.entry and run.info[slot.entry.index]
        if slot.cycleStart and info and info.interval then
            slot.cycleStart = slot.cycleStart + elapsed
            CooldownFrame_SetTimer(slot.cooldown, slot.cycleStart, info.interval / 1000, 1)
        end
    end
end

spellBar:SetScript("OnUpdate", function()
    if RunHeld() then
        HoldCooldowns(arg1)
        return
    end
    this.elapsed = (this.elapsed or 0) + arg1
    if this.elapsed < 0.1 then
        return
    end
    this.elapsed = 0
    for _, slot in ipairs(spellSlots) do
        local info = slot.entry and run.info[slot.entry.index]
        if slot.cycleStart and info and info.interval and GetTime() - slot.cycleStart >= info.interval / 1000 then
            RestartCooldown(slot)
        end
    end
end)

EndCap(campFrame, 96, -316)
EndCap(campFrame, 96, 220, true)

local masteryRim = UI.CastRim(campFrame, XP_WIDTH)
masteryRim:SetPoint("BOTTOM", root, "BOTTOM", 0, 1)
local masteryBar = CreateFrame("StatusBar", nil, masteryRim.opening)
masteryBar:SetAllPoints(masteryRim.opening)
masteryBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
masteryBar:SetStatusBarColor(0.95, 0.65, 0.15)
masteryBar:SetMinMaxValues(0, 1)
masteryBar:SetFrameLevel(masteryRim.opening:GetFrameLevel() + 1)
masteryRim.text = UI.Text(masteryRim.art, 10, UI.NUMBER_FONT, "OUTLINE")
masteryRim.text:SetPoint("CENTER", masteryRim.opening, "CENTER", 0, 1)

local crestRing = UI.Ring(campFrame, 32)
crestRing:SetPoint("CENTER", root, "BOTTOM", 0, 48)
crestRing:SetFrameLevel(masteryRim:GetFrameLevel() + 6)
crestRing.crest = crestRing:CreateTexture(nil, "ARTWORK")
crestRing.crest:SetPoint("TOPLEFT", crestRing, "TOPLEFT", 2, -2)
crestRing.crest:SetPoint("BOTTOMRIGHT", crestRing, "BOTTOMRIGHT", -2, 2)

local masteryName = UI.Text(campFrame, 14)
masteryName:SetPoint("RIGHT", root, "BOTTOM", -26, 48)
masteryName:SetJustifyH("RIGHT")
local masteryPoints = UI.Text(campFrame, 13)
masteryPoints:SetPoint("LEFT", root, "BOTTOM", 26, 48)
masteryPoints:SetTextColor(0.25, 1, 0.25)

local mastery

local function ShowMasteryTooltip()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    if not mastery then
        GameTooltip:AddLine("Class Mastery", 1, 1, 1)
        GameTooltip:Show()
        return
    end
    GameTooltip:AddDoubleLine(mastery.class .. " Mastery", mastery.level .. " / " .. mastery.maxLevel, 1, 1, 1, 0.6, 0.6, 0.6)
    if mastery.next > 0 then
        GameTooltip:AddLine(mastery.xp .. " / " .. mastery.next .. " experience", 1, 1, 1)
    end
    GameTooltip:AddLine("Runs as a " .. strlower(mastery.class) .. " earn Mastery experience for every minute you survive and every mini-boss and stage boss you kill. Harder difficulties earn more.", 1, 0.82, 0, 1)
    if not mastery.trees then
        GameTooltip:AddLine("Your class's talent trees aren't available yet. The experience you earn is saved for them.", 0.6, 0.6, 0.6, 1)
    elseif mastery.unspent > 0 then
        GameTooltip:AddLine("You have " .. mastery.unspent .. " unspent talent " .. (mastery.unspent == 1 and "point. Spend it" or "points. Spend them")
            .. " at the talent trainer.", 0.25, 1, 0.25, 1)
    end
    GameTooltip:Show()
end

for _, frame in ipairs({ masteryRim, crestRing }) do
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ShowMasteryTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function RefreshMastery()
    local _, classToken = UnitClass("player")
    UI.SetRoundClassCrest(crestRing.crest, classToken)
    if not mastery then
        masteryBar:SetValue(0)
        masteryRim.text:SetText("")
        masteryName:SetText("|cffffd100Class Mastery|r")
        masteryPoints:SetText("")
        return
    end
    if mastery.next > 0 then
        masteryBar:SetMinMaxValues(0, mastery.next)
        masteryBar:SetValue(min(mastery.xp, mastery.next))
        masteryRim.text:SetText(mastery.xp .. " / " .. mastery.next)
    else
        masteryBar:SetMinMaxValues(0, 1)
        masteryBar:SetValue(1)
        masteryRim.text:SetText("Max level")
    end
    masteryName:SetText("|cffffd100" .. mastery.class .. " Mastery|r " .. mastery.level)
    if not mastery.trees then
        masteryPoints:SetText("|cffaaaaaaTrees coming soon|r")
    elseif mastery.unspent > 0 then
        masteryPoints:SetText(mastery.unspent .. (mastery.unspent == 1 and " talent point" or " talent points") .. " to spend")
    else
        masteryPoints:SetText("")
    end
end

local wallet = CreateFrame("Frame", nil, campFrame)
wallet:SetWidth(240)
wallet:SetHeight(18)
wallet:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 66)
wallet.text = UI.Text(wallet, 13)
wallet.text:SetPoint("RIGHT", wallet, "RIGHT", 0, 0)
wallet.text:SetJustifyH("RIGHT")
wallet:EnableMouse(true)
wallet:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Account", 1, 1, 1)
    GameTooltip:AddDoubleLine("Gold", UI.FormatGold(GetMoney()), 1, 0.82, 0, 1, 1, 1)
    if run.shards then
        GameTooltip:AddDoubleLine("Darkmoon Tickets", "|cffc080ff" .. run.shards .. "|r", 1, 0.82, 0, 1, 1, 1)
    end
    GameTooltip:AddLine("Shared by every hero.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
wallet:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function RefreshWallet()
    local text = UI.FormatGold(GetMoney())
    if run.shards then
        text = text .. "    |cffc080ff" .. run.shards .. " Darkmoon Tickets|r"
    end
    wallet.text:SetText(text)
    wallet:SetWidth(wallet.text:GetStringWidth() + 4)
end

local DASH_SIZE = 26
local DASH_ICON = "Ability_Rogue_Sprint"
local BLINK_ICON = "Spell_Arcane_Blink"
local HALF_MASK = "Interface\\AddOns\\HordesOfAzeroth\\Textures\\HalfMask"
local DASH_ARC = "Interface\\AddOns\\HordesOfAzeroth\\Textures\\DashArc"
local DASH_ARC_FRAMES = 32
local DASH_ARC_COLUMNS = 8
local DASH_ARC_ROWS = 4
local DASH_ARC_SCALE = 1.1
local RIM_SHADOW = 5
local dash = { charges = 0, max = 0, cooldown = 0, key = "Shift" }

local dashRing = UI.Ring(root, DASH_SIZE, true)
dashRing:SetFrameLevel(xpRim:GetFrameLevel() + 6)
dashRing:Hide()
dashRing.dashIcon = UI.RingArt(dashRing, UI.ICON_PATH .. DASH_ICON)
dashRing.blinkIcon = UI.RingArt(dashRing, UI.ICON_PATH .. BLINK_ICON)
dashRing.blinkIcon:Hide()
dashRing.icon = dashRing.dashIcon

local function SweepHalf(rightSide)
    local half = dashRing:CreateTexture(nil, "ARTWORK")
    half:SetTexture(UI.FLAT)
    half:SetVertexColor(0, 0, 0, 0.75)
    half:SetAllPoints(dashRing.icon)
    half:SetMask("Textures\\MinimapMask")
    local fixed = dashRing:CreateMaskTexture()
    fixed:SetTexture(HALF_MASK)
    fixed:SetAllPoints(dashRing.icon)
    if rightSide then
        fixed:SetRotation(math.pi)
    end
    half:AddMaskTexture(fixed)
    half.turn = dashRing:CreateMaskTexture()
    half.turn:SetTexture(HALF_MASK)
    half.turn:SetAllPoints(dashRing.icon)
    half:AddMaskTexture(half.turn)
    half:Hide()
    return half
end
local sweepLeft, sweepRight
if dashRing.icon.SetMask and dashRing.CreateMaskTexture then
    sweepLeft = SweepHalf(false)
    sweepRight = SweepHalf(true)
end

local function SetSweep(done)
    if not sweepLeft then
        return
    end
    if not done then
        sweepLeft:Hide()
        sweepRight:Hide()
        return
    end
    local angle = done * 360
    sweepLeft.turn:SetRotation(-math.rad(max(angle, 180) - 180))
    sweepLeft:Show()
    if angle < 180 then
        sweepRight.turn:SetRotation(-math.rad(angle - 180))
        sweepRight:Show()
    else
        sweepRight:Hide()
    end
end

local dashText = CreateFrame("Frame", nil, dashRing)
dashText:SetAllPoints(dashRing)
dashText:SetFrameLevel(dashRing:GetFrameLevel() + 2)
dashRing.arc = dashText:CreateTexture(nil, "OVERLAY")
dashRing.arc:SetTexture(DASH_ARC)
dashRing.arc:SetWidth(DASH_SIZE * DASH_ARC_SCALE)
dashRing.arc:SetHeight(DASH_SIZE * DASH_ARC_SCALE)
dashRing.arc:SetPoint("CENTER", dashRing, "CENTER", 0, 0)
dashRing.arc:Hide()
dashRing.count = UI.Text(dashText, 9, UI.NUMBER_FONT, "OUTLINE")
dashRing.count:SetPoint("BOTTOMRIGHT", dashRing, "BOTTOMRIGHT", 1, 0)
UI.DashRing = dashRing

function UI.SetDashKey(text)
    dash.key = text
end

dashRing:EnableMouse(true)
dashRing:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddDoubleLine(dash.blink and "Blink" or "Dash", dash.key ~= "" and dash.key or NOT_BOUND, 1, 1, 1, 0.6, 0.6, 0.6)
    GameTooltip:AddDoubleLine(dash.charges .. "/" .. dash.max .. " charges",
        floor(dash.cooldown / 100 + 0.5) / 10 .. " sec recharge", 1, 1, 1, 1, 1, 1)
    if dash.blink then
        GameTooltip:AddLine("Teleport a short distance in the direction you're moving. In midair, you teleport the way you're facing.", 1, 0.82, 0, 1)
    else
        GameTooltip:AddLine("Dash a short distance in the direction you're moving. In midair, you dash the way you're facing.", 1, 0.82, 0, 1)
    end
    GameTooltip:Show()
end)
dashRing:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function SetDashArc(done)
    if not done then
        dashRing.arc:Hide()
        return
    end
    local frame = max(0, min(DASH_ARC_FRAMES - 1, floor(DASH_ARC_FRAMES * done)))
    local column, row = mod(frame, DASH_ARC_COLUMNS), floor(frame / DASH_ARC_COLUMNS)
    dashRing.arc:SetTexCoord(column / DASH_ARC_COLUMNS, (column + 1) / DASH_ARC_COLUMNS, row / DASH_ARC_ROWS, (row + 1) / DASH_ARC_ROWS)
    dashRing.arc:Show()
end

local function RefreshDash()
    if dash.max <= 0 then
        dashRing:Hide()
        return
    end
    local icon = dash.blink and dashRing.blinkIcon or dashRing.dashIcon
    if icon ~= dashRing.icon then
        dashRing.icon:Hide()
        icon:Show()
        dashRing.icon = icon
    end
    if dash.charges > 0 then
        dashRing.icon:SetVertexColor(1, 1, 1)
    else
        dashRing.icon:SetVertexColor(0.45, 0.45, 0.45)
    end
    if dash.left and dash.cooldown > 0 then
        local done = 1 - dash.left * 1000 / dash.cooldown
        SetSweep(done)
        SetDashArc(done)
    else
        SetSweep(nil)
        SetDashArc(nil)
    end
    dashRing.count:SetText(dash.max > 1 and dash.charges or "")
    dashRing:Show()
end

dashRing:SetScript("OnUpdate", function()
    if not dash.left or dash.paused or RunHeld() then
        return
    end
    dash.left = max(0, dash.left - arg1)
    RefreshDash()
end)

local function PlaceDash(running)
    dashRing:ClearAllPoints()
    if running then
        dashRing:SetPoint("BOTTOM", root, "BOTTOM", 26 + 4 + DASH_SIZE / 2, 48 + 30 - RIM_SHADOW)
    else
        dashRing:SetPoint("BOTTOM", root, "BOTTOM", 190, 1 + 30 - RIM_SHADOW)
    end
end

if UIPARENT_MANAGED_FRAME_POSITIONS and UIPARENT_MANAGED_FRAME_POSITIONS["CastingBarFrame"] then
    UIPARENT_MANAGED_FRAME_POSITIONS["CastingBarFrame"].baseY = 140
end

local function RunXp(level)
    if run.xp then
        return run.xp.level, run.xp.xp, run.xp.next
    end
    return level or UnitLevel("player"), UnitXP("player"), UnitXPMax("player")
end

local function RefreshXp(level)
    local current, maximum
    level, current, maximum = RunXp(level)
    if maximum and maximum > 0 then
        xpBar:SetMinMaxValues(0, maximum)
        xpBar:SetValue(min(current, maximum))
        xpRim.text:SetText(current .. " / " .. maximum)
    else
        xpBar:SetMinMaxValues(0, 1)
        xpBar:SetValue(1)
        xpRim.text:SetText("")
    end
    levelRing.text:SetText(level)
end

local function ShowXpTooltip()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    local level, current, maximum = RunXp()
    GameTooltip:AddLine("Level " .. level, 1, 1, 1)
    GameTooltip:AddLine(current .. " / " .. maximum .. " experience", 1, 1, 1)
    GameTooltip:AddLine("Every level brings a choice of 3 upgrades.", 1, 0.82, 0, 1)
    GameTooltip:AddLine("Each run starts again at level 1.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
for _, frame in ipairs({ xpRim, levelRing }) do
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", ShowXpTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SetMode(running)
    inRun = running
    PlaceDash(running)
    if running then
        campFrame:Hide()
        runFrame:Show()
        RefreshXp()
    else
        runFrame:Hide()
        campFrame:Show()
        RefreshMastery()
        RefreshWallet()
    end
end

local handlers = {}

handlers["start"] = function()
    run.info = {}
    run.stats = {}
    run.xp = nil
    SetMode(true)
end

local XP_PICKUP_SOUNDS = {
    "Interface\\AddOns\\HordesOfAzeroth\\Sounds\\XpCoin1.wav",
    "Interface\\AddOns\\HordesOfAzeroth\\Sounds\\XpCoin2.wav",
    "Interface\\AddOns\\HordesOfAzeroth\\Sounds\\XpCoin3.wav",
    "Interface\\AddOns\\HordesOfAzeroth\\Sounds\\XpCoin4.wav",
}
local XP_SOUND_GAP = 0.08
local XP_SOUND_MAX_QUEUED = 5
local xpSounds = CreateFrame("Frame")
xpSounds.last = 0
xpSounds.queued = 0
xpSounds.wait = 0

local function PlayXpPickupSound()
    local pick = math.random(getn(XP_PICKUP_SOUNDS) - 1)
    if pick >= xpSounds.last then
        pick = pick + 1
    end
    xpSounds.last = pick
    PlaySoundFile(XP_PICKUP_SOUNDS[pick])
end

xpSounds:SetScript("OnUpdate", function()
    if this.queued <= 0 then
        return
    end
    this.wait = this.wait - arg1
    if this.wait > 0 then
        return
    end
    this.queued = this.queued - 1
    this.wait = XP_SOUND_GAP
    PlayXpPickupSound()
end)

local function QueueXpPickupSounds(orbs)
    if orbs <= 0 or not UI.Option("xpSounds", true) then
        return
    end
    xpSounds.queued = min(xpSounds.queued + orbs, XP_SOUND_MAX_QUEUED)
end

handlers["runxp"] = function(f)
    run.xp = { level = tonumber(f[2] or "") or 1, xp = tonumber(f[3] or "") or 0, next = tonumber(f[4] or "") or 0 }
    if inRun then
        QueueXpPickupSounds(tonumber(f[5] or "") or 0)
    end
    if inRun then
        RefreshXp()
    end
end

handlers["state"] = function(f)
    if not inRun then
        SetMode(true)
    end
    if f[13] and f[13] ~= "" then
        run.stats = {}
        for index, item in ipairs(UI.Split(f[13], ",")) do
            local parts = UI.Split(item, ":")
            run.stats[index] = { damage = tonumber(parts[1]) or 0, kills = tonumber(parts[2]) or 0 }
        end
    end
end

handlers["end"] = function()
    run.xp = nil
    dash.max = 0
    RefreshDash()
    SetMode(false)
end

handlers["dash"] = function(f)
    dash.charges = tonumber(f[2] or "") or 0
    dash.max = tonumber(f[3] or "") or 0
    local untilNext = tonumber(f[4] or "") or 0
    dash.cooldown = tonumber(f[5] or "") or 0
    dash.blink = f[6] == "1"
    dash.paused = f[7] == "1"
    UI.ServerPaused = dash.paused
    dash.left =(dash.charges < dash.max and untilNext > 0) and untilNext / 1000 or nil
    RefreshDash()
end

handlers["pause"] = function(f)
    UI.ServerPaused = f[2] == "1"
end

handlers["loadout"] = function(f)
    run.spells, run.passives = {}, {}
    run.spellSlots = tonumber(f[3] or "")
    run.passiveSlots = tonumber(f[4] or "")
    local index = 0
    for _, item in ipairs(UI.Split(f[2] or "", ",")) do
        if item ~= "" then
            local parts = UI.Split(item, ":")
            index = index + 1
            local entry = { index = index, kind = parts[1], icon = parts[2] ~= "" and parts[2] or "INV_Misc_QuestionMark",
                rank = tonumber(parts[3]) or 1, max = tonumber(parts[4]) or 0 }
            if entry.kind == "p" then
                tinsert(run.passives, entry)
            else
                tinsert(run.spells, entry)
            end
        end
    end
    RefreshSlots()
end

handlers["pw"] = function(f)
    local index = tonumber(f[2])
    if not index then
        return
    end
    local info = run.info[index] or {}
    info.name = f[3]
    info.ranks = f[4] or ""
    info.interval = tonumber(f[5]) or 0
    info.nextCast = tonumber(f[6]) or 0
    info.held = nil
    info.line = f[7] or ""
    info.description = gsub(f[8] or "", "|n", "\n")
    info.damage = f[9] or ""
    run.info[index] = info
    RefreshSlots()
end

handlers["pcd"] = function(f)
    local index = tonumber(f[2])
    local info = index and run.info[index]
    if not info then
        return
    end
    info.interval = tonumber(f[3]) or info.interval
    info.nextCast = tonumber(f[4]) or 0
    info.held = f[5] == "1" or nil
    for _, slot in ipairs(spellSlots) do
        if slot.entry and slot.entry.index == index then
            slot.cycleStart = nil
            RestartCooldown(slot)
        end
    end
end

handlers["pwe"] = function(f)
    local index = tonumber(f[2])
    if not index then
        return
    end
    local info = run.info[index] or {}
    info.evolution = f[3] or ""
    info.evolutionText = f[4] or ""
    info.evolutions = nil
    info.evolvedFrom = f[5] or ""
    info.chance = f[6] or ""
    info.chanceValue = f[7] or "0"
    run.info[index] = info
    RefreshSlots()
end

handlers["pwev"] = function(f)
    local index = tonumber(f[2])
    if not index then
        return
    end
    local info = run.info[index] or {}
    info.evolutions = info.evolutions or {}
    tinsert(info.evolutions, { name = f[3] or "", text = f[4] or "" })
    run.info[index] = info
end

handlers["mastery"] = function(f)
    mastery = {
        class = f[2] or "Class",
        level = tonumber(f[3]) or 0,
        xp = tonumber(f[4]) or 0,
        next = tonumber(f[5]) or 0,
        maxLevel = tonumber(f[6]) or 0,
        unspent = tonumber(f[7]) or 0,
        trees = f[8] == "1",
    }
    RefreshMastery()
end

handlers["wallet"] = function(f)
    run.shards = tonumber(f[2])
    RefreshWallet()
end

handlers["shop"] = function(f)
    if f[5] == "shards" then
        run.shards = tonumber(f[6]) or run.shards
        RefreshWallet()
    end
end
handlers["shard"] = function(f)
    run.shards = tonumber(f[3]) or run.shards
end

UI.Listen(handlers)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_XP_UPDATE")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_MONEY")
events:SetScript("OnEvent", function()
    if event == "PLAYER_LEVEL_UP" then
        RefreshXp(arg1)
    elseif event == "PLAYER_MONEY" then
        RefreshWallet()
    else
        if event == "PLAYER_ENTERING_WORLD" then
            SetMode(inRun)
            if UIParent_ManageFramePositions then
                UIParent_ManageFramePositions()
            end
        end
        RefreshXp()
    end
end)

SetMode(false)
