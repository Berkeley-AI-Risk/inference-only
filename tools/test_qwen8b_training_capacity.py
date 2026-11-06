"""Small offline accounting/regression checks; no model, network or hardware."""
import copy
import importlib.util
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "qwen8b_counts", Path(__file__).with_name("estimate_qwen8b_training_capacity.py"))
counts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(counts)
ROOT = Path(os.environ.get("QWEN8B_CAPACITY_PACKAGE_ROOT", Path(__file__).resolve().parents[1]))


class AccountingChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.result = counts.estimate(ROOT)
        cls.measurements = json.loads((ROOT / counts.MEASUREMENTS).read_bytes())
        cls.cases = {c["name"]: c for campaign in cls.measurements["campaigns"]
                     if campaign["name"] == "suite" for c in campaign["cases"]}
        cls.report = (ROOT / counts.REPORT).read_text()

    def test_8b_matrix_count_independently_from_layout(self):
        layout = json.loads((ROOT / counts.LAYOUT).read_bytes())
        self.assertEqual(sum(m["rows"] * m["columns"] for m in layout["matrices"]), 7568097280)
        self.assertEqual(counts.work_counts(128)["matrix_operations"], 15211692032)

    def test_query_heads_not_kv_heads_control_attention(self):
        for n in (1, 128, 512, 32768):
            c = counts.work_counts(n)
            self.assertEqual(c["attention_operations"], 4 * 36 * 32 * 128 * n)
            self.assertEqual(c["kv_bytes_per_sequence"], 2 * 36 * 8 * 128 * n * 2)

    def test_named_products_and_linear_coefficients(self):
        for n in (1, 128, 512, 2048, 8192, 32768):
            c = counts.work_counts(n)
            self.assertEqual(c["gate_products"], 442368)
            self.assertEqual(c["norm_elements"], 483328)
            self.assertEqual(c["projection_rows"], 1552768)
            self.assertEqual(c["softmax_probability_products"], 1152 * n)
            self.assertEqual(c["named_dynamic_mac_equivalent_operations"], 592128 * n + 5923584)
            self.assertEqual(c["matrix_operations"], 15136194560 + 589824 * n)

    def test_untied_embedding_is_not_an_extra_projection(self):
        p = self.result["parameters"]
        self.assertEqual(p["unique_norm_parameters"], (2 * 36 + 1) * 4096 + 36 * 2 * 128)
        self.assertEqual(p["separate_embedding_parameters"], 151936 * 4096)
        self.assertEqual(p["unique_parameters"], 8190735360)
        self.assertEqual(p["matrix_macs"] + p["unique_norm_parameters"]
                         + p["separate_embedding_parameters"], p["unique_parameters"])

    def test_bad_contexts(self):
        for n in (0, -1, 32769, True, 128.0, "128"):
            with self.subTest(context=n), self.assertRaises(ValueError):
                counts.work_counts(n)

    def test_bad_rates(self):
        for r in (0, -1, math.inf, -math.inf, math.nan, True, "nan"):
            with self.subTest(rate=r), self.assertRaises(ValueError):
                counts.positive(r)

    def test_frozen_inputs_and_published_image_identity(self):
        r = self.result
        self.assertEqual(r["input_sha256"], counts.EXPECTED)
        self.assertEqual(r["verified_frozen_hardware_inputs"], 135)
        self.assertEqual(r["routed_checkpoint_sha256"], counts.CHECKPOINT_SHA)
        self.assertFalse(r["geometry"]["tied_embeddings"])

    def test_disjoint_dsp_count_not_new_private_candidate(self):
        c = self.result["inventory"]
        self.assertEqual(c["functional_multiplier_instances"], 692)
        self.assertEqual(c["integer_product_sites"] + c["integer_adder_dsp_blocks"]
                         + 2 * c["floating_multiplier_instances"], 1000)
        self.assertEqual(c["total_dsp_blocks"], 1000)
        self.assertNotEqual(c["total_dsp_blocks"], 1648)

    def test_conditional_roles_reconcile_from_hierarchy(self):
        c = self.result["inventory"]
        self.assertEqual(c["runtime_or_square_instances_conditional_classification"], 167)
        roles = c["conditional_runtime_or_square_roles"]
        self.assertEqual(roles["qk_products"] + roles["av_products"], 160)
        self.assertEqual(roles["rms_square"] + roles["rms_normalize"], 2)

    def test_changed_module_or_missing_role_rejected(self):
        for old in ("private_dot8_accumulator", "scale_probability", "second_multiply"):
            with self.subTest(module=old), self.assertRaises(ValueError):
                counts.mapped_inventory(self.report.replace(old, "changed_module"))

    def test_double_counted_report_rejected(self):
        with self.assertRaises(ValueError):
            counts.mapped_inventory(self.report + self.report)

    def test_evidence_hash_drift_rejected_without_changing_files(self):
        original = Path.read_bytes

        def read(path):
            data = original(path)
            return data + b" " if path == ROOT / counts.MEASUREMENTS else data

        with patch.object(Path, "read_bytes", read), self.assertRaises(ValueError):
            counts.estimate(ROOT)

    def test_source_drift_rejected_without_changing_files(self):
        original = Path.read_bytes
        target = ROOT / counts.DEMO / "hardware/design/qwen_rms_norm.sv"

        def read(path):
            data = original(path)
            return data + b" " if path == target else data

        with patch.object(Path, "read_bytes", read), self.assertRaisesRegex(ValueError, "Frozen hardware input"):
            counts.estimate(ROOT)

    def test_parameter_drift_rejected(self):
        layout = json.loads((ROOT / counts.LAYOUT).read_bytes())
        lock = json.loads((ROOT / counts.SOURCE_LOCK).read_bytes())
        layout["embedding"]["rows"] += 1
        with self.assertRaises(ValueError):
            counts.layout_counts(layout, lock)

    def test_actual_and_certified_factor_remain_unassigned(self):
        for field in ("reference_measured_tps", "actual_phi", "certified_phi"):
            self.assertIsNone(self.result[field])
        self.assertNotIn("sensitivity_only", self.result)

    def test_fixed_step_is_exact_context128_not_continuation(self):
        r = self.result["fpga_measured_rates"]["single-token-128-output"]
        self.assertEqual(r["context128_output_index"], 127)
        self.assertEqual(r["context128_step_ns"], 896424626)
        self.assertEqual(r["sustained_contexts"], [2, 128])
        self.assertEqual(r["cached_elapsed_ns"], 113156941089)
        self.assertAlmostEqual(r["context128_single_step_tps"], 1e9 / 896424626)
        self.assertNotEqual(r["context128_single_step_tps"], r["sustained_cached_tps"])
        self.assertEqual(r["named_ops_per_cached_token_mean"], 44411904)

    def test_chat_and_prefill_do_not_have_context128_decode(self):
        rates = self.result["fpga_measured_rates"]
        self.assertEqual(rates["chat-fpga"]["sustained_contexts"], [24, 75])
        self.assertEqual(rates["512-token-prefill"]["sustained_contexts"], [513, 527])
        for name in ("chat-fpga", "512-token-prefill"):
            self.assertIsNone(rates[name]["context128_single_step_tps"])
            self.assertIsNone(rates[name]["context128_output_index"])

    def test_incomplete_out_of_order_or_wrong_output_rejected(self):
        for mode in ("missing", "order", "token", "time", "boolean_index", "negative_step"):
            c = copy.deepcopy(self.cases["single-token-128-output"])
            if mode == "missing":
                c["rows"].pop()
            elif mode == "order":
                c["rows"].reverse()
            elif mode == "token":
                c["rows"][2]["token"] += 1
            elif mode == "time":
                c["rows"][2]["generation_elapsed_ns"] = c["rows"][1]["generation_elapsed_ns"]
            elif mode == "boolean_index":
                c["rows"][0]["index"] = False
            else:
                c["rows"][0]["step_ns"] = -1
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                counts.case_rates(c)

    def test_context_capacity_rejected(self):
        c = copy.deepcopy(self.cases["single-token-128-output"])
        c["prompt_tokens"] *= 32768
        with self.assertRaises(ValueError):
            counts.case_rates(c)

    def test_matching_schedule_cancels_only_matching_device_rate(self):
        ops = counts.work_counts(128)["named_dynamic_mac_equivalent_operations"]
        coefficient = self.result["phi_proxy_coefficient_per_matching_reference_tps"]["named_schedule_context128"]
        for device_rate in (1, 9, 100):
            self.assertAlmostEqual(coefficient, ops * device_rate / (counts.H100_OPS * device_rate))

    def test_retained_scenario_keeps_fixed_inference_denominator(self):
        r = self.result
        f128 = r["fixed_inference_rating"]["tps"]
        scenarios = r["retained_workload_scenarios_at_fixed128_rating"]
        self.assertEqual(scenarios["largest_modeled_case"], "512-token-prefill")
        for name, c in scenarios["coefficients_per_R128"].items():
            rate = r["fpga_measured_rates"][name]
            self.assertAlmostEqual(c * counts.H100_OPS * f128,
                                   rate["conditional_named_useful_operations_per_second"])
            matched = r["phi_proxy_coefficient_per_matching_reference_tps"][f"named_matching_continuation:{name}"]
            # Absolute tolerance must not silently accept tiny unequal coefficients.
            self.assertNotAlmostEqual(c, matched, delta=1e-12)

    def test_every_cycle_is_a_separate_conditional_allowance(self):
        c = self.result["phi_proxy_coefficient_per_matching_reference_tps"]
        f = self.result["fixed_inference_rating"]["tps"]
        self.assertTrue(math.isclose(
            c["all692_every_cycle_at_fixed128_rating"] * counts.H100_OPS * f,
            138400000000, rel_tol=1e-15, abs_tol=0))
        self.assertEqual(len(c), 8)

    def test_sensitivity_does_not_assign_measured_rate_or_actual_factor(self):
        r = counts.estimate(ROOT, 1000)
        for field in ("reference_measured_tps", "actual_phi", "certified_phi"):
            self.assertIsNone(r[field])
        for key, coefficient in r["phi_proxy_coefficient_per_matching_reference_tps"].items():
            self.assertEqual(r["sensitivity_only"]["phi_proxy"][key], coefficient * 1000)

    def test_cli_default_and_explicit_root(self):
        completed = subprocess.run(
            [sys.executable, str(Path(counts.__file__)), "--package-root", str(ROOT)],
            capture_output=True, text=True, timeout=20, check=True)
        r = json.loads(completed.stdout)
        self.assertEqual(r, self.result)
        self.assertEqual(completed.stderr, "")

    def test_cli_sensitivity(self):
        completed = subprocess.run(
            [sys.executable, str(Path(counts.__file__)), "--package-root", str(ROOT),
             "--assumed-reference-tps", "1000"],
            capture_output=True, text=True, timeout=20, check=True)
        r = json.loads(completed.stdout)
        self.assertEqual(r["sensitivity_only"]["assumed_R_for_each_matching_workload"], 1000)
        self.assertIsNone(r["reference_measured_tps"])

    def test_cli_nonfinite_reference_rejected(self):
        completed = subprocess.run(
            [sys.executable, str(Path(counts.__file__)), "--assumed-reference-tps", "nan"],
            capture_output=True, text=True, timeout=20)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(completed.stdout, "")


if __name__ == "__main__":
    unittest.main()
