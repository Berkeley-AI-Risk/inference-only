# Scope of the accompanying arithmetic-method review

This is an independent **AI static review**, not outside human review or a fresh
engine replay. The original review body below is reproduced verbatim, SHA-256
`64da2ad46d7e22d043c581c983996b52893e85a84c35a1fca246ed1f9df9b68e`. It assesses the explicitly trusted finite word-interpretation
rules and named helper revisions. It is supporting review evidence; the current
complete-Q qualification and replay remain the authority for the joined result.
See [documentation status](DOCUMENTATION.md) for the trusted-rule boundary.

---

# Independent review: native word arithmetic to integer Q arithmetic

Reviewed 2026-11-04. This is a narrow follow-up to the plan review. I inspected
`arithmetic.py`, `profile.py`, `postscale.py`, `tile.py`, `tile_any.py`,
`lanes.py`, `abstract_multiply.py`, `q_check.py`, the shared
`native_induction.py`, the arithmetic specifications, and recorded check
summaries. I did not run a solver, simulation, proof engine or implementation
change. Recorded results were inspected, not independently replayed.

## Verdict

**The proposed semantics-based route is sound and intelligible, provided it is
implemented as an explicit, narrowly checked derivation rule.** It need not
leave an unproved hardware translation premise. The standard meaning of the
word operators is already part of the formal model's foundation; a solver need
not rediscover it through a difficult mixed bit-vector/integer query.

However, recognizing “a multiplication with the right widths” and finding an
unrelated integer bound is not enough. The checker must carry out the complete
signed/congruence/no-wrap derivation below, apply the actual proved provider
with its exact guard and substitutions, and expose every premise. This extends
the trusted proof-rule code in the Python checker. State that fact and make the
small rule auditable; do not report it as a raw solver UNSAT result that never
occurred. A future machine-checked proof of the generic rule could reduce that
trusted code, but is not mathematically necessary for this review's approval of
the method.

## The exact mathematical bridge

Use distinct names `U_N(v)` for unsigned interpretation and `S_N(v)` for signed
two's-complement interpretation. Let `M=2^N`, and, for `0<=t<M`, define
`H_N(t)=t` when `t<M/2`, otherwise `t-M`. Define
`SR_N(z)=H_N(z mod M)` for an integer `z`.

