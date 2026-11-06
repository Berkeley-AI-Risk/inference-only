# Reproduce Qwen3-8B assets and evidence

[Guide](README.md) · [Validation](VALIDATION.md) · [Formal scope](FORMAL-STATUS.md)

Start with the offline checks to confirm the release and selected sources.
Then choose a software reference run, a board test or a hardware rebuild.
All Python commands below use Python 3.12.

| Task | Start here | Requirements and result |
| --- | --- | --- |
| Check the delivered release | [Offline checks](#check-the-recorded-release-offline) and [source selection](#source-selection-check) | Python standard library; checks supplied files and recorded measurements. |
| Compute expected tokens | [Fresh reference](#reconstruct-the-model-and-run-a-fresh-reference) | Accepted model assets and the reference's Python dependencies; a new software computation. |
| Run or measure the FPGA | [Hardware checks](#repeat-hardware-checks-and-measurements) | Matching image/model and exclusive FPGA access; a new board capture. |
| Compile a new implementation | [Hardware rebuild](#rebuild-the-hardware) | Linux, Vivado 2025.2 and pinned HDK/IP/shell inputs; a new build needing its own validation. |

The [validation guide](VALIDATION.md) identifies the measured image and results.
[FORMAL-STATUS.md](FORMAL-STATUS.md) explains the proof boundary: no 8B-specific
solver suite is supplied, and 1.7B or SimpleStories proofs do not transfer.

## Check the recorded release offline

Run from the repository root:

```sh
python3.12 -I -S -B tools/verify_release.py --strict
python3.12 -I -S -B demos/qwen3-8b/tools/check_measurements.py
python3.12 -I -S -B demos/qwen3-8b/tools/check_package.py
python3.12 -I -S -B tools/check_qwen_disclosures.py
python3.12 -I -S -B tools/fpga_speed_benchmark.py --check
```

These commands use the supplied artifacts without AWS, model execution or FPGA
access. `--strict` rejects unlisted files. On a working copy with environments
or generated outputs, omit it rather than deleting local work.
The disclosure checker compares the management-display description with the
frozen top-level source and the CDC totals with the packaged report; routed
image correspondence and actual operand use require separate verification.

## Source selection check

From the repository root, run:

```sh
python3.12 -I -S -B demos/qwen3-8b/tools/check_configuration.py
python3.12 -I -S -B demos/qwen3-8b/tools/test_configuration.py
```

This is a quick check that the intended design reaches the build scripts.
It verifies file hashes, ordered Tcl source lists and their staging/synthesis
readers, the CL top, explicit prefetch setting and local includes. It prints
the selected source order; tests exercise missing or duplicate files,
unsupported dynamic lists, escaping paths and changed reader forms.
The 8B command uses the common helper in the sibling 1.7B demo with the 8B
inventory and root-ROM selection, so keep both demo tool directories.
These are static Python checks, not Tcl execution or HDL elaboration; no model,
vendor tools or output build directory is needed.

## Inspect the recorded CDC and reset reports

The [hardware guide](HARDWARE.md#cdc-and-reset-disposition) explains the reset
strategy and remaining physical questions. Its
[November 6 summary](evidence/cdc-reset-diagnostic-2026-11-06/SUMMARY.json) supplies
gzip native CDC/methodology reports, two CLR timing examples, the original
checkpoint identity and exact report options. Host headers and output paths are
normalized, with original and derivative hashes recorded separately. This is
a recorded subset, not a fresh Vivado run or the complete private collection;
the checkpoint itself is not included in that subset.

## Reconstruct the model and run a fresh reference

Follow [model preparation and reference execution](README.md#prepare-the-fixed-model).
The pinned exporter reconstructs the accepted model image; the reference
regenerates a three-token continuation and repeats it after CLEAR. These are
fresh software computations, separate from the recorded hardware captures.

Fetching missing upstream assets uses the network. Retain the required
notices and verify the fixed model-image identity before using it. Agreement
on selected cases is not an all-prompt correctness theorem or a comparison
against upstream floating-point Qwen.

### Local numerical reproduction

For a broader software run, the [CPU campaign guide](reference/CAMPAIGNS.md)
compares the fixed reference with token IDs for three recorded prompts. Its
[197-output result](evidence/software-campaign-2026-11-05/README.md) is a finite
CPU check. The [component harnesses](tests/rtl/README.md) and
[RMSNorm harness](tests/rtl/RMSNORM.md) cover their named arithmetic/protocol cases.

## Repeat hardware checks and measurements

Follow [INSTALL.md](INSTALL.md) for the matching public image, model upload,
self-test, token-ID generation and shutdown. Obtain exclusive use of the FPGA
slot before loading or testing it. The package uses a command-line client;
it does not supply an 8B browser interface.

For a comparable speed measurement, follow the
[common FPGA benchmark](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md): one input
token, 128 feedback-dependent outputs and two complete trials, using its stated
timestamp and numerical-check rules. The offline checker recomputes recorded
rates; a new hardware run needs its own capture and source/image bindings.

## Rebuild the hardware

Use the [hardware/source-build guide](HARDWARE.md) for the pinned vendor environment,
staged sources, synthesis, placement and routing. Obtain the vendor dependencies
through their documented distribution channels. Preserve outputs in a fresh
build directory.

Review a rebuilt implementation's full timing, routing, CDC/reset and exception
reports, create its independently identified image through the AWS workflow,
and repeat numerical hardware tests. The released image's measurements do not
qualify another build.

