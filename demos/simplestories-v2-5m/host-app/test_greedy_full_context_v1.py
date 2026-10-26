"""Dedicated offline host fixtures, registered beside unchanged original tests.

Synthetic links/AppTest exercise host behavior only; no device, browser server,
numerical model or programmer is used and no hardware qualification is claimed.
"""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import streamlit as st
from streamlit.testing.v1 import AppTest
import fpga_backend as backend
from test_fpga_backend import FakeLink

GREEDY = ('baseline', 'kv-protected', 'encrypted-memory')


class GreedyFullContextTests(unittest.TestCase):
    def test_greedy_context_and_cli_deadline(self):
        for variant in GREEDY:
            with self.subTest(variant=variant):
                self.assertEqual(tuple(backend.limits_for_variant(variant).__dict__.values()),
                                 (2048, 128, 2049, 32768, 14400))

    def test_none_keeps_original_legacy_limits(self):
        self.assertEqual(tuple(backend.limits_for_variant(None).__dict__.values()),
                         (128, 128, 256, 4000, 120))

    def test_seeded_keeps_3600_second_deadline(self):
        self.assertEqual(tuple(backend.limits_for_variant('seeded-sampling').__dict__.values()),
                         (2048, 128, 2049, 32768, 3600))

    def test_unknown_variant_still_refused(self):
        for value in ('other', '', 0, False, []):
            with self.subTest(value=value), self.assertRaises(ValueError):
                backend.limits_for_variant(value)

    def generate(self, variant, prompt_count, outputs):
        with tempfile.TemporaryDirectory(prefix='greedy-context-synthetic-') as directory, \
             patch('runtime_profile.configured_variant_id', return_value=variant):
            tokenizer = backend.Tokenizer()
            prompt = 'once ' * prompt_count
            self.assertEqual(tokenizer.encode(prompt), [762] * prompt_count)
            peer = FakeLink(output=outputs)
            controller = backend.Controller(tokenizer, lambda observe: peer, directory)
            controller.start('offline-owner', prompt, len(outputs))
            controller.thread.join(30)
            self.assertFalse(controller.thread.is_alive(), 'Synthetic worker must terminate')
            result = controller.snapshot('offline-owner')
            self.assertEqual(result.state, 'complete')
            self.assertEqual(result.uploaded, prompt_count)
            self.assertEqual(result.generated, list(outputs))
            self.assertTrue(result.clear_acknowledged and peer.closed)
            self.assertEqual(peer.calls, [('clear', 0)] + [('append', 762)] * prompt_count
                             + [('step', 0)] * len(outputs) + [('clear', 0)])
            self.assertFalse(result.sampling_settings_applied)

    def test_2048_prompt_accepts_one_final_output_slot(self):
        for variant in GREEDY:
            with self.subTest(variant=variant):
                self.generate(variant, 2048, (200,))

    def test_2047_prompt_accepts_two_final_output_slots(self):
        for variant in GREEDY:
            with self.subTest(variant=variant):
                self.generate(variant, 2047, (200, 15))

    def test_context_overflow_and_invalid_input_never_start_worker(self):
        for variant in GREEDY:
            with tempfile.TemporaryDirectory(prefix='greedy-context-refusal-') as directory, \
                 patch('runtime_profile.configured_variant_id', return_value=variant):
                for prompt, count in [('once ' * 2048, 2), ('once ' * 2047, 3),
                                      ('once ' * 2049, 1), ('once', 129),
                                      ('x' * 32769, 1), ('[EOS]', 1)]:
                    with self.subTest(variant=variant, size=len(prompt), count=count):
                        peer = FakeLink()
                        controller = backend.Controller(link_factory=lambda observe: peer, logs=directory)
                        with self.assertRaises(ValueError):
                            controller.start('offline-owner', prompt, count)
                        self.assertIsNone(controller.thread)
                        self.assertFalse(peer.calls)

    def test_live_uart_uses_cli_step_deadline_and_never_greedy_settings(self):
        class Channel:
            def __init__(self):
                self.sent = []; self.deadlines = []; self.kind = 0x81; self.token = 200
            def send(self, raw, label):
                self.sent.append((raw, label))
            def next(self, timeout):
                self.deadlines.append(timeout)
                return dict(kind='normal', response=self.kind, token=self.token)
        for variant in GREEDY:
            with self.subTest(variant=variant):
                link = backend.LiveUART(lambda event: None)
                link.profile = dict(variant=variant)
                link.channel = Channel()
                self.assertEqual(link.command('step'), 200)
                link.channel.kind, link.channel.token = 0x82, 0
                self.assertIsNone(link.command('clear'))
                self.assertEqual(link.channel.deadlines, [14400, 10])
                self.assertEqual([label for _, label in link.channel.sent], ['step', 'clear'])
                self.assertTrue(all(len(raw) == 5 for raw, _ in link.channel.sent))
                sent = list(link.channel.sent)
                self.assertFalse(link.configure('0'))
                with self.assertRaises(backend.BoardError):
                    link.configure('1', 1)
                self.assertEqual(link.channel.sent, sent)

    def test_full_context_footer_and_bounds_without_sampling_controls(self):
        for variant in GREEDY:
            with self.subTest(variant=variant), tempfile.TemporaryDirectory(prefix='greedy-ui-offline-') as directory:
                st.cache_resource.clear()
                peer = FakeLink()
                controller = backend.Controller(link_factory=lambda observe: peer, logs=directory)
                with patch('fpga_backend.Controller', return_value=controller), \
                     patch('runtime_profile.configured_variant_id', return_value=variant):
                    app = AppTest.from_file(str(Path(__file__).with_name('streamlit_app.py')),
                                            default_timeout=30).run()
                self.assertFalse(app.exception)
                self.assertEqual(app.text_area[0].max_chars, 32768)
                self.assertEqual(app.number_input[0].max, 128)
                self.assertFalse(app.segmented_control)
                self.assertFalse(app.text_input)
                captions = '\n'.join(item.value for item in app.caption)
                self.assertIn('Up to 2,048 prompt tokens and 128 new tokens', captions)
                self.assertIn('2,049 tokens combined', captions)
                self.assertNotIn('Initial interactive-demo limit', captions)
                self.assertFalse(peer.calls)
                st.cache_resource.clear()


if __name__ == '__main__':
    unittest.main(verbosity=2)
