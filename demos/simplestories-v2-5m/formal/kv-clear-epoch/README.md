# Protected-K/V CLEAR epoch proof

For a fresh Linux proof in CI or locally, use [the Linux replay](LINUX-REPLAY.md).
It recompiles the actual RTL and rechecks the theorem on the generated native
semantics. Recorded validation and strict artifact replay are described below.

The actual plaintext K/V-protected SimpleStories guard has a source-bound,
unbounded proof of its 64-bit CLEAR epoch protocol. Read the
[theorem and diagram](THEOREM.md), [scalar SMT definitions](THEOREM.smt2),
[proof graph](PROOF-GRAPH.json) and [qualification](QUALIFICATION.json).
The [actual guard](../../variants/kv-protected/hardware/project/kv_integrity_guard.sv)
is unchanged.

Newly sampled CLEAR advances the epoch once below the maximum; held CLEAR does
not count repeatedly. A fresh CLEAR at all-ones retains the counter and causes
an immediate terminal fault that is latched into the next state. Held/no-new
CLEAR at max can remain healthy. The mathematical generation agrees with the
native epoch in reset-released nonterminal states. Common hard reset starts a
new count; global epoch uniqueness across resets is not claimed.

From the repository root, validate all saved results and current source bindings:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/run.py --recorded-only --out /tmp/clear-epoch-recorded --model demos/simplestories-v2-5m
```

Use a new output directory. For three fresh native recompilations and all 26
fresh solver queries, omit `--recorded-only`:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/run.py --out /tmp/clear-epoch-fresh --model demos/simplestories-v2-5m
```

Python assertions must remain enabled. The replay, corruption controls and
Linux installer reject `-O` and `-OO` before reading inputs or creating outputs.

Recorded-only mode uses Python's standard library and launches no compiler or
solver. Fresh mode requires the tested [toolchain](TOOLCHAIN.json), uses at most
two solver workers, and saves every fresh result under the requested output.
It reconstructs each query and rebinds it to the newly compiled native model.
All logical SMT bytes and JSON circuit data must match. Only the first Yosys
generator comment and JSON creator build banner may differ. Unknown, timeout, resource stop, source mismatch or failed control
does not count as success. `ps` is used to monitor only the launched solvers.

The 11 checker-corruption controls also use Python alone:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/kv-clear-epoch/self_test.py --out /tmp/clear-epoch-checks --model demos/simplestories-v2-5m
```

The extracted project contains exact SMT inputs and raw SAT/UNSAT replies,
portable exported receipt metadata, complete source/native models, reference
definitions and independent AI reviews of the underlying plan and composition.
The source and arithmetic lemmas are proved by Z3 and cvc5; Python checks their
typed, acyclic applications and coordinates reproduction. It is not a proof
assistant, and recorded-only validation does not rerun the solvers.

The suite covers the reset base, inductive joint invariant, epoch consumer in the read-integrity proof, exhaustive reset/no-new/fresh cases and four operating/boundary SAT
contexts. Two separately compiled full-native shadow controls detect an omitted
increment and a suppressed exhaustion fault. Their failures concern the epoch
relation while CLEAR-sampling equality remains intact. The ordinary control has
a short native reset-rooted prefix; exhaustion is an arbitrary-state boundary
witness, not a short execution through 2^64 events.

This closes one supporting invariant. Complete tag/RAM/cache preservation, the
legitimate-record-to-attention join, pending-row provenance, model/graph meaning,
whole-device inference-only behavior, physical timing/reset/bitstream mapping
and any residual-training bound remain open. No cryptographic or new
environmental premise is introduced by this scalar proof. The encrypted-memory,
baseline and seeded configurations gain no additional theorem from this package.
