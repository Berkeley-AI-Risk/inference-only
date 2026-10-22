# Qwen3-8B hardware and source build

The [installation guide](INSTALL.md) runs the measured image without compiling
hardware. This page is for inspecting the circuit or rebuilding it. A new
build is not automatically qualified by the reports shipped for the measured
image, and byte-identical output from a new vendor-tool run is not promised.

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

HBM holds weights and K/V. Weight pages are read into private storage,
authenticated against fixed expected digests, and retained for consumption.
The datapath consumes the verified copy, not a second unchecked memory read.
The core, memory interface and host interface are separate clock domains,
at 100, 125 and 250 MHz respectively. The clock-crossing and reset logic is
part of the design, not an assumption that all interfaces share one clock.
K/V is not authenticated in this package, and weights are not encrypted.

The released package contains only the measured implementation. Experimental
faster datapaths are not mixed into its source or measurements.

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

## Synthesis, placement and routing

The following are the build stages used by the measured implementation.
Use a Linux build host with enough memory and storage, and retain each log.
Start in Bash with Vivado 2025.2 installed:

```sh
source /path/to/Vivado/2025.2/settings64.sh
cd /path/to/aws-fpga
source hdk_setup.sh -s
export CL=cl_qwen
export CL_DIR=/path/to/fresh-qwen8b-build/cl_qwen
export SHELL_MODE=small_shell
export BUILD_TAG=private_qwen8b_100
export ENCRYPT=0
export BUILD_FLOW=SynthCL
cd "$CL_DIR/build/scripts"
vivado -mode batch -source build_all.tcl \
  -log synthesis.log -journal synthesis.jou \
  -tclargs SSI_SpreadLogic_high AggressiveExplore AggressiveExplore A0 B0 C2 H1
```

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

Creating an AWS image from a rebuild requires the vendor packaging and image
acceptance workflow and a new hardware correctness test. The public image in
[INSTALL.md](INSTALL.md) is the already tested deployment. This source-build
guide does not make a newly compiled image interchangeable with it.

## Verification boundaries

The measured image passed the token comparisons in [measurements.json](measurements.json).
The package includes an offline measurement checker and a numerical reference.
These are separate from physical timing checks. Neither those tests nor the
implementation reports prove whole-machine refinement or resistance to
physical modification. See the [interface assessment](README.md#inference-only-scope).
