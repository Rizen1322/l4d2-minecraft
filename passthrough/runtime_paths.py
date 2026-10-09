"""User paths: explicit argument > environment > ignored local config > Steam.
Importing this module never launches processes, downloads or edits games.
"""
import argparse
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / 'l4d2mc.local.json'

def configuration():
    if not LOCAL.exists():return {}
    result=json.loads(LOCAL.read_text(encoding='utf-8-sig'))
    if not isinstance(result,dict):raise ValueError('l4d2mc.local.json must be an object')
    for key in ('game','minecraft'):
        if key in result and (not isinstance(result[key],str) or not result[key].strip()):raise ValueError('Invalid local path: '+key)
    return result

def steam_roots():
    roots=[]
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Valve\Steam') as key:roots.append(Path(winreg.QueryValueEx(key,'SteamPath')[0]))
    except (ImportError,OSError):pass
    roots.append(Path(os.environ.get('ProgramFiles(x86)',r'C:\Program Files (x86)'))/'Steam')
    for root in list(roots):
        libraries=root/'steamapps/libraryfolders.vdf'
        if libraries.is_file():
            for raw in re.findall(r'"path"\s+"([^"\r\n]+)"',libraries.read_text(encoding='utf-8',errors='replace')):roots.append(Path(raw.replace('\\\\','\\')))
    return list(dict.fromkeys(roots))

def game_path(explicit=None):
    selected=explicit or os.environ.get('L4D2MC_GAME') or configuration().get('game')
    if selected:return Path(selected).expanduser()
    candidates=[root/'steamapps/common/Left 4 Dead 2' for root in steam_roots()]
    return next((p for p in candidates if (p/'left4dead2.exe').is_file()),candidates[0])

def minecraft_path(explicit=None):
    selected=explicit or os.environ.get('L4D2MC_MINECRAFT') or configuration().get('minecraft')
    return Path(selected).expanduser() if selected else Path(os.environ.get('APPDATA',Path.home()))/'.minecraft'

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('kind',choices=['game','minecraft']);args=parser.parse_args()
    print(game_path() if args.kind=='game' else minecraft_path())
