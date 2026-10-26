"""Artifact-dependent tests: reject damaged faulty-control evidence."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import importlib.util
import json
import os
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("fault_audit", Path(__file__).with_name("audit_fault_controls.py"))
AUDIT = importlib.util.module_from_spec(spec)
spec.loader.exec_module(AUDIT)


class FaultEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if "KV_FORMAL_WORK" not in os.environ:
            raise unittest.SkipTest("Requires a completed fault-controls replay.")
        cls.work = Path(os.environ["KV_FORMAL_WORK"])
        cls.directory = cls.work / "fault-controls/clear-history-sticky"

    def check(self, changed=None):
        changed = changed or {}
        return AUDIT.check_artifacts(self.work, "clear-history-sticky",
            lambda name: changed[name] if name in changed else (self.directory / name).read_bytes())

    def changed_result(self, key, value):
        result = json.loads((self.directory / "FINISHED.json").read_bytes())
        result[key] = value
        return {"FINISHED.json": json.dumps(result).encode()}

    def test_original(self):
        self.check()

    def test_reject_wrong_target(self):
        with self.assertRaises(AssertionError):
            self.check(self.changed_result("target_assertion", -1))

    def test_reject_wrong_query_hash(self):
        with self.assertRaises(AssertionError):
            self.check(self.changed_result("query_sha256", "0" * 64))

    def test_reject_wrong_model_hash(self):
        with self.assertRaises(AssertionError):
            self.check(self.changed_result("model_sha256", "0" * 64))

    def test_reject_changed_query(self):
        with self.assertRaises(AssertionError):
            self.check({"target.smt2": (self.directory / "target.smt2").read_bytes() + b"\n"})

    def test_reject_changed_mutation(self):
        with self.assertRaises(AssertionError):
            self.check({"guard.sv": (self.directory / "guard.sv").read_bytes() + b"\n"})

    def test_reject_solver_unknown_despite_pass_flag(self):
        with self.assertRaises(AssertionError):
            self.check({"z3.log": b"unknown\n"})

    def test_reject_extra_solver_output(self):
        with self.assertRaises(AssertionError):
            self.check({"cvc5.log": b"sat\nunsat\n"})


if __name__ == "__main__":
    unittest.main()
