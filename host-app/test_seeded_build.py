"""Offline build/qualification separation for the experimental seeded variant."""
import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_hardware
import runtime_profile


class SeededBuildTests(unittest.TestCase):
    def test_seeded_build_has_its_own_source_inventory(self):
        inputs = runtime_profile.hardware_inputs('seeded-sampling')
        self.assertEqual(len(inputs), 91)
        self.assertEqual(sum(name.startswith('project/official/') for name in inputs), 4)
        self.assertEqual(runtime_profile.variant_settings('seeded-sampling')['hardware_root'],
                         'variants/seeded-sampling/hardware')

    def test_collection_binds_all_distributable_sources_and_external_vendor_files(self):
        # The 87 real distributable inputs are checked byte-for-byte. Four
        # explicitly synthetic vendor stand-ins avoid distributing licensed IP.
        package = Path(__file__).resolve().parents[1]
        inputs = dict(runtime_profile.hardware_inputs('seeded-sampling'))
        with tempfile.TemporaryDirectory() as directory:
            vendor = Path(directory)
            for name in inputs:
                if name.startswith('project/official/'):
                    data = b'OFFLINE VENDOR STAND-IN: ' + Path(name).name.encode()
                    (vendor / Path(name).name).write_bytes(data)
                    inputs[name] = hashlib.sha256(data).hexdigest()
            with patch.object(runtime_profile, 'hardware_inputs', return_value=inputs):
                result = build_hardware.collect(package, vendor, 'seeded-sampling')
                self.assertEqual(set(result), set(inputs))
                changed = next(vendor.iterdir())
                changed.write_bytes(b'changed vendor input')
                with self.assertRaisesRegex(ValueError, 'missing or changed'):
                    build_hardware.collect(package, vendor, 'seeded-sampling')

    def test_unknown_build_variant_is_rejected_before_file_access(self):
        with self.assertRaisesRegex(ValueError, 'Unknown hardware variant'):
            build_hardware.collect(Path('/unused'), Path('/unused'), 'unknown')


if __name__ == '__main__':
    unittest.main()
