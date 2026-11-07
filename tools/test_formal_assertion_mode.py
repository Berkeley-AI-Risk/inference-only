"""Regression checks for proof-runner optimization refusal and engine failures."""
from pathlib import Path
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
FORMAL = 'demos/simplestories-v2-5m/formal/'
ENTRYPOINTS = [FORMAL + 'kv-clear-epoch/' + name for name in
              ['run.py', 'recompute.py', 'install_linux.py', 'self_test.py']]
ENTRYPOINTS += ['tools/model_size_reuse/run.py', 'tools/check_repaired_sawic.py']


class AssertionModeTests(unittest.TestCase):
    def test_optimized_entrypoints_refuse_before_inputs_outputs_or_tools(self):
        with tempfile.TemporaryDirectory(prefix='formal-mode-') as directory:
            scratch = Path(directory)
            empty_path = scratch / 'no-tools'
            empty_path.mkdir()
            env = dict(os.environ, PATH=str(empty_path))
            for relative in ENTRYPOINTS:
                for optimization in ['-O', '-OO']:
                    with self.subTest(entrypoint=relative, optimization=optimization):
                        out = scratch / (str(ENTRYPOINTS.index(relative)) + optimization)
                        command = [sys.executable, '-I', '-S', '-B', optimization,
                                   str(ROOT / relative), '--out', str(out),
                                   '--model', str(scratch / 'absent-model'),
                                   '--tool-receipt', str(scratch / 'absent-tools.json')]
                        result = subprocess.run(command, env=env, capture_output=True,
                                                text=True, timeout=10)
                        self.assertNotEqual(result.returncode, 0)
                        self.assertIn('do not use -O or -OO', result.stderr)
                        self.assertEqual(result.stdout, '')
                        self.assertFalse(out.exists())

    def test_optimized_refusal_preserves_existing_output(self):
        with tempfile.TemporaryDirectory(prefix='formal-existing-') as directory:
            out = Path(directory)
            saved = out / 'retained.txt'
            saved.write_text('Retained evidence\n')
            result = subprocess.run(
                [sys.executable, '-I', '-S', '-B', '-O',
                 str(ROOT / (FORMAL + 'kv-clear-epoch/run.py')),
                 '--recorded-only', '--out', str(out), '--model', str(out / 'absent')],
                capture_output=True, text=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('do not use -O or -OO', result.stderr)
            self.assertEqual(list(out.iterdir()), [saved])
            self.assertEqual(saved.read_text(), 'Retained evidence\n')

    def test_failed_or_unresolved_engine_never_matches(self):
        spec = importlib.util.spec_from_file_location(
            'clear_epoch_failure_test', ROOT / (FORMAL + 'kv-clear-epoch/run.py'))
        runner = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(runner)
        with tempfile.TemporaryDirectory(prefix='formal-engine-') as directory:
            scratch = Path(directory)
            tools = scratch / 'bin'
            tools.mkdir()
            monitor = shutil.which('ps')
            self.assertIsNotNone(monitor)
            (tools / 'ps').symlink_to(monitor)
            cases = [('failed-with-expected-text', 'unsat', 19),
                     ('unknown', 'unknown', 0), ('wrong-answer', 'sat', 0),
                     ('missing', None, None)]
            for engine in ['z3', 'cvc5']:
                for case, answer, exit_code in cases:
                    with self.subTest(engine=engine, case=case):
                        binary = tools / engine
                        if binary.exists():
                            binary.unlink()
                        if answer is not None:
                            binary.write_text('#!/bin/sh\nprintf "%s\\n" "' + answer +
                                              '"\nexit ' + str(exit_code) + '\n')
                            binary.chmod(0o755)
                        output = scratch / (engine + '-' + case)
                        output.mkdir()
                        node = {'solver': engine, 'query': 'unused.smt2',
                                'query_sha256': 'failure-fixture', 'expected': 'unsat'}
                        args = SimpleNamespace(memory_mb=256, timeout=10)
                        with patch.dict(os.environ, PATH=str(tools)):
                            result = runner.solve(scratch, output, 'control', node,
                                                  args, time.monotonic() + 30, None)
                        self.assertFalse(result['expected_result_matched'])
                        receipt = json.loads((output / 'fresh-solvers/control/RESULT.json').read_text())
                        self.assertFalse(receipt['expected_result_matched'])
                        if answer is not None:
                            self.assertEqual(result['exit_code'], exit_code, result)
                        else:
                            self.assertIn('launch-or-watchdog-error', result['stop_reason'])


if __name__ == '__main__':
    unittest.main()
