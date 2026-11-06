# Qwen3-1.7B hardware and source build

[Qwen guide](README.md) · [Run the prebuilt design](INSTALL.md) · [Licenses](NOTICES.md)

Use [INSTALL.md](INSTALL.md) to run the measured image without compiling it.
This guide explains the circuit, the source/build selection and the rebuild
procedure. A rebuilt image needs its own implementation and board validation.

## Circuit organization

The custom SystemVerilog circuit implements a fixed 28-layer Qwen3-1.7B
schedule. It uses signed 8-bit weights, per-vector signed 16-bit projection
inputs, integer dot-product accumulation, and specified FP32/BF16 operations
and tables elsewhere. The parallel projection datapath processes 32 rows of
eight weights per accepted beat. Attention remains an internal operation;
the host cannot supply its tensor addresses, shapes or operands.

The design uses AWS F2's UltraScale+ VU47P FPGA and HBM. The measured image
uses AWS clock recipes A0/B0/C2/H1: **100 MHz inference**, **125 MHz memory**,
and the **250 MHz host clock**. Weights and K/V are in HBM, not host DRAM or
DDR4. Four private weight-verification workers authenticate pages before
the inference engine can consume their checked on-chip copies. The mapped
payload storage occupies 128 UltraRAM blocks across 16 private banks.

