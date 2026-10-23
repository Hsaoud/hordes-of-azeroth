#include "ClientFix.h"
#include "ClientLua.h"

#include <windowsx.h>
#include <setupapi.h>
#include <hidsdi.h>
#include <hidpi.h>
#include <xinput.h>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <vector>

namespace
{
    namespace Lua = ClientLua;

    uintptr_t const VAR_INPUT_CONTROLLER    = 0x00BE1148;
    uintptr_t const VAR_INPUT_TIME          = 0x00CF0BC8;
    uintptr_t const FUN_RESOLVE_UNIT_TOKEN  = 0x00515940;
    uintptr_t const FUN_SET_CONTROL_BIT     = 0x00515090;
    uintptr_t const FUN_UNIT_SET_FACING     = 0x0060DE30;
    uintptr_t const FUN_PLAYER_JUMP         = 0x0060DEA0;
    uintptr_t const FUN_MOVEMENT_SET_FACING = 0x007C6F30;
    uintptr_t const VAR_GX_DEVICE           = 0x00C0ED38;
    uintptr_t const FUN_CURSOR_SET_VISIBLE  = 0x0058B590;
    uint32_t const OFF_DEVICE_CURSOR_VISIBLE = 0x2880;
    uintptr_t const VAR_GAME_STATE          = 0x00B4B2BC;
    uintptr_t const FUN_CAMERA_ROTATE       = 0x0050FEE0;
    uintptr_t const FUN_CAMERA_ZOOM_IN      = 0x0050FC60;
    uintptr_t const FUN_CAMERA_ZOOM_OUT     = 0x0050FCD0;
    uintptr_t const FUN_CLIENT_TIME         = 0x0042C010;
    uintptr_t const VAR_ZOOM_SPEED_CVAR     = 0x00BE0FBC;
    uint32_t const OFF_CVAR_FLOAT = 0x24;

    uint32_t const OFF_UNIT_MOVEMENT   = 0x118;
    uint32_t const OFF_MOVEMENT_FACING = 0x1C;
    uint32_t const OFF_CAMERA_YAW      = 0xF0;
    uint32_t const OFF_GAME_STATE_CAMERA = 0x65B8;
    uint32_t const OFF_CAMERA_ZOOM_FLAGS = 0x128;
    uint32_t const OFF_CAMERA_ZOOM_END   = 0x15C;

    uint32_t const CONTROL_FORWARD = 0x10;
    uint32_t const OFF_INPUT_KEYS = 0x04;
    uint32_t const OFF_MOVEMENT_FLAGS = 0x40;
    uint32_t const MOVEFLAG_FORWARD = 0x1;
    uint32_t const MOVEFLAG_FORWARD_AXIS = 0x1 | 0x2;
    uint32_t const FORWARD_AXIS_NOTE = 0x10000;
    uintptr_t const FUN_INPUT_MOVE = 0x00514640;
    DWORD const STALLED_FORWARD_MS = 300;
    DWORD const STALLED_RETRY_MS = 1000;

    using ResolveUnitToken_t = void*(__fastcall*)(char const* token);
    using SetControlBit_t = void(__thiscall*)(void* controller, uint32_t mask, int pressed, uint32_t time, int unused);
    using UnitSetFacing_t = void(__thiscall*)(void* unit, uint32_t time, float facing);
    using PlayerJump_t = void(__thiscall*)(void* player, uint32_t time);
    using MovementSetFacing_t = void(__thiscall*)(void* movement, float facing);
    using CursorSetVisible_t = void(__fastcall*)(int visible);
    using CameraRotate_t = void(__thiscall*)(void* camera, float dx, float dy);
    using CameraZoom_t = void(__thiscall*)(void* camera, float yards, uint32_t time);
    using ClientTime_t = uint32_t(__cdecl*)();

    enum Button : uint32_t
    {
        BUTTON_A     = 1u << 0,
        BUTTON_B     = 1u << 1,
        BUTTON_X     = 1u << 2,
        BUTTON_Y     = 1u << 3,
        BUTTON_LB    = 1u << 4,
        BUTTON_RB    = 1u << 5,
        BUTTON_LT    = 1u << 6,
        BUTTON_RT    = 1u << 7,
        BUTTON_VIEW  = 1u << 8,
        BUTTON_MENU  = 1u << 9,
        BUTTON_L3    = 1u << 10,
        BUTTON_R3    = 1u << 11,
        BUTTON_UP    = 1u << 12,
        BUTTON_DOWN  = 1u << 13,
        BUTTON_LEFT  = 1u << 14,
        BUTTON_RIGHT = 1u << 15,
        BUTTON_HOME  = 1u << 16,
    };
    char const* const BUTTON_NAMES[] = {
        "a", "b", "x", "y", "lb", "rb", "lt", "rt", "view", "menu", "l3", "r3", "up", "down", "left", "right", "home",
    };
    int const BUTTON_COUNT = int(sizeof(BUTTON_NAMES) / sizeof(BUTTON_NAMES[0]));

    enum class PadKind { None, Xbox, PlayStation };

    struct PadState
    {
        float lx = 0.0f, ly = 0.0f, rx = 0.0f, ry = 0.0f, lt = 0.0f, rt = 0.0f;
        uint32_t buttons = 0;
    };

    float const MOVE_DEADZONE = 0.24f;
    float const LOOK_DEADZONE = 0.20f;
    float const TRIGGER_PRESSED = 0.45f;
    float const ACTIVITY = 0.35f;
    float const FACING_EPSILON = 0.004f;
    float const FACING_SNAP = 0.35f;
    DWORD const FACING_SEND_MS = 50;
    float const CAMERA_YAW_RADIANS_PER_SECOND = 3.14159265f;
    float const CAMERA_PITCH_UNITS_PER_SECOND = 420.0f;
    float const ZOOM_THRESHOLD = 0.3f;
    float const ZOOM_STEP_YARDS = 1.0f;
    float const ZOOM_DEFAULT_SPEED = 8.33f;
    float const ZOOM_EXTEND_MS = 60.0f;
    int const ZOOM_LEAD_MS = 60;
    UINT const TICK_MS = 8;
    DWORD const FRAME_FALLBACK_MS = 100;
    UINT_PTR const TIMER_ID = 0x484F41;
    DWORD const XINPUT_RESCAN_MS = 2000;
    DWORD const SONY_RESCAN_MS = 2000;
    DWORD const DEBUG_REPORT_MS = 10000;
    float const CURSOR_SCREENS_PER_SECOND = 1.1f;
    LONG const MOUSE_TRAVEL_PIXELS = 30;
    DWORD const MOUSE_TRAVEL_WINDOW_MS = 400;
    DWORD const MOUSE_GRACE_MS = 1500;
    LPARAM const INJECTED_INPUT = 0x484F4143;
    uint32_t const DPAD_BUTTONS = BUTTON_UP | BUTTON_DOWN | BUTTON_LEFT | BUTTON_RIGHT;

