"""Offline codec/client/reference checks. No hardware or network access."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

VARIANT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


client = load('_test_public_seeded_generate', VARIANT / 'tools/generate.py')
codec = client.codec
oracle = load('_test_public_seeded_oracle', VARIANT / 'tools/sampler_oracle.py')


def reply(kind, token=0):
    body = bytes((0x5a, kind, token & 255, token >> 8))
    return body + bytes((codec.crc8(body),))


class MockSession:
    def __init__(self, *args, reject_settings=False, timeout_step=False, wrong_ack=False, **kwargs):
        self.reader = self
        self._pending = bytearray()
        self._frame_observer = None
        self.frames = []
        self.pending = []
        self.generated = 0
        self.closed = False
        self.reject_settings = reject_settings
        self.timeout_step = timeout_step
        self.wrong_ack = wrong_ack

    @property
    def buffered_bytes(self):
        return len(self._pending)

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.closed = True

    def _send(self, frame):
        if codec.crc8(frame[:-1]) != frame[-1]:
            raise AssertionError('client sent invalid CRC')
        self.frames.append(frame)
        op = frame[1]
        if op == 3:
            self.pending.append(reply(0xc3 if self.reject_settings else 0x83,
                                      0 if self.reject_settings else frame[2]))
        elif op == 1:
            if self.timeout_step:
                return
            token = (357, 3898, 104)[self.generated]
            self.generated += 1
            self.pending.append(reply(0x81, token))
        else:
            self.pending.append(reply(0x80 | op, 1 if self.wrong_ack else 0))

    def read_frame(self, timeout):
        if not self.pending:
            raise TimeoutError('mock only: no pending response')
        frame = self.pending.pop(0)
        if self._frame_observer is not None:
            self._frame_observer(frame)
        return frame


class CodecTests(unittest.TestCase):
    def test_codec_boundaries_embedded_commands_and_corruption(self):
        self.assertEqual(codec.encode_legacy(0, 378).hex(), 'a5007a0196')
        seeds = (0, (1 << 128) - 1, int.from_bytes(bytes.fromhex('a502000067a50100007ca5030000a50000'), 'little'))
        for seed in seeds:
            for code in range(4):
                frame = codec.encode_settings(code, seed)
                self.assertEqual(len(frame), 20)
                self.assertEqual(frame[3:19], seed.to_bytes(16, 'little'))
                self.assertEqual(codec.crc8(frame[:-1]), frame[-1])
        for code in (-1, 4, True):
            with self.assertRaises(ValueError):
                codec.encode_settings(code, 0)
        for seed in (-1, 1 << 128, True):
            with self.assertRaises(ValueError):
                codec.choose_seed(seed)
        packet = reply(0x83, 3)
        self.assertEqual(codec.decode_response(packet).operand, 3)
        for index in range(5):
            broken = bytearray(packet)
            broken[index] ^= 1
            with self.assertRaises(ValueError):
                codec.decode_response(bytes(broken))
        for packet in (reply(0x81, 4019), reply(0x83, 4), reply(0x82, 1), reply(0x84)):
            with self.assertRaises(ValueError):
                codec.decode_response(packet)


class ClientTests(unittest.TestCase):
    def run_cli(self, args):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            code = client.main(args)
        return code, [json.loads(line) for line in out.getvalue().splitlines()]

    def test_dry_run_never_imports_transport_and_displays_seed(self):
        with patch.object(client, 'released_transport', side_effect=AssertionError('opened transport')):
            code, records = self.run_cli(['--temperature', '2', '--seed', '0x123', '--steps', '3'])
        self.assertEqual(code, 0)
        self.assertEqual(records[0]['seed'], '0x00000000000000000000000000000123')
        self.assertFalse(records[0]['hardware_access'])
        self.assertEqual(len(records[1]['frames']), 6)

    def test_seeded_generation_order_frames_timings_and_cleanup(self):
        session = MockSession()
        transport = types.SimpleNamespace(TokenMachineSession=lambda *a, **k: session)
        with patch.object(client, 'released_transport', return_value=transport):
            code, records = self.run_cli(['--execute', '--device', '/dev/MOCK_ONLY',
                '--temperature', '1', '--seed', '0x99aabbccddeeff001122334455667788', '--steps', '3'])
        self.assertEqual(code, 0)
        self.assertEqual([frame[1] for frame in session.frames], [2, 3, 0, 1, 1, 1])
        self.assertEqual(records[-1]['generated_tokens'], [357, 3898, 104])
        self.assertEqual(records[-1]['cached_steps'], 2)
        self.assertTrue(session.closed)

    def test_invalid_inputs_stop_before_transport(self):
        cases = (['--steps', '0'], ['--tokens', '4019'], ['--seed', '-1'],
                 ['--timeout', 'nan'], ['--timeout', '0'], ['--steps', '2049'],
                 ['--execute'], ['--temperature', '3'])
        with patch.object(client, 'released_transport', side_effect=AssertionError('opened transport')), \
             contextlib.redirect_stderr(io.StringIO()):
            for args in cases:
                with self.subTest(args=args), self.assertRaises(SystemExit):
                    client.main(args)

    def test_rejection_and_timeout_stop_without_retry(self):
        for kwargs, expected_ops in ((dict(reject_settings=True), [2, 3]),
                                     (dict(timeout_step=True), [2, 3, 0, 1]),
                                     (dict(wrong_ack=True), [2])):
            with self.subTest(kwargs=kwargs):
                session = MockSession(**kwargs)
                transport = types.SimpleNamespace(TokenMachineSession=lambda *a, **k: session)
                with patch.object(client, 'released_transport', return_value=transport):
                    code, records = self.run_cli(['--execute', '--device', '/dev/MOCK_ONLY', '--steps', '1'])
                self.assertEqual(code, 1)
                self.assertEqual(records[-1]['event'], 'failed')
                self.assertEqual([frame[1] for frame in session.frames], expected_ops)
                self.assertTrue(session.closed)

    def test_existing_receipt_is_preserved_before_open(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / 'existing.jsonl'
            receipt.write_bytes(b'preserve\n')
            with patch.object(client, 'released_transport', side_effect=AssertionError('opened transport')):
                with self.assertRaises(FileExistsError):
                    client.main(['--execute', '--device', '/dev/MOCK_ONLY', '--record', str(receipt)])
            self.assertEqual(receipt.read_bytes(), b'preserve\n')

    def test_actual_pinned_reader_noise_crc_and_partial_reply_fail(self):
        transport = client.released_transport()
        for incoming in (b'noise', b'noise' + reply(0x83, 2), b'\x5a\x81',
                         reply(0x83, 2)[:-1] + b'\x00'):
            with self.subTest(incoming=incoming):
                reader = transport.ResponseFrameReader(-1)
                events = []
                wire = client.WireClient(types.SimpleNamespace(reader=reader),
                    lambda event, **data: events.append((event, data)), 1)
                reader._pending.extend(incoming)
                with patch.object(transport.select, 'select', return_value=((), (), ())):
                    with self.assertRaises((ValueError, TimeoutError)):
                        wire.quiet('negative')
                self.assertTrue(any(event in ('wire_noise', 'raw_rx', 'receive_error')
                                    for event, _ in events))

    def test_transport_hash_mismatch_refuses_import(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory)
            (package / 'host-app').mkdir()
            (package / 'host-app/token_machine_uart.py').write_text('raise RuntimeError("should not import")\n')
            with patch.object(client, 'PACKAGE', package):
                with self.assertRaisesRegex(ValueError, 'transport changed'):
                    client.released_transport()

    def test_clean_recipient_isolated_dry_run_has_no_private_dependency(self):
        with tempfile.TemporaryDirectory() as directory:
            tools = Path(directory) / 'variants/seeded-sampling/tools'
            tools.mkdir(parents=True)
            for name in ('generate.py', 'settings_codec.py'):
                shutil.copy2(VARIANT / 'tools' / name, tools / name)
            run = subprocess.run([sys.executable, '-I', '-S', '-B', str(tools / 'generate.py'),
                                  '--temperature', '0.5', '--seed', '0x123', '--steps', '3'],
                                 cwd=directory, capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertFalse(json.loads(run.stdout.splitlines()[0])['hardware_access'])


class ReferenceTests(unittest.TestCase):
    def test_seed_zero_known_prng_word_and_cdf_boundaries(self):
        self.assertEqual(oracle.initial_state(0), (1, 0))
        random, state = oracle.draw((1, 0))
        self.assertEqual(random, 131073)
        self.assertEqual(state, (562949955518465, 268435456))
        for random, expected in ((0, 0), ((1 << 63) - 1, 0), (1 << 63, 1), ((1 << 64) - 1, 1)):
            self.assertEqual(oracle.select_mass([1, 1], random), expected)
        self.assertEqual(oracle.select_mass([0, 5, 0], (1 << 64) - 1), 1)

    def test_table_tail_clipping_greedy_ties_and_seed_state(self):
        rows = [(0, -8)] + [(-4096, -8)] * 4018
        mass = oracle.weights(rows, 2)
        self.assertEqual(mass, [1 << 30] + [0] * 4018)
        state = oracle.initial_state(123)
        self.assertEqual(oracle.sample(rows, 2, state)[0], 0)
        tied = [(7, -8)] * 4019
        self.assertEqual(oracle.sample(tied, 0, state), (0, state))
        self.assertEqual(oracle.weights(tied, 1), [1 << 30] * 4019)
        with self.assertRaises(ValueError):
            oracle.sample(tied, 4, state)
        with self.assertRaises(ValueError):
            oracle.aligned_rows([(0, -8)] + [(0, -11)] * 4018)


if __name__ == '__main__':
    unittest.main()
