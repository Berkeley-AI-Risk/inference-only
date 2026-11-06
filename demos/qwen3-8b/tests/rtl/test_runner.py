"""Small harness controls; they do not substitute for native RTL execution."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('qwen_arithmetic_regression', HERE/'run.py')
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class RunnerTests(unittest.TestCase):
    def dot_summary(self, groups=512):
        return dict(passed=True, groups=groups, frames=326, accepted_beats=groups*326,
                    checked_products=groups*326*8, cancellations=6, input_bubbles=1,
                    held_checks=1, cycles=groups*326+100)

    def test_plan_keeps_production_lengths_and_edge_case_separate(self):
        cases = RUNNER.plans('dot8')
        self.assertEqual([case['groups'] for case in cases], [1, 512, 1536])
        self.assertEqual(len(RUNNER.plans('all')), 4)

    def test_unknown_suite_rejected(self):
        with self.assertRaises(ValueError):
            RUNNER.plans('missing')

    def test_sources_match_frozen_manifest(self):
        binding = RUNNER.verify_sources(RUNNER.plans('all'))
        self.assertEqual(binding['production_groups'], [512, 1536])
        self.assertIn('isSigNaNRecFN.v', binding['files'])
        self.assertIn('qwen_projection_engine.sv', binding['files'])

    def test_missing_source_binding_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'SOURCE-INPUTS.json').write_text(json.dumps({'frozen_hardware_inputs': {}}))
            with self.assertRaises(ValueError):
                RUNNER.verify_sources(RUNNER.plans('dot8'), root)

    def test_changed_source_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root/'hardware/design'
            source.mkdir(parents=True)
            manifest = json.loads((RUNNER.ROOT/'SOURCE-INPUTS.json').read_text())
            (root/'SOURCE-INPUTS.json').write_text(json.dumps(manifest))
            (source/'private_dot8_accumulator.sv').write_text('changed source')
            with self.assertRaises(ValueError):
                RUNNER.verify_sources(RUNNER.plans('dot8'), root)

    def test_complete_dot_counts(self):
        case = RUNNER.plans('dot8')[1]
        RUNNER.validate_summary(case, self.dot_summary())

    def test_incomplete_or_false_dot_counts_rejected(self):
        case = RUNNER.plans('dot8')[1]
        for key, value in [('passed', False), ('groups', 1), ('frames', 325),
                           ('accepted_beats', 1), ('checked_products', 0),
                           ('held_checks', 0), ('cancellations', 0), ('cycles', True)]:
            record = self.dot_summary()
            record[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                RUNNER.validate_summary(case, record)

    def test_scale_counts_require_actual_checks_and_cancellations(self):
        case = RUNNER.plans('scale')[0]
        record = dict(passed=True, inputs=12000, checked=11900, cancelled=100,
                      clears=1, resets=1, held_checks=1, error_results=1, cycles=15000)
        RUNNER.validate_summary(case, record)
        for key in ('checked', 'clears', 'resets', 'held_checks', 'error_results'):
            changed = copy.deepcopy(record)
            changed[key] = 0
            with self.subTest(key=key), self.assertRaises(ValueError):
                RUNNER.validate_summary(case, changed)

    def test_plan_cli_never_runs_native_tools(self):
        result = subprocess.run([sys.executable, '-I', '-S', '-B', str(HERE/'run.py'), '--plan'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertFalse(record['native_tools_run'])
        self.assertFalse(record['hardware_access'])

    def test_output_refuses_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, '-I', '-S', '-B', str(HERE/'run.py'),
                                     '--output', directory], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_owned_command_preserves_nonzero_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                RUNNER.command([sys.executable, '-I', '-S', '-B', '-c', 'raise SystemExit(7)'], root, root/'command', 5)
            receipt = json.loads((root/'command/EXIT.json').read_text())
            self.assertEqual(receipt['actual_child_exit'], 7)
            self.assertFalse(receipt['interrupted_or_timed_out'])

    def test_owned_timeout_preserves_actual_interruption(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                RUNNER.command([sys.executable, '-I', '-S', '-B', '-c', 'import time; time.sleep(10)'], root, root/'command', .03)
            receipt = json.loads((root/'command/EXIT.json').read_text())
            self.assertNotEqual(receipt['actual_child_exit'], 0)
            self.assertTrue(receipt['interrupted_or_timed_out'])
            self.assertEqual(receipt['interruption']['type'], 'TimeoutExpired')


if __name__ == '__main__':
    unittest.main(verbosity=2)
