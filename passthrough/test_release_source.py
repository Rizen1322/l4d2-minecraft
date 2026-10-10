from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import release_source as release

class ReleaseTests(unittest.TestCase):
    def test_release_includes_coop_entrypoints_but_not_extracted_repair_copies(self):
        for name in ['Auto-Setup-L4D2MC.cmd','Auto-Setup-L4D2MC.ps1','Coop.bat','Update-Coop.cmd','tools/coop_wizard.ps1','tools/update_coop.ps1','tools/test_launcher_arguments.ps1','docs/assets/coop-preview.png']:
            self.assertTrue(release.permitted(name),name)
        for name in ['docs/passthrough/private.json','docs/tools/token.json','docs/Launch-Minecraft.ps1','docs/assets/random-game-portrait.png','l4d2mc.coop.json','l4d2mc.coop.json.tmp']:
            self.assertFalse(release.permitted(name),name)
    def test_private_game_assets_and_profile_never_ship(self):
        for p in ['passthrough/guest-game/saves/world/level.dat','dist/l4d2mc_hud_assets/assets/a.png','l4d2mc.local.json','.env','passthrough/guest/build/libs/mod.jar','research/token.txt']:
            self.assertFalse(release.permitted(p),p)
        self.assertTrue(release.permitted('passthrough/guest/gradle/wrapper/gradle-wrapper.jar'))
        self.assertTrue(release.permitted('passthrough/host/l4d2mc_gameplay.nut'))
    def test_secret_in_source_stops_publication(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'README.md').write_text('README');(root/'LICENSE').write_text('license')
            (root/'tools').mkdir();(root/'tools/release_source.py').write_text('token = "ghp_'+'X'*36+'"')
            with self.assertRaises(ValueError):release.collect(root)
    def test_archive_is_reproducible_and_manifested(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);(root/'README.md').write_text('README');(root/'LICENSE').write_text('license')
            first=release.package(root,root/'one.zip');second=release.package(root,root/'two.zip')
            self.assertEqual(first.read_bytes(),second.read_bytes())
