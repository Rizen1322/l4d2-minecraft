"""Install the explicitly approved loaders, refusing to replace unowned files."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import urllib.request
import os
import tempfile
from runtime_paths import game_path, minecraft_path

ROOT = Path(__file__).resolve().parents[1]
GAME = None
MINECRAFT = None
GUEST = ROOT / "passthrough/guest-game"
RECEIPT = ROOT / "backups/passthrough-install.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fetch_json(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)

def validate_reshade(path):
    import pefile
    path=Path(path)
    if not path.is_file():raise RuntimeError('ReShade loader must be an x86 DLL file')
    try:
        binary=pefile.PE(str(path))
        exports={symbol.name for symbol in binary.DIRECTORY_ENTRY_EXPORT.symbols}
        if binary.FILE_HEADER.Machine!=0x14c or not {b'ReShadeRegisterAddon',b'ReShadeUnregisterAddon'}<=exports:
            raise RuntimeError('Expected x86 ReShade DLL with add-on API; x64/other DLL refused')
    except (pefile.PEFormatError,AttributeError) as error:
        raise RuntimeError('Invalid ReShade loader') from error
    finally:
        if 'binary' in locals():binary.close()


def preflight_file(source,target,manifest):
    if not source.is_file():raise RuntimeError('Build component missing: '+str(source))
    key = str(target.absolute())
    if target.exists() and key not in manifest:
        if digest(target) != digest(source):
            raise RuntimeError(f"Existing unowned file: {target}")
        return False
    elif target.exists() and digest(target) != manifest[key]:
        raise RuntimeError(f"Installed file was changed externally: {target}")
    return True

def atomic_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    descriptor,filename=tempfile.mkstemp(prefix='.l4d2mc-receipt-',dir=path.parent)
    temporary=Path(filename)
    try:
        with os.fdopen(descriptor,'w',encoding='utf-8') as output:
            json.dump(value,output,indent=2);output.flush();os.fsync(output.fileno())
        os.replace(temporary,path)
    finally:
        temporary.unlink(missing_ok=True)

def atomic_receipt(manifest):
    atomic_json(RECEIPT,manifest)

def pending_path():
    return RECEIPT.with_name(RECEIPT.name+'.pending')

def recover_pending(manifest):
    journal=pending_path()
    if not journal.exists():return
    value=json.loads(journal.read_text(encoding='utf-8'))
    key=value['target'];target=Path(key);before=value['before'];after=value['after']
    def valid_hash(h):return isinstance(h,str) and len(h)==64 and all(c in '0123456789abcdef' for c in h)
    if not target.is_absolute() or not valid_hash(after) or (before is not None and not valid_hash(before)) or type(value['owned']) is not bool:
        raise RuntimeError('Invalid pending install journal; files preserved')
    prior_ok=(key in manifest)==value['owned'] and manifest.get(key)==value['record']
    committed=manifest.get(key)==after
    if not prior_ok and not committed:raise RuntimeError('Pending install receipt changed externally; files preserved')
    current=digest(target) if target.exists() else None
    if current==after:
        manifest[key]=after;atomic_receipt(manifest)
    elif current==before and prior_ok:
        pass # Replacement never happened or ordinary rollback completed.
    else:raise RuntimeError('Pending install target changed externally; files preserved')
    if value.get('backup'):
        backup=Path(value['backup'])
        if backup.parent==target.parent and backup.name.startswith('.l4d2mc-rollback-') and backup.is_file() and digest(backup)==before:
            backup.unlink()
    journal.unlink()

def install_file(source,target,manifest):
    recover_pending(manifest)
    if not preflight_file(source,target,manifest):
        print(f'Preserved identical pre-existing file without taking ownership: {target}')
        return
    key=str(target.absolute())
    original=digest(target) if target.exists() else None
    target.parent.mkdir(parents=True, exist_ok=True)
    descriptor,filename=tempfile.mkstemp(prefix='.l4d2mc-',dir=target.parent)
    os.close(descriptor);temporary=Path(filename)
    backup=None;keep_backup=False
    had_record=key in manifest;old_record=manifest.get(key)
    try:
        shutil.copy2(source,temporary)
        if digest(source)!=digest(temporary):raise RuntimeError('Staged file hash mismatch: '+str(target))
        expected=digest(temporary)
        if (digest(target) if target.exists() else None)!=original:
            raise RuntimeError('Target changed during staging; user file preserved: '+str(target))
        if target.exists():
            descriptor,filename=tempfile.mkstemp(prefix='.l4d2mc-rollback-',dir=target.parent)
            os.close(descriptor);backup=Path(filename);shutil.copy2(target,backup)
        if (digest(target) if target.exists() else None)!=original:
            raise RuntimeError('Target changed during backup; user file preserved: '+str(target))
        atomic_json(pending_path(),{'target':key,'before':original,'after':expected,
            'owned':had_record,'record':old_record,'backup':str(backup) if backup else None})
        os.replace(temporary,target)
        manifest[key]=expected
        try:
            atomic_receipt(manifest)
        except OSError as error:
            if had_record:manifest[key]=old_record
            else:manifest.pop(key,None)
            try:
                if digest(target)!=expected:raise RuntimeError('Target changed during receipt failure')
                if backup is not None:os.replace(backup,target)
                else:target.unlink()
            except (OSError,RuntimeError) as rollback_error:
                keep_backup=True
                raise RuntimeError('Receipt update failed; rollback requires recovery from '+str(backup)) from rollback_error
            pending_path().unlink(missing_ok=True)
            raise error
        pending_path().unlink(missing_ok=True)
    finally:
        temporary.unlink(missing_ok=True)
        if backup is not None and not keep_backup:backup.unlink(missing_ok=True)


def host(manifest):
    global GAME
    GAME=GAME or game_path()
    if not (GAME / "left4dead2.exe").exists():
        raise RuntimeError("L4D2 installation missing")
    validate_reshade(ROOT/'toolchains/ReShade32.dll')
    for extension in ('mdl','phy','vvd','dx90.vtx'):
        if not (ROOT/'addon/models/l4d2mc'/('cube.'+extension)).is_file():
            raise RuntimeError('Own collision cube missing: run tools/build_assets.py --game <L4D2>')
    for material in ('dirt','stone','wood'):
        for extension in ('vmt','vtf'):
            if not (ROOT/'addon/materials/l4d2mc'/(material+'.'+extension)).is_file():
                raise RuntimeError('Own cube material missing: run tools/build_assets.py --game <L4D2>')
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
        (ROOT / "passthrough/host/l4d2mc_navigation.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_navigation.nut"),
        (ROOT / "passthrough/host/l4d2mc_coop.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_coop.nut"),
        (ROOT / "passthrough/host/l4d2mc_flight.nut", GAME / "left4dead2/scripts/vscripts/l4d2mc_flight.nut"),
        (ROOT / "passthrough/host/l4d2mc_use_press.cfg", GAME / "left4dead2/cfg/l4d2mc_use_press.cfg"),
        (ROOT / "passthrough/host/l4d2mc_use_release.cfg", GAME / "left4dead2/cfg/l4d2mc_use_release.cfg"),
    ]
    files.extend((p, shader_dir / p.name) for p in (ROOT / "passthrough/shaders").glob('*') if p.is_file())
    files.extend((p, GAME / 'left4dead2/models/l4d2mc' / p.name) for p in (ROOT / 'addon/models/l4d2mc').glob('*') if p.is_file())
    files.extend((p, GAME / 'left4dead2/materials/l4d2mc' / p.name) for p in (ROOT / 'addon/materials/l4d2mc').glob('*') if p.is_file())
    for source, target in files:
        install_file(source, target, manifest)
    print("L4D2 loader, adapter, shader and VScript installed.")


def install_guest_profile(source,target,manifest):
    """Preserve a conflicting launcher profile when installing this exact mod ID.

    General file/loader ownership rules still refuse unknown replacements.
    Only this deliberately selected mod profile can be moved aside, reversibly.
    """
    identifier='L4D2MC-Fabric-26.3'
    expected=MINECRAFT/f'versions/{identifier}/{identifier}.json'
    if target.absolute()!=expected.absolute():raise RuntimeError('Unexpected guest profile destination')
    key=str(target.absolute());backup=None
    if target.exists() and key not in manifest and digest(target)!=digest(source):
        if target.is_symlink():raise RuntimeError('Guest profile is a symlink; preserved without replacement')
        import uuid
        backup=target.with_name(target.name+'.l4d2mc-backup-'+uuid.uuid4().hex)
        # Same-directory rename preserves exact bytes, including custom arguments,
        # and never moves/deletes the version folder, accounts, worlds or saves.
        target.rename(backup)
        print('Existing mod profile preserved as: '+str(backup))
    try:install_file(source,target,manifest)
    except BaseException:
        if backup is not None and backup.exists() and not target.exists():backup.rename(target)
        raise


def guest(manifest):
    global MINECRAFT
    MINECRAFT=MINECRAFT or minecraft_path()
    jar = ROOT / "passthrough/guest/build/libs/passthrough-0.2.0.jar"
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
    install_guest_profile(profile, MINECRAFT / f'versions/{identifier}/{identifier}.json', manifest)
    # Fabric API is a public library, not a user's retail asset.
    api_name = 'fabric-api-0.161.0+26.3.jar'
    api = staging / api_name
    if not api.exists():
        urllib.request.urlretrieve('https://maven.fabricmc.net/net/fabricmc/fabric-api/fabric-api/0.161.0+26.3/' + api_name, api)
    install_file(api, GUEST / 'mods' / api_name, manifest)
    print(f"Minecraft profile: {identifier}; separate game directory: {GUEST}")
    print("Launch this version through your normal signed-in launcher.")


def uninstall(manifest):
    recover_pending(manifest)
    changed = []
    for filename, expected in list(manifest.items()):
        path = Path(filename)
        if path.exists() and digest(path) != expected:
            changed.append(filename)
            continue
        if path.exists():
            path.unlink()
        del manifest[filename]
    atomic_receipt(manifest)
    print('Removed own unchanged files. Worlds and launcher data preserved.')
    if changed:
        print('Preserved externally changed files:', changed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['host', 'guest', 'uninstall'])
    parser.add_argument('--game',type=Path)
    parser.add_argument('--minecraft',type=Path,help='Launcher directory containing versions/')
    args = parser.parse_args()
    GAME=game_path(args.game) if args.action=='host' else args.game
    MINECRAFT=minecraft_path(args.minecraft) if args.action=='guest' else args.minecraft
    receipt = json.loads(RECEIPT.read_text(encoding='utf-8')) if RECEIPT.exists() else {}
    {'host':host, 'guest':guest, 'uninstall':uninstall}[args.action](receipt)
