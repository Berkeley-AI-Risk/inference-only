# Periodic-reauthorization formal status

The main objective is a whole-machine theorem relating every public command stream to APPEND, STEP with the admitted fixed-architecture model and CLEAR, conditional on current model-specific permission. Functional numerical correctness, authorization and the inference-only boundary are related obligations. The whole-machine theorem remains open.

The [authorization-control packet](formal/authorization-control/README.md) contains twelve source-bound jobs: ten inductive and two auxiliary combinational results. They cover grant/model/nonce framing, lease expiry, registered permission, reset/start sequencing, signature-byte RAM, reply admission/deadline, renewal continuity, runtime request gating and the boot-to-home verifier handoff. The exact conditional statement and child contracts are in its theorem and source records.

The [page-consistency packet](../signed-update/formal/page-consistency/README.md) adds two full-geometry controller proofs with abstract hash flow. The [stream-assembly packet](../signed-update/formal/stream-assembly/README.md) proves five wrapper equivalences under common compressor responses. The authorization packet keeps its original query/source fingerprints and explicitly consumes that exact wrapper substitution; engine records are not retagged.

Cryptographic algorithm correctness, complete image-to-consumer numerical provenance, hostile K/V-memory tolerance, physical clocks/CDC, entropy, power-cycle freshness, physical security and residual-training bounds remain separate. The [board and simulation evidence](VALIDATION.md) supplies finite functional checks, including real signatures and reference-matched generation.
