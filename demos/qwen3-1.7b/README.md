# Qwen3-1.7B on AWS F2

[Project overview](../../README.md) · [SimpleStories-V2-5M on Tang Mega](../simplestories-v2-5m/README.md)

**A fixed numerical version of Qwen3-1.7B runs on one physical AWS F2 FPGA
at 8.964–9.001 sustained cached tokens/s in the tested short-prompt workloads.**
The FPGA performs inference; the host uploads the fixed model, sends token
commands and records the replies. This is a billion-parameter demonstration
of the same authenticated-weight, fixed-inference approach as Tang Mega.

**Run it yourself:** the [installation guide](INSTALL.md) uses the tested,
publicly loadable AWS FPGA image. This package includes the frozen hardware
source, model reconstruction tools, numerical reference, host client, browser
app and implementation reports. You supply an AWS F2 rental; no FPGA source
rebuild is needed to use the prebuilt image.

## The fixed model and circuit

The model is **Qwen/Qwen3-1.7B**, pinned at checkpoint revision
`70d244cc86ccca08cf5af4e1e306ecf908b1ad5e`. It has 1,720,574,976 unique
parameters, 28 transformer layers, hidden size 2,048, 16 query heads,
eight K/V heads and head dimension 128. Input embeddings and the output
weight matrix are tied.

The implemented numerical model uses quantized weights and fixed arithmetic
and rounding rules, with deterministic greedy token selection. It is not a
claim of bit-for-bit agreement with the upstream floating-point implementation.
Hardware outputs below were compared with the project's matching numerical
reference, not a generic Qwen GPU run.

The tested inference core runs at **100 MHz**. Weights and the attention
cache are stored in HBM; private on-chip buffers serve the arithmetic.
A fixed hardware schedule runs all 28 layers. The host does not supply
operator programs, matrix dimensions or intermediate tensor addresses.

Startup accepts the fixed 2,354,380,800-byte model image. The host checks its
size and hash, and hardware independently checks the received image.
Runtime hardware also authenticates weight pages before consuming the checked
on-chip copies, so acceptance does not depend solely on a startup check.
The fixed model-image SHA-256 is:

```text
90d82ed9b90c58607f924190be0c15f18b70d849c536a2ccbddd259858979cd1
```

There is no secret authentication key or manufacturer model-update command.
The current circuit **does not authenticate K/V or encrypt weights**.
Those are possible later variants, not features credited to these results.

## Interface and inference-only scope

The inference operations are `APPEND(token)`, `STEP` and `CLEAR`.
An ordinary generation request clears the tape, appends the prompt and performs
the requested number of STEPs. No application command submits arbitrary
matrix operands, reads intermediate tensors or replaces the accepted weights.

The platform has other facilities that must not be confused with those three
inference operations:

- A restricted startup upload path loads the fixed model; it is not a
  general-purpose HBM read/write interface.
- Status registers report readiness, received-byte count and errors.
- The tested engineering image has a 16-bit diagnostic status readout for
  attention-control states and valid flags. It is not a matrix-result port,
  but it is observable information beyond returned tokens.
- AWS manages FPGA configuration, clocks and resets. The general-purpose
  cloud host and AWS management plane are not claimed to be inference-only.

We assess the configured inference circuit under the **frozen-configuration
or eventual-ASIC assumption**, not the whole reprogrammable cloud platform.
A production design would need its own evaluation of external-memory,
diagnostic, test/debug and physical-tampering paths. Unaudited physical
access to HBM is not ruled out by a restricted host command interface.

