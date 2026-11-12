# Protected Qwen3 1.7B full machine replay

This offline runner regenerates an independent eighteen-step tensor oracle and
drives the protected RTL machine through CLEAR, APPEND, eighteen STEP commands
and a final CLEAR. It checks every tensor boundary and the actual writer and
reader traffic across K/V positions 15, 16 and 17. No model weights, generated
tensors, AWS tools or private engineering paths are included.

## Measured reader comparison

The [matched eighteen-STEP result](../references/matched-prefetch-long18-20261111.json)
used **9.2% fewer simulated core cycles** with the selected paired-prefetch reader.
Only `qwen_kvp_reader.sv` differs among the 95 compiler inputs; the model, oracle,
harness, arithmetic, clock ratio and transport settings agree.

| Timed interval | Baseline | Selected reader |
| --- | ---: | ---: |
| First STEP | 13,023,330 | 11,813,058 |
| Remaining 17 STEPs | 224,717,440 | 204,142,816 |
| All 18 STEPs | 237,740,770 | 215,955,874 |

| Token position | Baseline STEP cycles | Selected STEP cycles | K/V commits |
| --- | ---: | ---: | ---: |
| 15 | 13,247,512 | 12,037,240 | 28 |
| 16 | 13,074,280 | 11,864,008 | 28 |
| 17 | 13,253,392 | 12,043,120 | 28 |

All 18 outputs, 9,126 tensor boundaries, 27,581,184 BF16 values, 504 K/V commits
and both CLEAR acknowledgments match. Every STEP saves 1,210,272 cycles. The
cycle sum excludes initialization, initial CLEAR/APPEND and final CLEAR; the
first STEP is included in the total and also reported separately. Initialization
wall time was not independently timestamped for the baseline. Host process
runtimes are recorded separately and do not establish hardware throughput.

The [baseline receipt](../references/portable-long18-20261110.json) retains its
original reader and execution identities. The [baseline replay instructions at
commit 9b3078d](https://github.com/Berkeley-AI-Risk/inference-only/blob/9b3078dbb1dd75445f9b7a84344727cfce0cda15/demos/qwen3-1.7b/variants/protected-kv-simulation/full-machine/README.md)
use that reader and its original source pins. Run those commands from a checkout
of that commit with fresh oracle and run directories. The table above reports
the saved matched executions; a new run produces its own receipts.
The selected reader's source-bound
oracle must be prepared against the selected source set; an old source manifest
cannot be silently reused. The numerical tensor commitments remain unchanged.

## Prepare the model and independent tensors

First follow the existing [model preparation](../../../INSTALL.md#prepare-the-fixed-model)
instructions with your separately obtained, pinned upstream model. The resulting
`model-memory.bin` must be 2,354,380,800 bytes with SHA-256
`90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1`.
The runner verifies both before capture or replay. It does not download anything.

From the repository root, use the Python environment created by that procedure:

```sh
PYTHON=demos/qwen3-1.7b/.venv-model/bin/python
REPLAY=demos/qwen3-1.7b/variants/protected-kv-simulation/full-machine/replay.py
MODEL=/path/to/model-memory.bin
ORACLE=/tmp/qwen17-independent-long18
RUN=/tmp/qwen17-protected-long18

"$PYTHON" -B "$REPLAY" check-sources
"$PYTHON" -B "$REPLAY" capture --model-image "$MODEL" --output "$ORACLE" --threads 8
"$PYTHON" -B "$REPLAY" check-oracle --oracle "$ORACLE"
"$PYTHON" -B "$REPLAY" prepare --model-image "$MODEL" --oracle "$ORACLE" --output "$RUN"
"$PYTHON" -B "$REPLAY" build --output "$RUN"
```

Use new oracle and run directories. Capture uses the canonical public fixed
numerical reference on CPU, with explicit arithmetic and reduction orders.
`TENSOR-TAPE.json` contains eighteen compact commitments covering all 9,126
ordered tensor identities and hashes, including the original three-step prefix.
Every regenerated fixture must match those commitments before it can be used.
The fixtures only monitor RTL results; they never drive numerical operands.

`prepare` creates a sealed source stage from public RTL. Only that stage's
wrapper instance selects `qwen_protected_machine` instead of the plain machine.
The source tree, existing board inventory and published FPGA image stay plain.
The stage uses the production prefetch setting and a simulated 100:125 MHz
core/memory ratio. Neither staging nor compilation executes token inference.

## Run the full simulation

With Verilator and a C++17 compiler installed, allow several hours of local
simulation time and sufficient memory. The [recorded matched replay](../references/matched-prefetch-long18-20261111.json)
retains both host durations; duration depends on the host. The
public CPU oracle recommends about 16 GB of available memory. For managed runs,
use a host resource supervisor appropriate to your machine; the numerical
simulation has one thread and compilation has one worker. There is no unused-RAM
admission threshold in this runner.

```sh
"$PYTHON" -B "$REPLAY" run --model-image "$MODEL" --oracle "$ORACLE" \
  --output "$RUN" --max-seconds 18000
```

This starts one simulator child, saves stdout, stderr, the actual exit and
measured duration, and verifies the result. The child's terminal receipt binds
both log hashes; a later verification rejects either log if it has changed.
The finite wall-time limit stops
only this child group if needed. No failure or interruption is retried. An
interrupted run is not a numerical failure or a completed numerical pass.
`VERIFIED.json` requires child zero without stop/error, empty stderr and all of:

- Eighteen tokens matching `references/long18.json`.
- 504 ordered layer checks, 9,126 tensor boundaries and 27,581,184 BF16 values.
- 504 real K/V publications, including 28 each at positions 15, 16 and 17.
- Two application CLEAR acknowledgments after actual modeled AXI drainage.
- The accepted APPEND/STEP/CLEAR sequence, original terminal PASS, and unchanged
  model, oracle, ROM, compiler-stage, binary and public source identities.

After an interrupted review, retain all original receipts. If the simulator
actually completed successfully but the Python review itself was interrupted,
the offline review can be run separately, without launching another child:

```sh
"$PYTHON" -B "$REPLAY" verify --model-image "$MODEL" --oracle "$ORACLE" --output "$RUN"
```

The verifier does not overwrite an existing verification record. A new binary
hash is expected after recompilation; matching a historical binary is not a
prerequisite for reproducing its numerical result.

## Local runner controls and qualification

```sh
python3.12 -I -S -B demos/qwen3-1.7b/variants/protected-kv-simulation/full-machine/test_replay.py
```

These finite controls need neither weights nor PyTorch. They test source
selection (including refusal of unlisted compiler inputs), wrong-model rejection
and transcript acceptance/refusal logic; they
are not numerical simulation. The separate short [store-to-attention regression](../README.md)
tests corrupt K/V operand handling. This full-machine runner does not inject
stale or corrupt K/V and must not be cited as such a fault campaign.

The [matched replay receipt](../references/matched-prefetch-long18-20261111.json)
records the selected reader's actual eighteen-token execution against the same
independent tensor oracle used by the [baseline](../references/portable-long18-20261110.json).
Source-admission and portable runner checks are separate from those numerical
executions. The [reference constants](../references/long18.json) retain the
original numerical record. A new `VERIFIED.json` identifies the actual
binary, source stage, independent oracle and child terminal. Simulation covers
eighteen positions, not all contexts, and does not qualify physical CDC/reset,
vendor HBM, FPGA routing/timing, speed or power. Dependency rights remain those
in [NOTICES.md](../NOTICES.md); the behavioral monitor is project-authored test
code, with unchanged independent SHA and AXI fixture helpers.
