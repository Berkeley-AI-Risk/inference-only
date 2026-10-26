"""Build-tool fixture tests; no GOWIN process or physical board is used."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_hardware
import runtime_profile as profile


class BuildTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='fpga-build-offline-')
        self.root = Path(self.directory.name)
        self.package, self.vendor, self.ide = [self.root / n for n in ('package', 'vendor', 'ide')]
        self.files = {'project/source-' + str(i) + '.sv': ('OFFLINE SOURCE ' + str(i)).encode() for i in range(86)}
        self.files.update({'project/official/' + n: ('OFFLINE VENDOR FIXTURE ' + n).encode() for n in build_hardware.VENDOR_NAMES})
        self.inventory = {name: profile.sha(data) for name, data in self.files.items()}
        for name, data in self.files.items():
            path = self.vendor / Path(name).name if '/official/' in name else self.package / 'hardware' / name
            profile.private_write(path, data)
        self.executable = self.ide / 'bin/gw_sh'
        profile.private_write(self.executable, b'OFFLINE EXECUTABLE FIXTURE; NOT EXECUTABLE')

    def tearDown(self): self.directory.cleanup()

    def test_collect_exact_90_input_files_and_external_vendor_directory(self):
        with patch.object(profile, 'hardware_inputs', return_value=self.inventory):
            self.assertEqual(build_hardware.collect(self.package, self.vendor), self.files)
        self.assertFalse((self.package / 'hardware/project/official').exists())

    def test_changed_source_and_missing_vendor_rejected(self):
        with patch.object(profile, 'hardware_inputs', return_value=self.inventory):
            target = self.package / 'hardware/project/source-0.sv'
            target.write_bytes(b'CHANGED TEST FIXTURE')
            with self.assertRaises(ValueError): build_hardware.collect(self.package, self.vendor)
            target.write_bytes(self.files['project/source-0.sv'])
            with self.assertRaises(OSError): build_hardware.collect(self.package, self.root / 'absent-vendor')

    def test_preflight_is_read_only_and_requires_explicit_terms_confirmation(self):
        destination = self.root / 'never-created'
        with patch.object(build_hardware, 'collect', return_value=self.files), \
             patch.object(build_hardware.sys, 'platform', 'darwin'), \
             patch.object(build_hardware, 'GW_SHA256', profile.sha(self.executable.read_bytes())), \
             patch.object(build_hardware.subprocess, 'Popen', side_effect=AssertionError('No process allowed')):
            with self.assertRaises(ValueError):
                build_hardware.build(self.package, self.vendor, self.ide, destination, acknowledge_terms=False, preflight_only=True)
            result = build_hardware.build(self.package, self.vendor, self.ide, destination, acknowledge_terms=True, preflight_only=True)
            self.assertTrue(result['passed'])
            self.assertFalse(result['writes'] or result['hardware_access'] or destination.exists())

    def test_wrong_tool_and_existing_output_rejected_before_process(self):
        with patch.object(build_hardware, 'collect', return_value=self.files), \
             patch.object(build_hardware.sys, 'platform', 'darwin'), \
             patch.object(build_hardware.subprocess, 'Popen', side_effect=AssertionError('No process allowed')):
            with self.assertRaises(ValueError):
                build_hardware.build(self.package, self.vendor, self.ide, self.root / 'new', acknowledge_terms=True)
            with patch.object(build_hardware, 'GW_SHA256', profile.sha(self.executable.read_bytes())):
                with self.assertRaises(FileExistsError):
                    build_hardware.build(self.package, self.vendor, self.ide, self.root, acknowledge_terms=True)

    def test_failed_mock_compiler_writes_failed_receipt_not_qualification(self):
        sources = {'run.tcl': b'OFFLINE TCL FIXTURE', 'project/product.gprj': b'<offline-test />'}
        class FailedChild:
            pid = 12345
            def wait(self): return 1
        with patch.object(build_hardware, 'collect', return_value=sources), \
             patch.object(build_hardware.sys, 'platform', 'darwin'), \
             patch.object(build_hardware, 'GW_SHA256', profile.sha(self.executable.read_bytes())), \
             patch.object(build_hardware.subprocess, 'Popen', return_value=FailedChild()):
            output = self.root / 'mock-failed-build'
            result = build_hardware.build(self.package, self.vendor, self.ide, output, acknowledge_terms=True)
        self.assertFalse(result['flow_completed'] or result['timing_qualified'] or result['board_load_allowed'])
        self.assertTrue(result['source_inputs_unchanged'])
        self.assertEqual(json.loads((output / 'BUILD.json').read_text()), result)
        with self.assertRaises(ValueError): profile.check_build(output / 'BUILD.json')

    def successful_mock_build(self, name, image_bytes):
        sources = {'run.tcl': b'OFFLINE TCL FIXTURE', 'project/product.gprj': b'<offline-test />'}
        output = self.root / name
        class Child:
            pid = 12345
            def wait(self): return 0
        def launch(argv, **kwargs):
            if argv[0] != '/usr/bin/caffeinate':
                kwargs['stdout'].write(b'LOCAL_KV_SYN_COMPLETE hardware_access=0\nLOCAL_KV_NATIVE_COMPLETE hardware_access=0\n')
                image = output / 'project/impl/pnr/shared_product.fs'
                image.parent.mkdir(parents=True)
                with image.open('wb') as handle:
                    handle.truncate(image_bytes)  # Sparse synthetic file, not an FPGA configuration.
            return Child()
        with patch.object(build_hardware, 'collect', return_value=sources), \
             patch.object(build_hardware.sys, 'platform', 'darwin'), \
             patch.object(build_hardware, 'GW_SHA256', profile.sha(self.executable.read_bytes())), \
             patch.object(build_hardware.subprocess, 'Popen', side_effect=launch):
            result = build_hardware.build(self.package, self.vendor, self.ide, output, acknowledge_terms=True)
        self.assertEqual(json.loads((output / 'BUILD.json').read_text()), result)
        self.assertEqual(json.loads((output / 'TOOL-FINISHED.json').read_text())['exit'], 0)
        self.assertFalse(result['timing_qualified'] or result['board_load_allowed'] or result['hardware_access'])
        return result, output

    def test_realistic_large_compiler_output_has_completed_receipt(self):
        result, output = self.successful_mock_build('large-image', 41_329_247)
        self.assertTrue(result['flow_completed'] and result['source_inputs_unchanged'])
        self.assertEqual(result['validation_errors'], [])
        self.assertEqual(result['image_bytes'], 41_329_247)
        self.assertEqual(profile.check_build(output / 'BUILD.json')['image_sha256'], result['image_sha256'])

    def test_oversize_compiler_output_preserves_failed_receipt(self):
        result, output = self.successful_mock_build('oversize-image', profile.MAX_BITSTREAM_BYTES + 1)
        self.assertFalse(result['flow_completed'])
        self.assertEqual(result['exit'], 0)  # Tool success is distinct from wrapper validation.
        self.assertTrue(any('bounded regular file' in message for message in result['validation_errors']))
        self.assertIsNone(result['image_sha256'])
        with self.assertRaises(ValueError): profile.check_build(output / 'BUILD.json')


if __name__ == '__main__': unittest.main(verbosity=2)
