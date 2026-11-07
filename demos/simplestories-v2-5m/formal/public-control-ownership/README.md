# Public command, candidate commit and reply ownership

If CLEAR is accepted after a candidate commits but before reply capture, that
candidate loses publication authority. Once the bridge captures a token reply,
its bytes remain fixed through a later fault. Capture and pin-level delivery
are separate boundaries.

An accepted STEP snapshots the current tape and acquires a logical ticket. A
successful shell commit appends one candidate under that ticket; the bridge
can capture that held token once. An **opaque candidate** means an arbitrary
token supplied at the numerical core boundary.

The [readable theorem](THEOREM.md) and [formal predicate](STATEMENT.smt2) state
the exact baseline scope. The candidate's numerical origin remains open:
this result does not establish that it is the argmax of this STEP's head rows
or the prescribed model's next token. Twenty numerical/storage leaf instances,
with 137 output ports, remain unrestricted. The whole-device inference-only
theorem remains open.

The source proof connects the actual UART bridge/adapter to the native
controllers on one common sampled core-clock trace. Its
[dependency graph](CONTRACT-GRAPH.json) closes 142 native assertions, an
[independent phase invariant](PHASE-SUPPORT.smt2), all twelve history clauses
and four actual endpoint implications. Eighteen selected checks have clean
expected outcomes: fourteen UNSAT and four SAT contexts or defect checks.
Reset bases and unbounded induction establish safety beyond bounded test runs.

The operating witness starts at actual reset, cancels committed candidate 23
with a busy CLEAR before capture, observes controller drain, accepts another
STEP without another reset and publishes candidate 17 through a later fault.
A source-only stale-token capture defect is detected separately. Protocol
stimuli at the explicit cuts establish no numerical or physical-memory result.

The [native qualification receipt](NATIVE-QUALIFICATION.json) records a fresh
replay of these frozen proof inputs, including tool identities, all eighteen
answers and the operating witness. Its platform and execution scope are explicit.
The [formal replay workflow](../../../../.github/workflows/formal-replay.yml)
also recompiles and replays this packet with the managed Linux tools. Its
artifact contains separate hosted tool identities, queries, logs and traces.

## Replay

Python 3.8+ can verify the complete recorded packet without external tools:

```sh
python3 run.py --recorded --output /tmp/public-control-recorded
```

The default repository root is inferred from this package's installed location.
For a separately extracted package, add `--repository-root /path/to/inference-only`.
The checker verifies archive/member hashes, the thirteen actual production
source identities, both archived native models, every complete query and raw
answer, and the witness/guard receipts. This starts no solver or compiler.

To recompile and rerun the complete argument, install Yosys, Z3, Icarus Verilog
and vvp, then use a new output directory:

```sh
python3 run.py --fresh --output /tmp/public-control-fresh
```

This recompiles two native models, recomputes all eighteen solver checks,
and runs the native operating witness and four-state guard validation. It
permits different compiler-generated SMT bytes and proves the properties of
the freshly compiled models; it does not assume compiler equivalence. Tool
versions, executable hashes, queries, raw logs, exits and resource records are
saved in the output. Runs are sequential, limited to 60 seconds per compile or
simulation, 120 seconds per query and 4 GiB sampled owned-process-tree RSS.
No source or installed-tool changes are made.

For the repository's managed Linux tools, pass `--tool-receipt TOOLS.json` from
the [CLEAR replay installer](../kv-clear-epoch/LINUX-REPLAY.md). The receipt's
Yosys/Z3 paths, hashes and versions are checked before use; bundled PATH tools
cannot silently replace the selected solver. Icarus/vvp are selected from that
suite's directory, and their hashes/versions are newly recorded.

The archive includes the model sources, exact proof inputs, source/cut map,
inspectable source diffs, recorded models/answers and witness sources. The
public entry point orchestrates explicit SMT-LIB obligations; Python execution
alone is not the mathematical theorem. See [the source binding](SOURCE.json)
and the independent composition/witness reviews in the extracted project.
