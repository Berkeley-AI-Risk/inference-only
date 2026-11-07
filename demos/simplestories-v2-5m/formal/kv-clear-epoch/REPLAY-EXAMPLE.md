# Run a source-bound proof yourself

On Linux, start with [the pinned Linux replay](LINUX-REPLAY.md). It checks the
same theorem on freshly generated native semantics. The command below is the
strict mode, which requires the saved toolchain's logical model artifacts.

This example freshly recompiles the published plaintext K/V-protected
SimpleStories guard and checks its 64-bit CLEAR epoch invariant. It uses the
existing [proof package](README.md), [statement](THEOREM.smt2),
[theorem and diagram](THEOREM.md), and [proof graph](PROOF-GRAPH.json).
No FPGA, model weights, cloud instance or proprietary FPGA compiler is needed.

The property is small and useful: a newly sampled CLEAR advances the epoch once;
holding CLEAR does not count repeatedly; exhaustion causes terminal fault rather
than reusing a live epoch. The mathematical reference and native counter agree
from reset. Common hard reset begins a new scope; this is not global freshness
across power cycles, RAM zeroization or a whole-device inference-only theorem.

## Prerequisites and fresh command

Use a clean release and Python 3.12. Put the tested Yosys, Z3 and cvc5 versions in
[TOOLCHAIN.json](TOOLCHAIN.json) on PATH. They are source/solver tools; Gowin is
not required. Output must be outside the release and must not already exist.
From the repository root, on macOS or Linux:

```sh
clear_epoch_replay="$(mktemp -d)"
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/run.py \
  --model demos/simplestories-v2-5m \
  --out "$clear_epoch_replay/fresh" \
  --workers 2 --memory-mb 4096 --timeout 20 --total-timeout 180
```

This is a deliberately bounded local example: two solver workers, a 4 GiB sampled
RSS stop per solver, 20 s per query and 180 s total. Each native compilation also
has its existing 60 s timeout. Slow or incompatible environments can return an
unresolved result; use the package README's tested default limits when needed.
No timeout or unknown is counted as a proof. The runner uses `ps` only to monitor
its own children, so execution environments must permit that local monitoring.

The successful result includes:

```json
{
  "passed": true,
  "mode": "fresh",
  "fresh_native_compilations": 3,
  "fresh_solver_queries": 26,
  "all_fresh_expected_results_matched": true
}
```

This fresh replay was checked for this guide using the package/source bytes
selected by public revision `527c5fc93adfb1124f5acd4bc7371ec62ca34705` and the tested
toolchain. All three compilations and all 26 expected solver answers passed.
Runtime and memory are platform dependent; the command's bounds state the
resource scale without requiring a hardware board campaign.

## What is actually checked

The runner first verifies the package and its exact production-source bindings.
It recompiles the unchanged full guard/page-hash/SHA hierarchy and two separate
source-defect controls. All logical SMT bytes and JSON circuit data must match
the recorded models; only a generator comment and JSON creator build banner
may differ. It then reconstructs and runs all 26 selected Z3/cvc5 queries.

The graph includes a reset base, an inductive joint invariant, its actual
consumer binding, arithmetic/source dependencies, operating contexts and two
intended source-defect detections. The fault control does not silently assume
the original source's transition lemma. The exhaustion fixture is an
arbitrary-state boundary check, not a simulation through 2^64 requests.

An induction step reasons about an arbitrary state satisfying the invariant and
an arbitrary next input. Combined with its reset base and checked dependencies,
it establishes the invariant for all subsequent steps under the stated digital
contracts. A one-step obligation here is not merely a one-cycle execution test.
Raw commands, queries and replies are saved under `fresh-solvers/`; compiler
outputs and identities are under `fresh-models/`; `RESULT.json` summarizes the
run. The Python entry point orchestrates and checks bindings; the actual formal
answers come from the named solvers on the SMT statements.

## Saved receipts are a different check

For integrity and recorded-result validation without running any compiler or
solver, use a separate new output directory:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/run.py \
  --recorded-only --model demos/simplestories-v2-5m \
  --out "$clear_epoch_replay/recorded"
```

This reports `mode: recorded-only` and zero fresh compilations/queries. It does
not replace the fresh command above. Neither mode upgrades this scalar result
to legitimate K/V record provenance, numerical attention, protected-read or
whole-device correctness. Follow the [formal argument](../../../../docs/FORMAL-ARGUMENT.md)
for those remaining provider-to-consumer joins and configuration boundaries.
