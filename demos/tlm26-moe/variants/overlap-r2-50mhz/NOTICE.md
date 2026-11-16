# Notice and provenance

Copyright 2026 Wes Holliday. The project-owned clock-delivery adaptation, source overlay, verifier, K/V regression harness and documentation fall within the repository's existing [Apache-2.0 scope](../../../../LICENSE-SCOPE.md). Retain the root [LICENSE](../../../../LICENSE), [NOTICE](../../../../NOTICE), and [TLM26 dependency notices](../../NOTICES.md). This addition does not relicense third-party material.

The unchanged checkpoint is `h1matthew/tlm26` revision `804c2137003ede3820fc57608221deb620c2d6d7`, whose pinned model card declares MIT. The original source/tokenizer provenance is `ANRGUSC/tlm26` revision `967a9270ff81220421e062393ae56babe6152888`; retain its existing [MIT notice](../../metadata/upstream-LICENSE.txt). The model-derived reference IDs retain that provenance. Existing Fable SHA-compressor attribution remains applicable; the compressor is unchanged.

The exact source delta contains project-owned board wrappers and timing constraints, identified by before/after native-input hashes. It includes no vendor primitive definitions, library, DDR implementation, netlist, tool, model/checkpoint/tokenizer image or FPGA configuration. Original dependencies and their notices remain separate. Hashes identify inputs; they grant no redistribution rights.

Saved physical UART trial bytes remain unchanged. Portable canonical identities remove local UART/serial identifiers and replace custody paths with package-relative references. Compressed programmer transcripts preserve exact uncompressed bytes and digests. These are historical measurements, not current device custody or programming permission. No personal path, local approval record or credential is included.

The 1.612, 3.097 and 9.078 measurements remain distinct images and captures. The K/V review adds finite local simulation evidence with unchanged production RTL; its stated limits remain part of the result. This package retains the existing licensing scope and attributions.
