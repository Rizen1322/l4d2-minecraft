#pragma once
#include "source_camera.h"
#include <string>

// Public L4D2 VClient016 and VGUI_Surface031 API layouts:
// Lak3/l4d2-internal-base src/SDK/L4D2/Interfaces/{BaseClientDLL,VGuiSurface}.h
// Valve SDK CInput skips accumulation/recentering while ISurface's cursor is visible.
// A Windows ShowCursor call alone does not change that Source state.
namespace source_input {
inline void* client=nullptr;
inline void* surface=nullptr;
inline bool released=false;
inline bool pendingActivation=false;
inline void* acquire(const wchar_t* moduleName,const char* version) {
    HMODULE module=GetModuleHandleW(moduleName);
    auto factory=module?reinterpret_cast<void*(__cdecl*)(const char*,int*)>(GetProcAddress(module,"CreateInterface")):nullptr;
    return factory?factory(version,nullptr):nullptr;
}
inline bool mouse(bool active,bool focus=true) {
    if(!client)client=acquire(L"client.dll","VClient016");
    if(!surface)surface=acquire(L"vguimatsurface.dll","VGUI_Surface031");
    if(!source_camera::readable(client,sizeof(void*)) || !source_camera::readable(surface,sizeof(void*)))return false;
    auto ct=*reinterpret_cast<void***>(client),st=*reinterpret_cast<void***>(surface);
    if(!source_camera::readable(ct,16*sizeof(void*)) || !source_camera::readable(st,102*sizeof(void*)))return false;
    using Void=void(__thiscall*)(void*);
    using Flag=void(__thiscall*)(void*,bool);
    if(!active) {
        reinterpret_cast<Flag>(st[49])(surface,true); // SetCursorAlwaysVisible
        reinterpret_cast<Void>(st[58])(surface); // UnlockCursor
        reinterpret_cast<void(__thiscall*)(void*,unsigned long)>(st[48])(surface,2); // dc_arrow
        if(!released)reinterpret_cast<Void>(ct[15])(client); // IN_DeactivateMouse
        released=true;
    } else if(released || pendingActivation) {
        CURSORINFO previous{};previous.cbSize=sizeof(previous);
        const bool keepOutside=!focus && GetCursorInfo(&previous);
        reinterpret_cast<Flag>(st[49])(surface,false);
        // IN_ActivateMouse does not clear VGUI's arrow cursor. Leaving it visible
        // makes CInput skip MouseMove forever, even though it centers the pointer.
        reinterpret_cast<void(__thiscall*)(void*,unsigned long)>(st[48])(surface,1); // vgui::dc_none (dc_user is 0)
        if(focus)reinterpret_cast<Void>(st[59])(surface);
        if(focus)reinterpret_cast<Void>(ct[14])(client); // IN_ActivateMouse
        if(keepOutside)SetCursor(previous.hCursor);
        released=false;pendingActivation=!focus;
    }
    if(active && focus) {
        reinterpret_cast<Flag>(st[49])(surface,false);
        reinterpret_cast<Void>(st[58])(surface);
        reinterpret_cast<void(__thiscall*)(void*,unsigned long)>(st[48])(surface,1);
        reinterpret_cast<Void>(st[59])(surface);
    }
    return true;
}
inline void restore(){if(released)mouse(true,false);}
}
