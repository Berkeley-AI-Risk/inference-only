# Reproduce SimpleStories assets and evidence

The package supplies one selected image for each of the baseline,
K/V-protected, encrypted-memory and seeded configurations. Exact model/image
and source associations are in [greedy qualification](GREEDY-QUALIFICATION.md)
and [seeded qualification](CURRENT-QUALIFICATION.md). All use the same pinned
SimpleStories-V2-5M numerical model. Their proof boundaries are separate.

For running the prebuilt web demonstration, follow
[PROGRAMMING.md](PROGRAMMING.md) and the [host guide](host-app/README.md).
Offline record checks below operate no FPGA, programmer, network or solver.
Fresh asset reconstruction and fresh proof commands are explicitly separate.
Run all examples from the SimpleStories demo directory (`demos/simplestories-v2-5m/`).

## Check the supplied release and recorded results

Use Python 3.12 and install the pinned host dependencies for tokenizer checks.
On a clean copy, run:

```sh
python3.12 -I -S -B ../../tools/verify_release.py --strict
python3.12 -I -B tools/check_current_three_greedy_v15_v4.py --package . --stage current --index evidence/current-greedy/INDEX.json
python3.12 -I -S -B tools/check_current_seeded_recorded_v1.py --require-complete
python3.12 -I -S -B formal/current-seeded-sampling/check_recorded.py --require-complete
python3.12 -I -S -B ../../tools/fpga_speed_benchmark.py --check
python3.12 -I -S -B tools/estimate_training_capacity.py --check
python3.12 -I -S -B ../../tools/architecture_work_counts.py --check
```

`--strict` rejects unlisted extras, including local environments and generated
files. On a working copy omit that flag to check listed files while preserving
local work. Do not delete local files merely to satisfy a strict release check.

The greedy checker replays captured model/native observations, scoped proof
queries, source associations, mapped censuses, raw CLI/browser records and the
shared host's recorded tests. It does not execute the numerical model, a vendor
build or a solver again. The seeded check retains its recorded host-source
context; shared-host fixture checks do not grant a fresh seeded browser run.
The benchmark independently recomputes the common rates from selected captures.
The ordinary CI also runs scoped helper/control and analysis tests.

## Prerequisites

Use Python 3.12 for the numerical environment. The canonical quantization
manifest records NumPy 1.26.4; a newer NumPy version is not interchangeable
merely because the model's apparent outputs look similar. For fresh RTL proofs, use the toolchain pinned by the named formal replay.
Use a whitespace-free work path (an existing alias is acceptable).

Choose a dedicated asset directory **outside the source repository**. Replace
the example absolute paths below with your own paths. The downloader accepts
only the six pinned, hash-checked model/tokenizer data files and does not run
upstream model code. Retain the downloaded upstream notices.

```sh
python3.12 -m venv ../fpga-reference-env
../fpga-reference-env/bin/python -m pip install -r reference/requirements.txt
../fpga-reference-env/bin/python -I -B reference/scripts/fetch_upstream.py /absolute/asset-directory/upstream
../fpga-reference-env/bin/python -I -B reference/scripts/quantize.py /absolute/asset-directory/upstream /absolute/asset-directory/rom
```

The first command that fetches assets uses the network. Once the snapshot is
present, `fetch_upstream.py --check` is strictly offline. The quantizer computes
all eight canonical artifacts from the pinned checkpoint; `--check` recomputes
them and compares exact bytes without writing.

## Selected images and source builds

The supplied BUILD.json files identify completed native routes and exact
hardware-input inventories. The baseline has 90 inputs, K/V protection 93,
encrypted memory 100 and seeded sampling 91. Each includes four pinned vendor
inputs acquired separately. Source-to-mapped equivalence and complete
vendor-DDR timing signoff are not established.

For a recipient source build, use [VENDOR-SETUP.md](VENDOR-SETUP.md).
A new route needs its own functional and physical checks; the supplied image's
recorded results do not automatically qualify a rebuilt image.
For byte-exact ciphertext reconstruction with public demonstration keys, use
[encrypted-memory reproduction](ENCRYPTED-MEMORY.md#reproduce-and-inspect-the-package).

## Fresh scoped RTL proofs

[FORMAL-STATUS.md](FORMAL-STATUS.md) names each current theorem, unrestricted
private-service boundary and unresolved conclusion. The seeded
[replay guide](formal/current-seeded-sampling/README.md) gives its pinned
toolchain and complete primary/secondary and page-bank commands. Use fresh
output directories in a disposable copy; preserve the delivered manifest and
captured evidence. Greedy portable checks recheck the supplied named proof
queries and outcomes; they do not imply a new solver execution or a
whole-machine proof.

## Inference-only implementation checks

The [implementation-assurance guide](formal/implementation-assurance/README.md) provides a portable recorded-evidence check and separate commands for fresh RTL compilation, solver phases and exact source/query reproduction. These checks do not access the FPGA.

## Authentication and restricted access checks

From `demos/simplestories-v2-5m/`:

```sh
python3.12 -I -S -B formal/authentication-access/check_recorded.py
```

This checks exact recorded evidence and current source/image bindings without a
solver or FPGA. The [guide](formal/authentication-access/README.md) gives fresh
selected-query solver replay, source/model audit scope, cryptographic assumptions
and unresolved secondary results.
