"""Send an owned config to the existing native add-on; never launch a game."""
import ctypes
import re
import secrets

def send_config(window, config):
    if not re.fullmatch(r'l4d2mc_[A-Za-z0-9_]{1,89}',config):
        raise ValueError('Only owned L4D2MC config names are accepted')
    user=ctypes.windll.user32;kernel=ctypes.windll.kernel32
    user.GetPropW.argtypes=[ctypes.c_void_p,ctypes.c_wchar_p];user.GetPropW.restype=ctypes.c_void_p
    if user.GetPropW(window,'L4D2MC.CommandVersion')!=1:return False
    kernel.GlobalAddAtomW.argtypes=[ctypes.c_wchar_p];kernel.GlobalAddAtomW.restype=ctypes.c_ushort
    atom=kernel.GlobalAddAtomW(config)
    if not atom:return False
    try:
        user.RegisterWindowMessageW.argtypes=[ctypes.c_wchar_p]
        message=user.RegisterWindowMessageW('L4D2MC.OwnedConfig.v1')
        nonce=secrets.randbelow(0x7ffffffe)+1
        result=ctypes.c_size_t()
        user.SendMessageTimeoutW.argtypes=[ctypes.c_void_p,ctypes.c_uint,ctypes.c_size_t,ctypes.c_ssize_t,ctypes.c_uint,ctypes.c_uint,ctypes.POINTER(ctypes.c_size_t)]
        sent=user.SendMessageTimeoutW(window,message,atom,nonce,0x0002,500,ctypes.byref(result))
        return bool(sent) and user.GetPropW(window,'L4D2MC.CommandReceipt')==nonce
    finally:kernel.GlobalDeleteAtom(atom)

if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--exec',dest='config',required=True)
    args=parser.parse_args();user=ctypes.windll.user32
    user.FindWindowW.restype=ctypes.c_void_p
    raise SystemExit(0 if send_config(user.FindWindowW('Valve001',None),args.config) else 1)
