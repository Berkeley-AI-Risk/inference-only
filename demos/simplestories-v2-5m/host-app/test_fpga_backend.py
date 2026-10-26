"""Offline fixtures only. These tests never open the physical board."""
import json
from pathlib import Path
import stat
import tempfile
import threading
import unittest
from unittest.mock import patch

import fpga_backend as backend


class FakeLink:
    def __init__(self, output=(200, 15, 103, 157), fail=None, gate=None):
        self.output = iter(output)
        self.calls = []
        self.fail = fail
        self.gate = gate
        self.entered = threading.Event()
        self.closed = False

    def __enter__(self): return self
    def __exit__(self, *args): self.closed = True

    def command(self, operation, token=0):
        self.calls.append((operation, token))
        if self.gate and operation == self.gate[0]:
            self.entered.set()
            if not self.gate[1].wait(2): raise TimeoutError('offline test gate')
        if self.fail == operation:
            raise backend.BoardError('explicitly synthetic fault fixture')
        return next(self.output) if operation == 'step' else None


class BackendTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='fpga-console-offline-')
        self.tokenizer = backend.Tokenizer()

    def tearDown(self): self.directory.cleanup()

    def controller(self, fake):
        return backend.Controller(self.tokenizer, lambda observe: fake, self.directory.name)

    def finish(self, controller):
        controller.thread.join(3)
        self.assertFalse(controller.busy())
        return controller.snapshot('test-owner')

    def test_fixed_tokenizer_no_prompt_eos(self):
        self.assertEqual(self.tokenizer.encode('once'), [762])
        self.assertEqual(self.tokenizer.encode('around'), [378])
        self.assertEqual(self.tokenizer.encode('ONCE upon a time'), [762, 1310, 32, 398])
        self.assertNotIn(1, self.tokenizer.encode('once upon a time'))
        self.assertEqual(self.tokenizer.decode([378, 200, 15, 103, 1]), 'around him. he')
        self.assertIn('[UNK]', self.tokenizer.decode([0]))

    def test_text_limits(self):
        for value in ('', ' ', '\x00', 'x' * 4001, 'once ' * 129, '[EOS]'):
            with self.subTest(value=value[:20]), self.assertRaises(ValueError):
                self.tokenizer.encode(value)

    def test_generation_and_clear(self):
        fake = FakeLink(); c = self.controller(fake)
        c.start('test-owner', 'once', 4); result = self.finish(c)
        self.assertEqual(result.state, 'complete')
        self.assertEqual(result.generated, [200, 15, 103, 157])
        self.assertEqual(fake.calls, [('clear', 0), ('append', 762)] + [('step', 0)] * 4 + [('clear', 0)])
        self.assertTrue(result.clear_acknowledged and fake.closed)
        self.assertGreater(result.streaming_tps, 0)
        self.assertEqual(len(result.arrivals_seconds), 4)
        self.assertEqual(stat.S_IMODE(Path(result.log_path).stat().st_mode), 0o600)
        records = [json.loads(row) for row in Path(result.log_path).read_text().splitlines()]
        self.assertEqual(records[-1]['event'], 'finished')
        self.assertFalse(records[0]['software_inference'])

    def test_unknown_and_eos(self):
        fake = FakeLink(output=(0, 1, 200)); c = self.controller(fake)
        c.start('test-owner', 'once', 4); result = self.finish(c)
        self.assertEqual(result.generated, [0, 1])
        self.assertIn('[UNK]', result.text)
        self.assertNotIn('[EOS]', result.text)
        self.assertEqual(result.stop_reason, 'Model reached end of story')
        self.assertEqual(sum(op == 'step' for op, _ in fake.calls), 2)

    def test_invalid_count_rejected_before_hardware(self):
        fake = FakeLink(); c = self.controller(fake)
        for value in (True, 0, -1, 129, 2.5, '4'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                c.start('test-owner', 'once', value)
        self.assertFalse(fake.calls)

    def test_no_cleanup_or_retry_after_fault(self):
        fake = FakeLink(fail='step'); c = self.controller(fake)
        c.start('test-owner', 'once', 4); result = self.finish(c)
        self.assertEqual(result.state, 'error')
        self.assertFalse(result.clear_acknowledged)
        self.assertEqual(fake.calls, [('clear', 0), ('append', 762), ('step', 0)])
        self.assertTrue(c.needs_board_check and fake.closed)
        with self.assertRaises(RuntimeError): c.start('test-owner', 'once', 1)

    def test_stop_drains_inflight_step(self):
        gate = threading.Event(); fake = FakeLink(gate=('step', gate)); c = self.controller(fake)
        c.start('test-owner', 'once', 4)
        self.assertTrue(fake.entered.wait(1))
        c.stop('test-owner')
        self.assertTrue(c.busy())
        self.assertEqual(c.snapshot('another-tab').state, 'busy in another tab')
        self.assertEqual(c.snapshot('another-tab').prompt, '')
        with self.assertRaises(RuntimeError): c.start('another-tab', 'once', 1)
        with self.assertRaises(RuntimeError): c.stop('another-tab')
        gate.set(); result = self.finish(c)
        self.assertEqual(result.generated, [200])
        self.assertEqual(result.state, 'stopped')
        self.assertTrue(result.clear_acknowledged)
        self.assertEqual(fake.calls[-2:], [('step', 0), ('clear', 0)])

    def test_stop_during_prompt_upload(self):
        gate = threading.Event(); fake = FakeLink(gate=('append', gate)); c = self.controller(fake)
        c.start('test-owner', 'once upon a time', 4)
        self.assertTrue(fake.entered.wait(1)); c.stop('test-owner'); gate.set()
        result = self.finish(c)
        self.assertEqual(fake.calls, [('clear', 0), ('append', 762), ('clear', 0)])
        self.assertFalse(result.generated)
        self.assertEqual(result.state, 'stopped')

    def test_streaming_rate_excludes_prefill(self):
        result = backend.Result(arrivals_seconds=[20.0, 20.2, 20.4])
        self.assertAlmostEqual(result.streaming_tps, 5.0)
        self.assertIsNone(backend.Result(arrivals_seconds=[20]).streaming_tps)

    def test_snapshot_is_a_copy(self):
        c = self.controller(FakeLink()); c.start('test-owner', 'once', 1)
        result = self.finish(c); result.generated.clear()
        self.assertEqual(c.snapshot('test-owner').generated, [200])

    def test_actual_wire_wrapper_invalid_replies(self):
        class Channel:
            def __init__(self, event): self.event = event; self.sent = []
            def send(self, frame, operation): self.sent.append((frame, operation))
            def next(self, timeout): return self.event
        for event in (None, {'kind':'diagnostic'}, {'kind':'noise'}, {'kind':'malformed'},
                      {'kind':'normal', 'response':0xc1, 'token':0},
                      {'kind':'normal', 'response':0x81, 'token':4019}):
            link = backend.LiveUART(lambda row: None); link.channel = Channel(event)
            with self.subTest(event=event), self.assertRaises(backend.BoardError): link.command('step')
            self.assertEqual(len(link.channel.sent), 1)
        link = backend.LiveUART(lambda row: None)
        link.channel = Channel({'kind':'normal', 'response':0x81, 'token':200})
        self.assertEqual(link.command('step'), 200)
        self.assertEqual(link.channel.sent[0][0].hex(), 'a5010000da')
        with self.assertRaises(ValueError): link.command('write_weights', 12)

    def test_malformed_startup_requires_board_check(self):
        class FakeSession:
            def __init__(self, *args, **kwargs): self.fd = 17; self.closed = False
            def open(self): return self
            def close(self): self.closed = True
        class BrokenChannel:
            def __init__(self, *args): self.pending = bytearray()
            def next(self, timeout): raise ValueError('synthetic bad frame CRC')
        link = backend.LiveUART(lambda event: None)
        with patch.object(link.client, 'TokenMachineSession', FakeSession), \
             patch.object(link.reader, 'StrictChannel', BrokenChannel), \
             patch.object(link, '_deployment', return_value={'device': {'path': '/dev/offline-fixture'},
                 'image_sha256': 'synthetic', 'build_receipt_sha256': 'synthetic'}), \
             patch('runtime_profile.check_open_device'):
            with self.assertRaises(backend.BoardError): link.__enter__()
        self.assertTrue(link.session.closed)


if __name__ == '__main__': unittest.main(verbosity=2)
