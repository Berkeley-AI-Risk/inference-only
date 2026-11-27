"""Stage the board-tested Gowin inputs outside the checkout without running a build."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
DEMO = HERE.parents[1] / "demos/simplestories-v2-5m"
RECIPE = "run.tcl"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory outside the checkout")
    parser.add_argument("--vendor-dir", type=Path, help="directory containing the four original Gowin sources")
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(HERE.parents[1]) or output.exists():
        parser.error("provide a fresh output path outside the checkout")
    release = json.loads((DEMO / "prebuilt/kv-protected-reset-guarded/RELEASE.json").read_bytes())
    pins_file = release["original_inputs"]
    raw = (DEMO / pins_file["path"]).read_bytes()
    if sha256(raw).hexdigest() != pins_file["sha256"]:
        raise ValueError("The original hardware input inventory has changed")
    pins = json.loads(raw)
    datapath, = set(release["changed_inputs"]) - {RECIPE}
    missing = []
    with TemporaryDirectory(dir=output.parent) as temp:
        work = Path(temp) / "guarded"
        for name, digest in pins.items():
            source = DEMO / "variants/kv-protected/hardware" / name
            if name.startswith("project/official/"):
                if args.vendor_dir is None:
                    missing.append(name)
                    continue
                source = args.vendor_dir / Path(name).name
            data = source.read_bytes()
            if sha256(data).hexdigest() != digest:
                raise ValueError(f"Original source differs: {name}")
            target = work / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        with (HERE / "kv-read-reset.patch").open("rb") as patch:
            subprocess.run(["patch", "-p1"], cwd=(work / datapath).parent, stdin=patch, check=True)
        recipe = work / RECIPE
        recipe.write_bytes(recipe.read_bytes().replace(b"set_option -place_option 3",
                                                       b"set_option -place_option 4"))
        for name, digest in release["changed_inputs"].items():
            if sha256((work / name).read_bytes()).hexdigest() != digest:
                raise ValueError(f"Guarded board input differs: {name}")
        work.rename(output)
    print(f"Staged {len(pins) - len(missing)} of {len(pins)} verified inputs.")
    for name in missing:
        print(f"Separate vendor input: {name}")


if __name__ == "__main__":
    main()
