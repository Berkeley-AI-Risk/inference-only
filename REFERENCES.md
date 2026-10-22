# Design references and prior work

These demonstrations combine established model algorithms, cryptographic
primitives and hardware techniques with project-specific fixed control,
memory-access restrictions and verification. AI authorship of the custom
implementation is not a claim that those underlying ideas are new.

The references below distinguish **components and algorithms used** from
**related architectural work**. A related-work citation does not mean that we
copied its RTL, used its tools, or established its reported performance or
security properties. Exact borrowed-file revisions and licenses remain in
[the third-party notices](THIRD-PARTY-NOTICES.md) and
[Qwen dependency notices](demos/qwen3-1.7b/NOTICES.md).

## Models and inference algorithms

- **SimpleStories.** The trained weights and tokenizer come from the
  [pinned SimpleStories-V2-5M checkpoint](https://huggingface.co/SimpleStories/SimpleStories-V2-5M/tree/c4b3a4bb81297f5316697098e1d4b65c1249daf8).
  Its model card cites Finke et al.,
  [*Parameterized Synthetic Text Generation with SimpleStories* (2025)](https://arxiv.org/abs/2504.09184).
  The checkpoint and our specified integer conversion, not the paper alone,
  define the exact model executed by this demonstration.
- **Qwen3.** The second demonstration derives from the Qwen team's
  [*Qwen3 Technical Report* (2025)](https://arxiv.org/abs/2505.09388) and the
  [pinned Qwen3-1.7B checkpoint](https://huggingface.co/Qwen/Qwen3-1.7B/tree/70d244cc86ccca08cf5af4e1e306ecf908b1ad5e).
  Its quantized numerical reference and fixed greedy rule are documented
  [separately](demos/qwen3-1.7b/reference/README.md).
- **Transformer attention:** Vaswani et al.,
  [*Attention Is All You Need* (NeurIPS 2017)](https://arxiv.org/abs/1706.03762).
  The demonstrations implement attention internally; they do not expose it
  as a general matrix operation.
- **RMS normalization:** Zhang and Sennrich,
  [*Root Mean Square Layer Normalization* (NeurIPS 2019)](https://arxiv.org/abs/1910.07467).
- **Rotary position embeddings:** Su et al.,
  [*RoFormer: Enhanced Transformer with Rotary Position Embedding* (2021 preprint)](https://arxiv.org/abs/2104.09864).
- **Grouped-query attention:** Ainslie et al.,
  [*GQA: Training Generalized Multi-Query Transformer Models from Multi-Head Checkpoints* (EMNLP 2023)](https://aclanthology.org/2023.emnlp-main.298/).
  Qwen3-1.7B uses this model-level technique of sharing eight K/V heads among
  16 query heads.
  The project did not perform the paper's uptraining procedure.

These are algorithmic antecedents, not claims of bit-for-bit equivalence to
the papers' implementations. Our fixed formats, rounding, accumulation order,
tables and model conversions are part of each demonstration's numerical contract.

## Arithmetic implementations and cryptographic specifications

- **Berkeley HardFloat:** John R. Hauser's
  [Verilog arithmetic library](https://www.jhauser.us/arithmetic/HardFloat.html)
  supplies included Qwen floating-point modules. This is direct implementation
  reuse, with its retained upstream license, not merely related work.
- **AES S-box:** the Tang encrypted-memory RTL adapts Thomas Pornin's
  BearSSL implementation of the Boyar–Peralta Boolean circuit. See
  [BearSSL's explanation](https://bearssl.org/constanttime.html),
  Boyar and Peralta's
  [*New Logic Minimization Techniques with Applications to Cryptology* (2009; revised 2010)](https://eprint.iacr.org/2009/191),
  and our [exact source and license attribution](THIRD-PARTY-NOTICES.md#aes-s-box-circuit).
  This is direct circuit adaptation; it does not establish side-channel resistance.
- **SHA-256:** NIST,
  [*Secure Hash Standard*, FIPS 180-4 (2015)](https://csrc.nist.gov/pubs/fips/180-4/upd1/final).
  Used for fixed-weight checks and the Tang protected variants' private
  expected-digest checks. Our record framing, address/context binding and
  before-use publication rules are separate from the hash algorithm.
- **AES and counter mode:** NIST,
  [*Advanced Encryption Standard*, FIPS 197 (2001; updated 2023)](https://csrc.nist.gov/pubs/fips/197/final),
  and Dworkin,
  [*Recommendation for Block Cipher Modes of Operation*, SP 800-38A (2001)](https://csrc.nist.gov/pubs/sp/800/38/a/final).
  The encrypted-memory weight path uses AES-256-CTR plus a separate plaintext
  integrity check; CTR alone does not authenticate weights.
- **AES-SIV:** Harkins,
  [*Synthetic Initialization Vector (SIV) Authenticated Encryption Using the Advanced Encryption Standard (AES)*, RFC 5297 (2008)](https://www.rfc-editor.org/rfc/rfc5297).
  The encrypted K/V path implements this construction. Its private expected
  digests additionally enforce current contents; authenticating an old record
  does not establish freshness.

Using these specifications is not NIST validation or certification of our RTL.
The encrypted demonstration's published test keys provide reproducibility,
not secrecy from someone who has the package.

## Hardware and memory-protection antecedents

**Clock-domain crossings.** Clifford E. Cummings,
[*Simulation and Synthesis Techniques for Asynchronous FIFO Design* (SNUG San Jose 2002)](https://web.archive.org/web/20240304004420/http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf),
describes Gray-coded pointers synchronized between clock domains. This is
established background for the technique used by our
[private transport FIFOs](hardware/project/fifo.sv), not a claim that the
project's FIFO RTL was copied from that paper. Reset, draining, physical
constraints and implementation checks remain specific obligations.

**Decoupled memory movement and reuse.** Pellauer, Shao et al.,
[*Buffets: An Efficient and Composable Storage Idiom for Explicit Decoupled Data Orchestration* (ASPLOS 2019)](https://cwfletcher.github.io/content/research/2019.asplos.buffets.paper.pdf),
develop reusable buffers that separate filling from consumption and manage
synchronization and data lifetime locally. This is related work for our
private prefetch/buffer organization, not the source of the released RTL.
Our checked-weight buffers additionally withhold data until authentication
succeeds; buffer synchronization alone is not authentication.

**Integrity of untrusted external memory.** Suh et al.,
[*AEGIS: Architecture for Tamper-Evident and Tamper-Resistant Processing* (ICS 2003; extended revision)](https://people.csail.mit.edu/suh/papers/ics03.pdf),
describes a trusted processor boundary, external-memory integrity checks,
encryption and cached hash trees. It is an architectural antecedent, not an
implementation we copied. The Tang designs instead keep expected digests
directly on-chip: immutable weight-page digests and, in the protected variants,
mutable private K/V-group digests. They do not implement AEGIS's memory tree
or inherit its security analysis.

Memory integrity is not, by itself, an inference-only restriction. These
demonstrations also fix the inference schedule, permitted model and private
operand/result paths. Their particular guarantees and remaining assumptions
are assessed in [INFERENCE-ONLY.md](INFERENCE-ONLY.md) and the
[Qwen3-1.7B interface assessment](demos/qwen3-1.7b/README.md#interface-and-inference-only-scope)
and [Qwen3-8B interface scope](demos/qwen3-8b/README.md#inference-only-scope).
