"""Synthetic file/region guards; no physical flash or model inference."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_flash_layout as checker


class FlashLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = b'\x42' * checker.MODEL_BYTES
        cls.array = b'\xff' * checker.BASE + cls.model + b'\xff' * (checker.CAPACITY - checker.BASE - len(cls.model))

    def test_exact_regions(self):
        checker.compare_regions(self.model, self.array)

    def test_every_region_boundary_rejects_corruption(self):
        end = checker.BASE + checker.MODEL_BYTES
        for offset in (0, checker.BASE - 1, checker.BASE, end - 1, end, checker.CAPACITY - 1):
            with self.subTest(offset=offset):
                changed = bytearray(self.array)
                changed[offset] ^= 1
                with self.assertRaises(ValueError):
                    checker.compare_regions(self.model, changed)

    def test_lengths_and_wrong_offset_rejected(self):
        for model, readback in ((self.model[:-1], self.array), (self.model, self.array[:-1]),
                                (self.model, self.array + b'\xff'), (self.model, self.array[1:] + b'\xff')):
            with self.assertRaises(ValueError):
                checker.compare_regions(model, readback)

    def test_wrong_model_rejected_before_readback(self):
        with tempfile.TemporaryDirectory(prefix='flash-layout-fixture-') as directory:
            path = Path(directory) / 'wrong-model.bin'
            path.write_bytes(self.model)
            with self.assertRaisesRegex(ValueError, 'selected fixed-model'):
                checker.check_layout(path, Path(directory) / 'does-not-exist')

    def test_file_guards_and_equal_backups(self):
        with tempfile.TemporaryDirectory(prefix='flash-backup-fixture-') as directory:
            first, second = (Path(directory) / name for name in ('first.bin', 'second.bin'))
            first.write_bytes(self.array)
            second.write_bytes(self.array)
            self.assertTrue(checker.check_backups(first, second)['passed'])
            with self.assertRaisesRegex(ValueError, 'distinct files'):
                checker.check_backups(first, first)
            linked = Path(directory) / 'hard-link.bin'
            os.link(first, linked)
            with self.assertRaisesRegex(ValueError, 'distinct files'):
                checker.check_backups(first, linked)
            symbolic = Path(directory) / 'symbolic.bin'
            symbolic.symlink_to(first)
            with self.assertRaisesRegex(ValueError, 'regular file'):
                checker.check_backups(first, symbolic)
            second.write_bytes(self.array[:-1] + b'\x00')
            with self.assertRaisesRegex(ValueError, 'files differ'):
                checker.check_backups(first, second)
            second.write_bytes(b'')
            with self.assertRaisesRegex(ValueError, 'regular file'):
                checker.check_backups(first, second)

    def test_nonregular_file_is_not_opened(self):
        with tempfile.TemporaryDirectory(prefix='flash-file-fixture-') as directory:
            with patch.object(checker.os, 'open', side_effect=AssertionError('Must not open a directory')):
                with self.assertRaisesRegex(ValueError, 'regular file'):
                    checker.read_regular(directory, checker.CAPACITY)


if __name__ == '__main__':
    unittest.main(verbosity=2)
