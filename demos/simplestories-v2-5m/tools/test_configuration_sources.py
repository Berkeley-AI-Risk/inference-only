"""Refusal controls for build-list scope; no compiler, network or FPGA."""
from pathlib import Path
import hashlib
import tempfile
import unittest
import xml.etree.ElementTree as ET

import check_configuration_sources as check


class SourceListControls(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def fixture(self, verilog, members=None, vhdl=()):
        root = ET.Element('Project')
        files = ET.SubElement(root, 'FileList')
        for name in verilog:
            ET.SubElement(files, 'File', path=name, type='file.verilog', enable='1')
        for name in vhdl:
            ET.SubElement(files, 'File', path=name, type='file.vhdl', enable='1')
        ET.ElementTree(root).write(self.root / 'product.gprj')
        (self.root / 'production_sources.f').write_text('\n'.join(verilog if members is None else members) + '\n')

    def home(self, extra=(), omit_home=(), omit_vhdl=()):
        home = sorted(check.HOME_ADDITIONS - set(omit_home))
        vhdl = sorted(check.HOME_VHDL - set(omit_vhdl))
        self.fixture(['defines.v', 'base.sv'] + home + list(extra), ['defines.v', 'base.sv'], vhdl)

    def test_complete_members_and_order(self):
        self.fixture(['defines.v', 'top.sv'])
        row = check.source_lists(self.root, 'baseline')
        self.assertEqual(row['source_list_scope'], 'complete-verilog-members')
        self.assertTrue(row['common_members_same_order'])

    def test_complete_members_are_not_an_ordered_build(self):
        self.fixture(['defines.v', 'one.sv', 'two.sv'], ['defines.v', 'two.sv', 'one.sv'])
        row = check.source_lists(self.root, 'signed-update')
        self.assertFalse(row['common_members_same_order'])
        self.assertEqual(row['project_only_verilog'], [])

    def test_blank_lines_do_not_count_as_source_order_changes(self):
        self.fixture(['defines.v', 'top.sv'])
        (self.root / 'production_sources.f').write_text('defines.v\n\n  top.sv  \n\n')
        row = check.source_lists(self.root, 'signed-update')
        self.assertTrue(row['common_members_same_order'])

    def test_home_base_list_has_exact_explicit_supplements(self):
        self.home()
        row = check.source_lists(self.root, 'home-authorization')
        self.assertEqual(set(row['project_only_verilog']), check.HOME_ADDITIONS)
        self.assertEqual(set(row['vhdl']), check.HOME_VHDL)
        self.assertIn('incomplete', row['source_list_scope'])

    def test_missing_home_module_is_not_accepted_as_base_scope(self):
        self.home(omit_home={'home/nonce_frontend.sv'})
        with self.assertRaisesRegex(ValueError, 'home base-list'):
            check.source_lists(self.root, 'home-authorization')

    def test_missing_physical_entropy_source_is_rejected(self):
        self.home(omit_vhdl={'home/entropy_source.vhd'})
        with self.assertRaisesRegex(ValueError, 'VHDL selection'):
            check.source_lists(self.root, 'home-authorization')

    def test_unreviewed_project_addition_is_rejected(self):
        self.home(extra={'new_controller.sv'})
        with self.assertRaisesRegex(ValueError, 'home base-list'):
            check.source_lists(self.root, 'home-authorization')

    def test_inherited_list_cannot_silently_become_complete(self):
        self.home()
        with (self.root / 'production_sources.f').open('a') as stream:
            stream.write('\n'.join(sorted(check.HOME_ADDITIONS)) + '\n')
        with self.assertRaisesRegex(ValueError, 'home base-list'):
            check.source_lists(self.root, 'home-authorization')

    def test_list_cannot_enable_an_absent_project_member(self):
        self.fixture(['defines.v', 'top.sv'], ['defines.v', 'top.sv', 'alternate.sv'])
        with self.assertRaisesRegex(ValueError, 'disabled or absent'):
            check.source_lists(self.root, 'baseline')

    def test_duplicate_project_and_list_members_are_rejected(self):
        self.fixture(['top.sv', 'top.sv'])
        with self.assertRaisesRegex(ValueError, 'Duplicate enabled'):
            check.source_lists(self.root, 'baseline')
        self.fixture(['top.sv'], ['top.sv', 'top.sv'])
        with self.assertRaisesRegex(ValueError, 'Duplicate source-list'):
            check.source_lists(self.root, 'baseline')

    def test_input_cannot_escape_project(self):
        self.fixture(['../outside.sv'])
        with self.assertRaisesRegex(ValueError, 'Unsafe relative'):
            check.source_lists(self.root, 'baseline')

    def test_linked_project_is_not_followed(self):
        self.fixture(['top.sv'])
        original = self.root / 'original.gprj'
        (self.root / 'product.gprj').rename(original)
        (self.root / 'product.gprj').symlink_to(original)
        with self.assertRaisesRegex(ValueError, 'Linked input'):
            check.source_lists(self.root, 'baseline')

    def test_supplied_vendor_bytes_are_checked_without_changes(self):
        deps = {}
        for name in ['ddr.v', 'pll.v', 'pll_mod.v', 'init.v']:
            raw = ('fixture ' + name).encode()
            (self.root / name).write_bytes(raw)
            deps[name] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        self.assertIn('match', check.check_vendor(self.root, deps))
        self.assertEqual(before, {p.name: p.read_bytes() for p in self.root.iterdir()})
        (self.root / 'pll.v').write_bytes(b'different')
        with self.assertRaisesRegex(ValueError, 'Different external'):
            check.check_vendor(self.root, deps)

    def test_missing_supplied_vendor_input_is_not_treated_as_optional(self):
        deps = {'missing.v': dict(bytes=0, sha256=hashlib.sha256(b'').hexdigest())}
        with self.assertRaisesRegex(ValueError, 'Missing local'):
            check.check_vendor(self.root, deps)
        self.assertIn('prerequisites', check.check_vendor(None, deps))


if __name__ == '__main__':
    unittest.main()
