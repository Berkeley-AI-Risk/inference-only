"""Offline source-map reconstruction and refusal controls; no native tools."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('stage_source_map.py')
spec = importlib.util.spec_from_file_location('source_map_stager', SCRIPT)
subject = importlib.util.module_from_spec(spec)
spec.loader.exec_module(subject)


class SourceMapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.root = self.folder / 'release'
        self.root.mkdir()
        self.output = self.folder / 'reconstructed'
        self.original = {'source/shared.sv': b'module original; endmodule\n',
                         'evidence/result.json': b'{"result":"recorded"}'}
        self.map = {'schema': subject.SCHEMA, 'expected_files': 2, 'files': {}}
        for name, raw in self.original.items():
            source = 'shared/block.sv' if name.endswith('.sv') else 'payload/record.json'
            path = self.root / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            self.map['files'][name] = {'source': source, 'bytes': len(raw),
                'sha256': hashlib.sha256(raw).hexdigest(),
                'kind': 'shared' if name.endswith('.sv') else 'retained'}
        self.save_map()

    def save_map(self):
        (self.root / 'map.json').write_text(json.dumps(self.map))

    def run_stage(self):
        return subject.stage(self.root, 'map.json', self.output)

    def test_reconstructs_exact_bytes_including_missing_final_newline(self):
        result = self.run_stage()
        self.assertEqual(result['files'], 2)
        self.assertEqual(result['shared_sources'], 1)
        self.assertEqual({p.relative_to(self.output).as_posix(): p.read_bytes()
            for p in self.output.rglob('*') if p.is_file()}, self.original)

    def test_changed_shared_source_fails_before_output_creation(self):
        (self.root / 'shared/block.sv').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Changed source input: shared/block.sv'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_missing_shared_source_fails_before_output_creation(self):
        (self.root / 'shared/block.sv').unlink()
        with self.assertRaisesRegex(ValueError, 'Missing source input: shared/block.sv'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_retained_receipt_is_also_digest_checked(self):
        (self.root / 'payload/record.json').write_text('changed receipt')
        with self.assertRaisesRegex(ValueError, 'Changed source input: payload/record.json'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_existing_output_and_its_contents_are_preserved(self):
        self.output.mkdir()
        sentinel = self.output / 'keep'
        sentinel.write_text('previous results')
        with self.assertRaises(FileExistsError):
            self.run_stage()
        self.assertEqual(sentinel.read_text(), 'previous results')

    def test_output_inside_release_is_refused(self):
        self.output = self.root / 'new-output'
        with self.assertRaisesRegex(ValueError, 'outside the source repository'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_symlinked_shared_directory_is_refused(self):
        original = self.root / 'shared'
        saved = self.folder / 'external-shared'
        original.rename(saved)
        original.symlink_to(saved, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Symlink source input'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_escaping_source_or_destination_is_refused(self):
        row = self.map['files']['source/shared.sv']
        row['source'] = '../external.sv'
        self.save_map()
        with self.assertRaisesRegex(ValueError, 'Unsafe relative file name'):
            self.run_stage()
        row['source'] = 'shared/block.sv'
        self.map['files']['../external.sv'] = self.map['files'].pop('source/shared.sv')
        self.save_map()
        with self.assertRaisesRegex(ValueError, 'Unsafe relative file name'):
            self.run_stage()
        self.assertFalse(self.output.exists())

    def test_duplicate_members_and_destination_collisions_are_refused(self):
        (self.root / 'map.json').write_text('{"schema":"one","schema":"two"}')
        with self.assertRaisesRegex(ValueError, 'Duplicate source-map key'):
            self.run_stage()
        self.map['files']['source/shared.sv/nested'] = self.map['files']['evidence/result.json']
        self.map['expected_files'] = 3
        self.save_map()
        with self.assertRaisesRegex(ValueError, 'Colliding destination'):
            self.run_stage()
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
