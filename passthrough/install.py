"""Install the explicitly approved loaders, refusing to replace unowned files."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"E:\SteamLibrary\steamapps\common\Left 4 Dead 2")
MINECRAFT = Path(r"C:\Users\Rizen\AppData\Roaming\.tlauncher\legacy\Minecraft\game")
GUEST = ROOT / "passthrough/guest-game"
RECEIPT = ROOT / "backups/passthrough-install.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def install_file(source, target, manifest):
    key = str(target)
    if target.exists() and key not in manifest:
        if digest(target) != digest(source):
            raise RuntimeError(f"Existing unowned file: {target}")
        print(f'Preserved identical pre-existing file without taking ownership: {target}')
        return
    elif target.exists() and digest(target) != manifest[key]:
        raise RuntimeError(f"Installed file was changed externally: {target}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
    manifest[key] = digest(target)
    RECEIPT.parent.mkdir(parents=True, exist_ok=True)
    RECEIPT.write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def host(manifest):
    if not (GAME / "left4dead2.exe").exists():
        raise RuntimeError("L4D2 installation missing")
    staging = ROOT / "dist/passthrough-config"
    staging.mkdir(parents=True, exist_ok=True)
    # All files have unique paths except loader/config; refuse pre-existing owners there.
    shader_dir = GAME / "bin/l4d2mc/shaders"
    preset = GAME / "bin/l4d2mc/preset.ini"
    (staging / "ReShade.ini").write_text(
        "[ADDON]\n"
        f"AddonPath={GAME / 'bin/l4d2mc'}\n"
        "[GENERAL]\n"
        f"EffectSearchPaths={shader_dir}\n"
        f"PresetPath={preset}\n"
        "PerformanceMode=0\n"
        "[DEPTH]\nDepthCopyBeforeClears=1\nDepthCopyAtClearIndex=2\nUseAspectRatioHeuristics=3\n", encoding="utf-8")
    (staging / "preset.ini").write_text(
        "Techniques=MCPassthrough@L4D2Minecraft.fx\n"
        "TechniqueSorting=MCPassthrough@L4D2Minecraft.fx\n"
        "[L4D2Minecraft.fx]\nHostReversedZ=0\nHostDepthScale=0.03125\n"
        "LightMatch=0\nGradeMatch=0\nHazeStrength=0\nContactShadow=0\nBloomStrength=0\n",
        encoding="utf-8")
    files = [
        (ROOT / "toolchains/ReShade32.dll", GAME / "bin/d3d9.dll"),
        (staging / "ReShade.ini", GAME / "bin/ReShade.ini"),
        (staging / "preset.ini", preset),
        (ROOT / "dist/L4D2Minecraft.addon32", GAME / "bin/l4d2mc/L4D2Minecraft.addon32"),
        (ROOT / "passthrough/host/l4d2mc_bridge.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_bridge.nut"),
        (ROOT / "passthrough/host/l4d2mc_gameplay.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_gameplay.nut"),
        (ROOT / "passthrough/host/l4d2mc_survival.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_survival.nut"),
    ]
    files.extend((p, shader_dir / p.name) for p in (ROOT / "passthrough/shaders").glob('*') if p.is_file())
    files.extend((p, GAME / 'left4dead2/models/l4d2mc' / p.name) for p in (ROOT / 'addon/models/l4d2mc').glob('*') if p.is_file())
    for source, target in files:
        install_file(source, target, manifest)
    print("L4D2 loader, adapter, shader and VScript installed.")


def guest(manifest):
    jar = ROOT / "passthrough/guest/build/libs/passthrough-0.1.0.jar"
    if not jar.exists():
        raise RuntimeError("Build guest jar first")
    # Flatten the official vanilla + Fabric metadata. Replace only the gameDir
    # placeholder so all auth/account arguments remain supplied by the user's launcher.
    index = fetch_json("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
    version = next(v for v in index['versions'] if v['id'] == '26.3')
    vanilla = fetch_json(version['url'])
    fabric = fetch_json("https://meta.fabricmc.net/v2/versions/loader/26.3/0.19.5/profile/json")
    identifier = "L4D2MC-Fabric-26.3"
    vanilla['id'] = identifier
    vanilla['mainClass'] = fabric['mainClass']
    vanilla['libraries'].extend(fabric['libraries'])
    vanilla['arguments']['game'] = [str(GUEST) if v == '${game_directory}' else v for v in vanilla['arguments']['game']]
    vanilla['arguments']['jvm'].extend(fabric.get('arguments', {}).get('jvm', []))
    vanilla['arguments']['jvm'].extend(['--enable-native-access=ALL-UNNAMED'])
    # Separate mod directory and worlds; no copy of user's saves or tokens.
    GUEST.mkdir(parents=True, exist_ok=True)
    install_file(jar, GUEST / 'mods/l4d2mc-guest.jar', manifest)
    staging = ROOT / 'dist/passthrough-config'
    staging.mkdir(parents=True, exist_ok=True)
    profile = staging / f'{identifier}.json'
    profile.write_text(json.dumps(vanilla, indent=2), encoding='utf-8')
    install_file(profile, MINECRAFT / f'versions/{identifier}/{identifier}.json', manifest)
    # Fabric API is a public library, not a user's retail asset.
    api_name = 'fabric-api-0.161.0+26.3.jar'
    api = staging / api_name
    if not api.exists():
        urllib.request.urlretrieve('https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/0.161.0+26.3/' + api_name, api)
    install_file(api, GUEST / 'mods' / api_name, manifest)
    print(f"Minecraft profile: {identifier}; separate game directory: {GUEST}")
    print("Launch this version through your normal signed-in launcher.")


def uninstall(manifest):
    changed = []
    for filename, expected in list(manifest.items()):
        path = Path(filename)
        if path.exists() and digest(path) != expected:
            changed.append(filename)
            continue
        if path.exists():
            path.unlink()
        del manifest[filename]
    RECEIPT.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('Removed own unchanged files. Worlds and launcher data preserved.')
    if changed:
        print('Preserved externally changed files:', changed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['host', 'guest', 'uninstall'])
    args = parser.parse_args()
    receipt = json.loads(RECEIPT.read_text(encoding='utf-8')) if RECEIPT.exists() else {}
    {'host':host, 'guest':guest, 'uninstall':uninstall}[args.action](receipt)
