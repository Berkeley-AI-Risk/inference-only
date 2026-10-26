# Implementation assurance for the current SimpleStories designs

These checks strengthen the inference-only argument by proving properties of
the released RTL: which requests can issue, where writes can go, how ownership
persists, and whether the real transport preserves admitted fields. They use
Yosys, bounded model checking, induction, reachability witnesses and deliberate
semantic corruptions. The monitors observe the implementation; their state does
not drive production logic. No Lean specification is credited as an
implementation proof.

[SOURCES.json](SOURCES.json) pins the four current images, their native source
inventories and full address dimensions. Every distributed native input and
selected image is checked. Four omitted vendor inputs per image retain their
digests as provenance. This association is not source-to-bitstream equivalence.

## Checked implementation boundaries

| Boundary | Result | Verification boundary |
| --- | --- | --- |
| Boot/runtime handoff | 21 assertions pass Z3 and cvc5 for all four designs | Arbitrary component inputs; runtime ownership cannot revert, runtime model writes cannot issue, and faults close admission. |
| Actual runtime parent, adapter and handoff | 30 overlapping assertions pass both solvers for all four designs | The entire boot module's 14 outputs, totalling 330 bits, remain unrestricted. The actual runtime adapter and parent output gates are retained. |
| Fixed-length boot controller | 41 assertions pass both solvers | All 227,062 native words and 19-bit addressing remain. Observational counters establish the completed load/readback sequence before LOCK; model writes cannot recur after the boot read phase. Digest success and response inputs remain arbitrary. Only early boot-write reachability is formally searched. |
| Fixed QSPI reader | 24 assertions pass both solvers | The actual command is READ03 at the fixed model address and length. Z3 reaches the command/header and first-byte goals; cvc5 verifies a complete 163-state witness with every transition and safety property. This second result is witness checking, not an independent search. |
| Actual asynchronous command and return FIFOs | 28 assertions per channel pass Z3 in all six distinct native channel configurations; four also pass cvc5 induction | Literal 276-bit × 32-entry commands and 257-bit × 64-entry returns; exact module, lookahead and reset-release bindings. No input protocol assumptions, resized queues or internal cuts. Both encrypted cvc5 inductions remain unresolved. All four traffic goals are reached per channel, with separate cvc5 witnesses for the encrypted channels. |
| Actual transport with both FIFOs | 56 parent/range/field assertions pass Z3 in each of three native transports; cvc5 base checks pass | 52 internal FIFO invariants are reused as assumptions only after independent proof for the exact native module, dimensions and reset context. The new obligations remain assertions. The seeded transport is byte-identical to the baseline. Secondary induction and traffic search remain unresolved. |
| Actual greedy UART/core/shell | 134 assertions pass Z3 in each of the three greedy compositions; cvc5 base checks pass | Real queues, gates, tape and 17 memories remain. The 37 private semantic-layer output cuts remain unrestricted. Secondary induction is incomplete. Seeded sampling has its separate current controller result in [FORMAL-STATUS.md](../../FORMAL-STATUS.md). |

These counts overlap and must not be added. A complete base plus induction result
establishes its safety properties for arbitrarily long executions of the stated
two-state digital model. Reachability shows that named traffic can occur;
semantic mutants show that the properties detect specific wrong behaviors.
Neither supplies numerical model correctness or a cryptographic theorem.

The [evidence index](../../evidence/implementation-assurance/INDEX.json) selects
43 positive and mutation runs. It preserves the original partial campaign flags,
timeouts, solver replies, traces and source-audit records. A secondary timeout is
not counted as a theorem. The two-solver fixed-model checks, controller checks,
FIFO checks and transport composition have separate scopes.

## Remaining composition and physical limits

The native top-level wiring audit checks 63 signal, clock and reset equalities
per design. It establishes structural connections using blackboxed child
headers, not their behavior. The full temporal argument from authenticated boot
through runtime ownership to queued physical DDR commands remains open. In
particular, a handoff theorem before a queue does not prove that every earlier
boot write has drained from the physical interface when runtime starts.

The boot controller also has an isolated fault-state corner: an unexpected
response while its held final readback word is consumed can overwrite its FAIL
state transition while leaving the sticky fault asserted. With independently
arbitrary digest flags it can later assert both lock and fault. The actual
fault gate still suppresses requests. A full-length directed simulation through
the native enclosing FIFO/adapter instead reaches FAIL with lock deasserted,
because the adapter records the response protocol fault. This is a checked
finite execution, not a universal proof of the enclosing boot composition. The
passing controller proof claims the actual sticky-fault output gating and boot
sequence, rather than the false stronger state/lock property.

No result here proves physical metastability or Gray-bus skew, vendor DDR
behavior, SHA arithmetic or collision resistance, encryption security,
authenticated private-memory composition, physical erasure, eventual completion
under indefinite stalls, whole-machine numerical refinement, or
RTL-to-bitstream equivalence. The hardware images and numerical benchmark
records are unchanged.

## Check the recorded package

From the repository root, with Python 3.10 or later:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/check_implementation_assurance.py --package .
```

This checks all compressed and raw byte identities, current native sources and
images, reversible instrumentation, original solver outcomes and the recorded
compiler/query-audit bindings. It reruns the recorded-only fixed-model and
controller source audits. It does not execute Yosys, a solver, vendor tools or
the FPGA. About 1.70 GB of raw evidence is extracted temporarily from roughly
130 MB of compressed, deduplicated objects. The temporary files are removed.

To keep the extracted proof inputs for inspection or fresh checking, choose a
new output directory:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/check_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence
```

## Run fresh implementation checks

The original campaigns identify their exact tool binaries and versions in each
run's `INPUTS.json`. The current boot and transport runs used Yosys
`0.68+post` at commit `c12172fbae8af5e20f6fb52e3d4e92d56ed587b6`, Z3
`4.14.1` and cvc5 `1.3.1`. Their version strings and binary hashes remain in
the raw evidence.

With Yosys/SMTBMC and Z3 installed, these commands compile the frozen native
boot inputs and execute a real solver into new directories:

```sh
python3 -I -S -B demos/simplestories-v2-5m/tools/replay_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence --run boot-order-r5-held-last-support --phase bmc --out /tmp/simplestories-boot-base
python3 -I -S -B demos/simplestories-v2-5m/tools/replay_implementation_assurance.py --package . --work /tmp/simplestories-rtl-evidence --run boot-order-r5-held-last-support --phase induction --out /tmp/simplestories-boot-induction
```

Both phases are needed for the unbounded result. Use `--solver cvc5` to check a
phase independently. `--run` accepts a selected run name from the evidence
index; mutation runs use `--phase bmc` and succeed only when a real assertion
counterexample is found. Fresh results preserve current tool identities,
compiler output, queries, replies and logs, without replacing original records.

The extracted full source auditors can also reproduce compilation and exact
query generation:

```sh
python3 -I -S -B /tmp/simplestories-rtl-evidence/audit_fifo.py --package . --include-protected --out /tmp/simplestories-fifo-audit
python3 -I -S -B /tmp/simplestories-rtl-evidence/audit_transport.py --package . --out /tmp/simplestories-transport-audit
python3 -I -S -B /tmp/simplestories-rtl-evidence/audit_boot_order.py --package . --out /tmp/simplestories-boot-audit
```

These exact-reproduction auditors require the recorded tool binaries. They
re-elaborate RTL and regenerate queries using recorded solver replies; those
replies establish no new theorem. For fresh proof results with local tool
binaries, use the phase replay command above.
