from pathlib import Path
import tempfile
import unittest
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
import release_source as release

class ReleaseTests(unittest.TestCase):
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
