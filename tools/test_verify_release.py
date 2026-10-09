"""Synthetic manifest guards; no physical or network access."""
import json
from pathlib import Path
import tempfile
import unittest
import verify_release as subject


class InventoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'file.txt').write_text('fixture\n')
        self.row = subject.file_identity(self.root / 'file.txt')
        self.manifest({'file.txt': self.row})

    def manifest(self, files):
        (self.root / 'MANIFEST.json').write_text(json.dumps({'files': files}))

    def test_valid(self): self.assertEqual(subject.inventory(self.root, True)['files'], {'file.txt': self.row})

    def test_changed(self):
        (self.root / 'file.txt').write_text('different\n')
        with self.assertRaises(ValueError): subject.inventory(self.root)

    def test_traversal(self):
        for name in ('../outside', '/absolute', 'a/../file.txt', './file.txt', 'a\\file.txt'):
            with self.subTest(name=name):
                with self.assertRaises(ValueError): subject.checked_path(self.root, name)

    def test_symlink(self):
        (self.root / 'alias').symlink_to(self.root / 'file.txt')
        self.manifest({'alias': self.row})
        with self.assertRaises(ValueError): subject.inventory(self.root)

    def test_unlisted_strict(self):
        (self.root / 'private.txt').write_text('do not publish')
        with self.assertRaises(ValueError): subject.inventory(self.root, True)
        self.assertEqual(len(subject.inventory(self.root)['files']), 1)

    def test_missing_asset(self):
        with self.assertRaises(ValueError): subject.verify(self.root)


if __name__ == '__main__': unittest.main()
