"""File-only checks for HWIC source selection and evidence-scope drift."""
from pathlib import Path
import argparse
import copy
import json
import sys
import types
import unittest

HERE = Path(__file__).resolve().parent
MAP = HERE.parent / 'evidence/configuration-map-2026-11-06'
checker = types.ModuleType('hwic_configuration_rows')
checker.__file__ = str(MAP / 'check_rows.py')
exec(compile(Path(checker.__file__).read_bytes(), checker.__file__, 'exec'), checker.__dict__)
ROOT = HERE.parents[2]


class ConfigurationRows(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((MAP / 'rows.json').read_bytes())

    def reject(self, message):
        with self.assertRaisesRegex(ValueError, message):
            checker.verify(ROOT, self.data)

    def config(self, name):
        return next(x for x in self.data['configurations'] if x['configuration'] == name)

    def test_current_public_selection(self):
        result = checker.verify(ROOT, self.data)
        self.assertEqual(result['identical_hwic_source_operands'], 39)
        self.assertEqual(result['private_configurations_recorded_only'], 3)
        self.assertFalse(result['rtl_simulation_run'])

    def test_source_hash_drift(self):
        next(x for x in self.data['source_records'] if x['availability'] == 'public')['sha256'] = '0' * 64
        self.reject('source record changed')

    def test_private_selection_cannot_gain_public_replay(self):
        self.config('attention-reuse')['reproduction']['public_fresh_rtl_replay'] = True
        self.reject('private selection represented as public replay')

    def test_reuse_requires_actual_selected_content(self):
        self.data['public_reuse']['pairs'][0]['sha256'] = '0' * 64
        self.reject('reuse content pairs changed')

    def test_hwic_define_drift(self):
        self.config('public-rom')['build']['defines'].append('BOARD1_PROJECTION_MAC_NATIVE')
        self.reject('HWIC define selection changed')

    def test_geometry_capacity_mismatch(self):
        self.data['memory_process']['split_payload_banks']['count'] -= 1
        self.reject('split KV capacity arithmetic')

    def test_rom_capacity_must_match_source(self):
        self.data['memory_process']['central_rom_arrays'][0]['depth'] -= 1
        self.reject('ROM array source binding')

    def test_no_partial_campaign_or_source_review_promotion(self):
        clean = copy.deepcopy(self.data)
        self.config('split-kv')['evidence']['full_corpus_accepted'] = True
        self.reject('partial campaign promoted')
        self.data = clean
        self.config('attention-reuse')['evidence']['native_invocations'] = 1
        self.reject('source-only candidate promoted')

    def test_public_path_cannot_escape_release(self):
        next(x for x in self.data['source_records'] if x['availability'] == 'public')['path'] = '../outside'
        self.reject('invalid public path')

    def test_native_project_order_and_disabled_inputs(self):
        xml = '<Project><FileList><File path="defines.v" type="file.verilog" enable="1"/><File path="top.sv" type="file.verilog" enable="1"/><File path="not-selected.sv" type="file.verilog" enable="0"/><File path="clock.sdc" type="file.sdc" enable="1"/></FileList></Project>'
        self.assertEqual(checker.project_sources(xml), ['defines.v', 'top.sv'])
        self.assertNotEqual(checker.project_sources(xml), ['top.sv', 'defines.v'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--release-root', type=Path, default=ROOT)
    args, remaining = parser.parse_known_args()
    ROOT = args.release_root
    unittest.main(argv=[sys.argv[0]] + remaining)
