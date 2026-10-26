# Greedy SimpleStories qualification

These are the three supplied greedy configurations of SimpleStories-V2-5M on
Tang Mega 138K. They use the same fixed numerical model and nominal 25 MHz
inference clock. Model image SHA-256:
`cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`.

| Configuration | Cached host rate | Selected image SHA-256 |
| --- | ---: | --- |
| Authenticated weights | **10.04 tokens/s** | [01b040cb830cd4c5…](prebuilt/inference/BUILD.json) |
| K/V protection | **7.03 tokens/s** | [90ac68150d0c297b…](prebuilt/kv-protected/BUILD.json) |
| K/V protection + encrypted memory | **6.04 tokens/s** | [cfc8a3d8832b4a29…](prebuilt/encrypted-memory/BUILD.json) |

The encrypted-memory configuration retains K/V integrity and replay checks
and encrypts both weights and K/V. Its supplied keys are public demonstration
values. The [seeded-sampling configuration](STOCHASTIC-GENERATION.md) has its
own [qualification](CURRENT-QUALIFICATION.md), without K/V integrity protection.

## Common speed workload

Each row uses two repetitions of one input token `[378]` and exactly 128
feedback-dependent greedy outputs. CLEAR precedes each repetition; generation
continues through end markers. All 256 output IDs match the pinned numerical
reference. Timestamp each validated reply immediately after the command
returns to the generation loop. Pool 254 cached outputs over the summed elapsed
times from output 1 to output 128 in both trials. First-output request/reply
latency is recorded separately.

The [common protocol](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md),
[source selection](../../benchmarks/fpga-speed/selection.json) and
[computed results](../../benchmarks/fpga-speed/results.json) identify the
images, host sources, output IDs and timing arrays. The rate includes host
control and inter-reply gaps. Browser streaming, fixed-context capacity
calculations and long-prompt first-output latency are separately named scopes.

## Functional and browser coverage

Each selected image passed its complete ten-case CLI campaign, including
395 main reference outputs, both 128-output trials, 128/512/2,047/2,048-token
contexts, input/output-boundary refusals, final CLEAR and three in-flight
STEP/CLEAR race timings. Recovery commands and cancelled outputs have their
own checks and are not added to the 395 main-output count.

Each image also passed seven fresh browser cases and 26 checked outputs:

- A one-token prompt producing four outputs, then a repeated four-output run.
- 128 input tokens producing eight outputs.
- 512 input tokens producing four outputs.
- 2,048 input tokens producing one output.
- 2,047 input tokens with Stop requested after the first STEP was transmitted
  and before any output. Exactly its one completed output is drained, followed
  by CLEAR; no second STEP is sent.
- A new connection after Stop producing the original four expected outputs.

The browser supports 2,048 prompt tokens, 128 new tokens, 2,049 combined tokens
and 32,768 input characters. Its Stop action waits for an active STEP to finish
before clearing. Long-context STEPs can take minutes. The actual downloads,
accessibility snapshots, backend bytes, connection ownership and tokenization
are replayed against the recorded source and numerical-reference identities.

## Full-prompt latency

| Configuration | Browser first output, 2,048-token prompt |
| --- | ---: |
| Authenticated weights | 387.33 s (6.46 min) |
| K/V protection | 1321.28 s (22.02 min) |
| K/V protection + encrypted memory | 1543.98 s (25.73 min) |

Each row is one recorded browser trial producing one correct output. It includes
connection/setup as applicable and prompt upload, and is not a sustained cached
generation rate or a latency guarantee. The cases use the same public prompt
and critical host sources. Their exact downloads and backend records are part
of the corresponding browser capsules.

APPEND records tokens without evaluating the transformer. The first STEP
evaluates all prompt positions through the fixed six-layer path; causal
attention visits increasingly long prefixes. Parallel private attention and
memory reuse reduce that work, but this remains a position-major prompt path.

## Source and proof scope

The portable checks join each selected source inventory, completed native
route, implemented Tcl, static-path observations, model comparisons, mapped
primitive observations and actual CLI/browser captures. All three browser
campaigns use the same critical host source graph. The shared host's 79 fixture
tests and their exact 125-source snapshots have separate recorded evidence.

The [formal-status guide](FORMAL-STATUS.md) states the actual scoped RTL
properties, arbitrary private-service boundaries and unresolved conclusions.
The baseline has 34 attention-controller assertions. The protected design has
its 357-assertion joint cache scope including support, plus a separate 34-assertion
attention scope. The encrypted design's attention bridge rechecks the same 34
assertions through six byte-identical isolated sources; it adds no assertions
and supplies no encrypted-guard/SIV theorem. Counts are nonadditive.

These records establish functional qualification within the tested conditions.
They do not establish complete vendor-DDR timing signoff, continuous independent
attestation of the loaded FPGA, a universal numerical theorem, whole-machine
refinement, cryptographic security or physical-security certification.

## Offline reproduction

From a clean repository copy, install the pinned host dependencies, then run:

```sh
python3.12 -I -S -B ../../tools/verify_release.py --strict
python3.12 -I -B tools/check_current_three_greedy_v15_v4.py --package . --stage current --index evidence/current-greedy/INDEX.json
python3.12 -I -S -B ../../tools/fpga_speed_benchmark.py --check
```

These commands recheck recorded bytes, source associations and outcomes. They
operate no FPGA, programmer, model executable, solver or network service.
