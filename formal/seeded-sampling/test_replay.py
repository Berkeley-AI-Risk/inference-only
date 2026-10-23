"""Adversarial offline tests for portable source and proof-receipt boundaries."""
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode and not sys.flags.optimize
HERE = Path(__file__).resolve().parent


def module(name):
    spec = importlib.util.spec_from_file_location('test_' + name, HERE / (name + '.py'))
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value); return value


class PublicReplayBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.provider, self.checker, self.auditor = [module(name) for name in ('source_provider', 'check_replay', 'audit_components')]

    def test_only_distributed87_bytes_are_audited(self):
        read_bytes, observed = Path.read_bytes, []
        def observed_read(path):
            self.assertNotIn('/official/', path.as_posix())
            observed.append(path)
            return read_bytes(path)
        with mock.patch.object(Path, 'read_bytes', observed_read): result = self.provider.source_binding()
        self.assertEqual(result['distributed_inputs_verified'], 87)
        self.assertEqual(result['historical_native_inputs'], 91)
        self.assertEqual(len(result['omitted_vendor_inputs']), 4)
        self.assertFalse(result['omitted_vendor_bytes_verified'])
        self.assertFalse(result['whole_native91_byte_audit'])
        self.assertFalse(result['vendor_logic_elaborated'])
        self.assertIn(self.provider.IMAGE_PATH, observed)

    def test_corrupted_production_byte_is_rejected(self):
        read_bytes = Path.read_bytes
        target = self.provider.SOURCE / 'project/board1_seeded_head_selector.sv'
        def damaged(path): return read_bytes(path) + (b'\n// changed\n' if path == target else b'')
        with mock.patch.object(Path, 'read_bytes', damaged):
            with self.assertRaisesRegex(ValueError, 'Distributed source changed'): self.provider.source_inputs()

    def test_changed_monitor_cannot_silently_weaken_proof(self):
        read_bytes = Path.read_bytes
        target = HERE / 'selector-monitor.inc.sv'
        def damaged(path): return b'// no assertions\n' if path == target else read_bytes(path)
        with mock.patch.object(Path, 'read_bytes', damaged):
            with self.assertRaisesRegex(ValueError, 'Proof support changed'): self.provider.source_inputs()

    def test_unknown_cannot_be_relabelled_passed(self):
        with tempfile.TemporaryDirectory() as temporary:
            proof = Path(temporary)
            query, log = b'(check-sat)\n', b'unknown\n'
            (proof / 'z3-induction.smt2').write_bytes(query); (proof / 'z3-induction.log').write_bytes(log)
            row = dict(passed=True, exit=0, timed_out=False, answers=['unknown'],
                query_sha256=hashlib.sha256(query).hexdigest(), log_sha256=hashlib.sha256(log).hexdigest())
            with self.assertRaises(AssertionError):
                self.checker.check_phase(proof, dict(solver_results={'z3-induction': row}), 'z3-induction', ['unsat'])

    def test_unbacked_connected_summary_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            with self.assertRaises(FileNotFoundError):
                self.checker.check_connected(Path(temporary),
                    dict(primary_passed=True, audit_passed=True, primary=dict(assertions=196)), {}, self.auditor)

    def test_rehashed_vacuous_bounded_query_is_rejected(self):
        smt = '; yosys-smt2-assert 0 fixture fixture.sv:1\n'
        valid = self.checker.bounded_query(smt, 'fixture', True)
        malicious = valid.replace('(check-sat)', '(assert false)\n(check-sat)', 1)
        with self.assertRaises(AssertionError): self.checker.check_bounded_query(malicious, smt, 'fixture', True)

    def test_observer_feedback_is_rejected(self):
        value = dict(netnames={'f_slot': dict(bits=[1], hide_name=0)},
            ports={'public_o': dict(bits=[2], direction='output')},
            cells={'feedback': dict(type='$not', connections={'A': [1], 'Y': [2]},
                port_directions={'A': 'input', 'Y': 'output'})})
        with self.assertRaises(AssertionError): self.auditor.observer_cone(value, ['f_slot'], {})

    def inventory_fixture(self, root):
        (root / 'SOURCE.json').write_text('{}')
        raw = b'public proof source\n'; (root / 'proof.py').write_bytes(raw)
        return dict(schema='seeded-public-formal-package-v1', inventory_includes_itself=False,
            vendor_files_included=False, generated_runs_included=False,
            files={'proof.py': dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())})

    def test_generated_runs_are_allowed_but_never_indexed(self):
        checker = module('check_recorded')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); inventory = self.inventory_fixture(root)
            for name in ('runs/query.smt2', 'connected/runs/result.log'):
                path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text('generated')
            self.assertEqual(set(checker.check_files(root, inventory)), {'proof.py'})
            inventory['files']['runs/query.smt2'] = dict(bytes=9, sha256=hashlib.sha256(b'generated').hexdigest())
            with self.assertRaises(AssertionError): checker.check_files(root, inventory)

    def test_unlisted_release_source_is_rejected(self):
        checker = module('check_recorded')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); inventory = self.inventory_fixture(root)
            (root / 'unlisted.py').write_text('unreviewed')
            with self.assertRaises(AssertionError): checker.check_files(root, inventory)

    def test_inventory_path_cannot_escape_package(self):
        checker = module('check_recorded')
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); inventory = self.inventory_fixture(root)
            inventory['files']['../outside'] = dict(bytes=0, sha256=hashlib.sha256(b'').hexdigest())
            with self.assertRaises(AssertionError): checker.check_files(root, inventory)


if __name__ == '__main__': unittest.main()
