# TLM26 expert dispatch evidence

The local RTL replay matched **340 ordered expert W1 launches and 340 first W1 acceptance events**, including each event's history, token position, layer, rank, expert and weight address. All eight experts appeared in each of the five layers. Both histories produced their expected 12 tokens. The 24 outputs match the [physical record](../physical.json).

The trace contains one successful boot, two CLEAR markers and all 36 UART replies. An independent comparison checked all 719 lines in their full interleaved order. The simulator exited zero with empty stderr. [Trace](stdout.log), [result](RESULT.json), [input bindings](source-bindings.json), [native exit](native-exit.json), [independent review](independent-review.json).

Coverage includes the first W1 handshake and address for each selected expert in these two histories. The routing measurements come from RTL/DDR simulation. The physical board record supplies the matching external token responses. The recorded 44.912 seconds measures simulator runtime on the host.

The observer, stimulus, expected routes and trace retain their original bytes. JSON receipt extracts use repository-relative references and retain the original hashes and final evidence seal. [Reproduction](../../REPRODUCE.md#expert-dispatch-replay) describes the offline trace check and a fresh replay.
