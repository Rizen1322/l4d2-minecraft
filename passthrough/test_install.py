import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import install


class OwnershipTests(unittest.TestCase):
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
