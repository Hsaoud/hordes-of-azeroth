#pragma once

#include <windows.h>

void Log(char const* format, ...);
void StartController(HWND window);
void PrepareBorderless();
void StartBorderless(HWND window);
void RegisterBorderlessFunctions();
void RegisterInteractFunctions();
void RegisterCoopFunctions();
void TickLoginRecovery(void* L);
void RegisterKeyboardFunctions();
