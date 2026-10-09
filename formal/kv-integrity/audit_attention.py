"""Audit attention proof sources, observers, abstractions and every solver query.

Shares the source-model generator with the runner. This is an automated
cross-check, not an independent review of the model or a numerical theorem.
"""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

TOP = "board1_context2048_attention"


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def observer_check(module):
    def bits(values):
        return {b for b in values if isinstance(b, int)}
    nets, cells = module["netnames"], module["cells"]
    selectors = [tuple(c["connections"]["Y"]) for c in cells.values() if c["type"] == "$anyconst"]
    assert selectors == [tuple(nets["f_att_coordinate"]["bits"])]
    reached = bits(selectors[0])
    assert len(reached) == 6
    assert not any(c["type"] in ("$assume", "$anyinit", "$mem_v2") for c in cells.values())
    edges = []
    for cell in cells.values():
        ports, directions = cell["connections"], cell["port_directions"]
        sources = set().union(*(bits(v) for n, v in ports.items() if directions[n] == "input"))
        outputs = set().union(*(bits(v) for n, v in ports.items() if directions[n] == "output"))
        edges.append((sources, outputs))
    while True:
        more = set().union(*(out for source, out in edges if source & reached))
        if more <= reached:
            break
        reached |= more
    protected = {n: bits(v["bits"]) for n, v in nets.items() if not v["hide_name"] and not n.startswith("f_att_")}
    protected.update({n: bits(v["bits"]) for n, v in module["ports"].items()})
    hits = [n for n, value in protected.items() if value & reached]
    assert not hits, hits
    return {"selector_bits": 6, "production_signal_hits": []}


def arbitrary_outputs(module):
    """Every retained abstract output has its own direct, unrestricted driver."""
    nets, cells = module["netnames"], module["cells"]
    expected = {
        "u_divider": ("request_ready_o", "response_valid_o", "response_result_o", "response_fault_o"),
        "u_exp_lut": ("range_fault_o", "response_valid_o", "value_o", "response_fault_o"),
        "u_output_bram": ("read_data_o",),
        "u_score_lane": ("product0_o",),
        "u_shift": ("request_ready_o", "response_valid_o", "response_result_o", "response_fault_o"),
        "u_workspace_bram": ("bank0_read_data_o", "bank1_read_data_o", "bank2_read_data_o"),
    }
    pins = [inst + "." + pin for inst, outputs in expected.items() for pin in outputs]
    drivers = [tuple(c["connections"]["Y"]) for c in cells.values() if c["type"] == "$anyseq"]
    assert len(drivers) == len(pins) == 17
    actual, seen = {}, set()
    for name in pins:
        inst, pin = name.split(".")
        value = tuple(nets[name]["bits"])
        assert value == tuple(nets[inst + ".f_arbitrary_" + pin]["bits"])
        assert drivers.count(value) == 1 and all(isinstance(b, int) for b in value)
        assert not seen.intersection(value)
        seen.update(value)
        actual[name] = len(value)
    assert set(drivers) == {tuple(nets[n]["bits"]) for n in pins}
    return actual


def query_prefix(smt, initial):
    rows = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(3):
        rows += [f"(declare-fun s{i} () {TOP}_s)", f"(assert ({TOP}_h s{i}))", f"(assert ({TOP}_u s{i}))",
                 f"(assert (= ({TOP}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
        if i:
            rows += [f"(assert ({TOP}_t s{i-1} s{i}))"]
    if initial:
        rows += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n rst_n| s0)))", f"(assert (not (|{TOP}_n rst_n| s1)))"]
    return rows


