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

## The demonstrated design and measurements

| Model and platform | Measured cached generation | Package status |
| --- | --- | --- |
| **SimpleStories-V2-5M — Tang Mega**, authenticated weights | About **8.8 tokens/s** | Runnable release |
| Same model, **K/V-protected** | About **5.2 tokens/s** | Runnable release |
| Same model, **encrypted memory** | About **4.3 tokens/s** | Runnable experimental version; public demonstration keys |
| **Qwen3-1.7B — AWS F2**, authenticated weights | **8.964–9.001 tokens/s** | Runnable release; public AWS FPGA image |

These are measured rates, not clock-based estimates or peak ratings. Tang
Mega uses a one-token prompt and 128 generated tokens; Qwen uses 4-, 5- and
15-token prompts and two repeated 128-token suites. The models, tokenizers and
workloads differ, so this is **not a head-to-head performance benchmark**.
Both measurements exclude the first token. Tang's figures are cached command
rates; Qwen's also include gaps between replies. Longer prompts take longer
to produce the first token, and growing context slows subsequent generation.

- **[SimpleStories-V2-5M / Tang Mega guide](demos/simplestories-v2-5m/README.md):** board selection,
  all three versions, browser app, installation, measured prompt/decode speeds,
  and links to source, proofs and reproduction instructions.
- **[Qwen3-1.7B / AWS F2 guide](demos/qwen3-1.7b/README.md):** the billion-parameter
  hardware result, measured prompt/decode speeds, frozen-model boundary,
  installation, browser app, hardware sources and numerical reference.

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
assessment. The Qwen experiment also has AWS management and diagnostic
facilities outside its token application interface; the whole cloud platform
is not claimed to be inference-only.

The [detailed inference-only assessment](INFERENCE-ONLY.md) explains these
distinctions using the Tang Mega designs. Its [formal-verification report](FORMAL-STATUS.md)
covers specific properties of those RTL configurations, not whole-machine
refinement or Qwen. The [conditional training-capacity analysis](TRAINING-CAPACITY.md)
and [architecture-dependent analysis](ARCHITECTURE-DEPENDENT-CAPACITY.md)
make their assumptions explicit; their Tang Mega numerical factors are not
Qwen measurements. **Neither demonstration has a certified, nation-state-resistant
residual training fraction.** Small model size or modest speed is not what
makes the architectural restriction inference-only.

## Run a demonstration

For the Tang Mega, follow [its installation guide](demos/simplestories-v2-5m/README.md#run-it-on-your-board).
The prebuilt configurations, model, tokenizer and browser app are included;
running them requires neither hardware compilation nor a paid FPGA design
license. Installing the model erases flash, so preserve the factory backup
first. The tested host workflow uses Apple Silicon macOS.

For Qwen, follow [the AWS F2 installation guide](demos/qwen3-1.7b/INSTALL.md).
Load the publicly available tested FPGA image, reconstruct the fixed model
from the pinned upstream checkpoint, and build the included host client.
No FPGA compilation is needed for that path. You provide your own AWS account
and rental; the browser app can run on your Mac and connect to the F2 host
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

## Technical documentation and licenses

Start with a model's guide for its architecture, hardware instructions and
evidence. The root-level architecture, installation, simulation, proof,
H100 benchmark and capacity documents currently describe **Tang Mega** unless
they explicitly say otherwise. Qwen's reported results and limitations live
in its separate guide.

Project-owned code, documentation and the photograph are Apache-2.0; the
packaged SimpleStories model assets use the upstream MIT declaration.
See [LICENSE](LICENSE), [NOTICE](NOTICE), [LICENSING.md](LICENSING.md) and
[third-party notices](THIRD-PARTY-NOTICES.md). Qwen's upstream model is Apache-2.0;
its [dependency notices](demos/qwen3-1.7b/NOTICES.md) distinguish project-owned
code from AWS, FPGA-vendor and other third-party components. The project license
does not replace those components' terms.
