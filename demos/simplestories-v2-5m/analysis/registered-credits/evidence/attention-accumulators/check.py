"""One-cycle RTL product-to-state sensitivity and a workload-specific normalization."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import tarfile
import tempfile

MODULE = "board1_context2048_attention"
IMAGE = "01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"
RTL = f"project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/{MODULE}.sv"
H = 989_000_000_000_000

def sha(data):
    return hashlib.sha256(data).hexdigest()

def read(path):
    return json.loads(path.read_bytes())

def yosys(commands, scratch):
    p = subprocess.run(["yosys", "-Q", "-T", "-p", commands], cwd=scratch,
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    if p.returncode:
        raise RuntimeError(p.stdout[-3000:])
    return p.stdout

def touched_children(cells, product_bits):
    """Find every immediate child input reachable combinationally from this bank."""
    touched = set(product_bits)
    while True:
        before = len(touched)
        for c in cells.values():
            if not c["type"].startswith("$") or "ff" in c["type"]:
                continue
            ports = c["connections"]
            if any(touched.intersection(ports[p]) for p,d in c["port_directions"].items() if d == "input"):
                for p, d in c["port_directions"].items():
                    if d == "output":
                        touched.update(b for b in ports[p] if isinstance(b, int))
        if len(touched) == before:
            break
    # All child ports in this module are input-by-default with suffix _o for outputs.
    return {(name,p) for name,c in cells.items() if not c["type"].startswith("$")
            for p,bits in c["connections"].items() if not p.endswith("_o") and touched.intersection(bits)}

def product_cone(top):
    """Extract native combinational cells back to actual register values and child outputs."""
    cells, wires = top["cells"], top["netnames"]
    products = {}
    for family in ["score", "value"]:
        bits = []
        for lane in range(8):
            cell = cells[f"g_mac8[{lane}].u_{family}_lane"]
            assert cell["type"] == "board1_unified_projection_head_dynamic_mul_exact"
            ports = cell["connections"]
            assert ports["mode_i"] == ["1", "1"] and not ports["product1_o"]
            assert len(ports["product0_o"]) == 32
            bits.extend(ports["product0_o"])
        products[family] = bits
    # These child memories have synchronous payload reads. No product-dependent
    # combinational response from a cut child can round-trip back to our sinks.
    assert touched_children(cells, products["score"]) == {("u_workspace_bram", port) for port in
            ["bank0_write_data_i","bank1_write_data_i","bank2_write_data_i","write_address_i","write_enable_i"]}
    assert touched_children(cells, products["value"]) == {("u_accumulator_bram","write_data_i")}
    state = wires["state_q"]["bits"]
    reg_bits = wires["score_accumulator_q"]["bits"]
    (score_ff,) = [c for c in cells.values() if c["connections"].get("Q") == reg_bits]
    assert score_ff["type"] == "$adffe"
    assert all(int(score_ff["parameters"][k], 2) == v for k, v in
               [("EN_POLARITY", 1), ("ARST_POLARITY", 0), ("ARST_VALUE", 0), ("CLK_POLARITY", 1)])
    q, a, b = (score_ff["connections"], cells["u_workspace_bram"]["connections"],
               cells["u_accumulator_bram"]["connections"])
    assert q["CLK"] == a["clk"] == b["clk"] == wires["clk"]["bits"]
    outputs = {"acc_old": q["Q"], "acc_new": q["D"], "acc_en": q["EN"], "reset_n": q["ARST"],
               "wk_en": a["write_enable_i"], "wk_word": a["write_address_i"] +
               sum((a[f"bank{i}_write_data_i"] for i in range(3)), []),
               "pv_en": b["write_enable_i"], "pv_word": b["write_address_i"]+b["write_data_i"]}
    drivers = {}
    for name, c in cells.items():
        if c["type"].startswith("$") and "ff" not in c["type"]:
            for p, d in c["port_directions"].items():
                if d == "output":
                    for bit in c["connections"][p]:
                        if isinstance(bit, int):
                            assert bit not in drivers
                            drivers[bit] = name
    cuts = set(state + products["score"] + products["value"])
    frontier, kept = set(), {}
    todo = sum(outputs.values(), [])
    while todo:
        bit = todo.pop()
        if not isinstance(bit, int) or bit in cuts:
            continue
        if bit not in drivers:
            frontier.add(bit)
            continue
        name = drivers[bit]
        if name in kept:
            continue
        c = kept[name] = cells[name]
        for p, d in c["port_directions"].items():
            if d == "input":
                todo.extend(c["connections"][p])
    inputs = {"shared": sorted(frontier), "state": state, **products}
    ports = {k: {"direction": "input", "bits": v} for k, v in inputs.items()}
    ports.update({k: {"direction": "output", "bits": v} for k, v in outputs.items()})
    netnames = {k: {"hide_name": 0, "bits": v["bits"], "attributes": {}} for k,v in ports.items()}
    cone = {"attributes": {}, "ports": ports, "netnames": netnames, "cells": kept}
    return cone, inputs, outputs

def wrapper(inputs, outputs):
    inports = []
    for k, bits in inputs.items():
        inports.append(f"input [{len(bits)-1}:0] {k}")
        if k in ["score", "value"]:
            inports.append(f"input [{len(bits)-1}:0] alt_{k}")
    lines = ["module audit(" + ", ".join(inports + ["output bad_s, bad_v, diff_s, diff_v"]) + ");"]
    for name in ["base", "s", "v"]:
        connect = [f".{k}({'alt_' if (k,name) in [('score','s'),('value','v')] else ''}{k})" for k in inputs]
        for k, bits in outputs.items():
            lines.append(f"wire [{len(bits)-1}:0] {name}_{k};")
            connect.append(f".{k}({name}_{k})")
        lines.append(f"cone {name}(" + ",".join(connect) + ");")
        # Count both data and validity/address changes. Disabled memory data has no effect.
        effects_width = len(outputs["acc_new"]) + 2 + len(outputs["wk_word"]) + len(outputs["pv_word"])
        lines.append(f"wire [{effects_width-1}:0] {name}_effects = {{" +
                     f"{name}_reset_n ? ({name}_acc_en ? {name}_acc_new : {name}_acc_old) : '0," +
                     f"{name}_wk_en, {name}_wk_en ? {name}_wk_word : '0," +
                     f"{name}_pv_en, {name}_pv_en ? {name}_pv_word : '0" + "};")
    lines += ["assign diff_s = (base_effects != s_effects);",
              "assign diff_v = (base_effects != v_effects);",
              "assign bad_s = diff_s && state != 6'd33;",
              "assign bad_v = diff_v && state != 6'd24;", "endmodule"]
    return "\n".join(lines)

def main(root):
    demo = root / "demos/simplestories-v2-5m"
    build = read(demo / "prebuilt/inference/BUILD.json")
    assert sha((demo / "prebuilt/inference" / build["image_relative_path"]).read_bytes()) == build["image_sha256"] == IMAGE
    inventory_hash = build["hardware_inputs_sha256"]
    evidence = demo / "evidence/current-greedy"
    inventory = gzip.decompress((evidence / "objects" / f"{inventory_hash}.gz").read_bytes())
    assert sha(inventory) == inventory_hash
    native = json.loads(inventory)
    rtl_bytes = (demo / "hardware" / RTL).read_bytes()
    memory_rtl = RTL.replace("attention.sv", "attention_memories.sv")
    lane_rtl = "project/fpga/token_only_model0_ddr_board1/unified_dynamic_dsp1/rtl/board1_unified_projection_head_dynamic_mul_exact.sv"
    for path in [RTL, memory_rtl, lane_rtl, "project/production_sources.f", "project/constraints/product.sdc"]:
        assert sha((demo / "hardware" / path).read_bytes()) == native[path]
    recipe = (demo / "hardware/project/production_sources.f").read_text().splitlines()
    assert all(path[len("project/"):] in recipe for path in [RTL, memory_rtl, lane_rtl])
    impl = read(evidence / "baseline/analysis/implementation.json")
    census = read(evidence / "baseline/analysis/mapped-census.json")
    timing = read(evidence / "baseline/analysis/metrics.json")
    assert impl["image_sha256"] == census["image_sha256"] == timing["image_sha256"] == IMAGE
    assert census["functional_group_counts"]["attention_score"] == census["functional_group_counts"]["attention_value"] == 8
    assert all(census[f"attention_{x}_instances"] == 8 for x in ["score", "value"])
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp)
        (scratch / "attention.sv").write_bytes(rtl_bytes)
        yosys("read_verilog -DSYNTHESIS -sv attention.sv; proc; opt; write_json full.json", scratch)
        cone, inputs, outputs = product_cone(read(scratch / "full.json")["modules"][MODULE])
        (scratch / "cone.json").write_text(json.dumps({"modules": {"cone": cone}}))
        (scratch / "audit.sv").write_text(wrapper(inputs, outputs))
        prep = "read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; flatten; opt; "
        results = []
        for label, args in [("score_only_in_state_33", "-verify -prove bad_s 0"),
                            ("value_only_in_state_24", "-verify -prove bad_v 0"),
                            ("score_sensitive_witness", "-falsify -set state 33 -prove diff_s 0"),
                            ("value_sensitive_witness", "-falsify -set state 24 -prove diff_v 0")]:
            result = yosys(prep + "sat " + args + " audit", scratch)
            assert ("no model found: SUCCESS!" if "-verify" in args else "model found: FAIL!") in result
            results.append(label)
    metrics = timing["metrics"]
    seconds = [metrics[k]["last_step_seconds"] for k in ("around128","around128-repeat")]
    capture = read(demo / "benchmarks/fpga-speed/captures/baseline-common-speed-20261026-r1/FINISHED.json")
    assert capture["passed"] and capture["identity"]["fpga_image_sha256"] == IMAGE
    assert [case["step_seconds"][-1] for case in capture["cases"]] == seconds
    for case in capture["cases"]:
        assert case["prompt_tokens"] == [378] and len(case["generated_tokens"]) == 128
        assert case["generated_tokens"] == case["expected_tokens"]
    F = 2/sum(seconds)
    gpu = root / "evidence/qwen-h100-2026-10-25"
    ref = read(gpu / "computed-results.json")["references"]["small_fixed"]
    with tarfile.open(gpu / "raw-evidence.tar.gz") as archive:
        raw = archive.extractfile(ref["member"]).read()
    assert sha(raw) == ref["sha256"]
    case = json.loads(raw)
    assert case["status"] == "pass" and case["workload"]["context"] == 128
    work = case["workload"]["batch"] * case["workload"]["iterations"]
    assert work == case["timing"]["counted_tokens_per_trial"]
    R = work / statistics.median(x["wall_seconds"] for x in case["timing"]["samples"])
    assert R == ref["rate"]
    freq = impl["nominal_inference_clock_hz"]
    assert freq == capture["identity"]["clock_hz"]
    T = 2 * 8 * freq
    data = {"source_commit": "159528e36d46fc803326758b160aa5e84aebd72b", "image_sha256": IMAGE,
            "source_sha256": sha(rtl_bytes), "native_inventory_sha256": inventory_hash, "yosys": subprocess.check_output(["yosys","-V"],text=True).strip(),
            "sat_results":results, "combinational_cells_in_cone":len(cone["cells"]), "arbitrary_shared_cut_bits":len(inputs["shared"]),
            "FPGA_step_seconds": seconds, "F_fixed128":F, "R_fixed128":R, "R_batch":ref["batch"],
            "R_greedy_disagreements":ref["main_greedy_disagreements"], "accounting_normalizer_H": H,
            "clock_hz":freq, "max_product_contributions_per_edge":8, "operations_per_product":2,
            "channel_op_credit_per_second_upper":T, "channel_measured_proxy_upper":T*R/(H*F),
            "separately_counted_banks_ungated_ceiling":2*T*R/(H*F),
            "training_access_measured":False, "whole_system_upper":None}
    print(json.dumps(data,indent=2))
if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("checkout",type=Path)
    main(cli.parse_args().checkout.resolve())