    uint16_t const SONY_VENDOR = 0x054C;
    struct SonyModel
    {
        uint16_t product;
        bool dualSense;
    };
    SonyModel const SONY_MODELS[] = {
        { 0x05C4, false }, { 0x09CC, false }, { 0x0BA0, false }, { 0x0CE6, true }, { 0x0DF2, true },
    };

    using XInputGetState_t = DWORD(WINAPI*)(DWORD index, XINPUT_STATE* state);
    XInputGetState_t s_xinputGetState = nullptr;
    bool s_xinputConnected[XUSER_MAX_COUNT] = {};
    DWORD s_xinputScanAt = 0;

    std::mutex s_sonyLock;
    PadState s_sonyState;
    bool s_sonyConnected = false;

    bool s_simulating = false;
    PadState s_simulated;

    HWND s_window = nullptr;
    WNDPROC s_originalProc = nullptr;
    bool s_unicodeWindow = false;
    bool s_timerStarted = false;

    PadKind s_kind = PadKind::None;
    PadKind s_reportedKind = PadKind::None;
    uint32_t s_previousButtons = 0;
    bool s_capture = false;
    bool s_moving = false;
    DWORD s_stalledSince = 0;
    bool s_wasInWorld = false;
    DWORD s_cursorFlashUntil = 0;
    DWORD const CURSOR_FLASH_MS = 200;
    DWORD s_stalledRetryAt = 0;
    bool s_holdingCamera = false;
    float s_heldWorldYaw = 0.0f;
    struct ZoomHold
    {
        bool held;
        bool zoomIn;
        uint32_t notchEnd;
    };
    ZoomHold s_zoom = {};
    float s_sentFacing = 0.0f;
    DWORD s_facingSentAt = 0;
    DWORD s_debugAt = 0;
    bool s_cursorMode = false;
    bool s_scrollMode = false;
    bool s_cursorLeftDown = false;
    bool s_cursorRightDown = false;
    float s_cursorX = 0.0f;
    float s_cursorY = 0.0f;
    LONG s_cursorSetX = -1;
    LONG s_cursorSetY = -1;
    struct Options
    {
        float yawSpeed = 1.0f;
        float pitchSpeed = 1.0f;
        float cursorSpeed = 1.0f;
        float moveDeadzone = MOVE_DEADZONE;
        float lookDeadzone = LOOK_DEADZONE;
        bool invertPitch = false;
    };
    Options s_options;
    bool s_padInUse = false;
    bool s_cursorHidden = false;
    PadState s_lastPad;
    DWORD s_frameTickAt = 0;
    bool s_mouseKnown = false;
    LONG s_mouseX = 0;
    LONG s_mouseY = 0;
    LONG s_mouseTravel = 0;
    DWORD s_mouseAt = 0;
    DWORD s_padActiveAt = 0;

    void* LuaState()
    {
        return *reinterpret_cast<void**>(Lua::VAR_LUA_STATE);
    }

    float Clamp(float value, float low, float high)
    {
        return value < low ? low : (value > high ? high : value);
    }

    void ApplyRadialDeadzone(float& x, float& y, float deadzone)
    {
        float const length = std::sqrt(x * x + y * y);
        if (length <= deadzone)
        {
            x = y = 0.0f;
            return;
        }
        float const scaled = Clamp((length - deadzone) / (1.0f - deadzone), 0.0f, 1.0f);
        x = x / length * scaled;
        y = y / length * scaled;
    }

    float WrapAngle(float angle)
    {
        float const tau = 6.28318531f;
        angle = std::fmod(angle, tau);
        return angle < 0.0f ? angle + tau : angle;
    }

    float AngleBetween(float a, float b)
    {
        float const pi = 3.14159265f;
        float difference = WrapAngle(a - b);
        return difference > pi ? 6.28318531f - difference : difference;
    }

    bool IsActive(PadState const& pad)
    {
        return pad.buttons != 0 || std::fabs(pad.lx) > ACTIVITY || std::fabs(pad.ly) > ACTIVITY || std::fabs(pad.rx) > ACTIVITY ||
            std::fabs(pad.ry) > ACTIVITY || pad.lt > TRIGGER_PRESSED || pad.rt > TRIGGER_PRESSED;
    }

    void LoadXInput()
    {
        for (char const* name : { "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll" })
            if (HMODULE module = LoadLibraryA(name))
            {
                s_xinputGetState = reinterpret_cast<XInputGetState_t>(GetProcAddress(module, "XInputGetState"));
                if (s_xinputGetState)
                {
                    Log("controller: %s loaded", name);
                    return;
                }
            }
        Log("controller: no XInput library; Xbox controllers off");
    }

    float StickAxis(SHORT value)
    {
        return Clamp(float(value) / 32767.0f, -1.0f, 1.0f);
    }

