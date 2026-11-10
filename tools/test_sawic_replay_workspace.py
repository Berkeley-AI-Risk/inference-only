"""Filesystem controls for the fresh Tang replay staging command."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'demos/simplestories-v2-5m/variants/signed-update/tang/tests/prepare_replay.py'
spec = importlib.util.spec_from_file_location('sawic_replay_workspace', SCRIPT)
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class WorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.release = self.root / 'release'
        self.source = self.release / 'demos/model/variants/signed-update/tang'
        names = ['reference/signed_update.py', 'reference/tang_image.py',
                 *('tests/' + n for n in subject.TEST_INPUTS),
                 *('tools/' + n for n in subject.TOOL_INPUTS),
                 'hardware/project/nested/source.sv', 'evidence/fixtures/recorded.json',
                 'evidence/tang-fast-simulation/BUILD.json']
        for name in names:
            p = self.source / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(name)
        (self.release / 'tools').mkdir()
        (self.release / 'tools/verify_release.py').write_text('fixture')
        (self.release / 'MANIFEST.json').write_text('{}')

    def test_stages_inputs_and_empty_evidence_without_source_changes(self):
        before = {p.relative_to(self.source): p.read_bytes()
                  for p in self.source.rglob('*') if p.is_file()}
        result = subject.stage(self.source, self.root / 'run')
        replay = Path(result['replay'])
        self.assertEqual(list((replay / 'evidence').iterdir()), [])
        self.assertFalse(result['archived_evidence_copied'])
        self.assertEqual(result['input_vectors'], ['tests/rfc8554-case1.json', 'tests/lms-vectors.json'])
        for name in result['files']:
            self.assertEqual((replay / name).read_bytes(), before[Path(name)])
        self.assertEqual(before, {p.relative_to(self.source): p.read_bytes()
                                 for p in self.source.rglob('*') if p.is_file()})

    def test_refuses_existing_output(self):
        out = self.root / 'run'
        out.mkdir()
        (out / 'keep').write_text('evidence')
        with self.assertRaises(FileExistsError): subject.stage(self.source, out)
        self.assertEqual((out / 'keep').read_text(), 'evidence')

    def test_refuses_output_elsewhere_inside_checkout(self):
        with self.assertRaises(ValueError): subject.stage(self.source, self.release / 'new-output')
        self.assertFalse((self.release / 'new-output').exists())

    def test_refuses_source_file_symlink_without_copying_target(self):
        target = self.root / 'outside.txt'
        target.write_text('outside')
        (self.source / 'hardware/project/link.sv').symlink_to(target)
        with self.assertRaises(ValueError): subject.stage(self.source, self.root / 'run')
        self.assertFalse((self.root / 'run').exists())

    def test_refuses_source_directory_symlink_without_walking_target(self):
        target = self.root / 'outside'
        target.mkdir()
        (target / 'do-not-copy').write_text('outside')
        (self.source / 'hardware/project/link').symlink_to(target, target_is_directory=True)
        with self.assertRaises(ValueError): subject.stage(self.source, self.root / 'run')
        self.assertFalse((self.root / 'run').exists())


if __name__ == '__main__':
    unittest.main()
