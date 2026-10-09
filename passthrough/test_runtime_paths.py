import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import runtime_paths as paths

class RuntimePathTests(unittest.TestCase):
    def test_explicit_overrides_environment_and_local(self):
        with patch.dict(paths.os.environ,{'L4D2MC_GAME':'env-game'}),patch.object(paths,'configuration',return_value={'game':'local-game'}):
            self.assertEqual(paths.game_path('explicit-game'),Path('explicit-game'))
            self.assertEqual(paths.game_path(),Path('env-game'))
    def test_explicit_never_reads_broken_config(self):
        with patch.dict(paths.os.environ,{},clear=True),patch.object(paths,'configuration',side_effect=ValueError('broken')):
            self.assertEqual(paths.game_path('explicit'),Path('explicit'))
            self.assertEqual(paths.minecraft_path('explicit-mc'),Path('explicit-mc'))
    def test_secondary_steam_library_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);other=root/'Other library'
            target=other/'steamapps/common/Left 4 Dead 2';target.mkdir(parents=True);(target/'left4dead2.exe').touch()
            with patch.dict(paths.os.environ,{},clear=True),patch.object(paths,'configuration',return_value={}),patch.object(paths,'steam_roots',return_value=[root,other]):self.assertEqual(paths.game_path(),target)
    def test_local_config_never_accepts_nonpath(self):
        with tempfile.TemporaryDirectory() as directory:
            config=Path(directory)/'local.json';config.write_text(json.dumps({'game':False}))
            with patch.object(paths,'LOCAL',config),self.assertRaises(ValueError):paths.configuration()
    def test_minecraft_custom_launcher_path(self):
        with patch.dict(paths.os.environ,{},clear=True),patch.object(paths,'configuration',return_value={'minecraft':'custom launcher/game'}):self.assertEqual(paths.minecraft_path(),Path('custom launcher/game'))
