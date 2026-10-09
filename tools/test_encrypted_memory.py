"""Offline additive-variant checks; never open a device or run vendor tools."""
import hashlib
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load(name,path):
    spec = importlib.util.spec_from_file_location(name,path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


history = load('encrypted_history_test',ROOT/'tools/encrypted_memory_history.py')
crypto = load('encrypted_crypto_test',ROOT/'tools/encrypt_model_image.py')
flash = load('encrypted_flash_test',ROOT/'tools/check_encrypted_flash.py')
checker = load('encrypted_checker_test',ROOT/'tools/check_encrypted_memory.py')


class EncryptedMemoryTests(unittest.TestCase):
    def test_third_profile_uses_unchanged_qualification_with_mocked_device(self):
        sys.path.insert(0,str(ROOT/'host-app'))
        try:
            import runtime_profile as profile
            import qualify_board
            from test_runtime_profile import ProfileTests
            # Reuse the existing entirely synthetic channel, device identity
            # and temporary profile fixture; no serial port or socket opens.
            fixture=ProfileTests();fixture.setUp()
            try:
                fixture.build.update(variant='encrypted-memory',
                    hardware_inputs_sha256=profile.VARIANTS['encrypted-memory']['inputs_sha256'])
                fixture.rewrite(fixture.receipt,fixture.build)
                with self.assertRaises(ValueError):
                    qualify_board.qualify(fixture.receipt,fixture.identity['path'],confirm_loaded=True,
                        acknowledge_timing=False,link_factory=fixture.link)
                self.assertFalse(fixture.links)
                record=fixture.qualify()
                self.assertEqual(record['variant'],'encrypted-memory')
                self.assertEqual(profile.load_checked(),record)
                self.assertEqual(profile.configured_variant(),'Encrypted external memory (public test keys)')
                self.assertEqual(fixture.links[0].calls,[('clear',0),('append',378)]+[('step',0)]*4+[('clear',0)])
                self.assertTrue(fixture.links[0].closed)
                self.assertEqual(len(profile.hardware_inputs('encrypted-memory')),100)
            finally:fixture.tearDown()
        finally:sys.path.pop(0)

    def test_initial_board_scope_and_timing_cannot_be_relabelled(self):
        data=json.loads((ROOT/'evidence/encrypted-memory/initial-board.json').read_bytes())
        self.assertEqual(checker.check_initial_board(data),6)
        for field in ('full_context_board_test','physical_secrecy_qualified','timing_qualified','new_catalog_or_browser_test'):
            bad=copy.deepcopy(data);bad[field]=True
            with self.assertRaises(ValueError):checker.check_initial_board(bad)
        bad=copy.deepcopy(data);bad['generated_tokens'][0]=201
        with self.assertRaises(ValueError):checker.check_initial_board(bad)
        bad=copy.deepcopy(data);bad['encrypted_step_seconds'][0]=0.1
        with self.assertRaises(ValueError):checker.check_initial_board(bad)
        bad=copy.deepcopy(data);bad['encrypted_step_seconds'][0]=float('nan')
        with self.assertRaises(ValueError):checker.check_initial_board(bad)

    def test_shipped_source_and_model_association(self):
        result = checker.check(ROOT)
        self.assertTrue(result['passed'])
        self.assertEqual(result['enabled_rtl'],88)
        self.assertEqual(result['page_digests_checked'],1774)
        self.assertFalse(result['timing_qualified'])

    def test_exact_catalog_inverse(self):
        raw = (ROOT/history.SOURCE).read_bytes()
        restored = history.previous_bytes(ROOT,history.SOURCE,raw)
        self.assertEqual(hashlib.sha256(restored).hexdigest(),history.BEFORE)
        self.assertNotEqual(raw,restored)
        self.assertEqual(history.previous_bytes(ROOT,'host-app/token_machine_uart.py',b'unchanged'),b'unchanged')

    def test_catalog_mutations_rejected_even_with_rehashed_record(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            for name in (history.SOURCE,history.INVENTORY,'evidence/encrypted-memory/catalog-revision.json',
                         'tools/speed_release_history.py','evidence/speed-2026-10-02/source-revision.json'):
                (target/name).parent.mkdir(parents=True,exist_ok=True)
                shutil.copyfile(ROOT/name,target/name)
            raw = (target/history.SOURCE).read_bytes()
            record_path = target/'evidence/encrypted-memory/catalog-revision.json'
            original = record_path.read_bytes()
            for bad in (raw+b'\n',raw.replace(b'input_files\': 100',b'input_files\': 99'),
                        raw.replace(b'EXPECTED_TOKENS = [200',b'EXPECTED_TOKENS = [201')):
                record = json.loads(original); record['after_sha256'] = history.sha(bad)
                record_path.write_text(json.dumps(record))
                with self.assertRaises(ValueError): history.previous_bytes(target,history.SOURCE,bad)
            record_path.write_bytes(original)
            inventory = json.loads((target/history.INVENTORY).read_bytes())
            inventory[next(iter(inventory))] = '0'*64
            new = json.dumps(inventory).encode(); (target/history.INVENTORY).write_bytes(new)
            record = json.loads(original); record['inventory_sha256'] = history.sha(new)
            record_path.write_text(json.dumps(record))
            with self.assertRaises(ValueError): history.previous_bytes(target,history.SOURCE,raw)

    def test_public_keys_are_explicitly_nonsecret(self):
        keys = json.loads((ROOT/'variants/encrypted-memory/PUBLIC-TEST-KEYS.json').read_bytes())
        self.assertIs(keys['secret'],False)
        self.assertEqual(keys['weight_aes256_key_hex'],crypto.KEY)
        self.assertEqual(keys['weight_ctr_nonce_hex'],crypto.NONCE)
        self.assertIs(keys['otp_fuse_security_lock_programming'],False)

    def test_ctr_geometry(self):
        self.assertEqual(crypto.SIZE % 16,0)
        self.assertLess(crypto.SIZE//16,2**32)
        self.assertEqual(len(bytes.fromhex(crypto.NONCE+'00000000')),16)
        self.assertEqual(divmod(crypto.SIZE,4096),(1773,3776))

    def test_openssl_exact_ciphertext_and_decrypt(self):
        executable = shutil.which('openssl')
        if not executable: self.skipTest('OpenSSL unavailable; explicit reproduction command remains required')
        self.assertEqual(crypto.sha(crypto.reproduce(ROOT,executable)),crypto.CIPHER_SHA)

    def test_flash_exact_bytes_and_rejections(self):
        model = (ROOT/'assets/board1-encrypted-model2048.bin').read_bytes()
        plain = flash.plain
        full = b'\xff'*plain.BASE + model + b'\xff'*(plain.CAPACITY-plain.BASE-len(model))
        self.assertEqual(plain.sha(full),flash.FLASH_SHA)
        with tempfile.TemporaryDirectory() as directory:
            readback = Path(directory)/'readback.bin'; readback.write_bytes(full)
            self.assertTrue(flash.check_layout(ROOT/'assets/board1-encrypted-model2048.bin',readback)['passed'])
            with self.assertRaises(ValueError): flash.check_layout(ROOT/'assets/board1-real-semantic-image2048.bin',readback)
            for position in (0,plain.BASE,plain.BASE+len(model),plain.CAPACITY-1):
                altered = bytearray(full); altered[position] ^= 1; readback.write_bytes(altered)
                with self.assertRaises(ValueError): flash.check_layout(ROOT/'assets/board1-encrypted-model2048.bin',readback)
            readback.write_bytes(full[:-1])
            with self.assertRaises(ValueError): flash.check_layout(ROOT/'assets/board1-encrypted-model2048.bin',readback)


if __name__ == '__main__': unittest.main()
