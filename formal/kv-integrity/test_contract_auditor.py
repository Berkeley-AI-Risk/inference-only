"""Artifact-free regression tests for fail-closed query/log checks."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("contract", Path(__file__).with_name("audit_contract.py"))
contract = importlib.util.module_from_spec(spec)
spec.loader.exec_module(contract)


class ContractTests(unittest.TestCase):
    def test_accept_exact_answers(self):
        self.assertEqual(contract.exact_answers(b"sat\nunsat\n", ["sat", "unsat"]), ["sat", "unsat"])

    def test_reject_unknown(self):
        with self.assertRaises(AssertionError):
            contract.exact_answers(b"unknown\n", ["unsat"])

    def test_reject_extra_answer(self):
        with self.assertRaises(AssertionError):
            contract.exact_answers(b"unsat\nunsat\n", ["unsat"])

    def test_reject_missing_answer(self):
        with self.assertRaises(AssertionError):
            contract.exact_answers(b"", ["unsat"])

    def test_reject_error_with_answer(self):
        with self.assertRaises(AssertionError):
            contract.exact_answers(b"unsat\n(error \"bad query\")\n", ["unsat"])

    def test_reject_unrecognized_output(self):
        with self.assertRaises(AssertionError):
            contract.exact_answers(b"unsat\nUNEXPECTED\n", ["unsat"])

    @staticmethod
    def model():
        return "\n".join(f"(define-fun |top_{s}| ((state |top_s|)) Bool true)" for s in ("i", "h", "u"))

    def test_accept_unrestricted_model(self):
        contract.unrestricted_state_predicates(self.model(), "top")

    def test_reject_hidden_initial_constraint(self):
        with self.assertRaises(AssertionError):
            contract.unrestricted_state_predicates(self.model().replace("Bool true", "Bool false", 1), "top")

    def test_reject_missing_state_predicate(self):
        with self.assertRaises(AssertionError):
            contract.unrestricted_state_predicates(self.model().split("\n", 1)[1], "top")

    def test_reject_duplicate_state_predicate(self):
        with self.assertRaises(AssertionError):
            contract.unrestricted_state_predicates(self.model() + "\n" + self.model(), "top")

    def test_reject_assumption_cell(self):
        with self.assertRaises(AssertionError):
            contract.unrestricted_state_predicates(self.model() + "\n; yosys-smt2-assume 0 hidden", "top")

if __name__ == "__main__":
    unittest.main()
