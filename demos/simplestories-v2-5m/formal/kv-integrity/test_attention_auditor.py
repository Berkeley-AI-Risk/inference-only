"""Reject faulty attention-proof instrumentation and constrained abstractions."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import copy
import importlib.util
import json
import os
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AttentionAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit, cls.parent, cls.model = (load(n) for n in ("audit_attention", "audit_parent", "parent_model"))
        if "KV_FORMAL_WORK" not in os.environ:
            raise unittest.SkipTest("Requires generated artifacts: run tools/check_kv_integrity.py or set KV_FORMAL_WORK to its completed work directory.")
        cls.proof = Path(os.environ["KV_FORMAL_WORK"]) / "attention"
        cls.module = json.loads((cls.proof / "elaborated.json").read_text())["modules"][cls.audit.TOP]
        cls.monitor = (cls.proof / "attention_monitor.inc.sv").read_bytes()

    def test_real_monitor_readonly(self):
        self.assertEqual(self.parent.monitor_check(self.monitor), 34)

    def test_reject_production_assignment(self):
        bad = self.monitor.replace(b"f_att_aligned_mask[coordinate_q[5:3]] <= 1;", b"aligned_value_q[coordinate_q[5:3]] <= 1;")
        self.assertNotEqual(bad, self.monitor)
        with self.assertRaises(AssertionError):
            self.parent.monitor_check(bad)

    def test_reject_assumption(self):
        with self.assertRaises(AssertionError):
            self.parent.monitor_check(self.monitor + b"\nassume(model_lock_i);\n")

    def test_observer_is_nondriving(self):
        self.assertEqual(self.audit.observer_check(self.module)["production_signal_hits"], [])

    def test_reject_observer_in_production(self):
        bad = copy.deepcopy(self.module)
        bad["netnames"]["interface_live"]["bits"] = bad["netnames"]["f_att_coordinate"]["bits"][:1]
        with self.assertRaises(AssertionError):
            self.audit.observer_check(bad)

    def test_child_outputs_unrestricted(self):
        self.assertEqual(len(self.audit.arbitrary_outputs(self.module)), 17)

    def test_reject_constant_child_output(self):
        bad = copy.deepcopy(self.module)
        bad["netnames"]["u_divider.response_valid_o"]["bits"] = ["1"]
        with self.assertRaises(AssertionError):
            self.audit.arbitrary_outputs(bad)

    def test_reject_coupled_child_outputs(self):
        bad = copy.deepcopy(self.module)
        for name in ("response_fault_o", "f_arbitrary_response_fault_o"):
            bad["netnames"]["u_divider." + name]["bits"] = bad["netnames"]["u_divider.response_valid_o"]["bits"]
        with self.assertRaises(AssertionError):
            self.audit.arbitrary_outputs(bad)

    def test_all_queries_reconstructed(self):
        self.assertEqual(self.audit.check_queries(self.proof, 34, self.model.sha), 72)


if __name__ == "__main__":
    unittest.main(verbosity=2)
