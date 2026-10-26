"""Offline session-lifecycle and idle-noise checks; no physical UART."""
import tempfile
import threading
import unittest
from unittest.mock import patch

import fpga_backend as backend
from test_fpga_backend import FakeLink


class ReusableLink(FakeLink):
    def __init__(self, **kwargs):
        super().__init__(output=(200,) * 20, **kwargs)
        self.resumes = 0
        self.resume_error = False

    def resume(self, observe):
        self.resumes += 1
        if self.resume_error:
            raise backend.BoardError('synthetic late bytes')


class PersistentTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='fpga-reuse-offline-')
        self.links = []
        def factory(observe):
            link = ReusableLink()
            self.links.append(link)
            return link
        self.controller = backend.Controller(link_factory=factory, logs=self.folder.name,
                                             keep_connection=True)

    def tearDown(self):
        self.controller.disconnect()
        self.folder.cleanup()

    def run_once(self, owner='one'):
        self.controller.start(owner, 'around', 1)
        self.controller.thread.join(3)
        self.assertFalse(self.controller.busy())
        return self.controller.snapshot(owner)

    def test_reuse_only_after_clear_and_explicit_disconnect(self):
        self.assertEqual(self.run_once().state, 'complete')
        self.assertTrue(self.controller.connection_retained())
        self.assertFalse(self.links[0].closed)
        self.assertEqual(self.links[0].calls[-1], ('clear', 0))
        self.assertEqual(self.run_once('two').generated, [200])
        self.assertEqual(len(self.links), 1)
        self.assertEqual(self.links[0].resumes, 1)
        self.assertEqual(self.controller.snapshot('one').prompt, '')
        self.controller.disconnect()
        self.assertTrue(self.links[0].closed)
        self.assertFalse(self.controller.connection_retained())
        self.assertEqual(self.run_once().state, 'complete')
        self.assertEqual(len(self.links), 2)

    def test_idle_error_closes_without_command_or_retry(self):
        self.run_once()
        link = self.links[0]
        count = len(link.calls)
        link.resume_error = True
        self.assertEqual(self.run_once().state, 'error')
        self.assertEqual(len(link.calls), count)
        self.assertTrue(link.closed)
        self.assertTrue(self.controller.needs_board_check)
        with self.assertRaises(RuntimeError):
            self.controller.start('one', 'around', 1)

    def test_failed_final_clear_is_never_retained(self):
        self.run_once()
        self.links[0].fail = 'clear'
        self.assertEqual(self.run_once().state, 'error')
        self.assertFalse(self.controller.connection_retained())
        self.assertTrue(self.links[0].closed)

    def test_stop_drains_then_releases_and_blocks_disconnect_while_busy(self):
        self.run_once()
        link = self.links[0]
        gate = threading.Event()
        link.gate = ('step', gate)
        self.controller.start('one', 'around', 4)
        self.assertTrue(link.entered.wait(1))
        with self.assertRaises(RuntimeError): self.controller.disconnect()
        self.controller.stop('one')
        gate.set(); self.controller.thread.join(3)
        self.assertEqual(self.controller.result.state, 'stopped')
        self.assertTrue(link.closed)
        self.assertFalse(self.controller.connection_retained())
        self.assertEqual(link.calls[-1], ('clear', 0))

    def test_live_resume_checks_profile_fd_and_idle_bytes(self):
        class Session: fd = 17
        class Channel: pending = bytearray()
        profile = {'device': {'path': '/dev/offline'}, 'image_sha256': 'fixture'}
        for label in ('clean', 'pending', 'readable', 'profile', 'fd', 'closed'):
            with self.subTest(label=label):
                link = backend.LiveUART(lambda row: None)
                link.session = Session(); link.channel = Channel(); link.profile = profile
                link.channel.pending = bytearray(b'\x5a') if label == 'pending' else bytearray()
                observed = []
                with patch.object(link, '_deployment', return_value=({} if label == 'profile' else profile)), \
                     patch('runtime_profile.check_open_device', side_effect=(OSError('fd') if label == 'fd' else None)), \
                     patch('fpga_backend.select.select', return_value=([17] if label == 'readable' else [], [], []),
                           side_effect=(OSError('closed') if label == 'closed' else None)):
                    if label == 'clean':
                        link.resume(observed.append)
                        self.assertEqual(observed[0]['event'], 'connection_reused')
                    else:
                        with self.assertRaises(backend.BoardError): link.resume(observed.append)


if __name__ == '__main__': unittest.main()
