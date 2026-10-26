"""Offline extended qualification/profile checks; no physical UART."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import fpga_backend
import qualify_board
import runtime_profile as profile
import sampling_protocol as sampling

EXPECTED_OUTPUTS = (200, 15, 103, 157, 247, 130, 32, 357, 3898, 104,
                    357, 3898, 104, 3436, 4007, 141, 13, 13, 2)


class SyntheticLink:
    def __init__(self, output=EXPECTED_OUTPUTS):
        self.output = iter(output)
        self.calls = []
        self.closed = False
        self.channel = type('Quiet', (), {'pending': bytearray(), 'next': lambda self, timeout: None})()
    def __enter__(self): return self
    def __exit__(self, *args): self.closed = True
    def configure(self, temperature, seed):
        self.calls.append(('settings', temperature, seed))
        return True
    def command(self, operation, token=0):
        self.calls.append((operation, token))
        return next(self.output) if operation == 'step' else None


class SeededProfileTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='seeded-profile-offline-')
        self.root = Path(self.directory.name)
        self.active = self.root / 'local/board-profile.json'
        self.receipt = self.root / 'build/BUILD.json'
        image = self.root / 'build/project/impl/pnr/shared_product.fs'
        profile.private_write(image, b'SYNTHETIC OFFLINE IMAGE')
        profile.private_write(self.receipt, profile.encode(dict(schema=profile.BUILD_SCHEMA,
            variant='seeded-sampling', flow_completed=True, source_inputs_verified=True,
            source_inputs_unchanged=True, timing_qualified=False,
            hardware_inputs_sha256=profile.VARIANTS['seeded-sampling']['inputs_sha256'],
            image_relative_path='project/impl/pnr/shared_product.fs', image_sha256=profile.sha(image.read_bytes()))))
        self.identity = dict(path='/dev/EXPLICIT_OFFLINE_FIXTURE', rdev=1, stat_dev=2, inode=3)
        self.links = []
        self.mocks = [patch.object(profile, 'PROFILE', self.active),
                      patch.object(profile, 'check_device', return_value=self.identity),
                      patch.object(qualify_board, 'app_is_running', return_value=False)]
        for item in self.mocks: item.start()

    def tearDown(self):
        for item in reversed(self.mocks): item.stop()
        self.directory.cleanup()

    def qualify(self, output=EXPECTED_OUTPUTS):
        def factory(observe, deployment):
            link = SyntheticLink(output)
            self.links.append(link)
            return link
        return qualify_board.qualify(self.receipt, self.identity['path'], confirm_loaded=True,
            acknowledge_timing=True, link_factory=factory)

    def rewrite_log(self, record, rows):
        log = Path(record['qualification_log_path'])
        log.write_bytes(b''.join((json.dumps(row, sort_keys=True) + '\n').encode() for row in rows))
        record['qualification_log_sha256'] = profile.sha(log.read_bytes())
        self.active.write_bytes(profile.encode(record))

    def rows(self, record):
        return [json.loads(line) for line in Path(record['qualification_log_path']).read_text().splitlines()]

    def test_extended_qualification_exact_fixtures_and_profile(self):
        record = self.qualify()
        self.assertEqual(profile.load_checked(), record)
        self.assertEqual(profile.configured_variant_id(), 'seeded-sampling')
        self.assertEqual(record['known_answer']['exact_token_checks'], 19)
        calls = self.links[0].calls
        self.assertEqual(len(calls), 45)
        self.assertEqual([call[1:] for call in calls if call[0] == 'settings'],
            [('0', 0), ('0.5', sampling.SEED_A), ('1', sampling.SEED_A), ('2', sampling.SEED_A),
             ('0.5', sampling.SEED_B), ('1', sampling.SEED_B), ('2', sampling.SEED_B), ('0', 0)])
        self.assertEqual(calls[-2:], [('settings', '0', 0), ('clear', 0)])
        self.assertTrue(self.links[0].closed)
        results = [row for row in self.rows(record) if row.get('event') == 'qualification_result']
        self.assertEqual([row['token'] for row in results if row['operation'] == 'step'], list(EXPECTED_OUTPUTS))
        # The T=1 tape repeats through CLEAR with no intervening SETTINGS.
        start = next(i for i, row in enumerate(results)
                     if row['operation'] == 'settings' and row['operand'] == 2)
        self.assertEqual([row['operation'] for row in results[start:start + 11]],
            ['settings', 'append', 'step', 'step', 'step', 'clear', 'append', 'step', 'step', 'step', 'clear'])

    def test_legacy_seven_commands_cannot_qualify_seeded_variant(self):
        record = self.qualify()
        rows = self.rows(record)
        legacy = [row for row in rows if row.get('event') == 'qualification_result' and row['operation'] != 'settings'][:7]
        legacy.append(dict(event='qualification_complete', generated_tokens=[200, 15, 103, 157]))
        self.rewrite_log(record, legacy)
        with self.assertRaises(ValueError): profile.load_checked()

    def test_legacy_known_answer_record_is_rejected(self):
        record = self.qualify()
        record['known_answer'] = dict(prompt_tokens=[378], generated_tokens=[200, 15, 103, 157],
            initial_clear_acknowledged=True, final_clear_acknowledged=True)
        self.active.write_bytes(profile.encode(record))
        with self.assertRaises(ValueError): profile.load_checked()

    def test_updated_log_hash_cannot_hide_wrong_settings_token_or_completion(self):
        for fault in ('seed', 'token', 'completion'):
            with self.subTest(fault=fault):
                # Each iteration keeps its own independent valid record.
                if self.active.exists(): self.active.unlink()
                record = self.qualify()
                rows = self.rows(record)
                if fault == 'seed':
                    row = next(row for row in rows if row.get('event') == 'qualification_result'
                               and row['operation'] == 'settings' and row['operand'] == 2)
                    row['seed'] = '0x00000000000000000000000000000000'
                elif fault == 'token':
                    row = next(row for row in rows if row.get('event') == 'qualification_result' and row.get('token') == 3436)
                    row['token'] = 3437
                else:
                    rows[-1]['generated_tokens'] = list(EXPECTED_OUTPUTS[:-1])
                self.rewrite_log(record, rows)
                with self.assertRaises(ValueError): profile.load_checked()

    def test_wrong_changed_seed_output_preserves_failure_without_profile(self):
        wrong = EXPECTED_OUTPUTS[:-1] + (3,)
        with self.assertRaises(fpga_backend.BoardError): self.qualify(wrong)
        self.assertFalse(self.active.exists())
        self.assertTrue(self.links[0].closed)
        self.assertEqual(self.links[0].calls[-1], ('step', 0))
        logs = list(self.active.parent.glob('qualification-*/uart.jsonl'))
        self.assertEqual(json.loads(logs[0].read_text().splitlines()[-1])['event'], 'qualification_failed')


if __name__ == '__main__': unittest.main(verbosity=2)
