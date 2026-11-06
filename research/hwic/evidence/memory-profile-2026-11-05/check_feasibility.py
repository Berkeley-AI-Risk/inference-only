#!/usr/bin/env python3
"""Recompute recorded feasibility arithmetic; no RTL, EDA, model or network run.

The adjacent metrics.json contains recorded source counts and measured counter
summaries. This checks their arithmetic, not the unpublished source/log bytes,
macro qualification, numerical model equivalence or achieved ASIC performance.
"""
import argparse
import json
from decimal import Decimal
from pathlib import Path


def positive_integer(value):
    if type(value) is not int or value <= 0:
        raise ValueError("geometry and context values must be positive integers")
    return value


def ceildiv(a, b):
    return (positive_integer(a) + positive_integer(b) - 1) // b


def derive(data):
    counts = data["source_counts"]
    weight = counts["central_weights"]
    misc = counts["central_misc"]
    kv = counts["KV"]
    central_bits = sum(positive_integer(x["depth"]) * positive_integer(x["width_bits"])
                       for x in (weight, misc))
    kv_depth = (positive_integer(kv["layers"]) * positive_integer(kv["capacity_positions"])
                * positive_integer(kv["combined_KV_head_rows_per_layer_position"])
                * positive_integer(kv["words_per_combined_head_row"]))
    kv_bits = kv_depth * positive_integer(kv["word_bits"])
    assert central_bits % 8 == kv_bits % 8 == 0
    tiling = []
    for macro in data["process_screen"]["SRAM_geometry_examples"]:
        wide = ceildiv(kv["word_bits"], macro["width_bits"])
        deep = ceildiv(kv_depth, macro["depth"])
        area = Decimal(macro["area_um2"])
        if not area.is_finite() or area <= 0:
            raise ValueError("macro area must be finite and positive")
        instances = wide * deep
        tiling.append({
            "id": macro["id"], "parallel_width_tiles": wide,
            "depth_banks": deep, "instances": instances,
            "macro_rectangles_only_mm2": float(area * instances / Decimal(1000000)),
            "allocated_bits": instances * macro["depth"] * macro["width_bits"],
        })
    measured = data["profile"]["clean_context1"]
    active = sum(measured["disjoint_family_cycles"].values())
    assert active == measured["active_cycles"]
    assert active + measured["E_IDLE_cycles"] == measured["harness_cycles"]
    workload_percent = {}
    for case in data["profile"]["case_counter_summaries"]:
        assert sum(case["disjoint_family_cycles"].values()) == case["active_cycles"]
        assert case["active_cycles"] + case["E_IDLE_cycles"] == case["last_profiled_cycles"]
        assert case["last_profiled_cycles"] + case["final_test_wait_cycles"] == case["full_harness_cycles"]
        if case["clean_performance_case"]:
            workload_percent[case["name"]] = {
                key: 100 * value / case["active_cycles"]
                for key, value in case["disjoint_family_cycles"].items()
            }
    # These context counts describe the current serial source schedule. Long
    # context timing is a sensitivity scenario, never a measured extrapolation.
    contexts = []
    beta = data["profile"]["observed_adjacent_context_increment_envelope"]
    attention_base = measured["disjoint_family_cycles"]["attention_including_softmax_normalization_KV_reads"]
    nonattention = data["profile"]["ordinary_nonattention_active_clocks"]
    ordinary_idle = data["profile"]["ordinary_E_IDLE_clocks"]
    projection = (measured["disjoint_family_cycles"]["QKVO_projections"]
                  + measured["disjoint_family_cycles"]["GATE_UP_DOWN_projections"])
    assert active - attention_base == nonattention
    for context in data["contexts"]:
        positive_integer(context)
        if context > kv["capacity_positions"]:
            raise ValueError("context exceeds declared capacity")
        serial_attention = 3072 * context + 46 * (24 * context + 1536)
        row = {
            "context": context,
            "stored_KV_bytes_at_active_context": 3456 * context,
            "logical_KV_read_words256_per_step": 300 * (context - 1),
            "logical_KV_read_bytes_per_step": 9600 * (context - 1),
            "logical_KV_write_bytes_per_step": 3456,
            "serial_attention_inner_work_clocks": serial_attention,
            "conditional_active_work_floor_clocks": serial_attention + nonattention,
            "conditional_floor_scope": data["profile"]["conditional_floor_scope"],
            "measured_current_full_model_cycles": measured["harness_cycles"] if context == 1 else None,
        }
        if context != 1:
            row["unvalidated_sensitivity_harness_cycles"] = [
                attention_base + b * (context - 1) + nonattention + ordinary_idle for b in beta
            ]
        contexts.append(row)
    throughput = data["H100_reference"]["aggregate_fixed_context_evaluations_per_second"]
    assumed_clock = positive_integer(data["assumed_clock_Hz_for_sensitivity_only"])
    return {
        "central_ROM_bytes": central_bits // 8,
        "KV_depth_words256": kv_depth, "KV_bytes_at_configured_capacity": kv_bits // 8,
        "central_ROM_plus_KV_bytes": (central_bits + kv_bits) // 8,
        "central_ROM_plus_KV_MiB": (central_bits + kv_bits) / 8 / (1024 ** 2),
        "SRAM_geometry_tiling": tiling,
        "clean_context1_active_family_percent": {
            key: 100 * value / active for key, value in measured["disjoint_family_cycles"].items()
        },
        "clean_workload_attention_percent_range": [
            min(x["attention_including_softmax_normalization_KV_reads"] for x in workload_percent.values()),
            max(x["attention_including_softmax_normalization_KV_reads"] for x in workload_percent.values()),
        ],
        "clean_workload_SiLU_UP_percent_range": [
            min(x["SiLU_times_UP"] for x in workload_percent.values()),
            max(x["SiLU_times_UP"] for x in workload_percent.values()),
        ],
        "context1_zero_projection_service_active_speedup_scenario": active / (active - projection),
        "context1_zero_projection_service_full_counter_speedup_scenario": measured["harness_cycles"] / (measured["harness_cycles"] - projection),
        "context_scorecard": contexts,
        "aggregate_reference_context128_current_schedule_read_Bps_scenario": throughput * 9600 * 127,
        "assumed_single_port_payload_Bps": assumed_clock * 32,
        "aggregate_reference_context128_required_port_equivalents_scenario": float(Decimal(str(throughput)) * 9600 * 127 / (assumed_clock * 32)),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare recomputed arithmetic with recorded derived values")
    args = parser.parse_args()
    data = json.loads(Path(__file__).with_name("metrics.json").read_text())
    result = derive(data)
    if args.check:
        if result != data["derived"]:
            raise SystemExit("FAIL: recorded derived values differ")
        print("PASS: recorded capacity, tiling, counter accounting, context and bandwidth arithmetic")
        print("Scope: recorded inputs only; no source/log replay or ASIC/GPU qualification")
    else:
        print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