    bool ReadXInput(PadState& pad)
    {
        if (!s_xinputGetState)
            return false;
        DWORD const now = GetTickCount();
        bool const rescan = now - s_xinputScanAt > XINPUT_RESCAN_MS;
        if (rescan)
            s_xinputScanAt = now;
        bool found = false;
        for (DWORD index = 0; index < XUSER_MAX_COUNT; ++index)
        {
            if (!s_xinputConnected[index] && !rescan)
                continue;
            XINPUT_STATE state = {};
            bool const connected = s_xinputGetState(index, &state) == ERROR_SUCCESS;
            if (connected != s_xinputConnected[index])
                Log("controller: XInput slot %lu %s", index, connected ? "connected" : "disconnected");
            s_xinputConnected[index] = connected;
            if (!connected || found)
                continue;
            XINPUT_GAMEPAD const& g = state.Gamepad;
            pad.lx = StickAxis(g.sThumbLX);
            pad.ly = StickAxis(g.sThumbLY);
            pad.rx = StickAxis(g.sThumbRX);
            pad.ry = StickAxis(g.sThumbRY);
            pad.lt = float(g.bLeftTrigger) / 255.0f;
            pad.rt = float(g.bRightTrigger) / 255.0f;
            WORD const w = g.wButtons;
            uint32_t b = 0;
            if (w & XINPUT_GAMEPAD_A) b |= BUTTON_A;
            if (w & XINPUT_GAMEPAD_B) b |= BUTTON_B;
            if (w & XINPUT_GAMEPAD_X) b |= BUTTON_X;
            if (w & XINPUT_GAMEPAD_Y) b |= BUTTON_Y;
            if (w & XINPUT_GAMEPAD_LEFT_SHOULDER) b |= BUTTON_LB;
            if (w & XINPUT_GAMEPAD_RIGHT_SHOULDER) b |= BUTTON_RB;
            if (w & XINPUT_GAMEPAD_BACK) b |= BUTTON_VIEW;
            if (w & XINPUT_GAMEPAD_START) b |= BUTTON_MENU;
            if (w & XINPUT_GAMEPAD_LEFT_THUMB) b |= BUTTON_L3;
            if (w & XINPUT_GAMEPAD_RIGHT_THUMB) b |= BUTTON_R3;
            if (w & XINPUT_GAMEPAD_DPAD_UP) b |= BUTTON_UP;
            if (w & XINPUT_GAMEPAD_DPAD_DOWN) b |= BUTTON_DOWN;
            if (w & XINPUT_GAMEPAD_DPAD_LEFT) b |= BUTTON_LEFT;
            if (w & XINPUT_GAMEPAD_DPAD_RIGHT) b |= BUTTON_RIGHT;
            pad.buttons = b;
            found = true;
        }
        return found;
    }

    float SonyAxis(uint8_t value)
    {
        return Clamp((float(value) - 128.0f) / 127.0f, -1.0f, 1.0f);
    }

    uint32_t SonyButtons(uint8_t face, uint8_t shoulders, uint8_t system)
    {
        uint32_t b = 0;
        switch (face & 0x0F)
        {
            case 0: b |= BUTTON_UP; break;
            case 1: b |= BUTTON_UP | BUTTON_RIGHT; break;
            case 2: b |= BUTTON_RIGHT; break;
            case 3: b |= BUTTON_DOWN | BUTTON_RIGHT; break;
            case 4: b |= BUTTON_DOWN; break;
            case 5: b |= BUTTON_DOWN | BUTTON_LEFT; break;
            case 6: b |= BUTTON_LEFT; break;
            case 7: b |= BUTTON_UP | BUTTON_LEFT; break;
            default: break;
        }
        if (face & 0x10) b |= BUTTON_X;
        if (face & 0x20) b |= BUTTON_A;
        if (face & 0x40) b |= BUTTON_B;
        if (face & 0x80) b |= BUTTON_Y;
        if (shoulders & 0x01) b |= BUTTON_LB;
        if (shoulders & 0x02) b |= BUTTON_RB;
        if (shoulders & 0x10) b |= BUTTON_VIEW;
        if (shoulders & 0x20) b |= BUTTON_MENU;
        if (shoulders & 0x40) b |= BUTTON_L3;
        if (shoulders & 0x80) b |= BUTTON_R3;
        if (system & 0x01) b |= BUTTON_HOME;
        return b;
    }

    bool ParseSonyReport(uint8_t const* report, DWORD length, bool dualSense, PadState& pad)
    {
        int base = 0;
        bool extended = false;
        if (report[0] == 0x01 && dualSense && length >= 64)
            base = 1, extended = true;
        else if (report[0] == 0x31 && dualSense && length >= 12)
            base = 2, extended = true;
        else if (report[0] == 0x11 && !dualSense && length >= 13)
            base = 3;
        else if (report[0] == 0x01 && length >= 10)
            base = 1;
        else
            return false;

        pad.lx = SonyAxis(report[base]);
        pad.ly = -SonyAxis(report[base + 1]);
        pad.rx = SonyAxis(report[base + 2]);
        pad.ry = -SonyAxis(report[base + 3]);
        if (extended)
        {
            pad.lt = float(report[base + 4]) / 255.0f;
            pad.rt = float(report[base + 5]) / 255.0f;
            pad.buttons = SonyButtons(report[base + 7], report[base + 8], report[base + 9]);
        }
        else
        {
            pad.buttons = SonyButtons(report[base + 4], report[base + 5], report[base + 6]);
            pad.lt = float(report[base + 7]) / 255.0f;
            pad.rt = float(report[base + 8]) / 255.0f;
        }
        return true;
    }

    bool IsSonyPad(uint16_t vendor, uint16_t product, bool& dualSense)
    {
        if (vendor != SONY_VENDOR)
            return false;
        for (SonyModel const& model : SONY_MODELS)
            if (model.product == product)
            {
                dualSense = model.dualSense;
                return true;
            }
        return false;
    }

