"""Fetch/check only the six public files from the FPGA project's pinned model.

No executable model code or pickle checkpoint is downloaded or loaded.
"""

import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

REPOSITORY = "SimpleStories/SimpleStories-V2-5M"
REVISION = "c4b3a4bb81297f5316697098e1d4b65c1249daf8"
FILES = {
    "README.md": (2622, "f7affc404254197421fd3e4d4e03ca991807128d4b7da3d55f163a5c7b427c2e"),
    "config.json": (668, "dd02c20fa5afe463a7fce11615d298a1e84a58774831a2119bd793de87722a90"),
    "model.safetensors": (21424032, "7c8a5d078690e816920b4779decf55e58c34901c2668a1bc4f344b21862fce03"),
    "special_tokens_map.json": (75, "f2a009c988c79b451ac4d518525849cf93f9d017fd52acf4b892652c0186b923"),
    "tokenizer.json": (86463, "01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51"),
    "tokenizer_config.json": (587, "9d32dcb8457613e2dab376656eec6495a6e19fb0408859fb3a979cf42fed85f0"),
}


def check_bytes(name, data):
    size, digest = FILES[name]
    if len(data) != size or hashlib.sha256(data).hexdigest() != digest:
        raise ValueError(f"Pinned model verification failed: {name}")


def verify(directory):
    directory = Path(directory)
    for name in FILES:
        check_bytes(name, (directory / name).read_bytes())
    return {name: digest for name, (_, digest) in FILES.items()}


def fetch(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for name, (size, _) in FILES.items():
        target = directory / name
        if target.exists():
            check_bytes(name, target.read_bytes())
            continue
        url = f"https://huggingface.co/{REPOSITORY}/resolve/{REVISION}/{name}"
        request = urllib.request.Request(url, headers={"User-Agent": "fixed-model-benchmark/1"})
        with urllib.request.urlopen(request, timeout=120) as response:
            data = response.read(size + 1)
        check_bytes(name, data)
        # Never replace an existing file, even if another process creates it.
        with target.open("xb") as handle:
            handle.write(data)
        print(f"Verified {name} ({len(data):,} bytes)", flush=True)
    return verify(directory)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    hashes = verify(args.directory) if args.check_only else fetch(args.directory)
    print(json.dumps({"repository": REPOSITORY, "revision": REVISION, "sha256": hashes}, indent=2))
