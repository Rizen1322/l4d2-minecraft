#pragma once
#include <algorithm>
#include "source_camera.h"
#include <cstdio>

// Dispatch owned cfg names on Source's window thread. No extra game process,
// Steam initialization, arbitrary console text or render-thread engine writes.
namespace source_commands {
inline UINT message_id(){static const UINT id=RegisterWindowMessageW(L"L4D2MC.OwnedConfig.v1");return id;}
inline constexpr const wchar_t* ready=L"L4D2MC.CommandVersion";
inline constexpr const wchar_t* receipt=L"L4D2MC.CommandReceipt";
inline bool (*test_dispatch)(const char*)=nullptr;
inline bool valid(const wchar_t* name){
    if(wcsncmp(name,L"l4d2mc_",7)!=0)return false;
    size_t size=wcslen(name);if(size<=7 || size>96)return false;
    for(size_t i=7;i<size;++i)if(!((name[i]>=L'a'&&name[i]<=L'z')||(name[i]>=L'A'&&name[i]<=L'Z')||(name[i]>=L'0'&&name[i]<=L'9')||name[i]==L'_'))return false;
    return true;
}
inline bool execute(const wchar_t* cfg){
    if(!valid(cfg))return false;
    char text[110]="exec ";for(size_t i=0;i<wcslen(cfg);++i)text[5+i]=char(cfg[i]);
    if(test_dispatch)return test_dispatch(text);
    static void* engine=nullptr;
    if(!engine){auto module=GetModuleHandleW(L"engine.dll");auto factory=module?reinterpret_cast<void*(__cdecl*)(const char*,int*)>(GetProcAddress(module,"CreateInterface")):nullptr;engine=factory?factory("VEngineClient013",nullptr):nullptr;}
    if(!source_camera::readable(engine,sizeof(void*)))return false;
    auto table=*reinterpret_cast<void***>(engine);if(!source_camera::readable(table,107*sizeof(void*)))return false;
    // VEngineClient013 ClientCmd_Unrestricted (L4D2 layout) queues local console
    // input without CLIENTCMD_CAN_EXECUTE's restriction on exec. The payload is
    // still limited to owned cfg names above; no arbitrary commands are accepted.
    reinterpret_cast<void(__thiscall*)(void*,const char*)>(table[106])(engine,text);
    return true;
}
inline void handle(const CWPRETSTRUCT& event){
    if(event.message!=message_id() || !event.lParam || event.wParam>0xffff)return;
    wchar_t cfg[128]{};
    if(!GlobalGetAtomNameW(ATOM(event.wParam),cfg,128) || !execute(cfg))return;
    SetPropW(event.hwnd,receipt,reinterpret_cast<HANDLE>(event.lParam));
}
}
