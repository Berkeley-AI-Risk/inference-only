# Qwen3-8B hardware and source build

Use [INSTALL.md](INSTALL.md) to run the measured image without compiling it.
This guide explains the circuit, the source/build selection and the rebuild
procedure. A rebuilt image needs its own implementation and board validation;
new vendor-tool runs need not produce byte-identical output.

## Organization

The fixed core sequences the 36 transformer layers, the private tensor
operations and greedy token selection. It has no instruction upload or
software-supplied tensor addresses. The token/control interface runs through
the AWS shell; a separate, restricted startup path uploads the one accepted
model image. After startup, the inference datapath owns memory addressing.

The numerical datapath uses signed 8-bit projection weights and fixed
integer/FP32/BF16 conversions and rounding. The [reference](reference/run_reference.py)
implements this numerical contract rather than substituting upstream
floating-point inference. Embeddings and the output projection are distinct.

HBM holds weights and K/V. The [weight reader](hardware/design/qwen_model_reader.sv)
authenticates pages against fixed expected digests and retains the output in
private cache banks. The [parent queue](hardware/design/qwen_model_verified_machine.sv)
forwards those responses to the token machine. By source inspection, this path
is intended to supply the checked copy rather than reread unchecked memory.
Proving the complete path through actual scalar operand admission, selection
and use remains open for this 8B reader/core; the 1.7B component results do not
establish it.
The core, memory interface and host interface are separate clock domains,
at 100, 125 and 250 MHz respectively. The clock-crossing and reset logic is
part of the design, not an assumption that all interfaces share one clock.
K/V is not authenticated in this package, and weights are not encrypted.

This release contains the measured implementation, separate from private
faster-datapath experiments.

## Source identity and dependencies

[SOURCE-INPUTS.json](SOURCE-INPUTS.json) pins the hardware, host client and
vendor revisions. The measured build used:

| Component | Selection |
| --- | --- |
| Device | `xcvu47p-fsvh2892-2-e`, AWS F2 small shell |
| Vivado | 2025.2 |
| AWS FPGA repository | `b603a81f65666e0cf7a67ee5cf18b148eb6b08c3` |
| AWS IP repository | `6d32be972e6da854e61a8d3d6ec0466ab491c1b3` |
| Clock recipes | A0, B0, C2, H1 |
| Shell version | `0x10212415` |

Install the vendor tools and obtain the pinned AWS repository, IP and shell
through their normal distribution channels. The proprietary shell checkpoint
and vendor tools are not redistributed in this repository. Licenses and
attribution are summarized in [NOTICES.md](NOTICES.md).

Check and stage the frozen inputs into a **new** directory without spaces:

```sh
cd /path/to/inference-only/demos/qwen3-8b
python3.12 tools/prepare_hardware.py \
  --hdk /path/to/aws-fpga --output /path/to/fresh-qwen8b-build
```

This verifies the source hashes, vendor revisions and shell checkpoint, then
copies the hardware into `fresh-qwen8b-build/cl_qwen`. It neither starts a
vendor build nor accesses the FPGA. Use a new directory for each build;
preserve checkpoints and reports rather than overwriting a previous result.

## Configuration and build authority

Build this **released 8B baseline** from its own source selection. Shared module
names do not make it interchangeable with the 1.7B build or a private faster-8B
experiment.

