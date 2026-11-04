# SWIC component validation

Captured November 3, 2026. These results concern the single-clock memory-admission component. They do not establish complete model execution, timing/resource closure, physical security or a residual training bound. See [FORMAL-STATUS.md](FORMAL-STATUS.md).

| Campaign | Result and scope | Compact evidence |
| --- | --- | --- |
| Python reference | 25 cases pass: three compatible image/metadata fixtures, altered-package rejection, valid signed rollback, all 1,774 native page digests, and demo signer reservation/corrupt-state behavior | [Results](evidence/generated/reference-results.json) |
| RTL LMS verifier | 17 cases pass: eight valid signatures and nine negative cases, including both published RFC 8554 Test Case 1 LMS layers | [Result and source/input hashes](evidence/rtl-lms/result.json), [log](evidence/rtl-lms/run.log) |
| Connected RTL memory path | 26 boot cases pass: six valid authority/package combinations and 20 rejected cases; real LMS/SHA computation throughout | [Result and source/input hashes](evidence/rtl-memory/result.json), [log](evidence/rtl-memory/run.log) |
| Four-state simulation | Six directed unknown-input cases fail closed in boot-frame and DDR-readback seams | [Result](evidence/four-state/result.json), [log](evidence/four-state/run.log) |

The connected regression also performs five complete 7,265,984-byte DDR readbacks: four accepted and one deliberately corrupted. It checks both sets of all 2,328 sealed metadata words, including an approved metadata change. Four valid page transactions include the changed weight page, changed metadata page and short final page; an additional corrupted page is rejected by the native bank. The short page has 118 real words and a zero-filled tail.

Further directed cases check response stability under backpressure, read cancellation without reopening admission, rejection of out-of-range page/metadata reads, extra boot traffic after admission, and reset during frame loading, cryptographic verification and after admission. Monitors reject early model readiness or unverified page output. The four-state guards are simulation checks; they are not physical fault-injection countermeasures.

The three signed packages are the released model, a one-bit weight mutation, and a matching image/projection-metadata mutation. **The changed fixtures are not trained fine-tunes.** No token-generation or full numerical-model acceptance is claimed for them. The purpose is to demonstrate that model-dependent authenticated data can change while unsigned changes are rejected.

Verilator lint of the connected RTL passes without warning suppression. The compiled campaigns use one build job and one simulation thread each; captured simulation allocation is approximately 2 MB for LMS and 10 MB for the connected path. These are simulator figures, not FPGA resource estimates. Compilation and asset-generation memory are additional.

The input and source hashes bind each compiled campaign. Large regenerable packages, image/hex stimuli and build binaries are omitted from the compact snapshot. [REPRODUCE.md](REPRODUCE.md) recreates them from the local native image and published-vector fixture. The original SHA/page-bank identities are recorded in [native-sources.json](evidence/native-sources.json); the complete compact snapshot is bound by [SNAPSHOT.json](evidence/SNAPSHOT.json).
