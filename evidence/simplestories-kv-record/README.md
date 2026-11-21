# SimpleStories checked-parent K/V record proof

`SV::KV-WRITE-RECORD` connects a reported completion in the checked RTL to the 18 accepted K/V writes from one saved layer, position and pair store. The checked design is a 76-file behavioral probe reconstructed from the public SimpleStories baseline. The proof ends at the typed RTL handshake. Physical DDR persistence, readback and the numerical origin of the staged K/V values require separate evidence. The encrypted-memory and protected-K/V variants require their own source binding.

## Reproduce the sources

Use Python 3.12, Git, `patch` and a local clone with the objects for commit `470b836cbe94ecebc117fe7cfa2b9008d14951f4`, tree `35a5bf972a45eef735e43b2fd2c9dfdfa64074f1`. Give `--out` a fresh directory name under an existing directory. The clone can be at any checkout. [Pinned public tree](https://github.com/Berkeley-AI-Risk/inference-only/tree/470b836cbe94ecebc117fe7cfa2b9008d14951f4)

```sh
python3.12 -I -S -B /path/to/reproduce.py \
    --public-git /path/to/inference-only \
    --out /path/to/fresh-reconstruction
```

The command reads pinned Git objects locally. It checks the SHA-256 of each of the 77 named RTL inputs, including the historical original controller, and recreates the 76-file elaboration order. The reconstruction blanks the historical `default_nettype` directives, selects behavioral projection, moves two probe declarations before use, inlines the 4,097 words of the pinned exponent image and qualifies the checked controller's busy-CLEAR completion fault. The wrong-position controller is derived separately from those checked bytes. The command then generates all four record books into the fresh directory and compares them byte for byte with the recorded certified sources. `REPRODUCTION.json` gives the exact digest of each output. [Reconstruction manifest](reconstruction/SOURCES.sha256) · [Per-file candidate manifest](MANIFEST.json)

The command regenerates source and does not launch ACL2. For a source-only check of the translator correction, add `--stock-translator /path/to/acl2-8.7/books/centaur/sv/vl/svstmt-compile.lisp`. Review the retained recipe and obtain compatible proof tools separately for certification. [Translator recipe and dependencies](translator/README.md)

## Printed claim

For a probe execution from any initial state, choose natural cycles `r` and `n` with `r + 2 ≤ n`. In the modeled execution, `pending_persisted_q` is zero at `n` and one at `n+1`. With the inherited premises below, the latest record start `j` lies in `(r+2,n]` and follows acceptance of staging coordinate 127 at `j−1`. From `j` through `n`, the controller stays in a live write state with CLEAR low. The accepted writes in that interval equal the 18 address/data pairs of the record as held at `j`. An accepted write requires `private_kv_req_valid_o`, `private_kv_req_ready_i` and `private_kv_req_write_o` together. [Exact ACL2-printed theorem](evidence/kv-write-record.txt)

The nine K words come first, then the nine V words. The 19-bit address for word `w` in row `h` is `low19(227072 + 9 × (2 × (2048 × layer + low11(position)) + h) + w)`, with `h=0` for K and `h=1` for V. Each row has eight 256-bit words packing sixteen 16-bit coordinates apiece. The ninth word has the two exponent bytes in bits `[15:0]` and zeros above them. Both rows use the layer, position, exponents and pair store saved at the same `j`.

The proof inherits the following conditions from the checked control and payload books.

- The SVTV probe uses the behavioral `SYNTHESIS` deck. The modeled clocks toggle together and sample in the low phase. The high phase fixes `reset_n_i` high.
- `kv-reset-held-at` requires low sampled reset and zero internal overrides in cycles `r` through `r+2`, with enough input samples and two-valued CLEAR at `r`. The inherited unreset FIFO control, request words and app read slots are definite at `r+2`. `kv-payload-storage-definite-at` additionally requires definite payload banks, read and offer fields, request storage, and app address and data at `r+2`.
- `kv-environment-ok-from(r+2,n+1,envs,outs)` includes each transition through `n`. It requires the successor sample, zero internal overrides on both samples, locked clock and released successor reset. Reset, CLEAR, protocol input fields, endpoint controls and response data are definite. External faults, terminal signals and endpoint errors are low. Stage, commit and attention follow their protocol, responses have an outstanding read, typed metadata padding passes, and presented request descriptors are legal. The theorem places no schedule on endpoint ready or on when a record completes.

The 18-word theorem applies to this SVTV machine. The high phase leaves
`clear_i` unbound, which evaluates to X. Applying the theorem to ordinary UART
CLEAR traffic requires a clock model or a checked correspondence that accounts
for the registered CLEAR level and its asynchronous reset effects between
sampled edges. Board captures record the host commands and replies. In a
separate source-bound Tang UART/reader RTL replay with a modeled read service,
the buffered width adapter reset during the high half-cycle, before the next
command handshake.

The prefix theorem gives the accepted part of the same snapshot up to a live cycle, with length `kv-record-progress-at`. The interruption theorem places any CLEAR or cycle outside a live write at or before `n` before the start of the record credited at `n`. An already accepted prefix can exist after interruption. The theorem excludes crediting that interrupted interval as a completed record and gives no guarantee that memory rolls back. [Printed prefix theorem](evidence/kv-write-record-prefix.txt) · [Printed interruption theorem](evidence/kv-write-record-not-credited-when-interrupted.txt)

## Recorded positive and wrong-position cases

The checked scripted probe used layer 2 and starting position 0 for 644 cycles. The record started at 264, entered V at 449, and reported completion at the edge from 643 to 644. It counted 114 refused write cycles, with a longest stall of 40 cycles.

| Scripted case | Accepted K word addresses | Accepted V word addresses | Checked result |
| --- | --- | --- | --- |
| Stalled completion | 300800–300808 | 300809–300817 | All 18 words matched the single saved record in order. |
| Wrong position at the K-to-V transition | 300800–300808 | 300827–300835 | The data words and individual row conclusions still matched. The joined record conclusion failed, and the prover checked a counterexample to `REC-STEP-SVTV-THM`. The control's certified world omitted that theorem. |

The wrong-position control modifies one line in a separate copy of the proof controller. The archived readbacks are from the scripted probe, whose forward pass and endpoint are supplied by the fixture. They are separate from public token and board runs. [Exact control patch](proof/kv-write-record/mismatched-rows.patch) · [Every accepted address and 256-bit data word](evidence/RECORDED-RESULTS.json)

The author reported zero exits for certification and its build tool. ACL2 checked all 23 UNSAT proofs and evaluated four SAT assignments in the four-book run. An independent recipient loaded the same frozen certificates in two sessions, verified 11 local source/certificate/load-companion sets and 1,130 distinct system-book sources, and matched all 58 positive and eight wrong-position normalized events. The readback allows zero uncertified books and reports no skipped proofs or redefinition. The trust base includes ACL2, SBCL, the corrected VL/SV translator, the executed FGL and LRAT checking implementation, the 17 loaded trust tags and the imported certificate provenance. The source distribution carries the fingerprints of those records. [Author and recipient evidence](evidence/RECORDED-RESULTS.json)
