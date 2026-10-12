"""Generate original cube geometry/textures and compile with Valve's L4D2 tools."""
from pathlib import Path
import argparse
import random
import shutil
import struct
import subprocess
import sys

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def texture(kind: str) -> Image.Image:
    rng = random.Random({'dirt': 1, 'stone': 2, 'wood': 3}[kind])
    colors = {'dirt': (116, 78, 46), 'stone': (119, 126, 136), 'wood': (163, 114, 63)}
    image = Image.new('RGBA', (16, 16))
    for y in range(16):
        for x in range(16):
            delta = rng.randrange(-19, 20)
            if kind == 'wood':
                delta += -35 if y % 4 == 0 else (8 if y % 4 == 1 else 0)
                if (x + y // 4 * 5) % 13 == 0:
                    delta -= 15
            image.putpixel((x, y), tuple(max(0, min(255, c + delta)) for c in colors[kind]) + (255,))
    return image


def write_vtf(image: Image.Image, path: Path) -> None:
    image = image.resize((64, 64), Image.Resampling.NEAREST)
    header = bytearray(80)
    struct.pack_into('<4sIIIHHIHH', header, 0, b'VTF\0', 7, 2, 80, 64, 64, 1, 1, 0)
    struct.pack_into('<3f', header, 32, 0.3, 0.3, 0.3)
    struct.pack_into('<fIBI', header, 48, 1.0, 0, 1, 0xFFFFFFFF)
    struct.pack_into('<BBH', header, 61, 0, 0, 1)
    path.write_bytes(header + image.tobytes())


def cube_smd() -> str:
    # Vertex order gives outward face normals.
    faces = [
        ((0, 0, -1), [(-16,-16,-16),(-16,16,-16),(16,16,-16),(16,-16,-16)]),
        ((0, 0, 1), [(-16,-16,16),(16,-16,16),(16,16,16),(-16,16,16)]),
        ((-1,0,0), [(-16,-16,-16),(-16,-16,16),(-16,16,16),(-16,16,-16)]),
        ((1,0,0), [(16,-16,-16),(16,16,-16),(16,16,16),(16,-16,16)]),
        ((0,-1,0), [(-16,-16,-16),(16,-16,-16),(16,-16,16),(-16,-16,16)]),
        ((0,1,0), [(-16,16,-16),(-16,16,16),(16,16,16),(16,16,-16)]),
    ]
    lines = ['version 1','nodes','0 "root" -1','end','skeleton','time 0','0 0 0 0 0 0 0','end','triangles']
    uv = [(0,0),(1,0),(1,1),(0,1)]
    for normal, vertices in faces:
        for tri in [(0,1,2),(0,2,3)]:
            lines.append('dirt')
            for i in tri:
                lines.append('0 ' + ' '.join(map(str, vertices[i] + normal + uv[i])))
    return '\n'.join(lines + ['end',''])


def aura_smd() -> str:
    """Original six-box silhouette; no Minecraft textures or player skeleton."""
    lines=['version 1','nodes','0 "root" -1','end','skeleton','time 0','0 0 0 0 0 0 0','end','triangles']
    # Source forward is X, Steve's shoulders extend along Y. 2 Source units/pixel.
    boxes=[((-8,-8,48),(8,8,64)),((-4,-8,24),(4,8,48)),
           ((-4,-16,24),(4,-8,48)),((-4,8,24),(4,16,48)),
           ((-4,-8,0),(4,0,24)),((-4,0,0),(4,8,24))]
    template=cube_smd().split('triangles\n',1)[1].rsplit('end',1)[0].splitlines()
    for low,high in boxes:
        for line in template:
            if line=='dirt':lines.append('aura');continue
            values=line.split();coords=[float(v) for v in values[1:4]]
            mapped=[low[i]+(coords[i]+16)/32*(high[i]-low[i]) for i in range(3)]
            lines.append('0 '+' '.join(str(v) for v in mapped)+' '+' '.join(values[4:]))
    return '\n'.join(lines+['end',''])

def build(game: Path) -> None:
    compiler = game / 'bin' / 'studiomdl.exe'
    if not compiler.is_file():
        raise SystemExit('Install official Left 4 Dead 2 Authoring Tools (Steam 563).')
    src = ROOT / 'assets-src'
    materials = ROOT / 'addon' / 'materials' / 'l4d2mc'
    staging = ROOT / 'build-game'
    for directory in (src, materials, staging):
        directory.mkdir(parents=True, exist_ok=True)
    for kind in ('dirt', 'stone', 'wood'):
        image = texture(kind)
        image.save(src / f'{kind}.png')
        write_vtf(image, materials / f'{kind}.vtf')
        (materials / f'{kind}.vmt').write_text(
            f'"VertexLitGeneric"\n{{\n "$basetexture" "l4d2mc/{kind}"\n "$surfaceprop" "{ "wood" if kind != "stone" else "stone" }"\n}}\n')
    (src / 'cube.smd').write_text(cube_smd())
    write_vtf(Image.new('RGBA',(16,16),(255,255,255,255)),materials/'aura.vtf')
    (materials/'aura.vmt').write_text('"VertexLitGeneric"\n{\n "$basetexture" "l4d2mc/aura"\n}\n')
    (src/'steve_aura.smd').write_text(aura_smd())
    (src/'steve_aura.qc').write_text('$modelname "l4d2mc/steve_aura.mdl"\n$body steve "steve_aura.smd"\n$cdmaterials "l4d2mc/"\n$sequence idle "steve_aura.smd"\n$surfaceprop "flesh"\n')
    (src / 'cube.qc').write_text('''$modelname "l4d2mc/cube.mdl"
$staticprop
$body cube "cube.smd"
$cdmaterials "l4d2mc/"
$surfaceprop "wood"
$sequence idle "cube.smd"
$texturegroup skinfamilies
{
 { "dirt" }
 { "stone" }
 { "wood" }
}
$collisionmodel "cube.smd"
{
 $mass 100
}
''')
    # Absolute search paths, output models go to our staging folder, never the game.
    (staging / 'gameinfo.txt').write_text(
        '"GameInfo"\n{\n "game" "L4D2MC Build"\n "FileSystem"\n {\n "SteamAppId" "550"\n "SearchPaths"\n {\n'
        f' "Game" "{(ROOT / "addon").as_posix()}"\n "Game" "{(game / "left4dead2").as_posix()}"\n'
        f' "Game" "{(game / "hl2").as_posix()}"\n }}\n }}\n}}\n')
    result = subprocess.run([str(compiler), '-nop4', '-game', str(staging), str(src / 'cube.qc')],
                            cwd=game / 'bin', capture_output=True)
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence' / 'model-build.log').write_bytes(result.stdout + result.stderr)
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    print((result.stdout + result.stderr).decode('mbcs', errors='replace')[-3500:])
    if result.returncode != 0:
        raise SystemExit(result.returncode)
    built = staging / 'models' / 'l4d2mc'
    if not (built / 'cube.mdl').exists():
        raise SystemExit('Compiler did not produce cube.mdl; inspect model-build.log.')
    target = ROOT / 'addon' / 'models' / 'l4d2mc'
    target.mkdir(parents=True, exist_ok=True)
    for file in built.glob('cube.*'):
        shutil.copy2(file, target / file.name)
    aura=subprocess.run([str(compiler),'-nop4','-game',str(staging),str(src/'steve_aura.qc')],cwd=game/'bin',capture_output=True)
    (ROOT/'evidence'/'aura-model-build.log').write_bytes(aura.stdout+aura.stderr)
    if aura.returncode!=0 or not (built/'steve_aura.mdl').exists():raise RuntimeError('Aura model build failed; see evidence/aura-model-build.log')
    for file in built.glob('steve_aura.*'):shutil.copy2(file,target/file.name)
    print('Cube assets built:', target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--game', type=Path, required=True)
    build(parser.parse_args().game)
