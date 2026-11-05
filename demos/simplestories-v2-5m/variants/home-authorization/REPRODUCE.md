# Reproduction and evidence checks

Run from this directory with Python 3.10+. `DEMO` is the absolute enclosing `demos/simplestories-v2-5m` directory and `WORK` is a fresh directory outside the repository. Software tests need only the standard library. Full model fixture generation additionally needs NumPy. RTL compilation uses Verilator and a C++ compiler with one compilation job.

## Software and component checks

```sh
S_AWIC_DEMO_ROOT="$DEMO" python3 -I -B tests/test_home_auth.py
python3 -I -B tests/test_serial_client.py
python3 -I -B reference/demo.py --demo-root "$DEMO" --output "$WORK/software-demo"
python3 -I -B tests/run_rtl.py --output "$WORK/controller"
python3 -I -B integration/check_reproduction.py --output "$WORK/overlay-check"
```

The software demonstration verifies two signed model packages and home-policy revocation/replacement with a controlled software clock. It does not run numerical tokens. Component RTL uses real LMS/SHA but supplied verified roots and deterministic nonces. The component source is a baseline gate; the selected physical controller includes the source-bound composition changes exercised below.

## Complete composition simulation

Generate the signed-update fixtures in a fresh directory:

```sh
python3 -I -B ../signed-update/tang/tests/make_fixtures.py "$DEMO" --output "$WORK/fixtures"
python3 -I -B integration/build_sim.py --output "$WORK/full" --fixtures "$WORK/fixtures" \
  --share-message-selector --registered-permit --share-boot-compressor \
  --direct-publication-guard --registered-nonce-data --compact-norm-loader \
  --narrow-norm-carry --registered-metadata-collision --resetless-sha-data \
  --registered-verifier-reset --phase-qualified-startup-reset --qspi-core-reset-buffers 2
python3 -I -B integration/run_sim.py --build "$WORK/full" --scenario 0
python3 -I -B integration/run_sim.py --build "$WORK/full" --scenario 1
python3 -I -B integration/run_sim.py --build "$WORK/full" --scenario 2
python3 -I -B integration/run_sim.py --build "$WORK/full" --scenario 3
```

The scenarios cover valid renewal/context preservation, wrong-model rejection, expiry during inference and a corrupt renewal signature. The flash source/DDR PHY are explicit models and raw entropy bytes are deterministic stimuli; model admission, signatures, nonce conditioning and inference arithmetic remain RTL. No five-minute wall-clock cutoff is imposed.

## Native source and offline board audit

```sh
python3 -I -B tools/check_evidence.py
python3 -I -B tools/build_native.py --ide "$GOWIN_IDE" --vendor-dir "$VENDOR_INPUTS" \
  --dependency-manifest "$DEMO/VENDOR-DEPENDENCIES.json" --output "$WORK/native"
```

The first command independently rechecks stored token CRCs, the model/reference binding, unique nonces and signing leaves, real LMS grants, renewal/replay/revocation observations, paired timing and restoration. It checks exact hardware input and prebuilt hashes. It accesses no board or network. Redacted capture hash mappings are preserved in `evidence/PUBLIC-COPIES.json`.

The build command requires the pinned Education compiler and the four separately acquired vendor DDR/PLL inputs. It verifies tool and input hashes, copies the frozen composition and runs synthesis/place-and-route without accessing hardware. Rebuilt outputs need their own mapping/timing review; bit-identical implementation is not promised. Complete DDR timing, analog metastability, entropy and production security remain open.

## Common speed measurement

Create the independent base-model reference using `../signed-update/tang/tools/common_speed_reference.py` with `--demo "$DEMO" --image "$DEMO/assets/board1-real-semantic-image2048.bin" --output "$WORK/reference.json"`. Follow [INSTALL.md](INSTALL.md), substituting `--reference "$WORK/reference.json"` for `--smoke` in the relay command. Start the relay before SRAM loading. It collects `[378]`, 128 greedy outputs twice, validates every returned ID and records raw frames and validated-return timestamps. It includes renewal and host handover gaps, excludes output one from the cached metric and never retries commands. Preserve separate successful programmer, model-data/readback and source identity receipts before selecting any new headline result.

The published record is `evidence/board-25mhz-v9/COMMON-SPEED.json`; its two raw trial files, reference, collector and complete campaign audit accompany it. The repository's common benchmark checker admits the row only after the offline audit passes.

## Reset sequencing checks

With the vendor primitive simulation library acquired locally, run:

```sh
python3 -I -B integration/test_startup_reset.py --qualified \
  --vendor-primitives "$VENDOR_PRIMITIVES" --output "$WORK/startup-reset"
python3 -I -B integration/test_qspi_phase_reset.py --project hardware/project \
  --identity-buffers 2 --vendor-primitives "$VENDOR_PRIMITIVES" --output "$WORK/flash-reset"
```

`VENDOR_PRIMITIVES` is the vendor's `simlib/gw5a/prim_sim.v`. The recorded receipts identify their model files; another library requires its own result. The flash-reset simulation uses the actual vendor LUT model. Its binary sequencing proof uses the documented LUT truth function. These digital checks do not quantify analog metastability or physical source entropy.
