# Seeded-sampling evidence

These records identify the supplied SimpleStories-V2-5M seeded image `d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725`.

- [Model evidence](current-model-v4.json): 30 cases, 108 heads and 434,052 raw logit rows for the model-tested circuit.
- [CLI evidence](current-candidate-cli.json): all seven board suites, including eight matched 128-output trials and all 16 context cases.
- [Timing](current-timing-v8-baseline-selected-native.json) and [native summary](current-native-summary-v8-baseline-selected-native.json): exact image/source associations and command/reply durations. Temperature 1 measured 9.942238076 cached tokens/s over two 128-output trials. The named 2,048-token first STEP measured 352.237119291 seconds, excluding setup/upload.
- [Scoped source evidence](current-scoped-proofs-v4.json): seven modular scopes, separate cache-stage and exp-ROM source results, and finite mapped-ROM observations. This source-binding action is distinct from a solver run.
- [Current formal completion](../../formal/current-seeded-sampling/CURRENT-REPLAY.json): the named RTL-only result, with all 196 connected primary assertions and 194 secondary conclusions; CRC conclusions 38 and 73 remain unresolved. The 35/57/63/94 components and separate 42-assertion bank scope overlap and must not be added.
- [Browser status](current-browser.json): twelve Chrome cases and 100 exact outputs, independent checks of automatic seeds, full-context generation, Stop and resumed generation. The record names its exact host-source context.

[CURRENT-QUALIFICATION.md](../../demos/simplestories-v2-5m/CURRENT-QUALIFICATION.md) also describes full-array readback, the exact payload/source comparison and recipient reload/registration. [FORMAL-STATUS.md](../../demos/simplestories-v2-5m/FORMAL-STATUS.md) states the private-service boundaries and proof limits.

From the repository root, recheck recorded evidence without hardware, solvers or numerical-model execution:

```sh
python3.12 -I -S -B tools/check_current_seeded_recorded_v1.py --require-complete
python3.12 -I -S -B formal/current-seeded-sampling/check_recorded.py --require-complete
```

The image authenticates fixed weights and has no K/V cryptographic integrity or encryption. These finite and scoped results do not establish whole-machine numerical correctness, complete vendor-DDR timing, physical security or an independently attested loaded FPGA.
