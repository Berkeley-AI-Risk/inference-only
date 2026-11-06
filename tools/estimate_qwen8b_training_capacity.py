#!/usr/bin/env python3
"""Offline released Qwen3-8B arithmetic and conditional capacity coefficients.

No model execution, network, hardware or cloud use. R8B and actual/certified phi
remain unassigned. --assumed-reference-tps supplies sensitivity inputs only.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

H100_OPS = 989_000_000_000_000
MODEL_REVISION = "b968826d9c46dd6066d109eabc6255188de91218"
MODEL_SHA = "a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833"
CHECKPOINT_SHA = "c16119f03177c4975be4bcc54e93cf54c290bb98079f2f8ddb2cc10bb4d07a9c"
DEMO = "demos/qwen3-8b"
MEASUREMENTS = f"{DEMO}/measurements.json"
REPORT = f"{DEMO}/evidence/implementation/utilization-hierarchical.rpt"
SOURCE_INPUTS = f"{DEMO}/SOURCE-INPUTS.json"
SOURCE_LOCK = f"{DEMO}/model/source-lock.json"
LAYOUT = f"{DEMO}/model/layout.json"
EXPECTED = {
    MEASUREMENTS: "f888f5189b624931e539d9c160dbf761ac83289af996297287b9f3d6abc91d1b",
    REPORT: "55d55f86fb361aa2073869a947ff14e8095f1b02fab063abea3b9a52b4aa8301",
    SOURCE_INPUTS: "83c22320ac4e52947d1d89360c7b68d37c71ff3c45edb0df64459de5c3b8bee2",
    SOURCE_LOCK: "5051c931db7d389d5eb1f7e39abb3d0f6daeca4263a6684331c9133bd82140d3",
    LAYOUT: "2ece9ed53778d965826e4b355177c7efe74e9f772b45bb6a792383a28eb02ad2",
}
GEOMETRY = dict(layers=36, width=4096, ffn=12288, query_heads=32,
                kv_heads=8, head_width=128, vocabulary=151936,
                tied_embeddings=False, tape_capacity=32768)
PRIMARY_CASES = ("single-token-128-output", "chat-fpga", "512-token-prefill")


def positive(value):
    if isinstance(value, bool):
        raise ValueError("Rate must be finite and positive")
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise ValueError("Rate must be finite and positive")
    return value


def work_counts(context):
    if type(context) is not int or not 1 <= context <= 32768:
        raise ValueError("Context must be an integer in 1..32768")
    layers, width, ffn, q, kv, head, vocab = 36, 4096, 12288, 32, 8, 128, 151936
    projection_macs = layers * (2 * width * q * head + 2 * width * kv * head
                               + 3 * width * ffn) + vocab * width
    attention_macs = 2 * layers * q * head * context
    gate = layers * ffn
    norm_elements = (2 * layers + 1) * width + layers * (q + kv) * head
    projection_rows = layers * (2 * q * head + 2 * kv * head
                               + 2 * ffn + width) + vocab
    softmax_products = layers * q * context
    return {
        "context_including_current_input": context,
        "fixed_projection_and_head_macs": projection_macs,
        "attention_operations": 2 * attention_macs,
        "matrix_operations": 2 * (projection_macs + attention_macs),
        "gate_products": gate,
        "norm_elements": norm_elements,
        "projection_rows": projection_rows,
        "softmax_probability_products": softmax_products,
        "named_dynamic_mac_equivalent_operations": 2 * (
            attention_macs + gate + 2 * norm_elements + projection_rows + softmax_products),
        "attention_share_of_matrix_work": attention_macs / (projection_macs + attention_macs),
        "kv_bytes_per_sequence": 2 * layers * kv * head * context * 2,
    }


def mapped_inventory(report):
    """Census non-overlapping multiplier modules, not all hierarchical DSP rows."""
    counts = {name: {"instances": 0, "dsp_blocks": 0} for name in (
        "private_dot8_accumulator", "qwen_fp32_mul_stage", "qwen_bf16_elementwise")}
    roles = dict(qk_products=0, av_products=0, softmax_probability=0,
                 rms_square=0, rms_normalize=0, projection_activation_scale=0,
                 feed_forward_gate=0)
    stack = []
    top_dsp = None
    for line in report.splitlines():
        if not line.startswith("|"):
            continue
        raw = line.split("|")[1:-1]
        r = [c.strip() for c in raw]
        if len(r) != 13 or not r[-1].isdigit() or r[0].startswith("("):
            continue
        indent = len(raw[0]) - len(raw[0].lstrip())
        while stack and stack[-1][0] >= indent:
            stack.pop()
        parents = [module for _, module in stack]
        if r[0] == "top":
            top_dsp = int(r[-1])
        stack.append((indent, r[1]))
        module = next((name for name in counts if r[1] == name or r[1].startswith(name + "__")), None)
        if module is None or int(r[-1]) == 0:
            continue
        counts[module]["instances"] += 1
        counts[module]["dsp_blocks"] += int(r[-1])
        has = lambda name: any(p == name or p.startswith(name + "__") for p in parents)
        if module == "qwen_fp32_mul_stage":
            if has("qwen_av_stream16") and r[0].endswith(".multiply"):
                roles["av_products"] += 1
            elif has("qwen_qk_dot128") and r[0].endswith(".multiply"):
                roles["qk_products"] += 1
            elif has("qwen_softmax") and r[0] == "scale_probability":
                roles["softmax_probability"] += 1
            elif has("qwen_rms_norm") and r[0] in ("multiply", "normalize"):
                roles["rms_square" if r[0] == "multiply" else "rms_normalize"] += 1
            elif has("qwen_projection_scale") and r[0] == "second_multiply":
                roles["projection_activation_scale"] += 1
        elif module == "qwen_bf16_elementwise" and r[0] == "elementwise" and has("qwen_fixed_core"):
            roles["feed_forward_gate"] += 1
    expected = {
        "private_dot8_accumulator": {"instances": 64, "dsp_blocks": 640},
        "qwen_fp32_mul_stage": {"instances": 175, "dsp_blocks": 350},
        "qwen_bf16_elementwise": {"instances": 5, "dsp_blocks": 10},
    }
    expected_roles = dict(qk_products=32, av_products=128, softmax_probability=2,
                          rms_square=1, rms_normalize=1, projection_activation_scale=2,
                          feed_forward_gate=1)
    if counts != expected or roles != expected_roles or top_dsp != 1000:
        raise ValueError("Mapped arithmetic changed; review classification and counts")
    return {
        "report_module_counts": counts, "integer_product_sites": 512,
        "floating_multiplier_instances": 180, "functional_multiplier_instances": 692,
        "integer_adder_dsp_blocks": 128, "total_dsp_blocks": top_dsp,
        "conditional_runtime_or_square_roles": roles,
        "runtime_or_square_instances_conditional_classification": sum(roles.values()),
    }


def case_rates(case):
    rows, expected = case["rows"], case["expected_tokens"]
    prompt_length = len(case["prompt_tokens"])
    if (prompt_length < 1 or len(rows) < 2 or len(rows) != len(expected)
            or any(type(r["index"]) is not int for r in rows)
            or [r["index"] for r in rows] != list(range(len(rows)))
            or [r["token"] for r in rows] != expected
            or prompt_length + len(rows) - 1 > 32768):
        raise ValueError("Expected complete ordered output records at valid contexts")
    for index, row in enumerate(rows):
        for field in ("step_ns", "generation_elapsed_ns", "prompt_elapsed_ns"):
            if type(row[field]) is not int or row[field] <= 0:
                raise ValueError("Invalid timing record")
        if index and row["generation_elapsed_ns"] <= rows[index - 1]["generation_elapsed_ns"]:
            raise ValueError("Generation timestamps must increase")
    # Row zero includes prefill; only the subsequent delivery intervals are cached.
    contexts = range(prompt_length + 1, prompt_length + len(rows))
    elapsed_ns = rows[-1]["generation_elapsed_ns"] - rows[0]["generation_elapsed_ns"]
    ops = sum(work_counts(n)["named_dynamic_mac_equivalent_operations"] for n in contexts)
    fixed_index = 128 - prompt_length
    fixed = rows[fixed_index] if 1 <= fixed_index < len(rows) else None
    return {
        "sustained_cached_tps": (len(rows) - 1) * 1e9 / elapsed_ns,
        "sustained_cached_intervals": len(rows) - 1,
        "sustained_contexts": [contexts.start, contexts.stop - 1],
        "cached_elapsed_ns": elapsed_ns,
        "named_ops_per_cached_token_mean": ops / (len(rows) - 1),
        "conditional_named_useful_operations_per_second": ops * 1e9 / elapsed_ns,
        "context128_output_index": fixed_index if fixed else None,
        "context128_step_ns": fixed["step_ns"] if fixed else None,
        "context128_single_step_tps": 1e9 / fixed["step_ns"] if fixed else None,
    }


def layout_counts(layout, source_lock):
    matrix_macs = sum(m["rows"] * m["columns"] for m in layout["matrices"])
    unique_norm = sum(v["elements"] for v in layout["vectors"])
    embedding = layout["embedding"]["rows"] * layout["embedding"]["row_bytes"] // 2
    if (len(layout["matrices"]) != 253 or len(layout["vectors"]) != 145
            or matrix_macs != work_counts(1)["fixed_projection_and_head_macs"]
            or unique_norm != 308224 or embedding != 622329856
            or matrix_macs + unique_norm + embedding != source_lock["parameter_entries"]):
        raise ValueError("Layout and parameter counts do not reconcile")
    return dict(matrix_macs=matrix_macs, unique_norm_parameters=unique_norm,
                separate_embedding_parameters=embedding,
                unique_parameters=matrix_macs + unique_norm + embedding)


def estimate(root, assumed_reference_tps=None):
    root = Path(root)
    raw = {name: (root / name).read_bytes() for name in EXPECTED}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in raw.items()}
    if hashes != EXPECTED:
        raise ValueError("Released evidence changed; select and audit a new version")
    inputs = json.loads(raw[SOURCE_INPUTS])
    verified_inputs = {}
    for name, info in inputs["frozen_hardware_inputs"].items():
        path = root / DEMO / name
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if len(data) != info["bytes"] or digest != info["sha256"]:
            raise ValueError(f"Frozen hardware input changed: {name}")
        verified_inputs[name] = digest
    measurements = json.loads(raw[MEASUREMENTS])
    source_lock = json.loads(raw[SOURCE_LOCK])
    if (measurements["checkpoint_sha256"] != CHECKPOINT_SHA
            or measurements["image_sha256"] != MODEL_SHA
            or measurements["source_revision"] != MODEL_REVISION
            or measurements["core_clock_mhz"] != 100
            or measurements["memory_axi_clock_mhz"] != 125
            or measurements["full_context_qualified"] is not False
            or inputs["fixed_model_image_sha256"] != MODEL_SHA
            or inputs["clock_recipes"] != dict(a="A0", b="B0", c="C2", hbm="H1")
            or source_lock["model_id"] != "Qwen/Qwen3-8B"
            or source_lock["revision"] != MODEL_REVISION):
        raise ValueError("Model, checkpoint, clock or qualification binding differs")
    params = layout_counts(json.loads(raw[LAYOUT]), source_lock)
    census = mapped_inventory(raw[REPORT].decode())
    suite = next(c for c in measurements["campaigns"] if c["name"] == "suite")
    cases = {c["name"]: c for c in suite["cases"] if c["name"] in PRIMARY_CASES}
    if set(cases) != set(PRIMARY_CASES) or suite["final_clear_status"] != 0:
        raise ValueError("Primary measurement cases or final CLEAR missing")
    rates = {name: case_rates(cases[name]) for name in PRIMARY_CASES}
    fixed_f = rates[PRIMARY_CASES[0]]["context128_single_step_tps"]
    coefficients = {
        "attention160_every_cycle_at_fixed128_rating": 2 * 160 * 100e6 / (H100_OPS * fixed_f),
        "named167_every_cycle_at_fixed128_rating": 2 * 167 * 100e6 / (H100_OPS * fixed_f),
        "all692_every_cycle_at_fixed128_rating": 2 * 692 * 100e6 / (H100_OPS * fixed_f),
        "named_schedule_context128": work_counts(128)["named_dynamic_mac_equivalent_operations"] / H100_OPS,
        "matrix_schedule_context128": work_counts(128)["matrix_operations"] / H100_OPS,
    }
    for name, rate in rates.items():
        coefficients[f"named_matching_continuation:{name}"] = rate["named_ops_per_cached_token_mean"] / H100_OPS
    fixed_rating_cases = {
        name: rate["conditional_named_useful_operations_per_second"] / (H100_OPS * fixed_f)
        for name, rate in rates.items()}
    winner = max(fixed_rating_cases, key=fixed_rating_cases.get)
    result = {
        "schema": "qwen8b-conditional-capacity-v1",
        "status": "Conditional coefficients only; no measured 8B GPU reference, demonstrated attack or certified factor",
        "reference_measured_tps": None, "actual_phi": None, "certified_phi": None,
        "input_sha256": hashes, "verified_frozen_hardware_inputs": len(verified_inputs),
        "model_revision": MODEL_REVISION, "model_image_sha256": MODEL_SHA,
        "routed_checkpoint_sha256": CHECKPOINT_SHA, "geometry": GEOMETRY,
        "dense_h100_operations_per_second_normalizer": H100_OPS,
        "parameters": params, "inventory": census, "fpga_measured_rates": rates,
        "fixed_inference_rating": dict(case=PRIMARY_CASES[0], context=128, tps=fixed_f,
            scope="One host-timed STEP call, not a sustained peak or continuation delivery rate"),
        "decode_counts": [work_counts(n) for n in (128, 512, 2048, 8192, 32768)],
        "phi_proxy_coefficient_per_matching_reference_tps": coefficients,
        "retained_workload_scenarios_at_fixed128_rating": {
            "coefficients_per_R128": fixed_rating_cases, "largest_modeled_case": winner,
            "largest_modeled_coefficient_per_R128": fixed_rating_cases[winner],
            "scope": "Maximum only over three retained hypothetical useful-access schedules; not an achieved attack or bound over other schedules"},
        "coefficient_scope": "The first five rows multiply R128. Each named_matching_continuation row instead requires that continuation's own R. Alternative allowances are not additive.",
        "limitations": [
            "R8B is unmeasured here; Qwen1.7B and SimpleStories reference rates do not transfer.",
            "Named logical work is not an execution-rate bound over replay, cancellation or stalls.",
            "Every-cycle credit assumes useful operand control, accumulation and readout despite fixed dataflow and scheduling; such access is not demonstrated.",
            "Integer products, standalone products and squares are credited as full dense16 MACs only as conditional precision/usefulness allowances.",
            "Weights, norms and rotary coefficients have constrained sources; runtime does not mean independently attacker chosen.",
            "The fixed quantized FPGA and upstream GPU parent have different numerical functions.",
            "Long-context counts are model arithmetic, not qualification; retained primary tests reach a 512-token prompt plus 16 outputs.",
            "No token-only observation, K/V security, whole-device security or production/ASIC qualification follows from this calculator."],
    }
    if assumed_reference_tps is not None:
        rate = positive(assumed_reference_tps)
        result["sensitivity_only"] = {
            "assumed_R_for_each_matching_workload": rate,
            "phi_proxy": {k: rate * v for k, v in coefficients.items()},
            "retained_scenarios_assuming_R128": {k: rate * v for k, v in fixed_rating_cases.items()}}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--assumed-reference-tps", type=positive)
    args = parser.parse_args()
    print(json.dumps(estimate(args.package_root, args.assumed_reference_tps), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
