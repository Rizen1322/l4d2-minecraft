"""Create a reproducible source-only release; private builds/assets never ship."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import zipfile

ROOT=Path(__file__).resolve().parents[1]
ROOT_FILES={'README.md','LICENSE','CREDITS.md','CHANGELOG.md','requirements.txt','l4d2mc.example.json',
            'Setup-L4D2MC.ps1','Launch-Minecraft.ps1','Launch-L4D2MC-2K.bat','Play-Minecraft.cmd','.gitignore',
            'Auto-Setup-L4D2MC.cmd','Auto-Setup-L4D2MC.ps1','Coop.bat','Update-Coop.cmd'}
SUFFIXES={'.py','.ps1','.md','.txt','.java','.json','.cpp','.h','.fx','.fxh','.nut','.gradle','.properties','.bat','.cmd','.cfg'}
FORBIDDEN={'guest-game','.gradle','build','run','__pycache__','backups','evidence','dist','toolchains','output','research','release'}
SECRETS=re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-(?:proj-|ant-)?[A-Za-z0-9_-]{32,}|AKIA[0-9A-Z]{16}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')

def permitted(relative):
    p=Path(relative)
    if p.is_absolute() or '..' in p.parts or any(part in FORBIDDEN for part in p.parts):return False
    if p.as_posix() in ROOT_FILES:return True
    if p.parts[0]=='.github':return p.suffix in {'.yml','.yaml','.md'}
    if p.parts[0]=='docs':return (len(p.parts)==2 and p.suffix=='.md') or p.as_posix()=='docs/assets/coop-preview.png'
    if p.as_posix() in {'passthrough/guest/gradlew','passthrough/guest/gradle/wrapper/gradle-wrapper.jar'}:return True
    if p.parts[0] not in {'passthrough','tools'}:return False
    # Old model pipeline/tools are unrelated to the active mashup release.
    if p.parts[0]=='tools' and p.name not in {'build_assets.py','build_hud.py','hud_layout.py','private_hud_assets.py','release_source.py',
        'coop_wizard.ps1','pack_for_friend.ps1','test_launcher_arguments.ps1','update_coop.ps1'}:return False
    return p.suffix in SUFFIXES or p.name in {'LICENSE','.gitignore'}

def collect(root=ROOT):
    files=[]
    for directory,dirs,names in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if d not in FORBIDDEN and d!='.git' and (Path(directory)!=root or d in {'.github','docs','passthrough','tools'})]
        for name in names:
            p=Path(directory)/name;relative=p.relative_to(root)
            if not permitted(relative):continue
            if p.is_symlink() or not p.resolve().is_relative_to(root.resolve()):raise ValueError('Escaping file: '+str(relative))
            if SECRETS.search(p.read_bytes()):raise ValueError('Possible credential/private key: '+str(relative))
            files.append(relative)
    if Path('README.md') not in files or Path('LICENSE') not in files:raise ValueError('Release requires README and LICENSE')
    return sorted(files,key=lambda p:p.as_posix())

def package(root=ROOT,destination=None):
    destination=destination or root/'release/l4d2-minecraft-alpha-source.zip'
    files=collect(root);destination.parent.mkdir(parents=True,exist_ok=True)
    manifest={p.as_posix():hashlib.sha256((root/p).read_bytes()).hexdigest() for p in files}
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for p in files:
            info=zipfile.ZipInfo('l4d2-minecraft/'+p.as_posix(),(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,(root/p).read_bytes())
        info=zipfile.ZipInfo('l4d2-minecraft/SOURCE-MANIFEST.json',(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(info,json.dumps(manifest,sort_keys=True,indent=2))
    digest=hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix('.zip.sha256').write_text(digest+'  '+destination.name+'\n',encoding='ascii')
    print(f'Source-only release: {destination.name}; {len(files)} files; SHA256 {digest}')
    return destination

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if args.check:print(f'Source release lint passed: {len(collect())} files; game assets/builds/credentials excluded.')
    else:package()