The startup path accepts only the selected model image. The C++ host serializes
APPEND, STEP and CLEAR, with an exclusive slot lock; it performs tokenization
and presentation, not inference. Host-side end-marker stopping changes the
number of STEPs issued, not the circuit's greedy numerical rule.
The [interface assessment](README.md#interface-and-inference-only-scope)
also discloses status registers and the source-level
[management display](README.md#management-display). A routed-image check of
that display remains open; the top-level source does not expose the previously
described attention-state readout through this output.

### Detailed hardware diagram

This diagram expands the released 100 MHz design, using the same colors and
layout as the [SimpleStories diagram](../simplestories-v2-5m/HARDWARE.md#detailed-baseline-diagram).
Both circuits own the inference schedule, tensor addresses and checked-weight
path. Qwen uses HBM and substantially more parallel arithmetic. Its released
baseline does not include K/V integrity protection or weight encryption.

![Detailed Qwen3-1.7B baseline: fixed host and inference controllers, HBM weight verification and caches, selected projection banks, paired-head attention, and mapped DSP resources.](../../diagrams/qwen-hardware-architecture.svg)

[Open the full-size SVG](../../diagrams/qwen-hardware-architecture.svg) ·
[PNG](../../diagrams/qwen-hardware-architecture.png) ·
[Sources and regeneration](../../diagrams/README.md)

The 1,000 DSP blocks are mapped FPGA resources, not 1,000 independently usable
multipliers. Floating-point arithmetic can consume several blocks; some blocks
implement additions. Only one of the two projection banks is selected at a time.
The diagram summarizes functional connections, not physical placement or a
security proof.

### Parallel memory paths and remaining throughput limits

Weights arrive over eight 256-bit HBM AXI read ports, which assemble a
2,048-bit (256-byte) word. At the 125 MHz memory-side clock, their ideal
combined payload ceiling is 32 GB/s. This describes these particular wires,
not measured sustained bandwidth or the full HBM subsystem's rating.
Separate ports serve K/V. Four verification workers, prefetching, private
buffers and pipelined arithmetic overlap some of the work; they do not make
every inference stage run continuously or every HBM port fully utilized.

The selected projection bank accepts at most one 256-byte weight beat per
inference cycle, performing 256 integer products. Increasing external-memory
bandwidth alone cannot increase that acceptance rate. A wider design would
need matching throughput through the memory transport, authentication,
checked-weight buffers and arithmetic, while preserving hardware ownership
of all intermediate data and addresses. Such changes are engineering
opportunities, not speedups credited to this release.

## Source identity and measured implementation

`SOURCE-INPUTS.json` identifies the byte-identical selected RTL, build inputs,
tables, tokenizer and original qualification client. `host/` contains the
runnable client with end-marker stopping; `hardware/qualification-host/`
preserves the client used for the published sustained measurements.
`hardware/IMPLEMENTATION-INPUTS.json` identifies the actual placement/reset/
routing scripts and separately installed vendor dependencies:

| Dependency | Tested identity |
| --- | --- |
| Vivado | 2025.2 |
| AWS HDK | `b603a81f65666e0cf7a67ee5cf18b148eb6b08c3` |
| Version-specific AWS IP | `6d32be972e6da854e61a8d3d6ec0466ab491c1b3` |
| AWS runtime shell | `0x10212415` |
| Routed checkpoint SHA-256 | `e8a1143e44bdc65fd1da76d7faeac236e59c49ccd4d5ce004a3b962ce6b5c98d` |

The complete [timing report](evidence/implementation/timing-summary.rpt) shows
setup slack **+0.011 ns** and hold slack **+0.007 ns** under the declared
constraints. The [routing report](evidence/implementation/route-status.rpt)
shows 1,057,236 routable nets fully routed and zero routing errors.
The [report inventory](evidence/implementation/REPORTS.json) binds the
checkpoint to the preserved reports. Only build-host identifiers and private
filesystem prefixes were removed; warnings and report rows were retained.

Passing these timing checks does not mean the design has no warnings. The
[CDC](evidence/implementation/cdc.rpt), [DRC](evidence/implementation/drc.rpt)
and [exception](evidence/implementation/exceptions.rpt) reports remain available
for inspection. The reset contract excludes exactly 154 raw asynchronous-clear
inputs in 48 structurally checked release chains, while retaining interstage
and functional reset timing. The
[retained reset timing](evidence/implementation/reset-retained-timing.tsv) and
[payload memory timing](evidence/implementation/payload-retained-timing.tsv)
reports document those checks. This is not production ASIC signoff or a
whole-machine formal proof.

The [design references](../../docs/REFERENCES.md) credit the model's algorithmic
antecedents, reused arithmetic library and relevant hardware prior work.

<!-- BEGIN GENERATED QWEN CDC DISCLOSURE -->
The [CDC report](evidence/implementation/cdc.rpt) retains **39 critical
findings** in its summary (`CDC-1`: 1, `CDC-7`: 1, `CDC-10`: 35, `CDC-13`: 2).
These are reported finding counts, not a count of proved functional
failures. Per-finding disposition and whole-path reset/CDC qualification
remain open; positive setup/hold slack does not discharge them.
<!-- END GENERATED QWEN CDC DISCLOSURE -->

## Configuration and build authority

Build this **released 1.7B baseline** from its own source selection. The 8B
overlay and separate protected-K/V candidate are different configurations.

| Field | Released selection |
| --- | --- |
| Source identity | [SOURCE-INPUTS.json](SOURCE-INPUTS.json), joined to [hardware/IMPLEMENTATION-INPUTS.json](hardware/IMPLEMENTATION-INPUTS.json) by the source-bundle manifest hash |
| CL top and ordered inputs | `cl_qwen`; [qwen_sources.tcl](hardware/build/scripts/qwen_sources.tcl) selects 65 SystemVerilog and 12 Verilog files |
| RTL compilation | [synth_cl_qwen.tcl](hardware/build/scripts/synth_cl_qwen.tcl) reads those lists, selects out-of-context `${CL}`, defines `XSDB_SLV_DIS`, and retains hierarchy |
| Staging and build entry | [prepare_hardware.py](tools/prepare_hardware.py), then the pinned AWS builder and [build_all.tcl](hardware/build/scripts/build_all.tcl); `ENCRYPT=0`, `CL=cl_qwen`, small shell |
| Explicit top parameter | `MODEL_PREFETCH_PAGES=32`; follow instantiated parameters rather than module defaults |
| Model and numerical contract | Fixed 28-layer geometry, signed int8 projection weights and the specified integer/FP32/BF16 operations; [reference contract](reference/README.md) and [model installation](INSTALL.md#prepare-the-fixed-model) |
| Application and management interfaces | APPEND, STEP and CLEAR; restricted startup model loader, status and [management display](README.md#management-display) |
| Memory protection | Fixed-root weight-page authentication and retained private checked copies; external HBM K/V is **not authenticated** and weights are not encrypted |
| Clocks and vendor inputs | A0/B0/C2/H1: 100 MHz core, 125 MHz memory interface, 250 MHz host; pinned Vivado/HDK/IP/shell inputs in the implementation inventory |
| Evidence | [Validation](VALIDATION.md), [component formal scope](FORMAL-STATUS.md), and the selected installation and implementation records |

The preparer checks hashes before copying files. The
[source-selection check](REPRODUCE.md#source-selection-check) also checks that
the lists, compile scripts, includes and top agree. These are static checks,
not full RTL elaboration. The two shell interface includes and protected vendor
IP come from the pinned HDK. Historical filenames remain unchanged so earlier
build identities can be reproduced.

### CDC and reset disposition

Reset must put the host, core and memory interfaces into a consistent state and
release each domain safely, including during function-level reset (FLR). The
design uses targeted first-stage and Gray-bus constraints in
[qwen_cdc_constraints.tcl](hardware/build/scripts/qwen_cdc_constraints.tcl).
Its reset contract checks 48 chains and 154 asynchronous-clear (CLR) endpoints
before selecting exceptions, and retains min/max timing on 106 interstage and
14 functional-FLR endpoint pairs.

The remaining engineering questions are:

- **Safe reset waveforms.** Establish the mapped logic's polarity and
  initialization, minimum assertion width, glitch behavior and arrival skew.
  Positive timing between synchronizer stages does not answer these questions.
- **Coordinated release.** Check recovery/removal and crossing behavior under
  the real clock relationships, so reset release cannot expose stale ready or
  transaction state across domains.
- **Vendor behavior.** Establish the HBM controller's reset/warm-recovery
  contract and shell FLR behavior, including the hidden vendor endpoints.

These questions remain open for the released image. Local protected-K/V tests
exercise a separate candidate and do not provide its physical CDC/HBM/timing
qualification.

A November 6 read-only query of the original routed checkpoint used
`report_cdc -details -all_checks_per_endpoint`. That expanded reporting mode
found 32 additional critical `CDC-11` fan-out rows, for 71 critical rows in
total, and methodology reported 12 `LUTAR-1` warnings with zero waived findings.
The [diagnostic summary](evidence/cdc-reset-diagnostic-2026-11-06/SUMMARY.json)
identifies the unchanged checkpoint and sources and supplies native reports.
The earlier 39-finding report remains unchanged: the expanded inventory reflects
more checks per endpoint, not a circuit change or demonstrated regression.
All findings remain open.

The two CLR examples explain a report-counter correction: the observer expected
`Startpoint:`, but native paths use `Source:`/`Slack:`. The paths exist; their
slack is infinite under exceptions, so they supply arrival information rather
than recovery/removal margins. The summary distinguishes original and sanitized
hashes; only cloud hostnames and output paths were removed. Neither these paths
nor an empty query settles reset waveform safety. The interface and numerical
contract remain unchanged while this work proceeds.

## Rebuild from source

Running the prebuilt demonstration does not require rebuilding it. A rebuild
needs Linux x86-64, the pinned AWS HDK/IP, and Vivado 2025.2. Follow
[AWS's HDK setup guide](https://awsdocs-fpga-f2.readthedocs-hosted.com/latest/hdk/README.html)
to obtain the tools, version-specific IP and shell. A different vendor revision
is a new implementation requiring its own timing and hardware validation.

After sourcing Vivado's `settings64.sh` and the HDK's `hdk_setup.sh -s`, run
from `demos/qwen3-1.7b`:

```sh
python3.12 tools/prepare_hardware.py --hdk /path/to/aws-fpga \
  --output /data/qwen-build
export QWEN_BUILD=/data/qwen-build
export CL_DIR="$QWEN_BUILD/cl_qwen"
cd "$CL_DIR/build/scripts"
python3 aws_build_dcp_from_cl.py --cl cl_qwen --mode small_shell \
  --flow SynthCL --aws_clk_gen --clock_recipe_a A0 --clock_recipe_b B0 \
  --clock_recipe_c C2 --clock_recipe_hbm H1 --no-encrypt \
  --tag private_supported_c2_100
```

The historical build tag is retained because the frozen implementation scripts
check it; it is not an AWS account or a private image identifier. The preparer
requires a fresh directory and does not modify the released source tree.
It verifies the HDK, IP and shell identity before copying sources.

Next run the exact placement and routing scripts:

```sh
export CL=cl_qwen SHELL_MODE=small_shell BUILD_FLOW=ImplCL
export BUILD_TAG=private_supported_c2_100 ENCRYPT=0
vivado -mode batch -source "$QWEN_BUILD/build_all_placement.tcl" \
  -log "$QWEN_BUILD/placement.log" -journal "$QWEN_BUILD/placement.jou" \
  -tclargs SSI_SpreadLogic_high Default AggressiveExplore A0 B0 C2 H1
export QWEN_ROUTE_INPUT="$QWEN_BUILD/output/payload.reset-contract.post_phys_opt.dcp"
export QWEN_ROUTE_SHA=$(sha256sum "$QWEN_ROUTE_INPUT" | cut -d ' ' -f 1)
vivado -mode batch -source "$QWEN_BUILD/route_supported_c2_100.tcl" \
  -log "$QWEN_BUILD/route.log" -journal "$QWEN_BUILD/route.jou" \
  -tclargs "$QWEN_ROUTE_INPUT" "$QWEN_ROUTE_SHA" "$QWEN_BUILD/route"
```

The tested route uses `AggressiveExplore` with the internal parameter
`route.optimizeLeafClkProgDlys` disabled. Leaf-clock timing modeling remains
enabled; this is not a timing waiver or a vendor-endorsed workaround. The scripts
verify the real clock periods and the startup RAM output-register mapping.

From the Qwen directory, run:

```sh
python3.12 tools/check_routed_reports.py /data/qwen-build/route
```

This checks basic timing, routing and severe DRC status only. Review the full
CDC/reset/exception reports as well. A successful process exit alone is not
evidence of timing closure. Rebuilt placement may differ, and the supplied
measurements apply to the identified prebuilt image, not any new rebuild.

For a rebuild that passes review, place its routed checkpoint in the CL build's
`checkpoints` directory under a new timestamp tag and use the pinned AWS
builder's `--package-only` operation with all four clock recipes explicitly
specified. Then follow the
[AWS AFI creation instructions](https://awsdocs-fpga-f2.readthedocs-hosted.com/latest/hdk/docs/Amazon-FPGA-Images-Afis-Guide.html).
Image creation performs AWS platform validation; it does not replace numerical
tests. Load the new image only into a slot you control, then repeat the
known-answer and sustained tests before reporting its speed.
