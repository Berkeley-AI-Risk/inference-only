# Physical model-replacement evidence

This campaign uses the published 25 MHz periodic-reauthorization image. A is
the base model. B is a signed synthetic replacement with 320 changed final
normalization bytes. Both retain the fixed architecture and arithmetic tables.

`EVENTS.jsonl` retains raw UART receive/transmit chunks, valid approvals,
the same-nonce/wrong-model negative fixture, policy changes and replay tests.
The signed prefixes reconstruct both complete packages from the enclosing
demo's public base image. The portable checker derives the two programmed
blocks, verifies their identities, and checks the trace and observations.

`EVIDENCE-AUDIT.json` and `AUDIT-NEGATIVE-CONTROLS.json` record the local audit
that also read the complete private flash captures. Those complete arrays,
backups and live signer state are omitted. The public replay checks their
recorded receipts and hashes; it does not repeat a private-array comparison
unless `--private-workspace` is explicitly supplied with the original captures.

The recorded runner and private-auditor sources document the captured
experiment; their machine paths are redacted and they are not portable entry
points. Use `../../tools/check_model_replacement.py` for public offline replay
and the variant's reproduction guide for the physical sequence.

Generation with B succeeds across renewal. Its constant-zero outputs cannot
independently distinguish preserved context from a context reset; the base
model's separate campaign supplies the observable context-preservation check.
The two final restarts are SRAM reconfigurations, not electrical power cycles.
Public demo keys and this finite test do not qualify entropy, clock/power
tamper resistance or whole-machine inference-only behavior.
