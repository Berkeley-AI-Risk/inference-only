import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('h100', HERE / 'check_h100_reference.py')
H100 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(H100)


class H100ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.result = json.loads((HERE.parent / H100.SELECTED).read_text())

    def test_full_saved_evidence(self):
        checked = H100.verify(HERE.parent)
        self.assertEqual(checked['passed_cases'], 28)
        self.assertEqual(checked['preserved_failed_cases'], 2)

    def test_independent_timing_arithmetic(self):
        self.assertAlmostEqual(H100.validate_result(self.result), 1018047.5450472439)

    def test_overcounted_tokens_rejected(self):
        self.result['timing']['tokens_counted_per_trial'] *= 2
        with self.assertRaises(ValueError):
            H100.validate_result(self.result)

    def test_wrong_context_or_gpu_rejected(self):
        for category in ('context', 'gpu', 'precision'):
            candidate = copy.deepcopy(self.result)
            if category == 'context':
                candidate['workload']['context_including_current_input'] = 512
            elif category == 'gpu':
                candidate['environment']['gpu']['multiprocessor_count'] = 114
            else:
                candidate['model']['dtype'] = 'bfloat16'
            with self.subTest(category=category), self.assertRaises(ValueError):
                H100.validate_result(candidate)

    def test_numerical_policy_cannot_be_relabelled_strict(self):
        self.result['workload']['allow_greedy_rounding'] = False
        with self.assertRaises(ValueError):
            H100.validate_result(self.result)

    def test_nonfinite_or_incorrect_rate_rejected(self):
        for rate in (float('nan'), 2 * self.result['timing']['aggregate_tokens_per_second']):
            candidate = copy.deepcopy(self.result)
            candidate['timing']['aggregate_tokens_per_second'] = rate
            with self.subTest(rate=rate), self.assertRaises(ValueError):
                H100.validate_result(candidate)


if __name__ == '__main__':
    unittest.main()
