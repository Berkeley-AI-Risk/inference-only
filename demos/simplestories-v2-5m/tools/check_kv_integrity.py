#!/usr/bin/env python3
"""Replay the protected K/V history, projected-parent and attention safety checks."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

if not __debug__ or sys.flags.optimize:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")
if not (sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode):
    raise SystemExit("Run this checker with Python -I -S -B.")


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def check_image_binding(read, expected, manifest):
    """Bind the proof's sources to the recorded build, not to a live FPGA."""
    inventory = json.loads(read("host-app/hardware-inputs-kv-protected.json"))
    build = json.loads(read("prebuilt/kv-protected/BUILD.json"))
    prefix = "variants/kv-protected/hardware/"
    sources = expected["production_sources"]
    assert sources
    for name, digest in sources.items():
        assert name.startswith(prefix) and inventory[name[len(prefix):]] == digest, name
    canonical = (json.dumps(inventory, sort_keys=True, separators=(",", ":")) + "\n").encode()
    assert sha(canonical) == build["hardware_inputs_sha256"]
    assert build["schema"] == "fixed-fpga-local-build-v1" and build["variant"] == "kv-protected"
    assert all(build.get(key) is True for key in ("flow_completed", "source_inputs_verified", "source_inputs_unchanged"))
    assert build["image_relative_path"] == "project/impl/pnr/shared_product.fs"
    image_name = "prebuilt/kv-protected/project/impl/pnr/shared_product.fs"
    assert build["image_sha256"] == manifest[image_name]["sha256"] == sha(read(image_name))
    return {"build_receipt_image_sha256": build["image_sha256"],
            "build_receipt_hardware_inputs_sha256": build["hardware_inputs_sha256"],
            "proof_sources_in_build": len(sources), "attestation": False,
            "synthesis_equivalence_proved": False}


