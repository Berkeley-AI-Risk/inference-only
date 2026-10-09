import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('baseline_speed_checker',HERE/'check_baseline_speed.py')
check=importlib.util.module_from_spec(spec); spec.loader.exec_module(check)


class BaselineSpeedTests(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((HERE.parent/check.DIRECTORY/'board.json').read_bytes())
        self.reference=json.loads((HERE.parent/'evidence/read-window/references.json').read_bytes())

    def test_actual_selected_evidence(self):
        self.assertEqual(check.check(HERE.parent)['current_baseline_outputs'],391)

    def test_mutations_rejected(self):
        for change in ('token','image','rate','stream','missing','controls','replay','qualification','repeat','hash','single'):
            data=copy.deepcopy(self.data); row=data['cases'][0]
            if change=='token': row['long_generated_tokens'][0]^=1
            elif change=='image': row['image_sha256']='0'*64
            elif change=='rate': row['cached_command_tokens_per_second']*=1.01
            elif change=='stream': row['reply_elapsed_seconds'][-1]*=1.01
            elif change=='missing': data['cases'].pop()
            elif change=='controls': row['negative_controls_rejected']=3
            elif change=='replay': data['clear_replay_outputs']=36
            elif change=='qualification': data['full_context_board_test_of_this_image']=False
            elif change=='repeat': data['repeated_cached_tokens_per_second'][1]*=1.01
            elif change=='hash': row['private_uart_sha256']='bad'
            elif change=='single': data['cases'][-1]['cached_command_tokens_per_second']=1
            with self.subTest(change=change), self.assertRaises(ValueError): check.validate(data,self.reference)

    def test_replay_overclaim_rejected(self):
        replay=json.loads((HERE.parent/check.DIRECTORY/'replay.json').read_bytes())
        replay['composed']['complete_second_solver']=True
        with self.assertRaisesRegex(ValueError,'scope'): check.validate_replay(HERE.parent,replay)

    def test_changed_replay_input_rejected(self):
        replay=json.loads((HERE.parent/check.DIRECTORY/'replay.json').read_bytes())
        replay['source_sha256']['hardware/project/sha.sv']='0'*64
        with self.assertRaisesRegex(ValueError,'input'): check.validate_replay(HERE.parent,replay)

    def test_numerical_source_association_rejected(self):
        for key in ('model','bank','token','composed'):
            replay=json.loads((HERE.parent/check.DIRECTORY/'replay.json').read_bytes())
            replay['run_manifest_sha256'][key]='0'*64
            with self.subTest(key=key), self.assertRaisesRegex(ValueError,'association'):
                check.validate_replay(HERE.parent,replay)

    def test_missing_secondary_conclusion_rejected(self):
        replay=json.loads((HERE.parent/check.DIRECTORY/'replay.json').read_bytes())
        replay['composed']['secondary_runs'][1]['proved'].remove(50)
        with self.assertRaisesRegex(ValueError,'secondary'): check.validate_replay(HERE.parent,replay)


if __name__=='__main__': unittest.main()
