import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import install
from types import SimpleNamespace


class OwnershipTests(unittest.TestCase):
    def test_invalid_loader_refused_before_game_writes(self):
        with tempfile.TemporaryDirectory() as directory:
            loader=Path(directory)/'loader.dll';loader.write_bytes(b'not a PE')
            with self.assertRaises(RuntimeError):install.validate_reshade(loader)
            with self.assertRaises(RuntimeError):install.validate_reshade(Path(directory))

    def test_x64_reshade_refused_and_x86_api_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            loader=Path(directory)/'loader.dll';loader.touch()
            binary=SimpleNamespace(FILE_HEADER=SimpleNamespace(Machine=0x8664),
                DIRECTORY_ENTRY_EXPORT=SimpleNamespace(symbols=[SimpleNamespace(name=n) for n in (b'ReShadeRegisterAddon',b'ReShadeUnregisterAddon')]),close=lambda:None)
            with patch('pefile.PE',return_value=binary):
                with self.assertRaises(RuntimeError):install.validate_reshade(loader)
                binary.FILE_HEADER.Machine=0x14c;install.validate_reshade(loader)

    def test_identical_existing_file_never_becomes_owned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root/'source', root/'existing'
            source.write_bytes(b'unchanged')
            target.write_bytes(b'unchanged')
            manifest = {}
            with patch.object(install,'RECEIPT',root/'receipt.json'):
                install.install_file(source,target,manifest)
            self.assertEqual(manifest,{})
            self.assertEqual(target.read_bytes(),b'unchanged')

    def test_changed_user_file_is_preserved_on_uninstall(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, target = root/'source', root/'owned'
            source.write_bytes(b'ours')
            manifest = {}
            with patch.object(install,'RECEIPT',root/'receipt.json'):
                install.install_file(source,target,manifest)
                target.write_bytes(b'user change')
                install.uninstall(manifest)
            self.assertEqual(target.read_bytes(),b'user change')
            self.assertIn(str(target),manifest)


if __name__ == '__main__':
    unittest.main()
