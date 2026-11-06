"""Observable link, archive, redaction and finite-budget controls."""
from pathlib import Path
import gzip
import importlib.util
import tempfile
import unittest
import json
import subprocess
import sys

SPEC = importlib.util.spec_from_file_location('hygiene', Path(__file__).with_name('check_release_hygiene.py'))
M = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M)


class Checks(unittest.TestCase):
    def test_CI_metadata_mode_rejects_home_path_but_not_generic_provider_name(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / 'release'
            root.mkdir()
            f = root / 'data.txt'
            for label, content, expected in [('home', b'/Users/' + b'fixture-person' + b'/project', 1), ('generic', b'Dropbox', 0)]:
                f.write_bytes(content)
                output = base / (label + '.json')
                r = subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(M.__file__)), '--root', str(root), '--fail-on-findings', '--output', str(output)], capture_output=True, text=True)
                self.assertEqual(r.returncode, expected, r.stderr)
                self.assertNotIn('fixture-person', r.stdout)
                self.assertTrue(output.exists())

    def test_CI_mode_rejects_real_missing_link(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / 'release'
            root.mkdir()
            (root / 'README.md').write_text('[missing](not-there.md)\n')
            output = base / 'report.json'
            r = subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(M.__file__)), '--root', str(root), '--links-only', '--fail-on-findings', '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)
            self.assertTrue(output.exists())
            self.assertEqual(json.loads(output.read_bytes())['broken_links_by_reason'], {'missing_path': 1})

    def test_generated_manifest_links_follow_existing_contract_closure(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / 'release'
            (root / 'tools').mkdir(parents=True)
            (root / 'README.md').write_text('[manifest](MANIFEST.json)\n')
            (root / 'MANIFEST.json').write_text('{}')
            (root / 'tools/verify_release.py').write_text('# generated checker\n')
            contract = root / 'tools/release-contract.json'
            contract.write_text(json.dumps({'files': {'README.md': {}}}))
            output = base / 'report.json'
            r = subprocess.run([sys.executable, '-I', '-S', '-B', str(Path(M.__file__)), '--root', str(root), '--contract', str(contract), '--links-only', '--output', str(output)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            report = json.loads(output.read_bytes())
            self.assertEqual(report['members_expected'], 4)
            self.assertEqual(report['broken_links'], [])
            self.assertTrue(report['complete'])

    def test_unpublished_leftover_does_not_validate_release_link(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'README.md').write_text('[leftover](old.md)\n[real](new.md#present)\n')
            (root / 'old.md').write_text('# Old\n')
            (root / 'new.md').write_text('# Present\n')
            r = M.inspect(root, metadata_enabled=False, members={'README.md', 'new.md'})
            self.assertEqual(r['files_enumerated'], 2)
            self.assertEqual(r['broken_links_by_reason'], {'target_not_in_release_contract': 1})

    def test_relative_and_same_page_anchors_and_duplicate_headings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'README.md').write_text('# Hello, world!\n\n[good](#hello-world)\n[bad](#missing)\n[duplicate](child.md#repeat-1)\n[missing file](absent.md)\n\n```md\n[example](not-real.md)\n```\n')
            (root / 'child.md').write_text('# Repeat\n\n# Repeat\n')
            r = M.inspect(root, metadata_enabled=False)
            self.assertEqual(r['relative_links_checked'], 4)
            self.assertEqual(r['broken_links_by_reason'], {'missing_markdown_anchor': 1, 'missing_path': 1})
            self.assertEqual({v['target'] for v in r['broken_links']}, {'#missing', 'absent.md'})

    def test_plain_binary_and_gzip_matches_never_emit_matched_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            literal = b'/Users/' + b'fixture-person' + b'/private-project'
            (root / 'binary.bin').write_bytes(b'\x00' + literal + b'\x00')
            (root / 'object.gz').write_bytes(gzip.compress(b'prefix ' + literal + b' suffix'))
            r = M.inspect(root, links_enabled=False)
            self.assertEqual(r['metadata_files_by_category'], {'user_home_path': 2})
            self.assertTrue(r['complete'])
            self.assertEqual(r['gzip_files_scanned'], 1)
            self.assertNotIn('fixture-person', str(r))
            self.assertNotIn('private-project', str(r))

    def test_gzip_limit_and_corruption_are_not_clean_results(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'limited.gz').write_bytes(gzip.compress(b'x' * 200))
            (root / 'broken.gz').write_bytes(b'not gzip')
            r = M.inspect(root, links_enabled=False, per_file_limit=100)
            self.assertFalse(r['complete'])
            self.assertEqual(len(r['metadata_incomplete']), 2)
            self.assertIn('expanded_byte_limit', {v['incomplete_reason'] for v in r['metadata_incomplete']})

    def test_chunk_boundary_and_total_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = b'x' * ((1 << 20) - 4) + b'/home/' + b'fixture-user' + b'/project'
            (root / 'payload').write_bytes(payload)
            r = M.inspect(root, links_enabled=False)
            self.assertEqual(r['metadata_files_by_category'], {'unix_home_path': 1})
            r = M.inspect(root, links_enabled=False, total_limit=10)
            self.assertFalse(r['complete'])
            self.assertEqual(r['stop_reason'], 'total_expanded_byte_limit')

    def test_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'alias').symlink_to('/etc/hosts')
            r = M.inspect(root)
            self.assertEqual(r['files_enumerated'], 0)
            self.assertEqual(r['symlinks_not_followed'], ['alias'])


if __name__ == '__main__':
    unittest.main()
