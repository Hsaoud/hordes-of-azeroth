#include "ClientFix.h"
#include "ClientLua.h"

namespace
{
    int __fastcall GetKeyboardLayoutName(void* L)
    {
        HKL layout = GetKeyboardLayout(0);
        UINT forward = MapVirtualKeyExW(0x11, MAPVK_VSC_TO_VK_EX, layout);
        UINT left = MapVirtualKeyExW(0x1E, MAPVK_VSC_TO_VK_EX, layout);
        ClientLua::pushstring(L, forward == 'Z' && left == 'Q' ? "AZERTY" : forward == 'W' && left == 'A' ? "QWERTY" : "OTHER");
        return 1;
    }
}

void RegisterKeyboardFunctions()
{
    ClientLua::Register("HoAKeyboard_GetLayout", &GetKeyboardLayoutName);
}
