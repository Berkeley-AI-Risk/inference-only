# Seeded-sampling formal replay

This lane adds source-bound safety proofs for the existing seeded SimpleStories
image. It uses the supplied RTL, original exact greedy selector, full 4,019-row
sampler, real memories and fixed numerical ROMs. It does not inherit the old
three-command proofs merely because some components are reused.

The [recorded results](recorded/RESULTS.json) identify the reviewed models and
solver outcomes. The connected Z3 proof passes all **196 assertions**. Its
independent cvc5 replay proves the base and **194/196** conclusions; request CRC
38 and reply CRC 73 remain `unknown` after bounded supplements. They are proved
by Z3 and remain unresolved by cvc5. An `unknown` is neither a proof nor a
counterexample.

## Run from the public package

Use Python 3.9 or newer, Yosys, Z3, cvc5, Icarus Verilog (`iverilog`/`vvp`),
and the already installed Lean toolchain `leanprover/lean4:v4.33.1`. The scripts
do not install dependencies or download Lean. The recorded Yosys is
`0.68+post c12172fbae8af5e20f6fb52e3d4e92d56ed587b6`, Z3 is 4.14.1 and cvc5 is
1.3.1. Different tool versions can change model serialization or solver runtime.
Use your compatible Python executable in place of `python3.12` below.

From the repository root:

```sh
python3.12 -I -S -B formal/seeded-sampling/check_recorded.py
python3.12 -I -S -B formal/seeded-sampling/test_replay.py
python3.12 -I -S -B formal/seeded-sampling/replay.py \
  --run formal/seeded-sampling/runs/my-replay
```

This checks all four component proofs with both solvers, the connected primary
proof, Lean, source/observer/ROM audits, nine reset-reachable formal fault
controls, and five directed serial simulation controls. UART and shell cvc5
induction is checked one final conclusion at a time under the identical joint
prior invariant, avoiding the earlier joint-solver timeouts. The default run
does not attempt the connected cvc5 census; its fresh report says so explicitly.

`check_recorded.py` is the fast, standard-library-only package/receipt check;
it needs no proof tools and does not rerun or certify a theorem. `SOURCE.json`
lists exactly the distributable files. `--list-files` prints that list for a
manifest-only export. Local `runs/`, `connected/runs/` and Python bytecode caches
are generated artifacts and never enter that release inventory.

Add `--secondary` to attempt all 196 connected cvc5 conclusions and the recorded
bounded supplements:

```sh
python3.12 -I -S -B formal/seeded-sampling/replay.py \
  --run formal/seeded-sampling/runs/my-full-replay --secondary
```

Every destination must be new. Logs, failed checks and timeouts remain in that
directory. A primary/source/audit failure stops the campaign. Connected cvc5
`unknown` results are preserved as unresolved conclusions; solver errors or a
counterexample cannot pass the final independent receipt check. The full census
can take substantially longer than the primary replay.

`RESULTS.json` inside a run reports the checks actually completed, source and
model hashes, exact secondary coverage and limitations. `FINISHED.json` binds
the campaign to that result. Recheck an existing run without invoking solvers:

```sh
python3.12 -I -S -B formal/seeded-sampling/check_replay.py \
  --run formal/seeded-sampling/runs/my-replay \
  --output formal/seeded-sampling/runs/my-replay/RECHECK.json
```

For an exact comparison to the recorded Yosys serialization, add
`--require-recorded-model` to either the replay or receipt-check command. A
different serialization is reported separately from the fresh source-bound
proof result. The public replay was checked locally with this flag; its five
models match the reviewed models exactly. The scripts access no serial/JTAG
device, program no hardware, access no network and publish nothing.

## Source and vendor boundary

`source_provider.py` verifies exactly **87 distributed input files**, the
packaged FS image, and the hash-pinned proof support/unchanged baseline monitor
files. Their canonical distributed inventory SHA-256 is
`2c34ed9ddc4e48a36f4a13911bcd410b71d37416a3614caccfe5447b31df6ebd`.
The complete historical 91-input inventory SHA-256 remains
`26a0885f9ffefaeea68b948295635fcfb37367254b549c48e75e0d7093e96831`.
The four separately licensed vendor-file digests in that inventory are
**provenance**, not four additional files verified by public replay. They are
not read, copied, elaborated or proved here. No vendor files or flattened
netlist are distributed. A full native 91-file byte audit requires a separately
acquired native build packet; it still would not turn these scoped proofs into
a vendor or mapped-implementation theorem.

The image SHA-256 is
`0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033`.
The assembly-receipt SHA-256 is
`0dd7a437353ddd8c77728b820f752764c924ca7768dca80939384e5614d82112`.
Checking an image file associates artifacts; it does not prove that a connected
board loaded that image or prove source-to-bitstream equivalence.

## Proof inventory

