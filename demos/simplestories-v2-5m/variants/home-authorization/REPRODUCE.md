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

## Model-replacement evidence

Replay the public observations and adversarial controls without a board:

```sh
python3 -I -S -B tools/check_model_replacement.py
python3 -I -S -B tests/test_model_replacement_evidence.py
```

The checker reconstructs complete signed A/B packages from their recorded signed prefixes and the enclosing demo's public base image. B sets the 320 final-normalization bytes at image offset `214250*32` to zero. Signatures, model commitments, fixed tables, metadata and both programmed block hashes are verified. Raw receive/transmit chunks are parsed independently, including real home signatures, model/nonce bindings, CRCs, denial/replay cases and the grant-settling interval. The controls rebind capture hashes before testing the semantic checks.

With NumPy installed, recompute both 128-output references and both two-output smoke cases:

```sh
python3 -I -B tools/check_model_replacement.py --recompute-reference
```

Complete flash arrays and backups are private. Default replay checks their recorded receipts and hashes. An owner with the original private workspace can add `--private-workspace "$PRIVATE_WORKSPACE"` to compare the complete backup, candidate and post-install array bytes. That option reads private files locally and does not publish them.

To reconstruct the deliberately public, already-signed test packages in a fresh workspace:

```sh
python3 -I -S -B tools/reconstruct_replacement_models.py --output "$WORK/replacement-models"
```

For a physical repetition, use [INSTALL.md](INSTALL.md) and the [signed-update preserving-flash workflow](../signed-update/tang/REPRODUCE.md#offline-flash-data-and-board-qualification). Detect the exact board, preserve two independently initiated matching complete backups plus a durable copy, and validate complete candidates before writing. The recorded A/B transition changes only the complete 64 KiB blocks at `0xe80000` and `0xf00000`; reconstruct a preserving candidate from the actual board's backups rather than assuming its other bytes match another board.

1. Install A, allow only A at home base, and check `[1]` → `[108,32]` plus the first 32 `[378]` reference outputs.
2. Remove A and allow only B. Observe A's denied renewal and verify that inference stops.
3. Install signed B and independently read back the complete array. With B withheld, verify no inference output. The recorded negative fixture signs an A request with B's actual fresh nonce/device; that valid wrong-model approval must remain unusable.
4. Allow B, start a fresh session, and check `[1]` → `[0,0]` and the first 32 B reference outputs, with fresh approval between outputs 16 and 17.
5. Reinstall A while only B remains allowlisted. Independently verify its complete array, confirm denial after two SRAM configurations, and replay the captured A approval against the fresh challenge.
6. Restore the exact starting array and original SRAM image, then verify the baseline and CLEAR. Retain every partial/failure capture and restore through the reviewed recovery path on failure.

The [captured runner](evidence/model-replacement-v2/RUNNER.py), programmer/readback receipts and raw trace specify the recorded sequence. Its machine paths are redacted; it is not a portable programming command. Keep UART access exclusive, pace grants in 16-byte chunks with 3 ms gaps, and wait 0.5 seconds **after the complete grant transmission** before sending application commands. No electrical power-cycle test, entropy qualification, update-rate limiter or automatic remote installer is implied.

## Reset sequencing checks

With the vendor primitive simulation library acquired locally, run:

```sh
python3 -I -B integration/test_startup_reset.py --qualified \
  --vendor-primitives "$VENDOR_PRIMITIVES" --output "$WORK/startup-reset"
python3 -I -B integration/test_qspi_phase_reset.py --project hardware/project \
  --identity-buffers 2 --vendor-primitives "$VENDOR_PRIMITIVES" --output "$WORK/flash-reset"
```

`VENDOR_PRIMITIVES` is the vendor's `simlib/gw5a/prim_sim.v`. The recorded receipts identify their model files; another library requires its own result. The flash-reset simulation uses the actual vendor LUT model. Its binary sequencing proof uses the documented LUT truth function. These digital checks do not quantify analog metastability or physical source entropy.
