# What the RTL proofs establish

The checked hardware models support a restricted token interface for the fixed
SimpleStories-V2-5M numerical model. The three greedy designs accept
`APPEND(token)`, `STEP` and `CLEAR`; the optional seeded design also accepts
bounded temperature/seed settings at an empty, idle tape. Qwen has separate
implementation and test evidence; no Qwen theorem is claimed here.

The transaction contract is straightforward: APPEND records an accepted input
token, STEP owns one generated result that is stored and returned consistently,
and CLEAR invalidates the logical tape and cancels the relevant ownership.
A tape accepts at most 2,048 input positions, with a 2,049th slot for the final
result. Logical clearing does not promise physical erasure of every memory cell.

Yosys and SMT solvers check assertions against actual RTL and its declared
verification boundaries. Independent histories record admitted requests,
accepted commands, live tape contents, outstanding work and returned tokens.
These monitors are checked against the implementation rather than used as
assumptions. A completed induction establishes its safety properties for
arbitrarily long executions of that synchronous digital model under its reset
conditions. Finite simulations and physical-board tests exercise particular
executions and remain distinct evidence.

The current results are scoped control and component proofs. They do not prove
that the entire FPGA implements the fixed model's numerical next-token function.

## Current implementation checks for inference-only enforcement

The [implementation-assurance package](formal/implementation-assurance/README.md)
proves that, after runtime LOCK, writes issued at the vendor DDR application
interface stay in the permitted runtime K/V region until the common hard reset.
This includes earlier boot writes queued in transport. The actual boot/source
path, reset correspondence, full-size FIFOs and top-level wiring are joined;
all 54 transport premises are independently discharged, with no circular
dependencies or unproved client protocol promises.

| Checked boundary | Current result | Main limit |
| --- | --- | --- |
| Complete boot/memory source path | 113 overlapping assertions pass Z3 and cvc5 for each distinct path; all 227,062 native words remain | Four scalar authenticator outputs are unrestricted; no SHA arithmetic theorem. |
| Native reset correspondence and wiring | 11 reset assertions pass both solvers; 63 top-level connections are checked per image | Digital reset/wiring only; vendor reset generation and physical CDC remain outside. |
| QSPI model reader | 24 assertions pass both solvers; fixed READ03 command and range | Vendor I/O and physical flash protection are outside the theorem. |
| Full-size command and return FIFOs | 28 assertions per channel pass Z3; four of six distinct configurations also pass cvc5 induction | Two encrypted secondary inductions remain unresolved. |
| Source-to-vendor command write epoch | 105 transport assertions pass Z3 for each distinct transport; cvc5 base checks pass | Secondary induction/coverage remains incomplete, including two retained coverage tool errors. Vendor persistence/read ordering is not proved. |
| Connected greedy UART/core/shell | 134 assertions pass Z3 per greedy design | 37 private semantic-layer outputs remain arbitrary; secondary induction is incomplete. Seeded control has its separate result below. |

The 59 selected positive and mutation runs retain their original outcomes,
queries, replies, semantic controls and source audits. Counts overlap and are not
additive. A portable recorded check uses no vendor/compiler/solver tools;
separate commands perform exact source/query reproduction or fresh solver work.
Hardware images, model, host and benchmark records are unchanged. This command-
trace result strengthens the inference-only argument without establishing
whole-machine numerical, cryptographic, physical DDR or RTL-to-bitstream claims.

## Current seeded RTL replay

