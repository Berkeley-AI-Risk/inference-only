import copy
import hashlib
import json
from pathlib import Path
import unittest

import check_qwen_measurements as checker


class QwenMeasurementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package = Path(__file__).resolve().parents[1]
        cls.evidence = json.loads((cls.package / 'demos/qwen3-1.7b/measurements.json').read_text())

    def test_current_records_and_documentation(self):
        result = checker.check(self.package)
        self.assertEqual(result['compared_tokens'], 852)
        self.assertEqual(result['cases'], 21)
        self.assertTrue(5.50 < result['sustained_cached_tokens_per_second'][0] < 5.53)

    def changed(self):
        return copy.deepcopy(self.evidence)

    def replace_rows(self, case, rows):
        case['stdout'] = ''.join(json.dumps(row) + '\n' for row in rows)
        case['stdout_sha256'] = hashlib.sha256(case['stdout'].encode()).hexdigest()

    def test_first_step_is_excluded_from_cached_rate(self):
        case = self.changed()['campaigns'][0]['cases'][0]
        before = checker.measure(case)
        rows = [json.loads(line) for line in case['stdout'].splitlines()]
        for row in rows:
            row['generation_elapsed_ns'] += 1_000_000_000
            row['prompt_elapsed_ns'] += 1_000_000_000
        rows[0]['step_ns'] += 1_000_000_000
        self.replace_rows(case, rows)
        after = checker.measure(case)
        self.assertEqual(before['cached_tokens_per_second'], after['cached_tokens_per_second'])
        self.assertAlmostEqual(after['prompt_to_first_token_seconds'] - before['prompt_to_first_token_seconds'], 1)

    def test_reject_changed_token(self):
        data = self.changed()
        case = data['campaigns'][0]['cases'][0]
        rows = [json.loads(line) for line in case['stdout'].splitlines()]
        rows[0]['token'] += 1
        self.replace_rows(case, rows)
        with self.assertRaises(ValueError):
            checker.validate(data)

    def test_reject_missing_campaign(self):
        data = self.changed()
        data['campaigns'].pop()
        with self.assertRaises(ValueError):
            checker.validate(data)

    def test_reject_nonmonotonic_time(self):
        data = self.changed()
        case = data['campaigns'][0]['cases'][0]
        rows = [json.loads(line) for line in case['stdout'].splitlines()]
        rows[1]['generation_elapsed_ns'] = rows[0]['generation_elapsed_ns']
        self.replace_rows(case, rows)
        with self.assertRaises(ValueError):
            checker.validate(data)

    def test_reject_changed_transcript_hash(self):
        data = self.changed()
        data['campaigns'][0]['cases'][0]['stdout'] += ' '
        with self.assertRaises(ValueError):
            checker.validate(data)

    def test_reject_model_or_security_overclaim(self):
        for key, value in [('model_image_sha256', '0' * 64), ('weight_authentication', False),
                           ('full_context_qualified', True), ('production_security_certified', True),
                           ('kv_integrity', True), ('weight_encryption', True)]:
            data = self.changed()
            data['implementation'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                checker.validate(data)

    def test_reject_unexpected_private_metadata(self):
        data = self.changed()
        data['campaigns'][0]['instance'] = 'not part of the public schema'
        with self.assertRaises(ValueError):
            checker.validate(data)

    def test_reject_changed_replay(self):
        data = self.changed()
        data['campaigns'][2]['cases'][-1]['prompt_tokens'][0] += 1
        with self.assertRaises(ValueError):
            checker.validate(data)


if __name__ == '__main__':
    unittest.main()
