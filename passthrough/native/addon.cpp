#include <windows.h>
#include "compositor.h"

extern "C" __declspec(dllexport) const char *NAME = "L4D2 Minecraft";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Composites a real Minecraft guest into local L4D2. Prototype.";

extern "C" __declspec(dllexport) bool AddonInit(HMODULE addon, HMODULE)
{
    // Provisional clip planes: calibrate before claiming correct occlusion.
    compositor::set_host_planes(7.0f, 30000.0f);
    return compositor::try_register(addon);
}

extern "C" __declspec(dllexport) void AddonUninit(HMODULE addon, HMODULE)
{
    compositor::unregister(addon);
}
