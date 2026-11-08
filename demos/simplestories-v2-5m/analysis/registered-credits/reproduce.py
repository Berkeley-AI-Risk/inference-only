"""Recompute the recorded ratings and ledger, or rebuild the complete local evidence."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PYTHON = [sys.executable, "-I", "-S", "-B"]


def read(path):
    return json.loads(path.read_bytes())


def check_hashes(root, manifest):
    for name, expected in read(manifest).items():
        actual = hashlib.sha256((root / name).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"hash mismatch for {name}")


def run_stage(work, checkout, name, script, output, *args):
    directory = work / name
    print(f"Running {name}/{script}", file=sys.stderr, flush=True)
    command = PYTHON + [str(directory / script), str(checkout), *map(str, args)]
    if output:
        with (directory / output).open("w") as out:
            subprocess.run(command, cwd=directory, stdout=out, check=True)
        read(directory / output)
    else:
        subprocess.run(command, cwd=directory, stdout=sys.stderr, check=True)


def verify_native(run):
    directory = run / "support-sites"
    logs = directory / "native-runs"
    spec = importlib.util.spec_from_file_location("boot_capture", directory / "replay.py")
    capture = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(capture)

    def verified(path):
        rec = read(path)
        argv = json.dumps(rec["argv"], ensure_ascii=True, separators=(",", ":")).encode()
        log = path.parent / rec["merged_log"]
        assert rec["status"] == "exited" and rec["returncode"] == 0
        assert hashlib.sha256(argv).hexdigest() == rec["argv_sha256"]
        assert capture.file_hash(log) == rec["merged_log_sha256"] and log.stat().st_size == rec["merged_log_bytes"]
        return rec, log

    build, _ = verified(logs / "build.json")
    compiler_records = [verified(logs / path)[0] for path in build["compiler_receipts"]]
    assert compiler_records and all(rec["argv"][0] == build["compiler_path"] for rec in compiler_records)
    assert any("-c" in rec["argv"] for rec in compiler_records)
    assert any("-c" not in rec["argv"] and "-o" in rec["argv"] for rec in compiler_records)
    for token in (0, 1, 64):
        rec, log = verified(logs / f"token-{token}.json")
        assert rec["argv"][1:] == ["+IMAGE_MEMH=image.memh", "+ZERO_STALL", f"+TOKEN={token}"]
        assert rec["executable_sha256"] == build["model_binary_sha256"]
        trace_path = directory / rec["trace_file"]
        assert capture.file_hash(trace_path) == rec["trace_sha256"]
        assert trace_path.read_bytes() == capture.extract_trace(log)
    return len(compiler_records)


def reproduce(work, checkout, full):
    source = HERE / "evidence"
    shutil.copytree(source, work)
    if full:
        for record in [*work.rglob("*.json"), *work.rglob("*.trace")]:
            record.unlink()
    run_stage(work, checkout, "attention-accumulators", "check.py", "result.json")
    if full:
        run_stage(work, checkout, "attention-accumulators", "cadence.py", "cadence-result.json")
        run_stage(work, checkout, "projection-lanes", "check.py", "result.json")
        run_stage(work, checkout, "joint-cadence", "check.py", "result.json")
        run_stage(work, checkout, "remaining-datapath", "check.py", "result.json")
    run_stage(work, checkout, "support-sites", "check.py", "native-result.json")
    native_calls = None
    if full:
        run_stage(work, checkout, "support-sites", "owners.py", "owners-result.json")
        run_stage(work, checkout, "support-sites", "replay.py", None, work / "support-sites")
        native_calls = verify_native(work)
    run_stage(work, checkout, "support-sites", "ledger.py", "result.json", work / "support-sites")
    ledger = read(work / "support-sites/result.json")
    rating = read(work / "attention-accumulators/result.json")
    assert ledger == read(source / "support-sites/result.json"), "ledger or observed trace changed"
    assert rating["R_greedy_disagreements"] == 61 and rating["R_batch"] == 32768
    gross = rating["clock_hz"] * 128 * 682 / 747
    factor = gross / rating["accounting_normalizer_H"] * rating["R_fixed128"] / rating["F_fixed128"]
    assert gross == ledger["sustained_ops_s"]
    assert abs(factor - ledger["gross_proxy_at_fixed_context128"]) < 1e-14
    print(json.dumps({"mode": "full" if full else "records", "sites": ledger["covered_mapped_sites"],
        "F": rating["F_fixed128"], "R": rating["R_fixed128"], "H": rating["accounting_normalizer_H"],
        "sustained_gross_per_second": gross, "proxy": factor,
        "tokens_by_prompt": {k: v["result_token"] for k, v in ledger["booted_runs"].items()},
        "checked_cxx_invocations": native_calls, "whole_device_training_factor": ledger["whole_device_certified_training_factor"]}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("records", "full"))
    parser.add_argument("checkout", type=Path)
    parser.add_argument("--keep", type=Path, help="write regenerated evidence to this new directory")
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    check_hashes(checkout, HERE / "PUBLIC-INPUTS.json")
    check_hashes(HERE, HERE / "EVIDENCE-SHA256.json")
    if args.keep:
        target = args.keep.resolve()
        if target.exists():
            parser.error("--keep requires a new directory")
        reproduce(target, checkout, args.mode == "full")
    else:
        with tempfile.TemporaryDirectory(prefix="greedy90-") as folder:
            reproduce(Path(folder) / "evidence", checkout, args.mode == "full")


if __name__ == "__main__":
    main()
