"""Build, install and launch the local L4D2 Block Sandbox addon."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GAME = Path(r'E:\SteamLibrary\steamapps\common\Left 4 Dead 2')
NAME = 'l4d2mc_blocks.vpk'


def build(game: Path) -> Path:
    if not (ROOT / 'addon/models/l4d2mc/cube.mdl').is_file():
        raise SystemExit('Build models first: python tools/build_assets.py --game <game>.')
    compiler = game / 'bin/vpk.exe'
    if not compiler.is_file():
        raise SystemExit('Official Authoring Tools vpk.exe is missing.')
    dist = ROOT / 'dist'
    stage = dist / 'l4d2mc_blocks'
    stage.mkdir(parents=True, exist_ok=True)
    # No private probes or automated game-modifying tests in the player package.
    for source in (ROOT / 'addon').rglob('*'):
        if not source.is_file() or source.name in ('probe.nut', 'tests.nut', 'integration.nut') or source.name.endswith('_probe.nut'):
            continue
        target = stage / source.relative_to(ROOT / 'addon')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    result = subprocess.run([str(compiler), str(stage)], cwd=dist, capture_output=True)
    print((result.stdout + result.stderr).decode('mbcs', errors='replace')[-1500:])
    output = dist / NAME
    if result.returncode != 0 or not output.is_file():
        raise SystemExit('VPK build failed.')
    print('Package:', output)
    return output


def install(game: Path) -> None:
    package = ROOT / 'dist' / NAME
    if not package.is_file():
        raise SystemExit('Run build first.')
    addons = game / 'left4dead2/addons'
    if not addons.is_dir() or not (game / 'left4dead2.exe').is_file():
        raise SystemExit('Not a Left 4 Dead 2 installation.')
    destination = addons / NAME
    receipt = ROOT / 'backups/install-receipt.json'
    previous = json.loads(receipt.read_text()) if receipt.is_file() else None
    if destination.exists():
        actual = hashlib.sha256(destination.read_bytes()).hexdigest()
        if previous is None or previous.get('path') != str(destination) or previous.get('sha256') != actual:
            raise SystemExit('An untracked addon already uses this filename; refusing to replace it.')
    backup = ROOT / 'backups' / datetime.now().strftime('%Y%m%d-%H%M%S')
    backup.mkdir(parents=True)
    for source in (game / 'left4dead2/cfg', game / 'left4dead2/addonlist.txt'):
        if source.is_dir():
            shutil.copytree(source, backup / source.name)
        elif source.is_file():
            shutil.copy2(source, backup / source.name)
    if destination.is_file():
        shutil.copy2(destination, backup / NAME)
    shutil.copy2(package, destination)
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
        raise SystemExit('Installed file checksum does not match package.')
    receipt.write_text(json.dumps({'path': str(destination), 'sha256': digest, 'backup': str(backup)}, indent=2))
    print('Installed:', destination)
    print('Backup:', backup)
    print('Restart L4D2 to mount the addon.')


def launch(game: Path, map_name: str) -> None:
    import re
    if not re.fullmatch(r'[a-zA-Z0-9_]+', map_name):
        raise SystemExit('Invalid map name.')
    steam = Path(r'C:\Program Files (x86)\Steam\steam.exe')
    if not steam.is_file():
        raise SystemExit('Steam executable not found.')
    subprocess.Popen([str(steam), '-applaunch', '550', '-insecure', '-novid', '-console',
                      '+map', map_name, 'mcblocks'], cwd=game)
    print('Starting local Block Sandbox. Close an already running L4D2 first.')


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('build', 'install', 'launch'))
    parser.add_argument('--game', type=Path, default=DEFAULT_GAME)
    parser.add_argument('--map', default='c1m1_hotel')
    args = parser.parse_args()
    if args.action == 'build': build(args.game)
    elif args.action == 'install': install(args.game)
    else: launch(args.game, args.map)
