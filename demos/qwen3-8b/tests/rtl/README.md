# Qwen3 8B arithmetic RTL regressions

These finite Verilator tests run the released signed dot-product accumulator
and projection rescaling pipeline against independent host arithmetic. They
need no model image, AWS account, FPGA, vendor implementation tool or solver.
The runner checks and stages byte-identical inputs from
[SOURCE-INPUTS.json](../../SOURCE-INPUTS.json), leaving the released RTL unchanged.

## Arithmetic and protocol scope

The dot-product cases use one beat as a parameter edge case, plus the actual
512- and 1,536-beat lengths used by the released 8B projection engine. Each
beat contains eight signed 16-bit activations and signed 8-bit weights. The
reference accumulates independently decoded products in a signed 64-bit
integer. Directed signed extrema, individual lanes, zeros and deterministic
random inputs exercise 326 completed frames per geometry. The benches also
check input bubbles, ignored busy-start pulses, held outputs, and recovery
after six synchronous CLEAR/reset cancellations per geometry.

The scaling case checks the specified order:

```text
BF16_RNE(FP32_RNE(FP32_RNE(sum40) * row_scale) * vector_scale)
```

Its separate native IEEE-FP32 reference uses nearest-even rounding, disables
contraction, and requires subnormal support. It includes 40-bit signed bounds,
integer/rounding boundaries, finite scales, invalid scales and deterministic
random values. Of 12,000 accepted inputs, each must either produce a checked
result or be counted as cancelled by CLEAR/reset. Invalid results must set the
error indication; their unspecified payload bits are not credited as numerical
matches. Stalled result stability and reset/CLEAR transfer masking are checked.

These are component-level regression cases, not exhaustive arithmetic proofs,
full projection-tile/core tests, authenticated operand-use proofs, CDC checks,
FPGA timing qualification or inference-speed measurements. The independent
host compiler and floating-point behavior are part of the test's trusted base.

## Plan without building

From `demos/qwen3-8b`, with Python 3.12:

```sh
python3.12 -I -S -B tests/rtl/run.py --plan
python3.12 -I -S -B tests/rtl/test_runner.py
```

Planning and harness controls use only the standard library. The controls do
not substitute for executing the native RTL regressions.

## Build and execute

Install Verilator and a C++17 compiler through their normal distribution
channels. The runner performs no automatic installation. Verilator 5.050 was
used for the initial local run; each new result records its actual tool version.

Choose a fresh output path outside the release with no whitespace. Generated
native makefiles cannot reliably use a build directory containing spaces.
For example, replace the final directory name with a new unused name:

```sh
python3.12 -I -S -B tests/rtl/run.py \
  --jobs 2 --output /tmp/qwen8b-arithmetic-run-001
```

Builds run sequentially with two compiler jobs by default. Select `--suite dot8`
or `--suite scale` for a smaller run. Each compile has a 180-second limit and
each native test a 60-second limit; there are no automatic retries. A timeout
may stop only the runner's own unreaped child process group and is recorded as
an interruption, never a numerical pass.

The fresh output directory preserves source/binary identities, complete
compiler and test logs, actual child exit status and measured durations.
Successful completion writes `FINISHED.json`; a failed stage writes
`FAILED.json` and retains its logs. Each successful test must report its full
expected workload counts. Compiler warnings remain in the logs; a successful
finite simulation does not waive them or qualify physical implementation.

Keep new build outputs outside the checked release. Do not overwrite an earlier
result or copy raw machine-specific logs into a public evidence inventory
without the release review.
