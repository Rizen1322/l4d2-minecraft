#pragma once
#include <windows.h>
#include <atomic>

// A thread-local post-window-message hook: never subclass Source or swallow
// messages. SetCursor in Present can be overwritten by the next WM_SETCURSOR.
namespace source_cursor {
inline std::atomic<HWND> window{nullptr};
inline std::atomic<bool> hide{false};
inline std::atomic<ULONGLONG> updated{0};
inline HHOOK hook=nullptr;
using Verify=bool(*)();
inline std::atomic<Verify> allow{nullptr};
inline LRESULT CALLBACK after_message(int code,WPARAM wp,LPARAM lp) {
    const LRESULT result=CallNextHookEx(nullptr,code,wp,lp);
    if(code<0 || !lp)return result;
    const auto& message=*reinterpret_cast<const CWPRETSTRUCT*>(lp);
    if(message.message!=WM_SETCURSOR || LOWORD(message.lParam)!=HTCLIENT
        || message.hwnd!=window.load() || GetForegroundWindow()!=message.hwnd)return result;
    const auto now=GetTickCount64(),stamp=updated.load();
    const auto verify=allow.load();
    if(hide.load() && now>=stamp && now-stamp<1000 && verify && verify())SetCursor(nullptr);
    return result;
}
inline void remove() {
    hide=false;updated=0;
    if(hook){UnhookWindowsHookEx(hook);hook=nullptr;}
    window=nullptr;
}
inline bool publish(HWND hwnd,bool hidden,bool (*verified)()) {
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
    }
    hide=hidden;updated=GetTickCount64();return true;
}
}
