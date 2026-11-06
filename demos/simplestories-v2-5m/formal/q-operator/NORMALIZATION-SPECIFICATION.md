# Independent Q normalization specification

This is the finalized reader-facing specification for the qualified Q component. This is a finite algorithm on
256 integer raw/exponent pairs, not a function defined by actual RTL execution.
The values are signed raw50 R[r] and signed8 E[r] from the projection definition.

Define Shift(x,d) on signed64 x and integer d:

- d < -62: arithmetic rejection, including x=0.
- d > 62: result zero, without arithmetic rejection.
- -62 <= d < 0: exact x*2**(-d), rejecting if outside signed64.
- 0 <= d <= 62: signed round-to-nearest, ties-to-even of x/2**d.

A mantissa fits exactly when it lies in [-32767,32767].

If any R is nonzero, set b to the maximum, over nonzero rows, of
clamp(E[r] + bit_length(abs(R[r])) - 15, -32, 31).
For candidate k=b,b+1,...,31 in order:

1. Evaluate Shift(R[r], k-E[r]) for every row in row order. A helper arithmetic
   rejection rejects the normalization; no normalized rows have been emitted.
2. If every shifted result fits, select k and emit those 256 mantissas in row
   order with common exponent k, then complete.
3. Otherwise try k+1. Reject if no candidate remains.

The leading-bit candidate is a mathematical lower bound for an exponent with
fitting signed16 results; prove that bound independently from the native
parallel leading-bit implementation. The RNE fit pass handles rounding carry.

If every R is zero, choose k=0 and skip the fit pass. In row order evaluate
Shift(0,-E[r]) and emit a zero row on success, or reject at the first arithmetic
rejection. Thus this path may produce a proper prefix and then reject. DONE
requires all 256 rows. Do not replace it by unconditional zero-vector success.
The output stream plus arithmetic outcome is part of the independent profile.

Source-derived counterexample to an all-or-nothing zero-vector contract:
for actual I0, layer0, A[c]=0, accepted activation exponent e=89, rows0..16
have E<=62 and row17 has E=63. Their metadata sums fit signed8. The zero path
emits 17 zero rows at exponent0, then its shift -63 rejects. A native fixture
must confirm this independently and compare the result prefix/outcome.

Actual nonnumeric cancellation, lock/fault and watchdog events can truncate a
numerically defined stream. They cannot excuse an earlier wrong row. The
normalizer watchdog counts capture/result/done waits as well as arithmetic;
a transfer at count MAX-1 may occur before the higher-priority fault is latched
on that edge. The value/accepted-prefix proof must account for that transfer.
Exact watchdog authorization belongs to separately stated resource rules,
not a change to the arithmetic algorithm above.

The actual Q datapath starts projection and normalizer through separate start
handshakes. Prove their shared Q stage/layer/invocation before joining streams.
For a retained-vector claim, restore the concrete query-state RAM or prove its
source contract. A normalized stream alone does not prove Q RAM read contents.
