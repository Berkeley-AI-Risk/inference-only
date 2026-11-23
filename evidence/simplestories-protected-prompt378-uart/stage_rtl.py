"""Prepare the exact protected simulation inputs from public Git and the nine test files."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent


def digest(data):
    return hashlib.sha256(data).hexdigest()


def prepare(repo, destination, recipe):
    destination.mkdir(parents=True, exist_ok=False)
    for name, spec in recipe["inputs"].items():
        if spec["origin"] == "packet":
            raw = (HERE / "testbench" / name).read_bytes()
        else:
            obj = f'{recipe["public_commit"]}:{spec["public_path"]}'
            raw = subprocess.check_output(["git", "-C", str(repo), "show", obj])
            if spec["origin"] == "public_compressed":
                raw = gzip.decompress(raw)
        if len(raw) != spec["bytes"] or digest(raw) != spec["sha256"]:
            raise ValueError(f"Input differs from the observed simulation: {name}")
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(raw)


def run_simulation(destination, recipe):
    verilator = shutil.which("verilator")
    if verilator is None:
        raise RuntimeError("Verilator is required for a native simulation.")
    version = subprocess.check_output([verilator, "--version"], text=True).strip()
    if not version.startswith("Verilator 5.050 "):
        raise ValueError(f"Use Verilator 5.050 to reproduce this run (found {version})")
    with (destination / "BUILD.log").open("xb") as stream:
        subprocess.run([verilator, *recipe["build_arguments"]], cwd=destination,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    output = destination / "NATIVE.log"
    with output.open("xb") as stream:
        subprocess.run(recipe["simulation_command"], cwd=destination,
                       stdout=stream, stderr=subprocess.STDOUT, check=True)
    origin = json.loads((HERE / "ORIGIN.json").read_bytes())
    prefixes = tuple(x.encode("ascii") for x in origin["prefixes"])
    with output.open("rb") as stream:
        reached = b"".join(line for line in stream if line.startswith(prefixes))
    expected = gzip.decompress((HERE / "trace.txt.gz").read_bytes())
    if reached != expected:
        (destination / "differing-trace.txt").write_bytes(reached)
        raise ValueError("Regenerated event trace differs from the recorded capture")
    print(f"Matched {len(reached.splitlines())} recorded event lines; SHA-256 {digest(reached)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-git", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True, help="Fresh directory for the simulation")
    parser.add_argument("--execute", action="store_true", help="Build and run the full protected Verilator simulation")
    args = parser.parse_args()
    spec = json.loads((HERE / "SIMULATION-INPUTS.json").read_bytes())
    destination = args.out.resolve()
    prepare(args.public_git, destination, spec)
    print(f"Prepared {len(spec['inputs'])} hash-checked inputs in {destination}", flush=True)
    if args.execute:
        run_simulation(destination, spec)


if __name__ == "__main__":
    main()
