# Q specification and review status

The current complete-Q theorem uses the independent normalization algorithm in
[NORMALIZATION-SPECIFICATION.md](NORMALIZATION-SPECIFICATION.md). Its arithmetic,
ordered prefixes, zero-vector rejection, rounding and interruption rules are
unchanged from the hash-bound [NORMALIZATION.md](NORMALIZATION.md), SHA-256
`9bf81960ce66071a1321b68829abfd09952cb6cf0cbca8a8644ecd587887fa7a`. Only the reader-facing title/status sentence is finalized.
The original file is retained unchanged because it is an input of the existing
qualified, replayable proof capsule; its draft label does not indicate an open
choice of algorithm in that theorem.

The previously cited [arithmetic-method review](ARITHMETIC-METHOD-REVIEW.md) is
available here. It is an independent AI static review of named finite semantic
rules, not outside human review or a fresh proof-engine result. Its original
body is reproduced verbatim and its scope/revisions remain explicit.

The small canonical word-to-integer interpretation rules, SMT parsing and
substitution, source-specialization logic and composition checker are within
the declared trusted checking boundary. They are inspected mathematical rules;
they are not fabricated solver UNSAT receipts. Their native recurrence, bound
and ownership providers still need the exact engine-checked dependency joins.
See [WORD-INTERPRETATION.md](WORD-INTERPRETATION.md) and the review for those
premises. Executing or compiling Python alone establishes no hardware theorem.

These three reader/review documents supplement the sealed proof capsule. They
do not alter `project.tar.gz`, `PACKAGE.json`, the frozen algorithm, engine
queries, receipts, theorem conclusions or downstream dependency pins. The root
release inventory must include the added documents when packaging. The replay
instructions and their selected-versus-full engine distinction remain in
[README.md](README.md).

The complete-Q package establishes writes and stage completion. The separate
[RMSNorm-to-Q segment](../rms-q-segment/THEOREM.md) additionally establishes
retained query payloads and pre-overwrite reads. Q-RoPE, attention consumption,
remaining graph and the whole-device inference-only theorem remain open.
