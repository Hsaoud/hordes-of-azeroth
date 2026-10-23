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
health={SetMinMaxValues=function(self,a,b) self.maximum=b end,SetValue=function(self,v) self.value=v end,SetStatusBarColor=function(self,r,g,b) self.color={r,g,b} end}
plate={vbGuid='ally-guid',vbHealth=health}
''')
start=source.index('local function Recolor(')
end=source.index('local function TintKind',start)
lua.execute(source[start:end].replace('local function Recolor(', 'function Recolor('))
lua.execute('''
Recolor(plate)
assert(health.value==80 and health.maximum==100 and health.color[2]==0.8)
hp=20
Recolor(plate)
assert(health.value==20 and health.color[1]==0.95)
dead=true;hp=0
Recolor(plate)
assert(health.value==0 and health.color[1]==0.5)
''')
print('PASS ally plates show actual health, low-health warning and downed state')
