import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import update
import install

class AdoptionTests(unittest.TestCase):
    def test_previous_install_files_are_adopted_but_foreign_loaders_are_not(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'new.ini';source.write_text('[ADDON]\nAddonPath=X\\bin\\l4d2mc\n')
            old=root/'ReShade.ini';old.write_text('[ADDON]\nAddonPath=E:\\Games\\L4D2\\bin\\l4d2mc\n[GENERAL]\n')
            self.assertTrue(install.preflight_file(source,old,{}))
            foreign=root/'ReShade.ini';foreign.write_text('[ADDON]\nAddonPath=C:\\other\\addons\n')
            with self.assertRaises(RuntimeError):install.preflight_file(source,foreign,{})
            dll=root/'d3d9.dll';dll.write_bytes(b'other loader')
            with self.assertRaises(RuntimeError):install.preflight_file(source,dll,{})
            ours=root/'l4d2mc'/'preset.ini';ours.parent.mkdir();ours.write_text('old')
            self.assertTrue(install.preflight_file(source,ours,{}))

class UpdatePreflightTests(unittest.TestCase):
    def test_missing_late_component_never_updates_earlier_files(self):
        self.check_preflight('missing')
    def test_modified_late_target_never_updates_earlier_files(self):
        self.check_preflight('external')
    def check_preflight(self,failure):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);game=root/'game';guest=root/'guest';receipt=root/'receipt.json'
            with patch.object(update,'ROOT',root),patch.object(update,'GUEST',guest),patch.object(update,'RECEIPT',receipt),patch.object(install,'RECEIPT',receipt):
                pairs=[(root/'passthrough/guest/build/libs/passthrough-0.1.0.jar',guest/'mods/l4d2mc-guest.jar'),
                    (root/'dist/L4D2Minecraft.addon32',game/'bin/l4d2mc/L4D2Minecraft.addon32'),
                    (root/'dist/l4d2mc_hud.vpk',game/'left4dead2/addons/l4d2mc_hud.vpk')]
                pairs.extend((root/'passthrough/shaders'/n,game/'bin/l4d2mc/shaders'/n) for n in ('TeamHud.fxh','L4D2Minecraft.fx'))
                pairs.extend((root/'passthrough/host'/n,game/'left4dead2/scripts/vscripts'/n) for n in ('l4d2mc_bridge.nut','l4d2mc_gameplay.nut','l4d2mc_survival.nut','l4d2mc_navigation.nut','l4d2mc_coop.nut','l4d2mc_flight.nut'))
                manifest={}
                pairs.extend((root/'passthrough/host'/n,game/'left4dead2/cfg'/n) for n in ('l4d2mc_use_press.cfg','l4d2mc_use_release.cfg'))
                for source,target in pairs:
                    source.parent.mkdir(parents=True,exist_ok=True);target.parent.mkdir(parents=True,exist_ok=True)
                    source.write_bytes(b'new');target.write_bytes(b'old');manifest[str(target)]=install.digest(target)
                receipt.write_text(json.dumps(manifest))
                if failure=='missing':pairs[-1][0].unlink()
                else:pairs[-1][1].write_bytes(b'user modification')
                with self.assertRaises(RuntimeError):update.update(game)
                self.assertEqual(pairs[0][1].read_bytes(),b'old')
                self.assertEqual(json.loads(receipt.read_text()),manifest)
