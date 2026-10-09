#include <windows.h>
#include <cstdio>
// A hidden private window exercises the real thread hook without changing focus.
static HWND testWindow=nullptr;
static HWND test_foreground(){return testWindow;}
#define GetForegroundWindow test_foreground
#include "native/source_cursor.h"
#undef GetForegroundWindow
static bool gameplay=true;
static HANDLE ready=nullptr,stop=nullptr;
static bool installed=false;
static bool verified(){return gameplay;}
static LRESULT CALLBACK window_proc(HWND window,UINT message,WPARAM wp,LPARAM lp) {
    if(message==WM_SETCURSOR){SetCursor(LoadCursorW(nullptr,MAKEINTRESOURCEW(32512)));return TRUE;}
    return DefWindowProcW(window,message,wp,lp);
}
static DWORD WINAPI publish_from_render(void*) {
    installed=source_cursor::publish(testWindow,true,verified);
    SetEvent(ready);WaitForSingleObject(stop,10000);return installed?0:1;
}
static void event(int hit=HTCLIENT) {
    SendMessageW(testWindow,WM_SETCURSOR,reinterpret_cast<WPARAM>(testWindow),MAKELPARAM(hit,WM_MOUSEMOVE));
}
static bool check(bool condition,const char* reason){if(!condition)std::fprintf(stderr,"FAILED: %s\n",reason);return condition;}
int main() {
    WNDCLASSW cls{};cls.lpfnWndProc=window_proc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"L4D2MCOfflineCursorTest";
    if(!RegisterClassW(&cls))return 1;
    testWindow=CreateWindowW(cls.lpszClassName,L"Hidden cursor regression",0,0,0,1,1,nullptr,nullptr,cls.hInstance,nullptr);
    if(!testWindow)return 2;
    ready=CreateEventW(nullptr,TRUE,FALSE,nullptr);stop=CreateEventW(nullptr,TRUE,FALSE,nullptr);
    HANDLE worker=CreateThread(nullptr,0,publish_from_render,nullptr,0,nullptr);
    if(!worker)return 3;
    WaitForSingleObject(ready,5000);
    if(!check(installed,"Cross-thread UI hook installation"))return 4;
    event();if(!check(GetCursor()==nullptr,"WM_SETCURSOR arrow overwritten on UI thread"))return 5;
    for(int i=0;i<20;i++){event();if(!check(GetCursor()==nullptr,"Repeated mouse events restore arrow"))return 6;}
    gameplay=false;event();if(!check(GetCursor()!=nullptr,"Source menu cursor must survive"))return 7;
    gameplay=true;source_cursor::hide=false;event();if(!check(GetCursor()!=nullptr,"Inventory cursor must survive"))return 8;
    source_cursor::hide=true;event(HTCAPTION);if(!check(GetCursor()!=nullptr,"Window border cursor must survive"))return 9;
    source_cursor::updated=GetTickCount64()-2000;event();if(!check(GetCursor()!=nullptr,"Expired presentation must yield"))return 10;
    source_cursor::publish(testWindow,true,verified);source_cursor::remove();event();
    if(!check(GetCursor()!=nullptr && !source_cursor::hook,"Teardown must remove own hook"))return 11;
    SetEvent(stop);WaitForSingleObject(worker,5000);CloseHandle(worker);CloseHandle(ready);CloseHandle(stop);
    DestroyWindow(testWindow);UnregisterClassW(cls.lpszClassName,cls.hInstance);
    std::puts("Native UI-thread cursor regression passed");return 0;
}
