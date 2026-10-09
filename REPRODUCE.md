# Reproduce the model assets and scoped proofs

The baseline numerical/controller replays retain their configuration scope.
The protected K/V replay is bound to the supplied protected source set;
its proof monitor observes the packed value rows. Its assertions and
abstraction boundaries are listed in [FORMAL-STATUS.md](FORMAL-STATUS.md).
The third version uses the same plaintext model as its
starting point; see [encrypted-memory reproduction](ENCRYPTED-MEMORY.md#reproduce-and-inspect-the-package)
for its ciphertext, build sources and separate test scope.

These commands are for the source package root. They do not program the FPGA,
invoke a vendor build, or publish anything. They are optional for running
the prebuilt demo; start with [PROGRAMMING.md](PROGRAMMING.md) for that path.
The exact model image and tokenizer are included; these commands independently
reconstruct their provenance from the pinned original model checkpoint.

The baseline model/controller replays use the selected sources in `hardware/`,
including four-round-per-cycle weight-page hashing and packed attention-value storage.
The [selected replay record](evidence/baseline-current/replay.json)
records full-model, token-shell, page-bank and connected-shell runs.
Other component checks have their own source-bound receipts.
The K/V-protected variant has a separate
[guard simulation replay](simulation/kv-protected/README.md),
[scoped formal replay](formal/kv-integrity/README.md), and
[evidence summary](KV-PROTECTION.md#evidence-and-limits). The protected formal replay
is run separately; the baseline command does not include it.
Neither establishes whole-machine refinement. The same model image and
tokenizer serve both variants.

## Prerequisites

Use Python 3.12 for the numerical environment. The canonical quantization
manifest records NumPy 1.26.4; a newer NumPy version is not interchangeable
merely because the model's apparent outputs look similar. For proof and RTL
replays, use the [recorded toolchain below](#formal-toolchain-and-replay-results).
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

## Formal toolchain and replay results

The proof replays check both proof results and their connection to the audited
source. Some also require generated files to match the audited snapshots
byte-for-byte. A newer toolchain is not necessarily interchangeable.

| Tool | Recorded version | Used for |
| --- | --- | --- |
| Lean | 4.33.1 (`leanprover/lean4:v4.33.1`) | Abstract machine specification |
| Yosys | 0.68+post, commit `c12172fbae8af5e20f6fb52e3d4e92d56ed587b6` | RTL elaboration and formal queries |
| Z3 | 4.14.1 | Primary RTL proof obligations |
| cvc5 | 1.3.1 | Independent solver checks |
| Verilator | 5.050 | Connected-shell, backup-reader and full-model simulations |

The directed UART and weight-bank traces additionally require Icarus Verilog
(`iverilog` and `vvp`). Tool installers are not bundled. Install the exact Lean
toolchain before an offline replay; otherwise its launcher may download it.
Before a lengthy run, compare `yosys -V`, `z3 -version`, `cvc5 --version` and
`verilator --version` with the table. The protected-K/V replay accepts explicit
`--yosys`, `--z3` and `--cvc5` paths, so a different default installation need
not be removed. Other wrappers have their own options; consult `--help`.

The exact K/V replay records this full elaborator identity, including compiler:

```text
Yosys 0.68+post (git sha1 c12172fbae8af5e20f6fb52e3d4e92d56ed587b6, Release, AppleClang clang++ 21.0.0.21000101)
```

It checks all three formal-tool version strings before starting and still
requires the generated model/query identities to match afterward. A build
with another compiler can differ even at the same Yosys commit. This is a
toolchain-pinned offline replay; cross-platform byte identity is not established.
Use `--serial-stages` and a smaller `--jobs` value on a smaller machine.
Python `-O`/`-OO` is rejected because it disables the scripts' assertions.

Interpret a failed replay according to what failed:

- **Generated-file identity mismatch:** the generated source or query differs
  from the audited snapshot. A different Yosys build can cause this even when
  the solver obligations pass. The mismatch is not itself a counterexample,
  but the exact replay has not passed. Use the recorded toolchain; do not
  replace expected hashes to make the check pass.
- **Solver `unknown` or timeout:** that solver has not resolved the obligation.
  This is neither a proof nor, by itself, a counterexample. An independent primary
  proof result remains distinct from an incomplete second-solver check.
- **Unexpected solver answer:** inspect the named query and its log. A `sat`
  result where `unsat` is required fails that proof obligation. An induction
  counterexample does not necessarily show a reset-reachable hardware bug.
  Conversely, `sat` is expected for deliberately faulty controls and reuse
  witnesses; those tests must be judged against their own expected answers.
- **Tool or audit error:** missing executables, nonzero tool exits, malformed
  output or source changes also fail the replay. They are not proof results.

The wrappers retain logs in the requested work directory and identify failed
stages. Tape and K/V checks also report unresolved or unexpected per-query
answers. Required second-solver checks still fail on `unknown`; none is silently
accepted. The connected-shell replay's optional second solver has its separately
documented incomplete-result policy below. See [FORMAL-STATUS.md](FORMAL-STATUS.md)
for what each proof establishes.

## Selected FPGA image

```sh
../fpga-reference-env/bin/python -I -B tools/materialize_image.py \
  --reference-root reference \
  --rom /absolute/asset-directory/rom \
  --hardware-project hardware/project \
  --output /absolute/asset-directory/fpga-image
```

This independently reconstructs the selected 7,265,984-byte DDR image, checks
every serialized W10 field by unpacking it, and requires the exact image hash
`cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0`.
It also regenerates and compares all four synthesis memory files: fixed
normalization data, exponential lookup data, projection scale metadata and
the SHA-256 page-digest ROM. The final page is zero-padded to 4,096 bytes for
its page digest, matching the hardware bank's hash convention. Add `--check`
to verify the already materialized directory without modifying it.

**This image is not a whole-flash programming file.** It belongs at byte
offset `0x00801000` in the demonstrated flash layout. The selected boot reader
starts directly at that offset; it does not consume an older metadata header
at `0x00800000`. The demonstrated full array has erased (`FF`) bytes everywhere
outside the model, with the FPGA configuration loaded separately into SRAM.
See [PROGRAMMING.md](PROGRAMMING.md) for the exact layout, file-only checks and
reader/recovery procedure. Do not write the model at flash offset
zero or overwrite a factory image using this document alone.

## One offline verification command

First install the separate host dependencies as described in
[host-app/README.md](host-app/README.md). Keep that environment separate from
the NumPy-1.26.4 numerical reference environment. With the model snapshot and
canonical ROM directory present:

```sh
../fpga-reference-env/bin/python -I -B tools/verify_package.py \
  --upstream /absolute/asset-directory/upstream \
  --rom /absolute/asset-directory/rom \
  --app-python /absolute/path/to/host-app/.venv/bin/python \
  --work ../fresh-verification-run
```

Use `--lean`, `--yosys`, `--z3` and `--cvc5` to supply explicit tool paths if needed.
The work directory must not already exist and must be outside this package.
The command verifies the complete source inventory, recomputes Q0 artifacts,
materializes the FPGA image and four ROMs, runs all six curated numerical
cases, checks the Lean specification, and replays the UART induction proof
and three deliberately broken formal negative controls. It additionally proves
the expanded 46-assertion UART frame/response monitor and runs its directed
serial tests and five faulty simulation controls. It also copies the portable
host app into the fresh work directory and runs its offline tests with the
pinned tokenizer; no browser server or physical UART is opened. A negative control is
expected to return a proof counterexample; a timeout is not a passing negative.
Logs, source copies needed by proof tools, and the final scoped result are
kept in the work directory. The source package must remain byte-identical.

The additional controller/tape job proves 48 assertions with the real local
arithmetic and 17 memories retained. It checks the read-only symbolic observer,
all 3,328 normalization ROM words and the exact source/SMT binding. Z3 proves
the joint induction; cvc5 checks its base and all 48 conclusions, up to 12 in
parallel. Five deliberately broken tape implementations must yield bounded
counterexamples; the unchanged implementation must not. Two reuse witnesses
exercise reset/CLEAR with old RAM contents retained and then overwritten.
These are scoped component results, not complete model or machine refinement.

To replay just that stage without numerical-model or host dependencies:

```sh
python3 -I -B -S tools/check_token_shell.py --package . --work ../fresh-tape-proof
```

The local typed K/V job checks 59 further assertions with the real controller,
both address mappers and unreset payload registers. Both solvers check the base
and every induction conclusion; five faulty controls and two retained-staging
reuse witnesses are required. Source, query, elaboration and observer fanout
audits are included. External DDR contents remain component inputs, so this
does not prove external-memory epoch integrity or complete machine refinement.
To replay just that stage:

```sh
python3 -I -B -S tools/check_kv_epoch.py --package . --work ../fresh-kv-proof
```

The public-command job joins the actual UART and three-operation adapter using
the selected top's instance wiring. It proves 60 properties jointly: the 46
bridge properties plus 14 operation/operand/return connection properties.
The machine backend is explicitly excluded; its inputs remain arbitrary.
Yosys proves the base and induction, Z3 checks the same joint result, and cvc5
checks all 60 conclusions under the same joint prior invariant. Its induction
queries use `--bitblast=eager --ackermann`; timeouts are failures, not proofs.
Ten serial scenarios and five faulty simulation controls accompany the proof.
Source, interface and raw-log audits run again after the solvers. To replay
this stage alone, without numerical-model or host dependencies:

```sh
python3 -I -B -S tools/check_public_commands.py --package . --work ../fresh-command-proof
```

The standalone command accepts explicit `--yosys`, `--z3`, `--cvc5`,
`--iverilog` and `--vvp` paths. It neither programs nor contacts a physical
board. The 60 properties include the 46 bridge properties, not 60 extra ones.

The abstract Lean token-generation function is not a numerical model proof.
The UART proof checks 46 invariants under two-state clock/reset semantics,
using the actual source and 217-clock UART. This is not whole-machine refinement,
physical-tamper resistance or vendor netlist equivalence. See
[FORMAL-STATUS.md](FORMAL-STATUS.md). A successful replay must not be described
more broadly. The five UART trace negatives are simulation counterexamples;
the five controller/tape negatives are reset-reachable SMT counterexamples.

## Connected command/controller replay and auxiliary checks

The full offline command also checks the sanitized photograph, six flash-layout
file guards, ten backup-receiver tests, three shortened backup-reader RTL
simulations, and the connected 134-property primary proof with its serial
fault controls and source/cut/observer audit. These checks access no board.

It also rebuilds the [full-model RTL bench](simulation/model/README.md) from
64 byte-identical production sources and four ROMs. Four cases exercise real
inference with/without DDR stalls, CLEAR/replay, boot-weight corruption and
post-boot page corruption. Checker tests ensure missing observations,
wrong or extra tokens, fatal messages and timeouts cannot be reported as a
passing model simulation. Flash and the DDR PHY are behavioral fixtures;
this is not an electrical or whole-machine proof. These four simulations
redo full boot authentication. Allow tens of minutes; a four-case replay has
been reported at roughly 25 minutes with four cases running concurrently.
Elapsed time depends on the host and toolchain, and compilation adds work.

To replay just the full-model simulations after materializing the image:

```sh
python3.12 -I -S -B tools/check_model_rtl.py \
  --package . \
  --image /absolute/asset-directory/fpga-image/board1-real-semantic-image2048.bin \
  --work /absolute/space-free/path/to/fresh-model-rtl-run
```

`--image` takes the **binary file**, not the `fpga-image` directory produced by
`materialize_image.py`. The included `assets/board1-real-semantic-image2048.bin`
can also be used. By default, compilation uses eight workers and the four
cases run concurrently. `--build-jobs` and `--jobs` adjust those counts;
`--timeout-seconds` sets each case's limit (default 1,800 seconds). Increase
that limit for a slower host; a timed-out case is never counted as passing.

To replay the connected proof alone:

```sh
python3.12 -I -S -B tools/check_composed_shell.py \
  --package . --work /absolute/space-free/path/to/fresh-composed-proof
```

Add `--second-solver --seconds-per-query 900` to check all 134 conclusions
with cvc5. The recorded secondary result is 133 proved, one checksum
conclusion unresolved; a clean `unknown` is reported as incomplete. The
default replay requires Z3 to prove all 134, matches the selected audited queries,
and checks structure/simulation, but does not rerun cvc5 for this stage.
Its success is not a complete second-solver or whole-machine proof.

The auditor checks the secondary queries against the same primary formulas.
The command above gives every conclusion a 900-second allowance; elapsed
time and which queries finish can vary.
The array strategy is the tested one. The lower-level script's experimental
`--mode eager` option is rejected by this cvc5 build for these queries and
must not be treated as proof evidence.

The standalone UART/adapter, tape and local K/V stages require complete
checks by both solvers. See [FORMAL-STATUS.md](FORMAL-STATUS.md) for all boundaries.
The [backup helper](maintenance/flash-reader/README.md) is a separate maintenance
configuration; it is not included in the inference bitstream.

## Sealed weight-bank replay

The complete offline command also runs the 42-property bank proof with both
solvers, ten directed scenarios, five faulty variants, and the source/query/
observer audit. It retains the real 128-by-256-bit RAM but treats the SHA
compressor's replies as arbitrary; this is not a cryptographic or whole-chip
proof. Its generated sources and formulas must match the originally audited
result exactly. To run only this stage:

```sh
python3 -I -S -B tools/check_page_bank.py --package . --work ../fresh-bank-proof
```

The standalone command accepts `--yosys`, `--z3`, `--cvc5`, `--iverilog` and
`--vvp`. See [the detailed scope](formal/page-bank/README.md). This stage
does not need the model checkpoint, host dependencies or FPGA access.

## Release analysis and helper tests

The conditional training-capacity calculation is an additional offline check,
not a new hardware or security proof:

Run the commands below from a clean checkout or release archive, before
creating a local environment or build outputs. `--strict` verifies every
listed file and also rejects extra files, including ignored files such as
`host-app/.venv/`, Lean's `.lake/` directory, and `lake-manifest.json`.
In a working checkout containing those files, omit `--strict` from the first
command: every listed file is still checked, but extra files are permitted.
There is no need to delete your environment or build outputs to do that check.

```sh
python3.12 -I -S -B tools/verify_release.py --strict
python3.12 -I -S -B tools/estimate_training_capacity.py --check
python3.12 -I -S -B tools/architecture_work_counts.py --check
python3.12 -I -S -B tools/check_h100_reference.py
python3.12 -I -S -B -m unittest discover -s tools -p 'test_*.py' -v
```

See [TRAINING-CAPACITY.md](TRAINING-CAPACITY.md) and
[ARCHITECTURE-DEPENDENT-CAPACITY.md](ARCHITECTURE-DEPENDENT-CAPACITY.md) for the
access assumptions, workload definitions and counting conventions. These tests
do not open a UART, program a board or benchmark a GPU.

The [offline-check workflow](.github/workflows/offline-checks.yml) runs these
standard-library checks on pushes to `main` and pull requests, or when started
manually. It uses a read-only repository token and does not publish anything.
It does not rerun the formal solvers, model simulations, host app, vendor
implementation, physical board tests or H100 benchmark. A green result means
only that this small offline suite passed, not that the hardware is certified.

The separate [H100 benchmark guide](benchmarks/h100/README.md) explains how
to reproduce the GPU measurements on a single H100 SXM. Running that benchmark
requires its own environment and GPU; inspecting the saved measurements and
reproducing the conditional ratios does not. Neither is required to run the FPGA.

The exact build input inventory retains some compiled but uninstantiated
modules; [ARCHITECTURE.md](ARCHITECTURE.md#weight-projections-and-tied-head)
identifies them. Do not remove them when reproducing the source-bound image.
The project/source list also names four intentionally absent `official/`
inputs. Obtain them using [VENDOR-SETUP.md](VENDOR-SETUP.md) and build in the
separate work directory described there, not directly in the release tree.
`hardware_inputs_sha256` hashes the canonical compact, sorted JSON inventory
plus a newline, not the pretty-printed inventory file's bytes.

For a clean distributable archive, use `git archive` from a specific repository
commit, or disable macOS metadata copying when archiving an export.
Finder compression can add `._*` sidecars. Extract the archive to a fresh
directory and run `tools/verify_release.py --strict` there; local environments
and user logs are not release files. Record the commit and manifest hash so
readers can identify the exact archived version.