| Field | Released selection |
| --- | --- |
| Source and vendor identity | [SOURCE-INPUTS.json](SOURCE-INPUTS.json) pins the frozen hardware files, model-image hash, vendor revisions, shell and recipes |
| CL top and ordered inputs | `cl_qwen`; [qwen_sources.tcl](hardware/build/scripts/qwen_sources.tcl) selects 66 SystemVerilog and 12 Verilog files, including the 8B `qwen_fixed_root_rom.sv` |
| RTL compilation | [synth_cl_qwen.tcl](hardware/build/scripts/synth_cl_qwen.tcl) reads those lists, selects out-of-context `${CL}`, defines `XSDB_SLV_DIS`, and retains hierarchy |
| Staging and build entry | [prepare_hardware.py](tools/prepare_hardware.py), the [checked synthesis client](../../tools/qwen_build.py), frozen [build_all.tcl](hardware/build/scripts/build_all.tcl), and the placement/route scripts below; `ENCRYPT=0`, `CL=cl_qwen`, small shell |
| Explicit top parameter | `MODEL_PREFETCH_PAGES=32`; follow instantiated parameters rather than module defaults |
| Model and numerical contract | Fixed 36-layer geometry and [model-specific numerical reference](reference/run_reference.py); int8 projection weights with the stated integer/FP32/BF16 conversions and rounding |
| Fixed roots | The selected shared authenticator and root ROM use 134,705 pages with 18-bit page indices; the unselected older single-worker default is not the 8B root geometry |
| Application and management interfaces | APPEND, STEP and CLEAR; restricted startup model loader, status and [management display](README.md#management-display) |
| Memory and clock domains | Authenticated weight pages retained privately; unauthenticated external HBM K/V; 100 MHz core, 125 MHz memory interface, 250 MHz host |
| Applicable evidence | [Finite validation](VALIDATION.md), installation and implementation records. [No 8B solver proof suite](FORMAL-STATUS.md) is supplied. |

The [source-selection check](REPRODUCE.md#source-selection-check) checks that the
file hashes, lists, compile scripts, includes and top agree. It is a static
check, not full RTL/Tcl elaboration. The two shell interface includes and
protected vendor IP come from the pinned HDK. Historical filenames remain
unchanged so earlier build identities can be reproduced.

### CDC and reset disposition

Reset must put the host, core and memory interfaces into a consistent state and
release each domain safely, including during function-level reset (FLR). The
design uses targeted first-stage and Gray-bus constraints. Its reset contract
checks 48 chains and 154 asynchronous-clear (CLR) endpoints before selecting
exceptions, and retains min/max timing on 106 interstage and 14 functional-FLR
endpoint pairs.

The remaining engineering questions are:

- **Safe reset waveforms.** Establish the mapped logic's polarity and
  initialization, minimum assertion width, glitch behavior and arrival skew.
  Positive timing between synchronizer stages does not answer these questions.
- **Coordinated release.** Check recovery/removal and crossing behavior under
  the real clock relationships, so reset release cannot expose stale ready or
  transaction state across domains.
- **Vendor behavior.** Establish the HBM controller's reset/warm-recovery
  contract and shell FLR behavior, including the hidden vendor endpoints.

These questions remain open. Numerical tests and positive setup/hold slack do
not establish reset safety; a faster candidate needs its own physical and board
validation as well.

A November 6 read-only query of this original routed checkpoint used
`report_cdc -details -all_checks_per_endpoint`: it reported 32 additional
critical `CDC-11` fan-out rows, or 71 critical rows in total. Methodology
reported 12 `LUTAR-1` warnings and zero waived findings. The earlier 39-finding
report remains unchanged: expanded endpoint reporting is not a circuit change
or a demonstrated regression. All findings remain open.

The [diagnostic summary](evidence/cdc-reset-diagnostic-2026-11-06/SUMMARY.json)
identifies the unchanged checkpoint and sources and supplies native reports.
Its two CLR examples explain a report-counter correction: the observer expected
`Startpoint:`, but native paths use `Source:`/`Slack:`. The paths exist; their
slack is infinite under exceptions, so they supply arrival information rather
than recovery/removal margins. The summary distinguishes original and sanitized
hashes; only cloud hostnames and output paths were removed. Neither these paths
nor an empty query settles reset waveform safety; the full cloud collection is
not included.

## Synthesis, placement and routing

The following are the build stages used by the measured implementation.
Use a Linux build host with enough memory and storage, and retain each log.
Start in Bash with Vivado 2025.2 installed:

```sh
source /path/to/Vivado/2025.2/settings64.sh
cd /path/to/aws-fpga
source hdk_setup.sh -s
export QWEN_BUILD=/path/to/fresh-qwen8b-build
cd /path/to/inference-only/demos/qwen3-8b
python3.12 ../../tools/qwen_build.py synth \
  --profile qwen3-8b --build-dir "$QWEN_BUILD" \
  --hdk /path/to/aws-fpga --output "$QWEN_BUILD/synthesis-control"
export CL=cl_qwen
export CL_DIR="$QWEN_BUILD/cl_qwen"
export SHELL_MODE=small_shell
export BUILD_TAG=private_qwen8b_100
export ENCRYPT=0
cd "$CL_DIR/build/scripts"
```

The checked client invokes the same frozen synthesis Tcl with A0/B0/C2/H1.
It checks source/vendor/tool identities, propagates a failing Vivado exit, and
requires a fresh checkpoint with valid ZIP CRCs before writing
`synthesis-control/FINISHED.json`. That receipt records tool completion, not
timing closure.

Build and package clients take a nonblocking OS lock on the canonical staged
CL before preflight and hold it through artifact checks and receipt creation.
A concurrent client using that same stage exits 75, even with another receipt
directory or path alias; independent stages can run separately. Leave the
persistent `.qwen-build.lock` file in place: the OS lock, not file presence,
tracks ownership. This coordinates these clients, not manually launched vendor
commands; do not run such commands concurrently in the same stage.

`BUILD_TAG` is a checked build identifier, not an AWS sharing setting. The
scripts limit the vendor tool to eight threads. The resulting synthesis
checkpoint is
`cl_qwen/build/checkpoints/cl_qwen.private_qwen8b_100.post_synth.dcp`.
Inspect the synthesis results before proceeding:

```sh
export BUILD_FLOW=ImplCL
vivado -mode batch -source build_all_placement.tcl \
  -log placement.log -journal placement.jou \
  -tclargs SSI_SpreadLogic_high Default AggressiveExplore A0 B0 C2 H1
```

Placement writes `output/payload.reset-contract.post_phys_opt.dcp` under the
fresh build directory. It checks the expected clock periods, startup memory
mapping, private payload storage and reset-release structure. Inspect its
actual timing and congestion reports; a completed process is not a timing
pass. The route stage takes that checkpoint and its SHA-256 explicitly:

```sh
sha256sum /path/to/fresh-qwen8b-build/output/payload.reset-contract.post_phys_opt.dcp
vivado -mode batch -source route_supported_c2_100.tcl \
  -log route.log -journal route.jou \
  -tclargs \
  /path/to/fresh-qwen8b-build/output/payload.reset-contract.post_phys_opt.dcp \
  REPLACE_WITH_THE_CHECKPOINT_SHA256 \
  /path/to/fresh-qwen8b-build/output/route
```

The route script preserves clock modeling and the selected timing constraints.
Its leaf-clock optimization setting is explicit in the source. Do not bypass
the identity, geometry or timing checks to make a different build appear to
match this one. Route completion still requires examination of setup, hold,
pulse width, routing, clock crossings and constrained reset behavior.

The [implementation evidence](evidence/implementation/REPORTS.json) identifies
the measured routed checkpoint and the accompanying reports. For that build,
setup slack was +0.001 ns and hold slack +0.007 ns, with no routing errors.
Some vendor-shell and reset/clock-crossing findings require scoped review;
the reports are not a blanket statement that every warning disappeared.

<!-- BEGIN GENERATED QWEN CDC DISCLOSURE -->
The [CDC report](evidence/implementation/cdc.rpt) retains **39 critical
findings** in its summary (`CDC-1`: 1, `CDC-7`: 1, `CDC-10`: 35, `CDC-13`: 2).
These are reported finding counts, not a count of proved functional
failures. Per-finding disposition and whole-path reset/CDC qualification
remain open; positive setup/hold slack does not discharge them.
<!-- END GENERATED QWEN CDC DISCLOSURE -->

After reviewing the rebuilt route, timing, CDC and reset reports, package its
exact checkpoint from `demos/qwen3-8b`:

```sh
export QWEN_ROUTED_DCP="$QWEN_BUILD/output/route/supported-c2-100.post_route.dcp"
export QWEN_PACKAGE_TAG="$(date -u +%Y_%m_%d-%H%M%S)"
python3.12 ../../tools/qwen_build.py package \
  --profile qwen3-8b --build-dir "$QWEN_BUILD" --hdk /path/to/aws-fpga \
  --checkpoint "$QWEN_ROUTED_DCP" \
  --checkpoint-sha256 "$(sha256sum "$QWEN_ROUTED_DCP" | cut -d ' ' -f 1)" \
  --tag "$QWEN_PACKAGE_TAG" --output "$QWEN_BUILD/package-$QWEN_PACKAGE_TAG"
```

The `package` subcommand creates a developer tarball with manifest format 2,
A0/B0/C2/H1 recipes, tool/HDK/shell versions, fixed PCI IDs and the checked DCP
hash. It refuses `.VIOLATED` checkpoints and existing output directories, then
reopens and verifies every tar member. Packaging is not timing qualification
or AWS image creation.

Creating an AWS image from a rebuild still requires the vendor image acceptance
workflow and a new hardware correctness test. The public image in
[INSTALL.md](INSTALL.md) is the already tested deployment. This source-build
guide does not make a newly compiled image interchangeable with it.

## Verification boundaries

The measured image passed the token comparisons in [measurements.json](measurements.json).
The package includes an offline measurement checker and a numerical reference.
These are separate from physical timing checks. Neither those tests nor the
implementation reports prove whole-machine refinement or resistance to
physical modification. See the [interface assessment](README.md#inference-only-scope).
