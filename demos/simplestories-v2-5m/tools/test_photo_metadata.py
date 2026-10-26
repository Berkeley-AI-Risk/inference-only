"""Photo-checker CLI regressions and metadata rejection; no hardware access."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import check_photo_metadata as subject


class PhotoMetadataTests(unittest.TestCase):
    root = Path(__file__).resolve().parents[1]
    script = root / 'tools/check_photo_metadata.py'
    photo = root / 'fpga.jpeg'

    def run_check(self, cwd, *arguments):
        result = subprocess.run(
            [sys.executable, '-I', '-S', '-B', str(self.script), *arguments],
            cwd=cwd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_default_from_repository_root(self):
        self.assertEqual(self.run_check(self.root), subject.check(self.photo))

    def test_default_from_unrelated_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertEqual(self.run_check(directory), subject.check(self.photo))

    def test_explicit_relative_path(self):
        self.assertEqual(self.run_check(self.root, 'fpga.jpeg'), subject.check(self.photo))

    def test_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'metadata.jpeg'
            raw = self.photo.read_bytes()
            path.write_bytes(raw[:2] + b'\xff\xe1\x00\x08Exif\x00\x00' + raw[2:])
            with self.assertRaisesRegex(ValueError, 'Embedded metadata'):
                subject.check(path)

    def test_trailing_bytes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'trailer.jpeg'
            path.write_bytes(self.photo.read_bytes() + b'private data')
            with self.assertRaisesRegex(ValueError, 'Trailing data'):
                subject.check(path)


if __name__ == '__main__':
    unittest.main()
