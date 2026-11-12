# TLM26 expert dispatch evidence

The local RTL replay matched **340 ordered expert W1 launches and 340 first W1 acceptance events**, including each event's history, token position, layer, rank, expert and weight address. All eight experts appeared in each of the five layers. Both histories produced their expected 12 tokens; the 24 outputs match the [physical record](../physical.json).

The [trace](stdout.log) contains one successful boot, two CLEAR markers and all 36 UART replies. An independent comparison checked all 719 lines in their full interleaved order. The [result](RESULT.json), [input bindings](source-bindings.json), [native exit](native-exit.json) and [independent review](independent-review.json) preserve the identities and scope. The recorded simulator exited zero with empty stderr. Its 44.912-second host runtime is not hardware throughput.

These are observations for two histories in an RTL/DDR simulation. They check each selected expert's first W1 handshake and address, not every later weight access. The board's internal expert routing was not directly observed. This result does not establish arbitrary-history correctness, a formal theorem or physical timing closure.

The observer, stimulus, expected routes and trace retain their original bytes. JSON receipt extracts replace host-specific paths with repository-relative references and retain the original hashes and final evidence seal. No recorded binary or model image is distributed here. See [reproduction](../../REPRODUCE.md#expert-dispatch-replay) for the offline trace check and a fresh replay.
