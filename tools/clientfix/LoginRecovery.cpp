#include "ClientFix.h"
#include "ClientLua.h"
#include <cstdio>
#include <cstring>
#include <string>

namespace
{
    char const* RecoveryScript = R"lua(
return function(account, password)
    if not AccountLogin_Login or not DefaultServerLogin then return end
    local originalLogin = AccountLogin_Login
    local attempted = false
    function AccountLogin_Login()
        if AccountLoginPasswordEdit:GetText() ~= "123" then
            return originalLogin()
        end
        if not EULAAccepted() or not TOSAccepted() or TOSFrame:IsVisible() then return end
        AccountLoginAccountEdit:SetText(account)
        AccountLoginPasswordEdit:SetText("")
        DefaultServerLogin(account, password)
    end
    function HoALoginRecovery_Tick()
        if not AccountLogin or not AccountLogin:IsVisible() then return "ready" end
        if not EULAAccepted() or not TOSAccepted() or TOSFrame:IsVisible() then return "agreements" end
        if (ConnectionHelpFrame and ConnectionHelpFrame:IsVisible()) or
            (SurveyNotificationFrame and SurveyNotificationFrame:IsVisible()) then return "dialog" end
        if GlueDialog and GlueDialog:IsVisible() then return "connecting-or-message" end
        if BonkLogin_Begin and BonkLoginFrame and Bonk and BONK_ACCOUNT == account and BONK_PASSWORD == password then
            if not BonkLoginFrame:IsVisible() then BonkLogin_Begin() end
            return "custom-login"
        end
        if not attempted then
            attempted = true
            AccountLoginAccountEdit:SetText(account)
            AccountLoginPasswordEdit:SetText("")
            DefaultServerLogin(account, password)
        end
        return "recovered-stock-login"
    end
end
)lua";

    bool PushFunction(void* L, char const* name)
    {
        ClientLua::pushstring(L, name);
        ClientLua::gettable(L, ClientLua::GLOBALSINDEX);
        return ClientLua::type(L, -1) == ClientLua::TFUNCTION;
    }

    std::string ReadValue(std::string const& source, char const* name)
    {
        std::string prefix = std::string(name) + " = \"";
        size_t begin = source.find(prefix);
        if (begin == std::string::npos) return {};
        begin += prefix.size();
        size_t end = source.find('"', begin);
        if (end == std::string::npos || end == begin || end - begin > 16) return {};
        std::string value = source.substr(begin, end - begin);
        for (char c : value)
            if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))) return {};
        return value;
    }

    bool ReadProfile(std::string& account, std::string& password)
    {
        wchar_t path[MAX_PATH];
        DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
        if (!length || length >= MAX_PATH) return false;
        std::wstring file(path);
        file.resize(file.find_last_of(L"\\/") + 1);
        file += L"Interface\\GlueXML\\BonkAccount.lua";
        FILE* stream = nullptr;
        if (_wfopen_s(&stream, file.c_str(), L"rb") != 0 || !stream) return false;
        char contents[1024] = {};
        size_t count = fread(contents, 1, sizeof(contents) - 1, stream);
        fclose(stream);
        if (!count || count == sizeof(contents) - 1) return false;
        account = ReadValue(contents, "BONK_ACCOUNT");
        password = ReadValue(contents, "BONK_PASSWORD");
        bool validAccount = _stricmp(account.c_str(), "PLAYER") == 0;
        if (account.size() == 16 && account.substr(0, 4) == "COOP")
            validAccount = account.find_first_not_of("0123456789ABCDEF", 4) == std::string::npos;
        return validAccount && !password.empty();
    }
}

void TickLoginRecovery(void* L)
{
    static DWORD lastTick = 0;
    static std::string lastStatus;
    DWORD now = GetTickCount();
    if (now - lastTick < 500) return;
    lastTick = now;
    int top = ClientLua::gettop(L);
    if (PushFunction(L, "HoALoginRecovery_Tick"))
    {
        if (ClientLua::pcall(L, 0, 1, 0) == 0)
        {
            char const* state = ClientLua::tostring(L, -1);
            if (state && lastStatus != state)
            {
                lastStatus = state;
                Log("login: %s", state);
            }
        }
        else if (lastStatus != "recovery-error")
        {
            lastStatus = "recovery-error";
            Log("login: recovery-error");
        }
        ClientLua::settop(L, top);
        return;
    }
    ClientLua::settop(L, top);
    if (!PushFunction(L, "AccountLogin_Login"))
    {
        ClientLua::settop(L, top);
        return;
    }
    ClientLua::settop(L, top);
    std::string account, password;
    if (!ReadProfile(account, password)) return;
    if (PushFunction(L, "loadstring"))
    {
        ClientLua::pushstring(L, RecoveryScript);
        if (ClientLua::pcall(L, 1, 1, 0) == 0 && ClientLua::type(L, -1) == ClientLua::TFUNCTION &&
            ClientLua::pcall(L, 0, 1, 0) == 0 && ClientLua::type(L, -1) == ClientLua::TFUNCTION)
        {
            ClientLua::pushstring(L, account.c_str());
            ClientLua::pushstring(L, password.c_str());
            if (ClientLua::pcall(L, 2, 0, 0) == 0)
                Log("login: recovery-ready");
        }
    }
    ClientLua::settop(L, top);
}
