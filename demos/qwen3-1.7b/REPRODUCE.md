# Reproduce Qwen3-1.7B assets and evidence

[Guide](README.md) · [Validation](VALIDATION.md) · [Formal scope](FORMAL-STATUS.md)

Recorded-evidence checks, fresh model computations and FPGA/source-build work
are separate operations. Use Python 3.12 for the commands below. The
[validation page](VALIDATION.md) identifies the released image and evidence;
[FORMAL-STATUS.md](FORMAL-STATUS.md) summarizes the component RTL results and
open obligations. This release supplies a [source-bound status record](evidence/formal/STATUS.json),
rather than the complete development solver/evidence bundle. The commands
below check the supplied records and do not rerun the formal campaigns.

## Check the recorded release offline

Run from the repository root:

```sh
python3.12 -I -S -B tools/verify_release.py --strict
python3.12 -I -S -B tools/check_qwen_measurements.py
python3.12 -I -S -B tools/check_qwen_package.py
python3.12 -I -S -B tools/fpga_speed_benchmark.py --check
```

These checks use the supplied files and recorded observations. They do not
contact AWS, run a model, execute a solver or access an FPGA. `--strict` rejects
unlisted files; on a working copy with environments or generated outputs, omit
that flag rather than deleting local work to satisfy the clean-release check.

## Reconstruct the model and run a fresh reference

Follow [model preparation](INSTALL.md#prepare-the-fixed-model), then use the
[numerical-reference guide](reference/README.md) to regenerate expected tokens
from the accepted model image. It specifies dependencies, CPU/MPS options,
smoke/full workloads and the numerical acceptance boundary.

Fetching missing upstream assets uses the network. Retain the required
notices and verify the fixed model-image identity before using it. Agreement
on selected cases is not an all-prompt correctness theorem or a comparison
against upstream floating-point Qwen.

## Repeat hardware checks and measurements

Follow [INSTALL.md](INSTALL.md) for the matching public image, model upload,
known-answer tests and shutdown. The [browser checks](BROWSER.md#checks) provide
recipient-controller checks. Obtain exclusive use of the FPGA slot before
loading or testing it.

For a comparable speed measurement, follow the
[common FPGA benchmark](../../docs/benchmarks/FPGA-SPEED-BENCHMARK.md): one input
token, 128 feedback-dependent outputs and two complete trials, using its stated
timestamp and numerical-check rules. The offline checker recomputes recorded
rates; a new hardware run needs its own capture and source/image bindings.

## Rebuild the hardware

Use the [hardware/source-build guide](HARDWARE.md#rebuild-from-source) for the pinned vendor environment,
staged sources, synthesis, placement and routing. Obtain the vendor dependencies
through their documented distribution channels. Preserve outputs in a fresh
build directory.

Review a rebuilt implementation's full timing, routing, CDC/reset and exception
reports, create its independently identified image through the AWS workflow,
and repeat numerical hardware tests. The released image's measurements do not
qualify another build. Formal proof work is separate from these reproduction
steps; SimpleStories' proofs do not qualify Qwen.
