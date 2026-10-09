import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import install
from types import SimpleNamespace


class OwnershipTests(unittest.TestCase):
    def test_user_change_during_stage_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source';target=root/'owned';source.write_bytes(b'new');target.write_bytes(b'old')
            manifest={str(target):install.digest(target)};original_copy=install.shutil.copy2
            def concurrent_edit(a,b):
                original_copy(a,b);target.write_bytes(b'user edit')
            with patch.object(install,'RECEIPT',root/'receipt.json'),patch.object(install.shutil,'copy2',side_effect=concurrent_edit):
                with self.assertRaises(RuntimeError):install.install_file(source,target,manifest)
            self.assertEqual(target.read_bytes(),b'user edit')

    def test_recover_replaced_file_after_process_interruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);target=root/'owned';target.write_bytes(b'new')
            old=install.hashlib.sha256(b'old').hexdigest();new=install.digest(target);manifest={str(target):old}
            with patch.object(install,'RECEIPT',root/'receipt.json'):
                install.atomic_json(install.pending_path(),{'target':str(target),'before':old,'after':new,'owned':True,'record':old,'backup':None})
                install.recover_pending(manifest)
                self.assertEqual(manifest[str(target)],new)
                self.assertFalse(install.pending_path().exists())

    def test_recovery_preserves_external_change(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);target=root/'owned';target.write_bytes(b'user edit')
            old=install.hashlib.sha256(b'old').hexdigest();new=install.hashlib.sha256(b'new').hexdigest();manifest={str(target):old}
            with patch.object(install,'RECEIPT',root/'receipt.json'):
                install.atomic_json(install.pending_path(),{'target':str(target),'before':old,'after':new,'owned':True,'record':old,'backup':None})
                with self.assertRaises(RuntimeError):install.recover_pending(manifest)
                self.assertEqual(target.read_bytes(),b'user edit')
                self.assertTrue(install.pending_path().exists())

    def test_receipt_write_failure_rolls_back_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source';target=root/'owned'
            source.write_bytes(b'new');target.write_bytes(b'old');manifest={str(target):install.digest(target)};before=dict(manifest)
            with patch.object(install,'RECEIPT',root/'receipt.json'),patch.object(install,'atomic_receipt',side_effect=OSError('disk full')):
                with self.assertRaises(OSError):install.install_file(source,target,manifest)
            self.assertEqual(target.read_bytes(),b'old')
            self.assertEqual(manifest,before)
            self.assertEqual(list(root.glob('.l4d2mc-*')),[])

    def test_interrupted_copy_preserves_owned_file_and_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);source=root/'source';target=root/'owned';receipt=root/'receipt.json'
            source.write_bytes(b'new');target.write_bytes(b'old');manifest={str(target):install.digest(target)}
            receipt.write_text('old receipt')
            def interrupted(a,b):
                Path(b).write_bytes(b'partial');raise OSError('interrupted')
            with patch.object(install,'RECEIPT',receipt),patch.object(install.shutil,'copy2',side_effect=interrupted):
                with self.assertRaises(OSError):install.install_file(source,target,manifest)
            self.assertEqual(target.read_bytes(),b'old')
            self.assertEqual(receipt.read_text(),'old receipt')
            self.assertEqual(list(root.glob('.l4d2mc-*')),[])

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
