"""Mutation checks of the archived matched campaign; no device/model access."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('matched128_checker', HERE / 'check_seeded_matched128.py')
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class MatchedTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((subject.ROOT / subject.RECORD).read_text())

    def reject(self, change):
        data = copy.deepcopy(self.data)
        change(data)
        with self.assertRaises((ValueError, KeyError, TypeError)):
            subject.validate(data)

    def test_complete_archive_and_bindings(self):
        self.assertEqual(subject.check()['outputs_compared'], 1024)

    def test_output_and_independent_reference_cannot_change_together(self):
        self.reject(lambda d: d['cases'][4]['generated_tokens'].__setitem__(20, 1))
        def both(d):
            d['cases'][4]['generated_tokens'][20] = 1
            d['references']['2']['generated_tokens'][20] = 1
        self.reject(both)

    def test_seed_temperature_replay_and_frame_mutations(self):
        self.reject(lambda d: d['cases'][4].__setitem__('seed', '0x00'))
        self.reject(lambda d: d['cases'][4].__setitem__('temperature', '2'))
        self.reject(lambda d: d['cases'][5].__setitem__('replay_without_settings', False))
        self.reject(lambda d: d['cases'][4]['wire'][1].__setitem__('frame_hex', '5a830000d6'))
        self.reject(lambda d: d['cases'][7]['wire'].pop())

    def test_counts_timing_outlier_and_qualification_claims(self):
        self.reject(lambda d: d['cases'].pop(6))
        self.reject(lambda d: d['cases'][4].__setitem__('cached_command_tokens_per_second', 10.33))
        self.reject(lambda d: d['cases'][6].__setitem__('cached_command_tokens_per_second', 8.7))
        self.reject(lambda d: d['cases'][4]['reply_elapsed_seconds'].__setitem__(50, 30))
        self.reject(lambda d: d.__setitem__('full_context_qualified', True))
        self.reject(lambda d: d.__setitem__('whole_model_reference_replayed_by_public_checker', True))
        self.reject(lambda d: d.__setitem__('source_comparison_sha256', '0' * 64))


if __name__ == '__main__':
    unittest.main(verbosity=2)
