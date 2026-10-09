"""Directed real-bank simulation plus five deliberately faulty controls.

The compressor is a controllable fixture, not an implementation of SHA.
These reachable simulation witnesses complement, but do not replace, induction.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

BANK_SHA = "ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    bank = (args.package / "hardware/project/bank.sv").read_bytes()
    assert sha(bank) == BANK_SHA
    tb = (here / "bank_tb.sv").read_bytes()
    mutations = {
        "digest-bypass": (b"wire digest_error=state_q==COMPARE && !(&digest_match_q);",
                          b"wire digest_error=1'b0;", "BAD_DIGEST_ACCEPTED"),
        "early-verified": (b"assign verified_o=state_q==READY && !fault_o;",
                           b"assign verified_o=(state_q==READY || state_q==HASH) && !fault_o;", "PREMATURE_VERIFIED"),
        "sealed-write": (b"wire memory_write=fill_fire || state_q==ZERO;",
                         b"wire memory_write=fill_fire || state_q==ZERO || state_q==READY;", "SEALED_WRITE"),
        "cancel-clears-fault": (b"end else if(fault_o || protocol_error || digest_error",
            b"end else if(fault_o && cancel_read_i) begin state_q<=EMPTY; fault_o<=0; response_valid_q<=0;\n"
            b"        end else if(fault_o || protocol_error || digest_error", "FAULT_CLEARED_BY_CANCEL"),
        "wrong-sha-bytes": (b"bytes_big_endian[255-i*8 -: 8]=word[i*8 +: 8];",
                            b"bytes_big_endian[i*8 +: 8]=word[i*8 +: 8];", "SHA_BLOCK_MISMATCH"),
    }
    variants = {"good": (bank, None)}
    for name, (old, new, expected) in mutations.items():
        assert bank.count(old) == 1
        variants[name] = (bank.replace(old, new), expected)
    run = args.run.resolve()
    run.mkdir(parents=True, exist_ok=False)
    (run / "runner.py").write_bytes(Path(__file__).read_bytes())
    (run / "testbench.sv").write_bytes(tb)
    inputs = {"production_sha256": sha(bank), "testbench_sha256": sha(tb),
              "runner_sha256": sha(Path(__file__).read_bytes()), "hardware_access": False,
              "mutations": {name: {"old": old.decode(), "new": new.decode(), "expected": expected}
                            for name, (old, new, expected) in mutations.items()}}
    (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2)+"\n")

    def check(item):
        name, (source, expected) = item
        stage = run / name
        stage.mkdir()
        (stage / "bank.sv").write_bytes(source)
        (stage / "tb.sv").write_bytes(tb)
        with (stage / "compile.log").open("w") as output:
            compile_result = subprocess.run([shutil.which(args.iverilog), "-g2012", "-s", "bank_tb",
                "-o", "simulation.vvp", "bank.sv", "tb.sv"], cwd=stage, stdout=output,
                stderr=subprocess.STDOUT, timeout=60)
        result = None
        if compile_result.returncode == 0:
            with (stage / "simulation.log").open("w") as output:
                result = subprocess.run([shutil.which(args.vvp), "simulation.vvp"], cwd=stage,
                    stdout=output, stderr=subprocess.STDOUT, timeout=60)
        log = (stage / "simulation.log").read_text() if result is not None else ""
        if expected is None:
            passed = result is not None and result.returncode == 0 and "BANK_SCENARIOS_PASS scenarios=10 hash_blocks=195" in log and "FATAL" not in log
        else:
            passed = result is not None and result.returncode != 0 and expected in log and "BANK_SCENARIOS_PASS" not in log
        row = {"passed": passed, "source_sha256": sha(source), "compile_exit": compile_result.returncode,
               "simulation_exit": result.returncode if result is not None else None,
               "expected_fault": expected, "log_sha256": sha(log.encode())}
        print("BANK_SCENARIO_"+name+" "+json.dumps(row), flush=True)
        return name, row

    with ThreadPoolExecutor(max_workers=6) as pool:
        records = dict(pool.map(check, variants.items()))
    passed = all(row["passed"] for row in records.values())
    receipt = {"passed": passed, "results": records, "inputs_sha256": sha((run/"INPUTS.json").read_bytes()),
               "scope": "Directed simulation of real bank RAM/control with a controllable compressor fixture.",
               "hardware_access": False, "network_access": False}
    (run / "FINISHED.json").write_text(json.dumps(receipt, indent=2)+"\n")
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
