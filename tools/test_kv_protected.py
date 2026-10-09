"""Offline evidence guards; no device access or attack experiment."""
import copy
import json
from pathlib import Path
import unittest

import check_kv_protected as subject


class ProtectedEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.package = Path(__file__).resolve().parents[1]
        self.data = json.loads((self.package / 'evidence/kv-protected/physical-summary.json').read_text())

    def test_real_source_bindings_and_measurement_arithmetic(self):
        self.assertTrue(subject.check(self.package)['passed'])

    def test_changed_throughput_rejected(self):
        self.data['cases'][0]['protected_cached_tokens_per_second'] *= 2
        with self.assertRaises(ValueError): subject.check_physical(self.data)

    def test_false_physical_security_claim_rejected(self):
        for name in ('physical_corruption_injection_tested', 'timing_qualified', 'configuration_independently_attested'):
            with self.subTest(name=name):
                changed = copy.deepcopy(self.data)
                changed[name] = True
                with self.assertRaises(ValueError): subject.check_physical(changed)

    def test_missing_full_window_case_rejected(self):
        self.data['cases'] = self.data['cases'][:-1]
        with self.assertRaises(ValueError): subject.check_physical(self.data)

    def test_changed_cached_step_rejected(self):
        self.data['cases'][-1]['cached_decode_seconds'] = [1.0]
        with self.assertRaises(ValueError): subject.check_physical(self.data)

    def test_rehearsal_cannot_claim_a_physical_corruption_test(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        data['physical_corruption_injection_tested'] = True
        with self.assertRaises(ValueError): subject.check_rehearsal(self.package, data)

    def test_rehearsal_wrong_token_rejected(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        data['trials']['kv-protected']['ui_generated_tokens'][0] += 1
        with self.assertRaises(ValueError): subject.check_rehearsal(self.package, data)

    def test_rehearsal_missing_host_binding_rejected(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        data['unchanged_host_executable_sources'].pop('host-app/streamlit_app.py')
        with self.assertRaises(ValueError): subject.check_rehearsal(self.package, data)

    def test_exact_label_only_changes_match_board_tested_sources(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        connection = subject.read(self.package / 'evidence/host-connection-reuse.json')
        for name in subject.LABEL_REVISIONS:
            with self.subTest(name=name):
                old_leaf = subject.historical_source_bytes(self.package, name, (self.package / name).read_bytes())
                previous = subject.undo_connection_revision(name, old_leaf, connection)
                subject.check_host_source_bytes(name, previous,
                    data['unchanged_host_executable_sources'][name])

    def test_connection_reuse_measurements_and_sources(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        self.assertEqual(subject.check_connection_reuse(self.package, data), 64)

    def test_connection_reuse_wrong_mean_rejected(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        data['warm_mean_seconds'] += .1
        with self.assertRaises(ValueError): subject.check_connection_reuse(self.package, data)

    def test_connection_reuse_wrong_token_rejected(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        data['cases'][1]['generated_tokens'][0] += 1
        with self.assertRaises(ValueError): subject.check_connection_reuse(self.package, data)

    def test_connection_reuse_wrong_lifecycle_rejected(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        data['cases'][3]['reused'] = True
        with self.assertRaises(ValueError): subject.check_connection_reuse(self.package, data)

    def test_connection_reuse_missing_source_rejected(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        data['current_host_sources'].pop('host-app/test_persistent_uart.py')
        with self.assertRaises(ValueError): subject.check_connection_reuse(self.package, data)

    def test_connection_reuse_changed_patch_rejected(self):
        data = subject.read(self.package / 'evidence/host-connection-reuse.json')
        name = 'host-app/fpga_backend.py'
        data['changes'][name]['reverse_edits'][0]['before'] = ['unexpected old code\n']
        with self.assertRaises(ValueError): subject.undo_connection_revision(name, (self.package/name).read_bytes(), data)

    def test_behavior_change_cannot_be_reported_as_label_only(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        for name in subject.LABEL_REVISIONS:
            raw = (self.package / name).read_bytes() + b'\nraise RuntimeError("unexpected code change")\n'
            with self.subTest(name=name), self.assertRaises(ValueError):
                subject.check_host_source_bytes(name, raw, data['unchanged_host_executable_sources'][name])

    def test_unrecorded_label_edit_rejected(self):
        data = json.loads((self.package / 'evidence/kv-protected/release-rehearsal.json').read_text())
        name = 'host-app/runtime_profile.py'
        raw = (self.package / name).read_bytes().replace(b'K/V integrity protection', b'Different label')
        with self.assertRaises(ValueError):
            subject.check_host_source_bytes(name, raw, data['unchanged_host_executable_sources'][name])


if __name__ == '__main__': unittest.main()