| Model | Assertions | Checked boundary |
| --- | ---: | --- |
| Selector lifecycle | 35 | Atomic seed/temperature configuration, zero-seed normalization, rejection preservation, settings/start priority, winner ownership, PRNG commit, stalls, CLEAR rewind and sticky faults. Both solvers prove the base and joint k=3 induction. |
| Selector RAM ownership | 57, including those 35 | All 4,019 logit rows accepted before healthy sampling reads; current per-slot logits/mass ownership and captured RAM payload before use. Three real memories, one arbitrary slot and read-only child row counter. Both solvers prove base and joint k=3 induction. |
| Actual UART/frontend | 63 | RX/TX at 217 clocks/bit, complete-frame authorization, independent admitted-byte CRC history, settings payload/reply ownership, timeout revocation and real operation wires. Backend readiness/model/settings replies remain arbitrary. Z3 joint induction and cvc5 base plus all conclusions pass. |
| Actual token shell | 94 | Original 48 control/tape assertions, 11 settings assertions and 35 selector assertions. Actual shell/arithmetic/selector and 20 memories retained. Private model/layer/head service ports remain arbitrary. Both solvers check the complete base/induction, with cvc5 conclusions split. |
| Connected UART/core/shell | 196 | Actual gates, queues, shell and sampler; exactly the baseline's external port boundary and 37 unrestricted semantic-layer outputs. Z3 base and joint k=2 induction pass. cvc5 base + 194 conclusions pass, with the two CRC limits above. |
| Abstract transactions | 15 Lean theorems | Four atomic commands, bounded tape, seed normalization, settings effects, CLEAR replay, random-state advancement and reply counts. Fixed greedy/sample/random-step functions remain abstract. |

These counts overlap; they must not be added as independent properties. The
57-assertion RAM proof is a separate component result and is not inserted into
the 196-assertion composition. The connected proof retains **88** original
assertion statements unchanged. SETTINGS creates legitimate additional parser
states and indices, so **47** extended UART statements replace the original
46. The other added families are 35 selector, 11 shell settings, seven core
settings and eight frontend settings assertions.

All production inputs remain arbitrary at the declared boundaries. Reset is
low at base states 0 and 1; induction leaves reset unrestricted. All preceding
joint assertions are proved together and used as the induction invariant;
splitting the final cvc5 conjunction does not remove any prior assertion,
transition, memory or input boundary. Original unqualified `FORMAL` blocks are
disabled, and production `SYNTHESIS` excludes simulation-only X checks. This is
two-state synchronous RTL reasoning.

## What the observations establish

The selector's deterministic PRNG advances only when its owned positive-mode
winner is accepted. Greedy generation consumes no PRNG state. A stalled result
remains owned and stable; CLEAR revokes current work, retains configuration and
rewinds to the stored seed; reset restores greedy defaults; terminal faults
remain closed. Public result masking is checked. The RAM proof observes an
arbitrary constant slot, so its result covers every slot without replacing a
production memory. RAM payload is not assumed zero or physically erased.

The UART monitor tracks **admitted bytes**, not every byte arriving on the wire.
It independently folds a bit-serial CRC and checks complete-frame settings,
all seed bytes, timeout and reply ownership. The connected proof carries this
through the actual empty/idle shell certificate and settings gates. SETTINGS
adds only bounded temperature and public seed fields; it does not add an
application weight/tensor-write command. These are scoped command/control
claims, not an end-to-end information-flow theorem.

The Lean definition in [SeededPublicSurface.lean](SeededPublicSurface.lean)
has atomic transaction boundaries. `FixedFunctions.greedy`, `.sample` and
`.nextRandom` remain fixed parameters throughout a run. It imports no RTL or
weights. Busy, stalls, draining, reset circuitry and terminal faults are handled
by the separate actual RTL proofs, rather than modeled as asynchronous Lean
transactions. There is no Lean-to-RTL refinement theorem.

Unchanged bank/SHA and local typed-K/V source bytes retain their separately
named [42-property bank](../page-bank/README.md) and 59-property local-K/V scopes
in [FORMAL-STATUS.md](../../FORMAL-STATUS.md). No old receipt is assumed as a
new connected theorem, and arbitrary SHA replies do not prove compression
correctness. This lane does not qualify a seeded KV-protected or encrypted
hardware variant.

## Audits and sensitivity

The audits reconstruct derivations from the public packet, reverse permitted
source observations/cuts, check the complete original baseline boundary, and
require fresh Yosys elaboration to reproduce each run's JSON/RTLIL/SMT exactly.
They check all 4,097 exponential and 3,328 normalization ROM words, actual memory
sizes, zero assumption cells and no observer feedback into production ports,
named nets, ordinary read controls or memory writes. The independent receipt
checker reconstructs canonical reset/induction and bounded-negative queries,
then verifies hashes, logs, actual primary artifacts and secondary coverage.

Seven configuration/lifecycle and two early-read faulty selector copies produce
reset-reachable bounded counterexamples; the unchanged design passes the same
bound. These retain the full vocabulary and memories. Five faulty UART copies
are detected by the actual 284-case directed serial suite: CRC bypass, seed
corruption, invalid-temperature truncation, busy overtaking and missing timeout
revocation. These UART controls are finite simulation, not formal proof.
Offline adversarial tests reject corrupted sources, removed monitors,
relabeled unknowns, unbacked connected summaries, vacuous bounded queries and
observer feedback.

The remaining limits are complete numerical CDF equivalence, whole-machine
refinement, mapped-image correspondence, routed timing closure, global memory
noninterference, cryptographic randomness/security and physical fault behavior.
Successful board/reference/browser trials have their own evidence and do not
close these formal gaps. The original baseline is likewise a partial scoped
verification, not a complete whole-device certification.
