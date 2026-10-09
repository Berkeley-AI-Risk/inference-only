# Hardware architecture and implementation notes

This guide describes the baseline and K/V-protected layouts. The
third configuration has an encrypted external-memory path, a four-bank weight
cache sharing two AES and two SHA engines, four time-shared projection multiplier
lanes, and a different physical K/V layout; see [ENCRYPTED-MEMORY.md](ENCRYPTED-MEMORY.md).

This document is for readers familiar with RTL, FPGA implementation and
accelerator design. The [README](README.md) introduces the demo;
[INFERENCE-ONLY.md](INFERENCE-ONLY.md) assesses the restricted design, and
[FORMAL-STATUS.md](FORMAL-STATUS.md) separates
proved properties from remaining obligations.

The source links below describe the supplied baseline circuit:
the physically tested design with private weight prefetch, phase-selective
K/V reads, exact normalizer/divider shortcuts, four-round-per-cycle weight hashing and
packed attention values. Its model, numerical rules and three public commands
are fixed. The current baseline passed [model and board tests](VALIDATION.md#current-baseline-image).
The current protected and encrypted images have their own
[board tests](VALIDATION.md#current-protected-and-encrypted-images).
Supplied files do not attest the configuration currently running on any other board.

The separately supplied K/V-protected configuration retains this
model and public interface, but inserts a private integrity guard between
the atomic K/V controller and typed DDR boundary. It also includes transport
and reset/startup changes required by that implementation. Its complete
custom source tree is in `variants/kv-protected/hardware/`; the baseline is
in `hardware/`. Both include the same exact-arithmetic shortcuts.
For weight-page checking, the baseline uses four SHA-256 rounds per cycle
and the protected configuration uses two; both retain all 64 rounds. Both store
aligned attention values in eight 128-bit rows. These are private
implementation choices, not user controls. Only the protected version has
the K/V guard and its private expected-digest storage.
See [KV-PROTECTION.md](KV-PROTECTION.md)
for digest granularity, freshness, buffering, source identities and costs.
Unless explicitly stated otherwise, the source links, schedules and
implementation figures below describe the baseline, not the protected image.

## Fixed workload and numerical contract

| Property | Implemented value |
| --- | --- |
| Model | `SimpleStories/SimpleStories-V2-5M`, 5,354,496 parameters |
| Transformer layers | 6, executed through reused hardware |
| Hidden / feed-forward dimensions | 256 / 682 |
| Query / K/V heads | 4 / 2; 64 coordinates per head |
| Vocabulary | 4,019 IDs; fixed lowercase WordPiece tokenizer |
| Context target | 2,048 input positions; a 2,049-slot tape accommodates the final generated token |
| Numerical format | Project block-floating-point v5: W10/A16/KV16 |
| Decoding | Deterministic greedy argmax, not stochastic sampling |

Weights have signed 10-bit mantissas; activations and cached K/V values use
16-bit mantissas with the prescribed shared exponents and scaling metadata.
Intermediate accumulators are wider. Round-to-nearest-even, exponent selection,
range checks, lookup tables and tie handling belong to the numerical contract.
Changing arithmetic order or normalization is not assumed harmless merely
because the underlying real-valued transformer equation is unchanged.

The verification target is the project's pinned integer reference, not equality
with every output of the original floating-point model. The packaged
[reference model](reference/reference/model.py), quantization
code and asset manifests define the reproducible model conversion.

## System organization and clock boundaries

The public path is UART receiver/bridge → three-operation adapter → token
shell → fixed six-layer computation and tied output head → token reply.
The Mac performs tokenization and display, not model inference.

The [runtime overview diagram](diagrams/inference-machine.svg) shows these
functional boundaries without clock-domain or transport detail. The
[memory-integrity comparison](diagrams/memory-integrity.svg) distinguishes
fixed-weight verification from the additional K/V checks in the protected
configuration. The two DDR regions in the overview represent address
regions in one external memory, not separate devices.

The [physical top](hardware/project/top.sv) connects this path
to a flash boot loader, private model/KV memory system, thin DDR transport,
and GOWIN DDR3 controller. Application semantics and memory-access policy
remain in the 25 MHz core domain. The 100 MHz DDR application domain handles
ordered transport and physical-controller handshakes, not model scheduling.

| Clock | Role |
| --- | --- |
| Board 50 MHz | Reference clock and board-reset logic |
| Core 25 MHz | UART, inference controllers, arithmetic, runtime page verification and memory policy |
| DDR application 100 MHz | Thin command/return transport and controller interface |
| Memory PLL 400 MHz | Vendor DDR PHY clock source |
| Trusted/boot 12.5 MHz | Fixed flash source, boot-image SHA-256 readback and associated reset logic |

The clock tree also contains the PLL's 50 MHz output. Signal names
such as `trusted_clk_25mhz_o` are not authoritative frequency specifications:
the selected divider on that path is /4, giving 12.5 MHz. Likewise, some
reused modules have an `app_clk_i` port wired to the core clock. Inspect the
actual top-level connections and [constraints](hardware/project/constraints/product.sdc).
In particular, the boot/runtime DDR adapters and private arbiter use the core
clock despite that port name; the boot-image readback hash uses the trusted clock.

The [thin transport](hardware/project/thin_transport.sv) uses
Gray-pointer asynchronous FIFOs, a 32-command queue, a 64-entry return FIFO,
and a 32-outstanding-read reservation limit. Write command and data acceptance
are coordinated. Public `CLEAR` does not reset the transport: accepted work
must retain ownership and drain instead of being mistaken for a later request.
Reset asserts across the affected domains and releases through local
synchronizers. These structures do not substitute for physical CDC/timing
qualification.

## Public protocol and token controller

The [UART wrapper](hardware/project/uart_core.sv) selects
217 core clocks per bit, approximately 115,207 baud. Its fixed five-byte
frames carry command/reply information and CRC-8. CRC checks framing integrity,
not adversarial authenticity. There is no public tensor, address, layer/job,
arithmetic-mode, weight-loading or diagnostic-result command.

`APPEND` stores a valid token and advances the tape. `STEP` evaluates positions
not yet covered by the committed prefix, runs final normalization and the
tied vocabulary head, stores the winning token, and returns its ID. It does
not run the vocabulary head after every prompt position. Later `STEP`s reuse
the committed K/V prefix rather than reevaluating the whole prior prompt.

The [token shell](hardware/project/fpga/token_only_model0_ddr_board1/context2048_token_machine2/rtl/board1_context2048_token_shell.sv)
tracks tape length, replay position, committed prefix and held-output state.
`CLEAR` invalidates logical tape/cache state and cancels or drains work according
to ownership. It is not a bulk RAM zeroization operation and does not reopen
the boot loader or clear a terminal integrity fault. A physical reset is a
different event. All three supplied images have reached
the full 2,048-input window and final output slot in board tests; see
[the results](KV-PROTECTION.md#measured-performance).
These are finite functional tests, not complete timing qualification.

## Arithmetic microarchitecture

The six transformer layers share a fixed semantic sequencer and datapath.
They are not six independently programmable engines. The stage schedule
selects normalization, Q/K/V projections, rotary position operations, K/V
staging, causal attention, output projection, residuals and the gated
feed-forward computation. Layer, job and group descriptors are generated
internally; their presence on module ports is not a host programming interface.

### Weight projections and tied head

The live implementation is the clustered engine in
[cluster-adapter.sv](hardware/project/cluster-adapter.sv) and
[cluster-engine.sv](hardware/project/cluster-engine.sv).
`board1_fixed_group_projection_scale_job` instantiates
`board1_shared_projection_scale_group_adapter`, which instantiates
`board1_clustered_projection_scale2`.

It processes groups of up to 64 output rows. Four
[16-lane tiles](hardware/project/cluster-tile.sv) combine a scalar 16-bit
activation with a 640-bit weight beat (64 × 10 bits). Each lane uses an exact
[W10 × A16 multiplier](hardware/project/cluster-mul.sv), a product register
and a signed 35-bit accumulator. After the last weight beat, rows are read
one per cycle. Two fixed 27 × 18 multipliers separately scale the low 25 and
high 10 bits of the dot product by its 16-bit row multiplier; their results
are recombined into a signed 50-bit value. A four-stage pipeline stalls
globally on output backpressure. There is no arithmetic-mode input.

The tied vocabulary head reuses this engine (job 7: 63 groups, 51 valid rows
in the last group). Source-level multipliers are not the same as the vendor's
post-mapping DSP-block count.

The source inventory also retains five compiled but uninstantiated files:
`board1_asymmetric_private_issue_guard`, `board1_asymmetric_unified_dsp64`,
`board1_fixed_vector_rne_shift_iterative`, `board1_shared_projection_scale_engine`
and `board1_unified_projection_head_mul_exact`. They are not the active
datapath. They remain to preserve the tested build's exact 90-input identity.
Some source comments predate this engine or the second attention lane; the
live instantiations and this guide describe the released implementation.
Likewise, `*_GW5_DSP` explicit-primitive branches are not selected by the
released defines; their comments about tied-off features are not evidence
about the unselected branch's physical use.

### Attention and private intermediate storage

The actual attention RTL contains separate fixed-role score and weighted-value
multiplier instances, `u_score_lane` and `u_lane`. Both are fixed to their
dynamic 16 × 16 multiplication role. Coordinates are traversed sequentially;
this is not a 64-wide attention dot-product engine. Query reads are pipelined,
value alignment handles eight coordinates at a time, and an existing
value-exponent scan is shared by query heads that share a K/V head.

`Q × Kᵀ` consumes internally computed queries and privately fetched keys.
Scores enter private workspace RAM, exponentiation/normalization and softmax.
The resulting fixed-point probabilities feed `A × V`; its output enters
private vector RAM and then the fixed output projection. No host command
injects `Q` or `A` or exports either product. Private RAM between these stages
is buffering, not a software-addressable tensor interface.

### Other runtime arithmetic

Attention is not the only multiplication with runtime operands. The
[elementwise lane](hardware/project/fpga/token_only_model0_ddr_board1/fixed_elementwise_product_compact1/rtl/board1_fixed_elementwise_product_compact_lane.sv)
multiplies the internally computed feed-forward gate and up-projection values.
The same multiplier also applies the fixed rotary-position tables in other
scheduled phases.
The [RMSNorm service](hardware/project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_vector_rmsnorm_service.sv)
uses a shared, mode-selected multiplier: it squares each runtime vector
element, then in other phases multiplies normalized values by fixed ROM
weights and applies fixed row scales. The service has two live instances:
one in the semantic datapath and one in the token shell. Counting the two
attention lanes, there are five multiplier instances with a scheduled role
in which both inputs are runtime data, rather than one being a fixed model
coefficient. They are not all dedicated exclusively to that role.

These are private fixed-role operations, not independently callable arithmetic
services. The two operands of each RMSNorm square are tied to the same value.
The [capacity analysis](TRAINING-CAPACITY.md) explicitly distinguishes this
inventory from an attacker having useful general multiplication access.

The [semantic datapath](hardware/project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv)
owns query, key, value, hidden-state and intermediate vector/scratch RAMs.
The [attention engine](hardware/project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_attention.sv)
owns its query, score/probability and output workspaces. Memory write ports
are deliberately organized for native block-RAM inference. Payload RAMs need
not be physically reset: validity, overwrite-before-use and outstanding-work
ownership are substantive correctness obligations, not assumptions of zero
initial contents.

## Model storage, authentication and K/V memory

The fixed model payload is read from flash during boot into DDR. Runtime
model reads go through the [verified page service](hardware/project/service.sv).
The selected product instantiates four 4 KiB page banks, not the eight-bank
default visible in some reusable module declarations. Each bank fills its
actual on-chip RAM, seals and hashes that copy, compares against a fixed
page-digest ROM, and only then serves arithmetic reads from the verified copy.
Refill and pending responses are explicitly arbitrated. Raw DDR cannot supply
a new expected digest. Fixed projection scale/exponent metadata is also
held in a compiled on-chip ROM, with 55,872 useful payload bytes.

This avoids checking DDR once and then consuming unchecked mutable copies.
It does not establish cryptographic correctness or physical tamper resistance
by itself. SHA-256 is used for fixed-content verification, not encryption;
there is no update-signing secret or manufacturer weight-update command.

The runtime arbiter separates the following 256-bit-word address regions:

| Region | Half-open word range | Use |
| --- | --- | --- |
| Model image | `[0, 227062)` | 7,265,984 bytes; runtime model client is read-only |
| Alignment gap | `[227062, 227072)` | Not a legal runtime model/KV request |
| K/V cache | `[227072, 448256)` | 7,077,888 bytes; fixed typed inference reads/writes |

Each persisted layer/position/KV-head row contains four key words, four value
words and an exponent/padding word: 6 layers × 2,048 positions × 2 K/V heads
× 9 words. The typed controller stages the current row, persists it, and
commits prefix validity; pending and committed rows have different paths.
This design selects key-only or value-only reads according to the fixed
attention phase. Each committed-row request transfers five words (four data
words plus exponent metadata), rather than fetching both halves. The selector
is generated by the inference schedule and is not exposed to software.

**K/V payloads are not cryptographically authenticated.** Model-page hashing
must not be described as authentication of all DDR contents. Software lacks
a raw cache-access command, but a physical memory/bus attacker is a separate
threat. Establishing a practical GEMM-laundering throughput bound remains
additional work.

## Prompt processing and time to first token

The baseline and protected builds use three exact-arithmetic optimizations: a
three-clock block-floating normalizer, a private RMSNorm divider that skips
36 leading-zero iterations, and an attention divider that skips 18.
The skipped iterations follow from the actual callers' numerator bounds;
the rounding rule and integer results are unchanged. These changes do not
add public controls or bypass weight/K/V checks. Source-bound
arithmetic checks and model comparisons are summarized in
[the qualification record](evidence/leaf-speed/qualification.json).
The equivalence and caller-bound proofs are not bundled; the record contains
their receipt hashes. Public model replays exercise the supplied RTL but do
not prove these bounds for every possible input.

`APPEND` records tokens; it does not evaluate the transformer in advance.
On the first `STEP`, the controller processes each prompt position through
all six layers before moving to the next position. It streams the relevant
weights again for subsequent positions, and attention visits increasingly
long causal prefixes. The system therefore does not have a layer-major,
batched prompt-evaluation path. With the present traversal, projection work
grows roughly linearly with prompt length while the total causal attention
visits grow quadratically.

| Tested prompt | First STEP |
| --- | ---: |
| 128 tokens | 12.36 s |
| 512 tokens | 106.07 s |
| 2,048 tokens | 1,330.35 s |

These physical measurements include prompt evaluation, but exclude serial
connection setup and prompt upload. The design combines private weight
prefetch scheduling with selective K/V reads. The 512-token case generated
four outputs, averaging 2.68 cached tokens/s after the first. The baseline
performs four SHA-256 rounds per weight-checker cycle; the protected version
performs two. Both retain all 64 rounds and pack eight attention-value
coordinates into each 128-bit row. Neither choice removes checks or changes
numerical results. Both variants permit eight outstanding private projection
reads. The baseline prepares the next 512-bit hash block while the compressor
works on its captured current block, and uses the DSP's internal accumulation
registers for the same exact projection arithmetic. These choices expose no
additional commands, addresses or arithmetic operands to the host.

Further first-token improvements are plausible, but not implemented results:

- **Chunked prompt evaluation:** retain several positions' activations and
  accumulators, apply each verified weight group to those positions, and
  preserve causal attention within the chunk. This reduces repeated weight
  fetch/verification work but changes the controller's ordering, storage and
  per-layer commit invariants. It is not a small host-app change.
- **More attention parallelism and reuse:** wider private dot-product/value
  engines and shared K/V row reuse can reduce repeated arithmetic and memory
  traversal. Added arithmetic only helps when the cache/transport feeds it;
  routing, timing and exact numerical equivalence still need testing.

Neither requires a fourth public command or host access to arithmetic operands.
Both require renewed verification of private-state ownership, numerical output
and CLEAR behavior. There is no validated first-token latency forecast for
either redesign. Starting work earlier during prompt submission could hide
some latency, but would not by itself reduce total prompt-evaluation work.

## Physical implementation and verification boundaries

The target is the non-Pro Tang Mega 138K, GOWIN
`GW5AST-LV138PG484AC1/I0`. Custom hardware is SystemVerilog/Verilog; Python
provides reference arithmetic, test drivers and host tools; Tcl and constraint
files drive vendor synthesis, placement and routing. The DDR controller/PLL
IP and FPGA silicon are vendor components, not custom AI-authored hardware.

Both configurations routed and produced the reported exact-reference FPGA
outputs. The baseline global report retains **145 setup/recovery and ten hold/removal
violated endpoints**. Its inference-clock setup/hold slacks are **+0.018/+0.144 ns**
against a 25 MHz target: the reported setup margin is very small.
A complete census of the reported negative endpoints places
both ends of every negative path inside vendor DDR. This census was made from
private vendor reports; the release includes the summary and report hashes,
not the complete reports. That does not establish
that these crossings may safely be ignored or that external-I/O timing is
qualified. Successful board tests do not waive those limitations.
The current protected route has 152 setup/recovery and ten hold/removal
endpoints. Its complete reported-endpoint census also places negative paths
within vendor DDR, including seven DLL hold violations of −0.010 to −0.075 ns.
The inference setup/hold margins are +0.228/+0.116 ns, not complete product signoff.
See [baseline native results](evidence/baseline-current/native.json),
[current protected/encrypted results](evidence/speed-2026-10-02/native.json), and
[the protected timing limitations](KV-PROTECTION.md#evidence-and-limits).

The selected baseline uses 58,233/69,120 CLS, 196/340 BSRAM, and
74.5/298 DSP, as reported after mapping. Resource fit is not timing signoff.
The resource table counts 73 `MULTALU27X18` and three `MULT12X12` primitives.
Neither that count nor a scoped RTL proof substitutes for physical timing
and functional validation.

Formal work covers components of the actual command/controller/cache path,
as detailed in [FORMAL-STATUS.md](FORMAL-STATUS.md). Whole-machine refinement,
full numerical correctness, complete external-memory epoch isolation, mapped
implementation equivalence, correctness for every permitted prompt and invasive
tamper resistance remain distinct open obligations. No proof of all of them
is implied by the architecture described here.

## Reproducibility identities

- Model revision: `c4b3a4bb81297f5316697098e1d4b65c1249daf8`.
- Tokenizer SHA-256: `01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51`.
- Model payload SHA-256: `cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`.
- Selected baseline configuration SHA-256: `6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09`.
- Selected protected configuration SHA-256: `72d5a54e06ed2017e653122f3daecf073f239a917b79f24d1e7b886d68a21a2f`.
- Selected encrypted configuration SHA-256: `865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc`.

See the packaged [input manifest](MANIFEST.json) and
[reproduction instructions](REPRODUCE.md). File hashes identify
inputs and outputs; they are not remote attestation of the FPGA or permission
to redistribute vendor files. Each selected image has its own `BUILD.json`
and hardware-input inventory. See [the evidence guide](evidence/README.md)
and [programming guide](PROGRAMMING.md); no board action is performed by this document.