    HANDLE OpenSonyPad(bool& dualSense, USHORT& reportLength)
    {
        GUID hidGuid;
        HidD_GetHidGuid(&hidGuid);
        HDEVINFO devices = SetupDiGetClassDevsW(&hidGuid, nullptr, nullptr, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
        if (devices == INVALID_HANDLE_VALUE)
            return nullptr;
        HANDLE found = nullptr;
        SP_DEVICE_INTERFACE_DATA iface = { sizeof(iface) };
        for (DWORD index = 0; !found && SetupDiEnumDeviceInterfaces(devices, nullptr, &hidGuid, index, &iface); ++index)
        {
            DWORD needed = 0;
            SetupDiGetDeviceInterfaceDetailW(devices, &iface, nullptr, 0, &needed, nullptr);
            if (!needed)
                continue;
            std::vector<uint8_t> buffer(needed);
            auto* detail = reinterpret_cast<SP_DEVICE_INTERFACE_DETAIL_DATA_W*>(buffer.data());
            detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
            if (!SetupDiGetDeviceInterfaceDetailW(devices, &iface, detail, needed, nullptr, nullptr))
                continue;

            HANDLE probe = CreateFileW(detail->DevicePath, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
            if (probe == INVALID_HANDLE_VALUE)
                continue;
            HIDD_ATTRIBUTES attributes = { sizeof(attributes) };
            bool const sony = HidD_GetAttributes(probe, &attributes) && IsSonyPad(attributes.VendorID, attributes.ProductID, dualSense);
            CloseHandle(probe);
            if (!sony)
                continue;

            HANDLE device = CreateFileW(detail->DevicePath, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                OPEN_EXISTING, 0, nullptr);
            if (device == INVALID_HANDLE_VALUE)
                device = CreateFileW(detail->DevicePath, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
            if (device == INVALID_HANDLE_VALUE)
                continue;

            PHIDP_PREPARSED_DATA preparsed = nullptr;
            HIDP_CAPS caps = {};
            bool gamepad = false;
            if (HidD_GetPreparsedData(device, &preparsed))
            {
                gamepad = HidP_GetCaps(preparsed, &caps) == HIDP_STATUS_SUCCESS && caps.UsagePage == 0x01 &&
                    (caps.Usage == 0x05 || caps.Usage == 0x04);
                HidD_FreePreparsedData(preparsed);
            }
            if (!gamepad)
            {
                CloseHandle(device);
                continue;
            }
            reportLength = caps.InputReportByteLength;
            found = device;
            Log("controller: %s found (product %04x, reports of %u bytes)", dualSense ? "DualSense" : "DualShock 4",
                attributes.ProductID, unsigned(reportLength));
        }
        SetupDiDestroyDeviceInfoList(devices);
        return found;
    }

    DWORD WINAPI ReadSonyPads(LPVOID)
    {
        for (;;)
        {
            bool dualSense = false;
            USHORT reportLength = 0;
            HANDLE device = OpenSonyPad(dualSense, reportLength);
            if (!device)
            {
                Sleep(SONY_RESCAN_MS);
                continue;
            }
            std::vector<uint8_t> report(reportLength > 0 ? reportLength : 128);
            for (;;)
            {
                DWORD read = 0;
                if (!ReadFile(device, report.data(), DWORD(report.size()), &read, nullptr) || read == 0)
                    break;
                PadState pad;
                if (!ParseSonyReport(report.data(), read, dualSense, pad))
                    continue;
                std::lock_guard<std::mutex> lock(s_sonyLock);
                s_sonyState = pad;
                s_sonyConnected = true;
            }
            CloseHandle(device);
            {
                std::lock_guard<std::mutex> lock(s_sonyLock);
                s_sonyConnected = false;
                s_sonyState = PadState();
            }
            Log("controller: PlayStation controller disconnected");
            Sleep(SONY_RESCAN_MS);
        }
    }

    bool ReadSony(PadState& pad)
    {
        std::lock_guard<std::mutex> lock(s_sonyLock);
        if (!s_sonyConnected)
            return false;
        pad = s_sonyState;
        return true;
    }

    PadState ReadPadState()
    {
        if (s_simulating)
            return s_simulated;
        PadState xbox, sony;
        bool const hasXbox = ReadXInput(xbox);
        bool const hasSony = ReadSony(sony);
        if (hasSony && IsActive(sony))
            s_kind = PadKind::PlayStation;
        else if (hasXbox && IsActive(xbox))
            s_kind = PadKind::Xbox;
        else if (s_kind == PadKind::PlayStation && !hasSony)
            s_kind = hasXbox ? PadKind::Xbox : PadKind::None;
        else if (s_kind == PadKind::Xbox && !hasXbox)
            s_kind = hasSony ? PadKind::PlayStation : PadKind::None;
        else if (s_kind == PadKind::None)
            s_kind = hasSony ? PadKind::PlayStation : (hasXbox ? PadKind::Xbox : PadKind::None);

        if (hasSony && hasXbox)
            return s_kind == PadKind::PlayStation ? sony : xbox;
        if (hasSony)
            return sony;
        if (hasXbox)
            return xbox;
        return PadState();
    }

    void StampInputTime()
    {
        *reinterpret_cast<uint32_t*>(VAR_INPUT_TIME) = reinterpret_cast<ClientTime_t>(FUN_CLIENT_TIME)();
    }

    PadState ReadPad()
    {
        PadState const pad = ReadPadState();
        if (IsActive(pad))
        {
            s_padActiveAt = GetTickCount();
            StampInputTime();
        }
        if (IsActive(pad) && !s_padInUse && s_kind != PadKind::None)
        {
            s_padInUse = true;
            s_mouseTravel = 0;
            s_mouseKnown = false;
        }
        return pad;
    }

    PadKind ShownKind()
    {
        return s_padInUse ? s_kind : PadKind::None;
    }

    char const* KindName(PadKind kind)
    {
        return kind == PadKind::PlayStation ? "ps" : (kind == PadKind::Xbox ? "xbox" : nullptr);
    }

    char const* KindLabel(PadKind kind)
    {
        return KindName(kind) ? KindName(kind) : "none";
    }

    bool PushGlobalFunction(void* L, char const* name)
    {
        Lua::pushstring(L, name);
        Lua::gettable(L, Lua::GLOBALSINDEX);
        if (Lua::type(L, -1) == Lua::TFUNCTION)
            return true;
        Lua::settop(L, -2);
        return false;
    }

    void CallLua(void* L, char const* name, int args)
    {
        if (Lua::pcall(L, args, 0, 0) != 0)
        {
            char const* error = Lua::tostring(L, -1);
            Log("controller: %s failed: %s", name, error ? error : "?");
        }
    }

    void SendButton(void* L, int index, bool down)
    {
        int const top = Lua::gettop(L);
        if (PushGlobalFunction(L, "HoAController_OnButton"))
        {
            Lua::pushstring(L, BUTTON_NAMES[index]);
            Lua::pushboolean(L, down ? 1 : 0);
            CallLua(L, "HoAController_OnButton", 2);
        }
        Lua::settop(L, top);
    }

    void SendKind(void* L)
    {
        int const top = Lua::gettop(L);
        if (PushGlobalFunction(L, "HoAController_OnDevice"))
        {
            if (char const* name = KindName(ShownKind()))
                Lua::pushstring(L, name);
            else
                Lua::pushnil(L);
            CallLua(L, "HoAController_OnDevice", 1);
        }
        Lua::settop(L, top);
    }

    uint32_t ZoomClock()
    {
        return reinterpret_cast<ClientTime_t>(FUN_CLIENT_TIME)();
    }

    float ZoomSpeed()
    {
        uintptr_t const cvar = *reinterpret_cast<uintptr_t*>(VAR_ZOOM_SPEED_CVAR);
        float const speed = cvar ? *reinterpret_cast<float*>(cvar + OFF_CVAR_FLOAT) : 0.0f;
        return speed > 0.0f ? speed : ZOOM_DEFAULT_SPEED;
    }

    int ZoomIndex(bool zoomIn)
    {
        return zoomIn ? 0 : 1;
    }

    uint32_t& ZoomEnd(void* camera, bool zoomIn)
    {
        return *reinterpret_cast<uint32_t*>(reinterpret_cast<uintptr_t>(camera) + OFF_CAMERA_ZOOM_END + 4 * ZoomIndex(zoomIn));
    }

    bool ZoomRunning(void* camera, bool zoomIn)
    {
        uint32_t const flags = *reinterpret_cast<uint32_t*>(reinterpret_cast<uintptr_t>(camera) + OFF_CAMERA_ZOOM_FLAGS);
        return (flags & (1u << (2 * ZoomIndex(zoomIn)))) != 0 && ZoomEnd(camera, zoomIn) != 0;
    }

    void ZoomBy(void* camera, bool zoomIn, float yards, uint32_t now)
    {
        reinterpret_cast<CameraZoom_t>(zoomIn ? FUN_CAMERA_ZOOM_IN : FUN_CAMERA_ZOOM_OUT)(camera, yards, now);
    }

    void ReleaseZoom(void* camera, uint32_t now)
    {
        if (ZoomRunning(camera, s_zoom.zoomIn))
        {
            uint32_t const stopAt = int(s_zoom.notchEnd - now) > 0 ? s_zoom.notchEnd : now;
            uint32_t& end = ZoomEnd(camera, s_zoom.zoomIn);
            if (int(end - stopAt) > 0)
                end = stopAt;
        }
        s_zoom.held = false;
    }

    void Zoom(void* camera, float input)
    {
        float const strength = std::fabs(input);
        bool const zoomIn = input > 0.0f;
        uint32_t const now = ZoomClock();
        if (s_zoom.held && (strength < ZOOM_THRESHOLD || s_zoom.zoomIn != zoomIn))
            ReleaseZoom(camera, now);
        if (strength < ZOOM_THRESHOLD)
            return;
        if (!s_zoom.held)
        {
            ZoomBy(camera, zoomIn, ZOOM_STEP_YARDS, now);
            s_zoom.held = true;
            s_zoom.zoomIn = zoomIn;
            s_zoom.notchEnd = now + uint32_t(ZOOM_STEP_YARDS / ZoomSpeed() * 1000.0f);
            return;
        }
        if (!ZoomRunning(camera, zoomIn) || int(ZoomEnd(camera, zoomIn) - now) < ZOOM_LEAD_MS)
            ZoomBy(camera, zoomIn, ZoomSpeed() * ZOOM_EXTEND_MS / 1000.0f, now);
    }

    int __fastcall Lua_GetType(void* L)
    {
        if (char const* name = KindName(ShownKind()))
            Lua::pushstring(L, name);
        else
            Lua::pushnil(L);
        return 1;
    }

    int __fastcall Lua_SetCapture(void* L)
    {
        s_capture = Lua::toboolean(L, 1) != 0;
        return 0;
    }

    int __fastcall Lua_Simulate(void* L)
    {
        if (Lua::type(L, 1) == Lua::TNIL)
        {
            s_simulating = false;
            s_simulated = PadState();
            return 0;
        }
        s_simulating = true;
        s_kind = Lua::toboolean(L, 8) ? PadKind::PlayStation : PadKind::Xbox;
        s_simulated.lx = Clamp(float(Lua::tonumber(L, 1)), -1.0f, 1.0f);
        s_simulated.ly = Clamp(float(Lua::tonumber(L, 2)), -1.0f, 1.0f);
        s_simulated.rx = Clamp(float(Lua::tonumber(L, 3)), -1.0f, 1.0f);
        s_simulated.ry = Clamp(float(Lua::tonumber(L, 4)), -1.0f, 1.0f);
        s_simulated.lt = Clamp(float(Lua::tonumber(L, 5)), 0.0f, 1.0f);
        s_simulated.rt = Clamp(float(Lua::tonumber(L, 6)), 0.0f, 1.0f);
        s_simulated.buttons = uint32_t(Lua::tonumber(L, 7));
        return 0;
    }

    bool GameHasFocus()
    {
        return s_window && GetForegroundWindow() == s_window;
    }

    bool ClientScreenRect(RECT& rect)
    {
        if (!GetClientRect(s_window, &rect))
            return false;
        POINT origin = { 0, 0 };
        ClientToScreen(s_window, &origin);
        OffsetRect(&rect, origin.x, origin.y);
        return rect.right > rect.left && rect.bottom > rect.top;
    }

    void SendMouseButton(bool right, bool down)
    {
        INPUT input = {};
        input.type = INPUT_MOUSE;
        input.mi.dwExtraInfo = INJECTED_INPUT;
        input.mi.dwFlags = right ? (down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP) : (down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
        SendInput(1, &input, sizeof(input));
    }

    void ReleaseMouseButtons()
    {
        if (s_cursorLeftDown)
            SendMouseButton(false, false);
        if (s_cursorRightDown)
            SendMouseButton(true, false);
        s_cursorLeftDown = s_cursorRightDown = false;
    }

    bool GameCursorVisible()
    {
        auto* device = *reinterpret_cast<uint8_t**>(VAR_GX_DEVICE);
        return device && *reinterpret_cast<int*>(device + OFF_DEVICE_CURSOR_VISIBLE) != 0;
    }

    void SetGameCursorVisible(bool visible)
    {
        if (*reinterpret_cast<void**>(VAR_GX_DEVICE))
            reinterpret_cast<CursorSetVisible_t>(FUN_CURSOR_SET_VISIBLE)(visible ? 1 : 0);
    }

    void ShowHiddenCursor()
    {
        if (!s_cursorHidden)
            return;
        s_cursorHidden = false;
        SetGameCursorVisible(true);
    }

    void FlashCursor()
    {
        s_cursorFlashUntil = GetTickCount() + CURSOR_FLASH_MS;
        ShowHiddenCursor();
    }

    void UpdateCursorVisibility()
    {
        if (!s_padInUse || s_kind == PadKind::None || s_cursorMode || int(s_cursorFlashUntil - GetTickCount()) > 0)
        {
            ShowHiddenCursor();
            return;
        }
        if (GameCursorVisible())
            SetGameCursorVisible(false);
        s_cursorHidden = true;
    }

    void LeaveCursorMode()
    {
        ReleaseMouseButtons();
        if (s_cursorMode)
            Log("controller: cursor mode off");
        s_cursorMode = false;
    }

    void ToggleCursorMode()
    {
        if (s_cursorMode)
        {
            LeaveCursorMode();
            return;
        }
        if (!GameHasFocus())
            return;
        s_cursorMode = true;
        Log("controller: cursor mode on");
    }

    bool CursorButton(uint32_t bit, bool down)
    {
        if (!s_cursorMode || (bit != BUTTON_A && bit != BUTTON_X))
            return false;
        bool const right = bit == BUTTON_X;
        bool& held = right ? s_cursorRightDown : s_cursorLeftDown;
        if (down && GameHasFocus() && !held)
        {
            SendMouseButton(right, true);
            held = true;
        }
        else if (!down && held)
        {
            SendMouseButton(right, false);
            held = false;
        }
        return true;
    }

    void MoveCursor(PadState const& pad, float seconds)
    {
        float rx = pad.rx, ry = pad.ry;
        ApplyRadialDeadzone(rx, ry, s_options.lookDeadzone);
        RECT rect;
        if ((rx == 0.0f && ry == 0.0f) || !GameHasFocus() || !ClientScreenRect(rect))
            return;
        if (!s_cursorMode)
            Log("controller: cursor mode on");
        s_cursorMode = true;
        POINT cursor;
        GetCursorPos(&cursor);
        if (cursor.x != s_cursorSetX || cursor.y != s_cursorSetY)
        {
            s_cursorX = float(cursor.x);
            s_cursorY = float(cursor.y);
        }
        float const length = std::sqrt(rx * rx + ry * ry);
        float const speed = CURSOR_SCREENS_PER_SECOND * s_options.cursorSpeed * float(rect.bottom - rect.top) * seconds * length;
        s_cursorX = Clamp(s_cursorX + rx * speed, float(rect.left), float(rect.right - 1));
        s_cursorY = Clamp(s_cursorY - ry * speed, float(rect.top), float(rect.bottom - 1));
        s_cursorSetX = LONG(std::lround(s_cursorX));
        s_cursorSetY = LONG(std::lround(s_cursorY));
        SetCursorPos(s_cursorSetX, s_cursorSetY);
    }

    void Tick();

    int __fastcall Lua_Frame(void*)
    {
        static bool ticking = false;
        if (ticking)
            return 0;
        ticking = true;
        s_frameTickAt = GetTickCount();
        Tick();
        ticking = false;
        return 0;
    }

    int __fastcall Lua_SetOption(void* L)
    {
        char const* name = Lua::tostring(L, 1);
        if (!name)
            return 0;
        float const value = float(Lua::tonumber(L, 2));
        if (!std::strcmp(name, "yawSpeed"))
            s_options.yawSpeed = Clamp(value, 0.25f, 3.0f);
        else if (!std::strcmp(name, "pitchSpeed"))
            s_options.pitchSpeed = Clamp(value, 0.25f, 3.0f);
        else if (!std::strcmp(name, "cursorSpeed"))
            s_options.cursorSpeed = Clamp(value, 0.25f, 3.0f);
        else if (!std::strcmp(name, "deadzone"))
        {
            s_options.moveDeadzone = Clamp(value, 0.05f, 0.6f);
            s_options.lookDeadzone = s_options.moveDeadzone * LOOK_DEADZONE / MOVE_DEADZONE;
        }
        else if (!std::strcmp(name, "invertPitch"))
            s_options.invertPitch = Lua::toboolean(L, 2) != 0;
        return 0;
    }

    int __fastcall Lua_GetConnected(void* L)
    {
        if (char const* name = KindName(s_kind))
            Lua::pushstring(L, name);
        else
            Lua::pushnil(L);
        return 1;
    }

    int __fastcall Lua_GetSticks(void* L)
    {
        Lua::pushnumber(L, double(s_lastPad.lx));
        Lua::pushnumber(L, double(s_lastPad.ly));
        Lua::pushnumber(L, double(s_lastPad.rx));
        Lua::pushnumber(L, double(s_lastPad.ry));
        return 4;
    }

    int __fastcall Lua_SetScrollMode(void* L)
    {
        s_scrollMode = Lua::toboolean(L, 1) != 0;
        return 0;
    }

    int __fastcall Lua_CursorMode(void* L)
    {
        Lua::pushboolean(L, s_cursorMode ? 1 : 0);
        return 1;
    }

    void RegisterLuaFunctions(void* L)
    {
        int const top = Lua::gettop(L);
        bool const present = PushGlobalFunction(L, "HoAController_GetType");
        Lua::settop(L, top);
        if (present)
            return;
        Lua::Register("HoAController_GetType", &Lua_GetType);
        Lua::Register("HoAController_SetCapture", &Lua_SetCapture);
        Lua::Register("HoAController_Simulate", &Lua_Simulate);
        Lua::Register("HoAController_CursorMode", &Lua_CursorMode);
        Lua::Register("HoAController_Frame", &Lua_Frame);
        Lua::Register("HoAController_SetOption", &Lua_SetOption);
        Lua::Register("HoAController_GetConnected", &Lua_GetConnected);
        Lua::Register("HoAController_GetSticks", &Lua_GetSticks);
        Lua::Register("HoAController_SetScrollMode", &Lua_SetScrollMode);
        RegisterInteractFunctions();
        RegisterBorderlessFunctions();
        RegisterCoopFunctions();
        RegisterKeyboardFunctions();
        s_reportedKind = PadKind::None;
        s_capture = false;
        LeaveCursorMode();
        Log("controller: Lua functions registered");
    }

    void* ActiveCamera()
    {
        auto* state = *reinterpret_cast<uint8_t**>(VAR_GAME_STATE);
        return state ? *reinterpret_cast<void**>(state + OFF_GAME_STATE_CAMERA) : nullptr;
    }

    void* InputController()
    {
        return *reinterpret_cast<void**>(VAR_INPUT_CONTROLLER);
    }

    uint32_t InputTime()
    {
        return *reinterpret_cast<uint32_t*>(VAR_INPUT_TIME);
    }

    bool ForwardHeld(void* controller)
    {
        return (*reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(controller) + OFF_INPUT_KEYS) & CONTROL_FORWARD) != 0;
    }

    void SetForward(void* controller, bool pressed)
    {
        if (pressed == s_moving && (!pressed || ForwardHeld(controller)))
            return;
        if (pressed && s_moving)
            Log("controller: forward was dropped by the client, pressing it again");
        s_moving = pressed;
        reinterpret_cast<SetControlBit_t>(FUN_SET_CONTROL_BIT)(controller, CONTROL_FORWARD, pressed ? 1 : 0, InputTime(), 0);
    }

    void ReleaseAll()
    {
        if (void* controller = InputController())
            SetForward(controller, false);
        s_moving = false;
        s_holdingCamera = false;
        LeaveCursorMode();
    }

    float* Field(void* base, uint32_t offset)
    {
        return reinterpret_cast<float*>(static_cast<uint8_t*>(base) + offset);
    }

    template <typename T>
    T At(void const* base, uint32_t offset)
    {
        return *reinterpret_cast<T const*>(static_cast<uint8_t const*>(base) + offset);
    }

    void UnstickForward(void* controller, void* movement, DWORD now)
    {
        bool const walking = (*reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(movement) + OFF_MOVEMENT_FLAGS) & MOVEFLAG_FORWARD) != 0;
        if (walking || !ForwardHeld(controller))
        {
            s_stalledSince = 0;
            return;
        }
        if (!s_stalledSince)
            s_stalledSince = now;
        if (now - s_stalledSince < STALLED_FORWARD_MS || now - s_stalledRetryAt < STALLED_RETRY_MS)
            return;
        s_stalledRetryAt = now;
        s_stalledSince = 0;
        auto* keys = reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(controller) + OFF_INPUT_KEYS);
        uint32_t const flags = *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(movement) + OFF_MOVEMENT_FLAGS);
        uint32_t const before = *keys;
        if ((*keys & FORWARD_AXIS_NOTE) && !(flags & MOVEFLAG_FORWARD_AXIS))
            *keys &= ~FORWARD_AXIS_NOTE;
        using InputMove_t = void(__fastcall*)(void* self, void* edx, uint32_t time, int apply);
        reinterpret_cast<InputMove_t>(FUN_INPUT_MOVE)(controller, nullptr, InputTime(), 1);
        FlashCursor();
        Log("controller: forward held but the hero stood still, showed the cursor: keys %#x -> %#x, flags %#x -> %#x", before, *keys, flags,
            *reinterpret_cast<uint32_t*>(static_cast<uint8_t*>(movement) + OFF_MOVEMENT_FLAGS));
    }

