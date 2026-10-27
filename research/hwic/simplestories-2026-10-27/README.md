# Experimental SimpleStories HWIC checkpoint — 2026-10-27

This is a preliminary research source checkpoint, **not a qualified ASIC or a
fabricated chip**. It contains the complete executable SimpleStories token
machine, its fixed-weight ROM interface, private K/V memory, independent
reference-fixture generation and a portable reproduction runner. Model weights,
large simulation outputs, process kits and build caches are supplied separately.

The research direction was inspired by Yang Liu et al.,
[*Hardwired-Neurons Language Processing Units as General-Purpose Cognitive
Substrates*, arXiv:2508.16151v2](https://arxiv.org/abs/2508.16151v2).
HNLPU's coefficient grouping, bit-serial computation and model-dependent metal
connections motivate architectures to evaluate. **This checkpoint uses fixed
ROM feeding shared arithmetic.** It adapts our AWIC token core and does not
reproduce HNLPU's custom metal-embedding implementation. We have not established
that ROM is faster or smaller than HNLPU-style routing. See
[references and attribution](REFERENCES.md).

## What is included

- `rtl/`: 67 synthesizable source files and the complete-model testbench, copied
  byte-for-byte from the accepted `compact-compute3-v1-full0` experiment. The
  exact compile order is [sources.f](rtl/sources.f).
- [PROVENANCE.json](PROVENANCE.json): source identities, compile settings, fixed
  asset hashes and the original experiment's receipt identities.
- `reference/` and `tools/`: the unchanged numerical oracle and image derivation,
  a portable adapter for the separate tensor-fixture generator, and a fresh-build
  [replay runner](tools/replay.py).
- `evidence/`: compact validation records with their precise scope. Historical
  results and new checkpoint verification are identified separately.

The selected model is `SimpleStories/SimpleStories-V2-5M`, revision
`c4b3a4bb81297f5316697098e1d4b65c1249daf8`, with 5,354,496 parameters.
It preserves the existing W10/A16/KV16 BFP numerical contract and 2,048-position
hardware context. This is not a new low-bit model conversion.

The deployed top is `hwic_simplestories`. Its public interface accepts APPEND,
STEP and CLEAR through token/status handshakes. It exposes no model loader,
tensor address, arithmetic command or raw K/V memory port. All six transformer
layers, embeddings, normalization, attention and tied output-head arithmetic
execute in RTL; the runtime host supplies no numerical inference.

The main projection engine has four 16-lane tiles. A 640-bit ROM word supplies
64 ten-bit coefficients; the same 64 multiply–accumulate lanes are reused across
columns, output groups, matrices and layers. Other arithmetic units are separate.
The central weights/supporting-data ROM payload is 7,245,312 bytes, with separate
fixed norm/exp leaves; private K/V payload is 7,077,888 bytes. RTL arrays and
`$readmemh` initializers do not establish manufacturable ROM/SRAM macros.

## Reproduce

Use Python 3.12 with NumPy 1.26.4, Verilator and a C++ build toolchain. No board,
AWS instance, commercial tool, network download or host-side numerical provider
is used by the runner. Install dependencies separately; this repository does not
bundle tools or environments.

Supply the canonical SimpleStories Q0 ROM directory from the AWIC reference
workflow. Its eight required filenames, sizes and SHA-256 hashes are in
[q0-receipt.json](reference/evidence/q0-receipt.json). The oracle authenticates
that directory before using it. Original model provenance is the
[pinned publisher snapshot](https://huggingface.co/SimpleStories/SimpleStories-V2-5M/tree/c4b3a4bb81297f5316697098e1d4b65c1249daf8).
The upstream floating-point weights alone are not this Q0 input. Acquisition
and Q0 regeneration are prerequisites; no automatic downloader is included.

From this checkpoint directory, using a new **whitespace-free** work path:

```sh
python3.12 -I -B tools/replay.py \
  --rom /path/to/authenticated-q0 \
  --work /path/without-spaces/hwic-full \
  --build-jobs 16 --sim-jobs 4
```

The runner reconstructs and reverse-checks the fixed image, regenerates reference
fixtures in a separate process, compiles the unchanged complete RTL, and checks
all seven original cases: **53 token outputs and 2,605,355 selected tensor/logit
comparisons**, including cancellation, held outputs, CLEAR/replay and context
admission. It checks exact outputs and checksums, not merely a simulator exit.
This suite does not numerically execute every 2,048-position conversation.

For a shorter complete-model replay, add `--smoke`. To test the checker itself,
use another new work path and add `--smoke --fault-weight`. That command changes
one actual DUT embedding coefficient and must produce a tensor-comparison
failure against unchanged independent fixtures. Its successful fault-detection
receipt is explicitly separate from a numerical design pass.

Every native child receives a PID, argv, log, exit, wall time and individual
`wait4` CPU/resource record. Build products, generated weights and large
comparison fixtures stay under the ignored work directory. The host Python
controller's own CPU time is recorded separately.

## Qualification boundary and next work

The [original RTL validation](evidence/original-rtl-validation.json) covers the
complete model on the stated finite corpus. It is neither a universal formal
proof nor silicon performance measurement. The private research also has mapped
numerical evidence; the full mapped compiler tree and process libraries are not
included in this checkpoint, and this package alone does not reproduce it.

The remaining ASIC work includes qualified physical ROM/SRAM, complete
source-to-layout LVS, unwaived extraction/DRC issues and process-model domains,
clock/reset and manufacturing-test policy, parasitic extraction, PVT timing,
power and whole-chip area. No sign-off, fabricated execution, physical
repurposing resistance or numerical residual training factor is claimed.

The [current physical-memory snapshot](evidence/physical-status-complete.json)
retains a failed full-macro geometry comparison: nwell and poly unions differ.
The cause and representation interpretation remain open. Distinct public nets
and a matching local-interconnect mask do not override that failure.

Architectural research remains open: compare this reusable ROM baseline with
constant-specialized and HNLPU-inspired grouped/bit-serial implementations under
the same numerical contract, then evaluate spatial parallelism and batching
separately. SimpleStories remains first; Qwen3-1.7B remains an active research
target, and Qwen3-8B HWIC work is deferred while its AWIC improves.

The project-owned source follows the existing AWIC Apache-2.0 licensing.
Model-derived assets retain their original MIT provenance; they are not bundled.
See [LICENSE](LICENSE), [NOTICE](NOTICE) and the retained notices in `notices/`.
