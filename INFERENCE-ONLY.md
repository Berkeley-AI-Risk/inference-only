# In what sense is this design inference-only?

This assessment and its proof/capacity receipts concern the baseline and
K/V-protected configurations. The [encrypted-memory version](ENCRYPTED-MEMORY.md)
preserves the same public operations, but has separate circuitry and test
coverage; it has no whole-machine proof or certified training-capacity rating.

*The Feasibility of a Hardwired Pause of Frontier AI Training* introduces both
an idealized inference-only machine and a practical, operational criterion.
This repository provides a **working FPGA demonstration of the restricted
architecture**, assessed as if its FPGA configuration were permanently frozen
or the circuit were implemented in an ASIC.

The two configurations assessed here are: the **baseline without
K/V integrity checks**, and the **K/V-protected prototype**. The
model, accepted weights and public commands are the same. The distinction
below concerns physical access to attention-cache memory, not an additional
software interface. [KV-PROTECTION.md](KV-PROTECTION.md) gives the mechanism,
measurements and separate evidence for the protected image.

The essential distinction is between serving a permitted fixed model and
providing practically useful computation for training at generic, iteratively
updated weights. A small model and modest inference speed do not undermine
that architectural demonstration. Performance matters to deployment value and
to the denominator of a residual training factor; it is not itself the inference-only
restriction. Verification and physical tamper resistance are separate questions.

## The idealized machine and the implemented interface

The paper's idealized machine permits model selection and input, generation,
and erasure. Here the permitted set has one element, so model selection is
implicit. The hardware commands are `APPEND(token)`, `STEP`, and `CLEAR`.

The permitted model is the pinned **W10/A16/KV16 numerical approximation of
SimpleStories-V2-5M with deterministic greedy decoding**, not the original
floating-point model's stochastic distribution. Its architecture, accepted
weights, numerical rules, schedule and decoding policy are fixed. Finite
context and finite precision are explicit parts of the approximation.

There is no instruction loader, user-selected arithmetic program, or command
for tensors, intermediate-memory addresses, gradients or weight replacement.
The decoder/controller enforces these restrictions; replacing the Mac app
does not change them. Framing, acknowledgements and invalid-command rejection
are transport behavior around the three operations, not extra arithmetic
services. `CLEAR` logically erases the tape and invalidates cached state; it
does not zero every physical memory cell.

The actual development FPGA has a JTAG configuration path and volatile,
unencrypted configuration memory. Reprogramming it is outside the stated
frozen-design assessment. That assumption does **not** establish resistance
to other attacks on memory, clocks, signals or internal circuit connections.
Physical implementation on an FPGA is real; permanence is what the FPGA
does not provide. The separate backup-reader configuration replaces the
inference circuit and is not a fourth operation of that circuit.

## Fixed accepted weights, although their storage is writable