The [shared conceptual overview](../../README.md#in-what-sense-is-it-inference-only)
and [Tang Mega assessment](../../INFERENCE-ONLY.md) explain the distinction
between an architectural demonstration and a certified residual training
fraction. Tang Mega's scoped proofs and capacity estimates **do not transfer
automatically to Qwen**. No whole-machine refinement proof, physical-attack
resistance certification or measured training-capacity bound is claimed here.

## Measured generation speed

The following are two runs of the same three 128-output workloads on the
same loaded image. Each cached rate uses the **127 intervals after the first
returned token**, not the first STEP. The first-token column is from the
second run.

| Workload | Prompt tokens | Run 1, cached tokens/s | Run 2, cached tokens/s | Time to first token |
| --- | ---: | ---: | ---: | ---: |
| Story continuation | 4 | 8.9967 | 9.0012 | 0.389 s |
| Geography completion | 5 | 9.0004 | 9.0006 | 0.483 s |
| Chat-formatted greeting | 15 | 8.9649 | 8.9639 | 1.420 s |

The story prompt is “Once upon a time”; the geography prompt is “The capital
of France is”. The greeting uses “Say hello.” with the pinned single-user,
non-thinking chat template. All prompt and expected output token IDs are
included in [the measurement record](measurements.json).

Longer prompts were tested separately, with **16 outputs per case**:

| Prompt tokens | Generated tokens | Time to first token | Cached tokens/s |
| ---: | ---: | ---: | ---: |
| 64 | 16 | 6.058 s | 8.996 |
| 256 | 16 | 24.960 s | 8.516 |
| 512 | 16 | 51.964 s | 7.992 |

The 16-output cases contain only 15 cached intervals each. They characterize
these longer-prompt workloads, not a sustained 128-output run at those
contexts. Growing context increases attention work, so neither 9 tokens/s
nor the short-prompt latency should be assumed for arbitrary prompts.

Timing is observed by the host. Time to first token includes prompt APPENDs
and the first STEP, but excludes FPGA configuration, model upload, the preceding
CLEAR and text tokenization. Cached speed is
`(outputs - 1) / (last reply time - first reply time)`, using the client's
generation clock. It includes command/communication and intervening output
overhead, not just arithmetic cycles. Model loading is a separate startup cost.

## Validation and evidence boundaries

Five completed hardware campaigns contain **852 matching output-token
comparisons**: 3 in the initial smoke test, 15 in the expanded smoke suite,
390 in each repeated sustained suite, and 54 in the longer-prompt suite.
This count includes repeated workloads and CLEAR/replay checks; it is not
852 independent prompts. Every campaign ended with a successful CLEAR.

The longest measured prompt here has **512 tokens followed by 16 outputs**.
The design's 32,768-token tape budget is not a hardware-qualified context
claim: full-context numerical execution has not been demonstrated by these
tests. Output agreement on selected cases is also not a model-quality
benchmark or a proof of correctness for every prompt.

The routed implementation's saved report shows setup slack +0.011 ns,
hold slack +0.007 ns and no failing timing endpoints or routing errors under
its declared constraints. That does not resolve every CDC/reset assumption,
establish production signoff or certify the AWS platform against physical
attacks. The [hardware guide](HARDWARE.md) links the complete implementation
reports, source identities, build instructions and retained warnings.

[measurements.json](measurements.json) preserves the original token/timing
stdout for all 21 tested cases, expected token IDs and hashes binding the
records to the tested image package, model and client. Private account,
instance and image identifiers, local paths and management logs are excluded.
Hashes of those omitted envelopes identify provenance; they do not make
omitted records publicly inspectable. The public deployment identifier is
documented separately in [deployment.json](deployment.json).

To verify the packaged replies and recompute the tables, run from the
repository root:

```sh
python3 -I -S -B tools/check_qwen_measurements.py
python3 -I -S -B tools/check_qwen_package.py
python3 -I -S -B -m unittest discover -s tools -p 'test_qwen_measurements.py' -v
```

These commands need Python 3.11 or later and only the standard library. They do not rent
hardware, contact AWS or run inference. They check the saved replies against
the packaged expected IDs. The separately runnable
[numerical reference](reference/README.md) regenerates those IDs from the
accepted model image; its CPU and full distinct-prompt checks are also included.

## Availability and reproduction

**Do not use the Tang Mega programming instructions or bitstreams for this
experiment.** Use the separate [installation guide](INSTALL.md),
[browser instructions](BROWSER.md), [source-build guide](HARDWARE.md),
[numerical reference](reference/README.md) and [dependency notices](NOTICES.md).
The [detailed hardware diagram](HARDWARE.md#detailed-hardware-diagram) shows the
controllers, memory paths and arithmetic units alongside the SimpleStories design.
The [installation receipt](evidence/installation.json) records a fresh slot
reload, upload of the model rebuilt from this package, the three-token self-test
and a separate 390-token check using the recipient-built host client. These
checks used the image owner's existing F2 environment; they are not a second
account's installation test or a fresh operating-system setup.

The run sequence is: provision an appropriate F2 environment, load the matching
FPGA configuration, upload the checked model, pass a known-answer test, then
generate tokens. The tools do not silently provision paid resources or
substitute a host model. AWS access and any rental remain the operator's
responsibility. A source rebuild is a separate engineering workflow from
running the tested prebuilt image.

Further optimization targets faster generation without weakening consumed-weight
authentication or adding general arithmetic commands. **Ten tokens/s remains
a target, not a measured result.** K/V integrity and weight encryption are
also future work for this model, not features of the released image.
