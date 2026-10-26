"""Synthetic manifest guards; no physical or network access."""
import json
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
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


class RepositoryContractTests(unittest.TestCase):
    def setUp(self):
        # Keep the hard-linked fixture on the checker's filesystem in CI too.
        self.temp = tempfile.TemporaryDirectory(
            dir=Path(subject.__file__).resolve().parent, prefix='.contract-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        (self.root / 'tools').mkdir()
        self.payload = self.root / 'file.txt'
        self.payload.write_text('reviewed payload\n')
        # The check must run from the exact selected entrypoint. A hard link
        # preserves that identity without changing the actual checker source.
        os.link(Path(subject.__file__), self.root / 'tools/verify_release.py')
        self.contract = self.root / subject.ROOT_CONTRACT
        self.contract.write_text(json.dumps({
            'schema':'reviewed-whole-repository-byte-contract-v1',
            'files':{'file.txt':subject.file_identity(self.payload)},
        }))
        self.expected_sha = hashlib.sha256(self.contract.read_bytes()).hexdigest()
        self.manifest = {'files':{
            'file.txt':subject.file_identity(self.payload),
            subject.ROOT_CONTRACT:subject.file_identity(self.contract),
            'tools/verify_release.py':subject.file_identity(self.root / 'tools/verify_release.py'),
        }}

    def check(self):
        with mock.patch.object(subject, 'ROOT_CONTRACT_SHA', self.expected_sha):
            subject.verify_repository_contract(self.root, self.manifest)

    def test_exact_reviewed_contract_passes(self):
        self.check()

    def test_changed_payload_and_refreshed_manifest_are_rejected(self):
        self.payload.write_text('unreviewed replacement\n')
        self.manifest['files']['file.txt'] = subject.file_identity(self.payload)
        with self.assertRaisesRegex(ValueError, 'reviewed member contract'):
            self.check()

    def test_changed_ledger_and_refreshed_manifest_are_rejected(self):
        self.payload.write_text('unreviewed replacement\n')
        ledger = json.loads(self.contract.read_text())
        ledger['files']['file.txt'] = subject.file_identity(self.payload)
        self.contract.write_text(json.dumps(ledger))
        self.manifest['files']['file.txt'] = subject.file_identity(self.payload)
        self.manifest['files'][subject.ROOT_CONTRACT] = subject.file_identity(self.contract)
        with self.assertRaisesRegex(ValueError, 'byte contract changed'):
            self.check()

    def test_missing_declared_member_is_rejected(self):
        del self.manifest['files']['file.txt']
        with self.assertRaisesRegex(ValueError, 'reviewed member contract'):
            self.check()


if __name__ == '__main__': unittest.main()
