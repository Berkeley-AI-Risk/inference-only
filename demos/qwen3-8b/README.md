# Qwen3-8B on AWS F2

[Installation](INSTALL.md) · [Hardware and source build](HARDWARE.md) · [Recorded evidence](measurements.json)

A fixed numerical version of **Qwen3-8B runs on one physical AWS F2 FPGA at
about 1.1 sustained cached tokens/s** in the measured short-prompt workload.
The FPGA performs inference; the host loads the fixed model and exchanges
token commands. Work on a faster implementation is ongoing. No projected
speedup is included in the measurements below.

**Package status: runnable prototype; speed optimization in progress.** The
tested AWS FPGA image is publicly loadable. The package includes its exact
hardware sources, host client, fixed-model preparation tools, numerical
reference and implementation reports. Follow [INSTALL.md](INSTALL.md) to run
it on an F2 instance in your own AWS account. This package uses a token-ID
command-line client; an 8B browser interface is not yet included.

## What is fixed

The source model is `Qwen/Qwen3-8B`, checkpoint revision
`b968826d9c46dd6066d109eabc6255188de91218`: 36 transformer layers, hidden width
4,096, 32 query heads, eight K/V heads and head dimension 128. Embedding and
output matrices are not tied. The numerical implementation uses signed 8-bit
projection weights with per-row FP32 scales, BF16 embeddings, specified
integer/FP32/BF16 arithmetic and rounding, and greedy token selection.
It is not bit-for-bit identical to the upstream floating-point model.

The inference circuit runs at 100 MHz and its HBM interface at 125 MHz.
Weights and K/V are stored in HBM. Hardware owns the inference schedule and
intermediate addresses. Startup checks the complete fixed model image;
runtime page authentication checks weights before using their private on-chip
copies. Authentication is not bypassed to obtain these measurements.

The accepted model image is 8,828,026,880 bytes, with SHA-256:

```text
a1e8a91912dfa79fb602601e256a4a07da64c57dda146529c08886532d42f833
```

There is no secret authentication key or manufacturer model-update command.
This version does not authenticate K/V or encrypt weights.

## Inference-only scope

The application operations are `APPEND(token)`, `STEP` and `CLEAR`.
The application does not submit matrix operands, operator programs, tensor
addresses or replacement model weights. A restricted startup loader, status
registers and an attention-control diagnostic are separate engineering
facilities, not additional inference operations.

The assessment assumes a frozen FPGA configuration or an eventual fixed ASIC.
It does not call the AWS host or reprogrammable management platform
inference-only. External-memory access, diagnostic/test interfaces and physical
tampering need their own assessment. No whole-machine formal refinement proof,
physical-tampering certification or measured residual training fraction is
claimed for this 8B implementation.

## Measured performance

| Prompt tokens | Generated tokens | Time to first token | Cached tokens/s |
| ---: | ---: | ---: | ---: |
| 1 | 128 | 0.89 s | 1.1 |
| 23, chat-formatted | 53 | 18.84 s | 1.1 |
| 512 | 16 | 428.16 s | 1.1 |

Cached speed uses the intervals after the first returned token, including
host command and inter-reply overhead. The 16-output case contains only 15
cached intervals; it is not a sustained long-context benchmark. First-token
latency includes prompt APPENDs and the first STEP, but excludes configuration,
model upload, the preceding CLEAR and tokenization. Upload and authentication
of the complete model is a separate startup operation, taking about eight to
nine minutes in the recorded runs.

The [measurement record](measurements.json) includes all prompt IDs, expected
outputs and captured timing rows. Recompute the results without an FPGA:

```sh
python3.12 tools/check_measurements.py
```

The hardware tests contain 212 matching output checks: 197 outputs in the main
cases and 15 smoke/replay checks. These include repeated prefixes, not 212
independent prompts. The longest tested tape has 528 tokens. The circuit's
32,768-token tape capacity is not a hardware-qualified full-context claim.
These tests are not a broad language-quality benchmark.

The [installation rehearsal](evidence/installation.json) separately records
22 matching outputs from a freshly compiled client and a complete model
upload, including the built-in self-test and CLEAR/replay. It used the image
owner's account with the vendor SDK already installed. Public load permission
was checked through AWS; a second-account installation was not tested.

## Prepare the fixed model

The model is reconstructed locally rather than stored as an 8.8 GB Git file.
From this directory, with enough space for the upstream checkpoint, exported
image and dependencies (at least 35 GB is advisable):

```sh
python3.12 -m venv .venv-model
.venv-model/bin/python -m pip install -r model/requirements.txt
.venv-model/bin/python tools/prepare_model.py \
  --source local/upstream --download --output local/model --threads 8
```

Omit `--download` when the pinned upstream files are already present. The
exporter verifies them and rejects a result whose hash differs from the
fixed model accepted by the measured FPGA. This is an offline preparation
tool, not a programmable model loader on the chip.

To check the included software reference, run:

```sh
.venv-model/bin/python reference/run_reference.py --model local/model --threads 8
```

This regenerates a three-token continuation and repeats it after CLEAR. The
[recorded reference check](evidence/reference.json) identifies its sources;
it is a CPU numerical check. To inspect all packaged source/report and
installation bindings without AWS or a model download, run:

```sh
python3.12 tools/check_package.py
```
