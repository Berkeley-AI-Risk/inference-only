# SimpleStories: public memory options and detailed attention profile

November 5, 2026 Pacific. Experimental research; no new physical implementation.

Public sources are sufficient to make the next feasibility study more concrete.
TSMC 28HPC+ is the leading commercial process candidate for investigation, with
named via-ROM and SRAM families and a documented access route. This is a
candidate selection, not a finding that our complete chip fits or meets timing.
Actual instance geometry, PVT timing, compiler terms and cost remain unresolved.
No specific compiled memory instances are bound to this design yet. Public
screening can proceed alongside the attention work and preliminary sizing.

The attention study contains 30 distinct tensor workloads and 42 positive
kernel replays, checking 10,752 scalar outputs, plus a rejected wrong-output
control. The current arithmetic RTL was unchanged. A service model reproduces
the accepted full-model attention clocks exactly at contexts 1, 2 and 16.

## Memory/process shortlist

| Candidate | Public evidence | Remaining decision |
| --- | --- | --- |
| TSMC 28HPC+, Synopsys | Single-port via-ROM and high-speed SRAM catalog entries use the same named process | Obtain legal bank geometries and area/timing evidence; check standard-cell/process-stack compatibility, access and price |
| TSMC 28HPC, Dolphin Technology | Diffusion/via ROM compilers and SRAM families with published depth, width and capacity envelopes | Check specific legal organizations and instance area/timing; 28HPC is a distinct process label from 28HPC+ |
| TSMC 40 ULP eFlash, Silvaco | ROM part 61255 and dual-port SRAM part 61253; published capacity ranges and supply options | Check width/depth combinations, physical area, corner timing and actual compiler availability |
| IHP SG13G2 public kit | Actual SRAM layout/timing views already screened | Suitable to consider for component demonstrations; current full-capacity KV screen is about 203 mm² and the fixed-ROM path remains unresolved |

