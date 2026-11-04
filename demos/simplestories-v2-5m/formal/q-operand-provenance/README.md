# Baseline Q operand provenance

The baseline SimpleStories Q projection consumes the fixed model coefficients
and the matching current accepted activation at every native MAC input. Current
row metadata is preserved through serialization, tile RAM, synchronous reads
and both postscale coefficient inputs. The result covers six layers, four
groups per layer, 256 columns and all 64 lanes. Read the [theorem and diagram](THEOREM.md)
for its exact meaning, assumptions and limits.

The [main formal statement](THEOREM.smt2) is SMT-LIB, with four named predicates
expanded in [conclusions.smt2](conclusions.smt2). These are exactly the statement
bytes loaded by the engine project. The source-bound proof uses the native
SystemVerilog transition systems, total accepted-event histories, reset bases,
unbounded induction, complete case joins and literal provider applications.
Python orchestrates source checks and the engines; compiling Python is not a
verification of the hardware.

[QUALIFICATION.json](QUALIFICATION.json) records the completed reproduction;
the [full fresh-run receipt](FRESH-RESULT.json) supplies its detailed results.
There are **449 exact obligations: 438 UNSAT and eleven expected SAT contexts**.
The selected engines are recorded per obligation. The package also checks eight
native operating/actual-defect cases, 52 logical refusal controls and three
source-instrumentation refusals. Counts overlap with supporting work and are not
a coverage percentage.

Run from `demos/simplestories-v2-5m/`:

```sh
python3.12 -I -S -B formal/q-operand-provenance/run.py --recorded-only
```

This needs only Python 3.12 and validates all canonical query hashes, raw
answers, source reconstruction, native property definitions and exact provider
substitutions. It also validates the separately published upstream memory
packet. It starts no solver and leaves the checkout unchanged.

For fresh qualification, choose a new output directory outside the checkout:

```sh
python3.12 -I -S -B formal/q-operand-provenance/run.py --out /path/to/q-proof-fresh
```

The fresh entry recompiles the parent and cache, requires byte-identical native
transition models, runs all 449 obligations and all eight native controls, then
checks the complete derivation. It uses at most eight independent workers,
600 seconds and 8 GiB per query. Each completed query and raw reply is saved
before final qualification. The tested tool versions are in [TOOLCHAIN.json](TOOLCHAIN.json).
A timeout, unknown answer, changed source or missing provider fails qualification.
The unchanged 1,411-query upstream memory campaign is checked as recorded
support, rather than rerun by this entry.

`project.tar.gz` contains the current proof project, source construction and
compiler recipes, unmodified native projection subtree, histories, declarative
plans and rule checker. Native bodies are stored once; canonical queries are
reconstructed and matched to [EVIDENCE.json](EVIDENCE.json). No historical failed
candidates or obsolete runnable hardware images are included.

The parent control model leaves 19 other numerical leaves unrestricted. Its
previously qualified control construction and inherited readonly observations
remain explicit source evidence; this work adds no HDL observers. The checked
transition weakening omits only native MAC product/accumulator register updates.
It proves operand provenance, without establishing arithmetic-result correctness.

The theorem retains vendor storage behavior, the trusted model image at runtime
entry, static metadata-ROM/model binding and digital RTL/clock/reset boundaries.
The finite Q operating fixture uses a model-word test provider; its simulation
is not a replacement for the separately composed upstream memory proof.
The numerical Q result, normative RMSNorm arithmetic, remaining consumers,
attention/K/V behavior, protected variants and whole-device inference-only
theorem remain open.
