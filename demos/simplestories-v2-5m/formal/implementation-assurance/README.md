# Implementation assurance for the current SimpleStories designs

The current digital RTL proves that, once runtime LOCK has been observed,
commands issued at the vendor DDR application interface cannot write the model
region until the common hard reset. This includes boot writes previously queued
in the asynchronous transport. Permitted runtime writes stay in the design's
K/V region. The proof joins the actual boot/source path, reset logic and full-size
transport; it does not establish vendor DDR persistence or physical behavior.

These checks use Yosys, bounded model checking, unbounded induction, component
reachability and deliberate semantic corruptions. Read-only monitors never
drive production logic. [SOURCES.json](SOURCES.json) pins all four current
images and native inventories. Every distributed input and selected image is
checked; four omitted vendor inputs per image retain their hashes as provenance.
This association is not RTL-to-bitstream equivalence.

## Checked implementation boundaries

| Boundary | Result | Verification boundary |
| --- | --- | --- |
| Boot/runtime handoff | 21 assertions pass Z3 and cvc5 for all four designs | Runtime ownership cannot revert; model writes and invalid requests cannot issue through this boundary. |
| Actual boot controller, enclosing wrappers and complete memory source path | 113 overlapping assertions pass both solvers for each distinct source path; the seeded path shares the baseline sources | All 227,062 native words, the FIFO2 and adapters remain. Only four scalar authenticator outputs are unrestricted. SHA arithmetic is not assumed proved. The enclosing boot boundary also has its separate 66-assertion, two-solver result. |
| Actual clock/reset correspondence | 11 assertions pass both solvers, joined to all four native top levels | Source and transport histories share the same reset epoch. That epoch cannot restart after runtime without the actual common hard reset. Raw reset outputs and independent clock levels remain arbitrary. Vendor reset generation is outside the proof. |
| Fixed QSPI reader | 24 assertions pass both solvers | The command is READ03 at the fixed model address and length. Z3 reaches command/header and first-byte goals; cvc5 checks the complete 163-state witness. That witness check is separate from an independent search. |
| Actual asynchronous command and return FIFOs | 28 assertions per channel pass Z3 in all six distinct native configurations; four also pass cvc5 induction | Literal 276-bit × 32-entry commands and 257-bit × 64-entry returns, with native module/lookahead/reset bindings. No source protocol assumption, resized queue or internal cut. Both encrypted secondary inductions remain unresolved. |
| Source-to-vendor command write epoch | 105 transport assertions pass Z3 base and induction for all three distinct transports; cvc5 base checks pass | All 52 reused FIFO invariants and both source guarantees are independently discharged. Exact top connections and reset correspondence close the substitution without circular dependencies or unproved client promises. The seeded transport is byte-identical to the baseline. Secondary induction remains unresolved. |
| Actual greedy UART/core/shell | 134 assertions pass Z3 in each greedy composition; cvc5 base checks pass | Real queues, gates, tape and 17 memories remain. The 37 private semantic-layer outputs remain unrestricted. Secondary induction is incomplete. Seeded sampling has its separate result in [FORMAL-STATUS.md](../../FORMAL-STATUS.md). |

Counts overlap and must not be added. Base plus induction establishes safety
for arbitrarily long executions of the stated two-state digital model. Safety
permits arbitrary independent clock schedules, stalls and input values within
the declared component boundaries. No frequency ratio or fairness is assumed.

The transport uses two source guarantees: after an emitted source READ, later
writes target K/V; runtime LOCK requires a prior source READ and reply. The
complete source path proves these without a transport guarantee. Independently
proved FIFO ordering/payload invariants then establish that earlier model writes
cannot remain pending after that read reply. The real top-level wiring audit
checks 63 signal, clock and reset equalities per image. Its blackboxed child
headers establish wiring only; the separate behavioral proofs supply the named
component guarantees.

## Reachability, controls and remaining limits

All four transport component traffic goals are reached in Z3, including a K/V
write after LOCK. The encrypted transport uses a separate directed search that
emits a boot read, waits for its reply, then emits K/V writes. These are legal
traces of the contracted transport model, not complete fixed-model boot traces
or board-frequency measurements. The original timed-out searches remain in the
records. Full boot/model behavior also has its separate functional qualification.

Deliberately wrong operation, address, payload, boot ordering and fault-gating
implementations produce real assertion counterexamples. Redirecting physical
writes into the model region after LOCK is also detected. Seven refreshed-
metadata tampering controls check the final auditor, including disabled targets,
new assumptions, missing premises, wrong image identity and changed native logic.

The [evidence index](../../evidence/implementation-assurance/INDEX.json) selects
59 positive and mutation runs. Original aggregate flags, raw queries, replies,
traces, timeouts and source audits are preserved. cvc5's larger inductions and
some coverage searches remain incomplete. Two encrypted coverage records end
with backend/response-handling errors; no secondary conclusion is credited to
those records. Completed Z3 results establish the stated transport theorem.

The boot controller can retain a sticky fault while its internal state or lock
changes under adversarial response/digest flags. The enclosing source-path proof
uses the actual fault gates and completed readback history; it does not claim
the stronger, false internal state/lock property.

No result here proves physical metastability or Gray-bus skew, vendor DDR
ordering/persistence, SHA arithmetic or collision resistance, encryption
security, full authenticated-private-memory composition, physical erasure,
eventual completion under indefinite stalls, whole-machine numerical refinement
or RTL-to-bitstream equivalence. FPGA images, numerical model, host implementation
and benchmark records are unchanged.

## Check the recorded package

From the repository root, with Python 3.10 or later:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/check_implementation_assurance.py --package .
```

This checks all compressed/raw identities, current native sources and images,
reversible instrumentation, original outcomes and recorded compiler/query-audit
bindings. It executes neither Yosys nor a solver and establishes no new theorem.
About 2.24 GB of logical raw evidence is temporarily extracted from about 172 MB
of compressed, deduplicated objects. To keep it, choose a new output directory:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/check_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence
```

## Run fresh checks

Each run's `INPUTS.json` records the exact original binaries and versions. Current
campaigns used Yosys `0.68+post` at commit
`c12172fbae8af5e20f6fb52e3d4e92d56ed587b6`, Z3 `4.14.1` and cvc5 `1.3.1`.

With Yosys/SMTBMC and Z3 installed, compile the frozen native inputs and run a
real solver into new directories:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/replay_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence --run transport-epoch-baseline-r3-exact-kv-prefix --phase bmc --out /tmp/simplestories-transport-base
python3 -I -S -B demos/simplestories-v2-5m/tools/replay_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence --run transport-epoch-baseline-r3-exact-kv-prefix --phase induction --out /tmp/simplestories-transport-induction
```

Both phases are needed for the unbounded result. Use `--solver cvc5` for an
independent phase. Selected mutation runs use `--phase bmc` and succeed only
when a real assertion counterexample is found. Fresh results preserve their own
tool identities and do not overwrite the original evidence.

The extracted full auditor can recheck all source, FIFO, reset and top-level
premises, re-elaborate the transport and regenerate its exact recorded queries:

```sh
python3 -I -S -B /tmp/simplestories-rtl-evidence/audit_transport_epoch.py --package . --out /tmp/simplestories-epoch-audit
```

Exact reproduction requires the recorded compiler/query binaries. Recorded
solver replies reproduce query generation only; they establish no fresh proof.
Use phase replay above for fresh solver results with local binaries.
