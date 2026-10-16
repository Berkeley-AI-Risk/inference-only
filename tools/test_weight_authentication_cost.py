"""Offline negative controls for the measured runtime-authentication comparison."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('auth_cost_check', ROOT / 'tools/check_weight_authentication_cost.py')
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class AuthenticationCostTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = ROOT / CHECK.DIRECTORY
        cls.board = CHECK.read(cls.directory / 'board.json')
        cls.references = CHECK.read(ROOT / 'evidence/read-window/references.json')
        cls.replayer = CHECK.module(cls.directory / 'uart_replay.py')
        cls.events = [json.loads(line) for line in
                      (cls.directory / 'transcripts/baseline-3/around128.jsonl').read_text().splitlines()]

    def replay(self, events):
        return CHECK.replay_case(self.replayer, self.references['around128'], events)

    def altered_board(self, modify):
        board = copy.deepcopy(self.board); modify(board)
        original = CHECK.read
        with patch.object(CHECK, 'read', side_effect=lambda p: board if Path(p) == self.directory / 'board.json' else original(p)):
            with self.assertRaises(ValueError):
                CHECK.check(ROOT)

    def test_complete_record(self):
        result = CHECK.check(ROOT)
        self.assertEqual((result['board_cases'], result['main_outputs'], result['auxiliary_outputs']), (17, 1676, 204))
        self.assertFalse(result['timing_qualified'])

    def test_recorded_protocol_negative_controls(self):
        plan = self.replayer.commands(self.references['around128']['prompt_tokens'],
                                      self.references['around128']['generated_tokens'])
        self.assertEqual(self.replayer.negative_controls(plan, self.events), 4)

    def test_missing_trial_rejected(self):
        self.altered_board(lambda board: board['cases'].pop(9))

    def test_slow_repeat_not_discarded(self):
        self.altered_board(lambda board: board['comparisons'].pop(4))

    def test_changed_summary_rejected(self):
        self.altered_board(lambda board: board['comparisons'][0].update(extra_time_per_token_fraction=0))

    def test_changed_timing_rejected(self):
        self.altered_board(lambda board: board['cases'][0]['measured']['cached_decode_seconds'].__setitem__(0, 0.01))

    def test_changed_image_rejected(self):
        self.altered_board(lambda board: board['cases'][0].update(image_sha256=CHECK.DIAGNOSTIC))

    def test_qualification_overclaim_rejected(self):
        self.altered_board(lambda board: board.update(timing_qualified=True))

    def test_invalid_duration_rejected(self):
        for value in (0, -1, float('nan'), float('inf')):
            events = copy.deepcopy(self.events)
            next(e for e in events if e['event'] == 'command_result')['seconds'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.replay(events)

    def test_private_field_rejected(self):
        events = copy.deepcopy(self.events); events[0]['device'] = 'private-device'
        with self.assertRaises(ValueError):
            self.replay(events)

    def test_unknown_source_change_rejected(self):
        text = (ROOT / 'hardware/project/bank.sv').read_text()
        with self.assertRaises(ValueError):
            CHECK.diagnostic_bank(text.replace('state_q<=valid_words_q==128 ? READ0 : ZERO;', 'state_q<=READY;'))


if __name__ == '__main__':
    unittest.main()
