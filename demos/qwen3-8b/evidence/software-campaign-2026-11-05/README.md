# Complete recorded Qwen3 8B CPU campaign

The unchanged fixed-model CPU engine reproduced all 197 expected outputs from
the three distinct prompts in the recorded hardware suite. The
[result](result.json) preserves the actual software terminal record, with
numerical-source, runner, measurement and fixed-model identities. It contains
CPU timings, not a new FPGA benchmark.

| Recorded case | Prompt tokens | Matching outputs | Software generation seconds |
| --- | ---: | ---: | ---: |
| Single token and 128 outputs | 1 | 128 | 143.530 |
| FPGA chat | 23 | 53 | 79.151 |
| 512 token prefill | 512 | 16 | 688.469 |

The serial run used PyTorch 2.10.0, CPU execution and eight threads. Total
software time, including model checking and loading, was 930.828 seconds.
The supervisor observed an actual zero child exit, no resource stop or
observation error, normal kernel memory pressure, and successful final CLEAR.
Sampled peaks were 42,421,583,872 bytes RSS and 33,568,192,968 bytes physical
footprint. It made no automatic retry and used no unused-RAM cutoff.
Host/process monitoring records remain private; the JSON is not an independent
attestation of its own execution.

## Replay the saved result check

From `demos/qwen3-8b`, with Python 3.12:

```sh
python3.12 -I -S -B reference/run_campaign.py \
  --check-record evidence/software-campaign-2026-11-05/result.json
```

This verifies source identities, complete ordered cases, the recorded
expected output IDs and final CLEAR fields without executing the model.
For a fresh full CPU run, follow the
[campaign instructions](../../reference/CAMPAIGNS.md) and select
`--campaign all --repeat 1`. Use a fresh output directory and coordinate
memory use: the CPU engine packs projection weights into FP32 and needs tens
of gigabytes even for a short prompt.

## Scope

This is finite complete-model CPU execution on the three recorded workloads.
It is not full-context coverage, a new RTL/tensor-boundary comparison, a
whole-model theorem, an independent upstream-model equivalence result, or FPGA
timing, loaded-image, K/V-integrity or physical-security qualification. The
existing [hardware measurements](../../measurements.json) remain unchanged.
