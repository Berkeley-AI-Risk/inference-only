"""Regression checks for the source-projected parent proof's audit."""
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


class ParentAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.audit, cls.model, cls.hash_audit, cls.history = (load(name) for name in
            ("audit_parent", "parent_model", "audit_hash", "audit_history"))
        if "KV_FORMAL_WORK" not in os.environ:
            raise unittest.SkipTest("Requires generated artifacts: run tools/check_kv_integrity.py or set KV_FORMAL_WORK to its completed work directory.")
        cls.proof_dir = Path(os.environ["KV_FORMAL_WORK"]) / "parent"
        cls.module = json.loads((cls.proof_dir / "elaborated.json").read_text())["modules"][cls.model.TOP]
        cls.guard = (cls.proof_dir / "guard.sv").read_bytes()
        cls.monitor = (cls.proof_dir / "parent_monitor.inc.sv").read_bytes()
        cls.files = {p.name: p.read_bytes() for p in cls.proof_dir.glob("*.sv")}

    def test_real_parent_monitor_is_readonly(self):
        self.assertEqual(self.audit.monitor_check(self.monitor), 45)

    def test_reject_indexed_production_assignment(self):
        bad = self.monitor.replace(b"f_verified_mask[a_read_word_q] <= 1;", b"g_prefixes[a_read_word_q] <= 1;")
        with self.assertRaises(AssertionError):
            self.audit.monitor_check(bad)

    def test_reject_assumption(self):
        with self.assertRaises(AssertionError):
            self.audit.monitor_check(self.monitor + b"\n assume(reset_n_i);\n")

    def test_reject_extra_initialization(self):
        with self.assertRaises(AssertionError):
            self.audit.monitor_check(self.monitor + b"\n initial f_row_epoch = 0;\n")

    def test_real_guard_sources_reconstruct(self):
        self.audit.check_guard_sources(self.files, self.model, self.history, self.hash_audit)

    def test_reject_modified_production_guard(self):
        files = dict(self.files)
        files["guard.sv"] = self.guard.replace(b"if(write_fire) word_q<=s_wr_data;", b"if(write_fire) word_q<=m_rd_rsp_data;")
        with self.assertRaises(AssertionError):
            self.audit.check_guard_sources(files, self.model, self.history, self.hash_audit)

    def test_real_observers_cannot_drive_production(self):
        result = self.audit.observer_check(self.module, self.guard)
        self.assertEqual(result["memory_bits"], 1249280)

    def test_reject_observer_in_parent_control(self):
        module = copy.deepcopy(self.module)
        module["netnames"]["root_terminal"]["bits"] = module["netnames"]["u_atomic.f_coordinate"]["bits"][:1]
        with self.assertRaises(AssertionError):
            self.audit.observer_check(module, self.guard)

    def test_reject_observer_in_memory_write_address(self):
        module = copy.deepcopy(self.module)
        cell = module["cells"]["u_guard.partial_memory"]
        cell["connections"]["WR_ADDR"][0] = module["netnames"]["u_guard.f_stage_address"]["bits"][0]
        with self.assertRaises(AssertionError):
            self.audit.observer_check(module, self.guard)

    def test_reject_initialized_memory(self):
        module = copy.deepcopy(self.module)
        cell = module["cells"]["u_guard.stage_memory"]
        cell["parameters"]["INIT"] = "0" * len(cell["parameters"]["INIT"])
        with self.assertRaises(AssertionError):
            self.audit.observer_check(module, self.guard)

    def test_reject_constrained_compressor_output(self):
        module = copy.deepcopy(self.module)
        module["netnames"]["u_guard.u_hash.sha_done"]["bits"] = ["1"]
        with self.assertRaises(AssertionError):
            self.hash_audit.arbitrary_compressor_outputs(module, "u_guard.u_hash.")

    def test_queries_have_complete_coverage(self):
        self.assertEqual(self.audit.check_queries(self.proof_dir, 325, False, self.model.sha), 672)


if __name__ == "__main__":
    unittest.main(verbosity=2)
