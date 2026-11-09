from pathlib import Path
from lupa import lua51

root = Path(__file__).resolve().parents[2]
addon = root / 'Interface/AddOns/HordesOfAzeroth'
keyboard = (addon / 'VanillaBonkKeyboard.lua').read_text(encoding='utf-8')
lua = lua51.LuaRuntime()
lua.execute('''
bindings = { W='MOVEFORWARD', Z='TOGGLESHEATH', A='TURNLEFT', Q='STRAFELEFT' }
layout, saved = 'AZERTY', 0
function CreateFrame() return { RegisterEvent=function() end, SetScript=function(self,k,f) onLogin=f end } end
function HoAKeyboard_GetLayout() return layout end
function GetBindingAction(k) return bindings[k] end
function SetBinding(k,v) bindings[k]=v end
function SaveBindings(set) assert(set==2) saved=saved+1 end
function GetCurrentBindingSet() return 2 end
''')
lua.execute(keyboard)
lua.execute('''
onLogin()
assert(bindings.Z=='MOVEFORWARD' and bindings.Q=='TURNLEFT' and bindings.A=='STRAFELEFT' and saved==1)
onLogin()
assert(saved==1)
layout='QWERTY'
onLogin()
assert(bindings.W=='MOVEFORWARD' and bindings.A=='TURNLEFT' and saved==2)
bindings.Q='CUSTOM_ACTION'
layout='AZERTY'
onLogin()
assert(bindings.Z=='MOVEFORWARD' and bindings.Q=='CUSTOM_ACTION' and bindings.A=='TURNLEFT')
layout='OTHER'
onLogin()
assert(bindings.Q=='CUSTOM_ACTION')
''')
print('PASS keyboard detection adapts default movement, preserves custom keys and does not repeat changes')

source=(addon / 'VanillaBonkHeroBar.lua').read_text(encoding='utf-8')
lua=lua51.LuaRuntime()
lua.execute('''
UI, handlers, dash = {}, {}, {charges=0,max=1,cooldown=10000,left=1}
max=math.max
function RefreshDash() end
function getglobal() return nil end
dashRing={SetScript=function(self,name,fn) tick=fn end}
''')
start=source.index('local function RunHeld()')
end=source.index('local function HoldCooldowns',start)
lua.execute(source[start:end].replace('local function RunHeld()', 'function RunHeld()'))
start=source.index('dashRing:SetScript("OnUpdate"')
end=source.index('local function PlaceDash',start)
lua.execute(source[start:end])
start=source.index('handlers["dash"] =')
end=source.index('handlers["loadout"]',start)
lua.execute(source[start:end])
lua.execute('''
arg1=2
tick()
assert(dash.left==0 and dash.charges==0)
handlers.dash({'dash','0','1','7000','10000','0','1'})
arg1=30
tick()
assert(dash.left==7 and dash.charges==0)
handlers.dash({'dash','0','1','7000','10000','0','0'})
arg1=1
tick()
assert(dash.left==6 and dash.charges==0)
handlers.pause({'pause','1'})
tick()
assert(dash.left==6)
handlers.dash({'dash','1','1','0','10000','0','0'})
assert(dash.charges==1 and dash.left==nil)
''')
print('PASS dash waits for server confirmation and freezes during remote pauses')

source=(root / 'Interface/GlueXML/BonkGlue.lua').read_text(encoding='utf-8')
lua=lua51.LuaRuntime()
lua.execute('''
Bonk, BONK_ACCOUNT, attempts = {}, 'PLAYER', 0
local frame={Hide=function() end,Show=function() end,ClearFocus=function() end,SetText=function() end,IsVisible=function() return true end}
BonkHeroFrame,BonkLoginFrame,AccountLoginUI,AccountLoginAccountEdit,AccountLoginPasswordEdit,BonkLoginStatus,AccountLogin=frame,frame,frame,frame,frame,frame,frame
TOSFrame={IsVisible=function() return false end}
function EULAAccepted() return true end
function TOSAccepted() return true end
function AccountLogin_ShowUserAgreements() end
function AccountLogin_OnShow() AccountLogin_ShowUserAgreements() end
function BonkLogin_Connect() attempts=attempts+1 end
''')
start=source.index('local OriginalAccountLoginOnShow')
end=source.index('local OriginalAccountLoginOnKeyDown',start)
lua.execute(source[start:end])
lua.execute('AccountLogin_OnShow(); assert(attempts==1); AccountLogin_OnShow(); assert(attempts==2)')
print('PASS stock agreement callback and custom login entry cause exactly one connection attempt')

