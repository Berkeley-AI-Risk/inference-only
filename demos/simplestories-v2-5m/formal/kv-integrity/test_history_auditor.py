"""Auditor regression/sensitivity tests; no files or FPGA state are changed."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("kv_history_audit", HERE / "audit_history.py")
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)


class HistoryAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if "KV_FORMAL_WORK" not in os.environ:
            raise unittest.SkipTest("Requires generated artifacts: run tools/check_kv_integrity.py or set KV_FORMAL_WORK to its completed work directory.")
        cls.proof_dir = Path(os.environ["KV_FORMAL_WORK"]) / "history"
        inputs = json.loads((cls.proof_dir / "INPUTS.json").read_text())
        cls.flags = {key: inputs[key] for key in
                     ("staging_observer", "write_history", "partial_history", "tag_history", "composed_page_hash")}
        cls.guard = (cls.proof_dir / "guard.sv").read_bytes()
        cls.design = json.loads((cls.proof_dir / "elaborated.json").read_text())["modules"][AUDIT.TOP]

    def check_observers(self, design):
        return AUDIT.observer_audit(design, self.flags, self.guard)

    def test_all_real_monitors(self):
        self.assertEqual(sum(AUDIT.readonly_monitor((self.proof_dir / name).read_bytes(), name)["assertions"]
                             for name in AUDIT.COUNTS), 221)

    def test_all_real_observers(self):
        result = self.check_observers(self.design)
        self.assertEqual(len(result["observation_ports"]), 8)
        self.assertEqual(result["production_signal_hits"], [])

    def test_reject_tag_monitor_driving_production(self):
        raw = (self.proof_dir / "tag_history_monitor.inc.sv").read_bytes()
        bad = raw.replace(b"f_tag_value <=", b"digest_q <=")
        self.assertNotEqual(raw, bad)
        with self.assertRaises(AssertionError):
            AUDIT.readonly_monitor(bad, "tag_history_monitor.inc.sv")

    def test_reject_added_assumption(self):
        raw = (self.proof_dir / "partial_history_monitor.inc.sv").read_bytes()
        with self.assertRaises(AssertionError):
            AUDIT.readonly_monitor(raw + b"\nassume(f_partial_shape);\n", "partial_history_monitor.inc.sv")

    def test_reject_observer_driving_write_address(self):
        bad = copy.deepcopy(self.design)
        bad["cells"]["partial_memory"]["connections"]["WR_ADDR"][0] = bad["netnames"]["f_partial_select"]["bits"][0]
        with self.assertRaises(AssertionError):
            self.check_observers(bad)

    def test_reject_observer_driving_tag_write_data(self):
        bad = copy.deepcopy(self.design)
        bad["cells"]["g_tags[3].memory"]["connections"]["WR_DATA"][0] = bad["netnames"]["f_tag_select"]["bits"][0]
        with self.assertRaises(AssertionError):
            self.check_observers(bad)

    def test_reject_observer_driving_real_function_call(self):
        bad = copy.deepcopy(self.design)
        names = [name for name in bad["netnames"] if re.fullmatch(r"layer_base\$func\$guard\.sv:199\$\d+\.\$result", name)]
        self.assertEqual(len(names), 1)
        bad["netnames"][names[0]]["bits"][0] = bad["netnames"]["f_partial_select"]["bits"][0]
        with self.assertRaises(AssertionError):
            self.check_observers(bad)

    def test_reject_preset_tag_ram(self):
        bad = copy.deepcopy(self.design)
        params = bad["cells"]["g_tags[2].memory"]["parameters"]
        params["INIT"] = "0" * len(params["INIT"])
        with self.assertRaises(AssertionError):
            self.check_observers(bad)

    def test_reject_missing_observation_port(self):
        bad = copy.deepcopy(self.design)
        bad["cells"]["stage_memory"]["parameters"]["RD_PORTS"] = "1"
        with self.assertRaises(AssertionError):
            self.check_observers(bad)

    def test_reject_unproved_support_property(self):
        with self.assertRaises(AssertionError):
            AUDIT.validate_support({"0": [0, 2], "1": [0]}, 2)

    def test_reject_missing_conclusion_support(self):
        with self.assertRaises(AssertionError):
            AUDIT.validate_support({"0": [0]}, 2)

    def test_accept_subsets_only_from_joint_invariant(self):
        AUDIT.validate_support({"0": [0], "1": [0, 1]}, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
