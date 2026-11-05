# Baseline RMSNorm through Q and retained query RAM

This package connects the actual SimpleStories RMSNorm stage to the complete Q
operator and its retained query payloads. Its input boundary is the hidden
vector, exponent and role fixed at actual RMS stage admission. It establishes
independent numerical meaning through the real RMS workspace, Q admission and
capture, Q arithmetic/normalization, query writes and tagged reads before
overwrite. It does not establish the whole-device inference-only theorem.

Read [the theorem and diagram](THEOREM.md), the concrete preserved-record
predicate in [STATEMENT.smt2](STATEMENT.smt2), and the publication qualification
receipt. The [Q operator package](../q-operator/README.md) is an unchanged pinned
dependency, including its operand and upstream memory-path proofs.

The proof uses native RTL translated by Yosys, SMT-LIB implications checked by
Z3/cvc5, and explicit source specialization and trace-induction applications.
The replay checker reconstructs the exact original and actual solver inputs,
raw answers, premises and applications. Typechecking the readable statement or
running Python without the checked engine evidence is not hardware verification.

From this directory in a full repository checkout:

```sh
python3 run.py --model ../.. --out /tmp/rms-q-replay
python3 run.py --model ../.. --out /tmp/rms-q-recorded --recorded-only
```

Use a new output directory each time. The default replay recompiles the four new
native models, typechecks the selected original theories and freshly reruns the
selected composition checks. All 554 selected new query/reply pairs and the
pinned Q/operand/upstream receipts are reconstructed. `--all-new-engines` also
reruns every selected new solver obligation. `--recorded-only` reconstructs
recorded evidence without invoking formal engines, compilers or simulators.
The receipts distinguish fresh checks from reconstructed dependencies and finite
operating evidence.

`project.tar.gz` contains the source-bound project, independent numerical
references, native source/SMT/graphs, declarative plans, exact source bindings and
finite operating records. It excludes failed proof candidates and generated
simulation builds. Solver inputs are reconstructed from the frozen plans;
`EVIDENCE.json`, `CENSUS.json` and `PACKAGE.json` bind the selected inputs/replies
and released files. The top qualification receipt governs the connected claim;
component records do not independently qualify the whole circuit.

The baseline source/model, vendor storage and digital implementation boundaries
are explicit in the theorem. Other numerical leaves, the incoming vector's
whole-graph meaning, Q-RoPE arithmetic, timing/fault authorization, other
configurations and physical implementation equivalence remain outside this
segment.
