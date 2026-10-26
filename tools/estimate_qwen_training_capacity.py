#!/usr/bin/env python3
"""Offline Qwen3-1.7B counts and conditional residual-capacity coefficients.

This tool supplies coefficients only; qwen_h100_results.py binds measured rates.
--assumed-reference-tps is sensitivity only.
Reads the identified released evidence, never operates hardware or a network.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

H100_OPS = 989_000_000_000_000
MODEL_REVISION = "70d244cc86ccca08cf5af4e1e306ecf908b1ad5e"
MEASUREMENTS = "demos/qwen3-1.7b/measurements.json"
REPORT = "demos/qwen3-1.7b/evidence/implementation/utilization-hierarchical.rpt"
INVENTORY = "diagrams/qwen-hardware-architecture.inventory.json"
EXPECTED = {
    MEASUREMENTS: "8266c1a3e9057302af4cc1cdf5085ca496d688541d04feffe07d041ab3b7140b",
    REPORT: "bd21e8e1941eab0d86b9f41021181450c50a79e6d061c080c90c62488dfd5264",
}


def positive(value):
    value = float(value)
    if not math.isfinite(value) or value <= 0:
        raise ValueError("Rate must be finite and positive")
    return value


def work_counts(context):
    if type(context) is not int or not 1 <= context <= 32768:
        raise ValueError("Context must be an integer in 1..32768")
    layers, width, ffn, q, kv, head, vocab = 28, 2048, 6144, 16, 8, 128, 151936
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
        "named_dynamic_mac_equivalent_operations": 2 * (
            attention_macs + gate + 2 * norm_elements + projection_rows + softmax_products),
        "attention_share_of_matrix_work": attention_macs / (projection_macs + attention_macs),
        "kv_bytes_per_sequence": 2 * layers * kv * head * context * 2,
    }


def mapped_inventory(report):
    rows = [[c.strip() for c in line.split("|")[1:-1]]
            for line in report.splitlines() if line.startswith("|")]
    counts = {}
    for module in ("private_dot8_accumulator", "qwen_fp32_mul_stage", "qwen_bf16_elementwise"):
        selected = [r for r in rows if len(r) > 12 and module in r[1]
                    and r[-1].isdigit() and int(r[-1]) > 0]
        counts[module] = {"instances": len(selected), "dsp_blocks": sum(int(r[-1]) for r in selected)}
    expected = {
        "private_dot8_accumulator": {"instances": 64, "dsp_blocks": 640},
        "qwen_fp32_mul_stage": {"instances": 175, "dsp_blocks": 350},
        "qwen_bf16_elementwise": {"instances": 5, "dsp_blocks": 10},
    }
    if counts != expected:
        raise ValueError("Mapped arithmetic changed; review classification and counts")
    return {"report_module_counts": counts, "integer_product_sites": 64 * 8,
            "floating_multiplier_instances": 175 + 5,
            "functional_multiplier_instances": 64 * 8 + 175 + 5,
            "integer_adder_dsp_blocks": 64 * 2,
            "total_dsp_blocks": 640 + 350 + 10,
            "runtime_or_square_instances_conditional_classification": 167}


def case_rates(case):
    lines = [json.loads(line) for line in case["stdout"].splitlines()]
    if len(lines) != 128 or [x["index"] for x in lines] != list(range(128)):
        raise ValueError("Expected 128 ordered output records")
    prompt_length = len(case["prompt_tokens"])
    # Output index i consumes prompt_length+i input positions. Index zero
    # includes prefill and is excluded from the 127 cached intervals.
    fixed_index = 128 - prompt_length
    if not 1 <= fixed_index < len(lines):
        raise ValueError("Selected tape has no cached decode at 128 positions")
    fixed = lines[fixed_index]
    fixed_seconds = positive(fixed["step_ns"]) / 1e9
    elapsed = positive(lines[-1]["generation_elapsed_ns"] - lines[0]["generation_elapsed_ns"]) / 1e9
    contexts = list(range(prompt_length + 1, prompt_length + 128))
    return {
        "sustained_cached_tps": 127 / elapsed,
        "sustained_cached_intervals": 127,
        "sustained_contexts": [contexts[0], contexts[-1]],
        "named_ops_per_cached_token_mean": sum(work_counts(n)["named_dynamic_mac_equivalent_operations"]
                                                for n in contexts) / 127,
        "context128_output_index": fixed_index,
        "context128_step_seconds": fixed_seconds,
        "context128_single_step_tps": 1 / fixed_seconds,
        "fixed_step_scope": "One host-timed STEP call, not sustained peak throughput; generation delivery overhead differs.",
    }


def estimate(root, assumed_reference_tps=None):
    root = Path(root)
    raw = {name: (root / name).read_bytes() for name in (*EXPECTED, INVENTORY)}
    hashes = {name: hashlib.sha256(data).hexdigest() for name, data in raw.items()}
    if any(hashes[name] != digest for name, digest in EXPECTED.items()):
        raise ValueError("Released evidence changed; select and audit a new version")
    inventory = json.loads(raw[INVENTORY])
    if (inventory["routed_checkpoint_sha256"] != "e8a1143e44bdc65fd1da76d7faeac236e59c49ccd4d5ce004a3b962ce6b5c98d"
            or inventory["report_sha256"] != hashes[REPORT]
            or inventory["clocks_mhz"]["inference"] != 100):
        raise ValueError("Image, clock or report binding differs")
    census = mapped_inventory(raw[REPORT].decode())
    campaigns = json.loads(raw[MEASUREMENTS])["campaigns"]
    campaign = next(c for c in campaigns if c["name"] == "sustained-128-run2")
    cases = {c["name"]: c for c in campaign["cases"]
             if c["name"] in ("raw_story", "raw_geography", "chat_greeting")}
    rates = {name: case_rates(case) for name, case in cases.items()}
    fixed_f = rates["raw_story"]["context128_single_step_tps"]
    coefficients = {
        "attention160_every_cycle": 2 * 160 * 100e6 / (H100_OPS * fixed_f),
        "named167_every_cycle": 2 * 167 * 100e6 / (H100_OPS * fixed_f),
        "all692_every_cycle": 2 * 692 * 100e6 / (H100_OPS * fixed_f),
        "named_schedule_context128": work_counts(128)["named_dynamic_mac_equivalent_operations"] / H100_OPS,
        "matrix_schedule_context128": work_counts(128)["matrix_operations"] / H100_OPS,
        "named_schedule_story_continuation": rates["raw_story"]["named_ops_per_cached_token_mean"] / H100_OPS,
    }
    result = {
        "status": "coefficient-only analysis; measured references are bound separately by qwen_h100_results.py; no certified factor",
        "reference_measured_tps": None, "input_sha256": hashes,
        "model_revision": MODEL_REVISION, "dense_h100_operations_per_second": H100_OPS,
        "inventory": census, "fpga_measured_rates": rates,
        "decode_counts": [work_counts(n) for n in (128, 512, 2048, 8192, 32768)],
        "phi_proxy_coefficient_per_reference_tps": coefficients,
        "coefficient_scope": "Each coefficient multiplies its matching workload's R. The first five use context128; the last uses the 127-step story continuation geometry. Rows are alternative access assumptions and are not additive.",
        "limitations": ["Named logical work is not an execution-rate bound.",
                        "Every-cycle MAC credit assumes useful attacker access, not demonstrated access.",
                        "Integer and standalone products credited as full dense16 MACs are precision/usefulness allowances.",
                        "Parent GPU and quantized FPGA numerical functions differ.",
                        "Only short contexts have hardware evidence; model counts at longer contexts do not qualify them."],
    }
    if assumed_reference_tps is not None:
        rate = positive(assumed_reference_tps)
        result["sensitivity_only"] = {"assumed_R_for_each_matching_workload": rate,
                                      "phi_proxy": {k: rate * v for k, v in coefficients.items()}}
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--package-root", type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument("--assumed-reference-tps", type=positive)
    args = p.parse_args()
    print(json.dumps(estimate(args.package_root, args.assumed_reference_tps), indent=2))


if __name__ == "__main__":
    main()
