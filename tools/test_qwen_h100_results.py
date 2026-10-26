"""Evidence-boundary checks using the actual retained reference, without a GPU."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import unittest

spec = importlib.util.spec_from_file_location('h100_results', Path(__file__).with_name('qwen_h100_results.py'))
results = importlib.util.module_from_spec(spec)
spec.loader.exec_module(results)
ROOT = Path(os.environ.get('QWEN_CAPACITY_PACKAGE_ROOT', Path(__file__).resolve().parents[1]))
EVIDENCE = Path(os.environ.get('QWEN_H100_EVIDENCE_ROOT', ROOT / results.EVIDENCE))


class CaseSource:
    def __init__(self, raw):
        self.raw = raw

    def extractfile(self, name):
        return io.BytesIO(self.raw)


class EvidenceChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        selection = json.loads((EVIDENCE / 'SELECTED-REFERENCES.json').read_text())
        cls.entry = selection['cases']['qwen_fixed']
        receipt = json.loads((EVIDENCE / 'REMOTE-ARCHIVE.json').read_text())
        with tarfile.open(EVIDENCE / 'raw-evidence.tar.gz') as source:
            cls.raw = source.extractfile(cls.entry['member']).read()
            cls.case = json.loads(cls.raw)
            cls.inventory = json.load(source.extractfile(receipt['inventory']))

    def checked(self, case=None, role='qwen_fixed', entry=None, inventory=None):
        raw = self.raw if case is None else json.dumps(case).encode()
        selected = copy.deepcopy(self.entry if entry is None else entry)
        if case is not None:
            selected['sha256'] = hashlib.sha256(raw).hexdigest()
        return results.checked_case(CaseSource(raw), self.inventory if inventory is None else inventory,
                                    selected, role)

    def test_recorded_rate_reproduces_and_disagreements_remain_visible(self):
        case, rate = self.checked()
        self.assertAlmostEqual(rate, 61655.70936002969)
        self.assertEqual(case['checks']['optimized']['greedy_mismatch_count'], 1)
        self.assertFalse(case['checks']['optimized']['strict_greedy'])

    def test_complete_archive_and_comparison_reproduce(self):
        actual = results.analyze(ROOT, EVIDENCE)
        expected = json.loads((EVIDENCE / 'computed-results.json').read_text())
        self.assertEqual(actual, expected)
        self.assertEqual(actual['verified_payload_files'], 897)
        self.assertEqual(actual['case_counts'], {'total': 37, 'pass': 32, 'failed': 5})

    def test_changed_selected_identity_rejected(self):
        entry = dict(self.entry, sha256='0' * 64)
        with self.assertRaisesRegex(ValueError, 'identity'):
            self.checked(entry=entry)

    def test_wrong_model_and_workload_roles_rejected(self):
        for role in ('small_fixed', 'qwen_primary'):
            with self.subTest(role=role), self.assertRaises(ValueError):
                self.checked(role=role)

    def test_inflated_token_count_and_invalid_time_rejected(self):
        case = copy.deepcopy(self.case)
        case['workload']['batch'] *= 2
        with self.assertRaisesRegex(ValueError, 'accounting'):
            self.checked(case)
        for time in (0, -1, float('nan'), float('inf')):
            case = copy.deepcopy(self.case)
            case['timing']['samples'][0]['wall_seconds'] = time
            with self.subTest(time=time), self.assertRaises(ValueError):
                self.checked(case)

    def test_mismatched_source_snapshot_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        member = str(Path(self.entry['member']).parent / 'sources/benchmark.py')
        inventory['files'][member]['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'source binding'):
            self.checked(inventory=inventory)

    def test_failed_case_and_other_gpu_configuration_rejected(self):
        case = copy.deepcopy(self.case)
        case['status'] = 'failed'
        with self.assertRaisesRegex(ValueError, 'must pass'):
            self.checked(case)
        case = copy.deepcopy(self.case)
        case['environment']['gpu']['cuda_visible_devices'] = '0,1'
        with self.assertRaisesRegex(ValueError, 'single-H100'):
            self.checked(case)


if __name__ == '__main__':
    unittest.main()
