# First on-chip K/V lifecycle assurance check

The current TLM26 cache is private on-chip scratch RAM. The first local check passed on both measured 12.5 MHz schedules, and the measured 50 MHz image contains the exact same eight runtime RTL modules as the overlapped 12.5 MHz design. This is a source trace and finite full-product regression, not an unbounded formal theorem.

## Storage and all access paths

`tlm_decoder.sv` declares one signed 32-bit `scratch[0:83967]` memory. Its sole physical writer is the clocked `if(swe) scratch[sadr] <= swdata`. The lower 2,048 words hold activations and temporary values. K/V occupies words **2,048 through 83,967**: five layers, 256 positions per layer, and 64 words per position (32 K and 32 V), totaling **320 KiB**.

| Access | Control/data path | Bound |
| --- | --- | --- |
| Current K/V generation | Authenticated matrix operations write working K/V at 192/224; rotary logic updates working K | Working activation region, below 2,048 |
| Persistent K write | `CACHE_1` schedules the sole RAM writer with `cachebase+i` | `2048 + layer*16384 + pos*64 + i`, `i=0..31` |
| Persistent V write | `CACHE_3` schedules that writer with `cachebase+32+i` | Same row, lanes 32..63 |
| K consumption | `SCORE_DOT_1`/FETCH/GOT reads the score operand | `2048 + layer*16384 + t*64 + (head/2)*8 + j` |
| V consumption | `HEAD_VALUE_1`/FETCH/GOT reads the value operand | Same address pattern with lane offset 32 |

Those two cache-copy states are the only writes into the persistent K/V region. Other scratch writers target the fixed activation ranges: embedding/ADD to X, matrix outputs to fixed working buffers, normalization to Z, rotary to Q/K, attention scores and softmax to S, attention output to H, router coefficients to A, activation to P, and mixture intermediates to Y/O. The output logits occupy 1424..1935. The source trace and runtime scoreboard distinguish consumed K/V reads from idle/dummy RAM reads.

Layer control visits 0..4; head control 0..7 and lane control 0..7. Both attention loops visit `t=0..pos`, including the current row written earlier in that same layer. `cmd_ready` admits work only at `pos<256`; COMMIT increments the position after completing the token. There is no wrap or external K/V spill in this design.

The runtime UART accepts APPEND, STEP and CLEAR with checked framing, CRC, opcode and operand bounds. APPEND selects an input token; STEP's operand must be zero and the decoder takes its token from `next_token`. Neither command exposes a scratch address, raw K/V value, program write or external-memory command. The decoder exposes only a private authenticated weight-read port. `tlm_product` connects that port through the page guard and SHA core to read-only runtime DDR requests; no K/V word is exported on that interface.

The board top multiplexes the boot loader and runtime product. Before completion, the loader stages model words in external DDR. After completion, writes are disabled and the product supplies weight reads. Those boot writes have no path into on-chip decoder scratch. The pin-facing DDR controller/transport returns weight data; pages must match the fixed private digest before a weight is consumed. The board top has no host-addressed K/V/DMA endpoint. Debug/configuration hardware and arbitrary physical modification are outside this RTL assurance scope.

## CLEAR and the next history

CLEAR resets `state`, `wreq`, `pos` and `next_token`; it does **not** scrub RAM. The separate RAM-write process can still commit an already registered old write on the CLEAR edge. That write remains outside the new valid history. The UART cancels the old reply and withholds CLEAR acknowledgment until an accepted external weight response has drained; the page guard invalidates its good flag and uses DRAIN for a pending response. New work is admitted after this acknowledgment.

For a new command at position zero, each layer computes and writes its entire new row before the attention readers visit that layer's row zero. Later commands add rows in order. Old rows beyond the new live position remain physically present but the attention loops do not select them. A direct STEP immediately after CLEAR is also legal: `next_token` has become zero, so that command processes token zero and writes a new row zero. The normal BOS path first APPENDs token one.

## Regression and reproducibility

The unchanged full UART product was compiled separately for the original and overlapped schedules, using their actual 12.5 MHz UART and hold parameters. External weight-memory readiness/returns are modeled with ordered latency and stalls; actual weight bytes, page authentication, SHA, arithmetic, UART framing and CLEAR logic execute. The harness never assigns production state or supplies expected outputs to the DUT.

For each schedule, the test compares a clean run against two distinct prior APPEND histories (`1,403,407,261` and `1,291,376,280,294`) and a cancelled STEP that had already written K/V. It repeats all four cases both with BOS APPEND and with a direct STEP after CLEAR. All **eight cases per schedule** pass. The two schedules' transcripts agree exactly.

An observation-only scoreboard marks actual persistent K/V writes by CLEAR epoch and checks every score/value consumption against those marks and the live layer/position/lane bounds. It checked **44,032 consumed K/V reads and 10,368 K/V writes per schedule**. For the normal first new STEP it observes 1,280 K/V reads and 320 writes; the direct empty-history STEP uses 640 reads and 320 writes. Active K/V values, ordered K/V-consumption digests, verified weight-word digests, matrix-term/row digests and the next predicted token match clean controls. Full-cache digests differ after the prior histories, confirming that the test exercises retained stale RAM rather than an erased cache.

`tests/KV-REVIEW.json` records the exact runtime source and harness hashes, compile arguments and all eight outcomes. `tests/kv_isolation.cpp` is the exact compiled harness. To reproduce, place those eight pinned production RTL files and the harness in a build directory without spaces, run the recorded Verilator arguments, then run `obj/Vtlm_product` with the verified `model.bin`, `page_digest.hex`, `exp.hex`, `cos.hex` and `sin.hex` in its working directory. Repeat with the original and overlapped decoder; no vendor EDA, physical device or download is invoked by the harness.

This result covers these histories, normal weights, modeled memory responses and two cancellation trajectories. It does not exhaust every token, all 256 positions, every fault/interleaving, arbitrary SRAM corruption or physical DDR/CDC/PVT behavior. CLEAR provides logical history invalidation; it does not provide physical zeroization. The 50 MHz source identity extends the logic check to that image; the board speed run is separate evidence. No solver or unbounded noninterference proof is claimed.

## If longer histories require external K/V

The existing authenticated-block design offers reusable buffering, SHA/framing, backpressure, verification-before-release and CLEAR/drain machinery. Its immutable private digest ROM is appropriate for fixed weights, and cannot directly authenticate dynamically generated K/V.

A future external K/V engine would need a trusted integrity root or keyed MAC, with tags bound to context/epoch, layer, position, block index, length and freshness/version. Only decoder-generated K/V may create or update that trusted state. External data must remain untrusted until the entire block and tag verify in private storage; data/tag updates must commit together. CLEAR must invalidate the epoch, cancel or drain in-flight traffic and prevent an old response or replayed block from joining the next history. Epoch/version wrap needs an explicit rule. The host must not supply a trusted digest, valid flag or unrestricted authenticated write capability. These are design requirements for a future implementation, not protections already implemented for external K/V here.
