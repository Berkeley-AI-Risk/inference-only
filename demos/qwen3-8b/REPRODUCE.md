# Reproduce Qwen3-8B assets and evidence

[Guide](README.md) · [Validation](VALIDATION.md) · [Formal scope](FORMAL-STATUS.md)

Recorded-evidence checks, fresh model computations and FPGA/source-build work
are separate operations. Use Python 3.12 for the commands below. The
[validation page](VALIDATION.md) identifies the released image and evidence;
[FORMAL-STATUS.md](FORMAL-STATUS.md) states that no Qwen-specific proof suite
is supplied here.

## Check the recorded release offline

Run from the repository root:

```sh
python3.12 -I -S -B tools/verify_release.py --strict
python3.12 -I -S -B demos/qwen3-8b/tools/check_measurements.py
python3.12 -I -S -B demos/qwen3-8b/tools/check_package.py
python3.12 -I -S -B tools/fpga_speed_benchmark.py --check
```

These checks use the supplied files and recorded observations. They do not
contact AWS, run a model, execute a solver or access an FPGA. `--strict` rejects
unlisted files; on a working copy with environments or generated outputs, omit
that flag rather than deleting local work to satisfy the clean-release check.

## Reconstruct the model and run a fresh reference

Follow [model preparation and reference execution](README.md#prepare-the-fixed-model).
The pinned exporter reconstructs the accepted model image; the reference
regenerates a three-token continuation and repeats it after CLEAR. These are
fresh software computations, separate from the recorded hardware captures.

Fetching missing upstream assets uses the network. Retain the required
notices and verify the fixed model-image identity before using it. Agreement
on selected cases is not an all-prompt correctness theorem or a comparison
against upstream floating-point Qwen.

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
qualify another build. Formal proof work is separate from these reproduction
steps; SimpleStories' proofs do not qualify Qwen.
