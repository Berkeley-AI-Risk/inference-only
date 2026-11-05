# Baseline Q: independent value specification

This extends the accepted-argument/model-provenance theorem with the complete
source-bound Q value/prefix/completion argument. Qualification is recorded in
the enclosing package's receipts.
Sources, parameters and model image are named in the generated inventory.

An invocation is an accepted STAGE_Q/job0/layer L (0..5) with 256 ordered signed16
mantissas A[c] in [-32767,32767] and captured signed8 exponent e. No narrower
caller exponent bound or correctness of RMSNorm's output is assumed. The model
supplies signed10 weights W in [-511,511]. Each real metadata record has bits
31:24 zero, signed8 row exponent at 7:0, and positive unsigned15 multiplier
at 23:8 (bit23 zero). E=e+row_exponent-15 must fit signed8; otherwise the metadata
service rejects. Coefficients and metadata must be supplied by the existing
actual cache/transport provenance theorem on the same accepted events.

For row r=64*g+l, g=0..3 and l=0..63, the mathematical integer specification is:

    S[r,0]=0
    S[r,c+1]=S[r,c]+A[c]*W[L,r,c]   (c=0..255)
    D[r]=S[r,256]
    R[r]=D[r]*multiplier[L,r]
    E[r]=e+row_exponent[L,r]-15

The prefix bound is |S[r,c]| <= c*32767*511. Consequently |D|<=4,286,447,872
and |R|<=140,454,037,421,824. The actual 26-bit product, 48-bit accumulator,
35-bit dot and 50-bit raw output must represent these integers exactly. Native
overflow detection is a consequence, not a hypothesis of this statement.

Endpoint A is the job result's held VALID value and each VALID/READY transfer:
row r, signed50 R[r], signed8 E[r], and last exactly at r=255. Transfers are
ordered and counted once. A later fault or CLEAR cannot excuse an earlier wrong
live value. Successful job DONE requires all 256 rows transferred.

Normalization is defined by the finite algorithm in
`NORMALIZATION.md` . It specifies an ordered prefix
of (row, signed16 mantissa, common signed8 exponent, last) and either success or
arithmetic rejection. For nonzero vectors it tries exponents from the clamped
bit-length lower bound through 31, using signed RNE and the specified helper
shift limits. For zero vectors it selects exponent0, emits zeros sequentially
and rejects at the first shift<-62. Successful completion requires 256 transfers;
rejection never erases a previously emitted prefix.

Endpoint B includes held normalizer VALID, accepted transfers, actual guarded
STAGE_Q Q-RAM write admissions at output_index_q[7:0], query_exponent_q updates,
and stage completion. Every admitted write has the current invocation's correct
coordinate and mantissa. The common exponent belongs to that invocation. Stage
DONE requires the full ordered vector plus actual projection and normalizer
completion. Projection and normalizer starts may occur on different edges;
their stable stage/layer/generation equality must be proved.

Endpoint B does not claim retained Q-RAM contents or later read semantics while
query storage remains abstract. Q RoPE, attention, the caller's complete graph
meaning, other hardware configurations, timed arithmetic authorization and
physical DSP/bitstream equivalence remain separate obligations. This value
theorem does not authorize arbitrary watchdogs/faults in the whole-device
inference-only theorem.
