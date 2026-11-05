# From native word arithmetic to the independent integer specification

This rule has been independently reviewed in `ARITHMETIC-METHOD-REVIEW.md`.
It is a small explicit mathematical derivation in the trusted checking boundary,
separate from engine-proved implications. The checker records that distinction.
Failed or interrupted direct BV/Int queries remain failed or interrupted.

Use U_N for unsigned word value, S_N for signed two's-complement value and
SR_N(z) for signed interpretation of z modulo 2^N. In this campaign Z3's
`(bv2int x)` spelling is unsigned; cvc5 receives `ubv_to_int`. This spelling must
not be confused with the standard's meta-level signed function named bv2int.
The interpretation uses the [SMT-LIB fixed-size bit-vector definitions](https://smt-lib.org/theories-FixedSizeBitVectors.shtml).

The native MAC engine proof establishes, on its actual multiply enable,
P_next=bvmul26(sext26(A16),sext26(W10)). By the word definition, its unsigned
value is the product of the two unsigned operands modulo 2^26. Sign extension
represents S16(A) and S10(W) modulo 2^26. Each unsigned representation differs
from that signed integer by a whole multiple of 2^26. Expanding their product
and removing that whole multiple gives:

    S26(P_next) = SR26(S16(A16)*S10(W10)).

The separately engine-checked full signed16-by-signed10 bound puts this product
strictly inside signed26, including -32768 and -512. The checked signed-residue
lemma then gives exact integer multiplication. The narrower legal Q bound
[-32767,32767] by [-511,511] remains a separate model/admission fact.

`word_derivation.py` reconstructs the exact enabled native equation, operand
widths, sign extensions, target, congruence providers, range lemma and no-wrap
lemma. It does not accept a proposed native product as an input premise. Its
typed rule is an auditable trusted inference rule, not an additional engine.

The corresponding postscale word derivation uses the engine-proved signed35
split into unsigned low25 and signed high10, multiplication/addition modulo
2^50, constant shift as multiplication by 2^25, and the checked integer
distributivity identity. Actual pipeline ownership, coefficient application and
the final integer no-wrap conclusion still require their own provider joins.

To close the complete Q specification, this rule family must also cover the
accumulator's bvadd48/FIRST, low35 extraction and postscale48/add/shift50 integer
interpretation. Product or ring algebra alone is not the full Q theorem.
