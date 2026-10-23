from pathlib import Path
import re
from lupa import lua51


root = Path(__file__).resolve().parents[2]
native = (root / "tools/clientfix/LoginRecovery.cpp").read_text(encoding="utf-8")
script = re.search(r'R"lua\((.*?)\)lua"', native, re.S).group(1)
lua = lua51.LuaRuntime()
lua.execute('''
calls, originalCalls = {}, 0
accepted, accountVisible, agreementVisible, dialogVisible = true, true, false, false
AccountLogin = { IsVisible = function() return accountVisible end }
TOSFrame = { IsVisible = function() return agreementVisible end }
GlueDialog = { IsVisible = function() return dialogVisible end }
AccountLoginAccountEdit = { text = "", SetText = function(self, value) self.text = value end }
AccountLoginPasswordEdit = { text = "", SetText = function(self, value) self.text = value end, GetText = function(self) return self.text end }
function EULAAccepted() return accepted end
function TOSAccepted() return accepted end
function DefaultServerLogin(account, password) table.insert(calls, { account, password }) end
function AccountLogin_Login() originalCalls = originalCalls + 1 end
''')
lua.execute(script)("COOP0123456789AB", "TESTSECRET456789")
lua.execute('''
accepted = false
assert(HoALoginRecovery_Tick() == "agreements" and #calls == 0)
AccountLoginPasswordEdit.text = "123"
AccountLogin_Login()
assert(#calls == 0)
accepted, agreementVisible = true, true
assert(HoALoginRecovery_Tick() == "agreements" and #calls == 0)
agreementVisible, dialogVisible = false, true
assert(HoALoginRecovery_Tick() == "connecting-or-message" and #calls == 0)
dialogVisible = false
assert(HoALoginRecovery_Tick() == "recovered-stock-login" and #calls == 1)
for i = 1, 10 do HoALoginRecovery_Tick() end
assert(#calls == 1)
assert(calls[1][1] == "COOP0123456789AB" and calls[1][2] == "TESTSECRET456789")
AccountLoginAccountEdit.text = "PLAYER"
AccountLoginPasswordEdit.text = "123"
AccountLogin_Login()
assert(#calls == 2 and calls[2][1] == "COOP0123456789AB" and calls[2][2] == "TESTSECRET456789")
assert(AccountLoginPasswordEdit.text == "")
AccountLoginPasswordEdit.text = "manual"
AccountLogin_Login()
assert(originalCalls == 1 and #calls == 2)
accountVisible = false
assert(HoALoginRecovery_Tick() == "ready" and #calls == 2)
accountVisible = true
Bonk, BONK_ACCOUNT, BONK_PASSWORD = {}, "COOP0123456789AB", "TESTSECRET456789"
customShown, customCalls = false, 0
BonkLoginFrame = { IsVisible = function() return customShown end }
function BonkLogin_Begin() customCalls = customCalls + 1 customShown = true end
assert(HoALoginRecovery_Tick() == "custom-login" and customCalls == 1)
assert(HoALoginRecovery_Tick() == "custom-login" and customCalls == 1 and #calls == 2)
''')
print("PASS missing custom UI recovers once; 123 retries the prepared profile, never another account")
print("PASS agreements and dialogs respected; manual login preserved; delayed custom UI restored")
