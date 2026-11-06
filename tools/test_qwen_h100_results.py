"""Evidence-boundary checks using the actual retained reference, without a GPU."""
import copy
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest import mock

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

    def test_shared_reference_reader_is_independent_of_comparison(self):
        with mock.patch.object(results, 'analyze', side_effect=AssertionError('circular calculator dependency')):
            measured = results.reference_measurements(ROOT, EVIDENCE)
        self.assertAlmostEqual(measured['rates']['small_fixed'], 2951332.874617403)
        self.assertEqual(measured['cases']['small_fixed']['environment']['packages']['transformers'], '5.17.0')
        saved = json.loads((ROOT / 'demos/simplestories-v2-5m/evidence/training-capacity-estimates.json').read_text())
        self.assertEqual(saved['measured_reference']['aggregate_tokens_per_second'], measured['rates']['small_fixed'])
        self.assertEqual(saved['measured_reference']['member_sha256'], measured['selection']['cases']['small_fixed']['sha256'])
        self.assertEqual(saved['measured_reference']['archive_sha256'], measured['receipt']['sha256'])

    def test_comparison_documents_and_negative_prose_drift(self):
        actual = results.analyze(ROOT, EVIDENCE)
        results.check_documents(ROOT, actual)
        names = ('TRAINING-CAPACITY.md', 'docs/benchmarks/H100-BENCHMARK.md')
        originals = {name: (ROOT / name).read_text(encoding='utf-8') for name in names}
        for target in names:
            text = originals[target]
            mutations = (text.replace('19% lower', 'twice as high'),
                         text.replace('0.29 |', '0.10 |'),
                         text.replace(results.SUMMARY_START, ''), text + results.TABLE_END)
            for altered in mutations:
                self.assertNotEqual(altered, text)
                with self.subTest(target=target), tempfile.TemporaryDirectory() as temporary:
                    package = Path(temporary)
                    for name, content in originals.items():
                        path = package / name
                        path.parent.mkdir(parents=True, exist_ok=True)
                        path.write_text(altered if name == target else content, encoding='utf-8')
                    with self.assertRaises(ValueError):
                        results.check_documents(package, actual)

    def test_changed_selected_identity_rejected(self):
        entry = dict(self.entry, sha256='0' * 64)
        with self.assertRaisesRegex(ValueError, 'identity'):
            self.checked(entry=entry)

    def test_shared_selection_roles_and_hashes_are_checked(self):
        path = EVIDENCE / 'SELECTED-REFERENCES.json'
        real_read = Path.read_bytes
        selection = json.loads(real_read(path))
        wrong_role = copy.deepcopy(selection)
        wrong_role['cases']['unexpected'] = wrong_role['cases'].pop('small_fixed')
        wrong_hash = copy.deepcopy(selection)
        wrong_hash['cases']['small_fixed']['sha256'] = '0' * 64
        for altered in (wrong_role, wrong_hash):
            def read(selected):
                return json.dumps(altered).encode() if selected == path else real_read(selected)
            with self.subTest(selection=altered), mock.patch.object(Path, 'read_bytes', read):
                with self.assertRaises(ValueError):
                    results.reference_measurements(ROOT, EVIDENCE)

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
