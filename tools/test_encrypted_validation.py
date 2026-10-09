import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('encrypted_validation',HERE/'check_encrypted_validation.py')
checker = importlib.util.module_from_spec(spec); spec.loader.exec_module(checker)


class EncryptedValidationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((HERE.parent/'evidence/encrypted-memory/current-validation.json').read_bytes())

    def test_actual_summary(self):
        self.assertEqual(checker.validate(self.data)['recorded_outputs'],18)

    def test_wrong_image(self):
        self.data['image_sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError,'identity'): checker.validate(self.data)

    def test_missing_production_source(self):
        self.data['production_sources'].pop(next(iter(self.data['production_sources'])))
        with self.assertRaisesRegex(ValueError,'source binding'): checker.validate(self.data)

    def test_changed_source_hash(self):
        self.data['production_sources'][next(iter(self.data['production_sources']))] = '0'*64
        with self.assertRaisesRegex(ValueError,'production source'): checker.validate(self.data)

    def test_wrong_token(self):
        self.data['cases']['fox-zero']['generated_tokens'][0] ^= 1
        with self.assertRaisesRegex(ValueError,'output'): checker.validate(self.data)

    def test_corruption_case_missing(self):
        self.data['cases'].pop('corrupt-runtime')
        with self.assertRaisesRegex(ValueError,'cases'): checker.validate(self.data)

    def test_overstated_proofs_and_coverage(self):
        for name in ('whole_machine_proved','encrypted_variant_formally_verified','public_checker_replays_simulation'):
            data = copy.deepcopy(self.data); data[name] = True
            with self.subTest(name=name), self.assertRaisesRegex(ValueError,'qualification'):
                checker.validate(data)
        self.data['component_evidence']['aes']['coverage']['completed_jobs'] -= 1
        with self.assertRaisesRegex(ValueError,'coverage'): checker.validate(self.data)

    def test_current_geometry_and_inherited_sources(self):
        for field,value in (('weight_cache_banks',2),('weight_aes_engines',4),('weight_sha_engines',4)):
            data = copy.deepcopy(self.data); data[field] = value
            with self.subTest(field=field), self.assertRaisesRegex(ValueError,'geometry'):
                checker.validate(data)
        self.data['inherited_aes_primitive_sources']['project/tang_private_aes256.sv'] = '0'*64
        with self.assertRaisesRegex(ValueError,'Inherited AES'): checker.validate(self.data)

    def test_kv_guard_coverage_and_scope(self):
        for field in ('executable_hashes_recorded_at_execution','whole_machine_proved',
                      'public_checker_replays_simulation'):
            data = copy.deepcopy(self.data); data['kv_guard_component_evidence'][field] = True
            with self.subTest(field=field), self.assertRaisesRegex(ValueError,'guard evidence scope'):
                checker.validate(data)
        self.data['kv_guard_component_evidence']['guards']['geometry']['commands_per_unmutated_case'] -= 1
        with self.assertRaisesRegex(ValueError,'guard coverage'): checker.validate(self.data)


if __name__ == '__main__': unittest.main()
