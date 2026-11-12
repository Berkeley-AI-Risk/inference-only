"""Offline controls for the finite MoE trace checker; no simulator or model work."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


DEMO = Path(__file__).resolve().parents[1] / 'demos/tlm26-moe'
CHECKER = DEMO / 'scripts/check_dispatch.py'
spec = importlib.util.spec_from_file_location('tlm26_dispatch_checker', CHECKER)
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


def fixture():
    physical = json.loads((DEMO / 'evidence/physical.json').read_bytes())
    wire = [checker.frame(row['tx'], 0xA5) + checker.frame(row['rx'], 0x5A)
            for row in physical['honest'][:36]]
    records = []
    lines = ['boot_writes 98304 page_acks 768 changed_bytes 0']
    reads = 0
    for history in range(2):
        lines.extend([f'MOE_CLEAR {history}', '2 0 130 0 1 ' + str(reads)])
        for position in range(17):
            reply = wire[history * 18 + position + 1]
            token = reply[1] if position < 5 else reply[3]
            for layer in range(5):
                for rank in range(2):
                    expert = (position + layer + rank + history) % 8
                    address = 32832 + layer * 307840 + 12928 + expert * 36864
                    record = [history, position, token, layer, rank, expert, address]
                    records.append(record)
                    suffix = ' '.join(map(str, record))
                    lines.extend(['MOE_START ' + suffix, 'MOE_WEIGHT ' + suffix])
            reads += 1
            lines.append(' '.join(map(str, reply + [1, reads])))
    expected = {
        'bitstream_sha256': physical['bitstream_sha256'],
        'source_checkpoint_sha256': physical['source_checkpoint_sha256'],
        'staged_model_sha256': physical['boot']['honest']['sha256'],
        'expected_dispatches': records,
        'consumed_tokens_34_layer_by_expert_counts': [
            [sum(row[3] == layer and row[5] == expert for row in records) for expert in range(8)]
            for layer in range(5)],
    }
    return lines, expected, physical


class DispatchTests(unittest.TestCase):
    def setUp(self):
        self.lines, self.expected, self.physical = fixture()

    def check(self, lines=None, expected=None, physical=None):
        return checker.check('\n'.join(self.lines if lines is None else lines) + '\n',
                             self.expected if expected is None else expected,
                             self.physical if physical is None else physical)

    def test_complete_control(self):
        result = self.check()
        self.assertEqual(result['trace_lines_checked'], 719)
        self.assertEqual(result['verified_launches'], 340)
        self.assertEqual(result['verified_UART_replies'], 36)
        self.assertEqual(result['generated_tokens_matching_board'], 24)
        self.assertFalse(result['board_routing_directly_observed'])

    def test_recorded_trace(self):
        folder = DEMO / 'evidence/expert-dispatch'
        self.assertTrue((folder / 'stdout.log').is_file(), 'Published recorded trace is required')
        result = checker.check((folder / 'stdout.log').read_text(),
                               json.loads((folder / 'expected.json').read_bytes()), self.physical)
        self.assertEqual(result['distinct_experts_per_layer'], [8] * 5)

    def test_wrong_expert_rank_or_address(self):
        for field in (5, 6, 7):
            with self.subTest(field=field):
                lines = self.lines.copy()
                words = lines[3].split()
                words[field] = str(int(words[field]) + 1)
                lines[3] = ' '.join(words)
                with self.assertRaises(checker.CheckError):
                    self.check(lines)

    def test_missing_acceptance(self):
        with self.assertRaises(checker.CheckError):
            self.check(self.lines[:4] + self.lines[5:])

    def test_clear_or_uart_moved_across_dispatch(self):
        for index in (1, 2, 23):
            with self.subTest(index=index):
                lines = self.lines.copy()
                event = lines.pop(index)
                lines.insert(index + 2, event)
                with self.assertRaises(checker.CheckError):
                    self.check(lines)

    def test_truncated_extra_or_blank_line(self):
        for lines in (self.lines[:-1], self.lines + [self.lines[-1]], self.lines + ['']):
            with self.subTest(lines=len(lines)):
                with self.assertRaises(checker.CheckError):
                    self.check(lines)

    def test_crc_and_physical_identities(self):
        physical = copy.deepcopy(self.physical)
        raw = bytearray.fromhex(physical['honest'][0]['tx'])
        raw[-1] ^= 1
        physical['honest'][0]['tx'] = raw.hex()
        with self.assertRaises(checker.CheckError):
            self.check(physical=physical)
        for field in ('bitstream_sha256', 'source_checkpoint_sha256', 'staged_model_sha256'):
            expected = copy.deepcopy(self.expected)
            expected[field] = '0' * 64
            with self.subTest(field=field), self.assertRaises(checker.CheckError):
                self.check(expected=expected)

    def test_reference_layout_and_order(self):
        for field in (3, 4, 5, 6):
            expected = copy.deepcopy(self.expected)
            expected['expected_dispatches'][0][field] += 1
            with self.subTest(field=field), self.assertRaises(checker.CheckError):
                self.check(expected=expected)

    def test_nonpositive_cycles_and_decreasing_reads(self):
        for row, field, value in ((2, 4, 0), (44, 5, 0)):
            lines = self.lines.copy()
            words = lines[row].split()
            words[field] = str(value)
            lines[row] = ' '.join(words)
            with self.subTest(row=row), self.assertRaises(checker.CheckError):
                self.check(lines)

    def test_cli_explicit_inputs_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            trace, expected, physical, output = [folder / name for name in
                                                ('trace.log', 'expected.json', 'physical.json', 'out.json')]
            trace.write_text('\n'.join(self.lines) + '\n')
            expected.write_text(json.dumps(self.expected))
            physical.write_text(json.dumps(self.physical))
            command = [sys.executable, '-I', '-S', '-B', str(CHECKER), '--trace', str(trace),
                       '--expected', str(expected), '--physical', str(physical), '--output', str(output)]
            result = subprocess.run(command, cwd=folder, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(output.read_text())['passed'])
            before = output.read_bytes()
            second = subprocess.run(command, cwd=folder, capture_output=True, text=True)
            self.assertNotEqual(second.returncode, 0)
            self.assertEqual(output.read_bytes(), before)

    def test_optimized_modes_refuse_before_inputs(self):
        for mode in ('-O', '-OO'):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as folder:
                result = subprocess.run([sys.executable, mode, '-I', '-S', '-B', str(CHECKER)],
                                        cwd=folder, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('No verification performed', result.stderr)
                self.assertEqual(result.stdout, '')
                self.assertNotIn('Traceback', result.stderr)


if __name__ == '__main__':
    unittest.main()
