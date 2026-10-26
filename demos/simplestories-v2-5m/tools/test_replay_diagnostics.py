"""Offline tests for explanatory messages; none changes proof acceptance."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    'replay_diagnostics', Path(__file__).with_name('replay_diagnostics.py'))
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


class ReplayDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.checks = Path(self.temporary.name)

    def failure(self, answers, expected=None, *, code=0, unchanged=True, log=''):
        expected = ['unsat'] if expected is None else expected
        row = {'passed': False, 'exit': code, 'answers': answers, 'source_unchanged': unchanged}
        self.record({'cvc5-induction-000': row}, {'cvc5-induction-000': {'expected': expected}}, log)
        return diagnostics.stage_failure('checks', 1, self.checks / 'checks.log', self.checks)

    def record(self, results, inputs, log=''):
        (self.checks / 'INPUTS.json').write_text(json.dumps({'jobs': inputs}))
        (self.checks / 'FINISHED.json').write_text(json.dumps({'jobs': results}))
        for name in results:
            job = self.checks / name
            job.mkdir(exist_ok=True)
            (job / 'solver.log').write_text(log)

    def test_identity_message_names_both_hashes_without_claiming_counterexample(self):
        text = diagnostics.identity_failure(Path('base.smt2'), 'a' * 64, 'b' * 64)
        for fragment in ('ARTIFACT_IDENTITY_MISMATCH', 'base.smt2', 'a' * 64, 'b' * 64,
                         'not itself a proof counterexample', 'has not passed', 'Do not replace'):
            self.assertIn(fragment, text)

    def test_unknown_is_not_pass(self):
        text = self.failure(['unknown'])
        self.assertIn('SOLVER_INCONCLUSIVE (not proved)', text)
        self.assertIn('This replay has not passed.', text)
        self.assertIn('solver.log', text)

    def test_base_feasibility_sat_then_unknown(self):
        text = self.failure(['sat', 'unknown'], ['sat', 'unsat'])
        self.assertIn('SOLVER_INCONCLUSIVE', text)

    def test_unexpected_sat_is_not_a_timeout(self):
        text = self.failure(['sat'])
        self.assertIn('UNEXPECTED_SOLVER_ANSWER', text)
        self.assertNotIn('SOLVER_INCONCLUSIVE', text)

    def test_mixed_unknown_and_wrong_answer_is_not_just_inconclusive(self):
        text = self.failure(['unknown', 'sat'], ['sat', 'unsat'])
        self.assertIn('UNEXPECTED_SOLVER_ANSWER', text)
        self.assertNotIn('SOLVER_INCONCLUSIVE', text)

    def test_missing_answers_are_not_called_a_clean_unknown(self):
        text = self.failure(['unknown'], ['sat', 'unsat'])
        self.assertIn('UNEXPECTED_SOLVER_ANSWER', text)

    def test_nonzero_tool_exit_is_an_error_even_with_unknown(self):
        text = self.failure(['unknown'], code=1)
        self.assertIn('TOOL_OR_CHECK_ERROR', text)
        self.assertNotIn('SOLVER_INCONCLUSIVE', text)

    def test_changed_source_is_an_error_even_with_unsat(self):
        self.assertIn('TOOL_OR_CHECK_ERROR', self.failure(['unsat'], unchanged=False))

    def test_solver_error_is_not_hidden_by_unknown(self):
        text = self.failure(['unknown'], log='(error "unsupported option")\nunknown\n')
        self.assertIn('TOOL_OR_CHECK_ERROR', text)
        self.assertNotIn('SOLVER_INCONCLUSIVE', text)

    def test_expected_sat_control_is_not_reported_as_a_failure(self):
        self.record(
            {'faulty-control': {'passed': True}, 'cvc5-goal': {
                'passed': False, 'exit': 0, 'answers': ['unknown'], 'source_unchanged': True}},
            {'faulty-control': {'expected': ['sat', 'sat']}, 'cvc5-goal': {'expected': ['unsat']}})
        text = diagnostics.stage_failure('checks', 1, self.checks / 'checks.log', self.checks)
        self.assertIn('cvc5-goal: SOLVER_INCONCLUSIVE', text)
        self.assertNotIn('faulty-control:', text)

    def test_missing_or_malformed_receipt_keeps_stage_failure(self):
        for contents in (None, '{broken', '[]', '{"jobs": null}'):
            with self.subTest(contents=contents):
                if contents is not None:
                    (self.checks / 'INPUTS.json').write_text(contents)
                text = diagnostics.stage_failure('checks', 1, self.checks / 'checks.log', self.checks)
                self.assertIn('Detailed query diagnostics unavailable', text)
                self.assertIn('This replay has not passed.', text)

    def test_missing_job_is_not_hidden(self):
        self.record({}, {'missing-goal': {'expected': ['unsat']}})
        text = diagnostics.stage_failure('checks', 1, self.checks / 'checks.log', self.checks)
        self.assertIn('Detailed query diagnostics unavailable', text)

    def test_stage_without_query_receipts_names_its_log(self):
        text = diagnostics.stage_failure('proof', 2, self.checks / 'proof.log')
        self.assertIn('proof exited 2', text)
        self.assertIn(str(self.checks / 'proof.log'), text)


if __name__ == '__main__':
    unittest.main()
