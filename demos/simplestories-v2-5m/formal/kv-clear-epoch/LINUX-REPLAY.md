# Fresh Linux proof replay

The [formal CI job](../../../../.github/workflows/formal-replay.yml) compiles
the production plaintext K/V guard, page-hash and SHA hierarchy, then reruns all
26 CLEAR epoch obligations on the native models generated in that job. It also
compiles and checks the two existing source defects. It needs no FPGA, weights,
cloud instance or proprietary compiler.

The conclusion is the existing [64-bit CLEAR epoch theorem](THEOREM.md): sampled
CLEAR advances the epoch once, held CLEAR does not repeat, and exhaustion faults
instead of reusing an epoch. It is a supporting invariant; the whole protected
read and inference-only theorems remain open.

## Reproduce the CI command

On Linux ARM64, use Python 3.12 and a new output directory outside the repository.
From the repository root:

Keep Python assertions enabled; `-O` and `-OO` are refused before input or output
access by the installer and replay.

```sh
proof_scratch="$(mktemp -d)"
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/install_linux.py \
  --out "$proof_scratch/tools"
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/recompute.py \
  --model demos/simplestories-v2-5m --out "$proof_scratch/proof" \
  --tool-receipt "$proof_scratch/tools/TOOLS.json" \
  --workers 2 --memory-mb 4096 --timeout 120 --total-timeout 900
```

[LINUX-TOOLS.json](LINUX-TOOLS.json) pins the upstream release assets by exact
size and SHA-256. The installer checks them before extraction and records the
actual tool versions. CI uses `ubuntu-24.04-arm`, Python 3.12.12, OSS CAD Suite
2026-11-05 and cvc5 1.3.1. Linux x86-64 tool pins are also supplied; that install
uses the matching recorded executable paths. The fresh qualification recorded
for this contribution was on native Linux ARM64, not an x86 emulation.

The command allows two workers, 4 GiB sampled RSS per solver, 120 seconds per
query and 900 seconds total; each compilation has a 60-second timeout. It requires
local child-process monitoring with `ps`. A timeout, unknown, failed compilation
or unexpected answer fails the job. The runner does not skip missing tools.
It selects executables from the installation receipt, verifies their hashes and
versions before compiling, and ignores competing versions on the ambient PATH.

## What differs from strict artifact replay

`run.py` retains its existing fresh mode: it requires logical model identity
with the saved toolchain artifacts. `recompute.py` instead reconstructs each
query using the **freshly generated native semantics**. It does not rename a
new compiler's output into an old model or assert compiler equivalence. Source
bytes, source-defect changes, compile recipes, proof statements and composition
graph remain checked. All nine native memories, the 64-bit epoch and original
50,000,000-cycle timeout remain present.

The fresh models may differ from the recorded models. The theorem is checked
again against those models: reset, induction, consumer bindings, operating
contexts and defect detections must all give their expected answers. This is
the same source-bound scalar statement under a separately recorded compiler,
not an RTL-to-netlist or cross-compiler equivalence theorem.

`RESULT.json` reports `mode: fresh-recomputed`, three fresh compilations and
26 fresh queries. `FRESH-GRAPH.json`, `FRESH-BINDINGS.json`, `fresh-queries/`,
`fresh-models/` and `fresh-solvers/` retain exact statements, model bindings,
commands and raw answers. CI uploads those outputs and its tool-install receipt,
including on failure. The [recorded-only check](README.md) remains separate and
launches no compiler or solver.