def check_queries(directory, count, sha):
    finished = json.loads((directory / "FINISHED.json").read_text())
    assert finished["passed"] and finished["source_unchanged"] and finished["yosys_exit"] == 0
    assert finished["inputs_sha256"] == sha((directory / "INPUTS.json").read_bytes())
    smt = (directory / "design.smt2").read_text()
    contract = load(Path(__file__).with_name("audit_contract.py"))
    contract.unrestricted_state_predicates(smt, TOP)
    assert len(re.findall(r"^; yosys-smt2-assert ", smt, re.M)) == count
    assert "; yosys-smt2-assume " not in smt
    queries = {"reset-witness": (query_prefix(smt, True), ["sat"]),
               "base": (query_prefix(smt, True) + [f"(assert (not (and ({TOP}_a s0) ({TOP}_a s1) ({TOP}_a s2))))"], ["unsat"])}
    for i in range(count):
        queries[f"induction-{i:03d}"] = (query_prefix(smt, False) + [f"(assert ({TOP}_a s0))", f"(assert ({TOP}_a s1))",
            f"(assert (not (|{TOP}_a {i}| s2)))"], ["unsat"])
    assert set(finished["solver_results"]) == {s + "-" + n for s in ("z3", "cvc5") for n in queries}
    for name, (lines, expected) in queries.items():
        raw = ("\n".join(lines + ["(check-sat)"]) + "\n").encode()
        assert (directory / (name + ".smt2")).read_bytes() == raw, name
        for solver in ("z3", "cvc5"):
            row = finished["solver_results"][solver + "-" + name]
            log = (directory / (solver + "-" + name + ".log")).read_bytes()
            answers = contract.exact_answers(log, expected)
            assert row["passed"] and row["exit"] == 0 and b"(error " not in log
            assert row["query_sha256"] == sha(raw) and row["log_sha256"] == sha(log)
            assert row["answers"] == row["expected"] == answers == expected
    return 2 * len(queries)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "proof", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    model, parent = load(here / "attention_model.py"), load(here / "audit_parent.py")
    sha = model.helper(here).sha
    files, binding = model.derive(args.package.resolve(), here)
    proof, out = args.proof.resolve(), args.out.resolve()
    inputs = json.loads((proof / "INPUTS.json").read_text())
    for name, raw in files.items():
        assert (proof / name).read_bytes() == raw, name
    for key, value in binding.items():
        assert inputs[key] == value, key
    for name, record in inputs["files"].items():
        raw = (proof / name).read_bytes()
        assert sha(raw) == record["sha256"] and len(raw) == record["bytes"], name
    count = parent.monitor_check(files["attention_monitor.inc.sv"])
    assert count == inputs["assertions"] == 34 and inputs["induction_length"] == 2
    module = json.loads((proof / "elaborated.json").read_text())["modules"][TOP]
    observers, arbitrary = observer_check(module), arbitrary_outputs(module)
    queries = check_queries(proof, count, sha)
    sources = ["attention.sv"] + sorted(n for n in files if n.startswith("boundary-"))
    commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS " + " ".join(sources),
                f"prep -top {TOP} -flatten", "memory_map", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                f"select -assert-count {count} t:$assert", "select -assert-none t:$assume",
                "select -assert-count 1 t:$anyconst", "check -assert", "write_json elaborated.json",
                "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
    assert (proof / "prove.ys").read_text() == "\n".join(commands) + "\n"
    out.mkdir(parents=True, exist_ok=False)
    for name in sources + ["prove.ys"]:
        (out / name).write_bytes((proof / name).read_bytes())
    with (out / "yosys.log").open("w") as log:
        result = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=out, stdout=log, stderr=subprocess.STDOUT)
    assert result.returncode == 0
    for name in ("elaborated.json", "elaborated.il", "design.smt2"):
        assert (out / name).read_bytes() == (proof / name).read_bytes(), name
    (out / "audit_attention.py").write_bytes(Path(__file__).read_bytes())
    result = {"passed": True, "assertions": count, "queries_checked": queries,
              "observers": observers, "arbitrary_child_replies": arbitrary,
              "byte_identical_elaboration": True, "shared_source_model_generator": True,
              "independent_review": False, "whole_machine_refinement": False,
              "hardware_access": False, "network_access": False}
    (out / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("ATTENTION_AUDIT_PASSED", flush=True)


if __name__ == "__main__":
    main()
