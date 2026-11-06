# Reproduce SimpleStories assets and evidence

The package supplies six selected Tang configurations: four F-AWICs, a signed-update
S-AWIC and an S-AWIC with periodic reauthorization. The packaged base weights use
the fixed W10/A16/KV16 BFP-v5 numerical contract. Signed variants can admit other
compatible, signed weights; their references must match the admitted image.
[Greedy qualification](GREEDY-QUALIFICATION.md), [seeded qualification](CURRENT-QUALIFICATION.md)
and the signed variants' validation pages state separate evidence boundaries.

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
python3.12 -I -S -B formal/session-isolation/check_recorded.py
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
the example absolute paths below with your own paths. Keep both the asset directory
and `FPGA_REFERENCE_ENV` outside the entire checkout so strict release checking
does not encounter an unlisted Python environment. The downloader accepts
only the six pinned, hash-checked model/tokenizer data files and does not run
upstream model code. Retain the downloaded upstream notices.

```sh
FPGA_REFERENCE_ENV="/absolute/path/outside-the-checkout/fpga-reference-env"
python3.12 -m venv "$FPGA_REFERENCE_ENV"
"$FPGA_REFERENCE_ENV/bin/python" -m pip install -r reference/requirements.txt
"$FPGA_REFERENCE_ENV/bin/python" -I -B reference/scripts/fetch_upstream.py /absolute/asset-directory/upstream
"$FPGA_REFERENCE_ENV/bin/python" -I -B reference/scripts/quantize.py /absolute/asset-directory/upstream /absolute/asset-directory/rom
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

## Configuration and build authority

Each configuration has its own source inventory and FPGA image. The native
build uses `product.gprj` for enabled sources and constraints, and `run.tcl`
for the top module, language standards and implementation options.
`production_sources.f` lists HDL members; it does not replace that build recipe.

| Configuration | Selected input inventory | Native entry | Selected image SHA-256 prefix |
| --- | --- | --- | --- |
| F-AWIC baseline | [90 inputs](host-app/hardware-inputs.json) | [Project](hardware/project/product.gprj), [Tcl](hardware/run.tcl) | `01b040cb830c` |
| F-AWIC + K/V protection | [93 inputs](host-app/hardware-inputs-kv-protected.json) | [Project](variants/kv-protected/hardware/project/product.gprj), [Tcl](variants/kv-protected/hardware/run.tcl) | `90ac68150d0c` |
| F-AWIC + encrypted memory | [100 inputs](host-app/hardware-inputs-encrypted-memory.json) | [Project](variants/encrypted-memory/hardware/project/product.gprj), [Tcl](variants/encrypted-memory/hardware/run.tcl) | `cfc8a3d8832b` |
| F-AWIC + seeded sampling | [91 inputs](host-app/hardware-inputs-seeded-sampling.json) | [Project](variants/seeded-sampling/hardware/project/product.gprj), [Tcl](variants/seeded-sampling/hardware/run.tcl) | `d271626a7fb9` |
| S-AWIC | [105 inputs](variants/signed-update/tang/SOURCE-IDENTITY.json) | [Project](variants/signed-update/tang/hardware/project/product.gprj), [Tcl](variants/signed-update/tang/hardware/run.tcl) | `8472e592c68a` |
| S-AWIC + periodic reauthorization | [112 inputs](variants/home-authorization/SOURCE-IDENTITY.json) | [Project](variants/home-authorization/hardware/project/product.gprj), [Tcl](variants/home-authorization/hardware/run.tcl) | `92b334d6f160` |

Input totals include four separately acquired vendor files plus Tcl,
constraints and memory data. The linked inventories contain full source and
image hashes; the table shows image-hash prefixes.

The physical tops are:

- Four F-AWICs: `board1_fixed_shared_product_top`.
- Signed-update S-AWIC: `board1_fixed_swic_product_top`.
- Periodic-reauthorization S-AWIC: `board1_home_auth_product_top`.

| Configuration | Enabled Verilog / VHDL | Member-list scope |
| --- | ---: | --- |
| F-AWIC baseline | 81 / 0 | Complete Verilog members |
| F-AWIC + K/V protection | 83 / 0 | Complete Verilog members |
| F-AWIC + encrypted memory | 88 / 0 | Complete Verilog members |
| F-AWIC + seeded sampling | 82 / 0 | Complete Verilog members |
| S-AWIC | 91 / 0 | Complete Verilog members |
| S-AWIC + periodic reauthorization | 95 / 2 | 91 base members; project adds four Verilog and two VHDL files |

Normalized common-member order matches in these selected files. The home
project additionally includes `home/home_boot_gate.sv`,
`home/home_uart_transport.sv`, `home/home_product_top.sv`,
`home/nonce_frontend.sv`, `home/neoTRNG.vhd` and `home/entropy_source.vhd`.
Its inherited list is not a complete physical-home build recipe.

All selected `defines.v` files define `SYNTHESIS`. Baseline, seeded and both
signed variants also define `BOARD1_PROJECTION_MAC_NATIVE`; protected and
encrypted variants select their own arithmetic and memory implementations.
These defines and the Tcl settings belong to the selected input set.

All inference cores run at 25 MHz. DDR application transport runs at 100 MHz,
the memory PLL at 400 MHz, and the trusted domain at 12.5 MHz. Boot roles differ
by configuration: signed admission, hashing, LMS and home lease logic use the
25 MHz core. [Hardware](HARDWARE.md) and the signed guides show the connections.

For the four F-AWICs, use `host-app/build_hardware.py --variant` with
`baseline`, `kv-protected`, `encrypted-memory` or `seeded-sampling` and the
prerequisites in [VENDOR-SETUP.md](VENDOR-SETUP.md). Each signed variant uses
its own `tools/build_native.py` and authorized Standard compiler:
[signed-update reproduction](variants/signed-update/tang/REPRODUCE.md) or
[periodic-authorization reproduction](variants/home-authorization/REPRODUCE.md).
The inherited home list does not replace that wrapper/project/Tcl route.

`candidate.sv` implements the selected `board1_fixed_vector_rne_shift_pipeline1`
helper in all six projects. The selected attention module implements fixed GQA.
Use the input inventory and [qualification guide](README.md#implementation-and-evidence)
to identify the applicable implementation and tests; filenames and source
comments are not qualification records.

### Source selection check

From the SimpleStories demo directory:

```sh
python3.12 -I -S -B tools/check_configuration_sources.py
python3.12 -I -S -B -m unittest discover -s tools -p test_configuration_sources.py -v
```

The read-only checker compares all six source sets and image hashes with their
selected build records. It checks the top declaration, enabled files and list
scope. Use `--configuration home-authorization` for one row. Vendor files can
remain unacquired; add `--vendor-dir /absolute/path/to/fpga-vendor-inputs` to
verify an existing local copy. The checker neither downloads nor runs a
compiler, solver or FPGA. A passing result establishes file consistency.

The applicable evidence routes are [greedy qualification](GREEDY-QUALIFICATION.md),
[seeded qualification](CURRENT-QUALIFICATION.md), [formal scope](FORMAL-STATUS.md),
[signed-update validation](variants/signed-update/tang/VALIDATION.md) and
[periodic-authorization validation](variants/home-authorization/VALIDATION.md).
Replacement captures are image-bound; the periodic variant's validation page
separates its completed observations from the open repaired-controller test.
The linked guides state the remaining physical and numerical obligations.

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

## Normal K/V return evidence

The [normal returned-word guide](formal/kv-return/README.md) gives standard-library
recorded checks and fresh Yosys/Z3/Icarus replay from the supplied closed packet.
It states the checked component scope and imported-proof replay boundary.

## Native numerical and cache-value proofs

From the repository root:

```sh
python3.12 -B demos/simplestories-v2-5m/formal/native-component-values/run.py --recorded-only
python3.12 -B demos/simplestories-v2-5m/formal/native-component-values/run.py --out /tmp/simplestories-native-values
```

The [component guide](formal/native-component-values/README.md) pins the
compiler/solver versions and explains the RMSNorm and cache component theorems.
The cache's raw-read premise is discharged by the composed memory-path proof
below. The second command recompiles the
actual native subtrees, replays all 136 engine obligations and reruns finite
operating/defect controls. It writes to a new output directory without altering
the release. No FPGA access is required.


## Composed model-memory and cache-value proof

From the repository root:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/upstream-model-values/run.py --recorded-only
python3.12 -I -S -B demos/simplestories-v2-5m/formal/upstream-model-values/run.py --out /tmp/simplestories-upstream-values --workers 8
```

The [guide and theorem](formal/upstream-model-values/README.md) give the exact
scope and pinned tools. Fresh replay reconstructs/recompiles the native models,
runs all 1,411 queries and reruns the mixed-traffic and actual-only defect
controls. It needs no FPGA. Vendor storage, trusted startup image identity and
the static metadata-ROM/model binding remain stated boundaries.
