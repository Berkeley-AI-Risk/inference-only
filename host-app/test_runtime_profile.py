"""Offline deployment/profile tests. Every device and board response is synthetic."""
import copy
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

import fpga_backend
import qualify_board
import runtime_profile as profile


class QuietChannel:
    pending = bytearray()
    def next(self, timeout): return None


class SyntheticQualificationLink:
    def __init__(self, observe, deployment, tokens=(200, 15, 103, 157)):
        self.tokens = iter(tokens)
        self.calls = []
        self.closed = False
        self.channel = QuietChannel()
    def __enter__(self): return self
    def __exit__(self, *args): self.closed = True
    def command(self, operation, token=0):
        self.calls.append((operation, token))
        return next(self.tokens) if operation == 'step' else None


class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='fpga-profile-offline-')
        self.root = Path(self.directory.name)
        self.active = self.root / 'local/board-profile.json'
        self.image = self.root / 'build/project/impl/pnr/shared_product.fs'
        self.image_data = b'OFFLINE TEST FIXTURE, NOT AN FPGA CONFIGURATION'
        profile.private_write(self.image, self.image_data)
        self.receipt = self.root / 'build/BUILD.json'
        self.build = {'schema': profile.BUILD_SCHEMA, 'flow_completed': True,
            'source_inputs_verified': True, 'source_inputs_unchanged': True,
            'hardware_inputs_sha256': profile.HARDWARE_INPUTS_SHA256,
            'image_relative_path': 'project/impl/pnr/shared_product.fs',
            'image_sha256': profile.sha(self.image_data), 'timing_qualified': False}
        profile.private_write(self.receipt, profile.encode(self.build))
        self.identity = {'path': '/dev/explicitly-offline-fixture', 'rdev': 123, 'stat_dev': 456, 'inode': 789}
        self.info = type('Device', (), {'st_mode': stat.S_IFCHR, 'st_rdev': 123, 'st_dev': 456, 'st_ino': 789})()
        self.links = []
        self.mocks = [patch.object(profile, 'PROFILE', self.active),
            patch.object(qualify_board, 'app_is_running', return_value=False),
            patch.object(profile, 'check_device', return_value=self.identity)]
        for p in self.mocks: p.start()

    def tearDown(self):
        for p in reversed(self.mocks): p.stop()
        self.directory.cleanup()

    def link(self, observe, deployment):
        result = SyntheticQualificationLink(observe, deployment)
        self.links.append(result)
        return result

    def qualify(self, **kwargs):
        return qualify_board.qualify(self.receipt, self.identity['path'], confirm_loaded=True,
            acknowledge_timing=True, link_factory=self.link, **kwargs)

    def rewrite(self, path, value): path.write_bytes(profile.encode(value))

    def test_real_hardware_inventory_identity(self):
        self.assertEqual(len(profile.hardware_inputs()), 90)
        self.assertEqual(len([n for n in profile.hardware_inputs() if n.startswith('project/official/')]), 4)

    def test_protected_hardware_inventory_identity(self):
        selected = profile.hardware_inputs('kv-protected')
        self.assertEqual(len(selected), 93)
        self.assertEqual(len([name for name in selected if name.startswith('project/official/')]), 4)
        self.assertIn('project/kv_integrity_guard.sv', selected)

    def test_protected_profile_qualifies_and_retains_variant(self):
        self.build.update(variant='kv-protected',
            hardware_inputs_sha256=profile.VARIANTS['kv-protected']['inputs_sha256'])
        self.rewrite(self.receipt, self.build)
        record = self.qualify()
        self.assertEqual(record['variant'], 'kv-protected')
        self.assertEqual(profile.load_checked(), record)
        self.assertEqual(profile.configured_variant(), 'K/V integrity protection')

    def test_cross_variant_receipt_rejected_before_uart(self):
        for variant, digest in [('kv-protected', profile.HARDWARE_INPUTS_SHA256),
                ('baseline', profile.VARIANTS['kv-protected']['inputs_sha256']),
                ('unknown', profile.HARDWARE_INPUTS_SHA256)]:
            with self.subTest(variant=variant):
                self.rewrite(self.receipt, dict(self.build, variant=variant, hardware_inputs_sha256=digest))
                with self.assertRaises(ValueError): self.qualify()
        self.assertFalse(self.links)

    def test_changed_profile_variant_rejected(self):
        record = self.qualify()
        record['variant'] = 'kv-protected'
        self.rewrite(self.active, record)
        with self.assertRaises(ValueError): profile.load_checked()
        self.assertIsNone(profile.configured_variant())

    def test_success_and_rebuilt_image_identity(self):
        record = self.qualify()
        self.assertNotEqual(record['image_sha256'], fpga_backend.IMAGE_SHA)
        self.assertEqual(profile.load_checked(), record)
        self.assertEqual(profile.configured_port(), self.identity['path'])
        self.assertEqual(self.links[0].calls,
            [('clear', 0), ('append', 378)] + [('step', 0)] * 4 + [('clear', 0)])
        self.assertTrue(self.links[0].closed)
        self.assertEqual(stat.S_IMODE(self.active.stat().st_mode), 0o600)
        self.assertTrue(record['hardware_configuration_not_independently_attested'])

    def test_missing_profile_does_not_open_hardware(self):
        self.assertIsNone(profile.configured_port())
        with patch('fpga_backend.pinned_module') as import_helper:
            with self.assertRaises(FileNotFoundError): profile.load_checked()
            import_helper.assert_not_called()
        self.assertFalse(self.links)

    def test_explicit_operator_confirmations_before_uart(self):
        for confirmed, acknowledged in ((False, True), (True, False)):
            with self.subTest(confirmed=confirmed), self.assertRaises(ValueError):
                qualify_board.qualify(self.receipt, self.identity['path'], confirm_loaded=confirmed,
                    acknowledge_timing=acknowledged, link_factory=self.link)
        self.assertFalse(self.links)

    def test_running_app_blocks_qualification(self):
        with patch.object(qualify_board, 'app_is_running', return_value=True):
            with self.assertRaises(RuntimeError): self.qualify()
        self.assertFalse(self.links)

    def test_incomplete_wrong_source_and_image_builds_rejected(self):
        for key, value in (('flow_completed', False), ('source_inputs_unchanged', False),
                           ('hardware_inputs_sha256', '0' * 64), ('image_sha256', '1' * 64),
                           ('image_relative_path', '../wrong.fs')):
            with self.subTest(key=key):
                self.rewrite(self.receipt, dict(self.build, **{key: value}))
                with self.assertRaises(ValueError): self.qualify()
        self.assertFalse(self.links)

    def test_changed_bitstream_and_receipt_invalidate_profile(self):
        self.qualify()
        self.image.write_bytes(b'CHANGED OFFLINE FIXTURE')
        with self.assertRaises(ValueError): profile.load_checked()
        self.image.write_bytes(self.image_data)
        self.rewrite(self.receipt, dict(self.build, extra='changed receipt'))
        with self.assertRaises(ValueError): profile.load_checked()

    def test_realistic_text_bitstream_size_is_accepted_with_matching_hash(self):
        # Exact byte count of the selected real .fs, but entirely synthetic data.
        image = b'0' * 41_329_247
        self.assertGreater(len(image), 32 * 1024 * 1024)
        self.image.write_bytes(image)
        self.rewrite(self.receipt, dict(self.build, image_sha256=profile.sha(image)))
        result = profile.check_build(self.receipt)
        self.assertEqual(result['image_sha256'], profile.sha(image))
        self.assertFalse(result['timing_qualified'] or self.links)

    def test_oversize_bitstream_remains_rejected_before_uart(self):
        with self.image.open('wb') as out:
            out.truncate(profile.MAX_BITSTREAM_BYTES + 1)
        with self.assertRaisesRegex(ValueError, 'bounded regular file'):
            self.qualify()
        self.assertFalse(self.links)

    def test_changed_qualification_log_invalidate_profile(self):
        record = self.qualify()
        Path(record['qualification_log_path']).write_text('changed\n')
        with self.assertRaises(ValueError): profile.load_checked()

    def test_incomplete_sequence_rejected_even_with_updated_log_hash(self):
        record = self.qualify()
        path = Path(record['qualification_log_path'])
        rows = [json.loads(x) for x in path.read_text().splitlines()]
        rows = [r for r in rows if r.get('event') != 'qualification_complete']
        path.write_bytes(b''.join(json.dumps(r).encode() + b'\n' for r in rows))
        record['qualification_log_sha256'] = profile.sha(path.read_bytes())
        self.rewrite(self.active, record)
        with self.assertRaises(ValueError): profile.load_checked()

    def test_wrong_token_fails_without_cleanup_retry_or_profile(self):
        def wrong(observe, deployment):
            value = SyntheticQualificationLink(observe, deployment, tokens=(201,))
            self.links.append(value); return value
        with self.assertRaises(fpga_backend.BoardError):
            qualify_board.qualify(self.receipt, self.identity['path'], confirm_loaded=True,
                acknowledge_timing=True, link_factory=wrong)
        self.assertEqual(self.links[0].calls, [('clear', 0), ('append', 378), ('step', 0)])
        self.assertTrue(self.links[0].closed)
        self.assertFalse(self.active.exists())

    def test_existing_profile_no_clobber_and_recoverable_requalification(self):
        previous = self.qualify()
        old_bytes = self.active.read_bytes()
        with self.assertRaises(FileExistsError): self.qualify()
        self.assertEqual(len(self.links), 1)
        self.qualify(replace_profile=True)
        backups = list(self.active.parent.glob('qualification-*/previous-board-profile.json'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_bytes(), old_bytes)
        self.assertEqual(profile.load_checked()['known_answer'], previous['known_answer'])

    def test_symlink_build_and_profile_refused(self):
        linked = self.root / 'linked-receipt.json'
        linked.symlink_to(self.receipt)
        with self.assertRaises(OSError): profile.check_build(linked)
        self.active.parent.mkdir()
        self.active.symlink_to(self.receipt)
        with self.assertRaises(OSError): profile.load_checked()

    def test_device_identity_and_descriptor_checks(self):
        # The production checker is exercised with stat results, never a real tty.
        checker = self.mocks[-1]; checker.stop()
        try:
            with patch.object(profile.os, 'stat', return_value=self.info):
                self.assertEqual(profile.check_device(self.identity['path']), self.identity)
                with self.assertRaises(OSError): profile.check_device(self.identity['path'], dict(self.identity, inode=99))
                with self.assertRaises(ValueError): profile.check_device('')
            with patch.object(profile.os, 'fstat', return_value=self.info):
                profile.check_open_device(17, self.identity)
                with self.assertRaises(OSError): profile.check_open_device(17, dict(self.identity, rdev=99))
        finally: checker.start()

    def test_device_swap_after_open_closes_without_commands(self):
        self.qualify()
        link = fpga_backend.LiveUART(lambda event: None)
        class FakeSession:
            def __init__(self, *args, **kwargs): self.fd = 17; self.closed = False
            def open(self): return self
            def close(self): self.closed = True
        with patch.object(link.client, 'TokenMachineSession', FakeSession), \
             patch.object(profile, 'check_open_device', side_effect=OSError('synthetic swapped device')):
            with self.assertRaises(fpga_backend.BoardError): link.__enter__()
        self.assertTrue(link.session.closed)
        self.assertIsNone(link.channel)


if __name__ == '__main__': unittest.main(verbosity=2)