    void Move(PadState const& pad, void* player, void* camera, void* controller)
    {
        float lx = pad.lx, ly = pad.ly;
        ApplyRadialDeadzone(lx, ly, s_options.moveDeadzone);
        void* movement = *reinterpret_cast<void**>(static_cast<uint8_t*>(player) + OFF_UNIT_MOVEMENT);
        if ((lx == 0.0f && ly == 0.0f) || !movement)
        {
            SetForward(controller, false);
            s_holdingCamera = false;
            return;
        }

        float* facing = Field(movement, OFF_MOVEMENT_FACING);
        float* cameraYaw = Field(camera, OFF_CAMERA_YAW);
        DWORD const now = GetTickCount();
        if (!s_holdingCamera)
        {
            s_heldWorldYaw = WrapAngle(*facing + *cameraYaw);
            s_holdingCamera = true;
            s_sentFacing = *facing;
            s_facingSentAt = now - FACING_SEND_MS;
        }
        float const wanted = WrapAngle(s_heldWorldYaw - std::atan2(lx, ly));
        if (AngleBetween(wanted, *facing) > FACING_EPSILON)
            reinterpret_cast<MovementSetFacing_t>(FUN_MOVEMENT_SET_FACING)(movement, wanted);
        float const unsent = AngleBetween(wanted, s_sentFacing);
        if (unsent > FACING_EPSILON && (now - s_facingSentAt >= FACING_SEND_MS || unsent > FACING_SNAP))
        {
            s_sentFacing = wanted;
            s_facingSentAt = now;
            reinterpret_cast<UnitSetFacing_t>(FUN_UNIT_SET_FACING)(player, InputTime(), wanted);
        }
        *cameraYaw = WrapAngle(s_heldWorldYaw - *facing);
        SetForward(controller, true);
        UnstickForward(controller, movement, now);
    }

