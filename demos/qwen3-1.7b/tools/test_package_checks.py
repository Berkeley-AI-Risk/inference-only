"""Standard-library tests; no FPGA, AWS, vendor tool or model download."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hardware = load('prepare_hardware', HERE/'prepare_hardware.py')
reports = load('check_routed_reports', HERE/'check_routed_reports.py')
package = load('qwen_public_package', ROOT.parents[1]/'tools/check_qwen_package.py')


class PackageChecks(unittest.TestCase):
    def installation_inputs(self):
        return [json.loads((ROOT/name).read_text()) for name in (
            'deployment.json', 'evidence/installation.json',
            'evidence/installation-controller.json', 'measurements.json')]

    def test_installation_receipt(self):
        self.assertEqual(package.check_installation(ROOT, *self.installation_inputs()), 390)

    def test_installation_false_claims_rejected(self):
        for index, key in ((0, 'public_load_permission_verified'), (1, 'fresh_model_upload'),
                           (1, 'slot_reloaded'), (2, 'passed')):
            inputs = self.installation_inputs()
            inputs[index][key] = False
            with self.subTest(key=key), self.assertRaises(ValueError):
                package.check_installation(ROOT, *inputs)

    def test_wrong_installed_image_rejected(self):
        inputs = self.installation_inputs()
        inputs[1]['fpga_image_global_id'] = 'agfi-not-the-measured-image'
        with self.assertRaises(ValueError):
            package.check_installation(ROOT, *inputs)

    def test_wrong_installation_token_rejected(self):
        inputs = self.installation_inputs()
        inputs[2]['cases'][0]['steps'][0]['token'] += 1
        with self.assertRaises(ValueError):
            package.check_installation(ROOT, *inputs)

    def test_missing_installation_case_rejected(self):
        inputs = self.installation_inputs()
        inputs[2]['cases'].pop()
        with self.assertRaises(ValueError):
            package.check_installation(ROOT, *inputs)

    def test_selected_hardware_inputs(self):
        inputs, metadata = hardware.verify()
        self.assertEqual(len(inputs), 111)
        self.assertEqual(metadata['clock_recipes']['a'], 'A0')

    def test_staging_and_overwrite_rejection(self):
        with tempfile.TemporaryDirectory(prefix='qwen-release-') as work:
            output = Path(work)/'build'
            result = hardware.prepare(output)
            self.assertTrue(result['passed'])
            self.assertTrue((output/'cl_qwen/design/cl_qwen.sv').is_file())
            with self.assertRaises(ValueError):
                hardware.prepare(output)
            with self.assertRaises(ValueError):
                hardware.prepare(Path(work)/'with spaces')

    def test_changed_source_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            inputs, _ = hardware.verify()
            for name in [*inputs, 'SOURCE-INPUTS.json', 'hardware/IMPLEMENTATION-INPUTS.json']:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT/name, target)
            chosen = root/next(iter(inputs))
            chosen.write_bytes(chosen.read_bytes()+b'\n')
            with self.assertRaisesRegex(ValueError, 'Changed frozen input'):
                hardware.verify(root)

    def test_escaping_input_rejected(self):
        for name in ('../README.md', '/README.md', 'a\\b'):
            with self.assertRaises(ValueError):
                hardware.checked_path(ROOT, name)

    def test_recorded_reports_pass(self):
        result = reports.check(ROOT/'evidence/implementation')
        self.assertEqual(result['routed_nets'], 1044328)
        self.assertEqual(result['setup_slack_ns'], 0.132)

    def altered_report(self, filename, old, new):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            for name in ('timing-summary.rpt', 'route-status.rpt', 'drc.rpt'):
                text = (ROOT/'evidence/implementation'/name).read_text()
                if name == filename:
                    self.assertIn(old, text)
                    text = text.replace(old, new, 1)
                (root/name).write_text(text)
            with self.assertRaises(ValueError):
                reports.check(root)

    def test_bad_setup_rejected(self):
        self.altered_report('timing-summary.rpt', '0.132', '-0.132')

    def test_missing_timing_verdict_rejected(self):
        self.altered_report('timing-summary.rpt',
            'All user specified timing constraints are met.', 'Timing constraints are NOT met.')

    def test_incomplete_route_rejected(self):
        self.altered_report('route-status.rpt', '# of fully routed nets', '# of incompletely routed nets')

    def test_drc_error_rejected(self):
        self.altered_report('drc.rpt', '| Warning', '| Error  ')

    def test_missing_report_rejected(self):
        with tempfile.TemporaryDirectory() as work:
            with self.assertRaises(FileNotFoundError):
                reports.check(Path(work))

    def test_reference_file_validation(self):
        reference = load('qwen_reference_image_loader', ROOT/'reference/model_image.py')
        with tempfile.TemporaryDirectory() as work:
            path = Path(work)/'input.bin'
            data = b'fixed test input'
            path.write_bytes(data)
            sha = hashlib.sha256(data).hexdigest()
            self.assertEqual(reference.checked_file(path, len(data), sha), path)
            with self.assertRaises(ValueError):
                reference.checked_file(path, len(data)+1, sha)
            path.write_bytes(b'changed input!!!')
            with self.assertRaises(ValueError):
                reference.checked_file(path, len(data), sha)

    def test_reference_source_hashes(self):
        record = json.loads((ROOT/'reference/SOURCE-BINDING.json').read_text())
        self.assertEqual(len(record['files']), 6)
        for name, row in record['files'].items():
            self.assertEqual(hashlib.sha256((ROOT/'reference'/name).read_bytes()).hexdigest(),
                             row['public_sha256'])

    def test_report_hashes(self):
        root = ROOT/'evidence/implementation'
        record = json.loads((root/'REPORTS.json').read_text())
        self.assertEqual(len(record['reports']), 19)
        for name, row in record['reports'].items():
            self.assertEqual(hardware.digest(root/name), row['public']['sha256'])
            self.assertEqual((root/name).stat().st_size, row['public']['bytes'])


if __name__ == '__main__':
    unittest.main()
