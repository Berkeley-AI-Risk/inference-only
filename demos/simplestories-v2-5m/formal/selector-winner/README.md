# Baseline selector: START to healthy WINNER

After an actual accepted selector START, a healthy native WINNER returns the least ID attaining the maximum of that invocation's 4,019 legally admitted rows. Its payload belongs to the admitted row at that ID, and its output fields stay fixed under healthy winner backpressure. The [precise theorem](THEOREM.md) states the numerical format, cancellation conditions and proof joins.

This is a selector-unit result. The row stream is the stream actually admitted at its private unit interface. Proving that those rows are the prescribed model logits remains open. A separate development STEP-ownership result is not imported: connecting a parent accepted STEP to this START, WINNER and eventual public reply needs its own source/trace/work-identity join. This replay does not establish the whole-device inference-only theorem.

## One repository-root command

With Python 3.12, Yosys, Z3, Icarus Verilog and VVP on PATH, run from the repository root:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/selector-winner/run.py --repository-root . --output ../selector-winner-results
```

The output directory must be new and outside the repository. The command reads the three public inputs pinned in [SOURCE.json](SOURCE.json), appends the supplied nondriving observers, recompiles native RTL and runs two checks sequentially:

| Check | Required result |
| --- | --- |
| Native winner theorem | Unbounded induction: 58 assertions, including actual row ownership/base, independent numerical fold, arbitrary-row membership/dominance, least-ID ties and winner hold. |
| Wrong-tie comparator | A real reset/start/two-row trace must produce a SAT counterexample. The private copy sets the native incumbent to ID 1 while the strict fold keeps ID 0. |

The 4,019 rows comprise row 0 as the seed plus 4,018 subsequent comparisons. The proof checks initial cases and an inductive step; its induction length is not a row-count bound. It assumes neither eventual input delivery nor eventual winner acceptance.

The final line reports `theorem: UNBOUNDED` and `wrong_tie: SAT`. SAT is the required defect detection. Compiler errors or timeouts do not satisfy either check. `RESULT.json`, `TOOLS.json`, per-job logs, generated RTL/native JSON and structural audits are saved under the output path. No recorded solver model, private provider tree, model weights, network access or device is needed.

## Tools and resource limits

The replay uses the published public-control process guard. Its tool selector expects all four HDL/solver executables above; these two checks use Yosys's SAT engine. Each job has a 90-second wall cap and a 4 GiB owned-process-tree RSS cap, monitored with `ps`. There is one worker. The kit and source checkout may be read-only. Assertions must remain enabled; do not use Python `-O`.

The existing Linux formal workflow passes its installed tool receipt with `--tool-receipt "$RUNNER_TEMP/formal-tools/TOOLS.json"`. Local runs without that option select PATH tools and record executable hashes and versions. A local macOS result and a hosted Linux result are distinct executions; the runtime receipt identifies the selected tools.

## Proof boundary

The watched row ID is an arbitrary defined 12-bit constant, with no value or range restriction. It never drives native outputs. The runner checks that fact in the generated model, checks all 166 original storage bits have no initial-value constraint, and requires 58 assertions, zero assumption cells and exactly one arbitrary-constant cell. It also verifies every pinned production input and monitor before compilation.

The model is sampled, two-state RTL using `SYNTHESIS`, `async2sync` and `dffunmap`. Reset, CLEAR or failure can cancel an invocation. These results do not qualify physical timing/reset behavior, authenticate row values as logits, or connect the winner to the parent STEP and UART publication.
