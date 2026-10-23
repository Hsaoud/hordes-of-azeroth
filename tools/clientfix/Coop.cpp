#include "ClientFix.h"
#include "ClientLua.h"
#include <cstdio>
#include <cstring>
#include <string>

namespace
{
    std::string Invitation()
    {
        wchar_t path[MAX_PATH];
        DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
        if (!length || length >= MAX_PATH) return {};
        std::wstring file(path);
        file.resize(file.find_last_of(L"\\/") + 1);
        file += L"HordesOfAzeroth\\coop-invitation.txt";
        FILE* stream = nullptr;
        if (_wfopen_s(&stream, file.c_str(), L"rb") != 0 || !stream) return {};
        char code[257] = {};
        size_t count = fread(code, 1, sizeof(code) - 1, stream);
        fclose(stream);
        if (count < 40 || count >= sizeof(code) - 1 || strncmp(code, "HOA1-", 5)) return {};
        for (size_t i = 0; i < count; ++i)
            if (!((code[i] >= 'A' && code[i] <= 'Z') || (code[i] >= 'a' && code[i] <= 'z') ||
                (code[i] >= '0' && code[i] <= '9') || code[i] == '-' || code[i] == '_')) return {};
        return std::string(code, count);
    }

    int __fastcall GetInvitation(void* L)
    {
        std::string code = Invitation();
        if (code.empty()) ClientLua::pushnil(L);
        else ClientLua::pushstring(L, code.c_str());
        return 1;
    }

    int __fastcall CopyInvitation(void* L)
    {
        std::string code = Invitation();
        bool copied = false;
        if (!code.empty() && OpenClipboard(GetForegroundWindow()))
        {
            std::wstring wide(code.begin(), code.end());
            HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, (wide.size() + 1) * sizeof(wchar_t));
            if (memory)
            {
                void* buffer = GlobalLock(memory);
                if (buffer)
                {
                    memcpy(buffer, wide.c_str(), (wide.size() + 1) * sizeof(wchar_t));
                    GlobalUnlock(memory);
                    if (EmptyClipboard() && SetClipboardData(CF_UNICODETEXT, memory)) copied = true;
                }
                if (!copied) GlobalFree(memory);
            }
            CloseClipboard();
        }
        ClientLua::pushboolean(L, copied ? 1 : 0);
        return 1;
    }
}

void RegisterCoopFunctions()
{
    ClientLua::Register("HoACoop_GetInvitation", &GetInvitation);
    ClientLua::Register("HoACoop_CopyInvitation", &CopyInvitation);
}
