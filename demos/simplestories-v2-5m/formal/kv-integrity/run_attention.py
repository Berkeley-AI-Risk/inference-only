"""Reset-initialized induction for actual attention K/V capture and use."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha(raw): return hashlib.sha256(raw).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", type=Path, required=True)
    ap.add_argument("--run", type=Path, required=True)
    ap.add_argument("--timeout", type=int, default=180)
    ap.add_argument("--jobs", type=int, default=16)
    args = ap.parse_args()
    assert 1 <= args.jobs <= 16 and 1 <= args.timeout <= 600
    here = Path(__file__).resolve().parent
    model = load(here / "attention_model.py")
    files, binding = model.derive(args.package.resolve(), here)
    top, count = model.TOP, files["attention_monitor.inc.sv"].count(b"assert(")
    sources = ["attention.sv"] + sorted(n for n in files if n.startswith("boundary-"))
    commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS " + " ".join(sources),
                f"prep -top {top} -flatten", "memory_map", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                f"select -assert-count {count} t:$assert", "select -assert-none t:$assume",
                "select -assert-count 1 t:$anyconst", "check -assert", "write_json elaborated.json",
                "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
    files["prove.ys"] = ("\n".join(commands) + "\n").encode()
    for name in ("run_attention.py", "attention_model.py", "parent_model.py"):
        files[name] = (here / name).read_bytes()
    run = args.run.resolve()
    run.mkdir(parents=True, exist_ok=False)
    for name, raw in files.items(): (run / name).write_bytes(raw)
    inputs = dict(binding, assertions=count, induction_length=2, timeout_seconds=args.timeout,
        files={n: {"bytes": len(raw), "sha256": sha(raw)} for n, raw in files.items()}, hardware_access=False, network_access=False)
    (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2) + "\n")
    start = time.monotonic()
    print(f"ATTENTION_STARTED assertions={count} run={run}", flush=True)
    with (run / "yosys.log").open("w") as output:
        proc = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=run, stdout=output, stderr=subprocess.STDOUT)
    records = {}
    if proc.returncode == 0:
        smt = (run / "design.smt2").read_text()
        module = json.loads((run / "elaborated.json").read_text())["modules"][top]
        def chain(initial):
            rows = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
            for i in range(3):
                rows += [f"(declare-fun s{i} () {top}_s)", f"(assert ({top}_h s{i}))", f"(assert ({top}_u s{i}))",
                         f"(assert (= ({top}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
                if i: rows += [f"(assert ({top}_t s{i-1} s{i}))"]
            if initial:
                rows += [f"(assert ({top}_i s0))", f"(assert (not (|{top}_n rst_n| s0)))", f"(assert (not (|{top}_n rst_n| s1)))"]
            return rows
        queries = {"reset-witness": "\n".join(chain(True) + ["(check-sat)"]) + "\n"}
        queries["base"] = "\n".join(chain(True) + [f"(assert (not (and ({top}_a s0) ({top}_a s1) ({top}_a s2))))", "(check-sat)"]) + "\n"
        for i in range(count):
            queries[f"induction-{i:03d}"] = "\n".join(chain(False) + [f"(assert ({top}_a s0))", f"(assert ({top}_a s1))",
                f"(assert (not (|{top}_a {i}| s2)))", "(check-sat)"]) + "\n"
        for name, query in queries.items(): (run / (name + ".smt2")).write_text(query)
        def solve(pair):
            solver, name = pair
            begin = time.monotonic()
            argv = ([shutil.which("z3"), f"-T:{args.timeout}", "-smt2"] if solver == "z3" else
                    [shutil.which("cvc5"), f"--tlimit={args.timeout*1000}", "--lang=smt2"])
            label = solver + "-" + name
            with (run / (label + ".log")).open("w") as output:
                try:
                    process = subprocess.run(argv + [str(run / (name + ".smt2"))], stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout+15)
                    code = process.returncode
                except subprocess.TimeoutExpired: code = None
            raw = (run / (label + ".log")).read_bytes()
            answers = [line for line in raw.decode().splitlines() if line in ("sat", "unsat", "unknown")]
            expected = ["sat"] if name == "reset-witness" else ["unsat"]
            row = dict(passed=code == 0 and answers == expected and b"(error " not in raw,
                       exit=code, answers=answers, expected=expected, seconds=time.monotonic()-begin,
                       query_sha256=sha(queries[name].encode()), log_sha256=sha(raw))
            if not row["passed"]: print(label + " " + json.dumps(row), flush=True)
            if solver == "z3" and answers == ["sat"] and name != "reset-witness":
                names = [n for n, v in module["netnames"].items() if not v["hide_name"] and "." not in n and
                         len(v["bits"]) <= 128 and f"|{top}_n {n}|" in smt]
                diagnostic = (queries[name] + "(get-value (" + " ".join(f"(|{top}_n {n}| s{i})" for i in range(3) for n in names) + " " +
                    " ".join(f"(|{top}_a {j}| s2)" for j in range(count)) + "))\n")
                (run / (label + "-model.smt2")).write_text(diagnostic)
                with (run / (label + "-model.log")).open("w") as output:
                    subprocess.run(argv + [str(run / (label + "-model.smt2"))], stdout=output, stderr=subprocess.STDOUT, timeout=args.timeout+15)
            return label, row
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            records = dict(pool.map(solve, [(s, n) for s in ("z3", "cvc5") for n in queries]))
    unchanged = all(sha((run / n).read_bytes()) == sha(raw) for n, raw in files.items())
    passed = proc.returncode == 0 and len(records) == 2*(count+2) and unchanged and all(r["passed"] for r in records.values())
    result = dict(passed=passed, assertions=count, yosys_exit=proc.returncode, solver_results=records,
                  seconds=time.monotonic()-start, inputs_sha256=sha((run / "INPUTS.json").read_bytes()), source_unchanged=unchanged,
                  scope=binding["scope"], hardware_access=False, network_access=False)
    (run / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("ATTENTION_FINISHED passed=" + str(passed), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__": main()