    void Look(PadState const& pad, void* camera, float seconds)
    {
        float rx = pad.rx, ry = pad.ry;
        ApplyRadialDeadzone(rx, ry, s_options.lookDeadzone);
        float zoom = 0.0f;
        if (pad.lt >= TRIGGER_PRESSED)
        {
            float const dpad = ((pad.buttons & BUTTON_UP) ? 1.0f : 0.0f) - ((pad.buttons & BUTTON_DOWN) ? 1.0f : 0.0f);
            zoom = ry + dpad;
            ry = 0.0f;
        }
        Zoom(camera, zoom);
        if (s_options.invertPitch)
            ry = -ry;
        if (rx == 0.0f && ry == 0.0f)
            return;
        float const turn = -rx * std::fabs(rx) * CAMERA_YAW_RADIANS_PER_SECOND * s_options.yawSpeed * seconds;
        float* cameraYaw = Field(camera, OFF_CAMERA_YAW);
        if (s_holdingCamera)
            s_heldWorldYaw = WrapAngle(s_heldWorldYaw + turn);
        else
            *cameraYaw = WrapAngle(*cameraYaw + turn);
        if (ry != 0.0f)
            reinterpret_cast<CameraRotate_t>(FUN_CAMERA_ROTATE)(camera, 0.0f, -ry * std::fabs(ry) * CAMERA_PITCH_UNITS_PER_SECOND * s_options.pitchSpeed * seconds);
    }

