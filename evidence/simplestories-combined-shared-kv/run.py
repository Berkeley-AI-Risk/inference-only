"""Build and run eight signed SimpleStories commands on the shared K/V implementation."""

import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import re
import runpy
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage import HERE, check_inputs, checked_bytes

TRACE_PREFIXES = ("NUMERICAL_TOKEN ", "LEASE ", "CLEAR_DRAIN_COMPLETE ", "ACTUAL_A1_ROLE_CAPTURED ")


def validate_case(lines, expected):
    markers = [line for line in lines if line.startswith("PASS_")]
    if markers != [expected["marker"]]:
        raise ValueError(f"Unexpected case markers: {markers}")
    events = [line for line in lines if line.startswith(TRACE_PREFIXES)]
    if events != expected["events"]:
        raise ValueError("Public, lease, capture or drain events differ from the matched schedule")
    tokens = [int(m[1]) for line in lines if (m := re.match(r"^NUMERICAL_TOKEN token=(\d+)\b", line))]
    if tokens != expected["tokens"]:
        raise ValueError(f"Unexpected token sequence: {tokens}")
    return {"marker": markers[0], "tokens": tokens}


def reference_checks(root, spec):
    directory = root / "reference"
    for name, digest in spec["reference_inputs"].items():
        checked_bytes((directory / name).read_bytes(), digest)
    fixtures = directory / "FIXTURES.json"
    values = json.loads(checked_bytes(fixtures.read_bytes(), spec["fixture_manifest_sha256"]))
    check_role = runpy.run_path(str(directory / "reference_check.py"))["check_role"]
    return values, fixtures, check_role


# Each tuple names a real greedy position in a fixture independently regenerated from A or B.
OUTPUTS = {
    "0": (("A", 0), ("A", 1)), "1": (), "2": (),
    "5": (("A", 0), ("B", 0), ("B", 1)), "6": (("A", 0), ("B", 0)),
    "8": (("A", 0),), "9": (("A", 0),), "10": (("A", 0),),
}


def model_events(lines, number, fixtures, observation):
    expected_outputs = [fixtures["models"][m]["tokens"][i] for m, i in OUTPUTS[number]]
    if observation["tokens"] != expected_outputs:
        raise ValueError(f"Case {number} disagrees with the independent model")
    boot_labels = []
    for line in lines:
        if line.startswith(("BOOT_A ", "BOOT_MODEL ")):
            flags = dict(item.split("=", 1) for item in line.split()[1:])
            for name in ("real_manifest", "real_AES_CTR", "full_image", "all_signed_pages", "fixed_LUTs", "norms"):
                if flags.get(name) != "1":
                    raise ValueError(f"Case {number} has incomplete boot qualification: {name}")
        if line.startswith("BOOT_MODEL "):
            fields = dict(item.split("=", 1) for item in line.split()[1:])
            model = fields["label"]
            if fields["model"] != fixtures["models"][model]["model_commitment"]:
                raise ValueError(f"Boot commitment differs for {model}")
            boot_labels.append(model)
        elif line.startswith("BOOT_A "):
            boot_labels.append("A")
    expected_boots = ["A", "B"] if number in ("5", "6") else ["A"]
    if boot_labels != expected_boots:
        raise ValueError(f"Unexpected boot sequence in case {number}: {boot_labels}")
    contexts = [s.rsplit("context=", 1)[1] for s in lines if s.startswith("LEASE ")]
    leases = expected_boots if number != "0" else ["A", "A"]
    if contexts != [fixtures["contexts"][m + "-e1"] for m in leases]:
        raise ValueError(f"Unexpected accepted lease context in case {number}")


def authenticate(captures, expected, fixtures_file, check_role):
    records = {}
    for model in ("A", "B"):
        path = captures / f"actual-{model}1-role.memh"
        observed = check_role(path, model, 1, fixtures_file)
        fields = expected["captures"][model]
        if {key: observed[key] for key in fields} != fields:
            raise ValueError(f"Authenticated record differs for model {model}")
        records[model] = {"record_sha256": observed["native_capture_sha256"],
                          "plaintext_sha256": observed["plaintext_sha256"]}
    return records


def record(path, data):
    temp = path.with_name("." + path.name + ".tmp")
    temp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    temp.replace(path)


def check_case(log, number, expected, fixtures):
    lines = log.read_text().splitlines()
    observation = validate_case(lines, expected["cases"][number])
    model_events(lines, number, fixtures, observation)
    return observation


def check_recorded(root, spec, expected):
    fixtures, fixtures_file, check_role = reference_checks(root, spec)
    saved = HERE / "recorded"
    evidence = json.loads((HERE / "MEASUREMENT.json").read_bytes())
    results = {}
    for suite in spec["suite_order"]:
        branch = evidence["suites"][suite]
        if branch["build_exit"] != 0:
            raise ValueError(f"Recorded build did not exit cleanly for {suite}")
        plan = spec["suites"][suite]
        deck = root / suite
        check_inputs(deck, {**spec["common"], **plan["inputs"]})
        check_inputs(deck / "fixtures", plan["fixtures"])
        for case in plan["cases"]:
            number = str(case["number"])
            row = branch["cases"][number]
            if row["native_exit"] != 0 or row["raw_wait_status"] != 0:
                raise ValueError(f"Recorded native process did not exit cleanly for case {number}")
            log = saved / f"case-{number}.log"
            checked_bytes(log.read_bytes(), row["log_sha256"])
            results[number] = check_case(log, number, expected, fixtures)
    records = authenticate(saved, expected, fixtures_file, check_role)
    return {"mode": "recorded", "cases": results, "captures": records}


