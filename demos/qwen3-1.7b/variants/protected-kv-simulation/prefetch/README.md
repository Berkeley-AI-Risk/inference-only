# Paired K/V prefetch component comparison

The recorded full-model comparison reduced eighteen STEP intervals from
237,740,770 to 215,955,874 simulated core cycles (9.2%). The
[separate receipt](../references/matched-prefetch-long18-20261111.json) retains
the first STEP, the remaining seventeen and positions 15/16/17. This package
reproduces the smaller component experiments, not that full-model execution.
Neither measurement establishes physical frequency or FPGA throughput.

Three explicit reader selections share the same arithmetic, writer, owner and
verification path: `baseline` is the original protected reader, `anchor` adds
current-head V look-ahead, and `candidate` is the selected public reader with
one queued V follow-up for an admitted later K prefetch. The source manifest
pins all three. Numeric and fault top/test files and the fixed numerical header
are copied from the sealed experiment. `ORACLE.json` keeps its numerical arrays
and original digest while replacing local source paths with repository paths.
The scalar operand and root/leaf checks are independent of the DUT. No model
weights, Python numerical libraries, private services or downloads are needed.

From the repository root with Python 3.9+ (3.12 recommended), Verilator and a
C++17 compiler:

```sh
PREFETCH="$(pwd)/demos/qwen3-1.7b/variants/protected-kv-simulation/prefetch"
PYTHON=$(python3 -I -S -B -c 'import sys; print(sys.executable)')
RUN=/tmp/qwen17-prefetch-new
"$PYTHON" -I -S -B "$PREFETCH/run.py" check-sources
"$PYTHON" -I -S -B "$PREFETCH/test_controls.py"
"$PYTHON" -I -S -B "$PREFETCH/run.py" prepare --output "$RUN"
"$PYTHON" -I -S -B "$PREFETCH/run.py" build --output "$RUN" --max-seconds 3600
"$PYTHON" -I -S -B "$PREFETCH/run.py" run --output "$RUN" --max-seconds 3600
```

`check-sources`, the controls, `prepare` and `verify` start no native child.
Preparation refuses an existing output directory. Build uses one worker, and
each simulator uses one thread. Verilator compilation uses an unspaced system
temporary directory; exact source copies and their identities remain in the
caller-selected output. Each child gets a finite wall limit, an actual terminal
receipt and separate stdout/stderr. A failed, stopped or interrupted attempt
must be retained; there is no automatic retry or continuation after failure.
SIGTERM or SIGINT to the Python driver stops its owned process group and reaps
the direct child. `EXIT.json` records that child's actual exit and interruption.
For managed machines, use the site's resource admission policy before building
or running; the portable runner itself is not a host memory watchdog.

The fixed suite has eighteen numerical jobs (three readers, two transport
profiles, base/reversed-K/progressive workloads), two candidate five-case fault
suites, and three candidate later-group mutation/CLEAR jobs. Contexts are
2/16/17/33, with head sequence 0 → 1 → 0 and all 28 layers' ordered publication.
Comparison reports retain first-use and result times, through-quiescence and
tail drain, complete-case time, and matching requested/accepted traffic. Thus
moving waits into setup or cleanup cannot manufacture a reported saving.

For an external direct-child guard, build first and run each listed case with
the exact command below (replace `CASE` with a name from `PREPARED.json`):

```sh
"$PYTHON" -I -S -B "$PREFETCH/run.py" exec --output "$RUN" --case CASE
```

Set the guard's initial cwd to the absolute `$RUN`; retain its `EXIT.json`,
`stdout.log`, and `stderr.log` under `$RUN/runs/CASE/`. The adapter validates
bindings then uses same-PID `exec` into the binary, changing cwd to that case's
runtime directory. `PREPARED.json` supplies the exact absolute
`external_commands` and `external_cwd` for the guard. The guard must record the actual command, cwd, child exit,
stop reason and error. After all 23 actual cases, `run.py verify --output "$RUN"`
accepts either the runner's bound receipts or these direct-guard receipts;
it never launches a process or overwrites `VERIFIED.json`. Use the same Python
executable for the exec commands and verification. Disable `-O`/`-OO`.

These deterministic fixtures exercise two KV heads and three page groups, far
below authentication-slot capacity. Query/K activity is restricted to coordinate
zero. The two descriptor-delay profiles are not physical HBM models; later-group
security tests use only profile zero. There is no arbitrary-context/stall,
near-capacity progress, formal, physical CDC/reset, board, area or power claim.
