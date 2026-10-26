"""Reconstruct faulty models/queries and check raw solver answers.

This does not trust a saved PASS flag alone. It shares mutation/query helpers
with the runner, so it is not an independently implemented query checker.
"""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess


def helper(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


CONTROL = helper("check_fault_controls")
CONTRACT = helper("audit_contract")


def check_artifacts(work, name, read):
    files, expected_inputs = CONTROL.model_files(work, name)
    # JSON serializes the mutation tuples as lists.
    assert json.loads(read("INPUTS.json")) == json.loads(json.dumps(expected_inputs))
    for filename, raw in files.items():
        assert read(filename) == raw, (name, filename)
    stage, changed_name, _, needle = CONTROL.CASES[name]
    target_file = "parent.sv" if stage == "parent" else changed_name
    smt = read("design.smt2").decode()
    top = CONTROL.TOPS[stage]
    CONTRACT.unrestricted_state_predicates(smt, top)
    target = CONTROL.target_index(smt, target_file, files[target_file].decode(), needle)
    query = CONTROL.target_query(smt, top, target)
    assert read("target.smt2") == query, name
    result = json.loads(read("FINISHED.json"))
    assert result["passed"] is True and result["reset_reachable_claim"] is False
    assert result["target_assertion"] == target and type(result["target_assertion"]) is int
    assert result["query_sha256"] == CONTROL.sha(query)
    assert result["model_sha256"] == CONTROL.sha(smt.encode())
    assert set(result["solvers"]) == {"z3", "cvc5"}
    for solver, row in result["solvers"].items():
        raw = read(solver + ".log")
        CONTRACT.exact_answers(raw, ["sat"])
        assert row == {"passed": True, "exit": 0, "log_sha256": CONTROL.sha(raw)}, (name, solver)
    return files, result


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("work", "proof", "out"):
        ap.add_argument("--" + name, type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    assert 1 <= args.jobs <= 16
    proof, out = args.proof.resolve(), args.out.resolve()
    assert proof != out and not out.is_relative_to(proof)
    summary = json.loads((proof / "FINISHED.json").read_bytes())
    assert summary["passed"] and summary["reset_reachable_claim"] is False
    assert set(summary["cases"]) == set(CONTROL.CASES)
    assert {p.name for p in proof.iterdir() if p.is_dir()} == set(CONTROL.CASES)
    out.mkdir(parents=True, exist_ok=False)

    def check(name):
        directory = proof / name
        def read(filename):
            assert Path(filename).name == filename and not (directory / filename).is_symlink()
            return (directory / filename).read_bytes()
        files, result = check_artifacts(args.work, name, read)
        assert summary["cases"][name] == result
        replay = out / name
        replay.mkdir()
        for filename, raw in files.items():
            (replay / filename).write_bytes(raw)
        with (replay / "yosys.log").open("w") as log:
            proc = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=replay,
                                  stdout=log, stderr=subprocess.STDOUT, timeout=120)
        assert proc.returncode == 0
        for filename in ("design.smt2", "elaborated.json", "elaborated.il"):
            assert (replay / filename).read_bytes() == read(filename), (name, filename)
        return name, {key: result[key] for key in ("target_assertion", "query_sha256", "model_sha256")}

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        cases = dict(pool.map(check, CONTROL.CASES))
    result = {"passed": True, "cases_checked": len(cases), "cases": cases,
              "source_reelaboration_identical": True, "queries_reconstructed": True,
              "raw_solver_answers_checked": True, "reset_reachable_claim": False,
              "independently_implemented_query_checker": False,
              "hardware_access": False, "network_access": False}
    (out / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("FAULT_CONTROLS_AUDIT PASS", len(cases), flush=True)


if __name__ == "__main__":
    main()