def native_process(command, cwd, phase):
    phase.mkdir()
    log = phase / "native.log"
    start = time.monotonic()
    with log.open("xb") as output:
        completed = subprocess.run(command, cwd=cwd, stdout=output, stderr=subprocess.STDOUT)
    receipt = {"argv": command, "cwd": str(cwd), "exit": completed.returncode, "seconds": time.monotonic() - start,
               "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
    record(phase / "PROCESS.json", receipt)
    if completed.returncode:
        raise RuntimeError(f"Process exited {completed.returncode}. See {log}")
    return log


def verified_checkpoint(path, binding):
    if not path.is_file():
        return None
    saved = json.loads(path.read_bytes())
    if saved["binding"] != binding:
        raise ValueError(f"Different source, tool or command owns {path}. Choose a fresh stage directory.")
    log = Path(saved["attempt"]) / "native.log"
    checked_bytes(log.read_bytes(), saved["log_sha256"])
    process = json.loads((log.parent / "PROCESS.json").read_bytes())
    if process["exit"] != 0 or process["log_sha256"] != saved["log_sha256"]:
        raise ValueError(f"Checkpoint lacks a clean matching native process at {path}")
    return saved


def check_command(attempt, cwd, command):
    saved = json.loads((attempt / "PROCESS.json").read_bytes())
    if saved["cwd"] != str(cwd) or saved["argv"] != command:
        raise ValueError(f"Different native command or directory owns {attempt}")


def next_attempt(directory):
    directory.mkdir(exist_ok=True)
    n = 1
    while (directory / f"attempt-{n}").exists():
        n += 1
    return directory / f"attempt-{n}"


def build(deck, plan, home, binding):
    binary = deck / plan["binary"]
    receipt = home / "OK.json"
    saved = verified_checkpoint(receipt, binding)
    if saved:
        check_command(Path(saved["attempt"]), deck, plan["build"])
        checked_bytes(binary.read_bytes(), saved["binary_sha256"])
        return binary, saved["binary_sha256"]
    attempt = next_attempt(home)
    obj = deck / "obj"
    if obj.exists():
        # Retain the failed attempt before rebuilding. Refuse unrelated native objects.
        if not (home / "attempt-1").exists():
            raise ValueError(f"Unrecognized build objects at {obj}")
        obj.rename(home / (attempt.name + "-previous-objects"))
    log = native_process(plan["build"], deck, attempt)
    h = hashlib.sha256(binary.read_bytes()).hexdigest()
    record(receipt, {"binding": binding, "attempt": str(attempt),
                     "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest(), "binary_sha256": h})
    return binary, h


def run_native_locked(root, spec, expected):
    fixtures, fixtures_file, check_role = reference_checks(root, spec)
    home = root / "run"
    version = subprocess.check_output(["verilator", "--version"], text=True).strip()
    input_id = hashlib.sha256((HERE / "DECK.json").read_bytes() + (HERE / "EXPECTED.json").read_bytes()).hexdigest()
    saved_captures = None
    results = {}
    records = {}
    for suite in spec["suite_order"]:
        deck = root / suite
        plan = spec["suites"][suite]
        inputs = {**spec["common"], **plan["inputs"]}
        check_inputs(deck, inputs)
        check_inputs(deck / "fixtures", plan["fixtures"])
        binding = {"deck": input_id, "tool": version, "command": plan["build"]}
        binary, binary_hash = build(deck, plan, home / (suite + "-build"), binding)
        for case in plan["cases"]:
            number = str(case["number"])
            slot = home / ("case-" + number)
            binding = {"deck": input_id, "binary": binary_hash, "arguments": case["arguments"]}
            if number == "6":
                # The cross-model case always consumes this run's checked A capture.
                if saved_captures is None:
                    raise RuntimeError("Case 5 has not produced its authenticated records")
                binding["A_record"] = records["A"]["record_sha256"]
            saved = verified_checkpoint(slot / "OK.json", binding)
            attempt = Path(saved["attempt"]) if saved else next_attempt(slot)
            captures = saved_captures if number == "6" else attempt
            args = [arg.format(deck=deck, captures=captures) for arg in case["arguments"]]
            command = [str(binary), *args]
            if saved:
                check_command(attempt, deck, command)
                log = attempt / "native.log"
            else:
                checked_bytes(binary.read_bytes(), binary_hash)
                log = native_process(command, deck, attempt)
            results[number] = check_case(log, number, expected, fixtures)
            if number == "5":
                records = authenticate(attempt, expected, fixtures_file, check_role)
                saved_captures = attempt
            if not saved:
                record(slot / "OK.json", {"binding": binding, "attempt": str(attempt),
                                          "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()})
        check_inputs(deck, inputs)
        check_inputs(deck / "fixtures", plan["fixtures"])
    return {"mode": "native", "verilator_version": version, "cases": results, "captures": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("recorded", "native"))
    parser.add_argument("--staged", type=Path, required=True)
    args = parser.parse_args()
    root = args.staged.resolve()
    spec = json.loads((HERE / "DECK.json").read_bytes())
    expected = json.loads((HERE / "EXPECTED.json").read_bytes())
    if args.mode == "recorded":
        result = check_recorded(root, spec, expected)
    else:
        home = root / "run"
        home.mkdir(exist_ok=True)
        with (home / "native.lock").open("a+b") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = run_native_locked(root, spec, expected)
            record(home / "RESULT.json", result)
    if set(result["cases"]) != set(expected["cases"]) or set(result["captures"]) != {"A", "B"}:
        raise ValueError("Missing command or capture results")
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
