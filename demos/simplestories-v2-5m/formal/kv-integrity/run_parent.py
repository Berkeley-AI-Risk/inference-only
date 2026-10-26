"""Prove source-projected guard/atomic-KV composition, with explicit cuts."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
from concurrent.futures import ThreadPoolExecutor
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


def chain(smt, top, initial, k):
    rows = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(k + 1):
        rows += [f"(declare-fun s{i} () {top}_s)", f"(assert ({top}_h s{i}))", f"(assert ({top}_u s{i}))",
                 f"(assert (= ({top}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
        if i:
            rows += [f"(assert ({top}_t s{i-1} s{i}))"]
    if initial:
        rows += [f"(assert ({top}_i s0))", f"(assert (not (|{top}_n reset_n_i| s0)))",
                 f"(assert (not (|{top}_n reset_n_i| s1)))"]
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "prior", "run"):
        ap.add_argument("--" + name, type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=16)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--negative", choices=("lost-clear", "raw-read-bypass"))
    ap.add_argument("--elaborate-only", action="store_true")
    args = ap.parse_args()
    assert 1 <= args.jobs <= 16 and 1 <= args.timeout <= 600
    here = Path(__file__).resolve().parent
    model = load(here / "parent_model.py")
    files, binding = model.derive(args.package.resolve(), args.prior.resolve(), here, args.negative)
    count = 221 + 59 + files["parent_monitor.inc.sv"].count(b"assert(")
    top, sha = model.TOP, model.sha
    commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS guard.sv page_hash.sv compress_boundary.sv atomic.sv mapper.sv parent.sv",
                f"prep -top {top} -flatten", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                f"select -assert-count {count} t:$assert", "select -assert-none t:$assume",
                "select -assert-count 2 t:$anyseq", "select -assert-count 5 t:$anyconst",
                "select -assert-count 8 t:$mem_v2", "check -assert", "write_json elaborated.json",
                "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
    files["prove.ys"] = ("\n".join(commands) + "\n").encode()
    for name in ("run_parent.py", "parent_model.py"):
        files[name] = (here / name).read_bytes()
    run = args.run.resolve()
    run.mkdir(parents=True, exist_ok=False)
    for name, raw in files.items():
        (run / name).write_bytes(raw)
    inputs = dict(binding, assertions=count, induction_length=2, timeout_seconds=args.timeout,
                  files={name: {"sha256": sha(raw), "bytes": len(raw)} for name, raw in files.items()},
                  hardware_access=False, network_access=False,
                  environment="Base reset at states 0 and 1 only; all declared private boundary inputs and SHA replies unrestricted.")
    (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2) + "\n")
    started = time.monotonic()
    print(f"PARENT_STARTED assertions={count} run={run}", flush=True)
    with (run / "yosys.log").open("w") as output:
        result = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=run, stdout=output, stderr=subprocess.STDOUT)
    records = {}
    if result.returncode == 0 and not args.elaborate_only:
        smt = (run / "design.smt2").read_text()
        labels = {}
        ranges = {}
        for name, raw in files.items():
            if name.endswith("monitor.inc.sv") and name != "monitor.inc.sv":
                containers = [name for name in ("guard.sv", "page_hash.sv", "atomic.sv", "parent.sv") if files[name].count(raw) == 1]
                assert len(containers) == 1, (name, containers)
                container = containers[0]
                first = files[container][:files[container].index(raw)].count(b"\n") + 1
                ranges[name] = (container, first, first + raw.count(b"\n"))
        for index, source in re.findall(r"^; yosys-smt2-assert (\d+) \S+ (.*)$", smt, re.M):
            locations = re.findall(r"(guard\.sv|page_hash\.sv|atomic\.sv|parent\.sv):(\d+)\.", source)
            matches = [name for name, (container, first, last) in ranges.items()
                       if any(f == container and first <= int(line) <= last for f, line in locations)]
            assert len(matches) == 1, (index, source, matches)
            labels[int(index)] = matches[0]
        assert set(labels) == set(range(count))
        needed = {
            "control_monitor.inc.sv": ["control_monitor.inc.sv"],
            "staging_monitor.inc.sv": ["control_monitor.inc.sv", "staging_monitor.inc.sv"],
            "write_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv"],
            "partial_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "partial_history_monitor.inc.sv"],
            "tag_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "tag_history_monitor.inc.sv"],
            "hash_monitor.inc.sv": ["hash_monitor.inc.sv"],
            "hash_connection_monitor.inc.sv": ["control_monitor.inc.sv", "staging_monitor.inc.sv", "hash_monitor.inc.sv", "hash_connection_monitor.inc.sv"],
            "write_hash_connection_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "hash_monitor.inc.sv", "write_hash_connection_monitor.inc.sv"],
            "epoch_monitor.inc.sv": ["epoch_monitor.inc.sv"],
            "parent_monitor.inc.sv": ["control_monitor.inc.sv", "staging_monitor.inc.sv", "write_history_monitor.inc.sv", "epoch_monitor.inc.sv", "parent_monitor.inc.sv"],
        }
        support = {str(i): sorted(j for j, name in labels.items() if name in needed[labels[i]]) for i in range(count)}
        (run / "INDUCTION-SUPPORT.json").write_text(json.dumps({"conclusion_sources": labels, "earlier_state_assertions": support}, indent=2) + "\n")
        k = 6 if args.negative else 2
        queries = {"base": "\n".join(chain(smt, top, True, k) + [
            "(assert (not (and " + " ".join(f"({top}_a s{i})" for i in range(k + 1)) + ")))", "(check-sat)"]) + "\n"}
        if args.negative:
            # A concrete boot sequence is sufficient for these wiring
            # sensitivity tests. This restricts only negative examples, never
            # a positive theorem or induction query.
            module = json.loads((run / "elaborated.json").read_text())["modules"][top]
            constraints, witness = [], {}
            for step in range(k + 1):
                witness[str(step)] = {}
                for name, port in module["ports"].items():
                    width = len(port["bits"])
                    value = int(name == "private_model_locked_i" or (name == "reset_n_i" and step >= 2) or
                                (name == "clear_i" and step == 6 and args.negative == "lost-clear") or
                                (name == "guard_rd_data" and step == 6 and args.negative == "raw-read-bypass"))
                    literal = ("true" if value else "false") if width == 1 else f"(_ bv{value} {width})"
                    constraints.append(f"(assert (= (|{top}_n {name}| s{step}) {literal}))")
                    witness[str(step)][name] = value
            needle = ("assert(!clear_i || layer_clear || !child_reset_n);" if args.negative == "lost-clear" else
                      "assert(a_kv_read_rsp_data_i == kv_read_rsp_data);")
            target_line = [i for i, line in enumerate(files["parent.sv"].decode().splitlines(), 1) if line.strip() == needle]
            assert len(target_line) == 1
            targets = re.findall(r"^; yosys-smt2-assert (\d+) \S+ parent\.sv:" + str(target_line[0]) + r"\.", smt, re.M)
            assert len(targets) == 1
            (run / "NEGATIVE-WITNESS.json").write_text(json.dumps({"inputs": witness, "target_assertion": int(targets[0])}, indent=2) + "\n")
            queries["base"] = "\n".join(chain(smt, top, True, k) + constraints + [
                f"(assert (not (|{top}_a {targets[0]}| s{k})))", "(check-sat)"]) + "\n"
        if not args.negative:
            queries.pop("base")
            queries["reset-witness"] = "\n".join(chain(smt, top, True, k) + ["(check-sat)"]) + "\n"
            for component in sorted(set(labels.values())):
                indices = sorted(i for i, name in labels.items() if name == component)
                label = "base-" + component.removesuffix("_monitor.inc.sv")
                queries[label] = "\n".join(chain(smt, top, True, k) + [
                    "(assert (not (and " + " ".join(f"(|{top}_a {j}| s{i})" for i in range(k+1) for j in indices) + ")))",
                    "(check-sat)"]) + "\n"
            for index in range(count):
                queries[f"induction-{index:03d}"] = "\n".join(chain(smt, top, False, k) + [
                    "(assert (and " + " ".join(f"(|{top}_a {j}| s{i})" for j in support[str(index)]) + "))" for i in range(k)] + [
                    f"(assert (not (|{top}_a {index}| s{k})))", "(check-sat)"]) + "\n"
        for name, query in queries.items():
            (run / (name + ".smt2")).write_text(query)
        module = json.loads((run / "elaborated.json").read_text())["modules"][top]
        def solve(pair):
            solver, name = pair
            begin = time.monotonic()
            argv = ([shutil.which("z3"), f"-T:{args.timeout}", "-smt2"] if solver == "z3" else
                    [shutil.which("cvc5"), f"--tlimit={args.timeout*1000}", "--lang=smt2"])
            label = solver + "-" + name
            with (run / (label + ".log")).open("w") as output:
                try:
                    proc = subprocess.run(argv + [str(run / (name + ".smt2"))], stdout=output,
                                          stderr=subprocess.STDOUT, timeout=args.timeout + 15)
                    code = proc.returncode
                except subprocess.TimeoutExpired:
                    code = None
            raw = (run / (label + ".log")).read_bytes()
            answers = [s for s in raw.decode().splitlines() if s in ("sat", "unsat", "unknown")]
            expected = ["sat"] if args.negative or name == "reset-witness" else ["unsat"]
            row = {"passed": code == 0 and answers == expected and b"(error " not in raw, "answers": answers,
                   "expected": expected, "exit": code, "seconds": time.monotonic() - begin,
                   "query_sha256": sha(queries[name].encode()), "log_sha256": sha(raw)}
            if not row["passed"]:
                print(label + " " + json.dumps(row), flush=True)
            if solver == "z3" and answers and answers[-1] == "sat" and name != "reset-witness":
                names = [n for n in module["netnames"] if "." not in n and not n.startswith("$")]
                query = queries[name] + "(get-value (" + " ".join(f"(|{top}_n {n}| s{i})" for i in range(k+1)
                    for n in names if f"|{top}_n {n}|" in smt) + " " + " ".join(f"(|{top}_a {j}| s{k})" for j in range(count)) + "))\n"
                (run / (label + "-model.smt2")).write_text(query)
                with (run / (label + "-model.log")).open("w") as output:
                    try:
                        subprocess.run(argv + [str(run / (label + "-model.smt2"))], stdout=output,
                                       stderr=subprocess.STDOUT, timeout=args.timeout + 15)
                    except subprocess.TimeoutExpired:
                        pass
            return label, row
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            records = dict(pool.map(solve, [(s, n) for s in ("z3", "cvc5") for n in queries]))
    unchanged = all(sha((run / name).read_bytes()) == sha(raw) for name, raw in files.items())
    expected_records = 2 if args.negative else 2 * (count + 11)
    passed = result.returncode == 0 and len(records) == expected_records and unchanged and all(r["passed"] for r in records.values())
    receipt = {"passed": passed, "assertions": count, "yosys_exit": result.returncode,
               "production_proof": passed and not args.negative, "expected_negative_detected": passed and bool(args.negative),
               "seconds": time.monotonic() - started, "inputs_sha256": sha((run / "INPUTS.json").read_bytes()),
               "source_unchanged": unchanged, "solver_results": records,
               "hardware_access": False, "network_access": False,
               "scope": "Real guard/hash-wrapper and atomic controller, source-projected core CLEAR/reset/reply gates; arbitrary private stage and attention scheduling inputs. Not actual attention arithmetic or fixed-model data provenance."}
    (run / "FINISHED.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("PARENT_FINISHED passed=" + str(passed), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
