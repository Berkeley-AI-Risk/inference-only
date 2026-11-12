# Common FPGA generation speed benchmark

To enter the headline speed comparison, a design must use one input token, 128 generated outputs and two repetitions. The seeded-sampling row uses temperature 1 with a fixed public seed; the other measured rows use greedy decoding. Its cached rate includes the host control loop and gaps between token replies. The [overview table](../../README.md#the-demonstrated-designs-and-measurements) contains a rate only when both complete trials satisfy this protocol.

## Workload and execution

Run one sequence at a time on the FPGA's local control host, with no competing workload on that FPGA. Use the qualified image and model identified in the record. Record their hashes, clock, host client/source identity and collection conditions. A different image or clock requires its own measurements.

Use input token `[378]` for SimpleStories and `[9707]` for Qwen. These are model-native token IDs; the common workload fixes token counts, not text across different tokenizers. Before each measured trial, issue CLEAR, verify success and append the single input token. Produce exactly 128 outputs with true feedback. Continue through end markers. Use the decoding mode declared by the selected row. The seeded-sampling row uses temperature 1 and public seed `0x99aabbccddeeff001122334455667788`; validate its outputs against the corresponding seeded numerical reference. Other rows use greedy decoding.

Run two complete repetitions with the same image, model, clock, host software, prompt and decoding mode. Repeated sampled trials also use the same declared seed. Check all 128 returned IDs against the applicable numerical reference and retain the raw capture. A short CLEAR/replay smoke test cannot replace a full repetition. Preserve failures; never replace a failed trial with a successful retry without a separate record.

The physical run requires exclusive ownership of the FPGA and its token tape. Finish active experiments before CLEAR, image changes or model loading. Collection does not authorize a rental, flash rewrite or interruption of another owner's experiment.

## Primary timing

Use a monotonic clock on the local control host. For each output, record when the validated token is returned to the generation loop. This boundary is named `generation_loop_validated_reply`. Record all 128 timestamps, including output 1, and all individual STEP durations.

For trial `j`, let `t_j[k]` be the timestamp for returned output `k`, counting from one:

```text
cached_outputs_per_trial = 127
duration_j = t_j[128] - t_j[1]
trial_rate_j = 127 / duration_j

headline_rate = 254 / (duration_1 + duration_2)
```

The headline includes the host work and gaps between returned tokens. It excludes connection setup, CLEAR, prompt upload and production of the first output. It is a host-observed cached generation rate, not an FPGA arithmetic-only or peak rate. Pool token counts and durations; do not take the arithmetic mean of trial rates or select the fastest repetition.

Record first-STEP request/reply latency separately. It includes evaluation of the one-token prompt and production of the first output; prompt-upload time is a separate measurement.

Raw frame-receipt timestamps, operation-log timestamps and generation-loop return timestamps are distinct observations. A record must identify its boundary. Do not substitute an earlier RX timestamp for a caller timestamp or derive host-loop duration by summing command durations. Instrument or collect the missing timestamps if the required observation is unavailable.

## Secondary diagnostics

A command-only diagnostic may use:

```text
command_only_rate = 254 / sum(STEP durations for outputs 2..128 in both trials)
```

This excludes inter-command gaps and must be labeled separately. Browser streaming, first-output latency, other temperatures, longer prompts and fixed-context decode are separate panels. The headline comparison uses the primary formula exclusively.

## Evidence and checking

[Selection](../../benchmarks/fpga-speed/selection.json) pins the input records and selected image identities. [Computed results](../../benchmarks/fpga-speed/results.json) record trial counts, wall durations, primary rates and command-only diagnostics. A dash in the overview means that a complete paired record is unavailable; individual model guides can report other explicitly labeled validation workloads.

The overview features the K/V-protected SimpleStories F-AWIC. Its expanded
comparison includes the plain-cache baseline and the other SimpleStories
configurations, all calculated from their selected archived captures.
TLM26 appears with a pending common rate. Its [24-output board validation](../../demos/tlm26-moe/VALIDATION.md)
uses two five-token prompts and a deliberate 20 ms first-return hold; its median
STEP latency cannot substitute for this benchmark. The selection binds that
record's image and configured clock without treating it as a complete trial.

From the repository root, using Python's standard library:

```sh
python3 -I -S -B tools/fpga_speed_benchmark.py --check
python3 -I -S -B tools/fpga_speed_benchmark.py --table
python3 -I -S -B -m unittest discover -s tools -p 'test_fpga_speed_benchmark.py' -v
```

The checker rejects changed source identities, wrong prompt/output counts, undeclared decoding modes or temperatures, mixed modes or seeds across repetitions, early stopping, missing repeats, reused captures, nonmonotonic timestamps and mismatched boundaries. For seeded sampling it checks the recorded settings, CLEAR, prompt and returned token frames against the fixed-seed reference. It recomputes the table from recorded data without hardware access or a fresh numerical-model run.

The selection protocol is `one-token-128-host-v2`, with the decoding profile declared per row. For a new greedy capture, use schema `fpga-common-speed-capture-v1`, protocol `greedy-one-token-128-host-v1`, an explicit identity block and `timestamp_boundary`. Each named case records `prompt_tokens`, `generated_tokens`, `expected_tokens`, `reply_elapsed_seconds`, the 127 `cached_command_seconds`, `first_step_seconds`, `raw_capture_sha256`, `decoding`, `temperature`, `clear_before`, `stop_at_eos` and `feedback_dependent`. Preserve the independent reference provenance with the raw capture. Select only reviewed, hash-bound records.

Different models, numerical functions and hardware perform different work per token. The common protocol aligns the workload geometry and timing definition; it does not establish model-quality equivalence or a licensed inference rating. [H100 reference measurements](H100-BENCHMARK.md) have their own batch and timing boundaries and must be identified separately in residual training analysis.

## Signed-update SimpleStories

The S-AWIC row uses the signed base model, the same `[378]` prompt and greedy decoding as the fixed-commitment baseline. Its two complete 128-output trials use the source-bound S-AWIC bitstream at 25 MHz. The independent integer reference reconstructs the model from its physical image bytes. All 256 returned IDs match it.

The [raw capture and reference](../../demos/simplestories-v2-5m/variants/signed-update/tang/evidence/repair-board-2026-11-05/FINISHED.json) and [offline evidence review](../../demos/simplestories-v2-5m/variants/signed-update/tang/evidence/repair-board-2026-11-05/RAW-REVIEW.json) retain the validated-return timestamps, all 262 command/reply transactions, and source/image identities. The common checker replays those frame and timing associations before admitting the row. See the [collector and reproduction instructions](../../demos/simplestories-v2-5m/variants/signed-update/tang/REPRODUCE.md#common-speed-benchmark).

## Signed updates with periodic reauthorization

The [periodic-reauthorization S-AWIC](../../demos/simplestories-v2-5m/variants/home-authorization/README.md)
uses `[378]`, 128 greedy outputs and two repetitions. The selected repaired
image `92b334d6f160...` measures **~7.6 tokens/s** at 25 MHz in its
[paired capture](../../demos/simplestories-v2-5m/variants/home-authorization/evidence/repair-board-2026-11-05/COMMON-SPEED.json),
including renewal and host handover gaps. All 256 outputs match the independent
integer reference.

The offline auditor checks raw frames, token timing, real approval signatures
and restoration; the common table checker includes those checks. At 25 MHz,
the permission period is nominally ten seconds, renewal starts five seconds
before expiry, and the response deadline is four seconds. These authorize
continued inference; they do not impose a weight-update delay.

The [v9 capture](../../demos/simplestories-v2-5m/variants/home-authorization/evidence/board-25mhz-v9/COMMON-SPEED.json)
records a separate ~7.4 tokens/s observation for its identified image. The
[selection record](../../benchmarks/fpga-speed/selection.json) identifies the
records admitted to each headline row.