The seeded-sampling image is
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`.
Its [current replay](formal/current-seeded-sampling/README.md) and named
[completion record](formal/current-seeded-sampling/CURRENT-REPLAY.json) identify
the exact checked models, queries, tools and outcomes. The completion uses
schema `current-seeded-rtl-formal-replay-completion-v2` and records the actual
fresh RTL-only campaign; registering it does not execute a solver again.

| Checked model | Recorded result | Boundary |
| --- | --- | --- |
| Selector lifecycle | **35 assertions**, complete primary and secondary checks | Real fixed-dimension sampler and greedy child; settings admission, seed/PRNG commitment, result ownership, stalls, CLEAR rewind and sticky faults. Not numerical CDF equivalence. |
| Selector buffer ownership | **57 assertions**, complete primary and secondary checks, including the selector's 35 | All three sampler memories retained; complete 4,019-row acceptance, selected-slot current logits/mass and captured-payload ownership. Read-only observers do not drive production. This component is separate from the connected model. |
| UART/frontend | **63 assertions**, complete primary and secondary checks | Real RX/TX at 217 clocks per bit, bridge and adapter; independent admitted-byte/CRC history. Downstream readiness, model and settings replies remain arbitrary. |
| Seeded token shell | **94 assertions**, complete primary and secondary checks | Original 48 controller/tape statements, 11 settings statements and 35 selector statements; actual shell/arithmetic/sampler and 20 memories. Private model/layer/head services remain arbitrary inputs. |
| Connected UART/core/seeded shell | **196 assertions** pass primary Z3 base and induction. Secondary cvc5 passes the base and **194 of 196 conclusions**. | Same whole external boundary and **37 unrestricted private semantic-layer output cuts**. Actual queues, gates, shell, sampler and 20 memories remain. Request CRC conclusion **38** and reply CRC conclusion **73** remain `unknown` for cvc5. |

The connected primary result covers all 196 assertions. Its two unresolved
secondary conclusions are not counterexamples and are not counted as proved by
that solver. Each secondary conclusion uses the same joint prior invariants.
These counts overlap and must not be added. The 57-assertion component is not
inserted into the connected theorem. The connected model has no RTL assumption
cells; reset initializes its base states and is not imposed during induction.

The replay also records seven reset-reachable selector mutants, two buffer
mutants, five serial mutants and 284 actual serial scenarios. These sensitivity
and scenario checks have their stated finite scope; they are not additional
whole-machine assertions.

### Sealed weight-page bank

The separate current seeded bank proof passes **42 assertions with both
solvers**. It retains the real **32,768-bit RAM**, checks fill-before-read,
sealed-copy admission after a completed matching digest comparison, owned
replies, hash-input correspondence, prefetch sequencing and sticky faults.
Ten directed scenarios and five faulty controls accompany that proof.

The bank's **258-bit SHA replies remain arbitrary**. Production SHA is identified
as source provenance but is not elaborated in the bank theorem. The result does
not prove SHA compression arithmetic, the parent service's digest selection,
private bank/SHA composition or cryptographic security. The bank count is
nonadditive with the controller counts above.

### Source binding and retained support

The current provider verifies **87 distributed native source files and the
selected seeded image**. The full 91-input inventory additionally records four
omitted vendor digests; those digests are provenance, not verified vendor bytes
or elaborated vendor logic. Source audits check reversal of instrumentation,
local elaboration, initialized ROM words, original ports/cuts and read-only
observer cones. The separate finite model campaign checked 30 cases, 108 heads
and 434,052 raw logit rows with the implemented SHA engine; it does not turn
those executions into a universal arithmetic theorem.

The source association retains seven unchanged modular scopes, separate
154-assertion cache-stage evidence and exp-ROM source evidence. The source-binding
action ran no solver and retains its false replay flag. Its recorded primary
cache-stage evidence does not establish full cache equivalence, unconditional
terminal-failure write drain or physical erasure. The named fresh
completion above records the actual controller and bank replay separately.

The replay audits its [98-member support-source inventory](reference/baseline-formal-354/REFERENCE-SOURCES.json), including the monitor support and boundary derivation inputs. Source regeneration checks 128 model/source members and their complete source/binding map byte for byte. These source checks run no solver and grant no additional proof scope.

## Greedy design scope

The baseline, K/V-protected and encrypted designs have their own exact
source/model/native/mapped and physical qualification records in
[GREEDY-QUALIFICATION.md](GREEDY-QUALIFICATION.md). A changed design does not
inherit an older controller, cache, bank or SHA proof merely because it uses
the same numerical model or public command names. Source associations state
which byte-identical components retain evidence and which changed boundaries
remain outside it. Physical timing and resource observations add no assertions.

The selected greedy-source records retain these scoped results:

| Design | Checked source scope | Boundary |
| --- | --- | --- |
| Baseline | 34 attention-controller assertions; 72 recorded query checks | Child arithmetic and memory replies remain unrestricted at the listed outputs. No numerical-attention or concrete-memory composition theorem. |
| K/V-protected | Joint cache proof with 357 assertions including support; separate 34-assertion attention scope | Private scheduling and SHA replies remain arbitrary. These overlapping scopes do not establish cryptographic integrity or whole-machine refinement. |
| K/V protection and encrypted memory | 34 attention assertions joined through six byte-identical isolated sources; 72 query checks | The bridge adds no assertions and supplies no encrypted-guard/SIV, numerical-attention or private-memory composition theorem. |

Counts are nonadditive. The [qualification guide](GREEDY-QUALIFICATION.md)
identifies the exact source associations and recorded solver/audit results.
These byte/query rechecks run no fresh solver and supply no physical attestation.

The encrypted design retains K/V integrity and replay checks, but encryption
and the supplied public demonstration keys do not imply a cryptographic theorem.

## Limits

The monitors prove command authorization, operand preservation, STEP/result
ownership, live-tape correspondence and logical cancellation at their stated
boundaries. Private numerical and memory services remain unrestricted at the
listed cuts. They do not establish eventual completion when readiness stalls
forever, the correctness of every generated token, physical RAM erasure,
SHA arithmetic or private-memory composition, whole-machine refinement,
source-to-mapped-image equivalence, complete vendor-DDR timing or physical
security. A successful model or board test does not attest another loaded FPGA.

The assessment assumes a frozen circuit and synchronous digital behavior.
[INFERENCE-ONLY.md](INFERENCE-ONLY.md) and
[TRAINING-CAPACITY.md](TRAINING-CAPACITY.md) state the separate architectural
and conditional capacity assumptions; these proofs supply no certified residual
training factor.
