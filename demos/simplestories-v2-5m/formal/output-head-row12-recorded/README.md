# Recorded output-head row 12: original RMS record

The 256 input words saved for output-head row 12 and the exponent used by that
row come from the same final normalization on the same STEP. The proof retains
the original STEP, final-normalization launch, row identity and ordering, and
the previously qualified completed-row dot result through its accepted
producer/history dependencies.

This assumes the machine follows the saved controller and connected hardware
design, with the same clocks, resets and fixed settings. The other assumptions
are stated below.

This package checks **16 recorded native UNSAT results and 513 reconstructed
deductions** for the frozen native profile
`c07076ec5f5f4f27ca8208e502a0274b047552e5c356dc9bddaf03cd5b648b54`.
It does not establish upstream decoder/RMS numerical composition, the final
scaled score or selected token. It is not a proof of the public board image:
source equivalence to that image or current public RTL has not been established.

## Provision once, then replay

Use Linux and separately installed **CPython 3.12.12**, with assertions enabled.
The fixed `/proof` location is an explicit layout contract. Provision a new,
empty `/proof` directory owned by the replay user, or mount an empty directory
there in a Linux container. Allow 3 GiB memory and about two minutes; no solver,
compiler, vendor tools, weights, network or credentials are needed for replay.

Both archives travel in the repository, following the other formal packages'
archive plus `PACKAGE.json` convention. From the repository root, verify their
exact bytes before extracting into the empty directory:

```sh
proof_package=demos/simplestories-v2-5m/formal/output-head-row12-recorded
(cd "$proof_package" && sha256sum -c SHA256SUMS)
tar --no-same-owner -xzf "$proof_package/head-row12-project-replay-v1.tar.gz" -C /proof
tar --no-same-owner -xzf "$proof_package/historical-tool-data/z3-4.14.1-recorded-tool-data.tar.gz" -C /proof
```

Then run the one replay command:

```sh
python3.12 -I -S -B /proof/replay.py
```

Success reports `passed=true`, `recorded_native_leaves=16`,
`proof_nodes_reconstructed=513`, `reconstructed_result_byte_identical=true`
and `new_solver_jobs=0`. The complete 430-file inventory is checked before the
proof replay; the extracted directory can be mounted read-only for that command.
[QUALIFICATION.json](QUALIFICATION.json) and
[RECORDED-RESULT.json](RECORDED-RESULT.json) preserve the clean Linux result,
runtime identities and scope. The archives retain their qualified candidate
documentation and provenance literally; this README is the publication entry.

## Immutable artifacts

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| [Project replay](head-row12-project-replay-v1.tar.gz) | 15,128,211 | `91621c11cc469cc6853d988fc4abbfdcb206d95c2071f22229d332fc24df49e2` |
| [Historical tool data](historical-tool-data/z3-4.14.1-recorded-tool-data.tar.gz) | 6,321,985 | `8d556b8ae3277456978ed1150b53cf250a5c459b5cde4b456223fc48a1728104` |

The project archive has 429 members; the separate tool-data archive has two.
Their identical MIT-license member overlaps, giving 430 distinct provisioned
files. The exact macOS Z3 4.14.1 executable is **third-party MIT-licensed data**,
read and hashed to preserve the historical binary-identity checks. Its archive
mode is nonexecutable. It is never run on Linux or presented as project code or
a Linux solver. See [TOOL-NOTICE.md](TOOL-NOTICE.md).

## Assumptions and evidence boundary

The six inherited assumptions are that the machine follows that saved hardware
design and its clock/reset behavior; original reset-low samples 0 and 1 (two
separate anchors); the fixed
runtime-entry model image and lifetime; static metadata/model binding; and the
vendor-storage contract. Accepted producer/history exports remain prerequisites.
The full statement and explanation are inside the project archive at
`r-repository/inference-only/tang-greedy-speed/session-isolation/main-proof/head-row12-score-r1/engine-row-component-r1/THEOREM.md`
and the extracted root `README.md`.

Replay reconstructs the exact queries, checks recorded UNSAT protocol and native
receipts, and reruns deduction construction and type checks. It compares full
result and typing bytes. It does not perform fresh solving, regenerate RTL-to-SMT,
or independently check an UNSAT proof certificate. Neutral paths and transitive
file/structured-provenance hash and byte-length changes are explicit in the
extracted `RELOCATION.json`; mathematical formulas, all 36 SMT files, nine SV
files and the compilation script are unchanged. The portable result has its own
identity, distinct from the original path-bound seal. Project and third-party
notices are retained under their respective terms.
