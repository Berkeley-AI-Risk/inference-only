# Reproduce the S-AWIC component prototype

Run from this variant directory. Python 3.8 or later, Verilator with timing support, and Icarus Verilog for the four-state checks are required; the captured compiled regressions use Verilator 5.050. Tests use only the Python standard library, local native model assets and C++ compilation. They do not train a model or program a board. Verilator builds use one compiler job and one simulation thread. Temporary compilation directories avoid GNU Make's restriction on spaces in directory names.

```sh
python3 tests/reference_cases.py ../..
python3 tests/run_lms_rtl.py
python3 tests/run_memory_rtl.py ../..
python3 tests/run_x.py
```

The first command regenerates test packages and published-vector checks in `evidence/generated/`. The next commands build actual RTL and preserve logs and source hashes in `evidence/rtl-lms/` and `evidence/rtl-memory/`. Large generated images, hex files and native binaries are reproducible working outputs and are excluded from the compact evidence snapshot.

The three generated packages contain the released base image, a synthetic image differing by one weight bit, and a synthetic matching image/metadata change. These are authentication fixtures, not trained fine-tunes or numerical-equivalence tests. The full-image, metadata and page checks use those distinctions deliberately. Published signature inputs are in [rfc8554-case1.json](tests/rfc8554-case1.json), with the RFC URL and document hash from which they were extracted.

The fixed public demo policy can be regenerated independently:

```sh
python3 reference/generate_policy.py
```

Changing this include changes the hardware trust policy; it is not a runtime update mechanism. Native SHA/page-bank source hashes must continue to match [native-sources.json](evidence/native-sources.json).

## Package another compatible image with demo signatures

```sh
python3 reference/signed_update.py pack-demo IMAGE.bin METADATA192.memh OUTPUT.swic \
  --version 3 --signer-state demo-signer-state.json
python3 reference/signed_update.py verify-demo OUTPUT.swic
```

The CLI uses public demonstration signing material. Preserve the signer state between invocations; deleting or restoring it can reuse one-time leaves. These keys/state files provide no production authorization security. Existing output packages are not overwritten. The reference verifies exact lengths, all signatures, the commitment, image hash and every page digest before reporting success.

## Complete Tang target

Use [tang/REPRODUCE.md](tang/REPRODUCE.md) to regenerate complete-model fixtures, run fast and pin-level SPI token-machine simulations, build the native Tang target and prepare its fixed-layout flash data. The component commands above exercise a narrower single-clock fixture. Its public compact snapshot is under `evidence/component-snapshot/`; the validation document describes path redaction and preservation of the original captures.
