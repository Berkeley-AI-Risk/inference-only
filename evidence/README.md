# Evidence guide

The current SimpleStories images, numerical model, source inventories and qualification scopes are described in [greedy qualification](../demos/simplestories-v2-5m/GREEDY-QUALIFICATION.md) and [seeded qualification](../demos/simplestories-v2-5m/CURRENT-QUALIFICATION.md). Qwen3-1.7B and Qwen3-8B have their own evidence within their [model directories](../demos/).

## Greedy SimpleStories

`current-greedy/INDEX.json` selects the baseline, K/V-protected and encrypted-memory capsules, actual role ledger, shared host and minimal support-source context. The portable objects retain the exact recorded model/native observations, scoped proof queries, source associations, mapped observations, raw CLI frames, browser downloads and UI/backend observations. The current checker replays those bytes and their cross-associations; it does not rerun hardware, a numerical model or a solver.

```sh
python3.12 -I -B tools/check_current_three_greedy_v15_v4.py --package . --stage current --index evidence/current-greedy/INDEX.json
```

Each selected image passed ten CLI cases and seven browser cases. The [common speed captures](../benchmarks/fpga-speed/) separately contain the two full 128-output trials for each selected image. Their validated-reply timestamps, command durations and all generated/reference IDs support the common benchmark calculation.

The baseline's [analysis inputs](current-greedy/baseline/analysis/) bind its fixed-context measurements, native resources and complete mapped multiplier census to the conditional [capacity assessment](../demos/simplestories-v2-5m/TRAINING-CAPACITY.md). They do not demonstrate usable attacker access or certify a training factor.

## Seeded SimpleStories

[The seeded evidence guide](seeded-sampling/README.md) links the selected d271 image's model, seven-suite CLI campaign, context matrix, formal completion, readback and browser records. These use their exact recorded host/source contexts. Shared greedy-host fixture results do not grant a fresh seeded browser campaign.

## Interpretation

Raw records apply only to the source, image and workload identities they name. Supporting source and component records preserve the inputs needed for scoped checks; they do not add another runnable design or transfer a result to a changed image. Assertion counts overlap. Read [formal status](../demos/simplestories-v2-5m/FORMAL-STATUS.md) for the private-service cuts and unresolved conclusions.

All selected Tang images retain incomplete vendor-DDR timing signoff. Native route/resource observations, finite correct outputs and file hashes do not establish whole-machine refinement, cryptographic security, physical security or independent attestation of the loaded FPGA. [Release integrity](../demos/simplestories-v2-5m/REPRODUCE.md) is a separate byte check.
