# Sealed weight-bank proof

This component theorem uses the actual weight-page bank RTL and its complete
128-by-256-bit RAM. Both Z3 and cvc5 check all 42 assertions together by
reset-initialized induction of length two. Supporting phase/count invariants
are proved, not assumed.

The result establishes fill-before-read, no writes during hashing or verified
use, admission only after a matching completed digest comparison, correspondence
between hash-input blocks and the sealed memory, replies owned by accepted
in-range reads, and integrity faults that read cancellation cannot clear.
Invalid replies expose zero data. The expected digest and page tag remain
latched for the page's lifetime; a new accepted assignment invalidates the
old verified state before refilling. A held reply prevents eviction.

Hash-input correspondence holds when a block is launched. While the
compressor processes that captured block, the bank can prefetch the next
block into its input register. Five supporting invariants track this
prefetch sequence and its correspondence with the sealed RAM. The proof
does not assume that the input register stays unchanged during compression.

The geometry is the actual 227,062-word image: 1,774 pages, with 118 model
words and ten zero-padding words in the final page. A single arbitrary,
constant observer address ranges over every word. A source/dependency audit
checks that its added read-only RAM observation cannot drive production logic,
RAM writes or the production read control.

## Important boundary

The SHA compressor's busy, done and 256-bit result signals are **arbitrary**
in this proof. The bank may grant verified status only when the completed
result matches its latched expected digest. This does not prove that the
compressor calculated the right result, that SHA-256 is collision-resistant,
or that the parent selected the correct fixed digest ROM entry. All other
component inputs are unrestricted too; only reset initializes the base.
There are no assumption cells.

The hash-input correspondence uses the production byte-order conversion;
the directed simulation fixture checks that ordering independently. The
fixture supplies controllable compressor results rather than computing SHA.
Ten directed scenarios exercise full/partial pages, every valid word address,
reply backpressure, cancellation/reuse, changed external digest inputs,
corrupted digests, and invalid fills/pages/reads. Five deliberately faulty
variants must fail: digest bypass, premature verification, writes to sealed
RAM, clearing faults on cancellation, and incorrect hash byte order.
These sensitivity checks are simulation witnesses, not bounded SAT proofs.

The proof does not establish whole-chip CLEAR, external K/V authenticity,
numerical next-token correctness, progress, mapped-netlist equivalence or
physical-tamper resistance. Reset is permitted to clear a bank fault.
The component's arbitrary expected-digest input is not a public operation.
See [the overall formal status](../../FORMAL-STATUS.md).

## Replay

From the package root, with Yosys, Z3, cvc5, Icarus Verilog and `vvp` available:

```sh
python3 -I -S -B tools/check_page_bank.py --package . --work ../fresh-bank-proof
```

Explicit `--yosys`, `--z3`, `--cvc5`, `--iverilog` and `--vvp` paths are accepted.
Use a new work directory outside the package. This stage needs no model
download, numerical Python environment, vendor software or physical FPGA.

The wrapper runs both solvers and the scenarios, checks exact generated
source/elaboration/formula correspondence with the originally audited result,
then re-elaborates and audits the sources, observer, formulas and raw results.
An audit verify-only pass checks the recorded file identities again. Sources
inside the package remain unchanged. A timeout is not a passing proof.
