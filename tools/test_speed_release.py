import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('speed_release_check',HERE/'check_speed_release.py')
checker = importlib.util.module_from_spec(spec); spec.loader.exec_module(checker)
spec = importlib.util.spec_from_file_location('speed_history_check',HERE/'speed_release_history.py')
history = importlib.util.module_from_spec(spec); spec.loader.exec_module(history)


class SpeedEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        package = HERE.parent
        cls.data = json.loads((package/'evidence/speed-2026-10-02/board.json').read_bytes())
        cls.reference = json.loads((package/'evidence/encrypted-memory/broad-board.json').read_bytes())['reference_cases']
        cls.reference.update(json.loads((package/'evidence/read-window/references.json').read_bytes()))
        cls.replay = json.loads((package/'evidence/speed-2026-10-02/replay.json').read_bytes())

    def test_complete_actual_cases(self):
        self.assertEqual(checker.validate(self.data,self.reference)['main_case_outputs'],913)

    def test_wrong_rate_fails(self):
        data = copy.deepcopy(self.data)
        data['variants']['kv-protected']['cases'][0]['cached_tokens_per_second'] *= 1.05
        with self.assertRaisesRegex(ValueError,'arithmetic'): checker.validate(data,self.reference)

    def test_wrong_token_fails(self):
        data = copy.deepcopy(self.data)
        data['variants']['encrypted-memory']['cases'][0]['generated_tokens'][0] ^= 1
        with self.assertRaisesRegex(ValueError,'reference'): checker.validate(data,self.reference)

    def test_wrong_image_fails(self):
        data = copy.deepcopy(self.data)
        data['variants']['kv-protected']['cases'][0]['image_sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError,'image'): checker.validate(data,self.reference)

    def test_full_context_not_inherited(self):
        data = copy.deepcopy(self.data)
        data['variants']['kv-protected']['full_context_board_test_of_this_image'] = False
        with self.assertRaisesRegex(ValueError,'Full-context'): checker.validate(data,self.reference)

    def test_qualification_not_inherited(self):
        data = copy.deepcopy(self.data); data['timing_qualified'] = True
        with self.assertRaisesRegex(ValueError,'qualification'): checker.validate(data,self.reference)

    def test_current_replay_bindings(self):
        self.assertEqual(checker.validate_replay(HERE.parent,self.replay)['recorded_guard_commands'],275913)

    def test_replay_wrong_scope_rejected(self):
        data = copy.deepcopy(self.replay); data['encrypted_variant_formally_verified'] = True
        with self.assertRaisesRegex(ValueError,'qualification'): checker.validate_replay(HERE.parent,data)

    def test_replay_wrong_receipt_rejected(self):
        data = copy.deepcopy(self.replay); data['stages']['attention']['finished_receipt_sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError,'receipt'): checker.validate_replay(HERE.parent,data)

    def test_replay_guard_count_rejected(self):
        data = copy.deepcopy(self.replay); data['guard_full_geometry']['commands'] -= 1
        with self.assertRaisesRegex(ValueError,'guard simulation'): checker.validate_replay(HERE.parent,data)

    def test_each_historical_text_is_exactly_recovered(self):
        package = HERE.parent
        record = json.loads((package/'evidence/speed-2026-10-02/source-revision.json').read_bytes())
        for name,row in record['changes'].items():
            with self.subTest(name=name):
                recovered = history.previous_bytes(package,name,(package/name).read_bytes())
                self.assertEqual(history.sha(recovered),row['before_sha256'])

    def test_current_source_mutation_rejected(self):
        package = HERE.parent; name = 'host-app/runtime_profile.py'
        with self.assertRaisesRegex(ValueError,'current'):
            history.previous_bytes(package,name,(package/name).read_bytes()+b'changed')

    def test_old_image_identifier_needs_exact_current_image(self):
        package = HERE.parent
        for name,digest in history.OLD_IMAGES.items():
            with self.subTest(name=name):
                raw = (package/name).read_bytes()
                self.assertEqual(history.previous_digest(package,name,raw),digest)
                with self.assertRaisesRegex(ValueError,'image'):
                    history.previous_digest(package,name,raw+b'changed')


if __name__=='__main__': unittest.main()
