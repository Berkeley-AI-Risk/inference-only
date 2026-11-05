# Baseline Q projection: source-bound value proof

The complete baseline Q value/prefix/completion argument is qualified for the
named SimpleStories RTL. Read [THEOREM.md](THEOREM.md) for the guarantee and diagram,
[THEOREM.smt2](THEOREM.smt2) for its machine-readable endpoint statements, and
[SPECIFICATION.md](SPECIFICATION.md) for the independent arithmetic definition.
The [qualification](QUALIFICATION.json) and [independent reviews](FINAL-PACKAGING-REVIEW.md)
state the evidence and limits. This is a functional-correctness component of the
whole-device inference-only proof, which remains open.

From the repository root, check the full recorded proof chain without formal tools:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/q-operator/run.py --recorded-only --out /tmp/q-recorded --model demos/simplestories-v2-5m
```

Use a new output directory. Omit `--recorded-only` for seven fresh native
recompilations and 17 selected fresh solver queries. Add `--all-new-engines` to
replay all 329 new engine obligations. Fresh runs need the tools and versions
listed in [TOOLCHAIN.json](TOOLCHAIN.json); recorded-only mode uses Python alone.
The readable statement is also checked against the frozen rules with:

```sh
python3.12 -I -S -B demos/simplestories-v2-5m/formal/q-operator/check_statement.py
```

The proof has 326 UNSAT implications and three SAT controls. Its actual
source/parameter/port bindings, reset bases, first-step bootstrap, joint regular
induction and all raw, normalized and rejection endpoints are reconstructed on
one trace. All original obligations are typechecked before any function
abstraction; those typechecks are not counted as proofs. The existing 449
operand and 1,411 upstream memory obligations are reconstructed as dependencies.

The fresh qualification replay reproduced every canonical and transformed query
byte, compiled all seven numerical models identically, and passed all 17 selected
queries. Six positive activation patterns cover all six layers/all 64 lanes;
seven source-only numerical defects are detected. Thirteen connected finite
cases regenerate source, bench and independent expected values during local
qualification. Two normalizer aggregate records retain source/bench/log checks,
12 reference cases and watchdog/CLEAR edge evidence. Portable default execution
validates saved simulation evidence; it does not rerun simulations.

The proof includes arbitrary stalls, named interruptions and cancellation. It
covers actual Q write admissions and the actual exponent register, while retained
query-RAM contents/readback, caller RMSNorm/whole-graph composition, other
operators/configurations, timed fault authorization and physical DSP/bitstream
equivalence remain outside this component result. No production hardware is changed.
