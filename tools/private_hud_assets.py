"""Convert the user's own installed Source HUD portraits into private guest resources.

Generated assets stay in ignored dist/, never in the repository.
"""
from pathlib import Path
import struct
import argparse
import sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'passthrough'))
from runtime_paths import game_path
GAME=None
PORTRAITS={'coach':'coach','ellis':'mechanic','nick':'gambler','rochelle':'producer',
           'bill':'namvet','zoey':'teenangst','francis':'biker','louis':'manager'}


def extract(archive, wanted):
    archive=Path(archive);data=archive.read_bytes()
    signature,version,tree=struct.unpack_from('<III',data)
    if signature!=0x55aa1234 or version not in (1,2):raise ValueError('Unsupported VPK')
    cursor=28 if version==2 else 12;embedded=cursor+tree;found={}
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
                if key not in wanted:continue
                if index==0x7fff:payload=data[embedded+offset:embedded+offset+length]
                else:
                    with archive.with_name(f'pak01_{index:03}.vpk').open('rb') as source:
                        source.seek(offset);payload=source.read(length)
                if len(payload)!=length:raise ValueError('Truncated asset')
                found[key]=extra+payload
    if found.keys()!=wanted:raise ValueError('Required installed portraits missing')
    return found


def decode_vtf(data):
    signature,major,minor,header,w,h=struct.unpack_from('<4sIIIHH',data)
    frames=struct.unpack_from('<H',data,24)[0]
    fmt=struct.unpack_from('<I',data,52)[0];mips=data[56]
    if signature!=b'VTF\0' or major!=7 or not 1<=w<=2048 or not 1<=h<=2048 or frames!=1:
        raise ValueError('Unsupported portrait texture')
    sizes={0:lambda x,y:x*y*4,13:lambda x,y:max(1,(x+3)//4)*max(1,(y+3)//4)*8,
           14:lambda x,y:max(1,(x+3)//4)*max(1,(y+3)//4)*16,
           15:lambda x,y:max(1,(x+3)//4)*max(1,(y+3)//4)*16}
    if fmt not in sizes or not 1<=mips<=12:raise ValueError('Unsupported portrait encoding')
    if minor>=3:
        count=struct.unpack_from('<I',data,68)[0];offset=None
        for i in range(count):
            entry=80+8*i
            if data[entry:entry+3]==b'\x30\0\0':offset=struct.unpack_from('<I',data,entry+4)[0]
        if offset is None:raise ValueError('Missing VTF image resource')
    else:
        low=struct.unpack_from('<I',data,57)[0];lw,lh=data[61:63]
        if lw and lh and low not in sizes:raise ValueError('Unsupported thumbnail')
        offset=header+(sizes[low](lw,lh) if lw and lh else 0)
    offset+=sum(sizes[fmt](max(1,w>>i),max(1,h>>i)) for i in range(mips-1,0,-1))
    pixels=data[offset:offset+sizes[fmt](w,h)]
    if len(pixels)!=sizes[fmt](w,h):raise ValueError('Truncated VTF image')
    if fmt==0:return Image.frombytes('RGBA',(w,h),pixels)
    return Image.frombytes('RGBA',(w,h),pixels,'bcn',{13:1,14:2,15:3}[fmt])


def build(game=GAME):
    game=game_path(game)
    names={f'materials/vgui/s_panel_{value}.vtf' for value in PORTRAITS.values()}
    data=extract(game/'left4dead2/pak01_dir.vpk',names)
    destination=ROOT/'dist/l4d2mc_hud_assets/assets/passthrough/textures/gui/teammates'
    destination.mkdir(parents=True,exist_ok=True)
    for character,source in PORTRAITS.items():
        image=decode_vtf(data[f'materials/vgui/s_panel_{source}.vtf'])
        image.save(destination/f'{character}.png')
    print('Eight private teammate portraits generated from installed game.')


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=GAME)
    build(parser.parse_args().game)
