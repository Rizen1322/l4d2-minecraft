"""Apply only built, owned mashup components. Does not start or close games."""
import json
import argparse
from pathlib import Path
from install import ROOT,GAME,GUEST,RECEIPT,digest,install_file,preflight_file,recover_pending
from runtime_paths import game_path

def update(game=GAME):
    game=game_path(game)
    manifest=json.loads(RECEIPT.read_text(encoding='utf-8'))
    recover_pending(manifest)
    files=[(ROOT/'passthrough/guest/build/libs/passthrough-2.0.0.jar',GUEST/'mods/l4d2mc-guest.jar'),
           (ROOT/'dist/L4D2Minecraft.addon32',game/'bin/l4d2mc/L4D2Minecraft.addon32'),
           (ROOT/'dist/l4d2mc_hud.vpk',game/'left4dead2/addons/l4d2mc_hud.vpk')]
    files += [(ROOT/'passthrough/shaders'/name,game/'bin/l4d2mc/shaders'/name)
              for name in ('TeamHud.fxh','L4D2Minecraft.fx')]
    files += [(ROOT/'passthrough/host'/name,game/'left4dead2/scripts/vscripts'/name)
              for name in ('l4d2mc_bridge.nut','l4d2mc_gameplay.nut','l4d2mc_survival.nut','l4d2mc_navigation.nut','l4d2mc_coop.nut','l4d2mc_flight.nut')]
    files += [(ROOT/'passthrough/host'/name,game/'left4dead2/cfg'/name)
              for name in ('l4d2mc_use_press.cfg','l4d2mc_use_release.cfg')]
    files += [(ROOT/'addon/models/l4d2mc'/('steve_aura.'+ext),game/'left4dead2/models/l4d2mc'/('steve_aura.'+ext)) for ext in ('mdl','vvd','dx90.vtx')]
    files += [(ROOT/'addon/materials/l4d2mc'/('aura.'+ext),game/'left4dead2/materials/l4d2mc'/('aura.'+ext)) for ext in ('vmt','vtf')]
    pending=[]
    # Validate every payload/ownership before replacing any component.
    for source,target in files:
        if not source.is_file():raise RuntimeError('Build component missing: '+str(source))
        if target.exists() and digest(target)==digest(source):continue
        preflight_file(source,target,manifest)
    for source,target in files:
        if not source.is_file():raise RuntimeError('Build component missing: '+str(source))
        if target.exists() and digest(target)==digest(source):continue
        try:install_file(source,target,manifest)
        except PermissionError:pending.append(str(target));continue
        if digest(source)!=digest(target):raise RuntimeError('Installed hash mismatch: '+str(target))
    guest_jar=str(GUEST/'mods/l4d2mc-guest.jar')
    if guest_jar in pending:
        # The launcher runs while Minecraft is already open; its own JAR stays
        # locked until Minecraft exits. Apply it on the next closed-Minecraft run.
        pending.remove(guest_jar)
        print('Minecraft is running: the guest mod update applies after Minecraft is closed and update.py runs again.')
    if pending:raise RuntimeError('Close games before applying locked components: '+', '.join(pending))
    print(f'{len(files)} mashup components verified; no games started.')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--game',type=Path,default=GAME)
    update(parser.parse_args().game)
