"""Exercise actual recovery control flow with injected failures; no hardware."""
from pathlib import Path
import hashlib, importlib.util, json, tempfile, unittest
from unittest.mock import patch

W = Path(__file__).resolve().parents[1]
R = W.parent / 'sawic-model-replacement-20261105'
spec = importlib.util.spec_from_file_location('replacement_runner', W / 'integration/run_model_replacement.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
A = (R / 'model-A/array.bin').read_bytes()
B = (R / 'model-B/array.bin').read_bytes()

class RecoveryTests(unittest.TestCase):
    def test_recorded_early_CLEAR_is_blocked_until_grant_settles(self):
        home = {'time': 0, 'grant_sent_time': .47784712491557, 'decision': 'approved'}
        self.assertFalse(m.safe_command_window(home, .5008342498913407))
        self.assertFalse(m.safe_command_window(home, .97784712491556))
        self.assertTrue(m.safe_command_window(home, .97784712491557))

    def test_slow_grant_never_extends_the_renewal_guard(self):
        home = {'time': 0, 'grant_sent_time': 1, 'decision': 'approved'}
        self.assertFalse(m.safe_command_window(home, 1.49))
        self.assertTrue(m.safe_command_window(home, 1.5))
        self.assertFalse(m.safe_command_window(home, 4.5))
        self.assertFalse(m.safe_command_window(dict(home, decision='denied'), 2))

    def make(self, root, memory, touched=True, verified=False):
        c = object.__new__(m.Campaign)
        c.out = root
        c.flash_touched, c.flash_start_verified, c.sram_touched = touched, verified, True
        c.calls = []
        c.close = lambda: c.calls.append('close')
        c.set_phase = lambda name: c.calls.append(name)
        def install(direction, name):
            c.calls.append('restore-blocks')
            self.assertEqual(direction, 'B-to-A')
            for row in m.read(R / direction / 'BLOCK-PLAN.json')['writes']:
                data = (R / direction / row['file']).read_bytes()
                memory[row['address']:row['address'] + len(data)] = data
        def full_read(label, name):
            c.calls.append('verify-whole-array')
            self.assertEqual(label, 'A')
            self.assertEqual(memory, A)
            c.flash_start_verified = True
        c.install, c.full_read = install, full_read
        c.load = lambda image, name: c.calls.append('restore-sram')
        c.run = lambda cmd, name: c.calls.append('verify-baseline')
        return c

    def invoke(self, c):
        # Only the actual recovery method is exercised; device reset and time
        # are replaced before it runs. All transport callbacks are in-memory.
        with patch.object(m, 'reset_known_debugger', return_value={'mock': True}), patch.object(m.time, 'sleep'):
            c.restore()

    def test_no_flash_write_does_not_invoke_flash_recovery(self):
        with tempfile.TemporaryDirectory() as d:
            c = self.make(Path(d), bytearray(A), touched=False, verified=True)
            self.invoke(c)
            self.assertNotIn('restore-blocks', c.calls)
            self.assertEqual(c.calls[-2:], ['restore-sram', 'verify-baseline'])

    def test_partial_first_block_is_recovered_before_sram(self):
        with tempfile.TemporaryDirectory() as d:
            memory = bytearray(A)
            memory[0xe80000:0xe90000] = b'\xff' * 65536
            memory[0xe80000:0xe81000] = B[0xe80000:0xe81000]
            self.assertNotEqual(memory, A)
            c = self.make(Path(d), memory)
            self.invoke(c)
            self.assertEqual(memory, A)
            self.assertLess(c.calls.index('verify-whole-array'), c.calls.index('restore-sram'))

    def test_complete_B_is_recovered_exactly(self):
        with tempfile.TemporaryDirectory() as d:
            memory = bytearray(B)
            c = self.make(Path(d), memory)
            self.invoke(c)
            self.assertEqual(memory, A)
            self.assertEqual(m.read(Path(d) / 'RESTORED.json')['result'], 'PASS')

    def test_already_verified_A_is_not_erased_again(self):
        with tempfile.TemporaryDirectory() as d:
            c = self.make(Path(d), bytearray(A), verified=True)
            self.invoke(c)
            self.assertNotIn('restore-blocks', c.calls)
            self.assertNotIn('verify-whole-array', c.calls)

    def test_serial_cleanup_error_cannot_skip_flash_recovery(self):
        with tempfile.TemporaryDirectory() as d:
            c = self.make(Path(d), bytearray(B))
            def fail():
                raise OSError('injected descriptor close failure')
            c.close = fail
            self.invoke(c)
            self.assertIn('verify-whole-array', c.calls)
            self.assertTrue((Path(d) / 'SERIAL-CLEANUP-FAILURE.json').is_file())

    def test_flash_write_failure_does_not_claim_restoration(self):
        with tempfile.TemporaryDirectory() as d:
            c = self.make(Path(d), bytearray(B))
            def fail(*args):
                raise RuntimeError('injected restore write failure')
            c.install = fail
            with self.assertRaises(RuntimeError):
                self.invoke(c)
            self.assertNotIn('restore-sram', c.calls)
            self.assertFalse((Path(d) / 'RESTORED.json').exists())

    def test_unverified_array_cannot_enable_original_inference(self):
        with tempfile.TemporaryDirectory() as d:
            c = self.make(Path(d), bytearray(B))
            def fail(*args):
                raise RuntimeError('injected independent readback mismatch')
            c.full_read = fail
            with self.assertRaises(RuntimeError):
                self.invoke(c)
            self.assertNotIn('restore-sram', c.calls)
            self.assertFalse((Path(d) / 'RESTORED.json').exists())

if __name__ == '__main__':
    # The read used only for the final recovery hash is also replaced with a
    # synthetic file: no live capture, board lock, USB or UART is accessed.
    with tempfile.TemporaryDirectory() as tmp:
        fake = Path(tmp)
        (fake / 'backups').mkdir()
        (fake / 'backups/read1.bin').write_bytes(A)
        with patch.object(m, 'R', fake):
            # Block-file reads in the in-memory callback use this module's R.
            result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(RecoveryTests))
    out = R / 'harness-checks-settle-v1'
    out.mkdir(exist_ok=False)
    (out / 'RESULT.json').write_text(json.dumps({'result': 'PASS' if result.wasSuccessful() else 'FAIL', 'tests': result.testsRun,
        'hardware_access': False, 'runner_sha256': hashlib.sha256((W / 'integration/run_model_replacement.py').read_bytes()).hexdigest(),
        'test_source_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}, indent=2) + '\n')
    raise SystemExit(not result.wasSuccessful())
