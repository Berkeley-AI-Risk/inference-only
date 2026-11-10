"""Assertion-based MoE frontdoors must refuse optimized execution before work."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

DEMO = Path(__file__).resolve().parents[1] / 'demos/tlm26-moe'
SCRIPTS = ('checkpoint_reference.py', 'generate_decoder.py', 'integer_reference.py',
           'layout.py', 'reproduce.py', 'verify_board_receipt.py')


class AssertionModeTests(unittest.TestCase):
    pass


def refusal_case(script, mode):
    def check(self):
        # No model, dependencies, generated files or board are available here.
        with tempfile.TemporaryDirectory() as work:
            result = subprocess.run(
                [sys.executable, mode, '-I', '-S', '-B', str(DEMO / 'scripts' / script)],
                cwd=work, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Assertion checks are required', result.stderr)
        self.assertIn('No verification performed', result.stderr)
        self.assertEqual(result.stdout, '')
        self.assertNotIn('Traceback', result.stderr)
    return check


for script in SCRIPTS:
    for mode in ('-O', '-OO'):
        setattr(AssertionModeTests, 'test_' + Path(script).stem + '_refuses_' + mode[1:],
                refusal_case(script, mode))


if __name__ == '__main__':
    unittest.main()
