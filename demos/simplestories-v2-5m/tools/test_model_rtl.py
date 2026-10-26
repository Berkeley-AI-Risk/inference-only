"""Negative controls for the simulator-log acceptance gate; no hardware access."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('model_checker', ROOT / 'check_model_rtl.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
EXPECTED = json.loads((ROOT.parent / 'simulation/model/expected.json').read_text())['expected_markers']


class ModelLogTests(unittest.TestCase):
    def test_image_directory_is_rejected_before_build_or_work_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            work = Path(temporary) / 'unused-work'
            result = subprocess.run([
                sys.executable, '-I', '-S', '-B', str(ROOT / 'check_model_rtl.py'),
                '--package', str(ROOT.parent), '--image', temporary, '--work', str(work)],
                capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 2)
            self.assertIn('--image must name the binary file, not its directory', result.stderr)
            self.assertFalse(work.exists())

    def test_exact_observations(self):
        for name, markers in EXPECTED.items():
            with self.subTest(case=name):
                self.assertTrue(checker.check_case_log('\n'.join(markers), 0, markers))

    def test_failure_timeout_or_signal(self):
        for name, markers in EXPECTED.items():
            for code in (1, 124, -9):
                with self.subTest(case=name, code=code):
                    self.assertFalse(checker.check_case_log('\n'.join(markers), code, markers))

    def test_every_observation_required(self):
        for name, markers in EXPECTED.items():
            for index in range(len(markers)):
                with self.subTest(case=name, omitted=index):
                    self.assertFalse(checker.check_case_log('\n'.join(markers[:index] + markers[index+1:]), 0, markers))

    def test_duplicate_observation(self):
        for markers in EXPECTED.values():
            self.assertFalse(checker.check_case_log('\n'.join(markers + markers[:1]), 0, markers))

    def test_reordered_observations(self):
        for markers in EXPECTED.values():
            swapped = [markers[1], markers[0]] + markers[2:]
            self.assertFalse(checker.check_case_log('\n'.join(swapped), 0, markers))

    def test_extra_public_token(self):
        for markers in EXPECTED.values():
            text = '\n'.join(markers) + '\nSEMANTIC_STEP token=7\n'
            self.assertFalse(checker.check_case_log(text, 0, markers))

    def test_wrong_token_or_failed_rejection(self):
        for name, markers in EXPECTED.items():
            with self.subTest(case=name):
                text = '\n'.join(markers)
                changed = (text.replace('token=200 ', 'token=201 ', 1) if name in ('zero', 'stalled')
                    else text.replace('public_tokens=0', 'public_tokens=1', 1))
                self.assertNotEqual(text, changed)
                self.assertFalse(checker.check_case_log(changed, 0, markers))

    def test_fatal_even_after_pass(self):
        for markers in EXPECTED.values():
            for fatal in ('%Error', '%Fatal', '%Warning-MULTIDRIVEN', 'Assertion failed', 'Aborting', 'GLOBAL_TIMEOUT'):
                self.assertFalse(checker.check_case_log('\n'.join(markers) + '\n' + fatal, 0, markers))

    def test_empty_expectation(self):
        self.assertFalse(checker.check_case_log('', 0, []))

    def test_ordinary_simulator_finish_is_ignored(self):
        for markers in EXPECTED.values():
            self.assertTrue(checker.check_case_log('\n'.join(markers) + '\n- tb.sv: Simulation finished\n', 0, markers))


if __name__ == '__main__':
    unittest.main()
