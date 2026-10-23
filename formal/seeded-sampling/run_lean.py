"""Check the scoped transaction specification using the installed pinned Lean."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    source = (here / 'SeededPublicSurface.lean').read_bytes()
    text = source.decode()
    # No new proof axioms, placeholders or admission commands are accepted.
    if re.search(r'(?m)^\s*(axiom|sorry|admit)\b', text) or re.search(r'\b(sorry|admit)\b', text):
        raise ValueError('Unproved Lean declaration')
    installed = subprocess.run(['elan', 'toolchain', 'list'], capture_output=True, text=True, check=True)
    toolchain = 'leanprover/lean4:v4.33.1'
    if toolchain not in installed.stdout.splitlines():
        raise ValueError('Pinned toolchain is not already installed; no download is allowed')
    version = subprocess.run(['lean', '+' + toolchain, '--version'], capture_output=True, text=True, check=True)
    if 'version 4.33.1' not in version.stdout: raise ValueError('Unexpected Lean version')
    run = args.run.absolute()
    run.mkdir(parents=True, exist_ok=False)
    (run / 'SeededPublicSurface.lean').write_bytes(source)
    (run / 'runner.py').write_bytes(Path(__file__).read_bytes())
    start = time.monotonic()
    result = subprocess.run(['lean', '+' + toolchain, 'SeededPublicSurface.lean'], cwd=run,
                            capture_output=True, timeout=120)
    (run / 'stdout.log').write_bytes(result.stdout)
    (run / 'stderr.log').write_bytes(result.stderr)
    record = dict(passed=result.returncode == 0 and b'error:' not in result.stdout,
        exit=result.returncode, seconds=time.monotonic() - start, toolchain=toolchain,
        version=version.stdout.strip(), source_sha256=sha(source),
        runner_sha256=sha(Path(__file__).read_bytes()), theorem_count=len(re.findall(r'(?m)^theorem ', text)),
        stdout_sha256=sha(result.stdout), stderr_sha256=sha(result.stderr),
        hardware_access=False, network_access=False, rtl_imported=False,
        numerical_sampler_proved=False, rtl_refinement_proved=False,
        scope='Four-operation atomic transaction definition, bounded tape, settings admission/effects, seed/CLEAR replay and reply counts. Fixed model/sampler/random-transition functions are abstract parameters held fixed through each run; no RTL correspondence theorem.')
    (run / 'FINISHED.json').write_text(json.dumps(record, indent=2, sort_keys=True) + '\n')
    print(json.dumps(record), flush=True)
    return 0 if record['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
