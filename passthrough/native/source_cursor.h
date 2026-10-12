#pragma once
#include <windows.h>
#include <atomic>
#include <cstdint>
#include "source_commands.h"

// A thread-local post-window-message hook: never subclass Source or swallow
// messages. SetCursor in Present can be overwritten by the next WM_SETCURSOR.
namespace source_cursor {
inline std::atomic<HWND> window{nullptr};
inline std::atomic<bool> hide{false};
inline std::atomic<ULONGLONG> updated{0};
inline HHOOK hook=nullptr;
using Verify=bool(*)();
inline std::atomic<Verify> allow{nullptr};
inline std::atomic<Verify> wheelAllow{nullptr};
// Raw WHEEL_DELTA units; Python preserves fractional high-resolution scrolls.
inline std::atomic<int32_t> wheelUnits{0};
inline LRESULT CALLBACK after_message(int code,WPARAM wp,LPARAM lp) {
    const LRESULT result=CallNextHookEx(nullptr,code,wp,lp);
    if(code<0 || !lp)return result;
    const auto& message=*reinterpret_cast<const CWPRETSTRUCT*>(lp);
    if(message.hwnd==window.load())source_commands::handle(message);
    if(message.hwnd!=window.load() || GetForegroundWindow()!=message.hwnd)return result;
    const auto now=GetTickCount64(),stamp=updated.load();
    const bool fresh=now>=stamp && now-stamp<1000;
    if(message.message==WM_MOUSEWHEEL) {
        const auto verifyWheel=wheelAllow.load();
        if(fresh && verifyWheel && verifyWheel())wheelUnits.fetch_add(GET_WHEEL_DELTA_WPARAM(message.wParam));
        return result;
    }
    if(message.message!=WM_SETCURSOR || LOWORD(message.lParam)!=HTCLIENT)return result;
    const auto verify=allow.load();
    if(hide.load() && now>=stamp && now-stamp<1000 && verify && verify())SetCursor(nullptr);
    return result;
}
inline void remove() {
    if(window.load()){RemovePropW(window.load(),source_commands::ready);RemovePropW(window.load(),source_commands::receipt);}
    hide=false;updated=0;wheelAllow=nullptr;
    if(hook){UnhookWindowsHookEx(hook);hook=nullptr;}
    window=nullptr;
}
inline bool publish(HWND hwnd,bool hidden,bool (*verified)(),bool (*wheelVerified)()=nullptr) {
    if(window.load()!=hwnd)remove();
    if(!hook) {
        DWORD pid=0;const DWORD thread=GetWindowThreadProcessId(hwnd,&pid);
        if(!thread || pid!=GetCurrentProcessId())return false;
        // Unhook does not wait for an in-flight UI callback. Pin our own DLL
        // until process exit so hot unload cannot unmap a returning callback.
        HMODULE owner=nullptr;
        if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
            reinterpret_cast<LPCWSTR>(&after_message),&owner))return false;
        allow=verified;window=hwnd;
        hook=SetWindowsHookExW(WH_CALLWNDPROCRET,after_message,nullptr,thread);
        if(!hook){window=nullptr;return false;}
        SetPropW(hwnd,source_commands::ready,reinterpret_cast<HANDLE>(1));
    }
    wheelAllow=wheelVerified?wheelVerified:verified;
    hide=hidden;updated=GetTickCount64();return true;
}
}
