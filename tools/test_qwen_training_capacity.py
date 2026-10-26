"""Offline accounting checks; no model imports, hardware or network."""
import importlib.util
import math
import os
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "qwen_counts", Path(__file__).with_name("estimate_qwen_training_capacity.py"))
counts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(counts)
ROOT = Path(os.environ.get("QWEN_CAPACITY_PACKAGE_ROOT", Path(__file__).resolve().parents[1]))


class AccountingChecks(unittest.TestCase):
    def test_context_uses_query_heads_for_attention(self):
        c = counts.work_counts(128)
        self.assertEqual(c["attention_operations"], 4 * 28 * 16 * 128 * 128)
        self.assertEqual(c["kv_bytes_per_sequence"], 2 * 28 * 8 * 128 * 128 * 2)
        self.assertEqual(c["matrix_operations"], 3470262272)
        self.assertEqual(c["named_dynamic_mac_equivalent_operations"], 32080640)

    def test_bad_contexts_and_rates_rejected(self):
        for n in (0, 32769, True, 128.0):
            with self.assertRaises(ValueError):
                counts.work_counts(n)
        for r in (0, -1, math.inf, math.nan):
            with self.assertRaises(ValueError):
                counts.positive(r)

    def test_rms_parameter_reconciliation(self):
        # All unique parameters are projection/head weights or RMS weights.
        rms = (2 * 28 + 1) * 2048 + 28 * (16 + 8) * 128
        # Q/K normalization weights are shared across their heads.
        unique_rms = (2 * 28 + 1) * 2048 + 28 * 2 * 128
        self.assertEqual(rms, 202752)
        self.assertEqual(counts.work_counts(1)["fixed_projection_and_head_macs"] + unique_rms,
                         1720574976)

    def test_verified_evidence_and_disjoint_inventory(self):
        result = counts.estimate(ROOT)
        c = result["inventory"]
        self.assertEqual(c["functional_multiplier_instances"], 692)
        self.assertEqual(c["integer_product_sites"] + c["integer_adder_dsp_blocks"]
                         + 2 * c["floating_multiplier_instances"], c["total_dsp_blocks"])
        self.assertIsNone(result["reference_measured_tps"])
        self.assertNotIn("sensitivity_only", result)

    def test_fixed_context_is_not_continuation_average(self):
        r = counts.estimate(ROOT)["fpga_measured_rates"]["raw_story"]
        self.assertEqual(r["context128_output_index"], 124)
        self.assertEqual(r["context128_step_seconds"], 0.112895146)
        self.assertEqual(r["sustained_contexts"], [5, 131])
        self.assertEqual(r["named_ops_per_cached_token_mean"], 18264320)
        self.assertNotEqual(r["context128_single_step_tps"], r["sustained_cached_tps"])

    def test_sensitivity_and_matched_schedule_identity(self):
        result = counts.estimate(ROOT, 1234)
        proxy = result["sensitivity_only"]["phi_proxy"]["named_schedule_context128"]
        c = counts.work_counts(128)["named_dynamic_mac_equivalent_operations"]
        for device_rate in (1, 9, 100):
            self.assertAlmostEqual(proxy, (c * device_rate) * 1234 / (counts.H100_OPS * device_rate))

    def test_changed_report_rejected(self):
        text = (ROOT / counts.REPORT).read_text()
        with self.assertRaises(ValueError):
            counts.mapped_inventory(text.replace("private_dot8_accumulator", "changed_module"))


if __name__ == "__main__":
    unittest.main()
