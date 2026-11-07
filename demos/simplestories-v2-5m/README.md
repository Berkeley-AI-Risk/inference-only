# SimpleStories-V2-5M on Tang Mega


Run model-specific commands from this directory after cloning the repository:

```sh
cd inference-only/demos/simplestories-v2-5m
```

The Tang Mega runs the model's fixed architecture, quantized arithmetic and
next-token selection. The host computer tokenizes prompts and displays outputs;
the FPGA owns model evaluation and attention state. The implemented numerical
contract is W10/A16/KV16 BFP-v5.

Four **Fixed-Commitment AWICs (F-AWICs)** pin the accepted model commitment.
Two **Signed-Update AWICs (S-AWICs)** admit compatible signed model packages;
one also requires periodic permission to keep running the admitted weights.
The model hardware, host tools, proofs and evidence are in this directory.
Shared release and cross-model benchmark checks are at the repository root.

## Supplied configurations

| Configuration | Common cached generation | External K/V protection | Package status |
| --- | ---: | --- | --- |
| F-AWIC baseline | ~**10.0 tokens/s** | None | Runnable release |
| F-AWIC with K/V protection | ~**7.0 tokens/s** | Private expected SHA-256 digests and CLEAR epoch | Runnable release |
| F-AWIC with K/V protection + encrypted memory | ~**6.0 tokens/s** | AES-SIV plus private expected digests | Runnable release; public demonstration keys |
| F-AWIC with seeded sampling at temperature 1 | ~**9.9 tokens/s** | None | Runnable release |
| [S-AWIC](variants/signed-update/tang/README.md) | ~**10.1 tokens/s** | None | Runnable release; public demonstration keys |
| [S-AWIC with periodic reauthorization](variants/home-authorization/README.md) | ~**7.6 tokens/s** | None | Runnable token-ID demonstration; public demonstration keys |

Every row uses one input token and two 128-output trials. Selection is greedy
except for the seeded row, which uses temperature 1 and its recorded public
seed. The rate pools 254 cached outputs between validated replies, including
host control and inter-command gaps; periodic authorization includes renewal
and handover gaps. Command-only timings are separate. See the
[common protocol and selected records](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md).

The signed variants use an authorization policy of at least two of three
demonstration authorities. The [build and evidence map](REPRODUCE.md#configuration-and-build-authority)
identifies each configuration's sources, image and reproduction route. Their
memory protections, settings and evidence scopes are separate.

The browser workflow covers the four F-AWIC configurations. The three greedy
F-AWIC images support 2,048 input positions plus one final output slot, with
browser limits of 2,048 prompt tokens, 128 new tokens and 2,049 combined.
Long prompts take minutes before the first output; Stop drains an active STEP
before CLEAR. [Seeded generation](STOCHASTIC-GENERATION.md) specifies the
sampler's numerical/settings contract. The two signed variants have separate
installation and token-client instructions.

The encrypted design encrypts weights and K/V and retains integrity/replay
checks. Its supplied keys are public demonstration values, so they do not
provide deployed confidentiality.

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
The normal inference interface exposes APPEND, STEP and CLEAR; seeded sampling
also admits bounded settings at an empty, idle tape. Inference commands supply
no tensor operands, gradients or memory addresses. Signed model admission uses
the separate private flash boot path; the periodic variant relays model-bound
challenge/grant messages over UART. Neither adds a general weight-write or
arithmetic command to the inference interface.

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

## Signed model updates

The separate [S-AWIC prototype](variants/signed-update/README.md) admits compatible
full model parameters signed by two of three fixed demonstration authorities. Its
[complete Tang integration](variants/signed-update/tang/README.md) connects
signature admission to flash boot, DDR readback and the UART token machine.
[Validation status](variants/signed-update/tang/VALIDATION.md) distinguishes
completed simulations, native build qualification and board evidence. The
demonstration has public signing material and no deliberate update delay,
update cap or rollback prevention independent of home policy.

## Optional periodic reauthorization

The [S-AWIC with periodic reauthorization](variants/home-authorization/README.md) requires fresh approval at startup and periodically to keep running the authenticated model. Authorities can withdraw approval for old weights and distribute a signed replacement through the deployment host. It runs at 25 MHz and measures **~7.6 tokens/s** on the common paired benchmark, including renewal gaps. Its [installation](variants/home-authorization/INSTALL.md), [validation](variants/home-authorization/VALIDATION.md), [formal scope](variants/home-authorization/FORMAL-STATUS.md) and [reproduction](variants/home-authorization/REPRODUCE.md) are separate from the fixed-commitment and signed-update-only configurations.

The [physical replacement record](variants/home-authorization/VALIDATION.md#physical-model-replacement) checks two signed models, numerical outputs, withdrawal, rollback and replay for its identified image. It uses a controlled synthetic weight change. The complete replacement test for the repaired controller remains open; it is separate from the selected repaired image's approval/renewal/revocation and paired-speed checks.

## Combined security simulation

The [combined simulation target](variants/combined-security-simulation/README.md) joins signed admission, periodic reauthorization, encrypted authenticated weight reads and AES-SIV K/V on the full numerical datapath. It checks two distinct signed models, same-epoch cross-model K/V rejection, grant replay and late-response draining. Its private vault, persistent epoch and trusted time are explicit modeled services; it supplies no FPGA image or hardware benchmark.
