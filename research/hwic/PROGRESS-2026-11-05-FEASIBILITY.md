# SimpleStories HWIC: memory feasibility and current performance profile

November 5, 2026 Pacific. This is an experimental research assessment.

**The assessment is complete; full-chip feasibility is still unproved.** The
current SimpleStories model declares 7.25 MB of central fixed storage and
7.08 MB of KV storage at its configured 2,048-position capacity. No qualified
ROM/SRAM set in one manufacturable process has been bound to it. Current
profiling also shows that improving query projections alone cannot deliver the
overall throughput goal. Further physical optimization is on hold while these
memory and performance decisions are resolved.

This follows the feasibility review's recommendation to evaluate the complete
model before spending more time on a block. It preserves the accepted numerical
and block implementation results. It does not establish a chip area, clock,
power, token rate or manufacturing qualification.

## First target and memory requirements

SimpleStories-V2-5M remains the first complete HWIC target, with unchanged
W10/A16/KV16 BFP-v5 arithmetic and 2,048-position source capacity. One dependent
conversation is the latency baseline; batch aggregate throughput is a separate
comparison. Die area, package, power and cost budgets remain undecided. A matched
H100 comparison remains the performance objective; no such win is demonstrated.

| Declared storage | Geometry or source count | Requirement |
| --- | --- | --- |
| Central fixed weights | 84,720 × 640 bits | 6,777,600 bytes |
| Central fixed miscellaneous data | 14,616 × 256 bits | 467,712 bytes |
| KV at configured capacity | 221,184 × 256 bits | 7,077,888 bytes |
| Central fixed data plus KV | Sum of those three rows | **14,323,200 bytes / 13.660 MiB** |
| Other mutable unpacked arrays | Source declarations, including new normalizers and bank padding | 583,592 bits |
| Spatial row cut/output registers | Separate source-level pipeline census | 761,598 bits |

These are capacity and declaration counts, not total physical memory or a mapped
register census. Scalar/control registers remain outside the last two subtotals.
Gamma and exponential constants add 244,256 declared bits. One shared 16-lane
SiLU stage serves all six layers; its logical tables contain 2,359,296 bits.
Four fixed layer-0 matrix encodings overlap 5,893,120 bits in the central image.
Removal of those central copies, further constant sharing and synthesis pruning
have not been proved. These encodings are arithmetic/wiring, not dense SRAM.

The central ROM has one synchronous request stream shared by the 640-bit weight
and 256-bit miscellaneous records, with a held response. KV has one synchronous
256-bit read **or** write stream. Writes retire on acceptance; reads have held
responses. CLEAR revokes committed ownership without resetting every data bit.
Scratch arrays need their own 1R1W, banked, FIFO or parallel-register contracts.
The alternative ROM16 query block needs sixteen concurrent 640-bit bank reads;
it is not an additional memory in the integrated grouped candidate.

All 1,965 current source pins were checked against the accepted Make inputs for
this inventory. Running at context 128 would still allocate the configured
2,048-position KV store. A smaller capacity requires an explicit RTL and
verification change.

## Real-process memory screening

The following calculation tiles only the current **KV** geometry. Width slices
operate together and depth banks require selection/output logic. It excludes
halos, glue, repair/ECC, clocks, power distribution, compute and IO. It is neither
a floorplan nor a claim that the listed wrappers meet the current interface.

| Reviewed SRAM example | Width slices × depth banks | Instances | KV macro rectangles, mm² |
| --- | ---: | ---: | ---: |
| IHP SG13G2 8,192 × 32 | 8 × 27 | 216 | 203.022 |
| IHP SG13G2 2,048 × 64, BIST variant | 4 × 108 | 432 | 212.386 |
| GF180MCU 512 × 8 | 32 × 432 | 13,824 | 2,894.749 |
| ChipFoundry listed 8,192 × 32 offering | 8 × 27 | 216 | 289.440 |

