local defaults = { W = "MOVEFORWARD", Z = "TOGGLESHEATH", A = "TURNLEFT", Q = "STRAFELEFT" }
local french = { Z = "MOVEFORWARD", W = "TOGGLESHEATH", Q = "TURNLEFT", A = "STRAFELEFT" }
local keyboard = CreateFrame("Frame")
keyboard:RegisterEvent("PLAYER_LOGIN")
keyboard:SetScript("OnEvent", function()
    if not HoAKeyboard_GetLayout then return end
    local layout = HoAKeyboard_GetLayout()
    if layout ~= "AZERTY" and layout ~= "QWERTY" then return end
    local previous = VanillaBonkKeyboardLayout
    if previous == layout then return end
    local from = previous == "AZERTY" and french or defaults
    local target = layout == "AZERTY" and french or defaults
    local changed = false
    for _, pair in ipairs({ { "W", "Z" }, { "A", "Q" } }) do
        local first, second = pair[1], pair[2]
        if from[first] ~= target[first] and GetBindingAction(first) == from[first] and GetBindingAction(second) == from[second] then
            SetBinding(first, target[first])
            SetBinding(second, target[second])
            changed = true
        end
    end
    VanillaBonkKeyboardLayout = layout
    if changed then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
end)