    void Recenter(void* player, void* camera)
    {
        void* movement = *reinterpret_cast<void**>(static_cast<uint8_t*>(player) + OFF_UNIT_MOVEMENT);
        if (s_holdingCamera && movement)
            s_heldWorldYaw = *Field(movement, OFF_MOVEMENT_FACING);
        else
            *Field(camera, OFF_CAMERA_YAW) = 0.0f;
    }

    void Report(PadState const& pad, void* player, void* camera)
    {
        DWORD const now = GetTickCount();
        if (now - s_debugAt < DEBUG_REPORT_MS || !IsActive(pad))
            return;
        s_debugAt = now;
        void* movement = *reinterpret_cast<void**>(static_cast<uint8_t*>(player) + OFF_UNIT_MOVEMENT);
        Log("controller: %s stick %.2f,%.2f look %.2f,%.2f buttons %#x, capture %d, facing %.3f, camera %.3f (held world %.3f)", KindLabel(s_kind),
            pad.lx, pad.ly, pad.rx, pad.ry, pad.buttons, s_capture ? 1 : 0,
            movement ? *reinterpret_cast<float*>(static_cast<uint8_t*>(movement) + OFF_MOVEMENT_FACING) : -1.0f,
            *Field(camera, OFF_CAMERA_YAW), s_holdingCamera ? s_heldWorldYaw : -1.0f);
    }

    float SecondsSinceLastTick()
    {
        static LARGE_INTEGER frequency = {};
        static LARGE_INTEGER last = {};
        LARGE_INTEGER now;
        QueryPerformanceCounter(&now);
        if (!frequency.QuadPart)
        {
            QueryPerformanceFrequency(&frequency);
            last = now;
        }
        float const seconds = float(double(now.QuadPart - last.QuadPart) / double(frequency.QuadPart));
        last = now;
        return Clamp(seconds, 0.0f, 0.1f);
    }

