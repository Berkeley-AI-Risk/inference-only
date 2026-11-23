"""Rebuild the three shared-cipher simulation source decks from pinned public inputs."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent


def checked_bytes(source, digest):
    if hashlib.sha256(source).hexdigest() != digest:
        raise ValueError(f"Source hash differs from {digest}")
    return source


def load_source(row, repository, driver, commit):
    if row["origin"] == "git":
        data = subprocess.check_output(
            ["git", "-C", str(repository), "show", f'{commit}:{row["path"]}']
        )
    else:
        roots = {"generated": driver, "bundle": HERE}
        data = (roots[row["origin"]] / row["path"]).read_bytes()
    return checked_bytes(data, row.get("input_sha256", row["sha256"]))


def check_inputs(directory, rows):
    for name, row in rows.items():
        source = directory / name
        if not source.is_file() or source.stat().st_size != row["bytes"]:
            raise ValueError(f"Expected {row['bytes']} bytes at {source}")
        checked_bytes(source.read_bytes(), row["sha256"])


def prepare(repository, upstream, output):
    spec = json.loads((HERE / "DECK.json").read_bytes())
    driver = upstream / "driver"
    for name, expected in spec["reference_inputs"].items():
        checked_bytes((driver / name).read_bytes(), expected)
    output.mkdir(parents=True, exist_ok=False)
    details = {}
    for suite in spec["suite_order"]:
        target = output / suite
        target.mkdir()
        plan = spec["suites"][suite]
        rows = {**spec["common"], **plan["inputs"]}
        patches = []
        for name, row in rows.items():
            path = target / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(load_source(row, repository, driver, spec["public_base"]))
            if "patch" in row:
                patch = HERE / row["patch"]
                checked_bytes(patch.read_bytes(), row["patch_sha256"])
                patches.append(str(patch))
        if patches:
            subprocess.run(
                ["git", "apply", "--no-index", "--whitespace=nowarn", *patches],
                cwd=target, env={**os.environ, "GIT_CEILING_DIRECTORIES": str(output)},
                check=True,
            )
        check_inputs(target, rows)
        fixtures = target / "fixtures"
        fixtures.mkdir()
        for name, row in plan["fixtures"].items():
            data = (driver / "fixtures-v1" / name).read_bytes()
            (fixtures / name).write_bytes(checked_bytes(data, row["sha256"]))
        check_inputs(fixtures, plan["fixtures"])
        details[suite] = {"source_inputs": len(rows), "fixture_inputs": len(plan["fixtures"])}
    # Save the original public reference program with the inputs it expects.
    reference = output / "reference"
    for name, expected in spec["reference_inputs"].items():
        dest = reference / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(checked_bytes((driver / name).read_bytes(), expected))
    manifest = (driver / "fixtures-v1/FIXTURES.json").read_bytes()
    checked_bytes(manifest, spec["fixture_manifest_sha256"])
    (reference / "FIXTURES.json").write_bytes(manifest)
    receipt = {"public_commit": spec["public_base"], "suites": details}
    (output / "STAGED.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-repo", type=Path, required=True)
    parser.add_argument("--upstream", type=Path, required=True,
                        help="Output directory of the public combined simulation's prepare phase")
    parser.add_argument("--output", type=Path, required=True, help="Fresh directory for three source decks")
    args = parser.parse_args()
    prepare(args.public_repo.resolve(), args.upstream.resolve(), args.output.resolve())
