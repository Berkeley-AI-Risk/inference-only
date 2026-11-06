# RMSNorm arithmetic and protocol regression

The additive [runner](run_norm.py) builds the unchanged released
[RMSNorm module](../../hardware/design/qwen_rms_norm.sv) and checks both fixed
widths, 128 and 4,096 elements, using the [native C++ test](rmsnorm.cpp).
It needs no model weights, FPGA, network or cloud service.

## Numerical oracle

The independent native IEEE FP32 oracle squares BF16 inputs, accumulates
left-to-right, multiplies by the exact reciprocal width, adds the fixed
epsilon, then performs separate square-root and reciprocal operations.
Normalization rounds to BF16 before the norm-weight product, which rounds
to BF16 again. Compiler flags disable contraction and fast-math, require
rounding-mode awareness, and the test requires round-to-nearest-even with
FP32 subnormals. It does not substitute a library mean or reciprocal square root.

Healthy vectors cover signed zero, constants, alternating signs, a final-element
impulse, powers, BF16 subnormals, signed weights and deterministic pseudo-random
values. Eight error frames exercise nonfinite input, nonfinite weight, square
overflow and weighted-output overflow at both widths. They must return an error;
an error result is not counted as a matching numerical output.

## Protocol coverage and recorded result

The test inserts input bubbles and output stalls, checking that every held
result, index and error flag stays stable. It cancels frames with CLEAR during
loading and while a reply is stalled, and with reset during output. A complete
freshly filled frame follows each cancellation to check reuse.

The finite native regression passed with 26 complete healthy frames, eight
error frames and six cancelled frames. It checked 54,934 BF16 values, including
22 checked values before the two output-phase cancellations. There were four
CLEARs, two mid-frame resets, 24,041 held-reply checks and 22,562 input bubbles.
All staged RTL dependencies matched the frozen source-input manifest.

These selected vectors and synchronous module checks are not a formal theorem,
exhaustive input coverage, whole-core numerical validation, asynchronous reset
or CDC signoff, timing closure, or authentication/security qualification.
Verilator warnings are preserved in the build log, not waived by a passing test.

## Reproduce locally

From `demos/qwen3-8b`, with Python 3.12, Verilator and a C++17 compiler:

```sh
python3.12 -I -S -B tests/rtl/test_norm_runner.py
python3.12 -I -S -B tests/rtl/run_norm.py --plan
python3.12 -I -S -B tests/rtl/run_norm.py --output /tmp/qwen8b-rmsnorm-check --jobs 1
```

Use a fresh, whitespace-free output directory outside the demo. The runner
verifies the manifest and exact shared-helper identity, bounds the build to
one or two compiler jobs, and preserves real compile/execution exits, logs,
input and binary hashes, and a terminal record. It does not retry a failed run.
The [small runner tests](test_norm_runner.py) do not execute RTL and cannot
replace the native result. The separate [dot8 and scaling suite](README.md)
keeps its original sources and evidence.
