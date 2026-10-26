"""Offline seeded worker/wire checks. Every board response is synthetic."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import fpga_backend as backend
import sampling_protocol as sampling
from test_fpga_backend import FakeLink


class TinyTokenizer:
    def encode(self, prompt): return [378]
    def decode(self, tokens): return ' '.join(str(token) for token in tokens)


class SeededLink(FakeLink):
    def __init__(self, **kwargs):
        super().__init__(output=(357, 200, 247, 3436), **kwargs)

    def configure(self, temperature, seed):
        self.calls.append(('settings', (temperature, seed)))
        if self.fail == 'settings':
            raise backend.BoardError('synthetic settings rejection')
        return True

    def resume(self, observe): pass


class SeededBackendTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='seeded-backend-offline-')

    def tearDown(self): self.directory.cleanup()

    def controller(self, link, retained=False):
        return backend.Controller(TinyTokenizer(), lambda observe: link, self.directory.name,
                                  keep_connection=retained)

    def finish(self, controller):
        controller.thread.join(3)
        self.assertFalse(controller.busy())
        return controller.snapshot('owner')

    def test_fresh_seed_chosen_once_and_settings_before_prompt(self):
        link = SeededLink()
        controller = self.controller(link)
        with patch.object(sampling.secrets, 'randbits', return_value=sampling.SEED_A) as entropy:
            controller.start('owner', 'around', 1, temperature='1', seed='')
            result = self.finish(controller)
        entropy.assert_called_once_with(128)
        self.assertEqual(result.seed, '0x99aabbccddeeff001122334455667788')
        self.assertTrue(result.seed_used and result.sampling_settings_applied)
        self.assertEqual(link.calls[:3], [('clear', 0), ('settings', ('1', sampling.SEED_A)), ('append', 378)])
        rows = [json.loads(line) for line in Path(result.log_path).read_text().splitlines()]
        self.assertEqual(rows[0]['seed'], result.seed)
        self.assertEqual(rows[-1]['result']['temperature'], '1')
        self.assertIsNone(controller.snapshot('another-owner').seed)

    def test_retained_positive_run_followed_by_greedy_must_send_settings_zero(self):
        link = SeededLink()
        controller = self.controller(link, retained=True)
        try:
            controller.start('owner', 'around', 1, temperature='1', seed=123)
            self.assertEqual(self.finish(controller).state, 'complete')
            self.assertTrue(controller.connection_retained())
            boundary = len(link.calls)
            with patch.object(sampling.secrets, 'randbits', side_effect=AssertionError('greedy entropy')):
                controller.start('owner', 'around', 1, temperature='0', seed='ignored in greedy')
                result = self.finish(controller)
            self.assertEqual(link.calls[boundary:boundary + 3],
                             [('clear', 0), ('settings', ('0', 0)), ('append', 378)])
            self.assertIsNone(result.seed)
            self.assertFalse(result.seed_used)
        finally:
            controller.disconnect()

    def test_seed_and_temperature_validation_before_worker(self):
        link = SeededLink()
        controller = self.controller(link)
        for temperature, seed in (('3', 1), ('1', -1), ('1', 1 << 128), ('1', True), ('1', 'oops')):
            with self.subTest(temperature=temperature, seed=seed), self.assertRaises(ValueError):
                controller.start('owner', 'around', 1, temperature=temperature, seed=seed)
        self.assertFalse(link.calls)

    def test_settings_failure_stops_before_append_and_never_cleans_up_or_retries(self):
        link = SeededLink(fail='settings')
        controller = self.controller(link)
        controller.start('owner', 'around', 1, temperature='0.5', seed=1)
        result = self.finish(controller)
        self.assertEqual(result.state, 'error')
        self.assertEqual(link.calls, [('clear', 0), ('settings', ('0.5', 1))])
        self.assertTrue(controller.needs_board_check and link.closed)
        self.assertFalse(result.clear_acknowledged)

    def test_legacy_link_cannot_generate_positive_temperature(self):
        link = FakeLink()
        controller = self.controller(link)
        controller.start('owner', 'around', 1, temperature='1', seed=1)
        self.assertEqual(self.finish(controller).state, 'error')
        self.assertEqual(link.calls, [('clear', 0)])

    def test_configure_exact_frame_ack_and_legacy_gating(self):
        class Channel:
            def __init__(self, event): self.event, self.sent = event, []
            def send(self, frame, label): self.sent.append((frame, label))
            def next(self, timeout): return self.event
        link = backend.LiveUART(lambda event: None)
        link.profile = {'variant': 'seeded-sampling'}
        link.channel = Channel({'kind': 'normal', 'response': 0x83, 'token': 2})
        self.assertTrue(link.configure('1', sampling.SEED_A))
        frame, label = link.channel.sent[0]
        self.assertEqual(label, 'settings')
        self.assertEqual(len(frame), 20)
        self.assertEqual(frame[:3], bytes((0xa5, 3, 2)))
        self.assertEqual(frame[3:19], sampling.SEED_A.to_bytes(16, 'little'))
        self.assertEqual(frame[-1], sampling.codec.crc8(frame[:-1]))
        for event in (None, {'kind': 'normal', 'response': 0xc3, 'token': 0},
                      {'kind': 'normal', 'response': 0x83, 'token': 1}):
            link.channel = Channel(event)
            with self.assertRaises(backend.BoardError): link.configure('1', 1)
            self.assertEqual(len(link.channel.sent), 1)
        link.profile = {'variant': 'baseline'}
        link.channel = Channel(None)
        self.assertFalse(link.configure('0', 0))
        with self.assertRaises(backend.BoardError): link.configure('2', 1)
        self.assertFalse(link.channel.sent)

    def test_original_strict_channel_accepts_only_bounded_settings_adapter(self):
        link = backend.LiveUART(lambda event: None)
        adapted = sampling.decoder_client(link.client)
        for code in range(4):
            prefix = bytes((0x5a, 0x83, code, 0))
            frame = prefix + bytes((sampling.codec.crc8(prefix),))
            channel = link.reader.StrictChannel(None, adapted, lambda event: None)
            channel.pending.extend(frame)
            self.assertEqual(channel.next(1)['token'], code)
        prefix = bytes((0x5a, 0x83, 4, 0))
        channel.pending.extend(prefix + bytes((sampling.codec.crc8(prefix),)))
        with self.assertRaises(ValueError): channel.next(1)


if __name__ == '__main__': unittest.main(verbosity=2)
