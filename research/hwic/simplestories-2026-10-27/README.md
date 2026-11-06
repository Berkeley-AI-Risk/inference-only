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

## Configuration and evidence

The public ROM design is the reproducible baseline. Later experiments explore
spatial compute, a smaller K/V store and reuse of the AWIC's parallel attention
architecture. The [configuration map](../evidence/configuration-map-2026-11-06/rows.json)
records their exact source selections, compile settings and dated evidence.

| Implementation | Architectural change | Validation as of November 6, 2026 |
| --- | --- | --- |
| Published ROM baseline | Shared projection arithmetic fed by fixed ROM, with private K/V | Seven complete-model cases, 53 outputs and 2,605,355 comparisons; public replay below |
| Integrated spatial candidate | Layer-0 spatial projection paths and SiLU16 | [Complete regression](../PROGRESS-2026-11-04.md), including 28 genuine circuit-fault checks |
| Split K/V candidate | Separate payload and metadata banks replace the flat K/V backing RAM | Component, admission and 28 fault checks passed; complete positive corpus pending |
| Attention reuse candidate | Eight QK lanes and eight AV lanes, GQA pair-row reuse and prefix summaries from the AWIC | Source review complete; compilation and numerical validation pending |

These experiments target the same fixed numerical contract and token interface.
The newer three selections have separate source snapshots; their full RTL/build
inputs are not bundled here. The public replay rebuilds the ROM baseline.
Native compiled runs use Verilator with `SYNTHESIS` defined and do not establish
four-state/X-clean behavior.

### Reuse with the selected AWIC

The ROM baseline shares **39 byte-identical source files** with the selected
fixed-baseline Tang AWIC identified by
[`hardware-inputs.json`](../../../demos/simplestories-v2-5m/host-app/hardware-inputs.json).
Shared files include exact integer arithmetic, projection and elementwise
operators, vector scratch RAMs and semantic sequencing. The configuration map
contains the complete comparison, including changed files at shared paths.

This reuse offers a way to maintain common arithmetic and carry targeted
operator tests across designs. Each consumer still needs its own build and
integration checks: for example, the Tang build enables
`BOARD1_PROJECTION_MAC_NATIVE`, while the HWIC replay does not. File matches
include potentially uninstantiated modules, so they do not measure the fraction
of gates reused. Source-bound proofs and FPGA results apply to their named
circuits; they do not qualify an ASIC successor.

The attention proposal adds two exact AWIC files to the HWIC selection. Eight
parent bindings connect layer identity and value-staging/commit events to the
AWIC prefix summaries, while retaining HWIC arithmetic leaves. This integration
needs its own unchanged-golden admission, fault and full-model regression.
Its workspace and accumulator arrays add **42,384 bytes**, before prefix/control
state; speed and physical cost remain to be measured.

A later common-source candidate is
`board1_unified_projection_head_dynamic_mul_exact.sv`. Maintaining one
implementation could reduce arithmetic drift. Extraction requires explicit
compile/parameter bindings, exact results for each used mode, correspondence
for any selected vendor primitive, and affected integration regressions.
Frozen experiments retain their original source copies; this checkpoint makes
no source consolidation.

### Memory and process decision

**Hold further physical optimization until a compatible memory/process plan
meets the complete model's requirements.** The
[Dolphin TSMC 28HPC+ memory catalog](https://www.dolphin-ic.com/tsmc_28hpc%2B_mem.html)
identifies a candidate family, not a selected set of legal macro instances.
The next physical step requires:

1. Access to compatible ROM, SRAM, standard cells and I/O in one process.
2. Legal macro geometries and ports, with layout views and timing/power
   characterization across the required process, voltage and temperature corners.
3. A complete capacity, banking, bandwidth, area and clock budget using those
   implementations.

The functional central ROM contains **84,720 640-bit weight words** and
**14,616 256-bit supporting-data words**. It can accept one request per clock
with continuous response readiness; physical ROM banking and an achieved chip
bandwidth remain unresolved. The spatial experiments add four layer-0
constant-specialized matrices. Whole-model ROM pruning and complete logic area
remain open.

The split K/V candidate uses **192 1,024-by-256-bit payload banks** and
**12 2,048-by-16-bit metadata banks**: **6,340,608 array bytes**, versus
7,077,888 in the flat baseline. The 10.4167% capacity saving excludes read
pipelines, tags, controls and workspace; it is not a measured area or power
saving. K/V remains private and typed. CLEAR invalidates logical authority
and drains accepted work without zeroizing the payload.

Banking alone leaves the transport cost intact. At SRAM read latency one,
the unchanged typed path takes **61 cycles for a committed K-only or V-only
row and 109 for a full row**. The former core/application boundary already uses
one clock on both sides, so a direct same-clock bridge is a concrete scheduling
option. It has no RTL prototype or measured speedup yet. The
[memory feasibility assessment](../PROGRESS-2026-11-05-FEASIBILITY.md) and
[attention profile](../PROGRESS-2026-11-05-ATTENTION.md) provide the supporting
capacity and service-cost analysis.

ROM16 remains the lead query-block diagnostic; the grouped approach remains a
capped comparator. Those block studies leave whole-chip memory implementation,
PVT timing, physical verification, DFT, power integrity and activity-based power
analysis open.

From the release root, recompute the public source comparison and check the
recorded scope and capacity arithmetic:

```sh
python3.12 -I -S -B research/hwic/evidence/configuration-map-2026-11-06/check_rows.py
```

This is a file-consistency check; the RTL replay is below.

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