source=(addon / 'VanillaBonkPlates.lua').read_text(encoding='utf-8')
lua=lua51.LuaRuntime()
lua.execute('''
partyByGuid={['ally-guid']='party1'}
max=math.max
hp, maximum, dead = 80, 100, false
function UnitHealth() return hp end
function UnitHealthMax() return maximum end
function UnitIsDeadOrGhost() return dead end
depth, callbacks = 0, 0
function NotifyHealth(self)
    depth=depth+1
    assert(depth<10, 'recursive ally health update')
    callbacks=callbacks+1
    local previous=this
    this=self
    self.onValueChanged()
    this=previous
    depth=depth-1
end
health={SetMinMaxValues=function(self,a,b) self.maximum=b; NotifyHealth(self) end,SetValue=function(self,v) self.value=v; NotifyHealth(self) end,SetStatusBarColor=function(self,r,g,b) self.color={r,g,b} end,GetParent=function() return plate end,SetScript=function(self,k,f) self.onValueChanged=f end}
plate={vbGuid='ally-guid',vbHealth=health}
function TintKind() end
function UpdateText(owner) owner.percent=health.value/health.maximum*100 end
''')
start=source.index('local function Recolor(')
end=source.index('local function TintKind',start)
lua.execute(source[start:end].replace('local function Recolor(', 'function Recolor('))
start=source.index('health:SetScript("OnValueChanged"')
end=source.index('\n    plate:SetWidth(1)',start)
lua.execute(source[start:end])
lua.execute('''
Recolor(plate)
assert(health.value==80 and health.maximum==100 and health.color[2]==0.8)
hp=20
Recolor(plate)
assert(health.value==20 and health.color[1]==0.95)
dead=true;hp=0
Recolor(plate)
assert(health.value==0 and health.color[1]==0.5)
dead=false;hp=65;maximum=200
this=health
health.onValueChanged()
assert(health.value==65 and health.maximum==200 and plate.percent==32.5)
assert(this==health and depth==0 and not plate.vbUpdatingHealth)
for i=1,100 do health.onValueChanged() end
assert(health.value==65 and callbacks==208 and depth==0)
''')
print('PASS ally plates show actual health, low-health warning, downed and revived states without recursive value callbacks')

source=(addon / 'VanillaBonkUI.lua').read_text(encoding='utf-8')
lua=lua51.LuaRuntime()
lua.execute('''
UI={}
dead=false
function UnitIsDeadOrGhost(unit) assert(unit=='player') return dead end
function UnitName(unit) assert(unit=='player') return 'Coopalpha' end
function SendChatMessage(text, channel, language, target)
    assert(text=='.bonk pick 1' and language==nil)
    assert(channel==(dead and 'WHISPER' or 'SAY'))
    assert(target==(dead and 'Coopalpha' or nil))
end
''')
lua.execute(source[source.index('function UI.Command('):source.index('UI.FONT =')])
lua.execute('UI.Command("pick 1"); dead=true; UI.Command("pick 1"); dead=false; UI.Command("pick 1")')
for path in addon.glob('*.lua'):
    if path.name != 'VanillaBonkUI.lua':
        assert 'SendChatMessage(".bonk ' not in path.read_text(encoding='utf-8'), path
print('PASS all game commands use self whisper while dead, returning to normal transport after resurrection')

source=(addon / 'VanillaBonkHeroBar.lua').read_text(encoding='utf-8')
lua=lua51.LuaRuntime()
lua.execute('''
max,min,floor,mod,getn=math.max,math.min,math.floor,math.mod,table.getn
frames={}
function getglobal(name) return frames[name] end
function CreateFrame(kind,name,parent)
    local f={shown=true,scripts={},points={}}
    function f:SetWidth(v) self.width=v end
    function f:GetWidth() return self.width end
    function f:SetHeight(v) self.height=v end
    function f:SetPoint(...) self.points={...} end
    function f:GetPoint() return unpack(self.points) end
    function f:ClearAllPoints() self.points={} end
    function f:IsShown() return self.shown end
    function f:EnableMouse() end
    function f:RegisterEvent() end
    function f:SetScript(k,v) self.scripts[k]=v end
    frames[name]=f
    return f
end
UIParent=CreateFrame('Frame','UIParent')
UIParent:SetWidth(1024)
root=CreateFrame('Frame','root')
for i=0,23 do CreateFrame('Button','BuffButton'..i) end
for i=1,2 do CreateFrame('Button','TempEnchant'..i) end
function BuffButtons_UpdatePositions() frames.BuffButton8:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',0,0) end
''')
lua.execute(source[source.index('do\n    local dock ='):])
lua.execute('''
local dock=frames.VanillaBonkAuraDock
assert(dock.points[2]==root and dock.points[5]==144)
function CheckAuras()
    local seen={}
    for name,f in pairs(frames) do
        if (string.find(name,'^BuffButton') or string.find(name,'^TempEnchant')) and f.shown then
            assert(f.points[1]=='BOTTOM' and f.points[2]==dock and f.points[3]=='BOTTOM')
            local x,y=f.points[4],f.points[5]
            assert(math.abs(x)+15<UIParent.width/2 and y>=0)
            local key=x..':'..y
            assert(not seen[key], 'overlapping aura')
            seen[key]=true
        end
    end
end
CheckAuras()
BuffButtons_UpdatePositions()
CheckAuras()
frames.BuffButton0.shown=false
frames.TempEnchant1.shown=false
UIParent:SetWidth(250)
arg1=0.2
dock.scripts.OnUpdate()
CheckAuras()
assert(frames.BuffButton23.points[5]>=184)
frames.BuffButton0.shown=true
dock.scripts.OnEvent()
dock.scripts.OnUpdate()
CheckAuras()
''')
print('PASS native buffs and enchants stay above the spell bars, wrap without overlap and survive stock repositioning and resolution changes')
