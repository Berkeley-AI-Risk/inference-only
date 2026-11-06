# Boot page consistency: component verification

The boot checker compares every signed page digest with the same ordered
readback stream consumed by the whole-image and fixed-function-table checks.
It uses the runtime page bank's zero padding for the last page. Both Tang
variants contain the identical page checker and three-client compressor mux.

Two component jobs pass base checking and temporal induction:

- **Page accounting:** verification requires all 7,265,984 input bytes and all
  1,774 successful page verdicts. Page addresses remain in range, the final-page
  input length and zero-tail region are distinguished, reset closes permission,
  and failure remains closed. A mismatching page verdict cannot grant verification.
- **Compressor ownership:** acceptance and completion are exclusive. There is
  one outstanding operation, and completion is routed to its accepted owner.

These are binary clocked controller results. `page_sha_contract.sv` explicitly
abstracts the hash children: a page hash completes after a full page has been
accepted, and the compressor completes an outstanding accepted operation. Digest
values are arbitrary. The jobs do not prove SHA-256, signature security, progress
under perpetual stalls, physical memory behavior or a whole-machine theorem.

Ordinary unit fixtures independently compare the actual SHA RTL with Python
`hashlib`: two exact 64-byte pages, a three-page 4 KiB case with an 11-byte tail,
and the complete 1,774-page geometry with a 3,776-byte tail. The same bytes feed
page, whole-stream and suffix hashing through the actual shared compressor.
The tests check digest order/counts, reset during input, retained completion and
input stalls. They use synthetic bytes and no signatures or DDR interface.

## Reproduction

Use Python 3.10+, Yosys with `yosys-smtbmc`, cvc5, Verilator with timing support,
GNU Make and a C++ compiler. Run from this directory; `WORK` is a fresh directory
outside the repository. Builds use one compilation job and one simulation thread.

```sh
python3 -I -B check_recorded.py
python3 -I -B run_proofs.py --output "$WORK/page-proof"
python3 -I -B run_proofs.py --job compressor --output "$WORK/compressor-proof"
python3 -I -B ../../tests/run_page_consistency.py \
  --output "$WORK/page-unit" --full-geometry
```

The recorded checker checks file/source identities, generated proof designs,
recipes, logs and deterministic unit-fixture hashes. It does not execute a
solver or simulation. Fresh commands execute the engines. Proof artifacts and
unit run logs are retained in `records/`; `PACKAGE.json` binds their bytes.
Build directories and large regenerable hex stimuli are omitted. Native routed
implementation and board qualification are separate obligations.