The primary candidate's named products are
[via-ROM](https://www.synopsys.com/dw/ipdir.php?c=dwc_comp_ts28nph41p10asdvl01ms)
and [SRAM](https://www.synopsys.com/dw/ipdir.php?c=dwc_comp_ts28nph41p11sassl01ms).
No capacity, area or achieved clock is inferred from those product names.

Dolphin's [28HPC catalog](https://dolphin-ic.com/products/memory/tsmc_28hpc_mem.html)
advertises single-port SRAM up to 8K words deep, 288 bits wide and 288 Kbit per
instance, plus larger multi-bank configurations and immutable ROM compiler
families. An organization of 216 banks of 1,024×256 bits covers our KV capacity
and falls within those advertised maxima. That is an engineering proposal:
the page does not establish that every combination is compiler-legal, nor give
area or corner timing for our instance. It explicitly requires an NDA for views.

Silvaco lists ROM capacities up to 1,152k bits and SRAM capacities up to 288k
bits on the 40 ULP eFlash process. Treating k as 1,024, the current central
57,962,496 fixed bits and 56,623,104 KV bits need at least 50 ROM and 192 SRAM
instances at those maxima. These are **capacity-only lower counts**, not a legal
bank layout. The advertised ROM mux range is not a word-width specification.
[ROM catalog](https://silvaco.com/products/design/design-ip/foundation-ip/memory-compilers/rom-compiler/),
[SRAM catalog](https://silvaco.com/products/design/design-ip/foundation-ip/memory-compilers/sram-compiler/).

A public ordinary-ROM sizing reference is [TOM, Table II](https://arxiv.org/html/2602.20662v1#S5.T2):
1.308 MB/mm² at 28 nm for compiler-generated 2,048×64 ROMs. Tiling our central
weight and miscellaneous ROM geometries requires 420 and 32 banks respectively,
or 452 banks containing 7,405,568 bytes with padding. Dividing by the published
density gives **5.40–5.66 mm²** of reference ROM rectangles; the range brackets
binary versus decimal interpretation of the paper's MB unit. This uses the
ordinary ROM reference, without ternary quantization or TOM's custom sparsity
gain. Foundry, compiler, corner latency and legal bank availability are not
identified by that table. Bank selection, integration and the rest of the chip
remain to be accounted for.

A useful public sizing reference comes from Yokoyama et al.,
[*Disturbance Aware Dynamic Power Reduction in Synchronous 2RW Dualport 8T SRAM
by Self-Adjusting Wordline Pulse Timing*](https://www-vlsi.es.kit.ac.jp/thesis/papers/pdfs/JSSC-22-0279.R2.pdf).
The author-hosted manuscript's page 9, Table II was visually checked. Its
fabricated 28 nm eFlash test macro is 1,024×48 bits and 95.3×297.1 µm, with
typical 1.54 ns read access and 455 MHz frequency. Six width slices and 216
depth banks would cover our 221,184×256 KV geometry: 1,296 macro rectangles,
**36.694 mm²**, before glue, clocks, power distribution and IO. This is a
research-macro sizing scenario. Its foundry/compiler identity is not bound to
our 28HPC+ candidate, and its typical frequency does not establish 500 MHz or
worst-corner operation. Fixed weights and compute are excluded.

This public evidence supports investigating a denser mature process. It does
not support adding a ROM density from another process to claim a complete die.
Whole-chip area remains unknown. Both shortlisted commercial paths retain
manufactured immutable weights; loading the weights into writable SRAM would
change the HWIC architecture.

For later implementation, Europractice documents
[TSMC access procedures](https://europractice-ic.com/technologies/asics/tsmc/access-contacts/)
and [standard-cell/backend access](https://europractice-ic.com/technologies/asics/tsmc/tsmc-scl/).
Eligibility and entitlements for this project have not been established.
Backend access may require a firm tapeout plan and review. We have made no
vendor contact, signed no agreement and purchased no license. The next inquiry
should request legal geometries for 84,720×640 and 14,616×256 ROM, 221,184×256
KV, and the smaller banked scratch stores, together with instance area, PVT
latency/throughput, repair/test requirements and evaluation/redistribution terms.
The machine-readable [shortlist](evidence/attention-profile-2026-11-05/results.json) retains the facts,
sources and missing inputs.

## What the attention runs measured

The isolated build uses six files from the accepted integrated source corpus:
the attention FSM, synchronous memories, exact multipliers, exponential table,
iterative shifter and divider. All six were checked against the accepted source
proposal. The testbench adds observation counters and a private cache/query
service model; it changes no arithmetic module.

Eighteen workloads use the accepted around-case Q/K/V and attention outputs
for all six layers at contexts 1, 2 and 16. Twelve longer workloads repeat the
16-position post-RoPE K/V sequence at contexts 128 and 2,048. Their expected
outputs come from the pinned integer oracle and its previously accepted
2,048-position extension. That extension has a 42-bit softmax denominator,
matching the RTL; the original 512-position oracle's 40-bit guard is unsuitable
for some long workloads. All six original context-16 outputs also match this
oracle. The longer workloads are synthetic **attention-only** tests, not new
full-model long-context coverage or model-quality tests.

The current-service model uses the source's two-cycle scalar query reads,
64-cycle result draining, staged current-position bypass and a calibrated
historical-row response delay. Its summed six-layer clocks match the retained
full-model attention counters exactly at all three short contexts. The model
does not characterize a physical SRAM. Whole-model 128/2,048 timing remains
unmeasured for the current candidate.

| Context | Six-layer attention clocks | Division service | KV request/response | Serial QK + AV |
| --- | ---: | ---: | ---: | ---: |
| 1, accepted tensors | 104,072 | 71.95% | 0.12% | 2.98% |
| 2, accepted tensors | 114,918 | 66.16% | 3.34% | 5.38% |
| 16, accepted tensors | 257,370 | 35.81% | 21.73% | 19.25% |
| 128, repeated tensor workload | 1,385,756 | 15.96% | 34.10% | 28.60% |
| 2,048, repeated tensor workload | 20,729,516 | 11.74% | 36.73% | 30.59% |

These are disjoint FSM service families. Divider busy, cache wait and child
state counters overlap those families and must not be added again. Division
includes requests and response handling as well as busy clocks. Shifting,
alignment, normalization and local data movement account for the remaining
cycles. The public [profile](evidence/attention-profile-2026-11-05/results.json) retains
state counts, source identities and recorded exit summaries. The
[offline checker](evidence/attention-profile-2026-11-05/check_recorded_profile.py)
recomputes recorded arithmetic; it does not replay the private tensors. Actual
fixture/log pins and numerical-run checks remain in private research evidence.

The kernel makes 4C key requests, 4C value requests and 2C exponent-scan requests
per layer. Its divider busy count is exactly `46 × (4C + 256)` per layer. Value
output division by the fixed denominator 32,767 accounts for 70,656 busy clocks
across all six layers, independent of context. That is a concrete short-context
optimization target; its relative value shrinks at longer contexts.

## Memory-service sensitivity and optimization order

Twelve additional positive replays reduced modeled historical-row extra delay
from 59 to 14 clocks, retaining the same data and expected outputs. Attention
fell to 1,042,856 clocks at context 128 and 15,202,616 at 2,048: respectively
1.329× and 1.364× kernel speedups. These are actually replayed **behavioral
latency scenarios**. They do not implement a new memory controller or establish
its clock, area or power. An intentionally corrupted expected output was
rejected at head 0 with a genuine nonzero native exit.

The next architecture work should therefore:

1. Reduce serialized KV service overhead and redundant reads, while preserving
   typed ownership and CLEAR semantics. Use public macro latency/port scenarios
   to budget the controller before committing to a physical memory.
2. Evaluate parallel QK/AV lanes together with sufficient data delivery. At long
   context, speeding arithmetic alone leaves substantial KV service time.
3. Evaluate exact constant-denominator output division and faster shared RNE
   division for short contexts. Any arithmetic replacement needs independent
   numerical and protocol checks and should be reusable by AWIC and HWIC.
4. Keep whole-model clock/area/power and matched H100 comparisons separate from
   these kernel results. No new physical optimization starts from this profile.

The detailed profile uses the V5 harness and its recorded source pins.
The standalone build took seconds and used about 300 MB peak native RSS,
avoiding a rebuild of all spatial matrices. Native receipts retain CPU/wall
measurements, failures and the negative control; reference preparation and
research/review costs are recorded separately where measurable. New paid-service
charges are zero; provider tokens, billing and total research cost are unknown.

This remains HNLPU-inspired generated RTL research. It does not reproduce
[HNLPU's custom physical weight routing](https://arxiv.org/abs/2508.16151v2).
