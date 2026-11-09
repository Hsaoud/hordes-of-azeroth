from pathlib import Path
from lupa import lua51


root = Path(__file__).resolve().parents[2]
addon = root / "Interface" / "AddOns" / "HordesOfAzeroth"
lua = lua51.LuaRuntime()
parser = lua.eval("function(s,n) local f,e=loadstring(s,n); return f ~= nil,e end")
for path in addon.glob("*.lua"):
    ok, error = parser(path.read_text(encoding="utf-8"), str(path))
    assert ok, error
print("PASS all addon files parse with Lua 5.1")
lua.execute(r'''
mod = math.fmod
min, max, floor, ceil, abs, sqrt = math.min, math.max, math.floor, math.ceil, math.abs, math.sqrt
getn, tinsert, format, strsub, strfind = table.getn, table.insert, string.format, string.sub, string.find
frames, commands, UISpecialFrames = {}, {}, {}
local methods = {}
local noop = function() end
for _, name in ipairs({"SetShadowColor", "SetShadowOffset", "SetTexture", "SetTexCoord", "SetFont", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetFrameStrata", "SetFrameLevel", "EnableMouse", "EnableMouseWheel", "SetMovable", "SetClampedToScreen", "RegisterForDrag", "SetStatusBarTexture", "SetStatusBarColor", "SetAutoFocus", "SetVertexColor", "SetGradientAlpha", "SetBlendMode", "SetNormalTexture", "SetHighlightTexture", "SetDisabledTexture", "SetNormalFontObject", "SetHighlightFontObject", "SetDisabledFontObject", "RegisterForClicks", "SetID", "AddLine", "AddDoubleLine", "SetOwner", "SetAlpha", "SetPoint", "SetAllPoints", "ClearAllPoints"}) do methods[name] = noop end
function methods:SetWidth(v) assert(type(v) == "number") self.width = v end
function methods:SetHeight(v) assert(type(v) == "number") self.height = v end
function methods:GetWidth() return self.width or 100 end
function methods:GetHeight() return self.height or 30 end
function methods:GetFrameLevel() return 1 end
function methods:SetText(v) self.text = tostring(v) end
function methods:GetText() return self.text end
function methods:GetStringWidth() return string.len(self.text or "") * 6 end
function methods:GetName() return self.name end
function methods:SetParent(v) self.parent = v end
function methods:GetParent() return self.parent end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:RegisterEvent(name) self.events[name] = true end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:IsShown() return self.shown end
methods.IsVisible = methods.IsShown
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:SetMinMaxValues(a,b) self.minimum,self.maximum = a,b end
function methods:SetValue(v) assert(v >= self.minimum and v <= self.maximum) self.value = v end
function methods:SetZoom(v) self.zoom = v end
function methods:GetZoom() return self.zoom or 0 end
function methods:GetZoomLevels() return 6 end
function methods:SetMaskTexture(v) self.mask = v end
function methods:SetFocus() self.focused = true end
function methods:HighlightText() self.selected = true end
function methods:Click() this = self if self.scripts.OnClick then self.scripts.OnClick() end end
function CreateFrame(kind,name,parent)
    local frame = setmetatable({kind=kind,name=name,parent=parent,shown=true,enabled=true,scripts={},events={}}, {__index=methods})
    tinsert(frames,frame)
    if name then _G[name] = frame end
    return frame
end
function methods:CreateTexture(name) return CreateFrame("Texture",name,self) end
function methods:CreateFontString(name) return CreateFrame("FontString",name,self) end
function getglobal(name) return _G[name] end
for _,name in ipairs({"UIParent","WorldFrame","GameTooltip","UIErrorsFrame","Minimap","MinimapCluster","GameMenuFrame","OptionsFrame","SoundOptionsFrame","UIOptionsFrame","KeyBindingFrame"}) do CreateFrame("Frame",name) end
UIParent:SetHeight(768)
GameMenuFrame:Hide()
function GetMinimapZoneText() return "Westfall" end
function GetZoneText() return "Westfall" end
raidCount,partyCount = 0,0
function GetNumRaidMembers() return raidCount end
function GetNumPartyMembers() return partyCount end
function UnitHealth() return 75 end
function UnitHealthMax() return 100 end
function UnitIsConnected() return true end
function UnitIsDeadOrGhost() return false end
function UnitName(unit) return unit end
function GetTime() return 1 end
function PlaySound() end
function StaticPopup_Visible() return false end
function ShowUIPanel(frame) frame:Show() end
function HideUIPanel(frame) frame:Hide() end
function CloseMenus() end
function CloseAllWindows() end
function SendChatMessage(text) tinsert(commands,text) end
function HoACoop_GetInvitation() return "HOA1-" .. string.rep("A",80) end
function HoACoop_CopyInvitation() return copyAvailable end
function ToggleWorldMap() mapOpened = true end
function InviteByName(name) invited = name end
function IsPartyLeader() return true end
function ConvertToRaid() raidCount = 5 end
function SetPortraitTexture() end
VanillaBonkController = {}
SlashCmdList = {VANILLABONK = function() missionOpened = true end}
function Emit(text)
    arg1 = text
    for _,frame in ipairs(frames) do
        if frame.events.CHAT_MSG_SYSTEM and frame.scripts.OnEvent then this=frame frame.scripts.OnEvent() end
    end
end
function Button(text)
    for _,frame in ipairs(frames) do if frame.kind == "Button" and frame.text == text then return frame end end
    error("Missing button: " .. text)
end
''')
for name in ("UI", "Coop", "Tracker", "Navigation", "Menu"):
    lua.execute((addon / ("VanillaBonk" + name + ".lua")).read_text(encoding="utf-8"))
