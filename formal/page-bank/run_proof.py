"""Source-bound page-bank lifecycle proof; real RAM, arbitrary SHA replies.

Component safety only, not cryptographic or whole-machine proof. Only reset
initializes the base. All other inputs and all SHA replies remain free.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

TOP = "board1_verified_page_bank"
BANK_SHA = "ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1"
SHA_SHA = "7e4992bdf5c7a6e6405979a01a351254d4a84fb8c0e2e47afcbe3fc4ff7d3610"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--induction", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--split", action="store_true")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--yosys", default="yosys")
    parser.add_argument("--z3", default="z3")
    parser.add_argument("--cvc5", default="cvc5")
    args = parser.parse_args()
    assert 2 <= args.induction <= 8 and 1 <= args.jobs <= 16
    assert 1 <= args.timeout <= 600
    here = Path(__file__).resolve().parent
    package = args.package.resolve()
    manifest_raw = (package / "MANIFEST.json").read_bytes()
    manifest = json.loads(manifest_raw)["files"]
    bank = (package / "hardware/project/bank.sv").read_bytes()
    sha = (package / "hardware/project/sha.sv").read_bytes()
    assert digest(bank) == BANK_SHA == manifest["hardware/project/bank.sv"]["sha256"]
    assert digest(sha) == SHA_SHA == manifest["hardware/project/sha.sv"]["sha256"]
    monitor = (here / "bank_monitor.inc.sv").read_bytes()
    stub = (here / "sha_boundary.sv").read_bytes()
    assert b"assume(" not in monitor + stub
    assert bank.count(b"\nendmodule") == 1
    instrumented = bank.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
    count = monitor.count(b"assert(")
    files = {"production.sv": bank, "production-sha-not-elaborated.sv": sha,
             "bank.sv": instrumented, "monitor.inc.sv": monitor,
             "sha_boundary.sv": stub, "runner.py": Path(__file__).read_bytes()}
    commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS bank.sv sha_boundary.sv",
                f"prep -top {TOP} -flatten", "async2sync", "chformal -lower",
                "opt_clean", "dffunmap", f"select -assert-count {count} t:$assert",
                "select -assert-none t:$assume", "select -assert-count 3 t:$anyseq",
                "select -assert-count 1 t:$anyconst", "select -assert-count 1 t:$mem_v2",
                "check -assert", "write_json elaborated.json", "write_rtlil elaborated.il",
                "write_smt2 -wires design.smt2"]
    files["prove.ys"] = ("\n".join(commands) + "\n").encode()
    run = args.run.resolve()
    run.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        (run / name).write_bytes(data)
    inputs = {"manifest_sha256": digest(manifest_raw), "bank_sha256": BANK_SHA,
              "sha_source_not_elaborated_sha256": SHA_SHA, "assertions": count,
              "files": {name: {"sha256": digest(data), "bytes": len(data)}
                        for name, data in files.items()},
              "induction_length": args.induction, "timeout_seconds": args.timeout,
              "sha_boundary": {"busy_o": 1, "done_o": 1, "state_o": 256},
              "ram": {"words": 128, "word_bits": 256, "replacement": False},
              "environment": "Base reset at states 0 and 1; no other input constraints.",
              "hardware_access": False, "network_access": False}
    (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2) + "\n")
    started = time.monotonic()
    print(f"BANK_PROOF_STARTED assertions={count} run={run}", flush=True)
    with (run / "yosys.log").open("w") as output:
        result = subprocess.run([shutil.which(args.yosys), "-Q", "prove.ys"], cwd=run,
                                stdout=output, stderr=subprocess.STDOUT)
    records = {}
    if result.returncode == 0:
        module = json.loads((run / "elaborated.json").read_text())["modules"][TOP]
        memories = [c for c in module["cells"].values() if c["type"] == "$mem_v2"]
        assert len(memories) == 1
        assert int(memories[0]["parameters"]["WIDTH"], 2) == 256
        assert int(memories[0]["parameters"]["SIZE"], 2) == 128
        smt = (run / "design.smt2").read_text()
        assert len(re.findall(r"^; yosys-smt2-assert ", smt, re.M)) == count
        k = args.induction

        def chain(initial):
            parts = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
            for step in range(k + 1):
                parts += [f"(declare-fun s{step} () {TOP}_s)",
                          f"(assert ({TOP}_h s{step}))", f"(assert ({TOP}_u s{step}))",
                          f"(assert (= ({TOP}_is s{step}) {'true' if initial and step == 0 else 'false'}))"]
                if step:
                    parts += [f"(assert ({TOP}_t s{step-1} s{step}))"]
            if initial:
                parts += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n| s0)))",
                          f"(assert (not (|{TOP}_n reset_n| s1)))"]
            return parts

        queries = {"base": "\n".join(chain(True) + ["(check-sat)",
            "(assert (not (and " + " ".join(f"({TOP}_a s{i})" for i in range(k+1)) + ")))",
            "(check-sat)"]) + "\n"}
        prefix = chain(False) + [f"(assert ({TOP}_a s{i}))" for i in range(k)]
        if args.split:
            for index in range(count):
                queries[f"induction-{index:02d}"] = "\n".join(prefix + [
                    f"(assert (not (|{TOP}_a {index}| s{k})))", "(check-sat)"]) + "\n"
        else:
            queries["induction"] = "\n".join(prefix + [f"(assert (not ({TOP}_a s{k})))",
                                                        "(check-sat)"]) + "\n"
        for name, query in queries.items():
            (run / f"{name}.smt2").write_text(query)

        def solve(item):
            solver, name = item
            begin = time.monotonic()
            argv = ([shutil.which(args.z3), f"-T:{args.timeout}", "-smt2"] if solver == "z3" else
                    [shutil.which(args.cvc5), f"--tlimit={args.timeout * 1000}", "--lang=smt2", "--incremental"])
            label = solver + "-" + name
            with (run / f"{label}.log").open("w") as output:
                proc = subprocess.run(argv + [str(run / f"{name}.smt2")], stdout=output,
                                      stderr=subprocess.STDOUT, timeout=args.timeout + 30)
            log = (run / f"{label}.log").read_text()
            answers = [line for line in log.splitlines() if line in ("sat", "unsat", "unknown")]
            expected = ["sat", "unsat"] if name == "base" else ["unsat"]
            row = {"passed": proc.returncode == 0 and answers == expected and "(error " not in log,
                   "exit": proc.returncode, "answers": answers, "seconds": time.monotonic()-begin,
                   "query_sha256": digest(queries[name].encode()), "log_sha256": digest(log.encode())}
            if solver == "z3" and answers and answers[-1] == "sat":
                names = ["reset_n", "state_q", "fault_o", "fill_count_q", "valid_words_q",
                         "block_q", "f_seen", "f_address", "f_written", "f_checked", "f_digest_equal",
                         "f_read_seen", "f_read_target", "f_consumer_pending", "response_valid_q",
                         "begin_fire", "fill_fire", "read_fire", "protocol_error", "digest_error"]
                diagnostic = queries[name] + "(get-value (" + " ".join(
                    f"(|{TOP}_n {wire}| s{i})" for i in range(k+1) for wire in names) + " " + " ".join(
                    f"(|{TOP}_a {i}| s{k})" for i in range(count)) + "))\n"
                (run / f"{label}-countermodel.smt2").write_text(diagnostic)
                with (run / f"{label}-countermodel.log").open("w") as output:
                    subprocess.run(argv + [str(run / f"{label}-countermodel.smt2")], stdout=output,
                                   stderr=subprocess.STDOUT, timeout=args.timeout+30)
            print(f"BANK_PROOF_{label} " + json.dumps(row), flush=True)
            return label, row

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            records = dict(pool.map(solve, [(solver, name) for solver in ("z3", "cvc5") for name in queries]))
    unchanged = all(digest((run / name).read_bytes()) == digest(data) for name, data in files.items())
    expected_count = 2 * (count+1 if args.split else 2)
    passed = result.returncode == 0 and len(records) == expected_count and unchanged and all(
        row["passed"] for row in records.values())
    receipt = {"passed": passed, "assertions": count, "yosys_exit": result.returncode,
               "seconds": time.monotonic()-started, "inputs_sha256": digest((run / "INPUTS.json").read_bytes()),
               "source_unchanged": unchanged, "solver_results": records,
               "scope": "Page-bank control, sealed real RAM and digest-comparison admission only; SHA compressor replies arbitrary.",
               "hardware_access": False, "network_access": False}
    (run / "FINISHED.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("BANK_PROOF_FINISHED passed=" + str(passed), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
