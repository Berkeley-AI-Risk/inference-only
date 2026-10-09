"""Offline guards for the staged faster build identity; no device access."""
import json
from pathlib import Path
import tempfile
import unittest
import runtime_profile as profile


class FasterTargetTests(unittest.TestCase):
    def test_exact_faster_inventory(self):
        self.assertEqual(profile.HARDWARE_INPUTS_SHA256, "8955cde51f78b582612ca4ee61d146b6128a85a535b3d492d325a4168f77e334")
        self.assertEqual(len(profile.hardware_inputs()), 90)

    def test_older_native6_receipt_rejected(self):
        with tempfile.TemporaryDirectory(prefix="offline-old-build-") as folder:
            path = Path(folder) / "BUILD.json"
            record = {"schema": profile.BUILD_SCHEMA, "flow_completed": True,
                "source_inputs_verified": True, "source_inputs_unchanged": True,
                "hardware_inputs_sha256": "6d4bfa769a0526b075ed44b0bc302e132c77008d86cacd7451a5b6755430b9fc"}
            path.write_text(json.dumps(record))
            with self.assertRaisesRegex(ValueError, "selected sources"):
                profile.check_build(path)


if __name__ == "__main__":
    unittest.main()