lua.execute(r'''
Emit("BONK~coop~1~0~0~0~0")
assert(VanillaBonkCoop:IsShown())
ToggleGameMenu(true)
assert(Button("Invite friends"):IsShown())
Button("Choose expedition"):Click()
assert(missionOpened)
copyAvailable = true
VanillaBonkUI.CopyCoopInvitation()
assert(string.find(VanillaBonkInvitation.header.text,"Copied!",1,true))
copyAvailable = false
Button("Copy invitation"):Click()
assert(VanillaBonkInvitation.edit.selected and VanillaBonkInvitation.edit.focused)
Emit("BONK~coopprompt~42~Friend~Normal~Westfall~join")
assert(VanillaBonkMissionInvite:IsShown())
Button("Join in progress"):Click()
assert(commands[getn(commands)] == ".bonk coop accept 42")
Emit("BONK~coopprompt~42~Friend~Normal~Westfall~join")
assert(not VanillaBonkMissionInvite:IsShown())
Emit("BONK~coopprompt~0")
Emit("BONK~coopprompt~43~Friend~Normal~Westfall~start")
assert(VanillaBonkMissionInvite:IsShown())
Button("Not now"):Click()
assert(commands[getn(commands)] == ".bonk coop decline 43")
VanillaBonkUI.OpenCoopParty()
Emit("BONK~cooplobbyclear")
for i=1,25 do Emit("BONK~cooplobby~Hero" .. i .. "~8~0~0") end
assert(string.find(VanillaBonkParty.header.text,"page 1/3",1,true))
VanillaBonkParty.next:Click()
VanillaBonkParty.next:Click()
assert(string.find(VanillaBonkParty.header.text,"page 3/3",1,true))
local lastHero
for _,frame in ipairs(frames) do if frame.hero == "Hero25" then lastHero = frame end end
assert(lastHero)
lastHero:Click()
assert(invited == "Hero25")
raidCount = 40
Emit("BONK~coop~40~0~0~0~0")
this = VanillaBonkCoop
arg1 = -4
this.scripts.OnMouseWheel()
assert(string.find(VanillaBonkCoop.title.text,"5/5",1,true))
Emit("BONK~start~Westfall~Normal~600~1")
Emit("BONK~state~300~600~120~12345~8~0~50~100~1~0~12")
assert(VanillaBonkTracker.progress.value == 0.5)
assert(Minimap.parent == VanillaBonkNavigation and Minimap:GetWidth() >= 184)
Button("+"):Click()
assert(Minimap:GetZoom() == 1)
Button("World map"):Click()
assert(mapOpened)
ToggleGameMenu(true)
assert(Button("|cffff5a4aLeave Expedition|r"):IsShown())
Button("|cffff5a4aLeave Expedition|r"):Click()
Button("|cffff5a4aLeave|r"):Click()
assert(commands[getn(commands)] == ".bonk stop")
local specialFound = false
for _, name in ipairs(UISpecialFrames) do if name == "VanillaBonkMissionInvite" then specialFound = true end end
assert(specialFound)
Emit("BONK~coopprompt~0")
Emit("BONK~coopprompt~99~Leader~Normal~Westfall~start")
assert(VanillaBonkMissionInvite:IsShown())
this = VanillaBonkMissionInvite
if this.scripts.OnHide then this.scripts.OnHide() end
assert(commands[getn(commands)] == ".bonk coop decline 99")
''')
print("PASS menu actions, clipboard fallback, invitation deduplication, 25-player lobby, 40-player roster, HUD and minimap controls")

lua.execute(r'''
Emit("BONK~rescue~Hero1~2000~6000~1")
assert(VanillaBonkUI.CooperativeDeath and VanillaBonkRescue:IsShown())
assert(math.abs(VanillaBonkRescue.bar.value - 1/3) < 0.001)
ToggleGameMenu(true)
assert(not Button("|cffff5a4aLeave Expedition|r").enabled)
local previous = getn(commands)
Button("|cffff5a4aLeave Expedition|r"):Click()
assert(getn(commands)==previous)
Emit("BONK~rescue~Hero2~4000~6000~0")
assert(VanillaBonkRescue.title.text=="Your allies can revive you")
Emit("BONK~rescue~Hero2~0~0~0")
assert(VanillaBonkUI.CooperativeDeath)
Emit("BONK~rescue~Hero1~0~0~1")
assert(not VanillaBonkUI.CooperativeDeath and not VanillaBonkRescue:IsShown())
Emit("BONK~rescue~Hero2~3000~6000~0")
assert(VanillaBonkRescue.title.text=="Revive Hero2")
Emit("BONK~end~0~20~1~0")
assert(not VanillaBonkRescue:IsShown())
''')
print("PASS rescue progress, downed-player menu lock, multiple fallen allies and wipe cleanup")