Weights are stored in flash and loaded into private external DDR. Their
accepted values are fixed by SHA-256 digests compiled into the circuit.
Startup checks verify the image. Runtime model pages are copied into on-chip
memory, sealed and verified before arithmetic uses those same copies. Every
refill is checked; later reads do not rely solely on the startup result.
The [architecture guide](ARCHITECTURE.md#model-storage-authentication-and-kv-memory)
describes this path and its separation from the mutable K/V cache.

This is an FPGA demonstration of the paper's **Authenticated-Weight
Inference-Only Chip (AWIC)** architecture (§4.3), not an MSIC whose weight bits
are hardwired into model-specific silicon. All three supplied variants use
hardware-authenticated external weights. Under the frozen-configuration
assumption, neither the inference function nor the accepted weight digests
can be changed through the public interface. In an ASIC, those fixed circuit
choices would instead be made at manufacture. Demonstrating this architecture
is distinct from certifying its residual training factor.

There is no secret signing key or manufacturer-update command. This is
checked external storage, not physically hardwired weight bits. Its argument
depends on the hash function, its implementation, and the containment logic.
The normal model path is read-only and the K/V controller is range-bounded.
Those protections do not prove that invasive tampering or fault injection
cannot bypass a gate. Hardware enforcement is not the same as indestructibility.

## Internal multiplication is not a general matrix-multiplication service

The paper distinguishes dynamic multiplication—both operands vary at
runtime—from user-accessible general multiplication. The latter requires an
effective way to supply desired operands and recover useful products.

The design follows the paper's proposed attention dataflow:

- **Attention scores (`Q × Kᵀ`):** `Q` is produced by internal model
  operations; `K` comes from the private cache. Scores feed the internal
  softmax operation, not a host-readable score matrix.
- **Weighted values (`A × V`):** `A` comes from that internal softmax; `V`
  comes from the cache. Products feed private storage, the fixed output
  projection and later model operations, not a matrix-result command.
- **Other dynamic arithmetic:** the feed-forward gate product and RMSNorm
  squares also use runtime values. Their operands/results are internal and
  their roles are fixed by the schedule. The same elementwise multiplier also
  applies fixed rotary tables, and each RMSNorm multiplier also applies fixed
  normalization weights and row scales. These shared units are included in the
  [arithmetic inventory](ARCHITECTURE.md#other-runtime-arithmetic), not omitted
  merely because they are elementwise rather than matrix-shaped operations.

Thus each attention product has an internally generated operand and
internally consumed result. No command injects arbitrary `Q` or `A`, or
exports these products. Prompts influence them indirectly through the model.
This closes the **direct software-accessible GEMM interface**; it is not a
proof that every indirect computational use or physical attack is impossible.

These are distinct access models. A software-only adversary can replace the
host app and send arbitrary UART traffic, but does not thereby gain physical
DDR-bus access or control of internal multiplier connections. Physical memory
tampering and faults that compromise internal enforcement require separate
analysis. Conversely, an implementation flaw could be software-triggered;
the absence of a general arithmetic command is not an exhaustive bug-freedom
proof. The [capacity analysis](TRAINING-CAPACITY.md#access-assumptions-software-versus-hardware)
states which access assumptions each estimate grants.

“Directly” here means no software-accessible injection/extraction point. It
does not require an uninterrupted wire without registers or private buffers.

### Memory addressing does not require software exposure

A fixed-model machine needs hardware that generates addresses, but software
need not choose them. The layout is fixed at design time. Internal controllers
calculate addresses from the layer, token position, attention head and other
inference state. A longer context changes counters; it does not require host
pointers or software-managed tensor layouts.

That is how this implementation works: the host supplies token commands,
not intermediate-tensor addresses. DDR is not mapped into the host's address
space. Buffering and address generation therefore do not themselves provide
access to general matrix operations.

### What physical access to DDR changes

In the **baseline**, “private” means controller-owned, not physically protected. K/V cache contents
are model-generated during ordinary operation, but they are not encrypted or
cryptographically authenticated against a physical bus/memory attacker.

Such an attacker could attempt to replace cached K/V and observe subsequently
written cache values. Later layers' K/V values are written to the same memory
and give a nonlinear, quantized observation of earlier attention results.
This does not supply an injection point for arbitrary `Q` or `A`, nor a
readout of an untransformed attention product. Whether useful products can be recovered
usefully through the output projection, residuals, normalization, feed-forward
operations and later projections is an open quantitative attack question.
Neither a working training attack nor its impossibility has been demonstrated.

The **K/V-protected variant** adds before-use verification against SHA-256
digests retained in private on-chip memory. It binds data to location and
current logical context, stages and verifies external reads, and releases
the sealed verified copy. Changing external K/V alone therefore does not
supply chosen cache operands under the guard's integrity and trusted-on-chip
assumptions. [Scoped source-bound proofs](formal/kv-integrity/README.md) check
private write/tag history, guard-to-cache data and identity, and separately
attention capture/use. SHA implementation correctness and whole-machine
composition remain unproved. Corruption, stale data and CLEAR handling have
simulation tests; normal inference has physical tests. Physical corruption rejection has not
been demonstrated on the board, and no complete guard/composition theorem is
claimed. The bytes are still unencrypted and physically observable. This
does not establish resistance to invasive changes or faults inside the chip.

### Physical interfaces and a fixed ASIC

The paper's criterion in §4.2 covers physical exposure as well as software
access: off-chip memory, inter-chip links, and test/debug ports can provide
places to inject operands or observe results. Routing an operand from an
earlier operation does not keep that operand under internal control if an
attacker can overwrite it in transit. Exposed intermediates may also provide
a readout channel, but useful GEMM still requires suitable inputs and
recoverable outputs. The DDR analysis above therefore remains necessary
even though no software command exposes that memory.

The paper's HNLPU example (§4.3) illustrates this distinction. It describes
attention intermediates carried between chips over CXL links, creating
injection and readout opportunities despite fixed internal projections.
The paper proposes protecting those links through a sealed package or
encrypted and authenticated traffic, followed by further audit. Our current
demo does not distribute attention across multiple FPGAs; this example is
relevant to scaling the approach, not evidence that our DDR is untamperable.

For an eventual fixed ASIC, scan, test and debug facilities must also be
examined. Paths that expose useful arithmetic operands/results, checked weight
copies or authentication state would need to be removed or appropriately
restricted in the deployed device. Freezing the inference architecture does
not automatically secure these paths, and the present FPGA proofs do not
certify the test/debug design of a future ASIC. Likewise, a scaled-up design
would need a protected boundary around any inter-chip intermediate traffic.

## Operational assessment and quantitative estimates

The paper's practical concern is **usable training capacity**, not simply
whether a multiplication circuit exists or a training API is absent. There
is no backward-pass or weight-update engine here. General tensor/memory
commands are absent, not disabled by a driver. Model acceptance depends on
the compiled digests and runtime page-verification path; arithmetic ownership
depends on the fixed controllers. A complete physical-security assessment of
those protections remains to be done.

The [training-capacity analysis](TRAINING-CAPACITY.md) provides reproducible
conditional estimates for five scenarios: matrix arithmetic through tokens;
full use of five dynamic multipliers; full use of all 76 mapped multipliers;
dynamic operations only when the model runs them; and replacing accepted
weights while keeping the same schedule. Their residual training factor proxies use
a [measured single-H100 SXM reference](H100-BENCHMARK.md).
That benchmark uses the original FP16 checkpoint, not the exact FPGA numerical
model. The analysis also compares with the paper's illustrative 0.01, 0.001 and 0.0001
factors and separates achieved GPU performance from idealized performance models.
Those scenarios do not establish usable general arithmetic access, a failure
of weight enforcement, or a certified execution-rate bound. The analysis
reports sensitivity and remaining rating assumptions;
it does not claim zero residual capacity or a certified nation-state-resistant
factor.

The [architecture-dependent analysis](ARCHITECTURE-DEPENDENT-CAPACITY.md)
separates the model's arithmetic mix, multiplier-cycle capacity and reference
GPU efficiency. It explains why the scheduled estimate is workload-specific,
and derives attention-work fractions for Llama 405B. Those fractions do not
establish that an attacker can use the arithmetic for training.

A complete practical assessment must specify the attacker, bound recoverable
training computation at useful precision, and establish a comparable inference
rating. Efficiency affects that ratio, but small scale is not a categorical
objection to being an inference-only demonstration.

## What has been established

### What the proofs constrain for a software adversary

The formal checks are stronger than tests of a few well-formed commands.
They cover arbitrary serial input sequences in a reset-initialized,
synchronous digital RTL model. The connected front-end/core/token-shell
proof establishes 134 assertions, including supporting invariants: request
authorization, APPEND operand preservation, STEP ownership of public token
replies, tape bounds and stored/published-token agreement. Changing host
software or constructing a different command sequence cannot violate those
proved properties in that model. These are safety results, not guarantees
of eventual completion.

That materially constrains software-induced misuse at the proved boundaries.
It is not yet a proof that the full backend always implements the fixed
model, that all private-memory/controller properties compose, or that the
mapped FPGA implements the proved RTL. Nor is it a bound on every possible
computation performed through legitimate prompts. The independent
weight-page-bank proof adds sealed-copy/digest-admission properties, not
a complete proof of SHA-256 or the parent verification path. The protected
variant adds proofs of K/V guard history, cache assembly through selected
parent gates, and a separate attention capture/use result. They constrain
when externally fetched data can be admitted and used; they do not establish
the whole protected machine's numerical behavior or resistance to physical
modification of the checking circuitry. See
[FORMAL-STATUS.md](FORMAL-STATUS.md) for the exact theorem and solver scopes.

### Physical and functional evidence

The supplied baseline and K/V-protected images each produced 391
reference-matching main-case tokens plus 72 CLEAR/replay outputs, through
the full 2,048-input window. Their 128-output continuations were each repeated.
The supplied encrypted image produced 522 main-case tokens plus surrounding
CLEAR/replay checks and also passed a full-window test.
Formal work covers the abstract specification and scoped properties of the
real command interface, tape/controller, local K/V controller, sealed
weight-page bank, and the protected K/V paths described above.
See [VALIDATION.md](VALIDATION.md) and
[FORMAL-STATUS.md](FORMAL-STATUS.md) for precise scopes.

These are evidence for an architectural and functional approximation, not
a completed whole-machine refinement theorem, full numerical proof,
mapped-circuit equivalence proof, or invasive-tamper certificate. The useful
conclusion is that **a restricted fixed-model inference circuit can actually
be built, run and partly machine-checked**. Further auditing determines how
strong its quantitative guarantees are.

The proofs also do not establish that physical modification would be evident
to an inspector. A capacity rating restricted to undetected modification
would require separate evidence about detection, not just the command interface.

The interface and internal-dataflow principles can be applied to larger
designs. This prototype's performance, capacity estimates and physical
security do not automatically carry over to HBM or multi-chip versions.
