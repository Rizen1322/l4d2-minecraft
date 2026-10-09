"""Apply only built, owned mashup components. Does not start or close games."""
import json
import argparse
from pathlib import Path
from install import ROOT,GAME,GUEST,RECEIPT,digest,install_file
from runtime_paths import game_path

def update(game=GAME):
    game=game_path(game)
    manifest=json.loads(RECEIPT.read_text(encoding='utf-8'))
    files=[(ROOT/'passthrough/guest/build/libs/passthrough-0.1.0.jar',GUEST/'mods/l4d2mc-guest.jar'),
           (ROOT/'dist/L4D2Minecraft.addon32',game/'bin/l4d2mc/L4D2Minecraft.addon32'),
           (ROOT/'dist/l4d2mc_hud.vpk',game/'left4dead2/addons/l4d2mc_hud.vpk')]
    files += [(ROOT/'passthrough/shaders'/name,game/'bin/l4d2mc/shaders'/name)
              for name in ('TeamHud.fxh','L4D2Minecraft.fx')]
    files += [(ROOT/'passthrough/host'/name,game/'left4dead2/scripts/vscripts'/name)
              for name in ('l4d2mc_bridge.nut','l4d2mc_gameplay.nut','l4d2mc_survival.nut','l4d2mc_navigation.nut')]
    pending=[]
    for source,target in files:
        if not source.is_file():raise RuntimeError('Build component missing: '+str(source))
        if target.exists() and digest(target)==digest(source):continue
        try:install_file(source,target,manifest)
        except PermissionError:pending.append(str(target));continue
        if digest(source)!=digest(target):raise RuntimeError('Installed hash mismatch: '+str(target))
    if pending:raise RuntimeError('Close games before applying locked components: '+', '.join(pending))
    print('Nine mashup components verified; no games started.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=GAME)
    update(parser.parse_args().game)
