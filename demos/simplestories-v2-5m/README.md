# SimpleStories-V2-5M on Tang Mega


Run model-specific commands from this directory after cloning the repository:

```sh
cd inference-only/demos/simplestories-v2-5m
```

The model hardware, browser app, tools, proofs and evidence are all here. Shared release and cross-model benchmark checks remain at the repository root.
This demonstration runs a fixed W10/A16/KV16 approximation of
SimpleStories-V2-5M entirely on a Tang Mega 138K FPGA. The computer tokenizes
the prompt and displays generated text in the local web interface. The FPGA
owns model evaluation, attention state and next-token selection.

## Supplied configurations

| Configuration | Common cached generation | External K/V protection | Package status |
| --- | ---: | --- | --- |
| Authenticated weights | About **10.0 tokens/s** | None | Runnable release |
| K/V-protected | About **7.0 tokens/s** | Private expected SHA-256 digests | Runnable release |
| K/V protection + encrypted memory | About **6.0 tokens/s** | AES-SIV plus private expected digests | Runnable release; public demonstration keys |
| Seeded sampling at temperature 1 | About **9.9 tokens/s** | None | Runnable release |

Each row uses a one-token prompt and two 128-output trials: greedy selection
for the first three rows, temperature 1 and the recorded public seed for the
seeded row. The rate pools the 254 cached outputs between validated replies,
including host control and inter-command gaps. See the
[common protocol and exact results](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md).
For seeded sampling, the same trials give **9.928 cached host tokens/s** and
**9.942 command-only tokens/s**; those are distinct timing scopes.
[Seeded generation](STOCHASTIC-GENERATION.md) states its bounded temperature,
public-seed and numerical contract.

The three greedy images support 2,048 input positions plus one final output
slot, with browser limits of 2,048 prompt tokens, 128 new tokens and 2,049
combined. Long prompts take minutes to evaluate before the first output.
Stop drains an active STEP before CLEAR. The encrypted design encrypts both
weights and K/V and retains integrity/replay checks; its supplied keys are
public demonstration values, so they do not provide deployed confidentiality.

## Run the web demonstration

Read [PROGRAMMING.md](PROGRAMMING.md) completely for the supported board,
matching model/image installation and guarded backup/restoration. Then follow
the [host application guide](host-app/README.md) to qualify the loaded
image, launch the local web interface, connect USB and generate a story.
Changing designs requires the matching FPGA configuration; encrypted memory
also requires the matching ciphertext flash payload. The web app does not
reprogram the board or select a different model.

## Implementation and evidence

- [Hardware architecture](HARDWARE.md), [K/V protection](KV-PROTECTION.md) and
  [encrypted memory](ENCRYPTED-MEMORY.md).
- [Greedy qualification](GREEDY-QUALIFICATION.md), [seeded qualification](CURRENT-QUALIFICATION.md)
  and [validation and limits](VALIDATION.md).
- [Formal scope](FORMAL-STATUS.md): functional correctness and inference-only restrictions; [normal K/V return proof and replay](formal/kv-return/README.md).
- [Reproduction](REPRODUCE.md), [vendor setup](VENDOR-SETUP.md) and
  [source/license inventory](../../MANIFEST.json).

The model has six transformer layers, width 256, feed-forward width 682,
four query heads, two K/V heads and a 4,019-token lowercase WordPiece vocabulary.
Its fixed 7,265,984-byte payload has SHA-256
`cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`.
The FPGA exposes APPEND, STEP and CLEAR; seeded sampling additionally admits
bounded settings at an empty, idle tape. No command supplies tensor operands,
gradients, memory addresses or new accepted weights.

These are functional demonstrations under the frozen-circuit assumption.
All selected images have known negative vendor-DDR timing slack and are not
fully timing-closed; [validation](VALIDATION.md#recorded-negative-timing-slack)
lists each image's endpoint counts and worst slacks. Scoped RTL proofs and
finite model/board tests do not establish whole-machine numerical
refinement, independent loaded-image attestation or physical-security certification.
The [Qwen3-1.7B](../qwen3-1.7b/README.md) and [Qwen3-8B](../qwen3-8b/README.md)
demonstrations have separate implementation and evidence.

## Analysis

The [inference-only assessment](INFERENCE-ONLY.md) describes the access and
security assumptions. The [training-capacity assessment](TRAINING-CAPACITY.md)
and [shared methodology](../../docs/analysis/RESIDUAL-TRAINING-METHODOLOGY.md)
state the conditional arithmetic scenarios and their limits.

## Experimental signed updates

The separate [S-AWIC prototype](variants/signed-update/README.md) admits compatible
full model parameters signed by two of three fixed demonstration authorities. Its
[complete Tang integration](variants/signed-update/tang/README.md) connects
signature admission to flash boot, DDR readback and the UART token machine.
[Validation status](variants/signed-update/tang/VALIDATION.md) distinguishes
completed simulations, native build qualification and board evidence. This
experimental target has public demo signing material and no deliberate delay,
update cap or antirollback protection; it is separate from the measured
fixed-digest configurations above.

## Optional periodic reauthorization

The [S-AWIC with periodic reauthorization](variants/home-authorization/README.md) requires fresh approval at startup and periodically to keep running the authenticated model. Authorities can withdraw approval for old weights and distribute a signed replacement through the deployment host. It runs at 25 MHz and measures **~7.4 tokens/s** on the common paired benchmark, including renewal gaps. Its [installation](variants/home-authorization/INSTALL.md), [validation](variants/home-authorization/VALIDATION.md), [formal scope](variants/home-authorization/FORMAL-STATUS.md) and [reproduction](variants/home-authorization/REPRODUCE.md) are separate from the fixed-commitment and signed-update-only configurations.

The [physical replacement test](variants/home-authorization/VALIDATION.md#physical-model-replacement) exercises model-specific permission with two signed models, verifies their numerical outputs, and checks withdrawn-model rollback and replay rejection. The replacement is a controlled synthetic weight change.
