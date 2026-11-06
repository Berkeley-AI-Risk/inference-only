# Reproduce Qwen3 8B software campaigns

The additive [campaign runner](run_campaign.py) regenerates selected recorded
continuations or accepts a custom token-ID prompt using the unchanged fixed
numerical engine. It does not download a model, contact AWS or access an FPGA.
The original [three-token runner](run_reference.py) and its recorded evidence
remain unchanged.

Run the commands from `demos/qwen3-8b`. Planning, saved-record checks and unit
tests require only Python 3.12's standard library. Actual inference requires
the dependencies and verified exported model from
[model preparation](../README.md#prepare-the-fixed-model).

## Select a workload without running it

```sh
python3.12 -I -S -B reference/run_campaign.py --list
python3.12 -I -S -B reference/run_campaign.py --plan --campaign suite --case chat-fpga
python3.12 -I -S -B reference/run_campaign.py --plan --campaign all
```

Named campaigns use prompt and expected output IDs from
[measurements.json](../measurements.json). `all` selects the longest recorded
continuation for each distinct prompt: three cases and 197 outputs. It checks
that repeated deterministic prefixes agree before selecting them. This is a
workload selection, not a claim of complete context coverage.

`--steps N` selects a shorter recorded prefix; it cannot extend beyond the
available expected outputs. A custom `--prompt` requires an explicit positive
`--steps` and must fit the 32,768-token tape, including generated outputs.

## Run a fresh CPU case

Start with the short smoke case. The CPU reference expands projection weights
into FP32 packs, so even a short test needs tens of gigabytes of RAM. The runner
does not itself enforce a memory cap; coordinate other large jobs and use an
appropriate local supervisor. It performs no automatic retry.

```sh
.venv-model/bin/python -I -B reference/run_campaign.py \
  --campaign smoke --case first-three --repeat 2 \
  --model local/model --threads 8 --output local/cpu-smoke
```

Choose a fresh output directory whose parent already exists. Every case starts
with CLEAR, appends its prompt, and generates the selected output count; a final
CLEAR is required for successful completion. Deliberate `--repeat` runs are
limited to eight and are not retries after a failure.

The result directory contains `STARTED.json` and either `FINISHED.json` or
`FAILED.json`. Failures preserve partial actual outputs and any cleanup error.
A killed process may leave only its start record; that is not completion.
Records bind the numerical sources, original reference receipt, measurements,
runner and fixed model identity. Keep new results outside the reviewed release
inventory until they have been checked.

For an arbitrary token-ID prompt:

```sh
.venv-model/bin/python -I -B reference/run_campaign.py \
  --prompt 9707,11 --steps 4 --model local/model --threads 8 \
  --output local/custom-continuation
```

Custom generation reports `passed: null`: successful execution is not a
comparison with an independently expected answer. No EOS stopping is added;
the fixed token machine treats EOS as an ordinary token.

Check an actual saved result without re-running inference:

```sh
python3.12 -I -S -B reference/run_campaign.py \
  --check-record local/cpu-smoke/FINISHED.json
```

This checks record completeness, source bindings and the selected expected
tokens. It does not independently attest how a saved record was produced.

## Compare a separately captured hardware run

Hardware use is separate: follow [INSTALL.md](../INSTALL.md), obtain the
necessary resource/slot approval, and preserve the actual loaded-image/model
identity and client exit status. This section does not provision or authorize
a rental or reconfiguration.

The unchanged installation client accepts a prompt and output count; `generate`
does not stop at EOS. For the smoke workload, capture its JSONL directly and
preserve the real exit status before running another command:

```sh
sudo host/qwen_host --slot 0 generate 9707 3 > local/fpga-generation.jsonl
qwen_client_status=$?
python3.12 -I -S -B tools/check_token_capture.py \
  --capture local/fpga-generation.jsonl \
  --reference local/cpu-smoke/FINISHED.json --case-index 0 \
  --child-exit-code "$qwen_client_status" --output local/capture-comparison.json
```

The offline checker requires complete ordered matching token rows and valid
timestamps. It distinguishes reply-to-reply cached throughput from the sum of
command times. A single output has no cached-rate estimate. Nonzero client
exit, missing/extra rows, token mismatches and invalid timing fail the check.

The exit status is supplied by the operator, not independently attested.
Matching captured tokens do not establish loaded-image identity, clock
frequency, timing closure, physical security or a whole-model theorem. Retain
those separately scoped receipts; do not substitute software timings for an
FPGA benchmark.

## Run the small regression tests

```sh
python3.12 -I -S -B tools/test_reference_campaign.py
```

These exercise selection, limits, CLEAR/replay sequencing, failure handling,
saved-record checks and capture parsing using test doubles and saved rows.
They do not execute the full 8B model or qualify hardware.
