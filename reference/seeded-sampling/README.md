# Exact seeded model reference

This offline numerical reference reproduces the finite fixed-point sampler and
the complete integer SimpleStories model. It includes 48 fixed transcripts:
all four temperatures and seeds A/B for `around128`, `prefix128`, `prefix512`,
`prefix1024`, `prefix2047`, and `prefix2048`. Their 2136 output IDs, per-output
raw-head digests, final K/V digests, and final PRNG states are pinned in
[goldens/INDEX.json](goldens/INDEX.json). Six separate 32-output fixtures cover
zero and all-ones seeds at positive temperatures in
[domain-goldens/INDEX.json](domain-goldens/INDEX.json); zero maps to PRNG state
`(1, 0)`, as does seed one.

No private model directories or downloads are required. The included plaintext
model image contains all coefficients, scales, and numerical tables.
`reconstruct_rom.py` reverses its documented packing into the exact eight
canonical Q0 ROM files. Every byte count and digest must match the existing
public Q0 receipt and the unchanged authenticated integer loader. Rebuilding
the full FPGA model image from those ROMs must reproduce its exact hash
`cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`.
This does not modify a model or access a board.

Use Python with the pinned `numpy==1.26.4` environment in
[../requirements.txt](../requirements.txt). From the repository root, choose
new output directories outside the repository for these commands:

```sh
python -I -B reference/seeded-sampling/reconstruct_rom.py --output /tmp/seeded-rom
python -I -B reference/seeded-sampling/test_reference.py --engine native
python -I -B reference/seeded-sampling/run_reference.py \
  --rom /tmp/seeded-rom --engine native --build-dir /tmp/seeded-native \
  --output /tmp/seeded-reference-all
```

`native` requires a local Clang or GCC C++ compiler with `__int128`. It compiles
only the integer normalization/rounding kernel, with no external libraries or
downloads. Compiler outputs stay outside the source package. `scalar` uses the
original Python arithmetic and never compiles or loads that kernel:

```sh
python -I -B reference/seeded-sampling/run_reference.py \
  --rom /tmp/seeded-rom --engine scalar --case around128 --temperature 1 --seed a \
  --output /tmp/seeded-reference-scalar
python -I -B reference/seeded-sampling/run_reference.py \
  --rom /tmp/seeded-rom --engine native --build-dir /tmp/seeded-native \
  --domain --output /tmp/seeded-reference-seed-domain
python -I -S -B reference/seeded-sampling/check_package.py
```

With no case/settings filters, the runner replays all 48 fixed transcripts.
It shares the nested prompt prefill, then independently generates each output
tape. `--domain` selects the six additional seed fixtures. Each finished replay
compares every output, raw-head digest, K/V digest, and PRNG state. The package
checker uses only the standard library to verify file identities and fixture
geometry; it does not perform model inference. A complete scalar full-context
prefill can take roughly 47 minutes; the checked native normalization kernel
reduces that work substantially. These are host replay runtimes, not FPGA
performance measurements.

`model.py` imports the unchanged original integer model, retaining its exact
matrix, residual, RMSNorm, SiLU, RoPE, and attention arithmetic. `context2048.py`
extends its context/RoPE geometry and attention-denominator bound to 42 bits,
matching the existing 2048-position design. The extended RoPE tables and their
original 512-position prefixes are checked exactly. Native mode changes only
the normalization and signed shift loops; wide integer intermediates preserve
Python rounding and reject overflow. Tests compare 32991 randomized elements,
1326 normalization boundary vectors, signed RNE tie neighborhoods, and whole
model tokens, K/V state, and arithmetic statistics with the scalar source.
Synthetic range faults must latch before a position commits; CLEAR restores
the reference state. These bounded checks are not a formal equivalence proof.

Selection uses all 4019 exact signed head products and source exponents. It
aligns them to the first row's exponent minus two and uses the immutable Q30
table. Positive temperature takes one xoroshiro128++ draw per completed output,
computes `floor(random_u64 * total_mass / 2**64)`, then selects the first strict
CDF crossing. Greedy consumes no PRNG state; prefill consumes no draws. This is
the implemented finite distribution, without a claim of exact floating-point
softmax or independent physical randomness.

`compare_board.py` separately checks a sanitized physical-case JSON containing
`case`, `temperature`, `seed`, `prompt_tokens`, `generated_tokens`,
`image_sha256`, and an ordered `wire` array of `{direction, frame_hex}`. The
optional boolean `replay_without_settings` selects a CLEAR replay. Its normal
plan is CLEAR, optional SETTINGS, prompt APPENDs, STEP outputs, final CLEAR.
`--context-matrix` checks the richer qualification sequence: one SETTINGS,
three four-output recovery probes with empty STEP rejection, the long prompt,
capacity rejections where applicable, and final CLEAR. Both modes check raw
frames, CRCs, and every output against the pinned goldens:

```sh
python -I -S -B reference/seeded-sampling/compare_board.py \
  --physical-case SANITIZED-CASE.json \
  --golden reference/seeded-sampling/goldens/prefix2048-t2-seed-a.json \
  --context-matrix
```

These tools have no UART, flash, programming, network, or RTL execution path.
Software references do not attest a physical FPGA configuration, close timing,
prove whole-machine refinement, or establish physical security. The existing
model/image license and third-party provenance continue to apply. `SOURCE.json`
records the exact source and package bindings; original historical evidence is
retained separately with its original claim scope.
