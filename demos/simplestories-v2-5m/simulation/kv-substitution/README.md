# Paired K/V substitution replay

This opt-in RTL target compares ordinary SimpleStories inference with honest
and altered external K/V memory. It uses the released plaintext baseline and
K/V-protected functional sources, real full-image boot authentication and the
same APPEND `378`, STEP, STEP sequence. The second STEP consumes generated token
`200`. Its fixture changes only a previously written value row; model weights,
keys, query and exponent bytes remain unchanged.

From the repository root, with Python 3.12, NumPy 1.26.4, Verilator 5.050 and a
C++ toolchain:

```sh
python3 demos/simplestories-v2-5m/simulation/kv-substitution/run.py --output /tmp/paired-kv-substitution
```

Choose a new output directory outside the repository. `--build-jobs N` selects
compiler workers; `--jobs N` selects up to six simultaneous native cases. The
default uses one worker for each. The supplied [toolchain](toolchain/Dockerfile)
pins the same official Verilator base and hash-checked NumPy wheels as the
[combined simulation](../../variants/combined-security-simulation/README.md).
Neither replay invokes FPGA programming, routing, flash writes or cloud jobs.
This target is not a default CI job.

| Configuration and memory history | Accepted tokens | Required observation |
| --- | --- | --- |
| Plain, honest | `200, 15` | Independent integer reference matches. |
| Plain, old layer-0 V sign-negated | `200, 15` | Internal attention and later K/V writes change despite the same token. |
| Plain, old layer-4 V sign-negated | `200, 1138` | All eight altered words are fetched. |
| Protected, honest | `200, 15` | Independent numerical and SHA decisions match. |
| Protected, both old layer-4 V heads sign-negated | `200`, then fault | Only the first head's four altered words are fetched; no affected V delivery or new token. |
| Protected, only old layer-4 V head 1 sign-negated | `200`, then fault | Authentic head-0 V rows pass; the four altered head-1 words are fetched and refused before use. |

Addresses count private 256-bit DDR words, not host-selectable pointers. The
plain layer-4 data occupy `374537–374544`, with unchanged metadata word `374545`.
Protected data for the same logical values occupy `374532–374535` and
`374541–374544`, with shared metadata at `374536` and `374545`. The protected
both-head trial changes eight external words but stops before fetching the four
altered head-1 words. During the affected second STEP, both failing protected
trials have no final layer-4 attention output, next-layer position-one K/V write,
vocabulary-head row or second token. The error response carries zero data;
the fixture checks another 256 closed core edges after the fault.

`RESULT.json` requires all six real native children, fresh independent integer
reference generation and per-case comparison. The output retains commands,
tools, source/fixture seals, compiler warnings, native exits and raw logs,
extracted traces, numerical/SHA comparisons and explicit refusal controls for
changed input, changed trace, wrong numerical reference, wrong SHA digest,
saved binary identity and actual native exit. Validation reconciles the actual
compiler/native exits, binary and warning identities, and exact trace extraction
from each retained native log. The source-bound warning policy retains the
inherited width diagnostics; it is not a universal width-correctness proof.
Assertion-based helpers refuse `-O` and `-OO` before input/output access. Failed
and partial evidence remains in the output; no automatic retry or elapsed-time
cutoff is imposed. `--phase prepare`, `build`, `run` and `check` allow retained
finite slices against the same output directory.

The [input inventory](SOURCE-INPUTS.json) binds the selected source, image,
capsule and reference identities. Instrumentation is passive apart from the
declared external-memory substitution and ordinary token command fixture; no
boot lock, cache, prefix or guard tag is forced. Token observations are at the
real ready/valid boundary below the UART bridge. This two-state simulation
uses behavioral external memory and the registered projection DSP arithmetic
model; it does not measure a physical UART, DDR bus or FPGA timing.

The comparison assumes intact on-chip control and private tag/staging memories,
correct arithmetic/SHA implementations, SHA-256 second-preimage resistance and
correspondence to the physical circuit. It demonstrates these operand
substitutions and pre-use refusals. It supplies no useful-training throughput,
whole-device tamper theorem or certified residual training factor. See the
[K/V guide](../../KV-PROTECTION.md) for the mechanism and its limits.