For IHP, the areas come from six exact LEF/Liberty files at commit
`5e6d592e4002946a4616f798c357f0f3c06cf3b6`; byte counts and Git blob identities
were checked and are retained in the [metrics](evidence/memory-profile-2026-11-05/metrics.json).
The 8,192 × 32 rectangle is 1,520.16 × 618.3 µm. Its clock-to-Q tables span
5.5345–5.8048 ns at typical 1.20 V/25°C and 9.2587–9.6611 ns at slow
1.08 V/125°C. The reviewed 2,048 × 64 tables also exceed 5 ns typical and 8 ns
slow. Consequently these are **not direct one-cycle substitutes for a 2 ns
memory interface**. Lower clocks or added memory latency require a revised,
verified controller. Clock-to-Q alone does not determine chip maximum frequency.
See the [IHP SRAM library](https://ihp-open-pdk-docs.readthedocs.io/en/latest/contents/reference_libraries/sram.html)
and [pinned public views](https://github.com/IHP-GmbH/IHP-Open-PDK/tree/5e6d592e4002946a4616f798c357f0f3c06cf3b6/ihp-sg13g2/libs.ref/sg13g2_sram).

The GF180 example uses the official 431.86 × 484.88 µm dimensions. Its published
1.8 V typical minimum period is 23.5606 ns. This screens that particular small
macro; it does not rule out every GF180 memory architecture. The ChipFoundry
row uses the vendor's listed 1.34 mm² per 32 KiB Wishbone-wrapped offering;
its timing and raw-port integration were not qualified here.
[GF180 datasheet](https://gf180mcu-pdk.readthedocs.io/en/latest/IPs/SRAM/gf180mcu_fd_ip_sram/cells/gf180mcu_fd_ip_sram__sram512x8m8wm1/gf180mcu_fd_ip_sram__sram512x8m8wm1.html),
[ChipFoundry offering](https://chipfoundry.io/commercial-sram).

IHP is a real fabrication process, but its public release describes itself as a
preview rather than a production-qualified kit. Reading published views does
not qualify our integration. Local Sky130 OpenRAM/OpenROM experiments retain
model, interface, characterization or physical-verification gaps; the SRAM22
study retains a strict LVS/model-domain gap. These cannot be combined with the
predictive Nangate45 query result as one chip.
[IHP release status](https://github.com/IHP-GmbH/IHP-Open-PDK#readme).

**SRAM is volatile: these rows do not solve immutable weight storage.** We need
qualified mask/via ROM or characterized fixed logic in the same process as the
SRAM and standard cells. A concrete commercial catalog path exists: Synopsys
lists both [via ROM](https://www.synopsys.com/dw/ipdir.php?c=dwc_comp_ts28nph41p10asdvl01ms)
and [SRAM](https://www.synopsys.com/dw/ipdir.php?c=dwc_comp_ts28nph41p11sassl01ms)
for TSMC 28HPC+. The catalog establishes product families, not access, legal
macro geometries, density, timing, license price or a feasible die. Those inputs
remain unavailable. This study made no vendor contact or purchase.

The screened open macros therefore do not establish a compact full-model chip
at the assumed clock. No whole-chip size range is defensible yet. The typed KV
interface does not itself require HBM, but an HBM-free physical implementation
has not been demonstrated. External KV would add interface and integrity/state
protection requirements; its area and traffic must be compared explicitly.

## Current full-model cycle profile

The retained [full-model regression](PROGRESS-2026-11-04.md) already contains
the necessary aggregate counters. Nine relevant source identities and all seven
terminal log identities were rechecked. All 53 token checkpoints have zero
counter-accounting gaps. No new simulation was needed.

For the clean context-1 step, the harness measures **425,148 logical clocks**:
418,121 active clocks plus 7,027 E_IDLE clocks.

| Disjoint active stage family | Clocks |
| --- | ---: |
| Attention, including softmax, normalization and KV reads | 104,072 |
| GATE/UP/DOWN projections | 101,741 |
| Layer RMS | 58,764 |
| Q/K/V/O projections | 54,492 |
| Output head, including argmax | 35,692 |
| RoPE | 34,632 |
| Residual elementwise operations | 21,576 |
| SiLU × UP | 4,410 |
| KV stage/commit | 2,742 |

Across the four clean complete workloads, attention consumes **25.53–36.74%**
of active clocks; SiLU × UP consumes **0.90–1.05%**. Cancellation cases remain
in accounting but do not set performance ranges. The first fox/moon outputs
include prefill and are not standalone cached steps. ENGINE and STAGE counters
are overlapping views; nested unit counters must not be added. E_IDLE includes
useful embedding/final RMS as well as sequencing and test handshakes.

The previous October 29 partial-model 1.47× projection ceiling is historical.
For current context 1, optimistically deleting all Q/K/V/O and GATE/UP/DOWN
service clocks (156,233 clocks, excluding the separately listed output head)
would give 1.597× active-clock or 1.581× full-counter speedup. That removes
normalization and waits too; arithmetic-only improvements yield less. Further
SiLU optimization now has little end-to-end headroom. Attention, normalization
and data movement deserve the next architecture investigation alongside the
remaining matrix work. Exact QK/softmax/AV/cache-wait attribution still needs
attention substate counters.

| Context including current token | Current measured full-model clocks | Logical KV read bytes/step | Unvalidated sensitivity clocks |
| --- | ---: | ---: | ---: |
| 1 | 425,148 | 0 | — |
| 128 | Unmeasured | 1,219,200 | 1,442,410–1,967,682 |
| 2,048 | Unmeasured | 19,651,200 | 16,821,610–25,288,002 |

The current source issues 300(C−1) 256-bit reads and 108 writes per ordinary
step. The current position bypasses RAM reads; writes add 3,456 bytes. This
matches checked cache counters in all four clean cases. It describes logical
port traffic, not measured off-chip bandwidth.

The last column holds non-attention work fixed and applies the observed
adjacent-context attention increment envelope, 8,010–12,146 clocks, to larger
contexts. Operand-dependent shifts and normalization affect these increments.
**This is a sensitivity scenario, not a bound, confidence interval or validated
long-context forecast.** The current integrated numerical corpus reaches
context 16. Older 512/2,048-position runs do not qualify this newer candidate.
At a hypothetical 500 MHz, context 1 converts to about 1,176 steps/s; this is
not an achieved ASIC rate. Physical memory latency may change the schedule.

## Performance comparison and next decision

The [selected H100 reference](../../docs/benchmarks/H100-BENCHMARK.md) is
2,951,332.875 repeated fixed-context evaluations/s at context 128 and batch
32,768. A historical Transformers 4.48.3 batch-one compiled test measured about
6,513 evaluations/s. Neither is bit-exact HWIC autoregressive generation; the
current shared reference uses Transformers 5.17.0. The Qwen batch-one GPU rate
must not be substituted for SimpleStories.

As an aggregate-throughput stress test only, applying the current HWIC KV
schedule at the H100 aggregate evaluation rate demands **3.598 TB/s of logical
read traffic** at context 128. A 256-bit port at an assumed 500 MHz supplies at
most 16 GB/s: about 225 port equivalents before write/latency overhead. This
does not prescribe 225 physical ports; reuse, parallel streams and banking
change the architecture. It explains why hardwired projections alone are
insufficient for the aggregate target. No matched batch-one or aggregate GPU
victory is claimed.

The decision is to retain both ROM16 and grouped/spatial as architectural
options, keep the existing grouped physical attempt capped, and start no new
physical campaign until a common-process memory/logic path and a whole-model
cycle/traffic budget are credible. The next bounded physical test should be
a real-memory interface plus compute block, with explicit banking, muxing,
held responses, stalls, CLEAR, clocking and power connections. It needs actual
ROM/SRAM views, corner timing and an agreed capacity/area target first.

The existing ROM16 query result remains a one-block predictive-process result:
107 clocks, 2 ns target, native router DRVs 0, extracted setup +0.03048 ns,
hold +0.03960 ns and TNS 0 at the reviewed typical corner. Logical/SPEF coverage
was accepted with recorded exceptions. Geometric terminal connectivity, LVS,
power grid, corners, final-point numerical replay/power and full-chip closure
remain open. The earlier November 4 power figures belong to earlier netlists.

SimpleStories first remains worthwhile because the complete memory binding,
attention interfaces and verification methods can be reused on Qwen. Qwen needs
its own capacity, context and bandwidth study before physical work; its much
larger weights and KV do not inherit SimpleStories feasibility. Qwen 8B HWIC
remains deferred. Reuse of AWIC/HWIC arithmetic, interfaces and tests remains
a main goal.

The [compact metrics](evidence/memory-profile-2026-11-05/metrics.json) retain
source/log identities and the arithmetic inputs. To recompute capacities,
macro tiling, counter sums and traffic from those recorded inputs:

```sh
python3 -I -S -B research/hwic/evidence/memory-profile-2026-11-05/check_feasibility.py --check
```

This checks recorded arithmetic; it does not replay private logs, validate
macro circuits or reproduce the unpublished current candidate. The
[October 27 RTL checkpoint](simplestories-2026-10-27/README.md) remains the
standalone public source baseline. This assessment launched no new EDA, model,
simulation or cloud job and incurred no new paid-service charge. Provider token
counts, billing, local energy and total research cost remain unavailable.

The research draws on [HNLPU, *Hardwired-Neurons Language Processing Units as
General-Purpose Cognitive Substrates*, arXiv:2508.16151v2](https://arxiv.org/abs/2508.16151v2).
Our generated RTL and standard-cell experiments have not reproduced HNLPU's
custom physical weight routing or established its silicon performance.