The official theory defines `bvmul` through multiplication of **unsigned**
representatives followed by reduction to the word width; it also gives the
piecewise signed interpretation and nonnegative remainder convention. These
are the relevant definitions, rather than an assumption about a hardware
product. [SMT-LIB FixedSizeBitVectors](https://smt-lib.org/theories-FixedSizeBitVectors.shtml)

For `A:BV16`, `W:BV10` and their signed extensions to BV26, derive:

```text
U_26(sext(A)) ≡ S_16(A)                         (mod 2^26)
U_26(sext(W)) ≡ S_10(W)                         (mod 2^26)
S_26(bvmul_26(sext(A),sext(W)))
    = SR_26(S_16(A) * S_10(W))
```

The first two facts require the actual sign-extension/bit interpretation, not
zero extension. To justify the third, write each unsigned representative as
its signed value plus either zero or `M`. Expanding their product shows that
the difference from the signed product is an integer multiple of `M`. Thus
their remainders agree. Finally connect the result's sign bit to the upper or
lower half of its unsigned range.

The independent no-wrap lemma is:

```text
-2^(N-1) <= z < 2^(N-1)  implies  SR_N(z) = z.
```

For negative `z` its residue is `z+M`; for nonnegative `z` its residue is `z`.
The lower bound is inclusive and the upper bound strict. This proof can be
checked in the integer theory with constant moduli, separately from native
multiplication. It is then instantiated with the exact signed-product term,
using its proved bound. There is no asserted equation equating a desired
actual product to that term.

The semantics/congruence rule itself must appear in the derivation, not merely
the final no-wrap lemma. Otherwise unsigned-to-signed multiplication remains
the very seam that the failed direct query was intended to close.

## Important details in the current artifacts

1. **Match the bound to the actual statement.** The current
   `mac/signed-product-integer` rule is guarded by native transition context and
   `multiply_i`, but has no exclusions for −32768 or −512. The existing
   `bounds/integer-product-bound` only covers the smaller legal domain
   `[-32767,32767] × [-511,511]`. It cannot directly discharge the universal
   rule's bound premise. Preserve the universal rule by proving the full
   signed16/signed10 type bound: the absolute product is at most `2^24`, safely
   inside signed26. Alternatively, give a separately named derived theorem its
   exact legal-domain premises and discharge those at actual use. Do not
   silently change the old theorem or its receipt.

2. **Disambiguate conversion names.** `arithmetic.signed()` currently uses the
   Z3 unsigned `(bv2int ...)` spelling inside its piecewise signed function;
   the runner translates that spelling to cvc5's `ubv_to_int`. In the SMT-LIB
   theory document, the *semantic helper* named `bv2int` denotes signed
   interpretation. Keep the derivation in explicit `U_N`/`S_N` notation and
   pin the implemented dialect mapping. Z3's API also distinguishes unsigned
   and signed conversion explicitly. [Z3 conversion documentation](https://z3prover.github.io/api/html/namespacez3py.html)

3. **Use the enabled branch of the actual recurrence.** The native product
   theorem states that the next register is the multiplication only when
   `multiply_i` is true; otherwise it retains the old product. The integer
   bridge must retain that guard. The accepted-operand and pending-product
   history joins establish which earlier operands the currently accumulated
   product represents. The bridge does not replace those ownership proofs.

4. **Close all word/integer operations needed by the independent sum.** The
   product bridge alone does not prove integer Q arithmetic. Apply the same
   explicit interpretation/no-wrap reasoning to `bvadd48`, the FIRST-selected
   zero or prior prefix, sign-extension of product26, and extraction of dot35.
   The current integer prefix bounds then establish that the owned sum is an
   exact integer sum, all high bits have the proper sign, and dot extraction
   loses no value. An assumption that native overflow detection stayed low
   would not be an acceptable substitute.

5. **Postscale needs its own completed bridge.** The recorded
   `split-multiply-recombine50` rule is currently unsuccessful, while native
   multiplication, split reconstruction, extensions, integer split identity
   and product-width lemmas are recorded separately. The proposed method can
   avoid that expensive word-distributivity query too: interpret each actual
   signed27×signed18 multiply as an exact signed48 integer product, apply the
   proved signed35/low25/high10 split and integer distributivity, then interpret
   the actual add/shift50 recombination with its bound. All signed27×signed18
   products fit signed48 even before the narrower Q metadata bounds. The
   exact actual pipeline/operand bindings and the add/shift expression still
   need checking; the integer identity alone supplies neither.

## The uniform multiplication abstraction remains a different proof step

The saved tile preservation method is sound for its stated purpose. Uniformly
replacing every BV26 `bvmul` in the whole negated implication with one fresh,
unconstrained total `F:BV26×BV26→BV26` gives a stronger query. UNSAT for every
interpretation of `F` permits instantiation with concrete BV26 multiplication.
The transform's freshness, complete replacement, fixed sort and unchanged
assertions are essential.

That argument establishes product tracking/ownership and is not a proof of
`F`'s arithmetic meaning. The later integer bridge must apply to the recovered
**concrete** history/recurrence, after this instantiation, never to arbitrary
`F`. `q_check.py` reconstructs the saved transformed query at the approved
preservation rule and checks its raw answer; retain that artifact path and its
distinct role. No extra arithmetic axiom about `F` should be added.

## Required checker/application record

The current checker reconstructs canonical implication shapes and checks saved
engine queries. It does not yet implement this semantic derivation. Add a
distinct derived-rule kind, rather than accepting the timed-out bridge because
neighboring engine rules passed. Its record should make the following
independently inspectable:

- The exact native recurrence provider, source pins, current/next state,
  enable/FIRST branch and operand terms, including all widths and extensions.
- The exact unsigned/signed interpretation and operator-semantic rewrites,
  with their resulting formulas and substitutions. Typed term matching or
  equally strict canonical reconstruction must reject changed widths,
  extensions, slices, operators or histories.
- The bound/no-wrap providers and their literal premises instantiated on the
  same terms. Each premise must be discharged; a bound on a separate variable
  with no checked substitution is not a connection to the actual word.
- The final derived implication, complete provider dependency order and scope.
  No desired actual product/sum/result or untyped external fact may enter as an
  additional assumption.
- A derivation receipt identifying its trusted semantic rule version, checked
  engine-provider receipts and conclusion, rather than a fabricated raw engine
  `unsat`. Preserve the failed direct-query receipts honestly as failed.

Refusal controls should cover zero extension replacing sign extension, a
too-narrow product, an incorrect signed threshold, a missing negative case, a
legal-domain bound applied without its premise, a disabled multiply branch,
the wrong pending operands, missing instance coverage and an injected desired
product equation. Exhaustive small-width checks can usefully test the generic
rule implementation, including wrap cases; they do not replace its mathematical
justification for the actual widths.

## Practical alternative and recommendation

The cleanest solver decomposition is already close to the proposal: keep the
native word/port/history proofs in the BV theory; prove the signed-residue and
constant-modulus congruence lemmas in the integer theory; join them by the small
explicit semantic rule. Integer variables can stand for arithmetic expressions
when applying universally proved lemmas, provided that substitution is checked
and is not a new hardware assumption. This avoids asking one engine to solve
both bit-blasted multiplication and its unbounded integer expansion at once.

If a direct mixed solver result remains desirable as additional corroboration,
first isolate the two-operand bridge from native transition context and split
the four sign cases. A fallback is exhaustive case splitting on the narrower
10-bit operand, with checked complete case coverage: each branch has constant
word multiplication and linear integer scaling. That is a finite, transparent
route, but likely costs more than the semantic rule and does not strengthen the
meaning of the final theorem. It is optional corroboration, not a reason to
repeat the unchanged timed-out query.

I recommend the explicit semantic derivation with the safeguards above. It
preserves the user-facing independent integer specification: the dot remains
the mathematical sum of the accepted activation/model products, and the proof
shows that native finite words represent those integers. It does not define
the integer answer to be whatever the RTL happened to produce. This method
approval does not qualify the still-open complete Q composition or establish
physical DSP equivalence.

## Static audit of the implemented finite semantic rules

I subsequently audited `word_derivation.py`, SHA-256
`a6bb7d13681b8550b8746acb7753935a692b8687a23b94016e79e27d962e2668`,
together with `word_semantics.py`, `word_algebra.py`, `wide_bounds.py`, the
updated `q_check.py`, `tile_cases.py`, `tile_bindings.py`, the explanatory
`WORD-INTERPRETATION.md` and the seven saved derivation summaries. The inspected
`q_check.py` has SHA-256
`3cd4ba468c6cab2b983be79a47d5014a2d31334631c2f0d061b1a4c59f3b9c8d`.
This was static review only; I did not execute the checker or replay engines.

**Verdict: the seven fixed canonical targets are sound under the deliberately
exposed trusted semantic-rule boundary. I found no missing numerical domain,
false signedness/width relation, incorrect product substitution, or lost
enable/FIRST guard in those targets.** They are suitable component providers
for the next joins, subject to the specific application obligations below.

The review does not require turning this into a proof assistant. Its actual
mechanism must remain clear: `shape()` compares a candidate to the fixed
canonical constructor; it does not interpret an arbitrary sequence of proof
steps or symbolically execute every `instantiations` record. Mathematical
validity of the seven fixed semantic rule bodies is therefore trusted and
reviewed, while the engine-provider queries are checked against their raw
receipts. In that declared model, hardcoded canonical steps are not unchecked
desired hardware answers: each is a valid universal word-interpretation rule,
or an explicit conditional application to a source-proved equation. The records
correctly distinguish derived receipts from engine UNSAT, and retain
`whole_Q_operator_proved=False` and `whole_machine_theorem=False`.

| Derived kind | Audit conclusion and retained condition |
| --- | --- |
| `signed-native-product` | Correctly applies the enabled native product26 recurrence. The two sign indicators and the factorization substitution match `x*j+y*k+2^26*k*j`. The full signed16×signed10 bound now covers −32768 and −512, so the original universal target no longer depends on the narrower legal-Q bound. |
| `signed-native-accumulator` | Correctly interprets the enabled bvadd48 branch, with FIRST selecting integer zero and the other branch selecting the actual old accumulator. The signed48 bound on their sum remains a literal target premise. |
| `FIRST-integer-overwrite` | Carries the actual accumulate/FIRST premises from the native overwrite theorem and uses sign-extension preservation. It claims the existing pending product's value, without asserting that product is fresh or belongs to Q. |
| `bounded-dot35-extraction` | Correctly reduces the low35 word modulo 2^35. The difference between unsigned48 and signed48 is divisible by 2^35. The signed35 range premise is explicit; tile read/row ownership is still separate. |
| `signed-native-postscale-multiply` | The native operands are sign-extended from signed27 and signed18 to BV48. Their full type product fits signed48, and the signed-residue application is valid without model-specific bounds. |
| `split-postscale-word-ring` | The proved BV50 split plus standard add/multiply/constant-shift ring semantics establishes the exact target modulo 2^50. Its use of unsigned representatives for high50 is correct for this ring equality; it is not incorrectly claiming that unsigned high50 equals signed high10 as an integer. |
| `split-postscale-integer` | Correctly specializes the ring result to signed35 dot and unsigned15 multiplier. The full-type product bound fits signed50, including zero multiplier. The unsigned positive multiplier extension and signed-dot extension give the required signed interpretation before no-wrap. |

Some intermediate applications in the accumulator, multiply48 and ring records
are represented by fixed descriptive steps rather than a complete list of
literal substitutions. Their mathematics is unambiguous and valid for these
canonical terms; this is inside the declared trusted finite rule. Do not later
generalize the constructor to arbitrary terms or widths while retaining only
these descriptive checks. Any such generalization needs its own type,
substitution and premise validation.

### Specific obligations before applying these providers to actual Q results

1. **Connect the actual postscale width/extension path.** The abstract
   `split-postscale-integer` target contains BV50 low/high products. The actual
   engine registers signed48 products and computes its low contribution with
   `{2'b00,low_product_q}`, a *zero* extension, while its high contribution is
   sign-extended before the shift. Prove that the actual low product is the
   nonnegative unsigned25×unsigned15 product fitting positive signed48, and
   that the actual high product is the corresponding signed10×unsigned15
   product. Also bind the actual 16-bit metadata multiplier with bit15 clear
   to the theorem's BV15 `m`. The existing width/extension and wide-bound
   providers can support this. This obligation is not discharged by the
   abstract ring theorem or generic signed27×signed18 theorem alone. It is a
   real next application premise, not a counterexample to either provider.

2. **Discharge the conditional bounds on the same current history.** The
   accumulator and extraction targets retain bounds intentionally. The larger
   proof must connect the actual pending product and FIRST event to the
   current accepted-operand history, establish its integer prefix bound, and
   then apply the exact bound substitution. It must also join dot read,
   metadata, row and held postscale pipeline. No product/accumulator value
   from an unowned phase is made current by these semantic rules.

3. **Reconstruct derivations when importing them.** `verify()` rebuilds the
   canonical derivation, checks its selected engine providers, and returns or
   writes a fresh record. It does not read and validate an existing
   `*-DERIVATION.json` as an input. A larger join must invoke that reconstruction
   or compare a saved record against it and its current providers. Importing
   only a saved `checked:true` would create a new unchecked receipt seam that
   is absent from the reviewed rule mathematics.

4. **Keep dependency closure when selecting engine providers.** The currently
   selected semantic engine providers are dependency-free, so checking those
   exact named rules is sufficient here. In general,
   `q_check.check(..., only_rules=...)` checks only selected receipts; it does
   not recursively verify their local dependency receipts. If the next join
   selects an implication whose query imports other rule implications, those
   dependencies must also be checked. For example, selecting only the
   tile-cases preservation join would not by itself verify its sixteen case
   receipts. The presently recorded full 26-check tile contract and the
   all64 binding's full checks do not have this omission.

The inspected source-specialization record appropriately leaves accepted Q
invocation/layer/group, exactly 256 columns, FIRST/last alignment, model and
activation histories, reads, postscale and completion joins open. Neither the
seven arithmetic derivations nor the 26 tile checks silently close them. There
is no need to rerun the failed direct BV/Int or word-distributivity query merely
to justify these reviewed semantic rules. The next work should discharge the
actual application premises and retain the current accurate completion flags.

## Narrow follow-up: actual postscale frame and pruned multiplication queries

I statically inspected the added `frame-integer-function` rule, `frame.py`,
`frame_algebra.py`, `frame_integer.py`, `pruned_arithmetic.py` and the updated
checker. Recorded summaries show eight frame obligations, six scalar frame
facts and the held-output application passed. I did not run or replay them.

**No missing premise or unsound substitution was found in this added rule or
application. The pruning/uniform-abstraction transformation is sound for the
canonical query language and uses inspected here.** The following distinctions
are material to that conclusion.

### The arithmetic application retains the needed guard and physical extensions

The new semantic target has `d:BV35`, `m:BV16` and the explicit premise
`m[15]=0`. It unfolds the exact regenerated `frame-low`, `frame-high` and
`frame-raw` definitions, which use the actual signed27/signed18 operand views,
48-bit products and low-zero/high-sign extensions into the raw50 sum.

The scalar facts establish that the low48 product is nonnegative, making its
actual zero extension equal to sign extension. They also establish unsigned25,
signed10 and unsigned16 operand interpretations. The full signed27×signed18
bound permits exact interpretation of each 48-bit product. The signed35 split
and distributivity then give the desired product modulo 2^50; `m[15]=0`
supplies the unsigned15 bound needed for the final signed50 no-wrap step. Zero
multiplier is harmless for this local arithmetic theorem. Positivity and model
identity of a legally used multiplier remain separate caller facts.

The rule derives these facts by the declared fixed standard-word semantic
unfolding; it does not import an assumption that an actual DSP product already
has the desired answer. Its use of sign-extension preservation for the exact
extended operands is within that exposed trusted finite rule.

`frame_integer.py` substitutes the actual history expressions `fr-D3(h)` and
`fr-M3(h)` by parsed symbol substitution into the semantic conclusion. Its
target retains the corresponding `fr-M3(h)[15]=0` guard, native well-formedness,
reset, frame invariant and actual output VALID. Its semantic equality premise
is a discharged provider application: `q_check.py` reconstructs and verifies
`frame-integer-function`, and checks the complete frame induction before
accepting this application. It is consequently not an unclosed desired raw
result assumption. The frame result remains a theorem about the tuple actually
captured by the pipeline; correct current Q dot, metadata, epoch and row
identity have not been inferred.

The updated checker also closes selected providers' local dependency receipts,
including the nonnegativity dependency of the zero/sign-extension fact. This
addresses the earlier selected-rule dependency concern for this application.

### Why the pruned query implies the concrete query

`pruned_arithmetic.py` roots its dependency analysis at **all non-`define-fun`
statements**, not just selected assertions or the conclusion. It recursively
scans every atom in needed definitions, including function bodies and bare
zero-argument references. Lexical shadowing can cause it to retain extra
definitions, but cannot remove a genuinely referenced one under this analysis.
It explicitly refuses a remaining reference to a removed definition. Removing
an unused, ordinary total `define-fun` is elimination of a definitional
extension; it does not drop a constraint or change satisfiability.

After pruning, every remaining binary `bvmul` application is uniformly replaced
with the same fresh total `F48:BV48×BV48→BV48`. No assertion is removed. The
freshness test covers the complete parsed input, and undoing the replacement
must recover the pruned syntax tree exactly. The ordinary engine type check
must accept all these uses at BV48; mixed-width or nonbinary cases cannot
produce the exact accepted UNSAT answer. UNSAT for the transformed query means
no interpretation of `F48` satisfies that query. Choosing actual BV48
multiplication recovers the pruned concrete query, and unused definitions can
then be restored. This establishes the concrete implication.

The checker reconstructs that precise transformed engine query from the
canonical original and restricts this solver mode to frame preservation rules.
The proof is product/value **tracking** under an arbitrary common function;
the later integer interpretation applies to recovered concrete multiplication,
not to arbitrary `F48`.

The trusted boundary includes the SMT parser/printer and definition-dependency
analysis on this fixed input language, uniform-symbol substitution, the finite
canonical semantic rules, the native frontend/source model, and raw solver
soundness. The tokenizer is not a general proof checker or an excuse to expand
this transformation to other SMT command forms without review. The actual
canonical inputs use the ordinary definitions/declarations/assertions covered
by the argument above. Physical DSP correspondence remains its named platform
boundary. No complete Q theorem is claimed by these local results.

Reviewed identities:

| File | SHA-256 |
| --- | --- |
| `word_derivation.py` | `52e3398a2c6f0d7a874c6d6bb86460fd2223114712f32c1186410f0475f03a3f` |
| `frame.py` | `4427c5b1823c92c54146f87a81aa438e6bb6f4865c34258ee6e51e3e01cf9b73` |
| `frame_algebra.py` | `14781f7d8b026d9638bd3e445e7f4b7ff713a4f4e090336f46e13d4c276212f4` |
| `frame_integer.py` | `8f967032a5783915ab8d5b7bafd8e299b27d3a06b5da49f727d318977afcdc02` |
| `pruned_arithmetic.py` | `96f81fd9dd6260f40788d0e5e6063579480fbee05553dc01a071824dbe4aa6c7` |
| `q_check.py` | `ab55002cc35caaeb0f5b4cfcf264f03eb389123ada2437fa61233ba36e7a8742` |
