"""Small software-harness tests, not full-model numerical or FPGA validation."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


RUNNER = module('campaign_test_runner', ROOT/'reference/run_campaign.py')
CAPTURE = module('campaign_test_capture', ROOT/'tools/check_token_capture.py')


class FakeMachine:
    def __init__(self, outputs=(11, 358, 2776), fail_clear=None):
        self.outputs, self.fail_clear, self.clears = outputs, fail_clear, 0

    def clear(self):
        self.clears += 1
        self.index, self.prompt = 0, []
        if self.clears == self.fail_clear:
            raise RuntimeError('test cleanup error')

    def append(self, token):
        self.prompt.append(token)

    def step(self):
        value = self.outputs[self.index]
        self.index += 1
        return value


class CampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.measured = json.loads((ROOT/'measurements.json').read_text())
        cls.sources = RUNNER.verify_sources()

    def select(self, **kwargs):
        return RUNNER.select_cases(copy.deepcopy(self.measured), **kwargs)

    def synthetic_record(self, custom=False):
        selection = dict(campaign=None if custom else 'smoke', case=None,
                         prompt=[9707] if custom else None, steps=3)
        record = dict(schema=RUNNER.SCHEMA, source_sha256=self.sources,
                      runner_sha256=RUNNER.digest(ROOT/'reference/run_campaign.py'),
                      selection=selection, repeat=1, backend='cpu', threads=8,
                      model_sha256=RUNNER.MODEL_SHA, software_reference_only=True,
                      hardware_access=False, failure=None)
        RUNNER.execute(FakeMachine(), self.select(**selection), 1, record)
        return record

    def test_default_smoke(self):
        cases = self.select()
        self.assertEqual(len(cases), 2)
        self.assertEqual(cases[0]['expected_tokens'], [11, 358, 2776])

    def test_all_uses_longest_distinct_prompts(self):
        cases = self.select(campaign='all')
        self.assertEqual(len(cases), 3)
        self.assertEqual(sum(case['steps'] for case in cases), 197)

    def test_named_case_prefix(self):
        cases = self.select(campaign='suite', case='chat-fpga', steps=2)
        self.assertEqual(len(cases), 1)
        self.assertEqual(cases[0]['steps'], 2)
        self.assertEqual(len(cases[0]['prompt_tokens']), 23)

    def test_custom_prompt_not_comparison_pass(self):
        record = self.synthetic_record(custom=True)
        self.assertTrue(record['execution_completed'])
        self.assertIsNone(record['passed'])
        self.assertEqual(RUNNER.check_record(record)['compared_tokens'], 0)

    def test_bad_prompts_rejected(self):
        for text in ('', '1,', '-1', '1,,2', '1, 2', '１２', str(RUNNER.VOCAB)):
            with self.subTest(text=text), self.assertRaises(ValueError):
                RUNNER.parse_prompt(text)
        for prompt in ([True], [-1], [RUNNER.VOCAB], [1.5]):
            with self.subTest(prompt=prompt), self.assertRaises(ValueError):
                self.select(campaign=None, prompt=prompt, steps=1)
        self.assertEqual(RUNNER.parse_prompt('9707,11'), [9707, 11])

    def test_context_limit(self):
        with self.assertRaises(ValueError):
            self.select(campaign=None, prompt=[1], steps=RUNNER.CAPACITY)
        self.assertEqual(self.select(campaign=None, prompt=[1], steps=RUNNER.CAPACITY-1)[0]['steps'], RUNNER.CAPACITY-1)

    def test_invalid_selection(self):
        for options in (dict(campaign='missing'), dict(case='missing'), dict(campaign='all', case='first-three'),
                        dict(steps=0), dict(steps=4), dict(campaign=None, prompt=[1]),
                        dict(campaign='smoke', prompt=[1], steps=1)):
            with self.subTest(options=options), self.assertRaises(ValueError):
                self.select(**options)

    def test_inconsistent_recorded_prefix(self):
        measured = copy.deepcopy(self.measured)
        measured['campaigns'][0]['cases'][0]['expected_tokens'][0] = 0
        with self.assertRaises(ValueError):
            RUNNER.select_cases(measured, campaign='suite')

    def test_duplicate_recorded_names(self):
        measured = copy.deepcopy(self.measured)
        measured['campaigns'].append(measured['campaigns'][0])
        with self.assertRaises(ValueError):
            RUNNER.select_cases(measured)

    def test_repeat_clear_order_and_tokens(self):
        machine, result = FakeMachine(), {}
        RUNNER.execute(machine, self.select(), 2, result)
        self.assertEqual(machine.clears, 5)
        self.assertEqual([row['repetition'] for row in result['cases']], [0, 0, 1, 1])
        self.assertTrue(result['passed'] and result['final_clear'])

    def test_mismatch_keeps_partial_actual_outputs(self):
        result = {}
        with self.assertRaisesRegex(ValueError, 'token 1'):
            RUNNER.execute(FakeMachine(outputs=(11, 0)), self.select(), 1, result)
        self.assertEqual(result['cases'][0]['tokens'], [11, 0])
        self.assertFalse(result['execution_completed'])
        self.assertTrue(result['final_clear'])

    def test_cleanup_error_does_not_hide_original_mismatch(self):
        result = {}
        with self.assertRaisesRegex(ValueError, 'token 1'):
            RUNNER.execute(FakeMachine(outputs=(11, 0), fail_clear=2), self.select(), 1, result)
        self.assertFalse(result['final_clear'])
        self.assertEqual(result['cleanup_failure']['type'], 'RuntimeError')

    def test_cleanup_only_error_is_failure(self):
        result = {}
        with self.assertRaisesRegex(RuntimeError, 'cleanup'):
            RUNNER.execute(FakeMachine(fail_clear=3), self.select(), 1, result)
        self.assertFalse(result['passed'])

    def test_invalid_repeat_count(self):
        for repeat in (0, 9, True):
            with self.subTest(repeat=repeat), self.assertRaises(ValueError):
                RUNNER.execute(FakeMachine(), self.select(), repeat, {})

    def test_synthetic_record_checks_are_not_fresh_inference(self):
        result = RUNNER.check_record(self.synthetic_record())
        self.assertEqual(result['compared_tokens'], 6)
        self.assertIs(result['fresh_model_execution'], False)
        self.assertIs(result['hardware_qualification'], False)

    def test_record_mutations_rejected(self):
        original = self.synthetic_record()
        changes = [('passed', False), ('repeat', 2), ('final_clear', False), ('backend', 'cuda'),
                   ('hardware_access', True), ('runner_sha256', '0'*64), ('threads', True)]
        for key, value in changes:
            record = copy.deepcopy(original)
            record[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                RUNNER.check_record(record)
        record = copy.deepcopy(original)
        record['cases'][0]['tokens'][1] = 0
        with self.assertRaises(ValueError):
            RUNNER.check_record(record)

    def test_generation_cannot_claim_comparison_pass(self):
        record = self.synthetic_record(custom=True)
        record['passed'] = True
        with self.assertRaises(ValueError):
            RUNNER.check_record(record)

    def test_plan_cli_needs_no_model_or_torch(self):
        result = subprocess.run([sys.executable, '-I', '-S', '-B', str(ROOT/'reference/run_campaign.py'),
                                 '--plan', '--campaign', 'all'], text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIs(json.loads(result.stdout)['model_executed'], False)

    def test_list_cli(self):
        result = subprocess.run([sys.executable, '-I', '-S', '-B', str(ROOT/'reference/run_campaign.py'), '--list'],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(json.loads(result.stdout)), {'smoke', 'suite'})

    def test_initialization_failure_is_preserved_without_torch(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)/'new-run'
            result = subprocess.run([sys.executable, '-I', '-S', '-B', str(ROOT/'reference/run_campaign.py'),
                                     '--model', str(Path(directory)/'absent-model'), '--output', str(output)],
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((output/'STARTED.json').is_file())
            failure = json.loads((output/'FAILED.json').read_text())
            self.assertFalse(failure['passed'])
            self.assertEqual(failure['failure']['message'], 'Model directory does not exist')
            self.assertFalse((output/'FINISHED.json').exists())

    def test_existing_output_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, '-I', '-S', '-B', str(ROOT/'reference/run_campaign.py'),
                                     '--model', str(Path(directory)/'absent-model'), '--output', directory],
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list(Path(directory).iterdir()), [])


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.rows = copy.deepcopy(CampaignTests.measured['campaigns'][0]['cases'][0]['rows'])

    def text(self, rows=None):
        return '\n'.join(json.dumps(row) for row in (self.rows if rows is None else rows))

    def test_saved_rows_match_with_operator_exit_status(self):
        result = CAPTURE.check_rows(self.text(), [11, 358, 2776], 0)
        self.assertEqual(result['output_token_checks'], 3)
        self.assertGreater(result['cached_host_tokens_per_second'], 0)

    def test_nonzero_or_boolean_exit_status_rejected(self):
        for code in (-15, 1, True):
            with self.subTest(code=code), self.assertRaises(ValueError):
                CAPTURE.check_rows(self.text(), [11, 358, 2776], code)

    def test_partial_extra_wrong_and_repeated_rows_rejected(self):
        variants = [self.rows[:-1], self.rows+[self.rows[-1]], self.rows[::-1]]
        for changed in variants:
            with self.assertRaises(ValueError):
                CAPTURE.check_rows(self.text(changed), [11, 358, 2776], 0)
        changed = copy.deepcopy(self.rows)
        changed[1]['token'] = 0
        with self.assertRaises(ValueError):
            CAPTURE.check_rows(self.text(changed), [11, 358, 2776], 0)

    def test_bad_timing_and_malformed_rows_rejected(self):
        for field, value in [('step_ns', 0), ('generation_elapsed_ns', -1), ('prompt_elapsed_ns', 0), ('token', True)]:
            changed = copy.deepcopy(self.rows)
            changed[1][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                CAPTURE.check_rows(self.text(changed), [11, 358, 2776], 0)
        with self.assertRaises((ValueError, TypeError)):
            CAPTURE.check_rows('[1,2,3]', [11], 0)

    def test_single_token_has_no_cached_rate(self):
        result = CAPTURE.check_rows(self.text(self.rows[:1]), [11], 0)
        self.assertIsNone(result['cached_host_tokens_per_second'])

    def test_saved_capture_binding_does_not_claim_attestation(self):
        record = CampaignTests().synthetic_record()
        with tempfile.TemporaryDirectory() as directory:
            ref, capture = Path(directory)/'synthetic-reference.json', Path(directory)/'saved-client.jsonl'
            ref.write_text(json.dumps(record))
            capture.write_text(self.text())
            result = CAPTURE.check(capture, ref, 0, 0)
            self.assertTrue(result['recorded_capture_matches_reference'])
            self.assertFalse(result['hardware_qualification'])
            self.assertFalse(result['fresh_hardware_execution'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