def check_tool_versions(expected, resolved):
    """Reject a mismatched toolchain before generating or solving queries."""
    actual = {}
    for name, flag in (("yosys", "-V"), ("z3", "-version"), ("cvc5", "--version")):
        result = subprocess.run([resolved[name], flag], capture_output=True, text=True, check=True)
        actual[name] = result.stdout.splitlines()[0]
    if actual != expected:
        differences = [f"{name}: expected {expected.get(name)!r}; found {value!r}"
                       for name, value in actual.items() if expected.get(name) != value]
        raise SystemExit("Recorded toolchain mismatch; no proofs started.\n" + "\n".join(differences))
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--work", type=Path)
    parser.add_argument("--recorded-only", action="store_true", help="Check recorded source bindings only; do not run solvers.")
    parser.add_argument("--jobs", type=int, default=min(16, max(1, (os.cpu_count() or 2)//2)), help="Solver workers per positive proof (1–16); default at most half the logical CPUs.")
    parser.add_argument("--serial-stages", action="store_true", help="Do not overlap independent proof stages.")
    for name in ("yosys", "z3", "cvc5"):
        parser.add_argument("--" + name, type=Path, help="Explicit executable; otherwise use PATH.")
    parser.add_argument("--timeout", type=int, default=300, help="Per-query seconds (1–600); unknown never passes.")
    args = parser.parse_args()
    assert 1 <= args.jobs <= 16 and 1 <= args.timeout <= 600
    package = args.package.resolve(strict=True)
    manifest_raw = (package / "MANIFEST.json").read_bytes()
    manifest = json.loads(manifest_raw)["files"]
    formal = package / "formal/kv-integrity"
    checked = {}

    def read(name):
        path = package / name
        assert not path.is_symlink()
        raw = path.read_bytes()
        assert sha(raw) == manifest[name]["sha256"] and len(raw) == manifest[name]["bytes"], name
        checked[name] = sha(raw)
        return raw

    expected = json.loads(read("formal/kv-integrity/expected.json"))
    for name, digest in expected["production_sources"].items():
        assert sha(read(name)) == digest, name
    for name, digest in expected.get("verification_sources", {}).items():
        assert sha(read(name)) == digest, name
    for name, digest in expected["replay_sources"].items():
        assert sha(read(name)) == digest, name
    assert set(expected["recorded_results"]) == {"history", "parent", "attention"}
    for name, row in expected["recorded_results"].items():
        assert row["passed"] and type(row["assertions"]) is int and row["assertions"] > 0
        assert row["both_solvers_complete"] and row["assumption_cells"] == 0
    assert expected["whole_machine_refinement"] is False
    assert expected["sha_compression_correctness_proved"] is False
    image_binding = check_image_binding(read, expected, manifest)
    if args.recorded_only:
        assert args.work is None
        print(json.dumps(image_binding, sort_keys=True))
        print("KV_INTEGRITY_RECORDED_BINDINGS_PASSED (no solvers run)")
        return
    assert args.work is not None, "Provide --work outside the source package, or --recorded-only."
    work = args.work.resolve()
    assert not work.is_relative_to(package)
    resolved = {}
    for tool in ("yosys", "z3", "cvc5"):
        selected = getattr(args, tool)
        executable = str(selected.resolve(strict=True)) if selected else shutil.which(tool)
        if not executable or not os.access(executable, os.X_OK):
            raise SystemExit("Missing executable: " + tool)
        resolved[tool] = executable
    tool_versions = check_tool_versions(expected["tool_versions"], resolved)
    work.mkdir(parents=True, exist_ok=False)
    # Children use these exact executables via a private PATH directory.
    tool_dir = work / "tool-bin"
    tool_dir.mkdir()
    for name, executable in resolved.items():
        (tool_dir / name).symlink_to(executable)
    (work / "wrapper.py").write_bytes(Path(__file__).read_bytes())
    python = [sys.executable, "-I", "-S", "-B"]
    executions = {}

    def execute(item):
        label, argv = item
        started = time.monotonic()
        print("KV_INTEGRITY_STAGE " + label, flush=True)
        environment = dict(os.environ, KV_FORMAL_WORK=str(work), PATH=str(tool_dir) + os.pathsep + os.environ.get("PATH", ""))
        with (work / (label + ".log")).open("w") as log:
            result = subprocess.run(python + argv, stdout=log, stderr=subprocess.STDOUT, env=environment)
        row = {"exit": result.returncode, "seconds": time.monotonic() - started,
               "log_sha256": sha((work / (label + ".log")).read_bytes())}
        if result.returncode != 0:
            raise RuntimeError(f"{label} failed; inspect {work / (label + '.log')}")
        return label, row

    def group(items):
        with ThreadPoolExecutor(max_workers=1 if args.serial_stages else len(items)) as pool:
            executions.update(dict(pool.map(execute, items)))

    def run(name, script, flags=()):
        return name, [str(formal / script), "--package", str(package), "--run", str(work / name),
                      "--timeout", str(args.timeout), *flags]

    history = ["--staging", "--compose-hash", "--write-history", "--partial-history", "--tag-history", "--quiet"]
    workers = ["--jobs", str(args.jobs)]
    group([run("history", "run_control.py", history + ["--split", "--component-hypotheses"] + workers),
           run("attention", "run_attention.py", workers)])
    parent = ["--prior", str(work / "history")]
    group([run("parent", "run_parent.py", parent + workers),
           run("history-negative-clear", "run_control.py", history + ["--negative-clear"]),
           run("history-negative-data", "run_control.py", history + ["--negative-write-data"]),
           run("parent-negative-clear", "run_parent.py", parent + ["--negative", "lost-clear"]),
           run("parent-negative-bypass", "run_parent.py", parent + ["--negative", "raw-read-bypass"])])
    group([
        ("history-audit", [str(formal / "audit_history.py"), "--package", str(package), "--proof", str(work / "history"),
                           "--negative", str(work / "history-negative-clear"), "--negative", str(work / "history-negative-data"),
                           "--out", str(work / "history-audit")]),
        ("parent-audit", [str(formal / "audit_parent.py"), "--package", str(package), "--prior", str(work / "history"),
                          "--proof", str(work / "parent"), "--negative", str(work / "parent-negative-clear"),
                          "--negative", str(work / "parent-negative-bypass"), "--out", str(work / "parent-audit")]),
        ("attention-audit", [str(formal / "audit_attention.py"), "--package", str(package), "--proof", str(work / "attention"),
                             "--out", str(work / "attention-audit")]),
    ])
    label, result = execute(("audit-regressions", ["-m", "unittest", "discover", "-s", str(formal), "-p", "test_*_auditor.py", "-v"]))
    executions[label] = result
    regression_log = (work / "audit-regressions.log").read_text()
    assert "Ran 44 tests" in regression_log and "skipped" not in regression_log.lower()
    label, result = execute(("fault-controls", [str(formal / "check_fault_controls.py"),
        "--work", str(work), "--out", str(work / "fault-controls"),
        "--jobs", str(min(4, args.jobs)), "--timeout", str(args.timeout)]))
    executions[label] = result
    label, result = execute(("fault-controls-audit", [str(formal / "audit_fault_controls.py"),
        "--work", str(work), "--proof", str(work / "fault-controls"),
        "--out", str(work / "fault-controls-audit"), "--jobs", str(min(4, args.jobs))]))
    executions[label] = result
    label, result = execute(("fault-audit-regressions", ["-m", "unittest", "discover",
        "-s", str(formal), "-p", "test_fault_controls_audit.py", "-v"]))
    executions[label] = result
    fault_test_log = (work / "fault-audit-regressions.log").read_text()
    assert "Ran 8 tests" in fault_test_log and "skipped" not in fault_test_log.lower()
    for stage, names in expected["generated_artifacts"].items():
        for name, digest in names.items():
            assert sha((work / stage / name).read_bytes()) == digest, f"Generated identity mismatch: {stage}/{name}; use the recorded toolchain."
    assert (package / "MANIFEST.json").read_bytes() == manifest_raw
    assert all(sha((package / name).read_bytes()) == digest for name, digest in checked.items())
    stages = {name: json.loads((work / name / "FINISHED.json").read_bytes()) for name in ("history", "parent", "attention")}
    for name, stage in stages.items():
        assert stage["passed"] and stage["assertions"] == expected["recorded_results"][name]["assertions"]
        assert set(stage["solver_results"]) == set(expected["recorded_results"][name]["solver_results"])
        assert all(row["passed"] for row in stage["solver_results"].values())
    negatives = {name: json.loads((work / name / "FINISHED.json").read_bytes()) for name in executions if "-negative-" in name}
    assert len(negatives) == 4 and all(row["passed"] and row["expected_negative_detected"] for row in negatives.values())
    sensitivity = json.loads((work / "fault-controls/FINISHED.json").read_bytes())
    assert sensitivity["passed"] and len(sensitivity["cases"]) == 23
    assert all(row["passed"] and not row["reset_reachable_claim"] for row in sensitivity["cases"].values())
    fault_audit = json.loads((work / "fault-controls-audit/FINISHED.json").read_bytes())
    assert fault_audit["passed"] and fault_audit["cases_checked"] == 23
    assert set(sensitivity["cases"]) == set(expected["fault_controls"]) == set(fault_audit["cases"])
    for name, row in sensitivity["cases"].items():
        identity = {key: row[key] for key in ("target_assertion", "query_sha256", "model_sha256")}
        assert identity == expected["fault_controls"][name] == fault_audit["cases"][name], name
    result = {"passed": True, "package_manifest_sha256": sha(manifest_raw), "tool_versions": tool_versions,
              "assertions": {name: stage["assertions"] for name, stage in stages.items()},
              "solver_queries": {name: len(stage["solver_results"]) for name, stage in stages.items()},
              "both_solvers_complete": True, "negative_controls_detected": len(negatives),
              "induction_fault_controls_detected": len(sensitivity["cases"]),
              "audit_regression_tests": 44, "fault_audit_regression_tests": 8,
              "fault_control_artifacts_audited": True, "recorded_generated_artifacts_match": True,
              "source_files_unchanged": True, "checked_sources": checked, "executions": executions,
              "hardware_access": False, "network_access": False, "whole_machine_refinement": False,
              "guard_attention_joint_theorem": False, "sha_compression_correctness_proved": False,
              **image_binding}
    (work / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("KV_INTEGRITY_REPLAY_FINISHED passed=True", flush=True)


if __name__ == "__main__":
    main()
