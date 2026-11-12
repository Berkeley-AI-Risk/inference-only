"""Portable dispatch staging controls; never invokes Verilator or a simulator."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
DEMO = REPO / 'demos/tlm26-moe'


def load_subject():
    spec = importlib.util.spec_from_file_location('tlm26_dispatch_prepare', DEMO / 'scripts/reproduce.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name).resolve()
        self.root = self.base / 'copied-demo'
        self.root.mkdir()
        self.subject = load_subject()
        self.subject.ROOT = self.root
        bindings = json.loads((DEMO / 'evidence/expert-dispatch/source-bindings.json').read_text())
        # Copy only bounded replay inputs. Tiny stand-in runtime bytes test file
        # admission, not numerical behavior or the measured model.
        for name in [*bindings['sources'], bindings['stimulus']['path'], bindings['expected']['path']]:
            if not name.startswith('demos/tlm26-moe/'):
                continue
            relative = name.removeprefix('demos/tlm26-moe/')
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / name, target)
        (self.root / 'build').mkdir()
        for name in bindings['runtime_files']:
            raw = ('staging fixture ' + name).encode()
            (self.root / 'build' / name).write_bytes(raw)
            bindings['runtime_files'][name] = {'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}
        self.bindings = bindings
        self.binding_path = self.root / 'evidence/expert-dispatch/source-bindings.json'
        self.binding_path.write_text(json.dumps(bindings))
        self.output = self.base / 'fresh-output'

    def prepare(self):
        with mock.patch.object(self.subject.shutil, 'which', return_value='/portable/bin/verilator'), \
             mock.patch.object(self.subject.subprocess, 'run', side_effect=AssertionError('native execution forbidden')), \
             mock.patch.object(self.subject.urllib.request, 'urlopen', side_effect=AssertionError('network forbidden')):
            self.subject.dispatch(self.output, prepare_only=True, source_root=REPO)

    def test_copy_with_explicit_shared_source_root_stages_only(self):
        self.prepare()
        plan = json.loads((self.output / 'PLAN.json').read_text())
        self.assertTrue(plan['prepare_only'])
        self.assertEqual(len(plan['source_sha256']), 12)
        self.assertEqual((self.output / 'commands.txt').read_bytes(), (DEMO / 'tests/dispatch_commands.txt').read_bytes())
        self.assertEqual(plan['environment_remove'], ['BAD_BOOT_PAGE'])
        self.assertFalse((self.output / 'RESULT.json').exists())

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        marker = self.output / 'partial.txt'
        marker.write_text('preserve partial evidence')
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(marker.read_text(), 'preserve partial evidence')

    def test_changed_source_reference_stimulus_or_runtime_refused(self):
        for relative in ('rtl/tlm_decoder.sv', 'tests/dispatch_commands.txt',
                         'evidence/expert-dispatch/expected.json', 'build/model.bin'):
            with self.subTest(relative=relative):
                target = self.root / relative
                before = target.read_bytes()
                target.write_bytes(before + b'changed')
                try:
                    with self.assertRaises(ValueError):
                        self.prepare()
                    self.assertFalse(self.output.exists())
                finally:
                    target.write_bytes(before)

    def test_output_inside_demo_refused(self):
        self.output = self.root / 'unsafe-output'
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse(self.output.exists())

    def test_checker_load_failure_precedes_any_native_work(self):
        with mock.patch.object(self.subject.subprocess, 'run', side_effect=AssertionError('native execution forbidden')):
            with self.assertRaises(FileNotFoundError):
                self.subject.dispatch(self.output, source_root=REPO)
        self.assertFalse(self.output.exists())

    def test_isolated_source_frontdoor(self):
        completed = subprocess.run([sys.executable, '-I', '-S', '-B', str(DEMO / 'scripts/reproduce.py'),
                                    'dispatch-sources', '--source-root', str(REPO)],
                                   capture_output=True, text=True, cwd=self.base)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(completed.stdout)['sources_checked'], 12)


if __name__ == '__main__':
    unittest.main()
