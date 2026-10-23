# Seeded-sampling evidence

The Tang Mega 138K non-Pro Dock passed one bounded UART trial on October 23, 2026 UTC
(October 22 in California). The trial used the frozen optional `seeded-sampling`
image, one prompt token `[378]`, temperatures `0`, `0.5`, `1`, and `2`, and public
128-bit seeds. See [the CLI guide](../../STOCHASTIC-GENERATION.md).

- [receipt.json](receipt.json) records artifact identities, loading scope, tested
  fixtures, counts, observations, and host command/reply measurements.
- [uart.jsonl](uart.jsonl) preserves all 164 transmitted frames and 162 received
  frames, plus operation durations and four bounded quiet intervals. It has 493
  records. Raw bytes and operation order are retained; times are rebased to the
  first send. Device paths, USB identifiers, absolute paths, and unrelated logs
  are omitted.
- [native.json](native.json) summarizes the frozen native build and pins its
  original receipt and report hashes. Vendor reports are not distributed.
- [historical-tests.json](historical-tests.json) summarizes earlier private
  component and model/UART simulations. Its checksums preserve provenance; the
  public evidence checker does not rerun those compiled campaigns.
- [app.json](app.json) records a separate 45-operation, 19-token host qualifier
  and the rendered Streamlit form driving the actual FPGA backend through
  AppTest. It pins the seven tested host source files and settings codec, and
  retains sanitized command/reply frames and literal output IDs.
- [app-stop.jsonl](app-stop.jsonl) retains 48 raw frames from a later AppTest
  Stop after generation had begun, followed by a greedy restart. Its separate
  summary is the `stopped_after_generation` block in `app.json`.

There were 107 returned tokens: three startup tokens, 40 acceptance tokens, and
64 tokens in the performance fixture. Exactly 46 were compared with model
known answers: the three startup tokens, all 40 acceptance tokens, and the
first three performance tokens. The remaining 61 performance tokens are recorded
observations. The checker pins their transcript bytes without promoting them
to independently checked model references.

Acceptance includes greedy behavior with zero and all-ones seeds, three-token
fixtures at all four temperatures, replay after CLEAR without SETTINGS,
selected changed-seed outputs, malformed CRC/invalid temperature/nonempty
SETTINGS rejection, and preserved continuation afterward. Sending SETTINGS
immediately after STEP produced no deferred settings reply and preserved the
continuation. Sending CLEAR immediately after STEP produced a CLEAR reply,
then the seeded fixture replayed. These are host/wire observations; internal
busy transitions and owned memory reads were not observed physically.

At temperature `1`, the 64-output fixture had a first STEP of 85.382 ms and
63 subsequent STEP command/reply durations totaling 6.097466498 seconds:
**10.332160090 tokens/s**. Durations include host evidence recording. This
single prompt does not establish full-context throughput or worst-case latency.

The local image was SHA-256 checked and the SRAM programmer reported successful
loading. Flash was not modified. This is not independent attestation of the
loaded FPGA configuration. Reset defaults were observed after that load,
before SETTINGS; the harness did not perform a separate logic reset test.

Native routing reports inference setup/hold slack of +0.092/+0.144 ns at 25 MHz,
with 145 setup/recovery and ten hold/removal violated endpoints in vendor DDR.
Complete timing qualification remains open. The original wire campaign supplies
no full-context, browser, formal proof, physical fault injection, or security
qualification. Positive-temperature selection uses a finite fixed-point CDF
and deterministic seeded PRNG, rather than independent physical randomness or
an exact floating-point softmax distribution.

The separate app rehearsal checked 19 expected outputs across all temperatures,
repeat with the same seed, greedy after sampling, a changed seed, and a greedy
restart after Stop. Two additional blank-seed runs displayed distinct automatic
seeds and returned two observed tokens; those two outputs were not compared
with model known answers. Stop occurred before prompt upload, returned a final
CLEAR acknowledgement, and released the connection. A new run then reproduced
`[200, 15, 103]`; Disconnect released the retained connection. The rehearsal
used Streamlit AppTest and the real
backend/UART, with no mocked UART or software inference. It did not start a
listening server or automate a real browser. Its 19 output checks and the
qualifier's separate 19 checks are additional to the original 46 wire checks.

A later supplement waited until an output was observed while the app reported
`generating`, then clicked Stop. The request uploaded its one prompt token and
returned 13 of the requested 64 outputs before stopping, acknowledging final
CLEAR and releasing the connection. Its first three outputs were the pinned
`[357, 3898, 104]` fixture; the other ten are recorded observations. A new run
explicitly selected greedy settings and returned `[200, 15, 103]`, then
Disconnect released the connection. These six expected-output checks are
separate from the earlier app/qualifier counts. The internal command edge at
the Stop click was not observed, so this does not establish an in-flight STEP
or memory-read cancellation test.

Run from the repository root, offline:

```sh
python -I -S -B tools/check_seeded_sampling.py
python -I -S -B tools/test_seeded_sampling.py
```

The checker independently verifies frame CRCs, exact SETTINGS seed/temperature
bytes, operation sequence, fixed token fixtures, replay and rejection outcomes,
duration arithmetic, all 87 distributed native inputs, the canonical 91-input
inventory, the original build identity, and the exact prebuilt image. The four
vendor inputs may be absent; if present, their hashes are checked. Mutation
tests exercise wrong tokens with valid CRCs, changed seeds/temperatures,
rejections, replay/order changes, truncated frames, timing changes, unsupported
claims, and altered image/source/build/evidence hashes. These checks validate
the published record and its artifact bindings; they do not run hardware.
