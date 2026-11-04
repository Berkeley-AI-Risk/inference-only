# Native RMSNorm product specification

The checked claim is in `THEOREM.md`; `QUALIFICATION.json` records completion.
This file explains the construction. Exact formulas and dependencies are in
`project/native.smt2`, `product.smt2`, `history.smt2` and `PROOF-PLAN.json`.

Let N(s,s') be the compiled complete native transition relation, retaining
the 256×16 vector RAM, 682×58 normalizer RAM, coefficient ROM and arithmetic
helpers. The compiler's initial predicate initializes immutable ROMs; the proof
does not assume that resetless actual payload starts clean. ROM preservation
is checked separately. The configured vendor stateless multiply correspondence
is an explicit premise in `SOURCES.json`.

The product has actual state a and canonical reference state b. Actual
attempts, unused input fields, lock changes, faults and stalls are unrestricted.
The reference has reset controls and zero resetless payload at entry, held model
lock, no external fault, ordered input rows and always-ready output/done. Only
admitted descriptor fields and accepted mantissas are shared. Unused reference
input fields are zero; they do not track arbitrary actual pins. The history
monitor records accepted arguments rather than assuming their correctness.

After entry, with reset deasserted, the product transition is:

```
coupled(a,b) and coupled(a',b') and N(a,a') and
    (if tick(a) then N(b,b') else hold(b,b'))
```

`tick` removes neutral external waits: idle without admission, capture without
input, a held result without ready, and held done without ready. Accepted events,
CLEAR, failure and productive internal helper cycles are retained. `hold`
equates every inventoried reference sequential register and memory, while next
reference input fields remain free. It does not equate whole SMT state objects
or require every actual register to freeze. Removing reference hold edges
leaves an ordinary native canonical execution.

The relation is actual local failure or the live-state clauses in
`product.smt2`. Phase-dependent liveness selects owned scalar values and RAM,
ROM and shift payloads. Captured array prefixes agree at native address widths;
unused payloads may differ. Reachable-state invariants establish helper lifecycle,
bounds and phase ownership. Live reference watchdog values are no larger than
actual values. The consumed role/row coefficient, multiplier and exponent equal
the corresponding pinned coefficient-ROM entry. Numerical replies are derived
from the retained native arithmetic, not assumed equal.

`history.smt2` defines a functional observer with active invocation, captured
count, role/exponent, vector and output ordinal. It drives no DUT signal.
Legal accepted captures extend its owned vector prefix, which agrees with
actual RAM. Output validity requires complete legal capture, correct row/last
and matching canonical value. A held result retains its ordinal; a handshake
advances it. DONE requires ordinal 256 and canonical DONE.

Reset and CLEAR bases establish the relations despite old payload. A separate
ordinary-admission lemma connects an idle reachable DUT to a fresh canonical
reference without resetting the DUT. Failure persists and suppresses results
until actual CLEAR or hard reset. No future-health or equal-fault-outcome
assumption excuses an actual valid beat.

The finite canonical horizon follows from native watchdog counter-update,
idle-exit and failure-boundary laws plus a checked 32-bit ranking fact. A
context-qualified consequence combines them: the checker verifies each source
fact's assumptions, retains any unmet conditions in its implication, and checks
the logical join. These contextual imports do not replace numerical producers.
The horizon is the native watchdog plus 512 clocks after admission; lack of
DONE by then rejects the reference invocation.

Unary, product and history preservation cover every value of the actual 5-bit
parent-state sort. CLEAR and already-failed cases use separate checked lemmas.
The common rules are initialization, unbounded induction and consequence, with
acyclic dependency imports. `PROOF-PLAN.json` records assumptions, conclusions
and complete case groups.

All 26 top-level rules passed: 118 UNSAT obligations and one SAT non-vacuity
query across 119 engine calls. Full-vector post-CLEAR witnesses for all 13 roles
and actual-only stale-state/wrong-operand controls passed transcript validation.
Those traces are finite evidence alongside the induction proof.

Actual caller ports and parameters are source-bound. Caller operand provenance,
other operators, main graph/memory meaning, independent mathematical-oracle
correctness and bitstream equivalence remain outside this component result.

Use the [portable reproduction entry](README.md#reproduction) for recorded
validation or fresh source compilation, all solver queries and finite controls.
