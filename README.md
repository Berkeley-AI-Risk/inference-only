# Inference-only FPGA demonstrations

The paper *The Feasibility of a Hardwired Pause of Frontier AI Training*
([hardwired-pause.ai](https://hardwired-pause.ai)) introduces inference-only
chips in both an idealized sense and a practical, operational sense.
**This project builds physical FPGA demonstrations of that idea:** fixed
language models behind a restricted hardware interface, rather than a
general-purpose accelerator whose restrictions depend on its host software.

*Inference* uses an already-trained model to produce outputs without changing
its learned weights. The idealized machine permits models from a fixed set
and only three user operations: add input tokens to a model's tape, generate
another token, and clear the tape. Each demonstration here permits just one
model, so model selection is implicit.

| Inference command | Effect |
| --- | --- |
| `APPEND(token)` | Add one input token to the tape. |
| `STEP` | Generate a token, append it to the tape, and return it. |
| `CLEAR` | Empty the logical tape and invalidate cached inference state. |

Tokens are the pieces of text a language model reads and generates. The
hardware provides no application command to change model weights, submit a
matrix multiplication, or read and write intermediate tensors. Hardware
controllers own the inference schedule and memory addresses; the user supplies
tokens, not tensor pointers. Startup loaders, status and transport handling
are described separately in each model's guide.

An optional [seeded-sampling version of SimpleStories-V2-5M](STOCHASTIC-GENERATION.md)
also accepts a bounded temperature and public seed while its tape is empty and
idle. The optimized seeded image runs the same numerical model on the same Tang
Mega board. Its current evidence and qualification limits are stated
in [CURRENT-QUALIFICATION.md](CURRENT-QUALIFICATION.md). The original three
greedy images retain their own recorded evidence; the archived seeded 0e6
release is separate provenance.

## The demonstrated designs and measurements

| Model and platform | Measured cached generation | Package status |
| --- | --- | --- |
| **SimpleStories-V2-5M — Tang Mega**, authenticated weights | About **8.8 tokens/s** | Runnable release |
| Same model, **K/V-protected** | About **5.2 tokens/s** | Runnable release |
| Same model, **K/V protection + encrypted memory** | About **4.3 tokens/s** | Runnable experimental version; public demonstration keys |
| Same model, **seeded sampling**, without K/V integrity | About **9.9 tokens/s** at temperature 1 | Runnable release |
| **Qwen3-1.7B — AWS F2**, authenticated weights | About **9.0 tokens/s** | Runnable release; public AWS FPGA image |
| **Qwen3-8B — AWS F2**, authenticated weights | About **1.1 tokens/s** | Runnable prototype; speed optimization in progress; public AWS FPGA image |

The encrypted-memory version retains K/V integrity and replay protection and
also encrypts both weights and K/V; its supplied keys are public demonstration
keys. Seeded sampling uses the baseline's authenticated weights, without K/V
integrity or encryption.

These rates come from separate validation campaigns with different workloads:

- **SimpleStories-V2-5M:** all four quoted configurations use a one-token
  prompt and 128 generated tokens. The optimized seeded campaign retained its
  parent's eight trials: twice at each temperature 0, 0.5, 1 and 2. Its
  table rate is the weighted cached command rate at temperature 1.
- **Qwen3-1.7B:** three prompts of 4, 5 and 15 tokens each generate 128 tokens;
  the complete three-prompt suite was run twice.
- **Qwen3-8B:** the quoted sustained case uses a one-token prompt and
  128 generated tokens.

The records report what each campaign tested; they are **not a matched
comparison between the SimpleStories and Qwen models**, or evidence that
sampling makes SimpleStories faster. Models, tokenizers, hardware and timing
methods differ. Cached rates exclude the first token; the SimpleStories
rates sum command/reply times, while Qwen's also include gaps between replies.
Longer prompts take longer to produce the first token, and growing context
slows subsequent generation. These are measured rates, not peak ratings.

“Runnable release” means the image, model, app and installation instructions
are available. The optimized seeded package passed its seven board suites,
registered scoped scientific completion, fresh model/flash readback, exact
recipient reload and registration, and twelve ordinary Chrome cases with all
100 outputs matching the reference. Its
[current qualification record](CURRENT-QUALIFICATION.md) separates those results
from the remaining timing, security and proof limits. The archived seeded 0e6
ten-case rehearsal is historical. No other-owner installation or
complete-workload guarantee follows.
No Tang version has complete vendor-DDR timing or physical-security certification.

The optimized seeded image recorded **9.94 cached tokens/s** at temperature 1,
compared with **8.67 tokens/s** for the archived seeded image. Both measurements
use the same one-token prompt and two 128-output trials and exclude the first
hardware STEP. See the [qualification and timing details](CURRENT-QUALIFICATION.md#recorded-timing)
for the exact measurements, full workload and longer-prompt results.

- **[SimpleStories-V2-5M / Tang Mega guide](demos/simplestories-v2-5m/README.md):** board selection,
  the three greedy versions, optional seeded sampling, browser app,
  installation, measured prompt/decode speeds,
  and links to source, proofs and reproduction instructions.
- **[Qwen3-1.7B / AWS F2 guide](demos/qwen3-1.7b/README.md):** the billion-parameter
  hardware result, measured prompt/decode speeds, frozen-model boundary,
  installation, browser app, hardware sources and numerical reference.
- **[Qwen3-8B / AWS F2 guide](demos/qwen3-8b/README.md):** the eight-billion-parameter
  prototype, measured prompt/decode speeds, installation with a token-ID client,
  hardware sources and numerical reference. A browser app is not yet included.

<img src="fpga.jpeg" alt="The Tang Mega 138K board used for the SimpleStories inference-only demonstration, connected by USB." width="720">

*The physical Tang Mega board used for the small-model demo. We used the
[138K Basic Package](https://www.aliexpress.us/item/3256807078990410.html).
Board compatibility and installation details are in its guide.*

## In what sense is it inference-only?

An FPGA is configurable digital circuitry. Here it lets us test a proposed
circuit without manufacturing a custom chip. We assess each design **as if
its configuration were permanently frozen**, or implemented as a fixed
application-specific integrated circuit (ASIC). Reprogramming the development
FPGA is outside that assessment; resistance to other physical tampering is
not established by this assumption.

These designs illustrate the paper's **Authenticated-Weight Inference-Only
Chip (AWIC)** approach: architecture and inference function are fixed in
circuitry, while hardware authenticates the weights read from memory against
fixed cryptographic digests. The checked on-chip copies, not unchecked later
reads from external memory, supply arithmetic. No signing secret or
manufacturer weight-update command is needed. This differs from hardwiring
the weight bits themselves into model-specific silicon.

Internal multiplication is not an exposed general-purpose service. Attention
uses internally produced queries and probabilities, and sends its results to
later model operations. Fixed hardware, not host software, manages the
intermediate memory layout. This avoids exposing a direct matrix-multiplication
interface; it does not establish that every physical or indirect attack is
impossible.

The practical standard concerns **low residual training capacity even against
an adversary with physical possession**. Demonstrating the restricted
architecture is not the same as certifying that standard. External memory,
test/debug/scan paths and any future inter-chip links require their own
assessment. The Qwen experiments also have AWS management and diagnostic
facilities outside its token application interface; the whole cloud platform
is not claimed to be inference-only.

The [detailed inference-only assessment](INFERENCE-ONLY.md) explains these
distinctions using the Tang Mega designs. Its [formal-verification report](FORMAL-STATUS.md)
covers specific properties of the baseline and K/V-protected RTL and a
separate source-bound extension for seeded sampling. These are scoped
control/component proofs, without whole-machine refinement or a Qwen proof.
The [conditional training-capacity analysis](TRAINING-CAPACITY.md)
and [architecture-dependent analysis](ARCHITECTURE-DEPENDENT-CAPACITY.md)
make their assumptions explicit; their Tang Mega numerical factors are not
Qwen measurements. **None of these demonstrations has a certified, nation-state-resistant
residual training fraction.** Small model size or modest speed is not what
makes the architectural restriction inference-only.

## Run a demonstration

For the Tang Mega, follow [its installation guide](demos/simplestories-v2-5m/README.md#run-it-on-your-board).
The prebuilt configurations, model, tokenizer and browser app are included;
running them requires neither hardware compilation nor a paid FPGA design
license. Installing the model erases flash, so preserve the factory backup
first. The tested host workflow uses Apple Silicon macOS.

For Qwen, follow the AWS F2 installation guide for
[Qwen3-1.7B](demos/qwen3-1.7b/INSTALL.md) or [Qwen3-8B](demos/qwen3-8b/INSTALL.md).
Load the publicly available tested FPGA image, reconstruct the fixed model
from the pinned upstream checkpoint, and build the included host client.
No FPGA compilation is needed for that path. You provide your own AWS account
and rental; the 1.7B browser app can run on your Mac and connect to the F2 host
over SSH. Hardware sources, build instructions and numerical-reference tools
are also included.

## AI design experiment and attribution

A secondary goal is an experiment in AI capabilities in chip design.
**GPT 5.6 Sol and GPT 6 Astra wrote the custom RTL, implementation code,
verification and host tools, and the documentation**, under the project owner's
direction. Incorporated review feedback for the Tang Mega work came from
**Fable 5.1 and Opus 5.5**, including Fable's suggestion to separate fast DDR
transport from slower inference control.

Hardware is primarily SystemVerilog/Verilog; numerical references and tests
use Python and C++; host software uses Python and C++; implementation flows
use Tcl and constraints. This attribution excludes the FPGA silicon, boards,
vendor IP and tools, pretrained models, and third-party libraries. It is an
engineering experiment with human oversight, not a controlled comparison of
AI and human engineering ability.
The custom implementation builds on established algorithms and hardware
techniques; [design references and prior work](REFERENCES.md) distinguish
those antecedents from directly reused components.

## Technical documentation and licenses

Start with a model's guide for its architecture, hardware instructions and
evidence. The root-level architecture, installation, simulation, proof,
H100 benchmark and capacity documents currently describe **Tang Mega** unless
they explicitly say otherwise. Qwen's reported results and limitations live
in the respective model guides.

Project-owned code, documentation and the photograph are Apache-2.0; the
packaged SimpleStories model assets use the upstream MIT declaration.
See [LICENSE](LICENSE), [NOTICE](NOTICE), [LICENSING.md](LICENSING.md) and
[third-party notices](THIRD-PARTY-NOTICES.md). Qwen's upstream model is Apache-2.0;
its [dependency notices](demos/qwen3-1.7b/NOTICES.md) distinguish project-owned
code from AWS, FPGA-vendor and other third-party components. The
[8B dependency notices](demos/qwen3-8b/NOTICES.md) identify its corresponding
sources. The project license
does not replace those components' terms.
