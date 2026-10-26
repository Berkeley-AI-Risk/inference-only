# H100 evidence from October 25 2026

`raw-evidence.tar.gz` is the exact final remote evidence archive. Its SHA-256 is recorded in `REMOTE-ARCHIVE.json`; `BACKUP-VERIFIED.json` records verification of all 897 payload files and an empty GPU process list. Model weights, virtual environments and compiler caches are excluded. Checksums establish saved-file integrity, not physical attestation or a certified training bound.

`SELECTED-REFERENCES.json` selects independent fresh-process repeats for fixed-context Qwen, fixed-context SimpleStories and the Qwen one-token continuation. Member paths refer to the archive, not the surrounding repository. `computed-results.json` contains reproducible rates, conditional comparisons and a manifest of all 37 benchmark outcomes. The numerical diagnostic JSON files are also available directly.

From the repository root, run `python3 -I -S -B tools/qwen_h100_results.py --check` with Python 3.11 or later. This verifies the archive SHA, every payload digest, selected source bindings, workload geometry and counter/timing arithmetic without accessing a GPU or network. The source snapshots and case arguments inside the archive are the authoritative measured versions; failures remain preserved.
