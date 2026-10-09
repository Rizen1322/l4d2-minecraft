"""Build a private HUD using this user's installed resources, never download game assets."""
from pathlib import Path
import re
import struct
import subprocess
import hud_layout

ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r'E:\SteamLibrary\steamapps\common\Left 4 Dead 2')
FILES={'scripts/hudlayout.res',*(f'resource/ui/hud/{n}.res' for n in
       ('teamdisplayhud','teamdisplayhud_vertical','teammatepanel','teammatepanel_incap'))}

def read_resources(game=GAME):
    archive=game/'left4dead2/pak01_dir.vpk';data=archive.read_bytes()
    signature,version,size=struct.unpack_from('<III',data)
    if signature!=0x55aa1234 or version not in (1,2):raise ValueError('Unsupported VPK')
    cursor=28 if version==2 else 12;payload=cursor+size;result={}
    def token():
        nonlocal cursor
        end=data.index(b'\0',cursor);value=data[cursor:end].decode('utf-8');cursor=end+1;return value
    while (ext:=token()):
        while (folder:=token()):
            while (name:=token()):
                _,pre,index,offset,length,term=struct.unpack_from('<IHHIIH',data,cursor);cursor+=18
                if term!=0xffff:raise ValueError('Invalid VPK entry')
                extra=data[cursor:cursor+pre];cursor+=pre
                key=(folder+'/' if folder!=' ' else '')+name+'.'+ext
                if key not in FILES:continue
                source=data if index==0x7fff else archive.with_name(f'pak01_{index:03}.vpk').read_bytes()
                base=payload if index==0x7fff else 0
                result[key]=(extra+source[base+offset:base+offset+length]).decode('utf-8')
    if result.keys()!=FILES:raise ValueError('Required HUD resources missing')
    return result

def section(text,name):
    m=re.search(r'(?m)^\s*"?'+re.escape(name)+r'"?\s*\n\s*\{',text)
    if not m:raise ValueError('HUD panel missing: '+name)
    cursor=m.end();depth=1
    while depth:
        if text[cursor]=='{':depth+=1
        if text[cursor]=='}':depth-=1
        cursor+=1
    return m.start(),cursor

def patch_panel(text,name,values):
    a,b=section(text,name);panel=text[a:b]
    for key,value in values.items():
        panel,n=re.subn(r'("'+key+r'"\s*)"[^"]*"',lambda m:m[1]+'"'+str(value)+'"',panel,count=1)
        if n!=1:raise ValueError('Missing panel setting: '+name+'/'+key)
    return text[:a]+panel+text[b:]

def build(game=GAME):
    files=read_resources(game);stage=ROOT/'dist/l4d2mc_hud';stage.mkdir(parents=True,exist_ok=True)
    files['scripts/hudlayout.res']=patch_panel(files['scripts/hudlayout.res'],'HudWeaponSelection',{'xpos':3000,'visible':0})
    files['scripts/hudlayout.res']=patch_panel(files['scripts/hudlayout.res'],'HudWeapon',{'visible':0,'enabled':0,'wide':0,'tall':0})
    files['scripts/hudlayout.res']=patch_panel(files['scripts/hudlayout.res'],'CHudTeamDisplay',
                                            {'xpos':3000,'ypos':f'r{hud_layout.BOTTOM}','wide':0,'tall':0,'visible':0,'enabled':0})
    for name in ('teamdisplayhud','teamdisplayhud_vertical'):
        key=f'resource/ui/hud/{name}.res'
        for i in range(1,5):
            files[key]=patch_panel(files[key],f'TeamPlayer{i}',{'xpos':0,'ypos':(4-i)*hud_layout.STRIDE,'wide':hud_layout.WIDTH,'tall':70,'pinCorner':0})
    for name in ('teammatepanel','teammatepanel_incap'):
        key=f'resource/ui/hud/{name}.res'
        def scale(m):
            value=m[2]
            if re.fullmatch(r'-?\d+',value):value=str(round(int(value)*.78))
            return '"'+m[1]+'" "'+value+'"'
        files[key]=re.sub(r'"(xpos|ypos|wide|tall)"\s*"([^"]*)"',scale,files[key])
    files['addoninfo.txt']='"AddonInfo" { "addonSteamAppID" "550" "addontitle" "L4D2MC compact team HUD" "addonversion" "1" "addonauthor" "Local L4D2MC project" "addonDescription" "Private compact vertical team HUD; hides native weapon UI." }\n'
    for name,text in files.items():
        path=stage/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text,encoding='utf-8')
    subprocess.run([str(game/'bin/vpk.exe'),str(stage)],cwd=ROOT,check=True,capture_output=True)
    package=stage.with_suffix('.vpk')
    if not package.is_file():raise RuntimeError('HUD package missing')
    (ROOT/'passthrough/shaders/TeamHud.fxh').write_text(hud_layout.shader_header(),encoding='utf-8')
    print('Private HUD package:',package)
    return package

if __name__=='__main__':build()
