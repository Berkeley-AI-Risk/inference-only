"""Offline downloader guards. No live network, vendor program or hardware."""
import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import fetch_vendor as subject


class FetchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve() / 'vendor'
        self.data = b'original vendor input\n'
        self.pin = ('sub/file.v', len(self.data), hashlib.sha256(self.data).hexdigest())
        self.patcher = patch.object(subject, 'FILES', {'file.v': self.pin})
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def download(self, url, timeout):
        self.assertEqual(url, subject.BASE + 'sub/file.v')
        self.assertEqual(timeout, 90)
        return io.BytesIO(self.data)

    def test_fetch_and_offline_recheck(self):
        self.assertTrue(subject.acquire(self.root, opener=self.download)['passed'])
        with patch.object(subject.urllib.request, 'urlopen', side_effect=AssertionError('network')):
            self.assertTrue(subject.acquire(self.root, check=True)['passed'])

    def test_existing_match_does_not_fetch(self):
        subject.acquire(self.root, opener=self.download)
        self.assertTrue(subject.acquire(self.root, opener=lambda *a, **k: self.fail('network'))['passed'])

    def test_changed_existing_file_is_not_overwritten(self):
        subject.acquire(self.root, opener=self.download)
        (self.root / 'file.v').write_bytes(b'x' * len(self.data))
        with self.assertRaises(ValueError): subject.acquire(self.root, opener=self.download)
        self.assertEqual((self.root / 'file.v').read_bytes(), b'x' * len(self.data))

    def test_bad_download_not_published(self):
        with self.assertRaises(ValueError):
            subject.acquire(self.root, opener=lambda *a, **k: io.BytesIO(b'wrong'))
        self.assertFalse((self.root / 'file.v').exists())

    def test_offline_missing_file_fails_without_directory_creation(self):
        with self.assertRaises(FileNotFoundError): subject.acquire(self.root, check=True)
        self.assertFalse(self.root.exists())

    def test_symlink_rejected(self):
        self.root.mkdir()
        (self.root / 'file.v').symlink_to(self.root.parent / 'elsewhere')
        with self.assertRaises(ValueError): subject.acquire(self.root, opener=self.download)


if __name__ == '__main__': unittest.main()
