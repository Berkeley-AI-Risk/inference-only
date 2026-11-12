"""Offline source/preparation/auditor controls; never invoke native tools."""
if not __debug__:
    raise RuntimeError('Run prefetch controls with Python assertions enabled')
import sys
if sys.version_info < (3, 9):
    raise RuntimeError('The prefetch controls require Python 3.9 or newer')
import copy
import importlib.util
from pathlib import Path
import tempfile
import subprocess
import types
import unittest
from unittest import mock

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prefetch_runner_controls', HERE / 'run.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)


class Controls(unittest.TestCase):
    def test_prepare_refuses_output_under_repository(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            with mock.patch.object(r, 'REPOSITORY', root):
                with self.assertRaisesRegex(ValueError, 'outside the repository'):
                    r.prepare(root/'new-output')
            self.assertFalse((root/'new-output').exists())

    def test_fixed_suite_and_exact_readers(self):
        self.assertEqual(len(r.JOBS), 23)
        self.assertEqual(len(set(j[0] for j in r.JOBS)), 23)
        self.assertEqual(sum(j[1] == 'fault' for j in r.JOBS), 2)
        self.assertEqual(sum(j[3] in (3, 4, 5) for j in r.JOBS), 3)
        pins = r.check_sources()['reader_sha256']
        for c in r.CONFIGURATIONS:
            data = r.source_map(c)['qwen_kvp_reader.sv']
            self.assertEqual(r.hashlib.sha256(data).hexdigest(), pins['candidate' if c == 'fault' else c])

    def test_prepare_is_nonexecuting_and_refuses_reuse_and_changed_stage(self):
        with tempfile.TemporaryDirectory() as temp, mock.patch.object(r.subprocess, 'Popen', side_effect=AssertionError('native process forbidden')):
            out = Path(temp) / 'spaced output'
            r.prepare(out)
            r.prepared(out)
            with self.assertRaisesRegex(ValueError, 'already exists'):
                r.prepare(out)
            source = out / 'candidate/source/qwen_kvp_reader.sv'
            source.write_bytes(source.read_bytes() + b'\n// changed\n')
            with self.assertRaisesRegex(ValueError, 'Staged source changed'):
                r.prepared(out)

    def test_unlisted_compiler_file_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            model = root / 'demos/qwen3-1.7b'
            variant = model / 'variants/protected-kv-simulation'
            package = variant / 'prefetch'
            for p in (model/'hardware/design', variant/'rtl', package/'numeric', package/'fault'):
                p.mkdir(parents=True)
            (variant/'rtl/unlisted.sv').write_text('module unlisted; endmodule\n')
            with mock.patch.multiple(r, HERE=package, MODEL=model, VARIANT=variant, REPOSITORY=root), mock.patch.object(r, 'read', return_value={'package_files':{}, 'public_files':{}}):
                with self.assertRaisesRegex(ValueError, 'Unlisted compiler source'):
                    r.check_sources()

    def test_changed_pin_refused(self):
        manifest = copy.deepcopy(r.read(HERE/'INPUTS.json'))
        manifest['package_files']['numeric/top.sv']['sha256'] = '0'*64
        with mock.patch.object(r, 'read', return_value=manifest):
            with self.assertRaisesRegex(ValueError, 'Changed source input'):
                r.check_sources()

    def test_optimized_frontdoor_refused(self):
        with mock.patch.object(r.sys, 'flags', types.SimpleNamespace(optimize=1)):
            with self.assertRaisesRegex(ValueError, 'assertions enabled'):
                r.main()

    def test_all_frontdoors_refuse_O_and_OO_before_imports(self):
        for name in ('run.py', 'test_controls.py', 'audit_numeric.py', 'audit_fault.py', 'audit_security.py'):
            for level in (1, 2):
                with self.subTest(name=name, optimize=level):
                    code = compile((HERE/name).read_text(), str(HERE/name), 'exec', optimize=level)
                    with self.assertRaisesRegex(RuntimeError, 'assertions enabled'):
                        exec(code, {'__file__': str(HERE/name), '__name__': 'optimized_refusal_control'})

    def test_actual_optimized_subprocesses_refuse_without_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            cwd = Path(temp)
            for name in ('run.py', 'test_controls.py', 'audit_numeric.py', 'audit_fault.py', 'audit_security.py'):
                for option in ('-O', '-OO'):
                    with self.subTest(name=name, option=option):
                        argv = [sys.executable, '-I', '-S', '-B', option, str(HERE/name)]
                        if name == 'run.py':
                            argv += ['prepare', '--output', str(cwd/'must-not-exist')]
                        result = subprocess.run(argv, cwd=cwd, capture_output=True, text=True, timeout=10)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn('assertions enabled', result.stderr)
                        self.assertNotIn('source_checks_passed', result.stdout)
                        self.assertNotIn('"passed"', result.stdout)
                        self.assertEqual(list(cwd.iterdir()), [])

    def test_nonzero_native_exit_never_reaches_auditor(self):
        receipt = dict(actual_child_exit=1, error=None, stop_reason=None)
        with mock.patch.object(r, 'read', return_value=receipt), mock.patch.object(r, 'auditors', side_effect=AssertionError('must not audit')):
            with self.assertRaisesRegex(ValueError, 'Actual native case failed'):
                r.audit_case(Path('/unused'), r.JOBS[0])

    def test_auditors_reject_incomplete_and_bad_evidence(self):
        numeric, fault, security = r.auditors()
        with self.assertRaisesRegex(AssertionError, 'Missing numerical heads'):
            numeric.audit([], 0, 0)
        with self.assertRaisesRegex(AssertionError, 'Failed verification'):
            numeric.audit([dict(profile=0, workload=0, cycle=1, phase=0, event='verification', ok=False)], 0, 0)
        with self.assertRaisesRegex(ValueError, 'Missing result'):
            fault.check_case([], 0, 0)
        with self.assertRaisesRegex(AssertionError, 'Missing real context17'):
            security.audit([], 4)

    def test_log_grammar_rejects_false_PASS_and_diagnostics(self):
        numeric, fault, _ = r.auditors()
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)/'stdout.log'
            for parser, event, terminal in (
                    (numeric.read_rows, '{"profile":0,"workload":2}', 'PASS paired_multi_position profile=0 workload=2'),
                    (fault.read_rows, '{"event":"result"}', 'PASS operand_integrity_observation protected=1')):
                path.write_text(event+'\n'+terminal+'\n')
                self.assertEqual(len(parser(path)), 1)
                for diagnostic in ('FAIL changed operand', 'unexpected diagnostic', terminal):
                    path.write_text(event+'\n'+diagnostic+'\n'+terminal+'\n')
                    with self.assertRaises((AssertionError, ValueError)):
                        parser(path)
                path.write_text(event+'\n'+terminal+' extra\n')
                with self.assertRaises((AssertionError, ValueError)):
                    parser(path)

    def test_queue_binds_admitted_K_then_matching_V(self):
        rows = []; cycle = 1
        for phase, groups in ((1, (1,)), (2, (1, 2))):
            for hi, head in enumerate((0, 1, 0)):
                for group in groups:
                    rows.extend([dict(event='allocation', cycle=cycle, new_tag=head*2048+group),
                                 dict(event='follow_pending', cycle=cycle, phase=phase, head_index=hi,
                                      layer=0, head=head, group=group),
                                 dict(event='allocation', cycle=cycle+1, new_tag=(head+8)*2048+group)])
                    cycle += 3
        self.assertEqual(len(r.queue_lifecycle(rows, 2)), 9)
        changed = copy.deepcopy(rows); changed[2]['new_tag'] ^= 2048
        with self.assertRaisesRegex(ValueError, 'matching V'):
            r.queue_lifecycle(changed, 2)
        changed = copy.deepcopy(rows); changed[1]['group'] = 3
        with self.assertRaisesRegex(ValueError, 'committed prefix'):
            r.queue_lifecycle(changed, 2)


if __name__ == '__main__':
    unittest.main()
