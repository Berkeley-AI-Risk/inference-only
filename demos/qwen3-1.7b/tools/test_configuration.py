"""Finite source-selection helper tests; no simulator, solver or vendor tools."""
import argparse
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load(path):
    spec = importlib.util.spec_from_file_location('tested_qwen_configuration', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CHECK = load(HERE / 'check_configuration.py')
SELECTED_ROOT = ROOT
SELECTED_MODEL = 'qwen3-1.7b'
LITERAL = 'set qwen_sv_sources {cl_qwen.sv}\nset qwen_v_sources {HardFloat_rawFN.v}\n'


class ConfigurationTests(unittest.TestCase):
    def test_shipped_configuration(self):
        result = CHECK.verify(SELECTED_ROOT, SELECTED_MODEL)
        self.assertTrue(result['passed'])
        self.assertFalse(result['HDL_or_Tcl_elaboration'])
        self.assertFalse(result['cloud_actions'])

    def test_literal_and_compile_order(self):
        text = LITERAL.replace('cl_qwen.sv', 'first.sv cl_qwen.sv')
        self.assertEqual(CHECK.static_sources(text)[0], ['first.sv', 'cl_qwen.sv'])

    def test_duplicate(self):
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            CHECK.static_sources(LITERAL.replace('cl_qwen.sv', 'cl_qwen.sv cl_qwen.sv'))

    def test_dynamic_tcl_refused(self):
        with self.assertRaises(ValueError):
            CHECK.static_sources(LITERAL + 'lappend qwen_sv_sources extra.sv\n')

    def test_unsafe_members(self):
        for name in ('../cl_qwen.sv', '/cl_qwen.sv', '$chosen.sv', '[exec].sv', 'wrong.v'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                CHECK.static_sources(LITERAL.replace('cl_qwen.sv', name))

    def test_empty_or_extra_list_refused(self):
        for text in (LITERAL.replace('cl_qwen.sv', ''), LITERAL + 'set third {}'):
            with self.assertRaises(ValueError):
                CHECK.static_sources(text)

    def test_inventory_membership(self):
        groups = CHECK.static_sources(LITERAL)
        names = {'hardware/design/cl_qwen.sv': {}, 'hardware/design/HardFloat_rawFN.v': {}}
        self.assertEqual(CHECK.selection(names, groups), set(names))
        for changed in ({'hardware/design/cl_qwen.sv': {}}, dict(names, **{'hardware/design/extra.sv': {}})):
            with self.assertRaisesRegex(ValueError, 'inventory'):
                CHECK.selection(changed, groups)

    def test_missing_top(self):
        groups = [['other.sv'], ['HardFloat_rawFN.v']]
        with self.assertRaisesRegex(ValueError, 'top'):
            CHECK.selection({'hardware/design/' + n: {} for g in groups for n in g}, groups)

    def test_actual_consumers_and_mutations(self):
        scripts = SELECTED_ROOT / 'hardware/build/scripts'
        synth = (scripts / 'synth_cl_qwen.tcl').read_text()
        staging = (scripts / 'encrypt.tcl').read_text()
        build = (scripts / 'build_all.tcl').read_text()
        CHECK.consumers(synth, staging, build)
        for changed in (
            synth.replace('read_verilog -sv', 'read_verilog'),
            synth.replace('-top ${CL}', '-top other'),
            synth.replace('XSDB_SLV_DIS', 'OTHER_DEFINE'),
            synth + '\nread_verilog extra.v\n',
        ):
            with self.subTest(changed=changed[-60:]), self.assertRaises(ValueError):
                CHECK.consumers(changed, staging, build)
        with self.assertRaises(ValueError):
            CHECK.consumers(synth, staging.replace('$src_post_enc_dir', '$other'), build)
        with self.assertRaises(ValueError):
            CHECK.consumers(synth, staging, build.replace('source encrypt.tcl', 'source other.tcl'))

    def test_transitive_local_include(self):
        with tempfile.TemporaryDirectory(prefix='qwen-selection-') as directory:
            root = Path(directory)
            design = root / 'hardware/design'
            design.mkdir(parents=True)
            (design / 'top.sv').write_text('`include "one.vi"\n`include "cl_ports.vh"\n')
            (design / 'one.vi').write_text('`include "two.vi"\n')
            (design / 'two.vi').write_text('// retained header\n')
            selected = {'hardware/design/top.sv'}
            manifest = dict.fromkeys(selected | {'hardware/design/one.vi', 'hardware/design/two.vi'})
            vendor, headers = CHECK.local_includes(root, manifest, selected)
            self.assertEqual(vendor, ['cl_ports.vh'])
            self.assertEqual(len(headers), 2)
            del manifest['hardware/design/two.vi']
            with self.assertRaisesRegex(ValueError, 'Unpinned'):
                CHECK.local_includes(root, manifest, selected)

    def test_escaping_include_refused(self):
        with tempfile.TemporaryDirectory(prefix='qwen-selection-') as directory:
            root = Path(directory)
            (root / 'top.sv').write_text('`include "../other.vi"\n')
            with self.assertRaisesRegex(ValueError, 'include path'):
                CHECK.local_includes(root, {'top.sv': {}}, {'top.sv'})


def main(model='qwen3-1.7b', root=ROOT):
    global SELECTED_ROOT, SELECTED_MODEL
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=root)
    args = parser.parse_args()
    SELECTED_ROOT, SELECTED_MODEL = args.root.resolve(strict=True), model
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(ConfigurationTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)


if __name__ == '__main__':
    main()
