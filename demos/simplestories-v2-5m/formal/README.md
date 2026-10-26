# SimpleStories RTL verification

The [formal-status guide](../FORMAL-STATUS.md) states the properties established
for the selected designs and their implementation boundaries.

The verification directories contain source-bound proof bundles and their
recorded queries, results and supporting sources. These recorded bundles retain
their original bytes, including path text in their source READMEs and receipts.
They do not supply additional runnable hardware designs.

Run the model-specific commands from `demos/simplestories-v2-5m/` in the
repository. For example, the registered seeded proof completion is checked with:

```sh
python3.12 -I -S -B formal/current-seeded-sampling/check_recorded.py --require-complete
```

The whole-repository integrity and common benchmark checks remain at the
repository root. New solver runs and hardware qualification are distinct from
replaying these recorded results.

The current [implementation-assurance checks](implementation-assurance/README.md) cover the boot/runtime handoff, fixed-length boot controller, QSPI reader, real FIFOs and transport, and the greedy public controllers. Their source-bound component results and remaining composition limits are stated together.
