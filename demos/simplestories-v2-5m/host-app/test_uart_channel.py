"""Offline byte/pipe tests; never opens a physical UART."""
import os
import unittest
from pathlib import Path

import fpga_backend
from uart_channel import StrictChannel


class Session:
    def __init__(self, fd): self.fd, self.sent = fd, []
    def _send(self, frame): self.sent.append(frame)


class ChannelTests(unittest.TestCase):
    def setUp(self):
        self.reader_fd, self.writer_fd = os.pipe()
        self.session = Session(self.reader_fd)
        self.events = []
        self.client = fpga_backend.LiveUART(self.events.append).client
        self.channel = StrictChannel(self.session, self.client, self.events.append)

    def tearDown(self):
        os.close(self.reader_fd); os.close(self.writer_fd)

    def test_complete_and_fragmented_pipe_frames(self):
        frame = self.client.response_frame(0x81, 200)
        for split in range(5):
            self.channel.pending.extend(frame[:split])
            os.write(self.writer_fd, frame[split:])
            self.assertEqual(self.channel.next(0.1)['token'], 200)
            self.assertFalse(self.channel.pending)
        self.assertTrue(any(e['event'] == 'raw_chunk' for e in self.events))

    def test_all_single_bit_errors_rejected(self):
        frame = self.client.response_frame(0x81, 200)
        for bit in range(40):
            bad = bytearray(frame); bad[bit//8] ^= 1 << (bit%8)
            self.channel.pending = bad
            with self.subTest(bit=bit), self.assertRaises((ValueError, RuntimeError)):
                self.channel.next(0.1)

    def test_canonical_tokens_and_no_unsolicited_send(self):
        for kind, token in ((0x80, 1), (0x82, 1), (0x81, 4019)):
            self.channel.pending = bytearray(self.client.response_frame(kind, token))
            with self.assertRaises(RuntimeError): self.channel.next(0.1)
        frame = self.client.response_frame(0x81, 200)
        self.channel.pending = bytearray(frame + frame)
        self.assertEqual(self.channel.next(0.1)['token'], 200)
        with self.assertRaises(AssertionError):
            self.channel.send(self.client.request_frame('step'), 'unexpected')
        self.assertFalse(self.session.sent)

    def test_silence_and_partial_frame_timeout(self):
        self.assertIsNone(self.channel.next(0.001))
        self.channel.pending.extend(b'\x5a\x81')
        self.assertIsNone(self.channel.next(0.001))
        self.assertEqual(bytes(self.channel.pending), b'\x5a\x81')


if __name__ == '__main__': unittest.main(verbosity=2)
