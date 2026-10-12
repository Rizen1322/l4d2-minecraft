"""Run an owned L4D2MC config in the already-running L4D2; never start a game.

The in-process channel (native add-on calling VEngineClient slot 106 as
ClientCmd_Unrestricted) crashed retail build 10097 in tier0.dll with 0xC0000417
on the first exec, so it is not used. Commands go through Source's own
`-hijack` forwarding, which only ever targets an existing game window: the
window and its process are checked immediately before forwarding, and the
helper is started from that exact process's executable path.
"""
import ctypes
import ctypes.wintypes
import re
import subprocess


def _process_path(window):
    user=ctypes.windll.user32;kernel=ctypes.windll.kernel32
    pid=ctypes.wintypes.DWORD()
    user.GetWindowThreadProcessId(ctypes.c_void_p(window),ctypes.byref(pid))
    if not pid.value:return None
    handle=kernel.OpenProcess(0x1000,False,pid.value) # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:return None
    try:
        size=ctypes.wintypes.DWORD(1024);buffer=ctypes.create_unicode_buffer(1024)
        if not kernel.QueryFullProcessImageNameW(handle,0,buffer,ctypes.byref(size)):return None
        return buffer.value
    finally:kernel.CloseHandle(handle)


def send_config(window, config):
    if not re.fullmatch(r'l4d2mc_[A-Za-z0-9_]{1,89}',config):
        raise ValueError('Only owned L4D2MC config names are accepted')
    if not window:return False
    user=ctypes.windll.user32
    title=ctypes.create_unicode_buffer(512)
    user.GetWindowTextW(ctypes.c_void_p(window),title,len(title))
    if not title.value.startswith('Left 4 Dead 2'):return False
    exe=_process_path(window)
    if not exe or not exe.lower().endswith('left4dead2.exe'):return False
    subprocess.Popen([exe,'-insecure','-hijack','+exec',config],
        creationflags=subprocess.CREATE_NO_WINDOW,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    return True

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--exec',dest='config',required=True)
    args=parser.parse_args();user=ctypes.windll.user32
    user.FindWindowW.restype=ctypes.c_void_p
    raise SystemExit(0 if send_config(user.FindWindowW('Valve001',None),args.config) else 1)