    void Tick()
    {
        float const seconds = SecondsSinceLastTick();

        void* L = LuaState();
        if (!L)
            return;
        RegisterLuaFunctions(L);
        TickLoginRecovery(L);

        PadState pad = ReadPad();
        s_lastPad = pad;
        if (pad.lt >= TRIGGER_PRESSED)
            pad.buttons |= BUTTON_LT;
        if (pad.rt >= TRIGGER_PRESSED)
            pad.buttons |= BUTTON_RT;

        if (ShownKind() != s_reportedKind)
        {
            s_reportedKind = ShownKind();
            Log("controller: prompts for %s", KindLabel(s_reportedKind));
            SendKind(L);
        }

        void* player = reinterpret_cast<ResolveUnitToken_t>(FUN_RESOLVE_UNIT_TOKEN)("player");
        void* camera = player ? ActiveCamera() : nullptr;
        void* controller = InputController();
        bool const inWorld = player && camera && controller;

        uint32_t const changed = pad.buttons ^ s_previousButtons;
        s_previousButtons = pad.buttons;
        if (!s_capture || (changed & pad.buttons & DPAD_BUTTONS))
            LeaveCursorMode();
        for (int index = 0; index < BUTTON_COUNT; ++index)
        {
            uint32_t const bit = 1u << index;
            if (!(changed & bit))
                continue;
            bool const down = (pad.buttons & bit) != 0;
            if (CursorButton(bit, down))
                continue;
            if (bit == BUTTON_A && down && inWorld && !s_capture)
                reinterpret_cast<PlayerJump_t>(FUN_PLAYER_JUMP)(player, InputTime());
            if (bit == BUTTON_R3 && down && inWorld && !s_capture)
                Recenter(player, camera);
            if (bit == BUTTON_R3 && down && s_capture)
                ToggleCursorMode();
            SendButton(L, index, down);
        }

        if (inWorld && !s_wasInWorld)
            FlashCursor();
        s_wasInWorld = inWorld;
        UpdateCursorVisibility();
        if (!inWorld)
        {
            s_moving = false;
            s_holdingCamera = false;
            s_zoom.held = false;
            return;
        }
        if (s_kind == PadKind::None && !s_simulating)
        {
            if (s_moving)
                ReleaseAll();
            s_zoom.held = false;
            return;
        }
        Move(pad, player, camera, controller);
        if (s_capture)
        {
            s_zoom.held = false;
            if (!s_scrollMode || s_cursorMode)
                MoveCursor(pad, seconds);
        }
        else
            Look(pad, camera, seconds);
        Report(pad, player, camera);
    }

    bool IsMouseTravel(LPARAM lParam)
    {
        POINT point = { GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam) };
        ClientToScreen(s_window, &point);
        if (point.x == s_cursorSetX && point.y == s_cursorSetY)
            return false;
        DWORD const now = GetTickCount();
        if (now - s_mouseAt > MOUSE_TRAVEL_WINDOW_MS)
            s_mouseTravel = 0;
        s_mouseAt = now;
        if (s_mouseKnown)
            s_mouseTravel += std::abs(point.x - s_mouseX) + std::abs(point.y - s_mouseY);
        s_mouseKnown = true;
        s_mouseX = point.x;
        s_mouseY = point.y;
        return s_mouseTravel > MOUSE_TRAVEL_PIXELS;
    }

    bool IsKeyboardOrMouse(UINT message, LPARAM lParam)
    {
        if (!s_padInUse)
            return false;
        switch (message)
        {
            case WM_KEYDOWN:
            case WM_SYSKEYDOWN:
                return true;
            case WM_LBUTTONDOWN:
            case WM_RBUTTONDOWN:
            case WM_MBUTTONDOWN:
            case WM_XBUTTONDOWN:
            case WM_MOUSEWHEEL:
                return GetMessageExtraInfo() != INJECTED_INPUT;
            case WM_MOUSEMOVE:
                if (GetTickCount() - s_padActiveAt < MOUSE_GRACE_MS)
                {
                    s_mouseKnown = false;
                    s_mouseTravel = 0;
                    return false;
                }
                return GetMessageExtraInfo() != INJECTED_INPUT && IsMouseTravel(lParam);
            default:
                return false;
        }
    }

    void UseKeyboardAndMouse()
    {
        s_padInUse = false;
        LeaveCursorMode();
        ShowHiddenCursor();
    }

    LRESULT CALLBACK ControllerWindowProc(HWND window, UINT message, WPARAM wParam, LPARAM lParam)
    {
        if (!s_timerStarted)
        {
            s_timerStarted = SetTimer(window, TIMER_ID, TICK_MS, nullptr) != 0;
            Log("controller: tick timer %s", s_timerStarted ? "started" : "FAILED");
        }
        if (message == WM_TIMER && wParam == TIMER_ID)
        {
            if (GetTickCount() - s_frameTickAt > FRAME_FALLBACK_MS)
                Tick();
            return 0;
        }
        if (message == WM_ACTIVATEAPP && !wParam)
            ReleaseAll();
        if (IsKeyboardOrMouse(message, lParam))
        {
            Log("controller: keyboard and mouse (message %#x, wParam %#x)", message, unsigned(wParam));
            UseKeyboardAndMouse();
        }
        return s_unicodeWindow ? CallWindowProcW(s_originalProc, window, message, wParam, lParam)
                               : CallWindowProcA(s_originalProc, window, message, wParam, lParam);
    }
}

void StartController(HWND window)
{
    if (s_window)
        return;
    s_window = window;
    LoadXInput();
    s_unicodeWindow = IsWindowUnicode(window) != 0;
    LONG_PTR const proc = reinterpret_cast<LONG_PTR>(&ControllerWindowProc);
    s_originalProc = reinterpret_cast<WNDPROC>(s_unicodeWindow ? SetWindowLongPtrW(window, GWLP_WNDPROC, proc)
                                                               : SetWindowLongPtrA(window, GWLP_WNDPROC, proc));
    if (!s_originalProc)
    {
        Log("controller: could not hook the game window");
        return;
    }
    PostMessageW(window, WM_NULL, 0, 0);
    if (HANDLE reader = CreateThread(nullptr, 0, &ReadSonyPads, nullptr, 0, nullptr))
        CloseHandle(reader);
    Log("controller: started on the game window");
}
