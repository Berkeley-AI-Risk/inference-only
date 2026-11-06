# Seeded-sampling RTL verification

The selected SimpleStories-V2-5M seeded image is
`d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`.
[CURRENT-REPLAY.json](CURRENT-REPLAY.json) binds the exact sources, tools,
queries and recorded outcomes using schema
`current-seeded-rtl-formal-replay-completion-v2`.

The scoped RTL results are:

- 35 selector, 57 buffer-ownership, 63 UART/frontend and 94 token-shell
  assertions, checked by both solvers. These counts overlap.
- All 196 connected assertions pass Z3. cvc5 passes the base and 194
  conclusions; CRC conclusions 38 and 73 remain unresolved.
- The separate weight-page bank passes 42 assertions with both solvers,
  retaining its real 32,768-bit RAM and arbitrary 258-bit SHA replies.
- Directed scenarios and deliberately faulty controls check sensitivity
  within their recorded finite scopes.

The source provider checks 87 distributed native files and the selected image.
The 91-input native inventory also records four vendor digests. This provenance
check does not prove vendor logic or source-to-mapped-image equivalence.
The connected model retains 37 arbitrary private-output boundaries.
SHA compression arithmetic, private-bank/SHA composition, numerical sampling
equivalence and whole-machine refinement are not established.

[The formal-status guide](../../demos/simplestories-v2-5m/FORMAL-STATUS.md)
describes the properties and limits. Hardware/browser qualification is separate.

From the repository root, check the recorded completion without running solvers:

```sh
python3.12 -I -S -B formal/current-seeded-sampling/check_recorded.py --require-complete
```

For a fresh replay, use a clean disposable copy of the selected release and
new output directories. Preserve the original copy and its manifest:

```sh
python3.12 -I -S -B formal/current-seeded-sampling/check_recorded.py
python3.12 -I -S -B formal/current-seeded-sampling/test_replay.py
python3.12 -I -S -B formal/current-seeded-sampling/replay.py --run formal/current-seeded-sampling/runs/NEW-combined --secondary --require-recorded-model
python3.12 -I -S -B tools/check_current_seeded_page_bank.py --package . --work ../NEW-current-seeded-page-bank
```

The combined command checks the RTL components, connected model, source and
observer audits, finite sensitivity controls and all 196 secondary conclusions.
Only CRC conclusions 38 and 73 may remain unresolved; they are not counted
as proofs. The page-bank command is a separate scoped proof.
